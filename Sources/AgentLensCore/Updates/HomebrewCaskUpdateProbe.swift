// HomebrewCaskUpdateProbe — M13-B read-only cask latest-check adapter (R2).
//
// At most five manager commands per uncached batch, in this exact order and only while the caller
// owns the existing Homebrew batch admission:
//   1. <brew> --prefix
//   2. <brew> --caskroom
//   3. <brew> info --json=v2 --cask <declared names>              (whole-subject cap 16)
//   4. <brew> outdated --json=v2 --cask                           (no --greedy)
//   5. <brew> list --verbose --cask <installed identities>
//
// The manager's own verdict is the oracle. Cask version strings (including comma multi-part
// strings and `latest`) are opaque text and are never ordered to decide an update: the shared
// Homebrew-stable comparator is deliberately NOT used here. Parsing fails closed at the envelope
// and isolates bad records; an invalid record keeps its identity claims so it poisons its own
// association instead of disappearing into apparent absence.
//
// The reported prefix and Caskroom are bound to live directory identity (reported spelling plus
// canonical path). A missing prefix is never a comparison. Listing lines are normalized only for
// the accepted reported/canonical root alias, by path components, leaving final links intact.
// The observed manager, every observed selection and every derived token/version directory binding
// are revalidated before AND after each manager call; a replacement or retarget stops the batch
// before another launch.

import Darwin
import Foundation

/// One `info --json=v2 --cask` record. `isValid == false` markers keep only the raw identity
/// claims; every other field is a placeholder that is never compared or lent to another cask.
struct HomebrewCaskInfoRecord: Equatable, Sendable {
    enum InstalledValue: Equatable, Sendable {
        case missing
        case null
        case string(String)
        case malformed
    }

    let token: String
    let fullToken: String
    let tap: String
    let version: String
    let installed: InstalledValue
    /// nil means `auto_updates` was null or absent: Homebrew's own falsy semantics, which the live
    /// API confirmed by reporting the source declaration even for an uninstalled cask.
    let autoUpdates: Bool?
    let pinned: Bool
    let outdated: Bool
    let disabled: Bool
    let oldTokens: [String]
    let isValid: Bool

    init(
        token: String,
        fullToken: String = "",
        tap: String = "",
        version: String = "",
        installed: InstalledValue = .missing,
        autoUpdates: Bool? = nil,
        pinned: Bool = false,
        outdated: Bool = false,
        disabled: Bool = false,
        oldTokens: [String] = [],
        isValid: Bool = true
    ) {
        self.token = token
        self.fullToken = fullToken
        self.tap = tap
        self.version = version
        self.installed = installed
        self.autoUpdates = autoUpdates
        self.pinned = pinned
        self.outdated = outdated
        self.disabled = disabled
        self.oldTokens = oldTokens
        self.isValid = isValid
    }
}

/// One `outdated --json=v2 --cask` record. Homebrew keys cask outdated records on the BARE TOKEN
/// (`name`), never on `full_token`.
struct HomebrewCaskOutdatedRecord: Equatable, Sendable {
    let name: String
    let currentVersion: String
    let installedVersions: [String]
    let pinned: Bool
    let isValid: Bool

    init(
        name: String,
        currentVersion: String = "",
        installedVersions: [String] = [],
        pinned: Bool = false,
        isValid: Bool = true
    ) {
        self.name = name
        self.currentVersion = currentVersion
        self.installedVersions = installedVersions
        self.pinned = pinned
        self.isValid = isValid
    }
}

/// A manager-reported root (prefix or Caskroom) bound to the exact directory identity observed
/// through that reported spelling. Later checks re-observe through `reportedPath`, never through
/// a stored canonical spelling alone.
struct HomebrewCaskBoundRoot: Equatable, Sendable {
    let reportedPath: String
    let identity: DirectoryIdentity

    var canonicalPath: String { identity.canonicalPath }

    static func observe(_ reportedPath: String) -> HomebrewCaskBoundRoot? {
        guard let identity = FileIdentityObserver.observeDirectory(path: reportedPath) else {
            return nil
        }
        return HomebrewCaskBoundRoot(reportedPath: reportedPath, identity: identity)
    }

    var isCurrent: Bool {
        FileIdentityObserver.observeDirectory(path: reportedPath) == identity
    }
}

/// One directory bound to an exact final component below its parent. `path` is the lexical lookup
/// path; `identity.canonicalPath` must be exactly `parent.canonicalPath/<component>`.
struct HomebrewCaskBoundDirectory: Equatable, Sendable {
    let path: String
    let component: String
    let identity: DirectoryIdentity

    func isCurrent(parent: DirectoryIdentity) -> Bool {
        guard let current = FileIdentityObserver.observeDirectory(path: path),
              current == identity,
              FileIdentityObserver.isExactDescendant(
                current.canonicalPath, of: parent.canonicalPath, components: [component]
              )
        else { return false }
        return true
    }
}

/// The exact `<caskroom>/<token>/<version>` directory pair for one installed cask. Both components
/// are bound to the Caskroom identity, so a symlinked sibling tree can never borrow this proof.
struct HomebrewCaskStagedBinding: Equatable, Sendable {
    let caskroom: HomebrewCaskBoundRoot
    let token: String
    let version: String
    let tokenDirectory: HomebrewCaskBoundDirectory
    let versionDirectory: HomebrewCaskBoundDirectory

