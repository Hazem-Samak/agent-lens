// HomebrewOwnershipProbe — read-only Homebrew formula ownership proof (M9-B).
//
// Exactly three manager queries are possible: `brew --cellar`, a named
// `brew info --json=v2 --formula <full-name>`, and
// `brew list --verbose --formula <verified-full-name>`. `--installed` is never added: real
// Homebrew ignores the supplied name with that flag and returns every installed formula.
// Ownership never depends on semver support, upstream `stable`, or update availability.

import Foundation

struct HomebrewOwnershipProbe {

    private enum QueryOutcome {
        case success(Data)
        case failure(CommandFailure)
    }

    /// The ownership-required subset of one `info --json=v2` formula record. `versions.stable`
    /// and `revision` are deliberately absent: they belong to update availability, not to whether
    /// this manager owns the selected keg. A record with malformed or contradictory identity keeps
    /// its raw claims so it can still poison a duplicate match instead of disappearing.
    private struct OwnedFormulaRecord {
        let name: String
        let fullName: String
        let installedVersions: [String]?
        let hasConsistentIdentity: Bool
    }

    private struct FormulaProof {
        let manager: ObservedExecutable
        let selection: ObservedExecutable
        let cellar: DirectoryIdentity
        let keg: DirectoryIdentity

        func revalidate() -> InstallationOwnershipReason? {
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
            guard FileIdentityObserver.observeDirectory(path: cellar.canonicalPath) == cellar,
                  FileIdentityObserver.observeDirectory(path: keg.canonicalPath) == keg
            else {
                return .proofChanged
            }
            return nil
        }
    }

    static func verify(
        definition: DetectorDefinition,
        selection: ObservedExecutable,
        manager: ObservedExecutable,
        environment: ShellEnvironment,
        runner: UpdateCommandRunner
    ) async -> InstallationOwnershipOutcome {
        if let reason = revalidate(selection: selection, manager: manager) {
            return .unknown(reason)
        }

        let cellarText: String
        switch await query(
            manager: manager,
            arguments: ["--cellar"],
            environment: environment,
            runner: runner
        ) {
        case .failure(let failure):
            return .unknown(reason(for: failure))
        case .success(let data):
            guard let parsed = ManagerOutputParser.singleAbsolutePath(data) else {
                return .unknown(.invalidManagerOutput)
            }
            cellarText = parsed
        }
        if let reason = revalidate(selection: selection, manager: manager) {
            return .unknown(reason)
        }
        guard let cellar = FileIdentityObserver.observeDirectory(path: cellarText) else {
            return .unknown(.unsupportedInstallationLayout)
        }

        let keg: SelectedKeg
        switch HomebrewTargetParser.parse(
            selectedTarget: selection.canonicalTarget,
            cellar: cellarText
        ) {
        case .failure(.managerMismatch):
            return .unknown(.managerRootMismatch)
        case .failure(.unverified):
            return .unknown(.unsupportedInstallationLayout)
        case .success(let parsed):
            keg = parsed
        }

        let declaredFormulae = definition.packages.filter { $0.manager == .homebrewFormula }
        let hasCask = definition.packages.contains { $0.manager == .homebrewCask }
        guard !declaredFormulae.isEmpty else {
            return .unknown(hasCask ? .unsupportedCask : .noDeclaredPackage)
        }
        let matching = declaredFormulae.filter { formulaStem($0.name) == keg.formula }
        guard !matching.isEmpty else { return .unknown(.noMatchingPackage) }
        guard matching.count == 1, let declared = matching.first else {
            return .unknown(.ambiguousOwnership)
        }

        let kegPath = URL(fileURLWithPath: keg.cellar, isDirectory: true)
            .appendingPathComponent(keg.formula, isDirectory: true)
            .appendingPathComponent(keg.kegVersion, isDirectory: true)
            .standardizedFileURL
        guard let kegIdentity = FileIdentityObserver.observeDirectory(path: kegPath.path),
              FileIdentityObserver.isStrictDescendant(
                kegIdentity.canonicalPath,
                of: cellar.canonicalPath
              )
        else {
            return .unknown(.unsupportedInstallationLayout)
        }
        if let reason = revalidate(selection: selection, manager: manager) {
            return .unknown(reason)
        }

        let infoData: Data
        switch await query(
            manager: manager,
            arguments: ["info", "--json=v2", "--formula", declared.name],
            environment: environment,
            runner: runner
        ) {
        case .failure(let failure):
            return .unknown(reason(for: failure))
        case .success(let data):
            infoData = data
        }
        if let reason = revalidate(selection: selection, manager: manager) {
            return .unknown(reason)
        }
        guard FileIdentityObserver.observeDirectory(path: cellar.canonicalPath) == cellar,
              FileIdentityObserver.observeDirectory(path: kegIdentity.canonicalPath) == kegIdentity
        else {
            return .unknown(.proofChanged)
        }

        guard let records = parseOwnershipInfo(infoData) else {
            return .unknown(.invalidManagerOutput)
        }
        let claims = records.filter {
            $0.fullName == declared.name || $0.name == keg.formula
        }
        guard claims.count == 1, let record = claims.first,
              record.hasConsistentIdentity,
              record.name == keg.formula,
              record.fullName == declared.name,
              HomebrewUpdateProbe.formulaIdentityConsistent(
                name: record.name,
                fullName: record.fullName
              ),
              let installedVersions = record.installedVersions
        else {
            return .unknown(.formulaRecordMismatch)
        }
        guard installedVersions.contains(keg.kegVersion) else {
            return .unknown(.selectedKegNotInstalled)
        }
        if let reason = revalidate(selection: selection, manager: manager) {
            return .unknown(reason)
        }

        let listData: Data
        switch await query(
            manager: manager,
            arguments: ["list", "--verbose", "--formula", record.fullName],
            environment: environment,
            runner: runner
        ) {
        case .failure(let failure):
            return .unknown(reason(for: failure))
        case .success(let data):
            listData = data
        }
        if let reason = revalidate(selection: selection, manager: manager) {
            return .unknown(reason)
        }
        guard let listed = listConfirmsSelectedPath(
            listData,
            selectedCanonicalPath: selection.canonicalTarget
        ) else {
            return .unknown(.invalidManagerOutput)
        }
        guard listed else {
            return .unknown(.selectedKegNotConfirmed)
        }

        let proof = FormulaProof(
            manager: manager,
            selection: selection,
            cellar: cellar,
            keg: kegIdentity
        )
        if let failure = proof.revalidate() { return .unknown(failure) }
        if let reason = revalidate(selection: selection, manager: manager) {
            return .unknown(reason)
        }

        let installation = VerifiedInstallation(
            manager: .homebrewFormula,
            packageName: record.fullName,
            managerEntryPath: manager.entryPath,
            managerTarget: manager.canonicalTarget,
            managerFingerprint: manager.fingerprint,
            managerRoot: cellar.canonicalPath,
            installationRoot: kegIdentity.canonicalPath,
            selection: InstallationSelectionIdentity(
                entryPath: selection.entryPath,
                canonicalTarget: selection.canonicalTarget,
                fingerprint: selection.fingerprint
            )
        )
        return .verified(installation)
    }

