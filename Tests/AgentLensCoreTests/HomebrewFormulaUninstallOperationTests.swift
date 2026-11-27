import Foundation
import Testing
@testable import AgentLensCore

// M13-D formula Uninstall: lifecycle, literal argv, exact environment policy, refusal ordering,
// pin policy, honest dependent refusal, multi-keg residue and removal reconciliation. Every test
// uses the disposable synthetic Cellar in HomebrewFormulaOperationTestSupport.swift; no real brew
// executable or personal manager state is touched.

private func preparedUninstall(
    fixture: HomebrewFormulaFixture,
    definition: DetectorDefinition,
    diagnostic: ToolPathDiagnostic,
    runner: UpdateCommandRunner
) async throws -> HomebrewFormulaUninstallPreparation {
    switch await HomebrewFormulaUninstallOperation.prepare(
        definition: definition,
        diagnostic: diagnostic,
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: runner,
        operationRootBaseURL: fixture.root
    ) {
    case .ready(let preparation):
        return preparation
    case .unavailable(let reason):
        throw NSError(
            domain: "HomebrewFormulaUninstallOperationTests", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "unexpected refusal: \(reason)"]
        )
    }
}

private func expectRefusedUninstall(
    _ outcome: HomebrewFormulaUninstallOutcome,
    runner: HomebrewScriptedMutationRunner,
    messageContains: String? = nil
) {
    #expect(outcome.state == .failed)
    #expect(!outcome.processStarted)
    #expect(outcome.reconciliation == nil)
    #expect(runner.invocations.isEmpty)
    if let messageContains {
        #expect(outcome.message?.contains(messageContains) == true)
    }
}

@Test func uninstallPreviewBindsIdentityResidueAndDependentRefusal() async throws {
    let fixture = try HomebrewFormulaFixture(
        "uninstall-preview", kegs: ["0.9.0", "1.0.0"], selectedKeg: "1.0.0",
        hostileEnvironment: true
    )
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUninstall])
    let runner = HomebrewFormulaCommandRunner(fixture: fixture)
    let preparation = try await preparedUninstall(
        fixture: fixture, definition: definition, diagnostic: fixture.diagnostic(keg: "1.0.0"),
        runner: runner
    )
    let preview = preparation.preview
    #expect(preview.kind == .formula)
    #expect(preview.formulaName == "m13tool")
    #expect(preview.fullName == "m13tool")
    #expect(preview.selectedEntryPath == fixture.entry.path)
    #expect(preview.selectedTarget == fixture.expectedTarget("1.0.0"))
    #expect(preview.selectedKegVersion == "1.0.0")
    #expect(preview.installedKegs == ["0.9.0", "1.0.0"])
    #expect(preview.prefix == fixture.prefix.path)
    #expect(preview.cellar == fixture.cellar.path)
    #expect(preview.managerPath == fixture.brew.path)
    #expect(preview.arguments == ["uninstall", "--formula", "m13tool"])
    #expect(!preview.arguments.contains("--yes"))
    #expect(preview.timeoutSeconds == 900)
    #expect(preview.remainingKegDisclosure == homebrewFormulaRemainingKegDisclosure)
    #expect(preview.dependentRefusalDisclosure == homebrewFormulaDependentRefusalDisclosure)
    #expect(preview.effect == homebrewFormulaUninstallEffectText)
    for phrase in [
        "uninstall only the named formula's currently linked keg",
        "no other formula or cask is targeted",
        "Homebrew refuses and Agent Lens surfaces that refusal",
        "without using --ignore-dependencies",
        "Older kegs of this formula are not removed",
        "remain installed but unlinked",
        "reports them as residue",
        "automatic cleanup is disabled",
        "automatic removal of no-longer-needed dependencies is disabled",
        "metadata auto-update is disabled",
        "analytics are disabled",
        "download cache, logs, and temporary files",
        "does not redirect, inspect, or delete them",
        "bounded to 900 seconds",
    ] {
        #expect(preview.effect.contains(phrase), "effect text is missing: \(phrase)")
    }
    expectNoForbiddenMutationTokens(preview.arguments)
    #expect(HomebrewFormulaUninstallOperation.cancel(preparation))
}

