// NpmUpdateProbeTests — M10-B bounded npm `latest` metadata probe behavioral regressions (B02–B05).
//
// Every fixture is a synthetic, test-owned npm global tree on disk: `prefix/bin/<exe>` and a PATH
// alias both symlink to the package's own `bin/codex.js`, with a manifest that binds that bin. The
// existing ownership verifier reads that real tree, so the probe's two full verifications (initial
// and pre-publication) succeed exactly as they do on a machine. No real npm or registry is invoked:
// a recording seam answers `prefix`/`root`/`config get *registry`/`view`/`--version`, and the
// scratch base is an injected owned directory, so the flow's per-invocation roots, cleanup, and
// process counts are observable. The persistent document lives only in the injected scratch cache.
//
// The cases prove the frozen guarantees: verified up-to-date/update-available publish with npm
// identity and fresh provenance; a scoped bind puts BOTH registry flags on the single `view` call;
// a custom base or custom scope refuses with ZERO metadata calls; strict metadata rejections and a
// prerelease channel stay neutral and are never persisted; a newer installed version is never
// cached; a Check cache-hit skips the `view` call yet still re-runs ownership and registry reads and
// preserves the original observation time; Refresh always re-fetches; an exhausted stage stops after
// the initial ownership and preserves the tool's identity; and ineligible selections launch nothing.

import Foundation
import Darwin
import Testing
@testable import AgentLensCore

// MARK: Synthetic npm tree

private func npmProbeScratchRoot(_ label: String) throws -> URL {
    let processEnvironment = ProcessInfo.processInfo.environment
    guard let basePath = [processEnvironment["AGENT_LENS_TEST_SCRATCH"], processEnvironment["TMPDIR"]]
        .compactMap({ $0 })
        .first(where: { !$0.isEmpty })
    else {
        throw NSError(
            domain: "NpmProbeTests", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "no approved test scratch root is available"]
        )
    }
    let base = URL(fileURLWithPath: basePath, isDirectory: true).resolvingSymlinksInPath()
    let root = base.appendingPathComponent(
        "agentlens-m10b-probe-\(label)-\(UUID().uuidString)", isDirectory: true
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root.resolvingSymlinksInPath()
}

private func npmProbeWriteExecutable(_ url: URL) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
}

private func npmProbeEnvironment(pathEntries: [String]) -> ShellEnvironment {
    let joined = pathEntries.joined(separator: ":")
    return ShellEnvironment(
        shellPath: "/bin/zsh",
        pathEntries: pathEntries,
        pathJoined: joined,
        raw: ["PATH": joined, "HOME": "/synthetic/home"],
        isDegraded: false
    )
}

private func npmProbeDefinition(
    executableName: String,
    package: String
) throws -> DetectorDefinition {
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

/// A winner diagnostic for the PATH alias, carrying a fixed installed version so the probe reaches
/// the metadata stage instead of stopping at `installedVersionUnavailable`.
private func npmProbeWinnerDiagnostic(
    executableName: String,
    entryPath: String,
    version: String
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
        state: .installedAndOnPath,
        entryPath: entryPath,
        resolvedPath: target,
        source: "npm",
        version: version
    )
    return ToolPathDiagnostic(
        detectedTool: detected,
        pathCandidates: [candidate],
        firstLiveCandidate: candidate,
        targetGroups: [
            PathTargetGroup(canonicalTarget: target, entryPaths: [entryPath], firstSlotIndex: 0)
        ],
        repeatedPathSlotCount: 0,
        sameTargetAliasCount: 0,
        selection: .winner(candidate),
        shadowedInstallationCount: 0,
        installationVersions: []
    )
}

private struct NpmProbeFixture {
    let root: URL
    let prefix: URL
    let globalRoot: URL
    let managerDirectory: URL
    let alias: URL
    let target: URL
    let package: String
    let executableName: String
    let environment: ShellEnvironment

    var managerPath: String { managerDirectory.appendingPathComponent("npm").path }
    var prefixText: String { prefix.path }
    var rootText: String { globalRoot.path }
    var aliasPath: String { alias.path }

    init(_ label: String, package: String = "@openai/codex", executableName: String = "codex") throws {
        self.package = package
        self.executableName = executableName
        root = try npmProbeScratchRoot(label)
        prefix = root.appendingPathComponent("prefix", isDirectory: true)
        globalRoot = prefix.appendingPathComponent("lib/node_modules", isDirectory: true)
        managerDirectory = root.appendingPathComponent("manager-bin", isDirectory: true)
        let aliasDirectory = root.appendingPathComponent("alias-bin", isDirectory: true)
        try FileManager.default.createDirectory(at: managerDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: aliasDirectory, withIntermediateDirectories: true)
        try npmProbeWriteExecutable(managerDirectory.appendingPathComponent("npm"))

        var packageURL = globalRoot
        for component in package.split(separator: "/", omittingEmptySubsequences: false) {
            packageURL.appendPathComponent(String(component), isDirectory: true)
        }
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        target = packageURL.appendingPathComponent("bin/codex.js")
        try npmProbeWriteExecutable(target)

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
        environment = npmProbeEnvironment(
            pathEntries: [managerDirectory.path, aliasDirectory.path]
        )
    }
}

// MARK: Recording npm seam

private enum NpmCommand: Equatable {
    case prefix, root, version, view, configBase, configScope, other
}

/// Categorizes a scripted npm invocation by its command token. Scratch flags (`--cache <root>` etc.)
/// are prepended by the probe, so categorization scans membership rather than exact arrays. `view`
/// and `--version` are matched before config so the `version`/`registry` field tokens never collide.
private func categorizeNpm(_ arguments: [String]) -> NpmCommand {
    if arguments.contains("prefix") { return .prefix }
    if arguments.contains("root") { return .root }
    if arguments.contains("--version") { return .version }
    if arguments.contains("view") { return .view }
    if arguments.contains(where: { $0.hasSuffix(":registry") }) { return .configScope }
    if arguments.contains("registry") { return .configBase }
    return .other
}

private class RecordingNpmRunner: UpdateCommandRunner, @unchecked Sendable {
    struct Invocation {
        let arguments: [String]
        let environment: [String: String]
        let cacheMode: mode_t?
    }

    private let lock = NSLock()
    private var counts: [NpmCommand: Int] = [:]
    private var recorded: [[String]] = []
    private var viewArguments: [[String]] = []
    private var invocations: [Invocation] = []

    let prefix: String
    let root: String
    let baseRegistry: String
    let scopeRegistry: String
    let viewJSON: Data
    let versionText: String

    init(
        prefix: String,
        root: String,
        baseRegistry: String = "https://registry.npmjs.org/",
        scopeRegistry: String = "undefined",
        viewJSON: Data,
        versionText: String = "10.5.0"
    ) {
        self.prefix = prefix
        self.root = root
        self.baseRegistry = baseRegistry
        self.scopeRegistry = scopeRegistry
        self.viewJSON = viewJSON
        self.versionText = versionText
    }

    func count(_ command: NpmCommand) -> Int {
        lock.lock(); defer { lock.unlock() }
        return counts[command, default: 0]
    }

    var metadataCallCount: Int { count(.view) }
    var recordedCount: Int {
        lock.lock(); defer { lock.unlock() }
        return recorded.count
    }
    var viewArgs: [[String]] {
        lock.lock(); defer { lock.unlock() }
        return viewArguments
    }
    var recordedArguments: [[String]] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    var recordedInvocations: [Invocation] {
        lock.lock(); defer { lock.unlock() }
        return invocations
    }

    func run(
        executablePath: String, arguments: [String],
        environment: [String: String], timeout: TimeInterval
    ) async -> CommandOutcome {
        let command = categorizeNpm(arguments)
        noteCall(command, arguments, environment)
        return outcome(for: command)
    }

    private func noteCall(
        _ command: NpmCommand, _ arguments: [String], _ environment: [String: String]
    ) {
        lock.lock(); defer { lock.unlock() }
        counts[command, default: 0] += 1
        recorded.append(arguments)
        if command == .view { viewArguments.append(arguments) }
        var info = stat()
        let mode: mode_t?
        if let path = environment["NPM_CONFIG_CACHE"], lstat(path, &info) == 0 {
            mode = info.st_mode & mode_t(0o777)
        } else {
            mode = nil
        }
        invocations.append(Invocation(arguments: arguments, environment: environment, cacheMode: mode))
    }

    private func outcome(for command: NpmCommand) -> CommandOutcome {
        switch command {
        case .prefix: return .success(Data((prefix + "\n").utf8))
        case .root: return .success(Data((root + "\n").utf8))
        case .configBase: return .success(Data((baseRegistry + "\n").utf8))
        case .configScope: return .success(Data((scopeRegistry + "\n").utf8))
        case .view: return .success(viewJSON)
        case .version: return .success(Data((versionText + "\n").utf8))
        case .other: return .failure(.spawnFailure)
        }
    }
}

private func npmProbeViewJSON(package: String, version: String, latest: String) -> Data {
    Data(#"{"name":"\#(package)","version":"\#(version)","dist-tags.latest":"\#(latest)"}"#.utf8)
}

private func npmProbeFixedClock(_ date: Date) -> @Sendable () -> Date { { date } }
private func npmProbeZeroUptime() -> @Sendable () -> UInt64 { { 0 } }

private func npmProbeReason(_ status: VersionStatus) -> UnknownReason? {
    if case .unknown(_, let reason) = status { return reason }
    return nil
}

private let npmProbeBaseDate = Date(timeIntervalSince1970: 1_800_000_000)
private let npmProbeFarDeadline: UInt64 = .max / 2

// MARK: Verified publication

@Test func unscopedUpdateAvailablePublishesNpmIdentityAndFreshProvenance() async throws {
    let fixture = try NpmProbeFixture("ok-update", package: "codex-ai", executableName: "codex-ai")
    let definition = try npmProbeDefinition(executableName: "codex-ai", package: "codex-ai")
    let diagnostic = npmProbeWinnerDiagnostic(
        executableName: "codex-ai", entryPath: fixture.aliasPath, version: "1.0.0"
    )
    let runner = RecordingNpmRunner(
        prefix: fixture.prefixText, root: fixture.rootText,
        viewJSON: npmProbeViewJSON(package: "codex-ai", version: "2.0.0", latest: "2.0.0")
    )
    let cacheDir = try npmProbeScratchRoot("ok-update-cache")
    let scratchBase = cacheDir.appendingPathComponent("scratch", isDirectory: true)
    try FileManager.default.createDirectory(at: scratchBase, withIntermediateDirectories: true)

    let result = await NpmUpdateProbe.run(
        definition: definition, diagnostic: diagnostic, environment: fixture.environment,
        runner: runner, cacheURL: cacheDir.appendingPathComponent("update-cache.json"),
        mode: .checkUpdates, currentDirectory: fixture.root.path,
        now: npmProbeFixedClock(npmProbeBaseDate), uptime: npmProbeZeroUptime(),
        stageDeadline: npmProbeFarDeadline, diagnosticIndex: 3,
        npmScratchBaseURL: scratchBase
    )

    guard case .updateAvailable(let installed, let latest) = result.status else {
        Issue.record("expected updateAvailable, got \(result.status)"); return
    }
    #expect(installed.text == "1.0.0")
    #expect(latest.text == "2.0.0")
    #expect(result.provenance == .freshProbe(observedAt: npmProbeBaseDate))
    #expect(result.npmPackage == "codex-ai")
    #expect(result.npmRegistry == "https://registry.npmjs.org/")
    #expect(result.npmTag == "latest")
    #expect(result.npmVersion == "10.5.0")
    #expect(result.diagnosticIndex == 3)
    #expect(result.registryID == "codex-id")
    #expect(result.localVersion == "1.0.0")

    // Unscoped: the single `view` binds only the base registry, never a scope flag.
    let view = try #require(runner.viewArgs.first)
    #expect(view.contains("--registry=https://registry.npmjs.org/"))
    #expect(!view.contains { $0.hasPrefix("--@") && $0.contains(":registry=") })
    // Two full verifications + two registry reads + one view + one version.
    #expect(runner.count(.prefix) == 2)
    #expect(runner.count(.root) == 2)
    #expect(runner.count(.configBase) == 2)
    #expect(runner.count(.configScope) == 0)
    #expect(runner.metadataCallCount == 1)
    #expect(runner.count(.version) == 1)

    // A fresh verified comparison is persisted, and every scratch root is cleaned up.
    #expect(FileManager.default.fileExists(
        atPath: cacheDir.appendingPathComponent("npm-update-metadata-v1.json").path
    ))
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: scratchBase.path)
    #expect(leftovers.isEmpty)
}

