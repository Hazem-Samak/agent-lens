// OperationModels — the immutable, public M10-C operation vocabulary.
//
// A preparation binds a reviewable preview to internal authorization evidence. The public surface
// exposes only the preview; the complete proof, environment, plan identity and operation root live
// internally and are never serialized. An operation outcome retains the process result and the
// measured reconciliation delta separately so a zero exit cannot be mistaken for success.

import Foundation

/// Terminal (or explicitly interrupted) state of one npm update operation.
public enum OperationState: String, Equatable, Sendable {
    case succeeded
    case failed
    case cancelled
    case interrupted
    case uncertain
}

/// The exact effect text disclosed with a preview. It is presentation only; no string is executed.
public let npmUpdateEffectText = """
npm will replace or update the named global package to the reviewed version. Package dependencies and executable links may change. Package lifecycle scripts may run subject to npm policy; Agent Lens does not sandbox those scripts and cannot promise that only the verified prefix or the owned operation scratch changes. Configuration and caches outside the owned invocation scratch and verified prefix are not intentionally targeted. No rollback or atomicity is guaranteed.
"""

/// A fully reviewable update preview. Dynamic values are plain text/arrays; `arguments` is the
/// literal argv that will be executed, never a shell command.
public struct NpmUpdatePreview: Equatable, Sendable {
    public let registryID: String
    public let displayName: String
    public let selectedEntryPath: String
    public let selectedTarget: String
    public let installedVersion: String
    public let targetVersion: String
    public let packageName: String
    public let registry: String
    public let tag: String
    public let managerPath: String
    public let prefix: String
    public let workingDirectory: String
    public let executablePath: String
    public let arguments: [String]
    public let effect: String

    /// A readable rendering only. It is never passed to a shell.
    public var shellEscapedCommand: String {
        ([executablePath] + arguments).map(Self.shellEscaped).joined(separator: " ")
    }

    nonisolated private static func shellEscaped(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// Why preparation was refused. Every case is neutral and never authorizes a mutation.
public enum NpmUpdateUnavailableReason: String, Equatable, Sendable {
    case notUpdateAvailable
    case unsupportedManager
    case installedVersionUnavailable
    case unsupportedVersion
    case newerThanMetadata
    case prereleaseChannel
    case identityUnverified
    case managerUnavailable
    case unsupportedRegistry
    case metadataInvalid
    case queryTimedOut
    case budgetExhausted
    case operationRootUnsafe
    case noVerifiedSelection
    case operationNotAccepted
    case cancelled
    case probeFailed

    public var message: String {
        switch self {
        case .notUpdateAvailable: "No verified newer stable update is available."
        case .unsupportedManager: "The selected installation is not a verified npm-global package."
        case .installedVersionUnavailable: "The selected installation has no usable local version."
        case .unsupportedVersion: "The selected installation version is not stable strict SemVer."
        case .newerThanMetadata: "The selected installation is newer than the observed target."
        case .prereleaseChannel: "The observed latest target is not a stable release."
        case .identityUnverified: "The selected installation could not be freshly verified."
        case .managerUnavailable: "npm is not available on the captured PATH."
        case .unsupportedRegistry: "The selected npm route is not the supported public registry."
        case .metadataInvalid: "Fresh npm latest metadata was invalid."
        case .queryTimedOut: "Fresh npm metadata could not be observed within the query bound."
        case .budgetExhausted: "The read-only preparation budget was exhausted."
        case .operationRootUnsafe: "An owned operation scratch root could not be claimed safely."
        case .noVerifiedSelection: "The selected entry does not identify a verifiable target."
        case .operationNotAccepted: "Update is not yet accepted for this tool. Agent Lens detects it, but no managed update has been verified for it."
        case .cancelled: "Preparation was cancelled before any mutation."
        case .probeFailed: "Fresh npm verification failed."
        }
    }
}

/// The result of preparing one update.
public enum NpmUpdatePrepareResult: Sendable {
    case ready(NpmUpdatePreparation)
    case unavailable(NpmUpdateUnavailableReason)
}

/// An opaque preparation. It has no public initializer and cannot be built from display strings.
/// It retains the owned operation root until cancelled or consumed by `execute`.
public final class NpmUpdatePreparation: @unchecked Sendable {
    public let preview: NpmUpdatePreview
    internal let plan: NpmUpdatePlan

    private let lock = NSLock()
    private var claimed = false
    private var released = false

    internal init(preview: NpmUpdatePreview, plan: NpmUpdatePlan) {
        self.preview = preview
        self.plan = plan
    }

    /// Consumes the authorization evidence exactly once.
    internal func claim() -> NpmUpdatePlan? {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed, !released else { return nil }
        claimed = true
        return plan
    }

    /// Releases a preparation that will never execute. Returns false if it was already consumed.
    internal func releaseUnconsumed() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed, !released else { return false }
        released = true
        return releaseOperationRoot(plan.root)
    }

    internal var isConsumed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return claimed || released
    }
}

