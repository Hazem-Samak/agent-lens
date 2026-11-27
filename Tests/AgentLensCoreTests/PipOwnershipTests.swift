// PipOwnershipTests — M14-B pip/venv/pipx/prefix/user read-only layouts from Phase A.
//
// Synthetic scratch layouts only. The probe is filesystem-local; no pip, interpreter, pipx or
// shell command is executed.

import CryptoKit
import Foundation
import Testing
@testable import AgentLensCore

private func pipScratchRoot(_ label: String) throws -> URL {
    let environment = ProcessInfo.processInfo.environment
    guard let basePath = [environment["AGENT_LENS_TEST_SCRATCH"], environment["TMPDIR"]]
        .compactMap({ $0 })
        .first(where: { !$0.isEmpty })
    else {
        throw NSError(
            domain: "AgentLensPipOwnershipTests", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "no approved test scratch root"]
        )
    }
    let base = URL(fileURLWithPath: basePath, isDirectory: true).resolvingSymlinksInPath()
    let root = base.appendingPathComponent(
        "agentlens-m14b-pip-\(label)-\(UUID().uuidString)", isDirectory: true
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root.resolvingSymlinksInPath()
}

private func pipWriteExecutable(_ url: URL, _ contents: String) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try Data(contents.utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
}

private func pipWrite(_ url: URL, _ contents: String) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try Data(contents.utf8).write(to: url)
}

