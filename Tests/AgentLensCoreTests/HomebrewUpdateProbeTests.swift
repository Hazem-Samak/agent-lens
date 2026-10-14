import Darwin
import Foundation
import Testing
@testable import AgentLensCore

// M6 step 3 — Homebrew identity, typed JSON parsing, bounded batch, and status resolution.
// Everything is synthetic: a scratch prefix with a fake `brew` executable on PATH, and a
// scripted command runner. No real package manager is ever invoked.

private func m6ScratchRoot(_ label: String) throws -> URL {
    let environment = ProcessInfo.processInfo.environment
    guard let basePath = [environment["AGENT_LENS_TEST_SCRATCH"], environment["TMPDIR"]]
        .compactMap({ $0 })
        .first(where: { !$0.isEmpty })
    else {
        throw NSError(domain: "AgentLensTests", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "no approved test scratch root is available"])
    }
    let base = URL(fileURLWithPath: basePath, isDirectory: true).resolvingSymlinksInPath()
    let root = base.appendingPathComponent("agentlens-m6-\(label)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root.resolvingSymlinksInPath()
}

private func writeExecutable(_ url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
}

/// Synthetic Homebrew prefix: `<prefix>/bin/brew` plus a Cellar keg and a PATH symlink for each tool.
struct BrewFixture {
    let prefix: URL
    var cellar: String { prefix.appendingPathComponent("Cellar").path }
    var binDirectory: String { prefix.appendingPathComponent("bin").path }
    var brewPath: String { prefix.appendingPathComponent("bin/brew").path }

    /// Creates `Cellar/<formula>/<keg>/bin/<formula>` and links `bin/<formula>` to it.
    func installKeg(formula: String, keg: String) throws -> String {
        let target = prefix.appendingPathComponent("Cellar/\(formula)/\(keg)/bin/\(formula)")
        try writeExecutable(target)
        let link = prefix.appendingPathComponent("bin/\(formula)")
        try FileManager.default.createDirectory(
            at: link.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: target.path)
        return target.resolvingSymlinksInPath().path
    }
}

func makeBrewFixture(_ label: String) throws -> BrewFixture {
    let root = try m6ScratchRoot(label)
    let prefix = root.appendingPathComponent("prefix", isDirectory: true)
    try writeExecutable(prefix.appendingPathComponent("bin/brew"))
    return BrewFixture(prefix: prefix)
}

func m6Environment(pathEntries: [String]) -> ShellEnvironment {
    let joined = pathEntries.joined(separator: ":")
    return ShellEnvironment(
        shellPath: "/bin/zsh",
        pathEntries: pathEntries,
        pathJoined: joined,
        raw: ["PATH": joined, "HOME": "/synthetic/home"],
        isDegraded: false
    )
}

/// Scripted runner: records every invocation and answers from a handler.
final class ScriptedRunner: UpdateCommandRunner, @unchecked Sendable {
    typealias Handler = @Sendable (String, [String]) -> CommandOutcome
    private let lock = NSLock()
    private var recorded: [(executable: String, arguments: [String], environment: [String: String])] = []
    private let handler: Handler

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func run(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval
    ) async -> CommandOutcome {
        record(executablePath, arguments, environment)
        return handler(executablePath, arguments)
    }

    private func record(_ executable: String, _ arguments: [String], _ environment: [String: String]) {
        lock.lock()
        defer { lock.unlock() }
        recorded.append((executable, arguments, environment))
    }

    var calls: [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return recorded.map(\.arguments)
    }

    var environments: [[String: String]] {
        lock.lock()
        defer { lock.unlock() }
        return recorded.map(\.environment)
    }
}

/// A complete, well-formed Homebrew v2 `info` envelope for the given formulae.
func infoJSON(_ formulae: [(name: String, stable: String, revision: Int, installed: [String])]) -> Data {
    let records = formulae.map { formula -> String in
        let installed = formula.installed
            .map { "{\"version\":\"\($0)\",\"installed_on_request\":true}" }
            .joined(separator: ",")
        return """
        {"name":"\(formula.name)","full_name":"\(formula.name)","tap":"homebrew/core",\
        "revision":\(formula.revision),"versions":{"stable":"\(formula.stable)","head":null,"bottle":true},\
        "installed":[\(installed)],"unrelated_extra_field":{"ignored":true}}
        """
    }.joined(separator: ",")
    return Data("{\"formulae\":[\(records)],\"casks\":[{\"token\":\"unrelated-cask\"}]}".utf8)
}

func outdatedJSON(_ formulae: [(name: String, current: String, installed: [String])]) -> Data {
    let records = formulae.map {
        "{\"name\":\"\($0.name)\",\"installed_versions\":[\($0.installed.map { "\"\($0)\"" }.joined(separator: ","))],\"current_version\":\"\($0.current)\",\"pinned\":false}"
    }.joined(separator: ",")
    return Data("{\"formulae\":[\(records)],\"casks\":[]}".utf8)
}

// MARK: Manager resolution (brief: ordered PATH winner; broken links and directories skipped)

@Test func homebrewManagerIsTheFirstLivePathWinner() throws {
    let fixture = try makeBrewFixture("manager-winner")
    let brokenRoot = fixture.prefix.deletingLastPathComponent().appendingPathComponent("broken", isDirectory: true)
    try FileManager.default.createDirectory(at: brokenRoot, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
        atPath: brokenRoot.appendingPathComponent("brew").path,
        withDestinationPath: brokenRoot.appendingPathComponent("missing").path
    )
    let environment = m6Environment(pathEntries: [brokenRoot.path, fixture.binDirectory])

    let manager = HomebrewManagerResolver.resolve(environment: environment, currentDirectory: "/")

    #expect(manager?.entryPath == fixture.brewPath)
    #expect(manager?.canonicalTarget == fixture.brewPath)
}

@Test func homebrewManagerSkipsBrokenLinksDirectoriesAndNonExecutablesThenResolvesASymlink() throws {
    let fixture = try makeBrewFixture("manager-invalid-entries")
    let root = fixture.prefix.deletingLastPathComponent()
    let brokenRoot = root.appendingPathComponent("broken-manager", isDirectory: true)
    let directoryRoot = root.appendingPathComponent("directory-manager", isDirectory: true)
    let nonExecutableRoot = root.appendingPathComponent("non-executable-manager", isDirectory: true)
    let symlinkRoot = root.appendingPathComponent("manager-symlink", isDirectory: true)
    for directory in [brokenRoot, directoryRoot, nonExecutableRoot, symlinkRoot] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    try FileManager.default.createSymbolicLink(
        atPath: brokenRoot.appendingPathComponent("brew").path,
        withDestinationPath: brokenRoot.appendingPathComponent("missing-brew").path
    )
    try FileManager.default.createDirectory(
        at: directoryRoot.appendingPathComponent("brew"), withIntermediateDirectories: true
    )
    let nonExecutable = nonExecutableRoot.appendingPathComponent("brew")
    try Data("not executable\n".utf8).write(to: nonExecutable)
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: nonExecutable.path)
    let linkedManager = symlinkRoot.appendingPathComponent("brew")
    try FileManager.default.createSymbolicLink(atPath: linkedManager.path, withDestinationPath: fixture.brewPath)
    let laterRoot = root.appendingPathComponent("later-manager", isDirectory: true)
    try writeExecutable(laterRoot.appendingPathComponent("brew"))

    let manager = HomebrewManagerResolver.resolve(
        environment: m6Environment(pathEntries: [
            brokenRoot.path, directoryRoot.path, nonExecutableRoot.path, symlinkRoot.path, laterRoot.path,
        ]),
        currentDirectory: root.path
    )

    #expect(manager?.entryPath == linkedManager.path)
    #expect(manager?.canonicalTarget == fixture.brewPath)
}

