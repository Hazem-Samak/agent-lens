import Darwin
import Foundation
import Testing
@testable import AgentLensCore

private func resolverFixtureRoot() throws -> URL {
    let environment = ProcessInfo.processInfo.environment
    guard let basePath = [environment["AGENT_LENS_TEST_SCRATCH"], environment["TMPDIR"]]
        .compactMap({ $0 })
        .first(where: { !$0.isEmpty })
    else {
        throw NSError(domain: "AgentLensTests", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "no approved test scratch root is available"])
    }
    let base = URL(fileURLWithPath: basePath, isDirectory: true).resolvingSymlinksInPath()
    let root = base.appendingPathComponent("agentlens-resolver-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root.resolvingSymlinksInPath()
}

// M2 tests. From here on the tests are the only mechanism that distinguishes
// working code from plausible-looking code (D-012, M1 brief "why the test matters").

@Test func parseEnvironmentDumpExtractsSentinelDelimitedPairs() throws {
    var data = Data("\n\(ShellEnvironmentResolver.beginMarker)\n".utf8)
    data.append(Data("MULTILINE=hello\nworld".utf8))
    data.append(Data([0]))                       // NUL delimiter
    data.append(Data("PATH=/bin:/usr/bin".utf8))
    data.append(Data([0]))                       // NUL delimiter
    data.append(Data("\(ShellEnvironmentResolver.endMarker)\n".utf8))

    let dump = try #require(ShellEnvironmentResolver.parseEnvironmentDump(data))
    #expect(dump["MULTILINE"] == "hello\nworld")  // value containing a newline survives
    #expect(dump["PATH"] == "/bin:/usr/bin")      // value containing "=" survives
}

@Test func parseEnvironmentDumpReturnsNilWithoutSentinels() {
    let data = Data("just some banner text, no markers".utf8)
    #expect(ShellEnvironmentResolver.parseEnvironmentDump(data) == nil)
}

@Test func buildEnvironmentIsDegradedOnTimeoutAndUsesFallbackPath() {
    let outcome = ShellEnvironmentResolver.CaptureOutcome(dump: nil, timedOut: true)
    let environment = ShellEnvironmentResolver.buildEnvironment(
        shellPath: "/bin/zsh", outcome: outcome
    )
    #expect(environment.isDegraded)
    #expect(environment.pathJoined == ShellEnvironmentResolver.fallbackPath)
    #expect(environment.pathEntries == ShellEnvironmentResolver.fallbackPath.split(separator: ":").map(String.init))
    #expect(environment.raw["PATH"] == ShellEnvironmentResolver.fallbackPath)
}

@Test func buildEnvironmentIsDegradedWhenDumpHasNoPath() {
    let outcome = ShellEnvironmentResolver.CaptureOutcome(
        dump: ["HOME": "/Users/someone"], timedOut: false
    )
    let environment = ShellEnvironmentResolver.buildEnvironment(
        shellPath: "/bin/zsh", outcome: outcome
    )
    #expect(environment.isDegraded)
    #expect(environment.pathJoined == ShellEnvironmentResolver.fallbackPath)
}

@Test func buildEnvironmentPassesRawEnvironmentThroughForProcess() {
    let outcome = ShellEnvironmentResolver.CaptureOutcome(
        dump: ["HOME": "/Users/someone", "PATH": "/a:/b", "MULTILINE": "one\ntwo"],
        timedOut: false
    )
    let environment = ShellEnvironmentResolver.buildEnvironment(
        shellPath: "/bin/zsh", outcome: outcome
    )
    #expect(!environment.isDegraded)
    // The raw environment is usable directly in Process.environment:
    #expect(environment.raw["HOME"] == "/Users/someone")
    #expect(environment.raw["PATH"] == "/a:/b")
    #expect(environment.raw["MULTILINE"] == "one\ntwo")
    #expect(environment.pathEntries == ["/a", "/b"])
    #expect(environment.pathJoined == "/a:/b")
}

@Test func buildEnvironmentPreservesLeadingTrailingAndInternalEmptyPATHComponents() {
    let path = ":/first::/second:"
    let environment = ShellEnvironmentResolver.buildEnvironment(
        shellPath: "/bin/sh",
        outcome: ShellEnvironmentResolver.CaptureOutcome(
            dump: ["PATH": path], timedOut: false
        )
    )

    #expect(!environment.isDegraded)
    #expect(environment.pathJoined == path)
    #expect(environment.raw["PATH"] == path)
    #expect(environment.pathEntries == ["", "/first", "", "/second", ""])
}

