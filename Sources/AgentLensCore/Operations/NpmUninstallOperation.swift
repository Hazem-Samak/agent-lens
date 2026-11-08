// NpmUninstallOperation — confirmed, one-shot npm-global uninstall.
//
// Preparation performs a complete fresh ownership verification without reading or writing either
// metadata cache and without querying latest metadata. Confirmation repeats the fresh local scan
// and ownership proof, compares every bound fact, revalidates the live proof and owned operation
// root, then launches one literal npm argv. After a launch the operation always reconciles local
// facts; exit zero alone is never success.

import Darwin
import Foundation

/// The internal authorization evidence behind one public Uninstall preview. Never public, never
/// persisted.
struct NpmUninstallPlan: Sendable {
    let definition: DetectorDefinition
    let diagnostic: ToolPathDiagnostic
    let selectedEntryPath: String
    let selectedTarget: String
    let selection: ObservedExecutable
    let installedVersion: String?
    let environment: ShellEnvironment
    let environmentFingerprint: String
    let currentDirectory: String
    let manager: ObservedExecutable
    let installation: VerifiedInstallation
    let proof: NpmOwnershipProbe.NpmOwnershipProof
    let packageName: String
    let updateRunner: UpdateCommandRunner
    let root: NpmScratchRoot
    let arguments: [String]
    let preview: NpmUninstallPreview
}

public enum NpmUninstallOperation {

    private static let preparationBudgetNanoseconds: UInt64 = 60 * 1_000_000_000
    private static let confirmationBudgetNanoseconds: UInt64 = 60 * 1_000_000_000
    private static let mutationTimeout: TimeInterval = 120

    /// Prepares an exact preview and claims one mode-0700 owned operation root. No metadata cache
    /// is read or written, no latest query is sent, and no npm mutation process is launched.
    public static func prepare(
        definition: DetectorDefinition,
        diagnostic: ToolPathDiagnostic,
        environment: ShellEnvironment,
        currentDirectory: String,
        runner: UpdateCommandRunner,
        operationRootBaseURL: URL? = nil,
        uptime: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
    ) async -> NpmUninstallPrepareResult {
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

        guard let pair = selectionPair(diagnostic),
              let selection = FileIdentityObserver.observeExecutable(entryPath: pair.entry),
              selection.canonicalTarget == pair.target
        else { return .unavailable(.noVerifiedSelection) }
        guard let manager = NpmOwnershipProbe.resolveNpmManager(
            environment: environment, currentDirectory: currentDirectory
        ) else { return .unavailable(.managerUnavailable) }

        guard let base = NpmScratchBase(url: scratchBase),
              let root = NpmScratchRoot.claim(base: base)
        else { return .unavailable(.operationRootUnsafe) }
        if Task.isCancelled {
            _ = releaseOperationRoot(root)
            return .unavailable(.cancelled)
        }
        guard uptime() < deadline else {
            _ = releaseOperationRoot(root)
            return .unavailable(.probeFailed)
        }

        let scratchEnvironment = scratchEnvironment(environment, cacheRoot: root.url.path)
        let (outcome, proof) = await NpmOwnershipProbe.verifyWithProof(
            definition: definition,
            selection: selection,
            manager: manager,
            environment: scratchEnvironment,
            runner: runner
        )
        guard !Task.isCancelled, uptime() < deadline else {
            _ = releaseOperationRoot(root)
            return .unavailable(.cancelled)
        }
        let installation: VerifiedInstallation
        switch outcome {
        case .unknown(let reason):
            _ = releaseOperationRoot(root)
            return .unavailable(map(reason))
        case .verified(let value):
            installation = value
        }
        guard installation.manager == .npm,
              !installation.packageName.isEmpty,
              let proof
        else {
            _ = releaseOperationRoot(root)
            return .unavailable(.unsupportedManager)
        }
        guard proof.revalidate() == nil,
              let currentSelection = FileIdentityObserver.observeExecutable(entryPath: pair.entry),
              currentSelection == selection,
              currentSelection.canonicalTarget == pair.target,
              let currentManager = FileIdentityObserver.observeExecutable(entryPath: manager.entryPath),
              currentManager == manager
        else {
            _ = releaseOperationRoot(root)
            return .unavailable(.identityUnverified)
        }

        let packageName = installation.packageName
        let scope = scopeOf(packageName)
        let arguments = uninstallArguments(
            root: root.url.path,
            packageName: packageName,
            prefix: installation.managerRoot,
            scope: scope
        )
        let installedVersion = normalizedVersion(diagnostic.detectedTool.version)
        let preview = NpmUninstallPreview(
            registryID: definition.id,
            displayName: definition.displayName,
            selectedEntryPath: pair.entry,
            selectedTarget: pair.target,
            installedVersion: installedVersion,
            packageName: packageName,
            registry: NpmMetadataSemantics.acceptedRegistry,
            managerPath: manager.entryPath,
            prefix: installation.managerRoot,
            installationRoot: installation.installationRoot,
            workingDirectory: root.url.path,
            executablePath: manager.entryPath,
            arguments: arguments,
            effect: npmUninstallEffectText
        )
        let plan = NpmUninstallPlan(
            definition: definition,
            diagnostic: diagnostic,
            selectedEntryPath: pair.entry,
            selectedTarget: pair.target,
            selection: selection,
            installedVersion: installedVersion,
            environment: environment,
            environmentFingerprint: environmentFingerprint(
                environment: environment, currentDirectory: currentDirectory
            ),
            currentDirectory: currentDirectory,
            manager: manager,
            installation: installation,
            proof: proof,
            packageName: packageName,
            updateRunner: runner,
            root: root,
            arguments: arguments,
            preview: preview
        )
        return .ready(NpmUninstallPreparation(preview: preview, plan: plan))
    }

