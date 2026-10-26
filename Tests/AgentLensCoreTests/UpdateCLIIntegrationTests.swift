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
// * Every CLI subprocess launches under /usr/bin/sandbox-exec with a kernel-level denial aimed at
//   the REAL AgentLens cache directory. Measured ON THIS WORKSTATION: Foundation ignores a
//   synthetic HOME (NSHomeDirectory() and cachesDirectory both report the real user), so HOME
//   isolation alone let earlier runs write synthetic metadata into ~/Library/Caches/AgentLens.
//   The denial is applied to the CLI and every child it spawns. A failed cache write is neutral in
//   the production contract, so the supported-CLI status assertions stay meaningful.
// * The fixture PATH no longer appends the real login-shell PATH, and fake OpenCode/Grok sit on
//   it, so the default detectors cannot reach the real ~/.local, ~/.opencode or ~/.grok trees.
// * Each launched process has a bounded watchdog; a hang fails the test instead of wedging the
//   harness.
// * M10-A portability: fixtures run under the inherited TMPDIR with no Agent Lens override. The
//   denial profile names the PHYSICAL pathname (`realpath(3)`), because MEASURED HERE Seatbelt
//   matched physical names and the inherited `/var/folders/.../T/` spelling is an alias of
//   `/private/var/folders/.../T/`. An earlier comment here claimed the Darwin temp tree was
//   unenforceable; that was wrong — the failure was this alias mismatch. Building the profile
//   correctly is configuration, and the decoy control measures mechanism behaviour only at the
//   decoy's own path: neither is a blanket syscall guarantee about the personal cache.

private let sandboxExec = "/usr/bin/sandbox-exec"

/// Wall-clock budget for one sandboxed CLI run. The CLI's own worst case is the 3 s login-shell
/// capture, three 3 s version queries, and three 10 s manager queries; 120 s is generous slack.
private let cliRunBudget: TimeInterval = 120

private func cliScratch(_ label: String) throws -> URL {
    // Fixture roots: the explicit operator override (AGENT_LENS_TEST_SCRATCH), else the runtime's
    // inherited TMPDIR. Never the user's home, and never FileManager.default.temporaryDirectory
    // (measured: that API ignores TMPDIR). With neither set this fails closed rather than
    // relocating fixtures somewhere unauthorized.
    //
    let environment = ProcessInfo.processInfo.environment
    // DISPLAY spelling for callers: production normalizes observed paths via Foundation, and the
    // assertions compare against these strings. The PHYSICAL spelling is a separate value —
    // `ResolvedFixtureRoot.physicalPath`, resolved via `realpath(3)` in CLIFixtureIsolation.swift —
    // and that one is what a sandbox profile must name.
    //
    // Measured ON THIS WORKSTATION: Seatbelt matched the physical pathname, and a profile built from
    // the alias spelling did not deny the physical vnode, because the inherited `/var/folders/.../T/`
    // spelling symlinks to `/private/var/folders/.../T/`. Foundation's `resolvingSymlinksInPath()`
    // did not help here — measured, it returned the un-resolved `/var/...` spelling. That is a local
    // observation, not a universal macOS guarantee.
    return URL(fileURLWithPath: try makeOwnedFixtureRoot(label: label, environment: environment).displayPath)
}

private struct CLIResult {
    let stdout: String
    let stderr: String
    let status: Int32
}

// MARK: Cache isolation via sandbox-exec

/// The REAL AgentLens cache directory, evaluated in the test process where Foundation reports
/// the true user. This mirrors `updateCacheURL()` in Sources/agent-lens/main.swift:54-58 —
/// cachesDirectory + "AgentLens" — because MEASURED HERE a synthetic HOME does not move that
/// resolution, so the CLI aims its cache writes at this exact path. That is an observation on this
/// workstation, not a claim about every macOS configuration.
private func realAgentLensCacheDirectory() throws -> URL {
    guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    else {
        throw NSError(domain: "AgentLensCLI", code: 10,
                      userInfo: [NSLocalizedDescriptionKey: "no user caches directory resolvable"])
    }
    return caches.appendingPathComponent("AgentLens", isDirectory: true)
}

/// Every spelling of the REAL AgentLens cache directory that the kernel may resolve to.
///
/// The denial must name the physical pathname, because Seatbelt matches physical names. The cache
/// leaf usually does not exist, so `physicalPath` resolves the nearest existing ancestor (the
/// user's `Library/Caches`) and re-appends `AgentLens`. The Foundation spelling is retained as
/// well: if the leaf exists and is itself a symlink, either spelling may be the one the kernel
/// compares against.
private func agentLensCacheDenialTargets() throws -> [String] {
    let cacheDirectory = try realAgentLensCacheDirectory()
    var targets = [cacheDirectory.path]
    if let physical = physicalPath(cacheDirectory.path), physical != cacheDirectory.path {
        targets.append(physical)
    }
    return targets
}