private func pipBase64URLSHA256(_ data: Data) -> String {
    Data(SHA256.hash(data: data))
        .base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

private final class PipNoopRunner: UpdateCommandRunner, @unchecked Sendable {
    func run(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval
    ) async -> CommandOutcome {
        .failure(.spawnFailure)
    }
}

private enum PipFixtureKind {
    case venv
    case pipx
    case prefix
    case user
    case externallyManaged
    case strayMarkerPrefix
    case otherInstaller
    case missingRecord
    case badPipxMetadata
    case wrongPipxPath
}

private struct PipFixture {
    let root: URL
    let home: URL
    let envRoot: URL
    let script: URL
    let baseInterpreter: URL
    let sitePackages: URL
    let distInfo: URL
    let kind: PipFixtureKind

    init(_ label: String, kind: PipFixtureKind = .venv,
         wrapperSuffix: String = "", pipArgs: [String] = []) throws {
        self.kind = kind
        root = try pipScratchRoot(label)
        home = root.appendingPathComponent("home", isDirectory: true)
        baseInterpreter = root.appendingPathComponent("base/bin/python3.15", isDirectory: false)
        try pipWriteExecutable(baseInterpreter, "#!/bin/sh\nexit 0\n")
        switch kind {
        case .venv, .otherInstaller, .missingRecord:
            envRoot = root.appendingPathComponent("venv", isDirectory: true)
            script = envRoot.appendingPathComponent("bin/aider", isDirectory: false)
            sitePackages = envRoot.appendingPathComponent("lib/python3.15/site-packages", isDirectory: true)
        case .pipx, .badPipxMetadata, .wrongPipxPath:
            envRoot = root.appendingPathComponent("pipx/venvs/aider-chat", isDirectory: true)
            script = envRoot.appendingPathComponent("bin/aider", isDirectory: false)
            sitePackages = envRoot.appendingPathComponent("lib/python3.15/site-packages", isDirectory: true)
        case .prefix, .externallyManaged, .strayMarkerPrefix:
            envRoot = root.appendingPathComponent("prefix", isDirectory: true)
            script = envRoot.appendingPathComponent("bin/aider", isDirectory: false)
            sitePackages = envRoot.appendingPathComponent("lib/python3.15/site-packages", isDirectory: true)
        case .user:
            envRoot = home.appendingPathComponent("Library/Python/3.15", isDirectory: true)
            script = envRoot.appendingPathComponent("bin/aider", isDirectory: false)
            sitePackages = envRoot.appendingPathComponent("lib/python/site-packages", isDirectory: true)
        }
        distInfo = sitePackages.appendingPathComponent("aider_chat-0.85.0.dist-info", isDirectory: true)
        try FileManager.default.createDirectory(
            at: script.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: distInfo, withIntermediateDirectories: true)

        let isVenv = [.venv, .otherInstaller, .missingRecord, .pipx, .badPipxMetadata, .wrongPipxPath].contains { $0 == kind }
        let interpreter: String
        if isVenv {
            let venvPython = envRoot.appendingPathComponent("bin/python", isDirectory: false)
            try pipWriteExecutable(venvPython, "#!/bin/sh\nexit 0\n")
            interpreter = venvPython.path
            try pipWrite(envRoot.appendingPathComponent("pyvenv.cfg"), """
            home = /opt/homebrew/opt/python@3.15/bin
            include-system-site-packages = false
            version_info = 3.15.2

            """)
        } else if kind == .externallyManaged {
            let systemPython = envRoot.appendingPathComponent("bin/python3.15", isDirectory: false)
            try pipWriteExecutable(systemPython, "#!/bin/sh\nexit 0\n")
            interpreter = systemPython.path
        } else {
            interpreter = baseInterpreter.path
        }
        let shebangSuffix = wrapperSuffix.isEmpty ? "" : " \(wrapperSuffix)"
        let scriptData = Data("#!/\(interpreter)\(shebangSuffix)\nprint('aider')\n".utf8)
        try Data(scriptData).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        // The RECORD represents pipx's pre-rewrite console script. For the negative `-X` case,
        // remove ` -X` only from the RECORD bytes; the normalization rule must reject it.
        let recordedText = wrapperSuffix.isEmpty
            ? String(decoding: scriptData, as: UTF8.self)
            : String(decoding: scriptData, as: UTF8.self)
                .replacingOccurrences(of: " \(wrapperSuffix)\n", with: "\n")
        let normalized = Data(recordedText.utf8)
        let hash = pipBase64URLSHA256(normalized)
        if kind == .missingRecord {
            try pipWrite(distInfo.appendingPathComponent("RECORD"), """
            aider_chat-0.85.0.dist-info/RECORD,,

            """)
        } else {
            try pipWrite(distInfo.appendingPathComponent("RECORD"), """
            ../../../bin/aider,sha256=\(hash),\(normalized.count)
            aider_chat-0.85.0.dist-info/RECORD,,

            """)
        }
        let installer = kind == .otherInstaller ? "pipx\n" : "pip\n"
        try pipWrite(distInfo.appendingPathComponent("INSTALLER"), installer)
        try pipWrite(distInfo.appendingPathComponent("METADATA"), """
        Metadata-Version: 2.1
        Name: aider-chat
        Version: 0.85.0
        Requires-Python: >=3.9

        """)
        if [.pipx, .badPipxMetadata, .wrongPipxPath].contains(where: { $0 == kind }) {
            let pipArgsText = String(
                data: try JSONSerialization.data(withJSONObject: pipArgs, options: []),
                encoding: .utf8
            ) ?? "[]"
            let appPath = kind == .wrongPipxPath
                ? root.appendingPathComponent("wrong/aider").path
                : script.path
            let metadata = """
            {
              "backend": "pip",
              "environment": "aider-chat",
              "main_package": {
                "apps": ["aider"],
                "app_paths": [{"__Path__": "\(appPath)", "__type__": "Path"}],
                "package": "aider-chat",
                "package_or_url": "aider-chat==0.85.0",
                "package_version": "0.85.0",
                "pinned": false,
                "pip_args": \(pipArgsText)
              },
              "pipx_metadata_version": "0.12",
              "python_version": "Python 3.15.2",
              "source_interpreter": {"__Path__": "\(baseInterpreter.path)", "__type__": "Path"},
              "venv_args": []
            }
            """
            try pipWrite(envRoot.appendingPathComponent("pipx_metadata.json"),
                         kind == .badPipxMetadata ? "{}" : metadata)
        }
        if kind == .externallyManaged || kind == .strayMarkerPrefix {
            try pipWrite(envRoot.appendingPathComponent("lib/python3.15/EXTERNALLY-MANAGED"),
                         "[externally-managed]\nError=test\n")
        }
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
                packages: [try DeclaredPackage(manager: .pip, name: "aider-chat")],
                informationURL: nil,
                uninstallInstructionsURL: nil,
                versionQuery: .standard
            )
        }
    }

    var environment: ShellEnvironment {
        let path = root.appendingPathComponent("empty-bin").path
        return ShellEnvironment(
            shellPath: "/bin/zsh",
            pathEntries: [path],
            pathJoined: path,
            raw: ["PATH": path, "HOME": home.path],
            isDegraded: false
        )
    }

    func diagnostic(entryPath: String? = nil, source: String = "standalone") -> ToolPathDiagnostic {
        let entry = entryPath ?? script.path
        let target = URL(fileURLWithPath: entry)
            .resolvingSymlinksInPath().standardizedFileURL.path
        let candidate = PathCandidateObservation(
            origin: .path(slotIndex: 0, directoryText: URL(fileURLWithPath: entry).deletingLastPathComponent().path),
            entryPath: entry,
            kind: .executableSymlink,
            canonicalTarget: target
        )
        let detected = DetectedTool(
            displayName: "Aider",
            executableName: "aider",
            state: .installedNotOnPath,
            entryPath: entry,
            resolvedPath: target,
            source: source,
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
            shadowedInstallationCount: nil,
            installationVersions: []
        )
    }

    func verify(
        _ runner: PipNoopRunner = PipNoopRunner(),
        entryPath: String? = nil,
        source: String = "standalone"
    ) async throws -> InstallationOwnershipResult {
        await InstallationOwnershipVerifier.verify(
            definition: try definition,
            diagnostic: diagnostic(entryPath: entryPath, source: source),
            environment: environment,
            runner: runner,
            currentDirectory: root.path,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
    }
}

