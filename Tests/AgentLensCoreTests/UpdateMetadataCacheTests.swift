import Foundation
import Testing
@testable import AgentLensCore

// M6 step 4 — versioned six-hour metadata cache. Injected URL and clock; never the real cache.

private func cacheRoot(_ label: String) throws -> URL {
    let environment = ProcessInfo.processInfo.environment
    guard let basePath = [environment["AGENT_LENS_TEST_SCRATCH"], environment["TMPDIR"]]
        .compactMap({ $0 })
        .first(where: { !$0.isEmpty })
    else {
        throw NSError(domain: "AgentLensTests", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "no approved test scratch root is available"])
    }
    let base = URL(fileURLWithPath: basePath, isDirectory: true).resolvingSymlinksInPath()
    let root = base.appendingPathComponent("agentlens-m6-cache-\(label)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root.resolvingSymlinksInPath()
}

private let observedAt = Date(timeIntervalSince1970: 1_800_000_000.75)

private func sampleEntry(
    observed: Date = observedAt,
    registryID: String = "codex",
    fullName: String = "codex",
    formulaStable: String = "0.162.1",
    formulaRevision: Int = 2
) -> UpdateMetadataEntry {
    UpdateMetadataEntry(
        registryID: registryID,
        managerEntryPath: "/opt/homebrew/bin/brew",
        managerTarget: "/opt/homebrew/bin/brew",
        managerFingerprint: "fp-manager",
        cellar: "/opt/homebrew/Cellar",
        formulaStem: "codex",
        fullFormulaName: fullName,
        selectedEntryPath: "/opt/homebrew/bin/codex",
        selectedKegVersion: "0.162.1_1",
        selectedTarget: "/opt/homebrew/Cellar/codex/0.162.1_1/bin/codex",
        contextFingerprint: "fp-env",
        formulaStable: formulaStable,
        formulaRevision: formulaRevision,
        installedVersions: ["0.162.1_1"],
        observedAt: observed
    )
}

@Test func cacheHitBeforeTheSixHourBoundaryReturnsTheStoredMetadata() throws {
    let url = try cacheRoot("hit").appendingPathComponent("update-metadata-v1.json")
    let store = UpdateMetadataCache(fileURL: url, now: { observedAt.addingTimeInterval(21_599.5) })
    #expect(store.save([sampleEntry()]))

    let hit = store.lookup(sampleEntry().key)
    #expect(hit?.formulaRevision == 2)
    #expect(hit?.observedAt == observedAt)
}

@Test func exactlySixHoursIsAMissAndAFutureTimestampIsAMiss() throws {
    let url = try cacheRoot("boundary").appendingPathComponent("update-metadata-v1.json")
    #expect(UpdateMetadataCache(fileURL: url, now: { observedAt }).save([sampleEntry()]))

    let atExpiry = UpdateMetadataCache(fileURL: url, now: { observedAt.addingTimeInterval(21_600) })
    #expect(atExpiry.lookup(sampleEntry().key) == nil)

    let future = UpdateMetadataCache(fileURL: url, now: { observedAt.addingTimeInterval(-1) })
    #expect(future.lookup(sampleEntry().key) == nil)
}

