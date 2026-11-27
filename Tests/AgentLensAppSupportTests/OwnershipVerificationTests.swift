// OwnershipVerificationTests — M9-B app boundary and main-actor lifecycle.
//
// All manager answers are scripted; fixtures are synthetic Homebrew prefixes in scratch. These tests
// cover: the service passing session environment/runner/clock/currentDirectory into Core, off-main
// bounded work, the truthful verifying/cancelling phases, selection-change and explicit-cancel
// discard, fresh/failed rescans clearing proof, update application preserving proof, and neutral
// standalone/not-installed verification.

import AgentLensCore
import CryptoKit
import Foundation
import Testing
@testable import AgentLensAppSupport

// MARK: Registry and runner fixtures

private func ownershipRegistryJSON(
    _ rows: [(id: String, name: String, executable: String, packages: [(PackageManager, String)])]
) -> Data {
    let detectors = rows.map { row -> String in
        let packages = row.packages.map {
            "{\"manager\":\"\($0.0.rawValue)\",\"name\":\"\($0.1)\"}"
        }.joined(separator: ",")
        return """
        {"id":"\(row.id)","displayName":"\(row.name)","executableName":"\(row.executable)",\
        "category":"aiAgent","packages":[\(packages)],\
        "versionQuery":{"arguments":["--version"],"stream":"stdout","line":"first"}}
        """
    }.joined(separator: ",")
    return Data("{\"schemaVersion\":2,\"detectors\":[\(detectors)]}".utf8)
}

private func ownershipBrewHandler(
    cellar: String,
    formula: String,
    keg: String,
    executableTarget: String
) -> @Sendable (String, [String]) -> CommandOutcome {
    { _, arguments in
        if arguments == ["--cellar"] {
            return .success(Data((cellar + "\n").utf8))
        }
        if arguments.count == 4, arguments[0] == "info", arguments[1] == "--json=v2",
           arguments[2] == "--formula" {
            return .success(
                infoJSON([(name: formula, stable: "9.9.9", revision: 1, installed: [keg])])
            )
        }
        if arguments.count == 4, arguments[0] == "list", arguments[1] == "--verbose",
           arguments[2] == "--formula" {
            return .success(Data("\(executableTarget)\n".utf8))
        }
        return .failure(.spawnFailure)
    }
}

private struct OwnershipAppFixture {
    let brew: AppBrewFixture
    let keg: String
    let target: String

    init(_ label: String) throws {
        brew = try makeAppBrewFixture(label)
        keg = "1.0.0"
        target = try brew.installKeg(formula: "codex", keg: keg, version: "1.0.0")
    }

    var handler: @Sendable (String, [String]) -> CommandOutcome {
        ownershipBrewHandler(
            cellar: brew.cellar, formula: "codex", keg: keg, executableTarget: target
        )
    }
}

private func ownershipViewModelService(
    _ fixture: OwnershipAppFixture,
    runner: UpdateCommandRunner,
    clock: @escaping @Sendable () -> Date = fixedClock(),
    registryData: Data? = nil
) -> InventoryService {
    makeService(
        registryData: registryData ?? ownershipRegistryJSON([
            (
                id: "codex-id",
                name: "Codex",
                executable: "codex",
                packages: [(.homebrewFormula, "codex")]
            )
        ]),
        pathEntries: [fixture.brew.binDirectory],
        cacheURL: fixture.brew.cacheURL("ownership"),
        currentDirectory: fixture.brew.root.path,
        runner: runner,
        clock: clock
    )
}

// MARK: Service boundary

@MainActor
@Test func serviceVerifiesOwnershipWithTheSessionEnvironmentRunnerAndFixedClock() async throws {
    let fixture = try OwnershipAppFixture("ownership-service")
    defer { try? FileManager.default.removeItem(at: fixture.brew.root) }
    let observedAt = Date(timeIntervalSince1970: 1_800_000_777)
    let runner = RecordingManagerRunner(handler: fixture.handler)
    let service = ownershipViewModelService(fixture, runner: runner, clock: fixedClock(observedAt))

    let snapshot = try await service.localSnapshot()
    let entry = try #require(snapshot.entries.first)
    #expect(entry.ownership == nil)
    let result = await service.verifyingOwnership(of: entry)

    let installation = try #require(result.verifiedInstallation)
    #expect(result.registryID == "codex-id")
    #expect(result.observedAt == observedAt)
    #expect(installation.manager == .homebrewFormula)
    #expect(installation.packageName == "codex")
    #expect(installation.managerRoot == fixture.brew.cellar)
    #expect(installation.installationRoot == fixture.brew.cellar + "/codex/\(fixture.keg)")
    #expect(installation.selection.canonicalTarget == fixture.target)
    #expect(runner.invocationCount == 3)
    #expect(runner.arguments.first == ["--cellar"])
    #expect(runner.firstEnvironment?["HOMEBREW_NO_AUTO_UPDATE"] == "1")
    #expect(runner.firstEnvironment?["HOMEBREW_NO_ANALYTICS"] == "1")
    #expect(!FileManager.default.fileExists(atPath: fixture.brew.cacheURL("ownership").path))
}

