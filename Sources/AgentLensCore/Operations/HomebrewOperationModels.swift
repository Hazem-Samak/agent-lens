// HomebrewOperationModels — the immutable, public M13 Homebrew operation vocabulary.
//
// This file adds formula operation previews, refusal reasons, measured deltas and the exact effect
// texts. The npm vocabulary in `OperationModels.swift` is deliberately untouched: npm callers,
// control flow and effect texts stay byte-identical. A preparation binds a reviewable preview to
// internal authorization evidence; the public surface exposes only the preview. Every effect text
// names each environment switch this operation forces and the manager writes it does not redirect.
// It is presentation only; no string is executed.

import Foundation

/// Which Homebrew package class a mutation targets. A formula and a cask are separate owners with
/// separate argv, separate proofs and separate reasons; the vocabulary never widens one to the
/// other.
public enum HomebrewPackageKind: String, Equatable, Sendable {
    case formula
    case cask
}

/// The closed set of Homebrew mutation shapes Core can express. Update and Uninstall differ in
/// argv, environment switches, refusal policy and reconciliation facts, so they are separate cases
/// rather than a boolean flag on one operation.
public enum HomebrewMutationKind: String, Equatable, Sendable, CaseIterable {
    case formulaUpdate
    case formulaUninstall
    case caskUpdate
    case caskUninstall

    public var packageKind: HomebrewPackageKind {
        switch self {
        case .formulaUpdate, .formulaUninstall: .formula
        case .caskUpdate, .caskUninstall: .cask
        }
    }

    public var isUpdate: Bool {
        switch self {
        case .formulaUpdate, .caskUpdate: true
        case .formulaUninstall, .caskUninstall: false
        }
    }
}

/// How Homebrew's own unpinned `uninstall --formula <name>` selected the keg it will remove.
/// Homebrew's precedence is an existing opt link, then an existing linked-keg link, then a single
/// installed keg, then its latest-installed resolution. The last case is never inferred here.
enum HomebrewRemovalTargetSource: String, Equatable, Sendable {
    case optLink
    case linkedKegLink
    case singleInstalledKeg
}

/// The live keg identity the manager's literal uninstall command will remove. The identity is a
/// vnode observation, not path text.
struct HomebrewRemovalTarget: Equatable, Sendable {
    let source: HomebrewRemovalTargetSource
    let keg: DirectoryIdentity
}

/// The closed result of proving the default uninstall target. `unproven` is a typed refusal, never
/// a shortcut to launching and hoping.
enum HomebrewRemovalTargetEvidence: Equatable, Sendable {
    case proven(HomebrewRemovalTarget)
    case unproven(HomebrewRemovalTargetRefusal)
}

enum HomebrewRemovalTargetRefusal: Equatable, Sendable {
    /// The opt link is Homebrew's first choice and points at a different keg.
    case optLinkMismatch
    /// The linked-keg link is Homebrew's second choice and points at a different keg.
    case linkedKegLinkMismatch
    /// Multiple kegs are installed and neither manager link names the selected keg.
    case ambiguousMultipleKegs
    /// A manager link exists in an unusable shape (not a symlink, or dangling).
    case contradictoryEvidence
    /// The live Cellar rack could not be proven as one stable directory holding exactly the
    /// selected keg. A missing, unreadable, replaced or unstable rack, an entry the proof cannot
    /// classify, or an empty rack that the manager still reported installed all land here.
    case rackUnverified
}

/// The disclosed wall-clock bound for one Homebrew mutation (OD-M13-3). A real bottle or source
/// build legitimately exceeds the npm bound, so brew and npm do not share this number.
public let homebrewMutationTimeout: TimeInterval = 900

/// Preview disclosure for Homebrew's own target resolution (F-8). `brew upgrade` has no
/// version-selection flag, so the preview shows the manager's latest known version and states that
/// the manager re-resolves it at execution time.
public let homebrewFormulaTargetResolutionDisclosure = """
Homebrew re-resolves the target version when the upgrade runs; a version published after this preview may be installed instead.
"""

/// The exact confirm-time message when the manager's known version changed after the preview.
public let homebrewObservedTargetChangedMessage = """
Homebrew's known version for this package changed; a new preview is required.
"""

