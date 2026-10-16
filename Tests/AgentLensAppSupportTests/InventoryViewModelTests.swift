// InventoryViewModelTests — M7 stage 3: the main-actor state contract over the accepted
// `InventoryService` (M7 brief §"Proposed architecture and state contract", stage 3).
//
// Every fixture is synthetic and immutable: a JSON registry, a closed-PATH login-shell environment,
// an injected scanner, a scripted manager runner, a fixed clock, and a test-owned cache URL in
// approved scratch. No test launches a real login shell, reads the real PATH, runs a package
// manager, or touches the real Agent Lens cache.
//
// The scratch/registry/environment/service helpers and the gated scanner seam live in
// `InventoryServiceTests.swift` (same target) and are reused here unmodified.

import AgentLensCore
import Foundation
import Testing
@testable import AgentLensAppSupport

// MARK: Fixtures for the view-model tests

/// A registry loader that answers with a scripted sequence and then fails, so one produced service
/// can prove "first action succeeds, later action fails" without a second service shape.
final class ScriptedRegistryLoader: @unchecked Sendable {
    private let lock = NSLock()
    private var attempts = 0
    private let payloads: [Data]
    private let failure: any Error

    /// `payloads` are used in order; every attempt after them throws `failure`.
    init(payloads: [Data], failure: any Error = DetectorRegistryError.duplicateId("fixture")) {
        self.payloads = payloads
        self.failure = failure
    }

    var attemptCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return attempts
    }

    func load() throws -> [DetectorDefinition] {
        lock.lock()
        let attempt = attempts
        attempts += 1
        lock.unlock()
        guard attempt < payloads.count else { throw failure }
        return try DetectorRegistry.validate(data: payloads[attempt])
    }
}

/// A main-actor counter. Nothing in the pipeline may monopolize the main actor, so a main-actor task
/// scheduled while a bounded scan is gated must still run.
@MainActor
final class MainActorHeartbeat {
    private(set) var beats = 0
    func beat() { beats += 1 }
}

/// Raised when the main actor never got a chance to run inside the watchdog window.
enum MainActorProbeTimeout: Error, Equatable {
    case heartbeatNeverObserved
}

/// Bounded watchdog: waits until the main actor has run a task, or fails with a typed reason rather
/// than polling forever.
@MainActor
func awaitMainActorHeartbeat(
    _ heartbeat: MainActorHeartbeat,
    timeout: TimeInterval = 5
) async throws {
    Task { @MainActor in heartbeat.beat() }
    let deadline = Date().addingTimeInterval(timeout)
    while heartbeat.beats == 0 {
        guard Date() < deadline else { throw MainActorProbeTimeout.heartbeatNeverObserved }
        try await Task.sleep(nanoseconds: 2_000_000)
    }
}

// MARK: Cycle A — idle and the initial local-only launch

@MainActor
@Test func idleViewModelHasNoFactsAndLaunchPublishesLocalOnlyCounts() async throws {
    let root = try appSupportScratchRoot("vm-launch")
    defer { try? FileManager.default.removeItem(at: root) }
    let bin = root.appendingPathComponent("bin", isDirectory: true)
    try writeFixtureExecutable(bin.appendingPathComponent("alpha"))
    let cacheURL = root.appendingPathComponent("absent/cache.json")
    let runner = RecordingManagerRunner(handler: forbiddenManagerHandler())
    let viewModel = InventoryViewModel(
        service: makeService(
            registryData: registryJSON([
                RegistryRow(id: "alpha-id", displayName: "Alpha", executableName: "alpha"),
                RegistryRow(id: "beta-id", displayName: "Beta", executableName: "beta"),
                RegistryRow(id: "gamma-id", displayName: "Gamma", executableName: "gamma"),
            ]),
            pathEntries: [bin.path],
            cacheURL: cacheURL,
            currentDirectory: root.path,
            runner: runner
        )
    )

    // Idle: no facts, no counts, nothing selected, not busy.
    #expect(viewModel.phase == .idle)
    #expect(viewModel.entries.isEmpty)
    #expect(viewModel.filteredEntries.isEmpty)
    #expect(viewModel.knownToolCount == 0)
    #expect(viewModel.installedToolCount == 0)
    #expect(viewModel.updateAvailableCount == 0)
    #expect(viewModel.selectedEntry == nil)
    #expect(viewModel.freshnessFailure == nil)
    #expect(viewModel.updateFailure == nil)
    #expect(!viewModel.isBusy)

    await viewModel.launch()

    // Launch is local-only: registry order is preserved, missing tools are counted as known but not
    // installed, no update probe ran, and the cache was never created.
    #expect(viewModel.phase == .ready)
    #expect(viewModel.entries.map(\.registryID) == ["alpha-id", "beta-id", "gamma-id"])
    #expect(viewModel.installStates == [.installedAndOnPath, .notInstalled, .notInstalled])
    #expect(viewModel.knownToolCount == 3)
    #expect(viewModel.installedToolCount == 1)
    #expect(viewModel.updateAvailableCount == 0)
    #expect(viewModel.entries.allSatisfy { $0.update == nil })
    // The full snapshot is never filtered, and selection defaults to a real entry.
    #expect(viewModel.filteredEntries.count == 3)
    #expect(viewModel.selectedRegistryID == "alpha-id")
    #expect(viewModel.selectedEntry?.registryID == "alpha-id")
    #expect(!viewModel.isDegradedEnvironment)
    #expect(runner.invocationCount == 0)
    #expect(cacheArtifactsAbsent(cacheURL))
    #expect(!viewModel.isBusy)
}

