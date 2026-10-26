import Darwin
import Foundation
import Testing

// M10-A — focused behavioral regressions for the test-only fixture/isolation seams in
// CLIFixtureIsolation.swift. These exercise the control seam directly; they never replace
// `/usr/bin/sandbox-exec` at the real CLI launch seams and never touch the real cache.
//
// Coverage:
// * empty/missing base fails closed (pure input, no process-environment mutation);
// * a real resolution FAILURE (symlink loop) returns nil instead of inventing a path;
// * an owned symlink alias resolves to the same physical vnode, and denial is enforced for each
//   supplied spelling;
// * a pre-existing directory with the expected name prefix cannot be handed to cleanup;
// * cleanup re-validates identity, so a replaced directory is refused;
// * a simulated non-enforcing sandbox is rejected, and a launch failure is not a denial.

/// The authorized default base, taken from the INHERITED environment keys the production seam
/// itself reads. `NSTemporaryDirectory()` is deliberately not used as a fallback: measured, it
/// reports the per-user Darwin temp tree regardless of `TMPDIR`, so a test could pass against a
/// root the seam would never have chosen.
private func inheritedAuthorizedBase() throws -> String {
    let environment = ProcessInfo.processInfo.environment
    if let scratch = environment["AGENT_LENS_TEST_SCRATCH"], !scratch.isEmpty {
        return scratch
    }
    if let tmpdir = environment["TMPDIR"], !tmpdir.isEmpty {
        return tmpdir
    }
    throw inheritedAuthorizedBaseError()
}

/// Builds the seam environment from the INHERITED keys without rewriting one as the other: an
/// explicit `AGENT_LENS_TEST_SCRATCH` stays a scratch override, and `TMPDIR` stays the inherited
/// temporary directory. Both are passed through exactly as the production seam reads them.
private func seamEnvironment(_ scratch: String?) throws -> [String: String] {
    var environment: [String: String] = [:]
    let inherited = ProcessInfo.processInfo.environment
    if let tmpdir = inherited["TMPDIR"], !tmpdir.isEmpty {
        environment["TMPDIR"] = tmpdir
    }
    if let scratch, !scratch.isEmpty {
        environment["AGENT_LENS_TEST_SCRATCH"] = scratch
    }
    guard !environment.isEmpty else { throw inheritedAuthorizedBaseError() }
    return environment
}

private func inheritedAuthorizedBaseError() -> NSError {
    NSError(domain: "AgentLensIdentityTests", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "no authorized test scratch root in the inherited environment",
    ])
}

@Test func ownedFixtureRootRequiresAnAuthorizedBase() throws {
    #expect(throws: (any Error).self) {
        _ = try makeOwnedFixtureRoot(label: "empty-root", environment: ["AGENT_LENS_TEST_SCRATCH": ""])
    }

    let missingBase = FileManager.default.temporaryDirectory
        .appendingPathComponent("agentlens-missing-base-\(UUID().uuidString)", isDirectory: true)
    #expect(throws: (any Error).self) {
        _ = try makeOwnedFixtureRoot(
            label: "absent-base",
            environment: ["AGENT_LENS_TEST_SCRATCH": missingBase.path]
        )
    }

    // A real (non-ENOENT) resolution failure of the base must fail closed too.
    let loopParent = FileManager.default.temporaryDirectory
        .appendingPathComponent("agentlens-loop-parent-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: loopParent, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: loopParent) }
    let loop = loopParent.appendingPathComponent("self-loop")
    try FileManager.default.createSymbolicLink(atPath: loop.path, withDestinationPath: loop.path)
    #expect(physicalPath(loop.path) == nil, "ELOOP must not be reported as a resolved path")
    #expect(throws: (any Error).self) {
        _ = try makeOwnedFixtureRoot(label: "loop-base", environment: ["AGENT_LENS_TEST_SCRATCH": loop.path])
    }
}

