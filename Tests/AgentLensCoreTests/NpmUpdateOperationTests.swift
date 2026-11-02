import Foundation
import Testing
@testable import AgentLensCore

private func operationFixtureRoot(_ label: String) throws -> URL {
    let environment = ProcessInfo.processInfo.environment
    guard let basePath = [environment["AGENT_LENS_TEST_SCRATCH"], environment["TMPDIR"]]
        .compactMap({ $0 })
        .first(where: { !$0.isEmpty })
    else {
        throw NSError(domain: "NpmUpdateOperationTests", code: 1)
    }
    let root = URL(fileURLWithPath: basePath, isDirectory: true)
        .appendingPathComponent("agentlens-m10c-operation-\(label)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root.resolvingSymlinksInPath()
}

private func writeOperationExecutable(_ url: URL) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
}

private struct OperationFixture {
    let root: URL
    let prefix: URL
    let globalRoot: URL
    let managerDirectory: URL
    let alias: URL
    let target: URL
    let package: String
    let executableName: String
    let environment: ShellEnvironment

    init(_ label: String, package: String = "codex-ai", executableName: String = "codex-ai") throws {
        self.package = package
        self.executableName = executableName
        root = try operationFixtureRoot(label)
        prefix = root.appendingPathComponent("prefix", isDirectory: true)
        globalRoot = prefix.appendingPathComponent("lib/node_modules", isDirectory: true)
        managerDirectory = root.appendingPathComponent("manager-bin", isDirectory: true)
        let aliasDirectory = root.appendingPathComponent("alias-bin", isDirectory: true)
        try FileManager.default.createDirectory(at: managerDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: aliasDirectory, withIntermediateDirectories: true)
        try writeOperationExecutable(managerDirectory.appendingPathComponent("npm"))

        var packageURL = globalRoot
        for component in package.split(separator: "/", omittingEmptySubsequences: false) {
            packageURL.appendPathComponent(String(component), isDirectory: true)
        }
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        target = packageURL.appendingPathComponent("bin/codex.js")
        try writeOperationExecutable(target)
        let manifest: [String: Any] = [
            "name": package,
            "version": "1.0.0",
            "bin": [executableName: "bin/codex.js"],
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
        let joined = [managerDirectory.path, aliasDirectory.path].joined(separator: ":")
        environment = ShellEnvironment(
            shellPath: "/bin/zsh",
            pathEntries: [managerDirectory.path, aliasDirectory.path],
            pathJoined: joined,
            raw: ["PATH": joined, "HOME": "/synthetic/home"],
            isDegraded: false
        )
    }

    func definition() throws -> DetectorDefinition {
        try DetectorDefinition(
            id: "codex-id",
            displayName: "Codex",
            executableName: executableName,
            extraSearchRoots: [],
            fixture: nil,
            category: .aiAgent,
            packages: [try DeclaredPackage(manager: .npm, name: package)],
            informationURL: nil,
            uninstallInstructionsURL: nil,
            versionQuery: .standard
        )
    }

    func diagnostic(version: String) -> ToolPathDiagnostic {
        let target = URL(fileURLWithPath: alias.path).resolvingSymlinksInPath().standardizedFileURL.path
        let directory = alias.deletingLastPathComponent().path
        let candidate = PathCandidateObservation(
            origin: .path(slotIndex: 0, directoryText: directory),
            entryPath: alias.path,
            kind: .executableSymlink,
            canonicalTarget: target
        )
        let detected = DetectedTool(
            displayName: "Codex",
            executableName: executableName,
            state: .installedAndOnPath,
            entryPath: alias.path,
            resolvedPath: target,
            source: "npm",
            version: version
        )
        return ToolPathDiagnostic(
            detectedTool: detected,
            pathCandidates: [candidate],
            firstLiveCandidate: candidate,
            targetGroups: [
                PathTargetGroup(canonicalTarget: target, entryPaths: [alias.path], firstSlotIndex: 0)
            ],
            repeatedPathSlotCount: 0,
            sameTargetAliasCount: 0,
            selection: .winner(candidate),
            shadowedInstallationCount: 0,
            installationVersions: []
        )
    }

    func diagnosticMissingVersion() -> ToolPathDiagnostic {
        let target = URL(fileURLWithPath: alias.path).resolvingSymlinksInPath().standardizedFileURL.path
        let directory = alias.deletingLastPathComponent().path
        let candidate = PathCandidateObservation(
            origin: .path(slotIndex: 0, directoryText: directory),
            entryPath: alias.path,
            kind: .executableSymlink,
            canonicalTarget: target
        )
        let detected = DetectedTool(
            displayName: "Codex", executableName: executableName,
            state: .installedAndOnPath, entryPath: alias.path, resolvedPath: target,
            source: "npm", version: nil
        )
        return ToolPathDiagnostic(
            detectedTool: detected, pathCandidates: [candidate], firstLiveCandidate: candidate,
            targetGroups: [PathTargetGroup(canonicalTarget: target, entryPaths: [alias.path], firstSlotIndex: 0)],
            repeatedPathSlotCount: 0, sameTargetAliasCount: 0, selection: .winner(candidate),
            shadowedInstallationCount: 0, installationVersions: []
        )
    }
}

private enum OperationNpmCommand {
    case prefix, root, configBase, configScope, version, view, other
}

private func categorizeOperationNpm(_ arguments: [String]) -> OperationNpmCommand {
    if arguments.contains("prefix") { return .prefix }
    if arguments.contains("root") { return .root }
    if arguments.contains("--version") { return .version }
    if arguments.contains("view") { return .view }
    if arguments.contains(where: { $0.hasSuffix(":registry") }) { return .configScope }
    if arguments.contains("registry") { return .configBase }
    return .other
}

private final class OperationNpmRunner: UpdateCommandRunner, @unchecked Sendable {
    let prefix: String
    let root: String
    let package: String
    let viewVersion: String
    let baseRegistry: String
    let scopeRegistry: String
    private let lock = NSLock()
    private var recorded: [[String]] = []

    init(fixture: OperationFixture, viewVersion: String = "2.0.0",
         baseRegistry: String = "https://registry.npmjs.org/",
         prefixOverride: String? = nil, rootOverride: String? = nil,
         scopeRegistry: String = "undefined") {
        self.prefix = prefixOverride ?? fixture.prefix.path
        self.root = rootOverride ?? fixture.globalRoot.path
        self.package = fixture.package
        self.viewVersion = viewVersion
        self.baseRegistry = baseRegistry
        self.scopeRegistry = scopeRegistry
    }