@Test func homebrewManagerResolvesEmptyAndRelativeRootsAgainstTheSuppliedDirectory() throws {
    let root = try m6ScratchRoot("manager-relative-roots")
    let workingDirectory = root.appendingPathComponent("working-directory", isDirectory: true)
    let relativeRoot = workingDirectory.appendingPathComponent("relative-bin", isDirectory: true)
    let emptyRootManager = workingDirectory.appendingPathComponent("brew")
    let relativeManager = relativeRoot.appendingPathComponent("brew")
    try writeExecutable(emptyRootManager)
    try writeExecutable(relativeManager)

    let bothRoots = HomebrewManagerResolver.resolve(
        environment: m6Environment(pathEntries: ["", "relative-bin"]),
        currentDirectory: workingDirectory.path
    )
    let relativeOnly = HomebrewManagerResolver.resolve(
        environment: m6Environment(pathEntries: ["relative-bin"]),
        currentDirectory: workingDirectory.path
    )

    #expect(bothRoots?.entryPath == emptyRootManager.path)
    #expect(relativeOnly?.entryPath == relativeManager.path)
}

@Test func homebrewManagerIsAbsentWhenNoLiveBrewExists() throws {
    let root = try m6ScratchRoot("manager-absent")
    let manager = HomebrewManagerResolver.resolve(
        environment: m6Environment(pathEntries: [root.path]),
        currentDirectory: "/"
    )
    #expect(manager == nil)
}

// MARK: Selected Cellar ownership (brief: path components, never a substring match)

@Test func selectedTargetMustBelongToTheManagerCellarByPathComponents() {
    let cellar = "/opt/homebrew/Cellar"
    let owned = HomebrewTargetParser.parse(
        selectedTarget: "\(cellar)/codex/0.162.1_1/bin/codex", cellar: cellar
    )
    #expect(owned == .success(SelectedKeg(
        cellar: cellar,
        formula: "codex",
        kegVersion: "0.162.1_1",
        relativeExecutable: "bin/codex",
        selectedTarget: "\(cellar)/codex/0.162.1_1/bin/codex"
    )))

    // Another prefix that merely contains "/Cellar/" must not borrow this manager's metadata.
    #expect(HomebrewTargetParser.parse(
        selectedTarget: "/other/Cellar/codex/0.162.1_1/bin/codex", cellar: cellar
    ) == .failure(.managerMismatch))
    #expect(HomebrewTargetParser.parse(
        selectedTarget: "/home/user/Cellar-backup/Cellar/codex/0.162.1/bin/codex", cellar: cellar
    ) == .failure(.managerMismatch))
    // Missing keg or executable components are unverified, not guessed.
    #expect(HomebrewTargetParser.parse(
        selectedTarget: "\(cellar)/codex", cellar: cellar
    ) == .failure(.unverified))
    #expect(HomebrewTargetParser.parse(
        selectedTarget: "\(cellar)/codex/0.162.1_1", cellar: cellar
    ) == .failure(.unverified))
}

// MARK: Typed JSON (brief: invalid envelope fails; extra fields tolerated; relevant malformed isolated)

@Test func infoParserToleratesExtraFieldsAndIgnoresCasks() throws {
    let records = try #require(HomebrewUpdateProbe.parseInfo(infoJSON([
        (name: "codex", stable: "0.162.1", revision: 1, installed: ["0.162.1_1"])
    ])))
    #expect(records.count == 1)
    #expect(records.first == HomebrewFormulaRecord(
        name: "codex", fullName: "codex", stable: "0.162.1", revision: 1, installedVersions: ["0.162.1_1"]
    ))
}

@Test func invalidEnvelopesFailClosed() {
    let invalid = [
        "not json",
        "[]",
        "{\"casks\":[]}",
        "{\"formulae\":{}}",
        "{\"formulae\":[{\"name\":\"codex\"",
        "{\"formulae\":[]",
    ]
    for text in invalid {
        #expect(HomebrewUpdateProbe.parseInfo(Data(text.utf8)) == nil, "expected rejection of \(text)")
        #expect(HomebrewUpdateProbe.parseOutdated(Data(text.utf8)) == nil, "expected rejection of \(text)")
    }
}

@Test func malformedRelevantRecordBecomesAnInvalidMarkerNotAnOmission() throws {
    let text = """
    {"formulae":[
      {"name":"codex","full_name":"codex","revision":0,"versions":{"stable":42},"installed":[]},
      {"name":"opencode","full_name":"opencode","revision":0,"versions":{"stable":"2.0.28"},"installed":[{"version":"2.0.28"}]}
    ],"casks":[]}
    """
    let parsed = try #require(HomebrewUpdateProbe.parseInfo(Data(text.utf8)))
    // The malformed codex record survives as an invalid marker so runBatch/status can make
    // exactly codex unknown; opencode stays fully comparable. Omission is proven downstream
    // by malformedInfoRecordMakesOnlyItsOwnToolUnknownThroughRunBatch, not by list length.
    #expect(parsed.map(\.name) == ["codex", "opencode"])
    #expect(parsed.map(\.isValid) == [false, true])
    #expect(parsed.last?.stable == "2.0.28")
}

private func infoWithRevision(_ revision: String) -> String {
    "{\"formulae\":[{\"name\":\"codex\",\"full_name\":\"codex\",\"revision\":\(revision),"
        + "\"versions\":{\"stable\":\"1.2.3\"},\"installed\":[{\"version\":\"1.2.3\"}]}],\"casks\":[]}"
}

@Test func nonIntegerAndOutOfRangeRevisionsAreMalformedNotCoerced() {
    // JSONSerialization bridges false/true to NSNumber(int64 0/1) and fractional or
    // out-of-range numbers through floating point; none may become a revision.
    for revision in ["false", "true", "1.5", "42.0", "-1", "99999999999999999999999"] {
        let parsed = HomebrewUpdateProbe.parseInfo(Data(infoWithRevision(revision).utf8))
        #expect(parsed?.first?.isValid == false, "expected revision \(revision) to be malformed")
    }
    let valid = HomebrewUpdateProbe.parseInfo(Data(infoWithRevision("7").utf8))
    #expect(valid?.first?.isValid == true)
    #expect(valid?.first?.revision == 7)
}

@Test func nonUTF8AndBOMTranscriptsAreRejectedBeforeDecoding() throws {
    let plain = infoJSON([(name: "codex", stable: "1.2.3", revision: 0, installed: ["1.2.3"])])
    let text = try #require(String(data: plain, encoding: .utf8))
    let utf16 = try #require(text.data(using: .utf16))
    #expect(HomebrewUpdateProbe.parseInfo(utf16) == nil)
    #expect(HomebrewUpdateProbe.parseOutdated(utf16) == nil)
    var bom = Data([0xEF, 0xBB, 0xBF])
    bom.append(plain)
    #expect(HomebrewUpdateProbe.parseInfo(bom) == nil)
    #expect(HomebrewUpdateProbe.parseInfo(Data([0x7B, 0xFF, 0x7D])) == nil)
}

// MARK: Batch shape and process bounds

@Test func batchUsesAtMostThreeQueriesWithDeduplicatedMetadataArguments() async throws {
    let fixture = try makeBrewFixture("batch-count")
    let runner = ScriptedRunner { _, arguments in
        switch arguments.first {
        case "--cellar": .success(Data("\(fixture.cellar)\n".utf8))
        case "info": .success(infoJSON([
            (name: "codex", stable: "0.162.1", revision: 1, installed: ["0.162.1_1"]),
            (name: "opencode", stable: "2.0.28", revision: 0, installed: ["2.0.28"]),
        ]))
        default: .success(outdatedJSON([]))
        }
    }

    let result = await HomebrewUpdateProbe.runBatch(
        manager: HomebrewManager(entryPath: fixture.brewPath, canonicalTarget: fixture.brewPath),
        formulas: ["codex", "opencode", "codex"],
        environment: m6Environment(pathEntries: [fixture.binDirectory]),
        runner: runner
    )

    #expect(runner.calls.count == 3)
    #expect(runner.calls == [
        ["--cellar"],
        ["info", "--json=v2", "--formula", "codex", "opencode"],
        ["outdated", "--json=v2", "--formula"],
    ])
    let batch = try #require(try? result.get())
    #expect(batch.queryCount == 3)
    #expect(batch.cellar == fixture.cellar)
}

