import Foundation
import Testing
@testable import AgentLensCore

// M9-C — identity-bound local version collection. Every fixture executable is real and
// test-owned under the approved scratch root. Queries use the production local-query seam unless
// a transition must occur during a query.

private func versionFixtureRoot(_ label: String) throws -> URL {
    let environment = ProcessInfo.processInfo.environment
    guard let basePath = [environment["AGENT_LENS_TEST_SCRATCH"], environment["TMPDIR"]]
        .compactMap({ $0 })
        .first(where: { !$0.isEmpty })
    else {
        throw NSError(
            domain: "AgentLensVersionTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "no approved test scratch root is available"]
        )
    }
    let base = URL(fileURLWithPath: basePath, isDirectory: true).resolvingSymlinksInPath()
    let root = base.appendingPathComponent(
        "agentlens-m9c-\(label)-\(UUID().uuidString)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root.resolvingSymlinksInPath()
}

@discardableResult
private func makeVersionExecutable(
    in directory: URL,
    named name: String,
    version: String
) throws -> String {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let executable = directory.appendingPathComponent(name)
    let script = "#!/bin/sh\nprintf 'fixture \(version)\\n'\n"
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: executable.path
    )
    return executable.path
}

@discardableResult
private func replaceVersionExecutable(
    at path: String,
    named name: String,
    version: String
) throws -> String {
    try? FileManager.default.removeItem(atPath: path)
    return try makeVersionExecutable(
        in: URL(fileURLWithPath: path).deletingLastPathComponent(),
        named: name,
        version: version
    )
}

@discardableResult
private func makeFailingVersionExecutable(in directory: URL, named name: String) throws -> String {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let executable = directory.appendingPathComponent(name)
    try Data("#!/bin/sh\nexit 3\n".utf8).write(to: executable)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: executable.path
    )
    return executable.path
}

private func versionEnvironment(_ pathEntries: [String]) -> ShellEnvironment {
    let joined = pathEntries.joined(separator: ":")
    return ShellEnvironment(
        shellPath: "/bin/zsh",
        pathEntries: pathEntries,
        pathJoined: joined,
        raw: ["PATH": joined],
        isDegraded: false
    )
}

private final class VersionCallRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedPaths: [String] = []
    private var storedTimeouts: [TimeInterval] = []
    private var activeCount = 0
    private var maximumActive = 0

    func begin(_ path: String, timeout: TimeInterval) {
        lock.lock()
        storedPaths.append(path)
        storedTimeouts.append(timeout)
        activeCount += 1
        maximumActive = max(maximumActive, activeCount)
        lock.unlock()
    }

    func end() {
        lock.lock()
        activeCount -= 1
        lock.unlock()
    }

    var paths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storedPaths
    }

    var timeouts: [TimeInterval] {
        lock.lock()
        defer { lock.unlock() }
        return storedTimeouts
    }

    var maximumConcurrentQueries: Int {
        lock.lock()
        defer { lock.unlock() }
        return maximumActive
    }
}

private final class MonotonicClockBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: UInt64

    init(_ value: UInt64) {
        storedValue = value
    }

    var now: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func advance(by value: UInt64) {
        lock.lock()
        storedValue += value
        lock.unlock()
    }
}

private func recordingQuery(
    _ recorder: VersionCallRecorder
) -> @Sendable (String, ShellEnvironment, TimeInterval, VersionQuerySpecification) -> String? {
    { path, environment, timeout, specification in
        recorder.begin(path, timeout: timeout)
        defer { recorder.end() }
        return ToolDetector.queryVersion(
            executablePath: path,
            environment: environment,
            timeout: timeout,
            specification: specification
        )
    }
}

