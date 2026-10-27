// UpdateProbeCoordinator — M6 eligibility, mode policy, cache use, and association (brief §"Model and comparison contract").
//
// Results are keyed by the registry-derived tool ID and computed in input order, never by
// completion order. Eligibility is applied in the brief's fixed order so reasons are stable.
// The complete optional Check/Refresh stage — BOTH managers, every subject, and any cache-only
// path — runs inside one bounded stage admission with one monotonic budget and one deadline-clipped
// runner, so no manager from another run can overlap it. Plain/offline work never reaches admission.
// Cancellation is checked between steps and before any cache publication; a cancelled run never
// reports successful empty metadata.
//
// Association is explicit: every subject carries its registry ID and display name beside the
// M5 diagnostic, and every result carries the selected entry plus its observed canonical target
// so the selection can be re-verified immediately before a verified status is published or
// persisted. A moved, removed, or directory-replaced selection is `identityUnverified` neutral
// text — never a stale verified claim, and never a cache write.

import Darwin
import Dispatch
import Foundation

/// Observation seam for the bounded stage-admission queue, mirroring the existing Homebrew batch
/// hook. Internal only: it lets coordinator-level tests synchronize on a run that is waiting
/// BEFORE admission instead of sleeping and guessing.
enum UpdateProbeCoordinatorTestHooks {
    @TaskLocal static var onStageAdmissionQueued: (@Sendable () -> Void)?

    static func observingStageAdmissionQueue<T: Sendable>(
        _ observer: @escaping @Sendable () -> Void,
        operation: @Sendable () async -> T
    ) async -> T {
        await $onStageAdmissionQueued.withValue(observer) {
            await operation()
        }
    }
}

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

/// One scan subject: the validated registry definition carried beside the M5 diagnostic. The
/// definition is the association source — its stable ID, never a display name and never the
/// executable basename — so a display rename cannot detach a result from its identity, two tools
/// sharing a display name stay distinguishable, and an ID can never disagree with its own
/// definition.
public struct UpdateProbeSubject: Equatable, Sendable {
    public let definition: DetectorDefinition
    public let diagnostic: ToolPathDiagnostic

    public init(definition: DetectorDefinition, diagnostic: ToolPathDiagnostic) {
        self.definition = definition
        self.diagnostic = diagnostic
    }

