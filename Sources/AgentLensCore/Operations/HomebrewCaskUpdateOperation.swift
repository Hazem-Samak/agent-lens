// HomebrewCaskUpdateOperation — confirmed, one-shot Homebrew cask upgrade (M13-E R5/R6/R7/R8/R9).
//
// Preparation performs a complete fresh cask ownership proof, a fresh exact `info` observation
// (including strict `artifacts`), the unscoped pin cross-check and, for Update only, the unscoped
// ordinary `outdated` verdict. It never reads the update metadata cache, but it does read
// Homebrew's bounded saved installed cask definition, `INSTALL_RECEIPT.json` and the ordinary
// saved `config.json` because teardown loads those rather than the current source. Confirmation
// repeats the full observation after a
// fresh local scan, compares every bound fact (including both saved metadata files and their
// identities), revalidates the live proof and the owned operation root, then launches one literal
// `brew upgrade --cask` argv. After a launch the operation always reconciles fresh ownership,
// manager facts and staged membership; exit zero alone is never success.
//
// The shared observation in this file is used by the cask Uninstall operation too: one cask
// identity/artifact/pin/saved-teardown observation, two operations. It deliberately reuses the
// public ownership verifier, the M13-B cask parsers and the same bound-root/staged-directory
// types instead of inventing a second proof or an unbounded receipt parser.

import Darwin
import Foundation

// MARK: - Shared cask observation

/// One manager-declared CLI artifact. `source` is the manager's own binary source string or the
/// command-wrapper name; `target` is the manager's resolved absolute destination.
struct HomebrewCaskCliArtifact: Equatable, Sendable {
    let kind: HomebrewCaskArtifactKind
    let source: String
    /// The manager-resolved absolute destination from fresh or saved metadata.
    let target: String
    /// The saved/declared explicit target option (`binary ..., target:`), or nil for the manager's
    /// default target derived from the source basename. A command_wrapper never carries one here.
    let explicitTarget: String?
}

/// The supported artifact subset: at least one CLI artifact, no app/unknown kind, no uninstall
/// stanza. A zap stanza may be present; it is disclosed and never parsed for execution.
struct HomebrewCaskArtifactSet: Equatable, Sendable {
    let cliArtifacts: [HomebrewCaskCliArtifact]
    let hasZap: Bool
}

/// A CLI artifact plus the exact staged source path and the target presence observed at preview.
struct HomebrewCaskManagedTarget: Equatable, Sendable {
    let artifact: HomebrewCaskCliArtifact
    let sourcePath: String
    let presence: HomebrewCaskTargetPresence
    /// The live `<prefix>/bin` directory identity through which the target was observed.
    let linkParent: HomebrewCaskBoundDirectory
    let prefixRoot: HomebrewCaskBoundRoot
}

/// The manager's ordinary-outdated evidence for this cask, bound for confirm-time comparison.
struct HomebrewCaskOutdatedFacts: Equatable, Sendable {
    let currentVersion: String
    let installedVersions: [String]
    let pinned: Bool
}

enum HomebrewCaskInstalledValue: Equatable, Sendable {
    case missing
    case null
    case string(String)
    case malformed
}

enum HomebrewCaskArtifactParseResult: Equatable, Sendable {
    case supported(HomebrewCaskArtifactSet)
    case requiresElevation
    case unsupported
    case malformed
}

/// One artifact recovered from Homebrew's saved installed definition or install receipt. `target`
/// is present only when the saved document serialized the manager's resolved destination; a
/// receipt normally records just the kind/source pair.
struct HomebrewCaskInstalledArtifact: Equatable, Sendable {
    let kind: HomebrewCaskArtifactKind
    let source: String
    /// A top-level resolved destination when the saved document serialized one.
    let target: String?
    /// The explicit target option serialized inside `binary` (never a command_wrapper parameter).
    let explicitTarget: String?
}

/// The strict subset of saved installed artifacts this product can reason about. Zap remains
/// disclosure-only; an uninstall stanza or flight block is a typed elevation refusal.
struct HomebrewCaskInstalledArtifactSet: Equatable, Sendable {
    let cliArtifacts: [HomebrewCaskInstalledArtifact]
    let hasZap: Bool
}

enum HomebrewCaskInstalledArtifactParseResult: Equatable, Sendable {
    case supported(HomebrewCaskInstalledArtifactSet)
    case requiresElevation
    case unsupported
    case malformed

    var isElevation: Bool {
        if case .requiresElevation = self { return true }
        return false
    }

    var isUnsupported: Bool {
        if case .unsupported = self { return true }
        return false
    }

    var isMalformed: Bool {
        if case .malformed = self { return true }
        return false
    }
}

/// One bounded, regular saved metadata file, bound to the exact directory identity and content
/// observed at prepare. Never a path resolved from the receipt or a symlink.
struct HomebrewCaskSavedFile: Equatable, Sendable {
    let directory: HomebrewCaskBoundDirectory
    let name: String
    let path: String
    let fingerprint: ExecutableFingerprint
    let data: Data
}

/// Homebrew's selected saved installed cask definition plus `INSTALL_RECEIPT.json`, bound beneath
/// the already-verified `<Caskroom>/<token>` identity. The manager loads the saved file for
/// teardown, so its artifacts can differ from the current source metadata.
struct HomebrewCaskInstalledMetadata: Equatable, Sendable {
    let metadataDirectory: HomebrewCaskBoundDirectory
    let versionDirectory: HomebrewCaskBoundDirectory
    let timestampDirectory: HomebrewCaskBoundDirectory
    let casksDirectory: HomebrewCaskBoundDirectory
    let receipt: HomebrewCaskSavedFile
    let caskFile: HomebrewCaskSavedFile
    /// Homebrew's saved cask configuration, when present. Bound byte-for-byte because it can
    /// influence the installed cask's artifact configuration; its contents are never interpreted.
    let config: HomebrewCaskSavedFile?
    let artifacts: HomebrewCaskInstalledArtifactSet
    let managedTargets: [HomebrewCaskManagedTarget]
}

/// One record from the fresh exact `info --json=v2 --cask` query.
struct HomebrewCaskOperationInfo: Sendable {
    let token: String
    let fullToken: String
    let tap: String
    let version: String
    let installed: HomebrewCaskInstalledValue
    let autoUpdates: Bool?
    let pinned: Bool
    let outdated: Bool
    let disabled: Bool
    let disableReason: String?
    let deprecated: Bool
    let deprecationDisclosure: String?
    /// True only when fresh `depends_on` declares a non-empty formula or cask dependency. Missing
    /// or malformed `depends_on` makes the whole record malformed.
    let hasPackageDependencies: Bool
    let artifacts: HomebrewCaskArtifactParseResult
}

/// One fresh, read-only cask observation. Every manager query is followed by a revalidation of
/// the selected executable, the manager, both reported roots and the exact staged directories.
struct HomebrewCaskFacts: Sendable {
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
    let version: String
    let pinned: Bool
    let autoUpdates: Bool?
    let disabled: Bool
    let disableReason: String?
    let deprecated: Bool
    let deprecationDisclosure: String?
    let hasPackageDependencies: Bool
    let artifacts: HomebrewCaskArtifactSet
    let managedTargets: [HomebrewCaskManagedTarget]
    /// Homebrew's selected saved installed definition and receipt, which drive teardown and can
    /// differ from the current source. Never inferred from the current manifest.
    let installedMetadata: HomebrewCaskInstalledMetadata
    /// Exact targets this operation may disclose: current-source targets for Update, merged with
    /// verified installed targets; installed-only targets for Uninstall.
    let previewTargets: [HomebrewCaskArtifactTarget]
    /// The matching ordinary-outdated record, or nil when the manager reported no outdated row.
    /// Update requires agreement; Uninstall does not query this at all.
    let outdatedRecord: HomebrewCaskOutdatedFacts?
}

enum HomebrewCaskObservationMode: Equatable, Sendable {
    case update
    case uninstall
}

enum HomebrewCaskObservationFailure: Error, Equatable, Sendable {
    case noVerifiedSelection
    case managerUnavailable
    case unsupportedManager
    case identityUnverified
    case managerPrefixUnverified
    case caskroomUnverified
    case pinned
    case caskOperationUnsupported
    case caskUninstallRequiresElevation
    case caskArtifactTargetUnverified
    case metadataInvalid
    case budgetExhausted
    case cancelled
    case probeFailed
}

enum HomebrewCaskObservationResult: Sendable {
    case success(HomebrewCaskFacts)
    case unavailable(HomebrewCaskObservationFailure)
}

enum HomebrewCaskObservation {

