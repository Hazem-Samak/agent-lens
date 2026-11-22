// HomebrewCaskOwnershipProbeTests — M13-A read-only cask ownership proof.
//
// Every fixture is synthetic and test-owned: a scratch prefix, a manager executable, staged cask
// files, declarative records and scripted runner answers. No real brew or cask is invoked. The
// tests assert the typed proof and the neutral refusal reason, plus the exact ordered argv and
// the suppression of later queries after an identity change.

import Foundation
import Testing
@testable import AgentLensCore

// MARK: Shared scratch and fixture helpers

private func caskScratchRoot(_ label: String) throws -> URL {
    let environment = ProcessInfo.processInfo.environment
    guard let basePath = [environment["AGENT_LENS_TEST_SCRATCH"], environment["TMPDIR"]]
        .compactMap({ $0 })
        .first(where: { !$0.isEmpty })
    else {
        throw NSError(
            domain: "AgentLensCaskOwnershipTests", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "no approved test scratch root is available"]
        )
    }
    let base = URL(fileURLWithPath: basePath, isDirectory: true).resolvingSymlinksInPath()
    let root = base.appendingPathComponent(
        "agentlens-m13a-\(label)-\(UUID().uuidString)", isDirectory: true
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root.resolvingSymlinksInPath()
}

private func writeCaskExecutable(_ url: URL, version: String = "1.0.0") throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    let script = """
    #!/bin/sh
    if [ "$1" = "--version" ]; then printf '%s\\n' '\(version)'; fi
    exit 0
    """
    try Data(script.utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
}

private func appendRelative(_ url: URL, _ relative: String) -> URL {
    var result = url
    for component in relative.split(separator: "/") {
        result.appendPathComponent(String(component))
    }
    return result
}

private func caskEnvironment(pathEntries: [String]) -> ShellEnvironment {
    let joined = pathEntries.joined(separator: ":")
    return ShellEnvironment(
        shellPath: "/bin/zsh",
        pathEntries: pathEntries,
        pathJoined: joined,
        raw: ["PATH": joined, "HOME": "/synthetic/home"],
        isDegraded: false
    )
}

private func caskDefinition(
    executableName: String = "codex",
    packages: [(PackageManager, String)]
) throws -> DetectorDefinition {
    let declared = try packages.map { try DeclaredPackage(manager: $0.0, name: $0.1) }
    return try DetectorDefinition(
        id: "codex-id",
        displayName: "Codex",
        executableName: executableName,
        extraSearchRoots: [],
        fixture: nil,
        category: .aiAgent,
        packages: declared,
        informationURL: nil,
        uninstallInstructionsURL: nil,
        versionQuery: .standard
    )
}

private func caskDiagnostic(
    executableName: String,
    entryPath: String,
    source: String,
    state: InstallState = .installedAndOnPath,
    offPathRoot: String? = nil
) -> ToolPathDiagnostic {
    let target = URL(fileURLWithPath: entryPath)
        .resolvingSymlinksInPath().standardizedFileURL.path
    let directory = URL(fileURLWithPath: entryPath).deletingLastPathComponent().path
    let candidate = PathCandidateObservation(
        origin: .path(slotIndex: 0, directoryText: directory),
        entryPath: entryPath,
        kind: .executableSymlink,
        canonicalTarget: target
    )
    let detected = DetectedTool(
        displayName: "Codex",
        executableName: executableName,
        state: state,
        entryPath: entryPath,
        resolvedPath: target,
        source: source,
        version: nil
    )
    return ToolPathDiagnostic(
        detectedTool: detected,
        pathCandidates: [candidate],
        firstLiveCandidate: candidate,
        targetGroups: [
            PathTargetGroup(
                canonicalTarget: target, entryPaths: [entryPath], firstSlotIndex: 0
            )
        ],
        repeatedPathSlotCount: 0,
        sameTargetAliasCount: 0,
        selection: offPathRoot.map { .offPath(candidate: candidate, root: $0) }
            ?? .winner(candidate),
        shadowedInstallationCount: 0,
        installationVersions: []
    )
}

private func fixedCaskClock(
    _ value: Date = Date(timeIntervalSince1970: 1_800_000_500)
) -> @Sendable () -> Date {
    { value }
}

// MARK: Synthetic cask fixture

/// A synthetic Homebrew prefix plus Caskroom. `brew` lives in `<prefix>/bin`; the Caskroom may be
/// outside the prefix so tests cannot accidentally derive one root from the other.
private struct CaskFixture {
    let root: URL
    let prefix: URL
    let caskroom: URL
    let token: String
    let fullToken: String
    let version: String
    let artifactRelative: String

    var tokenDirectory: URL { caskroom.appendingPathComponent(token, isDirectory: true) }
    var versionDirectory: URL { tokenDirectory.appendingPathComponent(version, isDirectory: true) }
    var stagedArtifact: URL { appendRelative(versionDirectory, artifactRelative) }
    var prefixText: String { prefix.path }
    var caskroomText: String { caskroom.path }
    var brewPath: String { prefix.appendingPathComponent("bin/brew").path }
    var binDirectory: String { prefix.appendingPathComponent("bin").path }

    init(
        _ label: String,
        token: String = "codex",
        fullToken: String? = nil,
        version: String = "1.0.0",
        artifactRelative: String = "bin/codex",
        caskroomOutsidePrefix: Bool = false
    ) throws {
        root = try caskScratchRoot(label)
        prefix = root.appendingPathComponent("prefix", isDirectory: true)
        caskroom = caskroomOutsidePrefix
            ? root.appendingPathComponent("Caskroom", isDirectory: true)
            : prefix.appendingPathComponent("Caskroom", isDirectory: true)
        self.token = token
        self.fullToken = fullToken ?? token
        self.version = version
        self.artifactRelative = artifactRelative
        try writeCaskExecutable(prefix.appendingPathComponent("bin/brew"))
        try FileManager.default.createDirectory(
            at: versionDirectory, withIntermediateDirectories: true
        )
    }

    /// Stages the artifact as a regular executable and links `<prefix>/bin/<entryName>` to it.
    @discardableResult
    func installBinaryArtifact(entryName: String = "codex") throws -> (entry: String, target: String) {
        try writeCaskExecutable(stagedArtifact)
        let link = prefix.appendingPathComponent("bin/\(entryName)")
        try? FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(
            atPath: link.path, withDestinationPath: stagedArtifact.path
        )
        return (
            link.path,
            stagedArtifact.resolvingSymlinksInPath().standardizedFileURL.path
        )
    }

    /// Stages a moved-app symlink under the version directory and selects an executable inside the
    /// app that lives outside the Caskroom, as a `Moved` cask artifact does.
    @discardableResult
    func installMovedApp(appName: String = "Codex.app") throws -> (entry: String, appPath: String) {
        let appDirectory = root.appendingPathComponent(
            "Applications/\(appName)", isDirectory: true
        )
        let executable = appDirectory.appendingPathComponent("Contents/MacOS/codex")
        try writeCaskExecutable(executable)
        let stagedLink = versionDirectory.appendingPathComponent(appName)
        try? FileManager.default.removeItem(at: stagedLink)
        try FileManager.default.createSymbolicLink(
            atPath: stagedLink.path, withDestinationPath: appDirectory.path
        )
        let selectionDirectory = root.appendingPathComponent("selection", isDirectory: true)
        try FileManager.default.createDirectory(
            at: selectionDirectory, withIntermediateDirectories: true
        )
        let entry = selectionDirectory.appendingPathComponent("codex")
        try? FileManager.default.removeItem(at: entry)
        try FileManager.default.createSymbolicLink(
            atPath: entry.path, withDestinationPath: executable.path
        )
        return (
            entry.path,
            executable.resolvingSymlinksInPath().standardizedFileURL.path
        )
    }
}

// MARK: Scripted cask manager

private func caskRecordJSON(
    token: String,
    fullToken: String,
    installed: String?,
    oldTokens: [String] = [],
    extraFields: String = ""
) -> String {
    let installedField = installed.map { "\"installed\":\"\($0)\"" } ?? "\"installed\":null"
    let old = oldTokens.map { "\"\($0)\"" }.joined(separator: ",")
    return """
    {"token":"\(token)","full_token":"\(fullToken)",\(installedField),\
    "old_tokens":[\(old)]\(extraFields)}
    """
}

private func caskInfoJSON(records: [String]) -> Data {
    Data("{\"formulae\":[],\"casks\":[\(records.joined(separator: ","))]}".utf8)
}

private func caskBrewScript(
    prefix: String,
    caskroom: String,
    info: Data,
    list: Data,
    listToken: String,
    declared: [String],
    hook: @escaping @Sendable ([String]) -> Void = { _ in }
) -> @Sendable (String, [String]) -> CommandOutcome {
    { _, arguments in
        hook(arguments)
        switch arguments {
        case ["--prefix"]:
            return .success(Data((prefix + "\n").utf8))
        case ["--caskroom"]:
            return .success(Data((caskroom + "\n").utf8))
        default:
            if arguments == ["info", "--json=v2", "--cask"] + declared {
                return .success(info)
            }
            if arguments == ["list", "--verbose", "--cask", listToken] {
                return .success(list)
            }
            Issue.record("unexpected brew arguments: \(arguments)")
            return .failure(.spawnFailure)
        }
    }
}

private func runCaskVerification(
    definition: DetectorDefinition,
    diagnostic: ToolPathDiagnostic,
    environment: ShellEnvironment,
    runner: ScriptedRunner,
    currentDirectory: String
) async -> InstallationOwnershipResult {
    await InstallationOwnershipVerifier.verify(
        definition: definition,
        diagnostic: diagnostic,
        environment: environment,
        runner: runner,
        currentDirectory: currentDirectory,
        now: fixedCaskClock()
    )
}

private func caskCurrentDirectory(_ fixture: CaskFixture) -> String {
    fixture.root.path
}

private func relativeToListedRoot(_ path: String, root: String, listedRoot: String) -> String {
    guard path == root || path.hasPrefix(root + "/") else { return path }
    return listedRoot + String(path.dropFirst(root.count))
}

private func installMovedAppLink(
    fixture: CaskFixture,
    linkName: String,
    appName: String
) throws -> (entry: String, app: URL, executable: URL) {
    let app = fixture.root.appendingPathComponent("Applications/\(appName)", isDirectory: true)
    let executable = app.appendingPathComponent("Contents/MacOS/codex")
    try writeCaskExecutable(executable)
    let link = fixture.versionDirectory.appendingPathComponent(linkName)
    try? FileManager.default.removeItem(at: link)
    try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: app.path)
    let selectionDirectory = fixture.root.appendingPathComponent("selection", isDirectory: true)
    try FileManager.default.createDirectory(
        at: selectionDirectory, withIntermediateDirectories: true
    )
    let entry = selectionDirectory.appendingPathComponent("codex")
    try? FileManager.default.removeItem(at: entry)
    try FileManager.default.createSymbolicLink(
        atPath: entry.path, withDestinationPath: executable.path
    )
    return (entry.path, app, executable)
}

