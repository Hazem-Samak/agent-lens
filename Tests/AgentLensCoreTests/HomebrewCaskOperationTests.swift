import Darwin
import Foundation
import Testing
@testable import AgentLensCore

// M13-E cask Update/Uninstall: support classification, exact argv/environment, pin and version
// policy, disclosure, stale-fact invalidation, single-use/gate lifecycle, cancellation and
// reconciliation. Every path is synthetic under the approved test scratch root; no real brew
// executable, Caskroom, /Applications, personal cache or zap target is touched.

// MARK: - Disposable cask fixture

final class HomebrewCaskFixtureState: @unchecked Sendable {
    private let lock = NSLock()
    private var _installedVersion: String?
    private var _version: String
    private var _autoUpdates: Bool?
    private var _pinned: Bool
    private var _outdated: Bool
    private var _hasOutdatedRecord: Bool
    private var _disabled: Bool
    private var _disableReason: String?
    private var _deprecated: Bool
    private var _deprecationDate: String?
    private var _deprecationReason: String?
    private var _artifacts: [[String: Any]]
    private var _selectedTargetPath: String? = nil
    private var _stagedSourcePaths: [String] = []
    private var _pinnedNamesOverride: [String]?
    private var _infoFailure = false
    private var _dependsOn: Any = [String: Any]()
    private var _selectedTargetOverride: String?

    init(
        installedVersion: String?,
        version: String,
        autoUpdates: Bool?,
        pinned: Bool,
        outdated: Bool,
        hasOutdatedRecord: Bool,
        disabled: Bool,
        deprecated: Bool,
        artifacts: [[String: Any]]
    ) {
        _installedVersion = installedVersion
        _version = version
        _autoUpdates = autoUpdates
        _pinned = pinned
        _outdated = outdated
        _hasOutdatedRecord = hasOutdatedRecord
        _disabled = disabled
        _deprecated = deprecated
        _artifacts = artifacts
    }

    var installedVersion: String? {
        get { lock.withLock { _installedVersion } }
        set { lock.withLock { _installedVersion = newValue } }
    }
    var version: String {
        get { lock.withLock { _version } }
        set { lock.withLock { _version = newValue } }
    }
    var autoUpdates: Bool? {
        get { lock.withLock { _autoUpdates } }
        set { lock.withLock { _autoUpdates = newValue } }
    }
    var pinned: Bool {
        get { lock.withLock { _pinned } }
        set { lock.withLock { _pinned = newValue } }
    }
    var outdated: Bool {
        get { lock.withLock { _outdated } }
        set { lock.withLock { _outdated = newValue } }
    }
    var hasOutdatedRecord: Bool {
        get { lock.withLock { _hasOutdatedRecord } }
        set { lock.withLock { _hasOutdatedRecord = newValue } }
    }
    var disabled: Bool {
        get { lock.withLock { _disabled } }
        set { lock.withLock { _disabled = newValue } }
    }
    var disableReason: String? {
        get { lock.withLock { _disableReason } }
        set { lock.withLock { _disableReason = newValue } }
    }
    var deprecated: Bool {
        get { lock.withLock { _deprecated } }
        set { lock.withLock { _deprecated = newValue } }
    }
    var deprecationDate: String? {
        get { lock.withLock { _deprecationDate } }
        set { lock.withLock { _deprecationDate = newValue } }
    }
    var deprecationReason: String? {
        get { lock.withLock { _deprecationReason } }
        set { lock.withLock { _deprecationReason = newValue } }
    }
    var artifacts: [[String: Any]] {
        get { lock.withLock { _artifacts } }
        set { lock.withLock { _artifacts = newValue } }
    }
    var selectedTargetPath: String? {
        get { lock.withLock { _selectedTargetPath } }
        set { lock.withLock { _selectedTargetPath = newValue } }
    }
    var stagedSourcePaths: [String] {
        get { lock.withLock { _stagedSourcePaths } }
        set { lock.withLock { _stagedSourcePaths = newValue } }
    }
    var pinnedNamesOverride: [String]? {
        get { lock.withLock { _pinnedNamesOverride } }
        set { lock.withLock { _pinnedNamesOverride = newValue } }
    }
    var infoFailure: Bool {
        get { lock.withLock { _infoFailure } }
        set { lock.withLock { _infoFailure = newValue } }
    }
    /// Fresh `info.depends_on`. The default real shape is an empty object; tests replace it to
    /// declare formula/cask dependencies or malformed data.
    var dependsOn: Any {
        get { lock.withLock { _dependsOn } }
        set { lock.withLock { _dependsOn = newValue } }
    }
    /// Test-only selected target for an ownership-verified moved `.app` whose current source is a
    /// CLI binary. Normal fixtures leave this nil.
    var selectedTargetOverride: String? {
        get { lock.withLock { _selectedTargetOverride } }
        set { lock.withLock { _selectedTargetOverride = newValue } }
    }
}

/// A disposable synthetic Homebrew cask installation:
/// `<caskroom>/<token>/<installed>/<cli source>` plus `prefix/bin/<target>` and a PATH entry
/// symlink, with a synthetic `brew` executable. The manager is never invoked for real.
struct HomebrewCaskFixture: Sendable {
    let root: URL
    let prefix: URL
    let caskroom: URL
    let binDirectory: URL
    let managerDirectory: URL
    let pathDirectory: URL
    let brew: URL
    let token: String
    let fullToken: String
    let tap: String
    let executableName: String
    let state: HomebrewCaskFixtureState
    let environment: ShellEnvironment

    var entry: URL { pathDirectory.appendingPathComponent(executableName) }
    var tokenDirectory: URL { caskroom.appendingPathComponent(token, isDirectory: true) }

    init(
        _ label: String,
        installedVersion: String? = "1.0.0",
        version: String = "2.0.0",
        autoUpdates: Bool? = nil,
        pinned: Bool = false,
        outdated: Bool? = nil,
        hasOutdatedRecord: Bool? = nil,
        disabled: Bool = false,
        deprecated: Bool = false,
        tapped: Bool = false,
        commandWrapper: Bool = false,
        targetName: String = "m13cask",
        artifacts: [[String: Any]]? = nil,
        hostileEnvironment: Bool = false
    ) throws {
        let tokenValue = "m13cask"
        let rootValue = try homebrewOperationScratchRoot(label)
        let prefixValue = rootValue.appendingPathComponent("prefix", isDirectory: true)
        let caskroomValue = prefixValue.appendingPathComponent("Caskroom", isDirectory: true)
        let binValue = prefixValue.appendingPathComponent("bin", isDirectory: true)
        let managerValue = rootValue.appendingPathComponent("manager-bin", isDirectory: true)
        let pathValue = rootValue.appendingPathComponent("path-bin", isDirectory: true)
        token = tokenValue
        fullToken = tapped ? "m13test/homebrew-test/m13cask" : tokenValue
        tap = tapped ? "m13test/homebrew-test" : "homebrew/cask"
        executableName = tokenValue
        root = rootValue
        prefix = prefixValue
        caskroom = caskroomValue
        binDirectory = binValue
        managerDirectory = managerValue
        pathDirectory = pathValue
        brew = managerValue.appendingPathComponent("brew")

        var raw = [
            "PATH": [managerValue.path, pathValue.path].joined(separator: ":"),
            "HOME": rootValue.appendingPathComponent("home", isDirectory: true).path,
        ]
        if hostileEnvironment {
            raw["HOMEBREW_UPGRADE_GREEDY"] = "1"
            raw["HOMEBREW_UPGRADE_GREEDY_CASKS"] = "1"
            raw["HOMEBREW_NO_UPGRADE_QUIT_CASKS"] = "1"
            raw["HOMEBREW_CASK_OPTS"] = "--appdir=/Applications"
            raw["HOMEBREW_AUTOREMOVE"] = "1"
            raw["HOMEBREW_CACHE"] = "/personal/brew-cache"
            raw["SUDO_ASKPASS"] = "/personal/askpass"
            raw["HOMEBREW_SUDO_THROUGH_SUDO_USER"] = "1"
        }
        environment = ShellEnvironment(
            shellPath: "/bin/zsh",
            pathEntries: [managerValue.path, pathValue.path],
            pathJoined: [managerValue.path, pathValue.path].joined(separator: ":"),
            raw: raw,
            isDegraded: false
        )

        let defaultArtifacts: [[String: Any]]
        if commandWrapper {
            defaultArtifacts = [[
                "command_wrapper": ["m13cask", ["executable": "/usr/bin/true"]] as [Any],
                "target": binValue.appendingPathComponent(targetName).path,
            ]]
        } else {
            defaultArtifacts = [[
                "binary": ["m13cask"],
                "target": binValue.appendingPathComponent(targetName).path,
            ]]
        }
        let selectedArtifacts = artifacts ?? defaultArtifacts
        let effectiveOutdated = outdated
            ?? (installedVersion != nil && installedVersion != version)
        let effectiveOutdatedRecord = hasOutdatedRecord ?? effectiveOutdated
        state = HomebrewCaskFixtureState(
            installedVersion: installedVersion,
            version: version,
            autoUpdates: autoUpdates,
            pinned: pinned,
            outdated: effectiveOutdated,
            hasOutdatedRecord: effectiveOutdatedRecord,
            disabled: disabled,
            deprecated: deprecated,
            artifacts: selectedArtifacts
        )

        try FileManager.default.createDirectory(at: caskroom, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: managerDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pathDirectory, withIntermediateDirectories: true)
        try writeHomebrewExecutable(brew, "#!/bin/sh\nexit 9\n")
        try install(version: installedVersion)
    }

    private struct CliSpec {
        let kind: HomebrewCaskArtifactKind
        let source: String
        let target: String
    }

    private var cliSpecs: [CliSpec] {
        state.artifacts.compactMap { artifact in
            if let values = artifact["binary"] as? [Any],
               let source = values.first as? String,
               let target = artifact["target"] as? String {
                return CliSpec(kind: .binary, source: source, target: target)
            }
            if let values = artifact["command_wrapper"] as? [Any],
               let name = values.first as? String,
               let target = artifact["target"] as? String {
                return CliSpec(kind: .commandWrapper, source: name, target: target)
            }
            return nil
        }
    }

    /// Pinned Homebrew's real `%Y%m%d%H%M%S.%L` timestamp spelling.
    static let defaultMetadataTimestamp = "20260101000000.123"

    func versionDirectory(_ version: String) -> URL {
        tokenDirectory.appendingPathComponent(version, isDirectory: true)
    }

    var metadataDirectory: URL {
        tokenDirectory.appendingPathComponent(".metadata", isDirectory: true)
    }

    var metadataReceiptURL: URL {
        metadataDirectory.appendingPathComponent("INSTALL_RECEIPT.json")
    }

    func metadataCaskDirectory(
        version: String? = nil,
        timestamp: String = HomebrewCaskFixture.defaultMetadataTimestamp
    ) -> URL {
        metadataDirectory
            .appendingPathComponent(
                version ?? state.installedVersion ?? "1.0.0", isDirectory: true
            )
            .appendingPathComponent(timestamp, isDirectory: true)
            .appendingPathComponent("Casks", isDirectory: true)
    }

    func metadataCaskJSONURL(
        version: String? = nil,
        timestamp: String = HomebrewCaskFixture.defaultMetadataTimestamp
    ) -> URL {
        metadataCaskDirectory(version: version, timestamp: timestamp)
            .appendingPathComponent(token + ".json")
    }

    private func sourcePath(version: String, spec: CliSpec) -> URL {
        switch spec.kind {
        case .binary:
            if spec.source.hasPrefix("/") {
                return URL(fileURLWithPath: spec.source)
            }
            return versionDirectory(version).appendingPathComponent(spec.source)
        case .commandWrapper:
            return versionDirectory(version)
                .appendingPathComponent(".homebrew-command-wrappers")
                .appendingPathComponent(spec.source)
        }
    }

    func selectedTarget(version: String? = nil) -> String? {
        if let override = state.selectedTargetOverride { return override }
        if let version = version ?? state.installedVersion,
           let spec = cliSpecs.first {
            return sourcePath(version: version, spec: spec).path
        }
        // The selected installation is a local fact independent of the latest metadata under
        // test; a test may replace `state.artifacts` without moving the staged files.
        return state.selectedTargetPath
    }

