// HomebrewFormulaUpdateOperation — confirmed, one-shot Homebrew formula upgrade (M13-D R5/R6/R8/R9).
//
// Preparation performs a complete fresh ownership proof, a fresh manager-info observation and the
// unscoped pin cross-check, without reading or writing any metadata cache. Confirmation repeats the
// full observation after a fresh local scan, compares every bound fact, revalidates the live proof
// and the owned operation root, then launches one literal `brew upgrade` argv. After a launch the
// operation always reconciles local and manager facts; exit zero alone is never success.
//
// The fresh formula observation in this file is shared with the formula Uninstall operation: one
// identity/ownership/pin/target observation, two operations. It deliberately reuses the public
// ownership-verification entry point, the manager-info parser grammar and the batch target parser
// instead of inventing a second proof.

import Darwin
import Foundation

// MARK: - Shared fresh formula observation

/// One fresh, read-only formula observation bound to live filesystem identity. The cellars, kegs
/// and manager values are the manager's own reports; `targetVersion` is nil when the manager's
/// stable version text is absent or not a supported Homebrew stable version (Uninstall tolerates
/// that, Update refuses it).
struct HomebrewFormulaFacts: Sendable {
    let selectedEntryPath: String
    let selectedTarget: String
    let selection: ObservedExecutable
    let manager: ObservedExecutable
    let installation: VerifiedInstallation
    let formulaName: String
    let fullName: String
    /// The manager's own installation prefix (`brew --prefix`), observed and bound separately
    /// from the Cellar. Required for launch; a missing, replaced or inconsistent prefix refuses.
    let prefix: DirectoryIdentity
    let cellar: DirectoryIdentity
    let keg: DirectoryIdentity
    let selectedKegVersion: String
    let installedKegs: [String]
    /// Which keg Homebrew's own unpinned `uninstall --formula` resolves by its documented
    /// precedence. Update ignores this evidence; Uninstall requires it to name the selected keg.
    let removalTarget: HomebrewRemovalTargetEvidence
    let targetVersion: String?
    let pinned: Bool
    let deprecated: Bool
    let deprecationDisclosure: String?
    let disabled: Bool
    let disableReason: String?
}

enum HomebrewFormulaObservationFailure: Equatable, Sendable {
    case noVerifiedSelection
    case managerUnavailable
    case unsupportedManager
    case identityUnverified
    case managerPrefixUnverified
    case pinned
    case metadataInvalid
    case budgetExhausted
    case cancelled
    case probeFailed
}

enum HomebrewFormulaObservationResult: Sendable {
    case success(HomebrewFormulaFacts)
    case unavailable(HomebrewFormulaObservationFailure)
}

enum HomebrewFormulaObservation {

    /// One bounded observation. Every manager query is read-only, carries the diagnostic
    /// environment (never the mutation environment), and is followed by a revalidation of the
    /// selected executable, the manager, the prefix, the Cellar and the selected keg.
    static func observe(
        definition: DetectorDefinition,
        diagnostic: ToolPathDiagnostic,
        environment: ShellEnvironment,
        runner: UpdateCommandRunner,
        currentDirectory: String,
        uptime: @escaping @Sendable () -> UInt64,
        stageDeadline: UInt64
    ) async -> HomebrewFormulaObservationResult {
        if Task.isCancelled { return .unavailable(.cancelled) }
        guard uptime() < stageDeadline else { return .unavailable(.budgetExhausted) }
        guard let pair = homebrewFormulaSelectionPair(diagnostic),
              let selection = FileIdentityObserver.observeExecutable(entryPath: pair.entry),
              selection.canonicalTarget == pair.target
        else { return .unavailable(.noVerifiedSelection) }

        let observed = await InstallationOwnershipVerifier.verify(
            definition: definition,
            diagnostic: diagnostic,
            environment: environment,
            runner: runner,
            currentDirectory: currentDirectory,
            now: { Date() }
        )
        if Task.isCancelled { return .unavailable(.cancelled) }
        guard uptime() < stageDeadline else { return .unavailable(.budgetExhausted) }
        let installation: VerifiedInstallation
        switch observed.outcome {
        case .unknown(let reason):
            return .unavailable(map(reason))
        case .verified(let value):
            installation = value
        }
        guard installation.manager == .homebrewFormula,
              !installation.packageName.isEmpty,
              installation.selection.entryPath == selection.entryPath,
              installation.selection.canonicalTarget == pair.target,
              installation.selection.fingerprint == selection.fingerprint
        else { return .unavailable(.unsupportedManager) }
        guard let manager = FileIdentityObserver.observeExecutable(
            entryPath: installation.managerEntryPath
        ), manager.canonicalTarget == installation.managerTarget,
           manager.fingerprint == installation.managerFingerprint
        else { return .unavailable(.identityUnverified) }

        // Decompose the selected canonical target by path components against the manager's own
        // Cellar. The keg directory must be exactly `<Cellar>/<formula>/<keg>`.
        guard let selectedKeg = try? HomebrewTargetParser.parse(
            selectedTarget: pair.target,
            cellar: installation.managerRoot
        ).get() else {
            return .unavailable(.identityUnverified)
        }
        guard FileIdentityObserver.isExactDescendant(
            installation.installationRoot,
            of: installation.managerRoot,
            components: [selectedKeg.formula, selectedKeg.kegVersion]
        ), let cellar = FileIdentityObserver.observeDirectory(path: installation.managerRoot),
           let keg = FileIdentityObserver.observeDirectory(path: installation.installationRoot)
        else { return .unavailable(.identityUnverified) }

        // The actual manager prefix is a separate fact from the Cellar. It comes from the exact
        // verified manager, is normalized through the directory identity observer so ordinary
        // filesystem aliases compare correctly, and must contain the observed Cellar. The prefix
        // is never derived by stripping a Cellar suffix and no installation location is assumed.
        let prefixData: Data
        if Task.isCancelled { return .unavailable(.cancelled) }
        guard uptime() < stageDeadline else { return .unavailable(.budgetExhausted) }
        switch await query(
            manager: manager,
            arguments: ["--prefix"],
            environment: environment,
            runner: runner
        ) {
        case .failure(let failure):
            return .unavailable(map(failure))
        case .success(let data):
            prefixData = data
        }
        if Task.isCancelled { return .unavailable(.cancelled) }
        guard uptime() < stageDeadline else { return .unavailable(.budgetExhausted) }
        guard let prefixText = ManagerOutputParser.singleAbsolutePath(prefixData),
              let prefix = FileIdentityObserver.observeDirectory(path: prefixText),
              prefix.canonicalPath != "/",
              FileIdentityObserver.isStrictDescendant(
                cellar.canonicalPath, of: prefix.canonicalPath
              )
        else { return .unavailable(.managerPrefixUnverified) }
        guard homebrewFormulaProofIsLive(
            selection: selection, manager: manager, prefix: prefix, cellar: cellar, keg: keg
        ) else { return .unavailable(.identityUnverified) }

        // One fresh metadata query for this exact manager-returned full identity.
        let infoData: Data
        switch await query(
            manager: manager,
            arguments: ["info", "--json=v2", "--formula", installation.packageName],
            environment: environment,
            runner: runner
        ) {
        case .failure(let failure):
            return .unavailable(map(failure))
        case .success(let data):
            infoData = data
        }
        if Task.isCancelled { return .unavailable(.cancelled) }
        guard uptime() < stageDeadline else { return .unavailable(.budgetExhausted) }

        // The unscoped pin list: `brew list --pinned` prints installed rack basenames and cask
        // tokens. It is the cross-check for `info.pinned`; disagreement fails closed.
        let pinnedData: Data
        switch await query(
            manager: manager,
            arguments: ["list", "--pinned"],
            environment: environment,
            runner: runner
        ) {
        case .failure(let failure):
            return .unavailable(map(failure))
        case .success(let data):
            pinnedData = data
        }
        if Task.isCancelled { return .unavailable(.cancelled) }
        guard uptime() < stageDeadline else { return .unavailable(.budgetExhausted) }
        guard let pinnedNames = parsePinnedList(pinnedData) else {
            return .unavailable(.probeFailed)
        }

        guard let records = parseInfo(infoData), records.count == 1, let record = records.first
        else { return .unavailable(.metadataInvalid) }
        guard HomebrewUpdateProbe.formulaIdentityConsistent(
            name: record.name, fullName: record.fullName
        ), record.name == selectedKeg.formula,
           record.fullName == installation.packageName,
           record.installedKegs.contains(selectedKeg.kegVersion)
        else { return .unavailable(.identityUnverified) }

        let pinnedByList = pinnedNames.contains(record.name)
            || pinnedNames.contains(record.fullName)
        guard record.pinned == pinnedByList else { return .unavailable(.identityUnverified) }
        if record.pinned { return .unavailable(.pinned) }

        let targetVersion: String?
        if let stable = record.stable, let revision = record.revision,
           HomebrewUpdateProbe.isSupportedUpstreamVersion(stable) {
            let candidate = revision > 0 ? "\(stable)_\(revision)" : stable
            targetVersion = VersionComparison.parseHomebrewStable(candidate) == nil ? nil : candidate
        } else {
            targetVersion = nil
        }

        let removalTarget = homebrewRemovalTargetEvidence(
            prefix: prefix,
            cellar: cellar,
            formulaName: selectedKeg.formula,
            installedKegs: record.installedKegs,
            selectedKegVersion: selectedKeg.kegVersion,
            selectedKeg: keg
        )

        guard homebrewFormulaProofIsLive(
            selection: selection, manager: manager, prefix: prefix, cellar: cellar, keg: keg
        ) else { return .unavailable(.identityUnverified) }
        if Task.isCancelled { return .unavailable(.cancelled) }
        guard uptime() < stageDeadline else { return .unavailable(.budgetExhausted) }

        return .success(HomebrewFormulaFacts(
            selectedEntryPath: pair.entry,
            selectedTarget: pair.target,
            selection: selection,
            manager: manager,
            installation: installation,
            formulaName: selectedKeg.formula,
            fullName: installation.packageName,
            prefix: prefix,
            cellar: cellar,
            keg: keg,
            selectedKegVersion: selectedKeg.kegVersion,
            installedKegs: record.installedKegs.sorted(),
            removalTarget: removalTarget,
            targetVersion: targetVersion,
            pinned: record.pinned,
            deprecated: record.deprecated,
            deprecationDisclosure: deprecationDisclosure(for: record),
            disabled: record.disabled,
            disableReason: record.disableReason.map { homebrewBoundedDetail($0) }
        ))
    }

