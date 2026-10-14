// UpdateMetadataCache — M6 six-hour metadata cache (brief §"Cache contract").
//
// Persists validated SUCCESSFUL selected-tool metadata only, never a precomputed status.
// Status is recomputed on every run from current local facts. The file is versioned,
// size-limited to 1 MiB in both directions, and replaced atomically in its own directory.
// Keys include a stable SHA-256 of a deterministic serialization, never Swift's randomized
// Hasher, and no raw environment, credentials, or unrelated package inventory is stored.
//
// Identity is carried in full: the registry ID (never a display name or executable basename),
// the manager's PATH entry plus its canonical target and captured fingerprint, the
// manager-verified Cellar, the formula STEM and its verified FULL identity (`name` or
// `owner/tap/name`), the selected entry and canonical keg target, and the probe-context digest.
// Full formula identity is part of every persistent key. A query-free selection lookup can find a
// unique complete record without knowing its Cellar or full formula identity in advance; it never
// fabricates either value from a basename.

import CryptoKit
import Foundation

/// Identity of one cached selection. Every field must match for a hit.
public struct UpdateMetadataKey: Equatable, Sendable {
    public let registryID: String
    public let managerEntryPath: String
    public let managerTarget: String
    public let managerFingerprint: String
    public let cellar: String
    public let formulaStem: String
    /// Exact verified manager identity (`name` or `owner/tap/name`).
    public let fullFormulaName: String
    public let selectedEntryPath: String
    public let selectedKegVersion: String
    public let selectedTarget: String
    public let contextFingerprint: String

    public init(registryID: String, managerEntryPath: String, managerTarget: String,
                managerFingerprint: String, cellar: String, formulaStem: String,
                fullFormulaName: String, selectedEntryPath: String,
                selectedKegVersion: String, selectedTarget: String, contextFingerprint: String) {
        self.registryID = registryID
        self.managerEntryPath = managerEntryPath
        self.managerTarget = managerTarget
        self.managerFingerprint = managerFingerprint
        self.cellar = cellar
        self.formulaStem = formulaStem
        self.fullFormulaName = fullFormulaName
        self.selectedEntryPath = selectedEntryPath
        self.selectedKegVersion = selectedKegVersion
        self.selectedTarget = selectedTarget
        self.contextFingerprint = contextFingerprint
    }

    func matches(_ requested: UpdateMetadataKey) -> Bool {
        registryID == requested.registryID
            && managerEntryPath == requested.managerEntryPath
            && managerTarget == requested.managerTarget
            && managerFingerprint == requested.managerFingerprint
            && cellar == requested.cellar
            && formulaStem == requested.formulaStem
            && fullFormulaName == requested.fullFormulaName
            && selectedEntryPath == requested.selectedEntryPath
            && selectedKegVersion == requested.selectedKegVersion
            && selectedTarget == requested.selectedTarget
            && contextFingerprint == requested.contextFingerprint
    }

    /// Lowercase hex SHA-256. Stable across processes and platforms, unlike `Hasher`.
    public static func stableDigest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// The manager, selected entry/target, registry identity, and query context known before a
/// cache hit. Cellar, keg decomposition, and full formula identity are restored only from one
/// uniquely matching, structurally coherent stored record.
struct UpdateMetadataSelection: Equatable, Sendable {
    let registryID: String
    let managerEntryPath: String
    let managerTarget: String
    let managerFingerprint: String
    let selectedEntryPath: String
    let selectedTarget: String
    let contextFingerprint: String

    func matches(_ entry: UpdateMetadataEntry) -> Bool {
        registryID == entry.registryID
            && managerEntryPath == entry.managerEntryPath
            && managerTarget == entry.managerTarget
            && managerFingerprint == entry.managerFingerprint
            && selectedEntryPath == entry.selectedEntryPath
            && selectedTarget == entry.selectedTarget
            && contextFingerprint == entry.contextFingerprint
    }
}

/// One validated, successful metadata observation for a selected formula.
public struct UpdateMetadataEntry: Equatable, Sendable, Codable {
    public let registryID: String
    public let managerEntryPath: String
    public let managerTarget: String
    public let managerFingerprint: String
    public let cellar: String
    public let formulaStem: String
    /// The manager's own full identity claim for the formula, retained verbatim. Never derived
    /// from `formulaStem` on restore: a record that cannot name its tap is incomplete.
    public let fullFormulaName: String
    public let selectedEntryPath: String
    public let selectedKegVersion: String
    public let selectedTarget: String
    public let contextFingerprint: String
    public let formulaStable: String
    public let formulaRevision: Int
    public let installedVersions: [String]
    public let observedAt: Date

