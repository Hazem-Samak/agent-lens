// CaskUpdateMetadataCache — M13-B isolated cask latest-metadata document (R3).
//
// A SEPARATE document (`cask-update-metadata-v1.json`) beside the formula (schema 3) and npm
// (schema 1) documents. It is never a schema extension of either, never read by an operation, and
// never satisfies a formula or npm lookup. Only successful verified comparisons are stored;
// `unknown` is never written. Status is recomputed on restore from the manager's own observation,
// never trusted as a precomputed verdict.
//
// Identity is carried in full: registry ID, manager entry/target/fingerprint, the reported and
// canonical prefix/Caskroom paths with their directory identities, token, full token, tap, the
// manager's installed version, the exact token/version directory identities, the selected entry
// and target executable identity, the current declaration set, and a length-framed context digest
// with its own domain label. A restore fails closed unless every one of those still names the live
// selection and every recorded directory is still the exact bound directory: a retargeted alias,
// a replaced selected executable at the same path, or an altered declaration is a miss.
//
// Cask version strings are opaque. The cache never orders them: a manager-outdated verdict is
// coherent with any unequal pair and an `upToDate` verdict requires manager-string equality.

import CryptoKit
import Foundation

/// One validated, successful cask comparison observation for a verified selection.
public struct CaskUpdateMetadataEntry: Equatable, Sendable, Codable {
    public let registryID: String
    public let managerEntryPath: String
    public let managerTarget: String
    public let managerFingerprint: String
    /// The manager's reported prefix spelling and the identity observed through it.
    public let prefix: String
    public let prefixCanonical: String
    public let prefixDevice: UInt64
    public let prefixInode: UInt64
    /// The manager's reported Caskroom spelling and the identity observed through it.
    public let caskroom: String
    public let caskroomCanonical: String
    public let caskroomDevice: UInt64
    public let caskroomInode: UInt64
    public let token: String
    public let fullToken: String
    public let tap: String
    public let installedVersion: String
    /// Exact `<caskroomCanonical>/<token>` directory and identity.
    public let tokenDirectoryPath: String
    public let tokenDirectoryDevice: UInt64
    public let tokenDirectoryInode: UInt64
    /// Exact `<tokenDirectoryPath>/<installedVersion>` directory and identity.
    public let versionDirectoryPath: String
    public let versionDirectoryDevice: UInt64
    public let versionDirectoryInode: UInt64
    public let selectedEntryPath: String
    public let selectedTarget: String
    /// Stable digest of the observed selected executable identity (device/inode/mode/size/times).
    public let selectedFingerprint: String
    /// Stable digest of the current declared cask-name set for this registry subject.
    public let declarationsDigest: String
    public let contextDigest: String
    /// The manager-reported latest version string, retained verbatim (opaque text).
    public let version: String
    public let pinned: Bool
    /// The manager's own outdated verdict at observation. A verified `updateAvailable` stores
    /// `true`; a verified `upToDate` stores `false`.
    public let managerOutdated: Bool
    public let observedAt: Date