// MARK: Positive proof

@Test func caskBinaryProofUsesPrefixCaskroomInfoAndList() async throws {
    let fixture = try CaskFixture("binary")
    let installed = try fixture.installBinaryArtifact()
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
    let info = caskInfoJSON(records: [
        caskRecordJSON(token: "codex", fullToken: "codex", installed: fixture.version)
    ])
    let list = Data((fixture.stagedArtifact.path + "\n").utf8)
    let runner = ScriptedRunner(handler: caskBrewScript(
        prefix: fixture.prefixText,
        caskroom: fixture.caskroomText,
        info: info,
        list: list,
        listToken: "codex",
        declared: ["codex"]
    ))

    let result = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: installed.entry, source: "standalone"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: runner,
        currentDirectory: caskCurrentDirectory(fixture)
    )

    let installation = try #require(result.verifiedInstallation)
    #expect(result.unknownReason == nil)
    #expect(installation.manager == .homebrewCask)
    #expect(installation.packageName == "codex")
    #expect(installation.managerEntryPath == fixture.brewPath)
    #expect(installation.managerRoot == fixture.prefix.path)
    #expect(installation.installationRoot == fixture.tokenDirectory.path)
    #expect(installation.selection.entryPath == installed.entry)
    #expect(installation.selection.canonicalTarget == installed.target)
    #expect(runner.calls == [
        ["--prefix"],
        ["--caskroom"],
        ["info", "--json=v2", "--cask", "codex"],
        ["list", "--verbose", "--cask", "codex"],
    ])
    #expect(runner.calls.allSatisfy { !$0.contains("--cellar") })
    #expect(runner.environments.first?["HOMEBREW_NO_AUTO_UPDATE"] == "1")
    #expect(runner.environments.first?["HOMEBREW_NO_ANALYTICS"] == "1")
}

@Test func caskOffPathSelectionUsesTheSameBoundedProof() async throws {
    let fixture = try CaskFixture("off-path")
    let installed = try fixture.installBinaryArtifact()
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
    let info = caskInfoJSON(records: [
        caskRecordJSON(token: "codex", fullToken: "codex", installed: fixture.version)
    ])
    let runner = ScriptedRunner(handler: caskBrewScript(
        prefix: fixture.prefixText,
        caskroom: fixture.caskroomText,
        info: info,
        list: Data((fixture.stagedArtifact.path + "\n").utf8),
        listToken: "codex",
        declared: ["codex"]
    ))

    let result = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex",
            entryPath: installed.entry,
            source: "standalone",
            offPathRoot: "/synthetic/extra-root"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: runner,
        currentDirectory: caskCurrentDirectory(fixture)
    )

    let installation = try #require(result.verifiedInstallation)
    #expect(installation.selection.entryPath == installed.entry)
    #expect(runner.calls.count == 4)
}

@Test func caskCommandWrapperProofUsesStagedWrapper() async throws {
    let fixture = try CaskFixture(
        "command-wrapper", artifactRelative: ".homebrew-command-wrappers/codex"
    )
    let installed = try fixture.installBinaryArtifact()
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
    let info = caskInfoJSON(records: [
        caskRecordJSON(token: "codex", fullToken: "codex", installed: fixture.version)
    ])
    let runner = ScriptedRunner(handler: caskBrewScript(
        prefix: fixture.prefixText,
        caskroom: fixture.caskroomText,
        info: info,
        list: Data((fixture.stagedArtifact.path + "\n").utf8),
        listToken: "codex",
        declared: ["codex"]
    ))

    let result = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: installed.entry, source: "standalone"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: runner,
        currentDirectory: caskCurrentDirectory(fixture)
    )

    let installation = try #require(result.verifiedInstallation)
    #expect(installation.packageName == "codex")
    #expect(installation.installationRoot == fixture.tokenDirectory.path)
    #expect(runner.calls.count == 4)
}

@Test func caskMovedAppSymlinkProofUsesListedStagedLink() async throws {
    let fixture = try CaskFixture("moved-app", artifactRelative: "Codex.app")
    let moved = try fixture.installMovedApp()
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
    let info = caskInfoJSON(records: [
        caskRecordJSON(token: "codex", fullToken: "codex", installed: fixture.version)
    ])
    let runner = ScriptedRunner(handler: caskBrewScript(
        prefix: fixture.prefixText,
        caskroom: fixture.caskroomText,
        info: info,
        list: Data((fixture.stagedArtifact.path + "\n").utf8),
        listToken: "codex",
        declared: ["codex"]
    ))

    let result = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: moved.entry, source: "standalone"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: runner,
        currentDirectory: caskCurrentDirectory(fixture)
    )

    let installation = try #require(result.verifiedInstallation)
    #expect(installation.manager == .homebrewCask)
    #expect(installation.selection.canonicalTarget == moved.appPath)
    #expect(installation.installationRoot == fixture.tokenDirectory.path)
    #expect(runner.calls == [
        ["--prefix"],
        ["--caskroom"],
        ["info", "--json=v2", "--cask", "codex"],
        ["list", "--verbose", "--cask", "codex"],
    ])
}

@Test func caskTapFullTokenMatchVerifiesAndListsTheFullToken() async throws {
    let fixture = try CaskFixture(
        "tap", token: "codex-cli", fullToken: "acme/tap/codex-cli"
    )
    let installed = try fixture.installBinaryArtifact()
    let declaration = "acme/tap/codex-cli"
    let definition = try caskDefinition(packages: [(.homebrewCask, declaration)])
    let info = caskInfoJSON(records: [
        caskRecordJSON(
            token: "codex-cli", fullToken: declaration, installed: fixture.version
        )
    ])
    let runner = ScriptedRunner(handler: caskBrewScript(
        prefix: fixture.prefixText,
        caskroom: fixture.caskroomText,
        info: info,
        list: Data((fixture.stagedArtifact.path + "\n").utf8),
        listToken: declaration,
        declared: [declaration]
    ))

    let result = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: installed.entry, source: "standalone"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: runner,
        currentDirectory: caskCurrentDirectory(fixture)
    )

    let installation = try #require(result.verifiedInstallation)
    #expect(installation.packageName == declaration)
    #expect(installation.installationRoot == fixture.tokenDirectory.path)
    #expect(runner.calls.last == ["list", "--verbose", "--cask", declaration])
}

@Test func caskOpaqueLatestAndCommaVersionsVerifyWithoutVersionGrammar() async throws {
    for version in ["latest", "1.5.13,5999302598852608", "6.0,9001", "1.2.3 beta"] {
        let fixture = try CaskFixture("opaque-\(version)", version: version)
        let installed = try fixture.installBinaryArtifact()
        let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
        let info = caskInfoJSON(records: [
            caskRecordJSON(token: "codex", fullToken: "codex", installed: version)
        ])
        let runner = ScriptedRunner(handler: caskBrewScript(
            prefix: fixture.prefixText,
            caskroom: fixture.caskroomText,
            info: info,
            list: Data((fixture.stagedArtifact.path + "\n").utf8),
            listToken: "codex",
            declared: ["codex"]
        ))

        let result = await runCaskVerification(
            definition: definition,
            diagnostic: caskDiagnostic(
                executableName: "codex", entryPath: installed.entry, source: "standalone"
            ),
            environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
            runner: runner,
            currentDirectory: caskCurrentDirectory(fixture)
        )
        let installation = try #require(result.verifiedInstallation, "\(version)")
        #expect(installation.installationRoot == fixture.tokenDirectory.path, "\(version)")
    }
}

@Test func caskStatusFlagsPinsAndAutoUpdatesDoNotAffectOwnership() async throws {
    let fixture = try CaskFixture("status-flags")
    let installed = try fixture.installBinaryArtifact()
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
    let info = caskInfoJSON(records: [
        caskRecordJSON(
            token: "codex",
            fullToken: "codex",
            installed: fixture.version,
            extraFields: ",\"auto_updates\":true,\"pinned\":true,\"pinned_version\":\"0.9.0\","
                + "\"deprecated\":true,\"disabled\":true,\"version\":\"latest\","
                + "\"versions\":{\"stable\":null}"
        )
    ])
    let runner = ScriptedRunner(handler: caskBrewScript(
        prefix: fixture.prefixText,
        caskroom: fixture.caskroomText,
        info: info,
        list: Data((fixture.stagedArtifact.path + "\n").utf8),
        listToken: "codex",
        declared: ["codex"]
    ))

    let result = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: installed.entry, source: "standalone"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: runner,
        currentDirectory: caskCurrentDirectory(fixture)
    )

    #expect(result.verifiedInstallation != nil)
}

@Test func caskCaskroomOutsidePrefixIsQueriedSeparately() async throws {
    let fixture = try CaskFixture("external-caskroom", caskroomOutsidePrefix: true)
    let installed = try fixture.installBinaryArtifact()
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
    let info = caskInfoJSON(records: [
        caskRecordJSON(token: "codex", fullToken: "codex", installed: fixture.version)
    ])
    let runner = ScriptedRunner(handler: caskBrewScript(
        prefix: fixture.prefixText,
        caskroom: fixture.caskroomText,
        info: info,
        list: Data((fixture.stagedArtifact.path + "\n").utf8),
        listToken: "codex",
        declared: ["codex"]
    ))

    let result = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: installed.entry, source: "standalone"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: runner,
        currentDirectory: caskCurrentDirectory(fixture)
    )

    let installation = try #require(result.verifiedInstallation)
    #expect(installation.managerRoot == fixture.prefix.path)
    #expect(installation.installationRoot == fixture.tokenDirectory.path)
    #expect(!fixture.tokenDirectory.path.hasPrefix(fixture.prefix.path + "/"))
}

@Test func caskBrewSourceCaskDeclarationUsesTheCaskRoute() async throws {
    let fixture = try CaskFixture("brew-source")
    let installed = try fixture.installBinaryArtifact()
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
    let info = caskInfoJSON(records: [
        caskRecordJSON(token: "codex", fullToken: "codex", installed: fixture.version)
    ])
    let runner = ScriptedRunner(handler: caskBrewScript(
        prefix: fixture.prefixText,
        caskroom: fixture.caskroomText,
        info: info,
        list: Data((fixture.stagedArtifact.path + "\n").utf8),
        listToken: "codex",
        declared: ["codex"]
    ))

    let result = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: installed.entry, source: "brew"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: runner,
        currentDirectory: caskCurrentDirectory(fixture)
    )

    #expect(result.verifiedInstallation?.manager == .homebrewCask)
    #expect(!runner.calls.contains(["--cellar"]))
}