    var isCurrent: Bool {
        guard caskroom.isCurrent,
              tokenDirectory.isCurrent(parent: caskroom.identity),
              versionDirectory.isCurrent(parent: tokenDirectory.identity)
        else { return false }
        return true
    }

    static func observe(
        caskroom: HomebrewCaskBoundRoot,
        token: String,
        version: String
    ) -> HomebrewCaskStagedBinding? {
        guard HomebrewCaskUpdateProbe.isCleanPathComponent(token),
              HomebrewCaskUpdateProbe.isCleanPathComponent(version),
              version != ".metadata"
        else { return nil }
        let tokenPath = HomebrewCaskUpdateProbe.appendedPath(
            caskroom.canonicalPath, token
        )
        guard let tokenDirectory = HomebrewCaskUpdateProbe.boundDirectory(
            path: tokenPath, component: token, parent: caskroom.identity
        ) else { return nil }
        let versionPath = HomebrewCaskUpdateProbe.appendedPath(
            tokenDirectory.identity.canonicalPath, version
        )
        guard let versionDirectory = HomebrewCaskUpdateProbe.boundDirectory(
            path: versionPath, component: version, parent: tokenDirectory.identity
        ) else { return nil }
        return HomebrewCaskStagedBinding(
            caskroom: caskroom,
            token: token,
            version: version,
            tokenDirectory: tokenDirectory,
            versionDirectory: versionDirectory
        )
    }
}

struct HomebrewCaskBatchResult: Equatable, Sendable {
    let prefix: HomebrewCaskBoundRoot
    let caskroom: HomebrewCaskBoundRoot
    let records: [String: [HomebrewCaskInfoRecord]]
    let outdated: [String: [HomebrewCaskOutdatedRecord]]
    let listing: [String]
    /// Bare manager tokens whose `installed` value is a string.
    let installedTokens: [String]
    /// The names used for the combined listing query: bare tokens for core casks, the verified
    /// full identity for tapped casks.
    let listingNames: [String]
    /// Exact token/version directory bindings captured before the listing query.
    let stagedBindings: [HomebrewCaskStagedBinding]
    let queryCount: Int
}

enum HomebrewCaskBatchError: Error, Equatable, Sendable {
    case invalidToken
    case invalidOutput
    /// A manager, selection, reported root or token/version directory changed (or was never a
    /// live bound directory) before the next observation.
    case identityUnverified
    case commandFailed(CommandFailure)
}

/// The verified comparison for one selected cask. `managerOutdated` is the manager's own verdict
/// captured at observation; it is metadata, not a precomputed status. `installedVersion` is the
/// manager's installed version directory, which may legitimately differ from the CLI's local
/// version text; the verdict uses only manager values.
struct HomebrewCaskComparison: Equatable, Sendable {
    let token: String
    let fullToken: String
    let tap: String
    let installedVersion: String
    let version: String
    let pinned: Bool
    let managerOutdated: Bool
    let status: VersionStatus
}

enum HomebrewCaskEvaluation: Equatable, Sendable {
    case verified(HomebrewCaskComparison)
    case unknown(UnknownReason)
}

enum HomebrewCaskUpdateProbe {

    /// The bounded manager-wide listing contract, matching the M13-A cask proof.
    static let maximumListingLines = 4096
    static let maximumListingBytes = 1024 * 1024

    // MARK: Batch

