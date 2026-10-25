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

/// The location-only result of detection. The diagnostic scanner uses this internal seam so a
/// scan observes each canonical installation once instead of executing the public `detect` query
/// and then collecting versions again.
struct ToolLocation: Sendable, Equatable {
    let state: InstallState
    let entryPath: String?
    let resolvedPath: String?
    let source: String
}

/// Detects one tool against a `ShellEnvironment` (M3: one fixture tool).
public struct ToolDetector: Sendable {

    public let displayName: String
    public let executableName: String
    /// Directories to search when the tool is NOT on PATH — makes `installedNotOnPath` reachable (D-006).
    public let extraSearchRoots: [String]
    /// The registry-declared bounded version query. Required: there is no hidden
    /// hardcoded-query production convention. Existing consumers pass
    /// `VersionQuerySpecification.standard` explicitly.
    public let versionQuerySpecification: VersionQuerySpecification
    /// Injectable for unit tests; the production default executes the declared
    /// specification through the bounded runner.
    public let versionQuery: @Sendable (
        String, ShellEnvironment, TimeInterval, VersionQuerySpecification
    ) -> String?

    public init(
        displayName: String,
        executableName: String,
        extraSearchRoots: [String] = [],
        versionQuerySpecification: VersionQuerySpecification,
        versionQuery: @escaping @Sendable (
            String, ShellEnvironment, TimeInterval, VersionQuerySpecification
        ) -> String? = ToolDetector.queryVersion
    ) {
        self.displayName = displayName
        self.executableName = executableName
        self.extraSearchRoots = extraSearchRoots
        self.versionQuerySpecification = versionQuerySpecification
        self.versionQuery = versionQuery
    }

    /// Version-query timeout, seconds (brief req. 5; mirrors M2 req. 3 style).
    public static let versionTimeout: TimeInterval = 3

    // MARK: Detection

    public func detect(in environment: ShellEnvironment) -> DetectedTool {
        let location = locate(in: environment)
        let version: String?
        if let entryPath = location.entryPath {
            version = versionQuery(
                entryPath,
                environment,
                Self.versionTimeout,
                versionQuerySpecification
            )
        } else {
            version = nil
        }
        return detectedTool(from: location, version: version)
    }

    /// Locates the selected executable without running its version query. Internal so
    /// `PathDiagnosticsScanner` can collect one observation per canonical installation.
    func locate(in environment: ShellEnvironment) -> ToolLocation {
        if let entry = findExecutable(roots: environment.pathEntries) {
            return location(entryPath: entry, state: .installedAndOnPath)
        }
        if let entry = findExecutable(roots: extraSearchRoots.map(Self.expandTilde)) {
            return location(entryPath: entry, state: .installedNotOnPath)
        }
        return ToolLocation(
            state: .notInstalled,
            entryPath: nil,
            resolvedPath: nil,
            source: "–"
        )
    }

    func detectedTool(from location: ToolLocation, version: String?) -> DetectedTool {
        DetectedTool(
            displayName: displayName,
            executableName: executableName,
            state: location.state,
            entryPath: location.entryPath,
            resolvedPath: location.resolvedPath,
            source: location.source,
            version: version
        )
    }

    private func location(entryPath: String, state: InstallState) -> ToolLocation {
        let resolved = URL(fileURLWithPath: entryPath)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        return ToolLocation(
            state: state,
            entryPath: entryPath,
            resolvedPath: resolved,
            source: Self.classifySource(resolvedPath: resolved)
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

    /// Runs the declared executable/arguments locally with the fixed 3-second
    /// deadline and existing output limits, then extracts a version token from
    /// the selected stream and line. nil on failure, timeout, output limit,
    /// invalid UTF-8, or no version token — never a fabricated version.
    /// The environment comes from ShellEnvironment.raw — never the inherited env.
    public static func queryVersion(
        executablePath: String,
        environment: ShellEnvironment,
        timeout: TimeInterval,
        specification: VersionQuerySpecification
    ) -> String? {
        guard let result = BoundedProcessRunner.run(
            executablePath: executablePath,
            arguments: specification.arguments,
            environment: environment.raw,
            timeout: timeout,
            captureStream: specification.stream.captureStream
        ),
        !result.timedOut,
        !result.outputLimitExceeded,
        result.exitStatus == 0
        else {
            return nil
        }
        guard let output = String(data: result.standardOutput, encoding: .utf8) else { return nil }
        guard let line = selectedLine(from: output, selection: specification.line) else {
            return nil
        }
        return Self.extractVersionToken(from: String(line))
    }

    private static func selectedLine(
        from output: String,
        selection: VersionQuerySpecification.LineSelection
    ) -> Substring? {
        guard !output.isEmpty else { return nil }
        switch selection {
        case .first:
            return output[..<(output.firstIndex(of: "\n") ?? output.endIndex)]
        case .firstNonempty:
            var start = output.startIndex
            while start < output.endIndex {
                let end = output[start...].firstIndex(of: "\n") ?? output.endIndex
                let line = output[start..<end]
                let isBlank = !line.unicodeScalars.contains {
                    !CharacterSet.whitespacesAndNewlines.contains($0)
                }
                if !isBlank {
                    return line
                }
                guard end < output.endIndex else { return nil }
                start = output.index(after: end)
            }
            return nil
        }
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

private extension VersionQuerySpecification.Stream {
    var captureStream: BoundedProcessRunner.CaptureStream {
        switch self {
        case .stdout: .standardOutput
        case .stderr: .standardError
        }
    }
}
