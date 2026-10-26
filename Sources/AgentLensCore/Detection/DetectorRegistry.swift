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

/// Internal failure for app-declared registry resource location (M10-A R8).
///
/// Deliberately NOT a `DetectorRegistryError` case and not public: registry *data* validation
/// errors keep their exact public vocabulary, while a broken app resource declaration — a
/// packaging/metadata defect, not a registry defect — is reported in its own narrow type. Each
/// case names the defect without echoing absolute paths. Callers that only catch
/// `DetectorRegistryError` therefore fail closed on these (the frozen preflight reports them as
/// an unexpected registry load error and exits 1, which is accepted).
internal enum AppRegistryResourceError: Error, Equatable, Sendable, CustomStringConvertible {
    /// One marker key present, the other absent.
    case incompleteMarkers(missingKey: String)
    /// A marker key present with a non-string or empty value.
    case invalidMarker(key: String, reason: String)
    /// The path marker is not exactly `Contents/Resources/<safe-stem>.bundle`.
    case unsafePath(String)
    /// The two markers disagree about the bundle.
    case inconsistentMarkers
    /// The app resource root is not physically owned by the running app.
    case resourceRootEscapesApp
    /// The declared bundle is missing, or is not contained in the app's resource root.
    case bundleNotContained(String)
    /// The declared bundle directory is missing or is not a directory.
    case bundleMissing
    /// The bundle is a symlink escape or not a regular readable file for the registry.
    case resourceNotReadable(String)
    /// Injected test context is incomplete: an argument was supplied without its companion.
    case missingInjectedContext(String)

    var description: String {
        switch self {
        case .incompleteMarkers(let key):
            return "app registry resource: incomplete marker pair (missing '\(key)')"
        case .invalidMarker(let key, let reason):
            return "app registry resource: invalid marker '\(key)': \(reason)"
        case .unsafePath(let reason):
            return "app registry resource: unsafe bundle path: \(reason)"
        case .inconsistentMarkers:
            return "app registry resource: name and path markers are inconsistent"
        case .resourceRootEscapesApp:
            return "app registry resource: app resource root escapes the app bundle"
        case .bundleNotContained(let reason):
            return "app registry resource: bundle escapes the app resource root: \(reason)"
        case .bundleMissing:
            return "app registry resource: declared resource bundle is missing"
        case .resourceNotReadable(let reason):
            return "app registry resource: registry file is not readable: \(reason)"
        case .missingInjectedContext(let name):
            return "app registry resource: injected context is missing '\(name)'"
        }
    }
}

/// Locates the registry resource the running app declares in its `Info.plist` (M10-A R8).
///
/// Pure with respect to injected inputs: it never reads the environment, never changes the
/// working directory and never consults `Bundle.module`. Both marker keys are authoritative;
/// when neither is present it reports `.absent` so the caller can use the legacy lookup.
internal enum AppRegistryResourceLocator {

    enum Outcome: Equatable {
        case absent
        case declared(URL)
    }

    static let nameKey = "AgentLensCoreResourceBundleName"
    static let pathKey = "AgentLensCoreResourceBundlePath"
    static let registryFile = "DefaultDetectors.json"

    /// The COMPILED identity of AgentLensCore's resource bundle.
    ///
    /// This is a source-owned project contract, not a heuristic: `Package.swift` names the package
    /// `AgentLens` and the target `AgentLensCore`, and SwiftPM derives the bundle name as
    /// `<package>_<target>`. Core's own registry therefore always lives in this bundle inside the
    /// app, and the `Info.plist` marker pair never selects it. The markers remain authoritative
    /// for whether the app branch applies and for declaration validity; they are a branch and
    /// validity signal, NOT the source of Core's resource identity.
    ///
    /// A rename of the package or target must fail the real builder and the packaged preflight
    /// closed, and requires a reviewed update here — never a guessed fallback, never a directory
    /// search, never a second candidate.
    static let compiledBundleStem = "AgentLens_AgentLensCore"

    private static let resourcesPrefix = "Contents/Resources/"
    private static let bundleSuffix = ".bundle"

