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

private func coreProductsForContextVerifier() throws -> URL {
    let fileManager = FileManager.default
    func hasCoreArtifacts(_ directory: URL) -> Bool {
        let objectExists = fileManager.fileExists(atPath: directory.appendingPathComponent("AgentLensCore.o").path)
        let moduleExists = fileManager.fileExists(atPath: directory.appendingPathComponent("AgentLensCore.swiftmodule").path)
            || fileManager.fileExists(atPath: directory.appendingPathComponent("Modules/AgentLensCore.swiftmodule").path)
        return objectExists && moduleExists
    }

    let argv = CommandLine.arguments
    var starts: [URL] = []
    if let index = argv.firstIndex(of: "--test-bundle-path"), index + 1 < argv.count {
        starts.append(URL(fileURLWithPath: argv[index + 1]))
    }
    if let last = argv.last, last.contains(".xctest") {
        starts.append(URL(fileURLWithPath: last))
    }
    for start in starts {
        var directory = start.resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<8 {
            if hasCoreArtifacts(directory) { return directory }
            let parent = directory.deletingLastPathComponent()
            if parent == directory { break }
            directory = parent
        }
    }

    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .standardizedFileURL
    for searchRoot in [
        packageRoot.appendingPathComponent(".build", isDirectory: true),
        packageRoot.appendingPathComponent("build", isDirectory: true),
    ] {
        guard let enumerator = fileManager.enumerator(
            at: searchRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { continue }
        while let item = enumerator.nextObject() as? URL {
            if hasCoreArtifacts(item) { return item }
        }
    }
    throw NSError(domain: "AgentLensTests", code: 3,
                  userInfo: [NSLocalizedDescriptionKey: "could not locate active AgentLensCore build products"])
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
        shadowedInstallationCount: 0
    )
}

private func probeSubject(_ diagnostic: ToolPathDiagnostic, id: String, displayName: String? = nil) -> UpdateProbeSubject {
    UpdateProbeSubject(
        registryID: id,
        displayName: displayName ?? diagnostic.detectedTool.displayName,
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
        .unknown(installed: Version("0.162.1"), reason: .unsupportedSource),
        .unknown(installed: nil, reason: .notInstalled),
        .unknown(installed: Version("2.0.28"), reason: .noRegistry),
    ])
}

private func npmDiagnostic(_ tool: DetectedTool) -> ToolPathDiagnostic {
    ToolPathDiagnostic(
        detectedTool: tool, pathCandidates: [], firstLiveCandidate: nil, targetGroups: [],
        repeatedPathSlotCount: 0, sameTargetAliasCount: 0, selection: .notInstalled, shadowedInstallationCount: 0
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
        shadowedInstallationCount: 0
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
        selection: .inconsistent("disagreement"), shadowedInstallationCount: nil
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
        await HomebrewUpdateProbeTestHooks.observingAdmissionQueue({
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
        await HomebrewUpdateProbeTestHooks.observingAdmissionQueue({
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
            await HomebrewUpdateProbeTestHooks.observingAdmissionQueue({
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
        shadowedInstallationCount: 0
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
                versionQuery: { _, _, _ in "0.162.1" }
            )
            let diagnostic = PathDiagnosticsScanner.scan(detector: detector, environment: environment)
            let subject = UpdateProbeSubject(registryID: "codex", displayName: "Codex", diagnostic: diagnostic)
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

    let products = try coreProductsForContextVerifier()
    let compiler = Process()
    compiler.executableURL = URL(fileURLWithPath: "/usr/bin/swiftc")
    compiler.arguments = [
        "-parse-as-library", "-I", products.path, sourceURL.path,
        products.appendingPathComponent("AgentLensCore.o").path,
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
        let expected = "counts=3,0;inputs=true;identity=true;cacheHit=true;cwd=\(workingDirectory.path)\n"
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
        selection: .notInstalled, shadowedInstallationCount: 0
    )
    let inconsistentDiagnostic = ToolPathDiagnostic(
        detectedTool: diagnostic.detectedTool, pathCandidates: diagnostic.pathCandidates,
        firstLiveCandidate: diagnostic.firstLiveCandidate, targetGroups: diagnostic.targetGroups,
        repeatedPathSlotCount: diagnostic.repeatedPathSlotCount,
        sameTargetAliasCount: diagnostic.sameTargetAliasCount,
        selection: .inconsistent("synthetic inconsistent selection"),
        shadowedInstallationCount: nil
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