@Test func scopedCheckBindsBothRegistryFlagsAndReportsUpToDate() async throws {
    let fixture = try NpmProbeFixture("ok-scoped", package: "@openai/codex")
    let definition = try npmProbeDefinition(executableName: "codex", package: "@openai/codex")
    let diagnostic = npmProbeWinnerDiagnostic(
        executableName: "codex", entryPath: fixture.aliasPath, version: "1.0.0"
    )
    let runner = RecordingNpmRunner(
        prefix: fixture.prefixText, root: fixture.rootText,
        scopeRegistry: "https://registry.npmjs.org/",
        viewJSON: npmProbeViewJSON(package: "@openai/codex", version: "1.0.0", latest: "1.0.0")
    )
    let cacheDir = try npmProbeScratchRoot("ok-scoped-cache")

    let result = await NpmUpdateProbe.run(
        definition: definition, diagnostic: diagnostic, environment: fixture.environment,
        runner: runner, cacheURL: cacheDir.appendingPathComponent("update-cache.json"),
        mode: .checkUpdates, currentDirectory: fixture.root.path,
        now: npmProbeFixedClock(npmProbeBaseDate), uptime: npmProbeZeroUptime(),
        stageDeadline: npmProbeFarDeadline, diagnosticIndex: 0,
        npmScratchBaseURL: npmProbeScratch(cacheDir)
    )

    #expect(npmProbeReason(result.status) == nil)  // verified, not unknown
    guard case .upToDate = result.status else {
        Issue.record("expected upToDate, got \(result.status)"); return
    }
    // Both the base and the scope registry are bound after eligibility is established.
    let view = try #require(runner.viewArgs.first)
    #expect(view.contains("--registry=https://registry.npmjs.org/"))
    #expect(view.contains("--@openai:registry=https://registry.npmjs.org/"))
    #expect(runner.count(.configScope) == 2)
}

// MARK: Registry refusal — zero metadata calls

@Test func customBaseRegistryRefusesWithZeroViewCalls() async throws {
    let fixture = try NpmProbeFixture("refuse-base", package: "codex-ai", executableName: "codex-ai")
    let definition = try npmProbeDefinition(executableName: "codex-ai", package: "codex-ai")
    let diagnostic = npmProbeWinnerDiagnostic(
        executableName: "codex-ai", entryPath: fixture.aliasPath, version: "1.0.0"
    )
    let runner = RecordingNpmRunner(
        prefix: fixture.prefixText, root: fixture.rootText,
        baseRegistry: "https://npm.example.com/",
        viewJSON: npmProbeViewJSON(package: "codex-ai", version: "2.0.0", latest: "2.0.0")
    )
    let cacheDir = try npmProbeScratchRoot("refuse-base-cache")

    let result = await NpmUpdateProbe.run(
        definition: definition, diagnostic: diagnostic, environment: fixture.environment,
        runner: runner, cacheURL: cacheDir.appendingPathComponent("update-cache.json"),
        mode: .checkUpdates, currentDirectory: fixture.root.path,
        now: npmProbeFixedClock(npmProbeBaseDate), uptime: npmProbeZeroUptime(),
        stageDeadline: npmProbeFarDeadline, diagnosticIndex: 0,
        npmScratchBaseURL: npmProbeScratch(cacheDir)
    )

    #expect(npmProbeReason(result.status) == .unsupportedRegistry)
    #expect(runner.metadataCallCount == 0)  // a custom base never reaches the metadata stage
    #expect(result.npmPackage == "codex-ai")  // identity preserved on the neutral result
    #expect(result.npmRegistry == nil)
    #expect(result.npmTag == nil)
    #expect(!FileManager.default.fileExists(
        atPath: cacheDir.appendingPathComponent("npm-update-metadata-v1.json").path
    ))
}

@Test func customScopeRegistryRefusesWithZeroViewCalls() async throws {
    let fixture = try NpmProbeFixture("refuse-scope", package: "@openai/codex")
    let definition = try npmProbeDefinition(executableName: "codex", package: "@openai/codex")
    let diagnostic = npmProbeWinnerDiagnostic(
        executableName: "codex", entryPath: fixture.aliasPath, version: "1.0.0"
    )
    let runner = RecordingNpmRunner(
        prefix: fixture.prefixText, root: fixture.rootText,
        scopeRegistry: "https://npm.internal.example/",
        viewJSON: npmProbeViewJSON(package: "@openai/codex", version: "1.0.0", latest: "1.0.0")
    )
    let cacheDir = try npmProbeScratchRoot("refuse-scope-cache")

    let result = await NpmUpdateProbe.run(
        definition: definition, diagnostic: diagnostic, environment: fixture.environment,
        runner: runner, cacheURL: cacheDir.appendingPathComponent("update-cache.json"),
        mode: .checkUpdates, currentDirectory: fixture.root.path,
        now: npmProbeFixedClock(npmProbeBaseDate), uptime: npmProbeZeroUptime(),
        stageDeadline: npmProbeFarDeadline, diagnosticIndex: 0,
        npmScratchBaseURL: npmProbeScratch(cacheDir)
    )

    #expect(npmProbeReason(result.status) == .unsupportedRegistry)
    #expect(runner.metadataCallCount == 0)
    #expect(runner.count(.configScope) == 1)  // the scope read happened, then refusal
}

// MARK: Channel and comparison policy

@Test func prereleaseLatestIsUnsupportedChannelAndNeverPersisted() async throws {
    let fixture = try NpmProbeFixture("prerelease", package: "codex-ai", executableName: "codex-ai")
    let definition = try npmProbeDefinition(executableName: "codex-ai", package: "codex-ai")
    let diagnostic = npmProbeWinnerDiagnostic(
        executableName: "codex-ai", entryPath: fixture.aliasPath, version: "1.0.0"
    )
    let runner = RecordingNpmRunner(
        prefix: fixture.prefixText, root: fixture.rootText,
        viewJSON: npmProbeViewJSON(package: "codex-ai", version: "2.0.0-beta.1", latest: "2.0.0-beta.1")
    )
    let cacheDir = try npmProbeScratchRoot("prerelease-cache")

    let result = await NpmUpdateProbe.run(
        definition: definition, diagnostic: diagnostic, environment: fixture.environment,
        runner: runner, cacheURL: cacheDir.appendingPathComponent("update-cache.json"),
        mode: .checkUpdates, currentDirectory: fixture.root.path,
        now: npmProbeFixedClock(npmProbeBaseDate), uptime: npmProbeZeroUptime(),
        stageDeadline: npmProbeFarDeadline, diagnosticIndex: 0,
        npmScratchBaseURL: npmProbeScratch(cacheDir)
    )

    #expect(npmProbeReason(result.status) == .unsupportedChannel)
    #expect(result.provenance == .freshProbe(observedAt: npmProbeBaseDate))
    // The metadata WAS fetched fresh; only the channel is unusable. An unsupported channel is
    // never persisted as a reusable record.
    #expect(!FileManager.default.fileExists(
        atPath: cacheDir.appendingPathComponent("npm-update-metadata-v1.json").path
    ))
}

@Test func installedNewerThanKnownMetadataIsUnknownAndNotPersisted() async throws {
    let fixture = try NpmProbeFixture("newer", package: "codex-ai", executableName: "codex-ai")
    let definition = try npmProbeDefinition(executableName: "codex-ai", package: "codex-ai")
    let diagnostic = npmProbeWinnerDiagnostic(
        executableName: "codex-ai", entryPath: fixture.aliasPath, version: "2.0.0"
    )
    let runner = RecordingNpmRunner(
        prefix: fixture.prefixText, root: fixture.rootText,
        viewJSON: npmProbeViewJSON(package: "codex-ai", version: "1.0.0", latest: "1.0.0")
    )
    let cacheDir = try npmProbeScratchRoot("newer-cache")

    let result = await NpmUpdateProbe.run(
        definition: definition, diagnostic: diagnostic, environment: fixture.environment,
        runner: runner, cacheURL: cacheDir.appendingPathComponent("update-cache.json"),
        mode: .checkUpdates, currentDirectory: fixture.root.path,
        now: npmProbeFixedClock(npmProbeBaseDate), uptime: npmProbeZeroUptime(),
        stageDeadline: npmProbeFarDeadline, diagnosticIndex: 0,
        npmScratchBaseURL: npmProbeScratch(cacheDir)
    )

    #expect(npmProbeReason(result.status) == .newerThanKnownMetadata)
    #expect(!FileManager.default.fileExists(
        atPath: cacheDir.appendingPathComponent("npm-update-metadata-v1.json").path
    ))
}

// MARK: Strict metadata parsing