    /// Whether this dictionary declares either registry marker at all.
    static func declaresMarkers(in infoDictionary: [String: Any]) -> Bool {
        infoDictionary[nameKey] != nil || infoDictionary[pathKey] != nil
    }

    static func locate(
        infoDictionary: [String: Any],
        appBundleURL: URL,
        appResourceURL: URL?
    ) throws -> Outcome {
        let rawName = infoDictionary[nameKey]
        let rawPath = infoDictionary[pathKey]

        if rawName == nil && rawPath == nil {
            return .absent
        }
        guard let rawName else {
            throw AppRegistryResourceError.incompleteMarkers(missingKey: nameKey)
        }
        guard let rawPath else {
            throw AppRegistryResourceError.incompleteMarkers(missingKey: pathKey)
        }
        guard let name = rawName as? String else {
            throw AppRegistryResourceError.invalidMarker(key: nameKey, reason: "must be a string")
        }
        guard let path = rawPath as? String else {
            throw AppRegistryResourceError.invalidMarker(key: pathKey, reason: "must be a string")
        }
        guard !name.isEmpty else {
            throw AppRegistryResourceError.invalidMarker(key: nameKey, reason: "must not be empty")
        }
        guard !path.isEmpty else {
            throw AppRegistryResourceError.invalidMarker(key: pathKey, reason: "must not be empty")
        }

        // Name: one safe path component. Separators, traversal, control characters and a
        // literal `.bundle` suffix in the name are all refusals.
        if name.contains("/") || name.contains("\\") || name.contains("\u{0}") {
            throw AppRegistryResourceError.invalidMarker(key: nameKey, reason: "must be a single path component")
        }
        if name == "." || name == ".." || name.hasPrefix(".") {
            throw AppRegistryResourceError.invalidMarker(key: nameKey, reason: "must not be a dot component")
        }
        if name.unicodeScalars.contains(where: { scalar in
            scalar.properties.generalCategory == .control
                || CharacterSet.whitespacesAndNewlines.contains(scalar)
        }) {
            throw AppRegistryResourceError.invalidMarker(key: nameKey, reason: "must not contain whitespace or control characters")
        }
        if name.hasSuffix(bundleSuffix) {
            throw AppRegistryResourceError.invalidMarker(key: nameKey, reason: "must not carry the .bundle suffix")
        }

        let bundleFilename = name + bundleSuffix
        let expectedPath = resourcesPrefix + bundleFilename

        // Path: lexical validation only at this point; physical containment is checked below.
        if path.hasPrefix("/") || path.contains("..") {
            throw AppRegistryResourceError.unsafePath("must be relative with no traversal")
        }
        guard path == expectedPath else {
            throw AppRegistryResourceError.inconsistentMarkers
        }

        // Physical containment 1: the app's own resource root must be physically inside the
        // app bundle. The marker pair's declaration is then checked for containment too.
        let roots = try resolvedAppRoots(appBundleURL: appBundleURL, appResourceURL: appResourceURL)
        let declaredURL = roots.app.appendingPathComponent(path, isDirectory: true)
        let resolvedBundle = declaredURL.resolvingSymlinksInPath().standardizedFileURL
        guard contains(resolvedBundle, roots.resource) else {
            throw AppRegistryResourceError.bundleNotContained("resolved path is outside Contents/Resources")
        }
        _ = try registryFile(inBundle: resolvedBundle)
        return .declared(resolvedBundle)
    }

    /// Resolves Core's own registry file inside the COMPILED bundle under the app's resource
    /// root. Independent of the marker pair's value: a valid declaration pointing at some other
    /// bundle cannot redirect Core's identity, and a missing compiled bundle is a refusal rather
    /// than a fallback to the declared (possibly decoy) bundle.
    static func locateCompiledBundle(
        appBundleURL: URL,
        appResourceURL: URL?
    ) throws -> URL {
        let roots = try resolvedAppRoots(appBundleURL: appBundleURL, appResourceURL: appResourceURL)
        let compiledURL = roots.resource
            .appendingPathComponent(compiledBundleStem + ".bundle", isDirectory: true)
        let resolvedBundle = compiledURL.resolvingSymlinksInPath().standardizedFileURL
        guard contains(resolvedBundle, roots.resource) else {
            throw AppRegistryResourceError.bundleNotContained("compiled bundle is outside Contents/Resources")
        }
        return try registryFile(inBundle: resolvedBundle)
    }

