import Foundation
import Testing
@testable import AgentLensCore

// M13-D formula Update: lifecycle, literal argv, environment policy, refusal ordering, pin and
// disabled/deprecated policy, stale-fact invalidation, interruption and reconciliation. Every test
// uses the disposable synthetic Cellar in HomebrewFormulaOperationTestSupport.swift; no real brew
// executable or personal manager state is touched.

private func preparedUpdate(
    fixture: HomebrewFormulaFixture,
    definition: DetectorDefinition,
    diagnostic: ToolPathDiagnostic,
    runner: UpdateCommandRunner
) async throws -> HomebrewFormulaUpdatePreparation {
    switch await HomebrewFormulaUpdateOperation.prepare(
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
            domain: "HomebrewFormulaUpdateOperationTests", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "unexpected refusal: \(reason)"]
        )
    }
}

private func expectRefusedUpdate(
    _ outcome: HomebrewFormulaUpdateOutcome,
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

// MARK: - Lifecycle, preview and environment

@Test func preparationBindsPreviewAndExecutionSucceedsWithExactArgvAndEnvironment() async throws {
    let fixture = try HomebrewFormulaFixture(
        "update-success",
        kegs: ["0.9.0", "1.0.0"],
        selectedKeg: "1.0.0",
        stable: "2.0.0",
        hostileEnvironment: true
    )
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUpdate])
    let before = fixture.diagnostic(keg: "1.0.0")
    let updateRunner = HomebrewFormulaCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner(
        result: OperationCommandResult(
            stdout: Data("upgraded\n".utf8), stderr: Data("note\n".utf8),
            stdoutTruncated: false, stderrTruncated: false,
            exitStatus: 0, processStarted: true,
            timedOut: false, cancelled: false, cleanupWarning: false
        ),
        onLaunch: {
            try? fixture.createKeg("2.0.0")
            try? fixture.linkEntry(to: "2.0.0")
            fixture.state.kegs = ["0.9.0", "1.0.0", "2.0.0"]
            fixture.state.selectedKeg = "2.0.0"
        }
    )

    let preparation = try await preparedUpdate(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    let preview = preparation.preview
    #expect(preview.registryID == "m13tool")
    #expect(preview.kind == .formula)
    #expect(preview.formulaName == "m13tool")
    #expect(preview.fullName == "m13tool")
    #expect(preview.selectedEntryPath == fixture.entry.path)
    #expect(preview.selectedTarget == fixture.expectedTarget("1.0.0"))
    #expect(preview.selectedKegVersion == "1.0.0")
    #expect(preview.installedKegs == ["0.9.0", "1.0.0"])
    #expect(preview.targetVersion == "2.0.0")
    #expect(preview.targetResolution == homebrewFormulaTargetResolutionDisclosure)
    #expect(preview.targetResolution.contains("re-resolves the target version"))
    #expect(preview.pinned == false)
    #expect(preview.deprecated == false)
    #expect(preview.prefix == fixture.prefix.path)
    #expect(preview.cellar == fixture.cellar.path)
    #expect(preview.executablePath == fixture.brew.path)
    #expect(preview.arguments == ["upgrade", "--formula", "--yes", "m13tool"])
    #expect(preview.timeoutSeconds == 900)
    #expect(preview.effect == homebrewFormulaUpdateEffectText)
    for phrase in [
        "upgrade only the named formula",
        "no other formula or cask is targeted",
        "metadata auto-update is disabled",
        "analytics are disabled",
        "automatic post-upgrade cleanup is disabled",
        "automatic removal of no-longer-needed dependencies is disabled",
        "outdated dependent formulae is disabled",
        "includes --yes",
        "Greedy-upgrade, cask-option, upgrade-quit, and automatic-removal environment overrides are not honored",
        "download cache, logs, and temporary files",
        "does not redirect, inspect, or delete them",
        "No rollback, reinstall, or atomicity is guaranteed",
        "bounded to 900 seconds",
    ] {
        #expect(preview.effect.contains(phrase), "effect text is missing: \(phrase)")
    }
    expectNoForbiddenMutationTokens(preview.arguments)

    let outcome = await HomebrewFormulaUpdateOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in
            (fixture.diagnostic(keg: "2.0.0", version: "2.0.0"), fixture.environment)
        },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    #expect(outcome.state == .succeeded)
    #expect(outcome.processStarted)
    #expect(outcome.exitStatus == 0)
    #expect(outcome.stdoutText == "upgraded\n")
    #expect(outcome.stderrText == "note\n")
    #expect(outcome.cleanupWarnings.isEmpty)
    #expect(outcome.message == nil)
    let delta = try #require(outcome.reconciliation)
    #expect(delta.beforeSelectedKegVersion == "1.0.0")
    #expect(delta.afterSelectedKegVersion == "2.0.0")
    #expect(delta.observedTargetVersion == "2.0.0")
    #expect(delta.versionMatchesTarget)
    #expect(delta.previousKegReplaced)
    #expect(delta.previousKegStillPresent)
    #expect(delta.afterInstalledKegs == ["0.9.0", "1.0.0", "2.0.0"])
    #expect(!delta.observationFailed)
    #expect(delta.changed)
    guard case .verified(let installation)? = delta.ownership else {
        Issue.record("reconciliation must re-verify ownership")
        return
    }
    #expect(installation.manager == .homebrewFormula)
    #expect(installation.packageName == fixture.fullName)
    #expect(installation.managerRoot == fixture.cellar.path)
    #expect(!FileManager.default.fileExists(atPath: preview.workingDirectory))

    // One literal mutation, from the owned scratch, with the exact mutation environment.
    #expect(mutationRunner.invocations.count == 1)
    let mutation = try #require(mutationRunner.invocations.first)
    #expect(mutation.executablePath == fixture.brew.path)
    #expect(mutation.arguments == ["upgrade", "--formula", "--yes", "m13tool"])
    #expect(mutation.currentDirectory == preview.workingDirectory)
    #expect(mutation.timeout == 900)
    let environment = mutation.environment
    #expect(environment["HOMEBREW_NO_AUTO_UPDATE"] == "1")
    #expect(environment["HOMEBREW_NO_ANALYTICS"] == "1")
    #expect(environment["HOMEBREW_NO_INSTALL_CLEANUP"] == "1")
    #expect(environment["HOMEBREW_NO_AUTOREMOVE"] == "1")
    #expect(environment["HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK"] == "1")
    #expect(environment["HOMEBREW_NO_ASK"] == nil)
    for key in HomebrewOperationEnvironment.removedKeys {
        #expect(environment[key] == nil, "the mutation environment must not inherit \(key)")
    }
    // Homebrew's own cache/log/temp defaults are inherited untouched, never redirected.
    #expect(environment["HOMEBREW_CACHE"] == "/personal/brew-cache")
    #expect(environment["HOMEBREW_LOGS"] == nil)
    #expect(environment["HOMEBREW_TEMP"] == nil)

    // Read-only queries keep the diagnostic environment: no mutation switches leak into them.
    #expect(!updateRunner.invocations.isEmpty)
    for invocation in updateRunner.invocations {
        #expect(invocation.environment["HOMEBREW_NO_INSTALL_CLEANUP"] == nil)
        #expect(invocation.environment["HOMEBREW_NO_AUTOREMOVE"] == nil)
        #expect(invocation.environment["HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK"] == nil)
        #expect(invocation.environment["HOMEBREW_NO_AUTO_UPDATE"] == "1")
        #expect(invocation.environment["HOMEBREW_NO_ANALYTICS"] == "1")
    }
}

