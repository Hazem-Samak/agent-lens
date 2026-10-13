// ShellEnvironmentResolver — login-shell environment resolution.
// Implements D-005 and AGENT_LENS_SCOPE.md §20; framed by briefs/M2-environment-resolution.md.
//
// ─────────────────────────────────────────────────────────────────────────────
// M2 REQUIREMENT 7 — BINDING RULE FOR THIS AND ALL LATER MILESTONES:
// No other code in this project may read ProcessInfo.processInfo.environment["PATH"]
// for tool discovery or command execution. A GUI .app does not inherit the login
// shell's PATH; the resolver below is the ONLY source of truth.
// ─────────────────────────────────────────────────────────────────────────────
//
// How it works (M2 brief):
//   1. Login shell is read from the password database (getpwuid), never $SHELL.
//   2. The shell is launched login AND interactive (-l -i), wrapping a NUL-delimited
//      environment dump (`env -0`) in sentinel markers, so rc-file banners are discarded
//      and values containing newlines survive.
//   3. 3 second timeout; on failure or timeout falls back to a documented default
//      PATH with isDegraded = true. Never hangs.
//   4. Output is captured only — rc files are never sourced into this process.
//   5. The result is cached for the session.

import Darwin
import Foundation

/// The resolved login-shell environment, exposed for discovery and `Process` execution.
public struct ShellEnvironment: Sendable {
    /// The login shell path, e.g. `/bin/zsh`.
    public let shellPath: String
    /// PATH as the shell searches it — ordered.
    public let pathEntries: [String]
    /// The entries joined with ":".
    public let pathJoined: String
    /// The full captured environment, suitable for `Process.environment`.
    public let raw: [String: String]
    /// True when the fallback PATH was used because capture failed or timed out.
    public let isDegraded: Bool

    /// Public so M3 tests can inject synthetic environments without touching M2 logic.
    public init(
        shellPath: String,
        pathEntries: [String],
        pathJoined: String,
        raw: [String: String],
        isDegraded: Bool
    ) {
        self.shellPath = shellPath
        self.pathEntries = pathEntries
        self.pathJoined = pathJoined
        self.raw = raw
        self.isDegraded = isDegraded
    }
}

public enum ShellEnvironmentResolver {

    // MARK: Constants (all documented fallbacks, M2 req. 3)

    /// Documented default PATH used when the login-shell capture fails or times out.
    public static let fallbackPath = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    /// Sentinel markers around the environment dump. Everything outside them
    /// (rc-file banners, prompts, MOTDs) is discarded.
    public static let beginMarker = "__AGENTLENS_ENV_BEGIN__"
    public static let endMarker = "__AGENTLENS_ENV_END__"

    /// The capture command run inside the shell. `-i` is required so .zshrc is
    /// read; `env -0` uses NUL delimiters so values containing newlines survive.
    public static let defaultCaptureScript =
        #"printf "\n__AGENTLENS_ENV_BEGIN__\n"; env -0; printf "__AGENTLENS_ENV_END__\n""#

    /// Capture timeout, seconds (M2 req. 3).
    public static let captureTimeout: TimeInterval = 3

    /// Session cache. The lock lives inside the class, so the static `let` is
    /// concurrency-safe shared state in Swift 6 strict-concurrency mode.
    private static let cache = LockedOnceEnvironmentCache()

    /// Caches the environment resolved for this session (M2 req. 5).
    private final class LockedOnceEnvironmentCache: @unchecked Sendable {
        private let lock = NSLock()
        private var value: ShellEnvironment?

        func stored() -> ShellEnvironment? {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        func store(_ environment: ShellEnvironment) {
            lock.lock()
            value = environment
            lock.unlock()
        }
    }

    // MARK: Session resolution (M2 req. 5)

    /// Resolves the login-shell environment once per session and caches it.
    public static func resolve() -> ShellEnvironment {
        if let cached = cache.stored() { return cached }
        let shellPath = loginShellPath() ?? "/bin/sh"
        let outcome = capture(shellPath: shellPath)
        let environment = buildEnvironment(shellPath: shellPath, outcome: outcome)
        cache.store(environment)
        return environment
    }

    // MARK: Shell detection (M2 req. 1)

