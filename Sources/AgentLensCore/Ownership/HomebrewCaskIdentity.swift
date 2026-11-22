// HomebrewCaskIdentity — M13-A component decomposition for a cask-staged executable.
//
// The Caskroom has the same *shape* as the Cellar with a different vocabulary:
// `<caskroom>/<token>/<version-dir>/<relative artifact…>`. The token is a cask name (never a
// formula name), the version directory is OPAQUE (it may be `latest` or a comma-multi-part
// string and is never parsed as a version), and the staged artifact may be a directory (an app)
// or live below `.homebrew-command-wrappers`. Ownership is decided by PATH COMPONENTS, never by a
// substring and never by a declaration alone.

import Foundation

/// The selected executable decomposed as a staged cask artifact:
/// `<caskroom>/<token>/<version-dir>/<relative artifact>`.
public struct SelectedCask: Equatable, Sendable {
    public let caskroom: String
    public let token: String
    public let versionDirectory: String
    public let relativeArtifact: String
    public let selectedTarget: String

    public init(
        caskroom: String,
        token: String,
        versionDirectory: String,
        relativeArtifact: String,
        selectedTarget: String
    ) {
        self.caskroom = caskroom
        self.token = token
        self.versionDirectory = versionDirectory
        self.relativeArtifact = relativeArtifact
        self.selectedTarget = selectedTarget
    }
}

public enum HomebrewCaskIdentityFailure: Error, Equatable, Sendable {
    /// The selected executable is not inside the manager-reported Caskroom.
    case managerMismatch
    /// The path is inside the Caskroom but lacks the token/version/artifact structure.
    case unverified
}

public enum HomebrewCaskTargetParser {

    /// Parses by path components. A `/Caskroom/` substring anywhere else is not ownership, and a
    /// sibling root such as `<caskroom>2` never matches.
    public static func parse(
        selectedTarget: String,
        caskroom: String
    ) -> Result<SelectedCask, HomebrewCaskIdentityFailure> {
        guard let target = cleanedAbsolutePath(selectedTarget),
              let root = cleanedAbsolutePath(caskroom)
        else { return .failure(.unverified) }

        let targetComponents = components(of: target)
        let rootComponents = components(of: root)
        guard targetComponents.count > rootComponents.count,
              Array(targetComponents.prefix(rootComponents.count)) == rootComponents
        else { return .failure(.managerMismatch) }

        let below = Array(targetComponents.dropFirst(rootComponents.count))
        // token + opaque version directory + at least one relative artifact component. `.metadata`
        // is manager bookkeeping at every depth below the Caskroom; it is never a staged proof
        // path, and a lexical `.metadata` component is never canonicalized away.
        guard below.count >= 3, !below.contains(".metadata") else {
            return .failure(.unverified)
        }
        return .success(SelectedCask(
            caskroom: root,
            token: below[0],
            versionDirectory: below[1],
            relativeArtifact: below.dropFirst(2).joined(separator: "/"),
            selectedTarget: target
        ))
    }

    /// A clean absolute path with no empty interior component or `.`/`..` traversal. Paths under
    /// an ordinary temp alias keep their Foundation spelling; no symlink is resolved here.
    static func cleanedAbsolutePath(_ path: String) -> String? {
        guard path.hasPrefix("/"), !path.utf8.contains(0) else { return nil }
        if path == "/" { return "/" }
        let pieces = path
            .split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)
        guard pieces.first?.isEmpty == true else { return nil }
        let names = pieces.dropFirst()
        guard !names.isEmpty else { return nil }
        for name in names {
            guard !name.isEmpty, name != ".", name != ".." else { return nil }
        }
        return "/" + names.joined(separator: "/")
    }

    static func components(of cleanedPath: String) -> [String] {
        cleanedPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }
}