    func install(version: String?) throws {
        try removeFixtureItem(tokenDirectory)
        for spec in cliSpecs {
            try removeFixtureItem(URL(fileURLWithPath: spec.target))
        }
        try removeFixtureItem(entry)
        guard let version else {
            state.installedVersion = nil
            state.selectedTargetPath = nil
            state.stagedSourcePaths = []
            return
        }
        var staged: [String] = []
        for spec in cliSpecs {
            let source = sourcePath(version: version, spec: spec)
            try writeHomebrewExecutable(source, "#!/bin/sh\necho fixture\n")
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: spec.target).deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.createSymbolicLink(
                atPath: spec.target, withDestinationPath: source.path
            )
            staged.append(source.path)
        }
        if let firstSpec = cliSpecs.first {
            try FileManager.default.createSymbolicLink(
                atPath: entry.path, withDestinationPath: firstSpec.target
            )
            state.selectedTargetPath = sourcePath(version: version, spec: firstSpec).path
        } else {
            state.selectedTargetPath = nil
        }
        state.stagedSourcePaths = staged
        state.installedVersion = version
        try writeDefaultInstalledMetadata()
    }

    /// The real shape Homebrew leaves behind: an empty saved cask definition next to a receipt
    /// that carries the source identity, flight-block verdict and installed artifact list.
    private func writeDefaultInstalledMetadata() throws {
        guard let version = state.installedVersion else { return }
        try writeInstalledMetadata(
            version: version,
            savedJSON: [:],
            receiptArtifacts: state.artifacts,
            flightBlocks: false
        )
    }

    /// The real Homebrew config shape written by `Cask::Config#to_json`.
    static func defaultConfigJSON() -> [String: Any] {
        [
            "default": [String: Any](),
            "env": [String: Any](),
            "explicit": [String: Any](),
        ]
    }

    func writeInstalledMetadata(
        version: String? = nil,
        timestamp: String = HomebrewCaskFixture.defaultMetadataTimestamp,
        savedJSON: [String: Any] = [:],
        receiptArtifacts: [[String: Any]]? = nil,
        flightBlocks: Bool = false,
        sourceTap: String? = nil,
        sourceVersion: String? = nil,
        configJSON: [String: Any]? = HomebrewCaskFixture.defaultConfigJSON(),
        latestDownloadSHA: String? = nil
    ) throws {
        guard let installed = version ?? state.installedVersion else { return }
        try removeFixtureItem(metadataDirectory)
        let casks = metadataCaskDirectory(version: installed, timestamp: timestamp)
        try FileManager.default.createDirectory(at: casks, withIntermediateDirectories: true)
        let receipt: [String: Any] = [
            "source": [
                "tap": sourceTap ?? tap,
                "version": sourceVersion ?? installed,
            ],
            "uninstall_flight_blocks": flightBlocks,
            "uninstall_artifacts": receiptShape(receiptArtifacts ?? state.artifacts),
        ]
        let savedURL = casks.appendingPathComponent(token + ".json")
        let receiptData = try JSONSerialization.data(
            withJSONObject: receipt, options: [.sortedKeys]
        )
        try receiptData.write(to: metadataReceiptURL)
        let savedData = try JSONSerialization.data(
            withJSONObject: savedJSON, options: [.sortedKeys]
        )
        try savedData.write(to: savedURL)
        if let configJSON {
            let configData = try JSONSerialization.data(
                withJSONObject: configJSON, options: [.sortedKeys]
            )
            try configData.write(
                to: metadataDirectory.appendingPathComponent("config.json")
            )
        }
        if let latestDownloadSHA {
            try Data(latestDownloadSHA.utf8).write(
                to: metadataDirectory.appendingPathComponent("LATEST_DOWNLOAD_SHA256")
            )
        }
    }

    func writeSavedCaskJSON(_ object: [String: Any]) throws {
        guard let installed = state.installedVersion else { return }
        let url = metadataCaskJSONURL(version: installed)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try data.write(to: url)
    }

    func writeSavedConfig(_ object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try data.write(to: metadataDirectory.appendingPathComponent("config.json"))
    }

    func writeInstallReceipt(
        artifacts: [[String: Any]]? = nil,
        flightBlocks: Bool = false,
        sourceTap: String? = nil,
        sourceVersion: String? = nil
    ) throws {
        guard let installed = state.installedVersion else { return }
        try FileManager.default.createDirectory(
            at: metadataDirectory, withIntermediateDirectories: true
        )
        let receipt: [String: Any] = [
            "source": [
                "tap": sourceTap ?? tap,
                "version": sourceVersion ?? installed,
            ],
            "uninstall_flight_blocks": flightBlocks,
            "uninstall_artifacts": receiptShape(artifacts ?? state.artifacts),
        ]
        let data = try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys])
        try data.write(to: metadataReceiptURL)
    }

    /// The real receipt records the installed kind/source pairs, not the resolved top-level target.
    private func receiptShape(_ artifacts: [[String: Any]]) -> [[String: Any]] {
        artifacts.map { artifact in
            var copy = artifact
            copy.removeValue(forKey: "target")
            return copy
        }
    }

    func applyUpdate(to version: String) throws {
        try install(version: version)
        state.outdated = false
        state.hasOutdatedRecord = false
    }

    func applyUninstall() throws {
        try removeFixtureItem(tokenDirectory)
        for spec in cliSpecs {
            try removeFixtureItem(URL(fileURLWithPath: spec.target))
        }
        try removeFixtureItem(entry)
        state.installedVersion = nil
        state.selectedTargetPath = nil
        state.stagedSourcePaths = []
        state.outdated = false
        state.hasOutdatedRecord = false
    }

    func rewriteManager() throws {
        try writeHomebrewExecutable(brew, "#!/bin/sh\nexit 7\n")
    }

    func changePrefixMode(to mode: Int) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: mode], ofItemAtPath: prefix.path
        )
    }

    private func removeFixtureItem(_ url: URL) throws {
        var info = Darwin.stat()
        guard url.path.withCString({ Darwin.lstat($0, &info) }) == 0 else { return }
        try FileManager.default.removeItem(at: url)
    }

    func diagnostic(version: String? = nil) -> ToolPathDiagnostic {
        guard let installedVersion = version ?? state.installedVersion,
              let target = selectedTarget(version: installedVersion)
        else { return notInstalledDiagnostic() }
        let directory = pathDirectory.path
        let candidate = PathCandidateObservation(
            origin: .path(slotIndex: 1, directoryText: directory),
            entryPath: entry.path,
            kind: .executableSymlink,
            canonicalTarget: target
        )
        let detected = DetectedTool(
            displayName: "M13 Cask",
            executableName: executableName,
            state: .installedAndOnPath,
            entryPath: entry.path,
            resolvedPath: target,
            source: "standalone",
            version: installedVersion
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
            displayName: "M13 Cask",
            executableName: executableName,
            state: .notInstalled,
            entryPath: nil,
            resolvedPath: nil,
            source: "standalone",
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
            id: "m13casktool",
            displayName: "M13 Cask",
            executableName: executableName,
            extraSearchRoots: [],
            fixture: nil,
            category: .aiAgent,
            packages: [try DeclaredPackage(manager: .homebrewCask, name: fullToken)],
            informationURL: nil,
            uninstallInstructionsURL: nil,
            versionQuery: .standard,
            acceptedOperations: acceptedOperations
        )
    }

    func binaryArtifact(
        source: String = "m13cask",
        targetName: String = "m13cask"
    ) -> [String: Any] {
        [
            "binary": [source],
            "target": binDirectory.appendingPathComponent(targetName).path,
        ]
    }

    func appArtifact(name: String = "M13.app") -> [String: Any] {
        [
            "app": [name],
            "target": root.appendingPathComponent("Applications/\(name)").path,
        ]
    }

    func zapArtifact(path: String) -> [String: Any] {
        ["zap": [["trash": [path]]]]
    }

    func uninstallArtifact(path: String) -> [String: Any] {
        ["uninstall": [["delete": [path]]]]
    }

}

/// Deterministic read-only manager answers. It never launches `brew`.
final class HomebrewCaskCommandRunner: UpdateCommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [HomebrewCommandInvocation] = []
    private let fixture: HomebrewCaskFixture

    init(fixture: HomebrewCaskFixture) {
        self.fixture = fixture
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

        let state = fixture.state
        if arguments == ["--prefix"] {
            return .success(Data((fixture.prefix.path + "\n").utf8))
        }
        if arguments == ["--caskroom"] {
            return .success(Data((fixture.caskroom.path + "\n").utf8))
        }
        if arguments.count >= 4, arguments[0] == "info",
           arguments[1] == "--json=v2", arguments[2] == "--cask" {
            if state.infoFailure { return .failure(.nonzeroExit) }
            guard let data = infoData() else { return .failure(.invalidOutput) }
            return .success(data)
        }
        if arguments == ["list", "--pinned"] {
            let names = state.pinnedNamesOverride
                ?? (state.pinned ? [fixture.token] : [])
            return .success(Data(names.map { $0 + "\n" }.joined().utf8))
        }
        if arguments == ["outdated", "--json=v2", "--cask"] {
            guard let data = outdatedData() else { return .failure(.invalidOutput) }
            return .success(data)
        }
        if arguments.count >= 4, arguments[0] == "list",
           arguments[1] == "--verbose", arguments[2] == "--cask" {
            guard state.installedVersion != nil else {
                return .failure(.nonzeroExit)
            }
            let paths = state.stagedSourcePaths
            guard !paths.isEmpty else { return .failure(.nonzeroExit) }
            return .success(Data((paths.map { $0 + "\n" }.joined()).utf8))
        }
        return .failure(.spawnFailure)
    }

    private func infoData() -> Data? {
        let state = fixture.state
        let installed: Any = state.installedVersion.map { $0 as Any } ?? NSNull()
        var record: [String: Any] = [
            "token": fixture.token,
            "full_token": fixture.fullToken,
            "tap": fixture.tap,
            "version": state.version,
            "installed": installed,
            "auto_updates": state.autoUpdates.map { $0 as Any } ?? NSNull(),
            "pinned": state.pinned,
            "outdated": state.outdated,
            "disabled": state.disabled,
            "disable_reason": state.disableReason.map { $0 as Any } ?? NSNull(),
            "deprecated": state.deprecated,
            "deprecation_date": state.deprecationDate.map { $0 as Any } ?? NSNull(),
            "deprecation_reason": state.deprecationReason.map { $0 as Any } ?? NSNull(),
            "depends_on": state.dependsOn,
            "artifacts": state.artifacts,
        ]
        record["old_tokens"] = []
        return try? JSONSerialization.data(
            withJSONObject: ["casks": [record]], options: [.sortedKeys]
        )
    }

    private func outdatedData() -> Data? {
        let state = fixture.state
        if state.hasOutdatedRecord, let installed = state.installedVersion {
            return try? JSONSerialization.data(
                withJSONObject: ["casks": [[
                    "name": fixture.token,
                    "current_version": state.version,
                    "installed_versions": [installed],
                    "pinned": state.pinned,
                ]]],
                options: [.sortedKeys]
            )
        }
        return try? JSONSerialization.data(withJSONObject: ["casks": []], options: [])
    }
}

// MARK: - Helpers

private func preparedCaskUpdate(
    fixture: HomebrewCaskFixture,
    definition: DetectorDefinition,
    diagnostic: ToolPathDiagnostic,
    runner: UpdateCommandRunner
) async throws -> HomebrewCaskUpdatePreparation {
    switch await HomebrewCaskUpdateOperation.prepare(
        definition: definition,
        diagnostic: diagnostic,
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: runner,
        operationRootBaseURL: fixture.root
    ) {
    case .ready(let preparation):
        return preparation
    case .unavailable(let reason):
        throw NSError(
            domain: "HomebrewCaskOperationTests", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "unexpected update refusal: \(reason)"]
        )
    }
}

private func preparedCaskUninstall(
    fixture: HomebrewCaskFixture,
    definition: DetectorDefinition,
    diagnostic: ToolPathDiagnostic,
    runner: UpdateCommandRunner
) async throws -> HomebrewCaskUninstallPreparation {
    switch await HomebrewCaskUninstallOperation.prepare(
        definition: definition,
        diagnostic: diagnostic,
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: runner,
        operationRootBaseURL: fixture.root
    ) {
    case .ready(let preparation):
        return preparation
    case .unavailable(let reason):
        throw NSError(
            domain: "HomebrewCaskOperationTests", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "unexpected uninstall refusal: \(reason)"]
        )
    }
}

private func expectRefusedCaskUpdate(
    _ outcome: HomebrewCaskUpdateOutcome,
    runner: HomebrewScriptedMutationRunner,
    messageContains: String? = nil
) {
    #expect(outcome.state == .failed)
    #expect(!outcome.processStarted)
    #expect(outcome.reconciliation == nil)
    #expect(runner.invocations.isEmpty)
    if let messageContains {
        #expect(outcome.message?.contains(messageContains) == true)
    }
}

private func expectRefusedCaskUninstall(
    _ outcome: HomebrewCaskUninstallOutcome,
    runner: HomebrewScriptedMutationRunner,
    messageContains: String? = nil
) {
    #expect(outcome.state == .failed)
    #expect(!outcome.processStarted)
    #expect(outcome.reconciliation == nil)
    #expect(runner.invocations.isEmpty)
    if let messageContains {
        #expect(outcome.message?.contains(messageContains) == true)
    }
}

private func expectRefusedUpdatePreparation(
    _ result: HomebrewCaskUpdatePrepareResult,
    equals reason: HomebrewCaskUpdateUnavailableReason
) {
    guard case .unavailable(let actual) = result else {
        Issue.record("expected cask Update refusal \(reason)")
        return
    }
    #expect(actual == reason)
}

private func expectRefusedUninstallPreparation(
    _ result: HomebrewCaskUninstallPrepareResult,
    equals reason: HomebrewCaskUninstallUnavailableReason
) {
    guard case .unavailable(let actual) = result else {
        Issue.record("expected cask Uninstall refusal \(reason)")
        return
    }
    #expect(actual == reason)
}

// MARK: - Exact Update lifecycle

@Test func caskUpdateBindsPreviewAndExecutesWithLiteralArgvAndEnvironment() async throws {
    let fixture = try HomebrewCaskFixture("cask-update-success", hostileEnvironment: true)
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewCaskUpdate])
    let before = fixture.diagnostic()
    let updateRunner = HomebrewCaskCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner(
        result: OperationCommandResult(
            stdout: Data("upgraded\n".utf8), stderr: Data("note\n".utf8),
            stdoutTruncated: false, stderrTruncated: false,
            exitStatus: 0, processStarted: true,
            timedOut: false, cancelled: false, cleanupWarning: false
        ),
        onLaunch: { try? fixture.applyUpdate(to: "2.0.0") }
    )

    let preparation = try await preparedCaskUpdate(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    let preview = preparation.preview
    #expect(preview.registryID == "m13casktool")
    #expect(preview.kind == .cask)
    #expect(preview.token == "m13cask")
    #expect(preview.fullToken == "m13cask")
    #expect(preview.tap == "homebrew/cask")
    #expect(preview.selectedEntryPath == fixture.entry.path)
    #expect(preview.selectedTarget == fixture.selectedTarget(version: "1.0.0"))
    #expect(preview.installedVersion == "1.0.0")
    #expect(preview.targetVersion == "2.0.0")
    #expect(preview.targetResolution == homebrewCaskTargetResolutionDisclosure)
    #expect(preview.targetResolution.contains("re-resolves"))
    #expect(preview.artifactTargets == [
        HomebrewCaskArtifactTarget(
            kind: .binary,
            target: fixture.binDirectory.appendingPathComponent("m13cask").path,
            presence: .linked
        ),
    ])
    #expect(preview.artifactScopeDisclosure == homebrewCaskArtifactScopeDisclosure)
    #expect(preview.zapDeclared == false)
    #expect(preview.zapDisclosure == homebrewCaskZapExclusionDisclosure)
    #expect(preview.prefix == fixture.prefix.path)
    #expect(preview.caskroom == fixture.caskroom.path)
    #expect(preview.executablePath == fixture.brew.path)
    #expect(preview.arguments == ["upgrade", "--cask", "--yes", "m13cask"])
    #expect(preview.timeoutSeconds == 900)
    #expect(preview.effect == homebrewCaskUpdateEffectText)
    for phrase in [
        "upgrade only the named cask",
        "command-line artifact target",
        "no other cask or formula",
        "binary or command_wrapper",
        "no app artifact",
        "no uninstall stanza",
        "formula or cask package dependencies is refused",
        "HOMEBREW_NO_SUDO=1",
        "SUDO_ASKPASS",
        "HOMEBREW_SUDO_THROUGH_SUDO_USER",
        "configuration and caches",
        "does not run the zap step",
        "metadata auto-update is disabled",
        "analytics are disabled",
        "automatic post-upgrade cleanup is disabled",
        "outdated dependent formulae is disabled",
        "includes --yes",
        "download cache, logs, and temporary files",
        "No rollback, reinstall, or atomicity",
        "bounded to 900 seconds",
    ] {
        #expect(preview.effect.contains(phrase), "effect text is missing: \(phrase)")
    }
    expectNoForbiddenMutationTokens(preview.arguments)

    let outcome = await HomebrewCaskUpdateOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (fixture.diagnostic(), fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    #expect(outcome.state == .succeeded)
    #expect(outcome.processStarted)
    #expect(outcome.exitStatus == 0)
    #expect(outcome.stdoutText == "upgraded\n")
    #expect(outcome.stderrText == "note\n")
    #expect(outcome.cleanupWarnings.isEmpty)
    #expect(outcome.message == nil)
    #expect(!FileManager.default.fileExists(atPath: preview.workingDirectory))
    let delta = try #require(outcome.reconciliation)
    #expect(delta.beforeInstalledVersion == "1.0.0")
    #expect(delta.afterInstalledVersion == "2.0.0")
    #expect(delta.observedTargetVersion == "2.0.0")
    #expect(delta.versionMatchesTarget)
    #expect(delta.tokenMatches)
    #expect(delta.stagedMembershipConfirmed)
    #expect(delta.managedTargets.map(\.release) == [
        HomebrewCaskManagedTargetRelease.retargeted,
    ])
    #expect(delta.managedTargetsReleased)
    #expect(!delta.observationFailed)
    guard case .verified(let installation)? = delta.ownership else {
        Issue.record("reconciliation must re-verify cask ownership")
        return
    }
    #expect(installation.manager == .homebrewCask)
    #expect(installation.packageName == fixture.fullToken)
    #expect(installation.managerRoot == fixture.prefix.path)

    #expect(mutationRunner.invocations.count == 1)
    let mutation = try #require(mutationRunner.invocations.first)
    #expect(mutation.executablePath == fixture.brew.path)
    #expect(mutation.arguments == ["upgrade", "--cask", "--yes", "m13cask"])
    #expect(mutation.currentDirectory == preview.workingDirectory)
    #expect(mutation.timeout == 900)
    let environment = mutation.environment
    #expect(environment["HOMEBREW_NO_AUTO_UPDATE"] == "1")
    #expect(environment["HOMEBREW_NO_ANALYTICS"] == "1")
    #expect(environment["HOMEBREW_NO_INSTALL_CLEANUP"] == "1")
    #expect(environment["HOMEBREW_NO_AUTOREMOVE"] == "1")
    #expect(environment["HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK"] == "1")
    #expect(environment["HOMEBREW_NO_SUDO"] == "1")
    #expect(environment["HOMEBREW_NO_ASK"] == nil)
    #expect(environment["SUDO_ASKPASS"] == nil)
    #expect(environment["HOMEBREW_SUDO_THROUGH_SUDO_USER"] == nil)
    for key in HomebrewOperationEnvironment.removedKeys {
        #expect(environment[key] == nil, "mutation environment must not inherit \(key)")
    }
    #expect(environment["HOMEBREW_CACHE"] == "/personal/brew-cache")

    #expect(!updateRunner.invocations.isEmpty)
    for invocation in updateRunner.invocations {
        #expect(invocation.environment["HOMEBREW_NO_INSTALL_CLEANUP"] == nil)
        #expect(invocation.environment["HOMEBREW_NO_AUTOREMOVE"] == nil)
        #expect(invocation.environment["HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK"] == nil)
        #expect(invocation.environment["HOMEBREW_NO_AUTO_UPDATE"] == "1")
        #expect(invocation.environment["HOMEBREW_NO_ANALYTICS"] == "1")
    }
}

