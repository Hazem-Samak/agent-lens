import Darwin
import Foundation
import Testing
@testable import AgentLensCore

// M6 step 5 — the built `agent-lens` executable, observed through stdout/stderr/exit status.
// A synthetic login shell (ZDOTDIR rc fixture) supplies a CLOSED PATH of absolute fixture
// entries, and fake tools sit in scratch space. No production test-only override exists; no
// real manager state is touched.
//
// Stage-1 corrections:
// * AGENT_LENS_TEST_PRODUCTS is OPTIONAL. Without it the CLI is discovered next to the actual
//   running test products (symlinks resolved), never through the shared `.build` link. An
//   override that does not name a regular executable `agent-lens` fails loudly — it never
//   silently falls back to an unrelated executable.
// * Every CLI subprocess launches under /usr/bin/sandbox-exec with a kernel-level denial of the
//   REAL AgentLens cache directory. On this Mac Foundation ignores a synthetic HOME
//   (NSHomeDirectory() and cachesDirectory both report the real user), so HOME isolation alone
//   let earlier runs write synthetic metadata into ~/Library/Caches/AgentLens. The denial covers
//   the CLI and every child it spawns. A failed cache write is neutral in the production
//   contract, so the supported-CLI status assertions stay meaningful.
// * The fixture PATH no longer appends the real login-shell PATH, and fake OpenCode/Grok sit on
//   it, so the default detectors cannot reach the real ~/.local, ~/.opencode or ~/.grok trees.
// * Each launched process has a bounded watchdog; a hang fails the test instead of wedging the
//   harness.

private let sandboxExec = "/usr/bin/sandbox-exec"

/// Wall-clock budget for one sandboxed CLI run. The CLI's own worst case is the 3 s login-shell
/// capture, three 3 s version queries, and three 10 s manager queries; 120 s is generous slack.
private let cliRunBudget: TimeInterval = 120

