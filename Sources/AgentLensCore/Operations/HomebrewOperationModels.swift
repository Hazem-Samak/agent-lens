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

// MARK: - M13-E Homebrew cask operations

/// The only cask artifact kinds Agent Lens will manage. `binary` and `command_wrapper` both stage
/// one regular executable file and link one target; app bundles and every other artifact kind are
/// outside the product support boundary (R7).
public enum HomebrewCaskArtifactKind: String, Equatable, Sendable {
    case binary
    case commandWrapper = "command_wrapper"
}

/// Whether the manager-declared target was observed as a live link to this cask's staged source at
/// preview time. `absent` means the exact target path did not exist; the destination is still the
/// manager's own resolved target from fresh metadata, never a composed guess.
public enum HomebrewCaskTargetPresence: String, Equatable, Sendable {
    case linked
    case absent
}

/// One manager-declared CLI artifact target. `target` is the manager's resolved absolute
/// destination, not a product-composed default.
public struct HomebrewCaskArtifactTarget: Equatable, Sendable {
    public let kind: HomebrewCaskArtifactKind
    public let target: String
    public let presence: HomebrewCaskTargetPresence
}

/// Cask target resolution disclosure. A cask upgrade has no version-selection flag; the manager
/// re-resolves its own latest known version when the mutation runs.
public let homebrewCaskTargetResolutionDisclosure = """
Homebrew re-resolves the cask's target version when the upgrade runs; a version published after this preview may be installed instead.
"""

/// The exact effect text disclosed with a cask Update preview. It is presentation only.
public let homebrewCaskUpdateEffectText = """
Homebrew will upgrade only the named cask, including every command-line artifact target listed in this preview; no other cask or formula is targeted. Homebrew chooses the cask's target version itself when the upgrade runs, so the version shown in this preview was only the manager's latest known version at preview time and may already have changed. This support boundary accepts only casks whose fresh metadata and saved installed definition or install receipt declare binary or command_wrapper artifacts, with no app artifact and no uninstall stanza, and whose install receipt declares no uninstall flight blocks. A cask whose fresh metadata declares formula or cask package dependencies is refused before launch rather than allowing the upgrade to install those packages. Agent Lens forces HOMEBREW_NO_SUDO=1 for this cask operation, does not pass SUDO_ASKPASS or HOMEBREW_SUDO_THROUGH_SUDO_USER, and never elevates or enters a password. Agent Lens does not run the zap step and does not ask Homebrew to clean the configuration and caches named by zap; a path listed as a managed CLI artifact remains a removal target even if a zap stanza names the same path. For this operation Homebrew's own metadata auto-update is disabled, analytics are disabled, its automatic post-upgrade cleanup is disabled, automatic removal of no-longer-needed dependencies is disabled, and its check for outdated dependent formulae is disabled so dependents are not upgraded as a side effect. The reviewed command includes --yes, so no interactive prompt is expected. Greedy-upgrade, cask-option, upgrade-quit, and automatic-removal environment overrides are not honored for this operation. Homebrew may write to its own download cache, logs, and temporary files; Agent Lens does not redirect, inspect, or delete them, and Homebrew's own defaults are used. No rollback, reinstall, or atomicity is guaranteed, and an interrupted or failed operation may leave a partial state that must be re-observed. The operation is bounded to 900 seconds.
"""

