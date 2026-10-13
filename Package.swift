// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentLens",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        // The engine: models, scanner, detectors, package-manager adapters, operations.
        // Must never import SwiftUI or AppKit (D-002).
        // The detector registry JSON (D-010, D-017) is a bundled resource —
        // a resource DECLARATION, not a dependency; the package stays at zero external packages.
        .target(
            name: "AgentLensCore",
            resources: [
                .copy("Detectors/DefaultDetectors.json")
            ]
        ),
        // The CLI. The SwiftUI app target arrives at M7 (D-011, D-016).
        .executableTarget(
            name: "agent-lens",
            dependencies: ["AgentLensCore"]
        ),
        .testTarget(
            name: "AgentLensCoreTests",
            dependencies: ["AgentLensCore"]
        ),
    ]
)
