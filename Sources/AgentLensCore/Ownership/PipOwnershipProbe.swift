// PipOwnershipProbe — read-only pip, venv, pipx and split-prefix diagnostics (M14-B).
//
// This probe never edits an installation and never launches pip, an interpreter, a shebang
// wrapper or another process. It starts from the selected canonical script and proves the
// installer/file relationship through bounded local evidence only. Split `pip --prefix` and
// framework `--user` scripts bind to a live absolute base interpreter outside the installation
// root; that is installation linkage, not a claim that the tool currently imports or runs.

import Darwin
import Foundation

enum PipOwnershipProbe {

    static let maximumMetadataBytes = 256 * 1024
    static let maximumRecordBytes = 1024 * 1024
    static let maximumInstallerBytes = 4 * 1024
    static let maximumPyvenvBytes = 32 * 1024
    static let maximumPipxMetadataBytes = 64 * 1024
    static let maximumDirectURLBytes = 64 * 1024
    static let maximumEntries = 256

    private struct PipxMetadata {
        let packageName: String
        let pipArgs: [String]
    }

    private struct ParsedPipxMetadata {
        let metadata: PipxMetadata
        let file: PythonProofSupport.BoundedFile
    }

    private struct Proof: Sendable {
        let selection: ObservedExecutable
        let packageName: String
        let envRootPath: String
        let envRoot: DirectoryIdentity
        let binDirPath: String
        let binDir: DirectoryIdentity
        let scriptPath: String
        let script: FileIdentity
        let interpreter: ObservedExecutable
        let pyvenvPath: String?
        let pyvenv: FileIdentity?
        let sitePackagesPath: String
        let sitePackages: DirectoryIdentity
        let distInfoPath: String
        let distInfo: DirectoryIdentity
        let metadataPath: String
        let metadata: FileIdentity
        let recordPath: String
        let record: FileIdentity
        let installerPath: String
        let installer: FileIdentity
        let pipxMetadataPath: String?
        let pipxMetadata: FileIdentity?
        let optionalFiles: [(path: String, identity: FileIdentity)]
        let absenceChecks: [(directory: DirectoryIdentity, name: String)]
        let markerPath: String?
        let markerDirectory: DirectoryIdentity?
        let markerIdentity: FileIdentity?

        func revalidate() -> InstallationOwnershipReason? {
            PythonOwnershipProbeTestHooks.onBeforeFinalRevalidation?()
            guard let currentSelection = FileIdentityObserver.observeExecutable(
                entryPath: selection.entryPath
            ), currentSelection == selection else { return .selectedExecutableChanged }
            guard FileIdentityObserver.observeDirectory(path: envRootPath) == envRoot,
                  FileIdentityObserver.observeDirectory(path: binDirPath) == binDir,
                  FileIdentityObserver.observeDirectory(path: sitePackagesPath) == sitePackages,
                  FileIdentityObserver.observeDirectory(path: distInfoPath) == distInfo
            else { return .proofChanged }
            switch PythonProofSupport.locateDistribution(
                in: sitePackages,
                sitePackagesPath: sitePackagesPath,
                packageNames: [packageName],
                maximumEntries: maximumEntries
            ) {
            case .success(let current) where current.path == distInfoPath && current.identity == distInfo: break
            case .success, .failure: return .proofChanged
            }
            guard PythonProofSupport.revalidateFile(
                in: binDir, name: (scriptPath as NSString).lastPathComponent,
                identity: script, maximumBytes: maximumRecordBytes
            ), FileIdentityObserver.observeExecutable(entryPath: interpreter.entryPath) == interpreter,
               PythonProofSupport.revalidateFile(
                in: distInfo, name: "METADATA", identity: metadata,
                maximumBytes: maximumMetadataBytes
               ), PythonProofSupport.revalidateFile(
                in: distInfo, name: "RECORD", identity: record,
                maximumBytes: maximumRecordBytes
               ), PythonProofSupport.revalidateFile(
                in: distInfo, name: "INSTALLER", identity: installer,
                maximumBytes: maximumInstallerBytes
               )
            else { return .proofChanged }
            if let pyvenv, PythonProofSupport.revalidateFile(
                in: envRoot, name: "pyvenv.cfg", identity: pyvenv,
                maximumBytes: maximumPyvenvBytes
            ) == false { return .proofChanged }
            if let pipxMetadata, PythonProofSupport.revalidateFile(
                in: envRoot, name: "pipx_metadata.json", identity: pipxMetadata,
                maximumBytes: maximumPipxMetadataBytes
            ) == false { return .proofChanged }
            if let markerDirectory, let markerIdentity,
               !PythonProofSupport.revalidateFile(
                in: markerDirectory,
                name: "EXTERNALLY-MANAGED",
                identity: markerIdentity,
                maximumBytes: maximumInstallerBytes
               ) {
                return .proofChanged
            }
            for file in optionalFiles {
                guard PythonProofSupport.revalidateFile(
                    in: distInfo,
                    name: (file.path as NSString).lastPathComponent,
                    identity: file.identity,
                    maximumBytes: maximumDirectURLBytes
                ) else { return .proofChanged }
            }
            for check in absenceChecks {
                guard PythonProofSupport.lexicalNode(
                    in: check.directory, name: check.name
                ) == .absent else { return .proofChanged }
            }
            return nil
        }
    }

