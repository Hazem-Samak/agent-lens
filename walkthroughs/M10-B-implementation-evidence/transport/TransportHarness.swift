// M10-B batch3 headless controlled-transport harness (WORKER EVIDENCE, not acceptance).
//
// Why this exists: the coordinator's native host (`E/native/FixtureHost.swift`) drives the same
// production path through a SwiftUI window, which needs a GUI session and manual interaction, so it
// stays coordinator-owned (AC08). This harness keeps the WINDOW out and runs the identical shipping
// code path headlessly: `InventoryService.localSnapshot()` → `applyingUpdates(to:mode:)` →
// `UpdateProbeCoordinator` → `NpmUpdateProbe` → the production `ProcessUpdateCommandRunner`.
//
// Controlled transport (AC09): the real `npm` binary from the prepared fixture is launched with the
// EXACT production argv, and ONLY the two registry flags are substituted to a loopback server that
// this harness started. There is no product debug/custom-registry switch — substitution lives here,
// in the external harness, after the harness has verified production pinned BOTH the base and the
// `@openai` scope registry to the public origin.
//
// View detection is by PARSED SUBCOMMAND, not `arguments.first`: production puts the app-owned
// scratch flags (`--cache <root> --logs-dir <root> --no-update-notifier`) before `view`, so a
// `first == "view"` test never fires.
//
// Everything this harness writes lives under its own worker root: the cache document, the npm
// scratch base, the registry endpoint, and the argv receipts. The prepared fixture is read-only.

import AgentLensAppSupport
import AgentLensCore
import Foundation

private let workerRoot = URL(
    fileURLWithPath:
        "/private/tmp/agent-lens-m10b-implementation-9jaujmja/parent/qoder-r1-batch3"
)
private let fixtureRoot = URL(
    fileURLWithPath: "/private/tmp/agent-lens-m10b-implementation-9jaujmja/fixture"
)
private let transportRoot = workerRoot.appendingPathComponent("transport", isDirectory: true)

// MARK: - Receipts

actor Receipts {
    static let shared = Receipts()
    private let url: URL
    init() {
        url = transportRoot.appendingPathComponent("harness-receipts.jsonl")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
    }
    func append(_ row: [String: String]) {
        guard let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]),
              let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        try? handle.seekToEnd()
        try? handle.write(contentsOf: data + Data([10]))
    }
}

/// npm's subcommand, parsed past flags that precede it. `--cache`/`--logs-dir` each consume the NEXT
/// token as a value (an app-owned scratch directory that does not start with `-`), so the first
/// non-flag token is NOT the subcommand.
func parsedNpmSubcommand(_ arguments: [String]) -> String? {
    let valueTakingFlags: Set<String> = ["--cache", "--logs-dir", "--userconfig", "--prefix", "-C"]
    var index = 0
    while index < arguments.count {
        let token = arguments[index]
        if token.hasPrefix("-") {
            index += valueTakingFlags.contains(token) ? 2 : 1
            continue
        }
        return token
    }
    return nil
}

/// The controlled-transport runner: real production `ProcessUpdateCommandRunner`, with ONLY the two
/// public registry pins rewritten to the loopback endpoint after they have both been verified.
struct TransportRunner: UpdateCommandRunner {
    func run(
        executablePath: String, arguments: [String],
        environment: [String: String], timeout: TimeInterval
    ) async -> CommandOutcome {
        var executed = arguments
        let subcommand = parsedNpmSubcommand(arguments)
        var substituted = "false"
        if subcommand == "view" {
            guard let endpoint = try? String(
                contentsOf: transportRoot.appendingPathComponent("registry-url.txt"),
                encoding: .utf8
            ).trimmingCharacters(in: .whitespacesAndNewlines), endpoint.hasPrefix("http://127.0.0.1:")
            else { return .failure(.invalidOutput) }
            // Substitution is authorized only for an argv production pinned to the PUBLIC origin on
            // BOTH the base registry and the scope registry.
            guard arguments.contains("--registry=https://registry.npmjs.org/"),
                  arguments.contains("--@openai:registry=https://registry.npmjs.org/")
            else {
                await Receipts.shared.append([
                    "phase": "refused-unpinned-view", "originalArgv": arguments.description,
                ])
                return .failure(.invalidOutput)
            }
            executed = arguments.map {
                if $0.hasPrefix("--registry=") { return "--registry=\(endpoint)" }
                if $0.hasPrefix("--@openai:registry=") { return "--@openai:registry=\(endpoint)" }
                return $0
            }
            substituted = "true"
        }
        await Receipts.shared.append([
            "phase": "launch",
            "executable": executablePath,
            "subcommand": subcommand ?? "",
            "containsViewToken": String(arguments.contains("view")),
            "substituted": substituted,
            "originalArgv": arguments.description,
            "executedArgv": executed.description,
            "timeout": String(timeout),
            "cacheFlag": arguments.firstIndex(of: "--cache").map { arguments[$0 + 1] } ?? "",
        ])
        let result = await ProcessUpdateCommandRunner().run(
            executablePath: executablePath, arguments: executed,
            environment: environment, timeout: timeout
        )
        await Receipts.shared.append([
            "phase": "return", "subcommand": subcommand ?? "",
            "outcome": String(describing: result),
        ])
        return result
    }
}