private func cliScratch(_ label: String) throws -> URL {
    // Fixture roots: the explicit operator override (AGENT_LENS_TEST_SCRATCH), else the runtime's
    // temporary-directory root (TMPDIR). Never the user's home, and never
    // FileManager.default.temporaryDirectory: measured on this Mac, that API resolves to the
    // per-user /var/folders/.../T tree REGARDLESS of TMPDIR, and a Seatbelt subpath denial there
    // does NOT hold (the sandboxed decoy write succeeded with exit 0). So the darwin temp root is
    // both outside authorized storage and unenforceable. With neither override set and no TMPDIR,
    // this fails closed rather than relocating fixtures somewhere unauthorized.
    let environment = ProcessInfo.processInfo.environment
    let base: URL
    if let override = environment["AGENT_LENS_TEST_SCRATCH"], !override.isEmpty {
        base = URL(fileURLWithPath: override, isDirectory: true)
    } else if let tmpdir = environment["TMPDIR"], !tmpdir.isEmpty {
        base = URL(fileURLWithPath: tmpdir, isDirectory: true)
    } else {
        throw scratchBlocker()
    }
    // Canonicalize against symlinks BEFORE the path is used in a Seatbelt profile or compared in a
    // test: the kernel matches the resolved vnode path, not the symlinked spelling.
    let root = base.resolvingSymlinksInPath()
        .appendingPathComponent("agentlens-m6-cli-\(label)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root.resolvingSymlinksInPath()
}

private struct CLIResult {
    let stdout: String
    let stderr: String
    let status: Int32
}

// MARK: Cache isolation via sandbox-exec

/// The REAL AgentLens cache directory, evaluated in the test process where Foundation reports
/// the true user. This mirrors `updateCacheURL()` in Sources/agent-lens/main.swift:54-58 —
/// cachesDirectory + "AgentLens" — because a synthetic HOME does NOT move that resolution on
/// this platform, and the CLI therefore aims its cache writes at this exact path.
private func realAgentLensCacheDirectory() throws -> URL {
    guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    else {
        throw NSError(domain: "AgentLensCLI", code: 10,
                      userInfo: [NSLocalizedDescriptionKey: "no user caches directory resolvable"])
    }
    return caches.appendingPathComponent("AgentLens", isDirectory: true)
}

/// An SBPL profile that allows everything EXCEPT all reads and writes under `subpath`. Deny wins
/// over allow in Seatbelt, so this is a hard kernel-level block for the process and its children.
private func denialProfile(subpath: String) -> String {
    let escaped = subpath
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    return """
    (version 1)
    (allow default)
    (deny file-read* (subpath "\(escaped)"))
    (deny file-write* (subpath "\(escaped)"))
    """
}

private func isolationBlocker() -> NSError {
    NSError(domain: "AgentLensCLI", code: 11, userInfo: [
        NSLocalizedDescriptionKey:
        "\(sandboxExec) unavailable — refusing to run cache-writing CLI tests unsandboxed. "
        + "This is a blocker for the parent, not a reason to relax isolation.",
    ])
}

/// No AGENT_LENS_TEST_SCRATCH override and no TMPDIR: there is no authorized root to place
/// fixtures in. Fail closed rather than writing into the user's home or the unenforceable
/// per-user darwin temp tree.
private func scratchBlocker() -> NSError {
    NSError(domain: "AgentLensCLI", code: 13, userInfo: [
        NSLocalizedDescriptionKey:
        "no scratch root available — set AGENT_LENS_TEST_SCRATCH or TMPDIR to a writable "
        + "directory the operator authorizes for test fixtures. Refusing to relocate outside "
        + "authorized storage.",
    ])
}

// MARK: Process launching (bounded, captured to scratch files)

private func waitForTermination(_ process: Process, budget: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(budget)
    while process.isRunning {
        if Date() >= deadline { return false }
        Thread.sleep(forTimeInterval: 0.02)
    }
    return true
}

/// Launches one process with an explicit synthetic environment, capturing stdout/stderr to
/// scratch files (the proven M3 isolated-PATH pattern — no pipe lifetime shared with the
/// harness) and enforcing a bounded watchdog so a hang fails loudly instead of wedging tests.
private func runCaptured(
    executable: String,
    arguments: [String],
    environment: [String: String],
    captureDirectory: URL,
    label: String
) throws -> CLIResult {
    let stdoutURL = captureDirectory.appendingPathComponent("stdout-\(label)-\(UUID().uuidString).txt")
    let stderrURL = captureDirectory.appendingPathComponent("stderr-\(label)-\(UUID().uuidString).txt")
    FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
    FileManager.default.createFile(atPath: stderrURL.path, contents: nil)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.environment = environment
    process.standardInput = FileHandle.nullDevice
    let outHandle = try FileHandle(forWritingTo: stdoutURL)
    let errHandle = try FileHandle(forWritingTo: stderrURL)
    process.standardOutput = outHandle
    process.standardError = errHandle
    defer {
        try? outHandle.close()
        try? errHandle.close()
    }

    try process.run()
    if !waitForTermination(process, budget: cliRunBudget) {
        process.terminate()
        if !waitForTermination(process, budget: 5) {
            kill(process.processIdentifier, SIGKILL)
            _ = waitForTermination(process, budget: 5)
        }
        throw NSError(domain: "AgentLensCLI", code: 12, userInfo: [
            NSLocalizedDescriptionKey: "\(executable) exceeded its \(cliRunBudget)s watchdog budget",
        ])
    }
    process.waitUntilExit()

    return CLIResult(
        stdout: String(decoding: try Data(contentsOf: stdoutURL), as: UTF8.self),
        stderr: String(decoding: try Data(contentsOf: stderrURL), as: UTF8.self),
        status: process.terminationStatus
    )
}

/// Runs the built executable under the cache-denial sandbox with an isolated HOME and ZDOTDIR.
/// This is the ONLY launch seam for the CLI, so every CLI test inherits the isolation.
private func runCLI(_ arguments: [String], home: URL, zdotdir: URL) throws -> CLIResult {
    let cli = try builtAgentLensExecutable()
    guard FileManager.default.isExecutableFile(atPath: sandboxExec) else { throw isolationBlocker() }
    let profile = denialProfile(subpath: try realAgentLensCacheDirectory().path)
    // Synthetic environment only — the real environment is never merged in.
    let environment: [String: String] = [
        "HOME": home.path,
        "ZDOTDIR": zdotdir.path,
        "PATH": "/usr/bin:/bin",
    ]
    return try runCaptured(
        executable: sandboxExec,
        arguments: ["-p", profile, cli] + arguments,
        environment: environment,
        captureDirectory: home,
        label: "cli"
    )
}

private struct RunningCLI {
    let process: Process
    let stdoutURL: URL
    let stderrURL: URL
    let stdoutHandle: FileHandle
    let stderrHandle: FileHandle
}

private func launchCLIWithFileCapture(
    _ arguments: [String],
    home: URL,
    zdotdir: URL
) throws -> RunningCLI {
    let cli = try builtAgentLensExecutable()
    guard FileManager.default.isExecutableFile(atPath: sandboxExec) else { throw isolationBlocker() }
    let profile = denialProfile(subpath: try realAgentLensCacheDirectory().path)
    let stdoutURL = home.appendingPathComponent("live-stdout-\(UUID().uuidString).log")
    let stderrURL = home.appendingPathComponent("live-stderr-\(UUID().uuidString).log")
    FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
    FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
    let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
    let stderrHandle = try FileHandle(forWritingTo: stderrURL)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: sandboxExec)
    process.arguments = ["-p", profile, cli] + arguments
    process.environment = ["HOME": home.path, "ZDOTDIR": zdotdir.path, "PATH": "/usr/bin:/bin"]
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = stdoutHandle
    process.standardError = stderrHandle
    do {
        try process.run()
    } catch {
        try? stdoutHandle.close()
        try? stderrHandle.close()
        throw error
    }
    return RunningCLI(
        process: process, stdoutURL: stdoutURL, stderrURL: stderrURL,
        stdoutHandle: stdoutHandle, stderrHandle: stderrHandle
    )
}

private func waitForFile(_ url: URL, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if FileManager.default.fileExists(atPath: url.path) { return true }
        Thread.sleep(forTimeInterval: 0.01)
    }
    return FileManager.default.fileExists(atPath: url.path)
}

private func waitForCapturedPrefix(_ url: URL, prefix: String, timeout: TimeInterval) -> String? {
    let expected = Data(prefix.utf8)
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if let data = try? Data(contentsOf: url), data.starts(with: expected) {
            return String(decoding: data, as: UTF8.self)
        }
        Thread.sleep(forTimeInterval: 0.01)
    }
    guard let data = try? Data(contentsOf: url), data.starts(with: expected) else { return nil }
    return String(decoding: data, as: UTF8.self)
}

// MARK: Product discovery

