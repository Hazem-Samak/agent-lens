// HomebrewCaskUpdateProbeTests — M13-B cask latest-check adapter and tri-state resolver.
//
// Every manager answer is scripted. Fixtures are synthetic scratch trees; no real brew or cask is
// invoked. The tests pin the exact five-command argv, live manager/selection/root binding, the
// manager-verdict oracle (no formula comparator), every tri-state branch, record identity/alias
// poisoning, exact membership, the narrow moved-app proof, and the bounded listing parse.

import Darwin
import Foundation
import Testing
@testable import AgentLensCore

// MARK: Scratch and synthetic cask fixture

private func caskProbeScratchRoot(_ label: String) throws -> URL {
    let environment = ProcessInfo.processInfo.environment
    guard let basePath = [environment["AGENT_LENS_TEST_SCRATCH"], environment["TMPDIR"]]
        .compactMap({ $0 })
        .first(where: { !$0.isEmpty })
    else {
        throw NSError(
            domain: "AgentLensCaskProbeTests", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "no approved test scratch root is available"]
        )
    }
    let base = URL(fileURLWithPath: basePath, isDirectory: true).resolvingSymlinksInPath()
    let root = base.appendingPathComponent(
        "agentlens-m13b-\(label)-\(UUID().uuidString)", isDirectory: true
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root.resolvingSymlinksInPath()
}

