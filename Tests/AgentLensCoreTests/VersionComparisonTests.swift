import Testing
@testable import AgentLensCore

// M6 step 2 — strict SemVer and Homebrew stable+revision ordering.
// Pure functions: no filesystem, no processes, no clock.

// MARK: Numeric ordering (brief: "Numeric ordering", "SemVer")

@Test func semanticNumericComponentsCompareNumerically() {
    #expect(VersionComparison.ordering("1.9.0", "1.10.0", scheme: .semanticVersion) == .older)
    #expect(VersionComparison.ordering("1.10.0", "1.9.0", scheme: .semanticVersion) == .newer)
    #expect(VersionComparison.ordering("0.162.1", "0.162.1", scheme: .semanticVersion) == .equal)
}

@Test func semanticLargeComponentsDoNotOverflow() {
    let big = "99999999999999999999999999.0.0"
    let bigger = "99999999999999999999999998.0.0"
    #expect(VersionComparison.ordering(bigger, big, scheme: .semanticVersion) == .older)
    #expect(VersionComparison.ordering(big, bigger, scheme: .semanticVersion) == .newer)
}

// MARK: Prerelease precedence (brief: alpha.2 < alpha.10 < beta < release)

@Test func prereleaseIdentifiersFollowSemVerPrecedence() {
    #expect(VersionComparison.ordering("1.0.0-alpha.2", "1.0.0-alpha.10", scheme: .semanticVersion) == .older)
    #expect(VersionComparison.ordering("1.0.0-alpha.10", "1.0.0-beta", scheme: .semanticVersion) == .older)
    #expect(VersionComparison.ordering("1.0.0-beta", "1.0.0", scheme: .semanticVersion) == .older)
    #expect(VersionComparison.ordering("1.0.0", "1.0.0-rc.1", scheme: .semanticVersion) == .newer)
}

@Test func shorterEqualPrereleasePrefixComesFirst() {
    #expect(VersionComparison.ordering("1.0.0-alpha", "1.0.0-alpha.1", scheme: .semanticVersion) == .older)
}

@Test func numericPrereleaseIdentifiersPrecedeAlphanumericOnes() {
    #expect(VersionComparison.ordering("1.0.0-1", "1.0.0-alpha", scheme: .semanticVersion) == .older)
    #expect(VersionComparison.ordering("1.0.0-2", "1.0.0-10", scheme: .semanticVersion) == .older)
}

@Test func buildMetadataDoesNotAffectPrecedence() {
    #expect(VersionComparison.ordering("1.0.0+build.1", "1.0.0+build.2", scheme: .semanticVersion) == .equal)
    #expect(VersionComparison.ordering("1.0.0+exp.sha.5114f85", "1.0.0", scheme: .semanticVersion) == .equal)
}

// MARK: Strict rejection (brief: leading zeroes, empty identifiers, trailing junk)

@Test func strictSemanticParserRejectsMalformedText() {
    let malformed = [
        "01.2.3",        // leading zero in numeric core
        "1.02.3",
        "1.2.3-01",      // leading zero in numeric prerelease identifier
        "1.2.3-",        // empty prerelease
        "1.2.3-alpha..1",// empty identifier
        "1.2.3x",        // trailing junk
        "1.2.3 (build 7)",
        "1.2",           // local strict SemVer needs three components
        "1.x",
        "HEAD",
        "",
    ]
    for text in malformed {
        #expect(VersionComparison.parseSemanticVersion(text, allowTwoComponents: false) == nil,
                "expected \(text) to be rejected")
        #expect(VersionComparison.ordering(text, "1.0.0", scheme: .semanticVersion) == nil,
                "expected \(text) to be incomparable")
    }
}

// MARK: Homebrew stable + package revision (brief: "Homebrew revision")

@Test func homebrewRevisionOrdersSamePackageVersion() {
    #expect(VersionComparison.ordering("1.2.3_1", "1.2.3", scheme: .homebrewStable) == .newer)
    #expect(VersionComparison.ordering("1.2.3", "1.2.3_1", scheme: .homebrewStable) == .older)
    #expect(VersionComparison.ordering("1.2.3_2", "1.2.3_1", scheme: .homebrewStable) == .newer)
    #expect(VersionComparison.ordering("1.2.3_10", "1.2.3_9", scheme: .homebrewStable) == .newer)
}

@Test func homebrewTwoComponentStableVersionUsesZeroPatch() {
    #expect(VersionComparison.ordering("1.2", "1.2.0", scheme: .homebrewStable) == .equal)
    #expect(VersionComparison.ordering("1.2", "1.2.1", scheme: .homebrewStable) == .older)
    #expect(VersionComparison.ordering("1.10", "1.9.9", scheme: .homebrewStable) == .newer)
}

@Test func homebrewRejectsPrereleaseAndMalformedRevisions() {
    let unsupported = ["1.0.0-rc1", "1.2.3_x", "1.2.3_", "1.2.3__1", "1.x", "HEAD", "2024-01-01", "1.2.3_01"]
    for text in unsupported {
        #expect(VersionComparison.parseHomebrewStable(text) == nil, "expected \(text) to be unsupported")
        #expect(VersionComparison.ordering(text, "1.2.3", scheme: .homebrewStable) == nil)
    }
}

@Test func homebrewStableUpstreamAgreesWithLocalSemanticToken() {
    // Used by the identity check: the selected keg's upstream version must match the CLI banner.
    let upstream = VersionComparison.parseHomebrewStable("0.162.1_1")
    #expect(upstream?.upstreamText == "0.162.1")
    #expect(VersionComparison.ordering("0.162.1", "0.162.1", scheme: .semanticVersion) == .equal)
}