@Test func ownedFixtureRootIsPhysicalAndExclusivelyOwned() throws {
    let root = try makeOwnedFixtureRoot(label: "physical", environment: try seamEnvironment(nil))

    let fileManager = FileManager.default
    var isDirectory: ObjCBool = false
    #expect(fileManager.fileExists(atPath: root.physicalPath, isDirectory: &isDirectory))
    #expect(isDirectory.boolValue)
    #expect(root.physicalPath == physicalPath(root.physicalPath), "a handed-out root must already be physical")

    try removeOwnedFixtureRoot(root, fileManager: fileManager)
    #expect(!fileManager.fileExists(atPath: root.physicalPath))

    // A removed handle cannot be replayed.
    #expect(throws: (any Error).self) { try removeOwnedFixtureRoot(root, fileManager: fileManager) }
}

@Test func ownedSymlinkAliasResolvesToTheSamePhysicalVNode() throws {
    let physical = try makeOwnedFixtureRoot(label: "alias-target", environment: try seamEnvironment(nil))
    defer { try? removeOwnedFixtureRoot(physical) }
    let target = URL(fileURLWithPath: physical.physicalPath, isDirectory: true)

    let aliasParent = try makeOwnedFixtureRoot(label: "alias-parent", environment: try seamEnvironment(nil))
    defer { try? removeOwnedFixtureRoot(aliasParent) }
    let alias = URL(fileURLWithPath: aliasParent.physicalPath, isDirectory: true)
        .appendingPathComponent("alias-to-target")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: target)

    #expect(physicalPath(alias.path) == physical.physicalPath, "alias spelling must resolve physically")
    #expect(physicalPath(target.path) == physical.physicalPath, "physical spelling must be stable")

    let resolved = try makeOwnedFixtureRoot(
        label: "via-alias",
        environment: ["AGENT_LENS_TEST_SCRATCH": alias.path]
    )
    defer { try? removeOwnedFixtureRoot(resolved) }
    #expect(resolved.physicalPath.hasPrefix(physical.physicalPath + "/"),
            "a child created through an alias must land under the resolved physical vnode")
}

