import Darwin
import Foundation

/// Synchronously captures one selected output stream while enforcing a wall-clock
/// deadline for the launched process group. No background reader can remain
/// blocked after return. The default stream is stdout, preserving every existing
/// caller; M9-A adds stderr capture for declared version-query specifications.
enum BoundedProcessRunner {
    enum CaptureStream {
        case standardOutput
        case standardError
    }

    static let maximumStandardOutputBytes = 1_048_576

    struct Result {
        /// The captured stream (stdout by default, or stderr when requested).
        let standardOutput: Data
        let exitStatus: Int32?
        let timedOut: Bool
        let outputLimitExceeded: Bool
    }

    static func run(
        executablePath: String,
        arguments: [String],
        environment: [String: String]? = nil,
        timeout: TimeInterval,
        captureStream: CaptureStream = .standardOutput
    ) -> Result? {
        var pipeDescriptors = [Int32](repeating: -1, count: 2)
        guard pipeDescriptors.withUnsafeMutableBufferPointer({ pipe($0.baseAddress!) }) == 0 else {
            return nil
        }

        var readDescriptor = pipeDescriptors[0]
        var writeDescriptor = pipeDescriptors[1]
        var nullDescriptor = open("/dev/null", O_RDWR)
        guard nullDescriptor >= 0 else {
            close(readDescriptor)
            close(writeDescriptor)
            return nil
        }
        defer {
            if readDescriptor >= 0 { close(readDescriptor) }
            if writeDescriptor >= 0 { close(writeDescriptor) }
            if nullDescriptor >= 0 { close(nullDescriptor) }
        }

        for descriptor in [readDescriptor, writeDescriptor] {
            let flags = fcntl(descriptor, F_GETFD)
            guard flags >= 0, fcntl(descriptor, F_SETFD, flags | FD_CLOEXEC) >= 0 else {
                return nil
            }
        }
        let readFlags = fcntl(readDescriptor, F_GETFL)
        guard readFlags >= 0, fcntl(readDescriptor, F_SETFL, readFlags | O_NONBLOCK) >= 0 else {
            return nil
        }

        var fileActions: posix_spawn_file_actions_t? = nil
        guard posix_spawn_file_actions_init(&fileActions) == 0 else { return nil }
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        let capturedFileDescriptor = captureStream == .standardOutput
            ? STDOUT_FILENO
            : STDERR_FILENO
        let discardedFileDescriptor = captureStream == .standardOutput
            ? STDERR_FILENO
            : STDOUT_FILENO
        let fileActionStatuses = [
            posix_spawn_file_actions_adddup2(&fileActions, writeDescriptor, capturedFileDescriptor),
            posix_spawn_file_actions_adddup2(&fileActions, nullDescriptor, STDIN_FILENO),
            posix_spawn_file_actions_adddup2(&fileActions, nullDescriptor, discardedFileDescriptor),
            posix_spawn_file_actions_addclose(&fileActions, readDescriptor),
            posix_spawn_file_actions_addclose(&fileActions, writeDescriptor),
            posix_spawn_file_actions_addclose(&fileActions, nullDescriptor)
        ]
        guard fileActionStatuses.allSatisfy({ $0 == 0 }) else { return nil }

        var spawnAttributes: posix_spawnattr_t? = nil
        guard posix_spawnattr_init(&spawnAttributes) == 0 else { return nil }
        defer { posix_spawnattr_destroy(&spawnAttributes) }
        guard posix_spawnattr_setflags(&spawnAttributes, Int16(POSIX_SPAWN_SETPGROUP)) == 0,
              posix_spawnattr_setpgroup(&spawnAttributes, 0) == 0
        else {
            return nil
        }

        let environmentValues = environment.map { values in
            values.keys.sorted().map { "\($0)=\(values[$0] ?? "")" }
        } ?? inheritedEnvironmentValues()
        guard let argumentVector = CStringVector([executablePath] + arguments),
              let environmentVector = CStringVector(environmentValues)
        else {
            return nil
        }

        let startedAt = DispatchTime.now().uptimeNanoseconds
        let safeTimeout = timeout.isFinite ? max(0, timeout) : 0
        let maximumTimeout = Double(UInt64.max - startedAt) / 1_000_000_000
        let timeoutNanoseconds = UInt64(min(safeTimeout, maximumTimeout) * 1_000_000_000)
        let deadline = startedAt + timeoutNanoseconds

        var processIdentifier: pid_t = 0
        let spawnStatus = executablePath.withCString { executableCString in
            argumentVector.pointers.withUnsafeBufferPointer { argumentBuffer in
                environmentVector.pointers.withUnsafeBufferPointer { environmentBuffer in
                    posix_spawn(
                        &processIdentifier,
                        executableCString,
                        &fileActions,
                        &spawnAttributes,
                        argumentBuffer.baseAddress!,
                        environmentBuffer.baseAddress!
                    )
                }
            }
        }
        guard spawnStatus == 0 else { return nil }

        close(writeDescriptor)
        writeDescriptor = -1
        close(nullDescriptor)
        nullDescriptor = -1

        var output = Data()
        var stdoutReachedEOF = false
        var readFailed = false
        var childWasReaped = false
        var exitStatus: Int32?
        var outputLimitExceeded = false
        var buffer = [UInt8](repeating: 0, count: 16_384)

        while true {
            var deadlineReachedDuringRead = false
            if !stdoutReachedEOF {
                while true {
                    if DispatchTime.now().uptimeNanoseconds >= deadline {
                        deadlineReachedDuringRead = true
                        break
                    }
                    let remainingOutputBytes = Self.maximumStandardOutputBytes - output.count
                    let bytesRead = buffer.withUnsafeMutableBytes { rawBuffer in
                        Darwin.read(
                            readDescriptor,
                            rawBuffer.baseAddress!,
                            min(rawBuffer.count, remainingOutputBytes + 1)
                        )
                    }
                    if bytesRead > 0 {
                        let byteCount = Int(bytesRead)
                        if byteCount > remainingOutputBytes {
                            if remainingOutputBytes > 0 {
                                output.append(contentsOf: buffer.prefix(remainingOutputBytes))
                            }
                            outputLimitExceeded = true
                            break
                        }
                        output.append(contentsOf: buffer.prefix(byteCount))
                    } else if bytesRead == 0 {
                        stdoutReachedEOF = true
                        close(readDescriptor)
                        readDescriptor = -1
                        break
                    } else if errno == EINTR {
                        continue
                    } else if errno == EAGAIN || errno == EWOULDBLOCK {
                        break
                    } else {
                        readFailed = true
                        stdoutReachedEOF = true
                        close(readDescriptor)
                        readDescriptor = -1
                        break
                    }
                }
            }

            if outputLimitExceeded {
                Self.killAndReapProcessGroup(processIdentifier, childWasReaped: childWasReaped)
                return Result(
                    standardOutput: output,
                    exitStatus: nil,
                    timedOut: false,
                    outputLimitExceeded: true
                )
            }

            let now = DispatchTime.now().uptimeNanoseconds
            if deadlineReachedDuringRead || now >= deadline {
                Self.killAndReapProcessGroup(processIdentifier, childWasReaped: childWasReaped)
                return Result(
                    standardOutput: output,
                    exitStatus: nil,
                    timedOut: true,
                    outputLimitExceeded: false
                )
            }

            if !childWasReaped {
                var waitStatus: Int32 = 0
                let waitResult = waitpid(processIdentifier, &waitStatus, WNOHANG)
                if waitResult == processIdentifier {
                    childWasReaped = true
                    exitStatus = Self.exitStatus(from: waitStatus)
                } else if waitResult < 0, errno == ECHILD {
                    childWasReaped = true
                } else if waitResult < 0, errno != EINTR {
                    Self.killAndReapProcessGroup(processIdentifier, childWasReaped: false)
                    return nil
                }
            }

            if childWasReaped && stdoutReachedEOF && !Self.processGroupExists(processIdentifier) {
                if DispatchTime.now().uptimeNanoseconds >= deadline {
                    Self.killAndReapProcessGroup(processIdentifier, childWasReaped: childWasReaped)
                    return Result(
                        standardOutput: output,
                        exitStatus: nil,
                        timedOut: true,
                        outputLimitExceeded: false
                    )
                }
                guard !readFailed else { return nil }
                return Result(
                    standardOutput: output,
                    exitStatus: exitStatus,
                    timedOut: false,
                    outputLimitExceeded: false
                )
            }

            let pollNow = DispatchTime.now().uptimeNanoseconds
            if pollNow >= deadline {
                Self.killAndReapProcessGroup(processIdentifier, childWasReaped: childWasReaped)
                return Result(
                    standardOutput: output,
                    exitStatus: nil,
                    timedOut: true,
                    outputLimitExceeded: false
                )
            }

            let remainingMilliseconds = Int32(min(50, max(1, (deadline - pollNow) / 1_000_000)))
            let pollStatus: Int32
            if stdoutReachedEOF {
                pollStatus = poll(nil, 0, remainingMilliseconds)
            } else {
                var descriptor = pollfd(
                    fd: readDescriptor,
                    events: Int16(POLLIN | POLLHUP | POLLERR),
                    revents: 0
                )
                pollStatus = poll(&descriptor, nfds_t(1), remainingMilliseconds)
            }
            if pollStatus < 0, errno != EINTR {
                Self.killAndReapProcessGroup(processIdentifier, childWasReaped: childWasReaped)
                return nil
            }
        }
    }


