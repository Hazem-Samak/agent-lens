// M10-B batch3 worker copy of the controlled-transport external harness.
//
// Copy of the coordinator's `E/native/FixtureHost.swift` with the ONE correction this batch was
// asked for, plus evidence-hygiene changes. It is NOT acceptance evidence: it is worker-run
// controlled-transport evidence for AC09, which remains coordinator-owned.
//
// CORRECTION — the production metadata argv no longer starts with `view`: the app-owned scratch
// flags (`--cache <root> --logs-dir <root> --no-update-notifier`) precede the subcommand, so
// `arguments.first == "view"` never matched and the harness substituted nothing. Detection is now
// the PARSED SUBCOMMAND (npm's own value-taking flags are skipped), with a membership cross-check.
//
// Retained verbatim from the coordinator copy: BOTH public registry pins (`--registry=` and the
// `--@openai:registry=` scope pin) must be present BEFORE any controlled substitution, so the
// harness only ever redirects an argv that production itself already pinned to the public origin.
// There is still NO product debug/custom-registry switch: substitution lives only in this external
// runner.
//
// EVIDENCE HYGIENE (worker-only): query receipts are written into this worker's own evidence root
// instead of the shared prepared fixture, so `E/fixture` stays immutable.

import Foundation
import SwiftUI
import AgentLensCore
import AgentLensAppSupport

private let fixtureRoot = URL(fileURLWithPath: "/private/tmp/agent-lens-m10b-implementation-9jaujmja/fixture")
private let workerRoot = URL(fileURLWithPath: "/private/tmp/agent-lens-m10b-implementation-9jaujmja/parent/river-corrections")

actor FixtureReceipts {
    static let shared = FixtureReceipts()
    func append(_ row: [String: String]) {
        let url = workerRoot
            .appendingPathComponent("native", isDirectory: true)
            .appendingPathComponent("native-query-receipts.jsonl")
        guard let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]),
              let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        try? handle.seekToEnd()
        try? handle.write(contentsOf: data + Data([10]))
    }
}

/// npm's own subcommand, parsed past the leading scratch/value flags. `--cache` and `--logs-dir`
/// each consume the NEXT token as a value (an app-owned scratch directory that does not start with
/// `-`), so a naive "first non-flag token" would return that path instead of the subcommand.
private func parsedNpmSubcommand(_ arguments: [String]) -> String? {
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

struct FixtureRunner: UpdateCommandRunner {
    func run(executablePath: String, arguments: [String], environment: [String: String], timeout: TimeInterval) async -> CommandOutcome {
        var executed = arguments
        // Detection by parsed subcommand (membership is only a cross-check, never the discriminator).
        let isView = parsedNpmSubcommand(arguments) == "view"
        if isView {
            guard let endpoint = try? String(contentsOf: workerRoot.appendingPathComponent("transport/registry-url.txt"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), endpoint.hasPrefix("http://127.0.0.1:") else { return .failure(.invalidOutput) }
            // Controlled substitution is authorized ONLY for an argv production already pinned to
            // the public origin on BOTH the base and the scope flag.
            guard arguments.contains("--registry=https://registry.npmjs.org/"), arguments.contains("--@openai:registry=https://registry.npmjs.org/") else { return .failure(.invalidOutput) }
            executed = arguments.map {
                if $0.hasPrefix("--registry=") { return "--registry=\(endpoint)" }
                if $0.hasPrefix("--@openai:registry=") { return "--@openai:registry=\(endpoint)" }
                return $0
            }
        }
        await FixtureReceipts.shared.append(["phase":"launch", "executable":executablePath,"subcommand":parsedNpmSubcommand(arguments) ?? "","containsView":String(arguments.contains("view")),"originalArgv":arguments.description,"executedArgv":executed.description])
        let result = await ProcessUpdateCommandRunner().run(executablePath: executablePath, arguments: executed, environment: environment, timeout: timeout)
        await FixtureReceipts.shared.append(["phase":"return","outcome":String(describing:result)])
        return result
    }
}

@main
struct M10BFixtureHost: App {
    private let service: InventoryService
    init() {
        let raw = try! JSONDecoder().decode([String:String].self, from: Data(contentsOf: fixtureRoot.appendingPathComponent("environment.json")))
        let path = raw["PATH"]!.split(separator: ":").map(String.init)
        let environment = ShellEnvironment(shellPath: "/bin/zsh", pathEntries: path, pathJoined: raw["PATH"]!, raw: raw, isDegraded: false)
        let source = SessionEnvironmentSource(resolve: { environment }, loginShellPath: { "/bin/zsh" }, capture: { _ in .init(dump: nil, timedOut: true) }, build: { _,_ in environment })
        let registry = try! Data(contentsOf: fixtureRoot.appendingPathComponent("registry.json"))
        service = InventoryService(
            environment: SessionEnvironmentProvider(source: source),
            registry: { try DetectorRegistry.validate(data: registry) },
            updateRunner: FixtureRunner(),
            updateCacheURL: workerRoot.appendingPathComponent("native/app-cache/update-metadata-v1.json"),
            // The prepared, owned, non-symlink scratch base for this host. R07 validates it before
            // any launch and creates only unique mode-0700 children inside it.
            npmScratchBaseURL: workerRoot.appendingPathComponent("native/npm-scratch", isDirectory: true),
            currentDirectory: fixtureRoot.path
        )
    }
    var body: some Scene {
        Window("M10-B isolated acceptance host", id: "fixture") { MainWindow(service: service) }
    }
}