    public init(
        registryID: String,
        managerEntryPath: String,
        managerTarget: String,
        managerFingerprint: String,
        prefix: String,
        prefixCanonical: String,
        prefixDevice: UInt64,
        prefixInode: UInt64,
        caskroom: String,
        caskroomCanonical: String,
        caskroomDevice: UInt64,
        caskroomInode: UInt64,
        token: String,
        fullToken: String,
        tap: String,
        installedVersion: String,
        tokenDirectoryPath: String,
        tokenDirectoryDevice: UInt64,
        tokenDirectoryInode: UInt64,
        versionDirectoryPath: String,
        versionDirectoryDevice: UInt64,
        versionDirectoryInode: UInt64,
        selectedEntryPath: String,
        selectedTarget: String,
        selectedFingerprint: String,
        declarationsDigest: String,
        contextDigest: String,
        version: String,
        pinned: Bool,
        managerOutdated: Bool,
        observedAt: Date
    ) {
        self.registryID = registryID
        self.managerEntryPath = managerEntryPath
        self.managerTarget = managerTarget
        self.managerFingerprint = managerFingerprint
        self.prefix = prefix
        self.prefixCanonical = prefixCanonical
        self.prefixDevice = prefixDevice
        self.prefixInode = prefixInode
        self.caskroom = caskroom
        self.caskroomCanonical = caskroomCanonical
        self.caskroomDevice = caskroomDevice
        self.caskroomInode = caskroomInode
        self.token = token
        self.fullToken = fullToken
        self.tap = tap
        self.installedVersion = installedVersion
        self.tokenDirectoryPath = tokenDirectoryPath
        self.tokenDirectoryDevice = tokenDirectoryDevice
        self.tokenDirectoryInode = tokenDirectoryInode
        self.versionDirectoryPath = versionDirectoryPath
        self.versionDirectoryDevice = versionDirectoryDevice
        self.versionDirectoryInode = versionDirectoryInode
        self.selectedEntryPath = selectedEntryPath
        self.selectedTarget = selectedTarget
        self.selectedFingerprint = selectedFingerprint
        self.declarationsDigest = declarationsDigest
        self.contextDigest = contextDigest
        self.version = version
        self.pinned = pinned
        self.managerOutdated = managerOutdated
        self.observedAt = observedAt
    }

    public var key: CaskUpdateMetadataKey {
        CaskUpdateMetadataKey(
            registryID: registryID,
            managerEntryPath: managerEntryPath,
            managerTarget: managerTarget,
            managerFingerprint: managerFingerprint,
            prefix: prefix,
            prefixCanonical: prefixCanonical,
            prefixDevice: prefixDevice,
            prefixInode: prefixInode,
            caskroom: caskroom,
            caskroomCanonical: caskroomCanonical,
            caskroomDevice: caskroomDevice,
            caskroomInode: caskroomInode,
            token: token,
            fullToken: fullToken,
            tap: tap,
            installedVersion: installedVersion,
            tokenDirectoryPath: tokenDirectoryPath,
            tokenDirectoryDevice: tokenDirectoryDevice,
            tokenDirectoryInode: tokenDirectoryInode,
            versionDirectoryPath: versionDirectoryPath,
            versionDirectoryDevice: versionDirectoryDevice,
            versionDirectoryInode: versionDirectoryInode,
            selectedEntryPath: selectedEntryPath,
            selectedTarget: selectedTarget,
            selectedFingerprint: selectedFingerprint,
            declarationsDigest: declarationsDigest,
            contextDigest: contextDigest
        )
    }

    /// A restored record must agree with itself before it can support any claim. Nothing here
    /// launches a query; the live bindings are rechecked separately.
    public var isStructurallyCoherent: Bool {
        guard !registryID.isEmpty, !managerEntryPath.isEmpty, !managerTarget.isEmpty,
              !managerFingerprint.isEmpty, !prefix.isEmpty, !prefixCanonical.isEmpty,
              !caskroom.isEmpty, !caskroomCanonical.isEmpty,
              !token.isEmpty, !fullToken.isEmpty, !tap.isEmpty, !installedVersion.isEmpty,
              !tokenDirectoryPath.isEmpty, !versionDirectoryPath.isEmpty,
              !selectedEntryPath.isEmpty, !selectedTarget.isEmpty,
              !selectedFingerprint.isEmpty, !declarationsDigest.isEmpty,
              !contextDigest.isEmpty, !version.isEmpty
        else { return false }
        guard Self.isCleanAbsolutePath(prefix),
              Self.isCleanAbsolutePath(prefixCanonical),
              Self.isCleanAbsolutePath(caskroom),
              Self.isCleanAbsolutePath(caskroomCanonical),
              Self.isCleanAbsolutePath(managerEntryPath),
              Self.isCleanAbsolutePath(selectedEntryPath),
              Self.isCleanAbsolutePath(selectedTarget),
              Self.isCleanAbsolutePath(tokenDirectoryPath),
              Self.isCleanAbsolutePath(versionDirectoryPath)
        else { return false }
        guard HomebrewCaskUpdateProbe.isStructurallyValidCask(
            token: token, fullToken: fullToken, tap: tap
        ) else { return false }
        guard Self.isCleanPathComponent(installedVersion) else { return false }
        guard HomebrewCaskUpdateProbe.isSafeVersionText(version), version != "latest" else {
            return false
        }
        guard tokenDirectoryPath == HomebrewCaskUpdateProbe.appendedPath(
            caskroomCanonical, token
        ), versionDirectoryPath == HomebrewCaskUpdateProbe.appendedPath(
            tokenDirectoryPath, installedVersion
        ) else { return false }
        guard case .success(let staged) = HomebrewCaskTargetParser.parse(
            selectedTarget: selectedTarget, caskroom: caskroomCanonical
        ), staged.token == token,
           staged.versionDirectory == installedVersion,
           staged.selectedTarget == selectedTarget
        else { return false }
        // Only the two successful comparison shapes exist. Version strings are opaque: a recorded
        // manager-outdated verdict requires only an unequal pair, and `upToDate` requires manager
        // string equality. No formula ordering is consulted in either direction.
        if managerOutdated {
            return installedVersion != version
        }
        return installedVersion == version
    }

