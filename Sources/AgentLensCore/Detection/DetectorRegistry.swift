// DetectorRegistry — data-driven, versioned detector definitions.
// Implements D-010 (adding a tool must not require modifying the core scanner)
// and D-017 (JSON schema, settled at M4).
//
// Strict validation, fail closed: a registry file that does not match the
// schema is an error naming the offending detector — never silently skipped.

import Foundation

/// One detector definition, exactly as written in the JSON registry.
public struct DetectorDefinition: Codable, Sendable, Equatable {

    public struct Fixture: Codable, Sendable, Equatable {
        public let layout: String
        public let expectedSource: String

        public init(layout: String, expectedSource: String) {
            self.layout = layout
            self.expectedSource = expectedSource
        }
    }

    public let id: String
    public let displayName: String
    public let executableName: String
    public let extraSearchRoots: [String]
    public let fixture: Fixture?

    public init(
        id: String,
        displayName: String,
        executableName: String,
        extraSearchRoots: [String],
        fixture: Fixture?
    ) {
        self.id = id
        self.displayName = displayName
        self.executableName = executableName
        self.extraSearchRoots = extraSearchRoots
        self.fixture = fixture
    }

    /// Builds the runtime detector from this definition (M4 req. 5).
    public func makeDetector(
        versionQuery: @escaping @Sendable (String, ShellEnvironment, TimeInterval) -> String? =
            ToolDetector.queryVersion
    ) -> ToolDetector {
        ToolDetector(
            displayName: displayName,
            executableName: executableName,
            extraSearchRoots: extraSearchRoots,
            versionQuery: versionQuery
        )
    }
}

/// Registry validation errors. Each names the offending entry (M4 req. 3).
public enum DetectorRegistryError: Error, Equatable, Sendable, CustomStringConvertible {
    case missingSchemaVersion
    case unsupportedSchemaVersion(Int)
    case missingField(field: String, id: String)
    case emptyField(field: String, id: String)
    case duplicateId(String)
    case unknownLayout(String, id: String)
    case unknownExpectedSource(String, id: String)
    case badJSON(underlying: String)
    case noDetectors

    public var description: String {
        switch self {
        case .missingSchemaVersion:
            return "detector registry: missing schemaVersion"
        case .unsupportedSchemaVersion(let found):
            return "detector registry: unsupported schemaVersion \(found) (expected 1)"
        case .missingField(let field, let id):
            return "detector registry: detector '\(id)' is missing '\(field)'"
        case .emptyField(let field, let id):
            return "detector registry: detector '\(id)' has an empty '\(field)'"
        case .duplicateId(let id):
            return "detector registry: duplicate id '\(id)'"
        case .unknownLayout(let layout, let id):
            return "detector registry: '\(id)' has unknown fixture layout '\(layout)'"
        case .unknownExpectedSource(let source, let id):
            return "detector registry: '\(id)' has unknown fixture expectedSource '\(source)'"
        case .badJSON(let underlying):
            return "detector registry: invalid JSON — \(underlying)"
        case .noDetectors:
            return "detector registry: contains no detectors"
        }
    }
}

public enum DetectorRegistry {

    public static let supportedSchemaVersion = 1
    public static let knownLayouts: Set<String> = ["npmGlobal", "singleDirectory", "brewCellar"]
    public static let knownSources: Set<String> = ["npm", "brew", "standalone"]

    private struct LenientDetector {
        let index: Int
        let object: [String: Any]
    }

    /// Loads and validates the registry bundled with AgentLensCore (M4 req. 4).
    /// Throws `DetectorRegistryError` with a named cause; the CLI surfaces it
    /// on stderr and exits non-zero. No silent skipping.
    public static func loadDefault() throws -> [DetectorDefinition] {
        guard let url = Bundle.module.url(forResource: "DefaultDetectors", withExtension: "json") else {
            fatalError("DefaultDetectors.json missing from the AgentLensCore bundle — package misconfiguration")
        }
        let data = try Data(contentsOf: url)
        return try validate(data: data)
    }

    /// Strict validation of registry data (M4 req. 3). Pure — unit-tested directly.
    public static func validate(data: Data) throws -> [DetectorDefinition] {
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []),
              let root = json as? [String: Any]
        else {
            throw DetectorRegistryError.badJSON(underlying: "root is not a JSON object")
        }

        // schemaVersion: present, an integer, and supported.
        guard let versionAny = root["schemaVersion"] else {
            throw DetectorRegistryError.missingSchemaVersion
        }
        guard case let versionInt = versionAny as? Int, let version = versionInt else {
            throw DetectorRegistryError.badJSON(underlying: "schemaVersion is not an integer")
        }
        guard version == supportedSchemaVersion else {
            throw DetectorRegistryError.unsupportedSchemaVersion(version)
        }

        // detectors: a non-empty array of objects.
        guard let detectorArray = root["detectors"] as? [[String: Any]] else {
            throw DetectorRegistryError.noDetectors
        }
        guard !detectorArray.isEmpty else {
            throw DetectorRegistryError.noDetectors
        }

        var seenIds = Set<String>()
        var definitions: [DetectorDefinition] = []
        for (index, detector) in detectorArray.enumerated() {

            // id first: it names every subsequent error message.
            guard let idValue = detector["id"] as? String else {
                throw DetectorRegistryError.missingField(field: "id", id: "(detector #\(index))")
            }
            guard !idValue.isEmpty else {
                throw DetectorRegistryError.emptyField(field: "id", id: "(detector #\(index))")
            }
            let id = idValue

            guard let name = detector["displayName"] as? String else {
                throw DetectorRegistryError.missingField(field: "displayName", id: id)
            }
            guard !name.isEmpty else {
                throw DetectorRegistryError.emptyField(field: "displayName", id: id)
            }

            guard let executable = detector["executableName"] as? String else {
                throw DetectorRegistryError.missingField(field: "executableName", id: id)
            }
            guard !executable.isEmpty else {
                throw DetectorRegistryError.emptyField(field: "executableName", id: id)
            }

            guard !seenIds.contains(id) else {
                throw DetectorRegistryError.duplicateId(id)
            }
            seenIds.insert(id)

            let roots: [String]
            if let rootsAny = detector["extraSearchRoots"] {
                guard let rootsList = rootsAny as? [String] else {
                    throw DetectorRegistryError.badJSON(
                        underlying: "detector '\(id)' extraSearchRoots is not a string array"
                    )
                }
                roots = rootsList
            } else {
                roots = []
            }

            var fixture: DetectorDefinition.Fixture?
            if let fixtureAny = detector["fixture"] {
                guard let fixtureObject = fixtureAny as? [String: Any],
                      let layout = fixtureObject["layout"] as? String,
                      let expectedSource = fixtureObject["expectedSource"] as? String
                else {
                    throw DetectorRegistryError.badJSON(
                        underlying: "detector '\(id)' fixture must be an object with string 'layout' and 'expectedSource'"
                    )
                }
                guard knownLayouts.contains(layout) else {
                    throw DetectorRegistryError.unknownLayout(layout, id: id)
                }
                guard knownSources.contains(expectedSource) else {
                    throw DetectorRegistryError.unknownExpectedSource(expectedSource, id: id)
                }
                fixture = DetectorDefinition.Fixture(layout: layout, expectedSource: expectedSource)
            }

            definitions.append(
                DetectorDefinition(
                    id: id,
                    displayName: name,
                    executableName: executable,
                    extraSearchRoots: roots,
                    fixture: fixture
                )
            )
        }
        return definitions
    }
}
