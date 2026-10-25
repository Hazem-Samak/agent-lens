// InventorySnapshot — the immutable, typed inventory the app publishes to its UI.
// M7 brief §"Proposed architecture and state contract".
//
// One entry per validated registry definition, in registry order, ALWAYS including tools that are
// missing. Each entry carries the definition that produced it beside its M5 diagnostic, so a
// display rename, a shared display name, or two tools with the same executable basename can never
// detach a diagnostic from its identity: the stable registry ID is the association and selection
// key.
//
// Nothing here is filtered, sorted, or re-derived from presentation text. A missing tool stays a
// definition with `notInstalled` facts — it is never counted as an installation. The typed Core
// facts (`ToolPathDiagnostic`, `VersionStatus`) are preserved verbatim.

import AgentLensCore
import Foundation

/// One registry tool's aggregated facts: what the registry declares, what discovery found, and
/// the optional typed update outcome.
public struct InventoryEntry: Equatable, Sendable {

    /// The definition exactly as validated from the registry: stable ID, display name,
    /// executable name, and declared extra search roots.
    public let definition: DetectorDefinition

    /// The M5 PATH diagnostic for this definition, preserved verbatim.
    public let diagnostic: ToolPathDiagnostic

    /// The complete typed M6 update result for this entry, or nil when no update probe has been
    /// performed for it. The whole result is retained — not just its tri-state `status` — so the
    /// M6 provenance (fresh probe or cache, each with its observation time) and the verified
    /// identity facts reach the UI. There is exactly one status here: it lives inside the result,
    /// so it can never drift from the facts it was derived with. Neutral outcomes stay
    /// `VersionStatus.unknown` with their typed reason; a missing probe is never rendered as
    /// "up to date".
    public let update: ToolUpdateResult?

    /// The explicit M9-B read-only ownership observation for this entry, or nil when no
    /// verification has been performed. It is cleared by every fresh local scan, including a
    /// failed rescan that retains older local facts, and preserved only when update outcomes are
    /// applied to the same unchanged snapshot. Verification is an observation, not an
    /// authorization to modify an installation.
    public let ownership: InstallationOwnershipResult?

    public init(
        definition: DetectorDefinition,
        diagnostic: ToolPathDiagnostic,
        update: ToolUpdateResult?,
        ownership: InstallationOwnershipResult?
    ) {
        self.definition = definition
        self.diagnostic = diagnostic
        self.update = update
        self.ownership = ownership
    }

    /// The typed M6 status of the retained result, or nil when no probe has been performed.
    public var updateStatus: VersionStatus? { update?.status }

    /// Where the result came from and when it was observed (M6 `UpdateProvenance`), or nil when
    /// no probe has been performed. Presentation reads this; it is never re-derived from a status.
    public var updateProvenance: UpdateProvenance? { update?.provenance }

    /// The stable registry identity — the association and selection key. Derived from the
    /// definition so the two can never drift apart; never the display name, never the executable
    /// basename, never a position in an array.
    public var registryID: String { definition.id }

    /// The tri-state installation state (D-006), taken from the diagnostic's detected tool.
    public var installState: InstallState { diagnostic.detectedTool.state }
}

/// The complete local inventory for one scan, plus the optional typed update outcomes.
public struct InventorySnapshot: Equatable, Sendable {

    /// Every registry definition in registry order, missing tools included.
    public let entries: [InventoryEntry]

    /// True when the session environment behind this snapshot was the documented degraded
    /// fallback (M2/D-005). The UI surfaces this as a warning; it is never inferred from PATH text.
    public let isDegradedEnvironment: Bool

    public init(entries: [InventoryEntry], isDegradedEnvironment: Bool) {
        self.entries = entries
        self.isDegradedEnvironment = isDegradedEnvironment
    }

    /// Every tool this build knows how to look for: definitions, NOT installations.
    public var knownToolCount: Int { entries.count }

    /// Tools whose installation state is anything other than `notInstalled`. `installedNotOnPath`
    /// counts as installed — it is a diagnostic finding, not an absence (D-006).
    public var installedToolCount: Int {
        entries.filter { $0.installState != .notInstalled }.count
    }

    /// Tools with a verified, newer known version. Only `updateAvailable` contributes: unknown
    /// comparison outcomes stay neutral (D-007) and are never counted or rendered as current.
    public var updateAvailableCount: Int {
        entries.filter { entry in
            if case .updateAvailable = entry.updateStatus { return true }
            return false
        }.count
    }
}