private func requirePip(_ result: InstallationOwnershipResult) throws -> VerifiedInstallation {
    try #require(result.verifiedInstallation)
}

@Test func pipVenvLayoutBindsInstallerRecordAndInterpreter() async throws {
    let fixture = try PipFixture("venv")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let installation = try requirePip(await fixture.verify())
    #expect(installation.manager == .pip)
    #expect(installation.pythonEnvironment?.environmentKind == .virtualEnvironment)
    #expect(installation.pythonEnvironment?.installer == "pip")
    #expect(installation.pythonEnvironment?.installedVersion == "0.85.0")
    #expect(installation.pythonEnvironment?.interpreterVersion == "3.15.2")
    #expect(installation.managerRoot == fixture.sitePackages.resolvingSymlinksInPath().path)
    #expect(installation.installationRoot == fixture.envRoot.resolvingSymlinksInPath().path)
    #expect(installation.managerEntryPath.hasSuffix("/venv/bin/python"))
}

@Test func pipxExactShebangRewriteIsTheOnlyAcceptedRewrite() async throws {
    let fixture = try PipFixture("pipx", kind: .pipx, wrapperSuffix: "-E")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let installation = try requirePip(await fixture.verify())
    #expect(installation.pythonEnvironment?.environmentKind == .pipxEnvironment)
    #expect(installation.pythonEnvironment?.interpreterVersion == "3.15.2")

    let bad = try PipFixture("pipx-other-rewrite", kind: .pipx, wrapperSuffix: "-X")
    defer { try? FileManager.default.removeItem(at: bad.root) }
    let badResult = try await bad.verify()
    #expect(badResult.unknownReason == .manifestExecutableMismatch)
}

