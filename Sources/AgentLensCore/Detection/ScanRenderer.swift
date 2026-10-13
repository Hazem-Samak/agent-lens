// ScanRenderer — renders real detection results in the report shape first
// established at M1 and extended by the M3 brief.

import Foundation

/// Renders scan output. Marker by state:
///   installedAndOnPath -> "✓"
///   installedNotOnPath -> "!" + " (not on PATH)" appended
///   notInstalled       -> "–" plus dashes for version and source columns
/// Unknown version renders as "–" (D-007), never an error, never fabricated.
public enum ScanRenderer {

    public static func render(tools: [DetectedTool]) -> String {
        var lines: [String] = []
        lines.append("AI AGENTS                         \(tools.count)")
        lines.append("")
        for tool in tools {
            lines.append(row(for: tool))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func row(for tool: DetectedTool) -> String {
        switch tool.state {
        case .installedAndOnPath:
            return "✓ \(tool.displayName)          \(tool.version ?? "–")    \(tool.source)"
        case .installedNotOnPath:
            return "! \(tool.displayName)          \(tool.version ?? "–")    \(tool.source) (not on PATH)"
        case .notInstalled:
            return "– \(tool.displayName)          –    –"
        }
    }
}

/// The single M3 fixture detector (hardcoded by design — the data-driven
/// detector registry arrives at M4, O-003). Verified against this machine's
/// real install while drafting the brief.
public enum CoreDetectors {
    public static let codex = ToolDetector(
        displayName: "Codex",
        executableName: "codex",
        extraSearchRoots: ["~/.local/bin"]
    )
}