/// The exact effect text disclosed with a cask Uninstall preview. It is presentation only.
public let homebrewCaskUninstallEffectText = """
Homebrew will uninstall only the named cask, including every command-line artifact target listed in this preview; no other cask or formula is targeted. Cask removal may remove a companion app, not only the selected CLI. This support boundary accepts only casks whose fresh metadata and saved installed definition or install receipt declare binary or command_wrapper artifacts, with no app artifact and no uninstall stanza, and whose install receipt declares no uninstall flight blocks, so this operation is limited to the listed CLI artifact targets and the cask's staged files. Agent Lens forces HOMEBREW_NO_SUDO=1 for this cask operation, does not pass SUDO_ASKPASS or HOMEBREW_SUDO_THROUGH_SUDO_USER, and never elevates or enters a password. Agent Lens does not run the zap step and does not ask Homebrew to clean the configuration and caches named by zap; a path listed as a managed CLI artifact remains a removal target even if a zap stanza names the same path. For this operation Homebrew's automatic cleanup is disabled, automatic removal of no-longer-needed dependencies is disabled, its own metadata auto-update is disabled, and analytics are disabled. Greedy-upgrade, cask-option, upgrade-quit, and automatic-removal environment overrides are not honored for this operation. Homebrew may write to its own download cache, logs, and temporary files; Agent Lens does not redirect, inspect, or delete them, and Homebrew's own defaults are used. No rollback, reinstall, or atomicity is guaranteed, and an interrupted or failed removal may leave a partial state that must be re-observed. The operation is bounded to 900 seconds.
"""

/// Whole-cask scope disclosure shared by both previews.
public let homebrewCaskArtifactScopeDisclosure = """
This operation targets the whole named cask, including every current-source and verified installed command-line artifact target listed here; no other cask is targeted.
"""

/// Uninstall-specific scope disclosure. Uninstall acts on Homebrew's saved installed definition, so
/// it cannot promise anything about current-source targets that are not installed.
public let homebrewCaskUninstallArtifactScopeDisclosure = """
This operation targets the whole named cask, including every verified installed command-line artifact target listed here; no other cask is targeted.
"""

/// Companion-app consequence disclosed even when this supported CLI-only cask declares no app.
public let homebrewCaskCompanionAppDisclosure = """
Cask removal may remove a companion app, not only the selected CLI.
"""

/// The zap exclusion disclosed by every cask preview. Agent Lens does not run zap; it makes no
/// claim that a zap-declared path could never coincide with a managed artifact.
public let homebrewCaskZapExclusionDisclosure = """
Agent Lens does not run the zap step and does not ask Homebrew to clean the configuration and caches named by zap. A path listed as a managed CLI artifact remains a removal target even if a zap stanza names the same path.
"""

/// A fully reviewable cask Update preview. Dynamic values are plain text/arrays; `arguments` is the
/// literal argv that will be executed, never a shell command.
public struct HomebrewCaskUpdatePreview: Equatable, Sendable {
    public let registryID: String
    public let displayName: String
    public let kind: HomebrewPackageKind
    /// The manager's bare cask token.
    public let token: String
    /// The manager-returned full identity (`token` or `owner/tap/token`), never a composed string.
    public let fullToken: String
    /// The manager-reported tap.
    public let tap: String
    public let selectedEntryPath: String
    public let selectedTarget: String
    /// The manager's installed version directory, an opaque string.
    public let installedVersion: String
    /// The manager's latest known target version, an opaque string (comma forms are allowed).
    public let targetVersion: String
    /// States that Homebrew re-resolves the cask target when the upgrade runs.
    public let targetResolution: String
    public let pinned: Bool
    public let deprecated: Bool
    /// Plain-text deprecation disclosure (date/reason, bounded), or nil when not deprecated.
    public let deprecationDisclosure: String?
    /// Every manager-declared CLI artifact target with the presence observed at preview time.
    public let artifactTargets: [HomebrewCaskArtifactTarget]
    public let artifactScopeDisclosure: String
    /// True when fresh metadata declared a zap stanza. It is disclosed and never executed.
    public let zapDeclared: Bool
    public let zapDisclosure: String
    public let managerPath: String
    /// Homebrew's own installation prefix, normalized through the same identity as every proof.
    public let prefix: String
    /// The manager-owned Caskroom observed from `brew --caskroom`, kept separate from the prefix.
    public let caskroom: String
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

/// A fully reviewable cask Uninstall preview. Dynamic values are plain text/arrays; `arguments` is
/// the literal argv that will be executed, never a shell command.
public struct HomebrewCaskUninstallPreview: Equatable, Sendable {
    public let registryID: String
    public let displayName: String
    public let kind: HomebrewPackageKind
    public let token: String
    public let fullToken: String
    public let tap: String
    public let selectedEntryPath: String
    public let selectedTarget: String
    public let installedVersion: String
    public let deprecated: Bool
    public let deprecationDisclosure: String?
    public let artifactTargets: [HomebrewCaskArtifactTarget]
    public let artifactScopeDisclosure: String
    public let companionAppDisclosure: String
    public let zapDeclared: Bool
    public let zapDisclosure: String
    public let managerPath: String
    public let prefix: String
    public let caskroom: String
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

/// Why cask Update preparation was refused. Every case is neutral and never authorizes a mutation.
public enum HomebrewCaskUpdateUnavailableReason: Equatable, Sendable {
    case operationNotAccepted
    case cancelled
    case unsupportedManager
    case noVerifiedSelection
    case identityUnverified
    case managerPrefixUnverified
    case caskroomUnverified
    case managerUnavailable
    case operationRootUnsafe
    case pinned
    case caskDisabled(disableReason: String?)
    case caskAutoUpdates
    case caskTracksLatest
    /// The cask declares an app or another artifact kind outside the CLI-only support boundary.
    case caskOperationUnsupported
    /// The cask declares an uninstall stanza that Homebrew may elevate or run interactively.
    case caskUninstallRequiresElevation
    /// A manager-declared artifact target was not a safe, accurate link to this cask's source.
    case caskArtifactTargetUnverified
    case metadataInvalid
    case caskMetadataInconsistent
    case notUpdateAvailable
    case budgetExhausted
    case probeFailed

