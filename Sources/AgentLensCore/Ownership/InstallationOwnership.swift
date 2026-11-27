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

/// The Python environment shape proved by a local ownership diagnostic. These kinds are
/// diagnostics only; none authorizes a mutation.
public enum PythonEnvironmentKind: String, Codable, Sendable, Equatable, CaseIterable {
    case uvTool
    case virtualEnvironment
    case pipxEnvironment
    case externallyManagedSystem
    case sharedPrefix

    public var label: String {
        switch self {
        case .uvTool: "uv tool"
        case .virtualEnvironment: "Virtual environment (venv)"
        case .pipxEnvironment: "pipx environment"
        case .externallyManagedSystem: "Externally managed Python (PEP 668)"
        case .sharedPrefix: "Shared Python prefix"
        }
    }

    /// Read-only guidance for the native and CLI diagnostic surfaces. This is not a mutation
    /// affordance and does not claim that a shared prefix is PEP 668 managed.
    public var guidance: String {
        switch self {
        case .uvTool:
            "A uv-managed tool environment. This diagnostic is read-only."
        case .virtualEnvironment:
            "A virtual environment. Manage it with its own project tooling."
        case .pipxEnvironment:
            "A pipx-managed environment. Manage it with pipx."
        case .externallyManagedSystem:
            "An externally managed Python prefix (PEP 668). Packages are not installed there without an explicit override."
        case .sharedPrefix:
            "A shared Python prefix. This is not necessarily PEP 668 managed; Agent Lens does not modify it."
        }
    }
}

/// Where the installed distribution's source is known to have come from. `.publicPyPI` requires
/// affirmative local evidence; an absent index record is `.unknown`, not public PyPI.
public enum PythonIndexProvenance: String, Codable, Sendable, Equatable, CaseIterable {
    case publicPyPI
    case customIndex
    case nonRegistrySource
    case unknown

    public var label: String {
        switch self {
        case .publicPyPI: "Public PyPI"
        case .customIndex: "Custom index"
        case .nonRegistrySource: "Direct or non-registry source"
        case .unknown: "Unknown"
        }
    }
}

/// Read-only Python environment facts attached to a verified installation. These are display
/// facts, not the internal proof used for revalidation. No raw credential-bearing URL or receipt
/// text is exposed here.
public struct PythonEnvironmentMetadata: Equatable, Sendable {
    public let installedVersion: String
    public let interpreterVersion: String?
    public let requiresPython: String?
    public let environmentKind: PythonEnvironmentKind
    public let installer: String
    public let indexProvenance: PythonIndexProvenance
    /// Redacted receipt requirement descriptors (for example `aider-chat==0.85.0`), never raw URLs.
    public let receiptConstraints: [String]
    /// Redacted additional requirement names from a `--with` receipt; never raw URLs.
    public let extras: [String]

    public init(
        installedVersion: String,
        interpreterVersion: String?,
        requiresPython: String?,
        environmentKind: PythonEnvironmentKind,
        installer: String,
        indexProvenance: PythonIndexProvenance,
        receiptConstraints: [String] = [],
        extras: [String] = []
    ) {
        self.installedVersion = installedVersion
        self.interpreterVersion = interpreterVersion
        self.requiresPython = requiresPython
        self.environmentKind = environmentKind
        self.installer = installer
        self.indexProvenance = indexProvenance
        self.receiptConstraints = receiptConstraints
        self.extras = extras
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
    /// Python diagnostics, or nil for non-Python managers.
    public let pythonEnvironment: PythonEnvironmentMetadata?

    init(
        manager: PackageManager,
        packageName: String,
        managerEntryPath: String,
        managerTarget: String,
        managerFingerprint: ExecutableFingerprint,
        managerRoot: String,
        installationRoot: String,
        selection: InstallationSelectionIdentity,
        pythonEnvironment: PythonEnvironmentMetadata? = nil
    ) {
        self.manager = manager
        self.packageName = packageName
        self.managerEntryPath = managerEntryPath
        self.managerTarget = managerTarget
        self.managerFingerprint = managerFingerprint
        self.managerRoot = managerRoot
        self.installationRoot = installationRoot
        self.selection = selection
        self.pythonEnvironment = pythonEnvironment
    }
}

/// Why explicit ownership verification did not produce a verified identity. Every case is neutral:
/// none means "not owned", and none authorizes a manager operation.
public enum InstallationOwnershipReason: Error, Equatable, Sendable, CaseIterable {
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
    case caskRecordMismatch
    case caskTokenRenamed
    case selectedCaskNotInstalled
    case selectedCaskNotConfirmed
    case caskArtifactUnlinked
    case tooManyDeclaredCasks
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
        case .caskRecordMismatch:
            "The Homebrew cask record does not match the declared cask and the selected installation"
        case .caskTokenRenamed:
            "The declared Homebrew cask name was renamed; the declaration was not retargeted"
        case .selectedCaskNotInstalled:
            "The selected Homebrew cask version is not reported as installed"
        case .selectedCaskNotConfirmed:
            "The selected Homebrew cask installation is not confirmed by this manager"
        case .caskArtifactUnlinked:
            "Homebrew does not list a staged artifact for the selected cask executable"
        case .tooManyDeclaredCasks:
            "More than four declared casks were supplied; ownership was not verified"
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
