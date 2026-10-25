// BundleResourceTests — M7 stage 5: resource bundle preflight and registry schema validation tests.
// Proves real bundled loader yields valid ordered definitions and schema/JSON errors remain typed.
// M9-A migrates the fixtures to schema 2: category, packages and versionQuery are required.

import AgentLensCore
import Foundation
import Testing

@Suite("Bundle Resource and Registry Validation Tests")
struct BundleResourceTests {

    private func detectorObject(
        id: String,
        displayName: String,
        executableName: String,
        extraSearchRoots: String? = nil
    ) -> String {
        var fields = [
            #""id":"\#(id)""#,
            #""displayName":"\#(displayName)""#,
            #""executableName":"\#(executableName)""#,
            #""category":"aiAgent""#,
            #""packages":[]"#,
            #""versionQuery":{"arguments":["--version"],"stream":"stdout","line":"first"}"#,
        ]
        if let extraSearchRoots {
            fields.append(#""extraSearchRoots":\#(extraSearchRoots)"#)
        }
        return "{" + fields.joined(separator: ",") + "}"
    }

    @Test("Real bundled loader loads valid definitions in expected registry order")
    func realBundledLoaderLoadsValidDefinitions() throws {
        let definitions = try DetectorRegistry.loadDefault()
        #expect(!definitions.isEmpty)
        #expect(definitions.count == 3)
        #expect(definitions.map(\.id) == ["codex", "opencode", "grok"])
        #expect(definitions.map(\.displayName) == ["Codex", "OpenCode", "Grok CLI"])
        #expect(definitions.map(\.executableName) == ["codex", "opencode", "grok"])
        #expect(definitions.map(\.category) == [.aiAgent, .aiAgent, .aiAgent])

        for definition in definitions {
            let detector = definition.makeDetector()
            #expect(detector.displayName == definition.displayName)
            #expect(detector.executableName == definition.executableName)
            #expect(detector.extraSearchRoots == definition.extraSearchRoots)
        }
    }

    @Test("Corrupted JSON bytes throw typed badJSON error")
    func validateCorruptedJSONThrowsBadJSON() {
        let corrupted = Data("{ not valid json".utf8)
        #expect(throws: DetectorRegistryError.self) {
            try DetectorRegistry.validate(data: corrupted)
        }
    }

    @Test("Missing schemaVersion throws typed error")
    func validateMissingSchemaVersionThrows() {
        let json = Data("""
        {
          "detectors": [
            { "id": "t1", "displayName": "T1", "executableName": "t1" }
          ]
        }
        """.utf8)
        #expect(throws: DetectorRegistryError.missingSchemaVersion) {
            try DetectorRegistry.validate(data: json)
        }
    }

    @Test("Schema 1 is rejected outright")
    func validateSchemaOneIsRejected() {
        let json = Data("""
        {
          "schemaVersion": 1,
          "detectors": [
            \(detectorObject(id: "t1", displayName: "T1", executableName: "t1"))
          ]
        }
        """.utf8)
        #expect(throws: DetectorRegistryError.unsupportedSchemaVersion(1)) {
            try DetectorRegistry.validate(data: json)
        }
    }

    @Test("Unsupported schemaVersion throws typed error naming found version")
    func validateUnsupportedSchemaVersionThrows() {
        let json = Data("""
        {
          "schemaVersion": 99,
          "detectors": [
            \(detectorObject(id: "t1", displayName: "T1", executableName: "t1"))
          ]
        }
        """.utf8)
        #expect(throws: DetectorRegistryError.unsupportedSchemaVersion(99)) {
            try DetectorRegistry.validate(data: json)
        }
    }

    @Test("Empty detectors list throws noDetectors error")
    func validateEmptyDetectorsThrows() {
        let json = Data("""
        {
          "schemaVersion": 2,
          "detectors": []
        }
        """.utf8)
        #expect(throws: DetectorRegistryError.noDetectors) {
            try DetectorRegistry.validate(data: json)
        }
    }

    @Test("Missing required field throws missingField naming field and id")
    func validateMissingFieldThrows() {
        let json = Data("""
        {
          "schemaVersion": 2,
          "detectors": [
            {
              "id": "tool1",
              "displayName": "Tool 1",
              "category": "aiAgent",
              "packages": [],
              "versionQuery": { "arguments": ["--version"], "stream": "stdout", "line": "first" }
            }
          ]
        }
        """.utf8)
        #expect(throws: DetectorRegistryError.missingField(field: "executableName", id: "tool1")) {
            try DetectorRegistry.validate(data: json)
        }
    }

    @Test("Empty required field throws emptyField naming field and id")
    func validateEmptyFieldThrows() {
        let json = Data("""
        {
          "schemaVersion": 2,
          "detectors": [
            {
              "id": "tool1",
              "displayName": "",
              "executableName": "tool1",
              "category": "aiAgent",
              "packages": [],
              "versionQuery": { "arguments": ["--version"], "stream": "stdout", "line": "first" }
            }
          ]
        }
        """.utf8)
        #expect(throws: DetectorRegistryError.emptyField(field: "displayName", id: "tool1")) {
            try DetectorRegistry.validate(data: json)
        }
    }

    @Test("Duplicate detector ID throws duplicateId naming the ID")
    func validateDuplicateIDThrows() {
        let json = Data("""
        {
          "schemaVersion": 2,
          "detectors": [
            \(detectorObject(id: "dup", displayName: "D1", executableName: "d1")),
            \(detectorObject(id: "dup", displayName: "D2", executableName: "d2"))
          ]
        }
        """.utf8)
        #expect(throws: DetectorRegistryError.duplicateId("dup")) {
            try DetectorRegistry.validate(data: json)
        }
    }

    @Test("Valid synthetic registry preserves declaration order and all fields")
    func validateSyntheticRegistryPreservesOrder() throws {
        let json = Data("""
        {
          "schemaVersion": 2,
          "detectors": [
            \(detectorObject(id: "second", displayName: "Second Tool", executableName: "second", extraSearchRoots: "[\"~/.second\"]")),
            \(detectorObject(id: "first", displayName: "First Tool", executableName: "first"))
          ]
        }
        """.utf8)
        let definitions = try DetectorRegistry.validate(data: json)
        #expect(definitions.count == 2)
        #expect(definitions.map(\.id) == ["second", "first"])
        #expect(definitions[0].extraSearchRoots == ["~/.second"])
        #expect(definitions[1].extraSearchRoots.isEmpty)
        #expect(definitions.allSatisfy { $0.category == .aiAgent })
        #expect(definitions.allSatisfy { $0.versionQuery == .standard })
    }
}