@Test func pipxMetadataMustValidateBackendPackageAndExposedPath() async throws {
    let invalid = try PipFixture("pipx-invalid", kind: .badPipxMetadata)
    defer { try? FileManager.default.removeItem(at: invalid.root) }
    let invalidResult = try await invalid.verify()
    #expect(invalidResult.unknownReason == .manifestInvalid)

    let wrongPath = try PipFixture("pipx-wrong-path", kind: .wrongPipxPath)
    defer { try? FileManager.default.removeItem(at: wrongPath.root) }
    let wrongPathResult = try await wrongPath.verify()
    #expect(wrongPathResult.unknownReason == .unsupportedInstallationLayout)
}

@Test func splitPrefixAndUserAreReadOnlySharedLinkage() async throws {
    let prefix = try PipFixture("prefix", kind: .prefix)
    defer { try? FileManager.default.removeItem(at: prefix.root) }
    let prefixInstallation = try requirePip(await prefix.verify())
    #expect(prefixInstallation.pythonEnvironment?.environmentKind == .sharedPrefix)
    #expect(prefixInstallation.pythonEnvironment?.interpreterVersion == nil)
    #expect(prefixInstallation.managerEntryPath.hasSuffix("/base/bin/python3.15"))
    #expect(!FileManager.default.fileExists(atPath: prefix.envRoot.appendingPathComponent("bin/python").path))

    let user = try PipFixture("user", kind: .user)
    defer { try? FileManager.default.removeItem(at: user.root) }
    let userInstallation = try requirePip(await user.verify())
    #expect(userInstallation.pythonEnvironment?.environmentKind == .sharedPrefix)
    #expect(userInstallation.pythonEnvironment?.interpreterVersion == nil)
    #expect(userInstallation.managerEntryPath.hasSuffix("/base/bin/python3.15"))
    #expect(!FileManager.default.fileExists(atPath: user.envRoot.appendingPathComponent("bin/python").path))
}

@Test func externallyManagedMarkerAndInstallerMismatchAreDistinguished() async throws {
    let external = try PipFixture("external", kind: .externallyManaged)
    defer { try? FileManager.default.removeItem(at: external.root) }
    let installation = try requirePip(await external.verify())
    #expect(installation.pythonEnvironment?.environmentKind == .externallyManagedSystem)

    let stray = try PipFixture("stray-marker-prefix", kind: .strayMarkerPrefix)
    defer { try? FileManager.default.removeItem(at: stray.root) }
    let strayInstallation = try requirePip(await stray.verify())
    #expect(strayInstallation.pythonEnvironment?.environmentKind == .sharedPrefix)

    let other = try PipFixture("other-installer", kind: .otherInstaller)
    defer { try? FileManager.default.removeItem(at: other.root) }
    let otherResult = try await other.verify()
    #expect(otherResult.unknownReason == .unsupportedSource)
}

@Test func missingRecordAndWrongExecutableAreRefused() async throws {
    let missing = try PipFixture("missing-record", kind: .missingRecord)
    defer { try? FileManager.default.removeItem(at: missing.root) }
    let missingResult = try await missing.verify()
    #expect(missingResult.unknownReason == .executableNotDeclared)
}

@Test func pipFinalRevalidationObservesRecordDrift() async throws {
    let fixture = try PipFixture("drift")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let result = try await PythonOwnershipProbeTestHooks.$onBeforeFinalRevalidation.withValue({
        try? pipWrite(fixture.distInfo.appendingPathComponent("RECORD"), "changed\n")
    }) {
        try await fixture.verify()
    }
    #expect(result.unknownReason == .proofChanged)
}