    /// Re-observes the reported prefix/Caskroom paths, the selected executable and the exact
    /// token/version directories. Any replacement, retarget or alias change is a miss. This is a
    /// filesystem check only: a fully valid hit still launches zero manager queries.
    public var stagedBindingsAreCurrent: Bool {
        guard selectedExecutableIsCurrent else { return false }
        guard Self.rootIsCurrent(
            reported: prefix,
            canonical: prefixCanonical,
            device: prefixDevice,
            inode: prefixInode
        ), Self.rootIsCurrent(
            reported: caskroom,
            canonical: caskroomCanonical,
            device: caskroomDevice,
            inode: caskroomInode
        ) else { return false }

        guard let tokenIdentity = FileIdentityObserver.observeDirectory(
            path: tokenDirectoryPath
        ), tokenIdentity.canonicalPath == tokenDirectoryPath,
           tokenIdentity.device == tokenDirectoryDevice,
           tokenIdentity.inode == tokenDirectoryInode,
           FileIdentityObserver.isExactDescendant(
               tokenIdentity.canonicalPath,
               of: caskroomCanonical,
               components: [token]
           )
        else { return false }

        guard let versionIdentity = FileIdentityObserver.observeDirectory(
            path: versionDirectoryPath
        ), versionIdentity.canonicalPath == versionDirectoryPath,
           versionIdentity.device == versionDirectoryDevice,
           versionIdentity.inode == versionDirectoryInode,
           FileIdentityObserver.isExactDescendant(
               versionIdentity.canonicalPath,
               of: tokenDirectoryPath,
               components: [installedVersion]
           )
        else { return false }

        // The selected artifact itself must still be the recorded regular staged file.
        guard let mode = Self.linkStatusMode(selectedTarget) else { return false }
        return (mode & mode_t(S_IFMT)) == mode_t(S_IFREG)
    }

    /// The selected executable at its recorded entry must still resolve to the recorded target and
    /// carry the same observed identity. This catches a same-path replacement even for an exact-key
    /// lookup, not only for the coordinator's selection lookup.
    public var selectedExecutableIsCurrent: Bool {
        guard let observed = FileIdentityObserver.observeExecutable(
            entryPath: selectedEntryPath
        ) else { return false }
        return observed.canonicalTarget == selectedTarget
            && CaskUpdateMetadataKey.selectedFingerprintDigest(observed.fingerprint)
                == selectedFingerprint
    }

    private static func rootIsCurrent(
        reported: String,
        canonical: String,
        device: UInt64,
        inode: UInt64
    ) -> Bool {
        guard let current = FileIdentityObserver.observeDirectory(path: reported) else {
            return false
        }
        return current.canonicalPath == canonical
            && current.device == device
            && current.inode == inode
    }

    private static func isCleanAbsolutePath(_ path: String) -> Bool {
        HomebrewCaskTargetParser.cleanedAbsolutePath(path) != nil
    }

