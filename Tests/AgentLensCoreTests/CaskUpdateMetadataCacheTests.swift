// CaskUpdateMetadataCacheTests — M13-B isolated cask document (R3).
//
// Injected temp URLs and clock; the real cache is never touched. These fixtures stage real
// token/version directories and selected executables so every restore also exercises the live
// root/token/version/selected-identity bindings. The tests pin TTL, exact timestamps, the 1 MiB
// cap in both directions, full-identity matching, structural coherence without a version
// comparator, ambiguity, document merge, atomic refusal of an oversized replacement, and
// ecosystem isolation from the formula and npm documents.

import Foundation
import Testing
@testable import AgentLensCore

private func caskCacheRoot(_ label: String) throws -> URL {
    let environment = ProcessInfo.processInfo.environment
    guard let basePath = [environment["AGENT_LENS_TEST_SCRATCH"], environment["TMPDIR"]]
        .compactMap({ $0 })
        .first(where: { !$0.isEmpty })
    else {
        throw NSError(
            domain: "AgentLensCaskCacheTests", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "no approved test scratch root is available"]
        )
    }
    let base = URL(fileURLWithPath: basePath, isDirectory: true).resolvingSymlinksInPath()
    let root = base.appendingPathComponent(
        "agentlens-m13b-cache-\(label)-\(UUID().uuidString)", isDirectory: true
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root.resolvingSymlinksInPath()
}

private let caskObservedAt = Date(timeIntervalSince1970: 1_800_000_000.75)

private final class CaskCacheFixture {
    let root: URL
    let prefix: URL
    let caskroom: URL
    let managerPath: String

    init(_ label: String) throws {
        root = try caskCacheRoot(label)
        prefix = root.appendingPathComponent("prefix", isDirectory: true)
        caskroom = root.appendingPathComponent("Caskroom", isDirectory: true)
        let bin = prefix.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: caskroom, withIntermediateDirectories: true)
        managerPath = bin.appendingPathComponent("brew").path
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: URL(fileURLWithPath: managerPath))
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: managerPath
        )
    }

    var prefixRoot: HomebrewCaskBoundRoot { HomebrewCaskBoundRoot.observe(prefix.path)! }
    var caskroomRoot: HomebrewCaskBoundRoot { HomebrewCaskBoundRoot.observe(caskroom.path)! }

    struct Staged {
        let token: String
        let version: String
        let entryPath: String
        let target: String
        let tokenDirectory: HomebrewCaskBoundDirectory
        let versionDirectory: HomebrewCaskBoundDirectory
        let selectedIdentity: ObservedExecutable
        let selectedFingerprint: String
    }

    func stage(token: String, version: String) throws -> Staged {
        let artifact = caskroom
            .appendingPathComponent(token, isDirectory: true)
            .appendingPathComponent(version, isDirectory: true)
            .appendingPathComponent("bin/\(token)")
        try FileManager.default.createDirectory(
            at: artifact.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: artifact)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: artifact.path
        )
        let entry = prefix.appendingPathComponent("bin/\(token)")
        try? FileManager.default.removeItem(at: entry)
        try FileManager.default.createSymbolicLink(
            atPath: entry.path, withDestinationPath: artifact.path
        )
        let identity = FileIdentityObserver.observeExecutable(entryPath: entry.path)!
        return Staged(
            token: token,
            version: version,
            entryPath: entry.path,
            target: artifact.resolvingSymlinksInPath().standardizedFileURL.path,
            tokenDirectory: HomebrewCaskUpdateProbe.boundDirectory(
                path: HomebrewCaskUpdateProbe.appendedPath(caskroom.path, token),
                component: token,
                parent: caskroomRoot.identity
            )!,
            versionDirectory: HomebrewCaskUpdateProbe.boundDirectory(
                path: HomebrewCaskUpdateProbe.appendedPath(
                    HomebrewCaskUpdateProbe.appendedPath(caskroom.path, token), version
                ),
                component: version,
                parent: HomebrewCaskUpdateProbe.boundDirectory(
                    path: HomebrewCaskUpdateProbe.appendedPath(caskroom.path, token),
                    component: token,
                    parent: caskroomRoot.identity
                )!.identity
            )!,
            selectedIdentity: identity,
            selectedFingerprint: CaskUpdateMetadataKey.selectedFingerprintDigest(
                identity.fingerprint
            )
        )
    }
}