@Test func managerResolvedArtifactTargetIsDisclosedExactly() async throws {
    let fixture = try HomebrewCaskFixture(
        "cask-update-explicit-target", targetName: "m13alias"
    )
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    // Homebrew serializes an explicit `target:` option as a second hash in the artifact value
    // array, while the top-level `target` is the resolved destination this operation binds.
    fixture.state.artifacts = [[
        "binary": ["m13cask", ["target": "m13alias"]] as [Any],
        "target": fixture.binDirectory.appendingPathComponent("m13alias").path,
    ]]
    try fixture.install(version: "1.0.0")
    let definition = try fixture.definition(acceptedOperations: [.homebrewCaskUpdate])
    let preparation = try await preparedCaskUpdate(
        fixture: fixture,
        definition: definition,
        diagnostic: fixture.diagnostic(),
        runner: HomebrewCaskCommandRunner(fixture: fixture)
    )
    #expect(preparation.preview.artifactTargets == [
        HomebrewCaskArtifactTarget(
            kind: .binary,
            target: fixture.binDirectory.appendingPathComponent("m13alias").path,
            presence: .linked
        ),
    ])
    #expect(preparation.preview.selectedEntryPath == fixture.entry.path)
    #expect(preparation.preview.selectedTarget == fixture.selectedTarget(version: "1.0.0"))
    #expect(HomebrewCaskUpdateOperation.cancel(preparation))
}

@Test func reportedPrefixAliasDeduplicatesOnePhysicalTarget() async throws {
    let fixture = try HomebrewCaskFixture("cask-prefix-alias")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let realPrefix = fixture.root.appendingPathComponent("prefix-real", isDirectory: true)
    try FileManager.default.moveItem(at: fixture.prefix, to: realPrefix)
    try FileManager.default.createSymbolicLink(
        atPath: fixture.prefix.path, withDestinationPath: realPrefix.path
    )
    // The current info record keeps the alias spelling; the receipt has no saved target, so the
    // installed default target uses the canonical prefix/bin spelling. The selected diagnostic
    // target is the canonical staged source the entry actually resolves to.
    let observedSelection = try #require(
        FileIdentityObserver.observeExecutable(entryPath: fixture.entry.path)
    )
    fixture.state.selectedTargetOverride = observedSelection.canonicalTarget
    let canonicalBinIdentity = try #require(
        FileIdentityObserver.observeDirectory(path: fixture.binDirectory.path)
    )
    let canonicalBin = canonicalBinIdentity.canonicalPath
    let definition = try fixture.definition(acceptedOperations: [.homebrewCaskUpdate])
    let preparation = try await preparedCaskUpdate(
        fixture: fixture,
        definition: definition,
        diagnostic: fixture.diagnostic(),
        runner: HomebrewCaskCommandRunner(fixture: fixture)
    )
    #expect(preparation.preview.prefix == realPrefix.path)
    #expect(preparation.preview.artifactTargets == [
        HomebrewCaskArtifactTarget(
            kind: .binary,
            target: canonicalBin + "/m13cask",
            presence: .linked
        ),
    ])
    #expect(HomebrewCaskUpdateOperation.cancel(preparation))
}

@Test func commandWrapperCaskIsSupportedForUpdatePreview() async throws {
    let fixture = try HomebrewCaskFixture(
        "cask-update-command-wrapper", commandWrapper: true
    )
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewCaskUpdate])
    let preparation = try await preparedCaskUpdate(
        fixture: fixture,
        definition: definition,
        diagnostic: fixture.diagnostic(),
        runner: HomebrewCaskCommandRunner(fixture: fixture)
    )
    #expect(preparation.preview.artifactTargets == [
        HomebrewCaskArtifactTarget(
            kind: .commandWrapper,
            target: fixture.binDirectory.appendingPathComponent("m13cask").path,
            presence: .linked
        ),
    ])
    #expect(preparation.preview.arguments == ["upgrade", "--cask", "--yes", "m13cask"])
    #expect(HomebrewCaskUpdateOperation.cancel(preparation))
}

@Test func tappedCaskPreviewAndArgvUseTheManagerReturnedFullToken() async throws {
    let fixture = try HomebrewCaskFixture("cask-update-tapped", tapped: true)
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewCaskUpdate])
    let runner = HomebrewCaskCommandRunner(fixture: fixture)
    let preparation = try await preparedCaskUpdate(
        fixture: fixture, definition: definition, diagnostic: fixture.diagnostic(), runner: runner
    )
    #expect(preparation.preview.token == "m13cask")
    #expect(preparation.preview.fullToken == "m13test/homebrew-test/m13cask")
    #expect(preparation.preview.tap == "m13test/homebrew-test")
    #expect(preparation.preview.arguments
        == ["upgrade", "--cask", "--yes", "m13test/homebrew-test/m13cask"])
    expectNoForbiddenMutationTokens(preparation.preview.arguments)
    #expect(HomebrewCaskUpdateOperation.cancel(preparation))
}

@Test func commaVersionCaskUpdatesWithoutInventedOrdering() async throws {
    let fixture = try HomebrewCaskFixture(
        "cask-update-comma", installedVersion: "1.2.3,9", version: "1.2.4,10"
    )
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewCaskUpdate])
    let before = fixture.diagnostic()
    let updateRunner = HomebrewCaskCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner(
        onLaunch: { try? fixture.applyUpdate(to: "1.2.4,10") }
    )
    let preparation = try await preparedCaskUpdate(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    #expect(preparation.preview.installedVersion == "1.2.3,9")
    #expect(preparation.preview.targetVersion == "1.2.4,10")
    #expect(preparation.preview.arguments == ["upgrade", "--cask", "--yes", "m13cask"])
    let outcome = await HomebrewCaskUpdateOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (fixture.diagnostic(), fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    #expect(outcome.state == .succeeded)
    #expect(outcome.reconciliation?.afterInstalledVersion == "1.2.4,10")
    #expect(outcome.reconciliation?.versionMatchesTarget == true)
}

// MARK: - Refusal ordering and support boundary

@Test func unacceptedCaskOperationsRefuseBeforeObservationScratchOrProcess() async throws {
    let fixture = try HomebrewCaskFixture("cask-unaccepted")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [])
    let operationBase = fixture.root.appendingPathComponent("operation-base", isDirectory: true)
    try FileManager.default.createDirectory(at: operationBase, withIntermediateDirectories: true)
    let countRunner = HomebrewCountingCommandRunner()

    let update = await HomebrewCaskUpdateOperation.prepare(
        definition: definition,
        diagnostic: fixture.diagnostic(),
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: countRunner,
        operationRootBaseURL: operationBase
    )
    guard case .unavailable(let updateReason) = update else {
        Issue.record("unaccepted cask Update must refuse preparation")
        return
    }
    #expect(updateReason == .operationNotAccepted)
    #expect(countRunner.invocations == 0)
    #expect(try homebrewScratchIsEmpty(operationBase))

    let uninstall = await HomebrewCaskUninstallOperation.prepare(
        definition: definition,
        diagnostic: fixture.diagnostic(),
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: countRunner,
        operationRootBaseURL: operationBase
    )
    guard case .unavailable(let uninstallReason) = uninstall else {
        Issue.record("unaccepted cask Uninstall must refuse preparation")
        return
    }
    #expect(uninstallReason == .operationNotAccepted)
    #expect(countRunner.invocations == 0)
    #expect(try homebrewScratchIsEmpty(operationBase))
}

@Test func appArtifactCaskRefusesBothOperationsWithoutLaunch() async throws {
    let fixture = try HomebrewCaskFixture("cask-app-refusal")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    fixture.state.artifacts = [
        fixture.binaryArtifact(),
        fixture.appArtifact(name: "M13Companion.app"),
    ]
    let updateDefinition = try fixture.definition(acceptedOperations: [.homebrewCaskUpdate])
    let uninstallDefinition = try fixture.definition(
        acceptedOperations: [.homebrewCaskUninstall]
    )
    let runner = HomebrewCaskCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner()
    let operationBase = fixture.root.appendingPathComponent("operation-base", isDirectory: true)
    try FileManager.default.createDirectory(at: operationBase, withIntermediateDirectories: true)

    let update = await HomebrewCaskUpdateOperation.prepare(
        definition: updateDefinition,
        diagnostic: fixture.diagnostic(),
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: runner,
        operationRootBaseURL: operationBase
    )
    expectRefusedUpdatePreparation(update, equals: .caskOperationUnsupported)
    let uninstall = await HomebrewCaskUninstallOperation.prepare(
        definition: uninstallDefinition,
        diagnostic: fixture.diagnostic(),
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: runner,
        operationRootBaseURL: operationBase
    )
    expectRefusedUninstallPreparation(uninstall, equals: .caskOperationUnsupported)
    #expect(try homebrewScratchIsEmpty(operationBase))
    #expect(mutationRunner.invocations.isEmpty)
    #expect(!FileManager.default.fileExists(
        atPath: fixture.root.appendingPathComponent("Applications/M13Companion.app").path
    ))
    if case .ready(let preparation) = update {
        _ = HomebrewCaskUpdateOperation.cancel(preparation)
    }
    if case .ready(let preparation) = uninstall {
        _ = HomebrewCaskUninstallOperation.cancel(preparation)
    }
}

@Test func uninstallStanzaRefusesBothOperationsWithoutElevation() async throws {
    let fixture = try HomebrewCaskFixture("cask-stanza-refusal")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let sentinel = fixture.root.appendingPathComponent("delete-sentinel.txt")
    try Data("intact\n".utf8).write(to: sentinel)
    fixture.state.artifacts = [
        fixture.binaryArtifact(),
        fixture.uninstallArtifact(path: sentinel.path),
    ]
    let runner = HomebrewCaskCommandRunner(fixture: fixture)
    let operationBase = fixture.root.appendingPathComponent("operation-base", isDirectory: true)
    try FileManager.default.createDirectory(at: operationBase, withIntermediateDirectories: true)

    let update = await HomebrewCaskUpdateOperation.prepare(
        definition: try fixture.definition(acceptedOperations: [.homebrewCaskUpdate]),
        diagnostic: fixture.diagnostic(),
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: runner,
        operationRootBaseURL: operationBase
    )
    expectRefusedUpdatePreparation(update, equals: .caskUninstallRequiresElevation)
    let uninstall = await HomebrewCaskUninstallOperation.prepare(
        definition: try fixture.definition(acceptedOperations: [.homebrewCaskUninstall]),
        diagnostic: fixture.diagnostic(),
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: runner,
        operationRootBaseURL: operationBase
    )
    expectRefusedUninstallPreparation(uninstall, equals: .caskUninstallRequiresElevation)
    #expect(try homebrewScratchIsEmpty(operationBase))
    let sentinelText = try String(contentsOf: sentinel, encoding: .utf8)
    #expect(sentinelText == "intact\n")
}

@Test func emptyOrMalformedArtifactsFailClosedWithoutLaunch() async throws {
    let empty = try HomebrewCaskFixture("cask-empty-artifacts")
    defer { try? FileManager.default.removeItem(at: empty.root) }
    empty.state.artifacts = []
    let emptyRunner = HomebrewCaskCommandRunner(fixture: empty)
    let emptyResult = await HomebrewCaskUpdateOperation.prepare(
        definition: try empty.definition(acceptedOperations: [.homebrewCaskUpdate]),
        diagnostic: empty.diagnostic(),
        environment: empty.environment,
        currentDirectory: empty.root.path,
        runner: emptyRunner,
        operationRootBaseURL: empty.root
    )
    expectRefusedUpdatePreparation(emptyResult, equals: .caskOperationUnsupported)

    let malformed = try HomebrewCaskFixture("cask-malformed-artifacts")
    defer { try? FileManager.default.removeItem(at: malformed.root) }
    malformed.state.artifacts = [[
        "binary": "not-an-array",
        "target": malformed.binDirectory.appendingPathComponent("m13cask").path,
    ]]
    let malformedRunner = HomebrewCaskCommandRunner(fixture: malformed)
    let malformedResult = await HomebrewCaskUpdateOperation.prepare(
        definition: try malformed.definition(acceptedOperations: [.homebrewCaskUpdate]),
        diagnostic: malformed.diagnostic(),
        environment: malformed.environment,
        currentDirectory: malformed.root.path,
        runner: malformedRunner,
        operationRootBaseURL: malformed.root
    )
    expectRefusedUpdatePreparation(malformedResult, equals: .metadataInvalid)
    let malformedUninstall = await HomebrewCaskUninstallOperation.prepare(
        definition: try malformed.definition(acceptedOperations: [.homebrewCaskUninstall]),
        diagnostic: malformed.diagnostic(),
        environment: malformed.environment,
        currentDirectory: malformed.root.path,
        runner: malformedRunner,
        operationRootBaseURL: malformed.root
    )
    expectRefusedUninstallPreparation(malformedUninstall, equals: .metadataInvalid)
}