    var invocations: [[String]] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    private func note(_ arguments: [String]) {
        lock.lock()
        recorded.append(arguments)
        lock.unlock()
    }

    func run(
        executablePath: String, arguments: [String],
        environment: [String: String], timeout: TimeInterval
    ) async -> CommandOutcome {
        note(arguments)
        switch categorizeOperationNpm(arguments) {
        case .prefix: return .success(Data((prefix + "\n").utf8))
        case .root: return .success(Data((root + "\n").utf8))
        case .configBase: return .success(Data((baseRegistry + "\n").utf8))
        case .configScope: return .success(Data((scopeRegistry + "\n").utf8))
        case .version: return .success(Data("10.9.8\n".utf8))
        case .view:
            return .success(Data(
                #"{"name":"\#(package)","version":"\#(viewVersion)","dist-tags.latest":"\#(viewVersion)"}"#.utf8
            ))
        case .other: return .failure(.spawnFailure)
        }
    }
}

private final class RecordingOperationRunner: OperationCommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [[String]] = []
    let stdout: Data
    let stderr: Data
    let exitStatus: Int32

    init(stdout: String = "installed\n", stderr: String = "", exitStatus: Int32 = 0) {
        self.stdout = Data(stdout.utf8)
        self.stderr = Data(stderr.utf8)
        self.exitStatus = exitStatus
    }

    var invocations: [[String]] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    private func note(_ arguments: [String]) {
        lock.lock()
        recorded.append(arguments)
        lock.unlock()
    }

    func run(
        executablePath: String, arguments: [String],
        environment: [String: String], currentDirectory: String, timeout: TimeInterval
    ) async -> OperationCommandResult {
        note(arguments)
        return OperationCommandResult(
            stdout: stdout, stderr: stderr,
            stdoutTruncated: false, stderrTruncated: false,
            exitStatus: exitStatus, processStarted: true,
            timedOut: false, cancelled: false, cleanupWarning: false
        )
    }
}

private final class OperationScanState: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private let before: ToolPathDiagnostic
    private let after: ToolPathDiagnostic

    init(before: ToolPathDiagnostic, after: ToolPathDiagnostic) {
        self.before = before
        self.after = after
    }

    func next() -> ToolPathDiagnostic {
        lock.lock(); defer { lock.unlock() }
        count += 1
        return count == 1 ? before : after
    }
}

@Test func preparationBindsExactUnscopedArgvAndExecutionReconcilesToSuccess() async throws {
    let fixture = try OperationFixture("success")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition()
    let before = fixture.diagnostic(version: "1.0.0")
    let after = fixture.diagnostic(version: "2.0.0")
    let updateRunner = OperationNpmRunner(fixture: fixture)
    let operationRunner = RecordingOperationRunner()
    let scanState = OperationScanState(before: before, after: after)

    let prepared = await NpmUpdateOperation.prepare(
        definition: definition,
        diagnostic: before,
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: updateRunner,
        operationRootBaseURL: fixture.root
    )
    guard case .ready(let preparation) = prepared else {
        Issue.record("expected preparation")
        return
    }
    #expect(preparation.preview.installedVersion == "1.0.0")
    #expect(preparation.preview.targetVersion == "2.0.0")
    #expect(preparation.preview.packageName == fixture.package)
    #expect(preparation.preview.arguments.contains("install"))
    #expect(preparation.preview.arguments.contains("\(fixture.package)@2.0.0"))
    #expect(!preparation.preview.arguments.contains("@latest"))
    #expect(preparation.preview.arguments.contains("--no-save"))
    #expect(preparation.preview.arguments.contains("--fetch-retries=0"))

    let outcome = await NpmUpdateOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in scanState.next() },
        reconcileAfterLaunch: { _ in (scanState.next(), fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: operationRunner,
        gate: OperationExecutionGate()
    )
    #expect(outcome.state == .succeeded)
    #expect(outcome.processStarted)
    #expect(outcome.exitStatus == 0)
    #expect(outcome.reconciliation?.versionMatchesTarget == true)
    #expect(outcome.reconciliation?.afterVersion == "2.0.0")
    #expect(operationRunner.invocations.count == 1)
    let argv = try #require(operationRunner.invocations.first)
    #expect(preparation.preview.executablePath == fixture.managerDirectory.appendingPathComponent("npm").path)
    #expect(argv.first == "--cache")
    #expect(argv.contains("--global"))
    #expect(argv.contains("--prefix"))
    #expect(argv.contains(fixture.prefix.path))
    #expect(argv.contains("\(fixture.package)@2.0.0"))
    #expect(!argv.contains("@latest"))
    #expect(FileManager.default.fileExists(atPath: preparation.preview.workingDirectory) == false)
}