@MainActor
@Test func applyingUpdatesPreservesOwnershipAndAFreshLocalSnapshotDoesNotInventIt() async throws {
    let fixture = try OwnershipAppFixture("ownership-preserve")
    defer { try? FileManager.default.removeItem(at: fixture.brew.root) }
    let runner = RecordingManagerRunner(handler: fixture.handler)
    let service = ownershipViewModelService(fixture, runner: runner)

    let local = try await service.localSnapshot()
    let entry = try #require(local.entries.first)
    let result = await service.verifyingOwnership(of: entry)
    let withOwnership = InventorySnapshot(
        entries: [
            InventoryEntry(
                definition: entry.definition,
                diagnostic: entry.diagnostic,
                update: entry.update,
                ownership: result
            )
        ],
        isDegradedEnvironment: false
    )

    let applied = await service.applyingUpdates(to: withOwnership, mode: .offline)
    #expect(applied.entries.first?.ownership == result)
    #expect(applied.entries.first?.registryID == "codex-id")

    let fresh = try await service.localSnapshot()
    #expect(fresh.entries.first?.ownership == nil)
}

// MARK: Verifying phase, off-main execution, and publication

@MainActor
@Test func verifyPublishesVerifiedWithoutBlockingTheMainActorOrStayingBusy() async throws {
    let fixture = try OwnershipAppFixture("ownership-verified")
    defer { try? FileManager.default.removeItem(at: fixture.brew.root) }
    let runner = ControlledManagerRunner(script: fixture.handler)
    let viewModel = InventoryViewModel(
        service: ownershipViewModelService(fixture, runner: runner)
    )
    await viewModel.launch()
    #expect(viewModel.phase == .ready)
    #expect(viewModel.selectedEntry?.ownership == nil)

    runner.armGate()
    let verification = Task { await viewModel.verifySelectedInstallation() }
    try await runner.waitForGatedCall()

    #expect(viewModel.phase == .verifyingOwnership)
    #expect(viewModel.isBusy)
    #expect(!viewModel.isCancelling)
    // The gated manager command runs off the main actor: a main-actor task still gets to run.
    let heartbeat = MainActorHeartbeat()
    try await awaitMainActorHeartbeat(heartbeat)
    #expect(heartbeat.beats == 1)

    await runner.releaseGate()
    await verification.value

    #expect(viewModel.phase == .ready)
    #expect(!viewModel.isBusy)
    #expect(!viewModel.isCancelling)
    let entry = try #require(viewModel.selectedEntry)
    let installation = try #require(entry.ownership?.verifiedInstallation)
    #expect(installation.manager == .homebrewFormula)
    #expect(installation.packageName == "codex")
    #expect(installation.selection.canonicalTarget == fixture.target)
    #expect(runner.invocations == 3)
}

// MARK: Stale selection and cancellation

@MainActor
@Test func selectionChangeWhileVerifyingCancelsAndNeverAttachesProofToAnotherTool() async throws {
    let fixture = try OwnershipAppFixture("ownership-selection")
    defer { try? FileManager.default.removeItem(at: fixture.brew.root) }
    let runner = ControlledManagerRunner(script: fixture.handler)
    let registry = ownershipRegistryJSON([
        (
            id: "codex-id", name: "Codex", executable: "codex",
            packages: [(.homebrewFormula, "codex")]
        ),
        (id: "other-id", name: "Other", executable: "missing-other", packages: []),
    ])
    let viewModel = InventoryViewModel(
        service: ownershipViewModelService(fixture, runner: runner, registryData: registry)
    )
    await viewModel.launch()
    #expect(viewModel.selectedRegistryID == "codex-id")

    runner.armGate()
    let verification = Task { await viewModel.verifySelectedInstallation() }
    try await runner.waitForGatedCall()
    viewModel.select(registryID: "other-id")
    #expect(viewModel.isCancelling)

    await runner.releaseGate()
    await verification.value

    #expect(viewModel.phase == .ready)
    #expect(!viewModel.isBusy)
    #expect(!viewModel.isCancelling)
    #expect(viewModel.selectedRegistryID == "other-id")
    #expect(viewModel.entries.allSatisfy { $0.ownership == nil })
}

