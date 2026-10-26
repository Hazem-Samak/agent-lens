import Darwin
import Foundation

// M10-A — test-only fixture seams for the real-CLI integration tests.
//
// Two measured facts drive this file:
//
// 1. Seatbelt matches the PHYSICAL pathname. On this platform the inherited `TMPDIR` is spelled
//    `/var/folders/.../T/`, which is a symlink to `/private/var/folders/.../T/`. A
//    `(deny file-write* (subpath /var/folders/...))` profile does NOT deny a write to the physical
//    `/private/var/folders/...` path, so an earlier decoy write succeeded (exit 0) and the
//    isolation test failed even though the profile looked correct. Foundation's
//    `resolvingSymlinksInPath()` does NOT help: measured, it returns the `/var/folders/...`
//    spelling unchanged. Only `realpath(3)` returns the physical name.
//
// 2. `realpath(3)` fails (ENOENT) for a path whose leaf does not exist yet. Fixture roots are
//    created on demand, so resolution walks up to the nearest existing ancestor, resolves that,
//    and re-appends the remaining components. Resolution failure fails closed BEFORE launch.
//
// Nothing here is production code, and nothing here writes to the real AgentLens cache.

/// The physical, kernel-visible pathname of `path`, using POSIX `realpath(3)`.
///
/// Existing paths resolve directly. For a path whose own leaf does not exist yet, the nearest
/// existing ancestor is resolved physically and the remaining components are re-appended
/// verbatim; that is the only case treated as "not created yet".
///
/// A real resolution FAILURE is not a missing leaf and must never be reported as a resolved path:
/// a symlink loop (`ELOOP`), a permission denial (`EACCES`), a non-directory ancestor (`ENOTDIR`)
/// or any other errno yields `nil`, and callers fail closed before launching anything. Treating
/// `ELOOP` as "unresolved suffix" would hand back the loop pathname as if it were physical.
func physicalPath(_ path: String) -> String? {
    // A NUL byte can never be part of a POSIX pathname and would truncate at the C boundary, so a
    // NUL-bearing input is refused outright rather than resolved to its prefix.
    guard !path.utf8.contains(0) else { return nil }
    var existing = URL(fileURLWithPath: path).standardizedFileURL
    var suffix: [String] = []
    while true {
        switch resolveExisting(existing.path) {
        case .resolved(let resolved):
            return suffix.reversed().reduce(resolved) { partial, component in
                URL(fileURLWithPath: partial).appendingPathComponent(component).path
            }
        case .missing:
            let parent = existing.deletingLastPathComponent()
            if parent.path == existing.path { return nil }
            let component = existing.lastPathComponent
            if !component.isEmpty, component != "/" { suffix.append(component) }
            existing = parent
        case .failed:
            return nil
        }
    }
}

private enum ResolutionOutcome {
    case resolved(String)
    /// The pathname itself does not exist (`ENOENT`): its ancestors may still resolve.
    case missing
    /// Any other errno (`ELOOP`, `EACCES`, `ENOTDIR`, ...): a genuine resolution failure.
    case failed
}

private func resolveExisting(_ path: String) -> ResolutionOutcome {
    errno = 0
    guard let resolved = path.withCString({ realpath($0, nil) }) else {
        return errno == ENOENT ? .missing : .failed
    }
    defer { free(resolved) }
    guard let string = String(validatingCString: resolved) else { return .failed }
    return .resolved(string)
}

/// A fixture root THIS PROCESS created through `makeOwnedFixtureRoot`.
///
/// Provenance is not inferred from the path: a name prefix plus an owner UID is reproducible by
/// anyone who can create a directory, so a hand-built value naming a pre-existing directory would
/// otherwise be indistinguishable from a real fixture. The type is therefore unforgeable outside
/// this file — the initializer is private and callers only ever receive an instance from the
/// factory, carrying a per-creation `token` plus the recorded inode identity of the directory it
/// created. `removeOwnedFixtureRoot` re-checks identity before removing anything.
struct ResolvedFixtureRoot {
    /// The spelling to show in reports.
    let displayPath: String
    /// The physical name the sandbox profile must use.
    let physicalPath: String