@Test func denialIsEnforcedForEachSuppliedPhysicalSpelling() throws {
    // Controlled owned symlink: alias spelling versus resolved physical spelling must both be
    // denyable, so no host-specific TMPDIR shape is assumed.
    let target = try makeOwnedFixtureRoot(label: "spellings", environment: try seamEnvironment(nil))
    defer { try? removeOwnedFixtureRoot(target) }
    let parent = try makeOwnedFixtureRoot(label: "spellings-parent", environment: try seamEnvironment(nil))
    defer { try? removeOwnedFixtureRoot(parent) }

    let alias = URL(fileURLWithPath: parent.physicalPath, isDirectory: true)
        .appendingPathComponent("alias")
    try FileManager.default.createSymbolicLink(
        at: alias, withDestinationURL: URL(fileURLWithPath: target.physicalPath, isDirectory: true)
    )

    let spellings = [target.physicalPath, physicalPath(alias.path)].compactMap { $0 }
    #expect(Set(spellings).count == 1, "both spellings must name the same physical vnode")

    for spelling in spellings {
        let root = URL(fileURLWithPath: target.physicalPath, isDirectory: true)
        // Marker/receipt must sit OUTSIDE the denied subpath, or the allowed marker write is
        // itself denied and a launch failure would look indistinguishable from a denial.
        let outside = URL(fileURLWithPath: parent.physicalPath, isDirectory: true)
            .appendingPathComponent("capture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: outside) }
        let observation = try observeSandboxMechanism(
            root: root,
            profile: denialProfileFor(spelling),
            captureDirectory: outside,
            label: "spelling"
        )
        #expect(observation.executedMarker == "executed")
        #expect(observation.provesDenial, "denial must hold for the physical spelling \(spelling)")
    }
}

@Test func preexistingDirectoryCannotBeHandedToCleanup() throws {
    // A directory that merely LOOKS like a fixture root: correct name prefix, correct owner, inside
    // the authorized base. It was not created by the factory, so it must never be removed.
    let base = try makeOwnedFixtureRoot(label: "forgery-base", environment: try seamEnvironment(nil))
    defer { try? removeOwnedFixtureRoot(base) }
    let baseURL = URL(fileURLWithPath: base.physicalPath, isDirectory: true)
    let impostor = baseURL.appendingPathComponent("agentlens-m6-cli-forged-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: impostor, withIntermediateDirectories: false)
    try Data("keep me".utf8).write(to: impostor.appendingPathComponent("sentinel"))

    // There is no way to express "clean up this directory" for it: `ResolvedFixtureRoot` has a
    // private initializer and cleanup additionally requires an outstanding creation token, so a
    // hand-built or prefix-matching value cannot reach `removeOwnedFixtureRoot`. The assertions
    // below are the observable consequence — the impostor survives every cleanup this test runs.
    let realRoot = try makeOwnedFixtureRoot(label: "real-sibling", environment: try seamEnvironment(nil))
    try removeOwnedFixtureRoot(realRoot)

    #expect(FileManager.default.fileExists(atPath: impostor.path), "an uncreated directory must survive cleanup")
    #expect(FileManager.default.fileExists(atPath: impostor.appendingPathComponent("sentinel").path))
    try FileManager.default.removeItem(at: impostor)
}

@Test func replacedFixtureRootIsRefusedByCleanup() throws {
    let root = try makeOwnedFixtureRoot(label: "replaced", environment: try seamEnvironment(nil))
    let path = root.physicalPath
    try FileManager.default.removeItem(atPath: path)
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(atPath: path) }

    // Same name, different directory identity: cleanup must refuse.
    #expect(throws: (any Error).self) { try removeOwnedFixtureRoot(root) }
}

@Test func groupWritableFixtureRootIsRefusedByCleanup() throws {
    let root = try makeOwnedFixtureRoot(label: "mode", environment: try seamEnvironment(nil))
    let path = root.physicalPath
    let fileManager = FileManager.default

    // Owned, unmodified handle: cleanup works.
    try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)

    // Group-writable (0770) must be refused: a group member could swap contents between the
    // identity check and removal. Other-write alone is not the only unsafe bit.
    try fileManager.setAttributes([.posixPermissions: 0o770], ofItemAtPath: path)
    #expect(throws: (any Error).self) {
        try removeOwnedFixtureRoot(root, fileManager: fileManager)
    }
    #expect(fileManager.fileExists(atPath: path), "a refused cleanup must leave the child in place")

    // Other-writable (0707) likewise.
    try fileManager.setAttributes([.posixPermissions: 0o707], ofItemAtPath: path)
    #expect(throws: (any Error).self) {
        try removeOwnedFixtureRoot(root, fileManager: fileManager)
    }
    #expect(fileManager.fileExists(atPath: path))

    // Restore a safe mode and clean through the real handle.
    try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
    try removeOwnedFixtureRoot(root, fileManager: fileManager)
    #expect(!fileManager.fileExists(atPath: path))
}

@Test func simulatedNonEnforcingSandboxIsRejectedAndLaunchFailureIsNotDenial() throws {
    let root = try makeOwnedFixtureRoot(label: "simulated", environment: try seamEnvironment(nil))
    defer { try? removeOwnedFixtureRoot(root) }
    let directory = URL(fileURLWithPath: root.physicalPath, isDirectory: true)
    // Capture must be a SIBLING of the denied subpath, never inside it: the real sandbox denies the
    // marker write too, which would make a launch failure look like a denial.
    let captureOwner = try makeOwnedFixtureRoot(label: "simulated-capture", environment: try seamEnvironment(nil))
    defer { try? removeOwnedFixtureRoot(captureOwner) }
    let capture = URL(fileURLWithPath: captureOwner.physicalPath, isDirectory: true)

    let permissive = try observeSandboxMechanism(
        root: directory,
        profile: denialProfileFor(root.physicalPath),
        sandboxExec: "/bin/sh",
        captureDirectory: capture,
        label: "permissive"
    )
    #expect(permissive.executedMarker == "executed")
    #expect(permissive.writeStatus == 0, "the simulated sandbox lets the write through")
    #expect(!permissive.provesDenial, "a successful denied operation must never read as a denial")

    let absent = try observeSandboxMechanism(
        root: directory,
        profile: denialProfileFor(root.physicalPath),
        sandboxExec: "/usr/bin/false",
        captureDirectory: directory,
        label: "absent"
    )
    #expect(absent.executedMarker.isEmpty, "no marker means the child never ran")
    #expect(!absent.provesDenial, "launch failure without a marker must not count as denial")
}

