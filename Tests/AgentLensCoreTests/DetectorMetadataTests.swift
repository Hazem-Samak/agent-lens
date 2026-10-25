import Darwin
import Foundation
import Testing
@testable import AgentLensCore

// M9-A metadata tests: concrete value types, strict registry validation and
// the CLI metadata renderer. These exercise behavior and boundaries, not source
// text or incidental wording.

private let standardQueryField =
    #""versionQuery":{"arguments":["--version"],"stream":"stdout","line":"first"}"#

private func detectorObject(
    id: String = "tool",
    categoryField: String = #""category":"aiAgent""#,
    packagesField: String = #""packages":[]"#,
    queryField: String = standardQueryField,
    extraFields: [String] = []
) -> String {
    var fields = [
        #""id":"\#(id)""#,
        #""displayName":"Tool""#,
        #""executableName":"tool""#,
        categoryField,
        packagesField,
        queryField,
    ]
    fields.append(contentsOf: extraFields)
    return "{" + fields.joined(separator: ",") + "}"
}

private func registryData(
    detectors: [String],
    extraRootFields: [String] = []
) -> Data {
    var fields = [
        #""schemaVersion":2"#,
        #""detectors":[\#(detectors.joined(separator: ","))]"#,
    ]
    fields.append(contentsOf: extraRootFields)
    return Data(("{" + fields.joined(separator: ",") + "}").utf8)
}

private func registryError(_ data: Data) -> DetectorRegistryError? {
    do {
        _ = try DetectorRegistry.validate(data: data)
        return nil
    } catch let error as DetectorRegistryError {
        return error
    } catch {
        return nil
    }
}

private func expectInvalidField(
    _ data: Data,
    field: String,
    id: String = "tool"
) {
    guard case .invalidField(let actualField, let actualID, _) = registryError(data) else {
        Issue.record("expected an invalidField error for \(field)")
        return
    }
    #expect(actualField == field)
    #expect(actualID == id)
}

private func expectUnknownKey(
    _ data: Data,
    key: String,
    id: String?
) {
    guard case .unknownKey(let actualKey, let actualID) = registryError(data) else {
        Issue.record("expected an unknownKey error for \(key)")
        return
    }
    #expect(actualKey == key)
    #expect(actualID == id)
}

// MARK: Package candidates

@Test func validScopedNpmAndFullyQualifiedTapCandidatesAreAccepted() throws {
    let npmScoped = try DeclaredPackage(manager: .npm, name: "@openai/codex")
    let npmUnscoped = try DeclaredPackage(manager: .npm, name: "opencode-ai")
    let tappedFormula = try DeclaredPackage(manager: .homebrewFormula, name: "anomalyco/tap/opencode-v2")
    let cask = try DeclaredPackage(manager: .homebrewCask, name: "codex")

    let data = registryData(detectors: [
        detectorObject(
            packagesField: #""packages":[{"manager":"npm","name":"@openai/codex"},{"manager":"npm","name":"opencode-ai"},{"manager":"homebrewFormula","name":"anomalyco/tap/opencode-v2"},{"manager":"homebrewCask","name":"codex"}]"#
        )
    ])
    let definitions = try DetectorRegistry.validate(data: data)
    #expect(definitions[0].packages == [npmScoped, npmUnscoped, tappedFormula, cask])
}

@Test func homebrewCandidatesAcceptOnlyBareOrFullyQualifiedNames() throws {
    for manager in [PackageManager.homebrewFormula, .homebrewCask] {
        _ = try DeclaredPackage(manager: manager, name: "codex")
        _ = try DeclaredPackage(manager: manager, name: "anomalyco/tap/opencode-v2")

        for name in ["tap/name", "owner/", "/name", "owner//name", "owner/tap/", "owner/tap/name/extra"] {
            #expect(throws: DetectorRegistryError.self) {
                _ = try DeclaredPackage(manager: manager, name: name)
            }
        }
    }

    for manager in ["homebrewFormula", "homebrewCask"] {
        let data = registryData(detectors: [
            detectorObject(
                packagesField: #""packages":[{"manager":"\#(manager)","name":"tap/name"}]"#
            )
        ])
        expectInvalidField(data, field: "packages[0].name")

        let decodedPackage = Data(#"{"manager":"\#(manager)","name":"tap/name"}"#.utf8)
        #expect(throws: DetectorRegistryError.self) {
            _ = try JSONDecoder().decode(DeclaredPackage.self, from: decodedPackage)
        }
    }
}

