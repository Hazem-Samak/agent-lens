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

@Test func bundledDefaultDetectorsMatchFrozenCatalogue() throws {
    let definitions = try DetectorRegistry.loadDefault()
    let ids = definitions.map(\.id)
    #expect(ids == [
        "codex", "opencode", "grok", "claude", "gemini", "cline",
        "hermes", "aider", "goose", "kiro-cli", "omp", "agy",
        "dsh", "qodercli",
    ])
    #expect(definitions.allSatisfy { $0.executableName == $0.id })
    #expect(definitions.map(\.fixture) == [
        DetectorDefinition.Fixture(layout: "npmGlobal", expectedSource: "npm"),
        DetectorDefinition.Fixture(layout: "singleDirectory", expectedSource: "standalone"),
        DetectorDefinition.Fixture(layout: "singleDirectory", expectedSource: "standalone"),
        DetectorDefinition.Fixture(layout: "singleDirectory", expectedSource: "standalone"),
        DetectorDefinition.Fixture(layout: "npmGlobal", expectedSource: "npm"),
        DetectorDefinition.Fixture(layout: "npmGlobal", expectedSource: "npm"),
        DetectorDefinition.Fixture(layout: "singleDirectory", expectedSource: "standalone"),
        DetectorDefinition.Fixture(layout: "singleDirectory", expectedSource: "standalone"),
        DetectorDefinition.Fixture(layout: "singleDirectory", expectedSource: "standalone"),
        DetectorDefinition.Fixture(layout: "singleDirectory", expectedSource: "standalone"),
        DetectorDefinition.Fixture(layout: "singleDirectory", expectedSource: "standalone"),
        DetectorDefinition.Fixture(layout: "singleDirectory", expectedSource: "standalone"),
        DetectorDefinition.Fixture(layout: "npmGlobal", expectedSource: "npm"),
        DetectorDefinition.Fixture(layout: "singleDirectory", expectedSource: "standalone"),
    ])

    #expect(definitions.map(\.category) == [
        .aiAgent, .aiAgent, .aiAgent, .aiAgent, .aiAgent, .aiAgent,
        .aiAgent, .aiCodingTool, .aiCodingTool, .aiCodingTool, .aiHarness, .aiHarness,
        .aiHarness, .aiCodingTool,
    ])
    #expect(definitions.allSatisfy { $0.versionQuery == .standard })
    #expect(definitions[0].acceptedOperations == [.npmUpdate, .npmUninstall])
    #expect(definitions.dropFirst().allSatisfy { $0.acceptedOperations.isEmpty })
    #expect(definitions[0].packages == [
        try DeclaredPackage(manager: .npm, name: "@openai/codex"),
        try DeclaredPackage(manager: .homebrewCask, name: "codex"),
    ])
    #expect(definitions[0].informationURL?.absoluteString == "https://developers.openai.com/codex/cli")
    #expect(definitions[0].uninstallInstructionsURL == nil)
    #expect(definitions[1].packages == [
        try DeclaredPackage(manager: .npm, name: "@opencode/cli"),
        try DeclaredPackage(manager: .npm, name: "opencode-ai"),
        try DeclaredPackage(manager: .homebrewFormula, name: "anomalyco/tap/opencode-v2"),
        try DeclaredPackage(manager: .homebrewFormula, name: "anomalyco/tap/opencode"),
        try DeclaredPackage(manager: .homebrewFormula, name: "opencode"),
    ])
    #expect(definitions[1].informationURL?.absoluteString == "https://opencode.ai/docs/")
    #expect(definitions[1].uninstallInstructionsURL?.absoluteString == "https://opencode.ai/docs/cli/#uninstall")
    #expect(definitions[2].packages.isEmpty)
    #expect(definitions[2].informationURL?.absoluteString == "https://docs.x.ai/build/overview")
    #expect(definitions[2].uninstallInstructionsURL == nil)

    #expect(definitions[3].displayName == "Claude Code")
    #expect(definitions[3].extraSearchRoots == ["~/.local/bin"])
    #expect(definitions[3].packages == [
        try DeclaredPackage(manager: .npm, name: "@anthropic-ai/claude-code"),
        try DeclaredPackage(manager: .homebrewCask, name: "claude-code"),
        try DeclaredPackage(manager: .homebrewCask, name: "claude-code@latest"),
    ])
    #expect(definitions[3].informationURL?.absoluteString == "https://code.claude.com/docs/en/setup")
    #expect(definitions[3].uninstallInstructionsURL?.absoluteString == "https://code.claude.com/docs/en/setup#uninstall-claude-code")

    #expect(definitions[4].displayName == "Gemini CLI")
    #expect(definitions[4].extraSearchRoots.isEmpty)
    #expect(definitions[4].packages == [
        try DeclaredPackage(manager: .npm, name: "@google/gemini-cli"),
        try DeclaredPackage(manager: .homebrewFormula, name: "gemini-cli"),
    ])
    #expect(definitions[4].informationURL?.absoluteString == "https://geminicli.com/docs/get-started/installation/")
    #expect(definitions[4].uninstallInstructionsURL?.absoluteString == "https://geminicli.com/docs/resources/uninstall/")

    #expect(definitions[5].displayName == "Cline CLI")
    #expect(definitions[5].extraSearchRoots.isEmpty)
    #expect(definitions[5].packages == [
        try DeclaredPackage(manager: .npm, name: "cline"),
        try DeclaredPackage(manager: .homebrewFormula, name: "cline"),
    ])
    #expect(definitions[5].informationURL?.absoluteString == "https://docs.cline.bot/usage/cli-overview")
    #expect(definitions[5].uninstallInstructionsURL == nil)

    // M11-D collision batch: identity rows copied from docs/catalogue-identities.md.
    #expect(definitions[6].displayName == "Hermes")
    #expect(definitions[6].extraSearchRoots == ["~/.local/bin"])
    #expect(definitions[6].packages == [
        try DeclaredPackage(manager: .homebrewFormula, name: "hermes-agent"),
    ])
    #expect(definitions[6].informationURL?.absoluteString
            == "https://hermes-agent.nousresearch.com/docs/getting-started/installation")
    #expect(definitions[6].uninstallInstructionsURL?.absoluteString
            == "https://hermes-agent.nousresearch.com/docs/getting-started/updating#uninstalling")

    #expect(definitions[7].displayName == "Aider")
    #expect(definitions[7].extraSearchRoots.isEmpty)
    #expect(definitions[7].packages == [
        try DeclaredPackage(manager: .homebrewFormula, name: "aider"),
    ])
    #expect(definitions[7].informationURL?.absoluteString == "https://aider.chat/docs/install.html")
    #expect(definitions[7].uninstallInstructionsURL == nil)

    #expect(definitions[8].displayName == "Goose")
    #expect(definitions[8].extraSearchRoots == ["~/.local/bin"])
    #expect(definitions[8].packages == [
        try DeclaredPackage(manager: .homebrewFormula, name: "block-goose-cli"),
    ])
    #expect(definitions[8].informationURL?.absoluteString
            == "https://goose-docs.ai/docs/guides/goose-cli-commands")
    #expect(definitions[8].uninstallInstructionsURL == nil)

    #expect(definitions[9].displayName == "Kiro CLI")
    #expect(definitions[9].extraSearchRoots == ["~/.local/bin"])
    #expect(definitions[9].packages == [
        try DeclaredPackage(manager: .homebrewCask, name: "kiro-cli"),
    ])
    #expect(definitions[9].informationURL?.absoluteString == "https://kiro.dev/docs/cli/")
    #expect(definitions[9].uninstallInstructionsURL?.absoluteString
            == "https://kiro.dev/docs/getting-started/installation/")

    #expect(definitions[10].displayName == "Oh My Pi")
    #expect(definitions[10].extraSearchRoots == ["~/.local/bin"])
    #expect(definitions[10].packages == [
        try DeclaredPackage(manager: .npm, name: "@oh-my-pi/pi-coding-agent"),
        try DeclaredPackage(manager: .homebrewFormula, name: "can1357/tap/omp"),
    ])
    #expect(definitions[10].informationURL?.absoluteString == "https://omp.sh/docs/quickstart")
    #expect(definitions[10].uninstallInstructionsURL == nil)

    #expect(definitions[11].displayName == "Antigravity CLI")
    #expect(definitions[11].extraSearchRoots == ["~/.local/bin", "~/.gemini/bin"])
    #expect(definitions[11].packages == [
        try DeclaredPackage(manager: .homebrewCask, name: "antigravity-cli"),
    ])
    #expect(definitions[11].informationURL?.absoluteString
            == "https://antigravity.google/docs/getting-started/")
    #expect(definitions[11].uninstallInstructionsURL == nil)

    // M11-E remainder: dsh and qodercli copied from docs/catalogue-identities.md.
    #expect(definitions[12].displayName == "DeepSeek Harness")
    #expect(definitions[12].extraSearchRoots == ["~/.local/bin"])
    #expect(definitions[12].packages == [
        try DeclaredPackage(manager: .npm, name: "@deepseek-ai/dsh"),
    ])
    #expect(definitions[12].informationURL?.absoluteString
            == "https://github.com/deepseek-ai/deepseek-harness")
    #expect(definitions[12].uninstallInstructionsURL == nil)
    #expect(definitions[12].acceptedOperations.isEmpty)

    #expect(definitions[13].displayName == "Qoder")
    #expect(definitions[13].extraSearchRoots == ["~/.local/bin"])
    #expect(definitions[13].packages == [
        try DeclaredPackage(manager: .npm, name: "@qoder-ai/qodercli"),
    ])
    #expect(definitions[13].informationURL?.absoluteString
            == "https://docs.qoder.com/cli/installation")
    #expect(definitions[13].uninstallInstructionsURL?.absoluteString
            == "https://docs.qoder.com/cli/installation#uninstallation")
    #expect(definitions[13].acceptedOperations.isEmpty)
}