/// Minimal profile builder used by these focused tests only; the CLI seams build theirs from the
/// real cache targets.
private func denialProfileFor(_ subpath: String) -> String {
    let escaped = subpath
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    return """
    (version 1)
    (allow default)
    (deny file-read* (subpath "\(escaped)"))
    (deny file-write* (subpath "\(escaped)"))
    """
}

// MARK: R5 — evidence integrity and authorized-base derivation

@Test func authorizedBaseComesFromInheritedEnvironmentAndResolvesPhysically() throws {
    // The base must come from the inherited keys, and its physical spelling must be resolvable and
    // stable. Both spellings must name one vnode, which is what the sandbox profile relies on.
    let base = try inheritedAuthorizedBase()
    let physical = try #require(physicalPath(base), "the authorized base must resolve physically")
    #expect(try inheritedAuthorizedBase() == base, "the derived base must be stable across calls")
    #expect(physicalPath(physical) == physical, "the physical spelling must itself be physical")
    #expect(physicalPath(base) == physical, "alias and physical spellings must name one vnode")

    // A direct PHYSICAL base is accepted by the factory, producing a root beneath it.
    let direct = try makeOwnedFixtureRoot(label: "physical-base", environment: ["TMPDIR": physical])
    defer { try? removeOwnedFixtureRoot(direct) }
    #expect(direct.physicalPath.hasPrefix(physical + "/") || direct.physicalPath == physical,
            "a child of the physical base must stay beneath it")
}

@Test func testOnlyResolverRejectsNulBytes() throws {
    let base = try inheritedAuthorizedBase()
    #expect(physicalPath(base + "\0ignored") == nil, "a NUL-containing path must be refused")
    #expect(physicalPath("\0") == nil)
    #expect(physicalPath(base) != nil, "the clean path must still resolve")
}

// MARK: R5 — probe evidence integrity (unknown evidence must fail closed)

/// Writes a fake launcher and returns its path plus the OWNED handle for its directory, so the
/// caller can clean up through the real provenance-checked seam.
///
/// The observation seam invokes a sandboxed launcher as
/// `<launcher> -p <profile> /bin/sh <script> <marker> <deniedLeaf> <sentinel> <receipt>`,
/// so the launcher reads the real arguments from `$4` onward: marker is `$5`, receipt is `$8`.
/// `body` is inserted verbatim into a `/bin/sh` script.
private func fakeLauncher(
    _ label: String,
    body: String
) throws -> (path: String, owned: ResolvedFixtureRoot) {
    let owned = try makeOwnedFixtureRoot(label: label, environment: try seamEnvironment(nil))
    let launcher = URL(fileURLWithPath: owned.physicalPath, isDirectory: true)
        .appendingPathComponent("launcher.sh")
    let source = """
    #!/bin/sh
    SCRIPT="$4"
    MARKER="$5"
    DENIED="$6"
    SENTINEL="$7"
    RECEIPT="$8"
    \(body)
    """
    try Data(source.utf8).write(to: launcher)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)
    return (launcher.path, owned)
}

