// NpmUpdateMetadataCache — bounded npm latest-metadata document cache (M10-B).
//
// Persists validated successful npm `view @latest` observations only, never a precomputed status.
// Status is recomputed on every run from current local facts. The file is versioned,
// size-limited to 1 MiB in both directions, and replaced atomically in its own directory.
// Keys include a stable SHA-256 of a deterministic serialization, never Swift's randomized
// Hasher, and no raw environment, credentials, or unrelated package inventory is stored.
//
// Identity is carried in full: the registry ID, the verified npm package, the normalized
// accepted registry, the tag, the observed manager entry/target/fingerprint, the verified
// prefix and installation root, the selected entry/target/fingerprint, the proof fingerprint,
// and a stable context digest. Only the digest is persisted, never raw values or unsalted
// low-entropy credential hashes as separate fields. Invocation-local/random scratch/cache/log
// roots are excluded; registry queries and proof validation still run on each cache hit, so
// current config file routing changes cannot borrow old metadata. Prefix is not interchangeable
// with npm root. A new prefix/manifest/manager/registry invalidates a hit.
//
// Persist validated stable metadata and observation time, never final comparison status or
// failed/unsupported results. TTL is `0 <= now-observedAt < 6h`; exactly 6h/expired/future is
// a miss. Preserve original observation time on hit. Corrupt/oversize/ambiguous cache is a
// miss, not a scan failure. Writes cannot change Homebrew records. Preserve structurally valid
// unexpired records for other tools; replace only this identity, classify contamination per
// COMPLETE identity before pruning (one invalid record drops EVERY record of that identity, so
// an unrelated save can never promote its valid-looking sibling into a hit), keep fully-valid
// duplicate identities as preserved ambiguity, and treat duplicate complete identity records as
// a miss. Serialize in-process read/merge/write; cross-process atomic last-writer replacement
// may lose a cache hit but cannot authorize stale identity or corrupt JSON; no cross-process
// locking framework.

import CryptoKit
import Foundation

/// One validated npm latest-metadata observation for a verified selection.
public struct NpmUpdateMetadataEntry: Equatable, Sendable, Codable {
    public let registryID: String
    public let package: String
    public let registry: String
    public let tag: String
    public let managerEntryPath: String
    public let managerTarget: String
    public let managerFingerprint: String
    public let prefix: String
    public let installationRoot: String
    public let selectedEntryPath: String
    public let selectedTarget: String
    public let selectedFingerprint: String
    public let proofFingerprint: String
    public let contextDigest: String
    public let name: String
    public let version: String
    public let distTagsLatest: String
    public let observedAt: Date

    public init(
        registryID: String,
        package: String,
        registry: String,
        tag: String,
        managerEntryPath: String,
        managerTarget: String,
        managerFingerprint: String,
        prefix: String,
        installationRoot: String,
        selectedEntryPath: String,
        selectedTarget: String,
        selectedFingerprint: String,
        proofFingerprint: String,
        contextDigest: String,
        name: String,
        version: String,
        distTagsLatest: String,
        observedAt: Date
    ) {
        self.registryID = registryID
        self.package = package
        self.registry = registry
        self.tag = tag
        self.managerEntryPath = managerEntryPath
        self.managerTarget = managerTarget
        self.managerFingerprint = managerFingerprint
        self.prefix = prefix
        self.installationRoot = installationRoot
        self.selectedEntryPath = selectedEntryPath
        self.selectedTarget = selectedTarget
        self.selectedFingerprint = selectedFingerprint
        self.proofFingerprint = proofFingerprint
        self.contextDigest = contextDigest
        self.name = name
        self.version = version
        self.distTagsLatest = distTagsLatest
        self.observedAt = observedAt
    }

