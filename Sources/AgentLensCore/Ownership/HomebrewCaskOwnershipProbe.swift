// HomebrewCaskOwnershipProbe — read-only Homebrew cask ownership proof (M13-A).
//
// Exactly four manager queries are possible, in order: `brew --prefix`, `brew --caskroom`, one
// named `brew info --json=v2 --cask <declared names…>` (at most four names), and one named
// `brew list --verbose --cask <full_token>` after `info` produced exactly one installed record.
// `--installed` is never added, and Caskroom is never derived from the prefix by string-trimming.
//
// Ownership never depends on a cask version grammar, `auto_updates`, pins, or deprecated/disabled
// state. `.metadata/**` is manager bookkeeping, never membership proof. Every manager path is
// retained in the spelling the manager reported and re-observed through that spelling; a canonical
// result that differs from the pinned directory identity is a typed refusal, never a silent
// retarget. Token and version directories are compared by exact path components, so a symlink to
// a sibling tree inside the Caskroom cannot borrow another cask's proof.

import Darwin
import Foundation

struct HomebrewCaskOwnershipProbe {

    /// More declared cask names than this are refused before any process is constructed.
    static let maximumDeclaredCasks = 4
    /// Bounded listing contract: at most 4096 physical lines and 1 MiB of manager output.
    static let maximumListingLines = 4096
    static let maximumListingBytes = 1024 * 1024

    private enum QueryOutcome {
        case success(Data)
        case failure(CommandFailure)
    }

    private enum InstalledValue {
        case missing
        case null
        case string(String)
        case malformed
    }

    private struct CaskRecord {
        let token: String
        let fullToken: String
        let installed: InstalledValue
        let oldTokens: [String]
    }

    /// The manager's reported spelling and the directory identity observed through it. All later
    /// observations use `reportedPath`, never a stored canonical spelling alone.
    private struct BoundRoot {
        let reportedPath: String
        let identity: DirectoryIdentity

        static func observe(_ reportedPath: String) -> BoundRoot? {
            guard let identity = FileIdentityObserver.observeDirectory(path: reportedPath) else {
                return nil
            }
            return BoundRoot(reportedPath: reportedPath, identity: identity)
        }

        var isCurrent: Bool {
            guard let current = FileIdentityObserver.observeDirectory(path: reportedPath) else {
                return false
            }
            return current == identity
        }
    }

    /// One directory bound to an exact final component below its parent. `path` is the lexical
    /// lookup path; `identity.canonicalPath` must be exactly `parent.canonicalPath/<component>`.
    private struct BoundDirectory {
        let path: String
        let component: String
        let identity: DirectoryIdentity

        func isCurrent(parent: DirectoryIdentity) -> Bool {
            guard let current = FileIdentityObserver.observeDirectory(path: path),
                  current == identity,
                  FileIdentityObserver.isExactDescendant(
                    current.canonicalPath, of: parent.canonicalPath, components: [component]
                  )
            else { return false }
            return true
        }
    }

    private enum SelectionLayout {
        /// The selected canonical target decomposes under the Caskroom. Token/version identities
        /// are pinned before `info`.
        case staged(SelectedCask, StagedDirectories)
        /// The selected target is outside the Caskroom; only a listed staged app link may prove
        /// it. Potential declared token directories are pinned before `info`.
        case outside([TokenDirectoryPin])
    }

    /// Token and version directories already proven by the selection's own decomposition.
    private struct StagedDirectories {
        let token: BoundDirectory
        let version: BoundDirectory
    }

    /// State of one potential declared token directory, observed before `info`.
    private enum TokenDirectoryPinState: Equatable {
        case absent
        case invalid
        case bound(DirectoryIdentity)
    }

    private struct TokenDirectoryPin {
        let component: String
        let state: TokenDirectoryPinState
    }

    private enum Membership {
        /// Binary/command_wrapper: the selected canonical target equals a listed staged file.
        case stagedFile(path: String)
        /// Moved app: a listed staged app-directory link and the selection inside that bundle.
        case movedApp(AppLinkBinding)
    }