    public init(registryID: String, managerEntryPath: String, managerTarget: String,
                managerFingerprint: String, cellar: String, formulaStem: String,
                fullFormulaName: String, selectedEntryPath: String, selectedKegVersion: String,
                selectedTarget: String,
                contextFingerprint: String, formulaStable: String, formulaRevision: Int,
                installedVersions: [String], observedAt: Date) {
        self.registryID = registryID
        self.managerEntryPath = managerEntryPath
        self.managerTarget = managerTarget
        self.managerFingerprint = managerFingerprint
        self.cellar = cellar
        self.formulaStem = formulaStem
        self.fullFormulaName = fullFormulaName
        self.selectedEntryPath = selectedEntryPath
        self.selectedKegVersion = selectedKegVersion
        self.selectedTarget = selectedTarget
        self.contextFingerprint = contextFingerprint
        self.formulaStable = formulaStable
        self.formulaRevision = formulaRevision
        self.installedVersions = installedVersions
        self.observedAt = observedAt
    }

    public var key: UpdateMetadataKey {
        UpdateMetadataKey(registryID: registryID, managerEntryPath: managerEntryPath,
                          managerTarget: managerTarget, managerFingerprint: managerFingerprint,
                          cellar: cellar, formulaStem: formulaStem, fullFormulaName: fullFormulaName,
                          selectedEntryPath: selectedEntryPath, selectedKegVersion: selectedKegVersion,
                          selectedTarget: selectedTarget,
                          contextFingerprint: contextFingerprint)
    }

    /// A restored record must agree with itself before it can support any claim: the recorded
    /// full formula identity must be the stem or `owner/tap/stem`, the selected target must sit
    /// inside the recorded Cellar with formula, keg, and executable components, the formula
    /// component must equal the recorded stem, and the recorded inventory must actually list the
    /// selected keg. Nothing here launches a query — it only refuses to lend a self-contradictory
    /// record to a selection.
    public var isStructurallyCoherent: Bool {
        guard !registryID.isEmpty, !managerEntryPath.isEmpty, !managerTarget.isEmpty,
              !managerFingerprint.isEmpty, !contextFingerprint.isEmpty,
              !selectedEntryPath.isEmpty, !selectedTarget.isEmpty,
              !cellar.isEmpty, !formulaStem.isEmpty, !selectedKegVersion.isEmpty, !formulaStable.isEmpty,
              formulaRevision >= 0, !installedVersions.isEmpty,
              HomebrewUpdateProbe.isSupportedUpstreamVersion(formulaStable)
        else { return false }
        guard HomebrewUpdateProbe.formulaIdentityConsistent(name: formulaStem, fullName: fullFormulaName)
        else { return false }
        guard case .success(let keg) = HomebrewTargetParser.parse(selectedTarget: selectedTarget, cellar: cellar),
              keg.formula == formulaStem, keg.kegVersion == selectedKegVersion
        else { return false }
        return installedVersions.contains(keg.kegVersion)
    }

    // MARK: Exact-precision timestamp serialization
    //
    // `.iso8601` truncates to whole seconds, which silently shifted a fractional observation and
    // pushed an in-TTL entry past the boundary. The interval is therefore carried as the shortest
    // round-trippable decimal text of the same Double, so the restored date is bit-identical to
    // the observed one. Every identity field is required: a document missing one fails to decode
    // and is a miss, never a partially reconstructed record.

