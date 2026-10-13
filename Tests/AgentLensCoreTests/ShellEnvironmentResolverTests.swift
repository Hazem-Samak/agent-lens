import Darwin
import Foundation
import Testing
@testable import AgentLensCore

private func resolverFixtureRoot() throws -> URL {
    let base = ProcessInfo.processInfo.environment["AGENT_LENS_TEST_SCRATCH"]
        .map { URL(fileURLWithPath: $0, isDirectory: true) }
        ?? FileManager.default.temporaryDirectory
    let root = base.appendingPathComponent("agentlens-resolver-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
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
