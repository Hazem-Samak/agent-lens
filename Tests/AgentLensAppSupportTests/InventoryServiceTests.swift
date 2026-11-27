// InventoryServiceTests — M7 stage 2: the typed app boundary over the accepted M0–M6 engine.
//
// Every fixture is immutable and synthetic: a JSON registry, a login-shell environment with a
// closed PATH, an injected scanner, a scripted manager runner, a fixed clock, and a test-owned
// cache URL in scratch. No test resolves the real login shell, reads the real PATH, launches a
// package manager, or touches the real Agent Lens cache.
//
// This file also holds the scratch/filesystem helpers shared with SessionEnvironmentProviderTests
// (same test target).

@testable import AgentLensCore
import Foundation
import Testing
@testable import AgentLensAppSupport

// MARK: Shared scratch helpers

/// An approved, invocation-local scratch root beneath `TMPDIR` (or `AGENT_LENS_TEST_SCRATCH`).
func appSupportScratchRoot(_ label: String) throws -> URL {
    let environment = ProcessInfo.processInfo.environment
    guard let basePath = [environment["AGENT_LENS_TEST_SCRATCH"], environment["TMPDIR"]]
        .compactMap({ $0 })
        .first(where: { !$0.isEmpty })
    else {
        throw NSError(
            domain: "AgentLensAppSupportTests", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "no approved test scratch root is available"]
        )
    }
    let base = URL(fileURLWithPath: basePath, isDirectory: true).resolvingSymlinksInPath()
    let root = base.appendingPathComponent("agentlens-m7-\(label)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root.resolvingSymlinksInPath()
}

@discardableResult
func writeFixtureExecutable(_ url: URL) throws -> String {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url.path
}

/// The repository root, derived from this file: `Tests/AgentLensAppSupportTests/<file>`.
var appSupportRepositoryRoot: URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .standardizedFileURL
}

// MARK: Registry fixtures

/// One synthetic detector row. IDs are unique; display names and executable names are deliberately
/// duplicated in the identity tests.
struct RegistryRow {
    let id: String
    let displayName: String
    let executableName: String
    var extraSearchRoots: [String] = []
}

/// Schema-2 registry JSON for the given rows, in the given order.
func registryJSON(_ rows: [RegistryRow]) -> Data {
    let detectors = rows.map { row -> String in
        let roots = row.extraSearchRoots.isEmpty
            ? ""
            : ",\"extraSearchRoots\":[\(row.extraSearchRoots.map { "\"\($0)\"" }.joined(separator: ","))]"
        return "{\"id\":\"\(row.id)\",\"displayName\":\"\(row.displayName)\",\"executableName\":\"\(row.executableName)\"\(roots),\"category\":\"aiAgent\",\"packages\":[],\"versionQuery\":{\"arguments\":[\"--version\"],\"stream\":\"stdout\",\"line\":\"first\"}}"
    }.joined(separator: ",")
    return Data("{\"schemaVersion\":2,\"detectors\":[\(detectors)]}".utf8)
}

/// A schema-violating registry: two detectors sharing one ID.
func duplicateIDRegistryJSON() -> Data {
    registryJSON([
        RegistryRow(id: "fixture", displayName: "Fixture One", executableName: "fixture-one"),
        RegistryRow(id: "fixture", displayName: "Fixture Two", executableName: "fixture-two"),
    ])
}

// MARK: Manager fixtures

/// Synthetic Homebrew prefix: `<prefix>/bin/brew` plus one keg per formula, with the usual PATH
/// symlink. Mirrors the M6 fixture shape without reaching into the Core test target.
struct AppBrewFixture {
    let prefix: URL
    let root: URL
    var cellar: String { prefix.appendingPathComponent("Cellar").path }
    var binDirectory: String { prefix.appendingPathComponent("bin").path }
    var brewPath: String { prefix.appendingPathComponent("bin/brew").path }

    /// `Cellar/<formula>/<keg>/bin/<executable>` (the formula name by default), reporting `version`
    /// when one is given. The keg is linked from `bin/<executable>` unless the caller wants it
    /// reachable only through a declared extra search root. Returns the canonical keg target — what
    /// the PATH symlink or an extra root resolves to.
    @discardableResult
    func installKeg(
        formula: String,
        keg: String,
        executable: String? = nil,
        version: String? = nil,
        linkedFromPath: Bool = true
    ) throws -> String {
        let name = executable ?? formula
        let target = prefix.appendingPathComponent("Cellar/\(formula)/\(keg)/bin/\(name)")
        if let version {
            try writeVersionedFixture(target, version: version)
        } else {
            try writeFixtureExecutable(target)
        }
        guard linkedFromPath else { return target.resolvingSymlinksInPath().path }
        let link = prefix.appendingPathComponent("bin/\(name)")
        try FileManager.default.createDirectory(
            at: link.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: target.path)
        return target.resolvingSymlinksInPath().path
    }

    /// A test-owned cache URL that does not exist yet — never the real app cache.
    func cacheURL(_ label: String) -> URL {
        root.appendingPathComponent("cache-\(label).json")
    }
}

func makeAppBrewFixture(_ label: String) throws -> AppBrewFixture {
    let root = try appSupportScratchRoot(label)
    let prefix = root.appendingPathComponent("prefix", isDirectory: true)
    try writeFixtureExecutable(prefix.appendingPathComponent("bin/brew"))
    return AppBrewFixture(prefix: prefix, root: root)
}

/// Scripted manager seam: records every invocation with the environment it received.
final class RecordingManagerRunner: UpdateCommandRunner, @unchecked Sendable {
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

    /// Recording lives in a synchronous helper: `NSLock` may not be locked directly from an
    /// asynchronous context, and the lock must not be held across the handler call.
    private func record(_ executablePath: String, _ arguments: [String], _ environment: [String: String]) {
        lock.lock()
        recorded.append((executablePath, arguments, environment))
        lock.unlock()
    }

    var invocationCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return recorded.count
    }

    var arguments: [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return recorded.map(\.arguments)
    }

    /// The environment handed to the first invocation. Never print this value — assert booleans.
    var firstEnvironment: [String: String]? {
        lock.lock()
        defer { lock.unlock() }
        return recorded.first?.environment
    }
}

/// The three manager answers for one current Homebrew keg.
func healthyManagerHandler(
    cellar: String,
    formula: String,
    stable: String,
    revision: Int,
    keg: String
) -> @Sendable (String, [String]) -> CommandOutcome {
    { _, arguments in
        switch arguments.first {
        case "--cellar":
            return .success(Data("\(cellar)\n".utf8))
        case "info":
            return .success(infoJSON([(name: formula, stable: stable, revision: revision, installed: [keg])]))
        default:
            return .success(outdatedJSON([]))
        }
    }
}

/// A complete, well-formed Homebrew v2 `info` envelope.
func infoJSON(_ formulae: [(name: String, stable: String, revision: Int, installed: [String])]) -> Data {
    let records = formulae.map { formula -> String in
        let installed = formula.installed
            .map { "{\"version\":\"\($0)\",\"installed_on_request\":true}" }
            .joined(separator: ",")
        return """
        {"name":"\(formula.name)","full_name":"\(formula.name)","tap":"homebrew/core",\
        "revision":\(formula.revision),"versions":{"stable":"\(formula.stable)","head":null,"bottle":true},\
        "installed":[\(installed)]}
        """
    }.joined(separator: ",")
    return Data("{\"formulae\":[\(records)],\"casks\":[]}".utf8)
}

func outdatedJSON(_ formulae: [(name: String, current: String, installed: [String])]) -> Data {
    let records = formulae.map {
        "{\"name\":\"\($0.name)\",\"installed_versions\":[\($0.installed.map { "\"\($0)\"" }.joined(separator: ","))],\"current_version\":\"\($0.current)\",\"pinned\":false}"
    }.joined(separator: ",")
    return Data("{\"formulae\":[\(records)],\"casks\":[]}".utf8)
}

/// Fails loudly if any manager command is launched — the local-only/offline proof.
func forbiddenManagerHandler() -> @Sendable (String, [String]) -> CommandOutcome {
    { _, arguments in
        Issue.record("no manager command may be launched, got \(arguments)")
        return .failure(.spawnFailure)
    }
}

/// True when neither the cache file nor its directory exists — a local-only run created nothing.
func cacheArtifactsAbsent(_ url: URL) -> Bool {
    !FileManager.default.fileExists(atPath: url.path)
        && !FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path)
}

/// Every production file of the app-support target, discovered from disk so a new file is covered
/// automatically by the source-level invariants.
func appSupportSourceFiles() throws -> [URL] {
    let directory = appSupportRepositoryRoot
        .appendingPathComponent("Sources/AgentLensAppSupport", isDirectory: true)
    let contents = try FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil
    )
    return contents
        .filter { $0.pathExtension == "swift" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
}

// MARK: Service fixtures

/// A scanner seam that produces the recording closure the service consumes. Both the recording and
/// the gated test scanners conform, so `makeService(scanner:)` has one parameter type.
protocol DiagnosticScannerFactory: Sendable {
    func makeScanner() -> @Sendable (ToolDetector, ShellEnvironment, String) -> ToolPathDiagnostic
}

/// A recording scanner seam: counts calls and returns the diagnostic the real Core scanner produces
/// for the same detector/environment, so the fixtures stay immutable while the call is observable.
final class RecordingScanner: DiagnosticScannerFactory, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var seenExecutables: [String] = []

    var invocationCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    var executables: [String] {
        lock.lock()
        defer { lock.unlock() }
        return seenExecutables
    }

    func makeScanner() -> @Sendable (ToolDetector, ShellEnvironment, String) -> ToolPathDiagnostic {
        { detector, environment, currentDirectory in
            self.lock.lock()
            self.count += 1
            self.seenExecutables.append(detector.executableName)
            self.lock.unlock()
            return PathDiagnosticsScanner.scan(
                detector: detector,
                environment: environment,
                currentDirectory: currentDirectory
            )
        }
    }
}

/// A deterministic clock.
func fixedClock(_ value: Date = Date(timeIntervalSince1970: 1_800_000_000)) -> @Sendable () -> Date {
    { value }
}

/// Environment JSON without the on-disk registry: the registry loader seam takes typed data.
func definitions(from data: Data) throws -> [DetectorDefinition] {
    try DetectorRegistry.validate(data: data)
}

// MARK: Cycle A — local inventory

@Test func localSnapshotKeepsEveryRegistryEntryInRegistryOrderIncludingMissingTools() async throws {
    let root = try appSupportScratchRoot("order")
    defer { try? FileManager.default.removeItem(at: root) }
    let bin = root.appendingPathComponent("bin", isDirectory: true)
    try writeFixtureExecutable(bin.appendingPathComponent("alpha"))
    let rows = [
        RegistryRow(id: "alpha-id", displayName: "Alpha", executableName: "alpha"),
        RegistryRow(id: "beta-id", displayName: "Beta", executableName: "beta"),
        RegistryRow(id: "gamma-id", displayName: "Gamma", executableName: "gamma"),
    ]
    let service = makeService(
        registryData: registryJSON(rows),
        pathEntries: [bin.path],
        cacheURL: root.appendingPathComponent("cache.json"),
        currentDirectory: root.path
    )

    let snapshot = try await service.localSnapshot()

    #expect(snapshot.entries.map(\.registryID) == ["alpha-id", "beta-id", "gamma-id"])
    #expect(snapshot.entries.map(\.installState) == [.installedAndOnPath, .notInstalled, .notInstalled])
    // Known tools are definitions; installed tools are a distinct count (M7 brief: never depict a
    // missing tool as an installation).
    #expect(snapshot.knownToolCount == 3)
    #expect(snapshot.installedToolCount == 1)
    #expect(snapshot.updateAvailableCount == 0)
    #expect(snapshot.entries.allSatisfy { $0.update == nil })
}