    /// A staged symlink to an actual `.app` directory. The link and target names may differ
    /// (`Moved#post_move`), but the selection must be component-bounded inside the bundle.
    private struct AppLinkBinding: Equatable {
        let linkPath: String
        let appDirectory: String
    }

    private struct CaskProof {
        let manager: ObservedExecutable
        let selection: ObservedExecutable
        let prefix: BoundRoot
        let caskroom: BoundRoot
        let tokenDirectory: BoundDirectory
        let versionDirectory: BoundDirectory
        let membership: Membership

        func revalidate() -> InstallationOwnershipReason? {
            if let reason = HomebrewCaskOwnershipProbe.revalidateBindings(
                selection: selection,
                manager: manager,
                prefix: prefix,
                caskroom: caskroom
            ) {
                return reason
            }
            guard tokenDirectory.isCurrent(parent: caskroom.identity),
                  versionDirectory.isCurrent(parent: tokenDirectory.identity)
            else {
                return .proofChanged
            }
            switch membership {
            case .stagedFile(let path):
                guard HomebrewCaskOwnershipProbe.componentPathsEqual(
                    path, selection.canonicalTarget
                ), HomebrewCaskOwnershipProbe.isRegularStagedFile(path) else {
                    return .proofChanged
                }
            case .movedApp(let binding):
                guard let current = HomebrewCaskOwnershipProbe.appLinkBinding(
                    linkPath: binding.linkPath,
                    selectionTarget: selection.canonicalTarget
                ), current == binding else {
                    return .proofChanged
                }
            }
            return nil
        }
    }

    /// The single declaration/cap rule used by both the verifier routing boundary and the probe.
    /// Definitions already reject duplicate packages; the names are still deduplicated so this
    /// helper is total for hand-built values.
    enum DeclaredCaskPreflight {
        case names([String])
        case refused(InstallationOwnershipReason)
    }

    static func declaredCaskPreflight(
        definition: DetectorDefinition
    ) -> DeclaredCaskPreflight {
        var declaredNames: [String] = []
        for package in definition.packages where package.manager == .homebrewCask {
            if !declaredNames.contains(package.name) {
                declaredNames.append(package.name)
            }
        }
        guard !declaredNames.isEmpty else { return .refused(.noDeclaredPackage) }
        guard declaredNames.count <= maximumDeclaredCasks else {
            return .refused(.tooManyDeclaredCasks)
        }
        return .names(declaredNames)
    }