    static func verify(
        definition: DetectorDefinition,
        selection: ObservedExecutable,
        environment: ShellEnvironment
    ) -> InstallationOwnershipOutcome {
        let declaredPip = definition.packages.filter { $0.manager == .pip }
        guard !declaredPip.isEmpty else { return .unknown(.noDeclaredPackage) }

        guard let envRootPath = environmentRoot(
            for: selection,
            executableName: definition.executableName
        ), let envRoot = PythonProofSupport.observePlainDirectory(envRootPath),
           let binDir = PythonProofSupport.observePlainDirectory(envRootPath + "/bin")
        else { return .unknown(.unsupportedInstallationLayout) }
        switch PythonProofSupport.lexicalNode(in: envRoot, name: "uv-receipt.toml") {
        case .present: return .unknown(.unsupportedInstallationLayout)
        case .error: return .unknown(.manifestUnreadable)
        case .absent: break
        }

        let scriptRead: PythonProofSupport.BoundedFile
        switch PythonProofSupport.readFile(
            in: binDir,
            name: definition.executableName,
            maximumBytes: maximumRecordBytes
        ) {
        case .failure(let reason): return .unknown(reason)
        case .success(let value): scriptRead = value
        }
        guard let interpreterPath = PythonProofSupport.shebangInterpreter(scriptRead.data),
              let interpreter = FileIdentityObserver.observeExecutable(entryPath: interpreterPath)
        else { return .unknown(.unsupportedInstallationLayout) }

        let pyvenvRead: PythonProofSupport.BoundedFile?
        let interpreterVersion: String?
        let pyvenvNode = PythonProofSupport.lexicalNode(in: envRoot, name: "pyvenv.cfg")
        if pyvenvNode == .error { return .unknown(.manifestUnreadable) }
        let hasPyvenv = pyvenvNode == .present
        if hasPyvenv {
            switch PythonProofSupport.readFile(
                in: envRoot,
                name: "pyvenv.cfg",
                maximumBytes: maximumPyvenvBytes
            ) {
            case .failure(let reason): return .unknown(reason)
            case .success(let value): pyvenvRead = value
            }
            guard let parsed = PythonProofSupport.parsePyvenv(pyvenvRead!.data),
                  let version = parsed["version_info"] ?? parsed["version"],
                  !version.isEmpty
            else { return .unknown(.manifestInvalid) }
            interpreterVersion = version
        } else {
            pyvenvRead = nil
            interpreterVersion = nil
        }

        var pipxFile: PythonProofSupport.BoundedFile?
        let layout: (
            sitePackagesPath: String,
            sitePackages: DirectoryIdentity,
            kind: PythonEnvironmentKind,
            pipx: PipxMetadata?,
            markerPath: String?,
            markerDirectory: DirectoryIdentity?,
            markerIdentity: FileIdentity?
        )
        if hasPyvenv {
            guard FileIdentityObserver.isStrictDescendant(
                URL(fileURLWithPath: interpreterPath).standardizedFileURL.path,
                of: envRoot.canonicalPath
            ),
                URL(fileURLWithPath: interpreterPath).deletingLastPathComponent().lastPathComponent == "bin",
                PythonProofSupport.isPythonInterpreterName(URL(fileURLWithPath: interpreterPath).lastPathComponent),
                let version = interpreterVersion
            else { return .unknown(.unsupportedInstallationLayout) }
            guard let located = PythonProofSupport.locateVersionedSitePackages(
                envRoot: envRoot,
                version: version,
                maximumEntries: maximumEntries
            ) else { return .unknown(.unsupportedInstallationLayout) }
            let pipxNode = PythonProofSupport.lexicalNode(in: envRoot, name: "pipx_metadata.json")
            if pipxNode == .error { return .unknown(.manifestUnreadable) }
            if pipxNode == .present {
                let parsed: ParsedPipxMetadata
                switch readPipxMetadata(envRoot: envRoot, expectedScript: selection.canonicalTarget) {
                case .failure(let reason): return .unknown(reason)
                case .success(let value): parsed = value
                }
                pipxFile = parsed.file
                layout = (located.path, located.identity, .pipxEnvironment, parsed.metadata, nil, nil, nil)
            } else {
                layout = (located.path, located.identity, .virtualEnvironment, nil, nil, nil, nil)
            }
        } else {
            guard let located = locateSplitSitePackages(
                envRootPath: envRootPath,
                environment: environment
            ) else { return .unknown(.unsupportedInstallationLayout) }
            let interpreterName = URL(fileURLWithPath: interpreterPath).lastPathComponent
            guard PythonProofSupport.isPythonInterpreterName(interpreterName),
                  interpreterName == located.interpreterName
            else { return .unknown(.unsupportedInstallationLayout) }
            let interpreterInsideRoot = FileIdentityObserver.isExactDescendant(
                URL(fileURLWithPath: interpreterPath).standardizedFileURL.path,
                of: envRoot.canonicalPath,
                components: ["bin", interpreterName]
            )
            let kind: PythonEnvironmentKind
            var markerPath: String?
            var markerDirectory: DirectoryIdentity?
            var markerIdentity: FileIdentity?
            if interpreterInsideRoot {
                // Only a runtime whose own bin interpreter and matching stdlib marker are both
                // anchored can be externally managed. A stray marker in a --prefix install is
                // not evidence and never reaches this branch.
                guard let candidateMarker = located.markerPath,
                      let markerDir = located.markerDirectory,
                      let markerID = located.markerIdentity
                else { return .unknown(.unsupportedInstallationLayout) }
                kind = .externallyManagedSystem
                markerPath = candidateMarker
                markerDirectory = markerDir
                markerIdentity = markerID
            } else {
                kind = .sharedPrefix
                markerPath = nil
                markerDirectory = nil
                markerIdentity = nil
            }
            layout = (
                located.sitePackagesPath, located.sitePackages, kind, nil, markerPath,
                markerDirectory, markerIdentity
            )
        }

        let distInfo: PythonProofSupport.PythonDistribution
        switch PythonProofSupport.locateDistribution(
            in: layout.sitePackages,
            sitePackagesPath: layout.sitePackagesPath,
            packageNames: declaredPip.map(\.name),
            maximumEntries: maximumEntries
        ) {
        case .failure(let reason): return .unknown(reason)
        case .success(let value): distInfo = value
        }

        let installerRead: PythonProofSupport.BoundedFile
        switch PythonProofSupport.readFile(
            in: distInfo.identity,
            name: "INSTALLER",
            maximumBytes: maximumInstallerBytes
        ) {
        case .failure(let reason): return .unknown(reason)
        case .success(let value): installerRead = value
        }
        guard String(decoding: installerRead.data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines) == "pip"
        else { return .unknown(.unsupportedSource) }

        let metadataRead: PythonProofSupport.BoundedFile
        switch PythonProofSupport.readFile(
            in: distInfo.identity,
            name: "METADATA",
            maximumBytes: maximumMetadataBytes
        ) {
        case .failure(let reason): return .unknown(reason)
        case .success(let value): metadataRead = value
        }
        guard let metadata = PythonProofSupport.parseMetadata(metadataRead.data) else {
            return .unknown(.manifestInvalid)
        }
        let matchingDeclared = declaredPip.filter {
            PythonPackageIdentity.normalized($0.name)
                == PythonPackageIdentity.normalized(metadata.name)
        }
        guard matchingDeclared.count == 1, let declared = matchingDeclared.first else {
            return .unknown(matchingDeclared.isEmpty ? .packageNameMismatch : .ambiguousOwnership)
        }
        if let pipx = layout.pipx,
           PythonPackageIdentity.normalized(pipx.packageName)
               != PythonPackageIdentity.normalized(declared.name) {
            return .unknown(.packageNameMismatch)
        }

        let recordRead: PythonProofSupport.BoundedFile
        switch PythonProofSupport.readFile(
            in: distInfo.identity,
            name: "RECORD",
            maximumBytes: maximumRecordBytes
        ) {
        case .failure(let reason): return .unknown(reason)
        case .success(let value): recordRead = value
        }
        switch PythonProofSupport.verifyRecord(
            recordData: recordRead.data,
            scriptData: scriptRead.data,
            sitePackagesPath: layout.sitePackagesPath,
            selectedTarget: selection.canonicalTarget,
            executableName: definition.executableName,
            allowPipxNormalization: layout.kind == .pipxEnvironment
        ) {
        case .failure(let reason): return .unknown(reason)
        case .success: break
        }

        var optionalFiles: [(path: String, identity: FileIdentity)] = []
        var absenceChecks: [(directory: DirectoryIdentity, name: String)] = [
            (envRoot, "uv-receipt.toml")
        ]
        if pyvenvRead == nil {
            absenceChecks.append((envRoot, "pyvenv.cfg"))
        }
        if layout.pipx == nil {
            absenceChecks.append((envRoot, "pipx_metadata.json"))
        }
        let directURLPath = distInfo.path + "/direct_url.json"
        var directURL: FileIdentity?
        let directURLNode = PythonProofSupport.lexicalNode(in: distInfo.identity, name: "direct_url.json")
        if directURLNode == .error { return .unknown(.manifestUnreadable) }
        if directURLNode == .present {
            switch PythonProofSupport.readFile(
                in: distInfo.identity,
                name: "direct_url.json",
                maximumBytes: maximumDirectURLBytes
            ) {
            case .failure(let reason): return .unknown(reason)
            case .success(let value):
                directURL = value.identity
                optionalFiles.append((directURLPath, value.identity))
            }
        } else {
            absenceChecks.append((distInfo.identity, "direct_url.json"))
        }

        let provenance: PythonIndexProvenance
        if directURL != nil {
            provenance = .nonRegistrySource
        } else if let pipx = layout.pipx {
            provenance = pipxProvenance(pipx.pipArgs)
        } else {
            provenance = .unknown
        }

        let verified = VerifiedInstallation(
            manager: .pip,
            packageName: declared.name,
            managerEntryPath: interpreter.entryPath,
            managerTarget: interpreter.canonicalTarget,
            managerFingerprint: interpreter.fingerprint,
            managerRoot: layout.sitePackagesPath,
            installationRoot: envRoot.canonicalPath,
            selection: InstallationSelectionIdentity(
                entryPath: selection.entryPath,
                canonicalTarget: selection.canonicalTarget,
                fingerprint: selection.fingerprint
            ),
            pythonEnvironment: PythonEnvironmentMetadata(
                installedVersion: metadata.version,
                interpreterVersion: interpreterVersion,
                requiresPython: metadata.requiresPython,
                environmentKind: layout.kind,
                installer: "pip",
                indexProvenance: provenance
            )
        )
        let pipxMetadataIdentity = pipxFile?.identity
        let pipxMetadataPath = pipxFile?.identity.canonicalPath
        let proof = Proof(
            selection: selection,
            packageName: declared.name,
            envRootPath: envRoot.canonicalPath,
            envRoot: envRoot,
            binDirPath: envRoot.canonicalPath + "/bin",
            binDir: binDir,
            scriptPath: scriptRead.identity.canonicalPath,
            script: scriptRead.identity,
            interpreter: interpreter,
            pyvenvPath: pyvenvRead?.identity.canonicalPath,
            pyvenv: pyvenvRead?.identity,
            sitePackagesPath: layout.sitePackagesPath,
            sitePackages: layout.sitePackages,
            distInfoPath: distInfo.path,
            distInfo: distInfo.identity,
            metadataPath: metadataRead.identity.canonicalPath,
            metadata: metadataRead.identity,
            recordPath: recordRead.identity.canonicalPath,
            record: recordRead.identity,
            installerPath: installerRead.identity.canonicalPath,
            installer: installerRead.identity,
            pipxMetadataPath: pipxMetadataPath,
            pipxMetadata: pipxMetadataIdentity,
            optionalFiles: optionalFiles,
            absenceChecks: absenceChecks,
            markerPath: layout.markerPath,
            markerDirectory: layout.markerDirectory,
            markerIdentity: layout.markerIdentity
        )
        if let reason = proof.revalidate() { return .unknown(reason) }
        return .verified(verified)
    }

