import Testing
import Foundation
@testable import AgentLensCore

// M4 tests — D-010's promise, enforced: the registry is data-driven, every
// detector has a fixture test, and schema violations are rejected loudly.
// M9-A migrates the schema to 2 with required category/packages/versionQuery.

@discardableResult
private func makeExecutable(script: String, at fileURL: URL) throws -> String {
    try Data("#!/bin/sh\n\(script)\n".utf8).write(to: fileURL)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755], ofItemAtPath: fileURL.path
    )
    return fileURL.path
}

private func tempRoot(_ label: String) throws -> URL {
    let environment = ProcessInfo.processInfo.environment
    guard let basePath = [environment["AGENT_LENS_TEST_SCRATCH"], environment["TMPDIR"]]
        .compactMap({ $0 })
        .first(where: { !$0.isEmpty })
    else {
        throw NSError(domain: "AgentLensTests", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "no approved test scratch root is available"])
    }
    let base = URL(fileURLWithPath: basePath, isDirectory: true).resolvingSymlinksInPath()
    let dir = base.appendingPathComponent("agentlens-m4-\(label)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.resolvingSymlinksInPath()
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

private let standardQueryJSON = #""versionQuery":{"arguments":["--version"],"stream":"stdout","line":"first"}"#

/// A complete schema-2 detector object. Callers can replace individual fields
/// to build malformed variants while keeping the rest valid.
private func detectorJSON(
    id: String? = "x",
    displayName: String? = "X",
    executableName: String? = "x",
    extraFields: String = "",
    categoryField: String = #""category":"aiAgent""#,
    packagesField: String = #""packages":[]"#,
    queryField: String = standardQueryJSON
) -> String {
    var fields: [String] = []
    if let id { fields.append(#""id":\#(quoted(id))"#) }
    if let displayName { fields.append(#""displayName":\#(quoted(displayName))"#) }
    if let executableName { fields.append(#""executableName":\#(quoted(executableName))"#) }
    fields.append(categoryField)
    fields.append(packagesField)
    fields.append(queryField)
    if !extraFields.isEmpty { fields.append(extraFields) }
    return "{" + fields.joined(separator: ",") + "}"
}

private func quoted(_ value: String) -> String {
    let data = try! JSONEncoder().encode(value)
    return String(decoding: data, as: UTF8.self)
}

private func registryJSON(_ detectors: [String], schemaVersion: Int = 2) -> String {
    #"{"schemaVersion":\#(schemaVersion),"detectors":[\#(detectors.joined(separator: ","))]}"#
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

    #expect(definitions.map(\.category) == [.aiAgent, .aiAgent, .aiAgent])
    #expect(definitions.allSatisfy { $0.versionQuery == .standard })
    #expect(definitions[0].packages == [
        try DeclaredPackage(manager: .npm, name: "@openai/codex"),
        try DeclaredPackage(manager: .homebrewCask, name: "codex"),
    ])
    #expect(definitions[0].informationURL?.absoluteString == "https://developers.openai.com/codex/cli")
    #expect(definitions[0].uninstallInstructionsURL == nil)
    #expect(definitions[1].packages.count == 4)
    #expect(definitions[1].informationURL?.absoluteString == "https://opencode.ai/v2/docs/")
    #expect(definitions[1].uninstallInstructionsURL?.absoluteString == "https://opencode.ai/v2/docs/cli/#uninstall")
    #expect(definitions[2].packages.isEmpty)
    #expect(definitions[2].informationURL?.absoluteString == "https://docs.x.ai/build/overview")
    #expect(definitions[2].uninstallInstructionsURL == nil)
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
    // Schema 1 is rejected outright; there is no compatibility shim.
    try expectError(
        .unsupportedSchemaVersion(1),
        when: registryJSON([detectorJSON()], schemaVersion: 1)
    )
    try expectError(
        .unsupportedSchemaVersion(3),
        when: registryJSON([detectorJSON()], schemaVersion: 3)
    )
    try expectError(
        .missingField(field: "id", id: "(detector #0)"),
        when: registryJSON([detectorJSON(id: nil)])
    )
    try expectError(
        .emptyField(field: "executableName", id: "x"),
        when: registryJSON([detectorJSON(executableName: "")])
    )
    try expectError(
        .duplicateId("x"),
        when: registryJSON([detectorJSON(), detectorJSON(displayName: "Y", executableName: "y")])
    )
    try expectError(
        .unknownLayout("npmoobal", id: "x"),
        when: registryJSON([
            detectorJSON(extraFields: #""fixture":{"layout":"npmoobal","expectedSource":"npm"}"#)
        ])
    )
    try expectError(
        .unknownExpectedSource("npmx", id: "x"),
        when: registryJSON([
            detectorJSON(extraFields: #""fixture":{"layout":"npmGlobal","expectedSource":"npmx"}"#)
        ])
    )
    try expectError(
        .noDetectors,
        when: registryJSON([])
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

        let detector = definition.makeDetector(
            versionQuery: { _, _, _, _ in nil }
        )
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

    let definition = try DetectorDefinition(
        id: "newtool",
        displayName: "New Tool",
        executableName: "newtool",
        extraSearchRoots: [],
        fixture: DetectorDefinition.Fixture(layout: "singleDirectory", expectedSource: "standalone"),
        category: .aiAgent,
        packages: [],
        informationURL: nil,
        uninstallInstructionsURL: nil,
        versionQuery: .standard
    )
    let tool = definition.makeDetector(versionQuery: { _, _, _, _ in nil })
        .detect(in: environment(pathEntries: [root]))

    #expect(tool.state == .installedAndOnPath)
    #expect(tool.displayName == "New Tool")
    #expect(tool.source == "standalone")
}
