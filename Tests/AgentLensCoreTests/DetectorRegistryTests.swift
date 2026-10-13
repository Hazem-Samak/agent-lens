import Testing
import Foundation
@testable import AgentLensCore

// M4 tests — D-010's promise, enforced: the registry is data-driven, every
// detector has a fixture test, and schema violations are rejected loudly.

@discardableResult
private func makeExecutable(script: String, at fileURL: URL) throws -> String {
    try Data("#!/bin/sh\n\(script)\n".utf8).write(to: fileURL)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755], ofItemAtPath: fileURL.path
    )
    return fileURL.path
}

private func tempRoot(_ label: String) throws -> URL {
    let base = ProcessInfo.processInfo.environment["AGENT_LENS_TEST_SCRATCH"]
        .map { URL(fileURLWithPath: $0, isDirectory: true) }
        ?? FileManager.default.temporaryDirectory
    let dir = base.appendingPathComponent("agentlens-m4-\(label)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func environment(pathEntries: [URL]) -> ShellEnvironment {
    let joined = pathEntries.map(\.path).joined(separator: ":")
    return ShellEnvironment(
        shellPath: "/bin/zsh",
        pathEntries: pathEntries.map(\.path),
        pathJoined: joined,
        raw: ["PATH": joined],
        isDegraded: false
    )
}

// MARK: Bundled registry validity

@Test func bundledDefaultDetectorsIsValidWithThreeTools() throws {
    let definitions = try DetectorRegistry.loadDefault()
    let ids = definitions.map(\.id)
    #expect(ids == ["codex", "opencode", "grok"])
    #expect(definitions.allSatisfy { $0.executableName == $0.id })
    #expect(definitions[0].fixture == DetectorDefinition.Fixture(layout: "npmGlobal", expectedSource: "npm"))
    #expect(definitions[1].fixture == DetectorDefinition.Fixture(layout: "singleDirectory", expectedSource: "standalone"))
    #expect(definitions[2].fixture == DetectorDefinition.Fixture(layout: "singleDirectory", expectedSource: "standalone"))
}

// MARK: Schema violations are rejected with named errors

@Test func schemaViolationsAreRejectedLoudly() throws {
    func expectError(
        _ expected: DetectorRegistryError,
        when json: String
    ) throws {
        var thrown: DetectorRegistryError?
        do {
            _ = try DetectorRegistry.validate(data: Data(json.utf8))
        } catch let error as DetectorRegistryError {
            thrown = error
        }
        #expect(thrown == expected, "for input: \(json)")
    }

    try expectError(
        .missingSchemaVersion,
        when: #"{"detectors": []}"#
    )
    try expectError(
        .unsupportedSchemaVersion(2),
        when: #"{"schemaVersion": 2, "detectors": [{"id": "x", "displayName": "X", "executableName": "x"}]}"#
    )
    try expectError(
        .missingField(field: "id", id: "(detector #0)"),
        when: #"{"schemaVersion": 1, "detectors": [{"displayName": "X", "executableName": "x"}]}"#
    )
    try expectError(
        .emptyField(field: "executableName", id: "x"),
        when: #"{"schemaVersion": 1, "detectors": [{"id": "x", "displayName": "X", "executableName": ""}]}"#
    )
    try expectError(
        .duplicateId("x"),
        when: #"{"schemaVersion": 1, "detectors": [{"id": "x", "displayName": "X", "executableName": "x"}, {"id": "x", "displayName": "Y", "executableName": "y"}]}"#
    )
    try expectError(
        .unknownLayout("npmoobal", id: "x"),
        when: #"{"schemaVersion": 1, "detectors": [{"id": "x", "displayName": "X", "executableName": "x", "fixture": {"layout": "npmoobal", "expectedSource": "npm"}}]}"#
    )
    try expectError(
        .unknownExpectedSource("npmx", id: "x"),
        when: #"{"schemaVersion": 1, "detectors": [{"id": "x", "displayName": "X", "executableName": "x", "fixture": {"layout": "npmGlobal", "expectedSource": "npmx"}}]}"#
    )
    try expectError(
        .noDetectors,
        when: #"{"schemaVersion": 1, "detectors": []}"#
    )
    try expectError(
        .badJSON(underlying: "root is not a JSON object"),
        when: #"[1, 2, 3]"#
    )
}

// MARK: Per-detector fixture tests (D-010: "each with a fixture test")

@Test func bundledFixtureDefinitionsMatchSyntheticLayouts() throws {
    let definitions = try DetectorRegistry.loadDefault()
    for definition in definitions {
        let fixture = try #require(definition.fixture)

        let root = try tempRoot(definition.id)
        defer { try? FileManager.default.removeItem(at: root) }

        let searchRoot: URL
        switch fixture.layout {
        case "npmGlobal":
            let nodeModulesDir = root.appendingPathComponent("lib/node_modules/\(definition.id)/bin")
            try FileManager.default.createDirectory(at: nodeModulesDir, withIntermediateDirectories: true)
            let target = try makeExecutable(
                script: "exit 0", at: nodeModulesDir.appendingPathComponent("\(definition.executableName).js")
            )
            let binDir = root.appendingPathComponent("bin")
            try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(
                atPath: binDir.appendingPathComponent(definition.executableName).path,
                withDestinationPath: target
            )
            searchRoot = binDir
        case "singleDirectory":
            try makeExecutable(
                script: "exit 0", at: root.appendingPathComponent(definition.executableName)
            )
            searchRoot = root
        case "brewCellar":
            let cellarBin = root.appendingPathComponent("Cellar/\(definition.id)/1.0/bin")
            try FileManager.default.createDirectory(at: cellarBin, withIntermediateDirectories: true)
            try makeExecutable(
                script: "exit 0", at: cellarBin.appendingPathComponent(definition.executableName)
            )
            searchRoot = cellarBin
        default:
            Issue.record("unknown fixture layout reached the test — validator should have rejected it")
            return
        }

        let detector = definition.makeDetector(versionQuery: { _, _, _ in nil })
        let tool = detector.detect(in: environment(pathEntries: [searchRoot]))

        #expect(tool.state == .installedAndOnPath, "fixture test for \(definition.id) failed")
        #expect(tool.source == fixture.expectedSource, "fixture test for \(definition.id) failed")
    }
}

// MARK: D-010's promise demonstrated: a new tool via data only

@Test func addingAFourthDefinitionRequiresNoSourceChanges() throws {
    let root = try tempRoot("fourth")
    defer { try? FileManager.default.removeItem(at: root) }
    try makeExecutable(script: "exit 0", at: root.appendingPathComponent("newtool"))

    let definition = DetectorDefinition(
        id: "newtool",
        displayName: "New Tool",
        executableName: "newtool",
        extraSearchRoots: [],
        fixture: DetectorDefinition.Fixture(layout: "singleDirectory", expectedSource: "standalone")
    )
    let tool = definition.makeDetector(versionQuery: { _, _, _ in nil })
        .detect(in: environment(pathEntries: [root]))

    #expect(tool.state == .installedAndOnPath)
    #expect(tool.displayName == "New Tool")
    #expect(tool.source == "standalone")
}
