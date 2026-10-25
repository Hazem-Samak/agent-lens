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