    private static func map(
        _ reason: InstallationOwnershipReason
    ) -> HomebrewFormulaObservationFailure {
        switch reason {
        case .managerUnavailable: .managerUnavailable
        case .cancelled: .cancelled
        case .notInstalled, .selectionUnavailable, .inconsistentSelection: .noVerifiedSelection
        case .managerQueryFailed, .invalidManagerOutput: .probeFailed
        case .unsupportedSource, .noDeclaredPackage, .unsupportedCask,
             .unsupportedInstallationLayout, .managerRootMismatch:
            .unsupportedManager
        default: .identityUnverified
        }
    }

    private static func map(_ failure: CommandFailure) -> HomebrewFormulaObservationFailure {
        switch failure {
        case .cancelled: .cancelled
        default: .probeFailed
        }
    }

    static func query(
        manager: ObservedExecutable,
        arguments: [String],
        environment: ShellEnvironment,
        runner: UpdateCommandRunner
    ) async -> CommandOutcome {
        if Task.isCancelled { return .failure(.cancelled) }
        let outcome = await runner.run(
            executablePath: manager.entryPath,
            arguments: arguments,
            environment: HomebrewUpdateProbe.diagnosticEnvironment(from: environment),
            timeout: HomebrewUpdateProbe.queryTimeout
        )
        if Task.isCancelled { return .failure(.cancelled) }
        return outcome
    }

    // MARK: Manager JSON

    private struct FormulaInfoRecord {
        let name: String
        let fullName: String
        let stable: String?
        let revision: Int?
        let installedKegs: [String]
        let pinned: Bool
        let deprecated: Bool
        let deprecationDate: String?
        let deprecationReason: String?
        let disabled: Bool
        let disableReason: String?
    }