    /// Executes the five-command protocol while the caller owns admission. Zero tokens execute
    /// zero commands. The manager and every pending selection are snapshotted identities; each
    /// query revalidates all of them (and every root/directory binding known at that point) before
    /// it launches and again after it returns.
    static func runBatchWhileAdmitted(
        manager: ObservedExecutable,
        selections: [ObservedExecutable],
        tokens: [String],
        environment: ShellEnvironment,
        runner: UpdateCommandRunner
    ) async -> Result<HomebrewCaskBatchResult, HomebrewCaskBatchError> {
        var unique: [String] = []
        for token in tokens where !unique.contains(token) {
            // A declaration may be a bare cask token or a fully qualified `owner/tap/token`.
            guard isValidDeclaredCaskName(token) else { return .failure(.invalidToken) }
            unique.append(token)
        }
        guard !unique.isEmpty else {
            return .failure(.invalidToken)
        }

        let processEnvironment = HomebrewUpdateProbe.diagnosticEnvironment(from: environment)
        var queryCount = 0
        var prefix: HomebrewCaskBoundRoot?
        var caskroom: HomebrewCaskBoundRoot?
        var stagedBindings: [HomebrewCaskStagedBinding] = []

        func stageIsCurrent() -> Bool {
            guard let currentManager = FileIdentityObserver.observeExecutable(
                entryPath: manager.entryPath
            ), currentManager == manager else { return false }
            for selection in selections {
                guard let current = FileIdentityObserver.observeExecutable(
                    entryPath: selection.entryPath
                ), current == selection else { return false }
            }
            if let prefix, !prefix.isCurrent { return false }
            if let caskroom, !caskroom.isCurrent { return false }
            for binding in stagedBindings where !binding.isCurrent { return false }
            return true
        }

        func query(_ arguments: [String]) async -> Result<Data, HomebrewCaskBatchError> {
            guard stageIsCurrent() else { return .failure(.identityUnverified) }
            if Task.isCancelled { return .failure(.commandFailed(.cancelled)) }
            queryCount += 1
            let outcome = await runner.run(
                executablePath: manager.entryPath,
                arguments: arguments,
                environment: processEnvironment,
                timeout: HomebrewUpdateProbe.queryTimeout
            )
            if Task.isCancelled { return .failure(.commandFailed(.cancelled)) }
            guard stageIsCurrent() else { return .failure(.identityUnverified) }
            switch outcome {
            case .success(let data): return .success(data)
            case .failure(let failure): return .failure(.commandFailed(failure))
            }
        }

        func addBinding(_ binding: HomebrewCaskStagedBinding) {
            if !stagedBindings.contains(binding) { stagedBindings.append(binding) }
        }

        // 1. The manager's prefix. Reported and bound, never used to derive the Caskroom.
        switch await query(["--prefix"]) {
        case .failure(let error): return .failure(error)
        case .success(let data):
            guard let parsed = ManagerOutputParser.singleAbsolutePath(data),
                  HomebrewCaskTargetParser.cleanedAbsolutePath(parsed) != nil,
                  let bound = HomebrewCaskBoundRoot.observe(parsed)
            else { return .failure(.identityUnverified) }
            prefix = bound
        }
        guard stageIsCurrent() else { return .failure(.identityUnverified) }

        // 2. The manager's Caskroom, which may differ from the prefix.
        let caskroomRoot: HomebrewCaskBoundRoot
        switch await query(["--caskroom"]) {
        case .failure(let error): return .failure(error)
        case .success(let data):
            guard let parsed = ManagerOutputParser.singleAbsolutePath(data),
                  HomebrewCaskTargetParser.cleanedAbsolutePath(parsed) != nil,
                  let bound = HomebrewCaskBoundRoot.observe(parsed)
            else { return .failure(.identityUnverified) }
            caskroom = bound
            caskroomRoot = bound
        }
        guard stageIsCurrent() else { return .failure(.identityUnverified) }

        // 3. Token/version directories are derivable for every staged selection NOW, before the
        // metadata and listing queries. A target outside the Caskroom is the moved-app route and
        // gets its exact directories after `info` names the record.
        for selection in selections {
            switch HomebrewCaskTargetParser.parse(
                selectedTarget: selection.canonicalTarget,
                caskroom: caskroomRoot.canonicalPath
            ) {
            case .success(let decomposed):
                guard let binding = HomebrewCaskStagedBinding.observe(
                    caskroom: caskroomRoot,
                    token: decomposed.token,
                    version: decomposed.versionDirectory
                ) else { return .failure(.identityUnverified) }
                addBinding(binding)
            case .failure(.managerMismatch):
                continue
            case .failure(.unverified):
                return .failure(.identityUnverified)
            }
        }
        guard stageIsCurrent() else { return .failure(.identityUnverified) }

        // 4. One metadata query for every selected token.
        let infoData: Data
        switch await query(["info", "--json=v2", "--cask"] + unique) {
        case .failure(let error): return .failure(error)
        case .success(let data): infoData = data
        }
        guard let infoRecords = parseInfo(infoData) else { return .failure(.invalidOutput) }
        guard stageIsCurrent() else { return .failure(.identityUnverified) }

        // 5. One combined membership listing only for bare tokens the manager reports as
        // installed. Basic core casks keep their bare argv; a tapped cask is addressed by the
        // verified full identity so a bare name cannot retarget the listing.
        var installedTokens: [String] = []
        var listingNames: [String] = []
        for declaration in unique {
            for record in infoRecords where record.isValid && isInstalledString(record) {
                guard declarationMatches(declaration, record) else { continue }
                if !installedTokens.contains(record.token) {
                    installedTokens.append(record.token)
                }
                let listingName = record.fullToken == record.token
                    ? record.token
                    : record.fullToken
                if !listingNames.contains(listingName) {
                    listingNames.append(listingName)
                }
                // The record now names the installed version directory. Bind it before the
                // listing query (moved-app route included).
                guard case .string(let installedVersion) = record.installed else { continue }
                if let binding = HomebrewCaskStagedBinding.observe(
                    caskroom: caskroomRoot,
                    token: record.token,
                    version: installedVersion
                ) {
                    addBinding(binding)
                }
            }
        }
        guard stageIsCurrent() else { return .failure(.identityUnverified) }

        // 6. One manager-wide outdated query with no `--greedy` (no hidden widening).
        let outdatedData: Data
        switch await query(["outdated", "--json=v2", "--cask"]) {
        case .failure(let error): return .failure(error)
        case .success(let data): outdatedData = data
        }
        guard let outdatedRecords = parseOutdated(outdatedData) else {
            return .failure(.invalidOutput)
        }
        guard stageIsCurrent() else { return .failure(.identityUnverified) }

        var listing: [String] = []
        if !installedTokens.isEmpty {
            guard listingNames.count == installedTokens.count else {
                return .failure(.identityUnverified)
            }
            let listData: Data
            switch await query(["list", "--verbose", "--cask"] + listingNames) {
            case .failure(let error): return .failure(error)
            case .success(let data): listData = data
            }
            guard let parsed = parseListing(
                listData,
                reportedCaskroom: caskroomRoot.reportedPath,
                caskroomIdentity: caskroomRoot.identity
            ) else {
                // A combined-list failure is reported for every cask subject by the coordinator.
                return .failure(.invalidOutput)
            }
            listing = parsed
        }

        guard let prefix, let caskroom, stageIsCurrent() else {
            return .failure(.identityUnverified)
        }
        return .success(HomebrewCaskBatchResult(
            prefix: prefix,
            caskroom: caskroom,
            records: Dictionary(grouping: infoRecords, by: \.token),
            outdated: Dictionary(grouping: outdatedRecords, by: \.name),
            listing: listing,
            installedTokens: installedTokens,
            listingNames: listingNames,
            stagedBindings: stagedBindings,
            queryCount: queryCount
        ))
    }