@MainActor
@Test func explicitCancelWaitsForBoundedCleanupAndPublishesNoProof() async throws {
    let fixture = try OwnershipAppFixture("ownership-cancel")
    defer { try? FileManager.default.removeItem(at: fixture.brew.root) }
    let runner = ControlledManagerRunner(script: fixture.handler)
    let viewModel = InventoryViewModel(
        service: ownershipViewModelService(fixture, runner: runner)
    )
    await viewModel.launch()

    runner.armGate()
    let verification = Task { await viewModel.verifySelectedInstallation() }
    try await runner.waitForGatedCall()
    let cancellation = Task { await viewModel.cancel() }
    for _ in 0..<10_000 where !viewModel.isCancelling {
        await Task.yield()
    }
    #expect(viewModel.phase == .verifyingOwnership)
    #expect(viewModel.isCancelling)

    await runner.releaseGate()
    await cancellation.value
    await verification.value

    #expect(viewModel.phase == .ready)
    #expect(!viewModel.isBusy)
    #expect(!viewModel.isCancelling)
    #expect(viewModel.selectedEntry?.ownership == nil)
    #expect(viewModel.entries.allSatisfy { $0.ownership == nil })
}

@MainActor
@Test func repeatedVerifyWhileBusyCoalescesIntoOnePipeline() async throws {
    let fixture = try OwnershipAppFixture("ownership-coalesce")
    defer { try? FileManager.default.removeItem(at: fixture.brew.root) }
    let runner = ControlledManagerRunner(script: fixture.handler)
    let viewModel = InventoryViewModel(
        service: ownershipViewModelService(fixture, runner: runner)
    )
    await viewModel.launch()

    runner.armGate()
    let first = Task { await viewModel.verifySelectedInstallation() }
    try await runner.waitForGatedCall()
    await viewModel.verifySelectedInstallation()
    #expect(runner.invocations == 1)
    await runner.releaseGate()
    await first.value

    #expect(viewModel.selectedEntry?.ownership?.verifiedInstallation?.packageName == "codex")
    #expect(runner.invocations == 3)
}

// MARK: Fresh and failed rescans clear old proof

@MainActor
@Test func freshAndFailedRescansClearOldOwnershipWhileRetainingLocalFacts() async throws {
    let fixture = try OwnershipAppFixture("ownership-rescan")
    defer { try? FileManager.default.removeItem(at: fixture.brew.root) }
    let data = ownershipRegistryJSON([
        (
            id: "codex-id", name: "Codex", executable: "codex",
            packages: [(.homebrewFormula, "codex")]
        )
    ])
    let loader = ScriptedRegistryLoader(payloads: [data, data])
    let runner = RecordingManagerRunner(handler: fixture.handler)
    let environmentSource = RecordingEnvironmentSource(
        resolveEnvironment: ShellEnvironment(
            shellPath: "/bin/zsh",
            pathEntries: [fixture.brew.binDirectory],
            pathJoined: fixture.brew.binDirectory,
            raw: ["PATH": fixture.brew.binDirectory],
            isDegraded: false
        )
    ).provider
    let service = InventoryService(
        environment: environmentSource,
        registry: { try loader.load() },
        scanner: { detector, environment, directory in
            PathDiagnosticsScanner.scan(
                detector: detector, environment: environment, currentDirectory: directory
            )
        },
        updateRunner: runner,
        updateCacheURL: fixture.brew.cacheURL("ownership-rescan"),
        currentDirectory: fixture.brew.root.path,
        clock: fixedClock()
    )
    let viewModel = InventoryViewModel(service: service)

    await viewModel.launch()
    await viewModel.verifySelectedInstallation()
    #expect(viewModel.selectedEntry?.ownership?.verifiedInstallation != nil)

    // A successful fresh rescan publishes new local facts with no ownership proof.
    await viewModel.rescan()
    #expect(viewModel.phase == .ready)
    #expect(viewModel.selectedEntry?.ownership == nil)
    #expect(viewModel.installedToolCount == 1)

    // Verify again, then a registry failure retains the local facts but clears the old proof.
    await viewModel.verifySelectedInstallation()
    #expect(viewModel.selectedEntry?.ownership?.verifiedInstallation != nil)
    await viewModel.rescan()
    #expect(viewModel.phase == .failed)
    #expect(viewModel.freshnessFailure?.registryError == .duplicateId("fixture"))
    let retained = try #require(viewModel.selectedEntry)
    #expect(retained.installState == .installedAndOnPath)
    #expect(retained.diagnostic.detectedTool.version == "1.0.0")
    #expect(retained.ownership == nil)
    #expect(!viewModel.isBusy)
}

// MARK: Neutral explicit verification

