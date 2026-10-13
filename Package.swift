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
        .target(
            name: "AgentLensCore"
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
