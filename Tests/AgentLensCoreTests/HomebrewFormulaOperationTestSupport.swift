// Shared disposable fixture for the M13-D Homebrew formula operation tests.
//
// Every path is synthetic and lives under the approved test scratch root. No test here reads or
// writes a personal Homebrew prefix, Cellar, Caskroom, cache or /Applications, and no real brew
// executable is ever invoked: the manager is a synthetic executable and the read-only manager
// answers come from a deterministic scripted runner.

import Darwin
import Foundation
import Testing
@testable import AgentLensCore

func homebrewOperationScratchRoot(_ label: String) throws -> URL {
    let environment = ProcessInfo.processInfo.environment
    guard let basePath = [environment["AGENT_LENS_TEST_SCRATCH"], environment["TMPDIR"]]
        .compactMap({ $0 })
        .first(where: { !$0.isEmpty })
    else {
        throw NSError(domain: "HomebrewFormulaOperationTests", code: 1)
    }
    let root = URL(fileURLWithPath: basePath, isDirectory: true)
        .appendingPathComponent("agentlens-m13d-\(label)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root.resolvingSymlinksInPath()
}

func writeHomebrewExecutable(_ url: URL, _ script: String) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try Data(script.utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
}

/// Mutable manager state observed by the scripted read-only runner. Tests mutate it exactly where
/// a scripted mutation would have changed the manager's answers.
final class HomebrewFormulaFixtureState: @unchecked Sendable {
    private let lock = NSLock()
    private var _kegs: [String]
    private var _selectedKeg: String?
    private var _stable: String
    private var _revision: Int = 0
    private var _pinned: Bool
    private var _deprecated: Bool
    private var _deprecationDate: String?
    private var _deprecationReason: String?
    private var _disabled: Bool
    private var _disableReason: String?
    private var _pinnedNamesOverride: [String]?
    private var _infoFailure = false
    private var _infoMalformed = false
    private var _pinnedListFailure = false
    private var _listFailure = false
    private var _prefixOverride: String?
    private var _prefixFailure = false
    private var _stableJSONNull = false
    private var _stableMalformed = false

    init(kegs: [String], selectedKeg: String?, stable: String, pinned: Bool,
         deprecated: Bool, disabled: Bool) {
        _kegs = kegs
        _selectedKeg = selectedKeg
        _stable = stable
        _pinned = pinned
        _deprecated = deprecated
        _disabled = disabled
    }

    var kegs: [String] {
        get { lock.lock(); defer { lock.unlock() }; return _kegs }
        set { lock.lock(); _kegs = newValue; lock.unlock() }
    }
    var selectedKeg: String? {
        get { lock.lock(); defer { lock.unlock() }; return _selectedKeg }
        set { lock.lock(); _selectedKeg = newValue; lock.unlock() }
    }
    var stable: String {
        get { lock.lock(); defer { lock.unlock() }; return _stable }
        set { lock.lock(); _stable = newValue; lock.unlock() }
    }
    var revision: Int {
        get { lock.lock(); defer { lock.unlock() }; return _revision }
        set { lock.lock(); _revision = newValue; lock.unlock() }
    }
    var pinned: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _pinned }
        set { lock.lock(); _pinned = newValue; lock.unlock() }
    }
    var deprecated: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _deprecated }
        set { lock.lock(); _deprecated = newValue; lock.unlock() }
    }
    var deprecationDate: String? {
        get { lock.lock(); defer { lock.unlock() }; return _deprecationDate }
        set { lock.lock(); _deprecationDate = newValue; lock.unlock() }
    }
    var deprecationReason: String? {
        get { lock.lock(); defer { lock.unlock() }; return _deprecationReason }
        set { lock.lock(); _deprecationReason = newValue; lock.unlock() }
    }
    var disabled: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _disabled }
        set { lock.lock(); _disabled = newValue; lock.unlock() }
    }
    var disableReason: String? {
        get { lock.lock(); defer { lock.unlock() }; return _disableReason }
        set { lock.lock(); _disableReason = newValue; lock.unlock() }
    }
    var pinnedNamesOverride: [String]? {
        get { lock.lock(); defer { lock.unlock() }; return _pinnedNamesOverride }
        set { lock.lock(); _pinnedNamesOverride = newValue; lock.unlock() }
    }
    var infoFailure: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _infoFailure }
        set { lock.lock(); _infoFailure = newValue; lock.unlock() }
    }
    /// A successful query with a malformed body: the operation must treat the inventory as
    /// unknown, never as an empty result.
    var infoMalformed: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _infoMalformed }
        set { lock.lock(); _infoMalformed = newValue; lock.unlock() }
    }
    var pinnedListFailure: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _pinnedListFailure }
        set { lock.lock(); _pinnedListFailure = newValue; lock.unlock() }
    }
    var listFailure: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _listFailure }
        set { lock.lock(); _listFailure = newValue; lock.unlock() }
    }
    /// Replaces the `brew --prefix` answer without touching the fixture tree (missing/inconsistent
    /// prefix tests) or retargets the manager prefix answer between prepare and confirm.
    var prefixOverride: String? {
        get { lock.lock(); defer { lock.unlock() }; return _prefixOverride }
        set { lock.lock(); _prefixOverride = newValue; lock.unlock() }
    }
    var prefixFailure: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _prefixFailure }
        set { lock.lock(); _prefixFailure = newValue; lock.unlock() }
    }
    /// Emits Homebrew's own shape for a formula with no stable spec: `"stable": null`.
    var stableJSONNull: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _stableJSONNull }
        set { lock.lock(); _stableJSONNull = newValue; lock.unlock() }
    }
    /// Emits a present non-null, non-string stable (malformed) to prove fail-closed parsing.
    var stableMalformed: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _stableMalformed }
        set { lock.lock(); _stableMalformed = newValue; lock.unlock() }
    }
}