@Test func caskDeclarationOnNpmSourceReachesTheCaskProof() async throws {
    let fixture = try CaskFixture("npm-source-cask")
    let installed = try fixture.installBinaryArtifact()
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
    let info = caskInfoJSON(records: [
        caskRecordJSON(token: "codex", fullToken: "codex", installed: fixture.version)
    ])
    let runner = ScriptedRunner(handler: caskBrewScript(
        prefix: fixture.prefixText,
        caskroom: fixture.caskroomText,
        info: info,
        list: Data((fixture.stagedArtifact.path + "\n").utf8),
        listToken: "codex",
        declared: ["codex"]
    ))

    let result = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: installed.entry, source: "npm"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: runner,
        currentDirectory: caskCurrentDirectory(fixture)
    )

    #expect(result.verifiedInstallation?.manager == .homebrewCask)
    #expect(runner.calls.allSatisfy { $0 != ["prefix", "--global"] && $0 != ["root", "--global"] })
}

// MARK: Declarations, records, and installed values

@Test func caskMoreThanFourDeclarationsRefusesWithoutAProcess() async throws {
    let fixture = try CaskFixture("too-many")
    _ = try fixture.installBinaryArtifact()
    let definition = try caskDefinition(packages: [
        (.homebrewCask, "codex"), (.homebrewCask, "codex-two"), (.homebrewCask, "codex-three"),
        (.homebrewCask, "codex-four"), (.homebrewCask, "codex-five"),
    ])
    let runner = ScriptedRunner(handler: { _, arguments in
        Issue.record("more than four declarations must not query brew: \(arguments)")
        return .failure(.spawnFailure)
    })

    let result = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: fixture.brewPath, source: "standalone"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: runner,
        currentDirectory: caskCurrentDirectory(fixture)
    )

    #expect(result.unknownReason == .tooManyDeclaredCasks)
    #expect(
        result.unknownReason?.message
            == "More than four declared casks were supplied; ownership was not verified"
    )
    #expect(result.unknownReason != .ambiguousOwnership)
    #expect(runner.calls.isEmpty)
}

@Test func caskExactlyFourDeclarationsUsesOneInfoQuery() async throws {
    let fixture = try CaskFixture("four-declarations")
    let installed = try fixture.installBinaryArtifact()
    let definition = try caskDefinition(packages: [
        (.homebrewCask, "codex"), (.homebrewCask, "codex-two"),
        (.homebrewCask, "codex-three"), (.homebrewCask, "codex-four"),
    ])
    let info = caskInfoJSON(records: [
        caskRecordJSON(token: "codex", fullToken: "codex", installed: fixture.version)
    ])
    let declared = ["codex", "codex-two", "codex-three", "codex-four"]
    let runner = ScriptedRunner(handler: caskBrewScript(
        prefix: fixture.prefixText,
        caskroom: fixture.caskroomText,
        info: info,
        list: Data((fixture.stagedArtifact.path + "\n").utf8),
        listToken: "codex",
        declared: declared
    ))

    let result = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: installed.entry, source: "standalone"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: runner,
        currentDirectory: caskCurrentDirectory(fixture)
    )

    #expect(result.verifiedInstallation?.packageName == "codex")
    #expect(runner.calls == [
        ["--prefix"],
        ["--caskroom"],
        ["info", "--json=v2", "--cask"] + declared,
        ["list", "--verbose", "--cask", "codex"],
    ])
}

@Test func caskInstalledNullIsPackageNotInstalled() async throws {
    let fixture = try CaskFixture("installed-null")
    let installed = try fixture.installBinaryArtifact()
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
    let info = caskInfoJSON(records: [
        caskRecordJSON(token: "codex", fullToken: "codex", installed: nil)
    ])
    let runner = ScriptedRunner(handler: caskBrewScript(
        prefix: fixture.prefixText,
        caskroom: fixture.caskroomText,
        info: info,
        list: Data(),
        listToken: "codex",
        declared: ["codex"]
    ))

    let result = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: installed.entry, source: "standalone"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: runner,
        currentDirectory: caskCurrentDirectory(fixture)
    )

    #expect(result.unknownReason == .packageNotInstalled)
    #expect(runner.calls.count == 3)
}

@Test func caskInstalledNonStringIsInvalidManagerOutput() async throws {
    let fixture = try CaskFixture("installed-type")
    let installed = try fixture.installBinaryArtifact()
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
    let records = [
        #"{"token":"codex","full_token":"codex","installed":true,"old_tokens":[]}"#,
        #"{"token":"codex","full_token":"codex","installed":42,"old_tokens":[]}"#,
        #"{"token":"codex","full_token":"codex","installed":["1.0.0"],"old_tokens":[]}"#,
        #"{"token":"codex","full_token":"codex","installed":{"version":"1.0.0"},"old_tokens":[]}"#,
        #"{"token":"codex","full_token":"codex","old_tokens":[]}"#,
    ]

    for (index, record) in records.enumerated() {
        let runner = ScriptedRunner(handler: caskBrewScript(
            prefix: fixture.prefixText,
            caskroom: fixture.caskroomText,
            info: caskInfoJSON(records: [record]),
            list: Data(),
            listToken: "codex",
            declared: ["codex"]
        ))
        let result = await runCaskVerification(
            definition: definition,
            diagnostic: caskDiagnostic(
                executableName: "codex", entryPath: installed.entry, source: "standalone"
            ),
            environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
            runner: runner,
            currentDirectory: caskCurrentDirectory(fixture)
        )
        #expect(result.unknownReason == .invalidManagerOutput, "record \(index)")
        #expect(runner.calls.count == 3, "record \(index)")
    }
}

@Test func caskInstalledStringMismatchIsSelectedCaskNotInstalled() async throws {
    let fixture = try CaskFixture("installed-mismatch")
    let installed = try fixture.installBinaryArtifact()
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
    let info = caskInfoJSON(records: [
        caskRecordJSON(token: "codex", fullToken: "codex", installed: "2.0.0")
    ])
    let runner = ScriptedRunner(handler: caskBrewScript(
        prefix: fixture.prefixText,
        caskroom: fixture.caskroomText,
        info: info,
        list: Data(),
        listToken: "codex",
        declared: ["codex"]
    ))

    let result = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: installed.entry, source: "standalone"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: runner,
        currentDirectory: caskCurrentDirectory(fixture)
    )

    #expect(result.unknownReason == .selectedCaskNotInstalled)
    #expect(runner.calls.count == 3)
}

@Test func caskOldTokenDeclarationIsRenamedFailClosed() async throws {
    let fixture = try CaskFixture("renamed", token: "kiro-cli")
    let installed = try fixture.installBinaryArtifact(entryName: "kiro-cli")
    let definition = try caskDefinition(
        executableName: "kiro-cli", packages: [(.homebrewCask, "amazon-q")]
    )
    let info = caskInfoJSON(records: [
        caskRecordJSON(
            token: "kiro-cli",
            fullToken: "kiro-cli",
            installed: fixture.version,
            oldTokens: ["amazon-q", "codewhisperer"]
        )
    ])
    let runner = ScriptedRunner(handler: caskBrewScript(
        prefix: fixture.prefixText,
        caskroom: fixture.caskroomText,
        info: info,
        list: Data(),
        listToken: "kiro-cli",
        declared: ["amazon-q"]
    ))

    let result = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "kiro-cli", entryPath: installed.entry, source: "standalone"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: runner,
        currentDirectory: caskCurrentDirectory(fixture)
    )

    #expect(result.unknownReason == .caskTokenRenamed)
    #expect(runner.calls == [
        ["--prefix"],
        ["--caskroom"],
        ["info", "--json=v2", "--cask", "amazon-q"],
    ])
}

@Test func caskTapDeclarationWithoutFullTokenEqualityIsRecordMismatch() async throws {
    let fixture = try CaskFixture("tap-mismatch")
    let installed = try fixture.installBinaryArtifact()
    let definition = try caskDefinition(packages: [(.homebrewCask, "acme/tap/codex")])
    let info = caskInfoJSON(records: [
        caskRecordJSON(token: "codex", fullToken: "codex", installed: fixture.version)
    ])
    let runner = ScriptedRunner(handler: caskBrewScript(
        prefix: fixture.prefixText,
        caskroom: fixture.caskroomText,
        info: info,
        list: Data(),
        listToken: "codex",
        declared: ["acme/tap/codex"]
    ))

    let result = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: installed.entry, source: "standalone"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: runner,
        currentDirectory: caskCurrentDirectory(fixture)
    )

    #expect(result.unknownReason == .caskRecordMismatch)
    #expect(runner.calls.count == 3)
}

@Test func caskStagedTokenThatTheManagerDidNotReportIsRecordMismatch() async throws {
    let fixture = try CaskFixture("path-token", token: "other")
    let installed = try fixture.installBinaryArtifact()
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
    let info = caskInfoJSON(records: [
        caskRecordJSON(token: "codex", fullToken: "codex", installed: fixture.version)
    ])
    let runner = ScriptedRunner(handler: caskBrewScript(
        prefix: fixture.prefixText,
        caskroom: fixture.caskroomText,
        info: info,
        list: Data(),
        listToken: "codex",
        declared: ["codex"]
    ))

    let result = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: installed.entry, source: "standalone"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: runner,
        currentDirectory: caskCurrentDirectory(fixture)
    )

    #expect(result.unknownReason == .caskRecordMismatch)
    #expect(runner.calls.count == 3)
}

@Test func caskDuplicateStrictRecordsAreAmbiguous() async throws {
    let fixture = try CaskFixture("ambiguous")
    let installed = try fixture.installBinaryArtifact()
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
    let record = caskRecordJSON(
        token: "codex", fullToken: "codex", installed: fixture.version
    )
    let runner = ScriptedRunner(handler: caskBrewScript(
        prefix: fixture.prefixText,
        caskroom: fixture.caskroomText,
        info: caskInfoJSON(records: [record, record]),
        list: Data(),
        listToken: "codex",
        declared: ["codex"]
    ))

    let result = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: installed.entry, source: "standalone"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: runner,
        currentDirectory: caskCurrentDirectory(fixture)
    )

    #expect(result.unknownReason == .ambiguousOwnership)
    #expect(runner.calls.count == 3)
}

@Test func caskInfoMissingCasksArrayIsInvalidManagerOutput() async throws {
    let fixture = try CaskFixture("info-envelope")
    let installed = try fixture.installBinaryArtifact()
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
    let badEnvelopes = [
        Data("{\"formulae\":[]}".utf8),
        Data("not-json".utf8),
        Data("{\"formulae\":[],\"casks\":{}}".utf8),
        Data("{\"formulae\":[],\"casks\":[{\"token\":\"codex\"}]}".utf8),
        Data("{\"formulae\":[],\"casks\":[{\"token\":7,\"full_token\":\"codex\"}]}".utf8),
        Data(("{\"formulae\":[],\"casks\":[{\"token\":\"codex\",\"full_token\":\"codex\","
            + "\"installed\":\"1.0.0\",\"old_tokens\":\"amazon-q\"}]}").utf8),
    ]

    for (index, envelope) in badEnvelopes.enumerated() {
        let runner = ScriptedRunner(handler: caskBrewScript(
            prefix: fixture.prefixText,
            caskroom: fixture.caskroomText,
            info: envelope,
            list: Data(),
            listToken: "codex",
            declared: ["codex"]
        ))
        let result = await runCaskVerification(
            definition: definition,
            diagnostic: caskDiagnostic(
                executableName: "codex", entryPath: installed.entry, source: "standalone"
            ),
            environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
            runner: runner,
            currentDirectory: caskCurrentDirectory(fixture)
        )
        #expect(result.unknownReason == .invalidManagerOutput, "envelope \(index)")
        #expect(runner.calls.count == 3, "envelope \(index)")
    }
}

