// HomebrewIdentity — M6 manager resolution and selected-keg ownership (brief §"Homebrew batch contract").
//
// Resolution uses the ordered `ShellEnvironment.pathEntries` and the M2/M5 live-file
// semantics; it never falls back to inherited PATH, `which`, `/usr/bin/env brew`, or a
// hardcoded Homebrew prefix. Ownership is decided by PATH COMPONENTS, not substrings.

import Darwin
import Foundation

/// A verified `brew` executable: the absolute PATH entry and its canonical target.
public struct HomebrewManager: Equatable, Sendable {
    public let entryPath: String
    public let canonicalTarget: String

    public init(entryPath: String, canonicalTarget: String) {
        self.entryPath = entryPath
        self.canonicalTarget = canonicalTarget
    }
}

public enum HomebrewManagerResolver {

    /// The first live `brew` in the ordered login-shell PATH. Relative roots resolve against
    /// `currentDirectory`, exactly as discovery does. Broken links and directories are skipped.
    public static func resolve(environment: ShellEnvironment, currentDirectory: String) -> HomebrewManager? {
        let workingDirectory = URL(fileURLWithPath: currentDirectory, isDirectory: true).standardizedFileURL
        for directoryText in environment.pathEntries {
            let directory = directoryText.isEmpty
                ? workingDirectory
                : URL(fileURLWithPath: directoryText, isDirectory: true, relativeTo: workingDirectory)
                    .standardizedFileURL
            let entry = directory.appendingPathComponent("brew").standardizedFileURL.path
            guard isLiveExecutable(entry) else { continue }
            let target = URL(fileURLWithPath: entry).resolvingSymlinksInPath().standardizedFileURL.path
            return HomebrewManager(entryPath: entry, canonicalTarget: target)
        }
        return nil
    }

    /// Same live-file rule as `PathDiagnosticsScanner`: a regular file (after symlink
    /// resolution) that the process may execute.
    private static func isLiveExecutable(_ path: String) -> Bool {
        // fstatat follows symlinks (flag 0), so this classifies the resolved target.
        var info = Darwin.stat()
        let statStatus = path.withCString { pointer in fstatat(AT_FDCWD, pointer, &info, 0) }
        guard statStatus == 0 else { return false }
        guard (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else { return false }
        return path.withCString { access($0, X_OK) } == 0
    }
}

/// The selected executable decomposed as `<cellar>/<formula>/<keg-version>/<relative path>`.
public struct SelectedKeg: Equatable, Sendable {
    public let cellar: String
    public let formula: String
    public let kegVersion: String
    public let relativeExecutable: String
    public let selectedTarget: String

    public init(cellar: String, formula: String, kegVersion: String, relativeExecutable: String, selectedTarget: String) {
        self.cellar = cellar
        self.formula = formula
        self.kegVersion = kegVersion
        self.relativeExecutable = relativeExecutable
        self.selectedTarget = selectedTarget
    }
}

public enum HomebrewIdentityFailure: Error, Equatable, Sendable {
    /// The selected executable is not inside the resolved manager's Cellar.
    case managerMismatch
    /// The path lacks the formula/keg/executable structure needed to verify ownership.
    case unverified
}

public enum HomebrewTargetParser {

    /// Parses by path components. A `/Cellar/` substring anywhere else is not ownership.
    public static func parse(selectedTarget: String, cellar: String) -> Result<SelectedKeg, HomebrewIdentityFailure> {
        let target = URL(fileURLWithPath: selectedTarget).standardizedFileURL.path
        let normalizedCellar = URL(fileURLWithPath: cellar, isDirectory: true).standardizedFileURL.path
        let cellarPrefix = normalizedCellar.hasSuffix("/") ? normalizedCellar : normalizedCellar + "/"
        guard target.hasPrefix(cellarPrefix) else { return .failure(.managerMismatch) }

        let remainder = target.dropFirst(cellarPrefix.count)
        let components = remainder.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        // formula, keg, and at least one executable path component are required.
        guard components.count >= 3,
              components.allSatisfy({ !$0.isEmpty }),
              components[0] != ".", components[0] != "..",
              components[1] != ".", components[1] != ".."
        else {
            return .failure(.unverified)
        }
        return .success(SelectedKeg(
            cellar: normalizedCellar,
            formula: components[0],
            kegVersion: components[1],
            relativeExecutable: components.dropFirst(2).joined(separator: "/"),
            selectedTarget: target
        ))
    }
}