    /// Per-creation provenance, matched by `removeOwnedFixtureRoot`.
    fileprivate let token: UUID
    /// Authorized base this child was created under.
    fileprivate let authorizedBase: String
    /// Device + inode of the directory created by the factory.
    fileprivate let device: dev_t
    fileprivate let inode: ino_t

    /// Only the factory may mint a handle: `init` is fileprivate, and every caller in this file is
    /// either the factory or the factory's own cleanup path.
    fileprivate init(
        displayPath: String,
        physicalPath: String,
        token: UUID,
        authorizedBase: String,
        device: dev_t,
        inode: ino_t
    ) {
        self.displayPath = displayPath
        self.physicalPath = physicalPath
        self.token = token
        self.authorizedBase = authorizedBase
        self.device = device
        self.inode = inode
    }
}

/// Live-creation registry: a token is valid only while its root still exists unremoved, which is
/// what makes a replayed or guessed handle useless.
private let ownedRootLock = NSLock()
private nonisolated(unsafe) var outstandingRootTokens: Set<UUID> = []

/// Selects and validates the base for a new fixture root, then creates exactly one new child.
///
/// Precedence is `AGENT_LENS_TEST_SCRATCH` (nonempty) then `TMPDIR` (nonempty). With neither, this
/// fails closed — it never falls back to `$HOME`, the repository, or an installed manager's tree.
///
/// An existing explicit base is accepted as an operator-authorized location for a NEW uniquely
/// named child; the base itself is never a cleanup target. The base is resolved physically,
/// required to be a directory, and required to be writable before any child is created.
///
/// A real resolution failure of the base (symlink loop, permission denial, non-directory
/// component) fails closed here; it is never treated as an as-yet-uncreated leaf.
func makeOwnedFixtureRoot(
    label: String,
    environment: [String: String],
    fileManager: FileManager = .default
) throws -> ResolvedFixtureRoot {
    let override = environment["AGENT_LENS_TEST_SCRATCH"]
    let tmpdir = environment["TMPDIR"]

    let base: String
    if let override, !override.isEmpty {
        base = override
    } else if let tmpdir, !tmpdir.isEmpty {
        base = tmpdir
    } else {
        throw fixtureSeamError(
            code: 13,
            "no scratch root available — set AGENT_LENS_TEST_SCRATCH or TMPDIR to a writable "
            + "directory the operator authorizes for test fixtures. Refusing to relocate outside "
            + "authorized storage."
        )
    }

    guard let physicalBase = physicalPath(base) else {
        throw fixtureSeamError(
            code: 14,
            "cannot resolve the physical pathname of the fixture base \(base); refusing to launch "
            + "an isolation test whose sandbox profile would be unenforceable"
        )
    }

    var baseIsDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: physicalBase, isDirectory: &baseIsDirectory),
          baseIsDirectory.boolValue else {
        throw fixtureSeamError(code: 15, "fixture base is not a directory: \(physicalBase)")
    }
    guard fileManager.isWritableFile(atPath: physicalBase) else {
        throw fixtureSeamError(code: 16, "fixture base is not writable: \(physicalBase)")
    }

    // Create under the caller-supplied (DISPLAY) base so the child keeps that spelling: production
    // normalizes observed paths via Foundation and assertions compare display strings. The child's
    // physical pathname is resolved and recorded separately for sandbox profiles and cleanup.
    let child = URL(fileURLWithPath: base, isDirectory: true)
        .appendingPathComponent("agentlens-m6-cli-\(label)-\(UUID().uuidString)", isDirectory: true)
    // `withIntermediateDirectories: false` means an existing path at this name is an error rather
    // than silently adopted: the factory only ever reports directories it created itself.
    try fileManager.createDirectory(at: child, withIntermediateDirectories: false)

    let attributes = try fileManager.attributesOfItem(atPath: child.path)
    guard (attributes[.type] as? FileAttributeType) == .typeDirectory,
          let ownerID = attributes[.ownerAccountID] as? NSNumber,
          ownerID.uint32Value == UInt32(getuid()) else {
        throw fixtureSeamError(code: 17, "new fixture root is not a directory owned by this process: \(child.path)")
    }
    guard let systemNumber = attributes[.systemNumber] as? NSNumber,
          let systemFileNumber = attributes[.systemFileNumber] as? NSNumber else {
        throw fixtureSeamError(code: 18, "new fixture root has no recorded identity: \(child.path)")
    }
    // The child must resolve, and its physical name must sit beneath the physical base. It need not
    // equal the display spelling: the display base may itself be an alias (e.g. `/var/...`).
    guard let physicalChild = physicalPath(child.path),
          physicalChild == child.standardizedFileURL.path || physicalChild.hasPrefix(physicalBase + "/") else {
        throw fixtureSeamError(code: 19, "new fixture root did not resolve beneath its physical base: \(child.path)")
    }
    guard let mode = (attributes[.posixPermissions] as? NSNumber)?.uint16Value, mode & 0o022 == 0 else {
        throw fixtureSeamError(code: 20, "new fixture root is group/other-writable: \(child.path)")
    }

    let token = UUID()
    ownedRootLock.lock()
    outstandingRootTokens.insert(token)
    ownedRootLock.unlock()

    return ResolvedFixtureRoot(
        displayPath: child.path,
        physicalPath: physicalChild,
        token: token,
        authorizedBase: physicalBase,
        device: dev_t(truncatingIfNeeded: systemNumber.int64Value),
        inode: ino_t(truncatingIfNeeded: systemFileNumber.int64Value)
    )
}

