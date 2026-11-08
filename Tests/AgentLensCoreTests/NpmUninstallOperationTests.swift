import Foundation
import Testing
@testable import AgentLensCore

private func uninstallFixtureRoot(_ label: String) throws -> URL {
    let environment = ProcessInfo.processInfo.environment
    guard let basePath = [environment["AGENT_LENS_TEST_SCRATCH"], environment["TMPDIR"]]
        .compactMap({ $0 })
        .first(where: { !$0.isEmpty })
    else {
        throw NSError(domain: "NpmUninstallOperationTests", code: 1)
    }
    let root = URL(fileURLWithPath: basePath, isDirectory: true)
        .appendingPathComponent("agentlens-m10d-uninstall-\(label)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root.resolvingSymlinksInPath()
}

private func writeUninstallExecutable(_ url: URL) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
}

private struct UninstallFixture {
    let root: URL
    let prefix: URL
    let globalRoot: URL
    let managerDirectory: URL
    let aliasDirectory: URL
    let alias: URL
    let target: URL
    let packageURL: URL
    let prefixBin: URL
    let package: String
    let executableName: String
    let environment: ShellEnvironment

    init(_ label: String, package: String = "codex-ai", executableName: String = "codex-ai") throws {
        self.package = package
        self.executableName = executableName
        root = try uninstallFixtureRoot(label)
        prefix = root.appendingPathComponent("prefix", isDirectory: true)
        globalRoot = prefix.appendingPathComponent("lib/node_modules", isDirectory: true)
        managerDirectory = root.appendingPathComponent("manager-bin", isDirectory: true)
        aliasDirectory = root.appendingPathComponent("alias-bin", isDirectory: true)
        prefixBin = prefix.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: managerDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: aliasDirectory, withIntermediateDirectories: true)
        try writeUninstallExecutable(managerDirectory.appendingPathComponent("npm"))

        var packageURL = globalRoot
        for component in package.split(separator: "/", omittingEmptySubsequences: false) {
            packageURL.appendPathComponent(String(component), isDirectory: true)
        }
        self.packageURL = packageURL
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        target = packageURL.appendingPathComponent("bin/codex.js")
        try writeUninstallExecutable(target)
        let manifest: [String: Any] = [
            "name": package,
            "version": "1.0.0",
            "bin": [executableName: "bin/codex.js"],
        ]
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
            .write(to: packageURL.appendingPathComponent("package.json"))
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

    func diagnostic(version: String?, target override: URL? = nil) -> ToolPathDiagnostic {
        let canonical = (override ?? alias).resolvingSymlinksInPath().standardizedFileURL.path
        let directory = alias.deletingLastPathComponent().path
        let candidate = PathCandidateObservation(
            origin: .path(slotIndex: 0, directoryText: directory),
            entryPath: alias.path,
            kind: .executableSymlink,
            canonicalTarget: canonical
        )
        let detected = DetectedTool(
            displayName: "Codex",
            executableName: executableName,
            state: .installedAndOnPath,
            entryPath: alias.path,
            resolvedPath: canonical,
            source: "npm",
            version: version
        )
        return ToolPathDiagnostic(
            detectedTool: detected,
            pathCandidates: [candidate],
            firstLiveCandidate: candidate,
            targetGroups: [
                PathTargetGroup(canonicalTarget: canonical, entryPaths: [alias.path], firstSlotIndex: 0)
            ],
            repeatedPathSlotCount: 0,
            sameTargetAliasCount: 0,
            selection: .winner(candidate),
            shadowedInstallationCount: 0,
            installationVersions: []
        )
    }

    func missingDiagnostic() -> ToolPathDiagnostic {
        let detected = DetectedTool(
            displayName: "Codex",
            executableName: executableName,
            state: .notInstalled,
            entryPath: nil,
            resolvedPath: nil,
            source: "–",
            version: nil
        )
        return ToolPathDiagnostic(
            detectedTool: detected,
            pathCandidates: [],
            firstLiveCandidate: nil,
            targetGroups: [],
            repeatedPathSlotCount: 0,
            sameTargetAliasCount: 0,
            selection: .notInstalled,
            shadowedInstallationCount: 0,
            installationVersions: []
        )
    }