// MARK: Cycle A2 — launch is idempotent, cancellation reaches the owned pipeline

/// A view-model whose registry holds two tools and whose scans stop at a controlled gate: the
/// fixture the launch-idempotence and cancellation tests share. The registry never changes, so a
/// second scan is observable as a second scanner invocation rather than as new facts.
@MainActor
struct GatedViewModelFixture {
    let root: URL
    let scanner: GatedScanner
    let runner: RecordingManagerRunner
    let viewModel: InventoryViewModel

    init(_ label: String) throws {
        root = try appSupportScratchRoot(label)
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        scanner = GatedScanner()
        runner = RecordingManagerRunner(handler: forbiddenManagerHandler())
        viewModel = InventoryViewModel(
            service: makeService(
                registryData: registryJSON([
                    RegistryRow(id: "first-id", displayName: "First", executableName: "first-tool"),
                    RegistryRow(id: "second-id", displayName: "Second", executableName: "second-tool"),
                ]),
                pathEntries: [bin.path],
                cacheURL: root.appendingPathComponent("cache.json"),
                currentDirectory: root.path,
                scanner: scanner,
                runner: runner
            )
        )
    }

    /// Ends the fixture and guarantees the utility-queue worker is never left parked inside the gate.
    func cleanUp() {
        scanner.releaseFirstCall()
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor
@Test func repeatedLaunchPerformsOneRegistryAndLocalScan() async throws {
    let fixture = try GatedViewModelFixture("vm-launch-idempotent")
    defer { fixture.cleanUp() }
    let scanner = fixture.scanner
    let runner = fixture.runner

    let firstLaunch = Task { await fixture.viewModel.launch() }
    try await scanner.waitForFirstCall()
    scanner.releaseFirstCall()
    await firstLaunch.value

    #expect(fixture.viewModel.phase == .ready)
    #expect(fixture.viewModel.entries.map(\.registryID) == ["first-id", "second-id"])
    #expect(scanner.invocationCount == 2)

    // The same window launching again: the registry is not re-read, no tool is scanned a second
    // time, no manager command runs, and the published facts are untouched.
    await fixture.viewModel.launch()
    await fixture.viewModel.launch()

    #expect(fixture.viewModel.phase == .ready)
    #expect(fixture.viewModel.entries.map(\.registryID) == ["first-id", "second-id"])
    #expect(scanner.invocationCount == 2)
    #expect(runner.invocationCount == 0)
    #expect(!fixture.viewModel.isBusy)
}

@MainActor
@Test func cancellingLaunchAbandonsTheScanAndLetsALaterRescanRun() async throws {
    let fixture = try GatedViewModelFixture("vm-cancel-launch")
    defer { fixture.cleanUp() }
    let viewModel = fixture.viewModel
    let scanner = fixture.scanner
    let runner = fixture.runner

    let launch = Task { await viewModel.launch() }
    try await scanner.waitForFirstCall()
    #expect(viewModel.phase == .loadingLocal)

    // The window's `.task` is cancelled while the first bounded tool scan is inside the gate.
    launch.cancel()
    try await awaitMainActorHeartbeat(MainActorHeartbeat())

    // Nothing further was scanned while the bounded scan is still in flight: the cancellation has
    // not been allowed to publish a partial batch or an abandoned action's failure.
    #expect(scanner.invocationCount == 1)
    #expect(viewModel.entries.isEmpty)
    #expect(viewModel.freshnessFailure == nil)
    #expect(viewModel.updateFailure == nil)

    // Releasing the in-flight bounded scan lets the abandoned pipeline finish its cleanup: the
    // cancelled caller returns, the phase settles visibly, and the pipeline slot is free again.
    scanner.releaseFirstCall()
    await launch.value

    #expect(scanner.invocationCount == 1)
    #expect(viewModel.entries.isEmpty)
    #expect(viewModel.phase == .idle)
    #expect(viewModel.freshnessFailure == nil)
    #expect(!viewModel.isBusy)

    // The explicit recovery action works normally after the cancelled launch: the abandoned action
    // left no facts, no failure, and no occupied slot behind it.
    await viewModel.rescan()
    #expect(viewModel.phase == .ready)
    #expect(viewModel.entries.map(\.registryID) == ["first-id", "second-id"])
    #expect(scanner.invocationCount == 3)
    #expect(runner.invocationCount == 0)
    #expect(!viewModel.isBusy)
}

@MainActor
@Test func explicitCancelAbandonsTheScanAndLetsALaterRescanRun() async throws {
    let fixture = try GatedViewModelFixture("vm-cancel-method")
    defer { fixture.cleanUp() }
    let viewModel = fixture.viewModel
    let scanner = fixture.scanner

    let launch = Task { await viewModel.launch() }
    try await scanner.waitForFirstCall()

    // `cancel()` waits for the abandoned pipeline's cleanup, so it is started as its own task and
    // the release follows: the explicit elevator must not be able to deadlock behind its own gate.
    let cancellation = Task { await viewModel.cancel() }
    try await awaitMainActorHeartbeat(MainActorHeartbeat())

    #expect(scanner.invocationCount == 1)
    #expect(viewModel.entries.isEmpty)
    // The slot stays occupied until the abandoned pipeline's cleanup actually finishes, so no
    // second pipeline can start behind it.
    #expect(viewModel.isBusy)
    #expect(viewModel.phase == .loadingLocal)

    scanner.releaseFirstCall()
    await cancellation.value
    await launch.value

    // The abandoned action settled without publishing: no facts, no failure, and the slot is free.
    #expect(scanner.invocationCount == 1)
    #expect(viewModel.entries.isEmpty)
    #expect(viewModel.phase == .idle)
    #expect(viewModel.freshnessFailure == nil)
    #expect(!viewModel.isBusy)

    await viewModel.rescan()
    #expect(viewModel.phase == .ready)
    #expect(viewModel.entries.map(\.registryID) == ["first-id", "second-id"])
    #expect(scanner.invocationCount == 3)
}

// MARK: Cycle B — MainActor responsiveness and one pipeline at a time

@MainActor
@Test func launchKeepsTheMainActorResponsiveWhileABoundedScanIsGated() async throws {
    let root = try appSupportScratchRoot("vm-responsive")
    defer { try? FileManager.default.removeItem(at: root) }
    let bin = root.appendingPathComponent("bin", isDirectory: true)
    let scanner = GatedScanner()
    let runner = RecordingManagerRunner(handler: forbiddenManagerHandler())
    let viewModel = InventoryViewModel(
        service: makeService(
            registryData: registryJSON([
                RegistryRow(id: "first-id", displayName: "First", executableName: "first-tool"),
                RegistryRow(id: "second-id", displayName: "Second", executableName: "second-tool"),
            ]),
            pathEntries: [bin.path],
            cacheURL: root.appendingPathComponent("cache.json"),
            currentDirectory: root.path,
            scanner: scanner,
            runner: runner
        )
    )

    let launch = Task { await viewModel.launch() }
    defer { scanner.releaseFirstCall() }
    try await scanner.waitForFirstCall()

    // The bounded scan is in flight and the launch is suspended at it: the main actor still runs
    // other work, and no update probe can have started ahead of the local facts.
    try await awaitMainActorHeartbeat(MainActorHeartbeat())
    #expect(viewModel.phase == .loadingLocal)
    #expect(viewModel.entries.isEmpty)
    #expect(scanner.invocationCount == 1)
    #expect(runner.invocationCount == 0)

    scanner.releaseFirstCall()
    await launch.value

    #expect(viewModel.phase == .ready)
    #expect(viewModel.entries.map(\.registryID) == ["first-id", "second-id"])
    // Exactly one scan of every definition: the local phase ran once, in registry order.
    #expect(scanner.invocationCount == 2)
    #expect(runner.invocationCount == 0)
    #expect(!viewModel.isBusy)
}

@MainActor
@Test func conflictingActionCoalescesRatherThanStartingASecondPipeline() async throws {
    let root = try appSupportScratchRoot("vm-coalesce")
    defer { try? FileManager.default.removeItem(at: root) }
    let bin = root.appendingPathComponent("bin", isDirectory: true)
    let scanner = GatedScanner()
    let runner = RecordingManagerRunner(handler: forbiddenManagerHandler())
    let viewModel = InventoryViewModel(
        service: makeService(
            registryData: registryJSON([
                RegistryRow(id: "first-id", displayName: "First", executableName: "first-tool"),
                RegistryRow(id: "second-id", displayName: "Second", executableName: "second-tool"),
            ]),
            pathEntries: [bin.path],
            cacheURL: root.appendingPathComponent("cache.json"),
            currentDirectory: root.path,
            scanner: scanner,
            runner: runner
        )
    )

    let launch = Task { await viewModel.launch() }
    defer { scanner.releaseFirstCall() }
    try await scanner.waitForFirstCall()
    #expect(viewModel.isBusy)

    // A conflicting action returns without disturbing the running pipeline: no second scan, no
    // probe, and the running action's phase is untouched.
    await viewModel.refreshUpdates()
    #expect(viewModel.phase == .loadingLocal)
    #expect(scanner.invocationCount == 1)
    #expect(runner.invocationCount == 0)
    await viewModel.checkForUpdates()
    #expect(viewModel.phase == .loadingLocal)
    #expect(scanner.invocationCount == 1)
    #expect(runner.invocationCount == 0)

    scanner.releaseFirstCall()
    await launch.value

    // The coalesced actions ran no further local scan and no manager command at all.
    #expect(viewModel.phase == .ready)
    #expect(viewModel.entries.map(\.registryID) == ["first-id", "second-id"])
    #expect(scanner.invocationCount == 2)
    #expect(runner.invocationCount == 0)
    #expect(!viewModel.isBusy)
}

// MARK: Cycle C — selection and search identity

@MainActor
@Test func selectionAndSearchStayStableUnderDuplicateDisplayNamesAndRescan() async throws {
    let root = try appSupportScratchRoot("vm-selection")
    defer { try? FileManager.default.removeItem(at: root) }
    let bin = root.appendingPathComponent("bin", isDirectory: true)
    try writeFixtureExecutable(bin.appendingPathComponent("dup-b-tool"))
    try writeFixtureExecutable(bin.appendingPathComponent("other-tool"))
    // Two tools share one display name and the third is unrelated: only the registry ID may
    // distinguish `dup-a` from `dup-b`.
    let viewModel = InventoryViewModel(
        service: makeService(
            registryData: registryJSON([
                RegistryRow(id: "dup-a", displayName: "Duplicated", executableName: "dup-a-tool"),
                RegistryRow(id: "dup-b", displayName: "Duplicated", executableName: "dup-b-tool"),
                RegistryRow(id: "other", displayName: "Other", executableName: "other-tool"),
            ]),
            pathEntries: [bin.path],
            cacheURL: root.appendingPathComponent("cache.json"),
            currentDirectory: root.path
        )
    )

    await viewModel.launch()
    #expect(viewModel.filteredEntries.map(\.registryID) == ["dup-a", "dup-b", "other"])

    // Selecting the tool that is NOT first, by ID: the same display name must not steal it.
    viewModel.select(registryID: "dup-b")
    #expect(viewModel.selectedRegistryID == "dup-b")
    #expect(viewModel.selectedEntry?.definition.executableName == "dup-b-tool")
    #expect(viewModel.selectedEntry?.installState == .installedAndOnPath)

    // Selection is never stored as a filtered-row position: narrowing the search can hide the
    // selected entry without losing it.
    viewModel.searchText = "other"
    #expect(viewModel.filteredEntries.map(\.registryID) == ["other"])
    #expect(viewModel.selectedRegistryID == "dup-b")
    #expect(viewModel.selectedEntry?.registryID == "dup-b")

    // Search also reads the observed entry path, case-insensitively.
    viewModel.searchText = "DUP-B-TOOL"
    #expect(viewModel.filteredEntries.map(\.registryID) == ["dup-b"])

    // An unknown ID is refused rather than stored.
    viewModel.select(registryID: "not-a-registry-id")
    #expect(viewModel.selectedRegistryID == "dup-b")

    viewModel.searchText = ""
    #expect(viewModel.filteredEntries.count == 3)

    // A rescan republishes the same identities: the selection is retained by ID, not by index.
    await viewModel.rescan()
    #expect(viewModel.phase == .ready)
    #expect(viewModel.selectedRegistryID == "dup-b")
    #expect(viewModel.selectedEntry?.definition.executableName == "dup-b-tool")
}

/// The selection the user holds must survive a rescan that no longer contains it.
@MainActor
@Test func selectionReconcilesToFirstEntryWhenTheSelectedToolDisappears() async throws {
    let root = try appSupportScratchRoot("vm-reconcile")
    defer { try? FileManager.default.removeItem(at: root) }
    let bin = root.appendingPathComponent("bin", isDirectory: true)
    try writeFixtureExecutable(bin.appendingPathComponent("dup-a-tool"))
    try writeFixtureExecutable(bin.appendingPathComponent("dup-b-tool"))
    // The launch and the Check scan see two tools; the rescan sees only the first.
    let loader = ScriptedRegistryLoader(payloads: [
        registryJSON([
            RegistryRow(id: "dup-a", displayName: "Duplicated", executableName: "dup-a-tool"),
            RegistryRow(id: "dup-b", displayName: "Duplicated", executableName: "dup-b-tool"),
        ]),
        registryJSON([
            RegistryRow(id: "dup-a", displayName: "Duplicated", executableName: "dup-a-tool"),
        ]),
    ])
    let service = InventoryService(
        environment: RecordingEnvironmentSource(
            resolveEnvironment: ShellEnvironment(
                shellPath: "/bin/zsh",
                pathEntries: [bin.path],
                pathJoined: bin.path,
                raw: ["PATH": bin.path],
                isDegraded: false
            )
        ).provider,
        registry: { try loader.load() },
        scanner: { detector, environment, directory in
            PathDiagnosticsScanner.scan(
                detector: detector, environment: environment, currentDirectory: directory
            )
        },
        updateRunner: RecordingManagerRunner(handler: forbiddenManagerHandler()),
        updateCacheURL: root.appendingPathComponent("cache.json"),
        currentDirectory: root.path,
        clock: fixedClock()
    )
    let viewModel = InventoryViewModel(service: service)

    await viewModel.launch()
    viewModel.select(registryID: "dup-b")
    #expect(viewModel.selectedRegistryID == "dup-b")

    await viewModel.rescan()

    #expect(viewModel.entries.map(\.registryID) == ["dup-a"])
    #expect(viewModel.selectedRegistryID == "dup-a")
    #expect(viewModel.selectedEntry?.definition.executableName == "dup-a-tool")
}

// MARK: Cycle D — failed rescan keeps the useful local facts and clears verified badges

@MainActor
@Test func failedRescanRetainsLocalFactsAndClearsVerifiedUpdateBadges() async throws {
    let fixture = try makeAppBrewFixture("vm-failed-rescan")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    // A current keg installed by the synthetic Homebrew prefix, reporting its own version.
    let keg = "0.162.1_1"
    try fixture.installKeg(formula: "codex", keg: keg, version: "0.162.1")
    let observedAt = Date(timeIntervalSince1970: 1_800_000_000)
    let cacheURL = fixture.cacheURL("vm-failed-rescan")
    let runner = RecordingManagerRunner(
        handler: healthyManagerHandler(
            cellar: fixture.cellar, formula: "codex", stable: "0.162.1", revision: 1, keg: keg
        )
    )
    // Two successful registry loads (the launch scan and the Check scan), then a typed failure.
    let loader = ScriptedRegistryLoader(payloads: [
        registryJSON([RegistryRow(id: "codex-id", displayName: "Codex", executableName: "codex")]),
        registryJSON([RegistryRow(id: "codex-id", displayName: "Codex", executableName: "codex")]),
    ])
    let service = InventoryService(
        environment: RecordingEnvironmentSource(
            resolveEnvironment: ShellEnvironment(
                shellPath: "/bin/zsh",
                pathEntries: [fixture.binDirectory],
                pathJoined: fixture.binDirectory,
                raw: ["PATH": fixture.binDirectory],
                isDegraded: false
            )
        ).provider,
        registry: { try loader.load() },
        scanner: { detector, environment, directory in
            PathDiagnosticsScanner.scan(
                detector: detector, environment: environment, currentDirectory: directory
            )
        },
        updateRunner: runner,
        updateCacheURL: cacheURL,
        currentDirectory: fixture.root.path,
        clock: fixedClock(observedAt)
    )
    let viewModel = InventoryViewModel(service: service)

    await viewModel.launch()
    #expect(viewModel.phase == .ready)
    #expect(viewModel.installedToolCount == 1)
    #expect(viewModel.entries.first?.update == nil)

    // Check publishes the fresh local facts first and then a VERIFIED badge.
    await viewModel.checkForUpdates()
    let verified = try #require(viewModel.entries.first)
    #expect(verified.updateStatus == .upToDate(installed: Version("0.162.1"), latest: Version(keg)))
    #expect(verified.updateProvenance == .freshProbe(observedAt: observedAt))
    #expect(viewModel.phase == .ready)
    #expect(viewModel.freshnessFailure == nil)

    // A rescan whose registry load fails: the failure is a typed value, the last useful local
    // facts stay published, and the earlier verified result is NOT left looking current.
    await viewModel.rescan()

    #expect(viewModel.phase == .failed)
    #expect(viewModel.freshnessFailure?.registryError == .duplicateId("fixture"))
    #expect(viewModel.entries.map(\.registryID) == ["codex-id"])
    #expect(viewModel.installedToolCount == 1)
    #expect(viewModel.updateAvailableCount == 0)
    #expect(viewModel.entries.allSatisfy { $0.update == nil })
    #expect(viewModel.entries.allSatisfy { $0.updateStatus == nil })
    #expect(viewModel.selectedRegistryID == "codex-id")
    // The typed local facts are still readable beside the freshness failure.
    #expect(viewModel.entries.first?.installState == .installedAndOnPath)
    #expect(viewModel.entries.first?.diagnostic.detectedTool.version == "0.162.1")
    #expect(!viewModel.isBusy)
}

// MARK: Cycle E — local first, cancellation across a gated manager query, and a failed refresh

/// One controlled manager seam for both gated view-model proofs: the answer script (healthy or
/// failed) and the one-shot gate are test-owned state, so one service and one view-model can first
/// verify a tool and then be told that the manager fails. The gate is opened by `releaseGate()`
/// (opened via an awaited release), never by a sleep.
final class ControlledManagerRunner: UpdateCommandRunner, @unchecked Sendable {
    typealias Script = @Sendable (String, [String]) -> CommandOutcome

    private let lock = NSLock()
    private let gate = AsyncGate()
    private var script: Script
    private var invocationCount = 0
    private var gateArmed = false
    private var gatedCallArrived = false

    init(script: @escaping Script) {
        self.script = script
    }

    /// Replaces the answer script. This is the mutable half of the seam: a tool that was verified
    /// moments ago can be re-probed against a manager that now fails, with no second fixture.
    func setScript(_ newScript: @escaping Script) {
        lock.lock()
        script = newScript
        lock.unlock()
    }

    /// Holds the NEXT manager call at the gate; later calls run normally unless re-armed.
    func armGate() {
        lock.lock()
        gateArmed = true
        gatedCallArrived = false
        lock.unlock()
    }

    func releaseGate() async { await gate.openGate() }

    func run(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval
    ) async -> CommandOutcome {
        let (current, gated) = beginInvocation()
        if gated {
            noteGatedCallArrived()
            // `AsyncGate` ignores task cancellation, so the query stays open until the test opens
            // it: the paused manager call is deterministic rather than a race.
            await gate.waitForOpen()
        }
        return current(executablePath, arguments)
    }

    /// `NSLock` is never locked directly from an asynchronous context: recording, the script
    /// handover, and the gate flag all move through synchronous helpers.
    private func beginInvocation() -> (Script, Bool) {
        lock.lock()
        defer { lock.unlock() }
        invocationCount += 1
        let gated = gateArmed
        gateArmed = false
        return (script, gated)
    }

    private func noteGatedCallArrived() {
        lock.lock()
        gatedCallArrived = true
        lock.unlock()
    }

    var invocations: Int {
        lock.lock()
        defer { lock.unlock() }
        return invocationCount
    }

    private var hasGatedCallArrived: Bool {
        lock.lock()
        defer { lock.unlock() }
        return gatedCallArrived
    }

    /// Bounded test-side wait for the gated call. A call that never arrives fails with a typed
    /// reason rather than polling forever.
    func waitForGatedCall(timeout: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !hasGatedCallArrived {
            guard Date() < deadline else { throw GatedManagerTimeout.gatedCallNeverObserved }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
    }
}

/// Raised when the gated manager call never arrived inside the watchdog window.
enum GatedManagerTimeout: Error, Equatable {
    case gatedCallNeverObserved
}

/// The local-first contract at a real cancellation boundary: Check publishes the useful local
/// snapshot BEFORE its manager query finishes, and cancelling the initiating action after those
/// facts exist keeps them and publishes no update outcome for the abandoned action.
@MainActor
@Test func checkPublishesLocalFactsBeforeAGatedManagerQueryAndSurvivesCancellation() async throws {
    let fixture = try makeAppBrewFixture("vm-local-first")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    // A current keg installed by the synthetic Homebrew prefix, reporting its own version: the
    // registry tool is eligible for the M6 probe, so a manager query really is reached.
    let keg = "0.162.1_1"
    try fixture.installKeg(formula: "codex", keg: keg, version: "0.162.1")
    let runner = ControlledManagerRunner(
        script: healthyManagerHandler(
            cellar: fixture.cellar, formula: "codex", stable: "0.162.1", revision: 1, keg: keg
        )
    )
    let viewModel = InventoryViewModel(
        service: makeService(
            registryData: registryJSON([
                RegistryRow(id: "codex-id", displayName: "Codex", executableName: "codex")
            ]),
            pathEntries: [fixture.binDirectory],
            cacheURL: fixture.cacheURL("vm-local-first"),
            currentDirectory: fixture.root.path,
            runner: runner,
            clock: fixedClock()
        )
    )

    await viewModel.launch()
    #expect(viewModel.phase == .ready)
    #expect(viewModel.installedToolCount == 1)
    #expect(viewModel.entries.first?.update == nil)

    // The manager query is held open from the first command the probe issues.
    runner.armGate()
    let check = Task { await viewModel.checkForUpdates() }
    do {
    try await runner.waitForGatedCall()

    // The local facts are already published while the manager query is still in flight: the phase
    // names the check that is running, the tool is usable, and it carries no update outcome yet —
    // nothing borrowed from a previous result. The main actor is not monopolized meanwhile.
    try await awaitMainActorHeartbeat(MainActorHeartbeat())
    #expect(viewModel.phase == .checkingUpdates)
    #expect(viewModel.installedToolCount == 1)
    #expect(viewModel.entries.map(\.registryID) == ["codex-id"])
    #expect(viewModel.entries.first?.installState == .installedAndOnPath)
    #expect(viewModel.entries.first?.diagnostic.detectedTool.version == "0.162.1")
    #expect(viewModel.entries.first?.update == nil)
    #expect(viewModel.selectedRegistryID == "codex-id")
    #expect(runner.invocations == 1)

    // Cancelled AFTER the local facts exist. The slot stays occupied until the abandoned pipeline's
    // cleanup actually finishes, so nothing can start behind it.
    check.cancel()
    try await awaitMainActorHeartbeat(MainActorHeartbeat())
    #expect(viewModel.isBusy)
    #expect(viewModel.entries.first?.update == nil)

    await runner.releaseGate()
    await check.value
    } catch let error {
    check.cancel()
    await runner.releaseGate()
    await check.value
    throw error
    }

    // The abandoned action published no update outcome and no failure: the still-true local facts
    // remain, the phase settles on them, and a later action is free to run.
    #expect(!viewModel.isBusy)
    #expect(viewModel.phase == .localReady)
    #expect(viewModel.entries.map(\.registryID) == ["codex-id"])
    #expect(viewModel.installedToolCount == 1)
    #expect(viewModel.entries.first?.update == nil)
    #expect(viewModel.entries.first?.updateStatus == nil)
    #expect(viewModel.updateAvailableCount == 0)
    #expect(viewModel.selectedRegistryID == "codex-id")
    #expect(viewModel.freshnessFailure == nil)
    #expect(viewModel.updateFailure == nil)
}

/// A verified result is never left looking current. A Refresh whose manager fails clears the old
/// badge at the start, keeps the fresh local facts usable, and ends on Core's typed
/// `.probeFailed` unknown — not the previous `upToDate`.
@MainActor
@Test func failedRefreshReplacesAVerifiedBadgeWithATypedProbeFailure() async throws {
    let fixture = try makeAppBrewFixture("vm-failed-refresh")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let keg = "0.162.1_1"
    try fixture.installKeg(formula: "codex", keg: keg, version: "0.162.1")
    let observedAt = Date(timeIntervalSince1970: 1_800_000_000)
    let runner = ControlledManagerRunner(
        script: healthyManagerHandler(
            cellar: fixture.cellar, formula: "codex", stable: "0.162.1", revision: 1, keg: keg
        )
    )
    let viewModel = InventoryViewModel(
        service: makeService(
            registryData: registryJSON([
                RegistryRow(id: "codex-id", displayName: "Codex", executableName: "codex")
            ]),
            pathEntries: [fixture.binDirectory],
            cacheURL: fixture.cacheURL("vm-failed-refresh"),
            currentDirectory: fixture.root.path,
            runner: runner,
            clock: fixedClock(observedAt)
        )
    )

    await viewModel.launch()
    // The first Check verifies the tool against the synthetic manager.
    await viewModel.checkForUpdates()
    let verified = try #require(viewModel.entries.first)
    #expect(verified.updateStatus == .upToDate(installed: Version("0.162.1"), latest: Version(keg)))
    #expect(verified.updateProvenance == .freshProbe(observedAt: observedAt))
    #expect(viewModel.phase == .ready)
    #expect(viewModel.updateAvailableCount == 0)

    // The same seam now answers with an opaque process failure, and the Refresh's query is held so
    // the cleared state is observed while the new action is still running.
    runner.setScript { _, _ in .failure(.nonzeroExit) }
    runner.armGate()
    let refresh = Task { await viewModel.refreshUpdates() }
    do {
    try await runner.waitForGatedCall()

    // The previous verified badge is already gone while the fresh local facts are on screen: the
    // tool stays usable and no old result is presented as this action's outcome.
    #expect(viewModel.phase == .checkingUpdates)
    #expect(viewModel.installedToolCount == 1)
    #expect(viewModel.entries.first?.update == nil)
    #expect(viewModel.entries.first?.updateStatus == nil)
    #expect(viewModel.entries.first?.updateProvenance == nil)
    #expect(viewModel.entries.first?.installState == .installedAndOnPath)
    #expect(viewModel.entries.first?.diagnostic.detectedTool.version == "0.162.1")
    #expect(viewModel.selectedRegistryID == "codex-id")
    #expect(viewModel.updateAvailableCount == 0)

    await runner.releaseGate()
    await refresh.value
    } catch let error {
    refresh.cancel()
    await runner.releaseGate()
    await refresh.value
    throw error
    }

    // Core's own classification: an opaque `nonzeroExit` is `probeFailed`, never a guessed network
    // reason — and it is an unknown, not a verified comparison.
    let failed = try #require(viewModel.entries.first)
    #expect(failed.updateStatus == .unknown(installed: Version("0.162.1"), reason: .probeFailed))
    #expect(failed.updateStatus?.isVerifiedComparison == false)
    #expect(failed.updateProvenance == UpdateProvenance.none)
    #expect(viewModel.phase == .ready)
    #expect(viewModel.updateAvailableCount == 0)
    // The local facts, the selection, and the diagnostics survived the failed probe.
    #expect(viewModel.installedToolCount == 1)
    #expect(viewModel.selectedRegistryID == "codex-id")
    #expect(viewModel.entries.map(\.registryID) == ["codex-id"])
    #expect(failed.diagnostic.detectedTool.version == "0.162.1")
    #expect(failed.diagnostic.detectedTool.state == .installedAndOnPath)
    #expect(!viewModel.isBusy)
}

// MARK: Test-side read helpers

extension InventoryViewModel {
    /// The install states in published order — a compact read for the registry-order assertions.
    var installStates: [InstallState] { entries.map(\.installState) }
}