@Test func multiKegUninstallSucceedsAndReportsRemainingResidueHonestly() async throws {
    let fixture = try HomebrewFormulaFixture(
        "uninstall-residue", kegs: ["0.9.0", "1.0.0"], selectedKeg: "1.0.0"
    )
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUninstall])
    let updateRunner = HomebrewFormulaCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner(
        result: OperationCommandResult(
            stdout: Data("Uninstalling /Cellar/m13tool/1.0.0... (1,234 files)\n".utf8),
            stderr: Data(), stdoutTruncated: false, stderrTruncated: false,
            exitStatus: 0, processStarted: true,
            timedOut: false, cancelled: false, cleanupWarning: false
        ),
        onLaunch: {
            try? fixture.removeEntry()
            try? fixture.removeKeg("1.0.0")
            fixture.state.kegs = ["0.9.0"]
            fixture.state.selectedKeg = nil
        }
    )
    let before = fixture.diagnostic(keg: "1.0.0")
    let preparation = try await preparedUninstall(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    let outcome = await HomebrewFormulaUninstallOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (fixture.notInstalledDiagnostic(), fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    #expect(outcome.state == .succeeded)
    #expect(outcome.processStarted)
    #expect(outcome.exitStatus == 0)
    #expect(outcome.stdoutText.contains("Uninstalling"))
    #expect(outcome.message == nil)
    #expect(!FileManager.default.fileExists(atPath: preparation.preview.workingDirectory))
    let delta = try #require(outcome.reconciliation)
    #expect(delta.beforeSelectedKegVersion == "1.0.0")
    #expect(delta.afterSelectedKegVersion == nil)
    #expect(delta.beforeInstalledKegs == ["0.9.0", "1.0.0"])
    #expect(delta.afterInstalledKegs == ["0.9.0"])
    #expect(delta.recordedKegAbsent)
    #expect(!delta.recordedKegReplaced)
    #expect(delta.selectedTargetReleased)
    #expect(!delta.selectedEntryResidue)
    #expect(!delta.observationFailed)
    #expect(delta.remainingKegs == ["0.9.0"])
    #expect(delta.formulaStillInstalledViaRemainingKeg == true)
    #expect(delta.ownership == .unknown(.notInstalled))
    #expect(delta.changed)

    #expect(mutationRunner.invocations.count == 1)
    let mutation = try #require(mutationRunner.invocations.first)
    #expect(mutation.executablePath == fixture.brew.path)
    #expect(mutation.arguments == ["uninstall", "--formula", "m13tool"])
    #expect(mutation.currentDirectory == preparation.preview.workingDirectory)
    #expect(mutation.timeout == 900)
    expectNoForbiddenMutationTokens(mutation.arguments)
    #expect(mutation.environment["HOMEBREW_NO_AUTO_UPDATE"] == "1")
    #expect(mutation.environment["HOMEBREW_NO_ANALYTICS"] == "1")
    #expect(mutation.environment["HOMEBREW_NO_INSTALL_CLEANUP"] == "1")
    #expect(mutation.environment["HOMEBREW_NO_AUTOREMOVE"] == "1")
    #expect(mutation.environment["HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK"] == nil)
    #expect(mutation.environment["HOMEBREW_NO_ASK"] == nil)
    #expect(mutation.environment["HOMEBREW_LOGS"] == nil)
    #expect(mutation.environment["HOMEBREW_TEMP"] == nil)
    for key in HomebrewOperationEnvironment.removedKeys {
        #expect(mutation.environment[key] == nil)
    }
}

@Test func singleKegUninstallReportsNoRemainingResidue() async throws {
    let fixture = try HomebrewFormulaFixture("uninstall-single", kegs: ["1.0.0"])
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUninstall])
    let updateRunner = HomebrewFormulaCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner(onLaunch: {
        try? fixture.removeEntry()
        try? fixture.removeKeg("1.0.0")
        fixture.state.kegs = []
        fixture.state.selectedKeg = nil
    })
    let before = fixture.diagnostic(keg: "1.0.0")
    let preparation = try await preparedUninstall(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    let outcome = await HomebrewFormulaUninstallOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (fixture.notInstalledDiagnostic(), fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    #expect(outcome.state == .succeeded)
    let delta = try #require(outcome.reconciliation)
    #expect(delta.recordedKegAbsent)
    #expect(delta.remainingKegs == [])
    #expect(delta.formulaStillInstalledViaRemainingKeg == false)
}

@Test func uninstallIsNotRefusedForDeprecatedDisabledOrUnsupportedTarget() async throws {
    let fixture = try HomebrewFormulaFixture(
        "uninstall-not-refused", stable: "latest", deprecated: true, disabled: true
    )
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    fixture.state.disableReason = "obsolete"
    fixture.state.deprecationReason = "renamed upstream"
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUninstall])
    let runner = HomebrewFormulaCommandRunner(fixture: fixture)
    let preparation = try await preparedUninstall(
        fixture: fixture, definition: definition, diagnostic: fixture.diagnostic(keg: "1.0.0"),
        runner: runner
    )
    #expect(preparation.preview.selectedKegVersion == "1.0.0")
    #expect(preparation.preview.installedKegs == ["1.0.0"])
    #expect(HomebrewFormulaUninstallOperation.cancel(preparation))
}

@Test func pinnedUninstallRefusesBeforeScratchOrLaunch() async throws {
    let fixture = try HomebrewFormulaFixture("uninstall-pinned", pinned: true)
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUninstall])
    let runner = HomebrewFormulaCommandRunner(fixture: fixture)
    let operationBase = fixture.root.appendingPathComponent("operation-base", isDirectory: true)
    try FileManager.default.createDirectory(at: operationBase, withIntermediateDirectories: true)
    let refused = await HomebrewFormulaUninstallOperation.prepare(
        definition: definition,
        diagnostic: fixture.diagnostic(keg: "1.0.0"),
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: runner,
        operationRootBaseURL: operationBase
    )
    guard case .unavailable(let reason) = refused else {
        Issue.record("a pinned formula must refuse Uninstall")
        return
    }
    #expect(reason == .pinned)
    #expect(try homebrewScratchIsEmpty(operationBase))
    #expect(!runner.invocations.contains {
        $0.arguments.first == "uninstall" || $0.arguments.first == "unpin"
    })
}

@Test func pinAppearingAfterTheUninstallPreviewRefusesBeforeLaunch() async throws {
    let fixture = try HomebrewFormulaFixture("uninstall-pin-late")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUninstall])
    let updateRunner = HomebrewFormulaCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner()
    let before = fixture.diagnostic(keg: "1.0.0")
    let preparation = try await preparedUninstall(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    fixture.state.pinned = true
    let outcome = await HomebrewFormulaUninstallOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (before, fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    expectRefusedUninstall(outcome, runner: mutationRunner, messageContains: "now pinned")
}

@Test func unacceptedUninstallRefusesBeforeObservationScratchOrProcess() async throws {
    let fixture = try HomebrewFormulaFixture("uninstall-unaccepted")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [])
    let runner = HomebrewCountingCommandRunner()
    let operationBase = fixture.root.appendingPathComponent("operation-base", isDirectory: true)
    try FileManager.default.createDirectory(at: operationBase, withIntermediateDirectories: true)
    let refused = await HomebrewFormulaUninstallOperation.prepare(
        definition: definition,
        diagnostic: fixture.diagnostic(keg: "1.0.0"),
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: runner,
        operationRootBaseURL: operationBase
    )
    guard case .unavailable(let reason) = refused else {
        Issue.record("unaccepted Uninstall must refuse preparation")
        return
    }
    #expect(reason == .operationNotAccepted)
    #expect(reason.message.contains("not yet accepted"))
    #expect(runner.invocations == 0)
    #expect(try homebrewScratchIsEmpty(operationBase))
}

@Test func cancellingAnUninstallPreparationReleasesItsRootAndLaunchesNothing() async throws {
    let fixture = try HomebrewFormulaFixture("uninstall-cancel")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUninstall])
    let updateRunner = HomebrewFormulaCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner()
    let before = fixture.diagnostic(keg: "1.0.0")
    let preparation = try await preparedUninstall(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    let root = preparation.preview.workingDirectory
    #expect(FileManager.default.fileExists(atPath: root))
    #expect(HomebrewFormulaUninstallOperation.cancel(preparation))
    #expect(!FileManager.default.fileExists(atPath: root))
    let outcome = await HomebrewFormulaUninstallOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (before, fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    #expect(outcome.state == .failed)
    #expect(!outcome.processStarted)
    #expect(mutationRunner.invocations.isEmpty)
}

@Test func uninstallGateContentionRefusesWithoutLaunch() async throws {
    let fixture = try HomebrewFormulaFixture("uninstall-gate")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUninstall])
    let updateRunner = HomebrewFormulaCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner()
    let before = fixture.diagnostic(keg: "1.0.0")
    let preparation = try await preparedUninstall(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    let gate = OperationExecutionGate()
    #expect(await gate.acquire())
    let outcome = await HomebrewFormulaUninstallOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (before, fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: gate
    )
    await gate.release()
    #expect(outcome.state == .cancelled)
    #expect(!outcome.processStarted)
    #expect(mutationRunner.invocations.isEmpty)
}