    /// The app bundle and its resource root, both physically owned by the running app.
    private static func resolvedAppRoots(
        appBundleURL: URL,
        appResourceURL: URL?
    ) throws -> (app: URL, resource: URL) {
        guard let appResourceURL else {
            throw AppRegistryResourceError.resourceRootEscapesApp
        }
        let resolvedApp = appBundleURL.resolvingSymlinksInPath().standardizedFileURL
        let resolvedResource = appResourceURL.resolvingSymlinksInPath().standardizedFileURL
        let expectedRoot = resolvedApp
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .standardizedFileURL
        guard resolvedResource == expectedRoot else {
            throw AppRegistryResourceError.resourceRootEscapesApp
        }
        guard contains(resolvedResource, resolvedApp) else {
            throw AppRegistryResourceError.resourceRootEscapesApp
        }
        return (resolvedApp, resolvedResource)
    }

    /// The registry file inside one bundle directory, contained and a real regular readable file.
    ///
    /// Resolution uses Foundation's bundle lookup — the SAME mechanism the frozen preflight
    /// uses — because the two real generated layouts differ:
    ///   * Swift Build bundles: <Core.bundle>/Contents/Resources/DefaultDetectors.json
    ///   * native SwiftPM bundles: <Core.bundle>/DefaultDetectors.json
    /// A hand-built path would only work for one of them.
    private static func registryFile(inBundle resolvedBundle: URL) throws -> URL {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolvedBundle.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw AppRegistryResourceError.bundleMissing
        }
        guard let bundle = Bundle(url: resolvedBundle) else {
            throw AppRegistryResourceError.bundleMissing
        }
        guard let candidate = bundle.url(
            forResource: "DefaultDetectors", withExtension: "json"
        ) else {
            throw AppRegistryResourceError.resourceNotReadable("registry file is missing")
        }

