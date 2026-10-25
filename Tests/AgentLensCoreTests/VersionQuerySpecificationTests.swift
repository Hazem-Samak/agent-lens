import Foundation
import Testing
@testable import AgentLensCore

// M9-A version-query tests: validated specifications, real scratch executables,
// stream/line selection, literal argv, and failure semantics. All fixtures live
// in approved scratch space and are launched through the production runner.

private func queryScratchRoot(_ label: String) throws -> URL {
    let environment = ProcessInfo.processInfo.environment
    guard let basePath = [environment["AGENT_LENS_TEST_SCRATCH"], environment["TMPDIR"]]
        .compactMap({ $0 })
        .first(where: { !$0.isEmpty })
    else {
        throw NSError(
            domain: "AgentLensVersionQueryTests", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "no approved test scratch root is available"]
        )
    }
    let base = URL(fileURLWithPath: basePath, isDirectory: true).resolvingSymlinksInPath()
    let root = base.appendingPathComponent(
        "agentlens-m9-query-\(label)-\(UUID().uuidString)", isDirectory: true
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root.resolvingSymlinksInPath()
}

@discardableResult
private func writeQueryExecutable(
    _ script: String,
    in directory: URL,
    named name: String = "fixture"
) throws -> String {
    let url = directory.appendingPathComponent(name)
    try Data("#!/bin/sh\n\(script)\n".utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url.path
}

private func queryEnvironment(_ root: URL) -> ShellEnvironment {
    ShellEnvironment(
        shellPath: "/bin/sh",
        pathEntries: [root.path],
        pathJoined: root.path,
        raw: ["PATH": root.path],
        isDegraded: false
    )
}

private func registryJSON(
    arguments: [String],
    stream: String = "stdout",
    line: String = "first",
    executableName: String = "fixture"
) throws -> Data {
    let argumentsJSON = String(
        decoding: try JSONEncoder().encode(arguments),
        as: UTF8.self
    )
    return Data("""
    {
      "schemaVersion": 2,
      "detectors": [
        {
          "id": "fixture",
          "displayName": "Fixture",
          "executableName": "\(executableName)",
          "category": "aiAgent",
          "packages": [],
          "versionQuery": {
            "arguments": \(argumentsJSON),
            "stream": "\(stream)",
            "line": "\(line)"
          }
        }
      ]
    }
    """.utf8)
}

private func queryError(_ data: Data) -> DetectorRegistryError? {
    do {
        _ = try DetectorRegistry.validate(data: data)
        return nil
    } catch let error as DetectorRegistryError {
        return error
    } catch {
        return nil
    }
}

// MARK: Direct construction boundaries

@Test func versionQuerySpecificationRejectsInvalidArgumentsAtConstruction() {
    #expect(throws: DetectorRegistryError.self) {
        _ = try VersionQuerySpecification(arguments: [], stream: .stdout, line: .first)
    }
    #expect(throws: DetectorRegistryError.self) {
        _ = try VersionQuerySpecification(
            arguments: Array(repeating: "x", count: 9), stream: .stdout, line: .first
        )
    }
    #expect(throws: DetectorRegistryError.self) {
        _ = try VersionQuerySpecification(arguments: [""], stream: .stdout, line: .first)
    }
    #expect(throws: DetectorRegistryError.self) {
        _ = try VersionQuerySpecification(arguments: ["a\u{0}b"], stream: .stdout, line: .first)
    }
    #expect(throws: DetectorRegistryError.self) {
        _ = try VersionQuerySpecification(
            arguments: [String(repeating: "a", count: 257)],
            stream: .stderr,
            line: .firstNonempty
        )
    }
    #expect(throws: DetectorRegistryError.self) {
        _ = try VersionQuerySpecification(
            arguments: Array(repeating: String(repeating: "a", count: 256), count: 5),
            stream: .stdout,
            line: .first
        )
    }

    let boundary = try? VersionQuerySpecification(
        arguments: Array(repeating: String(repeating: "a", count: 256), count: 4),
        stream: .stderr,
        line: .firstNonempty
    )
    #expect(boundary != nil)
}