@Test func environmentBuilderIsOnePolicyForBothOperations() {
    let environment = ShellEnvironment(
        shellPath: "/bin/zsh",
        pathEntries: ["/usr/bin"],
        pathJoined: "/usr/bin",
        raw: [
            "PATH": "/usr/bin",
            "HOMEBREW_UPGRADE_GREEDY": "1",
            "HOMEBREW_UPGRADE_GREEDY_CASKS": "1",
            "HOMEBREW_NO_UPGRADE_QUIT_CASKS": "1",
            "HOMEBREW_CASK_OPTS": "--appdir=/Applications",
            "HOMEBREW_AUTOREMOVE": "1",
            "HOMEBREW_CACHE": "/personal/cache",
        ],
        isDegraded: false
    )
    let update = HomebrewOperationEnvironment.mutationEnvironment(
        from: environment, kind: .formulaUpdate
    )
    let uninstall = HomebrewOperationEnvironment.mutationEnvironment(
        from: environment, kind: .formulaUninstall
    )
    #expect(update["HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK"] == "1")
    #expect(uninstall["HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK"] == nil)
    for environment in [update, uninstall] {
        #expect(environment["HOMEBREW_NO_AUTO_UPDATE"] == "1")
        #expect(environment["HOMEBREW_NO_ANALYTICS"] == "1")
        #expect(environment["HOMEBREW_NO_INSTALL_CLEANUP"] == "1")
        #expect(environment["HOMEBREW_NO_AUTOREMOVE"] == "1")
        for key in HomebrewOperationEnvironment.removedKeys {
            #expect(environment[key] == nil)
        }
        // The builder never invents a cache/log/temp redirect and never sets NO_ASK itself.
        #expect(environment["HOMEBREW_CACHE"] == "/personal/cache")
        #expect(environment["HOMEBREW_LOGS"] == nil)
        #expect(environment["HOMEBREW_TEMP"] == nil)
        #expect(environment["HOMEBREW_NO_ASK"] == nil)
    }
    #expect(HomebrewOperationEnvironment.requiredSwitches(kind: .formulaUpdate)
        == [
            "HOMEBREW_NO_AUTO_UPDATE": "1",
            "HOMEBREW_NO_ANALYTICS": "1",
            "HOMEBREW_NO_INSTALL_CLEANUP": "1",
            "HOMEBREW_NO_AUTOREMOVE": "1",
            "HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK": "1",
        ])
    #expect(HomebrewOperationEnvironment.requiredSwitches(kind: .formulaUninstall)
        == [
            "HOMEBREW_NO_AUTO_UPDATE": "1",
            "HOMEBREW_NO_ANALYTICS": "1",
            "HOMEBREW_NO_INSTALL_CLEANUP": "1",
            "HOMEBREW_NO_AUTOREMOVE": "1",
        ])
}

@Test func revisionIsTheOnlyPackageRevisionSource() async throws {
    let fixture = try HomebrewFormulaFixture("update-revision", stable: "1.5.0")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    fixture.state.revision = 2
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUpdate])
    let runner = HomebrewFormulaCommandRunner(fixture: fixture)
    let preparation = try await preparedUpdate(
        fixture: fixture, definition: definition, diagnostic: fixture.diagnostic(keg: "1.0.0"),
        runner: runner
    )
    #expect(preparation.preview.targetVersion == "1.5.0_2")
    #expect(HomebrewFormulaUpdateOperation.cancel(preparation))

    // A revision-looking suffix in `stable` is not interpreted as a revision.
    fixture.state.stable = "1.5.0_2"
    let refused = await HomebrewFormulaUpdateOperation.prepare(
        definition: definition,
        diagnostic: fixture.diagnostic(keg: "1.0.0"),
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: runner,
        operationRootBaseURL: fixture.root
    )
    guard case .unavailable(let reason) = refused else {
        Issue.record("a decorated stable text must be refused")
        return
    }
    #expect(reason == .unsupportedVersion)
}

// MARK: - Refusal ordering and scratch