    private static func formulaStem(_ name: String) -> String {
        name.split(separator: "/").last.map(String.init) ?? name
    }

    private static func reason(for failure: CommandFailure) -> InstallationOwnershipReason {
        failure == .cancelled ? .cancelled : .managerQueryFailed
    }

    private static func revalidate(
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

    /// Parses only the ownership-required fields. `versions.stable` (absent, null or non-semver)
    /// and `revision` are ignored. Every record keeps its raw name/full_name claims: malformed or
    /// contradictory identity marks the record unusable but still visible for duplicate matching.
    private static func parseOwnershipInfo(_ data: Data) -> [OwnedFormulaRecord]? {
        guard let formulae = infoFormulaObjects(data) else { return nil }
        var records: [OwnedFormulaRecord] = []
        records.reserveCapacity(formulae.count)
        for record in formulae {
            guard let name = record["name"] as? String else { return nil }
            let rawFullName = record["full_name"] as? String
            records.append(OwnedFormulaRecord(
                name: name,
                fullName: rawFullName ?? "",
                installedVersions: installedVersionList(record["installed"]),
                hasConsistentIdentity: rawFullName.map {
                    HomebrewUpdateProbe.formulaIdentityConsistent(name: name, fullName: $0)
                } ?? false
            ))
        }
        return records
    }

    /// Validates the transport encoding and the v2 envelope shape, then returns the `formulae`
    /// array's object elements. Unknown member fields are tolerated at every level.
    private static func infoFormulaObjects(_ data: Data) -> [[String: Any]]? {
        guard strictUTF8Text(data) != nil,
              let json = try? JSONSerialization.jsonObject(with: data, options: []),
              let root = json as? [String: Any],
              let formulae = root["formulae"] as? [Any]
        else { return nil }
        var records: [[String: Any]] = []
        records.reserveCapacity(formulae.count)
        for element in formulae {
            guard let record = element as? [String: Any] else { return nil }
            records.append(record)
        }
        return records
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

    /// Every element must be an object carrying a string `version`; a partially readable
    /// collection is malformed rather than shortened.
    private static func installedVersionList(_ value: Any?) -> [String]? {
        guard let entries = value as? [Any] else { return nil }
        var versions: [String] = []
        versions.reserveCapacity(entries.count)
        for entry in entries {
            guard let object = entry as? [String: Any],
                  let version = object["version"] as? String
            else { return nil }
            versions.append(version)
        }
        return versions
    }

    /// Validates every listed path and tests membership of the selected canonical executable in
    /// one pass. The selected path's components are computed once, never once per listed file.
    /// Malformed output remains invalid even when a match was already found.
    private static func listConfirmsSelectedPath(
        _ data: Data,
        selectedCanonicalPath: String
    ) -> Bool? {
        guard !data.isEmpty, !data.contains(0x00),
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        let selectedComponents = URL(fileURLWithPath: selectedCanonicalPath)
            .standardizedFileURL.pathComponents
        var matched = false
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.hasSuffix("\r") ? rawLine.dropLast() : rawLine[...]
            guard line.hasPrefix("/") else { return nil }
            if !matched {
                let components = URL(fileURLWithPath: String(line))
                    .standardizedFileURL.pathComponents
                matched = components == selectedComponents
            }
        }
        return matched
    }
}