    /// Parses only the fields this operation needs. Identity, booleans and the installed keg list
    /// are strict; an unreadable collection is malformed rather than shortened. `versions.stable`
    /// is optional text: absent, JSON null (Homebrew's own `to_hash` shape for a formula with no
    /// stable spec) or an unsupported stable version makes Update refuse but is not itself corrupt
    /// manager output. A present non-null, non-string stable is malformed and fails closed.
    private static func parseInfo(_ data: Data) -> [FormulaInfoRecord]? {
        guard let text = homebrewStrictUTF8Text(data),
              let json = try? JSONSerialization.jsonObject(with: Data(text.utf8), options: []),
              let root = json as? [String: Any],
              let formulae = root["formulae"] as? [Any]
        else { return nil }
        var records: [FormulaInfoRecord] = []
        records.reserveCapacity(formulae.count)
        for element in formulae {
            guard let object = element as? [String: Any],
                  let name = object["name"] as? String,
                  let fullName = object["full_name"] as? String,
                  let installed = installedKegs(object["installed"]),
                  let pinned = strictBool(object["pinned"]),
                  let deprecated = strictBool(object["deprecated"]),
                  let disabled = strictBool(object["disabled"])
            else { return nil }
            let stable: String?
            let revision: Int?
            if let versions = object["versions"] {
                guard let versionsObject = versions as? [String: Any] else { return nil }
                if let rawStable = versionsObject["stable"], !(rawStable is NSNull) {
                    guard let value = rawStable as? String else { return nil }
                    stable = value
                } else {
                    stable = nil
                }
            } else {
                stable = nil
            }
            if let rawRevision = object["revision"] {
                guard let value = strictNonnegativeInt(rawRevision) else { return nil }
                revision = value
            } else {
                revision = nil
            }
            guard let deprecationDate = optionalString(object, "deprecation_date"),
                  let deprecationReason = optionalString(object, "deprecation_reason"),
                  let disableReason = optionalString(object, "disable_reason")
            else { return nil }
            records.append(FormulaInfoRecord(
                name: name,
                fullName: fullName,
                stable: stable,
                revision: revision,
                installedKegs: installed,
                pinned: pinned,
                deprecated: deprecated,
                deprecationDate: deprecationDate,
                deprecationReason: deprecationReason,
                disabled: disabled,
                disableReason: disableReason
            ))
        }
        return records
    }

    /// Post-launch fact extraction: the installed keg list for one exact identity, or nil when the
    /// response is malformed or names a different formula.
    static func installedKegs(
        fromInfo data: Data,
        fullName: String,
        formulaName: String
    ) -> [String]? {
        guard let records = parseInfo(data), records.count == 1, let record = records.first,
              record.fullName == fullName,
              record.name == formulaName,
              HomebrewUpdateProbe.formulaIdentityConsistent(
                name: record.name, fullName: record.fullName
              )
        else { return nil }
        return record.installedKegs.sorted()
    }

    private static func installedKegs(_ value: Any?) -> [String]? {
        guard let entries = value as? [Any] else { return nil }
        var versions: [String] = []
        versions.reserveCapacity(entries.count)
        for entry in entries {
            guard let object = entry as? [String: Any],
                  let version = object["version"] as? String,
                  !version.isEmpty, !version.utf8.contains(0)
            else { return nil }
            versions.append(version)
        }
        return versions
    }

    private static func optionalString(_ object: [String: Any], _ key: String) -> String?? {
        guard let value = object[key] else { return .some(nil) }
        if value is NSNull { return .some(nil) }
        guard let string = value as? String else { return nil }
        return .some(string)
    }

    /// `brew list --pinned` prints one pinned rack basename or cask token per line. Empty output is
    /// a valid "nothing pinned" answer. Anything else is malformed output, never a silent miss.
    private static func parsePinnedList(_ data: Data) -> [String]? {
        guard !data.isEmpty else { return [] }
        guard let text = homebrewStrictUTF8Text(data) else { return nil }
        var names: [String] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = rawLine
            if line.last == "\r" { line = line.dropLast() }
            if line.isEmpty { continue }
            let name = String(line)
            guard !name.hasPrefix("-"), HomebrewUpdateProbe.isValidFormulaName(name) else {
                return nil
            }
            names.append(name)
        }
        return names
    }

    private static func deprecationDisclosure(for record: FormulaInfoRecord) -> String? {
        guard record.deprecated else { return nil }
        var parts = ["Homebrew marks this formula as deprecated."]
        if let date = record.deprecationDate, !date.isEmpty {
            parts.append("Deprecated on \(homebrewBoundedDetail(date)).")
        }
        if let reason = record.deprecationReason, !reason.isEmpty {
            parts.append("Reason: \(homebrewBoundedDetail(reason)).")
        }
        parts.append("Update remains available; no replacement is installed automatically.")
        return parts.joined(separator: " ")
    }

    private static func strictBool(_ value: Any?) -> Bool? {
        guard let value else { return nil }
        guard CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID() else { return nil }
        return (value as! NSNumber).boolValue
    }

    /// Strict nonnegative integer extraction. Booleans bridge as `NSNumber` and fractional or
    /// out-of-range numbers would truncate silently, so both are rejected as malformed data.
    private static func strictNonnegativeInt(_ value: Any?) -> Int? {
        guard let value else { return nil }
        guard CFGetTypeID(value as CFTypeRef) != CFBooleanGetTypeID() else { return nil }
        guard let number = value as? NSNumber else { return nil }
        switch String(cString: number.objCType) {
        case "s", "i", "q", "l": break
        default: return nil
        }
        let widened = number.int64Value
        guard widened >= 0, widened <= Int64(Int.max) else { return nil }
        return Int(widened)
    }
}

// MARK: - Shared formula helpers

func homebrewStrictUTF8Text(_ data: Data) -> String? {
    let byteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]
    if data.count >= 3, Array(data.prefix(3)) == byteOrderMark { return nil }
    if data.contains(0x00) { return nil }
    guard let text = String(data: data, encoding: .utf8) else { return nil }
    guard Data(text.utf8) == data else { return nil }
    return text
}

/// Bounds manager-supplied disclosure text so a hostile reason cannot flood a preview.
func homebrewBoundedDetail(_ value: String, limit: Int = 200) -> String {
    let scalars = Array(value.unicodeScalars)
    guard scalars.count > limit else { return value }
    return String(String.UnicodeScalarView(scalars.prefix(limit)))
}

func homebrewFormulaProofIsLive(
    selection: ObservedExecutable,
    manager: ObservedExecutable,
    prefix: DirectoryIdentity,
    cellar: DirectoryIdentity,
    keg: DirectoryIdentity
) -> Bool {
    FileIdentityObserver.observeExecutable(entryPath: selection.entryPath) == selection
        && FileIdentityObserver.observeExecutable(entryPath: manager.entryPath) == manager
        && FileIdentityObserver.observeDirectory(path: prefix.canonicalPath) == prefix
        && FileIdentityObserver.observeDirectory(path: cellar.canonicalPath) == cellar
        && FileIdentityObserver.observeDirectory(path: keg.canonicalPath) == keg
}

/// One manager link observed by `lstat` first, then by the shared directory identity observer.
private enum HomebrewManagerLinkObservation: Equatable {
    case absent
    case resolves(DirectoryIdentity)
    case invalid
}

private func observeHomebrewManagerLink(_ path: String) -> HomebrewManagerLinkObservation {
    var info = Darwin.stat()
    let status = path.withCString { Darwin.lstat($0, &info) }
    guard status == 0 else {
        let code = errno
        return (code == ENOENT || code == ENOTDIR) ? .absent : .invalid
    }
    guard (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFLNK) else { return .invalid }
    guard let resolved = FileIdentityObserver.observeDirectory(path: path) else { return .invalid }
    return .resolves(resolved)
}

