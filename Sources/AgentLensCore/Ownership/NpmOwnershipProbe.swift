// NpmOwnershipProbe — read-only npm-global ownership proof (M9-B).
//
// Exactly two manager queries are possible: `npm prefix --global` and `npm root --global`.
// Declared npm candidates are inspected through their own package.json only (bounded regular-file
// read, maximum 1 MiB). A declaration alone never proves ownership; the manager's bin entry and
// the selected canonical executable must agree with the manifest's binding.
//
// The manifest is opened relative to a verified package-directory descriptor. Every directory
// component is walked with O_NOFOLLOW, so a replaced ancestor cannot redirect the read outside the
// package. `package.json` itself must be a regular file: the descriptor is opened nonblocking and
// validated with fstat before any read, so a FIFO, socket, device, directory or symlink cannot
// block or escape.

import Darwin
import Foundation

enum NpmOwnershipProbeTestHooks {
    /// Dormant outside tests. Invoked after the package directory identity is observed and before
    /// the anchored descriptor walk opens `package.json`, so a test can deterministically retarget
    /// a declared lexical package link or replace an ancestor between observation and open.
    @TaskLocal static var onBeforeAnchoredManifestOpen: (@Sendable () -> Void)?

    /// Dormant outside tests. Invoked immediately before the declared package bin is observed, so
    /// a test can deterministically retarget it after the lexical pre-check and exercise the
    /// containment check against the observation actually used as proof.
    @TaskLocal static var onBeforeBinObservation: (@Sendable () -> Void)?
}

struct NpmOwnershipProbe {

    private static let maximumManifestBytes = 1024 * 1024

    private enum QueryOutcome {
        case success(Data)
        case failure(CommandFailure)
    }

    private enum CandidateOutcome {
        case verified(VerifiedInstallation, NpmProof)
        case failed(InstallationOwnershipReason)
    }

    private struct ParsedManifest {
        let packageName: String
        let binRelativePath: String
    }

    private struct NpmProof {
        let manager: ObservedExecutable
        let selection: ObservedExecutable
        /// The exact paths npm reported, retained so a retargeted lexical spelling cannot keep an
        /// old canonical store's proof.
        let prefixLexicalPath: String
        let rootLexicalPath: String
        let prefix: DirectoryIdentity
        let root: DirectoryIdentity
        /// The declared `<root>/<package>` spelling, which may be a link into an in-root store.
        let packageLexicalPath: String
        let package: DirectoryIdentity
        let prefixBinLexicalPath: String
        let prefixBin: DirectoryIdentity
        let manifestLexicalPath: String
        let manifest: FileIdentity
        let bin: ObservedExecutable
        let managerBin: ObservedExecutable

