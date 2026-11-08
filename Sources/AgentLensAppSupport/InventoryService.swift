// InventoryService — the typed app boundary between AgentLensCore and the SwiftUI window.
// Implements M7 brief §"Proposed architecture and state contract".
//
// The service owns the M0–M6 machinery the window must not re-implement: the validated detector
// registry (D-010/D-017), the session login-shell environment (D-005), the M5 PATH diagnostic, and
// the M6 update coordinator with its cache policy. It produces immutable `InventorySnapshot` values
// and never presentation text: the GUI does not launch the CLI or parse its renderer.
//
// Association rule: every snapshot entry keeps the definition that produced it, so the stable
// registry ID travels with the M5 diagnostic and the M6 update result. Nothing is associated by
// display name, executable basename, or completion order, and nothing is zipped after filtering.
//
// Blocking work: `PathDiagnosticsScanner.scan` performs real filesystem stats and a bounded
// `--version` query, so scans run on a utility queue behind a checked continuation — never on an
// inherited main-actor task. Cancellation is checked between bounded per-tool scans, and a scan
// that is cancelled publishes nothing.
//
// Environment: every process receives `ShellEnvironment.raw` from the session provider. Nothing in
// this file reads `ProcessInfo` PATH or `$SHELL`, and no environment value is logged or persisted.

import AgentLensCore
import Dispatch
import Foundation

public struct UpdateExecutionResult: Sendable {
    public let outcome: OperationOutcome
    public let snapshot: InventorySnapshot?

    public init(outcome: OperationOutcome, snapshot: InventorySnapshot?) {
        self.outcome = outcome
        self.snapshot = snapshot
    }
}

public struct UninstallExecutionResult: Sendable {
    public let outcome: NpmUninstallOutcome
    public let snapshot: InventorySnapshot?

    public init(outcome: NpmUninstallOutcome, snapshot: InventorySnapshot?) {
        self.outcome = outcome
        self.snapshot = snapshot
    }
}

private final class OperationSnapshotBox: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: InventorySnapshot?
    func store(_ value: InventorySnapshot) { lock.lock(); snapshot = value; lock.unlock() }
    func take() -> InventorySnapshot? { lock.lock(); defer { lock.unlock() }; let value = snapshot; snapshot = nil; return value }
}

public struct InventoryService: Sendable {

    /// The registry loader seam. Production is Core's bundled-resource loader; tests validate
    /// synthetic JSON through Core's own validator, so no test depends on the resource.
    public typealias RegistryLoader = @Sendable () throws -> [DetectorDefinition]

    /// The M5 diagnostic scanner seam. Production is `PathDiagnosticsScanner.scan`.
    public typealias DiagnosticScanner =
        @Sendable (ToolDetector, ShellEnvironment, String) -> ToolPathDiagnostic

    /// The app-session environment (D-005).
    public let environment: SessionEnvironmentProvider

    public let registry: RegistryLoader
    public let scanner: DiagnosticScanner
    public let updateRunner: UpdateCommandRunner

    /// Operation-specific process and mutation-gate seams. Production uses the process-wide gate;
    /// tests and the controlled native host inject independent values.
    public let operationRunner: OperationCommandRunner
    public let operationGate: OperationExecutionGate
    public let operationRootBaseURL: URL?

    /// The M6 metadata cache location. Injected so tests never touch the real app cache.
    public let updateCacheURL: URL

    /// The M10-B npm scratch base. `nil` (production) makes the npm probe use Foundation's
    /// `temporaryDirectory`; tests and the controlled native host inject an owned root so no real
    /// cache/log/install path is ever touched.
    public let npmScratchBaseURL: URL?

    /// The working directory relative PATH entries resolve against, fixed for the app session.
    public let currentDirectory: String

    public let clock: @Sendable () -> Date

