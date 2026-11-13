// ConflictSummaryView — M12-C conflict summary (R3/R14).
//
// One row per conflict TOOL, built from A's frozen `ToolConflict(entry:)`. The row reports the
// classified kinds in the ruled order, the canonical-target copy count, and the measured local
// versions A observed. Versions are a flat list on purpose: A exposes no per-copy attribution, so
// this view never invents one. Aliases and repeated PATH slots are Diagnostics summary facts, not
// conflicts, and appear neither here nor in the count.
//
// "Show PATH evidence" only asks the parent to run `InventoryViewModel.showPathEvidence`; the
// existing DiagnosticsView is the sole per-candidate surface, so nothing is duplicated here.

import SwiftUI
import AgentLensAppSupport

public struct ConflictSummaryView: View {
    let conflicts: [ToolConflict]
    let onShowPathEvidence: (String) -> Void

    public init(
        conflicts: [ToolConflict],
        onShowPathEvidence: @escaping (String) -> Void
    ) {
        self.conflicts = conflicts
        self.onShowPathEvidence = onShowPathEvidence
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Conflicts")
                    .font(.headline)
                Text("\(conflicts.count)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            if conflicts.isEmpty {
                Text("No conflicts detected across the known tools.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(conflicts.enumerated()), id: \.element.registryID) { index, conflict in
                        if index > 0 {
                            Divider()
                                .padding(.vertical, 10)
                        }
                        conflictRow(conflict)
                    }
                }
            }
        }
    }

    private func conflictRow(_ conflict: ToolConflict) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(conflict.displayName)
                        .font(.body)
                        .fontWeight(.medium)
                    Text(conflict.registryID)
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Show PATH evidence") {
                    onShowPathEvidence(conflict.registryID)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Show PATH evidence for \(conflict.displayName)")
            }

            conflictFacts(conflict)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityLabel(for: conflict))
        }
    }

    private func conflictFacts(_ conflict: ToolConflict) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(kindLabels(for: conflict).joined(separator: " · "))
                .fontWeight(.medium)
            Text("Copy count: \(conflict.copyCount)")
            Text("Measured local versions: \(versionsText(for: conflict))")
            if let winnerEntryPath = conflict.winnerEntryPath {
                Text("Winner entry: \(winnerEntryPath)")
            }
            if let offPathRoot = conflict.offPathRoot {
                Text("Off-PATH root: \(offPathRoot)")
            }
            if let inconsistencyReason = conflict.inconsistencyReason {
                Text("Reason: \(inconsistencyReason)")
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// A's flat measured list; `—` means no local measurement was observed.
    private func versionsText(for conflict: ToolConflict) -> String {
        conflict.localVersions.isEmpty ? "—" : conflict.localVersions.joined(separator: ", ")
    }

    /// The kind order is A's ruled order; the labels are this App's plain-language presentation.
    private func kindLabels(for conflict: ToolConflict) -> [String] {
        conflict.kinds.map { kind in
            switch kind {
            case .shadowedCopy:
                "Shadowed copy"
            case .offPathCopy:
                "Off PATH"
            case .inconsistentDiagnostics:
                "Inconsistent diagnostics"
            }
        }
    }

    /// One combined label for the row's facts; the button keeps its own accessible action.
    private func accessibilityLabel(for conflict: ToolConflict) -> String {
        let kinds = kindLabels(for: conflict).joined(separator: ", ")
        return "\(conflict.displayName), conflict: \(kinds), copy count \(conflict.copyCount)"
    }
}