@Test func replayedPreparationCannotLaunchASecondMutation() async throws {
    let fixture = try OperationFixture("replay")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition()
    let before = fixture.diagnostic(version: "1.0.0")
    let after = fixture.diagnostic(version: "2.0.0")
    let updateRunner = OperationNpmRunner(fixture: fixture)
    let operationRunner = RecordingOperationRunner()
    let scanState = OperationScanState(before: before, after: after)
    guard case .ready(let preparation) = await NpmUpdateOperation.prepare(
        definition: definition, diagnostic: before, environment: fixture.environment,
        currentDirectory: fixture.root.path, runner: updateRunner,
        operationRootBaseURL: fixture.root
    ) else {
        Issue.record("expected preparation")
        return
    }
    let gate = OperationExecutionGate()
    _ = await NpmUpdateOperation.execute(
        confirmed: preparation, environment: fixture.environment,
        scan: { _, _, _ in scanState.next() },
        reconcileAfterLaunch: { _ in (scanState.next(), fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: operationRunner, gate: gate
    )
    let replay = await NpmUpdateOperation.execute(
        confirmed: preparation, environment: fixture.environment,
        scan: { _, _, _ in scanState.next() },
        reconcileAfterLaunch: { _ in (scanState.next(), fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: operationRunner, gate: gate
    )
    #expect(replay.state == .failed)
    #expect(!replay.processStarted)
    #expect(operationRunner.invocations.count == 1)
}

@Test func staleLocalSelectionRefusesBeforeLaunch() async throws {
    let fixture = try OperationFixture("stale")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition()
    let before = fixture.diagnostic(version: "1.0.0")
    let stale = fixture.diagnostic(version: "1.1.0")
    let updateRunner = OperationNpmRunner(fixture: fixture)
    let operationRunner = RecordingOperationRunner()
    guard case .ready(let preparation) = await NpmUpdateOperation.prepare(
        definition: definition, diagnostic: before, environment: fixture.environment,
        currentDirectory: fixture.root.path, runner: updateRunner,
        operationRootBaseURL: fixture.root
    ) else {
        Issue.record("expected preparation")
        return
    }
    let outcome = await NpmUpdateOperation.execute(
        confirmed: preparation, environment: fixture.environment,
        scan: { _, _, _ in stale },
        reconcileAfterLaunch: { _ in (stale, fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: operationRunner, gate: OperationExecutionGate()
    )
    #expect(outcome.state == .failed)
    #expect(!outcome.processStarted)
    #expect(operationRunner.invocations.isEmpty)
}

@Test func gateBusyRefusesWithoutLaunch() async throws {
    let fixture = try OperationFixture("gate")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition()
    let before = fixture.diagnostic(version: "1.0.0")
    let updateRunner = OperationNpmRunner(fixture: fixture)
    let operationRunner = RecordingOperationRunner()
    guard case .ready(let preparation) = await NpmUpdateOperation.prepare(
        definition: definition, diagnostic: before, environment: fixture.environment,
        currentDirectory: fixture.root.path, runner: updateRunner,
        operationRootBaseURL: fixture.root
    ) else {
        Issue.record("expected preparation")
        return
    }
    let gate = OperationExecutionGate()
    #expect(await gate.acquire())
    let outcome = await NpmUpdateOperation.execute(
        confirmed: preparation, environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (before, fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: operationRunner, gate: gate
    )
    #expect(outcome.state == .cancelled)
    #expect(!outcome.processStarted)
    #expect(operationRunner.invocations.isEmpty)
    await gate.release()
}

@Test func scopedPreparationPinsScopeRegistryAndCancelReleasesOwnedRoot() async throws {
    let fixture = try OperationFixture("scoped", package: "@openai/codex")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition()
    let before = fixture.diagnostic(version: "1.0.0")
    let updateRunner = OperationNpmRunner(fixture: fixture)
    guard case .ready(let preparation) = await NpmUpdateOperation.prepare(
        definition: definition, diagnostic: before, environment: fixture.environment,
        currentDirectory: fixture.root.path, runner: updateRunner,
        operationRootBaseURL: fixture.root
    ) else {
        Issue.record("expected scoped preparation")
        return
    }
    #expect(preparation.preview.packageName == "@openai/codex")
    #expect(preparation.preview.arguments.contains("--@openai:registry=https://registry.npmjs.org/"))
    let root = preparation.preview.workingDirectory
    #expect(FileManager.default.fileExists(atPath: root))
    #expect(NpmUpdateOperation.cancel(preparation))
    #expect(!FileManager.default.fileExists(atPath: root))
}

@Test func nonzeroOperationRetainsBothStreamsExitAndMeasuredDelta() async throws {
    let fixture = try OperationFixture("nonzero")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition()
    let before = fixture.diagnostic(version: "1.0.0")
    let after = fixture.diagnostic(version: "2.0.0")
    let updateRunner = OperationNpmRunner(fixture: fixture)
    let operationRunner = RecordingOperationRunner(
        stdout: "out\n", stderr: "failure\n", exitStatus: 42
    )
    let scanState = OperationScanState(before: before, after: after)
    guard case .ready(let preparation) = await NpmUpdateOperation.prepare(
        definition: definition, diagnostic: before, environment: fixture.environment,
        currentDirectory: fixture.root.path, runner: updateRunner,
        operationRootBaseURL: fixture.root
    ) else {
        Issue.record("expected preparation")
        return
    }
    let outcome = await NpmUpdateOperation.execute(
        confirmed: preparation, environment: fixture.environment,
        scan: { _, _, _ in scanState.next() },
        reconcileAfterLaunch: { _ in (scanState.next(), fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: operationRunner, gate: OperationExecutionGate()
    )
    #expect(outcome.state == .failed)
    #expect(outcome.processStarted)
    #expect(outcome.exitStatus == 42)
    #expect(outcome.stdoutText == "out\n")
    #expect(outcome.stderrText == "failure\n")
    #expect(outcome.reconciliation?.afterVersion == "2.0.0")
    #expect(outcome.reconciliation?.changed == true)
}

private final class CleanupBreakingOperationRunner: OperationCommandRunner, @unchecked Sendable {
    func run(executablePath: String, arguments: [String], environment: [String: String],
             currentDirectory: String, timeout: TimeInterval) async -> OperationCommandResult {
        try? FileManager.default.removeItem(atPath: currentDirectory)
        try? FileManager.default.createDirectory(
            atPath: currentDirectory, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        return OperationCommandResult(
            stdout: Data("installed\n".utf8), stderr: Data(),
            stdoutTruncated: false, stderrTruncated: false,
            exitStatus: 0, processStarted: true,
            timedOut: false, cancelled: false, cleanupWarning: false
        )
    }
}

private final class NoExitStatusOperationRunner: OperationCommandRunner, @unchecked Sendable {
    func run(executablePath: String, arguments: [String], environment: [String: String],
             currentDirectory: String, timeout: TimeInterval) async -> OperationCommandResult {
        OperationCommandResult(
            stdout: Data("observed\n".utf8), stderr: Data("diagnostic\n".utf8),
            stdoutTruncated: false, stderrTruncated: false,
            exitStatus: nil, processStarted: true,
            timedOut: false, cancelled: false, cleanupWarning: false
        )
    }
}

@Test func cleanupRefusalKeepsProvenSuccessAndAddsWarning() async throws {
    let fixture = try OperationFixture("cleanup-warning")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition()
    let before = fixture.diagnostic(version: "1.0.0")
    let after = fixture.diagnostic(version: "2.0.0")
    let updateRunner = OperationNpmRunner(fixture: fixture)
    let scanState = OperationScanState(before: before, after: after)
    guard case .ready(let preparation) = await NpmUpdateOperation.prepare(
        definition: definition, diagnostic: before, environment: fixture.environment,
        currentDirectory: fixture.root.path, runner: updateRunner,
        operationRootBaseURL: fixture.root
    ) else {
        Issue.record("expected preparation")
        return
    }
    let outcome = await NpmUpdateOperation.execute(
        confirmed: preparation, environment: fixture.environment,
        scan: { _, _, _ in scanState.next() },
        reconcileAfterLaunch: { _ in (scanState.next(), fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: CleanupBreakingOperationRunner(),
        gate: OperationExecutionGate()
    )
    #expect(outcome.state == .succeeded)
    #expect(outcome.exitStatus == 0)
    #expect(!outcome.cleanupWarnings.isEmpty)
}

@Test func missingObservedExitStatusIsUncertainAndPreservesOutput() async throws {
    let fixture = try OperationFixture("no-exit")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition()
    let before = fixture.diagnostic(version: "1.0.0")
    let after = fixture.diagnostic(version: "2.0.0")
    let updateRunner = OperationNpmRunner(fixture: fixture)
    let scanState = OperationScanState(before: before, after: after)
    guard case .ready(let preparation) = await NpmUpdateOperation.prepare(
        definition: definition, diagnostic: before, environment: fixture.environment,
        currentDirectory: fixture.root.path, runner: updateRunner,
        operationRootBaseURL: fixture.root
    ) else {
        Issue.record("expected preparation")
        return
    }
    let outcome = await NpmUpdateOperation.execute(
        confirmed: preparation, environment: fixture.environment,
        scan: { _, _, _ in scanState.next() },
        reconcileAfterLaunch: { _ in (scanState.next(), fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: NoExitStatusOperationRunner(),
        gate: OperationExecutionGate()
    )
    #expect(outcome.state == .uncertain)
    #expect(outcome.exitStatus == nil)
    #expect(outcome.stdoutText == "observed\n")
    #expect(outcome.stderrText == "diagnostic\n")
}

private func writeOperationVersionScript(_ url: URL, version: String) throws {
    try Data("#!/bin/sh\necho \(version)\n".utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
}

@Test func reconciliationKeepsSuccessForSameTargetAliasWinnerChange() async throws {
    let fixture = try OperationFixture("alias-winner")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition()
    try writeOperationVersionScript(fixture.target, version: "1.0.0")
    let before = PathDiagnosticsScanner.scan(
        detector: definition.makeDetector(), environment: fixture.environment,
        currentDirectory: fixture.root.path
    )
    let alias2Directory = fixture.root.appendingPathComponent("alias2-bin", isDirectory: true)
    try FileManager.default.createDirectory(at: alias2Directory, withIntermediateDirectories: true)
    let alias2 = alias2Directory.appendingPathComponent(fixture.executableName)
    try FileManager.default.createSymbolicLink(atPath: alias2.path, withDestinationPath: fixture.target.path)
    let afterPath = [fixture.managerDirectory.path, alias2Directory.path].joined(separator: ":")
    let afterEnvironment = ShellEnvironment(
        shellPath: "/bin/zsh",
        pathEntries: [fixture.managerDirectory.path, alias2Directory.path],
        pathJoined: afterPath,
        raw: ["PATH": afterPath, "HOME": "/synthetic/home"], isDegraded: false
    )
    try writeOperationVersionScript(fixture.target, version: "2.0.0")
    let after = PathDiagnosticsScanner.scan(
        detector: definition.makeDetector(), environment: afterEnvironment,
        currentDirectory: fixture.root.path
    )
    let updateRunner = OperationNpmRunner(fixture: fixture)
    guard case .ready(let preparation) = await NpmUpdateOperation.prepare(
        definition: definition, diagnostic: before, environment: fixture.environment,
        currentDirectory: fixture.root.path, runner: updateRunner,
        operationRootBaseURL: fixture.root
    ) else {
        Issue.record("expected preparation")
        return
    }
    let outcome = await NpmUpdateOperation.execute(
        confirmed: preparation, environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (after, afterEnvironment) },
        updateRunner: updateRunner,
        operationRunner: RecordingOperationRunner(),
        gate: OperationExecutionGate()
    )
    #expect(outcome.state == .succeeded)
    #expect(outcome.reconciliation?.versionMatchesTarget == true)
    #expect(outcome.reconciliation?.afterEntryPath == alias2.path)
    #expect(outcome.reconciliation?.afterTarget == fixture.target.path)
}

@Test func reconciliationReportsUncertainWhenPathWinnerHasDifferentTarget() async throws {
    let fixture = try OperationFixture("different-winner")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition()
    try writeOperationVersionScript(fixture.target, version: "1.0.0")
    let before = PathDiagnosticsScanner.scan(
        detector: definition.makeDetector(), environment: fixture.environment,
        currentDirectory: fixture.root.path
    )
    let otherDirectory = fixture.root.appendingPathComponent("other-bin", isDirectory: true)
    try FileManager.default.createDirectory(at: otherDirectory, withIntermediateDirectories: true)
    let otherTarget = otherDirectory.appendingPathComponent("codex-ai")
    try writeOperationVersionScript(otherTarget, version: "2.0.0")
    let afterEnvironment = ShellEnvironment(
        shellPath: "/bin/zsh", pathEntries: [otherDirectory.path], pathJoined: otherDirectory.path,
        raw: ["PATH": otherDirectory.path, "HOME": "/synthetic/home"], isDegraded: false
    )
    let after = PathDiagnosticsScanner.scan(
        detector: definition.makeDetector(), environment: afterEnvironment,
        currentDirectory: fixture.root.path
    )
    let updateRunner = OperationNpmRunner(fixture: fixture)
    guard case .ready(let preparation) = await NpmUpdateOperation.prepare(
        definition: definition, diagnostic: before, environment: fixture.environment,
        currentDirectory: fixture.root.path, runner: updateRunner,
        operationRootBaseURL: fixture.root
    ) else {
        Issue.record("expected preparation")
        return
    }
    let outcome = await NpmUpdateOperation.execute(
        confirmed: preparation, environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (after, afterEnvironment) },
        updateRunner: updateRunner,
        operationRunner: RecordingOperationRunner(),
        gate: OperationExecutionGate()
    )
    #expect(outcome.state == .uncertain)
    #expect(outcome.reconciliation?.versionMatchesTarget == true)
    #expect(outcome.reconciliation?.afterTarget == otherTarget.path)
}

private func prepareDrift(
    fixture: OperationFixture, definition: DetectorDefinition,
    diagnostic: ToolPathDiagnostic, runner: OperationNpmRunner
) async throws -> NpmUpdatePreparation {
    guard case .ready(let preparation) = await NpmUpdateOperation.prepare(
        definition: definition, diagnostic: diagnostic, environment: fixture.environment,
        currentDirectory: fixture.root.path, runner: runner,
        operationRootBaseURL: fixture.root
    ) else {
        throw NSError(domain: "NpmUpdateOperationTests", code: 2)
    }
    return preparation
}

private func expectRefused(_ outcome: OperationOutcome, _ runner: RecordingOperationRunner) {
    #expect(outcome.state == .failed)
    #expect(!outcome.processStarted)
    #expect(runner.invocations.isEmpty)
    #expect(outcome.message != nil)
}

@Test func staleRegistryRouteRefusesBeforeLaunch() async throws {
    let fixture = try OperationFixture("drift-registry")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition()
    let before = fixture.diagnostic(version: "1.0.0")
    let preparation = try await prepareDrift(
        fixture: fixture, definition: definition, diagnostic: before,
        runner: OperationNpmRunner(fixture: fixture)
    )
    let changed = OperationNpmRunner(fixture: fixture, baseRegistry: "https://evil.example/")
    let operationRunner = RecordingOperationRunner()
    let outcome = await NpmUpdateOperation.execute(
        confirmed: preparation, environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (before, fixture.environment) },
        updateRunner: changed, operationRunner: operationRunner, gate: OperationExecutionGate()
    )
    expectRefused(outcome, operationRunner)
}

@Test func staleScopeRegistryRouteRefusesBeforeLaunch() async throws {
    let fixture = try OperationFixture("drift-scope", package: "@openai/codex")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition()
    let before = fixture.diagnostic(version: "1.0.0")
    let preparation = try await prepareDrift(
        fixture: fixture, definition: definition, diagnostic: before,
        runner: OperationNpmRunner(fixture: fixture)
    )
    let changed = OperationNpmRunner(fixture: fixture, scopeRegistry: "https://evil.example/")
    let operationRunner = RecordingOperationRunner()
    let outcome = await NpmUpdateOperation.execute(
        confirmed: preparation, environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (before, fixture.environment) },
        updateRunner: changed, operationRunner: operationRunner, gate: OperationExecutionGate()
    )
    expectRefused(outcome, operationRunner)
}

@Test func movingLatestTagRefusesBeforeLaunch() async throws {
    let fixture = try OperationFixture("drift-latest")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition()
    let before = fixture.diagnostic(version: "1.0.0")
    let preparation = try await prepareDrift(
        fixture: fixture, definition: definition, diagnostic: before,
        runner: OperationNpmRunner(fixture: fixture)
    )
    let changed = OperationNpmRunner(fixture: fixture, viewVersion: "3.0.0")
    let operationRunner = RecordingOperationRunner()
    let outcome = await NpmUpdateOperation.execute(
        confirmed: preparation, environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (before, fixture.environment) },
        updateRunner: changed, operationRunner: operationRunner, gate: OperationExecutionGate()
    )
    expectRefused(outcome, operationRunner)
}

@Test func staleManagerExecutableRefusesBeforeLaunch() async throws {
    let fixture = try OperationFixture("drift-manager")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition()
    let before = fixture.diagnostic(version: "1.0.0")
    let preparation = try await prepareDrift(
        fixture: fixture, definition: definition, diagnostic: before,
        runner: OperationNpmRunner(fixture: fixture)
    )
    try Data("#!/bin/sh\nexit 7\n".utf8).write(
        to: fixture.managerDirectory.appendingPathComponent("npm")
    )
    let operationRunner = RecordingOperationRunner()
    let outcome = await NpmUpdateOperation.execute(
        confirmed: preparation, environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (before, fixture.environment) },
        updateRunner: OperationNpmRunner(fixture: fixture),
        operationRunner: operationRunner, gate: OperationExecutionGate()
    )
    expectRefused(outcome, operationRunner)
}

@Test func stalePrefixRefusesBeforeLaunch() async throws {
    let fixture = try OperationFixture("drift-prefix")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition()
    let before = fixture.diagnostic(version: "1.0.0")
    let preparation = try await prepareDrift(
        fixture: fixture, definition: definition, diagnostic: before,
        runner: OperationNpmRunner(fixture: fixture)
    )
    let changed = OperationNpmRunner(
        fixture: fixture, prefixOverride: fixture.prefix.path + "-other"
    )
    let operationRunner = RecordingOperationRunner()
    let outcome = await NpmUpdateOperation.execute(
        confirmed: preparation, environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (before, fixture.environment) },
        updateRunner: changed, operationRunner: operationRunner, gate: OperationExecutionGate()
    )
    expectRefused(outcome, operationRunner)
}

@Test func staleOwnedRootRefusesBeforeLaunch() async throws {
    let fixture = try OperationFixture("drift-owned-root")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition()
    let before = fixture.diagnostic(version: "1.0.0")
    let preparation = try await prepareDrift(
        fixture: fixture, definition: definition, diagnostic: before,
        runner: OperationNpmRunner(fixture: fixture)
    )
    try FileManager.default.removeItem(atPath: preparation.preview.workingDirectory)
    try FileManager.default.createDirectory(
        atPath: preparation.preview.workingDirectory, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
    )
    let operationRunner = RecordingOperationRunner()
    let outcome = await NpmUpdateOperation.execute(
        confirmed: preparation, environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (before, fixture.environment) },
        updateRunner: OperationNpmRunner(fixture: fixture),
        operationRunner: operationRunner, gate: OperationExecutionGate()
    )
    expectRefused(outcome, operationRunner)
}

@Test func staleManifestIdentityRefusesBeforeLaunch() async throws {
    let fixture = try OperationFixture("drift-manifest")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition()
    let before = fixture.diagnostic(version: "1.0.0")
    let preparation = try await prepareDrift(
        fixture: fixture, definition: definition, diagnostic: before,
        runner: OperationNpmRunner(fixture: fixture)
    )
    let manifestURL = fixture.globalRoot
        .appendingPathComponent("\(fixture.package)/package.json")
    try Data(#"{"name":"other-package","version":"1.0.0"}"#.utf8).write(to: manifestURL)
    let operationRunner = RecordingOperationRunner()
    let outcome = await NpmUpdateOperation.execute(
        confirmed: preparation, environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (before, fixture.environment) },
        updateRunner: OperationNpmRunner(fixture: fixture),
        operationRunner: operationRunner, gate: OperationExecutionGate()
    )
    expectRefused(outcome, operationRunner)
}

@Test func staleBinIdentityRefusesBeforeLaunch() async throws {
    let fixture = try OperationFixture("drift-bin")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition()
    let before = fixture.diagnostic(version: "1.0.0")
    let preparation = try await prepareDrift(
        fixture: fixture, definition: definition, diagnostic: before,
        runner: OperationNpmRunner(fixture: fixture)
    )
    try Data("#!/bin/sh\necho changed\n".utf8).write(to: fixture.target)
    let operationRunner = RecordingOperationRunner()
    let outcome = await NpmUpdateOperation.execute(
        confirmed: preparation, environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (before, fixture.environment) },
        updateRunner: OperationNpmRunner(fixture: fixture),
        operationRunner: operationRunner, gate: OperationExecutionGate()
    )
    expectRefused(outcome, operationRunner)
}

@Test func staleSelectionTargetRefusesThroughARealScanBeforeLaunch() async throws {
    let fixture = try OperationFixture("drift-selection")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition()
    let before = fixture.diagnostic(version: "1.0.0")
    let preparation = try await prepareDrift(
        fixture: fixture, definition: definition, diagnostic: before,
        runner: OperationNpmRunner(fixture: fixture)
    )
    let other = fixture.root.appendingPathComponent("other/codex.js")
    try FileManager.default.createDirectory(
        at: other.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try writeOperationVersionScript(other, version: "2.0.0")
    try FileManager.default.removeItem(atPath: fixture.alias.path)
    try FileManager.default.createSymbolicLink(atPath: fixture.alias.path, withDestinationPath: other.path)
    let operationRunner = RecordingOperationRunner()
    let outcome = await NpmUpdateOperation.execute(
        confirmed: preparation, environment: fixture.environment,
        scan: { detector, environment, directory in
            PathDiagnosticsScanner.scan(
                detector: detector.makeDetector(),
                environment: environment, currentDirectory: directory
            )
        },
        reconcileAfterLaunch: { _ in (before, fixture.environment) },
        updateRunner: OperationNpmRunner(fixture: fixture),
        operationRunner: operationRunner, gate: OperationExecutionGate()
    )
    expectRefused(outcome, operationRunner)
}

private func executeFailureProbe(
    fixture: OperationFixture, definition: DetectorDefinition,
    operationRunner: OperationCommandRunner,
    afterVersion: String = "1.5.0"
) async throws -> OperationOutcome {
    let before = fixture.diagnostic(version: "1.0.0")
    let after = fixture.diagnostic(version: afterVersion)
    let updateRunner = OperationNpmRunner(fixture: fixture)
    guard case .ready(let preparation) = await NpmUpdateOperation.prepare(
        definition: definition, diagnostic: before, environment: fixture.environment,
        currentDirectory: fixture.root.path, runner: updateRunner,
        operationRootBaseURL: fixture.root
    ) else {
        throw NSError(domain: "NpmUpdateOperationTests", code: 3)
    }
    let scanState = OperationScanState(before: before, after: after)
    return await NpmUpdateOperation.execute(
        confirmed: preparation, environment: fixture.environment,
        scan: { _, _, _ in scanState.next() },
        reconcileAfterLaunch: { _ in (scanState.next(), fixture.environment) },
        updateRunner: updateRunner, operationRunner: operationRunner,
        gate: OperationExecutionGate()
    )
}

@Test func exitZeroWithWrongFinalVersionIsUncertainAndNeverClaimsSuccess() async throws {
    let fixture = try OperationFixture("wrong-final")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition()
    let runner = RecordingOperationRunner(
        stdout: "changed 1 package\n", stderr: "", exitStatus: 0
    )
    let outcome = try await executeFailureProbe(
        fixture: fixture, definition: definition, operationRunner: runner,
        afterVersion: "1.9.9"
    )
    #expect(outcome.state == .uncertain)
    #expect(outcome.processStarted)
    #expect(outcome.exitStatus == 0)
    #expect(outcome.reconciliation?.versionMatchesTarget == false)
    #expect(outcome.reconciliation?.afterVersion == "1.9.9")
    #expect(outcome.stdoutText == "changed 1 package\n")
    #expect(runner.invocations.count == 1)
}

@Test func exitZeroWithoutAFinalVersionIsUncertainAndKeepsObservedState() async throws {
    let fixture = try OperationFixture("missing-final")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition()
    let runner = RecordingOperationRunner(
        stdout: "changed 1 package\n", stderr: "note\n", exitStatus: 0
    )
    let before = fixture.diagnostic(version: "1.0.0")
    let updateRunner = OperationNpmRunner(fixture: fixture)
    guard case .ready(let preparation) = await NpmUpdateOperation.prepare(
        definition: definition, diagnostic: before, environment: fixture.environment,
        currentDirectory: fixture.root.path, runner: updateRunner,
        operationRootBaseURL: fixture.root
    ) else {
        Issue.record("expected preparation")
        return
    }
    let after = fixture.diagnosticMissingVersion()
    let outcome = await NpmUpdateOperation.execute(
        confirmed: preparation, environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (after, fixture.environment) },
        updateRunner: updateRunner, operationRunner: runner,
        gate: OperationExecutionGate()
    )
    #expect(outcome.state == .uncertain)
    #expect(outcome.exitStatus == 0)
    #expect(outcome.reconciliation?.afterVersion == nil)
    #expect(outcome.stdoutText == "changed 1 package\n")
    #expect(outcome.stderrText == "note\n")
}

private func waitForOperationFile(_ url: URL, timeout: TimeInterval = 5) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if FileManager.default.fileExists(atPath: url.path) { return true }
        Thread.sleep(forTimeInterval: 0.01)
    }
    return FileManager.default.fileExists(atPath: url.path)
}

private func waitForOperationProcessGone(_ pid: pid_t, timeout: TimeInterval = 5) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if kill(pid, 0) != 0 { return true }
        Thread.sleep(forTimeInterval: 0.02)
    }
    return kill(pid, 0) != 0
}

@Test func cancelledTaskBeforeLaunchReportsCancelledWithNoMutation() async throws {
    let fixture = try OperationFixture("cancel-before-launch")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition()
    let before = fixture.diagnostic(version: "1.0.0")
    let updateRunner = OperationNpmRunner(fixture: fixture)
    let operationRunner = RecordingOperationRunner()
    guard case .ready(let preparation) = await NpmUpdateOperation.prepare(
        definition: definition, diagnostic: before, environment: fixture.environment,
        currentDirectory: fixture.root.path, runner: updateRunner,
        operationRootBaseURL: fixture.root
    ) else {
        Issue.record("expected preparation")
        return
    }
    let task = Task {
        await NpmUpdateOperation.execute(
            confirmed: preparation, environment: fixture.environment,
            scan: { _, _, _ in before },
            reconcileAfterLaunch: { _ in (before, fixture.environment) },
            updateRunner: updateRunner, operationRunner: operationRunner,
            gate: OperationExecutionGate()
        )
    }
    task.cancel()
    let outcome = await task.value
    #expect(outcome.state == .cancelled)
    #expect(!outcome.processStarted)
    #expect(operationRunner.invocations.isEmpty)
    #expect(outcome.reconciliation == nil)
}

@Test func cancellingAfterSpawnInterruptsAndStillReconcilesWithoutOrphan() async throws {
    let fixture = try OperationFixture("cancel-after-spawn")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition()
    let before = fixture.diagnostic(version: "1.0.0")
    let after = fixture.diagnostic(version: "2.0.0")
    let updateRunner = OperationNpmRunner(fixture: fixture)
    let pidFile = fixture.root.appendingPathComponent("delayed-npm-pid")
    let manager = fixture.managerDirectory.appendingPathComponent("npm")
    try Data("#!/bin/sh\nprintf '%s' \"$$\" > '\(pidFile.path)'\nexec /bin/sleep 30\n".utf8)
        .write(to: manager)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: manager.path)
    guard case .ready(let preparation) = await NpmUpdateOperation.prepare(
        definition: definition, diagnostic: before, environment: fixture.environment,
        currentDirectory: fixture.root.path, runner: updateRunner,
        operationRootBaseURL: fixture.root
    ) else {
        Issue.record("expected preparation")
        return
    }
    let task = Task {
        await NpmUpdateOperation.execute(
            confirmed: preparation, environment: fixture.environment,
            scan: { _, _, _ in before },
            reconcileAfterLaunch: { _ in (after, fixture.environment) },
            updateRunner: updateRunner,
            operationRunner: ProcessOperationCommandRunner(),
            gate: OperationExecutionGate()
        )
    }
    #expect(waitForOperationFile(pidFile))
    let pid = try #require(pid_t(try String(contentsOf: pidFile, encoding: .utf8)))
    task.cancel()
    let outcome = await task.value
    #expect(outcome.state == .interrupted)
    #expect(outcome.processStarted)
    #expect(outcome.reconciliation?.afterVersion == "2.0.0")
    guard case .verified(let installation)? = outcome.reconciliation?.ownership else {
        Issue.record("cancelled reconciliation must still verify ownership")
        return
    }
    #expect(installation.packageName == fixture.package)
    #expect(waitForOperationProcessGone(pid), "the delayed operation process must be reaped")
    #expect(!FileManager.default.fileExists(atPath: preparation.preview.workingDirectory))
}

@Test func defaultPreparationRootUsesCapturedTemporaryDirectory() async throws {
    let fixture = try OperationFixture("captured-tmp")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition()
    let before = fixture.diagnostic(version: "1.0.0")
    let ownedTmp = fixture.root.appendingPathComponent("captured-tmp", isDirectory: true)
    try FileManager.default.createDirectory(
        at: ownedTmp, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
    )
    var raw = fixture.environment.raw
    raw["TMPDIR"] = ownedTmp.path
    let ownedPhysical = NpmScratchBase.physicalPath(of: ownedTmp.path) ?? ownedTmp.path
    let capturedEnvironment = ShellEnvironment(
        shellPath: fixture.environment.shellPath,
        pathEntries: fixture.environment.pathEntries,
        pathJoined: fixture.environment.pathJoined,
        raw: raw, isDegraded: false
    )
    guard case .ready(let preparation) = await NpmUpdateOperation.prepare(
        definition: definition, diagnostic: before, environment: capturedEnvironment,
        currentDirectory: fixture.root.path, runner: OperationNpmRunner(fixture: fixture),
        operationRootBaseURL: nil
    ) else {
        Issue.record("expected a preparation from the captured TMPDIR")
        return
    }
    #expect(preparation.preview.workingDirectory.hasPrefix(ownedPhysical + "/"))
    #expect(!preparation.preview.workingDirectory.hasPrefix(
        FileManager.default.temporaryDirectory.path
    ))
    _ = NpmUpdateOperation.cancel(preparation)
}

