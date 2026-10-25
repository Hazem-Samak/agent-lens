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
        let outcome: InstallationOwnershipOutcome
        switch source {
        case "npm":
            outcome = await verifyNpm(
                definition: definition,
                selection: selected,
                environment: environment,
                runner: runner,
                currentDirectory: currentDirectory
            )
        case "brew":
            outcome = await verifyHomebrew(
                definition: definition,
                selection: selected,
                environment: environment,
                runner: runner,
                currentDirectory: currentDirectory
            )
        default:
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
