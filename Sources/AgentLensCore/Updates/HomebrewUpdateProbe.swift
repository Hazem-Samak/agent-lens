// HomebrewUpdateProbe — M6 batched Homebrew adapter (brief §"Homebrew batch contract").
//
// At most three manager commands per uncached batch, regardless of tool count:
//   1. <brew> --cellar
//   2. <brew> info --json=v2 --formula <deduplicated formula names>
//   3. <brew> outdated --json=v2 --formula
// Zero eligible formulae execute zero commands. Process failures are typed results,
// never empty metadata. Parsing fails closed at the envelope and isolates bad records.

import Foundation

enum HomebrewUpdateProbeTestHooks {
    @TaskLocal static var onAdmissionQueued: (@Sendable () -> Void)?

    static func observingAdmissionQueue<T: Sendable>(
        _ observer: @escaping @Sendable () -> Void,
        operation: @Sendable () async -> T
    ) async -> T {
        await $onAdmissionQueued.withValue(observer) {
            await operation()
        }
    }
}

/// Process-wide admission for manager batches. The occupied bit remains set while the
/// admitted operation awaits, so actor reentrancy cannot admit a second batch.
private actor HomebrewBatchAdmissionGate {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }

    private var occupied = false
    private var waiters: [Waiter] = []

    func withPermit<T: Sendable>(_ operation: @Sendable () async -> T) async -> T? {
        let id = UUID()
        guard await acquire(id) else { return nil }
        guard !Task.isCancelled else {
            release()
            return nil
        }

        let result = await operation()
        release()
        return result
    }

    private func acquire(_ id: UUID) async -> Bool {
        guard !Task.isCancelled else { return false }
        if !occupied && waiters.isEmpty {
            occupied = true
            return true
        }

        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                guard !Task.isCancelled else {
                    continuation.resume(returning: false)
                    return
                }
                waiters.append(Waiter(id: id, continuation: continuation))
                HomebrewUpdateProbeTestHooks.onAdmissionQueued?()
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(returning: false)
    }

    private func release() {
        guard !waiters.isEmpty else {
            occupied = false
            return
        }
        let next = waiters.removeFirst()
        occupied = true
        next.continuation.resume(returning: true)
    }
}

/// Why a manager process did not produce usable output. Opaque failures stay `nonzeroExit`
/// or `spawnFailure`; `networkUnavailable`/`rateLimited` require typed evidence from an adapter.
public enum CommandFailure: Error, Equatable, Sendable {
    case spawnFailure
    case nonzeroExit
    case timedOut
    case outputLimitExceeded
    case invalidOutput
    case networkUnavailable
    case rateLimited
    /// The caller cancelled before this query started. Never reported as successful metadata.
    case cancelled
}

public typealias CommandOutcome = Result<Data, CommandFailure>

/// Injectable process seam. Production wraps `BoundedProcessRunner`; tests script results.
public protocol UpdateCommandRunner: Sendable {
    func run(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval
    ) async -> CommandOutcome
}

public struct HomebrewFormulaRecord: Equatable, Sendable {
    public let name: String
    public let fullName: String
    public let stable: String
    public let revision: Int
    public let installedVersions: [String]
    /// False when the source record was malformed or self-contradictory. An invalid record keeps
    /// only its identity claims (`name` and the raw `full_name`): every metadata field is a
    /// placeholder that must never be compared or lent to a neighbour. Its purpose is to make its
    /// own tool unknown *and* to keep a borrowed full name visible, so ambiguous matching is
    /// poisoned instead of silently accepted.
    public let isValid: Bool

    public init(
        name: String,
        fullName: String = "",
        stable: String = "",
        revision: Int = 0,
        installedVersions: [String] = [],
        isValid: Bool = true
    ) {
        self.name = name
        self.fullName = fullName
        self.stable = stable
        self.revision = revision
        self.installedVersions = installedVersions
        self.isValid = isValid
    }

    /// The latest package version as Homebrew names it: `stable` or `stable_revision`.
    public var packageVersion: String {
        revision > 0 ? "\(stable)_\(revision)" : stable
    }
}

public struct HomebrewOutdatedRecord: Equatable, Sendable {
    public let name: String
    public let currentVersion: String
    public let installedVersions: [String]
    /// False when the source record was malformed. See `HomebrewFormulaRecord.isValid`:
    /// an invalid marker makes only its own tool unknown and is never compared.
    public let isValid: Bool