    /// The stable registry identity, derived from the definition it came from.
    public var registryID: String { definition.id }
    /// The user-visible label, derived from the same definition — kept beside, never separate from,
    /// the identity so the two cannot drift.
    public var displayName: String { definition.displayName }
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
    /// npm package name (nil for Homebrew results).
    public let npmPackage: String?
    /// Resolved npm registry (nil for Homebrew results).
    public let npmRegistry: String?
    /// Dist tag queried (nil for Homebrew results).
    public let npmTag: String?
    /// Observed `npm --version` text (nil when unavailable or for Homebrew results).
    public let npmVersion: String?
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
        npmPackage: String? = nil,
        npmRegistry: String? = nil,
        npmTag: String? = nil,
        npmVersion: String? = nil,
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
        self.npmPackage = npmPackage
        self.npmRegistry = npmRegistry
        self.npmTag = npmTag
        self.npmVersion = npmVersion
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
        now: @escaping @Sendable () -> Date,
        uptime: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds },
        npmScratchBaseURL: URL? = nil
    ) async -> [ToolUpdateResult] {
        var results = [ToolUpdateResult?](repeating: nil, count: subjects.count)
        var pending: [Pending] = []
        var npmPending: [Pending] = []

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
            let source = tool.source
            guard source == "brew" || source == "npm" else {
                let reason: UnknownReason = source == "standalone" ? .noRegistry : .unsupportedSource
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
                let entry = Pending(
                    index: index,
                    subject: subject,
                    selectedEntryPath: selection.entryPath,
                    observedTarget: selection.target,
                    localVersion: version
                )
                if source == "brew" { pending.append(entry) } else { npmPending.append(entry) }
            }
        }

        // Plain/offline runs return here with zero admission, zero cache read/write and zero
        // manager query: eligibility decided every subject without touching the stage gate.
        guard !pending.isEmpty || !npmPending.isEmpty else {
            return finalize(results, subjects)
        }

        // The manager identity is snapshotted BEFORE queueing for admission, exactly like the
        // scan-time selection pair. Resolution launches no process and touches no cache; it is only
        // the local PATH lookup. A snapshot taken after admission would silently bless a manager
        // replaced while this run waited, so the pre-launch revalidation could never notice.
        var managerIdentity: ManagerIdentity?
        if !pending.isEmpty, let manager = HomebrewManagerResolver.resolve(
            environment: environment,
            currentDirectory: currentDirectory
        ) {
            managerIdentity = ManagerIdentity(manager: manager, fingerprint: fingerprint(of: manager))
        }

        // ONE admission for the COMPLETE optional stage — Homebrew and npm together, including a
        // Homebrew-only or cache-only stage. A run that cannot enter the stage inside the bounded
        // wait (or that is cancelled while waiting) reports the reason for every optional subject
        // and launches nothing; a manager from another run can never overlap this one's npm work.
        let gate = UpdateStageAdmissionGate.shared
        let permitID = UUID()
        let acquired = await gate.acquire(id: permitID, waitNanos: Self.stageAdmissionWaitNanoseconds)
        guard acquired else {
            let reason: UnknownReason = Task.isCancelled ? .probeFailed : .budgetExhausted
            for entry in pending + npmPending {
                results[entry.index] = neutral(
                    pending: entry, reason, installed: Version(entry.localVersion)
                )
            }
            // Never released here: this run holds no permit, and releasing would free the stage
            // while another run is still inside it.
            return finalize(results, subjects)
        }

        // The single monotonic budget starts at admission and covers every manager and every
        // optional step: the Homebrew batch, npm ownership/config/metadata and revalidation.
        let stageDeadline = uptime().addingReportingOverflow(Self.stageBudgetNanoseconds).partialValue
        let clipped = DeadlineClippingRunner(
            base: runner, deadlineNanos: stageDeadline, uptime: uptime
        )

        // Homebrew first, so slow or exhausted npm work can never evict a completed Homebrew
        // result. Then npm subjects in registry order, inside the same admitted stage.
        if !pending.isEmpty {
            if let identity = managerIdentity {
                await resolveBatch(
                    pending: pending,
                    managerIdentity: identity,
                    environment: environment,
                    runner: clipped,
                    cache: UpdateMetadataCache(fileURL: cacheURL, now: now),
                    mode: mode,
                    currentDirectory: currentDirectory,
                    now: now,
                    uptime: uptime,
                    stageDeadline: stageDeadline,
                    results: &results
                )
            } else {
                for entry in pending {
                    results[entry.index] = neutral(pending: entry, .managerUnavailable, installed: Version(entry.localVersion))
                }
            }
        }
        if !npmPending.isEmpty {
            await resolveNpmBatch(
                pending: npmPending,
                environment: environment,
                runner: clipped,
                stageDeadline: stageDeadline,
                cacheURL: cacheURL,
                mode: mode,
                currentDirectory: currentDirectory,
                now: now,
                uptime: uptime,
                npmScratchBaseURL: npmScratchBaseURL,
                results: &results
            )
        }
        // Released exactly once, on every exit and cancellation path: both manager stages return
        // to this point rather than leaving the admitted stage early.
        await gate.release()
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
        uptime: @escaping @Sendable () -> UInt64,
        stageDeadline: UInt64,
        results: inout [ToolUpdateResult?]
    ) async {
        let manager = managerIdentity.manager
        // A refusal produced by the stage's deadline-clipping runner is reported by CAUSE: the
        // aggregate deadline exhausting maps to `budgetExhausted`, never to a generic cancelled or
        // `probeFailed` claim (R04), and this now applies to Homebrew launches as well as npm ones.
        let deadlineExhausted = { uptime() >= stageDeadline && !Task.isCancelled }
        let context = contextFingerprint(environment: environment, currentDirectory: currentDirectory)
        // The manager-reported Cellar is unavailable until a fresh batch. A cache hit therefore
        // restores one uniquely matching, complete stored identity for the verified selection.

        if mode == .checkUpdates {
            // A cache-only Check is still an admitted stage: with the aggregate deadline gone it
            // reports `budgetExhausted` rather than serving disk metadata (B03.4).
            if deadlineExhausted() {
                for entry in pending {
                    results[entry.index] = neutral(
                        pending: entry, .budgetExhausted, installed: Version(entry.localVersion)
                    )
                }
                return
            }
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
            let reason = unknownReason(for: error, stageDeadlineExhausted: deadlineExhausted())
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

    // MARK: npm stage

    /// The shared monotonic budget for one complete optional update stage (all subjects and BOTH
    /// managers, including the Homebrew batch, npm ownership/config, metadata and revalidation). It
    /// starts when stage admission is acquired. A stage that cannot finish inside it yields
    /// `budgetExhausted` for the work it never launched — never a partial or stale verified result.
    private static let stageBudgetNanoseconds: UInt64 = 60_000_000_000
    /// Admission waiting is separately bounded: a run that cannot acquire the complete optional
    /// stage inside this window reports `budgetExhausted` without launching ANY manager — Homebrew
    /// included — and without reading or writing either metadata document.
    private static let stageAdmissionWaitNanoseconds: UInt64 = 10_000_000_000

    /// Runs the npm latest probe for every eligible npm subject after the Homebrew batch, in
    /// registry order, inside the stage the caller already admitted.
    ///
    /// The caller owns admission and the one 60-second deadline, so the same deadline-clipped runner
    /// and the injected monotonic clock reach Homebrew and every npm ownership/config/metadata step.
    /// A slow or exhausted npm stage therefore cannot evict an already-completed Homebrew result and
    /// cannot launch a manager after the budget has run out. Homebrew's own inner batch admission and
    /// lock order are untouched: it nests inside this stage gate, never the reverse.
    private static func resolveNpmBatch(
        pending: [Pending],
        environment: ShellEnvironment,
        runner: UpdateCommandRunner,
        stageDeadline: UInt64,
        cacheURL: URL,
        mode: UpdateProbeMode,
        currentDirectory: String,
        now: @escaping @Sendable () -> Date,
        uptime: @escaping @Sendable () -> UInt64,
        npmScratchBaseURL: URL?,
        results: inout [ToolUpdateResult?]
    ) async {
        for entry in pending {
            if Task.isCancelled {
                results[entry.index] = neutral(
                    pending: entry, .probeFailed, installed: Version(entry.localVersion)
                )
                continue
            }
            // Exhaustion is checked before each subject so a later npm subject launches nothing.
            if uptime() >= stageDeadline {
                results[entry.index] = neutral(
                    pending: entry, .budgetExhausted, installed: Version(entry.localVersion)
                )
                continue
            }
            results[entry.index] = await NpmUpdateProbe.run(
                definition: entry.subject.definition,
                diagnostic: entry.subject.diagnostic,
                environment: environment,
                runner: runner,
                cacheURL: cacheURL,
                mode: mode,
                currentDirectory: currentDirectory,
                now: now,
                uptime: uptime,
                stageDeadline: stageDeadline,
                diagnosticIndex: entry.index,
                npmScratchBaseURL: npmScratchBaseURL
            )
        }
    }

    /// Grants one COMPLETE optional-stage permit at a time across simultaneous run calls and both
    /// managers. A waiter whose bounded wait elapses, or whose task is cancelled, is resumed with
    /// failure so the stage reports `budgetExhausted`/`probeFailed` without launching a manager.
    private actor UpdateStageAdmissionGate {
        static let shared = UpdateStageAdmissionGate()

        private struct Waiter {
            let id: UUID
            let continuation: CheckedContinuation<Bool, Never>
        }

        private var occupied = false
        private var waiters: [Waiter] = []

        func acquire(id: UUID, waitNanos: UInt64) async -> Bool {
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
                    UpdateProbeCoordinatorTestHooks.onStageAdmissionQueued?()
                    Task {
                        try? await Task.sleep(nanoseconds: waitNanos)
                        self.expire(id)
                    }
                }
            } onCancel: {
                Task { await self.expire(id) }
            }
        }

        func release() {
            guard !waiters.isEmpty else {
                occupied = false
                return
            }
            let next = waiters.removeFirst()
            occupied = true
            next.continuation.resume(returning: true)
        }

        /// Fails one waiter that is still queued. A waiter already granted has been removed, so a
        /// stray expiry is a no-op and never revokes a live permit.
        private func expire(_ id: UUID) {
            guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
            let waiter = waiters.remove(at: index)
            waiter.continuation.resume(returning: false)
        }
    }

    /// An `UpdateCommandRunner` wrapper that clips each nominal timeout to the remaining stage
    /// budget and refuses to launch once the budget is exhausted. The wrapped production runner is
    /// unchanged; only the timeout handed to it is reduced.
    ///
    /// The exhaustion refusal is a `.cancelled` failure. Callers must map it by CAUSE: when the
    /// aggregate stage deadline caused the refusal (injected `uptime() >= deadline`, no task
    /// cancellation), the reported reason is `budgetExhausted` — never a generic cancelled or
    /// probeFailed claim. The injected `uptime` closure is read outside the base runner, so a
    /// deadline exhausted during a response still takes effect at the next launch check.
    private struct DeadlineClippingRunner: UpdateCommandRunner {
        let base: UpdateCommandRunner
        let deadlineNanos: UInt64
        let uptime: @Sendable () -> UInt64

        func run(
            executablePath: String,
            arguments: [String],
            environment: [String: String],
            timeout: TimeInterval
        ) async -> CommandOutcome {
            let remaining = Int64(deadlineNanos) &- Int64(uptime())
            guard remaining > 0 else { return .failure(.cancelled) }
            let remainingSeconds = TimeInterval(remaining) / 1_000_000_000
            return await base.run(
                executablePath: executablePath,
                arguments: arguments,
                environment: environment,
                timeout: min(timeout, remainingSeconds)
            )
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
    /// from the runner is retained as a network-unavailable or rate-limited reason. A `.cancelled`
    /// failure the stage's clipping runner produced because the AGGREGATE deadline was already gone
    /// is reported as `budgetExhausted` — the caller's cause, not a generic cancellation claim.
    private static func unknownReason(
        for error: HomebrewBatchError,
        stageDeadlineExhausted: Bool
    ) -> UnknownReason {
        switch error {
        case .commandFailed(.networkUnavailable): .networkUnavailable
        case .commandFailed(.rateLimited): .rateLimited
        case .commandFailed(.cancelled) where stageDeadlineExhausted: .budgetExhausted
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