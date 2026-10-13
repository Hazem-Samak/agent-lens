import Testing
import Foundation
@testable import AgentLensCore

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

@Test func captureParsesASuccessfulRealShellRun() {
    // End-to-end against a real shell with the production script shape.
    let script = #"printf "\n__AGENTLENS_ENV_BEGIN__\n"; env -0; printf "__AGENTLENS_ENV_END__\n""#
    let outcome = ShellEnvironmentResolver.capture(shellPath: "/bin/sh", script: script)
    #expect(!outcome.timedOut)
    let dump = try? #require(outcome.dump)
    #expect(dump?["PATH"] != nil)
    #expect(dump?["HOME"] != nil)
}