@Test func localSnapshotPreservesTypedCoreFactsVerbatim() async throws {
    let root = try appSupportScratchRoot("parity")
    defer { try? FileManager.default.removeItem(at: root) }
    let bin = root.appendingPathComponent("bin", isDirectory: true)
    let alphaEntry = try writeFixtureExecutable(bin.appendingPathComponent("alpha"))
    let offPathRoot = root.appendingPathComponent("off-path", isDirectory: true)
    let betaTarget = try writeFixtureExecutable(offPathRoot.appendingPathComponent("beta"))
    let environment = ShellEnvironment(
        shellPath: "/bin/zsh",
        pathEntries: [bin.path],
        pathJoined: bin.path,
        raw: ["PATH": bin.path],
        isDegraded: false
    )
    let rows = [
        RegistryRow(id: "alpha-id", displayName: "Alpha", executableName: "alpha"),
        RegistryRow(
            id: "beta-id",
            displayName: "Beta",
            executableName: "beta",
            extraSearchRoots: [offPathRoot.path]
        ),
        RegistryRow(id: "gamma-id", displayName: "Gamma", executableName: "gamma"),
    ]
    let data = registryJSON(rows)
    let service = makeService(
        registryData: data,
        environment: environment,
        cacheURL: root.appendingPathComponent("cache.json"),
        currentDirectory: root.path
    )

    let snapshot = try await service.localSnapshot()

    // Core parity: the same immutable fixtures through the real Core scanner must agree exactly.
    let coreDefinitions = try definitions(from: data)
    #expect(snapshot.entries.count == coreDefinitions.count)
    for (entry, definition) in zip(snapshot.entries, coreDefinitions) {
        #expect(entry.definition == definition)
        let expected = PathDiagnosticsScanner.scan(
            detector: definition.makeDetector(versionQuery: { _, _, _, _ -> String? in nil }),
            environment: environment,
            currentDirectory: root.path
        )
        #expect(entry.diagnostic == expected)
    }

    // Typed facts survive: the PATH winner, the off-PATH selection, and the missing tool.
    #expect(snapshot.entries[0].diagnostic.detectedTool.entryPath == alphaEntry)
    if case .winner(let candidate) = snapshot.entries[0].diagnostic.selection {
        #expect(candidate.entryPath == alphaEntry)
    } else {
        Issue.record("alpha must be a verified PATH winner")
    }
    if case .offPath(let candidate, let declaredRoot) = snapshot.entries[1].diagnostic.selection {
        #expect(candidate.entryPath == betaTarget)
        #expect(declaredRoot == offPathRoot.path)
    } else {
        Issue.record("beta must be a verified off-PATH selection")
    }
    #expect(snapshot.entries[1].installState == .installedNotOnPath)
    #expect(snapshot.entries[2].diagnostic.selection == .notInstalled)
    #expect(snapshot.installedToolCount == 2)
    #expect(!snapshot.isDegradedEnvironment)
}

@Test func localSnapshotUsesOnlyTheInjectedEnvironmentNotTheProcessEnvironment() async throws {
    let root = try appSupportScratchRoot("closed-path")
    defer { try? FileManager.default.removeItem(at: root) }
    // The PATH holds only this scratch directory, so the fixture tools can only be found if the
    // code under test consults the injected environment (the real PATH would find real tools).
    let bin = root.appendingPathComponent("bin", isDirectory: true)
    try writeFixtureExecutable(bin.appendingPathComponent("alpha"))
    let service = makeService(
        registryData: registryJSON([
            RegistryRow(id: "alpha-id", displayName: "Alpha", executableName: "alpha"),
            RegistryRow(id: "absent-id", displayName: "Absent", executableName: "definitely-not-installed-xyz"),
        ]),
        pathEntries: [bin.path],
        cacheURL: root.appendingPathComponent("cache.json"),
        currentDirectory: root.path
    )

    let snapshot = try await service.localSnapshot()

    #expect(snapshot.entries.map(\.installState) == [.installedAndOnPath, .notInstalled])
    #expect(snapshot.entries[1].diagnostic.detectedTool.source == "–")
}

@Test func degradedSessionEnvironmentIsReportedAsATypedWarning() async throws {
    let root = try appSupportScratchRoot("degraded")
    defer { try? FileManager.default.removeItem(at: root) }
    let empty = root.appendingPathComponent("empty-bin", isDirectory: true)
    try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
    let environment = ShellEnvironment(
        shellPath: "/bin/zsh",
        pathEntries: [empty.path],
        pathJoined: empty.path,
        raw: ["PATH": empty.path],
        isDegraded: true
    )
    let service = makeService(
        registryData: registryJSON([RegistryRow(id: "alpha-id", displayName: "Alpha", executableName: "alpha")]),
        environment: environment,
        cacheURL: root.appendingPathComponent("cache.json"),
        currentDirectory: root.path
    )

    let snapshot = try await service.localSnapshot()

    #expect(snapshot.isDegradedEnvironment)
    #expect(snapshot.entries.first?.installState == .notInstalled)
}

@Test func missingToolsAndOffPathFactsRemainTypedRatherThanBeingDropped() async throws {
    let root = try appSupportScratchRoot("typed-missing")
    defer { try? FileManager.default.removeItem(at: root) }
    let bin = root.appendingPathComponent("bin", isDirectory: true)
    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    let service = makeService(
        registryData: registryJSON([
            RegistryRow(id: "missing-id", displayName: "Missing", executableName: "missing-tool"),
        ]),
        pathEntries: [bin.path],
        cacheURL: root.appendingPathComponent("cache.json"),
        currentDirectory: root.path
    )

    let snapshot = try await service.localSnapshot()

    #expect(snapshot.entries.count == 1)
    let entry = try #require(snapshot.entries.first)
    #expect(entry.registryID == "missing-id")
    #expect(entry.definition.displayName == "Missing")
    #expect(entry.installState == .notInstalled)
    #expect(entry.diagnostic.detectedTool.version == nil)
    #expect(entry.diagnostic.pathCandidates.isEmpty)
    #expect(entry.diagnostic.shadowedInstallationCount == 0)
    #expect(entry.update == nil)
    #expect(snapshot.updateAvailableCount == 0)
}

@Test func invalidRegistryDataIsReportedAsATypedCoreError() async throws {
    let root = try appSupportScratchRoot("invalid-registry")
    defer { try? FileManager.default.removeItem(at: root) }
    let service = makeService(
        registryData: duplicateIDRegistryJSON(),
        pathEntries: [root.path],
        cacheURL: root.appendingPathComponent("cache.json"),
        currentDirectory: root.path
    )

    var thrown: (any Error)?
    do {
        _ = try await service.localSnapshot()
    } catch {
        thrown = error
    }

    #expect(thrown as? DetectorRegistryError == .duplicateId("fixture"))
}

// MARK: Cycle B — cancellation across the offload boundary

/// A scanner seam with a controlled gate: the FIRST scanner call records itself and then blocks
/// until `releaseFirstCall()`. The scan loop runs on a GCD utility queue, so blocking inside the
/// scanner is exactly the "bounded tool scan in flight" the service must not abandon.
final class GatedScanner: DiagnosticScannerFactory, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private let gate = DispatchSemaphore(value: 0)

    func makeScanner() -> @Sendable (ToolDetector, ShellEnvironment, String) -> ToolPathDiagnostic {
        { detector, environment, currentDirectory in
            self.lock.lock()
            self.count += 1
            let attempt = self.count
            self.lock.unlock()
            if attempt == 1 { self.gate.wait() }
            return PathDiagnosticsScanner.scan(
                detector: detector,
                environment: environment,
                currentDirectory: currentDirectory
            )
        }
    }

    var invocationCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    /// Test-side wait. Polls rather than blocking, so no cooperative-pool thread is parked while
    /// the utility queue worker is held inside the gate. The wait is bounded: a first call that
    /// never arrives fails the test through a typed error rather than polling forever.
    func waitForFirstCall(timeout: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while invocationCount == 0 {
            guard Date() < deadline else { throw GatedScannerTimeout.firstCallNeverObserved }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    func releaseFirstCall() { gate.signal() }
}

/// Raised when the gated scanner's first call never arrives inside the watchdog window.
enum GatedScannerTimeout: Error, Equatable {
    case firstCallNeverObserved
}

/// A gate a test opens explicitly. Continuations ignore task cancellation, so a test can suspend
/// its own body past a `cancel()` call — which is how "already cancelled before the call" is
/// constructed deterministically instead of by racing.
actor AsyncGate {
    private var open = false
    private var waiting: CheckedContinuation<Void, Never>?

    func waitForOpen() async {
        if open { return }
        await withCheckedContinuation { self.waiting = $0 }
    }

    func openGate() {
        open = true
        waiting?.resume()
        waiting = nil
    }
}

/// The outcome of one snapshot call, observed from the test without joining the task.
final class SnapshotOutcome: @unchecked Sendable {
    private let lock = NSLock()
    private var failure: (any Error)?
    private var finished = false

    var isFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return finished
    }

    var thrownError: (any Error)? {
        lock.lock()
        defer { lock.unlock() }
        return failure
    }

    func finish(_ error: (any Error)?) {
        lock.lock()
        failure = error
        finished = true
        lock.unlock()
    }
}

@Test func cancellingAScanStopsBeforeTheNextToolAndWaitsForTheInFlightScan() async throws {
    let root = try appSupportScratchRoot("cancel-gate")
    defer { try? FileManager.default.removeItem(at: root) }
    let bin = root.appendingPathComponent("bin", isDirectory: true)
    let rows = [
        RegistryRow(id: "first-id", displayName: "First", executableName: "first-tool"),
        RegistryRow(id: "second-id", displayName: "Second", executableName: "second-tool"),
        RegistryRow(id: "third-id", displayName: "Third", executableName: "third-tool"),
    ]
    let scanner = GatedScanner()
    let service = makeService(
        registryData: registryJSON(rows),
        pathEntries: [bin.path],
        cacheURL: root.appendingPathComponent("cache.json"),
        currentDirectory: root.path,
        scanner: scanner
    )
    let outcome = SnapshotOutcome()

    let task = Task {
        do {
            _ = try await service.localSnapshot()
            outcome.finish(nil)
        } catch {
            outcome.finish(error)
        }
    }
    // The gate is released in a `defer` as well as below: a failure while waiting or asserting must
    // never leave the utility-queue worker parked inside the scanner.
    defer { scanner.releaseFirstCall() }
    try await scanner.waitForFirstCall()
    task.cancel()

    // The first scan is still inside the gate: the call must stay suspended rather than return a
    // partial snapshot, and the second tool's scan must not have started.
    try? await Task.sleep(nanoseconds: 300_000_000)
    #expect(!outcome.isFinished)
    #expect(scanner.invocationCount == 1)

    // Releasing the in-flight scan immediately precedes the cancellation settling: the call then
    // throws and has scanned nothing further.
    scanner.releaseFirstCall()
    await task.value

    #expect(outcome.thrownError is CancellationError)
    #expect(scanner.invocationCount == 1)
}

@Test func anAlreadyCancelledScanRunsNoToolScanAtAll() async throws {
    let root = try appSupportScratchRoot("cancel-prior")
    defer { try? FileManager.default.removeItem(at: root) }
    let bin = root.appendingPathComponent("bin", isDirectory: true)
    let scanner = GatedScanner()
    let service = makeService(
        registryData: registryJSON([
            RegistryRow(id: "first-id", displayName: "First", executableName: "first-tool"),
            RegistryRow(id: "second-id", displayName: "Second", executableName: "second-tool"),
        ]),
        pathEntries: [bin.path],
        cacheURL: root.appendingPathComponent("cache.json"),
        currentDirectory: root.path,
        scanner: scanner
    )

    // The body is suspended at the gate, cancelled there, and only then allowed to reach the
    // snapshot call — so the call itself is already cancelled when it starts.
    let gate = AsyncGate()
    let outcome = SnapshotOutcome()
    let task = Task {
        await gate.waitForOpen()
        do {
            _ = try await service.localSnapshot()
            outcome.finish(nil)
        } catch {
            outcome.finish(error)
        }
    }
    task.cancel()
    await gate.openGate()
    await task.value

    #expect(outcome.thrownError is CancellationError)
    #expect(scanner.invocationCount == 0)
}

