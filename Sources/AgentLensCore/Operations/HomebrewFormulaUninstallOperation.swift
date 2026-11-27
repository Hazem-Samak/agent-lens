// HomebrewFormulaUninstallOperation — confirmed, one-shot Homebrew formula uninstall (M13-D
// R5/R6/R8/R9).
//
// Preparation performs the same fresh ownership proof, manager-info observation and unscoped pin
// cross-check as Update, without reading or writing any metadata cache and without an update
// availability requirement: removal stays valid for deprecated, disabled or up-to-date formulae.
// Confirmation repeats the full observation after a fresh local scan, compares every bound fact,
// revalidates the live proof and owned operation root, then launches one literal `brew uninstall`
// argv. After a launch the operation always reconciles local and manager facts; exit zero alone is
// never success, and a remaining keg is reported as disclosed Homebrew residue.

import Darwin
import Foundation

/// The internal authorization evidence behind one public Uninstall preview. Never public, never
/// persisted.
struct HomebrewFormulaUninstallPlan: Sendable {
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
    /// The proven manager default-uninstall target bound at prepare time. Confirmation and the
    /// immediate pre-launch proof must re-observe this exact evidence.
    let removalTarget: HomebrewRemovalTarget
    let environment: ShellEnvironment
    let environmentFingerprint: String
    let currentDirectory: String
    let updateRunner: UpdateCommandRunner
    let root: NpmScratchRoot
    let arguments: [String]
    let preview: HomebrewFormulaUninstallPreview
}

/// An opaque Uninstall preparation. It has no public initializer and cannot be built from display
/// strings. It retains the owned operation root until cancelled or consumed by `execute`.
public final class HomebrewFormulaUninstallPreparation: @unchecked Sendable {
    public let preview: HomebrewFormulaUninstallPreview
    internal let plan: HomebrewFormulaUninstallPlan

    private let lock = NSLock()
    private var claimed = false
    private var released = false

    internal init(preview: HomebrewFormulaUninstallPreview, plan: HomebrewFormulaUninstallPlan) {
        self.preview = preview
        self.plan = plan
    }

    internal func claim() -> HomebrewFormulaUninstallPlan? {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed, !released else { return nil }
        claimed = true
        return plan
    }

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

/// The result of preparing one formula Uninstall.
public enum HomebrewFormulaUninstallPrepareResult: Sendable {
    case ready(HomebrewFormulaUninstallPreparation)
    case unavailable(HomebrewFormulaUninstallUnavailableReason)
}

/// The complete formula Uninstall result. Output is in-memory only and separate per stream.
public struct HomebrewFormulaUninstallOutcome: Equatable, Sendable {
    public let preview: HomebrewFormulaUninstallPreview
    public let state: OperationState
    public let stdout: Data
    public let stderr: Data
    public let stdoutTruncated: Bool
    public let stderrTruncated: Bool
    public let exitStatus: Int32?
    /// True only when the operation process was actually launched.
    public let processStarted: Bool
    public let reconciliation: HomebrewFormulaUninstallDelta?
    public let cleanupWarnings: [String]
    public let message: String?