    /// One bounded observation. Ownership uses the public verifier (its own four read-only
    /// queries); this observation then re-reads both reported roots, one exact info record, the
    /// unscoped pin list and, for Update only, the unscoped ordinary outdated list.
    static func observe(
        definition: DetectorDefinition,
        diagnostic: ToolPathDiagnostic,
        environment: ShellEnvironment,
        runner: UpdateCommandRunner,
        currentDirectory: String,
        uptime: @escaping @Sendable () -> UInt64,
        stageDeadline: UInt64,
        mode: HomebrewCaskObservationMode
    ) async -> HomebrewCaskObservationResult {
        if Task.isCancelled { return .unavailable(.cancelled) }
        guard uptime() < stageDeadline else { return .unavailable(.budgetExhausted) }
        guard let pair = homebrewCaskSelectionPair(diagnostic),
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
        guard installation.manager == .homebrewCask,
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

        let roots: HomebrewCaskBoundRoots
        switch await observeRoots(
            manager: manager,
            selection: selection,
            environment: environment,
            runner: runner
        ) {
        case .failure(let failure):
            return .unavailable(failure)
        case .success(let value):
            roots = value
        }
        guard roots.prefix.canonicalPath == installation.managerRoot else {
            return .unavailable(.managerPrefixUnverified)
        }
        if Task.isCancelled { return .unavailable(.cancelled) }
        guard uptime() < stageDeadline else { return .unavailable(.budgetExhausted) }

        // One fresh exact info query for the manager-returned full identity. Artifacts are
        // required and strict; extra manager fields are tolerated.
        let infoData: Data
        switch await query(
            manager: manager,
            arguments: ["info", "--json=v2", "--cask", installation.packageName],
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
        guard let info = parseInfo(infoData), info.count == 1, let record = info.first else {
            return .unavailable(.metadataInvalid)
        }
        guard record.fullToken == installation.packageName,
              HomebrewCaskUpdateProbe.isStructurallyValidCask(
                token: record.token, fullToken: record.fullToken, tap: record.tap
              )
        else { return .unavailable(.identityUnverified) }

        let artifacts: HomebrewCaskArtifactSet
        switch record.artifacts {
        case .malformed:
            return .unavailable(.metadataInvalid)
        case .requiresElevation:
            return .unavailable(.caskUninstallRequiresElevation)
        case .unsupported:
            return .unavailable(.caskOperationUnsupported)
        case .supported(let value):
            artifacts = value
        }

        guard case .string(let installedVersion) = record.installed else {
            return .unavailable(.identityUnverified)
        }
        // A selected target that parses inside the Caskroom must belong to the manager-reported
        // installed version. A moved `.app` or another outside target is classified below from the
        // saved teardown metadata instead of failing as an unverified Caskroom decomposition.
        let selectedIsStaged: Bool
        if let staged = try? HomebrewCaskTargetParser.parse(
            selectedTarget: pair.target,
            caskroom: roots.caskroom.canonicalPath
        ).get() {
            guard staged.token == record.token, staged.versionDirectory == installedVersion
            else { return .unavailable(.identityUnverified) }
            selectedIsStaged = true
        } else {
            selectedIsStaged = false
        }

        guard let binding = HomebrewCaskStagedBinding.observe(
            caskroom: roots.caskroom,
            token: record.token,
            version: installedVersion
        ), binding.tokenDirectory.identity.canonicalPath == installation.installationRoot
        else { return .unavailable(.identityUnverified) }

        let currentManagedTargets: [HomebrewCaskManagedTarget]
        let selectedIsCurrentCLI: Bool
        let currentBuildFailed: Bool
        switch buildManagedTargets(
            artifacts: artifacts,
            versionDirectory: binding.versionDirectory.identity.canonicalPath,
            prefix: roots.prefix
        ) {
        case .failure:
            currentManagedTargets = []
            selectedIsCurrentCLI = false
            currentBuildFailed = true
        case .success(let value):
            currentManagedTargets = value
            selectedIsCurrentCLI = value.contains {
                homebrewCaskPathsEqual($0.sourcePath, pair.target)
            }
            currentBuildFailed = false
        }

        // Homebrew's teardown reads the saved installed definition and receipt, not the current
        // source. Bind both now, retain the exact snapshot for confirm-time comparison, and prove
        // the installed artifact targets are the real links under this cask's installed version.
        // This happens before requiring current CLI membership so an ownership-verified moved old
        // app with clean new binary metadata still returns its typed app/stanza refusal.
        let installedMetadata: HomebrewCaskInstalledMetadata
        switch observeInstalledMetadata(
            caskroom: roots.caskroom,
            tokenDirectory: binding.tokenDirectory,
            stagedVersionDirectory: binding.versionDirectory,
            token: record.token,
            fullToken: record.fullToken,
            tap: record.tap,
            installedVersion: installedVersion,
            prefix: roots.prefix
        ) {
        case .failure(let failure):
            return .unavailable(failure)
        case .success(let value):
            installedMetadata = value
        }

        // The selected executable must be one of the manager's own current CLI artifact sources.
        // An app or another staged file is never widened into a mutation after the saved teardown
        // has had its chance to classify as unsupported or elevation-requiring. A selected staged
        // file whose current target proof failed is a target refusal, not a support-class one.
        guard selectedIsCurrentCLI else {
            if currentBuildFailed, selectedIsStaged {
                return .unavailable(.caskArtifactTargetUnverified)
            }
            return .unavailable(.caskOperationUnsupported)
        }

        let previewTargets: [HomebrewCaskArtifactTarget]
        switch disclosureTargets(
            mode: mode,
            current: currentManagedTargets,
            installed: installedMetadata.managedTargets
        ) {
        case .failure(let failure):
            return .unavailable(failure)
        case .success(let value):
            previewTargets = value
        }

        if Task.isCancelled { return .unavailable(.cancelled) }
        guard uptime() < stageDeadline else { return .unavailable(.budgetExhausted) }

        // The unscoped pin list. It prints cask tokens; a full token is tolerated as a strict
        // cross-check spelling. Disagreement with `info.pinned` fails closed.
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
        let pinnedByList = pinnedNames.contains(record.token)
            || pinnedNames.contains(record.fullToken)
        guard record.pinned == pinnedByList else {
            return .unavailable(.identityUnverified)
        }
        if record.pinned { return .unavailable(.pinned) }

        var outdatedRecord: HomebrewCaskOutdatedFacts?
        // A cask already refused by Update policy (disabled, self-updating, or `latest`) needs no
        // ordinary-outdated query. Plain `outdated` intentionally omits those casks, so requiring
        // agreement here would mask the typed policy refusal with a false identity contradiction.
        let needsOutdatedVerdict = mode == .update
            && !record.disabled
            && record.autoUpdates != true
            && record.version != "latest"
        if needsOutdatedVerdict {
            let outdatedData: Data
            switch await query(
                manager: manager,
                arguments: ["outdated", "--json=v2", "--cask"],
                environment: environment,
                runner: runner
            ) {
            case .failure(let failure):
                return .unavailable(map(failure))
            case .success(let data):
                outdatedData = data
            }
            if Task.isCancelled { return .unavailable(.cancelled) }
            guard uptime() < stageDeadline else { return .unavailable(.budgetExhausted) }
            switch outdatedFact(
                data: outdatedData,
                record: record,
                installedVersion: installedVersion
            ) {
            case .failure(let failure):
                return .unavailable(failure)
            case .success(let value):
                outdatedRecord = value
            }
        }

        guard homebrewCaskProofIsLive(roots: roots, manager: manager, selection: selection),
              binding.isCurrent,
              homebrewCaskIsRegularFile(pair.target),
              currentManagedTargets.allSatisfy({ managedTargetIsLive($0) }),
              installedMetadataIsLive(
                  installedMetadata,
                  caskroom: roots.caskroom,
                  tokenDirectory: binding.tokenDirectory,
                  stagedVersionDirectory: binding.versionDirectory,
                  token: record.token,
                  fullToken: record.fullToken,
                  tap: record.tap,
                  installedVersion: installedVersion,
                  prefix: roots.prefix
              ),
              installedMetadata.managedTargets.allSatisfy({ managedTargetIsLive($0) })
        else { return .unavailable(.identityUnverified) }
        if Task.isCancelled { return .unavailable(.cancelled) }
        guard uptime() < stageDeadline else { return .unavailable(.budgetExhausted) }

        return .success(HomebrewCaskFacts(
            selectedEntryPath: pair.entry,
            selectedTarget: pair.target,
            selection: selection,
            manager: manager,
            installation: installation,
            token: record.token,
            fullToken: record.fullToken,
            tap: record.tap,
            prefixRoot: roots.prefix,
            caskroomRoot: roots.caskroom,
            tokenDirectory: binding.tokenDirectory,
            versionDirectory: binding.versionDirectory,
            installedVersion: installedVersion,
            version: record.version,
            pinned: record.pinned,
            autoUpdates: record.autoUpdates,
            disabled: record.disabled,
            disableReason: record.disableReason,
            deprecated: record.deprecated,
            deprecationDisclosure: record.deprecationDisclosure,
            hasPackageDependencies: record.hasPackageDependencies,
            artifacts: artifacts,
            managedTargets: currentManagedTargets,
            installedMetadata: installedMetadata,
            previewTargets: previewTargets,
            outdatedRecord: outdatedRecord
        ))
    }

    // MARK: Roots

    /// Binds the reported prefix and Caskroom. Pre-launch callers pass the selected executable so
    /// a retargeted selection refuses; post-launch reconciliation passes nil because the selected
    /// executable is expected to have moved to the new staged version (or to be gone).
    static func observeRoots(
        manager: ObservedExecutable,
        selection: ObservedExecutable?,
        environment: ShellEnvironment,
        runner: UpdateCommandRunner
    ) async -> Result<HomebrewCaskBoundRoots, HomebrewCaskObservationFailure> {
        let prefixText: String
        switch await query(
            manager: manager, arguments: ["--prefix"], environment: environment, runner: runner
        ) {
        case .failure(let failure):
            return .failure(map(failure))
        case .success(let data):
            guard let parsed = ManagerOutputParser.singleAbsolutePath(data),
                  HomebrewCaskTargetParser.cleanedAbsolutePath(parsed) != nil
            else { return .failure(.managerPrefixUnverified) }
            prefixText = parsed
        }
        guard homebrewCaskManagerIsLive(manager),
              selection.map({ homebrewCaskSelectionIsLive($0, manager: manager) }) ?? true,
              let prefix = HomebrewCaskBoundRoot.observe(prefixText),
              prefix.canonicalPath != "/"
        else { return .failure(.managerPrefixUnverified) }

        let caskroomText: String
        switch await query(
            manager: manager, arguments: ["--caskroom"], environment: environment, runner: runner
        ) {
        case .failure(let failure):
            return .failure(map(failure))
        case .success(let data):
            guard let parsed = ManagerOutputParser.singleAbsolutePath(data),
                  HomebrewCaskTargetParser.cleanedAbsolutePath(parsed) != nil
            else { return .failure(.caskroomUnverified) }
            caskroomText = parsed
        }
        guard homebrewCaskManagerIsLive(manager),
              selection.map({ homebrewCaskSelectionIsLive($0, manager: manager) }) ?? true,
              let caskroom = HomebrewCaskBoundRoot.observe(caskroomText),
              caskroom.canonicalPath != "/"
        else { return .failure(.caskroomUnverified) }
        guard prefix.isCurrent, caskroom.isCurrent else {
            return .failure(.identityUnverified)
        }
        return .success(HomebrewCaskBoundRoots(prefix: prefix, caskroom: caskroom))
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

    static func map(
        _ failure: CommandFailure
    ) -> HomebrewCaskObservationFailure {
        switch failure {
        case .cancelled: .cancelled
        default: .probeFailed
        }
    }

    static func map(
        _ reason: InstallationOwnershipReason
    ) -> HomebrewCaskObservationFailure {
        switch reason {
        case .managerUnavailable: .managerUnavailable
        case .cancelled: .cancelled
        case .notInstalled, .selectionUnavailable, .inconsistentSelection,
             .packageNotInstalled:
            .noVerifiedSelection
        case .managerQueryFailed, .invalidManagerOutput: .probeFailed
        case .unsupportedSource, .noDeclaredPackage, .unsupportedCask,
             .unsupportedInstallationLayout, .managerRootMismatch, .tooManyDeclaredCasks:
            .unsupportedManager
        default: .identityUnverified
        }
    }

    // MARK: Manager JSON

    /// Parses the exact fields this operation consumes. Identity, booleans, the installed value and
    /// the artifacts presence are strict; an unreadable collection is malformed, never shortened.
    static func parseInfo(_ data: Data) -> [HomebrewCaskOperationInfo]? {
        guard let text = homebrewStrictUTF8Text(data),
              let json = try? JSONSerialization.jsonObject(with: Data(text.utf8), options: []),
              let root = json as? [String: Any],
              let casks = root["casks"] as? [Any]
        else { return nil }
        var parsed: [HomebrewCaskOperationInfo] = []
        parsed.reserveCapacity(casks.count)
        for element in casks {
            guard let object = element as? [String: Any],
                  let token = object["token"] as? String,
                  let fullToken = object["full_token"] as? String,
                  let tap = object["tap"] as? String,
                  let version = object["version"] as? String,
                  HomebrewCaskUpdateProbe.isSafeVersionText(version),
                  let pinned = strictBool(object["pinned"]),
                  let outdated = strictBool(object["outdated"]),
                  let disabled = strictBool(object["disabled"]),
                  let artifactsValue = object["artifacts"],
                  let hasPackageDependencies = parsePackageDependencies(object["depends_on"]),
                  let disableReason = optionalString(object, "disable_reason"),
                  let deprecationDate = optionalString(object, "deprecation_date"),
                  let deprecationReason = optionalString(object, "deprecation_reason")
            else { return nil }
            let installed = parseInstalled(object)
            if case .malformed = installed { return nil }
            let autoUpdates: Bool?
            if object.keys.contains("auto_updates"), !(object["auto_updates"] is NSNull) {
                guard let value = strictBool(object["auto_updates"]) else { return nil }
                autoUpdates = value
            } else {
                autoUpdates = nil
            }
            let deprecated: Bool
            if object.keys.contains("deprecated"), !(object["deprecated"] is NSNull) {
                guard let value = strictBool(object["deprecated"]) else { return nil }
                deprecated = value
            } else {
                deprecated = false
            }
            parsed.append(HomebrewCaskOperationInfo(
                token: token,
                fullToken: fullToken,
                tap: tap,
                version: version,
                installed: installed,
                autoUpdates: autoUpdates,
                pinned: pinned,
                outdated: outdated,
                disabled: disabled,
                disableReason: disableReason.map { homebrewBoundedDetail($0) },
                deprecated: deprecated,
                deprecationDisclosure: deprecationDisclosure(
                    deprecated: deprecated,
                    date: deprecationDate,
                    reason: deprecationReason
                ),
                hasPackageDependencies: hasPackageDependencies,
                artifacts: parseArtifacts(artifactsValue)
            ))
        }
        return parsed
    }

    /// Fresh `depends_on` is required. Only `formula` and `cask` install packages; an empty value
    /// for either is no package dependency, a non-empty one is refused by Update. Platform and
    /// requirement keys (`macos`, `arch`, `linux`, `x11`, `java`, …) do not install packages.
    /// Missing, non-object, null, or wrong-shaped package fields are malformed, never proof of
    /// absence.
    static func parsePackageDependencies(_ value: Any?) -> Bool? {
        guard let object = value as? [String: Any] else { return nil }
        for key in ["formula", "cask"] {
            guard let dependency = object[key] else { continue }
            if dependency is NSNull { return nil }
            if let values = dependency as? [Any] {
                if !values.isEmpty { return true }
                continue
            }
            if let text = dependency as? String {
                if !text.isEmpty { return true }
                continue
            }
            return nil
        }
        return false
    }

    static func parseInstalled(_ object: [String: Any]) -> HomebrewCaskInstalledValue {
        guard object.keys.contains("installed") else { return .missing }
        if object["installed"] is NSNull { return .null }
        guard let value = object["installed"] as? String,
              HomebrewCaskUpdateProbe.isCleanPathComponent(value)
        else { return .malformed }
        return .string(value)
    }

    static func strictBool(_ value: Any?) -> Bool? {
        guard let value else { return nil }
        guard CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID() else { return nil }
        return (value as! NSNumber).boolValue
    }

    static func optionalString(_ object: [String: Any], _ key: String) -> String?? {
        guard let value = object[key] else { return .some(nil) }
        if value is NSNull { return .some(nil) }
        guard let string = value as? String else { return nil }
        return .some(string)
    }

    /// `brew list --pinned` prints one pinned token per line; a full token is accepted for the
    /// strict cross-check. Empty output is a valid "nothing pinned" answer. Malformed output is
    /// never a silent miss.
    static func parsePinnedList(_ data: Data) -> [String]? {
        guard !data.isEmpty else { return [] }
        guard let text = homebrewStrictUTF8Text(data) else { return nil }
        var names: [String] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = rawLine
            if line.last == "\r" { line = line.dropLast() }
            if line.isEmpty { continue }
            let name = String(line)
            guard !name.hasPrefix("-"),
                  HomebrewCaskUpdateProbe.isValidDeclaredCaskName(name)
            else { return nil }
            names.append(name)
        }
        return names
    }

    private static func outdatedFact(
        data: Data,
        record: HomebrewCaskOperationInfo,
        installedVersion: String
    ) -> Result<HomebrewCaskOutdatedFacts?, HomebrewCaskObservationFailure> {
        guard let records = HomebrewCaskUpdateProbe.parseOutdated(data) else {
            return .failure(.probeFailed)
        }
        let tokenRecords = records.filter { $0.name == record.token }
        if record.fullToken != record.token,
           records.contains(where: { $0.name == record.fullToken }) {
            return .failure(.identityUnverified)
        }
        guard tokenRecords.count <= 1, tokenRecords.allSatisfy(\.isValid) else {
            return .failure(.identityUnverified)
        }
        let outdated = tokenRecords.first
        if record.outdated {
            guard let outdated,
                  outdated.currentVersion == record.version,
                  outdated.installedVersions == [installedVersion],
                  outdated.pinned == record.pinned,
                  installedVersion != record.version
            else { return .failure(.identityUnverified) }
            return .success(HomebrewCaskOutdatedFacts(
                currentVersion: outdated.currentVersion,
                installedVersions: outdated.installedVersions,
                pinned: outdated.pinned
            ))
        }
        guard outdated == nil else { return .failure(.identityUnverified) }
        return .success(nil)
    }

    /// Strict artifact classification. App artifacts and unknown kinds are unsupported; an
    /// uninstall stanza is the elevation refusal. Zap is classified as disclosure-only and its
    /// values are never interpreted. Binary/command_wrapper targets must be the manager's resolved
    /// absolute path, never a product-composed guess.
    static func parseArtifacts(_ value: Any) -> HomebrewCaskArtifactParseResult {
        guard let elements = value as? [Any] else { return .malformed }
        if elements.isEmpty { return .unsupported }
        var cliArtifacts: [HomebrewCaskCliArtifact] = []
        var hasZap = false
        var hasUninstall = false
        var hasUnsupportedKind = false
        var targets = Set<String>()
        for element in elements {
            guard let object = element as? [String: Any] else { return .malformed }
            let keys = Set(object.keys).subtracting(Set(["target"]))
            guard keys.count == 1, let key = keys.first else { return .malformed }
            switch key {
            case "uninstall":
                guard object["uninstall"] is [Any] else { return .malformed }
                hasUninstall = true
            case "zap":
                guard object["zap"] is [Any] else { return .malformed }
                hasZap = true
            case "app":
                guard let target = cleanArtifactTarget(object["target"]),
                      let names = object["app"] as? [Any],
                      names.count == 1 || names.count == 2,
                      let name = names.first as? String,
                      homebrewCaskIsCleanRelativeComponent(name)
                else { return .malformed }
                if names.count == 2, !(names[1] is [String: Any]) { return .malformed }
                guard targets.insert(target).inserted else { return .malformed }
                hasUnsupportedKind = true
            case "binary":
                guard let target = cleanArtifactTarget(object["target"]),
                      let values = object["binary"] as? [Any],
                      values.count == 1 || values.count == 2,
                      let source = values.first as? String,
                      homebrewCaskIsSafeSource(source)
                else { return .malformed }
                guard case .success(let option) = parseBinaryTargetOption(values) else {
                    return .malformed
                }
                guard targets.insert(target).inserted else { return .malformed }
                cliArtifacts.append(HomebrewCaskCliArtifact(
                    kind: .binary, source: source, target: target, explicitTarget: option
                ))
            case "command_wrapper":
                guard let target = cleanArtifactTarget(object["target"]),
                      let values = object["command_wrapper"] as? [Any],
                      values.count == 1 || values.count == 2,
                      let name = values.first as? String,
                      homebrewCaskIsCleanRelativeComponent(name)
                else { return .malformed }
                // The second array element is wrapper parameters (`content`, `executable`,
                // `args`, `env`), never a target override. The target is the wrapper name.
                if values.count == 2, !(values[1] is [String: Any]) { return .malformed }
                guard targets.insert(target).inserted else { return .malformed }
                cliArtifacts.append(HomebrewCaskCliArtifact(
                    kind: .commandWrapper, source: name, target: target, explicitTarget: nil
                ))
            default:
                hasUnsupportedKind = true
            }
        }
        if hasUninstall { return .requiresElevation }
        if hasUnsupportedKind || cliArtifacts.isEmpty { return .unsupported }
        let sorted = cliArtifacts.sorted {
            $0.target == $1.target
                ? ($0.kind.rawValue, $0.source) < ($1.kind.rawValue, $1.source)
                : $0.target < $1.target
        }
        return .supported(HomebrewCaskArtifactSet(
            cliArtifacts: sorted,
            hasZap: hasZap
        ))
    }

    static func cleanArtifactTarget(_ value: Any?) -> String? {
        guard let target = value as? String,
              HomebrewCaskTargetParser.cleanedAbsolutePath(target) == target,
              target != "/",
              !HomebrewCaskTargetParser.components(of: target).contains(".metadata")
        else { return nil }
        return target
    }

    /// The serialized `binary ..., target:` option is the second array element. It is retained
    /// verbatim here and validated against the bound prefix/bin parent later; `nil` means the
    /// manager derives the target from the source basename.
    static func parseBinaryTargetOption(
        _ values: [Any]
    ) -> Result<String?, HomebrewCaskObservationFailure> {
        guard values.count == 2 else { return .success(nil) }
        guard let options = values[1] as? [String: Any],
              Set(options.keys).subtracting(["target"]).isEmpty
        else { return .failure(.metadataInvalid) }
        guard let value = options["target"] else { return .success(nil) }
        guard let text = value as? String,
              !text.isEmpty,
              !text.utf8.contains(0)
        else { return .failure(.metadataInvalid) }
        return .success(text)
    }

    /// The single live `<prefix>/bin` parent every managed CLI target must resolve through.
    static func managedTargetLinkParent(
        prefix: HomebrewCaskBoundRoot
    ) -> HomebrewCaskBoundDirectory? {
        HomebrewCaskUpdateProbe.boundDirectory(
            path: HomebrewCaskUpdateProbe.appendedPath(prefix.canonicalPath, "bin"),
            component: "bin",
            parent: prefix.identity
        )
    }

    /// The manager's target leaf. A binary uses its saved explicit target option when present and
    /// otherwise the source basename; a command_wrapper uses the wrapper name. The result is a
    /// single safe relative component, never a path.
    static func managedTargetLeaf(
        kind: HomebrewCaskArtifactKind,
        source: String,
        explicitTarget: String?
    ) -> String? {
        switch kind {
        case .binary:
            if let explicitTarget {
                if explicitTarget.hasPrefix("/") {
                    guard HomebrewCaskTargetParser.cleanedAbsolutePath(explicitTarget)
                        == explicitTarget
                    else { return nil }
                    let leaf = (explicitTarget as NSString).lastPathComponent
                    return homebrewCaskIsCleanRelativeComponent(leaf) ? leaf : nil
                }
                return homebrewCaskIsCleanRelativeComponent(explicitTarget)
                    ? explicitTarget : nil
            }
            let leaf = (source as NSString).lastPathComponent
            return homebrewCaskIsCleanRelativeComponent(leaf) ? leaf : nil
        case .commandWrapper:
            return homebrewCaskIsCleanRelativeComponent(source) ? source : nil
        }
    }

    /// True only when `target` is an exact child of the bound prefix/bin identity with the expected
    /// leaf. This accepts the manager's canonical or reported prefix spelling but never a sibling
    /// directory, a deeper path, or a retargeted `bin` parent.
    static func managedTargetMatches(
        _ target: String,
        leaf: String,
        linkParent: HomebrewCaskBoundDirectory
    ) -> Bool {
        guard HomebrewCaskTargetParser.cleanedAbsolutePath(target) == target,
              (target as NSString).lastPathComponent == leaf
        else { return false }
        let parentPath = (target as NSString).deletingLastPathComponent
        guard let parentIdentity = FileIdentityObserver.observeDirectory(path: parentPath),
              parentIdentity == linkParent.identity
        else { return false }
        return true
    }

    private static func buildManagedTargets(
        artifacts: HomebrewCaskArtifactSet,
        versionDirectory: String,
        prefix: HomebrewCaskBoundRoot
    ) -> Result<[HomebrewCaskManagedTarget], HomebrewCaskObservationFailure> {
        guard let linkParent = managedTargetLinkParent(prefix: prefix) else {
            return .failure(.caskArtifactTargetUnverified)
        }
        var result: [HomebrewCaskManagedTarget] = []
        result.reserveCapacity(artifacts.cliArtifacts.count)
        for artifact in artifacts.cliArtifacts {
            guard let leaf = managedTargetLeaf(
                kind: artifact.kind,
                source: artifact.source,
                explicitTarget: artifact.explicitTarget
            ), managedTargetMatches(
                artifact.target, leaf: leaf, linkParent: linkParent
            ) else { return .failure(.caskArtifactTargetUnverified) }
            if let explicitTarget = artifact.explicitTarget,
               explicitTarget.hasPrefix("/"),
               !managedTargetMatches(
                   explicitTarget, leaf: leaf, linkParent: linkParent
               ) {
                return .failure(.caskArtifactTargetUnverified)
            }

            let sourcePath: String
            switch artifact.kind {
            case .binary:
                if artifact.source.hasPrefix("/") {
                    guard HomebrewCaskTargetParser.cleanedAbsolutePath(artifact.source)
                        == artifact.source,
                          !HomebrewCaskTargetParser.components(of: artifact.source)
                            .contains(".metadata"),
                          FileIdentityObserver.isStrictDescendant(
                            artifact.source, of: versionDirectory
                          )
                    else { return .failure(.caskArtifactTargetUnverified) }
                    sourcePath = artifact.source
                } else {
                    guard homebrewCaskIsCleanRelativePath(artifact.source) else {
                        return .failure(.caskArtifactTargetUnverified)
                    }
                    sourcePath = versionDirectory + "/" + artifact.source
                }
            case .commandWrapper:
                guard homebrewCaskIsCleanRelativeComponent(artifact.source) else {
                    return .failure(.caskArtifactTargetUnverified)
                }
                sourcePath = versionDirectory
                    + "/.homebrew-command-wrappers/" + artifact.source
            }
            guard homebrewCaskIsRegularFile(sourcePath) else {
                return .failure(.caskArtifactTargetUnverified)
            }
            let presence: HomebrewCaskTargetPresence
            switch observeManagedTarget(
                path: artifact.target,
                sourcePath: sourcePath,
                linkParent: linkParent,
                prefixRoot: prefix
            ) {
            case .failure:
                return .failure(.caskArtifactTargetUnverified)
            case .success(let value):
                presence = value
            }
            result.append(HomebrewCaskManagedTarget(
                artifact: artifact,
                sourcePath: sourcePath,
                presence: presence,
                linkParent: linkParent,
                prefixRoot: prefix
            ))
        }
        return .success(result)
    }

    static func managedTargetIsLive(_ target: HomebrewCaskManagedTarget) -> Bool {
        guard target.prefixRoot.isCurrent,
              target.linkParent.isCurrent(parent: target.prefixRoot.identity),
              homebrewCaskIsRegularFile(target.sourcePath)
        else { return false }
        switch observeManagedTarget(
            path: target.artifact.target,
            sourcePath: target.sourcePath,
            linkParent: target.linkParent,
            prefixRoot: target.prefixRoot
        ) {
        case .failure:
            return false
        case .success(let presence):
            return presence == target.presence
        }
    }

    static func observeManagedTarget(
        path: String,
        sourcePath: String,
        linkParent: HomebrewCaskBoundDirectory,
        prefixRoot: HomebrewCaskBoundRoot
    ) -> Result<HomebrewCaskTargetPresence, HomebrewCaskObservationFailure> {
        guard prefixRoot.isCurrent,
              linkParent.isCurrent(parent: prefixRoot.identity)
        else { return .failure(.caskArtifactTargetUnverified) }
        let parentPath = (path as NSString).deletingLastPathComponent
        guard let parentIdentity = FileIdentityObserver.observeDirectory(path: parentPath),
              parentIdentity == linkParent.identity
        else { return .failure(.caskArtifactTargetUnverified) }

        var info = Darwin.stat()
        let status = path.withCString { Darwin.lstat($0, &info) }
        if status != 0 {
            let code = errno
            return (code == ENOENT || code == ENOTDIR)
                ? .success(.absent) : .failure(.caskArtifactTargetUnverified)
        }
        guard (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFLNK),
              let observed = FileIdentityObserver.observeExecutable(entryPath: path),
              homebrewCaskPathsEqual(observed.canonicalTarget, sourcePath)
        else { return .failure(.caskArtifactTargetUnverified) }
        return .success(.linked)
    }

    private static func deprecationDisclosure(
        deprecated: Bool,
        date: String?,
        reason: String?
    ) -> String? {
        guard deprecated else { return nil }
        var parts = ["Homebrew marks this cask as deprecated."]
        if let date, !date.isEmpty {
            parts.append("Deprecated on \(homebrewBoundedDetail(date)).")
        }
        if let reason, !reason.isEmpty {
            parts.append("Reason: \(homebrewBoundedDetail(reason)).")
        }
        parts.append("The operation remains available; no replacement is installed automatically.")
        return parts.joined(separator: " ")
    }
}

// MARK: - Saved installed metadata

// Homebrew's teardown path loads the saved installed definition (and its receipt), never only the
// current tap source. These readers are deliberately narrow: bounded directory rosters, bounded
// regular-file opens relative to a verified descriptor, O_NOFOLLOW, and strict JSON. A missing,
// oversized, malformed, symlinked or ambiguous record refuses; it never falls back to the current
// manifest as proof that no teardown stanza existed.

extension HomebrewCaskObservation {
    static let maximumSavedMetadataBytes = 256 * 1024
    static let maximumSavedMetadataEntries = 256
    static let maximumSavedMetadataCandidates = 1024