private func sampleCaskEntry(
    _ fixture: CaskCacheFixture,
    _ staged: CaskCacheFixture.Staged,
    observed: Date = caskObservedAt,
    registryID: String? = nil,
    managerEntryPath: String? = nil,
    managerTarget: String? = nil,
    managerFingerprint: String = "fp-manager",
    prefixPath: String? = nil,
    prefixCanonical: String? = nil,
    prefixIdentity: DirectoryIdentity? = nil,
    caskroomPath: String? = nil,
    caskroomCanonical: String? = nil,
    caskroomIdentity: DirectoryIdentity? = nil,
    token: String? = nil,
    fullToken: String? = nil,
    tap: String = "homebrew/cask",
    installedVersion: String? = nil,
    tokenDirectory: HomebrewCaskBoundDirectory? = nil,
    versionDirectory: HomebrewCaskBoundDirectory? = nil,
    selectedEntryPath: String? = nil,
    selectedTarget: String? = nil,
    selectedFingerprint: String? = nil,
    declarationsDigest: String? = nil,
    contextDigest: String = "fp-cask-env",
    version: String = "3.2.2",
    pinned: Bool = false,
    managerOutdated: Bool = true
) -> CaskUpdateMetadataEntry {
    let resolvedToken = token ?? staged.token
    let full = fullToken ?? resolvedToken
    let prefixIdentity = prefixIdentity ?? fixture.prefixRoot.identity
    let caskroomIdentity = caskroomIdentity ?? fixture.caskroomRoot.identity
    return CaskUpdateMetadataEntry(
        registryID: registryID ?? staged.token,
        managerEntryPath: managerEntryPath ?? fixture.managerPath,
        managerTarget: managerTarget ?? fixture.managerPath,
        managerFingerprint: managerFingerprint,
        prefix: prefixPath ?? fixture.prefix.path,
        prefixCanonical: prefixCanonical ?? prefixIdentity.canonicalPath,
        prefixDevice: prefixIdentity.device,
        prefixInode: prefixIdentity.inode,
        caskroom: caskroomPath ?? fixture.caskroom.path,
        caskroomCanonical: caskroomCanonical ?? caskroomIdentity.canonicalPath,
        caskroomDevice: caskroomIdentity.device,
        caskroomInode: caskroomIdentity.inode,
        token: resolvedToken,
        fullToken: full,
        tap: tap,
        installedVersion: installedVersion ?? staged.version,
        tokenDirectoryPath: (tokenDirectory ?? staged.tokenDirectory).path,
        tokenDirectoryDevice: (tokenDirectory ?? staged.tokenDirectory).identity.device,
        tokenDirectoryInode: (tokenDirectory ?? staged.tokenDirectory).identity.inode,
        versionDirectoryPath: (versionDirectory ?? staged.versionDirectory).path,
        versionDirectoryDevice: (versionDirectory ?? staged.versionDirectory).identity.device,
        versionDirectoryInode: (versionDirectory ?? staged.versionDirectory).identity.inode,
        selectedEntryPath: selectedEntryPath ?? staged.entryPath,
        selectedTarget: selectedTarget ?? staged.target,
        selectedFingerprint: selectedFingerprint ?? staged.selectedFingerprint,
        declarationsDigest: declarationsDigest
            ?? CaskUpdateMetadataKey.declarationsDigest([resolvedToken]),
        contextDigest: contextDigest,
        version: version,
        pinned: pinned,
        managerOutdated: managerOutdated,
        observedAt: observed
    )
}