@Test func pipCompetingDistInfoAndNegativePipxMetadataAreRevalidated() async throws {
    let venv = try PipFixture("competing-dist-info")
    defer { try? FileManager.default.removeItem(at: venv.root) }
    let competing = try await PythonOwnershipProbeTestHooks.$onBeforeFinalRevalidation.withValue({
        try? FileManager.default.createDirectory(
            at: venv.sitePackages.appendingPathComponent(
                "aider_chat-9.9.9.dist-info", isDirectory: true
            ),
            withIntermediateDirectories: true
        )
    }) {
        try await venv.verify()
    }
    #expect(competing.unknownReason == .proofChanged)

    let prefix = try PipFixture("negative-pipx", kind: .prefix)
    defer { try? FileManager.default.removeItem(at: prefix.root) }
    let pipxAppeared = try await PythonOwnershipProbeTestHooks.$onBeforeFinalRevalidation.withValue({
        try? pipWrite(prefix.envRoot.appendingPathComponent("pipx_metadata.json"), "{}")
    }) {
        try await prefix.verify()
    }
    #expect(pipxAppeared.unknownReason == .proofChanged)
}


@Test func pipNoOwnershipFallbackFromUvReceiptOrUnprovedLayout() async throws {
    let fixture = try PipFixture("uv-receipt-no-fallback")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try pipWrite(fixture.envRoot.appendingPathComponent("uv-receipt.toml"), "[tool]\nrequirements=[]\n")
    let result = try await fixture.verify()
    #expect(result.unknownReason == .noMatchingPackage)

    let noSite = try PipFixture("no-site")
    defer { try? FileManager.default.removeItem(at: noSite.root) }
    try FileManager.default.removeItem(at: noSite.sitePackages)
    let noSiteResult = try await noSite.verify()
    #expect(noSiteResult.unknownReason == .unsupportedInstallationLayout)
}


private final class PipUvRootsRunner: UpdateCommandRunner, @unchecked Sendable {
    private(set) var arguments: [[String]] = []
    let toolDir: String
    let binDir: String
    init(toolDir: String, binDir: String) { self.toolDir = toolDir; self.binDir = binDir }
    func run(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval
    ) async -> CommandOutcome {
        self.arguments.append(arguments)
        if arguments == ["tool", "dir"] { return .success(Data((toolDir + "\n").utf8)) }
        if arguments == ["tool", "dir", "--bin"] { return .success(Data((binDir + "\n").utf8)) }
        return .failure(.spawnFailure)
    }
}

@Test func pipxSharedBinWithUvRootsStillRoutesToPip() async throws {
    let fixture = try PipFixture("pipx-shared-bin", kind: .pipx, wrapperSuffix: "-E")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let sharedBin = fixture.root.appendingPathComponent("shared-bin", isDirectory: true)
    let managerDir = fixture.root.appendingPathComponent("manager-bin", isDirectory: true)
    let toolDir = fixture.root.appendingPathComponent("uv-tools", isDirectory: true)
    try FileManager.default.createDirectory(at: sharedBin, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: toolDir, withIntermediateDirectories: true)
    try pipWriteExecutable(managerDir.appendingPathComponent("uv"), "#!/bin/sh\nexit 0\n")
    let shim = sharedBin.appendingPathComponent("aider")
    try FileManager.default.createSymbolicLink(atPath: shim.path, withDestinationPath: fixture.script.path)
    let environment = ShellEnvironment(
        shellPath: "/bin/zsh",
        pathEntries: [managerDir.path, sharedBin.path],
        pathJoined: [managerDir.path, sharedBin.path].joined(separator: ":"),
        raw: ["PATH": [managerDir.path, sharedBin.path].joined(separator: ":"), "HOME": fixture.home.path],
        isDegraded: false
    )
    let definition = try DetectorDefinition(
        id: "aider-id",
        displayName: "Aider",
        executableName: "aider",
        extraSearchRoots: [],
        fixture: nil,
        category: .aiCodingTool,
        packages: [
            try DeclaredPackage(manager: .uvTool, name: "aider-chat"),
            try DeclaredPackage(manager: .pip, name: "aider-chat"),
        ],
        informationURL: nil,
        uninstallInstructionsURL: nil,
        versionQuery: .standard
    )
    let runner = PipUvRootsRunner(toolDir: toolDir.path, binDir: sharedBin.path)
    let result = await InstallationOwnershipVerifier.verify(
        definition: definition,
        diagnostic: fixture.diagnostic(entryPath: shim.path),
        environment: environment,
        runner: runner,
        currentDirectory: fixture.root.path,
        now: { Date(timeIntervalSince1970: 1_800_000_000) }
    )
    let installation = try #require(result.verifiedInstallation)
    #expect(installation.manager == .pip)
    #expect(installation.pythonEnvironment?.environmentKind == .pipxEnvironment)
    #expect(runner.arguments == [["tool", "dir"], ["tool", "dir", "--bin"]])
}