@Test func caskEmptyCaskRecordsAreNoMatchingPackage() async throws {
    let fixture = try CaskFixture("no-records")
    let installed = try fixture.installBinaryArtifact()
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
    let runner = ScriptedRunner(handler: caskBrewScript(
        prefix: fixture.prefixText,
        caskroom: fixture.caskroomText,
        info: caskInfoJSON(records: []),
        list: Data(),
        listToken: "codex",
        declared: ["codex"]
    ))

    let result = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: installed.entry, source: "standalone"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: runner,
        currentDirectory: caskCurrentDirectory(fixture)
    )

    #expect(result.unknownReason == .noMatchingPackage)
    #expect(runner.calls.count == 3)
}

@Test func caskShallowCaskroomLayoutIsUnsupported() async throws {
    let fixture = try CaskFixture("shallow")
    let shallow = fixture.tokenDirectory.appendingPathComponent("codex")
    try writeCaskExecutable(shallow)
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
    let runner = ScriptedRunner(handler: { _, arguments in
        switch arguments {
        case ["--prefix"]:
            return .success(Data((fixture.prefixText + "\n").utf8))
        case ["--caskroom"]:
            return .success(Data((fixture.caskroomText + "\n").utf8))
        default:
            Issue.record("shallow layout must not query info/list: \(arguments)")
            return .failure(.spawnFailure)
        }
    })

    let result = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: shallow.path, source: "standalone"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: runner,
        currentDirectory: caskCurrentDirectory(fixture)
    )

    #expect(result.unknownReason == .unsupportedInstallationLayout)
    #expect(runner.calls == [["--prefix"], ["--caskroom"]])
}

// MARK: Listing membership

@Test func caskMetadataOnlyListingNeverProvesMembership() async throws {
    let fixture = try CaskFixture("metadata-only")
    let installed = try fixture.installBinaryArtifact()
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
    let info = caskInfoJSON(records: [
        caskRecordJSON(token: "codex", fullToken: "codex", installed: fixture.version)
    ])
    let metadataLine = fixture.tokenDirectory
        .appendingPathComponent(fixture.version)
        .appendingPathComponent(".metadata/INSTALL_RECEIPT.json").path
    try FileManager.default.createDirectory(
        at: URL(fileURLWithPath: metadataLine).deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try Data("{}".utf8).write(to: URL(fileURLWithPath: metadataLine))
    let runner = ScriptedRunner(handler: caskBrewScript(
        prefix: fixture.prefixText,
        caskroom: fixture.caskroomText,
        info: info,
        list: Data((metadataLine + "\n").utf8),
        listToken: "codex",
        declared: ["codex"]
    ))

    let result = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: installed.entry, source: "standalone"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: runner,
        currentDirectory: caskCurrentDirectory(fixture)
    )

    #expect(result.unknownReason == .caskArtifactUnlinked)
    #expect(runner.calls.count == 4)
}

@Test func caskDifferentStagedFileIsNotConfirmed() async throws {
    let fixture = try CaskFixture("wrong-file")
    let installed = try fixture.installBinaryArtifact()
    let otherArtifact = fixture.versionDirectory.appendingPathComponent("bin/other")
    try writeCaskExecutable(otherArtifact)
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
    let info = caskInfoJSON(records: [
        caskRecordJSON(token: "codex", fullToken: "codex", installed: fixture.version)
    ])
    let runner = ScriptedRunner(handler: caskBrewScript(
        prefix: fixture.prefixText,
        caskroom: fixture.caskroomText,
        info: info,
        list: Data((otherArtifact.path + "\n").utf8),
        listToken: "codex",
        declared: ["codex"]
    ))

    let result = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: installed.entry, source: "standalone"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: runner,
        currentDirectory: caskCurrentDirectory(fixture)
    )

    #expect(result.unknownReason == .selectedCaskNotConfirmed)
    #expect(runner.calls.count == 4)
}

@Test func caskMovedAppSiblingTargetIsNotConfirmed() async throws {
    let fixture = try CaskFixture("sibling-app", artifactRelative: "Codex.app")
    let moved = try fixture.installMovedApp()
    let siblingApp = fixture.root.appendingPathComponent("Applications/Codex.app2")
    let siblingExecutable = siblingApp.appendingPathComponent("Contents/MacOS/codex")
    try writeCaskExecutable(siblingExecutable)
    try? FileManager.default.removeItem(atPath: moved.entry)
    try FileManager.default.createSymbolicLink(
        atPath: moved.entry, withDestinationPath: siblingExecutable.path
    )
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
    let info = caskInfoJSON(records: [
        caskRecordJSON(token: "codex", fullToken: "codex", installed: fixture.version)
    ])
    let runner = ScriptedRunner(handler: caskBrewScript(
        prefix: fixture.prefixText,
        caskroom: fixture.caskroomText,
        info: info,
        list: Data((fixture.stagedArtifact.path + "\n").utf8),
        listToken: "codex",
        declared: ["codex"]
    ))

    let result = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: moved.entry, source: "standalone"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: runner,
        currentDirectory: caskCurrentDirectory(fixture)
    )

    #expect(result.unknownReason == .selectedCaskNotConfirmed)
}

@Test func caskMalformedTrailingLineInvalidatesAnAlreadyMatchedListing() async throws {
    let fixture = try CaskFixture("malformed-trailing")
    let installed = try fixture.installBinaryArtifact()
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
    let info = caskInfoJSON(records: [
        caskRecordJSON(token: "codex", fullToken: "codex", installed: fixture.version)
    ])
    let list = Data((fixture.stagedArtifact.path + "\nrelative/not-absolute\n").utf8)
    let runner = ScriptedRunner(handler: caskBrewScript(
        prefix: fixture.prefixText,
        caskroom: fixture.caskroomText,
        info: info,
        list: list,
        listToken: "codex",
        declared: ["codex"]
    ))

    let result = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: installed.entry, source: "standalone"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: runner,
        currentDirectory: caskCurrentDirectory(fixture)
    )

    #expect(result.unknownReason == .invalidManagerOutput)
}

@Test func caskListingOutsideTheCaskroomIsInvalid() async throws {
    let fixture = try CaskFixture("outside-line")
    let installed = try fixture.installBinaryArtifact()
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
    let info = caskInfoJSON(records: [
        caskRecordJSON(token: "codex", fullToken: "codex", installed: fixture.version)
    ])
    let siblingLine = fixture.root.appendingPathComponent(
        "Caskroom2/codex/\(fixture.version)/bin/codex"
    )
    let runner = ScriptedRunner(handler: caskBrewScript(
        prefix: fixture.prefixText,
        caskroom: fixture.caskroomText,
        info: info,
        list: Data((siblingLine.path + "\n").utf8),
        listToken: "codex",
        declared: ["codex"]
    ))

    let result = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: installed.entry, source: "standalone"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: runner,
        currentDirectory: caskCurrentDirectory(fixture)
    )

    #expect(result.unknownReason == .invalidManagerOutput)
}

@Test func caskListingOverTheLineOrByteCapIsInvalid() async throws {
    let fixture = try CaskFixture("listing-caps")
    let installed = try fixture.installBinaryArtifact()
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
    let info = caskInfoJSON(records: [
        caskRecordJSON(token: "codex", fullToken: "codex", installed: fixture.version)
    ])
    let match = fixture.stagedArtifact.path
    let lineOverflow = Data(
        Array(repeating: match, count: 4097).joined(separator: "\n").utf8
    )
    let byteOverflow = Data(("/" + String(repeating: "a", count: 1_100_000)).utf8)

    for list in [lineOverflow, byteOverflow] {
        let runner = ScriptedRunner(handler: caskBrewScript(
            prefix: fixture.prefixText,
            caskroom: fixture.caskroomText,
            info: info,
            list: list,
            listToken: "codex",
            declared: ["codex"]
        ))
        let result = await runCaskVerification(
            definition: definition,
            diagnostic: caskDiagnostic(
                executableName: "codex", entryPath: installed.entry, source: "standalone"
            ),
            environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
            runner: runner,
            currentDirectory: caskCurrentDirectory(fixture)
        )
        #expect(result.unknownReason == .invalidManagerOutput)
    }
}

// MARK: Correction round 1 — root aliases and reported spellings

@Test func caskRootSymlinkAliasCaskroomVerifies() async throws {
    let fixture = try CaskFixture("alias-root")
    let installed = try fixture.installBinaryArtifact()
    let alias = fixture.root.appendingPathComponent("Caskroom alias", isDirectory: true)
    try FileManager.default.createSymbolicLink(
        atPath: alias.path, withDestinationPath: fixture.caskroom.path
    )
    let receipt = fixture.versionDirectory
        .appendingPathComponent(".metadata/INSTALL_RECEIPT.json")
    try FileManager.default.createDirectory(
        at: receipt.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try Data("{}\n".utf8).write(to: receipt)
    let listing = relativeToListedRoot(
        fixture.stagedArtifact.path, root: fixture.caskroom.path, listedRoot: alias.path
    ) + "\n" + relativeToListedRoot(
        receipt.path, root: fixture.caskroom.path, listedRoot: alias.path
    ) + "\n"
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
    let info = caskInfoJSON(records: [
        caskRecordJSON(token: "codex", fullToken: "codex", installed: fixture.version)
    ])
    let runner = ScriptedRunner(handler: caskBrewScript(
        prefix: fixture.prefixText,
        caskroom: alias.path,
        info: info,
        list: Data(listing.utf8),
        listToken: "codex",
        declared: ["codex"]
    ))

    let result = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: installed.entry, source: "standalone"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: runner,
        currentDirectory: caskCurrentDirectory(fixture)
    )

    let installation = try #require(result.verifiedInstallation)
    #expect(installation.managerRoot == fixture.prefix.path)
    #expect(installation.installationRoot == fixture.tokenDirectory.path)
    #expect(installation.selection.canonicalTarget == installed.target)
    #expect(runner.calls.count == 4)
}