@Test func unacceptedUpdateRefusesBeforeObservationScratchOrProcess() async throws {
    let fixture = try HomebrewFormulaFixture("update-unaccepted")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [])
    let runner = HomebrewCountingCommandRunner()
    let operationBase = fixture.root.appendingPathComponent("operation-base", isDirectory: true)
    try FileManager.default.createDirectory(at: operationBase, withIntermediateDirectories: true)

    let refused = await HomebrewFormulaUpdateOperation.prepare(
        definition: definition,
        diagnostic: fixture.diagnostic(keg: "1.0.0"),
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: runner,
        operationRootBaseURL: operationBase
    )
    guard case .unavailable(let reason) = refused else {
        Issue.record("unaccepted Update must refuse preparation")
        return
    }
    #expect(reason == .operationNotAccepted)
    #expect(reason.message.contains("not yet accepted"))
    #expect(runner.invocations == 0)
    #expect(try homebrewScratchIsEmpty(operationBase))

    // The gate is the first decision: an unsafe scratch root is never inspected.
    let unsafeEnvironment = ShellEnvironment(
        shellPath: fixture.environment.shellPath,
        pathEntries: fixture.environment.pathEntries,
        pathJoined: fixture.environment.pathJoined,
        raw: fixture.environment.raw.merging(["TMPDIR": "/"]) { _, new in new },
        isDegraded: false
    )
    let refusedAfterUnsafe = await HomebrewFormulaUpdateOperation.prepare(
        definition: definition,
        diagnostic: fixture.diagnostic(keg: "1.0.0"),
        environment: unsafeEnvironment,
        currentDirectory: fixture.root.path,
        runner: runner
    )
    guard case .unavailable(let unsafeReason) = refusedAfterUnsafe else {
        Issue.record("unaccepted Update must refuse before scratch validation")
        return
    }
    #expect(unsafeReason == .operationNotAccepted)
    #expect(runner.invocations == 0)
}

@Test func cancellingAPreparationReleasesItsRootAndLaunchesNothing() async throws {
    let fixture = try HomebrewFormulaFixture("update-cancel")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUpdate])
    let updateRunner = HomebrewFormulaCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner()
    let before = fixture.diagnostic(keg: "1.0.0")
    let preparation = try await preparedUpdate(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    let root = preparation.preview.workingDirectory
    #expect(FileManager.default.fileExists(atPath: root))
    #expect(HomebrewFormulaUpdateOperation.cancel(preparation))
    #expect(!FileManager.default.fileExists(atPath: root))

    let outcome = await HomebrewFormulaUpdateOperation.execute(
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

@Test func cancelledPreparationTaskRefusesBeforeScratchClaim() async throws {
    let fixture = try HomebrewFormulaFixture("update-cancelled-task")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUpdate])
    let runner = HomebrewCountingCommandRunner()
    let operationBase = fixture.root.appendingPathComponent("operation-base", isDirectory: true)
    try FileManager.default.createDirectory(at: operationBase, withIntermediateDirectories: true)
    let task = Task {
        await HomebrewFormulaUpdateOperation.prepare(
            definition: definition,
            diagnostic: fixture.diagnostic(keg: "1.0.0"),
            environment: fixture.environment,
            currentDirectory: fixture.root.path,
            runner: runner,
            operationRootBaseURL: operationBase
        )
    }
    task.cancel()
    let result = await task.value
    guard case .unavailable(let reason) = result else {
        Issue.record("a cancelled preparation must refuse")
        return
    }
    #expect(reason == .cancelled)
    #expect(runner.invocations == 0)
    #expect(try homebrewScratchIsEmpty(operationBase))
}

@Test func gateContentionRefusesWithoutLaunchAndReleasesThePreview() async throws {
    let fixture = try HomebrewFormulaFixture("update-gate")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUpdate])
    let updateRunner = HomebrewFormulaCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner()
    let before = fixture.diagnostic(keg: "1.0.0")
    let preparation = try await preparedUpdate(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    let gate = OperationExecutionGate()
    #expect(await gate.acquire())
    let outcome = await HomebrewFormulaUpdateOperation.execute(
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
    #expect(!FileManager.default.fileExists(atPath: preparation.preview.workingDirectory))
}

@Test func theSharedProcessWideGateAlsoExcludesTheHomebrewMutation() async throws {
    let fixture = try HomebrewFormulaFixture("update-shared-gate")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUpdate])
    let updateRunner = HomebrewFormulaCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner()
    let before = fixture.diagnostic(keg: "1.0.0")
    let preparation = try await preparedUpdate(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    #expect(await OperationExecutionGate.shared.acquire())
    let outcome = await HomebrewFormulaUpdateOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (before, fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: .shared
    )
    await OperationExecutionGate.shared.release()
    #expect(outcome.state == .cancelled)
    #expect(!outcome.processStarted)
    #expect(mutationRunner.invocations.isEmpty)
}

// MARK: - Target grammar and availability