    private static func isCleanPathComponent(_ value: String) -> Bool {
        HomebrewCaskUpdateProbe.isCleanPathComponent(value)
    }

    private static func linkStatusMode(_ path: String) -> mode_t? {
        guard path.hasPrefix("/"), !path.utf8.contains(0) else { return nil }
        var info = stat()
        let status = path.withCString { pointer in lstat(pointer, &info) }
        return status == 0 ? info.st_mode : nil
    }

    // MARK: Exact-precision timestamp serialization

    private enum CodingKeys: String, CodingKey {
        case registryID
        case managerEntryPath
        case managerTarget
        case managerFingerprint
        case prefix
        case prefixCanonical
        case prefixDevice
        case prefixInode
        case caskroom
        case caskroomCanonical
        case caskroomDevice
        case caskroomInode
        case token
        case fullToken
        case tap
        case installedVersion
        case tokenDirectoryPath
        case tokenDirectoryDevice
        case tokenDirectoryInode
        case versionDirectoryPath
        case versionDirectoryDevice
        case versionDirectoryInode
        case selectedEntryPath
        case selectedTarget
        case selectedFingerprint
        case declarationsDigest
        case contextDigest
        case version
        case pinned
        case managerOutdated
        case observedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        registryID = try container.decode(String.self, forKey: .registryID)
        managerEntryPath = try container.decode(String.self, forKey: .managerEntryPath)
        managerTarget = try container.decode(String.self, forKey: .managerTarget)
        managerFingerprint = try container.decode(String.self, forKey: .managerFingerprint)
        prefix = try container.decode(String.self, forKey: .prefix)
        prefixCanonical = try container.decode(String.self, forKey: .prefixCanonical)
        prefixDevice = try container.decode(UInt64.self, forKey: .prefixDevice)
        prefixInode = try container.decode(UInt64.self, forKey: .prefixInode)
        caskroom = try container.decode(String.self, forKey: .caskroom)
        caskroomCanonical = try container.decode(String.self, forKey: .caskroomCanonical)
        caskroomDevice = try container.decode(UInt64.self, forKey: .caskroomDevice)
        caskroomInode = try container.decode(UInt64.self, forKey: .caskroomInode)
        token = try container.decode(String.self, forKey: .token)
        fullToken = try container.decode(String.self, forKey: .fullToken)
        tap = try container.decode(String.self, forKey: .tap)
        installedVersion = try container.decode(String.self, forKey: .installedVersion)
        tokenDirectoryPath = try container.decode(String.self, forKey: .tokenDirectoryPath)
        tokenDirectoryDevice = try container.decode(UInt64.self, forKey: .tokenDirectoryDevice)
        tokenDirectoryInode = try container.decode(UInt64.self, forKey: .tokenDirectoryInode)
        versionDirectoryPath = try container.decode(String.self, forKey: .versionDirectoryPath)
        versionDirectoryDevice = try container.decode(
            UInt64.self, forKey: .versionDirectoryDevice
        )
        versionDirectoryInode = try container.decode(
            UInt64.self, forKey: .versionDirectoryInode
        )
        selectedEntryPath = try container.decode(String.self, forKey: .selectedEntryPath)
        selectedTarget = try container.decode(String.self, forKey: .selectedTarget)
        selectedFingerprint = try container.decode(String.self, forKey: .selectedFingerprint)
        declarationsDigest = try container.decode(String.self, forKey: .declarationsDigest)
        contextDigest = try container.decode(String.self, forKey: .contextDigest)
        version = try container.decode(String.self, forKey: .version)
        pinned = try container.decode(Bool.self, forKey: .pinned)
        managerOutdated = try container.decode(Bool.self, forKey: .managerOutdated)
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
        try container.encode(prefix, forKey: .prefix)
        try container.encode(prefixCanonical, forKey: .prefixCanonical)
        try container.encode(prefixDevice, forKey: .prefixDevice)
        try container.encode(prefixInode, forKey: .prefixInode)
        try container.encode(caskroom, forKey: .caskroom)
        try container.encode(caskroomCanonical, forKey: .caskroomCanonical)
        try container.encode(caskroomDevice, forKey: .caskroomDevice)
        try container.encode(caskroomInode, forKey: .caskroomInode)
        try container.encode(token, forKey: .token)
        try container.encode(fullToken, forKey: .fullToken)
        try container.encode(tap, forKey: .tap)
        try container.encode(installedVersion, forKey: .installedVersion)
        try container.encode(tokenDirectoryPath, forKey: .tokenDirectoryPath)
        try container.encode(tokenDirectoryDevice, forKey: .tokenDirectoryDevice)
        try container.encode(tokenDirectoryInode, forKey: .tokenDirectoryInode)
        try container.encode(versionDirectoryPath, forKey: .versionDirectoryPath)
        try container.encode(versionDirectoryDevice, forKey: .versionDirectoryDevice)
        try container.encode(versionDirectoryInode, forKey: .versionDirectoryInode)
        try container.encode(selectedEntryPath, forKey: .selectedEntryPath)
        try container.encode(selectedTarget, forKey: .selectedTarget)
        try container.encode(selectedFingerprint, forKey: .selectedFingerprint)
        try container.encode(declarationsDigest, forKey: .declarationsDigest)
        try container.encode(contextDigest, forKey: .contextDigest)
        try container.encode(version, forKey: .version)
        try container.encode(pinned, forKey: .pinned)
        try container.encode(managerOutdated, forKey: .managerOutdated)
        try container.encode(observedAt.timeIntervalSince1970.description, forKey: .observedAt)
    }
}

