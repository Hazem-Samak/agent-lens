// UvToolOwnershipProbe — read-only uv tool ownership proof (M14-B).
//
// The proof starts at the diagnostic's selected canonical script and never borrows a manager
// result. The uv roots come from exactly two bounded queries (`tool dir`, `tool dir --bin`) with
// the same root-selection environment as the later mutation phases. The managed shim, receipt,
// pyvenv binding, distribution metadata, INSTALLER and RECORD must all agree with that one
// canonical script. No index is assumed: source provenance is either affirmatively recorded in the
// receipt or left unknown.

import CryptoKit
import Darwin
import Foundation

enum UvToolOwnershipProbe {

    static let rootQueryTimeout: TimeInterval = 5.0
    static let maximumRootOutputBytes = 64 * 1024
    static let maximumReceiptBytes = 64 * 1024
    static let maximumPyvenvBytes = 32 * 1024
    static let maximumMetadataBytes = 256 * 1024
    static let maximumRecordBytes = 1024 * 1024
    static let maximumEntryPointsBytes = 64 * 1024
    static let maximumDirectURLBytes = 64 * 1024
    static let maximumInstallerBytes = 4 * 1024
    static let maximumEntries = 256

    struct Roots: Equatable, Sendable {
        let toolDirPath: String
        let toolDir: DirectoryIdentity
        let binDirPath: String
        let binDir: DirectoryIdentity
    }

    private struct IndexRecord {
        let url: String
        let explicit: Bool?
        let isDefault: Bool?
        let format: String?
    }

    private struct Receipt {
        let constraints: [String]
        let extras: [String]
        let entrypointInstallPath: String
        let indexRecords: [IndexRecord]
        let topLevelIndexURL: String?
        let noIndex: Bool?
        let directSource: Bool
    }

    private struct Proof: Sendable {
        let manager: ObservedExecutable
        let selection: ObservedExecutable
        let packageName: String
        let roots: Roots
        let envRootPath: String
        let envRoot: DirectoryIdentity
        let binDirPath: String
        let binDir: DirectoryIdentity
        let shim: ObservedExecutable
        let receiptPath: String
        let receipt: FileIdentity
        let pyvenvPath: String
        let pyvenv: FileIdentity
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
        let scriptPath: String
        let script: FileIdentity
        let interpreter: ObservedExecutable
        let optionalFiles: [(path: String, identity: FileIdentity)]
        let absenceChecks: [(directory: DirectoryIdentity, name: String)]