    static func observeInstalledMetadata(
        caskroom: HomebrewCaskBoundRoot,
        tokenDirectory: HomebrewCaskBoundDirectory,
        stagedVersionDirectory: HomebrewCaskBoundDirectory,
        token: String,
        fullToken: String,
        tap: String,
        installedVersion: String,
        prefix: HomebrewCaskBoundRoot
    ) -> Result<HomebrewCaskInstalledMetadata, HomebrewCaskObservationFailure> {
        guard HomebrewCaskUpdateProbe.isCleanPathComponent(token),
              HomebrewCaskUpdateProbe.isCleanPathComponent(installedVersion),
              installedVersion != ".metadata",
              tokenDirectory.isCurrent(parent: caskroom.identity),
              stagedVersionDirectory.isCurrent(parent: tokenDirectory.identity)
        else { return .failure(.metadataInvalid) }

        let metadataPath = HomebrewCaskUpdateProbe.appendedPath(
            tokenDirectory.identity.canonicalPath, ".metadata"
        )
        guard let metadataDirectory = HomebrewCaskUpdateProbe.boundDirectory(
            path: metadataPath,
            component: ".metadata",
            parent: tokenDirectory.identity
        ), let metadataEntries = boundedSavedDirectoryEntries(metadataDirectory),
           metadataEntries.contains("INSTALL_RECEIPT.json"),
           let receipt = readSavedRegularFile(
               directory: metadataDirectory, name: "INSTALL_RECEIPT.json"
           )
        else { return .failure(.metadataInvalid) }

        // `.metadata/config.json` and (for `latest`) `.metadata/LATEST_DOWNLOAD_SHA256` are
        // ordinary install siblings, never version directories. Config can influence the
        // installed cask's artifact configuration, so it is read and bound byte-for-byte; its
        // meaning is never interpreted. Every other entry must be a real version directory.
        var versionDirectories: [HomebrewCaskBoundDirectory] = []
        var config: HomebrewCaskSavedFile?
        for name in metadataEntries {
            switch name {
            case "INSTALL_RECEIPT.json":
                continue
            case "config.json":
                guard savedEntryIsRegular(metadataDirectory, name: name),
                      let read = readSavedRegularFile(
                          directory: metadataDirectory, name: name
                      )
                else { return .failure(.metadataInvalid) }
                config = read
            case "LATEST_DOWNLOAD_SHA256":
                guard savedEntryIsRegular(metadataDirectory, name: name) else {
                    return .failure(.metadataInvalid)
                }
            default:
                guard HomebrewCaskUpdateProbe.isCleanPathComponent(name),
                      savedEntryIsDirectory(metadataDirectory, name: name),
                      let directory = HomebrewCaskUpdateProbe.boundDirectory(
                          path: metadataDirectory.identity.canonicalPath + "/" + name,
                          component: name,
                          parent: metadataDirectory.identity
                      )
                else { return .failure(.metadataInvalid) }
                versionDirectories.append(directory)
            }
        }
        guard !versionDirectories.isEmpty else { return .failure(.metadataInvalid) }

        guard let receiptObject = savedJSONObject(receipt.data) else {
            return .failure(.metadataInvalid)
        }

        // Homebrew selects the greatest timestamp across every metadata version before looking for
        // a caskfile. Determine that exact winner first; never skip a newer empty/legacy directory
        // in favor of an older valid file. Ties are ambiguous and refuse.
        var greatestTimestamp: String?
        var selectedVersionDirectory: HomebrewCaskBoundDirectory?
        var selectedTimestampDirectory: HomebrewCaskBoundDirectory?
        var greatestCount = 0
        var visitedTimestampDirectories = 0
        for versionDirectory in versionDirectories {
            guard let timestampEntries = boundedSavedDirectoryEntries(versionDirectory) else {
                return .failure(.metadataInvalid)
            }
            for timestamp in timestampEntries {
                guard isSavedTimestampName(timestamp),
                      savedEntryIsDirectory(versionDirectory, name: timestamp),
                      let timestampDirectory = HomebrewCaskUpdateProbe.boundDirectory(
                          path: versionDirectory.identity.canonicalPath + "/" + timestamp,
                          component: timestamp,
                          parent: versionDirectory.identity
                      )
                else { return .failure(.metadataInvalid) }
                visitedTimestampDirectories += 1
                guard visitedTimestampDirectories <= maximumSavedMetadataCandidates else {
                    return .failure(.metadataInvalid)
                }
                if let current = greatestTimestamp {
                    if timestamp > current {
                        greatestTimestamp = timestamp
                        selectedVersionDirectory = versionDirectory
                        selectedTimestampDirectory = timestampDirectory
                        greatestCount = 1
                    } else if timestamp == current {
                        greatestCount += 1
                    }
                } else {
                    greatestTimestamp = timestamp
                    selectedVersionDirectory = versionDirectory
                    selectedTimestampDirectory = timestampDirectory
                    greatestCount = 1
                }
            }
        }
        guard greatestTimestamp != nil,
              greatestCount == 1,
              let selectedVersionDirectory,
              let selectedTimestampDirectory
        else { return .failure(.metadataInvalid) }
        guard selectedVersionDirectory.component == installedVersion else {
            return .failure(.identityUnverified)
        }

        // Only the winning timestamp is inspected. Its Casks directory must hold exactly the
        // supported `<token>.json`; legacy Ruby/internal JSON can carry executable teardown and is
        // never read or accepted.
        guard let timestampEntries = boundedSavedDirectoryEntries(selectedTimestampDirectory),
              timestampEntries == ["Casks"],
              savedEntryIsDirectory(selectedTimestampDirectory, name: "Casks"),
              let casksDirectory = HomebrewCaskUpdateProbe.boundDirectory(
                  path: selectedTimestampDirectory.identity.canonicalPath + "/Casks",
                  component: "Casks",
                  parent: selectedTimestampDirectory.identity
              ),
              let caskEntries = boundedSavedDirectoryEntries(casksDirectory),
              caskEntries == [token + ".json"],
              savedEntryIsRegular(casksDirectory, name: caskEntries[0]),
              let caskFile = readSavedRegularFile(
                  directory: casksDirectory, name: caskEntries[0]
              )
        else { return .failure(.metadataInvalid) }
        guard let caskObject = savedJSONObject(caskFile.data) else {
            return .failure(.metadataInvalid)
        }

        // Continuity against the already-verified token/tap/version. Absent optional keys are
        // acceptable; a present conflicting value is not an observation.
        for (key, expected) in [
            ("token", token),
            ("full_token", fullToken),
            ("tap", tap),
            ("version", installedVersion),
        ] {
            guard let value = optionalString(caskObject, key) else {
                return .failure(.metadataInvalid)
            }
            if let value, value != expected { return .failure(.identityUnverified) }
        }

        // The saved installed definition is the manager's teardown source. A known uninstall
        // stanza refuses with elevation even before the receipt is classified, so a malformed or
        // unsupported receipt can never hide it.
        let savedArtifactsResult: HomebrewCaskInstalledArtifactParseResult? =
            caskObject["artifacts"].map { parseInstalledArtifacts($0) }
        if savedArtifactsResult?.isElevation == true {
            return .failure(.caskUninstallRequiresElevation)
        }

        // Receipt identity and flight-block fields are strict. Artifact classification is retained
        // so saved JSON and receipt are both inspected before selecting one refusal reason.
        guard let source = receiptObject["source"] as? [String: Any],
              let sourceTap = source["tap"] as? String,
              let sourceVersion = source["version"] as? String,
              let flightBlocks = strictBool(receiptObject["uninstall_flight_blocks"]),
              let receiptArtifactsValue = receiptObject["uninstall_artifacts"]
        else { return .failure(.metadataInvalid) }
        guard sourceTap == tap, sourceVersion == installedVersion else {
            return .failure(.identityUnverified)
        }
        let receiptArtifactsResult = parseInstalledArtifacts(receiptArtifactsValue)

        // A known uninstall stanza or flight block is an elevation refusal even when the other
        // snapshot also declares an unsupported artifact. Malformed data never hides that refusal,
        // and malformed data outranks a merely unsupported artifact surface.
        if flightBlocks
            || receiptArtifactsResult.isElevation
            || savedArtifactsResult?.isElevation == true {
            return .failure(.caskUninstallRequiresElevation)
        }
        if receiptArtifactsResult.isMalformed
            || savedArtifactsResult?.isMalformed == true {
            return .failure(.metadataInvalid)
        }
        if receiptArtifactsResult.isUnsupported
            || savedArtifactsResult?.isUnsupported == true {
            return .failure(.caskOperationUnsupported)
        }
        guard case .supported(let receiptArtifacts) = receiptArtifactsResult else {
            return .failure(.metadataInvalid)
        }
        let savedArtifacts: HomebrewCaskInstalledArtifactSet?
        if let savedArtifactsResult {
            guard case .supported(let value) = savedArtifactsResult else {
                return .failure(.metadataInvalid)
            }
            savedArtifacts = value
        } else {
            savedArtifacts = nil
        }
        let installedArtifacts = savedArtifacts ?? receiptArtifacts

        let managedTargets: [HomebrewCaskManagedTarget]
        switch buildInstalledManagedTargets(
            installedArtifacts,
            installedVersionDirectory: stagedVersionDirectory.identity.canonicalPath,
            prefix: prefix
        ) {
        case .failure(let failure):
            return .failure(failure)
        case .success(let value):
            managedTargets = value
        }

        return .success(HomebrewCaskInstalledMetadata(
            metadataDirectory: metadataDirectory,
            versionDirectory: selectedVersionDirectory,
            timestampDirectory: selectedTimestampDirectory,
            casksDirectory: casksDirectory,
            receipt: receipt,
            caskFile: caskFile,
            config: config,
            artifacts: installedArtifacts,
            managedTargets: managedTargets
        ))
    }

