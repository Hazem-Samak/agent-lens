// agent-lens — the CLI executable (D-016: the MVP ships as a command-line tool).
//
// M3: `scan` performs real detection (ToolDetector + ShellEnvironment); the
// argument-ordered dispatch from M1 is unchanged. Argument index 1 is the
// subcommand (index 0 is the program name).
//
// M6: `scan` accepts exactly one optional update mode. The M5 PATH report is printed
// first and unchanged; the VERSION / UPDATE STATUS section is appended after it.
// Invalid syntax exits 1 with usage on stderr. A probe failure never changes the exit.

import AgentLensCore
import Foundation

let args = CommandLine.arguments

func printUsage() {
    print(WalkingSkeleton.usageMessage)
}

func usageError() -> Never {
    FileHandle.standardError.write(Data((WalkingSkeleton.usageMessage + "\n").utf8))
    exit(1)
}

/// The four scan forms plus the no-argument/unknown behavior. Exactly one optional mode.
enum ScanMode {
    case localOnly
    case checkUpdates
    case refreshUpdates
    case offline

    /// Parses the operands after `scan`. Repeated, combined, or extra operands are rejected.
    static func parse(_ operands: [String]) -> ScanMode? {
        switch operands {
        case []: return .localOnly
        case ["--check-updates"]: return .checkUpdates
        case ["--refresh-updates"]: return .refreshUpdates
        case ["--offline"]: return .offline
        default: return nil
        }
    }

    var probeMode: UpdateProbeMode {
        switch self {
        case .localOnly: .localOnly
        case .checkUpdates: .checkUpdates
        case .refreshUpdates: .refresh
        case .offline: .offline
        }
    }
}

/// The update metadata cache lives in the app-owned caches directory (brief §Cache contract).
func updateCacheURL() -> URL {
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        .first!
        .appendingPathComponent("AgentLens", isDirectory: true)
        .appendingPathComponent("update-metadata-v1.json")
}

switch args.count >= 2 ? args[1] : nil {
case "scan":
    guard let mode = ScanMode.parse(Array(args.dropFirst(2))) else {
        usageError()
    }
    // M4: data-driven registry (D-010, D-017, D-018). Discovery and execution
    // environment come ONLY from the M2-resolved login shell — never inherited (D-005).
    let environment = ShellEnvironmentResolver.resolve()
    do {
        let definitions = try DetectorRegistry.loadDefault()
        let reports = definitions.map { definition in
            PathDiagnosticsScanner.scan(
                detector: definition.makeDetector(),
                environment: environment
            )
        }
        // Update results are associated by the registry's stable ID, carried beside the diagnostic
        // — never by display name and never by the executable basename.
        let subjects = zip(definitions, reports).map { definition, report in
            UpdateProbeSubject(
                registryID: definition.id,
                displayName: definition.displayName,
                diagnostic: report
            )
        }
        // The local inventory is published first and flushed, before any manager query.
        print(DiagnosticsScanRenderer.render(reports: reports, isDegraded: environment.isDegraded), terminator: "")
        // Declared metadata comes from the same validated definitions, in the same
        // order, and is appended before VERSION / UPDATE STATUS in every scan mode.
        print(DetectorMetadataRenderer.render(definitions: definitions), terminator: "")
        fflush(stdout)

        // Update status is appended after the M5 report; probe outcomes are values, not errors.
        // top-level code is async: the probe runs off the main executor via the bridge.
        Task {
            let results = await UpdateProbeCoordinator.run(
                subjects: subjects,
                environment: environment,
                mode: mode.probeMode,
                runner: ProcessUpdateCommandRunner(),
                cacheURL: updateCacheURL(),
                now: { Date() }
            )
            print(UpdateScanRenderer.render(results: results, mode: mode.probeMode), terminator: "")
            fflush(stdout)
            exit(0)
        }
        dispatchMain()
    } catch {
        // Fail loud: a broken registry is an operator-visible error, never a
        // silently reduced scan (M4 brief req. 3).
        FileHandle.standardError.write(Data("\(error)\n".utf8))
        exit(1)
    }
case "verify-installation":
    // Explicit, read-only ownership verification for exactly one registry entry.
    // Invalid syntax is rejected before any environment capture, scan or manager query.
    guard args.count == 3 else { usageError() }
    let registryID = args[2]
    let environment = ShellEnvironmentResolver.resolve()
    do {
        let definitions = try DetectorRegistry.loadDefault()
        guard let definition = definitions.first(where: { $0.id == registryID }) else {
            FileHandle.standardError.write(
                Data("agent-lens: unknown registry id '\(registryID)'\n".utf8)
            )
            exit(1)
        }
        let report = PathDiagnosticsScanner.scan(
            detector: definition.makeDetector(),
            environment: environment
        )
        // Local, path and declared facts come from the same validated definition as the
        // ownership result. No update coordinator, cache, manager batch or version lookup runs.
        print(
            DiagnosticsScanRenderer.render(reports: [report], isDegraded: environment.isDegraded),
            terminator: ""
        )
        print(DetectorMetadataRenderer.render(definitions: [definition]), terminator: "")
        fflush(stdout)

        Task {
            let result = await InstallationOwnershipVerifier.verify(
                definition: definition,
                diagnostic: report,
                environment: environment,
                runner: ProcessUpdateCommandRunner(),
                currentDirectory: FileManager.default.currentDirectoryPath,
                now: { Date() }
            )
            print(InstallationOwnershipRenderer.render(result), terminator: "")
            fflush(stdout)
            // Unknown is a diagnostic result, not a command failure.
            exit(0)
        }
        dispatchMain()
    } catch {
        FileHandle.standardError.write(Data("\(error)\n".utf8))
        exit(1)
    }
case "debug-env":
    // M2: prints the login-shell environment that all later discovery will use.
    // The PATH here has already been resolved from the login shell — reading
    // ProcessInfo's PATH is forbidden for discovery (D-005).
    guard args.count == 2 else { usageError() }
    print(ShellEnvironmentResolver.renderDebugEnvironment(ShellEnvironmentResolver.resolve()))
    exit(0)
case nil:
    // No argument: usage only, but a clean exit (brief requirement).
    printUsage()
    exit(0)
default:
    // Unknown command: usage on stderr, exit non-zero. This is what proves
    // the dispatch is real and not a hardcoded print.
    usageError()
}
