import Darwin
import Foundation

public enum PathCandidateKind: Equatable, Sendable {
    case executableFile
    case executableSymlink
    case brokenSymlink
    case symlinkTargetUnavailable
    case symlinkToDirectory
    case symlinkToNonExecutableFile
    case symlinkToNonRegular(type: String)
    case nonExecutableFile
    case directory
    case nonRegular(type: String)

    public var isLiveExecutable: Bool {
        switch self {
        case .executableFile, .executableSymlink:
            true
        default:
            false
        }
    }

    public var label: String {
        switch self {
        case .executableFile: "executable file"
        case .executableSymlink: "executable symlink"
        case .brokenSymlink: "broken symlink"
        case .symlinkTargetUnavailable: "symlink target unavailable"
        case .symlinkToDirectory: "symlink to directory"
        case .symlinkToNonExecutableFile: "symlink to non-executable file"
        case .symlinkToNonRegular(let type): "symlink to \(type)"
        case .nonExecutableFile: "non-executable file"
        case .directory: "directory"
        case .nonRegular(let type): type
        }
    }
}

public enum PathCandidateOrigin: Equatable, Sendable {
    case path(slotIndex: Int, directoryText: String)
    case extraRoot(index: Int, directoryText: String)
}

public struct PathCandidateObservation: Equatable, Sendable {
    public let origin: PathCandidateOrigin
    public let entryPath: String
    public let kind: PathCandidateKind
    public let canonicalTarget: String?

    public init(
        origin: PathCandidateOrigin,
        entryPath: String,
        kind: PathCandidateKind,
        canonicalTarget: String?
    ) {
        self.origin = origin
        self.entryPath = entryPath
        self.kind = kind
        self.canonicalTarget = canonicalTarget
    }
}

public struct PathTargetGroup: Equatable, Sendable {
    public let canonicalTarget: String
    public let entryPaths: [String]
    public let firstSlotIndex: Int

    public init(canonicalTarget: String, entryPaths: [String], firstSlotIndex: Int) {
        self.canonicalTarget = canonicalTarget
        self.entryPaths = entryPaths
        self.firstSlotIndex = firstSlotIndex
    }
}

public enum PathSelection: Equatable, Sendable {
    case winner(PathCandidateObservation)
    case offPath(candidate: PathCandidateObservation, root: String)
    case notInstalled
    case inconsistent(String)
}

public struct ToolPathDiagnostic: Equatable, Sendable {
    public let detectedTool: DetectedTool
    public let pathCandidates: [PathCandidateObservation]
    public let firstLiveCandidate: PathCandidateObservation?
    public let targetGroups: [PathTargetGroup]
    public let repeatedPathSlotCount: Int
    public let sameTargetAliasCount: Int
    public let selection: PathSelection
    public let shadowedInstallationCount: Int?

    public init(
        detectedTool: DetectedTool,
        pathCandidates: [PathCandidateObservation],
        firstLiveCandidate: PathCandidateObservation?,
        targetGroups: [PathTargetGroup],
        repeatedPathSlotCount: Int,
        sameTargetAliasCount: Int,
        selection: PathSelection,
        shadowedInstallationCount: Int?
    ) {
        self.detectedTool = detectedTool
        self.pathCandidates = pathCandidates
        self.firstLiveCandidate = firstLiveCandidate
        self.targetGroups = targetGroups
        self.repeatedPathSlotCount = repeatedPathSlotCount
        self.sameTargetAliasCount = sameTargetAliasCount
        self.selection = selection
        self.shadowedInstallationCount = shadowedInstallationCount
    }

    public var liveCandidates: [PathCandidateObservation] {
        pathCandidates.filter { $0.kind.isLiveExecutable }
    }

    public var invalidCandidates: [PathCandidateObservation] {
        pathCandidates.filter { !$0.kind.isLiveExecutable }
    }

    public var distinctLiveEntryPathCount: Int {
        Set(liveCandidates.map(\.entryPath)).count
    }

    public var canonicalTargetCount: Int {
        targetGroups.count
    }
}