/// The exact effect text disclosed with a formula Update preview. It is presentation only.
public let homebrewFormulaUpdateEffectText = """
Homebrew will upgrade only the named formula; no other formula or cask is targeted. Homebrew chooses the target version itself when the upgrade runs, so the version shown in this preview was only the manager's latest known version at preview time and may already have changed. For this operation Homebrew's own metadata auto-update is disabled, analytics are disabled, its automatic post-upgrade cleanup is disabled, automatic removal of no-longer-needed dependencies is disabled, and its check for outdated dependent formulae is disabled so dependents are not upgraded as a side effect. The reviewed command includes --yes, so no interactive prompt is expected. Greedy-upgrade, cask-option, upgrade-quit, and automatic-removal environment overrides are not honored for this operation. Homebrew may write to its own download cache, logs, and temporary files; Agent Lens does not redirect, inspect, or delete them, and Homebrew's own defaults are used. The previously installed keg may remain installed but unlinked. No rollback, reinstall, or atomicity is guaranteed, and an interrupted or failed operation may leave a partial state that must be re-observed. The operation is bounded to 900 seconds.
"""

/// The exact effect text disclosed with a formula Uninstall preview. It is presentation only.
public let homebrewFormulaUninstallEffectText = """
Homebrew will uninstall only the named formula's currently linked keg; no other formula or cask is targeted. If another installed formula depends on it, Homebrew refuses and Agent Lens surfaces that refusal without using --ignore-dependencies and without retrying. Older kegs of this formula are not removed by this operation: they may remain installed but unlinked, the command links are not relinked to them, and the result reports them as residue rather than claiming the formula was completely removed. For this operation Homebrew's automatic cleanup is disabled, automatic removal of no-longer-needed dependencies is disabled, its own metadata auto-update is disabled, and analytics are disabled. Greedy-upgrade, cask-option, upgrade-quit, and automatic-removal environment overrides are not honored for this operation. Homebrew may write to its own download cache, logs, and temporary files; Agent Lens does not redirect, inspect, or delete them, and Homebrew's own defaults are used. No rollback, reinstall, or atomicity is guaranteed, and an interrupted or failed removal may leave a partial state that must be re-observed. The operation is bounded to 900 seconds.
"""

/// Uninstall-specific disclosure: another keg may remain installed after the linked keg is gone.
public let homebrewFormulaRemainingKegDisclosure = """
Homebrew removes only the linked keg. Older kegs of the same formula may remain installed but unlinked; the command links are not relinked to them, and this result reports them as residue.
"""

/// Uninstall-specific disclosure: Homebrew's own dependent refusal is surfaced, never bypassed.
public let homebrewFormulaDependentRefusalDisclosure = """
If another installed formula depends on this formula, Homebrew refuses the uninstall. Agent Lens surfaces that refusal and does not use --ignore-dependencies or retry.
"""

/// A fully reviewable formula Update preview. Dynamic values are plain text/arrays; `arguments` is
/// the literal argv that will be executed, never a shell command.
public struct HomebrewFormulaUpdatePreview: Equatable, Sendable {
    public let registryID: String
    public let displayName: String
    public let kind: HomebrewPackageKind
    /// The formula's rack basename, as the manager reported it.
    public let formulaName: String
    /// The manager-returned full identity (`name` or `owner/tap/name`), never a composed string.
    public let fullName: String
    public let selectedEntryPath: String
    public let selectedTarget: String
    public let selectedKegVersion: String
    /// Every keg the manager reported as installed before the operation, in a stable sorted order.
    public let installedKegs: [String]
    /// The manager's latest known target version at preview time.
    public let targetVersion: String
    /// States that Homebrew re-resolves the target when the upgrade runs.
    public let targetResolution: String
    public let pinned: Bool
    public let deprecated: Bool
    /// Plain-text deprecation disclosure (date/reason, bounded), or nil when not deprecated.
    public let deprecationDisclosure: String?
    public let managerPath: String
    /// Homebrew's own installation prefix, observed from `brew --prefix` on the verified manager
    /// and normalized through the same filesystem identity as every other proof path.
    public let prefix: String
    /// The manager-owned Cellar observed from `brew --cellar`, kept separate from `prefix`.
    public let cellar: String
    public let workingDirectory: String
    public let executablePath: String
    public let arguments: [String]
    public let timeoutSeconds: Int
    public let effect: String

    /// A readable rendering only. It is never passed to a shell.
    public var shellEscapedCommand: String {
        ([executablePath] + arguments).map(Self.shellEscaped).joined(separator: " ")
    }

