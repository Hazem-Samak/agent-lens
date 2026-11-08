import Darwin
import Foundation
import Testing
@testable import AgentLensCore

private func operationRunnerRoot(_ label: String) throws -> URL {
    let environment = ProcessInfo.processInfo.environment
    guard let basePath = [environment["AGENT_LENS_TEST_SCRATCH"], environment["TMPDIR"]]
        .compactMap({ $0 })
        .first(where: { !$0.isEmpty })
    else {
        throw NSError(domain: "OperationProcessRunnerTests", code: 1)
    }
    let root = URL(fileURLWithPath: basePath, isDirectory: true)
        .appendingPathComponent("agentlens-m10c-op-\(label)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root.resolvingSymlinksInPath()
}

private func runOperationShell(
    _ script: String,
    currentDirectory: String,
    timeout: TimeInterval = 5
) async -> OperationCommandResult {
    await ProcessOperationCommandRunner().run(
        executablePath: "/bin/sh",
        arguments: ["-c", script],
        environment: ["PATH": "/usr/bin:/bin"],
        currentDirectory: currentDirectory,
        timeout: timeout
    )
}

private func waitForFile(_ url: URL, timeout: TimeInterval = 5) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if FileManager.default.fileExists(atPath: url.path) { return true }
        Thread.sleep(forTimeInterval: 0.01)
    }
    return FileManager.default.fileExists(atPath: url.path)
}

@Test func operationRunnerCapturesBothInterleavedStreamsWithoutDeadlock() async throws {
    let root = try operationRunnerRoot("interleaved")
    defer { try? FileManager.default.removeItem(at: root) }
    let result = await runOperationShell(
        "i=0; while [ $i -lt 2000 ]; do printf 'O%04d' \"$i\"; printf 'E%04d' \"$i\" >&2; i=$((i+1)); done",
        currentDirectory: root.path
    )
    #expect(result.processStarted)
    #expect(result.exitStatus == 0)
    #expect(!result.stdoutTruncated)
    #expect(!result.stderrTruncated)
    #expect(result.stdout.count >= 10_000)
    #expect(result.stderr.count >= 10_000)
    #expect(String(decoding: result.stdout, as: UTF8.self).contains("O1999"))
    #expect(String(decoding: result.stderr, as: UTF8.self).contains("E1999"))
}

@Test func operationRunnerTruncatesEachStreamExplicitly() async throws {
    let root = try operationRunnerRoot("truncate")
    defer { try? FileManager.default.removeItem(at: root) }
    let result = await runOperationShell(
        "/usr/bin/yes O | /usr/bin/head -c 1048600; /usr/bin/yes E 1>&2 | /usr/bin/head -c 1048600",
        currentDirectory: root.path
    )
    #expect(result.processStarted)
    #expect(result.stdout.count <= BoundedProcessRunner.maximumStandardOutputBytes)
    #expect(result.stderr.count <= BoundedProcessRunner.maximumStandardOutputBytes)
    #expect(result.stdoutTruncated || result.stderrTruncated)
}

@Test func operationRunnerCapturesWorkingDirectoryAndSeparateStderr() async throws {
    let root = try operationRunnerRoot("cwd")
    defer { try? FileManager.default.removeItem(at: root) }
    let result = await runOperationShell(
        "pwd; printf 'diagnostic' >&2",
        currentDirectory: root.path
    )
    #expect(result.processStarted)
    #expect(result.exitStatus == 0)
    let physical = root.path.withCString { realpath($0, nil) }
    let expected = physical.map { String(cString: $0) } ?? root.path
    #expect(String(decoding: result.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        == expected)
    #expect(String(decoding: result.stderr, as: UTF8.self) == "diagnostic")
}

@Test func operationRunnerReportsTimeoutAndReapsTheOwnedProcessGroup() async throws {
    let root = try operationRunnerRoot("timeout")
    defer { try? FileManager.default.removeItem(at: root) }
    let pidFile = root.appendingPathComponent("pid")
    let result = await runOperationShell(
        "printf '%s' \"$$\" > '\(pidFile.path)'; exec /bin/sleep 30",
        currentDirectory: root.path,
        timeout: 0.2
    )
    #expect(result.processStarted)
    #expect(result.timedOut)
    #expect(waitForFile(pidFile))
    let pid = try #require(pid_t(try String(contentsOf: pidFile, encoding: .utf8)))
    #expect(waitForProcessGone(pid))
}