    // MARK: - Operation-specific dual-stream API

    /// Operation-only result. The existing single-stream `Result` and every read-only caller keep
    /// their exact behavior; this result adds a second captured stream, explicit per-stream
    /// truncation, cancellation, and an operation root working directory.
    struct DualStreamResult: Sendable {
        let standardOutput: Data
        let standardError: Data
        let exitStatus: Int32?
        let timedOut: Bool
        let outputLimitExceeded: Bool
        let stdoutTruncated: Bool
        let stderrTruncated: Bool
        let cancelled: Bool
        let processStarted: Bool
        let cleanupWarning: Bool
    }

    /// Runs one operation process with separate stdout/stderr capture, a captured working
    /// directory, a bounded 1 MiB prefix per stream, and a process-group-bound cancellation path.
    /// Both pipes are polled together so a noisy stderr cannot deadlock stdout. `nil` means spawn
    /// failed before a process was created.
    static func runDualStream(
        executablePath: String,
        arguments: [String],
        environment: [String: String]? = nil,
        currentDirectory: String? = nil,
        timeout: TimeInterval,
        isCancelled: @escaping @Sendable () -> Bool = { false }
    ) -> DualStreamResult? {
        if isCancelled() {
            return DualStreamResult(
                standardOutput: Data(), standardError: Data(), exitStatus: nil,
                timedOut: false, outputLimitExceeded: false,
                stdoutTruncated: false, stderrTruncated: false,
                cancelled: true, processStarted: false, cleanupWarning: false
            )
        }

        var stdoutDescriptors = [Int32](repeating: -1, count: 2)
        var stderrDescriptors = [Int32](repeating: -1, count: 2)
        guard stdoutDescriptors.withUnsafeMutableBufferPointer({ pipe($0.baseAddress!) }) == 0,
              stderrDescriptors.withUnsafeMutableBufferPointer({ pipe($0.baseAddress!) }) == 0
        else {
            for descriptor in stdoutDescriptors + stderrDescriptors where descriptor >= 0 {
                close(descriptor)
            }
            return nil
        }
        let stdoutRead = stdoutDescriptors[0]
        var stdoutWrite = stdoutDescriptors[1]
        let stderrRead = stderrDescriptors[0]
        var stderrWrite = stderrDescriptors[1]
        var nullDescriptor = open("/dev/null", O_RDWR)
        guard nullDescriptor >= 0 else {
            for descriptor in [stdoutRead, stdoutWrite, stderrRead, stderrWrite] where descriptor >= 0 {
                close(descriptor)
            }
            return nil
        }
        defer {
            if stdoutRead >= 0 { close(stdoutRead) }
            if stdoutWrite >= 0 { close(stdoutWrite) }
            if stderrRead >= 0 { close(stderrRead) }
            if stderrWrite >= 0 { close(stderrWrite) }
            if nullDescriptor >= 0 { close(nullDescriptor) }
        }

        for descriptor in [stdoutRead, stdoutWrite, stderrRead, stderrWrite] {
            let flags = fcntl(descriptor, F_GETFD)
            guard flags >= 0, fcntl(descriptor, F_SETFD, flags | FD_CLOEXEC) >= 0 else {
                return nil
            }
        }
        for descriptor in [stdoutRead, stderrRead] {
            let flags = fcntl(descriptor, F_GETFL)
            guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) >= 0 else {
                return nil
            }
        }

