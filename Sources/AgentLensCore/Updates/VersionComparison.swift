// VersionComparison — M6 pure version parsing and ordering (brief §"Model and comparison contract").
//
// Strict Semantic Versioning 2.0.0 for CLI/npm-style versions, plus a narrow Homebrew
// stable-version policy (`upstream[_revision]`). Anything outside these grammars is
// unsupported: it returns nil, never a lexical guess. No external dependency; no
// fixed-width integer parsing (magnitudes compare as normalized digit strings).

public struct SemanticVersion: Equatable, Sendable {
    public let major: String
    public let minor: String
    public let patch: String
    public let prerelease: [String]
    public let build: [String]
}

public struct HomebrewStableVersion: Equatable, Sendable {
    /// The stable upstream version with two or three numeric components (the
    /// original text, before any revision suffix).
    public let upstreamText: String
    /// The Homebrew package revision; 0 when absent.
    public let revision: Int
    /// Upstream numeric components normalized to three (two-component versions get patch 0).
    let upstream: SemanticVersion
}

public enum VersionComparison {

    /// Compares two version texts under one scheme. Returns nil when either text is
    /// not supported by that scheme; callers must then report unknown, not guess.
    public static func ordering(_ lhs: String, _ rhs: String, scheme: VersionScheme) -> VersionOrdering? {
        switch scheme {
        case .semanticVersion:
            guard let left = parseSemanticVersion(lhs, allowTwoComponents: false),
                  let right = parseSemanticVersion(rhs, allowTwoComponents: false)
            else { return nil }
            return compare(left, right)
        case .homebrewStable:
            guard let left = parseHomebrewStable(lhs),
                  let right = parseHomebrewStable(rhs)
            else { return nil }
            let upstream = compare(left.upstream, right.upstream)
            if upstream != .equal { return upstream }
            return compareDigits(left.revision, right.revision)
        }
    }

    // MARK: Semantic Versioning

    /// Strict SemVer 2.0.0 grammar. `allowTwoComponents` accepts `MAJOR.MINOR` (patch 0),
    /// used only for Homebrew upstream versions. Build metadata is parsed and retained,
    /// but never affects ordering.
    public static func parseSemanticVersion(_ text: String, allowTwoComponents: Bool) -> SemanticVersion? {
        guard !text.isEmpty else { return nil }

        var core = Substring(text)
        var build: [String] = []
        if let plus = core.firstIndex(of: "+") {
            guard let identifiers = identifierList(core[core.index(after: plus)...], numericNoLeadingZero: false)
            else { return nil }
            build = identifiers
            core = core[..<plus]
        }

        var prerelease: [String] = []
        if let dash = core.firstIndex(of: "-") {
            guard let identifiers = identifierList(core[core.index(after: dash)...], numericNoLeadingZero: true)
            else { return nil }
            prerelease = identifiers
            core = core[..<dash]
        }

        let numbers = core.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let countIsSupported = numbers.count == 3 || (allowTwoComponents && numbers.count == 2)
        guard countIsSupported else { return nil }
        guard numbers.allSatisfy(isNumericNoLeadingZero) else { return nil }

        return SemanticVersion(
            major: numbers[0],
            minor: numbers[1],
            patch: numbers.count == 3 ? numbers[2] : "0",
            prerelease: prerelease,
            build: build
        )
    }

    // MARK: Homebrew stable versions

    /// Homebrew `upstream[_revision]` for stable releases. Upstream must be a stable
    /// `MAJOR.MINOR[.PATCH]` (no prerelease, no build metadata). Revision is a canonical
    /// nonnegative integer without a leading zero. Anything else returns nil.
    public static func parseHomebrewStable(_ text: String) -> HomebrewStableVersion? {
        guard !text.isEmpty else { return nil }
        let upstreamText: Substring
        let revision: Int
        if let underscore = text.firstIndex(of: "_") {
            upstreamText = text[..<underscore]
            let revisionText = String(text[text.index(after: underscore)...])
            guard isCanonicalNonnegativeInteger(revisionText),
                  let value = Int(revisionText)
            else { return nil }
            revision = value
        } else {
            upstreamText = text[...]
            revision = 0
        }
        let upstreamString = String(upstreamText)
        guard !upstreamString.contains("-"), !upstreamString.contains("+"),
              let upstream = parseSemanticVersion(upstreamString, allowTwoComponents: true)
        else { return nil }
        return HomebrewStableVersion(upstreamText: upstreamString, revision: revision, upstream: upstream)
    }

    // MARK: Ordering helpers

    private static func compare(_ left: SemanticVersion, _ right: SemanticVersion) -> VersionOrdering {
        for (lhs, rhs) in [(left.major, right.major), (left.minor, right.minor), (left.patch, right.patch)] {
            let result = compareDigits(lhs, rhs)
            if result != .equal { return result }
        }
        return comparePrerelease(left.prerelease, right.prerelease)
    }

    /// SemVer §11: a release outranks its prereleases; identifiers compare left to right.
    private static func comparePrerelease(_ left: [String], _ right: [String]) -> VersionOrdering {
        if left.isEmpty && right.isEmpty { return .equal }
        if left.isEmpty { return .newer }
        if right.isEmpty { return .older }
        for (lhs, rhs) in zip(left, right) {
            let result = compareIdentifier(lhs, rhs)
            if result != .equal { return result }
        }
        if left.count == right.count { return .equal }
        return left.count < right.count ? .older : .newer
    }

    private static func compareIdentifier(_ lhs: String, _ rhs: String) -> VersionOrdering {
        let lhsNumeric = isDigits(lhs)
        let rhsNumeric = isDigits(rhs)
        switch (lhsNumeric, rhsNumeric) {
        case (true, true): return compareDigits(lhs, rhs)
        case (true, false): return .older
        case (false, true): return .newer
        case (false, false):
            if lhs == rhs { return .equal }
            return lhs.utf8.lexicographicallyPrecedes(rhs.utf8) ? .older : .newer
        }
    }

    /// Compares canonical digit strings (no leading zeros) by magnitude without overflow.
    private static func compareDigits(_ lhs: String, _ rhs: String) -> VersionOrdering {
        if lhs.count != rhs.count { return lhs.count < rhs.count ? .older : .newer }
        if lhs == rhs { return .equal }
        return lhs < rhs ? .older : .newer
    }

    private static func compareDigits(_ lhs: Int, _ rhs: Int) -> VersionOrdering {
        if lhs == rhs { return .equal }
        return lhs < rhs ? .older : .newer
    }

    // MARK: Lexical grammar helpers

    private static func identifierList(_ text: Substring, numericNoLeadingZero: Bool) -> [String]? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(isIdentifierCharacter) else { return nil }
            if numericNoLeadingZero, isDigits(part), !isNumericNoLeadingZero(part) { return nil }
        }
        return parts
    }

    private static func isIdentifierCharacter(_ character: Character) -> Bool {
        character == "-" || (character.isASCII && (character.isLetter || character.isNumber))
    }

    private static func isDigits(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// Canonical numeric component: `0` or a nonzero digit followed by digits.
    private static func isNumericNoLeadingZero(_ text: String) -> Bool {
        guard isDigits(text) else { return false }
        return text == "0" || !text.hasPrefix("0")
    }

    private static func isCanonicalNonnegativeInteger(_ text: String) -> Bool {
        isNumericNoLeadingZero(text)
    }
}
