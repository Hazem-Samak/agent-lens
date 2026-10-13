// agent-lens — the CLI executable (D-016: the MVP ships as a command-line tool).
//
// M1: argument-ordered dispatch and a hardcoded report. Argument index 1 is the
// subcommand (index 0 is the program name).

import AgentLensCore
import Foundation

let args = CommandLine.arguments

func printUsage() {
    print(WalkingSkeleton.usageMessage)
}

switch args.count == 2 ? args[1] : nil {
case "scan":
    print(WalkingSkeleton.renderScanReport(tools: WalkingSkeleton.tools))
    exit(0)
case "debug-env":
    // M2: prints the login-shell environment that all later discovery will use.
    // The PATH here has already been resolved from the login shell — reading
    // ProcessInfo's PATH is forbidden for discovery (D-005).
    print(ShellEnvironmentResolver.renderDebugEnvironment(ShellEnvironmentResolver.resolve()))
    exit(0)
case nil:
    // No argument: usage only, but a clean exit (brief requirement).
    printUsage()
    exit(0)
default:
    // Unknown command: usage on stderr, exit non-zero. This is what proves
    // the dispatch is real and not a hardcoded print.
    FileHandle.standardError.write(Data((WalkingSkeleton.usageMessage + "\n").utf8))
    exit(1)
}