    public var message: String {
        switch self {
        case .operationNotAccepted:
            return "Update is not yet accepted for this Homebrew cask. Agent Lens detects it, but no managed update has been verified for it."
        case .cancelled:
            return "Preparation was cancelled before any mutation."
        case .unsupportedManager:
            return "The selected installation is not a verified Homebrew cask."
        case .noVerifiedSelection:
            return "The selected entry does not identify a verifiable Homebrew cask."
        case .identityUnverified:
            return "The selected Homebrew cask could not be freshly verified."
        case .managerPrefixUnverified:
            return "Homebrew's installation prefix could not be verified."
        case .caskroomUnverified:
            return "Homebrew's Caskroom could not be verified against the selected cask."
        case .managerUnavailable:
            return "Homebrew is not available on the captured PATH."
        case .operationRootUnsafe:
            return "An owned operation scratch root could not be claimed safely."
        case .pinned:
            return "Homebrew reports this cask as pinned; Agent Lens never unpins it, so no update was prepared."
        case .caskDisabled(let disableReason):
            let base = "Homebrew reports this cask as disabled; no update was prepared."
            guard let disableReason, !disableReason.isEmpty else { return base }
            return base + " Disable reason: " + disableReason
        case .caskAutoUpdates:
            return "Homebrew reports this cask as self-updating (auto_updates true); Agent Lens refuses to manage its update."
        case .caskTracksLatest:
            return "This cask tracks the mutable latest version; Agent Lens cannot verify a specific update target."
        case .caskOperationUnsupported:
            return "This cask declares an app, a formula or cask dependency, or another artifact outside Agent Lens's supported CLI-only cask boundary; no mutation was prepared."
        case .caskUninstallRequiresElevation:
            return "This cask declares an uninstall stanza that Homebrew may run with elevation or interactively; Agent Lens never escalates, so no mutation was prepared."
        case .caskArtifactTargetUnverified:
            return "The cask's managed CLI artifact targets could not be verified safely; no mutation was prepared."
        case .metadataInvalid:
            return "Fresh Homebrew cask metadata was invalid."
        case .caskMetadataInconsistent:
            return "Homebrew's installed and latest cask version strings disagree without an outdated verdict."
        case .notUpdateAvailable:
            return "Homebrew does not report a verified newer version for this cask."
        case .budgetExhausted:
            return "The read-only preparation budget was exhausted."
        case .probeFailed:
            return "Fresh Homebrew verification failed."
        }
    }
}

/// Why cask Uninstall preparation was refused. Uninstall is not refused for deprecated, disabled,
/// auto_updates, `latest`, or comma versions: removal stays valid. A real pin and any pin
/// disagreement still refuse before launch, and the R7 support boundary still applies.
public enum HomebrewCaskUninstallUnavailableReason: Equatable, Sendable {
    case operationNotAccepted
    case cancelled
    case unsupportedManager
    case noVerifiedSelection
    case identityUnverified
    case managerPrefixUnverified
    case caskroomUnverified
    case managerUnavailable
    case operationRootUnsafe
    case pinned
    case caskOperationUnsupported
    case caskUninstallRequiresElevation
    case caskArtifactTargetUnverified
    case metadataInvalid
    case budgetExhausted
    case probeFailed

