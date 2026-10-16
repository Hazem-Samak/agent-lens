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

    /// The M6 metadata cache location. Injected so tests never touch the real app cache.
    public let updateCacheURL: URL

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
        updateCacheURL: URL,
        currentDirectory: String = FileManager.default.currentDirectoryPath,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.environment = environment
        self.registry = registry
        self.scanner = scanner
        self.updateRunner = updateRunner
        self.updateCacheURL = updateCacheURL
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
            InventoryEntry(definition: definition, diagnostic: diagnostic, update: nil)
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
        let subjects = snapshot.entries.map { entry in
            UpdateProbeSubject(
                registryID: entry.registryID,
                displayName: entry.definition.displayName,
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
            now: clock
        )
        let resultByRegistryID = Dictionary(
            results.map { ($0.registryID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let entries = snapshot.entries.map { entry in
            InventoryEntry(
                definition: entry.definition,
                diagnostic: entry.diagnostic,
                update: resultByRegistryID[entry.registryID]
            )
        }
        return InventorySnapshot(
            entries: entries,
            isDegradedEnvironment: snapshot.isDegradedEnvironment
        )
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