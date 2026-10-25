import Darwin
import Dispatch
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
    /// One local version observation per observed canonical target, plus the selected off-PATH
    /// target when that is the existing selection. Empty in manually constructed fixtures means
    /// "no measurement", never a fabricated known version.
    public let installationVersions: [InstallationVersionObservation]

    public init(
        detectedTool: DetectedTool,
        pathCandidates: [PathCandidateObservation],
        firstLiveCandidate: PathCandidateObservation?,
        targetGroups: [PathTargetGroup],
        repeatedPathSlotCount: Int,
        sameTargetAliasCount: Int,
        selection: PathSelection,
        shadowedInstallationCount: Int?,
        installationVersions: [InstallationVersionObservation]
    ) {
        self.detectedTool = detectedTool
        self.pathCandidates = pathCandidates
        self.firstLiveCandidate = firstLiveCandidate
        self.targetGroups = targetGroups
        self.repeatedPathSlotCount = repeatedPathSlotCount
        self.sameTargetAliasCount = sameTargetAliasCount
        self.selection = selection
        self.shadowedInstallationCount = shadowedInstallationCount
        self.installationVersions = installationVersions
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
        scan(
            detector: detector,
            environment: environment,
            currentDirectory: currentDirectory,
            monotonicNow: { DispatchTime.now().uptimeNanoseconds }
        )
    }

    /// Internal monotonic-clock seam for deterministic aggregate-budget tests. Production uses
    /// the public `scan`, which passes the process's uptime clock; there is no fixture flag or
    /// mutable global clock.
    static func scan(
        detector: ToolDetector,
        environment: ShellEnvironment,
        currentDirectory: String,
        monotonicNow: @Sendable () -> UInt64
    ) -> ToolPathDiagnostic {
        let location = detector.locate(in: environment)
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

        var selection: PathSelection
        if let firstLiveCandidate {
            selection = verifyPathWinner(
                firstLiveCandidate,
                location: location,
                workingDirectory: workingDirectory
            )
        } else {
            let extraCandidate = findExtraRootCandidate(detector: detector, workingDirectory: workingDirectory)
            if let extraCandidate {
                selection = verifyOffPathCandidate(
                    extraCandidate.candidate,
                    root: extraCandidate.root,
                    location: location,
                    workingDirectory: workingDirectory
                )
            } else if location.state == .notInstalled {
                selection = .notInstalled
            } else {
                selection = .inconsistent(
                    "the detector selected an executable, but no live PATH or declared extra-root candidate was found"
                )
            }
        }

        let selectedCandidate = selectionCandidate(in: selection)
        let probeTargets = installationProbeTargets(
            selection: selection,
            groups: targetGroups,
            pathEntries: environment.pathEntries
        )
        let collection = InstallationVersionCollector.collect(
            targets: probeTargets,
            selectedEntryPath: selectedCandidate?.entryPath,
            selectedCanonicalTarget: selectedCandidate?.canonicalTarget,
            detector: detector,
            environment: environment,
            monotonicNow: monotonicNow
        )
        if let failure = collection.selectedIdentityFailure {
            selection = .inconsistent(failure)
        }

        // The summary version belongs to the selection published by this scan. A detected selected
        // identity failure makes that selection inconsistent, so no earlier captured candidate may
        // contribute a known version.
        let publishedSelectedCandidate = selectionCandidate(in: selection)
        let selectedVersion: String?
        if let publishedSelectedCandidate,
           let selectedTarget = publishedSelectedCandidate.canonicalTarget {
            selectedVersion = collection.observations.first {
                $0.canonicalTarget == selectedTarget
                    && $0.entryPath == publishedSelectedCandidate.entryPath
            }?.version
        } else {
            selectedVersion = nil
        }
        let detected = detector.detectedTool(from: location, version: selectedVersion)

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
            shadowedInstallationCount: shadowedInstallationCount,
            installationVersions: collection.observations
        )
    }

    /// Selected canonical target first, then remaining live PATH groups in deterministic
    /// first-seen order. The selected declared extra-root target is included only when the
    /// existing selection is off-PATH; discovery is never expanded beyond it.
    private static func installationProbeTargets(
        selection: PathSelection,
        groups: [PathTargetGroup],
        pathEntries: [String]
    ) -> [InstallationVersionProbeTarget] {
        var targets: [InstallationVersionProbeTarget] = []
        var seenTargets = Set<String>()

        if case .offPath(let candidate, _) = selection,
           let target = candidate.canonicalTarget,
           seenTargets.insert(target).inserted {
            targets.append(InstallationVersionProbeTarget(
                canonicalTarget: target,
                entryPath: candidate.entryPath,
                origin: candidate.origin,
                isSelected: true
            ))
        }

        let selectedTarget: String?
        if case .winner(let candidate) = selection {
            selectedTarget = candidate.canonicalTarget
        } else {
            selectedTarget = nil
        }
        if let selectedTarget,
           let selectedGroup = groups.first(where: { $0.canonicalTarget == selectedTarget }),
           let entryPath = selectedGroup.entryPaths.first,
           seenTargets.insert(selectedTarget).inserted {
            targets.append(InstallationVersionProbeTarget(
                canonicalTarget: selectedTarget,
                entryPath: entryPath,
                origin: discoveryOrigin(for: selectedGroup, pathEntries: pathEntries),
                isSelected: true
            ))
        }

        for group in groups {
            guard seenTargets.insert(group.canonicalTarget).inserted,
                  let entryPath = group.entryPaths.first
            else { continue }
            targets.append(InstallationVersionProbeTarget(
                canonicalTarget: group.canonicalTarget,
                entryPath: entryPath,
                origin: discoveryOrigin(for: group, pathEntries: pathEntries),
                isSelected: false
            ))
        }
        return targets
    }

    /// The exact discovery slot and raw text recorded when this group was first seen, read from
    /// the same immutable PATH entries the scan grouped. This is provenance, not a filesystem
    /// rescan or an inferred canonical-parent directory.
    private static func discoveryOrigin(
        for group: PathTargetGroup,
        pathEntries: [String]
    ) -> PathCandidateOrigin {
        .path(slotIndex: group.firstSlotIndex, directoryText: pathEntries[group.firstSlotIndex])
    }

    /// The candidate published by a valid selection. An inconsistent selection never names one.
    private static func selectionCandidate(
        in selection: PathSelection
    ) -> PathCandidateObservation? {
        switch selection {
        case .winner(let candidate), .offPath(let candidate, _):
            candidate
        case .notInstalled, .inconsistent:
            nil
        }
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
        location: ToolLocation,
        workingDirectory: URL
    ) -> PathSelection {
        guard location.state == .installedNotOnPath else {
            return .inconsistent(
                "the diagnostic found a declared extra-root executable, but the detector reported \(location.state.rawValue)"
            )
        }
        guard let detectedEntry = location.entryPath,
              let detectedTarget = location.resolvedPath,
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
        location: ToolLocation,
        workingDirectory: URL
    ) -> PathSelection {
        guard location.state == .installedAndOnPath else {
            return .inconsistent(
                "the diagnostic found a live PATH entry, but the detector reported \(location.state.rawValue)"
            )
        }
        guard let detectedEntry = location.entryPath,
              let detectedTarget = location.resolvedPath,
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
