import Darwin
import Foundation
import Testing
@testable import AgentLensCore

// M10-A amendment — focused identity tests for the recorded-physical-directory binding.
//
// These exercise ExecutableIdentity directly with owned fixtures. Device/inode checks and the
// no-follow descriptor walk stay load-bearing: every "refused" case below fails because identity
// or component safety does not hold, not because a path string merely differs.

private func ownedDirectory(_ label: String) throws -> URL {
    let base = [ProcessInfo.processInfo.environment["AGENT_LENS_TEST_SCRATCH"],
                ProcessInfo.processInfo.environment["TMPDIR"]]
        .compactMap { $0 }
        .first { !$0.isEmpty }
    guard let base else {
        throw NSError(domain: "AgentLensIdentityTests", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "no authorized test scratch root available",
        ])
    }
    let root = URL(fileURLWithPath: base, isDirectory: true)
        .appendingPathComponent("agentlens-identity-\(label)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func physical(_ path: String) -> String? {
    FileIdentityObserver.physicalPath(path)
}

@Test func observedDirectoryRecordsAPhysicalBindingForItsOwnIdentity() throws {
    let directory = try ownedDirectory("observe")
    defer { try? FileManager.default.removeItem(at: directory) }

    let identity = try #require(FileIdentityObserver.observeDirectory(path: directory.path))

    // Both spellings resolve, and the recorded physical path names the SAME vnode.
    let recorded = try #require(physical(identity.physicalPath))
    #expect(recorded == identity.physicalPath, "the recorded physical path must already be physical")

    let canonicalInfo = try #require(FileIdentityObserver.statInfo(identity.canonicalPath))
    let physicalInfo = try #require(FileIdentityObserver.statInfo(identity.physicalPath))
    #expect(UInt64(bitPattern: Int64(canonicalInfo.st_dev)) == identity.device)
    #expect(canonicalInfo.st_ino == identity.inode)
    #expect(physicalInfo.st_dev == canonicalInfo.st_dev)
    #expect(physicalInfo.st_ino == canonicalInfo.st_ino)
}

@Test func logicalAndPhysicalAliasesOpenUnderInheritedTemporaryDirectory() throws {
    // The measured defect: Foundation-standardized components rewrote /private/var back to /var,
    // and the /var alias is a symlink that O_NOFOLLOW refuses. Both spellings must now open.
    let directory = try ownedDirectory("aliases")
    defer { try? FileManager.default.removeItem(at: directory) }

    let physicalSpelling = try #require(physical(directory.path))
    let spellings = Set([directory.path, physicalSpelling])

    for spelling in spellings {
        let identity = try #require(
            FileIdentityObserver.observeDirectory(path: spelling),
            "observation must succeed for \(spelling)"
        )
        let descriptor = try #require(
            FileIdentityObserver.openVerifiedDirectory(path: identity.canonicalPath, expected: identity),
            "anchored open must succeed for \(spelling)"
        )
        #expect(close(descriptor) == 0)
    }

    // Aliases of one directory yield identical identity facts and the same physical binding, so
    // observations compare equal.
    let fromLogical = try #require(FileIdentityObserver.observeDirectory(path: directory.path))
    let fromPhysical = try #require(FileIdentityObserver.observeDirectory(path: physicalSpelling))
    #expect(fromLogical == fromPhysical, "aliases of one vnode must produce equal identities")
}

@Test func openerRequiresTheCanonicalArgumentFromTheSameObservation() throws {
    let directory = try ownedDirectory("consistency")
    defer { try? FileManager.default.removeItem(at: directory) }
    let identity = try #require(FileIdentityObserver.observeDirectory(path: directory.path))

    // A noncanonical argument is not accepted, even when it names the same vnode.
    let physicalSpelling = try #require(physical(directory.path))
    if physicalSpelling != identity.canonicalPath {
        #expect(FileIdentityObserver.openVerifiedDirectory(path: physicalSpelling, expected: identity) == nil)
    }
    #expect(FileIdentityObserver.openVerifiedDirectory(path: "/", expected: identity) == nil)
    #expect(FileIdentityObserver.openVerifiedDirectory(path: "relative/path", expected: identity) == nil)
}