@MainActor
@Test func standaloneAndNotInstalledToolsStayNeutralWithoutManagerQueries() async throws {
    let root = try appSupportScratchRoot("ownership-standalone")
    defer { try? FileManager.default.removeItem(at: root) }
    let bin = root.appendingPathComponent("bin", isDirectory: true)
    try writeFixtureExecutable(bin.appendingPathComponent("grok"))
    let registry = ownershipRegistryJSON([
        (id: "grok-id", name: "Grok", executable: "grok", packages: []),
        (id: "missing-id", name: "Missing", executable: "missing-tool", packages: []),
    ])
    let runner = RecordingManagerRunner(handler: forbiddenManagerHandler())
    let viewModel = InventoryViewModel(
        service: makeService(
            registryData: registry,
            pathEntries: [bin.path],
            cacheURL: root.appendingPathComponent("cache.json"),
            currentDirectory: root.path,
            runner: runner
        )
    )
    await viewModel.launch()
    #expect(viewModel.selectedEntry?.registryID == "grok-id")

    await viewModel.verifySelectedInstallation()
    let standalone = try #require(viewModel.selectedEntry?.ownership)
    #expect(standalone.unknownReason == .unsupportedSource)
    #expect(viewModel.phase == .ready)
    #expect(runner.invocationCount == 0)

    viewModel.select(registryID: "missing-id")
    await viewModel.verifySelectedInstallation()
    #expect(viewModel.selectedEntry?.ownership == nil)
    #expect(viewModel.phase == .ready)
    #expect(runner.invocationCount == 0)
    #expect(!viewModel.isBusy)
}


// MARK: M14-B Python read-only presentation seam

private func m14bPipFixture(_ label: String) throws -> (root: URL, script: URL, venv: URL) {
    let root = try appSupportScratchRoot("m14b-pip-\(label)")
    let venv = root.appendingPathComponent("venv", isDirectory: true)
    let python = venv.appendingPathComponent("bin/python")
    try writeFixtureExecutable(python)
    let script = venv.appendingPathComponent("bin/aider")
    let scriptData = Data("#!/\(python.path)\nprint('aider')\n".utf8)
    try FileManager.default.createDirectory(
        at: script.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try scriptData.write(to: script)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    try Data("""
    home = /opt/homebrew/opt/python@3.15/bin
    include-system-site-packages = false
    version_info = 3.15.2

    """.utf8).write(to: venv.appendingPathComponent("pyvenv.cfg"))
    let distInfo = venv.appendingPathComponent(
        "lib/python3.15/site-packages/aider_chat-0.85.0.dist-info", isDirectory: true
    )
    try FileManager.default.createDirectory(at: distInfo, withIntermediateDirectories: true)
    let hash = Data(SHA256.hash(data: scriptData)).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    try Data("""
    ../../../bin/aider,sha256=\(hash),\(scriptData.count)
    aider_chat-0.85.0.dist-info/RECORD,,

    """.utf8).write(to: distInfo.appendingPathComponent("RECORD"))
    try Data("pip\n".utf8).write(to: distInfo.appendingPathComponent("INSTALLER"))
    try Data("""
    Metadata-Version: 2.1
    Name: aider-chat
    Version: 0.85.0
    Requires-Python: >=3.9

    """.utf8).write(to: distInfo.appendingPathComponent("METADATA"))
    return (root, script, venv)
}

@MainActor
@Test func pipOwnershipPublishesReadOnlyEnvironmentDiagnosticsWithoutMutation() async throws {
    let fixture = try m14bPipFixture("presentation")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let registry = ownershipRegistryJSON([
        (id: "aider-id", name: "Aider", executable: "aider",
         packages: [(.pip, "aider-chat")])
    ])
    let service = makeService(
        registryData: registry,
        pathEntries: [fixture.venv.appendingPathComponent("bin").path],
        cacheURL: fixture.root.appendingPathComponent("cache.json"),
        currentDirectory: fixture.root.path
    )
    let snapshot = try await service.localSnapshot()
    let entry = try #require(snapshot.entries.first)
    let result = await service.verifyingOwnership(of: entry)
    let installation = try #require(result.verifiedInstallation)
    #expect(installation.manager == .pip)
    #expect(installation.pythonEnvironment?.environmentKind == .virtualEnvironment)
    #expect(installation.pythonEnvironment?.interpreterVersion == "3.15.2")

    let withOwnership = InventoryEntry(
        definition: entry.definition,
        diagnostic: entry.diagnostic,
        update: entry.update,
        ownership: result
    )
    let presentation = ManagementPresentation(entry: withOwnership)
    #expect(presentation.update == .hidden)
    #expect(presentation.uninstall == .hidden)
    #expect(presentation.otherLimits.contains {
        $0.contains("read-only diagnostics")
    })

    let rendered = InstallationOwnershipRenderer.render(result)
    #expect(rendered.contains("manager: pip"))
    #expect(rendered.contains("environment type: Virtual environment (venv)"))
    #expect(rendered.contains("installer: pip"))
    #expect(rendered.contains("index provenance: Unknown"))
}
