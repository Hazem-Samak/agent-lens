import Darwin
import Foundation
import Testing
@testable import AgentLensCore

// M3 tests — the brief's required units, all with injected environments and
// temp-dir fixtures so they never depend on the test machine's real state.

@discardableResult
private func makeExecutable(script: String, in directory: URL, named name: String) throws -> String {
    let fileURL = directory.appendingPathComponent(name)
    try Data("#!/bin/sh\n\(script)\n".utf8).write(to: fileURL)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755], ofItemAtPath: fileURL.path
    )
    return fileURL.path
}

private func fixtureEnvironment(
    pathEntries: [String],
    pathJoined: String? = nil,
    extraRaw: [String: String] = [:]
) -> ShellEnvironment {
    let joined = pathJoined ?? pathEntries.joined(separator: ":")
    return ShellEnvironment(
        shellPath: "/bin/zsh",
        pathEntries: pathEntries,
        pathJoined: joined,
        raw: ["PATH": joined].merging(extraRaw) { _, new in new },
        isDegraded: false
    )
}

private func fixtureRoot(_ label: String) throws -> URL {
    let environment = ProcessInfo.processInfo.environment
    guard let basePath = [environment["AGENT_LENS_TEST_SCRATCH"], environment["TMPDIR"]]
        .compactMap({ $0 })
        .first(where: { !$0.isEmpty })
    else {
        throw NSError(domain: "AgentLensTests", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "no approved test scratch root is available"])
    }
    let base = URL(fileURLWithPath: basePath, isDirectory: true).resolvingSymlinksInPath()
    let root = base.appendingPathComponent("agentlens-m3-\(label)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root.resolvingSymlinksInPath()
}

/// The test-only Core product selection: exactly the inputs a probe needs to compile and link
/// against the Core module, derived from ONE configuration root.
///
/// Two real layouts exist and both are supported from the same shipping source:
///
/// * Swift Build (this workstation): `AgentLensCore.o` aggregate plus `AgentLensCore.swiftmodule`,
///   both directly in the products directory.
/// * Native SwiftPM (hosted): `Modules/AgentLensCore.swiftmodule` plus the sorted, regular
///   `AgentLensCore.build/*.o` object vector. Measured in hosted run 40325427147: 27 objects, no
///   aggregate at the product root.
///
/// Every selected input must resolve inside the one canonical configuration root. Anything that is
/// unresolvable, incomplete, ambiguous or outside the root is refused — never filtered away in the
/// hope that the remainder links. Nothing is copied, recompiled, merged or fabricated.
struct AgentLensCoreProducts {
    enum Layout: String {
        case aggregate
        case native
    }

    /// Canonical physical configuration root (both `/var` and `/private/var` spellings of the same
    /// directory are legitimate; the physical resolution is what is recorded).
    let configurationRoot: URL
    /// Directory to pass to `-I` (the module's own directory).
    let moduleSearchDirectory: URL
    /// Exact object files to pass as literal argv, sorted by filename.
    let objectFiles: [URL]
    /// Explicit provenance. Never inferred from the object count: a native build with exactly one
    /// object is still native.
    let layout: Layout
}

/// A recognized layout: the module to import plus the objects to link.
private struct AgentLensCoreLayout {
    let layout: AgentLensCoreProducts.Layout
    let module: URL
    let objects: [URL]
}

/// The compiler every probe uses. Recorded in the diagnostic so a hosted compile choice can be
/// correlated with the toolchain that produced it.
private let coreProbeCompiler = "/usr/bin/swiftc"

private func coreProductsError(code: Int, _ message: String) -> NSError {
    NSError(domain: "AgentLensCoreProducts", code: code,
            userInfo: [NSLocalizedDescriptionKey: message])
}

private func canonicalPhysicalPath(_ url: URL) -> String? {
    var resolved = [CChar](repeating: 0, count: Int(PATH_MAX))
    guard realpath(url.path, &resolved) != nil else { return nil }
    return String(cString: resolved)
}

/// Error codes. Only `noLayout` permits the caller to keep climbing ancestors; every other code
/// describes a root that IS the active configuration and is therefore terminal.
private enum AgentLensCoreProductsError {
    static let noLayout = 1
    static let incompleteAggregate = 2
    static let incompleteNative = 3
    static let emptyNativeVector = 4
    static let invalidOverride = 5
    static let ambiguousLayout = 6
    static let escape = 7
    static let invalidObject = 8

    static let terminal: Set<Int> = [
        incompleteAggregate, incompleteNative, emptyNativeVector, invalidOverride,
        ambiguousLayout, escape, invalidObject,
    ]
}