/// Identity of one cached cask selection. Every field must match for a hit.
public struct CaskUpdateMetadataKey: Equatable, Sendable {
    public let registryID: String
    public let managerEntryPath: String
    public let managerTarget: String
    public let managerFingerprint: String
    public let prefix: String
    public let prefixCanonical: String
    public let prefixDevice: UInt64
    public let prefixInode: UInt64
    public let caskroom: String
    public let caskroomCanonical: String
    public let caskroomDevice: UInt64
    public let caskroomInode: UInt64
    public let token: String
    public let fullToken: String
    public let tap: String
    public let installedVersion: String
    public let tokenDirectoryPath: String
    public let tokenDirectoryDevice: UInt64
    public let tokenDirectoryInode: UInt64
    public let versionDirectoryPath: String
    public let versionDirectoryDevice: UInt64
    public let versionDirectoryInode: UInt64
    public let selectedEntryPath: String
    public let selectedTarget: String
    public let selectedFingerprint: String
    public let declarationsDigest: String
    public let contextDigest: String

    public init(
        registryID: String,
        managerEntryPath: String,
        managerTarget: String,
        managerFingerprint: String,
        prefix: String,
        prefixCanonical: String,
        prefixDevice: UInt64,
        prefixInode: UInt64,
        caskroom: String,
        caskroomCanonical: String,
        caskroomDevice: UInt64,
        caskroomInode: UInt64,
        token: String,
        fullToken: String,
        tap: String,
        installedVersion: String,
        tokenDirectoryPath: String,
        tokenDirectoryDevice: UInt64,
        tokenDirectoryInode: UInt64,
        versionDirectoryPath: String,
        versionDirectoryDevice: UInt64,
        versionDirectoryInode: UInt64,
        selectedEntryPath: String,
        selectedTarget: String,
        selectedFingerprint: String,
        declarationsDigest: String,
        contextDigest: String
    ) {
        self.registryID = registryID
        self.managerEntryPath = managerEntryPath
        self.managerTarget = managerTarget
        self.managerFingerprint = managerFingerprint
        self.prefix = prefix
        self.prefixCanonical = prefixCanonical
        self.prefixDevice = prefixDevice
        self.prefixInode = prefixInode
        self.caskroom = caskroom
        self.caskroomCanonical = caskroomCanonical
        self.caskroomDevice = caskroomDevice
        self.caskroomInode = caskroomInode
        self.token = token
        self.fullToken = fullToken
        self.tap = tap
        self.installedVersion = installedVersion
        self.tokenDirectoryPath = tokenDirectoryPath
        self.tokenDirectoryDevice = tokenDirectoryDevice
        self.tokenDirectoryInode = tokenDirectoryInode
        self.versionDirectoryPath = versionDirectoryPath
        self.versionDirectoryDevice = versionDirectoryDevice
        self.versionDirectoryInode = versionDirectoryInode
        self.selectedEntryPath = selectedEntryPath
        self.selectedTarget = selectedTarget
        self.selectedFingerprint = selectedFingerprint
        self.declarationsDigest = declarationsDigest
        self.contextDigest = contextDigest
    }

