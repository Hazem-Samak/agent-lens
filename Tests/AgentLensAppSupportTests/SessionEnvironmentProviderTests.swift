// SessionEnvironmentProviderTests — M7 stage 2: session reuse, explicit fresh rescan, and the
// no-PATH/no-$SHELL/raw-environment invariants (D-005, M2 requirement 7).
//
// The provider never launches a login shell here: every Core seam is a recording fake. Environment
// assertions are boolean or whitelisted-field only — a captured environment dictionary is never
// printed or interpolated.

import AgentLensCore
import Foundation
import Testing
@testable import AgentLensAppSupport

// MARK: Login-shell seams

/// Recording, scripted login-shell seams. Every call is counted, so the test can prove which seam
/// production code used: a missing count means the request never reached the injected core
/// functions (for example, an inherited main-actor `Task` reading `ProcessInfo` instead).
final class RecordingEnvironmentSource: @unchecked Sendable {
    private let lock = NSLock()
    private var resolveCount = 0
    private var loginShellPathCount = 0
    private var captureCount = 0
    private var buildCount = 0
    private var capturedShellPaths: [String] = []
    private var buildShellPaths: [String] = []

    /// The environment `resolve()` returns (the first, session-wide resolution).
    let resolveEnvironment: ShellEnvironment
    /// The environment a fresh capture produces.
    let capturedEnvironment: ShellEnvironment
    /// The login shell the password database reports. nil models an unavailable pw_shell entry.
    let loginShell: String?

    init(
        resolveEnvironment: ShellEnvironment,
        capturedEnvironment: ShellEnvironment? = nil,
        loginShell: String? = "/bin/zsh"
    ) {
        self.resolveEnvironment = resolveEnvironment
        self.capturedEnvironment = capturedEnvironment ?? resolveEnvironment
        self.loginShell = loginShell
    }

    var counts: (resolve: Int, loginShellPath: Int, capture: Int, build: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (resolveCount, loginShellPathCount, captureCount, buildCount)
    }

    var shellsCaptured: [String] {
        lock.lock()
        defer { lock.unlock() }
        return capturedShellPaths
    }

    var shellsBuilt: [String] {
        lock.lock()
        defer { lock.unlock() }
        return buildShellPaths
    }

    var source: SessionEnvironmentSource {
        SessionEnvironmentSource(
            resolve: {
                self.lock.lock()
                self.resolveCount += 1
                self.lock.unlock()
                return self.resolveEnvironment
            },
            loginShellPath: {
                self.lock.lock()
                self.loginShellPathCount += 1
                self.lock.unlock()
                return self.loginShell
            },
            capture: { shellPath in
                self.lock.lock()
                self.captureCount += 1
                self.capturedShellPaths.append(shellPath)
                self.lock.unlock()
                return ShellEnvironmentResolver.CaptureOutcome(
                    dump: self.capturedEnvironment.raw,
                    timedOut: false
                )
            },
            build: { shellPath, outcome in
                self.lock.lock()
                self.buildCount += 1
                self.buildShellPaths.append(shellPath)
                self.lock.unlock()
                _ = outcome
                return self.capturedEnvironment
            }
        )
    }

    var provider: SessionEnvironmentProvider { SessionEnvironmentProvider(source: source) }
}

private func syntheticEnvironment(
    shellPath: String = "/bin/zsh",
    pathEntries: [String],
    isDegraded: Bool = false,
    extraRaw: [String: String] = [:]
) -> ShellEnvironment {
    var raw: [String: String] = ["PATH": pathEntries.joined(separator: ":")]
    for (key, value) in extraRaw { raw[key] = value }
    return ShellEnvironment(
        shellPath: shellPath,
        pathEntries: pathEntries,
        pathJoined: pathEntries.joined(separator: ":"),
        raw: raw,
        isDegraded: isDegraded
    )
}

// MARK: Tests

@Test func theFirstRequestResolvesOnceAndLaterRequestsReuseTheSessionEnvironment() async throws {
    let root = try appSupportScratchRoot("session-reuse")
    defer { try? FileManager.default.removeItem(at: root) }
    let first = syntheticEnvironment(pathEntries: ["/synthetic/first"])
    let second = syntheticEnvironment(pathEntries: ["/synthetic/second"])
    let source = RecordingEnvironmentSource(resolveEnvironment: first, capturedEnvironment: second)
    let provider = source.provider

    let initial = await provider.sessionEnvironment()
    let reused = await provider.sessionEnvironment()
    let alsoReused = await provider.sessionEnvironment()

    #expect(initial.pathJoined == "/synthetic/first")
    #expect(reused.pathJoined == "/synthetic/first")
    #expect(alsoReused.pathJoined == "/synthetic/first")
    let counts = source.counts
    #expect(counts.resolve == 1)
    // A reused session environment performs no capture, and never re-reads the password database.
    #expect(counts.capture == 0)
    #expect(counts.loginShellPath == 0)
    #expect(counts.build == 0)
}

