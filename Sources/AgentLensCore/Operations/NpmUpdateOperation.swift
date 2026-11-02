// NpmUpdateOperation — confirmed, one-shot npm-global update.
//
// Preparation performs a complete fresh ownership/registry/latest observation without reading or
// writing either metadata cache. Confirmation repeats that observation after a fresh local scan,
// compares every bound fact, revalidates the live proof and owned operation root, then launches one
// literal npm argv. After a launch the operation always reconciles local facts; exit zero alone is
// never success.

import Darwin
import Foundation

/// The internal authorization evidence behind one public preview. Never public, never persisted.
struct NpmUpdatePlan: Sendable {
    let definition: DetectorDefinition
    let diagnostic: ToolPathDiagnostic
    let selectedEntryPath: String
    let selectedTarget: String
    let installedVersion: Version
    let targetVersion: Version
    let environment: ShellEnvironment
    let environmentFingerprint: String
    let currentDirectory: String
    let manager: ObservedExecutable
    let installation: VerifiedInstallation
    let proof: NpmOwnershipProbe.NpmOwnershipProof
    let registry: String
    let scope: String?
    let scopeRegistry: String?
    let managerFingerprint: String
    let proofFingerprint: String
    let npmVersion: String?
    let updateRunner: UpdateCommandRunner
    let root: NpmScratchRoot
    let arguments: [String]
    let preview: NpmUpdatePreview
}

/// Releases only the exact operation root recorded by the preparation. A replacement/retarget is
/// refused by the root's identity check and leaves the directory in place.
func releaseOperationRoot(_ root: NpmScratchRoot) -> Bool {
    NpmScratchCleanupLedger().release(root)
}

public enum NpmUpdateOperation {

    private static let preparationBudgetNanoseconds: UInt64 = 60 * 1_000_000_000
    private static let confirmationBudgetNanoseconds: UInt64 = 60 * 1_000_000_000
    private static let mutationTimeout: TimeInterval = 120

