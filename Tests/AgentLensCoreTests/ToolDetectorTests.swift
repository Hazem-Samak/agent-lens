import Testing
import Foundation
@testable import AgentLensCore

// M3 tests — the brief's required units, all with injected environments and
// temp-dir fixtures so they never depend on the test machine's real state.

@discardableResult
private func makeExecutable(script: String, in directory: URL, named name: String) throws -> String {
    let fileURL = directory.appendingPathComponent(name)
    try Data("#!/bin/sh\n\(script)\n".utf8).write(to: fileURL)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755], ofItemAtPath: fileURL.path
    )
    return fileURL.path
}

private func fixtureEnvironment(
    pathEntries: [String],
    pathJoined: String? = nil,
    extraRaw: [String: String] = [:]
) -> ShellEnvironment {
    let joined = pathJoined ?? pathEntries.joined(separator: ":")
    return ShellEnvironment(
        shellPath: "/bin/zsh",
        pathEntries: pathEntries,
        pathJoined: joined,
        raw: ["PATH": joined].merging(extraRaw) { _, new in new },
        isDegraded: false
    )
}

@Test func detectorFindsExecutableOnPath() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("agentlens-m3-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let executablePath = try makeExecutable(script: "exit 0", in: dir, named: "fakecli")

    let detector = ToolDetector(
        displayName: "FakeCLI",
        executableName: "fakecli",
        versionQuery: { _, _, _ in nil }
    )
    let tool = detector.detect(in: fixtureEnvironment(pathEntries: [dir.path]))

    #expect(tool.state == .installedAndOnPath)
    #expect(tool.entryPath == executablePath)
    #expect(tool.resolvedPath == executablePath)  // not a symlink -> resolves to itself
    #expect(tool.source == "standalone")          // /var/folders... is neither npm nor Cellar
}

@Test func detectorUsesExtraRootsForInstalledNotOnPath() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("agentlens-m3-\(UUID().uuidString)")
    let offPathDir = tmp.appendingPathComponent("off-path")
    let onPathDir = tmp.appendingPathComponent("on-path")
    try FileManager.default.createDirectory(at: offPathDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: onPathDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    _ = try makeExecutable(script: "exit 0", in: offPathDir, named: "fakecli")

    let detector = ToolDetector(
        displayName: "FakeCLI",
        executableName: "fakecli",
        extraSearchRoots: [offPathDir.path],
        versionQuery: { _, _, _ in nil }
    )
    let tool = detector.detect(in: fixtureEnvironment(pathEntries: [onPathDir.path]))

    #expect(tool.state == .installedNotOnPath)
    #expect(tool.entryPath == offPathDir.appendingPathComponent("fakecli").path)
}

@Test func detectorReportsNotInstalledWhenNothingFound() {
    let detector = ToolDetector(
        displayName: "FakeCLI",
        executableName: "nothing-named-this",
        versionQuery: { _, _, _ in nil }
    )
    let tool = detector.detect(in: fixtureEnvironment(pathEntries: ["/nonexistent-root"]))

    #expect(tool.state == .notInstalled)
    #expect(tool.source == "–")
    #expect(tool.version == nil)
}

@Test func detectorClassifiesNpmByResolvedSymbolicLinkTarget() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("agentlens-m3-\(UUID().uuidString)")
    let toolBin = tmp.appendingPathComponent("bin")
    let nodeModules = tmp.appendingPathComponent("lib/node_modules/@x/fakecli/bin")
    try FileManager.default.createDirectory(at: nodeModules, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: toolBin, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    // Real npm-style chain: bin shim symlink -> deep node_modules executable.
    let target = try makeExecutable(script: "exit 0", in: nodeModules, named: "fakecli.js")
    let shim = toolBin.appendingPathComponent("fakecli")
    try FileManager.default.createSymbolicLink(atPath: shim.path, withDestinationPath: target)

    let detector = ToolDetector(
        displayName: "FakeCLI",
        executableName: "fakecli",
        versionQuery: { _, _, _ in nil }
    )
    let tool = detector.detect(in: fixtureEnvironment(pathEntries: [toolBin.path]))

    #expect(tool.state == .installedAndOnPath)
    #expect(tool.source == "npm")                       // resolved target, NOT the shim dir
    #expect(tool.resolvedPath?.contains("/lib/node_modules/") == true)
    #expect(tool.resolvedPath?.hasSuffix("fakecli.js") == true)
}

@Test func detectorClassifiesCellarAsBrew() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("agentlens-m3-\(UUID().uuidString)")
    let cellarBin = tmp.appendingPathComponent("Cellar/fakecli/0.1/bin")
    try FileManager.default.createDirectory(at: cellarBin, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    _ = try makeExecutable(script: "exit 0", in: cellarBin, named: "fakecli")

    let detector = ToolDetector(
        displayName: "FakeCLI",
        executableName: "fakecli",
        versionQuery: { _, _, _ in nil }
    )
    let tool = detector.detect(in: fixtureEnvironment(pathEntries: [cellarBin.path]))

    #expect(tool.state == .installedAndOnPath)
    #expect(tool.source == "brew")
}

@Test func versionTokenExtractionHandlesKnownOutputShapes() {
    #expect(ToolDetector.extractVersionToken(from: "codex-cli 0.162.1") == "0.162.1")
    #expect(ToolDetector.extractVersionToken(from: "v1.2.3") == "1.2.3")
    #expect(ToolDetector.extractVersionToken(from: "mytool 1.0.0-beta.2 (build 7)") == "1.0.0-beta.2")
    #expect(ToolDetector.extractVersionToken(from: "no version here") == nil)
}

@Test func versionQueryTimesOutAgainstHangingBinary() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("agentlens-m3-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let hangingBinary = try makeExecutable(script: "sleep 30", in: dir, named: "hanging-tool")
    let environment = fixtureEnvironment(pathEntries: [dir.path])

    let started = Date()
    let version = ToolDetector.queryVersion(
        executablePath: hangingBinary, environment: environment, timeout: 0.5
    )
    let elapsed = Date().timeIntervalSince(started)

    #expect(version == nil)          // unknown, not hung (D-007)
    #expect(elapsed < 5.0)           // the timeout is real: ~0.5s, not 30s
}

@Test func scanRendererShapesAllThreeStates() {
    let onPath = DetectedTool(
        displayName: "Codex", executableName: "codex",
        state: .installedAndOnPath, entryPath: "/x/codex", resolvedPath: "/y/codex.js",
        source: "npm", version: "0.162.1"
    )
    let notOnPath = DetectedTool(
        displayName: "Codex", executableName: "codex",
        state: .installedNotOnPath, entryPath: "/z/codex", resolvedPath: "/z/codex",
        source: "standalone", version: nil
    )
    let absent = DetectedTool(
        displayName: "Codex", executableName: "codex",
        state: .notInstalled, entryPath: nil, resolvedPath: nil,
        source: "–", version: nil
    )

    let output = ScanRenderer.render(tools: [onPath, notOnPath, absent])
    #expect(output.contains("AI AGENTS                         3"))
    #expect(output.contains("✓ Codex          0.162.1    npm"))
    #expect(output.contains("! Codex          –    standalone (not on PATH)"))   // unknown version -> dash
    #expect(output.contains("– Codex          –    –"))
}
