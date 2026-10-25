import Darwin
import Foundation
import Testing
@testable import AgentLensCore

private func diagnosticsFixtureRoot(_ label: String) throws -> URL {
    let environment = ProcessInfo.processInfo.environment
    guard let basePath = [environment["AGENT_LENS_TEST_SCRATCH"], environment["TMPDIR"]]
        .compactMap({ $0 })
        .first(where: { !$0.isEmpty })
    else {
        throw NSError(domain: "AgentLensTests", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "no approved test scratch root is available"])
    }
    let base = URL(fileURLWithPath: basePath, isDirectory: true).resolvingSymlinksInPath()
    let root = base.appendingPathComponent("agentlens-m5-\(label)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root.resolvingSymlinksInPath()
}

@discardableResult
private func makeDiagnosticsExecutable(in directory: URL, named name: String) throws -> String {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let executable = directory.appendingPathComponent(name)
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    return executable.path
}

private func diagnosticsEnvironment(_ pathEntries: [String], degraded: Bool = false) -> ShellEnvironment {
    let joined = pathEntries.joined(separator: ":")
    return ShellEnvironment(
        shellPath: "/bin/zsh",
        pathEntries: pathEntries,
        pathJoined: joined,
        raw: ["PATH": joined],
        isDegraded: degraded
    )
}

private final class DiagnosticsCallRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedPaths: [String] = []

    func record(_ path: String) {
        lock.lock()
        storedPaths.append(path)
        lock.unlock()
    }

    var paths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storedPaths
    }
}

private func relativePath(from base: URL, to target: URL) -> String {
    let baseComponents = base.standardizedFileURL.pathComponents
    let targetComponents = target.standardizedFileURL.pathComponents
    var commonCount = 0
    while commonCount < min(baseComponents.count, targetComponents.count),
          baseComponents[commonCount] == targetComponents[commonCount] {
        commonCount += 1
    }
    let upward = Array(repeating: "..", count: baseComponents.count - commonCount)
    let downward = targetComponents.dropFirst(commonCount)
    return (upward + downward).joined(separator: "/")
}

@Test func pathDiagnosticsReportTheFirstLivePathWinner() throws {
    let root = try diagnosticsFixtureRoot("first-live")
    defer { try? FileManager.default.removeItem(at: root) }
    let firstRoot = root.appendingPathComponent("first", isDirectory: true)
    let laterRoot = root.appendingPathComponent("later", isDirectory: true)
    let firstEntry = try makeDiagnosticsExecutable(in: firstRoot, named: "fixture-tool")
    _ = try makeDiagnosticsExecutable(in: laterRoot, named: "fixture-tool")
    let detector = ToolDetector(
        displayName: "Fixture Tool",
        executableName: "fixture-tool",
        versionQuerySpecification: .standard,
        versionQuery: { _, _, _, _ in "4.5.6" }
    )

    let report = PathDiagnosticsScanner.scan(
        detector: detector,
        environment: diagnosticsEnvironment([firstRoot.path, laterRoot.path])
    )

    #expect(report.detectedTool.state == .installedAndOnPath)
    #expect(report.firstLiveCandidate?.entryPath == firstEntry)
    #expect(report.selection == .winner(report.firstLiveCandidate ?? PathCandidateObservation(
        origin: .path(slotIndex: -1, directoryText: ""),
        entryPath: "",
        kind: .brokenSymlink,
        canonicalTarget: nil
    )))
    #expect(report.shadowedInstallationCount == 1)
    #expect(report.detectedTool.version == "4.5.6")
    #expect(report.installationVersions.count == 2)
    #expect(report.installationVersions.first?.version == "4.5.6")
    #expect(report.installationVersions.allSatisfy { $0.fingerprint != nil })
}