@Test func pinnedCaskRefusesBothOperationsAndPinDisagreementFailsClosed() async throws {
    let pinned = try HomebrewCaskFixture("cask-pinned", pinned: true)
    defer { try? FileManager.default.removeItem(at: pinned.root) }
    let pinnedRunner = HomebrewCaskCommandRunner(fixture: pinned)
    let update = await HomebrewCaskUpdateOperation.prepare(
        definition: try pinned.definition(acceptedOperations: [.homebrewCaskUpdate]),
        diagnostic: pinned.diagnostic(),
        environment: pinned.environment,
        currentDirectory: pinned.root.path,
        runner: pinnedRunner,
        operationRootBaseURL: pinned.root
    )
    expectRefusedUpdatePreparation(update, equals: .pinned)
    let uninstall = await HomebrewCaskUninstallOperation.prepare(
        definition: try pinned.definition(acceptedOperations: [.homebrewCaskUninstall]),
        diagnostic: pinned.diagnostic(),
        environment: pinned.environment,
        currentDirectory: pinned.root.path,
        runner: pinnedRunner,
        operationRootBaseURL: pinned.root
    )
    expectRefusedUninstallPreparation(uninstall, equals: .pinned)

    let infoOnly = try HomebrewCaskFixture("cask-pin-info-only", pinned: true)
    defer { try? FileManager.default.removeItem(at: infoOnly.root) }
    infoOnly.state.pinnedNamesOverride = []
    let infoOnlyResult = await HomebrewCaskUpdateOperation.prepare(
        definition: try infoOnly.definition(acceptedOperations: [.homebrewCaskUpdate]),
        diagnostic: infoOnly.diagnostic(),
        environment: infoOnly.environment,
        currentDirectory: infoOnly.root.path,
        runner: HomebrewCaskCommandRunner(fixture: infoOnly),
        operationRootBaseURL: infoOnly.root
    )
    expectRefusedUpdatePreparation(infoOnlyResult, equals: .identityUnverified)

    let listOnly = try HomebrewCaskFixture("cask-pin-list-only")
    defer { try? FileManager.default.removeItem(at: listOnly.root) }
    listOnly.state.pinnedNamesOverride = ["m13cask"]
    let listOnlyResult = await HomebrewCaskUpdateOperation.prepare(
        definition: try listOnly.definition(acceptedOperations: [.homebrewCaskUpdate]),
        diagnostic: listOnly.diagnostic(),
        environment: listOnly.environment,
        currentDirectory: listOnly.root.path,
        runner: HomebrewCaskCommandRunner(fixture: listOnly),
        operationRootBaseURL: listOnly.root
    )
    expectRefusedUpdatePreparation(listOnlyResult, equals: .identityUnverified)
}

@Test func updatePolicyRefusalsAreSpecificAndBounded() async throws {
    let disabled = try HomebrewCaskFixture(
        "cask-disabled", outdated: true, hasOutdatedRecord: false, disabled: true
    )
    defer { try? FileManager.default.removeItem(at: disabled.root) }
    disabled.state.disableReason = String(repeating: "x", count: 300)
    let disabledResult = await HomebrewCaskUpdateOperation.prepare(
        definition: try disabled.definition(acceptedOperations: [.homebrewCaskUpdate]),
        diagnostic: disabled.diagnostic(),
        environment: disabled.environment,
        currentDirectory: disabled.root.path,
        runner: HomebrewCaskCommandRunner(fixture: disabled),
        operationRootBaseURL: disabled.root
    )
    let bounded = String(repeating: "x", count: 200)
    expectRefusedUpdatePreparation(
        disabledResult, equals: .caskDisabled(disableReason: bounded)
    )
    if case .unavailable(let reason) = disabledResult {
        #expect(reason.message.contains(bounded))
        #expect(!reason.message.contains(String(repeating: "x", count: 201)))
    }

    let auto = try HomebrewCaskFixture(
        "cask-auto", autoUpdates: true, outdated: true, hasOutdatedRecord: false
    )
    defer { try? FileManager.default.removeItem(at: auto.root) }
    let autoResult = await HomebrewCaskUpdateOperation.prepare(
        definition: try auto.definition(acceptedOperations: [.homebrewCaskUpdate]),
        diagnostic: auto.diagnostic(),
        environment: auto.environment,
        currentDirectory: auto.root.path,
        runner: HomebrewCaskCommandRunner(fixture: auto),
        operationRootBaseURL: auto.root
    )
    expectRefusedUpdatePreparation(autoResult, equals: .caskAutoUpdates)

    let latest = try HomebrewCaskFixture(
        "cask-latest", installedVersion: "latest", version: "latest",
        outdated: false, hasOutdatedRecord: false
    )
    defer { try? FileManager.default.removeItem(at: latest.root) }
    let latestResult = await HomebrewCaskUpdateOperation.prepare(
        definition: try latest.definition(acceptedOperations: [.homebrewCaskUpdate]),
        diagnostic: latest.diagnostic(),
        environment: latest.environment,
        currentDirectory: latest.root.path,
        runner: HomebrewCaskCommandRunner(fixture: latest),
        operationRootBaseURL: latest.root
    )
    expectRefusedUpdatePreparation(latestResult, equals: .caskTracksLatest)
}

@Test func deprecatedCaskUpdateIsPermittedAndDisclosed() async throws {
    let fixture = try HomebrewCaskFixture("cask-deprecated", deprecated: true)
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    fixture.state.deprecationDate = "2026-02-03"
    fixture.state.deprecationReason = "renamed upstream"
    let preparation = try await preparedCaskUpdate(
        fixture: fixture,
        definition: try fixture.definition(acceptedOperations: [.homebrewCaskUpdate]),
        diagnostic: fixture.diagnostic(),
        runner: HomebrewCaskCommandRunner(fixture: fixture)
    )
    #expect(preparation.preview.deprecated)
    let disclosure = try #require(preparation.preview.deprecationDisclosure)
    #expect(disclosure.contains("2026-02-03"))
    #expect(disclosure.contains("renamed upstream"))
    #expect(disclosure.contains("remains available"))
    #expect(HomebrewCaskUpdateOperation.cancel(preparation))
}

// MARK: - Exact Uninstall lifecycle and disclosure

@Test func caskUninstallDisclosesWholeCaskZapAndCompanionAppAndExecutesOnce() async throws {
    let fixture = try HomebrewCaskFixture("cask-uninstall-success", hostileEnvironment: true)
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let zapSentinel = fixture.root.appendingPathComponent("zap-sentinel.txt")
    try Data("zap untouched\n".utf8).write(to: zapSentinel)
    fixture.state.artifacts = [
        fixture.binaryArtifact(source: "m13cask", targetName: "m13cask"),
        fixture.binaryArtifact(source: "m13second", targetName: "m13second"),
        fixture.zapArtifact(path: zapSentinel.path),
    ]
    try fixture.install(version: "1.0.0")

    let definition = try fixture.definition(acceptedOperations: [.homebrewCaskUninstall])
    let before = fixture.diagnostic()
    let updateRunner = HomebrewCaskCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner(
        result: OperationCommandResult(
            stdout: Data("removed\n".utf8), stderr: Data("note\n".utf8),
            stdoutTruncated: false, stderrTruncated: false,
            exitStatus: 0, processStarted: true,
            timedOut: false, cancelled: false, cleanupWarning: false
        ),
        onLaunch: { try? fixture.applyUninstall() }
    )
    let preparation = try await preparedCaskUninstall(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    let preview = preparation.preview
    #expect(preview.kind == .cask)
    #expect(preview.token == "m13cask")
    #expect(preview.fullToken == "m13cask")
    #expect(preview.tap == "homebrew/cask")
    #expect(preview.installedVersion == "1.0.0")
    #expect(preview.artifactTargets.map(\.target) == [
        fixture.binDirectory.appendingPathComponent("m13cask").path,
        fixture.binDirectory.appendingPathComponent("m13second").path,
    ])
    #expect(preview.artifactTargets.allSatisfy { $0.presence == .linked })
    #expect(preview.artifactScopeDisclosure == homebrewCaskUninstallArtifactScopeDisclosure)
    #expect(preview.artifactScopeDisclosure.contains("verified installed"))
    #expect(!preview.artifactScopeDisclosure.contains("current-source"))
    #expect(preview.companionAppDisclosure == homebrewCaskCompanionAppDisclosure)
    #expect(preview.zapDeclared)
    #expect(preview.zapDisclosure == homebrewCaskZapExclusionDisclosure)
    #expect(preview.zapDisclosure.contains("configuration and caches"))
    #expect(preview.zapDisclosure.contains("does not run the zap step"))
    #expect(preview.arguments == ["uninstall", "--cask", "m13cask"])
    #expect(!preview.arguments.contains("--zap"))
    #expect(preview.timeoutSeconds == 900)
    #expect(preview.prefix == fixture.prefix.path)
    #expect(preview.caskroom == fixture.caskroom.path)
    expectNoForbiddenMutationTokens(preview.arguments)
    for phrase in [
        "uninstall only the named cask",
        "companion app",
        "command-line artifact target",
        "no app artifact",
        "no uninstall stanza",
        "HOMEBREW_NO_SUDO=1",
        "SUDO_ASKPASS",
        "configuration and caches",
        "does not run the zap step",
        "automatic cleanup is disabled",
        "download cache, logs, and temporary files",
        "No rollback, reinstall, or atomicity",
        "bounded to 900 seconds",
    ] {
        #expect(preview.effect.contains(phrase), "effect text is missing: \(phrase)")
    }

    let outcome = await HomebrewCaskUninstallOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (fixture.diagnostic(), fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    #expect(outcome.state == .succeeded)
    #expect(outcome.processStarted)
    #expect(outcome.stdoutText == "removed\n")
    #expect(outcome.stderrText == "note\n")
    #expect(outcome.message == nil)
    #expect(!FileManager.default.fileExists(atPath: preview.workingDirectory))
    let delta = try #require(outcome.reconciliation)
    #expect(delta.beforeInstalledVersion == "1.0.0")
    #expect(delta.afterInstalledVersion == nil)
    #expect(delta.infoInstalledAbsent)
    #expect(delta.tokenDirectoryAbsent)
    #expect(!delta.tokenDirectoryReplaced)
    #expect(delta.selectedTargetReleased)
    #expect(delta.managedTargets.map(\.release) == [
        HomebrewCaskManagedTargetRelease.released,
        HomebrewCaskManagedTargetRelease.released,
    ])
    #expect(delta.managedTargetsReleased)
    #expect(!delta.observationFailed)
    let zapText = try String(contentsOf: zapSentinel, encoding: .utf8)
    #expect(zapText == "zap untouched\n")

    #expect(mutationRunner.invocations.count == 1)
    let mutation = try #require(mutationRunner.invocations.first)
    #expect(mutation.executablePath == fixture.brew.path)
    #expect(mutation.arguments == ["uninstall", "--cask", "m13cask"])
    #expect(mutation.currentDirectory == preview.workingDirectory)
    #expect(mutation.timeout == 900)
    let environment = mutation.environment
    #expect(environment["HOMEBREW_NO_AUTO_UPDATE"] == "1")
    #expect(environment["HOMEBREW_NO_ANALYTICS"] == "1")
    #expect(environment["HOMEBREW_NO_INSTALL_CLEANUP"] == "1")
    #expect(environment["HOMEBREW_NO_AUTOREMOVE"] == "1")
    #expect(environment["HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK"] == nil)
    #expect(environment["HOMEBREW_NO_SUDO"] == "1")
    #expect(environment["SUDO_ASKPASS"] == nil)
    #expect(environment["HOMEBREW_SUDO_THROUGH_SUDO_USER"] == nil)
    for key in HomebrewOperationEnvironment.removedKeys {
        #expect(environment[key] == nil, "mutation environment must not inherit \(key)")
    }
}

@Test func uninstallIgnoresVersionPoliciesButStillRefusesPins() async throws {
    let latest = try HomebrewCaskFixture(
        "cask-uninstall-latest", installedVersion: "latest", version: "latest",
        autoUpdates: true, outdated: false, hasOutdatedRecord: false, disabled: true
    )
    defer { try? FileManager.default.removeItem(at: latest.root) }
    let latestPreparation = try await preparedCaskUninstall(
        fixture: latest,
        definition: try latest.definition(acceptedOperations: [.homebrewCaskUninstall]),
        diagnostic: latest.diagnostic(),
        runner: HomebrewCaskCommandRunner(fixture: latest)
    )
    #expect(latestPreparation.preview.installedVersion == "latest")
    #expect(HomebrewCaskUninstallOperation.cancel(latestPreparation))

    let comma = try HomebrewCaskFixture(
        "cask-uninstall-comma", installedVersion: "1.2.3,9", version: "1.2.4,10",
        autoUpdates: true, disabled: true
    )
    defer { try? FileManager.default.removeItem(at: comma.root) }
    let commaPreparation = try await preparedCaskUninstall(
        fixture: comma,
        definition: try comma.definition(acceptedOperations: [.homebrewCaskUninstall]),
        diagnostic: comma.diagnostic(),
        runner: HomebrewCaskCommandRunner(fixture: comma)
    )
    #expect(commaPreparation.preview.installedVersion == "1.2.3,9")
    #expect(HomebrewCaskUninstallOperation.cancel(commaPreparation))
}

// MARK: - Stale facts, pins and cancellation