/// The full denial profile for the REAL cache: one combined profile denying every known spelling.
private func realCacheDenialProfile() throws -> String {
    denialProfiles(for: try agentLensCacheDenialTargets())
}

/// Builds a SINGLE SBPL profile denying reads, writes and children under every supplied subpath.
/// Deny wins over allow in Seatbelt, so this is a hard kernel-level block for the process and its
/// descendants.
private func denialProfiles(for subpaths: [String]) -> String {
    var clauses = ["(version 1)", "(allow default)"]
    for subpath in subpaths {
        let escaped = subpath
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        clauses.append("(deny file-read* (subpath \"\(escaped)\"))")
        clauses.append("(deny file-write* (subpath \"\(escaped)\"))")
    }
    return clauses.joined(separator: "\n")
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
    label: String,
    budget: TimeInterval = cliRunBudget
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
    if !waitForTermination(process, budget: budget) {
        process.terminate()
        if !waitForTermination(process, budget: 5) {
            kill(process.processIdentifier, SIGKILL)
            _ = waitForTermination(process, budget: 5)
        }
        throw NSError(domain: "AgentLensCLI", code: 12, userInfo: [
            NSLocalizedDescriptionKey: "\(executable) exceeded its \(budget)s watchdog budget",
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
private func runCLI(
    _ arguments: [String],
    home: URL,
    zdotdir: URL,
    budget: TimeInterval = cliRunBudget
) throws -> CLIResult {
    let cli = try builtAgentLensExecutable()
    guard FileManager.default.isExecutableFile(atPath: sandboxExec) else { throw isolationBlocker() }
    let profile = try realCacheDenialProfile()
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
        label: "cli",
        budget: budget
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
    let profile = try realCacheDenialProfile()
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
    #expect(none.stdout.contains("verify-installation"))

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
    #expect(usage.contains("verify-installation <registry-id>"))
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

    // Test-process receipts: these four values are OBSERVED by this process, so parent/runner
    // environment settings cannot be mistaken for what the child saw.
    let environment = ProcessInfo.processInfo.environment
    let overridePresent = !(environment["AGENT_LENS_TEST_SCRATCH"] ?? "").isEmpty
    let inheritedTMPDIR = environment["TMPDIR"] ?? "<unset>"
    let scratch = try cliScratch("isolation")
    let scratchPhysical = physicalPath(scratch.path) ?? "<unresolvable>"
    print("isolation-probe selected_root=\(scratch.path)")
    print("isolation-probe physical_root=\(scratchPhysical)")
    print("isolation-probe scratch_override_present=\(overridePresent)")
    print("isolation-probe inherited_TMPDIR=\(inheritedTMPDIR)")
    // The DISPLAY spelling may be an alias of the physical one (inherited TMPDIR is `/var/...`,
    // physical `/private/var/...`). What must hold is that they name one vnode and the physical
    // spelling is itself stable — profiles use the physical value recorded by the seam.
    #expect(physicalPath(scratch.path) == scratchPhysical, "display and physical spellings must name one vnode")
    #expect(physicalPath(scratchPhysical) == scratchPhysical, "the physical spelling must be stable")

    // The denial target is asserted, never assumed. No syscall is ever issued against the real
    // cache directory — controls use an owned decoy only.
    let cacheDirectory = try realAgentLensCacheDirectory()
    let expectedTarget = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("AgentLens", isDirectory: true)
    #expect(cacheDirectory.path == expectedTarget.path, "the denial target must be exactly the directory main.swift:54-58 computes")

    // Both launch seams install the combined denial for every spelling of that directory.
    let realProfile = try realCacheDenialProfile()
    let targets = try agentLensCacheDenialTargets()
    #expect(targets.contains(cacheDirectory.path), "the Foundation spelling must stay denied")
    for target in targets {
        #expect(realProfile.contains("(deny file-read* (subpath \"\(target)\"))"), "read denial for \(target)")
        #expect(realProfile.contains("(deny file-write* (subpath \"\(target)\"))"), "write denial for \(target)")
    }
    if let physicalCache = physicalPath(cacheDirectory.path), physicalCache != cacheDirectory.path {
        #expect(targets.contains(physicalCache), "the physical cache alias must also be denied")
    }

    // Mechanism control at the measured path. OWNED decoy: the profile denies reads AND writes;
    // the child writes an allowed marker first, so a launch failure or a missing marker can never
    // be mistaken for a denial.
    let decoyRoot = try makeOwnedFixtureRoot(label: "isolation-decoy", environment: environment)
    defer { try? removeOwnedFixtureRoot(decoyRoot, fileManager: fileManager) }
    let decoy = URL(fileURLWithPath: decoyRoot.physicalPath, isDirectory: true)
    let decoyProfile = denialProfile(subpath: decoyRoot.physicalPath)

    let denied = try observeSandboxMechanism(
        root: decoy,
        profile: decoyProfile,
        captureDirectory: scratch,
        label: "denied"
    )
    #expect(denied.executedMarker == "executed",
            "the probe process must demonstrably run before its denied operations are evidence")
    #expect(denied.writeStatus != 0, "denied write must fail at the physical path")
    #expect(denied.readStatus != 0, "denied read must fail at the physical path")
    #expect(denied.readStdout.contains("owned fixture") == false, "denied read must yield no sentinel content")
    #expect(denied.deniedLeafExists == false, "the denied write must not create the leaf")
    // Exact raw payload including the trailing newline: a trimmed comparison would accept a
    // newline-only modification as "unmodified".
    #expect(denied.sentinelBefore == SandboxProbeObservation.expectedSentinelPayload)
    #expect(denied.sentinelAfter == SandboxProbeObservation.expectedSentinelPayload,
            "the sentinel must be byte-identical after a denied write")
    #expect(denied.provesDenial)

    // Unsandboxed positive control: the identical operations SUCCEED, so the refusal above comes
    // from the Seatbelt profile and not from file permissions.
    let controlRoot = try makeOwnedFixtureRoot(label: "isolation-control", environment: environment)
    defer { try? removeOwnedFixtureRoot(controlRoot, fileManager: fileManager) }
    let control = URL(fileURLWithPath: controlRoot.physicalPath, isDirectory: true)
    let allowed = try observeSandboxMechanism(
        root: control,
        profile: decoyProfile,
        sandboxExec: "/bin/sh",
        captureDirectory: scratch,
        label: "allowed"
    )
    #expect(allowed.executedMarker == "executed")
    #expect(allowed.writeStatus == 0, "unsandboxed control write must succeed")
    #expect(allowed.readStatus == 0, "unsandboxed control read must succeed")
    #expect(allowed.readStdout.contains("owned fixture"), "unsandboxed control read must return the sentinel")
    #expect(allowed.deniedLeafExists, "unsandboxed control write must create the leaf")
    #expect(!allowed.provesDenial, "a non-enforcing run must never be reported as a denial")

    // The decoy proves mechanism behaviour ONLY at the decoy's own measured path. It is not a
    // syscall guarantee about the personal cache: the cache path is named in the profile by
    // construction (configuration, not enforcement evidence), and the real cache is never read or
    // written to demonstrate anything.

    // Bounded owned cleanup: only the roots this test created, re-verified, are removed.
    try removeOwnedFixtureRoot(decoyRoot, fileManager: fileManager)
    try removeOwnedFixtureRoot(controlRoot, fileManager: fileManager)
    #expect(!fileManager.fileExists(atPath: decoyRoot.physicalPath))
    #expect(!fileManager.fileExists(atPath: controlRoot.physicalPath))
}

@Test func sandboxedCheckUpdatesPublishesNoReusableCacheAcrossTwoRuns() throws {
    // INDIRECT evidence only. A successful --check-updates run normally persists validated
    // metadata, and a second run would then answer from cache with ZERO manager queries. Both runs
    // here execute the full three-query batch and report fresh-probe provenance, consistent with
    // the cache being unusable. This does NOT by itself prove every cache read and write was
    // prevented: it observes manager-query counts, not cache syscalls. Direct evidence is
    // sandboxDeniesAllAccessToTheRealAgentLensCache plus review of the profile in both launch seams.
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

/// Writes the synthetic login-shell startup for BOTH shell families the production resolver can
/// observe. MEASURED on the hosted runner: its password database selects `/bin/bash`, so a
/// zsh-only fixture left the real login-shell PATH in place and no fixture manager was reachable.
/// Production keeps using `getpwuid`, never `$SHELL`; this fixture simply covers both rc files.
///
/// `.zshrc` runs after the system `/etc/zprofile` `path_helper`; a login bash reads
/// `~/.bash_profile` via `HOME` (the fixture launches `-l -i`). Both payloads are identical
/// POSIX-compatible `export PATH=…`, so
/// either shell exports the same CLOSED PATH — absolute fixture entries plus the resolver's own
/// `/usr/bin:/bin` — and never appends the real login-shell PATH, so no real tool can leak in.
private func writeRC(zdotdir: URL, home: URL, pathEntries: [String]) throws {
    try FileManager.default.createDirectory(at: zdotdir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    let joined = (pathEntries + ["/usr/bin", "/bin"]).map(shellQuote).joined(separator: ":")
    let payload = Data("export PATH=\(joined)\n".utf8)
    try payload.write(to: zdotdir.appendingPathComponent(".zshrc"))
    try payload.write(to: home.appendingPathComponent(".bash_profile"))
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
    try writeRC(zdotdir: zdotdir, home: home, pathEntries: [binDirectory.path])
    return BrewCLIScenario(root: root, home: home, zdotdir: zdotdir, binDirectory: binDirectory, logURL: logURL)
}

// MARK: Explicit ownership verification scenarios

private struct NpmOwnershipCLIScenario {
    let root: URL
    let home: URL
    let zdotdir: URL
    let prefix: URL
    let packageRoot: URL
    let logURL: URL
}

private func writeFakeNpm(in directory: URL, prefix: URL, globalRoot: URL, logURL: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let script = """
    #!/bin/sh
    printf '%s\\n' "$*" >> \(shellQuote(logURL.path))
    case "$*" in
      "prefix --global") printf '%s\\n' \(shellQuote(prefix.path)) ;;
      "root --global") printf '%s\\n' \(shellQuote(globalRoot.path)) ;;
      *) exit 2 ;;
    esac
    """
    let url = directory.appendingPathComponent("npm")
    try Data(script.utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
}

private func makeNpmOwnershipCLIScenario(_ label: String) throws -> NpmOwnershipCLIScenario {
    let root = try cliScratch(label)
    let home = root.appendingPathComponent("home", isDirectory: true)
    let zdotdir = root.appendingPathComponent("zdot", isDirectory: true)
    let prefix = root.appendingPathComponent("prefix", isDirectory: true)
    let globalRoot = prefix.appendingPathComponent("lib/node_modules", isDirectory: true)
    let packageRoot = globalRoot.appendingPathComponent("@openai/codex", isDirectory: true)
    let npmBin = root.appendingPathComponent("npm-bin", isDirectory: true)
    let extraBin = root.appendingPathComponent("extra-bin", isDirectory: true)
    let logURL = root.appendingPathComponent("npm.log")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
        at: packageRoot.appendingPathComponent("bin", isDirectory: true),
        withIntermediateDirectories: true
    )
    try writeFakeTool(
        in: packageRoot.appendingPathComponent("bin", isDirectory: true),
        named: "codex.js", version: "0.1.0"
    )
    let manifest = #"{"name":"@openai/codex","version":"0.1.0","bin":{"codex":"bin/codex.js"}}"#
    try Data(manifest.utf8).write(to: packageRoot.appendingPathComponent("package.json"))

    let prefixBin = prefix.appendingPathComponent("bin", isDirectory: true)
    try FileManager.default.createDirectory(at: prefixBin, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
        atPath: prefixBin.appendingPathComponent("codex").path,
        withDestinationPath: packageRoot.appendingPathComponent("bin/codex.js").path
    )
    try writeFakeNpm(in: npmBin, prefix: prefix, globalRoot: globalRoot, logURL: logURL)
    // Fake standalone tools keep the closed fixture PATH from falling through to real extra roots.
    try writeFakeTool(in: extraBin, named: "opencode", version: "2.0.28")
    try writeFakeTool(in: extraBin, named: "grok", version: "1.0.52")
    try writeRC(zdotdir: zdotdir, home: home, pathEntries: [prefixBin.path, npmBin.path, extraBin.path])
    return NpmOwnershipCLIScenario(
        root: root, home: home, zdotdir: zdotdir, prefix: prefix,
        packageRoot: packageRoot, logURL: logURL
    )
}

private struct FormulaOwnershipCLIScenario {
    let root: URL
    let home: URL
    let zdotdir: URL
    let prefix: URL
    let cellar: URL
    let kegDirectory: URL
    let kegTarget: URL
    let logURL: URL
}

private func makeFormulaOwnershipCLIScenario(_ label: String) throws -> FormulaOwnershipCLIScenario {
    let root = try cliScratch(label)
    let home = root.appendingPathComponent("home", isDirectory: true)
    let zdotdir = root.appendingPathComponent("zdot", isDirectory: true)
    let prefix = root.appendingPathComponent("prefix", isDirectory: true)
    let cellar = prefix.appendingPathComponent("Cellar", isDirectory: true)
    let kegDirectory = cellar.appendingPathComponent("opencode-v2/1.0.0", isDirectory: true)
    let kegTarget = kegDirectory.appendingPathComponent("bin/opencode")
    let logURL = root.appendingPathComponent("brew.log")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    try writeFakeTool(in: kegTarget.deletingLastPathComponent(), named: "opencode", version: "1.2.3")
    let binDirectory = prefix.appendingPathComponent("bin", isDirectory: true)
    try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
        atPath: binDirectory.appendingPathComponent("opencode").path,
        withDestinationPath: kegTarget.path
    )
    let info = #"{"formulae":[{"name":"opencode-v2","full_name":"anomalyco/tap/opencode-v2","tap":"anomalyco/tap","revision":1,"versions":{"stable":"9.9.9","head":null,"bottle":true},"installed":[{"version":"1.0.0","installed_on_request":true}]}],"casks":[]}"#
    let brewScript = """
    #!/bin/sh
    printf '%s\\n' "$*" >> \(shellQuote(logURL.path))
    case "$*" in
      "--cellar") printf '%s\\n' \(shellQuote(cellar.path)) ;;
      "info --json=v2 --formula anomalyco/tap/opencode-v2") printf '%s' \(shellQuote(info)) ;;
      "list --verbose --formula anomalyco/tap/opencode-v2") printf '%s\\n' \(shellQuote(kegTarget.path)) ;;
      *) exit 2 ;;
    esac
    """
    let brewURL = binDirectory.appendingPathComponent("brew")
    try Data(brewScript.utf8).write(to: brewURL)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: brewURL.path)
    try writeRC(zdotdir: zdotdir, home: home, pathEntries: [binDirectory.path])
    return FormulaOwnershipCLIScenario(
        root: root, home: home, zdotdir: zdotdir, prefix: prefix, cellar: cellar,
        kegDirectory: kegDirectory, kegTarget: kegTarget, logURL: logURL
    )
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
    #expect(result.stdout.contains("DETECTOR METADATA"))
    #expect(result.stdout.contains("VERSION / UPDATE STATUS"))
    #expect(result.stdout.range(of: "PATH DIAGNOSTICS")!.lowerBound < result.stdout.range(of: "DETECTOR METADATA")!.lowerBound)
    #expect(result.stdout.range(of: "DETECTOR METADATA")!.lowerBound < result.stdout.range(of: "VERSION / UPDATE STATUS")!.lowerBound)
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
    try writeRC(zdotdir: scenario.zdotdir, home: scenario.home, pathEntries: pathEntries)

    let expectedPrefix = try expectedM5Prefix(pathEntries: pathEntries)
    try Data().write(to: detectorLog)
    let result = try runCLI(["scan", "--check-updates"], home: scenario.home, zdotdir: scenario.zdotdir)

    #expect(result.status == 0)
    #expect(Array(result.stdout.utf8.prefix(expectedPrefix.utf8.count)) == Array(expectedPrefix.utf8))
    #expect(expectedPrefix.contains("same-target alias"))
    #expect(expectedPrefix.contains("shadowed because it appears later in PATH"))
    #expect(expectedPrefix.contains("invalid observed PATH entries:"))
    #expect(expectedPrefix.contains("0.162.1"))
    #expect(readLog(shadowedLog).count == 1,
            "a shadowed canonical installation is queried exactly once for its own version")
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
    let expectedMetadata = DetectorMetadataRenderer.render(
        definitions: try DetectorRegistry.loadDefault()
    )
    let expectedPrefixWithMetadata = expectedPrefix + expectedMetadata
    #expect(running.process.terminationStatus == 0)
    #expect(errorOutput.isEmpty)
    #expect(Array(output.utf8.prefix(expectedPrefix.utf8.count)) == Array(expectedPrefix.utf8))
    #expect(Array(output.utf8.prefix(expectedPrefixWithMetadata.utf8.count))
            == Array(expectedPrefixWithMetadata.utf8))
    #expect(output.components(separatedBy: "VERSION / UPDATE STATUS").count - 1 == 1)
    #expect(output.dropFirst(expectedPrefixWithMetadata.count).hasPrefix("\nVERSION / UPDATE STATUS\n"))
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

@Test func detectorMetadataIsAppendedAfterUnchangedPathReportInEveryScanMode() throws {
    let scenario = try makeBrewCLIScenario("metadata-modes", info: currentInfo, outdated: emptyOutdated)
    let expectedPathPrefix = try expectedM5Prefix(pathEntries: [scenario.binDirectory.path])
    let expectedMetadata = DetectorMetadataRenderer.render(
        definitions: try DetectorRegistry.loadDefault()
    )
    let expectedPrefixWithMetadata = expectedPathPrefix + expectedMetadata
    let modes: [[String]] = [
        ["scan"],
        ["scan", "--offline"],
        ["scan", "--check-updates"],
        ["scan", "--refresh-updates"],
    ]

    for arguments in modes {
        let result = try runCLI(arguments, home: scenario.home, zdotdir: scenario.zdotdir)
        #expect(result.status == 0, "\(arguments)")
        #expect(result.stderr.isEmpty, "\(arguments)")
        #expect(Array(result.stdout.utf8.prefix(expectedPathPrefix.utf8.count))
                == Array(expectedPathPrefix.utf8), "\(arguments)")
        #expect(Array(result.stdout.utf8.prefix(expectedPrefixWithMetadata.utf8.count))
                == Array(expectedPrefixWithMetadata.utf8), "\(arguments)")
        let metadataRange = try #require(result.stdout.range(of: "DETECTOR METADATA"))
        let versionRange = try #require(result.stdout.range(of: "VERSION / UPDATE STATUS"))
        #expect(metadataRange.lowerBound < versionRange.lowerBound, "\(arguments)")
        #expect(result.stdout.contains("Codex  category: AI Agent"), "\(arguments)")
        #expect(result.stdout.contains("declared package: npm @openai/codex (declaration only)"), "\(arguments)")
        #expect(result.stdout.contains("declared package: Homebrew cask codex (declaration only)"), "\(arguments)")
        #expect(result.stdout.contains("Grok CLI  category: AI Agent"), "\(arguments)")
        #expect(result.stdout.contains("declared packages: none"), "\(arguments)")
        #expect(result.stdout.contains("official information: https://docs.x.ai/build/overview"), "\(arguments)")
        #expect(result.stdout.contains("uninstall instructions: https://opencode.ai/v2/docs/cli/#uninstall"), "\(arguments)")
    }

    // Plain and offline make zero manager calls; check and refresh each make one batch.
    #expect(readLog(scenario.logURL).count == 6)
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
        selection: .winner(winnerCandidate), shadowedInstallationCount: 1,
        installationVersions: []
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
        selection: .offPath(candidate: offPathCandidate, root: offPathRoot), shadowedInstallationCount: 0,
        installationVersions: []
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