        func revalidate() -> InstallationOwnershipReason? {
            PythonOwnershipProbeTestHooks.onBeforeFinalRevalidation?()
            guard let currentManager = FileIdentityObserver.observeExecutable(
                entryPath: manager.entryPath
            ), currentManager == manager else { return .managerChanged }
            guard let currentSelection = FileIdentityObserver.observeExecutable(
                entryPath: selection.entryPath
            ), currentSelection == selection else { return .selectedExecutableChanged }
            guard FileIdentityObserver.observeDirectory(path: roots.toolDirPath) == roots.toolDir,
                  FileIdentityObserver.observeDirectory(path: roots.binDirPath) == roots.binDir,
                  FileIdentityObserver.observeDirectory(path: envRootPath) == envRoot,
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
            guard let currentShim = FileIdentityObserver.observeExecutable(entryPath: shim.entryPath),
                  currentShim == shim
            else { return .managerEntryMismatch }
            guard PythonProofSupport.revalidateFile(
                in: envRoot, name: "uv-receipt.toml", identity: receipt,
                maximumBytes: maximumReceiptBytes
            ), PythonProofSupport.revalidateFile(
                in: envRoot, name: "pyvenv.cfg", identity: pyvenv,
                maximumBytes: maximumPyvenvBytes
            ), PythonProofSupport.revalidateFile(
                in: distInfo, name: "METADATA", identity: metadata,
                maximumBytes: maximumMetadataBytes
            ), PythonProofSupport.revalidateFile(
                in: distInfo, name: "RECORD", identity: record,
                maximumBytes: maximumRecordBytes
            ), PythonProofSupport.revalidateFile(
                in: distInfo, name: "INSTALLER", identity: installer,
                maximumBytes: maximumInstallerBytes
            ), PythonProofSupport.revalidateFile(
                in: binDir, name: (scriptPath as NSString).lastPathComponent, identity: script,
                maximumBytes: maximumRecordBytes
            ), FileIdentityObserver.observeExecutable(entryPath: interpreter.entryPath) == interpreter
            else { return .proofChanged }
            for file in optionalFiles {
                guard PythonProofSupport.revalidateFile(
                    in: distInfo,
                    name: (file.path as NSString).lastPathComponent,
                    identity: file.identity,
                    maximumBytes: maximumEntryPointsBytes
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
        manager: ObservedExecutable,
        environment: ShellEnvironment,
        runner: UpdateCommandRunner
    ) async -> InstallationOwnershipOutcome {
        if let reason = revalidate(selection: selection, manager: manager) {
            return .unknown(reason)
        }
        let roots: Roots
        switch await resolveRoots(
            manager: manager,
            selection: selection,
            environment: environment,
            runner: runner
        ) {
        case .failure(let reason): return .unknown(reason)
        case .success(let value): roots = value
        }
        if let reason = revalidate(selection: selection, manager: manager) {
            return .unknown(reason)
        }

        guard let envRootPath = environmentRoot(for: selection, executableName: definition.executableName),
              let envRoot = PythonProofSupport.observePlainDirectory(envRootPath),
              FileIdentityObserver.isStrictDescendant(envRoot.canonicalPath, of: roots.toolDir.canonicalPath)
        else { return .unknown(.managerRootMismatch) }

        let targetComponents = URL(fileURLWithPath: selection.canonicalTarget)
            .standardizedFileURL.pathComponents
        let rootComponents = URL(fileURLWithPath: roots.toolDir.canonicalPath)
            .standardizedFileURL.pathComponents
        guard targetComponents.count == rootComponents.count + 3,
              Array(targetComponents.prefix(rootComponents.count)) == rootComponents,
              targetComponents[rootComponents.count + 1] == "bin",
              targetComponents.last == definition.executableName
        else { return .unknown(.managerRootMismatch) }
        let packageDirectoryName = targetComponents[rootComponents.count]
        let declaredUv = definition.packages.filter { $0.manager == .uvTool }
        let packageMatches = declaredUv.filter {
            PythonPackageIdentity.normalized($0.name) == PythonPackageIdentity.normalized(packageDirectoryName)
        }
        guard packageMatches.count == 1, let declared = packageMatches.first else {
            return .unknown(packageMatches.isEmpty ? .noMatchingPackage : .ambiguousOwnership)
        }

        let binDirPath = roots.binDirPath
        let expectedShimPath = URL(fileURLWithPath: binDirPath, isDirectory: true)
            .appendingPathComponent(definition.executableName)
            .standardizedFileURL.path
        guard selection.entryPath == expectedShimPath,
              let shim = FileIdentityObserver.observeExecutable(entryPath: expectedShimPath),
              shim == selection
        else { return .unknown(.managerEntryMismatch) }

        let envBinPath = envRoot.canonicalPath + "/bin"
        guard let envBinDir = PythonProofSupport.observePlainDirectory(envBinPath) else {
            return .unknown(.unsupportedInstallationLayout)
        }

        let receiptRead: PythonProofSupport.BoundedFile
        switch PythonProofSupport.readFile(
            in: envRoot,
            name: "uv-receipt.toml",
            maximumBytes: maximumReceiptBytes
        ) {
        case .failure(let reason): return .unknown(reason)
        case .success(let value): receiptRead = value
        }
        let receipt: Receipt
        switch parseReceipt(receiptRead.data, packageName: declared.name, executableName: definition.executableName,
                            expectedInstallPath: expectedShimPath) {
        case .failure(let reason): return .unknown(reason)
        case .success(let value): receipt = value
        }

        let pyvenvRead: PythonProofSupport.BoundedFile
        switch PythonProofSupport.readFile(in: envRoot, name: "pyvenv.cfg", maximumBytes: maximumPyvenvBytes) {
        case .failure(let reason): return .unknown(reason)
        case .success(let value): pyvenvRead = value
        }
        guard let pyvenv = PythonProofSupport.parsePyvenv(pyvenvRead.data),
              let interpreterVersion = pyvenv["version_info"] ?? pyvenv["version"] ?? pyvenv["version_info "],
              !interpreterVersion.isEmpty
        else { return .unknown(.manifestInvalid) }

        let scriptRead: PythonProofSupport.BoundedFile
        switch PythonProofSupport.readFile(
            in: envBinDir,
            name: definition.executableName,
            maximumBytes: maximumRecordBytes
        ) {
        case .failure(let reason): return .unknown(reason)
        case .success(let value): scriptRead = value
        }
        guard let interpreterPath = PythonProofSupport.shebangInterpreter(scriptRead.data),
              let interpreter = FileIdentityObserver.observeExecutable(entryPath: interpreterPath),
              FileIdentityObserver.isStrictDescendant(
                URL(fileURLWithPath: interpreter.entryPath).standardizedFileURL.path,
                of: envRoot.canonicalPath
              ),
              URL(fileURLWithPath: interpreter.entryPath).deletingLastPathComponent().lastPathComponent == "bin",
              PythonProofSupport.isPythonInterpreterName(
                URL(fileURLWithPath: interpreter.entryPath).lastPathComponent
              )
        else { return .unknown(.unsupportedInstallationLayout) }

        guard let distribution = locateDistribution(
            envRoot: envRoot,
            interpreterVersion: interpreterVersion,
            packageNames: [declared.name]
        ) else { return .unknown(.unsupportedInstallationLayout) }
        let sitePackagesPath = distribution.sitePackagesPath
        let sitePackages = distribution.sitePackages
        let distInfoPath = distribution.distInfoPath
        let distInfo = distribution.distInfo

        let installerRead: PythonProofSupport.BoundedFile
        switch PythonProofSupport.readFile(
            in: distInfo,
            name: "INSTALLER",
            maximumBytes: maximumInstallerBytes
        ) {
        case .failure(let reason): return .unknown(reason)
        case .success(let value): installerRead = value
        }
        guard String(decoding: installerRead.data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines) == "uv"
        else { return .unknown(.unsupportedSource) }

        let metadataRead: PythonProofSupport.BoundedFile
        switch PythonProofSupport.readFile(
            in: distInfo,
            name: "METADATA",
            maximumBytes: maximumMetadataBytes
        ) {
        case .failure(let reason): return .unknown(reason)
        case .success(let value): metadataRead = value
        }
        guard let metadata = PythonProofSupport.parseMetadata(metadataRead.data),
              PythonPackageIdentity.normalized(metadata.name) == PythonPackageIdentity.normalized(declared.name),
              !metadata.version.isEmpty
        else { return .unknown(.packageNameMismatch) }

        let recordRead: PythonProofSupport.BoundedFile
        switch PythonProofSupport.readFile(
            in: distInfo,
            name: "RECORD",
            maximumBytes: maximumRecordBytes
        ) {
        case .failure(let reason): return .unknown(reason)
        case .success(let value): recordRead = value
        }
        switch PythonProofSupport.verifyRecord(
            recordData: recordRead.data,
            scriptData: scriptRead.data,
            sitePackagesPath: sitePackagesPath,
            selectedTarget: selection.canonicalTarget,
            executableName: definition.executableName,
            allowPipxNormalization: false
        ) {
        case .failure(let reason): return .unknown(reason)
        case .success: break
        }

        var optionalFiles: [(path: String, identity: FileIdentity)] = []
        var absenceChecks: [(directory: DirectoryIdentity, name: String)] = []
        let entryPointsPath = URL(fileURLWithPath: distInfoPath, isDirectory: true)
            .appendingPathComponent("entry_points.txt").path
        let entryPointsNode = PythonProofSupport.lexicalNode(
            in: distInfo,
            name: "entry_points.txt"
        )
        if entryPointsNode == .error { return .unknown(.manifestUnreadable) }
        if entryPointsNode == .present {
            switch PythonProofSupport.readFile(
                in: distInfo,
                name: "entry_points.txt",
                maximumBytes: maximumEntryPointsBytes
            ) {
            case .failure(let reason): return .unknown(reason)
            case .success(let value):
                guard PythonProofSupport.consoleScriptDeclared(
                    value.data,
                    executableName: definition.executableName
                ) else { return .unknown(.executableNotDeclared) }
                optionalFiles.append((entryPointsPath, value.identity))
            }
        } else {
            absenceChecks.append((distInfo, "entry_points.txt"))
        }

        let directURLPath = URL(fileURLWithPath: distInfoPath, isDirectory: true)
            .appendingPathComponent("direct_url.json").path
        let directURLNode = PythonProofSupport.lexicalNode(
            in: distInfo,
            name: "direct_url.json"
        )
        if directURLNode == .error { return .unknown(.manifestUnreadable) }
        if directURLNode == .present {
            switch PythonProofSupport.readFile(
                in: distInfo,
                name: "direct_url.json",
                maximumBytes: maximumDirectURLBytes
            ) {
            case .failure(let reason): return .unknown(reason)
            case .success(let value):
                optionalFiles.append((directURLPath, value.identity))
            }
        } else {
            absenceChecks.append((distInfo, "direct_url.json"))
        }

        let provenance = indexProvenance(
            receipt: receipt,
            directURLIdentity: optionalFiles.first { $0.path == directURLPath }?.identity
        )

        let verified = VerifiedInstallation(
            manager: .uvTool,
            packageName: declared.name,
            managerEntryPath: manager.entryPath,
            managerTarget: manager.canonicalTarget,
            managerFingerprint: manager.fingerprint,
            managerRoot: roots.toolDir.canonicalPath,
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
                environmentKind: .uvTool,
                installer: "uv",
                indexProvenance: provenance,
                receiptConstraints: receipt.constraints,
                extras: receipt.extras
            )
        )
        let proof = Proof(
            manager: manager,
            selection: selection,
            packageName: declared.name,
            roots: roots,
            envRootPath: envRoot.canonicalPath,
            envRoot: envRoot,
            binDirPath: envBinPath,
            binDir: envBinDir,
            shim: shim,
            receiptPath: receiptRead.identity.canonicalPath,
            receipt: receiptRead.identity,
            pyvenvPath: pyvenvRead.identity.canonicalPath,
            pyvenv: pyvenvRead.identity,
            sitePackagesPath: sitePackagesPath,
            sitePackages: sitePackages,
            distInfoPath: distInfoPath,
            distInfo: distInfo,
            metadataPath: metadataRead.identity.canonicalPath,
            metadata: metadataRead.identity,
            recordPath: recordRead.identity.canonicalPath,
            record: recordRead.identity,
            installerPath: installerRead.identity.canonicalPath,
            installer: installerRead.identity,
            scriptPath: scriptRead.identity.canonicalPath,
            script: scriptRead.identity,
            interpreter: interpreter,
            optionalFiles: optionalFiles,
            absenceChecks: absenceChecks
        )
        if let reason = proof.revalidate() { return .unknown(reason) }
        return .verified(verified)
    }

    /// Resolve both roots once with the same root-selection inputs the later operation will use.
    static func resolveRoots(
        manager: ObservedExecutable,
        selection: ObservedExecutable,
        environment: ShellEnvironment,
        runner: UpdateCommandRunner
    ) async -> Result<Roots, InstallationOwnershipReason> {
        if let reason = revalidate(selection: selection, manager: manager) {
            return .failure(reason)
        }
        var raw = environment.raw
        raw["UV_NO_CACHE"] = "1"
        raw["UV_NO_PROGRESS"] = "1"
        raw["UV_OFFLINE"] = "1"
        let arguments: [[String]] = [["tool", "dir"], ["tool", "dir", "--bin"]]
        var output: [String] = []
        for args in arguments {
            if Task.isCancelled { return .failure(.cancelled) }
            if let reason = revalidate(selection: selection, manager: manager) {
                return .failure(reason)
            }
            let result = await runner.run(
                executablePath: manager.canonicalTarget,
                arguments: args,
                environment: raw,
                timeout: rootQueryTimeout
            )
            if Task.isCancelled { return .failure(.cancelled) }
            switch result {
            case .failure(let failure):
                return .failure(failure == .cancelled ? .cancelled : .managerQueryFailed)
            case .success(let data):
                guard data.count <= maximumRootOutputBytes,
                      let path = ManagerOutputParser.singleAbsolutePath(data)
                else { return .failure(.invalidManagerOutput) }
                output.append(path)
            }
            if let reason = revalidate(selection: selection, manager: manager) {
                return .failure(reason)
            }
        }
        let toolDirPath = URL(fileURLWithPath: output[0]).standardizedFileURL.path
        let binDirPath = URL(fileURLWithPath: output[1]).standardizedFileURL.path
        guard let toolDir = FileIdentityObserver.observeDirectory(path: toolDirPath),
              let binDir = FileIdentityObserver.observeDirectory(path: binDirPath)
        else { return .failure(.managerRootMismatch) }
        return .success(Roots(
            toolDirPath: toolDirPath,
            toolDir: toolDir,
            binDirPath: binDirPath,
            binDir: binDir
        ))
    }

    /// True when the selection's canonical target is inside the uv tool directory. Used by the
    /// classifier before a pip proof; a root match reserves ownership for uv even when the receipt
    /// is missing or unreadable.
    static func selectionIsInsideToolRoot(
        selection: ObservedExecutable,
        roots: Roots
    ) -> Bool {
        FileIdentityObserver.isStrictDescendant(
            selection.canonicalTarget,
            of: roots.toolDir.canonicalPath
        )
    }

    private static func revalidate(
        selection: ObservedExecutable,
        manager: ObservedExecutable
    ) -> InstallationOwnershipReason? {
        guard let currentSelection = FileIdentityObserver.observeExecutable(
            entryPath: selection.entryPath
        ), currentSelection == selection else { return .selectedExecutableChanged }
        guard let currentManager = FileIdentityObserver.observeExecutable(
            entryPath: manager.entryPath
        ), currentManager == manager else { return .managerChanged }
        return nil
    }

    static func resolveManager(
        environment: ShellEnvironment,
        currentDirectory: String
    ) -> ObservedExecutable? {
        let workingDirectory = URL(
            fileURLWithPath: currentDirectory,
            isDirectory: true
        ).standardizedFileURL
        for directoryText in environment.pathEntries {
            let directory = directoryText.isEmpty
                ? workingDirectory
                : URL(
                    fileURLWithPath: directoryText,
                    isDirectory: true,
                    relativeTo: workingDirectory
                ).standardizedFileURL
            let entry = directory.appendingPathComponent("uv").standardizedFileURL.path
            if let observed = FileIdentityObserver.observeExecutable(entryPath: entry) {
                return observed
            }
        }
        return nil
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
        guard root.hasPrefix("/") else { return nil }
        return root
    }

    private struct DistributionLocation {
        let sitePackagesPath: String
        let sitePackages: DirectoryIdentity
        let distInfoPath: String
        let distInfo: DirectoryIdentity
    }

    private static func locateDistribution(
        envRoot: DirectoryIdentity,
        interpreterVersion: String,
        packageNames: [String]
    ) -> DistributionLocation? {
        guard let sitePackages = PythonProofSupport.locateVersionedSitePackages(
            envRoot: envRoot,
            version: interpreterVersion,
            maximumEntries: maximumEntries
        ), case .success(let distribution) = PythonProofSupport.locateDistribution(
            in: sitePackages.identity,
            sitePackagesPath: sitePackages.path,
            packageNames: packageNames,
            maximumEntries: maximumEntries
        ) else { return nil }
        return DistributionLocation(
            sitePackagesPath: sitePackages.path,
            sitePackages: sitePackages.identity,
            distInfoPath: distribution.path,
            distInfo: distribution.identity
        )
    }

    private static func indexProvenance(
        receipt: Receipt,
        directURLIdentity: FileIdentity?
    ) -> PythonIndexProvenance {
        if receipt.directSource || directURLIdentity != nil {
            return .nonRegistrySource
        }
        if receipt.noIndex == true { return .unknown }
        guard receipt.topLevelIndexURL == nil,
              receipt.indexRecords.count == 1,
              let only = receipt.indexRecords.first
        else { return .unknown }
        if PythonProofSupport.isExactPublicPyPI(only.url),
           only.explicit == false,
           only.isDefault == true,
           only.format == "simple" {
            return .publicPyPI
        }
        return only.url.isEmpty ? .unknown : .customIndex
    }

    // MARK: Receipt parsing

    private static func parseReceipt(
        _ data: Data,
        packageName: String,
        executableName: String,
        expectedInstallPath: String
    ) -> Result<Receipt, InstallationOwnershipReason> {
        guard let root = PythonReceiptTOML.parse(data) else {
            return .failure(.manifestInvalid)
        }
        guard Set(root.keys) == ["tool"], let toolValue = root["tool"], case .table(let tool) = toolValue
        else { return .failure(.unsupportedInstallationLayout) }
        let allowedToolKeys: Set<String> = ["requirements", "python", "entrypoints", "options"]
        guard Set(tool.keys).isSubset(of: allowedToolKeys) else {
            return .failure(.unsupportedInstallationLayout)
        }
        if let pythonValue = tool["python"] {
            guard case .string = pythonValue else { return .failure(.manifestInvalid) }
        }
        guard let requirementsValue = tool["requirements"],
              case .array(let requirementValues) = requirementsValue,
              !requirementValues.isEmpty
        else { return .failure(.manifestInvalid) }
        var requirementNames: [String] = []
        var constraints: [String] = []
        var extras: [String] = []
        var directSource = false
        for value in requirementValues {
            guard case .table(let requirement) = value else {
                return .failure(.manifestInvalid)
            }
            let allowed: Set<String> = ["name", "specifier", "path", "url"]
            guard Set(requirement.keys).isSubset(of: allowed),
                  case .string(let name)? = requirement["name"],
                  PythonPackageIdentity.isValidDistributionName(name)
            else { return .failure(.unsupportedInstallationLayout) }
            requirementNames.append(name)
            var specifier: String?
            if let specifierValue = requirement["specifier"] {
                guard case .string(let value) = specifierValue else {
                    return .failure(.manifestInvalid)
                }
                specifier = value
            }
            let constraint = PythonProofSupport.safeConstraint(name, specifier)
            if requirement["path"] != nil || requirement["url"] != nil {
                directSource = true
            }
            constraints.append(constraint)
        }
        guard PythonPackageIdentity.normalized(requirementNames[0])
            == PythonPackageIdentity.normalized(packageName)
        else { return .failure(.packageNameMismatch) }
        extras = Array(requirementNames.dropFirst())

        guard let entrypointsValue = tool["entrypoints"],
              case .array(let entrypointValues) = entrypointsValue
        else { return .failure(.manifestInvalid) }
        var matchingEntrypoints: [(name: String, installPath: String, from: String)] = []
        for value in entrypointValues {
            guard case .table(let entrypoint) = value else {
                return .failure(.manifestInvalid)
            }
            let allowed: Set<String> = ["name", "install-path", "from"]
            guard Set(entrypoint.keys).isSubset(of: allowed),
                  case .string(let name)? = entrypoint["name"],
                  case .string(let installPath)? = entrypoint["install-path"],
                  case .string(let from)? = entrypoint["from"]
            else { return .failure(.unsupportedInstallationLayout) }
            if name == executableName {
                matchingEntrypoints.append((name, installPath, from))
            }
        }
        guard matchingEntrypoints.count == 1, let entrypoint = matchingEntrypoints.first else {
            return .failure(matchingEntrypoints.isEmpty ? .executableNotDeclared : .ambiguousOwnership)
        }
        guard PythonProofSupport.isAbsolute(entrypoint.installPath),
              URL(fileURLWithPath: entrypoint.installPath).standardizedFileURL.path
                  == expectedInstallPath
        else { return .failure(.managerEntryMismatch) }
        guard PythonPackageIdentity.isValidDistributionName(entrypoint.from),
              PythonPackageIdentity.normalized(entrypoint.from)
                == PythonPackageIdentity.normalized(packageName)
        else { return .failure(.manifestExecutableMismatch) }

        var indexRecords: [IndexRecord] = []
        var topLevelIndexURL: String?
        var noIndex: Bool?
        if let optionsValue = tool["options"] {
            guard case .table(let options) = optionsValue else {
                return .failure(.manifestInvalid)
            }
            let allowedOptions: Set<String> = ["index", "index-url", "no-index"]
            guard Set(options.keys).isSubset(of: allowedOptions) else {
                return .failure(.unsupportedInstallationLayout)
            }
            if let indexValue = options["index"] {
                guard case .array(let indexes) = indexValue else {
                    return .failure(.manifestInvalid)
                }
                for index in indexes {
                    guard case .table(let entry) = index else { return .failure(.manifestInvalid) }
                    let allowedIndex: Set<String> = ["url", "explicit", "default", "format", "authenticate"]
                    guard Set(entry.keys).isSubset(of: allowedIndex),
                          case .string(let url)? = entry["url"],
                          !url.isEmpty
                    else { return .failure(.unsupportedInstallationLayout) }
                    var explicit: Bool?
                    if let value = entry["explicit"] {
                        guard case .bool(let bool) = value else { return .failure(.manifestInvalid) }
                        explicit = bool
                    }
                    var isDefault: Bool?
                    if let value = entry["default"] {
                        guard case .bool(let bool) = value else { return .failure(.manifestInvalid) }
                        isDefault = bool
                    }
                    var format: String?
                    if let value = entry["format"] {
                        guard case .string(let string) = value else { return .failure(.manifestInvalid) }
                        format = string
                    }
                    if let value = entry["authenticate"] {
                        guard case .string = value else { return .failure(.manifestInvalid) }
                    }
                    indexRecords.append(IndexRecord(
                        url: url, explicit: explicit, isDefault: isDefault, format: format
                    ))
                }
            }
            if let indexURLValue = options["index-url"] {
                guard case .string(let url) = indexURLValue, !url.isEmpty else {
                    return .failure(.manifestInvalid)
                }
                topLevelIndexURL = url
            }
            if let noIndexValue = options["no-index"] {
                guard case .bool(let value) = noIndexValue else {
                    return .failure(.manifestInvalid)
                }
                noIndex = value
            }
        }
        return .success(Receipt(
            constraints: constraints,
            extras: extras,
            entrypointInstallPath: entrypoint.installPath,
            indexRecords: indexRecords,
            topLevelIndexURL: topLevelIndexURL,
            noIndex: noIndex,
            directSource: directSource
        ))
    }
}

/// A tiny strict TOML subset parser for the observed uv receipt. It accepts only what the receipt
/// shape uses: tables `[tool]`/`[tool.options]`, bare keys, basic strings, booleans, integers,
/// arrays (including multiline arrays) and inline tables. Duplicate keys and duplicate table names
/// are rejected. It is intentionally not a general TOML implementation and never falls back to a
/// regex scan of malformed input.
private enum PythonReceiptTOML {
    enum Value: Equatable {
        case string(String)
        case bool(Bool)
        case integer(Int)
        case array([Value])
        case table([String: Value])
    }