@Test func pinAppearingAfterPreviewRefusesBeforeLaunch() async throws {
    let fixture = try HomebrewCaskFixture("cask-pin-late")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewCaskUpdate])
    let before = fixture.diagnostic()
    let updateRunner = HomebrewCaskCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner()
    let preparation = try await preparedCaskUpdate(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    fixture.state.pinned = true
    fixture.state.pinnedNamesOverride = nil

    let outcome = await HomebrewCaskUpdateOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (fixture.diagnostic(), fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    expectRefusedCaskUpdate(outcome, runner: mutationRunner, messageContains: "now pinned")
}

@Test func staleArtifactsOrSelectionRefuseBeforeLaunch() async throws {
    let artifacts = try HomebrewCaskFixture("cask-stale-artifacts")
    defer { try? FileManager.default.removeItem(at: artifacts.root) }
    let artifactsDefinition = try artifacts.definition(
        acceptedOperations: [.homebrewCaskUpdate]
    )
    let artifactsBefore = artifacts.diagnostic()
    let artifactsRunner = HomebrewCaskCommandRunner(fixture: artifacts)
    let artifactsMutation = HomebrewScriptedMutationRunner()
    let artifactsPreparation = try await preparedCaskUpdate(
        fixture: artifacts, definition: artifactsDefinition,
        diagnostic: artifactsBefore, runner: artifactsRunner
    )
    artifacts.state.artifacts = [
        artifacts.binaryArtifact(),
        artifacts.appArtifact(name: "Late.app"),
    ]
    let artifactsOutcome = await HomebrewCaskUpdateOperation.execute(
        confirmed: artifactsPreparation,
        environment: artifacts.environment,
        scan: { _, _, _ in artifactsBefore },
        reconcileAfterLaunch: { _ in (artifacts.diagnostic(), artifacts.environment) },
        updateRunner: artifactsRunner,
        operationRunner: artifactsMutation,
        gate: OperationExecutionGate()
    )
    expectRefusedCaskUpdate(artifactsOutcome, runner: artifactsMutation)

    let selection = try HomebrewCaskFixture("cask-stale-selection")
    defer { try? FileManager.default.removeItem(at: selection.root) }
    let selectionDefinition = try selection.definition(
        acceptedOperations: [.homebrewCaskUpdate]
    )
    let selectionBefore = selection.diagnostic()
    let selectionRunner = HomebrewCaskCommandRunner(fixture: selection)
    let selectionMutation = HomebrewScriptedMutationRunner()
    let selectionPreparation = try await preparedCaskUpdate(
        fixture: selection, definition: selectionDefinition,
        diagnostic: selectionBefore, runner: selectionRunner
    )
    try selection.applyUpdate(to: "1.5.0")
    let selectionOutcome = await HomebrewCaskUpdateOperation.execute(
        confirmed: selectionPreparation,
        environment: selection.environment,
        scan: { _, _, _ in selectionBefore },
        reconcileAfterLaunch: { _ in (selection.diagnostic(), selection.environment) },
        updateRunner: selectionRunner,
        operationRunner: selectionMutation,
        gate: OperationExecutionGate()
    )
    expectRefusedCaskUpdate(selectionOutcome, runner: selectionMutation)
}

@Test func staleManagerTargetOrRootRefusesBeforeLaunch() async throws {
    let manager = try HomebrewCaskFixture("cask-stale-manager")
    defer { try? FileManager.default.removeItem(at: manager.root) }
    let managerDefinition = try manager.definition(acceptedOperations: [.homebrewCaskUpdate])
    let managerBefore = manager.diagnostic()
    let managerRunner = HomebrewCaskCommandRunner(fixture: manager)
    let managerMutation = HomebrewScriptedMutationRunner()
    let managerPreparation = try await preparedCaskUpdate(
        fixture: manager, definition: managerDefinition,
        diagnostic: managerBefore, runner: managerRunner
    )
    try manager.rewriteManager()
    let managerOutcome = await HomebrewCaskUpdateOperation.execute(
        confirmed: managerPreparation,
        environment: manager.environment,
        scan: { _, _, _ in managerBefore },
        reconcileAfterLaunch: { _ in (manager.diagnostic(), manager.environment) },
        updateRunner: managerRunner,
        operationRunner: managerMutation,
        gate: OperationExecutionGate()
    )
    expectRefusedCaskUpdate(managerOutcome, runner: managerMutation)

    let target = try HomebrewCaskFixture("cask-stale-target")
    defer { try? FileManager.default.removeItem(at: target.root) }
    let targetDefinition = try target.definition(acceptedOperations: [.homebrewCaskUpdate])
    let targetBefore = target.diagnostic()
    let targetRunner = HomebrewCaskCommandRunner(fixture: target)
    let targetMutation = HomebrewScriptedMutationRunner()
    let targetPreparation = try await preparedCaskUpdate(
        fixture: target, definition: targetDefinition,
        diagnostic: targetBefore, runner: targetRunner
    )
    target.state.version = "3.0.0"
    let targetOutcome = await HomebrewCaskUpdateOperation.execute(
        confirmed: targetPreparation,
        environment: target.environment,
        scan: { _, _, _ in targetBefore },
        reconcileAfterLaunch: { _ in (target.diagnostic(), target.environment) },
        updateRunner: targetRunner,
        operationRunner: targetMutation,
        gate: OperationExecutionGate()
    )
    expectRefusedCaskUpdate(targetOutcome, runner: targetMutation)
    #expect(targetOutcome.message == homebrewObservedTargetChangedMessage)

    let root = try HomebrewCaskFixture("cask-stale-root")
    defer { try? FileManager.default.removeItem(at: root.root) }
    let rootDefinition = try root.definition(acceptedOperations: [.homebrewCaskUpdate])
    let rootBefore = root.diagnostic()
    let rootRunner = HomebrewCaskCommandRunner(fixture: root)
    let rootMutation = HomebrewScriptedMutationRunner()
    let rootPreparation = try await preparedCaskUpdate(
        fixture: root, definition: rootDefinition,
        diagnostic: rootBefore, runner: rootRunner
    )
    try root.changePrefixMode(to: 0o750)
    let rootOutcome = await HomebrewCaskUpdateOperation.execute(
        confirmed: rootPreparation,
        environment: root.environment,
        scan: { _, _, _ in rootBefore },
        reconcileAfterLaunch: { _ in (root.diagnostic(), root.environment) },
        updateRunner: rootRunner,
        operationRunner: rootMutation,
        gate: OperationExecutionGate()
    )
    expectRefusedCaskUpdate(rootOutcome, runner: rootMutation)
}

@Test func cancelReleasesScratchSingleUseAndBusyGateReleaseThePreview() async throws {
    let fixture = try HomebrewCaskFixture("cask-cancel-gate")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewCaskUpdate])
    let before = fixture.diagnostic()
    let updateRunner = HomebrewCaskCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner()

    let cancelled = try await preparedCaskUpdate(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    let cancelledRoot = cancelled.preview.workingDirectory
    #expect(FileManager.default.fileExists(atPath: cancelledRoot))
    #expect(HomebrewCaskUpdateOperation.cancel(cancelled))
    #expect(!FileManager.default.fileExists(atPath: cancelledRoot))
    let replay = await HomebrewCaskUpdateOperation.execute(
        confirmed: cancelled,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (fixture.diagnostic(), fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    expectRefusedCaskUpdate(replay, runner: mutationRunner)

    let busy = try await preparedCaskUpdate(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    let gate = OperationExecutionGate()
    #expect(await gate.acquire())
    let contended = await HomebrewCaskUpdateOperation.execute(
        confirmed: busy,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (fixture.diagnostic(), fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: gate
    )
    await gate.release()
    #expect(contended.state == .cancelled)
    #expect(!contended.processStarted)
    #expect(mutationRunner.invocations.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: busy.preview.workingDirectory))
}

// MARK: - Saved installed metadata safeguard

@Test func savedInstalledUninstallStanzaRefusesBothOperationsWithoutLaunch() async throws {
    let fixture = try HomebrewCaskFixture("cask-saved-uninstall")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let sentinel = fixture.root.appendingPathComponent("saved-delete-sentinel.txt")
    try Data("intact\n".utf8).write(to: sentinel)
    try fixture.writeSavedCaskJSON(["artifacts": [
        fixture.binaryArtifact(),
        fixture.uninstallArtifact(path: sentinel.path),
    ]])
    let operationBase = fixture.root.appendingPathComponent("operation-base", isDirectory: true)
    try FileManager.default.createDirectory(at: operationBase, withIntermediateDirectories: true)
    let runner = HomebrewCaskCommandRunner(fixture: fixture)

    let update = await HomebrewCaskUpdateOperation.prepare(
        definition: try fixture.definition(acceptedOperations: [.homebrewCaskUpdate]),
        diagnostic: fixture.diagnostic(),
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: runner,
        operationRootBaseURL: operationBase
    )
    expectRefusedUpdatePreparation(update, equals: .caskUninstallRequiresElevation)
    let uninstall = await HomebrewCaskUninstallOperation.prepare(
        definition: try fixture.definition(acceptedOperations: [.homebrewCaskUninstall]),
        diagnostic: fixture.diagnostic(),
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: runner,
        operationRootBaseURL: operationBase
    )
    expectRefusedUninstallPreparation(uninstall, equals: .caskUninstallRequiresElevation)
    #expect(try homebrewScratchIsEmpty(operationBase))
    #expect(try String(contentsOf: sentinel, encoding: .utf8) == "intact\n")
}

@Test func savedSourceOnlyRepairOverrideCannotBypassReceiptRefusal() async throws {
    let stanza = try HomebrewCaskFixture("cask-saved-source-only-stanza")
    defer { try? FileManager.default.removeItem(at: stanza.root) }
    let sentinel = stanza.root.appendingPathComponent("saved-source-delete-sentinel.txt")
    try Data("intact\n".utf8).write(to: sentinel)
    // Saved source artifacts are clean; the receipt still carries a real uninstall stanza.
    try stanza.writeSavedCaskJSON(["artifacts": [stanza.binaryArtifact()]])
    try stanza.writeInstallReceipt(artifacts: [
        stanza.binaryArtifact(),
        stanza.uninstallArtifact(path: sentinel.path),
    ])
    let stanzaRunner = HomebrewCaskCommandRunner(fixture: stanza)
    let stanzaUpdate = await HomebrewCaskUpdateOperation.prepare(
        definition: try stanza.definition(acceptedOperations: [.homebrewCaskUpdate]),
        diagnostic: stanza.diagnostic(),
        environment: stanza.environment,
        currentDirectory: stanza.root.path,
        runner: stanzaRunner,
        operationRootBaseURL: stanza.root
    )
    expectRefusedUpdatePreparation(stanzaUpdate, equals: .caskUninstallRequiresElevation)
    let stanzaUninstall = await HomebrewCaskUninstallOperation.prepare(
        definition: try stanza.definition(acceptedOperations: [.homebrewCaskUninstall]),
        diagnostic: stanza.diagnostic(),
        environment: stanza.environment,
        currentDirectory: stanza.root.path,
        runner: stanzaRunner,
        operationRootBaseURL: stanza.root
    )
    expectRefusedUninstallPreparation(stanzaUninstall, equals: .caskUninstallRequiresElevation)
    #expect(try String(contentsOf: sentinel, encoding: .utf8) == "intact\n")

    let flight = try HomebrewCaskFixture("cask-saved-source-only-flight")
    defer { try? FileManager.default.removeItem(at: flight.root) }
    try flight.writeSavedCaskJSON(["artifacts": [flight.binaryArtifact()]])
    try flight.writeInstallReceipt(
        artifacts: [flight.binaryArtifact()],
        flightBlocks: true
    )
    let flightUpdate = await HomebrewCaskUpdateOperation.prepare(
        definition: try flight.definition(acceptedOperations: [.homebrewCaskUpdate]),
        diagnostic: flight.diagnostic(),
        environment: flight.environment,
        currentDirectory: flight.root.path,
        runner: HomebrewCaskCommandRunner(fixture: flight),
        operationRootBaseURL: flight.root
    )
    expectRefusedUpdatePreparation(flightUpdate, equals: .caskUninstallRequiresElevation)
}

@Test func olderSavedAppArtifactRefusesAgainstNewBinaryMetadata() async throws {
    let fixture = try HomebrewCaskFixture("cask-saved-old-app")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    // Current source now declares a clean binary; the saved installed definition still says app.
    try fixture.writeSavedCaskJSON(["artifacts": [
        fixture.appArtifact(name: "M13Old.app"),
    ]])
    let runner = HomebrewCaskCommandRunner(fixture: fixture)
    let update = await HomebrewCaskUpdateOperation.prepare(
        definition: try fixture.definition(acceptedOperations: [.homebrewCaskUpdate]),
        diagnostic: fixture.diagnostic(),
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: runner,
        operationRootBaseURL: fixture.root
    )
    expectRefusedUpdatePreparation(update, equals: .caskOperationUnsupported)
    let uninstall = await HomebrewCaskUninstallOperation.prepare(
        definition: try fixture.definition(acceptedOperations: [.homebrewCaskUninstall]),
        diagnostic: fixture.diagnostic(),
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: runner,
        operationRootBaseURL: fixture.root
    )
    expectRefusedUninstallPreparation(uninstall, equals: .caskOperationUnsupported)
}

@Test func savedInstalledScopeDrivesUninstallAndMergesIntoUpdateDisclosure() async throws {
    let fixture = try HomebrewCaskFixture(
        "cask-installed-scope", targetName: "m13new"
    )
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    // Current source now declares only the new binary.
    fixture.state.artifacts = [
        fixture.binaryArtifact(source: "m13new", targetName: "m13new")
    ]
    try fixture.install(version: "1.0.0")
    // The saved installed definition retains the old binary and its resolved target.
    let oldSource = fixture.versionDirectory("1.0.0").appendingPathComponent("m13old")
    try writeHomebrewExecutable(oldSource, "#!/bin/sh\nexit 0\n")
    let oldTarget = fixture.binDirectory.appendingPathComponent("m13old")
    try FileManager.default.createSymbolicLink(
        atPath: oldTarget.path, withDestinationPath: oldSource.path
    )
    try fixture.writeSavedCaskJSON(["artifacts": [[
        "binary": ["m13old"],
        "target": oldTarget.path,
    ]]])
    let currentTarget = fixture.binDirectory.appendingPathComponent("m13new").path
    let runner = HomebrewCaskCommandRunner(fixture: fixture)

    let update = try await preparedCaskUpdate(
        fixture: fixture,
        definition: try fixture.definition(acceptedOperations: [.homebrewCaskUpdate]),
        diagnostic: fixture.diagnostic(),
        runner: runner
    )
    #expect(update.preview.artifactTargets.contains {
        $0.target == oldTarget.path
    })
    #expect(update.preview.artifactTargets.contains {
        $0.target == currentTarget
    })
    #expect(HomebrewCaskUpdateOperation.cancel(update))

    let uninstall = try await preparedCaskUninstall(
        fixture: fixture,
        definition: try fixture.definition(acceptedOperations: [.homebrewCaskUninstall]),
        diagnostic: fixture.diagnostic(),
        runner: runner
    )
    #expect(uninstall.preview.artifactTargets == [
        HomebrewCaskArtifactTarget(
            kind: .binary, target: oldTarget.path, presence: .linked
        )
    ])
    #expect(HomebrewCaskUninstallOperation.cancel(uninstall))
}

