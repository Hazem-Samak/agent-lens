import Darwin
import Foundation
import Testing
@testable import AgentLensCore

// M6 step 4 — coordinator: eligibility order, mode policy, cache use, association, cancellation.
// Every test injects a scripted runner, a temporary cache file, and a fixed clock.

private final class CountingRunner: UpdateCommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var recordedArguments: [[String]] = []
    private var activeBatches = 0
    private var maximumObserved = 0
    var maximumConcurrentBatches: Int {
        lock.lock(); defer { lock.unlock() }
        return maximumObserved
    }
    let delay: UInt64
    let handler: @Sendable ([String]) -> CommandOutcome

    init(delayNanoseconds: UInt64 = 0, handler: @escaping @Sendable ([String]) -> CommandOutcome) {
        self.delay = delayNanoseconds
        self.handler = handler
    }

    var invocationCount: Int {
        lock.lock(); defer { lock.unlock() }
        return count
    }

    var arguments: [[String]] {
        lock.lock(); defer { lock.unlock() }
        return recordedArguments
    }

    private func begin(_ arguments: [String]) {
        lock.lock(); defer { lock.unlock() }
        count += 1
        recordedArguments.append(arguments)
        activeBatches += 1
        maximumObserved = max(maximumObserved, activeBatches)
    }

    private func end() {
        lock.lock(); defer { lock.unlock() }
        activeBatches -= 1
    }

    func run(executablePath: String, arguments: [String], environment: [String: String], timeout: TimeInterval) async -> CommandOutcome {
        begin(arguments)
        defer { end() }
        if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
        return handler(arguments)
    }
}

private actor OneShotSignal {
    private var signaled = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        guard !signaled else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func signal() {
        guard !signaled else { return }
        signaled = true
        continuation?.resume()
        continuation = nil
    }
}

/// Deterministic process seam: one selected invocation can be held until the test releases it.
private final class ControlledRunner: UpdateCommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var invocations: [[String]] = []
    private var active = 0
    private var maximumActive = 0
    private let heldInvocation: Int?
    private let entered: OneShotSignal
    private let release: OneShotSignal
    private let handler: @Sendable ([String]) -> CommandOutcome

    init(
        heldInvocation: Int? = 1,
        entered: OneShotSignal = OneShotSignal(),
        release: OneShotSignal = OneShotSignal(),
        handler: @escaping @Sendable ([String]) -> CommandOutcome
    ) {
        self.heldInvocation = heldInvocation
        self.entered = entered
        self.release = release
        self.handler = handler
    }

    var invocationCount: Int {
        lock.lock(); defer { lock.unlock() }
        return invocations.count
    }

    var maximumConcurrentInvocations: Int {
        lock.lock(); defer { lock.unlock() }
        return maximumActive
    }

    private func begin(_ arguments: [String]) -> Int {
        lock.lock(); defer { lock.unlock() }
        invocations.append(arguments)
        active += 1
        maximumActive = max(maximumActive, active)
        return invocations.count
    }

    private func end() {
        lock.lock(); defer { lock.unlock() }
        active -= 1
    }

    func run(executablePath: String, arguments: [String], environment: [String: String], timeout: TimeInterval) async -> CommandOutcome {
        let ordinal = begin(arguments)
        if ordinal == heldInvocation {
            await entered.signal()
            await release.wait()
        }
        let outcome = handler(arguments)
        end()
        return outcome
    }
}

private final class RecordingProcessRunner: UpdateCommandRunner, @unchecked Sendable {
    struct Observation: Sendable {
        let outcome: CommandOutcome
        let elapsed: TimeInterval
    }

    private let lock = NSLock()
    private var recorded: [Observation] = []
    private let deadlineLimit: TimeInterval
    private let production = ProcessUpdateCommandRunner()

    init(deadlineLimit: TimeInterval = 7) {
        self.deadlineLimit = deadlineLimit
    }

    var observations: [Observation] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    private func record(_ observation: Observation) {
        lock.lock(); defer { lock.unlock() }
        recorded.append(observation)
    }

    func run(executablePath: String, arguments: [String], environment: [String: String], timeout: TimeInterval) async -> CommandOutcome {
        let started = DispatchTime.now().uptimeNanoseconds
        let outcome = await production.run(
            executablePath: executablePath,
            arguments: arguments,
            environment: environment,
            timeout: min(timeout, deadlineLimit)
        )
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000
        record(Observation(outcome: outcome, elapsed: elapsed))
        return outcome
    }
}

private struct Scenario {
    let fixture: BrewFixture
    let codexKeg: String
    let url: URL
    let clockValue: Date
}

private func scenario(_ label: String, now: Date = Date(timeIntervalSince1970: 1_800_000_000)) throws -> Scenario {
    let fixture = try makeBrewFixture(label)
    let keg = try fixture.installKeg(formula: "codex", keg: "0.162.1_1")
    let url = fixture.prefix.deletingLastPathComponent().appendingPathComponent("cache-\(label).json")
    return Scenario(fixture: fixture, codexKeg: keg, url: url, clockValue: now)
}

private func processEnvironment(
    _ scenario: Scenario,
    behavior: String,
    markers: [String: String] = [:]
) -> ShellEnvironment {
    var raw = m6Environment(pathEntries: [scenario.fixture.binDirectory]).raw
    raw["AGENT_LENS_PROCESS_CASE"] = behavior
    raw["AGENT_LENS_PROCESS_CELLAR"] = scenario.fixture.cellar
    for (key, value) in markers { raw[key] = value }
    return ShellEnvironment(
        shellPath: "/bin/zsh",
        pathEntries: [scenario.fixture.binDirectory],
        pathJoined: scenario.fixture.binDirectory,
        raw: raw,
        isDegraded: false
    )
}