    public init(
        environment: SessionEnvironmentProvider,
        registry: @escaping RegistryLoader = { try DetectorRegistry.loadDefault() },
        scanner: @escaping DiagnosticScanner = { detector, environment, currentDirectory in
            PathDiagnosticsScanner.scan(
                detector: detector,
                environment: environment,
                currentDirectory: currentDirectory
            )
        },
        updateRunner: UpdateCommandRunner = ProcessUpdateCommandRunner(),
        operationRunner: OperationCommandRunner = ProcessOperationCommandRunner(),
        operationGate: OperationExecutionGate = OperationExecutionGate.shared,
        operationRootBaseURL: URL? = nil,
        updateCacheURL: URL,
        npmScratchBaseURL: URL? = nil,
        currentDirectory: String = FileManager.default.currentDirectoryPath,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.environment = environment
        self.registry = registry
        self.scanner = scanner
        self.updateRunner = updateRunner
        self.operationRunner = operationRunner
        self.operationGate = operationGate
        self.operationRootBaseURL = operationRootBaseURL ?? npmScratchBaseURL
        self.updateCacheURL = updateCacheURL
        self.npmScratchBaseURL = npmScratchBaseURL
        self.currentDirectory = currentDirectory
        self.clock = clock
    }

    // MARK: Local inventory

    /// The complete local inventory, using the current session environment.
    public func localSnapshot() async throws -> InventorySnapshot {
        let environment = await environment.sessionEnvironment()
        return try await Self.scanAll(
            environment: environment,
            registry: registry,
            scanner: scanner,
            currentDirectory: currentDirectory
        )
    }

    /// Explicit rescan: a fresh login-shell capture, then a fresh local inventory from it.
    public func refreshedLocalSnapshot() async throws -> InventorySnapshot {
        let environment = await environment.rescanEnvironment()
        return try await Self.scanAll(
            environment: environment,
            registry: registry,
            scanner: scanner,
            currentDirectory: currentDirectory
        )
    }

    /// Scans every registry definition in registry order, off the caller's executor.
    ///
    /// The registry is validated and the definitions are frozen BEFORE any scan, so a definition can
    /// never be paired with another tool's diagnostic and the registry ID travels with its own
    /// facts. Every definition is scanned, including ones that will be filtered out of the UI;
    /// missing tools stay in the snapshot as typed `notInstalled` facts.
    ///
    /// Caller cancellation arrives as a Swift task, but the scan body runs inside a GCD utility
    /// closure that carries no Swift task context, so `Task.isCancelled` read there would always be
    /// false. The boundary therefore converts the caller's cancellation into an explicit signal:
    /// the handler records it in a thread-safe flag that the offloaded loop re-reads before each
    /// bounded tool scan and before computing a result. Cancellation thus takes effect at the next
    /// scan boundary, the in-flight bounded scan is awaited to completion on the same utility queue
    /// (its process work never overlaps the next pipeline), and the call then throws
    /// `CancellationError` instead of returning a partial snapshot.
    private static func scanAll(
        environment: ShellEnvironment,
        registry: RegistryLoader,
        scanner: @escaping DiagnosticScanner,
        currentDirectory: String
    ) async throws -> InventorySnapshot {
        let definitions = try registry()
        let currentDirectory = currentDirectory
        // An already-cancelled caller performs no tool scan at all. This is the caller's task, so
        // `Task.isCancelled` is authoritative here — unlike inside the offloaded closure below.
        if Task.isCancelled { throw CancellationError() }
        let cancellation = ScanCancellationFlag()
        let scanned = await withTaskCancellationHandler {
            await offUtilityQueue { () -> [ToolPathDiagnostic]? in
                var diagnostics: [ToolPathDiagnostic] = []
                diagnostics.reserveCapacity(definitions.count)
                for definition in definitions {
                    if cancellation.isCancelled { break }
                    diagnostics.append(
                        scanner(definition.makeDetector(), environment, currentDirectory)
                    )
                }
                guard !cancellation.isCancelled else { return nil }
                return diagnostics
            }
        } onCancel: {
            cancellation.cancel()
        }
        guard let scanned else {
            throw CancellationError()
        }
        let entries = zip(definitions, scanned).map { definition, diagnostic in
            InventoryEntry(
                definition: definition,
                diagnostic: diagnostic,
                update: nil,
                ownership: nil
            )
        }
        return InventorySnapshot(
            entries: entries,
            isDegradedEnvironment: environment.isDegraded
        )
    }

    // MARK: Updates