    /// Re-runs the complete bounded saved-metadata observation and compares the retained snapshot.
    /// Used after async manager queries and immediately before launch.
    static func installedMetadataIsLive(
        _ metadata: HomebrewCaskInstalledMetadata,
        caskroom: HomebrewCaskBoundRoot,
        tokenDirectory: HomebrewCaskBoundDirectory,
        stagedVersionDirectory: HomebrewCaskBoundDirectory,
        token: String,
        fullToken: String,
        tap: String,
        installedVersion: String,
        prefix: HomebrewCaskBoundRoot
    ) -> Bool {
        guard case .success(let fresh) = observeInstalledMetadata(
            caskroom: caskroom,
            tokenDirectory: tokenDirectory,
            stagedVersionDirectory: stagedVersionDirectory,
            token: token,
            fullToken: fullToken,
            tap: tap,
            installedVersion: installedVersion,
            prefix: prefix
        ) else { return false }
        return fresh == metadata
    }

    static func disclosureTargets(
        mode: HomebrewCaskObservationMode,
        current: [HomebrewCaskManagedTarget],
        installed: [HomebrewCaskManagedTarget]
    ) -> Result<[HomebrewCaskArtifactTarget], HomebrewCaskObservationFailure> {
        let selected: [HomebrewCaskManagedTarget]
        switch mode {
        case .update:
            selected = current + installed
        case .uninstall:
            selected = installed
        }
        // Disclosure is the only projection: every managed target keeps its reported path for
        // live confirmation. The same physical target can arrive under the manager's alias
        // spelling and the canonical prefix/bin spelling, so compare the already bound bin
        // directory identity plus the exact validated leaf, never the lexical path. The leaf is
        // never realpath-resolved here: that would follow the managed link itself.
        var result: [(target: HomebrewCaskArtifactTarget, identity: DirectoryIdentity, leaf: String)] = []
        result.reserveCapacity(selected.count)
        for managed in selected {
            guard let leaf = managedTargetLeaf(
                kind: managed.artifact.kind,
                source: managed.artifact.source,
                explicitTarget: managed.artifact.explicitTarget
            ), (managed.artifact.target as NSString).lastPathComponent == leaf
            else { return .failure(.caskArtifactTargetUnverified) }
            let target = HomebrewCaskArtifactTarget(
                kind: managed.artifact.kind,
                target: managed.linkParent.identity.canonicalPath + "/" + leaf,
                presence: managed.presence
            )
            if let index = result.firstIndex(where: {
                $0.identity == managed.linkParent.identity && $0.leaf == leaf
            }) {
                guard result[index].target.kind == target.kind,
                      result[index].target.presence == target.presence
                else { return .failure(.caskArtifactTargetUnverified) }
            } else {
                result.append((target, managed.linkParent.identity, leaf))
            }
        }
        return .success(result.map { $0.target }.sorted { $0.target < $1.target })
    }

