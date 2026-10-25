import SwiftUI
import AgentLensAppSupport
import AgentLensCore

public enum NavigationDestination: String, CaseIterable, Identifiable, Hashable {
    case inventory = "Inventory"
    case diagnostics = "Diagnostics"

    public var id: String { rawValue }
}

public struct MainWindow: View {
    private var _model: State<InventoryViewModel>
    private var model: InventoryViewModel {
        get { _model.wrappedValue }
        nonmutating set { _model.wrappedValue = newValue }
    }

    private var _selectedDestination: State<NavigationDestination?> = State(initialValue: .inventory)
    private var selectedDestination: NavigationDestination? {
        get { _selectedDestination.wrappedValue }
        nonmutating set { _selectedDestination.wrappedValue = newValue }
    }

    private var _activeActionTask: State<Task<Void, Never>?> = State(initialValue: nil)
    private var activeActionTask: Task<Void, Never>? {
        get { _activeActionTask.wrappedValue }
        nonmutating set { _activeActionTask.wrappedValue = newValue }
    }

    public init(service: InventoryService = Self.makeDefaultService()) {
        self._model = State(initialValue: InventoryViewModel(service: service))
        self._selectedDestination = State(initialValue: .inventory)
        self._activeActionTask = State(initialValue: nil)
    }

    public static func makeDefaultService() -> InventoryService {
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("AgentLens", isDirectory: true)
            .appendingPathComponent("update-metadata-v1.json")
        let environmentProvider = SessionEnvironmentProvider(source: .live)
        return InventoryService(
            environment: environmentProvider,
            updateCacheURL: cacheURL
        )
    }

    public var body: some View {
        NavigationSplitView {
            sidebarView
        } content: {
            ToolListView(model: model, onRescan: {
                runAction {
                    await model.rescan()
                }
            })
        } detail: {
            detailView
        }
        .toolbar {
            toolbarItems
        }
        .task {
            await model.launch()
        }
        .onDisappear {
            cancelActiveAction()
        }
    }

    // MARK: - Action lifetime management

    private func runAction(_ perform: @escaping @MainActor () async -> Void) {
        guard activeActionTask == nil, !model.isBusy else { return }
        let task = Task { @MainActor in
            defer {
                activeActionTask = nil
            }
            guard !Task.isCancelled else { return }
            await perform()
        }
        activeActionTask = task
    }

    private func cancelCurrentAction() {
        guard model.isBusy || activeActionTask != nil else { return }
        if model.phase == .verifyingOwnership {
            // Verification reports `Cancelling` immediately through the model, then lets the
            // owned cleanup finish; do not bypass that state by only cancelling the action task.
            Task { @MainActor in
                await model.cancel()
            }
        } else if let task = activeActionTask {
            task.cancel()
            Task { @MainActor in
                await task.value
            }
        } else {
            Task { @MainActor in
                await model.cancel()
            }
        }
    }

    private func cancelActiveAction() {
        activeActionTask?.cancel()
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        List(NavigationDestination.allCases, selection: _selectedDestination.projectedValue) { destination in
            NavigationLink(value: destination) {
                Label {
                    HStack {
                        Text(destination.rawValue)
                        Spacer()
                        if destination == .inventory {
                            Text("\(model.installedToolCount)/\(model.knownToolCount)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: destinationIcon(destination))
                }
            }
        }
        .navigationTitle("Agent Lens")
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            if model.isDegradedEnvironment {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Degraded PATH fallback")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func destinationIcon(_ destination: NavigationDestination) -> String {
        switch destination {
        case .inventory:
            "shippingbox"
        case .diagnostics:
            "stethoscope"
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailView: some View {
        switch selectedDestination {
        case .inventory, .none:
            ToolDetailView(
                entry: model.selectedEntry,
                isDegradedEnvironment: model.isDegradedEnvironment,
                freshnessFailure: model.freshnessFailure,
                updateFailure: model.updateFailure,
                isVerifyingOwnership: model.phase == .verifyingOwnership,
                isCancellingOwnership: model.isCancelling,
                isBusy: model.isBusy,
                onVerifyOwnership: {
                    runAction {
                        await model.verifySelectedInstallation()
                    }
                },
                onCancelOwnership: {
                    cancelCurrentAction()
                }
            )
        case .diagnostics:
            DiagnosticsView(
                entry: model.selectedEntry,
                isDegradedEnvironment: model.isDegradedEnvironment,
                freshnessFailure: model.freshnessFailure
            )
        }
    }

    // MARK: - Toolbar

    private var busyLabel: String {
        switch model.phase {
        case .verifyingOwnership:
            model.isCancelling ? "Cancelling…" : "Verifying…"
        case .loadingLocal:
            "Scanning…"
        case .idle, .localReady, .checkingUpdates, .ready, .failed:
            "Checking…"
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 6) {
                Text("\(model.knownToolCount) known, \(model.installedToolCount) installed")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if model.updateAvailableCount > 0 {
                    Text("• \(model.updateAvailableCount) update available")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            if model.isBusy {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(busyLabel)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Cancel") {
                        cancelCurrentAction()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .disabled(model.isCancelling)
                }
            }

            Button {
                runAction {
                    await model.rescan()
                }
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .disabled(model.isBusy)
            .help("Rescan login-shell environment and local tools")

            Button {
                runAction {
                    await model.checkForUpdates()
                }
            } label: {
                Label("Check Updates", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(model.isBusy)
            .help("Check for updates using cached metadata when valid")

            Button {
                runAction {
                    await model.refreshUpdates()
                }
            } label: {
                Label("Refresh Updates", systemImage: "arrow.clockwise.circle")
            }
            .disabled(model.isBusy)
            .help("Bypass cache and refresh update metadata")
        }
    }
}