@Test func malformedViewOutputIsMetadataInvalidWithOneViewCall() async throws {
    let cases: [(String, Data)] = [
        ("extra-key", Data(#"{"name":"codex-ai","version":"2.0.0","dist-tags.latest":"2.0.0","extra":"x"}"#.utf8)),
        ("nested-tag", Data(#"{"name":"codex-ai","version":"2.0.0","dist-tags":{"latest":"2.0.0"}}"#.utf8)),
        ("name-mismatch", npmProbeViewJSON(package: "someone-else", version: "2.0.0", latest: "2.0.0")),
        ("version-diverges", npmProbeViewJSON(package: "codex-ai", version: "1.0.0", latest: "2.0.0")),
    ]
    for (label, payload) in cases {
        let fixture = try NpmProbeFixture("bad-\(label)", package: "codex-ai", executableName: "codex-ai")
        let definition = try npmProbeDefinition(executableName: "codex-ai", package: "codex-ai")
        let diagnostic = npmProbeWinnerDiagnostic(
            executableName: "codex-ai", entryPath: fixture.aliasPath, version: "1.0.0"
        )
        let runner = RecordingNpmRunner(
            prefix: fixture.prefixText, root: fixture.rootText, viewJSON: payload
        )
        let cacheDir = try npmProbeScratchRoot("bad-\(label)-cache")

        let result = await NpmUpdateProbe.run(
            definition: definition, diagnostic: diagnostic, environment: fixture.environment,
            runner: runner, cacheURL: cacheDir.appendingPathComponent("update-cache.json"),
            mode: .checkUpdates, currentDirectory: fixture.root.path,
            now: npmProbeFixedClock(npmProbeBaseDate), uptime: npmProbeZeroUptime(),
            stageDeadline: npmProbeFarDeadline, diagnosticIndex: 0,
            npmScratchBaseURL: npmProbeScratch(cacheDir)
        )

        #expect(npmProbeReason(result.status) == .metadataInvalid, "\(label)")
        #expect(runner.metadataCallCount == 1, "\(label)")
        #expect(result.npmRegistry == "https://registry.npmjs.org/", "\(label)")
    }
}

// MARK: Cache hit — no metadata call, still revalidates

@Test func checkCacheHitSkipsViewAndPreservesOriginalObservation() async throws {
    let fixture = try NpmProbeFixture("cache-hit", package: "codex-ai", executableName: "codex-ai")
    let definition = try npmProbeDefinition(executableName: "codex-ai", package: "codex-ai")
    let diagnostic = npmProbeWinnerDiagnostic(
        executableName: "codex-ai", entryPath: fixture.aliasPath, version: "1.0.0"
    )
    let cacheDir = try npmProbeScratchRoot("cache-hit-cache")
    let cacheURL = cacheDir.appendingPathComponent("update-cache.json")
    let later = npmProbeBaseDate.addingTimeInterval(60)

    // Populate via Refresh (always re-fetches) at the original observation time.
    let seed = RecordingNpmRunner(
        prefix: fixture.prefixText, root: fixture.rootText,
        viewJSON: npmProbeViewJSON(package: "codex-ai", version: "2.0.0", latest: "2.0.0")
    )
    let refreshResult = await NpmUpdateProbe.run(
        definition: definition, diagnostic: diagnostic, environment: fixture.environment,
        runner: seed, cacheURL: cacheURL, mode: .refresh, currentDirectory: fixture.root.path,
        now: npmProbeFixedClock(npmProbeBaseDate), uptime: npmProbeZeroUptime(),
        stageDeadline: npmProbeFarDeadline, diagnosticIndex: 0,
        npmScratchBaseURL: npmProbeScratch(cacheDir, "scratch-a")
    )
    #expect(seed.metadataCallCount == 1)  // Refresh fetched
    guard case .updateAvailable = refreshResult.status else {
        Issue.record("refresh should fetch an updateAvailable"); return
    }

    // A Check on the same identity within TTL uses the stored metadata without a `view` call.
    let check = RecordingNpmRunner(
        prefix: fixture.prefixText, root: fixture.rootText,
        viewJSON: npmProbeViewJSON(package: "codex-ai", version: "9.9.9", latest: "9.9.9")
    )
    let checkResult = await NpmUpdateProbe.run(
        definition: definition, diagnostic: diagnostic, environment: fixture.environment,
        runner: check, cacheURL: cacheURL, mode: .checkUpdates, currentDirectory: fixture.root.path,
        now: npmProbeFixedClock(later), uptime: npmProbeZeroUptime(),
        stageDeadline: npmProbeFarDeadline, diagnosticIndex: 0,
        npmScratchBaseURL: npmProbeScratch(cacheDir, "scratch-b")
    )
    #expect(check.metadataCallCount == 0)  // the hit never launches a metadata query
    // Ownership and registry validation still ran on the hit.
    #expect(check.count(.prefix) == 2)
    #expect(check.count(.configBase) == 2)
    // The stored metadata (2.0.0) — not the fresh-but-unused 9.9.9 — drives the comparison, and the
    // original observation time is preserved.
    guard case .updateAvailable(_, let latest) = checkResult.status else {
        Issue.record("cache hit should still report updateAvailable 2.0.0"); return
    }
    #expect(latest.text == "2.0.0")
    #expect(checkResult.provenance == .cache(observedAt: npmProbeBaseDate))
}

// MARK: R06 — a stored identity match is not proof of valid metadata

/// Rewrites one stored entry's `version` in place, simulating a document that still decodes and
/// still matches the selection identity but no longer carries what this flow ever verified.
private func tamperStoredNpmMetadataVersion(_ data: Data, to version: String) throws -> Data {
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          var entries = object["entries"] as? [[String: Any]],
          var entry = entries.first
    else {
        throw NSError(domain: "NpmProbeTests", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "seeded npm document is malformed"])
    }
    entry["version"] = version
    entries[0] = entry
    var mutated = object
    mutated["entries"] = entries
    return try JSONSerialization.data(withJSONObject: mutated, options: [.sortedKeys])
}

@Test func tamperedCacheRecordRefusesTheHitAndRefetchesBoundedOnce() async throws {
    let fixture = try NpmProbeFixture("tampered-hit", package: "codex-ai", executableName: "codex-ai")
    let definition = try npmProbeDefinition(executableName: "codex-ai", package: "codex-ai")
    let diagnostic = npmProbeWinnerDiagnostic(
        executableName: "codex-ai", entryPath: fixture.aliasPath, version: "1.0.0"
    )
    let cacheDir = try npmProbeScratchRoot("tampered-hit-cache")
    let cacheURL = cacheDir.appendingPathComponent("update-cache.json")
    let metadataURL = cacheDir.appendingPathComponent("npm-update-metadata-v1.json")

    // Seed one genuinely verified observation through the normal publish path (Refresh always
    // re-fetches), so the identity in the document is exactly the one a later Check will compute.
    let seed = RecordingNpmRunner(
        prefix: fixture.prefixText, root: fixture.rootText,
        viewJSON: npmProbeViewJSON(package: "codex-ai", version: "2.0.0", latest: "2.0.0")
    )
    _ = await NpmUpdateProbe.run(
        definition: definition, diagnostic: diagnostic, environment: fixture.environment,
        runner: seed, cacheURL: cacheURL, mode: .refresh, currentDirectory: fixture.root.path,
        now: npmProbeFixedClock(npmProbeBaseDate), uptime: npmProbeZeroUptime(),
        stageDeadline: npmProbeFarDeadline, diagnosticIndex: 0,
        npmScratchBaseURL: npmProbeScratch(cacheDir, "scratch-a")
    )
    #expect(seed.metadataCallCount == 1)

    // Tamper the stored metadata: the identity still matches, the document still decodes, but the
    // recorded `version` is now a prerelease the fresh parser would never have accepted.
    let tampered = try tamperStoredNpmMetadataVersion(Data(contentsOf: metadataURL), to: "2.0.0-rc.1")
    try tampered.write(to: metadataURL)

    let check = RecordingNpmRunner(
        prefix: fixture.prefixText, root: fixture.rootText,
        viewJSON: npmProbeViewJSON(package: "codex-ai", version: "2.0.0", latest: "2.0.0")
    )
    let result = await NpmUpdateProbe.run(
        definition: definition, diagnostic: diagnostic, environment: fixture.environment,
        runner: check, cacheURL: cacheURL, mode: .checkUpdates, currentDirectory: fixture.root.path,
        now: npmProbeFixedClock(npmProbeBaseDate), uptime: npmProbeZeroUptime(),
        stageDeadline: npmProbeFarDeadline, diagnosticIndex: 0,
        npmScratchBaseURL: npmProbeScratch(cacheDir, "scratch-b")
    )

    // The poisoned record cannot support a claim: exactly one fresh bounded metadata query ran.
    #expect(check.metadataCallCount == 1)
    guard case .updateAvailable(_, let latest) = result.status else {
        Issue.record("tampered hit should refetch and report updateAvailable 2.0.0"); return
    }
    #expect(latest.text == "2.0.0")
    // Fresh evidence, never a cache provenance borrowed from a record this flow refused.
    #expect(result.provenance == .freshProbe(observedAt: npmProbeBaseDate))

    // The verified fresh observation repairs the identity for the next scan.
    let repaired = String(decoding: try Data(contentsOf: metadataURL), as: UTF8.self)
    #expect(!repaired.contains("2.0.0-rc.1"))
    let followUp = RecordingNpmRunner(
        prefix: fixture.prefixText, root: fixture.rootText,
        viewJSON: npmProbeViewJSON(package: "codex-ai", version: "9.9.9", latest: "9.9.9")
    )
    let followUpResult = await NpmUpdateProbe.run(
        definition: definition, diagnostic: diagnostic, environment: fixture.environment,
        runner: followUp, cacheURL: cacheURL, mode: .checkUpdates, currentDirectory: fixture.root.path,
        now: npmProbeFixedClock(npmProbeBaseDate.addingTimeInterval(60)), uptime: npmProbeZeroUptime(),
        stageDeadline: npmProbeFarDeadline, diagnosticIndex: 0,
        npmScratchBaseURL: npmProbeScratch(cacheDir, "scratch-c")
    )
    #expect(followUp.metadataCallCount == 0)  // repaired record is a legitimate hit
    guard case .updateAvailable(_, let restored) = followUpResult.status else {
        Issue.record("repaired record should support the stored 2.0.0 comparison"); return
    }
    #expect(restored.text == "2.0.0")
    #expect(followUpResult.provenance == .cache(observedAt: npmProbeBaseDate))
}

// MARK: Stage budget

@Test func exhaustedStageStopsAfterInitialOwnershipAndPreservesIdentity() async throws {
    let fixture = try NpmProbeFixture("budget", package: "codex-ai", executableName: "codex-ai")
    let definition = try npmProbeDefinition(executableName: "codex-ai", package: "codex-ai")
    let diagnostic = npmProbeWinnerDiagnostic(
        executableName: "codex-ai", entryPath: fixture.aliasPath, version: "1.0.0"
    )
    let runner = RecordingNpmRunner(
        prefix: fixture.prefixText, root: fixture.rootText,
        viewJSON: npmProbeViewJSON(package: "codex-ai", version: "2.0.0", latest: "2.0.0")
    )
    let cacheDir = try npmProbeScratchRoot("budget-cache")

    // A deadline already in the past (uptime 1 >= stageDeadline 0) fails immediately after the
    // initial ownership verification and before any registry or metadata call.
    let result = await NpmUpdateProbe.run(
        definition: definition, diagnostic: diagnostic, environment: fixture.environment,
        runner: runner, cacheURL: cacheDir.appendingPathComponent("update-cache.json"),
        mode: .checkUpdates, currentDirectory: fixture.root.path,
        now: npmProbeFixedClock(npmProbeBaseDate), uptime: { 1 },
        stageDeadline: 0, diagnosticIndex: 5,
        npmScratchBaseURL: npmProbeScratch(cacheDir)
    )

    #expect(npmProbeReason(result.status) == .budgetExhausted)
    #expect(runner.metadataCallCount == 0)
    #expect(runner.count(.configBase) == 0)
    // Only the single initial ownership verification ran (prefix + root) before the guard failed;
    // the pre-publication re-verification and every registry/metadata call are skipped.
    #expect(runner.count(.prefix) == 1)
    #expect(runner.count(.root) == 1)
    // Identity of the same tool is preserved on the neutral budget result.
    #expect(result.registryID == "codex-id")
    #expect(result.displayName == "Codex")
    #expect(result.diagnosticIndex == 5)
    #expect(result.localVersion == "1.0.0")
    #expect(result.npmPackage == "codex-ai")
    #expect(result.selectedEntryPath == fixture.aliasPath)
}

// MARK: Zero-command neutral outcomes

@Test func missingSelectionLaunchesNoCommands() async throws {
    let definition = try npmProbeDefinition(executableName: "codex", package: "@openai/codex")
    let inconsistent = ToolPathDiagnostic(
        detectedTool: DetectedTool(
            displayName: "Codex", executableName: "codex", state: .installedAndOnPath,
            entryPath: "/synthetic/codex", resolvedPath: nil, source: "npm", version: "1.0.0"
        ),
        pathCandidates: [], firstLiveCandidate: nil, targetGroups: [],
        repeatedPathSlotCount: 1, sameTargetAliasCount: 0,
        selection: .inconsistent("repeated PATH slot"), shadowedInstallationCount: nil,
        installationVersions: []
    )
    let runner = RecordingNpmRunner(
        prefix: "/no/prefix", root: "/no/root",
        viewJSON: npmProbeViewJSON(package: "@openai/codex", version: "2.0.0", latest: "2.0.0")
    )
    let result = await NpmUpdateProbe.run(
        definition: definition, diagnostic: inconsistent,
        environment: npmProbeEnvironment(pathEntries: ["/synthetic/bin"]),
        runner: runner, cacheURL: try npmProbeScratchRoot("missing-sel"),
        mode: .checkUpdates, currentDirectory: "/",
        now: npmProbeFixedClock(npmProbeBaseDate), uptime: npmProbeZeroUptime(),
        stageDeadline: npmProbeFarDeadline, diagnosticIndex: 0
    )
    #expect(npmProbeReason(result.status) == .installedVersionUnavailable)
    #expect(runner.recordedCount == 0)
}

@Test func managerAbsentFromPathLaunchesNoCommands() async throws {
    let fixture = try NpmProbeFixture("no-manager", package: "codex-ai", executableName: "codex-ai")
    let definition = try npmProbeDefinition(executableName: "codex-ai", package: "codex-ai")
    let diagnostic = npmProbeWinnerDiagnostic(
        executableName: "codex-ai", entryPath: fixture.aliasPath, version: "1.0.0"
    )
    // No `npm` anywhere on the search PATH.
    let environment = npmProbeEnvironment(pathEntries: ["/definitely/not/here"])
    let runner = RecordingNpmRunner(
        prefix: fixture.prefixText, root: fixture.rootText,
        viewJSON: npmProbeViewJSON(package: "codex-ai", version: "2.0.0", latest: "2.0.0")
    )
    let result = await NpmUpdateProbe.run(
        definition: definition, diagnostic: diagnostic, environment: environment,
        runner: runner, cacheURL: try npmProbeScratchRoot("no-manager-cache"),
        mode: .checkUpdates, currentDirectory: fixture.root.path,
        now: npmProbeFixedClock(npmProbeBaseDate), uptime: npmProbeZeroUptime(),
        stageDeadline: npmProbeFarDeadline, diagnosticIndex: 0,
        npmScratchBaseURL: try npmProbeScratchRoot("no-manager-scratch")
    )
    #expect(npmProbeReason(result.status) == .managerUnavailable)
    #expect(runner.recordedCount == 0)
    // The selection identity is still carried — an unknown is about the same tool.
    #expect(result.selectedEntryPath == fixture.aliasPath)
    #expect(result.localVersion == "1.0.0")
}


// MARK: - R1 corrections regressions (coordinator briefs R01–R04)
//
// These cases exercise the four blocking corrections directly against the probe:
//   - R01: a LATER declaration is the verified match; the first declaration never authorizes a
//     lookup, and an ambiguous match launches nothing.
//   - R02: every scoped verified package pins BOTH registry flags even when the scope config
//     reports the measured unset value; a blank scope output is malformed and refuses.
//   - R03: the proof digest covers directory/file/executable identity, so a same-path manifest or
//     bin replacement, a replaced manager, or a replaced root directory can never reuse a prior
//     proof's cached metadata.
//   - R04: after the LAST external query and immediately before cache commit/publication, the
//     live proof must revalidate; a replacement in that window refuses, an exhausted aggregate
//     deadline maps to budgetExhausted, and nothing is published or persisted either way.
//
// Scripted-call ordinals below assume the probe's observable npm sequence:
//   unscoped Check miss: 1 prefix, 2 root, 3 base config, 4 view, 5 version,
//                        6 prefix, 7 root, 8 base config (LAST external query)
//   scoped Check miss:   ... 4 scope config, 5 view, 6 version, 8 prefix, 9 root,
//                        10 base config, 11 scope config (LAST external query)
//   Check cache hit:     the view step is absent; the scope/base config is still last.

private func npmProbeRunMulti(
    fixture: NpmProbeFixture, names: [String], runner: any UpdateCommandRunner,
    cacheURL: URL, mode: UpdateProbeMode, scratchBase: URL,
    now: @escaping @Sendable () -> Date = npmProbeFixedClock(npmProbeBaseDate),
    uptime: @escaping @Sendable () -> UInt64 = npmProbeZeroUptime(),
    stageDeadline: UInt64 = npmProbeFarDeadline
) async -> ToolUpdateResult {
    let definition = try! DetectorDefinition(
        id: "codex-id", displayName: "Codex", executableName: fixture.executableName,
        extraSearchRoots: [], fixture: nil, category: .aiAgent,
        packages: names.map { try! DeclaredPackage(manager: .npm, name: $0) },
        informationURL: nil, uninstallInstructionsURL: nil, versionQuery: .standard
    )
    let diagnostic = npmProbeWinnerDiagnostic(
        executableName: fixture.executableName, entryPath: fixture.aliasPath, version: "1.0.0"
    )
    return await NpmUpdateProbe.run(
        definition: definition, diagnostic: diagnostic, environment: fixture.environment,
        runner: runner, cacheURL: cacheURL, mode: mode, currentDirectory: fixture.root.path,
        now: now, uptime: uptime, stageDeadline: stageDeadline, diagnosticIndex: 0,
        npmScratchBaseURL: scratchBase
    )
}

private func npmProbeCacheURL(_ cacheDir: URL) -> URL {
    cacheDir.appendingPathComponent("update-cache.json")
}

private func npmProbeScratch(_ cacheDir: URL, _ tag: String = "scratch") -> URL {
    let url = cacheDir.appendingPathComponent(tag, isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Reads the persisted npm metadata document's proof fingerprints. Returns an empty array when
/// the document is absent, unreadable, or malformed — callers assert on `.count`/equality, so a
/// missing record still fails the test loudly without a throwing expression inside `#require`.
private func npmProbeStoredProofFingerprints(cacheDir: URL) -> [String] {
    let url = cacheDir.appendingPathComponent("npm-update-metadata-v1.json")
    guard let data = try? Data(contentsOf: url) else { return [] }
    struct Doc: Decodable {
        struct E: Decodable { let proofFingerprint: String }
        let entries: [E]
    }
    return (try? JSONDecoder().decode(Doc.self, from: data))?.entries.map(\.proofFingerprint) ?? []
}

private func npmProbeMetadataDocExists(cacheDir: URL) -> Bool {
    FileManager.default.fileExists(
        atPath: cacheDir.appendingPathComponent("npm-update-metadata-v1.json").path
    )
}

private func npmProbeReplaceExecutable(at url: URL, content: String) throws {
    try Data(content.utf8).write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
}

// MARK: R01 — verified identity comes from the matched declaration, never the first

@Test func laterDeclarationMatchUsesVerifiedPackageNameForEveryLookup() async throws {
    let fixture = try NpmProbeFixture("r01-second", package: "@openai/codex")
    // The shipped OpenCode layout declares multiple npm alternatives; only the LATER one is
    // actually installed in the verified prefix.
    let runner = RecordingNpmRunner(
        prefix: fixture.prefixText, root: fixture.rootText,
        viewJSON: npmProbeViewJSON(package: "@openai/codex", version: "2.0.0", latest: "2.0.0")
    )
    let cacheDir = try npmProbeScratchRoot("r01-second-cache")
    let result = await npmProbeRunMulti(
        fixture: fixture, names: ["@missing/not-installed", "@openai/codex"], runner: runner,
        cacheURL: npmProbeCacheURL(cacheDir), mode: .checkUpdates,
        scratchBase: npmProbeScratch(cacheDir)
    )
    // The published identity is the VERIFIED matched package, not the first declaration.
    #expect(result.npmPackage == "@openai/codex")
    guard case .updateAvailable = result.status else {
        Issue.record("expected updateAvailable for the verified package, got \(result.status)"); return
    }
    // Exactly one view, for the verified name. The unmatched declaration was never queried and
    // cannot borrow another package's metadata; scope resolution is for the verified scope only.
    #expect(runner.metadataCallCount == 1)
    let view = try #require(runner.viewArgs.first)
    #expect(view.contains("@openai/codex@latest"))
    #expect(!view.contains { $0.contains("@missing/not-installed") })
    #expect(!runner.recordedArguments.contains { $0.contains("@missing:registry") })
    #expect(runner.count(.configScope) == 2)
}

@Test func unmatchedDeclarationAuthorizesZeroLookupsAndPersistsNothing() async throws {
    // R01 guard, expressed through the layout validated metadata can actually produce. A true
    // multi-match ambiguity never reaches the probe: DetectorDefinition rejects duplicate
    // (manager, name) declarations, and the strict-descendant bin rule forbids two distinct
    // installed packages from both owning one selection. What DOES reach it is a declaration that
    // matches no installed package. That declaration must verify nothing, authorize no registry
    // lookup, launch zero config/view commands, persist nothing, and never borrow another
    // package's metadata — displaying its name only as an inert placeholder.
    let fixture = try NpmProbeFixture("r01-nomatch", package: "@openai/codex")
    let runner = RecordingNpmRunner(
        prefix: fixture.prefixText, root: fixture.rootText,
        viewJSON: npmProbeViewJSON(package: "@openai/codex", version: "2.0.0", latest: "2.0.0")
    )
    let cacheDir = try npmProbeScratchRoot("r01-nomatch-cache")
    let result = await npmProbeRunMulti(
        fixture: fixture, names: ["@missing/not-installed"], runner: runner,
        cacheURL: npmProbeCacheURL(cacheDir), mode: .checkUpdates,
        scratchBase: npmProbeScratch(cacheDir)
    )
    // Never a verified claim — an unknown typed reason.
    #expect(npmProbeReason(result.status) != nil)
    // Zero registry traffic authorized: no config route read, no metadata view.
    #expect(runner.count(.configBase) == 0)
    #expect(runner.metadataCallCount == 0)
    // Nothing persisted.
    #expect(!npmProbeMetadataDocExists(cacheDir: cacheDir))
    // The unmatched name appears only as a placeholder; it never drove a lookup (view count 0).
    #expect(result.npmPackage == "@missing/not-installed")
}

// MARK: R02 — scoped pinning on the unset path; blank scope refuses

@Test func scopedUnsetConfigStillPinsBothRegistryFlags() async throws {
    let fixture = try NpmProbeFixture("r02-unset-pin", package: "@openai/codex")
    let runner = RecordingNpmRunner(
        prefix: fixture.prefixText, root: fixture.rootText,
        scopeRegistry: "undefined",  // the ordinary unset-scope measurement
        viewJSON: npmProbeViewJSON(package: "@openai/codex", version: "2.0.0", latest: "2.0.0")
    )
    let cacheDir = try npmProbeScratchRoot("r02-unset-pin-cache")
    let result = await npmProbeRunMulti(
        fixture: fixture, names: ["@openai/codex"], runner: runner,
        cacheURL: npmProbeCacheURL(cacheDir), mode: .checkUpdates,
        scratchBase: npmProbeScratch(cacheDir)
    )
    guard case .updateAvailable = result.status else {
        Issue.record("expected updateAvailable, got \(result.status)"); return
    }
    let view = try #require(runner.viewArgs.first)
    // B02.4: BOTH flags bound on the unset-scope path — the scoped flag pins the accepted public
    // origin because a user-level scope override outranks the base registry flag alone.
    #expect(view.contains("--registry=https://registry.npmjs.org/"))
    #expect(view.contains("--@openai:registry=https://registry.npmjs.org/"))
}

@Test func blankScopeOutputRefusesAsMalformedWithZeroViewCalls() async throws {
    let fixture = try NpmProbeFixture("r02-blank-scope", package: "@openai/codex")
    let runner = RecordingNpmRunner(
        prefix: fixture.prefixText, root: fixture.rootText,
        scopeRegistry: "  ",  // blank/whitespace is NOT the measured unset value
        viewJSON: npmProbeViewJSON(package: "@openai/codex", version: "2.0.0", latest: "2.0.0")
    )
    let cacheDir = try npmProbeScratchRoot("r02-blank-scope-cache")
    let result = await npmProbeRunMulti(
        fixture: fixture, names: ["@openai/codex"], runner: runner,
        cacheURL: npmProbeCacheURL(cacheDir), mode: .checkUpdates,
        scratchBase: npmProbeScratch(cacheDir)
    )
    #expect(npmProbeReason(result.status) == .unsupportedRegistry)
    #expect(runner.metadataCallCount == 0)
    #expect(!npmProbeMetadataDocExists(cacheDir: cacheDir))
}

// MARK: R03 — identity changes must never reuse a prior proof's cached metadata

@Test func samePathManifestReplacementNeverReusesCachedProofMetadata() async throws {
    let fixture = try NpmProbeFixture("r03-manifest", package: "@openai/codex")
    let cacheDir = try npmProbeScratchRoot("r03-manifest-cache")
    let cacheURL = npmProbeCacheURL(cacheDir)
    let scratch = npmProbeScratch(cacheDir)
    let manifestURL = fixture.globalRoot
        .appendingPathComponent("@openai/codex", isDirectory: true)
        .appendingPathComponent("package.json")

    // Seed one cached observation under the manifest's ORIGINAL identity.
    let seed = RecordingNpmRunner(
        prefix: fixture.prefixText, root: fixture.rootText,
        viewJSON: npmProbeViewJSON(package: "@openai/codex", version: "2.0.0", latest: "2.0.0")
    )
    _ = await npmProbeRunMulti(
        fixture: fixture, names: ["@openai/codex"], runner: seed, cacheURL: cacheURL,
        mode: .refresh, scratchBase: scratch
    )
    let seededProofs = npmProbeStoredProofFingerprints(cacheDir: cacheDir)
    #expect(seededProofs.count == 1)

    // Atomically replace package.json at the SAME path with the same valid content plus a newline.
    let old = try Data(contentsOf: manifestURL)
    try (old + Data([0x0A])).write(to: manifestURL, options: .atomic)

    // The exact B04.2 window: a Check whose fresh proof now carries the REPLACED manifest identity.
    let check = RecordingNpmRunner(
        prefix: fixture.prefixText, root: fixture.rootText,
        viewJSON: npmProbeViewJSON(package: "@openai/codex", version: "3.0.0", latest: "3.0.0")
    )
    let result = await npmProbeRunMulti(
        fixture: fixture, names: ["@openai/codex"], runner: check, cacheURL: cacheURL,
        mode: .checkUpdates, scratchBase: scratch
    )
    // The prior proof's metadata is never reused: the changed manifest identity produces a
    // different key, so the hit becomes a fresh observation.
    #expect(check.metadataCallCount == 1)
    guard case .updateAvailable(_, let latest) = result.status else {
        Issue.record("expected a fresh updateAvailable, got \(result.status)"); return
    }
    #expect(latest.text == "3.0.0")
    #expect(result.provenance == .freshProbe(observedAt: npmProbeBaseDate))
    let storedProofs = npmProbeStoredProofFingerprints(cacheDir: cacheDir)
    // No reuse of the stale record: a fresh, distinct identity was published alongside it. The
    // old record is preserved (its key no longer matches) — proof the changed identity could not
    // borrow it — while exactly one new fingerprint entered the document.
    #expect(Set(storedProofs).subtracting(seededProofs).count == 1)

    // Restore the manifest exactly (coordinator repro parity).
    try old.write(to: manifestURL, options: .atomic)
}

@Test func samePathBinReplacementInvalidatesCacheHitWithFreshView() async throws {
    let fixture = try NpmProbeFixture("r03-bin", package: "@openai/codex")
    let cacheDir = try npmProbeScratchRoot("r03-bin-cache")
    let cacheURL = npmProbeCacheURL(cacheDir)
    let scratch = npmProbeScratch(cacheDir)
    let binURL = fixture.target

    let seed = RecordingNpmRunner(
        prefix: fixture.prefixText, root: fixture.rootText,
        viewJSON: npmProbeViewJSON(package: "@openai/codex", version: "2.0.0", latest: "2.0.0")
    )
    _ = await npmProbeRunMulti(
        fixture: fixture, names: ["@openai/codex"], runner: seed, cacheURL: cacheURL,
        mode: .refresh, scratchBase: scratch
    )

    // Replace the bound bin at the same path (new inode/fingerprint, same content plus a line).
    let old = try Data(contentsOf: binURL)
    try npmProbeReplaceExecutable(
        at: binURL, content: String(decoding: old, as: UTF8.self) + "\n"
    )

    let check = RecordingNpmRunner(
        prefix: fixture.prefixText, root: fixture.rootText,
        viewJSON: npmProbeViewJSON(package: "@openai/codex", version: "3.0.0", latest: "3.0.0")
    )
    let result = await npmProbeRunMulti(
        fixture: fixture, names: ["@openai/codex"], runner: check, cacheURL: cacheURL,
        mode: .checkUpdates, scratchBase: scratch
    )
    #expect(check.metadataCallCount == 1)  // no cached-proof reuse
    #expect(result.provenance != .cache(observedAt: npmProbeBaseDate))
    #expect(npmProbeReason(result.status) == nil)
    try old.write(to: binURL, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binURL.path)
}

@Test func replacedRootDirectoryRefusesNeverReusingPriorProof() async throws {
    let fixture = try NpmProbeFixture("r03-root", package: "@openai/codex")
    let cacheDir = try npmProbeScratchRoot("r03-root-cache")
    let cacheURL = npmProbeCacheURL(cacheDir)
    let scratch = npmProbeScratch(cacheDir)

    let seed = RecordingNpmRunner(
        prefix: fixture.prefixText, root: fixture.rootText,
        viewJSON: npmProbeViewJSON(package: "@openai/codex", version: "2.0.0", latest: "2.0.0")
    )
    _ = await npmProbeRunMulti(
        fixture: fixture, names: ["@openai/codex"], runner: seed, cacheURL: cacheURL,
        mode: .refresh, scratchBase: scratch
    )

    // Directory replacement at the same path: a NEW (empty) directory where the manager's root
    // was. No package can verify against the replaced root, so the prior proof is refused
    // outright rather than reused.
    let aside = fixture.root.appendingPathComponent("root-aside", isDirectory: true)
    try FileManager.default.moveItem(at: fixture.globalRoot, to: aside)
    try FileManager.default.createDirectory(at: fixture.globalRoot, withIntermediateDirectories: true)

    let check = RecordingNpmRunner(
        prefix: fixture.prefixText, root: fixture.rootText,
        viewJSON: npmProbeViewJSON(package: "@openai/codex", version: "3.0.0", latest: "3.0.0")
    )
    let result = await npmProbeRunMulti(
        fixture: fixture, names: ["@openai/codex"], runner: check, cacheURL: cacheURL,
        mode: .checkUpdates, scratchBase: scratch
    )
    #expect(check.metadataCallCount == 0)
    #expect(npmProbeReason(result.status) == .identityUnverified)
    // The stored document is untouched: no new publication borrowed the replaced directory.
    let storedProofs = npmProbeStoredProofFingerprints(cacheDir: cacheDir)
    #expect(storedProofs.count == 1)
}

@Test func replacedManagerCannotReusePriorProofIdentity() async throws {
    let fixture = try NpmProbeFixture("r03-manager", package: "@openai/codex")
    let cacheDir = try npmProbeScratchRoot("r03-manager-cache")
    let cacheURL = npmProbeCacheURL(cacheDir)
    let scratch = npmProbeScratch(cacheDir)

    let seed = RecordingNpmRunner(
        prefix: fixture.prefixText, root: fixture.rootText,
        viewJSON: npmProbeViewJSON(package: "@openai/codex", version: "2.0.0", latest: "2.0.0")
    )
    _ = await npmProbeRunMulti(
        fixture: fixture, names: ["@openai/codex"], runner: seed, cacheURL: cacheURL,
        mode: .refresh, scratchBase: scratch
    )
    let seededProofs = npmProbeStoredProofFingerprints(cacheDir: cacheDir)

    // The manager entry is replaced at the same path before the next Check. The stored proof was
    // recorded under the OLD manager identity; a hit must never be taken with the new one.
    let managerURL = fixture.managerDirectory.appendingPathComponent("npm")
    try npmProbeReplaceExecutable(at: managerURL, content: "#!/bin/sh\nexit 0 # replaced\n")

    let check = RecordingNpmRunner(
        prefix: fixture.prefixText, root: fixture.rootText,
        viewJSON: npmProbeViewJSON(package: "@openai/codex", version: "3.0.0", latest: "3.0.0")
    )
    let result = await npmProbeRunMulti(
        fixture: fixture, names: ["@openai/codex"], runner: check, cacheURL: cacheURL,
        mode: .checkUpdates, scratchBase: scratch
    )
    // The prior proof metadata is NOT reused: the run either fails closed on identity or, at
    // worst, re-observes everything from scratch — never a cached provenance.
    #expect(result.provenance != .cache(observedAt: npmProbeBaseDate))
    #expect(check.metadataCallCount == 1)
    let storedProofs = npmProbeStoredProofFingerprints(cacheDir: cacheDir)
    // No reuse of the stale record: a fresh, distinct identity was published alongside it. The
    // old record is preserved (its key no longer matches) — proof the changed identity could not
    // borrow it — while exactly one new fingerprint entered the document.
    #expect(Set(storedProofs).subtracting(seededProofs).count == 1)
}

// MARK: R04 — the final-query window

/// Shared mutable monotonic clock so a scripted response can exhaust the aggregate stage
/// deadline exactly like a slow final query would.
private final class NpmProbeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 0
    func get() -> UInt64 { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ next: UInt64) { lock.lock(); value = next; lock.unlock() }
}

/// A recording runner that fires a mutation immediately AFTER the nth scripted response and then
/// exhausts a shared clock — the deterministic stand-in for the coordinator's external-review
/// replacements in the final-query window.
private final class GatedScriptedNpmRunner: RecordingNpmRunner, @unchecked Sendable {
    private let fireLock = NSLock()
    private var remaining = 0
    private var hook: (() -> Void)?
    private let clock: NpmProbeClock
    private let exhaustValue: UInt64

    init(
        prefix: String, root: String, viewJSON: Data, clock: NpmProbeClock,
        exhaustValue: UInt64 = 1_000
    ) {
        self.clock = clock
        self.exhaustValue = exhaustValue
        super.init(prefix: prefix, root: root, viewJSON: viewJSON)
    }

    func fireAfter(_ nth: Int, hook: @escaping () -> Void) {
        fireLock.lock(); defer { fireLock.unlock() }
        remaining = nth
        self.hook = hook
    }

    /// Synchronously decides whether THIS invocation is the nth, firing the gate hook exactly once
    /// (when the decrement brings the remaining count to zero) rather than on every call while a
    /// budget remains. All `NSLock` use lives here in a non-async method so the async `run` body
    /// never touches the lock directly.
    private func consumeFireGate() -> (() -> Void)? {
        fireLock.lock(); defer { fireLock.unlock() }
        guard remaining > 0 else { return nil }
        remaining -= 1
        return remaining == 0 ? hook : nil
    }

    override func run(
        executablePath: String, arguments: [String],
        environment: [String: String], timeout: TimeInterval
    ) async -> CommandOutcome {
        let outcome = await super.run(
            executablePath: executablePath, arguments: arguments,
            environment: environment, timeout: timeout
        )
        if let fire = consumeFireGate() {
            fire()
            clock.set(exhaustValue)
        }
        return outcome
    }
}

/// Runs a far-deadline, zero-uptime cache-hit Check with a plain recording runner and returns the
/// total number of npm commands the probe issues on that path. Because the metadata view is skipped
/// on a cache hit, this equals the ordinal of the LAST external query — exactly where an R04 window
/// mutation must land to be caught by the final live gate rather than an early step.
private func npmProbeLastQueryOrdinal(
    fixture: NpmProbeFixture, cacheURL: URL, scratch: URL
) async -> Int {
    let recorder = RecordingNpmRunner(
        prefix: fixture.prefixText, root: fixture.rootText,
        viewJSON: npmProbeViewJSON(package: "@openai/codex", version: "2.0.0", latest: "2.0.0")
    )
    _ = await npmProbeRunMulti(
        fixture: fixture, names: ["@openai/codex"], runner: recorder, cacheURL: cacheURL,
        mode: .checkUpdates, scratchBase: scratch
    )
    return recorder.recordedArguments.count
}

@Test func selectionReplacementDuringFinalScopeReadRefusesAndPersistsNothing() async throws {
    let fixture = try NpmProbeFixture("r04-window-replace", package: "@openai/codex")
    let cacheDir = try npmProbeScratchRoot("r04-window-replace-cache")
    let cacheURL = npmProbeCacheURL(cacheDir)
    let scratch = npmProbeScratch(cacheDir)

    let seed = RecordingNpmRunner(
        prefix: fixture.prefixText, root: fixture.rootText,
        viewJSON: npmProbeViewJSON(package: "@openai/codex", version: "2.0.0", latest: "2.0.0")
    )
    _ = await npmProbeRunMulti(
        fixture: fixture, names: ["@openai/codex"], runner: seed, cacheURL: cacheURL,
        mode: .refresh, scratchBase: scratch
    )
    let seededProofs = npmProbeStoredProofFingerprints(cacheDir: cacheDir)
    // Learn where the last external query lands for this exact cache-hit sequence.
    let lastQuery = await npmProbeLastQueryOrdinal(
        fixture: fixture, cacheURL: cacheURL, scratch: scratch
    )
    #expect(lastQuery > 0)

    // Replace the selected/bin executable atomically immediately AFTER the final registry query —
    // exactly the coordinator's `replacement-after-final-proof` window. The clock moves, but stays
    // inside the stage deadline, so only the final live-gate revalidation can observe it.
    let clock = NpmProbeClock()
    let runner = GatedScriptedNpmRunner(
        prefix: fixture.prefixText, root: fixture.rootText,
        viewJSON: npmProbeViewJSON(package: "@openai/codex", version: "3.0.0", latest: "3.0.0"),
        clock: clock, exhaustValue: 10
    )
    let binURL = fixture.target
    runner.fireAfter(lastQuery) {
        try? npmProbeReplaceExecutable(
            at: binURL, content: "#!/bin/sh\nprintf 'codex 9.0.0\\n'\n"
        )
    }
    let result = await npmProbeRunMulti(
        fixture: fixture, names: ["@openai/codex"], runner: runner, cacheURL: cacheURL,
        mode: .checkUpdates, scratchBase: scratch,
        uptime: { clock.get() }, stageDeadline: 1_000_000
    )
    // The live proof revalidation AFTER the final query observes the changed executable identity:
    // neutral unknown, no publication; the stored document keeps ONLY the prior seed record.
    #expect(npmProbeReason(result.status) == .identityUnverified)
    #expect(runner.metadataCallCount == 0)  // cache hit; the refused success never persisted
    let storedProofs = npmProbeStoredProofFingerprints(cacheDir: cacheDir)
    #expect(storedProofs == seededProofs)
    // Restore the original bin content for fixture hygiene.
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: binURL, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binURL.path)
}

@Test func deadlineExhaustedAfterFinalQueryMapsToBudgetExhaustedOnCacheHit() async throws {
    let fixture = try NpmProbeFixture("r04-window-deadline", package: "@openai/codex")
    let cacheDir = try npmProbeScratchRoot("r04-window-deadline-cache")
    let cacheURL = npmProbeCacheURL(cacheDir)
    let scratch = npmProbeScratch(cacheDir)

    let seed = RecordingNpmRunner(
        prefix: fixture.prefixText, root: fixture.rootText,
        viewJSON: npmProbeViewJSON(package: "@openai/codex", version: "2.0.0", latest: "2.0.0")
    )
    let refresh = await npmProbeRunMulti(
        fixture: fixture, names: ["@openai/codex"], runner: seed, cacheURL: cacheURL,
        mode: .refresh, scratchBase: scratch
    )
    guard case .updateAvailable = refresh.status else {
        Issue.record("seed refresh should publish updateAvailable"); return
    }

    // Learn where the last external query lands, then advance the injected monotonic clock past
    // the stage deadline immediately AFTER that final command. Every prior step succeeded; only the
    // final live gate remains — exactly the coordinator's `deadline-after-final-scope` window.
    let lastQuery = await npmProbeLastQueryOrdinal(
        fixture: fixture, cacheURL: cacheURL, scratch: scratch
    )
    #expect(lastQuery > 0)
    let clock = NpmProbeClock()
    let runner = GatedScriptedNpmRunner(
        prefix: fixture.prefixText, root: fixture.rootText,
        viewJSON: npmProbeViewJSON(package: "@openai/codex", version: "3.0.0", latest: "3.0.0"),
        clock: clock
    )
    runner.fireAfter(lastQuery, hook: {})
    let result = await npmProbeRunMulti(
        fixture: fixture, names: ["@openai/codex"], runner: runner, cacheURL: cacheURL,
        mode: .checkUpdates, scratchBase: scratch,
        uptime: { clock.get() }, stageDeadline: 100
    )
    // Budget exhaustion at the last-query window — never a generic cancelled/probeFailed claim,
    // never a stale success from the cache hit, and no view launch.
    #expect(npmProbeReason(result.status) == .budgetExhausted)
    #expect(result.provenance == UpdateProvenance.none)
    #expect(runner.metadataCallCount == 0)
    // The final reads DID happen before the refusal (this is the last-query window, not an
    // early bail): ownership ran twice and both config groups completed.
    #expect(runner.count(.prefix) == 2)
    #expect(runner.count(.root) == 2)
    #expect(runner.count(.configBase) == 2)
    #expect(runner.count(.configScope) == 2)
    // The stored document still holds exactly the seed record: nothing was committed or renewed.
    let storedProofs = npmProbeStoredProofFingerprints(cacheDir: cacheDir)
    #expect(storedProofs.count == 1)
}

// MARK: River RC1/RC2 — child-environment isolation and cause-aware metadata refusal

@Test func everyNpmInvocationOverridesInheritedCacheLogsAndNotifierIncludingFourOwnershipQueries() async throws {
    let fixture = try NpmProbeFixture("river-environment")
    let cacheDir = try npmProbeScratchRoot("river-environment-cache")
    defer {
        try? FileManager.default.removeItem(at: fixture.root)
        try? FileManager.default.removeItem(at: cacheDir)
    }
    let scratch = npmProbeScratch(cacheDir)
    let trapCache = cacheDir.appendingPathComponent("inherited-cache")
    let trapLogs = cacheDir.appendingPathComponent("inherited-logs")
    let sentinel = Data("must remain byte-identical".utf8)
    for trap in [trapCache, trapLogs] {
        try FileManager.default.createDirectory(at: trap, withIntermediateDirectories: true)
        try sentinel.write(to: trap.appendingPathComponent("sentinel"))
    }
    var raw = fixture.environment.raw
    raw["npm_config_cache"] = trapCache.path
    raw["Npm_Config_Cache"] = trapCache.path
    raw["NPM_CONFIG_LOGS_DIR"] = trapLogs.path
    raw["npm_config_logs_dir"] = trapLogs.path
    raw["Npm_Config_Update_Notifier"] = "1"
    raw["npm_config_update_notifier"] = "true"
    raw["TMPDIR"] = fixture.root.path
    let environment = ShellEnvironment(
        shellPath: fixture.environment.shellPath, pathEntries: fixture.environment.pathEntries,
        pathJoined: fixture.environment.pathJoined, raw: raw, isDegraded: false
    )
    let definition = try npmProbeDefinition(executableName: "codex", package: "@openai/codex")
    let diagnostic = npmProbeWinnerDiagnostic(
        executableName: "codex", entryPath: fixture.aliasPath, version: "1.0.0"
    )
    let runner = RecordingNpmRunner(
        prefix: fixture.prefixText, root: fixture.rootText,
        viewJSON: npmProbeViewJSON(package: "@openai/codex", version: "2.0.0", latest: "2.0.0")
    )
    let result = await NpmUpdateProbe.run(
        definition: definition, diagnostic: diagnostic, environment: environment, runner: runner,
        cacheURL: npmProbeCacheURL(cacheDir), mode: .checkUpdates, currentDirectory: fixture.root.path,
        now: npmProbeFixedClock(npmProbeBaseDate), uptime: npmProbeZeroUptime(),
        stageDeadline: npmProbeFarDeadline, diagnosticIndex: 0, npmScratchBaseURL: scratch
    )
    guard case .updateAvailable = result.status else {
        Issue.record("isolation regression must reach both ownership groups: \(result.status)"); return
    }
    let invocations = runner.recordedInvocations
    #expect(invocations.count == 10) // four ownership, four config, one view, one version
    #expect(runner.count(.prefix) == 2)
    #expect(runner.count(.root) == 2)
    for invocation in invocations {
        let env = invocation.environment
        let root = try #require(env["NPM_CONFIG_CACHE"])
        #expect(env["NPM_CONFIG_LOGS_DIR"] == root)
        #expect(env["NPM_CONFIG_UPDATE_NOTIFIER"] == "false")
        #expect(env["TMPDIR"] == fixture.root.path)
        for key in ["NPM_CONFIG_CACHE", "NPM_CONFIG_LOGS_DIR", "NPM_CONFIG_UPDATE_NOTIFIER"] {
            #expect(env.keys.filter { $0.lowercased() == key.lowercased() } == [key])
        }
        #expect(invocation.cacheMode == mode_t(0o700)) // observed while the command was live
        #expect(URL(fileURLWithPath: root).deletingLastPathComponent().resolvingSymlinksInPath()
            == scratch.resolvingSymlinksInPath())
        #expect(!FileManager.default.fileExists(atPath: root))
    }
    // Prefix/root share a root within each verification group; final proof gets a distinct root.
    let ownership = invocations.filter { [.prefix, .root].contains(categorizeNpm($0.arguments)) }
    try #require(ownership.count == 4)
    #expect(ownership[0].environment["NPM_CONFIG_CACHE"] == ownership[1].environment["NPM_CONFIG_CACHE"])
    #expect(ownership[2].environment["NPM_CONFIG_CACHE"] == ownership[3].environment["NPM_CONFIG_CACHE"])
    #expect(ownership[0].environment["NPM_CONFIG_CACHE"] != ownership[2].environment["NPM_CONFIG_CACHE"])
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: scratch.path)
    #expect(leftovers.isEmpty)
    for trap in [trapCache, trapLogs] {
        let contents = try FileManager.default.contentsOfDirectory(atPath: trap.path)
        let actual = try Data(contentsOf: trap.appendingPathComponent("sentinel"))
        #expect(contents == ["sentinel"])
        #expect(actual == sentinel)
    }
}

private final class MetadataDeadlineRefusalRunner: RecordingNpmRunner, @unchecked Sendable {
    let clock: NpmProbeClock
    let cancelTask: Bool
    init(prefix: String, root: String, clock: NpmProbeClock, cancelTask: Bool) {
        self.clock = clock
        self.cancelTask = cancelTask
        super.init(prefix: prefix, root: root, viewJSON: Data())
    }

    override func run(
        executablePath: String, arguments: [String], environment: [String: String], timeout: TimeInterval
    ) async -> CommandOutcome {
        if categorizeNpm(arguments) == .view {
            // The pre-view guard passed. The clipping runner now observes the exhausted clock
            // and refuses BEFORE forwarding a metadata process to the underlying runner.
            clock.set(100)
            if cancelTask { withUnsafeCurrentTask { $0?.cancel() } }
            return .failure(.cancelled)
        }
        return await super.run(
            executablePath: executablePath, arguments: arguments, environment: environment, timeout: timeout
        )
    }
}

@Test func metadataDeadlineRefusalUsesBudgetReasonWhileTaskCancellationStaysNeutral() async throws {
    for cancelTask in [false, true] {
        let fixture = try NpmProbeFixture("river-view-deadline")
        let cacheDir = try npmProbeScratchRoot("river-view-deadline-cache")
        defer {
            try? FileManager.default.removeItem(at: fixture.root)
            try? FileManager.default.removeItem(at: cacheDir)
        }
        let scratch = npmProbeScratch(cacheDir)
        let clock = NpmProbeClock()
        let runner = MetadataDeadlineRefusalRunner(
            prefix: fixture.prefixText, root: fixture.rootText, clock: clock, cancelTask: cancelTask
        )
        let task = Task {
            await npmProbeRunMulti(
                fixture: fixture, names: ["@openai/codex"], runner: runner,
                cacheURL: npmProbeCacheURL(cacheDir), mode: .checkUpdates, scratchBase: scratch,
                uptime: { clock.get() }, stageDeadline: 100
            )
        }
        let result = await task.value
        #expect(clock.get() == 100) // the pre-view path was traversed and the refusal seam fired
        #expect(npmProbeReason(result.status) == (cancelTask ? .probeFailed : .budgetExhausted))
        #expect(result.provenance == UpdateProvenance.none)
        #expect(runner.metadataCallCount == 0) // refusal never forwarded a metadata launch
        #expect(!FileManager.default.fileExists(
            atPath: cacheDir.appendingPathComponent("npm-update-metadata-v1.json").path
        ))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: scratch.path)
        #expect(leftovers.isEmpty)
    }
}

