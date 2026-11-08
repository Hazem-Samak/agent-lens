// InventoryViewModel — the main-actor state contract the SwiftUI window renders (M7 brief
// §"Proposed architecture and state contract", phases `idle`/`loadingLocal`/`localReady`/
// `checkingUpdates`/`ready`/`failed`).
//
// This type owns presentation STATE, never facts: it holds the published `InventorySnapshot`
// verbatim and derives counts, filtering, and selection from it. Core's typed values
// (`ToolPathDiagnostic`, `VersionStatus`, `UpdateProvenance`) are never re-derived, and errors stay
// VALUES rather than strings where a typed reason exists.
//
// Local-first ordering is the whole point of the file: an action publishes the local snapshot
// BEFORE any optional update probe is allowed to run, and a launch resolves nothing but local
// facts — no manager command, no cache read, no update coordinator.
//
// One active pipeline at a time. A conflicting call coalesces (it neither disturbs the running
// phase nor its badges) instead of starting a second pipeline, so a user mashing Check/Refresh
// cannot interleave two scans. Generations are monotonic; a completion whose generation is no
// longer current publishes nothing. Cancellation follows ownership: a caller whose task is
// cancelled (the window's `.task` going away) cancels the pipeline it opened, waits for that
// pipeline's bounded cleanup, and publishes neither a partial snapshot nor a cancellation error.
//
// Every production process receives `ShellEnvironment.raw` from the service. Nothing here reads
// `ProcessInfo` PATH or `$SHELL`, holds a login shell, or persists/logs a captured value.

import AgentLensCore
import Foundation
import Observation

@MainActor
@Observable
public final class InventoryViewModel {

    /// The state contract's phases. `localReady` is the window's "local facts are on screen, an
    /// optional update phase may follow" state; `ready` is a settled action.
    public enum Phase: Equatable, Sendable {
        case idle
        case loadingLocal
        case localReady
        case checkingUpdates
        case verifyingOwnership
        case ready
        case failed
    }

    /// A failure as a value. The typed Core error is preserved when the failure is one — a
    /// `DetectorRegistryError` from an invalid registry is never flattened into prose — and the
    /// message is the error's own description, not a synthesized claim.
    public struct Failure: Equatable, Sendable {
        public let message: String
        public let registryError: DetectorRegistryError?

        public init(error: any Error) {
            if let registryError = error as? DetectorRegistryError {
                self.registryError = registryError
                self.message = registryError.description
            } else {
                self.registryError = nil
                self.message = String(describing: error)
            }
        }
    }

    /// The concrete boundary, injected. Its existing seams (registry, environment, scanner,
    /// runner, clock, cache URL) are what tests replace, so no protocol is invented for it.
    private let service: InventoryService

    /// Monotonic action identity. A completion or error is published only while its generation is
    /// still the current one, so an obsolete action can never clear or overwrite newer state.
    private var generation: UInt64 = 0

    /// The running pipeline, if any. Read and written on the main actor only, so a conflicting
    /// action observes the slot synchronously.
    private var activePipeline: Task<Void, Never>?

    /// Update preparation/execution is a second single-slot pipeline. Keeping it separate from the
    /// scan pipeline lets a pending preview exist without a running process while still making
    /// every UI action observe one mutually exclusive operation owner.
    private var updatePipeline: Task<Void, Never>?
    private var updateGeneration: UInt64 = 0
    private var uninstallPipeline: Task<Void, Never>?
    private var uninstallGeneration: UInt64 = 0
    private var isTearingDownMutation = false

    // MARK: Published state

    public private(set) var phase: Phase = .idle

    /// True while a requested cancellation is being awaited. The UI says Cancelling rather than
    /// Verifying, and the action still owns the pipeline until its bounded cleanup returns.
    public private(set) var isCancelling: Bool = false

    /// The published local facts, with update outcomes when a probe has been performed. nil before
    /// the first successful local scan.
    public private(set) var snapshot: InventorySnapshot?

    /// The case-insensitive search text. Selection is held by registry ID, so typing hides the
    /// selected row without losing it.
    public var searchText: String = "" {
        didSet {
            if searchText != oldValue { invalidatePendingUpdate() }
        }
    }

    /// The selected registry ID — never a row index, display name, or executable basename, so two
    /// tools sharing a display name stay distinguishable.
    public private(set) var selectedRegistryID: String?