    // MARK: Bounded saved metadata reads

    /// Bounded `readdir(3)` roster over the verified directory descriptor. A directory holding
    /// more entries than this proof can classify is refused, not shortened.
    private static func boundedSavedDirectoryEntries(
        _ directory: HomebrewCaskBoundDirectory
    ) -> [String]? {
        guard let descriptor = FileIdentityObserver.openVerifiedDirectory(
            path: directory.identity.canonicalPath,
            expected: directory.identity
        ) else { return nil }
        guard let stream = fdopendir(descriptor) else {
            _ = Darwin.close(descriptor)
            return nil
        }
        defer { _ = closedir(stream) }
        var names: [String] = []
        while true {
            errno = 0
            guard let entry = readdir(stream) else {
                return errno == 0 ? names.sorted() : nil
            }
            let name = withUnsafePointer(to: entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) {
                    String(cString: $0)
                }
            }
            if name == "." || name == ".." { continue }
            if name.isEmpty || name.contains("/") || name.utf8.contains(0) {
                return nil
            }
            if names.count >= maximumSavedMetadataEntries { return nil }
            names.append(name)
        }
    }

    private static func savedEntryInfo(
        _ directory: HomebrewCaskBoundDirectory,
        name: String
    ) -> stat? {
        guard !name.isEmpty, !name.contains("/"), !name.utf8.contains(0) else { return nil }
        var info = Darwin.stat()
        let status = (directory.identity.canonicalPath + "/" + name).withCString {
            Darwin.lstat($0, &info)
        }
        return status == 0 ? info : nil
    }

    private static func savedEntryExists(
        _ directory: HomebrewCaskBoundDirectory,
        name: String
    ) -> Bool {
        savedEntryInfo(directory, name: name) != nil
    }

    private static func savedEntryIsDirectory(
        _ directory: HomebrewCaskBoundDirectory,
        name: String
    ) -> Bool {
        guard let info = savedEntryInfo(directory, name: name) else { return false }
        return FileIdentityObserver.isDirectory(info.st_mode)
    }

    private static func savedEntryIsRegular(
        _ directory: HomebrewCaskBoundDirectory,
        name: String
    ) -> Bool {
        guard let info = savedEntryInfo(directory, name: name) else { return false }
        return FileIdentityObserver.isRegular(info.st_mode)
    }

    /// One bounded regular-file read through a verified directory descriptor. The final component
    /// is opened with O_NOFOLLOW and the descriptor must remain the same regular vnode with the
    /// same content size for the whole read.
    private static func readSavedRegularFile(
        directory: HomebrewCaskBoundDirectory,
        name: String
    ) -> HomebrewCaskSavedFile? {
        guard !name.isEmpty, !name.contains("/"), !name.utf8.contains(0),
              let directoryDescriptor = FileIdentityObserver.openVerifiedDirectory(
                  path: directory.identity.canonicalPath,
                  expected: directory.identity
              )
        else { return nil }
        defer { _ = Darwin.close(directoryDescriptor) }

        var pathInfo = Darwin.stat()
        let pathStatus = name.withCString {
            Darwin.fstatat(
                directoryDescriptor, $0, &pathInfo, AT_SYMLINK_NOFOLLOW
            )
        }
        guard pathStatus == 0, FileIdentityObserver.isRegular(pathInfo.st_mode) else {
            return nil
        }

        let descriptor = name.withCString {
            Darwin.openat(
                directoryDescriptor,
                $0,
                O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC
            )
        }
        guard descriptor >= 0 else { return nil }
        defer { _ = Darwin.close(descriptor) }

        var info = Darwin.stat()
        guard Darwin.fstat(descriptor, &info) == 0,
              FileIdentityObserver.isRegular(info.st_mode),
              info.st_size >= 0,
              UInt64(info.st_size) <= UInt64(maximumSavedMetadataBytes),
              info.st_dev == pathInfo.st_dev,
              info.st_ino == pathInfo.st_ino
        else { return nil }

        var data = Data()
        data.reserveCapacity(Int(info.st_size))
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { bytes -> Int in
                guard let base = bytes.baseAddress else { return 0 }
                return Darwin.read(descriptor, base, bytes.count)
            }
            if count < 0 { return nil }
            if count == 0 { break }
            if data.count + count > maximumSavedMetadataBytes { return nil }
            data.append(contentsOf: buffer[0..<count])
        }
        var after = Darwin.stat()
        guard Darwin.fstat(descriptor, &after) == 0,
              FileIdentityObserver.fingerprint(after)
                  == FileIdentityObserver.fingerprint(info),
              data.count == Int(info.st_size)
        else { return nil }

