// OperationProcessRunner — the production mutation-process bridge.
//
// The blocking dual-stream runner runs on a utility queue. Task cancellation is converted into a
// thread-safe flag the synchronous poll loop can observe; after launch the runner's TERM/KILL path
// owns the exact process group and joins it before this bridge returns.

import Dispatch
import Foundation

/// Thread-safe cancellation signal spanning the async boundary and the synchronous poll loop.
final class OperationCancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

public struct ProcessOperationCommandRunner: OperationCommandRunner {

    public init() {}

    public func run(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        currentDirectory: String,
        timeout: TimeInterval
    ) async -> OperationCommandResult {
        if Task.isCancelled {
            return OperationCommandResult(
                stdout: Data(), stderr: Data(),
                stdoutTruncated: false, stderrTruncated: false,
                exitStatus: nil, processStarted: false,
                timedOut: false, cancelled: true, cleanupWarning: false
            )
        }
        let cancellation = OperationCancellationFlag()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<OperationCommandResult, Never>) in
                DispatchQueue.global(qos: .utility).async {
                    let outcome = BoundedProcessRunner.runDualStream(
                        executablePath: executablePath,
                        arguments: arguments,
                        environment: environment,
                        currentDirectory: currentDirectory,
                        timeout: timeout,
                        isCancelled: { cancellation.isCancelled }
                    )
                    guard let outcome else {
                        continuation.resume(returning: OperationCommandResult(
                            stdout: Data(), stderr: Data(),
                            stdoutTruncated: false, stderrTruncated: false,
                            exitStatus: nil, processStarted: false,
                            timedOut: false, cancelled: false, cleanupWarning: false
                        ))
                        return
                    }
                    continuation.resume(returning: OperationCommandResult(
                        stdout: outcome.standardOutput,
                        stderr: outcome.standardError,
                        stdoutTruncated: outcome.stdoutTruncated,
                        stderrTruncated: outcome.stderrTruncated,
                        exitStatus: outcome.exitStatus,
                        processStarted: outcome.processStarted,
                        timedOut: outcome.timedOut,
                        cancelled: outcome.cancelled,
                        cleanupWarning: outcome.cleanupWarning
                    ))
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }
}
