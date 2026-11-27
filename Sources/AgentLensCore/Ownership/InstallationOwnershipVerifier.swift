// InstallationOwnershipVerifier — explicit, read-only ownership verification (M9-B).
//
// The diagnostic selection is the only starting point. The heuristic detected source chooses a
// manager adapter, but never proves ownership. Ineligible or unsupported selections return a
// neutral result before any process is constructed. Each adapter re-observes the selected
// executable, the manager and its proof files around every query and before returning.

import Foundation

public enum InstallationOwnershipVerifier {

    public static func verify(
        definition: DetectorDefinition,
        diagnostic: ToolPathDiagnostic,
        environment: ShellEnvironment,
        runner: UpdateCommandRunner,
        currentDirectory: String,
        now: @Sendable () -> Date
    ) async -> InstallationOwnershipResult {
        let selectedCandidate: PathCandidateObservation
        switch diagnostic.selection {
        case .winner(let candidate), .offPath(let candidate, _):
            selectedCandidate = candidate
        case .notInstalled:
            return result(
                definition: definition,
                selection: nil,
                outcome: .unknown(.notInstalled),
                now: now
            )
        case .inconsistent:
            return result(
                definition: definition,
                selection: nil,
                outcome: .unknown(.inconsistentSelection),
                now: now
            )
        }

        guard let selected = FileIdentityObserver.observeExecutable(
            entryPath: selectedCandidate.entryPath
        ), let reportedTarget = selectedCandidate.canonicalTarget,
        selected.canonicalTarget == reportedTarget
        else {
            return result(
                definition: definition,
                selection: nil,
                outcome: .unknown(.selectionUnavailable),
                now: now
            )
        }
        guard !Task.isCancelled else {
            return result(
                definition: definition,
                selection: selected,
                outcome: .unknown(.cancelled),
                now: now
            )
        }

        let source = diagnostic.detectedTool.source
        let hasNpm = definition.packages.contains { $0.manager == .npm }
        let hasFormula = definition.packages.contains { $0.manager == .homebrewFormula }
        let hasCask = definition.packages.contains { $0.manager == .homebrewCask }
        let hasUvTool = definition.packages.contains { $0.manager == .uvTool }
        let hasPip = definition.packages.contains { $0.manager == .pip }
        let outcome: InstallationOwnershipOutcome
        // Routing order (R1): npm only for an npm source with an npm declaration; the formula
        // proof only for a brew source with a formula declaration; otherwise a declared cask is
        // proved by the cask route regardless of the heuristic source. A cask declaration never
        // falls through to a previous branch's failure, and a cask proof never borrows a formula
        // result.
        if source == "npm", hasNpm {
            outcome = await verifyNpm(
                definition: definition,
                selection: selected,
                environment: environment,
                runner: runner,
                currentDirectory: currentDirectory
            )
        } else if source == "brew", hasFormula {
            outcome = await verifyHomebrew(
                definition: definition,
                selection: selected,
                environment: environment,
                runner: runner,
                currentDirectory: currentDirectory
            )
        } else if hasCask {
            let cask = await verifyHomebrewCask(
                definition: definition,
                selection: selected,
                environment: environment,
                runner: runner,
                currentDirectory: currentDirectory
            )
            // Only the two "not this cask layout" refusals may fall through to a declared Python
            // manager. Every other cask answer remains the cask answer.
            if case .unknown(let reason) = cask,
               (reason == .managerRootMismatch || reason == .unsupportedInstallationLayout),
               hasUvTool || hasPip {
                outcome = await verifyPython(
                    definition: definition,
                    selection: selected,
                    environment: environment,
                    runner: runner,
                    currentDirectory: currentDirectory,
                    hasUvTool: hasUvTool,
                    hasPip: hasPip
                )
            } else {
                outcome = cask
            }
        } else if source == "npm" {
            // Preserves the existing no-declaration refusal for npm sources.
            outcome = await verifyNpm(
                definition: definition,
                selection: selected,
                environment: environment,
                runner: runner,
                currentDirectory: currentDirectory
            )
        } else if source == "brew" {
            // A brew source without a formula declaration follows the otherwise branch: a
            // declared Python manager is classified locally; a Homebrew framework symlink layout
            // is not promoted to pip ownership (R1.3).
            if hasUvTool || hasPip {
                outcome = await verifyPython(
                    definition: definition,
                    selection: selected,
                    environment: environment,
                    runner: runner,
                    currentDirectory: currentDirectory,
                    hasUvTool: hasUvTool,
                    hasPip: hasPip
                )
            } else {
                outcome = await verifyHomebrew(
                    definition: definition,
                    selection: selected,
                    environment: environment,
                    runner: runner,
                    currentDirectory: currentDirectory
                )
            }
        } else if hasUvTool || hasPip {
            outcome = await verifyPython(
                definition: definition,
                selection: selected,
                environment: environment,
                runner: runner,
                currentDirectory: currentDirectory,
                hasUvTool: hasUvTool,
                hasPip: hasPip
            )
        } else {
            outcome = .unknown(.unsupportedSource)
        }

        guard !Task.isCancelled else {
            return result(
                definition: definition,
                selection: selected,
                outcome: .unknown(.cancelled),
                now: now
            )
        }

        if case .verified = outcome {
            guard let currentSelection = FileIdentityObserver.observeExecutable(
                entryPath: selected.entryPath
            ), currentSelection == selected else {
                return result(
                    definition: definition,
                    selection: selected,
                    outcome: .unknown(.selectedExecutableChanged),
                    now: now
                )
            }
        }

        return result(
            definition: definition,
            selection: selected,
            outcome: outcome,
            now: now
        )
    }