private func entryCopy(
    _ entry: CaskUpdateMetadataEntry,
    registryID: String? = nil,
    managerEntryPath: String? = nil,
    managerTarget: String? = nil,
    managerFingerprint: String? = nil,
    prefix: String? = nil,
    prefixCanonical: String? = nil,
    prefixDevice: UInt64? = nil,
    prefixInode: UInt64? = nil,
    caskroom: String? = nil,
    caskroomCanonical: String? = nil,
    caskroomDevice: UInt64? = nil,
    caskroomInode: UInt64? = nil,
    token: String? = nil,
    fullToken: String? = nil,
    tap: String? = nil,
    installedVersion: String? = nil,
    tokenDirectoryPath: String? = nil,
    tokenDirectoryDevice: UInt64? = nil,
    tokenDirectoryInode: UInt64? = nil,
    versionDirectoryPath: String? = nil,
    versionDirectoryDevice: UInt64? = nil,
    versionDirectoryInode: UInt64? = nil,
    selectedEntryPath: String? = nil,
    selectedTarget: String? = nil,
    selectedFingerprint: String? = nil,
    declarationsDigest: String? = nil,
    contextDigest: String? = nil,
    version: String? = nil,
    pinned: Bool? = nil,
    managerOutdated: Bool? = nil,
    observedAt: Date? = nil
) -> CaskUpdateMetadataEntry {
    CaskUpdateMetadataEntry(
        registryID: registryID ?? entry.registryID,
        managerEntryPath: managerEntryPath ?? entry.managerEntryPath,
        managerTarget: managerTarget ?? entry.managerTarget,
        managerFingerprint: managerFingerprint ?? entry.managerFingerprint,
        prefix: prefix ?? entry.prefix,
        prefixCanonical: prefixCanonical ?? entry.prefixCanonical,
        prefixDevice: prefixDevice ?? entry.prefixDevice,
        prefixInode: prefixInode ?? entry.prefixInode,
        caskroom: caskroom ?? entry.caskroom,
        caskroomCanonical: caskroomCanonical ?? entry.caskroomCanonical,
        caskroomDevice: caskroomDevice ?? entry.caskroomDevice,
        caskroomInode: caskroomInode ?? entry.caskroomInode,
        token: token ?? entry.token,
        fullToken: fullToken ?? entry.fullToken,
        tap: tap ?? entry.tap,
        installedVersion: installedVersion ?? entry.installedVersion,
        tokenDirectoryPath: tokenDirectoryPath ?? entry.tokenDirectoryPath,
        tokenDirectoryDevice: tokenDirectoryDevice ?? entry.tokenDirectoryDevice,
        tokenDirectoryInode: tokenDirectoryInode ?? entry.tokenDirectoryInode,
        versionDirectoryPath: versionDirectoryPath ?? entry.versionDirectoryPath,
        versionDirectoryDevice: versionDirectoryDevice ?? entry.versionDirectoryDevice,
        versionDirectoryInode: versionDirectoryInode ?? entry.versionDirectoryInode,
        selectedEntryPath: selectedEntryPath ?? entry.selectedEntryPath,
        selectedTarget: selectedTarget ?? entry.selectedTarget,
        selectedFingerprint: selectedFingerprint ?? entry.selectedFingerprint,
        declarationsDigest: declarationsDigest ?? entry.declarationsDigest,
        contextDigest: contextDigest ?? entry.contextDigest,
        version: version ?? entry.version,
        pinned: pinned ?? entry.pinned,
        managerOutdated: managerOutdated ?? entry.managerOutdated,
        observedAt: observedAt ?? entry.observedAt
    )
}

private func sampleSelection(
    _ entry: CaskUpdateMetadataEntry
) -> CaskUpdateMetadataSelection {
    CaskUpdateMetadataSelection(
        registryID: entry.registryID,
        managerEntryPath: entry.managerEntryPath,
        managerTarget: entry.managerTarget,
        managerFingerprint: entry.managerFingerprint,
        selectedEntryPath: entry.selectedEntryPath,
        selectedTarget: entry.selectedTarget,
        selectedFingerprint: entry.selectedFingerprint,
        declarationsDigest: entry.declarationsDigest,
        contextDigest: entry.contextDigest
    )
}

private func writeRawCaskDocument(_ data: Data, to url: URL) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try data.write(to: url)
}

private func encodeCaskDocument(_ entries: [CaskUpdateMetadataEntry], schema: Int = 1) throws -> Data {
    let document = CaskUpdateMetadataDocument(schemaVersion: schema, entries: entries)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(document)
}

// MARK: TTL and exact timestamps

@Test func coldDocumentIsAMissAndAFreshDocumentIsAHit() throws {
    let fixture = try CaskCacheFixture("hit")
    let staged = try fixture.stage(token: "kiro-cli", version: "3.2.1")
    let formulaURL = fixture.root.appendingPathComponent("update-metadata-v1.json")
    let store = CaskUpdateMetadataCache(updateCacheURL: formulaURL, now: { caskObservedAt })
    #expect(store.fileURL.lastPathComponent == "cask-update-metadata-v1.json")
    #expect(store.lookup(sampleSelection(sampleCaskEntry(fixture, staged))) == nil)

    let entry = sampleCaskEntry(fixture, staged)
    #expect(store.save([entry]))
    let hit = store.lookup(entry.key)
    #expect(hit?.version == entry.version)
    #expect(hit?.managerOutdated == true)
    #expect(hit?.observedAt == caskObservedAt)
    #expect(store.lookup(sampleSelection(entry)) == hit)
}

