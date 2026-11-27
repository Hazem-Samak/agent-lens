// InstallationOwnershipRenderer — the CLI OWNERSHIP VERIFICATION section (M9-B).
//
// Pure rendering of one typed result. It never re-derives ownership from paths or labels, and the
// read-only notice is part of every result so a verified observation cannot be mistaken for
// permission to modify an installation.

import Foundation

public enum InstallationOwnershipRenderer {

    public static func render(_ result: InstallationOwnershipResult) -> String {
        var lines: [String] = []
        lines.append("")
        lines.append("OWNERSHIP VERIFICATION")
        lines.append("  registry id: \(result.registryID)")

        switch result.outcome {
        case .verified(let installation):
            lines.append("  result: verified")
            lines.append("  manager: \(installation.manager.label)")
            lines.append("  package: \(installation.packageName)")
            lines.append("  manager executable: \(installation.managerEntryPath)")
            lines.append("  manager target: \(installation.managerTarget)")
            lines.append("  manager root: \(installation.managerRoot)")
            lines.append("  installation root: \(installation.installationRoot)")
            lines.append("  selected entry: \(installation.selection.entryPath)")
            lines.append("  selected target: \(installation.selection.canonicalTarget)")
            if let python = installation.pythonEnvironment {
                lines.append("  environment root: \(installation.installationRoot)")
                lines.append("  environment type: \(python.environmentKind.label)")
                lines.append("  installed version: \(python.installedVersion)")
                lines.append("  python interpreter: \(python.interpreterVersion ?? "unknown")")
                if let requires = python.requiresPython {
                    lines.append("  requires-python: \(requires)")
                }
                lines.append("  installer: \(python.installer)")
                lines.append("  index provenance: \(python.indexProvenance.label)")
                if !python.receiptConstraints.isEmpty {
                    lines.append("  receipt constraints: \(python.receiptConstraints.joined(separator: ", "))")
                }
                if !python.extras.isEmpty {
                    lines.append("  additional requirements: \(python.extras.joined(separator: ", "))")
                }
                lines.append("  guidance: \(python.environmentKind.guidance)")
            }
        case .unknown(let reason):
            lines.append("  result: unknown")
            lines.append("  reason: \(reason.message)")
            if let entry = result.observedSelectedEntry {
                lines.append("  selected entry: \(entry)")
            }
            if let target = result.observedSelectedTarget {
                lines.append("  selected target: \(target)")
            }
        }

        lines.append("  observed at: \(timestamp(result.observedAt))")
        lines.append(
            "  note: read-only verification from this invocation; no installation changes were made"
        )
        return lines.joined(separator: "\n") + "\n"
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}