private func isRegularExecutable(_ url: URL) -> Bool {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return false }
    guard (attributes[.type] as? FileAttributeType) == .typeRegular else { return false }
    return FileManager.default.isExecutableFile(atPath: url.path)
}

/// Locates the `agent-lens` product belonging to THIS test run.
///
/// With `AGENT_LENS_TEST_PRODUCTS` set it is validated (a real executable must live there) and
/// used; an invalid override fails loudly rather than silently running an unrelated binary.
/// Without it, discovery recovers the products directory from the SwiftPM testing helper's own
/// argv. Measured: `Bundle.main` is the HELPER's bundle (`/Library/.../usr/libexec/swift/pm`), so
/// walking up from it or from `executableURL` can never reach a product; but `--test-bundle-path`
/// names this test binary inside `<products>/AgentLensCoreTests.xctest`, and the same path is
/// repeated as the final positional argument. Walking up from there finds the sibling
/// `agent-lens` product, symlinks resolved, so a stale shared `.build/debug` link from a different
/// build system can never be followed.
private func builtAgentLensExecutable() throws -> String {
    if let override = ProcessInfo.processInfo.environment["AGENT_LENS_TEST_PRODUCTS"], !override.isEmpty {
        let candidate = URL(fileURLWithPath: override, isDirectory: true)
            .appendingPathComponent("agent-lens")
        guard isRegularExecutable(candidate) else {
            throw NSError(domain: "AgentLensCLI", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "AGENT_LENS_TEST_PRODUCTS names no regular executable agent-lens at \(candidate.path)"])
        }
        return candidate.path
    }
    // Recover the products directory from the testing helper's argv (see the doc comment above).
    var starts: [URL] = []
    let argv = CommandLine.arguments
    if let index = argv.firstIndex(of: "--test-bundle-path"), index + 1 < argv.count {
        starts.append(URL(fileURLWithPath: argv[index + 1]))
    }
    if let last = argv.last, last.contains(".xctest") {
        starts.append(URL(fileURLWithPath: last))
    }
    for start in starts {
        var directory = start.resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<5 {
            let candidate = directory.appendingPathComponent("agent-lens")
            if isRegularExecutable(candidate) { return candidate.path }
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path { break }
            directory = parent
        }
    }
    throw NSError(domain: "AgentLensCLI", code: 1, userInfo: [
        NSLocalizedDescriptionKey:
        "could not discover agent-lens from the testing helper argv (\(argv)); "
        + "set AGENT_LENS_TEST_PRODUCTS to the products directory",
    ])
}

// MARK: Argument grammar (exact forms; no network or manager contact for syntax failures)

@Test func cliRejectsCombinedAndRepeatedScanFlagsWithUsageOnStderr() throws {
    let scenario = try makeBrewCLIScenario("syntax-invalid", info: currentInfo, outdated: emptyOutdated)
    let cases: [[String]] = [
        ["scan", "--check-updates", "--check-updates"],
        ["scan", "--refresh-updates", "--refresh-updates"],
        ["scan", "--offline", "--offline"],
        ["scan", "--check-updates", "--refresh-updates"],
        ["scan", "--check-updates", "--offline"],
        ["scan", "--refresh-updates", "--offline"],
        ["debug-env", "--check-updates"],
        ["debug-env", "--refresh-updates"],
        ["debug-env", "--offline"],
        ["debug-env", "extra-operand"],
        ["scan", "extra-operand"],
        ["scan", "--unknown-flag"],
    ]
    for arguments in cases {
        let result = try runCLI(arguments, home: scenario.home, zdotdir: scenario.zdotdir)
        #expect(result.status == 1, "expected exit 1 for \(arguments)")
        #expect(result.stdout.isEmpty, "usage must not appear on stdout for \(arguments)")
        #expect(result.stderr.contains("usage: agent-lens"), "expected usage on stderr for \(arguments)")
    }
    #expect(readLog(scenario.logURL).isEmpty, "syntax errors must not contact Homebrew")
}

@Test func cliNoArgumentsAndUnknownCommandKeepTheirExitStatuses() throws {
    let home = try cliScratch("legacy-home")
    let zdot = try cliScratch("legacy-zdot")
    let none = try runCLI([], home: home, zdotdir: zdot)
    #expect(none.status == 0)
    #expect(none.stdout.hasPrefix("usage: agent-lens <scan"))
    #expect(none.stdout.contains("debug-env"))

    let unknown = try runCLI(["unknown-command"], home: home, zdotdir: zdot)
    #expect(unknown.status == 1)
    #expect(unknown.stderr.contains("usage: agent-lens"))
}

// MARK: Usage contract

@Test func usageStringDocumentsTheExactScanModes() {
    let usage = WalkingSkeleton.usageMessage
    #expect(usage.contains("scan"))
    #expect(usage.contains("--check-updates"))
    #expect(usage.contains("--refresh-updates"))
    #expect(usage.contains("--offline"))
    #expect(usage.contains("debug-env"))
}

@Test func validDebugEnvironmentCommandUsesTheFixturePathWithoutManagerProbes() throws {
    let scenario = try makeBrewCLIScenario("debug-env-valid", info: currentInfo, outdated: emptyOutdated)
    let result = try runCLI(["debug-env"], home: scenario.home, zdotdir: scenario.zdotdir)

    #expect(result.status == 0)
    #expect(result.stderr.isEmpty)
    #expect(result.stdout.contains("path_joined:"))
    #expect(result.stdout.contains(scenario.binDirectory.path))
    #expect(readLog(scenario.logURL).isEmpty)
}

