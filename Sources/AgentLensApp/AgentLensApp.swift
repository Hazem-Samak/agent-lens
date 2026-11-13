import SwiftUI
import AgentLensAppSupport
import AgentLensCore
import Foundation

@main
enum AgentLensAppEntry {
    static func main() {
        let args = CommandLine.arguments
        if args.count == 2 && args[1] == "--bundle-preflight" {
            let exitCode = runBundlePreflight()
            exit(exitCode)
        } else if args.count == 1 {
            AgentLensApp.main()
        } else {
            fputs("bundle-preflight: failed: unsupported argument vector\n", stderr)
            exit(1)
        }
    }

    private static func runBundlePreflight() -> Int32 {
        // 1. Fail safely if debug resource override environment variables are present
        let env = ProcessInfo.processInfo.environment
        if env["PACKAGE_RESOURCE_BUNDLE_PATH"] != nil || env["PACKAGE_RESOURCE_BUNDLE_URL"] != nil {
            fputs("bundle-preflight: failed: resource override environment present\n", stderr)
            return 1
        }

        // 2. Read packaging-generated metadata from main Info.plist
        guard let bundleName = Bundle.main.object(forInfoDictionaryKey: "AgentLensCoreResourceBundleName") as? String,
              !bundleName.isEmpty
        else {
            fputs("bundle-preflight: failed: missing AgentLensCoreResourceBundleName in Info.plist\n", stderr)
            return 1
        }

        guard let relativePath = Bundle.main.object(forInfoDictionaryKey: "AgentLensCoreResourceBundlePath") as? String,
              !relativePath.isEmpty
        else {
            fputs("bundle-preflight: failed: missing AgentLensCoreResourceBundlePath in Info.plist\n", stderr)
            return 1
        }

        // Relative path validation: must not start with / or contain parent-directory navigation
        if relativePath.hasPrefix("/") || relativePath.contains("..") {
            fputs("bundle-preflight: failed: invalid resource bundle path specification\n", stderr)
            return 1
        }

        // Expected relative path and name consistency check
        let expectedBundleFilename = bundleName + ".bundle"
        let expectedRelativePath = "Contents/Resources/" + expectedBundleFilename
        guard relativePath == expectedRelativePath else {
            fputs("bundle-preflight: failed: resource bundle path and name inconsistent\n", stderr)
            return 1
        }

        // Check that main resourceURL is available
        guard let mainResourceURL = Bundle.main.resourceURL else {
            fputs("bundle-preflight: failed: main bundle resource URL unavailable\n", stderr)
            return 1
        }

        let mainBundleURL = Bundle.main.bundleURL
        let targetURL = mainBundleURL.appendingPathComponent(relativePath).standardized
        let expectedBundleURL = mainResourceURL.appendingPathComponent(expectedBundleFilename).standardized

        // Verify guarded bundle is precisely under supported compiled lookup root (Bundle.main.resourceURL)
        let resolvedTarget = targetURL.resolvingSymlinksInPath()
        let resolvedExpected = expectedBundleURL.resolvingSymlinksInPath()
        let resolvedResourceRoot = mainResourceURL.resolvingSymlinksInPath()

        guard resolvedTarget.path == resolvedExpected.path else {
            fputs("bundle-preflight: failed: resource bundle not under supported lookup root\n", stderr)
            return 1
        }

        guard resolvedTarget.path.hasPrefix(resolvedResourceRoot.path + "/") else {
            fputs("bundle-preflight: failed: resource bundle path escapes application bundle\n", stderr)
            return 1
        }

        // Physically validate referenced bundled resource bundle directory exists
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolvedTarget.path, isDirectory: &isDir),
              isDir.boolValue
        else {
            fputs("bundle-preflight: failed: referenced resource bundle directory is missing\n", stderr)
            return 1
        }

        // Ensure valid Bundle(url:) and verify its resource lookup
        guard let coreBundle = Bundle(url: targetURL) else {
            fputs("bundle-preflight: failed: unable to initialize resource bundle\n", stderr)
            return 1
        }

        guard let detectorURL = coreBundle.url(forResource: "DefaultDetectors", withExtension: "json") else {
            fputs("bundle-preflight: failed: DefaultDetectors.json missing from resource bundle\n", stderr)
            return 1
        }

        let resolvedDetector = detectorURL.resolvingSymlinksInPath()
        guard resolvedDetector.path.hasPrefix(resolvedTarget.path + "/") else {
            fputs("bundle-preflight: failed: detector resource file escapes bundle directory\n", stderr)
            return 1
        }