    static func verify(
        definition: DetectorDefinition,
        selection: ObservedExecutable,
        manager: ObservedExecutable,
        environment: ShellEnvironment,
        runner: UpdateCommandRunner
    ) async -> InstallationOwnershipOutcome {
        let declaredNames: [String]
        switch declaredCaskPreflight(definition: definition) {
        case .names(let names):
            declaredNames = names
        case .refused(let reason):
            return .unknown(reason)
        }

        if let reason = revalidateIdentity(selection: selection, manager: manager) {
            return .unknown(reason)
        }

        // 1. The manager's prefix. It is reported separately and never used to derive Caskroom.
        let prefixText: String
        switch await query(
            manager: manager,
            arguments: ["--prefix"],
            environment: environment,
            runner: runner
        ) {
        case .failure(let failure):
            return .unknown(reason(for: failure))
        case .success(let data):
            guard let parsed = ManagerOutputParser.singleAbsolutePath(data) else {
                return .unknown(.invalidManagerOutput)
            }
            prefixText = parsed
        }
        if let reason = revalidateIdentity(selection: selection, manager: manager) {
            return .unknown(reason)
        }
        guard let prefix = BoundRoot.observe(prefixText) else {
            return .unknown(.unsupportedInstallationLayout)
        }
        if let reason = revalidateBindings(
            selection: selection, manager: manager, prefix: prefix
        ) {
            return .unknown(reason)
        }

        // 2. The manager's Caskroom. `HOMEBREW_CASKROOM` may differ from the prefix.
        let caskroomText: String
        switch await query(
            manager: manager,
            arguments: ["--caskroom"],
            environment: environment,
            runner: runner
        ) {
        case .failure(let failure):
            return .unknown(reason(for: failure))
        case .success(let data):
            guard let parsed = ManagerOutputParser.singleAbsolutePath(data) else {
                return .unknown(.invalidManagerOutput)
            }
            caskroomText = parsed
        }
        if let reason = revalidateBindings(
            selection: selection, manager: manager, prefix: prefix
        ) {
            return .unknown(reason)
        }
        guard let caskroom = BoundRoot.observe(caskroomText) else {
            return .unknown(.unsupportedInstallationLayout)
        }
        if let reason = revalidateBindings(
            selection: selection, manager: manager, prefix: prefix, caskroom: caskroom
        ) {
            return .unknown(reason)
        }

        // 3. Decompose the selected canonical target by path components. Failure to live under
        // the Caskroom is the moved-app route; a shallow, traversal, or metadata-containing
        // in-Caskroom layout is refused before any record query.
        let layout: SelectionLayout
        switch HomebrewCaskTargetParser.parse(
            selectedTarget: selection.canonicalTarget,
            caskroom: caskroom.identity.canonicalPath
        ) {
        case .success(let staged):
            guard let directories = observeStagedDirectories(
                caskroom: caskroom.identity,
                token: staged.token,
                version: staged.versionDirectory
            ) else {
                return .unknown(.unsupportedInstallationLayout)
            }
            layout = .staged(staged, directories)
        case .failure(.managerMismatch):
            layout = .outside(pinDeclaredTokenDirectories(
                declaredNames: declaredNames, caskroom: caskroom.identity
            ))
        case .failure(.unverified):
            return .unknown(.unsupportedInstallationLayout)
        }
        if let reason = revalidateLayout(
            layout,
            selection: selection,
            manager: manager,
            prefix: prefix,
            caskroom: caskroom
        ) {
            return .unknown(reason)
        }

        // 4. One metadata query for every declared cask name.
        let infoData: Data
        switch await query(
            manager: manager,
            arguments: ["info", "--json=v2", "--cask"] + declaredNames,
            environment: environment,
            runner: runner
        ) {
        case .failure(let failure):
            return .unknown(reason(for: failure))
        case .success(let data):
            infoData = data
        }
        if let reason = revalidateBindings(
            selection: selection, manager: manager, prefix: prefix, caskroom: caskroom
        ) {
            return .unknown(reason)
        }
        guard let records = parseInfo(infoData) else {
            return .unknown(.invalidManagerOutput)
        }
        guard !records.isEmpty else { return .unknown(.noMatchingPackage) }

        // A declaration that matches only a previous token is refused, never silently retargeted.
        let renamedOnly = declaredNames.contains { name in
            !records.contains { declarationMatches(name, $0) }
                && records.contains { $0.oldTokens.contains(name) }
        }
        guard !renamedOnly else { return .unknown(.caskTokenRenamed) }

        var candidates = records.filter { record in
            declaredNames.contains { declarationMatches($0, record) }
        }
        guard !candidates.isEmpty else { return .unknown(.caskRecordMismatch) }
        if case .staged(let staged, _) = layout {
            candidates = candidates.filter { $0.token == staged.token }
            guard !candidates.isEmpty else { return .unknown(.caskRecordMismatch) }
        }
        guard candidates.count == 1, let record = candidates.first else {
            return .unknown(.ambiguousOwnership)
        }

        // 5. The manager's own install record must name the staged version directory. The version
        // text is opaque: it is compared for equality and never parsed. `.metadata` is never a
        // package version, token, or artifact.
        let installedVersion: String
        switch record.installed {
        case .null:
            return .unknown(.packageNotInstalled)
        case .missing, .malformed:
            return .unknown(.invalidManagerOutput)
        case .string(let value):
            installedVersion = value
        }
        guard isCleanPathComponent(record.token),
              isCleanPathComponent(installedVersion),
              installedVersion != ".metadata"
        else {
            return .unknown(.invalidManagerOutput)
        }

        let tokenDirectory: BoundDirectory
        let versionDirectory: BoundDirectory
        switch layout {
        case .staged(let staged, let directories):
            guard staged.versionDirectory == installedVersion else {
                return .unknown(.selectedCaskNotInstalled)
            }
            guard directories.token.isCurrent(parent: caskroom.identity),
                  directories.version.isCurrent(parent: directories.token.identity)
            else {
                return .unknown(.proofChanged)
            }
            tokenDirectory = directories.token
            versionDirectory = directories.version
        case .outside(let pins):
            guard let pin = pins.first(where: { $0.component == record.token }) else {
                return .unknown(.unsupportedInstallationLayout)
            }
            switch resolveMovedTokenDirectory(
                caskroom: caskroom.identity, pin: pin
            ) {
            case .refused(let reason):
                return .unknown(reason)
            case .directory(let resolved):
                tokenDirectory = resolved
            }
            // Every other potential declared token directory must be unchanged too.
            for other in pins where other.component != pin.component {
                guard pinState(
                    component: other.component, caskroom: caskroom.identity
                ) == other.state else {
                    return .unknown(.proofChanged)
                }
            }
            guard let resolvedVersion = boundDirectory(
                parent: tokenDirectory.identity, component: installedVersion
            ) else {
                return .unknown(.unsupportedInstallationLayout)
            }
            versionDirectory = resolvedVersion
        }
        if let reason = revalidateBindings(
            selection: selection, manager: manager, prefix: prefix, caskroom: caskroom
        ) {
            return .unknown(reason)
        }

        // 6. One listing query for the canonical full token.
        let listData: Data
        switch await query(
            manager: manager,
            arguments: ["list", "--verbose", "--cask", record.fullToken],
            environment: environment,
            runner: runner
        ) {
        case .failure(let failure):
            return .unknown(reason(for: failure))
        case .success(let data):
            listData = data
        }
        if let reason = revalidateBindings(
            selection: selection, manager: manager, prefix: prefix, caskroom: caskroom
        ) {
            return .unknown(reason)
        }
        guard tokenDirectory.isCurrent(parent: caskroom.identity),
              versionDirectory.isCurrent(parent: tokenDirectory.identity)
        else {
            return .unknown(.proofChanged)
        }
        if case .outside(let pins) = layout {
            for pin in pins {
                guard pinState(
                    component: pin.component, caskroom: caskroom.identity
                ) == pin.state else {
                    return .unknown(.proofChanged)
                }
            }
        }

        // 7. Bounded listing parse and membership proof.
        guard let lines = parseListing(
            listData,
            caskroom: caskroom.identity,
            reportedCaskroomPath: caskroom.reportedPath
        ) else {
            return .unknown(.invalidManagerOutput)
        }
        let stagedLines = stagedLines(
            lines, caskroom: caskroom.identity, token: record.token,
            version: installedVersion
        )
        let membership: Membership
        switch layout {
        case .staged:
            guard let exact = stagedLines.first(where: {
                componentPathsEqual($0, selection.canonicalTarget)
            }), isRegularStagedFile(exact) else {
                return .unknown(
                    stagedLines.isEmpty ? .caskArtifactUnlinked : .selectedCaskNotConfirmed
                )
            }
            membership = .stagedFile(path: exact)
        case .outside:
            var match: AppLinkBinding?
            for line in stagedLines {
                if let binding = appLinkBinding(
                    linkPath: line, selectionTarget: selection.canonicalTarget
                ) {
                    match = binding
                    break
                }
            }
            guard let match else {
                return .unknown(
                    stagedLines.isEmpty ? .caskArtifactUnlinked : .selectedCaskNotConfirmed
                )
            }
            membership = .movedApp(match)
        }

        // 8. Local proof revalidation before publication.
        let proof = CaskProof(
            manager: manager,
            selection: selection,
            prefix: prefix,
            caskroom: caskroom,
            tokenDirectory: tokenDirectory,
            versionDirectory: versionDirectory,
            membership: membership
        )
        if let failure = proof.revalidate() { return .unknown(failure) }

        let installation = VerifiedInstallation(
            manager: .homebrewCask,
            packageName: record.fullToken,
            managerEntryPath: manager.entryPath,
            managerTarget: manager.canonicalTarget,
            managerFingerprint: manager.fingerprint,
            managerRoot: prefix.identity.canonicalPath,
            installationRoot: tokenDirectory.identity.canonicalPath,
            selection: InstallationSelectionIdentity(
                entryPath: selection.entryPath,
                canonicalTarget: selection.canonicalTarget,
                fingerprint: selection.fingerprint
            )
        )
        return .verified(installation)
    }