        func revalidate() -> InstallationOwnershipReason? {
            if let reason = NpmOwnershipProbe.revalidate(selection: selection, manager: manager) {
                return reason
            }
            guard FileIdentityObserver.observeDirectory(path: prefixLexicalPath) == prefix,
                  FileIdentityObserver.observeDirectory(path: rootLexicalPath) == root,
                  FileIdentityObserver.observeDirectory(path: prefix.canonicalPath) == prefix,
                  FileIdentityObserver.observeDirectory(path: root.canonicalPath) == root,
                  FileIdentityObserver.observeDirectory(path: packageLexicalPath) == package,
                  FileIdentityObserver.observeDirectory(path: package.canonicalPath) == package,
                  FileIdentityObserver.observeDirectory(path: prefixBinLexicalPath) == prefixBin,
                  FileIdentityObserver.observeDirectory(path: prefixBin.canonicalPath) == prefixBin
            else {
                return .proofChanged
            }
            guard FileIdentityObserver.observeFile(path: manifestLexicalPath) == manifest,
                  FileIdentityObserver.observeFile(path: manifest.canonicalPath) == manifest
            else {
                return .proofChanged
            }
            guard let currentBin = FileIdentityObserver.observeExecutable(entryPath: bin.entryPath),
                  currentBin == bin
            else {
                return .proofChanged
            }
            guard let currentManagerBin = FileIdentityObserver.observeExecutable(
                entryPath: managerBin.entryPath
            ), currentManagerBin == managerBin,
            currentManagerBin.canonicalTarget == selection.canonicalTarget,
            currentManagerBin.fingerprint == selection.fingerprint
            else {
                return .managerEntryMismatch
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

        let prefixText: String
        switch await query(
            manager: manager,
            arguments: ["prefix", "--global"],
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
        if let reason = revalidate(selection: selection, manager: manager) {
            return .unknown(reason)
        }

        let rootText: String
        switch await query(
            manager: manager,
            arguments: ["root", "--global"],
            environment: environment,
            runner: runner
        ) {
        case .failure(let failure):
            return .unknown(reason(for: failure))
        case .success(let data):
            guard let parsed = ManagerOutputParser.singleAbsolutePath(data) else {
                return .unknown(.invalidManagerOutput)
            }
            rootText = parsed
        }
        if let reason = revalidate(selection: selection, manager: manager) {
            return .unknown(reason)
        }

        let prefixLexicalPath = URL(fileURLWithPath: prefixText).standardizedFileURL.path
        let rootLexicalPath = URL(fileURLWithPath: rootText).standardizedFileURL.path
        guard let prefix = FileIdentityObserver.observeDirectory(path: prefixLexicalPath),
              let root = FileIdentityObserver.observeDirectory(path: rootLexicalPath)
        else {
            return .unknown(.unsupportedInstallationLayout)
        }
        // Identity equality alone is insufficient: `<prefix>/lib/node_modules` may be a symlink
        // into another prefix whose directory identity is then equal to the reported root. The
        // canonical root must be exactly the prefix followed by `lib/node_modules`, by components.
        guard FileIdentityObserver.isExactDescendant(
            root.canonicalPath,
            of: prefix.canonicalPath,
            components: ["lib", "node_modules"]
        ) else {
            return .unknown(.managerRootMismatch)
        }

        let packages = definition.packages.filter { $0.manager == .npm }
        guard !packages.isEmpty else { return .unknown(.noDeclaredPackage) }

        var matches: [(VerifiedInstallation, NpmProof)] = []
        var firstFailure: InstallationOwnershipReason?
        for package in packages {
            if Task.isCancelled { return .unknown(.cancelled) }
            switch inspect(
                package: package,
                executableName: definition.executableName,
                selection: selection,
                manager: manager,
                prefixLexicalPath: prefixLexicalPath,
                rootLexicalPath: rootLexicalPath,
                prefix: prefix,
                root: root
            ) {
            case .verified(let installation, let proof):
                matches.append((installation, proof))
            case .failed(let reason):
                if firstFailure == nil { firstFailure = reason }
            }
        }

        guard !matches.isEmpty else {
            return .unknown(firstFailure ?? .noMatchingPackage)
        }
        guard matches.count == 1, let match = matches.first else {
            return .unknown(.ambiguousOwnership)
        }
        if Task.isCancelled { return .unknown(.cancelled) }
        if let failure = match.1.revalidate() { return .unknown(failure) }
        if let reason = revalidate(selection: selection, manager: manager) {
            return .unknown(reason)
        }
        return .verified(match.0)
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
            environment: environment.raw,
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

    private static func inspect(
        package: DeclaredPackage,
        executableName: String,
        selection: ObservedExecutable,
        manager: ObservedExecutable,
        prefixLexicalPath: String,
        rootLexicalPath: String,
        prefix: DirectoryIdentity,
        root: DirectoryIdentity
    ) -> CandidateOutcome {
        var packageURL = URL(fileURLWithPath: rootLexicalPath, isDirectory: true)
        let components = package.name.split(separator: "/", omittingEmptySubsequences: false)
        guard (1...2).contains(components.count),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else {
            return .failed(.packagePathUnsafe)
        }
        for component in components {
            packageURL.appendPathComponent(String(component), isDirectory: true)
        }
        let lexicalPackage = packageURL.standardizedFileURL
        guard FileIdentityObserver.isStrictDescendant(lexicalPackage.path, of: rootLexicalPath)
        else {
            return .failed(.packagePathUnsafe)
        }
        guard let packageIdentity = FileIdentityObserver.observeDirectory(path: lexicalPackage.path)
        else {
            return .failed(.packageNotInstalled)
        }
        guard FileIdentityObserver.isStrictDescendant(
            packageIdentity.canonicalPath,
            of: root.canonicalPath
        ) else {
            return .failed(.packagePathUnsafe)
        }

        let prefixBinLexicalPath = URL(fileURLWithPath: prefixLexicalPath, isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true).path
        guard let prefixBin = FileIdentityObserver.observeDirectory(path: prefixBinLexicalPath)
        else {
            return .failed(.managerEntryMismatch)
        }
        guard FileIdentityObserver.isStrictDescendant(
            prefixBin.canonicalPath,
            of: prefix.canonicalPath
        ) else {
            return .failed(.managerEntryMismatch)
        }

        let manifestLexicalPath = URL(fileURLWithPath: lexicalPackage.path, isDirectory: true)
            .appendingPathComponent("package.json")
            .path
        let manifest: ParsedManifest
        let manifestIdentity: FileIdentity
        switch readManifest(
            packageDirectory: packageIdentity,
            expectedPackageName: package.name,
            executableName: executableName
        ) {
        case .failure(let reason):
            return .failed(reason)
        case .success(let parsed, let identity):
            manifest = parsed
            manifestIdentity = identity
        }
        guard manifest.packageName == package.name else {
            return .failed(.packageNameMismatch)
        }

        let bin: ObservedExecutable
        switch resolveBin(
            manifest.binRelativePath,
            packageRoot: packageIdentity.canonicalPath,
            selection: selection
        ) {
        case .failure(let reason):
            return .failed(reason)
        case .success(let observed):
            bin = observed
        }

        let managerBinPath = URL(fileURLWithPath: prefixBinLexicalPath, isDirectory: true)
            .appendingPathComponent(executableName)
            .path
        guard let managerBin = FileIdentityObserver.observeExecutable(entryPath: managerBinPath)
        else {
            return .failed(.managerEntryMismatch)
        }
        guard managerBin.canonicalTarget == selection.canonicalTarget,
              managerBin.fingerprint == selection.fingerprint
        else {
            return .failed(.managerEntryMismatch)
        }

        let installation = VerifiedInstallation(
            manager: .npm,
            packageName: package.name,
            managerEntryPath: manager.entryPath,
            managerTarget: manager.canonicalTarget,
            managerFingerprint: manager.fingerprint,
            managerRoot: prefix.canonicalPath,
            installationRoot: packageIdentity.canonicalPath,
            selection: InstallationSelectionIdentity(
                entryPath: selection.entryPath,
                canonicalTarget: selection.canonicalTarget,
                fingerprint: selection.fingerprint
            )
        )
        let proof = NpmProof(
            manager: manager,
            selection: selection,
            prefixLexicalPath: prefixLexicalPath,
            rootLexicalPath: rootLexicalPath,
            prefix: prefix,
            root: root,
            packageLexicalPath: lexicalPackage.path,
            package: packageIdentity,
            prefixBinLexicalPath: prefixBinLexicalPath,
            prefixBin: prefixBin,
            manifestLexicalPath: manifestLexicalPath,
            manifest: manifestIdentity,
            bin: bin,
            managerBin: managerBin
        )
        return .verified(installation, proof)
    }

    private enum ManifestReadOutcome {
        case success(ParsedManifest, FileIdentity)
        case failure(InstallationOwnershipReason)
    }

    private static func readManifest(
        packageDirectory: DirectoryIdentity,
        expectedPackageName: String,
        executableName: String
    ) -> ManifestReadOutcome {
        NpmOwnershipProbeTestHooks.onBeforeAnchoredManifestOpen?()

        guard let packageDescriptor = FileIdentityObserver.openVerifiedDirectory(
            path: packageDirectory.canonicalPath,
            expected: packageDirectory
        ) else {
            return .failure(.packagePathUnsafe)
        }
        defer { _ = close(packageDescriptor) }

        // Reject an obviously non-regular final component before opening it (a device can have
        // open-side effects even with O_NONBLOCK). The descriptor-level fstat below remains the
        // authority against a replacement between this check and the open.
        var pathInfo = stat()
        let pathStatus = "package.json".withCString {
            fstatat(packageDescriptor, $0, &pathInfo, AT_SYMLINK_NOFOLLOW)
        }
        if pathStatus == 0, !FileIdentityObserver.isRegular(pathInfo.st_mode) {
            return .failure(.manifestUnreadable)
        }

        let descriptor = "package.json".withCString {
            openat(
                packageDescriptor,
                $0,
                O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC
            )
        }
        guard descriptor >= 0 else {
            if errno == ENOENT || errno == ENOTDIR { return .failure(.manifestMissing) }
            return .failure(.manifestUnreadable)
        }
        defer { _ = close(descriptor) }

        var info = stat()
        guard fstat(descriptor, &info) == 0, FileIdentityObserver.isRegular(info.st_mode) else {
            return .failure(.manifestUnreadable)
        }
        guard info.st_size >= 0, UInt64(info.st_size) <= UInt64(maximumManifestBytes) else {
            return .failure(.manifestTooLarge)
        }

        var data = Data()
        data.reserveCapacity(Int(info.st_size))
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { bytes -> Int in
                guard let base = bytes.baseAddress else { return 0 }
                return Darwin.read(descriptor, base, bytes.count)
            }
            if count < 0 { return .failure(.manifestUnreadable) }
            if count == 0 { break }
            if data.count + count > maximumManifestBytes {
                return .failure(.manifestTooLarge)
            }
            data.append(contentsOf: buffer[0..<count])
        }
        guard data.count == Int(info.st_size) else {
            return .failure(.manifestUnreadable)
        }

        let canonicalManifestPath = URL(
            fileURLWithPath: packageDirectory.canonicalPath,
            isDirectory: true
        )
        .appendingPathComponent("package.json")
        .path
        let identity = FileIdentity(
            canonicalPath: canonicalManifestPath,
            fingerprint: FileIdentityObserver.fingerprint(info)
        )
        // Validate the original bounded bytes; no String re-encode, no duplicate full copy.
        guard !data.contains(0x00),
              !data.starts(with: [0xEF, 0xBB, 0xBF]),
              String(data: data, encoding: .utf8) != nil
        else {
            return .failure(.manifestInvalid)
        }
        guard let object = try? JSONSerialization.jsonObject(with: data, options: []),
              let manifest = object as? [String: Any]
        else {
            return .failure(.manifestInvalid)
        }
        guard let name = manifest["name"] as? String else {
            return .failure(.manifestInvalid)
        }
        guard name == expectedPackageName else {
            return .failure(.packageNameMismatch)
        }
        let binRelativePath: String
        if let bin = manifest["bin"] as? [String: Any] {
            guard let declared = bin[executableName] else {
                return .failure(.executableNotDeclared)
            }
            guard let path = declared as? String else {
                return .failure(.manifestInvalid)
            }
            binRelativePath = path
        } else if let bin = manifest["bin"] as? String {
            guard manifestName(packageName: name) == executableName else {
                return .failure(.executableNotDeclared)
            }
            binRelativePath = bin
        } else if manifest["bin"] == nil {
            return .failure(.executableNotDeclared)
        } else {
            return .failure(.manifestInvalid)
        }
        return .success(
            ParsedManifest(packageName: name, binRelativePath: binRelativePath),
            identity
        )
    }

    private static func manifestName(packageName: String) -> String {
        packageName.split(separator: "/").last.map(String.init) ?? packageName
    }

    private enum BinOutcome {
        case success(ObservedExecutable)
        case failure(InstallationOwnershipReason)
    }

    private static func resolveBin(
        _ relative: String,
        packageRoot: String,
        selection: ObservedExecutable
    ) -> BinOutcome {
        guard !relative.isEmpty,
              !relative.contains("\0"),
              !relative.hasPrefix("/")
        else {
            return .failure(.executableOutsidePackage)
        }
        let components = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != ".." })
        else {
            return .failure(.executableOutsidePackage)
        }

        let lexical = URL(fileURLWithPath: packageRoot, isDirectory: true)
            .appendingPathComponent(relative)
            .standardizedFileURL
        guard FileIdentityObserver.isStrictDescendant(lexical.path, of: packageRoot) else {
            return .failure(.executableOutsidePackage)
        }
        NpmOwnershipProbeTestHooks.onBeforeBinObservation?()
        // Contain the exact observation that will become the proof. A pre-resolution snapshot
        // could disagree with observeExecutable after a bin-link retarget.
        guard let observed = FileIdentityObserver.observeExecutable(entryPath: lexical.path),
              FileIdentityObserver.isStrictDescendant(observed.canonicalTarget, of: packageRoot)
        else {
            return .failure(.executableOutsidePackage)
        }
        guard observed.canonicalTarget == selection.canonicalTarget,
              observed.fingerprint == selection.fingerprint
        else {
            return .failure(.manifestExecutableMismatch)
        }
        return .success(observed)
    }
}