@Test func batchWithNoEligibleFormulaRunsZeroQueries() async throws {
    let fixture = try makeBrewFixture("batch-empty")
    let runner = ScriptedRunner { _, _ in .failure(.nonzeroExit) }

    let result = await HomebrewUpdateProbe.runBatch(
        manager: HomebrewManager(entryPath: fixture.brewPath, canonicalTarget: fixture.brewPath),
        formulas: [],
        environment: m6Environment(pathEntries: [fixture.binDirectory]),
        runner: runner
    )

    #expect(runner.calls.isEmpty)
    #expect((try? result.get())?.queryCount == 0)
}

@Test func batchRejectsInvalidFormulaTokensBeforeAnyProcessStarts() async throws {
    let fixture = try makeBrewFixture("batch-token")
    let runner = ScriptedRunner { _, _ in .success(Data()) }
    for hostile in ["codex;rm -rf /", "-flag", "two words", "$(id)", ""] {
        let result = await HomebrewUpdateProbe.runBatch(
            manager: HomebrewManager(entryPath: fixture.brewPath, canonicalTarget: fixture.brewPath),
            formulas: [hostile],
            environment: m6Environment(pathEntries: [fixture.binDirectory]),
            runner: runner
        )
        #expect(result == .failure(.invalidFormulaName), "expected rejection of \(hostile)")
    }
    #expect(runner.calls.isEmpty)
}

@Test func batchProcessFailureIsNeverSuccessfulEmptyMetadata() async throws {
    let fixture = try makeBrewFixture("batch-fail")
    let failures: [CommandFailure] = [.nonzeroExit, .timedOut, .outputLimitExceeded, .spawnFailure]
    for failure in failures {
        let runner = ScriptedRunner { _, _ in .failure(failure) }
        let result = await HomebrewUpdateProbe.runBatch(
            manager: HomebrewManager(entryPath: fixture.brewPath, canonicalTarget: fixture.brewPath),
            formulas: ["codex"],
            environment: m6Environment(pathEntries: [fixture.binDirectory]),
            runner: runner
        )
        #expect(result == .failure(.commandFailed(failure)))
        // A batch-wide failure skips later queries: only the Cellar query ran.
        #expect(runner.calls == [["--cellar"]])
    }
}

@Test func batchAlwaysSetsDiagnosticEnvironmentWithoutMutatingOriginal() async throws {
    let fixture = try makeBrewFixture("batch-env")
    let original = m6Environment(pathEntries: [fixture.binDirectory])
    let runner = ScriptedRunner { _, arguments in
        switch arguments.first {
        case "--cellar": .success(Data("\(fixture.cellar)\n".utf8))
        case "info": .success(infoJSON([
            (name: "codex", stable: "1.2.3", revision: 0, installed: ["1.2.3"])
        ]))
        default: .success(outdatedJSON([]))
        }
    }

    _ = await HomebrewUpdateProbe.runBatch(
        manager: HomebrewManager(entryPath: fixture.brewPath, canonicalTarget: fixture.brewPath),
        formulas: ["codex"],
        environment: original,
        runner: runner
    )

    #expect(runner.calls.count == 3)
    #expect(runner.environments.count == 3)
    #expect(runner.environments.allSatisfy { environment in
        environment["HOMEBREW_NO_AUTO_UPDATE"] == "1"
            && environment["HOMEBREW_NO_ANALYTICS"] == "1"
            && environment["PATH"] == fixture.binDirectory
            && environment["HOME"] == "/synthetic/home"
    })
    #expect(original.raw["HOMEBREW_NO_AUTO_UPDATE"] == nil)
}

// MARK: End-to-end isolation through runBatch and status resolution

@Test func malformedInfoRecordMakesOnlyItsOwnToolUnknownThroughRunBatch() async throws {
    let fixture = try makeBrewFixture("batch-malformed-info")
    let infoText = """
    {"formulae":[
      {"name":"codex","full_name":"codex","revision":0,"versions":{"stable":42},"installed":[]},
      {"name":"opencode","full_name":"opencode","revision":0,"versions":{"stable":"2.0.28"},"installed":[{"version":"2.0.28"}]}
    ],"casks":[]}
    """
    let runner = ScriptedRunner { _, arguments in
        switch arguments.first {
        case "--cellar": .success(Data("\(fixture.cellar)\n".utf8))
        case "info": .success(Data(infoText.utf8))
        default: .success(outdatedJSON([]))
        }
    }
    let result = await HomebrewUpdateProbe.runBatch(
        manager: HomebrewManager(entryPath: fixture.brewPath, canonicalTarget: fixture.brewPath),
        formulas: ["codex", "opencode"],
        environment: m6Environment(pathEntries: [fixture.binDirectory]),
        runner: runner
    )
    let batch = try #require(try? result.get())
    let cellar = try #require(batch.cellar)
    #expect(resolve(
        selectedTarget: "\(cellar)/codex/2.0.0/bin/codex",
        localVersion: "2.0.0",
        batch: batch
    ) == .unknown(installed: Version("2.0.0"), reason: .identityUnverified))
    #expect(resolve(
        selectedTarget: "\(cellar)/opencode/2.0.28/bin/opencode",
        localVersion: "2.0.28",
        batch: batch
    ) == .upToDate(installed: Version("2.0.28"), latest: Version("2.0.28")))
}

@Test func malformedOutdatedRecordMakesOnlyItsOwnToolUnknownThroughRunBatch() async throws {
    let fixture = try makeBrewFixture("batch-malformed-outdated")
    let outdatedText = """
    {"formulae":[
      {"name":"codex","current_version":42,"installed_versions":["1.2.3"]},
      {"name":"opencode","current_version":"2.0.29","installed_versions":["2.0.28"]}
    ],"casks":[]}
    """
    let runner = ScriptedRunner { _, arguments in
        switch arguments.first {
        case "--cellar": .success(Data("\(fixture.cellar)\n".utf8))
        case "info": .success(infoJSON([
            (name: "codex", stable: "1.2.3", revision: 0, installed: ["1.2.3"]),
            (name: "opencode", stable: "2.0.29", revision: 0, installed: ["2.0.28"]),
        ]))
        default: .success(Data(outdatedText.utf8))
        }
    }
    let result = await HomebrewUpdateProbe.runBatch(
        manager: HomebrewManager(entryPath: fixture.brewPath, canonicalTarget: fixture.brewPath),
        formulas: ["codex", "opencode"],
        environment: m6Environment(pathEntries: [fixture.binDirectory]),
        runner: runner
    )
    let batch = try #require(try? result.get())
    let cellar = try #require(batch.cellar)
    // Valid info + malformed matching outdated must NOT read as upToDate.
    #expect(resolve(
        selectedTarget: "\(cellar)/codex/1.2.3/bin/codex",
        localVersion: "1.2.3",
        batch: batch
    ) == .unknown(installed: Version("1.2.3"), reason: .identityUnverified))
    #expect(resolve(
        selectedTarget: "\(cellar)/opencode/2.0.28/bin/opencode",
        localVersion: "2.0.28",
        batch: batch
    ) == .updateAvailable(installed: Version("2.0.28"), latest: Version("2.0.29")))
}

@Test func invalidEnvelopeFailsTheWholeBatchThroughRunBatch() async throws {
    let fixture = try makeBrewFixture("batch-envelope")
    let runner = ScriptedRunner { _, arguments in
        switch arguments.first {
        case "--cellar": .success(Data("\(fixture.cellar)\n".utf8))
        case "info": .success(Data("{\"formulae\":[{\"name\":\"codex\"".utf8))
        default: .success(outdatedJSON([]))
        }
    }
    let result = await HomebrewUpdateProbe.runBatch(
        manager: HomebrewManager(entryPath: fixture.brewPath, canonicalTarget: fixture.brewPath),
        formulas: ["codex"],
        environment: m6Environment(pathEntries: [fixture.binDirectory]),
        runner: runner
    )
    #expect(result == .failure(.invalidOutput))
}

@Test func utf16TranscriptFailsTheBatchAsInvalidOutput() async throws {
    let fixture = try makeBrewFixture("batch-utf16")
    let plain = try #require(String(data: infoJSON([
        (name: "codex", stable: "1.2.3", revision: 0, installed: ["1.2.3"])
    ]), encoding: .utf8))
    let transcoded = try #require(plain.data(using: .utf16))
    let runner = ScriptedRunner { _, arguments in
        arguments.first == "--cellar"
            ? .success(Data("\(fixture.cellar)\n".utf8))
            : .success(transcoded)
    }
    let result = await HomebrewUpdateProbe.runBatch(
        manager: HomebrewManager(entryPath: fixture.brewPath, canonicalTarget: fixture.brewPath),
        formulas: ["codex"],
        environment: m6Environment(pathEntries: [fixture.binDirectory]),
        runner: runner
    )
    // Undecodable transport is invalidOutput (coordinator renders probeFailed), never
    // inferred networkUnavailable or rateLimited.
    #expect(result == .failure(.invalidOutput))
}