@Test func ttlBoundaryAndFutureObservationAreMisses() throws {
    let fixture = try CaskCacheFixture("ttl")
    let staged = try fixture.stage(token: "kiro-cli", version: "3.2.1")
    let url = fixture.root.appendingPathComponent("cask-update-metadata-v1.json")
    let entry = sampleCaskEntry(fixture, staged)
    #expect(CaskUpdateMetadataCache(updateCacheURL: url, now: { caskObservedAt })
        .save([entry]))

    let atExpiry = CaskUpdateMetadataCache(
        updateCacheURL: url, now: { caskObservedAt.addingTimeInterval(21_600) }
    )
    #expect(atExpiry.lookup(entry.key) == nil)
    let future = CaskUpdateMetadataCache(
        updateCacheURL: url, now: { caskObservedAt.addingTimeInterval(-1) }
    )
    #expect(future.lookup(entry.key) == nil)
    let justInside = CaskUpdateMetadataCache(
        updateCacheURL: url, now: { caskObservedAt.addingTimeInterval(21_599.5) }
    )
    #expect(justInside.lookup(entry.key) == entry)
}

// MARK: Identity

@Test func everyIdentityFieldAndTheContextDigestMustMatch() throws {
    let fixture = try CaskCacheFixture("identity")
    let staged = try fixture.stage(token: "kiro-cli", version: "3.2.1")
    let url = fixture.root.appendingPathComponent("cask-update-metadata-v1.json")
    let entry = sampleCaskEntry(fixture, staged)
    #expect(CaskUpdateMetadataCache(updateCacheURL: url, now: { caskObservedAt })
        .save([entry]))

    let variants = [
        entryCopy(entry, registryID: "other"),
        entryCopy(entry, managerEntryPath: "/other/brew"),
        entryCopy(entry, managerTarget: "/other/brew-target"),
        entryCopy(entry, managerFingerprint: "changed"),
        entryCopy(entry, prefix: "/other/prefix"),
        entryCopy(entry, prefixCanonical: "/other/prefix-canonical"),
        entryCopy(entry, prefixDevice: entry.prefixDevice + 1),
        entryCopy(entry, prefixInode: entry.prefixInode + 1),
        entryCopy(entry, caskroom: "/other/Caskroom"),
        entryCopy(entry, caskroomCanonical: "/other/Caskroom-canonical"),
        entryCopy(entry, caskroomDevice: entry.caskroomDevice + 1),
        entryCopy(entry, caskroomInode: entry.caskroomInode + 1),
        entryCopy(entry, token: "other"),
        entryCopy(entry, fullToken: "owner/tap/kiro-cli"),
        entryCopy(entry, tap: "other/tap"),
        entryCopy(entry, installedVersion: "3.2.0"),
        entryCopy(entry, tokenDirectoryPath: "/other/token"),
        entryCopy(entry, tokenDirectoryDevice: entry.tokenDirectoryDevice + 1),
        entryCopy(entry, tokenDirectoryInode: entry.tokenDirectoryInode + 1),
        entryCopy(entry, versionDirectoryPath: "/other/version"),
        entryCopy(entry, versionDirectoryDevice: entry.versionDirectoryDevice + 1),
        entryCopy(entry, versionDirectoryInode: entry.versionDirectoryInode + 1),
        entryCopy(entry, selectedEntryPath: "/other/bin/kiro-cli"),
        entryCopy(entry, selectedTarget: "/other/Caskroom/kiro-cli/3.2.1/bin/kiro-cli"),
        entryCopy(entry, selectedFingerprint: "changed-selected"),
        entryCopy(entry, declarationsDigest: "changed-declarations"),
        entryCopy(entry, contextDigest: "changed-context"),
    ]
    let store = CaskUpdateMetadataCache(updateCacheURL: url, now: { caskObservedAt })
    for variant in variants {
        #expect(store.lookup(variant.key) == nil)
    }
    // Selection matching covers the pre-query identity only.
    let selectionVariants = [
        entryCopy(entry, registryID: "other"),
        entryCopy(entry, managerEntryPath: "/other/brew"),
        entryCopy(entry, managerFingerprint: "changed"),
        entryCopy(entry, selectedEntryPath: "/other/bin/kiro-cli"),
        entryCopy(entry, selectedTarget: "/other/Caskroom/kiro-cli/3.2.1/bin/kiro-cli"),
        entryCopy(entry, selectedFingerprint: "changed-selected"),
        entryCopy(entry, declarationsDigest: "changed-declarations"),
        entryCopy(entry, contextDigest: "changed-context"),
    ]
    for variant in selectionVariants {
        #expect(store.lookup(sampleSelection(variant)) == nil)
    }
    #expect(store.lookup(entry.key) == entry)
}