/// Recognizes a complete Core layout inside `root`, or reports why the root is unusable.
private func recognizeAgentLensCoreLayout(
    in root: String,
    fileManager: FileManager
) -> Result<AgentLensCoreLayout, NSError> {
    let aggregateObject = root + "/AgentLensCore.o"
    let siblingModule = root + "/AgentLensCore.swiftmodule"
    let nestedModule = root + "/Modules/AgentLensCore.swiftmodule"
    let objectDirectory = root + "/AgentLensCore.build"

    func isRegular(_ path: String) -> Bool {
        guard let attributes = try? fileManager.attributesOfItem(atPath: path) else { return false }
        return (attributes[.type] as? FileAttributeType) == .typeRegular
    }
    func isOnDisk(_ path: String) -> Bool {
        fileManager.fileExists(atPath: path) || (try? fileManager.attributesOfItem(atPath: path)) != nil
    }
    func isDirectory(_ path: String) -> Bool {
        var flag: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &flag) && flag.boolValue
    }
    func isSymlink(_ path: String) -> Bool {
        (try? fileManager.destinationOfSymbolicLink(atPath: path)) != nil
    }
    /// A selected input must physically resolve inside the root and name the same inode it claims.
    func escapesRoot(_ path: String) -> Bool {
        guard let physical = canonicalPhysicalPath(URL(fileURLWithPath: path)) else { return true }
        return physical != path && !physical.hasPrefix(root + "/")
    }

    let hasAggregate = isOnDisk(aggregateObject)
    let siblingModuleExists = isOnDisk(siblingModule)
    let nestedModuleExists = isOnDisk(nestedModule)
    let hasObjectDirectory = isDirectory(objectDirectory)

    let aggregateSignature = hasAggregate || siblingModuleExists
    let nativeSignature = nestedModuleExists || hasObjectDirectory

    // Two complete layout signatures in ONE root is ambiguous: refuse rather than pick by
    // precedence, because the caller cannot tell which artifacts the active build produced.
    if aggregateSignature && nativeSignature {
        return .failure(coreProductsError(
            code: AgentLensCoreProductsError.ambiguousLayout,
            "ambiguous Core layout at \(root): both the aggregate AgentLensCore.o signature and the "
            + "native Modules/AgentLensCore.swiftmodule + AgentLensCore.build/ signature are present"
        ))
    }

    // Measured Swift Build: aggregate object with the module beside it.
    if aggregateSignature {
        guard hasAggregate, siblingModuleExists,
              isRegular(aggregateObject), !isSymlink(aggregateObject) else {
            return .failure(coreProductsError(
                code: AgentLensCoreProductsError.incompleteAggregate,
                "incomplete aggregate Core layout at \(root): AgentLensCore.o must be a regular "
                + "non-symlink file and AgentLensCore.swiftmodule must exist beside it"
            ))
        }
        guard !escapesRoot(aggregateObject), !escapesRoot(siblingModule) else {
            return .failure(coreProductsError(
                code: AgentLensCoreProductsError.escape,
                "aggregate Core inputs at \(root) resolve outside the selected configuration root"
            ))
        }
        return .success(AgentLensCoreLayout(
            layout: .aggregate,
            module: URL(fileURLWithPath: siblingModule),
            objects: [URL(fileURLWithPath: aggregateObject)]
        ))
    }

    // Measured native SwiftPM: module under Modules/, objects under AgentLensCore.build/.
    if nativeSignature {
        guard nestedModuleExists, hasObjectDirectory else {
            return .failure(coreProductsError(
                code: AgentLensCoreProductsError.incompleteNative,
                "incomplete native Core layout at \(root): Modules/AgentLensCore.swiftmodule and "
                + "AgentLensCore.build/ must both exist"
            ))
        }
        guard !isSymlink(objectDirectory), isDirectory(objectDirectory) else {
            return .failure(coreProductsError(
                code: AgentLensCoreProductsError.escape,
                "AgentLensCore.build at \(root) is not a real directory (symlinked object "
                + "directories would let unrelated objects in)"
            ))
        }
        guard !escapesRoot(nestedModule) else {
            return .failure(coreProductsError(
                code: AgentLensCoreProductsError.escape,
                "Core module at \(nestedModule) resolves outside the selected configuration root \(root)"
            ))
        }
        let names = (try? fileManager.contentsOfDirectory(atPath: objectDirectory)) ?? []
        // Every `.o` in this target's own build directory is an input. Anything that is a symlink,
        // not a regular file, or resolves outside the root makes the vector UNUSABLE: dropping it
        // would silently link an incomplete Core.
        let objectNames = names.filter { $0.hasSuffix(".o") }.sorted()
        guard !objectNames.isEmpty else {
            return .failure(coreProductsError(
                code: AgentLensCoreProductsError.emptyNativeVector,
                "native Core layout at \(root) has no objects in AgentLensCore.build/"
            ))
        }
        for name in objectNames {
            let path = objectDirectory + "/" + name
            guard isRegular(path), !isSymlink(path) else {
                return .failure(coreProductsError(
                    code: AgentLensCoreProductsError.invalidObject,
                    "native Core object \(path) is not a regular non-symlink file; refusing to link "
                    + "an incomplete Core object vector"
                ))
            }
            guard !escapesRoot(path) else {
                return .failure(coreProductsError(
                    code: AgentLensCoreProductsError.invalidObject,
                    "native Core object \(path) resolves outside the selected configuration root \(root)"
                ))
            }
        }
        return .success(AgentLensCoreLayout(
            layout: .native,
            module: URL(fileURLWithPath: nestedModule),
            objects: objectNames.map { URL(fileURLWithPath: objectDirectory + "/" + $0) }
        ))
    }

    return .failure(coreProductsError(
        code: AgentLensCoreProductsError.noLayout,
        "no AgentLensCore build products at \(root)"
    ))
}

/// Validates an explicit `AGENT_LENS_TEST_PRODUCTS` value: it must be an absolute, NUL-free path
/// naming an existing directory. Any invalid value fails here, before any bundle fallback.
private func resolveProductsOverride(
    _ override: String,
    fileManager: FileManager
) throws -> String {
    guard !override.isEmpty else {
        throw coreProductsError(
            code: AgentLensCoreProductsError.invalidOverride,
            "AGENT_LENS_TEST_PRODUCTS is set but empty; unset it to use active-product discovery"
        )
    }
    guard !override.utf8.contains(0) else {
        throw coreProductsError(
            code: AgentLensCoreProductsError.invalidOverride,
            "AGENT_LENS_TEST_PRODUCTS contains a NUL byte: \(override.debugDescription)"
        )
    }
    guard override.hasPrefix("/") else {
        throw coreProductsError(
            code: AgentLensCoreProductsError.invalidOverride,
            "AGENT_LENS_TEST_PRODUCTS must be an absolute path, not \(override.debugDescription) "
            + "(a relative value would silently mean the current directory)"
        )
    }
    guard let physical = canonicalPhysicalPath(URL(fileURLWithPath: override, isDirectory: true))
    else {
        throw coreProductsError(
            code: AgentLensCoreProductsError.invalidOverride,
            "AGENT_LENS_TEST_PRODUCTS does not name an existing directory: \(override)"
        )
    }
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: physical, isDirectory: &isDirectory),
          isDirectory.boolValue else {
        throw coreProductsError(
            code: AgentLensCoreProductsError.invalidOverride,
            "AGENT_LENS_TEST_PRODUCTS is not a directory: \(physical)"
        )
    }
    return physical
}