/// A bounded, fail-closed classification of the live Cellar rack Homebrew enumerates for its
/// single-keg fallback. Homebrew counts rack entries whose path is a directory (`Pathname#directory?`,
/// which follows symlinks); this proof must not guess, so a plain directory is a possible keg, a
/// symlink is unclassifiable without following it and refuses, and an ordinary known non-directory
/// (regular file, socket, FIFO, device) is not a keg. Any read failure or an entry count beyond the
/// bound refuses instead of producing a partial count.
private enum HomebrewCellarRackObservation: Equatable {
    case exactlyOne(DirectoryIdentity)
    case none
    case multiple
    case unverifiable
}

/// Far above any real Cellar rack (a formula's installed versions), small enough to keep the
/// observation bounded on a hostile or corrupt filesystem.
private let homebrewRackEntryLimit = 512

private func observeHomebrewCellarRack(
    cellar: DirectoryIdentity,
    formulaName: String
) -> HomebrewCellarRackObservation {
    // The rack is the lowercased formula directory under the bound Cellar. Requiring the observed
    // canonical spelling to equal that literal path rejects a rack replaced by a symlink while
    // still allowing the ordinary `/var`<->`/private/var` alias handled by the directory observer.
    let rackPath = cellar.canonicalPath + "/" + formulaName.lowercased()
    guard let rack = FileIdentityObserver.observeDirectory(path: rackPath),
          rack.canonicalPath == rackPath
    else { return .unverifiable }
    guard let names = boundedHomebrewDirectoryEntryNames(rackPath) else { return .unverifiable }

    var candidates: [DirectoryIdentity] = []
    for name in names {
        let entryPath = rackPath + "/" + name
        var info = Darwin.stat()
        let status = entryPath.withCString { Darwin.lstat($0, &info) }
        // A vanished or unreadable entry means the rack changed during the observation; a partial
        // roster cannot prove how many kegs Homebrew will see.
        guard status == 0 else { return .unverifiable }
        switch info.st_mode & mode_t(S_IFMT) {
        case mode_t(S_IFDIR):
            guard let identity = FileIdentityObserver.observeDirectory(path: entryPath),
                  identity.canonicalPath == entryPath
            else { return .unverifiable }
            candidates.append(identity)
        case mode_t(S_IFLNK):
            // Homebrew's `directory?` follows the link, so a directory symlink would be another
            // possible keg and a link to a non-directory is not provably harmless. Refuse.
            return .unverifiable
        default:
            // A known non-directory is not a keg and does not prove another one.
            continue
        }
    }
    // The rack must still be the same vnode after the walk; a replacement mid-enumeration leaves
    // the roster stale.
    guard FileIdentityObserver.observeDirectory(path: rackPath) == rack else {
        return .unverifiable
    }
    switch candidates.count {
    case 0:
        return .none
    case 1:
        return .exactlyOne(candidates[0])
    default:
        return .multiple
    }
}

/// Bounded `readdir(3)` roster. Returns nil when the directory cannot be opened or read, or when
/// it holds more entries than the proof is willing to classify. `.`/`..` are skipped.
private func boundedHomebrewDirectoryEntryNames(_ path: String) -> [String]? {
    guard let directory = opendir(path) else { return nil }
    defer { closedir(directory) }
    var names: [String] = []
    while true {
        errno = 0
        guard let entry = readdir(directory) else {
            return errno == 0 ? names : nil
        }
        let name = withUnsafePointer(to: entry.pointee.d_name) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) {
                String(cString: $0)
            }
        }
        if name == "." || name == ".." { continue }
        if names.count >= homebrewRackEntryLimit { return nil }
        names.append(name)
    }
}

/// Mirrors the pinned Homebrew `resolve_default_keg` precedence for the factual inputs this proof
/// can observe safely: an existing opt link, then an existing linked-keg link, then a single
/// installed keg. The single-keg case is decided from the live Cellar rack, never from the cached
/// manager inventory alone: Homebrew enumerates that rack's directory entries, so this proof does
/// too, immediately after the caller's final asynchronous query, and rejects anything it cannot
/// classify. Homebrew's final latest-installed resolution is not inferred; multiple kegs with no
/// usable manager link are a typed refusal instead.
func homebrewRemovalTargetEvidence(
    prefix: DirectoryIdentity,
    cellar: DirectoryIdentity,
    formulaName: String,
    installedKegs: [String],
    selectedKegVersion: String,
    selectedKeg: DirectoryIdentity
) -> HomebrewRemovalTargetEvidence {
    // `resolve_default_keg` builds the rack from `Formulary.to_rack(name.downcase)`; the opt and
    // linked paths use that rack basename, never the possibly tap-qualified argument.
    let rack = formulaName.lowercased()
    let optPath = prefix.canonicalPath + "/opt/" + rack
    switch observeHomebrewManagerLink(optPath) {
    case .resolves(let resolved):
        return resolved == selectedKeg
            ? .proven(HomebrewRemovalTarget(source: .optLink, keg: resolved))
            : .unproven(.optLinkMismatch)
    case .invalid:
        return .unproven(.contradictoryEvidence)
    case .absent:
        break
    }

    let linkedPath = prefix.canonicalPath + "/var/homebrew/linked/" + rack
    switch observeHomebrewManagerLink(linkedPath) {
    case .resolves(let resolved):
        return resolved == selectedKeg
            ? .proven(HomebrewRemovalTarget(source: .linkedKegLink, keg: resolved))
            : .unproven(.linkedKegLinkMismatch)
    case .invalid:
        return .unproven(.contradictoryEvidence)
    case .absent:
        break
    }

    // The manager inventory is only a consistency check here. It cannot prove the single-keg
    // fallback on its own: Homebrew decides that fallback from the rack's contents at the moment
    // the mutation starts, and a keg can appear after this metadata snapshot without changing the
    // selected executable or the cached count.
    guard installedKegs.count == 1 else { return .unproven(.ambiguousMultipleKegs) }
    guard installedKegs[0] == selectedKegVersion else { return .unproven(.contradictoryEvidence) }
    switch observeHomebrewCellarRack(cellar: cellar, formulaName: formulaName) {
    case .exactlyOne(let live):
        guard live == selectedKeg else { return .unproven(.contradictoryEvidence) }
        return .proven(HomebrewRemovalTarget(source: .singleInstalledKeg, keg: live))
    case .none, .unverifiable:
        return .unproven(.rackUnverified)
    case .multiple:
        return .unproven(.ambiguousMultipleKegs)
    }
}

