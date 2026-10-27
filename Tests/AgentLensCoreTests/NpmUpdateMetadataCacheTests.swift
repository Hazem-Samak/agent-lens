// NpmUpdateMetadataCacheTests — M10-B npm metadata cache behavioral regressions (B04).
//
// Every fixture is synthetic and test-owned. Nothing reads a real HOME/npm cache; the persistent
// document lives in an injected scratch directory. These cases prove the frozen cache contract:
// six-hour TTL boundaries, corrupt/oversize/duplicate records are misses (never scan failures),
// merge preserves other tools and replaces only the matching identity, expired records are pruned,
// and Homebrew records are never touched because the npm document is a separate sibling file.
//
// R06 adds: a stored record must satisfy the SAME strict semantics the fresh `view` parser required
// (accepted normalized registry, `latest` tag, catalogue-valid package/name equality, stable strict
// SemVer equal to dist-tags.latest), so a parseable-but-poisoned record is a miss and can never be
// written; an ambiguous identity remains a miss even after an unrelated save (never silent
// latest-wins); and the document read/merge/write is one in-process critical section.

import Foundation
import Testing
@testable import AgentLensCore

// MARK: Scratch and construction helpers

private func npmCacheScratch(_ label: String) throws -> URL {
    let environment = ProcessInfo.processInfo.environment
    guard let basePath = [environment["AGENT_LENS_TEST_SCRATCH"], environment["TMPDIR"]]
        .compactMap({ $0 })
        .first(where: { !$0.isEmpty })
    else {
        throw NSError(domain: "NpmCacheTests", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "no approved test scratch root"])
    }
    let base = URL(fileURLWithPath: basePath, isDirectory: true).resolvingSymlinksInPath()
    let root = base.appendingPathComponent("agentlens-m10b-cache-\(label)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private let coherentPackage = "@openai/codex"

private func cacheKey(
    registryID: String = "codex",
    prefix: String = "/prefix",
    installationRoot: String = "/prefix/lib/node_modules/@openai/codex",
    registry: String = "https://registry.npmjs.org/",
    tag: String = "latest",
    package: String = coherentPackage
) -> NpmUpdateMetadataKey {
    NpmUpdateMetadataKey(
        registryID: registryID,
        package: package,
        registry: registry,
        tag: tag,
        managerEntryPath: "/bin/npm",
        managerTarget: "/bin/npm-target",
        managerFingerprint: "mgrfp",
        prefix: prefix,
        installationRoot: installationRoot,
        selectedEntryPath: "/prefix/bin/codex",
        selectedTarget: "/prefix/lib/node_modules/@openai/codex/bin/codex.js",
        selectedFingerprint: "selfp",
        proofFingerprint: "prooffp",
        contextDigest: "ctxdigest"
    )
}

private func cacheEntry(
    matching key: NpmUpdateMetadataKey = cacheKey(),
    observedAt: Date,
    version: String = "1.2.3",
    name: String? = nil,
    distTagsLatest: String? = nil
) -> NpmUpdateMetadataEntry {
    NpmUpdateMetadataEntry(
        registryID: key.registryID,
        package: key.package,
        registry: key.registry,
        tag: key.tag,
        managerEntryPath: key.managerEntryPath,
        managerTarget: key.managerTarget,
        managerFingerprint: key.managerFingerprint,
        prefix: key.prefix,
        installationRoot: key.installationRoot,
        selectedEntryPath: key.selectedEntryPath,
        selectedTarget: key.selectedTarget,
        selectedFingerprint: key.selectedFingerprint,
        proofFingerprint: key.proofFingerprint,
        contextDigest: key.contextDigest,
        name: name ?? key.package,
        version: version,
        distTagsLatest: distTagsLatest ?? version,
        observedAt: observedAt
    )
}

/// The npm document is the sibling of the injected Homebrew cache URL.
private func npmDocumentURL(_ directory: URL) -> URL {
    directory.appendingPathComponent("npm-update-metadata-v1.json")
}

/// Writes the document directly, bypassing `save`, so a test can plant a record the cache itself
/// would refuse to accept (a pre-existing or externally tampered on-disk state).
private func writeStoredRecords(
    _ directory: URL,
    _ entries: [NpmUpdateMetadataEntry]
) throws {
    let document = #"{"schemaVersion":1,"entries":["#
        + entries.map(encodedEntry).joined(separator: ",") + "]}"
    try Data(document.utf8).write(to: npmDocumentURL(directory))
}

// MARK: TTL boundaries

@Test func freshEntryIsFoundWithinTTL() throws {
    let dir = try npmCacheScratch("ttl-hit")
    let observedAt = Date(timeIntervalSince1970: 1_800_000_000)
    let cache = NpmUpdateMetadataCache(
        updateCacheURL: dir.appendingPathComponent("update-cache.json"),
        now: { observedAt.addingTimeInterval(3_600) }  // one hour later, inside six
    )
    #expect(cache.save([cacheEntry(observedAt: observedAt)]))
    let restored = try #require(cache.lookup(cacheKey()))
    #expect(restored.version == "1.2.3")
    #expect(restored.observedAt == observedAt)  // original observation time preserved
}

@Test func entryExactlyAtSixHoursIsAMiss() throws {
    let dir = try npmCacheScratch("ttl-exact")
    let observedAt = Date(timeIntervalSince1970: 1_800_000_000)
    let cache = NpmUpdateMetadataCache(
        updateCacheURL: dir.appendingPathComponent("update-cache.json"),
        now: { observedAt.addingTimeInterval(NpmUpdateMetadataCache.ttl) }
    )
    #expect(cache.save([cacheEntry(observedAt: observedAt)]))
    #expect(cache.lookup(cacheKey()) == nil)
}

@Test func futureObservationIsAMissAndStaysOutOfStoreAfterSave() throws {
    let dir = try npmCacheScratch("ttl-future")
    let observedAt = Date(timeIntervalSince1970: 1_800_000_000)
    let readCache = NpmUpdateMetadataCache(
        updateCacheURL: dir.appendingPathComponent("update-cache.json"),
        now: { observedAt.addingTimeInterval(-10) }  // clock is before the record
    )
    #expect(readCache.save([cacheEntry(observedAt: observedAt)]))
    #expect(readCache.lookup(cacheKey()) == nil)
}

// MARK: Corrupt / oversize / duplicate are misses, not scan failures

@Test func corruptDocumentIsAMissNotAThrow() throws {
    let dir = try npmCacheScratch("corrupt")
    let cacheURL = dir.appendingPathComponent("update-cache.json")
    try Data("this is not json".utf8)
        .write(to: cacheURL.deletingLastPathComponent().appendingPathComponent("npm-update-metadata-v1.json"))
    let cache = NpmUpdateMetadataCache(updateCacheURL: cacheURL, now: { Date() })
    #expect(cache.lookup(cacheKey()) == nil)  // miss, no throw
}

@Test func oversizeDocumentIsAMiss() throws {
    let dir = try npmCacheScratch("oversize")
    let cacheURL = dir.appendingPathComponent("update-cache.json")
    let padding = String(repeating: "x", count: NpmUpdateMetadataCache.maximumDocumentBytes + 16)
    try Data(padding.utf8).write(
        to: cacheURL.deletingLastPathComponent().appendingPathComponent("npm-update-metadata-v1.json")
    )
    let cache = NpmUpdateMetadataCache(updateCacheURL: cacheURL, now: { Date() })
    #expect(cache.lookup(cacheKey()) == nil)
}

@Test func duplicateCompleteIdentityRecordsAreAMiss() throws {
    let dir = try npmCacheScratch("duplicate")
    let cacheURL = dir.appendingPathComponent("update-cache.json")
    let observedAt = Date(timeIntervalSince1970: 1_800_000_000)
    let entry = cacheEntry(observedAt: observedAt)
    // Two self-consistent records with one identity, planted directly: `save` never collapses
    // another identity's ambiguity, so two live matches must never silently first-win.
    try writeStoredRecords(dir, [entry, entry])
    let cache = NpmUpdateMetadataCache(
        updateCacheURL: cacheURL,
        now: { observedAt.addingTimeInterval(60) }
    )
    #expect(cache.lookup(cacheKey()) == nil)
}

private func encodedEntry(_ entry: NpmUpdateMetadataEntry) -> String {
    let data = try! JSONEncoder().encode(entry)
    return String(decoding: data, as: UTF8.self)
}

// MARK: Merge / preserve / prune / replace

@Test func savePreservesOtherToolAndReplacesOnlyMatchingIdentity() throws {
    let dir = try npmCacheScratch("merge")
    let cacheURL = dir.appendingPathComponent("update-cache.json")
    let base = Date(timeIntervalSince1970: 1_800_000_000)
    let now: @Sendable () -> Date = { base.addingTimeInterval(120) }
    let cache = NpmUpdateMetadataCache(updateCacheURL: cacheURL, now: now)

    let otherKey = cacheKey(registryID: "opencode",
                            prefix: "/other-prefix",
                            installationRoot: "/other-prefix/lib/node_modules/opencode")
    #expect(cache.save([cacheEntry(matching: otherKey, observedAt: base, version: "1.0.0")]))

    let codexKey = cacheKey(registryID: "codex")
    #expect(cache.save([cacheEntry(matching: codexKey, observedAt: base, version: "1.0.0")]))

    // Replace only codex; opencode survives untouched.
    #expect(cache.save([cacheEntry(matching: codexKey, observedAt: base.addingTimeInterval(30), version: "2.0.0")]))

    let codex = try #require(cache.lookup(codexKey))
    #expect(codex.version == "2.0.0")
    let other = try #require(cache.lookup(otherKey))
    #expect(other.version == "1.0.0")  // untouched
}

@Test func savePrunesExpiredRecords() throws {
    let dir = try npmCacheScratch("prune")
    let cacheURL = dir.appendingPathComponent("update-cache.json")
    let base = Date(timeIntervalSince1970: 1_800_000_000)
    // Seed an expired record directly, then a fresh save should drop it.
    let expired = cacheEntry(observedAt: base.addingTimeInterval(-40_000), version: "0.0.1")
    let document = #"{"schemaVersion":1,"entries":["# + encodedEntry(expired) + "]}"
    try Data(document.utf8).write(to: cacheURL.deletingLastPathComponent().appendingPathComponent("npm-update-metadata-v1.json"))

    let freshKey = cacheKey(registryID: "codex-fresh")
    let cache = NpmUpdateMetadataCache(updateCacheURL: cacheURL, now: { base })
    #expect(cache.save([cacheEntry(matching: freshKey, observedAt: base)]))

    let stored = try Data(contentsOf: cacheURL.deletingLastPathComponent().appendingPathComponent("npm-update-metadata-v1.json"))
    #expect(!String(decoding: stored, as: UTF8.self).contains("0.0.1"))  // expired pruned
    #expect(cache.lookup(freshKey) != nil)
}

// MARK: Incoherent records rejected; Homebrew file untouched

@Test func saveRejectsIncoherentEntryAndLeavesStoreUnchanged() throws {
    let dir = try npmCacheScratch("incoherent")
    let cacheURL = dir.appendingPathComponent("update-cache.json")
    let cache = NpmUpdateMetadataCache(updateCacheURL: cacheURL, now: { Date() })
    // name != package violates self-consistency.
    let bad = cacheEntry(observedAt: Date(), name: "different-name")
    #expect(cache.save([bad]) == false)
    #expect(FileManager.default.fileExists(
        atPath: cacheURL.deletingLastPathComponent().appendingPathComponent("npm-update-metadata-v1.json").path
    ) == false)
}