/// Selects the Core products for a probe, from explicit hints only, so focused fixtures never
/// mutate process-global environment or CWD.
///
/// Precedence: a present `AGENT_LENS_TEST_PRODUCTS` (VALID OR NOT — an invalid value fails before
/// any other path is tried), then the active test bundle's own ancestry. There is deliberately no
/// recursive package `.build`/`build` search and no CWD or scratch fallback: a stale artifact from
/// a different build must never be picked up.
func selectAgentLensCoreProducts(
    environment: [String: String],
    arguments: [String],
    executablePath: String? = nil,
    fileManager: FileManager = .default
) throws -> AgentLensCoreProducts {
    func diagnose(_ selection: AgentLensCoreProducts) {
        FileHandle.standardError.write(Data(
            ("core-probe: layout=\(selection.layout.rawValue) "
             + "root=\(selection.configurationRoot.path) "
             + "module=\(selection.moduleSearchDirectory.path) "
             + "objects=\(selection.objectFiles.count) "
             + "compiler=\(coreProbeCompiler)\n").utf8
        ))
    }

    // Presence — not non-emptiness — decides: an empty or malformed value is an operator error, not
    // a request to silently fall back to whatever bundle happens to be running.
    if let override = environment["AGENT_LENS_TEST_PRODUCTS"] {
        let physical = try resolveProductsOverride(override, fileManager: fileManager)
        let layout = try recognizeAgentLensCoreLayout(in: physical, fileManager: fileManager).get()
        let selection = AgentLensCoreProducts(
            configurationRoot: URL(fileURLWithPath: physical, isDirectory: true),
            moduleSearchDirectory: layout.module.deletingLastPathComponent(),
            objectFiles: layout.objects,
            layout: layout.layout
        )
        diagnose(selection)
        return selection
    }

    // Bounded: only the named bundle and the running test executable, and only their ancestors.
    var hints: [String] = []
    if let index = arguments.firstIndex(of: "--test-bundle-path"), index + 1 < arguments.count {
        hints.append(arguments[index + 1])
    }
    if let last = arguments.last, last.contains(".xctest") {
        hints.append(last)
    }
    if let executablePath { hints.append(executablePath) }

    for hint in hints {
        // The hint itself may be a SYMLINK (an active .xctest reached through a link, or an aliased
        // product root). Ancestry must start at the hint's PHYSICAL parent, not its lexical one:
        // climbing the lexical path would walk into whatever directory happens to contain the link
        // and could select a completely unrelated — yet lexically valid — product root.
        guard let physicalHint = canonicalPhysicalPath(URL(fileURLWithPath: hint)) else { continue }
        var candidate = URL(fileURLWithPath: physicalHint).deletingLastPathComponent()
        for _ in 0..<8 {
            if let physical = canonicalPhysicalPath(candidate) {
                switch recognizeAgentLensCoreLayout(in: physical, fileManager: fileManager) {
                case .success(let layout):
                    let selection = AgentLensCoreProducts(
                        configurationRoot: URL(fileURLWithPath: physical, isDirectory: true),
                        moduleSearchDirectory: layout.module.deletingLastPathComponent(),
                        objectFiles: layout.objects,
                        layout: layout.layout
                    )
                    diagnose(selection)
                    return selection
                case .failure(let error):
                    // ONLY "no layout here" may climb. A nearer root that IS a Core configuration
                    // but is incomplete, ambiguous or escaping is terminal: falling through would
                    // silently select a different — quite possibly stale — build.
                    let code = (error as NSError).code
                    if AgentLensCoreProductsError.terminal.contains(code) { throw error }
                }
            }
            let parent = candidate.deletingLastPathComponent()
            if parent.path == candidate.path { break }
            candidate = parent
        }
    }

    throw coreProductsError(
        code: AgentLensCoreProductsError.noLayout,
        "could not locate active AgentLensCore build products from "
        + "\(hints.isEmpty ? "no bundle/executable hint" : hints.joined(separator: ", "))"
    )
}

/// Convenience for the existing test call sites: the active products with no global mutation.
func agentLensCoreProducts() throws -> AgentLensCoreProducts {
    try selectAgentLensCoreProducts(
        environment: ProcessInfo.processInfo.environment,
        arguments: CommandLine.arguments,
        executablePath: Bundle.main.executableURL?.path
    )
}

/// Compile-and-link arguments for a probe against the selected products.
func agentLensCoreCompileArguments(for products: AgentLensCoreProducts) -> [String] {
    var arguments = ["-I", products.moduleSearchDirectory.path]
    arguments.append(contentsOf: products.objectFiles.map(\.path))
    return arguments
}

// MARK: Core product selection (both measured layouts)

/// A metadata-only fixture tree: nothing here is compiled, linked or executed.
private func productFixtureRoot(_ label: String) throws -> URL {
    try fixtureRoot("products-\(label)")
}

private func writeRegularFile(_ path: String, _ contents: String = "fixture") throws {
    let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data(contents.utf8).write(to: URL(fileURLWithPath: path))
}

private func makeAggregateLayout(_ root: URL) throws {
    try writeRegularFile(root.appendingPathComponent("AgentLensCore.o").path)
    try writeRegularFile(root.appendingPathComponent("AgentLensCore.swiftmodule").path)
}

@discardableResult
private func makeNativeLayout(_ root: URL, objects: [String]) throws -> URL {
    let modules = root.appendingPathComponent("Modules")
    try writeRegularFile(modules.appendingPathComponent("AgentLensCore.swiftmodule").path)
    let objectDirectory = root.appendingPathComponent("AgentLensCore.build")
    for name in objects {
        try writeRegularFile(objectDirectory.appendingPathComponent(name).path)
    }
    return modules
}

private func selectWithOverride(_ root: URL) throws -> AgentLensCoreProducts {
    try selectAgentLensCoreProducts(
        environment: ["AGENT_LENS_TEST_PRODUCTS": root.path], arguments: []
    )
}

@Test func productSelectionRecognizesTheAggregateSwiftBuildLayout() throws {
    let root = try productFixtureRoot("aggregate")
    defer { try? FileManager.default.removeItem(at: root) }
    try makeAggregateLayout(root)

    let selection = try selectWithOverride(root)
    #expect(selection.layout == .aggregate)
    // The selection records PHYSICAL paths; compare by identity, not by spelling (`TMPDIR` is
    // `/var/...` whose physical name is `/private/var/...`).
    #expect(canonicalPhysicalPath(selection.moduleSearchDirectory)
            == canonicalPhysicalPath(root))
    #expect(selection.objectFiles.map(\.lastPathComponent) == ["AgentLensCore.o"])
    let arguments = agentLensCoreCompileArguments(for: selection)
    #expect(arguments.first == "-I")
    #expect(arguments.count == 3)
}