    /// Simulates what npm does for a successful global removal: the package directory and the
    /// prefix bin link are gone. The external alias deliberately becomes dangling.
    func removeInstalledPackage() {
        try? FileManager.default.removeItem(at: prefixBin.appendingPathComponent(executableName))
        try? FileManager.default.removeItem(at: packageURL)
    }
}

private final class UninstallNpmRunner: UpdateCommandRunner, @unchecked Sendable {
    let prefix: String
    let root: String
    private let lock = NSLock()
    private var recorded: [[String]] = []

    init(fixture: UninstallFixture, prefixOverride: String? = nil, rootOverride: String? = nil) {
        self.prefix = prefixOverride ?? fixture.prefix.path
        self.root = rootOverride ?? fixture.globalRoot.path
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
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval
    ) async -> CommandOutcome {
        note(arguments)
        if arguments.contains("prefix") { return .success(Data((prefix + "\n").utf8)) }
        if arguments.contains("root") { return .success(Data((root + "\n").utf8)) }
        return .failure(.spawnFailure)
    }
}

private final class UninstallOperationRunner: OperationCommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [[String]] = []
    let stdout: Data
    let stderr: Data
    let exitStatus: Int32
    let processStarted: Bool
    let cancelled: Bool
    let timedOut: Bool
    let mutate: @Sendable () -> Void

    init(
        stdout: String = "removed\n",
        stderr: String = "",
        exitStatus: Int32 = 0,
        processStarted: Bool = true,
        cancelled: Bool = false,
        timedOut: Bool = false,
        mutate: @escaping @Sendable () -> Void = {}
    ) {
        self.stdout = Data(stdout.utf8)
        self.stderr = Data(stderr.utf8)
        self.exitStatus = exitStatus
        self.processStarted = processStarted
        self.cancelled = cancelled
        self.timedOut = timedOut
        self.mutate = mutate
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
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        currentDirectory: String,
        timeout: TimeInterval
    ) async -> OperationCommandResult {
        note(arguments)
        if processStarted { mutate() }
        return OperationCommandResult(
            stdout: stdout,
            stderr: stderr,
            stdoutTruncated: false,
            stderrTruncated: false,
            exitStatus: exitStatus,
            processStarted: processStarted,
            timedOut: timedOut,
            cancelled: cancelled,
            cleanupWarning: false
        )
    }
}

private final class UninstallScanState: @unchecked Sendable {
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

private func waitForUninstallFile(_ url: URL, timeout: TimeInterval = 5) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if FileManager.default.fileExists(atPath: url.path) { return true }
        Thread.sleep(forTimeInterval: 0.02)
    }
    return false
}

private func waitForUninstallProcessGone(_ pid: pid_t, timeout: TimeInterval = 5) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if kill(pid, 0) != 0 { return true }
        Thread.sleep(forTimeInterval: 0.02)
    }
    return kill(pid, 0) != 0
}