@Test func equalOrOlderObservedTargetsRefusePreparation() async throws {
    let equalFixture = try HomebrewFormulaFixture(
        "update-equal", kegs: ["2.0.0"], selectedKeg: "2.0.0", stable: "2.0.0"
    )
    defer { try? FileManager.default.removeItem(at: equalFixture.root) }
    let equalDefinition = try equalFixture.definition(
        acceptedOperations: [.homebrewFormulaUpdate]
    )
    let equalRunner = HomebrewFormulaCommandRunner(fixture: equalFixture)
    let equalResult = await HomebrewFormulaUpdateOperation.prepare(
        definition: equalDefinition,
        diagnostic: equalFixture.diagnostic(keg: "2.0.0"),
        environment: equalFixture.environment,
        currentDirectory: equalFixture.root.path,
        runner: equalRunner,
        operationRootBaseURL: equalFixture.root
    )
    guard case .unavailable(let equalReason) = equalResult else {
        Issue.record("an up-to-date formula must refuse Update")
        return
    }
    #expect(equalReason == .notUpdateAvailable)

    let olderFixture = try HomebrewFormulaFixture(
        "update-older", kegs: ["3.0.0"], selectedKeg: "3.0.0", stable: "1.0.0"
    )
    defer { try? FileManager.default.removeItem(at: olderFixture.root) }
    let olderDefinition = try olderFixture.definition(
        acceptedOperations: [.homebrewFormulaUpdate]
    )
    let olderRunner = HomebrewFormulaCommandRunner(fixture: olderFixture)
    let olderResult = await HomebrewFormulaUpdateOperation.prepare(
        definition: olderDefinition,
        diagnostic: olderFixture.diagnostic(keg: "3.0.0"),
        environment: olderFixture.environment,
        currentDirectory: olderFixture.root.path,
        runner: olderRunner,
        operationRootBaseURL: olderFixture.root
    )
    guard case .unavailable(let olderReason) = olderResult else {
        Issue.record("a newer installed keg must refuse Update")
        return
    }
    #expect(olderReason == .newerThanMetadata)

    let latestFixture = try HomebrewFormulaFixture("update-latest", stable: "latest")
    defer { try? FileManager.default.removeItem(at: latestFixture.root) }
    let latestDefinition = try latestFixture.definition(
        acceptedOperations: [.homebrewFormulaUpdate]
    )
    let latestRunner = HomebrewFormulaCommandRunner(fixture: latestFixture)
    let latestResult = await HomebrewFormulaUpdateOperation.prepare(
        definition: latestDefinition,
        diagnostic: latestFixture.diagnostic(keg: "1.0.0"),
        environment: latestFixture.environment,
        currentDirectory: latestFixture.root.path,
        runner: latestRunner,
        operationRootBaseURL: latestFixture.root
    )
    guard case .unavailable(let latestReason) = latestResult else {
        Issue.record("an unsupported stable grammar must refuse Update")
        return
    }
    #expect(latestReason == .unsupportedVersion)
}

// MARK: - Pins, disabled, deprecated

@Test func pinnedFormulaRefusesBeforeScratchOrLaunch() async throws {
    let fixture = try HomebrewFormulaFixture("update-pinned", pinned: true)
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUpdate])
    let runner = HomebrewFormulaCommandRunner(fixture: fixture)
    let operationBase = fixture.root.appendingPathComponent("operation-base", isDirectory: true)
    try FileManager.default.createDirectory(at: operationBase, withIntermediateDirectories: true)

    let refused = await HomebrewFormulaUpdateOperation.prepare(
        definition: definition,
        diagnostic: fixture.diagnostic(keg: "1.0.0"),
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: runner,
        operationRootBaseURL: operationBase
    )
    guard case .unavailable(let reason) = refused else {
        Issue.record("a pinned formula must refuse preparation")
        return
    }
    #expect(reason == .pinned)
    #expect(reason.message.contains("never unpins"))
    #expect(try homebrewScratchIsEmpty(operationBase))
    #expect(!runner.invocations.contains { $0.arguments.first == "upgrade" })
}

@Test func pinCrossCheckDisagreementFailsClosed() async throws {
    let infoPinnedFixture = try HomebrewFormulaFixture(
        "update-pin-info-only", pinned: true
    )
    defer { try? FileManager.default.removeItem(at: infoPinnedFixture.root) }
    infoPinnedFixture.state.pinnedNamesOverride = []
    let infoPinnedDefinition = try infoPinnedFixture.definition(
        acceptedOperations: [.homebrewFormulaUpdate]
    )
    let infoPinnedRunner = HomebrewFormulaCommandRunner(fixture: infoPinnedFixture)
    let infoPinned = await HomebrewFormulaUpdateOperation.prepare(
        definition: infoPinnedDefinition,
        diagnostic: infoPinnedFixture.diagnostic(keg: "1.0.0"),
        environment: infoPinnedFixture.environment,
        currentDirectory: infoPinnedFixture.root.path,
        runner: infoPinnedRunner,
        operationRootBaseURL: infoPinnedFixture.root
    )
    guard case .unavailable(let infoPinnedReason) = infoPinned else {
        Issue.record("info.pinned without a list match must fail closed")
        return
    }
    #expect(infoPinnedReason == .identityUnverified)

    let listPinnedFixture = try HomebrewFormulaFixture(
        "update-pin-list-only", pinned: false
    )
    defer { try? FileManager.default.removeItem(at: listPinnedFixture.root) }
    listPinnedFixture.state.pinnedNamesOverride = ["m13tool"]
    let listPinnedDefinition = try listPinnedFixture.definition(
        acceptedOperations: [.homebrewFormulaUpdate]
    )
    let listPinnedRunner = HomebrewFormulaCommandRunner(fixture: listPinnedFixture)
    let listPinned = await HomebrewFormulaUpdateOperation.prepare(
        definition: listPinnedDefinition,
        diagnostic: listPinnedFixture.diagnostic(keg: "1.0.0"),
        environment: listPinnedFixture.environment,
        currentDirectory: listPinnedFixture.root.path,
        runner: listPinnedRunner,
        operationRootBaseURL: listPinnedFixture.root
    )
    guard case .unavailable(let listPinnedReason) = listPinned else {
        Issue.record("a pinned list entry without info.pinned must fail closed")
        return
    }
    #expect(listPinnedReason == .identityUnverified)
}