    /// A restored record must satisfy the SAME strict semantics that authorized a fresh `view`
    /// parse before it may support any claim (R06): every bound identity field present, the accepted
    /// normalized registry, the `latest` tag, a catalogue-valid npm package name equal to the
    /// recorded name, and a STABLE strict SemVer `version` exactly equal to `dist-tags.latest`.
    /// A key match is not proof of valid metadata, so a structurally parseable but corrupted
    /// document — custom/alternate registry spelling, an unsupported tag, a prerelease or
    /// two-component version, or a `version`/`dist-tags.latest` divergence — is a miss, never a
    /// verified observation. Nothing here launches a query.
    public var isFullyValidatedRecord: Bool {
        guard !registryID.isEmpty, !package.isEmpty, !registry.isEmpty, !tag.isEmpty,
              !managerEntryPath.isEmpty, !managerTarget.isEmpty, !managerFingerprint.isEmpty,
              !prefix.isEmpty, !installationRoot.isEmpty, !selectedEntryPath.isEmpty,
              !selectedTarget.isEmpty, !selectedFingerprint.isEmpty, !proofFingerprint.isEmpty,
              !contextDigest.isEmpty, !name.isEmpty, !version.isEmpty, !distTagsLatest.isEmpty
        else { return false }
        return NpmMetadataSemantics.isAcceptedNormalizedRegistry(registry)
            && tag == NpmMetadataSemantics.latestTag
            && NpmMetadataSemantics.isValidNpmPackageName(package)
            && name == package
            && NpmMetadataSemantics.versionMatchesLatestTag(version, distTagsLatest: distTagsLatest)
            && NpmMetadataSemantics.isStableSemanticVersion(version)
    }

    private enum CodingKeys: String, CodingKey {
        case registryID, package, registry, tag
        case managerEntryPath, managerTarget, managerFingerprint
        case prefix, installationRoot
        case selectedEntryPath, selectedTarget, selectedFingerprint, proofFingerprint
        case contextDigest
        case name, version, distTagsLatest
        case observedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        registryID = try container.decode(String.self, forKey: .registryID)
        package = try container.decode(String.self, forKey: .package)
        registry = try container.decode(String.self, forKey: .registry)
        tag = try container.decode(String.self, forKey: .tag)
        managerEntryPath = try container.decode(String.self, forKey: .managerEntryPath)
        managerTarget = try container.decode(String.self, forKey: .managerTarget)
        managerFingerprint = try container.decode(String.self, forKey: .managerFingerprint)
        prefix = try container.decode(String.self, forKey: .prefix)
        installationRoot = try container.decode(String.self, forKey: .installationRoot)
        selectedEntryPath = try container.decode(String.self, forKey: .selectedEntryPath)
        selectedTarget = try container.decode(String.self, forKey: .selectedTarget)
        selectedFingerprint = try container.decode(String.self, forKey: .selectedFingerprint)
        proofFingerprint = try container.decode(String.self, forKey: .proofFingerprint)
        contextDigest = try container.decode(String.self, forKey: .contextDigest)
        name = try container.decode(String.self, forKey: .name)
        version = try container.decode(String.self, forKey: .version)
        distTagsLatest = try container.decode(String.self, forKey: .distTagsLatest)
        let text = try container.decode(String.self, forKey: .observedAt)
        guard let interval = Double(text), interval.isFinite else {
            throw DecodingError.dataCorruptedError(
                forKey: .observedAt, in: container,
                debugDescription: "observation timestamp is not an exact finite interval"
            )
        }
        observedAt = Date(timeIntervalSince1970: interval)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(registryID, forKey: .registryID)
        try container.encode(package, forKey: .package)
        try container.encode(registry, forKey: .registry)
        try container.encode(tag, forKey: .tag)
        try container.encode(managerEntryPath, forKey: .managerEntryPath)
        try container.encode(managerTarget, forKey: .managerTarget)
        try container.encode(managerFingerprint, forKey: .managerFingerprint)
        try container.encode(prefix, forKey: .prefix)
        try container.encode(installationRoot, forKey: .installationRoot)
        try container.encode(selectedEntryPath, forKey: .selectedEntryPath)
        try container.encode(selectedTarget, forKey: .selectedTarget)
        try container.encode(selectedFingerprint, forKey: .selectedFingerprint)
        try container.encode(proofFingerprint, forKey: .proofFingerprint)
        try container.encode(contextDigest, forKey: .contextDigest)
        try container.encode(name, forKey: .name)
        try container.encode(version, forKey: .version)
        try container.encode(distTagsLatest, forKey: .distTagsLatest)
        try container.encode(observedAt.timeIntervalSince1970.description, forKey: .observedAt)
    }
}