@Test func invalidPackageIdentitiesAreRejectedWithThePackageField() {
    let invalidNames = [
        "",
        " openai/codex",
        "openai codex",
        "@openai",
        "../codex",
        "/absolute/codex",
        "codex/extra",
        "codex; rm -rf /",
        "$(touch /tmp/codex)",
        "--force",
        "codex\nother",
        "codex\u{0}other",
    ]
    for name in invalidNames {
        let encoded = String(decoding: try! JSONEncoder().encode(name), as: UTF8.self)
        let data = registryData(detectors: [
            detectorObject(
                packagesField: #""packages":[{"manager":"npm","name":\#(encoded)}]"#
            )
        ])
        if name.isEmpty {
            // An empty required name is still the named package field, reported as empty.
            #expect(registryError(data) == .emptyField(field: "packages[0].name", id: "tool"))
        } else {
            expectInvalidField(data, field: "packages[0].name")
        }
    }
}

@Test func unknownPackageManagerIsRejectedWithTheManagerField() {
    let data = registryData(detectors: [
        detectorObject(
            packagesField: #""packages":[{"manager":"pip","name":"codex"}]"#
        )
    ])
    expectInvalidField(data, field: "packages[0].manager")
}

@Test func duplicateManagerAndNamePairsAreRejectedButDifferentManagersAreDistinct() throws {
    let duplicate = registryData(detectors: [
        detectorObject(
            packagesField: #""packages":[{"manager":"npm","name":"codex"},{"manager":"npm","name":"codex"}]"#
        )
    ])
    #expect(registryError(duplicate) == .duplicatePackage(manager: "npm", name: "codex", id: "tool"))

    let distinct = registryData(detectors: [
        detectorObject(
            packagesField: #""packages":[{"manager":"npm","name":"codex"},{"manager":"homebrewCask","name":"codex"}]"#
        )
    ])
    let definitions = try DetectorRegistry.validate(data: distinct)
    #expect(definitions[0].packages.count == 2)
}

// MARK: Category

