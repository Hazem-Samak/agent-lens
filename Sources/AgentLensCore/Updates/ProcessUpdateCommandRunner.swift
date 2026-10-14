// ProcessUpdateCommandRunner — production bridge from the bounded, synchronous process runner
// to the async UpdateCommandRunner seam (brief §"Homebrew batch contract").
//
// The blocking BoundedProcessRunner call runs on a utility dispatch queue inside a checked
// continuation, so no actor or the main executor blocks. The runner reports only what it
// can observe: spawn failure, timeout, output-limit overflow, and nonzero exit. It cannot
// distinguish DNS or HTTP 429 from other failures, so those map to probeFailed (never guessed).

import Foundation

public struct ProcessUpdateCommandRunner: UpdateCommandRunner {

    public init() {}

    public func run(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval
    ) async -> CommandOutcome {
        await withCheckedContinuation { (continuation: CheckedContinuation<CommandOutcome, Never>) in
            DispatchQueue.global(qos: .utility).async {
                let outcome = Self.launch(
                    executablePath: executablePath,
                    arguments: arguments,
                    environment: environment,
                    timeout: timeout
                )
                continuation.resume(returning: outcome)
            }
        }
    }

    static func launch(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval
    ) -> CommandOutcome {
        guard let result = BoundedProcessRunner.run(
            executablePath: executablePath,
            arguments: arguments,
            environment: environment,
            timeout: timeout
        ) else {
            return .failure(.spawnFailure)
        }
        if result.timedOut { return .failure(.timedOut) }
        if result.outputLimitExceeded { return .failure(.outputLimitExceeded) }
        guard result.exitStatus == 0 else { return .failure(.nonzeroExit) }
        return .success(result.standardOutput)
    }
}