private func writeProbeExecutable(_ url: URL, version: String = "1.0.0") throws {
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

private struct CaskProbeFixture {
    let root: URL
    let prefix: URL
    let caskroom: URL
    let token: String
    let fullToken: String
    let version: String
    let localVersion: String
    let entryPath: String
    let selectedTarget: String
    let brewPath: String
    let binDirectory: String

    init(
        _ label: String,
        token: String = "codex",
        fullToken: String? = nil,
        version: String = "1.0.0",
        localVersion: String = "1.0.0"
    ) throws {
        root = try caskProbeScratchRoot(label)
        prefix = root.appendingPathComponent("prefix", isDirectory: true)
        caskroom = root.appendingPathComponent("Caskroom", isDirectory: true)
        self.token = token
        self.fullToken = fullToken ?? token
        self.version = version
        self.localVersion = localVersion
        let artifact = caskroom
            .appendingPathComponent(token, isDirectory: true)
            .appendingPathComponent(version, isDirectory: true)
            .appendingPathComponent("bin/\(token)")
        try writeProbeExecutable(artifact, version: localVersion)
        let bin = prefix.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let entry = bin.appendingPathComponent(token)
        try? FileManager.default.removeItem(at: entry)
        try FileManager.default.createSymbolicLink(
            atPath: entry.path, withDestinationPath: artifact.path
        )
        try writeProbeExecutable(bin.appendingPathComponent("brew"))
        entryPath = entry.path
        selectedTarget = artifact.resolvingSymlinksInPath().standardizedFileURL.path
        brewPath = bin.appendingPathComponent("brew").path
        binDirectory = bin.path
    }

    var manager: HomebrewManager {
        HomebrewManager(entryPath: brewPath, canonicalTarget: brewPath)
    }

    var observedManager: ObservedExecutable {
        FileIdentityObserver.observeExecutable(entryPath: brewPath)!
    }

    var observedSelection: ObservedExecutable {
        FileIdentityObserver.observeExecutable(entryPath: entryPath)!
    }

    var boundPrefix: HomebrewCaskBoundRoot {
        HomebrewCaskBoundRoot.observe(prefix.path)!
    }

    var boundCaskroom: HomebrewCaskBoundRoot {
        HomebrewCaskBoundRoot.observe(caskroom.path)!
    }

    func stagedBinding(token: String? = nil, version: String? = nil)
        -> HomebrewCaskStagedBinding
    {
        HomebrewCaskStagedBinding.observe(
            caskroom: boundCaskroom, token: token ?? self.token, version: version ?? self.version
        )!
    }

    var environment: ShellEnvironment {
        let joined = binDirectory
        return ShellEnvironment(
            shellPath: "/bin/zsh",
            pathEntries: [binDirectory],
            pathJoined: joined,
            raw: ["PATH": joined, "HOME": "/synthetic/home"],
            isDegraded: false
        )
    }
}

// MARK: JSON helpers

private func caskInfoJSON(_ records: [String]) -> Data {
    Data("{\"formulae\":[],\"casks\":[\(records.joined(separator: ","))]}".utf8)
}

private func caskInfoRecord(
    token: String,
    fullToken: String? = nil,
    tap: String = "homebrew/cask",
    version: String,
    installed: String?,
    oldTokens: [String] = [],
    autoUpdates: String = "null",
    pinned: Bool = false,
    outdated: Bool = false,
    disabled: Bool = false,
    deprecated: Bool = false
) -> String {
    let full = fullToken ?? token
    let installedField = installed.map { "\"installed\":\"\($0)\"" } ?? "\"installed\":null"
    let old = oldTokens.map { "\"\($0)\"" }.joined(separator: ",")
    return """
    {"token":"\(token)","full_token":"\(full)","tap":"\(tap)","version":"\(version)",\
    \(installedField),"auto_updates":\(autoUpdates),"pinned":\(pinned),"outdated":\(outdated),\
    "disabled":\(disabled),"deprecated":\(deprecated),"old_tokens":[\(old)]}
    """
}

private func caskOutdatedJSON(_ records: [String]) -> Data {
    Data("{\"formulae\":[],\"casks\":[\(records.joined(separator: ","))]}".utf8)
}

private func caskOutdatedRecord(
    name: String,
    current: String,
    installed: [String],
    pinned: Bool = false
) -> String {
    let versions = installed.map { "\"\($0)\"" }.joined(separator: ",")
    return """
    {"name":"\(name)","current_version":"\(current)","installed_versions":[\(versions)],\
    "pinned":\(pinned),"pinned_version":null}
    """
}

private func listingData(_ lines: [String]) -> Data {
    Data(lines.joined(separator: "\n").utf8 + (lines.isEmpty ? Data() : Data("\n".utf8)))
}

/// Scripted manager with the exact five-command protocol. The handler sees argv and answers.
private func caskRunner(
    prefix: String,
    caskroom: String,
    info: Data,
    outdated: Data,
    listing: Data,
    infoTokens: [String],
    listTokens: [String],
    onCall: @escaping @Sendable ([String]) -> Void = { _ in }
) -> ScriptedRunner {
    ScriptedRunner { _, arguments in
        onCall(arguments)
        switch arguments {
        case ["--prefix"]:
            return .success(Data((prefix + "\n").utf8))
        case ["--caskroom"]:
            return .success(Data((caskroom + "\n").utf8))
        case ["info", "--json=v2", "--cask"] + infoTokens:
            return .success(info)
        case ["outdated", "--json=v2", "--cask"]:
            return .success(outdated)
        case ["list", "--verbose", "--cask"] + listTokens:
            return .success(listing)
        default:
            Issue.record("unexpected brew arguments: \(arguments)")
            return .failure(.spawnFailure)
        }
    }
}

// MARK: Typed batch helpers for resolver tests

private func typedRecords(_ records: [HomebrewCaskInfoRecord]) -> [String: [HomebrewCaskInfoRecord]] {
    Dictionary(grouping: records, by: \.token)
}

private func typedOutdated(
    _ records: [HomebrewCaskOutdatedRecord]
) -> [String: [HomebrewCaskOutdatedRecord]] {
    Dictionary(grouping: records, by: \.name)
}

private func resolverBatch(
    fixture: CaskProbeFixture,
    records: [HomebrewCaskInfoRecord],
    outdated: [HomebrewCaskOutdatedRecord] = [],
    listing: [String]? = nil,
    installedTokens: [String]? = nil,
    stagedBindings: [HomebrewCaskStagedBinding]? = nil
) -> HomebrewCaskBatchResult {
    let inferredInstalled = records.compactMap { record -> String? in
        if case .string = record.installed { return record.token }
        return nil
    }
    return HomebrewCaskBatchResult(
        prefix: fixture.boundPrefix,
        caskroom: fixture.boundCaskroom,
        records: typedRecords(records),
        outdated: typedOutdated(outdated),
        listing: listing ?? [fixture.selectedTarget],
        installedTokens: installedTokens ?? inferredInstalled,
        listingNames: installedTokens ?? inferredInstalled,
        stagedBindings: stagedBindings ?? [fixture.stagedBinding()],
        queryCount: 0
    )
}

private func installedRecord(
    _ fixture: CaskProbeFixture,
    version: String? = nil,
    installed: String? = nil,
    fullToken: String? = nil,
    tap: String = "homebrew/cask",
    autoUpdates: Bool? = nil,
    pinned: Bool = false,
    outdated: Bool = false,
    disabled: Bool = false,
    oldTokens: [String] = []
) -> HomebrewCaskInfoRecord {
    HomebrewCaskInfoRecord(
        token: fixture.token,
        fullToken: fullToken ?? fixture.fullToken,
        tap: tap,
        version: version ?? fixture.version,
        installed: .string(installed ?? fixture.version),
        autoUpdates: autoUpdates,
        pinned: pinned,
        outdated: outdated,
        disabled: disabled,
        oldTokens: oldTokens
    )
}

private func evaluate(
    _ fixture: CaskProbeFixture,
    records: [HomebrewCaskInfoRecord],
    outdated: [HomebrewCaskOutdatedRecord] = [],
    listing: [String]? = nil,
    installedTokens: [String]? = nil,
    stagedBindings: [HomebrewCaskStagedBinding]? = nil,
    declaredNames: [String]? = nil,
    selectedTarget: String? = nil,
    localVersion: String? = nil
) -> HomebrewCaskEvaluation {
    HomebrewCaskStatusResolver.evaluate(
        declaredNames: declaredNames ?? [fixture.token],
        selectedTarget: selectedTarget ?? fixture.selectedTarget,
        localVersion: localVersion ?? fixture.localVersion,
        batch: resolverBatch(
            fixture: fixture,
            records: records,
            outdated: outdated,
            listing: listing,
            installedTokens: installedTokens,
            stagedBindings: stagedBindings
        )
    )
}

private func verifiedStatus(_ evaluation: HomebrewCaskEvaluation) -> VersionStatus? {
    guard case .verified(let comparison) = evaluation else { return nil }
    return comparison.status
}

private func unknownReason(_ evaluation: HomebrewCaskEvaluation) -> UnknownReason? {
    guard case .unknown(let reason) = evaluation else { return nil }
    return reason
}

private func runBatch(
    _ fixture: CaskProbeFixture,
    tokens: [String],
    selections: [ObservedExecutable]? = nil,
    runner: UpdateCommandRunner
) async -> Result<HomebrewCaskBatchResult, HomebrewCaskBatchError> {
    await HomebrewCaskUpdateProbe.runBatchWhileAdmitted(
        manager: fixture.observedManager,
        selections: selections ?? [fixture.observedSelection],
        tokens: tokens,
        environment: fixture.environment,
        runner: runner
    )
}

// MARK: Parse behavior

@Test func infoParserReadsTheManagerFieldsAndKeepsNullAutoUpdatesAsNotDeclared() {
    let data = caskInfoJSON([
        caskInfoRecord(
            token: "codex", version: "1.2.3", installed: "1.2.3",
            autoUpdates: "null", pinned: true, outdated: false, disabled: false
        ),
        caskInfoRecord(
            token: "managed", version: "latest", installed: "latest", autoUpdates: "true"
        ),
        caskInfoRecord(
            token: "legacy", version: "1,2", installed: "1,2", autoUpdates: "false",
            deprecated: true
        ),
    ])
    let records = HomebrewCaskUpdateProbe.parseInfo(data)
    #expect(records?.count == 3)
    #expect(records?[0].token == "codex")
    #expect(records?[0].installed == .string("1.2.3"))
    #expect(records?[0].autoUpdates == nil)
    #expect(records?[0].pinned == true)
    #expect(records?[1].autoUpdates == true)
    #expect(records?[2].autoUpdates == false)
    #expect(records?.allSatisfy(\.isValid) == true)
}

@Test func infoParserKeepsMalformedRecordsAsPoisoningMarkersButRejectsUnattributableData() {
    let malformedFlags = caskInfoJSON([
        caskInfoRecord(token: "codex", version: "1.0.0", installed: "1.0.0", autoUpdates: "1")
    ])
    let records = HomebrewCaskUpdateProbe.parseInfo(malformedFlags)
    #expect(records?.count == 1)
    #expect(records?[0].isValid == false)

    let missingInstalled = caskInfoJSON([
        "{\"token\":\"codex\",\"full_token\":\"codex\",\"tap\":\"homebrew/cask\",\"version\":\"1.0.0\",\"pinned\":false,\"outdated\":false,\"disabled\":false}"
    ])
    #expect(HomebrewCaskUpdateProbe.parseInfo(missingInstalled)?.first?.isValid == false)

    let contradictory = caskInfoJSON([
        caskInfoRecord(
            token: "codex", fullToken: "owner/tap/codex", tap: "other/tap",
            version: "1.0.0", installed: "1.0.0"
        )
    ])
    #expect(HomebrewCaskUpdateProbe.parseInfo(contradictory)?.first?.isValid == false)

    #expect(HomebrewCaskUpdateProbe.parseInfo(Data("{}".utf8)) == nil)
    #expect(HomebrewCaskUpdateProbe.parseInfo(Data("{\"formulae\":[]}".utf8)) == nil)
    #expect(HomebrewCaskUpdateProbe.parseInfo(Data("{\"casks\":[1]}".utf8)) == nil)
    #expect(HomebrewCaskUpdateProbe.parseInfo(Data("{\"casks\":[{\"version\":\"1\"}]}".utf8)) == nil)
    #expect(HomebrewCaskUpdateProbe.parseInfo(Data("\u{FEFF}{}".utf8)) == nil)
    #expect(HomebrewCaskUpdateProbe.parseInfo(Data("{\"casks\":[]}\u{0}".utf8)) == nil)
}

@Test func malformedUnrelatedRecordsAreIsolatedInsteadOfFailingTheEnvelope() {
    let info = caskInfoJSON([
        caskInfoRecord(token: "codex", version: "1.0.0", installed: "1.0.0"),
        #"{"token":"bad/token","full_token":"bad/token","tap":"homebrew/cask","version":"1.0.0","installed":"1.0.0","pinned":false,"outdated":false,"disabled":false}"#,
    ])
    let records = HomebrewCaskUpdateProbe.parseInfo(info)
    #expect(records?.count == 2)
    #expect(records?[0].isValid == true)
    #expect(records?[1].isValid == false)
    // A malformed *unattributable* element still fails the whole batch.
    #expect(HomebrewCaskUpdateProbe.parseInfo(Data("{\"casks\":[{\"version\":\"1\"}]}".utf8)) == nil)

    let outdated = caskOutdatedJSON([
        caskOutdatedRecord(name: "codex", current: "1.0.0", installed: ["1.0.0"]),
        #"{"name":"bad name","current_version":"1.0.0","installed_versions":["1.0.0"],"pinned":false}"#,
    ])
    let outdatedRecords = HomebrewCaskUpdateProbe.parseOutdated(outdated)
    #expect(outdatedRecords?.count == 2)
    #expect(outdatedRecords?[0].isValid == true)
    #expect(outdatedRecords?[1].isValid == false)
}

@Test func outdatedParserKeysOnTheBareTokenAndKeepsMalformedRecords() {
    let data = caskOutdatedJSON([
        caskOutdatedRecord(name: "codex", current: "1.2.4", installed: ["1.2.3"]),
        "{\"name\":\"broken\",\"current_version\":1,\"installed_versions\":[\"1\"],\"pinned\":false}",
    ])
    let records = HomebrewCaskUpdateProbe.parseOutdated(data)
    #expect(records?.count == 2)
    #expect(records?[0].isValid == true)
    #expect(records?[0].currentVersion == "1.2.4")
    #expect(records?[1].isValid == false)
    #expect(HomebrewCaskUpdateProbe.parseOutdated(Data("{\"casks\":[{\"current_version\":\"1\"}]}".utf8)) == nil)
}

@Test func listingParserRejectsTraversalOutsideRootsAndMalformedLines() throws {
    let root = try caskProbeScratchRoot("listing")
    let inside = root.appendingPathComponent("codex/1.0.0/bin/codex").path
    try FileManager.default.createDirectory(
        at: root.appendingPathComponent("codex/1.0.0/bin"), withIntermediateDirectories: true
    )
    try Data("x".utf8).write(to: URL(fileURLWithPath: inside))
    let identity = FileIdentityObserver.observeDirectory(path: root.path)!
    func parse(_ lines: [String]) -> [String]? {
        HomebrewCaskUpdateProbe.parseListing(
            listingData(lines), reportedCaskroom: root.path, caskroomIdentity: identity
        )
    }
    #expect(parse([inside]) == [inside])
    #expect(HomebrewCaskUpdateProbe.parseListing(
        Data(), reportedCaskroom: root.path, caskroomIdentity: identity
    ) == nil)
    #expect(parse(["/elsewhere/codex"]) == nil)
    #expect(parse(["relative/codex"]) == nil)
    #expect(parse([""]) == nil)
    #expect(parse(["\(root.path)/../codex"]) == nil)
    #expect(parse([root.path]) == nil)
    #expect(parse(["\(root.path)2/codex"]) == nil)
}