@Test func changedIdentityOrFingerprintsAreMisses() throws {
    let url = try cacheRoot("identity").appendingPathComponent("update-metadata-v1.json")
    let store = UpdateMetadataCache(fileURL: url, now: { observedAt })
    #expect(store.save([sampleEntry()]))

    let base = sampleEntry().key
    let variants = [
        UpdateMetadataKey(registryID: base.registryID, managerEntryPath: base.managerEntryPath,
                          managerTarget: "/usr/local/bin/brew", managerFingerprint: base.managerFingerprint,
                          cellar: base.cellar, formulaStem: base.formulaStem,
                          fullFormulaName: base.fullFormulaName, selectedEntryPath: base.selectedEntryPath,
                          selectedKegVersion: base.selectedKegVersion, selectedTarget: base.selectedTarget,
                          contextFingerprint: base.contextFingerprint),
        UpdateMetadataKey(registryID: base.registryID, managerEntryPath: base.managerEntryPath,
                          managerTarget: base.managerTarget, managerFingerprint: "changed",
                          cellar: base.cellar, formulaStem: base.formulaStem,
                          fullFormulaName: base.fullFormulaName, selectedEntryPath: base.selectedEntryPath,
                          selectedKegVersion: base.selectedKegVersion, selectedTarget: base.selectedTarget,
                          contextFingerprint: base.contextFingerprint),
        UpdateMetadataKey(registryID: base.registryID, managerEntryPath: base.managerEntryPath,
                          managerTarget: base.managerTarget, managerFingerprint: base.managerFingerprint,
                          cellar: "/other/Cellar", formulaStem: base.formulaStem,
                          fullFormulaName: base.fullFormulaName, selectedEntryPath: base.selectedEntryPath,
                          selectedKegVersion: base.selectedKegVersion, selectedTarget: base.selectedTarget,
                          contextFingerprint: base.contextFingerprint),
        UpdateMetadataKey(registryID: base.registryID, managerEntryPath: base.managerEntryPath,
                          managerTarget: base.managerTarget, managerFingerprint: base.managerFingerprint,
                          cellar: base.cellar, formulaStem: base.formulaStem,
                          fullFormulaName: "hazem/tools/codex", selectedEntryPath: base.selectedEntryPath,
                          selectedKegVersion: base.selectedKegVersion, selectedTarget: base.selectedTarget,
                          contextFingerprint: base.contextFingerprint),
        UpdateMetadataKey(registryID: base.registryID, managerEntryPath: base.managerEntryPath,
                          managerTarget: base.managerTarget, managerFingerprint: base.managerFingerprint,
                          cellar: base.cellar, formulaStem: base.formulaStem,
                          fullFormulaName: base.fullFormulaName, selectedEntryPath: "/other/bin/codex",
                          selectedKegVersion: base.selectedKegVersion, selectedTarget: base.selectedTarget,
                          contextFingerprint: base.contextFingerprint),
        UpdateMetadataKey(registryID: base.registryID, managerEntryPath: base.managerEntryPath,
                          managerTarget: base.managerTarget, managerFingerprint: base.managerFingerprint,
                          cellar: base.cellar, formulaStem: base.formulaStem,
                          fullFormulaName: base.fullFormulaName, selectedEntryPath: base.selectedEntryPath,
                          selectedKegVersion: "0.162.1_2", selectedTarget: base.selectedTarget,
                          contextFingerprint: base.contextFingerprint),
        UpdateMetadataKey(registryID: "other-id", managerEntryPath: base.managerEntryPath,
                          managerTarget: base.managerTarget, managerFingerprint: base.managerFingerprint,
                          cellar: base.cellar, formulaStem: base.formulaStem,
                          fullFormulaName: base.fullFormulaName, selectedEntryPath: base.selectedEntryPath,
                          selectedKegVersion: base.selectedKegVersion, selectedTarget: base.selectedTarget,
                          contextFingerprint: base.contextFingerprint),
        UpdateMetadataKey(registryID: base.registryID, managerEntryPath: "/opt/other/bin/brew",
                          managerTarget: base.managerTarget, managerFingerprint: base.managerFingerprint,
                          cellar: base.cellar, formulaStem: base.formulaStem,
                          fullFormulaName: base.fullFormulaName, selectedEntryPath: base.selectedEntryPath,
                          selectedKegVersion: base.selectedKegVersion, selectedTarget: base.selectedTarget,
                          contextFingerprint: base.contextFingerprint),
        UpdateMetadataKey(registryID: base.registryID, managerEntryPath: base.managerEntryPath,
                          managerTarget: base.managerTarget, managerFingerprint: base.managerFingerprint,
                          cellar: base.cellar, formulaStem: "other-formula",
                          fullFormulaName: base.fullFormulaName, selectedEntryPath: base.selectedEntryPath,
                          selectedKegVersion: base.selectedKegVersion, selectedTarget: base.selectedTarget,
                          contextFingerprint: base.contextFingerprint),
        UpdateMetadataKey(registryID: base.registryID, managerEntryPath: base.managerEntryPath,
                          managerTarget: base.managerTarget, managerFingerprint: base.managerFingerprint,
                          cellar: base.cellar, formulaStem: base.formulaStem,
                          fullFormulaName: base.fullFormulaName, selectedEntryPath: base.selectedEntryPath,
                          selectedKegVersion: base.selectedKegVersion,
                          selectedTarget: "/opt/homebrew/Cellar/codex/0.162.1_2/bin/codex",
                          contextFingerprint: base.contextFingerprint),
        UpdateMetadataKey(registryID: base.registryID, managerEntryPath: base.managerEntryPath,
                          managerTarget: base.managerTarget, managerFingerprint: base.managerFingerprint,
                          cellar: base.cellar, formulaStem: base.formulaStem,
                          fullFormulaName: base.fullFormulaName, selectedEntryPath: base.selectedEntryPath,
                          selectedKegVersion: base.selectedKegVersion, selectedTarget: base.selectedTarget,
                          contextFingerprint: "changed-env"),
    ]
    for variant in variants {
        #expect(store.lookup(variant) == nil)
    }
}

@Test func corruptWrongSchemaAndAbsentFilesAreMisses() throws {
    let root = try cacheRoot("corrupt")
    let url = root.appendingPathComponent("update-metadata-v1.json")
    let store = UpdateMetadataCache(fileURL: url, now: { observedAt })
    #expect(store.lookup(sampleEntry().key) == nil)

    try Data("{ not json".utf8).write(to: url)
    #expect(store.lookup(sampleEntry().key) == nil)

    try Data("{\"schemaVersion\":2,\"entries\":[]}".utf8).write(to: url)
    #expect(store.lookup(sampleEntry().key) == nil)
}