// MARK: - R07 — scratch base validation, owned-child identity, anchored cleanup

/// Raw POSIX observation of one path WITHOUT following a final-component symlink.
private func npmProbeLstat(_ url: URL) -> stat? {
    var info = stat()
    guard Darwin.lstat(url.path, &info) == 0 else { return nil }
    return info
}

@Test func unsafeScratchBasesRefuseWithZeroNpmLaunches() async throws {
    // R07: the injected scratch BASE is validated before a single npm process is launched. A
    // missing, symlinked, non-directory, group-writable or other-writable root is unsafe — the stage
    // refuses with a neutral, identity-preserving failure, launches ZERO commands, enters nothing
    // through the symlink, and persists nothing.
    let fixture = try NpmProbeFixture("r07-unsafe", package: "codex-ai", executableName: "codex-ai")
    let definition = try npmProbeDefinition(executableName: "codex-ai", package: "codex-ai")
    let diagnostic = npmProbeWinnerDiagnostic(
        executableName: "codex-ai", entryPath: fixture.aliasPath, version: "1.0.0"
    )
    let cacheDir = try npmProbeScratchRoot("r07-unsafe-cache")
    let parent = npmProbeScratch(cacheDir, "unsafe-parent")
    let fm = FileManager.default

    func makeDir(_ name: String, mode: Int? = nil) throws -> URL {
        let url = parent.appendingPathComponent(name, isDirectory: true)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        if let mode {
            try fm.setAttributes([.posixPermissions: NSNumber(value: mode)], ofItemAtPath: url.path)
        }
        return url
    }

    // A symlink whose DESTINATION is itself a perfectly safe owned directory is still a retarget:
    // the injected root's own component must not be a link.
    let symlinkTarget = try makeDir("real-destination")
    let link = parent.appendingPathComponent("as-symlink", isDirectory: true)
    try fm.createSymbolicLink(at: link, withDestinationURL: symlinkTarget)
    let notDirectory = parent.appendingPathComponent("not-a-directory")
    try Data("x".utf8).write(to: notDirectory)

    let unsafe: [(String, URL)] = [
        ("missing", parent.appendingPathComponent("never-created", isDirectory: true)),
        ("symlink", link),
        ("not-a-directory", notDirectory),
        ("group-writable", try makeDir("group-writable", mode: 0o770)),
        ("other-writable", try makeDir("other-writable", mode: 0o757)),
    ]
    for (label, base) in unsafe {
        let runner = RecordingNpmRunner(
            prefix: fixture.prefixText, root: fixture.rootText,
            viewJSON: npmProbeViewJSON(package: "codex-ai", version: "2.0.0", latest: "2.0.0")
        )
        let result = await NpmUpdateProbe.run(
            definition: definition, diagnostic: diagnostic, environment: fixture.environment,
            runner: runner, cacheURL: cacheDir.appendingPathComponent("update-\(label).json"),
            mode: .checkUpdates, currentDirectory: fixture.root.path,
            now: npmProbeFixedClock(npmProbeBaseDate), uptime: npmProbeZeroUptime(),
            stageDeadline: npmProbeFarDeadline, diagnosticIndex: 0,
            npmScratchBaseURL: base
        )
        #expect(npmProbeReason(result.status) == .probeFailed, "\(label) accepted an unsafe base")
        #expect(runner.recordedCount == 0, "\(label) launched npm commands")
        // The refusal is about the SAME tool: identity is preserved on the neutral result.
        #expect(result.localVersion == "1.0.0", "\(label)")
        #expect(result.selectedEntryPath == fixture.aliasPath, "\(label)")
    }
    // Nothing was ever created inside or THROUGH the safe destination of the refused symlink.
    #expect(try fm.contentsOfDirectory(atPath: symlinkTarget.path).isEmpty)
    // And no metadata document was written for any of the refusals.
    #expect(!npmProbeMetadataDocExists(cacheDir: cacheDir))
}