        var fileActions: posix_spawn_file_actions_t? = nil
        guard posix_spawn_file_actions_init(&fileActions) == 0 else { return nil }
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        let actionStatuses = [
            posix_spawn_file_actions_adddup2(&fileActions, stdoutWrite, STDOUT_FILENO),
            posix_spawn_file_actions_adddup2(&fileActions, stderrWrite, STDERR_FILENO),
            posix_spawn_file_actions_adddup2(&fileActions, nullDescriptor, STDIN_FILENO),
            posix_spawn_file_actions_addclose(&fileActions, stdoutRead),
            posix_spawn_file_actions_addclose(&fileActions, stdoutWrite),
            posix_spawn_file_actions_addclose(&fileActions, stderrRead),
            posix_spawn_file_actions_addclose(&fileActions, stderrWrite),
            posix_spawn_file_actions_addclose(&fileActions, nullDescriptor),
        ]
        guard actionStatuses.allSatisfy({ $0 == 0 }) else { return nil }
        if let currentDirectory {
            let status = currentDirectory.withCString {
                posix_spawn_file_actions_addchdir_np(&fileActions, $0)
            }
            guard status == 0 else { return nil }
        }

        var spawnAttributes: posix_spawnattr_t? = nil
        guard posix_spawnattr_init(&spawnAttributes) == 0 else { return nil }
        defer { posix_spawnattr_destroy(&spawnAttributes) }
        guard posix_spawnattr_setflags(&spawnAttributes, Int16(POSIX_SPAWN_SETPGROUP)) == 0,
              posix_spawnattr_setpgroup(&spawnAttributes, 0) == 0
        else {
            return nil
        }