@Test func brewSourceWithoutFormulaStillUsesTheDeclaredPipProof() async throws {
    let fixture = try PipFixture("brew-no-formula")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let result = try await fixture.verify(source: "brew")
    #expect(result.verifiedInstallation?.manager == .pip)
}


@Test func symlinkedSitePackagesAncestorIsUnsupported() async throws {
    let fixture = try PipFixture("symlinked-site")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let actual = fixture.root.appendingPathComponent("actual-site", isDirectory: true)
    try FileManager.default.moveItem(at: fixture.sitePackages, to: actual)
    try FileManager.default.createSymbolicLink(
        atPath: fixture.sitePackages.path, withDestinationPath: actual.path
    )
    let result = try await fixture.verify()
    #expect(result.unknownReason == .unsupportedInstallationLayout)
}


@Test func uvRootMatchWithoutReceiptReservesOwnershipAndNeverFallsBackToPip() async throws {
    let fixture = try PipFixture("uv-root-reserved")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let managerDir = fixture.root.appendingPathComponent("manager-bin", isDirectory: true)
    try pipWriteExecutable(managerDir.appendingPathComponent("uv"), "#!/bin/sh\nexit 0\n")
    let environment = ShellEnvironment(
        shellPath: "/bin/zsh",
        pathEntries: [managerDir.path],
        pathJoined: managerDir.path,
        raw: ["PATH": managerDir.path, "HOME": fixture.home.path],
        isDegraded: false
    )
    let definition = try DetectorDefinition(
        id: "aider-id",
        displayName: "Aider",
        executableName: "aider",
        extraSearchRoots: [],
        fixture: nil,
        category: .aiCodingTool,
        packages: [
            try DeclaredPackage(manager: .uvTool, name: "aider-chat"),
            try DeclaredPackage(manager: .pip, name: "aider-chat"),
        ],
        informationURL: nil,
        uninstallInstructionsURL: nil,
        versionQuery: .standard
    )
    let runner = PipUvRootsRunner(toolDir: fixture.root.path, binDir: fixture.root.path)
    let result = await InstallationOwnershipVerifier.verify(
        definition: definition,
        diagnostic: fixture.diagnostic(),
        environment: environment,
        runner: runner,
        currentDirectory: fixture.root.path,
        now: { Date(timeIntervalSince1970: 1_800_000_000) }
    )
    #expect(result.unknownReason == .manifestMissing)
}


@Test func pipFinalRevalidationObservesUvReceiptAppearance() async throws {
    let fixture = try PipFixture("uv-receipt-appears")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let result = try await PythonOwnershipProbeTestHooks.$onBeforeFinalRevalidation.withValue({
        try? pipWrite(fixture.envRoot.appendingPathComponent("uv-receipt.toml"), "[tool]\n")
    }) {
        try await fixture.verify()
    }
    #expect(result.unknownReason == .proofChanged)
}

