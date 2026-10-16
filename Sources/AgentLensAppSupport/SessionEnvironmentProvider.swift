// SessionEnvironmentProvider — one app-session login-shell environment for the app layer.
// Implements M7 brief §"Proposed architecture and state contract".
//
// BINDING (D-005, M2 requirement 7): this type is the app's only environment source. Every
// process the app starts receives `ShellEnvironment.raw`; nothing here reads the process
// environment's PATH or `$SHELL`, and no captured value is persisted or logged. The login shell
// comes from the password database (`loginShellPath()`), never `$SHELL`.
//
// Session semantics:
//   * the first request resolves once through Core's cached `resolve()` (M2 req. 5), and every
//     later request reuses that value;
//   * an explicit Rescan takes a FRESH capture — `loginShellPath()` + `capture` +
//     `buildEnvironment`, exactly the public Core seams — and becomes the session environment, so a
//     later Check/Refresh reuses the fresh value;
//   * Core's own session cache is left untouched: there is no reset, invalidate, or force-refresh.
//
// Both requests block inside Core (the capture is bounded by Core's 3 s timeout), so each runs on a
// utility queue behind a checked continuation. Never on an inherited main-actor task.

import AgentLensCore
import Dispatch
import Foundation

/// The injected login-shell seams. The defaults are the real M2 core functions; tests replace them
/// with recording fakes so no test ever launches a login shell.
public struct SessionEnvironmentSource: Sendable {

    /// Core's cached session resolution.
    public let resolve: @Sendable () -> ShellEnvironment
    /// The login shell from the password database (never `$SHELL`).
    public let loginShellPath: @Sendable () -> String?
    /// One bounded capture attempt for an explicit rescan.
    public let capture: @Sendable (String) -> ShellEnvironmentResolver.CaptureOutcome
    /// Builds the final environment from a capture outcome, applying Core's documented fallback.
    public let build: @Sendable (String, ShellEnvironmentResolver.CaptureOutcome) -> ShellEnvironment

    public init(
        resolve: @escaping @Sendable () -> ShellEnvironment,
        loginShellPath: @escaping @Sendable () -> String?,
        capture: @escaping @Sendable (String) -> ShellEnvironmentResolver.CaptureOutcome,
        build: @escaping @Sendable (String, ShellEnvironmentResolver.CaptureOutcome) -> ShellEnvironment
    ) {
        self.resolve = resolve
        self.loginShellPath = loginShellPath
        self.capture = capture
        self.build = build
    }

    /// Production wiring: the M2 Core functions, unchanged and uninstrumented.
    public static let live = SessionEnvironmentSource(
        resolve: { ShellEnvironmentResolver.resolve() },
        loginShellPath: { ShellEnvironmentResolver.loginShellPath() },
        capture: { shellPath in ShellEnvironmentResolver.capture(shellPath: shellPath) },
        build: { shellPath, outcome in
            ShellEnvironmentResolver.buildEnvironment(shellPath: shellPath, outcome: outcome)
        }
    )
}

public final class SessionEnvironmentProvider: @unchecked Sendable {

    /// The shell used when the password database yields no login shell — identical to Core's own
    /// fallback in `resolve()`. Never `$SHELL` (D-005, M2 req. 1).
    public static let fallbackShellPath = "/bin/sh"

    private let source: SessionEnvironmentSource
    /// Owns the session value, so resolution, reuse, and supersession are serialized in one place.
    private let store = SessionEnvironmentStore()

    public init(source: SessionEnvironmentSource = .live) {
        self.source = source
    }

    /// The session environment: resolved once, then reused for the rest of the app session, so
    /// Check and Refresh act on exactly the environment the published inventory came from.
    public func sessionEnvironment() async -> ShellEnvironment {
        let source = self.source
        return await store.session { await Self.resolve(source) }
    }

    /// Explicit rescan: a fresh login-shell capture that becomes the session environment.
    public func rescanEnvironment() async -> ShellEnvironment {
        let source = self.source
        return await store.refresh { await Self.freshCapture(source) }
    }

    /// One resolution through Core's session-cached `resolve()`, off the caller's executor.
    private static func resolve(_ source: SessionEnvironmentSource) async -> ShellEnvironment {
        await offUtilityQueue { source.resolve() }
    }

    /// One fresh capture through the public Core seams, in Core's own order: the password-database
    /// login shell (never `$SHELL`), one bounded capture, then Core's documented build. Core's own
    /// session cache is left untouched — there is no reset, invalidate, or force-refresh.
    private static func freshCapture(_ source: SessionEnvironmentSource) async -> ShellEnvironment {
        await offUtilityQueue {
            let shellPath = source.loginShellPath() ?? Self.fallbackShellPath
            return source.build(shellPath, source.capture(shellPath))
        }
    }

    /// Runs one blocking capture/resolution call on a utility queue. A checked continuation
    /// guarantees exactly one resume; nothing blocks the caller's executor.
    private static func offUtilityQueue<T: Sendable>(
        _ work: @escaping @Sendable () -> T
    ) async -> T {
        await withCheckedContinuation { (continuation: CheckedContinuation<T, Never>) in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: work())
            }
        }
    }
}

/// The session value itself: resolved once, reused afterwards, and superseded by an explicit
/// rescan. An actor, not a lock, so no lock is ever held across the awaits inside Core's capture —
/// concurrent callers share the ONE in-flight resolution instead of each starting their own.
private actor SessionEnvironmentStore {

    private var value: ShellEnvironment?
    private var inFlight: (id: UUID, task: Task<ShellEnvironment, Never>)?

    /// The session environment, resolving at most once for all concurrent first requests.
    func session(_ produce: @escaping @Sendable () async -> ShellEnvironment) async -> ShellEnvironment {
        if let value { return value }
        if let inFlight { return await inFlight.task.value }
        let id = UUID()
        let task = Task { await produce() }
        inFlight = (id, task)
        let resolved = await task.value
        if inFlight?.id == id { inFlight = nil }
        value = resolved
        return resolved
    }

    /// A fresh capture that becomes the session environment. Serialized behind any in-flight
    /// resolution or rescan, so captures never overlap and this result is the newest one.
    func refresh(_ produce: @escaping @Sendable () async -> ShellEnvironment) async -> ShellEnvironment {
        while let current = inFlight {
            _ = await current.task.value
            if inFlight?.id == current.id { inFlight = nil }
        }
        let id = UUID()
        let task = Task { await produce() }
        inFlight = (id, task)
        let fresh = await task.value
        if inFlight?.id == id { inFlight = nil }
        value = fresh
        return fresh
    }
}