// MARK: Status resolution (brief: identity, selected keg, revision, contradictions)

private func resolve(
    selectedTarget: String,
    localVersion: String,
    batch: HomebrewBatchResult
) -> VersionStatus {
    HomebrewStatusResolver.status(
        selectedTarget: selectedTarget,
        localVersion: localVersion,
        batch: batch
    )
}

private func batchResult(
    cellar: String,
    formulas: [HomebrewFormulaRecord] = [],
    outdated: [HomebrewOutdatedRecord] = []
) -> HomebrewBatchResult {
    HomebrewBatchResult(
        cellar: cellar,
        formulas: Dictionary(grouping: formulas, by: \.name),
        outdated: Dictionary(grouping: outdated, by: \.name),
        queryCount: 3
    )
}

private let codexCellar = "/opt/homebrew/Cellar"
private let codexKeg = "\(codexCellar)/codex/0.162.1_1/bin/codex"
private let codexFormula = HomebrewFormulaRecord(
    name: "codex", fullName: "codex", stable: "0.162.1", revision: 2, installedVersions: ["0.162.1_1"]
)

@Test func selectedCurrentKegWithOlderUnselectedKegIsStillUpdateAvailableWhenMetadataIsNewer() {
    // Selected _1, latest _2 — revision difference is an update even with equal upstream text.
    let status = resolve(
        selectedTarget: codexKeg,
        localVersion: "0.162.1",
        batch: batchResult(cellar: codexCellar, formulas: [codexFormula])
    )
    #expect(status == .updateAvailable(installed: Version("0.162.1"), latest: Version("0.162.1_2")))
}

@Test func selectedCurrentKegStaysUpToDateDespiteOlderUnselectedKegInCellar() {
    // The Cellar also holds 0.161.0 (unselected, older). The selected keg is the latest revision.
    let current = HomebrewFormulaRecord(
        name: "codex", fullName: "codex", stable: "0.162.1", revision: 1,
        installedVersions: ["0.161.0", "0.162.1_1"]
    )
    let status = resolve(
        selectedTarget: codexKeg,
        localVersion: "0.162.1",
        batch: batchResult(cellar: codexCellar, formulas: [current])
    )
    #expect(status == .upToDate(installed: Version("0.162.1"), latest: Version("0.162.1_1")))
}

@Test func selectedOlderKegStaysUpdateEvenWhenACurrentKegIsInstalled() {
    // Selected keg is older than metadata while a newer keg is installed but unselected.
    let older = "\(codexCellar)/codex/0.161.0/bin/codex"
    let formula = HomebrewFormulaRecord(
        name: "codex", fullName: "codex", stable: "0.162.1", revision: 1,
        installedVersions: ["0.161.0", "0.162.1_1"]
    )
    let status = resolve(
        selectedTarget: older,
        localVersion: "0.161.0",
        batch: batchResult(cellar: codexCellar, formulas: [formula])
    )
    #expect(status == .updateAvailable(installed: Version("0.161.0"), latest: Version("0.162.1_1")))
}

@Test func absenceFromOutdatedListIsNotEnoughForUpToDate() {
    // Outdated list is empty, but the selected keg is older than stable metadata.
    let selectedOld = "\(codexCellar)/codex/0.161.0/bin/codex"
    let formula = HomebrewFormulaRecord(
        name: "codex", fullName: "codex", stable: "0.162.1", revision: 0,
        installedVersions: ["0.161.0"]
    )
    let status = resolve(
        selectedTarget: selectedOld,
        localVersion: "0.161.0",
        batch: batchResult(cellar: codexCellar, formulas: [formula], outdated: [])
    )
    #expect(status == .updateAvailable(installed: Version("0.161.0"), latest: Version("0.162.1")))
}

@Test func contradictingOutdatedRecordMakesIdentityUnverified() {
    let outdated = HomebrewOutdatedRecord(name: "codex", currentVersion: "0.170.0", installedVersions: ["0.162.1_1"])
    let status = resolve(
        selectedTarget: codexKeg,
        localVersion: "0.162.1",
        batch: batchResult(cellar: codexCellar, formulas: [codexFormula], outdated: [outdated])
    )
    #expect(status == .unknown(installed: Version("0.162.1"), reason: .identityUnverified))
}

@Test func localVersionMustAgreeWithTheSelectedKegUpstream() {
    let status = resolve(
        selectedTarget: codexKeg,
        localVersion: "0.150.0",
        batch: batchResult(cellar: codexCellar, formulas: [codexFormula])
    )
    #expect(status == .unknown(installed: Version("0.150.0"), reason: .identityUnverified))
}

@Test func missingOrDuplicateFormulaRecordsAreUnverifiedNotGuessed() {
    let missing = resolve(
        selectedTarget: codexKeg,
        localVersion: "0.162.1",
        batch: batchResult(cellar: codexCellar, formulas: [])
    )
    #expect(missing == .unknown(installed: Version("0.162.1"), reason: .identityUnverified))

    let duplicated = resolve(
        selectedTarget: codexKeg,
        localVersion: "0.162.1",
        batch: batchResult(cellar: codexCellar, formulas: [codexFormula, codexFormula])
    )
    #expect(duplicated == .unknown(installed: Version("0.162.1"), reason: .identityUnverified))
}

@Test func foreignManagerCellarIsReportedAsManagerMismatch() {
    let status = resolve(
        selectedTarget: "/other/Cellar/codex/0.162.1_1/bin/codex",
        localVersion: "0.162.1",
        batch: batchResult(cellar: codexCellar, formulas: [codexFormula])
    )
    #expect(status == .unknown(installed: Version("0.162.1"), reason: .managerMismatch))
}

@Test func unsupportedLocalVersionIsUnknownAndKeepsItsText() {
    let status = resolve(
        selectedTarget: codexKeg,
        localVersion: "2024-01-01",
        batch: batchResult(cellar: codexCellar, formulas: [codexFormula])
    )
    #expect(status == .unknown(installed: Version("2024-01-01"), reason: .unsupportedVersion))
}

@Test func selectedPackageNewerThanMetadataIsUnknownNotDowngrade() {
    let newer = "\(codexCellar)/codex/0.163.0/bin/codex"
    let formula = HomebrewFormulaRecord(
        name: "codex", fullName: "codex", stable: "0.162.1", revision: 0,
        installedVersions: ["0.163.0"]
    )
    let status = resolve(
        selectedTarget: newer,
        localVersion: "0.163.0",
        batch: batchResult(cellar: codexCellar, formulas: [formula])
    )
    #expect(status == .unknown(installed: Version("0.163.0"), reason: .newerThanKnownMetadata))
}

// MARK: Stage-2 corrections — formula identity, selected-keg controls, version agreement

private let tappedCodex = HomebrewFormulaRecord(
    name: "codex", fullName: "vendor/tap/codex", stable: "1.2.3", revision: 0,
    installedVersions: ["1.2.3"]
)
private let tappedKeg = "\(codexCellar)/codex/1.2.3/bin/codex"

@Test func legitimateTappedFormulaAssociatesAnAgreeingOutdatedRecordByFullName() {
    let tapped = HomebrewFormulaRecord(
        name: "codex", fullName: "vendor/tap/codex", stable: "1.2.4", revision: 0,
        installedVersions: ["1.2.3"]
    )
    let outdated = HomebrewOutdatedRecord(
        name: "vendor/tap/codex", currentVersion: "1.2.4", installedVersions: ["1.2.3"]
    )
    #expect(resolve(
        selectedTarget: tappedKeg,
        localVersion: "1.2.3",
        batch: batchResult(cellar: codexCellar, formulas: [tapped], outdated: [outdated])
    ) == .updateAvailable(installed: Version("1.2.3"), latest: Version("1.2.4")))
}