    // MARK: Record identity

    /// The declaration rules are deliberately narrow: a bare declaration may match either the
    /// canonical full token or a token that is itself the full token; a tap declaration must equal
    /// `full_token` exactly. `old_tokens` never satisfies this rule.
    private static func declarationMatches(_ declared: String, _ record: CaskRecord) -> Bool {
        if declared == record.fullToken { return true }
        return declared == record.token && record.fullToken == record.token
    }

    /// Validates the identity metadata in one manager record before any listing query. A record
    /// that claims a contradictory `token`/`full_token` pair poisons the whole response; it is
    /// never dropped so that a different record can be selected around it.
    private static func parseInfo(_ data: Data) -> [CaskRecord]? {
        guard let text = strictUTF8Text(data),
              let json = try? JSONSerialization.jsonObject(
                with: Data(text.utf8), options: []
              ),
              let root = json as? [String: Any],
              let casks = root["casks"] as? [Any]
        else { return nil }

        var records: [CaskRecord] = []
        records.reserveCapacity(casks.count)
        for element in casks {
            guard let object = element as? [String: Any],
                  let token = object["token"] as? String,
                  let fullToken = object["full_token"] as? String,
                  isStructurallyValidCask(token: token, fullToken: fullToken)
            else { return nil }

            let oldTokens: [String]
            if let rawOldTokens = object["old_tokens"] {
                guard let entries = rawOldTokens as? [Any] else { return nil }
                var strings: [String] = []
                strings.reserveCapacity(entries.count)
                for entry in entries {
                    guard let value = entry as? String else { return nil }
                    strings.append(value)
                }
                oldTokens = strings
            } else {
                oldTokens = []
            }

            let installed: InstalledValue
            if !object.keys.contains("installed") {
                installed = .missing
            } else if object["installed"] is NSNull {
                installed = .null
            } else if let value = object["installed"] as? String {
                installed = .string(value)
            } else {
                installed = .malformed
            }
            records.append(CaskRecord(
                token: token,
                fullToken: fullToken,
                installed: installed,
                oldTokens: oldTokens
            ))
        }
        return records
    }