@Test func dependentFormulaRefusalIsAnHonestFailureWithoutABypass() async throws {
    let fixture = try HomebrewFormulaFixture("uninstall-dependent")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUninstall])
    let updateRunner = HomebrewFormulaCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner(
        result: OperationCommandResult(
            stdout: Data(), stderr: Data(
                "Error: Refusing to uninstall /Cellar/m13tool/1.0.0\nbecause it is required by m13consumer, which is currently installed.\n".utf8
            ),
            stdoutTruncated: false, stderrTruncated: false,
            exitStatus: 1, processStarted: true,
            timedOut: false, cancelled: false, cleanupWarning: false
        )
    )
    let before = fixture.diagnostic(keg: "1.0.0")
    let preparation = try await preparedUninstall(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    let outcome = await HomebrewFormulaUninstallOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (before, fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    #expect(outcome.state == .failed)
    #expect(outcome.processStarted)
    #expect(outcome.exitStatus == 1)
    #expect(outcome.stderrText.contains("Refusing to uninstall"))
    #expect(outcome.stderrText.contains("required by m13consumer"))
    let delta = try #require(outcome.reconciliation)
    #expect(!delta.recordedKegAbsent)
    #expect(!delta.selectedTargetReleased)
    #expect(delta.remainingKegs == ["1.0.0"])
    #expect(mutationRunner.invocations.count == 1)
    let mutation = try #require(mutationRunner.invocations.first)
    #expect(!mutation.arguments.contains("--ignore-dependencies"))
    expectNoForbiddenMutationTokens(mutation.arguments)
}

@Test func exitZeroWithoutRemovalIsUncertain() async throws {
    let fixture = try HomebrewFormulaFixture("uninstall-no-removal")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUninstall])
    let updateRunner = HomebrewFormulaCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner(
        result: OperationCommandResult(
            stdout: Data("Skipping\n".utf8), stderr: Data(),
            stdoutTruncated: false, stderrTruncated: false,
            exitStatus: 0, processStarted: true,
            timedOut: false, cancelled: false, cleanupWarning: false
        )
    )
    let before = fixture.diagnostic(keg: "1.0.0")
    let preparation = try await preparedUninstall(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    let outcome = await HomebrewFormulaUninstallOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (before, fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    #expect(outcome.state == .uncertain)
    #expect(outcome.processStarted)
    #expect(outcome.exitStatus == 0)
    let delta = try #require(outcome.reconciliation)
    #expect(!delta.recordedKegAbsent)
    #expect(!delta.selectedTargetReleased)
}

@Test func replacedKegAtTheRecordedPathIsNotReportedAsAbsence() async throws {
    let fixture = try HomebrewFormulaFixture("uninstall-replaced-keg")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUninstall])
    let updateRunner = HomebrewFormulaCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner(onLaunch: {
        try? fixture.removeEntry()
        try? fixture.removeKeg("1.0.0")
        try? fixture.createKeg("1.0.0")
        fixture.state.kegs = []
        fixture.state.selectedKeg = nil
    })
    let before = fixture.diagnostic(keg: "1.0.0")
    let preparation = try await preparedUninstall(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    let outcome = await HomebrewFormulaUninstallOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (fixture.notInstalledDiagnostic(), fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    #expect(outcome.state == .uncertain)
    #expect(outcome.processStarted)
    #expect(outcome.exitStatus == 0)
    let delta = try #require(outcome.reconciliation)
    #expect(!delta.recordedKegAbsent)
    #expect(delta.recordedKegReplaced)
    #expect(delta.selectedTargetReleased)
}

@Test func uninstallLeavesDanglingEntryResidueDisclosed() async throws {
    let fixture = try HomebrewFormulaFixture("uninstall-dangling")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUninstall])
    let updateRunner = HomebrewFormulaCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner(onLaunch: {
        try? fixture.removeKeg("1.0.0")
        fixture.state.kegs = []
        fixture.state.selectedKeg = nil
    })
    let before = fixture.diagnostic(keg: "1.0.0")
    let preparation = try await preparedUninstall(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    let outcome = await HomebrewFormulaUninstallOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (fixture.notInstalledDiagnostic(), fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    #expect(outcome.state == .succeeded)
    let delta = try #require(outcome.reconciliation)
    #expect(delta.recordedKegAbsent)
    #expect(delta.selectedTargetReleased)
    #expect(delta.selectedEntryResidue)
}

@Test func staleUninstallInstalledKegListRefusesBeforeLaunch() async throws {
    let fixture = try HomebrewFormulaFixture("uninstall-stale-kegs")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUninstall])
    let updateRunner = HomebrewFormulaCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner()
    let before = fixture.diagnostic(keg: "1.0.0")
    let preparation = try await preparedUninstall(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    try fixture.createKeg("0.5.0")
    fixture.state.kegs = ["0.5.0", "1.0.0"]
    let outcome = await HomebrewFormulaUninstallOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (before, fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    expectRefusedUninstall(outcome, runner: mutationRunner)
}

@Test func staleUninstallSelectionRefusesBeforeLaunch() async throws {
    let fixture = try HomebrewFormulaFixture("uninstall-stale-selection")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUninstall])
    let updateRunner = HomebrewFormulaCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner()
    let before = fixture.diagnostic(keg: "1.0.0")
    let preparation = try await preparedUninstall(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    try fixture.createKeg("1.5.0")
    fixture.state.kegs = ["1.0.0", "1.5.0"]
    fixture.state.selectedKeg = "1.5.0"
    try fixture.linkEntry(to: "1.5.0")
    let outcome = await HomebrewFormulaUninstallOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (before, fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    expectRefusedUninstall(outcome, runner: mutationRunner)
}

@Test func staleUninstallManagerExecutableRefusesBeforeLaunch() async throws {
    let fixture = try HomebrewFormulaFixture("uninstall-stale-manager")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUninstall])
    let updateRunner = HomebrewFormulaCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner()
    let before = fixture.diagnostic(keg: "1.0.0")
    let preparation = try await preparedUninstall(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    try fixture.rewriteManager()
    let outcome = await HomebrewFormulaUninstallOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (before, fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    expectRefusedUninstall(outcome, runner: mutationRunner)
}

@Test func interruptedUninstallReportsInterruptedWithReconciliation() async throws {
    let fixture = try HomebrewFormulaFixture(
        "uninstall-interrupted", kegs: ["0.9.0", "1.0.0"], selectedKeg: "1.0.0"
    )
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUninstall])
    let updateRunner = HomebrewFormulaCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner(
        result: OperationCommandResult(
            stdout: Data(), stderr: Data(),
            stdoutTruncated: false, stderrTruncated: false,
            exitStatus: nil, processStarted: true,
            timedOut: false, cancelled: true, cleanupWarning: false
        ),
        onLaunch: {
            try? fixture.removeEntry()
            try? fixture.removeKeg("1.0.0")
            fixture.state.kegs = ["0.9.0"]
            fixture.state.selectedKeg = nil
        }
    )
    let before = fixture.diagnostic(keg: "1.0.0")
    let preparation = try await preparedUninstall(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    let outcome = await HomebrewFormulaUninstallOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (fixture.notInstalledDiagnostic(), fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    #expect(outcome.state == .interrupted)
    #expect(outcome.processStarted)
    let delta = try #require(outcome.reconciliation)
    #expect(delta.recordedKegAbsent)
    #expect(delta.selectedTargetReleased)
    #expect(delta.remainingKegs == ["0.9.0"])
    #expect(outcome.message?.contains("interrupted") == true)
}

@Test func postLaunchObservationFailureIsNeverUninstallSuccess() async throws {
    let fixture = try HomebrewFormulaFixture("uninstall-observation-failure")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUninstall])
    let updateRunner = HomebrewFormulaCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner(onLaunch: {
        try? fixture.removeEntry()
        try? fixture.removeKeg("1.0.0")
        fixture.state.kegs = []
        fixture.state.selectedKeg = nil
    })
    let before = fixture.diagnostic(keg: "1.0.0")
    let preparation = try await preparedUninstall(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    let outcome = await HomebrewFormulaUninstallOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in
            fixture.state.infoFailure = true
            return (fixture.notInstalledDiagnostic(), fixture.environment)
        },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    #expect(outcome.state == .uncertain)
    #expect(outcome.processStarted)
    #expect(outcome.exitStatus == 0)
    let delta = try #require(outcome.reconciliation)
    #expect(delta.recordedKegAbsent)
    #expect(delta.selectedTargetReleased)
    #expect(delta.observationFailed)
    // The failed manager query leaves the residue inventory genuinely unknown, never "known
    // empty" and never a negative remaining-keg proof.
    #expect(delta.afterInstalledKegs == nil)
    #expect(delta.remainingKegs == nil)
    #expect(delta.formulaStillInstalledViaRemainingKeg == nil)
}