        let environmentValues = environment.map { values in
            values.keys.sorted().map { "\($0)=\(values[$0] ?? "")" }
        } ?? inheritedEnvironmentValues()
        guard let argumentVector = CStringVector([executablePath] + arguments),
              let environmentVector = CStringVector(environmentValues)
        else {
            return nil
        }

        let startedAt = DispatchTime.now().uptimeNanoseconds
        let safeTimeout = timeout.isFinite ? max(0, timeout) : 0
        let maximumTimeout = Double(UInt64.max - startedAt) / 1_000_000_000
        let timeoutNanoseconds = UInt64(min(safeTimeout, maximumTimeout) * 1_000_000_000)
        let deadline = startedAt + timeoutNanoseconds

        var processIdentifier: pid_t = 0
        let spawnStatus = executablePath.withCString { executableCString in
            argumentVector.pointers.withUnsafeBufferPointer { argumentBuffer in
                environmentVector.pointers.withUnsafeBufferPointer { environmentBuffer in
                    posix_spawn(
                        &processIdentifier,
                        executableCString,
                        &fileActions,
                        &spawnAttributes,
                        argumentBuffer.baseAddress!,
                        environmentBuffer.baseAddress!
                    )
                }
            }
        }
        guard spawnStatus == 0 else { return nil }

        close(stdoutWrite)
        stdoutWrite = -1
        close(stderrWrite)
        stderrWrite = -1
        close(nullDescriptor)
        nullDescriptor = -1

        var stdoutData = Data()
        var stderrData = Data()
        var stdoutEOF = false
        var stderrEOF = false
        var stdoutTruncated = false
        var stderrTruncated = false
        var childWasReaped = false
        var exitStatus: Int32?
        var cleanupWarning = false
        var buffer = [UInt8](repeating: 0, count: 16_384)