/// Measured before/after facts. It is a delta, never an atomicity or rollback claim.
public struct InstallationDelta: Equatable, Sendable {
    public let beforeVersion: String?
    public let afterVersion: String?
    public let beforeEntryPath: String?
    public let afterEntryPath: String?
    public let beforeTarget: String?
    public let afterTarget: String?
    public let beforeAliases: [String]
    public let afterAliases: [String]
    public let beforeShadowedCount: Int
    public let afterShadowedCount: Int
    public let beforeInstallState: InstallState
    public let afterInstallState: InstallState
    public let ownership: InstallationOwnershipOutcome?
    public let versionMatchesTarget: Bool

    public var changed: Bool {
        beforeVersion != afterVersion
            || beforeEntryPath != afterEntryPath
            || beforeTarget != afterTarget
            || beforeAliases != afterAliases
            || beforeShadowedCount != afterShadowedCount
            || beforeInstallState != afterInstallState
    }
}

/// The complete operation result. Output is in-memory only and separate per stream.
public struct OperationOutcome: Equatable, Sendable {
    public let preview: NpmUpdatePreview
    public let state: OperationState
    public let stdout: Data
    public let stderr: Data
    public let stdoutTruncated: Bool
    public let stderrTruncated: Bool
    public let exitStatus: Int32?
    /// True only when the operation process was actually launched.
    public let processStarted: Bool
    public let reconciliation: InstallationDelta?
    public let cleanupWarnings: [String]
    public let message: String?

    public var stdoutText: String { String(decoding: stdout, as: UTF8.self) }
    public var stderrText: String { String(decoding: stderr, as: UTF8.self) }

    public init(
        preview: NpmUpdatePreview,
        state: OperationState,
        stdout: Data,
        stderr: Data,
        stdoutTruncated: Bool,
        stderrTruncated: Bool,
        exitStatus: Int32?,
        processStarted: Bool,
        reconciliation: InstallationDelta?,
        cleanupWarnings: [String],
        message: String?
    ) {
        self.preview = preview
        self.state = state
        self.stdout = stdout
        self.stderr = stderr
        self.stdoutTruncated = stdoutTruncated
        self.stderrTruncated = stderrTruncated
        self.exitStatus = exitStatus
        self.processStarted = processStarted
        self.reconciliation = reconciliation
        self.cleanupWarnings = cleanupWarnings
        self.message = message
    }
}

/// One operation-specific dual-stream process result.
public struct OperationCommandResult: Equatable, Sendable {
    public let stdout: Data
    public let stderr: Data
    public let stdoutTruncated: Bool
    public let stderrTruncated: Bool
    public let exitStatus: Int32?
    public let processStarted: Bool
    public let timedOut: Bool
    public let cancelled: Bool
    public let cleanupWarning: Bool