        return HomebrewCaskSavedFile(
            directory: directory,
            name: name,
            path: directory.identity.canonicalPath + "/" + name,
            fingerprint: FileIdentityObserver.fingerprint(info),
            data: data
        )
    }

    // MARK: Saved metadata parsing

    private static func savedJSONObject(_ data: Data) -> [String: Any]? {
        guard let text = homebrewStrictUTF8Text(data),
              let json = try? JSONSerialization.jsonObject(
                  with: Data(text.utf8), options: []
              ),
              let object = json as? [String: Any]
        else { return nil }
        return object
    }

    /// Strict saved-artifact classification. Unlike the current source, a receipt normally omits
    /// the resolved top-level target. Every stanza kind is still recognized: uninstall refuses
    /// before its payload is inspected, app/unknown refuses as unsupported, and zap is never read.
    private static func parseInstalledArtifacts(
        _ value: Any
    ) -> HomebrewCaskInstalledArtifactParseResult {
        guard let elements = value as? [Any] else { return .malformed }
        if elements.isEmpty { return .unsupported }
        var cliArtifacts: [HomebrewCaskInstalledArtifact] = []
        var hasZap = false
        var hasUninstall = false
        var hasUnsupportedKind = false
        var sources = Set<String>()
        for element in elements {
            guard let object = element as? [String: Any] else { return .malformed }
            let keys = Set(object.keys).subtracting(Set(["target"]))
            guard keys.count == 1, let key = keys.first else { return .malformed }
            switch key {
            case "uninstall":
                guard object["uninstall"] is [Any] else { return .malformed }
                hasUninstall = true
            case "zap":
                guard object["zap"] is [Any] else { return .malformed }
                hasZap = true
            case "app":
                guard let names = object["app"] as? [Any],
                      names.count == 1 || names.count == 2,
                      let name = names.first as? String,
                      homebrewCaskIsCleanRelativeComponent(name)
                else { return .malformed }
                if names.count == 2, !(names[1] is [String: Any]) { return .malformed }
                hasUnsupportedKind = true
            case "binary":
                let target: String?
                if object.keys.contains("target") {
                    guard let cleaned = cleanArtifactTarget(object["target"]) else {
                        return .malformed
                    }
                    target = cleaned
                } else {
                    target = nil
                }
                guard let values = object["binary"] as? [Any],
                      values.count == 1 || values.count == 2,
                      let source = values.first as? String,
                      homebrewCaskIsSafeSource(source),
                      case .success(let explicitTarget) = parseBinaryTargetOption(values)
                else { return .malformed }
                guard sources.insert("binary\0" + source).inserted else {
                    return .malformed
                }
                cliArtifacts.append(HomebrewCaskInstalledArtifact(
                    kind: .binary,
                    source: source,
                    target: target,
                    explicitTarget: explicitTarget
                ))
            case "command_wrapper":
                let target: String?
                if object.keys.contains("target") {
                    guard let cleaned = cleanArtifactTarget(object["target"]) else {
                        return .malformed
                    }
                    target = cleaned
                } else {
                    target = nil
                }
                guard let values = object["command_wrapper"] as? [Any],
                      values.count == 1 || values.count == 2,
                      let name = values.first as? String,
                      homebrewCaskIsCleanRelativeComponent(name)
                else { return .malformed }
                // Wrapper parameters are not a target override; the target is the wrapper name.
                if values.count == 2, !(values[1] is [String: Any]) { return .malformed }
                guard sources.insert("wrapper\0" + name).inserted else {
                    return .malformed
                }
                cliArtifacts.append(HomebrewCaskInstalledArtifact(
                    kind: .commandWrapper,
                    source: name,
                    target: target,
                    explicitTarget: nil
                ))
            default:
                hasUnsupportedKind = true
            }
        }
        if hasUninstall { return .requiresElevation }
        if hasUnsupportedKind || cliArtifacts.isEmpty { return .unsupported }
        let sorted = cliArtifacts.sorted {
            $0.target == $1.target
                ? ($0.kind.rawValue, $0.source) < ($1.kind.rawValue, $1.source)
                : ($0.target ?? "") < ($1.target ?? "")
        }
        return .supported(HomebrewCaskInstalledArtifactSet(
            cliArtifacts: sorted,
            hasZap: hasZap
        ))
    }

    private static func buildInstalledManagedTargets(
        _ artifacts: HomebrewCaskInstalledArtifactSet,
        installedVersionDirectory: String,
        prefix: HomebrewCaskBoundRoot
    ) -> Result<[HomebrewCaskManagedTarget], HomebrewCaskObservationFailure> {
        guard let linkParent = managedTargetLinkParent(prefix: prefix) else {
            return .failure(.caskArtifactTargetUnverified)
        }
        var result: [HomebrewCaskManagedTarget] = []
        for artifact in artifacts.cliArtifacts {
            guard let leaf = managedTargetLeaf(
                kind: artifact.kind,
                source: artifact.source,
                explicitTarget: artifact.explicitTarget
            ) else { return .failure(.caskArtifactTargetUnverified) }

            // An absolute explicit option must itself be an exact child of prefix/bin. A relative
            // option is the leaf Homebrew expands beneath prefix/bin. The top-level resolved
            // target, when the saved document carries one, must agree with that same leaf and
            // parent identity.
            if let explicitTarget = artifact.explicitTarget, explicitTarget.hasPrefix("/") {
                guard managedTargetMatches(
                    explicitTarget, leaf: leaf, linkParent: linkParent
                ) else { return .failure(.caskArtifactTargetUnverified) }
            }
            let target: String
            if let savedTarget = artifact.target {
                guard managedTargetMatches(
                    savedTarget, leaf: leaf, linkParent: linkParent
                ) else { return .failure(.caskArtifactTargetUnverified) }
                target = savedTarget
            } else {
                // The receipt normally omits the resolved target even for an explicit alias. The
                // manager's exact default is prefix/bin/<leaf>; this is a verified derivation, not
                // a borrowed current-manifest path and not a guessed absolute path.
                target = linkParent.identity.canonicalPath + "/" + leaf
            }

            let sourcePath: String
            switch artifact.kind {
            case .binary:
                if artifact.source.hasPrefix("/") {
                    guard HomebrewCaskTargetParser.cleanedAbsolutePath(artifact.source)
                        == artifact.source,
                          !HomebrewCaskTargetParser.components(of: artifact.source)
                            .contains(".metadata"),
                          FileIdentityObserver.isStrictDescendant(
                              artifact.source, of: installedVersionDirectory
                          )
                    else { return .failure(.caskArtifactTargetUnverified) }
                    sourcePath = artifact.source
                } else {
                    guard homebrewCaskIsCleanRelativePath(artifact.source) else {
                        return .failure(.caskArtifactTargetUnverified)
                    }
                    sourcePath = installedVersionDirectory + "/" + artifact.source
                }
            case .commandWrapper:
                guard homebrewCaskIsCleanRelativeComponent(artifact.source) else {
                    return .failure(.caskArtifactTargetUnverified)
                }
                sourcePath = installedVersionDirectory
                    + "/.homebrew-command-wrappers/" + artifact.source
            }
            guard homebrewCaskIsRegularFile(sourcePath) else {
                return .failure(.caskArtifactTargetUnverified)
            }
            let presence: HomebrewCaskTargetPresence
            switch observeManagedTarget(
                path: target,
                sourcePath: sourcePath,
                linkParent: linkParent,
                prefixRoot: prefix
            ) {
            case .failure:
                return .failure(.caskArtifactTargetUnverified)
            case .success(let value):
                presence = value
            }
            if let existing = result.first(where: {
                homebrewCaskPathsEqual($0.artifact.target, target)
            }) {
                guard existing.sourcePath == sourcePath,
                      existing.artifact.kind == artifact.kind,
                      existing.presence == presence
                else { return .failure(.caskArtifactTargetUnverified) }
                continue
            }
            result.append(HomebrewCaskManagedTarget(
                artifact: HomebrewCaskCliArtifact(
                    kind: artifact.kind,
                    source: artifact.source,
                    target: target,
                    explicitTarget: artifact.explicitTarget
                ),
                sourcePath: sourcePath,
                presence: presence,
                linkParent: linkParent,
                prefixRoot: prefix
            ))
        }
        return .success(result.sorted {
            $0.artifact.target == $1.artifact.target
                ? ($0.artifact.kind.rawValue, $0.artifact.source)
                    < ($1.artifact.kind.rawValue, $1.artifact.source)
                : $0.artifact.target < $1.artifact.target
        })
    }

    /// Homebrew timestamps are `%Y%m%d%H%M%S.%L` directory names: exactly 14 digits, a dot, and
    /// 3 digits (`20261126085347.911`). Fixed width keeps lexicographic and chronological order
    /// identical; anything else fails closed.
    private static func isSavedTimestampName(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == 18, bytes[14] == 0x2E else { return false }
        for index in 0..<14 where bytes[index] < 0x30 || bytes[index] > 0x39 {
            return false
        }
        for index in 15..<18 where bytes[index] < 0x30 || bytes[index] > 0x39 {
            return false
        }
        return true
    }
}

// MARK: - Shared cask helpers

struct HomebrewCaskBoundRoots: Equatable, Sendable {
    let prefix: HomebrewCaskBoundRoot
    let caskroom: HomebrewCaskBoundRoot
}

func homebrewCaskSelectionPair(
    _ diagnostic: ToolPathDiagnostic
) -> (entry: String, target: String)? {
    homebrewFormulaSelectionPair(diagnostic)
}

func homebrewCaskAliases(_ diagnostic: ToolPathDiagnostic) -> [String] {
    diagnostic.pathCandidates.map(\.entryPath)
}

enum HomebrewCaskProofIdentity {
    /// The manager-returned token/full_token/tap triple is the only dynamic argv identity. It must
    /// agree structurally and must not look like a flag or command text.
    static func isSafeProofName(
        token: String,
        fullToken: String,
        tap: String
    ) -> Bool {
        !fullToken.isEmpty
            && !fullToken.hasPrefix("-")
            && !fullToken.contains("\n")
            && HomebrewCaskUpdateProbe.isStructurallyValidCask(
                token: token, fullToken: fullToken, tap: tap
            )
    }
}

func homebrewCaskManagerIsLive(_ manager: ObservedExecutable) -> Bool {
    FileIdentityObserver.observeExecutable(entryPath: manager.entryPath) == manager
}

func homebrewCaskSelectionIsLive(
    _ selection: ObservedExecutable,
    manager: ObservedExecutable
) -> Bool {
    FileIdentityObserver.observeExecutable(entryPath: selection.entryPath) == selection
        && homebrewCaskManagerIsLive(manager)
}

func homebrewCaskIdentityIsLive(
    manager: ObservedExecutable,
    selection: ObservedExecutable
) -> Bool {
    homebrewCaskSelectionIsLive(selection, manager: manager)
}

func homebrewCaskProofIsLive(
    roots: HomebrewCaskBoundRoots,
    manager: ObservedExecutable,
    selection: ObservedExecutable
) -> Bool {
    homebrewCaskIdentityIsLive(manager: manager, selection: selection)
        && roots.prefix.isCurrent
        && roots.caskroom.isCurrent
}

func homebrewCaskPathsEqual(_ lhs: String, _ rhs: String) -> Bool {
    guard let left = HomebrewCaskTargetParser.cleanedAbsolutePath(lhs),
          let right = HomebrewCaskTargetParser.cleanedAbsolutePath(rhs)
    else { return false }
    return HomebrewCaskTargetParser.components(of: left)
        == HomebrewCaskTargetParser.components(of: right)
}

/// Lexically collapses `.` and `..` for a readlink destination. Homebrew's ordinary relative link
/// text uses `..`; rejecting it as unclean would misreport a real dangling residue. The input is
/// never passed to the filesystem here, and a traversal above `/` is refused.
func homebrewCaskLexicallyNormalizedAbsolutePath(_ path: String) -> String? {
    guard path.hasPrefix("/"), !path.utf8.contains(0) else { return nil }
    var components: [String] = []
    for component in path.split(separator: "/", omittingEmptySubsequences: true) {
        let name = String(component)
        if name == "." { continue }
        if name == ".." {
            guard !components.isEmpty else { return nil }
            components.removeLast()
        } else {
            components.append(name)
        }
    }
    return "/" + components.joined(separator: "/")
}