@Test func captureTimesOutAgainstAHangingShell() {
    // A script that never finishes must trip the timeout, not hang (M2 req. 3).
    let outcome = ShellEnvironmentResolver.capture(
        shellPath: "/bin/sh",
        script: "sleep 30",
        timeout: 0.5
    )
    #expect(outcome.timedOut)
    #expect(outcome.dump == nil)
}

@Test func captureKillsTerminationResistantProcessAfterEarlyStdoutEOF() throws {
    let root = try resolverFixtureRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let pidFile = root.appendingPathComponent("child.pid")
    let script = "printf '%s' \"$$\" > '\(pidFile.path)'; exec 1>&-; trap '' TERM; exec /bin/sleep 2"

    let started = DispatchTime.now().uptimeNanoseconds
    let outcome = ShellEnvironmentResolver.capture(
        shellPath: "/bin/sh",
        script: script,
        timeout: 0.1
    )
    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000
    let pidText = try String(contentsOf: pidFile, encoding: .utf8)
    let pid = try #require(pid_t(pidText))
    defer {
        if kill(pid, 0) == 0 { _ = kill(pid, SIGKILL) }
    }

    #expect(outcome.timedOut)
    #expect(outcome.dump == nil)
    #expect(elapsed >= 0.08 && elapsed < 0.5, "elapsed: \(elapsed)")
    #expect(kill(pid, 0) == -1)
}

@Test func captureDiscardsLargeStderrWithoutBlocking() {
    let script = "i=0; while [ \"$i\" -lt 4096 ]; do printf '................................' >&2; i=$((i + 1)); done; \(ShellEnvironmentResolver.defaultCaptureScript)"
    let outcome = ShellEnvironmentResolver.capture(
        shellPath: "/bin/sh",
        script: script,
        timeout: 1
    )

    #expect(!outcome.timedOut)
    #expect(outcome.dump?["PATH"] != nil)
}

@Test func captureParsesASuccessfulRealShellRun() {
    // End-to-end against a real shell with the production script shape.
    let script = #"printf "\n__AGENTLENS_ENV_BEGIN__\n"; env -0; printf "__AGENTLENS_ENV_END__\n""#
    let outcome = ShellEnvironmentResolver.capture(shellPath: "/bin/sh", script: script)
    #expect(!outcome.timedOut)
    let dump = try? #require(outcome.dump)
    #expect(dump?["PATH"] != nil)
    #expect(dump?["HOME"] != nil)
}

@Test func captureRejectsSentinelsFromANonzeroShellExit() {
    let outcome = ShellEnvironmentResolver.capture(
        shellPath: "/bin/sh",
        script: "\(ShellEnvironmentResolver.defaultCaptureScript); exit 7",
        timeout: 2
    )

    #expect(!outcome.timedOut)
    let dumpWasRejected = outcome.dump == nil
    #expect(dumpWasRejected, "capture accepted sentinels from a failed shell")
    let environment = ShellEnvironmentResolver.buildEnvironment(
        shellPath: "/bin/sh", outcome: outcome
    )
    let environmentIsDegraded = environment.isDegraded
    #expect(environmentIsDegraded, "failed shell capture must use degraded fallback")
}

// MARK: Terminal-context production-seam regression

private struct BoundedFixtureProcessResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

private func waitForFixtureProcess(_ process: Process, budget: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(budget)
    while process.isRunning {
        if Date() >= deadline { return false }
        Thread.sleep(forTimeInterval: 0.02)
    }
    return true
}