@Test func liveRootTokenVersionAndSelectedBindingsAreRequiredForARestore() throws {
    let fixture = try CaskCacheFixture("live-bindings")
    let staged = try fixture.stage(token: "kiro-cli", version: "3.2.1")
    let url = fixture.root.appendingPathComponent("cask-update-metadata-v1.json")
    let entry = sampleCaskEntry(fixture, staged)
    let store = CaskUpdateMetadataCache(updateCacheURL: url, now: { caskObservedAt })
    #expect(store.save([entry]))
    #expect(store.lookup(sampleSelection(entry)) == entry)

    // Same selected path, replaced executable: the current selection digest no longer matches.
    try Data("#!/bin/sh\nprintf 'new\\n'\n".utf8).write(
        to: URL(fileURLWithPath: staged.target)
    )
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755], ofItemAtPath: staged.target
    )
    let replacedIdentity = FileIdentityObserver.observeExecutable(
        entryPath: staged.entryPath
    )!
    let replacedSelection = CaskUpdateMetadataSelection(
        registryID: entry.registryID,
        managerEntryPath: entry.managerEntryPath,
        managerTarget: entry.managerTarget,
        managerFingerprint: entry.managerFingerprint,
        selectedEntryPath: entry.selectedEntryPath,
        selectedTarget: entry.selectedTarget,
        selectedFingerprint: CaskUpdateMetadataKey.selectedFingerprintDigest(
            replacedIdentity.fingerprint
        ),
        declarationsDigest: entry.declarationsDigest,
        contextDigest: entry.contextDigest
    )
    #expect(store.lookup(replacedSelection) == nil)
    // Even the exact-key lookup refuses a replaced selected executable at the same path.
    #expect(store.lookup(entry.key) == nil)

    // A retargeted reported Caskroom alias is also a miss for the stored exact key.
    let replacement = fixture.root.appendingPathComponent("replacement", isDirectory: true)
    try FileManager.default.createDirectory(at: replacement, withIntermediateDirectories: true)
    let moved = replacement.appendingPathComponent("Caskroom", isDirectory: true)
    try FileManager.default.moveItem(at: fixture.caskroom, to: moved)
    try FileManager.default.createSymbolicLink(
        atPath: fixture.caskroom.path, withDestinationPath: moved.path
    )
    #expect(store.lookup(entry.key) == nil)
}

@Test func alteredDeclarationsOrSelectedIdentityCannotRestore() throws {
    let fixture = try CaskCacheFixture("declaration")
    let staged = try fixture.stage(token: "kiro-cli", version: "3.2.1")
    let url = fixture.root.appendingPathComponent("cask-update-metadata-v1.json")
    let entry = sampleCaskEntry(fixture, staged)
    let store = CaskUpdateMetadataCache(updateCacheURL: url, now: { caskObservedAt })
    #expect(store.save([entry]))

    var changedDeclaration = sampleSelection(entry)
    changedDeclaration = CaskUpdateMetadataSelection(
        registryID: changedDeclaration.registryID,
        managerEntryPath: changedDeclaration.managerEntryPath,
        managerTarget: changedDeclaration.managerTarget,
        managerFingerprint: changedDeclaration.managerFingerprint,
        selectedEntryPath: changedDeclaration.selectedEntryPath,
        selectedTarget: changedDeclaration.selectedTarget,
        selectedFingerprint: changedDeclaration.selectedFingerprint,
        declarationsDigest: CaskUpdateMetadataKey.declarationsDigest(
            ["kiro-cli", "kiro-cli@latest"]
        ),
        contextDigest: changedDeclaration.contextDigest
    )
    #expect(store.lookup(changedDeclaration) == nil)
}

// MARK: Structural coherence and ambiguity