@Test func tappedFormulaOutdatedContradictionIsFoundByFullNameNotIgnored() {
    // Basename association would miss this record (it is keyed by full name) and would report
    // updateAvailable from metadata alone. Full-name association finds it, and its disagreement
    // with stable metadata fails closed.
    let tapped = HomebrewFormulaRecord(
        name: "codex", fullName: "vendor/tap/codex", stable: "1.2.4", revision: 0,
        installedVersions: ["1.2.3"]
    )
    let outdated = HomebrewOutdatedRecord(
        name: "vendor/tap/codex", currentVersion: "1.2.3", installedVersions: ["1.2.3"]
    )
    #expect(resolve(
        selectedTarget: tappedKeg,
        localVersion: "1.2.3",
        batch: batchResult(cellar: codexCellar, formulas: [tapped], outdated: [outdated])
    ) == .unknown(installed: Version("1.2.3"), reason: .identityUnverified))
}

@Test func contradictoryOutdatedForTappedFormulaIsUnverifiedNotUpToDate() {
    let outdated = HomebrewOutdatedRecord(
        name: "vendor/tap/codex", currentVersion: "9.0.0", installedVersions: ["1.2.3"]
    )
    #expect(resolve(
        selectedTarget: tappedKeg,
        localVersion: "1.2.3",
        batch: batchResult(cellar: codexCellar, formulas: [tappedCodex], outdated: [outdated])
    ) == .unknown(installed: Version("1.2.3"), reason: .identityUnverified))
}

@Test func bareNameOutdatedAliasForTappedFormulaIsUnverified() {
    let outdated = HomebrewOutdatedRecord(
        name: "codex", currentVersion: "9.0.0", installedVersions: ["1.2.3"]
    )
    #expect(resolve(
        selectedTarget: tappedKeg,
        localVersion: "1.2.3",
        batch: batchResult(cellar: codexCellar, formulas: [tappedCodex], outdated: [outdated])
    ) == .unknown(installed: Version("1.2.3"), reason: .identityUnverified))
}

@Test func contradictoryFullNameInInfoIsAnInvalidRecordNotOwnershipByBasename() {
    let text = "{\"formulae\":[{\"name\":\"codex\",\"full_name\":\"wrong/tap/not-codex\",\"revision\":0,"
        + "\"versions\":{\"stable\":\"1.2.3\"},\"installed\":[{\"version\":\"1.2.3\"}]}],\"casks\":[]}"
    let parsed = HomebrewUpdateProbe.parseInfo(Data(text.utf8))
    #expect(parsed?.first?.isValid == false)
    #expect(resolve(
        selectedTarget: "\(codexCellar)/codex/1.2.3/bin/codex",
        localVersion: "1.2.3",
        batch: batchResult(
            cellar: codexCellar,
            formulas: [HomebrewFormulaRecord(name: "codex", isValid: false)]
        )
    ) == .unknown(installed: Version("1.2.3"), reason: .identityUnverified))
}

@Test func duplicateFullIdentitiesAreAmbiguousNotGuessed() {
    let alias = HomebrewFormulaRecord(
        name: "codex-alt", fullName: "vendor/tap/codex", stable: "1.2.3", revision: 0,
        installedVersions: ["1.2.3"]
    )
    #expect(resolve(
        selectedTarget: tappedKeg,
        localVersion: "1.2.3",
        batch: batchResult(cellar: codexCellar, formulas: [tappedCodex, alias])
    ) == .unknown(installed: Version("1.2.3"), reason: .identityUnverified))

    #expect(resolve(
        selectedTarget: tappedKeg,
        localVersion: "1.2.3",
        batch: batchResult(cellar: codexCellar, formulas: [tappedCodex, tappedCodex])
    ) == .unknown(installed: Version("1.2.3"), reason: .identityUnverified))
}

@Test func selectedCurrentKegStaysUpToDateWhenOnlyAnUnselectedOldKegIsOutdated() {
    let formula = HomebrewFormulaRecord(
        name: "codex", fullName: "codex", stable: "1.2.3", revision: 0,
        installedVersions: ["1.1.0", "1.2.3"]
    )
    let outdated = HomebrewOutdatedRecord(
        name: "codex", currentVersion: "1.2.3", installedVersions: ["1.1.0"]
    )
    #expect(resolve(
        selectedTarget: "\(codexCellar)/codex/1.2.3/bin/codex",
        localVersion: "1.2.3",
        batch: batchResult(cellar: codexCellar, formulas: [formula], outdated: [outdated])
    ) == .upToDate(installed: Version("1.2.3"), latest: Version("1.2.3")))
}

@Test func selectedOlderKegWithActualOutdatedRecordIsUpdateAvailable() {
    let formula = HomebrewFormulaRecord(
        name: "codex", fullName: "codex", stable: "1.2.3", revision: 0,
        installedVersions: ["1.1.0", "1.2.3"]
    )
    let outdated = HomebrewOutdatedRecord(
        name: "codex", currentVersion: "1.2.3", installedVersions: ["1.1.0"]
    )
    #expect(resolve(
        selectedTarget: "\(codexCellar)/codex/1.1.0/bin/codex",
        localVersion: "1.1.0",
        batch: batchResult(cellar: codexCellar, formulas: [formula], outdated: [outdated])
    ) == .updateAvailable(installed: Version("1.1.0"), latest: Version("1.2.3")))
}

@Test func outdatedListingTheEqualSelectedKegIsAContradiction() {
    let formula = HomebrewFormulaRecord(
        name: "codex", fullName: "codex", stable: "1.2.3", revision: 0,
        installedVersions: ["1.2.3"]
    )
    let outdated = HomebrewOutdatedRecord(
        name: "codex", currentVersion: "1.2.3", installedVersions: ["1.2.3"]
    )
    #expect(resolve(
        selectedTarget: "\(codexCellar)/codex/1.2.3/bin/codex",
        localVersion: "1.2.3",
        batch: batchResult(cellar: codexCellar, formulas: [formula], outdated: [outdated])
    ) == .unknown(installed: Version("1.2.3"), reason: .identityUnverified))
}

@Test func twoComponentLocalAndKegVersionsAgreeUnderHomebrewPolicy() {
    let formula = HomebrewFormulaRecord(
        name: "codex", fullName: "codex", stable: "1.2", revision: 0, installedVersions: ["1.2"]
    )
    #expect(resolve(
        selectedTarget: "\(codexCellar)/codex/1.2/bin/codex",
        localVersion: "1.2",
        batch: batchResult(cellar: codexCellar, formulas: [formula])
    ) == .upToDate(installed: Version("1.2"), latest: Version("1.2")))
}

@Test func localTwoComponentAgreesWithThreeComponentKegUpstream() {
    let formula = HomebrewFormulaRecord(
        name: "codex", fullName: "codex", stable: "1.2.0", revision: 0, installedVersions: ["1.2.0"]
    )
    #expect(resolve(
        selectedTarget: "\(codexCellar)/codex/1.2.0/bin/codex",
        localVersion: "1.2",
        batch: batchResult(cellar: codexCellar, formulas: [formula])
    ) == .upToDate(installed: Version("1.2"), latest: Version("1.2.0")))
}

@Test func kegRevisionStaysSeparateFromTwoComponentUpstream() {
    let formula = HomebrewFormulaRecord(
        name: "codex", fullName: "codex", stable: "1.2", revision: 1, installedVersions: ["1.2"]
    )
    #expect(resolve(
        selectedTarget: "\(codexCellar)/codex/1.2/bin/codex",
        localVersion: "1.2",
        batch: batchResult(cellar: codexCellar, formulas: [formula])
    ) == .updateAvailable(installed: Version("1.2"), latest: Version("1.2_1")))
}

@Test func unsupportedUpstreamFormatsRemainUnknownWithoutLexicalGuessing() {
    let formula = HomebrewFormulaRecord(
        name: "codex", fullName: "codex", stable: "1.2.3", revision: 0, installedVersions: ["1.2.3"]
    )
    for local in ["1.2.3.4", "HEAD", "2024-01-01"] {
        #expect(resolve(
            selectedTarget: "\(codexCellar)/codex/1.2.3/bin/codex",
            localVersion: local,
            batch: batchResult(cellar: codexCellar, formulas: [formula])
        ) == .unknown(installed: Version(local), reason: .unsupportedVersion), "expected \(local) unsupported")
    }
}

