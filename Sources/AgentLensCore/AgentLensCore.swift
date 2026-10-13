// AgentLensCore — hardcoded walking-skeleton report (M1 brief).
//
// M1 rules: NO filesystem scanning, NO Process usage, NO network, NO detectors,
// NO code that looks at the real machine. Every value below is a literal.

/// One detected AI CLI tool. Installation source is the package manager
/// (or "standalone" later); see D-004 for why we never reimplement the manager.
public struct ToolReport: Equatable, Sendable {
    public let name: String
    public let version: String
    public let source: String

    public init(name: String, version: String, source: String) {
        self.name = name
        self.version = version
        self.source = source
    }
}

/// The single hardcoded fixture of M1. It will be replaced by real detection
/// starting in M2 (environment resolution) and M3 (first real detector).
public enum WalkingSkeleton {
    public static let tools: [ToolReport] = [
        ToolReport(name: "Codex", version: "0.154.0", source: "npm")
    ]

    /// Renders the scan report given the reports to include.
    /// Kept pure and testable — from M2 on, the tests stop being circular (D-012).
    public static func renderScanReport(tools: [ToolReport]) -> String {
        guard !tools.isEmpty else {
            return "AI AGENTS                         0\n\n(none found)\n"
        }
        var lines: [String] = []
        lines.append("AI AGENTS                         \(tools.count)")
        lines.append("")
        for tool in tools {
            lines.append("✓ \(tool.name)          \(tool.version)    \(tool.source)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// One-line usage message, shown for the no-argument and unknown-command cases.
    public static let usageMessage = "usage: agent-lens <scan>"
}