// MARK: - Main

func report(_ label: String, _ value: String) {
    print("\(label): \(value)")
}

func listing(_ url: URL) -> String {
    (try? FileManager.default.contentsOfDirectory(atPath: url.path))?.sorted().description ?? "absent"
}

do {
    let arguments = CommandLine.arguments
    let mode: UpdateProbeMode = arguments.contains("--refresh") ? .refresh : .checkUpdates
    let raw = try JSONDecoder().decode(
        [String: String].self,
        from: Data(contentsOf: fixtureRoot.appendingPathComponent("environment.json"))
    )
    let pathEntries = (raw["PATH"] ?? "").split(separator: ":").map(String.init)
    let environment = ShellEnvironment(
        shellPath: "/bin/zsh", pathEntries: pathEntries, pathJoined: raw["PATH"] ?? "",
        raw: raw, isDegraded: false
    )
    let source = SessionEnvironmentSource(
        resolve: { environment },
        loginShellPath: { "/bin/zsh" },
        capture: { _ in .init(dump: nil, timedOut: true) },
        build: { _, _ in environment }
    )
    let registry = try Data(contentsOf: fixtureRoot.appendingPathComponent("registry.json"))

    // Worker-owned scratch base and cache document — the prepared fixture is never written to.
    let fileManager = FileManager.default
    let scratchBase = transportRoot.appendingPathComponent("npm-scratch", isDirectory: true)
    try fileManager.createDirectory(at: scratchBase, withIntermediateDirectories: true)
    try fileManager.setAttributes(
        [.posixPermissions: NSNumber(value: 0o700)], ofItemAtPath: scratchBase.path
    )
    let appCache = transportRoot.appendingPathComponent("app-cache", isDirectory: true)
    try fileManager.createDirectory(at: appCache, withIntermediateDirectories: true)
    let cacheURL = appCache.appendingPathComponent("update-metadata-v1.json")
    let npmDocumentURL = appCache.appendingPathComponent("npm-update-metadata-v1.json")

    let service = InventoryService(
        environment: SessionEnvironmentProvider(source: source),
        registry: { try DetectorRegistry.validate(data: registry) },
        updateRunner: TransportRunner(),
        updateCacheURL: cacheURL,
        npmScratchBaseURL: scratchBase,
        currentDirectory: fixtureRoot.path
    )

    report("mode", mode == .refresh ? "refresh" : "checkUpdates")
    report("scratchBase-before", listing(scratchBase))
    let snapshot = try await service.localSnapshot()
    let updated = await service.applyingUpdates(to: snapshot, mode: mode)
    report("scratchBase-after", listing(scratchBase))
    for entry in updated.entries {
        guard let result = entry.update else { continue }
        report(
            "result",
            [
                "registryID=\(result.registryID)",
                "display=\(entry.definition.displayName)",
                "local=\(result.localVersion ?? "nil")",
                "status=\(result.status)",
                "provenance=\(result.provenance)",
                "npmPackage=\(result.npmPackage ?? "nil")",
                "npmRegistry=\(result.npmRegistry ?? "nil")",
                "npmTag=\(result.npmTag ?? "nil")",
                "npmVersion=\(result.npmVersion ?? "nil")",
            ].joined(separator: " ")
        )
    }
    report("npmDocumentExists", String(fileManager.fileExists(atPath: npmDocumentURL.path)))
    if let data = try? Data(contentsOf: npmDocumentURL) {
        struct Doc: Decodable { struct E: Decodable { let package: String; let version: String; let tag: String; let registry: String }
            let schemaVersion: Int; let entries: [E] }
        if let doc = try? JSONDecoder().decode(Doc.self, from: data) {
            report("npmSchemaVersion", String(doc.schemaVersion))
            report("npmEntryCount", String(doc.entries.count))
            for record in doc.entries {
                report("npmRecord", "\(record.package) \(record.version) tag=\(record.tag) registry=\(record.registry)")
            }
        }
    }
    report("homebrewDocumentExists", String(fileManager.fileExists(atPath: cacheURL.path)))
    report("personalCachesAgentLens", String(
        fileManager.fileExists(atPath: ("\(NSHomeDirectory())/Library/Caches/AgentLens"))
    ))
} catch {
    report("harnessError", String(describing: error))
    exit(1)
}
