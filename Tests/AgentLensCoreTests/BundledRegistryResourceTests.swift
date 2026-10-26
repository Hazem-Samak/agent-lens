// BundledRegistryResourceTests — M10-A R8: app resource location with independent Core identity.
//
// Two separate questions are tested here:
//
// 1. BRANCH + VALIDITY. The Info.plist marker pair decides whether the app branch applies at all
//    and whether the declaration itself is well formed and physically sane. Any defect in it
//    fails closed; `Bundle.module` is never consulted on that branch (its generated native
//    accessor carries a compile-time build-path fallback that must not mask a bad app).
// 2. IDENTITY. The markers do NOT select Core's own resource identity. Core always reads the
//    COMPILED bundle `AppRegistryResourceLocator.compiledBundleStem`, which is a source-owned
//    contract tied to `Package.swift` (package `AgentLens`, target `AgentLensCore`). A valid
//    declaration pointing at some other bundle is accepted as a declaration but must still load
//    the real Core payload, so the frozen preflight can report its own mismatch message.
//
// Only when BOTH marker keys are absent does the legacy lazy `Bundle.module` path apply.
//
// Every fixture below is an owned temporary directory tree passed explicitly through the internal
// seam. Nothing here reads or mutates global state: no `Bundle.main` swap, no environment or
// working-directory change.

import Foundation
import Testing
@testable import AgentLensCore

// MARK: - Fixtures

private enum Fixture {
    /// The ACTUAL Core bundle name, read from the production constant rather than retyped, so a
    /// reviewed rename cannot silently leave these fixtures testing a bundle Core ignores.
    static var bundleName: String { AppRegistryResourceLocator.compiledBundleStem }
    static var bundlePath: String { "Contents/Resources/\(bundleName).bundle" }