@Test func pathDiagnosticsSeparateRepeatedSlotsAliasesAndShadowedTargets() throws {
    let root = try diagnosticsFixtureRoot("counts")
    defer { try? FileManager.default.removeItem(at: root) }
    let targetRoot = root.appendingPathComponent("target", isDirectory: true)
    let firstRoot = root.appendingPathComponent("first", isDirectory: true)
    let aliasRoot = root.appendingPathComponent("alias", isDirectory: true)
    let laterRoot = root.appendingPathComponent("later", isDirectory: true)
    let target = try makeDiagnosticsExecutable(in: targetRoot, named: "fixture-target")
    for directory in [firstRoot, aliasRoot] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: directory.appendingPathComponent("fixture-tool").path,
            withDestinationPath: target
        )
    }
    let laterEntry = try makeDiagnosticsExecutable(in: laterRoot, named: "fixture-tool")
    let firstEntry = firstRoot.appendingPathComponent("fixture-tool").path
    let calls = DiagnosticsCallRecorder()
    let detector = ToolDetector(
        displayName: "Fixture Tool",
        executableName: "fixture-tool",
        versionQuerySpecification: .standard,
        versionQuery: { path, _, _, _ in
            calls.record(path)
            return nil
        }
    )

    let report = PathDiagnosticsScanner.scan(
        detector: detector,
        environment: diagnosticsEnvironment([firstRoot.path, aliasRoot.path, firstRoot.path + "/.", laterRoot.path])
    )

    #expect(report.liveCandidates.count == 4)
    #expect(report.distinctLiveEntryPathCount == 3)
    #expect(report.canonicalTargetCount == 2)
    #expect(report.repeatedPathSlotCount == 1)
    #expect(report.sameTargetAliasCount == 1)
    #expect(report.targetGroups.first?.entryPaths == [firstEntry, aliasRoot.appendingPathComponent("fixture-tool").path])
    #expect(report.shadowedInstallationCount == 1)
    #expect(calls.paths == [firstEntry, laterEntry])
    #expect(report.installationVersions.map(\.canonicalTarget) == [
        report.targetGroups[0].canonicalTarget,
        report.targetGroups[1].canonicalTarget,
    ])
    #expect(report.installationVersions.allSatisfy {
        $0.outcome == .unknown(.queryFailed)
    })
    let rendered = DiagnosticsScanRenderer.render(reports: [report], isDegraded: false)
    #expect(rendered.contains("live entry paths: 3"))
    #expect(rendered.contains("canonical targets: 2"))
    #expect(rendered.contains("repeated PATH slots: 1"))
    #expect(rendered.contains("same-target aliases: 1"))
    #expect(rendered.contains("shadowed installations: 1"))
    #expect(rendered.contains("verified winner:"))
    #expect(rendered.contains("same-target alias"))
    #expect(rendered.contains("shadowed because it appears later in PATH"))
}