@Test func installationVersionsKeepDistinctValuesForTwoRealCanonicalTargets() throws {
    let root = try versionFixtureRoot("two-targets")
    defer { try? FileManager.default.removeItem(at: root) }
    let winnerRoot = root.appendingPathComponent("winner", isDirectory: true)
    let shadowRoot = root.appendingPathComponent("shadow", isDirectory: true)
    let winner = try makeVersionExecutable(in: winnerRoot, named: "fixture-tool", version: "1.2.3")
    let shadow = try makeVersionExecutable(in: shadowRoot, named: "fixture-tool", version: "4.5.6")
    let calls = VersionCallRecorder()
    let detector = ToolDetector(
        displayName: "Fixture Tool",
        executableName: "fixture-tool",
        versionQuerySpecification: .standard,
        versionQuery: recordingQuery(calls)
    )

    let report = PathDiagnosticsScanner.scan(
        detector: detector,
        environment: versionEnvironment([winnerRoot.path, shadowRoot.path])
    )

    #expect(report.detectedTool.version == "1.2.3")
    #expect(report.installationVersions.map(\.canonicalTarget) == [winner, shadow])
    #expect(report.installationVersions.map(\.version) == ["1.2.3", "4.5.6"])
    #expect(report.installationVersions.map(\.origin) == [
        .path(slotIndex: 0, directoryText: winnerRoot.path),
        .path(slotIndex: 1, directoryText: shadowRoot.path),
    ])
    #expect(report.installationVersions.allSatisfy { $0.fingerprint != nil })
    #expect(report.selection == .winner(try #require(report.firstLiveCandidate)))
    #expect(report.shadowedInstallationCount == 1)
    #expect(calls.paths == [winner, shadow])

    let rendered = DiagnosticsScanRenderer.render(reports: [report], isDegraded: false)
    #expect(rendered.contains("canonical installation versions:"))
    #expect(rendered.contains("\(winner) -> version 1.2.3"))
    #expect(rendered.contains("\(shadow) -> version 4.5.6"))
}

@Test func installationVersionsQueryEachCanonicalTargetOnceDespiteAliasesAndRepeatedSlots() throws {
    let root = try versionFixtureRoot("alias-dedup")
    defer { try? FileManager.default.removeItem(at: root) }
    let targetRoot = root.appendingPathComponent("target", isDirectory: true)
    let winnerRoot = root.appendingPathComponent("winner", isDirectory: true)
    let aliasRoot = root.appendingPathComponent("alias", isDirectory: true)
    let shadowRoot = root.appendingPathComponent("shadow", isDirectory: true)
    let target = try makeVersionExecutable(
        in: targetRoot, named: "fixture-target", version: "1.0.0"
    )
    for directory in [winnerRoot, aliasRoot] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: directory.appendingPathComponent("fixture-tool").path,
            withDestinationPath: target
        )
    }
    let winnerEntry = winnerRoot.appendingPathComponent("fixture-tool").path
    let shadowEntry = try makeVersionExecutable(
        in: shadowRoot, named: "fixture-tool", version: "2.0.0"
    )
    let calls = VersionCallRecorder()
    let detector = ToolDetector(
        displayName: "Fixture Tool",
        executableName: "fixture-tool",
        versionQuerySpecification: .standard,
        versionQuery: recordingQuery(calls)
    )

    let report = PathDiagnosticsScanner.scan(
        detector: detector,
        environment: versionEnvironment([
            winnerRoot.path,
            aliasRoot.path,
            winnerRoot.path + "/.",
            shadowRoot.path,
        ])
    )

    #expect(report.liveCandidates.count == 4)
    #expect(report.distinctLiveEntryPathCount == 3)
    #expect(report.canonicalTargetCount == 2)
    #expect(report.repeatedPathSlotCount == 1)
    #expect(report.sameTargetAliasCount == 1)
    #expect(report.installationVersions.count == 2)
    #expect(report.installationVersions.map(\.canonicalTarget) == [target, shadowEntry])
    #expect(report.installationVersions.map(\.entryPath) == [winnerEntry, shadowEntry])
    #expect(report.installationVersions.map(\.origin) == [
        .path(slotIndex: 0, directoryText: winnerRoot.path),
        .path(slotIndex: 3, directoryText: shadowRoot.path),
    ])
    #expect(report.installationVersions.map(\.version) == ["1.0.0", "2.0.0"])
    #expect(report.detectedTool.version == "1.0.0")
    #expect(calls.paths == [winnerEntry, shadowEntry])
}