// MARK: verify-installation through the real CLI

@Test func verifyInstallationNpmPrintsLocalDeclaredFactsThenExactReadOnlyProof() throws {
    let scenario = try makeNpmOwnershipCLIScenario("npm-verify")
    let result = try runCLI(
        ["verify-installation", "codex"], home: scenario.home, zdotdir: scenario.zdotdir
    )

    #expect(result.status == 0)
    #expect(result.stderr.isEmpty)
    // Exactly the two documented read-only npm queries, in order, with no update or cache step.
    #expect(readLog(scenario.logURL) == ["prefix --global", "root --global"])

    // The named definition's local and declared facts precede the ownership section; the other
    // registry entries are not scanned merely because verification was requested.
    let pathRange = try #require(result.stdout.range(of: "PATH DIAGNOSTICS"))
    let metadataRange = try #require(result.stdout.range(of: "DETECTOR METADATA"))
    let ownershipRange = try #require(result.stdout.range(of: "OWNERSHIP VERIFICATION"))
    #expect(pathRange.lowerBound < metadataRange.lowerBound)
    #expect(metadataRange.lowerBound < ownershipRange.lowerBound)
    #expect(result.stdout.contains("Codex          0.1.0    npm"))
    #expect(result.stdout.contains("declared package: npm @openai/codex (declaration only)"))
    #expect(!result.stdout.contains("OpenCode"))
    #expect(!result.stdout.contains("Grok CLI"))
    #expect(!result.stdout.contains("VERSION / UPDATE STATUS"))

    // Verified identity is carried from manager output and manifest inspection, not the label.
    #expect(result.stdout.contains("  result: verified"))
    #expect(result.stdout.contains("  manager: npm"))
    #expect(result.stdout.contains("  package: @openai/codex"))
    #expect(result.stdout.contains("  manager executable: \(scenario.root.appendingPathComponent("npm-bin/npm").path)"))
    #expect(result.stdout.contains("  manager root: \(scenario.prefix.path)"))
    #expect(result.stdout.contains("  installation root: \(scenario.packageRoot.path)"))
    #expect(result.stdout.contains("  selected entry: \(scenario.prefix.appendingPathComponent("bin/codex").path)"))
    #expect(result.stdout.contains(
        "  selected target: \(scenario.packageRoot.appendingPathComponent("bin/codex.js").path)"
    ))

    // The timestamp is the observation time, and every result states its read-only character.
    let timestampLine = try #require(
        result.stdout.split(separator: "\n").first { $0.hasPrefix("  observed at: ") }
    )
    let timestampText = String(timestampLine.dropFirst("  observed at: ".count))
    #expect(ISO8601DateFormatter().date(from: timestampText) != nil)
    #expect(result.stdout.contains(
        "  note: read-only verification from this invocation; no installation changes were made"
    ))
}