    /// Route a declared Python candidate only after a local receipt/root classifier. A uv receipt
    /// of any type reserves the selection for uv; a known uv tool root does the same even when the
    /// receipt is absent. Pip proof never requires uv to exist.
    private static func verifyPython(
        definition: DetectorDefinition,
        selection: ObservedExecutable,
        environment: ShellEnvironment,
        runner: UpdateCommandRunner,
        currentDirectory: String,
        hasUvTool: Bool,
        hasPip: Bool
    ) async -> InstallationOwnershipOutcome {
        let target = URL(fileURLWithPath: selection.canonicalTarget)
            .standardizedFileURL.path
        let envRoot = URL(fileURLWithPath: target, isDirectory: false)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .standardizedFileURL.path
        guard envRoot.hasPrefix("/"),
              FileIdentityObserver.isExactDescendant(
                target,
                of: envRoot,
                components: ["bin", definition.executableName]
              )
        else { return .unknown(.unsupportedInstallationLayout) }

        let receiptPath = envRoot + "/uv-receipt.toml"
        let receiptNode = PythonProofSupport.lexicalNode(receiptPath)
        if receiptNode == .error { return .unknown(.manifestUnreadable) }
        let receiptExists = receiptNode == .present
        if receiptExists {
            guard hasUvTool else { return .unknown(.noMatchingPackage) }
            guard let manager = UvToolOwnershipProbe.resolveManager(
                environment: environment,
                currentDirectory: currentDirectory
            ) else { return .unknown(.managerUnavailable) }
            return await UvToolOwnershipProbe.verify(
                definition: definition,
                selection: selection,
                manager: manager,
                environment: environment,
                runner: runner
            )
        }

        // A declared Python manager without any local Python layout evidence is an unrelated
        // standalone executable; do not spawn uv just to ask about its roots.
        guard let envRootIdentity = PythonProofSupport.observePlainDirectory(envRoot),
              PythonProofSupport.hasPythonLayoutEvidence(envRootIdentity) else {
            if hasPip {
                return PipOwnershipProbe.verify(
                    definition: definition,
                    selection: selection,
                    environment: environment
                )
            }
            return .unknown(.unsupportedInstallationLayout)
        }

        // A known uv root reserves the selection even when only pip is declared. The root query
        // is used only after positive local Python layout evidence.
        if hasPip,
           let manager = UvToolOwnershipProbe.resolveManager(
                environment: environment,
                currentDirectory: currentDirectory
           ) {
            switch await UvToolOwnershipProbe.resolveRoots(
                manager: manager,
                selection: selection,
                environment: environment,
                runner: runner
            ) {
            case .failure(.cancelled):
                return .unknown(.cancelled)
            case .failure:
                break // Unavailable root evidence does not recategorize the environment.
            case .success(let roots):
                if UvToolOwnershipProbe.selectionIsInsideToolRoot(selection: selection, roots: roots) {
                    return .unknown(.manifestMissing)
                }
            }
        }

        if hasPip {
            return PipOwnershipProbe.verify(
                definition: definition,
                selection: selection,
                environment: environment
            )
        }
        guard hasUvTool,
              let manager = UvToolOwnershipProbe.resolveManager(
                environment: environment,
                currentDirectory: currentDirectory
              )
        else { return .unknown(.managerUnavailable) }
        return await UvToolOwnershipProbe.verify(
            definition: definition,
            selection: selection,
            manager: manager,
            environment: environment,
            runner: runner
        )
    }

