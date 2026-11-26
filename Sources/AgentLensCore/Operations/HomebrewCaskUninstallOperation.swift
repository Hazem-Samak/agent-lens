// HomebrewCaskUninstallOperation — confirmed, one-shot Homebrew cask uninstall (M13-E
// R5/R6/R7/R8/R9).
//
// Preparation performs the same fresh cask ownership proof, exact info/artifacts observation,
// saved installed definition/receipt proof and unscoped pin cross-check as Update, without an
// update-availability requirement and without refusing disabled, auto-updating, `latest` or
// comma-version casks: removal stays valid. Artifact support class, pins, saved teardown evidence
// and every bound identity are still enforced. Confirmation repeats the full observation after a
// fresh local scan, compares every bound fact, revalidates the live proof and owned operation root,
// then launches one literal `brew uninstall --cask` argv. After a launch the operation always
// reconciles the fresh manager record, the original Caskroom token directory, the selection and
// every previewed managed target from the safe installed scope; exit zero alone is never success.

import Darwin
import Foundation

/// The internal authorization evidence behind one public cask Uninstall preview. Never public, never
/// persisted.
struct HomebrewCaskUninstallPlan: Sendable {
    let definition: DetectorDefinition
    let diagnostic: ToolPathDiagnostic
    let selectedEntryPath: String
    let selectedTarget: String
    let selection: ObservedExecutable
    let manager: ObservedExecutable
    let installation: VerifiedInstallation
    let token: String
    let fullToken: String
    let tap: String
    let prefixRoot: HomebrewCaskBoundRoot
    let caskroomRoot: HomebrewCaskBoundRoot
    let tokenDirectory: HomebrewCaskBoundDirectory
    let versionDirectory: HomebrewCaskBoundDirectory
    let installedVersion: String
    let pinned: Bool
    let deprecated: Bool
    let deprecationDisclosure: String?
    let artifacts: HomebrewCaskArtifactSet
    /// Current-source targets, bound for confirm-time comparison.
    let currentManagedTargets: [HomebrewCaskManagedTarget]
    /// Installed targets from Homebrew's saved metadata. Reconciliation uses this scope, never the
    /// current manifest.
    let managedTargets: [HomebrewCaskManagedTarget]
    let installedMetadata: HomebrewCaskInstalledMetadata
    let environment: ShellEnvironment
    let environmentFingerprint: String
    let currentDirectory: String
    let updateRunner: UpdateCommandRunner
    let root: NpmScratchRoot
    let arguments: [String]
    let preview: HomebrewCaskUninstallPreview
}

/// An opaque cask Uninstall preparation. It has no public initializer and cannot be built from
/// display strings. It retains the owned operation root until cancelled or consumed by `execute`.
public final class HomebrewCaskUninstallPreparation: @unchecked Sendable {
    public let preview: HomebrewCaskUninstallPreview
    internal let plan: HomebrewCaskUninstallPlan

    private let lock = NSLock()
    private var claimed = false
    private var released = false

    internal init(preview: HomebrewCaskUninstallPreview, plan: HomebrewCaskUninstallPlan) {
        self.preview = preview
        self.plan = plan
    }