@Test func pathDiagnosticsRetainInvalidFilesystemEvidenceBeforeTheWinner() throws {
    let root = try diagnosticsFixtureRoot("invalid-evidence")
    defer { try? FileManager.default.removeItem(at: root) }
    let absentRoot = root.appendingPathComponent("absent", isDirectory: true)
    let brokenRoot = root.appendingPathComponent("broken", isDirectory: true)
    let cyclicRoot = root.appendingPathComponent("cyclic", isDirectory: true)
    let nonExecutableRoot = root.appendingPathComponent("non-executable", isDirectory: true)
    let directoryRoot = root.appendingPathComponent("directory", isDirectory: true)
    let linkedFileRoot = root.appendingPathComponent("linked-file", isDirectory: true)
    let linkedDirectoryRoot = root.appendingPathComponent("linked-directory", isDirectory: true)
    let fifoRoot = root.appendingPathComponent("fifo", isDirectory: true)
    let liveRoot = root.appendingPathComponent("live", isDirectory: true)
    let nonExecutableTargetRoot = root.appendingPathComponent("non-executable-target", isDirectory: true)
    let directoryTargetRoot = root.appendingPathComponent("directory-target", isDirectory: true)
    for directory in [brokenRoot, cyclicRoot, nonExecutableRoot, directoryRoot, linkedFileRoot,
                      linkedDirectoryRoot, fifoRoot, nonExecutableTargetRoot,
                      directoryTargetRoot] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    let brokenLink = brokenRoot.appendingPathComponent("fixture-tool")
    try FileManager.default.createSymbolicLink(
        atPath: brokenLink.path,
        withDestinationPath: root.appendingPathComponent("missing-target").path
    )
    let cycleEntry = cyclicRoot.appendingPathComponent("fixture-tool")
    let cycleTarget = cyclicRoot.appendingPathComponent("cycle-target")
    try FileManager.default.createSymbolicLink(atPath: cycleEntry.path, withDestinationPath: cycleTarget.path)
    try FileManager.default.createSymbolicLink(atPath: cycleTarget.path, withDestinationPath: cycleEntry.path)
    let nonExecutable = nonExecutableRoot.appendingPathComponent("fixture-tool")
    try Data("not executable\n".utf8).write(to: nonExecutable)
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: nonExecutable.path)
    try FileManager.default.createDirectory(
        at: directoryRoot.appendingPathComponent("fixture-tool"),
        withIntermediateDirectories: true
    )
    let nonExecutableTarget = nonExecutableTargetRoot.appendingPathComponent("target")
    try Data("not executable\n".utf8).write(to: nonExecutableTarget)
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: nonExecutableTarget.path)
    try FileManager.default.createSymbolicLink(
        atPath: linkedFileRoot.appendingPathComponent("fixture-tool").path,
        withDestinationPath: nonExecutableTarget.path
    )
    try FileManager.default.createDirectory(at: directoryTargetRoot, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
        atPath: linkedDirectoryRoot.appendingPathComponent("fixture-tool").path,
        withDestinationPath: directoryTargetRoot.path
    )
    #expect(Darwin.mkfifo(fifoRoot.appendingPathComponent("fixture-tool").path, mode_t(0o644)) == 0)
    let liveEntry = try makeDiagnosticsExecutable(in: liveRoot, named: "fixture-tool")
    let detector = ToolDetector(
        displayName: "Fixture Tool",
        executableName: "fixture-tool",
        versionQuerySpecification: .standard,
        versionQuery: { _, _, _, _ in nil }
    )

    let report = PathDiagnosticsScanner.scan(
        detector: detector,
        environment: diagnosticsEnvironment([
            absentRoot.path, brokenRoot.path, cyclicRoot.path, nonExecutableRoot.path, directoryRoot.path,
            linkedFileRoot.path, linkedDirectoryRoot.path, fifoRoot.path, liveRoot.path
        ])
    )

    #expect(report.pathCandidates.map(\.kind) == [
        .brokenSymlink,
        .symlinkTargetUnavailable,
        .nonExecutableFile,
        .directory,
        .symlinkToNonExecutableFile,
        .symlinkToDirectory,
        .nonRegular(type: "fifo"),
        .executableFile
    ])
    #expect(report.invalidCandidates.count == 7)
    #expect(report.pathCandidates.map(\.entryPath).contains(absentRoot.appendingPathComponent("fixture-tool").path) == false)
    #expect(report.firstLiveCandidate?.entryPath == liveEntry)
    #expect(report.firstLiveCandidate?.origin == .path(slotIndex: 8, directoryText: liveRoot.path))
    #expect(report.selection == .winner(report.firstLiveCandidate ?? PathCandidateObservation(
        origin: .path(slotIndex: -1, directoryText: ""),
        entryPath: "",
        kind: .brokenSymlink,
        canonicalTarget: nil
    )))
}

@Test func pathDiagnosticsTreatsInvalidOnlyAndAbsentCandidatesAsNotInstalled() throws {
    let root = try diagnosticsFixtureRoot("invalid-only")
    defer { try? FileManager.default.removeItem(at: root) }
    let brokenRoot = root.appendingPathComponent("broken", isDirectory: true)
    let nonExecutableRoot = root.appendingPathComponent("non-executable", isDirectory: true)
    try FileManager.default.createDirectory(at: brokenRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: nonExecutableRoot, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
        atPath: brokenRoot.appendingPathComponent("fixture-tool").path,
        withDestinationPath: root.appendingPathComponent("missing-target").path
    )
    let nonExecutable = nonExecutableRoot.appendingPathComponent("fixture-tool")
    try Data("not executable\n".utf8).write(to: nonExecutable)
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: nonExecutable.path)
    let missingRoot = root.appendingPathComponent("missing", isDirectory: true)
    let detector = ToolDetector(
        displayName: "Fixture Tool",
        executableName: "fixture-tool",
        versionQuerySpecification: .standard,
        versionQuery: { _, _, _, _ in nil }
    )

    let report = PathDiagnosticsScanner.scan(
        detector: detector,
        environment: diagnosticsEnvironment([missingRoot.path, brokenRoot.path, nonExecutableRoot.path])
    )

    #expect(report.detectedTool.state == .notInstalled)
    #expect(report.selection == .notInstalled)
    #expect(report.firstLiveCandidate == nil)
    #expect(report.pathCandidates.map(\.kind) == [.brokenSymlink, .nonExecutableFile])
    #expect(report.pathCandidates.allSatisfy { $0.entryPath != missingRoot.appendingPathComponent("fixture-tool").path })
    #expect(report.shadowedInstallationCount == 0)
}