@Test func selectedExtraRootGetsOnlyItsOwnOffPathVersion() throws {
    let root = try versionFixtureRoot("off-path-selected")
    defer { try? FileManager.default.removeItem(at: root) }
    let emptyPathRoot = root.appendingPathComponent("path", isDirectory: true)
    let selectedExtraRoot = root.appendingPathComponent("selected-extra", isDirectory: true)
    let unselectedExtraRoot = root.appendingPathComponent("unselected-extra", isDirectory: true)
    try FileManager.default.createDirectory(at: emptyPathRoot, withIntermediateDirectories: true)
    let selectedEntry = try makeVersionExecutable(
        in: selectedExtraRoot, named: "fixture-tool", version: "3.1.0"
    )
    _ = try makeVersionExecutable(
        in: unselectedExtraRoot, named: "fixture-tool", version: "9.9.9"
    )
    let calls = VersionCallRecorder()
    let detector = ToolDetector(
        displayName: "Fixture Tool",
        executableName: "fixture-tool",
        extraSearchRoots: [selectedExtraRoot.path, unselectedExtraRoot.path],
        versionQuerySpecification: .standard,
        versionQuery: recordingQuery(calls)
    )

    let report = PathDiagnosticsScanner.scan(
        detector: detector,
        environment: versionEnvironment([emptyPathRoot.path])
    )

    #expect(report.detectedTool.state == .installedNotOnPath)
    #expect(report.detectedTool.version == "3.1.0")
    #expect(report.installationVersions.count == 1)
    #expect(report.installationVersions.first?.canonicalTarget == selectedEntry)
    #expect(report.installationVersions.first?.entryPath == selectedEntry)
    #expect(report.installationVersions.first?.origin == .extraRoot(
        index: 0,
        directoryText: selectedExtraRoot.path
    ))
    #expect(report.installationVersions.first?.version == "3.1.0")
    #expect(calls.paths == [selectedEntry])
    guard case .offPath(let candidate, let configuredRoot) = report.selection else {
        Issue.record("expected the selected declared extra root to remain an off-PATH selection")
        return
    }
    #expect(candidate.entryPath == selectedEntry)
    #expect(configuredRoot == selectedExtraRoot.path)
    #expect(report.shadowedInstallationCount == 0)

    let rendered = DiagnosticsScanRenderer.render(reports: [report], isDegraded: false)
    #expect(rendered.contains("\(selectedEntry) -> version 3.1.0"))
    #expect(rendered.contains("off PATH, declared extra root"))
    #expect(!rendered.contains("verified winner:"))
}

@Test func unchangedFailedQueryKeepsTheWinnerAndPublishesNeutralUnknown() throws {
    let root = try versionFixtureRoot("query-failed")
    defer { try? FileManager.default.removeItem(at: root) }
    let binRoot = root.appendingPathComponent("bin", isDirectory: true)
    let entry = try makeFailingVersionExecutable(in: binRoot, named: "fixture-tool")
    let detector = ToolDetector(
        displayName: "Fixture Tool",
        executableName: "fixture-tool",
        versionQuerySpecification: .standard
    )

    let report = PathDiagnosticsScanner.scan(
        detector: detector,
        environment: versionEnvironment([binRoot.path])
    )

    #expect(report.detectedTool.state == .installedAndOnPath)
    #expect(report.detectedTool.version == nil)
    #expect(report.selection == .winner(try #require(report.firstLiveCandidate)))
    #expect(report.shadowedInstallationCount == 0)
    #expect(report.installationVersions.count == 1)
    #expect(report.installationVersions.first?.entryPath == entry)
    #expect(report.installationVersions.first?.outcome == .unknown(.queryFailed))
    #expect(report.installationVersions.first?.fingerprint != nil)

    let rendered = DiagnosticsScanRenderer.render(reports: [report], isDegraded: false)
    #expect(rendered.contains("unknown — the version query failed or returned no version"))
}