/// Re-observes the same manager links and, for the no-link fallback, the live Cellar rack
/// immediately before launch. The returned evidence must equal the bound preparation evidence, so
/// a retargeted opt/linked link or a second keg directory refuses even when the selected executable
/// and every other proof path are unchanged.
func homebrewRemovalTargetIsLive(
    prefix: DirectoryIdentity,
    cellar: DirectoryIdentity,
    formulaName: String,
    installedKegs: [String],
    selectedKegVersion: String,
    selectedKeg: DirectoryIdentity,
    expected: HomebrewRemovalTarget
) -> Bool {
    homebrewRemovalTargetEvidence(
        prefix: prefix,
        cellar: cellar,
        formulaName: formulaName,
        installedKegs: installedKegs,
        selectedKegVersion: selectedKegVersion,
        selectedKeg: selectedKeg
    ) == .proven(expected)
}

func homebrewFormulaSelectionPair(
    _ diagnostic: ToolPathDiagnostic
) -> (entry: String, target: String)? {
    let candidate: PathCandidateObservation
    switch diagnostic.selection {
    case .winner(let value): candidate = value
    case .offPath(let value, _): candidate = value
    case .notInstalled, .inconsistent: return nil
    }
    guard let target = candidate.canonicalTarget, !target.isEmpty else { return nil }
    return (candidate.entryPath, target)
}

func homebrewFormulaAliases(_ diagnostic: ToolPathDiagnostic) -> [String] {
    diagnostic.pathCandidates.map(\.entryPath)
}

/// The manager-returned proof identity is the only dynamic argv element. It is validated as a
/// Homebrew identity (closed alphabet, `name` or `owner/tap/name`) and must not look like a flag.
enum HomebrewFormulaIdentity {
    static func isSafeProofName(fullName: String, formulaName: String) -> Bool {
        !fullName.isEmpty
            && !fullName.hasPrefix("-")
            && !fullName.contains("\n")
            && HomebrewUpdateProbe.formulaIdentityConsistent(
                name: formulaName, fullName: fullName
            )
    }
}

// MARK: - Formula Update

/// The internal authorization evidence behind one public Update preview. Never public, never
/// persisted.
struct HomebrewFormulaUpdatePlan: Sendable {
    let definition: DetectorDefinition
    let diagnostic: ToolPathDiagnostic
    let selectedEntryPath: String
    let selectedTarget: String
    let selection: ObservedExecutable
    let manager: ObservedExecutable
    let prefix: DirectoryIdentity
    let cellar: DirectoryIdentity
    let keg: DirectoryIdentity
    let installation: VerifiedInstallation
    let formulaName: String
    let fullName: String
    let selectedKegVersion: String
    let installedKegs: [String]
    let targetVersion: String
    let pinned: Bool
    let deprecated: Bool
    let deprecationDisclosure: String?
    let disabled: Bool
    let environment: ShellEnvironment
    let environmentFingerprint: String
    let currentDirectory: String
    let updateRunner: UpdateCommandRunner
    let root: NpmScratchRoot
    let arguments: [String]
    let preview: HomebrewFormulaUpdatePreview
}

/// An opaque Update preparation. It has no public initializer and cannot be built from display
/// strings. It retains the owned operation root until cancelled or consumed by `execute`.
public final class HomebrewFormulaUpdatePreparation: @unchecked Sendable {
    public let preview: HomebrewFormulaUpdatePreview
    internal let plan: HomebrewFormulaUpdatePlan

    private let lock = NSLock()
    private var claimed = false
    private var released = false

    internal init(preview: HomebrewFormulaUpdatePreview, plan: HomebrewFormulaUpdatePlan) {
        self.preview = preview
        self.plan = plan
    }

    /// Consumes the authorization evidence exactly once.
    internal func claim() -> HomebrewFormulaUpdatePlan? {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed, !released else { return nil }
        claimed = true
        return plan
    }

    /// Releases a preparation that will never execute. Returns false if it was already consumed.
    internal func releaseUnconsumed() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed, !released else { return false }
        released = true
        return releaseOperationRoot(plan.root)
    }

    internal var isConsumed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return claimed || released
    }
}

/// The result of preparing one formula Update.
public enum HomebrewFormulaUpdatePrepareResult: Sendable {
    case ready(HomebrewFormulaUpdatePreparation)
    case unavailable(HomebrewFormulaUpdateUnavailableReason)
}

/// The complete formula Update result. Output is in-memory only and separate per stream.
public struct HomebrewFormulaUpdateOutcome: Equatable, Sendable {
    public let preview: HomebrewFormulaUpdatePreview
    public let state: OperationState
    public let stdout: Data
    public let stderr: Data
    public let stdoutTruncated: Bool
    public let stderrTruncated: Bool
    public let exitStatus: Int32?
    /// True only when the operation process was actually launched.
    public let processStarted: Bool
    public let reconciliation: HomebrewFormulaUpdateDelta?
    public let cleanupWarnings: [String]
    public let message: String?

    public var stdoutText: String { String(decoding: stdout, as: UTF8.self) }
    public var stderrText: String { String(decoding: stderr, as: UTF8.self) }
}

public enum HomebrewFormulaUpdateOperation {

    private static let preparationBudgetNanoseconds: UInt64 = 60 * 1_000_000_000
    private static let confirmationBudgetNanoseconds: UInt64 = 60 * 1_000_000_000