// MARK: Real-cache isolation proof

@Test func sandboxDeniesAllAccessToTheRealAgentLensCache() throws {
    let fileManager = FileManager.default
    guard fileManager.isExecutableFile(atPath: sandboxExec) else { throw isolationBlocker() }
    let cacheDirectory = try realAgentLensCacheDirectory()
    let scratch = try cliScratch("isolation")

    // The denial target is asserted, never assumed. No syscall is issued against the real cache
    // directory at any point in this file — the parent's ledger hash covers its contents.
    let expectedTarget = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("AgentLens", isDirectory: true)
    #expect(cacheDirectory.path == expectedTarget.path, "the denial target must be exactly the directory main.swift:54-58 computes")
    let profile = denialProfile(subpath: cacheDirectory.path)
    #expect(profile.contains("(deny file-read* (subpath \"\(cacheDirectory.path)\"))"))
    #expect(profile.contains("(deny file-write* (subpath \"\(cacheDirectory.path)\"))"))

    // Mechanism control on a scratch decoy: the identical profile shape refuses, and the identical
    // command WITHOUT the sandbox succeeds. The refusal therefore comes from the Seatbelt profile,
    // not from file permissions — so the denial every CLI run installs is a genuine kernel-level
    // guarantee for the path asserted above.
    let decoy = try cliScratch("isolation-decoy")
    let decoyTarget = decoy.appendingPathComponent("probe")
    let decoyProfile = denialProfile(subpath: decoy.path)
    let refused = try runCaptured(
        executable: sandboxExec,
        arguments: ["-p", decoyProfile, "/bin/sh", "-c", "touch \"$1\"", "_", decoyTarget.path],
        environment: ["PATH": "/usr/bin:/bin"],
        captureDirectory: scratch,
        label: "decoy-refused"
    )
    #expect(refused.status != 0)
    #expect(fileManager.fileExists(atPath: decoyTarget.path) == false)

    let allowed = try runCaptured(
        executable: "/bin/sh",
        arguments: ["-c", "touch \"$1\"", "_", decoyTarget.path],
        environment: ["PATH": "/usr/bin:/bin"],
        captureDirectory: scratch,
        label: "decoy-allowed"
    )
    #expect(allowed.status == 0, "unsandboxed control write must succeed, proving the denial is the sandbox")
    #expect(fileManager.fileExists(atPath: decoyTarget.path))
}

@Test func sandboxedCheckUpdatesPublishesNoReusableCacheAcrossTwoRuns() throws {
    // Behavioural proof of the denial using fixture state only. A successful --check-updates run
    // normally persists validated metadata, and a second run would then answer from cache with
    // ZERO manager queries. Because the real cache directory is denied for reads AND writes, both
    // runs must execute the full three-query batch and both must report fresh-probe provenance.
    // A failed cache write is neutral in the production contract, so the meaningful upToDate
    // result still stands on every attempt.
    let s = try makeBrewCLIScenario("brew-nocache", info: currentInfo, outdated: emptyOutdated)
    for attempt in 1...2 {
        let result = try runCLI(["scan", "--check-updates"], home: s.home, zdotdir: s.zdotdir)
        #expect(result.status == 0, "attempt \(attempt)")
        #expect(result.stdout.contains("Codex  installed 0.162.1  latest known 0.162.1_1  up to date"), "attempt \(attempt)")
        #expect(result.stdout.contains("source: Homebrew metadata; checked at"),
                "attempt \(attempt) must be a fresh probe, never a cache hit")
    }
    let calls = readLog(s.logURL)
    #expect(calls.count == 6, "two uncached runs must each execute the three-query batch; got \(calls)")
}

// MARK: End-to-end synthetic Homebrew through the built CLI

/// Quotes a value for single-quoted shell embedding, so scratch paths containing spaces or
/// other metacharacters survive intact.
private func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