    private static func isStructurallyValidCask(token: String, fullToken: String) -> Bool {
        guard isCleanPathComponent(token),
              token != ".metadata",
              DeclaredPackage.validationFailure(
                manager: .homebrewCask, name: token
              ) == nil,
              DeclaredPackage.validationFailure(
                manager: .homebrewCask, name: fullToken
              ) == nil
        else { return false }
        let components = fullToken.split(separator: "/", omittingEmptySubsequences: false)
        guard let last = components.last else { return false }
        return String(last) == token
    }

    // MARK: Listing

    /// Validates the bounded listing in one pass. Every physical line must be an absolute path
    /// strictly below the reported Caskroom (or its canonical spelling); a malformed line
    /// invalidates the whole listing even when a matching line was already seen. A single terminal
    /// line ending is allowed, and the 4096-line cap counts physical lines.
    private static func parseListing(
        _ data: Data,
        caskroom: DirectoryIdentity,
        reportedCaskroomPath: String
    ) -> [String]? {
        guard !data.isEmpty,
              data.count <= maximumListingBytes,
              strictUTF8Text(data) != nil
        else { return nil }

        guard let reportedRoot = HomebrewCaskTargetParser.cleanedAbsolutePath(
            reportedCaskroomPath
        ), let canonicalRoot = HomebrewCaskTargetParser.cleanedAbsolutePath(
            caskroom.canonicalPath
        ) else { return nil }
        let reportedComponents = HomebrewCaskTargetParser.components(of: reportedRoot)
        let canonicalComponents = HomebrewCaskTargetParser.components(of: canonicalRoot)
        guard !reportedComponents.isEmpty, !canonicalComponents.isEmpty else { return nil }
        // Only the exact reported spelling and the exact canonical spelling are accepted. Any
        // other alias or sibling is malformed manager output, not proof.
        let roots: [(listed: [String], canonical: [String])] =
            reportedComponents == canonicalComponents
            ? [(reportedComponents, canonicalComponents)]
            : [(reportedComponents, canonicalComponents),
               (canonicalComponents, canonicalComponents)]

        var bytes = Array(data)
        if bytes.last == 0x0A { bytes.removeLast() }
        let rawLines = bytes.split(separator: 0x0A, omittingEmptySubsequences: false)
        guard rawLines.count <= maximumListingLines else { return nil }

        var paths: [String] = []
        paths.reserveCapacity(rawLines.count)
        for rawLine in rawLines {
            var line = rawLine
            if line.last == 0x0D { line = line.dropLast() }
            guard !line.isEmpty,
                  let text = String(bytes: line, encoding: .utf8),
                  let cleaned = HomebrewCaskTargetParser.cleanedAbsolutePath(text)
            else { return nil }
            let lineComponents = HomebrewCaskTargetParser.components(of: cleaned)
            var mapped: String?
            for root in roots {
                guard lineComponents.count > root.listed.count,
                      Array(lineComponents.prefix(root.listed.count)) == root.listed
                else { continue }
                let suffix = lineComponents.dropFirst(root.listed.count)
                mapped = "/" + (root.canonical + suffix).joined(separator: "/")
                break
            }
            guard let mapped else { return nil }
            paths.append(mapped)
        }
        return paths
    }