// MARK: Cycle C — M6 provenance across the service/snapshot boundary

/// Writes an executable that reports one version text, so the real Core scanner observes a local
/// version without any version-query seam.
@discardableResult
func writeVersionedFixture(_ url: URL, version: String) throws -> String {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try Data("#!/bin/sh\necho \(version)\n".utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url.path
}

@Test func coordinatorProvenanceSurvivesTheServiceIntoTheSnapshot() async throws {
    let fixture = try makeAppBrewFixture("provenance")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    // One current keg installed by the synthetic Homebrew prefix, reporting its own version.
    let keg = "0.162.1_1"
    let target = try writeVersionedFixture(
        fixture.prefix.appendingPathComponent("Cellar/codex/\(keg)/bin/codex"),
        version: "0.162.1"
    )
    let link = fixture.prefix.appendingPathComponent("bin/codex")
    try FileManager.default.createDirectory(
        at: link.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try? FileManager.default.removeItem(at: link)
    try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: target)

    let observedAt = Date(timeIntervalSince1970: 1_800_000_000)
    let cacheURL = fixture.cacheURL("provenance")
    let runner = RecordingManagerRunner(
        handler: healthyManagerHandler(
            cellar: fixture.cellar, formula: "codex", stable: "0.162.1", revision: 1, keg: keg
        )
    )
    let service = makeService(
        registryData: registryJSON([
            RegistryRow(id: "codex-id", displayName: "Codex", executableName: "codex"),
        ]),
        pathEntries: [fixture.binDirectory],
        cacheURL: cacheURL,
        currentDirectory: fixture.root.path,
        runner: runner,
        clock: fixedClock(observedAt)
    )

    let local = try await service.localSnapshot()
    #expect(local.entries.first?.installState == .installedAndOnPath)

    // A fresh probe: the M6 result's typed provenance and identity must reach the snapshot whole.
    let refreshed = await service.applyingUpdates(to: local, mode: .refresh)
    let freshEntry = try #require(refreshed.entries.first)
    #expect(freshEntry.updateStatus == .upToDate(installed: Version("0.162.1"), latest: Version(keg)))
    #expect(freshEntry.updateProvenance == .freshProbe(observedAt: observedAt))
    #expect(refreshed.updateAvailableCount == 0)
    let freshResult = try #require(freshEntry.update)
    #expect(freshResult.registryID == "codex-id")
    #expect(freshResult.selectedTarget == target)
    #expect(freshResult.managerEntryPath == fixture.brewPath)
    #expect(runner.invocationCount == 3)

    // A cache hit: the same typed provenance channel carries the cache's own observation time,
    // and no manager command is launched to produce it.
    let cached = await service.applyingUpdates(
        to: refreshed, mode: .checkUpdates
    )
    let cachedEntry = try #require(cached.entries.first)
    #expect(cachedEntry.updateProvenance == .cache(observedAt: observedAt))
    #expect(cachedEntry.updateStatus == .upToDate(installed: Version("0.162.1"), latest: Version(keg)))
    #expect(runner.invocationCount == 3)

    // A second explicit refresh ignores the cache and probes again: the same typed fresh provenance,
    // the same typed identity, and three further manager answers.
    let reprobed = await service.applyingUpdates(to: cached, mode: .refresh)
    let reprobedEntry = try #require(reprobed.entries.first)
    #expect(reprobedEntry.updateProvenance == .freshProbe(observedAt: observedAt))
    #expect(reprobedEntry.updateStatus == .upToDate(installed: Version("0.162.1"), latest: Version(keg)))
    #expect(reprobed.updateAvailableCount == 0)
    #expect(runner.invocationCount == 6)
}

// MARK: Cycle D — the quiet modes across the service boundary

/// `localOnly` and `offline` are the quiet modes: an eligible Homebrew tool resolves fully (brew
/// source, current keg, local version), yet neither mode launches a manager command, touches the
/// cache, nor claims an update. Core already proves the cache is never read; this proves the
/// service boundary preserves that, and that an existing cache file is left byte-identical.
@Test func quietModesLeaveEligibleToolsNeutralAndTouchNeitherManagerNorCache() async throws {
    let fixture = try makeAppBrewFixture("quiet-modes")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let keg = "0.162.1_1"
    try fixture.installKeg(formula: "codex", keg: keg, version: "0.162.1")

    let cacheURL = fixture.cacheURL("quiet-modes")
    let sentinel = Data("{\"sentinel\":true}".utf8)
    try sentinel.write(to: cacheURL)

    let runner = RecordingManagerRunner(handler: forbiddenManagerHandler())
    let service = makeService(
        registryData: registryJSON([
            RegistryRow(id: "codex-id", displayName: "Codex", executableName: "codex"),
        ]),
        pathEntries: [fixture.binDirectory],
        cacheURL: cacheURL,
        currentDirectory: fixture.root.path,
        runner: runner
    )

    let local = try await service.localSnapshot()
    #expect(local.entries.first?.installState == .installedAndOnPath)

    for (mode, reason) in [
        (UpdateProbeMode.localOnly, UnknownReason.notChecked),
        (UpdateProbeMode.offline, UnknownReason.networkUnavailable),
    ] {
        let applied = await service.applyingUpdates(to: local, mode: mode)
        let entry = try #require(applied.entries.first)
        #expect(entry.updateStatus == .unknown(installed: Version("0.162.1"), reason: reason))
        #expect(entry.updateProvenance == UpdateProvenance.none)
        #expect(applied.updateAvailableCount == 0)
        #expect(runner.invocationCount == 0)
        let afterBytes = try Data(contentsOf: cacheURL)
        #expect(afterBytes == sentinel)
    }
}

/// The same quiet-mode run against a cache URL whose directory does not exist: nothing is created,
/// so a local-only scan can never leave cache artifacts behind.
@Test func localOnlyRunAgainstAnAbsentCacheURLCreatesNoCacheArtifacts() async throws {
    let fixture = try makeAppBrewFixture("absent-cache")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try fixture.installKeg(formula: "codex", keg: "0.162.1_1", version: "0.162.1")

    let cacheURL = fixture.root.appendingPathComponent("absent/cache.json")
    let runner = RecordingManagerRunner(handler: forbiddenManagerHandler())
    let service = makeService(
        registryData: registryJSON([
            RegistryRow(id: "codex-id", displayName: "Codex", executableName: "codex"),
        ]),
        pathEntries: [fixture.binDirectory],
        cacheURL: cacheURL,
        currentDirectory: fixture.root.path,
        runner: runner
    )

    let applied = await service.applyingUpdates(to: try await service.localSnapshot(), mode: .localOnly)

    #expect(applied.entries.first?.updateStatus == .unknown(installed: Version("0.162.1"), reason: .notChecked))
    #expect(applied.updateAvailableCount == 0)
    #expect(runner.invocationCount == 0)
    #expect(cacheArtifactsAbsent(cacheURL))
}

// MARK: Service construction helper

/// Builds the service with synthetic seams. The registry loader validates typed JSON through
/// Core's own validator, so no test depends on the bundled resource.
///
/// The session environment is either supplied directly (`environment:`) or built from a closed
/// PATH (`pathEntries:`); either way it is an injected synthetic value, never a real login-shell
/// resolution.
func makeService(
    registryData: Data,
    environment: ShellEnvironment? = nil,
    pathEntries: [String] = [],
    cacheURL: URL,
    currentDirectory: String,
    scanner: (any DiagnosticScannerFactory)? = nil,
    runner: UpdateCommandRunner? = nil,
    clock: @escaping @Sendable () -> Date = fixedClock()
) -> InventoryService {
    let resolved = environment ?? ShellEnvironment(
        shellPath: "/bin/zsh",
        pathEntries: pathEntries,
        pathJoined: pathEntries.joined(separator: ":"),
        raw: ["PATH": pathEntries.joined(separator: ":")],
        isDegraded: false
    )
    // The provider caches, so one source serves every request the service makes.
    let source = RecordingEnvironmentSource(resolveEnvironment: resolved)
    let diagnostics: InventoryService.DiagnosticScanner
    if let scanner {
        diagnostics = scanner.makeScanner()
    } else {
        diagnostics = { detector, environment, directory in
            PathDiagnosticsScanner.scan(
                detector: detector,
                environment: environment,
                currentDirectory: directory
            )
        }
    }
    let manager = runner ?? RecordingManagerRunner(handler: forbiddenManagerHandler())
    return InventoryService(
        environment: source.provider,
        registry: { try DetectorRegistry.validate(data: registryData) },
        scanner: diagnostics,
        updateRunner: manager,
        updateCacheURL: cacheURL,
        currentDirectory: currentDirectory,
        clock: clock
    )
}
// MARK: M10-C operation boundary

@Test func updatePreparationRefusesAnEntryWithoutAVerifiedUpdateStatus() async throws {
    let root = try appSupportScratchRoot("m10c-prepare-neutral")
    defer { try? FileManager.default.removeItem(at: root) }
    let bin = root.appendingPathComponent("bin", isDirectory: true)
    try writeFixtureExecutable(bin.appendingPathComponent("alpha"))
    let data = registryJSON([
        RegistryRow(id: "alpha-id", displayName: "Alpha", executableName: "alpha"),
    ])
    let service = makeService(
        registryData: data,
        pathEntries: [bin.path],
        cacheURL: root.appendingPathComponent("cache.json"),
        currentDirectory: root.path
    )
    let snapshot = try await service.localSnapshot()
    let entry = try #require(snapshot.entries.first)
    let result = await service.prepareUpdate(for: entry)
    guard case .unavailable(let reason) = result else {
        Issue.record("expected neutral preparation")
        return
    }
    #expect(reason == .notUpdateAvailable)
}

// MARK: M10-C post-launch reconciliation boundary

private func m10cServiceFixtureRoot(_ label: String) throws -> URL {
    let root = try appSupportScratchRoot("m10c-\(label)")
    return root
}

private func m10cWriteExecutable(_ url: URL, contents: String = "#!/bin/sh\necho 'fixture 1.0.0'\nexit 0\n") throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try Data(contents.utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
}

private final class M10CNpmRunner: UpdateCommandRunner, @unchecked Sendable {
    let prefix: String
    let root: String
    let target: String
    private let lock = NSLock()
    private var calls: [[String]] = []
    init(prefix: String, root: String, target: String) {
        self.prefix = prefix; self.root = root; self.target = target
    }
    var invocations: [[String]] { lock.lock(); defer { lock.unlock() }; return calls }
    private func note(_ arguments: [String]) { lock.lock(); calls.append(arguments); lock.unlock() }
    func run(executablePath: String, arguments: [String],
             environment: [String: String], timeout: TimeInterval) async -> CommandOutcome {
        note(arguments)
        if arguments.contains("prefix") { return .success(Data((prefix + "\n").utf8)) }
        if arguments.contains("root") { return .success(Data((root + "\n").utf8)) }
        if arguments.contains("view") {
            return .success(Data("{\"name\":\"@openai/codex\",\"version\":\"\(target)\",\"dist-tags.latest\":\"\(target)\"}".utf8))
        }
        if arguments.contains("--version") { return .success(Data("10.9.8\n".utf8)) }
        if arguments.contains(where: { $0.hasSuffix(":registry") }) {
            return .success(Data("undefined\n".utf8))
        }
        if arguments.contains("registry") {
            return .success(Data("https://registry.npmjs.org/\n".utf8))
        }
        return .failure(.spawnFailure)
    }
}

private final class M10CSuccessfulOperationRunner: OperationCommandRunner, @unchecked Sendable {
    let prefix: String
    init(prefix: String) { self.prefix = prefix }
    func run(executablePath: String, arguments: [String], environment: [String: String],
             currentDirectory: String, timeout: TimeInterval) async -> OperationCommandResult {
        let packageRoot = URL(fileURLWithPath: prefix, isDirectory: true)
            .appendingPathComponent("lib/node_modules/@openai/codex", isDirectory: true)
        try? FileManager.default.createDirectory(at: packageRoot, withIntermediateDirectories: true)
        try? Data("{\"name\":\"@openai/codex\",\"version\":\"2.0.0\",\"bin\":{\"codex\":\"bin/codex\"}}".utf8)
            .write(to: packageRoot.appendingPathComponent("package.json"))
        try? m10cWriteExecutable(
            packageRoot.appendingPathComponent("bin/codex"),
            contents: "#!/bin/sh\necho 'codex-cli 2.0.0'\n"
        )
        return OperationCommandResult(
            stdout: Data("installed\n".utf8), stderr: Data(),
            stdoutTruncated: false, stderrTruncated: false,
            exitStatus: 0, processStarted: true,
            timedOut: false, cancelled: false, cleanupWarning: false
        )
    }
}

@Test func failedPostLaunchRescanCannotLeaveASuccessfulOutcome() async throws {
    let root = try m10cServiceFixtureRoot("rescan-uncertain")
    defer { try? FileManager.default.removeItem(at: root) }
    let prefix = root.appendingPathComponent("prefix", isDirectory: true)
    let globalRoot = prefix.appendingPathComponent("lib/node_modules", isDirectory: true)
    let managerDir = root.appendingPathComponent("manager-bin", isDirectory: true)
    let aliasDir = root.appendingPathComponent("alias-bin", isDirectory: true)
    let packageRoot = globalRoot.appendingPathComponent("@openai/codex", isDirectory: true)
    let target = packageRoot.appendingPathComponent("bin/codex")
    try m10cWriteExecutable(managerDir.appendingPathComponent("npm"))
    try m10cWriteExecutable(target, contents: "#!/bin/sh\necho 'codex-cli 1.0.0'\n")
    try Data("{\"name\":\"@openai/codex\",\"version\":\"1.0.0\",\"bin\":{\"codex\":\"bin/codex\"}}".utf8)
        .write(to: packageRoot.appendingPathComponent("package.json"))
    try FileManager.default.createDirectory(at: prefix.appendingPathComponent("bin"), withIntermediateDirectories: true)
    let prefixAlias = prefix.appendingPathComponent("bin/codex")
    try FileManager.default.createSymbolicLink(atPath: prefixAlias.path, withDestinationPath: target.path)
    try FileManager.default.createDirectory(at: aliasDir, withIntermediateDirectories: true)
    let alias = aliasDir.appendingPathComponent("codex")
    try FileManager.default.createSymbolicLink(atPath: alias.path, withDestinationPath: target.path)
    let joinedPath = [managerDir.path, aliasDir.path].joined(separator: ":")
    let environment = ShellEnvironment(
        shellPath: "/bin/zsh", pathEntries: [managerDir.path, aliasDir.path],
        pathJoined: joinedPath, raw: ["PATH": joinedPath, "HOME": "/synthetic/home"],
        isDegraded: false
    )
    let definitionData = Data("""
    {"schemaVersion":2,"detectors":[{"id":"codex-id","displayName":"Codex","executableName":"codex","category":"aiAgent","packages":[{"manager":"npm","name":"@openai/codex"}],"acceptedOperations":["npmUpdate"],"versionQuery":{"arguments":["--version"],"stream":"stdout","line":"first"}}]}
    """.utf8)
    let definitions = try DetectorRegistry.validate(data: definitionData)
    let definition = definitions[0]
    let diagnostic = PathDiagnosticsScanner.scan(
        detector: definition.makeDetector(), environment: environment, currentDirectory: root.path
    )
    let updateRunner = M10CNpmRunner(prefix: prefix.path, root: globalRoot.path, target: "2.0.0")
    let operationBase = root.appendingPathComponent("operation-base", isDirectory: true)
    try FileManager.default.createDirectory(
        at: operationBase, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
    )
    guard case .ready(let preparation) = await NpmUpdateOperation.prepare(
        definition: definition, diagnostic: diagnostic, environment: environment,
        currentDirectory: root.path, runner: updateRunner,
        operationRootBaseURL: operationBase
    ) else {
        Issue.record("expected preparation")
        return
    }
    let source = SessionEnvironmentSource(
        resolve: { environment }, loginShellPath: { "/bin/sh" },
        capture: { _ in ShellEnvironmentResolver.CaptureOutcome(dump: environment.raw, timedOut: false) },
        build: { _, _ in environment }
    )
    let service = InventoryService(
        environment: SessionEnvironmentProvider(source: source),
        registry: { throw NSError(domain: "M10CRescan", code: 1) },
        scanner: { detector, env, cwd in
            PathDiagnosticsScanner.scan(detector: detector, environment: env, currentDirectory: cwd)
        },
        updateRunner: updateRunner,
        operationRunner: M10CSuccessfulOperationRunner(prefix: prefix.path),
        operationGate: OperationExecutionGate(),
        operationRootBaseURL: operationBase,
        updateCacheURL: root.appendingPathComponent("cache.json"),
        npmScratchBaseURL: root.appendingPathComponent("scratch", isDirectory: true),
        currentDirectory: root.path,
        clock: fixedClock()
    )
    let result = await service.executeUpdate(preparation)
    #expect(result.outcome.processStarted)
    #expect(result.outcome.state == .uncertain)
    #expect(result.outcome.stdoutText == "installed\n")
    #expect(result.snapshot == nil)
}

/// M10-B B04 regression: with no injected scratch base, Check/Refresh must use Foundation's
/// `temporaryDirectory`, not the captured login-shell TMPDIR. An unsafe captured value therefore
/// cannot turn an otherwise healthy npm check into `probeFailed`.
@Test func checkUpdatesUsesFoundationScratchWhenNoBaseIsInjected() async throws {
    let root = try m10cServiceFixtureRoot("check-default-scratch")
    defer { try? FileManager.default.removeItem(at: root) }
    let prefix = root.appendingPathComponent("prefix", isDirectory: true)
    let globalRoot = prefix.appendingPathComponent("lib/node_modules", isDirectory: true)
    let managerDir = root.appendingPathComponent("manager-bin", isDirectory: true)
    let aliasDir = root.appendingPathComponent("alias-bin", isDirectory: true)
    let packageRoot = globalRoot.appendingPathComponent("@openai/codex", isDirectory: true)
    let target = packageRoot.appendingPathComponent("bin/codex")
    try m10cWriteExecutable(managerDir.appendingPathComponent("npm"))
    try m10cWriteExecutable(target, contents: "#!/bin/sh\necho 'codex-cli 1.0.0'\n")
    try Data("{\"name\":\"@openai/codex\",\"version\":\"1.0.0\",\"bin\":{\"codex\":\"bin/codex\"}}".utf8)
        .write(to: packageRoot.appendingPathComponent("package.json"))
    try FileManager.default.createDirectory(
        at: prefix.appendingPathComponent("bin"), withIntermediateDirectories: true
    )
    let prefixAlias = prefix.appendingPathComponent("bin/codex")
    try FileManager.default.createSymbolicLink(atPath: prefixAlias.path, withDestinationPath: target.path)
    try FileManager.default.createDirectory(at: aliasDir, withIntermediateDirectories: true)
    let alias = aliasDir.appendingPathComponent("codex")
    try FileManager.default.createSymbolicLink(atPath: alias.path, withDestinationPath: target.path)

    // A captured login-shell TMPDIR that NpmScratchBase must refuse if the service forwards it.
    let unsafeTMPDIR = root.appendingPathComponent("unsafe-tmp", isDirectory: true)
    try FileManager.default.createDirectory(at: unsafeTMPDIR, withIntermediateDirectories: true)
    try FileManager.default.setAttributes(
        [.posixPermissions: NSNumber(value: 0o777)], ofItemAtPath: unsafeTMPDIR.path
    )

    let joinedPath = [managerDir.path, aliasDir.path].joined(separator: ":")
    let environment = ShellEnvironment(
        shellPath: "/bin/zsh", pathEntries: [managerDir.path, aliasDir.path],
        pathJoined: joinedPath,
        raw: ["PATH": joinedPath, "HOME": "/synthetic/home", "TMPDIR": unsafeTMPDIR.path],
        isDegraded: false
    )
    let source = SessionEnvironmentSource(
        resolve: { environment }, loginShellPath: { "/bin/sh" },
        capture: { _ in ShellEnvironmentResolver.CaptureOutcome(dump: environment.raw, timedOut: false) },
        build: { _, _ in environment }
    )
    let definitionData = Data("""
    {"schemaVersion":2,"detectors":[{"id":"codex-id","displayName":"Codex","executableName":"codex","category":"aiAgent","packages":[{"manager":"npm","name":"@openai/codex"}],"acceptedOperations":["npmUpdate"],"versionQuery":{"arguments":["--version"],"stream":"stdout","line":"first"}}]}
    """.utf8)
    let service = InventoryService(
        environment: SessionEnvironmentProvider(source: source),
        registry: { try DetectorRegistry.validate(data: definitionData) },
        updateRunner: M10CNpmRunner(prefix: prefix.path, root: globalRoot.path, target: "2.0.0"),
        updateCacheURL: root.appendingPathComponent("cache.json"),
        currentDirectory: root.path,
        clock: fixedClock()
    )

    let local = try await service.localSnapshot()
    let applied = await service.applyingUpdates(to: local, mode: .checkUpdates)
    let entry = try #require(applied.entries.first)
    #expect(entry.updateStatus == .updateAvailable(
        installed: Version("1.0.0"), latest: Version("2.0.0")
    ))
}