@Test func verifyInstallationFIFOManifestSettlesWithinTheSubprocessWatchdog() throws {
    let scenario = try makeNpmOwnershipCLIScenario("npm-fifo-verify")
    let manifest = scenario.packageRoot.appendingPathComponent("package.json")
    try FileManager.default.removeItem(at: manifest)
    let created = manifest.path.withCString { mkfifo($0, 0o600) }
    #expect(created == 0)
    guard created == 0 else { return }

    // A blocking descriptor open on this FIFO has no writer and never returns. The subprocess
    // watchdog turns that regression into a bounded test failure instead of wedging the suite.
    let result = try runCLI(
        ["verify-installation", "codex"],
        home: scenario.home,
        zdotdir: scenario.zdotdir,
        budget: 20
    )

    #expect(result.status == 0)
    #expect(result.stderr.isEmpty)
    #expect(result.stdout.contains("  result: unknown"))
    #expect(result.stdout.contains("  reason: The package manifest could not be read"))
    #expect(readLog(scenario.logURL) == ["prefix --global", "root --global"])
}

@Test func verifyInstallationHomebrewFormulaUsesCellarInfoListAndIgnoresStableVersion() throws {
    let scenario = try makeFormulaOwnershipCLIScenario("brew-formula-verify")
    let result = try runCLI(
        ["verify-installation", "opencode"], home: scenario.home, zdotdir: scenario.zdotdir
    )

    #expect(result.status == 0)
    #expect(result.stderr.isEmpty)
    // Exactly `--cellar`, named `info --json=v2 --formula`, and named `list --verbose --formula`.
    // `--installed` is deliberately absent, and no update check or cache path is exercised.
    #expect(readLog(scenario.logURL) == [
        "--cellar",
        "info --json=v2 --formula anomalyco/tap/opencode-v2",
        "list --verbose --formula anomalyco/tap/opencode-v2",
    ])
    #expect(result.stdout.contains("  result: verified"))
    #expect(result.stdout.contains("  manager: Homebrew formula"))
    #expect(result.stdout.contains("  package: anomalyco/tap/opencode-v2"))
    #expect(result.stdout.contains("  manager root: \(scenario.cellar.path)"))
    #expect(result.stdout.contains("  installation root: \(scenario.kegDirectory.path)"))
    #expect(result.stdout.contains(
        "  selected entry: \(scenario.prefix.appendingPathComponent("bin/opencode").path)"
    ))
    #expect(result.stdout.contains("  selected target: \(scenario.kegTarget.path)"))
    #expect(!result.stdout.contains("VERSION / UPDATE STATUS"))
    // The fixture's upstream `stable` is 9.9.9 while the selected keg is 1.0.0. Ownership must
    // never borrow that version or compare against it.
    #expect(!result.stdout.contains("9.9.9"))
}