    /// The most recent local/rescan failure. The last useful snapshot stays published beside it, so
    /// a failed rescan degrades freshness instead of blanking the window.
    public private(set) var freshnessFailure: Failure?

    /// The most recent update-phase failure. Local diagnostics stay usable beside it.
    public private(set) var updateFailure: Failure?

    /// The pending preview, if any. The preparation is opaque authorization evidence; the UI only
    /// reads its preview.
    public private(set) var updatePreparation: NpmUpdatePreparation?

    /// The reviewed preview is retained while the opaque preparation is being consumed so the
    /// executing sheet cannot disappear between Confirm and the result.
    public private(set) var updatePreview: NpmUpdatePreview?

    /// The last operation result, retained until the sheet is dismissed or another action starts.
    public private(set) var updateOutcome: OperationOutcome?

    /// A typed refusal from preparation, retained for the native presentation.
    public private(set) var updateUnavailableReason: NpmUpdateUnavailableReason?

    /// The pending Uninstall preview and opaque authorization evidence.
    public private(set) var uninstallPreparation: NpmUninstallPreparation?
    public private(set) var uninstallPreview: NpmUninstallPreview?
    public private(set) var uninstallOutcome: NpmUninstallOutcome?
    public private(set) var uninstallUnavailableReason: NpmUninstallUnavailableReason?

    public init(service: InventoryService) {
        self.service = service
    }

    // MARK: Derived reads (snapshot truth only)

    /// The full, never-filtered snapshot entries. Filtering belongs to `filteredEntries`.
    public var entries: [InventoryEntry] { snapshot?.entries ?? [] }

    /// Known tools: definitions, NOT installations.
    public var knownToolCount: Int { snapshot?.knownToolCount ?? 0 }

    /// Installed tools, by the typed install state (`installedNotOnPath` counts as installed).
    public var installedToolCount: Int { snapshot?.installedToolCount ?? 0 }

    /// Only verified `updateAvailable` comparisons are counted; neutral outcomes never are.
    public var updateAvailableCount: Int { snapshot?.updateAvailableCount ?? 0 }

    /// The documented degraded-environment warning (M2/D-005), never inferred from PATH text.
    public var isDegradedEnvironment: Bool { snapshot?.isDegradedEnvironment ?? false }

    /// True while an action owns a pipeline; the window disables conflicting controls with it.
    public var isBusy: Bool {
        activePipeline != nil || updatePipeline != nil || uninstallPipeline != nil
    }

    /// True while the confirmation sheet has something to present.
    public var isUpdateSheetPresented: Bool {
        updatePreview != nil || updatePreparation != nil || updateOutcome != nil
            || updateUnavailableReason != nil
    }

    /// True while the Uninstall sheet has something to present. Update and Uninstall share one
    /// mutation slot, so at most one of the two sheets can be presented.
    public var isUninstallSheetPresented: Bool {
        uninstallPreview != nil || uninstallPreparation != nil || uninstallOutcome != nil
            || uninstallUnavailableReason != nil
    }

    public private(set) var isPreparingUpdate: Bool = false
    public private(set) var isExecutingUpdate: Bool = false
    public private(set) var isPreparingUninstall: Bool = false
    public private(set) var isExecutingUninstall: Bool = false