/// Identity of one cached npm selection. Every field must match for a hit.
public struct NpmUpdateMetadataKey: Equatable, Sendable {
    public let registryID: String
    public let package: String
    public let registry: String
    public let tag: String
    public let managerEntryPath: String
    public let managerTarget: String
    public let managerFingerprint: String
    public let prefix: String
    public let installationRoot: String
    public let selectedEntryPath: String
    public let selectedTarget: String
    public let selectedFingerprint: String
    public let proofFingerprint: String
    public let contextDigest: String

    public init(
        registryID: String,
        package: String,
        registry: String,
        tag: String,
        managerEntryPath: String,
        managerTarget: String,
        managerFingerprint: String,
        prefix: String,
        installationRoot: String,
        selectedEntryPath: String,
        selectedTarget: String,
        selectedFingerprint: String,
        proofFingerprint: String,
        contextDigest: String
    ) {
        self.registryID = registryID
        self.package = package
        self.registry = registry
        self.tag = tag
        self.managerEntryPath = managerEntryPath
        self.managerTarget = managerTarget
        self.managerFingerprint = managerFingerprint
        self.prefix = prefix
        self.installationRoot = installationRoot
        self.selectedEntryPath = selectedEntryPath
        self.selectedTarget = selectedTarget
        self.selectedFingerprint = selectedFingerprint
        self.proofFingerprint = proofFingerprint
        self.contextDigest = contextDigest
    }

    func matches(_ requested: NpmUpdateMetadataKey) -> Bool {
        registryID == requested.registryID
            && package == requested.package
            && registry == requested.registry
            && tag == requested.tag
            && managerEntryPath == requested.managerEntryPath
            && managerTarget == requested.managerTarget
            && managerFingerprint == requested.managerFingerprint
            && prefix == requested.prefix
            && installationRoot == requested.installationRoot
            && selectedEntryPath == requested.selectedEntryPath
            && selectedTarget == requested.selectedTarget
            && selectedFingerprint == requested.selectedFingerprint
            && proofFingerprint == requested.proofFingerprint
            && contextDigest == requested.contextDigest
    }

    /// Lowercase hex SHA-256. Stable across processes and platforms, unlike `Hasher`.
    public static func stableDigest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Versioned on-disk document. Unknown or older schema versions are misses, never migrated
/// silently: schema 1 requires the full selected npm identity and exact-precision timestamp.
struct NpmUpdateMetadataDocument: Codable, Equatable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let entries: [NpmUpdateMetadataEntry]
}

/// One process-wide serialization token for the npm metadata document. Foundation `NSLock` only:
/// no new locking framework or dependency is introduced. It serializes IN-PROCESS read/merge/write
/// (B04.3) — the coordinator's stage admission alone does not serialize direct or concurrent saves.
/// Cross-process contention still relies on atomic last-writer replacement, which may lose a cache
/// hit but can never authorize a stale identity or a corrupt document; no cross-process lock is
/// claimed or added.
private final class NpmCacheDocumentLock: @unchecked Sendable {
    let lock = NSLock()
}

private let npmUpdateMetadataDocumentLock = NpmCacheDocumentLock()

/// Runs one document operation as a single in-process critical section. These sections never await
/// and never nest, so no path can hold the lock across a suspension or deadlock on itself.
private func withNpmCacheDocumentLock<T>(_ operation: () -> T) -> T {
    npmUpdateMetadataDocumentLock.lock.lock()
    defer { npmUpdateMetadataDocumentLock.lock.unlock() }
    return operation()
}

/// Bounded npm latest-metadata document cache beside the injected Homebrew cache.
///
/// Derive the persistent npm document as a sibling of `updateCacheURL`; never add a required
/// second cache argument. Production nil scratch base uses Foundation `temporaryDirectory`;
/// tests/host supply an owned scratch root.
public struct NpmUpdateMetadataCache: Sendable {

    /// Exactly six hours; `0 <= age < ttl` is a hit.
    public static let ttl: TimeInterval = 21_600
    /// Maximum bytes read or written for the document.
    public static let maximumDocumentBytes = 1_048_576

