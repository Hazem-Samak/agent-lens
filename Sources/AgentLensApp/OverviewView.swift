// OverviewView — M12-B summary destination (R14).
//
// Overview is a SUMMARY, never a second inventory: summary tiles derived from the published
// snapshot plus the degraded-environment banner. There is deliberately no all-tools table here —
// the three category destinations partition the catalogue, so a second full list could disagree
// with them.
//
// A non-empty search replaces the tiles with matches across every category (scope `.all`, registry
// order). Choosing a match navigates into that tool's category scope and selects its registry ID;
// those two writes are the ViewModel's own R1 triggers, so a pending confirmation is released.
//
// The conflict summary section is M12-C. Its placement is marked below; nothing is built here.

import SwiftUI
import AgentLensAppSupport
import AgentLensCore

public struct OverviewView: View {
    @Bindable var model: InventoryViewModel
    private let onRescan: (@MainActor () -> Void)?
    private let onSelectMatch: (InventoryEntry) -> Void
    private let onShowPathEvidence: (String) -> Void

    public init(
        model: InventoryViewModel,
        onRescan: (@MainActor () -> Void)? = nil,
        onSelectMatch: @escaping (InventoryEntry) -> Void,
        onShowPathEvidence: @escaping (String) -> Void
    ) {
        self.model = model
        self.onRescan = onRescan
        self.onSelectMatch = onSelectMatch
        self.onShowPathEvidence = onShowPathEvidence
    }

    public var body: some View {
        Group {
            if model.entries.isEmpty {
                InventoryEmptyStateView(model: model, onRescan: onRescan)
            } else if isSearching {
                matchResults
            } else {
                summary
            }
        }
        .navigationTitle("Overview")
        .searchable(
            text: $model.searchText,
            placement: .toolbar,
            prompt: "Search name, executable, or path"
        )
    }

    private var isSearching: Bool {
        !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Summary

    private var summary: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if model.isDegradedEnvironment {
                    degradedEnvironmentBanner
                }

                summaryTiles

                ConflictSummaryView(
                    conflicts: model.entries.compactMap { ToolConflict(entry: $0) },
                    onShowPathEvidence: onShowPathEvidence
                )
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var summaryTiles: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: 12)],
            alignment: .leading,
            spacing: 12
        ) {
            tile("Known tools", count: model.knownToolCount)
            tile("Installed", count: model.installedToolCount)
            tile("Off PATH", count: model.snapshot?.offPathToolCount ?? 0)
            tile("Update available", count: model.updateAvailableCount)
            tile("Conflict tools", count: model.snapshot?.conflictToolCount ?? 0)
        }
    }

    private func tile(_ label: String, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(count)")
                .font(.title2)
                .fontWeight(.semibold)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(count)")
    }

    private var degradedEnvironmentBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.body)
            VStack(alignment: .leading, spacing: 2) {
                Text("Degraded Environment")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("The login shell could not be captured; PATH uses the documented fallback PATH. Results may not represent the login shell's authoritative PATH.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Match results

    @ViewBuilder
    private var matchResults: some View {
        if model.filteredEntries.isEmpty {
            ContentUnavailableView.search(text: model.searchText)
        } else {
            List(model.filteredEntries, id: \.registryID) { entry in
                Button {
                    onSelectMatch(entry)
                } label: {
                    ToolRow(entry: entry)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.inset)
        }
    }
}
