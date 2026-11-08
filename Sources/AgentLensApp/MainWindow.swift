import AppKit
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

    private var _lifecycleToken: State<UUID?> = State(initialValue: nil)

    public init(service: InventoryService = Self.makeDefaultService()) {
        self._model = State(initialValue: InventoryViewModel(service: service))
        self._selectedDestination = State(initialValue: .inventory)
        self._activeActionTask = State(initialValue: nil)
        self._lifecycleToken = State(initialValue: nil)
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
        .onAppear {
            if _lifecycleToken.wrappedValue == nil {
                _lifecycleToken.wrappedValue = AppLifecycleGate.shared.register(
                    shouldWait: {
                        model.isBusy || activeActionTask != nil
                            || model.isUpdateSheetPresented || model.isUninstallSheetPresented
                    },
                    cancelAndJoin: {
                        cancelActiveAction()
                        await model.cancel()
                        await model.cancelUpdate()
                        await model.cancelUninstall()
                    }
                )
            }
        }
        .task {
            await model.launch()
        }
        .sheet(isPresented: updateSheetBinding, onDismiss: {
            model.dismissUpdate()
        }) {
            UpdateOperationView(
                preview: model.updatePreview ?? model.updatePreparation?.preview,
                outcome: model.updateOutcome,
                unavailable: model.updateUnavailableReason,
                isExecuting: model.isExecutingUpdate,
                isCancelling: model.isCancelling,
                onConfirm: {
                    runAction {
                        await model.confirmSelectedUpdate()
                    }
                },
                onCancel: {
                    Task { @MainActor in
                        await model.cancelUpdate()
                    }
                },
                onDismiss: {
                    model.dismissUpdate()
                }
            )
            .interactiveDismissDisabled(model.isExecutingUpdate)
        }
        .sheet(isPresented: uninstallSheetBinding, onDismiss: {
            model.dismissUninstall()
        }) {
            UninstallOperationView(
                preview: model.uninstallPreview ?? model.uninstallPreparation?.preview,
                outcome: model.uninstallOutcome,
                unavailable: model.uninstallUnavailableReason,
                isExecuting: model.isExecutingUninstall,
                isCancelling: model.isCancelling,
                onConfirm: {
                    runAction {
                        await model.confirmSelectedUninstall()
                    }
                },
                onCancel: {
                    Task { @MainActor in
                        await model.cancelUninstall()
                    }
                },
                onDismiss: {
                    model.dismissUninstall()
                }
            )
            .interactiveDismissDisabled(model.isExecutingUninstall)
        }
        .background(WindowCloseObserver(onClose: {
            cancelActiveAction()
            await model.cancelUpdate()
            await model.cancelUninstall()
        }))
        .onDisappear {
            cancelActiveAction()
            Task { @MainActor in
                await model.cancelUpdate()
                await model.cancelUninstall()
            }
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
        if model.phase == .verifyingOwnership || model.isPreparingUpdate || model.isExecutingUpdate
            || model.isPreparingUninstall || model.isExecutingUninstall {
            // These actions report `Cancelling` immediately through the model, then let owned
            // bounded cleanup finish; do not bypass that state by only cancelling the action task.
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
                isPreparingUpdate: model.isPreparingUpdate,
                isExecutingUpdate: model.isExecutingUpdate,
                isPreparingUninstall: model.isPreparingUninstall,
                isExecutingUninstall: model.isExecutingUninstall,
                isBusy: model.isBusy,
                onVerifyOwnership: {
                    runAction {
                        await model.verifySelectedInstallation()
                    }
                },
                onCancelOwnership: {
                    cancelCurrentAction()
                },
                onPrepareUpdate: {
                    runAction {
                        await model.prepareSelectedUpdate()
                    }
                },
                onPrepareUninstall: {
                    runAction {
                        await model.prepareSelectedUninstall()
                    }
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

    private var updateSheetBinding: Binding<Bool> {
        Binding(
            get: { model.isUpdateSheetPresented },
            set: { presented in
                if !presented { model.dismissUpdate() }
            }
        )
    }

    private var uninstallSheetBinding: Binding<Bool> {
        Binding(
            get: { model.isUninstallSheetPresented },
            set: { presented in
                if !presented { model.dismissUninstall() }
            }
        )
    }

    // MARK: - Toolbar

    private var busyLabel: String {
        if model.isPreparingUpdate { return model.isCancelling ? "Cancelling…" : "Preparing Update…" }
        if model.isExecutingUpdate { return model.isCancelling ? "Cancelling…" : "Updating…" }
        if model.isPreparingUninstall { return model.isCancelling ? "Cancelling…" : "Preparing Uninstall…" }
        if model.isExecutingUninstall { return model.isCancelling ? "Cancelling…" : "Uninstalling…" }
        return switch model.phase {
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


/// Observes the hosting NSWindow for the normal will-close notification. Termination is owned by
/// `AgentLensTerminationDelegate`/`AppLifecycleGate`; this observer does not replace the window
/// delegate, so optional AppKit delegate methods continue to belong to the real owner.
private struct WindowCloseObserver: NSViewRepresentable {
    let onClose: @MainActor () async -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onClose: onClose) }

    func makeNSView(context: Context) -> NSView {
        let view = HostingWindowView()
        view.onWindowChange = { window in context.coordinator.attach(to: window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Coordinator: NSObject, @unchecked Sendable {
        private let onClose: @MainActor () async -> Void
        private weak var window: NSWindow?
        private var observer: NSObjectProtocol?

        init(onClose: @escaping @MainActor () async -> Void) {
            self.onClose = onClose
        }

        @MainActor
        func attach(to window: NSWindow?) {
            guard self.window !== window else { return }
            if let observer { NotificationCenter.default.removeObserver(observer) }
            self.window = window
            guard let window else { return }
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.onCloseSynchronously() }
            }
        }

        private func onCloseSynchronously() {
            // The willClose notification is synchronous; release any pending preview here. The
            // application termination gate separately joins an active operation/reconciliation.
            Task { @MainActor [weak self] in await self?.onClose() }
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}

private final class HostingWindowView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }
}

/// One application-wide termination seam. The window owns the state/model; this gate only keeps the
/// existing lifecycle hook and lets the AppKit termination delegate await that same cancellation/join.
@MainActor
public final class AppLifecycleGate {
    public static let shared = AppLifecycleGate()

    private struct Entry {
        let shouldWait: @MainActor () -> Bool
        let cancelAndJoin: @MainActor () async -> Void
    }

    private var entries: [UUID: Entry] = [:]
    private var terminationInProgress = false

    private init() {}

    public func register(
        shouldWait: @escaping @MainActor () -> Bool,
        cancelAndJoin: @escaping @MainActor () async -> Void
    ) -> UUID {
        let token = UUID()
        entries[token] = Entry(shouldWait: shouldWait, cancelAndJoin: cancelAndJoin)
        return token
    }

    public func unregister(_ token: UUID) {
        entries.removeValue(forKey: token)
    }

    public var needsWait: Bool {
        entries.values.contains { $0.shouldWait() }
    }

    /// True exactly once for the first termination request that has active work.
    public func beginTermination() -> Bool {
        guard !terminationInProgress, needsWait else { return false }
        terminationInProgress = true
        return true
    }

    public func prepareForTermination() async {
        for entry in Array(entries.values) {
            guard entry.shouldWait() else { continue }
            await entry.cancelAndJoin()
        }
    }
}

/// Actual product termination delegate. It is shared by the shipping App and the controlled native
/// host; there is no copied lifecycle approximation in the fixture.
@MainActor
public class AgentLensTerminationDelegate: NSObject, NSApplicationDelegate {
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if AppLifecycleGate.shared.beginTermination() {
            Task { @MainActor in
                await AppLifecycleGate.shared.prepareForTermination()
                sender.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
        return AppLifecycleGate.shared.needsWait ? .terminateLater : .terminateNow
    }
}