@Test func savedMetadataChangeOrSamePathReplacementAfterPrepareAbortsBeforeLaunch() async throws {
    let changed = try HomebrewCaskFixture("cask-saved-changed-after-prepare")
    defer { try? FileManager.default.removeItem(at: changed.root) }
    let changedDefinition = try changed.definition(acceptedOperations: [.homebrewCaskUpdate])
    let changedBefore = changed.diagnostic()
    let changedRunner = HomebrewCaskCommandRunner(fixture: changed)
    let changedMutation = HomebrewScriptedMutationRunner()
    let changedPreparation = try await preparedCaskUpdate(
        fixture: changed, definition: changedDefinition,
        diagnostic: changedBefore, runner: changedRunner
    )
    // Valid JSON with the same identity facts, but different bounded bytes than the preview.
    try changed.writeSavedCaskJSON(["version": "1.0.0"])
    let changedOutcome = await HomebrewCaskUpdateOperation.execute(
        confirmed: changedPreparation,
        environment: changed.environment,
        scan: { _, _, _ in changedBefore },
        reconcileAfterLaunch: { _ in (changed.diagnostic(), changed.environment) },
        updateRunner: changedRunner,
        operationRunner: changedMutation,
        gate: OperationExecutionGate()
    )
    expectRefusedCaskUpdate(changedOutcome, runner: changedMutation)

    let replaced = try HomebrewCaskFixture("cask-saved-replaced-after-prepare")
    defer { try? FileManager.default.removeItem(at: replaced.root) }
    let replacedDefinition = try replaced.definition(
        acceptedOperations: [.homebrewCaskUninstall]
    )
    let replacedBefore = replaced.diagnostic()
    let replacedRunner = HomebrewCaskCommandRunner(fixture: replaced)
    let replacedMutation = HomebrewScriptedMutationRunner()
    let replacedPreparation = try await preparedCaskUninstall(
        fixture: replaced, definition: replacedDefinition,
        diagnostic: replacedBefore, runner: replacedRunner
    )
    let receiptData = try Data(contentsOf: replaced.metadataReceiptURL)
    try FileManager.default.removeItem(at: replaced.metadataReceiptURL)
    try receiptData.write(to: replaced.metadataReceiptURL)
    let replacedOutcome = await HomebrewCaskUninstallOperation.execute(
        confirmed: replacedPreparation,
        environment: replaced.environment,
        scan: { _, _, _ in replacedBefore },
        reconcileAfterLaunch: { _ in (replaced.diagnostic(), replaced.environment) },
        updateRunner: replacedRunner,
        operationRunner: replacedMutation,
        gate: OperationExecutionGate()
    )
    expectRefusedCaskUninstall(replacedOutcome, runner: replacedMutation)
}

@Test func malformedMissingOversizedOrSymlinkedSavedMetadataRefusesBothOperations() async throws {
    func assertBothRefuse(_ fixture: HomebrewCaskFixture) async throws {
        let operationBase = fixture.root.appendingPathComponent(
            "operation-base", isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: operationBase, withIntermediateDirectories: true
        )
        let runner = HomebrewCaskCommandRunner(fixture: fixture)
        let update = await HomebrewCaskUpdateOperation.prepare(
            definition: try fixture.definition(acceptedOperations: [.homebrewCaskUpdate]),
            diagnostic: fixture.diagnostic(),
            environment: fixture.environment,
            currentDirectory: fixture.root.path,
            runner: runner,
            operationRootBaseURL: operationBase
        )
        expectRefusedUpdatePreparation(update, equals: .metadataInvalid)
        let uninstall = await HomebrewCaskUninstallOperation.prepare(
            definition: try fixture.definition(
                acceptedOperations: [.homebrewCaskUninstall]
            ),
            diagnostic: fixture.diagnostic(),
            environment: fixture.environment,
            currentDirectory: fixture.root.path,
            runner: runner,
            operationRootBaseURL: operationBase
        )
        expectRefusedUninstallPreparation(uninstall, equals: .metadataInvalid)
        #expect(try homebrewScratchIsEmpty(operationBase))
    }

    let malformed = try HomebrewCaskFixture("cask-saved-malformed")
    defer { try? FileManager.default.removeItem(at: malformed.root) }
    try Data("{ not json".utf8).write(to: malformed.metadataCaskJSONURL())
    try await assertBothRefuse(malformed)

    let malformedReceipt = try HomebrewCaskFixture("cask-saved-malformed-receipt")
    defer { try? FileManager.default.removeItem(at: malformedReceipt.root) }
    try Data("{".utf8).write(to: malformedReceipt.metadataReceiptURL)
    try await assertBothRefuse(malformedReceipt)

    let missing = try HomebrewCaskFixture("cask-saved-missing-receipt")
    defer { try? FileManager.default.removeItem(at: missing.root) }
    try FileManager.default.removeItem(at: missing.metadataReceiptURL)
    try await assertBothRefuse(missing)

    let oversized = try HomebrewCaskFixture("cask-saved-oversized")
    defer { try? FileManager.default.removeItem(at: oversized.root) }
    try Data(
        repeating: 0x20,
        count: HomebrewCaskObservation.maximumSavedMetadataBytes + 1
    ).write(to: oversized.metadataCaskJSONURL())
    try await assertBothRefuse(oversized)

    let symlinked = try HomebrewCaskFixture("cask-saved-symlink")
    defer { try? FileManager.default.removeItem(at: symlinked.root) }
    let alternate = symlinked.root.appendingPathComponent("alternate-cask.json")
    try Data("{}".utf8).write(to: alternate)
    try FileManager.default.removeItem(at: symlinked.metadataCaskJSONURL())
    try FileManager.default.createSymbolicLink(
        atPath: symlinked.metadataCaskJSONURL().path,
        withDestinationPath: alternate.path
    )
    try await assertBothRefuse(symlinked)

    let symlinkedReceipt = try HomebrewCaskFixture("cask-saved-symlink-receipt")
    defer { try? FileManager.default.removeItem(at: symlinkedReceipt.root) }
    let alternateReceipt = symlinkedReceipt.root.appendingPathComponent("alternate-receipt.json")
    let receiptData = try Data(contentsOf: symlinkedReceipt.metadataReceiptURL)
    try receiptData.write(to: alternateReceipt)
    try FileManager.default.removeItem(at: symlinkedReceipt.metadataReceiptURL)
    try FileManager.default.createSymbolicLink(
        atPath: symlinkedReceipt.metadataReceiptURL.path,
        withDestinationPath: alternateReceipt.path
    )
    try await assertBothRefuse(symlinkedReceipt)

    let legacy = try HomebrewCaskFixture("cask-saved-legacy-ruby")
    defer { try? FileManager.default.removeItem(at: legacy.root) }
    try FileManager.default.removeItem(at: legacy.metadataCaskJSONURL())
    try Data("Cask::DSL".utf8).write(
        to: legacy.metadataCaskDirectory().appendingPathComponent("m13cask.rb")
    )
    try await assertBothRefuse(legacy)
}

@Test func savedMetadataTapOrVersionDiscontinuityRefuses() async throws {
    let tapMismatch = try HomebrewCaskFixture("cask-saved-tap-mismatch")
    defer { try? FileManager.default.removeItem(at: tapMismatch.root) }
    try tapMismatch.writeInstallReceipt(
        artifacts: [tapMismatch.binaryArtifact()],
        sourceTap: "m13test/other-tap"
    )
    let tapUpdate = await HomebrewCaskUpdateOperation.prepare(
        definition: try tapMismatch.definition(acceptedOperations: [.homebrewCaskUpdate]),
        diagnostic: tapMismatch.diagnostic(),
        environment: tapMismatch.environment,
        currentDirectory: tapMismatch.root.path,
        runner: HomebrewCaskCommandRunner(fixture: tapMismatch),
        operationRootBaseURL: tapMismatch.root
    )
    expectRefusedUpdatePreparation(tapUpdate, equals: .identityUnverified)

    let versionMismatch = try HomebrewCaskFixture("cask-saved-version-mismatch")
    defer { try? FileManager.default.removeItem(at: versionMismatch.root) }
    try versionMismatch.writeSavedCaskJSON(["version": "9.9.9"])
    let versionUninstall = await HomebrewCaskUninstallOperation.prepare(
        definition: try versionMismatch.definition(
            acceptedOperations: [.homebrewCaskUninstall]
        ),
        diagnostic: versionMismatch.diagnostic(),
        environment: versionMismatch.environment,
        currentDirectory: versionMismatch.root.path,
        runner: HomebrewCaskCommandRunner(fixture: versionMismatch),
        operationRootBaseURL: versionMismatch.root
    )
    expectRefusedUninstallPreparation(versionUninstall, equals: .identityUnverified)
}

// MARK: - Exit zero, failed reconciliation and interruption

@Test func cancelReleasesCaskUninstallScratchAndCannotReplay() async throws {
    let fixture = try HomebrewCaskFixture("cask-uninstall-cancel")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewCaskUninstall])
    let before = fixture.diagnostic()
    let updateRunner = HomebrewCaskCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner()
    let preparation = try await preparedCaskUninstall(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    let root = preparation.preview.workingDirectory
    #expect(FileManager.default.fileExists(atPath: root))
    #expect(HomebrewCaskUninstallOperation.cancel(preparation))
    #expect(!FileManager.default.fileExists(atPath: root))
    let replay = await HomebrewCaskUninstallOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (fixture.diagnostic(), fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    expectRefusedCaskUninstall(replay, runner: mutationRunner)
}

@Test func exitZeroWithoutCaskRemovalIsUncertain() async throws {
    let fixture = try HomebrewCaskFixture("cask-uninstall-no-change")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewCaskUninstall])
    let before = fixture.diagnostic()
    let updateRunner = HomebrewCaskCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner()
    let preparation = try await preparedCaskUninstall(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    let outcome = await HomebrewCaskUninstallOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (fixture.diagnostic(), fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    #expect(outcome.state == .uncertain)
    #expect(outcome.processStarted)
    #expect(outcome.exitStatus == 0)
    let delta = try #require(outcome.reconciliation)
    #expect(!delta.infoInstalledAbsent)
    #expect(!delta.tokenDirectoryAbsent)
    #expect(!delta.selectedTargetReleased)
    #expect(!delta.managedTargetsReleased)
    #expect(!delta.observationFailed)
    #expect(!delta.changed)
}

@Test func caskUninstallNoOpWithInfoFailureIsUncertainAndUnchanged() async throws {
    let fixture = try HomebrewCaskFixture("cask-uninstall-info-failure-no-change")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewCaskUninstall])
    let before = fixture.diagnostic()
    let updateRunner = HomebrewCaskCommandRunner(fixture: fixture)
    // Post-launch info fails; the installation itself is a real no-op.
    let mutationRunner = HomebrewScriptedMutationRunner(
        onLaunch: { fixture.state.infoFailure = true }
    )
    let preparation = try await preparedCaskUninstall(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    let outcome = await HomebrewCaskUninstallOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (fixture.diagnostic(), fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    #expect(outcome.state == .uncertain)
    #expect(outcome.processStarted)
    #expect(outcome.exitStatus == 0)
    let delta = try #require(outcome.reconciliation)
    #expect(delta.afterInstalledVersion == nil)
    #expect(delta.observationFailed)
    #expect(!delta.changed)
    #expect(!delta.infoInstalledAbsent)
}

@Test func failedCaskReconciliationIsNeverSuccess() async throws {
    let fixture = try HomebrewCaskFixture("cask-reconcile-failure")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewCaskUpdate])
    let before = fixture.diagnostic()
    let updateRunner = HomebrewCaskCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner(
        onLaunch: { try? fixture.applyUpdate(to: "2.0.0") }
    )
    let preparation = try await preparedCaskUpdate(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    let outcome = await HomebrewCaskUpdateOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in
            fixture.state.infoFailure = true
            return (fixture.diagnostic(), fixture.environment)
        },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    #expect(outcome.state == .uncertain)
    #expect(outcome.processStarted)
    #expect(outcome.exitStatus == 0)
    let delta = try #require(outcome.reconciliation)
    #expect(delta.observationFailed)
    #expect(!delta.versionMatchesTarget)
}