@Test func symlinkedAncestorScratchBaseStillRunsAndLeavesNoOwnedChild() async throws {
    // R07 must keep the DEFAULT working: macOS spells its sanctioned TMPDIR as `/var/…`, a physical
    // alias of `/private/var/…`, so a symlinked ANCESTOR of the base is legitimate. Only the base
    // component itself is held to the safety rules. Such a base runs to a verified publication and
    // still leaves no owned child behind.
    let fixture = try NpmProbeFixture("r07-alias", package: "codex-ai", executableName: "codex-ai")
    let definition = try npmProbeDefinition(executableName: "codex-ai", package: "codex-ai")
    let diagnostic = npmProbeWinnerDiagnostic(
        executableName: "codex-ai", entryPath: fixture.aliasPath, version: "1.0.0"
    )
    let fm = FileManager.default
    let cacheDir = try npmProbeScratchRoot("r07-alias-cache")
    let realParent = fixture.root.appendingPathComponent("real-parent", isDirectory: true)
    let physicalBase = realParent.appendingPathComponent("scratch", isDirectory: true)
    try fm.createDirectory(at: physicalBase, withIntermediateDirectories: true)
    let aliasParent = fixture.root.appendingPathComponent("alias-parent", isDirectory: true)
    try fm.createSymbolicLink(at: aliasParent, withDestinationURL: realParent)
    // The INJECTED spelling goes through a symlinked ancestor; the base component is a real dir.
    let injected = aliasParent.appendingPathComponent("scratch", isDirectory: true)

    let runner = RecordingNpmRunner(
        prefix: fixture.prefixText, root: fixture.rootText,
        viewJSON: npmProbeViewJSON(package: "codex-ai", version: "2.0.0", latest: "2.0.0")
    )
    let result = await NpmUpdateProbe.run(
        definition: definition, diagnostic: diagnostic, environment: fixture.environment,
        runner: runner, cacheURL: npmProbeCacheURL(cacheDir),
        mode: .checkUpdates, currentDirectory: fixture.root.path,
        now: npmProbeFixedClock(npmProbeBaseDate), uptime: npmProbeZeroUptime(),
        stageDeadline: npmProbeFarDeadline, diagnosticIndex: 0,
        npmScratchBaseURL: injected
    )
    #expect(npmProbeReason(result.status) == nil)
    guard case .updateAvailable = result.status else {
        Issue.record("a symlinked ancestor must not block the stage, got \(result.status)"); return
    }
    // Children were created in the PHYSICAL location the validation resolved to…
    #expect(try fm.contentsOfDirectory(atPath: physicalBase.path).isEmpty)
    // …which the alias spelling reports identically, proving the alias was followed, not refused.
    #expect(try fm.contentsOfDirectory(atPath: injected.path).isEmpty)
    // The per-invocation roots were actually used: npm saw `--cache` paths under the base's PHYSICAL
    // directory, never a name created through the symlinked ancestor spelling.
    let resolvedPhysicalBase = try #require(NpmScratchBase.physicalPath(of: physicalBase.path))
    let view = try #require(runner.viewArgs.first)
    let cacheFlag = view.firstIndex(of: "--cache").map { view[$0 + 1] }
    #expect(cacheFlag?.hasPrefix(resolvedPhysicalBase + "/") == true)
    #expect(cacheFlag?.contains("alias-parent") == false)
}