// MARK: - Manager prefix and proven removal target (R1 corrections 1 and 2)

@Test func uninstallPreviewBindsActualPrefixAndProvenRemovalTarget() async throws {
    let fixture = try HomebrewFormulaFixture(
        "uninstall-prefix", kegs: ["0.9.0", "1.0.0"], selectedKeg: "1.0.0"
    )
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUninstall])
    let runner = HomebrewFormulaCommandRunner(fixture: fixture)
    let preparation = try await preparedUninstall(
        fixture: fixture, definition: definition, diagnostic: fixture.diagnostic(keg: "1.0.0"),
        runner: runner
    )
    #expect(preparation.preview.prefix == fixture.prefix.path)
    #expect(preparation.preview.cellar == fixture.cellar.path)
    #expect(preparation.preview.prefix != preparation.preview.cellar)
    #expect(preparation.plan.removalTarget.source == .optLink)
    #expect(preparation.plan.removalTarget.keg == preparation.plan.keg)
    #expect(runner.invocations.contains {
        $0.arguments == ["--prefix"] && $0.executablePath == fixture.brew.path
    })
    #expect(HomebrewFormulaUninstallOperation.cancel(preparation))
}

@Test func olderSelectedKegWithNewerManagerDefaultRefusesBeforeScratchOrLaunch() async throws {
    let fixture = try HomebrewFormulaFixture(
        "uninstall-older-selected", kegs: ["1.0.0", "1.2.0"], selectedKeg: "1.0.0"
    )
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    // Homebrew's default target moved to the newer keg while PATH still selects the older keg.
    try fixture.setOptLink(to: "1.2.0")
    try fixture.setLinkedKegLink(to: "1.2.0")
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUninstall])
    let runner = HomebrewFormulaCommandRunner(fixture: fixture)
    let operationBase = fixture.root.appendingPathComponent("operation-base", isDirectory: true)
    try FileManager.default.createDirectory(at: operationBase, withIntermediateDirectories: true)
    let refused = await HomebrewFormulaUninstallOperation.prepare(
        definition: definition,
        diagnostic: fixture.diagnostic(keg: "1.0.0"),
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: runner,
        operationRootBaseURL: operationBase
    )
    guard case .unavailable(let reason) = refused else {
        Issue.record("an older selected keg must not authorize removing the newer default keg")
        return
    }
    #expect(reason == .uninstallRemovalTargetUnverified)
    #expect(try homebrewScratchIsEmpty(operationBase))
    #expect(!runner.invocations.contains { $0.arguments.first == "uninstall" })
}

@Test func optLinkTakesPrecedenceOverTheLinkedKegLink() async throws {
    let fixture = try HomebrewFormulaFixture(
        "uninstall-opt-precedence", kegs: ["1.0.0", "1.2.0"], selectedKeg: "1.0.0"
    )
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUninstall])
    let runner = HomebrewFormulaCommandRunner(fixture: fixture)

    // The opt link names the selected keg; the linked-keg link disagrees. Homebrew follows opt.
    try fixture.setOptLink(to: "1.0.0")
    try fixture.setLinkedKegLink(to: "1.2.0")
    let optWins = try await preparedUninstall(
        fixture: fixture, definition: definition, diagnostic: fixture.diagnostic(keg: "1.0.0"),
        runner: runner
    )
    #expect(optWins.plan.removalTarget.source == .optLink)
    #expect(optWins.plan.removalTarget.keg == optWins.plan.keg)
    #expect(HomebrewFormulaUninstallOperation.cancel(optWins))

    // Now opt names the newer keg while linked names the selected keg. Opt still wins, so the
    // literal command would remove the newer keg: a typed refusal.
    try fixture.setOptLink(to: "1.2.0")
    try fixture.setLinkedKegLink(to: "1.0.0")
    let operationBase = fixture.root.appendingPathComponent(
        "operation-base", isDirectory: true
    )
    try FileManager.default.createDirectory(at: operationBase, withIntermediateDirectories: true)
    let refused = await HomebrewFormulaUninstallOperation.prepare(
        definition: definition,
        diagnostic: fixture.diagnostic(keg: "1.0.0"),
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: runner,
        operationRootBaseURL: operationBase
    )
    guard case .unavailable(let reason) = refused else {
        Issue.record("opt precedence must refuse when it names a different keg")
        return
    }
    #expect(reason == .uninstallRemovalTargetUnverified)
    #expect(try homebrewScratchIsEmpty(operationBase))
}