@Test func pathDiagnosticsReportsKnownExtraRootAsOffPathWithoutCallingItWinner() throws {
    let root = try diagnosticsFixtureRoot("off-path")
    defer { try? FileManager.default.removeItem(at: root) }
    let pathRoot = root.appendingPathComponent("path", isDirectory: true)
    let missingExtraRoot = root.appendingPathComponent("missing-extra", isDirectory: true)
    let invalidExtraRoot = root.appendingPathComponent("invalid-extra", isDirectory: true)
    let extraRoot = root.appendingPathComponent("known-extra", isDirectory: true)
    try FileManager.default.createDirectory(at: invalidExtraRoot, withIntermediateDirectories: true)
    let invalidExtraEntry = invalidExtraRoot.appendingPathComponent("fixture-tool")
    try Data("not executable\n".utf8).write(to: invalidExtraEntry)
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: invalidExtraEntry.path)
    let extraEntry = try makeDiagnosticsExecutable(in: extraRoot, named: "fixture-tool")
    let home = NSHomeDirectory()
    let tildeRoot = "~" + String(extraRoot.path.dropFirst(home.count))
    let detector = ToolDetector(
        displayName: "Fixture Tool",
        executableName: "fixture-tool",
        extraSearchRoots: [missingExtraRoot.path, invalidExtraRoot.path, tildeRoot],
        versionQuerySpecification: .standard,
        versionQuery: { _, _, _, _ in nil }
    )

    let report = PathDiagnosticsScanner.scan(
        detector: detector,
        environment: diagnosticsEnvironment([pathRoot.path])
    )

    #expect(report.detectedTool.state == .installedNotOnPath)
    #expect(report.pathCandidates.isEmpty)
    #expect(report.firstLiveCandidate == nil)
    #expect(report.selection == .offPath(
        candidate: PathCandidateObservation(
            origin: .extraRoot(index: 2, directoryText: tildeRoot),
            entryPath: extraEntry,
            kind: .executableFile,
            canonicalTarget: extraEntry
        ),
        root: tildeRoot
    ))
    #expect(report.shadowedInstallationCount == 0)
    #expect(report.installationVersions.count == 1)
    #expect(report.installationVersions.first?.canonicalTarget == extraEntry)
    #expect(report.installationVersions.first?.entryPath == extraEntry)
    #expect(report.installationVersions.first?.outcome == .unknown(.queryFailed))
    let rendered = DiagnosticsScanRenderer.render(reports: [report], isDegraded: false)
    #expect(rendered.contains("known extra root (off PATH; not a shell winner): \(tildeRoot)"))
    #expect(rendered.contains("! Fixture Tool          –    standalone (not on PATH)"))
    #expect(rendered.contains("canonical installation versions:"))
    #expect(rendered.contains("off PATH, declared extra root"))
    #expect(!rendered.contains("verified winner:"))
}

@Test func pathDiagnosticsResolvesEmptyAndRelativeRootsAgainstInjectedWorkingDirectory() throws {
    let root = try diagnosticsFixtureRoot("injected-cwd")
    defer { try? FileManager.default.removeItem(at: root) }
    let name = "fixture-tool-\(UUID().uuidString)"
    let firstWorkingDirectory = root.appendingPathComponent("first-cwd", isDirectory: true)
    let secondWorkingDirectory = root.appendingPathComponent("second-cwd", isDirectory: true)
    let firstRelativeRoot = firstWorkingDirectory.appendingPathComponent("relative-bin", isDirectory: true)
    let secondRelativeRoot = secondWorkingDirectory.appendingPathComponent("relative-bin", isDirectory: true)
    let firstEmptyEntry = try makeDiagnosticsExecutable(in: firstWorkingDirectory, named: name)
    let secondEmptyEntry = try makeDiagnosticsExecutable(in: secondWorkingDirectory, named: name)
    _ = try makeDiagnosticsExecutable(in: firstRelativeRoot, named: name)
    _ = try makeDiagnosticsExecutable(in: secondRelativeRoot, named: name)
    let detector = ToolDetector(displayName: "Fixture Tool", executableName: name, versionQuerySpecification: .standard)
    let environment = diagnosticsEnvironment(["", "relative-bin"])

    let firstReport = PathDiagnosticsScanner.scan(
        detector: detector,
        environment: environment,
        currentDirectory: firstWorkingDirectory.path
    )
    let secondReport = PathDiagnosticsScanner.scan(
        detector: detector,
        environment: environment,
        currentDirectory: secondWorkingDirectory.path
    )

    #expect(firstReport.pathCandidates.map(\.entryPath) == [
        firstEmptyEntry,
        firstRelativeRoot.appendingPathComponent(name).path
    ])
    #expect(secondReport.pathCandidates.map(\.entryPath) == [
        secondEmptyEntry,
        secondRelativeRoot.appendingPathComponent(name).path
    ])
    #expect(firstReport.firstLiveCandidate?.entryPath == firstEmptyEntry)
    #expect(secondReport.firstLiveCandidate?.entryPath == secondEmptyEntry)
    #expect(firstReport.detectedTool.state == .notInstalled)
    #expect(secondReport.detectedTool.state == .notInstalled)
}