    public var stdoutText: String { String(decoding: stdout, as: UTF8.self) }
    public var stderrText: String { String(decoding: stderr, as: UTF8.self) }
}

public enum HomebrewFormulaUninstallOperation {

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
    ) async -> HomebrewFormulaUninstallPrepareResult {
        // D-021 guard position: cancellation first, then accepted-operation containment, before any
        // observation, scratch claim or process.
        if Task.isCancelled { return .unavailable(.cancelled) }
        guard definition.acceptedOperations.contains(.homebrewFormulaUninstall) else {
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
        // Homebrew's literal `uninstall --formula <full_name>` re-resolves its own default keg.
        // Launch only when the manager's opt/linked/single-keg evidence proves that the keg it
        // will remove is exactly the selected, recorded keg. A mismatch, ambiguity, contradiction
        // or an unsupported latest-installed resolution refuses before scratch or process.
        guard case .proven(let removalTarget) = observation.removalTarget,
              removalTarget.keg == observation.keg
        else { return .unavailable(.uninstallRemovalTargetUnverified) }

        guard let base = NpmScratchBase(url: scratchBase),
              let root = NpmScratchRoot.claim(base: base)
        else { return .unavailable(.operationRootUnsafe) }
        if Task.isCancelled {
            _ = releaseOperationRoot(root)
            return .unavailable(.cancelled)
        }

        let arguments = uninstallArguments(fullName: observation.fullName)
        let preview = HomebrewFormulaUninstallPreview(
            registryID: definition.id,
            displayName: definition.displayName,
            kind: .formula,
            formulaName: observation.formulaName,
            fullName: observation.fullName,
            selectedEntryPath: observation.selectedEntryPath,
            selectedTarget: observation.selectedTarget,
            selectedKegVersion: observation.selectedKegVersion,
            installedKegs: observation.installedKegs,
            remainingKegDisclosure: homebrewFormulaRemainingKegDisclosure,
            dependentRefusalDisclosure: homebrewFormulaDependentRefusalDisclosure,
            managerPath: observation.manager.entryPath,
            prefix: observation.prefix.canonicalPath,
            cellar: observation.cellar.canonicalPath,
            workingDirectory: root.url.path,
            executablePath: observation.manager.entryPath,
            arguments: arguments,
            timeoutSeconds: Int(homebrewMutationTimeout),
            effect: homebrewFormulaUninstallEffectText
        )
        let plan = HomebrewFormulaUninstallPlan(
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
            removalTarget: removalTarget,
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
        return .ready(HomebrewFormulaUninstallPreparation(preview: preview, plan: plan))
    }

    /// Cancels a pending preview and releases only its owned root.
    @discardableResult
    public static func cancel(_ preparation: HomebrewFormulaUninstallPreparation) -> Bool {
        preparation.releaseUnconsumed()
    }

    /// Consumes a confirmed preparation and launches at most one literal `brew uninstall`.
    public static func execute(
        confirmed preparation: HomebrewFormulaUninstallPreparation,
        environment: ShellEnvironment,
        scan: @escaping @Sendable (DetectorDefinition, ShellEnvironment, String) -> ToolPathDiagnostic?,
        reconcileAfterLaunch: @escaping @Sendable (DetectorDefinition) async -> (ToolPathDiagnostic, ShellEnvironment)?,
        updateRunner: UpdateCommandRunner,
        operationRunner: OperationCommandRunner,
        gate: OperationExecutionGate,
        uptime: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
    ) async -> HomebrewFormulaUninstallOutcome {
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
            reconciliation: HomebrewFormulaUninstallDelta? = nil,
            cleanupWarnings: [String] = [],
            message: String? = nil
        ) async -> HomebrewFormulaUninstallOutcome {
            var warnings = cleanupWarnings
            if !releaseOperationRoot(plan.root) {
                warnings.append("The owned operation scratch root could not be removed safely.")
            }
            await gate.release()
            return HomebrewFormulaUninstallOutcome(
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
                    ? "The uninstall was cancelled before launch."
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
                message = "The uninstall was cancelled before launch."
            default:
                message = "Fresh confirmation failed: \(map(failure).message)"
            }
            return await finish(state: state, processStarted: false, message: message)
        case .success(let value):
            confirmed = value
        }

        guard confirmed.selection == plan.selection,
              confirmed.manager == plan.manager,
              confirmed.prefix == plan.prefix,
              confirmed.installation == plan.installation,
              confirmed.formulaName == plan.formulaName,
              confirmed.fullName == plan.fullName,
              confirmed.selectedKegVersion == plan.selectedKegVersion,
              confirmed.installedKegs == plan.installedKegs,
              confirmed.pinned == false
        else {
            return await finish(
                state: .failed, processStarted: false,
                message: "A bound formula identity or manager fact changed; a new preview is required."
            )
        }
        // The manager's default removal target must still be the exact bound keg. This catches a
        // retargeted opt/linked link even when the selected executable did not change.
        guard case .proven(let confirmedTarget) = confirmed.removalTarget,
              confirmedTarget == plan.removalTarget
        else {
            return await finish(
                state: .failed, processStarted: false,
                message: "Homebrew's default uninstall target changed; a new preview is required."
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
        guard homebrewRemovalTargetIsLive(
            prefix: plan.prefix,
            cellar: plan.cellar,
            formulaName: plan.formulaName,
            installedKegs: plan.installedKegs,
            selectedKegVersion: plan.selectedKegVersion,
            selectedKeg: plan.keg,
            expected: plan.removalTarget
        ) else {
            return await finish(
                state: .failed, processStarted: false,
                message: "Homebrew's default uninstall target changed immediately before launch; no mutation was started."
            )
        }
        guard uptime() < deadline, !Task.isCancelled else {
            return await finish(
                state: Task.isCancelled ? .cancelled : .failed, processStarted: false,
                message: Task.isCancelled
                    ? "The uninstall was cancelled before launch."
                    : "Confirmation revalidation exceeded its read-only budget."
            )
        }

        let operationEnvironment = HomebrewOperationEnvironment.mutationEnvironment(
            from: plan.environment, kind: .formulaUninstall
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
                    ? "The uninstall was cancelled before the process launched."
                    : "The Homebrew process could not be launched; no mutation retry was attempted."
            )
        }

        var warnings: [String] = []
        if processResult.cleanupWarning {
            warnings.append("The Homebrew process group could not be fully reaped within the cleanup bound.")
        }
        let reconciliation: HomebrewFormulaUninstallDelta?
        if let fresh = await reconcileAfterLaunch(plan.definition) {
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
        if let reconciliation {
            if interrupted {
                state = .interrupted
            } else if let exitStatus = processResult.exitStatus {
                if exitStatus == 0 {
                    state = (reconciliation.recordedKegAbsent
                        && reconciliation.selectedTargetReleased
                        && !reconciliation.observationFailed)
                        ? .succeeded : .uncertain
                } else {
                    state = .failed
                }
            } else {
                state = .uncertain
            }
        } else {
            state = .uncertain
        }

        let cleaned = releaseOperationRoot(plan.root)
        if !cleaned {
            warnings.append("The owned operation scratch root could not be removed safely.")
        }
        await gate.release()
        return HomebrewFormulaUninstallOutcome(
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

    private enum KegRemovalObservation: Equatable {
        case present(DirectoryIdentity)
        case absent
        case failed
    }

    private enum EntryRemovalObservation: Equatable {
        case stillPresent
        case released
        case dangling
        case absent
        case failed
    }

    /// Distinguishes a genuinely absent recorded keg directory from an unreadable or raced
    /// observation. Only `lstat` ENOENT/ENOTDIR is absence.
    private static func observeKegRemoval(path: String) -> KegRemovalObservation {
        var info = Darwin.stat()
        let lstatResult = path.withCString { Darwin.lstat($0, &info) }
        if lstatResult == 0 {
            guard let identity = FileIdentityObserver.observeDirectory(path: path) else {
                return .failed
            }
            return .present(identity)
        }
        let code = errno
        return (code == ENOENT || code == ENOTDIR) ? .absent : .failed
    }

    /// Distinguishes a released selected entry from a still-live target, a dangling residue, and an
    /// unreadable observation. Only `lstat` ENOENT/ENOTDIR is absence.
    private static func observeEntryRemoval(
        path: String,
        oldTarget: String
    ) -> EntryRemovalObservation {
        var info = Darwin.stat()
        let lstatResult = path.withCString { Darwin.lstat($0, &info) }
        if lstatResult == 0 {
            if let observed = FileIdentityObserver.observeExecutable(entryPath: path) {
                return observed.canonicalTarget == oldTarget ? .stillPresent : .released
            }
            if (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFLNK) {
                var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
                let count = path.withCString { Darwin.readlink($0, &buffer, buffer.count) }
                if count > 0, count < buffer.count {
                    let targetText = String(
                        decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
                        as: UTF8.self
                    )
                    let parent = (path as NSString).deletingLastPathComponent
                    let target = targetText.hasPrefix("/")
                        ? targetText : parent + "/" + targetText
                    var targetInfo = Darwin.stat()
                    let targetResult = target.withCString { Darwin.lstat($0, &targetInfo) }
                    if targetResult != 0, errno == ENOENT { return .dangling }
                }
            }
            return .failed
        }
        let code = errno
        return (code == ENOENT || code == ENOTDIR) ? .absent : .failed
    }

    private static func reconcile(
        plan: HomebrewFormulaUninstallPlan,
        diagnostic after: ToolPathDiagnostic,
        environment: ShellEnvironment
    ) async -> (HomebrewFormulaUninstallDelta?, [String]) {
        let afterSelection = homebrewFormulaSelectionPair(after)
        let (ownership, ownershipWarning) = await reconcileOwnership(
            plan: plan, diagnostic: after, environment: environment
        )
        let kegObservation = observeKegRemoval(path: plan.keg.canonicalPath)
        let entryObservation = observeEntryRemoval(
            path: plan.selectedEntryPath, oldTarget: plan.selectedTarget
        )

        let recordedKegAbsent: Bool
        let recordedKegReplaced: Bool
        switch kegObservation {
        case .absent:
            recordedKegAbsent = true
            recordedKegReplaced = false
        case .present(let identity):
            recordedKegAbsent = false
            recordedKegReplaced = identity != plan.keg
        case .failed:
            recordedKegAbsent = false
            recordedKegReplaced = false
        }
        let selectedTargetReleased = entryObservation == .released
            || entryObservation == .dangling
            || entryObservation == .absent
        let selectedEntryResidue = entryObservation == .dangling

        var remainingKegs: [String]?
        var infoFailed = false
        switch await HomebrewFormulaObservation.query(
            manager: plan.manager,
            arguments: ["info", "--json=v2", "--formula", plan.fullName],
            environment: environment,
            runner: plan.updateRunner
        ) {
        case .failure:
            infoFailed = true
        case .success(let data):
            if let kegs = HomebrewFormulaObservation.installedKegs(
                fromInfo: data, fullName: plan.fullName, formulaName: plan.formulaName
            ) {
                remainingKegs = kegs
            } else {
                infoFailed = true
            }
        }

        let afterKegVersion = selectedKegVersion(
            afterSelection, cellar: plan.cellar.canonicalPath, formula: plan.formulaName
        )
        let observationFailed = infoFailed
            || kegObservation == .failed
            || entryObservation == .failed
            || (afterSelection != nil && afterKegVersion == nil)
        let beforeSelection = homebrewFormulaSelectionPair(plan.diagnostic)

        let delta = HomebrewFormulaUninstallDelta(
            beforeSelectedKegVersion: plan.selectedKegVersion,
            afterSelectedKegVersion: afterKegVersion,
            beforeInstalledKegs: plan.installedKegs,
            afterInstalledKegs: remainingKegs,
            recordedKegAbsent: recordedKegAbsent,
            recordedKegReplaced: recordedKegReplaced,
            selectedTargetReleased: selectedTargetReleased,
            selectedEntryResidue: selectedEntryResidue,
            observationFailed: observationFailed,
            remainingKegs: remainingKegs,
            formulaStillInstalledViaRemainingKeg: remainingKegs.map { !$0.isEmpty },
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
            ownership: ownership
        )
        return (delta, ownershipWarning.map { [$0] } ?? [])
    }

    private static func reconcileOwnership(
        plan: HomebrewFormulaUninstallPlan,
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

    /// The only dynamic argv element is the manager-returned full identity. Uninstall has no
    /// `--yes` (there is no ask prompt), and `--force`, `--zap`, `--ignore-dependencies`, `--all`,
    /// `--dry-run` and a second target are impossible by construction.
    static func uninstallArguments(fullName: String) -> [String] {
        ["uninstall", "--formula", fullName]
    }

    private static func map(
        _ failure: HomebrewFormulaObservationFailure
    ) -> HomebrewFormulaUninstallUnavailableReason {
        switch failure {
        case .noVerifiedSelection: .noVerifiedSelection
        case .managerUnavailable: .managerUnavailable
        case .unsupportedManager: .unsupportedManager
        case .identityUnverified: .identityUnverified
        case .managerPrefixUnverified: .managerPrefixUnverified
        case .pinned: .pinned
        case .metadataInvalid: .probeFailed
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
            "The uninstall was cancelled before the process launched; no mutation was reported."
        case .failed:
            "Homebrew exited nonzero; the measured delta is reported without a rollback claim."
        case .interrupted:
            "The Homebrew process was interrupted; reconciliation is reported without a rollback claim."
        case .uncertain:
            interrupted
                ? "The Homebrew process was interrupted and the result could not be confirmed from fresh facts."
                : "The Homebrew process completed, but removal could not be proven from fresh facts."
        }
    }

    private static func noProcessOutcome(
        preview: HomebrewFormulaUninstallPreview,
        state: OperationState,
        message: String,
        cleanupOK: Bool
    ) -> HomebrewFormulaUninstallOutcome {
        HomebrewFormulaUninstallOutcome(
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
