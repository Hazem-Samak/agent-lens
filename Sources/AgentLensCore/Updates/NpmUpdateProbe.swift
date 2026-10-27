// NpmUpdateProbe — bounded npm latest-version status probe (M10-B).
//
// Queries only the verified public npm registry for the exact verified package's `latest` dist
// tag, using `npm view <name>@latest name version dist-tags.latest --json`. Every npm invocation
// uses an app-owned temporary npm cache/log root, mode 0700, unique per invocation group: one root
// for each complete ownership verification (shared by its prefix/root subprocesses) and separate
// roots for each registry/version/metadata invocation, outside personal npm cache and install
// roots. The scratch BASE is validated before any launch (R07): a missing, symlinked,
// non-directory, foreign-owned or group/other-writable injected root refuses with zero npm commands,
// while symlinked ANCESTORS are tolerated (the sanctioned default TMPDIR `/var/…` physical alias).
// Each claimed child is a unique mode-0700 direct physical child of the validated base recorded by
// device+inode, and cleanup is anchored to that record: only the owned child is ever removed, and a
// child that cannot be removed is propagated as a failure instead of discarded.
// Registry routing is validated before any metadata query; custom or malformed routes refuse
// with zero metadata requests.
//
// Process call budget per subject (nominal, before re-verification):
//   - unscoped: 6 verification/config calls (prefix, root ×2; registry ×2) plus an optional view
//     and one npm --version; B02.4 then re-reads ownership (2) and effective registry (2) before
//     publication, so a successful unscoped check costs 10 config/ownership calls plus view/version.
//   - scoped: the same shape with the scope-registry config doubling every registry step.
// The 60-second monotonic stage budget, enforced by the coordinator's deadline-clipping runner and
// the injected clock reported here, bounds the real cost; a stage that cannot finish reports
// `budgetExhausted` and publishes nothing rather than a partial or stale verified result.
//
// Identity: every field of the returned result — registry ID, display name, diagnostic, index and
// the local version carried by that exact diagnostic — is preserved on BOTH the verified and the
// neutral path. A refusal never fabricates an empty diagnostic or a blank identity: an unknown is
// still about the same tool.

import Foundation
import Darwin

/// The one npm metadata semantics vocabulary, shared by the fresh `view` parser and by the
/// persistent metadata cache (R06). A stored key is not proof of valid metadata, so the cache must
/// validate a restored document with exactly these rules rather than a weaker copy. Internal: it
/// exposes no new public surface and no adapter framework.
enum NpmMetadataSemantics {
    /// The only accepted public npm registry base, with a trailing slash (the normalized form).
    static let acceptedRegistry = "https://registry.npmjs.org/"
    /// The accepted base without the optional trailing slash, used for equality testing.
    static let acceptedRegistryNoSlash = "https://registry.npmjs.org"
    /// The only dist tag this phase reads or stores; never the configurable default tag.
    static let latestTag = "latest"

    /// Normalizes a registry URL for eligibility: accepted only when it is exactly
    /// `https://registry.npmjs.org/` with an optional trailing slash, no credentials, query,
    /// fragment, alternate port, or path.
    static func normalizedAcceptedRegistry(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == acceptedRegistry || trimmed == acceptedRegistryNoSlash else { return nil }
        return acceptedRegistry
    }

    /// True only for the exact normalized accepted origin, which is what a persisted record must
    /// already carry. Anything else (custom host, scheme, port, path, credential, trailing-slash
    /// variant) is an unsupported registry.
    static func isAcceptedNormalizedRegistry(_ value: String) -> Bool {
        value == acceptedRegistry
    }

    /// Strict SemVer 2.0.0 grammar — no two/four-component tolerance, the same check a fresh parse
    /// requires.
    static func isStrictSemanticVersion(_ text: String) -> Bool {
        VersionComparison.parseSemanticVersion(text, allowTwoComponents: false) != nil
    }

    /// Strict SemVer on the STABLE channel: the prerelease component must be absent. A prerelease
    /// `latest` is an unsupported channel and is never a persisted, reusable observation.
    static func isStableSemanticVersion(_ text: String) -> Bool {
        guard let parsed = VersionComparison.parseSemanticVersion(text, allowTwoComponents: false)
        else { return false }
        return parsed.prerelease.isEmpty
    }

    /// The catalogue's own npm package-name grammar, so a stored identity is validated by the same
    /// rule a declared candidate is.
    static func isValidNpmPackageName(_ text: String) -> Bool {
        DeclaredPackage.validationFailure(manager: .npm, name: text) == nil
    }

    /// `version` must be a strict SemVer exactly equal to `dist-tags.latest`: the measured single
    /// `@latest` object. Shared by the fresh parser and the stored-record validator; a divergence
    /// means the object is not one unambiguous latest observation.
    static func versionMatchesLatestTag(_ version: String, distTagsLatest: String) -> Bool {
        version == distTagsLatest && isStrictSemanticVersion(version)
    }
}

/// The only accepted public npm registry base, with a trailing slash (the normalized form).
private let acceptedRegistry = NpmMetadataSemantics.acceptedRegistry

/// npm metadata query timeout, seconds.
private let npmMetadataTimeout: TimeInterval = 20
/// npm registry config query timeout, seconds.
private let npmConfigTimeout: TimeInterval = 3
/// npm version query timeout, seconds.
private let npmVersionTimeout: TimeInterval = 3

/// The dist tag always requested; never the configurable default tag.
private let npmLatestTag = NpmMetadataSemantics.latestTag

/// Environment keys the flow rewrites to an invocation-local scratch root, plus `TMPDIR`. These
/// are excluded from the persistent cache context digest because they change every invocation
/// while identity does not (M10-B brief B04.2). Matched case-insensitively.
private let npmVolatileEnvironmentKeys: Set<String> = [
    "npm_config_cache", "npm_config_logs_dir", "npm_config_update_notifier", "tmpdir"
]

/// Strictly parsed `npm view @latest` output: one flat object with the three measured keys.
private struct NpmViewOutput: Equatable, Sendable {
    let name: String
    let version: String
    let distTagsLatest: String
}