    /// Revalidates the manager, every batch selection and every captured root/directory binding.
    /// Used immediately before a verified fresh result is published and before metadata is saved.
    static func batchIsLive(
        manager: ObservedExecutable,
        selections: [ObservedExecutable],
        batch: HomebrewCaskBatchResult
    ) -> Bool {
        guard FileIdentityObserver.observeExecutable(entryPath: manager.entryPath) == manager else {
            return false
        }
        for selection in selections {
            guard FileIdentityObserver.observeExecutable(
                entryPath: selection.entryPath
            ) == selection else { return false }
        }
        guard batch.prefix.isCurrent, batch.caskroom.isCurrent else { return false }
        for binding in batch.stagedBindings where !binding.isCurrent { return false }
        return true
    }

    /// The exact token/version directory pair must be the one captured during the batch. A record
    /// whose directories were never bound is never verified.
    static func proofDirectoriesAreLive(
        batch: HomebrewCaskBatchResult,
        token: String,
        installedVersion: String
    ) -> Bool {
        guard batch.caskroom.isCurrent else { return false }
        guard let binding = batch.stagedBindings.first(where: {
            $0.token == token && $0.version == installedVersion
        }) else { return false }
        return binding.isCurrent
    }

    // MARK: JSON (typed; extra fields tolerated)

    /// Parses `info --json=v2 --cask`. The envelope must be an object whose `casks` value is an
    /// array of objects. A record carrying a usable token but failing validation is kept as an
    /// invalid marker so it poisons exactly its own association. A record with no token, or a
    /// non-object element, cannot be attributed and fails the whole batch.
    static func parseInfo(_ data: Data) -> [HomebrewCaskInfoRecord]? {
        guard let casks = jsonCaskRecords(data) else { return nil }
        var parsed: [HomebrewCaskInfoRecord] = []
        parsed.reserveCapacity(casks.count)
        for object in casks {
            // Every object must carry a usable identity claim; an unattributable element fails the
            // whole batch rather than being assigned to a neighbour.
            guard let token = object["token"] as? String,
                  !token.isEmpty, !token.utf8.contains(0)
            else { return nil }
            let fullToken = object["full_token"] as? String ?? ""
            let tap = object["tap"] as? String ?? ""
            let version = object["version"] as? String ?? ""
            let rawOldTokens = parseOldTokens(object["old_tokens"])
            let oldTokens = rawOldTokens ?? []
            let autoUpdates = parseOptionalBool(object, key: "auto_updates")
            let pinned = strictBool(object["pinned"])
            let outdated = strictBool(object["outdated"])
            let disabled = strictBool(object["disabled"])
            let installed = parseInstalled(object)
            let valid = isValidBareCaskToken(token)
                && isStructurallyValidCask(token: token, fullToken: fullToken, tap: tap)
                && isSafeVersionText(version)
                && isStructurallyValidInstalled(installed.value)
                && autoUpdates.isValid
                && pinned != nil && outdated != nil && disabled != nil
                && rawOldTokens != nil
            parsed.append(HomebrewCaskInfoRecord(
                token: token,
                fullToken: fullToken,
                tap: tap,
                version: version,
                installed: installed.value,
                autoUpdates: autoUpdates.value,
                pinned: pinned ?? false,
                outdated: outdated ?? false,
                disabled: disabled ?? false,
                oldTokens: oldTokens,
                isValid: valid
            ))
        }
        return parsed
    }

    /// Parses `outdated --json=v2 --cask`. Same envelope and isolation rules. `name` is the bare
    /// token; a missing name cannot be attributed and fails the whole batch.
    static func parseOutdated(_ data: Data) -> [HomebrewCaskOutdatedRecord]? {
        guard let casks = jsonCaskRecords(data) else { return nil }
        var parsed: [HomebrewCaskOutdatedRecord] = []
        parsed.reserveCapacity(casks.count)
        for object in casks {
            // The bare token is the only attributing claim. A malformed token is retained as an
            // invalid marker for exactly that key; a non-string/empty name fails the batch.
            guard let name = object["name"] as? String,
                  !name.isEmpty, !name.utf8.contains(0)
            else { return nil }
            let current = object["current_version"] as? String
            let installed = stringList(object["installed_versions"])
            let pinned = strictBool(object["pinned"])
            let valid = isValidBareCaskToken(name)
                && current != nil && isSafeVersionText(current ?? "")
                && installed != nil && pinned != nil
            parsed.append(HomebrewCaskOutdatedRecord(
                name: name,
                currentVersion: current ?? "",
                installedVersions: installed ?? [],
                pinned: pinned ?? false,
                isValid: valid
            ))
        }
        return parsed
    }