    public init(
        stdout: Data,
        stderr: Data,
        stdoutTruncated: Bool,
        stderrTruncated: Bool,
        exitStatus: Int32?,
        processStarted: Bool,
        timedOut: Bool,
        cancelled: Bool,
        cleanupWarning: Bool
    ) {
        self.stdout = stdout
        self.stderr = stderr
        self.stdoutTruncated = stdoutTruncated
        self.stderrTruncated = stderrTruncated
        self.exitStatus = exitStatus
        self.processStarted = processStarted
        self.timedOut = timedOut
        self.cancelled = cancelled
        self.cleanupWarning = cleanupWarning
    }
}

/// Injectable operation process seam. Production uses `ProcessOperationCommandRunner`.
public protocol OperationCommandRunner: Sendable {
    func run(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        currentDirectory: String,
        timeout: TimeInterval
    ) async -> OperationCommandResult
}

/// Process-wide production mutation exclusion. Tests inject independent instances.
public actor OperationExecutionGate {
    public static let shared = OperationExecutionGate()

    private var busy = false

    public init() {}

    /// Returns true only when this caller acquired the gate.
    public func acquire() -> Bool {
        guard !busy else { return false }
        busy = true
        return true
    }

    public func release() {
        busy = false
    }
}

// MARK: - M10-D npm Uninstall

/// The exact effect text disclosed with an Uninstall preview. It is presentation only; no string
/// is executed.
public let npmUninstallEffectText = """
npm will remove the named global package from the verified prefix. Its executable links may be removed, the PATH winner may change, and another installed copy may become visible. npm v7+ does not run uninstall lifecycle scripts, and Agent Lens does not add a script-policy override. Transitive dependency directories, caches, configuration, logs, and other installations outside the verified package are not intentionally targeted and may remain. No rollback, reinstall, or atomicity is guaranteed; an interrupted or failed removal may leave a partial state that must be re-observed.
"""

/// A fully reviewable Uninstall preview. Dynamic values are plain text/arrays; `arguments` is the
/// literal argv that will be executed, never a shell command.
public struct NpmUninstallPreview: Equatable, Sendable {
    public let registryID: String
    public let displayName: String
    public let selectedEntryPath: String
    public let selectedTarget: String
    public let installedVersion: String?
    public let packageName: String
    public let registry: String
    public let managerPath: String
    public let prefix: String
    public let installationRoot: String
    public let workingDirectory: String
    public let executablePath: String
    public let arguments: [String]
    public let effect: String

    /// A readable rendering only. It is never passed to a shell.
    public var shellEscapedCommand: String {
        ([executablePath] + arguments).map(Self.shellEscaped).joined(separator: " ")
    }

    nonisolated private static func shellEscaped(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// Why Uninstall preparation was refused. Every case is neutral and never authorizes a mutation.
public enum NpmUninstallUnavailableReason: String, Equatable, Sendable {
    case unsupportedManager
    case noVerifiedSelection
    case identityUnverified
    case managerUnavailable
    case operationRootUnsafe
    case operationNotAccepted
    case cancelled
    case probeFailed

    public var message: String {
        switch self {
        case .unsupportedManager: "The selected installation is not a verified npm-global package."
        case .noVerifiedSelection: "The selected entry does not identify a verifiable installation."
        case .identityUnverified: "The selected installation could not be freshly verified."
        case .managerUnavailable: "npm is not available on the captured PATH."
        case .operationRootUnsafe: "An owned operation scratch root could not be claimed safely."
        case .operationNotAccepted: "Uninstall is not yet accepted for this tool. Agent Lens detects it, but no managed uninstall has been verified for it."
        case .cancelled: "Preparation was cancelled before any mutation."
        case .probeFailed: "Fresh npm verification failed."
        }
    }
}

/// The result of preparing one Uninstall.
public enum NpmUninstallPrepareResult: Sendable {
    case ready(NpmUninstallPreparation)
    case unavailable(NpmUninstallUnavailableReason)
}

/// An opaque Uninstall preparation. It has no public initializer and cannot be built from display
/// strings. It retains the owned operation root until cancelled or consumed by `execute`.
public final class NpmUninstallPreparation: @unchecked Sendable {
    public let preview: NpmUninstallPreview
    internal let plan: NpmUninstallPlan

    private let lock = NSLock()
    private var claimed = false
    private var released = false

    internal init(preview: NpmUninstallPreview, plan: NpmUninstallPlan) {
        self.preview = preview
        self.plan = plan
    }

    internal func claim() -> NpmUninstallPlan? {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed, !released else { return nil }
        claimed = true
        return plan
    }

    internal func releaseUnconsumed() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed, !released else { return false }
        released = true
        return releaseOperationRoot(plan.root)
    }

    internal var isConsumed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return claimed || released
    }
}