    static let maximumDepth = 8
    static let maximumElements = 256

    static func parse(_ data: Data) -> [String: Value]? {
        guard !data.contains(0), !data.starts(with: [0xEF, 0xBB, 0xBF]) else { return nil }
        var parser = Parser(bytes: [UInt8](data))
        return parser.parseDocument()
    }

    private struct Parser {
        let bytes: [UInt8]
        var index = 0

        mutating func parseDocument() -> [String: Value]? {
            var root: [String: Value] = [:]
            var currentPath: [String] = []
            var seenSections = Set<String>()
            while true {
                skipTrivia()
                guard index < bytes.count else { return root }
                if bytes[index] == 0x5B { // [
                    guard let path = parseSectionHeader() else { return nil }
                    guard path == ["tool"] || path == ["tool", "options"] else { return nil }
                    let joined = path.joined(separator: ".")
                    guard seenSections.insert(joined).inserted else { return nil }
                    if !ensureTable(path: path, in: &root) { return nil }
                    currentPath = path
                } else {
                    // The observed receipt has no root-level keys; exact headers only.
                    guard !currentPath.isEmpty,
                          let key = parseKey(), skipTriviaAndExpect(0x3D),
                          let value = parseValue(depth: 0, allowNewlines: true),
                          requireLineEnd()
                    else { return nil }
                    guard insert(value, key: key, path: currentPath, root: &root) else { return nil }
                }
            }
        }