@Test func registryRejectsInvalidVersionQueryFieldsWithNamedFields() {
    func expectField(_ data: Data, _ field: String) {
        guard case .invalidField(let actual, let id, _) = queryError(data) else {
            Issue.record("expected invalidField for \(field)")
            return
        }
        #expect(actual == field)
        #expect(id == "fixture")
    }

    expectField(
        Data(#"{"schemaVersion":2,"detectors":[{"id":"fixture","displayName":"Fixture","executableName":"fixture","category":"aiAgent","packages":[],"versionQuery":{"arguments":[],"stream":"stdout","line":"first"}}]}"#.utf8),
        "versionQuery.arguments"
    )
    expectField(
        Data(#"{"schemaVersion":2,"detectors":[{"id":"fixture","displayName":"Fixture","executableName":"fixture","category":"aiAgent","packages":[],"versionQuery":{"arguments":["x"],"stream":"both","line":"first"}}]}"#.utf8),
        "versionQuery.stream"
    )
    expectField(
        Data(#"{"schemaVersion":2,"detectors":[{"id":"fixture","displayName":"Fixture","executableName":"fixture","category":"aiAgent","packages":[],"versionQuery":{"arguments":["x"],"stream":"stdout","line":"last"}}]}"#.utf8),
        "versionQuery.line"
    )
    #expect(
        queryError(
            Data(#"{"schemaVersion":2,"detectors":[{"id":"fixture","displayName":"Fixture","executableName":"fixture","category":"aiAgent","packages":[]}]}"#.utf8)
        ) == .missingField(field: "versionQuery", id: "fixture")
    )
}

// MARK: Production path through makeDetector

@Test func makeDetectorUsesRegistryArgumentsInTheProductionPath() throws {
    let root = try queryScratchRoot("arguments")
    defer { try? FileManager.default.removeItem(at: root) }
    try writeQueryExecutable(
        """
        if [ "$1" = "--version" ]; then
          printf 'wrong 9.9.9\\n'
        elif [ "$1" = "version" ]; then
          printf 'right 1.2.3\\n'
        else
          printf 'other 0.0.0\\n'
        fi
        """,
        in: root
    )

    let definitions = try DetectorRegistry.validate(
        data: registryJSON(arguments: ["version"])
    )
    let detector = try #require(definitions.first).makeDetector()
    let tool = detector.detect(in: queryEnvironment(root))

    #expect(tool.state == .installedAndOnPath)
    #expect(tool.version == "1.2.3")
}

@Test func makeDetectorUsesDeclaredStdoutAndStderrStreams() throws {
    let root = try queryScratchRoot("streams")
    defer { try? FileManager.default.removeItem(at: root) }
    try writeQueryExecutable(
        """
        printf 'stdout 1.1.1\\n'
        printf 'stderr 2.2.2\\n' >&2
        """,
        in: root
    )

    let stdoutDefinition = try #require(
        try DetectorRegistry.validate(
            data: registryJSON(arguments: ["--version"], stream: "stdout")
        ).first
    )
    let stderrDefinition = try #require(
        try DetectorRegistry.validate(
            data: registryJSON(arguments: ["--version"], stream: "stderr")
        ).first
    )

    #expect(
        stdoutDefinition.makeDetector().detect(in: queryEnvironment(root)).version == "1.1.1"
    )
    #expect(
        stderrDefinition.makeDetector().detect(in: queryEnvironment(root)).version == "2.2.2"
    )
}

@Test func firstRequiresTheFirstLineWhileFirstNonemptySkipsIntroductoryBlankLines() throws {
    let root = try queryScratchRoot("line")
    defer { try? FileManager.default.removeItem(at: root) }
    try writeQueryExecutable("printf '\\n\\n3.3.3\\n'", in: root)

    let firstDefinition = try #require(
        try DetectorRegistry.validate(data: registryJSON(arguments: ["--version"])).first
    )
    let firstNonemptyDefinition = try #require(
        try DetectorRegistry.validate(
            data: registryJSON(arguments: ["--version"], line: "firstNonempty")
        ).first
    )

    #expect(firstDefinition.makeDetector().detect(in: queryEnvironment(root)).version == nil)
    #expect(
        firstNonemptyDefinition.makeDetector().detect(in: queryEnvironment(root)).version == "3.3.3"
    )
}

@Test func firstNonemptySkipsWhitespaceAndCRLFBlankLines() throws {
    let root = try queryScratchRoot("line-whitespace")
    defer { try? FileManager.default.removeItem(at: root) }
    try writeQueryExecutable("printf '\\r\\n \\r\\n\\t\\n8.8.8\\r\\n'", in: root)

    let firstDefinition = try #require(
        try DetectorRegistry.validate(data: registryJSON(arguments: ["--version"])).first
    )
    let firstNonemptyDefinition = try #require(
        try DetectorRegistry.validate(
            data: registryJSON(arguments: ["--version"], line: "firstNonempty")
        ).first
    )

    #expect(firstDefinition.makeDetector().detect(in: queryEnvironment(root)).version == nil)
    #expect(
        firstNonemptyDefinition.makeDetector().detect(in: queryEnvironment(root)).version == "8.8.8"
    )
}