@Test func pipxFinalRevalidationObserversExactMetadataSnapshot() async throws {
    let fixture = try PipFixture("pipx-metadata-drift", kind: .pipx, wrapperSuffix: "-E")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let result = try await PythonOwnershipProbeTestHooks.$onBeforeFinalRevalidation.withValue({
        try? pipWrite(fixture.envRoot.appendingPathComponent("pipx_metadata.json"), "{}")
    }) {
        try await fixture.verify()
    }
    #expect(result.unknownReason == .proofChanged)
}

@Test func pipOnlyStillReservesAKnownUvRoot() async throws {
    let fixture = try PipFixture("pip-only-uv-root")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let managerDir = fixture.root.appendingPathComponent("manager-bin", isDirectory: true)
    try pipWriteExecutable(managerDir.appendingPathComponent("uv"), "#!/bin/sh\nexit 0\n")
    let environment = ShellEnvironment(
        shellPath: "/bin/zsh",
        pathEntries: [managerDir.path],
        pathJoined: managerDir.path,
        raw: ["PATH": managerDir.path, "HOME": fixture.home.path],
        isDegraded: false
    )
    let definition = try DetectorDefinition(
        id: "aider-id", displayName: "Aider", executableName: "aider",
        extraSearchRoots: [], fixture: nil, category: .aiCodingTool,
        packages: [try DeclaredPackage(manager: .pip, name: "aider-chat")],
        informationURL: nil, uninstallInstructionsURL: nil, versionQuery: .standard
    )
    let runner = PipUvRootsRunner(toolDir: fixture.root.path, binDir: fixture.root.path)
    let result = await InstallationOwnershipVerifier.verify(
        definition: definition,
        diagnostic: fixture.diagnostic(),
        environment: environment,
        runner: runner,
        currentDirectory: fixture.root.path,
        now: { Date(timeIntervalSince1970: 1_800_000_000) }
    )
    #expect(result.unknownReason == .manifestMissing)
}

@Test func pipxProvenanceRequiresOneUnambiguousIndex() async throws {
    let publicFixture = try PipFixture(
        "pipx-public", kind: .pipx, wrapperSuffix: "-E",
        pipArgs: ["--index-url", "https://pypi.org/simple"]
    )
    defer { try? FileManager.default.removeItem(at: publicFixture.root) }
    let publicResult = try await publicFixture.verify()
    #expect(publicResult.verifiedInstallation?.pythonEnvironment?.indexProvenance == .unknown)

    let noIndex = try PipFixture(
        "pipx-no-index", kind: .pipx, wrapperSuffix: "-E",
        pipArgs: ["--no-index", "--find-links", "/tmp"]
    )
    defer { try? FileManager.default.removeItem(at: noIndex.root) }
    let noIndexResult = try await noIndex.verify()
    #expect(noIndexResult.verifiedInstallation?.pythonEnvironment?.indexProvenance == .unknown)

    let duplicates = try PipFixture(
        "pipx-duplicate-index", kind: .pipx, wrapperSuffix: "-E",
        pipArgs: [
            "--index-url", "https://pypi.org/simple",
            "--index-url", "https://pypi.org/simple",
        ]
    )
    defer { try? FileManager.default.removeItem(at: duplicates.root) }
    let duplicatesResult = try await duplicates.verify()
    #expect(duplicatesResult.verifiedInstallation?.pythonEnvironment?.indexProvenance == .unknown)
}


@Test func metadataHeaderTextAfterBlankLineCannotOverrideHeaders() async throws {
    let fixture = try PipFixture("metadata-body")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try pipWrite(fixture.distInfo.appendingPathComponent("METADATA"), """
    Metadata-Version: 2.1
    Name: aider-chat
    Version: 0.85.0
    Requires-Python: >=3.9

    Name: evil
    Version: 9.9.9
    Requires-Python: >=3.99
    """)
    let result = try await fixture.verify()
    #expect(result.verifiedInstallation?.pythonEnvironment?.installedVersion == "0.85.0")
    #expect(result.verifiedInstallation?.pythonEnvironment?.requiresPython == ">=3.9")
}