@Test func unsafeCapturedTemporaryDirectoryRefusesWithZeroMutation() async throws {
    let fixture = try OperationFixture("captured-tmp-unsafe")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition()
    let before = fixture.diagnostic(version: "1.0.0")
    let unsafeTmp = fixture.root.appendingPathComponent("unsafe-tmp", isDirectory: true)
    try FileManager.default.createDirectory(
        at: unsafeTmp, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o777]
    )
    var raw = fixture.environment.raw
    raw["TMPDIR"] = unsafeTmp.path
    let capturedEnvironment = ShellEnvironment(
        shellPath: fixture.environment.shellPath,
        pathEntries: fixture.environment.pathEntries,
        pathJoined: fixture.environment.pathJoined,
        raw: raw, isDegraded: false
    )
    let updateRunner = OperationNpmRunner(fixture: fixture)
    let result = await NpmUpdateOperation.prepare(
        definition: definition, diagnostic: before, environment: capturedEnvironment,
        currentDirectory: fixture.root.path, runner: updateRunner,
        operationRootBaseURL: nil
    )
    guard case .unavailable(.operationRootUnsafe) = result else {
        Issue.record("an unsafe captured TMPDIR must fail closed")
        return
    }
    #expect(updateRunner.invocations.isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: unsafeTmp.path).isEmpty)
}

