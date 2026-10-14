// UpdateProbeCoordinator — M6 eligibility, mode policy, cache use, and association (brief §"Model and comparison contract").
//
// Results are keyed by the registry-derived tool ID and computed in input order, never by
// completion order. Eligibility is applied in the brief's fixed order so reasons are stable.
// Only one manager batch runs at a time. Cancellation is checked between steps and
// before any cache publication; a cancelled run never reports successful empty metadata.
//
// Association is explicit: every subject carries its registry ID and display name beside the
// M5 diagnostic, and every result carries the selected entry plus its observed canonical target
// so the selection can be re-verified immediately before a verified status is published or
// persisted. A moved, removed, or directory-replaced selection is `identityUnverified` neutral
// text — never a stale verified claim, and never a cache write.

import Darwin
import Foundation

public enum UpdateProbeMode: Equatable, Sendable {
    /// Plain scan: no cache read/write and no manager query.
    case localOnly
    /// `--check-updates`: a valid cache hit is used; otherwise one bounded probe.
    case checkUpdates
    /// `--refresh-updates`: ignore cache reads, probe, and replace cache on success.
    case refresh
    /// `--offline`: no cache reads and no manager query.
    case offline
}

public enum UpdateProvenance: Equatable, Sendable {
    case none
    case freshProbe(observedAt: Date)
    case cache(observedAt: Date)
}

/// One scan subject: the registry identity carried beside the M5 diagnostic. The registry ID is
/// the association key — never the display name and never the executable basename — so a display
/// rename cannot detach a result from its identity, and two tools sharing a display name stay
/// distinguishable.
public struct UpdateProbeSubject: Equatable, Sendable {
    public let registryID: String
    public let displayName: String
    public let diagnostic: ToolPathDiagnostic

    public init(registryID: String, displayName: String, diagnostic: ToolPathDiagnostic) {
        self.registryID = registryID
        self.displayName = displayName
        self.diagnostic = diagnostic
    }
}

public struct ToolUpdateResult: Equatable, Sendable {
    /// The stable registry identity this result belongs to.
    public let registryID: String
    /// The user-visible label, kept separate from the identity.
    public let displayName: String
    /// Position in the input subjects array and the original, immutable M5 diagnostic.
    public let diagnosticIndex: Int
    public let diagnostic: ToolPathDiagnostic
    /// Original local version text, kept independently of the tri-state comparison.
    public let localVersion: String?
    /// The selected entry as observed at scan time (a PATH slot entry or an off-PATH candidate).
    public let selectedEntryPath: String?
    /// The canonical keg target the selected entry resolved to at scan time.
    public let selectedTarget: String?
    /// Selected Homebrew keg version when the verified Cellar decomposition is available.
    public let selectedKegVersion: String?
    /// Captured manager executable identity, available when a manager was resolved.
    public let managerEntryPath: String?
    /// The verified manager canonical target, when a manager was resolved and identity held.
    public let managerTarget: String?
    public let managerFingerprint: String?
    /// The Cellar returned by the manager or retained in verified cached metadata.
    public let managerCellar: String?
    /// Formula stem and full manager-reported identity are distinct (e.g. `codex` versus
    /// `owner/tap/codex`). Neither is synthesized from the other.
    public let formulaStem: String?
    /// The manager's verified full formula identity (`name` or `owner/tap/name`), when available.
    public let fullFormulaName: String?
    public let status: VersionStatus
    public let provenance: UpdateProvenance

    public init(
        registryID: String,
        displayName: String,
        diagnosticIndex: Int,
        diagnostic: ToolPathDiagnostic,
        localVersion: String?,
        selectedEntryPath: String?,
        selectedTarget: String?,
        selectedKegVersion: String?,
        managerEntryPath: String?,
        managerTarget: String?,
        managerFingerprint: String?,
        managerCellar: String?,
        formulaStem: String?,
        fullFormulaName: String?,
        status: VersionStatus,
        provenance: UpdateProvenance
    ) {
        self.registryID = registryID
        self.displayName = displayName
        self.diagnosticIndex = diagnosticIndex
        self.diagnostic = diagnostic
        self.localVersion = localVersion
        self.selectedEntryPath = selectedEntryPath
        self.selectedTarget = selectedTarget
        self.selectedKegVersion = selectedKegVersion
        self.managerEntryPath = managerEntryPath
        self.managerTarget = managerTarget
        self.managerFingerprint = managerFingerprint
        self.managerCellar = managerCellar
        self.formulaStem = formulaStem
        self.fullFormulaName = fullFormulaName
        self.status = status
        self.provenance = provenance
    }
}