@Test func pinAppearingAfterThePreviewRefusesBeforeLaunch() async throws {
    let fixture = try HomebrewFormulaFixture("update-pin-late")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUpdate])
    let updateRunner = HomebrewFormulaCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner()
    let before = fixture.diagnostic(keg: "1.0.0")
    let preparation = try await preparedUpdate(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    fixture.state.pinned = true

    let outcome = await HomebrewFormulaUpdateOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (before, fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    expectRefusedUpdate(outcome, runner: mutationRunner, messageContains: "now pinned")
}

@Test func disabledFormulaRefusesWithABoundedDisableReason() async throws {
    let longReason = String(repeating: "x", count: 300)
    let fixture = try HomebrewFormulaFixture("update-disabled", disabled: true)
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    fixture.state.disableReason = longReason
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUpdate])
    let runner = HomebrewFormulaCommandRunner(fixture: fixture)
    let refused = await HomebrewFormulaUpdateOperation.prepare(
        definition: definition,
        diagnostic: fixture.diagnostic(keg: "1.0.0"),
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: runner,
        operationRootBaseURL: fixture.root
    )
    guard case .unavailable(let reason) = refused else {
        Issue.record("a disabled formula must refuse Update")
        return
    }
    let bounded = String(repeating: "x", count: 200)
    #expect(reason == .formulaDisabled(disableReason: bounded))
    #expect(reason.message.contains(bounded))
    #expect(!reason.message.contains(String(repeating: "x", count: 201)))
}

@Test func deprecatedFormulaUpdateIsPermittedAndDisclosed() async throws {
    let fixture = try HomebrewFormulaFixture(
        "update-deprecated", deprecated: true, disabled: false
    )
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    fixture.state.deprecationDate = "2026-01-02"
    fixture.state.deprecationReason = "renamed upstream"
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUpdate])
    let runner = HomebrewFormulaCommandRunner(fixture: fixture)
    let preparation = try await preparedUpdate(
        fixture: fixture, definition: definition, diagnostic: fixture.diagnostic(keg: "1.0.0"),
        runner: runner
    )
    #expect(preparation.preview.deprecated)
    let disclosure = try #require(preparation.preview.deprecationDisclosure)
    #expect(disclosure.contains("deprecated"))
    #expect(disclosure.contains("2026-01-02"))
    #expect(disclosure.contains("renamed upstream"))
    #expect(disclosure.contains("Update remains available"))
}

// MARK: - Stale facts