/// Writes a fake `brew` that logs each argument vector and answers the three M6 queries from
/// fixtures. Its log is the only evidence of manager activity, so query counts are observable.
/// The log lives strictly inside the scenario's scratch root.
private func writeFakeBrew(in binDirectory: URL, cellar: URL, logURL: URL, infoJSON: String, outdatedJSON: String) throws {
    try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
    let script = """
    #!/bin/sh
    printf '%s\\n' "$*" >> \(shellQuote(logURL.path))
    case "$1" in
      --cellar) printf '%s\\n' \(shellQuote(cellar.path)) ;;
      info) printf '%s' \(shellQuote(infoJSON)) ;;
      outdated) printf '%s' \(shellQuote(outdatedJSON)) ;;
      *) exit 2 ;;
    esac
    """
    let url = binDirectory.appendingPathComponent("brew")
    try Data(script.utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
}

/// Writes the synthetic login-shell startup. `.zshrc` runs after the system `/etc/zprofile`
/// `path_helper`, so these entries win. The PATH is CLOSED — absolute fixture entries plus the
/// resolver's own `/usr/bin:/bin` requirement — and never appends the real login-shell PATH, so
/// no real tool can leak into a fixture run.
private func writeRC(zdotdir: URL, pathEntries: [String]) throws {
    try FileManager.default.createDirectory(at: zdotdir, withIntermediateDirectories: true)
    let joined = (pathEntries + ["/usr/bin", "/bin"]).map(shellQuote).joined(separator: ":")
    try Data("export PATH=\(joined)\n".utf8).write(to: zdotdir.appendingPathComponent(".zshrc"))
}

private func expectedM5Prefix(pathEntries: [String], isDegraded: Bool = false) throws -> String {
    let completePath = pathEntries + ["/usr/bin", "/bin"]
    let joined = completePath.joined(separator: ":")
    let environment = ShellEnvironment(
        shellPath: "/bin/zsh",
        pathEntries: completePath,
        pathJoined: joined,
        raw: ["PATH": joined],
        isDegraded: isDegraded
    )
    let reports = try DetectorRegistry.loadDefault().map { definition in
        PathDiagnosticsScanner.scan(detector: definition.makeDetector(), environment: environment)
    }
    return DiagnosticsScanRenderer.render(reports: reports, isDegraded: isDegraded)
}

private func writeFakeTool(in directory: URL, named name: String, version: String) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(name)
    let script = "#!/bin/sh\nif [ \"$1\" = \"--version\" ]; then echo \(shellQuote("\(name) \(version)")); fi\n"
    try Data(script.utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
}

private func readLog(_ url: URL) -> [String] {
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
    return text.split(separator: "\n").map(String.init)
}

/// A synthetic Homebrew install of Codex 0.162.1_1 in a fake Cellar, with a PATH symlink.
private struct BrewCLIScenario {
    let root: URL
    let home: URL
    let zdotdir: URL
    let binDirectory: URL
    let logURL: URL
}

private func makeBrewCLIScenario(_ label: String, info: String, outdated: String) throws -> BrewCLIScenario {
    let root = try cliScratch(label)
    let home = root.appendingPathComponent("home", isDirectory: true)
    let zdotdir = root.appendingPathComponent("zdot", isDirectory: true)
    let prefix = root.appendingPathComponent("prefix", isDirectory: true)
    let cellar = prefix.appendingPathComponent("Cellar", isDirectory: true)
    let binDirectory = prefix.appendingPathComponent("bin", isDirectory: true)
    let logURL = root.appendingPathComponent("brew.log")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)

    // The real keg: Cellar/codex/0.162.1_1/bin/codex, a fake CLI reporting 0.162.1.
    let keg = cellar.appendingPathComponent("codex/0.162.1_1/bin", isDirectory: true)
    try writeFakeTool(in: keg, named: "codex", version: "0.162.1")
    try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
        atPath: binDirectory.appendingPathComponent("codex").path,
        withDestinationPath: keg.appendingPathComponent("codex").path
    )
    try writeFakeBrew(in: binDirectory, cellar: cellar, logURL: logURL, infoJSON: info, outdatedJSON: outdated)

    // Fake OpenCode and Grok on the fixture PATH. Without them the default detectors fall
    // through to the REAL extra roots (~/.opencode/bin, ~/.grok/bin, ~/.local/bin) — Foundation
    // resolves ~ to the real user even with a synthetic HOME — and would execute real tools.
    try writeFakeTool(in: binDirectory, named: "opencode", version: "2.0.28")
    try writeFakeTool(in: binDirectory, named: "grok", version: "1.0.52")

    // The login shell sees ONLY the fake brew/codex/opencode/grok PATH.
    try writeRC(zdotdir: zdotdir, pathEntries: [binDirectory.path])
    return BrewCLIScenario(root: root, home: home, zdotdir: zdotdir, binDirectory: binDirectory, logURL: logURL)
}

private let currentInfo = #"{"formulae":[{"name":"codex","full_name":"codex","tap":"homebrew/core","revision":1,"versions":{"stable":"0.162.1","head":null,"bottle":true},"installed":[{"version":"0.162.1_1","installed_on_request":true}]}],"casks":[]}"#
private let emptyOutdated = #"{"formulae":[],"casks":[]}"#

@Test func checkUpdatesThroughRealCLIReportsSupportedBrewCurrentWithThreeQueries() throws {
    let s = try makeBrewCLIScenario("brew-current", info: currentInfo, outdated: emptyOutdated)
    let result = try runCLI(["scan", "--check-updates"], home: s.home, zdotdir: s.zdotdir)
    let expectedPrefix = try expectedM5Prefix(pathEntries: [s.binDirectory.path])

    #expect(result.status == 0)
    // The M5 report is the unchanged prefix and the update section is appended after it.
    #expect(result.stdout.contains("PATH DIAGNOSTICS"))
    #expect(result.stdout.contains("VERSION / UPDATE STATUS"))
    #expect(result.stdout.range(of: "PATH DIAGNOSTICS")!.lowerBound < result.stdout.range(of: "VERSION / UPDATE STATUS")!.lowerBound)
    #expect(Array(result.stdout.utf8.prefix(expectedPrefix.utf8.count)) == Array(expectedPrefix.utf8))
    #expect(expectedPrefix.contains("0.162.1"), "the unchanged local report must retain its useful version")
    #expect(result.stdout.contains("Codex  installed 0.162.1  latest known 0.162.1_1  up to date"))
    #expect(result.stdout.contains("0 updates available"))
    // Exactly three manager commands for the single eligible formula. The cache write this mode
    // attempts targets the real AgentLens directory and is denied by the sandbox — a neutral
    // outcome per the production contract, so the fresh-probe status above must still stand.
    let calls = readLog(s.logURL)
    #expect(calls.count == 3)
    #expect(calls.first == "--cellar")
}