/// The normalized destination of a symlink at `path`. A relative destination is resolved against
/// the link's parent and then lexically normalized; the target need not exist.
func homebrewCaskReadLink(_ path: String) -> String? {
    var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
    let count = path.withCString { Darwin.readlink($0, &buffer, buffer.count) }
    guard count > 0, count < buffer.count else { return nil }
    let text = String(
        decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
        as: UTF8.self
    )
    guard !text.isEmpty, !text.utf8.contains(0) else { return nil }
    if text.hasPrefix("/") {
        return homebrewCaskLexicallyNormalizedAbsolutePath(text)
    }
    let parent = (path as NSString).deletingLastPathComponent
    return homebrewCaskLexicallyNormalizedAbsolutePath(parent + "/" + text)
}

func homebrewCaskIsRegularFile(_ path: String) -> Bool {
    guard path.hasPrefix("/"), !path.utf8.contains(0) else { return false }
    var info = Darwin.stat()
    guard path.withCString({ Darwin.lstat($0, &info) }) == 0 else { return false }
    return (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG)
}

func homebrewCaskIsCleanRelativeComponent(_ value: String) -> Bool {
    !value.isEmpty
        && value != "."
        && value != ".."
        && value != ".metadata"
        && !value.contains("/")
        && !value.utf8.contains(0)
}

func homebrewCaskIsSafeSource(_ source: String) -> Bool {
    if source.hasPrefix("/") {
        return HomebrewCaskTargetParser.cleanedAbsolutePath(source) == source
            && !HomebrewCaskTargetParser.components(of: source).contains(".metadata")
    }
    return homebrewCaskIsCleanRelativePath(source)
}

func homebrewCaskIsCleanRelativePath(_ value: String) -> Bool {
    guard !value.isEmpty, !value.hasPrefix("/"), !value.utf8.contains(0) else {
        return false
    }
    for component in value.split(separator: "/", omittingEmptySubsequences: false) {
        let name = String(component)
        guard !name.isEmpty, name != ".", name != "..", name != ".metadata" else {
            return false
        }
    }
    return true
}

/// Post-launch ownership re-verification shared by both cask operations. A missing selection is
/// recorded as `notInstalled`, not as a failed verification.
func homebrewCaskReconcileOwnership(
    definition: DetectorDefinition,
    diagnostic: ToolPathDiagnostic,
    environment: ShellEnvironment,
    runner: UpdateCommandRunner,
    currentDirectory: String
) async -> (InstallationOwnershipOutcome?, String?) {
    guard homebrewCaskSelectionPair(diagnostic) != nil else {
        return (.unknown(.notInstalled), nil)
    }
    let observed = await InstallationOwnershipVerifier.verify(
        definition: definition,
        diagnostic: diagnostic,
        environment: environment,
        runner: runner,
        currentDirectory: currentDirectory,
        now: { Date() }
    )
    return (observed.outcome, nil)
}

/// The explicit-root and captured-TMPDIR behavior shared by both cask preparations. It matches the
/// formula operation: an injected root wins, an explicit captured TMPDIR must validate, and only a
/// missing TMPDIR falls back to Foundation's temporary directory.
func homebrewCaskScratchBase(
    environment: ShellEnvironment,
    operationRootBaseURL: URL?
) -> URL? {
    if let operationRootBaseURL { return operationRootBaseURL }
    if environment.raw["TMPDIR"] != nil {
        guard let captured = capturedTemporaryDirectory(environment),
              NpmScratchBase(url: captured) != nil
        else { return nil }
        return captured
    }
    return FileManager.default.temporaryDirectory
}

// MARK: - Cask Update

/// The internal authorization evidence behind one public cask Update preview. Never public, never
/// persisted.
struct HomebrewCaskUpdatePlan: Sendable {
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
    let targetVersion: String
    let pinned: Bool
    let autoUpdates: Bool?
    let disabled: Bool
    let deprecated: Bool
    let deprecationDisclosure: String?
    let hasPackageDependencies: Bool
    let outdatedRecord: HomebrewCaskOutdatedFacts?
    let artifacts: HomebrewCaskArtifactSet
    let managedTargets: [HomebrewCaskManagedTarget]
    let installedMetadata: HomebrewCaskInstalledMetadata
    let environment: ShellEnvironment
    let environmentFingerprint: String
    let currentDirectory: String
    let updateRunner: UpdateCommandRunner
    let root: NpmScratchRoot
    let arguments: [String]
    let preview: HomebrewCaskUpdatePreview
}

/// An opaque cask Update preparation. It has no public initializer and cannot be built from display
/// strings. It retains the owned operation root until cancelled or consumed by `execute`.
public final class HomebrewCaskUpdatePreparation: @unchecked Sendable {
    public let preview: HomebrewCaskUpdatePreview
    internal let plan: HomebrewCaskUpdatePlan

    private let lock = NSLock()
    private var claimed = false
    private var released = false

    internal init(preview: HomebrewCaskUpdatePreview, plan: HomebrewCaskUpdatePlan) {
        self.preview = preview
        self.plan = plan
    }