    private static func verifyNpm(
        definition: DetectorDefinition,
        selection: ObservedExecutable,
        environment: ShellEnvironment,
        runner: UpdateCommandRunner,
        currentDirectory: String
    ) async -> InstallationOwnershipOutcome {
        guard definition.packages.contains(where: { $0.manager == .npm }) else {
            return .unknown(.noDeclaredPackage)
        }
        guard let manager = resolveNpm(
            environment: environment,
            currentDirectory: currentDirectory
        ) else {
            return .unknown(.managerUnavailable)
        }
        return await NpmOwnershipProbe.verify(
            definition: definition,
            selection: selection,
            manager: manager,
            environment: environment,
            runner: runner
        )
    }

    private static func verifyHomebrew(
        definition: DetectorDefinition,
        selection: ObservedExecutable,
        environment: ShellEnvironment,
        runner: UpdateCommandRunner,
        currentDirectory: String
    ) async -> InstallationOwnershipOutcome {
        let hasFormula = definition.packages.contains { $0.manager == .homebrewFormula }
        if !hasFormula {
            let hasCask = definition.packages.contains { $0.manager == .homebrewCask }
            return .unknown(hasCask ? .unsupportedCask : .noDeclaredPackage)
        }
        guard let manager = resolveBrew(
            environment: environment,
            currentDirectory: currentDirectory
        ) else {
            return .unknown(.managerUnavailable)
        }
        return await HomebrewOwnershipProbe.verify(
            definition: definition,
            selection: selection,
            manager: manager,
            environment: environment,
            runner: runner
        )
    }

    private static func verifyHomebrewCask(
        definition: DetectorDefinition,
        selection: ObservedExecutable,
        environment: ShellEnvironment,
        runner: UpdateCommandRunner,
        currentDirectory: String
    ) async -> InstallationOwnershipOutcome {
        switch HomebrewCaskOwnershipProbe.declaredCaskPreflight(definition: definition) {
        case .refused(let reason):
            return .unknown(reason)
        case .names:
            break
        }
        guard let manager = resolveBrew(
            environment: environment,
            currentDirectory: currentDirectory
        ) else {
            return .unknown(.managerUnavailable)
        }
        return await HomebrewCaskOwnershipProbe.verify(
            definition: definition,
            selection: selection,
            manager: manager,
            environment: environment,
            runner: runner
        )
    }

    private static func resolveNpm(
        environment: ShellEnvironment,
        currentDirectory: String
    ) -> ObservedExecutable? {
        let workingDirectory = URL(
            fileURLWithPath: currentDirectory,
            isDirectory: true
        ).standardizedFileURL
        for directoryText in environment.pathEntries {
            let directory = directoryText.isEmpty
                ? workingDirectory
                : URL(
                    fileURLWithPath: directoryText,
                    isDirectory: true,
                    relativeTo: workingDirectory
                ).standardizedFileURL
            let entry = directory.appendingPathComponent("npm").standardizedFileURL.path
            if let observed = FileIdentityObserver.observeExecutable(entryPath: entry) {
                return observed
            }
        }
        return nil
    }

    private static func resolveBrew(
        environment: ShellEnvironment,
        currentDirectory: String
    ) -> ObservedExecutable? {
        guard let manager = HomebrewManagerResolver.resolve(
            environment: environment,
            currentDirectory: currentDirectory
        ) else { return nil }
        guard let observed = FileIdentityObserver.observeExecutable(
            entryPath: manager.entryPath
        ), observed.canonicalTarget == manager.canonicalTarget
        else { return nil }
        return observed
    }

    private static func result(
        definition: DetectorDefinition,
        selection: ObservedExecutable?,
        outcome: InstallationOwnershipOutcome,
        now: @Sendable () -> Date
    ) -> InstallationOwnershipResult {
        InstallationOwnershipResult(
            registryID: definition.id,
            observedSelectedEntry: selection?.entryPath,
            observedSelectedTarget: selection?.canonicalTarget,
            observedAt: now(),
            outcome: outcome
        )
    }
}
