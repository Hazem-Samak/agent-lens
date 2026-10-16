// InventoryServiceTests — M7 stage 2: the typed app boundary over the accepted M0–M6 engine.
//
// Every fixture is immutable and synthetic: a JSON registry, a login-shell environment with a
// closed PATH, an injected scanner, a scripted manager runner, a fixed clock, and a test-owned
// cache URL in scratch. No test resolves the real login shell, reads the real PATH, launches a
// package manager, or touches the real Agent Lens cache.
//
// This file also holds the scratch/filesystem helpers shared with SessionEnvironmentProviderTests
// (same test target).

import AgentLensCore
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

/// Schema-1 registry JSON for the given rows, in the given order.
func registryJSON(_ rows: [RegistryRow]) -> Data {
    let detectors = rows.map { row -> String in
        let roots = row.extraSearchRoots.isEmpty
            ? ""
            : ",\"extraSearchRoots\":[\(row.extraSearchRoots.map { "\"\($0)\"" }.joined(separator: ","))]"
        return "{\"id\":\"\(row.id)\",\"displayName\":\"\(row.displayName)\",\"executableName\":\"\(row.executableName)\"\(roots)}"
    }.joined(separator: ",")
    return Data("{\"schemaVersion\":1,\"detectors\":[\(detectors)]}".utf8)
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
            detector: definition.makeDetector(versionQuery: { _, _, _ -> String? in nil }),
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