@Test func caskPhysicalPrivateVarCaskroomSpellingVerifies() async throws {
    let fixture = try CaskFixture("private-var")
    let installed = try fixture.installBinaryArtifact()
    let physicalRoot = try #require(FileIdentityObserver.physicalPath(fixture.caskroom.path))
    let listing = relativeToListedRoot(
        fixture.stagedArtifact.path, root: fixture.caskroom.path, listedRoot: physicalRoot
    ) + "\n"
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
    let info = caskInfoJSON(records: [
        caskRecordJSON(token: "codex", fullToken: "codex", installed: fixture.version)
    ])
    let runner = ScriptedRunner(handler: caskBrewScript(
        prefix: fixture.prefixText,
        caskroom: physicalRoot,
        info: info,
        list: Data(listing.utf8),
        listToken: "codex",
        declared: ["codex"]
    ))

    let result = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: installed.entry, source: "standalone"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: runner,
        currentDirectory: caskCurrentDirectory(fixture)
    )

    #expect(result.verifiedInstallation?.installationRoot == fixture.tokenDirectory.path)
    #expect(runner.calls.count == 4)
}

@Test func caskReportedRootAliasRetargetDuringInfoIsProofChanged() async throws {
    let fixture = try CaskFixture("alias-retarget")
    let installed = try fixture.installBinaryArtifact()
    let alias = fixture.root.appendingPathComponent("Caskroom alias", isDirectory: true)
    try FileManager.default.createSymbolicLink(
        atPath: alias.path, withDestinationPath: fixture.caskroom.path
    )
    let other = fixture.root.appendingPathComponent("OtherCaskroom", isDirectory: true)
    try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
    let info = caskInfoJSON(records: [
        caskRecordJSON(token: "codex", fullToken: "codex", installed: fixture.version)
    ])
    let runner = ScriptedRunner(handler: caskBrewScript(
        prefix: fixture.prefixText,
        caskroom: alias.path,
        info: info,
        list: Data((fixture.stagedArtifact.path + "\n").utf8),
        listToken: "codex",
        declared: ["codex"],
        hook: { arguments in
            guard arguments == ["info", "--json=v2", "--cask", "codex"] else { return }
            try? FileManager.default.removeItem(at: alias)
            try? FileManager.default.createSymbolicLink(
                atPath: alias.path, withDestinationPath: other.path
            )
        }
    ))

    let result = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: installed.entry, source: "standalone"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: runner,
        currentDirectory: caskCurrentDirectory(fixture)
    )

    #expect(result.unknownReason == .proofChanged)
    #expect(runner.calls.count == 3)
}

@Test func caskPrefixRetargetDuringCaskroomQueryIsProofChanged() async throws {
    let fixture = try CaskFixture("prefix-retarget", caskroomOutsidePrefix: true)
    let installed = try fixture.installBinaryArtifact()
    let managerBin = fixture.root.appendingPathComponent("manager-bin", isDirectory: true)
    try writeCaskExecutable(managerBin.appendingPathComponent("brew"))
    let prefix = fixture.prefix
    let displaced = fixture.root.appendingPathComponent("prefix-real", isDirectory: true)
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
    let info = caskInfoJSON(records: [
        caskRecordJSON(token: "codex", fullToken: "codex", installed: fixture.version)
    ])
    let runner = ScriptedRunner(handler: caskBrewScript(
        prefix: fixture.prefixText,
        caskroom: fixture.caskroomText,
        info: info,
        list: Data((fixture.stagedArtifact.path + "\n").utf8),
        listToken: "codex",
        declared: ["codex"],
        hook: { arguments in
            guard arguments == ["--caskroom"] else { return }
            try? FileManager.default.moveItem(at: prefix, to: displaced)
            try? FileManager.default.createSymbolicLink(
                atPath: prefix.path, withDestinationPath: displaced.path
            )
        }
    ))

    let result = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: installed.entry, source: "standalone"
        ),
        environment: caskEnvironment(pathEntries: [managerBin.path]),
        runner: runner,
        currentDirectory: caskCurrentDirectory(fixture)
    )

    #expect(result.unknownReason == .proofChanged)
    #expect(runner.calls == [["--prefix"], ["--caskroom"]])
}

@Test func caskUnreportedCaskroomAliasInListingIsInvalid() async throws {
    let fixture = try CaskFixture("unreported-alias")
    let installed = try fixture.installBinaryArtifact()
    let otherAlias = fixture.root.appendingPathComponent("OtherAlias", isDirectory: true)
    try FileManager.default.createSymbolicLink(
        atPath: otherAlias.path, withDestinationPath: fixture.caskroom.path
    )
    let listing = relativeToListedRoot(
        fixture.stagedArtifact.path, root: fixture.caskroom.path, listedRoot: otherAlias.path
    ) + "\n"
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
    let info = caskInfoJSON(records: [
        caskRecordJSON(token: "codex", fullToken: "codex", installed: fixture.version)
    ])
    let runner = ScriptedRunner(handler: caskBrewScript(
        prefix: fixture.prefixText,
        caskroom: fixture.caskroomText,
        info: info,
        list: Data(listing.utf8),
        listToken: "codex",
        declared: ["codex"]
    ))

    let result = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: installed.entry, source: "standalone"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: runner,
        currentDirectory: caskCurrentDirectory(fixture)
    )

    #expect(result.unknownReason == .invalidManagerOutput)
    #expect(runner.calls.count == 4)
}

// MARK: Correction round 1 — moved apps and descendant membership

@Test func caskBroadStagedDirectoryLinkNeverProvesDescendant() async throws {
    let fixture = try CaskFixture("broad-link")
    let unrelated = fixture.root.appendingPathComponent("unrelated/bin/codex")
    try writeCaskExecutable(unrelated)
    let selectionDirectory = fixture.root.appendingPathComponent("selection", isDirectory: true)
    try FileManager.default.createDirectory(
        at: selectionDirectory, withIntermediateDirectories: true
    )
    let entry = selectionDirectory.appendingPathComponent("codex")
    try FileManager.default.createSymbolicLink(
        atPath: entry.path, withDestinationPath: unrelated.path
    )
    let stagedLink = fixture.versionDirectory.appendingPathComponent("unrelated-folder")
    try FileManager.default.createSymbolicLink(
        atPath: stagedLink.path, withDestinationPath: fixture.root.path
    )
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
    let info = caskInfoJSON(records: [
        caskRecordJSON(token: "codex", fullToken: "codex", installed: fixture.version)
    ])
    let runner = ScriptedRunner(handler: caskBrewScript(
        prefix: fixture.prefixText,
        caskroom: fixture.caskroomText,
        info: info,
        list: Data((stagedLink.path + "\n").utf8),
        listToken: "codex",
        declared: ["codex"]
    ))

    let result = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: entry.path, source: "standalone"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: runner,
        currentDirectory: caskCurrentDirectory(fixture)
    )

    #expect(result.verifiedInstallation == nil)
    #expect(result.unknownReason == .selectedCaskNotConfirmed)
    #expect(runner.calls.count == 4)
}

@Test func caskStagedLinkToFileIsNotAMovedApp() async throws {
    let fixture = try CaskFixture("file-link")
    let target = fixture.root.appendingPathComponent("Payload/Flat.app")
    try writeCaskExecutable(target)
    let stagedLink = fixture.versionDirectory.appendingPathComponent("Flat.app")
    try FileManager.default.createSymbolicLink(
        atPath: stagedLink.path, withDestinationPath: target.path
    )
    let selectionDirectory = fixture.root.appendingPathComponent("selection", isDirectory: true)
    try FileManager.default.createDirectory(
        at: selectionDirectory, withIntermediateDirectories: true
    )
    let entry = selectionDirectory.appendingPathComponent("codex")
    try FileManager.default.createSymbolicLink(
        atPath: entry.path, withDestinationPath: target.path
    )
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
    let info = caskInfoJSON(records: [
        caskRecordJSON(token: "codex", fullToken: "codex", installed: fixture.version)
    ])
    let runner = ScriptedRunner(handler: caskBrewScript(
        prefix: fixture.prefixText,
        caskroom: fixture.caskroomText,
        info: info,
        list: Data((stagedLink.path + "\n").utf8),
        listToken: "codex",
        declared: ["codex"]
    ))

    let result = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: entry.path, source: "standalone"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: runner,
        currentDirectory: caskCurrentDirectory(fixture)
    )

    #expect(result.verifiedInstallation == nil)
    #expect(result.unknownReason == .selectedCaskNotConfirmed)
}

@Test func caskStagedLinkToNonAppDirectoryIsNotAMovedApp() async throws {
    let fixture = try CaskFixture("non-app-link")
    let payload = fixture.root.appendingPathComponent("Payload", isDirectory: true)
    let executable = payload.appendingPathComponent("Contents/MacOS/codex")
    try writeCaskExecutable(executable)
    let stagedLink = fixture.versionDirectory.appendingPathComponent("Payload.app")
    try FileManager.default.createSymbolicLink(
        atPath: stagedLink.path, withDestinationPath: payload.path
    )
    let selectionDirectory = fixture.root.appendingPathComponent("selection", isDirectory: true)
    try FileManager.default.createDirectory(
        at: selectionDirectory, withIntermediateDirectories: true
    )
    let entry = selectionDirectory.appendingPathComponent("codex")
    try FileManager.default.createSymbolicLink(
        atPath: entry.path, withDestinationPath: executable.path
    )
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
    let info = caskInfoJSON(records: [
        caskRecordJSON(token: "codex", fullToken: "codex", installed: fixture.version)
    ])
    let runner = ScriptedRunner(handler: caskBrewScript(
        prefix: fixture.prefixText,
        caskroom: fixture.caskroomText,
        info: info,
        list: Data((stagedLink.path + "\n").utf8),
        listToken: "codex",
        declared: ["codex"]
    ))

    let result = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: entry.path, source: "standalone"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: runner,
        currentDirectory: caskCurrentDirectory(fixture)
    )

    #expect(result.verifiedInstallation == nil)
    #expect(result.unknownReason == .selectedCaskNotConfirmed)
}

@Test func caskMovedAppRenamedTargetBundleVerifies() async throws {
    let fixture = try CaskFixture("renamed-moved-app")
    let moved = try installMovedAppLink(
        fixture: fixture, linkName: "Codex Old.app", appName: "Codex New.app"
    )
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
    let info = caskInfoJSON(records: [
        caskRecordJSON(token: "codex", fullToken: "codex", installed: fixture.version)
    ])
    let stagedLink = fixture.versionDirectory.appendingPathComponent("Codex Old.app")
    let runner = ScriptedRunner(handler: caskBrewScript(
        prefix: fixture.prefixText,
        caskroom: fixture.caskroomText,
        info: info,
        list: Data((stagedLink.path + "\n").utf8),
        listToken: "codex",
        declared: ["codex"]
    ))

    let result = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: moved.entry, source: "standalone"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: runner,
        currentDirectory: caskCurrentDirectory(fixture)
    )

    let installation = try #require(result.verifiedInstallation)
    #expect(installation.installationRoot == fixture.tokenDirectory.path)
    #expect(installation.selection.canonicalTarget == moved.executable.path)
    #expect(runner.calls == [
        ["--prefix"],
        ["--caskroom"],
        ["info", "--json=v2", "--cask", "codex"],
        ["list", "--verbose", "--cask", "codex"],
    ])
}

