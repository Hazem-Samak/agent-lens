// VersionStatus — M6 typed update-status models (scaffold, step 2 RED).

/// A version as observed from a tool or from manager metadata. Retains the original
/// text; strict parsing/comparison is separate (VersionComparison).
public struct Version: Equatable, Hashable, Sendable, CustomStringConvertible {
    public let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var description: String { text }
}

/// Comparison policy. Unsupported schemes never become comparable.
public enum VersionScheme: Equatable, Sendable {
    case semanticVersion
    case homebrewStable
}

public enum VersionOrdering: Equatable, Sendable {
    case older
    case equal
    case newer
}

public enum UnknownReason: Equatable, Sendable {
    case noRegistry
    case networkUnavailable
    case probeFailed
    case rateLimited
    case notChecked
    case notInstalled
    case unsupportedSource
    case installedVersionUnavailable
    case unsupportedVersion
    case managerUnavailable
    case managerMismatch
    case identityUnverified
    case diagnosticInconsistent
    case newerThanKnownMetadata
}

public enum VersionStatus: Equatable, Sendable {
    case upToDate(installed: Version, latest: Version)
    case updateAvailable(installed: Version, latest: Version)
    case unknown(installed: Version?, reason: UnknownReason)

    /// True only for a verified comparison (upToDate or updateAvailable). Unknowns are never cached.
    public var isVerifiedComparison: Bool {
        switch self {
        case .upToDate, .updateAvailable: true
        case .unknown: false
        }
    }

    /// Derives the status from verified installed and latest versions. Unsupported or
    /// incomparable texts produce unknown with the local text retained — never a guess.
    public static func evaluate(installed: Version, latest: Version, scheme: VersionScheme) -> VersionStatus {
        switch VersionComparison.ordering(installed.text, latest.text, scheme: scheme) {
        case .equal?:
            return .upToDate(installed: installed, latest: latest)
        case .older?:
            return .updateAvailable(installed: installed, latest: latest)
        case .newer?:
            // Installed is ahead of known metadata: do not imply a downgrade.
            return .unknown(installed: installed, reason: .newerThanKnownMetadata)
        case nil:
            return .unknown(installed: installed, reason: .unsupportedVersion)
        }
    }
}