@Test func changedObservedTargetInvalidatesThePreviewByExactMessage() async throws {
    let fixture = try HomebrewFormulaFixture("update-stale-target")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUpdate])
    let updateRunner = HomebrewFormulaCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner()
    let before = fixture.diagnostic(keg: "1.0.0")
    let preparation = try await preparedUpdate(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    fixture.state.stable = "3.0.0"

    let outcome = await HomebrewFormulaUpdateOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (before, fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    expectRefusedUpdate(outcome, runner: mutationRunner)
    #expect(outcome.message == "Homebrew's known version for this package changed; a new preview is required.")
}

@Test func staleFormulaManagerExecutableRefusesBeforeLaunch() async throws {
    let fixture = try HomebrewFormulaFixture("update-stale-manager")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUpdate])
    let updateRunner = HomebrewFormulaCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner()
    let before = fixture.diagnostic(keg: "1.0.0")
    let preparation = try await preparedUpdate(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    try fixture.rewriteManager()

    let outcome = await HomebrewFormulaUpdateOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (before, fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    expectRefusedUpdate(outcome, runner: mutationRunner)
}

@Test func staleCellarIdentityRefusesBeforeLaunch() async throws {
    let fixture = try HomebrewFormulaFixture("update-stale-cellar")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUpdate])
    let updateRunner = HomebrewFormulaCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner()
    let before = fixture.diagnostic(keg: "1.0.0")
    let preparation = try await preparedUpdate(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    try fixture.replaceCellarIdentity()

    let outcome = await HomebrewFormulaUpdateOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (before, fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    expectRefusedUpdate(outcome, runner: mutationRunner)
}

@Test func staleKegIdentityRefusesBeforeLaunch() async throws {
    let fixture = try HomebrewFormulaFixture("update-stale-keg")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUpdate])
    let updateRunner = HomebrewFormulaCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner()
    let before = fixture.diagnostic(keg: "1.0.0")
    let preparation = try await preparedUpdate(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    try fixture.removeKeg("1.0.0")
    try fixture.createKeg("1.0.0")
    try fixture.linkEntry(to: "1.0.0")

    let outcome = await HomebrewFormulaUpdateOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (before, fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    expectRefusedUpdate(outcome, runner: mutationRunner)
}

@Test func staleFormulaSelectionRefusesBeforeLaunch() async throws {
    let fixture = try HomebrewFormulaFixture("update-stale-selection")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUpdate])
    let updateRunner = HomebrewFormulaCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner()
    let before = fixture.diagnostic(keg: "1.0.0")
    let preparation = try await preparedUpdate(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    try fixture.createKeg("1.5.0")
    fixture.state.kegs = ["1.0.0", "1.5.0"]
    fixture.state.selectedKeg = "1.5.0"
    try fixture.linkEntry(to: "1.5.0")

    let outcome = await HomebrewFormulaUpdateOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (before, fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    expectRefusedUpdate(outcome, runner: mutationRunner)
}

@Test func staleInstalledKegListRefusesBeforeLaunch() async throws {
    let fixture = try HomebrewFormulaFixture("update-stale-kegs")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUpdate])
    let updateRunner = HomebrewFormulaCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner()
    let before = fixture.diagnostic(keg: "1.0.0")
    let preparation = try await preparedUpdate(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    try fixture.createKeg("0.5.0")
    fixture.state.kegs = ["0.5.0", "1.0.0"]

    let outcome = await HomebrewFormulaUpdateOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (before, fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    expectRefusedUpdate(outcome, runner: mutationRunner)
}

@Test func changedEnvironmentAndReplacedOperationRootRefuseBeforeLaunch() async throws {
    let fixture = try HomebrewFormulaFixture("update-stale-context")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUpdate])
    let updateRunner = HomebrewFormulaCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner()
    let before = fixture.diagnostic(keg: "1.0.0")

    let environmentPreparation = try await preparedUpdate(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    let changedEnvironment = ShellEnvironment(
        shellPath: fixture.environment.shellPath,
        pathEntries: fixture.environment.pathEntries,
        pathJoined: fixture.environment.pathJoined,
        raw: fixture.environment.raw.merging(["HOME": "/other/home"]) { _, new in new },
        isDegraded: false
    )
    let environmentOutcome = await HomebrewFormulaUpdateOperation.execute(
        confirmed: environmentPreparation,
        environment: changedEnvironment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (before, changedEnvironment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    expectRefusedUpdate(
        environmentOutcome, runner: mutationRunner,
        messageContains: "captured environment changed"
    )

    let rootPreparation = try await preparedUpdate(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    let root = rootPreparation.preview.workingDirectory
    try FileManager.default.removeItem(atPath: root)
    try FileManager.default.createDirectory(
        atPath: root, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
    )
    let rootOutcome = await HomebrewFormulaUpdateOperation.execute(
        confirmed: rootPreparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (before, fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    expectRefusedUpdate(rootOutcome, runner: mutationRunner)
}

// MARK: - Exit zero, interruption and reconciliation

@Test func exitZeroWithoutAChangedSelectedKegIsUncertain() async throws {
    let fixture = try HomebrewFormulaFixture("update-no-change")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUpdate])
    let updateRunner = HomebrewFormulaCommandRunner(fixture: fixture)
    let before = fixture.diagnostic(keg: "1.0.0")
    let mutationRunner = HomebrewScriptedMutationRunner(
        result: OperationCommandResult(
            stdout: Data("Warning: m13tool already installed\n".utf8),
            stderr: Data(), stdoutTruncated: false, stderrTruncated: false,
            exitStatus: 0, processStarted: true,
            timedOut: false, cancelled: false, cleanupWarning: false
        )
    )
    let preparation = try await preparedUpdate(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    let outcome = await HomebrewFormulaUpdateOperation.execute(
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
    #expect(outcome.stdoutText.contains("already installed"))
    let delta = try #require(outcome.reconciliation)
    #expect(!delta.versionMatchesTarget)
    #expect(!delta.previousKegReplaced)
    #expect(delta.afterSelectedKegVersion == "1.0.0")
    #expect(delta.observationFailed == false)
}

@Test func nonzeroExitIsAnHonestFailureWithTheMeasuredDelta() async throws {
    let fixture = try HomebrewFormulaFixture("update-nonzero")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUpdate])
    let updateRunner = HomebrewFormulaCommandRunner(fixture: fixture)
    let before = fixture.diagnostic(keg: "1.0.0")
    let mutationRunner = HomebrewScriptedMutationRunner(
        result: OperationCommandResult(
            stdout: Data("out\n".utf8), stderr: Data("Error: pinned\n".utf8),
            stdoutTruncated: false, stderrTruncated: false,
            exitStatus: 1, processStarted: true,
            timedOut: false, cancelled: false, cleanupWarning: false
        )
    )
    let preparation = try await preparedUpdate(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    let outcome = await HomebrewFormulaUpdateOperation.execute(
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
    #expect(outcome.stderrText == "Error: pinned\n")
    #expect(outcome.reconciliation != nil)
    #expect(mutationRunner.invocations.count == 1)
}

@Test func missingObservedExitStatusIsUncertainForFormulaUpdate() async throws {
    let fixture = try HomebrewFormulaFixture("update-no-exit")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUpdate])
    let updateRunner = HomebrewFormulaCommandRunner(fixture: fixture)
    let before = fixture.diagnostic(keg: "1.0.0")
    let mutationRunner = HomebrewScriptedMutationRunner(
        result: OperationCommandResult(
            stdout: Data("observed\n".utf8), stderr: Data("diagnostic\n".utf8),
            stdoutTruncated: false, stderrTruncated: false,
            exitStatus: nil, processStarted: true,
            timedOut: false, cancelled: false, cleanupWarning: false
        )
    )
    let preparation = try await preparedUpdate(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    let outcome = await HomebrewFormulaUpdateOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (before, fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    #expect(outcome.state == .uncertain)
    #expect(outcome.exitStatus == nil)
    #expect(outcome.stdoutText == "observed\n")
    #expect(outcome.stderrText == "diagnostic\n")
}

@Test func postLaunchCancellationWithoutReconciliationIsUncertain() async throws {
    let fixture = try HomebrewFormulaFixture("update-cancelled-no-reconcile")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUpdate])
    let updateRunner = HomebrewFormulaCommandRunner(fixture: fixture)
    let before = fixture.diagnostic(keg: "1.0.0")
    let mutationRunner = HomebrewScriptedMutationRunner(
        result: OperationCommandResult(
            stdout: Data(), stderr: Data(),
            stdoutTruncated: false, stderrTruncated: false,
            exitStatus: nil, processStarted: true,
            timedOut: false, cancelled: true, cleanupWarning: false
        )
    )
    let preparation = try await preparedUpdate(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    let outcome = await HomebrewFormulaUpdateOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in nil },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    #expect(outcome.state == .uncertain)
    #expect(outcome.processStarted)
    #expect(outcome.reconciliation == nil)
    #expect(outcome.message?.contains("could not be confirmed") == true)
}

@Test func cancellingAfterSpawnReportsInterruptedAndReconcilesWithoutAnOrphan() async throws {
    let fixture = try HomebrewFormulaFixture("update-interrupted")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUpdate])
    let updateRunner = HomebrewFormulaCommandRunner(fixture: fixture)
    let pidFile = fixture.root.appendingPathComponent("mutation-pid")
    let newKeg = fixture.kegDirectory("2.0.0")
    let newTarget = newKeg.appendingPathComponent("bin/\(fixture.executableName)")
    try writeHomebrewExecutable(
        fixture.brew,
        """
        #!/bin/sh
        if [ "$1" = "upgrade" ]; then
          /bin/mkdir -p '\(newKeg.path)/bin'
          /bin/cp '\(fixture.expectedTarget("1.0.0"))' '\(newTarget.path)'
          /bin/ln -sfn '\(fixture.expectedTarget("2.0.0"))' '\(fixture.entry.path)'
          printf '%s' "$$" > '\(pidFile.path)'
          exec /bin/sleep 30
        fi
        exit 9
        """
    )
    let before = fixture.diagnostic(keg: "1.0.0")
    let preparation = try await preparedUpdate(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    let task = Task {
        await HomebrewFormulaUpdateOperation.execute(
            confirmed: preparation,
            environment: fixture.environment,
            scan: { _, _, _ in before },
            reconcileAfterLaunch: { _ in
                fixture.state.kegs = ["1.0.0", "2.0.0"]
                fixture.state.selectedKeg = "2.0.0"
                return (fixture.diagnostic(keg: "2.0.0", version: "2.0.0"), fixture.environment)
            },
            updateRunner: updateRunner,
            operationRunner: ProcessOperationCommandRunner(),
            gate: OperationExecutionGate()
        )
    }
    #expect(waitForHomebrewFile(pidFile))
    let pid = try #require(pid_t(try String(contentsOf: pidFile, encoding: .utf8)))
    task.cancel()
    let outcome = await task.value
    #expect(outcome.state == .interrupted)
    #expect(outcome.processStarted)
    #expect(outcome.reconciliation?.versionMatchesTarget == true)
    #expect(outcome.reconciliation?.previousKegReplaced == true)
    #expect(waitForHomebrewProcessGone(pid))
    #expect(!FileManager.default.fileExists(atPath: preparation.preview.workingDirectory))
}

@Test func postLaunchObservationFailureIsNeverSuccess() async throws {
    let fixture = try HomebrewFormulaFixture("update-observation-failure")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUpdate])
    let updateRunner = HomebrewFormulaCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner(onLaunch: {
        try? fixture.createKeg("2.0.0")
        try? fixture.linkEntry(to: "2.0.0")
        fixture.state.kegs = ["1.0.0", "2.0.0"]
        fixture.state.selectedKeg = "2.0.0"
    })
    let before = fixture.diagnostic(keg: "1.0.0")
    let preparation = try await preparedUpdate(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    let outcome = await HomebrewFormulaUpdateOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in
            fixture.state.infoFailure = true
            return (fixture.diagnostic(keg: "2.0.0", version: "2.0.0"), fixture.environment)
        },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    #expect(outcome.state == .uncertain)
    #expect(outcome.processStarted)
    #expect(outcome.exitStatus == 0)
    let delta = try #require(outcome.reconciliation)
    #expect(delta.observationFailed)
    #expect(delta.versionMatchesTarget)
}