        private mutating func parseSectionHeader() -> [String]? {
            guard consume(0x5B) else { return nil }
            var path: [String] = []
            while true {
                guard let key = parseKey() else { return nil }
                path.append(key)
                skipInlineSpace()
                if consume(0x5D) {
                    guard requireLineEnd() else { return nil }
                    return path
                }
                guard consume(0x2E) else { return nil } // .
            }
        }

        private mutating func ensureTable(path: [String], in root: inout [String: Value]) -> Bool {
            var current = root
            func insertPath(_ remaining: ArraySlice<String>, into table: inout [String: Value]) -> Bool {
                guard let first = remaining.first else { return true }
                if remaining.count == 1 {
                    if let existing = table[first] {
                        if case .table = existing { return true }
                        return false
                    }
                    table[first] = .table([:])
                    return true
                }
                var child: [String: Value]
                if let existing = table[first] {
                    guard case .table(let tableValue) = existing else { return false }
                    child = tableValue
                } else {
                    child = [:]
                }
                guard insertPath(remaining.dropFirst(), into: &child) else { return false }
                table[first] = .table(child)
                return true
            }
            let ok = insertPath(path[...], into: &current)
            root = current
            return ok
        }

        private mutating func insert(
            _ value: Value,
            key: String,
            path: [String],
            root: inout [String: Value]
        ) -> Bool {
            if path.isEmpty {
                guard root[key] == nil else { return false }
                root[key] = value
                return true
            }
            var table: [String: Value]
            if let existing = root[path[0]] {
                guard case .table(let value) = existing else { return false }
                table = value
            } else {
                table = [:]
            }
            if path.count > 1 {
                var nested = table
                guard insert(value, key: key, path: Array(path.dropFirst()), root: &nested) else {
                    return false
                }
                table = nested
            } else {
                guard table[key] == nil else { return false }
                table[key] = value
            }
            root[path[0]] = .table(table)
            return true
        }