@Test func missingAndUnresolvableDirectoriesHaveNoObservation() throws {
    let absent = "/agentlens-absent-\(UUID().uuidString)"
    #expect(FileIdentityObserver.observeDirectory(path: absent) == nil)
    #expect(FileIdentityObserver.physicalPath(absent) == nil)

    // A symlink loop is a real resolution failure, not a missing leaf.
    let parent = try ownedDirectory("loop")
    defer { try? FileManager.default.removeItem(at: parent) }
    let loop = parent.appendingPathComponent("self")
    try FileManager.default.createSymbolicLink(atPath: loop.path, withDestinationPath: loop.path)
    #expect(FileIdentityObserver.physicalPath(loop.path) == nil)
    #expect(FileIdentityObserver.observeDirectory(path: loop.path) == nil)

    // A regular file is not a directory observation.
    let file = parent.appendingPathComponent("plain.txt")
    try Data("x".utf8).write(to: file)
    #expect(FileIdentityObserver.observeDirectory(path: file.path) == nil)
}

@Test func degeneratePhysicalComponentsAreRejected() throws {
    let directory = try ownedDirectory("degenerate")
    defer { try? FileManager.default.removeItem(at: directory) }
    let identity = try #require(FileIdentityObserver.observeDirectory(path: directory.path))
    let valid = identity.physicalPath

    // Every bad binding below is built from the VALID physical path of the SAME directory, so a
    // refusal cannot happen merely through a later inode mismatch: if the malformed shape were
    // accepted, the walk would land on the correct inode and succeed.
    let badBindings: [(String, String)] = [
        ("empty", ""),
        ("root-only", "/"),
        ("relative", "relative"),
        ("relative-prefix", "ignored" + valid),
        ("relative-prefix-slash", "ignored/" + valid),
        ("nul-suffix", valid + "\0ignored"),
        // A real NUL with a trailing suffix: `withCString` would truncate at the NUL and walk the
        // VALID prefix, landing on the same inode. This must be refused by binding validation.
        ("nul-embedded", valid + "\0/ignored"),
        ("dot-component", valid + "/./ignored"),
        ("dotdot-component", valid + "/../"),
        ("trailing-slash", valid + "/"),
        ("double-slash", valid.replacingOccurrences(of: "/", with: "//")),
    ]

    for (label, bad) in badBindings where !bad.isEmpty || label == "empty" {
        let forged = DirectoryIdentity(
            canonicalPath: identity.canonicalPath,
            device: identity.device,
            inode: identity.inode,
            mode: identity.mode,
            physicalPath: bad
        )
        #expect(FileIdentityObserver.openVerifiedDirectory(path: identity.canonicalPath, expected: forged) == nil,
                "malformed binding must be refused before descriptor work: \(label)")
    }

    // Control: the genuine binding still opens, so the refusals above are about the binding shape.
    let descriptor = try #require(
        FileIdentityObserver.openVerifiedDirectory(path: identity.canonicalPath, expected: identity)
    )
    #expect(close(descriptor) == 0)
}

@Test func observedDirectoryReplacedIsRefused() throws {
    let root = try ownedDirectory("replacement")
    defer { try? FileManager.default.removeItem(at: root) }
    let target = root.appendingPathComponent("child", isDirectory: true)
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)

    let identity = try #require(FileIdentityObserver.observeDirectory(path: target.path))
    let initial = try #require(FileIdentityObserver.openVerifiedDirectory(path: identity.canonicalPath, expected: identity))
    #expect(close(initial) == 0)

    // Replace with a NEW directory (distinct inode): an identity guard, independent of the walk.
    try FileManager.default.removeItem(at: target)
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)

    #expect(FileIdentityObserver.openVerifiedDirectory(path: identity.canonicalPath, expected: identity) == nil,
            "a replaced directory must not inherit the original proof")
}