    func matches(_ requested: CaskUpdateMetadataKey) -> Bool {
        registryID == requested.registryID
            && managerEntryPath == requested.managerEntryPath
            && managerTarget == requested.managerTarget
            && managerFingerprint == requested.managerFingerprint
            && prefix == requested.prefix
            && prefixCanonical == requested.prefixCanonical
            && prefixDevice == requested.prefixDevice
            && prefixInode == requested.prefixInode
            && caskroom == requested.caskroom
            && caskroomCanonical == requested.caskroomCanonical
            && caskroomDevice == requested.caskroomDevice
            && caskroomInode == requested.caskroomInode
            && token == requested.token
            && fullToken == requested.fullToken
            && tap == requested.tap
            && installedVersion == requested.installedVersion
            && tokenDirectoryPath == requested.tokenDirectoryPath
            && tokenDirectoryDevice == requested.tokenDirectoryDevice
            && tokenDirectoryInode == requested.tokenDirectoryInode
            && versionDirectoryPath == requested.versionDirectoryPath
            && versionDirectoryDevice == requested.versionDirectoryDevice
            && versionDirectoryInode == requested.versionDirectoryInode
            && selectedEntryPath == requested.selectedEntryPath
            && selectedTarget == requested.selectedTarget
            && selectedFingerprint == requested.selectedFingerprint
            && declarationsDigest == requested.declarationsDigest
            && contextDigest == requested.contextDigest
    }

    /// Lowercase hex SHA-256. Stable across processes and platforms, unlike `Hasher`.
    public static func stableDigest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// The exact current declaration set for one registry subject, in declaration order, under a
    /// dedicated domain label. A declaration change therefore cannot hit an older record.
    public static func declarationsDigest(_ declarations: [String]) -> String {
        func frame(_ text: String) -> String { "\(text.utf8.count):\(text)" }
        let material = frame("agent-lens-cask-declarations-v1")
            + frame(String(declarations.count))
            + declarations.map(frame).joined()
        return stableDigest(material)
    }

    /// The observed selected executable identity as a stable digest. A same-path replacement
    /// changes the fingerprint and cannot hit an older record.
    static func selectedFingerprintDigest(_ fingerprint: ExecutableFingerprint) -> String {
        func frame(_ text: String) -> String { "\(text.utf8.count):\(text)" }
        let material = frame("agent-lens-cask-selected-fingerprint-v1")
            + frame(String(fingerprint.device))
            + frame(String(fingerprint.inode))
            + frame(String(fingerprint.mode))
            + frame(String(fingerprint.size))
            + frame("\(fingerprint.modifiedSeconds).\(fingerprint.modifiedNanoseconds)")
            + frame("\(fingerprint.changedSeconds).\(fingerprint.changedNanoseconds)")
        return stableDigest(material)
    }
}

/// The identity known before a cache hit: this registry selection under this manager and context,
/// with the observed selected executable identity and the current cask declaration set.
struct CaskUpdateMetadataSelection: Equatable, Sendable {
    let registryID: String
    let managerEntryPath: String
    let managerTarget: String
    let managerFingerprint: String
    let selectedEntryPath: String
    let selectedTarget: String
    let selectedFingerprint: String
    let declarationsDigest: String
    let contextDigest: String