@Test func pathDiagnosticsMatchesDetectorForEmptySlotAndRelativeLiveRoots() throws {
    let root = try diagnosticsFixtureRoot("relative-winner")
    defer { try? FileManager.default.removeItem(at: root) }
    let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let relativeRoot = relativePath(
        from: currentDirectory,
        to: root.appendingPathComponent("relative-bin", isDirectory: true)
    )
    let executableName = "agentlens-m5-\(UUID().uuidString)"
    let relativeBin = root.appendingPathComponent("relative-bin", isDirectory: true)
    let liveEntry = try makeDiagnosticsExecutable(in: relativeBin, named: executableName)
    let calls = DiagnosticsCallRecorder()
    let detectorEntry = "\(relativeRoot)/\(executableName)"
    let detector = ToolDetector(
        displayName: "Fixture Tool",
        executableName: executableName,
        versionQuerySpecification: .standard,
        versionQuery: { path, _, _, _ in
            calls.record(path)
            return nil
        }
    )

    let report = PathDiagnosticsScanner.scan(
        detector: detector,
        environment: diagnosticsEnvironment(["", relativeRoot, relativeRoot])
    )

    #expect(report.detectedTool.entryPath == detectorEntry)
    #expect(report.detectedTool.resolvedPath == liveEntry)
    #expect(report.firstLiveCandidate?.entryPath == liveEntry)
    #expect(report.selection == .winner(report.firstLiveCandidate ?? PathCandidateObservation(
        origin: .path(slotIndex: -1, directoryText: ""),
        entryPath: "",
        kind: .brokenSymlink,
        canonicalTarget: nil
    )))
    #expect(report.repeatedPathSlotCount == 1)
    #expect(report.sameTargetAliasCount == 0)
    #expect(report.shadowedInstallationCount == 0)
    #expect(calls.paths == [liveEntry])
    #expect(report.installationVersions.count == 1)
    #expect(report.installationVersions.first?.entryPath == liveEntry)
}

@Test func pathDiagnosticsDoesNotDoubleCountAnExtraRootOverlappingLivePath() throws {
    let root = try diagnosticsFixtureRoot("extra-overlap")
    defer { try? FileManager.default.removeItem(at: root) }
    let pathRoot = root.appendingPathComponent("bin", isDirectory: true)
    let liveEntry = try makeDiagnosticsExecutable(in: pathRoot, named: "fixture-tool")
    let detector = ToolDetector(
        displayName: "Fixture Tool",
        executableName: "fixture-tool",
        extraSearchRoots: [pathRoot.path],
        versionQuerySpecification: .standard,
        versionQuery: { _, _, _, _ in nil }
    )

    let report = PathDiagnosticsScanner.scan(
        detector: detector,
        environment: diagnosticsEnvironment([pathRoot.path])
    )

    #expect(report.pathCandidates.count == 1)
    #expect(report.firstLiveCandidate?.entryPath == liveEntry)
    #expect(report.selection == .winner(report.firstLiveCandidate ?? PathCandidateObservation(
        origin: .path(slotIndex: -1, directoryText: ""),
        entryPath: "",
        kind: .brokenSymlink,
        canonicalTarget: nil
    )))
    #expect(report.detectedTool.state == .installedAndOnPath)
}