// MARK: Stage-2 follow-up corrections — UTF transport, borrowed identity, inventory cross-check

/// BOM-free UTF-16/32 ASCII JSON is full of NUL bytes, and NUL is a valid UTF-8 byte, so a
/// `String(data:encoding:.utf8) != nil` gate alone lets those transcripts reach `JSONSerialization`,
/// whose encoding auto-detection then reinterprets the bytes and manufactures metadata. Every
/// endian form, with and without a BOM, must fail before decoding.
private let nonUTF8Transports: [(label: String, encoding: String.Encoding, bom: [UInt8])] = [
    ("utf16LE", .utf16LittleEndian, [0xFF, 0xFE]),
    ("utf16BE", .utf16BigEndian, [0xFE, 0xFF]),
    ("utf32LE", .utf32LittleEndian, [0xFF, 0xFE, 0x00, 0x00]),
    ("utf32BE", .utf32BigEndian, [0x00, 0x00, 0xFE, 0xFF]),
]

@Test func everyNonUTF8EndianFormIsRejectedWithAndWithoutABOM() throws {
    // `infoJSON` carries unrelated extra fields and a cask array, so this doubles as the positive
    // control: valid UTF-8 with tolerated extras must still parse.
    let plain = infoJSON([(name: "codex", stable: "1.2.3", revision: 0, installed: ["1.2.3"])])
    let text = try #require(String(data: plain, encoding: .utf8))
    #expect(HomebrewUpdateProbe.parseInfo(plain)?.first?.isValid == true)
    #expect(HomebrewUpdateProbe.parseOutdated(outdatedJSON([
        (name: "codex", current: "1.2.4", installed: ["1.2.3"])
    ]))?.first?.isValid == true)

    for transport in nonUTF8Transports {
        let body = try #require(text.data(using: transport.encoding))
        #expect(HomebrewUpdateProbe.parseInfo(body) == nil, "\(transport.label) without BOM accepted by parseInfo")
        #expect(HomebrewUpdateProbe.parseOutdated(body) == nil, "\(transport.label) without BOM accepted by parseOutdated")

        var withBOM = Data(transport.bom)
        withBOM.append(body)
        #expect(HomebrewUpdateProbe.parseInfo(withBOM) == nil, "\(transport.label) with BOM accepted by parseInfo")
        #expect(HomebrewUpdateProbe.parseOutdated(withBOM) == nil, "\(transport.label) with BOM accepted by parseOutdated")
    }

    // The native .utf16/.utf32 spellings emit a BOM plus NUL padding; both must fail.
    for (label, encoding) in [("utf16", String.Encoding.utf16), ("utf32", String.Encoding.utf32)] {
        let body = try #require(text.data(using: encoding))
        #expect(HomebrewUpdateProbe.parseInfo(body) == nil, "\(label) accepted by parseInfo")
        #expect(HomebrewUpdateProbe.parseOutdated(body) == nil, "\(label) accepted by parseOutdated")
    }
}

@Test func invalidUTF8SequencesAndEmbeddedNULAreRejectedWhileValidUTF8Passes() {
    // Truncated, overlong and continuation-only sequences are not UTF-8.
    let badBytes: [[UInt8]] = [
        [0x7B, 0xFF, 0x7D], [0x7B, 0xC0, 0x80, 0x7D], [0x7B, 0xE2, 0x82, 0x7D], [0x7B, 0x80],
    ]
    for bytes in badBytes {
        let data = Data(bytes)
        #expect(HomebrewUpdateProbe.parseInfo(data) == nil, "accepted \(bytes)")
        #expect(HomebrewUpdateProbe.parseOutdated(data) == nil, "accepted \(bytes)")
    }
    // A NUL inside otherwise-valid UTF-8 is valid UTF-8 but never valid JSON transport.
    let nulInside = Data("{\"\u{0}formulae\":[]}".utf8)
    #expect(String(data: nulInside, encoding: .utf8) != nil, "control: NUL text is decodable UTF-8")
    #expect(HomebrewUpdateProbe.parseInfo(nulInside) == nil)
    #expect(HomebrewUpdateProbe.parseOutdated(nulInside) == nil)
}

@Test func utf32LittleEndianTranscriptFailsTheBatchAsInvalidOutput() async throws {
    let fixture = try makeBrewFixture("batch-utf32le")
    let plain = try #require(String(data: infoJSON([
        (name: "codex", stable: "1.2.3", revision: 0, installed: ["1.2.3"])
    ]), encoding: .utf8))
    let transcoded = try #require(plain.data(using: .utf32LittleEndian))
    let runner = ScriptedRunner { _, arguments in
        arguments.first == "--cellar"
            ? .success(Data("\(fixture.cellar)\n".utf8))
            : .success(transcoded)
    }
    let result = await HomebrewUpdateProbe.runBatch(
        manager: HomebrewManager(entryPath: fixture.brewPath, canonicalTarget: fixture.brewPath),
        formulas: ["codex"],
        environment: m6Environment(pathEntries: [fixture.binDirectory]),
        runner: runner
    )
    #expect(result == .failure(.invalidOutput))
}

@Test func malformedBorrowedAliasRetainsItsFullNameClaimAndPoisonsTheNeighbour() throws {
    let good = """
    {"name":"codex","full_name":"codex","revision":0,"versions":{"stable":"1.2.3"},"installed":[{"version":"1.2.3"}]}
    """
    // Malformed (stable is a number) but it borrows codex's full name under a different stem.
    let borrowed = """
    {"name":"other","full_name":"codex","revision":0,"versions":{"stable":42},"installed":[]}
    """
    let text = """
    {"formulae":[\(good),\(borrowed)],"casks":[]}
    """
    let parsed = try #require(HomebrewUpdateProbe.parseInfo(Data(text.utf8)))
    #expect(parsed.map(\.name) == ["codex", "other"])
    #expect(parsed.map(\.isValid) == [true, false])
    // The invalid marker must survive with its raw identity claim, not be erased into "".
    #expect(parsed.last?.fullName == "codex")
    #expect(parsed.last?.stable == "")
    #expect(parsed.last?.installedVersions == [])

    // Metadata alone would read as upToDate; the borrowed alias must make it unverified instead.
    #expect(resolve(
        selectedTarget: "\(codexCellar)/codex/1.2.3/bin/codex",
        localVersion: "1.2.3",
        batch: batchResult(cellar: codexCellar, formulas: parsed)
    ) == .unknown(installed: Version("1.2.3"), reason: .identityUnverified))
}

@Test func malformedNeighbourWithItsOwnIdentityLeavesTheValidRecordUsable() throws {
    let good = """
    {"name":"codex","full_name":"codex","revision":0,"versions":{"stable":"1.2.3"},"installed":[{"version":"1.2.3"}]}
    """
    let unrelated = """
    {"name":"other","full_name":"other","revision":0,"versions":{"stable":42},"installed":[]}
    """
    let text = """
    {"formulae":[\(good),\(unrelated)],"casks":[]}
    """
    let parsed = try #require(HomebrewUpdateProbe.parseInfo(Data(text.utf8)))
    #expect(parsed.map(\.isValid) == [true, false])
    #expect(parsed.last?.fullName == "other")
    #expect(resolve(
        selectedTarget: "\(codexCellar)/codex/1.2.3/bin/codex",
        localVersion: "1.2.3",
        batch: batchResult(cellar: codexCellar, formulas: parsed)
    ) == .upToDate(installed: Version("1.2.3"), latest: Version("1.2.3")))
}

@Test func directlyConstructedDisagreeingFullNameIsNotTrustedDespiteDefaultIsValid() {
    // `isValid` defaults to true for public construction and cache restoration, so the resolver must
    // re-derive name/full-name agreement rather than borrow the flag.
    let lying = HomebrewFormulaRecord(
        name: "codex", fullName: "wrong/tap/not-codex", stable: "1.2.3", revision: 0,
        installedVersions: ["1.2.3"]
    )
    #expect(lying.isValid)
    #expect(resolve(
        selectedTarget: "\(codexCellar)/codex/1.2.3/bin/codex",
        localVersion: "1.2.3",
        batch: batchResult(cellar: codexCellar, formulas: [lying])
    ) == .unknown(installed: Version("1.2.3"), reason: .identityUnverified))
}