/// Runs a bounded fixture process with file capture. This deliberately uses `/usr/bin/script`
/// from the regression below to give the child a controlling terminal without forking inside the
/// Swift test process.
private func runBoundedFixtureProcess(
    executable: String,
    arguments: [String],
    environment: [String: String]?,
    captureDirectory: URL,
    label: String,
    budget: TimeInterval
) throws -> BoundedFixtureProcessResult {
    let stdoutURL = captureDirectory.appendingPathComponent("stdout-\(label)-\(UUID().uuidString).txt")
    let stderrURL = captureDirectory.appendingPathComponent("stderr-\(label)-\(UUID().uuidString).txt")
    FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
    FileManager.default.createFile(atPath: stderrURL.path, contents: nil)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    if let environment { process.environment = environment }
    process.currentDirectoryURL = captureDirectory
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
    if !waitForFixtureProcess(process, budget: budget) {
        process.terminate()
        if !waitForFixtureProcess(process, budget: 2) {
            _ = kill(process.processIdentifier, SIGKILL)
            _ = waitForFixtureProcess(process, budget: 2)
        }
        throw NSError(domain: "AgentLensResolverTests", code: 20, userInfo: [
            NSLocalizedDescriptionKey: "\(executable) exceeded its \(budget)s watchdog",
        ])
    }
    process.waitUntilExit()

    return BoundedFixtureProcessResult(
        status: process.terminationStatus,
        stdout: String(decoding: try Data(contentsOf: stdoutURL), as: UTF8.self),
        stderr: String(decoding: try Data(contentsOf: stderrURL), as: UTF8.self)
    )
}

/// Proves the production `capture` seam is safe when the CLI itself is launched from a terminal.
/// `/usr/bin/script` supplies the controlling terminal; the helper calls the real resolver rather
/// than reproducing shell launch flags in the test. It must observe the exact closed fixture PATH
/// for both supported login-shell families, without terminal job-control interaction.
@Test func ptyProductionCaptureUsesFixturePathForSupportedLoginShells() throws {
    let root = try resolverFixtureRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let home = root.appendingPathComponent("home", isDirectory: true)
    let zdot = root.appendingPathComponent("zdot", isDirectory: true)
    let bin = root.appendingPathComponent("fixture-bin", isDirectory: true)
    for directory in [home, zdot, bin] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    let expectedPath = ([bin.path] + ["/usr/bin", "/bin"]).joined(separator: ":")
    let payload = Data("export PATH='\(expectedPath)'\n".utf8)
    try payload.write(to: zdot.appendingPathComponent(".zshrc"))
    try payload.write(to: home.appendingPathComponent(".bash_profile"))

    let source = root.appendingPathComponent("pty-capture-probe.swift")
    let helper = root.appendingPathComponent("pty-capture-probe")
    let helperSource = #"""
    import AgentLensCore
    import Darwin

    let shell = CommandLine.arguments[1]
    let outcome = ShellEnvironmentResolver.capture(shellPath: shell)
    let environment = ShellEnvironmentResolver.buildEnvironment(shellPath: shell, outcome: outcome)
    print("tty=\(isatty(0))")
    print("degraded=\(environment.isDegraded)")
    print("path=\(environment.pathJoined)")
    """#
    try Data(helperSource.utf8).write(to: source)

    let products = try agentLensCoreProducts()
    let compile = try runBoundedFixtureProcess(
        executable: "/usr/bin/swiftc",
        arguments: agentLensCoreCompileArguments(for: products) + [source.path, "-o", helper.path],
        environment: nil,
        captureDirectory: root,
        label: "pty-capture-compile",
        budget: 60
    )
    #expect(compile.status == 0, "PTY helper compilation failed: \(compile.stderr)")
    guard compile.status == 0 else { return }

    for shell in ["/bin/zsh", "/bin/bash"] {
        let shellName = (shell as NSString).lastPathComponent
        let result = try runBoundedFixtureProcess(
            executable: "/usr/bin/script",
            arguments: ["-q", "/dev/null", helper.path, shell],
            environment: ["HOME": home.path, "ZDOTDIR": zdot.path, "PATH": "/usr/bin:/bin"],
            captureDirectory: root,
            label: "pty-capture-\(shellName)",
            budget: 15
        )
        #expect(result.status == 0, "\(shell) PTY helper exited \(result.status): \(result.stderr)")
        let normalized = result.stdout
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(lines.contains(where: { $0.hasSuffix("tty=1") }),
                "\(shell) did not observe a controlling terminal: \(result.stdout)")
        #expect(lines.contains("degraded=false"),
                "\(shell) capture degraded in PTY: \(result.stdout)")
        #expect(lines.contains("path=\(expectedPath)"),
                "\(shell) fixture PATH missing or not an exact line: \(result.stdout)")
    }
}