@Test func incoherentRecordsAreNeverStoredOrRestored() throws {
    let fixture = try CaskCacheFixture("incoherent")
    let staged = try fixture.stage(token: "kiro-cli", version: "3.2.1")
    let url = fixture.root.appendingPathComponent("cask-update-metadata-v1.json")
    let store = CaskUpdateMetadataCache(updateCacheURL: url, now: { caskObservedAt })
    let base = sampleCaskEntry(fixture, staged)

    let incoherent = [
        // full_token/tap disagree
        entryCopy(base, fullToken: "owner/tap/kiro-cli", tap: "other/tap"),
        // selected target does not decompose under the recorded Caskroom
        entryCopy(base, selectedTarget: "/Applications/Kiro.app/Contents/MacOS/kiro-cli"),
        // installed version differs from the selected target's version directory
        entryCopy(base, installedVersion: "3.2.0"),
        // unknown is never a cached shape
        entryCopy(base, version: "latest"),
        // an impossible verdict: manager-outdated with equal strings
        entryCopy(base, version: staged.version, managerOutdated: true),
        // an impossible verdict: up-to-date with unequal strings
        entryCopy(base, version: "3.2.2", managerOutdated: false),
        // token directory does not name the exact component
        entryCopy(base, tokenDirectoryPath: "\(fixture.caskroom.path)/other-token"),
    ]
    for entry in incoherent {
        #expect(!entry.isStructurallyCoherent)
        #expect(store.save([entry]) == false)
    }
    #expect(!FileManager.default.fileExists(atPath: url.path))

    // A hand-written incoherent document is a miss, never a partially reconstructed record.
    let handWritten = try encodeCaskDocument([incoherent[1]])
    try writeRawCaskDocument(handWritten, to: url)
    #expect(store.lookup(sampleSelection(incoherent[1])) == nil)
}

@Test func unequalManagerOutdatedPairIsCoherentWithoutAnyVersionOrdering() throws {
    let fixture = try CaskCacheFixture("oracle-veto")
    let staged = try fixture.stage(token: "kiro-cli", version: "3.2.1")
    let url = fixture.root.appendingPathComponent("cask-update-metadata-v1.json")
    // Manager metadata is LOWER than the installed string; the formula comparator used to reject
    // this. Both manager records attested an update, so the cache must accept the observation.
    let entry = sampleCaskEntry(fixture, staged, version: "3.1.0", managerOutdated: true)
    #expect(entry.isStructurallyCoherent)
    let store = CaskUpdateMetadataCache(updateCacheURL: url, now: { caskObservedAt })
    #expect(store.save([entry]))
    #expect(store.lookup(sampleSelection(entry)) == entry)
}

@Test func twoLiveRecordsForOneSelectionAreAmbiguityNotFirstWins() throws {
    let fixture = try CaskCacheFixture("ambiguity")
    let staged = try fixture.stage(token: "kiro-cli", version: "3.2.1")
    let url = fixture.root.appendingPathComponent("cask-update-metadata-v1.json")
    let first = sampleCaskEntry(fixture, staged)
    let second = sampleCaskEntry(
        fixture, staged, fullToken: "owner/tap/kiro-cli", tap: "owner/tap"
    )
    #expect(first.isStructurallyCoherent)
    #expect(second.isStructurallyCoherent)
    let store = CaskUpdateMetadataCache(updateCacheURL: url, now: { caskObservedAt })
    #expect(store.save([first, second]))
    #expect(store.lookup(sampleSelection(first)) == nil)
    #expect(store.lookup(first.key) == first)
    #expect(store.lookup(second.key) == second)
}

// MARK: Bounds, schema and corruption

@Test func oversizeDocumentsAreMissesAndOversizeWritesNeverEvictSiblings() throws {
    let fixture = try CaskCacheFixture("bounds")
    let staged = try fixture.stage(token: "kiro-cli", version: "3.2.1")
    let other = try fixture.stage(token: "other-tool", version: "1.0.0")
    let url = fixture.root.appendingPathComponent("cask-update-metadata-v1.json")
    try writeRawCaskDocument(
        Data(repeating: 0x20, count: CaskUpdateMetadataCache.maximumDocumentBytes + 1),
        to: url
    )
    let store = CaskUpdateMetadataCache(updateCacheURL: url, now: { caskObservedAt })
    #expect(store.lookup(sampleCaskEntry(fixture, staged).key) == nil)

    // A valid sibling survives an incoming record that cannot fit.
    #expect(store.save([sampleCaskEntry(fixture, staged)]))
    let before = try Data(contentsOf: url)
    let hugeVersion = String(repeating: "9", count: CaskUpdateMetadataCache.maximumDocumentBytes + 1)
    let huge = sampleCaskEntry(fixture, other, version: hugeVersion)
    #expect(huge.isStructurallyCoherent)
    #expect(store.save([huge]) == false)
    #expect(try Data(contentsOf: url) == before)
    #expect(store.lookup(sampleCaskEntry(fixture, staged).key) == sampleCaskEntry(fixture, staged))
    #expect(store.lookup(huge.key) == nil)
}