@Test func preparationBindsExactUninstallArgvAndRemovalReconcilesToSuccess() async throws {
    let fixture = try UninstallFixture("success")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition()
    let before = fixture.diagnostic(version: "1.0.0")
    let after = fixture.missingDiagnostic()
    let updateRunner = UninstallNpmRunner(fixture: fixture)
    let operationRunner = UninstallOperationRunner(mutate: fixture.removeInstalledPackage)
    let scanState = UninstallScanState(before: before, after: after)

    let prepared = await NpmUninstallOperation.prepare(
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
    #expect(preparation.preview.packageName == fixture.package)
    #expect(preparation.preview.arguments.contains("uninstall"))
    #expect(preparation.preview.arguments.contains(fixture.package))
    #expect(!preparation.preview.arguments.contains("@latest"))
    #expect(preparation.preview.arguments.contains("--global"))
    #expect(preparation.preview.arguments.contains("--prefix"))
    #expect(preparation.preview.arguments.contains(fixture.prefix.path))
    #expect(preparation.preview.arguments.contains("--registry=https://registry.npmjs.org/"))
    #expect(preparation.preview.arguments.contains("--no-save"))
    #expect(updateRunner.invocations.allSatisfy { $0.contains("prefix") || $0.contains("root") })

    let outcome = await NpmUninstallOperation.execute(
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
    #expect(outcome.reconciliation?.packageDirectoryAbsent == true)
    #expect(outcome.reconciliation?.selectedTargetReleased == true)
    #expect(outcome.reconciliation?.selectedEntryResidue == true)
    #expect(outcome.reconciliation?.observationFailed == false)
    #expect(outcome.reconciliation?.afterInstallState == .notInstalled)
    #expect(operationRunner.invocations.count == 1)
    let argv = try #require(operationRunner.invocations.first)
    #expect(argv.first == "--cache")
    #expect(argv.contains("uninstall"))
    #expect(argv.contains("--global"))
    #expect(argv.contains("--prefix"))
    #expect(argv.contains(fixture.prefix.path))
    #expect(!argv.contains("--force"))
    #expect(!argv.contains("--ignore-scripts"))
    #expect(!FileManager.default.fileExists(atPath: preparation.preview.workingDirectory))
}

@Test func exitZeroWithoutRemovalIsUncertainAndNeverClaimsSuccess() async throws {
    let fixture = try UninstallFixture("still-present")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition()
    let before = fixture.diagnostic(version: "1.0.0")
    let updateRunner = UninstallNpmRunner(fixture: fixture)
    let operationRunner = UninstallOperationRunner()
    guard case .ready(let preparation) = await NpmUninstallOperation.prepare(
        definition: definition,
        diagnostic: before,
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: updateRunner,
        operationRootBaseURL: fixture.root
    ) else {
        Issue.record("expected preparation")
        return
    }
    let outcome = await NpmUninstallOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (before, fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: operationRunner,
        gate: OperationExecutionGate()
    )
    #expect(outcome.state == .uncertain)
    #expect(outcome.reconciliation?.packageDirectoryAbsent == false)
    #expect(outcome.reconciliation?.selectedTargetReleased == false)
    #expect(outcome.processStarted)
}

@Test func nonzeroExitRetainsBothStreamsAndMeasuredDelta() async throws {
    let fixture = try UninstallFixture("nonzero")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition()
    let before = fixture.diagnostic(version: "1.0.0")
    let after = fixture.missingDiagnostic()
    let updateRunner = UninstallNpmRunner(fixture: fixture)
    let operationRunner = UninstallOperationRunner(
        stdout: "out\n", stderr: "failure\n", exitStatus: 42,
        mutate: fixture.removeInstalledPackage
    )
    let scanState = UninstallScanState(before: before, after: after)
    guard case .ready(let preparation) = await NpmUninstallOperation.prepare(
        definition: definition,
        diagnostic: before,
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: updateRunner,
        operationRootBaseURL: fixture.root
    ) else {
        Issue.record("expected preparation")
        return
    }
    let outcome = await NpmUninstallOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in scanState.next() },
        reconcileAfterLaunch: { _ in (scanState.next(), fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: operationRunner,
        gate: OperationExecutionGate()
    )
    #expect(outcome.state == .failed)
    #expect(outcome.exitStatus == 42)
    #expect(outcome.stdoutText == "out\n")
    #expect(outcome.stderrText == "failure\n")
    #expect(outcome.reconciliation?.packageDirectoryAbsent == true)
}

@Test func missingLocalVersionStillPreparesAndRemoves() async throws {
    let fixture = try UninstallFixture("missing-version")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition()
    let before = fixture.diagnostic(version: nil)
    let after = fixture.missingDiagnostic()
    let updateRunner = UninstallNpmRunner(fixture: fixture)
    let operationRunner = UninstallOperationRunner(mutate: fixture.removeInstalledPackage)
    let scanState = UninstallScanState(before: before, after: after)
    guard case .ready(let preparation) = await NpmUninstallOperation.prepare(
        definition: definition,
        diagnostic: before,
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: updateRunner,
        operationRootBaseURL: fixture.root
    ) else {
        Issue.record("expected a preparation without a local version")
        return
    }
    #expect(preparation.preview.installedVersion == nil)
    let outcome = await NpmUninstallOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in scanState.next() },
        reconcileAfterLaunch: { _ in (scanState.next(), fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: operationRunner,
        gate: OperationExecutionGate()
    )
    #expect(outcome.state == .succeeded)
}

@Test func cancelReleasesOwnedRootWithZeroMutation() async throws {
    let fixture = try UninstallFixture("cancel")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition()
    let before = fixture.diagnostic(version: "1.0.0")
    let updateRunner = UninstallNpmRunner(fixture: fixture)
    guard case .ready(let preparation) = await NpmUninstallOperation.prepare(
        definition: definition,
        diagnostic: before,
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: updateRunner,
        operationRootBaseURL: fixture.root
    ) else {
        Issue.record("expected preparation")
        return
    }
    let root = preparation.preview.workingDirectory
    #expect(FileManager.default.fileExists(atPath: root))
    #expect(NpmUninstallOperation.cancel(preparation))
    #expect(!FileManager.default.fileExists(atPath: root))
}

@Test func replayedPreparationCannotLaunchASecondRemoval() async throws {
    let fixture = try UninstallFixture("replay")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition()
    let before = fixture.diagnostic(version: "1.0.0")
    let after = fixture.missingDiagnostic()
    let updateRunner = UninstallNpmRunner(fixture: fixture)
    let operationRunner = UninstallOperationRunner(mutate: fixture.removeInstalledPackage)
    let scanState = UninstallScanState(before: before, after: after)
    guard case .ready(let preparation) = await NpmUninstallOperation.prepare(
        definition: definition,
        diagnostic: before,
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: updateRunner,
        operationRootBaseURL: fixture.root
    ) else {
        Issue.record("expected preparation")
        return
    }
    let gate = OperationExecutionGate()
    _ = await NpmUninstallOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in scanState.next() },
        reconcileAfterLaunch: { _ in (scanState.next(), fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: operationRunner,
        gate: gate
    )
    let replay = await NpmUninstallOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in scanState.next() },
        reconcileAfterLaunch: { _ in (scanState.next(), fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: operationRunner,
        gate: gate
    )
    #expect(replay.state == .failed)
    #expect(!replay.processStarted)
    #expect(operationRunner.invocations.count == 1)
}

@Test func busyGateRefusesWithoutLaunch() async throws {
    let fixture = try UninstallFixture("gate")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition()
    let before = fixture.diagnostic(version: "1.0.0")
    let updateRunner = UninstallNpmRunner(fixture: fixture)
    let operationRunner = UninstallOperationRunner()
    guard case .ready(let preparation) = await NpmUninstallOperation.prepare(
        definition: definition,
        diagnostic: before,
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: updateRunner,
        operationRootBaseURL: fixture.root
    ) else {
        Issue.record("expected preparation")
        return
    }
    let gate = OperationExecutionGate()
    #expect(await gate.acquire())
    let outcome = await NpmUninstallOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (before, fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: operationRunner,
        gate: gate
    )
    #expect(outcome.state == .cancelled)
    #expect(!outcome.processStarted)
    #expect(operationRunner.invocations.isEmpty)
    await gate.release()
}

@Test func staleSelectionRefusesBeforeLaunch() async throws {
    let fixture = try UninstallFixture("stale-selection")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition()
    let before = fixture.diagnostic(version: "1.0.0")
    let updateRunner = UninstallNpmRunner(fixture: fixture)
    let operationRunner = UninstallOperationRunner(mutate: fixture.removeInstalledPackage)
    guard case .ready(let preparation) = await NpmUninstallOperation.prepare(
        definition: definition,
        diagnostic: before,
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: updateRunner,
        operationRootBaseURL: fixture.root
    ) else {
        Issue.record("expected preparation")
        return
    }
    let outcome = await NpmUninstallOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in fixture.missingDiagnostic() },
        reconcileAfterLaunch: { _ in nil },
        updateRunner: updateRunner,
        operationRunner: operationRunner,
        gate: OperationExecutionGate()
    )
    #expect(outcome.state == .failed)
    #expect(!outcome.processStarted)
    #expect(operationRunner.invocations.isEmpty)
}