    /// Prepares an exact preview and claims one mode-0700 owned operation root. No cache is read or
    /// written and no brew mutation process is launched.
    public static func prepare(
        definition: DetectorDefinition,
        diagnostic: ToolPathDiagnostic,
        environment: ShellEnvironment,
        currentDirectory: String,
        runner: UpdateCommandRunner,
        operationRootBaseURL: URL? = nil,
        uptime: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
    ) async -> HomebrewFormulaUpdatePrepareResult {
        // D-021 guard position: cancellation first, then accepted-operation containment, before any
        // observation, scratch claim or process.
        if Task.isCancelled { return .unavailable(.cancelled) }
        guard definition.acceptedOperations.contains(.homebrewFormulaUpdate) else {
            return .unavailable(.operationNotAccepted)
        }
        let deadline = uptime() &+ preparationBudgetNanoseconds
        let scratchBase: URL
        if let operationRootBaseURL {
            scratchBase = operationRootBaseURL
        } else if environment.raw["TMPDIR"] != nil {
            guard let captured = capturedTemporaryDirectory(environment),
                  NpmScratchBase(url: captured) != nil
            else { return .unavailable(.operationRootUnsafe) }
            scratchBase = captured
        } else {
            scratchBase = FileManager.default.temporaryDirectory
        }

        let observation: HomebrewFormulaFacts
        switch await HomebrewFormulaObservation.observe(
            definition: definition,
            diagnostic: diagnostic,
            environment: environment,
            runner: runner,
            currentDirectory: currentDirectory,
            uptime: uptime,
            stageDeadline: deadline
        ) {
        case .unavailable(let failure):
            return .unavailable(map(failure))
        case .success(let facts):
            observation = facts
        }
        if Task.isCancelled { return .unavailable(.cancelled) }
        guard HomebrewFormulaIdentity.isSafeProofName(
            fullName: observation.fullName, formulaName: observation.formulaName
        ) else { return .unavailable(.identityUnverified) }
        // A disabled formula refuses Update regardless of its target grammar, and surfaces the
        // manager's own disable reason (bounded by the observation).
        guard observation.disabled == false else {
            return .unavailable(.formulaDisabled(disableReason: observation.disableReason))
        }
        guard let targetVersion = observation.targetVersion else {
            return .unavailable(.unsupportedVersion)
        }
        switch VersionComparison.ordering(
            observation.selectedKegVersion, targetVersion, scheme: .homebrewStable
        ) {
        case .older:
            break
        case .equal:
            return .unavailable(.notUpdateAvailable)
        case .newer:
            return .unavailable(.newerThanMetadata)
        case nil:
            return .unavailable(.unsupportedVersion)
        }

        guard let base = NpmScratchBase(url: scratchBase),
              let root = NpmScratchRoot.claim(base: base)
        else { return .unavailable(.operationRootUnsafe) }
        if Task.isCancelled {
            _ = releaseOperationRoot(root)
            return .unavailable(.cancelled)
        }

        let arguments = updateArguments(fullName: observation.fullName)
        let preview = HomebrewFormulaUpdatePreview(
            registryID: definition.id,
            displayName: definition.displayName,
            kind: .formula,
            formulaName: observation.formulaName,
            fullName: observation.fullName,
            selectedEntryPath: observation.selectedEntryPath,
            selectedTarget: observation.selectedTarget,
            selectedKegVersion: observation.selectedKegVersion,
            installedKegs: observation.installedKegs,
            targetVersion: targetVersion,
            targetResolution: homebrewFormulaTargetResolutionDisclosure,
            pinned: observation.pinned,
            deprecated: observation.deprecated,
            deprecationDisclosure: observation.deprecationDisclosure,
            managerPath: observation.manager.entryPath,
            prefix: observation.prefix.canonicalPath,
            cellar: observation.cellar.canonicalPath,
            workingDirectory: root.url.path,
            executablePath: observation.manager.entryPath,
            arguments: arguments,
            timeoutSeconds: Int(homebrewMutationTimeout),
            effect: homebrewFormulaUpdateEffectText
        )
        let plan = HomebrewFormulaUpdatePlan(
            definition: definition,
            diagnostic: diagnostic,
            selectedEntryPath: observation.selectedEntryPath,
            selectedTarget: observation.selectedTarget,
            selection: observation.selection,
            manager: observation.manager,
            prefix: observation.prefix,
            cellar: observation.cellar,
            keg: observation.keg,
            installation: observation.installation,
            formulaName: observation.formulaName,
            fullName: observation.fullName,
            selectedKegVersion: observation.selectedKegVersion,
            installedKegs: observation.installedKegs,
            targetVersion: targetVersion,
            pinned: observation.pinned,
            deprecated: observation.deprecated,
            deprecationDisclosure: observation.deprecationDisclosure,
            disabled: observation.disabled,
            environment: environment,
            environmentFingerprint: HomebrewOperationEnvironment.contextFingerprint(
                environment: environment, currentDirectory: currentDirectory
            ),
            currentDirectory: currentDirectory,
            updateRunner: runner,
            root: root,
            arguments: arguments,
            preview: preview
        )
        return .ready(HomebrewFormulaUpdatePreparation(preview: preview, plan: plan))
    }

    /// Cancels a pending preview and releases only its owned root.
    @discardableResult
    public static func cancel(_ preparation: HomebrewFormulaUpdatePreparation) -> Bool {
        preparation.releaseUnconsumed()
    }