    /// Two detectors in a deliberately distinctive order, so a passing load proves this payload
    /// was the one selected rather than any bundled default.
    static let customRegistry = #"""
    {
      "schemaVersion": 2,
      "detectors": [
        {
          "id": "zeta-fixture",
          "displayName": "Zeta Fixture",
          "executableName": "zeta-fixture",
          "category": "aiHarness",
          "packages": [],
          "versionQuery": { "arguments": ["--version"], "stream": "stderr", "line": "firstNonempty" }
        },
        {
          "id": "alpha-fixture",
          "displayName": "Alpha Fixture",
          "executableName": "alpha-fixture",
          "category": "aiCodingTool",
          "packages": [],
          "versionQuery": { "arguments": ["--version"], "stream": "stdout", "line": "first" }
        }
      ]
    }
    """#

    static func scratchRoot() throws -> URL {
        let environment = ProcessInfo.processInfo.environment
        guard let basePath = [environment["AGENT_LENS_TEST_SCRATCH"], environment["TMPDIR"]]
            .compactMap({ $0 })
            .first(where: { !$0.isEmpty })
        else {
            throw FixtureError.noScratchRoot
        }
        let base = URL(fileURLWithPath: basePath, isDirectory: true).resolvingSymlinksInPath()
        let dir = base.appendingPathComponent("agentlens-r8-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.resolvingSymlinksInPath()
    }

    enum FixtureError: Error { case noScratchRoot }

    /// An app whose declared bundle contains `registry` at the expected place.
    static func makeApp(
        at root: URL,
        registry: String = customRegistry,
        name: String? = nil,
        path: String? = nil
    ) throws -> AppFixture {
        let name = name ?? bundleName
        let path = path ?? bundlePath
        let app = root.appendingPathComponent("AgentLensFixture.app", isDirectory: true)
        let resources = app.appendingPathComponent("Contents/Resources", isDirectory: true)
        let bundle = resources.appendingPathComponent(name + ".bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try Data(registry.utf8).write(to: bundle.appendingPathComponent("DefaultDetectors.json"))
        return AppFixture(
            appURL: app,
            resourceURL: resources,
            bundleURL: bundle,
            info: ["AgentLensCoreResourceBundleName": name, "AgentLensCoreResourceBundlePath": path]
        )
    }

    struct AppFixture {
        let appURL: URL
        let resourceURL: URL
        let bundleURL: URL
        var info: [String: Any]

        func load() throws -> [DetectorDefinition] {
            try DetectorRegistry.validate(
                data: try DetectorRegistry.loadDefaultRegistryData(
                    infoDictionary: info,
                    mainBundleURL: appURL,
                    mainResourceURL: resourceURL
                )
            )
        }

        func loadData() throws -> Data {
            try DetectorRegistry.loadDefaultRegistryData(
                infoDictionary: info,
                mainBundleURL: appURL,
                mainResourceURL: resourceURL
            )
        }
    }
}

// MARK: - Declared resource is authoritative

@Test func declaredAppResourceSuppliesOrderedCustomPayload() throws {
    let root = try Fixture.scratchRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try Fixture.makeApp(at: root)

    let definitions = try fixture.load()
    // Order is the declaration order of THIS payload, not the bundled default order.
    #expect(definitions.map(\.id) == ["zeta-fixture", "alpha-fixture"])
    #expect(definitions.map(\.category) == [.aiHarness, .aiCodingTool])
    #expect(definitions[0].displayName == "Zeta Fixture")
}

@Test func declaredStructuredBundleLayoutIsAccepted() throws {
    // Swift Build's real bundle keeps the registry under Contents/Resources inside the
    // .bundle; native's keeps it flat. Production must accept both, so resolution goes through
    // Foundation's bundle lookup (as the frozen preflight does) instead of a hand-built path.
    let root = try Fixture.scratchRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let app = root.appendingPathComponent("Structured.app", isDirectory: true)
    let resources = app.appendingPathComponent("Contents/Resources", isDirectory: true)
    let bundle = resources.appendingPathComponent("AgentLens_AgentLensCore.bundle", isDirectory: true)
    let structured = bundle.appendingPathComponent("Contents/Resources", isDirectory: true)
    try FileManager.default.createDirectory(at: structured, withIntermediateDirectories: true)
    try Data(Fixture.customRegistry.utf8)
        .write(to: structured.appendingPathComponent("DefaultDetectors.json"))

    let data = try DetectorRegistry.loadDefaultRegistryData(
        infoDictionary: [
            "AgentLensCoreResourceBundleName": Fixture.bundleName,
            "AgentLensCoreResourceBundlePath": Fixture.bundlePath,
        ],
        mainBundleURL: app,
        mainResourceURL: resources
    )
    #expect(try DetectorRegistry.validate(data: data).map(\.id) == ["zeta-fixture", "alpha-fixture"])
}

@Test func nonRegularRegistryFileThrowsWithoutBlocking() throws {
    // A FIFO at the registry path must be refused by the regular-file check BEFORE any read.
    // If the check ever regressed to "exists && !isDirectory", Data(contentsOf:) would open the
    // FIFO and this test would hang instead of failing, so the scenario is inherently guarded.
    let root = try Fixture.scratchRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try Fixture.makeApp(at: root)

    let file = fixture.bundleURL.appendingPathComponent("DefaultDetectors.json")
    try FileManager.default.removeItem(at: file)
    #expect(mkfifo(file.path, 0o644) == 0, "failed to create the FIFO fixture")

    #expect(throws: AppRegistryResourceError.resourceNotReadable(
        "registry file is not a regular file"
    )) {
        _ = try fixture.loadData()
    }
}

@Test func declaredAppResourceMatchesItsOwnBytes() throws {
    let root = try Fixture.scratchRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try Fixture.makeApp(at: root)

    let loaded = try fixture.loadData()
    #expect(loaded == Data(Fixture.customRegistry.utf8))
}

@Test func declaredAppResourceSurvivesVarPrivateAliasing() throws {
    // /var is a symlink to /private/var on macOS. A fixture created through one spelling and
    // evaluated through the other must still be accepted: containment compares resolved paths.
    let root = try Fixture.scratchRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try Fixture.makeApp(at: root)

    let aliasApp: URL
    if fixture.appURL.path.hasPrefix("/private/var/") {
        aliasApp = URL(fileURLWithPath: String(fixture.appURL.path.dropFirst("/private".count)))
    } else {
        aliasApp = URL(fileURLWithPath: "/private" + fixture.appURL.path)
    }
    // Only assert through the alias when that spelling is a distinct existing path.
    guard aliasApp.path != fixture.appURL.path,
          FileManager.default.fileExists(atPath: aliasApp.path)
    else { return }
    let aliasResource = aliasApp.appendingPathComponent("Contents/Resources", isDirectory: true)
    let data = try DetectorRegistry.loadDefaultRegistryData(
        infoDictionary: fixture.info,
        mainBundleURL: aliasApp,
        mainResourceURL: aliasResource
    )
    #expect(try DetectorRegistry.validate(data: data).map(\.id) == ["zeta-fixture", "alpha-fixture"])
}

@Test func declaredAppResourceSurvivesSymlinkedAppAncestor() throws {
    let root = try Fixture.scratchRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try Fixture.makeApp(at: root)

    let linkRoot = root.appendingPathComponent("linked-parent", isDirectory: true)
    try FileManager.default.createSymbolicLink(at: linkRoot, withDestinationURL: root)
    defer { try? FileManager.default.removeItem(at: linkRoot) }

    let linkedApp = linkRoot.appendingPathComponent("AgentLensFixture.app", isDirectory: true)
    let linkedResource = linkedApp.appendingPathComponent("Contents/Resources", isDirectory: true)
    let data = try DetectorRegistry.loadDefaultRegistryData(
        infoDictionary: fixture.info,
        mainBundleURL: linkedApp,
        mainResourceURL: linkedResource
    )
    #expect(try DetectorRegistry.validate(data: data).map(\.id) == ["zeta-fixture", "alpha-fixture"])
}

// MARK: - Core identity is compiled, not declared
//
// A valid declaration may point at a different bundle. That is a DECLARATION fact, not
// Core's identity: Core still reads the compiled bundle, so the frozen preflight sees two
// different payloads and reports its existing mismatch. Throwing here instead would
// replace that exact message with a different failure.

/// Builds an app whose ACTUAL Core bundle holds `coreRegistry`, plus a separate, valid,
/// *declared* decoy bundle holding `decoyRegistry`.
private func makeAppWithDeclaredDecoy(
    at root: URL,
    coreRegistry: String = Fixture.customRegistry,
    decoyRegistry: String = Fixture.customRegistry,
    includeCompiled: Bool = true
) throws -> Fixture.AppFixture {
    let app = root.appendingPathComponent("AgentLensFixture.app", isDirectory: true)
    let resources = app.appendingPathComponent("Contents/Resources", isDirectory: true)
    try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)

    let coreName = AppRegistryResourceLocator.compiledBundleStem
    let coreBundle = resources.appendingPathComponent(coreName + ".bundle", isDirectory: true)
    if includeCompiled {
        try FileManager.default.createDirectory(at: coreBundle, withIntermediateDirectories: true)
        try Data(coreRegistry.utf8)
            .write(to: coreBundle.appendingPathComponent("DefaultDetectors.json"))
    }

    let decoy = resources.appendingPathComponent("decoy.bundle", isDirectory: true)
    try FileManager.default.createDirectory(at: decoy, withIntermediateDirectories: true)
    try Data(decoyRegistry.utf8)
        .write(to: decoy.appendingPathComponent("DefaultDetectors.json"))

    return Fixture.AppFixture(
        appURL: app,
        resourceURL: resources,
        bundleURL: coreBundle,
        info: [
            "AgentLensCoreResourceBundleName": "decoy",
            "AgentLensCoreResourceBundlePath": "Contents/Resources/decoy.bundle",
        ]
    )
}

/// A payload with different IDs and order from `customRegistry`, so a selected decoy is
/// distinguishable from the real Core payload by identity alone.
private let distinctDecoyRegistry = #"""
{
  "schemaVersion": 2,
  "detectors": [
    {
      "id": "decoy-only",
      "displayName": "Decoy Only",
      "executableName": "decoy-only",
      "category": "aiAgent",
      "packages": [],
      "versionQuery": { "arguments": ["--version"], "stream": "stdout", "line": "first" }
    }
  ]
}
"""#

@Test func validDeclaredDecoyLoadsCompiledCorePayloadWithoutThrowing() throws {
    // Regression for packaging case 09 Case C: paired valid markers naming a different
    // bundle used to make Core read the same decoy the preflight had already validated, so
    // the equality check falsely passed. Core must read its own compiled payload and let the
    // frozen preflight report the mismatch in its own words.
    let root = try Fixture.scratchRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try makeAppWithDeclaredDecoy(
        at: root, coreRegistry: Fixture.customRegistry, decoyRegistry: distinctDecoyRegistry
    )

    let counter = FallbackCounter()
    let data = try DetectorRegistry.loadDefaultRegistryData(
        infoDictionary: fixture.info,
        mainBundleURL: fixture.appURL,
        mainResourceURL: fixture.resourceURL,
        lazyFallback: { counter.increment(); return sentinelBytes }
    )

    #expect(data == Data(Fixture.customRegistry.utf8), "must read the compiled Core payload")
    #expect(data != Data(distinctDecoyRegistry.utf8), "must never read the declared decoy")
    #expect(counter.count == 0, "a valid declaration must not consult the fallback")
    let ids = try DetectorRegistry.validate(data: data).map(\.id)
    #expect(ids == ["zeta-fixture", "alpha-fixture"], "compiled order is preserved")
}

@Test func compiledBundleMissingWhileValidDecoyExistsThrows() throws {
    let root = try Fixture.scratchRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try makeAppWithDeclaredDecoy(
        at: root, decoyRegistry: distinctDecoyRegistry, includeCompiled: false
    )

    let counter = FallbackCounter()
    #expect(throws: AppRegistryResourceError.bundleMissing) {
        _ = try DetectorRegistry.loadDefaultRegistryData(
            infoDictionary: fixture.info,
            mainBundleURL: fixture.appURL,
            mainResourceURL: fixture.resourceURL,
            lazyFallback: { counter.increment(); return sentinelBytes }
        )
    }
    #expect(counter.count == 0, "a missing compiled bundle must not fall back")
}

@Test func customCompiledPayloadIsReadByContentAndOrder() throws {
    // A correctly placed custom registry in the compiled bundle is what an app author
    // replaces; it must be read verbatim, in declaration order, with no decoy involved.
    let root = try Fixture.scratchRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let custom = distinctDecoyRegistry
    let fixture = try Fixture.makeApp(at: root, registry: custom)

    let data = try fixture.loadData()
    #expect(data == Data(custom.utf8))
    #expect(try DetectorRegistry.validate(data: data).map(\.id) == ["decoy-only"])
}


// MARK: - Invalid metadata never falls back to Bundle.module
//
// The fallback would succeed here (the test build tree has the real resource), so a successful
// load in any of these cases would prove a silent fallback. Each must throw instead.

@Test func incompleteNameMarkerThrowsWithoutFallback() throws {
    let root = try Fixture.scratchRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    var fixture = try Fixture.makeApp(at: root)
    fixture.info.removeValue(forKey: "AgentLensCoreResourceBundleName")
    #expect(throws: AppRegistryResourceError.incompleteMarkers(missingKey: "AgentLensCoreResourceBundleName")) {
        _ = try fixture.loadData()
    }
}

@Test func incompletePathMarkerThrowsWithoutFallback() throws {
    let root = try Fixture.scratchRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    var fixture = try Fixture.makeApp(at: root)
    fixture.info.removeValue(forKey: "AgentLensCoreResourceBundlePath")
    #expect(throws: AppRegistryResourceError.incompleteMarkers(missingKey: "AgentLensCoreResourceBundlePath")) {
        _ = try fixture.loadData()
    }
}

@Test func nonStringNameMarkerThrowsWithoutFallback() throws {
    let root = try Fixture.scratchRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    var fixture = try Fixture.makeApp(at: root)
    fixture.info["AgentLensCoreResourceBundleName"] = 42
    #expect(throws: AppRegistryResourceError.invalidMarker(
        key: "AgentLensCoreResourceBundleName", reason: "must be a string"
    )) {
        _ = try fixture.loadData()
    }
}

@Test func nonStringPathMarkerThrowsWithoutFallback() throws {
    let root = try Fixture.scratchRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    var fixture = try Fixture.makeApp(at: root)
    fixture.info["AgentLensCoreResourceBundlePath"] = ["array", "not", "string"]
    #expect(throws: AppRegistryResourceError.invalidMarker(
        key: "AgentLensCoreResourceBundlePath", reason: "must be a string"
    )) {
        _ = try fixture.loadData()
    }
}

@Test func emptyMarkerValuesThrowWithoutFallback() throws {
    let root = try Fixture.scratchRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    var fixture = try Fixture.makeApp(at: root)
    fixture.info["AgentLensCoreResourceBundleName"] = ""
    #expect(throws: AppRegistryResourceError.invalidMarker(
        key: "AgentLensCoreResourceBundleName", reason: "must not be empty"
    )) {
        _ = try fixture.loadData()
    }
}

@Test func nameCarryingBundleSuffixThrowsWithoutFallback() throws {
    let root = try Fixture.scratchRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    var fixture = try Fixture.makeApp(at: root)
    fixture.info["AgentLensCoreResourceBundleName"] = Fixture.bundleName + ".bundle"
    #expect(throws: AppRegistryResourceError.invalidMarker(
        key: "AgentLensCoreResourceBundleName", reason: "must not carry the .bundle suffix"
    )) {
        _ = try fixture.loadData()
    }
}

@Test func nameWithSeparatorThrowsWithoutFallback() throws {
    let root = try Fixture.scratchRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    var fixture = try Fixture.makeApp(at: root)
    fixture.info["AgentLensCoreResourceBundleName"] = "nested/AgentLens_AgentLensCore"
    #expect(throws: AppRegistryResourceError.invalidMarker(
        key: "AgentLensCoreResourceBundleName", reason: "must be a single path component"
    )) {
        _ = try fixture.loadData()
    }
}

@Test func traversalPathMarkerThrowsWithoutFallback() throws {
    let root = try Fixture.scratchRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    var fixture = try Fixture.makeApp(at: root)
    fixture.info["AgentLensCoreResourceBundlePath"] = "Contents/Resources/../Resources/AgentLens_AgentLensCore.bundle"
    #expect(throws: AppRegistryResourceError.unsafePath("must be relative with no traversal")) {
        _ = try fixture.loadData()
    }
}

@Test func absolutePathMarkerThrowsWithoutFallback() throws {
    let root = try Fixture.scratchRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    var fixture = try Fixture.makeApp(at: root)
    fixture.info["AgentLensCoreResourceBundlePath"] = "/tmp/AgentLens_AgentLensCore.bundle"
    #expect(throws: AppRegistryResourceError.unsafePath("must be relative with no traversal")) {
        _ = try fixture.loadData()
    }
}

@Test func inconsistentMarkersThrowWithoutFallback() throws {
    let root = try Fixture.scratchRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    var fixture = try Fixture.makeApp(at: root)
    fixture.info["AgentLensCoreResourceBundlePath"] = "Contents/Resources/Other.bundle"
    #expect(throws: AppRegistryResourceError.inconsistentMarkers) {
        _ = try fixture.loadData()
    }
}

// MARK: - Resource defects fail closed

@Test func missingBundleDirectoryThrowsWithoutFallback() throws {
    let root = try Fixture.scratchRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try Fixture.makeApp(at: root)
    try FileManager.default.removeItem(at: fixture.bundleURL)
    #expect(throws: AppRegistryResourceError.bundleMissing) {
        _ = try fixture.loadData()
    }
}

@Test func missingRegistryFileThrowsWithoutFallback() throws {
    let root = try Fixture.scratchRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try Fixture.makeApp(at: root)
    try FileManager.default.removeItem(at: fixture.bundleURL.appendingPathComponent("DefaultDetectors.json"))
    #expect(throws: AppRegistryResourceError.resourceNotReadable("registry file is missing")) {
        _ = try fixture.loadData()
    }
}

@Test func registryFileThatIsADirectoryThrowsWithoutFallback() throws {
    let root = try Fixture.scratchRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try Fixture.makeApp(at: root)
    let file = fixture.bundleURL.appendingPathComponent("DefaultDetectors.json")
    try FileManager.default.removeItem(at: file)
    try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
    #expect(throws: AppRegistryResourceError.resourceNotReadable(
        "registry file is not a regular file"
    )) {
        _ = try fixture.loadData()
    }
}

@Test func bundleSymlinkEscapingResourceRootThrowsWithoutFallback() throws {
    let root = try Fixture.scratchRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try Fixture.makeApp(at: root)

    // A complete, valid bundle OUTSIDE the app, reached through the declared in-app path.
    let outside = root.appendingPathComponent("outside-bundle", isDirectory: true)
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    try Data(Fixture.customRegistry.utf8)
        .write(to: outside.appendingPathComponent("DefaultDetectors.json"))

    try FileManager.default.removeItem(at: fixture.bundleURL)
    try FileManager.default.createSymbolicLink(at: fixture.bundleURL, withDestinationURL: outside)

    #expect(throws: AppRegistryResourceError.bundleNotContained("resolved path is outside Contents/Resources")) {
        _ = try fixture.loadData()
    }
}

@Test func registryFileSymlinkEscapingBundleThrowsWithoutFallback() throws {
    let root = try Fixture.scratchRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try Fixture.makeApp(at: root)

    let outsideFile = root.appendingPathComponent("outside-registry.json")
    try Data(Fixture.customRegistry.utf8).write(to: outsideFile)

    let file = fixture.bundleURL.appendingPathComponent("DefaultDetectors.json")
    try FileManager.default.removeItem(at: file)
    try FileManager.default.createSymbolicLink(at: file, withDestinationURL: outsideFile)

    #expect(throws: AppRegistryResourceError.resourceNotReadable("registry file escapes the declared bundle")) {
        _ = try fixture.loadData()
    }
}

@Test func resourceRootEscapingAppThrowsWithoutFallback() throws {
    let root = try Fixture.scratchRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try Fixture.makeApp(at: root)

    // An unrelated directory containing an identically named, valid bundle.
    let foreign = root.appendingPathComponent("foreign-app/Contents/Resources", isDirectory: true)
    let foreignBundle = foreign.appendingPathComponent("AgentLens_AgentLensCore.bundle", isDirectory: true)
    try FileManager.default.createDirectory(at: foreignBundle, withIntermediateDirectories: true)
    try Data(Fixture.customRegistry.utf8)
        .write(to: foreignBundle.appendingPathComponent("DefaultDetectors.json"))

    #expect(throws: AppRegistryResourceError.resourceRootEscapesApp) {
        _ = try DetectorRegistry.loadDefaultRegistryData(
            infoDictionary: fixture.info,
            mainBundleURL: fixture.appURL,
            mainResourceURL: foreign
        )
    }
}

@Test func nilResourceRootThrowsWithoutFallback() throws {
    let root = try Fixture.scratchRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try Fixture.makeApp(at: root)
    #expect(throws: AppRegistryResourceError.resourceRootEscapesApp) {
        _ = try DetectorRegistry.loadDefaultRegistryData(
            infoDictionary: fixture.info,
            mainBundleURL: fixture.appURL,
            mainResourceURL: nil
        )
    }
}

@Test func malformedDeclaredRegistryThrowsRegistryErrorNotFallback() throws {
    let root = try Fixture.scratchRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try Fixture.makeApp(at: root, registry: "{ not json at all")
    // Location succeeds; the DATA is rejected by the unchanged validator, proving the declared
    // bytes (not the bundled default) are what got validated.
    #expect(throws: DetectorRegistryError.self) {
        _ = try fixture.load()
    }
}

// MARK: - Both absent: lazy Bundle.module path, exactly as before

@Test func absentMarkersUseBundledResource() throws {
    // Neither key present, and no injected bundle: identical to the historical call.
    let definitions = try DetectorRegistry.loadDefault()
    #expect(definitions.map(\.id) == ["codex", "opencode", "grok"])
}

@Test func absentMarkersReportAbsentFromTheSeam() throws {
    let outcome = try AppRegistryResourceLocator.locate(
        infoDictionary: [:],
        appBundleURL: URL(fileURLWithPath: "/nonexistent/AgentLens.app", isDirectory: true),
        appResourceURL: nil
    )
    #expect(outcome == .absent)
}

@Test func presentButEmptyDictionaryIsNotAbsentForUnrelatedKeys() throws {
    // Unrelated keys do not make the markers present, so the legacy path applies.
    let outcome = try AppRegistryResourceLocator.locate(
        infoDictionary: ["CFBundleName": "Agent Lens"],
        appBundleURL: URL(fileURLWithPath: "/nonexistent/AgentLens.app", isDirectory: true),
        appResourceURL: nil
    )
    #expect(outcome == .absent)
}

// MARK: - The lazy fallback is invoked exactly 0 or 1 times
//
// These count ACTUAL invocations of the injected fallback through the same production seam.
// The closure returns deliberately wrong sentinel bytes, so any test that receives them proves
// the fallback ran; a marker-present branch that silently consulted it could not pass.

private final class FallbackCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}

private let sentinelBytes = Data("{\"schemaVersion\": 999}".utf8)

@Test func declaredResourceNeverInvokesTheLazyFallback() throws {
    let root = try Fixture.scratchRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try Fixture.makeApp(at: root)

    let counter = FallbackCounter()
    let data = try DetectorRegistry.loadDefaultRegistryData(
        infoDictionary: fixture.info,
        mainBundleURL: fixture.appURL,
        mainResourceURL: fixture.resourceURL,
        lazyFallback: { counter.increment(); return sentinelBytes }
    )
    #expect(counter.count == 0, "the declared-resource branch must never consult the fallback")
    #expect(data == Data(Fixture.customRegistry.utf8), "the declared payload must be the bytes used")
    #expect(data != sentinelBytes)
}

@Test func invalidMarkersNeverInvokeTheLazyFallback() throws {
    // One representative invalid case per refusal family. Every one must fail closed without
    // touching the fallback, and an eager fallback would return the sentinel instead of throwing.
    let root = try Fixture.scratchRoot()
    let base = try Fixture.makeApp(at: root)
    defer { try? FileManager.default.removeItem(at: root) }

    var variants: [[String: Any]] = []
    var incomplete = base.info
    incomplete.removeValue(forKey: "AgentLensCoreResourceBundleName")
    variants.append(incomplete)
    variants.append([
        "AgentLensCoreResourceBundleName": 17,
        "AgentLensCoreResourceBundlePath": Fixture.bundlePath,
    ])
    variants.append([
        "AgentLensCoreResourceBundleName": Fixture.bundleName,
        "AgentLensCoreResourceBundlePath": "Contents/Resources/../escape.bundle",
    ])
    variants.append([
        "AgentLensCoreResourceBundleName": Fixture.bundleName,
        "AgentLensCoreResourceBundlePath": "Contents/Resources/Other.bundle",
    ])

    for info in variants {
        let counter = FallbackCounter()
        var threw = false
        do {
            _ = try DetectorRegistry.loadDefaultRegistryData(
                infoDictionary: info,
                mainBundleURL: base.appURL,
                mainResourceURL: base.resourceURL,
                lazyFallback: { counter.increment(); return sentinelBytes }
            )
        } catch {
            threw = true
        }
        #expect(threw, "invalid markers must throw, never fall back")
        #expect(counter.count == 0, "invalid markers must not consult the fallback")
    }
}

@Test func absentMarkersInvokeTheLazyFallbackExactlyOnce() throws {
    let counter = FallbackCounter()
    let data = try DetectorRegistry.loadDefaultRegistryData(
        infoDictionary: [:],
        mainBundleURL: URL(fileURLWithPath: "/nonexistent/AgentLens.app", isDirectory: true),
        mainResourceURL: nil,
        lazyFallback: { counter.increment(); return sentinelBytes }
    )
    #expect(counter.count == 1, "both markers absent must invoke the fallback exactly once")
    #expect(data == sentinelBytes, "the absent branch must return the fallback's bytes")
}

@Test func fallbackPropagatesItsOwnError() throws {
    // Nothing swallows a fallback failure into a silent success.
    struct Boom: Error {}
    #expect(throws: Boom.self) {
        _ = try DetectorRegistry.loadDefaultRegistryData(
            infoDictionary: [:],
            mainBundleURL: URL(fileURLWithPath: "/nonexistent/AgentLens.app", isDirectory: true),
            mainResourceURL: nil,
            lazyFallback: { throw Boom() }
        )
    }
}

@Test func partialInjectedMarkerMetadataNeverReachesTheFallback() throws {
    // A SUPPLIED marker dictionary must never be discarded in favour of process metadata: doing
    // so would hide the supplied marker and route an invalid declaration to the fallback.
    let counter = FallbackCounter()
    var threw = false
    do {
        _ = try DetectorRegistry.loadDefaultRegistryData(
            infoDictionary: ["AgentLensCoreResourceBundleName": "InvalidPartial"],
            lazyFallback: { counter.increment(); return sentinelBytes }
        )
    } catch let error as AppRegistryResourceError {
        threw = true
        #expect(error == .missingInjectedContext("mainBundleURL"))
    }
    #expect(threw, "a marker-present dictionary without an app URL must be refused")
    #expect(counter.count == 0, "supplied invalid marker metadata must not consult the fallback")
}

@Test func markerPathWithoutAppURLNeverReachesTheFallback() throws {
    let counter = FallbackCounter()
    #expect(throws: AppRegistryResourceError.missingInjectedContext("mainBundleURL")) {
        _ = try DetectorRegistry.loadDefaultRegistryData(
            infoDictionary: ["AgentLensCoreResourceBundlePath": "Contents/Resources/X.bundle"],
            lazyFallback: { counter.increment(); return sentinelBytes }
        )
    }
    #expect(counter.count == 0)
}

@Test func appURLWithoutMetadataIsIncompleteContext() throws {
    // The reverse asymmetry: an app URL with no dictionary cannot be silently paired with the
    // process's own Info.plist either.
    let counter = FallbackCounter()
    #expect(throws: AppRegistryResourceError.missingInjectedContext("infoDictionary")) {
        _ = try DetectorRegistry.loadDefaultRegistryData(
            mainBundleURL: URL(fileURLWithPath: "/nonexistent/AgentLens.app", isDirectory: true),
            lazyFallback: { counter.increment(); return sentinelBytes }
        )
    }
    #expect(counter.count == 0)
}