@Test func productSelectionRecognizesTheNativeObjectVectorSortedAndTargetScoped() throws {
    let root = try productFixtureRoot("native")
    defer { try? FileManager.default.removeItem(at: root) }
    let modules = try makeNativeLayout(root, objects: ["Zulu.swift.o", "Alpha.swift.o", "Middle.swift.o"])
    // Another target's directory must never contribute objects.
    try writeRegularFile(root.appendingPathComponent("AgentLensApp.build/App.swift.o").path)

    let selection = try selectWithOverride(root)
    #expect(selection.layout == .native)
    #expect(canonicalPhysicalPath(selection.moduleSearchDirectory) == canonicalPhysicalPath(modules))
    #expect(selection.objectFiles.map(\.lastPathComponent)
            == ["Alpha.swift.o", "Middle.swift.o", "Zulu.swift.o"])
    let arguments = agentLensCoreCompileArguments(for: selection)
    #expect(arguments[0] == "-I")
    #expect(canonicalPhysicalPath(URL(fileURLWithPath: arguments[1])) == canonicalPhysicalPath(modules))
    #expect(arguments.count == 2 + 3)
}

/// A one-object native layout is still NATIVE. Deriving the label from the object count would
/// mislabel it as the aggregate Swift Build layout.
@Test func productSelectionLabelsAOneObjectNativeLayoutAsNative() throws {
    let root = try productFixtureRoot("native-one")
    defer { try? FileManager.default.removeItem(at: root) }
    try makeNativeLayout(root, objects: ["Only.swift.o"])

    let selection = try selectWithOverride(root)
    #expect(selection.layout == .native)
    #expect(selection.objectFiles.count == 1)
}

/// Presence of the override decides, so an empty value is an operator error — never a quiet
/// fallback to a perfectly valid running bundle.
@Test func productSelectionRejectsAnEmptyOverrideEvenWithAValidBundleAvailable() throws {
    #expect(throws: (any Error).self) {
        try selectAgentLensCoreProducts(
            environment: ["AGENT_LENS_TEST_PRODUCTS": ""],
            arguments: CommandLine.arguments,
            executablePath: Bundle.main.executableURL?.path
        )
    }
}

@Test func productSelectionRejectsRelativeAndNULOverrides() throws {
    for bad in ["relative/products", "products/debug", "", "/tmp/\(Character(UnicodeScalar(0)))x"] {
        #expect(throws: (any Error).self) {
            try selectAgentLensCoreProducts(
                environment: ["AGENT_LENS_TEST_PRODUCTS": bad],
                arguments: CommandLine.arguments,
                executablePath: Bundle.main.executableURL?.path
            )
        }
    }
}

/// An invalid override must fail rather than fall back — proven with a VALID bundle hint present
/// and a valid directory sitting right next to the invalid value.
@Test func productSelectionInvalidOverrideNeverFallsBackToAValidBundle() throws {
    let empty = try productFixtureRoot("override-empty")
    defer { try? FileManager.default.removeItem(at: empty) }
    let validNeighbour = try productFixtureRoot("override-valid-neighbour")
    defer { try? FileManager.default.removeItem(at: validNeighbour) }
    try makeAggregateLayout(validNeighbour)

    // Sanity: the bundle hint alone WOULD succeed, so a fallback would be observable.
    let viaBundle = try selectAgentLensCoreProducts(
        environment: [:], arguments: CommandLine.arguments,
        executablePath: Bundle.main.executableURL?.path
    )
    #expect(!viaBundle.objectFiles.isEmpty)

    #expect(throws: (any Error).self) {
        try selectAgentLensCoreProducts(
            environment: ["AGENT_LENS_TEST_PRODUCTS": empty.path],
            arguments: CommandLine.arguments,
            executablePath: Bundle.main.executableURL?.path
        )
    }
}

/// Both complete layout signatures in one root: refuse instead of picking by precedence.
@Test func productSelectionRejectsAmbiguousDualLayoutRoot() throws {
    let root = try productFixtureRoot("ambiguous")
    defer { try? FileManager.default.removeItem(at: root) }
    try makeAggregateLayout(root)
    try makeNativeLayout(root, objects: ["Alpha.swift.o"])

    #expect(throws: (any Error).self) { try selectWithOverride(root) }
}

@Test func productSelectionRejectsARecognizedButIncompleteActiveRoot() throws {
    let root = try productFixtureRoot("incomplete")
    defer { try? FileManager.default.removeItem(at: root) }
    // Native-shaped module with no object directory: a partial active layout.
    try writeRegularFile(root.appendingPathComponent("Modules/AgentLensCore.swiftmodule").path)

    #expect(throws: (any Error).self) { try selectWithOverride(root) }
}

/// LOAD-BEARING: an invalid nearer active root must terminate the search even when a VALID
/// ancestor exists. Real nested directories, one bundle hint; only the nearest root differs.
@Test func productSelectionStopsAtAnInvalidNearerRootWithAValidAncestor() throws {
    let outer = try productFixtureRoot("nested-ancestor")
    defer { try? FileManager.default.removeItem(at: outer) }
    try makeAggregateLayout(outer)   // valid ancestor products

    // A nearer root holding only half of a native layout. It is reached BEFORE the valid ancestor.
    let nearer = outer.appendingPathComponent("active")
    try FileManager.default.createDirectory(at: nearer, withIntermediateDirectories: true)
    let bundle = nearer.appendingPathComponent("Probe.xctest")
    try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)

    // With no partial nearer root, the same hint finds the VALID ancestor.
    let ancestorOnly = try selectAgentLensCoreProducts(
        environment: [:], arguments: ["--test-bundle-path", bundle.path], executablePath: nil
    )
    #expect(ancestorOnly.layout == .aggregate)
    #expect(canonicalPhysicalPath(ancestorOnly.configurationRoot) == canonicalPhysicalPath(outer))

    // Now make the nearer root a RECOGNIZED but incomplete Core configuration.
    try writeRegularFile(nearer.appendingPathComponent("Modules/AgentLensCore.swiftmodule").path)

    // The same hint must now throw: falling through would silently select the valid (possibly
    // stale) ancestor instead.
    #expect(throws: (any Error).self) {
        try selectAgentLensCoreProducts(
            environment: [:], arguments: ["--test-bundle-path", bundle.path], executablePath: nil
        )
    }
}