@Test func ancestorSymlinkToTheSameInodeIsRefused() throws {
    // Load-bearing no-follow test: the symlink points at the SAME original inode, so the final
    // device/inode check would PASS. Only refusing to follow the link can make this fail.
    let root = try ownedDirectory("ancestor-same-inode")
    defer { try? FileManager.default.removeItem(at: root) }

    let realParent = root.appendingPathComponent("real", isDirectory: true)
    let leaf = realParent.appendingPathComponent("leaf", isDirectory: true)
    try FileManager.default.createDirectory(at: leaf, withIntermediateDirectories: true)

    let identity = try #require(FileIdentityObserver.observeDirectory(path: leaf.path))
    let control = try #require(
        FileIdentityObserver.openVerifiedDirectory(path: identity.canonicalPath, expected: identity),
        "the genuine path must open before the ancestor is swapped"
    )
    #expect(close(control) == 0)

    // MOVE the observed subtree to a sibling, then put a symlink at the ORIGINAL component name
    // pointing back at the moved directory: same inode, different route.
    let movedParent = root.appendingPathComponent("moved", isDirectory: true)
    try FileManager.default.moveItem(at: realParent, to: movedParent)
    try FileManager.default.createSymbolicLink(atPath: realParent.path, withDestinationPath: movedParent.path)

    // Sanity: following the link WOULD reach the recorded inode.
    let movedLeaf = movedParent.appendingPathComponent("leaf", isDirectory: true)
    let movedIdentity = try #require(FileIdentityObserver.observeDirectory(path: movedLeaf.path))
    #expect(movedIdentity.device == identity.device && movedIdentity.inode == identity.inode,
            "the symlink target must be the same inode for this test to be load-bearing")

    #expect(FileIdentityObserver.openVerifiedDirectory(path: identity.canonicalPath, expected: identity) == nil,
            "an ancestor symlink must be refused even when it resolves to the same inode")
}

@Test func finalComponentSymlinkToTheSameInodeIsRefused() throws {
    // Same construction at the final component: following the link would land on the recorded
    // inode, so only O_NOFOLLOW produces the refusal.
    let root = try ownedDirectory("final-same-inode")
    defer { try? FileManager.default.removeItem(at: root) }

    let leaf = root.appendingPathComponent("leaf", isDirectory: true)
    try FileManager.default.createDirectory(at: leaf, withIntermediateDirectories: false)

    let identity = try #require(FileIdentityObserver.observeDirectory(path: leaf.path))
    let control = try #require(
        FileIdentityObserver.openVerifiedDirectory(path: identity.canonicalPath, expected: identity)
    )
    #expect(close(control) == 0)

    let moved = root.appendingPathComponent("moved-leaf", isDirectory: true)
    try FileManager.default.moveItem(at: leaf, to: moved)
    try FileManager.default.createSymbolicLink(atPath: leaf.path, withDestinationPath: moved.path)

    let movedIdentity = try #require(FileIdentityObserver.observeDirectory(path: moved.path))
    #expect(movedIdentity.device == identity.device && movedIdentity.inode == identity.inode)

    #expect(FileIdentityObserver.openVerifiedDirectory(path: identity.canonicalPath, expected: identity) == nil,
            "a final-component symlink must be refused even when it resolves to the same inode")
}

@Test func physicalEqualityIsNotASubstituteForIdentityFacts() throws {
    let root = try ownedDirectory("identity-not-path")
    defer { try? FileManager.default.removeItem(at: root) }
    let first = root.appendingPathComponent("first", isDirectory: true)
    let second = root.appendingPathComponent("second", isDirectory: true)
    try FileManager.default.createDirectory(at: first, withIntermediateDirectories: false)
    try FileManager.default.createDirectory(at: second, withIntermediateDirectories: false)

    let firstIdentity = try #require(FileIdentityObserver.observeDirectory(path: first.path))
    let secondIdentity = try #require(FileIdentityObserver.observeDirectory(path: second.path))

    #expect(firstIdentity != secondIdentity, "distinct vnodes must not compare equal")

    // Graft the second directory's physical binding onto the first identity's device/inode.
    let grafted = DirectoryIdentity(
        canonicalPath: firstIdentity.canonicalPath,
        device: firstIdentity.device,
        inode: firstIdentity.inode,
        mode: firstIdentity.mode,
        physicalPath: secondIdentity.physicalPath
    )
    #expect(grafted != firstIdentity, "a changed physical binding must change equality")
    #expect(FileIdentityObserver.openVerifiedDirectory(path: grafted.canonicalPath, expected: grafted) == nil,
            "a grafted binding must not open")
}