@Test func refreshThroughRealCLIIsAValidScanModeAndRunsOneBoundedBatch() throws {
    let scenario = try makeBrewCLIScenario("brew-refresh", info: currentInfo, outdated: emptyOutdated)
    let result = try runCLI(["scan", "--refresh-updates"], home: scenario.home, zdotdir: scenario.zdotdir)

    #expect(result.status == 0)
    #expect(result.stderr.isEmpty)
    #expect(result.stdout.contains("Codex  installed 0.162.1  latest known 0.162.1_1  up to date"))
    #expect(result.stdout.contains("0 updates available"))
    #expect(readLog(scenario.logURL).count == 3)
}

@Test func realCLIAppendsAfterTheExactM5WinnerAliasShadowedAndInvalidPrefix() throws {
    let scenario = try makeBrewCLIScenario("brew-m5-prefix", info: currentInfo, outdated: emptyOutdated)
    let detectorLog = scenario.root.appendingPathComponent("detector-invocations.log")
    for (tool, version) in [("codex", "0.162.1"), ("opencode", "2.0.28"), ("grok", "1.0.52")] {
        let target = scenario.binDirectory.appendingPathComponent(tool).resolvingSymlinksInPath()
        let script = """
        #!/bin/sh
        printf '%s\\n' '\(tool)' >> \(shellQuote(detectorLog.path))
        printf '%s\\n' '\(tool) \(version)'
        """
        try Data(script.utf8).write(to: target)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
    }
    let aliasRoot = scenario.root.appendingPathComponent("alias", isDirectory: true)
    let shadowedRoot = scenario.root.appendingPathComponent("shadowed", isDirectory: true)
    let invalidRoot = scenario.root.appendingPathComponent("invalid", isDirectory: true)
    for directory in [aliasRoot, shadowedRoot, invalidRoot] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    let alias = aliasRoot.appendingPathComponent("codex")
    try FileManager.default.createSymbolicLink(
        atPath: alias.path,
        withDestinationPath: scenario.binDirectory.appendingPathComponent("codex").path
    )
    let shadowedLog = scenario.root.appendingPathComponent("shadowed-execution.log")
    let shadowed = shadowedRoot.appendingPathComponent("codex")
    let shadowedScript = "#!/bin/sh\nprintf x >> \(shellQuote(shadowedLog.path))\nprintf 'codex 9.9.9\\n'\n"
    try Data(shadowedScript.utf8).write(to: shadowed)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shadowed.path)
    let broken = invalidRoot.appendingPathComponent("codex")
    try FileManager.default.createSymbolicLink(
        atPath: broken.path,
        withDestinationPath: scenario.root.appendingPathComponent("missing-codex").path
    )
    let pathEntries = [scenario.binDirectory.path, aliasRoot.path, shadowedRoot.path, invalidRoot.path]
    try writeRC(zdotdir: scenario.zdotdir, pathEntries: pathEntries)

    let expectedPrefix = try expectedM5Prefix(pathEntries: pathEntries)
    try Data().write(to: detectorLog)
    let result = try runCLI(["scan", "--check-updates"], home: scenario.home, zdotdir: scenario.zdotdir)

    #expect(result.status == 0)
    #expect(Array(result.stdout.utf8.prefix(expectedPrefix.utf8.count)) == Array(expectedPrefix.utf8))
    #expect(expectedPrefix.contains("same-target alias"))
    #expect(expectedPrefix.contains("shadowed because it appears later in PATH"))
    #expect(expectedPrefix.contains("invalid observed PATH entries:"))
    #expect(expectedPrefix.contains("0.162.1"))
    #expect(FileManager.default.fileExists(atPath: shadowedLog.path) == false,
            "shadowed executables must remain unqueried")
    #expect(readLog(scenario.logURL).count == 3)
    let detectorCalls = readLog(detectorLog)
    #expect(detectorCalls.count == 3)
    #expect(Set(detectorCalls) == Set(["codex", "opencode", "grok"]))
}

