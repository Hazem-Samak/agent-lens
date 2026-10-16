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

struct AgentLensApp: App {
    var body: some Scene {
        Window("Agent Lens", id: "main") {
            MainWindow()
        }
        .defaultSize(width: 960, height: 600)
    }
}