/// Removes a fixture root this process created — and ONLY such a root.
///
/// Every guard below is re-checked at cleanup time, because the tree may have been replaced
/// between creation and removal: the token must still be outstanding, the recorded device/inode
/// must still describe a directory, the mode must not be group/other-writable, and the physical
/// path must be a strict child of the recorded authorized base (which is itself never removed).
/// A pre-existing or forged `ResolvedFixtureRoot` cannot satisfy these checks, so nothing outside
/// this factory's own creations is ever deleted.
func removeOwnedFixtureRoot(_ root: ResolvedFixtureRoot, fileManager: FileManager = .default) throws {
    ownedRootLock.lock()
    let known = outstandingRootTokens.contains(root.token)
    ownedRootLock.unlock()
    guard known else {
        throw fixtureSeamError(code: 21, "refusing to remove a root this factory did not create: \(root.physicalPath)")
    }

    // Containment: a strict child of the recorded physical base, never the base itself.
    let baseURL = URL(fileURLWithPath: root.authorizedBase, isDirectory: true)
    let candidate = URL(fileURLWithPath: root.physicalPath, isDirectory: true)
    let baseComponents = baseURL.standardizedFileURL.pathComponents
    let candidateComponents = candidate.standardizedFileURL.pathComponents
    guard candidateComponents.count > baseComponents.count,
          Array(candidateComponents.prefix(baseComponents.count)) == baseComponents else {
        throw fixtureSeamError(code: 22, "refusing to remove a path outside its authorized base: \(root.physicalPath)")
    }

    // The physical resolution must still land on the recorded pathname: a symlink swapped in at
    // this name would otherwise redirect the removal.
    guard physicalPath(root.physicalPath) == root.physicalPath else {
        throw fixtureSeamError(code: 23, "fixture root no longer resolves to itself: \(root.physicalPath)")
    }

    let attributes = try fileManager.attributesOfItem(atPath: root.physicalPath)
    guard (attributes[.type] as? FileAttributeType) == .typeDirectory else {
        throw fixtureSeamError(code: 24, "refusing to remove a fixture root that is no longer a directory: \(root.physicalPath)")
    }
    guard let ownerID = attributes[.ownerAccountID] as? NSNumber,
          ownerID.uint32Value == UInt32(getuid()) else {
        throw fixtureSeamError(code: 27, "refusing to remove a fixture root this user no longer owns: \(root.physicalPath)")
    }
    guard let systemNumber = attributes[.systemNumber] as? NSNumber,
          let systemFileNumber = attributes[.systemFileNumber] as? NSNumber,
          dev_t(truncatingIfNeeded: systemNumber.int64Value) == root.device,
          ino_t(truncatingIfNeeded: systemFileNumber.int64Value) == root.inode else {
        throw fixtureSeamError(code: 25, "refusing to remove a replaced fixture root: \(root.physicalPath)")
    }
    guard let mode = (attributes[.posixPermissions] as? NSNumber)?.uint16Value, mode & 0o022 == 0 else {
        throw fixtureSeamError(code: 26, "refusing to remove a group/other-writable fixture root: \(root.physicalPath)")
    }

    try fileManager.removeItem(atPath: root.physicalPath)

    ownedRootLock.lock()
    outstandingRootTokens.remove(root.token)
    ownedRootLock.unlock()
}