@Test func linkedKegLinkProvesTheTargetWhenTheOptLinkIsAbsent() async throws {
    let fixture = try HomebrewFormulaFixture(
        "uninstall-linked-only", kegs: ["1.0.0", "1.2.0"], selectedKeg: "1.0.0"
    )
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try fixture.removeOptLink()
    try fixture.setLinkedKegLink(to: "1.0.0")
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUninstall])
    let runner = HomebrewFormulaCommandRunner(fixture: fixture)
    let preparation = try await preparedUninstall(
        fixture: fixture, definition: definition, diagnostic: fixture.diagnostic(keg: "1.0.0"),
        runner: runner
    )
    #expect(preparation.plan.removalTarget.source == .linkedKegLink)
    #expect(preparation.plan.removalTarget.keg == preparation.plan.keg)
    #expect(HomebrewFormulaUninstallOperation.cancel(preparation))
}

@Test func singleInstalledKegWithoutManagerLinksIsProvenAndUninstalls() async throws {
    let fixture = try HomebrewFormulaFixture("uninstall-single-no-links", kegs: ["1.0.0"])
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try fixture.removeOptLink()
    try fixture.removeLinkedKegLink()
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUninstall])
    let updateRunner = HomebrewFormulaCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner(onLaunch: {
        try? fixture.removeEntry()
        try? fixture.removeKeg("1.0.0")
        fixture.state.kegs = []
        fixture.state.selectedKeg = nil
    })
    let before = fixture.diagnostic(keg: "1.0.0")
    let preparation = try await preparedUninstall(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    #expect(preparation.plan.removalTarget.source == .singleInstalledKeg)
    let outcome = await HomebrewFormulaUninstallOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (fixture.notInstalledDiagnostic(), fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    #expect(outcome.state == .succeeded)
    #expect(outcome.reconciliation?.remainingKegs == [])
    #expect(mutationRunner.invocations.count == 1)
}

@Test func multipleKegsWithoutManagerLinksRefuseAsAmbiguous() async throws {
    let fixture = try HomebrewFormulaFixture(
        "uninstall-ambiguous", kegs: ["1.0.0", "1.2.0"], selectedKeg: "1.0.0"
    )
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try fixture.removeOptLink()
    try fixture.removeLinkedKegLink()
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUninstall])
    let runner = HomebrewFormulaCommandRunner(fixture: fixture)
    let operationBase = fixture.root.appendingPathComponent("operation-base", isDirectory: true)
    try FileManager.default.createDirectory(at: operationBase, withIntermediateDirectories: true)
    let refused = await HomebrewFormulaUninstallOperation.prepare(
        definition: definition,
        diagnostic: fixture.diagnostic(keg: "1.0.0"),
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: runner,
        operationRootBaseURL: operationBase
    )
    guard case .unavailable(let reason) = refused else {
        Issue.record("multiple kegs without a manager link are ambiguous")
        return
    }
    #expect(reason == .uninstallRemovalTargetUnverified)
    #expect(try homebrewScratchIsEmpty(operationBase))
}

// MARK: - Live Cellar rack proof for the single-keg fallback (R2 correction)

private func liveRackEvidence(
    fixture: HomebrewFormulaFixture,
    prefix: DirectoryIdentity,
    cellar: DirectoryIdentity,
    keg: DirectoryIdentity,
    installedKegs: [String] = ["1.0.0"]
) -> HomebrewRemovalTargetEvidence {
    homebrewRemovalTargetEvidence(
        prefix: prefix,
        cellar: cellar,
        formulaName: fixture.formulaName,
        installedKegs: installedKegs,
        selectedKegVersion: "1.0.0",
        selectedKeg: keg
    )
}

private func liveRackTarget(
    fixture: HomebrewFormulaFixture,
    prefix: DirectoryIdentity,
    cellar: DirectoryIdentity,
    keg: DirectoryIdentity,
    expected: HomebrewRemovalTarget,
    installedKegs: [String] = ["1.0.0"]
) -> Bool {
    homebrewRemovalTargetIsLive(
        prefix: prefix,
        cellar: cellar,
        formulaName: fixture.formulaName,
        installedKegs: installedKegs,
        selectedKegVersion: "1.0.0",
        selectedKeg: keg,
        expected: expected
    )
}

@Test func secondKegAfterTheFinalManagerReadRefusesBeforeLaunchWithUnchangedSelection() async throws {
    let fixture = try HomebrewFormulaFixture("uninstall-rack-after-read", kegs: ["1.0.0"])
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try fixture.removeOptLink()
    try fixture.removeLinkedKegLink()
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUninstall])
    let updateRunner = HomebrewFormulaCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner()
    let before = fixture.diagnostic(keg: "1.0.0")
    let preparation = try await preparedUninstall(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    #expect(preparation.plan.removalTarget.source == .singleInstalledKeg)
    let selectedBefore = try #require(
        FileIdentityObserver.observeExecutable(entryPath: fixture.entry.path)
    )

    // The second keg appears only after the confirmation pass has consumed its final asynchronous
    // manager read (`list --pinned`). The manager inventory deliberately stays at one keg, so only
    // a live rack observation made after that read can see the new directory.
    let rack = fixture.cellar.appendingPathComponent(fixture.formulaName, isDirectory: true)
    let addedKeg = rack.appendingPathComponent("1.2.0", isDirectory: true)
    updateRunner.onQuery = { invocation in
        guard invocation.arguments == ["list", "--pinned"] else { return }
        guard !FileManager.default.fileExists(atPath: addedKeg.path) else { return }
        try? fixture.createKeg("1.2.0")
    }

    let outcome = await HomebrewFormulaUninstallOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (before, fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    expectRefusedUninstall(
        outcome, runner: mutationRunner,
        messageContains: "default uninstall target changed"
    )
    // The selected executable and its target are byte-identical throughout the drift.
    #expect(FileIdentityObserver.observeExecutable(entryPath: fixture.entry.path) == selectedBefore)
}