@Test func staleProofRefusesBeforeLaunch() async throws {
    let fixture = try UninstallFixture("stale-proof")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition()
    let before = fixture.diagnostic(version: "1.0.0")
    let updateRunner = UninstallNpmRunner(fixture: fixture)
    let operationRunner = UninstallOperationRunner(mutate: fixture.removeInstalledPackage)
    guard case .ready(let preparation) = await NpmUninstallOperation.prepare(
        definition: definition,
        diagnostic: before,
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: updateRunner,
        operationRootBaseURL: fixture.root
    ) else {
        Issue.record("expected preparation")
        return
    }
    try FileManager.default.removeItem(at: fixture.packageURL.appendingPathComponent("package.json"))
    let outcome = await NpmUninstallOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in nil },
        updateRunner: updateRunner,
        operationRunner: operationRunner,
        gate: OperationExecutionGate()
    )
    #expect(outcome.state == .failed)
    #expect(!outcome.processStarted)
    #expect(operationRunner.invocations.isEmpty)
}

@Test func scopedPackagePinsScopeRegistry() async throws {
    let fixture = try UninstallFixture("scoped", package: "@openai/codex")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition()
    let before = fixture.diagnostic(version: "1.0.0")
    let updateRunner = UninstallNpmRunner(fixture: fixture)
    guard case .ready(let preparation) = await NpmUninstallOperation.prepare(
        definition: definition,
        diagnostic: before,
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: updateRunner,
        operationRootBaseURL: fixture.root
    ) else {
        Issue.record("expected preparation")
        return
    }
    #expect(preparation.preview.packageName == "@openai/codex")
    #expect(preparation.preview.arguments.contains("--@openai:registry=https://registry.npmjs.org/"))
    _ = NpmUninstallOperation.cancel(preparation)
}