/// Measured before/after facts for one Uninstall. It is a delta, never an atomicity or rollback
/// claim.
public struct NpmUninstallDelta: Equatable, Sendable {
    public let beforeVersion: String?
    public let afterVersion: String?
    public let beforeEntryPath: String?
    public let afterEntryPath: String?
    public let beforeTarget: String?
    public let afterTarget: String?
    public let beforeAliases: [String]
    public let afterAliases: [String]
    public let beforeShadowedCount: Int
    public let afterShadowedCount: Int
    public let beforeInstallState: InstallState
    public let afterInstallState: InstallState
    /// True only when the exact recorded package directory was observed absent (not merely
    /// unreadable or replaced).
    public let packageDirectoryAbsent: Bool
    /// True when a directory exists at the recorded package path but has a different identity
    /// (for example, a replacement package or a retargeted store). Never success.
    public let packageDirectoryReplaced: Bool
    /// True only when the selected entry no longer resolves to the recorded canonical target.
    public let selectedTargetReleased: Bool
    /// True when a dangling selected-entry symlink remains after the target was released.
    public let selectedEntryResidue: Bool
    /// True when either removal observation failed (permission, I/O, race, or wrong type). This is
    /// never a success fact.
    public let observationFailed: Bool
    public let ownership: InstallationOwnershipOutcome?

    public var changed: Bool {
        beforeVersion != afterVersion
            || beforeEntryPath != afterEntryPath
            || beforeTarget != afterTarget
            || beforeAliases != afterAliases
            || beforeShadowedCount != afterShadowedCount
            || beforeInstallState != afterInstallState
            || packageDirectoryAbsent
            || packageDirectoryReplaced
            || selectedTargetReleased
            || selectedEntryResidue
            || observationFailed
    }
}

/// The complete Uninstall result. Output is in-memory only and separate per stream.
public struct NpmUninstallOutcome: Equatable, Sendable {
    public let preview: NpmUninstallPreview
    public let state: OperationState
    public let stdout: Data
    public let stderr: Data
    public let stdoutTruncated: Bool
    public let stderrTruncated: Bool
    public let exitStatus: Int32?
    public let processStarted: Bool
    public let reconciliation: NpmUninstallDelta?
    public let cleanupWarnings: [String]
    public let message: String?

    public var stdoutText: String { String(decoding: stdout, as: UTF8.self) }
    public var stderrText: String { String(decoding: stderr, as: UTF8.self) }

    public init(
        preview: NpmUninstallPreview,
        state: OperationState,
        stdout: Data,
        stderr: Data,
        stdoutTruncated: Bool,
        stderrTruncated: Bool,
        exitStatus: Int32?,
        processStarted: Bool,
        reconciliation: NpmUninstallDelta?,
        cleanupWarnings: [String],
        message: String?
    ) {
        self.preview = preview
        self.state = state
        self.stdout = stdout
        self.stderr = stderr
        self.stdoutTruncated = stdoutTruncated
        self.stderrTruncated = stderrTruncated
        self.exitStatus = exitStatus
        self.processStarted = processStarted
        self.reconciliation = reconciliation
        self.cleanupWarnings = cleanupWarnings
        self.message = message
    }
}