    /// The npm metadata document lives beside the injected update cache URL.
    public let fileURL: URL
    public let now: @Sendable () -> Date

    /// Creates a cache whose document is a sibling of `updateCacheURL`.
    public init(
        updateCacheURL: URL,
        now: @escaping @Sendable () -> Date
    ) {
        self.fileURL = updateCacheURL.deletingLastPathComponent()
            .appendingPathComponent("npm-update-metadata-v1.json")
        self.now = now
    }

    /// The stored entry for the complete identity key only when EXACTLY ONE record matches it, that
    /// record satisfies the same strict validation that authorized a fresh parse, and its age is
    /// inside the TTL. Any read, size, JSON, schema, identity, semantic, or timestamp failure is a
    /// miss. The read is one in-process critical section so a concurrent `save` cannot interleave a
    /// half-merged document (B04.3).
    public func lookup(_ key: NpmUpdateMetadataKey) -> NpmUpdateMetadataEntry? {
        withNpmCacheDocumentLock { lookupUnlocked(key) }
    }

    private func lookupUnlocked(_ key: NpmUpdateMetadataKey) -> NpmUpdateMetadataEntry? {
        guard let document = readDocument() else { return nil }
        let current = now()
        var live: [NpmUpdateMetadataEntry] = []
        for entry in document.entries where entry.key.matches(key) {
            // A key match is not proof of valid metadata. If ANY record for this identity fails the
            // strict rules, the identity is corrupted: fail closed instead of promoting a sibling
            // record that happens to parse.
            guard entry.isFullyValidatedRecord else { return nil }
            let age = current.timeIntervalSince(entry.observedAt)
            guard age >= 0 && age < Self.ttl else { continue }
            live.append(entry)
        }
        // Two live records for one identity is ambiguity, never a silent first-wins.
        guard live.count == 1 else { return nil }
        return live.first
    }

    /// Refuses any entry that is not a fully validated record, then reads, prunes, merges and writes
    /// the union atomically as ONE in-process critical section (B04.3). Returns false when the write
    /// fails; the caller keeps its current successful result either way.
    @discardableResult
    public func save(_ entries: [NpmUpdateMetadataEntry]) -> Bool {
        guard entries.allSatisfy(\.isFullyValidatedRecord) else { return false }
        return withNpmCacheDocumentLock { saveMerged(entries) }
    }