/// A disposable synthetic Homebrew formula installation:
/// `<root>/Cellar/<formula>/<keg>/bin/<exe>` plus a PATH entry symlink and a synthetic `brew`.
struct HomebrewFormulaFixture: Sendable {
    let root: URL
    let prefix: URL
    let cellar: URL
    let optDirectory: URL
    let linkedDirectory: URL
    let managerDirectory: URL
    let pathDirectory: URL
    let brew: URL
    let formulaName: String
    let executableName: String
    let state: HomebrewFormulaFixtureState
    let environment: ShellEnvironment

    var fullName: String { formulaName }

    init(
        _ label: String,
        kegs: [String] = ["1.0.0"],
        selectedKeg: String? = "1.0.0",
        stable: String = "2.0.0",
        pinned: Bool = false,
        deprecated: Bool = false,
        disabled: Bool = false,
        hostileEnvironment: Bool = false
    ) throws {
        formulaName = "m13tool"
        executableName = "m13tool"
        root = try homebrewOperationScratchRoot(label)
        prefix = root.appendingPathComponent("prefix", isDirectory: true)
        cellar = prefix.appendingPathComponent("Cellar", isDirectory: true)
        optDirectory = prefix.appendingPathComponent("opt", isDirectory: true)
        linkedDirectory = prefix.appendingPathComponent("var/homebrew/linked", isDirectory: true)
        managerDirectory = root.appendingPathComponent("manager-bin", isDirectory: true)
        pathDirectory = root.appendingPathComponent("path-bin", isDirectory: true)
        brew = managerDirectory.appendingPathComponent("brew")
        state = HomebrewFormulaFixtureState(
            kegs: kegs, selectedKeg: selectedKeg, stable: stable,
            pinned: pinned, deprecated: deprecated, disabled: disabled
        )

        var raw = [
            "PATH": [managerDirectory.path, pathDirectory.path].joined(separator: ":"),
            "HOME": root.appendingPathComponent("home", isDirectory: true).path,
        ]
        if hostileEnvironment {
            raw["HOMEBREW_UPGRADE_GREEDY"] = "1"
            raw["HOMEBREW_UPGRADE_GREEDY_CASKS"] = "1"
            raw["HOMEBREW_NO_UPGRADE_QUIT_CASKS"] = "1"
            raw["HOMEBREW_CASK_OPTS"] = "--appdir=/Applications"
            raw["HOMEBREW_AUTOREMOVE"] = "1"
            raw["HOMEBREW_CACHE"] = "/personal/brew-cache"
        }
        environment = ShellEnvironment(
            shellPath: "/bin/zsh",
            pathEntries: [managerDirectory.path, pathDirectory.path],
            pathJoined: [managerDirectory.path, pathDirectory.path].joined(separator: ":"),
            raw: raw,
            isDegraded: false
        )

        try FileManager.default.createDirectory(at: cellar, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: optDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: linkedDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pathDirectory, withIntermediateDirectories: true)
        try writeHomebrewExecutable(brew, "#!/bin/sh\nexit 9\n")
        for keg in kegs {
            try createKeg(keg)
        }
        if let selectedKeg {
            try linkEntry(to: selectedKeg)
            try setOptLink(to: selectedKeg)
            try setLinkedKegLink(to: selectedKeg)
        }
    }

    var entry: URL { pathDirectory.appendingPathComponent(executableName) }