@Test func claimedScratchChildIsOwnedMode0700DirectPhysicalChildOfBase() throws {
    // R07 owned-child identity: a claim creates a UNIQUE directory, mode 0700 regardless of umask,
    // owned by this process, recorded with its observed device+inode, and anchored as a DIRECT
    // physical child of the validated base. The base record itself carries the physical spelling.
    let cacheDir = try npmProbeScratchRoot("r07-claim")
    let baseURL = npmProbeScratch(cacheDir, "base")
    guard let base = NpmScratchBase(url: baseURL) else {
        Issue.record("a safe owned base was refused"); return
    }
    #expect(base.physicalPath == base.lexicalURL.path)

    guard let first = NpmScratchRoot.claim(base: base),
          let second = NpmScratchRoot.claim(base: base)
    else {
        Issue.record("claiming an owned child under a safe base failed"); return
    }
    // Unique per invocation group — never the same name twice.
    #expect(first.url.path != second.url.path)

    for root in [first, second] {
        let info = try #require(npmProbeLstat(root.url))
        #expect((info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR))
        #expect((info.st_mode & mode_t(S_IFMT)) != mode_t(S_IFLNK))
        #expect(Int(info.st_mode & 0o7777) == 0o700)
        #expect(info.st_uid == getuid())
        // The recorded identity is exactly what cleanup will re-check.
        #expect(info.st_dev == root.device)
        #expect(info.st_ino == root.inode)
        // Anchored: the recorded physical name is a direct child of the validated physical base.
        #expect(root.physicalPath.hasPrefix(base.physicalPath + "/"))
        #expect(
            URL(fileURLWithPath: root.physicalPath, isDirectory: true)
                .deletingLastPathComponent().path == base.physicalPath
        )
    }

    let ledger = NpmScratchCleanupLedger()
    #expect(ledger.release(first))
    #expect(ledger.release(second))
    #expect(!ledger.hasFailures)
    #expect(try FileManager.default.contentsOfDirectory(atPath: base.physicalPath).isEmpty)
}