@Test func verifyInstallationCaskIsNeutralWithZeroManagerQueries() throws {
    let scenario = try makeBrewCLIScenario(
        "brew-cask-verify", info: currentInfo, outdated: emptyOutdated
    )
    let result = try runCLI(
        ["verify-installation", "codex"], home: scenario.home, zdotdir: scenario.zdotdir
    )

    #expect(result.status == 0)
    #expect(result.stderr.isEmpty)
    #expect(result.stdout.contains("  result: unknown"))
    #expect(result.stdout.contains("  reason: Homebrew cask ownership is not supported"))
    #expect(result.stdout.contains("  selected entry: \(scenario.binDirectory.appendingPathComponent("codex").path)"))
    #expect(result.stdout.contains("no installation changes were made"))
    #expect(readLog(scenario.logURL).isEmpty, "cask verification must not query Homebrew")
}

@Test func verifyInstallationStandaloneIsNeutralWithZeroManagerQueries() throws {
    let scenario = try makeNpmOwnershipCLIScenario("npm-standalone-verify")
    let result = try runCLI(
        ["verify-installation", "grok"], home: scenario.home, zdotdir: scenario.zdotdir
    )

    #expect(result.status == 0)
    #expect(result.stderr.isEmpty)
    #expect(result.stdout.contains("  registry id: grok"))
    #expect(result.stdout.contains("  result: unknown"))
    #expect(result.stdout.contains(
        "  reason: The detected installation source is not supported for ownership verification"
    ))
    #expect(!result.stdout.contains("  manager:"))
    #expect(!result.stdout.contains("VERSION / UPDATE STATUS"))
    #expect(readLog(scenario.logURL).isEmpty, "standalone verification must not query npm")
}