    func kegDirectory(_ version: String) -> URL {
        cellar
            .appendingPathComponent(formulaName, isDirectory: true)
            .appendingPathComponent(version, isDirectory: true)
    }

    func expectedTarget(_ version: String) -> String {
        kegDirectory(version)
            .appendingPathComponent("bin/\(executableName)")
            .standardizedFileURL.path
    }

    func createKeg(_ version: String) throws {
        let target = kegDirectory(version).appendingPathComponent("bin/\(executableName)")
        try writeHomebrewExecutable(target, "#!/bin/sh\necho \(version)\n")
    }

    func linkEntry(to version: String) throws {
        try removeEntry()
        try FileManager.default.createSymbolicLink(
            atPath: entry.path, withDestinationPath: expectedTarget(version)
        )
    }

    func removeEntry() throws {
        var info = Darwin.stat()
        if entry.path.withCString({ Darwin.lstat($0, &info) }) == 0 {
            try FileManager.default.removeItem(at: entry)
        }
    }

    func removeKeg(_ version: String) throws {
        try FileManager.default.removeItem(at: kegDirectory(version))
    }

    var optLink: URL { optDirectory.appendingPathComponent(formulaName) }
    var linkedKegLink: URL { linkedDirectory.appendingPathComponent(formulaName) }

    /// Reproduces Homebrew's `opt/<rack>` symlink, the first input of `resolve_default_keg`.
    func setOptLink(to version: String) throws {
        try replaceFixtureLink(
            at: optLink,
            destination: "../Cellar/\(formulaName)/\(version)"
        )
    }

    /// Reproduces Homebrew's `var/homebrew/linked/<rack>` symlink, the second input.
    func setLinkedKegLink(to version: String) throws {
        try replaceFixtureLink(
            at: linkedKegLink,
            destination: "../../../Cellar/\(formulaName)/\(version)"
        )
    }

    func removeOptLink() throws {
        try removeFixtureLink(at: optLink)
    }

    func removeLinkedKegLink() throws {
        try removeFixtureLink(at: linkedKegLink)
    }

    private func replaceFixtureLink(at link: URL, destination: String) throws {
        try removeFixtureLink(at: link)
        try FileManager.default.createSymbolicLink(
            atPath: link.path, withDestinationPath: destination
        )
    }

    private func removeFixtureLink(at link: URL) throws {
        var info = Darwin.stat()
        if link.path.withCString({ Darwin.lstat($0, &info) }) == 0 {
            try FileManager.default.removeItem(at: link)
        }
    }

    /// Recreates the Cellar as a different vnode with identical contents: the recorded Cellar
    /// identity must stop matching. The manager links still name the same keg paths.
    func replaceCellarIdentity() throws {
        try FileManager.default.removeItem(at: cellar)
        try FileManager.default.createDirectory(at: cellar, withIntermediateDirectories: true)
        for keg in state.kegs {
            try createKeg(keg)
        }
        if let selected = state.selectedKeg {
            try linkEntry(to: selected)
        }
    }

    /// Recreates the whole manager prefix (prefix, Cellar, opt and linked) as a different vnode
    /// with identical contents, so only the recorded prefix identity changes.
    func replacePrefixIdentity() throws {
        try FileManager.default.removeItem(at: prefix)
        try FileManager.default.createDirectory(at: cellar, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: optDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: linkedDirectory, withIntermediateDirectories: true)
        for keg in state.kegs {
            try createKeg(keg)
        }
        if let selected = state.selectedKeg {
            try linkEntry(to: selected)
            try setOptLink(to: selected)
            try setLinkedKegLink(to: selected)
        }
    }