    public init(
        name: String,
        currentVersion: String = "",
        installedVersions: [String] = [],
        isValid: Bool = true
    ) {
        self.name = name
        self.currentVersion = currentVersion
        self.installedVersions = installedVersions
        self.isValid = isValid
    }
}

public struct HomebrewBatchResult: Equatable, Sendable {
    public let cellar: String?
    public let formulas: [String: [HomebrewFormulaRecord]]
    public let outdated: [String: [HomebrewOutdatedRecord]]
    public let queryCount: Int

    public init(
        cellar: String?,
        formulas: [String: [HomebrewFormulaRecord]],
        outdated: [String: [HomebrewOutdatedRecord]],
        queryCount: Int
    ) {
        self.cellar = cellar
        self.formulas = formulas
        self.outdated = outdated
        self.queryCount = queryCount
    }
}

public enum HomebrewBatchError: Error, Equatable, Sendable {
    case invalidFormulaName
    case commandFailed(CommandFailure)
    case invalidOutput
}

public enum HomebrewUpdateProbe {

    private static let batchAdmission = HomebrewBatchAdmissionGate()

    private enum BatchFormulaSelection {
        case explicit([String])
        case selectedTargets([String])
    }

    /// Per-process wall-clock deadline (brief: ten seconds).
    public static let queryTimeout: TimeInterval = 10

    /// Homebrew formula-name grammar for this adapter. Anything else never reaches a process.
    static func isValidFormulaName(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first else { return false }
        func isAlphaNumeric(_ scalar: Unicode.Scalar) -> Bool {
            (scalar.value >= 0x30 && scalar.value <= 0x39)
                || (scalar.value >= 0x41 && scalar.value <= 0x5A)
                || (scalar.value >= 0x61 && scalar.value <= 0x7A)
        }
        guard isAlphaNumeric(first) else { return false }
        return name.unicodeScalars.allSatisfy { isAlphaNumeric($0) || "+._@-".unicodeScalars.contains($0) }
    }

    // MARK: JSON (typed; extra fields tolerated)

    /// Parses `info --json=v2`. The envelope must be an object whose `formulae` value is an
    /// array of objects. A record carrying a usable name but failing validation is kept as an
    /// invalid marker, so it makes exactly its own tool unknown instead of being erased into an
    /// apparent absence of data. A record with no name, or an array element that is not an
    /// object, cannot be attributed to any tool and fails the whole batch rather than being
    /// assigned to a neighbour.
    public static func parseInfo(_ data: Data) -> [HomebrewFormulaRecord]? {
        guard let formulae = jsonFormulaRecords(data) else { return nil }
        var parsed: [HomebrewFormulaRecord] = []
        parsed.reserveCapacity(formulae.count)
        for record in formulae {
            guard let name = record["name"] as? String else { return nil }
            guard let fullName = record["full_name"] as? String,
                  let versions = record["versions"] as? [String: Any],
                  let stable = versions["stable"] as? String,
                  isSupportedUpstreamVersion(stable),
                  let revision = strictNonnegativeInt(record["revision"]),
                  let installed = installedVersionList(record["installed"]),
                  formulaIdentityConsistent(name: name, fullName: fullName)
            else {
                // The raw identity claims survive even when the rest of the record is unusable, so a
                // borrowed full name cannot vanish into an apparent absence of data.
                parsed.append(HomebrewFormulaRecord(
                    name: name,
                    fullName: record["full_name"] as? String ?? "",
                    isValid: false
                ))
                continue
            }
            parsed.append(HomebrewFormulaRecord(
                name: name,
                fullName: fullName,
                stable: stable,
                revision: revision,
                installedVersions: installed
            ))
        }
        return parsed
    }

    /// Parses `outdated --json=v2`. Same envelope and isolation rules as `parseInfo`; cask data
    /// is tolerated but never consumed. Homebrew labels these records by full name, so the
    /// record's `name` is retained verbatim for full-identity association.
    public static func parseOutdated(_ data: Data) -> [HomebrewOutdatedRecord]? {
        guard let formulae = jsonFormulaRecords(data) else { return nil }
        var parsed: [HomebrewOutdatedRecord] = []
        parsed.reserveCapacity(formulae.count)
        for record in formulae {
            guard let name = record["name"] as? String else { return nil }
            guard let current = record["current_version"] as? String,
                  let installed = stringList(record["installed_versions"])
            else {
                parsed.append(HomebrewOutdatedRecord(name: name, isValid: false))
                continue
            }
            parsed.append(HomebrewOutdatedRecord(
                name: name,
                currentVersion: current,
                installedVersions: installed
            ))
        }
        return parsed
    }