@Test func oversizedCacheFileIsRejectedAsAMiss() throws {
    let url = try cacheRoot("oversized").appendingPathComponent("update-metadata-v1.json")
    try Data(count: 1_048_577).write(to: url)
    let store = UpdateMetadataCache(fileURL: url, now: { observedAt })
    #expect(store.lookup(sampleEntry().key) == nil)
}

@Test func writeFailureIsNeutralAndDoesNotThrowIntoInventory() throws {
    let root = try cacheRoot("write-fail")
    // A regular file where the cache directory should be makes the write impossible.
    let blocker = root.appendingPathComponent("blocker")
    try Data("x".utf8).write(to: blocker)
    let store = UpdateMetadataCache(
        fileURL: blocker.appendingPathComponent("update-metadata-v1.json"),
        now: { observedAt }
    )
    #expect(store.save([sampleEntry()]) == false)
}

@Test func successfulSaveReplacesTheDocumentAtomicallyAndKeepsOnlySelectedRecords() throws {
    let url = try cacheRoot("atomic").appendingPathComponent("update-metadata-v1.json")
    let store = UpdateMetadataCache(fileURL: url, now: { observedAt })
    #expect(store.save([sampleEntry()]))

    let persisted = try String(contentsOf: url, encoding: .utf8)
    // Only the validated selected metadata; no raw environment or unrelated package inventory.
    #expect(!persisted.contains("unrelated"))
    #expect(!persisted.contains("HOME"))
    #expect(persisted.contains("\"schemaVersion\" : 3"))
    #expect(persisted.contains("0.162.1"))
    // No temporary files left behind in the directory.
    let siblings = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
    #expect(siblings == ["update-metadata-v1.json"])
}

@Test func storedDigestIsAStableCryptographicSHA256NotHasherRandomized() {
    // FIPS 180-2 test vector: SHA-256("abc"). Pins the digest to a real, process-stable value.
    #expect(UpdateMetadataKey.stableDigest("abc")
        == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    #expect(UpdateMetadataKey.stableDigest("abc") == UpdateMetadataKey.stableDigest("abc"))
    #expect(UpdateMetadataKey.stableDigest("abd") != UpdateMetadataKey.stableDigest("abc"))
}

@Test func fullFormulaIdentityIsPartOfTheKeyAndSelectionLookupRejectsAmbiguity() throws {
    let url = try cacheRoot("full-formula-key").appendingPathComponent("update-metadata-v1.json")
    let store = UpdateMetadataCache(fileURL: url, now: { observedAt })
    let tapped = sampleEntry(fullName: "hazem/homebrew-tools/codex")
    let otherTap = sampleEntry(fullName: "other/homebrew-tools/codex")
    let selection = UpdateMetadataSelection(
        registryID: tapped.registryID,
        managerEntryPath: tapped.managerEntryPath,
        managerTarget: tapped.managerTarget,
        managerFingerprint: tapped.managerFingerprint,
        selectedEntryPath: tapped.selectedEntryPath,
        selectedTarget: tapped.selectedTarget,
        contextFingerprint: tapped.contextFingerprint
    )

    #expect(store.save([tapped]))
    #expect(store.lookup(selection) == tapped)
    #expect(store.lookup(tapped.key) == tapped)

    #expect(store.save([tapped, otherTap]))
    #expect(store.lookup(tapped.key) == tapped)
    #expect(store.lookup(otherTap.key) == otherTap)
    #expect(store.lookup(selection) == nil)
}

@Test func cachedStableMustBeUpstreamTextWithRevisionStoredSeparately() throws {
    let url = try cacheRoot("stable-suffix").appendingPathComponent("update-metadata-v1.json")
    let store = UpdateMetadataCache(fileURL: url, now: { observedAt })
    let forged = sampleEntry(formulaStable: "1.2.3_99", formulaRevision: 0)
    #expect(!forged.isStructurallyCoherent)
    #expect(!store.save([forged]))

    let document = UpdateMetadataDocument(
        schemaVersion: UpdateMetadataDocument.currentSchemaVersion,
        entries: [forged]
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(document).write(to: url)
    #expect(store.lookup(forged.key) == nil)
    let selection = UpdateMetadataSelection(
        registryID: forged.registryID,
        managerEntryPath: forged.managerEntryPath,
        managerTarget: forged.managerTarget,
        managerFingerprint: forged.managerFingerprint,
        selectedEntryPath: forged.selectedEntryPath,
        selectedTarget: forged.selectedTarget,
        contextFingerprint: forged.contextFingerprint
    )
    #expect(store.lookup(selection) == nil)

    let genuineRevision = sampleEntry(formulaStable: "1.2.3", formulaRevision: 99)
    #expect(store.save([genuineRevision]))
    #expect(store.lookup(genuineRevision.key) == genuineRevision)
}