// MARK: - Argv construction

@Test func literalArgvIsOneTargetAndForbidsEveryWideningToken() {
    let update = HomebrewFormulaUpdateOperation.updateArguments(fullName: "m13tool")
    #expect(update == ["upgrade", "--formula", "--yes", "m13tool"])
    #expect(update.filter { !$0.hasPrefix("-") && $0 != "upgrade" }.count == 1)
    expectNoForbiddenMutationTokens(update)

    let tappedUpdate = HomebrewFormulaUpdateOperation.updateArguments(
        fullName: "m13test/homebrew-test/m13tool"
    )
    #expect(tappedUpdate == ["upgrade", "--formula", "--yes", "m13test/homebrew-test/m13tool"])
    #expect(tappedUpdate.filter { !$0.hasPrefix("-") && $0 != "upgrade" }.count == 1)
    expectNoForbiddenMutationTokens(tappedUpdate)

    let uninstall = HomebrewFormulaUninstallOperation.uninstallArguments(fullName: "m13tool")
    #expect(uninstall == ["uninstall", "--formula", "m13tool"])
    #expect(!uninstall.contains("--yes"))
    #expect(uninstall.filter { !$0.hasPrefix("-") && $0 != "uninstall" }.count == 1)
    expectNoForbiddenMutationTokens(uninstall)
}

@Test func proofIdentityMustBeAManagerReturnedHomebrewName() {
    #expect(HomebrewFormulaIdentity.isSafeProofName(
        fullName: "m13tool", formulaName: "m13tool"
    ))
    #expect(HomebrewFormulaIdentity.isSafeProofName(
        fullName: "m13test/homebrew-test/m13tool", formulaName: "m13tool"
    ))
    #expect(!HomebrewFormulaIdentity.isSafeProofName(fullName: "", formulaName: "m13tool"))
    #expect(!HomebrewFormulaIdentity.isSafeProofName(fullName: "--force", formulaName: "m13tool"))
    #expect(!HomebrewFormulaIdentity.isSafeProofName(
        fullName: "other/tap/different", formulaName: "m13tool"
    ))
    #expect(!HomebrewFormulaIdentity.isSafeProofName(
        fullName: "m13tool --force", formulaName: "m13tool"
    ))
    #expect(!HomebrewFormulaIdentity.isSafeProofName(
        fullName: "m13test/homebrew-test/other", formulaName: "m13tool"
    ))
}

// MARK: - Manager prefix (R1 correction 1)

@Test func preparationBindsTheActualManagerPrefixSeparatelyFromTheCellar() async throws {
    let fixture = try HomebrewFormulaFixture("update-prefix")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUpdate])
    let runner = HomebrewFormulaCommandRunner(fixture: fixture)
    let preparation = try await preparedUpdate(
        fixture: fixture, definition: definition, diagnostic: fixture.diagnostic(keg: "1.0.0"),
        runner: runner
    )
    #expect(preparation.preview.prefix == fixture.prefix.path)
    #expect(preparation.preview.cellar == fixture.cellar.path)
    #expect(preparation.preview.prefix != preparation.preview.cellar)
    let prefixQueries = runner.invocations.filter { $0.arguments == ["--prefix"] }
    #expect(prefixQueries.count == 1)
    #expect(prefixQueries.first?.executablePath == fixture.brew.path)
    #expect(HomebrewFormulaUpdateOperation.cancel(preparation))
}

