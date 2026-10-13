// agent-lens — the CLI executable (D-016: the MVP ships as a command-line tool).
//
// M3: `scan` performs real detection (ToolDetector + ShellEnvironment); the
// argument-ordered dispatch from M1 is unchanged. Argument index 1 is the
// subcommand (index 0 is the program name).

import AgentLensCore
import Foundation

let args = CommandLine.arguments

func printUsage() {
    print(WalkingSkeleton.usageMessage)
}

switch args.count == 2 ? args[1] : nil {
case "scan":
    // M4: data-driven registry (D-010, D-017, D-018). Discovery and execution
    // environment come ONLY from the M2-resolved login shell — never inherited (D-005).
    let environment = ShellEnvironmentResolver.resolve()
    do {
        let definitions = try DetectorRegistry.loadDefault()
        let tools = definitions.map { $0.makeDetector().detect(in: environment) }
        print(ScanRenderer.render(tools: tools))
        exit(0)
    } catch {
        // Fail loud: a broken registry is an operator-visible error, never a
        // silently reduced scan (M4 brief req. 3).
        FileHandle.standardError.write(Data("\(error)\n".utf8))
        exit(1)
    }
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
