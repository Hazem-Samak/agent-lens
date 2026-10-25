// InstallationOwnership — explicit, read-only manager ownership results (M9-B).
//
// A verified value exists only for the exact evidence gathered by one verification invocation.
// It is an observation, not a durable authorization token: later installation changes make it
// stale, and callers must not treat it as permission to install, update or uninstall anything.
// Unknown is a first-class diagnostic result with a neutral, typed reason.

import Foundation

/// The selected entry and the canonical executable it resolved to during verification.
public struct InstallationSelectionIdentity: Equatable, Sendable {
    public let entryPath: String
    public let canonicalTarget: String
    public let fingerprint: ExecutableFingerprint

    public init(
        entryPath: String,
        canonicalTarget: String,
        fingerprint: ExecutableFingerprint
    ) {
        self.entryPath = entryPath
        self.canonicalTarget = canonicalTarget
        self.fingerprint = fingerprint
    }
}

/// The package-manager identity proved by this invocation.
public struct VerifiedInstallation: Equatable, Sendable {
    public let manager: PackageManager
    public let packageName: String
    public let managerEntryPath: String
    public let managerTarget: String
    public let managerFingerprint: ExecutableFingerprint
    /// npm's global prefix or Homebrew's Cellar.
    public let managerRoot: String
    /// The npm package root or the selected Homebrew keg.
    public let installationRoot: String
    public let selection: InstallationSelectionIdentity

    init(
        manager: PackageManager,
        packageName: String,
        managerEntryPath: String,
        managerTarget: String,
        managerFingerprint: ExecutableFingerprint,
        managerRoot: String,
        installationRoot: String,
        selection: InstallationSelectionIdentity
    ) {
        self.manager = manager
        self.packageName = packageName
        self.managerEntryPath = managerEntryPath
        self.managerTarget = managerTarget
        self.managerFingerprint = managerFingerprint
        self.managerRoot = managerRoot
        self.installationRoot = installationRoot
        self.selection = selection
    }
}

/// Why explicit ownership verification did not produce a verified identity. Every case is neutral:
/// none means "not owned", and none authorizes a manager operation.
public enum InstallationOwnershipReason: Equatable, Sendable, CaseIterable {
    case notInstalled
    case inconsistentSelection
    case selectionUnavailable
    case unsupportedSource
    case noDeclaredPackage
    case noMatchingPackage
    case unsupportedCask
    case unsupportedInstallationLayout
    case ambiguousOwnership
    case managerUnavailable
    case managerQueryFailed
    case invalidManagerOutput
    case managerRootMismatch
    case packageNotInstalled
    case packagePathUnsafe
    case manifestMissing
    case manifestUnreadable
    case manifestTooLarge
    case manifestInvalid
    case packageNameMismatch
    case executableNotDeclared
    case executableOutsidePackage
    case manifestExecutableMismatch
    case managerEntryMismatch
    case selectedExecutableChanged
    case managerChanged
    case proofChanged
    case formulaRecordMismatch
    case selectedKegNotInstalled
    case selectedKegNotConfirmed
    case cancelled

    public var message: String {
        switch self {
        case .notInstalled:
            "No live executable is installed"
        case .inconsistentSelection:
            "PATH diagnostics are inconsistent, so ownership cannot be verified"
        case .selectionUnavailable:
            "The selected executable is unavailable"
        case .unsupportedSource:
            "The detected installation source is not supported for ownership verification"
        case .noDeclaredPackage:
            "No package is declared for the detected installation source"
        case .noMatchingPackage:
            "No declared package matches the selected installation"
        case .unsupportedCask:
            "Homebrew cask ownership is not supported"
        case .unsupportedInstallationLayout:
            "The installation layout is not supported"
        case .ambiguousOwnership:
            "More than one declared package matched; ownership is ambiguous"
        case .managerUnavailable:
            "The package manager was not found on the captured PATH"
        case .managerQueryFailed:
            "The package manager query failed"
        case .invalidManagerOutput:
            "The package manager returned invalid output"
        case .managerRootMismatch:
            "The selected executable does not belong to the manager's reported root"
        case .packageNotInstalled:
            "The declared package is not installed in the manager's root"
        case .packagePathUnsafe:
            "The package path is unsafe to inspect"
        case .manifestMissing:
            "The package manifest is missing"
        case .manifestUnreadable:
            "The package manifest could not be read"
        case .manifestTooLarge:
            "The package manifest exceeds the bounded read limit"
        case .manifestInvalid:
            "The package manifest is invalid"
        case .packageNameMismatch:
            "The package manifest names a different package"
        case .executableNotDeclared:
            "The package manifest does not declare this executable"
        case .executableOutsidePackage:
            "The declared executable resolves outside the package"
        case .manifestExecutableMismatch:
            "The package manifest binds this executable to a different target"
        case .managerEntryMismatch:
            "The manager's executable entry does not resolve to the selected target"
        case .selectedExecutableChanged:
            "The selected executable changed during verification"
        case .managerChanged:
            "The package manager changed during verification"
        case .proofChanged:
            "The installation proof changed during verification"
        case .formulaRecordMismatch:
            "The Homebrew formula record does not match the selected installation"
        case .selectedKegNotInstalled:
            "The selected Homebrew keg is not reported as installed"
        case .selectedKegNotConfirmed:
            "The selected Homebrew keg is not confirmed by this manager; another keg's proof was not borrowed"
        case .cancelled:
            "Verification was cancelled"
        }
    }
}

public enum InstallationOwnershipOutcome: Equatable, Sendable {
    case verified(VerifiedInstallation)
    case unknown(InstallationOwnershipReason)
}

/// The complete result of one explicit ownership verification. `observedAt` is the publication
/// time of this invocation, not a cached historical fact.
public struct InstallationOwnershipResult: Equatable, Sendable {
    public let registryID: String
    public let observedSelectedEntry: String?
    public let observedSelectedTarget: String?
    public let observedAt: Date
    public let outcome: InstallationOwnershipOutcome

    public init(
        registryID: String,
        observedSelectedEntry: String?,
        observedSelectedTarget: String?,
        observedAt: Date,
        outcome: InstallationOwnershipOutcome
    ) {
        self.registryID = registryID
        self.observedSelectedEntry = observedSelectedEntry
        self.observedSelectedTarget = observedSelectedTarget
        self.observedAt = observedAt
        self.outcome = outcome
    }

    public var verifiedInstallation: VerifiedInstallation? {
        if case .verified(let installation) = outcome { return installation }
        return nil
    }

    public var unknownReason: InstallationOwnershipReason? {
        if case .unknown(let reason) = outcome { return reason }
        return nil
    }
}