private final class CacheSentinelRunner: UpdateCommandRunner, @unchecked Sendable {
    let inner: OperationNpmRunner
    let sentinel: String
    init(fixture: OperationFixture, sentinel: String) {
        self.inner = OperationNpmRunner(fixture: fixture)
        self.sentinel = sentinel
    }
    func run(executablePath: String, arguments: [String], environment: [String: String], timeout: TimeInterval) async -> CommandOutcome {
        let cache = environment["NPM_CONFIG_CACHE"] ?? environment["npm_config_cache"]
        if cache == sentinel {
            try? Data("leak\n".utf8).write(to: URL(fileURLWithPath: sentinel + "/leak"))
        }
        return await inner.run(executablePath: executablePath, arguments: arguments,
                               environment: environment, timeout: timeout)
    }
}

@Test func postLaunchOwnershipQueryUsesOwnedCacheScratch() async throws {
    let fixture = try OperationFixture("ownership-cache")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let sentinel = fixture.root.appendingPathComponent("captured-cache", isDirectory: true)
    try FileManager.default.createDirectory(
        at: sentinel, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
    )
    var raw = fixture.environment.raw
    raw["NPM_CONFIG_CACHE"] = sentinel.path
    raw["npm_config_cache"] = sentinel.path
    let environment = ShellEnvironment(
        shellPath: fixture.environment.shellPath,
        pathEntries: fixture.environment.pathEntries,
        pathJoined: fixture.environment.pathJoined,
        raw: raw, isDegraded: false
    )
    let definition = try fixture.definition()
    let before = fixture.diagnostic(version: "1.0.0")
    let after = fixture.diagnostic(version: "2.0.0")
    let updateRunner = CacheSentinelRunner(fixture: fixture, sentinel: sentinel.path)
    guard case .ready(let preparation) = await NpmUpdateOperation.prepare(
        definition: definition, diagnostic: before, environment: environment,
        currentDirectory: fixture.root.path, runner: updateRunner,
        operationRootBaseURL: fixture.root
    ) else {
        Issue.record("expected preparation")
        return
    }
    try? FileManager.default.removeItem(at: sentinel.appendingPathComponent("leak"))
    let scanState = OperationScanState(before: before, after: after)
    let outcome = await NpmUpdateOperation.execute(
        confirmed: preparation, environment: environment,
        scan: { _, _, _ in scanState.next() },
        reconcileAfterLaunch: { _ in (scanState.next(), environment) },
        updateRunner: updateRunner,
        operationRunner: RecordingOperationRunner(),
        gate: OperationExecutionGate()
    )
    #expect(outcome.state == .succeeded)
    #expect(!FileManager.default.fileExists(atPath: sentinel.appendingPathComponent("leak").path),
            "post-launch ownership queries must not reuse the captured shared npm cache")
}