public enum PathDiagnosticsScanner {
    public static func scan(
        detector: ToolDetector,
        environment: ShellEnvironment,
        currentDirectory: String = FileManager.default.currentDirectoryPath
    ) -> ToolPathDiagnostic {
        let detected = detector.detect(in: environment)
        let workingDirectory = URL(
            fileURLWithPath: currentDirectory,
            isDirectory: true
        ).standardizedFileURL
        let pathCandidates = environment.pathEntries.enumerated().compactMap { slot, directoryText in
            let candidate = candidatePath(
                directoryText: directoryText,
                executableName: detector.executableName,
                workingDirectory: workingDirectory
            )
            return inspectCandidate(
                entryPath: candidate,
                origin: .path(slotIndex: slot, directoryText: directoryText)
            )
        }
        let liveCandidates = pathCandidates.filter { $0.kind.isLiveExecutable }
        let firstLiveCandidate = liveCandidates.first
        let targetGroups = makeTargetGroups(liveCandidates)
        let repeatedPathSlotCount = pathCandidates.count - Set(pathCandidates.map(\.entryPath)).count
        let sameTargetAliasCount = targetGroups.reduce(0) { $0 + max(0, $1.entryPaths.count - 1) }

        let selection: PathSelection
        if let firstLiveCandidate {
            selection = verifyPathWinner(
                firstLiveCandidate,
                detected: detected,
                workingDirectory: workingDirectory
            )
        } else {
            let extraCandidate = findExtraRootCandidate(detector: detector, workingDirectory: workingDirectory)
            if let extraCandidate {
                selection = verifyOffPathCandidate(
                    extraCandidate.candidate,
                    root: extraCandidate.root,
                    detected: detected,
                    workingDirectory: workingDirectory
                )
            } else if detected.state == .notInstalled {
                selection = .notInstalled
            } else {
                selection = .inconsistent(
                    "the detector selected an executable, but no live PATH or declared extra-root candidate was found"
                )
            }
        }
        let shadowedInstallationCount: Int?
        switch selection {
        case .winner:
            shadowedInstallationCount = max(0, targetGroups.count - 1)
        case .notInstalled:
            shadowedInstallationCount = 0
        case .offPath:
            shadowedInstallationCount = 0
        case .inconsistent:
            shadowedInstallationCount = nil
        }
        return ToolPathDiagnostic(
            detectedTool: detected,
            pathCandidates: pathCandidates,
            firstLiveCandidate: firstLiveCandidate,
            targetGroups: targetGroups,
            repeatedPathSlotCount: repeatedPathSlotCount,
            sameTargetAliasCount: sameTargetAliasCount,
            selection: selection,
            shadowedInstallationCount: shadowedInstallationCount
        )
    }

    private static func candidatePath(
        directoryText: String,
        executableName: String,
        workingDirectory: URL
    ) -> String {
        let directory = directoryText.isEmpty
            ? workingDirectory
            : URL(
                fileURLWithPath: directoryText,
                isDirectory: true,
                relativeTo: workingDirectory
            ).standardizedFileURL
        return directory.appendingPathComponent(executableName).standardizedFileURL.path
    }

    private static func inspectCandidate(
        entryPath: String,
        origin: PathCandidateOrigin
    ) -> PathCandidateObservation? {
        var entryInfo = stat()
        guard entryPath.withCString({ Darwin.lstat($0, &entryInfo) }) == 0 else { return nil }

        let isSymlink = (entryInfo.st_mode & mode_t(S_IFMT)) == mode_t(S_IFLNK)
        var targetInfo = entryInfo
        if isSymlink {
            let (targetStatus, targetError) = entryPath.withCString { path -> (Int32, Int32) in
                let status = Darwin.fstatat(AT_FDCWD, path, &targetInfo, 0)
                return (status, status == 0 ? 0 : errno)
            }
            guard targetStatus == 0 else {
                let kind: PathCandidateKind = (targetError == ENOENT || targetError == ENOTDIR)
                    ? .brokenSymlink
                    : .symlinkTargetUnavailable
                return PathCandidateObservation(
                    origin: origin,
                    entryPath: entryPath,
                    kind: kind,
                    canonicalTarget: nil
                )
            }
        }

        let targetType = targetInfo.st_mode & mode_t(S_IFMT)
        let kind: PathCandidateKind
        let isLive: Bool
        if targetType == mode_t(S_IFREG) {
            let executable = entryPath.withCString({ Darwin.access($0, X_OK) }) == 0
            if isSymlink {
                kind = executable ? .executableSymlink : .symlinkToNonExecutableFile
            } else {
                kind = executable ? .executableFile : .nonExecutableFile
            }
            isLive = executable
        } else if targetType == mode_t(S_IFDIR) {
            kind = isSymlink ? .symlinkToDirectory : .directory
            isLive = false
        } else {
            let type = filesystemType(targetType)
            kind = isSymlink ? .symlinkToNonRegular(type: type) : .nonRegular(type: type)
            isLive = false
        }

        let target = isLive
            ? URL(fileURLWithPath: entryPath).resolvingSymlinksInPath().standardizedFileURL.path
            : nil
        return PathCandidateObservation(
            origin: origin,
            entryPath: entryPath,
            kind: kind,
            canonicalTarget: target
        )
    }