        func drain(_ descriptor: Int32, into data: inout Data, eof: inout Bool,
                   truncated: inout Bool) {
            guard !eof else { return }
            while true {
                let remaining = Self.maximumStandardOutputBytes - data.count
                let bytesRead = buffer.withUnsafeMutableBytes { rawBuffer in
                    Darwin.read(
                        descriptor,
                        rawBuffer.baseAddress!,
                        min(rawBuffer.count, remaining + 1)
                    )
                }
                if bytesRead > 0 {
                    let count = Int(bytesRead)
                    if count > remaining {
                        if remaining > 0 { data.append(contentsOf: buffer.prefix(remaining)) }
                        truncated = true
                        break
                    }
                    data.append(contentsOf: buffer.prefix(count))
                } else if bytesRead == 0 {
                    eof = true
                    break
                } else if errno == EINTR {
                    continue
                } else if errno == EAGAIN || errno == EWOULDBLOCK {
                    break
                } else {
                    eof = true
                    break
                }
            }
        }

        func reap() {
            guard !childWasReaped else { return }
            var status: Int32 = 0
            let result = waitpid(processIdentifier, &status, WNOHANG)
            if result == processIdentifier {
                childWasReaped = true
                exitStatus = Self.exitStatus(from: status)
            } else if result < 0, errno == ECHILD {
                childWasReaped = true
            }
        }

        func pollPipes(milliseconds: Int32) {
            var descriptors: [pollfd] = []
            if !stdoutEOF, stdoutRead >= 0 {
                descriptors.append(pollfd(
                    fd: stdoutRead, events: Int16(POLLIN | POLLHUP | POLLERR), revents: 0
                ))
            }
            if !stderrEOF, stderrRead >= 0 {
                descriptors.append(pollfd(
                    fd: stderrRead, events: Int16(POLLIN | POLLHUP | POLLERR), revents: 0
                ))
            }
            if descriptors.isEmpty {
                _ = poll(nil, 0, milliseconds)
            } else {
                descriptors.withUnsafeMutableBufferPointer {
                    _ = poll($0.baseAddress, nfds_t($0.count), milliseconds)
                }
            }
        }

        func terminateAndDrain() -> DualStreamResult {
            _ = kill(-processIdentifier, SIGTERM)
            let graceDeadline = DispatchTime.now().uptimeNanoseconds + 2_000_000_000
            while DispatchTime.now().uptimeNanoseconds < graceDeadline {
                drain(stdoutRead, into: &stdoutData, eof: &stdoutEOF, truncated: &stdoutTruncated)
                drain(stderrRead, into: &stderrData, eof: &stderrEOF, truncated: &stderrTruncated)
                reap()
                if childWasReaped, stdoutEOF, stderrEOF,
                   !Self.processGroupExists(processIdentifier) {
                    break
                }
                pollPipes(milliseconds: 20)
            }
            if !childWasReaped || Self.processGroupExists(processIdentifier) {
                _ = kill(-processIdentifier, SIGKILL)
                let killDeadline = DispatchTime.now().uptimeNanoseconds + 1_000_000_000
                while DispatchTime.now().uptimeNanoseconds < killDeadline {
                    drain(stdoutRead, into: &stdoutData, eof: &stdoutEOF, truncated: &stdoutTruncated)
                    drain(stderrRead, into: &stderrData, eof: &stderrEOF, truncated: &stderrTruncated)
                    reap()
                    if childWasReaped, stdoutEOF, stderrEOF,
                       !Self.processGroupExists(processIdentifier) {
                        break
                    }
                    pollPipes(milliseconds: 20)
                }
            }
            cleanupWarning = !childWasReaped || Self.processGroupExists(processIdentifier)
            return DualStreamResult(
                standardOutput: stdoutData,
                standardError: stderrData,
                exitStatus: exitStatus,
                timedOut: false,
                outputLimitExceeded: false,
                stdoutTruncated: stdoutTruncated,
                stderrTruncated: stderrTruncated,
                cancelled: false,
                processStarted: true,
                cleanupWarning: cleanupWarning
            )
        }