@Test func caskMovedAppLinkRetargetDuringInfoCannotBorrowProof() async throws {
    let fixture = try CaskFixture("moved-link-retarget", artifactRelative: "Codex.app")
    let moved = try fixture.installMovedApp()
    let otherApp = fixture.root.appendingPathComponent("Applications/Other.app", isDirectory: true)
    let otherExecutable = otherApp.appendingPathComponent("Contents/MacOS/codex")
    try writeCaskExecutable(otherExecutable)
    let stagedLink = fixture.versionDirectory.appendingPathComponent("Codex.app")
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
    let info = caskInfoJSON(records: [
        caskRecordJSON(token: "codex", fullToken: "codex", installed: fixture.version)
    ])
    let runner = ScriptedRunner(handler: caskBrewScript(
        prefix: fixture.prefixText,
        caskroom: fixture.caskroomText,
        info: info,
        list: Data((stagedLink.path + "\n").utf8),
        listToken: "codex",
        declared: ["codex"],
        hook: { arguments in
            guard arguments == ["info", "--json=v2", "--cask", "codex"] else { return }
            try? FileManager.default.removeItem(at: stagedLink)
            try? FileManager.default.createSymbolicLink(
                atPath: stagedLink.path, withDestinationPath: otherApp.path
            )
        }
    ))

    let result = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: moved.entry, source: "standalone"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: runner,
        currentDirectory: caskCurrentDirectory(fixture)
    )

    #expect(result.verifiedInstallation == nil)
    #expect(result.unknownReason == .selectedCaskNotConfirmed)
    #expect(runner.calls.count == 4)
}

// MARK: Correction round 1 — metadata, tokens, and exact directory bindings

@Test func caskMetadataInTheSelectedProofPathIsUnsupportedBeforeInfo() async throws {
    let cases: [(label: String, version: String, artifact: String)] = [
        ("metadata-version", ".metadata", "bin/codex"),
        ("metadata-artifact", "1.0.0", ".metadata/bin/codex"),
    ]
    for item in cases {
        let fixture = try CaskFixture(
            item.label, version: item.version, artifactRelative: item.artifact
        )
        let installed = try fixture.installBinaryArtifact()
        let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
        let runner = ScriptedRunner(handler: { _, arguments in
            switch arguments {
            case ["--prefix"]:
                return .success(Data((fixture.prefixText + "\n").utf8))
            case ["--caskroom"]:
                return .success(Data((fixture.caskroomText + "\n").utf8))
            default:
                Issue.record("metadata path must not query info/list: \(arguments)")
                return .failure(.spawnFailure)
            }
        })

        let result = await runCaskVerification(
            definition: definition,
            diagnostic: caskDiagnostic(
                executableName: "codex", entryPath: installed.entry, source: "standalone"
            ),
            environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
            runner: runner,
            currentDirectory: caskCurrentDirectory(fixture)
        )

        #expect(result.unknownReason == .unsupportedInstallationLayout, "\(item.label)")
        #expect(runner.calls.count == 2, "\(item.label)")
    }
}

@Test func caskMetadataInstalledVersionIsInvalidManagerOutput() async throws {
    let fixture = try CaskFixture("metadata-installed")
    let installed = try fixture.installBinaryArtifact()
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
    let info = caskInfoJSON(records: [
        caskRecordJSON(token: "codex", fullToken: "codex", installed: ".metadata")
    ])
    let runner = ScriptedRunner(handler: caskBrewScript(
        prefix: fixture.prefixText,
        caskroom: fixture.caskroomText,
        info: info,
        list: Data((fixture.stagedArtifact.path + "\n").utf8),
        listToken: "codex",
        declared: ["codex"]
    ))

    let result = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: installed.entry, source: "standalone"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: runner,
        currentDirectory: caskCurrentDirectory(fixture)
    )

    #expect(result.unknownReason == .invalidManagerOutput)
    #expect(runner.calls.count == 3)
}

@Test func caskContradictoryRecordMetadataIsInvalidBeforeList() async throws {
    let fixture = try CaskFixture("contradictory-token")
    let installed = try fixture.installBinaryArtifact()
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
    let valid = caskRecordJSON(token: "codex", fullToken: "codex", installed: fixture.version)
    let invalidRecords: [[String]] = [
        [#"{"token":"other-cask","full_token":"codex","installed":"1.0.0","old_tokens":[]}"#],
        [#"{"token":"codex","full_token":"acme/tap/other","installed":"1.0.0","old_tokens":[]}"#],
        [#"{"token":"bad/token","full_token":"bad/token","installed":"1.0.0","old_tokens":[]}"#],
        [
            #"{"token":"codex","full_token":"acme/tap/other","installed":"1.0.0","old_tokens":[]}"#,
            valid,
        ],
    ]
    for (index, records) in invalidRecords.enumerated() {
        let runner = ScriptedRunner(handler: caskBrewScript(
            prefix: fixture.prefixText,
            caskroom: fixture.caskroomText,
            info: caskInfoJSON(records: records),
            list: Data((fixture.stagedArtifact.path + "\n").utf8),
            listToken: "codex",
            declared: ["codex"]
        ))

        let result = await runCaskVerification(
            definition: definition,
            diagnostic: caskDiagnostic(
                executableName: "codex", entryPath: installed.entry, source: "standalone"
            ),
            environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
            runner: runner,
            currentDirectory: caskCurrentDirectory(fixture)
        )

        #expect(result.unknownReason == .invalidManagerOutput, "case \(index)")
        #expect(runner.calls.count == 3, "case \(index)")
    }
}

@Test func caskStagedTokenDirectoryIdentityChangeDuringInfoIsProofChanged() async throws {
    let fixture = try CaskFixture("staged-token-change")
    let installed = try fixture.installBinaryArtifact()
    let tokenDirectory = fixture.tokenDirectory
    let attributes = try FileManager.default.attributesOfItem(atPath: tokenDirectory.path)
    let mode = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0o755
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
    let info = caskInfoJSON(records: [
        caskRecordJSON(token: "codex", fullToken: "codex", installed: fixture.version)
    ])
    let runner = ScriptedRunner(handler: caskBrewScript(
        prefix: fixture.prefixText,
        caskroom: fixture.caskroomText,
        info: info,
        list: Data((fixture.stagedArtifact.path + "\n").utf8),
        listToken: "codex",
        declared: ["codex"],
        hook: { arguments in
            guard arguments == ["info", "--json=v2", "--cask", "codex"] else { return }
            try? FileManager.default.setAttributes(
                [.posixPermissions: mode ^ 0o020], ofItemAtPath: tokenDirectory.path
            )
        }
    ))

    let result = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: installed.entry, source: "standalone"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: runner,
        currentDirectory: caskCurrentDirectory(fixture)
    )

    #expect(result.unknownReason == .proofChanged)
    #expect(runner.calls.count == 3)
}

@Test func caskKnownStagedTokenRetargetDuringInfoIsProofChanged() async throws {
    let fixture = try CaskFixture("moved-token-retarget", artifactRelative: "Codex.app")
    let moved = try fixture.installMovedApp()
    let tokenDirectory = fixture.tokenDirectory
    let copy = fixture.caskroom.appendingPathComponent("codex-copy", isDirectory: true)
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
    let info = caskInfoJSON(records: [
        caskRecordJSON(token: "codex", fullToken: "codex", installed: fixture.version)
    ])
    let runner = ScriptedRunner(handler: caskBrewScript(
        prefix: fixture.prefixText,
        caskroom: fixture.caskroomText,
        info: info,
        list: Data((fixture.stagedArtifact.path + "\n").utf8),
        listToken: "codex",
        declared: ["codex"],
        hook: { arguments in
            guard arguments == ["info", "--json=v2", "--cask", "codex"] else { return }
            try? FileManager.default.moveItem(at: tokenDirectory, to: copy)
            try? FileManager.default.createSymbolicLink(
                atPath: tokenDirectory.path, withDestinationPath: copy.path
            )
        }
    ))

    let result = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: moved.entry, source: "standalone"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: runner,
        currentDirectory: caskCurrentDirectory(fixture)
    )

    #expect(result.unknownReason == .proofChanged)
    #expect(runner.calls.count == 3)
}

@Test func caskSymlinkedSiblingTokenDirectoryIsUnsupported() async throws {
    let fixture = try CaskFixture("sibling-token-link", artifactRelative: "Codex.app")
    let moved = try fixture.installMovedApp()
    let tokenDirectory = fixture.tokenDirectory
    let copy = fixture.caskroom.appendingPathComponent("codex-copy", isDirectory: true)
    try FileManager.default.moveItem(at: tokenDirectory, to: copy)
    try FileManager.default.createSymbolicLink(
        atPath: tokenDirectory.path, withDestinationPath: copy.path
    )
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
    let info = caskInfoJSON(records: [
        caskRecordJSON(token: "codex", fullToken: "codex", installed: fixture.version)
    ])
    let runner = ScriptedRunner(handler: caskBrewScript(
        prefix: fixture.prefixText,
        caskroom: fixture.caskroomText,
        info: info,
        list: Data((fixture.stagedArtifact.path + "\n").utf8),
        listToken: "codex",
        declared: ["codex"]
    ))

    let result = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: moved.entry, source: "standalone"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: runner,
        currentDirectory: caskCurrentDirectory(fixture)
    )

    #expect(result.unknownReason == .unsupportedInstallationLayout)
    #expect(runner.calls.count == 3)
}

@Test func caskSymlinkedSiblingVersionDirectoryIsUnsupported() async throws {
    let fixture = try CaskFixture("sibling-version-link", artifactRelative: "Codex.app")
    let moved = try fixture.installMovedApp()
    let versionDirectory = fixture.versionDirectory
    let copy = fixture.tokenDirectory.appendingPathComponent("1.0.0-copy", isDirectory: true)
    try FileManager.default.moveItem(at: versionDirectory, to: copy)
    try FileManager.default.createSymbolicLink(
        atPath: versionDirectory.path, withDestinationPath: copy.path
    )
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
    let info = caskInfoJSON(records: [
        caskRecordJSON(token: "codex", fullToken: "codex", installed: fixture.version)
    ])
    let runner = ScriptedRunner(handler: caskBrewScript(
        prefix: fixture.prefixText,
        caskroom: fixture.caskroomText,
        info: info,
        list: Data((fixture.stagedArtifact.path + "\n").utf8),
        listToken: "codex",
        declared: ["codex"]
    ))

    let result = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: moved.entry, source: "standalone"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: runner,
        currentDirectory: caskCurrentDirectory(fixture)
    )

    #expect(result.unknownReason == .unsupportedInstallationLayout)
    #expect(runner.calls.count == 3)
}