    private static func jsonCaskRecords(_ data: Data) -> [[String: Any]]? {
        guard let text = strictUTF8Text(data) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: Data(text.utf8), options: []),
              let root = json as? [String: Any],
              let casks = root["casks"] as? [Any]
        else { return nil }
        var records: [[String: Any]] = []
        records.reserveCapacity(casks.count)
        for element in casks {
            guard let record = element as? [String: Any] else { return nil }
            records.append(record)
        }
        return records
    }

    /// Strict boolean extraction. `JSONSerialization` bridges numeric values through `NSNumber`,
    /// so `as? Bool` alone would accept `1`, `0`, or `0.5` as flags.
    private static func strictBool(_ value: Any?) -> Bool? {
        guard let value else { return nil }
        guard CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID() else { return nil }
        return (value as! NSNumber).boolValue
    }

    private static func parseOptionalBool(
        _ object: [String: Any],
        key: String
    ) -> (value: Bool?, isValid: Bool) {
        guard object.keys.contains(key), !(object[key] is NSNull) else {
            return (nil, true)
        }
        guard let value = strictBool(object[key]) else { return (nil, false) }
        return (value, true)
    }

    private static func parseInstalled(
        _ object: [String: Any]
    ) -> (value: HomebrewCaskInfoRecord.InstalledValue, isValid: Bool) {
        guard object.keys.contains("installed") else { return (.missing, false) }
        if object["installed"] is NSNull { return (.null, true) }
        guard let value = object["installed"] as? String else { return (.malformed, false) }
        guard isCleanPathComponent(value), value != ".metadata" else { return (.malformed, false) }
        return (.string(value), true)
    }

    private static func isInstalledString(_ record: HomebrewCaskInfoRecord) -> Bool {
        if case .string = record.installed { return true }
        return false
    }

    private static func isStructurallyValidInstalled(
        _ installed: HomebrewCaskInfoRecord.InstalledValue
    ) -> Bool {
        switch installed {
        case .null, .string: true
        case .missing, .malformed: false
        }
    }

    private static func parseOldTokens(_ value: Any?) -> [String]? {
        guard let value else { return [] }
        if value is NSNull { return [] }
        return stringList(value)
    }

    private static func stringList(_ value: Any?) -> [String]? {
        guard let entries = value as? [Any] else { return nil }
        var strings: [String] = []
        strings.reserveCapacity(entries.count)
        for entry in entries {
            guard let string = entry as? String, !string.isEmpty else { return nil }
            strings.append(string)
        }
        return strings
    }

    // MARK: Listing

    /// Validates the bounded combined listing in one pass. Every physical line must be an absolute
    /// path strictly below the reported Caskroom spelling OR the exact canonical spelling; only
    /// that accepted root alias is normalized, by path components, to the canonical root. Final
    /// components (a staged app link) are left intact. A malformed line invalidates the whole
    /// listing. `.metadata` lines are manager bookkeeping and are never membership proof.
    static func parseListing(
        _ data: Data,
        reportedCaskroom: String,
        caskroomIdentity: DirectoryIdentity
    ) -> [String]? {
        guard !data.isEmpty,
              data.count <= maximumListingBytes,
              strictUTF8Text(data) != nil
        else { return nil }

        let canonicalRoot = caskroomIdentity.canonicalPath
        guard let reportedRoot = HomebrewCaskTargetParser.cleanedAbsolutePath(
            reportedCaskroom
        ), let canonicalCleaned = HomebrewCaskTargetParser.cleanedAbsolutePath(
            canonicalRoot
        ) else { return nil }
        let reportedComponents = HomebrewCaskTargetParser.components(of: reportedRoot)
        let canonicalComponents = HomebrewCaskTargetParser.components(of: canonicalCleaned)
        guard !reportedComponents.isEmpty, !canonicalComponents.isEmpty else { return nil }
        // Only the exact reported spelling and the exact canonical spelling are accepted. Any
        // other alias or sibling is malformed manager output, not proof.
        let roots: [(listed: [String], canonical: [String])] =
            reportedComponents == canonicalComponents
            ? [(reportedComponents, canonicalComponents)]
            : [(reportedComponents, canonicalComponents),
               (canonicalComponents, canonicalComponents)]

        var bytes = Array(data)
        if bytes.last == 0x0A { bytes.removeLast() }
        let rawLines = bytes.split(separator: 0x0A, omittingEmptySubsequences: false)
        guard rawLines.count <= maximumListingLines else { return nil }

        var paths: [String] = []
        paths.reserveCapacity(rawLines.count)
        for rawLine in rawLines {
            var line = rawLine
            if line.last == 0x0D { line = line.dropLast() }
            guard !line.isEmpty,
                  let text = String(bytes: line, encoding: .utf8),
                  let cleaned = HomebrewCaskTargetParser.cleanedAbsolutePath(text)
            else { return nil }
            let lineComponents = HomebrewCaskTargetParser.components(of: cleaned)
            var mapped: String?
            for root in roots {
                guard lineComponents.count > root.listed.count,
                      Array(lineComponents.prefix(root.listed.count)) == root.listed
                else { continue }
                let suffix = lineComponents.dropFirst(root.listed.count)
                mapped = "/" + (root.canonical + suffix).joined(separator: "/")
                break
            }
            guard let mapped else { return nil }
            paths.append(mapped)
        }
        return paths
    }

    // MARK: Identity grammar

    /// A declared cask name: a bare token or a fully qualified `owner/tap/token`, using the same
    /// validated registry grammar M13-A accepts.
    static func isValidDeclaredCaskName(_ name: String) -> Bool {
        DeclaredPackage.validationFailure(manager: .homebrewCask, name: name) == nil
    }

    /// A bare cask token: one path component, no traversal, no `.metadata`, and the registry's
    /// declared-package alphabet.
    static func isValidBareCaskToken(_ token: String) -> Bool {
        isCleanPathComponent(token)
            && isValidDeclaredCaskName(token)
    }

    /// `full_token` is the bare token for a core cask, or `owner/tap/token`. `tap` is two
    /// components. The two must agree: a third-party full token is exactly `<tap>/<token>`.
    static func isStructurallyValidCask(token: String, fullToken: String, tap: String) -> Bool {
        guard isValidBareCaskToken(token), isValidTap(tap) else { return false }
        guard DeclaredPackage.validationFailure(
            manager: .homebrewCask, name: fullToken
        ) == nil else { return false }
        let components = fullToken.split(separator: "/", omittingEmptySubsequences: false)
        guard let last = components.last, String(last) == token else { return false }
        // A bare full token is a core cask; a third-party cask's full token carries its tap.
        // Anything else leaves the identity fields disagreeing, so it is never compared.
        if fullToken == token { return tap == "homebrew/cask" }
        guard components.count == 3 else { return false }
        return fullToken == tap + "/" + token
    }

    static func isValidTap(_ tap: String) -> Bool {
        let components = tap.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 2 else { return false }
        let pattern = #"^[A-Za-z0-9][A-Za-z0-9._+@-]*$"#
        return components.allSatisfy {
            String($0).range(of: pattern, options: .regularExpression) != nil
        }
    }

    /// Opaque manager version text. The string is never parsed or ordered here; `latest` is
    /// accepted so the resolver can report its typed unknown.
    static func isSafeVersionText(_ text: String) -> Bool {
        !text.isEmpty
            && text != "."
            && text != ".."
            && text != ".metadata"
            && !text.contains("/")
            && !text.utf8.contains(0)
    }

    /// The M13-A declaration rule: a bare declaration may match either the canonical full token or
    /// a token that is itself the full token; a tap declaration must equal `full_token` exactly.
    /// `old_tokens` never satisfies this rule.
    static func declarationMatches(
        _ declared: String,
        _ record: HomebrewCaskInfoRecord
    ) -> Bool {
        if declared == record.fullToken { return true }
        return declared == record.token && record.fullToken == record.token
    }

    static func isCleanPathComponent(_ value: String) -> Bool {
        !value.isEmpty
            && value != "."
            && value != ".."
            && value != ".metadata"
            && !value.contains("/")
            && !value.utf8.contains(0)
    }

    static func appendedPath(_ base: String, _ component: String) -> String {
        URL(fileURLWithPath: base, isDirectory: true)
            .appendingPathComponent(component, isDirectory: true)
            .path
    }

    static func boundDirectory(
        path: String,
        component: String,
        parent: DirectoryIdentity
    ) -> HomebrewCaskBoundDirectory? {
        guard let identity = FileIdentityObserver.observeDirectory(path: path),
              FileIdentityObserver.isExactDescendant(
                identity.canonicalPath, of: parent.canonicalPath, components: [component]
              )
        else { return nil }
        return HomebrewCaskBoundDirectory(
            path: path, component: component, identity: identity
        )
    }

    /// Homebrew emits UTF-8. Reject a leading BOM, NUL bytes, and any non-UTF-8 sequence.
    private static func strictUTF8Text(_ data: Data) -> String? {
        let byteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]
        if data.count >= 3, Array(data.prefix(3)) == byteOrderMark { return nil }
        if data.contains(0x00) { return nil }
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        guard Data(text.utf8) == data else { return nil }
        return text
    }
}