    public var message: String {
        switch self {
        case .operationNotAccepted:
            "Uninstall is not yet accepted for this Homebrew cask. Agent Lens detects it, but no managed uninstall has been verified for it."
        case .cancelled:
            "Preparation was cancelled before any mutation."
        case .unsupportedManager:
            "The selected installation is not a verified Homebrew cask."
        case .noVerifiedSelection:
            "The selected entry does not identify a verifiable Homebrew cask."
        case .identityUnverified:
            "The selected Homebrew cask could not be freshly verified."
        case .managerPrefixUnverified:
            "Homebrew's installation prefix could not be verified."
        case .caskroomUnverified:
            "Homebrew's Caskroom could not be verified against the selected cask."
        case .managerUnavailable:
            "Homebrew is not available on the captured PATH."
        case .operationRootUnsafe:
            "An owned operation scratch root could not be claimed safely."
        case .pinned:
            "Homebrew reports this cask as pinned; Agent Lens never unpins it, so no uninstall was prepared."
        case .caskOperationUnsupported:
            "This cask declares an app or another artifact outside Agent Lens's supported CLI-only cask boundary; no mutation was prepared."
        case .caskUninstallRequiresElevation:
            "This cask declares an uninstall stanza that Homebrew may run with elevation or interactively; Agent Lens never escalates, so no mutation was prepared."
        case .caskArtifactTargetUnverified:
            "The cask's managed CLI artifact targets could not be verified safely; no removal was prepared."
        case .metadataInvalid:
            "Fresh Homebrew cask metadata was invalid."
        case .budgetExhausted:
            "The read-only preparation budget was exhausted."
        case .probeFailed:
            "Fresh Homebrew verification failed."
        }
    }
}

/// How one previewed managed target behaved during reconciliation. `successor` means this cask's
/// recorded link was released but a different destination now occupies the path; it is never
/// described as this cask's target. `retargeted` means the path now links into the verified new
/// staged version (an Update-only success fact).
public enum HomebrewCaskManagedTargetRelease: String, Equatable, Sendable {
    case released
    case successor
    case retargeted
    case stillPresent
    case absentAtPreview
    /// The path was absent at preview but is now occupied by something this operation cannot
    /// explain. Never a clean removal fact.
    case occupiedAfterAbsentPreview
    case observationFailed

    /// A real before/after difference, never an unknown or a false success predicate.
    var isBeforeAfterDifference: Bool {
        switch self {
        case .released, .successor, .retargeted, .occupiedAfterAbsentPreview:
            return true
        case .stillPresent, .absentAtPreview, .observationFailed:
            return false
        }
    }