/// Parses the measured flat `npm view <name>@latest name version dist-tags.latest --json` shape:
/// exactly one JSON object with exactly the three flat string keys `name`, `version`,
/// `dist-tags.latest`. Rejects empty/multiple objects, extra keys, nested tag shape, name
/// mismatch, wrong types, malformed JSON, missing tag/version, banners on stdout, and
/// truncation (oversize output is already rejected by the runner's 1 MiB cap).
private func parseNpmViewOutput(_ data: Data, expectedPackage: String) -> NpmViewOutput? {
    guard let text = String(data: data, encoding: .utf8) else { return nil }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    guard let jsonData = trimmed.data(using: .utf8) else { return nil }
    guard let object = try? JSONSerialization.jsonObject(with: jsonData, options: []),
          let dict = object as? [String: Any]
    else { return nil }
    // Exactly the three measured flat keys, no more, no fewer.
    guard dict.keys.count == 3,
          dict["name"] is String,
          dict["version"] is String,
          dict["dist-tags.latest"] is String
    else { return nil }
    guard let name = dict["name"] as? String,
          let version = dict["version"] as? String,
          let distTagsLatest = dict["dist-tags.latest"] as? String
    else { return nil }
    guard name == expectedPackage else { return nil }
    // `version` must be a strict SemVer and exactly equal to `dist-tags.latest` (the measured
    // @latest shape). The cache validates a restored record with this same rule.
    guard NpmMetadataSemantics.versionMatchesLatestTag(
        version, distTagsLatest: distTagsLatest
    ) else { return nil }
    return NpmViewOutput(name: name, version: version, distTagsLatest: distTagsLatest)
}

/// Converts a restored cache record into the SAME strictly validated triple a fresh `view` parse
/// yields. A cache key match is not proof of valid metadata: unless the record still satisfies the
/// stored-record rules (accepted normalized registry and `latest` tag, validated package/name
/// equality, stable strict SemVer `version == dist-tags.latest`), it is refused here and the stage
/// falls through to a fresh bounded query instead of borrowing poisoned metadata (R06).
private func npmViewOutput(from cached: NpmUpdateMetadataEntry) -> NpmViewOutput? {
    guard cached.isFullyValidatedRecord else { return nil }
    return NpmViewOutput(name: cached.name, version: cached.version, distTagsLatest: cached.distTagsLatest)
}

/// True when a strict-SemVer `latest` carries a non-empty prerelease component. A prerelease
/// channel is never recommended as an update; the caller reports an unsupported-channel unknown.
private func isPrerelease(_ text: String) -> Bool {
    guard let parsed = VersionComparison.parseSemanticVersion(text, allowTwoComponents: false)
    else { return false }
    return !parsed.prerelease.isEmpty
}

/// Normalizes a registry URL for eligibility (see `NpmMetadataSemantics`): accepted only when it is
/// exactly `https://registry.npmjs.org/` with an optional trailing slash, no credentials, query,
/// fragment, alternate port, or path.
private func normalizeAndValidateRegistry(_ value: String) -> String? {
    NpmMetadataSemantics.normalizedAcceptedRegistry(value)
}

/// The scope component of an npm package name, when it is scoped (`@scope/name`).
private func scopeOf(_ packageName: String) -> String? {
    let components = packageName.split(separator: "/", omittingEmptySubsequences: false)
    guard components.count == 2, let first = components.first, first.hasPrefix("@") else {
        return nil
    }
    return String(first)
}

/// The reason an effective registry route was refused, or why a config query could not prove it.
private enum RegistryRoute: Equatable, Sendable {
    /// Base public registry, no scope relevant (unscoped package or unset scope).
    case basePublic(registry: String)
    /// Scoped package with accepted public base and accepted public or unset scope registry.
    case scoped(registry: String, scopeRegistry: String?)
    /// Refused: custom/malformed registry, or a failed/timed-out config query. Carries the exact
    /// shared unknown reason so zero metadata requests are sent on any refusal.
    case refused(reason: UnknownReason)
}

/// Maps a bounded npm command failure to a shared unknown reason. Timeout is distinguished
/// from every other opaque failure; only a well-formed custom/malformed value is `unsupportedRegistry`.
/// A `.cancelled` failure caused by the coordinator's deadline-clipping runner refusing at the
/// exhausted aggregate stage deadline maps to `budgetExhausted`, not a generic cancelled/
/// probeFailed; an actual task cancellation keeps its opaque reason.
private func configFailureReason(
    _ failure: CommandFailure,
    aggregateDeadlineExhausted: Bool,
    taskCancelled: Bool
) -> UnknownReason {
    switch failure {
    case .timedOut: .queryTimedOut
    case .cancelled where aggregateDeadlineExhausted && !taskCancelled: .budgetExhausted
    default: .probeFailed
    }
}

/// True only for the measured unset-scope outputs (`undefined`/`null`, as emitted by supported
/// npm for an unset scope config). An EMPTY output is NOT unset: blank/whitespace-only scope
/// output is malformed and must be refused, never silently reinterpreted as falling back to base.
private func isUnsetScopeOutput(_ text: String) -> Bool {
    text.caseInsensitiveCompare("undefined") == .orderedSame
        || text.caseInsensitiveCompare("null") == .orderedSame
}