@Test func markerWithMissingReceiptIsNotADenial() throws {
    let root = try makeOwnedFixtureRoot(label: "marker-only", environment: try seamEnvironment(nil))
    defer { try? removeOwnedFixtureRoot(root) }
    let directory = URL(fileURLWithPath: root.physicalPath, isDirectory: true)
    let capture = try makeOwnedFixtureRoot(label: "marker-only-capture", environment: try seamEnvironment(nil))
    defer { try? removeOwnedFixtureRoot(capture) }
    let captureURL = URL(fileURLWithPath: capture.physicalPath, isDirectory: true)

    // Writes only the marker, never the receipt.
    let launcher = try fakeLauncher("marker-launcher", body: "printf 'executed' > \"$MARKER\"")
    defer { try? removeOwnedFixtureRoot(launcher.owned) }

    let observation = try observeSandboxMechanism(
        root: directory,
        profile: "(version 1)(allow default)",
        sandboxExec: launcher.path,
        captureDirectory: captureURL,
        label: "marker-only"
    )
    #expect(observation.executedMarker == "executed", "the fake must actually run and write its marker")
    #expect(observation.writeStatus == nil, "a missing receipt must not yield a status")
    #expect(observation.readStatus == nil)
    #expect(!observation.provesDenial, "marker plus missing receipt is unknown evidence, not a denial")
}

@Test func malformedOrAmbiguousStatusesAreNeverDenial() throws {
    // Every case writes the marker first, so a failure to run is distinguishable from bad evidence.
    let cases: [(String, String)] = [
        ("truncated", "printf 'write=1' > \"$RECEIPT\""),
        ("duplicate", "printf 'write=1\\nwrite=1\\nread=1\\n' > \"$RECEIPT\""),
        ("malformed", "printf 'write=abc\\nread=1\\n' > \"$RECEIPT\""),
        ("negative", "printf 'write=-1\\nread=1\\n' > \"$RECEIPT\""),
        ("out-of-range", "printf 'write=999\\nread=1\\n' > \"$RECEIPT\""),
        ("empty-value", "printf 'write=\\nread=1\\n' > \"$RECEIPT\""),
        ("missing-read", "printf 'write=1\\n' > \"$RECEIPT\""),
    ]

    for (label, receiptBody) in cases {
        let root = try makeOwnedFixtureRoot(label: "evidence-\(label)", environment: try seamEnvironment(nil))
        let directory = URL(fileURLWithPath: root.physicalPath, isDirectory: true)
        let capture = try makeOwnedFixtureRoot(label: "evidence-capture-\(label)", environment: try seamEnvironment(nil))
        let captureURL = URL(fileURLWithPath: capture.physicalPath, isDirectory: true)
        let markerWrite = "printf 'executed' > \"$MARKER\"; "
        let launcher = try fakeLauncher("launcher-\(label)", body: markerWrite + receiptBody)
        defer {
            try? removeOwnedFixtureRoot(launcher.owned)
            try? removeOwnedFixtureRoot(capture)
            try? removeOwnedFixtureRoot(root)
        }

        let observation = try observeSandboxMechanism(
            root: directory,
            profile: "(version 1)(allow default)",
            sandboxExec: launcher.path,
            captureDirectory: captureURL,
            label: label
        )
        #expect(observation.executedMarker == "executed", "\(label) fake must actually run")
        #expect(!observation.provesDenial, "\(label) evidence must fail closed, never read as denial")
    }
}

@Test func nonzeroProbeExitAfterMarkerIsNotADenial() throws {
    let root = try makeOwnedFixtureRoot(label: "nonzero-exit", environment: try seamEnvironment(nil))
    defer { try? removeOwnedFixtureRoot(root) }
    let directory = URL(fileURLWithPath: root.physicalPath, isDirectory: true)
    let capture = try makeOwnedFixtureRoot(label: "nonzero-capture", environment: try seamEnvironment(nil))
    defer { try? removeOwnedFixtureRoot(capture) }
    let captureURL = URL(fileURLWithPath: capture.physicalPath, isDirectory: true)

    // Marker present, statuses look like refusals, but the launcher terminates nonzero afterwards.
    let body = "printf 'executed' > \"$MARKER\"; printf 'write=1\\nread=1\\n' > \"$RECEIPT\"; exit 7"
    let launcher = try fakeLauncher("nonzero-launcher", body: body)
    defer { try? removeOwnedFixtureRoot(launcher.owned) }

    let observation = try observeSandboxMechanism(
        root: directory,
        profile: "(version 1)(allow default)",
        sandboxExec: launcher.path,
        captureDirectory: captureURL,
        label: "nonzero"
    )
    #expect(observation.executedMarker == "executed")
    #expect(observation.writeStatus == 1)
    #expect(observation.probeExitStatus == 7)
    #expect(!observation.provesDenial, "a nonzero probe exit must not be read as a denial")
}