@Test func anchoredCleanupRemovesOnlyTheRecordedOwnedChild() throws {
    // R07 cleanup is scoped to the one recorded owned child. Siblings — another live owned child or
    // a directory the caller happens to keep under the same base — are never touched.
    let cacheDir = try npmProbeScratchRoot("r07-only-owned")
    let base = try #require(NpmScratchBase(url: npmProbeScratch(cacheDir, "base")))
    guard let doomed = NpmScratchRoot.claim(base: base),
          let neighbour = NpmScratchRoot.claim(base: base)
    else {
        Issue.record("claiming owned children failed"); return
    }
    let fm = FileManager.default
    let sibling = base.lexicalURL.appendingPathComponent("caller-content", isDirectory: true)
    try fm.createDirectory(at: sibling, withIntermediateDirectories: true)
    let sentinel = sibling.appendingPathComponent("sentinel.txt")
    try Data("do not remove".utf8).write(to: sentinel)
    let neighbourSentinel = neighbour.url.appendingPathComponent("inside.txt")
    try Data("also mine".utf8).write(to: neighbourSentinel)

    let ledger = NpmScratchCleanupLedger()
    #expect(ledger.release(doomed))
    #expect(!fm.fileExists(atPath: doomed.url.path))
    #expect(fm.fileExists(atPath: neighbourSentinel.path))
    #expect(fm.fileExists(atPath: sentinel.path))
    #expect(!ledger.hasFailures)
    #expect(ledger.failures == 0)

    #expect(ledger.release(neighbour))
    #expect(try fm.contentsOfDirectory(atPath: base.physicalPath) == ["caller-content"])
    try fm.removeItem(at: sibling)
}