@Test func productSelectionRefusesAModuleThatEscapesTheConfigurationRoot() throws {
    let root = try productFixtureRoot("escape")
    defer { try? FileManager.default.removeItem(at: root) }
    let elsewhere = try productFixtureRoot("escape-target")
    defer { try? FileManager.default.removeItem(at: elsewhere) }
    try writeRegularFile(elsewhere.appendingPathComponent("AgentLensCore.swiftmodule").path)
    try writeRegularFile(root.appendingPathComponent("AgentLensCore.o").path)
    try FileManager.default.createSymbolicLink(
        atPath: root.appendingPathComponent("AgentLensCore.swiftmodule").path,
        withDestinationPath: elsewhere.appendingPathComponent("AgentLensCore.swiftmodule").path
    )

    // Convenient regression: an escaping aggregate module is rejected (already measured).
    #expect(throws: (any Error).self) { try selectWithOverride(root) }
}

/// A single bad object must invalidate the whole vector, not be silently dropped: dropping it
/// would link an incomplete Core that still exits 0 and looks healthy.
@Test func productSelectionRejectsAnExternalObjectSymlinkInsteadOfDroppingIt() throws {
    let root = try productFixtureRoot("object-escape")
    defer { try? FileManager.default.removeItem(at: root) }
    let elsewhere = try productFixtureRoot("object-escape-target")
    defer { try? FileManager.default.removeItem(at: elsewhere) }
    try makeNativeLayout(root, objects: ["Good.swift.o"])
    let external = elsewhere.appendingPathComponent("Evil.swift.o")
    try writeRegularFile(external.path)
    try FileManager.default.createSymbolicLink(
        atPath: root.appendingPathComponent("AgentLensCore.build/Evil.swift.o").path,
        withDestinationPath: external.path
    )

    #expect(throws: (any Error).self) { try selectWithOverride(root) }
}

/// A symlinked `AgentLensCore.build` would let unrelated objects in under a legitimate name.
@Test func productSelectionRejectsASymlinkedObjectDirectory() throws {
    let root = try productFixtureRoot("build-dir-symlink")
    defer { try? FileManager.default.removeItem(at: root) }
    let elsewhere = try productFixtureRoot("build-dir-target")
    defer { try? FileManager.default.removeItem(at: elsewhere) }
    try writeRegularFile(root.appendingPathComponent("Modules/AgentLensCore.swiftmodule").path)
    try writeRegularFile(elsewhere.appendingPathComponent("AgentLensCore.build/Other.swift.o").path)
    try FileManager.default.createSymbolicLink(
        atPath: root.appendingPathComponent("AgentLensCore.build").path,
        withDestinationPath: elsewhere.appendingPathComponent("AgentLensCore.build").path
    )

    #expect(throws: (any Error).self) { try selectWithOverride(root) }
}

/// A legitimate `/var` ↔ `/private/var` alias of the SAME directory must be accepted.
@Test func productSelectionAcceptsAPhysicalAliasOfTheSameRoot() throws {
    let root = try productFixtureRoot("alias")
    defer { try? FileManager.default.removeItem(at: root) }
    try makeAggregateLayout(root)

    let alias = try fixtureRoot("products-alias-link")
    defer { try? FileManager.default.removeItem(at: alias) }
    let link = alias.appendingPathComponent("linked-products")
    try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: root.path)

    let selection = try selectWithOverride(link)
    #expect(selection.layout == .aggregate)
    #expect(canonicalPhysicalPath(selection.configurationRoot) == canonicalPhysicalPath(root))
}

/// LOAD-BEARING: a bundle hint that is a SYMLINK living under a DIFFERENT complete product root must
/// resolve to the REAL bundle's own root. Resolving only the hint while climbing lexical ancestors
/// selects whatever root physically contains the link — an unrelated build that looks perfectly valid.
@Test func productSelectionFollowsThePhysicalBundleNotTheLexicalParentRoot() throws {
    let actualRoot = try productFixtureRoot("physical-active")
    defer { try? FileManager.default.removeItem(at: actualRoot) }
    try makeAggregateLayout(actualRoot)
    let realBundle = actualRoot.appendingPathComponent("Active.xctest")
    try FileManager.default.createDirectory(at: realBundle, withIntermediateDirectories: true)

    // A different, equally complete root that must NOT be selected.
    let decoyRoot = try productFixtureRoot("lexical-decoy")
    defer { try? FileManager.default.removeItem(at: decoyRoot) }
    try makeAggregateLayout(decoyRoot)
    let linkedBundle = decoyRoot.appendingPathComponent("Linked.xctest")
    try FileManager.default.createSymbolicLink(atPath: linkedBundle.path, withDestinationPath: realBundle.path)

    let selection = try selectAgentLensCoreProducts(
        environment: [:], arguments: ["--test-bundle-path", linkedBundle.path], executablePath: nil
    )
    #expect(canonicalPhysicalPath(selection.configurationRoot) == canonicalPhysicalPath(actualRoot))
    #expect(canonicalPhysicalPath(selection.configurationRoot) != canonicalPhysicalPath(decoyRoot))
}

@Test func productSelectionFindsTheActiveBundleAncestryWithoutCwdFallback() throws {
    let products = try agentLensCoreProducts()
    #expect(FileManager.default.fileExists(atPath: products.configurationRoot.path))
    #expect(!products.objectFiles.isEmpty)
    #expect(products.objectFiles.allSatisfy {
        $0.path.hasPrefix(products.configurationRoot.path + "/")
    })

    // No hints at all must fail rather than fall back to any package or scratch directory.
    #expect(throws: (any Error).self) {
        try selectAgentLensCoreProducts(environment: [:], arguments: [], executablePath: nil)
    }
}