    /// Validates the transport encoding and the v2 envelope shape, then returns the `formulae`
    /// array's object elements. Unknown member fields are tolerated at every level.
    private static func jsonFormulaRecords(_ data: Data) -> [[String: Any]]? {
        guard let text = strictUTF8Text(data) else { return nil }
        // Decoding proceeds from the validated UTF-8 re-encoding, never from the original bytes, so
        // `JSONSerialization`'s encoding auto-detection cannot reinterpret a non-UTF8 transcript.
        let validatedUTF8 = Data(text.utf8)
        guard let json = try? JSONSerialization.jsonObject(with: validatedUTF8, options: []),
              let root = json as? [String: Any],
              let formulae = root["formulae"] as? [Any]
        else { return nil }
        var records: [[String: Any]] = []
        records.reserveCapacity(formulae.count)
        for element in formulae {
            guard let record = element as? [String: Any] else { return nil }
            records.append(record)
        }
        return records
    }

    /// Homebrew emits UTF-8. Reject a leading BOM, any NUL byte, and any byte sequence that is not
    /// valid UTF-8, then hand the decoded text back as UTF-8 for the parser to consume.
    ///
    /// The NUL rejection is load-bearing: a BOM-free UTF-16LE/BE or UTF-32LE/BE ASCII JSON
    /// transcript is full of NUL bytes, and NUL is itself a perfectly valid UTF-8 byte, so a
    /// `String(data:encoding:.utf8) != nil` gate alone accepts those transcripts. Passing the
    /// original `Data` to `JSONSerialization` would then let its encoding auto-detection
    /// reinterpret the bytes as UTF-16/32 and turn undecodable output into metadata. Re-encoding
    /// the validated text guarantees the parser only ever sees UTF-8.
    private static func strictUTF8Text(_ data: Data) -> String? {
        let byteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]
        if data.count >= 3, Array(data.prefix(3)) == byteOrderMark { return nil }
        if data.contains(0x00) { return nil }
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        // Belt and braces: only bytes that survive a UTF-8 round trip reach the parser.
        guard Data(text.utf8) == data else { return nil }
        return text
    }

    /// Strict nonnegative integer extraction. `JSONSerialization` boxes JSON booleans as
    /// `__NSCFBoolean` (whose `int64Value` is 0 or 1) and boxes fractional or out-of-range
    /// numbers as floating-point values (whose `int64Value` silently truncates). Both are
    /// rejected here, so a `revision` of `false`, `true`, `1.5`, `42.0`, `-1` or `1e30` is
    /// malformed data instead of 0, 1, or arithmetic garbage.
    private static func strictNonnegativeInt(_ value: Any?) -> Int? {
        guard let value else { return nil }
        guard CFGetTypeID(value as CFTypeRef) != CFBooleanGetTypeID() else { return nil }
        guard let number = value as? NSNumber else { return nil }
        switch String(cString: number.objCType) {
        case "s", "i", "q", "l":
            break
        default:
            return nil
        }
        let widened = number.int64Value
        guard widened >= 0, widened <= Int64(Int.max) else { return nil }
        return Int(widened)
    }

    /// The `installed` array's per-keg version strings; every element must be an object carrying
    /// a string `version`, so a partially readable collection is malformed rather than shortened.
    private static func installedVersionList(_ value: Any?) -> [String]? {
        guard let entries = value as? [Any] else { return nil }
        let versions = entries.compactMap { ($0 as? [String: Any])?["version"] as? String }
        guard versions.count == entries.count else { return nil }
        return versions
    }

    /// A JSON array whose every element is a string; mixed or non-array data is malformed.
    private static func stringList(_ value: Any?) -> [String]? {
        guard let entries = value as? [Any] else { return nil }
        let strings = entries.compactMap { $0 as? String }
        guard strings.count == entries.count else { return nil }
        return strings
    }

    /// Homebrew's `full_name` is either the bare formula name or `owner/tap/name`, whose last
    /// component is exactly `name`. A mismatched stem, an empty or over-long path, or an invalid
    /// token contradicts the record's identity: such a record must never be compared and must
    /// never lend its name to an outdated entry. Ownership is never derived from an executable
    /// basename or a fixture label — only from these two fields agreeing.
    static func formulaIdentityConsistent(name: String, fullName: String) -> Bool {
        guard isValidFormulaName(name) else { return false }
        if fullName == name { return true }
        let parts = fullName.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts[2] == name else { return false }
        return parts.allSatisfy(isValidFormulaName)
    }

    /// Formula `versions.stable` is upstream text only; the manager's separate `revision`
    /// field is the sole source of a package revision suffix.
    static func isSupportedUpstreamVersion(_ text: String) -> Bool {
        guard let parsed = VersionComparison.parseHomebrewStable(text) else { return false }
        return parsed.revision == 0 && parsed.upstreamText == text
    }

    // MARK: Batch

    /// Runs the bounded batch. `formulas` are selected eligible formula names; duplicates are
    /// removed while keeping order. Invalid names fail before any process is constructed.
    public static func runBatch(
        manager: HomebrewManager,
        formulas: [String],
        environment: ShellEnvironment,
        runner: UpdateCommandRunner
    ) async -> Result<HomebrewBatchResult, HomebrewBatchError> {
        guard let result = await withBatchAdmission({
            await runBatchWhileAdmitted(
                manager: manager,
                formulas: formulas,
                environment: environment,
                runner: runner
            )
        }) else {
            return .failure(.commandFailed(.cancelled))
        }
        return result
    }

    /// Shared with the coordinator so selection and manager identity can be revalidated
    /// immediately after queue admission and before the first manager process starts.
    static func withBatchAdmission<T: Sendable>(
        _ operation: @Sendable () async -> T
    ) async -> T? {
        await batchAdmission.withPermit(operation)
    }

    /// Executes the existing sequential three-query protocol while the caller owns admission.
    static func runBatchWhileAdmitted(
        manager: HomebrewManager,
        formulas: [String],
        environment: ShellEnvironment,
        runner: UpdateCommandRunner
    ) async -> Result<HomebrewBatchResult, HomebrewBatchError> {
        await runBatchWhileAdmitted(
            manager: manager,
            selection: .explicit(formulas),
            environment: environment,
            runner: runner
        )
    }

    /// Resolves formula operands only after the manager has reported its Cellar. This avoids
    /// guessing from an arbitrary `Cellar` path component while keeping the public explicit-
    /// formula batch API unchanged.
    static func runSelectedTargetsBatchWhileAdmitted(
        manager: HomebrewManager,
        selectedTargets: [String],
        environment: ShellEnvironment,
        runner: UpdateCommandRunner
    ) async -> Result<HomebrewBatchResult, HomebrewBatchError> {
        await runBatchWhileAdmitted(
            manager: manager,
            selection: .selectedTargets(selectedTargets),
            environment: environment,
            runner: runner
        )
    }

    private static func runBatchWhileAdmitted(
        manager: HomebrewManager,
        selection: BatchFormulaSelection,
        environment: ShellEnvironment,
        runner: UpdateCommandRunner
    ) async -> Result<HomebrewBatchResult, HomebrewBatchError> {
        var unique: [String]
        switch selection {
        case .explicit(let formulas):
            unique = []
            for name in formulas where !unique.contains(name) {
                guard isValidFormulaName(name) else { return .failure(.invalidFormulaName) }
                unique.append(name)
            }
            guard !unique.isEmpty else {
                return .success(HomebrewBatchResult(cellar: nil, formulas: [:], outdated: [:], queryCount: 0))
            }
        case .selectedTargets(let targets):
            guard !targets.isEmpty else {
                return .success(HomebrewBatchResult(cellar: nil, formulas: [:], outdated: [:], queryCount: 0))
            }
            unique = []
        }

        let processEnvironment = diagnosticEnvironment(from: environment)
        var queryCount = 0

        func query(_ arguments: [String]) async -> Result<Data, HomebrewBatchError> {
            // Cancellation is observed before each process starts, never after success is claimed.
            if Task.isCancelled { return .failure(.commandFailed(.cancelled)) }
            queryCount += 1
            let outcome = await runner.run(
                executablePath: manager.entryPath,
                arguments: arguments,
                environment: processEnvironment,
                timeout: queryTimeout
            )
            // A running child is allowed to finish its bounded cleanup, but its late success
            // cannot authorize a later query or become reusable metadata after cancellation.
            guard !Task.isCancelled else { return .failure(.commandFailed(.cancelled)) }
            switch outcome {
            case .success(let data): return .success(data)
            case .failure(let failure): return .failure(.commandFailed(failure))
            }
        }

        // 1. Cellar — the manager's own identity for selected-target ownership.
        let cellarData: Data
        switch await query(["--cellar"]) {
        case .failure(let error): return .failure(error)
        case .success(let data): cellarData = data
        }
        guard let cellarText = String(data: cellarData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              cellarText.hasPrefix("/")
        else {
            return .failure(.invalidOutput)
        }

        if case .selectedTargets(let targets) = selection {
            unique = Set(targets.compactMap { target in
                guard case .success(let keg) = HomebrewTargetParser.parse(
                    selectedTarget: target,
                    cellar: cellarText
                ) else { return nil }
                return keg.formula
            }).sorted()
            guard unique.allSatisfy(isValidFormulaName) else { return .failure(.invalidFormulaName) }
            guard !unique.isEmpty else {
                return .success(HomebrewBatchResult(
                    cellar: cellarText, formulas: [:], outdated: [:], queryCount: queryCount
                ))
            }
        }

        // 2. Metadata for selected formulae only.
        let infoData: Data
        switch await query(["info", "--json=v2", "--formula"] + unique) {
        case .failure(let error): return .failure(error)
        case .success(let data): infoData = data
        }
        guard let infoRecords = parseInfo(infoData) else { return .failure(.invalidOutput) }

        // 3. Outdated list; absence is not proof of currency and is cross-checked later.
        let outdatedData: Data
        switch await query(["outdated", "--json=v2", "--formula"]) {
        case .failure(let error): return .failure(error)
        case .success(let data): outdatedData = data
        }
        guard let outdatedRecords = parseOutdated(outdatedData) else { return .failure(.invalidOutput) }
        guard !Task.isCancelled else { return .failure(.commandFailed(.cancelled)) }

        return .success(HomebrewBatchResult(
            cellar: cellarText,
            formulas: Dictionary(grouping: infoRecords, by: \.name),
            outdated: Dictionary(grouping: outdatedRecords, by: \.name),
            queryCount: queryCount
        ))
    }

    /// The original environment plus the two diagnostic toggles. The caller's value is untouched.
    static func diagnosticEnvironment(from environment: ShellEnvironment) -> [String: String] {
        var values = environment.raw
        values["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        values["HOMEBREW_NO_ANALYTICS"] = "1"
        return values
    }
}

/// Derives a tri-state status for one selected installation from a verified batch.
public enum HomebrewStatusResolver {

    public static func status(
        selectedTarget: String,
        localVersion: String,
        batch: HomebrewBatchResult
    ) -> VersionStatus {
        let installed = Version(localVersion)
        guard let cellar = batch.cellar else {
            return .unknown(installed: installed, reason: .managerUnavailable)
        }

        // Ownership: the selected keg must sit in this manager's Cellar.
        let keg: SelectedKeg
        switch HomebrewTargetParser.parse(selectedTarget: selectedTarget, cellar: cellar) {
        case .failure(.managerMismatch):
            return .unknown(installed: installed, reason: .managerMismatch)
        case .failure(.unverified):
            return .unknown(installed: installed, reason: .identityUnverified)
        case .success(let verified):
            keg = verified
        }

        // Both sides must be supported Homebrew stable versions. The local CLI text keeps its
        // original spelling; agreement is decided by the shared upstream grammar rather than by
        // raw-text equality, so `1.2` and `1.2.0` are the same upstream under the Homebrew
        // policy while the keg's revision stays a separate package component.
        guard let localPackage = VersionComparison.parseHomebrewStable(localVersion),
              let kegPackage = VersionComparison.parseHomebrewStable(keg.kegVersion)
        else {
            return .unknown(installed: installed, reason: .unsupportedVersion)
        }

        // The selected keg's upstream must agree with the CLI-reported version. Comparing the
        // two upstream texts (revision suffixes stripped) keeps the revision out of the
        // identity check.
        guard VersionComparison.ordering(
            localPackage.upstreamText, kegPackage.upstreamText, scheme: .homebrewStable
        ) == .equal else {
            return .unknown(installed: installed, reason: .identityUnverified)
        }

        // The formula record must be unique, valid, and must list the selected keg as installed.
        // An invalid marker or a duplicated stem is ambiguity, never a silent omission.
        //
        // `isValid` is not trusted here: a record can be constructed directly or restored from a
        // cache with `isValid` defaulting to true, so the name/full-name agreement is re-derived
        // from the two identity fields on every resolution. A disagreeing stem contradicts the
        // record's own ownership claim and is never compared.
        guard let records = batch.formulas[keg.formula], records.count == 1,
              let record = records.first, record.isValid,
              record.name == keg.formula,
              HomebrewUpdateProbe.formulaIdentityConsistent(name: record.name, fullName: record.fullName),
              record.installedVersions.contains(keg.kegVersion)
        else {
            return .unknown(installed: installed, reason: .identityUnverified)
        }

        // Publicly constructed records can bypass parseInfo's validation. Do not interpret a
        // revision-looking suffix in `stable` as upstream text or compose it with `revision`.
        guard record.revision >= 0,
              HomebrewUpdateProbe.isSupportedUpstreamVersion(record.stable)
        else {
            return .unknown(installed: installed, reason: .unsupportedVersion)
        }

        // No other record may claim this full name under a different stem: an ambiguous alias
        // cannot be attributed to the selected keg. Invalid markers are scanned too — they keep
        // their raw full name precisely so a borrowed identity poisons this match instead of
        // disappearing into an apparent absence of data. Their metadata is never read.
        let aliasConflict = batch.formulas.values.contains { siblings in
            siblings.contains { $0.fullName == record.fullName && $0.name != record.name }
        }
        guard !aliasConflict else {
            return .unknown(installed: installed, reason: .identityUnverified)
        }

        // Compare the selected package revision against the candidate latest package, not the
        // bare CLI banner text.
        let latest = record.packageVersion
        guard let comparison = VersionComparison.ordering(keg.kegVersion, latest, scheme: .homebrewStable)
        else {
            return .unknown(installed: installed, reason: .unsupportedVersion)
        }

        // Cross-check the outdated records associated by the verified full name. A bare-name
        // record for a tapped formula is a conflicting alias, so it is collected too rather
        // than silently ignored. Homebrew lists only the *outdated* installed kegs, so the
        // selected keg's absence from that list is expected; its presence while equal to the
        // latest package is a contradiction.
        // Only a record keyed by the verified full identity confirms anything. For a tapped formula
        // the bare stem is a *different* tap's key, so collecting it as support would launder a
        // foreign identity claim into a verified update; it is gathered separately and rejected.
        let aliasCandidates: [HomebrewOutdatedRecord]
        if keg.formula != record.fullName {
            aliasCandidates = batch.outdated[keg.formula] ?? []
        } else {
            aliasCandidates = []
        }
        guard aliasCandidates.isEmpty else {
            return .unknown(installed: installed, reason: .identityUnverified)
        }

        let outdatedCandidates = batch.outdated[record.fullName] ?? []
        if !outdatedCandidates.isEmpty {
            guard outdatedCandidates.count == 1,
                  let outdated = outdatedCandidates.first,
                  outdated.isValid,
                  outdated.currentVersion == latest,
                  outdatedInstalledAgree(outdated: outdated, record: record, latest: latest),
                  !(comparison == .equal && outdated.installedVersions.contains(keg.kegVersion))
            else {
                return .unknown(installed: installed, reason: .identityUnverified)
            }
        }

        switch comparison {
        case .equal:
            return .upToDate(installed: installed, latest: Version(latest))
        case .older:
            return .updateAvailable(installed: installed, latest: Version(latest))
        case .newer:
            return .unknown(installed: installed, reason: .newerThanKnownMetadata)
        }
    }

    /// Cross-checks an outdated record's installed-keg claims against the verified inventory that
    /// `info` reported for the same formula.
    ///
    /// Homebrew lists only the *outdated* kegs, so the selected keg's absence from that list is
    /// expected; membership of the selected keg is deliberately NOT required — demanding it would
    /// recreate the unselected-old-keg false negative. What is required is that every keg the
    /// outdated record names is one this manager actually reports as installed, and that each is a
    /// supported version strictly older than the latest package. A claim naming a keg nobody has
    /// installed (`9.9.9`) or naming the latest package itself contradicts the verified inventory,
    /// so the identity is poisoned rather than trusted.
    private static func outdatedInstalledAgree(
        outdated: HomebrewOutdatedRecord,
        record: HomebrewFormulaRecord,
        latest: String
    ) -> Bool {
        for claimed in outdated.installedVersions {
            guard record.installedVersions.contains(claimed) else { return false }
            guard VersionComparison.ordering(claimed, latest, scheme: .homebrewStable) == .older
            else { return false }
        }
        return true
    }
}