private struct FixedDiagnosticScanner: DiagnosticScannerFactory {
    let diagnostic: ToolPathDiagnostic
    func makeScanner() -> @Sendable (ToolDetector, ShellEnvironment, String) -> ToolPathDiagnostic {
        { _, _, _ in diagnostic }
    }
}

@Test func updatePreparationRefusesWhenFreshLocalSelectionTargetChanged() async throws {
    let root = try appSupportScratchRoot("m10c-stale-prepare")
    defer { try? FileManager.default.removeItem(at: root) }
    let oldBin = root.appendingPathComponent("old-bin", isDirectory: true)
    let newBin = root.appendingPathComponent("new-bin", isDirectory: true)
    try writeFixtureExecutable(oldBin.appendingPathComponent("alpha"))
    try Data("#!/bin/sh\necho 'alpha 1.0.0'\n".utf8).write(to: oldBin.appendingPathComponent("alpha"))
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755], ofItemAtPath: oldBin.appendingPathComponent("alpha").path
    )
    try writeFixtureExecutable(newBin.appendingPathComponent("alpha"))
    try Data("#!/bin/sh\necho 'alpha 1.0.0'\n".utf8).write(to: newBin.appendingPathComponent("alpha"))
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755], ofItemAtPath: newBin.appendingPathComponent("alpha").path
    )
    let data = registryJSON([RegistryRow(id: "alpha-id", displayName: "Alpha", executableName: "alpha")])
    let definitions = try DetectorRegistry.validate(data: data)
    let definition = definitions[0]
    let oldEnvironment = ShellEnvironment(
        shellPath: "/bin/zsh", pathEntries: [oldBin.path], pathJoined: oldBin.path,
        raw: ["PATH": oldBin.path], isDegraded: false
    )
    let newEnvironment = ShellEnvironment(
        shellPath: "/bin/zsh", pathEntries: [newBin.path], pathJoined: newBin.path,
        raw: ["PATH": newBin.path], isDegraded: false
    )
    let oldDiagnostic = PathDiagnosticsScanner.scan(
        detector: definition.makeDetector(), environment: oldEnvironment,
        currentDirectory: root.path
    )
    let newDiagnostic = PathDiagnosticsScanner.scan(
        detector: definition.makeDetector(), environment: newEnvironment,
        currentDirectory: root.path
    )
    let update = ToolUpdateResult(
        registryID: "alpha-id", displayName: "Alpha", diagnosticIndex: 0,
        diagnostic: oldDiagnostic, localVersion: "1.0.0",
        selectedEntryPath: oldDiagnostic.detectedTool.entryPath,
        selectedTarget: oldDiagnostic.detectedTool.resolvedPath,
        selectedKegVersion: nil, managerEntryPath: nil, managerTarget: nil,
        managerFingerprint: nil, managerCellar: nil, formulaStem: nil,
        fullFormulaName: nil, npmPackage: "@openai/codex",
        npmRegistry: "https://registry.npmjs.org/", npmTag: "latest",
        npmVersion: "10.9.8",
        status: .updateAvailable(installed: Version("1.0.0"), latest: Version("2.0.0")),
        provenance: .freshProbe(observedAt: Date(timeIntervalSince1970: 0))
    )
    let entry = InventoryEntry(
        definition: definition, diagnostic: oldDiagnostic, update: update, ownership: nil
    )
    let service = makeService(
        registryData: data,
        environment: oldEnvironment,
        cacheURL: root.appendingPathComponent("cache.json"),
        currentDirectory: root.path,
        scanner: FixedDiagnosticScanner(diagnostic: newDiagnostic)
    )
    let result = await service.prepareUpdate(for: entry)
    guard case .unavailable(let reason) = result else {
        Issue.record("changed fresh target must refuse preparation")
        return
    }
    #expect(reason == .identityUnverified)
}