@Test func noMetadataOrRegistryQueriesAreSent() async throws {
    let fixture = try UninstallFixture("no-metadata")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition()
    let before = fixture.diagnostic(version: "1.0.0")
    let updateRunner = UninstallNpmRunner(fixture: fixture)
    guard case .ready(let preparation) = await NpmUninstallOperation.prepare(
        definition: definition,
        diagnostic: before,
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: updateRunner,
        operationRootBaseURL: fixture.root
    ) else {
        Issue.record("expected preparation")
        return
    }
    #expect(!updateRunner.invocations.contains { $0.contains("view") })
    #expect(!updateRunner.invocations.contains { $0.contains("config") })
    _ = NpmUninstallOperation.cancel(preparation)
}

@Test func cleanupRefusalKeepsProvenRemovalAndAddsWarning() async throws {
    let fixture = try UninstallFixture("cleanup-warning")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition()
    let before = fixture.diagnostic(version: "1.0.0")
    let after = fixture.missingDiagnostic()
    let updateRunner = UninstallNpmRunner(fixture: fixture)
    let scanState = UninstallScanState(before: before, after: after)
    guard case .ready(let preparation) = await NpmUninstallOperation.prepare(
        definition: definition,
        diagnostic: before,
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: updateRunner,
        operationRootBaseURL: fixture.root
    ) else {
        Issue.record("expected preparation")
        return
    }
    let operationRoot = preparation.preview.workingDirectory
    let breaker = UninstallOperationRunner(mutate: {
        fixture.removeInstalledPackage()
        try? FileManager.default.removeItem(atPath: operationRoot)
        try? FileManager.default.createDirectory(
            atPath: operationRoot, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
    })
    let outcome = await NpmUninstallOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in scanState.next() },
        reconcileAfterLaunch: { _ in (scanState.next(), fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: breaker,
        gate: OperationExecutionGate()
    )
    #expect(outcome.state == .succeeded)
    #expect(outcome.cleanupWarnings.contains { $0.contains("scratch root") })
}

private final class CleanupRefusingUninstallRunner: OperationCommandRunner, @unchecked Sendable {
    let fixture: UninstallFixture
    init(fixture: UninstallFixture) { self.fixture = fixture }
    func run(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        currentDirectory: String,
        timeout: TimeInterval
    ) async -> OperationCommandResult {
        fixture.removeInstalledPackage()
        try? FileManager.default.removeItem(atPath: currentDirectory)
        try? FileManager.default.createDirectory(
            atPath: currentDirectory, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        return OperationCommandResult(
            stdout: Data("removed\n".utf8), stderr: Data(),
            stdoutTruncated: false, stderrTruncated: false,
            exitStatus: 0, processStarted: true,
            timedOut: false, cancelled: false, cleanupWarning: false
        )
    }
}

@Test func cleanupBreakingRunnerRetainsSuccessAndWarning() async throws {
    let fixture = try UninstallFixture("cleanup-break")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition()
    let before = fixture.diagnostic(version: "1.0.0")
    let after = fixture.missingDiagnostic()
    let updateRunner = UninstallNpmRunner(fixture: fixture)
    let scanState = UninstallScanState(before: before, after: after)
    guard case .ready(let preparation) = await NpmUninstallOperation.prepare(
        definition: definition,
        diagnostic: before,
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: updateRunner,
        operationRootBaseURL: fixture.root
    ) else {
        Issue.record("expected preparation")
        return
    }
    let outcome = await NpmUninstallOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in scanState.next() },
        reconcileAfterLaunch: { _ in (scanState.next(), fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: CleanupRefusingUninstallRunner(fixture: fixture),
        gate: OperationExecutionGate()
    )
    #expect(outcome.state == .succeeded)
    #expect(outcome.cleanupWarnings.contains { $0.contains("scratch root") })
}

@Test func cancellingAfterSpawnInterruptsAndReconcilesWithoutOrphan() async throws {
    let fixture = try UninstallFixture("cancel-after-spawn")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let pidFile = fixture.root.appendingPathComponent("delayed-uninstall-pid")
    let manager = fixture.managerDirectory.appendingPathComponent("npm")
    let script = """
    #!/bin/sh
    for arg in "$@"; do
      if [ "$arg" = "uninstall" ]; then
        printf '%s' "$$" > '\(pidFile.path)'
        trap '' TERM
        sleep 30
        exit 0
      fi
    done
    exit 64
    """
    try Data(script.utf8).write(to: manager)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: manager.path)
    let definition = try fixture.definition()
    let before = fixture.diagnostic(version: "1.0.0")
    let after = fixture.missingDiagnostic()
    let updateRunner = UninstallNpmRunner(fixture: fixture)
    guard case .ready(let preparation) = await NpmUninstallOperation.prepare(
        definition: definition,
        diagnostic: before,
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: updateRunner,
        operationRootBaseURL: fixture.root
    ) else {
        Issue.record("expected preparation")
        return
    }
    let task = Task {
        await NpmUninstallOperation.execute(
            confirmed: preparation,
            environment: fixture.environment,
            scan: { _, _, _ in before },
            reconcileAfterLaunch: { _ in (after, fixture.environment) },
            updateRunner: updateRunner,
            operationRunner: ProcessOperationCommandRunner(),
            gate: OperationExecutionGate()
        )
    }
    #expect(waitForUninstallFile(pidFile))
    let pid = try #require(pid_t(try String(contentsOf: pidFile, encoding: .utf8)))
    task.cancel()
    let outcome = await task.value
    #expect(outcome.state == .interrupted)
    #expect(outcome.processStarted)
    #expect(outcome.reconciliation != nil)
    #expect(outcome.reconciliation?.packageDirectoryAbsent == false)
    #expect(waitForUninstallProcessGone(pid), "the delayed uninstall process must be reaped")
    #expect(!FileManager.default.fileExists(atPath: preparation.preview.workingDirectory))
}

@Test func replacedPackageDirectoryIsNotCleanRemoval() async throws {
    let fixture = try UninstallFixture("replaced-package")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition()
    let before = fixture.diagnostic(version: "1.0.0")
    let updateRunner = UninstallNpmRunner(fixture: fixture)
    let operationRunner = UninstallOperationRunner(mutate: {
        try? FileManager.default.removeItem(at: fixture.packageURL)
        try? FileManager.default.createDirectory(
            at: fixture.packageURL, withIntermediateDirectories: true
        )
        try? Data("replacement\n".utf8).write(
            to: fixture.packageURL.appendingPathComponent("replacement.txt")
        )
    })
    guard case .ready(let preparation) = await NpmUninstallOperation.prepare(
        definition: definition,
        diagnostic: before,
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: updateRunner,
        operationRootBaseURL: fixture.root
    ) else {
        Issue.record("expected preparation")
        return
    }
    let outcome = await NpmUninstallOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (fixture.missingDiagnostic(), fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: operationRunner,
        gate: OperationExecutionGate()
    )
    #expect(outcome.state == .uncertain)
    #expect(outcome.reconciliation?.packageDirectoryAbsent == false)
    #expect(outcome.reconciliation?.packageDirectoryReplaced == true)
    #expect(outcome.reconciliation?.observationFailed == false)
}

@Test func symlinkedInRootStoreRemovalBindsRecordedIdentity() async throws {
    let fixture = try UninstallFixture("symlink-store")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let store = fixture.globalRoot
        .appendingPathComponent(".store/codex-1.0.0", isDirectory: true)
    try FileManager.default.createDirectory(
        at: store.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try FileManager.default.moveItem(at: fixture.packageURL, to: store)
    try FileManager.default.createSymbolicLink(
        atPath: fixture.packageURL.path, withDestinationPath: store.path
    )
    let definition = try fixture.definition()
    let before = fixture.diagnostic(version: "1.0.0")
    let updateRunner = UninstallNpmRunner(fixture: fixture)
    let operationRunner = UninstallOperationRunner(mutate: {
        try? FileManager.default.removeItem(at: fixture.packageURL)
        try? FileManager.default.removeItem(at: store)
        try? FileManager.default.removeItem(
            at: fixture.prefixBin.appendingPathComponent(fixture.executableName)
        )
    })
    guard case .ready(let preparation) = await NpmUninstallOperation.prepare(
        definition: definition,
        diagnostic: before,
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: updateRunner,
        operationRootBaseURL: fixture.root
    ) else {
        Issue.record("expected preparation for the in-root store")
        return
    }
    let outcome = await NpmUninstallOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (fixture.missingDiagnostic(), fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: operationRunner,
        gate: OperationExecutionGate()
    )
    #expect(outcome.state == .succeeded)
    #expect(outcome.reconciliation?.packageDirectoryAbsent == true)
    #expect(outcome.reconciliation?.packageDirectoryReplaced == false)
    #expect(outcome.reconciliation?.selectedTargetReleased == true)
}

@Test func sharedBinRetargetIsReportedAsUnknownOwnership() async throws {
    let fixture = try UninstallFixture("shared-bin")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition()
    let before = fixture.diagnostic(version: "1.0.0")
    let otherPackage = fixture.globalRoot.appendingPathComponent("shared-owner", isDirectory: true)
    let otherTarget = otherPackage.appendingPathComponent("bin/codex")
    let updateRunner = UninstallNpmRunner(fixture: fixture)
    let operationRunner = UninstallOperationRunner(mutate: {
        fixture.removeInstalledPackage()
        try? FileManager.default.createDirectory(
            at: otherPackage, withIntermediateDirectories: true
        )
        try? Data("#!/bin/sh\necho 'shared 9.9.9'\n".utf8).write(to: otherTarget)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: otherTarget.path)
        try? FileManager.default.removeItem(at: fixture.alias)
        try? FileManager.default.createSymbolicLink(
            atPath: fixture.alias.path, withDestinationPath: otherTarget.path
        )
    })
    guard case .ready(let preparation) = await NpmUninstallOperation.prepare(
        definition: definition,
        diagnostic: before,
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: updateRunner,
        operationRootBaseURL: fixture.root
    ) else {
        Issue.record("expected preparation")
        return
    }
    let after = fixture.diagnostic(version: "9.9.9", target: otherTarget)
    let outcome = await NpmUninstallOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (after, fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: operationRunner,
        gate: OperationExecutionGate()
    )
    #expect(outcome.state == .succeeded)
    #expect(outcome.reconciliation?.packageDirectoryAbsent == true)
    #expect(outcome.reconciliation?.selectedTargetReleased == true)
    if case .unknown? = outcome.reconciliation?.ownership {
        // The remaining bin is not the reviewed package; its ownership is neutral, not borrowed.
    } else {
        Issue.record("a shared-bin retarget must not be reported as verified ownership")
    }
}

@Test func unreadableRemovalObservationIsUncertainNotSuccess() async throws {
    let fixture = try UninstallFixture("observation-failed")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition()
    let before = fixture.diagnostic(version: "1.0.0")
    let updateRunner = UninstallNpmRunner(fixture: fixture)
    let operationRunner = UninstallOperationRunner(
        exitStatus: 0,
        mutate: {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o000], ofItemAtPath: fixture.prefix.path
            )
        }
    )
    guard case .ready(let preparation) = await NpmUninstallOperation.prepare(
        definition: definition,
        diagnostic: before,
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: updateRunner,
        operationRootBaseURL: fixture.root
    ) else {
        Issue.record("expected preparation")
        return
    }
    let outcome = await NpmUninstallOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (fixture.missingDiagnostic(), fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: operationRunner,
        gate: OperationExecutionGate()
    )
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755], ofItemAtPath: fixture.prefix.path
    )
    #expect(outcome.state == .uncertain)
    #expect(outcome.reconciliation?.observationFailed == true)
    #expect(outcome.reconciliation?.packageDirectoryAbsent == false)
    #expect(outcome.reconciliation?.selectedTargetReleased == false)
}