@Test func newlineOnlySentinelMutationIsNotADenial() throws {
    let root = try makeOwnedFixtureRoot(label: "sentinel-newline", environment: try seamEnvironment(nil))
    defer { try? removeOwnedFixtureRoot(root) }
    let directory = URL(fileURLWithPath: root.physicalPath, isDirectory: true)
    let capture = try makeOwnedFixtureRoot(label: "sentinel-newline-capture", environment: try seamEnvironment(nil))
    defer { try? removeOwnedFixtureRoot(capture) }
    let captureURL = URL(fileURLWithPath: capture.physicalPath, isDirectory: true)

    // Every OTHER piece of evidence is a valid denial: marker written, one well-formed refusal per
    // operation, clean receipt, probe exit 0. Only the sentinel is modified — by appending a single
    // newline. A trimmed comparison would call that "unmodified"; byte equality must not.
    let body = #"""
    printf 'executed' > "$MARKER"
    printf '\n' >> "$SENTINEL"
    printf 'write=1\nread=1\n' > "$RECEIPT"
    exit 0
    """#
    let launcher = try fakeLauncher("sentinel-newline-launcher", body: body)
    defer { try? removeOwnedFixtureRoot(launcher.owned) }

    let observation = try observeSandboxMechanism(
        root: directory,
        profile: "(version 1)(allow default)",
        sandboxExec: launcher.path,
        captureDirectory: captureURL,
        label: "sentinel-newline"
    )
    #expect(observation.executedMarker == "executed", "the fake must actually run and write its marker")
    #expect(observation.writeStatus == 1)
    #expect(observation.readStatus == 1)
    #expect(observation.probeExitStatus == 0)
    #expect(observation.sentinelBefore == SandboxProbeObservation.expectedSentinelPayload,
            "the pre-launch sentinel must be the exact expected payload")
    #expect(observation.sentinelAfter == SandboxProbeObservation.expectedSentinelPayload + "\n",
            "the observed sentinel must carry the appended newline byte for byte")
    #expect(!observation.provesDenial,
            "a newline-only sentinel modification must never read as a denial")
}

@Test func unrecognizedReceiptLineIsNotADenial() throws {
    let root = try makeOwnedFixtureRoot(label: "unexpected-receipt", environment: try seamEnvironment(nil))
    defer { try? removeOwnedFixtureRoot(root) }
    let directory = URL(fileURLWithPath: root.physicalPath, isDirectory: true)
    let capture = try makeOwnedFixtureRoot(label: "unexpected-receipt-capture", environment: try seamEnvironment(nil))
    defer { try? removeOwnedFixtureRoot(capture) }
    let captureURL = URL(fileURLWithPath: capture.physicalPath, isDirectory: true)

    // Marker and both valid statuses are present and the sentinel is untouched, so only the surplus
    // `unexpected=1` line distinguishes this from a denial. The contract defines no such key, and an
    // undefined receipt line means the evidence is not understood — which is never a denial.
    let body = #"""
    printf 'executed' > "$MARKER"
    printf 'write=1\nread=1\nunexpected=1\n' > "$RECEIPT"
    exit 0
    """#
    let launcher = try fakeLauncher("unexpected-receipt-launcher", body: body)
    defer { try? removeOwnedFixtureRoot(launcher.owned) }

    let observation = try observeSandboxMechanism(
        root: directory,
        profile: "(version 1)(allow default)",
        sandboxExec: launcher.path,
        captureDirectory: captureURL,
        label: "unexpected-receipt"
    )
    #expect(observation.executedMarker == "executed", "the fake must actually run and write its marker")
    #expect(observation.writeStatus == 1)
    #expect(observation.readStatus == 1)
    #expect(observation.unrecognizedReceiptLines == ["unexpected=1"],
            "the surplus line must be reported verbatim, not silently dropped")
    #expect(!observation.provesDenial, "an undefined receipt line must fail closed, never read as denial")
}