@Test func oversizedReplacementWithTheSameKeyLeavesTheOldBytesIdentical() throws {
    let fixture = try CaskCacheFixture("oversize-replace")
    let staged = try fixture.stage(token: "kiro-cli", version: "3.2.1")
    let url = fixture.root.appendingPathComponent("cask-update-metadata-v1.json")
    let store = CaskUpdateMetadataCache(updateCacheURL: url, now: { caskObservedAt })
    let old = sampleCaskEntry(fixture, staged, version: "3.2.2")
    #expect(store.save([old]))
    let before = try Data(contentsOf: url)

    // The replacement has the SAME cache key (version is payload, not key) but cannot fit.
    let hugeVersion = String(
        repeating: "9", count: CaskUpdateMetadataCache.maximumDocumentBytes + 1
    )
    let huge = entryCopy(old, version: hugeVersion)
    #expect(huge.key == old.key)
    #expect(huge.isStructurallyCoherent)
    #expect(store.save([huge]) == false)
    #expect(try Data(contentsOf: url) == before)
    #expect(store.lookup(old.key) == old)
}

@Test func schemaMismatchAndCorruptionAreMisses() throws {
    let fixture = try CaskCacheFixture("schema")
    let staged = try fixture.stage(token: "kiro-cli", version: "3.2.1")
    let url = fixture.root.appendingPathComponent("cask-update-metadata-v1.json")
    let store = CaskUpdateMetadataCache(updateCacheURL: url, now: { caskObservedAt })
    let entry = sampleCaskEntry(fixture, staged)

    try writeRawCaskDocument(try encodeCaskDocument([entry], schema: 2), to: url)
    #expect(store.lookup(entry.key) == nil)

    try writeRawCaskDocument(Data("{\"schemaVersion\":1,\"entries\":[".utf8), to: url)
    #expect(store.lookup(entry.key) == nil)

    try writeRawCaskDocument(Data(), to: url)
    #expect(store.lookup(entry.key) == nil)

    // A missing observation timestamp is a decode miss, never "now".
    let missingTimestamp = """
    {"schemaVersion":1,"entries":[{"registryID":"kiro-cli"}]}
    """
    try writeRawCaskDocument(Data(missingTimestamp.utf8), to: url)
    #expect(store.lookup(entry.key) == nil)
}

@Test func saveMergesUnrelatedIdentitiesAndPrunesExpiredOnes() throws {
    let fixture = try CaskCacheFixture("merge")
    let firstStaged = try fixture.stage(token: "kiro-cli", version: "3.2.1")
    let secondStaged = try fixture.stage(token: "antigravity-cli", version: "1.5.6")
    let thirdStaged = try fixture.stage(token: "codex", version: "1.0.0")
    let url = fixture.root.appendingPathComponent("cask-update-metadata-v1.json")
    let first = sampleCaskEntry(fixture, firstStaged, observed: caskObservedAt)
    let second = sampleCaskEntry(
        fixture, secondStaged,
        registryID: "agy", version: "1.5.6", managerOutdated: false
    )
    let store = CaskUpdateMetadataCache(updateCacheURL: url, now: { caskObservedAt })
    #expect(store.save([first]))
    #expect(store.save([second]))
    #expect(store.lookup(first.key) == first)
    #expect(store.lookup(second.key) == second)

    // An expired identity is pruned while the unrelated record survives a later save.
    let laterNow = caskObservedAt.addingTimeInterval(21_700)
    let later = CaskUpdateMetadataCache(
        updateCacheURL: url, now: { laterNow }
    )
    #expect(later.lookup(first.key) == nil)
    #expect(later.lookup(second.key) == nil)
    let third = sampleCaskEntry(
        fixture, thirdStaged,
        observed: laterNow,
        registryID: "codex", version: "1.0.0", managerOutdated: false
    )
    #expect(later.save([third]))
    #expect(later.lookup(third.key) == third)
}

// MARK: Ecosystem isolation