@Test func reportedCaskroomAliasIsNormalizedByComponentsAndFinalLinksStayIntact() throws {
    let fixture = try CaskProbeFixture("alias-listing")
    let alias = fixture.root.appendingPathComponent("reported caskroom", isDirectory: true)
    try FileManager.default.createSymbolicLink(
        atPath: alias.path, withDestinationPath: fixture.caskroom.path
    )
    let aliasIdentity = FileIdentityObserver.observeDirectory(path: alias.path)!
    #expect(aliasIdentity.canonicalPath == fixture.boundCaskroom.canonicalPath)

    let aliasLine = alias.appendingPathComponent(
        "\(fixture.token)/\(fixture.version)/bin/\(fixture.token)"
    ).path
    let parsed = HomebrewCaskUpdateProbe.parseListing(
        listingData([aliasLine]),
        reportedCaskroom: alias.path,
        caskroomIdentity: aliasIdentity
    )
    #expect(parsed == [fixture.selectedTarget])
    #expect(parsed?.first?.hasSuffix("/bin/\(fixture.token)") == true)

    // A `.app` link line keeps its final link component; it is not resolved by the parser.
    let appLink = fixture.caskroom.appendingPathComponent(
        "\(fixture.token)/\(fixture.version)/Staged.app"
    )
    let bundle = fixture.root.appendingPathComponent("Applications/Fixture.app", isDirectory: true)
    try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
        atPath: appLink.path, withDestinationPath: bundle.path
    )
    let appLine = alias.appendingPathComponent(
        "\(fixture.token)/\(fixture.version)/Staged.app"
    ).path
    let appParsed = HomebrewCaskUpdateProbe.parseListing(
        listingData([appLine]),
        reportedCaskroom: alias.path,
        caskroomIdentity: aliasIdentity
    )
    #expect(appParsed == [appLink.path])
    #expect(appParsed?.first?.hasSuffix("/Staged.app") == true)
}

// MARK: Batch contract

@Test func caskBatchUsesTheExactFiveCommandsInOrder() async throws {
    let fixture = try CaskProbeFixture("argv")
    let info = caskInfoJSON([
        caskInfoRecord(token: fixture.token, version: fixture.version, installed: fixture.version)
    ])
    let runner = caskRunner(
        prefix: fixture.prefix.path,
        caskroom: fixture.caskroom.path,
        info: info,
        outdated: caskOutdatedJSON([]),
        listing: listingData([fixture.selectedTarget]),
        infoTokens: [fixture.token],
        listTokens: [fixture.token]
    )
    let result = await runBatch(
        fixture,
        tokens: [fixture.token, fixture.token],
        runner: runner
    )
    guard case .success(let batch) = result else {
        Issue.record("expected a successful batch, got \(result)")
        return
    }
    #expect(runner.calls == [
        ["--prefix"],
        ["--caskroom"],
        ["info", "--json=v2", "--cask", fixture.token],
        ["outdated", "--json=v2", "--cask"],
        ["list", "--verbose", "--cask", fixture.token],
    ])
    #expect(batch.queryCount == 5)
    #expect(batch.prefix.reportedPath == fixture.prefix.path)
    #expect(batch.prefix.canonicalPath == fixture.boundPrefix.canonicalPath)
    #expect(batch.caskroom.reportedPath == fixture.caskroom.path)
    #expect(batch.caskroom.canonicalPath == fixture.boundCaskroom.canonicalPath)
    #expect(batch.installedTokens == [fixture.token])
    #expect(batch.listing == [fixture.selectedTarget])
    #expect(batch.stagedBindings.contains(fixture.stagedBinding()))
    // The diagnostic toggles reach every manager query.
    #expect(runner.environments.allSatisfy {
        $0["HOMEBREW_NO_AUTO_UPDATE"] == "1" && $0["HOMEBREW_NO_ANALYTICS"] == "1"
    })
}