@Test func operationRunnerCancellationUsesTheSameBoundedGroupCleanup() async throws {
    let root = try operationRunnerRoot("cancel")
    defer { try? FileManager.default.removeItem(at: root) }
    let pidFile = root.appendingPathComponent("pid")
    let task = Task {
        await runOperationShell(
            "printf '%s' \"$$\" > '\(pidFile.path)'; exec /bin/sleep 30",
            currentDirectory: root.path,
            timeout: 30
        )
    }
    #expect(waitForFile(pidFile))
    task.cancel()
    let result = await task.value
    #expect(result.processStarted)
    #expect(result.cancelled)
    let pid = try #require(pid_t(try String(contentsOf: pidFile, encoding: .utf8)))
    #expect(waitForProcessGone(pid))
}

@Test func operationRunnerMapsSpawnFailureWithoutAStartedProcess() async throws {
    let root = try operationRunnerRoot("spawn-failure")
    defer { try? FileManager.default.removeItem(at: root) }
    let result = await ProcessOperationCommandRunner().run(
        executablePath: root.appendingPathComponent("missing").path,
        arguments: [], environment: ["PATH": "/usr/bin:/bin"],
        currentDirectory: root.path, timeout: 1
    )
    #expect(!result.processStarted)
    #expect(!result.timedOut)
    #expect(!result.cancelled)
}

private func waitForProcessGone(_ pid: pid_t, timeout: TimeInterval = 3) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if kill(pid, 0) != 0 { return true }
        Thread.sleep(forTimeInterval: 0.02)
    }
    return kill(pid, 0) != 0
}

@Test func operationRunnerReapsADelayedChildAfterParentExit() async throws {
    let root = try operationRunnerRoot("delayed-child")
    defer { try? FileManager.default.removeItem(at: root) }
    let childPIDFile = root.appendingPathComponent("child-pid")
    let result = await runOperationShell(
        "/bin/sh -c 'printf %s \"$$\" > \"\(childPIDFile.path)\"; exec /bin/sleep 30' & exit 0",
        currentDirectory: root.path,
        timeout: 5
    )
    #expect(result.processStarted)
    #expect(result.exitStatus == 0)
    #expect(waitForFile(childPIDFile))
    let childPID = try #require(pid_t(try String(contentsOf: childPIDFile, encoding: .utf8)))
    #expect(waitForProcessGone(childPID), "the runner must reap the delayed child process group")
}

@Test func operationRunnerOverflowIsExplicitAndDoesNotMasqueradeAsSuccessEvidence() async throws {
    let root = try operationRunnerRoot("overflow")
    defer { try? FileManager.default.removeItem(at: root) }
    let result = await runOperationShell(
        "/usr/bin/yes O | /usr/bin/head -c 1100000; printf E >&2",
        currentDirectory: root.path,
        timeout: 5
    )
    #expect(result.processStarted)
    #expect(result.stdoutTruncated)
    #expect(result.exitStatus == 0)
    #expect(result.stdout.count <= BoundedProcessRunner.maximumStandardOutputBytes)
}

/// A cancellation delivered after the entry check but before `posix_spawn` must not start a
/// process. The injected closure returns false once (entry) and true at the last check.
@Test func cancellationDuringSetupPreventsSpawn() throws {
    let root = try operationRunnerRoot("prelaunch-cancel")
    defer { try? FileManager.default.removeItem(at: root) }
    let marker = root.appendingPathComponent("spawned")

    final class SetupCancellation: @unchecked Sendable {
        private let lock = NSLock()
        private var calls = 0
        func next() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            calls += 1
            return calls > 1
        }
    }

    let cancellation = SetupCancellation()
    let result = BoundedProcessRunner.runDualStream(
        executablePath: "/bin/sh",
        arguments: ["-c", "printf spawned > '\(marker.path)'"],
        environment: ["PATH": "/usr/bin:/bin"],
        currentDirectory: root.path,
        timeout: 5,
        isCancelled: { cancellation.next() }
    )
    #expect(result?.cancelled == true)
    #expect(result?.processStarted == false)
    #expect(result?.exitStatus == nil)
    #expect(!FileManager.default.fileExists(atPath: marker.path))
}