public enum UpdateProbeCoordinator {

    /// One eligible selected installation awaiting a manager answer. Carries the ACTUAL entry
    /// and its observed canonical target, not just the target, so the selection can be rechecked.
    private struct Pending {
        let index: Int
        let subject: UpdateProbeSubject
        let selectedEntryPath: String
        let observedTarget: String
        let localVersion: String

        var registryID: String { subject.registryID }
        var displayName: String { subject.displayName }
    }

    /// The manager identity captured once at resolution. Every later revalidation compares against
    /// this snapshot, so a manager replaced mid-run cannot be tagged with old observations.
    private struct ManagerIdentity {
        let manager: HomebrewManager
        let fingerprint: String
    }

    private enum AdmittedBatchOutcome: Sendable {
        case cancelled
        case identityChanged
        case completed(Result<HomebrewBatchResult, HomebrewBatchError>)
    }

    public static func run(
        subjects: [UpdateProbeSubject],
        environment: ShellEnvironment,
        mode: UpdateProbeMode,
        runner: UpdateCommandRunner,
        cacheURL: URL,
        currentDirectory: String = FileManager.default.currentDirectoryPath,
        now: @escaping @Sendable () -> Date
    ) async -> [ToolUpdateResult] {
        var results = [ToolUpdateResult?](repeating: nil, count: subjects.count)
        var pending: [Pending] = []

        // Eligibility, in the brief's fixed order, decided without any process.
        for (index, subject) in subjects.enumerated() {
            let tool = subject.diagnostic.detectedTool
            let localVersion = tool.version.map(Version.init)

            if tool.state == .notInstalled {
                results[index] = neutral(subject, index, .notInstalled, installed: nil)
                continue
            }
            if case .inconsistent = subject.diagnostic.selection {
                results[index] = neutral(subject, index, .diagnosticInconsistent, installed: localVersion)
                continue
            }
            guard tool.source == "brew" else {
                let reason: UnknownReason = tool.source == "standalone" ? .noRegistry : .unsupportedSource
                results[index] = neutral(subject, index, reason, installed: localVersion)
                continue
            }
            guard let version = tool.version,
                  let selection = selectedPair(subject.diagnostic)
            else {
                results[index] = neutral(subject, index, .installedVersionUnavailable, installed: nil)
                continue
            }
            switch mode {
            case .localOnly:
                results[index] = neutral(subject, index, .notChecked, installed: localVersion)
            case .offline:
                results[index] = neutral(subject, index, .networkUnavailable, installed: localVersion)
            case .checkUpdates, .refresh:
                pending.append(Pending(
                    index: index,
                    subject: subject,
                    selectedEntryPath: selection.entryPath,
                    observedTarget: selection.target,
                    localVersion: version
                ))
            }
        }

        // Zero eligible tools means zero manager commands and zero cache reads.
        if !pending.isEmpty {
            guard let manager = HomebrewManagerResolver.resolve(
                environment: environment,
                currentDirectory: currentDirectory
            ) else {
                for entry in pending {
                    results[entry.index] = neutral(pending: entry, .managerUnavailable, installed: Version(entry.localVersion))
                }
                return finalize(results, subjects)
            }
            let identity = ManagerIdentity(manager: manager, fingerprint: fingerprint(of: manager))
            await resolveBatch(
                pending: pending,
                managerIdentity: identity,
                environment: environment,
                runner: runner,
                cache: UpdateMetadataCache(fileURL: cacheURL, now: now),
                mode: mode,
                currentDirectory: currentDirectory,
                now: now,
                results: &results
            )
        }
        return finalize(results, subjects)
    }

    // MARK: Batch resolution