@Test func uninstallDefaultPreparationRootUsesCapturedTemporaryDirectory() async throws {
    let fixture = try UninstallFixture("captured-tmp")
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
    guard case .ready(let preparation) = await NpmUninstallOperation.prepare(
        definition: definition,
        diagnostic: before,
        environment: capturedEnvironment,
        currentDirectory: fixture.root.path,
        runner: UninstallNpmRunner(fixture: fixture),
        operationRootBaseURL: nil
    ) else {
        Issue.record("expected a preparation from the captured TMPDIR")
        return
    }
    #expect(preparation.preview.workingDirectory.hasPrefix(ownedPhysical + "/"))
    _ = NpmUninstallOperation.cancel(preparation)
}

@Test func uninstallUnsafeCapturedTemporaryDirectoryRefusesWithZeroMutation() async throws {
    let fixture = try UninstallFixture("captured-tmp-unsafe")
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
    let updateRunner = UninstallNpmRunner(fixture: fixture)
    let result = await NpmUninstallOperation.prepare(
        definition: definition,
        diagnostic: before,
        environment: capturedEnvironment,
        currentDirectory: fixture.root.path,
        runner: updateRunner,
        operationRootBaseURL: nil
    )
    guard case .unavailable(.operationRootUnsafe) = result else {
        Issue.record("an unsafe captured TMPDIR must fail closed")
        return
    }
    #expect(updateRunner.invocations.isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: unsafeTmp.path).isEmpty)
}