@Test func caskListingPhysicalLineCapAllowsOneTerminalEnding() async throws {
    let fixture = try CaskFixture("physical-line-cap")
    let installed = try fixture.installBinaryArtifact()
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
    let info = caskInfoJSON(records: [
        caskRecordJSON(token: "codex", fullToken: "codex", installed: fixture.version)
    ])
    let match = fixture.stagedArtifact.path
    let allowed = Data((Array(repeating: match, count: 4096).joined(separator: "\n") + "\n").utf8)
    let overflow = Data((Array(repeating: match, count: 4097).joined(separator: "\n") + "\n").utf8)
    let doubleEnding = Data((match + "\n\n").utf8)

    let allowedRunner = ScriptedRunner(handler: caskBrewScript(
        prefix: fixture.prefixText,
        caskroom: fixture.caskroomText,
        info: info,
        list: allowed,
        listToken: "codex",
        declared: ["codex"]
    ))
    let allowedResult = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: installed.entry, source: "standalone"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: allowedRunner,
        currentDirectory: caskCurrentDirectory(fixture)
    )
    #expect(allowedResult.verifiedInstallation != nil)

    for list in [overflow, doubleEnding] {
        let runner = ScriptedRunner(handler: caskBrewScript(
            prefix: fixture.prefixText,
            caskroom: fixture.caskroomText,
            info: info,
            list: list,
            listToken: "codex",
            declared: ["codex"]
        ))
        let result = await runCaskVerification(
            definition: definition,
            diagnostic: caskDiagnostic(
                executableName: "codex", entryPath: installed.entry, source: "standalone"
            ),
            environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
            runner: runner,
            currentDirectory: caskCurrentDirectory(fixture)
        )
        #expect(result.unknownReason == .invalidManagerOutput)
    }
}

// MARK: Identity changes and cancellation

@Test func caskManagerChangeAfterPrefixSuppressesLaterQueries() async throws {
    let fixture = try CaskFixture("manager-change")
    let installed = try fixture.installBinaryArtifact()
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
    let brewPath = fixture.brewPath
    let runner = ScriptedRunner(handler: caskBrewScript(
        prefix: fixture.prefixText,
        caskroom: fixture.caskroomText,
        info: caskInfoJSON(records: []),
        list: Data(),
        listToken: "codex",
        declared: ["codex"],
        hook: { arguments in
            guard arguments == ["--prefix"] else { return }
            try? Data("#!/bin/sh\nexit 0\n".utf8)
                .write(to: URL(fileURLWithPath: brewPath))
        }
    ))

    let result = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: installed.entry, source: "standalone"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: runner,
        currentDirectory: caskCurrentDirectory(fixture)
    )

    #expect(result.unknownReason == .managerChanged)
    #expect(runner.calls == [["--prefix"]])
}

@Test func caskSelectionChangeDuringInfoSuppressesTheList() async throws {
    let fixture = try CaskFixture("selection-change")
    let installed = try fixture.installBinaryArtifact()
    let replacement = fixture.versionDirectory.appendingPathComponent("bin/codex-replacement")
    try writeCaskExecutable(replacement, version: "2.0.0")
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
    let info = caskInfoJSON(records: [
        caskRecordJSON(token: "codex", fullToken: "codex", installed: fixture.version)
    ])
    let entry = installed.entry
    let runner = ScriptedRunner(handler: caskBrewScript(
        prefix: fixture.prefixText,
        caskroom: fixture.caskroomText,
        info: info,
        list: Data((fixture.stagedArtifact.path + "\n").utf8),
        listToken: "codex",
        declared: ["codex"],
        hook: { arguments in
            guard arguments == ["info", "--json=v2", "--cask", "codex"] else { return }
            try? FileManager.default.removeItem(atPath: entry)
            try? FileManager.default.createSymbolicLink(
                atPath: entry, withDestinationPath: replacement.path
            )
        }
    ))

    let result = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: installed.entry, source: "standalone"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: runner,
        currentDirectory: caskCurrentDirectory(fixture)
    )

    #expect(result.unknownReason == .selectedExecutableChanged)
    #expect(runner.calls.count == 3)
}

@Test func caskCaskroomReplacementDuringInfoIsProofChanged() async throws {
    let fixture = try CaskFixture("caskroom-change", artifactRelative: "Codex.app")
    let moved = try fixture.installMovedApp()
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
    let info = caskInfoJSON(records: [
        caskRecordJSON(token: "codex", fullToken: "codex", installed: fixture.version)
    ])
    let caskroom = fixture.caskroom
    let displaced = fixture.root.appendingPathComponent("Caskroom-displaced")
    let runner = ScriptedRunner(handler: caskBrewScript(
        prefix: fixture.prefixText,
        caskroom: fixture.caskroomText,
        info: info,
        list: Data((fixture.stagedArtifact.path + "\n").utf8),
        listToken: "codex",
        declared: ["codex"],
        hook: { arguments in
            guard arguments == ["info", "--json=v2", "--cask", "codex"] else { return }
            try? FileManager.default.moveItem(at: caskroom, to: displaced)
        }
    ))

    let result = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: moved.entry, source: "standalone"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: runner,
        currentDirectory: caskCurrentDirectory(fixture)
    )

    #expect(result.unknownReason == .proofChanged)
    #expect(runner.calls.count == 3)
}

@Test func caskTokenDirectoryReplacementDuringListIsProofChanged() async throws {
    let fixture = try CaskFixture("token-change", artifactRelative: "Codex.app")
    let moved = try fixture.installMovedApp()
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
    let info = caskInfoJSON(records: [
        caskRecordJSON(token: "codex", fullToken: "codex", installed: fixture.version)
    ])
    let tokenDirectory = fixture.tokenDirectory
    let displaced = fixture.caskroom.appendingPathComponent("codex-displaced")
    let runner = ScriptedRunner(handler: caskBrewScript(
        prefix: fixture.prefixText,
        caskroom: fixture.caskroomText,
        info: info,
        list: Data((fixture.stagedArtifact.path + "\n").utf8),
        listToken: "codex",
        declared: ["codex"],
        hook: { arguments in
            guard arguments == ["list", "--verbose", "--cask", "codex"] else { return }
            try? FileManager.default.moveItem(at: tokenDirectory, to: displaced)
        }
    ))

    let result = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: moved.entry, source: "standalone"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: runner,
        currentDirectory: caskCurrentDirectory(fixture)
    )

    #expect(result.unknownReason == .proofChanged)
    #expect(runner.calls.count == 4)
}

@Test func caskVersionDirectoryReplacementDuringListIsProofChanged() async throws {
    let fixture = try CaskFixture("version-change", artifactRelative: "Codex.app")
    let moved = try fixture.installMovedApp()
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
    let info = caskInfoJSON(records: [
        caskRecordJSON(token: "codex", fullToken: "codex", installed: fixture.version)
    ])
    let versionDirectory = fixture.versionDirectory
    let displaced = fixture.tokenDirectory.appendingPathComponent("displaced")
    let runner = ScriptedRunner(handler: caskBrewScript(
        prefix: fixture.prefixText,
        caskroom: fixture.caskroomText,
        info: info,
        list: Data((fixture.stagedArtifact.path + "\n").utf8),
        listToken: "codex",
        declared: ["codex"],
        hook: { arguments in
            guard arguments == ["list", "--verbose", "--cask", "codex"] else { return }
            try? FileManager.default.moveItem(at: versionDirectory, to: displaced)
        }
    ))

    let result = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: moved.entry, source: "standalone"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: runner,
        currentDirectory: caskCurrentDirectory(fixture)
    )

    #expect(result.unknownReason == .proofChanged)
    #expect(runner.calls.count == 4)
}

// MARK: Manager output refusals

@Test func caskMalformedOrFailedManagerRootsAreNeutral() async throws {
    let fixture = try CaskFixture("root-output")
    let installed = try fixture.installBinaryArtifact()
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])

    let malformedPrefix = ScriptedRunner(handler: { _, arguments in
        guard arguments == ["--prefix"] else {
            Issue.record("malformed prefix must not proceed: \(arguments)")
            return .failure(.spawnFailure)
        }
        return .success(Data("relative/path\n".utf8))
    })
    let prefixResult = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: installed.entry, source: "standalone"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: malformedPrefix,
        currentDirectory: caskCurrentDirectory(fixture)
    )
    #expect(prefixResult.unknownReason == .invalidManagerOutput)
    #expect(malformedPrefix.calls == [["--prefix"]])

    let failedCaskroom = ScriptedRunner(handler: { _, arguments in
        switch arguments {
        case ["--prefix"]:
            return .success(Data((fixture.prefixText + "\n").utf8))
        case ["--caskroom"]:
            return .failure(.nonzeroExit)
        default:
            Issue.record("failed caskroom must suppress later queries: \(arguments)")
            return .failure(.spawnFailure)
        }
    })
    let caskroomResult = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: installed.entry, source: "standalone"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: failedCaskroom,
        currentDirectory: caskCurrentDirectory(fixture)
    )
    #expect(caskroomResult.unknownReason == .managerQueryFailed)
    #expect(failedCaskroom.calls == [["--prefix"], ["--caskroom"]])
}

@Test func caskInfoFailureAndMissingTokenDirectoryAreNeutral() async throws {
    let fixture = try CaskFixture("info-failure", artifactRelative: "Codex.app")
    let moved = try fixture.installMovedApp()
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])

    let failedInfo = ScriptedRunner(handler: { _, arguments in
        switch arguments {
        case ["--prefix"]:
            return .success(Data((fixture.prefixText + "\n").utf8))
        case ["--caskroom"]:
            return .success(Data((fixture.caskroomText + "\n").utf8))
        case ["info", "--json=v2", "--cask", "codex"]:
            return .failure(.nonzeroExit)
        default:
            Issue.record("failed info must suppress later queries: \(arguments)")
            return .failure(.spawnFailure)
        }
    })
    let infoResult = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: moved.entry, source: "standalone"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: failedInfo,
        currentDirectory: caskCurrentDirectory(fixture)
    )
    #expect(infoResult.unknownReason == .managerQueryFailed)
    #expect(failedInfo.calls.count == 3)

    let tokenDirectory = fixture.tokenDirectory
    let displaced = fixture.root.appendingPathComponent("token-displaced")
    let info = caskInfoJSON(records: [
        caskRecordJSON(token: "codex", fullToken: "codex", installed: fixture.version)
    ])
    let missingToken = ScriptedRunner(handler: caskBrewScript(
        prefix: fixture.prefixText,
        caskroom: fixture.caskroomText,
        info: info,
        list: Data(),
        listToken: "codex",
        declared: ["codex"],
        hook: { arguments in
            guard arguments == ["info", "--json=v2", "--cask", "codex"] else { return }
            try? FileManager.default.moveItem(at: tokenDirectory, to: displaced)
        }
    ))
    let tokenResult = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: moved.entry, source: "standalone"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: missingToken,
        currentDirectory: caskCurrentDirectory(fixture)
    )
    #expect(tokenResult.unknownReason == .unsupportedInstallationLayout)
    #expect(missingToken.calls.count == 3)
}