    private static func resolveBatch(
        pending: [Pending],
        managerIdentity: ManagerIdentity,
        environment: ShellEnvironment,
        runner: UpdateCommandRunner,
        cache: UpdateMetadataCache,
        mode: UpdateProbeMode,
        currentDirectory: String,
        now: @escaping @Sendable () -> Date,
        results: inout [ToolUpdateResult?]
    ) async {
        let manager = managerIdentity.manager
        let context = contextFingerprint(environment: environment, currentDirectory: currentDirectory)
        // The manager-reported Cellar is unavailable until a fresh batch. A cache hit therefore
        // restores one uniquely matching, complete stored identity for the verified selection.

        if mode == .checkUpdates {
            // Cache-first: a fully valid hit for every pending tool avoids the manager entirely.
            var hits: [Int: UpdateMetadataEntry] = [:]
            for entry in pending {
                let selection = UpdateMetadataSelection(
                    registryID: entry.registryID,
                    managerEntryPath: manager.entryPath,
                    managerTarget: manager.canonicalTarget,
                    managerFingerprint: managerIdentity.fingerprint,
                    selectedEntryPath: entry.selectedEntryPath,
                    selectedTarget: entry.observedTarget,
                    contextFingerprint: context
                )
                guard let cached = cache.lookup(selection) else { break }
                hits[entry.index] = cached
            }
            if hits.count == pending.count {
                for entry in pending {
                    guard let cached = hits[entry.index] else { continue }
                    guard !Task.isCancelled,
                          managerIsLive(managerIdentity),
                          selectionIsLive(entry)
                    else {
                        let reason: UnknownReason = Task.isCancelled ? .probeFailed : .identityUnverified
                        results[entry.index] = neutral(pending: entry, reason, installed: Version(entry.localVersion))
                        continue
                    }
                    let result = cachedResult(entry: entry, cached: cached)
                    // Recheck immediately before each verified cache result is published.
                    guard managerIsLive(managerIdentity), selectionIsLive(entry) else {
                        results[entry.index] = neutral(pending: entry, .identityUnverified, installed: Version(entry.localVersion))
                        continue
                    }
                    results[entry.index] = result
                }
                return
            }
        }

        // Formula operands are derived relative to the manager-reported Cellar by the batch seam.
        let admission = await HomebrewUpdateProbe.withBatchAdmission {
            guard !Task.isCancelled else { return AdmittedBatchOutcome.cancelled }
            // Waiting for another scan must not turn a replaced manager or selected entry into
            // authority to launch a process. Existing post-query checks remain in force too.
            guard managerIsLive(managerIdentity), pending.allSatisfy(selectionIsLive) else {
                return AdmittedBatchOutcome.identityChanged
            }
            return .completed(await HomebrewUpdateProbe.runSelectedTargetsBatchWhileAdmitted(
                manager: manager,
                selectedTargets: pending.map(\.observedTarget),
                environment: environment,
                runner: runner
            ))
        }
        guard let admission else {
            for entry in pending {
                results[entry.index] = neutral(pending: entry, .probeFailed, installed: Version(entry.localVersion))
            }
            return
        }
        let outcome: Result<HomebrewBatchResult, HomebrewBatchError>
        switch admission {
        case .cancelled:
            for entry in pending {
                results[entry.index] = neutral(pending: entry, .probeFailed, installed: Version(entry.localVersion))
            }
            return
        case .identityChanged:
            for entry in pending {
                results[entry.index] = neutral(pending: entry, .identityUnverified, installed: Version(entry.localVersion))
            }
            return
        case .completed(let result):
            outcome = result
        }
        let batch: HomebrewBatchResult
        switch outcome {
        case .failure(let error):
            let reason = unknownReason(for: error)
            for entry in pending {
                results[entry.index] = neutral(pending: entry, reason, installed: Version(entry.localVersion))
            }
            return
        case .success(let value):
            batch = value
        }

        guard !Task.isCancelled else {
            for entry in pending {
                results[entry.index] = neutral(pending: entry, .probeFailed, installed: Version(entry.localVersion))
            }
            return
        }
        let observed = now()
        let verifiedCellar = batch.cellar.map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL.path }
        var toPersist: [Int: UpdateMetadataEntry] = [:]
        for entry in pending {
            guard managerIsLive(managerIdentity), selectionIsLive(entry) else {
                results[entry.index] = neutral(pending: entry, .identityUnverified, installed: Version(entry.localVersion))
                continue
            }
            let status = HomebrewStatusResolver.status(
                selectedTarget: entry.observedTarget,
                localVersion: entry.localVersion,
                batch: batch
            )
            let record = verifiedRecord(for: entry, batch: batch)
            let selectedKeg = verifiedCellar.flatMap { cellar in
                try? HomebrewTargetParser.parse(selectedTarget: entry.observedTarget, cellar: cellar).get()
            }
            // Recheck after comparison and immediately before publishing this fresh result.
            guard managerIsLive(managerIdentity), selectionIsLive(entry) else {
                results[entry.index] = neutral(pending: entry, .identityUnverified, installed: Version(entry.localVersion))
                continue
            }
            results[entry.index] = ToolUpdateResult(
                registryID: entry.registryID,
                displayName: entry.displayName,
                diagnosticIndex: entry.index,
                diagnostic: entry.subject.diagnostic,
                localVersion: entry.localVersion,
                selectedEntryPath: entry.selectedEntryPath,
                selectedTarget: entry.observedTarget,
                selectedKegVersion: selectedKeg?.kegVersion,
                managerEntryPath: manager.entryPath,
                managerTarget: manager.canonicalTarget,
                managerFingerprint: managerIdentity.fingerprint,
                managerCellar: verifiedCellar,
                formulaStem: record?.name ?? selectedKeg?.formula,
                fullFormulaName: record?.fullName,
                status: status,
                provenance: .freshProbe(observedAt: observed)
            )
            // Any verified, successful comparison is reusable metadata: upToDate AND
            // updateAvailable. Unknown outcomes are never persisted as six-hour negative entries.
            if isVerifiedSuccess(status), let record, let selectedKeg {
                toPersist[entry.index] = UpdateMetadataEntry(
                    registryID: entry.registryID,
                    managerEntryPath: manager.entryPath,
                    managerTarget: manager.canonicalTarget,
                    managerFingerprint: managerIdentity.fingerprint,
                    cellar: selectedKeg.cellar,
                    formulaStem: selectedKeg.formula,
                    fullFormulaName: record.fullName,
                    selectedEntryPath: entry.selectedEntryPath,
                    selectedKegVersion: selectedKeg.kegVersion,
                    selectedTarget: entry.observedTarget,
                    contextFingerprint: context,
                    formulaStable: record.stable,
                    formulaRevision: record.revision,
                    installedVersions: record.installedVersions,
                    observedAt: observed
                )
            }
        }