@Test func selectedRetargetDuringQueryCannotKeepAPlausiblePrintedVersion() throws {
    let root = try versionFixtureRoot("selected-retarget")
    defer { try? FileManager.default.removeItem(at: root) }
    let binRoot = root.appendingPathComponent("bin", isDirectory: true)
    let targetARoot = root.appendingPathComponent("target-a", isDirectory: true)
    let targetBRoot = root.appendingPathComponent("target-b", isDirectory: true)
    let shadowRoot = root.appendingPathComponent("shadow", isDirectory: true)
    try FileManager.default.createDirectory(at: binRoot, withIntermediateDirectories: true)
    let targetA = try makeVersionExecutable(in: targetARoot, named: "tool-a", version: "1.0.0")
    let targetB = try makeVersionExecutable(in: targetBRoot, named: "tool-b", version: "2.0.0")
    let shadowEntry = try makeVersionExecutable(
        in: shadowRoot, named: "fixture-tool", version: "2.0.0"
    )
    let winnerEntry = binRoot.appendingPathComponent("fixture-tool").path
    try FileManager.default.createSymbolicLink(atPath: winnerEntry, withDestinationPath: targetA)
    let calls = VersionCallRecorder()
    let detector = ToolDetector(
        displayName: "Fixture Tool",
        executableName: "fixture-tool",
        versionQuerySpecification: .standard,
        versionQuery: { path, environment, timeout, specification in
            calls.begin(path, timeout: timeout)
            defer { calls.end() }
            if path == winnerEntry {
                try? FileManager.default.removeItem(atPath: winnerEntry)
                try? FileManager.default.createSymbolicLink(
                    atPath: winnerEntry,
                    withDestinationPath: targetB
                )
                return "9.9.9"
            }
            return ToolDetector.queryVersion(
                executablePath: path,
                environment: environment,
                timeout: timeout,
                specification: specification
            )
        }
    )

    let report = PathDiagnosticsScanner.scan(
        detector: detector,
        environment: versionEnvironment([binRoot.path, shadowRoot.path])
    )

    #expect(report.detectedTool.version == nil)
    #expect(report.shadowedInstallationCount == nil)
    if case .inconsistent(let reason) = report.selection {
        #expect(reason.contains("target"))
    } else {
        Issue.record("a selected retarget must invalidate the PATH selection")
    }
    #expect(calls.paths == [winnerEntry, shadowEntry])
    #expect(report.installationVersions.count == 2)
    #expect(report.installationVersions[0].canonicalTarget == targetA)
    #expect(report.installationVersions[0].outcome == .unknown(.identityChanged))
    #expect(report.installationVersions[0].version == nil)
    #expect(report.installationVersions[1].canonicalTarget == shadowEntry)
    #expect(report.installationVersions[1].version == "2.0.0")
}

@Test func samePathReplacementDuringQueryLosesThePrintedVersion() throws {
    let root = try versionFixtureRoot("same-path-replacement")
    defer { try? FileManager.default.removeItem(at: root) }
    let binRoot = root.appendingPathComponent("bin", isDirectory: true)
    let entry = try makeVersionExecutable(
        in: binRoot, named: "fixture-tool", version: "1.0.0"
    )
    let detector = ToolDetector(
        displayName: "Fixture Tool",
        executableName: "fixture-tool",
        versionQuerySpecification: .standard,
        versionQuery: { path, _, _, _ in
            _ = try? replaceVersionExecutable(
                at: path,
                named: "fixture-tool",
                version: "88.888.8888"
            )
            return "7.7.7"
        }
    )

    let report = PathDiagnosticsScanner.scan(
        detector: detector,
        environment: versionEnvironment([binRoot.path])
    )

    #expect(report.detectedTool.version == nil)
    #expect(report.shadowedInstallationCount == nil)
    if case .inconsistent = report.selection {
        // Expected: the selected executable was replaced at the same path.
    } else {
        Issue.record("same-path replacement must invalidate the selected observation")
    }
    #expect(report.installationVersions.count == 1)
    #expect(report.installationVersions.first?.canonicalTarget == entry)
    #expect(report.installationVersions.first?.outcome == .unknown(.identityChanged))
    #expect(report.installationVersions.first?.version == nil)
}

