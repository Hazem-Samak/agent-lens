// InstallationVersionObservation — one local version fact per observed canonical installation.
//
// A version is never inferred from a path, a registry declaration, another alias or a search
// result. Each value is bound to the executable entry and canonical target that were observed
// around the bounded local query. Unknown is a first-class neutral outcome with a typed reason.

import Foundation

/// Why one canonical installation has no known local version. The current bounded query seam
/// returns `String?`, so it cannot truthfully distinguish exit, timeout, output-cap or no-token
/// failures; `.queryFailed` intentionally covers all of them.
public enum InstallationVersionUnknownReason: String, Equatable, Sendable, CaseIterable {
    case executableUnavailable
    case identityChanged
    case queryFailed
    case budgetExhausted

    public var message: String {
        switch self {
        case .executableUnavailable:
            "the executable was unavailable when observed"
        case .identityChanged:
            "the executable identity changed during observation"
        case .queryFailed:
            "the version query failed or returned no version"
        case .budgetExhausted:
            "the version probe budget was exhausted before this installation could be queried"
        }
    }
}

public enum InstallationVersionOutcome: Equatable, Sendable {
    case measured(String)
    case unknown(InstallationVersionUnknownReason)

    /// The measured version, or nil for every neutral unknown.
    public var version: String? {
        if case .measured(let version) = self { return version }
        return nil
    }

    public var unknownReason: InstallationVersionUnknownReason? {
        if case .unknown(let reason) = self { return reason }
        return nil
    }
}

/// One observation for one canonical executable target. `entryPath` is the representative entry
/// used for the query (or the entry that would have been used when the budget prevented it).
/// `origin` is the discovery origin observed when the representative entry was inspected; it is
/// retained independently of whether the target remains the current selection. `fingerprint` is
/// present when a live executable identity was observed; a known measurement is only published
/// when the before/after/revalidation observations agree on it.
public struct InstallationVersionObservation: Equatable, Sendable {
    public let canonicalTarget: String
    public let entryPath: String
    public let origin: PathCandidateOrigin
    public let fingerprint: ExecutableFingerprint?
    public let outcome: InstallationVersionOutcome

    public init(
        canonicalTarget: String,
        entryPath: String,
        origin: PathCandidateOrigin,
        fingerprint: ExecutableFingerprint?,
        outcome: InstallationVersionOutcome
    ) {
        self.canonicalTarget = canonicalTarget
        self.entryPath = entryPath
        self.origin = origin
        self.fingerprint = fingerprint
        self.outcome = outcome
    }

    public var version: String? { outcome.version }
}