// MARK: M10-D uninstall boundary

private final class M10DUninstallOperationRunner: OperationCommandRunner, @unchecked Sendable {
    let packageRoot: String
    let prefixBin: String
    let executableName: String
    init(packageRoot: String, prefixBin: String, executableName: String) {
        self.packageRoot = packageRoot
        self.prefixBin = prefixBin
        self.executableName = executableName
    }
    func run(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        currentDirectory: String,
        timeout: TimeInterval
    ) async -> OperationCommandResult {
        try? FileManager.default.removeItem(atPath: packageRoot)
        try? FileManager.default.removeItem(
            atPath: URL(fileURLWithPath: prefixBin).appendingPathComponent(executableName).path
        )
        return OperationCommandResult(
            stdout: Data("removed\n".utf8), stderr: Data(),
            stdoutTruncated: false, stderrTruncated: false,
            exitStatus: 0, processStarted: true,
            timedOut: false, cancelled: false, cleanupWarning: false
        )
    }
}

@Test func uninstallPreparationAndExecutionPublishTheFreshRemovalDelta() async throws {
    let root = try appSupportScratchRoot("m10d-uninstall-boundary")
    defer { try? FileManager.default.removeItem(at: root) }
    let prefix = root.appendingPathComponent("prefix", isDirectory: true)
    let globalRoot = prefix.appendingPathComponent("lib/node_modules", isDirectory: true)
    let managerDir = root.appendingPathComponent("manager-bin", isDirectory: true)
    let aliasDir = root.appendingPathComponent("alias-bin", isDirectory: true)
    let packageRoot = globalRoot.appendingPathComponent("@openai/codex", isDirectory: true)
    let target = packageRoot.appendingPathComponent("bin/codex")
    try m10cWriteExecutable(managerDir.appendingPathComponent("npm"))
    try m10cWriteExecutable(target, contents: "#!/bin/sh\necho 'codex-cli 1.0.0'\n")
    try Data("{\"name\":\"@openai/codex\",\"version\":\"1.0.0\",\"bin\":{\"codex\":\"bin/codex\"}}".utf8)
        .write(to: packageRoot.appendingPathComponent("package.json"))
    let prefixBin = prefix.appendingPathComponent("bin", isDirectory: true)
    try FileManager.default.createDirectory(at: prefixBin, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
        atPath: prefixBin.appendingPathComponent("codex").path,
        withDestinationPath: target.path
    )
    try FileManager.default.createDirectory(at: aliasDir, withIntermediateDirectories: true)
    let alias = aliasDir.appendingPathComponent("codex")
    try FileManager.default.createSymbolicLink(atPath: alias.path, withDestinationPath: target.path)
    let joinedPath = [managerDir.path, aliasDir.path].joined(separator: ":")
    let environment = ShellEnvironment(
        shellPath: "/bin/zsh", pathEntries: [managerDir.path, aliasDir.path],
        pathJoined: joinedPath, raw: ["PATH": joinedPath, "HOME": "/synthetic/home"],
        isDegraded: false
    )
    let definitionData = Data("""
    {"schemaVersion":2,"detectors":[{"id":"codex-id","displayName":"Codex","executableName":"codex","category":"aiAgent","packages":[{"manager":"npm","name":"@openai/codex"}],"acceptedOperations":["npmUninstall"],"versionQuery":{"arguments":["--version"],"stream":"stdout","line":"first"}}]}
    """.utf8)
    let definition = try DetectorRegistry.validate(data: definitionData)[0]
    let diagnostic = PathDiagnosticsScanner.scan(
        detector: definition.makeDetector(), environment: environment, currentDirectory: root.path
    )
    let selection = try #require(FileIdentityObserver.observeExecutable(entryPath: alias.path))
    let manager = try #require(FileIdentityObserver.observeExecutable(entryPath: managerDir.appendingPathComponent("npm").path))
    let ownership = InstallationOwnershipResult(
        registryID: "codex-id",
        observedSelectedEntry: selection.entryPath,
        observedSelectedTarget: selection.canonicalTarget,
        observedAt: Date(timeIntervalSince1970: 0),
        outcome: .verified(VerifiedInstallation(
            manager: .npm,
            packageName: "@openai/codex",
            managerEntryPath: manager.entryPath,
            managerTarget: manager.canonicalTarget,
            managerFingerprint: manager.fingerprint,
            managerRoot: prefix.path,
            installationRoot: packageRoot.path,
            selection: InstallationSelectionIdentity(
                entryPath: selection.entryPath,
                canonicalTarget: selection.canonicalTarget,
                fingerprint: selection.fingerprint
            )
        ))
    )
    let entry = InventoryEntry(
        definition: definition, diagnostic: diagnostic, update: nil, ownership: ownership
    )
    let operationBase = root.appendingPathComponent("operation-base", isDirectory: true)
    try FileManager.default.createDirectory(
        at: operationBase, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
    )
    let source = SessionEnvironmentSource(
        resolve: { environment }, loginShellPath: { "/bin/sh" },
        capture: { _ in ShellEnvironmentResolver.CaptureOutcome(dump: environment.raw, timedOut: false) },
        build: { _, _ in environment }
    )
    let service = InventoryService(
        environment: SessionEnvironmentProvider(source: source),
        registry: { [definition] },
        scanner: { detector, env, cwd in
            PathDiagnosticsScanner.scan(detector: detector, environment: env, currentDirectory: cwd)
        },
        updateRunner: M10CNpmRunner(prefix: prefix.path, root: globalRoot.path, target: "2.0.0"),
        operationRunner: M10DUninstallOperationRunner(
            packageRoot: packageRoot.path,
            prefixBin: prefixBin.path,
            executableName: "codex"
        ),
        operationGate: OperationExecutionGate(),
        operationRootBaseURL: operationBase,
        updateCacheURL: root.appendingPathComponent("cache.json"),
        npmScratchBaseURL: root.appendingPathComponent("scratch", isDirectory: true),
        currentDirectory: root.path,
        clock: fixedClock()
    )
    let prepared = await service.prepareUninstall(for: entry)
    guard case .ready(let preparation) = prepared else {
        Issue.record("expected uninstall preparation")
        return
    }
    #expect(preparation.preview.packageName == "@openai/codex")
    let result = await service.executeUninstall(preparation)
    #expect(result.outcome.state == .succeeded)
    #expect(result.outcome.processStarted)
    #expect(result.outcome.reconciliation?.packageDirectoryAbsent == true)
    #expect(result.outcome.reconciliation?.selectedTargetReleased == true)
    #expect(result.snapshot?.entries.first?.installState == .notInstalled)
}

// MARK: - M13-G Homebrew formula operation boundary

/// Mutable manager answers shared by the read-only queries and the operation runner, so the
/// post-launch observation sees exactly the mutation the runner performed.
final class AppFormulaManagerState: @unchecked Sendable {
    private let lock = NSLock()
    private var installed: [String]
    private var listed: String
    let stable: String

    init(installed: [String], listedPath: String, stable: String) {
        self.installed = installed
        self.listed = listedPath
        self.stable = stable
    }

    var installedKegs: [String] { lock.lock(); defer { lock.unlock() }; return installed }
    var listedPath: String { lock.lock(); defer { lock.unlock() }; return listed }

    func upgrade(to keg: String, listedPath: String) {
        lock.lock()
        installed = [keg] + installed.filter { $0 != keg }
        listed = listedPath
        lock.unlock()
    }

    func removeAll() {
        lock.lock()
        installed = []
        lock.unlock()
    }
}

/// A disposable synthetic Homebrew formula installation:
/// `<prefix>/Cellar/<formula>/<keg>/bin/<formula>` linked from `<prefix>/bin`, with a synthetic
/// `brew` executable. No real manager is ever invoked.
struct AppFormulaOperationFixture: Sendable {
    let root: URL
    let prefix: URL
    let cellar: String
    let binDirectory: String
    let brewPath: String
    let formulaName: String
    let installedKeg: String
    let targetVersion: String
    let target: String
    let operationBase: URL
    let environment: ShellEnvironment
    let definition: DetectorDefinition
    let definitions: [DetectorDefinition]
    let state: AppFormulaManagerState