    /// Reads the current document, prunes expired/future/unvalidated records and records whose
    /// identity is being replaced, and writes the union with `entries` atomically (M10-B brief
    /// B04.3). Fully validated unexpired records for OTHER identities are preserved verbatim; only
    /// an identity matching one of the incoming entries is replaced. A corrupt, oversize, or
    /// schema-mismatched npm document is treated as empty so a fresh validated record can still be
    /// persisted. The separate Homebrew document is never read or written here.
    ///
    /// Contamination is classified per COMPLETE identity BEFORE any per-record pruning. If ANY
    /// record of an identity fails the strict rules, that identity is corrupted, so EVERY stored
    /// record of it is dropped: an unrelated save can never prune the poison and thereby promote
    /// the surviving valid-looking sibling into a cache hit this process never verified. Only an
    /// incoming verified record for that same identity (below, or a later save) can repair it.
    ///
    /// A pre-existing DUPLICATE identity of wholly valid records belonging to another tool is never
    /// collapsed to a "latest wins": the duplicates survive an unrelated save and remain an
    /// ambiguity miss until that identity itself stores a verified record, at which point every
    /// stored copy of it is replaced by the single incoming one. Silently choosing a winner would
    /// manufacture a cache hit from a document this process never verified.
    private func saveMerged(_ entries: [NpmUpdateMetadataEntry]) -> Bool {
        let current = now()
        func withinTTL(_ observedAt: Date) -> Bool {
            let age = current.timeIntervalSince(observedAt)
            return age >= 0 && age < Self.ttl
        }
        let incomingDigests = Set(entries.map { npmMetadataKeyDigest($0.key) })

        // A missing/corrupt/oversize/schema-mismatched npm document is treated as empty.
        let existing = readDocument()?.entries ?? []

        // First pass: preclassify every complete identity present in the document.
        var groups: [String: [NpmUpdateMetadataEntry]] = [:]
        var order: [String] = []
        for entry in existing {
            let digest = npmMetadataKeyDigest(entry.key)
            if groups[digest] == nil { order.append(digest) }
            groups[digest, default: []].append(entry)
        }

        var keptExisting: [NpmUpdateMetadataEntry] = []
        for digest in order {
            let group = groups[digest] ?? []
            // Replacing identity: every stored copy of it gives way to the incoming record.
            if incomingDigests.contains(digest) { continue }
            // Contaminated identity: one invalid record makes the whole identity unusable, so it
            // is dropped entirely rather than pruned record by record (which would promote a
            // valid-looking sibling into an unverified hit).
            if !group.allSatisfy(\.isFullyValidatedRecord) { continue }
            // Fully valid identity: keep live records verbatim, including ambiguity duplicates,
            // and prune only expired/future ones.
            keptExisting.append(contentsOf: group.filter { withinTTL($0.observedAt) })
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        func encodedSize(_ items: [NpmUpdateMetadataEntry]) -> Int? {
            let document = NpmUpdateMetadataDocument(
                schemaVersion: NpmUpdateMetadataDocument.currentSchemaVersion,
                entries: items
            )
            return try? encoder.encode(document).count
        }

        var items = keptExisting + entries
        guard let size = encodedSize(items) else { return false }
        if size > Self.maximumDocumentBytes {
            // Drop the incoming record itself rather than evict another tool's record. If the
            // document still exceeds the cap, the record cannot be stored.
            items = keptExisting
            guard let retrySize = encodedSize(items), retrySize <= Self.maximumDocumentBytes
            else { return false }
        }

        let document = NpmUpdateMetadataDocument(
            schemaVersion: NpmUpdateMetadataDocument.currentSchemaVersion,
            entries: items
        )
        guard let data = try? encoder.encode(document),
              data.count <= Self.maximumDocumentBytes
        else {
            return false
        }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    private func readDocument() -> NpmUpdateMetadataDocument? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: Self.maximumDocumentBytes + 1),
              data.count <= Self.maximumDocumentBytes
        else {
            return nil
        }
        guard let document = try? JSONDecoder().decode(NpmUpdateMetadataDocument.self, from: data),
              document.schemaVersion == NpmUpdateMetadataDocument.currentSchemaVersion
        else {
            return nil
        }
        return document
    }
}

private extension NpmUpdateMetadataEntry {
    var key: NpmUpdateMetadataKey {
        NpmUpdateMetadataKey(
            registryID: registryID,
            package: package,
            registry: registry,
            tag: tag,
            managerEntryPath: managerEntryPath,
            managerTarget: managerTarget,
            managerFingerprint: managerFingerprint,
            prefix: prefix,
            installationRoot: installationRoot,
            selectedEntryPath: selectedEntryPath,
            selectedTarget: selectedTarget,
            selectedFingerprint: selectedFingerprint,
            proofFingerprint: proofFingerprint,
            contextDigest: contextDigest
        )
    }
}

/// A stable, length-framed digest of every identity field of a key, so `save` can dedupe and match
/// records without requiring the key struct to be `Hashable`. Deterministic across processes and
/// platforms; uses the same SHA-256 helper as the key itself.
private func npmMetadataKeyDigest(_ key: NpmUpdateMetadataKey) -> String {
    func frame(_ text: String) -> String { "\(text.utf8.count):\(text)" }
    let material = frame("agent-lens-npm-cache-key-v1")
        + frame(key.registryID) + frame(key.package) + frame(key.registry) + frame(key.tag)
        + frame(key.managerEntryPath) + frame(key.managerTarget) + frame(key.managerFingerprint)
        + frame(key.prefix) + frame(key.installationRoot)
        + frame(key.selectedEntryPath) + frame(key.selectedTarget) + frame(key.selectedFingerprint)
        + frame(key.proofFingerprint) + frame(key.contextDigest)
    return NpmUpdateMetadataKey.stableDigest(material)
}