@Test func immediatePrelaunchRackProofRejectsASecondKegWithUnchangedSelection() async throws {
    let fixture = try HomebrewFormulaFixture("uninstall-rack-live", kegs: ["1.0.0"])
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try fixture.removeOptLink()
    try fixture.removeLinkedKegLink()
    let prefix = try #require(FileIdentityObserver.observeDirectory(path: fixture.prefix.path))
    let cellar = try #require(FileIdentityObserver.observeDirectory(path: fixture.cellar.path))
    let keg = try #require(
        FileIdentityObserver.observeDirectory(path: fixture.kegDirectory("1.0.0").path)
    )
    let expected = HomebrewRemovalTarget(source: .singleInstalledKeg, keg: keg)
    #expect(liveRackEvidence(fixture: fixture, prefix: prefix, cellar: cellar, keg: keg)
        == .proven(expected))
    #expect(liveRackTarget(
        fixture: fixture, prefix: prefix, cellar: cellar, keg: keg, expected: expected
    ))
    let selectedBefore = try #require(
        FileIdentityObserver.observeExecutable(entryPath: fixture.entry.path)
    )

    // The selected executable is untouched; only a second keg directory appears. The immediate
    // pre-launch proof must re-read the live rack itself rather than replay the cached count.
    try fixture.createKeg("1.2.0")
    #expect(liveRackTarget(
        fixture: fixture, prefix: prefix, cellar: cellar, keg: keg, expected: expected
    ) == false)
    #expect(liveRackEvidence(fixture: fixture, prefix: prefix, cellar: cellar, keg: keg)
        == .unproven(.ambiguousMultipleKegs))
    #expect(FileIdentityObserver.observeExecutable(entryPath: fixture.entry.path) == selectedBefore)
}

@Test func ordinaryNonDirectoryRackEntryDoesNotCountAsASecondKeg() async throws {
    let fixture = try HomebrewFormulaFixture("uninstall-rack-file", kegs: ["1.0.0"])
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try fixture.removeOptLink()
    try fixture.removeLinkedKegLink()
    let rack = fixture.cellar.appendingPathComponent(fixture.formulaName, isDirectory: true)
    try Data("rackside residue".utf8).write(to: rack.appendingPathComponent(".rackside"))
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUninstall])
    let runner = HomebrewFormulaCommandRunner(fixture: fixture)
    let preparation = try await preparedUninstall(
        fixture: fixture, definition: definition, diagnostic: fixture.diagnostic(keg: "1.0.0"),
        runner: runner
    )
    #expect(preparation.plan.removalTarget.source == .singleInstalledKeg)
    #expect(preparation.plan.removalTarget.keg == preparation.plan.keg)
    #expect(HomebrewFormulaUninstallOperation.cancel(preparation))
}

@Test func unclassifiableRackEntryFailsClosedBeforeScratchOrLaunch() async throws {
    let fixture = try HomebrewFormulaFixture("uninstall-rack-symlink", kegs: ["1.0.0"])
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try fixture.removeOptLink()
    try fixture.removeLinkedKegLink()
    let rack = fixture.cellar.appendingPathComponent(fixture.formulaName, isDirectory: true)
    // A directory symlink is a possible keg to Homebrew's own rack enumeration; the proof cannot
    // classify it as an ordinary non-directory, so it must refuse instead of counting one keg.
    try FileManager.default.createSymbolicLink(
        atPath: rack.appendingPathComponent("alias-1.0.0").path,
        withDestinationPath: "1.0.0"
    )
    let prefix = try #require(FileIdentityObserver.observeDirectory(path: fixture.prefix.path))
    let cellar = try #require(FileIdentityObserver.observeDirectory(path: fixture.cellar.path))
    let keg = try #require(
        FileIdentityObserver.observeDirectory(path: fixture.kegDirectory("1.0.0").path)
    )
    #expect(liveRackEvidence(fixture: fixture, prefix: prefix, cellar: cellar, keg: keg)
        == .unproven(.rackUnverified))

    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUninstall])
    let runner = HomebrewFormulaCommandRunner(fixture: fixture)
    let operationBase = fixture.root.appendingPathComponent("operation-base", isDirectory: true)
    try FileManager.default.createDirectory(at: operationBase, withIntermediateDirectories: true)
    let refused = await HomebrewFormulaUninstallOperation.prepare(
        definition: definition,
        diagnostic: fixture.diagnostic(keg: "1.0.0"),
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: runner,
        operationRootBaseURL: operationBase
    )
    guard case .unavailable(let reason) = refused else {
        Issue.record("an unclassifiable rack entry must refuse the single-keg fallback")
        return
    }
    #expect(reason == .uninstallRemovalTargetUnverified)
    #expect(try homebrewScratchIsEmpty(operationBase))
    #expect(!runner.invocations.contains { $0.arguments.first == "uninstall" })
}

@Test func emptyOrMissingRackIsUnverified() async throws {
    let fixture = try HomebrewFormulaFixture("uninstall-rack-stale", kegs: ["1.0.0"])
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try fixture.removeOptLink()
    try fixture.removeLinkedKegLink()
    let prefix = try #require(FileIdentityObserver.observeDirectory(path: fixture.prefix.path))
    let cellar = try #require(FileIdentityObserver.observeDirectory(path: fixture.cellar.path))
    let keg = try #require(
        FileIdentityObserver.observeDirectory(path: fixture.kegDirectory("1.0.0").path)
    )
    #expect(liveRackEvidence(fixture: fixture, prefix: prefix, cellar: cellar, keg: keg)
        == .proven(HomebrewRemovalTarget(source: .singleInstalledKeg, keg: keg)))

    // An empty rack can no longer prove which keg Homebrew's fallback selects.
    try fixture.removeKeg("1.0.0")
    #expect(liveRackEvidence(fixture: fixture, prefix: prefix, cellar: cellar, keg: keg)
        == .unproven(.rackUnverified))

    // A missing rack is likewise unverified, never "zero kegs, proceed".
    let rack = fixture.cellar.appendingPathComponent(fixture.formulaName, isDirectory: true)
    try FileManager.default.removeItem(at: rack)
    #expect(liveRackEvidence(fixture: fixture, prefix: prefix, cellar: cellar, keg: keg)
        == .unproven(.rackUnverified))
}