@Test func earlySelectedChangeWhileALaterQueryRunsClearsTheSelectedVersion() throws {
    let root = try versionFixtureRoot("early-selected-change")
    defer { try? FileManager.default.removeItem(at: root) }
    let firstRoot = root.appendingPathComponent("first", isDirectory: true)
    let secondRoot = root.appendingPathComponent("second", isDirectory: true)
    let thirdRoot = root.appendingPathComponent("third", isDirectory: true)
    let first = try makeVersionExecutable(in: firstRoot, named: "fixture-tool", version: "1.0.0")
    let second = try makeVersionExecutable(in: secondRoot, named: "fixture-tool", version: "2.0.0")
    let third = try makeVersionExecutable(in: thirdRoot, named: "fixture-tool", version: "3.0.0")
    let detector = ToolDetector(
        displayName: "Fixture Tool",
        executableName: "fixture-tool",
        versionQuerySpecification: .standard,
        versionQuery: { path, environment, timeout, specification in
            if path == third {
                _ = try? replaceVersionExecutable(
                    at: first,
                    named: "fixture-tool",
                    version: "99.0.0"
                )
            }
            return ToolDetector.queryVersion(
                executablePath: path,
                environment: environment,
                timeout: timeout,
                specification: specification
            )
        }
    )

    let report = PathDiagnosticsScanner.scan(
        detector: detector,
        environment: versionEnvironment([firstRoot.path, secondRoot.path, thirdRoot.path])
    )

    #expect(report.detectedTool.version == nil)
    #expect(report.shadowedInstallationCount == nil)
    if case .inconsistent = report.selection {
        // Expected: an earlier selected identity changed while a later canonical copy was probed.
    } else {
        Issue.record("an early selected identity change must invalidate the selection")
    }
    #expect(report.installationVersions.map(\.canonicalTarget) == [first, second, third])
    #expect(report.installationVersions[0].outcome == .unknown(.identityChanged))
    #expect(report.installationVersions[0].version == nil)
    #expect(report.installationVersions[1].version == "2.0.0")
    #expect(report.installationVersions[2].version == "3.0.0")
}

@Test func earlyShadowedChangeWhileALaterQueryRunsLeavesTheWinnerIntact() throws {
    let root = try versionFixtureRoot("early-shadowed-change")
    defer { try? FileManager.default.removeItem(at: root) }
    let firstRoot = root.appendingPathComponent("first", isDirectory: true)
    let secondRoot = root.appendingPathComponent("second", isDirectory: true)
    let thirdRoot = root.appendingPathComponent("third", isDirectory: true)
    let first = try makeVersionExecutable(in: firstRoot, named: "fixture-tool", version: "1.0.0")
    let second = try makeVersionExecutable(in: secondRoot, named: "fixture-tool", version: "2.0.0")
    let third = try makeVersionExecutable(in: thirdRoot, named: "fixture-tool", version: "3.0.0")
    let detector = ToolDetector(
        displayName: "Fixture Tool",
        executableName: "fixture-tool",
        versionQuerySpecification: .standard,
        versionQuery: { path, environment, timeout, specification in
            if path == third {
                _ = try? replaceVersionExecutable(
                    at: second,
                    named: "fixture-tool",
                    version: "88.0.0"
                )
            }
            return ToolDetector.queryVersion(
                executablePath: path,
                environment: environment,
                timeout: timeout,
                specification: specification
            )
        }
    )

    let report = PathDiagnosticsScanner.scan(
        detector: detector,
        environment: versionEnvironment([firstRoot.path, secondRoot.path, thirdRoot.path])
    )

    #expect(report.detectedTool.version == "1.0.0")
    #expect(report.selection == .winner(try #require(report.firstLiveCandidate)))
    #expect(report.shadowedInstallationCount == 2)
    #expect(report.installationVersions.map(\.canonicalTarget) == [first, second, third])
    #expect(report.installationVersions[0].version == "1.0.0")
    #expect(report.installationVersions[1].outcome == .unknown(.identityChanged))
    #expect(report.installationVersions[1].version == nil)
    #expect(report.installationVersions[2].version == "3.0.0")
}

@Test func missingAndUnexecutableShadowedCandidatesStayUnknownWithoutBorrowing() throws {
    let root = try versionFixtureRoot("missing-unexecutable")
    defer { try? FileManager.default.removeItem(at: root) }
    let firstRoot = root.appendingPathComponent("first", isDirectory: true)
    let removedRoot = root.appendingPathComponent("removed", isDirectory: true)
    let unexecutableRoot = root.appendingPathComponent("unexecutable", isDirectory: true)
    let first = try makeVersionExecutable(in: firstRoot, named: "fixture-tool", version: "1.0.0")
    let removed = try makeVersionExecutable(in: removedRoot, named: "fixture-tool", version: "2.0.0")
    let unexecutable = try makeVersionExecutable(
        in: unexecutableRoot, named: "fixture-tool", version: "3.0.0"
    )
    let detector = ToolDetector(
        displayName: "Fixture Tool",
        executableName: "fixture-tool",
        versionQuerySpecification: .standard,
        versionQuery: { path, environment, timeout, specification in
            if path == first {
                try? FileManager.default.removeItem(atPath: removed)
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o644],
                    ofItemAtPath: unexecutable
                )
            }
            return ToolDetector.queryVersion(
                executablePath: path,
                environment: environment,
                timeout: timeout,
                specification: specification
            )
        }
    )

    let report = PathDiagnosticsScanner.scan(
        detector: detector,
        environment: versionEnvironment([firstRoot.path, removedRoot.path, unexecutableRoot.path])
    )

    #expect(report.detectedTool.version == "1.0.0")
    #expect(report.selection == .winner(try #require(report.firstLiveCandidate)))
    #expect(report.installationVersions.map(\.canonicalTarget) == [first, removed, unexecutable])
    #expect(report.installationVersions[0].version == "1.0.0")
    #expect(report.installationVersions[1].outcome == .unknown(.executableUnavailable))
    #expect(report.installationVersions[1].version == nil)
    #expect(report.installationVersions[2].outcome == .unknown(.executableUnavailable))
    #expect(report.installationVersions[2].version == nil)
}