    /// The non-metadata lines that sit under `<caskroom>/<token>/<installed>/`. `.metadata` is
    /// manager bookkeeping at any depth below the Caskroom and never proves membership.
    private static func stagedLines(
        _ lines: [String],
        caskroom: DirectoryIdentity,
        token: String,
        version: String
    ) -> [String] {
        let rootComponents = HomebrewCaskTargetParser.components(of: caskroom.canonicalPath)
        return lines.filter { line in
            let components = HomebrewCaskTargetParser.components(of: line)
            guard components.count > rootComponents.count,
                  Array(components.prefix(rootComponents.count)) == rootComponents
            else { return false }
            let relative = Array(components.dropFirst(rootComponents.count))
            guard !relative.contains(".metadata"),
                  relative.count > 2,
                  relative[0] == token,
                  relative[1] == version
            else { return false }
            return true
        }
    }

    // MARK: Directory bindings

    private static func appendedPath(_ base: String, _ component: String) -> String {
        URL(fileURLWithPath: base, isDirectory: true)
            .appendingPathComponent(component, isDirectory: true)
            .path
    }

    /// Binds `<parent>/<component>` to the exact canonical component spelling. A symlink to a
    /// sibling tree inside the Caskroom canonicalizes to a different final component and fails.
    private static func boundDirectory(
        parent: DirectoryIdentity,
        component: String
    ) -> BoundDirectory? {
        let path = appendedPath(parent.canonicalPath, component)
        guard let identity = FileIdentityObserver.observeDirectory(path: path),
              FileIdentityObserver.isExactDescendant(
                identity.canonicalPath, of: parent.canonicalPath, components: [component]
              )
        else { return nil }
        return BoundDirectory(path: path, component: component, identity: identity)
    }

    private static func observeStagedDirectories(
        caskroom: DirectoryIdentity,
        token: String,
        version: String
    ) -> StagedDirectories? {
        guard let tokenDirectory = boundDirectory(parent: caskroom, component: token),
              let versionDirectory = boundDirectory(
                parent: tokenDirectory.identity, component: version
              )
        else { return nil }
        return StagedDirectories(token: tokenDirectory, version: versionDirectory)
    }

    /// The moved-app route has no selected token/version path, so every potential declared token
    /// directory is pinned before `info`. A pre-existing symlinked sibling is recorded as invalid.
    private static func pinDeclaredTokenDirectories(
        declaredNames: [String],
        caskroom: DirectoryIdentity
    ) -> [TokenDirectoryPin] {
        var components: [String] = []
        for name in declaredNames {
            let pieces = name.split(separator: "/", omittingEmptySubsequences: false)
            guard let last = pieces.last else { continue }
            let component = String(last)
            if !components.contains(component) {
                components.append(component)
            }
        }
        return components.map { component in
            TokenDirectoryPin(
                component: component,
                state: pinState(component: component, caskroom: caskroom)
            )
        }
    }