@Test func symlinkedRackPathIsUnverifiedRatherThanFollowed() async throws {
    let fixture = try HomebrewFormulaFixture("uninstall-rack-alias", kegs: ["1.0.0"])
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try fixture.removeOptLink()
    try fixture.removeLinkedKegLink()
    let prefix = try #require(FileIdentityObserver.observeDirectory(path: fixture.prefix.path))
    let cellar = try #require(FileIdentityObserver.observeDirectory(path: fixture.cellar.path))
    let keg = try #require(
        FileIdentityObserver.observeDirectory(path: fixture.kegDirectory("1.0.0").path)
    )

    // The manager's Cellar rack is a real directory. If the rack path is replaced by a symlink,
    // the proof cannot treat the alias as the same rack position it bound, so it refuses rather
    // than following the link and counting whatever is behind it.
    let rack = fixture.cellar.appendingPathComponent(fixture.formulaName, isDirectory: true)
    let rackStore = fixture.cellar.appendingPathComponent("m13tool-store", isDirectory: true)
    try FileManager.default.moveItem(at: rack, to: rackStore)
    try FileManager.default.createSymbolicLink(
        atPath: rack.path, withDestinationPath: rackStore.lastPathComponent
    )
    #expect(FileIdentityObserver.observeDirectory(
        path: rackStore.appendingPathComponent("1.0.0").path
    ) != nil)
    #expect(liveRackEvidence(fixture: fixture, prefix: prefix, cellar: cellar, keg: keg)
        == .unproven(.rackUnverified))
}

@Test func replacedSelectedKegVnodeUnderOneRackEntryIsContradictory() async throws {
    let fixture = try HomebrewFormulaFixture("uninstall-rack-replaced", kegs: ["1.0.0"])
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try fixture.removeOptLink()
    try fixture.removeLinkedKegLink()
    let prefix = try #require(FileIdentityObserver.observeDirectory(path: fixture.prefix.path))
    let cellar = try #require(FileIdentityObserver.observeDirectory(path: fixture.cellar.path))
    let keg = try #require(
        FileIdentityObserver.observeDirectory(path: fixture.kegDirectory("1.0.0").path)
    )
    let expected = HomebrewRemovalTarget(source: .singleInstalledKeg, keg: keg)
    #expect(liveRackTarget(
        fixture: fixture, prefix: prefix, cellar: cellar, keg: keg, expected: expected
    ))

    // Same version path, different vnode: the single rack entry is no longer the bound selected
    // keg, so the fallback is inconsistent even though the cached name and count still agree.
    try fixture.removeKeg("1.0.0")
    try fixture.createKeg("1.0.0")
    #expect(liveRackEvidence(fixture: fixture, prefix: prefix, cellar: cellar, keg: keg)
        == .unproven(.contradictoryEvidence))
    #expect(liveRackTarget(
        fixture: fixture, prefix: prefix, cellar: cellar, keg: keg, expected: expected
    ) == false)
}

@Test func rackEntryFloodFailsClosedAtTheObservationBound() async throws {
    let fixture = try HomebrewFormulaFixture("uninstall-rack-flood", kegs: ["1.0.0"])
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try fixture.removeOptLink()
    try fixture.removeLinkedKegLink()
    let rack = fixture.cellar.appendingPathComponent(fixture.formulaName, isDirectory: true)
    for index in 0..<512 {
        FileManager.default.createFile(
            atPath: rack.appendingPathComponent("file-\(index)").path, contents: nil
        )
    }
    let prefix = try #require(FileIdentityObserver.observeDirectory(path: fixture.prefix.path))
    let cellar = try #require(FileIdentityObserver.observeDirectory(path: fixture.cellar.path))
    let keg = try #require(
        FileIdentityObserver.observeDirectory(path: fixture.kegDirectory("1.0.0").path)
    )
    // 512 ordinary files plus the one keg exceed the bounded roster; the proof refuses rather
    // than returning a partial count.
    #expect(liveRackEvidence(fixture: fixture, prefix: prefix, cellar: cellar, keg: keg)
        == .unproven(.rackUnverified))
}

@Test func retargetedOptLinkWithUnchangedSelectionRefusesBeforeLaunch() async throws {
    let fixture = try HomebrewFormulaFixture(
        "uninstall-opt-drift", kegs: ["1.0.0", "1.2.0"], selectedKeg: "1.0.0"
    )
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUninstall])
    let updateRunner = HomebrewFormulaCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner()
    let before = fixture.diagnostic(keg: "1.0.0")
    let preparation = try await preparedUninstall(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    // Default target drifts to the newer keg; the selected executable and its target are unchanged.
    try fixture.setOptLink(to: "1.2.0")
    let outcome = await HomebrewFormulaUninstallOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (before, fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    expectRefusedUninstall(
        outcome, runner: mutationRunner,
        messageContains: "default uninstall target changed"
    )
}

@Test func missingPrefixRefusesUninstallBeforeScratchOrLaunch() async throws {
    let fixture = try HomebrewFormulaFixture("uninstall-prefix-missing")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    fixture.state.prefixFailure = true
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUninstall])
    let runner = HomebrewFormulaCommandRunner(fixture: fixture)
    let operationBase = fixture.root.appendingPathComponent("operation-base", isDirectory: true)
    try FileManager.default.createDirectory(at: operationBase, withIntermediateDirectories: true)
    let refused = await HomebrewFormulaUninstallOperation.prepare(
        definition: definition,
        diagnostic: fixture.diagnostic(keg: "1.0.0"),
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: runner,
        operationRootBaseURL: operationBase
    )
    guard case .unavailable(let reason) = refused else {
        Issue.record("an unavailable manager prefix must refuse Uninstall")
        return
    }
    #expect(reason == .probeFailed)
    #expect(try homebrewScratchIsEmpty(operationBase))
    #expect(!runner.invocations.contains { $0.arguments.first == "uninstall" })
}