        private mutating func parseKey() -> String? {
            skipInlineSpace()
            let start = index
            while index < bytes.count {
                let byte = bytes[index]
                let isKey = (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A)
                    || (byte >= 0x30 && byte <= 0x39) || byte == 0x2D || byte == 0x5F
                if !isKey { break }
                index += 1
            }
            guard index > start else { return nil }
            return String(decoding: bytes[start..<index], as: UTF8.self)
        }

        private mutating func parseValue(depth: Int, allowNewlines: Bool) -> Value? {
            guard depth <= maximumDepth else { return nil }
            if allowNewlines { skipTrivia() } else { skipInlineSpace() }
            guard index < bytes.count else { return nil }
            switch bytes[index] {
            case 0x22:
                return parseString().map(Value.string)
            case 0x5B:
                return parseArray(depth: depth + 1, allowNewlines: allowNewlines).map(Value.array)
            case 0x7B:
                return parseInlineTable(depth: depth + 1).map(Value.table)
            case 0x74, 0x66:
                return parseBool().map(Value.bool)
            case 0x2D, 0x30...0x39:
                return parseInteger().map(Value.integer)
            default:
                return nil
            }
        }

        private mutating func parseString() -> String? {
            guard consume(0x22) else { return nil }
            var result: [UInt8] = []
            while index < bytes.count {
                let byte = bytes[index]
                if byte == 0x22 {
                    index += 1
                    return String(decoding: result, as: UTF8.self)
                }
                if byte == 0x5C {
                    index += 1
                    guard index < bytes.count else { return nil }
                    switch bytes[index] {
                    case 0x22: result.append(0x22)
                    case 0x5C: result.append(0x5C)
                    case 0x6E: result.append(0x0A)
                    case 0x72: result.append(0x0D)
                    case 0x74: result.append(0x09)
                    case 0x62: result.append(0x08)
                    case 0x66: result.append(0x0C)
                    case 0x75:
                        guard index + 4 < bytes.count,
                              let scalar = UInt32(
                                String(decoding: bytes[(index + 1)...(index + 4)], as: UTF8.self),
                                radix: 16
                              ),
                              let unicode = UnicodeScalar(scalar)
                        else { return nil }
                        result.append(contentsOf: String(unicode).utf8)
                        index += 4
                    default: return nil
                    }
                    index += 1
                    continue
                }
                guard byte >= 0x20, byte != 0x7F else { return nil }
                result.append(byte)
                index += 1
            }
            return nil
        }

