import Foundation

public enum DiagnosticsScanRenderer {
    public static func render(reports: [ToolPathDiagnostic], isDegraded: Bool) -> String {
        var lines = [ScanRenderer.render(tools: reports.map(\.detectedTool))
            .trimmingCharacters(in: .newlines)]
        if isDegraded {
            lines.append("")
            lines.append(
                "WARNING: The login shell could not be captured; PATH uses the documented fallback PATH."
            )
            lines.append("Results may not represent the login shell's authoritative PATH.")
        }

        lines.append("")
        lines.append("PATH DIAGNOSTICS")
        for report in reports {
            lines.append("")
            lines.append("\(report.detectedTool.displayName)")
            lines.append(
                "  live entry paths: \(report.distinctLiveEntryPathCount); canonical targets: \(report.canonicalTargetCount)"
            )
            let shadowed = report.shadowedInstallationCount.map(String.init) ?? "unavailable (consistency failure)"
            lines.append(
                "  repeated PATH slots: \(report.repeatedPathSlotCount); same-target aliases: \(report.sameTargetAliasCount); shadowed installations: \(shadowed)"
            )

            switch report.selection {
            case .winner(let winner):
                lines.append(
                    "  verified winner: \(winner.entryPath) -> \(winner.canonicalTarget ?? "unknown target") (PATH slot \(pathSlotNumber(winner)); matches detector)"
                )
            case .offPath(let candidate, let root):
                lines.append("  known extra root (off PATH; not a shell winner): \(root)")
                lines.append(
                    "  found: \(candidate.entryPath) -> \(candidate.canonicalTarget ?? "unknown target")"
                )
            case .notInstalled:
                lines.append("  selection: no live executable in PATH or declared extra roots")
            case .inconsistent(let reason):
                lines.append("  winner unavailable: consistency failure — \(reason)")
            }

            appendLiveEntries(for: report, to: &lines)
            if !report.invalidCandidates.isEmpty {
                lines.append("  invalid observed PATH entries:")
                for candidate in report.invalidCandidates {
                    lines.append(
                        "    slot \(pathSlotNumber(candidate)) (PATH entry \(quotedPathEntry(candidate))): \(candidate.entryPath) — \(candidate.kind.label)"
                    )
                }
            } else if report.pathCandidates.isEmpty && report.liveCandidates.isEmpty {
                lines.append("  PATH candidates: none observed")
            }
        }

        lines.append("")
        lines.append(
            "Count definitions: repeated PATH slots are extra occurrences of an observed normalized entry path; same-target aliases are distinct live entry paths beyond the first for one canonical target; shadowed installations are distinct live canonical targets outside the verified winner's target group."
        )
        return lines.joined(separator: "\n") + "\n"
    }

    private static func appendLiveEntries(for report: ToolPathDiagnostic, to lines: inout [String]) {
        var seenEntryPaths = Set<String>()
        let entries = report.liveCandidates.filter { seenEntryPaths.insert($0.entryPath).inserted }
        guard !entries.isEmpty else { return }

        lines.append("  live PATH entries:")
        let winner: PathCandidateObservation?
        if case .winner(let selected) = report.selection {
            winner = selected
        } else {
            winner = nil
        }
        for candidate in entries {
            let observations = report.liveCandidates.filter { $0.entryPath == candidate.entryPath }
            let slots = observations.map { pathSlotNumber($0) }
            let slotText = slots.count > 1
                ? "slots \(slots.map(String.init).joined(separator: ", "))"
                : "slot \(slots[0])"
            let target = candidate.canonicalTarget ?? "unknown target"
            let note: String
            if let winner, candidate.entryPath == winner.entryPath {
                note = "verified winner"
            } else if let winner,
                      candidate.canonicalTarget == winner.canonicalTarget {
                note = "same-target alias of \(winner.entryPath)"
            } else if winner != nil {
                note = "shadowed because it appears later in PATH"
            } else {
                note = "live candidate; no winner claimed"
            }
            lines.append(
                "    \(slotText) (PATH entry \(quotedPathEntry(candidate))): \(candidate.entryPath) -> \(target) — \(note)"
            )
        }
    }

    private static func pathSlotNumber(_ candidate: PathCandidateObservation) -> Int {
        switch candidate.origin {
        case .path(let slotIndex, _): slotIndex + 1
        case .extraRoot(let index, _): index + 1
        }
    }

    private static func quotedPathEntry(_ candidate: PathCandidateObservation) -> String {
        switch candidate.origin {
        case .path(_, let directoryText), .extraRoot(_, let directoryText):
            "\"\(directoryText)\""
        }
    }
}
