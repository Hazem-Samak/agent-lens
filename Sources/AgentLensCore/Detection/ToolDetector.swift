// ToolDetector — first real detector (M3 brief).
//
// D-004: detect the installation mechanism, never reimplement the manager.
// D-006: installation state is tri-state — installedAndOnPath / installedNotOnPath / notInstalled.
// D-007: the installed version is always obtained locally; unknown is rendered as a dash.
//
// M2 requirement 7 carries forward: this file consumes ONLY ShellEnvironment —
// pathEntries for search, raw as Process.environment. The binding comment in
// ShellEnvironmentResolver.swift remains true.

import Foundation

/// Tri-state installation state (D-006). Never a boolean.
/// `installedNotOnPath` is the diagnostic this product exists to surface —
/// an error state for other tools, a first-class report here.
public enum InstallState: String, Sendable, Equatable {
    case installedAndOnPath
    case installedNotOnPath
    case notInstalled
}

/// The result of detecting one tool.
public struct DetectedTool: Sendable, Equatable {
    public let displayName: String
    public let executableName: String
    public let state: InstallState
    /// The executable as found (possibly a shim/symlink).
    public let entryPath: String?
    /// Symlinks resolved — the real executable (what classification is based on).
    public let resolvedPath: String?
    /// Installation mechanism: "npm" / "brew" / "standalone". "–" when not installed.
    public let source: String
    /// Installed version, obtained locally. nil = unknown — never an error, never fabricated (D-007).
    public let version: String?
}

/// Detects one tool against a `ShellEnvironment` (M3: one fixture tool).
public struct ToolDetector: Sendable {

    public let displayName: String
    public let executableName: String
    /// Directories to search when the tool is NOT on PATH — makes `installedNotOnPath` reachable (D-006).
    public let extraSearchRoots: [String]
    /// Injectable for unit tests; production default queries the real binary.
    public let versionQuery: @Sendable (String, ShellEnvironment, TimeInterval) -> String?

    public init(
        displayName: String,
        executableName: String,
        extraSearchRoots: [String] = [],
        versionQuery: @escaping @Sendable (String, ShellEnvironment, TimeInterval) -> String? =
            ToolDetector.queryVersion
    ) {
        self.displayName = displayName
        self.executableName = executableName
        self.extraSearchRoots = extraSearchRoots
        self.versionQuery = versionQuery
    }

    /// Version-query timeout, seconds (brief req. 5; mirrors M2 req. 3 style).
    public static let versionTimeout: TimeInterval = 3

    // MARK: Detection

    public func detect(in environment: ShellEnvironment) -> DetectedTool {
        if let entry = findExecutable(roots: environment.pathEntries) {
            return finish(entryPath: entry, state: .installedAndOnPath, environment: environment)
        }
        if let entry = findExecutable(roots: extraSearchRoots.map(Self.expandTilde)) {
            return finish(entryPath: entry, state: .installedNotOnPath, environment: environment)
        }
        return DetectedTool(
            displayName: displayName,
            executableName: executableName,
            state: .notInstalled,
            entryPath: nil,
            resolvedPath: nil,
            source: "–",
            version: nil
        )
    }

    private func finish(
        entryPath: String,
        state: InstallState,
        environment: ShellEnvironment
    ) -> DetectedTool {
        let resolved = URL(fileURLWithPath: entryPath)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        return DetectedTool(
            displayName: displayName,
            executableName: executableName,
            state: state,
            entryPath: entryPath,
            resolvedPath: resolved,
            source: Self.classifySource(resolvedPath: resolved),
            version: versionQuery(entryPath, environment, Self.versionTimeout)
        )
    }

    private func findExecutable(roots: [String]) -> String? {
        let fileManager = FileManager.default
        for root in roots {
            let candidate = root.isEmpty
                ? executableName
                : (root as NSString).appendingPathComponent(executableName)
            let currentDirectory = URL(
                fileURLWithPath: fileManager.currentDirectoryPath,
                isDirectory: true
            )
            let candidateURL = URL(
                fileURLWithPath: candidate,
                relativeTo: currentDirectory
            ).standardizedFileURL
            let resolvedURL = candidateURL.resolvingSymlinksInPath().standardizedFileURL
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: resolvedURL.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue,
                  let attributes = try? fileManager.attributesOfItem(atPath: resolvedURL.path),
                  attributes[.type] as? FileAttributeType == .typeRegular,
                  fileManager.isExecutableFile(atPath: resolvedURL.path)
            else {
                continue
            }
            return candidate
        }
        return nil
    }

    /// PATH entries never contain "~", but configured extra roots may.
    static func expandTilde(_ path: String) -> String {
        guard path.hasPrefix("~") else { return path }
        let suffix = path.dropFirst()
        if suffix.isEmpty || suffix.hasPrefix("/") {
            return NSHomeDirectory() + suffix
        }
        return path
    }

    // MARK: Source classification (brief req. 3)

    /// Classify by the RESOLVED target — not the shim's directory. A Homebrew shim
    /// into `lib/node_modules` is npm-managed (mechanism wins, D-004); report order
    /// reflects that: npm first, then brew, then standalone.
    public static func classifySource(resolvedPath: String) -> String {
        if resolvedPath.contains("/lib/node_modules/") { return "npm" }
        if resolvedPath.contains("/Cellar/") { return "brew" }
        return "standalone"
    }

    // MARK: Local version query (brief req. 5, D-007)

    /// Runs `<executable> --version` locally with a timeout, returning the first
    /// version token found (leading "v" stripped). nil on failure or timeout.
    /// The environment comes from ShellEnvironment.raw — never the inherited env.
    public static func queryVersion(
        executablePath: String,
        environment: ShellEnvironment,
        timeout: TimeInterval
    ) -> String? {
        guard let result = BoundedProcessRunner.run(
            executablePath: executablePath,
            arguments: ["--version"],
            environment: environment.raw,
            timeout: timeout
        ),
        !result.timedOut,
        !result.outputLimitExceeded,
        result.exitStatus == 0
        else {
            return nil
        }
        guard let output = String(data: result.standardOutput, encoding: .utf8) else { return nil }
        let firstLine = output.split(separator: "\n", omittingEmptySubsequences: true).first
        return Self.extractVersionToken(from: firstLine.map(String.init) ?? "")
    }

    /// First `\d.\d...` token in the line, including prerelease suffixes:
    /// `codex-cli 0.162.1` → `0.162.1`, `v1.2.3` → `1.2.3`, `1.0.0-beta.2 (build 7)` → `1.0.0-beta.2`.
    public static func extractVersionToken(from line: String) -> String? {
        guard let match = line.range(of: #"[0-9]+(\.[0-9]+){1,3}(-[0-9A-Za-z.]+)?"#, options: .regularExpression) else {
            return nil
        }
        return String(line[match])
    }

}