// MARK: Literal argv, not shell evaluation

@Test func queryArgumentsWithSpacesAndMetacharactersRemainLiteralArgv() throws {
    let root = try queryScratchRoot("literal-argv")
    defer { try? FileManager.default.removeItem(at: root) }
    let marker = root.appendingPathComponent("shell-evaluation-marker")
    let argvLog = root.appendingPathComponent("argv.log")
    let arguments = [
        "--flag with space",
        "$(touch \(marker.path))",
        "; echo injected",
    ]
    let argumentsJSON = String(decoding: try JSONEncoder().encode(arguments), as: UTF8.self)
    try writeQueryExecutable(
        """
        printf '%s\\n' "$@" > '\(argvLog.path)'
        if [ "$1" = "--flag with space" ] \\
           && [ "$2" = '$(touch \(marker.path))' ] \\
           && [ "$3" = "; echo injected" ]; then
          printf 'literal 4.4.4\\n'
        fi
        """,
        in: root
    )

    let data = Data("""
    {
      "schemaVersion": 2,
      "detectors": [
        {
          "id": "fixture",
          "displayName": "Fixture",
          "executableName": "fixture",
          "category": "aiAgent",
          "packages": [],
          "versionQuery": {
            "arguments": \(argumentsJSON),
            "stream": "stdout",
            "line": "first"
          }
        }
      ]
    }
    """.utf8)
    let definition = try #require(try DetectorRegistry.validate(data: data).first)
    let tool = definition.makeDetector().detect(in: queryEnvironment(root))

    #expect(tool.version == "4.4.4")
    #expect(FileManager.default.fileExists(atPath: marker.path) == false)
    let logged = try String(contentsOf: argvLog, encoding: .utf8)
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map(String.init)
    #expect(Array(logged.prefix(arguments.count)) == arguments)
}

// MARK: Failure semantics remain nil

@Test func invalidUTF8NoVersionAndNonzeroExitRemainNil() throws {
    let root = try queryScratchRoot("failures")
    defer { try? FileManager.default.removeItem(at: root) }
    let environment = queryEnvironment(root)
    let specification = VersionQuerySpecification.standard

    let invalidUTF8 = try writeQueryExecutable(
        "printf '\\377\\376'", in: root, named: "invalid-utf8"
    )
    #expect(
        ToolDetector.queryVersion(
            executablePath: invalidUTF8,
            environment: environment,
            timeout: 1,
            specification: specification
        ) == nil
    )

    let noVersion = try writeQueryExecutable(
        "printf 'nothing version-like here\\n'", in: root, named: "no-version"
    )
    #expect(
        ToolDetector.queryVersion(
            executablePath: noVersion,
            environment: environment,
            timeout: 1,
            specification: specification
        ) == nil
    )

    let nonzero = try writeQueryExecutable(
        "printf '9.8.7\\n'; exit 7", in: root, named: "nonzero"
    )
    #expect(
        ToolDetector.queryVersion(
            executablePath: nonzero,
            environment: environment,
            timeout: 1,
            specification: specification
        ) == nil
    )
}

@Test func timeoutAndOutputLimitRemainNilWithTheDeclaredSpecification() throws {
    let root = try queryScratchRoot("bounds")
    defer { try? FileManager.default.removeItem(at: root) }
    let environment = queryEnvironment(root)

    let hanging = try writeQueryExecutable(
        "exec /bin/sleep 30", in: root, named: "hanging"
    )
    let started = DispatchTime.now().uptimeNanoseconds
    let timedOut = ToolDetector.queryVersion(
        executablePath: hanging,
        environment: environment,
        timeout: 0.2,
        specification: .standard
    )
    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000
    #expect(timedOut == nil)
    #expect(elapsed >= 0.15 && elapsed < 1.0, "elapsed: \(elapsed)")

    let verbose = try writeQueryExecutable(
        "printf '9.8.7\\n'; /usr/bin/yes x | /usr/bin/head -c 1200000",
        in: root,
        named: "verbose"
    )
    #expect(
        ToolDetector.queryVersion(
            executablePath: verbose,
            environment: environment,
            timeout: 4,
            specification: .standard
        ) == nil
    )
}