private func fixtureSeamError(code: Int, _ message: String) -> NSError {
    NSError(domain: "AgentLensCLISeam", code: code, userInfo: [NSLocalizedDescriptionKey: message])
}

// MARK: Mechanism-control runner

/// Result of one sandbox mechanism-control probe.
///
/// The child records each operation's status in a file OUTSIDE the denied subpath, so a denial is
/// only accepted when the child demonstrably ran AND both operations were observably refused.
///
/// Unknown evidence is never encoded as success: a missing receipt, a missing/duplicate/malformed
/// status, a negative or out-of-shell-range value, or a nonzero probe exit all leave `provesDenial`
/// false. `writeStatus`/`readStatus` are optional for exactly that reason — the earlier
/// `-1`/`-1` default made a marker-only run indistinguishable from a genuine double refusal.
struct SandboxProbeObservation {
    /// The exact fixture payload the sentinel must contain, INCLUDING its trailing newline.
    static let expectedSentinelPayload = "owned fixture\n"

    let executedMarker: String
    /// Exact raw sentinel bytes read BEFORE launch (no trimming), not a constant.
    let sentinelBefore: String
    /// Exact raw sentinel bytes read after the probe, or nil when unreadable.
    let sentinelAfter: String?
    /// Shell exit status of the denied write, or nil when no single valid status was recorded.
    let writeStatus: Int32?
    /// Shell exit status of the denied read, or nil when no single valid status was recorded.
    let readStatus: Int32?
    /// Probe script exit status (`nil` when the process could not be waited on).
    let probeExitStatus: Int32?
    let readStdout: String
    let deniedLeafExists: Bool
    /// Non-nil when the receipt contained a line the contract does not define.
    let unrecognizedReceiptLines: [String]

    /// A denial is evidence only when the child ran, the script completed successfully, each
    /// operation produced exactly one valid refusal status, the receipt contained nothing
    /// unexpected, and the sentinel was EXACTLY the expected payload both before and after.
    ///
    /// Byte equality is required, not trimmed equality: trimming would hide a newline-only change,
    /// which is still a modification of the file the denial is supposed to protect.
    var provesDenial: Bool {
        executedMarker == "executed"
            && probeExitStatus == 0
            && validRefusal(writeStatus)
            && validRefusal(readStatus)
            && unrecognizedReceiptLines.isEmpty
            && sentinelBefore == Self.expectedSentinelPayload
            && sentinelAfter == Self.expectedSentinelPayload
            && !readStdout.contains("owned fixture")
            && !deniedLeafExists
    }

    /// A refusal is a nonzero shell status inside the shell's conventional range.
    private func validRefusal(_ status: Int32?) -> Bool {
        guard let status else { return false }
        return status > 0 && status <= 255
    }
}