        // A second per-selection check catches changes made after result construction. Since the
        // results are not returned until this loop completes, a stale verified value becomes the
        // required neutral identity result. The same check gates metadata persistence.
        if Task.isCancelled {
            for entry in pending {
                results[entry.index] = neutral(pending: entry, .probeFailed, installed: Version(entry.localVersion))
            }
            return
        }
        for entry in pending where results[entry.index]?.status.isVerifiedComparison == true {
            guard managerIsLive(managerIdentity), selectionIsLive(entry) else {
                results[entry.index] = neutral(pending: entry, .identityUnverified, installed: Version(entry.localVersion))
                toPersist.removeValue(forKey: entry.index)
                continue
            }
        }
        if mode != .offline, !toPersist.isEmpty {
            var persistable: [UpdateMetadataEntry] = []
            for entry in pending where toPersist[entry.index] != nil {
                guard managerIsLive(managerIdentity), selectionIsLive(entry) else {
                    results[entry.index] = neutral(pending: entry, .identityUnverified, installed: Version(entry.localVersion))
                    continue
                }
                if let metadata = toPersist[entry.index] { persistable.append(metadata) }
            }
            if !persistable.isEmpty {
                guard !Task.isCancelled else {
                    for entry in pending {
                        results[entry.index] = neutral(pending: entry, .probeFailed, installed: Version(entry.localVersion))
                    }
                    return
                }
                if managerIsLive(managerIdentity) {
                    _ = cache.save(persistable)
                } else {
                    for entry in pending where results[entry.index]?.status.isVerifiedComparison == true {
                        results[entry.index] = neutral(pending: entry, .identityUnverified, installed: Version(entry.localVersion))
                    }
                }
            }
        }
    }

    // MARK: Selection and manager revalidation

    /// The selected entry and observed canonical target taken from the M5 selection itself, so a
    /// PATH winner and a verified off-PATH selection are treated identically.
    private static func selectedPair(_ diagnostic: ToolPathDiagnostic) -> (entryPath: String, target: String)? {
        let candidate: PathCandidateObservation
        switch diagnostic.selection {
        case .winner(let value): candidate = value
        case .offPath(let value, _): candidate = value
        case .notInstalled, .inconsistent: return nil
        }
        guard let target = candidate.canonicalTarget, !target.isEmpty else { return nil }
        return (candidate.entryPath, target)
    }

    private static func selectionIsLive(_ entry: Pending) -> Bool {
        guard isLiveRegularExecutable(entry.selectedEntryPath) else { return false }
        return resolveTarget(entry.selectedEntryPath) == entry.observedTarget
    }

    private static func managerIsLive(_ identity: ManagerIdentity) -> Bool {
        guard isLiveRegularExecutable(identity.manager.entryPath) else { return false }
        guard resolveTarget(identity.manager.entryPath) == identity.manager.canonicalTarget else { return false }
        return fingerprint(of: identity.manager) == identity.fingerprint
    }

    /// A regular file (after symlink resolution) the process may execute. No tool is ever run —
    /// this is a stat/access check only.
    private static func isLiveRegularExecutable(_ path: String) -> Bool {
        var info = Darwin.stat()
        let statStatus = path.withCString { pointer in fstatat(AT_FDCWD, pointer, &info, 0) }
        guard statStatus == 0 else { return false }
        guard (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else { return false }
        return path.withCString { access($0, X_OK) } == 0
    }

    private static func resolveTarget(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    // MARK: Cache helpers

    /// Recomputes the tri-state status from cached metadata against the CURRENT local facts. The
    /// stored full formula identity is restored verbatim — never reconstructed from the stem.
    private static func cachedResult(entry: Pending, cached: UpdateMetadataEntry) -> ToolUpdateResult {
        let batch = HomebrewBatchResult(
            cellar: cached.cellar,
            formulas: [cached.formulaStem: [HomebrewFormulaRecord(
                name: cached.formulaStem,
                fullName: cached.fullFormulaName,
                stable: cached.formulaStable,
                revision: cached.formulaRevision,
                installedVersions: cached.installedVersions
            )]],
            outdated: [:],
            queryCount: 0
        )
        let status = HomebrewStatusResolver.status(
            selectedTarget: entry.observedTarget,
            localVersion: entry.localVersion,
            batch: batch
        )
        return ToolUpdateResult(
            registryID: entry.registryID,
            displayName: entry.displayName,
            diagnosticIndex: entry.index,
            diagnostic: entry.subject.diagnostic,
            localVersion: entry.localVersion,
            selectedEntryPath: entry.selectedEntryPath,
            selectedTarget: entry.observedTarget,
            selectedKegVersion: cached.selectedKegVersion,
            managerEntryPath: cached.managerEntryPath,
            managerTarget: cached.managerTarget,
            managerFingerprint: cached.managerFingerprint,
            managerCellar: cached.cellar,
            formulaStem: cached.formulaStem,
            fullFormulaName: cached.fullFormulaName,
            status: status,
            provenance: .cache(observedAt: cached.observedAt)
        )
    }


    /// Re-derives the single verified record behind a successful comparison, mirroring the gates
    /// `HomebrewStatusResolver` already passed, so the cache stores the manager's own full
    /// identity claim rather than a basename.
    private static func verifiedRecord(for entry: Pending, batch: HomebrewBatchResult) -> HomebrewFormulaRecord? {
        guard let cellar = batch.cellar else { return nil }
        guard case .success(let keg) = HomebrewTargetParser.parse(selectedTarget: entry.observedTarget, cellar: cellar)
        else { return nil }
        guard let records = batch.formulas[keg.formula], records.count == 1,
              let record = records.first, record.isValid,
              record.name == keg.formula,
              HomebrewUpdateProbe.formulaIdentityConsistent(name: record.name, fullName: record.fullName),
              record.revision >= 0,
              HomebrewUpdateProbe.isSupportedUpstreamVersion(record.stable),
              record.installedVersions.contains(keg.kegVersion)
        else { return nil }
        return record
    }

    private static func fingerprint(of manager: HomebrewManager) -> String {
        var entryInfo = Darwin.stat()
        var targetInfo = Darwin.stat()
        let entryStatus = manager.entryPath.withCString { pointer in
            fstatat(AT_FDCWD, pointer, &entryInfo, AT_SYMLINK_NOFOLLOW)
        }
        let targetStatus = manager.canonicalTarget.withCString { pointer in
            stat(pointer, &targetInfo)
        }
        guard entryStatus == 0, targetStatus == 0 else {
            return UpdateMetadataKey.stableDigest("unavailable\(manager.entryPath)\(manager.canonicalTarget)")
        }
        func fields(_ info: Darwin.stat) -> [String] {
            [
                String(info.st_dev), String(info.st_ino), String(info.st_mode), String(info.st_size),
                "\(info.st_mtimespec.tv_sec).\(info.st_mtimespec.tv_nsec)",
                "\(info.st_ctimespec.tv_sec).\(info.st_ctimespec.tv_nsec)",
            ]
        }
        let parts = [manager.entryPath, manager.canonicalTarget] + fields(entryInfo) + fields(targetInfo)
        let material = parts.map { "\($0.utf8.count):\($0)" }.joined()
        return UpdateMetadataKey.stableDigest(material)
    }

    /// The probe context digest: every effective subprocess-environment input exactly as sent
    /// (the captured environment plus the two diagnostic toggles) plus the actual working
    /// directory that relative PATH entries resolve against. Length-prefixed frames make the
    /// serialization unambiguous; only the digest is stored, never a raw value or credential.
    private static func contextFingerprint(environment: ShellEnvironment, currentDirectory: String) -> String {
        let values = HomebrewUpdateProbe.diagnosticEnvironment(from: environment)
        func frame(_ text: String) -> String { "\(text.utf8.count):\(text)" }
        let workingDirectory = URL(fileURLWithPath: currentDirectory, isDirectory: true).standardizedFileURL.path
        let pairs = values.keys.sorted().map { frame($0) + frame(values[$0] ?? "") }.joined()
        let material = frame("agent-lens-update-context-v1")
            + frame("environment") + frame(String(values.count)) + pairs
            + frame("current-directory") + frame(workingDirectory)
        return UpdateMetadataKey.stableDigest(material)
    }

    /// Opaque process failures remain honest `probeFailed` results. Only explicit typed evidence
    /// from the runner is retained as a network-unavailable or rate-limited reason.
    private static func unknownReason(for error: HomebrewBatchError) -> UnknownReason {
        switch error {
        case .commandFailed(.networkUnavailable): .networkUnavailable
        case .commandFailed(.rateLimited): .rateLimited
        default: .probeFailed
        }
    }

    /// A verified, successful comparison — the only outcomes that may be published or persisted.
    private static func isVerifiedSuccess(_ status: VersionStatus) -> Bool {
        switch status {
        case .upToDate, .updateAvailable: true
        case .unknown: false
        }
    }

    // MARK: Result helpers

    private static func neutral(
        _ subject: UpdateProbeSubject,
        _ index: Int,
        _ reason: UnknownReason,
        installed: Version?
    ) -> ToolUpdateResult {
        let selection = reasonForPreservingSelection(reason) ? selectedPair(subject.diagnostic) : nil
        return ToolUpdateResult(
            registryID: subject.registryID,
            displayName: subject.displayName,
            diagnosticIndex: index,
            diagnostic: subject.diagnostic,
            localVersion: installed?.text,
            selectedEntryPath: selection?.entryPath,
            selectedTarget: selection?.target,
            selectedKegVersion: nil,
            managerEntryPath: nil,
            managerTarget: nil,
            managerFingerprint: nil,
            managerCellar: nil,
            formulaStem: nil,
            fullFormulaName: nil,
            status: .unknown(installed: installed, reason: reason),
            provenance: .none
        )
    }

    private static func neutral(
        pending: Pending,
        _ reason: UnknownReason,
        installed: Version?
    ) -> ToolUpdateResult {
        ToolUpdateResult(
            registryID: pending.registryID,
            displayName: pending.displayName,
            diagnosticIndex: pending.index,
            diagnostic: pending.subject.diagnostic,
            localVersion: pending.localVersion,
            selectedEntryPath: pending.selectedEntryPath,
            selectedTarget: pending.observedTarget,
            selectedKegVersion: nil,
            managerEntryPath: nil,
            managerTarget: nil,
            managerFingerprint: nil,
            managerCellar: nil,
            formulaStem: nil,
            fullFormulaName: nil,
            status: .unknown(installed: installed, reason: reason),
            provenance: .none
        )
    }

    private static func reasonForPreservingSelection(_ reason: UnknownReason) -> Bool {
        reason != .notInstalled && reason != .diagnosticInconsistent
    }

    private static func finalize(_ results: [ToolUpdateResult?], _ subjects: [UpdateProbeSubject]) -> [ToolUpdateResult] {
        zip(results, subjects.enumerated()).map { result, pair in
            let (index, subject) = pair
            return result ?? ToolUpdateResult(
                registryID: subject.registryID,
                displayName: subject.displayName,
                diagnosticIndex: index,
                diagnostic: subject.diagnostic,
                localVersion: subject.diagnostic.detectedTool.version,
                selectedEntryPath: nil,
                selectedTarget: nil,
                selectedKegVersion: nil,
                managerEntryPath: nil,
                managerTarget: nil,
                managerFingerprint: nil,
                managerCellar: nil,
                formulaStem: nil,
                fullFormulaName: nil,
                status: .unknown(installed: nil, reason: .probeFailed),
                provenance: .none
            )
        }
    }
}