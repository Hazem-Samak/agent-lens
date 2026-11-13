// WorkflowPresentation — the UI-free presentation model for M12 (M12-A).
//
// Three orthogonal pieces of presentation state live here, never in Core:
//   * `listScope` picks the list's membership; `updateStatusFilter` narrows Updates only;
//   * `detailPane` picks what the detail column shows;
//   * `ToolConflict` and `ManagementPresentation` are PURE functions of one published entry, so a
//     view never re-derives a predicate and every "why not" sentence has exactly one source.
//
// Nothing here invents a fact. Conflicts are read from the accepted M5 `ToolPathDiagnostic`,
// measured versions come from `.measured` observations only, and refusal text comes from the Core
// enums themselves (read, never retyped).

import AgentLensCore

/// Which tools the list shows. Membership is scope only: the update-status filter applies after
/// it, and only when the scope is `.updates`.
public enum ListScope: Equatable, Sendable {
    /// The whole snapshot, in registry order.
    case all
    /// One registry category.
    case category(ToolCategory)
    /// Installed tools only, with tri-state update cells. Not-installed tools have no install
    /// adapter, so they never belong here.
    case updates

    /// Scope membership alone. The update-status filter is a separate, later step.
    public func includes(_ entry: InventoryEntry) -> Bool {
        switch self {
        case .all:
            return true
        case .category(let category):
            return entry.definition.category == category
        case .updates:
            // Not-installed tools have no install adapter (D-004), so they never belong in Updates.
            return entry.installState != .notInstalled
        }
    }
}

/// What the detail column shows. A pure pane switch never retargets a confirmation.
public enum DetailPane: Equatable, Sendable {
    case tool
    case diagnostics
    case settings
}

/// The Updates destination's tri-state narrowing. `.unknown` is neutral metadata and is never
/// treated as up to date; `.notChecked` means no update probe result was published at all.
public enum UpdateStatusFilter: Equatable, Sendable {
    case all
    case updateAvailable
    case upToDate
    case unknown
    case notChecked

    /// Whether one entry survives this filter. Only meaningful under `ListScope.updates`.
    public func includes(_ entry: InventoryEntry) -> Bool {
        switch self {
        case .all:
            return true
        case .updateAvailable:
            if case .updateAvailable? = entry.updateStatus { return true }
            return false
        case .upToDate:
            if case .upToDate? = entry.updateStatus { return true }
            return false
        case .unknown:
            // A neutral result is not "current" and is not "not checked": it is its own cell.
            if case .unknown? = entry.updateStatus { return true }
            return false
        case .notChecked:
            return entry.update == nil
        }
    }
}

/// The actionable conflict kinds, in the order a conflict row reports them. Aliases and repeated
/// PATH slots are diagnostics-summary facts, not conflicts: they never change which binary runs.
public enum ToolConflictKind: Equatable, Sendable, CaseIterable {
    case shadowedCopy
    case offPathCopy
    case inconsistentDiagnostics
}

/// One tool's conflict record. A tool with two kinds is ONE conflict tool; the count counts tools.
public struct ToolConflict: Equatable, Sendable {
    public let registryID: String
    public let displayName: String
    public let kinds: [ToolConflictKind]
    /// How many distinct canonical targets were observed (`canonicalTargetCount`).
    public let copyCount: Int
    /// Measured local versions only, in observation order. Never a latest version and never a
    /// fabricated value; an unmeasured target contributes nothing.
    public let localVersions: [String]
    /// The winning entry path, when the selection is a PATH winner.
    public let winnerEntryPath: String?
    /// The declared extra root that produced the off-PATH selection, when that is the selection.
    public let offPathRoot: String?
    /// The stored inconsistency reason; no winner path is invented for an inconsistent selection.
    public let inconsistencyReason: String?

    /// The non-empty kind list for one diagnostic, in the ruled order.
    public static func kinds(for diagnostic: ToolPathDiagnostic) -> [ToolConflictKind] {
        var kinds: [ToolConflictKind] = []
        if (diagnostic.shadowedInstallationCount ?? 0) > 0 {
            kinds.append(.shadowedCopy)
        }
        switch diagnostic.selection {
        case .offPath:
            kinds.append(.offPathCopy)
        case .inconsistent:
            kinds.append(.inconsistentDiagnostics)
        case .winner, .notInstalled:
            break
        }
        return kinds
    }

