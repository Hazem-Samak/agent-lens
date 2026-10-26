// ExecutableIdentity — shared, live filesystem identity for Core's filesystem observations.
//
// Two consumers depend on this seam: explicit ownership verification and per-installation version
// collection. Ownership is never inferred from path text. Every proof compares the current
// canonical target and stat identity of the selected executable, the resolved manager, and the
// proof files. The
// fingerprint deliberately includes device/inode/mode/size and modification/change times, so a
// replacement, retarget or metadata change invalidates an earlier observation. No digest is
// fabricated when stat fails: the observation simply does not exist.

import Darwin
import Foundation

/// The live stat identity of a file. atime is intentionally absent: reading a proof file must not
/// invalidate the proof by itself.
public struct ExecutableFingerprint: Equatable, Sendable {
    public let device: UInt64
    public let inode: UInt64
    public let mode: UInt32
    public let size: Int64
    public let modifiedSeconds: Int64
    public let modifiedNanoseconds: Int64
    public let changedSeconds: Int64
    public let changedNanoseconds: Int64
}

/// A live executable entry (possibly a symlink) and its canonical target.
struct ObservedExecutable: Equatable, Sendable {
    let entryPath: String
    let canonicalTarget: String
    let fingerprint: ExecutableFingerprint
}

/// A live regular file observed through a lexical path (the canonical spelling is retained).
struct FileIdentity: Equatable, Sendable {
    let canonicalPath: String
    let fingerprint: ExecutableFingerprint
}

/// A live directory identity. Timestamps are deliberately omitted: a busy package prefix or
/// Cellar can change while the proof is still valid; replacement is caught by device/inode.
///
/// `physicalPath` is the POSIX `realpath(3)` spelling captured at observation and is used ONLY for
/// descriptor-relative opening. `canonicalPath` keeps its existing consumers: containment checks,
/// presentation (selected entry / canonical target / manager root) and cache keys. The two
/// spellings differ under ordinary temp aliases (`/var/...` vs `/private/var/...`), so they are
/// never mixed: comparing physical components against canonical ones is a bug, not a check.
struct DirectoryIdentity: Equatable, Sendable {
    let canonicalPath: String
    let device: UInt64
    let inode: UInt64
    let mode: UInt32
    /// Internal only: never public, never serialized, never a cache key, never production-logged.
    let physicalPath: String
}

enum FileIdentityObserver {

    static func observeExecutable(entryPath: String) -> ObservedExecutable? {
        guard entryPath.hasPrefix("/"),
              let entryInfo = statInfo(entryPath),
              isRegular(entryInfo.st_mode),
              isExecutable(entryPath)
        else { return nil }

        let canonical = URL(fileURLWithPath: entryPath)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        guard canonical.hasPrefix("/"),
              let targetInfo = statInfo(canonical),
              isRegular(targetInfo.st_mode),
              isExecutable(canonical),
              targetInfo.st_dev == entryInfo.st_dev,
              targetInfo.st_ino == entryInfo.st_ino
        else { return nil }

        return ObservedExecutable(
            entryPath: entryPath,
            canonicalTarget: canonical,
            fingerprint: fingerprint(targetInfo)
        )
    }

    static func observeFile(path: String) -> FileIdentity? {
        guard path.hasPrefix("/") else { return nil }
        let canonical = URL(fileURLWithPath: path)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        guard canonical.hasPrefix("/"),
              let info = statInfo(canonical),
              isRegular(info.st_mode)
        else { return nil }
        return FileIdentity(canonicalPath: canonical, fingerprint: fingerprint(info))
    }

    static func observeDirectory(path: String) -> DirectoryIdentity? {
        guard path.hasPrefix("/") else { return nil }
        let canonical = URL(fileURLWithPath: path)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        guard canonical.hasPrefix("/"),
              let info = statInfo(canonical),
              isDirectory(info.st_mode)
        else { return nil }
        // The descriptor walk needs the PHYSICAL spelling: Foundation rewrites `/private/var`
        // back to `/var`, and the `/var` alias is a symlink that `O_NOFOLLOW` refuses. Resolve
        // with POSIX `realpath(3)` and require it to name the SAME vnode we just observed, so a
        // failure or a divergent resolution yields no observation at all.
        guard let physical = physicalPath(canonical),
              physical.hasPrefix("/"),
              let physicalInfo = statInfo(physical),
              isDirectory(physicalInfo.st_mode),
              physicalInfo.st_dev == info.st_dev,
              physicalInfo.st_ino == info.st_ino
        else { return nil }
        return DirectoryIdentity(
            canonicalPath: canonical,
            device: UInt64(bitPattern: Int64(info.st_dev)),
            inode: info.st_ino,
            mode: UInt32(info.st_mode),
            physicalPath: physical
        )
    }

    /// The POSIX physical pathname of an existing path, or nil. Uses `realpath(3)` directly:
    /// `URL.resolvingSymlinksInPath()` demonstrably returns the un-resolved alias spelling.
    static func physicalPath(_ path: String) -> String? {
        guard let resolved = path.withCString({ realpath($0, nil) }) else { return nil }
        defer { free(resolved) }
        guard let string = String(validatingCString: resolved) else { return nil }
        return string.hasPrefix("/") ? string : nil
    }