@Test func anchoredCleanupRefusesAChildReplacedByADifferentDirectory() throws {
    // R07 identity recheck: a path that still exists, still is a directory, and still is owned by
    // this process but is a DIFFERENT vnode was not created by this claim. Cleanup refuses it (and
    // records a failure) rather than deleting an object it never observed.
    let cacheDir = try npmProbeScratchRoot("r07-same-path")
    let base = try #require(NpmScratchBase(url: npmProbeScratch(cacheDir, "base")))
    guard let root = NpmScratchRoot.claim(base: base) else {
        Issue.record("claiming an owned child failed"); return
    }
    let fm = FileManager.default
    let recordedInode = root.inode
    try fm.removeItem(at: root.url)
    // Re-create the SAME pathname: new inode, same everything else the naive check would use.
    try fm.createDirectory(at: root.url, withIntermediateDirectories: false)
    let replacementSentinel = root.url.appendingPathComponent("sentinel.txt")
    try Data("someone else's directory".utf8).write(to: replacementSentinel)
    let replacementInode = try #require(npmProbeLstat(root.url)).st_ino
    #expect(replacementInode != recordedInode)

    let ledger = NpmScratchCleanupLedger()
    #expect(!ledger.release(root))
    #expect(ledger.hasFailures)
    #expect(ledger.failures == 1)
    // The replacement and its contents are untouched — nothing outside the owned child is removed.
    #expect(fm.fileExists(atPath: replacementSentinel.path))

    // A repeated refusal is still a failure, never a silent success.
    #expect(!ledger.release(root))
    #expect(ledger.failures == 2)
    try fm.removeItem(at: root.url)
}

@Test func anchoredCleanupRefusesARetargetedAncestorAndLeavesTheRecordedChild() throws {
    // R07 anchoring: if the BASE is swapped for a symlink to where the real directory was moved, the
    // recorded child name still resolves to a directory with the SAME vnode — but its physical
    // pathname is no longer the one this process created. Cleanup must refuse rather than act
    // through a retargeted ancestor, and it must report the failure.
    let cacheDir = try npmProbeScratchRoot("r07-retarget")
    // Build the base in its OWN physical spelling so the recorded child's pathname keeps running
    // through the base component that is later swapped for a symlink.
    let physicalParent = try #require(
        NpmScratchBase.physicalPath(of: npmProbeScratch(cacheDir, "retarget-parent").path)
    )
    let baseDir = URL(fileURLWithPath: physicalParent, isDirectory: true)
        .appendingPathComponent("base", isDirectory: true)
    try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: false)
    let base = try #require(NpmScratchBase(url: baseDir))
    guard let root = NpmScratchRoot.claim(base: base) else {
        Issue.record("claiming an owned child failed"); return
    }
    let fm = FileManager.default
    let inside = root.url.appendingPathComponent("sentinel.txt")
    try Data("still mine".utf8).write(to: inside)

    // Swap the validated base for a symlink to the moved-aside real directory.
    let moved = cacheDir.appendingPathComponent("base-moved", isDirectory: true)
    try fm.moveItem(at: baseDir, to: moved)
    try fm.createSymbolicLink(at: baseDir, withDestinationURL: moved)
    // The path still resolves, and to the very same vnode…
    #expect(npmProbeLstat(root.url)?.st_ino == root.inode)
    // …but the physical name is now different, which is exactly the anchor check's job.
    #expect(NpmScratchBase.physicalPath(of: root.url.path) != root.physicalPath)

    let ledger = NpmScratchCleanupLedger()
    #expect(!ledger.release(root))
    #expect(ledger.hasFailures)
    // The recorded child survives intact inside the moved directory; nothing was deleted elsewhere.
    #expect(fm.fileExists(atPath: inside.path))

    // Restore: with the base real again the anchor holds and the same record cleans up normally.
    try fm.removeItem(at: baseDir)
    try fm.moveItem(at: moved, to: baseDir)
    #expect(ledger.release(root))
    #expect(!fm.fileExists(atPath: root.url.path))
    #expect(try fm.contentsOfDirectory(atPath: baseDir.path).isEmpty)
}

@Test func scratchCleanupFailureIsPropagatedAndNeverPublishedAsVerified() async throws {
    // R07 propagation: an owned scratch child this run created that it CANNOT remove is a stage
    // failure, not an ignorable detail. Every later stage still works, so the run reaches its
    // publication gate with a legitimate cache hit in hand — and must still refuse with NOTHING
    // persisted, rather than report a verified status that implies zero leftovers.
    let fixture = try NpmProbeFixture("r07-propagate", package: "@openai/codex")
    let cacheDir = try npmProbeScratchRoot("r07-propagate-cache")
    let cacheURL = npmProbeCacheURL(cacheDir)
    let scratch = npmProbeScratch(cacheDir)
    let fm = FileManager.default

    // Seed a valid, reusable observation so the failing run would otherwise be a plain cache hit.
    let seed = RecordingNpmRunner(
        prefix: fixture.prefixText, root: fixture.rootText,
        viewJSON: npmProbeViewJSON(package: "@openai/codex", version: "2.0.0", latest: "2.0.0")
    )
    let seeded = await npmProbeRunMulti(
        fixture: fixture, names: ["@openai/codex"], runner: seed, cacheURL: cacheURL,
        mode: .refresh, scratchBase: scratch
    )
    guard case .updateAvailable = seeded.status else {
        Issue.record("the seed refresh must publish, got \(seeded.status)"); return
    }
    let seededProofs = npmProbeStoredProofFingerprints(cacheDir: cacheDir)
    #expect(seededProofs.count == 1)
    #expect(try fm.contentsOfDirectory(atPath: scratch.path).isEmpty)

    // Immediately after the FIRST ownership command, make the live owned child unremovable by
    // planting a read-only subdirectory inside it. The base stays writable, so every later stage
    // still creates and releases its own child normally: the cleanup failure is the ONLY defect.
    let clock = NpmProbeClock()
    let runner = GatedScriptedNpmRunner(
        prefix: fixture.prefixText, root: fixture.rootText,
        viewJSON: npmProbeViewJSON(package: "@openai/codex", version: "2.0.0", latest: "2.0.0"),
        clock: clock, exhaustValue: 1
    )
    runner.fireAfter(1) {
        guard let entries = try? fm.contentsOfDirectory(atPath: scratch.path),
              entries.count == 1, let child = entries.first else { return }
        let inner = scratch
            .appendingPathComponent(child, isDirectory: true)
            .appendingPathComponent("locked", isDirectory: true)
        try? fm.createDirectory(at: inner, withIntermediateDirectories: true)
        try? Data("keep".utf8).write(to: inner.appendingPathComponent("file.txt"))
        try? fm.setAttributes(
            [.posixPermissions: NSNumber(value: 0o500)], ofItemAtPath: inner.path
        )
    }

    let result = await npmProbeRunMulti(
        fixture: fixture, names: ["@openai/codex"], runner: runner, cacheURL: cacheURL,
        mode: .checkUpdates, scratchBase: scratch, uptime: { clock.get() }
    )
    // No verified status, no provenance claim, and no metadata query needed or issued.
    #expect(npmProbeReason(result.status) == .probeFailed)
    #expect(result.provenance == UpdateProvenance.none)
    #expect(runner.metadataCallCount == 0)
    // Identity is still preserved about the same tool.
    #expect(result.npmPackage == "@openai/codex")
    #expect(result.localVersion == "1.0.0")
    // Nothing was committed or renewed: the document is byte-for-byte the same record set.
    #expect(npmProbeStoredProofFingerprints(cacheDir: cacheDir) == seededProofs)

    // The unremovable owned child is STILL THERE — the run never claimed zero leftovers.
    let leftovers = try fm.contentsOfDirectory(atPath: scratch.path)
    #expect(leftovers.count == 1)
    let stuckChild = scratch.appendingPathComponent(leftovers[0], isDirectory: true)
    #expect(fm.fileExists(atPath: stuckChild.appendingPathComponent("locked/file.txt").path))

    // Release the fixture's own planted obstruction, then verify the stage's contract retroactively:
    // with no unremovable child a fresh Check publishes normally and leaves the base empty.
    try fm.setAttributes(
        [.posixPermissions: NSNumber(value: 0o700)],
        ofItemAtPath: stuckChild.appendingPathComponent("locked").path
    )
    try fm.removeItem(at: stuckChild)
    let recovery = RecordingNpmRunner(
        prefix: fixture.prefixText, root: fixture.rootText,
        viewJSON: npmProbeViewJSON(package: "@openai/codex", version: "2.0.0", latest: "2.0.0")
    )
    let recovered = await npmProbeRunMulti(
        fixture: fixture, names: ["@openai/codex"], runner: recovery, cacheURL: cacheURL,
        mode: .checkUpdates, scratchBase: scratch
    )
    #expect(npmProbeReason(recovered.status) == nil)
    #expect(recovered.provenance == .cache(observedAt: npmProbeBaseDate))
    #expect(try fm.contentsOfDirectory(atPath: scratch.path).isEmpty)
}