    func matches(_ entry: CaskUpdateMetadataEntry) -> Bool {
        registryID == entry.registryID
            && managerEntryPath == entry.managerEntryPath
            && managerTarget == entry.managerTarget
            && managerFingerprint == entry.managerFingerprint
            && selectedEntryPath == entry.selectedEntryPath
            && selectedTarget == entry.selectedTarget
            && selectedFingerprint == entry.selectedFingerprint
            && declarationsDigest == entry.declarationsDigest
            && contextDigest == entry.contextDigest
    }
}

/// Versioned on-disk document. Unknown or other schema versions are misses, never migrated.
struct CaskUpdateMetadataDocument: Codable, Equatable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let entries: [CaskUpdateMetadataEntry]
}

/// One process-wide serialization token for the cask document, matching the npm document's
/// in-process read/merge/write discipline. No cross-process lock framework is added.
private final class CaskCacheDocumentLock: @unchecked Sendable {
    let lock = NSLock()
}

private let caskUpdateMetadataDocumentLock = CaskCacheDocumentLock()

private func withCaskCacheDocumentLock<T>(_ operation: () -> T) -> T {
    caskUpdateMetadataDocumentLock.lock.lock()
    defer { caskUpdateMetadataDocumentLock.lock.unlock() }
    return operation()
}

/// Bounded cask latest-metadata cache living beside the injected formula cache.
public struct CaskUpdateMetadataCache: Sendable {

    /// Exactly six hours; `0 <= age < ttl` is a hit.
    public static let ttl: TimeInterval = 21_600
    /// Maximum bytes read or written for the document.
    public static let maximumDocumentBytes = 1_048_576

    public let fileURL: URL
    public let now: @Sendable () -> Date

    /// The cask document is a sibling of the injected formula metadata document.
    public init(updateCacheURL: URL, now: @escaping @Sendable () -> Date) {
        self.fileURL = updateCacheURL.deletingLastPathComponent()
            .appendingPathComponent("cask-update-metadata-v1.json")
        self.now = now
    }

    /// The stored entry for the complete identity key when present, coherent, live and inside TTL.
    public func lookup(_ key: CaskUpdateMetadataKey) -> CaskUpdateMetadataEntry? {
        withCaskCacheDocumentLock { lookupUnlocked { $0.key.matches(key) } }
    }

    /// Restores the one complete identity for this exact manager/selection/context. Ambiguity is a
    /// miss, never first-wins. A record whose live root, token, version or selected executable no
    /// longer matches is also a miss: it must be freshly verified.
    func lookup(_ selection: CaskUpdateMetadataSelection) -> CaskUpdateMetadataEntry? {
        withCaskCacheDocumentLock { lookupUnlocked { selection.matches($0) } }
    }

    private func lookupUnlocked(
        matching predicate: (CaskUpdateMetadataEntry) -> Bool
    ) -> CaskUpdateMetadataEntry? {
        guard let document = readDocument() else { return nil }
        let current = now()
        var matches: [CaskUpdateMetadataEntry] = []
        for entry in document.entries where predicate(entry) {
            // A key match is not proof of valid metadata. If ANY record for this selection is
            // incoherent or no longer live, the identity is unusable: fail closed instead of
            // promoting a sibling.
            guard entry.isStructurallyCoherent, entry.stagedBindingsAreCurrent else {
                return nil
            }
            let age = current.timeIntervalSince(entry.observedAt)
            guard age >= 0 && age < Self.ttl else { continue }
            matches.append(entry)
        }
        guard matches.count == 1 else { return nil }
        return matches.first
    }

    /// Refuses any incoherent entry, then reads, prunes, merges and writes the union atomically as
    /// one in-process critical section. An unrelated save never drops a valid sibling record.
    /// An incoming set that cannot fit leaves the existing document byte-identical.
    @discardableResult
    public func save(_ entries: [CaskUpdateMetadataEntry]) -> Bool {
        guard !entries.isEmpty, entries.allSatisfy(\.isStructurallyCoherent) else { return false }
        return withCaskCacheDocumentLock { saveMerged(entries) }
    }