@Test func aggregateVersionProbeBudgetStopsAfterThreeSecondsRemainderAndKeepsEveryTarget() throws {
    let root = try versionFixtureRoot("aggregate-budget")
    defer { try? FileManager.default.removeItem(at: root) }
    let directories = (0..<4).map { root.appendingPathComponent("bin-\($0)", isDirectory: true) }
    let entries = try directories.enumerated().map { index, directory in
        try makeVersionExecutable(
            in: directory, named: "fixture-tool", version: "1.0.\(index)"
        )
    }
    let clock = MonotonicClockBox(1_000_000_000)
    let calls = VersionCallRecorder()
    let detector = ToolDetector(
        displayName: "Fixture Tool",
        executableName: "fixture-tool",
        versionQuerySpecification: .standard,
        versionQuery: { path, _, timeout, _ in
            calls.begin(path, timeout: timeout)
            defer { calls.end() }
            clock.advance(by: 4_000_000_000)
            return "1.0.0"
        }
    )

    let report = PathDiagnosticsScanner.scan(
        detector: detector,
        environment: versionEnvironment(directories.map(\.path)),
        currentDirectory: FileManager.default.currentDirectoryPath,
        monotonicNow: { clock.now }
    )

    #expect(calls.paths == Array(entries.prefix(3)))
    #expect(calls.timeouts.count == 3)
    #expect(abs(calls.timeouts[0] - 3) < 0.000_001)
    #expect(abs(calls.timeouts[1] - 3) < 0.000_001)
    #expect(abs(calls.timeouts[2] - 2) < 0.000_001)
    #expect(calls.maximumConcurrentQueries == 1)
    #expect(report.installationVersions.map(\.canonicalTarget) == entries)
    #expect(report.installationVersions.prefix(3).allSatisfy { $0.outcome == .measured("1.0.0") })
    #expect(report.installationVersions[3].outcome == .unknown(.budgetExhausted))
    #expect(report.installationVersions[3].fingerprint == nil)
    #expect(report.detectedTool.version == "1.0.0")
    #expect(report.selection == .winner(try #require(report.firstLiveCandidate)))
}

@Test func directDetectStillRunsExactlyOneLocalVersionQuery() throws {
    let root = try versionFixtureRoot("direct-detect")
    defer { try? FileManager.default.removeItem(at: root) }
    let binRoot = root.appendingPathComponent("bin", isDirectory: true)
    let entry = try makeVersionExecutable(
        in: binRoot, named: "fixture-tool", version: "6.7.8"
    )
    let calls = VersionCallRecorder()
    let detector = ToolDetector(
        displayName: "Fixture Tool",
        executableName: "fixture-tool",
        versionQuerySpecification: .standard,
        versionQuery: recordingQuery(calls)
    )

    let tool = detector.detect(in: versionEnvironment([binRoot.path]))

    #expect(tool.state == .installedAndOnPath)
    #expect(tool.entryPath == entry)
    #expect(tool.version == "6.7.8")
    #expect(calls.paths == [entry])
}