@Test func detectorFindsExecutableOnPath() throws {
    let dir = try fixtureRoot("find")
    defer { try? FileManager.default.removeItem(at: dir) }

    let executablePath = try makeExecutable(script: "exit 0", in: dir, named: "fakecli")

    let detector = ToolDetector(
        displayName: "FakeCLI",
        executableName: "fakecli",
        versionQuerySpecification: .standard,
        versionQuery: { _, _, _, _ in nil }
    )
    let tool = detector.detect(in: fixtureEnvironment(pathEntries: [dir.path]))

    #expect(tool.state == .installedAndOnPath)
    #expect(tool.entryPath == executablePath)
    #expect(tool.resolvedPath == executablePath)  // not a symlink -> resolves to itself
    #expect(tool.source == "standalone")          // /var/folders... is neither npm nor Cellar
}

@Test func detectorUsesExtraRootsForInstalledNotOnPath() throws {
    let tmp = try fixtureRoot("off-path")
    let offPathDir = tmp.appendingPathComponent("off-path")
    let onPathDir = tmp.appendingPathComponent("on-path")
    try FileManager.default.createDirectory(at: offPathDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: onPathDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    _ = try makeExecutable(script: "exit 0", in: offPathDir, named: "fakecli")

    let detector = ToolDetector(
        displayName: "FakeCLI",
        executableName: "fakecli",
        extraSearchRoots: [offPathDir.path],
        versionQuerySpecification: .standard,
        versionQuery: { _, _, _, _ in nil }
    )
    let tool = detector.detect(in: fixtureEnvironment(pathEntries: [onPathDir.path]))

    #expect(tool.state == .installedNotOnPath)
    #expect(tool.entryPath == offPathDir.appendingPathComponent("fakecli").path)
}

@Test func detectorReportsNotInstalledWhenNothingFound() {
    let detector = ToolDetector(
        displayName: "FakeCLI",
        executableName: "nothing-named-this",
        versionQuerySpecification: .standard,
        versionQuery: { _, _, _, _ in nil }
    )
    let tool = detector.detect(in: fixtureEnvironment(pathEntries: ["/nonexistent-root"]))

    #expect(tool.state == .notInstalled)
    #expect(tool.source == "–")
    #expect(tool.version == nil)
}

@Test func detectorClassifiesNpmByResolvedSymbolicLinkTarget() throws {
    let tmp = try fixtureRoot("npm")
    let toolBin = tmp.appendingPathComponent("bin")
    let nodeModules = tmp.appendingPathComponent("lib/node_modules/@x/fakecli/bin")
    try FileManager.default.createDirectory(at: nodeModules, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: toolBin, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    // Real npm-style chain: bin shim symlink -> deep node_modules executable.
    let target = try makeExecutable(script: "exit 0", in: nodeModules, named: "fakecli.js")
    let shim = toolBin.appendingPathComponent("fakecli")
    try FileManager.default.createSymbolicLink(atPath: shim.path, withDestinationPath: target)

    let detector = ToolDetector(
        displayName: "FakeCLI",
        executableName: "fakecli",
        versionQuerySpecification: .standard,
        versionQuery: { _, _, _, _ in nil }
    )
    let tool = detector.detect(in: fixtureEnvironment(pathEntries: [toolBin.path]))

    #expect(tool.state == .installedAndOnPath)
    #expect(tool.source == "npm")                       // resolved target, NOT the shim dir
    #expect(tool.resolvedPath?.contains("/lib/node_modules/") == true)
    #expect(tool.resolvedPath?.hasSuffix("fakecli.js") == true)
}

@Test func detectorClassifiesCellarAsBrew() throws {
    let tmp = try fixtureRoot("brew")
    let cellarBin = tmp.appendingPathComponent("Cellar/fakecli/0.1/bin")
    try FileManager.default.createDirectory(at: cellarBin, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    _ = try makeExecutable(script: "exit 0", in: cellarBin, named: "fakecli")

    let detector = ToolDetector(
        displayName: "FakeCLI",
        executableName: "fakecli",
        versionQuerySpecification: .standard,
        versionQuery: { _, _, _, _ in nil }
    )
    let tool = detector.detect(in: fixtureEnvironment(pathEntries: [cellarBin.path]))

    #expect(tool.state == .installedAndOnPath)
    #expect(tool.source == "brew")
}

@Test func versionTokenExtractionHandlesKnownOutputShapes() {
    #expect(ToolDetector.extractVersionToken(from: "codex-cli 0.162.1") == "0.162.1")
    #expect(ToolDetector.extractVersionToken(from: "v1.2.3") == "1.2.3")
    #expect(ToolDetector.extractVersionToken(from: "mytool 1.0.0-beta.2 (build 7)") == "1.0.0-beta.2")
    #expect(ToolDetector.extractVersionToken(from: "no version here") == nil)
}

@Test func versionQueryTimesOutAgainstHangingBinary() throws {
    let dir = try fixtureRoot("hanging-version")
    defer { try? FileManager.default.removeItem(at: dir) }

    let hangingBinary = try makeExecutable(script: "exec /bin/sleep 30", in: dir, named: "hanging-tool")
    let environment = fixtureEnvironment(pathEntries: [dir.path])

    let started = DispatchTime.now().uptimeNanoseconds
    let version = ToolDetector.queryVersion(
        executablePath: hangingBinary, environment: environment, timeout: 0.2,
        specification: .standard
    )
    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000

    #expect(version == nil)          // unknown, not hung (D-007)
    #expect(elapsed >= 0.15 && elapsed < 1.0, "elapsed: \(elapsed)")
}

@Test func detectorDoesNotTreatDirectoryAsAnInstalledExecutable() throws {
    let root = try fixtureRoot("directory-candidate")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(
        at: root.appendingPathComponent("fakecli"), withIntermediateDirectories: true
    )

    let detector = ToolDetector(
        displayName: "FakeCLI", executableName: "fakecli",
        versionQuerySpecification: .standard, versionQuery: { _, _, _, _ in nil }
    )
    let tool = detector.detect(in: fixtureEnvironment(pathEntries: [root.path]))

    #expect(tool.state == .notInstalled)
    #expect(tool.entryPath == nil)
}

@Test func detectorSkipsBrokenSymlinkAndKeepsFirstLivePathWinner() throws {
    let root = try fixtureRoot("symlink-order")
    let directoryRoot = root.appendingPathComponent("directory")
    let brokenRoot = root.appendingPathComponent("broken")
    let nonExecutableRoot = root.appendingPathComponent("non-executable")
    let directorySymlinkRoot = root.appendingPathComponent("directory-symlink")
    let liveRoot = root.appendingPathComponent("live")
    let laterRoot = root.appendingPathComponent("later")
    let targetRoot = root.appendingPathComponent("target")
    let directoryTarget = root.appendingPathComponent("directory-target", isDirectory: true)
    for directory in [directoryRoot, brokenRoot, nonExecutableRoot, directorySymlinkRoot,
                      liveRoot, laterRoot, targetRoot, directoryTarget] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    defer { try? FileManager.default.removeItem(at: root) }

    try FileManager.default.createDirectory(
        at: directoryRoot.appendingPathComponent("fakecli"), withIntermediateDirectories: true
    )
    let brokenLink = brokenRoot.appendingPathComponent("fakecli")
    try FileManager.default.createSymbolicLink(
        atPath: brokenLink.path,
        withDestinationPath: root.appendingPathComponent("missing-target").path
    )
    let nonExecutable = nonExecutableRoot.appendingPathComponent("fakecli")
    try Data("not executable\n".utf8).write(to: nonExecutable)
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: nonExecutable.path)
    try FileManager.default.createSymbolicLink(
        atPath: directorySymlinkRoot.appendingPathComponent("fakecli").path,
        withDestinationPath: directoryTarget.path
    )
    let target = try makeExecutable(script: "exit 0", in: targetRoot, named: "fakecli-target")
    let liveLink = liveRoot.appendingPathComponent("fakecli")
    try FileManager.default.createSymbolicLink(atPath: liveLink.path, withDestinationPath: target)
    _ = try makeExecutable(script: "exit 0", in: laterRoot, named: "fakecli")

    let detector = ToolDetector(
        displayName: "FakeCLI", executableName: "fakecli",
        versionQuerySpecification: .standard, versionQuery: { _, _, _, _ in nil }
    )
    let tool = detector.detect(in: fixtureEnvironment(
        pathEntries: [directoryRoot.path, brokenRoot.path, nonExecutableRoot.path,
                      directorySymlinkRoot.path, liveRoot.path, laterRoot.path]
    ))

    #expect(tool.state == .installedAndOnPath)
    #expect(tool.entryPath == liveLink.path)
    #expect(tool.resolvedPath == target)
}

@Test func detectorKeepsOrderAcrossEmptyPATHComponents() throws {
    let root = try fixtureRoot("empty-path-order")
    let firstRoot = root.appendingPathComponent("first")
    let secondRoot = root.appendingPathComponent("second")
    try FileManager.default.createDirectory(at: firstRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    _ = try makeExecutable(script: "exit 0", in: firstRoot, named: "fakecli")
    _ = try makeExecutable(script: "exit 0", in: secondRoot, named: "fakecli")
    let path = ":\(firstRoot.path)::\(secondRoot.path):"
    let environment = ShellEnvironmentResolver.buildEnvironment(
        shellPath: "/bin/sh",
        outcome: ShellEnvironmentResolver.CaptureOutcome(dump: ["PATH": path], timedOut: false)
    )
    let detector = ToolDetector(
        displayName: "FakeCLI", executableName: "fakecli",
        versionQuerySpecification: .standard, versionQuery: { _, _, _, _ in nil }
    )

    let tool = detector.detect(in: environment)

    #expect(environment.pathEntries == ["", firstRoot.path, "", secondRoot.path, ""])
    #expect(environment.pathJoined == path)
    #expect(environment.raw["PATH"] == path)
    #expect(tool.entryPath == firstRoot.appendingPathComponent("fakecli").path)
}

@Test func detectorAndVersionQueryHonorEmptyAndRelativeRootsInAnIsolatedWorkingDirectory() throws {
    let root = try fixtureRoot("isolated-relative-path")
    defer { try? FileManager.default.removeItem(at: root) }
    try makeExecutable(script: "printf 'cwd 3.4.5\\n'", in: root, named: "fakecli")
    let relativeRoot = root.appendingPathComponent("relative-bin")
    try FileManager.default.createDirectory(at: relativeRoot, withIntermediateDirectories: true)
    try makeExecutable(script: "printf 'relative 6.7.8\\n'", in: relativeRoot, named: "fakecli")

    let products = try agentLensCoreProducts()
    let source = root.appendingPathComponent("relative-path-probe.swift")
    let executable = root.appendingPathComponent("relative-path-probe")
    let sourceText = """
    import Foundation
    import AgentLensCore

    let detector = ToolDetector(
        displayName: "FakeCLI", executableName: "fakecli",
        versionQuerySpecification: .standard
    )
    let emptyEnvironment = ShellEnvironment(
        shellPath: "/bin/sh", pathEntries: ["", "relative-bin"],
        pathJoined: ":relative-bin", raw: ["PATH": ":relative-bin"], isDegraded: false
    )
    let relativeEnvironment = ShellEnvironment(
        shellPath: "/bin/sh", pathEntries: ["relative-bin"],
        pathJoined: "relative-bin", raw: ["PATH": "relative-bin"], isDegraded: false
    )
    let empty = detector.detect(in: emptyEnvironment)
    let relative = detector.detect(in: relativeEnvironment)
    print([empty.entryPath ?? "nil", empty.resolvedPath ?? "nil", empty.version ?? "nil"].joined(separator: "|"))
    print([relative.entryPath ?? "nil", relative.resolvedPath ?? "nil", relative.version ?? "nil"].joined(separator: "|"))
    """
    try Data(sourceText.utf8).write(to: source)

    func run(_ process: Process) throws -> (Int32, String, String) {
        let stdoutURL = root.appendingPathComponent("verifier-stdout-\(UUID().uuidString)")
        let stderrURL = root.appendingPathComponent("verifier-stderr-\(UUID().uuidString)")
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
            return (SIGKILL, "", "isolated verifier exceeded its 30-second watchdog")
        }
        let output = String(data: try Data(contentsOf: stdoutURL), encoding: .utf8) ?? ""
        let errors = String(data: try Data(contentsOf: stderrURL), encoding: .utf8) ?? ""
        return (process.terminationStatus, output, errors)
    }

    let compiler = Process()
    compiler.executableURL = URL(fileURLWithPath: "/usr/bin/swiftc")
    compiler.arguments = agentLensCoreCompileArguments(for: products) + [
        source.path,
        "-o", executable.path
    ]
    compiler.currentDirectoryURL = root
    let compile = try run(compiler)
    guard compile.0 == 0 else {
        Issue.record("isolated PATH verifier compilation failed: \(compile.1)\n\(compile.2)")
        return
    }

    let verifier = Process()
    verifier.executableURL = executable
    verifier.currentDirectoryURL = root
    let result = try run(verifier)
    let expected = [
        "fakecli|\(root.appendingPathComponent("fakecli").path)|3.4.5",
        "relative-bin/fakecli|\(relativeRoot.appendingPathComponent("fakecli").path)|6.7.8"
    ].joined(separator: "\n") + "\n"
    #expect(result.0 == 0, "isolated PATH verifier failed: \(result.2)")
    #expect(result.1 == expected, "isolated PATH verifier output differed: \(result.1)")
}

@Test func versionQueryKillsTerminationResistantProcessAfterEarlyStdoutEOF() throws {
    let root = try fixtureRoot("early-eof-version")
    defer { try? FileManager.default.removeItem(at: root) }
    let pidFile = root.appendingPathComponent("child.pid")
    let binary = try makeExecutable(
        script: "printf '%s' \"$$\" > '\(pidFile.path)'; exec 1>&-; trap '' TERM; exec /bin/sleep 30",
        in: root,
        named: "early-eof-tool"
    )
    let environment = fixtureEnvironment(pathEntries: [root.path])

    let started = DispatchTime.now().uptimeNanoseconds
    let version = ToolDetector.queryVersion(
        executablePath: binary, environment: environment, timeout: 2,
        specification: .standard
    )
    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000
    let pidText = try String(contentsOf: pidFile, encoding: .utf8)
    let pid = try #require(pid_t(pidText))
    defer {
        if kill(pid, 0) == 0 { _ = kill(pid, SIGKILL) }
    }

    #expect(version == nil)
    #expect(elapsed >= 1.9 && elapsed < 2.8, "elapsed: \(elapsed)")
    #expect(kill(pid, 0) == -1)
}

@Test func versionQueryRejectsOutputFromNonzeroExit() throws {
    let root = try fixtureRoot("nonzero-version")
    defer { try? FileManager.default.removeItem(at: root) }
    let binary = try makeExecutable(
        script: "printf 'FakeCLI 9.8.7\\n'; exit 7", in: root, named: "failed-version-tool"
    )
    let environment = fixtureEnvironment(pathEntries: [root.path])

    let version = ToolDetector.queryVersion(
        executablePath: binary, environment: environment, timeout: 1,
        specification: .standard
    )

    #expect(version == nil)
}

@Test func versionQueryRejectsTruncatedOutputEvenWhenTheFirstLineLooksValid() throws {
    let root = try fixtureRoot("truncated-version")
    defer { try? FileManager.default.removeItem(at: root) }
    let binary = try makeExecutable(
        script: "printf 'FakeCLI 9.8.7\\n'; /usr/bin/yes x | /usr/bin/head -c 1200000",
        in: root,
        named: "verbose-version-tool"
    )

    let version = ToolDetector.queryVersion(
        executablePath: binary,
        environment: fixtureEnvironment(pathEntries: [root.path]),
        timeout: 4,
        specification: .standard
    )

    #expect(version == nil)
}

@Test func boundedProcessRunnerEnforcesDeadlineWhileStdoutRemainsReadable() throws {
    let root = try fixtureRoot("continuous-output")
    defer { try? FileManager.default.removeItem(at: root) }
    let pidFile = root.appendingPathComponent("continuous-writer.pid")
    let script = "printf '%s' \"$$\" > '\(pidFile.path)'; exec /usr/bin/yes x"

    let started = DispatchTime.now().uptimeNanoseconds
    let result = BoundedProcessRunner.run(
        executablePath: "/bin/sh",
        arguments: ["-c", script],
        environment: ["PATH": "/usr/bin:/bin"],
        timeout: 1.5
    )
    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000
    let pidText = try String(contentsOf: pidFile, encoding: .utf8)
    let pid = try #require(pid_t(pidText))
    defer {
        if kill(pid, 0) == 0 { _ = kill(pid, SIGKILL) }
    }

    #expect(result?.timedOut == false)
    #expect(result?.outputLimitExceeded == true)
    #expect((result?.standardOutput.count ?? .max) <= BoundedProcessRunner.maximumStandardOutputBytes)
    #expect(elapsed < 1.5, "elapsed: \(elapsed)")
    #expect(kill(pid, 0) == -1)
}

@Test func scanRendererShapesAllThreeStates() {
    let onPath = DetectedTool(
        displayName: "Codex", executableName: "codex",
        state: .installedAndOnPath, entryPath: "/x/codex", resolvedPath: "/y/codex.js",
        source: "npm", version: "0.162.1"
    )
    let notOnPath = DetectedTool(
        displayName: "Codex", executableName: "codex",
        state: .installedNotOnPath, entryPath: "/z/codex", resolvedPath: "/z/codex",
        source: "standalone", version: nil
    )
    let absent = DetectedTool(
        displayName: "Codex", executableName: "codex",
        state: .notInstalled, entryPath: nil, resolvedPath: nil,
        source: "–", version: nil
    )

    let output = ScanRenderer.render(tools: [onPath, notOnPath, absent])
    #expect(output.contains("AI AGENTS                         3"))
    #expect(output.contains("✓ Codex          0.162.1    npm"))
    #expect(output.contains("! Codex          –    standalone (not on PATH)"))   // unknown version -> dash
    #expect(output.contains("– Codex          –    –"))
}