private func writeProductionProcessScript(to path: String) throws {
    let script = #"""
    #!/bin/sh
    case "$AGENT_LENS_PROCESS_CASE:$1" in
      hang-descendant:--cellar)
        /bin/sleep 30 &
        child=$!
        printf '%s\n' "$child" > "$AGENT_LENS_PID_MARKER"
        exit 0
        ;;
      early-eof:--cellar)
        /bin/sleep 30 >/dev/null 2>&1 &
        child=$!
        printf '%s\n' "$child" > "$AGENT_LENS_PID_MARKER"
        printf '%s\n' "$AGENT_LENS_PROCESS_CELLAR"
        exit 0
        ;;
      oversized:--cellar)
        /usr/bin/head -c 1048577 /dev/zero
        ;;
      nonzero:--cellar)
        printf '%s\n' 'controlled nonzero exit'
        exit 7
        ;;
      invalid-utf8:--cellar)
        printf '\377'
        ;;
      delayed-final:outdated)
        printf '%s\n' started > "$AGENT_LENS_STARTED_MARKER"
        while [ ! -f "$AGENT_LENS_RELEASE_MARKER" ]; do /bin/sleep 0.01; done
        printf '%s\n' finished > "$AGENT_LENS_FINISHED_MARKER"
        printf '%s' '{"formulae":[],"casks":[]}'
        ;;
      delayed:--cellar)
        printf '%s\n' started > "$AGENT_LENS_STARTED_MARKER"
        while [ ! -f "$AGENT_LENS_RELEASE_MARKER" ]; do /bin/sleep 0.01; done
        printf '%s\n' finished > "$AGENT_LENS_FINISHED_MARKER"
        printf '%s\n' "$AGENT_LENS_PROCESS_CELLAR"
        ;;
      *:--cellar)
        printf '%s\n' "$AGENT_LENS_PROCESS_CELLAR"
        ;;
      *:info)
        printf '%s' '{"formulae":[{"name":"codex","full_name":"codex","revision":1,"versions":{"stable":"0.162.1"},"installed":[{"version":"0.162.1_1"}]}],"casks":[]}'
        ;;
      *)
        printf '%s' '{"formulae":[],"casks":[]}'
        ;;
    esac
    """#
    try Data(script.utf8).write(to: URL(fileURLWithPath: path))
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
}

private func waitForScratchMarker(_ url: URL, timeout: TimeInterval) async -> Bool {
    let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(timeout * 1_000_000_000)
    while !FileManager.default.fileExists(atPath: url.path) {
        if DispatchTime.now().uptimeNanoseconds >= deadline { return false }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    return true
}

private func processIsAlive(_ pid: pid_t) -> Bool {
    if kill(pid, 0) == 0 { return true }
    return errno == EPERM
}

private func waitForProcessExit(_ pid: pid_t, timeout: TimeInterval) async -> Bool {
    let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(timeout * 1_000_000_000)
    while processIsAlive(pid) {
        if DispatchTime.now().uptimeNanoseconds >= deadline { return false }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return true
}

private struct IsolatedProcessResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

private func runIsolatedProcess(
    _ process: Process,
    captureDirectory: URL,
    label: String,
    timeout: TimeInterval = 60
) throws -> IsolatedProcessResult {
    let stdoutURL = captureDirectory.appendingPathComponent("\(label)-stdout-\(UUID().uuidString).log")
    let stderrURL = captureDirectory.appendingPathComponent("\(label)-stderr-\(UUID().uuidString).log")
    try Data().write(to: stdoutURL)
    try Data().write(to: stderrURL)
    let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
    let stderrHandle = try FileHandle(forWritingTo: stderrURL)
    defer {
        try? stdoutHandle.close()
        try? stderrHandle.close()
    }
    process.standardOutput = stdoutHandle
    process.standardError = stderrHandle
    let exited = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in exited.signal() }
    try process.run()
    guard exited.wait(timeout: .now() + timeout) == .success else {
        process.terminate()
        if exited.wait(timeout: .now() + 1) != .success {
            _ = kill(process.processIdentifier, SIGKILL)
            _ = exited.wait(timeout: .now() + 1)
        }
        throw NSError(domain: "AgentLensTests", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "isolated subprocess exceeded its watchdog"])
    }
    process.waitUntilExit()
    try stdoutHandle.close()
    try stderrHandle.close()
    return IsolatedProcessResult(
        status: process.terminationStatus,
        stdout: String(decoding: try Data(contentsOf: stdoutURL), as: UTF8.self),
        stderr: String(decoding: try Data(contentsOf: stderrURL), as: UTF8.self)
    )
}

/// The three manager answers for one current Codex keg at revision 1 with stable 0.162.1.
private func healthyHandler(cellar: String) -> @Sendable ([String]) -> CommandOutcome {
    { arguments in
        switch arguments.first {
        case "--cellar": return .success(Data("\(cellar)\n".utf8))
        case "info": return .success(infoJSON([(name: "codex", stable: "0.162.1", revision: 1, installed: ["0.162.1_1"])]))
        default: return .success(outdatedJSON([]))
        }
    }
}

private func toolDetection(
    _ scenario: Scenario,
    version: String?,
    path: String? = nil,
    target: String? = nil,
    originDirectory: String? = nil
) -> ToolPathDiagnostic {
    let entry = path ?? scenario.codexKeg
    let canonicalTarget = target ?? entry
    let detected = DetectedTool(
        displayName: "Codex",
        executableName: "codex",
        state: .installedAndOnPath,
        entryPath: entry,
        resolvedPath: canonicalTarget,
        source: "brew",
        version: version
    )
    let candidate = PathCandidateObservation(
        origin: .path(slotIndex: 0, directoryText: originDirectory ?? scenario.fixture.binDirectory),
        entryPath: entry,
        kind: .executableSymlink,
        canonicalTarget: canonicalTarget
    )
    return ToolPathDiagnostic(
        detectedTool: detected,
        pathCandidates: [candidate],
        firstLiveCandidate: candidate,
        targetGroups: [PathTargetGroup(canonicalTarget: canonicalTarget, entryPaths: [entry], firstSlotIndex: 0)],
        repeatedPathSlotCount: 0,
        sameTargetAliasCount: 0,
        selection: .winner(candidate),
        shadowedInstallationCount: 0,
        installationVersions: []
    )
}

private func probeDefinition(id: String, displayName: String, executableName: String) -> DetectorDefinition {
    let name = executableName.isEmpty ? "tool" : executableName
    // Homebrew coordinator subjects never inspect declared packages — eligibility is driven by the
    // diagnostic's source — so an empty package set keeps the subject identity faithful: the stable
    // registry ID and display name travel with the diagnostic exactly as the coordinator expects.
    return try! DetectorDefinition(
        id: id,
        displayName: displayName,
        executableName: name,
        extraSearchRoots: [],
        fixture: nil,
        category: .aiAgent,
        packages: [],
        informationURL: nil,
        uninstallInstructionsURL: nil,
        versionQuery: .standard
    )
}

private func probeSubject(_ diagnostic: ToolPathDiagnostic, id: String, displayName: String? = nil) -> UpdateProbeSubject {
    UpdateProbeSubject(
        definition: probeDefinition(
            id: id,
            displayName: displayName ?? diagnostic.detectedTool.displayName,
            executableName: diagnostic.detectedTool.executableName
        ),
        diagnostic: diagnostic
    )
}

@Test func offlineModeLaunchesNoProbeAndReadsNoCache() async throws {
    let s = try scenario("offline")
    let runner = CountingRunner(handler: healthyHandler(cellar: s.fixture.cellar))
    let results = await UpdateProbeCoordinator.run(
        subjects: [probeSubject(toolDetection(s, version: "0.162.1"), id: "codex")],
        environment: m6Environment(pathEntries: [s.fixture.binDirectory]),
        mode: .offline,
        runner: runner,
        cacheURL: s.url,
        now: { s.clockValue }
    )
    #expect(runner.invocationCount == 0)
    #expect(results.first?.status == .unknown(installed: Version("0.162.1"), reason: .networkUnavailable))
    #expect(FileManager.default.fileExists(atPath: s.url.path) == false)
}

@Test func unsupportedStableKeepsLocalTextAndDoesNotCreateCacheEntry() async throws {
    let s = try scenario("unsupported-stable")
    let runner = CountingRunner { arguments in
        switch arguments.first {
        case "--cellar": .success(Data("\(s.fixture.cellar)\n".utf8))
        case "info": .success(infoJSON([
            (name: "codex", stable: "HEAD", revision: 0, installed: ["0.162.1_1"]),
        ]))
        default: .success(outdatedJSON([]))
        }
    }
    let results = await UpdateProbeCoordinator.run(
        subjects: [probeSubject(toolDetection(s, version: "0.162.1"), id: "codex")],
        environment: m6Environment(pathEntries: [s.fixture.binDirectory]),
        mode: .refresh,
        runner: runner,
        cacheURL: s.url,
        now: { s.clockValue }
    )
    let result = try #require(results.first)
    #expect(result.status == .unknown(installed: Version("0.162.1"), reason: .unsupportedVersion))
    #expect(result.localVersion == "0.162.1")
    #expect(result.provenance == .freshProbe(observedAt: s.clockValue))
    #expect(FileManager.default.fileExists(atPath: s.url.path) == false)
}

@Test func plainScanReportsNotCheckedAndMakesNoManagerCall() async throws {
    let s = try scenario("plain")
    let runner = CountingRunner(handler: healthyHandler(cellar: s.fixture.cellar))
    let results = await UpdateProbeCoordinator.run(
        subjects: [probeSubject(toolDetection(s, version: "0.162.1"), id: "codex")],
        environment: m6Environment(pathEntries: [s.fixture.binDirectory]),
        mode: .localOnly,
        runner: runner,
        cacheURL: s.url,
        now: { s.clockValue }
    )
    #expect(runner.invocationCount == 0)
    #expect(results.first?.status == .unknown(installed: Version("0.162.1"), reason: .notChecked))
}

@Test func checkUpdatesProbesOnceThenHitsTheSixHourCacheWithoutAnotherQuery() async throws {
    let s = try scenario("cache-hit", now: Date(timeIntervalSince1970: 1_800_000_000.75))
    let runner = CountingRunner(handler: healthyHandler(cellar: s.fixture.cellar))
    let env = m6Environment(pathEntries: [s.fixture.binDirectory])
    let subjects = [probeSubject(toolDetection(s, version: "0.162.1"), id: "codex")]

    let first = await UpdateProbeCoordinator.run(
        subjects: subjects, environment: env, mode: .checkUpdates,
        runner: runner, cacheURL: s.url, now: { s.clockValue }
    )
    #expect(runner.invocationCount == 3)
    #expect(first.first?.provenance == .freshProbe(observedAt: s.clockValue))

    let second = await UpdateProbeCoordinator.run(
        subjects: subjects, environment: env, mode: .checkUpdates,
        runner: runner, cacheURL: s.url, now: { s.clockValue.addingTimeInterval(60) }
    )
    #expect(runner.invocationCount == 3) // cache hit: zero additional queries
    #expect(second.first?.provenance == .cache(observedAt: s.clockValue))
    #expect(second.first?.status == first.first?.status)
}

@Test func refreshBypassesTheCacheAndAFailedRefreshDoesNotRenewOldSuccess() async throws {
    let s = try scenario("refresh")
    let env = m6Environment(pathEntries: [s.fixture.binDirectory])
    let subjects = [probeSubject(toolDetection(s, version: "0.162.1"), id: "codex")]
    let initialRunner = CountingRunner(handler: healthyHandler(cellar: s.fixture.cellar))
    let initial = await UpdateProbeCoordinator.run(
        subjects: subjects, environment: env, mode: .checkUpdates,
        runner: initialRunner,
        cacheURL: s.url, now: { s.clockValue }
    )
    #expect(initialRunner.invocationCount == 3)
    #expect(initial.first?.provenance == .freshProbe(observedAt: s.clockValue))
    let initialCache = try Data(contentsOf: s.url)
    let initialDocument = try JSONDecoder().decode(UpdateMetadataDocument.self, from: initialCache)
    #expect(initialDocument.entries.first?.observedAt == s.clockValue)

    let updatedMetadata: @Sendable ([String]) -> CommandOutcome = { arguments in
        switch arguments.first {
        case "--cellar": .success(Data("\(s.fixture.cellar)\n".utf8))
        case "info": .success(infoJSON([
            (name: "codex", stable: "0.162.1", revision: 2, installed: ["0.162.1_1"])
        ]))
        default: .success(outdatedJSON([
            (name: "codex", current: "0.162.1_2", installed: ["0.162.1_1"])
        ]))
        }
    }
    let successfulRefreshRunner = CountingRunner(handler: updatedMetadata)
    let successfulRefreshAt = s.clockValue.addingTimeInterval(30)
    let successfulRefresh = await UpdateProbeCoordinator.run(
        subjects: subjects, environment: env, mode: .refresh,
        runner: successfulRefreshRunner, cacheURL: s.url, now: { successfulRefreshAt }
    )
    #expect(successfulRefreshRunner.invocationCount == 3)
    #expect(successfulRefresh.first?.status == .updateAvailable(
        installed: Version("0.162.1"), latest: Version("0.162.1_2")
    ))
    #expect(successfulRefresh.first?.provenance == .freshProbe(observedAt: successfulRefreshAt))
    let refreshedCache = try Data(contentsOf: s.url)
    let refreshedDocument = try JSONDecoder().decode(UpdateMetadataDocument.self, from: refreshedCache)
    #expect(refreshedCache != initialCache)
    #expect(refreshedDocument.entries.first?.observedAt == successfulRefreshAt)
    #expect(refreshedDocument.entries.first?.formulaRevision == 2)

    for (mode, expectedReason) in [
        (UpdateProbeMode.localOnly, UnknownReason.notChecked),
        (.offline, .networkUnavailable),
    ] {
        let disabledRunner = CountingRunner { _ in .failure(.nonzeroExit) }
        let disabled = await UpdateProbeCoordinator.run(
            subjects: subjects, environment: env, mode: mode,
            runner: disabledRunner, cacheURL: s.url,
            now: { successfulRefreshAt.addingTimeInterval(30) }
        )
        #expect(disabledRunner.invocationCount == 0)
        #expect(disabled.first?.status == .unknown(installed: Version("0.162.1"), reason: expectedReason))
        #expect(disabled.first?.provenance == UpdateProvenance.none)
        #expect(try Data(contentsOf: s.url) == refreshedCache)
    }

    let failing = CountingRunner { _ in .failure(.nonzeroExit) }
    let failedRefreshAt = successfulRefreshAt.addingTimeInterval(30)
    let refreshed = await UpdateProbeCoordinator.run(
        subjects: subjects, environment: env, mode: .refresh,
        runner: failing, cacheURL: s.url, now: { failedRefreshAt }
    )
    #expect(failing.invocationCount == 1) // the metadata query ran; cache was bypassed
    #expect(refreshed.first?.status == .unknown(installed: Version("0.162.1"), reason: .probeFailed))
    #expect(refreshed.first?.provenance == UpdateProvenance.none)
    #expect(try Data(contentsOf: s.url) == refreshedCache)
    let afterFailedRefresh = try JSONDecoder().decode(
        UpdateMetadataDocument.self, from: Data(contentsOf: s.url)
    )
    #expect(afterFailedRefresh.entries.first?.observedAt == successfulRefreshAt)
}

@Test func npmAndMissingToolsInvokeZeroManagerCommandsAndCarryTypedReasons() async throws {
    let s = try scenario("ineligible")
    let runner = CountingRunner(handler: healthyHandler(cellar: s.fixture.cellar))
    let npm = DetectedTool(
        displayName: "Codex", executableName: "codex", state: .installedAndOnPath,
        entryPath: "/x/lib/node_modules/codex", resolvedPath: "/x/lib/node_modules/codex",
        source: "npm", version: "0.162.1"
    )
    let missing = DetectedTool(
        displayName: "Grok CLI", executableName: "grok", state: .notInstalled,
        entryPath: nil, resolvedPath: nil, source: "–", version: nil
    )
    let standalone = DetectedTool(
        displayName: "OpenCode", executableName: "opencode", state: .installedAndOnPath,
        entryPath: "/x/opencode", resolvedPath: "/x/opencode", source: "standalone", version: "2.0.28"
    )
    let results = await UpdateProbeCoordinator.run(
        subjects: [
            probeSubject(winnerDiagnostic(npm), id: "npm-tool"),
            probeSubject(missingDiagnostic(missing), id: "missing-tool"),
            probeSubject(winnerDiagnostic(standalone), id: "standalone-tool"),
        ],
        environment: m6Environment(pathEntries: [s.fixture.binDirectory]),
        mode: .checkUpdates,
        runner: runner,
        cacheURL: s.url,
        now: { s.clockValue }
    )
    #expect(runner.invocationCount == 0)
    #expect(results.map(\.registryID) == ["npm-tool", "missing-tool", "standalone-tool"])
    #expect(results.map(\.diagnosticIndex) == [0, 1, 2])
    #expect(results.map(\.status) == [
        // M10-B: an npm selection is now eligible and enters the bounded npm probe. The selected
        // executable path cannot be re-observed, so the probe fails closed as an identity unknown
        // BEFORE any manager command is launched — still zero commands, never a verified claim.
        .unknown(installed: Version("0.162.1"), reason: .identityUnverified),
        .unknown(installed: nil, reason: .notInstalled),
        .unknown(installed: Version("2.0.28"), reason: .noRegistry),
    ])
}

private func npmDiagnostic(_ tool: DetectedTool) -> ToolPathDiagnostic {
    ToolPathDiagnostic(
        detectedTool: tool, pathCandidates: [], firstLiveCandidate: nil, targetGroups: [],
        repeatedPathSlotCount: 0, sameTargetAliasCount: 0, selection: .notInstalled, shadowedInstallationCount: 0,
        installationVersions: []
    )
}

private func missingDiagnostic(_ tool: DetectedTool) -> ToolPathDiagnostic { npmDiagnostic(tool) }

/// An installed tool whose M5 selection is a verified winner, consistent with its detector state.
private func winnerDiagnostic(_ tool: DetectedTool) -> ToolPathDiagnostic {
    let entry = tool.entryPath ?? ""
    let candidate = PathCandidateObservation(
        origin: .path(slotIndex: 0, directoryText: "/synthetic/bin"),
        entryPath: entry,
        kind: .executableSymlink,
        canonicalTarget: entry
    )
    return ToolPathDiagnostic(
        detectedTool: tool, pathCandidates: [candidate], firstLiveCandidate: candidate,
        targetGroups: [PathTargetGroup(canonicalTarget: entry, entryPaths: [entry], firstSlotIndex: 0)],
        repeatedPathSlotCount: 0, sameTargetAliasCount: 0, selection: .winner(candidate),
        shadowedInstallationCount: 0,
        installationVersions: []
    )
}

@Test func inconsistentM5SelectionSuppressesAnyStatusClaim() async throws {
    let s = try scenario("inconsistent")
    let runner = CountingRunner(handler: healthyHandler(cellar: s.fixture.cellar))
    let base = toolDetection(s, version: "0.162.1")
    let inconsistent = ToolPathDiagnostic(
        detectedTool: base.detectedTool, pathCandidates: base.pathCandidates,
        firstLiveCandidate: base.firstLiveCandidate, targetGroups: base.targetGroups,
        repeatedPathSlotCount: 0, sameTargetAliasCount: 0,
        selection: .inconsistent("disagreement"), shadowedInstallationCount: nil,
        installationVersions: []
    )
    let results = await UpdateProbeCoordinator.run(
        subjects: [probeSubject(inconsistent, id: "codex")], environment: m6Environment(pathEntries: [s.fixture.binDirectory]),
        mode: .checkUpdates, runner: runner, cacheURL: s.url, now: { s.clockValue }
    )
    #expect(runner.invocationCount == 0)
    #expect(results.first?.status == .unknown(installed: Version("0.162.1"), reason: .diagnosticInconsistent))
    #expect(results.first?.registryID == "codex")
    #expect(results.first?.diagnostic == inconsistent)
    #expect(results.first?.selectedTarget == nil)
    #expect(results.first?.localVersion == "0.162.1")
}

@Test func installedVersionChangeRecomputesStatusFromTheSameCachedMetadata() async throws {
    let s = try scenario("recompute")
    let env = m6Environment(pathEntries: [s.fixture.binDirectory])
    _ = await UpdateProbeCoordinator.run(
        subjects: [probeSubject(toolDetection(s, version: "0.162.1"), id: "codex")], environment: env, mode: .checkUpdates,
        runner: CountingRunner(handler: healthyHandler(cellar: s.fixture.cellar)),
        cacheURL: s.url, now: { s.clockValue }
    )
    // Same cached latest (0.162.1_1 vs package 0.162.1_1): the local banner text changes to an unsupported value.
    let results = await UpdateProbeCoordinator.run(
        subjects: [probeSubject(toolDetection(s, version: "0.150.0"), id: "codex")], environment: env, mode: .checkUpdates,
        runner: CountingRunner { _ in .failure(.nonzeroExit) }, cacheURL: s.url,
        now: { s.clockValue.addingTimeInterval(10) }
    )
    #expect(results.first?.status == .unknown(installed: Version("0.150.0"), reason: .identityUnverified))
}

@Test func resultsAreAssociatedByRegistryIDNotCompletionOrder() async throws {
    let s = try scenario("order")
    let runner = CountingRunner(delayNanoseconds: 20_000_000, handler: healthyHandler(cellar: s.fixture.cellar))
    let codex = toolDetection(s, version: "0.162.1")
    let results = await UpdateProbeCoordinator.run(
        subjects: [probeSubject(npmDiagnostic(DetectedTool(
            displayName: "OpenCode", executableName: "opencode", state: .notInstalled,
            entryPath: nil, resolvedPath: nil, source: "–", version: nil
        )), id: "opencode"), probeSubject(codex, id: "codex")],
        environment: m6Environment(pathEntries: [s.fixture.binDirectory]),
        mode: .checkUpdates, runner: runner, cacheURL: s.url, now: { s.clockValue }
    )
    #expect(results.map(\.registryID) == ["opencode", "codex"])
    #expect(results.last?.status == .upToDate(installed: Version("0.162.1"), latest: Version("0.162.1_1")))
}

@Test func overlappingRefreshCallsShareOneManagerBatchAdmission() async throws {
    let s = try scenario("overlapping-refresh")
    let firstEntered = OneShotSignal()
    let releaseFirst = OneShotSignal()
    let secondQueued = OneShotSignal()
    let handler = healthyHandler(cellar: s.fixture.cellar)
    let runner = ControlledRunner(entered: firstEntered, release: releaseFirst, handler: handler)
    let environment = m6Environment(pathEntries: [s.fixture.binDirectory])
    let subjects = [probeSubject(toolDetection(s, version: "0.162.1"), id: "codex")]
    let secondCache = URL(fileURLWithPath: s.url.path + ".second")

    let first = Task {
        await UpdateProbeCoordinator.run(
            subjects: subjects, environment: environment, mode: .refresh,
            runner: runner, cacheURL: s.url, now: { s.clockValue }
        )
    }
    await firstEntered.wait()
    let second = Task {
        // R05: the whole optional stage is admitted first, so the second run queues at the stage
        // gate — before Homebrew's inner batch gate, before any manager and before any cache read.
        await UpdateProbeCoordinatorTestHooks.observingStageAdmissionQueue({
            Task { await secondQueued.signal() }
        }) {
            await UpdateProbeCoordinator.run(
                subjects: subjects, environment: environment, mode: .refresh,
                runner: runner, cacheURL: secondCache, now: { s.clockValue }
            )
        }
    }
    await secondQueued.wait()

    #expect(runner.invocationCount == 1)
    await releaseFirst.signal()
    let firstResults = await first.value
    let secondResults = await second.value

    #expect(runner.invocationCount == 6)
    #expect(runner.maximumConcurrentInvocations == 1)
    #expect(firstResults.first?.status == .upToDate(installed: Version("0.162.1"), latest: Version("0.162.1_1")))
    #expect(secondResults.first?.status == .upToDate(installed: Version("0.162.1"), latest: Version("0.162.1_1")))
}

@Test func directPublicBatchesShareTheSameAdmissionGate() async throws {
    let s = try scenario("overlapping-direct-batches")
    let firstEntered = OneShotSignal()
    let releaseFirst = OneShotSignal()
    let secondQueued = OneShotSignal()
    let runner = ControlledRunner(
        entered: firstEntered,
        release: releaseFirst,
        handler: healthyHandler(cellar: s.fixture.cellar)
    )
    let manager = HomebrewManager(entryPath: s.fixture.brewPath, canonicalTarget: s.fixture.brewPath)
    let environment = m6Environment(pathEntries: [s.fixture.binDirectory])

    let first = Task {
        await HomebrewUpdateProbe.runBatch(
            manager: manager, formulas: ["codex"], environment: environment, runner: runner
        )
    }
    await firstEntered.wait()
    let second = Task {
        await HomebrewUpdateProbeTestHooks.observingAdmissionQueue({
            Task { await secondQueued.signal() }
        }) {
            await HomebrewUpdateProbe.runBatch(
                manager: manager, formulas: ["codex"], environment: environment, runner: runner
            )
        }
    }
    await secondQueued.wait()
    #expect(runner.invocationCount == 1)

    await releaseFirst.signal()
    let firstResult = await first.value
    let secondResult = await second.value
    #expect((try? firstResult.get())?.queryCount == 3)
    #expect((try? secondResult.get())?.queryCount == 3)
    #expect(runner.invocationCount == 6)
    #expect(runner.maximumConcurrentInvocations == 1)
}

@Test func cancellationWhileWaitingLaunchesNoCommandsAndDoesNotCache() async throws {
    let s = try scenario("cancel-admission")
    let firstEntered = OneShotSignal()
    let releaseFirst = OneShotSignal()
    let secondQueued = OneShotSignal()
    let firstRunner = ControlledRunner(
        entered: firstEntered,
        release: releaseFirst,
        handler: healthyHandler(cellar: s.fixture.cellar)
    )
    let secondRunner = CountingRunner(handler: healthyHandler(cellar: s.fixture.cellar))
    let environment = m6Environment(pathEntries: [s.fixture.binDirectory])
    let subjects = [probeSubject(toolDetection(s, version: "0.162.1"), id: "codex")]
    let secondCache = URL(fileURLWithPath: s.url.path + ".cancelled")

    let first = Task {
        await UpdateProbeCoordinator.run(
            subjects: subjects, environment: environment, mode: .refresh,
            runner: firstRunner, cacheURL: s.url, now: { s.clockValue }
        )
    }
    await firstEntered.wait()
    let second = Task {
        // R05: cancelled while waiting for the complete stage, so no manager of either kind is
        // launched and neither metadata document is written.
        await UpdateProbeCoordinatorTestHooks.observingStageAdmissionQueue({
            Task { await secondQueued.signal() }
        }) {
            await UpdateProbeCoordinator.run(
                subjects: subjects, environment: environment, mode: .refresh,
                runner: secondRunner, cacheURL: secondCache, now: { s.clockValue }
            )
        }
    }
    await secondQueued.wait()
    second.cancel()
    let cancelledResults = await second.value

    #expect(secondRunner.invocationCount == 0)
    #expect(cancelledResults.first?.status == .unknown(installed: Version("0.162.1"), reason: .probeFailed))
    #expect(FileManager.default.fileExists(atPath: secondCache.path) == false)

    await releaseFirst.signal()
    _ = await first.value
    let recovered = CountingRunner(handler: healthyHandler(cellar: s.fixture.cellar))
    let recoveryResults = await UpdateProbeCoordinator.run(
        subjects: subjects, environment: environment, mode: .refresh,
        runner: recovered, cacheURL: secondCache, now: { s.clockValue }
    )
    #expect(recovered.invocationCount == 3)
    #expect(recoveryResults.first?.status.isVerifiedComparison == true)
}

@Test func cancellationDuringFirstOrFinalQueryRejectsLateSuccessAndReleasesAdmission() async throws {
    for heldInvocation in [1, 3] {
        let s = try scenario("cancel-query-\(heldInvocation)")
        let entered = OneShotSignal()
        let release = OneShotSignal()
        let runner = ControlledRunner(
            heldInvocation: heldInvocation,
            entered: entered,
            release: release,
            handler: healthyHandler(cellar: s.fixture.cellar)
        )
        let environment = m6Environment(pathEntries: [s.fixture.binDirectory])
        let subjects = [probeSubject(toolDetection(s, version: "0.162.1"), id: "codex")]
        let task = Task {
            await UpdateProbeCoordinator.run(
                subjects: subjects, environment: environment, mode: .refresh,
                runner: runner, cacheURL: s.url, now: { s.clockValue }
            )
        }
        await entered.wait()
        task.cancel()
        await release.signal()
        let results = await task.value

        #expect(runner.invocationCount == heldInvocation)
        #expect(results.first?.status == .unknown(installed: Version("0.162.1"), reason: .probeFailed))
        #expect(results.first?.provenance == UpdateProvenance.none)
        #expect(FileManager.default.fileExists(atPath: s.url.path) == false)

        let followup = CountingRunner(handler: healthyHandler(cellar: s.fixture.cellar))
        let next = await UpdateProbeCoordinator.run(
            subjects: subjects, environment: environment, mode: .refresh,
            runner: followup, cacheURL: URL(fileURLWithPath: s.url.path + ".followup"),
            now: { s.clockValue }
        )
        #expect(followup.invocationCount == 3)
        #expect(next.first?.status.isVerifiedComparison == true)
    }
}

@Test func queuedBatchRevalidatesSelectedEntryAndManagerBeforeLaunching() async throws {
    for replacement in ["selection", "manager"] {
        let holder = try scenario("queue-holder-\(replacement)")
        let waiting = try scenario("queue-waiting-\(replacement)")
        let firstEntered = OneShotSignal()
        let releaseFirst = OneShotSignal()
        let queued = OneShotSignal()
        let holderRunner = ControlledRunner(
            entered: firstEntered,
            release: releaseFirst,
            handler: healthyHandler(cellar: holder.fixture.cellar)
        )
        let holderEnvironment = m6Environment(pathEntries: [holder.fixture.binDirectory])
        let holderSubjects = [probeSubject(toolDetection(holder, version: "0.162.1"), id: "holder")]
        let first = Task {
            await UpdateProbeCoordinator.run(
                subjects: holderSubjects, environment: holderEnvironment, mode: .refresh,
                runner: holderRunner, cacheURL: holder.url, now: { holder.clockValue }
            )
        }
        await firstEntered.wait()

        let selectedEntry = URL(fileURLWithPath: waiting.fixture.binDirectory).appendingPathComponent("codex").path
        let waitingDiagnostic = toolDetection(
            waiting, version: "0.162.1", path: selectedEntry, target: waiting.codexKeg
        )
        let waitingSubjects = [probeSubject(waitingDiagnostic, id: "waiting")]
        let waitingEnvironment = m6Environment(pathEntries: [waiting.fixture.binDirectory])
        let waitingRunner = CountingRunner(handler: healthyHandler(cellar: waiting.fixture.cellar))
        let waitingTask = Task {
            // R05: the waiting run is queued for the whole optional stage, so it performs no
            // manager work of either kind until it is admitted and revalidated.
            await UpdateProbeCoordinatorTestHooks.observingStageAdmissionQueue({
                Task { await queued.signal() }
            }) {
                await UpdateProbeCoordinator.run(
                    subjects: waitingSubjects, environment: waitingEnvironment, mode: .refresh,
                    runner: waitingRunner, cacheURL: waiting.url, now: { waiting.clockValue }
                )
            }
        }
        await queued.wait()

        if replacement == "selection" {
            let replacementTarget = URL(fileURLWithPath: waiting.fixture.cellar)
                .appendingPathComponent("codex/0.162.1_2/bin/codex").path
            try createScratchExecutable(at: replacementTarget)
            mutateSelectedEntry(selectedEntry, replacementTarget: replacementTarget, mutation: .retargeted)
        } else {
            try Data("#!/bin/sh\necho replaced-manager\nexit 0\n".utf8)
                .write(to: URL(fileURLWithPath: waiting.fixture.brewPath))
        }

        await releaseFirst.signal()
        _ = await first.value
        let waitingResults = await waitingTask.value
        #expect(waitingRunner.invocationCount == 0)
        #expect(waitingResults.first?.status == .unknown(installed: Version("0.162.1"), reason: .identityUnverified))
        #expect(FileManager.default.fileExists(atPath: waiting.url.path) == false)
    }
}

@Test func admissionIsReleasedAfterMalformedAndProcessFailure() async throws {
    let s = try scenario("admission-release-failures")
    let manager = HomebrewManager(entryPath: s.fixture.brewPath, canonicalTarget: s.fixture.brewPath)
    let environment = m6Environment(pathEntries: [s.fixture.binDirectory])
    let cases: [(CommandOutcome, HomebrewBatchError)] = [
        (.success(Data("not a cellar path\n".utf8)), .invalidOutput),
        (.failure(.spawnFailure), .commandFailed(.spawnFailure)),
        (.failure(.nonzeroExit), .commandFailed(.nonzeroExit)),
    ]

    for (failedOutcome, expectedError) in cases {
        let failed = await HomebrewUpdateProbe.runBatch(
            manager: manager, formulas: ["codex"], environment: environment,
            runner: CountingRunner { _ in failedOutcome }
        )
        #expect(failed == .failure(expectedError))
        let healthy = await HomebrewUpdateProbe.runBatch(
            manager: manager, formulas: ["codex"], environment: environment,
            runner: CountingRunner(handler: healthyHandler(cellar: s.fixture.cellar))
        )
        #expect((try? healthy.get())?.queryCount == 3)
    }
}

@Test func foreignCellarSubstringNeverBorrowsAHomebrewCacheIdentity() async throws {
    // A selected executable under a foreign "/Cellar/" path must not be cached or probed as Homebrew.
    let s = try scenario("foreign-substring")
    let runner = CountingRunner(handler: healthyHandler(cellar: s.fixture.cellar))
    let foreign = s.fixture.prefix.deletingLastPathComponent()
        .appendingPathComponent("other/Cellar/codex/0.162.1_1/bin/codex").path
    try createScratchExecutable(at: foreign)
    let selectedEntry = URL(fileURLWithPath: s.fixture.binDirectory).appendingPathComponent("codex").path
    try FileManager.default.removeItem(atPath: selectedEntry)
    try FileManager.default.createSymbolicLink(atPath: selectedEntry, withDestinationPath: foreign)
    let results = await UpdateProbeCoordinator.run(
        subjects: [probeSubject(toolDetection(s, version: "0.162.1", path: selectedEntry, target: foreign), id: "codex")],
        environment: m6Environment(pathEntries: [s.fixture.binDirectory]),
        mode: .checkUpdates,
        runner: runner,
        cacheURL: s.url,
        now: { s.clockValue }
    )
    // The status must come from ownership verification, never from a substring-derived identity.
    #expect(runner.arguments == [["--cellar"]])
    #expect(runner.invocationCount == 1)
    #expect(results.first?.status == .unknown(installed: Version("0.162.1"), reason: .managerMismatch))
    // A foreign target produces no cached Homebrew metadata for a later lookup.
    #expect(FileManager.default.fileExists(atPath: s.url.path) == false)
}

@Test func successfulUpdateAvailableMetadataIsCachedNotReprobedEveryScan() async throws {
    // Regression: a validated, successful updateAvailable result must be cached like upToDate.
    let s = try scenario("cache-update")
    let stale: @Sendable ([String]) -> CommandOutcome = { arguments in
        switch arguments.first {
        case "--cellar": .success(Data("\(s.fixture.cellar)\n".utf8))
        case "info": .success(infoJSON([(name: "codex", stable: "0.162.1", revision: 2, installed: ["0.162.1_1"])]))
        default: .success(outdatedJSON([(name: "codex", current: "0.162.1_2", installed: ["0.162.1_1"])]))
        }
    }
    let env = m6Environment(pathEntries: [s.fixture.binDirectory])
    let subjects = [probeSubject(toolDetection(s, version: "0.162.1"), id: "codex")]

    let first = await UpdateProbeCoordinator.run(
        subjects: subjects, environment: env, mode: .checkUpdates,
        runner: CountingRunner(handler: stale), cacheURL: s.url, now: { s.clockValue }
    )
    #expect(first.first?.status == .updateAvailable(installed: Version("0.162.1"), latest: Version("0.162.1_2")))

    let second = CountingRunner(handler: stale)
    let again = await UpdateProbeCoordinator.run(
        subjects: subjects, environment: env, mode: .checkUpdates,
        runner: second, cacheURL: s.url, now: { s.clockValue.addingTimeInterval(60) }
    )
    #expect(second.invocationCount == 0) // served from cache, no manager query
    #expect(again.first?.provenance == .cache(observedAt: s.clockValue))
}

@Test func changedManagerExecutableInvalidatesTheCachedIdentity() async throws {
    // Regression: replacing the brew executable (new size/mtime) must not reuse cached metadata.
    let s = try scenario("manager-changed")
    let env = m6Environment(pathEntries: [s.fixture.binDirectory])
    let subjects = [probeSubject(toolDetection(s, version: "0.162.1"), id: "codex")]
    _ = await UpdateProbeCoordinator.run(
        subjects: subjects, environment: env, mode: .checkUpdates,
        runner: CountingRunner(handler: healthyHandler(cellar: s.fixture.cellar)),
        cacheURL: s.url, now: { s.clockValue }
    )

    // Rewrite the manager with different content (size and modification time both change).
    try Data("#!/bin/sh\necho changed-manager-build-with-more-bytes\n".utf8)
        .write(to: URL(fileURLWithPath: s.fixture.brewPath))
    try FileManager.default.setAttributes(
        [.modificationDate: s.clockValue.addingTimeInterval(120)],
        ofItemAtPath: s.fixture.brewPath
    )

    let after = CountingRunner(handler: healthyHandler(cellar: s.fixture.cellar))
    let results = await UpdateProbeCoordinator.run(
        subjects: subjects, environment: env, mode: .checkUpdates,
        runner: after, cacheURL: s.url, now: { s.clockValue.addingTimeInterval(180) }
    )
    #expect(after.invocationCount == 3) // cache identity changed: fresh probe, not reuse
    #expect(results.first?.provenance == .freshProbe(observedAt: s.clockValue.addingTimeInterval(180)))
}

private enum SelectedEntryMutation: CaseIterable, Sendable {
    case removed
    case brokenLink
    case directoryReplacement
    case retargeted
}

private func createScratchExecutable(at path: String) throws {
    let url = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("#!/bin/sh\necho codex 0.162.1\n".utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
}

private func mutateSelectedEntry(_ path: String, replacementTarget: String, mutation: SelectedEntryMutation) {
    try? FileManager.default.removeItem(atPath: path)
    switch mutation {
    case .removed:
        break
    case .brokenLink:
        try? FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: path + ".missing")
    case .directoryReplacement:
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    case .retargeted:
        try? FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: replacementTarget)
    }
}

private func offPathDiagnostic(_ s: Scenario, entryPath: String, target: String) -> ToolPathDiagnostic {
    let tool = DetectedTool(
        displayName: "Codex", executableName: "codex", state: .installedNotOnPath,
        entryPath: entryPath, resolvedPath: target, source: "brew", version: "0.162.1"
    )
    let candidate = PathCandidateObservation(
        origin: .extraRoot(index: 0, directoryText: URL(fileURLWithPath: entryPath).deletingLastPathComponent().path),
        entryPath: entryPath, kind: .executableSymlink, canonicalTarget: target
    )
    return ToolPathDiagnostic(
        detectedTool: tool, pathCandidates: [], firstLiveCandidate: nil, targetGroups: [],
        repeatedPathSlotCount: 0, sameTargetAliasCount: 0,
        selection: .offPath(candidate: candidate, root: URL(fileURLWithPath: entryPath).deletingLastPathComponent().path),
        shadowedInstallationCount: 0,
        installationVersions: []
    )
}

private func replacingEnvironmentValue(_ environment: ShellEnvironment, key: String, value: String) -> ShellEnvironment {
    var raw = environment.raw
    raw[key] = value
    return ShellEnvironment(
        shellPath: environment.shellPath,
        pathEntries: environment.pathEntries,
        pathJoined: environment.pathJoined,
        raw: raw,
        isDegraded: environment.isDegraded
    )
}

@Test func selectedEntryMutationDuringFinalQueryNeverPublishesOrPersistsVerifiedStatus() async throws {
    for mutation in SelectedEntryMutation.allCases {
        let s = try scenario("selected-\(mutation)")
        let selectedEntry = URL(fileURLWithPath: s.fixture.binDirectory).appendingPathComponent("codex").path
        let replacementTarget = URL(fileURLWithPath: s.fixture.cellar)
            .appendingPathComponent("codex/0.162.1_2/bin/codex").path
        try createScratchExecutable(at: replacementTarget)
        let original = toolDetection(s, version: "0.162.1", path: selectedEntry, target: s.codexKeg)
        let subject = probeSubject(original, id: "codex")
        let cellar = s.fixture.cellar
        let info = infoJSON([(name: "codex", stable: "0.162.1", revision: 1, installed: ["0.162.1_1"])])
        let runner = CountingRunner { arguments -> CommandOutcome in
            switch arguments.first {
            case "--cellar": return .success(Data("\(cellar)\n".utf8))
            case "info": return .success(info)
            default:
                mutateSelectedEntry(selectedEntry, replacementTarget: replacementTarget, mutation: mutation)
                return .success(outdatedJSON([]))
            }
        }
        let results = await UpdateProbeCoordinator.run(
            subjects: [subject], environment: m6Environment(pathEntries: [s.fixture.binDirectory]),
            mode: .checkUpdates, runner: runner, cacheURL: s.url, now: { s.clockValue }
        )
        let result = results[0]
        #expect(result.status == .unknown(installed: Version("0.162.1"), reason: .identityUnverified))
        #expect(result.provenance == .none)
        #expect(result.selectedEntryPath == selectedEntry)
        #expect(result.selectedTarget == s.codexKeg)
        #expect(result.localVersion == "0.162.1")
        #expect(result.diagnostic == original)
        #expect(FileManager.default.fileExists(atPath: s.url.path) == false)
    }
}

@Test func offPathSelectionGetsTheSamePostProbeRevalidation() async throws {
    let s = try scenario("offpath-revalidation")
    let offPathRoot = s.fixture.prefix.appendingPathComponent("off-path", isDirectory: true)
    try FileManager.default.createDirectory(at: offPathRoot, withIntermediateDirectories: true)
    let selectedEntry = offPathRoot.appendingPathComponent("codex").path
    try FileManager.default.createSymbolicLink(atPath: selectedEntry, withDestinationPath: s.codexKeg)
    let diagnostic = offPathDiagnostic(s, entryPath: selectedEntry, target: s.codexKeg)
    let cellar = s.fixture.cellar
    let info = infoJSON([(name: "codex", stable: "0.162.1", revision: 1, installed: ["0.162.1_1"])])
    let runner = CountingRunner { arguments -> CommandOutcome in
        switch arguments.first {
        case "--cellar": return .success(Data("\(cellar)\n".utf8))
        case "info": return .success(info)
        default:
            try? FileManager.default.removeItem(atPath: selectedEntry)
            return .success(outdatedJSON([]))
        }
    }
    let results = await UpdateProbeCoordinator.run(
        subjects: [probeSubject(diagnostic, id: "codex")],
        environment: m6Environment(pathEntries: [s.fixture.binDirectory]),
        mode: .checkUpdates, runner: runner, cacheURL: s.url, now: { s.clockValue }
    )
    #expect(results[0].status == .unknown(installed: Version("0.162.1"), reason: .identityUnverified))
    #expect(results[0].diagnostic == diagnostic)
    #expect(FileManager.default.fileExists(atPath: s.url.path) == false)
}

@Test func cachedStatusIsNotPublishedAfterSelectedEntryDisappears() async throws {
    let s = try scenario("cache-selected-removed")
    let selectedEntry = URL(fileURLWithPath: s.fixture.binDirectory).appendingPathComponent("codex").path
    let subject = probeSubject(toolDetection(s, version: "0.162.1", path: selectedEntry, target: s.codexKeg), id: "codex")
    let env = m6Environment(pathEntries: [s.fixture.binDirectory])
    _ = await UpdateProbeCoordinator.run(
        subjects: [subject], environment: env, mode: .checkUpdates,
        runner: CountingRunner(handler: healthyHandler(cellar: s.fixture.cellar)),
        cacheURL: s.url, now: { s.clockValue }
    )
    try FileManager.default.removeItem(atPath: selectedEntry)

    let unusedRunner = CountingRunner(handler: healthyHandler(cellar: s.fixture.cellar))
    let results = await UpdateProbeCoordinator.run(
        subjects: [subject], environment: env, mode: .checkUpdates,
        runner: unusedRunner, cacheURL: s.url, now: { s.clockValue.addingTimeInterval(60) }
    )
    #expect(unusedRunner.invocationCount == 0)
    #expect(results[0].status == .unknown(installed: Version("0.162.1"), reason: .identityUnverified))
    #expect(results[0].provenance == .none)
}

@Test func replacedManagerDuringFinalQueryCannotOwnTheOldMetadata() async throws {
    let s = try scenario("manager-during-query")
    let managerPath = s.fixture.brewPath
    let original = toolDetection(s, version: "0.162.1")
    let cellar = s.fixture.cellar
    let info = infoJSON([(name: "codex", stable: "0.162.1", revision: 1, installed: ["0.162.1_1"])])
    let runner = CountingRunner { arguments -> CommandOutcome in
        switch arguments.first {
        case "--cellar": return .success(Data("\(cellar)\n".utf8))
        case "info": return .success(info)
        default:
            try? Data("#!/bin/sh\nexit 7\n".utf8).write(to: URL(fileURLWithPath: managerPath))
            return .success(outdatedJSON([]))
        }
    }
    let results = await UpdateProbeCoordinator.run(
        subjects: [probeSubject(original, id: "codex")],
        environment: m6Environment(pathEntries: [s.fixture.binDirectory]), mode: .checkUpdates,
        runner: runner, cacheURL: s.url, now: { s.clockValue }
    )
    #expect(results[0].status == .unknown(installed: Version("0.162.1"), reason: .identityUnverified))
    #expect(results[0].managerTarget == nil)
    #expect(FileManager.default.fileExists(atPath: s.url.path) == false)
}

@Test func effectiveEnvironmentAndWorkingDirectoryEachInvalidateCoordinatorCacheKeys() async throws {
    let s = try scenario("context-fingerprint")
    let env = m6Environment(pathEntries: [s.fixture.binDirectory])
    let subjects = [probeSubject(toolDetection(s, version: "0.162.1"), id: "codex")]
    let initialRunner = CountingRunner(handler: healthyHandler(cellar: s.fixture.cellar))
    _ = await UpdateProbeCoordinator.run(
        subjects: subjects, environment: env, mode: .checkUpdates, runner: initialRunner,
        cacheURL: s.url, now: { s.clockValue }
    )
    #expect(initialRunner.invocationCount == 3)
    let stableRunner = CountingRunner(handler: healthyHandler(cellar: s.fixture.cellar))
    let stable = await UpdateProbeCoordinator.run(
        subjects: subjects, environment: env, mode: .checkUpdates, runner: stableRunner,
        cacheURL: s.url, now: { s.clockValue.addingTimeInterval(30) }
    )
    #expect(stableRunner.invocationCount == 0)
    #expect(stable.first?.provenance == .cache(observedAt: s.clockValue))

    let cwd = s.fixture.prefix.deletingLastPathComponent().appendingPathComponent("other-working-directory")
    try FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)
    let variants: [(String, ShellEnvironment, String)] = [
        ("home", replacingEnvironmentValue(env, key: "HOME", value: "/synthetic/other-home"), FileManager.default.currentDirectoryPath),
        ("api-domain", replacingEnvironmentValue(env, key: "HOMEBREW_API_DOMAIN", value: "https://api.invalid.example"), FileManager.default.currentDirectoryPath),
        ("cwd", env, cwd.path),
    ]
    for (label, changedEnvironment, changedDirectory) in variants {
        let variantURL = URL(fileURLWithPath: s.url.path + ".\(label)")
        try FileManager.default.copyItem(at: s.url, to: variantURL)
        let runner = CountingRunner(handler: healthyHandler(cellar: s.fixture.cellar))
        let results = await UpdateProbeCoordinator.run(
            subjects: subjects, environment: changedEnvironment, mode: .checkUpdates,
            runner: runner, cacheURL: variantURL, currentDirectory: changedDirectory,
            now: { s.clockValue.addingTimeInterval(30) }
        )
        #expect(runner.invocationCount == 3)
        #expect(results.first?.provenance == .freshProbe(observedAt: s.clockValue.addingTimeInterval(30)))
    }
}

@Test func actualSubprocessWorkingDirectoryControlsCoordinatorCacheContext() throws {
    let scenario = try scenario("actual-cwd-cache-context")
    let root = scenario.fixture.prefix.deletingLastPathComponent()
    let firstDirectory = root.appendingPathComponent("first-working-directory", isDirectory: true)
    let secondDirectory = root.appendingPathComponent("second-working-directory", isDirectory: true)
    try FileManager.default.createDirectory(at: firstDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)

    let bin = URL(fileURLWithPath: scenario.fixture.binDirectory, isDirectory: true)
    let cellar = URL(fileURLWithPath: scenario.fixture.cellar, isDirectory: true)
    let target = URL(fileURLWithPath: scenario.codexKeg)
    let selectedEntry = bin.appendingPathComponent("codex")

    let verifierSource = #"""
    import AgentLensCore
    import Darwin
    import Foundation

    private final class Runner: UpdateCommandRunner, @unchecked Sendable {
        private let lock = NSLock()
        private var storedCount = 0
        private var storedInputsMatch = true
        private let managerPath: String
        private let binPath: String
        private let cellarPath: String

        init(managerPath: String, binPath: String, cellarPath: String) {
            self.managerPath = managerPath
            self.binPath = binPath
            self.cellarPath = cellarPath
        }

        private func record(_ executablePath: String, _ arguments: [String], _ environment: [String: String]) -> Int {
            lock.lock()
            defer { lock.unlock() }
            storedCount += 1
            let expected = [
                ["--cellar"],
                ["info", "--json=v2", "--formula", "codex"],
                ["outdated", "--json=v2", "--formula"],
            ]
            let ordinal = storedCount - 1
            let valid = ordinal < expected.count
                && arguments == expected[ordinal]
                && executablePath == managerPath
                && environment["PATH"] == binPath
                && environment["HOME"] == "/synthetic/home"
                && environment["HOMEBREW_NO_AUTO_UPDATE"] == "1"
                && environment["HOMEBREW_NO_ANALYTICS"] == "1"
            storedInputsMatch = storedInputsMatch && valid
            return ordinal
        }

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return storedCount
        }

        var inputsMatch: Bool {
            lock.lock()
            defer { lock.unlock() }
            return storedInputsMatch
        }

        func run(
            executablePath: String,
            arguments: [String],
            environment: [String: String],
            timeout: TimeInterval
        ) async -> CommandOutcome {
            _ = record(executablePath, arguments, environment)
            switch arguments.first {
            case "--cellar": return .success(Data("\(cellarPath)\n".utf8))
            case "info":
                return .success(Data("{\"formulae\":[{\"name\":\"codex\",\"full_name\":\"codex\",\"revision\":1,\"versions\":{\"stable\":\"0.162.1\"},\"installed\":[{\"version\":\"0.162.1_1\"}]}],\"casks\":[]}".utf8))
            case "outdated": return .success(Data("{\"formulae\":[],\"casks\":[]}".utf8))
            default: return .failure(.nonzeroExit)
            }
        }
    }

    @main
    struct ContextVerifier {
        static func main() async {
            let args = CommandLine.arguments
            guard args.count == 7 else { exit(2) }
            let cacheURL = URL(fileURLWithPath: args[1])
            let binPath = args[2]
            let cellarPath = args[3]
            let managerPath = args[4]
            let selectedEntry = args[5]
            let selectedTarget = args[6]
            let environment = ShellEnvironment(
                shellPath: "/bin/sh", pathEntries: [binPath], pathJoined: binPath,
                raw: ["PATH": binPath, "HOME": "/synthetic/home"], isDegraded: false
            )
            let detector = ToolDetector(
                displayName: "Codex", executableName: "codex",
                versionQuerySpecification: .standard,
                versionQuery: { _, _, _, _ in "0.162.1" }
            )
            let diagnostic = PathDiagnosticsScanner.scan(detector: detector, environment: environment)
            let definition = try! DetectorDefinition(
                id: "codex", displayName: "Codex", executableName: "codex",
                extraSearchRoots: [], fixture: nil, category: .aiAgent, packages: [],
                informationURL: nil, uninstallInstructionsURL: nil, versionQuery: .standard
            )
            let subject = UpdateProbeSubject(definition: definition, diagnostic: diagnostic)
            let now = Date(timeIntervalSince1970: 1_800_000_000.5)

            let firstRunner = Runner(managerPath: managerPath, binPath: binPath, cellarPath: cellarPath)
            let first = await UpdateProbeCoordinator.run(
                subjects: [subject], environment: environment, mode: .checkUpdates,
                runner: firstRunner, cacheURL: cacheURL, now: { now }
            )
            let secondRunner = Runner(managerPath: managerPath, binPath: binPath, cellarPath: cellarPath)
            let second = await UpdateProbeCoordinator.run(
                subjects: [subject], environment: environment, mode: .checkUpdates,
                runner: secondRunner, cacheURL: cacheURL, now: { now }
            )
            let identityMatches = first.first?.selectedTarget == selectedTarget
                && first.first?.managerEntryPath == managerPath
                && second.first?.selectedTarget == selectedTarget
                && second.first?.managerEntryPath == managerPath
                && first.first?.status == second.first?.status
            let cacheHit = second.first?.provenance == .cache(observedAt: now)
                && second.first?.status == .upToDate(installed: Version("0.162.1"), latest: Version("0.162.1_1"))
            print("counts=\(firstRunner.count),\(secondRunner.count);inputs=\(firstRunner.inputsMatch && secondRunner.inputsMatch);identity=\(identityMatches);cacheHit=\(cacheHit);cwd=\(FileManager.default.currentDirectoryPath)")
        }
    }
    """#
    let sourceURL = root.appendingPathComponent("context-verifier.swift")
    let executableURL = root.appendingPathComponent("context-verifier")
    let cacheURL = root.appendingPathComponent("shared-cache.json")
    try Data(verifierSource.utf8).write(to: sourceURL)

    let products = try selectAgentLensCoreProducts(
        environment: ProcessInfo.processInfo.environment,
        arguments: CommandLine.arguments,
        executablePath: Bundle.main.executableURL?.path
    )
    let compiler = Process()
    compiler.executableURL = URL(fileURLWithPath: "/usr/bin/swiftc")
    compiler.arguments = agentLensCoreCompileArguments(for: products) + [
        "-parse-as-library", sourceURL.path,
        "-o", executableURL.path,
    ]
    compiler.currentDirectoryURL = root
    let compilation = try runIsolatedProcess(compiler, captureDirectory: root, label: "context-compile")
    #expect(compilation.status == 0, "isolated coordinator verifier must compile: \(compilation.stderr)")
    guard compilation.status == 0 else { return }

    let verifierArguments = [
        cacheURL.path, bin.path, cellar.path, scenario.fixture.brewPath,
        selectedEntry.path, target.path,
    ]
    let verifierEnvironment = ["PATH": "/usr/bin:/bin", "HOME": root.path, "TMPDIR": root.path]
    for (label, workingDirectory) in [("first", firstDirectory), ("second", secondDirectory)] {
        let verifier = Process()
        verifier.executableURL = executableURL
        verifier.arguments = verifierArguments
        verifier.environment = verifierEnvironment
        verifier.currentDirectoryURL = workingDirectory
        let result = try runIsolatedProcess(verifier, captureDirectory: root, label: "context-\(label)")
        // The child reports `getcwd()`, which on this platform returns the PHYSICAL pathname
        // (`/private/var/...`), not the inherited alias spelling the fixture passed in
        // (`/var/...`). Compare physical identity, keeping every other field exact. A raw string
        // comparison here fails under the ordinary TMPDIR for a spelling difference only.
        // REQUIRE the physical resolution: silently falling back to the alias spelling would accept
        // an unresolved cwd. `getcwd()` returns the physical pathname on this platform.
        let physicalWorkingDirectory = try #require(
            FileIdentityObserver.physicalPath(workingDirectory.path),
            "the working directory must resolve physically for this context check"
        )
        let expected = "counts=3,0;inputs=true;identity=true;cacheHit=true;cwd=\(physicalWorkingDirectory)\n"
        #expect(result.status == 0, "isolated coordinator verifier failed: \(result.stderr)")
        #expect(result.stderr.isEmpty)
        #expect(result.stdout == expected)
    }
}

@Test func tappedFormulaIdentitySurvivesMetadataRoundTripWithoutQueries() async throws {
    let s = try scenario("tapped-cache")
    let tappedName = "hazem/homebrew-tools/codex"
    let info = Data("""
    {"formulae":[{"name":"codex","full_name":"\(tappedName)","tap":"hazem/homebrew-tools","revision":1,"versions":{"stable":"0.162.1"},"installed":[{"version":"0.162.1_1"}]}],"casks":[]}
    """.utf8)
    let cellar = s.fixture.cellar
    let handler: @Sendable ([String]) -> CommandOutcome = { arguments in
        switch arguments.first {
        case "--cellar": return .success(Data("\(cellar)\n".utf8))
        case "info": return .success(info)
        default: return .success(outdatedJSON([]))
        }
    }
    let subjects = [probeSubject(toolDetection(s, version: "0.162.1"), id: "codex")]
    let firstRunner = CountingRunner(handler: handler)
    let first = await UpdateProbeCoordinator.run(
        subjects: subjects, environment: m6Environment(pathEntries: [s.fixture.binDirectory]),
        mode: .checkUpdates, runner: firstRunner, cacheURL: s.url, now: { s.clockValue }
    )
    #expect(firstRunner.invocationCount == 3)
    #expect(first.first?.formulaStem == "codex")
    #expect(first.first?.fullFormulaName == tappedName)
    #expect(first.first?.managerCellar == s.fixture.cellar)
    let persisted = try Data(contentsOf: s.url)
    let document = try JSONDecoder().decode(UpdateMetadataDocument.self, from: persisted)
    #expect(document.entries.count == 1)
    #expect(document.entries.first?.fullFormulaName == tappedName)

    let secondRunner = CountingRunner(handler: handler)
    let second = await UpdateProbeCoordinator.run(
        subjects: subjects, environment: m6Environment(pathEntries: [s.fixture.binDirectory]),
        mode: .checkUpdates, runner: secondRunner, cacheURL: s.url,
        now: { s.clockValue.addingTimeInterval(60) }
    )
    #expect(secondRunner.invocationCount == 0)
    #expect(second.first?.fullFormulaName == tappedName)
    #expect(second.first?.provenance == .cache(observedAt: s.clockValue))
}

@Test func registryIdentityIsIndependentOfSharedOrRenamedDisplayLabels() async throws {
    let s = try scenario("registry-identity")
    let diagnostic = toolDetection(s, version: "0.162.1")
    let shared = [
        probeSubject(diagnostic, id: "registry.codex.primary", displayName: "Codex"),
        probeSubject(diagnostic, id: "registry.codex.alias", displayName: "Codex"),
    ]
    let runner = CountingRunner(handler: healthyHandler(cellar: s.fixture.cellar))
    let results = await UpdateProbeCoordinator.run(
        subjects: shared, environment: m6Environment(pathEntries: [s.fixture.binDirectory]),
        mode: .localOnly, runner: runner, cacheURL: s.url, now: { s.clockValue }
    )
    #expect(runner.invocationCount == 0)
    #expect(results.map(\.registryID) == ["registry.codex.primary", "registry.codex.alias"])
    #expect(results.map(\.displayName) == ["Codex", "Codex"])
    #expect(results.map(\.diagnosticIndex) == [0, 1])
    #expect(results.allSatisfy { $0.diagnostic == diagnostic })

    let renamed = await UpdateProbeCoordinator.run(
        subjects: [probeSubject(diagnostic, id: "registry.codex.primary", displayName: "Codex CLI")],
        environment: m6Environment(pathEntries: [s.fixture.binDirectory]),
        mode: .localOnly, runner: runner, cacheURL: s.url, now: { s.clockValue }
    )
    #expect(renamed.first?.registryID == "registry.codex.primary")
    #expect(renamed.first?.displayName == "Codex CLI")

    let ordered = await UpdateProbeCoordinator.run(
        subjects: [
            probeSubject(diagnostic, id: "internal.codex", displayName: "Codex"),
            probeSubject(diagnostic, id: "internal.opencode", displayName: "OpenCode"),
            probeSubject(diagnostic, id: "internal.grok", displayName: "Grok"),
        ],
        environment: m6Environment(pathEntries: [s.fixture.binDirectory]),
        mode: .localOnly, runner: runner, cacheURL: s.url, now: { s.clockValue }
    )
    let rendered = UpdateScanRenderer.render(results: ordered, mode: .localOnly)
    let codexPosition = try #require(rendered.range(of: "Codex  installed")?.lowerBound)
    let openCodePosition = try #require(rendered.range(of: "OpenCode  installed")?.lowerBound)
    let grokPosition = try #require(rendered.range(of: "Grok  installed")?.lowerBound)
    #expect(codexPosition < openCodePosition && openCodePosition < grokPosition)
    #expect(!rendered.contains("internal.codex"))
}

@Test func rendererCountsOnlySelectedUpdatesAndUsesDeterministicUTC() throws {
    let s = try scenario("renderer-selected-count")
    let diagnostic = toolDetection(s, version: "0.162.1")
    let missingTool = DetectedTool(
        displayName: "Codex", executableName: "codex", state: .notInstalled,
        entryPath: nil, resolvedPath: nil, source: "–", version: nil
    )
    let missingDiagnostic = ToolPathDiagnostic(
        detectedTool: missingTool, pathCandidates: [], firstLiveCandidate: nil,
        targetGroups: [], repeatedPathSlotCount: 0, sameTargetAliasCount: 0,
        selection: .notInstalled, shadowedInstallationCount: 0,
        installationVersions: []
    )
    let inconsistentDiagnostic = ToolPathDiagnostic(
        detectedTool: diagnostic.detectedTool, pathCandidates: diagnostic.pathCandidates,
        firstLiveCandidate: diagnostic.firstLiveCandidate, targetGroups: diagnostic.targetGroups,
        repeatedPathSlotCount: diagnostic.repeatedPathSlotCount,
        sameTargetAliasCount: diagnostic.sameTargetAliasCount,
        selection: .inconsistent("synthetic inconsistent selection"),
        shadowedInstallationCount: nil,
        installationVersions: []
    )
    func result(
        id: String,
        diagnostic: ToolPathDiagnostic,
        selectedEntry: String?,
        selectedTarget: String?,
        status: VersionStatus = .updateAvailable(
            installed: Version("0.162.1"), latest: Version("0.162.1_2")
        ),
        provenance: UpdateProvenance = .none
    ) -> ToolUpdateResult {
        ToolUpdateResult(
            registryID: id, displayName: "Codex",
            diagnosticIndex: 0, diagnostic: diagnostic, localVersion: diagnostic.detectedTool.version,
            selectedEntryPath: selectedEntry, selectedTarget: selectedTarget,
            selectedKegVersion: selectedEntry == nil ? nil : "0.162.1_1",
            managerEntryPath: nil, managerTarget: nil, managerFingerprint: nil,
            managerCellar: nil, formulaStem: nil, fullFormulaName: nil,
            status: status,
            provenance: provenance
        )
    }

    let observedAt = Date(timeIntervalSince1970: 0)
    let results = [
        result(
            id: "selected", diagnostic: diagnostic,
            selectedEntry: s.codexKeg, selectedTarget: s.codexKeg,
            provenance: .freshProbe(observedAt: observedAt)
        ),
        result(
            id: "uninstalled", diagnostic: missingDiagnostic, selectedEntry: nil, selectedTarget: nil,
            status: .unknown(installed: nil, reason: .notInstalled)
        ),
        result(
            id: "inconsistent", diagnostic: inconsistentDiagnostic,
            selectedEntry: s.codexKeg, selectedTarget: s.codexKeg,
            provenance: .cache(observedAt: observedAt)
        ),
    ]
    let rendered = UpdateScanRenderer.render(results: results, mode: .checkUpdates)
    #expect(rendered.contains("1 update available"))
    #expect(rendered.contains("Codex  installed —  latest known —  unknown — not installed"))
    #expect(rendered.contains("source: Homebrew metadata; checked at 1970-01-01T00:00:00Z"))
    #expect(rendered.contains("source: Homebrew metadata cache; observed at 1970-01-01T00:00:00Z"))
    #expect(UpdateScanRenderer.timestamp(Date(timeIntervalSince1970: 0)) == "1970-01-01T00:00:00Z")
}

@Test func nestedCellarComponentsKeepTheManagerVerifiedCellarAndCacheIdentity() async throws {
    let base = try scenario("nested-cellar")
    let nestedPrefix = base.fixture.prefix.deletingLastPathComponent()
        .appendingPathComponent("Cellar/nested-prefix", isDirectory: true)
    let brewPath = nestedPrefix.appendingPathComponent("bin/brew").path
    try createScratchExecutable(at: brewPath)
    let fixture = BrewFixture(prefix: nestedPrefix)
    let target = try fixture.installKeg(formula: "codex", keg: "0.162.1_1")
    let nestedScenario = Scenario(fixture: fixture, codexKeg: target, url: base.url, clockValue: base.clockValue)
    let entry = URL(fileURLWithPath: fixture.binDirectory).appendingPathComponent("codex").path
    let subject = probeSubject(
        toolDetection(nestedScenario, version: "0.162.1", path: entry, target: target, originDirectory: fixture.binDirectory),
        id: "codex"
    )
    let environment = m6Environment(pathEntries: [fixture.binDirectory])
    let handler: @Sendable ([String]) -> CommandOutcome = { arguments in
        switch arguments {
        case ["--cellar"]: .success(Data("\(fixture.cellar)\n".utf8))
        case ["info", "--json=v2", "--formula", "codex"]:
            .success(infoJSON([(name: "codex", stable: "0.162.1", revision: 1, installed: ["0.162.1_1"])]))
        case ["outdated", "--json=v2", "--formula"]: .success(outdatedJSON([]))
        default: .failure(.nonzeroExit)
        }
    }
    let firstRunner = CountingRunner(handler: handler)
    let first = await UpdateProbeCoordinator.run(
        subjects: [subject], environment: environment, mode: .checkUpdates,
        runner: firstRunner, cacheURL: base.url, now: { base.clockValue }
    )
    #expect(firstRunner.invocationCount == 3)
    #expect(firstRunner.arguments == [
        ["--cellar"],
        ["info", "--json=v2", "--formula", "codex"],
        ["outdated", "--json=v2", "--formula"],
    ])
    #expect(first.first?.managerCellar == fixture.cellar)
    #expect(first.first?.selectedTarget == target)
    #expect(first.first?.status == .upToDate(
        installed: Version("0.162.1"), latest: Version("0.162.1_1")
    ))

    let secondRunner = CountingRunner(handler: handler)
    let second = await UpdateProbeCoordinator.run(
        subjects: [subject], environment: environment, mode: .checkUpdates,
        runner: secondRunner, cacheURL: base.url, now: { base.clockValue.addingTimeInterval(60) }
    )
    #expect(secondRunner.invocationCount == 0)
    #expect(secondRunner.arguments.isEmpty)
    #expect(second.first?.managerCellar == fixture.cellar)
    #expect(second.first?.provenance == .cache(observedAt: base.clockValue))
}

@Test func managerReportedCellarSupportsRepositorySymlinkLayoutAndZeroQueryHit() async throws {
    let s = try scenario("repository-manager-cellar")
    let repositoryBrew = s.fixture.prefix.deletingLastPathComponent()
        .appendingPathComponent("Homebrew/bin/brew").path
    try createScratchExecutable(at: repositoryBrew)
    try FileManager.default.removeItem(atPath: s.fixture.brewPath)
    try FileManager.default.createSymbolicLink(atPath: s.fixture.brewPath, withDestinationPath: repositoryBrew)

    let subject = probeSubject(toolDetection(s, version: "0.162.1"), id: "codex")
    let environment = m6Environment(pathEntries: [s.fixture.binDirectory])
    let firstRunner = CountingRunner(handler: healthyHandler(cellar: s.fixture.cellar))
    let first = await UpdateProbeCoordinator.run(
        subjects: [subject], environment: environment, mode: .checkUpdates,
        runner: firstRunner, cacheURL: s.url, now: { s.clockValue }
    )
    #expect(firstRunner.invocationCount == 3)
    #expect(first.first?.managerTarget == repositoryBrew)
    #expect(first.first?.managerCellar == s.fixture.cellar)
    #expect(first.first?.status == .upToDate(installed: Version("0.162.1"), latest: Version("0.162.1_1")))
    #expect(FileManager.default.fileExists(atPath: s.url.path))

    let secondRunner = CountingRunner(handler: healthyHandler(cellar: s.fixture.cellar))
    let second = await UpdateProbeCoordinator.run(
        subjects: [subject], environment: environment, mode: .checkUpdates,
        runner: secondRunner, cacheURL: s.url, now: { s.clockValue.addingTimeInterval(60) }
    )
    #expect(secondRunner.invocationCount == 0)
    #expect(second.first?.managerCellar == s.fixture.cellar)
    #expect(second.first?.provenance == .cache(observedAt: s.clockValue))
}

@Test func typedManagerFailuresKeepTheirEvidenceAndOpaqueExitStaysProbeFailed() async throws {
    let s = try scenario("typed-failure-reasons")
    let subject = probeSubject(toolDetection(s, version: "0.162.1"), id: "codex")
    let variants: [(CommandFailure, UnknownReason)] = [
        (.networkUnavailable, .networkUnavailable),
        (.rateLimited, .rateLimited),
        (.nonzeroExit, .probeFailed),
    ]
    for (failure, reason) in variants {
        let runner = CountingRunner { _ in .failure(failure) }
        let results = await UpdateProbeCoordinator.run(
            subjects: [subject], environment: m6Environment(pathEntries: [s.fixture.binDirectory]),
            mode: .checkUpdates, runner: runner, cacheURL: s.url, now: { s.clockValue }
        )
        #expect(runner.invocationCount == 1)
        #expect(results.first?.status == .unknown(installed: Version("0.162.1"), reason: reason))
    }
}

@Test func rendererDistinguishesOfflinePolicyTypedNetworkEvidenceAndOpaqueExit() async throws {
    let s = try scenario("renderer-reason-honesty")
    let subject = probeSubject(toolDetection(s, version: "0.162.1"), id: "codex")
    let environment = m6Environment(pathEntries: [s.fixture.binDirectory])
    let variants: [(UpdateProbeMode, CommandFailure?, String, UnknownReason)] = [
        (.offline, nil, "offline mode was requested", .networkUnavailable),
        (.checkUpdates, .networkUnavailable, "network unavailable", .networkUnavailable),
        (.refresh, .rateLimited, "rate limited", .rateLimited),
        (.checkUpdates, .nonzeroExit, "update probe failed", .probeFailed),
    ]

    for (index, variant) in variants.enumerated() {
        let (mode, failure, explanation, reason) = variant
        let runner = CountingRunner { _ in
            if let failure { return .failure(failure) }
            return healthyHandler(cellar: s.fixture.cellar)(["--cellar"])
        }
        let results = await UpdateProbeCoordinator.run(
            subjects: [subject], environment: environment, mode: mode,
            runner: runner, cacheURL: URL(fileURLWithPath: s.url.path + ".\(index)"),
            now: { s.clockValue }
        )
        let result = try #require(results.first)
        let output = UpdateScanRenderer.render(results: results, mode: mode)
        #expect(result.status == .unknown(installed: Version("0.162.1"), reason: reason))
        #expect(result.provenance == UpdateProvenance.none)
        #expect(output.contains("installed 0.162.1"))
        #expect(output.contains("latest known —  unknown — \(explanation)"))
        #expect(output.contains("0 updates available"))
        #expect(!output.contains("offline mode was requested") || mode == .offline)
        #expect(!output.contains("✓") && !output.contains("✗") && !output.contains("❌"))
        #expect(!output.contains("source: Homebrew metadata"))
    }
}

@Test func productionProcessOutcomesReachTheCoordinatorWithinTheirRealBounds() async throws {
    #expect(HomebrewUpdateProbe.queryTimeout == 10)
    var timeoutElapsed: TimeInterval = 0
    var outputLimitElapsed: TimeInterval = 0

    for behavior in ["hang-descendant", "oversized", "nonzero", "invalid-utf8"] {
        let s = try scenario("production-process-\(behavior)")
        try writeProductionProcessScript(to: s.fixture.brewPath)
        let pidMarker = s.fixture.prefix.deletingLastPathComponent().appendingPathComponent("child-\(behavior).pid")
        let markers = behavior == "hang-descendant"
            ? ["AGENT_LENS_PID_MARKER": pidMarker.path]
            : [:]
        let environment = processEnvironment(s, behavior: behavior, markers: markers)
        // Test-only deadline leaves room for a cold process launch under concurrent compilation,
        // while remaining below the unchanged ten-second production bound.
        let runner = RecordingProcessRunner(deadlineLimit: 7)
        let subjects = [probeSubject(toolDetection(s, version: "0.162.1"), id: "codex")]
        let results = await UpdateProbeCoordinator.run(
            subjects: subjects, environment: environment, mode: .refresh,
            runner: runner, cacheURL: s.url, now: { s.clockValue }
        )

        let observations = runner.observations
        let observation = try #require(observations.first)
        #expect(observations.count == 1)
        #expect(results.first?.status == .unknown(installed: Version("0.162.1"), reason: .probeFailed))
        #expect(results.first?.provenance == UpdateProvenance.none)
        #expect(results.first?.localVersion == "0.162.1")
        #expect(FileManager.default.fileExists(atPath: s.url.path) == false)

        switch behavior {
        case "hang-descendant":
            guard case .failure(.timedOut) = observation.outcome else {
                Issue.record("expected the real process bridge to report a deadline timeout")
                continue
            }
            timeoutElapsed = observation.elapsed
            let markerReady = await waitForScratchMarker(pidMarker, timeout: 3)
            guard markerReady else {
                Issue.record("timeout expired before the descendant PID marker was written")
                continue
            }
            guard let pidText = try? String(contentsOf: pidMarker, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  let childPID = pid_t(pidText)
            else {
                Issue.record("descendant PID marker was present but unreadable")
                continue
            }
            let childExited = await waitForProcessExit(childPID, timeout: 1)
            if !childExited { _ = kill(childPID, SIGKILL) }
            #expect(childExited)
        case "oversized":
            guard case .failure(.outputLimitExceeded) = observation.outcome else {
                Issue.record("expected the real process bridge to report the stdout byte limit")
                continue
            }
            outputLimitElapsed = observation.elapsed
        case "nonzero":
            #expect(observation.outcome == .failure(.nonzeroExit))
        default:
            guard case .success(let bytes) = observation.outcome else {
                Issue.record("invalid UTF-8 test did not reach the metadata parser")
                continue
            }
            #expect(bytes == Data([0xFF]))
        }
    }

    #expect(timeoutElapsed >= 5 && timeoutElapsed < 9)
    #expect(outputLimitElapsed < 5)
    #expect(timeoutElapsed > outputLimitElapsed)
}

@Test func cancellingARealHangingQueryWaitsForCleanupAndStopsTheBatch() async throws {
    let s = try scenario("cancel-real-hanging-query")
    try writeProductionProcessScript(to: s.fixture.brewPath)
    let pidMarker = s.fixture.prefix.deletingLastPathComponent().appendingPathComponent("cancelled-child.pid")
    let environment = processEnvironment(
        s, behavior: "hang-descendant", markers: ["AGENT_LENS_PID_MARKER": pidMarker.path]
    )
    let runner = RecordingProcessRunner(deadlineLimit: 7)
    let subjects = [probeSubject(toolDetection(s, version: "0.162.1"), id: "codex")]
    let task = Task {
        await UpdateProbeCoordinator.run(
            subjects: subjects, environment: environment, mode: .refresh,
            runner: runner, cacheURL: s.url, now: { s.clockValue }
        )
    }

    let markerReady = await waitForScratchMarker(pidMarker, timeout: 30)
    guard markerReady else {
        task.cancel()
        _ = await task.value
        Issue.record("hanging fixture did not establish a descendant before its deadline")
        return
    }
    task.cancel()
    let results = await task.value

    let observations = runner.observations
    let observation = try #require(observations.first)
    #expect(observations.count == 1)
    #expect(observation.outcome == .failure(.timedOut))
    #expect(observation.elapsed < 9)
    #expect(results.first?.status == .unknown(installed: Version("0.162.1"), reason: .probeFailed))
    #expect(results.first?.provenance == UpdateProvenance.none)
    #expect(FileManager.default.fileExists(atPath: s.url.path) == false)

    guard let pidText = try? String(contentsOf: pidMarker, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines),
          let childPID = pid_t(pidText)
    else {
        Issue.record("cancelled hanging fixture did not leave a readable descendant PID marker")
        return
    }
    let childExited = await waitForProcessExit(childPID, timeout: 1)
    if !childExited { _ = kill(childPID, SIGKILL) }
    #expect(childExited)
}

@Test func cancelledRealFinalQueryCannotPublishItsLateSuccessfulMetadata() async throws {
    let s = try scenario("cancel-real-final-query")
    try writeProductionProcessScript(to: s.fixture.brewPath)
    let startedMarker = s.fixture.prefix.deletingLastPathComponent().appendingPathComponent("final-query-started")
    let releaseMarker = s.fixture.prefix.deletingLastPathComponent().appendingPathComponent("final-query-release")
    let environment = processEnvironment(
        s,
        behavior: "delayed-final",
        markers: [
            "AGENT_LENS_STARTED_MARKER": startedMarker.path,
            "AGENT_LENS_RELEASE_MARKER": releaseMarker.path,
            "AGENT_LENS_FINISHED_MARKER": s.fixture.prefix.deletingLastPathComponent()
                .appendingPathComponent("final-query-finished").path,
        ]
    )
    let runner = RecordingProcessRunner(deadlineLimit: 7)
    let subjects = [probeSubject(toolDetection(s, version: "0.162.1"), id: "codex")]
    let task = Task {
        await UpdateProbeCoordinator.run(
            subjects: subjects, environment: environment, mode: .refresh,
            runner: runner, cacheURL: s.url, now: { s.clockValue }
        )
    }

    let finalProcessStarted = await waitForScratchMarker(startedMarker, timeout: 30)
    guard finalProcessStarted else {
        task.cancel()
        try? Data("release\n".utf8).write(to: releaseMarker)
        _ = await task.value
        Issue.record("final-query fixture did not write its process-started marker")
        return
    }
    task.cancel()
    try Data("release\n".utf8).write(to: releaseMarker)
    let results = await task.value

    let observations = runner.observations
    #expect(observations.count == 3)
    #expect(observations.last?.outcome == .success(Data("{\"formulae\":[],\"casks\":[]}".utf8)))
    #expect(results.first?.status == .unknown(installed: Version("0.162.1"), reason: .probeFailed))
    #expect(results.first?.provenance == UpdateProvenance.none)
    #expect(FileManager.default.fileExists(atPath: s.url.path) == false)
}

@Test func productionProcessHandlesParentExitBeforeItsHangingDescendant() async throws {
    let s = try scenario("production-early-stdout-eof")
    try writeProductionProcessScript(to: s.fixture.brewPath)
    let pidMarker = s.fixture.prefix.deletingLastPathComponent().appendingPathComponent("early-eof-child.pid")
    let environment = processEnvironment(
        s, behavior: "early-eof", markers: ["AGENT_LENS_PID_MARKER": pidMarker.path]
    )
    let runner = RecordingProcessRunner(deadlineLimit: 7)
    let subjects = [probeSubject(toolDetection(s, version: "0.162.1"), id: "codex")]

    let results = await UpdateProbeCoordinator.run(
        subjects: subjects, environment: environment, mode: .refresh,
        runner: runner, cacheURL: s.url, now: { s.clockValue }
    )

    let markerReady = await waitForScratchMarker(pidMarker, timeout: 3)
    guard markerReady,
          let pidText = try? String(contentsOf: pidMarker, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
          let childPID = pid_t(pidText)
    else {
        Issue.record("early-EOF fixture did not establish a readable descendant PID marker")
        return
    }
    let childExited = await waitForProcessExit(childPID, timeout: 1)
    if !childExited { _ = kill(childPID, SIGKILL) }
    #expect(childExited)
    #expect(results.first?.localVersion == "0.162.1")
    #expect(results.first?.status == .unknown(installed: Version("0.162.1"), reason: .probeFailed))
    #expect(runner.observations.count == 1)
    #expect(runner.observations.first?.outcome == .failure(.timedOut))
    #expect((runner.observations.first?.elapsed ?? 0) < 9)
}

@Test func realDelayedProcessLeavesMainActorResponsive() async throws {
    let s = try scenario("real-process-responsiveness")
    try writeProductionProcessScript(to: s.fixture.brewPath)
    let startedMarker = s.fixture.prefix.deletingLastPathComponent().appendingPathComponent("process-started")
    let releaseMarker = s.fixture.prefix.deletingLastPathComponent().appendingPathComponent("process-release")
    let finishedMarker = s.fixture.prefix.deletingLastPathComponent().appendingPathComponent("process-finished")
    let environment = processEnvironment(
        s,
        behavior: "delayed",
        markers: [
            "AGENT_LENS_STARTED_MARKER": startedMarker.path,
            "AGENT_LENS_RELEASE_MARKER": releaseMarker.path,
            "AGENT_LENS_FINISHED_MARKER": finishedMarker.path,
        ]
    )
    let runner = RecordingProcessRunner(deadlineLimit: 7)
    let subjects = [probeSubject(toolDetection(s, version: "0.162.1"), id: "codex")]
    let processTask = Task { @MainActor in
        await UpdateProbeCoordinator.run(
            subjects: subjects, environment: environment, mode: .refresh,
            runner: runner, cacheURL: s.url, now: { s.clockValue }
        )
    }
    let processStarted = await waitForScratchMarker(startedMarker, timeout: 30)
    #expect(processStarted)

    let releasePath = releaseMarker.path
    let watchdog = Task.detached {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        try? Data("release\n".utf8).write(to: URL(fileURLWithPath: releasePath))
    }
    let responsiveBeforeProcessExit = await Task { @MainActor in
        !FileManager.default.fileExists(atPath: finishedMarker.path)
    }.value
    #expect(responsiveBeforeProcessExit)
    try Data("release\n".utf8).write(to: releaseMarker)
    let results = await processTask.value
    _ = await watchdog.value

    #expect(results.first?.status.isVerifiedComparison == true)
    #expect(runner.observations.count == 3)
}

// MARK: - M10-B R04: aggregate-deadline refusal mapping (coordinator level)

/// Shared mutable monotonic clock for coordinator stage-budget tests.
private final class StageClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 0
    func get() -> UInt64 { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ next: UInt64) { lock.lock(); value = next; lock.unlock() }
}

/// A synthetic, test-owned npm global tree for coordinator-stage tests: the existing ownership
/// verifier reads this real layout, while a scripted seam answers manager/config/view queries.
private struct NpmStageFixture {
    let root: URL
    let prefix: URL
    let globalRoot: URL
    let managerDirectory: URL
    let alias: URL
    let target: URL
    let environment: ShellEnvironment

    var managerPath: String { managerDirectory.appendingPathComponent("npm").path }
    var prefixText: String { prefix.path }
    var rootText: String { globalRoot.path }

    init(_ label: String, package: String = "@openai/codex", executableName: String = "codex") throws {
        let processEnvironment = ProcessInfo.processInfo.environment
        guard let basePath = [processEnvironment["AGENT_LENS_TEST_SCRATCH"], processEnvironment["TMPDIR"]]
            .compactMap({ $0 })
            .first(where: { !$0.isEmpty })
        else {
            throw NSError(domain: "NpmStageFixture", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "no approved test scratch root"])
        }
        let base = URL(fileURLWithPath: basePath, isDirectory: true).resolvingSymlinksInPath()
        root = base.appendingPathComponent(
            "agentlens-m10b-stage-\(label)-\(UUID().uuidString)", isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        prefix = root.appendingPathComponent("prefix", isDirectory: true)
        globalRoot = prefix.appendingPathComponent("lib/node_modules", isDirectory: true)
        managerDirectory = root.appendingPathComponent("manager-bin", isDirectory: true)
        let aliasDirectory = root.appendingPathComponent("alias-bin", isDirectory: true)
        try FileManager.default.createDirectory(at: managerDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: aliasDirectory, withIntermediateDirectories: true)

        func writeExecutable(_ url: URL) throws {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: url.path
            )
        }
        try writeExecutable(managerDirectory.appendingPathComponent("npm"))

        var packageURL = globalRoot
        for component in package.split(separator: "/", omittingEmptySubsequences: false) {
            packageURL.appendPathComponent(String(component), isDirectory: true)
        }
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        target = packageURL.appendingPathComponent("bin/codex.js")
        try writeExecutable(target)
        let manifest: [String: Any] = [
            "name": package, "version": "1.0.0", "bin": [executableName: "bin/codex.js"],
        ]
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
            .write(to: packageURL.appendingPathComponent("package.json"))

        let prefixBin = prefix.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: prefixBin, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: prefixBin.appendingPathComponent(executableName).path,
            withDestinationPath: target.path
        )
        alias = aliasDirectory.appendingPathComponent(executableName)
        try FileManager.default.createSymbolicLink(
            atPath: alias.path, withDestinationPath: target.path
        )
        let joined = "\(managerDirectory.path):\(aliasDirectory.path)"
        environment = ShellEnvironment(
            shellPath: "/bin/zsh",
            pathEntries: [managerDirectory.path, aliasDirectory.path],
            pathJoined: joined,
            raw: ["PATH": joined, "HOME": "/synthetic/home"],
            isDegraded: false
        )
    }

    func npmSubject(
        version: String = "1.0.0", package: String = "@openai/codex", id: String = "codex-npm"
    ) -> UpdateProbeSubject {
        let tool = DetectedTool(
            displayName: "Codex", executableName: "codex", state: .installedAndOnPath,
            entryPath: alias.path, resolvedPath: target.path, source: "npm", version: version
        )
        let candidate = PathCandidateObservation(
            origin: .path(slotIndex: 0, directoryText: alias.deletingLastPathComponent().path),
            entryPath: alias.path, kind: .executableSymlink, canonicalTarget: target.path
        )
        let diagnostic = ToolPathDiagnostic(
            detectedTool: tool, pathCandidates: [candidate], firstLiveCandidate: candidate,
            targetGroups: [PathTargetGroup(
                canonicalTarget: target.path, entryPaths: [alias.path], firstSlotIndex: 0
            )],
            repeatedPathSlotCount: 0, sameTargetAliasCount: 0, selection: .winner(candidate),
            shadowedInstallationCount: 0, installationVersions: []
        )
        return UpdateProbeSubject(
            definition: try! DetectorDefinition(
                id: id, displayName: "Codex", executableName: "codex",
                extraSearchRoots: [], fixture: nil, category: .aiAgent,
                packages: [try! DeclaredPackage(manager: .npm, name: package)],
                informationURL: nil, uninstallInstructionsURL: nil, versionQuery: .standard
            ),
            diagnostic: diagnostic
        )
    }
}

/// Coordinator-level R04 regression: when the aggregate stage deadline is exhausted mid-query,
/// the deadline-clipping runner's refusal must reach the result as `budgetExhausted` — never a
/// generic cancelled/probeFailed — and nothing may launch afterward or persist.
@Test func deadlineClippingRefusalAtStageBudgetReportsBudgetExhausted() async throws {
    let fixture = try NpmStageFixture("clip-mapping")
    let cacheDir = fixture.root.appendingPathComponent("cache", isDirectory: true)
    try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    let cacheURL = cacheDir.appendingPathComponent("update-metadata-v1.json")
    let scratchBase = fixture.root.appendingPathComponent("stage-scratch", isDirectory: true)
    try FileManager.default.createDirectory(at: scratchBase, withIntermediateDirectories: true)

    let clock = StageClock()
    final class RefusalRunner: UpdateCommandRunner, @unchecked Sendable {
        private let lock = NSLock()
        private var invocationsList: [[String]] = []
        let exhaustAtInvocation: Int
        let prefixText: String
        let rootText: String
        let clock: StageClock
        init(
            exhaustAtInvocation: Int, prefixText: String, rootText: String, clock: StageClock
        ) {
            self.exhaustAtInvocation = exhaustAtInvocation
            self.prefixText = prefixText
            self.rootText = rootText
            self.clock = clock
        }
        var invocations: [[String]] {
            lock.lock(); defer { lock.unlock() }
            return invocationsList
        }
        /// Synchronously records the arguments and returns the 1-based invocation ordinal. All
        /// `NSLock` use lives here in a non-async method so the async `run` body never locks.
        private func recordInvocation(_ arguments: [String]) -> Int {
            lock.lock(); defer { lock.unlock() }
            invocationsList.append(arguments)
            return invocationsList.count
        }
        func run(
            executablePath: String, arguments: [String],
            environment: [String: String], timeout: TimeInterval
        ) async -> CommandOutcome {
            let ordinal = recordInvocation(arguments)
            if ordinal == exhaustAtInvocation {
                // A slow final query pushes the injected monotonic clock past the 60-second
                // stage budget; every later launch attempt is the clipping runner's refusal.
                clock.set(200_000_000_000)
            }
            if arguments.contains("prefix") {
                return .success(Data("\(prefixText)\n".utf8))
            }
            if arguments.contains("root") {
                return .success(Data("\(rootText)\n".utf8))
            }
            return .failure(.invalidOutput)
        }
    }
    // Exhaust during the initial ownership's `root` query: the clipping runner then refuses every
    // subsequent launch, including the first registry config read.
    let runner = RefusalRunner(
        exhaustAtInvocation: 2, prefixText: fixture.prefixText, rootText: fixture.rootText,
        clock: clock
    )

    let results = await UpdateProbeCoordinator.run(
        subjects: [fixture.npmSubject()],
        environment: fixture.environment,
        mode: .checkUpdates,
        runner: runner,
        cacheURL: cacheURL,
        currentDirectory: fixture.root.path,
        now: { Date(timeIntervalSince1970: 1_800_000_000) },
        uptime: { clock.get() },
        npmScratchBaseURL: scratchBase
    )
    // The stage's clipping refusal at the exhausted aggregate deadline is budgetExhausted.
    #expect(results.first?.status == .unknown(
        installed: Version("1.0.0"), reason: .budgetExhausted
    ))
    // Nothing after the exhaustion launched, and no metadata was read or written.
    #expect(runner.invocations.count == 2)
    #expect(!runner.invocations.contains { $0.contains("config") })
    #expect(!runner.invocations.contains { $0.contains("view") })
    #expect(FileManager.default.fileExists(
        atPath: cacheDir.appendingPathComponent("npm-update-metadata-v1.json").path
    ) == false)
    // The stage's scratch children are owned and removed by the flow.
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: scratchBase.path)
    #expect(leftovers.isEmpty)
}

// MARK: - M10-B R05: one bounded admission and one budget for the COMPLETE optional stage
//
// R05 moved the boundary from "each manager admits itself" to "the coordinator admits the whole
// Check/Refresh stage once": one 10-second admission wait, one 60-second monotonic budget started at
// admission, and one deadline-clipped runner handed to Homebrew AND every npm ownership/config/
// metadata step. These cases therefore observe the coordinator, not one probe: cross-run
// mixed-manager exclusivity, Homebrew-first ordering, cache-only admission, expiry before ANY
// launch, clipping that reaches both managers, npm exhaustion that retains a completed Homebrew
// result, plain/offline work that never touches admission, and release-exactly-once.

private struct StageCommand: Equatable {
    let label: String
    /// "brew" or "npm": which manager the flow chose for this launch.
    let manager: String
    let token: String
    /// The timeout the stage's deadline-clipping runner handed to the wrapped runner.
    let timeout: TimeInterval
}

/// Cross-run observation point: live command concurrency, launch order, and per-command timeouts.
private final class StageCommandLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [StageCommand] = []
    private var active = 0
    private var maximumActive = 0

    func begin(_ entry: StageCommand) {
        lock.lock()
        entries.append(entry)
        active += 1
        maximumActive = max(maximumActive, active)
        lock.unlock()
    }

    func end() {
        lock.lock()
        active -= 1
        lock.unlock()
    }

    var snapshot: [StageCommand] { lock.lock(); defer { lock.unlock() }; return entries }
    var maximumConcurrentInvocations: Int { lock.lock(); defer { lock.unlock() }; return maximumActive }
}

/// Classifies one scripted launch by the manager executable the flow chose, so a Homebrew argument
/// can never be mistaken for an npm one. Order mirrors the npm probe's own command vocabulary.
private func stageCommandToken(for arguments: [String], isHomebrew: Bool) -> String {
    if isHomebrew {
        if arguments.contains("--cellar") { return "--cellar" }
        if arguments.contains("info") { return "info" }
        if arguments.contains("outdated") { return "outdated" }
        return "other"
    }
    if arguments.contains("prefix") { return "prefix" }
    if arguments.contains("root") { return "root" }
    if arguments.contains("--version") { return "--version" }
    if arguments.contains("view") { return "view" }
    if arguments.contains(where: { $0.hasSuffix(":registry") }) { return "scope-registry" }
    if arguments.contains("registry") { return "base-registry" }
    return "other"
}

private func mixedStageOutcome(
    _ arguments: [String],
    isHomebrew: Bool,
    brewCellar: String,
    npmPrefix: String,
    npmRoot: String,
    viewJSON: Data
) -> CommandOutcome {
    if isHomebrew {
        if arguments.contains("--cellar") { return .success(Data("\(brewCellar)\n".utf8)) }
        if arguments.contains("info") {
            return .success(infoJSON([
                (name: "codex", stable: "0.162.1", revision: 1, installed: ["0.162.1_1"])
            ]))
        }
        return .success(outdatedJSON([]))
    }
    if arguments.contains("prefix") { return .success(Data("\(npmPrefix)\n".utf8)) }
    if arguments.contains("root") { return .success(Data("\(npmRoot)\n".utf8)) }
    if arguments.contains("--version") { return .success(Data("10.5.0\n".utf8)) }
    if arguments.contains("view") { return .success(viewJSON) }
    if arguments.contains(where: { $0.hasSuffix(":registry") }) { return .success(Data("undefined\n".utf8)) }
    if arguments.contains("registry") {
        return .success(Data("https://registry.npmjs.org/\n".utf8))
    }
    return .failure(.spawnFailure)
}

/// One synthetic machine hosting BOTH managers, with its own metadata document and stage scratch.
private struct MixedStageFixture {
    let brew: Scenario
    let npm: NpmStageFixture
    let environment: ShellEnvironment
    let subjects: [UpdateProbeSubject]
    let cacheURL: URL
    let npmDocumentURL: URL
    let scratchBase: URL
    let workingDirectory: String
    let viewJSON = Data(
        #"{"name":"@openai/codex","version":"2.0.0","dist-tags.latest":"2.0.0"}"#.utf8
    )

    var brewExecutable: String { brew.fixture.brewPath }
    var brewCellar: String { brew.fixture.cellar }
    var clockValue: Date { brew.clockValue }

    init(_ label: String) throws {
        let brew = try scenario("mixed-\(label)")
        let npm = try NpmStageFixture("mixed-\(label)")
        let cacheDir = npm.root.appendingPathComponent("cache", isDirectory: true)
        let scratch = npm.root.appendingPathComponent("stage-scratch", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        self.brew = brew
        self.npm = npm
        // Both managers resolve from one PATH: Homebrew first, then the npm global tree.
        environment = m6Environment(pathEntries: [
            brew.fixture.binDirectory, npm.managerDirectory.path,
            npm.alias.deletingLastPathComponent().path
        ])
        subjects = [
            probeSubject(toolDetection(brew, version: "0.162.1"), id: "codex"),
            npm.npmSubject(id: "codex-npm"),
        ]
        cacheURL = cacheDir.appendingPathComponent("update-metadata-v1.json")
        npmDocumentURL = cacheDir.appendingPathComponent("npm-update-metadata-v1.json")
        scratchBase = scratch
        workingDirectory = npm.root.path
    }
}

/// Answers both managers with one current Codex keg and one npm 2.0.0 latest, attributing every
/// launch to `label` in a shared log and optionally moving the aggregate stage clock.
private final class MixedStageRunner: UpdateCommandRunner, @unchecked Sendable {
    /// When the single 60-second stage budget is observed as consumed. A jump is applied only AFTER
    /// the triggering command has launched, so it never retroactively refuses that command.
    struct Budget {
        let jumpToNanos: UInt64?
        let afterHomebrewCommands: Int
        let onFirstNpmCommand: Bool
        init(
            jumpToNanos: UInt64? = nil,
            afterHomebrewCommands: Int = .max,
            onFirstNpmCommand: Bool = false
        ) {
            self.jumpToNanos = jumpToNanos
            self.afterHomebrewCommands = afterHomebrewCommands
            self.onFirstNpmCommand = onFirstNpmCommand
        }
    }

    private let log: StageCommandLog
    private let lock = NSLock()
    private var homebrewAnswered = 0
    private var npmAnswered = 0

    let label: String
    private let brewExecutable: String
    private let brewCellar: String
    private let npmPrefixText: String
    private let npmRootText: String
    private let viewJSON: Data
    private let clock: StageClock
    private let budget: Budget
    private let holdFirstNpmCommand: Bool
    private let entered: OneShotSignal
    private let release: OneShotSignal

    init(
        label: String,
        fixture: MixedStageFixture,
        log: StageCommandLog,
        clock: StageClock,
        budget: Budget = Budget(),
        holdFirstNpmCommand: Bool = false,
        entered: OneShotSignal = OneShotSignal(),
        release: OneShotSignal = OneShotSignal()
    ) {
        self.label = label
        self.log = log
        self.clock = clock
        self.brewExecutable = fixture.brewExecutable
        self.brewCellar = fixture.brewCellar
        self.npmPrefixText = fixture.npm.prefixText
        self.npmRootText = fixture.npm.rootText
        self.viewJSON = fixture.viewJSON
        self.budget = budget
        self.holdFirstNpmCommand = holdFirstNpmCommand
        self.entered = entered
        self.release = release
    }

    var commands: [StageCommand] { log.snapshot.filter { $0.label == label } }

    func run(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval
    ) async -> CommandOutcome {
        let isHomebrew = executablePath == brewExecutable
        let token = stageCommandToken(for: arguments, isHomebrew: isHomebrew)
        log.begin(StageCommand(
            label: label, manager: isHomebrew ? "brew" : "npm", token: token, timeout: timeout
        ))
        defer { log.end() }
        if holdFirstNpmCommand, !isHomebrew, token == "prefix" {
            await entered.signal()
            await release.wait()
        }
        consumeBudget(isHomebrew: isHomebrew)
        return mixedStageOutcome(
            arguments, isHomebrew: isHomebrew, brewCellar: brewCellar,
            npmPrefix: npmPrefixText, npmRoot: npmRootText, viewJSON: viewJSON
        )
    }

    private func consumeBudget(isHomebrew: Bool) {
        lock.lock()
        if isHomebrew {
            homebrewAnswered += 1
            if homebrewAnswered == budget.afterHomebrewCommands, let target = budget.jumpToNanos {
                clock.set(target)
            }
        } else {
            npmAnswered += 1
            if npmAnswered == 1, budget.onFirstNpmCommand, let target = budget.jumpToNanos {
                clock.set(target)
            }
        }
        lock.unlock()
    }
}

/// A monotonic clock seam whose first read answers `first` and every later read answers `rest`, so
/// a test can exhaust the aggregate budget immediately after admission.
private final class SteppedStageClock: @unchecked Sendable {
    private let lock = NSLock()
    private var reads = 0
    let first: UInt64
    let rest: UInt64
    init(first: UInt64, rest: UInt64) {
        self.first = first
        self.rest = rest
    }
    func get() -> UInt64 {
        lock.lock()
        reads += 1
        let value = reads == 1 ? first : rest
        lock.unlock()
        return value
    }
}

private func mixedStageRun(
    _ fixture: MixedStageFixture,
    runner: any UpdateCommandRunner,
    uptime: @escaping @Sendable () -> UInt64 = { 0 },
    mode: UpdateProbeMode = .refresh
) async -> [ToolUpdateResult] {
    await UpdateProbeCoordinator.run(
        subjects: fixture.subjects,
        environment: fixture.environment,
        mode: mode,
        runner: runner,
        cacheURL: fixture.cacheURL,
        currentDirectory: fixture.workingDirectory,
        now: { fixture.clockValue },
        uptime: uptime,
        npmScratchBaseURL: fixture.scratchBase
    )
}

/// R05: two simultaneous mixed-manager scans may not interleave at all. The whole stage is admitted
/// once, so no Homebrew command of one run can overlap any command of the other run and vice versa.
@Test func mixedManagerConcurrentRunsNeverShareTheStageAndKeepHomebrewFirst() async throws {
    let log = StageCommandLog()
    let first = try MixedStageFixture("overlap-a")
    let second = try MixedStageFixture("overlap-b")
    let firstClock = StageClock()
    let secondClock = StageClock()
    let firstRunner = MixedStageRunner(label: "A", fixture: first, log: log, clock: firstClock)
    let secondRunner = MixedStageRunner(label: "B", fixture: second, log: log, clock: secondClock)

    async let firstResults = mixedStageRun(first, runner: firstRunner, uptime: { firstClock.get() })
    async let secondResults = mixedStageRun(second, runner: secondRunner, uptime: { secondClock.get() })
    let results = [await firstResults, await secondResults]

    // One command in flight at a time across BOTH managers and BOTH runs.
    #expect(log.maximumConcurrentInvocations == 1)
    // Each run occupies one contiguous block of the stage: exactly one handover, no interleaving.
    let labels = log.snapshot.map(\.label)
    let handovers = zip(labels, labels.dropFirst()).filter { $0.0 != $0.1 }.count
    #expect(handovers == 1)
    // Homebrew-first ordering holds inside each admitted stage.
    for label in ["A", "B"] {
        let managers = log.snapshot.filter { $0.label == label }.map(\.manager)
        #expect(managers.prefix(3).allSatisfy { $0 == "brew" })
        let firstNpmIndex = managers.firstIndex(of: "npm") ?? managers.endIndex
        #expect(!managers.dropFirst(firstNpmIndex).contains("brew"))
    }
    // Waiting for admission cost nothing but time: both runs publish both managers.
    for runResults in results {
        #expect(runResults.count == 2)
        #expect(runResults[0].registryID == "codex")
        #expect(runResults[0].status.isVerifiedComparison == true)
        #expect(runResults[1].registryID == "codex-npm")
        #expect(runResults[1].status.isVerifiedComparison == true)
    }
}

/// R05: a Homebrew cache hit is still admitted work. While another run owns the stage, a Check that
/// would need no process at all must wait outside the stage rather than read the disk metadata.
@Test func cacheOnlyCheckWaitsForStageAdmissionBeforeServingDiskMetadata() async throws {
    let s = try scenario("admission-cache-only")
    let env = m6Environment(pathEntries: [s.fixture.binDirectory])
    let subjects = [probeSubject(toolDetection(s, version: "0.162.1"), id: "codex")]
    let seeder = CountingRunner(handler: healthyHandler(cellar: s.fixture.cellar))
    let seeded = await UpdateProbeCoordinator.run(
        subjects: subjects, environment: env, mode: .checkUpdates, runner: seeder,
        cacheURL: s.url, now: { s.clockValue }
    )
    #expect(seeder.invocationCount == 3)
    #expect(seeded.first?.provenance == .freshProbe(observedAt: s.clockValue))

    // Hold the stage with an unrelated Refresh whose first Homebrew command blocks. It reads and
    // writes only its own document, so the hit below still refers to the seeded observation.
    let holderURL = s.url.deletingLastPathComponent().appendingPathComponent("holder-cache.json")
    let entered = OneShotSignal()
    let release = OneShotSignal()
    let holder = ControlledRunner(
        heldInvocation: 1, entered: entered, release: release,
        handler: healthyHandler(cellar: s.fixture.cellar)
    )
    let holderTask = Task {
        await UpdateProbeCoordinator.run(
            subjects: subjects, environment: env, mode: .refresh, runner: holder,
            cacheURL: holderURL, now: { s.clockValue.addingTimeInterval(10) }
        )
    }
    await entered.wait()

    let queued = OneShotSignal()
    let hitRunner = CountingRunner(handler: healthyHandler(cellar: s.fixture.cellar))
    let hitTask = Task {
        await UpdateProbeCoordinatorTestHooks.observingStageAdmissionQueue(
            { Task { await queued.signal() } }
        ) {
            await UpdateProbeCoordinator.run(
                subjects: subjects, environment: env, mode: .checkUpdates, runner: hitRunner,
                cacheURL: s.url, now: { s.clockValue.addingTimeInterval(60) }
            )
        }
    }
    // The queue notification is the proof: a zero-query Check reached admission instead of reading.
    await queued.wait()
    #expect(hitRunner.invocationCount == 0)

    await release.signal()
    let hit = await hitTask.value
    _ = await holderTask.value
    #expect(hit.first?.provenance == .cache(observedAt: s.clockValue))
    #expect(hitRunner.invocationCount == 0)
}

/// R05: with the aggregate stage budget gone, a cache-only Check refuses to serve disk metadata and
/// reports the budget instead — admission is not a formality the metadata path can skip.
@Test func exhaustedStageDeadlineRefusesAHomebrewCacheHit() async throws {
    let s = try scenario("admission-cache-exhausted")
    let env = m6Environment(pathEntries: [s.fixture.binDirectory])
    let subjects = [probeSubject(toolDetection(s, version: "0.162.1"), id: "codex")]
    let seeder = CountingRunner(handler: healthyHandler(cellar: s.fixture.cellar))
    _ = await UpdateProbeCoordinator.run(
        subjects: subjects, environment: env, mode: .checkUpdates, runner: seeder,
        cacheURL: s.url, now: { s.clockValue }
    )
    #expect(FileManager.default.fileExists(atPath: s.url.path))

    let clock = SteppedStageClock(first: 0, rest: 70_000_000_000)
    let runner = CountingRunner(handler: healthyHandler(cellar: s.fixture.cellar))
    let results = await UpdateProbeCoordinator.run(
        subjects: subjects, environment: env, mode: .checkUpdates, runner: runner,
        cacheURL: s.url, now: { s.clockValue.addingTimeInterval(60) },
        uptime: { clock.get() }
    )
    #expect(results.first?.status == .unknown(
        installed: Version("0.162.1"), reason: .budgetExhausted
    ))
    #expect(runner.invocationCount == 0)
}

/// R05: one budget covers both managers, and Homebrew completes inside it. When the budget runs out
/// at the boundary, the npm stage launches nothing while the finished Homebrew result and its
/// metadata are retained — slow npm work can never evict a completed Homebrew answer.
@Test func npmStageExhaustionRetainsCompletedHomebrewResults() async throws {
    let fixture = try MixedStageFixture("npm-exhaust")
    let log = StageCommandLog()
    let clock = StageClock()
    // The clock jumps only after the third (final) Homebrew command has launched, so the whole
    // Homebrew batch is answered inside the budget and the first thing to find it gone is npm.
    let runner = MixedStageRunner(
        label: "run", fixture: fixture, log: log, clock: clock,
        budget: MixedStageRunner.Budget(jumpToNanos: 200_000_000_000, afterHomebrewCommands: 3)
    )
    let results = await mixedStageRun(fixture, runner: runner, uptime: { clock.get() })

    // Exactly the three Homebrew commands ran; no npm ownership/config/metadata launch followed.
    #expect(log.snapshot.map(\.manager) == ["brew", "brew", "brew"])
    #expect(results[0].status.isVerifiedComparison == true)
    #expect(results[0].provenance == .freshProbe(observedAt: fixture.clockValue))
    #expect(results[0].managerCellar != nil)
    #expect(results[1].status == .unknown(
        installed: Version("1.0.0"), reason: .budgetExhausted
    ))
    // The exhausted subject keeps its identity and gains no claim.
    #expect(results[1].registryID == "codex-npm")
    #expect(results[1].localVersion == "1.0.0")
    #expect(results[1].selectedEntryPath == fixture.npm.alias.path)
    // Homebrew's verified metadata was persisted; npm wrote nothing.
    #expect(FileManager.default.fileExists(atPath: fixture.cacheURL.path))
    #expect(FileManager.default.fileExists(atPath: fixture.npmDocumentURL.path) == false)
}

/// R05: the deadline-clipped runner is the single place both managers launch through, so the same
/// remaining budget shortens BOTH command families. Homebrew keeps its nominal bound while more than
/// that remains; the 20-second npm metadata query is cut to what is actually left.
@Test func oneStageDeadlineClipsHomebrewAndNpmCommandsTogether() async throws {
    // Control: the aggregate clock never moves, so every command keeps its nominal timeout.
    let control = try MixedStageFixture("clip-control")
    let controlLog = StageCommandLog()
    let controlClock = StageClock()
    let controlRunner = MixedStageRunner(label: "control", fixture: control, log: controlLog, clock: controlClock)
    let controlResults = await mixedStageRun(control, runner: controlRunner, uptime: { controlClock.get() })
    let controlCommands = controlLog.snapshot
    let controlBrew = controlCommands.filter { $0.manager == "brew" }.map(\.timeout)
    #expect(Set(controlBrew) == [HomebrewUpdateProbe.queryTimeout])
    #expect(controlBrew.count == 3)
    let controlView = try #require(controlCommands.first { $0.token == "view" })
    #expect(controlView.timeout == 20)  // the nominal npm metadata bound, unclipped

    // Same stage, but the budget is at 45 of 60 seconds by the time the npm stage starts.
    let clipped = try MixedStageFixture("clip-jump")
    let clippedLog = StageCommandLog()
    let clippedClock = StageClock()
    let clippedRunner = MixedStageRunner(
        label: "clipped", fixture: clipped, log: clippedLog, clock: clippedClock,
        budget: MixedStageRunner.Budget(jumpToNanos: 45_000_000_000, onFirstNpmCommand: true)
    )
    let clippedResults = await mixedStageRun(clipped, runner: clippedRunner, uptime: { clippedClock.get() })
    let clippedCommands = clippedLog.snapshot
    // Homebrew was still inside the budget, so its nominal bound passed through untouched.
    #expect(Set(clippedCommands.filter { $0.manager == "brew" }.map(\.timeout))
            == [HomebrewUpdateProbe.queryTimeout])
    // The metadata query is clipped to the 15 seconds left, below its 20-second nominal.
    let clippedView = try #require(clippedCommands.first { $0.token == "view" })
    #expect(clippedView.timeout == 15)
    #expect(clippedView.timeout < controlView.timeout)
    // Short 3-second config/version reads need no clipping and were not turned into failures.
    for command in clippedCommands where command.token == "base-registry"
        || command.token == "scope-registry" || command.token == "--version" {
        #expect(command.timeout == 3)
    }
    // Clipping is a bound, not an error: both managers still publish verified comparisons.
    #expect(controlResults.allSatisfy { $0.status.isVerifiedComparison })
    #expect(clippedResults.allSatisfy { $0.status.isVerifiedComparison })
}

/// R05: plain and offline scans are not optional-stage work. They must complete while another run
/// owns the stage, launching nothing and touching neither metadata document.
@Test func plainAndOfflineRunsNeverWaitForStageAdmission() async throws {
    let fixture = try MixedStageFixture("plain-offline")
    let log = StageCommandLog()
    let holderClock = StageClock()
    let entered = OneShotSignal()
    let release = OneShotSignal()
    let holder = MixedStageRunner(
        label: "holder", fixture: fixture, log: log, clock: holderClock,
        holdFirstNpmCommand: true, entered: entered, release: release
    )
    let holderTask = Task {
        await mixedStageRun(fixture, runner: holder, uptime: { holderClock.get() })
    }
    // The stage is occupied, mid-npm, and the npm metadata document does not exist yet.
    await entered.wait()
    #expect(FileManager.default.fileExists(atPath: fixture.npmDocumentURL.path) == false)

    let idle = CountingRunner(handler: healthyHandler(cellar: fixture.brewCellar))
    let plain = await mixedStageRun(fixture, runner: idle, mode: .localOnly)
    let offline = await mixedStageRun(fixture, runner: idle, mode: .offline)

    // Both returned without waiting for a permit that was still held at that moment.
    #expect(idle.invocationCount == 0)
    #expect(plain.map(\.status) == [
        .unknown(installed: Version("0.162.1"), reason: .notChecked),
        .unknown(installed: Version("1.0.0"), reason: .notChecked),
    ])
    #expect(offline.map(\.status) == [
        .unknown(installed: Version("0.162.1"), reason: .networkUnavailable),
        .unknown(installed: Version("1.0.0"), reason: .networkUnavailable),
    ])
    #expect(FileManager.default.fileExists(atPath: fixture.npmDocumentURL.path) == false)

    await release.signal()
    _ = await holderTask.value
}

/// R05: a run that cannot enter the stage inside the bounded admission wait launches NOTHING from
/// either manager, reads and writes no metadata, reports the budget for every optional subject, and
/// never frees the permit it never held. The bounded wait itself is the wall-clock cost asserted
/// here, so this case is intentionally the slow one.
@Test func admissionExpiryBeforeAnyLaunchReportsBudgetAndKeepsTheStageUsable() async throws {
    let fixture = try MixedStageFixture("admission-expiry")
    let holderLog = StageCommandLog()
    let holderClock = StageClock()
    let entered = OneShotSignal()
    let release = OneShotSignal()
    let holder = MixedStageRunner(
        label: "holder", fixture: fixture, log: holderLog, clock: holderClock,
        holdFirstNpmCommand: true, entered: entered, release: release
    )
    let holderTask = Task {
        await mixedStageRun(fixture, runner: holder, uptime: { holderClock.get() })
    }
    await entered.wait()

    let victimLog = StageCommandLog()
    let victimClock = StageClock()
    let victimRunner = MixedStageRunner(label: "victim", fixture: fixture, log: victimLog, clock: victimClock)
    let started = DispatchTime.now().uptimeNanoseconds
    let victim = await mixedStageRun(fixture, runner: victimRunner, uptime: { victimClock.get() })
    let waitedSeconds = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000

    // Bounded: the wait ended at the admission window, not whenever the holder felt like it.
    #expect(waitedSeconds >= 9 && waitedSeconds < 30)
    #expect(victimLog.snapshot.isEmpty)  // no Homebrew and no npm command launched
    #expect(victim.map(\.status) == [
        .unknown(installed: Version("0.162.1"), reason: .budgetExhausted),
        .unknown(installed: Version("1.0.0"), reason: .budgetExhausted),
    ])
    #expect(FileManager.default.fileExists(atPath: fixture.npmDocumentURL.path) == false)

    await release.signal()
    _ = await holderTask.value

    // The expired waiter released nothing it did not own: the stage still admits exactly one run.
    let recoveryLog = StageCommandLog()
    let recoveryClock = StageClock()
    let recoveryRunner = MixedStageRunner(label: "recovery", fixture: fixture, log: recoveryLog, clock: recoveryClock)
    let recovery = await mixedStageRun(fixture, runner: recoveryRunner, uptime: { recoveryClock.get() })
    #expect(recovery.allSatisfy { $0.status.isVerifiedComparison })
    #expect(recoveryLog.maximumConcurrentInvocations == 1)
}

/// R05 release-exactly-once under late cancellation: cancelling inside an admitted stage, after the
/// Homebrew batch already finished, must keep that completed answer, report only the npm subject as
/// failed, write no npm metadata, and leave the permit held (never double-released) so the next
/// simultaneous pair is still serialized.
@Test func cancellationInsideAdmittedStageReleasesThePermitExactlyOnce() async throws {
    let fixture = try MixedStageFixture("late-cancel")
    let log = StageCommandLog()
    let holderClock = StageClock()
    let entered = OneShotSignal()
    let release = OneShotSignal()
    let victimRunner = MixedStageRunner(
        label: "victim", fixture: fixture, log: log, clock: holderClock,
        holdFirstNpmCommand: true, entered: entered, release: release
    )
    let victimTask = Task {
        await mixedStageRun(fixture, runner: victimRunner, uptime: { holderClock.get() })
    }
    // Cancel AFTER admission and after the Homebrew batch completed: the run is inside npm work.
    await entered.wait()
    victimTask.cancel()
    await release.signal()
    let victim = await victimTask.value

    // The finished Homebrew comparison is retained; the cancelled npm subject claims nothing.
    #expect(victim[0].status.isVerifiedComparison)
    #expect(victim[1].status == .unknown(
        installed: Version("1.0.0"), reason: .probeFailed
    ))
    #expect(FileManager.default.fileExists(atPath: fixture.npmDocumentURL.path) == false)

    // The permit came back exactly once: a fresh pair still cannot overlap, and neither is stranded
    // outside a stage that would report budgetExhausted.
    let afterLog = StageCommandLog()
    let firstClock = StageClock()
    let secondClock = StageClock()
    let firstRunner = MixedStageRunner(label: "first", fixture: fixture, log: afterLog, clock: firstClock)
    let secondRunner = MixedStageRunner(label: "second", fixture: fixture, log: afterLog, clock: secondClock)
    async let firstResults = mixedStageRun(fixture, runner: firstRunner, uptime: { firstClock.get() })
    async let secondResults = mixedStageRun(fixture, runner: secondRunner, uptime: { secondClock.get() })
    let after = [await firstResults, await secondResults]
    #expect(afterLog.maximumConcurrentInvocations == 1)
    for runResults in after {
        #expect(runResults.allSatisfy { $0.status.isVerifiedComparison })
    }
}

// MARK: - M13-B cask latest-check coordinator cases
//
// The cask stage reuses the M6 eligibility order, the one complete-stage admission, the existing
// Homebrew batch gate, and the one deadline-clipped runner. These fixtures are synthetic scratch
// trees and scripted manager answers; no real brew or cask is invoked.

private struct CaskStageFixture {
    let root: URL
    let brew: BrewFixture
    let caskroom: URL
    let cacheURL: URL
    let clockValue: Date
    let environment: ShellEnvironment

    init(_ label: String) throws {
        brew = try makeBrewFixture("cask-\(label)")
        root = brew.prefix.deletingLastPathComponent()
        caskroom = brew.prefix.appendingPathComponent("Caskroom", isDirectory: true)
        try FileManager.default.createDirectory(at: caskroom, withIntermediateDirectories: true)
        let cacheDirectory = root.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        cacheURL = cacheDirectory.appendingPathComponent("update-metadata-v1.json")
        clockValue = Date(timeIntervalSince1970: 1_800_000_000)
        environment = m6Environment(pathEntries: [brew.binDirectory])
    }

    var caskCacheURL: URL {
        cacheURL.deletingLastPathComponent()
            .appendingPathComponent("cask-update-metadata-v1.json")
    }

    /// Stages `<caskroom>/<token>/<version>/bin/<token>`, links `<prefix>/bin/<token>` to it, and
    /// builds a standalone diagnostic plus a validated cask-declaring definition.
    func subject(
        token: String,
        version: String = "1.0.0",
        localVersion: String? = nil,
        declaresCask: Bool = true,
        declaration: String? = nil,
        declarations: [String]? = nil,
        id: String? = nil,
        externalTarget: String? = nil
    ) throws -> (subject: UpdateProbeSubject, selectedTarget: String) {
        let target: String
        let link = brew.prefix.appendingPathComponent("bin/\(token)")
        if let externalTarget {
            target = externalTarget
            try? FileManager.default.removeItem(at: link)
            try FileManager.default.createSymbolicLink(
                atPath: link.path, withDestinationPath: externalTarget
            )
        } else {
            let artifact = caskroom
                .appendingPathComponent(token, isDirectory: true)
                .appendingPathComponent(version, isDirectory: true)
                .appendingPathComponent("bin/\(token)")
            try FileManager.default.createDirectory(
                at: artifact.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let local = localVersion ?? version
            let script = "#!/bin/sh\nprintf '%s\\n' '\(local)'\n"
            try Data(script.utf8).write(to: artifact)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: artifact.path
            )
            try? FileManager.default.removeItem(at: link)
            try FileManager.default.createSymbolicLink(
                atPath: link.path, withDestinationPath: artifact.path
            )
            target = artifact.resolvingSymlinksInPath().standardizedFileURL.path
        }
        let candidate = PathCandidateObservation(
            origin: .path(slotIndex: 0, directoryText: brew.binDirectory),
            entryPath: link.path,
            kind: .executableSymlink,
            canonicalTarget: target
        )
        let tool = DetectedTool(
            displayName: token,
            executableName: token,
            state: .installedAndOnPath,
            entryPath: link.path,
            resolvedPath: target,
            source: "standalone",
            version: localVersion ?? version
        )
        let diagnostic = ToolPathDiagnostic(
            detectedTool: tool,
            pathCandidates: [candidate],
            firstLiveCandidate: candidate,
            targetGroups: [PathTargetGroup(
                canonicalTarget: target, entryPaths: [link.path], firstSlotIndex: 0
            )],
            repeatedPathSlotCount: 0,
            sameTargetAliasCount: 0,
            selection: .winner(candidate),
            shadowedInstallationCount: 0,
            installationVersions: []
        )
        let declaredNames = declarations ?? [declaration ?? token]
        let packages = declaresCask
            ? try declaredNames.map { try DeclaredPackage(manager: .homebrewCask, name: $0) }
            : []
        let definition = try DetectorDefinition(
            id: id ?? "cask-\(token)",
            displayName: token,
            executableName: token,
            extraSearchRoots: [],
            fixture: nil,
            category: .aiHarness,
            packages: packages,
            informationURL: nil,
            uninstallInstructionsURL: nil,
            versionQuery: .standard
        )
        return (UpdateProbeSubject(definition: definition, diagnostic: diagnostic), target)
    }

    /// A selected Homebrew formula under the same manager, used to prove that a completed formula
    /// result survives a later cask-stage failure.
    func formulaSubject(
        formula: String = "codex",
        keg: String = "0.162.1_1",
        version: String = "0.162.1"
    ) throws -> UpdateProbeSubject {
        let target = try brew.installKeg(formula: formula, keg: keg)
        let entry = brew.prefix.appendingPathComponent("bin/\(formula)")
        let candidate = PathCandidateObservation(
            origin: .path(slotIndex: 0, directoryText: brew.binDirectory),
            entryPath: entry.path,
            kind: .executableSymlink,
            canonicalTarget: target
        )
        let tool = DetectedTool(
            displayName: formula,
            executableName: formula,
            state: .installedAndOnPath,
            entryPath: entry.path,
            resolvedPath: target,
            source: "brew",
            version: version
        )
        let diagnostic = ToolPathDiagnostic(
            detectedTool: tool,
            pathCandidates: [candidate],
            firstLiveCandidate: candidate,
            targetGroups: [PathTargetGroup(
                canonicalTarget: target, entryPaths: [entry.path], firstSlotIndex: 0
            )],
            repeatedPathSlotCount: 0,
            sameTargetAliasCount: 0,
            selection: .winner(candidate),
            shadowedInstallationCount: 0,
            installationVersions: []
        )
        return UpdateProbeSubject(
            definition: probeDefinition(id: formula, displayName: formula, executableName: formula),
            diagnostic: diagnostic
        )
    }
}

private func m13bInfoRecord(
    token: String,
    version: String,
    installed: String?,
    autoUpdates: Bool? = nil,
    pinned: Bool = false,
    outdated: Bool = false,
    disabled: Bool = false,
    fullToken: String? = nil,
    tap: String = "homebrew/cask"
) -> String {
    let full = fullToken ?? token
    let installedField = installed.map { "\"installed\":\"\($0)\"" } ?? "\"installed\":null"
    let auto = autoUpdates.map { $0 ? "true" : "false" } ?? "null"
    return """
    {"token":"\(token)","full_token":"\(full)","tap":"\(tap)","version":"\(version)",\
    \(installedField),"auto_updates":\(auto),"pinned":\(pinned),"outdated":\(outdated),\
    "disabled":\(disabled)}
    """
}

private func m13bInfoJSON(_ records: [String]) -> Data {
    Data("{\"formulae\":[],\"casks\":[\(records.joined(separator: ","))]}".utf8)
}

private func m13bOutdatedRecord(
    name: String,
    current: String,
    installed: String,
    pinned: Bool = false
) -> String {
    """
    {"name":"\(name)","current_version":"\(current)","installed_versions":["\(installed)"],\
    "pinned":\(pinned),"pinned_version":null}
    """
}

private func m13bOutdatedJSON(_ records: [String]) -> Data {
    Data("{\"formulae\":[],\"casks\":[\(records.joined(separator: ","))]}".utf8)
}

private func m13bListing(_ targets: [String]) -> Data {
    Data(targets.joined(separator: "\n").utf8 + (targets.isEmpty ? Data() : Data("\n".utf8)))
}

/// Records the executable and argv of every launch, attributing brew vs npm by executable path.
private final class CaskStageRunner: UpdateCommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [(executable: String, arguments: [String])] = []
    private let handler: @Sendable (String, [String]) -> CommandOutcome

    init(handler: @escaping @Sendable (String, [String]) -> CommandOutcome) {
        self.handler = handler
    }

    var calls: [(executable: String, arguments: [String])] {
        lock.lock(); defer { lock.unlock() }
        return entries
    }

    private func record(_ executable: String, _ arguments: [String]) {
        lock.lock()
        defer { lock.unlock() }
        entries.append((executable, arguments))
    }

    func run(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval
    ) async -> CommandOutcome {
        record(executablePath, arguments)
        return handler(executablePath, arguments)
    }
}

private func caskOnlyHandler(
    fixture: CaskStageFixture,
    info: Data,
    outdated: Data,
    listing: Data,
    infoTokens: [String],
    listTokens: [String]
) -> @Sendable (String, [String]) -> CommandOutcome {
    { _, arguments in
        switch arguments {
        case ["--prefix"]:
            return .success(Data((fixture.brew.prefix.path + "\n").utf8))
        case ["--caskroom"]:
            return .success(Data((fixture.caskroom.path + "\n").utf8))
        case ["info", "--json=v2", "--cask"] + infoTokens:
            return .success(info)
        case ["outdated", "--json=v2", "--cask"]:
            return .success(outdated)
        case ["list", "--verbose", "--cask"] + listTokens:
            return .success(listing)
        default:
            Issue.record("unexpected cask-stage arguments: \(arguments)")
            return .failure(.spawnFailure)
        }
    }
}

private func runCaskStage(
    fixture: CaskStageFixture,
    subjects: [UpdateProbeSubject],
    runner: UpdateCommandRunner,
    mode: UpdateProbeMode = .checkUpdates,
    now: Date? = nil,
    currentDirectory: String? = nil,
    uptime: (@Sendable () -> UInt64)? = nil
) async -> [ToolUpdateResult] {
    await UpdateProbeCoordinator.run(
        subjects: subjects,
        environment: fixture.environment,
        mode: mode,
        runner: runner,
        cacheURL: fixture.cacheURL,
        currentDirectory: currentDirectory ?? fixture.root.path,
        now: { now ?? fixture.clockValue },
        uptime: uptime ?? { DispatchTime.now().uptimeNanoseconds }
    )
}

@Test func caskCheckRunsTheFiveCommandBatchAndRendersUpToDate() async throws {
    let fixture = try CaskStageFixture("five")
    let staged = try fixture.subject(token: "codex")
    let info = m13bInfoJSON([
        m13bInfoRecord(token: "codex", version: "1.0.0", installed: "1.0.0")
    ])
    let runner = CaskStageRunner(handler: caskOnlyHandler(
        fixture: fixture, info: info, outdated: m13bOutdatedJSON([]),
        listing: m13bListing([staged.selectedTarget]),
        infoTokens: ["codex"], listTokens: ["codex"]
    ))
    let results = await runCaskStage(fixture: fixture, subjects: [staged.subject], runner: runner)

    #expect(runner.calls.map(\.arguments) == [
        ["--prefix"],
        ["--caskroom"],
        ["info", "--json=v2", "--cask", "codex"],
        ["outdated", "--json=v2", "--cask"],
        ["list", "--verbose", "--cask", "codex"],
    ])
    #expect(results.first?.status == .upToDate(
        installed: Version("1.0.0"), latest: Version("1.0.0")
    ))
    #expect(results.first?.caskToken == "codex")
    #expect(results.first?.caskFullToken == "codex")
    #expect(results.first?.caskTap == "homebrew/cask")
    #expect(results.first?.caskInstalledVersion == "1.0.0")
    #expect(results.first?.caskPinned == false)
    #expect(results.first?.formulaStem == nil)
    #expect(results.first?.npmPackage == nil)
    #expect(results.first?.provenance == .freshProbe(observedAt: fixture.clockValue))
    let rendered = UpdateScanRenderer.render(results: results, mode: .checkUpdates)
    #expect(rendered.contains("codex  installed 1.0.0  latest known 1.0.0  up to date"))
    #expect(rendered.contains("0 updates available"))
    #expect(rendered.contains("source: Homebrew cask metadata (cask codex tap homebrew/cask installed 1.0.0; not pinned); checked at 2027-01-15T08:00:00Z"))
    #expect(FileManager.default.fileExists(atPath: fixture.caskCacheURL.path))
}

@Test func fullyQualifiedDeclarationQueriesTheFullNameAndListsTheBareToken() async throws {
    let fixture = try CaskStageFixture("qualified")
    let staged = try fixture.subject(
        token: "kiro-cli", declaration: "owner/tap/kiro-cli", id: "kiro-qualified"
    )
    let info = m13bInfoJSON([
        m13bInfoRecord(
            token: "kiro-cli", version: "1.0.0", installed: "1.0.0",
            fullToken: "owner/tap/kiro-cli", tap: "owner/tap"
        )
    ])
    let runner = CaskStageRunner(handler: caskOnlyHandler(
        fixture: fixture, info: info, outdated: m13bOutdatedJSON([]),
        listing: m13bListing([staged.selectedTarget]),
        infoTokens: ["owner/tap/kiro-cli"], listTokens: ["owner/tap/kiro-cli"]
    ))
    let results = await runCaskStage(fixture: fixture, subjects: [staged.subject], runner: runner)
    #expect(runner.calls.map(\.arguments) == [
        ["--prefix"],
        ["--caskroom"],
        ["info", "--json=v2", "--cask", "owner/tap/kiro-cli"],
        ["outdated", "--json=v2", "--cask"],
        ["list", "--verbose", "--cask", "owner/tap/kiro-cli"],
    ])
    #expect(results.first?.status == .upToDate(
        installed: Version("1.0.0"), latest: Version("1.0.0")
    ))
    #expect(results.first?.caskFullToken == "owner/tap/kiro-cli")
    #expect(results.first?.caskTap == "owner/tap")
    #expect(FileManager.default.fileExists(atPath: fixture.caskCacheURL.path))
}

@Test func standaloneWithoutCaskDeclarationStaysNoRegistry() async throws {
    let fixture = try CaskStageFixture("no-cask")
    let staged = try fixture.subject(token: "codex", declaresCask: false)
    let runner = CaskStageRunner { _, arguments in
        Issue.record("unexpected manager launch for an undeclared cask: \(arguments)")
        return .failure(.spawnFailure)
    }
    let results = await runCaskStage(fixture: fixture, subjects: [staged.subject], runner: runner)
    #expect(runner.calls.isEmpty)
    #expect(results.first?.status == .unknown(
        installed: Version("1.0.0"), reason: .noRegistry
    ))
    #expect(!FileManager.default.fileExists(atPath: fixture.caskCacheURL.path))
}

@Test func pinnedCaskUpdateIsCountedAndThePinStaysVisible() async throws {
    let fixture = try CaskStageFixture("pinned")
    let staged = try fixture.subject(token: "codex")
    let info = m13bInfoJSON([
        m13bInfoRecord(
            token: "codex", version: "1.2.4", installed: "1.0.0",
            pinned: true, outdated: true
        )
    ])
    let runner = CaskStageRunner(handler: caskOnlyHandler(
        fixture: fixture, info: info,
        outdated: m13bOutdatedJSON([
            m13bOutdatedRecord(
                name: "codex", current: "1.2.4", installed: "1.0.0", pinned: true
            )
        ]),
        listing: m13bListing([staged.selectedTarget]),
        infoTokens: ["codex"], listTokens: ["codex"]
    ))
    let results = await runCaskStage(fixture: fixture, subjects: [staged.subject], runner: runner)
    #expect(results.first?.status == .updateAvailable(
        installed: Version("1.0.0"), latest: Version("1.2.4")
    ))
    #expect(results.first?.caskPinned == true)
    let rendered = UpdateScanRenderer.render(results: results, mode: .checkUpdates)
    #expect(rendered.contains("1 update available"))
    #expect(rendered.contains("pinned); checked at"))
}

@Test func typedCaskUnknownIsNeverCachedAndNeverCounts() async throws {
    let fixture = try CaskStageFixture("unknown")
    let staged = try fixture.subject(token: "codex")
    let info = m13bInfoJSON([
        m13bInfoRecord(
            token: "codex", version: "1.2.4", installed: "1.0.0",
            autoUpdates: true, outdated: true
        )
    ])
    let runner = CaskStageRunner(handler: caskOnlyHandler(
        fixture: fixture, info: info,
        outdated: m13bOutdatedJSON([
            m13bOutdatedRecord(name: "codex", current: "1.2.4", installed: "1.0.0")
        ]),
        listing: m13bListing([staged.selectedTarget]),
        infoTokens: ["codex"], listTokens: ["codex"]
    ))
    let first = await runCaskStage(fixture: fixture, subjects: [staged.subject], runner: runner)
    #expect(first.first?.status == .unknown(
        installed: Version("1.0.0"), reason: .caskAutoUpdates
    ))
    #expect(runner.calls.count == 5)
    #expect(!FileManager.default.fileExists(atPath: fixture.caskCacheURL.path))
    let rendered = UpdateScanRenderer.render(results: first, mode: .checkUpdates)
    #expect(rendered.contains("0 updates available"))
    #expect(rendered.contains("cask manages its own updates"))

    let second = await runCaskStage(fixture: fixture, subjects: [staged.subject], runner: runner)
    #expect(second.first?.status == .unknown(
        installed: Version("1.0.0"), reason: .caskAutoUpdates
    ))
    #expect(runner.calls.count == 10, "a negative result must be re-probed, never cached")
}

@Test func caskCheckServesACacheHitWithoutAnyManagerQuery() async throws {
    let fixture = try CaskStageFixture("cache-hit")
    let staged = try fixture.subject(token: "codex")
    let info = m13bInfoJSON([
        m13bInfoRecord(
            token: "codex", version: "1.2.4", installed: "1.0.0",
            pinned: true, outdated: true
        )
    ])
    let warm = CaskStageRunner(handler: caskOnlyHandler(
        fixture: fixture, info: info,
        outdated: m13bOutdatedJSON([
            m13bOutdatedRecord(
                name: "codex", current: "1.2.4", installed: "1.0.0", pinned: true
            )
        ]),
        listing: m13bListing([staged.selectedTarget]),
        infoTokens: ["codex"], listTokens: ["codex"]
    ))
    let fresh = await runCaskStage(fixture: fixture, subjects: [staged.subject], runner: warm)
    #expect(fresh.first?.provenance == .freshProbe(observedAt: fixture.clockValue))
    #expect(warm.calls.count == 5)

    let cold = CaskStageRunner { _, arguments in
        Issue.record("a valid cask cache hit must launch no manager: \(arguments)")
        return .failure(.spawnFailure)
    }
    let cached = await runCaskStage(fixture: fixture, subjects: [staged.subject], runner: cold)
    #expect(cold.calls.isEmpty)
    #expect(cached.first?.status == .updateAvailable(
        installed: Version("1.0.0"), latest: Version("1.2.4")
    ))
    #expect(cached.first?.caskPinned == true)
    #expect(cached.first?.provenance == .cache(observedAt: fixture.clockValue))
    let rendered = UpdateScanRenderer.render(results: cached, mode: .checkUpdates)
    #expect(rendered.contains("1 update available"))
    #expect(rendered.contains("source: Homebrew cask metadata cache"))
}

@Test func caskRefreshBypassesTheCacheAndReplacesIt() async throws {
    let fixture = try CaskStageFixture("refresh")
    let staged = try fixture.subject(token: "codex")
    func info(version: String) -> Data {
        m13bInfoJSON([
            m13bInfoRecord(token: "codex", version: version, installed: "1.0.0", outdated: true)
        ])
    }
    func outdated(version: String) -> Data {
        m13bOutdatedJSON([
            m13bOutdatedRecord(name: "codex", current: version, installed: "1.0.0")
        ])
    }
    let first = CaskStageRunner(handler: caskOnlyHandler(
        fixture: fixture, info: info(version: "1.2.4"),
        outdated: outdated(version: "1.2.4"),
        listing: m13bListing([staged.selectedTarget]),
        infoTokens: ["codex"], listTokens: ["codex"]
    ))
    _ = await runCaskStage(fixture: fixture, subjects: [staged.subject], runner: first)

    let refreshed = CaskStageRunner(handler: caskOnlyHandler(
        fixture: fixture, info: info(version: "1.3.0"),
        outdated: outdated(version: "1.3.0"),
        listing: m13bListing([staged.selectedTarget]),
        infoTokens: ["codex"], listTokens: ["codex"]
    ))
    let value = await runCaskStage(
        fixture: fixture, subjects: [staged.subject], runner: refreshed, mode: .refresh
    )
    #expect(refreshed.calls.count == 5, "Refresh must not serve the cached 1.2.4")
    #expect(value.first?.status == .updateAvailable(
        installed: Version("1.0.0"), latest: Version("1.3.0")
    ))
    #expect(value.first?.provenance == .freshProbe(observedAt: fixture.clockValue))

    let after = CaskStageRunner { _, arguments in
        Issue.record("the refreshed cache should be a hit: \(arguments)")
        return .failure(.spawnFailure)
    }
    let cached = await runCaskStage(fixture: fixture, subjects: [staged.subject], runner: after)
    #expect(after.calls.isEmpty)
    #expect(cached.first?.status == .updateAvailable(
        installed: Version("1.0.0"), latest: Version("1.3.0")
    ))
}

@Test func caskComparisonCompletedAtTheDeadlineIsPublishedButNotStored() async throws {
    let fixture = try CaskStageFixture("deadline-store")
    let staged = try fixture.subject(token: "codex")
    let clock = StageClock()
    let info = m13bInfoJSON([
        m13bInfoRecord(token: "codex", version: "1.0.0", installed: "1.0.0")
    ])
    let runner = CaskStageRunner { _, arguments in
        let response = caskOnlyHandler(
            fixture: fixture, info: info, outdated: m13bOutdatedJSON([]),
            listing: m13bListing([staged.selectedTarget]),
            infoTokens: ["codex"], listTokens: ["codex"]
        )(fixture.brew.brewPath, arguments)
        if arguments == ["list", "--verbose", "--cask", "codex"] {
            // The final answer arrives, then the aggregate budget is observed as gone.
            clock.set(200_000_000_000)
        }
        return response
    }
    let results = await runCaskStage(
        fixture: fixture, subjects: [staged.subject], runner: runner,
        uptime: { clock.get() }
    )
    #expect(results.first?.status == .upToDate(
        installed: Version("1.0.0"), latest: Version("1.0.0")
    ))
    #expect(!FileManager.default.fileExists(atPath: fixture.caskCacheURL.path))
}

@Test func caskLocalOnlyAndOfflineAdmitNothingAndWriteNoDocument() async throws {
    let fixture = try CaskStageFixture("plain")
    let staged = try fixture.subject(token: "codex")
    let runner = CaskStageRunner { _, arguments in
        Issue.record("plain/offline cask work launched a manager: \(arguments)")
        return .failure(.spawnFailure)
    }
    let local = await runCaskStage(
        fixture: fixture, subjects: [staged.subject], runner: runner, mode: .localOnly
    )
    #expect(local.first?.status == .unknown(
        installed: Version("1.0.0"), reason: .notChecked
    ))
    let offline = await runCaskStage(
        fixture: fixture, subjects: [staged.subject], runner: runner, mode: .offline
    )
    #expect(offline.first?.status == .unknown(
        installed: Version("1.0.0"), reason: .networkUnavailable
    ))
    #expect(runner.calls.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: fixture.caskCacheURL.path))
}

@Test func caskBatchRunsAfterFormulaAndBeforeNpmInTheSameAdmittedStage() async throws {
    let mixed = try MixedStageFixture("cask-order")
    // Put the cask staged artifact under the SAME brew prefix the formula uses, so one manager
    // answers the formula batch and then the cask batch.
    let caskroom = mixed.brew.fixture.prefix.appendingPathComponent("Caskroom", isDirectory: true)
    try FileManager.default.createDirectory(at: caskroom, withIntermediateDirectories: true)
    let artifact = caskroom.appendingPathComponent("kiro-cli/3.2.1/bin/kiro-cli")
    try FileManager.default.createDirectory(
        at: artifact.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try Data("#!/bin/sh\nprintf '%s\\n' '3.2.1'\n".utf8).write(to: artifact)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755], ofItemAtPath: artifact.path
    )
    let link = mixed.brew.fixture.prefix.appendingPathComponent("bin/kiro-cli")
    try? FileManager.default.removeItem(at: link)
    try FileManager.default.createSymbolicLink(
        atPath: link.path, withDestinationPath: artifact.path
    )
    let target = artifact.resolvingSymlinksInPath().standardizedFileURL.path
    let candidate = PathCandidateObservation(
        origin: .path(slotIndex: 0, directoryText: mixed.brew.fixture.binDirectory),
        entryPath: link.path, kind: .executableSymlink, canonicalTarget: target
    )
    let caskDiagnostic = ToolPathDiagnostic(
        detectedTool: DetectedTool(
            displayName: "Kiro CLI", executableName: "kiro-cli", state: .installedAndOnPath,
            entryPath: link.path, resolvedPath: target, source: "standalone", version: "3.2.1"
        ),
        pathCandidates: [candidate], firstLiveCandidate: candidate,
        targetGroups: [PathTargetGroup(
            canonicalTarget: target, entryPaths: [link.path], firstSlotIndex: 0
        )],
        repeatedPathSlotCount: 0, sameTargetAliasCount: 0, selection: .winner(candidate),
        shadowedInstallationCount: 0, installationVersions: []
    )
    let caskSubject = UpdateProbeSubject(
        definition: try DetectorDefinition(
            id: "kiro-cli-cask", displayName: "Kiro CLI", executableName: "kiro-cli",
            extraSearchRoots: [], fixture: nil, category: .aiCodingTool,
            packages: [try DeclaredPackage(manager: .homebrewCask, name: "kiro-cli")],
            informationURL: nil, uninstallInstructionsURL: nil, versionQuery: .standard
        ),
        diagnostic: caskDiagnostic
    )
    let subjects = [
        probeSubject(toolDetection(mixed.brew, version: "0.162.1"), id: "codex"),
        caskSubject,
        mixed.npm.npmSubject(id: "codex-npm"),
    ]
    let caskInfo = m13bInfoJSON([
        m13bInfoRecord(token: "kiro-cli", version: "3.2.1", installed: "3.2.1")
    ])
    let runner = CaskStageRunner { executable, arguments in
        if executable == mixed.brew.fixture.brewPath {
            if arguments == ["--cellar"] {
                return .success(Data((mixed.brew.fixture.cellar + "\n").utf8))
            }
            if arguments.first == "info", arguments.contains("--formula") {
                return .success(infoJSON([
                    (name: "codex", stable: "0.162.1", revision: 1, installed: ["0.162.1_1"])
                ]))
            }
            if arguments == ["outdated", "--json=v2", "--formula"] {
                return .success(outdatedJSON([]))
            }
            if arguments == ["--prefix"] {
                return .success(Data((mixed.brew.fixture.prefix.path + "\n").utf8))
            }
            if arguments == ["--caskroom"] {
                return .success(Data((caskroom.path + "\n").utf8))
            }
            if arguments == ["info", "--json=v2", "--cask", "kiro-cli"] {
                return .success(caskInfo)
            }
            if arguments == ["outdated", "--json=v2", "--cask"] {
                return .success(m13bOutdatedJSON([]))
            }
            if arguments == ["list", "--verbose", "--cask", "kiro-cli"] {
                return .success(m13bListing([target]))
            }
            Issue.record("unexpected brew arguments: \(arguments)")
            return .failure(.spawnFailure)
        }
        return mixedStageOutcome(
            arguments, isHomebrew: false,
            brewCellar: mixed.brew.fixture.cellar,
            npmPrefix: mixed.npm.prefixText, npmRoot: mixed.npm.rootText,
            viewJSON: mixed.viewJSON
        )
    }
    let results = await UpdateProbeCoordinator.run(
        subjects: subjects,
        environment: mixed.environment,
        mode: .checkUpdates,
        runner: runner,
        cacheURL: mixed.cacheURL,
        currentDirectory: mixed.workingDirectory,
        now: { mixed.clockValue },
        npmScratchBaseURL: mixed.scratchBase
    )
    let brewCalls = runner.calls.filter { $0.executable == mixed.brew.fixture.brewPath }
        .map(\.arguments)
    let npmCalls = runner.calls.filter { $0.executable == mixed.npm.managerPath }
    #expect(brewCalls.prefix(3) == [
        ["--cellar"],
        ["info", "--json=v2", "--formula", "codex"],
        ["outdated", "--json=v2", "--formula"],
    ])
    #expect(brewCalls.dropFirst(3).prefix(5) == [
        ["--prefix"],
        ["--caskroom"],
        ["info", "--json=v2", "--cask", "kiro-cli"],
        ["outdated", "--json=v2", "--cask"],
        ["list", "--verbose", "--cask", "kiro-cli"],
    ])
    #expect(!npmCalls.isEmpty)
    let lastBrewIndex = runner.calls.lastIndex { $0.executable == mixed.brew.fixture.brewPath } ?? -1
    let firstNpmIndex = runner.calls.firstIndex { $0.executable == mixed.npm.managerPath } ?? .max
    #expect(lastBrewIndex < firstNpmIndex, "the cask batch must complete before npm work")
    #expect(results.count == 3)
    #expect(results[0].status.isVerifiedComparison)
    #expect(results[1].status == .upToDate(
        installed: Version("3.2.1"), latest: Version("3.2.1")
    ))
    #expect(results[2].status.isVerifiedComparison)
}

@Test func combinedCaskListFailureMarksEveryCaskSubjectProbeFailed() async throws {
    let fixture = try CaskStageFixture("list-failure")
    let first = try fixture.subject(token: "codex", id: "codex-cask")
    let second = try fixture.subject(token: "kiro-cli", id: "kiro-cask")
    let info = m13bInfoJSON([
        m13bInfoRecord(token: "codex", version: "1.0.0", installed: "1.0.0"),
        m13bInfoRecord(token: "kiro-cli", version: "1.0.0", installed: "1.0.0"),
    ])
    let runner = CaskStageRunner { _, arguments in
        switch arguments {
        case ["--prefix"]:
            return .success(Data((fixture.brew.prefix.path + "\n").utf8))
        case ["--caskroom"]:
            return .success(Data((fixture.caskroom.path + "\n").utf8))
        case ["info", "--json=v2", "--cask", "codex", "kiro-cli"]:
            return .success(info)
        case ["outdated", "--json=v2", "--cask"]:
            return .success(m13bOutdatedJSON([]))
        case ["list", "--verbose", "--cask", "codex", "kiro-cli"]:
            return .failure(.nonzeroExit)
        default:
            Issue.record("unexpected arguments: \(arguments)")
            return .failure(.spawnFailure)
        }
    }
    let results = await runCaskStage(
        fixture: fixture, subjects: [first.subject, second.subject], runner: runner
    )
    #expect(results.map(\.status) == [
        .unknown(installed: Version("1.0.0"), reason: .probeFailed),
        .unknown(installed: Version("1.0.0"), reason: .probeFailed),
    ])
    #expect(!FileManager.default.fileExists(atPath: fixture.caskCacheURL.path))
}

@Test func caskTokenCapSixteenLeavesTheSeventeenthSubjectBudgetExhausted() async throws {
    let fixture = try CaskStageFixture("cap")
    var subjects: [UpdateProbeSubject] = []
    var targets: [String] = []
    for index in 0..<17 {
        let token = "tool\(index)"
        let staged = try fixture.subject(token: token, id: "cask-\(token)")
        subjects.append(staged.subject)
        targets.append(staged.selectedTarget)
    }
    let tokens = (0..<16).map { "tool\($0)" }
    let capTargets = Array(targets.prefix(16))
    let info = m13bInfoJSON(
        tokens.map { m13bInfoRecord(token: $0, version: "1.0.0", installed: "1.0.0") }
    )
    let runner = CaskStageRunner { _, arguments in
        switch arguments {
        case ["--prefix"]:
            return .success(Data((fixture.brew.prefix.path + "\n").utf8))
        case ["--caskroom"]:
            return .success(Data((fixture.caskroom.path + "\n").utf8))
        case ["info", "--json=v2", "--cask"] + tokens:
            return .success(info)
        case ["outdated", "--json=v2", "--cask"]:
            return .success(m13bOutdatedJSON([]))
        case ["list", "--verbose", "--cask"] + tokens:
            return .success(m13bListing(capTargets))
        default:
            Issue.record("unexpected capped arguments: \(arguments)")
            return .failure(.spawnFailure)
        }
    }
    let results = await runCaskStage(fixture: fixture, subjects: subjects, runner: runner)
    #expect(runner.calls.count == 5)
    #expect(runner.calls[2].arguments == ["info", "--json=v2", "--cask"] + tokens)
    #expect(results.prefix(16).allSatisfy { $0.status.isVerifiedComparison })
    #expect(results[16].status == .unknown(
        installed: Version("1.0.0"), reason: .budgetExhausted
    ))
}

@Test func caskQueryTimeoutIsReportedAsTheQueryBound() async throws {
    let fixture = try CaskStageFixture("timeout")
    let staged = try fixture.subject(token: "codex")
    let runner = CaskStageRunner { _, arguments in
        #expect(arguments == ["--prefix"])
        return .failure(.timedOut)
    }
    let results = await runCaskStage(fixture: fixture, subjects: [staged.subject], runner: runner)
    #expect(runner.calls.count == 1)
    #expect(results.first?.status == .unknown(
        installed: Version("1.0.0"), reason: .queryTimedOut
    ))
    #expect(!FileManager.default.fileExists(atPath: fixture.caskCacheURL.path))
}

@Test func caskStageBudgetExhaustionRetainsACompletedFormulaResult() async throws {
    let fixture = try CaskStageFixture("budget")
    let formula = try fixture.formulaSubject()
    let cask = try fixture.subject(token: "kiro-cli")
    let clock = StageClock()
    let runner = CaskStageRunner { _, arguments in
        switch arguments {
        case ["--cellar"]:
            return .success(Data((fixture.brew.cellar + "\n").utf8))
        case ["info", "--json=v2", "--formula", "codex"]:
            return .success(infoJSON([
                (name: "codex", stable: "0.162.1", revision: 1, installed: ["0.162.1_1"])
            ]))
        case ["outdated", "--json=v2", "--formula"]:
            // The aggregate stage budget is gone once this final formula query completes.
            clock.set(200_000_000_000)
            return .success(outdatedJSON([]))
        default:
            Issue.record("the cask stage must launch nothing after the budget is gone: \(arguments)")
            return .failure(.spawnFailure)
        }
    }
    let results = await runCaskStage(
        fixture: fixture, subjects: [formula, cask.subject], runner: runner,
        uptime: { clock.get() }
    )
    #expect(runner.calls.count == 3)
    #expect(results[0].status == .upToDate(
        installed: Version("0.162.1"), latest: Version("0.162.1_1")
    ))
    #expect(results[1].status == .unknown(
        installed: Version("1.0.0"), reason: .budgetExhausted
    ))
    #expect(!FileManager.default.fileExists(atPath: fixture.caskCacheURL.path))
}

@Test func cancellationDuringTheCaskBatchPublishesNothing() async throws {
    let fixture = try CaskStageFixture("cancel")
    let staged = try fixture.subject(token: "codex")
    let entered = OneShotSignal()
    let release = OneShotSignal()
    let runner = ControlledRunner(
        heldInvocation: 1,
        entered: entered,
        release: release,
        handler: { arguments in
            if arguments == ["--prefix"] {
                return .success(Data((fixture.brew.prefix.path + "\n").utf8))
            }
            Issue.record("only the held prefix query may launch: \(arguments)")
            return .failure(.spawnFailure)
        }
    )
    let task = Task {
        await runCaskStage(fixture: fixture, subjects: [staged.subject], runner: runner)
    }
    await entered.wait()
    task.cancel()
    await release.signal()
    let results = await task.value
    #expect(runner.invocationCount == 1)
    #expect(results.first?.status == .unknown(
        installed: Version("1.0.0"), reason: .probeFailed
    ))
    #expect(!FileManager.default.fileExists(atPath: fixture.caskCacheURL.path))
}

@Test func caskCacheHitIsBoundToItsWorkingDirectoryContext() async throws {
    let fixture = try CaskStageFixture("context")
    let staged = try fixture.subject(token: "codex")
    let info = m13bInfoJSON([
        m13bInfoRecord(token: "codex", version: "1.0.0", installed: "1.0.0")
    ])
    let warm = CaskStageRunner(handler: caskOnlyHandler(
        fixture: fixture, info: info, outdated: m13bOutdatedJSON([]),
        listing: m13bListing([staged.selectedTarget]),
        infoTokens: ["codex"], listTokens: ["codex"]
    ))
    _ = await runCaskStage(fixture: fixture, subjects: [staged.subject], runner: warm)
    #expect(warm.calls.count == 5)

    let otherDirectory = fixture.root.appendingPathComponent("other", isDirectory: true)
    try FileManager.default.createDirectory(at: otherDirectory, withIntermediateDirectories: true)
    let other = CaskStageRunner { _, arguments in
        #expect(arguments == ["--prefix"])
        return .failure(.spawnFailure)
    }
    let results = await runCaskStage(
        fixture: fixture, subjects: [staged.subject], runner: other,
        currentDirectory: otherDirectory.path
    )
    #expect(other.calls.count == 1, "a changed working directory is a different cask context")
    #expect(results.first?.status == .unknown(
        installed: Version("1.0.0"), reason: .probeFailed
    ))
}

@Test func freshlyVerifiedMovedAppIsPublishedButNeverCached() async throws {
    let fixture = try CaskStageFixture("moved-cask")
    let bundle = fixture.root.appendingPathComponent("Applications/Kiro.app", isDirectory: true)
    let binary = bundle.appendingPathComponent("Contents/MacOS/kiro-cli")
    try FileManager.default.createDirectory(
        at: binary.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try Data("#!/bin/sh\nprintf '1.0.0\\n'\n".utf8).write(to: binary)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755], ofItemAtPath: binary.path
    )
    let stagedVersion = fixture.caskroom.appendingPathComponent(
        "kiro-cli/1.0.0", isDirectory: true
    )
    try FileManager.default.createDirectory(at: stagedVersion, withIntermediateDirectories: true)
    let appLink = stagedVersion.appendingPathComponent("Staged.app")
    try FileManager.default.createSymbolicLink(
        atPath: appLink.path, withDestinationPath: bundle.path
    )
    let moved = try fixture.subject(
        token: "kiro-cli",
        externalTarget: binary.resolvingSymlinksInPath().standardizedFileURL.path
    )
    let info = m13bInfoJSON([
        m13bInfoRecord(token: "kiro-cli", version: "1.1.0", installed: "1.0.0", outdated: true)
    ])
    let runner = CaskStageRunner(handler: caskOnlyHandler(
        fixture: fixture, info: info,
        outdated: m13bOutdatedJSON([
            m13bOutdatedRecord(name: "kiro-cli", current: "1.1.0", installed: "1.0.0")
        ]),
        listing: m13bListing([appLink.path]),
        infoTokens: ["kiro-cli"], listTokens: ["kiro-cli"]
    ))
    let results = await runCaskStage(
        fixture: fixture, subjects: [moved.subject], runner: runner
    )
    #expect(results.first?.status == .updateAvailable(
        installed: Version("1.0.0"), latest: Version("1.1.0")
    ))
    #expect(results.first?.caskInstalledVersion == "1.0.0")
    #expect(runner.calls.count == 5)
    // R3 only permits exact staged-target decomposition: a freshly verified moved app is never
    // written, so there is no document to restore.
    #expect(!FileManager.default.fileExists(atPath: fixture.caskCacheURL.path))
}

@Test func samePathReplacementBetweenCallsStopsTheBatchAndCachesNothing() async throws {
    let fixture = try CaskStageFixture("replace-selection")
    let staged = try fixture.subject(token: "codex")
    let info = m13bInfoJSON([
        m13bInfoRecord(token: "codex", version: "1.0.0", installed: "1.0.0")
    ])
    let runner = CaskStageRunner { _, arguments in
        let response = caskOnlyHandler(
            fixture: fixture, info: info, outdated: m13bOutdatedJSON([]),
            listing: m13bListing([staged.selectedTarget]),
            infoTokens: ["codex"], listTokens: ["codex"]
        )(fixture.brew.brewPath, arguments)
        if arguments == ["--caskroom"] {
            // Replace the executable at the SAME canonical path.
            try? Data("#!/bin/sh\nprintf '9.9.9\\n'\n".utf8).write(
                to: URL(fileURLWithPath: staged.selectedTarget)
            )
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: staged.selectedTarget
            )
        }
        return response
    }
    let results = await runCaskStage(
        fixture: fixture, subjects: [staged.subject], runner: runner
    )
    #expect(runner.calls.map(\.arguments) == [["--prefix"], ["--caskroom"]])
    #expect(results.first?.status == .unknown(
        installed: Version("1.0.0"), reason: .identityUnverified
    ))
    #expect(!FileManager.default.fileExists(atPath: fixture.caskCacheURL.path))
}

@Test func replacedManagerBetweenCallsStopsBeforeTheNextQuery() async throws {
    let fixture = try CaskStageFixture("replace-manager")
    let staged = try fixture.subject(token: "codex")
    let runner = CaskStageRunner { _, arguments in
        #expect(arguments == ["--prefix"])
        try? FileManager.default.removeItem(atPath: fixture.brew.brewPath)
        try? Data("#!/bin/sh\nexit 0\n".utf8).write(
            to: URL(fileURLWithPath: fixture.brew.brewPath)
        )
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: fixture.brew.brewPath
        )
        return .success(Data((fixture.brew.prefix.path + "\n").utf8))
    }
    let results = await runCaskStage(
        fixture: fixture, subjects: [staged.subject], runner: runner
    )
    #expect(runner.calls.count == 1)
    #expect(results.first?.status == .unknown(
        installed: Version("1.0.0"), reason: .identityUnverified
    ))
    #expect(!FileManager.default.fileExists(atPath: fixture.caskCacheURL.path))
}

@Test func staleCaskDeclarationCannotRestoreTheCacheEntry() async throws {
    let fixture = try CaskStageFixture("declaration-cache")
    let first = try fixture.subject(token: "kiro-cli", id: "cask-kiro")
    let firstInfo = m13bInfoJSON([
        m13bInfoRecord(token: "kiro-cli", version: "1.0.0", installed: "1.0.0")
    ])
    let warm = CaskStageRunner(handler: caskOnlyHandler(
        fixture: fixture, info: firstInfo, outdated: m13bOutdatedJSON([]),
        listing: m13bListing([first.selectedTarget]),
        infoTokens: ["kiro-cli"], listTokens: ["kiro-cli"]
    ))
    let warmed = await runCaskStage(
        fixture: fixture, subjects: [first.subject], runner: warm
    )
    #expect(warmed.first?.status == .upToDate(
        installed: Version("1.0.0"), latest: Version("1.0.0")
    ))
    #expect(FileManager.default.fileExists(atPath: fixture.caskCacheURL.path))

    // Same registry identity, same selection, different current cask declaration: a miss.
    let second = try fixture.subject(
        token: "kiro-cli", declarations: ["kiro-cli@latest"], id: "cask-kiro"
    )
    let cold = CaskStageRunner { _, arguments in
        switch arguments {
        case ["--prefix"]:
            return .success(Data((fixture.brew.prefix.path + "\n").utf8))
        case ["--caskroom"]:
            return .success(Data((fixture.caskroom.path + "\n").utf8))
        case ["info", "--json=v2", "--cask", "kiro-cli@latest"]:
            return .success(m13bInfoJSON([]))
        case ["outdated", "--json=v2", "--cask"]:
            return .success(m13bOutdatedJSON([]))
        default:
            Issue.record("a changed declaration must be freshly probed: \(arguments)")
            return .failure(.spawnFailure)
        }
    }
    let results = await runCaskStage(
        fixture: fixture, subjects: [second.subject], runner: cold
    )
    #expect(cold.calls.first?.arguments == ["--prefix"], "no cache hit for a new declaration")
    #expect(results.first?.status == .unknown(
        installed: Version("1.0.0"), reason: .identityUnverified
    ))
}

@Test func capAdmitsAWholeDeclarationSetOrExcludesTheSubjectEntirely() async throws {
    let fixture = try CaskStageFixture("cap-orphan")
    var subjects: [UpdateProbeSubject] = []
    var targets: [String] = []
    for index in 0..<15 {
        let token = "tool\(index)"
        let staged = try fixture.subject(token: token, id: "cask-\(token)")
        subjects.append(staged.subject)
        targets.append(staged.selectedTarget)
    }
    let starved = try fixture.subject(
        token: "extra", declarations: ["owner/tap/extra-one", "owner/tap/extra-two"],
        id: "cask-extra"
    )
    subjects.append(starved.subject)
    let targets15 = targets
    let tokens = (0..<15).map { "tool\($0)" }
    let info = m13bInfoJSON(
        tokens.map { m13bInfoRecord(token: $0, version: "1.0.0", installed: "1.0.0") }
    )
    let runner = CaskStageRunner { _, arguments in
        switch arguments {
        case ["--prefix"]:
            return .success(Data((fixture.brew.prefix.path + "\n").utf8))
        case ["--caskroom"]:
            return .success(Data((fixture.caskroom.path + "\n").utf8))
        case ["info", "--json=v2", "--cask"] + tokens:
            return .success(info)
        case ["outdated", "--json=v2", "--cask"]:
            return .success(m13bOutdatedJSON([]))
        case ["list", "--verbose", "--cask"] + tokens:
            return .success(m13bListing(targets15))
        default:
            Issue.record("a rejected subject must leave no orphan token: \(arguments)")
            return .failure(.spawnFailure)
        }
    }
    let results = await runCaskStage(fixture: fixture, subjects: subjects, runner: runner)
    #expect(runner.calls[2].arguments == ["info", "--json=v2", "--cask"] + tokens)
    #expect(!runner.calls.contains { $0.arguments.contains("owner/tap/extra-one") })
    #expect(!runner.calls.contains { $0.arguments.contains("owner/tap/extra-two") })
    #expect(results.prefix(15).allSatisfy { $0.status.isVerifiedComparison })
    #expect(results[15].status == .unknown(
        installed: Version("1.0.0"), reason: .budgetExhausted
    ))
}