    /// Changes only the prefix directory's mode, leaving the Cellar and keg vnodes untouched.
    func changePrefixMode(to mode: Int) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: mode], ofItemAtPath: prefix.path
        )
    }

    func rewriteManager() throws {
        try writeHomebrewExecutable(brew, "#!/bin/sh\nexit 7\n")
    }

    func diagnostic(keg: String, version: String? = nil) -> ToolPathDiagnostic {
        let target = expectedTarget(keg)
        let directory = pathDirectory.path
        let candidate = PathCandidateObservation(
            origin: .path(slotIndex: 1, directoryText: directory),
            entryPath: entry.path,
            kind: .executableSymlink,
            canonicalTarget: target
        )
        let detected = DetectedTool(
            displayName: "M13 Tool",
            executableName: executableName,
            state: .installedAndOnPath,
            entryPath: entry.path,
            resolvedPath: target,
            source: "brew",
            version: version ?? keg
        )
        return ToolPathDiagnostic(
            detectedTool: detected,
            pathCandidates: [candidate],
            firstLiveCandidate: candidate,
            targetGroups: [
                PathTargetGroup(canonicalTarget: target, entryPaths: [entry.path], firstSlotIndex: 1)
            ],
            repeatedPathSlotCount: 0,
            sameTargetAliasCount: 0,
            selection: .winner(candidate),
            shadowedInstallationCount: 0,
            installationVersions: []
        )
    }

    func notInstalledDiagnostic() -> ToolPathDiagnostic {
        let detected = DetectedTool(
            displayName: "M13 Tool",
            executableName: executableName,
            state: .notInstalled,
            entryPath: nil,
            resolvedPath: nil,
            source: "–",
            version: nil
        )
        return ToolPathDiagnostic(
            detectedTool: detected,
            pathCandidates: [],
            firstLiveCandidate: nil,
            targetGroups: [],
            repeatedPathSlotCount: 0,
            sameTargetAliasCount: 0,
            selection: .notInstalled,
            shadowedInstallationCount: 0,
            installationVersions: []
        )
    }

    func definition(acceptedOperations: [AcceptedOperation]) throws -> DetectorDefinition {
        try DetectorDefinition(
            id: "m13tool",
            displayName: "M13 Tool",
            executableName: executableName,
            extraSearchRoots: [],
            fixture: nil,
            category: .aiAgent,
            packages: [try DeclaredPackage(manager: .homebrewFormula, name: formulaName)],
            informationURL: nil,
            uninstallInstructionsURL: nil,
            versionQuery: .standard,
            acceptedOperations: acceptedOperations
        )
    }

    var managerEntryPath: String { brew.path }
}

struct HomebrewCommandInvocation: Sendable {
    let executablePath: String
    let arguments: [String]
    let environment: [String: String]
    let currentDirectory: String?
    let timeout: TimeInterval
}

/// Deterministic read-only manager answers for the M13-D formula fixture. It never launches `brew`.
final class HomebrewFormulaCommandRunner: UpdateCommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [HomebrewCommandInvocation] = []
    private let state: HomebrewFormulaFixtureState
    private let prefix: String
    private let cellar: String
    private let formulaName: String
    private let fullName: String
    private let target: @Sendable (String) -> String
    /// Invoked after the read-only invocation is recorded and before its scripted answer is
    /// produced, so a test can change the live filesystem at an exact point in the observation
    /// sequence (for example, immediately after the final asynchronous manager read).
    var onQuery: (@Sendable (HomebrewCommandInvocation) -> Void)?

    init(fixture: HomebrewFormulaFixture) {
        state = fixture.state
        prefix = fixture.prefix.path
        cellar = fixture.cellar.path
        formulaName = fixture.formulaName
        fullName = fixture.fullName
        let cellarPath = fixture.cellar.path
        let formula = fixture.formulaName
        let executable = fixture.executableName
        target = { version in
            URL(fileURLWithPath: cellarPath, isDirectory: true)
                .appendingPathComponent(formula, isDirectory: true)
                .appendingPathComponent(version, isDirectory: true)
                .appendingPathComponent("bin/\(executable)")
                .standardizedFileURL.path
        }
    }

    var invocations: [HomebrewCommandInvocation] {
        lock.withLock { recorded }
    }

    func run(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval
    ) async -> CommandOutcome {
        let invocation = HomebrewCommandInvocation(
            executablePath: executablePath,
            arguments: arguments,
            environment: environment,
            currentDirectory: nil,
            timeout: timeout
        )
        lock.withLock { recorded.append(invocation) }
        onQuery?(invocation)

        if arguments == ["--cellar"] {
            return .success(Data((cellar + "\n").utf8))
        }
        if arguments == ["--prefix"] {
            if state.prefixFailure { return .failure(.nonzeroExit) }
            return .success(Data(((state.prefixOverride ?? prefix) + "\n").utf8))
        }
        if arguments.count >= 4, arguments[0] == "info", arguments[1] == "--json=v2",
           arguments[2] == "--formula" {
            if state.infoFailure { return .failure(.nonzeroExit) }
            if state.infoMalformed { return .success(Data("{\"formulae\":\"malformed\"}".utf8)) }
            guard let data = infoData() else { return .failure(.invalidOutput) }
            return .success(data)
        }
        if arguments == ["list", "--pinned"] {
            if state.pinnedListFailure { return .failure(.nonzeroExit) }
            let names = state.pinnedNamesOverride
                ?? (state.pinned ? [formulaName] : [])
            return .success(Data(names.map { $0 + "\n" }.joined().utf8))
        }
        if arguments.count >= 4, arguments[0] == "list", arguments[1] == "--verbose",
           arguments[2] == "--formula" {
            if state.listFailure { return .failure(.nonzeroExit) }
            guard let selected = state.selectedKeg else { return .failure(.nonzeroExit) }
            return .success(Data((target(selected) + "\n").utf8))
        }
        return .failure(.spawnFailure)
    }

    private func infoData() -> Data? {
        let kegs = state.kegs
        let stableValue: Any
        if state.stableJSONNull {
            stableValue = NSNull()
        } else if state.stableMalformed {
            stableValue = 42
        } else {
            stableValue = state.stable
        }
        let object: [String: Any] = [
            "formulae": [[
                "name": formulaName,
                "full_name": fullName,
                "versions": ["stable": stableValue],
                "revision": state.revision,
                "installed": kegs.map { ["version": $0] },
                "pinned": state.pinned,
                "outdated": false,
                "deprecated": state.deprecated,
                "deprecation_date": state.deprecationDate.map { $0 as Any } ?? NSNull(),
                "deprecation_reason": state.deprecationReason.map { $0 as Any } ?? NSNull(),
                "disabled": state.disabled,
                "disable_date": NSNull(),
                "disable_reason": state.disableReason.map { $0 as Any } ?? NSNull(),
            ]]
        ]
        return try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}

