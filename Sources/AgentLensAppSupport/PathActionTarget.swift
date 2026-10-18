import Foundation
import AgentLensCore

/// Describes one of the two path rows in tool details (Selected Entry or
/// Resolved Target) and whether its value is eligible for Copy Path / Reveal
/// in Finder.
///
/// This type is purely value/policy: it does not touch the pasteboard, Finder,
/// or any native subsystem. Native effects live in `AgentLensApp`.
///
/// Eligibility is evaluated per field. A path is actionable when it is:
///   - supplied (non-nil),
///   - nonempty (after observing that a value was supplied — we do not trim
///     or otherwise reinterpret it),
///   - absolute (begins with `/`),
///   - free of any NUL character,
///   - not an unexpanded `~` home placeholder.
///
/// The literal path text is preserved verbatim (spaces, Unicode, quotes, shell
/// metacharacters, URL-reserved characters). We never synthesize a fallback.
public struct PathActionTarget: Equatable, Sendable {
    /// Which path row this target represents.
    public enum Field: Equatable, Sendable {
        case selectedEntry
        case resolvedTarget
    }

    /// Which of the two path actions to perform.
    public enum Action: Equatable, Sendable {
        case copyPath
        case revealInFinder
    }

    /// Why a field has no enabled action.
    public enum Ineligibility: Equatable, Sendable {
        case noSelection
        case notInstalled
        case inconsistent
        case missingValue
        case empty
        case relativePath
        case containsNUL
        case unexpandedTilde

        /// Concise, user-facing reason shown when an action is unavailable.
        public var reason: String {
            switch self {
            case .noSelection:
                return "No tool selected."
            case .notInstalled:
                return "This tool is not installed; no path to act on."
            case .inconsistent:
                return "Detection is inconsistent; path actions are disabled."
            case .missingValue:
                return "This path is not available."
            case .empty:
                return "This path is empty."
            case .relativePath:
                return "Path is not absolute."
            case .containsNUL:
                return "Path contains an invalid character."
            case .unexpandedTilde:
                return "Path contains an unexpanded home directory placeholder."
            }
        }
    }

    public let field: Field
    /// The literal path text as supplied, if any. Never reinterpreted.
    public let path: String?
    /// `nil` when the field is actionable; otherwise the reason it is not.
    public let ineligibility: Ineligibility?

    public var isActionable: Bool { ineligibility == nil }

    /// Initialize a target, preserving the type's own validity invariant.
    ///
    /// The caller-supplied `ineligibility` carries selection-level gates
    /// (`.noSelection`, `.notInstalled`, `.inconsistent`) and any explicit
    /// per-field reason. When it is `nil`, the constructor still independently
    /// validates the raw path shape and disables the target if the path is not
    /// a valid actionable absolute path. This guarantees no target can be
    /// constructed with `isActionable == true` for an empty, relative, tilde,
    /// NUL-containing, or absent path.
    public init(field: Field, path: String?, ineligibility: Ineligibility?) {
        self.field = field
        self.path = path
        self.ineligibility = ineligibility ?? Self.rawPathIneligibility(path)
    }

    /// Validate a single raw field value in isolation.
    ///
    /// `selection` gates whether any path action is exposed at all; when it is
    /// `.notInstalled`, `.inconsistent`, or absent, no field is actionable.
    static func ineligibility(
        forPath path: String?,
        gatedBy selection: PathSelection?
    ) -> Ineligibility? {
        if let selection {
            switch selection {
            case .winner, .offPath:
                break
            case .notInstalled:
                return .notInstalled
            case .inconsistent:
                return .inconsistent
            }
        } else {
            return .noSelection
        }

        return rawPathIneligibility(path)
    }

    /// Validate only the raw path shape (independent of the selection gate).
    /// Returns `nil` exactly when `path` is a valid actionable absolute path.
    /// This is the single shared validation helper used by both the gated
    /// derivation and the public initializer.
    static func rawPathIneligibility(_ path: String?) -> Ineligibility? {
        guard let path else { return .missingValue }
        if path.isEmpty { return .empty }
        if path.contains("\0") { return .containsNUL }
        // Unexpanded tilde: a leading `~` (own `~` or someone's `~user`) is not
        // an absolute path and must not be expanded by the GUI.
        if path.hasPrefix("~") { return .unexpandedTilde }
        if !path.hasPrefix("/") { return .relativePath }
        return nil
    }

    /// Build both targets from a full inventory entry's diagnostic selection.
    ///
    /// The `entryPath` and `canonicalTarget` come from the verified winning or
    /// off-PATH candidate; a `DetectedTool.entryPath` (which may be relative)
    /// is never consulted here. The target uses `canonicalTarget`.
    public static func targets(for entry: InventoryEntry?) -> [PathActionTarget] {
        guard let entry else {
            return [
                PathActionTarget(field: .selectedEntry, path: nil, ineligibility: .noSelection),
                PathActionTarget(field: .resolvedTarget, path: nil, ineligibility: .noSelection),
            ]
        }

        let selection = entry.diagnostic.selection
        let candidate: PathCandidateObservation?
        switch selection {
        case .winner(let c), .offPath(let c, _):
            candidate = c
        case .notInstalled, .inconsistent:
            candidate = nil
        }

        let entryPath = candidate?.entryPath
        let targetPath = candidate?.canonicalTarget

        return [
            PathActionTarget(
                field: .selectedEntry,
                path: entryPath,
                ineligibility: ineligibility(forPath: entryPath, gatedBy: selection)
            ),
            PathActionTarget(
                field: .resolvedTarget,
                path: targetPath,
                ineligibility: ineligibility(forPath: targetPath, gatedBy: selection)
            ),
        ]
    }
}
// MARK: - Dispatch / failure policy

/// The result of attempting a path action. Native effects are injected so this
/// policy is deterministic and testable without touching the pasteboard or
/// Finder.
public enum PathActionOutcome: Equatable, Sendable {
    case copied
    case clipboardFailed
    case revealed
    case revealMissing
    case ineligible(PathActionTarget.Ineligibility)
}

/// Pure dispatch of a path action through injected side-effect closures.
///
/// Copy writes the exact target text and does not consult existence: recorded
/// text remains useful after the file vanished or a rescan retained a snapshot.
/// Reveal checks existence first and, when the path is missing, returns without
/// requesting a Finder call.
public enum PathActionDispatcher {
    public static func perform(
        _ action: PathActionTarget.Action,
        target: PathActionTarget,
        pathExists: (String) -> Bool,
        writeClipboard: (String) -> Bool,
        revealInFinder: (String) -> PathActionOutcome
    ) -> PathActionOutcome {
        if let reason = target.ineligibility {
            return .ineligible(reason)
        }
        guard let path = target.path else {
            return .ineligible(.missingValue)
        }

        switch action {
        case .copyPath:
            // Copy writes the exact recorded text and deliberately does not
            // consult existence: recorded text remains useful after the file
            // vanished or a rescan retained a snapshot.
            return writeClipboard(path) ? .copied : .clipboardFailed
        case .revealInFinder:
            guard pathExists(path) else { return .revealMissing }
            return revealInFinder(path)
        }
    }
}