@Test func caskBatchSkipsTheListQueryWhenNoInstalledStringIsReported() async throws {
    let fixture = try CaskProbeFixture("uninstalled")
    let info = caskInfoJSON([
        caskInfoRecord(token: fixture.token, version: fixture.version, installed: nil)
    ])
    let runner = caskRunner(
        prefix: fixture.prefix.path,
        caskroom: fixture.caskroom.path,
        info: info,
        outdated: caskOutdatedJSON([]),
        listing: Data(),
        infoTokens: [fixture.token],
        listTokens: []
    )
    let result = await runBatch(fixture, tokens: [fixture.token], runner: runner)
    guard case .success(let batch) = result else {
        Issue.record("expected a successful batch, got \(result)")
        return
    }
    #expect(batch.queryCount == 4)
    #expect(batch.listing.isEmpty)
    #expect(runner.calls.map { $0[0] } == ["--prefix", "--caskroom", "info", "outdated"])
}

@Test func invalidCaskTokensFailBeforeAnyProcess() async throws {
    let fixture = try CaskProbeFixture("invalid-token")
    let runner = ScriptedRunner { _, arguments in
        Issue.record("unexpected command for invalid token: \(arguments)")
        return .failure(.spawnFailure)
    }
    for token in ["-cask", "a/b/c/d", "a/b", ".metadata", "bad topic", "bad\u{0}token"] {
        let result = await runBatch(fixture, tokens: [token], runner: runner)
        #expect(result == .failure(.invalidToken), "token \(token.debugDescription)")
    }
    #expect(HomebrewCaskUpdateProbe.isValidDeclaredCaskName("owner/tap/tool"))
    #expect(HomebrewCaskUpdateProbe.isValidBareCaskToken("tool"))
    #expect(!HomebrewCaskUpdateProbe.isValidBareCaskToken("owner/tap/tool"))
    #expect(runner.calls.isEmpty)
}

@Test func fullyQualifiedCaskDeclarationIsQueriedAndListsTheVerifiedFullIdentity() async throws {
    let fixture = try CaskProbeFixture(
        "qualified", token: "codex", fullToken: "owner/tap/codex"
    )
    let info = caskInfoJSON([
        caskInfoRecord(
            token: "codex", fullToken: "owner/tap/codex", tap: "owner/tap",
            version: fixture.version, installed: fixture.version
        )
    ])
    let runner = caskRunner(
        prefix: fixture.prefix.path,
        caskroom: fixture.caskroom.path,
        info: info,
        outdated: caskOutdatedJSON([]),
        listing: listingData([fixture.selectedTarget]),
        infoTokens: ["owner/tap/codex"],
        listTokens: ["owner/tap/codex"]
    )
    let result = await runBatch(
        fixture, tokens: ["owner/tap/codex"], runner: runner
    )
    guard case .success(let batch) = result else {
        Issue.record("expected a successful fully qualified batch, got \(result)")
        return
    }
    #expect(runner.calls[2] == ["info", "--json=v2", "--cask", "owner/tap/codex"])
    #expect(runner.calls[4] == ["list", "--verbose", "--cask", "owner/tap/codex"])
    #expect(batch.installedTokens == ["codex"])
    #expect(batch.listingNames == ["owner/tap/codex"])
    #expect(batch.records["codex"]?.first?.fullToken == "owner/tap/codex")
}

@Test func caskBatchFailuresAreTypedAndNeverSuccessfulEmptyMetadata() async throws {
    let fixture = try CaskProbeFixture("failures")
    let validInfo = caskInfoJSON([
        caskInfoRecord(token: fixture.token, version: fixture.version, installed: fixture.version)
    ])

    func run(_ handler: @escaping @Sendable ([String]) -> CommandOutcome) async
        -> Result<HomebrewCaskBatchResult, HomebrewCaskBatchError>
    {
        await runBatch(
            fixture,
            tokens: [fixture.token],
            runner: ScriptedRunner { _, arguments in handler(arguments) }
        )
    }

    #expect(await run { _ in .failure(.networkUnavailable) }
        == .failure(.commandFailed(.networkUnavailable)))
    #expect(await run { arguments in
        if arguments == ["--prefix"] { return .success(Data((fixture.prefix.path + "\n").utf8)) }
        if arguments == ["--caskroom"] { return .success(Data((fixture.caskroom.path + "\n").utf8)) }
        return .success(Data("not-json".utf8))
    } == .failure(.invalidOutput))
    #expect(await run { arguments in
        if arguments == ["--prefix"] { return .success(Data((fixture.prefix.path + "\n").utf8)) }
        if arguments == ["--caskroom"] { return .success(Data((fixture.caskroom.path + "\n").utf8)) }
        if arguments.first == "info" { return .success(validInfo) }
        return .success(Data("{}".utf8))
    } == .failure(.invalidOutput))
    #expect(await run { arguments in
        if arguments == ["--prefix"] { return .success(Data((fixture.prefix.path + "\n").utf8)) }
        if arguments == ["--caskroom"] { return .success(Data((fixture.caskroom.path + "\n").utf8)) }
        if arguments.first == "info" { return .success(validInfo) }
        if arguments.first == "outdated" { return .success(caskOutdatedJSON([])) }
        return .success(Data("relative/line".utf8))
    } == .failure(.invalidOutput))
    #expect(await run { arguments in
        if arguments == ["--prefix"] { return .success(Data((fixture.prefix.path + "\n").utf8)) }
        if arguments == ["--caskroom"] { return .success(Data((fixture.caskroom.path + "\n").utf8)) }
        if arguments.first == "info" { return .success(validInfo) }
        if arguments.first == "outdated" { return .success(caskOutdatedJSON([])) }
        return .failure(.timedOut)
    } == .failure(.commandFailed(.timedOut)))
}

@Test func missingPrefixAndCaskroomAreTypedUnknownsThatLaunchNoFurtherQuery() async throws {
    let fixture = try CaskProbeFixture("missing-root")
    let missingPrefix = ScriptedRunner { _, arguments in
        #expect(arguments == ["--prefix"])
        return .success(Data((fixture.root.appendingPathComponent("missing").path + "\n").utf8))
    }
    #expect(await runBatch(fixture, tokens: [fixture.token], runner: missingPrefix)
        == .failure(.identityUnverified))
    #expect(missingPrefix.calls.count == 1)

    let missingCaskroom = ScriptedRunner { _, arguments in
        if arguments == ["--prefix"] {
            return .success(Data((fixture.prefix.path + "\n").utf8))
        }
        #expect(arguments == ["--caskroom"])
        return .success(Data((fixture.root.appendingPathComponent("missing2").path + "\n").utf8))
    }
    #expect(await runBatch(fixture, tokens: [fixture.token], runner: missingCaskroom)
        == .failure(.identityUnverified))
    #expect(missingCaskroom.calls.count == 2)
}