@Test func explicitRescanCapturesFreshEnvironmentAndBecomesTheSessionEnvironment() async throws {
    let root = try appSupportScratchRoot("rescan")
    defer { try? FileManager.default.removeItem(at: root) }
    let initial = syntheticEnvironment(pathEntries: ["/synthetic/initial"])
    let fresh = syntheticEnvironment(pathEntries: ["/synthetic/fresh"], isDegraded: false)
    let source = RecordingEnvironmentSource(resolveEnvironment: initial, capturedEnvironment: fresh)
    let provider = source.provider

    let first = await provider.sessionEnvironment()
    let rescanned = await provider.rescanEnvironment()
    let afterwards = await provider.sessionEnvironment()

    #expect(first.pathJoined == "/synthetic/initial")
    #expect(rescanned.pathJoined == "/synthetic/fresh")
    // The fresh capture becomes the session environment: Check/Refresh reuse it rather than
    // silently falling back to the stale resolved value.
    #expect(afterwards.pathJoined == "/synthetic/fresh")

    let counts = source.counts
    #expect(counts.resolve == 1)
    #expect(counts.loginShellPath == 1)
    #expect(counts.capture == 1)
    #expect(counts.build == 1)
    // The capture is taken for the password-database login shell — never `$SHELL`.
    #expect(source.shellsCaptured == ["/bin/zsh"])
    #expect(source.shellsBuilt == ["/bin/zsh"])
}

@Test func rescanFallsBackToTheDocumentedShellWhenThePasswordDatabaseHasNoShell() async throws {
    let initial = syntheticEnvironment(pathEntries: ["/synthetic/initial"])
    let fresh = syntheticEnvironment(pathEntries: ["/synthetic/fresh"])
    let source = RecordingEnvironmentSource(
        resolveEnvironment: initial,
        capturedEnvironment: fresh,
        loginShell: nil
    )

    _ = await source.provider.rescanEnvironment()

    // The fallback is the same /bin/sh Core uses in resolve(); it is never $SHELL.
    #expect(source.shellsCaptured == [SessionEnvironmentProvider.fallbackShellPath])
}

@Test func rescanPropagatesADegradedCaptureRatherThanHidingIt() async throws {
    let initial = syntheticEnvironment(pathEntries: ["/synthetic/initial"])
    let degraded = syntheticEnvironment(
        pathEntries: ShellEnvironmentResolver.fallbackPath.split(separator: ":").map(String.init),
        isDegraded: true
    )
    let source = RecordingEnvironmentSource(resolveEnvironment: initial, capturedEnvironment: degraded)

    let rescanned = await source.provider.rescanEnvironment()

    #expect(rescanned.isDegraded)
    #expect(rescanned.pathJoined == ShellEnvironmentResolver.fallbackPath)
}

@Test func theRawEnvironmentIsCarriedThroughVerbatimForProcessExecution() async throws {
    let environment = syntheticEnvironment(
        pathEntries: ["/synthetic/bin"],
        extraRaw: ["AGENT_LENS_SYNTHETIC_TOKEN": "fixture-value"]
    )
    let source = RecordingEnvironmentSource(resolveEnvironment: environment)

    let resolved = await source.provider.sessionEnvironment()

    // Every process receives this exact dictionary — the caller's value is not rebuilt or filtered.
    #expect(resolved.raw["PATH"] == "/synthetic/bin")
    #expect(resolved.raw["AGENT_LENS_SYNTHETIC_TOKEN"] == "fixture-value")
    #expect(resolved.raw.count == 2)
    #expect(resolved.isDegraded == false)
}

@Test func productionWiringUsesOnlyTheCoreLoginShellSeams() throws {
    // The production default must be Core's own functions, so the app never resolves a login shell
    // through `$SHELL`, an inherited PATH, or a terminal-derived environment (D-005 / M2 req. 7).
    let sourceFiles = try appSupportSourceFiles()
    #expect(!sourceFiles.isEmpty)
    let combined = try appSupportSourceCodeExcludingComments(sourceFiles)
    #expect(!combined.contains("ProcessInfo.processInfo.environment"))
    #expect(!combined.contains("ProcessInfo.processInfo.environment[\"PATH\"]"))
    #expect(!combined.contains("\"SHELL\""))
    #expect(!combined.contains("/usr/bin/env"))
    #expect(!combined.contains("which "))
    // No SwiftUI or AppKit import: the support target is a plain, testable boundary (D-002).
    #expect(!combined.contains("import SwiftUI"))
    #expect(!combined.contains("import AppKit"))
}

/// The production source with every whole-line Swift comment removed, so documentation prose can
/// never satisfy or trip an invariant about the code. Only lines whose first non-whitespace
/// characters are `//` (including `///`) are dropped — `Sources/AgentLensAppSupport` contains no
/// block comments — and every remaining line is compared verbatim, so a forbidden call in real
/// code is still caught.
private func appSupportSourceCodeExcludingComments(_ files: [URL]) throws -> String {
    var code = ""
    for file in files {
        let contents = try String(contentsOf: file, encoding: .utf8)
        for line in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
            code += line + "\n"
        }
    }
    return code
}

@Test func theSourceGuardIgnoresCommentProseButStillSeesRealCode() throws {
    let root = try appSupportScratchRoot("source-guard-control")
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("Synthetic.swift")
    try Data(
        """
        // correct regardless of which threads the handler and the utility queue run on
        /// the login shell is never `$SHELL` and never resolved through `which `
        let kept = "which " + "real code"
        """.utf8
    ).write(to: file)

    let filtered = try appSupportSourceCodeExcludingComments([file])

    // Comment prose that mentions a forbidden phrase is invisible to the guard...
    #expect(!filtered.contains("correct regardless of which threads"))
    #expect(!filtered.contains("never resolved through"))
    // ...while the same phrase in an actual code line still trips it.
    #expect(filtered.contains("which "))
    #expect(filtered.contains("let kept"))
}