private final class QueryScratchBreakingRunner: UpdateCommandRunner, @unchecked Sendable {
    let inner: OperationNpmRunner
    private var armed = false
    init(fixture: OperationFixture) { self.inner = OperationNpmRunner(fixture: fixture) }
    func arm() { armed = true }
    func run(executablePath: String, arguments: [String], environment: [String: String],
             timeout: TimeInterval) async -> CommandOutcome {
        let shouldBreak = armed
        if shouldBreak { armed = false }
        if shouldBreak, let cache = environment["NPM_CONFIG_CACHE"] ?? environment["npm_config_cache"] {
            try? FileManager.default.removeItem(atPath: cache)
            try? FileManager.default.createDirectory(
                atPath: cache, withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
        }
        return await inner.run(executablePath: executablePath, arguments: arguments,
                               environment: environment, timeout: timeout)
    }
}

private final class ArmQueryScratchOperationRunner: OperationCommandRunner, @unchecked Sendable {
    let query: QueryScratchBreakingRunner
    init(query: QueryScratchBreakingRunner) { self.query = query }
    func run(executablePath: String, arguments: [String], environment: [String: String],
             currentDirectory: String, timeout: TimeInterval) async -> OperationCommandResult {
        query.arm()
        return OperationCommandResult(
            stdout: Data("installed\n".utf8), stderr: Data(),
            stdoutTruncated: false, stderrTruncated: false,
            exitStatus: 0, processStarted: true,
            timedOut: false, cancelled: false, cleanupWarning: false
        )
    }
}

@Test func ownershipQueryScratchReleaseRefusalKeepsSuccessAndWarning() async throws {
    let fixture = try OperationFixture("query-scratch-release")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition()
    let before = fixture.diagnostic(version: "1.0.0")
    let after = fixture.diagnostic(version: "2.0.0")
    let updateRunner = QueryScratchBreakingRunner(fixture: fixture)
    guard case .ready(let preparation) = await NpmUpdateOperation.prepare(
        definition: definition, diagnostic: before, environment: fixture.environment,
        currentDirectory: fixture.root.path, runner: updateRunner,
        operationRootBaseURL: fixture.root
    ) else {
        Issue.record("expected preparation")
        return
    }
    let scanState = OperationScanState(before: before, after: after)
    let outcome = await NpmUpdateOperation.execute(
        confirmed: preparation, environment: fixture.environment,
        scan: { _, _, _ in scanState.next() },
        reconcileAfterLaunch: { _ in (scanState.next(), fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: ArmQueryScratchOperationRunner(query: updateRunner),
        gate: OperationExecutionGate()
    )
    #expect(outcome.state == .succeeded)
    #expect(outcome.cleanupWarnings.contains { $0.contains("ownership query scratch") })
}

private final class BreakingQueryBaseOperationRunner: OperationCommandRunner, @unchecked Sendable {
    func run(executablePath: String, arguments: [String], environment: [String: String],
             currentDirectory: String, timeout: TimeInterval) async -> OperationCommandResult {
        let base = URL(fileURLWithPath: currentDirectory).deletingLastPathComponent()
        try? FileManager.default.removeItem(at: base)
        return OperationCommandResult(
            stdout: Data("installed\n".utf8), stderr: Data(),
            stdoutTruncated: false, stderrTruncated: false,
            exitStatus: 0, processStarted: true,
            timedOut: false, cancelled: false, cleanupWarning: false
        )
    }
}

@Test func failedOwnershipQueryBaseClaimIsUntrustedContainmentNotSelection() async throws {
    let fixture = try OperationFixture("query-base-refusal")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let operationBase = fixture.root.appendingPathComponent("op-base", isDirectory: true)
    try FileManager.default.createDirectory(
        at: operationBase, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
    )
    let definition = try fixture.definition()
    let before = fixture.diagnostic(version: "1.0.0")
    let after = fixture.diagnostic(version: "2.0.0")
    let updateRunner = OperationNpmRunner(fixture: fixture)
    guard case .ready(let preparation) = await NpmUpdateOperation.prepare(
        definition: definition, diagnostic: before, environment: fixture.environment,
        currentDirectory: fixture.root.path, runner: updateRunner,
        operationRootBaseURL: operationBase
    ) else {
        Issue.record("expected preparation")
        return
    }
    let scanState = OperationScanState(before: before, after: after)
    let outcome = await NpmUpdateOperation.execute(
        confirmed: preparation, environment: fixture.environment,
        scan: { _, _, _ in scanState.next() },
        reconcileAfterLaunch: { _ in (scanState.next(), fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: BreakingQueryBaseOperationRunner(),
        gate: OperationExecutionGate()
    )
    #expect(outcome.state == .uncertain)
    if case .unknown(let reason)? = outcome.reconciliation?.ownership {
        #expect(reason == .managerQueryFailed)
    } else {
        Issue.record("expected an ownership containment reason")
    }
    #expect(outcome.cleanupWarnings.contains { $0.contains("ownership query scratch") })
}