    private func saveMerged(_ entries: [CaskUpdateMetadataEntry]) -> Bool {
        let current = now()
        func withinTTL(_ observedAt: Date) -> Bool {
            let age = current.timeIntervalSince(observedAt)
            return age >= 0 && age < Self.ttl
        }
        let incomingDigests = Set(entries.map { caskMetadataKeyDigest($0.key) })

        // A missing/corrupt/oversize/schema-mismatched cask document is treated as empty.
        let existing = readDocument()?.entries ?? []

        var groups: [String: [CaskUpdateMetadataEntry]] = [:]
        var order: [String] = []
        for entry in existing {
            let digest = caskMetadataKeyDigest(entry.key)
            if groups[digest] == nil { order.append(digest) }
            groups[digest, default: []].append(entry)
        }

        var keptExisting: [CaskUpdateMetadataEntry] = []
        for digest in order {
            let group = groups[digest] ?? []
            // Replacing identity: every stored copy gives way to the incoming record.
            if incomingDigests.contains(digest) { continue }
            // One incoherent record makes the entire identity unusable.
            if !group.allSatisfy(\.isStructurallyCoherent) { continue }
            // Valid identities keep live records verbatim, including preserved ambiguity.
            keptExisting.append(contentsOf: group.filter { withinTTL($0.observedAt) })
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        func encodedSize(_ items: [CaskUpdateMetadataEntry]) -> Int? {
            let document = CaskUpdateMetadataDocument(
                schemaVersion: CaskUpdateMetadataDocument.currentSchemaVersion,
                entries: items
            )
            return try? encoder.encode(document).count
        }

        // The COMPLETE merged document must fit. An oversized save is refused as an unmodified
        // document: not even a prior record with the same key is dropped or replaced.
        let items = keptExisting + entries
        guard let size = encodedSize(items), size <= Self.maximumDocumentBytes else {
            return false
        }

        let document = CaskUpdateMetadataDocument(
            schemaVersion: CaskUpdateMetadataDocument.currentSchemaVersion,
            entries: items
        )
        guard let data = try? encoder.encode(document),
              data.count <= Self.maximumDocumentBytes
        else { return false }
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

    private func readDocument() -> CaskUpdateMetadataDocument? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: Self.maximumDocumentBytes + 1),
              data.count <= Self.maximumDocumentBytes
        else {
            return nil
        }
        guard let document = try? JSONDecoder().decode(CaskUpdateMetadataDocument.self, from: data),
              document.schemaVersion == CaskUpdateMetadataDocument.currentSchemaVersion
        else {
            return nil
        }
        return document
    }
}

/// A stable, length-framed digest of every identity field, so `save` can match records without
/// requiring the key to be `Hashable`.
private func caskMetadataKeyDigest(_ key: CaskUpdateMetadataKey) -> String {
    func frame(_ text: String) -> String { "\(text.utf8.count):\(text)" }
    let material = frame("agent-lens-cask-cache-key-v1")
        + frame(key.registryID) + frame(key.managerEntryPath) + frame(key.managerTarget)
        + frame(key.managerFingerprint) + frame(key.prefix)
        + frame(key.prefixCanonical) + frame(String(key.prefixDevice))
        + frame(String(key.prefixInode)) + frame(key.caskroom)
        + frame(key.caskroomCanonical) + frame(String(key.caskroomDevice))
        + frame(String(key.caskroomInode)) + frame(key.token)
        + frame(key.fullToken) + frame(key.tap) + frame(key.installedVersion)
        + frame(key.tokenDirectoryPath) + frame(String(key.tokenDirectoryDevice))
        + frame(String(key.tokenDirectoryInode)) + frame(key.versionDirectoryPath)
        + frame(String(key.versionDirectoryDevice))
        + frame(String(key.versionDirectoryInode)) + frame(key.selectedEntryPath)
        + frame(key.selectedTarget) + frame(key.selectedFingerprint)
        + frame(key.declarationsDigest) + frame(key.contextDigest)
    return CaskUpdateMetadataKey.stableDigest(material)
}