/// Derives the effective registry route for the verified package from npm config output.
///
/// `npm config get registry --global` must resolve to the accepted public base. For a scoped
/// package, `npm config get @scope:registry --global` must be accepted public or the measured
/// unset value (`undefined`/`null`). Failed/malformed/ambiguous/empty values refuse.
/// A custom base + public scope is refused: zero public fallback.
private func resolveRegistryRoute(
    packageName: String,
    runner: UpdateCommandRunner,
    environment: [String: String],
    npmPath: String,
    scratchArguments: [String],
    aggregateDeadlineExhausted: Bool,
    taskCancelled: Bool
) async -> RegistryRoute {
    // Base registry.
    let baseOutcome = await runner.run(
        executablePath: npmPath,
        arguments: scratchArguments + ["config", "get", "registry", "--global"],
        environment: environment,
        timeout: npmConfigTimeout
    )
    switch baseOutcome {
    case .failure(let failure):
        return .refused(reason: configFailureReason(
            failure, aggregateDeadlineExhausted: aggregateDeadlineExhausted,
            taskCancelled: taskCancelled
        ))
    case .success(let baseData):
        guard let baseText = String(data: baseData, encoding: .utf8),
              let baseRegistry = normalizeAndValidateRegistry(baseText)
        else { return .refused(reason: .unsupportedRegistry) }
        // Scope registry, only when the package is scoped.
        if let scope = scopeOf(packageName) {
            let scopeOutcome = await runner.run(
                executablePath: npmPath,
                arguments: scratchArguments + ["config", "get", "\(scope):registry", "--global"],
                environment: environment,
                timeout: npmConfigTimeout
            )
            switch scopeOutcome {
            case .failure(let failure):
                return .refused(reason: configFailureReason(
                    failure, aggregateDeadlineExhausted: aggregateDeadlineExhausted,
                    taskCancelled: taskCancelled
                ))
            case .success(let scopeData):
                let scopeText = String(data: scopeData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                // Only the MEASURED unset values fall back to base; an empty value is malformed.
                if isUnsetScopeOutput(scopeText) {
                    return .scoped(registry: baseRegistry, scopeRegistry: nil)
                }
                guard !scopeText.isEmpty,
                      let scopeRegistry = normalizeAndValidateRegistry(scopeText) else {
                    return .refused(reason: .unsupportedRegistry)
                }
                return .scoped(registry: baseRegistry, scopeRegistry: scopeRegistry)
            }
        }
        return .basePublic(registry: baseRegistry)
    }
}

/// Derives the metadata argument array for `npm view`, binding the accepted registry into both
/// `--registry=<accepted>` and, for EVERY scoped verified package, `--@scope:registry=<accepted>`
/// after eligibility is established — even when the scope config reported the measured unset
/// value, where the accepted normalized public origin is pinned. A user-level scope override
/// outranks the base registry flag alone, so the scoped flag is essential on both the configured
/// and unset-scope paths. These binding flags never turn a refused custom route into an eligible one.
private func metadataArguments(
    packageName: String,
    route: RegistryRoute,
    scratchArguments: [String]
) -> [String] {
    var args = scratchArguments + ["view", "\(packageName)@\(npmLatestTag)",
                                   "name", "version", "dist-tags.latest",
                                   "--json", "--global"]
    switch route {
    case .basePublic(let registry):
        args.append("--registry=\(registry)")
    case .scoped(let registry, let scopeRegistry):
        args.append("--registry=\(registry)")
        if let scope = scopeOf(packageName) {
            // An unset scope pins the same accepted public origin as the effective base route.
            args.append("--\(scope):registry=\(scopeRegistry ?? registry)")
        }
    case .refused:
        break
    }
    args.append(contentsOf: ["--prefer-online", "--offline=false", "--fetch-retries=0",
                             "--fetch-timeout=10000"])
    return args
}

/// Derives a per-invocation npm environment by copying the raw session environment, removing
/// case-insensitive npm cache/log/notifier duplicates, and setting canonical values to this
/// invocation's owned scratch root. Inherited registry/scope/userconfig/globalconfig/prefix
/// settings and auth are preserved; only cache/log/update-notifier are overridden.
private func npmEnvironment(
    raw: [String: String],
    cacheRoot: String
) -> [String: String] {
    var values = raw
    for key in values.keys where npmVolatileEnvironmentKeys.contains(key.lowercased())
        && key.lowercased() != "tmpdir"
    {
        values.removeValue(forKey: key)
    }
    values["NPM_CONFIG_CACHE"] = cacheRoot
    values["NPM_CONFIG_LOGS_DIR"] = cacheRoot
    values["NPM_CONFIG_UPDATE_NOTIFIER"] = "false"
    return values
}

/// Copies a captured environment, overriding only its npm cache/log/notifier settings to the
/// invocation's owned scratch root. PATH, TMPDIR and every routing/auth setting are preserved
/// verbatim so the existing ownership verifier reads the same config it always did — only the write
/// target is redirected outside any personal cache.
private func derivedScratchEnvironment(
    _ base: ShellEnvironment,
    cacheRoot: String
) -> ShellEnvironment {
    ShellEnvironment(
        shellPath: base.shellPath,
        pathEntries: base.pathEntries,
        pathJoined: base.pathJoined,
        raw: npmEnvironment(raw: base.raw, cacheRoot: cacheRoot),
        isDegraded: base.isDegraded
    )
}

/// Scratch flags appended to every non-ownership npm invocation in this flow.
private func npmScratchArguments(cacheRoot: String) -> [String] {
    ["--cache", cacheRoot, "--logs-dir", cacheRoot, "--no-update-notifier"]
}

/// An anchored, validated npm scratch BASE (R07).
///
/// The injected base is the caller's owned root — production passes Foundation's `temporaryDirectory`,
/// tests/host pass an owned directory. Validation refuses an unsafe injected root BEFORE any npm
/// process is launched: a missing path, a base that is itself a symlink (an arbitrary retarget),
/// anything that is not a directory, or a directory this process does not own and that is writable
/// by group or other (the classic shared-temp hazard). The base's own ANCESTORS may legitimately be
/// symlinks: macOS spells the sanctioned default `TMPDIR` as `/var/folders/…/T/`, a physical alias of
/// `/private/var/folders/…/T/`, and that lexical alias is never treated as unsafe. The resolved
/// physical pathname is captured once and every claimed child is anchored to it.
struct NpmScratchBase: Equatable, Sendable {
    /// The validated base in its own physical spelling, so a claimed child's own name is never a
    /// symlink and cleanup can re-anchor at the exact recorded pathname.
    let lexicalURL: URL
    /// `realpath(3)` of the validated base.
    let physicalPath: String

    /// Validates the injected base, or returns nil when the root is unsafe/unusable.
    init?(url: URL) {
        let lexical = url.standardizedFileURL.path
        guard !lexical.isEmpty else { return nil }
        var info = Darwin.stat()
        // `lstat` on the base itself: a symlinked injected root is refused, never followed.
        guard Darwin.lstat(lexical, &info) == 0 else { return nil }
        guard !Self.isSymlink(info.st_mode), FileIdentityObserver.isDirectory(info.st_mode) else {
            return nil
        }
        // The owner must be this process's user, with no group/other write access.
        guard info.st_uid == getuid(),
              info.st_mode & mode_t(S_IWGRP | S_IWOTH) == 0
        else { return nil }
        guard let resolved = Self.physicalPath(of: lexical) else { return nil }
        self.lexicalURL = URL(fileURLWithPath: resolved, isDirectory: true)
        self.physicalPath = resolved
    }

    /// POSIX `realpath(3)`, the same physical resolver the M9 identity seams use: Foundation's
    /// `resolvingSymlinksInPath()` demonstrably returns the un-resolved alias spelling.
    static func physicalPath(of path: String) -> String? {
        guard let resolved = path.withCString({ realpath($0, nil) }) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// True when an `lstat` mode names a symbolic link (the module's `S_IFMT` masking idiom).
    static func isSymlink(_ mode: mode_t) -> Bool {
        (mode & mode_t(S_IFMT)) == mode_t(S_IFLNK)
    }
}

/// One owned scratch child created under a validated base, together with the identity THIS process
/// observed when it created it (R07).
struct NpmScratchRoot: Equatable, Sendable {
    /// The exact claimed path (validated base's physical spelling + the unique component).
    let url: URL
    /// The physical pathname recorded at creation; cleanup must still resolve exactly here.
    let physicalPath: String
    let device: dev_t
    let inode: ino_t

    /// Creates ONE unique mode-0700 child of the validated base and records its observed ownership
    /// identity. No intermediate directory is ever created and no symlink is followed — the base
    /// itself already passed validation. Returns nil when the child cannot be created, cannot be
    /// set to 0700, is not a directory owned by this process, or is not physically a direct child
    /// of the validated base. Every such case is a hard stop BEFORE any npm command is launched.
    static func claim(base: NpmScratchBase) -> NpmScratchRoot? {
        let child = base.lexicalURL
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let manager = FileManager.default
        var createdHere = false
        do {
            try manager.createDirectory(
                at: child, withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            createdHere = true
        } catch let error as POSIXError where error.code == .EEXIST {
            // A unique random name can only collide by chance. Never adopt an object this call did
            // not create: it has no observed identity to recheck during cleanup.
            return nil
        } catch {
            return nil
        }

        func abandon() {
            if createdHere { try? manager.removeItem(at: child) }
        }

        // The process `umask` is not trusted to have left 0700: set it explicitly, then re-observe.
        guard chmod(child.path, 0o700) == 0 else {
            abandon()
            return nil
        }
        var info = Darwin.stat()
        guard Darwin.lstat(child.path, &info) == 0,
              FileIdentityObserver.isDirectory(info.st_mode),
              info.st_uid == getuid()
        else {
            abandon()
            return nil
        }
        // Anchor: the claimed name must still be a direct physical child of the validated base,
        // under exactly the component this call created. Foundation normalization is deliberately
        // NOT used here — `standardizedFileURL` rewrites the `/private/var/…` physical spelling
        // back to the `/var/…` alias, which would reject the sanctioned default TMPDIR.
        guard let physical = NpmScratchBase.physicalPath(of: child.path),
              physical.hasPrefix(base.physicalPath + "/"),
              String(physical.dropFirst(base.physicalPath.count + 1)) == child.lastPathComponent,
              URL(fileURLWithPath: physical, isDirectory: true)
                  .deletingLastPathComponent().path == base.physicalPath
        else {
            abandon()
            return nil
        }
        return NpmScratchRoot(
            url: URL(fileURLWithPath: physical, isDirectory: true),
            physicalPath: physical, device: info.st_dev, inode: info.st_ino
        )
    }
}

/// Accumulates scratch cleanup failures for one probe run so they are PROPAGATED rather than
/// silently discarded (R07): a run that could not remove an owned child it created never reports a
/// verified success and never implies zero leftovers. Foundation `NSLock` only.
final class NpmScratchCleanupLedger: @unchecked Sendable {
    private let lock = NSLock()
    private var failureCount = 0

    var hasFailures: Bool {
        lock.lock(); defer { lock.unlock() }
        return failureCount > 0
    }

    var failures: Int {
        lock.lock(); defer { lock.unlock() }
        return failureCount
    }

    fileprivate func recordFailure() {
        lock.lock(); failureCount += 1; lock.unlock()
    }

    /// Removes ONE owned child created through `NpmScratchRoot.claim`, rechecking the exact recorded
    /// identity first: the same vnode (device + inode), still a directory owned by this process, and
    /// still resolving to exactly the physical pathname claimed at creation. A path that was
    /// replaced, retargeted through a swapped ancestor, or that cannot be removed is reported as a
    /// cleanup failure and left in place — nothing outside the recorded owned child is ever removed.
    @discardableResult
    func release(_ root: NpmScratchRoot) -> Bool {
        var info = Darwin.stat()
        let isRecordedDirectory = Darwin.lstat(root.url.path, &info) == 0
            && FileIdentityObserver.isDirectory(info.st_mode)
            && info.st_uid == getuid()
            && info.st_dev == root.device
            && info.st_ino == root.inode
        guard isRecordedDirectory,
              NpmScratchBase.physicalPath(of: root.url.path) == root.physicalPath
        else {
            recordFailure()
            return false
        }
        do {
            try FileManager.default.removeItem(at: root.url)
            return true
        } catch {
            recordFailure()
            return false
        }
    }
}

/// Claims a unique mode-0700 scratch root under `baseURL`, anchored to the validated physical base.
/// Returns nil — a hard stop before any launch — when the injected base is unsafe/missing or the
/// owned child cannot be created and verified. Every caller treats nil as a refusal.
private func createScratchRoot(baseURL: URL) -> NpmScratchRoot? {
    guard let base = NpmScratchBase(url: baseURL) else { return nil }
    return NpmScratchRoot.claim(base: base)
}

/// Removes an owned scratch child and reports whether cleanup actually succeeded, so a caller can
/// never claim a fully-verified stage while an owned root it created is still present.
private func removeScratchRoot(
    _ root: NpmScratchRoot, ledger: NpmScratchCleanupLedger
) -> Bool {
    ledger.release(root)
}

/// A stable, length-framed digest of an `ExecutableFingerprint`. Every field is included so a
/// replacement, retarget or metadata change produces a different digest. Never Swift's randomized
/// `Hasher`.
private func fingerprintString(_ fingerprint: ExecutableFingerprint) -> String {
    let material: [String] = [
        "device", String(fingerprint.device),
        "inode", String(fingerprint.inode),
        "mode", String(fingerprint.mode),
        "size", String(fingerprint.size),
        "mtime", "\(fingerprint.modifiedSeconds).\(fingerprint.modifiedNanoseconds)",
        "ctime", "\(fingerprint.changedSeconds).\(fingerprint.changedNanoseconds)"
    ]
    let framed = material.map { "\($0.utf8.count):\($0)" }.joined()
    return UpdateMetadataKey.stableDigest(framed)
}

/// The selected entry and observed canonical target taken from the M5 selection itself, so a PATH
/// winner and a verified off-PATH selection are treated identically. Mirrors the coordinator's
/// `selectedPair`, retyped for this probe's neutral-construction call sites.
private func npmSelectionPair(_ diagnostic: ToolPathDiagnostic) -> (entry: String, target: String)? {
    let candidate: PathCandidateObservation
    switch diagnostic.selection {
    case .winner(let value): candidate = value
    case .offPath(let value, _): candidate = value
    case .notInstalled, .inconsistent: return nil
    }
    guard let target = candidate.canonicalTarget, !target.isEmpty else { return nil }
    return (candidate.entryPath, target)
}

public enum NpmUpdateProbe {

    /// Runs the bounded npm latest-version probe for one verified subject. Returns a
    /// `ToolUpdateResult` with npm-specific fields and provenance. All process work uses the
    /// supplied (deadline-clipped) runner and per-invocation scratch roots.
    public static func run(
        definition: DetectorDefinition,
        diagnostic: ToolPathDiagnostic,
        environment: ShellEnvironment,
        runner: UpdateCommandRunner,
        cacheURL: URL,
        mode: UpdateProbeMode,
        currentDirectory: String,
        now: @escaping @Sendable () -> Date,
        uptime: @escaping @Sendable () -> UInt64,
        stageDeadline: UInt64,
        diagnosticIndex: Int,
        npmScratchBaseURL: URL? = nil
    ) async -> ToolUpdateResult {
        // Local facts come from this exact diagnostic; never borrowed from another selection.
        let installed = diagnostic.detectedTool.version.map(Version.init)

        func neutral(
            _ reason: UnknownReason,
            installed: Version?,
            selection: (entry: String, target: String)? = nil,
            manager: ObservedExecutable? = nil,
            npmPackage: String? = nil,
            registry: String? = nil,
            npmVersion: String? = nil
        ) -> ToolUpdateResult {
            ToolUpdateResult(
                registryID: definition.id,
                displayName: definition.displayName,
                diagnosticIndex: diagnosticIndex,
                diagnostic: diagnostic,
                localVersion: installed?.text,
                selectedEntryPath: selection?.entry,
                selectedTarget: selection?.target,
                selectedKegVersion: nil,
                managerEntryPath: manager?.entryPath,
                managerTarget: manager?.canonicalTarget,
                managerFingerprint: manager.map { fingerprintString($0.fingerprint) },
                managerCellar: nil,
                formulaStem: nil,
                fullFormulaName: nil,
                npmPackage: npmPackage,
                npmRegistry: registry,
                npmTag: registry != nil ? npmLatestTag : nil,
                npmVersion: npmVersion,
                status: .unknown(installed: installed, reason: reason),
                provenance: .none
            )
        }

        /// A neutral result for a failure AFTER the scratch root and selection identity are known:
        /// carries the re-observed selection and the resolved manager, plus the declared npm
        /// package placeholder where one exists. Only neutral results derived from a VERIFIED
        /// installation use `installation.packageName` (see the ownership gate below); this
        /// placeholder never authorizes a lookup.
        func neutralFailure(
            _ reason: UnknownReason,
            selection: (entry: String, target: String),
            manager: ObservedExecutable,
            package: String? = nil,
            registry: String? = nil,
            npmVersion: String? = nil
        ) -> ToolUpdateResult {
            neutral(
                reason, installed: installed, selection: selection, manager: manager,
                npmPackage: package, registry: registry, npmVersion: npmVersion
            )
        }

        // The selection pair (entry + observed canonical target) from the M5 diagnostic itself.
        guard let selection = npmSelectionPair(diagnostic) else {
            return neutral(.installedVersionUnavailable, installed: installed)
        }
        // Re-observe the selected executable with its REAL live fingerprint, exactly as the
        // standalone verifier does. A fingerprint built from zeros would fail every proof recheck.
        guard let observedSelection = FileIdentityObserver.observeExecutable(
            entryPath: selection.entry
        ), observedSelection.canonicalTarget == selection.target else {
            return neutral(.identityUnverified, installed: installed, selection: selection)
        }
        guard let localVersion = installed, !localVersion.text.isEmpty else {
            return neutral(.installedVersionUnavailable, installed: nil, selection: selection)
        }

        // Resolve the npm manager from the captured session environment.
        guard let manager = NpmOwnershipProbe.resolveNpmManager(
            environment: environment, currentDirectory: currentDirectory
        ) else {
            return neutral(.managerUnavailable, installed: localVersion, selection: selection)
        }

        // A declared npm package name is a PLACEHOLDER only: it may appear on a neutral result
        // before ownership proves anything, and it never authorizes a registry lookup, a metadata
        // argv, or a cache key. The verified identity arrives with the matched installation below.
        let declaredNpmPackage = definition.packages.first(where: { $0.manager == .npm })?.name

        // Scratch base: injected owned root in tests/host; Foundation temporary directory in
        // production. No personal npm cache or install root is ever used. The base is VALIDATED
        // before any launch (R07): a symlinked, unowned, world/group-writable or missing injected
        // root refuses with zero npm commands, while the sanctioned default TMPDIR physical alias
        // (`/var/…` → `/private/var/…`) resolves normally. The ledger records every owned child
        // this run could not remove, so a cleanup failure is reported rather than claimed away.
        let scratchBase = npmScratchBaseURL ?? FileManager.default.temporaryDirectory
        let scratchLedger = NpmScratchCleanupLedger()

        // ---- Initial full ownership verification (one scratch root shared by prefix/root) ----
        guard let ownershipScratch = createScratchRoot(baseURL: scratchBase) else {
            return neutralFailure(.probeFailed, selection: selection, manager: manager,
                                  package: declaredNpmPackage)
        }
        let initialOwnership = await verifyOwnership(
            definition: definition,
            selection: observedSelection,
            manager: manager,
            baseEnvironment: environment,
            scratchRoot: ownershipScratch,
            runner: runner
        )
        _ = removeScratchRoot(ownershipScratch, ledger: scratchLedger)

        switch initialOwnership {
        case .refused(let reason), .failed(let reason):
            // No verified installation exists, so only the display placeholder is carried; the
            // verified package identity is never borrowed from an unmatched declaration (R01).
            return neutralFailure(
                reason, selection: selection, manager: manager, package: declaredNpmPackage
            )
        case .verified(let installation, let proof):
            // R01: after unique ownership succeeds, the ONLY identity allowed to authorize a
            // lookup is the matched installation's verified package name — which may come from a
            // later declaration than the first. No pre-verification first-declaration identity
            // reaches this point.
            let npmPackage = installation.packageName
            guard !npmPackage.isEmpty else {
                // A verified installation without a usable name cannot carry any lookup identity.
                return neutralFailure(.identityUnverified, selection: selection, manager: manager)
            }
            // ---- Registry route eligibility (separate scratch, config flags, timeout-clipped) ----
            guard uptime() < stageDeadline else {
                return neutralFailure(.budgetExhausted, selection: selection, manager: manager,
                                      package: npmPackage)
            }
            let route = await registryRoute(
                packageName: npmPackage, environment: environment, manager: manager,
                scratchBase: scratchBase, ledger: scratchLedger, runner: runner, uptime: uptime,
                stageDeadline: stageDeadline
            )
            switch route {
            case .refused(let reason):
                return neutralFailure(reason, selection: selection, manager: manager,
                                      package: npmPackage)
            case .basePublic, .scoped:
                break
            }
            let accepted = acceptedRegistry

            // ---- Cache lookup (Check only; Refresh always re-fetches) ----
            let contextDigest = npmContextDigest(
                environment: environment, currentDirectory: currentDirectory,
                registry: accepted, package: npmPackage
            )
            let cache = NpmUpdateMetadataCache(updateCacheURL: cacheURL, now: now)
            let key = NpmUpdateMetadataKey(
                registryID: definition.id,
                package: npmPackage,
                registry: accepted,
                tag: npmLatestTag,
                managerEntryPath: manager.entryPath,
                managerTarget: manager.canonicalTarget,
                managerFingerprint: fingerprintString(manager.fingerprint),
                prefix: installation.managerRoot,
                installationRoot: installation.installationRoot,
                selectedEntryPath: selection.entry,
                selectedTarget: selection.target,
                selectedFingerprint: fingerprintString(proof.selection.fingerprint),
                proofFingerprint: proof.fingerprint,
                contextDigest: contextDigest
            )
            var viewOutput: NpmViewOutput?
            var cachedObservedAt: Date?
            if mode == .checkUpdates,
               let cached = cache.lookup(key),
               let restored = npmViewOutput(from: cached)
            {
                viewOutput = restored
                cachedObservedAt = cached.observedAt
            }

            // ---- Metadata view (only on cache miss) ----
            if viewOutput == nil {
                guard uptime() < stageDeadline, !Task.isCancelled else {
                    return neutralFailure(
                        Task.isCancelled ? .probeFailed : .budgetExhausted,
                        selection: selection, manager: manager,
                        package: npmPackage, registry: accepted
                    )
                }
                let view = await metadataView(
                    packageName: npmPackage, route: route, environment: environment,
                    manager: manager, scratchBase: scratchBase, ledger: scratchLedger,
                    runner: runner, uptime: uptime, stageDeadline: stageDeadline
                )
                switch view {
                case .failure(let reason):
                    return neutralFailure(reason, selection: selection, manager: manager,
                                          package: npmPackage, registry: accepted)
                case .success(let output):
                    viewOutput = output
                }
            }

            // ---- npm --version observation (best-effort; never invalidates metadata) ----
            var npmVersionText: String?
            if !Task.isCancelled, uptime() < stageDeadline {
                npmVersionText = await npmVersion(
                    environment: environment, manager: manager,
                    scratchBase: scratchBase, ledger: scratchLedger, runner: runner
                )
            }

            // ---- Final full ownership + registry re-verification before publication (B02.4) ----
            guard uptime() < stageDeadline, !Task.isCancelled else {
                return neutralFailure(
                    Task.isCancelled ? .probeFailed : .budgetExhausted,
                    selection: selection, manager: manager,
                    package: npmPackage, registry: accepted, npmVersion: npmVersionText
                )
            }
            guard let finalScratch = createScratchRoot(baseURL: scratchBase) else {
                return neutralFailure(.probeFailed, selection: selection, manager: manager,
                                      package: npmPackage, registry: accepted,
                                      npmVersion: npmVersionText)
            }
            let finalOwnership = await verifyOwnership(
                definition: definition, selection: observedSelection, manager: manager,
                baseEnvironment: environment, scratchRoot: finalScratch, runner: runner
            )
            _ = removeScratchRoot(finalScratch, ledger: scratchLedger)

            let finalProof: NpmOwnershipProbe.NpmOwnershipProof
            switch finalOwnership {
            case .refused(let reason), .failed(let reason):
                return neutralFailure(reason, selection: selection, manager: manager,
                                      package: npmPackage, registry: accepted,
                                      npmVersion: npmVersionText)
            case .verified(let finalInstallation, let proof2):
                finalProof = proof2
                // "Final full ownership means re-running prefix/root and anchored proof
                // construction, then comparing full initial/final proof and effective registry."
                guard proof == proof2,
                      finalInstallation.managerRoot == installation.managerRoot,
                      finalInstallation.installationRoot == installation.installationRoot,
                      finalInstallation.packageName == installation.packageName
                else {
                    return neutralFailure(.identityUnverified, selection: selection, manager: manager,
                                          package: npmPackage, registry: accepted,
                                          npmVersion: npmVersionText)
                }
            }

            // Re-read effective registry and require it to still be the accepted public route.
            guard uptime() < stageDeadline else {
                return neutralFailure(.budgetExhausted, selection: selection, manager: manager,
                                      package: npmPackage, registry: accepted,
                                      npmVersion: npmVersionText)
            }
            let finalRoute = await registryRoute(
                packageName: npmPackage, environment: environment, manager: manager,
                scratchBase: scratchBase, ledger: scratchLedger, runner: runner, uptime: uptime,
                stageDeadline: stageDeadline
            )
            switch finalRoute {
            case .refused(let reason):
                return neutralFailure(reason, selection: selection, manager: manager,
                                      package: npmPackage, registry: accepted,
                                      npmVersion: npmVersionText)
            case .basePublic, .scoped:
                break
            }
            // Compare EFFECTIVE route state, not only the base origin: a scope route that changed
            // (or diverged) between the two reads refuses rather than publishing under a stale
            // eligibility decision.
            guard finalRoute == route else {
                return neutralFailure(.identityUnverified, selection: selection, manager: manager,
                                      package: npmPackage, registry: accepted,
                                      npmVersion: npmVersionText)
            }

            // ---- R04 final live gate: AFTER the last external query, immediately BEFORE any
            // cache commit or publication. Full ownership above ran before these final config
            // reads, so re-run the recorded proof's live revalidation here and re-check the
            // stage deadline and cancellation. A changed executable/manifest/root yields
            // identityUnverified, an exhausted budget yields budgetExhausted, and either way
            // NOTHING is cached or published. This narrows the race window; it does not claim to
            // eliminate every unavoidable filesystem race (B02.4, B04.5).
            if Task.isCancelled {
                return neutralFailure(.probeFailed, selection: selection, manager: manager,
                                      package: npmPackage, registry: accepted,
                                      npmVersion: npmVersionText)
            }
            guard uptime() < stageDeadline else {
                return neutralFailure(.budgetExhausted, selection: selection, manager: manager,
                                      package: npmPackage, registry: accepted,
                                      npmVersion: npmVersionText)
            }
            if let reason = finalProof.revalidate() {
                return neutralFailure(mapOwnershipReason(reason), selection: selection,
                                      manager: manager, package: npmPackage, registry: accepted,
                                      npmVersion: npmVersionText)
            }
            // R07: cleanup failure is PROPAGATED, never dismissed. If any owned scratch child this
            // run created could not be removed, the stage is not reported as verified and nothing is
            // cached or published — a neutral failure never implies "no leftovers".
            if scratchLedger.hasFailures {
                return neutralFailure(.probeFailed, selection: selection, manager: manager,
                                      package: npmPackage, registry: accepted,
                                      npmVersion: npmVersionText)
            }

            guard let output = viewOutput else {
                return neutralFailure(.metadataInvalid, selection: selection, manager: manager,
                                      package: npmPackage, registry: accepted,
                                      npmVersion: npmVersionText)
            }

            // ---- Channel policy and comparison ----
            let latest = Version(output.distTagsLatest)
            let status: VersionStatus
            if isPrerelease(output.distTagsLatest) {
                status = .unknown(installed: localVersion, reason: .unsupportedChannel)
            } else {
                status = VersionStatus.evaluate(
                    installed: localVersion, latest: latest, scheme: .semanticVersion
                )
            }

            // Persist validated successful metadata only; never failed/unsupported results, and
            // never a cache hit (an hit already stores the original observation time). A fresh
            // verified comparison (upToDate AND updateAvailable) is reusable metadata.
            let isCacheHit = cachedObservedAt != nil
            if !isCacheHit, status.isVerifiedComparison {
                let observedAt = now()
                _ = cache.save([NpmUpdateMetadataEntry(
                    registryID: definition.id,
                    package: npmPackage,
                    registry: accepted,
                    tag: npmLatestTag,
                    managerEntryPath: manager.entryPath,
                    managerTarget: manager.canonicalTarget,
                    managerFingerprint: fingerprintString(manager.fingerprint),
                    prefix: installation.managerRoot,
                    installationRoot: installation.installationRoot,
                    selectedEntryPath: selection.entry,
                    selectedTarget: selection.target,
                    selectedFingerprint: fingerprintString(finalProof.selection.fingerprint),
                    proofFingerprint: finalProof.fingerprint,
                    contextDigest: contextDigest,
                    name: output.name,
                    version: output.version,
                    distTagsLatest: output.distTagsLatest,
                    observedAt: observedAt
                )])
            }

            // Provenance timing: a Check hit preserves the ORIGINAL observation time; a fresh
            // probe records this run's time. Presentation source (Homebrew versus npm) is carried
            // by the typed npm fields on the result, never by overloading the provenance formula.
            let provenance: UpdateProvenance
            if let originalObservedAt = cachedObservedAt {
                provenance = .cache(observedAt: originalObservedAt)
            } else {
                provenance = .freshProbe(observedAt: now())
            }

            return ToolUpdateResult(
                registryID: definition.id,
                displayName: definition.displayName,
                diagnosticIndex: diagnosticIndex,
                diagnostic: diagnostic,
                localVersion: localVersion.text,
                selectedEntryPath: selection.entry,
                selectedTarget: selection.target,
                selectedKegVersion: nil,
                managerEntryPath: manager.entryPath,
                managerTarget: manager.canonicalTarget,
                managerFingerprint: fingerprintString(manager.fingerprint),
                managerCellar: nil,
                formulaStem: nil,
                fullFormulaName: nil,
                npmPackage: npmPackage,
                npmRegistry: accepted,
                npmTag: npmLatestTag,
                npmVersion: npmVersionText,
                status: status,
                provenance: provenance
            )
        }
    }

    // MARK: - Ownership

    private enum OwnershipStep {
        case verified(VerifiedInstallation, NpmOwnershipProbe.NpmOwnershipProof)
        case failed(UnknownReason)
        case refused(UnknownReason)
    }

    /// Runs the existing ownership verifier for one scratch group, mapping its typed outcome to a
    /// shared unknown reason. The derived scratch environment reaches the verifier's prefix/root
    /// subprocesses; the deadline-clipped runner bounds their nominal timeout.
    private static func verifyOwnership(
        definition: DetectorDefinition,
        selection: ObservedExecutable,
        manager: ObservedExecutable,
        baseEnvironment: ShellEnvironment,
        scratchRoot: NpmScratchRoot,
        runner: UpdateCommandRunner
    ) async -> OwnershipStep {
        let scratchEnvironment = derivedScratchEnvironment(
            baseEnvironment, cacheRoot: scratchRoot.url.path
        )
        let (outcome, proof) = await NpmOwnershipProbe.verifyWithProof(
            definition: definition,
            selection: selection,
            manager: manager,
            environment: scratchEnvironment,
            runner: runner
        )
        switch outcome {
        case .verified(let installation):
            guard let proof else { return .failed(.identityUnverified) }
            return .verified(installation, proof)
        case .unknown(let reason):
            return .failed(mapOwnershipReason(reason))
        }
    }

    // MARK: - Registry / view / version helpers

    /// Runs the registry route resolution for one invocation group and reports eligibility. A
    /// scratch root that cannot be created is a hard stop reported as an opaque `probeFailed`.
    /// A runner refusal produced at the exhausted aggregate stage deadline maps to
    /// `budgetExhausted`, not a generic cancelled/probeFailed (R04).
    private static func registryRoute(
        packageName: String,
        environment: ShellEnvironment,
        manager: ObservedExecutable,
        scratchBase: URL,
        ledger: NpmScratchCleanupLedger,
        runner: UpdateCommandRunner,
        uptime: @escaping @Sendable () -> UInt64,
        stageDeadline: UInt64
    ) async -> RegistryRoute {
        guard let root = createScratchRoot(baseURL: scratchBase) else {
            return .refused(reason: .probeFailed)
        }
        let route = await resolveRegistryRoute(
            packageName: packageName,
            runner: runner,
            environment: npmEnvironment(raw: environment.raw, cacheRoot: root.url.path),
            npmPath: manager.entryPath,
            scratchArguments: npmScratchArguments(cacheRoot: root.url.path),
            aggregateDeadlineExhausted: uptime() >= stageDeadline,
            taskCancelled: Task.isCancelled
        )
        // R07: release the OWNED anchored child and record any failure rather than discard it.
        _ = removeScratchRoot(root, ledger: ledger)
        return route
    }

    private enum MetadataOutcome {
        case success(NpmViewOutput)
        case failure(UnknownReason)
    }

    private static func metadataView(
        packageName: String,
        route: RegistryRoute,
        environment: ShellEnvironment,
        manager: ObservedExecutable,
        scratchBase: URL,
        ledger: NpmScratchCleanupLedger,
        runner: UpdateCommandRunner,
        uptime: @Sendable () -> UInt64,
        stageDeadline: UInt64
    ) async -> MetadataOutcome {
        guard let root = createScratchRoot(baseURL: scratchBase) else {
            return .failure(.probeFailed)
        }
        let args = metadataArguments(
            packageName: packageName, route: route,
            scratchArguments: npmScratchArguments(cacheRoot: root.url.path)
        )
        let outcome = await runner.run(
            executablePath: manager.entryPath,
            arguments: args,
            environment: npmEnvironment(raw: environment.raw, cacheRoot: root.url.path),
            timeout: npmMetadataTimeout
        )
        let result: MetadataOutcome
        switch outcome {
        case .success(let data):
            guard let output = parseNpmViewOutput(data, expectedPackage: packageName) else {
                result = .failure(.metadataInvalid)
                break
            }
            result = .success(output)
        case .failure(let failure):
            switch failure {
            case .timedOut: result = .failure(.queryTimedOut)
            case .outputLimitExceeded: result = .failure(.metadataInvalid)
            default:
                result = .failure(configFailureReason(
                    failure, aggregateDeadlineExhausted: uptime() >= stageDeadline,
                    taskCancelled: Task.isCancelled
                ))
            }
        }
        // R07: the owned child is released after the query, with failures recorded.
        _ = removeScratchRoot(root, ledger: ledger)
        return result
    }

    /// Best-effort `npm --version` observation. A malformed or unavailable version never
    /// invalidates an otherwise strict metadata result; it is simply reported as nil provenance.
    private static func npmVersion(
        environment: ShellEnvironment,
        manager: ObservedExecutable,
        scratchBase: URL,
        ledger: NpmScratchCleanupLedger,
        runner: UpdateCommandRunner
    ) async -> String? {
        guard let root = createScratchRoot(baseURL: scratchBase) else { return nil }
        let outcome = await runner.run(
            executablePath: manager.entryPath,
            arguments: npmScratchArguments(cacheRoot: root.url.path) + ["--version"],
            environment: npmEnvironment(raw: environment.raw, cacheRoot: root.url.path),
            timeout: npmVersionTimeout
        )
        let text: String?
        if case .success(let data) = outcome,
           let value = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty
        {
            text = value
        } else {
            text = nil
        }
        // R07: even a best-effort query releases only its own anchored child, and records failure.
        _ = removeScratchRoot(root, ledger: ledger)
        return text
    }

    // MARK: - Cache context digest

    /// The stable npm cache context digest (B04.2): namespace `agent-lens-npm-context-v1`, the
    /// normalized accepted registry, the verified package, the `latest` tag, the pre-overlay
    /// captured environment with cache/log/notifier overrides and `TMPDIR` removed (sorted,
    /// length-framed key/value pairs), and the standardized current directory. Only the digest is
    /// persisted; the volatile per-invocation scratch spelling and TMPDIR never affect it, so two
    /// consecutive Checks with distinct scratch roots hit the same record.
    private static func npmContextDigest(
        environment: ShellEnvironment,
        currentDirectory: String,
        registry: String,
        package: String
    ) -> String {
        func frame(_ text: String) -> String { "\(text.utf8.count):\(text)" }
        let workingDirectory = URL(
            fileURLWithPath: currentDirectory, isDirectory: true
        ).standardizedFileURL.path
        let stable = environment.raw
            .filter { !npmVolatileEnvironmentKeys.contains($0.key.lowercased()) }
        let pairs = stable.keys.sorted().map { frame($0) + frame(stable[$0] ?? "") }.joined()
        let material = frame("agent-lens-npm-context-v1")
            + frame("registry") + frame(registry)
            + frame("package") + frame(package)
            + frame("tag") + frame(npmLatestTag)
            + frame("environment-count") + frame(String(stable.count))
            + pairs
            + frame("current-directory") + frame(workingDirectory)
        return UpdateMetadataKey.stableDigest(material)
    }

    // MARK: - Reason mapping

    /// Maps the ownership verifier's internal reason to the shared `UnknownReason` vocabulary.
    /// Cancellation is neutral, a changed proof/identity is `identityUnverified`, and a manager
    /// that could not be reached is `managerUnavailable`; every other ownership failure stays an
    /// opaque `probeFailed`. None of these ever become a verified claim.
    static func mapOwnershipReason(_ reason: InstallationOwnershipReason) -> UnknownReason {
        switch reason {
        case .cancelled: .probeFailed
        case .managerUnavailable: .managerUnavailable
        case .selectedExecutableChanged, .managerChanged, .proofChanged,
             .managerEntryMismatch, .manifestExecutableMismatch, .managerRootMismatch,
             .unsupportedInstallationLayout, .packagePathUnsafe, .executableOutsidePackage:
            .identityUnverified
        case .noDeclaredPackage, .unsupportedSource: .unsupportedSource
        case .noMatchingPackage, .ambiguousOwnership: .identityUnverified
        default: .probeFailed
        }
    }
}