@Test func unknownCategoryIsRejectedWithTheCategoryField() {
    let data = registryData(detectors: [
        detectorObject(categoryField: #""category":"manager""#)
    ])
    expectInvalidField(data, field: "category")
}

// MARK: Official links

@Test func httpsInformationAndUninstallLinksAreAcceptedAndPreserved() throws {
    let data = registryData(detectors: [
        detectorObject(extraFields: [
            #""informationURL":"https://developers.openai.com/codex/cli""#,
            #""uninstallInstructionsURL":"https://opencode.ai/v2/docs/cli/#uninstall""#,
        ])
    ])
    let definition = try #require(try DetectorRegistry.validate(data: data).first)
    #expect(definition.informationURL?.absoluteString == "https://developers.openai.com/codex/cli")
    #expect(definition.uninstallInstructionsURL?.absoluteString == "https://opencode.ai/v2/docs/cli/#uninstall")
}

@Test func absentOrNullOptionalLinksRemainAbsent() throws {
    let data = registryData(detectors: [
        detectorObject(extraFields: [
            #""informationURL":null"#,
            #""uninstallInstructionsURL":null"#,
        ])
    ])
    let definition = try #require(try DetectorRegistry.validate(data: data).first)
    #expect(definition.informationURL == nil)
    #expect(definition.uninstallInstructionsURL == nil)
}

@Test func malformedOrNonHTTPSLinksAreRejected() {
    let invalidLinks = [
        "file:///tmp/instructions",
        "javascript:alert(1)",
        "http://example.com/instructions",
        "https://",
        "https:///instructions",
        "https://user:pass@example.com/instructions",
        "https://exa mple.com/instructions",
        "not a url",
    ]
    for link in invalidLinks {
        let encoded = String(decoding: try! JSONEncoder().encode(link), as: UTF8.self)
        let data = registryData(detectors: [
            detectorObject(extraFields: [#""informationURL":\#(encoded)"#])
        ])
        expectInvalidField(data, field: "informationURL")
    }
}

// MARK: Strict unknown keys

@Test func unknownKeysAreRejectedAtRootDefinitionFixturePackageAndQueryLevels() {
    expectUnknownKey(
        registryData(detectors: [detectorObject()], extraRootFields: [#""unexpected":true"#]),
        key: "unexpected",
        id: nil
    )
    expectUnknownKey(
        registryData(detectors: [detectorObject(extraFields: [#""homepage":"https://example.com""#])]),
        key: "homepage",
        id: "tool"
    )
    expectUnknownKey(
        registryData(detectors: [
            detectorObject(extraFields: [
                #""fixture":{"layout":"singleDirectory","expectedSource":"standalone","timeout":3}"#
            ])
        ]),
        key: "fixture.timeout",
        id: "tool"
    )
    expectUnknownKey(
        registryData(detectors: [
            detectorObject(
                packagesField: #""packages":[{"manager":"npm","name":"codex","version":"1.0.0"}]"#
            )
        ]),
        key: "packages[0].version",
        id: "tool"
    )
    expectUnknownKey(
        registryData(detectors: [
            detectorObject(
                queryField: #""versionQuery":{"arguments":["--version"],"stream":"stdout","line":"first","timeout":3}"#
            )
        ]),
        key: "versionQuery.timeout",
        id: "tool"
    )
}

// MARK: Codable does not bypass validity

@Test func validDefinitionsRoundTripThroughCodable() throws {
    let definitions = try DetectorRegistry.loadDefault()
    let data = try JSONEncoder().encode(definitions)
    let decoded = try JSONDecoder().decode([DetectorDefinition].self, from: data)
    #expect(decoded == definitions)
}

@Test func decodingAnInvalidDefinitionFailsClosed() {
    let invalidCategory = Data(
        detectorObject(categoryField: #""category":"unsupported""#).utf8
    )
    #expect(throws: DetectorRegistryError.self) {
        _ = try JSONDecoder().decode(DetectorDefinition.self, from: invalidCategory)
    }

    let invalidQuery = Data(
        detectorObject(
            queryField: #""versionQuery":{"arguments":[],"stream":"stdout","line":"first"}"#
        ).utf8
    )
    #expect(throws: DetectorRegistryError.self) {
        _ = try JSONDecoder().decode(DetectorDefinition.self, from: invalidQuery)
    }

    let unknownDefinitionKey = Data(
        detectorObject(extraFields: [#""unexpected":true"#]).utf8
    )
    #expect(throws: DetectorRegistryError.self) {
        _ = try JSONDecoder().decode(DetectorDefinition.self, from: unknownDefinitionKey)
    }

    let unknownFixtureKey = Data(
        detectorObject(extraFields: [
            #""fixture":{"layout":"singleDirectory","expectedSource":"standalone","timeout":3}"#
        ]).utf8
    )
    do {
        _ = try JSONDecoder().decode(DetectorDefinition.self, from: unknownFixtureKey)
        Issue.record("expected a typed fixture rejection")
    } catch let error as DetectorRegistryError {
        guard case .invalidField(let field, let id, let reason) = error else {
            Issue.record("expected an invalidField error, got \(error)")
            return
        }
        #expect(field == "fixture")
        #expect(id == "tool")
        #expect(reason.contains("fixture.timeout"))
    } catch {
        Issue.record("expected DetectorRegistryError, got \(error)")
    }

    let unknownPackageKey = Data(
        detectorObject(
            packagesField: #""packages":[{"manager":"npm","name":"codex","version":"1.0.0"}]"#
        ).utf8
    )
    #expect(throws: DetectorRegistryError.self) {
        _ = try JSONDecoder().decode(DetectorDefinition.self, from: unknownPackageKey)
    }

    let unknownQueryKey = Data(
        detectorObject(
            queryField: #""versionQuery":{"arguments":["--version"],"stream":"stdout","line":"first","timeout":3}"#
        ).utf8
    )
    #expect(throws: DetectorRegistryError.self) {
        _ = try JSONDecoder().decode(DetectorDefinition.self, from: unknownQueryKey)
    }
}

@Test func directConstructionRejectsNonHTTPSInformationURL() {
    #expect(throws: DetectorRegistryError.self) {
        _ = try DetectorDefinition(
            id: "tool",
            displayName: "Tool",
            executableName: "tool",
            extraSearchRoots: [],
            fixture: nil,
            category: .aiAgent,
            packages: [],
            informationURL: URL(string: "http://example.com/instructions"),
            uninstallInstructionsURL: nil,
            versionQuery: .standard
        )
    }
}

// MARK: Schema-version boundary isolation

@Test func dangerousSchemaVersionsAreRejectedWithoutTrappingTheTestProcess() throws {
    let root = try metadataScratchRoot("schema-boundary")
    defer { try? FileManager.default.removeItem(at: root) }
    let products = try agentLensCoreProductsDirectory()
    let source = root.appendingPathComponent("schema-boundary-probe.swift")
    let executable = root.appendingPathComponent("schema-boundary-probe")

    let probeSource = #"""
    import Foundation
    import AgentLensCore

    func validate(_ schema: String) -> String {
        let detector = #"{"id":"probe","displayName":"Probe","executableName":"probe","category":"aiAgent","packages":[],"versionQuery":{"arguments":["--version"],"stream":"stdout","line":"first"}}"#
        let text = "{\"schemaVersion\":\(schema),\"detectors\":[\(detector)]}"
        do {
            _ = try DetectorRegistry.validate(data: Data(text.utf8))
            return "accepted"
        } catch let error as DetectorRegistryError {
            switch error {
            case .unsupportedSchemaVersion(let value):
                return "unsupported:\(value)"
            case .badJSON:
                return "badJSON"
            default:
                return "other:\(error)"
            }
        } catch {
            return "other:\(error)"
        }
    }

    let cases = [
        ("valid", "2"),
        ("validDecimal", "2.0"),
        ("fraction", "2.5"),
        ("boolean", "true"),
        ("intMax", "9223372036854775807"),
        ("aboveIntMax", "9223372036854775808"),
        ("intMaxDecimal", "9223372036854775807.0"),
        ("nearIntMax", "9223372036854775296"),
        ("aboveIntMaxDecimal", "9223372036854775808.0"),
        ("intMin", "-9223372036854775808"),
        ("minDecimal", "-9223372036854775808.0"),
        ("belowIntMin", "-9223372036854775809"),
        ("hugeDouble", "1e19"),
    ]
    for (label, schema) in cases {
        print("\(label)|\(validate(schema))")
    }
    """#
    try Data(probeSource.utf8).write(to: source)

    let compiler = Process()
    compiler.executableURL = URL(fileURLWithPath: "/usr/bin/swiftc")
    compiler.arguments = [
        "-I", products.path,
        source.path,
        products.appendingPathComponent("AgentLensCore.o").path,
        "-o", executable.path,
    ]
    compiler.currentDirectoryURL = root
    let compilation = try runIsolatedProcess(compiler, captureDirectory: root, label: "schema-probe-compile")
    #expect(compilation.status == 0, "probe compilation failed: \(compilation.stderr)")
    guard compilation.status == 0 else { return }

    let probe = Process()
    probe.executableURL = executable
    probe.currentDirectoryURL = root
    let result = try runIsolatedProcess(probe, captureDirectory: root, label: "schema-probe-run")
    #expect(result.status == 0, "probe terminated without a normal exit: \(result.stderr)")
    let lines = Set(
        result.stdout.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    )
    let expected: Set<String> = [
        "valid|accepted",
        "validDecimal|accepted",
        "fraction|badJSON",
        "boolean|badJSON",
        "intMax|unsupported:9223372036854775807",
        "aboveIntMax|badJSON",
        "intMaxDecimal|unsupported:9223372036854775807",
        "nearIntMax|unsupported:9223372036854775296",
        "aboveIntMaxDecimal|badJSON",
        "intMin|unsupported:-9223372036854775808",
        "minDecimal|unsupported:-9223372036854775808",
        "belowIntMin|badJSON",
        "hugeDouble|badJSON",
    ]
    #expect(lines == expected, "schema probe output: \(result.stdout)")
}

private func metadataScratchRoot(_ label: String) throws -> URL {
    let environment = ProcessInfo.processInfo.environment
    guard let basePath = [environment["AGENT_LENS_TEST_SCRATCH"], environment["TMPDIR"]]
        .compactMap({ $0 })
        .first(where: { !$0.isEmpty })
    else {
        throw NSError(
            domain: "AgentLensMetadataTests", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "no approved test scratch root is available"]
        )
    }
    let base = URL(fileURLWithPath: basePath, isDirectory: true).resolvingSymlinksInPath()
    let root = base.appendingPathComponent(
        "agentlens-m9a-r1-\(label)-\(UUID().uuidString)", isDirectory: true
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root.resolvingSymlinksInPath()
}

private func runIsolatedProcess(
    _ process: Process,
    captureDirectory: URL,
    label: String
) throws -> (status: Int32, stdout: String, stderr: String) {
    let stdoutURL = captureDirectory.appendingPathComponent("\(label)-stdout")
    let stderrURL = captureDirectory.appendingPathComponent("\(label)-stderr")
    try Data().write(to: stdoutURL)
    try Data().write(to: stderrURL)
    let stdout = try FileHandle(forWritingTo: stdoutURL)
    let stderr = try FileHandle(forWritingTo: stderrURL)
    defer {
        try? stdout.close()
        try? stderr.close()
        try? FileManager.default.removeItem(at: stdoutURL)
        try? FileManager.default.removeItem(at: stderrURL)
    }
    process.standardOutput = stdout
    process.standardError = stderr
    let exited = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in exited.signal() }
    try process.run()
    try stdout.close()
    try stderr.close()
    guard exited.wait(timeout: .now() + 30) == .success else {
        process.terminate()
        _ = kill(process.processIdentifier, SIGKILL)
        _ = exited.wait(timeout: .now() + 1)
        return (SIGKILL, "", "isolated process exceeded its 30-second watchdog")
    }
    let output = String(data: try Data(contentsOf: stdoutURL), encoding: .utf8) ?? ""
    let errors = String(data: try Data(contentsOf: stderrURL), encoding: .utf8) ?? ""
    return (process.terminationStatus, output, errors)
}