@Test func terminalSelectedRetargetAfterPublicationInvalidatesTheSelectedObservation() throws {
    let root = try versionFixtureRoot("terminal-selected-retarget")
    defer { try? FileManager.default.removeItem(at: root) }
    let binRoot = root.appendingPathComponent("bin", isDirectory: true)
    let targetARoot = root.appendingPathComponent("target-a", isDirectory: true)
    let targetBRoot = root.appendingPathComponent("target-b", isDirectory: true)
    let shadowRoot = root.appendingPathComponent("shadow", isDirectory: true)
    try FileManager.default.createDirectory(at: binRoot, withIntermediateDirectories: true)
    let targetA = try makeVersionExecutable(in: targetARoot, named: "tool-a", version: "1.2.3")
    let targetB = try makeVersionExecutable(in: targetBRoot, named: "tool-b", version: "2.3.4")
    let shadowEntry = try makeVersionExecutable(
        in: shadowRoot, named: "fixture-tool", version: "4.5.6"
    )
    let winnerEntry = binRoot.appendingPathComponent("fixture-tool").path
    try FileManager.default.createSymbolicLink(atPath: winnerEntry, withDestinationPath: targetA)
    let calls = VersionCallRecorder()
    let detector = ToolDetector(
        displayName: "Fixture Tool",
        executableName: "fixture-tool",
        versionQuerySpecification: .standard,
        versionQuery: recordingQuery(calls)
    )

    let report = InstallationVersionCollectorTestHooks.$onBeforeTerminalSelectedRecheck.withValue({
        try? FileManager.default.removeItem(atPath: winnerEntry)
        try? FileManager.default.createSymbolicLink(
            atPath: winnerEntry,
            withDestinationPath: targetB
        )
    }) {
        PathDiagnosticsScanner.scan(
            detector: detector,
            environment: versionEnvironment([binRoot.path, shadowRoot.path])
        )
    }

    #expect(report.detectedTool.version == nil)
    #expect(report.shadowedInstallationCount == nil)
    if case .inconsistent(let reason) = report.selection {
        #expect(reason.contains("target"))
    } else {
        Issue.record("the terminal selected retarget must invalidate the PATH selection")
    }
    let currentDestination = try FileManager.default.destinationOfSymbolicLink(atPath: winnerEntry)
    #expect(currentDestination == targetB)
    #expect(calls.paths == [winnerEntry, shadowEntry])
    #expect(report.installationVersions.map(\.canonicalTarget) == [targetA, shadowEntry])
    #expect(report.installationVersions.map(\.entryPath) == [winnerEntry, shadowEntry])
    #expect(report.installationVersions[0].outcome == .unknown(.identityChanged))
    #expect(report.installationVersions[0].version == nil)
    #expect(report.installationVersions[1].outcome == .measured("4.5.6"))
    #expect(report.installationVersions[1].version == "4.5.6")
}

@Test func offRootSelectedRetargetDuringQueryRetainsItsExactDiscoveryOrigin() throws {
    let root = try versionFixtureRoot("off-path-origin-retarget")
    defer { try? FileManager.default.removeItem(at: root) }
    let emptyPathRoot = root.appendingPathComponent("path", isDirectory: true)
    let selectedExtraRoot = root.appendingPathComponent("selected-extra", isDirectory: true)
    let unselectedExtraRoot = root.appendingPathComponent("unselected-extra", isDirectory: true)
    let targetARoot = root.appendingPathComponent("target-a", isDirectory: true)
    let targetBRoot = root.appendingPathComponent("target-b", isDirectory: true)
    try FileManager.default.createDirectory(at: emptyPathRoot, withIntermediateDirectories: true)
    let targetA = try makeVersionExecutable(in: targetARoot, named: "tool-a", version: "1.2.3")
    let targetB = try makeVersionExecutable(in: targetBRoot, named: "tool-b", version: "2.3.4")
    try FileManager.default.createDirectory(
        at: selectedExtraRoot,
        withIntermediateDirectories: true
    )
    let selectedEntry = selectedExtraRoot.appendingPathComponent("fixture-tool").path
    try FileManager.default.createSymbolicLink(atPath: selectedEntry, withDestinationPath: targetA)
    let unselectedEntry = try makeVersionExecutable(
        in: unselectedExtraRoot, named: "fixture-tool", version: "9.9.9"
    )
    let calls = VersionCallRecorder()
    let detector = ToolDetector(
        displayName: "Fixture Tool",
        executableName: "fixture-tool",
        extraSearchRoots: [selectedExtraRoot.path, unselectedExtraRoot.path],
        versionQuerySpecification: .standard,
        versionQuery: { path, environment, timeout, specification in
            calls.begin(path, timeout: timeout)
            defer { calls.end() }
            if path == selectedEntry {
                try? FileManager.default.removeItem(atPath: selectedEntry)
                try? FileManager.default.createSymbolicLink(
                    atPath: selectedEntry,
                    withDestinationPath: targetB
                )
                return "8.8.8"
            }
            return ToolDetector.queryVersion(
                executablePath: path,
                environment: environment,
                timeout: timeout,
                specification: specification
            )
        }
    )

    let report = PathDiagnosticsScanner.scan(
        detector: detector,
        environment: versionEnvironment([emptyPathRoot.path])
    )

    #expect(report.detectedTool.state == .installedNotOnPath)
    #expect(report.detectedTool.version == nil)
    #expect(report.shadowedInstallationCount == nil)
    if case .inconsistent = report.selection {
        // Expected: the selected off-root executable moved during collection.
    } else {
        Issue.record("an off-root selected retarget must invalidate the selection")
    }
    #expect(calls.paths == [selectedEntry])
    #expect(report.installationVersions.count == 1)
    let observation = try #require(report.installationVersions.first)
    #expect(observation.canonicalTarget == targetA)
    #expect(observation.entryPath == selectedEntry)
    #expect(observation.origin == .extraRoot(index: 0, directoryText: selectedExtraRoot.path))
    #expect(observation.outcome == .unknown(.identityChanged))
    #expect(observation.version == nil)
    #expect(!report.installationVersions.contains { $0.canonicalTarget == unselectedEntry })
}