    static func fingerprint(_ info: stat) -> ExecutableFingerprint {
        ExecutableFingerprint(
            device: UInt64(bitPattern: Int64(info.st_dev)),
            inode: info.st_ino,
            mode: UInt32(info.st_mode),
            size: Int64(info.st_size),
            modifiedSeconds: Int64(info.st_mtimespec.tv_sec),
            modifiedNanoseconds: Int64(info.st_mtimespec.tv_nsec),
            changedSeconds: Int64(info.st_ctimespec.tv_sec),
            changedNanoseconds: Int64(info.st_ctimespec.tv_nsec)
        )
    }

    /// True when `path` is strictly below `root` by path components. A shared spelling prefix is
    /// not containment.
    static func isStrictDescendant(_ path: String, of root: String) -> Bool {
        isDescendant(path, of: root, exactTrailingComponents: nil)
    }

    /// True when the canonical `path` is exactly `root` followed by `components`, compared by
    /// path components. This is deliberately stronger than following the expected spelling: a
    /// symlinked final component can make a directory identity match while the real path lives
    /// under another prefix.
    static func isExactDescendant(
        _ path: String,
        of root: String,
        components: [String]
    ) -> Bool {
        isDescendant(path, of: root, exactTrailingComponents: components)
    }

    private static func isDescendant(
        _ path: String,
        of root: String,
        exactTrailingComponents: [String]?
    ) -> Bool {
        let pathComponents = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        let rootComponents = URL(fileURLWithPath: root).standardizedFileURL.pathComponents
        guard pathComponents.count > rootComponents.count,
              Array(pathComponents.prefix(rootComponents.count)) == rootComponents
        else { return false }
        guard let exactTrailingComponents else { return true }
        return pathComponents.count == rootComponents.count + exactTrailingComponents.count
            && Array(pathComponents.suffix(exactTrailingComponents.count)) == exactTrailingComponents
    }

    /// Opens an already-observed directory for descriptor-relative work by walking every PHYSICAL
    /// path component from `/` with `O_NOFOLLOW`, then verifies the opened descriptor still matches
    /// `expected`. An ancestor replaced by a symlink therefore fails instead of redirecting the
    /// open. The caller owns the returned descriptor.
    ///
    /// `path` must equal `expected.canonicalPath`: that is a consistency check tying the argument to
    /// the observation it came from, not a lookup key. The walk itself uses only the physical
    /// spelling recorded at observation, because Foundation-standardized components rewrite
    /// `/private/var` to `/var` and the alias is a symlink that `O_NOFOLLOW` refuses.
    static func openVerifiedDirectory(
        path: String,
        expected: DirectoryIdentity
    ) -> Int32? {
        guard path.hasPrefix("/"), path == expected.canonicalPath else { return nil }
        // The recorded binding must be a well-formed ABSOLUTE path before any descriptor work.
        // Two rejected shapes would otherwise reach the SAME valid inode and look acceptable:
        //   * a relative prefix (`"ignored" + validPath`) — the old `dropFirst()` discarded it;
        //   * an embedded NUL — `withCString` truncates at it, so a valid prefix plus a NUL suffix
        //     silently became the valid path.
        let binding = expected.physicalPath
        guard binding.hasPrefix("/"), !binding.utf8.contains(0) else { return nil }
        // Split the recorded physical string directly: no URL standardization, so no alias
        // rewriting. Degenerate components are rejected rather than repaired.
        let pieces = binding
            .split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)
        guard pieces.first?.isEmpty == true else { return nil }
        // A leading empty component is the leading `/` itself; everything else must be a real name.
        let names = pieces.dropFirst()
        guard !names.isEmpty else { return nil }
        for name in names {
            guard !name.isEmpty, name != ".", name != "..", !name.contains("\0") else { return nil }
        }

        var descriptor = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }

        for name in names {
            let next = name.withCString {
                openat(descriptor, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            }
            guard next >= 0 else {
                _ = close(descriptor)
                return nil
            }
            _ = close(descriptor)
            descriptor = next
        }

        var info = stat()
        guard fstat(descriptor, &info) == 0,
              isDirectory(info.st_mode),
              UInt64(bitPattern: Int64(info.st_dev)) == expected.device,
              info.st_ino == expected.inode
        else {
            _ = close(descriptor)
            return nil
        }
        return descriptor
    }

    static func statInfo(_ path: String) -> stat? {
        var info = stat()
        let status = path.withCString { pointer in fstatat(AT_FDCWD, pointer, &info, 0) }
        return status == 0 ? info : nil
    }

    static func isRegular(_ mode: mode_t) -> Bool {
        (mode & mode_t(S_IFMT)) == mode_t(S_IFREG)
    }

    static func isDirectory(_ mode: mode_t) -> Bool {
        (mode & mode_t(S_IFMT)) == mode_t(S_IFDIR)
    }

    static func isExecutable(_ path: String) -> Bool {
        path.withCString { pointer in Darwin.access(pointer, X_OK) } == 0
    }
}

/// Parses manager path output for npm and brew. Exactly one absolute, NUL-free line is accepted;
/// a single terminal LF or CRLF is tolerated. Spaces are significant and are never trimmed.
enum ManagerOutputParser {

    static func singleAbsolutePath(_ data: Data) -> String? {
        guard !data.isEmpty, !data.contains(0x00),
              var text = String(data: data, encoding: .utf8)
        else { return nil }

        if text.hasSuffix("\n") {
            text.removeLast()
            if text.hasSuffix("\r") { text.removeLast() }
        }
        guard !text.isEmpty,
              !text.contains("\n"),
              !text.contains("\r"),
              text.hasPrefix("/")
        else { return nil }
        return text
    }
}