/// Resolves one selected cask to the tri-state from the manager's own records. No cask version
/// comparator is invented or borrowed: outdated presence/absence is the manager's verdict, and
/// installed/latest strings (including comma forms and `latest`) remain opaque. The verdict uses
/// only Homebrew-verified membership and manager values; the CLI's local version text is retained
/// only as the displayed installed value and the selected-update count identity.
enum HomebrewCaskStatusResolver {

    static func evaluate(
        declaredNames: [String],
        selectedTarget: String,
        localVersion: String,
        batch: HomebrewCaskBatchResult
    ) -> HomebrewCaskEvaluation {
        let installed = Version(localVersion)
        let allRecords = batch.records.values.flatMap { $0 }

        // A declaration that now matches only a previous token is refused, never silently
        // retargeted to the renamed cask.
        for name in declaredNames {
            let matchesNow = allRecords.contains {
                HomebrewCaskUpdateProbe.declarationMatches(name, $0)
            }
            let matchesOldToken = allRecords.contains { $0.oldTokens.contains(name) }
            if !matchesNow && matchesOldToken { return .unknown(.identityUnverified) }
        }

        // Associate only this subject's declarations. Records whose token/full_token names a
        // declaration are candidates even when malformed, so a bad or aliased record poisons the
        // association instead of disappearing into apparent absence.
        let candidates = allRecords.filter { record in
            declaredNames.contains { name in
                name == record.token || name == record.fullToken
            }
        }
        guard !candidates.isEmpty else { return .unknown(.identityUnverified) }
        guard candidates.allSatisfy(\.isValid) else { return .unknown(.identityUnverified) }

        let candidateTokens = candidates.map(\.token)
        guard Set(candidateTokens).count == candidateTokens.count else {
            return .unknown(.identityUnverified)
        }

        let installedCandidates = candidates.filter {
            if case .string = $0.installed { return true }
            return false
        }
        guard installedCandidates.count == 1, let record = installedCandidates.first,
              case .string(let installedVersion) = record.installed
        else { return .unknown(.identityUnverified) }

        // One bare manager token is unique across the WHOLE info response. Two trees (even two
        // different tapped full_tokens) claiming one bare token can borrow the same combined
        // listing or outdated row; ambiguity is refused instead of first-wins.
        let tokenClaims = allRecords.filter { $0.token == record.token }
        guard tokenClaims.count == 1 else { return .unknown(.identityUnverified) }

        // The selected record must satisfy the narrow declaration rule: a bare declaration never
        // claims a tapped cask, and a tap declaration must equal `full_token`.
        guard declaredNames.contains(where: {
            HomebrewCaskUpdateProbe.declarationMatches($0, record)
        }) else { return .unknown(.identityUnverified) }

        // Re-derive the identity grammar instead of trusting `isValid`: a record can be
        // hand-constructed or restored with the default valid flag, exactly as in the formula
        // resolver. A contradictory token/full_token/tap claim is never compared.
        guard HomebrewCaskUpdateProbe.isStructurallyValidCask(
            token: record.token, fullToken: record.fullToken, tap: record.tap
        ), HomebrewCaskUpdateProbe.isSafeVersionText(record.version) else {
            return .unknown(.identityUnverified)
        }

        // The selected canonical target must either decompose EXACTLY under the bound Caskroom
        // (staged cask) or be the verified target of a listed staged `.app` link (moved app).
        guard let selected = HomebrewCaskTargetParser.cleanedAbsolutePath(selectedTarget),
              HomebrewCaskUpdateProbe.proofDirectoriesAreLive(
                batch: batch, token: record.token, installedVersion: installedVersion
              )
        else { return .unknown(.identityUnverified) }

        switch HomebrewCaskTargetParser.parse(
            selectedTarget: selected, caskroom: batch.caskroom.canonicalPath
        ) {
        case .success(let staged):
            guard staged.token == record.token,
                  staged.versionDirectory == installedVersion,
                  batch.installedTokens.contains(record.token),
                  batch.listing.contains(where: { componentPathsEqual($0, staged.selectedTarget) }),
                  isRegularStagedFile(staged.selectedTarget)
            else { return .unknown(.identityUnverified) }
        case .failure(.managerMismatch):
            // The narrow M13-A moved-app proof: a listed staged symlink whose name and resolved
            // target are `.app` directories, with the selection component-bounded inside it.
            guard batch.installedTokens.contains(record.token),
                  movedAppBinding(
                    batch: batch,
                    token: record.token,
                    installedVersion: installedVersion,
                    selectionTarget: selected
                  ) != nil
            else { return .unknown(.identityUnverified) }
        case .failure(.unverified):
            return .unknown(.identityUnverified)
        }

        // Typed unknowns retain their reason even when the row is otherwise plausible.
        if record.disabled { return .unknown(.caskDisabled) }
        if record.version == "latest" { return .unknown(.caskTracksLatest) }
        if record.autoUpdates == true { return .unknown(.caskAutoUpdates) }

        // Outdated records are keyed on the BARE TOKEN. A foreign record keyed by this cask's full
        // token is an alias claim and poisons the association (never mixed with formula rules).
        let tokenOutdated = batch.outdated[record.token] ?? []
        guard tokenOutdated.allSatisfy(\.isValid) else { return .unknown(.identityUnverified) }
        guard tokenOutdated.count <= 1 else { return .unknown(.identityUnverified) }
        if record.fullToken != record.token,
           !(batch.outdated[record.fullToken] ?? []).isEmpty {
            return .unknown(.identityUnverified)
        }
        let outdatedRecord = tokenOutdated.first

        if let outdatedRecord {
            // Both manager verdicts must agree, and the record must describe this exact install.
            guard record.outdated,
                  outdatedRecord.currentVersion == record.version,
                  outdatedRecord.installedVersions == [installedVersion],
                  outdatedRecord.pinned == record.pinned,
                  installedVersion != record.version
            else { return .unknown(.identityUnverified) }
            // The manager says a newer version exists; version strings are opaque and are never
            // ordered. The raw manager `version` is published verbatim.
            return .verified(HomebrewCaskComparison(
                token: record.token,
                fullToken: record.fullToken,
                tap: record.tap,
                installedVersion: installedVersion,
                version: record.version,
                pinned: record.pinned,
                managerOutdated: true,
                status: .updateAvailable(installed: installed, latest: Version(record.version))
            ))
        }

        // No outdated record: the info row must also say not-outdated, and the manager strings
        // decide equality. An unequal, non-outdated pair is inconsistent; it is never reported as
        // up to date, never converted into an update offer, and never given an invented order.
        guard !record.outdated else { return .unknown(.identityUnverified) }
        guard installedVersion == record.version else {
            return .unknown(.caskMetadataInconsistent)
        }
        return .verified(HomebrewCaskComparison(
            token: record.token,
            fullToken: record.fullToken,
            tap: record.tap,
            installedVersion: installedVersion,
            version: record.version,
            pinned: record.pinned,
            managerOutdated: false,
            status: .upToDate(installed: installed, latest: Version(record.version))
        ))
    }