        // Physically contain the SELECTED file, then require a real regular file. `lstat` is
        // used because the security-relevant question is what the path itself is, not what it
        // points at: a FIFO or device node is refused here, before any read could block.
        let resolvedFile = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard contains(resolvedFile, resolvedBundle) else {
            throw AppRegistryResourceError.resourceNotReadable("registry file escapes the declared bundle")
        }
        var info = stat()
        guard lstat(resolvedFile.path, &info) == 0 else {
            throw AppRegistryResourceError.resourceNotReadable("registry file is missing")
        }
        guard (info.st_mode & S_IFMT) == S_IFREG else {
            throw AppRegistryResourceError.resourceNotReadable("registry file is not a regular file")
        }
        guard FileManager.default.isReadableFile(atPath: resolvedFile.path) else {
            throw AppRegistryResourceError.resourceNotReadable("registry file is not readable")
        }
        return resolvedFile
    }

    /// `child` is `parent` itself or a descendant of it, after both have been resolved.
    private static func contains(_ child: URL, _ parent: URL) -> Bool {
        let parentPath = parent.path
        let childPath = child.path
        return childPath == parentPath || childPath.hasPrefix(parentPath + "/")
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
    ///
    /// Resource location (M10-A R8). A packaged macOS `.app` declares a Core resource location
    /// in `Info.plist` (`AgentLensCoreResourceBundleName` / `AgentLensCoreResourceBundlePath`).
    /// When EITHER marker key is present, the app branch applies: that declaration is validated
    /// (both keys, exact `Contents/Resources/<name>.bundle`, physically contained, regular file)
    /// and any defect throws `AppRegistryResourceError`. The markers are a BRANCH and VALIDITY
    /// signal only — Core's own identity is the compiled `AgentLens_AgentLensCore` bundle, so a
    /// valid declaration naming a different bundle cannot redirect which payload Core reads.
    /// `Bundle.module` is never consulted on that branch, so a generated accessor's compile-time
    /// build-path fallback cannot mask a missing or wrong in-app resource. When BOTH keys are
    /// absent (CLI, tests, a plain build tree) the historical lazy `Bundle.module` path is used,
    /// unchanged.
    public static func loadDefault() throws -> [DetectorDefinition] {
        let data = try loadDefaultRegistryData()
        return try validate(data: data)
    }

    /// The raw bytes `loadDefault()` validates. Internal so tests exercise the same seam
    /// production calls.
    ///
    /// `lazyFallback` is the legacy `Bundle.module` lookup. It is injected so tests can count
    /// how often it is actually INVOKED (it must be exactly zero whenever either marker key is
    /// present, and exactly once when both are absent). Production passes the closure below,
    /// which keeps the historical guard and its exact fatalError text.
    static func loadDefaultRegistryData(
        infoDictionary: [String: Any]? = nil,
        mainBundleURL: URL? = nil,
        mainResourceURL: URL? = nil,
        lazyFallback: () throws -> Data = agentLensCoreBundledRegistryData
    ) throws -> Data {
        // Resolution rule: a SUPPLIED metadata dictionary is never discarded. `nil` for every
        // injected argument means "use the process's main bundle" (the production call). If any
        // argument is supplied, the supplied values are used as-is and a missing app URL is a
        // refusal — never a silent substitution of process metadata, which could hide a marker
        // present in the supplied dictionary and reach the fallback.
        let info: [String: Any]
        let appURL: URL
        let resourceRoot: URL?
        let nothingSupplied = infoDictionary == nil && mainBundleURL == nil && mainResourceURL == nil
        if nothingSupplied {
            let bundle = Bundle.main
            info = bundle.infoDictionary ?? [:]
            appURL = bundle.bundleURL
            resourceRoot = bundle.resourceURL
        } else {
            guard let suppliedInfo = infoDictionary else {
                throw AppRegistryResourceError.missingInjectedContext("infoDictionary")
            }
            info = suppliedInfo
            if let suppliedURL = mainBundleURL {
                appURL = suppliedURL
            } else if AppRegistryResourceLocator.declaresMarkers(in: suppliedInfo) {
                // A marker-present dictionary with no app URL cannot be resolved against the
                // process's own bundle: that would silently substitute unrelated metadata.
                throw AppRegistryResourceError.missingInjectedContext("mainBundleURL")
            } else {
                // No markers and no URL: unreachable for locating (the locator reports `.absent`
                // before touching the URL), so any placeholder is never read.
                appURL = URL(fileURLWithPath: "/", isDirectory: true)
            }
            resourceRoot = mainResourceURL
        }

        switch try AppRegistryResourceLocator.locate(
            infoDictionary: info,
            appBundleURL: appURL,
            appResourceURL: resourceRoot
        ) {
        case .declared:
            // The declaration is valid and physically sane, but it does NOT choose Core's
            // identity: resolve the COMPILED bundle under the same app resource root. A valid
            // declaration pointing elsewhere must still load the real Core data, so the frozen
            // preflight's own guarded-vs-loaded comparison can report its existing mismatch.
            let compiled = try AppRegistryResourceLocator.locateCompiledBundle(
                appBundleURL: appURL,
                appResourceURL: resourceRoot
            )
            return try Data(contentsOf: compiled)
        case .absent:
            // Both marker keys absent: the historical behavior, including its exact message.
            // The closure is only reached here, so a marker-present branch can never touch
            // `Bundle.module` (no generated build-path fallback, no eager lookup).
            return try lazyFallback()
        }
    }

    /// The legacy bundled lookup, unchanged in behavior and message. Reached only when the app
    /// declares no registry resource markers at all (CLI, tests, a plain build tree).
    private static func agentLensCoreBundledRegistryData() throws -> Data {
        guard let url = Bundle.module.url(forResource: "DefaultDetectors", withExtension: "json") else {
            fatalError("DefaultDetectors.json missing from the AgentLensCore bundle — package misconfiguration")
        }
        return try Data(contentsOf: url)
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