// MARK: Component parser

@Test func caskTargetParserDecomposesOpaqueVersionsAndRejectsSiblingOrShallowRoots() {
    let root = "/synthetic/Caskroom"
    let parsed = HomebrewCaskTargetParser.parse(
        selectedTarget: "/synthetic/Caskroom/codex/1.5.13,5999302598852608/bin/codex",
        caskroom: root
    )
    switch parsed {
    case .success(let cask):
        #expect(cask.caskroom == root)
        #expect(cask.token == "codex")
        #expect(cask.versionDirectory == "1.5.13,5999302598852608")
        #expect(cask.relativeArtifact == "bin/codex")
        #expect(cask.selectedTarget == "/synthetic/Caskroom/codex/1.5.13,5999302598852608/bin/codex")
    case .failure(let failure):
        Issue.record("opaque version should decompose: \(failure)")
    }

    #expect(
        HomebrewCaskTargetParser.parse(
            selectedTarget: "/synthetic/Caskroom2/codex/1.0.0/bin/codex", caskroom: root
        ) == .failure(.managerMismatch)
    )
    #expect(
        HomebrewCaskTargetParser.parse(
            selectedTarget: "/synthetic/Caskroom/codex/1.0.0", caskroom: root
        ) == .failure(.unverified)
    )
    #expect(
        HomebrewCaskTargetParser.parse(
            selectedTarget: "/synthetic/Caskroom/codex/../escape/bin/codex", caskroom: root
        ) == .failure(.unverified)
    )
    #expect(
        HomebrewCaskTargetParser.parse(
            selectedTarget: "/synthetic/Caskroom//codex/1.0.0/bin/codex", caskroom: root
        ) == .failure(.unverified)
    )
    for metadataTarget in [
        "/synthetic/Caskroom/.metadata/1.0.0/bin/codex",
        "/synthetic/Caskroom/codex/.metadata/bin/codex",
        "/synthetic/Caskroom/codex/1.0.0/.metadata/bin/codex",
    ] {
        #expect(
            HomebrewCaskTargetParser.parse(
                selectedTarget: metadataTarget, caskroom: root
            ) == .failure(.unverified),
            "\(metadataTarget)"
        )
    }
}

@Test func caskSiblingCaskroomSelectionNeverVerifies() async throws {
    let fixture = try CaskFixture("sibling-root")
    let staged = try fixture.installBinaryArtifact()
    let sibling = fixture.root.appendingPathComponent(
        "Caskroom2/codex/\(fixture.version)/bin/codex"
    )
    try writeCaskExecutable(sibling)
    let siblingSelection = fixture.root.appendingPathComponent("selection/codex")
    try FileManager.default.createDirectory(
        at: siblingSelection.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try FileManager.default.createSymbolicLink(
        atPath: siblingSelection.path, withDestinationPath: sibling.path
    )
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
    let info = caskInfoJSON(records: [
        caskRecordJSON(token: "codex", fullToken: "codex", installed: fixture.version)
    ])
    let runner = ScriptedRunner(handler: caskBrewScript(
        prefix: fixture.prefixText,
        caskroom: fixture.caskroomText,
        info: info,
        list: Data((staged.target + "\n").utf8),
        listToken: "codex",
        declared: ["codex"]
    ))

    let result = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: siblingSelection.path, source: "standalone"
        ),
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: runner,
        currentDirectory: caskCurrentDirectory(fixture)
    )

    #expect(result.verifiedInstallation == nil)
    #expect(result.unknownReason == .selectedCaskNotConfirmed)
}

// MARK: Cancellation

private actor CaskQueryGate {
    private var entryCount = 0
    private var entryWaiter: CheckedContinuation<Void, Never>?
    private var pending: CommandOutcome?
    private var responseWaiter: CheckedContinuation<CommandOutcome, Never>?

    func noteEntry() {
        entryCount += 1
        entryWaiter?.resume()
        entryWaiter = nil
    }

    func waitForEntry() async {
        if entryCount > 0 { return }
        await withCheckedContinuation { entryWaiter = $0 }
    }

    func takeResponse() async -> CommandOutcome {
        if let pending { return pending }
        return await withCheckedContinuation { responseWaiter = $0 }
    }

    func respond(_ outcome: CommandOutcome) {
        if let responseWaiter {
            responseWaiter.resume(returning: outcome)
            self.responseWaiter = nil
        } else {
            pending = outcome
        }
    }

    var entries: Int { entryCount }
}

private struct CaskGatedRunner: UpdateCommandRunner, Sendable {
    let gate: CaskQueryGate

    func run(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval
    ) async -> CommandOutcome {
        await gate.noteEntry()
        return await gate.takeResponse()
    }
}

@Test func caskCancellationReturnsCancelledAndStopsTheProof() async throws {
    let fixture = try CaskFixture("cancelled")
    let installed = try fixture.installBinaryArtifact()
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
    let gate = CaskQueryGate()
    let runner = CaskGatedRunner(gate: gate)
    let task = Task {
        await InstallationOwnershipVerifier.verify(
            definition: definition,
            diagnostic: caskDiagnostic(
                executableName: "codex", entryPath: installed.entry, source: "standalone"
            ),
            environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
            runner: runner,
            currentDirectory: fixture.root.path,
            now: fixedCaskClock()
        )
    }

    await gate.waitForEntry()
    task.cancel()
    await gate.respond(.success(Data((fixture.prefixText + "\n").utf8)))
    let result = await task.value

    #expect(result.unknownReason == .cancelled)
    #expect(await gate.entries == 1)
}

// MARK: Routing regressions

@Test func caskSourceWithFormulaDeclarationKeepsTheFormulaProof() async throws {
    let fixture = try makeBrewFixture("m13a-formula-route")
    let target = try fixture.installKeg(formula: "codex", keg: "1.0.0")
    let definition = try caskDefinition(packages: [
        (.homebrewFormula, "codex"), (.homebrewCask, "codex"),
    ])
    let info = infoJSON([(name: "codex", stable: "1.0.0", revision: 1, installed: ["1.0.0"])])
    let runner = ScriptedRunner(handler: { _, arguments in
        switch arguments {
        case ["--cellar"]:
            return .success(Data((fixture.cellar + "\n").utf8))
        case ["info", "--json=v2", "--formula", "codex"]:
            return .success(info)
        case ["list", "--verbose", "--formula", "codex"]:
            return .success(Data((target + "\n").utf8))
        default:
            Issue.record("formula route must not run cask argv: \(arguments)")
            return .failure(.spawnFailure)
        }
    })
    let entry = fixture.prefix.appendingPathComponent("bin/codex").path

    let result = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: entry, source: "brew"
        ),
        environment: m6Environment(pathEntries: [fixture.binDirectory]),
        runner: runner,
        currentDirectory: fixture.prefix.deletingLastPathComponent().path
    )

    #expect(result.verifiedInstallation?.manager == .homebrewFormula)
    #expect(runner.calls == [
        ["--cellar"],
        ["info", "--json=v2", "--formula", "codex"],
        ["list", "--verbose", "--formula", "codex"],
    ])
}

@Test func caskSourceWithNpmDeclarationKeepsTheNpmProof() async throws {
    let root = try caskScratchRoot("npm-route")
    let prefix = root.appendingPathComponent("prefix", isDirectory: true)
    let managerDirectory = root.appendingPathComponent("manager-bin", isDirectory: true)
    let nodeModules = prefix.appendingPathComponent("lib/node_modules", isDirectory: true)
    try writeCaskExecutable(managerDirectory.appendingPathComponent("npm"))
    try FileManager.default.createDirectory(at: nodeModules, withIntermediateDirectories: true)
    let selectionDirectory = root.appendingPathComponent("selection", isDirectory: true)
    let selection = selectionDirectory.appendingPathComponent("codex")
    try writeCaskExecutable(selection)
    let definition = try caskDefinition(packages: [
        (.npm, "@openai/codex"), (.homebrewCask, "codex"),
    ])
    let runner = ScriptedRunner(handler: { _, arguments in
        switch arguments {
        case ["prefix", "--global"]:
            return .success(Data((prefix.path + "\n").utf8))
        case ["root", "--global"]:
            return .success(Data((nodeModules.path + "\n").utf8))
        default:
            Issue.record("npm route must not run cask argv: \(arguments)")
            return .failure(.spawnFailure)
        }
    })

    let result = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: selection.path, source: "npm"
        ),
        environment: caskEnvironment(pathEntries: [managerDirectory.path]),
        runner: runner,
        currentDirectory: root.path
    )

    #expect(result.verifiedInstallation == nil)
    #expect(runner.calls == [["prefix", "--global"], ["root", "--global"]])
}

@Test func caskManagerUnavailableRefusesWithoutAProcess() async throws {
    let fixture = try CaskFixture("manager-missing")
    let installed = try fixture.installBinaryArtifact()
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
    let runner = ScriptedRunner(handler: { _, arguments in
        Issue.record("a missing manager must not query brew: \(arguments)")
        return .failure(.spawnFailure)
    })

    let result = await runCaskVerification(
        definition: definition,
        diagnostic: caskDiagnostic(
            executableName: "codex", entryPath: installed.entry, source: "standalone"
        ),
        environment: caskEnvironment(pathEntries: [fixture.prefix.path + "/no-manager"]),
        runner: runner,
        currentDirectory: caskCurrentDirectory(fixture)
    )

    #expect(result.unknownReason == .managerUnavailable)
    #expect(runner.calls.isEmpty)
}

@Test func caskFormulaProbeStillRefusesACaskOnlyDeclarationDirectly() async throws {
    let fixture = try makeBrewFixture("m13a-formula-probe-cask")
    _ = try fixture.installKeg(formula: "codex", keg: "1.0.0")
    let definition = try caskDefinition(packages: [(.homebrewCask, "codex")])
    let selection = try #require(FileIdentityObserver.observeExecutable(
        entryPath: fixture.prefix.appendingPathComponent("bin/codex").path
    ))
    let manager = try #require(FileIdentityObserver.observeExecutable(
        entryPath: fixture.brewPath
    ))
    let runner = ScriptedRunner(handler: { _, arguments in
        guard arguments == ["--cellar"] else {
            Issue.record("the formula probe must not query further: \(arguments)")
            return .failure(.spawnFailure)
        }
        return .success(Data((fixture.cellar + "\n").utf8))
    })

    let outcome = await HomebrewOwnershipProbe.verify(
        definition: definition,
        selection: selection,
        manager: manager,
        environment: caskEnvironment(pathEntries: [fixture.binDirectory]),
        runner: runner
    )

    #expect(outcome == .unknown(.unsupportedCask))
    #expect(runner.calls == [["--cellar"]])
}