@Test func delayedManagerLeavesFlushedM5InventoryVisibleBeforeOneAppendedUpdateSection() throws {
    let scenario = try makeBrewCLIScenario("brew-delayed-prefix", info: currentInfo, outdated: emptyOutdated)
    let startedMarker = scenario.root.appendingPathComponent("brew-started")
    let releaseMarker = scenario.root.appendingPathComponent("brew-release")
    let cellar = scenario.root.appendingPathComponent("prefix/Cellar", isDirectory: true)
    let controlledBrew = """
    #!/bin/sh
    printf '%s\\n' "$*" >> \(shellQuote(scenario.logURL.path))
    case "$1" in
      --cellar)
        printf ready > \(shellQuote(startedMarker.path))
        while [ ! -f \(shellQuote(releaseMarker.path)) ]; do /bin/sleep 0.01; done
        printf '%s\\n' \(shellQuote(cellar.path))
        ;;
      info) printf '%s' \(shellQuote(currentInfo)) ;;
      outdated) printf '%s' \(shellQuote(emptyOutdated)) ;;
      *) exit 2 ;;
    esac
    """
    let brewURL = scenario.binDirectory.appendingPathComponent("brew")
    try Data(controlledBrew.utf8).write(to: brewURL)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: brewURL.path)
    let expectedPrefix = try expectedM5Prefix(pathEntries: [scenario.binDirectory.path])
    let running = try launchCLIWithFileCapture(
        ["scan", "--check-updates"], home: scenario.home, zdotdir: scenario.zdotdir
    )
    var released = false
    defer {
        if !released { try? Data("release".utf8).write(to: releaseMarker) }
        if running.process.isRunning {
            if !waitForTermination(running.process, budget: 5) {
                _ = kill(running.process.processIdentifier, SIGKILL)
                _ = waitForTermination(running.process, budget: 2)
            }
        }
        try? running.stdoutHandle.close()
        try? running.stderrHandle.close()
    }

    let managerStarted = waitForFile(startedMarker, timeout: 20)
    #expect(managerStarted, "the fake manager must reach its explicit wait before release")
    let visibleBeforeRelease = waitForCapturedPrefix(
        running.stdoutURL, prefix: expectedPrefix, timeout: 20
    )
    #expect(visibleBeforeRelease != nil, "the local M5 report must be flushed while brew is still waiting")
    if let visibleBeforeRelease {
        #expect(!visibleBeforeRelease.contains("VERSION / UPDATE STATUS"))
        #expect(visibleBeforeRelease.components(separatedBy: "VERSION / UPDATE STATUS").count - 1 == 0)
    }
    #expect(running.process.isRunning, "the CLI must still be alive before the manager is released")

    try Data("release".utf8).write(to: releaseMarker)
    released = true
    let completed = waitForTermination(running.process, budget: cliRunBudget)
    #expect(completed, "the released CLI must finish within its watchdog")
    if !completed {
        running.process.terminate()
        _ = waitForTermination(running.process, budget: 2)
        if running.process.isRunning { _ = kill(running.process.processIdentifier, SIGKILL) }
    }
    running.process.waitUntilExit()
    try running.stdoutHandle.close()
    try running.stderrHandle.close()

    let output = String(decoding: try Data(contentsOf: running.stdoutURL), as: UTF8.self)
    let errorOutput = String(decoding: try Data(contentsOf: running.stderrURL), as: UTF8.self)
    #expect(running.process.terminationStatus == 0)
    #expect(errorOutput.isEmpty)
    #expect(Array(output.utf8.prefix(expectedPrefix.utf8.count)) == Array(expectedPrefix.utf8))
    #expect(output.components(separatedBy: "VERSION / UPDATE STATUS").count - 1 == 1)
    #expect(output.dropFirst(expectedPrefix.count).hasPrefix("\nVERSION / UPDATE STATUS\n"))
    #expect(output.contains("0 updates available\n"))
    #expect(readLog(scenario.logURL).count == 3)
}

@Test func checkUpdatesThroughRealCLIReportsUpdateAvailableAndCountsIt() throws {
    let outdated = #"{"formulae":[{"name":"codex","installed_versions":["0.162.1_1"],"current_version":"0.162.1_2","pinned":false}],"casks":[]}"#
    let info = #"{"formulae":[{"name":"codex","full_name":"codex","tap":"homebrew/core","revision":2,"versions":{"stable":"0.162.1","head":null,"bottle":true},"installed":[{"version":"0.162.1_1"}]}],"casks":[]}"#
    let s = try makeBrewCLIScenario("brew-update", info: info, outdated: outdated)
    let result = try runCLI(["scan", "--check-updates"], home: s.home, zdotdir: s.zdotdir)

    #expect(result.status == 0)
    #expect(result.stdout.contains("Codex  installed 0.162.1  latest known 0.162.1_2  update available"))
    #expect(result.stdout.contains("1 update available"))
}

@Test func offlineThroughRealCLIMakesZeroManagerCalls() throws {
    let s = try makeBrewCLIScenario("brew-offline", info: currentInfo, outdated: emptyOutdated)
    let result = try runCLI(["scan", "--offline"], home: s.home, zdotdir: s.zdotdir)

    #expect(result.status == 0)
    #expect(readLog(s.logURL).isEmpty)
    #expect(result.stdout.contains("unknown — offline mode was requested"))
    #expect(result.stdout.contains("0 updates available"))
    // The old assertion checked <scratch HOME>/Library/Caches — meaningless on this Mac, where
    // Foundation ignores the synthetic HOME. Real-cache isolation is proved by
    // sandboxDeniesAllAccessToTheRealAgentLensCache, and every runCLI goes through that denial.
}

@Test func plainScanMakesZeroManagerCallsAndReportsNotChecked() throws {
    let s = try makeBrewCLIScenario("brew-plain", info: currentInfo, outdated: emptyOutdated)
    let result = try runCLI(["scan"], home: s.home, zdotdir: s.zdotdir)

    #expect(result.status == 0)
    #expect(readLog(s.logURL).isEmpty)
    #expect(result.stdout.contains("unknown — update check not requested"))
}