    /// A staged symlink to an actual `.app` directory. The link and target names may differ; the
    /// selection must be component-bounded inside the resolved bundle. A link to a plain file or a
    /// broad directory is never a moved-app proof. The exact predicate is re-run at publish through
    /// the live re-evaluation and directory binding checks.
    private struct AppLinkBinding: Equatable {
        let linkPath: String
        let appDirectory: String
    }

    private static func movedAppBinding(
        batch: HomebrewCaskBatchResult,
        token: String,
        installedVersion: String,
        selectionTarget: String
    ) -> AppLinkBinding? {
        let lines = stagedLines(
            batch.listing,
            caskroomCanonical: batch.caskroom.canonicalPath,
            token: token,
            version: installedVersion
        )
        for line in lines {
            if let binding = appLinkBinding(
                linkPath: line, selectionTarget: selectionTarget
            ) {
                return binding
            }
        }
        return nil
    }

    /// The non-metadata lines that sit under `<caskroom>/<token>/<installed>/`. `.metadata` is
    /// manager bookkeeping at any depth below the Caskroom and never proves membership.
    private static func stagedLines(
        _ lines: [String],
        caskroomCanonical: String,
        token: String,
        version: String
    ) -> [String] {
        let rootComponents = HomebrewCaskTargetParser.components(of: caskroomCanonical)
        return lines.filter { line in
            let components = HomebrewCaskTargetParser.components(of: line)
            guard components.count > rootComponents.count,
                  Array(components.prefix(rootComponents.count)) == rootComponents
            else { return false }
            let relative = Array(components.dropFirst(rootComponents.count))
            guard !relative.contains(".metadata"),
                  relative.count > 2,
                  relative[0] == token,
                  relative[1] == version
            else { return false }
            return true
        }
    }