@Test func verifyInstallationInvalidAndUnknownFormsExitOneWithoutManagerEffects() throws {
    let scenario = try makeNpmOwnershipCLIScenario("npm-invalid-verify")
    let cases: [[String]] = [
        ["verify-installation"],
        ["verify-installation", "codex", "extra"],
        ["verify-installation", "codex", "--check-updates"],
    ]
    for arguments in cases {
        let result = try runCLI(arguments, home: scenario.home, zdotdir: scenario.zdotdir)
        #expect(result.status == 1, "expected exit 1 for \(arguments)")
        #expect(result.stdout.isEmpty, "no partial report for \(arguments)")
        #expect(result.stderr.contains("usage: agent-lens"), "expected usage for \(arguments)")
    }

    let unknown = try runCLI(
        ["verify-installation", "not-a-registry-id"], home: scenario.home, zdotdir: scenario.zdotdir
    )
    #expect(unknown.status == 1)
    #expect(unknown.stdout.isEmpty)
    #expect(unknown.stderr.contains("unknown registry id 'not-a-registry-id'"))
    #expect(!unknown.stderr.contains("usage: agent-lens"))
    #expect(readLog(scenario.logURL).isEmpty, "invalid forms must not contact npm")
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
// MARK: Login-shell fixture portability (zsh and bash)

/// Proves OBSERVED, from a real process in both supported shell families, that the fixture rc
/// payload yields the exact CLOSED fixture PATH. The hosted runner's password database selects
/// `/bin/bash`, so a zsh-only fixture silently kept the real login-shell PATH; this control runs
/// the same owned HOME/ZDOTDIR pair under `/bin/zsh` and `/bin/bash` with login + interactive
/// flags and reads back the exported `PATH` the shell itself reports.
///
/// The invariant is EXACT stdout equality with the expected printf payload. A prefix or substring
/// match would accept the closed fixture PATH with an inherited suffix appended, which is exactly
/// the defect this control exists to catch.
///
/// No production override and no `$SHELL` mutation: both shells are invoked directly, the fixture
/// writes the same payload to both rc locations, and the children run under the standard cache
/// denial profile. Only `PATH` text crosses the boundary — no tool discovery and no manager calls.
@Test func loginShellFixtureExportsTheExactClosedPathForBothZshAndBash() throws {
    let fileManager = FileManager.default
    guard fileManager.isExecutableFile(atPath: sandboxExec) else { throw isolationBlocker() }
    let root = try cliScratch("login-shell-portability")
    let home = root.appendingPathComponent("home", isDirectory: true)
    let zdotdir = root.appendingPathComponent("zdot", isDirectory: true)
    let fixtureBin = root.appendingPathComponent("fixture-bin", isDirectory: true)
    try fileManager.createDirectory(at: fixtureBin, withIntermediateDirectories: true)
    try writeRC(zdotdir: zdotdir, home: home, pathEntries: [fixtureBin.path])

    // The fixture entry is first, then the resolver's own /usr/bin:/bin requirement.
    let expected = ([fixtureBin.path] + ["/usr/bin", "/bin"]).joined(separator: ":")
    // printf emits the PATH followed by exactly one newline; nothing else may reach stdout.
    let expectedStdout = expected + "\n"

    let profile = try realCacheDenialProfile()
    for shell in ["/bin/zsh", "/bin/bash"] {
        guard fileManager.isExecutableFile(atPath: shell) else { throw isolationBlocker() }
        let result = try runCaptured(
            executable: sandboxExec,
            arguments: ["-p", profile, shell, "-l", "-i", "-c", "/usr/bin/printf '%s\\n' \"$PATH\""],
            environment: ["HOME": home.path, "ZDOTDIR": zdotdir.path, "PATH": "/usr/bin:/bin"],
            captureDirectory: home,
            label: "login-shell-\((shell as NSString).lastPathComponent)",
            budget: cliRunBudget
        )
        // An interactive shell may print its own banner ("no job control") on stderr, so stderr is
        // deliberately NOT asserted empty. Exit status and the exact exported PATH are the evidence.
        #expect(result.status == 0, "\(shell) exited \(result.status): \(result.stderr)")
        #expect(result.stdout == expectedStdout,
                "\(shell) stdout was not the exact closed fixture PATH; stdout: \(result.stdout), stderr: \(result.stderr)")
    }
}