    private static func pinState(
        component: String,
        caskroom: DirectoryIdentity
    ) -> TokenDirectoryPinState {
        let path = appendedPath(caskroom.canonicalPath, component)
        guard let identity = FileIdentityObserver.observeDirectory(path: path) else {
            return .absent
        }
        guard FileIdentityObserver.isExactDescendant(
            identity.canonicalPath, of: caskroom.canonicalPath, components: [component]
        ) else {
            return .invalid
        }
        return .bound(identity)
    }

    /// Resolves the selected declared token directory for the moved-app route. Missing directories
    /// keep the existing unsupported-layout refusal; a known directory that changed or now lives
    /// through a sibling symlink is a proof change.
    private enum TokenDirectoryResolution {
        case directory(BoundDirectory)
        case refused(InstallationOwnershipReason)
    }

    private static func resolveMovedTokenDirectory(
        caskroom: DirectoryIdentity,
        pin: TokenDirectoryPin
    ) -> TokenDirectoryResolution {
        let path = appendedPath(caskroom.canonicalPath, pin.component)
        let observed = FileIdentityObserver.observeDirectory(path: path)
        switch pin.state {
        case .invalid:
            return .refused(.unsupportedInstallationLayout)
        case .absent:
            return .refused(observed == nil ? .unsupportedInstallationLayout : .proofChanged)
        case .bound(let expected):
            guard let observed else { return .refused(.unsupportedInstallationLayout) }
            guard observed == expected,
                  FileIdentityObserver.isExactDescendant(
                    observed.canonicalPath, of: caskroom.canonicalPath,
                    components: [pin.component]
                  )
            else { return .refused(.proofChanged) }
            return .directory(BoundDirectory(
                path: path, component: pin.component, identity: observed
            ))
        }
    }

    private static func revalidateLayout(
        _ layout: SelectionLayout,
        selection: ObservedExecutable,
        manager: ObservedExecutable,
        prefix: BoundRoot,
        caskroom: BoundRoot
    ) -> InstallationOwnershipReason? {
        switch layout {
        case .staged(_, let directories):
            return revalidateBindings(
                selection: selection,
                manager: manager,
                prefix: prefix,
                caskroom: caskroom,
                staged: directories
            )
        case .outside(let pins):
            return revalidateBindings(
                selection: selection,
                manager: manager,
                prefix: prefix,
                caskroom: caskroom,
                tokenPins: pins
            )
        }
    }

    // MARK: Identity helpers

    private static func componentPathsEqual(_ lhs: String, _ rhs: String) -> Bool {
        guard let left = HomebrewCaskTargetParser.cleanedAbsolutePath(lhs),
              let right = HomebrewCaskTargetParser.cleanedAbsolutePath(rhs)
        else { return false }
        return HomebrewCaskTargetParser.components(of: left)
            == HomebrewCaskTargetParser.components(of: right)
    }

    /// `find` lists a `Binary`/`CommandWrapper` artifact as the staged regular file itself.
    private static func isRegularStagedFile(_ path: String) -> Bool {
        guard let mode = linkStatusMode(path) else { return false }
        return (mode & mode_t(S_IFMT)) == mode_t(S_IFREG)
    }

    private static func isSymlink(_ path: String) -> Bool {
        guard let mode = linkStatusMode(path) else { return false }
        return (mode & mode_t(S_IFMT)) == mode_t(S_IFLNK)
    }

    private static func linkStatusMode(_ path: String) -> mode_t? {
        guard path.hasPrefix("/"), !path.utf8.contains(0) else { return nil }
        var info = stat()
        let status = path.withCString { pointer in lstat(pointer, &info) }
        return status == 0 ? info.st_mode : nil
    }

    /// Matches the spelling rule used by `FileIdentityObserver`: Foundation's canonical spelling,
    /// not the POSIX `/private/var` alias.
    private static func resolvedPath(_ path: String) -> String {
        URL(fileURLWithPath: path)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
    }