    /// The entries the window lists: the full snapshot filtered by search text, in registry order.
    /// Nothing is re-associated after filtering — each entry carries its own definition, diagnostic,
    /// and update result, so a filter can never mix facts across tools.
    public var filteredEntries: [InventoryEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return entries }
        return entries.filter { Self.matches($0, query: query) }
    }

    /// The selected entry, resolved by ID against the published snapshot. nil when nothing is
    /// selected or the selected tool is gone.
    public var selectedEntry: InventoryEntry? {
        guard let selectedRegistryID else { return nil }
        return entries.first { $0.registryID == selectedRegistryID }
    }

    /// Selection by ID. An unknown ID is refused rather than stored, so selection can never point at
    /// an entry that is not published.
    public func select(registryID: String?) {
        if registryID != selectedRegistryID { invalidatePendingUpdate() }
        guard let registryID else {
            if selectedRegistryID != nil, phase == .verifyingOwnership {
                isCancelling = true
                activePipeline?.cancel()
            }
            selectedRegistryID = nil
            return
        }
        guard entries.contains(where: { $0.registryID == registryID }) else { return }
        // A proof belongs to one selected tool. Switching selection cancels the running
        // verification instead of letting its result attach to the new tool.
        if registryID != selectedRegistryID, phase == .verifyingOwnership {
            isCancelling = true
            activePipeline?.cancel()
        }
        selectedRegistryID = registryID
    }

    // MARK: Actions

    /// Launch: the idempotent initial local-only inventory. No manager command, no cache read, no
    /// update probe. It runs only from the initial fact-free state (`idle`): a repeat launch — the
    /// window re-appearing, a second `.task` on the same window — performs no second scan and
    /// publishes nothing, and a launch while an action is running coalesces. Recovering a stale or
    /// failed inventory is the explicit `rescan()`.
    public func launch() async {
        guard phase == .idle else { return }
        await run(isInitialLaunch: true, isRescan: false, updateMode: nil)
    }

    /// Rescan: a fresh login-shell capture and a fresh local inventory. Local facts only.
    public func rescan() async {
        await run(isInitialLaunch: false, isRescan: true, updateMode: nil)
    }

    /// Check: fresh local facts published first, then the cache-eligible M6 probe.
    public func checkForUpdates() async {
        await run(isInitialLaunch: false, isRescan: false, updateMode: .checkUpdates)
    }

    /// Refresh: fresh local facts published first, then an M6 probe that bypasses the cache read.
    public func refreshUpdates() async {
        await run(isInitialLaunch: false, isRescan: false, updateMode: .refresh)
    }

    /// The only app entry point for explicit read-only ownership verification. It owns the same
    /// single pipeline slot as scan/update actions, so a conflicting action coalesces rather than
    /// interleaving, and it never clears update badges. Verification starts from the currently
    /// published selected entry and publishes only into that same entry while the selection and
    /// its observed target identity are unchanged.
    public func verifySelectedInstallation() async {
        invalidatePendingUpdate()
        guard activePipeline == nil, updatePipeline == nil, uninstallPipeline == nil else { return }
        guard let entry = selectedEntry,
              Self.observedSelection(entry.diagnostic) != nil
        else { return }

        generation &+= 1
        let generation = generation
        let registryID = entry.registryID
        let observedSelection = Self.observedSelection(entry.diagnostic)
        isCancelling = false
        phase = .verifyingOwnership

        let service = self.service
        let pipeline = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await service.verifyingOwnership(of: entry)
            guard generation == self.generation,
                  !Task.isCancelled,
                  self.phase == .verifyingOwnership,
                  result.registryID == registryID,
                  self.selectedRegistryID == registryID,
                  let current = self.selectedEntry,
                  current.registryID == registryID,
                  Self.observedSelection(current.diagnostic) == observedSelection
            else { return }
            self.publishOwnership(result, for: registryID)
            self.phase = .ready
            self.isCancelling = false
        }
        activePipeline = pipeline
        await withTaskCancellationHandler {
            await pipeline.value
        } onCancel: {
            pipeline.cancel()
        }

        let cancelled = pipeline.isCancelled || Task.isCancelled
        if generation == self.generation { activePipeline = nil }
        guard cancelled else {
            // A non-cancelled verification that could not publish (for example, its selected
            // target changed) still settles the phase; it must never leave the window busy.
            if generation == self.generation, phase == .verifyingOwnership {
                phase = snapshot == nil ? .idle : .ready
                isCancelling = false
            }
            return
        }
        invalidate(generation: generation)
        if phase == .verifyingOwnership {
            phase = snapshot == nil ? .idle : .ready
        }
        isCancelling = false
    }

    /// Freshly prepares the selected npm update. The preparation stays in one pending slot; any
    /// selection/filter/scan/check/refresh/verify action invalidates it without mutation.
    public func prepareSelectedUpdate() async {
        invalidatePendingUpdate()
        guard activePipeline == nil, updatePipeline == nil, uninstallPipeline == nil else { return }
        guard let entry = selectedEntry,
              case .updateAvailable = entry.updateStatus,
              entry.update?.npmPackage != nil
        else { return }

        updateGeneration &+= 1
        let generation = updateGeneration
        let registryID = entry.registryID
        let observed = Self.observedSelection(entry.diagnostic)
        updateOutcome = nil
        updateUnavailableReason = nil
        updatePreview = nil
        isCancelling = false
        isPreparingUpdate = true
        let service = self.service
        let pipeline = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await service.prepareUpdate(for: entry)
            guard generation == self.updateGeneration,
                  !Task.isCancelled,
                  self.selectedRegistryID == registryID,
                  self.selectedEntry?.registryID == registryID,
                  let current = self.selectedEntry,
                  Self.observedSelection(current.diagnostic) == observed
            else {
                if case .ready(let preparation) = result { _ = service.cancelUpdate(preparation) }
                return
            }
            switch result {
            case .ready(let preparation):
                self.updatePreparation = preparation
                self.updatePreview = preparation.preview
            case .unavailable(let reason):
                self.updateUnavailableReason = reason
            }
        }
        updatePipeline = pipeline
        await withTaskCancellationHandler {
            await pipeline.value
        } onCancel: {
            pipeline.cancel()
        }
        if generation == self.updateGeneration {
            updatePipeline = nil
            isPreparingUpdate = false
        }
        if generation == self.updateGeneration, isCancelling {
            if let preparation = updatePreparation {
                _ = service.cancelUpdate(preparation)
                updatePreparation = nil
            }
            phase = snapshot == nil ? .idle : .localReady
            isCancelling = false
        }
    }

    /// Consumes the pending preparation and executes the one confirmed mutation. The service
    /// returns a fresh local snapshot after Core's mandatory reconciliation.
    public func confirmSelectedUpdate() async {
        guard activePipeline == nil, updatePipeline == nil, uninstallPipeline == nil,
              uninstallPreparation == nil,
              let preparation = updatePreparation
        else { return }
        updateGeneration &+= 1
        let generation = updateGeneration
        updatePreparation = nil
        updateOutcome = nil
        updateUnavailableReason = nil
        isCancelling = false
        isExecutingUpdate = true
        let service = self.service
        let pipeline = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await service.executeUpdate(preparation)
            guard generation == self.updateGeneration else { return }
            self.updateOutcome = result.outcome
            if let snapshot = result.snapshot {
                self.publish(snapshot, updateFailure: nil)
            }
            self.isExecutingUpdate = false
            self.isCancelling = false
        }
        updatePipeline = pipeline
        await withTaskCancellationHandler {
            await pipeline.value
        } onCancel: {
            pipeline.cancel()
        }
        if generation == self.updateGeneration {
            updatePipeline = nil
            isExecutingUpdate = false
        }
        if generation == self.updateGeneration, isCancelling {
            phase = snapshot == nil ? .idle : .localReady
            isCancelling = false
        }
    }

    /// Cancels a pending preview with zero mutation, or interrupts and joins a launched operation.
    public func cancelUpdate() async {
        if let pipeline = updatePipeline {
            isCancelling = true
            pipeline.cancel()
            await pipeline.value
            if pipeline.isCancelled || Task.isCancelled {
                if isPreparingUpdate, let preparation = updatePreparation {
                    _ = service.cancelUpdate(preparation)
                    updatePreparation = nil
                }
                if isPreparingUpdate { phase = snapshot == nil ? .idle : .localReady }
                if isPreparingUpdate { updatePreview = nil }
                isPreparingUpdate = false
                isCancelling = false
            }
            return
        }
        if let preparation = updatePreparation {
            _ = service.cancelUpdate(preparation)
            updatePreparation = nil
        }
        updateOutcome = nil
        updateUnavailableReason = nil
        updatePreview = nil
        if phase == .ready || phase == .localReady { phase = snapshot == nil ? .idle : .ready }
        isCancelling = false
    }

    /// Closes the native update sheet. A pending preview is released; an executing operation is
    /// cancelled and joins through `cancelUpdate`.
    public func dismissUpdate() {
        if updatePipeline != nil {
            Task { @MainActor in await self.cancelUpdate() }
            return
        }
        if let preparation = updatePreparation {
            _ = service.cancelUpdate(preparation)
            updatePreparation = nil
        }
        updateOutcome = nil
        updateUnavailableReason = nil
        updatePreview = nil
    }

    /// Freshly prepares the selected npm Uninstall. Eligibility is gated by a current verified npm
    /// ownership observation; Core repeats full live verification and never trusts it.
    public func prepareSelectedUninstall() async {
        invalidatePendingUpdate()
        guard activePipeline == nil, updatePipeline == nil, uninstallPipeline == nil else { return }
        guard let entry = selectedEntry,
              let verified = entry.ownership?.verifiedInstallation,
              verified.manager == .npm,
              Self.observedSelection(entry.diagnostic) != nil
        else { return }

        uninstallGeneration &+= 1
        let generation = uninstallGeneration
        let registryID = entry.registryID
        let observed = Self.observedSelection(entry.diagnostic)
        uninstallOutcome = nil
        uninstallUnavailableReason = nil
        uninstallPreview = nil
        isCancelling = false
        isPreparingUninstall = true
        let service = self.service
        let pipeline = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await service.prepareUninstall(for: entry)
            guard generation == self.uninstallGeneration,
                  !Task.isCancelled,
                  self.selectedRegistryID == registryID,
                  self.selectedEntry?.registryID == registryID,
                  let current = self.selectedEntry,
                  Self.observedSelection(current.diagnostic) == observed
            else {
                if case .ready(let preparation) = result { _ = service.cancelUninstall(preparation) }
                return
            }
            switch result {
            case .ready(let preparation):
                self.uninstallPreparation = preparation
                self.uninstallPreview = preparation.preview
            case .unavailable(let reason):
                self.uninstallUnavailableReason = reason
            }
        }
        uninstallPipeline = pipeline
        await withTaskCancellationHandler {
            await pipeline.value
        } onCancel: {
            pipeline.cancel()
        }
        if generation == self.uninstallGeneration {
            uninstallPipeline = nil
            isPreparingUninstall = false
        }
        if generation == self.uninstallGeneration, isCancelling {
            if let preparation = uninstallPreparation {
                _ = service.cancelUninstall(preparation)
                uninstallPreparation = nil
            }
            phase = snapshot == nil ? .idle : .localReady
            isCancelling = false
        }
    }

    /// Consumes the pending Uninstall preparation and executes the one confirmed removal.
    public func confirmSelectedUninstall() async {
        guard activePipeline == nil, updatePipeline == nil, uninstallPipeline == nil,
              updatePreparation == nil,
              let preparation = uninstallPreparation
        else { return }
        uninstallGeneration &+= 1
        let generation = uninstallGeneration
        let registryID = preparation.preview.registryID
        uninstallPreparation = nil
        uninstallOutcome = nil
        uninstallUnavailableReason = nil
        isCancelling = false
        isExecutingUninstall = true
        let service = self.service
        let pipeline = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await service.executeUninstall(preparation)
            guard generation == self.uninstallGeneration else { return }
            self.uninstallOutcome = result.outcome
            if let snapshot = result.snapshot {
                self.publish(snapshot, updateFailure: nil)
            } else if result.outcome.processStarted {
                // A launched removal must not leave the destructive action armed when the
                // post-launch rescan failed or was cancelled. Clear only this entry's observation.
                self.clearOwnership(for: registryID)
            }
            self.isExecutingUninstall = false
            self.isCancelling = false
        }
        uninstallPipeline = pipeline
        await withTaskCancellationHandler {
            await pipeline.value
        } onCancel: {
            pipeline.cancel()
        }
        if generation == self.uninstallGeneration {
            uninstallPipeline = nil
            isExecutingUninstall = false
        }
        if generation == self.uninstallGeneration, isCancelling {
            phase = snapshot == nil ? .idle : .localReady
            isCancelling = false
        }
    }

    /// Cancels a pending Uninstall preview with zero mutation, or interrupts and joins a launched
    /// operation.
    public func cancelUninstall() async {
        if let pipeline = uninstallPipeline {
            isCancelling = true
            pipeline.cancel()
            await pipeline.value
            if pipeline.isCancelled || Task.isCancelled {
                if isPreparingUninstall, let preparation = uninstallPreparation {
                    _ = service.cancelUninstall(preparation)
                    uninstallPreparation = nil
                }
                if isPreparingUninstall { phase = snapshot == nil ? .idle : .localReady }
                if isPreparingUninstall { uninstallPreview = nil }
                isPreparingUninstall = false
                isCancelling = false
            }
            return
        }
        if let preparation = uninstallPreparation {
            _ = service.cancelUninstall(preparation)
            uninstallPreparation = nil
        }
        uninstallOutcome = nil
        uninstallUnavailableReason = nil
        uninstallPreview = nil
        if phase == .ready || phase == .localReady { phase = snapshot == nil ? .idle : .ready }
        isCancelling = false
    }

    /// Closes the native Uninstall sheet. A pending preview is released; an executing operation is
    /// cancelled and joins through `cancelUninstall`.
    public func dismissUninstall() {
        if uninstallPipeline != nil {
            Task { @MainActor in await self.cancelUninstall() }
            return
        }
        if let preparation = uninstallPreparation {
            _ = service.cancelUninstall(preparation)
            uninstallPreparation = nil
        }
        uninstallOutcome = nil
        uninstallUnavailableReason = nil
        uninstallPreview = nil
    }

    /// Invalidates a pending preview on any competing selection/filter/scan/check/refresh/verify.
    private func invalidatePendingUpdate() {
        if isTearingDownMutation { return }
        // A launched mutation is not a pending preview. Its outcome is bound to its own registry
        // ID and its snapshot is the whole-inventory reconciliation, so a competing selection or
        // filter must not cancel it or discard those facts. The busy slot still blocks new actions
        // until this pipeline joins; teardown is only for an unconsumed preparation.
        if isExecutingUpdate || isExecutingUninstall { return }
        let update = updatePipeline
        let uninstall = uninstallPipeline
        guard update != nil || uninstall != nil else {
            if let preparation = updatePreparation {
                _ = service.cancelUpdate(preparation)
                updatePreparation = nil
            }
            if let preparation = uninstallPreparation {
                _ = service.cancelUninstall(preparation)
                uninstallPreparation = nil
            }
            updateOutcome = nil
            updateUnavailableReason = nil
            updatePreview = nil
            uninstallOutcome = nil
            uninstallUnavailableReason = nil
            uninstallPreview = nil
            return
        }
        updateGeneration &+= 1
        uninstallGeneration &+= 1
        isTearingDownMutation = true
        isCancelling = true
        update?.cancel()
        uninstall?.cancel()
        if let preparation = updatePreparation {
            _ = service.cancelUpdate(preparation)
            updatePreparation = nil
        }
        if let preparation = uninstallPreparation {
            _ = service.cancelUninstall(preparation)
            uninstallPreparation = nil
        }
        updateOutcome = nil
        updateUnavailableReason = nil
        updatePreview = nil
        uninstallOutcome = nil
        uninstallUnavailableReason = nil
        uninstallPreview = nil
        // Keep one joined teardown task in the update slot so no new mutation can install while
        // either old pipeline is still finishing its bounded cleanup.
        uninstallPipeline = nil
        updatePipeline = Task { @MainActor [weak self] in
            await update?.value
            await uninstall?.value
            guard let self else { return }
            self.updatePipeline = nil
            self.isTearingDownMutation = false
            self.isPreparingUpdate = false
            self.isExecutingUpdate = false
            self.isPreparingUninstall = false
            self.isExecutingUninstall = false
            self.isCancelling = false
            self.phase = self.snapshot == nil ? .idle : .localReady
        }
    }

    // MARK: The pipeline

    /// Opens one action and awaits its single pipeline. A call that arrives while a pipeline owns
    /// the slot coalesces: the running action's phase and badges are left untouched.
    ///
    /// The caller that opened the pipeline owns its lifetime: cancelling the caller's task cancels
    /// this pipeline, so a SwiftUI `.task` disappearing stops the scan instead of leaving it
    /// running unattended. A cancelled action then settles without publishing: the slot is released,
    /// its identity is voided, and neither a partial snapshot nor a cancellation failure reaches the
    /// window. Cancellation itself is not a failure state — the caller's own task carries it.
    private func run(isInitialLaunch: Bool, isRescan: Bool, updateMode: UpdateProbeMode?) async {
        invalidatePendingUpdate()
        guard activePipeline == nil, updatePipeline == nil, uninstallPipeline == nil else { return }

        generation &+= 1
        let generation = generation
        // Every new action clears the previous verified update results and the previous failure
        // report BEFORE the scan: an old badge must never look like this action's result, and an old
        // error must not be presented as current while the new local facts are still loading.
        publishClearedUpdates()
        freshnessFailure = nil
        updateFailure = nil
        isCancelling = false
        phase = isInitialLaunch ? .loadingLocal : .checkingUpdates

        let service = self.service
        let pipeline = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runPipeline(
                generation: generation,
                isRescan: isRescan,
                updateMode: updateMode,
                service: service
            )
        }
        activePipeline = pipeline
        // The cancellation handler forwards THIS caller's cancellation to the pipeline it opened.
        // It runs synchronously on the cancelling thread and touches no actor state — `Task.cancel()`
        // is thread-safe and the pipeline observes it at its next suspension — so no isolated state
        // is accessed from `onCancel`.
        //
        // The join must stay reachable from a cancelled caller (otherwise the abandoned pipeline
        // would hold the slot). `Task<Void, Never>.value` is non-throwing — its failure type is
        // `Never` — so this action's non-throwing surface is preserved without a `try`/`catch`:
        // there is no error to absorb and none to rethrow, and a cancelled caller simply holds its
        // own cancellation from the task that was cancelled.
        await withTaskCancellationHandler {
            await pipeline.value
        } onCancel: {
            pipeline.cancel()
        }
        // The pipeline's own cancellation state is authoritative: it is set whether this
        // caller's task was cancelled (the window's `.task` went away) or the pipeline was
        // cancelled explicitly through `cancel()`. Reading only the caller's flag would leave
        // an explicitly cancelled action stuck in a loading phase.
        let cancelled = pipeline.isCancelled || Task.isCancelled
        // Only the owning action clears the slot; a superseded action cannot release a newer one.
        if generation == self.generation { activePipeline = nil }

        // A cancelled action settles by cancellation, never by failure: no obsolete snapshot and no
        // freshness error is published for it, and its identity is voided so a late completion from
        // the abandoned pipeline cannot publish either. There is nothing to rethrow — this action's
        // surface is non-throwing (the window's `.task` closure cannot throw) and the caller already
        // holds its own cancellation from the task that was cancelled.
        guard !cancelled else {
            invalidate(generation: generation)
            // Cancellation cleanup settles the visible phase rather than leaving the window
            // mid-load. An action cancelled before its local facts existed has nothing to show but
            // the initial state; one cancelled after they were published keeps them, because those
            // facts are still true and were already on screen.
            switch phase {
            case .loadingLocal, .checkingUpdates, .verifyingOwnership:
                phase = snapshot == nil ? .idle : .localReady
            case .idle, .localReady, .ready, .failed:
                break
            }
            return
        }
    }

    /// Cancels the action that currently owns the pipeline and waits for it, so a window going away
    /// leaves no scan running behind it and no snapshot from the cancelled action is published.
    /// Cancelling an idle view-model does nothing; it never starts a pipeline.
    public func cancel() async {
        if updatePipeline != nil {
            await cancelUpdate()
            return
        }
        if uninstallPipeline != nil {
            await cancelUninstall()
            return
        }
        guard let pipeline = activePipeline else { return }
        if phase == .verifyingOwnership { isCancelling = true }
        pipeline.cancel()
        await pipeline.value
    }

    /// Voids one action's identity. A pipeline that already observed the cancellation publishes
    /// nothing further, because every publication is guarded by the generation check.
    private func invalidate(generation: UInt64) {
        guard generation == self.generation else { return }
        self.generation &+= 1
    }

    /// The pipeline body. Every terminal path runs after the service call it started has returned,
    /// so nothing here abandons in-flight bounded scanning work: the service itself waits for its
    /// current bounded tool scan before reporting a cancellation.
    private func runPipeline(
        generation: UInt64,
        isRescan: Bool,
        updateMode: UpdateProbeMode?,
        service: InventoryService
    ) async {
        if Task.isCancelled || generation != self.generation { return }

        do {
            let local = isRescan
                ? try await service.refreshedLocalSnapshot()
                : try await service.localSnapshot()

            // Obsolete generations publish nothing at all — not even the local batch.
            guard generation == self.generation, !Task.isCancelled else { return }
            self.publish(local, updateFailure: nil)
            self.phase = .localReady
        } catch {
            // An obsolete action's error is not this action's error — and a cancellation is not a
            // failure at all: the abandoned action publishes no freshness error for the window.
            guard generation == self.generation, !Task.isCancelled else { return }
            self.freshnessFailure = Failure(error: error)
            self.phase = .failed
            return
        }

        guard let updateMode else {
            self.phase = .ready
            return
        }

        guard let local = snapshot else { return }
        self.phase = .checkingUpdates
        if Task.isCancelled || generation != self.generation { return }

        // The M6 probe reads the CURRENT session environment (the service's own rule), so Check and
        // Refresh act on exactly the environment the published local facts came from.
        let probed = await service.applyingUpdates(to: local, mode: updateMode)
        guard generation == self.generation, !Task.isCancelled else { return }

        // A neutral probe outcome is not a failure: M6 reports per-tool typed reasons, and those
        // reasons are exactly what the window must keep showing.
        self.publish(probed, updateFailure: nil)
        self.phase = .ready
    }

    /// Publishes a snapshot and reconciles selection by registry ID. The previous selected ID is
    /// preserved when it still exists; otherwise the first entry is chosen, or nil when the
    /// snapshot is empty.
    private func publish(_ snapshot: InventorySnapshot, updateFailure: Failure?) {
        self.snapshot = snapshot
        self.updateFailure = updateFailure
        self.freshnessFailure = nil
        reconcileSelection()
    }

    /// Clears every update badge while keeping the local facts: the entries stay exactly as
    /// published, with the update outcome removed. No other fact is touched.
    private func publishClearedUpdates() {
        guard let snapshot else { return }
        self.snapshot = InventorySnapshot(
            entries: snapshot.entries.map {
                InventoryEntry(
                    definition: $0.definition,
                    diagnostic: $0.diagnostic,
                    update: nil,
                    ownership: nil
                )
            },
            isDegradedEnvironment: snapshot.isDegradedEnvironment
        )
        reconcileSelection()
    }

    /// Publishes one verification result into exactly its own registry entry. Update results and
    /// every other entry are retained unchanged; a verification never rewrites local facts.
    private func publishOwnership(
        _ result: InstallationOwnershipResult,
        for registryID: String
    ) {
        guard let snapshot else { return }
        let entries = snapshot.entries.map { entry in
            guard entry.registryID == registryID else { return entry }
            return InventoryEntry(
                definition: entry.definition,
                diagnostic: entry.diagnostic,
                update: entry.update,
                ownership: result
            )
        }
        self.snapshot = InventorySnapshot(
            entries: entries,
            isDegradedEnvironment: snapshot.isDegradedEnvironment
        )
        reconcileSelection()
    }

    /// Clears one entry's ownership observation without changing its local facts. Used after a
    /// launched removal whose reconciliation could not publish a fresh snapshot.
    private func clearOwnership(for registryID: String) {
        guard let snapshot else { return }
        let entries = snapshot.entries.map { entry in
            guard entry.registryID == registryID else { return entry }
            return InventoryEntry(
                definition: entry.definition,
                diagnostic: entry.diagnostic,
                update: entry.update,
                ownership: nil
            )
        }
        self.snapshot = InventorySnapshot(
            entries: entries,
            isDegradedEnvironment: snapshot.isDegradedEnvironment
        )
        reconcileSelection()
    }

    /// Selection reconciliation, by ID only.
    private func reconcileSelection() {
        let entries = self.entries
        guard !entries.isEmpty else {
            selectedRegistryID = nil
            return
        }
        if let selectedRegistryID, entries.contains(where: { $0.registryID == selectedRegistryID }) {
            return
        }
        selectedRegistryID = entries.first?.registryID
    }

    /// The selected entry and canonical target, compared across the verification boundary so a
    /// late result can never attach to a retargeted or different installation.
    private struct ObservedSelection: Equatable {
        let entryPath: String
        let canonicalTarget: String?
    }

    private static func observedSelection(_ diagnostic: ToolPathDiagnostic) -> ObservedSelection? {
        switch diagnostic.selection {
        case .winner(let candidate), .offPath(let candidate, _):
            return ObservedSelection(
                entryPath: candidate.entryPath,
                canonicalTarget: candidate.canonicalTarget
            )
        case .notInstalled, .inconsistent:
            return nil
        }
    }

    /// Search matches the identity a user reads and the paths the diagnostics observed. Selection
    /// is never part of this predicate, so filtering cannot change it.
    private static func matches(_ entry: InventoryEntry, query: String) -> Bool {
        var haystack: [String] = [
            entry.definition.displayName,
            entry.definition.executableName,
            entry.registryID,
        ]
        if let entryPath = entry.diagnostic.detectedTool.entryPath { haystack.append(entryPath) }
        if let resolved = entry.diagnostic.detectedTool.resolvedPath { haystack.append(resolved) }
        for candidate in entry.diagnostic.pathCandidates {
            haystack.append(candidate.entryPath)
            if let target = candidate.canonicalTarget { haystack.append(target) }
        }
        switch entry.diagnostic.selection {
        case .winner(let candidate):
            haystack.append(candidate.entryPath)
        case .offPath(let candidate, let root):
            haystack.append(candidate.entryPath)
            haystack.append(root)
        case .notInstalled, .inconsistent:
            break
        }
        return haystack.contains { $0.lowercased().contains(query) }
    }
}