    /// Runs the M6 update probe for one published local snapshot and returns the same entries with
    /// typed update outcomes attached by registry ID.
    ///
    /// The local snapshot is never rebuilt here: callers publish local facts first and hand the
    /// already-published snapshot in, so an update outcome can only be attached to the exact facts
    /// it was computed from. The probe reads the SESSION environment, so a caller that wants a fresh
    /// environment calls `refreshedLocalSnapshot()` first and then probes — Check and Refresh both
    /// reuse the session environment rather than resolving a new one (M7 brief).
    ///
    /// `localOnly` and `offline` keep M6's zero-manager/zero-cache guarantee.
    public func applyingUpdates(
        to snapshot: InventorySnapshot,
        mode: UpdateProbeMode
    ) async -> InventorySnapshot {
        let probeEnvironment = await environment.sessionEnvironment()
        // Production nil intentionally reaches the probe's Foundation `temporaryDirectory`
        // fallback (M10-B B04). A captured login-shell TMPDIR is used only by the explicit
        // operation paths, which compute and validate their own owned root before any launch.
        let scratchBase = npmScratchBaseURL
        let subjects = snapshot.entries.map { entry in
            UpdateProbeSubject(
                definition: entry.definition,
                diagnostic: entry.diagnostic
            )
        }
        let results = await UpdateProbeCoordinator.run(
            subjects: subjects,
            environment: probeEnvironment,
            mode: mode,
            runner: updateRunner,
            cacheURL: updateCacheURL,
            currentDirectory: currentDirectory,
            now: clock,
            npmScratchBaseURL: scratchBase
        )
        let resultByRegistryID = Dictionary(
            results.map { ($0.registryID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let entries = snapshot.entries.map { entry in
            InventoryEntry(
                definition: entry.definition,
                diagnostic: entry.diagnostic,
                update: resultByRegistryID[entry.registryID],
                ownership: entry.ownership
            )
        }
        return InventorySnapshot(
            entries: entries,
            isDegradedEnvironment: snapshot.isDegradedEnvironment
        )
    }

    // MARK: Ownership

    /// Explicit, read-only ownership verification for one published entry. The verification uses
    /// the session environment, the existing injected runner, the fixed session working directory
    /// and the service clock, exactly as the rest of the app boundary does. It never scans tools,
    /// consults the update cache, or runs an update batch.
    ///
    /// The Core verifier runs in a detached utility task so its filesystem stats and bounded
    /// manager processes never occupy the main actor. Cancelling the caller cancels that task and
    /// then awaits it, so bounded in-flight cleanup finishes before this call returns. Core maps
    /// cancellation to a neutral `.cancelled` result; it never publishes a late verified value.
    public func verifyingOwnership(of entry: InventoryEntry) async -> InstallationOwnershipResult {
        let definition = entry.definition
        let diagnostic = entry.diagnostic
        let environment = await environment.sessionEnvironment()
        let runner = updateRunner
        let currentDirectory = currentDirectory
        let clock = clock
        let task = Task.detached(priority: .utility) {
            await InstallationOwnershipVerifier.verify(
                definition: definition,
                diagnostic: diagnostic,
                environment: environment,
                runner: runner,
                currentDirectory: currentDirectory,
                now: clock
            )
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    // MARK: Update operation

    /// Freshly prepares one selected npm update. The service resolves the session environment
    /// once and runs the blocking inventory/ownership work off the caller's executor.
    public func prepareUpdate(for entry: InventoryEntry) async -> NpmUpdatePrepareResult {
        guard case .updateAvailable = entry.updateStatus,
              entry.update?.npmPackage != nil
        else { return .unavailable(.notUpdateAvailable) }
        guard let clickedPair = Self.selectedPair(entry.diagnostic) else {
            return .unavailable(.noVerifiedSelection)
        }
        let environment = await environment.sessionEnvironment()
        let registry = self.registry
        let scanner = self.scanner
        let runner = updateRunner
        let currentDirectory = currentDirectory
        let rootBase = operationRootBaseURL
        let registryID = entry.registryID
        let task = Task.detached(priority: .utility) {
            // C01.2: a fresh local inventory from the already-captured session environment must
            // still identify the exact clicked registry entry and canonical target. A changed
            // selection refuses; it never silently retargets the fresh winner.
            let fresh: InventorySnapshot
            do {
                fresh = try await Self.scanAll(
                    environment: environment,
                    registry: registry,
                    scanner: scanner,
                    currentDirectory: currentDirectory
                )
            } catch {
                return NpmUpdatePrepareResult.unavailable(
                    Task.isCancelled ? .cancelled : .probeFailed
                )
            }
            guard !Task.isCancelled else { return .unavailable(.cancelled) }
            guard let freshEntry = fresh.entries.first(where: { $0.registryID == registryID }),
                  let freshPair = Self.selectedPair(freshEntry.diagnostic),
                  freshPair.entry == clickedPair.entry,
                  freshPair.target == clickedPair.target
            else { return .unavailable(.identityUnverified) }
            return await NpmUpdateOperation.prepare(
                definition: freshEntry.definition,
                diagnostic: freshEntry.diagnostic,
                environment: environment,
                currentDirectory: currentDirectory,
                runner: runner,
                operationRootBaseURL: rootBase,
                uptime: { DispatchTime.now().uptimeNanoseconds }
            )
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private static func selectedPair(_ diagnostic: ToolPathDiagnostic) -> (entry: String, target: String)? {
        let candidate: PathCandidateObservation
        switch diagnostic.selection {
        case .winner(let value): candidate = value
        case .offPath(let value, _): candidate = value
        case .notInstalled, .inconsistent: return nil
        }
        guard let target = candidate.canonicalTarget, !target.isEmpty else { return nil }
        return (candidate.entryPath, target)
    }

    /// Consumes one approved preparation. The Core operation performs all revalidation and the
    /// single mutation; this service then refreshes the local inventory for presentation.
    public func executeUpdate(_ preparation: NpmUpdatePreparation) async -> UpdateExecutionResult {
        let environment = await environment.sessionEnvironment()
        let scanner = self.scanner
        let runner = updateRunner
        let operationRunner = self.operationRunner
        let gate = operationGate
        let snapshotBox = OperationSnapshotBox()
        let service = self
        let task = Task.detached(priority: .utility) {
            // This closure is called by Core only after a process actually launched. It performs
            // one fresh login-shell/local rescan independently of the caller's cancellation and
            // supplies the fresh environment to Core's ownership/version reconciliation.
            let reconcileAfterLaunch: @Sendable (DetectorDefinition) async -> (ToolPathDiagnostic, ShellEnvironment)? = { definition in
                let freshTask = Task.detached(priority: .utility) {
                    try? await service.refreshedLocalSnapshot()
                }
                guard let fresh = await freshTask.value,
                      let entry = fresh.entries.first(where: { $0.registryID == definition.id })
                else { return nil }
                snapshotBox.store(fresh)
                let freshEnvironment = await service.environment.sessionEnvironment()
                return (entry.diagnostic, freshEnvironment)
            }
            let outcome = await NpmUpdateOperation.execute(
                confirmed: preparation,
                environment: environment,
                scan: { definition, shellEnvironment, directory in
                    scanner(definition.makeDetector(), shellEnvironment, directory)
                },
                reconcileAfterLaunch: reconcileAfterLaunch,
                updateRunner: runner,
                operationRunner: operationRunner,
                gate: gate,
                uptime: { DispatchTime.now().uptimeNanoseconds }
            )
            return UpdateExecutionResult(outcome: outcome, snapshot: snapshotBox.take())
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Releases a pending preview without launching a process.
    @discardableResult
    public func cancelUpdate(_ preparation: NpmUpdatePreparation) -> Bool {
        NpmUpdateOperation.cancel(preparation)
    }

    // MARK: Uninstall operation

    /// Freshly prepares one selected npm uninstall. The published ownership observation gates the
    /// UI, but Core repeats full live verification; it is never treated as authority.
    public func prepareUninstall(for entry: InventoryEntry) async -> NpmUninstallPrepareResult {
        guard let published = entry.ownership?.verifiedInstallation,
              published.manager == .npm,
              let clickedPair = Self.selectedPair(entry.diagnostic),
              published.selection.entryPath == clickedPair.entry,
              published.selection.canonicalTarget == clickedPair.target
        else { return .unavailable(.identityUnverified) }
        let environment = await environment.sessionEnvironment()
        let registry = self.registry
        let scanner = self.scanner
        let runner = updateRunner
        let currentDirectory = currentDirectory
        let rootBase = operationRootBaseURL
        let registryID = entry.registryID
        let task = Task.detached(priority: .utility) {
            let fresh: InventorySnapshot
            do {
                fresh = try await Self.scanAll(
                    environment: environment,
                    registry: registry,
                    scanner: scanner,
                    currentDirectory: currentDirectory
                )
            } catch {
                return NpmUninstallPrepareResult.unavailable(
                    Task.isCancelled ? .cancelled : .probeFailed
                )
            }
            guard !Task.isCancelled else { return .unavailable(.cancelled) }
            guard let freshEntry = fresh.entries.first(where: { $0.registryID == registryID }),
                  let freshPair = Self.selectedPair(freshEntry.diagnostic),
                  freshPair.entry == clickedPair.entry,
                  freshPair.target == clickedPair.target
            else { return .unavailable(.identityUnverified) }
            return await NpmUninstallOperation.prepare(
                definition: freshEntry.definition,
                diagnostic: freshEntry.diagnostic,
                environment: environment,
                currentDirectory: currentDirectory,
                runner: runner,
                operationRootBaseURL: rootBase,
                uptime: { DispatchTime.now().uptimeNanoseconds }
            )
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Consumes one approved preparation. Core performs all revalidation and the single mutation;
    /// this service then refreshes the local inventory for presentation.
    public func executeUninstall(_ preparation: NpmUninstallPreparation) async -> UninstallExecutionResult {
        let environment = await environment.sessionEnvironment()
        let scanner = self.scanner
        let runner = updateRunner
        let operationRunner = self.operationRunner
        let gate = operationGate
        let snapshotBox = OperationSnapshotBox()
        let service = self
        let task = Task.detached(priority: .utility) {
            let reconcileAfterLaunch: @Sendable (DetectorDefinition) async -> (ToolPathDiagnostic, ShellEnvironment)? = { definition in
                let freshTask = Task.detached(priority: .utility) {
                    try? await service.refreshedLocalSnapshot()
                }
                guard let fresh = await freshTask.value,
                      let entry = fresh.entries.first(where: { $0.registryID == definition.id })
                else { return nil }
                snapshotBox.store(fresh)
                let freshEnvironment = await service.environment.sessionEnvironment()
                return (entry.diagnostic, freshEnvironment)
            }
            let outcome = await NpmUninstallOperation.execute(
                confirmed: preparation,
                environment: environment,
                scan: { definition, shellEnvironment, directory in
                    scanner(definition.makeDetector(), shellEnvironment, directory)
                },
                reconcileAfterLaunch: reconcileAfterLaunch,
                updateRunner: runner,
                operationRunner: operationRunner,
                gate: gate,
                uptime: { DispatchTime.now().uptimeNanoseconds }
            )
            return UninstallExecutionResult(outcome: outcome, snapshot: snapshotBox.take())
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Releases a pending uninstall preview without launching a process.
    @discardableResult
    public func cancelUninstall(_ preparation: NpmUninstallPreparation) -> Bool {
        NpmUninstallOperation.cancel(preparation)
    }

    // MARK: Offload

    /// The explicit cancellation signal across the offload boundary: the caller's task
    /// cancellation sets it, the offloaded scan body reads it. `NSLock`-guarded so the flag is
    /// correct regardless of which threads the handler and the utility queue run on.
    private final class ScanCancellationFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }

        func cancel() {
            lock.lock()
            cancelled = true
            lock.unlock()
        }
    }

    /// Runs blocking filesystem/process work on a utility queue. A checked continuation resumes
    /// exactly once; the caller's executor is never blocked.
    private static func offUtilityQueue<T: Sendable>(
        _ work: @escaping @Sendable () -> T
    ) async -> T {
        await withCheckedContinuation { (continuation: CheckedContinuation<T, Never>) in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: work())
            }
        }
    }
}