    /// Cancels a pending preview and releases only its owned root.
    @discardableResult
    public static func cancel(_ preparation: NpmUninstallPreparation) -> Bool {
        preparation.releaseUnconsumed()
    }

    /// Consumes a confirmed preparation and launches at most one literal npm uninstall.
    public static func execute(
        confirmed preparation: NpmUninstallPreparation,
        environment: ShellEnvironment,
        scan: @escaping @Sendable (DetectorDefinition, ShellEnvironment, String) -> ToolPathDiagnostic?,
        reconcileAfterLaunch: @escaping @Sendable (DetectorDefinition) async -> (ToolPathDiagnostic, ShellEnvironment)?,
        updateRunner: UpdateCommandRunner,
        operationRunner: OperationCommandRunner,
        gate: OperationExecutionGate,
        uptime: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
    ) async -> NpmUninstallOutcome {
        let preview = preparation.preview
        guard await gate.acquire() else {
            let cleanupOK = preparation.releaseUnconsumed()
            return noProcessOutcome(
                preview: preview,
                state: .cancelled,
                message: "Another mutation owns the operation gate; this preparation was released.",
                cleanupOK: cleanupOK
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
            reconciliation: NpmUninstallDelta? = nil,
            cleanupWarnings: [String] = [],
            message: String? = nil,
            releaseRoot: Bool = true
        ) async -> NpmUninstallOutcome {
            var warnings = cleanupWarnings
            if releaseRoot, !releaseOperationRoot(plan.root) {
                warnings.append("The owned operation scratch root could not be removed safely.")
            }
            await gate.release()
            return NpmUninstallOutcome(
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
        guard let freshSelection = selectionPair(freshDiagnostic),
              freshSelection.entry == plan.selectedEntryPath,
              freshSelection.target == plan.selectedTarget,
              normalizedVersion(freshDiagnostic.detectedTool.version) == plan.installedVersion
        else {
            return await finish(
                state: .failed, processStarted: false,
                message: "The selected installation changed; a new preview is required."
            )
        }

        let freshEnvironment = scratchEnvironment(plan.environment, cacheRoot: plan.root.url.path)
        let (confirmedOutcome, confirmedProof) = await NpmOwnershipProbe.verifyWithProof(
            definition: plan.definition,
            selection: plan.selection,
            manager: plan.manager,
            environment: freshEnvironment,
            runner: updateRunner
        )
        guard !Task.isCancelled, uptime() < deadline else {
            return await finish(
                state: Task.isCancelled ? .cancelled : .failed, processStarted: false,
                message: Task.isCancelled
                    ? "The uninstall was cancelled before launch."
                    : "Confirmation revalidation exceeded its read-only budget."
            )
        }
        switch confirmedOutcome {
        case .unknown(let reason):
            return await finish(
                state: reason == .cancelled ? .cancelled : .failed, processStarted: false,
                message: "Fresh confirmation failed: \(map(reason).message)"
            )
        case .verified(let installation):
            guard installation == plan.installation,
                  let confirmedProof,
                  confirmedProof == plan.proof
            else {
                return await finish(
                    state: .failed, processStarted: false,
                    message: "A bound installation, proof, or manager fact changed; a new preview is required."
                )
            }
        }
        guard plan.root.isLive() else {
            return await finish(
                state: .failed, processStarted: false,
                message: "The owned operation root changed during confirmation; a new preview is required."
            )
        }
        guard plan.proof.revalidate() == nil else {
            return await finish(
                state: .failed, processStarted: false,
                message: "The live ownership proof changed immediately before launch; no mutation was started."
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
                    ? "The uninstall was cancelled before the process launched."
                    : "The npm process could not be launched; no mutation retry was attempted."
            )
        }

        var warnings: [String] = []
        if processResult.cleanupWarning {
            warnings.append("The npm process group could not be fully reaped within the cleanup bound.")
        }
        let reconciliation: NpmUninstallDelta?
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
        let state: OperationState
        if let reconciliation {
            if interrupted {
                state = .interrupted
            } else if let exitStatus = processResult.exitStatus {
                if exitStatus == 0 {
                    state = (reconciliation.packageDirectoryAbsent
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
        return NpmUninstallOutcome(
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

    private enum PackageRemovalObservation: Equatable {
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

    /// Distinguishes a genuinely absent package directory from an unreadable or raced observation.
    /// A nil `FileIdentityObserver` result alone is never removal evidence.
    private static func observePackageRemoval(path: String) -> PackageRemovalObservation {
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
        plan: NpmUninstallPlan,
        diagnostic after: ToolPathDiagnostic,
        environment: ShellEnvironment
    ) async -> (NpmUninstallDelta?, [String]) {
        let afterSelection = selectionPair(after)
        let (ownership, ownershipWarning) = await reconcileOwnership(
            plan: plan, diagnostic: after, environment: environment
        )
        let packageObservation = observePackageRemoval(path: plan.proof.packageLexicalPath)
        let entryObservation = observeEntryRemoval(
            path: plan.selectedEntryPath, oldTarget: plan.selectedTarget
        )
        let packageDirectoryAbsent: Bool
        let packageDirectoryReplaced: Bool
        switch packageObservation {
        case .absent:
            packageDirectoryAbsent = true
            packageDirectoryReplaced = false
        case .present(let identity):
            packageDirectoryAbsent = false
            packageDirectoryReplaced = identity != plan.proof.package
        case .failed:
            packageDirectoryAbsent = false
            packageDirectoryReplaced = false
        }
        let selectedTargetReleased = entryObservation == .released
            || entryObservation == .dangling
            || entryObservation == .absent
        let selectedEntryResidue = entryObservation == .dangling
        let observationFailed = packageObservation == .failed || entryObservation == .failed
        let beforeSelection = selectionPair(plan.diagnostic)
        let delta = NpmUninstallDelta(
            beforeVersion: plan.installedVersion,
            afterVersion: normalizedVersion(after.detectedTool.version),
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
            packageDirectoryAbsent: packageDirectoryAbsent,
            packageDirectoryReplaced: packageDirectoryReplaced,
            selectedTargetReleased: selectedTargetReleased,
            selectedEntryResidue: selectedEntryResidue,
            observationFailed: observationFailed,
            ownership: ownership
        )
        return (delta, ownershipWarning.map { [$0] } ?? [])
    }

    private static func reconcileOwnership(
        plan: NpmUninstallPlan,
        diagnostic: ToolPathDiagnostic,
        environment: ShellEnvironment
    ) async -> (InstallationOwnershipOutcome?, String?) {
        guard let pair = selectionPair(diagnostic) else {
            return (.unknown(.notInstalled), nil)
        }
        guard let selected = FileIdentityObserver.observeExecutable(entryPath: pair.entry),
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
        let queryEnvironment = scratchEnvironment(environment, cacheRoot: queryRoot.url.path)
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

    // MARK: - Preview/argv helpers

    private static func uninstallArguments(
        root: String,
        packageName: String,
        prefix: String,
        scope: String?
    ) -> [String] {
        var arguments = [
            "--cache", root,
            "--logs-dir", root,
            "--no-update-notifier",
            "uninstall", packageName,
            "--global",
            "--prefix", prefix,
            "--registry=\(NpmMetadataSemantics.acceptedRegistry)",
        ]
        if let scope {
            arguments.append("--\(scope):registry=\(NpmMetadataSemantics.acceptedRegistry)")
        }
        arguments.append(contentsOf: [
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

    private static func normalizedVersion(_ version: String?) -> String? {
        guard let version, !version.isEmpty else { return nil }
        return version
    }

    private static func scratchEnvironment(
        _ base: ShellEnvironment,
        cacheRoot: String
    ) -> ShellEnvironment {
        ShellEnvironment(
            shellPath: base.shellPath,
            pathEntries: base.pathEntries,
            pathJoined: base.pathJoined,
            raw: npmEnvironment(raw: base.raw, cacheRoot: cacheRoot),
            isDegraded: base.isDegraded
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

    private static func map(_ reason: InstallationOwnershipReason) -> NpmUninstallUnavailableReason {
        switch reason {
        case .managerUnavailable: .managerUnavailable
        case .notInstalled, .selectionUnavailable, .inconsistentSelection: .noVerifiedSelection
        case .cancelled: .cancelled
        case .unsupportedSource, .noDeclaredPackage: .unsupportedManager
        default: .identityUnverified
        }
    }

    private static func message(for state: OperationState, interrupted: Bool) -> String? {
        switch state {
        case .succeeded:
            nil
        case .cancelled:
            "The uninstall was cancelled before the process launched; no mutation was reported."
        case .failed:
            "npm exited nonzero; the measured delta is reported without a rollback claim."
        case .interrupted:
            "The npm process was interrupted; reconciliation is reported without a rollback claim."
        case .uncertain:
            interrupted
                ? "The npm process was interrupted and the result could not be confirmed from fresh facts."
                : "The npm process completed, but removal could not be proven from fresh facts."
        }
    }

    private static func noProcessOutcome(
        preview: NpmUninstallPreview,
        state: OperationState,
        message: String,
        cleanupOK: Bool
    ) -> NpmUninstallOutcome {
        NpmUninstallOutcome(
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