/// Runs identical read/write controls against `root`, through `sentinel`, under `profile`.
///
/// Sentinel lives INSIDE the denied root; marker and receipt live OUTSIDE it so the allowed marker
/// write is never itself denied. The child writes the marker first (proving the intended process
/// started and reached the probe code), attempts a denied write plus a denied read, and records
/// each shell status on its own line. `sandboxExec` is injectable so a test can simulate a sandbox
/// that reports success instead of enforcing, or a launcher that never runs the script;
/// production launch seams always use the real binary.
func observeSandboxMechanism(
    root: URL,
    profile: String,
    sandboxExec: String = "/usr/bin/sandbox-exec",
    captureDirectory: URL,
    label: String
) throws -> SandboxProbeObservation {
    let fileManager = FileManager.default
    let sentinel = root.appendingPathComponent("sentinel")
    if !fileManager.fileExists(atPath: sentinel.path) {
        try Data(SandboxProbeObservation.expectedSentinelPayload.utf8).write(to: sentinel)
    }
    // Read the real pre-operation bytes; never assume them.
    let sentinelBefore = (try? String(contentsOf: sentinel, encoding: .utf8)) ?? ""
    let deniedLeaf = root.appendingPathComponent("denied-write")
    let marker = captureDirectory.appendingPathComponent("mechanism-\(label)-\(UUID().uuidString).marker")
    let receipt = captureDirectory.appendingPathComponent("mechanism-\(label)-\(UUID().uuidString).receipt")

    let script = """
    #!/bin/sh
    # $1 allowed marker, $2 denied leaf, $3 sentinel, $4 receipt
    printf 'executed' > "$1" || exit 90
    touch "$2" 2>/dev/null
    printf 'write=%s\n' "$?" > "$4"
    cat "$3" 2>/dev/null
    printf 'read=%s\n' "$?" >> "$4"
    exit 0
    """
    let scriptURL = captureDirectory.appendingPathComponent("probe-\(label)-\(UUID().uuidString).sh")
    try Data(script.utf8).write(to: scriptURL)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

    let runner = Process()
    let sandboxed = sandboxExec != "/bin/sh"
    runner.executableURL = URL(fileURLWithPath: sandboxed ? sandboxExec : "/bin/sh")
    runner.arguments = sandboxed
        ? ["-p", profile, "/bin/sh", scriptURL.path, marker.path, deniedLeaf.path, sentinel.path, receipt.path]
        : [scriptURL.path, marker.path, deniedLeaf.path, sentinel.path, receipt.path]
    runner.environment = ["PATH": "/usr/bin:/bin"]
    runner.standardInput = FileHandle.nullDevice
    let outPipe = Pipe()
    let errPipe = Pipe()
    runner.standardOutput = outPipe
    runner.standardError = errPipe
    try runner.run()

    let deadline = Date().addingTimeInterval(30)
    while runner.isRunning {
        if Date() >= deadline {
            runner.terminate()
            if runner.isRunning { kill(runner.processIdentifier, SIGKILL) }
            throw fixtureSeamError(code: 20, "\(sandboxExec) exceeded its 30s probe budget")
        }
        Thread.sleep(forTimeInterval: 0.01)
    }
    runner.waitUntilExit()
    let stdout = String(decoding: outPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    _ = errPipe.fileHandleForReading.readDataToEndOfFile()

    // Strict evidence parsing. Each status must appear EXACTLY once and be the only content on its
    // line as a well-formed signed integer; anything else leaves that status nil, so a denial can
    // never be inferred from absent or malformed data.
    let receiptLines: [String]
    if let text = try? String(contentsOf: receipt, encoding: .utf8) {
        receiptLines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    } else {
        receiptLines = []
    }

    let recognizedKeys = ["write", "read"]
    // A trailing empty slice from the final newline is structural; anything else that is neither a
    // recognized `key=value` line nor that single terminator is unexpected evidence.
    let unrecognized = receiptLines.filter { line in
        if line.isEmpty { return false }
        guard let separator = line.firstIndex(of: "=") else { return true }
        let key = String(line[line.startIndex..<separator])
        return !recognizedKeys.contains(key)
    }

    func status(for key: String) -> Int32? {
        let matches = receiptLines.compactMap { line -> String? in
            line.hasPrefix(key + "=") ? String(line.dropFirst(key.count + 1)) : nil
        }
        guard matches.count == 1, let text = matches.first, !text.isEmpty,
              text.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "-") }),
              !text.hasPrefix("-") || text.dropFirst().allSatisfy({ $0.isNumber }),
              let value = Int32(text)
        else { return nil }
        return value
    }

    return SandboxProbeObservation(
        executedMarker: (try? String(contentsOf: marker, encoding: .utf8)) ?? "",
        sentinelBefore: sentinelBefore,
        sentinelAfter: try? String(contentsOf: sentinel, encoding: .utf8),
        writeStatus: status(for: "write"),
        readStatus: status(for: "read"),
        probeExitStatus: runner.terminationStatus,
        readStdout: stdout,
        deniedLeafExists: fileManager.fileExists(atPath: deniedLeaf.path),
        unrecognizedReceiptLines: unrecognized
    )
}