@Test func caskUpdateNoOpWithInfoFailureIsUncertainAndUnchanged() async throws {
    let fixture = try HomebrewCaskFixture("cask-update-info-failure-no-change")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewCaskUpdate])
    let before = fixture.diagnostic()
    let updateRunner = HomebrewCaskCommandRunner(fixture: fixture)
    // Post-launch info fails; the installation itself is a real no-op.
    let mutationRunner = HomebrewScriptedMutationRunner(
        onLaunch: { fixture.state.infoFailure = true }
    )
    let preparation = try await preparedCaskUpdate(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    let outcome = await HomebrewCaskUpdateOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (fixture.diagnostic(), fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    #expect(outcome.state == .uncertain)
    #expect(outcome.processStarted)
    #expect(outcome.exitStatus == 0)
    let delta = try #require(outcome.reconciliation)
    #expect(delta.afterInstalledVersion == nil)
    #expect(delta.observationFailed)
    #expect(!delta.changed)
    #expect(!delta.managedTargetsReleased)
}

@Test func canceledLaunchedCaskUpdateIsInterruptedAndReconciled() async throws {
    let fixture = try HomebrewCaskFixture("cask-interrupted")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewCaskUpdate])
    let before = fixture.diagnostic()
    let updateRunner = HomebrewCaskCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner(
        result: OperationCommandResult(
            stdout: Data(), stderr: Data(),
            stdoutTruncated: false, stderrTruncated: false,
            exitStatus: nil, processStarted: true,
            timedOut: false, cancelled: true, cleanupWarning: false
        ),
        onLaunch: { try? fixture.applyUpdate(to: "2.0.0") }
    )
    let preparation = try await preparedCaskUpdate(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    let outcome = await HomebrewCaskUpdateOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (fixture.diagnostic(), fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    #expect(outcome.state == .interrupted)
    #expect(outcome.processStarted)
    #expect(outcome.reconciliation?.versionMatchesTarget == true)
    #expect(outcome.reconciliation?.stagedMembershipConfirmed == true)
    #expect(outcome.message?.contains("interrupted") == true)
    #expect(!FileManager.default.fileExists(atPath: preparation.preview.workingDirectory))
}

// MARK: - Real saved layout, dependencies and target exactness

@Test func realTimestampSelectionRefusesNewerEmptyOrTiedDirectory() async throws {
    let fixture = try HomebrewCaskFixture("cask-real-timestamp")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let newerCasks = fixture.metadataCaskDirectory(timestamp: "20260101000000.999")
    try FileManager.default.createDirectory(at: newerCasks, withIntermediateDirectories: true)
    let runner = HomebrewCaskCommandRunner(fixture: fixture)
    let operationBase = fixture.root.appendingPathComponent("operation-base", isDirectory: true)
    try FileManager.default.createDirectory(at: operationBase, withIntermediateDirectories: true)

    let update = await HomebrewCaskUpdateOperation.prepare(
        definition: try fixture.definition(acceptedOperations: [.homebrewCaskUpdate]),
        diagnostic: fixture.diagnostic(),
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: runner,
        operationRootBaseURL: operationBase
    )
    expectRefusedUpdatePreparation(update, equals: .metadataInvalid)
    let uninstall = await HomebrewCaskUninstallOperation.prepare(
        definition: try fixture.definition(acceptedOperations: [.homebrewCaskUninstall]),
        diagnostic: fixture.diagnostic(),
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: runner,
        operationRootBaseURL: operationBase
    )
    expectRefusedUninstallPreparation(uninstall, equals: .metadataInvalid)
    #expect(try homebrewScratchIsEmpty(operationBase))

    // The newer timestamp is selected before looking for a caskfile. Once it has a valid `{}`
    // cask, the older complete fixture directory is no longer the manager's source.
    try Data("{}".utf8).write(to: newerCasks.appendingPathComponent("m13cask.json"))
    let preparation = try await preparedCaskUpdate(
        fixture: fixture,
        definition: try fixture.definition(acceptedOperations: [.homebrewCaskUpdate]),
        diagnostic: fixture.diagnostic(),
        runner: runner
    )
    #expect(HomebrewCaskUpdateOperation.cancel(preparation))
}

@Test func tiedGreatestTimestampAcrossVersionsRefuses() async throws {
    let fixture = try HomebrewCaskFixture("cask-timestamp-tie")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let tiedCasks = fixture.metadataCaskDirectory(
        version: "0.9.0", timestamp: HomebrewCaskFixture.defaultMetadataTimestamp
    )
    try FileManager.default.createDirectory(at: tiedCasks, withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: tiedCasks.appendingPathComponent("m13cask.json"))
    let result = await HomebrewCaskUpdateOperation.prepare(
        definition: try fixture.definition(acceptedOperations: [.homebrewCaskUpdate]),
        diagnostic: fixture.diagnostic(),
        environment: fixture.environment,
        currentDirectory: fixture.root.path,
        runner: HomebrewCaskCommandRunner(fixture: fixture),
        operationRootBaseURL: fixture.root
    )
    expectRefusedUpdatePreparation(result, equals: .metadataInvalid)
}

@Test func savedConfigAndLatestChecksumAreAllowedButUnsafeOrReplacedConfigRefuses() async throws {
    let allowed = try HomebrewCaskFixture("cask-config-allowed")
    defer { try? FileManager.default.removeItem(at: allowed.root) }
    try Data("abc123\n".utf8).write(
        to: allowed.metadataDirectory.appendingPathComponent("LATEST_DOWNLOAD_SHA256")
    )
    let allowedPreparation = try await preparedCaskUpdate(
        fixture: allowed,
        definition: try allowed.definition(acceptedOperations: [.homebrewCaskUpdate]),
        diagnostic: allowed.diagnostic(),
        runner: HomebrewCaskCommandRunner(fixture: allowed)
    )
    #expect(HomebrewCaskUpdateOperation.cancel(allowedPreparation))

    let latest = try HomebrewCaskFixture(
        "cask-latest-checksum", installedVersion: "latest", version: "latest",
        outdated: false, hasOutdatedRecord: false
    )
    defer { try? FileManager.default.removeItem(at: latest.root) }
    try latest.writeInstalledMetadata(latestDownloadSHA: "def456\n")
    let latestPreparation = try await preparedCaskUninstall(
        fixture: latest,
        definition: try latest.definition(acceptedOperations: [.homebrewCaskUninstall]),
        diagnostic: latest.diagnostic(),
        runner: HomebrewCaskCommandRunner(fixture: latest)
    )
    #expect(HomebrewCaskUninstallOperation.cancel(latestPreparation))

    let symlinked = try HomebrewCaskFixture("cask-config-symlink")
    defer { try? FileManager.default.removeItem(at: symlinked.root) }
    let alternate = symlinked.root.appendingPathComponent("alternate-config.json")
    try Data("{}".utf8).write(to: alternate)
    let configURL = symlinked.metadataDirectory.appendingPathComponent("config.json")
    try FileManager.default.removeItem(at: configURL)
    try FileManager.default.createSymbolicLink(
        atPath: configURL.path, withDestinationPath: alternate.path
    )
    let symlinkResult = await HomebrewCaskUpdateOperation.prepare(
        definition: try symlinked.definition(acceptedOperations: [.homebrewCaskUpdate]),
        diagnostic: symlinked.diagnostic(),
        environment: symlinked.environment,
        currentDirectory: symlinked.root.path,
        runner: HomebrewCaskCommandRunner(fixture: symlinked),
        operationRootBaseURL: symlinked.root
    )
    expectRefusedUpdatePreparation(symlinkResult, equals: .metadataInvalid)

    let replaced = try HomebrewCaskFixture("cask-config-replaced")
    defer { try? FileManager.default.removeItem(at: replaced.root) }
    let replacedDefinition = try replaced.definition(acceptedOperations: [.homebrewCaskUpdate])
    let replacedBefore = replaced.diagnostic()
    let replacedRunner = HomebrewCaskCommandRunner(fixture: replaced)
    let replacedMutation = HomebrewScriptedMutationRunner()
    let replacedPreparation = try await preparedCaskUpdate(
        fixture: replaced, definition: replacedDefinition,
        diagnostic: replacedBefore, runner: replacedRunner
    )
    try replaced.writeSavedConfig([
        "default": ["languages": ["fr"]],
        "env": [String: Any](),
        "explicit": [String: Any](),
    ])
    let replacedOutcome = await HomebrewCaskUpdateOperation.execute(
        confirmed: replacedPreparation,
        environment: replaced.environment,
        scan: { _, _, _ in replacedBefore },
        reconcileAfterLaunch: { _ in (replaced.diagnostic(), replaced.environment) },
        updateRunner: replacedRunner,
        operationRunner: replacedMutation,
        gate: OperationExecutionGate()
    )
    expectRefusedCaskUpdate(replacedOutcome, runner: replacedMutation)
}

@Test func caskUpdateRefusesPackageDependenciesBeforeScratchAndRevalidates() async throws {
    let dependent = try HomebrewCaskFixture("cask-dependent-update")
    defer { try? FileManager.default.removeItem(at: dependent.root) }
    dependent.state.dependsOn = [
        "formula": ["some-formula"],
        "cask": ["some-cask"],
    ] as [String: Any]
    let operationBase = dependent.root.appendingPathComponent("operation-base", isDirectory: true)
    try FileManager.default.createDirectory(at: operationBase, withIntermediateDirectories: true)
    let dependentUpdate = await HomebrewCaskUpdateOperation.prepare(
        definition: try dependent.definition(acceptedOperations: [.homebrewCaskUpdate]),
        diagnostic: dependent.diagnostic(),
        environment: dependent.environment,
        currentDirectory: dependent.root.path,
        runner: HomebrewCaskCommandRunner(fixture: dependent),
        operationRootBaseURL: operationBase
    )
    expectRefusedUpdatePreparation(dependentUpdate, equals: .caskOperationUnsupported)
    #expect(try homebrewScratchIsEmpty(operationBase))

    // Uninstall policy is unchanged: package dependencies are Homebrew's own refusal to surface.
    let dependentUninstall = try await preparedCaskUninstall(
        fixture: dependent,
        definition: try dependent.definition(acceptedOperations: [.homebrewCaskUninstall]),
        diagnostic: dependent.diagnostic(),
        runner: HomebrewCaskCommandRunner(fixture: dependent)
    )
    #expect(HomebrewCaskUninstallOperation.cancel(dependentUninstall))

    let malformed = try HomebrewCaskFixture("cask-malformed-depends-on")
    defer { try? FileManager.default.removeItem(at: malformed.root) }
    malformed.state.dependsOn = "not-an-object"
    let malformedResult = await HomebrewCaskUpdateOperation.prepare(
        definition: try malformed.definition(acceptedOperations: [.homebrewCaskUpdate]),
        diagnostic: malformed.diagnostic(),
        environment: malformed.environment,
        currentDirectory: malformed.root.path,
        runner: HomebrewCaskCommandRunner(fixture: malformed),
        operationRootBaseURL: malformed.root
    )
    expectRefusedUpdatePreparation(malformedResult, equals: .metadataInvalid)

    let revalidated = try HomebrewCaskFixture("cask-dependent-revalidated")
    defer { try? FileManager.default.removeItem(at: revalidated.root) }
    let definition = try revalidated.definition(acceptedOperations: [.homebrewCaskUpdate])
    let before = revalidated.diagnostic()
    let updateRunner = HomebrewCaskCommandRunner(fixture: revalidated)
    let mutationRunner = HomebrewScriptedMutationRunner()
    let preparation = try await preparedCaskUpdate(
        fixture: revalidated, definition: definition,
        diagnostic: before, runner: updateRunner
    )
    revalidated.state.dependsOn = ["cask": ["some-cask"]] as [String: Any]
    let outcome = await HomebrewCaskUpdateOperation.execute(
        confirmed: preparation,
        environment: revalidated.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (revalidated.diagnostic(), revalidated.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    expectRefusedCaskUpdate(
        outcome, runner: mutationRunner, messageContains: "dependencies"
    )
}

@Test func savedExplicitAliasAndMissingCurrentTargetAreNeverBorrowed() async throws {
    let explicit = try HomebrewCaskFixture(
        "cask-saved-explicit-alias", targetName: "m13old"
    )
    defer { try? FileManager.default.removeItem(at: explicit.root) }
    let oldTarget = explicit.binDirectory.appendingPathComponent("m13old")
    let oldArtifacts: [[String: Any]] = [[
        "binary": ["m13cask", ["target": "m13old"]] as [Any],
        "target": oldTarget.path,
    ]]
    explicit.state.artifacts = oldArtifacts
    try explicit.install(version: "1.0.0")
    let newTarget = explicit.binDirectory.appendingPathComponent("m13other")
    explicit.state.artifacts = [[
        "binary": ["m13cask", ["target": "m13other"]] as [Any],
        "target": newTarget.path,
    ]]
    let explicitPreparation = try await preparedCaskUpdate(
        fixture: explicit,
        definition: try explicit.definition(acceptedOperations: [.homebrewCaskUpdate]),
        diagnostic: explicit.diagnostic(),
        runner: HomebrewCaskCommandRunner(fixture: explicit)
    )
    #expect(explicitPreparation.preview.artifactTargets.contains {
        $0.target == oldTarget.path && $0.presence == .linked
    })
    #expect(explicitPreparation.preview.artifactTargets.contains {
        $0.target == newTarget.path && $0.presence == .absent
    })
    #expect(HomebrewCaskUpdateOperation.cancel(explicitPreparation))

    let borrowed = try HomebrewCaskFixture("cask-borrowed-missing")
    defer { try? FileManager.default.removeItem(at: borrowed.root) }
    let oldDefaultTarget = borrowed.binDirectory.appendingPathComponent("m13cask")
    let missingTarget = borrowed.binDirectory.appendingPathComponent("m13missing")
    borrowed.state.artifacts = [[
        "binary": ["m13cask", ["target": "m13missing"]] as [Any],
        "target": missingTarget.path,
    ]]
    let borrowedPreparation = try await preparedCaskUpdate(
        fixture: borrowed,
        definition: try borrowed.definition(acceptedOperations: [.homebrewCaskUpdate]),
        diagnostic: borrowed.diagnostic(),
        runner: HomebrewCaskCommandRunner(fixture: borrowed)
    )
    #expect(borrowedPreparation.preview.artifactTargets.contains {
        $0.target == oldDefaultTarget.path && $0.presence == .linked
    })
    #expect(borrowedPreparation.preview.artifactTargets.contains {
        $0.target == missingTarget.path && $0.presence == .absent
    })
    #expect(HomebrewCaskUpdateOperation.cancel(borrowedPreparation))
}

@Test func currentExplicitTargetMustMatchResolvedDestinationAndPrefixBin() async throws {
    let mismatched = try HomebrewCaskFixture("cask-current-target-mismatch")
    defer { try? FileManager.default.removeItem(at: mismatched.root) }
    let resolved = mismatched.binDirectory.appendingPathComponent("m13different")
    mismatched.state.artifacts = [[
        "binary": ["m13cask", ["target": "m13expected"]] as [Any],
        "target": resolved.path,
    ]]
    try mismatched.install(version: "1.0.0")
    let mismatchResult = await HomebrewCaskUpdateOperation.prepare(
        definition: try mismatched.definition(acceptedOperations: [.homebrewCaskUpdate]),
        diagnostic: mismatched.diagnostic(),
        environment: mismatched.environment,
        currentDirectory: mismatched.root.path,
        runner: HomebrewCaskCommandRunner(fixture: mismatched),
        operationRootBaseURL: mismatched.root
    )
    expectRefusedUpdatePreparation(mismatchResult, equals: .caskArtifactTargetUnverified)

    let outside = try HomebrewCaskFixture("cask-current-target-outside")
    defer { try? FileManager.default.removeItem(at: outside.root) }
    let outsideTarget = outside.root.appendingPathComponent("outside-bin/m13cask")
    outside.state.artifacts = [[
        "binary": ["m13cask"],
        "target": outsideTarget.path,
    ]]
    try outside.install(version: "1.0.0")
    let outsideResult = await HomebrewCaskUpdateOperation.prepare(
        definition: try outside.definition(acceptedOperations: [.homebrewCaskUpdate]),
        diagnostic: outside.diagnostic(),
        environment: outside.environment,
        currentDirectory: outside.root.path,
        runner: HomebrewCaskCommandRunner(fixture: outside),
        operationRootBaseURL: outside.root
    )
    expectRefusedUpdatePreparation(outsideResult, equals: .caskArtifactTargetUnverified)
}

@Test func caskUpdateDoesNotSucceedWithOldInstalledTargetLeftBehind() async throws {
    let fixture = try HomebrewCaskFixture(
        "cask-update-old-target-residue", targetName: "m13new"
    )
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    fixture.state.artifacts = [
        fixture.binaryArtifact(source: "m13new", targetName: "m13new")
    ]
    try fixture.install(version: "1.0.0")
    let oldSource = fixture.versionDirectory("1.0.0").appendingPathComponent("m13old")
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: oldSource)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755], ofItemAtPath: oldSource.path
    )
    let oldTarget = fixture.binDirectory.appendingPathComponent("m13old")
    try FileManager.default.createSymbolicLink(
        atPath: oldTarget.path, withDestinationPath: oldSource.path
    )
    try fixture.writeSavedCaskJSON(["artifacts": [[
        "binary": ["m13old"],
        "target": oldTarget.path,
    ]]])
    let definition = try fixture.definition(acceptedOperations: [.homebrewCaskUpdate])
    let before = fixture.diagnostic()
    let updateRunner = HomebrewCaskCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner(
        onLaunch: { try? fixture.applyUpdate(to: "2.0.0") }
    )
    let preparation = try await preparedCaskUpdate(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    let outcome = await HomebrewCaskUpdateOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (fixture.diagnostic(), fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    #expect(outcome.state == .uncertain)
    let delta = try #require(outcome.reconciliation)
    #expect(delta.managedTargets.contains {
        $0.target == oldTarget.path && $0.release == .stillPresent
    })
    #expect(!delta.managedTargetsReleased)
}