/// A deterministic scripted mutation process. `onLaunch` applies the mutation's observable effect
/// at the exact point the process would have run it, so reconciliation sees real local facts.
final class HomebrewScriptedMutationRunner: OperationCommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [HomebrewCommandInvocation] = []
    let result: OperationCommandResult
    let onLaunch: @Sendable () -> Void

    init(
        result: OperationCommandResult = OperationCommandResult(
            stdout: Data(), stderr: Data(),
            stdoutTruncated: false, stderrTruncated: false,
            exitStatus: 0, processStarted: true,
            timedOut: false, cancelled: false, cleanupWarning: false
        ),
        onLaunch: @escaping @Sendable () -> Void = {}
    ) {
        self.result = result
        self.onLaunch = onLaunch
    }

    var invocations: [HomebrewCommandInvocation] {
        lock.withLock { recorded }
    }

    func run(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        currentDirectory: String,
        timeout: TimeInterval
    ) async -> OperationCommandResult {
        lock.withLock {
            recorded.append(HomebrewCommandInvocation(
                executablePath: executablePath,
                arguments: arguments,
                environment: environment,
                currentDirectory: currentDirectory,
                timeout: timeout
            ))
        }
        onLaunch()
        return result
    }
}

/// Counts every manager query. A refused preparation must not observe anything.
final class HomebrewCountingCommandRunner: UpdateCommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var invocations: Int {
        lock.withLock { count }
    }

    func run(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval
    ) async -> CommandOutcome {
        lock.withLock { count += 1 }
        return .failure(.spawnFailure)
    }
}

let homebrewForbiddenMutationFlags = [
    "--force", "--zap", "--ignore-dependencies", "--all", "--dry-run",
    "--overwrite", "--build-from-source", "--installed",
]

let homebrewForbiddenMutationVerbs = [
    "update", "pin", "unpin", "cleanup", "autoremove",
    "install", "reinstall", "migrate", "link", "unlink", "tap", "untap",
]

func expectNoForbiddenMutationTokens(_ arguments: [String]) {
    for argument in arguments {
        if homebrewForbiddenMutationFlags.contains(argument) {
            Issue.record("forbidden flag \(argument) appeared in \(arguments)")
        }
        if argument.hasPrefix("--greedy") {
            Issue.record("forbidden greedy flag \(argument) appeared in \(arguments)")
        }
    }
    if let verb = arguments.first, homebrewForbiddenMutationVerbs.contains(verb) {
        Issue.record("forbidden verb \(verb) appeared in \(arguments)")
    }
}

func homebrewScratchIsEmpty(_ url: URL) throws -> Bool {
    try FileManager.default.contentsOfDirectory(atPath: url.path).isEmpty
}

func waitForHomebrewFile(_ url: URL, timeout: TimeInterval = 5) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if FileManager.default.fileExists(atPath: url.path) { return true }
        Thread.sleep(forTimeInterval: 0.01)
    }
    return FileManager.default.fileExists(atPath: url.path)
}

func waitForHomebrewProcessGone(_ pid: pid_t, timeout: TimeInterval = 5) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if kill(pid, 0) != 0 { return true }
        Thread.sleep(forTimeInterval: 0.02)
    }
    return kill(pid, 0) != 0
}