        private mutating func parseBool() -> Bool? {
            if bytes[index...].starts(with: Array("true".utf8)) {
                index += 4
                return true
            }
            if bytes[index...].starts(with: Array("false".utf8)) {
                index += 5
                return false
            }
            return nil
        }

        private mutating func parseInteger() -> Int? {
            let start = index
            if bytes[index] == 0x2D { index += 1 }
            let digitStart = index
            while index < bytes.count, bytes[index] >= 0x30, bytes[index] <= 0x39 {
                index += 1
            }
            guard index > digitStart else { return nil }
            return Int(String(decoding: bytes[start..<index], as: UTF8.self))
        }

        private mutating func parseArray(depth: Int, allowNewlines: Bool) -> [Value]? {
            guard depth <= maximumDepth, consume(0x5B) else { return nil }
            var values: [Value] = []
            while true {
                if allowNewlines { skipTrivia() } else { skipInlineSpace() }
                if consume(0x5D) { return values }
                guard values.count < maximumElements,
                      let value = parseValue(depth: depth, allowNewlines: allowNewlines)
                else { return nil }
                values.append(value)
                if allowNewlines { skipTrivia() } else { skipInlineSpace() }
                if consume(0x2C) { continue }
                guard consume(0x5D) else { return nil }
                return values
            }
        }