@Test func prefixIdentityChangeImmediatelyBeforeUninstallLaunchRefuses() async throws {
    let fixture = try HomebrewFormulaFixture("uninstall-prefix-identity")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUninstall])
    let updateRunner = HomebrewFormulaCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner()
    let before = fixture.diagnostic(keg: "1.0.0")
    let preparation = try await preparedUninstall(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    try fixture.changePrefixMode(to: 0o750)
    let outcome = await HomebrewFormulaUninstallOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (before, fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    expectRefusedUninstall(outcome, runner: mutationRunner)
}

// MARK: - Stable null and unknown residue (R1 corrections 3 and 4)

@Test func jsonNullStableIsAbsentMetadataForUninstallButUnsupportedForUpdate() async throws {
    let fixture = try HomebrewFormulaFixture(
        "stable-null", kegs: ["1.0.0"], selectedKeg: "1.0.0", stable: "1.0.0"
    )
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    fixture.state.stableJSONNull = true
    let definition = try fixture.definition(
        acceptedOperations: [.homebrewFormulaUpdate, .homebrewFormulaUninstall]
    )
    let runner = HomebrewFormulaCommandRunner(fixture: fixture)

    // Valid identity, unpinned, and a confirmed default removable keg: Uninstall stays available
    // even though the manager reports no stable version.
    let preparation = try await preparedUninstall(
        fixture: fixture, definition: definition, diagnostic: fixture.diagnostic(keg: "1.0.0"),
        runner: runner
    )
    #expect(preparation.preview.selectedKegVersion == "1.0.0")
    #expect(preparation.plan.removalTarget.keg == preparation.plan.keg)
    #expect(HomebrewFormulaUninstallOperation.cancel(preparation))

    // Update still requires a supported stable target.
    let update = await HomebrewFormulaUpdateOperation.prepare(
        definition: definition,
        diagnostic: fixture.diagnostic(keg: "1.0.0"),
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: runner,
        operationRootBaseURL: fixture.root
    )
    guard case .unavailable(let updateReason) = update else {
        Issue.record("null stable must refuse Update as unsupported")
        return
    }
    #expect(updateReason == .unsupportedVersion)
}

@Test func malformedNonNullStableFailsClosedForBothOperations() async throws {
    let fixture = try HomebrewFormulaFixture(
        "stable-malformed", kegs: ["1.0.0"], selectedKeg: "1.0.0", stable: "1.0.0"
    )
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    fixture.state.stableMalformed = true
    let definition = try fixture.definition(
        acceptedOperations: [.homebrewFormulaUpdate, .homebrewFormulaUninstall]
    )
    let runner = HomebrewFormulaCommandRunner(fixture: fixture)
    let operationBase = fixture.root.appendingPathComponent("operation-base", isDirectory: true)
    try FileManager.default.createDirectory(at: operationBase, withIntermediateDirectories: true)

    let uninstall = await HomebrewFormulaUninstallOperation.prepare(
        definition: definition,
        diagnostic: fixture.diagnostic(keg: "1.0.0"),
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: runner,
        operationRootBaseURL: operationBase
    )
    guard case .unavailable(let uninstallReason) = uninstall else {
        Issue.record("a non-string, non-null stable must fail Uninstall closed")
        return
    }
    #expect(uninstallReason == .probeFailed)

    let update = await HomebrewFormulaUpdateOperation.prepare(
        definition: definition,
        diagnostic: fixture.diagnostic(keg: "1.0.0"),
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: runner,
        operationRootBaseURL: operationBase
    )
    guard case .unavailable(let updateReason) = update else {
        Issue.record("a non-string, non-null stable must fail Update closed")
        return
    }
    #expect(updateReason == .metadataInvalid)
    #expect(try homebrewScratchIsEmpty(operationBase))
    #expect(!runner.invocations.contains {
        $0.arguments.first == "upgrade" || $0.arguments.first == "uninstall"
    })
}

@Test func malformedPostUninstallInfoPreservesUnknownResidue() async throws {
    let fixture = try HomebrewFormulaFixture("uninstall-malformed-residue")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUninstall])
    let updateRunner = HomebrewFormulaCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner(onLaunch: {
        try? fixture.removeEntry()
        try? fixture.removeKeg("1.0.0")
        fixture.state.kegs = []
        fixture.state.selectedKeg = nil
    })
    let before = fixture.diagnostic(keg: "1.0.0")
    let preparation = try await preparedUninstall(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    let outcome = await HomebrewFormulaUninstallOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in
            fixture.state.infoMalformed = true
            return (fixture.notInstalledDiagnostic(), fixture.environment)
        },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    #expect(outcome.state == .uncertain)
    #expect(outcome.processStarted)
    let delta = try #require(outcome.reconciliation)
    #expect(delta.recordedKegAbsent)
    #expect(delta.observationFailed)
    #expect(delta.afterInstalledKegs == nil)
    #expect(delta.remainingKegs == nil)
    #expect(delta.formulaStillInstalledViaRemainingKeg == nil)
}

@Test func linkedKegLinkMismatchRefusesWhenTheOptLinkIsAbsent() async throws {
    let fixture = try HomebrewFormulaFixture(
        "uninstall-linked-mismatch", kegs: ["1.0.0", "1.2.0"], selectedKeg: "1.0.0"
    )
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try fixture.removeOptLink()
    try fixture.setLinkedKegLink(to: "1.2.0")
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUninstall])
    let runner = HomebrewFormulaCommandRunner(fixture: fixture)
    let operationBase = fixture.root.appendingPathComponent("operation-base", isDirectory: true)
    try FileManager.default.createDirectory(at: operationBase, withIntermediateDirectories: true)
    let refused = await HomebrewFormulaUninstallOperation.prepare(
        definition: definition,
        diagnostic: fixture.diagnostic(keg: "1.0.0"),
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: runner,
        operationRootBaseURL: operationBase
    )
    guard case .unavailable(let reason) = refused else {
        Issue.record("a linked-keg link naming another keg must refuse")
        return
    }
    #expect(reason == .uninstallRemovalTargetUnverified)
    #expect(try homebrewScratchIsEmpty(operationBase))
}

@Test func contradictoryManagerLinkEvidenceRefusesUninstallButNotUpdate() async throws {
    let fixture = try HomebrewFormulaFixture(
        "uninstall-contradictory-link", kegs: ["1.0.0"], selectedKeg: "1.0.0"
    )
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try fixture.removeOptLink()
    try fixture.removeLinkedKegLink()
    // A non-symlink at the opt path is unusable manager evidence, not a fall-through.
    try FileManager.default.createDirectory(
        at: fixture.optLink, withIntermediateDirectories: true
    )
    let definition = try fixture.definition(
        acceptedOperations: [.homebrewFormulaUpdate, .homebrewFormulaUninstall]
    )
    let runner = HomebrewFormulaCommandRunner(fixture: fixture)
    let operationBase = fixture.root.appendingPathComponent("operation-base", isDirectory: true)
    try FileManager.default.createDirectory(at: operationBase, withIntermediateDirectories: true)

    let uninstall = await HomebrewFormulaUninstallOperation.prepare(
        definition: definition,
        diagnostic: fixture.diagnostic(keg: "1.0.0"),
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: runner,
        operationRootBaseURL: operationBase
    )
    guard case .unavailable(let reason) = uninstall else {
        Issue.record("contradictory manager link evidence must refuse Uninstall")
        return
    }
    #expect(reason == .uninstallRemovalTargetUnverified)
    #expect(try homebrewScratchIsEmpty(operationBase))

    // Uninstall's removal-target proof must not narrow Update's availability.
    let update = await HomebrewFormulaUpdateOperation.prepare(
        definition: definition,
        diagnostic: fixture.diagnostic(keg: "1.0.0"),
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: runner,
        operationRootBaseURL: fixture.root
    )
    guard case .ready(let preparation) = update else {
        Issue.record("contradictory uninstall evidence must not refuse Update")
        return
    }
    #expect(HomebrewFormulaUpdateOperation.cancel(preparation))
}