@Test func prefixAliasIsNormalizedBeforePreviewAndBinding() async throws {
    let fixture = try HomebrewFormulaFixture("update-prefix-alias")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let alias = fixture.root.appendingPathComponent("prefix-alias", isDirectory: true)
    try FileManager.default.createSymbolicLink(
        atPath: alias.path, withDestinationPath: fixture.prefix.path
    )
    fixture.state.prefixOverride = alias.path
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUpdate])
    let runner = HomebrewFormulaCommandRunner(fixture: fixture)
    let preparation = try await preparedUpdate(
        fixture: fixture, definition: definition, diagnostic: fixture.diagnostic(keg: "1.0.0"),
        runner: runner
    )
    // The alias spelling is normalized to the bound directory's canonical path, and the Cellar is
    // still a distinct fact.
    #expect(preparation.preview.prefix == fixture.prefix.path)
    #expect(preparation.preview.cellar == fixture.cellar.path)
    #expect(HomebrewFormulaUpdateOperation.cancel(preparation))
}

@Test func missingOrInconsistentPrefixRefusesBeforeScratchOrProcess() async throws {
    let missing = try HomebrewFormulaFixture("update-prefix-missing")
    defer { try? FileManager.default.removeItem(at: missing.root) }
    let missingDefinition = try missing.definition(acceptedOperations: [.homebrewFormulaUpdate])
    let missingRunner = HomebrewFormulaCommandRunner(fixture: missing)
    missing.state.prefixOverride = missing.root.appendingPathComponent("absent-prefix").path
    let missingBase = missing.root.appendingPathComponent("operation-base", isDirectory: true)
    try FileManager.default.createDirectory(at: missingBase, withIntermediateDirectories: true)
    let missingResult = await HomebrewFormulaUpdateOperation.prepare(
        definition: missingDefinition,
        diagnostic: missing.diagnostic(keg: "1.0.0"),
        environment: missing.environment,
        currentDirectory: missing.root.path,
        runner: missingRunner,
        operationRootBaseURL: missingBase
    )
    guard case .unavailable(let missingReason) = missingResult else {
        Issue.record("a missing manager prefix must refuse Update")
        return
    }
    #expect(missingReason == .managerPrefixUnverified)
    #expect(try homebrewScratchIsEmpty(missingBase))
    #expect(!missingRunner.invocations.contains { $0.arguments.first == "upgrade" })

    let inconsistent = try HomebrewFormulaFixture("update-prefix-inconsistent")
    defer { try? FileManager.default.removeItem(at: inconsistent.root) }
    let inconsistentDefinition = try inconsistent.definition(
        acceptedOperations: [.homebrewFormulaUpdate]
    )
    let inconsistentRunner = HomebrewFormulaCommandRunner(fixture: inconsistent)
    // An existing directory that does not contain the observed Cellar.
    inconsistent.state.prefixOverride = inconsistent.pathDirectory.path
    let inconsistentBase = inconsistent.root.appendingPathComponent(
        "operation-base", isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: inconsistentBase, withIntermediateDirectories: true
    )
    let inconsistentResult = await HomebrewFormulaUpdateOperation.prepare(
        definition: inconsistentDefinition,
        diagnostic: inconsistent.diagnostic(keg: "1.0.0"),
        environment: inconsistent.environment,
        currentDirectory: inconsistent.root.path,
        runner: inconsistentRunner,
        operationRootBaseURL: inconsistentBase
    )
    guard case .unavailable(let inconsistentReason) = inconsistentResult else {
        Issue.record("an inconsistent manager prefix must refuse Update")
        return
    }
    #expect(inconsistentReason == .managerPrefixUnverified)
    #expect(try homebrewScratchIsEmpty(inconsistentBase))
    #expect(!inconsistentRunner.invocations.contains { $0.arguments.first == "upgrade" })
}

@Test func changedManagerPrefixAnswerAfterPreviewRefusesBeforeLaunch() async throws {
    let fixture = try HomebrewFormulaFixture("update-prefix-changed")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUpdate])
    let updateRunner = HomebrewFormulaCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner()
    let before = fixture.diagnostic(keg: "1.0.0")
    let preparation = try await preparedUpdate(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    // A different existing ancestor that still contains the Cellar: the prefix binding, not the
    // consistency check, must invalidate the preview.
    fixture.state.prefixOverride = fixture.root.path
    let outcome = await HomebrewFormulaUpdateOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (before, fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    expectRefusedUpdate(
        outcome, runner: mutationRunner,
        messageContains: "bound formula identity or manager fact changed"
    )
}

@Test func replacedPrefixIdentityRefusesBeforeLaunch() async throws {
    let fixture = try HomebrewFormulaFixture("update-prefix-replaced")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUpdate])
    let updateRunner = HomebrewFormulaCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner()
    let before = fixture.diagnostic(keg: "1.0.0")
    let preparation = try await preparedUpdate(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    try fixture.replacePrefixIdentity()
    let outcome = await HomebrewFormulaUpdateOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (before, fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    expectRefusedUpdate(outcome, runner: mutationRunner)
}

@Test func prefixIdentityChangeImmediatelyBeforeUpdateLaunchRefuses() async throws {
    let fixture = try HomebrewFormulaFixture("update-prefix-identity")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewFormulaUpdate])
    let updateRunner = HomebrewFormulaCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner()
    let before = fixture.diagnostic(keg: "1.0.0")
    let preparation = try await preparedUpdate(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    // Only the prefix directory's identity changes; the Cellar, keg and selected executable do not.
    try fixture.changePrefixMode(to: 0o750)
    let outcome = await HomebrewFormulaUpdateOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (before, fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    expectRefusedUpdate(outcome, runner: mutationRunner)
}
