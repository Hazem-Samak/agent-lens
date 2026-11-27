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
        case prepareFormulaUpdate
        case prepareCaskUpdate
        case unavailable(String)
        case hidden

        /// True only for the actionable prepare shapes. The menu bar uses this instead of naming
        /// one manager, so a promoted Homebrew operation keeps the accepted shortcut wiring.
        public var isPrepare: Bool {
            switch self {
            case .prepareNpmUpdate, .prepareFormulaUpdate, .prepareCaskUpdate:
                return true
            case .unavailable, .hidden:
                return false
            }
        }
    }

    public enum UninstallAffordance: Equatable, Sendable {
        case prepareNpmUninstall
        case prepareFormulaUninstall
        case prepareCaskUninstall
        case unavailable(String)
        case needsVerification(String)
        case hidden

        public var isPrepare: Bool {
            switch self {
            case .prepareNpmUninstall, .prepareFormulaUninstall, .prepareCaskUninstall:
                return true
            case .unavailable, .needsVerification, .hidden:
                return false
            }
        }
    }

    public let update: UpdateAffordance
    public let uninstall: UninstallAffordance
    /// Manager limitations that are text, never buttons, each at most once.
    public let otherLimits: [String]

    /// Fixed contract sentences (judgment R4/R11). Core's own `operationNotAccepted.message`
    /// strings are read from the enums below and never copied here; the former fixed Homebrew
    /// "not available in this version" sentences are gone, replaced by those per-entry reasons.
    static let newerVersionWithoutManagedUpdate =
        "A newer version is reported by the supported latest check. Managed update is not available for this installation in this version."
    static let verifyToEnableUninstall =
        "Verify Installation to enable Uninstall for this npm package."
    static let verifyToEnableFormulaUninstall =
        "Verify Installation to enable Uninstall for this Homebrew formula."
    static let verifyToEnableCaskUninstall =
        "Verify Installation to enable Uninstall for this Homebrew cask."
    static let standaloneLimit =
        "This copy is classified as standalone. Agent Lens does not delete standalone files."

    public init(entry: InventoryEntry) {
        let definition = entry.definition
        let accepted = Set(definition.acceptedOperations)
        let declaredNpm = definition.packages.contains { $0.manager == .npm }
        let declaredFormula = definition.packages.contains { $0.manager == .homebrewFormula }
        let declaredCask = definition.packages.contains { $0.manager == .homebrewCask }
        let declaredPip = definition.packages.contains { $0.manager == .pip }

        // Update slot: the accepted npm predicate first (byte-identical), then the Homebrew result
        // only when its own manager-verified identity and observed selection agree with the
        // declared manager kind and the accepted operation.
        if case .updateAvailable? = entry.updateStatus, entry.update?.npmPackage != nil {
            self.update = accepted.contains(.npmUpdate)
                ? .prepareNpmUpdate
                : .unavailable(NpmUpdateUnavailableReason.operationNotAccepted.message)
        } else if case .updateAvailable? = entry.updateStatus,
                  let kind = Self.verifiedHomebrewUpdateKind(entry) {
            switch kind {
            case .formula:
                self.update = accepted.contains(.homebrewFormulaUpdate)
                    ? .prepareFormulaUpdate
                    : .unavailable(
                        HomebrewFormulaUpdateUnavailableReason.operationNotAccepted.message
                    )
            case .cask:
                self.update = accepted.contains(.homebrewCaskUpdate)
                    ? .prepareCaskUpdate
                    : .unavailable(
                        HomebrewCaskUpdateUnavailableReason.operationNotAccepted.message
                    )
            }
        } else if case .updateAvailable? = entry.updateStatus {
            self.update = .unavailable(Self.newerVersionWithoutManagedUpdate)
        } else {
            self.update = .hidden
        }

        // Uninstall slot: the exactly verified manager decides its own removal route; otherwise the
        // declared managers explain themselves. npm keeps its accepted predicates, order and
        // sentences; each Homebrew kind reads its own Core reason. An unrelated declaration can
        // never shadow the manager this entry's own proof names.
        let verifiedManager = Self.exactVerifiedManager(entry: entry)
        let installed = entry.installState != .notInstalled
        if installed, let verifiedManager {
            self.uninstall = Self.verifiedUninstall(manager: verifiedManager, accepted: accepted)
        } else if declaredNpm, !accepted.contains(.npmUninstall) {
            self.uninstall = .unavailable(NpmUninstallUnavailableReason.operationNotAccepted.message)
        } else if accepted.contains(.npmUninstall) {
            self.uninstall = .needsVerification(Self.verifyToEnableUninstall)
        } else if installed, declaredFormula {
            self.uninstall = Self.formulaUninstall(
                accepted: accepted.contains(.homebrewFormulaUninstall)
            )
        } else if installed, declaredCask {
            self.uninstall = Self.caskUninstall(
                accepted: accepted.contains(.homebrewCaskUninstall)
            )
        } else {
            self.uninstall = .hidden
        }

        // Manager limits are text, never buttons; a declared manager contributes at most once. A
        // manager that is not promoted says why through the matching Core reason, and a reason the
        // update/uninstall slot already shows is not repeated here.
        var limits: [String] = []
        if entry.installState != .notInstalled {
            if declaredFormula, let limit = Self.formulaLimit(accepted: accepted),
               self.update != .unavailable(limit), self.uninstall != .unavailable(limit) {
                limits.append(limit)
            }
            if declaredCask, let limit = Self.caskLimit(accepted: accepted),
               self.update != .unavailable(limit), self.uninstall != .unavailable(limit) {
                limits.append(limit)
            }
            // Homebrew's cask proof is the exact ownership observation, not the source heuristic: a
            // verified cask copy is Homebrew-owned, so it is never described as standalone-deletable.
            if entry.diagnostic.detectedTool.source == "standalone",
               verifiedManager != .homebrewCask,
               verifiedManager != .uvTool,
               verifiedManager != .pip {
                limits.append(Self.standaloneLimit)
            }
            if declaredPip, verifiedManager == nil || verifiedManager == .pip {
                limits.append(
                    "pip environments are read-only diagnostics; no update or uninstall is available."
                )
            }
        }
        self.otherLimits = limits
    }

    /// The manager kind of a published `updateAvailable` Homebrew result, or nil when this entry has
    /// no exact Homebrew update route.
    ///
    /// The result is evidence for THIS entry only: its registry ID and the selection it observed
    /// must equal the registry ID and the observed selection pair the diagnostics publish now. The
    /// coordinator fills exactly one identity shape — formula stem plus full formula name, or cask
    /// token plus full cask token — so a result carrying both shapes is contradictory evidence and
    /// proves neither manager. The registry declaration must name that kind; a declaration or the
    /// `standalone` source heuristic is never proof by itself. npm keeps its accepted predicate and
    /// is handled separately.
    static func verifiedHomebrewUpdateKind(_ entry: InventoryEntry) -> HomebrewPackageKind? {
        guard case .updateAvailable? = entry.updateStatus,
              let update = entry.update,
              update.registryID == entry.registryID,
              update.npmPackage == nil,
              update.managerEntryPath != nil,
              update.managerTarget != nil,
              let selected = entry.diagnostic.observedSelectionPair,
              update.selectedEntryPath == selected.entry,
              update.selectedTarget == selected.target
        else { return nil }
        let formulaEvidence = update.formulaStem != nil && update.fullFormulaName != nil
        let caskEvidence = update.caskToken != nil && update.caskFullToken != nil
        // Exactly one shape, or the result proves nothing.
        guard formulaEvidence != caskEvidence else { return nil }
        if caskEvidence {
            return Self.declares(.homebrewCask, definition: entry.definition) ? .cask : nil
        }
        return Self.declares(.homebrewFormula, definition: entry.definition) ? .formula : nil
    }

    /// The package manager this entry's own verification observation proves for the selection the
    /// diagnostics publish right now, or nil when there is no exact proof.
    ///
    /// A registry declaration is not proof, the `standalone` source heuristic is not proof, and an
    /// observation for another registry entry or for a selection the diagnostics no longer publish
    /// is not this entry's proof. The operation boundary re-checks the same registry ID and the same
    /// entry/target pair before Core runs anything, so the control offered here and the mutation
    /// that is authorized can never disagree about which selection they mean.
    private static func verifiedManager(entry: InventoryEntry) -> PackageManager? {
        guard let ownership = entry.ownership,
              ownership.registryID == entry.registryID,
              let installation = ownership.verifiedInstallation,
              let selected = entry.diagnostic.observedSelectionPair,
              installation.selection.entryPath == selected.entry,
              installation.selection.canonicalTarget == selected.target
        else { return nil }
        return installation.manager
    }

    /// The exactly verified manager for this entry's current selection when the registry also
    /// declares that manager. The removal affordance and the removal preparation gate both read
    /// this one predicate, so a control is offered exactly when a preparation can start.
    static func exactVerifiedManager(entry: InventoryEntry) -> PackageManager? {
        guard let manager = verifiedManager(entry: entry),
              declares(manager, definition: entry.definition)
        else { return nil }
        return manager
    }

    private static func declares(
        _ manager: PackageManager,
        definition: DetectorDefinition
    ) -> Bool {
        definition.packages.contains { $0.manager == manager }
    }

    /// The route owned by an exactly verified manager. The verified kind selects its own operation
    /// grant; another manager's grant never authorizes it.
    private static func verifiedUninstall(
        manager: PackageManager,
        accepted: Set<AcceptedOperation>
    ) -> UninstallAffordance {
        switch manager {
        case .npm:
            return accepted.contains(.npmUninstall)
                ? .prepareNpmUninstall
                : .unavailable(NpmUninstallUnavailableReason.operationNotAccepted.message)
        case .homebrewFormula:
            return accepted.contains(.homebrewFormulaUninstall)
                ? .prepareFormulaUninstall
                : .unavailable(
                    HomebrewFormulaUninstallUnavailableReason.operationNotAccepted.message
                )
        case .homebrewCask:
            return accepted.contains(.homebrewCaskUninstall)
                ? .prepareCaskUninstall
                : .unavailable(
                    HomebrewCaskUninstallUnavailableReason.operationNotAccepted.message
                )
        case .uvTool, .pip:
            // M14-B has no Python mutation vocabulary or grant. Pip remains informational by
            // construction; uv actions arrive only in a later phase with an explicit grant.
            return .hidden
        }
    }

    /// A declared Homebrew kind's own removal route when no exact proof exists: the accepted
    /// operation offers the manager-appropriate verification hint, and its absence shows that
    /// manager's own Core reason. Never an armed control.
    private static func formulaUninstall(accepted: Bool) -> UninstallAffordance {
        accepted
            ? .needsVerification(Self.verifyToEnableFormulaUninstall)
            : .unavailable(HomebrewFormulaUninstallUnavailableReason.operationNotAccepted.message)
    }

    private static func caskUninstall(accepted: Bool) -> UninstallAffordance {
        accepted
            ? .needsVerification(Self.verifyToEnableCaskUninstall)
            : .unavailable(HomebrewCaskUninstallUnavailableReason.operationNotAccepted.message)
    }

    private static func formulaLimit(accepted: Set<AcceptedOperation>) -> String? {
        if !accepted.contains(.homebrewFormulaUpdate) {
            return HomebrewFormulaUpdateUnavailableReason.operationNotAccepted.message
        }
        if !accepted.contains(.homebrewFormulaUninstall) {
            return HomebrewFormulaUninstallUnavailableReason.operationNotAccepted.message
        }
        return nil
    }

    private static func caskLimit(accepted: Set<AcceptedOperation>) -> String? {
        if !accepted.contains(.homebrewCaskUpdate) {
            return HomebrewCaskUpdateUnavailableReason.operationNotAccepted.message
        }
        if !accepted.contains(.homebrewCaskUninstall) {
            return HomebrewCaskUninstallUnavailableReason.operationNotAccepted.message
        }
        return nil
    }
}

extension ToolPathDiagnostic {
    /// The exact selection this diagnostic publishes: the selected entry path and its non-empty
    /// canonical target, or nil when the tool has no live selection. Both the affordance model and
    /// the operation boundary compare their evidence against this one pair, so a verified control
    /// and the service's pre-launch re-check can never disagree about which selection they mean.
    var observedSelectionPair: (entry: String, target: String)? {
        let candidate: PathCandidateObservation
        switch selection {
        case .winner(let value): candidate = value
        case .offPath(let value, _): candidate = value
        case .notInstalled, .inconsistent: return nil
        }
        guard let target = candidate.canonicalTarget, !target.isEmpty else { return nil }
        return (candidate.entryPath, target)
    }
}