@Test func caskUpdateExitZeroWithoutChangeReportsNoDeltaChange() async throws {
    let fixture = try HomebrewCaskFixture("cask-update-no-change")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let definition = try fixture.definition(acceptedOperations: [.homebrewCaskUpdate])
    let before = fixture.diagnostic()
    let updateRunner = HomebrewCaskCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner()
    let preparation = try await preparedCaskUpdate(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    let outcome = await HomebrewCaskUpdateOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (fixture.diagnostic(), fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    #expect(outcome.state == .uncertain)
    let delta = try #require(outcome.reconciliation)
    #expect(!delta.versionMatchesTarget)
    #expect(delta.managedTargets.map(\.release) == [
        HomebrewCaskManagedTargetRelease.stillPresent,
    ])
    #expect(!delta.changed)
}

@Test func caskUninstallDoesNotTreatAbsentPreviewTargetOccupancyAsClean() async throws {
    let fixture = try HomebrewCaskFixture("cask-uninstall-absent-preview")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let target = fixture.binDirectory.appendingPathComponent("m13cask")
    try FileManager.default.removeItem(at: target)
    // Keep the selected entry live via its staged source; only the manager-declared target link
    // is absent at preview.
    let source = try #require(fixture.selectedTarget(version: "1.0.0"))
    try FileManager.default.removeItem(at: fixture.entry)
    try FileManager.default.createSymbolicLink(
        atPath: fixture.entry.path, withDestinationPath: source
    )
    let definition = try fixture.definition(acceptedOperations: [.homebrewCaskUninstall])
    let before = fixture.diagnostic()
    let updateRunner = HomebrewCaskCommandRunner(fixture: fixture)
    let other = fixture.root.appendingPathComponent("unrelated-target")
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: other)
    let mutationRunner = HomebrewScriptedMutationRunner(
        onLaunch: {
            try? fixture.applyUninstall()
            try? FileManager.default.createSymbolicLink(
                atPath: target.path, withDestinationPath: other.path
            )
        }
    )
    let preparation = try await preparedCaskUninstall(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    #expect(preparation.preview.artifactTargets == [
        HomebrewCaskArtifactTarget(
            kind: .binary, target: target.path, presence: .absent
        ),
    ])
    let outcome = await HomebrewCaskUninstallOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (fixture.diagnostic(), fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    #expect(outcome.state == .uncertain)
    let delta = try #require(outcome.reconciliation)
    #expect(delta.managedTargets.map(\.release) == [
        HomebrewCaskManagedTargetRelease.occupiedAfterAbsentPreview,
    ])
    #expect(!delta.managedTargetsReleased)
}

@Test func caskUpdateDoesNotTreatAbsentPreviewTargetOccupancyAsClean() async throws {
    let fixture = try HomebrewCaskFixture("cask-update-absent-preview")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    fixture.state.artifacts = [
        fixture.binaryArtifact(source: "m13cask", targetName: "m13cask"),
        fixture.binaryArtifact(source: "m13second", targetName: "m13second"),
    ]
    try fixture.install(version: "1.0.0")
    let secondaryTarget = fixture.binDirectory.appendingPathComponent("m13second")
    try FileManager.default.removeItem(at: secondaryTarget)
    let unrelated = fixture.root.appendingPathComponent("unrelated-target")
    try writeHomebrewExecutable(unrelated, "#!/bin/sh\nexit 0\n")
    let definition = try fixture.definition(acceptedOperations: [.homebrewCaskUpdate])
    let before = fixture.diagnostic()
    let updateRunner = HomebrewCaskCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner(
        onLaunch: {
            try? fixture.applyUpdate(to: "2.0.0")
            try? FileManager.default.removeItem(at: secondaryTarget)
            try? FileManager.default.createSymbolicLink(
                atPath: secondaryTarget.path, withDestinationPath: unrelated.path
            )
        }
    )
    let preparation = try await preparedCaskUpdate(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    #expect(preparation.preview.artifactTargets.contains {
        $0.target == secondaryTarget.path && $0.presence == .absent
    })
    let outcome = await HomebrewCaskUpdateOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (fixture.diagnostic(), fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    #expect(outcome.state == .uncertain)
    let delta = try #require(outcome.reconciliation)
    #expect(delta.managedTargets.contains {
        $0.target == secondaryTarget.path
            && $0.release == .occupiedAfterAbsentPreview
    })
    #expect(delta.managedTargets.contains {
        $0.target == fixture.binDirectory.appendingPathComponent("m13cask").path
            && $0.release == .retargeted
    })
    #expect(!delta.managedTargetsReleased)
}

@Test func caskUpdateDoesNotSucceedOnDifferentFileUnderNewStage() async throws {
    let fixture = try HomebrewCaskFixture("cask-update-absolute-different-stage-file")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let oldVersion = fixture.versionDirectory("1.0.0")
    let absoluteOldSource = oldVersion.appendingPathComponent("m13abs").path
    let secondaryTarget = fixture.binDirectory.appendingPathComponent("m13abs")
    fixture.state.artifacts = [
        fixture.binaryArtifact(),
        ["binary": [absoluteOldSource], "target": secondaryTarget.path],
    ]
    try fixture.install(version: "1.0.0")
    let definition = try fixture.definition(acceptedOperations: [.homebrewCaskUpdate])
    let before = fixture.diagnostic()
    let updateRunner = HomebrewCaskCommandRunner(fixture: fixture)
    let newVersion = fixture.versionDirectory("2.0.0")
    let impostor = newVersion.appendingPathComponent("m13impostor")
    let mutationRunner = HomebrewScriptedMutationRunner(
        onLaunch: {
            // A successful upgrade moves only the current primary artifact. The old absolute
            // secondary source is not part of the new stage; point its target at a different
            // regular file inside that verified stage.
            let installedArtifacts = fixture.state.artifacts
            fixture.state.artifacts = [fixture.binaryArtifact()]
            try? fixture.applyUpdate(to: "2.0.0")
            fixture.state.artifacts = installedArtifacts
            try? writeHomebrewExecutable(impostor, "#!/bin/sh\nexit 0\n")
            try? FileManager.default.removeItem(at: secondaryTarget)
            try? FileManager.default.createSymbolicLink(
                atPath: secondaryTarget.path, withDestinationPath: impostor.path
            )
        }
    )
    let preparation = try await preparedCaskUpdate(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    #expect(preparation.preview.artifactTargets.contains {
        $0.target == secondaryTarget.path && $0.presence == .linked
    })
    let outcome = await HomebrewCaskUpdateOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (fixture.diagnostic(), fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    #expect(outcome.state == .uncertain)
    let delta = try #require(outcome.reconciliation)
    #expect(delta.versionMatchesTarget)
    #expect(delta.stagedMembershipConfirmed)
    #expect(delta.managedTargets.contains {
        $0.target == fixture.binDirectory.appendingPathComponent("m13cask").path
            && $0.release == .retargeted
    })
    #expect(delta.managedTargets.contains {
        $0.target == secondaryTarget.path && $0.release == .observationFailed
    })
    #expect(!delta.managedTargetsReleased)
}

private func makeMovedAppCaskFixture(_ label: String) throws -> (
    fixture: HomebrewCaskFixture, appExecutable: URL
) {
    let fixture = try HomebrewCaskFixture(label)
    try FileManager.default.removeItem(at: fixture.tokenDirectory)
    try FileManager.default.removeItem(
        at: fixture.binDirectory.appendingPathComponent("m13cask")
    )
    try FileManager.default.removeItem(at: fixture.entry)

    let appDirectory = fixture.root.appendingPathComponent(
        "Applications/M13Old.app", isDirectory: true
    )
    let executable = appDirectory.appendingPathComponent("Contents/MacOS/m13app")
    try writeHomebrewExecutable(executable, "#!/bin/sh\nexit 0\n")
    let versionDirectory = fixture.versionDirectory("1.0.0")
    try FileManager.default.createDirectory(
        at: versionDirectory, withIntermediateDirectories: true
    )
    let appLink = versionDirectory.appendingPathComponent("M13Old.app")
    try FileManager.default.createSymbolicLink(
        atPath: appLink.path, withDestinationPath: appDirectory.path
    )
    try FileManager.default.createSymbolicLink(
        atPath: fixture.entry.path, withDestinationPath: executable.path
    )
    fixture.state.stagedSourcePaths = [appLink.path]
    fixture.state.selectedTargetOverride = executable.path
    fixture.state.installedVersion = "1.0.0"
    fixture.state.artifacts = [fixture.binaryArtifact()]
    try fixture.writeInstalledMetadata(
        receiptArtifacts: [fixture.appArtifact(name: "M13Old.app")]
    )
    return (fixture, executable)
}

@Test func movedOldAppWithCleanBinarySourceReturnsTypedRefusal() async throws {
    let moved = try makeMovedAppCaskFixture("cask-moved-old-app")
    defer { try? FileManager.default.removeItem(at: moved.fixture.root) }
    let runner = HomebrewCaskCommandRunner(fixture: moved.fixture)
    let operationBase = moved.fixture.root.appendingPathComponent(
        "operation-base", isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: operationBase, withIntermediateDirectories: true
    )

    let update = await HomebrewCaskUpdateOperation.prepare(
        definition: try moved.fixture.definition(
            acceptedOperations: [.homebrewCaskUpdate]
        ),
        diagnostic: moved.fixture.diagnostic(),
        environment: moved.fixture.environment,
        currentDirectory: moved.fixture.root.path,
        runner: runner,
        operationRootBaseURL: operationBase
    )
    expectRefusedUpdatePreparation(update, equals: .caskOperationUnsupported)
    let uninstall = await HomebrewCaskUninstallOperation.prepare(
        definition: try moved.fixture.definition(
            acceptedOperations: [.homebrewCaskUninstall]
        ),
        diagnostic: moved.fixture.diagnostic(),
        environment: moved.fixture.environment,
        currentDirectory: moved.fixture.root.path,
        runner: runner,
        operationRootBaseURL: operationBase
    )
    expectRefusedUninstallPreparation(
        uninstall, equals: .caskOperationUnsupported
    )
    #expect(try homebrewScratchIsEmpty(operationBase))
}

@Test func savedStanzaWinsOverUnsupportedReceiptForMovedOldApp() async throws {
    let moved = try makeMovedAppCaskFixture("cask-moved-old-app-stanza")
    defer { try? FileManager.default.removeItem(at: moved.fixture.root) }
    let sentinel = moved.fixture.root.appendingPathComponent("stanza-sentinel.txt")
    try Data("intact\n".utf8).write(to: sentinel)
    // The receipt still declares the unsupported old app; the saved installed definition declares
    // a real uninstall stanza. Elevation must win over the unsupported surface.
    try moved.fixture.writeSavedCaskJSON(["artifacts": [
        moved.fixture.uninstallArtifact(path: sentinel.path),
    ]])
    let runner = HomebrewCaskCommandRunner(fixture: moved.fixture)
    let operationBase = moved.fixture.root.appendingPathComponent(
        "operation-base", isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: operationBase, withIntermediateDirectories: true
    )

    let update = await HomebrewCaskUpdateOperation.prepare(
        definition: try moved.fixture.definition(
            acceptedOperations: [.homebrewCaskUpdate]
        ),
        diagnostic: moved.fixture.diagnostic(),
        environment: moved.fixture.environment,
        currentDirectory: moved.fixture.root.path,
        runner: runner,
        operationRootBaseURL: operationBase
    )
    expectRefusedUpdatePreparation(
        update, equals: .caskUninstallRequiresElevation
    )
    let uninstall = await HomebrewCaskUninstallOperation.prepare(
        definition: try moved.fixture.definition(
            acceptedOperations: [.homebrewCaskUninstall]
        ),
        diagnostic: moved.fixture.diagnostic(),
        environment: moved.fixture.environment,
        currentDirectory: moved.fixture.root.path,
        runner: runner,
        operationRootBaseURL: operationBase
    )
    expectRefusedUninstallPreparation(
        uninstall, equals: .caskUninstallRequiresElevation
    )
    #expect(try homebrewScratchIsEmpty(operationBase))
    #expect(try String(contentsOf: sentinel, encoding: .utf8) == "intact\n")
}

@Test func caskUninstallNormalizesRelativeDanglingLinkResidue() async throws {
    let fixture = try HomebrewCaskFixture("cask-relative-dangling")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let target = fixture.binDirectory.appendingPathComponent("m13cask")
    try FileManager.default.removeItem(at: target)
    // Homebrew's ordinary link text is relative and may contain `..`.
    try FileManager.default.createSymbolicLink(
        atPath: target.path,
        withDestinationPath: "../Caskroom/m13cask/1.0.0/m13cask"
    )
    let definition = try fixture.definition(acceptedOperations: [.homebrewCaskUninstall])
    let before = fixture.diagnostic()
    let updateRunner = HomebrewCaskCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner(
        onLaunch: {
            fixture.state.installedVersion = nil
            try? FileManager.default.removeItem(at: fixture.tokenDirectory)
            try? FileManager.default.removeItem(at: fixture.entry)
        }
    )
    let preparation = try await preparedCaskUninstall(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    #expect(preparation.preview.artifactTargets.allSatisfy { $0.presence == .linked })
    let outcome = await HomebrewCaskUninstallOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (fixture.diagnostic(), fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    #expect(outcome.state == .uncertain)
    let delta = try #require(outcome.reconciliation)
    #expect(delta.managedTargets.map(\.release) == [
        HomebrewCaskManagedTargetRelease.stillPresent,
    ])
    #expect(!delta.managedTargetsReleased)
}

@Test func caskUninstallBindsDeprecationDisclosureToConfirmation() async throws {
    let fixture = try HomebrewCaskFixture(
        "cask-uninstall-deprecation-revalidation", deprecated: true
    )
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    fixture.state.deprecationDate = "2026-02-03"
    fixture.state.deprecationReason = "renamed upstream"
    let definition = try fixture.definition(acceptedOperations: [.homebrewCaskUninstall])
    let before = fixture.diagnostic()
    let updateRunner = HomebrewCaskCommandRunner(fixture: fixture)
    let mutationRunner = HomebrewScriptedMutationRunner()
    let preparation = try await preparedCaskUninstall(
        fixture: fixture, definition: definition, diagnostic: before, runner: updateRunner
    )
    #expect(preparation.preview.deprecated)
    #expect(preparation.preview.deprecationDisclosure?.contains("2026-02-03") == true)
    fixture.state.deprecated = false
    let outcome = await HomebrewCaskUninstallOperation.execute(
        confirmed: preparation,
        environment: fixture.environment,
        scan: { _, _, _ in before },
        reconcileAfterLaunch: { _ in (fixture.diagnostic(), fixture.environment) },
        updateRunner: updateRunner,
        operationRunner: mutationRunner,
        gate: OperationExecutionGate()
    )
    expectRefusedCaskUninstall(outcome, runner: mutationRunner)
}