@Test func npmDocumentIsASeparateSiblingOfTheHomebrewCache() throws {
    let dir = try npmCacheScratch("sibling")
    let homebrewURL = dir.appendingPathComponent("homebrew-update-cache.json")
    // Pre-create a Homebrew document at the injected URL; constructing/saving the npm cache must
    // never read or rewrite it.
    try Data(#"{"schemaVersion":3,"entries":[]}"#.utf8).write(to: homebrewURL)
    let before = try Data(contentsOf: homebrewURL)
    let cache = NpmUpdateMetadataCache(updateCacheURL: homebrewURL, now: { Date() })
    #expect(cache.fileURL.lastPathComponent == "npm-update-metadata-v1.json")
    #expect(cache.save([cacheEntry(observedAt: Date())]))
    let after = try Data(contentsOf: homebrewURL)
    #expect(before == after)  // Homebrew record identical
}

// MARK: R06 — a stored record must satisfy the SAME strict semantics as a fresh parse
//
// A key match is not proof of valid metadata. Each case below plants one parseable, key-matching
// record with exactly one poisoned semantic field and requires a miss, and additionally requires
// `save` to refuse that same record, so no path can write or read a claim the fresh `view` parser
// would never have authorized.

private let r06ObservedAt = Date(timeIntervalSince1970: 1_800_000_000)

/// One poisoned-but-parseable record: the same identity, one semantic field altered.
private func r06Case(
    _ label: String,
    key poisonedKey: NpmUpdateMetadataKey,
    version: String = "1.2.3",
    name: String? = nil,
    distTagsLatest: String? = nil
) throws -> (dir: URL, cache: NpmUpdateMetadataCache, record: NpmUpdateMetadataEntry) {
    let dir = try npmCacheScratch(label)
    let cache = NpmUpdateMetadataCache(
        updateCacheURL: dir.appendingPathComponent("update-cache.json"),
        now: { r06ObservedAt.addingTimeInterval(60) }
    )
    let record = cacheEntry(
        matching: poisonedKey, observedAt: r06ObservedAt,
        version: version, name: name, distTagsLatest: distTagsLatest
    )
    try writeStoredRecords(dir, [record])
    return (dir, cache, record)
}

@Test func storedUnsupportedRegistryIsAMissAndCannotBeSaved() throws {
    // Trailing-slash and host spellings the fresh path would normalize are stored only in the
    // exact normalized form, so anything else — even a syntactically valid private mirror — is a
    // miss rather than a foreign-origin observation.
    let testCase = try r06Case(
        "poison-registry",
        key: cacheKey(registry: "https://npm.internal.example/")
    )
    #expect(testCase.cache.lookup(cacheKey(registry: "https://npm.internal.example/")) == nil)
    #expect(testCase.cache.save([testCase.record]) == false)

    // The trailing-slash variant is the accepted normalized form: it validates and is a hit.
    let accepted = try r06Case("accepted-registry", key: cacheKey())
    #expect(accepted.cache.lookup(cacheKey()) != nil)
}

@Test func storedUnsupportedTagIsAMissAndCannotBeSaved() throws {
    // Only the `latest` dist tag is ever read or reused; a stored `next`/default-tag record is
    // evidence about a different channel.
    let testCase = try r06Case("poison-tag", key: cacheKey(tag: "next"))
    #expect(testCase.cache.lookup(cacheKey(tag: "next")) == nil)
    #expect(testCase.cache.save([testCase.record]) == false)
}

@Test func storedPrereleaseVersionIsAMissAndCannotBeSaved() throws {
    // A prerelease `latest` is an unsupported channel, never a reusable six-hour observation —
    // self-consistent version and dist-tags.latest included.
    let testCase = try r06Case("poison-prerelease", key: cacheKey(), version: "2.0.0-rc.1")
    #expect(testCase.cache.lookup(cacheKey()) == nil)
    #expect(testCase.cache.save([testCase.record]) == false)
}

@Test func storedTwoComponentVersionIsAMissAndCannotBeSaved() throws {
    // The npm scheme is strict SemVer with no two-component tolerance, exactly as a fresh parse.
    let testCase = try r06Case("poison-two-component", key: cacheKey(), version: "1.2")
    #expect(testCase.cache.lookup(cacheKey()) == nil)
    #expect(testCase.cache.save([testCase.record]) == false)
}

@Test func storedVersionDivergingFromLatestTagIsAMissAndCannotBeSaved() throws {
    // Two different answers in one record means it is not one unambiguous `@latest` observation.
    let testCase = try r06Case(
        "poison-divergence", key: cacheKey(), version: "1.2.3", distTagsLatest: "1.2.4"
    )
    #expect(testCase.cache.lookup(cacheKey()) == nil)
    #expect(testCase.cache.save([testCase.record]) == false)
}

@Test func storedNameDifferingFromPackageIsAMissAndCannotBeSaved() throws {
    let testCase = try r06Case(
        "poison-name", key: cacheKey(), name: "some-other-package"
    )
    #expect(testCase.cache.lookup(cacheKey()) == nil)
    #expect(testCase.cache.save([testCase.record]) == false)
}

@Test func storedPackageOutsideCatalogueGrammarIsAMissAndCannotBeSaved() throws {
    // The stored identity is validated by the catalogue's own npm name rule, so a name that could
    // never have been declared (an option marker) cannot be reused as metadata either.
    let testCase = try r06Case("poison-package-grammar", key: cacheKey(package: "-evil"))
    #expect(testCase.cache.lookup(cacheKey(package: "-evil")) == nil)
    #expect(testCase.cache.save([testCase.record]) == false)
}

@Test func poisonedRecordForAnIdentityIsNotReplacedBySilentlyChoosingAnother() throws {
    // One poisoned and one live record for the SAME identity: the poisoned record means the
    // identity is corrupted, so lookup fails closed rather than promoting the sibling.
    let dir = try npmCacheScratch("fail-closed")
    let cache = NpmUpdateMetadataCache(
        updateCacheURL: dir.appendingPathComponent("update-cache.json"),
        now: { r06ObservedAt.addingTimeInterval(60) }
    )
    let poisoned = cacheEntry(matching: cacheKey(), observedAt: r06ObservedAt, version: "1.2")
    let live = cacheEntry(matching: cacheKey(), observedAt: r06ObservedAt, version: "9.9.9")
    try writeStoredRecords(dir, [live, poisoned])
    #expect(cache.lookup(cacheKey()) == nil)
    // The identity repairs itself only when its own verified record is stored: every stored copy
    // of that identity is then replaced by exactly one verified record.
    #expect(cache.save([live]))
    let restored = try #require(cache.lookup(cacheKey()))
    #expect(restored.version == "9.9.9")
    let stored = String(decoding: try Data(contentsOf: npmDocumentURL(dir)), as: UTF8.self)
    #expect(!stored.contains("\"1.2\""))
}

@Test func unrelatedSaveNeverPromotesTheValidSiblingOfAContaminatedIdentity() throws {
    // Residual R06 (coordinator CacheProbe repro, compiled independently against the freshly built
    // Core): stored tool-A records hold one VALID 2.0.0 record and one parseable same-identity
    // POISON (`version=2.0.0`, `distTags.latest=9.0.0`). Lookup correctly misses at first. The old
    // per-record filter dropped the poison but PRESERVED A's valid-looking sibling during an
    // unrelated tool-B save, flipping the very next A lookup into an unverified HIT. Contamination
    // must be classified per COMPLETE identity before pruning: an unrelated save drops EVERY A
    // record and the miss persists until A's own verified metadata repairs it.
    let dir = try npmCacheScratch("contaminated-sibling")
    let homebrewURL = dir.appendingPathComponent("update-cache.json")
    try Data(#"{"schemaVersion":3,"entries":[]}"#.utf8).write(to: homebrewURL)
    let homebrewBefore = try Data(contentsOf: homebrewURL)
    let cache = NpmUpdateMetadataCache(
        updateCacheURL: homebrewURL,
        now: { r06ObservedAt.addingTimeInterval(60) }
    )
    let contaminatedKey = cacheKey(registryID: "tool-a", prefix: "/a-prefix")
    let validSibling = cacheEntry(matching: contaminatedKey, observedAt: r06ObservedAt, version: "2.0.0")
    let poison = cacheEntry(
        matching: contaminatedKey, observedAt: r06ObservedAt, version: "2.0.0", distTagsLatest: "9.0.0"
    )
    let unrelatedKey = cacheKey(registryID: "tool-b", prefix: "/b-prefix")
    try writeStoredRecords(dir, [validSibling, poison])

    // Stage 1 of the repro: the contaminated identity starts as a miss.
    #expect(cache.lookup(contaminatedKey) == nil)

    // Stage 2: an UNRELATED identity saves successfully.
    let incomingB = cacheEntry(matching: unrelatedKey, observedAt: r06ObservedAt, version: "1.5.0")
    #expect(cache.save([incomingB]))

    // Stage 3 of the repro: the old defect flipped this to a hit. A miss must still be a miss.
    #expect(cache.lookup(contaminatedKey) == nil)

    // The whole contaminated identity is gone — poison AND sibling — so invalid data can never
    // become a usable record, while the unrelated identity and the Homebrew document are intact.
    let stored = String(decoding: try Data(contentsOf: npmDocumentURL(dir)), as: UTF8.self)
    #expect(!stored.contains("/a-prefix"))
    #expect(!stored.contains("\"2.0.0\""))
    #expect(!stored.contains("\"9.0.0\""))
    #expect(cache.lookup(unrelatedKey)?.version == "1.5.0")
    #expect(try Data(contentsOf: homebrewURL) == homebrewBefore)

    // Only A's OWN verified metadata repairs the identity.
    let repaired = cacheEntry(matching: contaminatedKey, observedAt: r06ObservedAt, version: "3.0.0")
    #expect(cache.save([repaired]))
    let restored = try #require(cache.lookup(contaminatedKey))
    #expect(restored.version == "3.0.0")
    // And a later contamination of the same identity still cannot survive an unrelated save.
    try writeStoredRecords(dir, [restored, cacheEntry(
        matching: contaminatedKey, observedAt: r06ObservedAt, version: "3.0.0",
        distTagsLatest: "9.9.9"
    )])
    #expect(cache.lookup(contaminatedKey) == nil)
    #expect(cache.save([cacheEntry(matching: unrelatedKey, observedAt: r06ObservedAt, version: "1.6.0")]))
    #expect(cache.lookup(contaminatedKey) == nil)
    #expect(cache.lookup(unrelatedKey)?.version == "1.6.0")
    let afterSecondContamination =
        String(decoding: try Data(contentsOf: npmDocumentURL(dir)), as: UTF8.self)
    #expect(!afterSecondContamination.contains("\"9.9.9\""))
    #expect(!afterSecondContamination.contains("/a-prefix"))
}

@Test func unrelatedSaveNeverCollapsesAnAmbiguousIdentityAndNeverTouchesHomebrew() throws {
    // R06: two live records for tool A stay an ambiguity miss even after tool B saves, and the
    // duplicates themselves survive untouched — collapsing them to "latest wins" would manufacture
    // a hit that this process never verified.
    let dir = try npmCacheScratch("ambiguity-survives")
    let homebrewURL = dir.appendingPathComponent("update-cache.json")
    try Data(#"{"schemaVersion":3,"entries":[]}"#.utf8).write(to: homebrewURL)
    let homebrewBefore = try Data(contentsOf: homebrewURL)
    let cache = NpmUpdateMetadataCache(updateCacheURL: homebrewURL, now: { r06ObservedAt })

    let ambiguousKey = cacheKey(registryID: "ambiguous", prefix: "/a-prefix")
    let older = cacheEntry(matching: ambiguousKey, observedAt: r06ObservedAt, version: "1.0.0")
    let newer = cacheEntry(matching: ambiguousKey, observedAt: r06ObservedAt, version: "2.0.0")
    let otherKey = cacheKey(registryID: "other", prefix: "/b-prefix")
    try writeStoredRecords(dir, [older, newer, cacheEntry(matching: otherKey, observedAt: r06ObservedAt)])
    #expect(cache.lookup(ambiguousKey) == nil)

    // An unrelated identity's save: the ambiguity is preserved verbatim, still a miss.
    #expect(cache.save([cacheEntry(matching: otherKey, observedAt: r06ObservedAt, version: "3.0.0")]))
    #expect(cache.lookup(ambiguousKey) == nil)
    let stored = String(decoding: try Data(contentsOf: npmDocumentURL(dir)), as: UTF8.self)
    #expect(stored.contains("\"1.0.0\""))  // never collapsed to a silent winner
    #expect(stored.contains("\"2.0.0\""))
    #expect(cache.lookup(otherKey)?.version == "3.0.0")  // its own identity replaced cleanly
    #expect(try Data(contentsOf: homebrewURL) == homebrewBefore)
}

@Test func saveRefusesPoisonedIncomingRecordWithoutDisturbingStoredRecords() throws {
    let dir = try npmCacheScratch("incoming-poison")
    let cache = NpmUpdateMetadataCache(
        updateCacheURL: dir.appendingPathComponent("update-cache.json"),
        now: { r06ObservedAt.addingTimeInterval(60) }
    )
    let goodKey = cacheKey(registryID: "good")
    #expect(cache.save([cacheEntry(matching: goodKey, observedAt: r06ObservedAt, version: "1.0.0")]))
    let before = try Data(contentsOf: npmDocumentURL(dir))

    let poisoned = cacheEntry(
        matching: cacheKey(registryID: "poisoned"), observedAt: r06ObservedAt, version: "3.0.0-rc.1"
    )
    #expect(cache.save([poisoned]) == false)
    #expect(cache.save([cacheEntry(matching: goodKey, observedAt: r06ObservedAt, version: "1.0.0"), poisoned]) == false)
    #expect(try Data(contentsOf: npmDocumentURL(dir)) == before)  // store byte-identical
    #expect(cache.lookup(cacheKey(registryID: "poisoned")) == nil)
    #expect(cache.lookup(goodKey)?.version == "1.0.0")
}

@Test func simultaneousSavesOfDistinctIdentitiesAllSurvive() async throws {
    // R06 synchronization: the document read/merge/write is one in-process critical section, so
    // concurrent saves cannot interleave and lose another tool's record. Without it, a lost update
    // would silently delete metadata a different subject just verified.
    let dir = try npmCacheScratch("concurrent-save")
    let cache = NpmUpdateMetadataCache(
        updateCacheURL: dir.appendingPathComponent("update-cache.json"),
        now: { r06ObservedAt.addingTimeInterval(60) }
    )
    let identities = (0..<8).map { index in
        cacheKey(registryID: "tool-\(index)", prefix: "/prefix-\(index)",
                 installationRoot: "/prefix-\(index)/lib/node_modules/pkg")
    }
    await withTaskGroup(of: Bool.self) { group in
        for (index, key) in identities.enumerated() {
            group.addTask {
                await Task.yield()
                return cache.save([cacheEntry(matching: key, observedAt: r06ObservedAt,
                                              version: "1.0.\(index)")])
            }
        }
        for await saved in group { #expect(saved) }
    }
    for (index, key) in identities.enumerated() {
        let restored = try #require(cache.lookup(key))
        #expect(restored.version == "1.0.\(index)")
    }
}