    internal func claim() -> HomebrewCaskUpdatePlan? {
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

/// The result of preparing one cask Update.
public enum HomebrewCaskUpdatePrepareResult: Sendable {
    case ready(HomebrewCaskUpdatePreparation)
    case unavailable(HomebrewCaskUpdateUnavailableReason)
}

/// The complete cask Update result. Output is in-memory only and separate per stream.
public struct HomebrewCaskUpdateOutcome: Equatable, Sendable {
    public let preview: HomebrewCaskUpdatePreview
    public let state: OperationState
    public let stdout: Data
    public let stderr: Data
    public let stdoutTruncated: Bool
    public let stderrTruncated: Bool
    public let exitStatus: Int32?
    /// True only when the operation process was actually launched.
    public let processStarted: Bool
    public let reconciliation: HomebrewCaskUpdateDelta?
    public let cleanupWarnings: [String]
    public let message: String?

    public var stdoutText: String { String(decoding: stdout, as: UTF8.self) }
    public var stderrText: String { String(decoding: stderr, as: UTF8.self) }
}

public enum HomebrewCaskUpdateOperation {

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
    ) async -> HomebrewCaskUpdatePrepareResult {
        // D-021 guard position: cancellation first, then accepted-operation containment, before any
        // observation, scratch claim or process.
        if Task.isCancelled { return .unavailable(.cancelled) }
        guard definition.acceptedOperations.contains(.homebrewCaskUpdate) else {
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
            mode: .update
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
        // Pinned `brew upgrade --cask` installs missing formula and cask dependencies through the
        // target cask. The preview can only promise the named cask and its listed artifacts, so a
        // fresh declaration of such a dependency refuses before any scratch claim or launch.
        guard !facts.hasPackageDependencies else {
            return .unavailable(.caskOperationUnsupported)
        }

        guard !facts.disabled else {
            return .unavailable(.caskDisabled(disableReason: facts.disableReason))
        }
        guard facts.autoUpdates != true else { return .unavailable(.caskAutoUpdates) }
        guard facts.version != "latest" else { return .unavailable(.caskTracksLatest) }
        if facts.outdatedRecord == nil {
            if facts.installedVersion == facts.version {
                return .unavailable(.notUpdateAvailable)
            }
            return .unavailable(.caskMetadataInconsistent)
        }

        guard let base = NpmScratchBase(url: scratchBase),
              let root = NpmScratchRoot.claim(base: base)
        else { return .unavailable(.operationRootUnsafe) }
        if Task.isCancelled {
            _ = releaseOperationRoot(root)
            return .unavailable(.cancelled)
        }

        let arguments = updateArguments(fullToken: facts.fullToken)
        let preview = HomebrewCaskUpdatePreview(
            registryID: definition.id,
            displayName: definition.displayName,
            kind: .cask,
            token: facts.token,
            fullToken: facts.fullToken,
            tap: facts.tap,
            selectedEntryPath: facts.selectedEntryPath,
            selectedTarget: facts.selectedTarget,
            installedVersion: facts.installedVersion,
            targetVersion: facts.version,
            targetResolution: homebrewCaskTargetResolutionDisclosure,
            pinned: facts.pinned,
            deprecated: facts.deprecated,
            deprecationDisclosure: facts.deprecationDisclosure,
            artifactTargets: facts.previewTargets,
            artifactScopeDisclosure: homebrewCaskArtifactScopeDisclosure,
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
            effect: homebrewCaskUpdateEffectText
        )
        let plan = HomebrewCaskUpdatePlan(
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
            targetVersion: facts.version,
            pinned: facts.pinned,
            autoUpdates: facts.autoUpdates,
            disabled: facts.disabled,
            deprecated: facts.deprecated,
            deprecationDisclosure: facts.deprecationDisclosure,
            hasPackageDependencies: facts.hasPackageDependencies,
            outdatedRecord: facts.outdatedRecord,
            artifacts: facts.artifacts,
            managedTargets: facts.managedTargets,
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
        return .ready(HomebrewCaskUpdatePreparation(preview: preview, plan: plan))
    }

    /// Cancels a pending preview and releases only its owned root.
    @discardableResult
    public static func cancel(_ preparation: HomebrewCaskUpdatePreparation) -> Bool {
        preparation.releaseUnconsumed()
    }

    /// Consumes a confirmed preparation and launches at most one literal `brew upgrade --cask`.
    public static func execute(
        confirmed preparation: HomebrewCaskUpdatePreparation,
        environment: ShellEnvironment,
        scan: @escaping @Sendable (DetectorDefinition, ShellEnvironment, String) -> ToolPathDiagnostic?,
        reconcileAfterLaunch: @escaping @Sendable (DetectorDefinition) async -> (ToolPathDiagnostic, ShellEnvironment)?,
        updateRunner: UpdateCommandRunner,
        operationRunner: OperationCommandRunner,
        gate: OperationExecutionGate,
        uptime: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
    ) async -> HomebrewCaskUpdateOutcome {
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
            reconciliation: HomebrewCaskUpdateDelta? = nil,
            cleanupWarnings: [String] = [],
            message: String? = nil
        ) async -> HomebrewCaskUpdateOutcome {
            var warnings = cleanupWarnings
            if !releaseOperationRoot(plan.root) {
                warnings.append("The owned operation scratch root could not be removed safely.")
            }
            await gate.release()
            return HomebrewCaskUpdateOutcome(
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
            mode: .update
        ) {
        case .unavailable(let failure):
            let state: OperationState = Task.isCancelled ? .cancelled : .failed
            let message: String
            switch failure {
            case .pinned:
                message = "The cask is now pinned; a new preview is required."
            case .cancelled:
                message = "The update was cancelled before launch."
            default:
                message = "Fresh confirmation failed: \(map(failure).message)"
            }
            return await finish(state: state, processStarted: false, message: message)
        case .success(let value):
            confirmed = value
        }

        guard !confirmed.hasPackageDependencies else {
            return await finish(
                state: .failed, processStarted: false,
                message: "The cask now declares formula or cask package dependencies; a new preview is required."
            )
        }
        // A changed manager-known target invalidates the preview by name (R5/F-8).
        guard confirmed.version == plan.targetVersion else {
            return await finish(
                state: .failed, processStarted: false,
                message: homebrewObservedTargetChangedMessage
            )
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
              confirmed.autoUpdates == plan.autoUpdates,
              confirmed.disabled == plan.disabled,
              confirmed.deprecated == plan.deprecated,
              confirmed.deprecationDisclosure == plan.deprecationDisclosure,
              confirmed.hasPackageDependencies == plan.hasPackageDependencies,
              confirmed.outdatedRecord == plan.outdatedRecord,
              confirmed.artifacts == plan.artifacts,
              confirmed.managedTargets == plan.managedTargets,
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
           plan.managedTargets.allSatisfy({
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
           plan.installedMetadata.managedTargets.allSatisfy({
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
                    ? "The update was cancelled before launch."
                    : "Confirmation revalidation exceeded its read-only budget."
            )
        }

        let operationEnvironment = HomebrewOperationEnvironment.mutationEnvironment(
            from: plan.environment, kind: .caskUpdate
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
        let reconciliation: HomebrewCaskUpdateDelta?
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
        return HomebrewCaskUpdateOutcome(
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

    /// Success is never inferred from exit zero: fresh ownership must still name the same full
    /// token under the same prefix, fresh metadata must report the observed target version as
    /// installed, and the fresh selection must sit in the matching staged version directory.
    private static func reconcilesAsSuccess(
        _ delta: HomebrewCaskUpdateDelta?,
        plan: HomebrewCaskUpdatePlan
    ) -> Bool {
        guard let delta, !delta.observationFailed else { return false }
        guard delta.versionMatchesTarget,
              delta.tokenMatches,
              delta.stagedMembershipConfirmed,
              delta.managedTargetsReleased,
              case .verified(let installation)? = delta.ownership
        else { return false }
        return installation.manager == .homebrewCask
            && installation.packageName == plan.fullToken
            && installation.managerRoot == plan.prefixRoot.canonicalPath
    }

    static func reconcile(
        plan: HomebrewCaskUpdatePlan,
        diagnostic after: ToolPathDiagnostic,
        environment: ShellEnvironment
    ) async -> (HomebrewCaskUpdateDelta?, [String]) {
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
        // The selected executable may legitimately be gone after a failed update; the root helper
        // revalidates the bound preparation selection, so a successful result requires both.
        var rootsMatch = false
        if let roots {
            rootsMatch = roots.prefix == plan.prefixRoot && roots.caskroom == plan.caskroomRoot
        }

        var afterInstalled: String?
        var afterToken: String?
        var afterFullToken: String?
        var afterTap: String?
        var infoFailed = false
        switch await HomebrewCaskObservation.query(
            manager: plan.manager,
            arguments: ["info", "--json=v2", "--cask", plan.fullToken],
            environment: environment,
            runner: plan.updateRunner
        ) {
        case .failure:
            infoFailed = true
        case .success(let data):
            guard let records = HomebrewCaskObservation.parseInfo(data),
                  records.count == 1,
                  let record = records.first,
                  case .string(let installed) = record.installed,
                  HomebrewCaskUpdateProbe.isStructurallyValidCask(
                    token: record.token, fullToken: record.fullToken, tap: record.tap
                  )
            else {
                infoFailed = true
                break
            }
            afterInstalled = installed
            afterToken = record.token
            afterFullToken = record.fullToken
            afterTap = record.tap
        }

        var afterStagedVersion: String?
        if let roots, let afterSelection, let afterInstalled,
           let staged = try? HomebrewCaskTargetParser.parse(
            selectedTarget: afterSelection.target,
            caskroom: roots.caskroom.canonicalPath
           ).get(),
           staged.token == plan.token,
           staged.versionDirectory == afterInstalled {
            afterStagedVersion = staged.versionDirectory
        }

        var newVersionDirectory: String?
        if rootsMatch, let roots, let afterInstalled,
           let binding = HomebrewCaskStagedBinding.observe(
               caskroom: roots.caskroom,
               token: plan.token,
               version: afterInstalled
           ),
           binding.isCurrent {
            newVersionDirectory = binding.versionDirectory.identity.canonicalPath
        }
        let managedTargets = plan.installedMetadata.managedTargets.map {
            observeUpdateManagedTargetRelease(
                $0,
                oldVersionDirectory: plan.versionDirectory.identity.canonicalPath,
                newVersionDirectory: newVersionDirectory
            )
        }

        // The last async manager read has completed. Re-check the recorded manager and both roots
        // before turning any of these observations into success facts.
        let managerCurrent = homebrewCaskManagerIsLive(plan.manager)
        let rootsCurrent = roots.map {
            $0.prefix.isCurrent && $0.caskroom.isCurrent
        } ?? false

        let versionMatchesTarget = afterInstalled == plan.targetVersion
            && afterStagedVersion == plan.targetVersion
        let tokenMatches = afterToken == plan.token
            && afterFullToken == plan.fullToken
            && afterTap == plan.tap
        let stagedMembership: Bool
        if rootsMatch, afterStagedVersion == plan.targetVersion,
           case .verified(let installation)? = ownership,
           installation.manager == .homebrewCask,
           installation.packageName == plan.fullToken,
           installation.managerRoot == plan.prefixRoot.canonicalPath,
           installation.managerEntryPath == plan.manager.entryPath,
           installation.managerTarget == plan.manager.canonicalTarget,
           installation.managerFingerprint == plan.manager.fingerprint {
            stagedMembership = true
        } else {
            stagedMembership = false
        }
        let observationFailed = infoFailed
            || roots == nil
            || !managerCurrent
            || !rootsCurrent
            || (afterInstalled != nil && newVersionDirectory == nil)
            || managedTargets.contains { $0.release == .observationFailed }
            || (afterSelection != nil && (afterInstalled == nil || afterStagedVersion == nil))
        let beforeSelection = homebrewCaskSelectionPair(plan.diagnostic)

        let delta = HomebrewCaskUpdateDelta(
            beforeInstalledVersion: plan.installedVersion,
            afterInstalledVersion: afterInstalled,
            observedTargetVersion: plan.targetVersion,
            versionMatchesTarget: versionMatchesTarget,
            tokenMatches: tokenMatches,
            afterToken: afterToken,
            afterFullToken: afterFullToken,
            afterTap: afterTap,
            stagedMembershipConfirmed: stagedMembership,
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
            managedTargets: managedTargets,
            observationFailed: observationFailed
        )
        return (delta, ownershipWarning.map { [$0] } ?? [])
    }

    /// A previously installed target is clean only when it is gone, was retargeted to a verified
    /// source under the new staged version, or (for a path that was absent at preview) stayed
    /// absent. A still-present old link, wrong-type object or unreadable path is never success.
    private static func observeUpdateManagedTargetRelease(
        _ managed: HomebrewCaskManagedTarget,
        oldVersionDirectory: String,
        newVersionDirectory: String?
    ) -> HomebrewCaskManagedTargetDelta {
        let result: HomebrewCaskManagedTargetRelease
        var info = Darwin.stat()
        let status = managed.artifact.target.withCString { Darwin.lstat($0, &info) }
        if status != 0 {
            let code = errno
            if code == ENOENT || code == ENOTDIR {
                result = managed.presence == .absent ? .absentAtPreview : .released
            } else {
                result = .observationFailed
            }
        } else if (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFLNK) {
            if let observed = FileIdentityObserver.observeExecutable(
                entryPath: managed.artifact.target
            ) {
                let observedTarget = observed.canonicalTarget
                if homebrewCaskPathsEqual(observedTarget, managed.sourcePath) {
                    result = .stillPresent
                } else if let newVersionDirectory,
                          updateTargetMovedToNewSource(
                              managed,
                              observedTarget: observedTarget,
                              oldVersionDirectory: oldVersionDirectory,
                              newVersionDirectory: newVersionDirectory
                          ) {
                    result = .retargeted
                } else if let newVersionDirectory,
                          FileIdentityObserver.isStrictDescendant(
                              observedTarget, of: newVersionDirectory
                          ) {
                    // A different live file under this cask's verified new stage is neither
                    // this artifact's retarget nor an unrelated external successor.
                    result = .observationFailed
                } else {
                    result = managed.presence == .absent
                        ? .occupiedAfterAbsentPreview : .successor
                }
            } else if let destination = homebrewCaskReadLink(managed.artifact.target) {
                if homebrewCaskPathsEqual(destination, managed.sourcePath) {
                    result = .stillPresent
                } else if managed.presence == .absent {
                    // A path absent at preview imposes no after-fact only while it is still
                    // absent; every later occupancy, including a dangling link, is unexplained.
                    result = .occupiedAfterAbsentPreview
                } else if let newVersionDirectory,
                          FileIdentityObserver.isStrictDescendant(
                              destination, of: newVersionDirectory
                          ) {
                    // A dangling link into the new version is not a verified live source.
                    result = .observationFailed
                } else {
                    result = .successor
                }
            } else {
                result = .observationFailed
            }
        } else if managed.presence == .absent {
            result = .occupiedAfterAbsentPreview
        } else {
            result = .observationFailed
        }
        return HomebrewCaskManagedTargetDelta(
            kind: managed.artifact.kind,
            target: managed.artifact.target,
            release: result
        )
    }

    /// The target links to this artifact's own stage under the verified new version, not merely to
    /// some other regular file in that directory.
    private static func updateTargetMovedToNewSource(
        _ managed: HomebrewCaskManagedTarget,
        observedTarget: String,
        oldVersionDirectory: String,
        newVersionDirectory: String
    ) -> Bool {
        let relativeComponents: [String]
        switch managed.artifact.kind {
        case .binary where !managed.artifact.source.hasPrefix("/"):
            guard homebrewCaskIsCleanRelativePath(managed.artifact.source) else {
                return false
            }
            relativeComponents = HomebrewCaskTargetParser.components(
                of: managed.artifact.source
            )
        case .commandWrapper:
            guard homebrewCaskIsCleanRelativeComponent(managed.artifact.source) else {
                return false
            }
            relativeComponents = [
                ".homebrew-command-wrappers", managed.artifact.source,
            ]
        case .binary:
            // The absolute source was proven a strict descendant of the old exact stage at
            // preview. Its exact relative components, not any regular file under the new stage,
            // must correspond under the new stage.
            let oldComponents = HomebrewCaskTargetParser.components(
                of: oldVersionDirectory
            )
            let sourceComponents = HomebrewCaskTargetParser.components(
                of: managed.sourcePath
            )
            guard sourceComponents.count > oldComponents.count,
                  Array(sourceComponents.prefix(oldComponents.count)) == oldComponents
            else { return false }
            relativeComponents = Array(sourceComponents.dropFirst(oldComponents.count))
        }
        guard !relativeComponents.isEmpty,
              FileIdentityObserver.isStrictDescendant(
                  observedTarget, of: newVersionDirectory
              ),
              homebrewCaskIsRegularFile(observedTarget)
        else { return false }
        let expectedTarget = ([newVersionDirectory] + relativeComponents)
            .joined(separator: "/")
        return homebrewCaskPathsEqual(observedTarget, expectedTarget)
    }

    // MARK: - Preview/argv helpers

    /// The only dynamic argv element is the manager-returned full token. The verb and both flags
    /// are literals, so `--force`, `--zap`, `--ignore-dependencies`, `--all`, `--dry-run`,
    /// `--greedy*`, `--formula`, a different verb and a second target are impossible.
    static func updateArguments(fullToken: String) -> [String] {
        ["upgrade", "--cask", "--yes", fullToken]
    }

    private static func map(
        _ failure: HomebrewCaskObservationFailure
    ) -> HomebrewCaskUpdateUnavailableReason {
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
        preview: HomebrewCaskUpdatePreview,
        state: OperationState,
        message: String,
        cleanupOK: Bool
    ) -> HomebrewCaskUpdateOutcome {
        HomebrewCaskUpdateOutcome(
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