@Test func samePathSelectedExecutableReplacementStopsBeforeTheNextQuery() async throws {
    let fixture = try CaskProbeFixture("replace-selection")
    let info = caskInfoJSON([
        caskInfoRecord(token: fixture.token, version: fixture.version, installed: fixture.version)
    ])
    let runner = caskRunner(
        prefix: fixture.prefix.path,
        caskroom: fixture.caskroom.path,
        info: info,
        outdated: caskOutdatedJSON([]),
        listing: listingData([fixture.selectedTarget]),
        infoTokens: [fixture.token],
        listTokens: [fixture.token]
    ) { arguments in
        if arguments == ["--caskroom"] {
            // Replace the executable at the SAME canonical path.
            try? Data("#!/bin/sh\nprintf '2.0.0\\n'\n".utf8)
                .write(to: URL(fileURLWithPath: fixture.selectedTarget))
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: fixture.selectedTarget
            )
        }
    }
    let result = await runBatch(fixture, tokens: [fixture.token], runner: runner)
    #expect(result == .failure(.identityUnverified))
    #expect(runner.calls == [["--prefix"], ["--caskroom"]])
}

@Test func replacedManagerStopsBeforeTheNextQuery() async throws {
    let fixture = try CaskProbeFixture("replace-manager")
    let runner = ScriptedRunner { _, arguments in
        #expect(arguments == ["--prefix"])
        // Same path, new vnode: the snapshot identity no longer matches.
        try? FileManager.default.removeItem(atPath: fixture.brewPath)
        try? Data("#!/bin/sh\nexit 0\n".utf8).write(to: URL(fileURLWithPath: fixture.brewPath))
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: fixture.brewPath
        )
        return .success(Data((fixture.prefix.path + "\n").utf8))
    }
    let result = await runBatch(fixture, tokens: [fixture.token], runner: runner)
    #expect(result == .failure(.identityUnverified))
    #expect(runner.calls.count == 1)
}

@Test func retargetedCaskroomOrPrefixStopsBeforeTheNextQuery() async throws {
    let fixture = try CaskProbeFixture("retarget-root")
    let replacement = fixture.root.appendingPathComponent("replacement-caskroom", isDirectory: true)
    try FileManager.default.createDirectory(at: replacement, withIntermediateDirectories: true)
    let runner = ScriptedRunner { _, arguments in
        if arguments == ["--prefix"] {
            return .success(Data((fixture.prefix.path + "\n").utf8))
        }
        if arguments == ["--caskroom"] {
            return .success(Data((fixture.caskroom.path + "\n").utf8))
        }
        #expect(arguments.first == "info")
        // Retarget the bound Caskroom while the info query is in flight.
        try? FileManager.default.moveItem(
            at: fixture.caskroom, to: replacement.appendingPathComponent("moved")
        )
        try? FileManager.default.createSymbolicLink(
            atPath: fixture.caskroom.path,
            withDestinationPath: replacement.appendingPathComponent("moved").path
        )
        return .success(caskInfoJSON([]))
    }
    let result = await runBatch(fixture, tokens: [fixture.token], runner: runner)
    #expect(result == .failure(.identityUnverified))
    #expect(runner.calls.count == 3)

    let prefixFixture = try CaskProbeFixture("retarget-prefix")
    let prefixReplacement = prefixFixture.root.appendingPathComponent("moved-prefix", isDirectory: true)
    let prefixRunner = ScriptedRunner { _, arguments in
        if arguments == ["--prefix"] {
            return .success(Data((prefixFixture.prefix.path + "\n").utf8))
        }
        if arguments == ["--caskroom"] {
            return .success(Data((prefixFixture.caskroom.path + "\n").utf8))
        }
        try? FileManager.default.moveItem(at: prefixFixture.prefix, to: prefixReplacement)
        try? FileManager.default.createSymbolicLink(
            atPath: prefixFixture.prefix.path, withDestinationPath: prefixReplacement.path
        )
        return .success(caskInfoJSON([]))
    }
    #expect(await runBatch(prefixFixture, tokens: [prefixFixture.token], runner: prefixRunner)
        == .failure(.identityUnverified))
    #expect(prefixRunner.calls.count == 3)
}

@Test func reportedCaskroomAliasProducesACanonicalListingAndAVerifiedBatch() async throws {
    let fixture = try CaskProbeFixture("reported-alias")
    let alias = fixture.root.appendingPathComponent("reported alias", isDirectory: true)
    try FileManager.default.createSymbolicLink(
        atPath: alias.path, withDestinationPath: fixture.caskroom.path
    )
    let aliasLine = alias.appendingPathComponent(
        "\(fixture.token)/\(fixture.version)/bin/\(fixture.token)"
    ).path
    let info = caskInfoJSON([
        caskInfoRecord(token: fixture.token, version: fixture.version, installed: fixture.version)
    ])
    let runner = caskRunner(
        prefix: fixture.prefix.path,
        caskroom: alias.path,
        info: info,
        outdated: caskOutdatedJSON([]),
        listing: listingData([aliasLine]),
        infoTokens: [fixture.token],
        listTokens: [fixture.token]
    )
    let result = await runBatch(fixture, tokens: [fixture.token], runner: runner)
    guard case .success(let batch) = result else {
        Issue.record("expected the reported alias to verify, got \(result)")
        return
    }
    #expect(batch.caskroom.reportedPath == alias.path)
    #expect(batch.caskroom.canonicalPath == fixture.boundCaskroom.canonicalPath)
    #expect(batch.listing == [fixture.selectedTarget])
    let evaluation = HomebrewCaskStatusResolver.evaluate(
        declaredNames: [fixture.token],
        selectedTarget: fixture.selectedTarget,
        localVersion: fixture.localVersion,
        batch: batch
    )
    #expect(verifiedStatus(evaluation) == .upToDate(
        installed: Version("1.0.0"), latest: Version("1.0.0")
    ))
}

// MARK: Tri-state branches

@Test func equalManagerStringsThatAreNotOutdatedAreUpToDate() throws {
    let fixture = try CaskProbeFixture("up-to-date")
    let evaluation = evaluate(
        fixture,
        records: [installedRecord(fixture)],
        localVersion: "1.0.0"
    )
    #expect(verifiedStatus(evaluation) == .upToDate(
        installed: Version("1.0.0"), latest: Version(fixture.version)
    ))
    guard case .verified(let comparison) = evaluation else {
        Issue.record("expected a verified comparison")
        return
    }
    #expect(comparison.managerOutdated == false)
    #expect(comparison.pinned == false)
}

@Test func managerOutdatedVerdictIsAnUpdateWithTheMetadataVersionVerbatim() throws {
    let fixture = try CaskProbeFixture("update")
    let evaluation = evaluate(
        fixture,
        records: [installedRecord(fixture, version: "1.2.4", outdated: true)],
        outdated: [HomebrewCaskOutdatedRecord(
            name: fixture.token, currentVersion: "1.2.4",
            installedVersions: [fixture.version]
        )]
    )
    #expect(verifiedStatus(evaluation) == .updateAvailable(
        installed: Version("1.0.0"), latest: Version("1.2.4")
    ))
    #expect(verifiedStatus(evaluation)?.isVerifiedComparison == true)
}