    private static func filesystemType(_ type: mode_t) -> String {
        switch type {
        case mode_t(S_IFIFO): "fifo"
        case mode_t(S_IFCHR): "character device"
        case mode_t(S_IFBLK): "block device"
        case mode_t(S_IFSOCK): "socket"
        default: "other non-regular entry"
        }
    }

    private static func findExtraRootCandidate(
        detector: ToolDetector,
        workingDirectory: URL
    ) -> (candidate: PathCandidateObservation, root: String)? {
        for (index, configuredRoot) in detector.extraSearchRoots.enumerated() {
            let expandedRoot = ToolDetector.expandTilde(configuredRoot)
            let entryPath = candidatePath(
                directoryText: expandedRoot,
                executableName: detector.executableName,
                workingDirectory: workingDirectory
            )
            guard let candidate = inspectCandidate(
                entryPath: entryPath,
                origin: .extraRoot(index: index, directoryText: configuredRoot)
            ), candidate.kind.isLiveExecutable else {
                continue
            }
            return (candidate, configuredRoot)
        }
        return nil
    }

    private static func verifyOffPathCandidate(
        _ candidate: PathCandidateObservation,
        root: String,
        detected: DetectedTool,
        workingDirectory: URL
    ) -> PathSelection {
        guard detected.state == .installedNotOnPath else {
            return .inconsistent(
                "the diagnostic found a declared extra-root executable, but the detector reported \(detected.state.rawValue)"
            )
        }
        guard let detectedEntry = detected.entryPath,
              let detectedTarget = detected.resolvedPath,
              let diagnosticTarget = candidate.canonicalTarget
        else {
            return .inconsistent("the detector did not return both an off-PATH entry and resolved target")
        }
        let normalizedEntry = URL(
            fileURLWithPath: detectedEntry,
            relativeTo: workingDirectory
        ).standardizedFileURL.path
        let normalizedTarget = URL(
            fileURLWithPath: detectedTarget,
            relativeTo: workingDirectory
        ).standardizedFileURL.path
        guard normalizedEntry == candidate.entryPath else {
            return .inconsistent(
                "the detector off-PATH entry \(normalizedEntry) does not match the declared extra-root entry \(candidate.entryPath)"
            )
        }
        guard normalizedTarget == diagnosticTarget else {
            return .inconsistent(
                "the detector target \(normalizedTarget) does not match the declared extra-root target \(diagnosticTarget)"
            )
        }
        return .offPath(candidate: candidate, root: root)
    }

    private static func makeTargetGroups(
        _ candidates: [PathCandidateObservation]
    ) -> [PathTargetGroup] {
        var groups: [PathTargetGroup] = []
        for candidate in candidates {
            guard let target = candidate.canonicalTarget,
                  case .path(let slotIndex, _) = candidate.origin
            else {
                continue
            }
            if let index = groups.firstIndex(where: { $0.canonicalTarget == target }) {
                var entryPaths = groups[index].entryPaths
                if !entryPaths.contains(candidate.entryPath) {
                    entryPaths.append(candidate.entryPath)
                    groups[index] = PathTargetGroup(
                        canonicalTarget: target,
                        entryPaths: entryPaths,
                        firstSlotIndex: groups[index].firstSlotIndex
                    )
                }
            } else {
                groups.append(PathTargetGroup(
                    canonicalTarget: target,
                    entryPaths: [candidate.entryPath],
                    firstSlotIndex: slotIndex
                ))
            }
        }
        return groups.sorted { $0.firstSlotIndex < $1.firstSlotIndex }
    }

    private static func verifyPathWinner(
        _ candidate: PathCandidateObservation,
        detected: DetectedTool,
        workingDirectory: URL
    ) -> PathSelection {
        guard detected.state == .installedAndOnPath else {
            return .inconsistent(
                "the diagnostic found a live PATH entry, but the detector reported \(detected.state.rawValue)"
            )
        }
        guard let detectedEntry = detected.entryPath,
              let detectedTarget = detected.resolvedPath,
              let diagnosticTarget = candidate.canonicalTarget
        else {
            return .inconsistent("the detector did not return both a selected entry and resolved target")
        }

        let normalizedEntry = URL(
            fileURLWithPath: detectedEntry,
            relativeTo: workingDirectory
        ).standardizedFileURL.path
        let normalizedTarget = URL(
            fileURLWithPath: detectedTarget,
            relativeTo: workingDirectory
        ).standardizedFileURL.path
        guard normalizedEntry == candidate.entryPath else {
            return .inconsistent(
                "the detector entry \(normalizedEntry) does not match the first live PATH entry \(candidate.entryPath)"
            )
        }
        guard normalizedTarget == diagnosticTarget else {
            return .inconsistent(
                "the detector target \(normalizedTarget) does not match the first live PATH target \(diagnosticTarget)"
            )
        }
        return .winner(candidate)
    }
}