        var fileIsDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolvedDetector.path, isDirectory: &fileIsDir),
              !fileIsDir.boolValue
        else {
            fputs("bundle-preflight: failed: DefaultDetectors.json missing from resource bundle\n", stderr)
            return 1
        }

        // Read guarded resource Data and validate through real DetectorRegistry.validate(data:)
        guard let data = try? Data(contentsOf: resolvedDetector) else {
            fputs("bundle-preflight: failed: unable to read detector registry data\n", stderr)
            return 1
        }

        let guardedDefinitions: [DetectorDefinition]
        do {
            guardedDefinitions = try DetectorRegistry.validate(data: data)
            guard !guardedDefinitions.isEmpty else {
                fputs("bundle-preflight: failed: registry contains no detectors\n", stderr)
                return 1
            }
        } catch is DetectorRegistryError {
            fputs("bundle-preflight: failed: invalid detector registry data\n", stderr)
            return 1
        } catch {
            fputs("bundle-preflight: failed: unexpected registry load error\n", stderr)
            return 1
        }

        // Now call real DetectorRegistry.loadDefault() and verify ordered match
        do {
            let loadedDefinitions = try DetectorRegistry.loadDefault()
            guard loadedDefinitions == guardedDefinitions else {
                fputs("bundle-preflight: failed: loaded registry mismatch with guarded bundle\n", stderr)
                return 1
            }
            let ids = loadedDefinitions.map(\.id).joined(separator: " ")
            print("bundle-preflight: ok registry_count=\(loadedDefinitions.count) registry_ids=\(ids)")
            return 0
        } catch is DetectorRegistryError {
            fputs("bundle-preflight: failed: invalid detector registry data\n", stderr)
            return 1
        } catch {
            fputs("bundle-preflight: failed: unexpected registry load error\n", stderr)
            return 1
        }
    }
}

/// Everything the menu bar needs from the focused window, captured as values plus main-actor
/// actions. The ViewModel's R1 hooks stay the only invalidation path: menu items call the same
/// public actions the toolbar calls, and destination selection writes the same destination state.
@MainActor
struct AppCommandActions {
    let isBusy: Bool
    let isSheetPresented: Bool
    let updateAffordanceIsPrepare: Bool
    let uninstallAffordanceIsPrepare: Bool
    let canVerifyInstallation: Bool
    let selectDestination: @MainActor (NavigationDestination) -> Void
    let rescan: @MainActor () -> Void
    let checkForUpdates: @MainActor () -> Void
    let refreshUpdates: @MainActor () -> Void
    let prepareUpdate: @MainActor () -> Void
    let prepareUninstall: @MainActor () -> Void
    let verifyInstallation: @MainActor () -> Void
}

private struct AppCommandActionsKey: FocusedValueKey {
    typealias Value = AppCommandActions
}

extension FocusedValues {
    var appCommandActions: AppCommandActions? {
        get { self[AppCommandActionsKey.self] }
        set { self[AppCommandActionsKey.self] = newValue }
    }
}

/// The native menu bar (R9). No item ever confirms a mutation: the Tool items prepare or verify
/// only. Edit keeps the standard system items (⌘C is not overridden), ⌘F stays the searchable
/// field's own shortcut, and path actions remain the detail-view buttons.
struct AgentLensCommands: Commands {
    @FocusedValue(\.appCommandActions) private var actions

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                actions?.selectDestination(.settings)
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(after: .newItem) {
            Divider()
            Button("Rescan") {
                actions?.rescan()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(fileItemsDisabled)

            Button("Check for Updates") {
                actions?.checkForUpdates()
            }
            .keyboardShortcut("u", modifiers: .command)
            .disabled(fileItemsDisabled)

            Button("Refresh Update Metadata") {
                actions?.refreshUpdates()
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])
            .disabled(fileItemsDisabled)
        }

        CommandGroup(after: .sidebar) {
            Divider()
            Button("Overview") {
                actions?.selectDestination(.overview)
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("AI Agents") {
                actions?.selectDestination(.aiAgents)
            }
            .keyboardShortcut("2", modifiers: .command)

            Button("AI Coding Tools") {
                actions?.selectDestination(.aiCodingTools)
            }
            .keyboardShortcut("3", modifiers: .command)

            Button("AI Harnesses") {
                actions?.selectDestination(.aiHarnesses)
            }
            .keyboardShortcut("4", modifiers: .command)

            Button("Updates") {
                actions?.selectDestination(.updates)
            }
            .keyboardShortcut("5", modifiers: .command)

            Button("Diagnostics") {
                actions?.selectDestination(.diagnostics)
            }
            .keyboardShortcut("6", modifiers: .command)

            Button("Settings") {
                actions?.selectDestination(.settings)
            }
            .keyboardShortcut("7", modifiers: .command)
        }

        CommandMenu("Tool") {
            Button("Prepare Update…") {
                actions?.prepareUpdate()
            }
            .keyboardShortcut("u", modifiers: [.command, .option])
            .disabled(!canPrepareUpdate)

            Button("Prepare Uninstall…") {
                actions?.prepareUninstall()
            }
            .keyboardShortcut(.delete, modifiers: [.command, .option])
            .disabled(!canPrepareUninstall)

            Divider()

            Button("Verify Installation") {
                actions?.verifyInstallation()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(!canVerifyInstallation)
        }
    }

    private var fileItemsDisabled: Bool {
        actions?.isBusy ?? true
    }

    private var canPrepareUpdate: Bool {
        guard let actions else { return false }
        return !actions.isBusy && !actions.isSheetPresented && actions.updateAffordanceIsPrepare
    }

    private var canPrepareUninstall: Bool {
        guard let actions else { return false }
        return !actions.isBusy && !actions.isSheetPresented && actions.uninstallAffordanceIsPrepare
    }

    private var canVerifyInstallation: Bool {
        guard let actions else { return false }
        return !actions.isBusy && actions.canVerifyInstallation
    }
}

struct AgentLensApp: App {
    @NSApplicationDelegateAdaptor(AgentLensTerminationDelegate.self) private var terminationDelegate

    var body: some Scene {
        Window("Agent Lens", id: "main") {
            MainWindow()
        }
        .defaultSize(width: 960, height: 600)
        .commands {
            AgentLensCommands()
        }
    }
}