        private mutating func parseInlineTable(depth: Int) -> [String: Value]? {
            guard depth <= maximumDepth, consume(0x7B) else { return nil }
            var table: [String: Value] = [:]
            while true {
                skipInlineSpace()
                if consume(0x7D) { return table }
                guard table.count < maximumElements,
                      let key = parseKey(), skipInlineSpaceAndExpect(0x3D),
                      let value = parseValue(depth: depth, allowNewlines: false),
                      table[key] == nil
                else { return nil }
                table[key] = value
                skipInlineSpace()
                if consume(0x2C) { continue }
                guard consume(0x7D) else { return nil }
                return table
            }
        }

        private mutating func skipTrivia() {
            while index < bytes.count {
                switch bytes[index] {
                case 0x20, 0x09, 0x0A, 0x0D:
                    index += 1
                case 0x23:
                    while index < bytes.count, bytes[index] != 0x0A { index += 1 }
                default:
                    return
                }
            }
        }

        private mutating func skipInlineSpace() {
            while index < bytes.count, bytes[index] == 0x20 || bytes[index] == 0x09 {
                index += 1
            }
        }

        private mutating func requireLineEnd() -> Bool {
            skipInlineSpace()
            if index < bytes.count, bytes[index] == 0x23 {
                while index < bytes.count, bytes[index] != 0x0A { index += 1 }
            }
            guard index < bytes.count else { return true }
            if bytes[index] == 0x0D {
                index += 1
                guard index < bytes.count, bytes[index] == 0x0A else { return false }
                index += 1
                return true
            }
            if bytes[index] == 0x0A {
                index += 1
                return true
            }
            return false
        }

        private mutating func skipTriviaAndExpect(_ byte: UInt8) -> Bool {
            skipTrivia()
            return consume(byte)
        }

        private mutating func skipInlineSpaceAndExpect(_ byte: UInt8) -> Bool {
            skipInlineSpace()
            return consume(byte)
        }

        private mutating func consume(_ byte: UInt8) -> Bool {
            guard index < bytes.count, bytes[index] == byte else { return false }
            index += 1
            return true
        }
    }
}

private extension Array where Element == UInt8 {
    func starts(with other: [UInt8]) -> Bool {
        count >= other.count && Array(prefix(other.count)) == other
    }
}