    /// Consumes a confirmed preparation and launches at most one literal `brew upgrade`.
    public static func execute(
        confirmed preparation: HomebrewFormulaUpdatePreparation,
        environment: ShellEnvironment,
        scan: @escaping @Sendable (DetectorDefinition, ShellEnvironment, String) -> ToolPathDiagnostic?,
        reconcileAfterLaunch: @escaping @Sendable (DetectorDefinition) async -> (ToolPathDiagnostic, ShellEnvironment)?,
        updateRunner: UpdateCommandRunner,
        operationRunner: OperationCommandRunner,
        gate: OperationExecutionGate,
        uptime: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
    ) async -> HomebrewFormulaUpdateOutcome {
        let preview = preparation.preview
        guard await gate.acquire() else {
            let wasConsumed = preparation.isConsumed
            let cleanupOK = preparation.releaseUnconsumed()
            return noProcessOutcome(
                preview: preview,
                state: .cancelled,
                message: wasConsumed
                    ? "The preparation was already consumed by another execution."
                    : "Another mutation owns the operation gate; this preparation was released.",
                cleanupOK: wasConsumed ? true : cleanupOK
            )
        }
        guard let plan = preparation.claim() else {
            await gate.release()
            return noProcessOutcome(
                preview: preview,
                state: .failed,
                message: "The preparation was already consumed.",
                cleanupOK: true
            )
        }

        let deadline = uptime() &+ confirmationBudgetNanoseconds

        func finish(
            state: OperationState,
            stdout: Data = Data(),
            stderr: Data = Data(),
            stdoutTruncated: Bool = false,
            stderrTruncated: Bool = false,
            exitStatus: Int32? = nil,
            processStarted: Bool,
            reconciliation: HomebrewFormulaUpdateDelta? = nil,
            cleanupWarnings: [String] = [],
            message: String? = nil
        ) async -> HomebrewFormulaUpdateOutcome {
            var warnings = cleanupWarnings
            if !releaseOperationRoot(plan.root) {
                warnings.append("The owned operation scratch root could not be removed safely.")
            }
            await gate.release()
            return HomebrewFormulaUpdateOutcome(
                preview: plan.preview,
                state: state,
                stdout: stdout,
                stderr: stderr,
                stdoutTruncated: stdoutTruncated,
                stderrTruncated: stderrTruncated,
                exitStatus: exitStatus,
                processStarted: processStarted,
                reconciliation: reconciliation,
                cleanupWarnings: warnings,
                message: message
            )
        }

        guard HomebrewOperationEnvironment.contextFingerprint(
            environment: environment, currentDirectory: plan.currentDirectory
        ) == plan.environmentFingerprint else {
            return await finish(
                state: .failed, processStarted: false,
                message: "The captured environment changed; a new preview is required."
            )
        }
        guard plan.root.isLive() else {
            return await finish(
                state: .failed, processStarted: false,
                message: "The owned operation root changed; a new preview is required."
            )
        }
        guard uptime() < deadline, !Task.isCancelled else {
            return await finish(
                state: Task.isCancelled ? .cancelled : .failed, processStarted: false,
                message: Task.isCancelled
                    ? "The update was cancelled before launch."
                    : "Confirmation revalidation exceeded its read-only budget."
            )
        }
        guard let freshDiagnostic = scan(
            plan.definition, plan.environment, plan.currentDirectory
        ) else {
            return await finish(
                state: .failed, processStarted: false,
                message: "A fresh local scan could not be obtained; a new preview is required."
            )
        }
        guard let freshSelection = homebrewFormulaSelectionPair(freshDiagnostic),
              freshSelection.entry == plan.selectedEntryPath,
              freshSelection.target == plan.selectedTarget
        else {
            return await finish(
                state: .failed, processStarted: false,
                message: "The selected installation changed; a new preview is required."
            )
        }

        let confirmed: HomebrewFormulaFacts
        switch await HomebrewFormulaObservation.observe(
            definition: plan.definition,
            diagnostic: freshDiagnostic,
            environment: plan.environment,
            runner: updateRunner,
            currentDirectory: plan.currentDirectory,
            uptime: uptime,
            stageDeadline: deadline
        ) {
        case .unavailable(let failure):
            let state: OperationState = Task.isCancelled ? .cancelled : .failed
            let message: String
            switch failure {
            case .pinned:
                message = "The formula is now pinned; a new preview is required."
            case .cancelled:
                message = "The update was cancelled before launch."
            default:
                message = "Fresh confirmation failed: \(map(failure).message)"
            }
            return await finish(state: state, processStarted: false, message: message)
        case .success(let value):
            confirmed = value
        }

        // A changed manager-known target invalidates the preview by name (R5/F-8).
        guard confirmed.targetVersion == plan.targetVersion else {
            return await finish(
                state: .failed, processStarted: false,
                message: homebrewObservedTargetChangedMessage
            )
        }
        guard confirmed.selection == plan.selection,
              confirmed.manager == plan.manager,
              confirmed.prefix == plan.prefix,
              confirmed.installation == plan.installation,
              confirmed.formulaName == plan.formulaName,
              confirmed.fullName == plan.fullName,
              confirmed.selectedKegVersion == plan.selectedKegVersion,
              confirmed.installedKegs == plan.installedKegs,
              confirmed.pinned == plan.pinned,
              confirmed.deprecated == plan.deprecated,
              confirmed.deprecationDisclosure == plan.deprecationDisclosure,
              confirmed.disabled == plan.disabled
        else {
            return await finish(
                state: .failed, processStarted: false,
                message: "A bound formula identity or manager fact changed; a new preview is required."
            )
        }
        guard plan.root.isLive() else {
            return await finish(
                state: .failed, processStarted: false,
                message: "The owned operation root changed during confirmation; a new preview is required."
            )
        }
        guard homebrewFormulaProofIsLive(
            selection: plan.selection,
            manager: plan.manager,
            prefix: plan.prefix,
            cellar: plan.cellar,
            keg: plan.keg
        ) else {
            return await finish(
                state: .failed, processStarted: false,
                message: "The live Homebrew proof changed immediately before launch; no mutation was started."
            )
        }
        guard uptime() < deadline, !Task.isCancelled else {
            return await finish(
                state: Task.isCancelled ? .cancelled : .failed, processStarted: false,
                message: Task.isCancelled
                    ? "The update was cancelled before launch."
                    : "Confirmation revalidation exceeded its read-only budget."
            )
        }

        let operationEnvironment = HomebrewOperationEnvironment.mutationEnvironment(
            from: plan.environment, kind: .formulaUpdate
        )
        let processResult = await operationRunner.run(
            executablePath: plan.manager.entryPath,
            arguments: plan.arguments,
            environment: operationEnvironment,
            currentDirectory: plan.root.url.path,
            timeout: homebrewMutationTimeout
        )
        if !processResult.processStarted {
            return await finish(
                state: processResult.cancelled ? .cancelled : .failed,
                stdout: processResult.stdout,
                stderr: processResult.stderr,
                stdoutTruncated: processResult.stdoutTruncated,
                stderrTruncated: processResult.stderrTruncated,
                exitStatus: processResult.exitStatus,
                processStarted: false,
                message: processResult.cancelled
                    ? "The update was cancelled before the process launched."
                    : "The Homebrew process could not be launched; no mutation retry was attempted."
            )
        }

        var warnings: [String] = []
        if processResult.cleanupWarning {
            warnings.append("The Homebrew process group could not be fully reaped within the cleanup bound.")
        }
        let reconciliation: HomebrewFormulaUpdateDelta?
        if let fresh = await reconcileAfterLaunch(plan.definition) {
            // The post-launch observation must finish independently of the caller's cancellation.
            let reconciled = await Task.detached {
                await reconcile(plan: plan, diagnostic: fresh.0, environment: fresh.1)
            }.value
            reconciliation = reconciled.0
            warnings.append(contentsOf: reconciled.1)
        } else {
            reconciliation = nil
        }
        let interrupted = processResult.cancelled || processResult.timedOut
            || processResult.stdoutTruncated || processResult.stderrTruncated
            || Task.isCancelled
        let state: OperationState
        if reconciliation == nil {
            state = .uncertain
        } else if interrupted {
            state = .interrupted
        } else if let exitStatus = processResult.exitStatus {
            if exitStatus == 0 {
                state = reconcilesAsSuccess(reconciliation, plan: plan) ? .succeeded : .uncertain
            } else {
                state = .failed
            }
        } else {
            state = .uncertain
        }

        let cleaned = releaseOperationRoot(plan.root)
        if !cleaned {
            warnings.append("The owned operation scratch root could not be removed safely.")
        }
        await gate.release()
        return HomebrewFormulaUpdateOutcome(
            preview: plan.preview,
            state: state,
            stdout: processResult.stdout,
            stderr: processResult.stderr,
            stdoutTruncated: processResult.stdoutTruncated,
            stderrTruncated: processResult.stderrTruncated,
            exitStatus: processResult.exitStatus,
            processStarted: true,
            reconciliation: reconciliation,
            cleanupWarnings: warnings,
            message: message(for: state, interrupted: interrupted)
        )
    }

    // MARK: - Reconciliation

