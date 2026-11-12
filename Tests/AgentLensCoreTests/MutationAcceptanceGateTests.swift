import Foundation
import Testing
@testable import AgentLensCore

// M11-B fail-closed mutation acceptance gate.
//
// Eligibility is data: a detector definition must carry the matching accepted operation before a
// preparation may observe ownership, claim a scratch root, or launch a manager process. These
// tests exercise the refusal boundary directly with an injected counting runner — never a real
// package manager — and prove the gate is the first decision after cancellation.

private func gateScratchRoot(_ label: String) throws -> URL {
    let environment = ProcessInfo.processInfo.environment
    guard let basePath = [environment["AGENT_LENS_TEST_SCRATCH"], environment["TMPDIR"]]
        .compactMap({ $0 })
        .first(where: { !$0.isEmpty })
    else {
        throw NSError(domain: "MutationAcceptanceGateTests", code: 1)
    }
    let root = URL(fileURLWithPath: basePath, isDirectory: true)
        .appendingPathComponent("agentlens-m11b-gate-\(label)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root.resolvingSymlinksInPath()
}

/// Counts every manager invocation. Any call from a refused preparation is a test failure: the
/// gate must return before the first observation.
private final class GateCountingUpdateRunner: UpdateCommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var invocations: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func run(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval
    ) async -> CommandOutcome {
        note()
        return .failure(.spawnFailure)
    }

    private func note() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}

private func gateDefinition(
    acceptedOperations: [AcceptedOperation],
    id: String = "gate-tool",
    package: String = "gate-tool"
) throws -> DetectorDefinition {
    try DetectorDefinition(
        id: id,
        displayName: "Gate Tool",
        executableName: "gate-tool",
        extraSearchRoots: [],
        fixture: nil,
        category: .aiAgent,
        packages: [try DeclaredPackage(manager: .npm, name: package)],
        informationURL: nil,
        uninstallInstructionsURL: nil,
        versionQuery: .standard,
        acceptedOperations: acceptedOperations
    )
}

private func gateDefinitionCopy(
    of definition: DetectorDefinition,
    acceptedOperations: [AcceptedOperation]
) throws -> DetectorDefinition {
    try DetectorDefinition(
        id: definition.id,
        displayName: definition.displayName,
        executableName: definition.executableName,
        extraSearchRoots: definition.extraSearchRoots,
        fixture: definition.fixture,
        category: definition.category,
        packages: definition.packages,
        informationURL: definition.informationURL,
        uninstallInstructionsURL: definition.uninstallInstructionsURL,
        versionQuery: definition.versionQuery,
        acceptedOperations: acceptedOperations
    )
}

private func gateEnvironment(tmpdir: String? = nil) -> ShellEnvironment {
    var raw = ["PATH": "/usr/bin:/bin"]
    if let tmpdir { raw["TMPDIR"] = tmpdir }
    return ShellEnvironment(
        shellPath: "/bin/zsh",
        pathEntries: ["/usr/bin", "/bin"],
        pathJoined: "/usr/bin:/bin",
        raw: raw,
        isDegraded: false
    )
}

private func gateDiagnostic() -> ToolPathDiagnostic {
    let detected = DetectedTool(
        displayName: "Gate Tool",
        executableName: "gate-tool",
        state: .notInstalled,
        entryPath: nil,
        resolvedPath: nil,
        source: "–",
        version: nil
    )
    return ToolPathDiagnostic(
        detectedTool: detected,
        pathCandidates: [],
        firstLiveCandidate: nil,
        targetGroups: [],
        repeatedPathSlotCount: 0,
        sameTargetAliasCount: 0,
        selection: .notInstalled,
        shadowedInstallationCount: 0,
        installationVersions: []
    )
}

private func emptyDirectory(_ url: URL) throws -> Bool {
    try FileManager.default.contentsOfDirectory(atPath: url.path).isEmpty
}

@Test func unacceptedUpdateRefusesBeforeObservationOrScratchClaim() async throws {
    let root = try gateScratchRoot("update")
    defer { try? FileManager.default.removeItem(at: root) }
    let definition = try gateDefinition(acceptedOperations: [])
    let runner = GateCountingUpdateRunner()
    let operationBase = root.appendingPathComponent("operation-base", isDirectory: true)
    try FileManager.default.createDirectory(at: operationBase, withIntermediateDirectories: true)

    let result = await NpmUpdateOperation.prepare(
        definition: definition,
        diagnostic: gateDiagnostic(),
        environment: gateEnvironment(),
        currentDirectory: root.path,
        runner: runner,
        operationRootBaseURL: operationBase
    )

    guard case .unavailable(let reason) = result else {
        Issue.record("unaccepted update must refuse preparation")
        return
    }
    #expect(reason == .operationNotAccepted)
    #expect(reason.message == "Update is not yet accepted for this tool. Agent Lens detects it, but no managed update has been verified for it.")
    #expect(runner.invocations == 0)
    #expect(try emptyDirectory(operationBase))
}