@Test func syntheticOffPathDegradedM5ReportRemainsTheExactBytePrefix() throws {
    let root = try cliScratch("synthetic-m5-prefix")
    let winnerPath = root.appendingPathComponent("bin/codex").path
    let winnerTarget = root.appendingPathComponent("Cellar/codex/0.162.1_1/bin/codex").path
    let aliasPath = root.appendingPathComponent("alias/codex").path
    let shadowedPath = root.appendingPathComponent("shadowed/codex").path
    let shadowedTarget = root.appendingPathComponent("other/codex").path
    let invalidPath = root.appendingPathComponent("invalid/codex").path
    let offPathEntry = root.appendingPathComponent("known-extra/opencode").path
    let offPathRoot = root.appendingPathComponent("known-extra").path
    let winnerTool = DetectedTool(
        displayName: "Codex", executableName: "codex", state: .installedAndOnPath,
        entryPath: winnerPath, resolvedPath: winnerTarget, source: "brew", version: "0.162.1"
    )
    let winnerCandidate = PathCandidateObservation(
        origin: .path(slotIndex: 0, directoryText: root.appendingPathComponent("bin").path),
        entryPath: winnerPath, kind: .executableSymlink, canonicalTarget: winnerTarget
    )
    let aliasCandidate = PathCandidateObservation(
        origin: .path(slotIndex: 1, directoryText: root.appendingPathComponent("alias").path),
        entryPath: aliasPath, kind: .executableSymlink, canonicalTarget: winnerTarget
    )
    let shadowedCandidate = PathCandidateObservation(
        origin: .path(slotIndex: 2, directoryText: root.appendingPathComponent("shadowed").path),
        entryPath: shadowedPath, kind: .executableFile, canonicalTarget: shadowedTarget
    )
    let invalidCandidate = PathCandidateObservation(
        origin: .path(slotIndex: 3, directoryText: root.appendingPathComponent("invalid").path),
        entryPath: invalidPath, kind: .brokenSymlink, canonicalTarget: nil
    )
    let winnerReport = ToolPathDiagnostic(
        detectedTool: winnerTool,
        pathCandidates: [winnerCandidate, aliasCandidate, shadowedCandidate, invalidCandidate],
        firstLiveCandidate: winnerCandidate,
        targetGroups: [
            PathTargetGroup(canonicalTarget: winnerTarget, entryPaths: [winnerPath, aliasPath], firstSlotIndex: 0),
            PathTargetGroup(canonicalTarget: shadowedTarget, entryPaths: [shadowedPath], firstSlotIndex: 2),
        ],
        repeatedPathSlotCount: 0, sameTargetAliasCount: 1,
        selection: .winner(winnerCandidate), shadowedInstallationCount: 1
    )
    let offPathTool = DetectedTool(
        displayName: "OpenCode", executableName: "opencode", state: .installedNotOnPath,
        entryPath: offPathEntry, resolvedPath: offPathEntry, source: "standalone", version: "2.0.28"
    )
    let offPathCandidate = PathCandidateObservation(
        origin: .extraRoot(index: 0, directoryText: offPathRoot),
        entryPath: offPathEntry, kind: .executableFile, canonicalTarget: offPathEntry
    )
    let offPathReport = ToolPathDiagnostic(
        detectedTool: offPathTool, pathCandidates: [], firstLiveCandidate: nil, targetGroups: [],
        repeatedPathSlotCount: 0, sameTargetAliasCount: 0,
        selection: .offPath(candidate: offPathCandidate, root: offPathRoot), shadowedInstallationCount: 0
    )
    let prefix = DiagnosticsScanRenderer.render(reports: [winnerReport, offPathReport], isDegraded: true)
    let observedAt = Date(timeIntervalSince1970: 0)
    let results = [
        ToolUpdateResult(
            registryID: "codex", displayName: "Codex", diagnosticIndex: 0,
            diagnostic: winnerReport, localVersion: "0.162.1",
            selectedEntryPath: winnerPath, selectedTarget: winnerTarget, selectedKegVersion: "0.162.1_1",
            managerEntryPath: nil, managerTarget: nil, managerFingerprint: nil, managerCellar: nil,
            formulaStem: nil, fullFormulaName: nil,
            status: .updateAvailable(installed: Version("0.162.1"), latest: Version("0.162.1_2")),
            provenance: .freshProbe(observedAt: observedAt)
        ),
        ToolUpdateResult(
            registryID: "opencode", displayName: "OpenCode", diagnosticIndex: 1,
            diagnostic: offPathReport, localVersion: "2.0.28",
            selectedEntryPath: offPathEntry, selectedTarget: offPathEntry, selectedKegVersion: nil,
            managerEntryPath: nil, managerTarget: nil, managerFingerprint: nil, managerCellar: nil,
            formulaStem: nil, fullFormulaName: nil,
            status: .unknown(installed: Version("2.0.28"), reason: .noRegistry), provenance: .none
        ),
    ]
    let complete = prefix + UpdateScanRenderer.render(results: results, mode: .checkUpdates)

    #expect(Array(complete.utf8.prefix(prefix.utf8.count)) == Array(prefix.utf8))
    #expect(prefix.contains("WARNING: The login shell could not be captured"))
    #expect(prefix.contains("same-target alias"))
    #expect(prefix.contains("shadowed because it appears later in PATH"))
    #expect(prefix.contains("invalid observed PATH entries:"))
    #expect(prefix.contains("known extra root (off PATH; not a shell winner)"))
    #expect(prefix.contains("0.162.1"))
    #expect(complete.dropFirst(prefix.count).hasPrefix("\nVERSION / UPDATE STATUS\n"))
}

@Test func probeFailureIsAResultValueAndScanStillExitsZero() throws {
    let failing = try makeBrewCLIScenario("brew-fail", info: currentInfo, outdated: emptyOutdated)
    // Break the Cellar query by replacing the fake brew with one that exits nonzero.
    let brew = failing.binDirectory.appendingPathComponent("brew")
    let script = "#!/bin/sh\necho x >> \(shellQuote(failing.logURL.path))\nexit 3\n"
    try Data(script.utf8).write(to: brew)
    let result = try runCLI(["scan", "--refresh-updates"], home: failing.home, zdotdir: failing.zdotdir)

    #expect(result.status == 0)
    #expect(result.stdout.contains("VERSION / UPDATE STATUS"))
    #expect(result.stdout.contains("0.162.1"))
    #expect(result.stdout.contains("unknown — update probe failed"))
}