    internal func claim() -> HomebrewCaskUninstallPlan? {
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

/// The result of preparing one cask Uninstall.
public enum HomebrewCaskUninstallPrepareResult: Sendable {
    case ready(HomebrewCaskUninstallPreparation)
    case unavailable(HomebrewCaskUninstallUnavailableReason)
}

/// The complete cask Uninstall result. Output is in-memory only and separate per stream.
public struct HomebrewCaskUninstallOutcome: Equatable, Sendable {
    public let preview: HomebrewCaskUninstallPreview
    public let state: OperationState
    public let stdout: Data
    public let stderr: Data
    public let stdoutTruncated: Bool
    public let stderrTruncated: Bool
    public let exitStatus: Int32?
    /// True only when the operation process was actually launched.
    public let processStarted: Bool
    public let reconciliation: HomebrewCaskUninstallDelta?
    public let cleanupWarnings: [String]
    public let message: String?

    public var stdoutText: String { String(decoding: stdout, as: UTF8.self) }
    public var stderrText: String { String(decoding: stderr, as: UTF8.self) }
}

public enum HomebrewCaskUninstallOperation {

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
    ) async -> HomebrewCaskUninstallPrepareResult {
        // D-021 guard position: cancellation first, then accepted-operation containment, before any
        // observation, scratch claim or process.
        if Task.isCancelled { return .unavailable(.cancelled) }
        guard definition.acceptedOperations.contains(.homebrewCaskUninstall) else {
            return .unavailable(.operationNotAccepted)
        }
        let deadline = uptime() &+ preparationBudgetNanoseconds
        guard let scratchBase = homebrewCaskScratchBase(
            environment: environment,
            operationRootBaseURL: operationRootBaseURL
        ) else { return .unavailable(.operationRootUnsafe) }

        let facts: HomebrewCaskFacts
        switch await HomebrewCaskObservation.observe(
            definition: definition,
            diagnostic: diagnostic,
            environment: environment,
            runner: runner,
            currentDirectory: currentDirectory,
            uptime: uptime,
            stageDeadline: deadline,
            mode: .uninstall
        ) {
        case .unavailable(let failure):
            return .unavailable(map(failure))
        case .success(let value):
            facts = value
        }
        if Task.isCancelled { return .unavailable(.cancelled) }
        guard HomebrewCaskProofIdentity.isSafeProofName(
            token: facts.token, fullToken: facts.fullToken, tap: facts.tap
        ) else { return .unavailable(.identityUnverified) }

        guard let base = NpmScratchBase(url: scratchBase),
              let root = NpmScratchRoot.claim(base: base)
        else { return .unavailable(.operationRootUnsafe) }
        if Task.isCancelled {
            _ = releaseOperationRoot(root)
            return .unavailable(.cancelled)
        }

        let arguments = uninstallArguments(fullToken: facts.fullToken)
        let preview = HomebrewCaskUninstallPreview(
            registryID: definition.id,
            displayName: definition.displayName,
            kind: .cask,
            token: facts.token,
            fullToken: facts.fullToken,
            tap: facts.tap,
            selectedEntryPath: facts.selectedEntryPath,
            selectedTarget: facts.selectedTarget,
            installedVersion: facts.installedVersion,
            deprecated: facts.deprecated,
            deprecationDisclosure: facts.deprecationDisclosure,
            artifactTargets: facts.previewTargets,
            artifactScopeDisclosure: homebrewCaskUninstallArtifactScopeDisclosure,
            companionAppDisclosure: homebrewCaskCompanionAppDisclosure,
            zapDeclared: facts.artifacts.hasZap
                || facts.installedMetadata.artifacts.hasZap,
            zapDisclosure: homebrewCaskZapExclusionDisclosure,
            managerPath: facts.manager.entryPath,
            prefix: facts.prefixRoot.canonicalPath,
            caskroom: facts.caskroomRoot.canonicalPath,
            workingDirectory: root.url.path,
            executablePath: facts.manager.entryPath,
            arguments: arguments,
            timeoutSeconds: Int(homebrewMutationTimeout),
            effect: homebrewCaskUninstallEffectText
        )
        let plan = HomebrewCaskUninstallPlan(
            definition: definition,
            diagnostic: diagnostic,
            selectedEntryPath: facts.selectedEntryPath,
            selectedTarget: facts.selectedTarget,
            selection: facts.selection,
            manager: facts.manager,
            installation: facts.installation,
            token: facts.token,
            fullToken: facts.fullToken,
            tap: facts.tap,
            prefixRoot: facts.prefixRoot,
            caskroomRoot: facts.caskroomRoot,
            tokenDirectory: facts.tokenDirectory,
            versionDirectory: facts.versionDirectory,
            installedVersion: facts.installedVersion,
            pinned: facts.pinned,
            deprecated: facts.deprecated,
            deprecationDisclosure: facts.deprecationDisclosure,
            artifacts: facts.artifacts,
            currentManagedTargets: facts.managedTargets,
            managedTargets: facts.installedMetadata.managedTargets,
            installedMetadata: facts.installedMetadata,
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
        return .ready(HomebrewCaskUninstallPreparation(preview: preview, plan: plan))
    }

    /// Cancels a pending preview and releases only its owned root.
    @discardableResult
    public static func cancel(_ preparation: HomebrewCaskUninstallPreparation) -> Bool {
        preparation.releaseUnconsumed()
    }

    /// Consumes a confirmed preparation and launches at most one literal `brew uninstall --cask`.
    public static func execute(
        confirmed preparation: HomebrewCaskUninstallPreparation,
        environment: ShellEnvironment,
        scan: @escaping @Sendable (DetectorDefinition, ShellEnvironment, String) -> ToolPathDiagnostic?,
        reconcileAfterLaunch: @escaping @Sendable (DetectorDefinition) async -> (ToolPathDiagnostic, ShellEnvironment)?,
        updateRunner: UpdateCommandRunner,
        operationRunner: OperationCommandRunner,
        gate: OperationExecutionGate,
        uptime: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
    ) async -> HomebrewCaskUninstallOutcome {
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
            reconciliation: HomebrewCaskUninstallDelta? = nil,
            cleanupWarnings: [String] = [],
            message: String? = nil
        ) async -> HomebrewCaskUninstallOutcome {
            var warnings = cleanupWarnings
            if !releaseOperationRoot(plan.root) {
                warnings.append("The owned operation scratch root could not be removed safely.")
            }
            await gate.release()
            return HomebrewCaskUninstallOutcome(
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
        guard let freshSelection = homebrewCaskSelectionPair(freshDiagnostic),
              freshSelection.entry == plan.selectedEntryPath,
              freshSelection.target == plan.selectedTarget
        else {
            return await finish(
                state: .failed, processStarted: false,
                message: "The selected installation changed; a new preview is required."
            )
        }

        let confirmed: HomebrewCaskFacts
        switch await HomebrewCaskObservation.observe(
            definition: plan.definition,
            diagnostic: freshDiagnostic,
            environment: plan.environment,
            runner: updateRunner,
            currentDirectory: plan.currentDirectory,
            uptime: uptime,
            stageDeadline: deadline,
            mode: .uninstall
        ) {
        case .unavailable(let failure):
            let state: OperationState = Task.isCancelled ? .cancelled : .failed
            let message: String
            switch failure {
            case .pinned:
                message = "The cask is now pinned; a new preview is required."
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
              confirmed.installation == plan.installation,
              confirmed.token == plan.token,
              confirmed.fullToken == plan.fullToken,
              confirmed.tap == plan.tap,
              confirmed.prefixRoot == plan.prefixRoot,
              confirmed.caskroomRoot == plan.caskroomRoot,
              confirmed.tokenDirectory == plan.tokenDirectory,
              confirmed.versionDirectory == plan.versionDirectory,
              confirmed.installedVersion == plan.installedVersion,
              confirmed.pinned == plan.pinned,
              confirmed.deprecated == plan.deprecated,
              confirmed.deprecationDisclosure == plan.deprecationDisclosure,
              confirmed.artifacts == plan.artifacts,
              confirmed.managedTargets == plan.currentManagedTargets,
              confirmed.installedMetadata == plan.installedMetadata
        else {
            return await finish(
                state: .failed, processStarted: false,
                message: "A bound cask identity, artifact or manager fact changed; a new preview is required."
            )
        }
        guard plan.root.isLive() else {
            return await finish(
                state: .failed, processStarted: false,
                message: "The owned operation root changed during confirmation; a new preview is required."
            )
        }
        guard homebrewCaskProofIsLive(
            roots: HomebrewCaskBoundRoots(
                prefix: plan.prefixRoot, caskroom: plan.caskroomRoot
            ),
            manager: plan.manager,
            selection: plan.selection
        ), plan.tokenDirectory.isCurrent(parent: plan.caskroomRoot.identity),
           plan.versionDirectory.isCurrent(parent: plan.tokenDirectory.identity),
           homebrewCaskIsRegularFile(plan.selectedTarget),
           plan.currentManagedTargets.allSatisfy({
               HomebrewCaskObservation.managedTargetIsLive($0)
           }),
           HomebrewCaskObservation.installedMetadataIsLive(
               plan.installedMetadata,
               caskroom: plan.caskroomRoot,
               tokenDirectory: plan.tokenDirectory,
               stagedVersionDirectory: plan.versionDirectory,
               token: plan.token,
               fullToken: plan.fullToken,
               tap: plan.tap,
               installedVersion: plan.installedVersion,
               prefix: plan.prefixRoot
           ),
           plan.managedTargets.allSatisfy({
               HomebrewCaskObservation.managedTargetIsLive($0)
           })
        else {
            return await finish(
                state: .failed, processStarted: false,
                message: "The live Homebrew cask proof changed immediately before launch; no mutation was started."
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
            from: plan.environment, kind: .caskUninstall
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
        let reconciliation: HomebrewCaskUninstallDelta?
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
                    state = reconcilesAsSuccess(reconciliation) ? .succeeded : .uncertain
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
        return HomebrewCaskUninstallOutcome(
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

    private enum InstalledPresence: Equatable {
        case absent
        case installed(String)
        case unknown
    }

    private enum TokenDirectoryObservation: Equatable {
        case absent
        case present(DirectoryIdentity)
        case failed
    }

    private enum EntryObservation: Equatable {
        case stillPresent
        case released
        case dangling
        case absent
        case failed
    }

    /// Success is never inferred from exit zero: the exact original token directory must be absent,
    /// fresh manager metadata must report the exact token as not installed, and the selection and
    /// every previewed linked target must be released. Zap paths are never inspected.
    private static func reconcilesAsSuccess(_ delta: HomebrewCaskUninstallDelta) -> Bool {
        !delta.observationFailed
            && delta.infoInstalledAbsent
            && delta.tokenDirectoryAbsent
            && !delta.tokenDirectoryReplaced
            && delta.selectedTargetReleased
            && delta.managedTargetsReleased
    }

    static func reconcile(
        plan: HomebrewCaskUninstallPlan,
        diagnostic after: ToolPathDiagnostic,
        environment: ShellEnvironment
    ) async -> (HomebrewCaskUninstallDelta?, [String]) {
        let afterSelection = homebrewCaskSelectionPair(after)
        let (ownership, ownershipWarning) = await homebrewCaskReconcileOwnership(
            definition: plan.definition,
            diagnostic: after,
            environment: environment,
            runner: plan.updateRunner,
            currentDirectory: plan.currentDirectory
        )

        let roots: HomebrewCaskBoundRoots?
        switch await HomebrewCaskObservation.observeRoots(
            manager: plan.manager,
            selection: nil,
            environment: environment,
            runner: plan.updateRunner
        ) {
        case .failure:
            roots = nil
        case .success(let value):
            roots = value
        }
        let rootsMatch = roots.map {
            $0.prefix == plan.prefixRoot && $0.caskroom == plan.caskroomRoot
        } ?? false

        let presence = await installedPresence(
            plan: plan, environment: environment
        )
        let infoInstalledAbsent = presence == .absent
        let afterInstalledVersion: String?
        switch presence {
        case .installed(let value): afterInstalledVersion = value
        case .absent, .unknown: afterInstalledVersion = nil
        }

        let tokenDirectory = observeTokenDirectoryRemoval(
            path: plan.tokenDirectory.identity.canonicalPath
        )
        let tokenDirectoryAbsent = tokenDirectory == .absent
        let tokenDirectoryReplaced: Bool
        if case .present(let identity) = tokenDirectory {
            tokenDirectoryReplaced = identity != plan.tokenDirectory.identity
        } else {
            tokenDirectoryReplaced = false
        }
        let entry = observeEntryRemoval(
            path: plan.selectedEntryPath, oldTarget: plan.selectedTarget
        )
        let selectedTargetReleased = entry == .released
            || entry == .dangling
            || entry == .absent
        let selectedEntryResidue = entry == .dangling
        let managedTargets = plan.managedTargets.map { observeManagedTargetRelease($0) }

        // The last async manager read has completed. Re-check the recorded manager and both roots
        // so a stale pre-query observation can never become a success fact.
        let managerCurrent = homebrewCaskManagerIsLive(plan.manager)
        let rootsCurrent = roots.map {
            $0.prefix.isCurrent && $0.caskroom.isCurrent
        } ?? false

        let observationFailed = roots == nil
            || !rootsMatch
            || !managerCurrent
            || !rootsCurrent
            || presence == .unknown
            || tokenDirectory == .failed
            || entry == .failed
            || managedTargets.contains { $0.release == .observationFailed }
        let beforeSelection = homebrewCaskSelectionPair(plan.diagnostic)

        let delta = HomebrewCaskUninstallDelta(
            beforeInstalledVersion: plan.installedVersion,
            afterInstalledVersion: afterInstalledVersion,
            infoInstalledAbsent: infoInstalledAbsent,
            tokenDirectoryAbsent: tokenDirectoryAbsent,
            tokenDirectoryReplaced: tokenDirectoryReplaced,
            selectedTargetReleased: selectedTargetReleased,
            selectedEntryResidue: selectedEntryResidue,
            managedTargets: managedTargets,
            beforeEntryPath: beforeSelection?.entry ?? plan.selectedEntryPath,
            afterEntryPath: afterSelection?.entry,
            beforeTarget: beforeSelection?.target ?? plan.selectedTarget,
            afterTarget: afterSelection?.target,
            beforeAliases: homebrewCaskAliases(plan.diagnostic),
            afterAliases: homebrewCaskAliases(after),
            beforeShadowedCount: plan.diagnostic.shadowedInstallationCount ?? 0,
            afterShadowedCount: after.shadowedInstallationCount ?? 0,
            beforeInstallState: plan.diagnostic.detectedTool.state,
            afterInstallState: after.detectedTool.state,
            ownership: ownership,
            observationFailed: observationFailed
        )
        return (delta, ownershipWarning.map { [$0] } ?? [])
    }

    private static func installedPresence(
        plan: HomebrewCaskUninstallPlan,
        environment: ShellEnvironment
    ) async -> InstalledPresence {
        switch await HomebrewCaskObservation.query(
            manager: plan.manager,
            arguments: ["info", "--json=v2", "--cask", plan.fullToken],
            environment: environment,
            runner: plan.updateRunner
        ) {
        case .failure:
            return .unknown
        case .success(let data):
            guard let records = HomebrewCaskObservation.parseInfo(data) else {
                return .unknown
            }
            if records.isEmpty { return .absent }
            guard records.count == 1, let record = records.first,
                  record.token == plan.token,
                  record.fullToken == plan.fullToken,
                  record.tap == plan.tap,
                  HomebrewCaskUpdateProbe.isStructurallyValidCask(
                    token: record.token, fullToken: record.fullToken, tap: record.tap
                  )
            else { return .unknown }
            switch record.installed {
            case .null: return .absent
            case .string(let value): return .installed(value)
            case .missing, .malformed: return .unknown
            }
        }
    }

    private static func observeTokenDirectoryRemoval(
        path: String
    ) -> TokenDirectoryObservation {
        var info = Darwin.stat()
        let status = path.withCString { Darwin.lstat($0, &info) }
        if status != 0 {
            let code = errno
            return (code == ENOENT || code == ENOTDIR) ? .absent : .failed
        }
        guard let identity = FileIdentityObserver.observeDirectory(path: path) else {
            return .failed
        }
        return .present(identity)
    }

    /// Distinguishes a released selected entry from a still-live target, a dangling residue, and an
    /// unreadable observation. Only `lstat` ENOENT/ENOTDIR is absence.
    private static func observeEntryRemoval(
        path: String,
        oldTarget: String
    ) -> EntryObservation {
        var info = Darwin.stat()
        let status = path.withCString { Darwin.lstat($0, &info) }
        if status == 0 {
            if let observed = FileIdentityObserver.observeExecutable(entryPath: path) {
                return observed.canonicalTarget == oldTarget ? .stillPresent : .released
            }
            if (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFLNK) {
                let destination = homebrewCaskReadLink(path)
                if let destination,
                   !FileManager.default.fileExists(atPath: destination) {
                    return homebrewCaskPathsEqual(destination, oldTarget)
                        ? .dangling : .released
                }
            }
            return .failed
        }
        let code = errno
        return (code == ENOENT || code == ENOTDIR) ? .absent : .failed
    }

    /// Each previewed linked target must be released. A link to a different destination is a
    /// successor, not this cask's residue; a wrong-type object or unreadable path is uncertain.
    private static func observeManagedTargetRelease(
        _ managed: HomebrewCaskManagedTarget
    ) -> HomebrewCaskManagedTargetDelta {
        let result: HomebrewCaskManagedTargetRelease
        switch managed.presence {
        case .absent:
            // A path absent at preview imposes no after-fact only while it is still absent. Any
            // occupancy afterward is unexplained by this removal and is never a clean result.
            var info = Darwin.stat()
            let status = managed.artifact.target.withCString { Darwin.lstat($0, &info) }
            if status != 0 {
                let code = errno
                result = (code == ENOENT || code == ENOTDIR)
                    ? .absentAtPreview : .observationFailed
            } else if (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFLNK),
                      let destination = homebrewCaskReadLink(managed.artifact.target),
                      homebrewCaskPathsEqual(destination, managed.sourcePath) {
                result = .stillPresent
            } else {
                result = .occupiedAfterAbsentPreview
            }
        case .linked:
            result = observeRelease(
                path: managed.artifact.target,
                sourcePath: managed.sourcePath
            )
        }
        return HomebrewCaskManagedTargetDelta(
            kind: managed.artifact.kind,
            target: managed.artifact.target,
            release: result
        )
    }

    private static func observeRelease(
        path: String,
        sourcePath: String
    ) -> HomebrewCaskManagedTargetRelease {
        var info = Darwin.stat()
        let status = path.withCString { Darwin.lstat($0, &info) }
        if status != 0 {
            let code = errno
            return (code == ENOENT || code == ENOTDIR) ? .released : .observationFailed
        }
        guard (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFLNK) else {
            return .observationFailed
        }
        if let observed = FileIdentityObserver.observeExecutable(entryPath: path) {
            return homebrewCaskPathsEqual(observed.canonicalTarget, sourcePath)
                ? .stillPresent : .successor
        }
        // A dangling link can still be this cask's own residue (the staged source is gone). A
        // dangling link to a different destination is an unrelated successor, not our residue.
        guard let destination = homebrewCaskReadLink(path) else {
            return .observationFailed
        }
        return homebrewCaskPathsEqual(destination, sourcePath)
            ? .stillPresent : .successor
    }

    // MARK: - Preview/argv helpers

    /// The only dynamic argv element is the manager-returned full token. Uninstall has no `--yes`
    /// (there is no ask prompt), and `--force`, `--zap`, `--ignore-dependencies`, `--all`,
    /// `--dry-run`, `--formula` and a second target are impossible by construction.
    static func uninstallArguments(fullToken: String) -> [String] {
        ["uninstall", "--cask", fullToken]
    }

    private static func map(
        _ failure: HomebrewCaskObservationFailure
    ) -> HomebrewCaskUninstallUnavailableReason {
        switch failure {
        case .noVerifiedSelection: .noVerifiedSelection
        case .managerUnavailable: .managerUnavailable
        case .unsupportedManager: .unsupportedManager
        case .identityUnverified: .identityUnverified
        case .managerPrefixUnverified: .managerPrefixUnverified
        case .caskroomUnverified: .caskroomUnverified
        case .pinned: .pinned
        case .caskOperationUnsupported: .caskOperationUnsupported
        case .caskUninstallRequiresElevation: .caskUninstallRequiresElevation
        case .caskArtifactTargetUnverified: .caskArtifactTargetUnverified
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
        preview: HomebrewCaskUninstallPreview,
        state: OperationState,
        message: String,
        cleanupOK: Bool
    ) -> HomebrewCaskUninstallOutcome {
        HomebrewCaskUninstallOutcome(
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