        while true {
            if isCancelled() {
                var result = terminateAndDrain()
                result = DualStreamResult(
                    standardOutput: result.standardOutput,
                    standardError: result.standardError,
                    exitStatus: result.exitStatus,
                    timedOut: false,
                    outputLimitExceeded: false,
                    stdoutTruncated: result.stdoutTruncated,
                    stderrTruncated: result.stderrTruncated,
                    cancelled: true,
                    processStarted: true,
                    cleanupWarning: result.cleanupWarning
                )
                return result
            }

            drain(stdoutRead, into: &stdoutData, eof: &stdoutEOF, truncated: &stdoutTruncated)
            drain(stderrRead, into: &stderrData, eof: &stderrEOF, truncated: &stderrTruncated)
            if stdoutTruncated || stderrTruncated {
                var result = terminateAndDrain()
                result = DualStreamResult(
                    standardOutput: result.standardOutput,
                    standardError: result.standardError,
                    exitStatus: result.exitStatus,
                    timedOut: false,
                    outputLimitExceeded: true,
                    stdoutTruncated: result.stdoutTruncated,
                    stderrTruncated: result.stderrTruncated,
                    cancelled: false,
                    processStarted: true,
                    cleanupWarning: result.cleanupWarning
                )
                return result
            }

            reap()
            if childWasReaped, stdoutEOF, stderrEOF,
               !Self.processGroupExists(processIdentifier) {
                return DualStreamResult(
                    standardOutput: stdoutData,
                    standardError: stderrData,
                    exitStatus: exitStatus,
                    timedOut: false,
                    outputLimitExceeded: false,
                    stdoutTruncated: false,
                    stderrTruncated: false,
                    cancelled: false,
                    processStarted: true,
                    cleanupWarning: cleanupWarning
                )
            }

            let now = DispatchTime.now().uptimeNanoseconds
            if now >= deadline {
                var result = terminateAndDrain()
                result = DualStreamResult(
                    standardOutput: result.standardOutput,
                    standardError: result.standardError,
                    exitStatus: result.exitStatus,
                    timedOut: true,
                    outputLimitExceeded: false,
                    stdoutTruncated: result.stdoutTruncated,
                    stderrTruncated: result.stderrTruncated,
                    cancelled: false,
                    processStarted: true,
                    cleanupWarning: result.cleanupWarning
                )
                return result
            }

            let remaining = Int32(min(50, max(1, (deadline - now) / 1_000_000)))
            pollPipes(milliseconds: remaining)
        }
    }

    private static func inheritedEnvironmentValues() -> [String] {
        var values: [String] = []
        var cursor = environ
        while let entry = cursor.pointee {
            values.append(String(cString: entry))
            cursor = cursor.advanced(by: 1)
        }
        return values
    }

    private static func exitStatus(from waitStatus: Int32) -> Int32 {
        let signal = waitStatus & 0x7f
        return signal == 0 ? (waitStatus >> 8) & 0xff : 128 + signal
    }

    private static func processGroupExists(_ processGroup: pid_t) -> Bool {
        if kill(-processGroup, 0) == 0 { return true }
        return errno != ESRCH
    }

    private static func killAndReapProcessGroup(_ processGroup: pid_t, childWasReaped: Bool) {
        _ = kill(-processGroup, SIGKILL)
        let cleanupStartedAt = DispatchTime.now().uptimeNanoseconds
        let cleanupDeadline = cleanupStartedAt + 100_000_000
        var childReaped = childWasReaped
        var waitStatus: Int32 = 0

        while DispatchTime.now().uptimeNanoseconds < cleanupDeadline {
            if !childReaped {
                let waitResult = waitpid(processGroup, &waitStatus, WNOHANG)
                childReaped = waitResult == processGroup || (waitResult < 0 && errno == ECHILD)
            }
            if childReaped && !processGroupExists(processGroup) { return }
            _ = poll(nil, 0, 5)
        }

        if !childReaped { _ = waitpid(processGroup, &waitStatus, WNOHANG) }
    }
}

private final class CStringVector {
    let pointers: [UnsafeMutablePointer<CChar>?]

    init?(_ strings: [String]) {
        var allocated: [UnsafeMutablePointer<CChar>?] = []
        for string in strings {
            guard let pointer = strdup(string) else {
                for pointer in allocated { if let pointer { free(pointer) } }
                return nil
            }
            allocated.append(pointer)
        }
        allocated.append(nil)
        pointers = allocated
    }

    deinit {
        for pointer in pointers {
            if let pointer { free(pointer) }
        }
    }
}