    private static func appLinkBinding(
        linkPath: String,
        selectionTarget: String
    ) -> AppLinkBinding? {
        guard isSymlink(linkPath),
              isAppBundleName(lastComponent(of: linkPath)),
              let target = FileIdentityObserver.observeDirectory(
                path: resolvedPath(linkPath)
              ),
              isAppBundleName(lastComponent(of: target.canonicalPath)),
              componentPathsEqual(selectionTarget, target.canonicalPath)
                || FileIdentityObserver.isStrictDescendant(
                    selectionTarget, of: target.canonicalPath
                )
        else { return nil }
        return AppLinkBinding(
            linkPath: linkPath, appDirectory: target.canonicalPath
        )
    }

    private static func componentPathsEqual(_ lhs: String, _ rhs: String) -> Bool {
        guard let left = HomebrewCaskTargetParser.cleanedAbsolutePath(lhs),
              let right = HomebrewCaskTargetParser.cleanedAbsolutePath(rhs)
        else { return false }
        return HomebrewCaskTargetParser.components(of: left)
            == HomebrewCaskTargetParser.components(of: right)
    }

    /// Matches the spelling rule used by `FileIdentityObserver`: Foundation's canonical spelling,
    /// not the POSIX `/private/var` alias.
    private static func resolvedPath(_ path: String) -> String {
        URL(fileURLWithPath: path)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
    }

    private static func isAppBundleName(_ name: String) -> Bool {
        name.lowercased().hasSuffix(".app")
    }

    private static func lastComponent(of path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    private static func isSymlink(_ path: String) -> Bool {
        guard let mode = linkStatusMode(path) else { return false }
        return (mode & mode_t(S_IFMT)) == mode_t(S_IFLNK)
    }

    private static func isRegularStagedFile(_ path: String) -> Bool {
        guard let mode = linkStatusMode(path) else { return false }
        return (mode & mode_t(S_IFMT)) == mode_t(S_IFREG)
    }

    private static func linkStatusMode(_ path: String) -> mode_t? {
        guard path.hasPrefix("/"), !path.utf8.contains(0) else { return nil }
        var info = stat()
        let status = path.withCString { pointer in lstat(pointer, &info) }
        return status == 0 ? info.st_mode : nil
    }
}