    private enum CodingKeys: String, CodingKey {
        case registryID
        case managerEntryPath
        case managerTarget
        case managerFingerprint
        case cellar
        case formulaStem
        case fullFormulaName
        case selectedEntryPath
        case selectedKegVersion
        case selectedTarget
        case contextFingerprint
        case formulaStable
        case formulaRevision
        case installedVersions
        case observedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        registryID = try container.decode(String.self, forKey: .registryID)
        managerEntryPath = try container.decode(String.self, forKey: .managerEntryPath)
        managerTarget = try container.decode(String.self, forKey: .managerTarget)
        managerFingerprint = try container.decode(String.self, forKey: .managerFingerprint)
        cellar = try container.decode(String.self, forKey: .cellar)
        formulaStem = try container.decode(String.self, forKey: .formulaStem)
        fullFormulaName = try container.decode(String.self, forKey: .fullFormulaName)
        selectedEntryPath = try container.decode(String.self, forKey: .selectedEntryPath)
        selectedKegVersion = try container.decode(String.self, forKey: .selectedKegVersion)
        selectedTarget = try container.decode(String.self, forKey: .selectedTarget)
        contextFingerprint = try container.decode(String.self, forKey: .contextFingerprint)
        formulaStable = try container.decode(String.self, forKey: .formulaStable)
        formulaRevision = try container.decode(Int.self, forKey: .formulaRevision)
        installedVersions = try container.decode([String].self, forKey: .installedVersions)
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
        try container.encode(managerEntryPath, forKey: .managerEntryPath)
        try container.encode(managerTarget, forKey: .managerTarget)
        try container.encode(managerFingerprint, forKey: .managerFingerprint)
        try container.encode(cellar, forKey: .cellar)
        try container.encode(formulaStem, forKey: .formulaStem)
        try container.encode(fullFormulaName, forKey: .fullFormulaName)
        try container.encode(selectedEntryPath, forKey: .selectedEntryPath)
        try container.encode(selectedKegVersion, forKey: .selectedKegVersion)
        try container.encode(selectedTarget, forKey: .selectedTarget)
        try container.encode(contextFingerprint, forKey: .contextFingerprint)
        try container.encode(formulaStable, forKey: .formulaStable)
        try container.encode(formulaRevision, forKey: .formulaRevision)
        try container.encode(installedVersions, forKey: .installedVersions)
        try container.encode(observedAt.timeIntervalSince1970.description, forKey: .observedAt)
    }
}

/// Versioned on-disk document. Unknown or older schema versions are misses, never migrated
/// silently: schema 3 requires the full selected-keg identity and exact-precision timestamp, so an
/// older incomplete document cannot pass as a valid record.
struct UpdateMetadataDocument: Codable, Equatable {
    static let currentSchemaVersion = 3

    let schemaVersion: Int
    let entries: [UpdateMetadataEntry]
}

public struct UpdateMetadataCache: Sendable {

    /// Exactly six hours; `0 <= age < ttl` is a hit.
    public static let ttl: TimeInterval = 21_600
    /// Maximum bytes read or written for the document.
    public static let maximumDocumentBytes = 1_048_576

    public let fileURL: URL
    public let now: @Sendable () -> Date

    public init(fileURL: URL, now: @escaping @Sendable () -> Date) {
        self.fileURL = fileURL
        self.now = now
    }

    /// The stored entry for the complete identity key when it is present, self-consistent, and
    /// within the TTL. Any read, size, JSON, schema, identity, or timestamp failure is a miss.
    public func lookup(_ key: UpdateMetadataKey) -> UpdateMetadataEntry? {
        lookup { $0.key.matches(key) }
    }

    /// Restores a previously verified complete identity for this exact manager/selection/context.
    /// Ambiguous Cellar or full-formula identities are misses, never first-wins.
    func lookup(_ selection: UpdateMetadataSelection) -> UpdateMetadataEntry? {
        lookup { selection.matches($0) }
    }

    private func lookup(matching predicate: (UpdateMetadataEntry) -> Bool) -> UpdateMetadataEntry? {
        guard let document = readDocument() else { return nil }
        let current = now()
        var matches: [UpdateMetadataEntry] = []
        for entry in document.entries where predicate(entry) {
            guard entry.isStructurallyCoherent else { continue }
            let age = current.timeIntervalSince(entry.observedAt)
            guard age >= 0 && age < Self.ttl else { continue }
            matches.append(entry)
        }
        // Two live records for one identity is ambiguity, never a silent first-wins.
        guard matches.count == 1 else { return nil }
        return matches.first
    }

    /// Atomically replaces the document with the given validated entries. Returns false when
    /// the write fails; the caller keeps its current successful result either way.
    @discardableResult
    public func save(_ entries: [UpdateMetadataEntry]) -> Bool {
        guard entries.allSatisfy(\.isStructurallyCoherent) else { return false }
        let document = UpdateMetadataDocument(
            schemaVersion: UpdateMetadataDocument.currentSchemaVersion,
            entries: entries
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
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

    private func readDocument() -> UpdateMetadataDocument? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: Self.maximumDocumentBytes + 1),
              data.count <= Self.maximumDocumentBytes
        else {
            return nil
        }
        guard let document = try? JSONDecoder().decode(UpdateMetadataDocument.self, from: data),
              document.schemaVersion == UpdateMetadataDocument.currentSchemaVersion
        else {
            return nil
        }
        return document
    }
}