    /// The login shell from the password database. `$SHELL` must NOT be used:
    /// it may be unset in a GUI context.
    public static func loginShellPath() -> String? {
        guard let passwd = getpwuid(getuid()) else { return nil }
        guard let shell = passwd.pointee.pw_shell else { return nil }
        let shellString = String(validatingUTF8: shell)
        guard let shellString, !shellString.isEmpty else { return nil }
        return shellString
    }

    // MARK: Sentinel parsing (pure, unit-tested)

    /// Outcome of one capture attempt.
    public struct CaptureOutcome: Sendable {
        public let dump: [String: String]?
        public let timedOut: Bool

        public init(dump: [String: String]?, timedOut: Bool) {
            self.dump = dump
            self.timedOut = timedOut
        }
    }

    /// Parses the raw capture output between the sentinels into KEY=VALUE pairs.
    /// Splits on NUL so values containing newlines or "=" survive intact.
    /// Returns nil when both sentinels are not found.
    public static func parseEnvironmentDump(_ data: Data) -> [String: String]? {
        let begin = Data("\(beginMarker)\n".utf8)
        let end = Data(endMarker.utf8)
        guard let beginRange = data.range(of: begin),
              let endRange = data.range(of: end),
              beginRange.upperBound <= endRange.lowerBound
        else { return nil }

        let payload = data.subdata(in: beginRange.upperBound ..< endRange.lowerBound)
        var result: [String: String] = [:]
        for chunk in payload.split(separator: 0, omittingEmptySubsequences: false) {
            guard let entry = String(data: Data(chunk), encoding: .utf8),
                  !entry.isEmpty,
                  let equals = entry.firstIndex(of: "=")
            else { continue }
            let key = String(entry[entry.startIndex ..< equals])
            let value = String(entry[entry.index(after: equals)...])
            result[key] = value
        }
        return result.isEmpty ? nil : result
    }

    // MARK: Capture (M2 req. 2, 3, 4)

    /// Launches `shellPath -l -i -c <script>` and captures stdout.
    /// Output is captured only — nothing is sourced or eval'd into this process (M2 req. 4).
    /// Public parameters are for unit tests; production callers use the defaults.
    public static func capture(
        shellPath: String,
        script: String = ShellEnvironmentResolver.defaultCaptureScript,
        timeout: TimeInterval = ShellEnvironmentResolver.captureTimeout
    ) -> CaptureOutcome {
        guard let result = BoundedProcessRunner.run(
            executablePath: shellPath,
            arguments: ["-l", "-i", "-c", script],
            timeout: timeout
        ) else {
            return CaptureOutcome(dump: nil, timedOut: false)
        }
        guard !result.timedOut else {
            return CaptureOutcome(dump: nil, timedOut: true)
        }
        guard !result.outputLimitExceeded, result.exitStatus == 0 else {
            return CaptureOutcome(dump: nil, timedOut: false)
        }
        return CaptureOutcome(
            dump: parseEnvironmentDump(result.standardOutput),
            timedOut: false
        )
    }

    // MARK: Environment building (pure, unit-tested)

    /// Builds the final environment, applying the documented fallback when capture
    /// failed, timed out, or produced no PATH (M2 req. 3). The raw environment is
    /// passed through untouched for use with `Process`.
    public static func buildEnvironment(shellPath: String, outcome: CaptureOutcome) -> ShellEnvironment {
        var raw = outcome.dump ?? [:]
        let degraded = outcome.timedOut || raw["PATH"] == nil
        let path = degraded
            ? fallbackPath
            : (raw["PATH"] ?? fallbackPath)
        // Keep the raw environment internally consistent for Process.environment.
        raw["PATH"] = path
        let entries = path
            .split(separator: ":", omittingEmptySubsequences: false)
            .map(String.init)
        return ShellEnvironment(
            shellPath: shellPath,
            pathEntries: entries,
            pathJoined: path,
            raw: raw,
            isDegraded: degraded
        )
    }

    // MARK: debug-env rendering (pure, unit-tested)

    /// Renders `agent-lens debug-env` output exactly as the M2 brief requires.
    public static func renderDebugEnvironment(_ environment: ShellEnvironment) -> String {
        var lines: [String] = []
        lines.append("shell:       \(environment.shellPath)")
        lines.append("degraded:    \(environment.isDegraded)")
        lines.append("path_joined: \(environment.pathJoined)")
        lines.append("path_entries:")
        lines.append(contentsOf: environment.pathEntries.map { "  \($0)" })
        return lines.joined(separator: "\n") + "\n"
    }
}