@Test func formulaOrderingNeverVetoesAgreeingManagerVerdicts() throws {
    // A fixture where the manager's metadata version is LOWER than the installed string but both
    // manager records attest an update. The shared formula comparator would veto this; cask
    // latest-check must not consult it.
    let fixture = try CaskProbeFixture("oracle-veto")
    let evaluation = evaluate(
        fixture,
        records: [installedRecord(fixture, version: "0.9.0", outdated: true)],
        outdated: [HomebrewCaskOutdatedRecord(
            name: fixture.token, currentVersion: "0.9.0",
            installedVersions: [fixture.version]
        )]
    )
    #expect(verifiedStatus(evaluation) == .updateAvailable(
        installed: Version("1.0.0"), latest: Version("0.9.0")
    ))
}

@Test func commaVersionCaskUsesTheManagerVerdictAndNeverAnInventedOrdering() throws {
    let fixture = try CaskProbeFixture(
        "comma", version: "1.2.3,9", localVersion: "1.2.3"
    )
    let updated = evaluate(
        fixture,
        records: [installedRecord(fixture, version: "1.2.4,10", outdated: true)],
        outdated: [HomebrewCaskOutdatedRecord(
            name: fixture.token, currentVersion: "1.2.4,10",
            installedVersions: [fixture.version]
        )]
    )
    #expect(verifiedStatus(updated) == .updateAvailable(
        installed: Version("1.2.3"), latest: Version("1.2.4,10")
    ))
    guard case .verified(let comparison) = updated else {
        Issue.record("expected a verified comma cask")
        return
    }
    #expect(comparison.installedVersion == "1.2.3,9")

    let inconsistent = evaluate(
        fixture,
        records: [installedRecord(fixture, version: "1.2.4,10", outdated: false)]
    )
    #expect(unknownReason(inconsistent) == .caskMetadataInconsistent)
}

@Test func latestAutoUpdatesAndDisabledRetainTheirTypedUnknowns() throws {
    let fixture = try CaskProbeFixture("typed")
    let latest = evaluate(
        fixture,
        records: [installedRecord(fixture, version: "latest", outdated: true)],
        outdated: [HomebrewCaskOutdatedRecord(
            name: fixture.token, currentVersion: "latest",
            installedVersions: [fixture.version]
        )]
    )
    #expect(unknownReason(latest) == .caskTracksLatest)

    let managed = evaluate(
        fixture,
        records: [installedRecord(
            fixture, version: "1.2.4", autoUpdates: true, outdated: true
        )],
        outdated: [HomebrewCaskOutdatedRecord(
            name: fixture.token, currentVersion: "1.2.4",
            installedVersions: [fixture.version]
        )]
    )
    #expect(unknownReason(managed) == .caskAutoUpdates)

    let disabled = evaluate(
        fixture,
        records: [installedRecord(
            fixture, version: "1.2.4", outdated: true, disabled: true
        )],
        outdated: [HomebrewCaskOutdatedRecord(
            name: fixture.token, currentVersion: "1.2.4",
            installedVersions: [fixture.version]
        )]
    )
    #expect(unknownReason(disabled) == .caskDisabled)
}

@Test func nullAutoUpdatesProceedsWithTheComparison() throws {
    let fixture = try CaskProbeFixture("null-auto-updates")
    let evaluation = evaluate(
        fixture,
        records: [installedRecord(
            fixture, version: "1.2.4", autoUpdates: nil, outdated: true
        )],
        outdated: [HomebrewCaskOutdatedRecord(
            name: fixture.token, currentVersion: "1.2.4",
            installedVersions: [fixture.version]
        )]
    )
    #expect(verifiedStatus(evaluation) == .updateAvailable(
        installed: Version("1.0.0"), latest: Version("1.2.4")
    ))
}

@Test func deprecatedAloneDoesNotPreventATruthfulComparison() throws {
    let fixture = try CaskProbeFixture("deprecated")
    let record = HomebrewCaskInfoRecord(
        token: fixture.token, fullToken: fixture.fullToken, tap: "homebrew/cask",
        version: "1.0.0", installed: .string(fixture.version)
    )
    // The parser ignores `deprecated`; a deprecated, enabled cask compares normally.
    let data = caskInfoJSON([
        caskInfoRecord(
            token: fixture.token, version: "1.0.0", installed: fixture.version,
            disabled: false, deprecated: true
        )
    ])
    #expect(HomebrewCaskUpdateProbe.parseInfo(data)?.first?.isValid == true)
    let evaluation = evaluate(fixture, records: [record])
    #expect(verifiedStatus(evaluation) == .upToDate(
        installed: Version("1.0.0"), latest: Version("1.0.0")
    ))
}

@Test func pinnedNewerCaskRemainsAnUpdateAndKeepsThePinFlag() throws {
    let fixture = try CaskProbeFixture("pinned")
    let evaluation = evaluate(
        fixture,
        records: [installedRecord(
            fixture, version: "1.2.4", pinned: true, outdated: true
        )],
        outdated: [HomebrewCaskOutdatedRecord(
            name: fixture.token, currentVersion: "1.2.4",
            installedVersions: [fixture.version], pinned: true
        )]
    )
    guard case .verified(let comparison) = evaluation else {
        Issue.record("expected a verified pinned update")
        return
    }
    #expect(comparison.status == .updateAvailable(
        installed: Version("1.0.0"), latest: Version("1.2.4")
    ))
    #expect(comparison.pinned == true)
}

@Test func unequalNotOutdatedPairIsInconsistentInBothDirections() throws {
    let fixture = try CaskProbeFixture("direction")
    let inconsistent = evaluate(
        fixture,
        records: [installedRecord(fixture, version: "1.2.3", outdated: false)]
    )
    #expect(unknownReason(inconsistent) == .caskMetadataInconsistent)

    // The formula comparator used to name this "newer". Cask strings are opaque and no manager
    // record attests a direction, so the same inconsistent reason applies.
    let newer = evaluate(
        fixture,
        records: [installedRecord(fixture, version: "0.9.0", outdated: false)]
    )
    #expect(unknownReason(newer) == .caskMetadataInconsistent)
}

@Test func localVersionMayDifferFromTheManagerInstalledDirectory() throws {
    let fixture = try CaskProbeFixture(
        "local-differs", version: "1.0.0,42", localVersion: "1.0.0"
    )
    let evaluation = evaluate(
        fixture,
        records: [installedRecord(fixture, version: "1.0.0,42", outdated: false)],
        localVersion: "1.0.0"
    )
    guard case .verified(let comparison) = evaluation else {
        Issue.record("expected the manager strings to verify")
        return
    }
    #expect(comparison.installedVersion == "1.0.0,42")
    #expect(comparison.status == .upToDate(
        installed: Version("1.0.0"), latest: Version("1.0.0,42")
    ))
}

// MARK: Identity, alias and membership poisoning