@Test func borrowedAliasAndLyingFullNameAreRejectedDownstreamOfRunBatch() async throws {
    let fixture = try makeBrewFixture("batch-borrowed-alias")
    let infoText = """
    {"formulae":[
      {"name":"codex","full_name":"codex","revision":0,"versions":{"stable":"1.2.3"},"installed":[{"version":"1.2.3"}]},
      {"name":"other","full_name":"codex","revision":0,"versions":{"stable":42},"installed":[]}
    ],"casks":[]}
    """
    let runner = ScriptedRunner { _, arguments in
        switch arguments.first {
        case "--cellar": .success(Data("\(fixture.cellar)\n".utf8))
        case "info": .success(Data(infoText.utf8))
        default: .success(outdatedJSON([]))
        }
    }
    let batch = try #require(try? await HomebrewUpdateProbe.runBatch(
        manager: HomebrewManager(entryPath: fixture.brewPath, canonicalTarget: fixture.brewPath),
        formulas: ["codex", "other"],
        environment: m6Environment(pathEntries: [fixture.binDirectory]),
        runner: runner
    ).get())
    #expect(resolve(
        selectedTarget: "\(fixture.cellar)/codex/1.2.3/bin/codex",
        localVersion: "1.2.3",
        batch: batch
    ) == .unknown(installed: Version("1.2.3"), reason: .identityUnverified))
}

@Test func outdatedNamingAnUninstalledKegContradictsTheVerifiedInventory() {
    let formula = HomebrewFormulaRecord(
        name: "codex", fullName: "codex", stable: "1.2.4", revision: 0, installedVersions: ["1.2.3"]
    )
    let outdated = HomebrewOutdatedRecord(
        name: "codex", currentVersion: "1.2.4", installedVersions: ["9.9.9"]
    )
    #expect(resolve(
        selectedTarget: "\(codexCellar)/codex/1.2.3/bin/codex",
        localVersion: "1.2.3",
        batch: batchResult(cellar: codexCellar, formulas: [formula], outdated: [outdated])
    ) == .unknown(installed: Version("1.2.3"), reason: .identityUnverified))
}

@Test func outdatedNamingTheLatestPackageItselfContradictsTheInventory() {
    let formula = HomebrewFormulaRecord(
        name: "codex", fullName: "codex", stable: "1.2.4", revision: 0, installedVersions: ["1.2.3"]
    )
    let outdated = HomebrewOutdatedRecord(
        name: "codex", currentVersion: "1.2.4", installedVersions: ["1.2.4"]
    )
    #expect(resolve(
        selectedTarget: "\(codexCellar)/codex/1.2.3/bin/codex",
        localVersion: "1.2.3",
        batch: batchResult(cellar: codexCellar, formulas: [formula], outdated: [outdated])
    ) == .unknown(installed: Version("1.2.3"), reason: .identityUnverified))
}

@Test func outdatedListingOnlyRealOlderInstalledKeepsTheUpdateVerdict() {
    // The cross-check must not over-reject: every claimed keg is in the inventory and older.
    let formula = HomebrewFormulaRecord(
        name: "codex", fullName: "codex", stable: "1.2.4", revision: 0,
        installedVersions: ["1.1.0", "1.2.3"]
    )
    let outdated = HomebrewOutdatedRecord(
        name: "codex", currentVersion: "1.2.4", installedVersions: ["1.1.0", "1.2.3"]
    )
    #expect(resolve(
        selectedTarget: "\(codexCellar)/codex/1.2.3/bin/codex",
        localVersion: "1.2.3",
        batch: batchResult(cellar: codexCellar, formulas: [formula], outdated: [outdated])
    ) == .updateAvailable(installed: Version("1.2.3"), latest: Version("1.2.4")))
}

@Test func contradictoryOutdatedInventoryClaimIsRejectedDownstreamOfRunBatch() async throws {
    let fixture = try makeBrewFixture("batch-outdated-inventory")
    let runner = ScriptedRunner { _, arguments in
        switch arguments.first {
        case "--cellar": .success(Data("\(fixture.cellar)\n".utf8))
        case "info": .success(infoJSON([
            (name: "codex", stable: "1.2.4", revision: 0, installed: ["1.2.3"])
        ]))
        default: .success(outdatedJSON([
            (name: "codex", current: "1.2.4", installed: ["9.9.9"])
        ]))
        }
    }
    let batch = try #require(try? await HomebrewUpdateProbe.runBatch(
        manager: HomebrewManager(entryPath: fixture.brewPath, canonicalTarget: fixture.brewPath),
        formulas: ["codex"],
        environment: m6Environment(pathEntries: [fixture.binDirectory]),
        runner: runner
    ).get())
    #expect(resolve(
        selectedTarget: "\(fixture.cellar)/codex/1.2.3/bin/codex",
        localVersion: "1.2.3",
        batch: batch
    ) == .unknown(installed: Version("1.2.3"), reason: .identityUnverified))
}

@Test func tappedFormulaRejectsABareOutdatedAliasEvenWhenItsNumbersAgree() {
    let tapped = HomebrewFormulaRecord(
        name: "codex", fullName: "vendor/tap/codex", stable: "1.2.4", revision: 0,
        installedVersions: ["1.2.3"]
    )
    // A bare-name key belongs to a different tap's formula; agreeing numbers do not verify it.
    let bareAlias = HomebrewOutdatedRecord(
        name: "codex", currentVersion: "1.2.4", installedVersions: ["1.2.3"]
    )
    #expect(resolve(
        selectedTarget: tappedKeg,
        localVersion: "1.2.3",
        batch: batchResult(cellar: codexCellar, formulas: [tapped], outdated: [bareAlias])
    ) == .unknown(installed: Version("1.2.3"), reason: .identityUnverified))

    // The identical claim under the verified full name compares normally.
    let verified = HomebrewOutdatedRecord(
        name: "vendor/tap/codex", currentVersion: "1.2.4", installedVersions: ["1.2.3"]
    )
    #expect(resolve(
        selectedTarget: tappedKeg,
        localVersion: "1.2.3",
        batch: batchResult(cellar: codexCellar, formulas: [tapped], outdated: [verified])
    ) == .updateAvailable(installed: Version("1.2.3"), latest: Version("1.2.4")))
}

@Test func tappedFormulaWithBothFullAndBareOutdatedRecordsIsAmbiguous() {
    let tapped = HomebrewFormulaRecord(
        name: "codex", fullName: "vendor/tap/codex", stable: "1.2.4", revision: 0,
        installedVersions: ["1.2.3"]
    )
    let verified = HomebrewOutdatedRecord(
        name: "vendor/tap/codex", currentVersion: "1.2.4", installedVersions: ["1.2.3"]
    )
    let bareAlias = HomebrewOutdatedRecord(
        name: "codex", currentVersion: "1.2.4", installedVersions: ["1.2.3"]
    )
    #expect(resolve(
        selectedTarget: tappedKeg,
        localVersion: "1.2.3",
        batch: batchResult(cellar: codexCellar, formulas: [tapped], outdated: [verified, bareAlias])
    ) == .unknown(installed: Version("1.2.3"), reason: .identityUnverified))
}

@Test func unverifiedBareOutdatedAliasForTappedFormulaIsRejectedDownstreamOfRunBatch() async throws {
    let fixture = try makeBrewFixture("batch-tapped-bare-alias")
    let infoText = """
    {"formulae":[{"name":"codex","full_name":"vendor/tap/codex","revision":0,\
    "versions":{"stable":"1.2.4"},"installed":[{"version":"1.2.3"}]}],"casks":[]}
    """
    let runner = ScriptedRunner { _, arguments in
        switch arguments.first {
        case "--cellar": .success(Data("\(fixture.cellar)\n".utf8))
        case "info": .success(Data(infoText.utf8))
        default: .success(outdatedJSON([
            (name: "codex", current: "1.2.4", installed: ["1.2.3"])
        ]))
        }
    }
    let batch = try #require(try? await HomebrewUpdateProbe.runBatch(
        manager: HomebrewManager(entryPath: fixture.brewPath, canonicalTarget: fixture.brewPath),
        formulas: ["codex"],
        environment: m6Environment(pathEntries: [fixture.binDirectory]),
        runner: runner
    ).get())
    #expect(resolve(
        selectedTarget: "\(fixture.cellar)/codex/1.2.3/bin/codex",
        localVersion: "1.2.3",
        batch: batch
    ) == .unknown(installed: Version("1.2.3"), reason: .identityUnverified))
}