// MARK: Collision identities never reach the bundled registry (M11-D)

/// Binding do-not-declare table from `docs/catalogue-identities.md`, keyed by manager raw value.
/// The manager is part of the key: formula `goose` is pressly's migration CLI, while formula
/// `block-goose-cli` is the frozen Goose candidate. They are different declarations.
private let forbiddenCollisionPackages: [String: Set<String>] = [
    "homebrewFormula": ["dsh", "goose"],
    "homebrewCask": ["qoder", "opencode-desktop", "block-goose"],
    "npm": [
        "goose", "kiro-cli", "qoder", "@qoder-ai/qoder", "@aws/kiro-cli", "@oh-my-pi/cli",
    ],
]

/// The IDE/router names: never detector ids and never executable names.
private let forbiddenCollisionRegistryIDs: Set<String> = ["kiro", "qoder"]

private func collisionIdentityViolations(in definitions: [DetectorDefinition]) -> [String] {
    var violations: [String] = []
    for definition in definitions {
        if forbiddenCollisionRegistryIDs.contains(definition.id) {
            violations.append("detector id \(definition.id)")
        }
        if forbiddenCollisionRegistryIDs.contains(definition.executableName) {
            violations.append("executable \(definition.executableName) (detector \(definition.id))")
        }
        for package in definition.packages {
            if forbiddenCollisionPackages[package.manager.rawValue]?.contains(package.name) == true {
                violations.append(
                    "\(package.manager.rawValue) \(package.name) (detector \(definition.id))"
                )
            }
        }
    }
    return violations
}

