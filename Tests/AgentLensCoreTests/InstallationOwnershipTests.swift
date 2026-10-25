// InstallationOwnershipTests — M9-B explicit, read-only ownership verification.
//
// Every fixture is synthetic and test-owned: scratch prefixes, fake manager executables, declarative
// manifests and scripted runner answers. No real npm or brew is invoked. The tests assert the typed
// proof and the neutral reason, plus manager-call counts and suppression after identity changes.

import Foundation
import Testing
@testable import AgentLensCore

// MARK: Shared scratch and fixture helpers

private func ownershipScratchRoot(_ label: String) throws -> URL {
    let environment = ProcessInfo.processInfo.environment
    guard let basePath = [environment["AGENT_LENS_TEST_SCRATCH"], environment["TMPDIR"]]
        .compactMap({ $0 })
        .first(where: { !$0.isEmpty })
    else {
        throw NSError(
            domain: "AgentLensOwnershipTests", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "no approved test scratch root is available"]
        )
    }
    let base = URL(fileURLWithPath: basePath, isDirectory: true).resolvingSymlinksInPath()
    let root = base.appendingPathComponent(
        "agentlens-m9b-\(label)-\(UUID().uuidString)", isDirectory: true
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root.resolvingSymlinksInPath()
}

private func writeOwnershipExecutable(_ url: URL, version: String = "1.0.0") throws {
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

private func ownershipEnvironment(pathEntries: [String]) -> ShellEnvironment {
    let joined = pathEntries.joined(separator: ":")
    return ShellEnvironment(
        shellPath: "/bin/zsh",
        pathEntries: pathEntries,
        pathJoined: joined,
        raw: ["PATH": joined, "HOME": "/synthetic/home"],
        isDegraded: false
    )
}

private func ownershipDefinition(
    executableName: String = "codex",
    packages: [(PackageManager, String)] = []
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

private func ownershipDiagnostic(
    executableName: String,
    entryPath: String,
    source: String,
    state: InstallState = .installedAndOnPath
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
        selection: .winner(candidate),
        shadowedInstallationCount: 0,
        installationVersions: []
    )
}

private func absentDiagnostic(source: String = "npm") -> ToolPathDiagnostic {
    ToolPathDiagnostic(
        detectedTool: DetectedTool(
            displayName: "Codex",
            executableName: "codex",
            state: .notInstalled,
            entryPath: nil,
            resolvedPath: nil,
            source: "–",
            version: nil
        ),
        pathCandidates: [],
        firstLiveCandidate: nil,
        targetGroups: [],
        repeatedPathSlotCount: 0,
        sameTargetAliasCount: 0,
        selection: .notInstalled,
        shadowedInstallationCount: nil,
        installationVersions: []
    )
}

private func inconsistentDiagnostic() -> ToolPathDiagnostic {
    ToolPathDiagnostic(
        detectedTool: DetectedTool(
            displayName: "Codex",
            executableName: "codex",
            state: .installedAndOnPath,
            entryPath: "/synthetic/missing",
            resolvedPath: nil,
            source: "npm",
            version: nil
        ),
        pathCandidates: [],
        firstLiveCandidate: nil,
        targetGroups: [],
        repeatedPathSlotCount: 1,
        sameTargetAliasCount: 0,
        selection: .inconsistent("repeated PATH slot"),
        shadowedInstallationCount: nil,
        installationVersions: []
    )
}

private func fixedOwnershipClock(
    _ value: Date = Date(timeIntervalSince1970: 1_800_000_000)
) -> @Sendable () -> Date {
    { value }
}

// MARK: npm fixture

private struct NpmOwnershipFixture {
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
    var aliasPath: String { alias.path }
    var targetPath: String { target.path }

    init(
        _ label: String,
        packageName: String = "@openai/codex",
        executableName: String = "codex",
        manifestName: String? = nil,
        binValue: [String: Any]? = nil,
        stringBin: String? = nil
    ) throws {
        root = try ownershipScratchRoot(label)
        prefix = root.appendingPathComponent("prefix", isDirectory: true)
        globalRoot = prefix.appendingPathComponent("lib/node_modules", isDirectory: true)
        managerDirectory = root.appendingPathComponent("manager-bin", isDirectory: true)
        let aliasDirectory = root.appendingPathComponent("alias-bin", isDirectory: true)
        try FileManager.default.createDirectory(
            at: managerDirectory, withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: aliasDirectory, withIntermediateDirectories: true
        )
        try writeOwnershipExecutable(managerDirectory.appendingPathComponent("npm"))

        var packageURL = globalRoot
        for component in packageName.split(separator: "/", omittingEmptySubsequences: false) {
            packageURL.appendPathComponent(String(component), isDirectory: true)
        }
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        target = packageURL.appendingPathComponent("bin/codex.js")
        try writeOwnershipExecutable(target)

        let resolvedName = manifestName ?? packageName
        let manifest: [String: Any] = [
            "name": resolvedName,
            "version": "1.0.0",
            "bin": binValue ?? (stringBin.map { $0 as Any } ?? [executableName: "bin/codex.js"]),
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        try data.write(to: packageURL.appendingPathComponent("package.json"))

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
        environment = ownershipEnvironment(pathEntries: [managerDirectory.path, aliasDirectory.path])
    }

    func packageRoot(_ name: String) -> URL {
        var url = globalRoot
        for component in name.split(separator: "/", omittingEmptySubsequences: false) {
            url.appendPathComponent(String(component), isDirectory: true)
        }
        return url
    }

    /// Adds a second declared npm package that binds the same executable name to the same selected
    /// target, so both inspected candidates produce a complete match.
    @discardableResult
    func addMatchingPackage(_ name: String, executableName: String = "codex") throws -> URL {
        let packageURL = packageRoot(name)
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        let binDirectory = packageURL.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        let binTarget = binDirectory.appendingPathComponent("codex.js")
        if !FileManager.default.fileExists(atPath: binTarget.path) {
            try FileManager.default.createSymbolicLink(
                atPath: binTarget.path, withDestinationPath: target.path
            )
        }
        let manifest: [String: Any] = [
            "name": name,
            "version": "1.0.0",
            "bin": [executableName: "bin/codex.js"],
        ]
        try JSONSerialization.data(withJSONObject: manifest)
            .write(to: packageURL.appendingPathComponent("package.json"))
        return packageURL
    }
}

private func npmScript(
    prefix: String,
    root: String,
    extra: @escaping @Sendable ([String]) -> CommandOutcome? = { _ in nil }
) -> @Sendable (String, [String]) -> CommandOutcome {
    { _, arguments in
        if let outcome = extra(arguments) { return outcome }
        switch arguments {
        case ["prefix", "--global"]:
            return .success(Data((prefix + "\n").utf8))
        case ["root", "--global"]:
            return .success(Data((root + "\n").utf8))
        default:
            Issue.record("unexpected npm arguments: \(arguments)")
            return .failure(.spawnFailure)
        }
    }
}

// MARK: npm positive proof

@Test func npmObjectBinAndExternalSameTargetAliasProveTheDeclaredPackage() async throws {
    let fixture = try NpmOwnershipFixture("npm-positive")
    let definition = try ownershipDefinition(packages: [(.npm, "@openai/codex")])
    let diagnostic = ownershipDiagnostic(
        executableName: "codex", entryPath: fixture.aliasPath, source: "npm"
    )
    let runner = ScriptedRunner(handler: npmScript(prefix: fixture.prefixText, root: fixture.rootText))
    let observedAt = Date(timeIntervalSince1970: 1_800_000_123)

    let result = await InstallationOwnershipVerifier.verify(
        definition: definition,
        diagnostic: diagnostic,
        environment: fixture.environment,
        runner: runner,
        currentDirectory: fixture.root.path,
        now: fixedOwnershipClock(observedAt)
    )

    #expect(result.registryID == "codex-id")
    #expect(result.observedSelectedEntry == fixture.aliasPath)
    #expect(result.observedSelectedTarget == fixture.targetPath)
    #expect(result.observedAt == observedAt)
    let installation = try #require(result.verifiedInstallation)
    #expect(result.unknownReason == nil)
    #expect(installation.manager == .npm)
    #expect(installation.packageName == "@openai/codex")
    #expect(installation.managerEntryPath == fixture.managerPath)
    #expect(installation.managerRoot == fixture.prefix.path)
    #expect(installation.installationRoot == fixture.packageRoot("@openai/codex")
        .resolvingSymlinksInPath().path)
    // The selected PATH alias is outside the prefix but still resolves to the proven manager bin.
    #expect(installation.selection.entryPath == fixture.aliasPath)
    #expect(installation.selection.canonicalTarget == fixture.targetPath)
    #expect(installation.managerTarget == fixture.managerPath)
    #expect(runner.calls == [["prefix", "--global"], ["root", "--global"]])
    #expect(runner.environments.first == fixture.environment.raw)
}

@Test func npmStringBinShorthandUsesThePackageBasename() async throws {
    let fixture = try NpmOwnershipFixture(
        "npm-string-bin",
        packageName: "codex-ai",
        executableName: "codex-ai",
        stringBin: "bin/codex.js"
    )
    let definition = try ownershipDefinition(
        executableName: "codex-ai", packages: [(.npm, "codex-ai")]
    )
    let diagnostic = ownershipDiagnostic(
        executableName: "codex-ai", entryPath: fixture.aliasPath, source: "npm"
    )
    let runner = ScriptedRunner(handler: npmScript(prefix: fixture.prefixText, root: fixture.rootText))

    let result = await InstallationOwnershipVerifier.verify(
        definition: definition,
        diagnostic: diagnostic,
        environment: fixture.environment,
        runner: runner,
        currentDirectory: fixture.root.path,
        now: fixedOwnershipClock()
    )

    let installation = try #require(result.verifiedInstallation)
    #expect(installation.packageName == "codex-ai")
    #expect(installation.managerRoot == fixture.prefix.path)
    #expect(runner.calls.count == 2)
}

@Test func npmDeclarationAloneDoesNotProveOwnershipWhenTheManagerBinIsMissing() async throws {
    let fixture = try NpmOwnershipFixture("npm-declaration-only")
    try FileManager.default.removeItem(
        at: fixture.prefix.appendingPathComponent("bin/codex")
    )
    let definition = try ownershipDefinition(packages: [(.npm, "@openai/codex")])
    let diagnostic = ownershipDiagnostic(
        executableName: "codex", entryPath: fixture.aliasPath, source: "npm"
    )
    let runner = ScriptedRunner(handler: npmScript(prefix: fixture.prefixText, root: fixture.rootText))

    let result = await InstallationOwnershipVerifier.verify(
        definition: definition,
        diagnostic: diagnostic,
        environment: fixture.environment,
        runner: runner,
        currentDirectory: fixture.root.path,
        now: fixedOwnershipClock()
    )

    #expect(result.verifiedInstallation == nil)
    #expect(result.unknownReason == .managerEntryMismatch)
}

// MARK: npm negative proof

@Test func npmRootMustMatchThePrefixLayoutByComponents() async throws {
    let fixture = try NpmOwnershipFixture("npm-root-mismatch")
    let unrelatedRoot = fixture.root.appendingPathComponent("other/lib/node_modules", isDirectory: true)
    try FileManager.default.createDirectory(at: unrelatedRoot, withIntermediateDirectories: true)
    let definition = try ownershipDefinition(packages: [(.npm, "@openai/codex")])
    let diagnostic = ownershipDiagnostic(
        executableName: "codex", entryPath: fixture.aliasPath, source: "npm"
    )
    let runner = ScriptedRunner(
        handler: npmScript(prefix: fixture.prefixText, root: unrelatedRoot.path)
    )

    let result = await InstallationOwnershipVerifier.verify(
        definition: definition,
        diagnostic: diagnostic,
        environment: fixture.environment,
        runner: runner,
        currentDirectory: fixture.root.path,
        now: fixedOwnershipClock()
    )

    #expect(result.unknownReason == .managerRootMismatch)
    #expect(runner.calls.count == 2)
}

@Test func npmEscapingNodeModulesLinkCannotBorrowAnotherPrefix() async throws {
    let fixture = try NpmOwnershipFixture("npm-prefix-escape")
    let otherRoot = fixture.root.appendingPathComponent(
        "other-prefix/lib/node_modules", isDirectory: true
    )
    let otherPackage = otherRoot.appendingPathComponent("@openai/codex", isDirectory: true)
    let otherBin = otherPackage.appendingPathComponent("bin", isDirectory: true)
    try FileManager.default.createDirectory(at: otherBin, withIntermediateDirectories: true)
    try writeOwnershipExecutable(otherBin.appendingPathComponent("codex.js"))
    let manifest: [String: Any] = [
        "name": "@openai/codex",
        "version": "1.0.0",
        "bin": ["codex": "bin/codex.js"],
    ]
    try JSONSerialization.data(withJSONObject: manifest)
        .write(to: otherPackage.appendingPathComponent("package.json"))
    // Replace the reported prefix's node_modules directory with a link into another prefix.
    try FileManager.default.removeItem(at: fixture.globalRoot)
    try FileManager.default.createDirectory(
        at: fixture.globalRoot.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try FileManager.default.createSymbolicLink(
        atPath: fixture.globalRoot.path, withDestinationPath: otherRoot.path
    )

    let definition = try ownershipDefinition(packages: [(.npm, "@openai/codex")])
    let diagnostic = ownershipDiagnostic(
        executableName: "codex", entryPath: fixture.aliasPath, source: "npm"
    )
    let runner = ScriptedRunner(
        handler: npmScript(prefix: fixture.prefixText, root: otherRoot.path)
    )

    let result = await InstallationOwnershipVerifier.verify(
        definition: definition,
        diagnostic: diagnostic,
        environment: fixture.environment,
        runner: runner,
        currentDirectory: fixture.root.path,
        now: fixedOwnershipClock()
    )

    #expect(result.verifiedInstallation == nil)
    #expect(result.unknownReason == .managerRootMismatch)
    #expect(runner.calls.count == 2)
}

@Test func npmDecoyNodeModulesPathCannotBorrowTheRealPrefixProof() async throws {
    let fixture = try NpmOwnershipFixture("npm-decoy")
    let decoyRoot = fixture.root.appendingPathComponent("decoy/lib/node_modules", isDirectory: true)
    let decoyPackage = decoyRoot.appendingPathComponent("@openai/codex/bin", isDirectory: true)
    try FileManager.default.createDirectory(at: decoyPackage, withIntermediateDirectories: true)
    let decoyTarget = decoyPackage.appendingPathComponent("codex.js")
    try writeOwnershipExecutable(decoyTarget)
    let decoyBin = fixture.root.appendingPathComponent("decoy/bin", isDirectory: true)
    try FileManager.default.createDirectory(at: decoyBin, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
        atPath: decoyBin.appendingPathComponent("codex").path,
        withDestinationPath: decoyTarget.path
    )
    let definition = try ownershipDefinition(packages: [(.npm, "@openai/codex")])
    let diagnostic = ownershipDiagnostic(
        executableName: "codex",
        entryPath: decoyBin.appendingPathComponent("codex").path,
        source: "npm"
    )
    let runner = ScriptedRunner(handler: npmScript(prefix: fixture.prefixText, root: fixture.rootText))

    let result = await InstallationOwnershipVerifier.verify(
        definition: definition,
        diagnostic: diagnostic,
        environment: fixture.environment,
        runner: runner,
        currentDirectory: fixture.root.path,
        now: fixedOwnershipClock()
    )

    #expect(result.verifiedInstallation == nil)
    #expect(result.unknownReason == .manifestExecutableMismatch)
}

@Test func npmWrongManifestNameAndMissingBinAreNeutral() async throws {
    let wrongName = try NpmOwnershipFixture("npm-wrong-name", manifestName: "someone-else")
    let definition = try ownershipDefinition(packages: [(.npm, "@openai/codex")])
    let diagnostic = ownershipDiagnostic(
        executableName: "codex", entryPath: wrongName.aliasPath, source: "npm"
    )
    let runner = ScriptedRunner(
        handler: npmScript(prefix: wrongName.prefixText, root: wrongName.rootText)
    )
    let result = await InstallationOwnershipVerifier.verify(
        definition: definition,
        diagnostic: diagnostic,
        environment: wrongName.environment,
        runner: runner,
        currentDirectory: wrongName.root.path,
        now: fixedOwnershipClock()
    )
    #expect(result.unknownReason == .packageNameMismatch)

    let missingBin = try NpmOwnershipFixture(
        "npm-missing-bin", binValue: ["other": "bin/codex.js"]
    )
    let runner2 = ScriptedRunner(
        handler: npmScript(prefix: missingBin.prefixText, root: missingBin.rootText)
    )
    let result2 = await InstallationOwnershipVerifier.verify(
        definition: definition,
        diagnostic: ownershipDiagnostic(
            executableName: "codex", entryPath: missingBin.aliasPath, source: "npm"
        ),
        environment: missingBin.environment,
        runner: runner2,
        currentDirectory: missingBin.root.path,
        now: fixedOwnershipClock()
    )
    #expect(result2.unknownReason == .executableNotDeclared)
}

@Test func npmTraversalAndSymlinkEscapesNeverLeaveThePackageRoot() async throws {
    let traversal = try NpmOwnershipFixture(
        "npm-traversal", binValue: ["codex": "../../outside.js"]
    )
    let outside = traversal.root.appendingPathComponent("outside.js")
    try writeOwnershipExecutable(outside)
    let definition = try ownershipDefinition(packages: [(.npm, "@openai/codex")])
    let traversalRunner = ScriptedRunner(
        handler: npmScript(prefix: traversal.prefixText, root: traversal.rootText)
    )
    let traversalResult = await InstallationOwnershipVerifier.verify(
        definition: definition,
        diagnostic: ownershipDiagnostic(
            executableName: "codex", entryPath: traversal.aliasPath, source: "npm"
        ),
        environment: traversal.environment,
        runner: traversalRunner,
        currentDirectory: traversal.root.path,
        now: fixedOwnershipClock()
    )
    #expect(traversalResult.unknownReason == .executableOutsidePackage)

    let escaped = try NpmOwnershipFixture("npm-symlink-escape")
    let bindir = escaped.packageRoot("@openai/codex").appendingPathComponent("bin")
    let declaredBin = bindir.appendingPathComponent("codex.js")
    try FileManager.default.removeItem(at: declaredBin)
    let external = escaped.root.appendingPathComponent("external-codex")
    try writeOwnershipExecutable(external)
    try FileManager.default.createSymbolicLink(
        atPath: declaredBin.path, withDestinationPath: external.path
    )
    let escapedRunner = ScriptedRunner(
        handler: npmScript(prefix: escaped.prefixText, root: escaped.rootText)
    )
    let escapedResult = await InstallationOwnershipVerifier.verify(
        definition: definition,
        diagnostic: ownershipDiagnostic(
            executableName: "codex", entryPath: escaped.aliasPath, source: "npm"
        ),
        environment: escaped.environment,
        runner: escapedRunner,
        currentDirectory: escaped.root.path,
        now: fixedOwnershipClock()
    )
    #expect(escapedResult.unknownReason == .executableOutsidePackage)
}

@Test func npmSymlinkedManifestIsRejectedWithoutFollowingIt() async throws {
    let fixture = try NpmOwnershipFixture("npm-symlink-manifest")
    let outside = fixture.root.appendingPathComponent("outside-manifest.json")
    try Data(#"{"name":"@openai/codex","bin":{"codex":"bin/codex.js"}}"#.utf8)
        .write(to: outside)
    let manifest = fixture.packageRoot("@openai/codex").appendingPathComponent("package.json")
    try FileManager.default.removeItem(at: manifest)
    try FileManager.default.createSymbolicLink(
        atPath: manifest.path, withDestinationPath: outside.path
    )
    let definition = try ownershipDefinition(packages: [(.npm, "@openai/codex")])
    let runner = ScriptedRunner(
        handler: npmScript(prefix: fixture.prefixText, root: fixture.rootText)
    )

    let result = await InstallationOwnershipVerifier.verify(
        definition: definition,
        diagnostic: ownershipDiagnostic(
            executableName: "codex", entryPath: fixture.aliasPath, source: "npm"
        ),
        environment: fixture.environment,
        runner: runner,
        currentDirectory: fixture.root.path,
        now: fixedOwnershipClock()
    )

    // The outside file is a valid manifest for this package. If it were inspected after following
    // the final-component symlink, verification would succeed; the neutral reason proves refusal.
    #expect(result.verifiedInstallation == nil)
    #expect(result.unknownReason == .manifestUnreadable)
}

@Test func npmDirectoryAndDeviceManifestPlaceholdersAreRejectedWithoutReads() async throws {
    let directoryCase = try NpmOwnershipFixture("npm-directory-manifest")
    let directoryManifest = directoryCase.packageRoot("@openai/codex")
        .appendingPathComponent("package.json")
    try FileManager.default.removeItem(at: directoryManifest)
    try FileManager.default.createDirectory(
        at: directoryManifest, withIntermediateDirectories: false
    )
    let definition = try ownershipDefinition(packages: [(.npm, "@openai/codex")])
    let directoryRunner = ScriptedRunner(
        handler: npmScript(prefix: directoryCase.prefixText, root: directoryCase.rootText)
    )
    let directoryResult = await InstallationOwnershipVerifier.verify(
        definition: definition,
        diagnostic: ownershipDiagnostic(
            executableName: "codex", entryPath: directoryCase.aliasPath, source: "npm"
        ),
        environment: directoryCase.environment,
        runner: directoryRunner,
        currentDirectory: directoryCase.root.path,
        now: fixedOwnershipClock()
    )
    #expect(directoryResult.unknownReason == .manifestUnreadable)

    let deviceCase = try NpmOwnershipFixture("npm-device-manifest")
    let deviceManifest = deviceCase.packageRoot("@openai/codex")
        .appendingPathComponent("package.json")
    try FileManager.default.removeItem(at: deviceManifest)
    try FileManager.default.createSymbolicLink(
        atPath: deviceManifest.path, withDestinationPath: "/dev/null"
    )
    let deviceRunner = ScriptedRunner(
        handler: npmScript(prefix: deviceCase.prefixText, root: deviceCase.rootText)
    )
    let deviceResult = await InstallationOwnershipVerifier.verify(
        definition: definition,
        diagnostic: ownershipDiagnostic(
            executableName: "codex", entryPath: deviceCase.aliasPath, source: "npm"
        ),
        environment: deviceCase.environment,
        runner: deviceRunner,
        currentDirectory: deviceCase.root.path,
        now: fixedOwnershipClock()
    )
    #expect(deviceResult.unknownReason == .manifestUnreadable)
}

@Test func npmStaticAncestorSymlinkEscapeIsRejectedBeforeAnyManifestRead() async throws {
    let fixture = try NpmOwnershipFixture("npm-static-ancestor-escape")
    let outside = fixture.root.appendingPathComponent("outside-prefix", isDirectory: true)
    let outsidePackage = outside.appendingPathComponent("codex", isDirectory: true)
    let outsideBin = outsidePackage.appendingPathComponent("bin", isDirectory: true)
    try FileManager.default.createDirectory(at: outsideBin, withIntermediateDirectories: true)
    try writeOwnershipExecutable(outsideBin.appendingPathComponent("codex.js"))
    var decoyManifest = Data(repeating: 0x20, count: 1024 * 1024 + 1)
    decoyManifest[0] = UInt8(ascii: "{")
    try decoyManifest.write(to: outsidePackage.appendingPathComponent("package.json"))

    // The lexical package's ancestor becomes a link to an outside tree containing an oversized
    // manifest. Canonical containment must reject the package before that file is inspected.
    let scope = fixture.globalRoot.appendingPathComponent("@openai", isDirectory: true)
    try FileManager.default.removeItem(at: scope)
    try FileManager.default.createSymbolicLink(
        atPath: scope.path, withDestinationPath: outside.path
    )
    let definition = try ownershipDefinition(packages: [(.npm, "@openai/codex")])
    let runner = ScriptedRunner(
        handler: npmScript(prefix: fixture.prefixText, root: fixture.rootText)
    )

    let result = await InstallationOwnershipVerifier.verify(
        definition: definition,
        diagnostic: ownershipDiagnostic(
            executableName: "codex", entryPath: fixture.aliasPath, source: "npm"
        ),
        environment: fixture.environment,
        runner: runner,
        currentDirectory: fixture.root.path,
        now: fixedOwnershipClock()
    )

    #expect(result.verifiedInstallation == nil)
    #expect(result.unknownReason == .packagePathUnsafe)
}

@Test func npmAncestorReplacementAfterObservationCannotReadAnOutsideDecoy() async throws {
    let fixture = try NpmOwnershipFixture("npm-ancestor-replacement")
    let outside = fixture.root.appendingPathComponent("outside-decoy", isDirectory: true)
    let outsidePackage = outside.appendingPathComponent("codex", isDirectory: true)
    let outsideBin = outsidePackage.appendingPathComponent("bin", isDirectory: true)
    try FileManager.default.createDirectory(at: outsideBin, withIntermediateDirectories: true)
    try writeOwnershipExecutable(outsideBin.appendingPathComponent("codex.js"))
    var decoyManifest = Data(repeating: 0x20, count: 1024 * 1024 + 1)
    decoyManifest[0] = UInt8(ascii: "{")
    try decoyManifest.write(to: outsidePackage.appendingPathComponent("package.json"))

    let scope = fixture.globalRoot.appendingPathComponent("@openai", isDirectory: true)
    let observedScope = fixture.globalRoot.appendingPathComponent(
        "@openai-observed", isDirectory: true
    )
    let definition = try ownershipDefinition(packages: [(.npm, "@openai/codex")])
    let runner = ScriptedRunner(
        handler: npmScript(prefix: fixture.prefixText, root: fixture.rootText)
    )
    let diagnostic = ownershipDiagnostic(
        executableName: "codex", entryPath: fixture.aliasPath, source: "npm"
    )

    let result = await NpmOwnershipProbeTestHooks.$onBeforeAnchoredManifestOpen.withValue({
        try? FileManager.default.moveItem(at: scope, to: observedScope)
        try? FileManager.default.createSymbolicLink(
            atPath: scope.path, withDestinationPath: outside.path
        )
    }) {
        await InstallationOwnershipVerifier.verify(
            definition: definition,
            diagnostic: diagnostic,
            environment: fixture.environment,
            runner: runner,
            currentDirectory: fixture.root.path,
            now: fixedOwnershipClock()
        )
    }

    // The decoy manifest is oversized: if an unanchored absolute open followed the replaced
    // ancestor, the result would be `.manifestTooLarge` (or a successful decoy read). The anchored
    // walk fails on the ancestor symlink, so no outside bytes are consumed.
    #expect(result.verifiedInstallation == nil)
    #expect(result.unknownReason == .packagePathUnsafe)
}

@Test func npmDeclaredPackageLinkRetargetCannotKeepTheOldStoreProof() async throws {
    let fixture = try NpmOwnershipFixture("npm-package-link-retarget")
    let link = fixture.packageRoot("@openai/codex")
    let stores = fixture.globalRoot.appendingPathComponent(".stores", isDirectory: true)
    let storeOne = stores.appendingPathComponent("codex-v1", isDirectory: true)
    let storeTwo = stores.appendingPathComponent("codex-v2", isDirectory: true)
    for (index, store) in [storeOne, storeTwo].enumerated() {
        let binDirectory = store.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        try writeOwnershipExecutable(
            binDirectory.appendingPathComponent("codex.js"), version: "1.0.\(index)"
        )
        let manifest: [String: Any] = [
            "name": "@openai/codex",
            "version": "1.0.\(index)",
            "bin": ["codex": "bin/codex.js"],
        ]
        try JSONSerialization.data(withJSONObject: manifest)
            .write(to: store.appendingPathComponent("package.json"))
    }
    try FileManager.default.removeItem(at: link)
    try FileManager.default.createSymbolicLink(
        atPath: link.path, withDestinationPath: storeOne.path
    )
    // Keep the selected alias and the manager's prefix-bin entry pointing directly at the first
    // store, so only the declared lexical package link moves during verification.
    let stableTarget = storeOne.appendingPathComponent("bin/codex.js").path
    let prefixBinEntry = fixture.prefix.appendingPathComponent("bin/codex")
    try FileManager.default.removeItem(at: prefixBinEntry)
    try FileManager.default.createSymbolicLink(
        atPath: prefixBinEntry.path, withDestinationPath: stableTarget
    )
    try FileManager.default.removeItem(atPath: fixture.aliasPath)
    try FileManager.default.createSymbolicLink(
        atPath: fixture.aliasPath, withDestinationPath: stableTarget
    )

    let definition = try ownershipDefinition(packages: [(.npm, "@openai/codex")])
    let runner = ScriptedRunner(
        handler: npmScript(prefix: fixture.prefixText, root: fixture.rootText)
    )
    let diagnostic = ownershipDiagnostic(
        executableName: "codex", entryPath: fixture.aliasPath, source: "npm"
    )

    let result = await NpmOwnershipProbeTestHooks.$onBeforeAnchoredManifestOpen.withValue({
        // The selected executable, prefix bin and the originally observed store stay unchanged;
        // only the declared lexical package link moves to another in-root store.
        try? FileManager.default.removeItem(at: link)
        try? FileManager.default.createSymbolicLink(
            atPath: link.path, withDestinationPath: storeTwo.path
        )
    }) {
        await InstallationOwnershipVerifier.verify(
            definition: definition,
            diagnostic: diagnostic,
            environment: fixture.environment,
            runner: runner,
            currentDirectory: fixture.root.path,
            now: fixedOwnershipClock()
        )
    }

    #expect(result.verifiedInstallation == nil)
    #expect(result.unknownReason == .proofChanged)
    #expect(runner.calls.count == 2)
}

@Test func npmBinRetargetToOutsidePrefixCannotBorrowManagerBinProof() async throws {
    let fixture = try NpmOwnershipFixture("npm-bin-retarget")
    let package = fixture.packageRoot("@openai/codex")
    let packageBin = package.appendingPathComponent("bin/codex.js")
    let insideTarget = package.appendingPathComponent("bin/inside-codex.js")
    try writeOwnershipExecutable(insideTarget)
    try FileManager.default.removeItem(at: packageBin)
    try FileManager.default.createSymbolicLink(
        atPath: packageBin.path, withDestinationPath: insideTarget.path
    )

    // The selected executable and the manager prefix-bin entry belong to another test-owned
    // prefix. Only the declared package's bin link initially points inside its own package.
    let otherPrefix = fixture.root.appendingPathComponent("other-prefix", isDirectory: true)
    let selectedTarget = otherPrefix.appendingPathComponent("bin/codex.js")
    try writeOwnershipExecutable(selectedTarget)
    let prefixBin = fixture.prefix.appendingPathComponent("bin/codex")
    try FileManager.default.removeItem(at: prefixBin)
    try FileManager.default.createSymbolicLink(
        atPath: prefixBin.path, withDestinationPath: selectedTarget.path
    )
    try FileManager.default.removeItem(atPath: fixture.aliasPath)
    try FileManager.default.createSymbolicLink(
        atPath: fixture.aliasPath, withDestinationPath: selectedTarget.path
    )

    let definition = try ownershipDefinition(packages: [(.npm, "@openai/codex")])
    let runner = ScriptedRunner(
        handler: npmScript(prefix: fixture.prefixText, root: fixture.rootText)
    )
    let diagnostic = ownershipDiagnostic(
        executableName: "codex", entryPath: fixture.aliasPath, source: "npm"
    )

    let result = await NpmOwnershipProbeTestHooks.$onBeforeBinObservation.withValue({
        // Retarget after the pre-resolution point and before the executable observation used as
        // proof. The corrected adapter must contain that observed canonical target, not the
        // discarded pre-resolution.
        try? FileManager.default.removeItem(at: packageBin)
        try? FileManager.default.createSymbolicLink(
            atPath: packageBin.path, withDestinationPath: selectedTarget.path
        )
    }) {
        await InstallationOwnershipVerifier.verify(
            definition: definition,
            diagnostic: diagnostic,
            environment: fixture.environment,
            runner: runner,
            currentDirectory: fixture.root.path,
            now: fixedOwnershipClock()
        )
    }

    #expect(result.verifiedInstallation == nil)
    #expect(result.unknownReason == .executableOutsidePackage)
    #expect(result.observedSelectedTarget == selectedTarget.path)
    #expect(runner.calls.count == 2)
}

@Test func npmOversizedAndMalformedManifestsAreRejectedWithoutVerification() async throws {
    let oversized = try NpmOwnershipFixture("npm-oversized")
    let oversizedManifest = oversized.packageRoot("@openai/codex")
        .appendingPathComponent("package.json")
    var oversizedData = Data(repeating: 0x20, count: 1024 * 1024 + 1)
    oversizedData[0] = UInt8(ascii: "{")
    try oversizedData.write(to: oversizedManifest)
    let definition = try ownershipDefinition(packages: [(.npm, "@openai/codex")])
    let oversizedRunner = ScriptedRunner(
        handler: npmScript(prefix: oversized.prefixText, root: oversized.rootText)
    )
    let oversizedResult = await InstallationOwnershipVerifier.verify(
        definition: definition,
        diagnostic: ownershipDiagnostic(
            executableName: "codex", entryPath: oversized.aliasPath, source: "npm"
        ),
        environment: oversized.environment,
        runner: oversizedRunner,
        currentDirectory: oversized.root.path,
        now: fixedOwnershipClock()
    )
    #expect(oversizedResult.unknownReason == .manifestTooLarge)

    let malformed = try NpmOwnershipFixture("npm-malformed")
    try Data("{\"name\":".utf8).write(
        to: malformed.packageRoot("@openai/codex").appendingPathComponent("package.json")
    )
    let malformedRunner = ScriptedRunner(
        handler: npmScript(prefix: malformed.prefixText, root: malformed.rootText)
    )
    let malformedResult = await InstallationOwnershipVerifier.verify(
        definition: definition,
        diagnostic: ownershipDiagnostic(
            executableName: "codex", entryPath: malformed.aliasPath, source: "npm"
        ),
        environment: malformed.environment,
        runner: malformedRunner,
        currentDirectory: malformed.root.path,
        now: fixedOwnershipClock()
    )
    #expect(malformedResult.unknownReason == .manifestInvalid)
}

@Test func npmMissingDeclaredPackageIsNeutralRatherThanBorrowingAnotherPackage() async throws {
    let fixture = try NpmOwnershipFixture("npm-missing-package")
    let definition = try ownershipDefinition(packages: [(.npm, "@openai/other-tool")])
    let runner = ScriptedRunner(handler: npmScript(prefix: fixture.prefixText, root: fixture.rootText))

    let result = await InstallationOwnershipVerifier.verify(
        definition: definition,
        diagnostic: ownershipDiagnostic(
            executableName: "codex", entryPath: fixture.aliasPath, source: "npm"
        ),
        environment: fixture.environment,
        runner: runner,
        currentDirectory: fixture.root.path,
        now: fixedOwnershipClock()
    )

    #expect(result.unknownReason == .packageNotInstalled)
    #expect(runner.calls.count == 2)
}

@Test func npmSecondDeclarationCannotBorrowTheFirstPackagesExecutable() async throws {
    let fixture = try NpmOwnershipFixture("npm-second-declaration")
    // The second package's declaration cannot produce a second proof from the first package's
    // executable: its own bin is absent/outside its root. The genuine first package still verifies,
    // and the copy is never reported as the owner.
    try fixture.addMatchingPackage("@openai/codex-copy")
    let definition = try ownershipDefinition(
        packages: [(.npm, "@openai/codex"), (.npm, "@openai/codex-copy")]
    )
    let runner = ScriptedRunner(handler: npmScript(prefix: fixture.prefixText, root: fixture.rootText))

    let result = await InstallationOwnershipVerifier.verify(
        definition: definition,
        diagnostic: ownershipDiagnostic(
            executableName: "codex", entryPath: fixture.aliasPath, source: "npm"
        ),
        environment: fixture.environment,
        runner: runner,
        currentDirectory: fixture.root.path,
        now: fixedOwnershipClock()
    )

    let installation = try #require(result.verifiedInstallation)
    #expect(installation.packageName == "@openai/codex")
    #expect(installation.packageName != "@openai/codex-copy")
}

// MARK: Identity change and cancellation

@Test func npmSelectionRetargetDuringTheQuerySuppressesTheNextQueryAndNeverVerifies() async throws {
    let fixture = try NpmOwnershipFixture("npm-retarget")
    let replacementTarget = fixture.root.appendingPathComponent("replacement-codex")
    try writeOwnershipExecutable(replacementTarget)
    let aliasPath = fixture.aliasPath
    let runner = ScriptedRunner(handler: { _, arguments in
        if arguments == ["prefix", "--global"] {
            try? FileManager.default.removeItem(atPath: aliasPath)
            try? FileManager.default.createSymbolicLink(
                atPath: aliasPath, withDestinationPath: replacementTarget.path
            )
            return .success(Data((fixture.prefixText + "\n").utf8))
        }
        Issue.record("the root query must be suppressed after the selection changed")
        return .success(Data((fixture.rootText + "\n").utf8))
    })
    let definition = try ownershipDefinition(packages: [(.npm, "@openai/codex")])

    let result = await InstallationOwnershipVerifier.verify(
        definition: definition,
        diagnostic: ownershipDiagnostic(
            executableName: "codex", entryPath: fixture.aliasPath, source: "npm"
        ),
        environment: fixture.environment,
        runner: runner,
        currentDirectory: fixture.root.path,
        now: fixedOwnershipClock()
    )

    #expect(result.verifiedInstallation == nil)
    #expect(result.unknownReason == .selectedExecutableChanged)
    #expect(runner.calls == [["prefix", "--global"]])
}

@Test func npmManagerChangeDuringPrefixSuppressesRootAndReportsTheManager() async throws {
    let fixture = try NpmOwnershipFixture("npm-manager-change")
    let definition = try ownershipDefinition(packages: [(.npm, "@openai/codex")])
    let managerPath = fixture.managerPath
    let runner = ScriptedRunner(handler: { _, arguments in
        if arguments == ["prefix", "--global"] {
            try? Data("#!/bin/sh\nexit 1\n".utf8).write(to: URL(fileURLWithPath: managerPath))
            return .success(Data((fixture.prefixText + "\n").utf8))
        }
        Issue.record("the root query must be suppressed after the manager changed")
        return .success(Data((fixture.rootText + "\n").utf8))
    })

    let result = await InstallationOwnershipVerifier.verify(
        definition: definition,
        diagnostic: ownershipDiagnostic(
            executableName: "codex", entryPath: fixture.aliasPath, source: "npm"
        ),
        environment: fixture.environment,
        runner: runner,
        currentDirectory: fixture.root.path,
        now: fixedOwnershipClock()
    )

    #expect(result.verifiedInstallation == nil)
    #expect(result.unknownReason == .managerChanged)
    #expect(runner.calls == [["prefix", "--global"]])
}

/// An asynchronous gate that deliberately ignores task cancellation, like a bounded manager
/// process already in flight. The test opens it explicitly, so cleanup is awaited rather than
/// orphaned.
private actor OwnershipQueryGate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func open() {
        opened = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }

    func wait() async {
        if opened { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

private actor OwnershipRunnerState {
    private(set) var calls = 0
    private var callWaiters: [CheckedContinuation<Void, Never>] = []

    func noteCall() {
        calls += 1
        let pending = callWaiters
        callWaiters.removeAll()
        for waiter in pending { waiter.resume() }
    }

    func waitForCall() async {
        if calls > 0 { return }
        await withCheckedContinuation { callWaiters.append($0) }
    }
}

private final class GatedOwnershipRunner: UpdateCommandRunner, @unchecked Sendable {
    let state = OwnershipRunnerState()
    let gate = OwnershipQueryGate()
    let outcome: CommandOutcome

    init(outcome: CommandOutcome) {
        self.outcome = outcome
    }

    func run(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval
    ) async -> CommandOutcome {
        await state.noteCall()
        await gate.wait()
        return outcome
    }
}

@Test func cancellationDuringABoundedQueryAwaitsCleanupAndPublishesNoVerifiedResult() async throws {
    let fixture = try NpmOwnershipFixture("npm-cancel-during")
    let definition = try ownershipDefinition(packages: [(.npm, "@openai/codex")])
    let diagnostic = ownershipDiagnostic(
        executableName: "codex", entryPath: fixture.aliasPath, source: "npm"
    )
    let runner = GatedOwnershipRunner(
        outcome: .success(Data((fixture.prefixText + "\n").utf8))
    )

    let task = Task {
        await InstallationOwnershipVerifier.verify(
            definition: definition,
            diagnostic: diagnostic,
            environment: fixture.environment,
            runner: runner,
            currentDirectory: fixture.root.path,
            now: fixedOwnershipClock()
        )
    }
    await runner.state.waitForCall()
    task.cancel()
    await runner.gate.open()
    let result = await task.value

    #expect(result.unknownReason == .cancelled)
    let callCount = await runner.state.calls
    #expect(callCount == 1, "the next query must be suppressed after cancellation")
}

@Test func cancellationBeforeAnyQueryIsNeutralAndNeverVerified() async throws {
    let fixture = try NpmOwnershipFixture("npm-cancel-before")
    let definition = try ownershipDefinition(packages: [(.npm, "@openai/codex")])
    let diagnostic = ownershipDiagnostic(
        executableName: "codex", entryPath: fixture.aliasPath, source: "npm"
    )
    let runner = ScriptedRunner(handler: npmScript(prefix: fixture.prefixText, root: fixture.rootText))

    let task = Task {
        await InstallationOwnershipVerifier.verify(
            definition: definition,
            diagnostic: diagnostic,
            environment: fixture.environment,
            runner: runner,
            currentDirectory: fixture.root.path,
            now: fixedOwnershipClock()
        )
    }
    task.cancel()
    let result = await task.value

    #expect(result.verifiedInstallation == nil)
    #expect(result.unknownReason == .cancelled)
}

// MARK: Zero-query neutral outcomes

@Test func notInstalledInconsistentAndStandaloneSelectionsMakeZeroManagerCalls() async throws {
    let definition = try ownershipDefinition(packages: [(.npm, "@openai/codex")])
    let runner = ScriptedRunner(handler: { _, arguments in
        Issue.record("ineligible ownership must not query a manager: \(arguments)")
        return .failure(.spawnFailure)
    })
    let environment = ownershipEnvironment(pathEntries: ["/synthetic/bin"])

    let notInstalled = await InstallationOwnershipVerifier.verify(
        definition: definition,
        diagnostic: absentDiagnostic(),
        environment: environment,
        runner: runner,
        currentDirectory: "/",
        now: fixedOwnershipClock()
    )
    #expect(notInstalled.unknownReason == .notInstalled)

    let inconsistent = await InstallationOwnershipVerifier.verify(
        definition: definition,
        diagnostic: inconsistentDiagnostic(),
        environment: environment,
        runner: runner,
        currentDirectory: "/",
        now: fixedOwnershipClock()
    )
    #expect(inconsistent.unknownReason == .inconsistentSelection)

    let fixture = try NpmOwnershipFixture("npm-standalone")
    let standalone = await InstallationOwnershipVerifier.verify(
        definition: definition,
        diagnostic: ownershipDiagnostic(
            executableName: "codex", entryPath: fixture.aliasPath, source: "standalone"
        ),
        environment: fixture.environment,
        runner: runner,
        currentDirectory: fixture.root.path,
        now: fixedOwnershipClock()
    )
    #expect(standalone.unknownReason == .unsupportedSource)
    #expect(runner.calls.isEmpty)
}

@Test func npmWithoutADeclaredCandidateMakesZeroManagerCalls() async throws {
    let fixture = try NpmOwnershipFixture("npm-no-declaration")
    let definition = try ownershipDefinition(packages: [])
    let runner = ScriptedRunner(handler: { _, arguments in
        Issue.record("no declaration must not query npm: \(arguments)")
        return .failure(.spawnFailure)
    })

    let result = await InstallationOwnershipVerifier.verify(
        definition: definition,
        diagnostic: ownershipDiagnostic(
            executableName: "codex", entryPath: fixture.aliasPath, source: "npm"
        ),
        environment: fixture.environment,
        runner: runner,
        currentDirectory: fixture.root.path,
        now: fixedOwnershipClock()
    )

    #expect(result.unknownReason == .noDeclaredPackage)
    #expect(runner.calls.isEmpty)
}

// MARK: Homebrew formula proof

private func brewScript(
    cellar: String,
    info: Data,
    list: Data,
    extra: @escaping @Sendable ([String]) -> CommandOutcome? = { _ in nil }
) -> @Sendable (String, [String]) -> CommandOutcome {
    { _, arguments in
        if let outcome = extra(arguments) { return outcome }
        if arguments == ["--cellar"] {
            return .success(Data((cellar + "\n").utf8))
        }
        if arguments.count == 4, arguments[0] == "info", arguments[1] == "--json=v2",
           arguments[2] == "--formula" {
            return .success(info)
        }
        if arguments.count == 4, arguments[0] == "list", arguments[1] == "--verbose",
           arguments[2] == "--formula" {
            return .success(list)
        }
        switch arguments {
        default:
            Issue.record("unexpected brew arguments: \(arguments)")
            return .failure(.spawnFailure)
        }
    }
}

@Test func homebrewFormulaProofUsesCellarInfoAndListWithoutStableVersionComparison() async throws {
    let fixture = try makeBrewFixture("ownership-brew-positive")
    let kegVersion = "1.0.0"
    let target = try fixture.installKeg(formula: "codex", keg: kegVersion)
    let definition = try ownershipDefinition(packages: [(.homebrewFormula, "codex")])
    let selectedEntry = fixture.prefix.appendingPathComponent("bin/codex").path
    let diagnostic = ownershipDiagnostic(
        executableName: "codex", entryPath: selectedEntry, source: "brew"
    )
    let info = infoJSON([(name: "codex", stable: "not-a-semver", revision: 1, installed: [kegVersion])])
    let list = Data("\(target)\n".utf8)
    let runner = ScriptedRunner(handler: brewScript(cellar: fixture.cellar, info: info, list: list))

    let result = await InstallationOwnershipVerifier.verify(
        definition: definition,
        diagnostic: diagnostic,
        environment: m6Environment(pathEntries: [fixture.binDirectory]),
        runner: runner,
        currentDirectory: fixture.prefix.deletingLastPathComponent().path,
        now: fixedOwnershipClock()
    )

    let installation = try #require(result.verifiedInstallation)
    #expect(installation.manager == .homebrewFormula)
    #expect(installation.packageName == "codex")
    #expect(installation.managerRoot == fixture.cellar)
    #expect(installation.installationRoot == fixture.cellar + "/codex/\(kegVersion)")
    #expect(installation.selection.entryPath == selectedEntry)
    #expect(installation.selection.canonicalTarget == target)
    #expect(runner.calls == [
        ["--cellar"],
        ["info", "--json=v2", "--formula", "codex"],
        ["list", "--verbose", "--formula", "codex"],
    ])
    #expect(runner.calls.allSatisfy { !$0.contains("--installed") })
    let diagnosticsEnvironment = runner.environments.first
    #expect(diagnosticsEnvironment?["HOMEBREW_NO_AUTO_UPDATE"] == "1")
    #expect(diagnosticsEnvironment?["HOMEBREW_NO_ANALYTICS"] == "1")
}

private func ownershipInfoJSON(record: String) -> Data {
    ownershipInfoJSON(records: [record])
}

private func ownershipInfoJSON(records: [String]) -> Data {
    Data("{\"formulae\":[\(records.joined(separator: ","))],\"casks\":[]}".utf8)
}

@Test func homebrewOwnershipDoesNotRequireStableVersionOrRevision() async throws {
    let fixture = try makeBrewFixture("ownership-brew-stable-independent")
    let kegVersion = "HEAD-abc"
    let target = try fixture.installKeg(formula: "codex", keg: kegVersion)
    let definition = try ownershipDefinition(packages: [(.homebrewFormula, "codex")])
    let selectedEntry = fixture.prefix.appendingPathComponent("bin/codex").path
    let diagnostic = ownershipDiagnostic(
        executableName: "codex", entryPath: selectedEntry, source: "brew"
    )
    let environment = m6Environment(pathEntries: [fixture.binDirectory])
    let currentDirectory = fixture.prefix.deletingLastPathComponent().path
    let records = [
        #"{"name":"codex","full_name":"codex","installed":[{"version":"HEAD-abc"}],"versions":{"stable":null},"revision":0}"#,
        #"{"name":"codex","full_name":"codex","installed":[{"version":"HEAD-abc"}],"versions":{}}"#,
        #"{"name":"codex","full_name":"codex","installed":[{"version":"HEAD-abc"}],"versions":{"stable":"not-a-semver"}}"#,
        #"{"name":"codex","full_name":"codex","installed":[{"version":"HEAD-abc"}],"revision":null}"#,
        #"{"name":"codex","full_name":"codex","installed":[{"version":"HEAD-abc"}],"versions":{"stable":17},"revision":"not-an-integer"}"#,
    ]

    for (index, record) in records.enumerated() {
        let runner = ScriptedRunner(handler: brewScript(
            cellar: fixture.cellar,
            info: ownershipInfoJSON(record: record),
            list: Data("\(target)\n".utf8)
        ))
        let result = await InstallationOwnershipVerifier.verify(
            definition: definition,
            diagnostic: diagnostic,
            environment: environment,
            runner: runner,
            currentDirectory: currentDirectory,
            now: fixedOwnershipClock()
        )
        let installation = try #require(
            result.verifiedInstallation, "ownership variant \(index) must verify"
        )
        #expect(installation.packageName == "codex", "variant \(index)")
        #expect(installation.installationRoot == fixture.cellar + "/codex/\(kegVersion)")
        #expect(runner.calls.count == 3, "variant \(index)")
    }
}

@Test func homebrewOwnershipKeepsMalformedIdentityClaimsFromBorrowingProof() async throws {
    let fixture = try makeBrewFixture("ownership-brew-identity-claims")
    let kegVersion = "1.0.0"
    let target = try fixture.installKeg(formula: "codex", keg: kegVersion)
    let definition = try ownershipDefinition(packages: [(.homebrewFormula, "codex")])
    let selectedEntry = fixture.prefix.appendingPathComponent("bin/codex").path
    let diagnostic = ownershipDiagnostic(
        executableName: "codex", entryPath: selectedEntry, source: "brew"
    )
    let environment = m6Environment(pathEntries: [fixture.binDirectory])
    let currentDirectory = fixture.prefix.deletingLastPathComponent().path
    let list = Data("\(target)\n".utf8)

    let cases: [(label: String, info: Data, reason: InstallationOwnershipReason)] = [
        (
            "missing-full-name",
            ownershipInfoJSON(
                record: #"{"name":"codex","installed":[{"version":"1.0.0"}],"versions":{"stable":"1.0.0"}}"#
            ),
            .formulaRecordMismatch
        ),
        (
            "contradictory-full-name",
            ownershipInfoJSON(
                record: #"{"name":"codex","full_name":"acme/tap/codex-copy","installed":[{"version":"1.0.0"}]}"#
            ),
            .formulaRecordMismatch
        ),
        (
            "borrowed-tap-full-name",
            ownershipInfoJSON(
                record: #"{"name":"codex","full_name":"acme/tap/codex","installed":[{"version":"1.0.0"}]}"#
            ),
            .formulaRecordMismatch
        ),
        (
            "malformed-installed-list",
            ownershipInfoJSON(
                record: #"{"name":"codex","full_name":"codex","installed":"1.0.0"}"#
            ),
            .formulaRecordMismatch
        ),
        (
            "missing-name",
            ownershipInfoJSON(
                record: #"{"full_name":"codex","installed":[{"version":"1.0.0"}]}"#
            ),
            .invalidManagerOutput
        ),
    ]

    for testCase in cases {
        let runner = ScriptedRunner(handler: brewScript(
            cellar: fixture.cellar, info: testCase.info, list: list
        ))
        let result = await InstallationOwnershipVerifier.verify(
            definition: definition,
            diagnostic: diagnostic,
            environment: environment,
            runner: runner,
            currentDirectory: currentDirectory,
            now: fixedOwnershipClock()
        )
        #expect(result.verifiedInstallation == nil, "\(testCase.label)")
        #expect(result.unknownReason == testCase.reason, "\(testCase.label)")
        #expect(runner.calls.count == 2, "\(testCase.label)")
    }

    let duplicate = ownershipInfoJSON(
        records: [
            #"{"name":"codex","full_name":"codex","installed":[{"version":"1.0.0"}]}"#,
            #"{"name":"codex","full_name":"other/tap/codex-copy","installed":[{"version":"1.0.0"}]}"#,
        ]
    )
    let duplicateRunner = ScriptedRunner(handler: brewScript(
        cellar: fixture.cellar, info: duplicate, list: list
    ))
    let duplicateResult = await InstallationOwnershipVerifier.verify(
        definition: definition,
        diagnostic: diagnostic,
        environment: environment,
        runner: duplicateRunner,
        currentDirectory: currentDirectory,
        now: fixedOwnershipClock()
    )
    #expect(duplicateResult.unknownReason == .formulaRecordMismatch)
    #expect(duplicateRunner.calls.count == 2)
}

@Test func homebrewMalformedDuplicateAndMismatchedRecordsNeverVerify() async throws {
    let fixture = try makeBrewFixture("ownership-brew-records")
    let kegVersion = "1.0.0"
    let target = try fixture.installKeg(formula: "codex", keg: kegVersion)
    let definition = try ownershipDefinition(packages: [(.homebrewFormula, "codex")])
    let selectedEntry = fixture.prefix.appendingPathComponent("bin/codex").path
    let diagnostic = ownershipDiagnostic(
        executableName: "codex", entryPath: selectedEntry, source: "brew"
    )
    let list = Data("\(target)\n".utf8)
    let environment = m6Environment(pathEntries: [fixture.binDirectory])
    let currentDirectory = fixture.prefix.deletingLastPathComponent().path

    let malformedRunner = ScriptedRunner(handler: brewScript(
        cellar: fixture.cellar, info: Data("not-json".utf8), list: list
    ))
    let malformed = await InstallationOwnershipVerifier.verify(
        definition: definition, diagnostic: diagnostic, environment: environment,
        runner: malformedRunner, currentDirectory: currentDirectory, now: fixedOwnershipClock()
    )
    #expect(malformed.unknownReason == .invalidManagerOutput)
    #expect(malformedRunner.calls.count == 2)

    let duplicateInfo = infoJSON([
        (name: "codex", stable: "1.0.0", revision: 1, installed: [kegVersion]),
        (name: "codex", stable: "1.0.0", revision: 1, installed: [kegVersion]),
    ])
    let duplicateRunner = ScriptedRunner(handler: brewScript(
        cellar: fixture.cellar, info: duplicateInfo, list: list
    ))
    let duplicate = await InstallationOwnershipVerifier.verify(
        definition: definition, diagnostic: diagnostic, environment: environment,
        runner: duplicateRunner, currentDirectory: currentDirectory, now: fixedOwnershipClock()
    )
    #expect(duplicate.unknownReason == .formulaRecordMismatch)

    let mismatchedDefinition = try ownershipDefinition(
        packages: [(.homebrewFormula, "acme/tap/codex")]
    )
    let mismatchRunner = ScriptedRunner(handler: brewScript(
        cellar: fixture.cellar,
        info: infoJSON([(name: "codex", stable: "1.0.0", revision: 1, installed: [kegVersion])]),
        list: list
    ))
    let mismatch = await InstallationOwnershipVerifier.verify(
        definition: mismatchedDefinition, diagnostic: diagnostic, environment: environment,
        runner: mismatchRunner, currentDirectory: currentDirectory, now: fixedOwnershipClock()
    )
    #expect(mismatch.unknownReason == .formulaRecordMismatch)
}

@Test func homebrewOtherKegUninstalledKegAndUnlistedKegStayUnknown() async throws {
    let fixture = try makeBrewFixture("ownership-brew-kegs")
    let kegVersion = "1.0.0"
    let target = try fixture.installKeg(formula: "codex", keg: kegVersion)
    let definition = try ownershipDefinition(packages: [(.homebrewFormula, "codex")])
    let selectedEntry = fixture.prefix.appendingPathComponent("bin/codex").path
    let diagnostic = ownershipDiagnostic(
        executableName: "codex", entryPath: selectedEntry, source: "brew"
    )
    let environment = m6Environment(pathEntries: [fixture.binDirectory])
    let currentDirectory = fixture.prefix.deletingLastPathComponent().path

    // A different keg path in the list is not the selected keg; the selected symlink stays on the
    // original target, so this proves the list result is not borrowed from a sibling keg.
    let otherKeg = fixture.prefix
        .appendingPathComponent("Cellar/codex/9.9.9/bin/codex")
    try writeOwnershipExecutable(otherKeg)
    let otherList = Data("\(otherKeg.path)\n".utf8)
    let otherRunner = ScriptedRunner(handler: brewScript(
        cellar: fixture.cellar,
        info: infoJSON([(name: "codex", stable: "1.0.0", revision: 1, installed: [kegVersion])]),
        list: otherList
    ))
    let other = await InstallationOwnershipVerifier.verify(
        definition: definition, diagnostic: diagnostic, environment: environment,
        runner: otherRunner, currentDirectory: currentDirectory, now: fixedOwnershipClock()
    )
    #expect(other.unknownReason == .selectedKegNotConfirmed)
    #expect(otherRunner.calls.count == 3)

    let uninstalledRunner = ScriptedRunner(handler: brewScript(
        cellar: fixture.cellar,
        info: infoJSON([(name: "codex", stable: "1.0.0", revision: 1, installed: ["2.0.0"])]),
        list: Data("\(target)\n".utf8)
    ))
    let uninstalled = await InstallationOwnershipVerifier.verify(
        definition: definition, diagnostic: diagnostic, environment: environment,
        runner: uninstalledRunner, currentDirectory: currentDirectory, now: fixedOwnershipClock()
    )
    #expect(uninstalled.unknownReason == .selectedKegNotInstalled)
    #expect(uninstalledRunner.calls.count == 2)
}

@Test func homebrewOtherCellarCaskAndStandaloneNeverQueryForFormulaProof() async throws {
    let fixture = try makeBrewFixture("ownership-brew-other-cellar")
    try FileManager.default.createDirectory(
        at: fixture.prefix.appendingPathComponent("Cellar", isDirectory: true),
        withIntermediateDirectories: true
    )
    let otherCellar = fixture.prefix.deletingLastPathComponent()
        .appendingPathComponent("other/Cellar", isDirectory: true)
    let otherKeg = otherCellar.appendingPathComponent("codex/1.0.0/bin", isDirectory: true)
    try FileManager.default.createDirectory(at: otherKeg, withIntermediateDirectories: true)
    let otherTarget = otherKeg.appendingPathComponent("codex")
    try writeOwnershipExecutable(otherTarget)
    let otherBin = fixture.prefix.deletingLastPathComponent()
        .appendingPathComponent("other/bin", isDirectory: true)
    try FileManager.default.createDirectory(at: otherBin, withIntermediateDirectories: true)
    let selectedEntry = otherBin.appendingPathComponent("codex")
    try FileManager.default.createSymbolicLink(
        atPath: selectedEntry.path, withDestinationPath: otherTarget.path
    )
    let definition = try ownershipDefinition(packages: [(.homebrewFormula, "codex")])
    let runner = ScriptedRunner(handler: { _, arguments in
        if arguments == ["--cellar"] {
            return .success(Data((fixture.cellar + "\n").utf8))
        }
        Issue.record("other Cellar must not proceed to info/list: \(arguments)")
        return .failure(.spawnFailure)
    })
    let result = await InstallationOwnershipVerifier.verify(
        definition: definition,
        diagnostic: ownershipDiagnostic(
            executableName: "codex", entryPath: selectedEntry.path, source: "brew"
        ),
        environment: m6Environment(pathEntries: [otherBin.path, fixture.binDirectory]),
        runner: runner,
        currentDirectory: fixture.prefix.deletingLastPathComponent().path,
        now: fixedOwnershipClock()
    )
    #expect(result.unknownReason == .managerRootMismatch)
    #expect(runner.calls == [["--cellar"]])

    let caskDefinition = try ownershipDefinition(packages: [(.homebrewCask, "codex")])
    let zeroRunner = ScriptedRunner(handler: { _, arguments in
        Issue.record("cask ownership must not query brew: \(arguments)")
        return .failure(.spawnFailure)
    })
    let cask = await InstallationOwnershipVerifier.verify(
        definition: caskDefinition,
        diagnostic: ownershipDiagnostic(
            executableName: "codex", entryPath: selectedEntry.path, source: "brew"
        ),
        environment: m6Environment(pathEntries: [fixture.binDirectory]),
        runner: zeroRunner,
        currentDirectory: fixture.prefix.deletingLastPathComponent().path,
        now: fixedOwnershipClock()
    )
    #expect(cask.unknownReason == .unsupportedCask)
    #expect(zeroRunner.calls.isEmpty)
}

@Test func homebrewManagerChangeDuringInfoSuppressesListAndNeverVerifies() async throws {
    let fixture = try makeBrewFixture("ownership-brew-manager-change")
    let kegVersion = "1.0.0"
    let target = try fixture.installKeg(formula: "codex", keg: kegVersion)
    let definition = try ownershipDefinition(packages: [(.homebrewFormula, "codex")])
    let selectedEntry = fixture.prefix.appendingPathComponent("bin/codex").path
    let diagnostic = ownershipDiagnostic(
        executableName: "codex", entryPath: selectedEntry, source: "brew"
    )
    let brewPath = fixture.brewPath
    let runner = ScriptedRunner(handler: { _, arguments in
        switch arguments {
        case ["--cellar"]:
            return .success(Data((fixture.cellar + "\n").utf8))
        case ["info", "--json=v2", "--formula", "codex"]:
            try? Data("#!/bin/sh\nexit 0\n".utf8).write(to: URL(fileURLWithPath: brewPath))
            return .success(
                infoJSON([(name: "codex", stable: "1.0.0", revision: 1, installed: [kegVersion])])
            )
        case ["list", "--verbose", "--formula", "codex"]:
            Issue.record("manager identity change must suppress the list query")
            return .success(Data("\(target)\n".utf8))
        default:
            return .failure(.spawnFailure)
        }
    })

    let result = await InstallationOwnershipVerifier.verify(
        definition: definition,
        diagnostic: diagnostic,
        environment: m6Environment(pathEntries: [fixture.binDirectory]),
        runner: runner,
        currentDirectory: fixture.prefix.deletingLastPathComponent().path,
        now: fixedOwnershipClock()
    )

    #expect(result.verifiedInstallation == nil)
    #expect(result.unknownReason == .managerChanged)
    #expect(runner.calls.count == 2)
}