@Test func duplicateOrAliasedManagerRecordsAreRefused() throws {
    let fixture = try CaskProbeFixture("aliases")
    let duplicate = evaluate(
        fixture,
        records: [installedRecord(fixture), installedRecord(fixture)]
    )
    #expect(unknownReason(duplicate) == .identityUnverified)

    let tapped = try CaskProbeFixture(
        "tapped", token: "codex", fullToken: "owner/tap/codex"
    )
    // A bare declaration never claims a tapped full token.
    let bareDeclaration = HomebrewCaskStatusResolver.evaluate(
        declaredNames: ["codex"],
        selectedTarget: tapped.selectedTarget,
        localVersion: tapped.localVersion,
        batch: resolverBatch(
            fixture: tapped,
            records: [installedRecord(tapped, tap: "owner/tap")]
        )
    )
    #expect(unknownReason(bareDeclaration) == .identityUnverified)

    // The full declaration verifies.
    let fullDeclaration = HomebrewCaskStatusResolver.evaluate(
        declaredNames: ["owner/tap/codex"],
        selectedTarget: tapped.selectedTarget,
        localVersion: tapped.localVersion,
        batch: resolverBatch(
            fixture: tapped,
            records: [installedRecord(tapped, tap: "owner/tap")]
        )
    )
    #expect(verifiedStatus(fullDeclaration) == .upToDate(
        installed: Version("1.0.0"), latest: Version("1.0.0")
    ))
}

@Test func duplicateBareTokenClaimsAcrossTheInfoResponseAreRefused() throws {
    let fixture = try CaskProbeFixture("duplicate-bare")
    // Two different tapped full_tokens claim the same bare token and the same caskroom slot.
    let first = installedRecord(
        fixture, fullToken: "owner/tap/codex", tap: "owner/tap"
    )
    let second = installedRecord(
        fixture, fullToken: "other/tap/codex", tap: "other/tap"
    )
    #expect(unknownReason(evaluate(
        fixture, records: [first, second], declaredNames: ["codex"]
    )) == .identityUnverified)
    #expect(unknownReason(evaluate(
        fixture, records: [first, second], declaredNames: ["owner/tap/codex"]
    )) == .identityUnverified)
    #expect(unknownReason(evaluate(
        fixture, records: [first, second], declaredNames: ["other/tap/codex"]
    )) == .identityUnverified)

    // A duplicate bare token that does NOT belong to this subject is not this subject's proof.
    let unrelated = HomebrewCaskInfoRecord(
        token: "other", fullToken: "other", tap: "homebrew/cask",
        version: "1.0.0", installed: .string("1.0.0")
    )
    let evaluation = evaluate(
        fixture,
        records: [installedRecord(fixture), unrelated, unrelated]
    )
    #expect(verifiedStatus(evaluation) == .upToDate(
        installed: Version("1.0.0"), latest: Version("1.0.0")
    ))
}

@Test func renamedOldTokenAndUninstalledRecordAreRefused() throws {
    let fixture = try CaskProbeFixture("renamed")
    let renamed = evaluate(
        fixture,
        records: [HomebrewCaskInfoRecord(
            token: "new-token", fullToken: "new-token", tap: "homebrew/cask",
            version: "1.0.0", installed: .string(fixture.version),
            oldTokens: [fixture.token]
        )]
    )
    #expect(unknownReason(renamed) == .identityUnverified)

    let uninstalled = evaluate(
        fixture,
        records: [HomebrewCaskInfoRecord(
            token: fixture.token, fullToken: fixture.fullToken, tap: "homebrew/cask",
            version: "1.0.0", installed: .null
        )]
    )
    #expect(unknownReason(uninstalled) == .identityUnverified)
}

@Test func outdatedRecordIdentityVersionAndInstalledAgreementAreCrossChecked() throws {
    let fixture = try CaskProbeFixture("outdated-identity")
    let record = installedRecord(fixture, version: "1.2.4", outdated: true)

    let wrongCurrent = evaluate(
        fixture, records: [record],
        outdated: [HomebrewCaskOutdatedRecord(
            name: fixture.token, currentVersion: "9.9.9",
            installedVersions: [fixture.version]
        )]
    )
    #expect(unknownReason(wrongCurrent) == .identityUnverified)

    let wrongInstalled = evaluate(
        fixture, records: [record],
        outdated: [HomebrewCaskOutdatedRecord(
            name: fixture.token, currentVersion: "1.2.4",
            installedVersions: ["0.0.1"]
        )]
    )
    #expect(unknownReason(wrongInstalled) == .identityUnverified)

    let wrongPin = evaluate(
        fixture, records: [record],
        outdated: [HomebrewCaskOutdatedRecord(
            name: fixture.token, currentVersion: "1.2.4",
            installedVersions: [fixture.version], pinned: true
        )]
    )
    #expect(unknownReason(wrongPin) == .identityUnverified)

    let duplicate = evaluate(
        fixture, records: [record],
        outdated: [
            HomebrewCaskOutdatedRecord(
                name: fixture.token, currentVersion: "1.2.4",
                installedVersions: [fixture.version]
            ),
            HomebrewCaskOutdatedRecord(
                name: fixture.token, currentVersion: "1.2.4",
                installedVersions: [fixture.version]
            ),
        ]
    )
    #expect(unknownReason(duplicate) == .identityUnverified)

    let infoSaysOutdated = evaluate(
        fixture,
        records: [installedRecord(fixture, version: "1.2.4", outdated: true)]
    )
    #expect(unknownReason(infoSaysOutdated) == .identityUnverified)

    let listSaysOutdated = evaluate(
        fixture,
        records: [installedRecord(fixture, version: "1.2.4", outdated: false)],
        outdated: [HomebrewCaskOutdatedRecord(
            name: fixture.token, currentVersion: "1.2.4",
            installedVersions: [fixture.version]
        )]
    )
    #expect(unknownReason(listSaysOutdated) == .identityUnverified)
}

@Test func foreignFullTokenOutdatedKeyPoisonsATappedCaskWithoutStrippingUnrelatedRows() throws {
    let fixture = try CaskProbeFixture(
        "foreign-key", token: "codex", fullToken: "owner/tap/codex"
    )
    let evaluation = HomebrewCaskStatusResolver.evaluate(
        declaredNames: ["owner/tap/codex"],
        selectedTarget: fixture.selectedTarget,
        localVersion: fixture.localVersion,
        batch: resolverBatch(
            fixture: fixture,
            records: [installedRecord(fixture, tap: "owner/tap")],
            outdated: [
                HomebrewCaskOutdatedRecord(
                    name: "owner/tap/codex", currentVersion: "1.0.0",
                    installedVersions: [fixture.version]
                ),
                HomebrewCaskOutdatedRecord(
                    name: "unrelated", currentVersion: "9.9.9",
                    installedVersions: ["9.9.8"]
                ),
            ]
        )
    )
    #expect(unknownReason(evaluation) == .identityUnverified)
    // The manager-wide rows are retained; only this subject's association is refused.
    #expect(evaluation != .verified(HomebrewCaskComparison(
        token: fixture.token, fullToken: fixture.fullToken, tap: "owner/tap",
        installedVersion: fixture.version, version: "1.0.0", pinned: false,
        managerOutdated: false,
        status: .upToDate(installed: Version("1.0.0"), latest: Version("1.0.0"))
    )))
}