@Test func bundledRegistryNeverDeclaresCollisionIdentities() throws {
    let definitions = try DetectorRegistry.loadDefault()
    #expect(collisionIdentityViolations(in: definitions).isEmpty,
            "the bundled registry must never declare a do-not-declare identity")

    // Seeded control: the scan must reject a forbidden identity in EVERY manager branch. Without
    // this, an empty list could mean a branch check is vacuous (M11-F carry-forward).
    let seeded = try DetectorRegistry.validate(data: Data(#"""
    {"schemaVersion":2,"detectors":[
      {"id":"kiro","displayName":"Kiro","executableName":"kiro","category":"aiCodingTool",
       "packages":[{"manager":"npm","name":"@aws/kiro-cli"}],
       "versionQuery":{"arguments":["--version"],"stream":"stdout","line":"first"}},
      {"id":"seed-formula","displayName":"Seed Formula","executableName":"seed-formula",
       "category":"aiCodingTool",
       "packages":[{"manager":"homebrewFormula","name":"goose"}],
       "versionQuery":{"arguments":["--version"],"stream":"stdout","line":"first"}},
      {"id":"seed-cask","displayName":"Seed Cask","executableName":"seed-cask",
       "category":"aiCodingTool",
       "packages":[{"manager":"homebrewCask","name":"qoder"}],
       "versionQuery":{"arguments":["--version"],"stream":"stdout","line":"first"}}
    ]}
    """#.utf8))
    let seededViolations = collisionIdentityViolations(in: seeded)
    #expect(seededViolations.contains("detector id kiro"))
    #expect(seededViolations.contains("executable kiro (detector kiro)"))
    #expect(seededViolations.contains("npm @aws/kiro-cli (detector kiro)"))
    #expect(seededViolations.contains("homebrewFormula goose (detector seed-formula)"))
    #expect(seededViolations.contains("homebrewCask qoder (detector seed-cask)"))
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

// MARK: Accepted operations (M11-B fail-closed mutation gate)

@Test func acceptedOperationsAreOptionalClosedAndValidatedPerField() throws {
    func expectError(
        _ expected: DetectorRegistryError,
        when extraFields: String
    ) throws {
        let data = Data(registryJSON([detectorJSON(extraFields: extraFields)]).utf8)
        var thrown: DetectorRegistryError?
        do {
            _ = try DetectorRegistry.validate(data: data)
        } catch let error as DetectorRegistryError {
            thrown = error
        }
        #expect(thrown == expected, "for fields: \(extraFields)")
    }

    // Absent and empty both mean no accepted operation.
    let absent = try DetectorRegistry.validate(data: Data(registryJSON([detectorJSON()]).utf8))
    #expect(absent[0].acceptedOperations.isEmpty)
    let empty = try DetectorRegistry.validate(
        data: Data(registryJSON([detectorJSON(extraFields: #""acceptedOperations":[]"#)]).utf8)
    )
    #expect(empty[0].acceptedOperations.isEmpty)

    // The complete closed vocabulary is accepted in declared order.
    let both = try DetectorRegistry.validate(data: Data(registryJSON([
        detectorJSON(extraFields: #""acceptedOperations":["npmUpdate","npmUninstall"]"#)
    ]).utf8))
    #expect(both[0].acceptedOperations == [.npmUpdate, .npmUninstall])

    try expectError(
        .invalidField(
            field: "acceptedOperations[0]",
            id: "x",
            reason: "must be one of npmUpdate, npmUninstall"
        ),
        when: #""acceptedOperations":["npmUpgrade"]"#
    )
    try expectError(
        .invalidField(
            field: "acceptedOperations[1]",
            id: "x",
            reason: "duplicate operation 'npmUpdate'"
        ),
        when: #""acceptedOperations":["npmUpdate","npmUpdate"]"#
    )
    try expectError(
        .invalidField(
            field: "acceptedOperations",
            id: "x",
            reason: "must be an array of accepted operation strings"
        ),
        when: #""acceptedOperations":"npmUpdate""#
    )
    try expectError(
        .invalidField(
            field: "acceptedOperations[1]",
            id: "x",
            reason: "must be a string"
        ),
        when: #""acceptedOperations":["npmUpdate",7]"#
    )
    try expectError(
        .invalidField(
            field: "acceptedOperations",
            id: "x",
            reason: "must be an array of accepted operation strings"
        ),
        when: #""acceptedOperations":null"#
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
