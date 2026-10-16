import SwiftUI
import AgentLensAppSupport
import AgentLensCore

public struct ToolListView: View {
    @Bindable var model: InventoryViewModel
    private let onRescan: (@MainActor () -> Void)?

    public init(model: InventoryViewModel, onRescan: (@MainActor () -> Void)? = nil) {
        self.model = model
        self.onRescan = onRescan
    }

    public var body: some View {
        Group {
            if model.entries.isEmpty {
                emptyInventoryView
            } else if model.filteredEntries.isEmpty {
                ContentUnavailableView.search(text: model.searchText)
            } else {
                toolList
            }
        }
        .navigationTitle("Tools")
        .searchable(
            text: $model.searchText,
            placement: .toolbar,
            prompt: "Search name, executable, or path"
        )
    }

    private var toolList: some View {
        List(
            model.filteredEntries,
            id: \.registryID,
            selection: Binding<String?>(
                get: { model.selectedRegistryID },
                set: { model.select(registryID: $0) }
            )
        ) { entry in
            ToolRow(entry: entry)
                .tag(entry.registryID)
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private var emptyInventoryView: some View {
        switch model.phase {
        case .loadingLocal:
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)
                Text("Scanning local tools…")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            ContentUnavailableView {
                Label("Scan Failed", systemImage: "exclamationmark.triangle")
            } description: {
                Text(model.freshnessFailure?.message ?? "An error occurred while scanning local tools.")
            } actions: {
                Button("Rescan") {
                    onRescan?()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy)
            }
        case .idle, .localReady, .checkingUpdates, .ready:
            ContentUnavailableView(
                "No Tools Defined",
                systemImage: "wrench.and.screwdriver",
                description: Text("The detector registry contains no tool definitions.")
            )
        }
    }
}

private struct ToolRow: View {
    let entry: InventoryEntry

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.definition.displayName)
                    .font(.body)
                    .fontWeight(.medium)
                Text(entry.definition.executableName)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundColor(.secondary)
            }

            Spacer()

            installBadge

            if case .updateAvailable = entry.updateStatus {
                updateBadge
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    @ViewBuilder
    private var installBadge: some View {
        switch entry.installState {
        case .installedAndOnPath:
            Text("On PATH")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12), in: Capsule())
                .foregroundColor(.primary)
        case .installedNotOnPath:
            Text("Off PATH")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.15), in: Capsule())
                .foregroundColor(.orange)
        case .notInstalled:
            Text("Not installed")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var updateBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.caption2)
            Text("Update")
                .font(.caption2)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.accentColor.opacity(0.15), in: Capsule())
        .foregroundColor(.accentColor)
    }

    private var accessibilityDescription: String {
        var parts: [String] = [
            entry.definition.displayName,
            entry.definition.executableName,
        ]
        switch entry.installState {
        case .installedAndOnPath:
            parts.append("Installed and on PATH")
        case .installedNotOnPath:
            parts.append("Installed off PATH")
        case .notInstalled:
            parts.append("Not installed")
        }
        if case .updateAvailable = entry.updateStatus {
            parts.append("Update available")
        }
        return parts.joined(separator: ", ")
    }
}