    /// Prepares an exact preview and claims one mode-0700 owned operation root. No cache is read or
    /// written and no npm mutation process is launched.
    public static func prepare(
        definition: DetectorDefinition,
        diagnostic: ToolPathDiagnostic,
        environment: ShellEnvironment,
        currentDirectory: String,
        runner: UpdateCommandRunner,
        operationRootBaseURL: URL? = nil,
        uptime: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
    ) async -> NpmUpdatePrepareResult {
        if Task.isCancelled { return .unavailable(.cancelled) }
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
        let observation: NpmFreshObservation
        switch await NpmUpdateProbe.observeFresh(
            definition: definition,
            diagnostic: diagnostic,
            environment: environment,
            runner: runner,
            currentDirectory: currentDirectory,
            uptime: uptime,
            stageDeadline: deadline,
            npmScratchBaseURL: scratchBase
        ) {
        case .unavailable(let reason):
            return .unavailable(Task.isCancelled ? .cancelled : map(reason))
        case .success(let value):
            observation = value
        }
        if Task.isCancelled { return .unavailable(.cancelled) }

        guard observation.installation.manager == .npm else {
            return .unavailable(.unsupportedManager)
        }
        guard !observation.installation.packageName.isEmpty else {
            return .unavailable(.identityUnverified)
        }
        guard NpmMetadataSemantics.isStableSemanticVersion(observation.installedVersion.text) else {
            return .unavailable(.unsupportedVersion)
        }
        guard NpmMetadataSemantics.isStableSemanticVersion(observation.metadata.version),
              NpmMetadataSemantics.isStrictSemanticVersion(observation.metadata.version)
        else {
            return .unavailable(observation.metadata.version.contains("-")
                ? .prereleaseChannel : .metadataInvalid)
        }
        let targetVersion = Version(observation.metadata.version)
        switch VersionComparison.ordering(
            observation.installedVersion.text,
            targetVersion.text,
            scheme: .semanticVersion
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

        let rootBase = scratchBase
        guard let base = NpmScratchBase(url: rootBase),
              let root = NpmScratchRoot.claim(base: base)
        else {
            return .unavailable(.operationRootUnsafe)
        }
        if Task.isCancelled {
            _ = releaseOperationRoot(root)
            return .unavailable(.cancelled)
        }

        let scope = scopeOf(observation.installation.packageName)
        let arguments = mutableArguments(
            root: root.url.path,
            packageName: observation.installation.packageName,
            targetVersion: targetVersion.text,
            prefix: observation.installation.managerRoot,
            registry: observation.registry,
            scope: scope
        )
        let preview = NpmUpdatePreview(
            registryID: definition.id,
            displayName: definition.displayName,
            selectedEntryPath: observation.selectedEntryPath,
            selectedTarget: observation.selectedTarget,
            installedVersion: observation.installedVersion.text,
            targetVersion: targetVersion.text,
            packageName: observation.installation.packageName,
            registry: observation.registry,
            tag: NpmMetadataSemantics.latestTag,
            managerPath: observation.manager.entryPath,
            prefix: observation.installation.managerRoot,
            workingDirectory: root.url.path,
            executablePath: observation.manager.entryPath,
            arguments: arguments,
            effect: npmUpdateEffectText
        )
        let plan = NpmUpdatePlan(
            definition: definition,
            diagnostic: diagnostic,
            selectedEntryPath: observation.selectedEntryPath,
            selectedTarget: observation.selectedTarget,
            installedVersion: observation.installedVersion,
            targetVersion: targetVersion,
            environment: environment,
            environmentFingerprint: environmentFingerprint(
                environment: environment, currentDirectory: currentDirectory
            ),
            currentDirectory: currentDirectory,
            manager: observation.manager,
            installation: observation.installation,
            proof: observation.proof,
            registry: observation.registry,
            scope: scope,
            scopeRegistry: observation.scopeRegistry,
            managerFingerprint: fingerprint(observation.manager.fingerprint),
            proofFingerprint: observation.proof.fingerprint,
            npmVersion: observation.npmVersion,
            updateRunner: runner,
            root: root,
            arguments: arguments,
            preview: preview
        )
        return .ready(NpmUpdatePreparation(preview: preview, plan: plan))
    }

    /// Cancels a pending preview and releases only its owned root.
    @discardableResult
    public static func cancel(_ preparation: NpmUpdatePreparation) -> Bool {
        preparation.releaseUnconsumed()
    }

    /// Consumes a confirmed preparation and launches at most one exact-version npm install.
    public static func execute(
        confirmed preparation: NpmUpdatePreparation,
        environment: ShellEnvironment,
        scan: @escaping @Sendable (DetectorDefinition, ShellEnvironment, String) -> ToolPathDiagnostic?,
        reconcileAfterLaunch: @escaping @Sendable (DetectorDefinition) async -> (ToolPathDiagnostic, ShellEnvironment)?,
        updateRunner: UpdateCommandRunner,
        operationRunner: OperationCommandRunner,
        gate: OperationExecutionGate,
        uptime: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
    ) async -> OperationOutcome {
        let preview = preparation.preview
        guard await gate.acquire() else {
            let cleanupOK = preparation.releaseUnconsumed()
            return noProcessOutcome(
                preview: preview, state: .cancelled,
                message: "Another mutation owns the operation gate; this preparation was released.",
                cleanupOK: cleanupOK
            )
        }
        guard let plan = preparation.claim() else {
            await gate.release()
            return noProcessOutcome(
                preview: preview, state: .failed,
                message: "The preparation was already consumed.",
                cleanupOK: true
            )
        }

        let started = uptime()
        let deadline = started &+ confirmationBudgetNanoseconds

        func finish(
            state: OperationState,
            stdout: Data = Data(),
            stderr: Data = Data(),
            stdoutTruncated: Bool = false,
            stderrTruncated: Bool = false,
            exitStatus: Int32? = nil,
            processStarted: Bool,
            reconciliation: InstallationDelta? = nil,
            cleanupWarnings: [String] = [],
            message: String? = nil,
            releaseRoot: Bool = true
        ) async -> OperationOutcome {
            var warnings = cleanupWarnings
            if releaseRoot, !releaseOperationRoot(plan.root) {
                warnings.append("The owned operation scratch root could not be removed safely.")
            }
            await gate.release()
            return OperationOutcome(
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

        guard environmentFingerprint(
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
        guard let freshSelection = selectionPair(freshDiagnostic),
              freshSelection.entry == plan.selectedEntryPath,
              freshSelection.target == plan.selectedTarget
        else {
            return await finish(
                state: .failed, processStarted: false,
                message: "The selected installation changed; a new preview is required."
            )
        }

        let confirmed: NpmFreshObservation
        switch await NpmUpdateProbe.observeFresh(
            definition: plan.definition,
            diagnostic: freshDiagnostic,
            environment: plan.environment,
            runner: updateRunner,
            currentDirectory: plan.currentDirectory,
            uptime: uptime,
            stageDeadline: deadline,
            npmScratchBaseURL: plan.root.url
        ) {
        case .unavailable(let reason):
            return await finish(
                state: Task.isCancelled ? .cancelled : .failed, processStarted: false,
                message: Task.isCancelled
                    ? "The update was cancelled before launch."
                    : "Fresh confirmation failed: \(map(reason).message)"
            )
        case .success(let value):
            confirmed = value
        }

        let freshPlanMatches = confirmed.selectedEntryPath == plan.selectedEntryPath
            && confirmed.selectedTarget == plan.selectedTarget
            && confirmed.installedVersion.text == plan.installedVersion.text
            && confirmed.metadata.version == plan.targetVersion.text
            && confirmed.installation == plan.installation
            && confirmed.manager == plan.manager
            && confirmed.proof == plan.proof
            && confirmed.registry == plan.registry
            && confirmed.scopeRegistry == plan.scopeRegistry
            && confirmed.scope == plan.scope
            && confirmed.installation.packageName == plan.installation.packageName
        guard freshPlanMatches else {
            return await finish(
                state: .failed, processStarted: false,
                message: "A bound installation, metadata, route, or manager fact changed; a new preview is required."
            )
        }
        guard plan.root.isLive() else {
            return await finish(
                state: .failed, processStarted: false,
                message: "The owned operation root changed during confirmation; a new preview is required."
            )
        }
        guard confirmed.proof.revalidate() == nil else {
            return await finish(
                state: .failed, processStarted: false,
                message: "The live ownership proof changed immediately before launch; no mutation was started."
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

        let operationEnvironment = npmEnvironment(
            raw: plan.environment.raw, cacheRoot: plan.root.url.path
        )
        let processResult = await operationRunner.run(
            executablePath: plan.manager.entryPath,
            arguments: plan.arguments,
            environment: operationEnvironment,
            currentDirectory: plan.root.url.path,
            timeout: mutationTimeout
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
                    : "The npm process could not be launched; no mutation retry was attempted."
            )
        }

        var warnings: [String] = []
        if processResult.cleanupWarning {
            warnings.append("The npm process group could not be fully reaped within the cleanup bound.")
        }
        let reconciliation: InstallationDelta?
        if let fresh = await reconcileAfterLaunch(plan.definition) {
            // The post-launch proof and ownership query must finish independently of the caller's
            // cancellation, after the fresh scan. NpmOwnershipProbe deliberately returns .cancelled
            // when its own Task is cancelled, so keep this entire bounded query in a detached child.
            let reconciled = await Task.detached {
                await reconcile(
                    plan: plan, diagnostic: fresh.0, environment: fresh.1
                )
            }.value
            reconciliation = reconciled.0
            warnings.append(contentsOf: reconciled.1)
        } else {
            reconciliation = nil
        }
        let interrupted = processResult.cancelled || processResult.timedOut
            || processResult.stdoutTruncated || processResult.stderrTruncated
        let state: OperationState
        if reconciliation == nil {
            state = .uncertain
        } else if interrupted {
            state = .interrupted
        } else if let exitStatus = processResult.exitStatus {
            if exitStatus == 0 {
                state = (reconciliation?.versionMatchesTarget == true
                    && ownershipVerified(reconciliation?.ownership, plan: plan))
                    ? .succeeded : .uncertain
            } else {
                state = .failed
            }
        } else {
            // A spawned process with no observable exit status is not a failed install claim; it
            // is an inconclusive observation, and its streams/result remain attached.
            state = .uncertain
        }

        let cleaned = releaseOperationRoot(plan.root)
        if !cleaned {
            warnings.append("The owned operation scratch root could not be removed safely.")
        }
        await gate.release()
        return OperationOutcome(
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
            message: state == .succeeded
                ? nil
                : (interrupted
                    ? "The npm process was interrupted; reconciliation is reported without a rollback claim."
                    : "The npm process completed, but success could not be proven from fresh facts.")
        )
    }

    // MARK: - Reconciliation

    private static func reconcile(
        plan: NpmUpdatePlan,
        diagnostic after: ToolPathDiagnostic,
        environment: ShellEnvironment
    ) async -> (InstallationDelta?, [String]) {
        let afterSelection = selectionPair(after)
        let (ownership, ownershipWarning) = await reconcileOwnership(
            plan: plan, diagnostic: after, environment: environment
        )
        let afterVersion = after.detectedTool.version
        let matchesTarget = afterVersion.map {
            NpmMetadataSemantics.isStableSemanticVersion($0)
                && VersionComparison.ordering(
                    $0, plan.targetVersion.text, scheme: .semanticVersion
                ) == .equal
        } ?? false
        let beforeSelection = selectionPair(plan.diagnostic)
        let delta = InstallationDelta(
            beforeVersion: plan.installedVersion.text,
            afterVersion: afterVersion,
            beforeEntryPath: beforeSelection?.entry ?? plan.selectedEntryPath,
            afterEntryPath: afterSelection?.entry,
            beforeTarget: beforeSelection?.target ?? plan.selectedTarget,
            afterTarget: afterSelection?.target,
            beforeAliases: aliases(plan.diagnostic),
            afterAliases: aliases(after),
            beforeShadowedCount: plan.diagnostic.shadowedInstallationCount ?? 0,
            afterShadowedCount: after.shadowedInstallationCount ?? 0,
            beforeInstallState: plan.diagnostic.detectedTool.state,
            afterInstallState: after.detectedTool.state,
            ownership: ownership,
            versionMatchesTarget: matchesTarget
        )
        return (delta, ownershipWarning.map { [$0] } ?? [])
    }

    private static func reconcileOwnership(
        plan: NpmUpdatePlan,
        diagnostic: ToolPathDiagnostic,
        environment: ShellEnvironment
    ) async -> (InstallationOwnershipOutcome?, String?) {
        guard let pair = selectionPair(diagnostic),
              let selected = FileIdentityObserver.observeExecutable(entryPath: pair.entry),
              selected.canonicalTarget == pair.target
        else { return (.unknown(.selectionUnavailable), nil) }
        guard let manager = NpmOwnershipProbe.resolveNpmManager(
            environment: environment, currentDirectory: plan.currentDirectory
        ) else { return (.unknown(.managerUnavailable), nil) }
        // Ownership queries are additional npm invocations after the mutation. Keep their cache and
        // logs in a freshly claimed, validated child of the owned operation base, never the
        // captured/shared npm cache and never a possibly replaced operation root.
        let queryBaseURL = plan.root.url.deletingLastPathComponent()
        guard let base = NpmScratchBase(url: queryBaseURL),
              let queryRoot = NpmScratchRoot.claim(base: base)
        else {
            return (.unknown(.managerQueryFailed),
                    "The ownership query scratch root could not be claimed safely.")
        }
        let queryRaw = npmEnvironment(
            raw: environment.raw, cacheRoot: queryRoot.url.path
        )
        let queryEnvironment = ShellEnvironment(
            shellPath: environment.shellPath,
            pathEntries: environment.pathEntries,
            pathJoined: environment.pathJoined,
            raw: queryRaw,
            isDegraded: environment.isDegraded
        )
        let (outcome, _) = await NpmOwnershipProbe.verifyWithProof(
            definition: plan.definition,
            selection: selected,
            manager: manager,
            environment: queryEnvironment,
            runner: plan.updateRunner
        )
        let released = NpmScratchCleanupLedger().release(queryRoot)
        return (outcome, released ? nil : "The ownership query scratch root could not be removed safely.")
    }

    private static func ownershipVerified(
        _ outcome: InstallationOwnershipOutcome?,
        plan: NpmUpdatePlan
    ) -> Bool {
        guard case .verified(let installation)? = outcome else { return false }
        return installation.manager == .npm
            && installation.packageName == plan.installation.packageName
            && installation.managerRoot == plan.installation.managerRoot
            && installation.selection.canonicalTarget == plan.installation.selection.canonicalTarget
    }

    // MARK: - Preview/argv helpers

    private static func mutableArguments(
        root: String,
        packageName: String,
        targetVersion: String,
        prefix: String,
        registry: String,
        scope: String?
    ) -> [String] {
        var arguments = [
            "--cache", root,
            "--logs-dir", root,
            "--no-update-notifier",
            "install", "\(packageName)@\(targetVersion)",
            "--global",
            "--prefix", prefix,
            "--registry=\(registry)",
        ]
        if let scope {
            arguments.append("--\(scope):registry=\(registry)")
        }
        arguments.append(contentsOf: [
            "--prefer-online",
            "--offline=false",
            "--no-audit",
            "--no-fund",
            "--package-lock=false",
            "--no-save",
            "--fetch-retries=0",
            "--fetch-timeout=30000",
        ])
        return arguments
    }

    private static func selectionPair(
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

    private static func aliases(_ diagnostic: ToolPathDiagnostic) -> [String] {
        diagnostic.pathCandidates.map(\.entryPath)
    }

    private static func fingerprint(_ value: ExecutableFingerprint) -> String {
        let material = [
            "device", String(value.device),
            "inode", String(value.inode),
            "mode", String(value.mode),
            "size", String(value.size),
            "mtime", "\(value.modifiedSeconds).\(value.modifiedNanoseconds)",
            "ctime", "\(value.changedSeconds).\(value.changedNanoseconds)",
        ]
        return UpdateMetadataKey.stableDigest(
            material.map { "\($0.utf8.count):\($0)" }.joined()
        )
    }

    private static func environmentFingerprint(
        environment: ShellEnvironment,
        currentDirectory: String
    ) -> String {
        let working = URL(fileURLWithPath: currentDirectory, isDirectory: true)
            .standardizedFileURL.path
        let values = environment.raw.keys.sorted().map {
            "\($0.utf8.count):\($0)\(environment.raw[$0]!.utf8.count):\(environment.raw[$0]!)"
        }.joined()
        return UpdateMetadataKey.stableDigest(
            "environment-context-v1" + "\(working.utf8.count):\(working)" + values
        )
    }

    private static func map(_ reason: UnknownReason) -> NpmUpdateUnavailableReason {
        switch reason {
        case .notInstalled: .noVerifiedSelection
        case .unsupportedSource: .unsupportedManager
        case .installedVersionUnavailable: .installedVersionUnavailable
        case .unsupportedVersion: .unsupportedVersion
        case .newerThanKnownMetadata: .newerThanMetadata
        case .unsupportedChannel: .prereleaseChannel
        case .identityUnverified, .diagnosticInconsistent, .managerMismatch:
            .identityUnverified
        case .managerUnavailable: .managerUnavailable
        case .unsupportedRegistry: .unsupportedRegistry
        case .metadataInvalid: .metadataInvalid
        case .queryTimedOut: .queryTimedOut
        case .budgetExhausted: .budgetExhausted
        case .probeFailed: .probeFailed
        case .noRegistry: .unsupportedManager
        case .networkUnavailable, .rateLimited: .probeFailed
        case .notChecked: .probeFailed
        }
    }

    private static func noProcessOutcome(
        preview: NpmUpdatePreview,
        state: OperationState,
        message: String,
        cleanupOK: Bool
    ) -> OperationOutcome {
        OperationOutcome(
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