    init(_ label: String) throws {
        let rootValue = try appSupportScratchRoot(label)
        let prefixValue = rootValue.appendingPathComponent("prefix", isDirectory: true)
        let formula = "hermes-agent"
        let keg = "1.0.0"
        let targetURL = prefixValue
            .appendingPathComponent("Cellar/\(formula)/\(keg)/bin/\(formula)")
        try writeFixtureExecutable(prefixValue.appendingPathComponent("bin/brew"))
        try m13gWriteExecutable(targetURL, version: "1.0.0")
        let link = prefixValue.appendingPathComponent("bin/\(formula)")
        try FileManager.default.createDirectory(
            at: link.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: targetURL.path)
        let canonicalPrefix = prefixValue.resolvingSymlinksInPath()
        let canonicalTarget = targetURL.resolvingSymlinksInPath().path
        let joinedPath = canonicalPrefix.appendingPathComponent("bin").path
        let environmentValue = ShellEnvironment(
            shellPath: "/bin/zsh",
            pathEntries: [joinedPath],
            pathJoined: joinedPath,
            raw: ["PATH": joinedPath, "HOME": rootValue.appendingPathComponent("home").path],
            isDegraded: false
        )
        let data = Data("""
        {"schemaVersion":2,"detectors":[{"id":"hermes-id","displayName":"Hermes","executableName":"hermes-agent","category":"aiAgent","packages":[{"manager":"homebrewFormula","name":"hermes-agent"}],"acceptedOperations":["homebrewFormulaUpdate","homebrewFormulaUninstall"],"versionQuery":{"arguments":["--version"],"stream":"stdout","line":"first"}},{"id":"beta-id","displayName":"Beta","executableName":"beta","category":"aiHarness","packages":[],"versionQuery":{"arguments":["--version"],"stream":"stdout","line":"first"}}]}
        """.utf8)
        let operationBaseValue = rootValue.appendingPathComponent("operation-base", isDirectory: true)
        try FileManager.default.createDirectory(
            at: operationBaseValue, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        self.root = rootValue
        self.prefix = canonicalPrefix
        self.cellar = canonicalPrefix.appendingPathComponent("Cellar").path
        self.binDirectory = joinedPath
        self.brewPath = canonicalPrefix.appendingPathComponent("bin/brew").path
        self.formulaName = formula
        self.installedKeg = keg
        self.targetVersion = "2.0.0"
        self.target = canonicalTarget
        self.operationBase = operationBaseValue
        self.environment = environmentValue
        self.definitions = try DetectorRegistry.validate(data: data)
        self.definition = self.definitions[0]
        self.state = AppFormulaManagerState(
            installed: [keg], listedPath: canonicalTarget, stable: "2.0.0"
        )
    }

    var managerHandler: @Sendable (String, [String]) -> CommandOutcome {
        let cellar = cellar
        let prefix = prefix.path
        let formula = formulaName
        let target = target
        let state = state
        return { _, arguments in
            switch arguments.first {
            case "--prefix":
                return .success(Data((prefix + "\n").utf8))
            case "--cellar":
                return .success(Data((cellar + "\n").utf8))
            case "info":
                let kegs = state.installedKegs
                let installed = kegs
                    .map { "{\"version\":\"\($0)\",\"installed_on_request\":true}" }
                    .joined(separator: ",")
                let envelope = """
                {"formulae":[{"name":"\(formula)","full_name":"\(formula)","tap":"homebrew/core",\
                "revision":0,"versions":{"stable":"\(state.stable)","head":null,"bottle":true},\
                "installed":[\(installed)],"pinned":false,"deprecated":false,"disabled":false}],"casks":[]}
                """
                return .success(Data(envelope.utf8))
            case "list":
                if arguments.contains("--pinned") { return .success(Data()) }
                if arguments.contains("--verbose") {
                    let listed = state.listedPath
                    return .success(Data((listed + "\n").utf8))
                }
                return .success(Data())
            case "outdated":
                let kegs = state.installedKegs
                guard kegs != [state.stable] else {
                    return .success(Data("{\"formulae\":[],\"casks\":[]}".utf8))
                }
                let installed = kegs.map { "\"\($0)\"" }.joined(separator: ",")
                let envelope = """
                {"formulae":[{"name":"\(formula)","installed_versions":[\(installed)],\
                "current_version":"\(state.stable)","pinned":false}],"casks":[]}
                """
                return .success(Data(envelope.utf8))
            default:
                return .failure(.spawnFailure)
            }
        }
    }

    func makeService(
        operationRunner: OperationCommandRunner,
        updateRunner: UpdateCommandRunner? = nil
    ) -> InventoryService {
        let environment = self.environment
        let definitions = self.definitions
        let handler = self.managerHandler
        let manager = updateRunner ?? RecordingManagerRunner(handler: handler)
        let source = SessionEnvironmentSource(
            resolve: { environment },
            loginShellPath: { "/bin/sh" },
            capture: { _ in
                ShellEnvironmentResolver.CaptureOutcome(dump: environment.raw, timedOut: false)
            },
            build: { _, _ in environment }
        )
        return InventoryService(
            environment: SessionEnvironmentProvider(source: source),
            registry: { definitions },
            scanner: { detector, env, cwd in
                PathDiagnosticsScanner.scan(detector: detector, environment: env, currentDirectory: cwd)
            },
            updateRunner: manager,
            operationRunner: operationRunner,
            operationGate: OperationExecutionGate(),
            operationRootBaseURL: operationBase,
            updateCacheURL: root.appendingPathComponent("cache.json"),
            currentDirectory: root.path,
            clock: fixedClock()
        )
    }

    /// A published entry carrying the manager-verified update identity the presentation gate
    /// reads. The diagnostic and definition are the real scanned values; the observed selection is
    /// copied exactly as the coordinator copies it (the PATH-slot entry and its canonical target).
    func updatedEntry(_ entry: InventoryEntry) -> InventoryEntry {
        let selected = entry.diagnostic.observedSelectionPair
        return InventoryEntry(
            definition: entry.definition,
            diagnostic: entry.diagnostic,
            update: ToolUpdateResult(
                registryID: entry.registryID,
                displayName: entry.definition.displayName,
                diagnosticIndex: 0,
                diagnostic: entry.diagnostic,
                localVersion: "1.0.0",
                selectedEntryPath: selected?.entry,
                selectedTarget: selected?.target,
                selectedKegVersion: installedKeg,
                managerEntryPath: brewPath,
                managerTarget: brewPath,
                managerFingerprint: nil,
                managerCellar: cellar,
                formulaStem: formulaName,
                fullFormulaName: formulaName,
                status: .updateAvailable(installed: Version("1.0.0"), latest: Version(targetVersion)),
                provenance: .freshProbe(observedAt: Date(timeIntervalSince1970: 0))
            ),
            ownership: entry.ownership
        )
    }
}

private func m13gWriteExecutable(_ url: URL, version: String) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try Data("#!/bin/sh\necho 'hermes-agent \(version)'\nexit 0\n".utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
}

/// Performs the update mutation the real manager would: stages the new keg, relinks the selected
/// executable, and updates the manager-answer state the post-launch observation reads.
final class AppFormulaUpgradeRunner: OperationCommandRunner, @unchecked Sendable {
    let fixture: AppFormulaOperationFixture
    private let lock = NSLock()
    private var calls = 0
    var invocationCount: Int { lock.lock(); defer { lock.unlock() }; return calls }

    init(fixture: AppFormulaOperationFixture) {
        self.fixture = fixture
    }

    private func noteCall() {
        lock.lock()
        calls += 1
        lock.unlock()
    }

    func run(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        currentDirectory: String,
        timeout: TimeInterval
    ) async -> OperationCommandResult {
        noteCall()
        let newTarget = fixture.prefix
            .appendingPathComponent("Cellar/\(fixture.formulaName)/\(fixture.targetVersion)/bin/\(fixture.formulaName)")
        try? m13gWriteExecutable(newTarget, version: fixture.targetVersion)
        let link = fixture.prefix.appendingPathComponent("bin/\(fixture.formulaName)")
        try? FileManager.default.removeItem(at: link)
        try? FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: newTarget.path)
        fixture.state.upgrade(
            to: fixture.targetVersion,
            listedPath: newTarget.resolvingSymlinksInPath().path
        )
        return OperationCommandResult(
            stdout: Data("upgraded\n".utf8), stderr: Data(),
            stdoutTruncated: false, stderrTruncated: false,
            exitStatus: 0, processStarted: true,
            timedOut: false, cancelled: false, cleanupWarning: false
        )
    }
}

/// Performs the uninstall mutation the real manager would for a single linked keg.
final class AppFormulaUninstallRunner: OperationCommandRunner, @unchecked Sendable {
    let fixture: AppFormulaOperationFixture
    private let lock = NSLock()
    private var calls = 0
    var invocationCount: Int { lock.lock(); defer { lock.unlock() }; return calls }

    init(fixture: AppFormulaOperationFixture) {
        self.fixture = fixture
    }

    private func noteCall() {
        lock.lock()
        calls += 1
        lock.unlock()
    }

    func run(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        currentDirectory: String,
        timeout: TimeInterval
    ) async -> OperationCommandResult {
        noteCall()
        try? FileManager.default.removeItem(
            at: fixture.prefix.appendingPathComponent("Cellar/\(fixture.formulaName)")
        )
        try? FileManager.default.removeItem(
            at: fixture.prefix.appendingPathComponent("bin/\(fixture.formulaName)")
        )
        fixture.state.removeAll()
        return OperationCommandResult(
            stdout: Data("uninstalled\n".utf8), stderr: Data(),
            stdoutTruncated: false, stderrTruncated: false,
            exitStatus: 0, processStarted: true,
            timedOut: false, cancelled: false, cleanupWarning: false
        )
    }
}

final class AppFormulaCountingOperationRunner: OperationCommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    var invocationCount: Int { lock.lock(); defer { lock.unlock() }; return calls }

    private func noteCall() {
        lock.lock()
        calls += 1
        lock.unlock()
    }

    func run(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        currentDirectory: String,
        timeout: TimeInterval
    ) async -> OperationCommandResult {
        noteCall()
        return OperationCommandResult(
            stdout: Data(), stderr: Data(),
            stdoutTruncated: false, stderrTruncated: false,
            exitStatus: 1, processStarted: true,
            timedOut: false, cancelled: false, cleanupWarning: false
        )
    }
}

@Test func formulaUpdatePreparationAndExecutionForwardTheTypedPreviewAndPublishTheDelta() async throws {
    let fixture = try AppFormulaOperationFixture("m13g-formula-update")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let runner = AppFormulaUpgradeRunner(fixture: fixture)
    let service = fixture.makeService(operationRunner: runner)
    let local = try await service.localSnapshot()
    let scanned = try #require(local.entries.first)
    let entry = fixture.updatedEntry(scanned)

    let prepared = await service.prepareFormulaUpdate(for: entry)
    guard case .ready(let preparation) = prepared else {
        Issue.record("expected a formula update preparation, got \(prepared)")
        return
    }
    #expect(preparation.preview.kind == .formula)
    #expect(preparation.preview.registryID == "hermes-id")
    #expect(preparation.preview.fullName == "hermes-agent")
    #expect(preparation.preview.prefix == fixture.prefix.path)
    #expect(preparation.preview.timeoutSeconds == 900)
    #expect(preparation.preview.arguments == ["upgrade", "--formula", "--yes", "hermes-agent"])
    #expect(preparation.preview.effect.contains("900 seconds"))

    let result = await service.executeFormulaUpdate(preparation)
    let outcome = result.outcome
    #expect(runner.invocationCount == 1)
    #expect(outcome.processStarted)
    #expect(outcome.state == .succeeded)
    #expect(outcome.reconciliation?.previousKegReplaced == true)
    #expect(outcome.reconciliation?.versionMatchesTarget == true)
    let refreshed = try #require(result.snapshot?.entries.first)
    #expect(refreshed.diagnostic.detectedTool.version?.contains(fixture.targetVersion) == true)
    #expect(refreshed.installState == .installedAndOnPath)
}

@Test func formulaUpdatePreparationRefusesAnUnverifiedManagerIdentity() async throws {
    let fixture = try AppFormulaOperationFixture("m13g-formula-update-guard")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let operationRunner = AppFormulaCountingOperationRunner()
    let service = fixture.makeService(operationRunner: operationRunner)
    let local = try await service.localSnapshot()
    let scanned = try #require(local.entries.first)

    // The published update result still has no manager identity (a declaration is not proof).
    let result = await service.prepareFormulaUpdate(for: scanned)
    guard case .unavailable(let reason) = result else {
        Issue.record("expected a typed refusal")
        return
    }
    #expect(reason == .notUpdateAvailable)
    #expect(operationRunner.invocationCount == 0)
}

@Test func formulaUninstallPreparationAndExecutionForwardTheTypedPreviewAndPublishTheRemoval() async throws {
    let fixture = try AppFormulaOperationFixture("m13g-formula-uninstall")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let runner = AppFormulaUninstallRunner(fixture: fixture)
    let service = fixture.makeService(operationRunner: runner)
    let local = try await service.localSnapshot()
    let scanned = try #require(local.entries.first)
    let ownership = await service.verifyingOwnership(of: scanned)
    #expect(ownership.verifiedInstallation?.manager == .homebrewFormula)
    let entry = InventoryEntry(
        definition: scanned.definition,
        diagnostic: scanned.diagnostic,
        update: nil,
        ownership: ownership
    )

    let prepared = await service.prepareFormulaUninstall(for: entry)
    guard case .ready(let preparation) = prepared else {
        Issue.record("expected a formula uninstall preparation, got \(prepared)")
        return
    }
    #expect(preparation.preview.kind == .formula)
    #expect(preparation.preview.installedKegs == ["1.0.0"])
    #expect(preparation.preview.arguments == ["uninstall", "--formula", "hermes-agent"])

    let result = await service.executeFormulaUninstall(preparation)
    let outcome = result.outcome
    #expect(runner.invocationCount == 1)
    #expect(outcome.processStarted)
    #expect(outcome.state == .succeeded)
    #expect(outcome.reconciliation?.recordedKegAbsent == true)
    #expect(outcome.reconciliation?.selectedTargetReleased == true)
    let refreshed = try #require(result.snapshot?.entries.first)
    #expect(refreshed.installState == .notInstalled)
}

@Test func caskUpdatePreparationNeverBorrowsAFormulaIdentity() async throws {
    let fixture = try AppFormulaOperationFixture("m13g-cask-update-guard")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let operations = AppFormulaCountingOperationRunner()
    let service = fixture.makeService(operationRunner: operations)
    let local = try await service.localSnapshot()
    let scanned = try #require(local.entries.first)
    // The published result is a verified formula identity; the cask route must refuse rather than
    // fall back across manager kinds.
    let entry = fixture.updatedEntry(scanned)
    let result = await service.prepareCaskUpdate(for: entry)
    guard case .unavailable(let reason) = result else {
        Issue.record("expected a typed cask refusal")
        return
    }
    #expect(reason == .notUpdateAvailable)
    #expect(operations.invocationCount == 0)
}