@Test func membershipMustNameTheExactSelectedTargetUnderTheReportedCaskroom() throws {
    let fixture = try CaskProbeFixture("membership")
    let missing = evaluate(
        fixture, records: [installedRecord(fixture)], listing: []
    )
    #expect(unknownReason(missing) == .identityUnverified)

    let sibling = fixture.caskroom
        .appendingPathComponent("other/1.0.0/bin/other").path
    let foreign = evaluate(
        fixture, records: [installedRecord(fixture)], listing: [sibling]
    )
    #expect(unknownReason(foreign) == .identityUnverified)

    let wrongVersion = evaluate(
        fixture,
        records: [HomebrewCaskInfoRecord(
            token: fixture.token, fullToken: fixture.fullToken, tap: "homebrew/cask",
            version: "1.0.1", installed: .string("1.0.1")
        )],
        listing: [fixture.selectedTarget]
    )
    #expect(unknownReason(wrongVersion) == .identityUnverified)

    // A symlinked token directory that canonicalizes to a sibling token never borrows proof.
    let siblingToken = fixture.caskroom.appendingPathComponent("sibling-token", isDirectory: true)
    try FileManager.default.createDirectory(at: siblingToken, withIntermediateDirectories: true)
    let linkedToken = fixture.caskroom.appendingPathComponent("linked-token")
    try? FileManager.default.createSymbolicLink(
        atPath: linkedToken.path, withDestinationPath: siblingToken.path
    )
    let missingBinding = evaluate(
        fixture,
        records: [HomebrewCaskInfoRecord(
            token: "linked-token", fullToken: "linked-token", tap: "homebrew/cask",
            version: "1.0.0", installed: .string("1.0.0")
        )],
        stagedBindings: [],
        declaredNames: ["linked-token"]
    )
    #expect(unknownReason(missingBinding) == .identityUnverified)
}

// MARK: Moved app

private func movedAppFixture(
    _ label: String,
    appName: String = "Codex.app",
    linkName: String = "Staged.app",
    linkToFile: Bool = false,
    selectionInsideBundle: Bool = true,
    metadataLink: Bool = false
) throws -> (fixture: CaskProbeFixture, selection: String, listing: [String]) {
    let fixture = try CaskProbeFixture(label)
    let bundle = fixture.root.appendingPathComponent("Applications/\(appName)", isDirectory: true)
    try FileManager.default.createDirectory(
        at: bundle.appendingPathComponent("Contents/MacOS", isDirectory: true),
        withIntermediateDirectories: true
    )
    let binary = bundle.appendingPathComponent("Contents/MacOS/codex")
    try writeProbeExecutable(binary)
    let selection = (selectionInsideBundle
        ? binary
        : fixture.root.appendingPathComponent("Applications/Other.app/Contents/MacOS/codex")
    ).resolvingSymlinksInPath().standardizedFileURL.path
    if !selectionInsideBundle {
        try writeProbeExecutable(URL(fileURLWithPath: selection))
    }
    let versionDirectory = fixture.caskroom.appendingPathComponent(
        "\(fixture.token)/\(fixture.version)", isDirectory: true
    )
    if metadataLink {
        try FileManager.default.createDirectory(
            at: versionDirectory.appendingPathComponent(".metadata", isDirectory: true),
            withIntermediateDirectories: true
        )
    }
    let linkParent = metadataLink
        ? versionDirectory.appendingPathComponent(".metadata", isDirectory: true)
        : versionDirectory
    let link = linkParent.appendingPathComponent(linkName)
    let destination = linkToFile ? binary.path : bundle.path
    try FileManager.default.createSymbolicLink(
        atPath: link.path, withDestinationPath: destination
    )
    return (fixture, selection, [link.path])
}

@Test func freshlyVerifiedMovedAppIsAnUpdateAndNeverNeedsAStagedTarget() throws {
    let moved = try movedAppFixture("moved")
    let evaluation = evaluate(
        moved.fixture,
        records: [installedRecord(moved.fixture, version: "1.1.0", outdated: true)],
        outdated: [HomebrewCaskOutdatedRecord(
            name: moved.fixture.token, currentVersion: "1.1.0",
            installedVersions: [moved.fixture.version]
        )],
        listing: moved.listing,
        selectedTarget: moved.selection
    )
    #expect(verifiedStatus(evaluation) == .updateAvailable(
        installed: Version("1.0.0"), latest: Version("1.1.0")
    ))
    guard case .verified(let comparison) = evaluation else {
        Issue.record("expected the moved app to verify")
        return
    }
    #expect(comparison.installedVersion == moved.fixture.version)
}

@Test func movedAppProofRejectsBroadUnrelatedRedirectedAndMetadataLinks() throws {
    // The link target is a plain file, not a `.app` directory.
    let fileLink = try movedAppFixture("moved-file", linkName: "Staged.app", linkToFile: true)
    #expect(unknownReason(evaluate(
        fileLink.fixture,
        records: [installedRecord(fileLink.fixture, version: "1.1.0", outdated: true)],
        outdated: [HomebrewCaskOutdatedRecord(
            name: fileLink.fixture.token, currentVersion: "1.1.0",
            installedVersions: [fileLink.fixture.version]
        )],
        listing: fileLink.listing,
        selectedTarget: fileLink.selection
    )) == .identityUnverified)

    // The listed link resolves to a directory that is not named `.app` (broad link).
    let broad = try movedAppFixture("moved-broad", appName: "Codex", linkName: "Staged.app")
    #expect(unknownReason(evaluate(
        broad.fixture,
        records: [installedRecord(broad.fixture, version: "1.1.0", outdated: true)],
        outdated: [HomebrewCaskOutdatedRecord(
            name: broad.fixture.token, currentVersion: "1.1.0",
            installedVersions: [broad.fixture.version]
        )],
        listing: broad.listing,
        selectedTarget: broad.selection
    )) == .identityUnverified)

    // The selection is inside a different bundle than the listed app link.
    let unrelated = try movedAppFixture(
        "moved-unrelated", selectionInsideBundle: false
    )
    #expect(unknownReason(evaluate(
        unrelated.fixture,
        records: [installedRecord(unrelated.fixture, version: "1.1.0", outdated: true)],
        outdated: [HomebrewCaskOutdatedRecord(
            name: unrelated.fixture.token, currentVersion: "1.1.0",
            installedVersions: [unrelated.fixture.version]
        )],
        listing: unrelated.listing,
        selectedTarget: unrelated.selection
    )) == .identityUnverified)

    // A link under `.metadata` is manager bookkeeping, never membership.
    let metadata = try movedAppFixture("moved-metadata", metadataLink: true)
    #expect(unknownReason(evaluate(
        metadata.fixture,
        records: [installedRecord(metadata.fixture, version: "1.1.0", outdated: true)],
        outdated: [HomebrewCaskOutdatedRecord(
            name: metadata.fixture.token, currentVersion: "1.1.0",
            installedVersions: [metadata.fixture.version]
        )],
        listing: metadata.listing,
        selectedTarget: metadata.selection
    )) == .identityUnverified)

    // A selected target outside the Caskroom with no listed app link at all.
    let noLink = try movedAppFixture("moved-no-link", selectionInsideBundle: false)
    #expect(unknownReason(evaluate(
        noLink.fixture,
        records: [installedRecord(noLink.fixture, version: "1.1.0", outdated: true)],
        outdated: [HomebrewCaskOutdatedRecord(
            name: noLink.fixture.token, currentVersion: "1.1.0",
            installedVersions: [noLink.fixture.version]
        )],
        listing: [noLink.fixture.selectedTarget],
        selectedTarget: noLink.selection
    )) == .identityUnverified)
}
