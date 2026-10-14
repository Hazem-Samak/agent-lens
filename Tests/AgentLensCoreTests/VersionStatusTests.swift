import Testing
@testable import AgentLensCore

// M6 step 2 — the tri-state status derived from verified comparisons.

@Test func equalVerifiedVersionsAreUpToDate() {
    let status = VersionStatus.evaluate(
        installed: Version("1.10.0"),
        latest: Version("1.10.0"),
        scheme: .semanticVersion
    )
    #expect(status == .upToDate(installed: Version("1.10.0"), latest: Version("1.10.0")))
}

@Test func olderVerifiedVersionIsUpdateAvailable() {
    let status = VersionStatus.evaluate(
        installed: Version("1.9.0"),
        latest: Version("1.10.0"),
        scheme: .semanticVersion
    )
    #expect(status == .updateAvailable(installed: Version("1.9.0"), latest: Version("1.10.0")))
}

@Test func homebrewRevisionDifferenceIsAnUpdateNotAnUpToDate() {
    let status = VersionStatus.evaluate(
        installed: Version("1.2.3_1"),
        latest: Version("1.2.3_2"),
        scheme: .homebrewStable
    )
    #expect(status == .updateAvailable(installed: Version("1.2.3_1"), latest: Version("1.2.3_2")))
}

@Test func installedNewerThanKnownMetadataIsUnknownNotDowngrade() {
    let status = VersionStatus.evaluate(
        installed: Version("2.0.0"),
        latest: Version("1.9.0"),
        scheme: .semanticVersion
    )
    #expect(status == .unknown(installed: Version("2.0.0"), reason: .newerThanKnownMetadata))
}

@Test func unsupportedSchemeRetainsLocalTextAndNeverFabricatesLatest() {
    let status = VersionStatus.evaluate(
        installed: Version("2024-01-01"),
        latest: Version("1.0.0"),
        scheme: .homebrewStable
    )
    #expect(status == .unknown(installed: Version("2024-01-01"), reason: .unsupportedVersion))
}