@Test func vanishedOffRootSelectionRetainsItsExactDiscoveryOrigin() throws {
    let root = try versionFixtureRoot("off-path-origin-vanished")
    defer { try? FileManager.default.removeItem(at: root) }
    let emptyPathRoot = root.appendingPathComponent("path", isDirectory: true)
    let selectedExtraRoot = root.appendingPathComponent("selected-extra", isDirectory: true)
    let unselectedExtraRoot = root.appendingPathComponent("unselected-extra", isDirectory: true)
    try FileManager.default.createDirectory(at: emptyPathRoot, withIntermediateDirectories: true)
    let selectedEntry = try makeVersionExecutable(
        in: selectedExtraRoot, named: "fixture-tool", version: "1.2.3"
    )
    let unselectedEntry = try makeVersionExecutable(
        in: unselectedExtraRoot, named: "fixture-tool", version: "9.9.9"
    )
    let calls = VersionCallRecorder()
    let detector = ToolDetector(
        displayName: "Fixture Tool",
        executableName: "fixture-tool",
        extraSearchRoots: [selectedExtraRoot.path, unselectedExtraRoot.path],
        versionQuerySpecification: .standard,
        versionQuery: { path, environment, timeout, specification in
            calls.begin(path, timeout: timeout)
            defer { calls.end() }
            if path == selectedEntry {
                try? FileManager.default.removeItem(atPath: selectedEntry)
                return "8.8.8"
            }
            return ToolDetector.queryVersion(
                executablePath: path,
                environment: environment,
                timeout: timeout,
                specification: specification
            )
        }
    )

    let report = PathDiagnosticsScanner.scan(
        detector: detector,
        environment: versionEnvironment([emptyPathRoot.path])
    )

    #expect(report.detectedTool.state == .installedNotOnPath)
    #expect(report.detectedTool.version == nil)
    #expect(report.shadowedInstallationCount == nil)
    if case .inconsistent = report.selection {
        // Expected: the selected off-root executable vanished during collection.
    } else {
        Issue.record("a vanished off-root selection must invalidate the selection")
    }
    #expect(calls.paths == [selectedEntry])
    #expect(report.installationVersions.count == 1)
    let observation = try #require(report.installationVersions.first)
    #expect(observation.canonicalTarget == selectedEntry)
    #expect(observation.entryPath == selectedEntry)
    #expect(observation.origin == .extraRoot(index: 0, directoryText: selectedExtraRoot.path))
    #expect(observation.outcome == .unknown(.identityChanged))
    #expect(observation.version == nil)
    #expect(!report.installationVersions.contains { $0.canonicalTarget == unselectedEntry })
    #expect(!FileManager.default.fileExists(atPath: selectedEntry))
}
