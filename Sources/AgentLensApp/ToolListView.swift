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
                InventoryEmptyStateView(model: model, onRescan: onRescan)
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
            ToolRow(entry: entry, showsUpdateCell: model.listScope == .updates)
                .tag(entry.registryID)
        }
        .listStyle(.inset)
    }
}

/// The shared "no inventory facts yet" presentation: the same copy is used by the list
/// destinations and by Overview, so loading, failure, and the empty registry read identically.
struct InventoryEmptyStateView: View {
    let model: InventoryViewModel
    let onRescan: (@MainActor () -> Void)?

    var body: some View {
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
        case .idle, .localReady, .checkingUpdates, .verifyingOwnership, .ready:
            ContentUnavailableView(
                "No Tools Defined",
                systemImage: "wrench.and.screwdriver",
                description: Text("The detector registry contains no tool definitions.")
            )
        }
    }
}

struct ToolRow: View {
    let entry: InventoryEntry
    /// Shows the Updates destination's tri-state cell for every non-`updateAvailable` status.
    var showsUpdateCell: Bool = false

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
                Text(localVersionText)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundColor(.secondary)
                Text(sourceText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                declaredPackageRows
            }

            Spacer()

            installBadge

            updateStatusCell
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    /// The local version fact exactly as published; `—` when no local measurement exists.
    private var localVersionText: String {
        entry.diagnostic.detectedTool.version ?? "—"
    }

    /// The source heuristic as a labeled fact, never a verdict. A tool that is not installed has no
    /// source observation to report. `—` means "not observed", never "standalone".
    private var sourceText: String {
        guard entry.installState != .notInstalled else { return "—" }
        let source = entry.diagnostic.detectedTool.source
        return source.isEmpty ? "—" : "Source: \(source)"
    }

    private var declaredPackageRows: some View {
        ForEach(Array(entry.definition.packages.enumerated()), id: \.offset) { _, package in
            Text(packageText(package))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func packageText(_ package: DeclaredPackage) -> String {
        "\(package.manager.label): \(package.name)"
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

    /// `updateAvailable` keeps its badge everywhere; the Updates destination additionally shows a
    /// neutral tri-state cell so up-to-date, unknown, and not-checked are distinguishable without
    /// ever reading as "current" or "update available".
    @ViewBuilder
    private var updateStatusCell: some View {
        if case .updateAvailable = entry.updateStatus {
            updateBadge
        } else if showsUpdateCell {
            Text(neutralUpdateText)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var neutralUpdateText: String {
        switch entry.updateStatus {
        case .upToDate?:
            "Up to date"
        case .unknown?:
            "Unknown"
        case .updateAvailable?:
            "Update available"
        case nil:
            "Not checked"
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
        parts.append(entry.definition.category.label)
        if let version = entry.diagnostic.detectedTool.version {
            parts.append("version \(version)")
        } else {
            parts.append("version unknown")
        }
        let conflicts = conflictLabels
        if !conflicts.isEmpty {
            parts.append("conflict: " + conflicts.joined(separator: ", "))
        }
        if case .updateAvailable = entry.updateStatus {
            parts.append("Update available")
        }
        return parts.joined(separator: ", ")
    }

    private var conflictLabels: [String] {
        guard let conflict = ToolConflict(entry: entry) else { return [] }
        return conflict.kinds.map { kind in
            switch kind {
            case .shadowedCopy:
                "shadowed copy"
            case .offPathCopy:
                "off PATH copy"
            case .inconsistentDiagnostics:
                "inconsistent diagnostics"
            }
        }
    }
}
