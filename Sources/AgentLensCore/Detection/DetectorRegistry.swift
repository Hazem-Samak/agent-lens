// DetectorRegistry — data-driven, versioned detector definitions.
// Implements D-010 (adding a tool must not require modifying the core scanner)
// and D-017 (JSON schema, settled at M4; schema 2 at M9-A).
//
// Strict validation, fail closed: a registry file that does not match the
// schema is an error naming the offending detector — never silently skipped.
// Schema 1 is rejected outright; there is no compatibility shim.

import CoreFoundation
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

        enum CodingKeys: String, CodingKey, CaseIterable {
            case layout
            case expectedSource
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let allowed = Set(CodingKeys.allCases.map(\.stringValue))
            if let unknown = try firstUnknownDetectorKey(in: decoder, allowed: allowed) {
                throw DetectorRegistryError.unknownKey(key: "fixture.\(unknown)", id: "(detector)")
            }
            let layout = try container.decode(String.self, forKey: .layout)
            let expectedSource = try container.decode(String.self, forKey: .expectedSource)
            self.init(layout: layout, expectedSource: expectedSource)
        }
    }

    public let id: String
    public let displayName: String
    public let executableName: String
    public let extraSearchRoots: [String]
    public let fixture: Fixture?
    public let category: ToolCategory
    public let packages: [DeclaredPackage]
    public let informationURL: URL?
    public let uninstallInstructionsURL: URL?
    public let versionQuery: VersionQuerySpecification

    /// Canonical validated construction. Direct callers cannot create a definition
    /// whose package, link, fixture or version-query values would be unusable.
    public init(
        id: String,
        displayName: String,
        executableName: String,
        extraSearchRoots: [String],
        fixture: Fixture?,
        category: ToolCategory,
        packages: [DeclaredPackage],
        informationURL: URL?,
        uninstallInstructionsURL: URL?,
        versionQuery: VersionQuerySpecification
    ) throws {
        guard !id.isEmpty else {
            throw DetectorRegistryError.emptyField(field: "id", id: id)
        }
        guard !displayName.isEmpty else {
            throw DetectorRegistryError.emptyField(field: "displayName", id: id)
        }
        guard !executableName.isEmpty else {
            throw DetectorRegistryError.emptyField(field: "executableName", id: id)
        }
        if let fixture {
            guard DetectorRegistry.knownLayouts.contains(fixture.layout) else {
                throw DetectorRegistryError.unknownLayout(fixture.layout, id: id)
            }
            guard DetectorRegistry.knownSources.contains(fixture.expectedSource) else {
                throw DetectorRegistryError.unknownExpectedSource(fixture.expectedSource, id: id)
            }
        }
        var seenPackages = Set<String>()
        for package in packages {
            let key = "\(package.manager.rawValue)\u{0}\(package.name)"
            guard seenPackages.insert(key).inserted else {
                throw DetectorRegistryError.duplicatePackage(
                    manager: package.manager.rawValue,
                    name: package.name,
                    id: id
                )
            }
        }
        if let informationURL,
           !DetectorMetadataValidation.isValidHTTPSURL(informationURL)
        {
            throw DetectorRegistryError.invalidField(
                field: "informationURL",
                id: id,
                reason: "must be an HTTPS URL with a host and no user information"
            )
        }
        if let uninstallInstructionsURL,
           !DetectorMetadataValidation.isValidHTTPSURL(uninstallInstructionsURL)
        {
            throw DetectorRegistryError.invalidField(
                field: "uninstallInstructionsURL",
                id: id,
                reason: "must be an HTTPS URL with a host and no user information"
            )
        }

        self.id = id
        self.displayName = displayName
        self.executableName = executableName
        self.extraSearchRoots = extraSearchRoots
        self.fixture = fixture
        self.category = category
        self.packages = packages
        self.informationURL = informationURL
        self.uninstallInstructionsURL = uninstallInstructionsURL
        self.versionQuery = versionQuery
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case displayName
        case executableName
        case extraSearchRoots
        case fixture
        case category
        case packages
        case informationURL
        case uninstallInstructionsURL
        case versionQuery
    }

    /// Decoding preserves the same invariants as JSON registry validation. Unknown
    /// keys are rejected at this level; nested metadata decoders reject their own.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let allowed = Set(CodingKeys.allCases.map(\.stringValue))
        if let unknownKey = try firstUnknownDetectorKey(in: decoder, allowed: allowed) {
            let id = (try? container.decode(String.self, forKey: .id)) ?? "(detector)"
            throw DetectorRegistryError.unknownKey(key: unknownKey, id: id)
        }

        let id = try Self.requiredString(container, .id, field: "id", id: "(detector)")
        let displayName = try Self.requiredString(container, .displayName, field: "displayName", id: id)
        let executableName = try Self.requiredString(container, .executableName, field: "executableName", id: id)

        let extraSearchRoots: [String]
        do {
            extraSearchRoots = try container.decodeIfPresent([String].self, forKey: .extraSearchRoots) ?? []
        } catch {
            throw DetectorRegistryError.invalidField(
                field: "extraSearchRoots",
                id: id,
                reason: "must be a string array"
            )
        }

        let fixture: Fixture?
        do {
            fixture = try container.decodeIfPresent(Fixture.self, forKey: .fixture)
        } catch let error as DetectorRegistryError {
            throw DetectorRegistryError.invalidField(
                field: "fixture",
                id: id,
                reason: error.validationDetail ?? error.description
            )
        } catch {
            throw DetectorRegistryError.invalidField(
                field: "fixture",
                id: id,
                reason: "must be an object with string layout and expectedSource"
            )
        }

        let rawCategory = try Self.requiredString(container, .category, field: "category", id: id)
        guard let category = ToolCategory(rawValue: rawCategory) else {
            throw DetectorRegistryError.invalidField(
                field: "category",
                id: id,
                reason: "must be one of aiAgent, aiCodingTool, aiHarness"
            )
        }

        let decodedPackages: [DeclaredPackage]?
        do {
            decodedPackages = try container.decodeIfPresent([DeclaredPackage].self, forKey: .packages)
        } catch let error as DetectorRegistryError {
            throw DetectorRegistryError.invalidField(
                field: "packages",
                id: id,
                reason: error.validationDetail ?? error.description
            )
        } catch {
            throw DetectorRegistryError.invalidField(
                field: "packages",
                id: id,
                reason: "must be an array of package objects"
            )
        }
        guard let packages = decodedPackages else {
            throw DetectorRegistryError.missingField(field: "packages", id: id)
        }

        let informationURL = try Self.optionalURL(
            container, .informationURL, field: "informationURL", id: id
        )
        let uninstallInstructionsURL = try Self.optionalURL(
            container, .uninstallInstructionsURL, field: "uninstallInstructionsURL", id: id
        )

        let decodedVersionQuery: VersionQuerySpecification?
        do {
            decodedVersionQuery = try container.decodeIfPresent(
                VersionQuerySpecification.self, forKey: .versionQuery
            )
        } catch let error as DetectorRegistryError {
            throw DetectorRegistryError.invalidField(
                field: "versionQuery",
                id: id,
                reason: error.validationDetail ?? error.description
            )
        } catch {
            throw DetectorRegistryError.invalidField(
                field: "versionQuery",
                id: id,
                reason: "must be an object with arguments, stream and line"
            )
        }
        guard let versionQuery = decodedVersionQuery else {
            throw DetectorRegistryError.missingField(field: "versionQuery", id: id)
        }

        try self.init(
            id: id,
            displayName: displayName,
            executableName: executableName,
            extraSearchRoots: extraSearchRoots,
            fixture: fixture,
            category: category,
            packages: packages,
            informationURL: informationURL,
            uninstallInstructionsURL: uninstallInstructionsURL,
            versionQuery: versionQuery
        )
    }

    private static func requiredString<K: CodingKey>(
        _ container: KeyedDecodingContainer<K>,
        _ key: K,
        field: String,
        id: String
    ) throws -> String {
        let value: String?
        do {
            value = try container.decodeIfPresent(String.self, forKey: key)
        } catch {
            throw DetectorRegistryError.invalidField(field: field, id: id, reason: "must be a string")
        }
        guard let value else {
            throw DetectorRegistryError.missingField(field: field, id: id)
        }
        guard !value.isEmpty else {
            throw DetectorRegistryError.emptyField(field: field, id: id)
        }
        return value
    }

    private static func optionalURL<K: CodingKey>(
        _ container: KeyedDecodingContainer<K>,
        _ key: K,
        field: String,
        id: String
    ) throws -> URL? {
        let value: String?
        do {
            value = try container.decodeIfPresent(String.self, forKey: key)
        } catch {
            throw DetectorRegistryError.invalidField(
                field: field, id: id, reason: "must be an HTTPS URL string"
            )
        }
        guard let value else { return nil }
        guard let url = DetectorMetadataValidation.validatedHTTPSURL(value) else {
            throw DetectorRegistryError.invalidField(
                field: field,
                id: id,
                reason: "must be an HTTPS URL with a host and no user information"
            )
        }
        return url
    }

    /// Builds the runtime detector from this definition (M4 req. 5), using this
    /// definition's bounded version-query specification in the production path.
    public func makeDetector(
        versionQuery: @escaping @Sendable (
            String, ShellEnvironment, TimeInterval, VersionQuerySpecification
        ) -> String? = ToolDetector.queryVersion
    ) -> ToolDetector {
        ToolDetector(
            displayName: displayName,
            executableName: executableName,
            extraSearchRoots: extraSearchRoots,
            versionQuerySpecification: self.versionQuery,
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
    case unknownKey(key: String, id: String?)
    case invalidField(field: String, id: String, reason: String)
    case duplicatePackage(manager: String, name: String, id: String)
    case unknownLayout(String, id: String)
    case unknownExpectedSource(String, id: String)
    case badJSON(underlying: String)
    case noDetectors

    public var description: String {
        switch self {
        case .missingSchemaVersion:
            return "detector registry: missing schemaVersion"
        case .unsupportedSchemaVersion(let found):
            return "detector registry: unsupported schemaVersion \(found) (expected 2)"
        case .missingField(let field, let id):
            return "detector registry: detector '\(id)' is missing '\(field)'"
        case .emptyField(let field, let id):
            return "detector registry: detector '\(id)' has an empty '\(field)'"
        case .duplicateId(let id):
            return "detector registry: duplicate id '\(id)'"
        case .unknownKey(let key, let id):
            if let id {
                return "detector registry: detector '\(id)' has unknown key '\(key)'"
            }
            return "detector registry: unknown root key '\(key)'"
        case .invalidField(let field, let id, let reason):
            return "detector registry: detector '\(id)' has invalid '\(field)': \(reason)"
        case .duplicatePackage(let manager, let name, let id):
            return "detector registry: detector '\(id)' declares duplicate package '\(manager):\(name)'"
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

    /// The reason text for a nested invalid-field error, used when re-wrapping a
    /// nested metadata error with the owning detector's id.
    var validationDetail: String? {
        switch self {
        case .invalidField(_, _, let reason):
            return reason
        case .unknownKey(let key, _):
            return "unknown key '\(key)'"
        case .missingField(let field, _):
            return "missing '\(field)'"
        case .emptyField(let field, _):
            return "empty '\(field)'"
        case .duplicatePackage(let manager, let name, _):
            return "duplicate package '\(manager):\(name)'"
        default:
            return nil
        }
    }
}

public enum DetectorRegistry {

    public static let supportedSchemaVersion = 2
    public static let knownLayouts: Set<String> = ["npmGlobal", "singleDirectory", "brewCellar"]
    public static let knownSources: Set<String> = ["npm", "brew", "standalone"]

    private static let rootKeys: Set<String> = ["schemaVersion", "detectors"]
    private static let definitionKeys: Set<String> = [
        "id", "displayName", "executableName", "extraSearchRoots", "fixture",
        "category", "packages", "informationURL", "uninstallInstructionsURL", "versionQuery",
    ]
    private static let fixtureKeys: Set<String> = ["layout", "expectedSource"]
    private static let packageKeys: Set<String> = ["manager", "name"]
    private static let versionQueryKeys: Set<String> = ["arguments", "stream", "line"]

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
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw DetectorRegistryError.badJSON(underlying: error.localizedDescription)
        }
        guard let root = json as? [String: Any] else {
            throw DetectorRegistryError.badJSON(underlying: "root is not a JSON object")
        }

        // schemaVersion: present, an integer (never a bool or fraction), and supported.
        guard let versionAny = root["schemaVersion"] else {
            throw DetectorRegistryError.missingSchemaVersion
        }
        guard let version = integralSchemaVersion(versionAny) else {
            throw DetectorRegistryError.badJSON(underlying: "schemaVersion is not an integer")
        }
        guard version == supportedSchemaVersion else {
            throw DetectorRegistryError.unsupportedSchemaVersion(version)
        }
        try rejectUnknownKeys(in: root, allowed: rootKeys, id: nil)

        guard let detectorsAny = root["detectors"], !(detectorsAny is NSNull) else {
            throw DetectorRegistryError.noDetectors
        }
        guard let detectorList = detectorsAny as? [Any] else {
            throw DetectorRegistryError.invalidField(
                field: "detectors",
                id: "(registry)",
                reason: "must be an array of detector objects"
            )
        }
        guard !detectorList.isEmpty else {
            throw DetectorRegistryError.noDetectors
        }

        var seenIds = Set<String>()
        var definitions: [DetectorDefinition] = []
        for (index, element) in detectorList.enumerated() {
            let fallbackId = "(detector #\(index))"
            guard let detector = element as? [String: Any] else {
                throw DetectorRegistryError.invalidField(
                    field: "detectors[\(index)]",
                    id: fallbackId,
                    reason: "must be an object"
                )
            }

            // id first: it names every subsequent error message.
            guard let idAny = detector["id"] else {
                throw DetectorRegistryError.missingField(field: "id", id: fallbackId)
            }
            guard let idValue = idAny as? String else {
                throw DetectorRegistryError.invalidField(
                    field: "id", id: fallbackId, reason: "must be a string"
                )
            }
            guard !idValue.isEmpty else {
                throw DetectorRegistryError.emptyField(field: "id", id: fallbackId)
            }
            let id = idValue
            try rejectUnknownKeys(in: detector, allowed: definitionKeys, id: id)

            let displayName = try requiredString(detector, "displayName", id: id)
            let executableName = try requiredString(detector, "executableName", id: id)

            guard !seenIds.contains(id) else {
                throw DetectorRegistryError.duplicateId(id)
            }
            seenIds.insert(id)

            let extraSearchRoots = try optionalStringArray(detector, "extraSearchRoots", id: id)
            let fixture = try parseFixture(detector["fixture"], id: id)
            let category = try parseCategory(detector, id: id)
            let packages = try parsePackages(detector, id: id)
            let informationURL = try parseOptionalURL(detector, "informationURL", id: id)
            let uninstallInstructionsURL = try parseOptionalURL(
                detector, "uninstallInstructionsURL", id: id
            )
            let versionQuery = try parseVersionQuery(detector, id: id)

            definitions.append(
                try DetectorDefinition(
                    id: id,
                    displayName: displayName,
                    executableName: executableName,
                    extraSearchRoots: extraSearchRoots,
                    fixture: fixture,
                    category: category,
                    packages: packages,
                    informationURL: informationURL,
                    uninstallInstructionsURL: uninstallInstructionsURL,
                    versionQuery: versionQuery
                )
            )
        }
        return definitions
    }

    // MARK: Parsing helpers

    private static func integralSchemaVersion(_ value: Any) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        // JSON booleans bridge to NSNumber; a boolean is not a schema version.
        guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }

        // A decimal number preserves integer identity beyond Double's 53-bit
        // significand. Round it exactly instead of converting through Double.
        if number is NSDecimalNumber {
            let decimalNumber = number as! NSDecimalNumber
            guard decimalNumber != .notANumber else { return nil }
            var decimal = decimalNumber.decimalValue
            var rounded = Decimal()
            NSDecimalRound(&rounded, &decimal, 0, .plain)
            guard rounded == decimal else { return nil }
            guard decimal >= Decimal(Int.min), decimal <= Decimal(Int.max) else { return nil }
            return Int(decimalNumber.int64Value)
        }

        switch String(cString: number.objCType) {
        case "c", "s", "i", "l", "q":
            // Signed integer storage is already exact; Int is 64-bit here.
            return Int(number.int64Value)
        case "C", "S", "I", "L", "Q":
            // Unsigned values above Int.max are not representable and fail closed.
            let unsigned = number.uint64Value
            guard unsigned <= UInt64(Int.max) else { return nil }
            return Int(unsigned)
        case "f", "d":
            let double = number.doubleValue
            // Double(Int.max) rounds to 2^63, so use the exclusive 2^63 upper
            // bound. Values at or beyond that boundary must never reach Int(_:).
            guard double.isFinite,
                  double.rounded(.towardZero) == double,
                  double >= -9_223_372_036_854_775_808.0,
                  double < 9_223_372_036_854_775_808.0
            else {
                return nil
            }
            return Int(double)
        default:
            return nil
        }
    }

    private static func rejectUnknownKeys(
        in object: [String: Any],
        allowed: Set<String>,
        id: String?,
        prefix: String = ""
    ) throws {
        guard let unknown = object.keys
            .filter({ !allowed.contains($0) })
            .sorted()
            .first
        else {
            return
        }
        throw DetectorRegistryError.unknownKey(key: prefix + unknown, id: id)
    }

    private static func requiredString(
        _ object: [String: Any],
        _ key: String,
        field: String? = nil,
        id: String
    ) throws -> String {
        let field = field ?? key
        guard let value = object[key] else {
            throw DetectorRegistryError.missingField(field: field, id: id)
        }
        guard let text = value as? String else {
            throw DetectorRegistryError.invalidField(
                field: field, id: id, reason: "must be a string"
            )
        }
        guard !text.isEmpty else {
            throw DetectorRegistryError.emptyField(field: field, id: id)
        }
        return text
    }

    private static func optionalStringArray(
        _ object: [String: Any],
        _ key: String,
        id: String
    ) throws -> [String] {
        guard let value = object[key], !(value is NSNull) else { return [] }
        guard let list = value as? [Any] else {
            throw DetectorRegistryError.invalidField(
                field: key, id: id, reason: "must be a string array"
            )
        }
        var result: [String] = []
        for (index, element) in list.enumerated() {
            guard let string = element as? String else {
                throw DetectorRegistryError.invalidField(
                    field: "\(key)[\(index)]", id: id, reason: "must be a string"
                )
            }
            result.append(string)
        }
        return result
    }

    private static func parseFixture(
        _ value: Any?,
        id: String
    ) throws -> DetectorDefinition.Fixture? {
        guard let value, !(value is NSNull) else { return nil }
        guard let object = value as? [String: Any] else {
            throw DetectorRegistryError.invalidField(
                field: "fixture", id: id, reason: "must be an object"
            )
        }
        try rejectUnknownKeys(in: object, allowed: fixtureKeys, id: id, prefix: "fixture.")
        let layout = try requiredString(object, "layout", field: "fixture.layout", id: id)
        let expectedSource = try requiredString(
            object, "expectedSource", field: "fixture.expectedSource", id: id
        )
        guard knownLayouts.contains(layout) else {
            throw DetectorRegistryError.unknownLayout(layout, id: id)
        }
        guard knownSources.contains(expectedSource) else {
            throw DetectorRegistryError.unknownExpectedSource(expectedSource, id: id)
        }
        return DetectorDefinition.Fixture(layout: layout, expectedSource: expectedSource)
    }

    private static func parseCategory(
        _ object: [String: Any],
        id: String
    ) throws -> ToolCategory {
        let raw = try requiredString(object, "category", id: id)
        guard let category = ToolCategory(rawValue: raw) else {
            throw DetectorRegistryError.invalidField(
                field: "category",
                id: id,
                reason: "must be one of aiAgent, aiCodingTool, aiHarness"
            )
        }
        return category
    }

    private static func parsePackages(
        _ object: [String: Any],
        id: String
    ) throws -> [DeclaredPackage] {
        guard let value = object["packages"] else {
            throw DetectorRegistryError.missingField(field: "packages", id: id)
        }
        guard let list = value as? [Any] else {
            throw DetectorRegistryError.invalidField(
                field: "packages", id: id, reason: "must be an array of package objects"
            )
        }
        var packages: [DeclaredPackage] = []
        for (index, element) in list.enumerated() {
            let field = "packages[\(index)]"
            guard let packageObject = element as? [String: Any] else {
                throw DetectorRegistryError.invalidField(
                    field: field, id: id, reason: "must be an object"
                )
            }
            try rejectUnknownKeys(in: packageObject, allowed: packageKeys, id: id, prefix: "\(field).")
            let rawManager = try requiredString(
                packageObject, "manager", field: "\(field).manager", id: id
            )
            guard let manager = PackageManager(rawValue: rawManager) else {
                throw DetectorRegistryError.invalidField(
                    field: "\(field).manager",
                    id: id,
                    reason: "must be one of npm, homebrewFormula, homebrewCask"
                )
            }
            let name = try requiredString(packageObject, "name", field: "\(field).name", id: id)
            do {
                packages.append(try DeclaredPackage(manager: manager, name: name))
            } catch let error as DetectorRegistryError {
                throw DetectorRegistryError.invalidField(
                    field: "\(field).name",
                    id: id,
                    reason: error.validationDetail ?? "invalid package name"
                )
            }
        }
        return packages
    }

    private static func parseOptionalURL(
        _ object: [String: Any],
        _ key: String,
        id: String
    ) throws -> URL? {
        guard let value = object[key], !(value is NSNull) else { return nil }
        guard let text = value as? String else {
            throw DetectorRegistryError.invalidField(
                field: key, id: id, reason: "must be an HTTPS URL string"
            )
        }
        guard let url = DetectorMetadataValidation.validatedHTTPSURL(text) else {
            throw DetectorRegistryError.invalidField(
                field: key,
                id: id,
                reason: "must be an HTTPS URL with a host and no user information"
            )
        }
        return url
    }

    private static func parseVersionQuery(
        _ object: [String: Any],
        id: String
    ) throws -> VersionQuerySpecification {
        guard let value = object["versionQuery"] else {
            throw DetectorRegistryError.missingField(field: "versionQuery", id: id)
        }
        guard let query = value as? [String: Any] else {
            throw DetectorRegistryError.invalidField(
                field: "versionQuery", id: id, reason: "must be an object"
            )
        }
        try rejectUnknownKeys(in: query, allowed: versionQueryKeys, id: id, prefix: "versionQuery.")

        guard let argumentsValue = query["arguments"] else {
            throw DetectorRegistryError.missingField(field: "versionQuery.arguments", id: id)
        }
        guard let argumentList = argumentsValue as? [Any] else {
            throw DetectorRegistryError.invalidField(
                field: "versionQuery.arguments", id: id, reason: "must be a string array"
            )
        }
        var arguments: [String] = []
        for (index, element) in argumentList.enumerated() {
            guard let argument = element as? String else {
                throw DetectorRegistryError.invalidField(
                    field: "versionQuery.arguments[\(index)]",
                    id: id,
                    reason: "must be a string"
                )
            }
            arguments.append(argument)
        }

        let rawStream = try requiredString(
            query, "stream", field: "versionQuery.stream", id: id
        )
        guard let stream = VersionQuerySpecification.Stream(rawValue: rawStream) else {
            throw DetectorRegistryError.invalidField(
                field: "versionQuery.stream",
                id: id,
                reason: "must be one of stdout, stderr"
            )
        }
        let rawLine = try requiredString(query, "line", field: "versionQuery.line", id: id)
        guard let line = VersionQuerySpecification.LineSelection(rawValue: rawLine) else {
            throw DetectorRegistryError.invalidField(
                field: "versionQuery.line",
                id: id,
                reason: "must be one of first, firstNonempty"
            )
        }

        do {
            return try VersionQuerySpecification(arguments: arguments, stream: stream, line: line)
        } catch let error as DetectorRegistryError {
            throw DetectorRegistryError.invalidField(
                field: "versionQuery.arguments",
                id: id,
                reason: error.validationDetail ?? "invalid arguments"
            )
        }
    }
}