    private static func environmentRoot(
        for selection: ObservedExecutable,
        executableName: String
    ) -> String? {
        let components = URL(fileURLWithPath: selection.canonicalTarget)
            .standardizedFileURL.pathComponents
        guard components.count >= 3,
              components.last == executableName,
              components[components.count - 2] == "bin"
        else { return nil }
        let root = URL(fileURLWithPath: selection.canonicalTarget)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
        return root.hasPrefix("/") ? root : nil
    }

    private struct SplitLocation {
        let sitePackagesPath: String
        let sitePackages: DirectoryIdentity
        let version: String
        let interpreterName: String
        let markerPath: String?
        let markerDirectory: DirectoryIdentity?
        let markerIdentity: FileIdentity?
    }

    private static func locateSplitSitePackages(
        envRootPath: String,
        environment: ShellEnvironment
    ) -> SplitLocation? {
        guard let envRoot = PythonProofSupport.observePlainDirectory(envRootPath) else {
            return nil
        }
        let libPath = envRootPath + "/lib"
        guard let lib = PythonProofSupport.observePlainDirectory(libPath),
              let names = PythonProofSupport.listNames(in: lib, maximumEntries: maximumEntries)
        else { return nil }

        let home = environment.raw["HOME"] ?? ""
        let standardRoot = URL(fileURLWithPath: envRootPath).standardizedFileURL.path
        let userPrefix = home.isEmpty ? nil : standardRoot.hasPrefix(home + "/Library/Python/")
        let version: String
        let versionedPath: String
        let interpreterName: String
        let isUserScheme: Bool
        if let userPrefix, userPrefix,
           let index = standardRoot.range(of: home + "/Library/Python/")?.upperBound {
            let suffix = String(standardRoot[index...])
            let components = suffix.split(separator: ".", omittingEmptySubsequences: false)
            guard components.count == 2,
                  components.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isNumber } })
            else { return nil }
            version = suffix
            versionedPath = libPath + "/python"
            interpreterName = "python" + suffix
            isUserScheme = true
        } else {
            let candidates = names.filter { name in
                guard name.hasPrefix("python3.") else { return false }
                let suffix = name.dropFirst("python3.".count)
                return !suffix.isEmpty && suffix.allSatisfy { $0.isNumber }
            }
            guard candidates.count == 1, let only = candidates.first else { return nil }
            version = String(only.dropFirst("python3.".count))
            versionedPath = libPath + "/" + only
            interpreterName = only
            isUserScheme = false
        }
        guard let versionDir = PythonProofSupport.observePlainDirectory(versionedPath),
              let entries = PythonProofSupport.listNames(
                in: versionDir,
                maximumEntries: maximumEntries
              ),
              entries.contains("site-packages")
        else { return nil }
        let sitePath = versionedPath + "/site-packages"
        guard let site = PythonProofSupport.observePlainDirectory(sitePath) else { return nil }
        let markerNode = PythonProofSupport.lexicalNode(
            in: versionDir,
            name: "EXTERNALLY-MANAGED"
        )
        if markerNode == .error { return nil }
        var markerIdentity: FileIdentity?
        if markerNode == .present, !isUserScheme {
            switch PythonProofSupport.readFile(
                in: versionDir,
                name: "EXTERNALLY-MANAGED",
                maximumBytes: maximumInstallerBytes
            ) {
            case .success(let file): markerIdentity = file.identity
            case .failure: return nil
            }
        }
        return SplitLocation(
            sitePackagesPath: sitePath,
            sitePackages: site,
            version: version,
            interpreterName: interpreterName,
            markerPath: markerNode == .present && !isUserScheme
                ? versionedPath + "/EXTERNALLY-MANAGED" : nil,
            markerDirectory: markerNode == .present && !isUserScheme ? versionDir : nil,
            markerIdentity: markerIdentity
        )
    }

    private static func readPipxMetadata(
        envRoot: DirectoryIdentity,
        expectedScript: String
    ) -> Result<ParsedPipxMetadata, InstallationOwnershipReason> {
        let read: PythonProofSupport.BoundedFile
        switch PythonProofSupport.readFile(
            in: envRoot,
            name: "pipx_metadata.json",
            maximumBytes: maximumPipxMetadataBytes
        ) {
        case .failure(let reason): return .failure(reason)
        case .success(let value): read = value
        }
        guard let object = try? JSONSerialization.jsonObject(with: read.data),
              let root = object as? [String: Any],
              root["pipx_metadata_version"] as? String == "0.12",
              root["backend"] as? String == "pip",
              let main = root["main_package"] as? [String: Any],
              let package = main["package"] as? String,
              PythonPackageIdentity.isValidDistributionName(package),
              let _ = main["package_or_url"] as? String,
              let apps = main["apps"] as? [String],
              apps.contains(URL(fileURLWithPath: expectedScript).lastPathComponent),
              let appPaths = main["app_paths"] as? [[String: Any]]
        else { return .failure(.manifestInvalid) }
        let expectedPath = URL(fileURLWithPath: expectedScript).standardizedFileURL.path
        let exposed = appPaths.contains { value in
            guard let path = value["__Path__"] as? String else { return false }
            return URL(fileURLWithPath: path).standardizedFileURL.path == expectedPath
        }
        guard exposed else { return .failure(.unsupportedInstallationLayout) }
        guard let pipArgs = main["pip_args"] as? [String] else {
            return .failure(.manifestInvalid)
        }
        return .success(ParsedPipxMetadata(
            metadata: PipxMetadata(packageName: package, pipArgs: pipArgs),
            file: read
        ))
    }

    private static func pipxProvenance(_ pipArgs: [String]) -> PythonIndexProvenance {
        if pipArgs.contains("--no-index")
            || pipArgs.contains("--extra-index-url")
            || pipArgs.contains("--find-links")
            || pipArgs.contains("-f") {
            return .unknown
        }
        var indices: [String] = []
        var index = 0
        while index < pipArgs.count {
            let argument = pipArgs[index]
            if argument == "--index-url" || argument == "-i" {
                guard index + 1 < pipArgs.count, !pipArgs[index + 1].hasPrefix("-") else {
                    return .unknown
                }
                indices.append(pipArgs[index + 1])
                index += 2
                continue
            }
            if argument.hasPrefix("--index-url=") {
                let value = String(argument.dropFirst("--index-url=".count))
                guard !value.isEmpty, !value.hasPrefix("-") else { return .unknown }
                indices.append(value)
            }
            index += 1
        }
        guard indices.count == 1, let only = indices.first else { return .unknown }
        // pipx metadata alone is not independent proof of a public-PyPI install. A non-public
        // single index is unambiguous custom evidence; a public claim stays unknown in B.
        if PythonProofSupport.isExactPublicPyPI(only) { return .unknown }
        guard URLComponents(string: only)?.scheme != nil else { return .unknown }
        return .customIndex
    }
}