@Test func unacceptedUninstallRefusesBeforeObservationOrScratchClaim() async throws {
    let root = try gateScratchRoot("uninstall")
    defer { try? FileManager.default.removeItem(at: root) }
    let definition = try gateDefinition(acceptedOperations: [])
    let runner = GateCountingUpdateRunner()
    let operationBase = root.appendingPathComponent("operation-base", isDirectory: true)
    try FileManager.default.createDirectory(at: operationBase, withIntermediateDirectories: true)

    let result = await NpmUninstallOperation.prepare(
        definition: definition,
        diagnostic: gateDiagnostic(),
        environment: gateEnvironment(),
        currentDirectory: root.path,
        runner: runner,
        operationRootBaseURL: operationBase
    )

    guard case .unavailable(let reason) = result else {
        Issue.record("unaccepted Uninstall must refuse preparation")
        return
    }
    #expect(reason == .operationNotAccepted)
    #expect(reason.message == "Uninstall is not yet accepted for this tool. Agent Lens detects it, but no managed uninstall has been verified for it.")
    #expect(runner.invocations == 0)
    #expect(try emptyDirectory(operationBase))
}

@Test func eachOperationRequiresItsOwnAcceptance() async throws {
    let root = try gateScratchRoot("per-operation")
    defer { try? FileManager.default.removeItem(at: root) }
    let runner = GateCountingUpdateRunner()
    let operationBase = root.appendingPathComponent("operation-base", isDirectory: true)
    try FileManager.default.createDirectory(at: operationBase, withIntermediateDirectories: true)

    let updateOnly = try gateDefinition(acceptedOperations: [.npmUpdate])
    let updateRefused = await NpmUninstallOperation.prepare(
        definition: updateOnly,
        diagnostic: gateDiagnostic(),
        environment: gateEnvironment(),
        currentDirectory: root.path,
        runner: runner,
        operationRootBaseURL: operationBase
    )
    guard case .unavailable(let uninstallReason) = updateRefused else {
        Issue.record("update-only acceptance must not authorize Uninstall")
        return
    }
    #expect(uninstallReason == .operationNotAccepted)

    let uninstallOnly = try gateDefinition(acceptedOperations: [.npmUninstall])
    let uninstallRefused = await NpmUpdateOperation.prepare(
        definition: uninstallOnly,
        diagnostic: gateDiagnostic(),
        environment: gateEnvironment(),
        currentDirectory: root.path,
        runner: runner,
        operationRootBaseURL: operationBase
    )
    guard case .unavailable(let updateReason) = uninstallRefused else {
        Issue.record("uninstall-only acceptance must not authorize Update")
        return
    }
    #expect(updateReason == .operationNotAccepted)

    #expect(runner.invocations == 0)
    #expect(try emptyDirectory(operationBase))
}

@Test func gateRunsBeforeScratchValidationForAnUnacceptedDefinition() async throws {
    let root = try gateScratchRoot("order")
    defer { try? FileManager.default.removeItem(at: root) }
    let definition = try gateDefinition(acceptedOperations: [])
    let runner = GateCountingUpdateRunner()

    // `/` is not a safe owned scratch base. An accepted definition would refuse it with
    // `.operationRootUnsafe`; an unaccepted one must refuse earlier and never inspect it.
    let result = await NpmUpdateOperation.prepare(
        definition: definition,
        diagnostic: gateDiagnostic(),
        environment: gateEnvironment(tmpdir: "/"),
        currentDirectory: root.path,
        runner: runner
    )

    guard case .unavailable(let reason) = result else {
        Issue.record("unaccepted update must refuse before scratch validation")
        return
    }
    #expect(reason == .operationNotAccepted)
    #expect(runner.invocations == 0)
}

@Test func bundledCodexAcceptanceIsDataAndARemovedCopyRefusesBothOperations() async throws {
    let root = try gateScratchRoot("codex-copy")
    defer { try? FileManager.default.removeItem(at: root) }
    let codex = try #require(try DetectorRegistry.loadDefault().first { $0.id == "codex" })
    #expect(codex.acceptedOperations == [.npmUpdate, .npmUninstall])

    let removed = try gateDefinitionCopy(of: codex, acceptedOperations: [])
    #expect(removed.acceptedOperations.isEmpty)
    let runner = GateCountingUpdateRunner()
    let operationBase = root.appendingPathComponent("operation-base", isDirectory: true)
    try FileManager.default.createDirectory(at: operationBase, withIntermediateDirectories: true)

    let updateResult = await NpmUpdateOperation.prepare(
        definition: removed,
        diagnostic: gateDiagnostic(),
        environment: gateEnvironment(),
        currentDirectory: root.path,
        runner: runner,
        operationRootBaseURL: operationBase
    )
    guard case .unavailable(let updateReason) = updateResult else {
        Issue.record("a codex copy without acceptance must refuse Update")
        return
    }
    #expect(updateReason == .operationNotAccepted)

    let uninstallResult = await NpmUninstallOperation.prepare(
        definition: removed,
        diagnostic: gateDiagnostic(),
        environment: gateEnvironment(),
        currentDirectory: root.path,
        runner: runner,
        operationRootBaseURL: operationBase
    )
    guard case .unavailable(let uninstallReason) = uninstallResult else {
        Issue.record("a codex copy without acceptance must refuse Uninstall")
        return
    }
    #expect(uninstallReason == .operationNotAccepted)

    #expect(runner.invocations == 0)
    #expect(try emptyDirectory(operationBase))
}