    nonisolated private static func shellEscaped(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// A fully reviewable formula Uninstall preview. Dynamic values are plain text/arrays;
/// `arguments` is the literal argv that will be executed, never a shell command.
public struct HomebrewFormulaUninstallPreview: Equatable, Sendable {
    public let registryID: String
    public let displayName: String
    public let kind: HomebrewPackageKind
    public let formulaName: String
    public let fullName: String
    public let selectedEntryPath: String
    public let selectedTarget: String
    public let selectedKegVersion: String
    /// Every keg the manager reported as installed before the operation, in a stable sorted order.
    public let installedKegs: [String]
    public let remainingKegDisclosure: String
    public let dependentRefusalDisclosure: String
    public let managerPath: String
    /// Homebrew's own installation prefix, observed from `brew --prefix` on the verified manager
    /// and normalized through the same filesystem identity as every other proof path.
    public let prefix: String
    /// The manager-owned Cellar observed from `brew --cellar`, kept separate from `prefix`.
    public let cellar: String
    public let workingDirectory: String
    public let executablePath: String
    public let arguments: [String]
    public let timeoutSeconds: Int
    public let effect: String

    public var shellEscapedCommand: String {
        ([executablePath] + arguments).map(Self.shellEscaped).joined(separator: " ")
    }

    nonisolated private static func shellEscaped(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// Why formula Update preparation was refused. Every case is neutral and never authorizes a
/// mutation. Refusals happen before any scratch claim or process launch.
public enum HomebrewFormulaUpdateUnavailableReason: Equatable, Sendable {
    case operationNotAccepted
    case cancelled
    case unsupportedManager
    case noVerifiedSelection
    case identityUnverified
    case managerPrefixUnverified
    case managerUnavailable
    case operationRootUnsafe
    case pinned
    /// `disable_reason` is surfaced verbatim (bounded to 200 characters) when the manager gave one.
    case formulaDisabled(disableReason: String?)
    case unsupportedVersion
    case metadataInvalid
    case notUpdateAvailable
    case newerThanMetadata
    case budgetExhausted
    case probeFailed

    public var message: String {
        switch self {
        case .operationNotAccepted:
            return "Update is not yet accepted for this Homebrew formula. Agent Lens detects it, but no managed update has been verified for it."
        case .cancelled:
            return "Preparation was cancelled before any mutation."
        case .unsupportedManager:
            return "The selected installation is not a verified Homebrew formula."
        case .noVerifiedSelection:
            return "The selected entry does not identify a verifiable Homebrew formula."
        case .identityUnverified:
            return "The selected Homebrew formula could not be freshly verified."
        case .managerPrefixUnverified:
            return "Homebrew's installation prefix could not be verified against the selected Cellar."
        case .managerUnavailable:
            return "Homebrew is not available on the captured PATH."
        case .operationRootUnsafe:
            return "An owned operation scratch root could not be claimed safely."
        case .pinned:
            return "Homebrew reports this formula as pinned; Agent Lens never unpins it, so no update was prepared."
        case .formulaDisabled(let disableReason):
            let base = "Homebrew reports this formula as disabled; no update was prepared."
            guard let disableReason, !disableReason.isEmpty else { return base }
            return base + " Disable reason: " + disableReason
        case .unsupportedVersion:
            return "The selected keg or the manager's known target is not a supported Homebrew stable version."
        case .metadataInvalid:
            return "Fresh Homebrew formula metadata was invalid."
        case .notUpdateAvailable:
            return "No verified newer Homebrew target is available for the selected keg."
        case .newerThanMetadata:
            return "The selected keg version is newer than the manager's known target."
        case .budgetExhausted:
            return "The read-only preparation budget was exhausted."
        case .probeFailed:
            return "Fresh Homebrew verification failed."
        }
    }
}

/// Why formula Uninstall preparation was refused. Uninstall is not refused for deprecated,
/// disabled, pinned-adjacent metadata, or an unsupported stable version: removal stays valid. A
/// real pin and any pin disagreement still refuse before launch.
public enum HomebrewFormulaUninstallUnavailableReason: Equatable, Sendable {
    case operationNotAccepted
    case cancelled
    case unsupportedManager
    case noVerifiedSelection
    case identityUnverified
    case managerPrefixUnverified
    case managerUnavailable
    case operationRootUnsafe
    case pinned
    /// The exact selected keg is not provably the keg Homebrew's literal uninstall command removes.
    case uninstallRemovalTargetUnverified
    case budgetExhausted
    case probeFailed

    public var message: String {
        switch self {
        case .operationNotAccepted:
            return "Uninstall is not yet accepted for this Homebrew formula. Agent Lens detects it, but no managed uninstall has been verified for it."
        case .cancelled:
            return "Preparation was cancelled before any mutation."
        case .unsupportedManager:
            return "The selected installation is not a verified Homebrew formula."
        case .noVerifiedSelection:
            return "The selected entry does not identify a verifiable Homebrew formula."
        case .identityUnverified:
            return "The selected Homebrew formula could not be freshly verified."
        case .managerPrefixUnverified:
            return "Homebrew's installation prefix could not be verified against the selected Cellar."
        case .managerUnavailable:
            return "Homebrew is not available on the captured PATH."
        case .operationRootUnsafe:
            return "An owned operation scratch root could not be claimed safely."
        case .pinned:
            return "Homebrew reports this formula as pinned; Agent Lens never unpins it, so no uninstall was prepared."
        case .uninstallRemovalTargetUnverified:
            return "Homebrew's default uninstall target could not be proven to be the selected keg; no removal was prepared."
        case .budgetExhausted:
            return "The read-only preparation budget was exhausted."
        case .probeFailed:
            return "Fresh Homebrew verification failed."
        }
    }
}

/// Measured before/after facts for one formula Update. It is a delta, never an atomicity or
/// rollback claim. `versionMatchesTarget` and `previousKegReplaced` are independent facts: an exit
/// zero with either false is never success.
public struct HomebrewFormulaUpdateDelta: Equatable, Sendable {
    public let beforeSelectedKegVersion: String
    public let afterSelectedKegVersion: String?
    public let beforeInstalledKegs: [String]
    public let afterInstalledKegs: [String]
    /// True when the previously selected keg is still present (expected Homebrew residue, not a
    /// failure).
    public let previousKegStillPresent: Bool
    /// True only when the selected keg version actually changed.
    public let previousKegReplaced: Bool
    public let observedTargetVersion: String
    /// True only when the selected keg now names the manager's observed target.
    public let versionMatchesTarget: Bool
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
    /// True when the post-launch local or manager observation could not be completed. Never a
    /// success fact.
    public let observationFailed: Bool

    public var changed: Bool {
        beforeSelectedKegVersion != afterSelectedKegVersion
            || beforeInstalledKegs != afterInstalledKegs
            || beforeEntryPath != afterEntryPath
            || beforeTarget != afterTarget
            || beforeAliases != afterAliases
            || beforeShadowedCount != afterShadowedCount
            || beforeInstallState != afterInstallState
    }
}

/// Measured before/after facts for one formula Uninstall. It is a delta, never an atomicity or
/// rollback claim. A remaining keg is Homebrew's default behaviour and is reported as disclosed
/// residue, never as "completely removed".
public struct HomebrewFormulaUninstallDelta: Equatable, Sendable {
    public let beforeSelectedKegVersion: String
    public let afterSelectedKegVersion: String?
    public let beforeInstalledKegs: [String]
    /// The post-uninstall installed inventory, or nil when the manager query failed or was
    /// malformed. `nil` is unknown, distinct from a known-empty array.
    public let afterInstalledKegs: [String]?
    /// True only when the exact recorded `<Cellar>/<formula>/<keg>` directory was observed absent
    /// (`lstat` ENOENT/ENOTDIR), not merely unreadable.
    public let recordedKegAbsent: Bool
    /// True when a directory exists at the recorded keg path with a different identity. Never
    /// success.
    public let recordedKegReplaced: Bool
    /// True only when the selected entry no longer resolves to the recorded canonical target.
    public let selectedTargetReleased: Bool
    /// True when a dangling selected-entry symlink remains after the target was released.
    public let selectedEntryResidue: Bool
    /// True when either removal observation failed (permission, I/O, race, or wrong type). Never a
    /// success fact.
    public let observationFailed: Bool
    /// Kegs still installed after the operation, or nil when the post-uninstall manager query
    /// failed or was malformed. `nil` means unknown, never empty (Homebrew removes only the
    /// recorded keg).
    public let remainingKegs: [String]?
    /// True when a remaining keg still installs this formula (honest residue, not a success claim);
    /// nil when the residue inventory is unknown. Known-empty is `false`, not `nil`.
    public let formulaStillInstalledViaRemainingKeg: Bool?
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

    public var changed: Bool {
        beforeSelectedKegVersion != afterSelectedKegVersion
            || beforeInstalledKegs != afterInstalledKegs
            || beforeEntryPath != afterEntryPath
            || beforeTarget != afterTarget
            || beforeAliases != afterAliases
            || beforeShadowedCount != afterShadowedCount
            || beforeInstallState != afterInstallState
            || recordedKegAbsent
            || recordedKegReplaced
            || selectedTargetReleased
            || selectedEntryResidue
            || observationFailed
    }
}