@Test func caskUninstallPreparationRequiresVerifiedCaskOwnership() async throws {
    let fixture = try AppFormulaOperationFixture("m13g-cask-uninstall-guard")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let operations = AppFormulaCountingOperationRunner()
    let service = fixture.makeService(operationRunner: operations)
    let local = try await service.localSnapshot()
    let scanned = try #require(local.entries.first)
    let ownership = await service.verifyingOwnership(of: scanned)
    let entry = InventoryEntry(
        definition: scanned.definition,
        diagnostic: scanned.diagnostic,
        update: nil,
        ownership: ownership
    )
    let result = await service.prepareCaskUninstall(for: entry)
    guard case .unavailable(let reason) = result else {
        Issue.record("expected a typed cask refusal")
        return
    }
    #expect(reason == .identityUnverified)
    #expect(operations.invocationCount == 0)
}

// MARK: - M13-G Homebrew cask operation boundary

/// Mutable manager answers shared by the read-only cask queries (ownership verification and the
/// confirmed observation) and the operation runners, so the post-launch reconciliation reads
/// exactly the mutation the runner performed. No real manager is ever invoked.
final class AppCaskManagerState: @unchecked Sendable {
    private let lock = NSLock()
    private var installedVersion: String?
    private var staged: [String]
    private var outdated: Bool

    init(installedVersion: String?, staged: [String], outdated: Bool) {
        self.installedVersion = installedVersion
        self.staged = staged
        self.outdated = outdated
    }

    var installed: String? {
        lock.lock(); defer { lock.unlock() }
        return installedVersion
    }

    var isOutdated: Bool {
        lock.lock(); defer { lock.unlock() }
        return outdated
    }

    var stagedPaths: [String] {
        lock.lock(); defer { lock.unlock() }
        return staged
    }

    func apply(installedVersion: String?, stagedPaths: [String], outdated: Bool) {
        lock.lock()
        self.installedVersion = installedVersion
        self.staged = stagedPaths
        self.outdated = outdated
        lock.unlock()
    }
}

/// A disposable synthetic Homebrew cask installation:
/// `<prefix>/Caskroom/<token>/<installed>/<token>` linked from `<prefix>/bin/<token>`, the saved
/// installed definition/receipt Homebrew leaves in `<token>/.metadata`, and a synthetic `brew`
/// executable in `<prefix>/bin`. `npmCodex` additionally installs one npm-shaped package in the
/// same prefix so a single service exercises both managers. No real manager, Caskroom or
/// /Applications path is touched.
struct AppCaskOperationFixture: Sendable {
    let root: URL
    let prefix: URL
    let caskroom: URL
    let binDirectory: URL
    let brewPath: String
    let entry: URL
    let token: String
    let tap: String
    let installedVersion: String
    let targetVersion: String
    let operationBase: URL
    let environment: ShellEnvironment
    let registryData: Data
    let definition: DetectorDefinition
    let definitions: [DetectorDefinition]
    let state: AppCaskManagerState
    /// The npm-shaped companion installed by `npmCodex`, if any.
    let npmGlobalRoot: URL?
    let npmScratchDirectory: URL?

    var tokenDirectory: URL { caskroom.appendingPathComponent(token, isDirectory: true) }

    init(_ label: String, npmCodex: Bool = false) throws {
        let rootValue = try appSupportScratchRoot(label)
        let prefixValue = rootValue.appendingPathComponent("prefix", isDirectory: true)
        let binValue = prefixValue.appendingPathComponent("bin", isDirectory: true)
        let caskroomValue = prefixValue.appendingPathComponent("Caskroom", isDirectory: true)
        let caskToken = "m13cask"
        let installed = "1.0.0"
        let latest = "2.0.0"
        try FileManager.default.createDirectory(at: binValue, withIntermediateDirectories: true)
        try writeFixtureExecutable(binValue.appendingPathComponent("brew"))

        var detectors = [
            """
            {"id":"m13cask-id","displayName":"M13 Cask","executableName":"m13cask",\
            "category":"aiAgent","packages":[{"manager":"homebrewCask","name":"m13cask"}],\
            "acceptedOperations":["homebrewCaskUpdate","homebrewCaskUninstall"],\
            "versionQuery":{"arguments":["--version"],"stream":"stdout","line":"first"}}
            """,
            """
            {"id":"beta-id","displayName":"Beta","executableName":"beta","category":"aiHarness",\
            "packages":[],"versionQuery":{"arguments":["--version"],"stream":"stdout","line":"first"}}
            """,
        ]
        var globalRoot: URL?
        var scratch: URL?
        if npmCodex {
            try writeFixtureExecutable(binValue.appendingPathComponent("npm"))
            let npmRoot = prefixValue.appendingPathComponent("lib/node_modules", isDirectory: true)
            let codexRoot = npmRoot.appendingPathComponent("@openai/codex", isDirectory: true)
            let codexTarget = codexRoot.appendingPathComponent("bin/codex")
            try m13gWriteCaskExecutable(codexTarget, token: "codex", version: "1.0.0")
            try Data(
                "{\"name\":\"@openai/codex\",\"version\":\"1.0.0\",\"bin\":{\"codex\":\"bin/codex\"}}".utf8
            ).write(to: codexRoot.appendingPathComponent("package.json"))
            try FileManager.default.createSymbolicLink(
                atPath: binValue.appendingPathComponent("codex").path,
                withDestinationPath: codexTarget.path
            )
            let scratchValue = rootValue.appendingPathComponent("npm-scratch", isDirectory: true)
            try FileManager.default.createDirectory(
                at: scratchValue, withIntermediateDirectories: true
            )
            globalRoot = npmRoot
            scratch = scratchValue
            detectors.append(
                """
                {"id":"codex-id","displayName":"Codex","executableName":"codex","category":"aiAgent",\
                "packages":[{"manager":"npm","name":"@openai/codex"}],"acceptedOperations":["npmUpdate"],\
                "versionQuery":{"arguments":["--version"],"stream":"stdout","line":"first"}}
                """
            )
        }
        let data = Data(
            "{\"schemaVersion\":2,\"detectors\":[\(detectors.joined(separator: ","))]}".utf8
        )
        let canonicalPrefix = prefixValue.resolvingSymlinksInPath()
        let canonicalBin = canonicalPrefix.appendingPathComponent("bin", isDirectory: true)
        let canonicalCaskroom = canonicalPrefix.appendingPathComponent("Caskroom", isDirectory: true)
        let joinedPath = canonicalBin.path
        let environmentValue = ShellEnvironment(
            shellPath: "/bin/zsh",
            pathEntries: [joinedPath],
            pathJoined: joinedPath,
            raw: ["PATH": joinedPath, "HOME": rootValue.appendingPathComponent("home").path],
            isDegraded: false
        )
        let operationBaseValue = rootValue.appendingPathComponent("operation-base", isDirectory: true)
        try FileManager.default.createDirectory(
            at: operationBaseValue, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        let validated = try DetectorRegistry.validate(data: data)
        self.root = rootValue
        self.prefix = canonicalPrefix
        self.caskroom = canonicalCaskroom
        self.binDirectory = canonicalBin
        self.brewPath = canonicalBin.appendingPathComponent("brew").path
        self.entry = canonicalBin.appendingPathComponent(caskToken)
        self.token = caskToken
        self.tap = "homebrew/cask"
        self.installedVersion = installed
        self.targetVersion = latest
        self.operationBase = operationBaseValue
        self.environment = environmentValue
        self.registryData = data
        self.definitions = validated
        self.definition = validated[0]
        self.npmGlobalRoot = globalRoot
        self.npmScratchDirectory = scratch
        self.state = AppCaskManagerState(
            installedVersion: nil, staged: [], outdated: false
        )
        try install(version: installed)
    }

    /// Writes one real Caskroom version directory with its saved installed metadata and relinks the
    /// `prefix/bin` entry, then updates the manager answers the read-only queries read.
    private func install(version: String) throws {
        try? FileManager.default.removeItem(at: tokenDirectory)
        let versionDirectory = tokenDirectory.appendingPathComponent(version, isDirectory: true)
        let source = versionDirectory.appendingPathComponent(token)
        try m13gWriteCaskExecutable(source, token: token, version: version)
        try Self.writeInstalledMetadata(
            tokenDirectory: tokenDirectory, token: token, tap: tap, version: version
        )
        try? FileManager.default.removeItem(at: entry)
        try FileManager.default.createSymbolicLink(
            atPath: entry.path, withDestinationPath: source.path
        )
        state.apply(
            installedVersion: version,
            stagedPaths: [source.resolvingSymlinksInPath().path],
            outdated: version != targetVersion
        )
    }

    /// The mutation `brew upgrade --cask` performs: the new staged version replaces the old one.
    func applyUpdate() throws {
        try install(version: targetVersion)
    }

    /// The mutation `brew uninstall --cask` performs: the token directory and link disappear.
    func applyUninstall() throws {
        try? FileManager.default.removeItem(at: tokenDirectory)
        try? FileManager.default.removeItem(at: entry)
        state.apply(installedVersion: nil, stagedPaths: [], outdated: false)
    }

    /// Homebrew's real saved layout under the cask's token directory:
    /// `.metadata/INSTALL_RECEIPT.json`, `.metadata/config.json`, and the winning
    /// `.metadata/<version>/<stamp>/Casks/<token>.json`.
    static func writeInstalledMetadata(
        tokenDirectory: URL,
        token: String,
        tap: String,
        version: String
    ) throws {
        let metadata = tokenDirectory.appendingPathComponent(".metadata", isDirectory: true)
        let casks = metadata
            .appendingPathComponent(version, isDirectory: true)
            .appendingPathComponent("20260101000000.123", isDirectory: true)
            .appendingPathComponent("Casks", isDirectory: true)
        try FileManager.default.createDirectory(at: casks, withIntermediateDirectories: true)
        let receipt: [String: Any] = [
            "source": ["tap": tap, "version": version],
            "uninstall_flight_blocks": false,
            "uninstall_artifacts": [["binary": [token]]],
        ]
        try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys])
            .write(to: metadata.appendingPathComponent("INSTALL_RECEIPT.json"))
        try JSONSerialization.data(withJSONObject: [String: Any](), options: [.sortedKeys])
            .write(to: casks.appendingPathComponent(token + ".json"))
        let config: [String: Any] = [
            "default": [String: Any](), "env": [String: Any](), "explicit": [String: Any](),
        ]
        try JSONSerialization.data(withJSONObject: config, options: [.sortedKeys])
            .write(to: metadata.appendingPathComponent("config.json"))
    }

    /// Deterministic read-only manager answers for the four cask owner probes, the confirmed
    /// observation, the pin list and the ordinary outdated list. Nothing is launched for real.
    var managerHandler: @Sendable (String, [String]) -> CommandOutcome {
        let prefixPath = prefix.path
        let caskroomPath = caskroom.path
        let caskToken = token
        let caskTap = tap
        let target = binDirectory.appendingPathComponent(token).path
        let latest = targetVersion
        let state = state
        return { _, arguments in
            switch arguments.first {
            case "--prefix":
                return .success(Data((prefixPath + "\n").utf8))
            case "--caskroom":
                return .success(Data((caskroomPath + "\n").utf8))
            case "info":
                let record: [String: Any] = [
                    "token": caskToken,
                    "full_token": caskToken,
                    "tap": caskTap,
                    "version": latest,
                    "installed": state.installed.map { $0 as Any } ?? NSNull(),
                    "auto_updates": NSNull(),
                    "pinned": false,
                    "outdated": state.isOutdated,
                    "disabled": false,
                    "old_tokens": [String](),
                    "depends_on": [String: Any](),
                    "artifacts": [["binary": [caskToken], "target": target]],
                ]
                guard let data = try? JSONSerialization.data(withJSONObject: ["casks": [record]])
                else { return .failure(.invalidOutput) }
                return .success(data)
            case "list":
                if arguments.contains("--pinned") { return .success(Data()) }
                if arguments.contains("--verbose") {
                    guard state.installed != nil, !state.stagedPaths.isEmpty else {
                        return .failure(.nonzeroExit)
                    }
                    let text = state.stagedPaths.joined(separator: "\n") + "\n"
                    return .success(Data(text.utf8))
                }
                return .success(Data())
            case "outdated":
                guard state.isOutdated, let installed = state.installed else {
                    return .success(Data("{\"casks\":[]}".utf8))
                }
                let row: [String: Any] = [
                    "name": caskToken,
                    "current_version": latest,
                    "installed_versions": [installed],
                    "pinned": false,
                ]
                guard let data = try? JSONSerialization.data(withJSONObject: ["casks": [row]])
                else { return .failure(.invalidOutput) }
                return .success(data)
            default:
                return .failure(.spawnFailure)
            }
        }
    }

    func makeService(
        operationRunner: OperationCommandRunner,
        updateRunner: UpdateCommandRunner? = nil,
        registryLoader: (@Sendable () throws -> [DetectorDefinition])? = nil
    ) -> InventoryService {
        let environment = self.environment
        let definitions = self.definitions
        let handler = self.managerHandler
        let manager = updateRunner ?? RecordingManagerRunner(handler: handler)
        let registry: @Sendable () throws -> [DetectorDefinition] = registryLoader ?? { definitions }
        let source = SessionEnvironmentSource(
            resolve: { environment },
            loginShellPath: { "/bin/sh" },
            capture: { _ in
                ShellEnvironmentResolver.CaptureOutcome(dump: environment.raw, timedOut: false)
            },
            build: { _, _ in environment }
        )
        return InventoryService(
            environment: SessionEnvironmentProvider(source: source),
            registry: registry,
            scanner: { detector, env, cwd in
                PathDiagnosticsScanner.scan(detector: detector, environment: env, currentDirectory: cwd)
            },
            updateRunner: manager,
            operationRunner: operationRunner,
            operationGate: OperationExecutionGate(),
            operationRootBaseURL: operationBase,
            updateCacheURL: root.appendingPathComponent("cache.json"),
            npmScratchBaseURL: npmScratchDirectory,
            currentDirectory: root.path,
            clock: fixedClock()
        )
    }

    /// A published entry carrying the manager-verified cask update identity the presentation gate
    /// reads. The diagnostic is the real scanned value; the observed selection is copied exactly as
    /// the coordinator copies it (the PATH-slot entry and its canonical Caskroom target).
    func updatedEntry(_ entry: InventoryEntry) -> InventoryEntry {
        let selected = entry.diagnostic.observedSelectionPair
        return InventoryEntry(
            definition: entry.definition,
            diagnostic: entry.diagnostic,
            update: ToolUpdateResult(
                registryID: entry.registryID,
                displayName: entry.definition.displayName,
                diagnosticIndex: 0,
                diagnostic: entry.diagnostic,
                localVersion: installedVersion,
                selectedEntryPath: selected?.entry,
                selectedTarget: selected?.target,
                selectedKegVersion: nil,
                managerEntryPath: brewPath,
                managerTarget: brewPath,
                managerFingerprint: nil,
                managerCellar: nil,
                formulaStem: nil,
                fullFormulaName: nil,
                caskToken: token,
                caskFullToken: token,
                caskTap: tap,
                caskInstalledVersion: installedVersion,
                caskPinned: false,
                status: .updateAvailable(
                    installed: Version(installedVersion), latest: Version(targetVersion)
                ),
                provenance: .freshProbe(observedAt: Date(timeIntervalSince1970: 0))
            ),
            ownership: entry.ownership
        )
    }
}