@Test func pathDiagnosticsRefusesAChangedTargetInsteadOfClaimingAFalseWinner() throws {
    let root = try diagnosticsFixtureRoot("target-mismatch")
    defer { try? FileManager.default.removeItem(at: root) }
    let pathRoot = root.appendingPathComponent("bin", isDirectory: true)
    let firstTargetRoot = root.appendingPathComponent("target-a", isDirectory: true)
    let changedTargetRoot = root.appendingPathComponent("target-b", isDirectory: true)
    try FileManager.default.createDirectory(at: pathRoot, withIntermediateDirectories: true)
    let firstTarget = try makeDiagnosticsExecutable(in: firstTargetRoot, named: "tool-a")
    let changedTarget = try makeDiagnosticsExecutable(in: changedTargetRoot, named: "tool-b")
    let entry = pathRoot.appendingPathComponent("fixture-tool")
    try FileManager.default.createSymbolicLink(atPath: entry.path, withDestinationPath: firstTarget)
    let detector = ToolDetector(
        displayName: "Fixture Tool",
        executableName: "fixture-tool",
        versionQuerySpecification: .standard,
        versionQuery: { _, _, _, _ in
            try? FileManager.default.removeItem(at: entry)
            try? FileManager.default.createSymbolicLink(atPath: entry.path, withDestinationPath: changedTarget)
            return nil
        }
    )

    let report = PathDiagnosticsScanner.scan(
        detector: detector,
        environment: diagnosticsEnvironment([pathRoot.path])
    )

    #expect(report.detectedTool.resolvedPath == firstTarget)
    #expect(report.firstLiveCandidate?.canonicalTarget == firstTarget)
    if case .inconsistent(let reason) = report.selection {
        #expect(reason.contains("target"))
    } else {
        #expect(Bool(false), "a changed target must not be shown as the winner")
    }
    #expect(report.shadowedInstallationCount == nil)
    #expect(report.detectedTool.version == nil)
    #expect(report.installationVersions.first?.canonicalTarget == firstTarget)
    #expect(report.installationVersions.first?.outcome == .unknown(.identityChanged))
}

@Test func pathDiagnosticsRejectsAReplacedCapturedTargetForPathWinner() throws {
    let root = try diagnosticsFixtureRoot("replaced-canonical-path-target")
    defer { try? FileManager.default.removeItem(at: root) }
    let pathRoot = root.appendingPathComponent("bin", isDirectory: true)
    let originalTargetRoot = root.appendingPathComponent("target-a", isDirectory: true)
    let changedTargetRoot = root.appendingPathComponent("target-b", isDirectory: true)
    try FileManager.default.createDirectory(at: pathRoot, withIntermediateDirectories: true)
    let originalTarget = try makeDiagnosticsExecutable(in: originalTargetRoot, named: "tool-a")
    let changedTarget = try makeDiagnosticsExecutable(in: changedTargetRoot, named: "tool-b")
    let entry = pathRoot.appendingPathComponent("fixture-tool")
    try FileManager.default.createSymbolicLink(atPath: entry.path, withDestinationPath: originalTarget)
    let detector = ToolDetector(
        displayName: "Fixture Tool",
        executableName: "fixture-tool",
        versionQuerySpecification: .standard,
        versionQuery: { _, _, _, _ in
            try? FileManager.default.removeItem(atPath: originalTarget)
            try? FileManager.default.createSymbolicLink(
                atPath: originalTarget,
                withDestinationPath: changedTarget
            )
            return nil
        }
    )

    let report = PathDiagnosticsScanner.scan(
        detector: detector,
        environment: diagnosticsEnvironment([pathRoot.path])
    )

    #expect(originalTarget != changedTarget)
    #expect(report.detectedTool.resolvedPath == originalTarget)
    #expect(report.firstLiveCandidate?.canonicalTarget == originalTarget)
    if case .inconsistent(let reason) = report.selection {
        #expect(reason.contains("target"))
    } else {
        #expect(Bool(false), "replacing the captured target must not produce a verified PATH winner")
    }
    #expect(report.shadowedInstallationCount == nil)
    #expect(report.detectedTool.version == nil)
    #expect(report.installationVersions.first?.canonicalTarget == originalTarget)
    #expect(report.installationVersions.first?.outcome == .unknown(.identityChanged))
    let rendered = DiagnosticsScanRenderer.render(reports: [report], isDegraded: false)
    #expect(!rendered.contains("verified winner:"))
    #expect(rendered.contains("winner unavailable: consistency failure"))
    #expect(rendered.contains("shadowed installations: unavailable (consistency failure)"))
}