    /// The release shapes that do not leave this cask's old artifact at the path.
    var isReleased: Bool {
        switch self {
        case .released, .successor, .retargeted, .absentAtPreview:
            return true
        case .stillPresent, .occupiedAfterAbsentPreview, .observationFailed:
            return false
        }
    }
}

/// One managed target's measured release fact.
public struct HomebrewCaskManagedTargetDelta: Equatable, Sendable {
    public let kind: HomebrewCaskArtifactKind
    public let target: String
    public let release: HomebrewCaskManagedTargetRelease
}

/// Measured before/after facts for one cask Update. It is a delta, never an atomicity or rollback
/// claim. `versionMatchesTarget`, `tokenMatches`, and `stagedMembershipConfirmed` are independent
/// facts: an exit zero with any false is never success.
public struct HomebrewCaskUpdateDelta: Equatable, Sendable {
    public let beforeInstalledVersion: String
    public let afterInstalledVersion: String?
    public let observedTargetVersion: String
    public let versionMatchesTarget: Bool
    public let tokenMatches: Bool
    public let afterToken: String?
    public let afterFullToken: String?
    public let afterTap: String?
    /// True only when fresh ownership verification confirms staged membership for the same full
    /// token, the same prefix, and the observed installed version directory.
    public let stagedMembershipConfirmed: Bool
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
    /// Every previously installed managed target disclosed by the preview, reconciled after the
    /// launch. A still-present old link or an unreadable path is never success.
    public let managedTargets: [HomebrewCaskManagedTargetDelta]
    /// True when the post-launch local or manager observation could not be completed. Never a
    /// success fact.
    public let observationFailed: Bool

    /// No previously installed target still links to this cask's old staged source and every
    /// observation completed.
    public var managedTargetsReleased: Bool {
        managedTargets.allSatisfy { $0.release.isReleased }
    }

    public var changed: Bool {
        // An unobserved after-version is not a difference; unknown outcomes stay uncertain.
        (afterInstalledVersion.map { $0 != beforeInstalledVersion } ?? false)
            || beforeEntryPath != afterEntryPath
            || beforeTarget != afterTarget
            || beforeAliases != afterAliases
            || beforeShadowedCount != afterShadowedCount
            || beforeInstallState != afterInstallState
            || managedTargets.contains { $0.release.isBeforeAfterDifference }
    }
}

/// Measured before/after facts for one cask Uninstall. It is a delta, never an atomicity or
/// rollback claim. `infoInstalledAbsent`, `tokenDirectoryAbsent`, `selectedTargetReleased`, and
/// `managedTargetsReleased` are independent facts: an exit zero with any false is never success.
public struct HomebrewCaskUninstallDelta: Equatable, Sendable {
    public let beforeInstalledVersion: String
    public let afterInstalledVersion: String?
    /// True only when fresh manager metadata returns `installed: null` or no record for the exact
    /// token. A failed or malformed query is never absence.
    public let infoInstalledAbsent: Bool
    /// True only when the exact original `<Caskroom>/<token>` directory was observed absent
    /// (`lstat` ENOENT/ENOTDIR), not merely unreadable.
    public let tokenDirectoryAbsent: Bool
    /// True when a directory exists at the recorded token path with a different identity.
    public let tokenDirectoryReplaced: Bool
    /// True only when the selected entry no longer resolves to the recorded canonical target.
    public let selectedTargetReleased: Bool
    /// True when a dangling selected-entry symlink remains after the target was released.
    public let selectedEntryResidue: Bool
    public let managedTargets: [HomebrewCaskManagedTargetDelta]
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
    public let observationFailed: Bool

    /// A previewed target that was absent before the operation imposes no after-fact only while it
    /// is still absent. A successor released this cask's link and is not reported as this cask's
    /// residue; a path that was absent is never silently accepted as clean when it is now occupied.
    public var managedTargetsReleased: Bool {
        managedTargets.allSatisfy { $0.release.isReleased }
    }

    public var changed: Bool {
        // An unobserved after-version is not a difference; unknown outcomes stay uncertain.
        (afterInstalledVersion.map { $0 != beforeInstalledVersion } ?? false)
            || beforeEntryPath != afterEntryPath
            || beforeTarget != afterTarget
            || beforeAliases != afterAliases
            || beforeShadowedCount != afterShadowedCount
            || beforeInstallState != afterInstallState
            || infoInstalledAbsent
            || tokenDirectoryAbsent
            || tokenDirectoryReplaced
            || selectedTargetReleased
            || selectedEntryResidue
            || managedTargets.contains { $0.release.isBeforeAfterDifference }
    }
}