    /// A moved app is proved only by a staged symlink to an actual `.app` DIRECTORY and a
    /// component-bounded selection inside that bundle. The link and target names may differ
    /// (`Moved#post_move` links target to source). A link to a plain file or a broad directory is
    /// never a moved-app proof. This exact predicate runs again before publication.
    private static func appLinkBinding(
        linkPath: String,
        selectionTarget: String
    ) -> AppLinkBinding? {
        guard isSymlink(linkPath),
              isAppBundleName(lastComponent(of: linkPath)),
              let target = FileIdentityObserver.observeDirectory(path: resolvedPath(linkPath)),
              isAppBundleName(lastComponent(of: target.canonicalPath)),
              componentPathsEqual(selectionTarget, target.canonicalPath)
                || FileIdentityObserver.isStrictDescendant(
                    selectionTarget, of: target.canonicalPath
                )
        else { return nil }
        return AppLinkBinding(linkPath: linkPath, appDirectory: target.canonicalPath)
    }

    private static func isAppBundleName(_ name: String) -> Bool {
        name.lowercased().hasSuffix(".app")
    }

    private static func lastComponent(of path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    private static func isCleanPathComponent(_ value: String) -> Bool {
        !value.isEmpty
            && value != "."
            && value != ".."
            && value != ".metadata"
            && !value.contains("/")
            && !value.utf8.contains(0)
    }

    private static func revalidateIdentity(
        selection: ObservedExecutable,
        manager: ObservedExecutable
    ) -> InstallationOwnershipReason? {
        guard let currentSelection = FileIdentityObserver.observeExecutable(
            entryPath: selection.entryPath
        ), currentSelection == selection else {
            return .selectedExecutableChanged
        }
        guard let currentManager = FileIdentityObserver.observeExecutable(
            entryPath: manager.entryPath
        ), currentManager == manager else {
            return .managerChanged
        }
        return nil
    }

    private static func revalidateBindings(
        selection: ObservedExecutable,
        manager: ObservedExecutable,
        prefix: BoundRoot? = nil,
        caskroom: BoundRoot? = nil,
        staged: StagedDirectories? = nil,
        tokenPins: [TokenDirectoryPin] = []
    ) -> InstallationOwnershipReason? {
        if let reason = revalidateIdentity(selection: selection, manager: manager) {
            return reason
        }
        if let prefix, !prefix.isCurrent { return .proofChanged }
        if let caskroom, !caskroom.isCurrent { return .proofChanged }
        if let staged, let caskroom {
            guard staged.token.isCurrent(parent: caskroom.identity),
                  staged.version.isCurrent(parent: staged.token.identity)
            else {
                return .proofChanged
            }
        }
        if !tokenPins.isEmpty, let caskroom {
            for pin in tokenPins {
                guard pinState(
                    component: pin.component, caskroom: caskroom.identity
                ) == pin.state else {
                    return .proofChanged
                }
            }
        }
        return nil
    }

    private static func reason(for failure: CommandFailure) -> InstallationOwnershipReason {
        failure == .cancelled ? .cancelled : .managerQueryFailed
    }

    private static func query(
        manager: ObservedExecutable,
        arguments: [String],
        environment: ShellEnvironment,
        runner: UpdateCommandRunner
    ) async -> QueryOutcome {
        if Task.isCancelled { return .failure(.cancelled) }
        let outcome = await runner.run(
            executablePath: manager.entryPath,
            arguments: arguments,
            environment: HomebrewUpdateProbe.diagnosticEnvironment(from: environment),
            timeout: HomebrewUpdateProbe.queryTimeout
        )
        if Task.isCancelled { return .failure(.cancelled) }
        switch outcome {
        case .success(let data):
            return .success(data)
        case .failure(let failure):
            return .failure(failure)
        }
    }

    /// Homebrew emits UTF-8. Reject a leading BOM, any NUL byte, and any byte sequence that is not
    /// valid UTF-8; the caller parses the original validated bytes.
    private static func strictUTF8Text(_ data: Data) -> String? {
        let byteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]
        if data.count >= 3, Array(data.prefix(3)) == byteOrderMark { return nil }
        if data.contains(0x00) { return nil }
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        guard Data(text.utf8) == data else { return nil }
        return text
    }
}