@Test func pathDiagnosticsRejectsAReplacedCapturedTargetForOffPathCandidate() throws {
    let root = try diagnosticsFixtureRoot("replaced-canonical-off-path-target")
    defer { try? FileManager.default.removeItem(at: root) }
    let pathRoot = root.appendingPathComponent("path", isDirectory: true)
    let extraRoot = root.appendingPathComponent("extra", isDirectory: true)
    let originalTargetRoot = root.appendingPathComponent("target-a", isDirectory: true)
    let changedTargetRoot = root.appendingPathComponent("target-b", isDirectory: true)
    try FileManager.default.createDirectory(at: pathRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: extraRoot, withIntermediateDirectories: true)
    let originalTarget = try makeDiagnosticsExecutable(in: originalTargetRoot, named: "tool-a")
    let changedTarget = try makeDiagnosticsExecutable(in: changedTargetRoot, named: "tool-b")
    let entry = extraRoot.appendingPathComponent("fixture-tool")
    try FileManager.default.createSymbolicLink(atPath: entry.path, withDestinationPath: originalTarget)
    let detector = ToolDetector(
        displayName: "Fixture Tool",
        executableName: "fixture-tool",
        extraSearchRoots: [extraRoot.path],
        versionQuerySpecification: .standard,
        versionQuery: { _, _, _, _ in
            try? FileManager.default.removeItem(atPath: originalTarget)
            try? FileManager.default.createSymbolicLink(
                atPath: originalTarget,
                withDestinationPath: changedTarget
            )
            return nil
        }
    )

    let report = PathDiagnosticsScanner.scan(
        detector: detector,
        environment: diagnosticsEnvironment([pathRoot.path])
    )

    #expect(originalTarget != changedTarget)
    #expect(report.detectedTool.state == .installedNotOnPath)
    #expect(report.detectedTool.resolvedPath == originalTarget)
    let diagnosticTarget = URL(fileURLWithPath: originalTarget)
        .resolvingSymlinksInPath()
        .standardizedFileURL
        .path
    #expect(diagnosticTarget == changedTarget)
    #expect(report.detectedTool.resolvedPath != diagnosticTarget)
    if case .inconsistent(let reason) = report.selection {
        #expect(reason.contains("target"))
    } else {
        #expect(Bool(false), "replacing the captured target must produce an off-PATH consistency failure")
    }
    #expect(report.shadowedInstallationCount == nil)
    #expect(report.detectedTool.version == nil)
    #expect(report.installationVersions.first?.canonicalTarget == originalTarget)
    #expect(report.installationVersions.first?.outcome == .unknown(.identityChanged))
    let rendered = DiagnosticsScanRenderer.render(reports: [report], isDegraded: false)
    #expect(!rendered.contains("verified winner:"))
    #expect(rendered.contains("winner unavailable: consistency failure"))
    #expect(rendered.contains("shadowed installations: unavailable (consistency failure)"))
}

@Test func diagnosticsRendererPreservesRegistryOrderDashVersionAndDegradedWarning() throws {
    let root = try diagnosticsFixtureRoot("renderer-order")
    defer { try? FileManager.default.removeItem(at: root) }
    let definitions = try DetectorRegistry.loadDefault()
    let environment = diagnosticsEnvironment([root.path], degraded: true)
    let reports = definitions.map { definition in
        PathDiagnosticsScanner.scan(
            detector: ToolDetector(
                displayName: definition.displayName,
                executableName: definition.executableName,
                extraSearchRoots: [],
                versionQuerySpecification: .standard,
                versionQuery: { _, _, _, _ in nil }
            ),
            environment: environment
        )
    }

    let rendered = DiagnosticsScanRenderer.render(reports: reports, isDegraded: environment.isDegraded)

    #expect(reports.map(\.detectedTool.displayName) == definitions.map(\.displayName))
    #expect(rendered.contains("WARNING:"))
    #expect(rendered.contains("documented fallback PATH"))
    #expect(rendered.contains("may not represent the login shell's authoritative PATH"))
    #expect(rendered.contains("– Codex          –    –"))
    #expect(rendered.contains("– OpenCode          –    –"))
    #expect(rendered.contains("– Grok CLI          –    –"))
    let codex = try #require(rendered.range(of: "– Codex"))
    let openCode = try #require(rendered.range(of: "– OpenCode"))
    let grok = try #require(rendered.range(of: "– Grok CLI"))
    #expect(codex.lowerBound < openCode.lowerBound)
    #expect(openCode.lowerBound < grok.lowerBound)
}
