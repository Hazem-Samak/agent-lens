import Darwin
import Foundation
import Testing
@testable import AgentLensCore

// M13-D R6 / OD-M13-7: the Darwin mutation-spawn contract.
//
// The operation entry point (`BoundedProcessRunner.runDualStream`, reached through
// `ProcessOperationCommandRunner`) must place the child in a NEW SESSION with no controlling
// terminal, while the single-stream query entry point keeps its historical SETPGROUP behaviour.
// A session leader is its own process-group leader, so the existing process-group TERM/KILL and
// reaping semantics still terminate the whole mutation group on timeout and cancellation.

private func spawnContractRoot(_ label: String) throws -> URL {
    try homebrewOperationScratchRoot(label)
}

private func mutationShellTask(pidFile: URL, script: String, timeout: TimeInterval) -> Task<OperationCommandResult, Never> {
    Task {
        await ProcessOperationCommandRunner().run(
            executablePath: "/bin/sh",
            arguments: ["-c", script],
            environment: ["PATH": "/usr/bin:/bin"],
            currentDirectory: pidFile.deletingLastPathComponent().path,
            timeout: timeout
        )
    }
}

@Test func mutationSpawnCreatesANewSessionWithoutAControllingTerminal() async throws {
    let root = try spawnContractRoot("spawn-session")
    defer { try? FileManager.default.removeItem(at: root) }
    let pidFile = root.appendingPathComponent("pid")
    let task = mutationShellTask(
        pidFile: pidFile,
        script: """
        printf '%s' "$$" > '\(pidFile.path)'
        if exec 3</dev/tty 2>/dev/null; then
          echo tty-open=YES
          exec 3<&-
        else
          echo tty-open=NO
        fi
        exec /bin/sleep 30
        """,
        timeout: 30
    )
    #expect(waitForHomebrewFile(pidFile))
    let pid = try #require(pid_t(try String(contentsOf: pidFile, encoding: .utf8)))
    #expect(Darwin.getsid(pid) == pid, "the mutation must be a new session leader")
    #expect(Darwin.getpgid(pid) == pid, "the session leader must also be its own process group")
    #expect(Darwin.getsid(pid) != Darwin.getsid(getpid()), "the mutation must not share our session")

    // The parent's own controlling terminal is observed so the report can say whether the stronger
    // pty case ran. Either way the child above must not be able to open /dev/tty.
    let parentTTY = open("/dev/tty", O_RDWR)
    if parentTTY >= 0 { close(parentTTY) }
    print("mutation-spawn parent-controlling-terminal=\(parentTTY >= 0)")

    task.cancel()
    let result = await task.value
    #expect(result.processStarted)
    #expect(result.cancelled)
    #expect(String(decoding: result.stdout, as: UTF8.self).contains("tty-open=NO"))
    #expect(waitForHomebrewProcessGone(pid))
}

@Test func singleStreamQuerySpawnKeepsItsInheritedSessionAndOwnGroup() async throws {
    let root = try spawnContractRoot("query-session")
    defer { try? FileManager.default.removeItem(at: root) }
    let pidFile = root.appendingPathComponent("pid")
    let task = Task {
        BoundedProcessRunner.run(
            executablePath: "/bin/sh",
            arguments: ["-c", "printf '%s' \"$$\" > '\(pidFile.path)'; exec /bin/sleep 30"],
            environment: ["PATH": "/usr/bin:/bin"],
            timeout: 30
        ) != nil
    }
    #expect(waitForHomebrewFile(pidFile))
    let pid = try #require(pid_t(try String(contentsOf: pidFile, encoding: .utf8)))
    // Historical behaviour retained: SETPGROUP only, so the child keeps the parent's session while
    // becoming its own process group.
    #expect(Darwin.getsid(pid) == Darwin.getsid(getpid()))
    #expect(Darwin.getpgid(pid) == pid)
    #expect(Darwin.getsid(pid) != pid)
    _ = kill(pid, SIGKILL)
    _ = await task.value
}

@Test func mutationTimeoutTerminatesTheWholeSessionProcessGroup() async throws {
    let root = try spawnContractRoot("spawn-timeout")
    defer { try? FileManager.default.removeItem(at: root) }
    let parentPIDFile = root.appendingPathComponent("parent-pid")
    let childPIDFile = root.appendingPathComponent("child-pid")
    let result = await ProcessOperationCommandRunner().run(
        executablePath: "/bin/sh",
        arguments: ["-c", """
        /bin/sh -c 'printf %s "$$" > "\(childPIDFile.path)"; exec /bin/sleep 30' &
        printf '%s' "$$" > "\(parentPIDFile.path)"
        exec /bin/sleep 30
        """],
        environment: ["PATH": "/usr/bin:/bin"],
        currentDirectory: root.path,
        timeout: 0.4
    )
    #expect(result.processStarted)
    #expect(result.timedOut)
    #expect(waitForHomebrewFile(parentPIDFile))
    #expect(waitForHomebrewFile(childPIDFile))
    let parentPID = try #require(pid_t(try String(contentsOf: parentPIDFile, encoding: .utf8)))
    let childPID = try #require(pid_t(try String(contentsOf: childPIDFile, encoding: .utf8)))
    #expect(waitForHomebrewProcessGone(parentPID), "the timed-out mutation session leader must be gone")
    #expect(waitForHomebrewProcessGone(childPID), "the timed-out mutation group child must be gone")
}

@Test func mutationCancellationTerminatesTheWholeSessionProcessGroup() async throws {
    let root = try spawnContractRoot("spawn-cancel")
    defer { try? FileManager.default.removeItem(at: root) }
    let parentPIDFile = root.appendingPathComponent("parent-pid")
    let childPIDFile = root.appendingPathComponent("child-pid")
    let task = mutationShellTask(
        pidFile: parentPIDFile,
        script: """
        /bin/sh -c 'printf %s "$$" > "\(childPIDFile.path)"; exec /bin/sleep 30' &
        printf '%s' "$$" > "\(parentPIDFile.path)"
        exec /bin/sleep 30
        """,
        timeout: 30
    )
    #expect(waitForHomebrewFile(parentPIDFile))
    #expect(waitForHomebrewFile(childPIDFile))
    let parentPID = try #require(pid_t(try String(contentsOf: parentPIDFile, encoding: .utf8)))
    let childPID = try #require(pid_t(try String(contentsOf: childPIDFile, encoding: .utf8)))
    task.cancel()
    let result = await task.value
    #expect(result.processStarted)
    #expect(result.cancelled)
    #expect(waitForHomebrewProcessGone(parentPID), "the cancelled mutation session leader must be gone")
    #expect(waitForHomebrewProcessGone(childPID), "the cancelled mutation group child must be gone")
}
