// UvToolOwnershipTests — M14-B real uv tool proof shapes from Phase A.
//
// Every fixture is synthetic and test-owned: a scratch uv tool root, managed shim, receipt,
// pyvenv, dist-info and a scripted two-query runner. No real uv or install command is invoked.

import CryptoKit
import Foundation
import Testing
@testable import AgentLensCore

private func uvScratchRoot(_ label: String) throws -> URL {
    let environment = ProcessInfo.processInfo.environment
    guard let basePath = [environment["AGENT_LENS_TEST_SCRATCH"], environment["TMPDIR"]]
        .compactMap({ $0 })
        .first(where: { !$0.isEmpty })
    else {
        throw NSError(
            domain: "AgentLensUvOwnershipTests", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "no approved test scratch root"]
        )
    }
    let base = URL(fileURLWithPath: basePath, isDirectory: true).resolvingSymlinksInPath()
    let root = base.appendingPathComponent(
        "agentlens-m14b-uv-\(label)-\(UUID().uuidString)", isDirectory: true
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root.resolvingSymlinksInPath()
}

private func uvWriteExecutable(_ url: URL, contents: String) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try Data(contents.utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
}

private func uvWrite(_ url: URL, _ contents: String) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try Data(contents.utf8).write(to: url)
}

private func uvBase64URLSHA256(_ data: Data) -> String {
    Data(SHA256.hash(data: data))
        .base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

private final class UvScriptedRunner: UpdateCommandRunner, @unchecked Sendable {
    private var calls: [[String]] = []
    private var environments: [[String: String]] = []
    let toolDir: String
    let binDir: String
    let customHandler: (@Sendable ([String]) -> CommandOutcome)?

    init(toolDir: String, binDir: String,
         customHandler: (@Sendable ([String]) -> CommandOutcome)? = nil) {
        self.toolDir = toolDir
        self.binDir = binDir
        self.customHandler = customHandler
    }

    var arguments: [[String]] { calls }
    var lastEnvironment: [String: String]? { environments.last }

    func run(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval
    ) async -> CommandOutcome {
        calls.append(arguments)
        environments.append(environment)
        if let customHandler { return customHandler(arguments) }
        if arguments == ["tool", "dir"] {
            return .success(Data((toolDir + "\n").utf8))
        }
        if arguments == ["tool", "dir", "--bin"] {
            return .success(Data((binDir + "\n").utf8))
        }
        return .failure(.spawnFailure)
    }
}

private struct UvFixture {
    let root: URL
    let toolDir: URL
    let binDir: URL
    let envRoot: URL
    let script: URL
    let shim: URL
    let managerDir: URL
    let manager: URL
    let distInfo: URL

    init(_ label: String, receiptOverride: String? = nil) throws {
        root = try uvScratchRoot(label)
        toolDir = root.appendingPathComponent("tools", isDirectory: true)
        binDir = root.appendingPathComponent("bin", isDirectory: true)
        managerDir = root.appendingPathComponent("manager-bin", isDirectory: true)
        envRoot = toolDir.appendingPathComponent("aider-chat", isDirectory: true)
        script = envRoot.appendingPathComponent("bin/aider", isDirectory: false)
        shim = binDir.appendingPathComponent("aider", isDirectory: false)
        manager = managerDir.appendingPathComponent("uv", isDirectory: false)
        distInfo = envRoot.appendingPathComponent(
            "lib/python3.15/site-packages/aider_chat-0.86.2.dist-info", isDirectory: true
        )
        try FileManager.default.createDirectory(at: envRoot.appendingPathComponent("bin"),
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: distInfo, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: managerDir, withIntermediateDirectories: true)
        try uvWriteExecutable(manager, contents: "#!/bin/sh\nexit 0\n")
        try uvWriteExecutable(
            envRoot.appendingPathComponent("bin/python"),
            contents: "#!/bin/sh\nexit 0\n"
        )
        let scriptData = Data("#!/\(envRoot.path)/bin/python\nprint('aider')\n".utf8)
        try Data(scriptData).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                              ofItemAtPath: script.path)
        try FileManager.default.createSymbolicLink(
            atPath: shim.path, withDestinationPath: script.path
        )
        try uvWrite(envRoot.appendingPathComponent("pyvenv.cfg"), """
        home = /opt/homebrew/opt/python@3.15/bin
        implementation = CPython
        uv = 0.13.10
        version_info = 3.15.2
        include-system-site-packages = false

        """)
        let hash = uvBase64URLSHA256(scriptData)
        try uvWrite(distInfo.appendingPathComponent("RECORD"), """
        ../../../bin/aider,sha256=\(hash),\(scriptData.count)
        aider_chat-0.86.2.dist-info/RECORD,,

        """)
        try uvWrite(distInfo.appendingPathComponent("INSTALLER"), "uv\n")
        try uvWrite(distInfo.appendingPathComponent("METADATA"), """
        Metadata-Version: 2.1
        Name: aider-chat
        Version: 0.86.2
        Requires-Python: >=3.10

        """)
        try uvWrite(distInfo.appendingPathComponent("entry_points.txt"), """
        [console_scripts]
        aider = aider_chat.cli:main

        """)
        let receipt = receiptOverride ?? Self.defaultReceipt(
            shim: shim.path, envRoot: envRoot.path
        )
        try uvWrite(envRoot.appendingPathComponent("uv-receipt.toml"), receipt)
    }

    static func defaultReceipt(shim: String, envRoot: String) -> String {
        """
        [tool]
        requirements = [{ name = "aider-chat" }]
        python = "\(envRoot)/bin/python"
        entrypoints = [
            { name = "aider", install-path = "\(shim)", from = "aider-chat" },
        ]

        [tool.options]
        index = [{ url = "http://127.0.0.1:9/simple", explicit = false, default = true, format = "simple", authenticate = "auto" }]

        """
    }

    var definition: DetectorDefinition {
        get throws {
            try DetectorDefinition(
                id: "aider-id",
                displayName: "Aider",
                executableName: "aider",
                extraSearchRoots: [],
                fixture: nil,
                category: .aiCodingTool,
                packages: [try DeclaredPackage(manager: .uvTool, name: "aider-chat")],
                informationURL: nil,
                uninstallInstructionsURL: nil,
                versionQuery: .standard
            )
        }
    }

    var environment: ShellEnvironment {
        let path = managerDir.path
        return ShellEnvironment(
            shellPath: "/bin/zsh",
            pathEntries: [path],
            pathJoined: path,
            raw: ["PATH": path, "HOME": root.appendingPathComponent("home").path],
            isDegraded: false
        )
    }

    func diagnostic(entryPath: String? = nil) -> ToolPathDiagnostic {
        let entry = entryPath ?? shim.path
        let target = URL(fileURLWithPath: entry).resolvingSymlinksInPath().standardizedFileURL.path
        let directory = URL(fileURLWithPath: entry).deletingLastPathComponent().path
        let candidate = PathCandidateObservation(
            origin: .path(slotIndex: 0, directoryText: directory),
            entryPath: entry,
            kind: .executableSymlink,
            canonicalTarget: target
        )
        let detected = DetectedTool(
            displayName: "Aider",
            executableName: "aider",
            state: .installedAndOnPath,
            entryPath: entry,
            resolvedPath: target,
            source: "standalone",
            version: nil
        )
        return ToolPathDiagnostic(
            detectedTool: detected,
            pathCandidates: [candidate],
            firstLiveCandidate: candidate,
            targetGroups: [PathTargetGroup(canonicalTarget: target, entryPaths: [entry], firstSlotIndex: 0)],
            repeatedPathSlotCount: 0,
            sameTargetAliasCount: 0,
            selection: .winner(candidate),
            shadowedInstallationCount: 0,
            installationVersions: []
        )
    }

    func verify(_ runner: UvScriptedRunner) async throws -> InstallationOwnershipResult {
        await InstallationOwnershipVerifier.verify(
            definition: try definition,
            diagnostic: diagnostic(),
            environment: environment,
            runner: runner,
            currentDirectory: root.path,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
    }
}

@Test func uvFixtureVerifiesExactShimReceiptAndRecord() async throws {
    let fixture = try UvFixture("positive")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let runner = UvScriptedRunner(toolDir: fixture.toolDir.path, binDir: fixture.binDir.path)
    let result = try await fixture.verify(runner)
    let installation = try #require(result.verifiedInstallation)
    #expect(installation.manager == .uvTool)
    #expect(installation.packageName == "aider-chat")
    #expect(installation.managerRoot == fixture.toolDir.resolvingSymlinksInPath().path)
    #expect(installation.installationRoot == fixture.envRoot.resolvingSymlinksInPath().path)
    #expect(installation.selection.entryPath == fixture.shim.path)
    #expect(installation.pythonEnvironment?.installedVersion == "0.86.2")
    #expect(installation.pythonEnvironment?.interpreterVersion == "3.15.2")
    #expect(installation.pythonEnvironment?.environmentKind == .uvTool)
    #expect(installation.pythonEnvironment?.installer == "uv")
    #expect(installation.pythonEnvironment?.indexProvenance == .customIndex)
    #expect(runner.arguments == [["tool", "dir"], ["tool", "dir", "--bin"]])
    #expect(runner.lastEnvironment?["UV_NO_CACHE"] == "1")
    #expect(runner.lastEnvironment?["UV_OFFLINE"] == "1")
    #expect(runner.lastEnvironment?["UV_NO_PROGRESS"] == "1")
}

@Test func uvCrossTargetEntryIsNeverTheManagedShim() async throws {
    let fixture = try UvFixture("cross-target")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let alias = fixture.binDir.appendingPathComponent("aider-alias")
    try FileManager.default.createSymbolicLink(atPath: alias.path, withDestinationPath: fixture.script.path)
    let runner = UvScriptedRunner(toolDir: fixture.toolDir.path, binDir: fixture.binDir.path)
    let result = await InstallationOwnershipVerifier.verify(
        definition: try fixture.definition,
        diagnostic: fixture.diagnostic(entryPath: alias.path),
        environment: fixture.environment,
        runner: runner,
        currentDirectory: fixture.root.path,
        now: { Date(timeIntervalSince1970: 1_800_000_000) }
    )
    #expect(result.unknownReason == .managerEntryMismatch)
}

@Test func uvMissingOrSymlinkedReceiptNeverFallsBackToAnotherManager() async throws {
    let fixture = try UvFixture("missing-receipt")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let runner = UvScriptedRunner(toolDir: fixture.toolDir.path, binDir: fixture.binDir.path)
    try FileManager.default.removeItem(at: fixture.envRoot.appendingPathComponent("uv-receipt.toml"))
    let result = try await fixture.verify(runner)
    #expect(result.unknownReason == .manifestMissing)

    let fixture2 = try UvFixture("symlink-receipt")
    defer { try? FileManager.default.removeItem(at: fixture2.root) }
    let receipt = fixture2.envRoot.appendingPathComponent("uv-receipt.toml")
    let target = fixture2.root.appendingPathComponent("outside-receipt.toml")
    try uvWrite(target, UvFixture.defaultReceipt(shim: fixture2.shim.path, envRoot: fixture2.envRoot.path))
    try FileManager.default.removeItem(at: receipt)
    try FileManager.default.createSymbolicLink(atPath: receipt.path, withDestinationPath: target.path)
    let result2 = try await fixture2.verify(UvScriptedRunner(
        toolDir: fixture2.toolDir.path, binDir: fixture2.binDir.path
    ))
    #expect(result2.unknownReason == .manifestUnreadable)
}

@Test func uvMalformedReceiptAndWrongEntrypointAreRefused() async throws {
    let malformed = try UvFixture("malformed", receiptOverride: """
    [tool]
    requirements = [{ name = "aider-chat" }]
    requirements = [{ name = "aider-chat" }]

    """)
    defer { try? FileManager.default.removeItem(at: malformed.root) }
    let malformedResult = try await malformed.verify(UvScriptedRunner(
        toolDir: malformed.toolDir.path, binDir: malformed.binDir.path
    ))
    #expect(malformedResult.unknownReason == .manifestInvalid)

    let wrongFrom = try UvFixture("wrong-from")
    defer { try? FileManager.default.removeItem(at: wrongFrom.root) }
    let wrongReceipt = UvFixture.defaultReceipt(
        shim: wrongFrom.shim.path, envRoot: wrongFrom.envRoot.path
    ).replacingOccurrences(of: "from = \"aider-chat\"", with: "from = \"other-package\"")
    try uvWrite(wrongFrom.envRoot.appendingPathComponent("uv-receipt.toml"), wrongReceipt)
    let wrongResult = try await wrongFrom.verify(UvScriptedRunner(
        toolDir: wrongFrom.toolDir.path, binDir: wrongFrom.binDir.path
    ))
    #expect(wrongResult.unknownReason == .manifestExecutableMismatch)
}

@Test func uvRecordMustOwnTheExactScriptAndHash() async throws {
    let fixture = try UvFixture("bad-record")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try uvWrite(fixture.distInfo.appendingPathComponent("RECORD"), """
    ../../../bin/aider,sha256=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA,1
    aider_chat-0.86.2.dist-info/RECORD,,

    """)
    let result = try await fixture.verify(UvScriptedRunner(
        toolDir: fixture.toolDir.path, binDir: fixture.binDir.path
    ))
    #expect(result.unknownReason == .manifestExecutableMismatch)
}

@Test func uvFinalRevalidationObservesReceiptDrift() async throws {
    let fixture = try UvFixture("drift")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let runner = UvScriptedRunner(toolDir: fixture.toolDir.path, binDir: fixture.binDir.path)
    let result = try await PythonOwnershipProbeTestHooks.$onBeforeFinalRevalidation.withValue({
        try? uvWrite(fixture.envRoot.appendingPathComponent("uv-receipt.toml"), "not toml [")
    }) {
        try await fixture.verify(runner)
    }
    #expect(result.unknownReason == .proofChanged)
}

@Test func uvAbsentManagerAndMalformedRootOutputAreTyped() async throws {
    let fixture = try UvFixture("no-manager")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try FileManager.default.removeItem(at: fixture.manager)
    let noManager = try await fixture.verify(UvScriptedRunner(
        toolDir: fixture.toolDir.path, binDir: fixture.binDir.path
    ))
    #expect(noManager.unknownReason == .managerUnavailable)

    let fixture2 = try UvFixture("bad-root-output")
    defer { try? FileManager.default.removeItem(at: fixture2.root) }
    let runner = UvScriptedRunner(
        toolDir: "relative/tools", binDir: fixture2.binDir.path
    )
    let bad = try await fixture2.verify(runner)
    #expect(bad.unknownReason == .invalidManagerOutput)
}


@Test func uvCompetingDistInfoAndNegativeDirectURLCannotBeAdoptedAtRevalidation() async throws {
    let fixture = try UvFixture("competing-dist-info")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let runner = UvScriptedRunner(toolDir: fixture.toolDir.path, binDir: fixture.binDir.path)
    let result = try await PythonOwnershipProbeTestHooks.$onBeforeFinalRevalidation.withValue({
        let competitor = fixture.envRoot.appendingPathComponent(
            "lib/python3.15/site-packages/aider_chat-9.9.9.dist-info",
            isDirectory: true
        )
        try? FileManager.default.createDirectory(at: competitor, withIntermediateDirectories: true)
    }) {
        try await fixture.verify(runner)
    }
    #expect(result.unknownReason == .proofChanged)

    let direct = try UvFixture("negative-direct-url")
    defer { try? FileManager.default.removeItem(at: direct.root) }
    let directResult = try await PythonOwnershipProbeTestHooks.$onBeforeFinalRevalidation.withValue({
        try? uvWrite(direct.distInfo.appendingPathComponent("direct_url.json"),
                     #"{"url":"file:///tmp/example.whl"}"#)
    }) {
        try await direct.verify(UvScriptedRunner(
            toolDir: direct.toolDir.path, binDir: direct.binDir.path
        ))
    }
    #expect(directResult.unknownReason == .proofChanged)
}

@Test func sharedEnumerationStopsAtTheEntryCap() throws {
    let root = try uvScratchRoot("entry-cap")
    defer { try? FileManager.default.removeItem(at: root) }
    let directory = root.appendingPathComponent("entries", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for index in 0...256 {
        try Data().write(to: directory.appendingPathComponent("entry-\(index)"))
    }
    let identity = try #require(PythonProofSupport.observePlainDirectory(directory.path))
    #expect(PythonProofSupport.listNames(in: identity, maximumEntries: 256) == nil)
    #expect(PythonProofSupport.listNames(in: identity, maximumEntries: 257)?.count == 257)
}


@Test func uvNoIndexAndConflictingIndexOptionsRemainUnknownProvenance() async throws {
    let noIndex = try UvFixture("no-index")
    defer { try? FileManager.default.removeItem(at: noIndex.root) }
    let noIndexReceipt = """
    [tool]
    requirements = [{ name = "aider-chat" }]
    entrypoints = [
        { name = "aider", install-path = "\(noIndex.shim.path)", from = "aider-chat" },
    ]

    """
    try uvWrite(noIndex.envRoot.appendingPathComponent("uv-receipt.toml"), noIndexReceipt)
    let noIndexResult = try await noIndex.verify(UvScriptedRunner(
        toolDir: noIndex.toolDir.path, binDir: noIndex.binDir.path
    ))
    #expect(noIndexResult.verifiedInstallation?.pythonEnvironment?.indexProvenance == .unknown)

    let conflicting = try UvFixture("conflicting-index")
    defer { try? FileManager.default.removeItem(at: conflicting.root) }
    let conflictingReceipt = """
    [tool]
    requirements = [{ name = "aider-chat" }]
    entrypoints = [
        { name = "aider", install-path = "\(conflicting.shim.path)", from = "aider-chat" },
    ]

    [tool.options]
    index = [
        { url = "https://pypi.org/simple", explicit = false, default = true },
        { url = "https://example.invalid/simple", explicit = false, default = true },
    ]

    """
    try uvWrite(conflicting.envRoot.appendingPathComponent("uv-receipt.toml"), conflictingReceipt)
    let conflictingResult = try await conflicting.verify(UvScriptedRunner(
        toolDir: conflicting.toolDir.path, binDir: conflicting.binDir.path
    ))
    #expect(conflictingResult.verifiedInstallation?.pythonEnvironment?.indexProvenance == .unknown)
}


@Test func uvAmbiguousEntrypointsAreRefused() async throws {
    let fixture = try UvFixture("ambiguous-entrypoints")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let receipt = """
    [tool]
    requirements = [{ name = "aider-chat" }]
    entrypoints = [
        { name = "aider", install-path = "\(fixture.shim.path)", from = "aider-chat" },
        { name = "aider", install-path = "\(fixture.shim.path)", from = "aider-chat" },
    ]

    """
    try uvWrite(fixture.envRoot.appendingPathComponent("uv-receipt.toml"), receipt)
    let result = try await fixture.verify(UvScriptedRunner(
        toolDir: fixture.toolDir.path, binDir: fixture.binDir.path
    ))
    #expect(result.unknownReason == .ambiguousOwnership)
}


@Test func uvManagerChangeBetweenRootQueriesStopsFurtherQueries() async throws {
    let fixture = try UvFixture("manager-between")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let manager = fixture.manager
    let runner = UvScriptedRunner(
        toolDir: fixture.toolDir.path,
        binDir: fixture.binDir.path,
        customHandler: { arguments in
            if arguments == ["tool", "dir"] {
                try? Data("#!/bin/sh\nexit 0\n".utf8).write(to: manager)
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o755], ofItemAtPath: manager.path
                )
                return .success(Data((fixture.toolDir.path + "\n").utf8))
            }
            return .success(Data((fixture.binDir.path + "\n").utf8))
        }
    )
    let result = try await fixture.verify(runner)
    #expect(result.unknownReason == .managerChanged)
    #expect(runner.arguments == [["tool", "dir"]])
}

@Test func uvNoPythonLayoutEvidenceDoesNotQueryUv() async throws {
    let fixture = try UvFixture("no-layout")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try? FileManager.default.removeItem(at: fixture.envRoot.appendingPathComponent("pyvenv.cfg"))
    try? FileManager.default.removeItem(at: fixture.envRoot.appendingPathComponent("lib"))
    try? FileManager.default.removeItem(at: fixture.envRoot.appendingPathComponent("uv-receipt.toml"))
    let definition = try DetectorDefinition(
        id: "aider-id", displayName: "Aider", executableName: "aider",
        extraSearchRoots: [], fixture: nil, category: .aiCodingTool,
        packages: [
            try DeclaredPackage(manager: .uvTool, name: "aider-chat"),
            try DeclaredPackage(manager: .pip, name: "aider-chat"),
        ],
        informationURL: nil, uninstallInstructionsURL: nil, versionQuery: .standard
    )
    let runner = UvScriptedRunner(toolDir: fixture.toolDir.path, binDir: fixture.binDir.path)
    let result = await InstallationOwnershipVerifier.verify(
        definition: definition,
        diagnostic: fixture.diagnostic(),
        environment: fixture.environment,
        runner: runner,
        currentDirectory: fixture.root.path,
        now: { Date(timeIntervalSince1970: 1_800_000_000) }
    )
    #expect(result.unknownReason == .unsupportedInstallationLayout)
    #expect(runner.arguments.isEmpty)
}

@Test func uvExactPublicIndexEvidenceAndStrictRecordPath() async throws {
    let fixture = try UvFixture("public-index")
    let receipt = UvFixture.defaultReceipt(shim: fixture.shim.path, envRoot: fixture.envRoot.path)
        .replacingOccurrences(of: "http://127.0.0.1:9/simple", with: "https://pypi.org/simple")
    try uvWrite(fixture.envRoot.appendingPathComponent("uv-receipt.toml"), receipt)
    let result = try await fixture.verify(UvScriptedRunner(
        toolDir: fixture.toolDir.path, binDir: fixture.binDir.path
    ))
    #expect(result.verifiedInstallation?.pythonEnvironment?.indexProvenance == .publicPyPI)

    let strict = try UvFixture("strict-record")
    defer { try? FileManager.default.removeItem(at: strict.root) }
    try uvWrite(strict.distInfo.appendingPathComponent("RECORD"), """
    ../bin/aider,sha256=\(uvBase64URLSHA256(Data("#!/x\n".utf8))),4
    aider_chat-0.86.2.dist-info/RECORD,,

    """)
    let strictResult = try await strict.verify(UvScriptedRunner(
        toolDir: strict.toolDir.path, binDir: strict.binDir.path
    ))
    #expect(strictResult.unknownReason == .executableNotDeclared)
}

@Test func uvReceiptSummaryOmitsUnsafeSpecifierText() async throws {
    let fixture = try UvFixture("unsafe-specifier")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let receipt = """
    [tool]
    requirements = [{ name = "aider-chat", specifier = ";token=secret" }]
    entrypoints = [
        { name = "aider", install-path = "\(fixture.shim.path)", from = "aider-chat" },
    ]

    """
    try uvWrite(fixture.envRoot.appendingPathComponent("uv-receipt.toml"), receipt)
    let result = try await fixture.verify(UvScriptedRunner(
        toolDir: fixture.toolDir.path, binDir: fixture.binDir.path
    ))
    #expect(result.verifiedInstallation?.pythonEnvironment?.receiptConstraints == ["aider-chat"])
}


@Test func uvManagerResolutionUsesCurrentDirectoryForEmptyPathEntry() async throws {
    let fixture = try UvFixture("current-directory")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let localManager = fixture.root.appendingPathComponent("uv")
    try uvWriteExecutable(localManager, contents: "#!/bin/sh\nexit 0\n")
    let environment = ShellEnvironment(
        shellPath: "/bin/zsh",
        pathEntries: [""],
        pathJoined: "",
        raw: ["PATH": "", "HOME": fixture.root.appendingPathComponent("home").path],
        isDegraded: false
    )
    let result = await InstallationOwnershipVerifier.verify(
        definition: try fixture.definition,
        diagnostic: fixture.diagnostic(),
        environment: environment,
        runner: UvScriptedRunner(toolDir: fixture.toolDir.path, binDir: fixture.binDir.path),
        currentDirectory: fixture.root.path,
        now: { Date(timeIntervalSince1970: 1_800_000_000) }
    )
    #expect(result.verifiedInstallation?.manager == .uvTool)
}

@Test func uvReceiptRejectsUnexactHeadersBoundariesAndNonBooleanOptions() async throws {
    let header = try UvFixture("bad-header", receiptOverride: """
    [tool]
    requirements = [{ name = "aider-chat" }]
    entrypoints = [{ name = "aider", install-path = "PLACEHOLDER", from = "aider-chat" }]

    [tool.extra]
    value = "x"

    """)
    defer { try? FileManager.default.removeItem(at: header.root) }
    // The placeholder install-path is intentionally irrelevant: the exact-header rejection is
    // reached before a successful entrypoint proof.
    let headerResult = try await header.verify(UvScriptedRunner(
        toolDir: header.toolDir.path, binDir: header.binDir.path
    ))
    #expect(headerResult.unknownReason == .manifestInvalid)

    let boundary = try UvFixture("bad-boundary")
    defer { try? FileManager.default.removeItem(at: boundary.root) }
    let boundaryReceipt = """
    [tool]
    requirements = [{ name = "aider-chat" }] entrypoints = []

    """
    try uvWrite(boundary.envRoot.appendingPathComponent("uv-receipt.toml"), boundaryReceipt)
    let boundaryResult = try await boundary.verify(UvScriptedRunner(
        toolDir: boundary.toolDir.path, binDir: boundary.binDir.path
    ))
    #expect(boundaryResult.unknownReason == .manifestInvalid)

    let duplicateSection = try UvFixture("duplicate-section")
    defer { try? FileManager.default.removeItem(at: duplicateSection.root) }
    try uvWrite(duplicateSection.envRoot.appendingPathComponent("uv-receipt.toml"), """
    [tool]
    requirements = [{ name = "aider-chat" }]
    [tool]
    requirements = [{ name = "aider-chat" }]
    """)
    let duplicateResult = try await duplicateSection.verify(UvScriptedRunner(
        toolDir: duplicateSection.toolDir.path, binDir: duplicateSection.binDir.path
    ))
    #expect(duplicateResult.unknownReason == .manifestInvalid)
}


@Test func uvNoIndexDirectReceiptIsNonPublicAndStalePythonIsIgnored() async throws {
    let fixture = try UvFixture("no-index-direct")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let receipt = """
    [tool]
    requirements = [{ name = "aider-chat", path = "\(fixture.root.path)/aider.whl" }]
    python = "/opt/homebrew/opt/python@3.15/bin/python3.15"
    entrypoints = [
        { name = "aider", install-path = "\(fixture.shim.path)", from = "aider-chat" },
    ]

    [tool.options]
    no-index = true

    """
    try uvWrite(fixture.envRoot.appendingPathComponent("uv-receipt.toml"), receipt)
    let result = try await fixture.verify(UvScriptedRunner(
        toolDir: fixture.toolDir.path, binDir: fixture.binDir.path
    ))
    #expect(result.verifiedInstallation?.pythonEnvironment?.indexProvenance == .nonRegistrySource)
    #expect(result.verifiedInstallation?.pythonEnvironment?.interpreterVersion == "3.15.2")
    #expect(result.verifiedInstallation?.pythonEnvironment?.receiptConstraints == ["aider-chat"])
}

@Test func uvPinAndExtrasReceiptSummariesAreValidatedAndDisplayedSafely() async throws {
    let fixture = try UvFixture("pin-extras")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let receipt = """
    [tool]
    requirements = [
        { name = "aider-chat", specifier = "==0.85.0" },
        { name = "m14-sentinel" },
    ]
    entrypoints = [
        { name = "aider", install-path = "\(fixture.shim.path)", from = "aider-chat" },
    ]

    """
    try uvWrite(fixture.envRoot.appendingPathComponent("uv-receipt.toml"), receipt)
    let result = try await fixture.verify(UvScriptedRunner(
        toolDir: fixture.toolDir.path, binDir: fixture.binDir.path
    ))
    #expect(result.verifiedInstallation?.pythonEnvironment?.receiptConstraints
        == ["aider-chat==0.85.0", "m14-sentinel"])
    #expect(result.verifiedInstallation?.pythonEnvironment?.extras == ["m14-sentinel"])
}