    /// Success is never inferred from exit zero: the recorded keg must have been replaced by the
    /// observed manager target, fresh ownership must still name the same full identity, and both
    /// observations must have completed.
    private static func reconcilesAsSuccess(
        _ delta: HomebrewFormulaUpdateDelta?,
        plan: HomebrewFormulaUpdatePlan
    ) -> Bool {
        guard let delta, !delta.observationFailed else { return false }
        guard delta.versionMatchesTarget, delta.previousKegReplaced else { return false }
        guard case .verified(let installation)? = delta.ownership else { return false }
        return installation.manager == .homebrewFormula
            && installation.packageName == plan.fullName
            && installation.managerRoot == plan.cellar.canonicalPath
    }

    private static func reconcile(
        plan: HomebrewFormulaUpdatePlan,
        diagnostic after: ToolPathDiagnostic,
        environment: ShellEnvironment
    ) async -> (HomebrewFormulaUpdateDelta?, [String]) {
        let afterSelection = homebrewFormulaSelectionPair(after)
        let (ownership, ownershipWarning) = await reconcileOwnership(
            plan: plan, diagnostic: after, environment: environment
        )

        var afterInstalledKegs: [String] = []
        var observationFailed = false
        switch await HomebrewFormulaObservation.query(
            manager: plan.manager,
            arguments: ["info", "--json=v2", "--formula", plan.fullName],
            environment: environment,
            runner: plan.updateRunner
        ) {
        case .failure:
            observationFailed = true
        case .success(let data):
            if let kegs = HomebrewFormulaObservation.installedKegs(
                fromInfo: data, fullName: plan.fullName, formulaName: plan.formulaName
            ) {
                afterInstalledKegs = kegs
            } else {
                observationFailed = true
            }
        }

        let afterKegVersion = selectedKegVersion(
            afterSelection, cellar: plan.cellar.canonicalPath, formula: plan.formulaName
        )
        if afterSelection != nil, afterKegVersion == nil { observationFailed = true }
        let versionMatchesTarget = afterKegVersion == plan.targetVersion
        let previousKegReplaced = afterKegVersion != nil
            && afterKegVersion != plan.selectedKegVersion
        let previousKegStillPresent = afterInstalledKegs.contains(plan.selectedKegVersion)
        let beforeSelection = homebrewFormulaSelectionPair(plan.diagnostic)

        let delta = HomebrewFormulaUpdateDelta(
            beforeSelectedKegVersion: plan.selectedKegVersion,
            afterSelectedKegVersion: afterKegVersion,
            beforeInstalledKegs: plan.installedKegs,
            afterInstalledKegs: afterInstalledKegs,
            previousKegStillPresent: previousKegStillPresent,
            previousKegReplaced: previousKegReplaced,
            observedTargetVersion: plan.targetVersion,
            versionMatchesTarget: versionMatchesTarget,
            beforeEntryPath: beforeSelection?.entry ?? plan.selectedEntryPath,
            afterEntryPath: afterSelection?.entry,
            beforeTarget: beforeSelection?.target ?? plan.selectedTarget,
            afterTarget: afterSelection?.target,
            beforeAliases: homebrewFormulaAliases(plan.diagnostic),
            afterAliases: homebrewFormulaAliases(after),
            beforeShadowedCount: plan.diagnostic.shadowedInstallationCount ?? 0,
            afterShadowedCount: after.shadowedInstallationCount ?? 0,
            beforeInstallState: plan.diagnostic.detectedTool.state,
            afterInstallState: after.detectedTool.state,
            ownership: ownership,
            observationFailed: observationFailed
        )
        return (delta, ownershipWarning.map { [$0] } ?? [])
    }

    private static func reconcileOwnership(
        plan: HomebrewFormulaUpdatePlan,
        diagnostic: ToolPathDiagnostic,
        environment: ShellEnvironment
    ) async -> (InstallationOwnershipOutcome?, String?) {
        guard homebrewFormulaSelectionPair(diagnostic) != nil else {
            return (.unknown(.notInstalled), nil)
        }
        let observed = await InstallationOwnershipVerifier.verify(
            definition: plan.definition,
            diagnostic: diagnostic,
            environment: environment,
            runner: plan.updateRunner,
            currentDirectory: plan.currentDirectory,
            now: { Date() }
        )
        return (observed.outcome, nil)
    }

    private static func selectedKegVersion(
        _ pair: (entry: String, target: String)?,
        cellar: String,
        formula: String
    ) -> String? {
        guard let pair,
              let keg = try? HomebrewTargetParser.parse(
                selectedTarget: pair.target, cellar: cellar
              ).get(),
              keg.formula == formula
        else { return nil }
        return keg.kegVersion
    }

    // MARK: - Preview/argv helpers

    /// The only dynamic argv element is the manager-returned full identity. The verb and both flags
    /// are literals, so `--force`, `--zap`, `--ignore-dependencies`, `--all`, `--dry-run`,
    /// `--greedy*`, `--overwrite`, `--build-from-source`, `--installed`, a different verb and a
    /// second target are impossible by construction.
    static func updateArguments(fullName: String) -> [String] {
        ["upgrade", "--formula", "--yes", fullName]
    }

    private static func map(
        _ failure: HomebrewFormulaObservationFailure
    ) -> HomebrewFormulaUpdateUnavailableReason {
        switch failure {
        case .noVerifiedSelection: .noVerifiedSelection
        case .managerUnavailable: .managerUnavailable
        case .unsupportedManager: .unsupportedManager
        case .identityUnverified: .identityUnverified
        case .managerPrefixUnverified: .managerPrefixUnverified
        case .pinned: .pinned
        case .metadataInvalid: .metadataInvalid
        case .budgetExhausted: .budgetExhausted
        case .cancelled: .cancelled
        case .probeFailed: .probeFailed
        }
    }

    private static func message(for state: OperationState, interrupted: Bool) -> String? {
        switch state {
        case .succeeded:
            nil
        case .cancelled:
            "The update was cancelled before the process launched; no mutation was reported."
        case .failed:
            "Homebrew exited nonzero; the measured delta is reported without a rollback claim."
        case .interrupted:
            "The Homebrew process was interrupted; reconciliation is reported without a rollback claim."
        case .uncertain:
            interrupted
                ? "The Homebrew process was interrupted and the result could not be confirmed from fresh facts."
                : "The Homebrew process completed, but success could not be proven from fresh facts."
        }
    }

    private static func noProcessOutcome(
        preview: HomebrewFormulaUpdatePreview,
        state: OperationState,
        message: String,
        cleanupOK: Bool
    ) -> HomebrewFormulaUpdateOutcome {
        HomebrewFormulaUpdateOutcome(
            preview: preview,
            state: state,
            stdout: Data(),
            stderr: Data(),
            stdoutTruncated: false,
            stderrTruncated: false,
            exitStatus: nil,
            processStarted: false,
            reconciliation: nil,
            cleanupWarnings: cleanupOK
                ? [] : ["The owned operation scratch root could not be removed safely."],
            message: message
        )
    }
}