/// A versioned shell script standing in for a cask's command-line artifact.
private func m13gWriteCaskExecutable(_ url: URL, token: String, version: String) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try Data("#!/bin/sh\necho '\(token) \(version)'\nexit 0\n".utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
}

/// Performs the update mutation the real manager would and records the literal argv it received.
final class AppCaskUpgradeRunner: OperationCommandRunner, @unchecked Sendable {
    let fixture: AppCaskOperationFixture
    private let lock = NSLock()
    private var recorded: [[String]] = []

    init(fixture: AppCaskOperationFixture) {
        self.fixture = fixture
    }

    var invocationCount: Int {
        lock.lock(); defer { lock.unlock() }
        return recorded.count
    }

    var recordedArguments: [[String]] {
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
        try? fixture.applyUpdate()
        return OperationCommandResult(
            stdout: Data("upgraded\n".utf8), stderr: Data(),
            stdoutTruncated: false, stderrTruncated: false,
            exitStatus: 0, processStarted: true,
            timedOut: false, cancelled: false, cleanupWarning: false
        )
    }
}

/// Performs the removal mutation the real manager would and records the literal argv it received.
final class AppCaskUninstallRunner: OperationCommandRunner, @unchecked Sendable {
    let fixture: AppCaskOperationFixture
    private let lock = NSLock()
    private var recorded: [[String]] = []

    init(fixture: AppCaskOperationFixture) {
        self.fixture = fixture
    }

    var invocationCount: Int {
        lock.lock(); defer { lock.unlock() }
        return recorded.count
    }

    var recordedArguments: [[String]] {
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
        try? fixture.applyUninstall()
        return OperationCommandResult(
            stdout: Data("uninstalled\n".utf8), stderr: Data(),
            stdoutTruncated: false, stderrTruncated: false,
            exitStatus: 0, processStarted: true,
            timedOut: false, cancelled: false, cleanupWarning: false
        )
    }
}

@Test func caskUpdatePreparationCancelReprepareAndExecutionForwardTheTypedPreviewAndPublishTheDelta() async throws {
    let fixture = try AppCaskOperationFixture("m13g-cask-update")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let runner = AppCaskUpgradeRunner(fixture: fixture)
    let service = fixture.makeService(operationRunner: runner)
    let local = try await service.localSnapshot()
    let scanned = try #require(local.entries.first { $0.registryID == "m13cask-id" })
    let entry = fixture.updatedEntry(scanned)
    #expect(ManagementPresentation.verifiedHomebrewUpdateKind(entry) == .cask)

    let prepared = await service.prepareCaskUpdate(for: entry)
    guard case .ready(let preparation) = prepared else {
        Issue.record("expected a cask update preparation, got \(prepared)")
        return
    }
    let preview = preparation.preview
    #expect(preview.kind == .cask)
    #expect(preview.registryID == "m13cask-id")
    #expect(preview.token == fixture.token)
    #expect(preview.fullToken == fixture.token)
    #expect(preview.tap == fixture.tap)
    #expect(preview.installedVersion == fixture.installedVersion)
    #expect(preview.targetVersion == fixture.targetVersion)
    #expect(preview.prefix == fixture.prefix.path)
    #expect(preview.caskroom == fixture.caskroom.path)
    #expect(preview.executablePath == fixture.brewPath)
    #expect(preview.arguments == ["upgrade", "--cask", "--yes", fixture.token])
    #expect(preview.timeoutSeconds == 900)
    #expect(FileManager.default.fileExists(atPath: preview.workingDirectory))
    #expect(runner.invocationCount == 0)

    // Cancel releases the owned scratch root with zero mutation and no manager launch.
    #expect(service.cancelCaskUpdate(preparation))
    #expect(!FileManager.default.fileExists(atPath: preview.workingDirectory))
    #expect(runner.invocationCount == 0)
    #expect(FileManager.default.fileExists(atPath: fixture.entry.path))
    #expect(FileManager.default.fileExists(
        atPath: fixture.tokenDirectory.appendingPathComponent(fixture.installedVersion).path
    ))

    // The same entry re-prepares into a fresh owned root, then executes exactly once.
    let reprepared = await service.prepareCaskUpdate(for: entry)
    guard case .ready(let confirmed) = reprepared else {
        Issue.record("expected a second cask update preparation, got \(reprepared)")
        return
    }
    #expect(confirmed.preview.workingDirectory != preview.workingDirectory)
    #expect(FileManager.default.fileExists(atPath: confirmed.preview.workingDirectory))

    let result = await service.executeCaskUpdate(confirmed)
    let outcome = result.outcome
    #expect(runner.invocationCount == 1)
    #expect(runner.recordedArguments == [["upgrade", "--cask", "--yes", fixture.token]])
    #expect(outcome.processStarted)
    #expect(outcome.state == .succeeded)
    #expect(outcome.reconciliation?.beforeInstalledVersion == fixture.installedVersion)
    #expect(outcome.reconciliation?.afterInstalledVersion == fixture.targetVersion)
    #expect(outcome.reconciliation?.versionMatchesTarget == true)
    #expect(outcome.reconciliation?.stagedMembershipConfirmed == true)
    #expect(!FileManager.default.fileExists(atPath: confirmed.preview.workingDirectory))
    let refreshed = try #require(result.snapshot?.entries.first { $0.registryID == "m13cask-id" })
    #expect(refreshed.installState == .installedAndOnPath)
    #expect(refreshed.diagnostic.detectedTool.version?.contains(fixture.targetVersion) == true)
}

@Test func caskUninstallPreparationCancelReprepareAndExecutionForwardTheTypedPreviewAndPublishTheRemoval() async throws {
    let fixture = try AppCaskOperationFixture("m13g-cask-uninstall-run")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let runner = AppCaskUninstallRunner(fixture: fixture)
    let service = fixture.makeService(operationRunner: runner)
    let local = try await service.localSnapshot()
    let scanned = try #require(local.entries.first { $0.registryID == "m13cask-id" })
    let ownership = await service.verifyingOwnership(of: scanned)
    #expect(ownership.verifiedInstallation?.manager == .homebrewCask)
    let entry = InventoryEntry(
        definition: scanned.definition,
        diagnostic: scanned.diagnostic,
        update: nil,
        ownership: ownership
    )

    let prepared = await service.prepareCaskUninstall(for: entry)
    guard case .ready(let preparation) = prepared else {
        Issue.record("expected a cask uninstall preparation, got \(prepared)")
        return
    }
    let preview = preparation.preview
    #expect(preview.kind == .cask)
    #expect(preview.token == fixture.token)
    #expect(preview.fullToken == fixture.token)
    #expect(preview.tap == fixture.tap)
    #expect(preview.installedVersion == fixture.installedVersion)
    #expect(preview.prefix == fixture.prefix.path)
    #expect(preview.caskroom == fixture.caskroom.path)
    #expect(preview.executablePath == fixture.brewPath)
    #expect(preview.arguments == ["uninstall", "--cask", fixture.token])
    #expect(!preview.arguments.contains("--zap"))
    #expect(preview.timeoutSeconds == 900)
    #expect(FileManager.default.fileExists(atPath: preview.workingDirectory))
    #expect(runner.invocationCount == 0)

    #expect(service.cancelCaskUninstall(preparation))
    #expect(!FileManager.default.fileExists(atPath: preview.workingDirectory))
    #expect(runner.invocationCount == 0)
    #expect(FileManager.default.fileExists(atPath: fixture.tokenDirectory.path))

    let reprepared = await service.prepareCaskUninstall(for: entry)
    guard case .ready(let confirmed) = reprepared else {
        Issue.record("expected a second cask uninstall preparation, got \(reprepared)")
        return
    }
    let result = await service.executeCaskUninstall(confirmed)
    let outcome = result.outcome
    #expect(runner.invocationCount == 1)
    #expect(runner.recordedArguments == [["uninstall", "--cask", fixture.token]])
    #expect(outcome.processStarted)
    #expect(outcome.state == .succeeded)
    #expect(outcome.reconciliation?.beforeInstalledVersion == fixture.installedVersion)
    #expect(outcome.reconciliation?.afterInstalledVersion == nil)
    #expect(outcome.reconciliation?.infoInstalledAbsent == true)
    #expect(outcome.reconciliation?.tokenDirectoryAbsent == true)
    #expect(outcome.reconciliation?.selectedTargetReleased == true)
    #expect(!FileManager.default.fileExists(atPath: confirmed.preview.workingDirectory))
    let refreshed = try #require(result.snapshot?.entries.first { $0.registryID == "m13cask-id" })
    #expect(refreshed.installState == .notInstalled)
}