@Test func unsupportedStableFormatsRemainUnsupportedThroughRunBatch() async throws {
    let fixture = try makeBrewFixture("stable-suffix-revision")
    let environment = m6Environment(pathEntries: [fixture.binDirectory])
    for stable in ["HEAD", "1.x", "1.2.3_99"] {
        for revision in [0, 4] {
            let runner = ScriptedRunner { _, arguments in
                switch arguments.first {
                case "--cellar": .success(Data("\(fixture.cellar)\n".utf8))
                case "info": .success(infoJSON([
                    (name: "codex", stable: stable, revision: revision, installed: ["1.2.3"])
                ]))
                default: .success(outdatedJSON([]))
                }
            }
            let batch = try #require(try? await HomebrewUpdateProbe.runBatch(
                manager: HomebrewManager(entryPath: fixture.brewPath, canonicalTarget: fixture.brewPath),
                formulas: ["codex"], environment: environment, runner: runner
            ).get())
            let record = try #require(batch.formulas["codex"]?.first)
            #expect(record.isValid)
            #expect(record.stable == stable)
            #expect(record.revision == revision)
            #expect(record.installedVersions == ["1.2.3"])
            #expect(resolve(
                selectedTarget: "\(fixture.cellar)/codex/1.2.3/bin/codex",
                localVersion: "1.2.3",
                batch: batch
            ) == .unknown(installed: Version("1.2.3"), reason: .unsupportedVersion))
        }
    }
}

@Test func validStableWithSeparateManagerRevisionRemainsSupportedThroughRunBatch() async throws {
    let fixture = try makeBrewFixture("genuine-revision")
    let environment = m6Environment(pathEntries: [fixture.binDirectory])
    let genuineRevisionRunner = ScriptedRunner { _, arguments in
        switch arguments.first {
        case "--cellar": .success(Data("\(fixture.cellar)\n".utf8))
        case "info": .success(infoJSON([
            (name: "codex", stable: "1.2.3", revision: 99, installed: ["1.2.3"])
        ]))
        default: .success(outdatedJSON([]))
        }
    }
    let genuineRevisionBatch = try #require(try? await HomebrewUpdateProbe.runBatch(
        manager: HomebrewManager(entryPath: fixture.brewPath, canonicalTarget: fixture.brewPath),
        formulas: ["codex"], environment: environment, runner: genuineRevisionRunner
    ).get())
    #expect(resolve(
        selectedTarget: "\(fixture.cellar)/codex/1.2.3/bin/codex",
        localVersion: "1.2.3",
        batch: genuineRevisionBatch
    ) == .updateAvailable(installed: Version("1.2.3"), latest: Version("1.2.3_99")))
}

@Test func unsupportedStableValidatesMatchingOutdatedRecordsFirst() async throws {
    let fixture = try makeBrewFixture("unsupported-stable-outdated-priority")
    let malformedOutdated = Data("""
    {"formulae":[{"name":"codex","current_version":42,"installed_versions":["1.2.3"]}],"casks":[]}
    """.utf8)
    let duplicateOutdated = Data("""
    {"formulae":[
      {"name":"codex","current_version":"1.2.4","installed_versions":["1.2.3"]},
      {"name":"codex","current_version":"1.2.5","installed_versions":["1.2.3"]}
    ],"casks":[]}
    """.utf8)
    let cases: [(label: String, outdated: Data, reason: UnknownReason)] = [
        ("malformed matching outdated record", malformedOutdated, .identityUnverified),
        ("duplicate matching outdated records", duplicateOutdated, .identityUnverified),
        ("valid matching outdated record", outdatedJSON([
            (name: "codex", current: "1.2.4", installed: ["1.2.3"]),
        ]), .unsupportedVersion),
    ]

    for testCase in cases {
        let runner = ScriptedRunner { _, arguments in
            switch arguments.first {
            case "--cellar": .success(Data("\(fixture.cellar)\n".utf8))
            case "info": .success(infoJSON([
                (name: "codex", stable: "HEAD", revision: 0, installed: ["1.2.3"]),
            ]))
            default: .success(testCase.outdated)
            }
        }
        let batch = try #require(try? await HomebrewUpdateProbe.runBatch(
            manager: HomebrewManager(entryPath: fixture.brewPath, canonicalTarget: fixture.brewPath),
            formulas: ["codex"],
            environment: m6Environment(pathEntries: [fixture.binDirectory]),
            runner: runner
        ).get())
        #expect(resolve(
            selectedTarget: "\(fixture.cellar)/codex/1.2.3/bin/codex",
            localVersion: "1.2.3",
            batch: batch
        ) == .unknown(installed: Version("1.2.3"), reason: testCase.reason), "case: \(testCase.label)")
    }
}

@Test func unsupportedStableDoesNotOverrideIdentityOrSelectedKegFailures() async throws {
    let fixture = try makeBrewFixture("unsupported-stable-identity-priority")
    let malformedIdentity = Data("""
    {"formulae":[{"name":"codex","full_name":"wrong/tap/not-codex","revision":0,
    "versions":{"stable":"HEAD"},"installed":[{"version":"1.2.3"}]}],"casks":[]}
    """.utf8)
    let borrowedIdentity = Data("""
    {"formulae":[
      {"name":"codex","full_name":"codex","revision":0,"versions":{"stable":"HEAD"},"installed":[{"version":"1.2.3"}]},
      {"name":"other","full_name":"codex","revision":0,"versions":{"stable":"1.2.3"},"installed":[{"version":"1.2.3"}]}
    ],"casks":[]}
    """.utf8)
    let cases: [(label: String, data: Data, formulas: [String])] = [
        ("malformed formula identity", malformedIdentity, ["codex"]),
        ("duplicate formula records", infoJSON([
            (name: "codex", stable: "HEAD", revision: 0, installed: ["1.2.3"]),
            (name: "codex", stable: "1.x", revision: 0, installed: ["1.2.3"]),
        ]), ["codex"]),
        ("selected keg missing from inventory", infoJSON([
            (name: "codex", stable: "HEAD", revision: 0, installed: ["0.9.0"]),
        ]), ["codex"]),
        ("unsupported record has a borrowed identity", borrowedIdentity, ["codex", "other"]),
    ]

    for testCase in cases {
        let runner = ScriptedRunner { _, arguments in
            switch arguments.first {
            case "--cellar": .success(Data("\(fixture.cellar)\n".utf8))
            case "info": .success(testCase.data)
            default: .success(outdatedJSON([]))
            }
        }
        let batch = try #require(try? await HomebrewUpdateProbe.runBatch(
            manager: HomebrewManager(entryPath: fixture.brewPath, canonicalTarget: fixture.brewPath),
            formulas: testCase.formulas,
            environment: m6Environment(pathEntries: [fixture.binDirectory]),
            runner: runner
        ).get())
        #expect(resolve(
            selectedTarget: "\(fixture.cellar)/codex/1.2.3/bin/codex",
            localVersion: "1.2.3",
            batch: batch
        ) == .unknown(installed: Version("1.2.3"), reason: .identityUnverified), "case: \(testCase.label)")
    }
}

@Test func directlyConstructedStableSuffixIsUnsupportedDespiteDefaultValidity() {
    let forged = HomebrewFormulaRecord(
        name: "codex", fullName: "codex", stable: "1.2.3_99", revision: 0,
        installedVersions: ["1.2.3"]
    )
    #expect(forged.isValid)
    #expect(resolve(
        selectedTarget: "\(codexCellar)/codex/1.2.3/bin/codex",
        localVersion: "1.2.3",
        batch: batchResult(cellar: codexCellar, formulas: [forged])
    ) == .unknown(installed: Version("1.2.3"), reason: .unsupportedVersion))
}