@Test func caskDocumentIsSeparateAndNeverSatisfiesSiblingEcosystems() throws {
    let fixture = try CaskCacheFixture("isolation")
    let staged = try fixture.stage(token: "kiro-cli", version: "3.2.1")
    let formulaURL = fixture.root.appendingPathComponent("update-metadata-v1.json")
    let npmURL = fixture.root.appendingPathComponent("npm-update-metadata-v1.json")
    let caskURL = fixture.root.appendingPathComponent("cask-update-metadata-v1.json")

    let caskEntry = sampleCaskEntry(fixture, staged)
    let caskStore = CaskUpdateMetadataCache(updateCacheURL: formulaURL, now: { caskObservedAt })
    #expect(caskStore.fileURL == caskURL)
    #expect(caskStore.save([caskEntry]))

    let formulaEntry = UpdateMetadataEntry(
        registryID: caskEntry.registryID,
        managerEntryPath: caskEntry.managerEntryPath,
        managerTarget: caskEntry.managerTarget,
        managerFingerprint: caskEntry.managerFingerprint,
        cellar: fixture.prefix.appendingPathComponent("Cellar").path,
        formulaStem: "kiro-cli",
        fullFormulaName: "kiro-cli",
        selectedEntryPath: caskEntry.selectedEntryPath,
        selectedKegVersion: "3.2.1",
        selectedTarget: fixture.prefix.appendingPathComponent(
            "Cellar/kiro-cli/3.2.1/bin/kiro-cli"
        ).path,
        contextFingerprint: caskEntry.contextDigest,
        formulaStable: "3.2.1",
        formulaRevision: 0,
        installedVersions: ["3.2.1"],
        observedAt: caskObservedAt
    )
    let formulaStore = UpdateMetadataCache(fileURL: formulaURL, now: { caskObservedAt })
    #expect(formulaStore.save([formulaEntry]))
    let formulaBytes = try Data(contentsOf: formulaURL)

    let npmEntry = NpmUpdateMetadataEntry(
        registryID: "codex",
        package: "@openai/codex",
        registry: "https://registry.npmjs.org/",
        tag: "latest",
        managerEntryPath: fixture.prefix.appendingPathComponent("bin/npm").path,
        managerTarget: fixture.prefix.appendingPathComponent("bin/npm").path,
        managerFingerprint: "fp-npm",
        prefix: fixture.prefix.path,
        installationRoot: fixture.prefix.appendingPathComponent("lib/node_modules/@openai/codex").path,
        selectedEntryPath: staged.entryPath,
        selectedTarget: staged.target,
        selectedFingerprint: "fp-selected",
        proofFingerprint: "fp-proof",
        contextDigest: "fp-npm-context",
        name: "@openai/codex",
        version: "0.162.1",
        distTagsLatest: "0.162.1",
        observedAt: caskObservedAt
    )
    let npmStore = NpmUpdateMetadataCache(updateCacheURL: formulaURL, now: { caskObservedAt })
    #expect(npmStore.fileURL == npmURL)
    #expect(npmStore.save([npmEntry]))
    let npmBytes = try Data(contentsOf: npmURL)
    #expect(npmEntry.isFullyValidatedRecord)

    // The cask save did not consume or replace either sibling document.
    #expect(try Data(contentsOf: formulaURL) == formulaBytes)
    #expect(try Data(contentsOf: npmURL) == npmBytes)

    // Copying each document into the other path is never accepted as the wrong ecosystem.
    let caskBytes = try Data(contentsOf: caskURL)
    try writeRawCaskDocument(caskBytes, to: formulaURL)
    #expect(formulaStore.lookup(formulaEntry.key) == nil)
    try writeRawCaskDocument(caskBytes, to: npmURL)
    #expect(npmStore.lookup(npmEntryKey(npmEntry)) == nil)

    try writeRawCaskDocument(formulaBytes, to: caskURL)
    #expect(caskStore.lookup(caskEntry.key) == nil)
    try writeRawCaskDocument(npmBytes, to: caskURL)
    #expect(caskStore.lookup(caskEntry.key) == nil)
}

/// The npm cache's full key is internal to that family; this mirrors the one construction the
/// npm probe uses so the isolation assertion can address the stored entry.
private func npmEntryKey(_ entry: NpmUpdateMetadataEntry) -> NpmUpdateMetadataKey {
    NpmUpdateMetadataKey(
        registryID: entry.registryID,
        package: entry.package,
        registry: entry.registry,
        tag: entry.tag,
        managerEntryPath: entry.managerEntryPath,
        managerTarget: entry.managerTarget,
        managerFingerprint: entry.managerFingerprint,
        prefix: entry.prefix,
        installationRoot: entry.installationRoot,
        selectedEntryPath: entry.selectedEntryPath,
        selectedTarget: entry.selectedTarget,
        selectedFingerprint: entry.selectedFingerprint,
        proofFingerprint: entry.proofFingerprint,
        contextDigest: entry.contextDigest
    )
}