    /// A conflict record, or nil when the tool has no conflict kind.
    public init?(entry: InventoryEntry) {
        let diagnostic = entry.diagnostic
        let kinds = Self.kinds(for: diagnostic)
        guard !kinds.isEmpty else { return nil }
        self.registryID = entry.registryID
        self.displayName = entry.definition.displayName
        self.kinds = kinds
        self.copyCount = diagnostic.canonicalTargetCount
        // `.measured` observations only: no latest version, no fabricated value.
        self.localVersions = diagnostic.installationVersions.compactMap { observation in
            if case .measured(let version) = observation.outcome { return version }
            return nil
        }
        var winnerEntryPath: String?
        var offPathRoot: String?
        var inconsistencyReason: String?
        switch diagnostic.selection {
        case .winner(let candidate):
            winnerEntryPath = candidate.entryPath
        case .offPath(_, let root):
            offPathRoot = root
        case .inconsistent(let reason):
            inconsistencyReason = reason
        case .notInstalled:
            break
        }
        self.winnerEntryPath = winnerEntryPath
        self.offPathRoot = offPathRoot
        self.inconsistencyReason = inconsistencyReason
    }
}

/// The single source of "is a control offered, and why not" for one entry.
public struct ManagementPresentation: Equatable, Sendable {

    public enum UpdateAffordance: Equatable, Sendable {
        case prepareNpmUpdate
        case unavailable(String)
        case hidden
    }

    public enum UninstallAffordance: Equatable, Sendable {
        case prepareNpmUninstall
        case unavailable(String)
        case needsVerification(String)
        case hidden
    }

    public let update: UpdateAffordance
    public let uninstall: UninstallAffordance
    /// Manager limitations that are text, never buttons, each at most once.
    public let otherLimits: [String]

    /// Fixed contract sentences (judgment R4). Core's own `operationNotAccepted.message` strings
    /// are read from the enums below and never copied here.
    static let newerVersionWithoutManagedUpdate =
        "A newer version is reported by the supported latest check. Managed update is not available for this installation in this version."
    static let verifyToEnableUninstall =
        "Verify Installation to enable Uninstall for this npm package."
    static let homebrewFormulaLimit =
        "Homebrew formula update and uninstall are not available in this version."
    static let homebrewCaskLimit =
        "Homebrew cask update and uninstall are not available in this version."
    static let standaloneLimit =
        "This copy is classified as standalone. Agent Lens does not delete standalone files."

    public init(entry: InventoryEntry) {
        let definition = entry.definition
        let accepted = Set(definition.acceptedOperations)
        let declaredNpm = definition.packages.contains { $0.manager == .npm }

        // Update slot: the current detail-view predicate, including "no newer affordance for a
        // neutral or not-checked result".
        if case .updateAvailable? = entry.updateStatus, entry.update?.npmPackage != nil {
            self.update = accepted.contains(.npmUpdate)
                ? .prepareNpmUpdate
                : .unavailable(NpmUpdateUnavailableReason.operationNotAccepted.message)
        } else if case .updateAvailable? = entry.updateStatus {
            self.update = .unavailable(Self.newerVersionWithoutManagedUpdate)
        } else {
            self.update = .hidden
        }

        // Uninstall slot: accepted + verified npm + a selected installation, else explain. The
        // declared-npm rule matches the Manage section, which is only rendered for npm tools.
        let hasSelectedInstallation: Bool
        switch entry.diagnostic.selection {
        case .winner, .offPath:
            hasSelectedInstallation = true
        case .notInstalled, .inconsistent:
            hasSelectedInstallation = false
        }
        if accepted.contains(.npmUninstall),
           entry.ownership?.verifiedInstallation?.manager == .npm,
           hasSelectedInstallation {
            self.uninstall = .prepareNpmUninstall
        } else if declaredNpm, !accepted.contains(.npmUninstall) {
            self.uninstall = .unavailable(NpmUninstallUnavailableReason.operationNotAccepted.message)
        } else if accepted.contains(.npmUninstall) {
            self.uninstall = .needsVerification(Self.verifyToEnableUninstall)
        } else {
            self.uninstall = .hidden
        }

        // Manager limits are text, never buttons; a declared manager contributes at most once.
        var limits: [String] = []
        if entry.installState != .notInstalled {
            if definition.packages.contains(where: { $0.manager == .homebrewFormula }) {
                limits.append(Self.homebrewFormulaLimit)
            }
            if definition.packages.contains(where: { $0.manager == .homebrewCask }) {
                limits.append(Self.homebrewCaskLimit)
            }
            if entry.diagnostic.detectedTool.source == "standalone" {
                limits.append(Self.standaloneLimit)
            }
        }
        self.otherLimits = limits
    }
}
