import Darwin
import Foundation
import Testing
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

private func fixtureRoot(_ label: String) throws -> URL {
    let environment = ProcessInfo.processInfo.environment
    guard let basePath = [environment["AGENT_LENS_TEST_SCRATCH"], environment["TMPDIR"]]
        .compactMap({ $0 })
        .first(where: { !$0.isEmpty })
    else {
        throw NSError(domain: "AgentLensTests", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "no approved test scratch root is available"])
    }
    let base = URL(fileURLWithPath: basePath, isDirectory: true).resolvingSymlinksInPath()
    let root = base.appendingPathComponent("agentlens-m3-\(label)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root.resolvingSymlinksInPath()
}

private func agentLensCoreProductsDirectory() throws -> URL {
    let fileManager = FileManager.default
    let override = ProcessInfo.processInfo.environment["AGENT_LENS_TEST_PRODUCTS"]
    func hasCoreArtifacts(_ directory: URL) -> Bool {
        let objectExists = fileManager.fileExists(
            atPath: directory.appendingPathComponent("AgentLensCore.o").path
        )
        let moduleExists = fileManager.fileExists(
            atPath: directory.appendingPathComponent("AgentLensCore.swiftmodule").path
        ) || fileManager.fileExists(
            atPath: directory.appendingPathComponent("Modules/AgentLensCore.swiftmodule").path
        )
        return objectExists && moduleExists
    }
    func isBuildProductDirectory(_ directory: URL) -> Bool {
        let pathIsProduct = directory.pathComponents.contains("Products")
        let pathIsSwiftPMConfiguration = ["debug", "release"].contains(
            directory.lastPathComponent.lowercased()
        )
        return hasCoreArtifacts(directory) && (pathIsProduct || pathIsSwiftPMConfiguration)
    }

    if let override {
        let directory = URL(fileURLWithPath: override, isDirectory: true).standardizedFileURL
        if hasCoreArtifacts(directory) { return directory }
    }

    let executableDirectories = [
        Bundle.main.executableURL?.deletingLastPathComponent().path,
        CommandLine.arguments.first.map { URL(fileURLWithPath: $0).standardizedFileURL.deletingLastPathComponent().path }
    ].compactMap { $0 }.map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }
    var directCandidates: [URL] = []
    for executableDirectory in executableDirectories {
        var candidate = executableDirectory
        for _ in 0..<8 {
            directCandidates.append(candidate)
            let parent = candidate.deletingLastPathComponent()
            if parent == candidate { break }
            candidate = parent
        }
    }

    for candidate in directCandidates where isBuildProductDirectory(candidate) {
        return candidate
    }

    var searchRoots: [URL] = []
    if let override {
        searchRoots.append(URL(fileURLWithPath: override, isDirectory: true))
    }
    if let scratch = ProcessInfo.processInfo.environment["AGENT_LENS_TEST_SCRATCH"] {
        searchRoots.append(URL(fileURLWithPath: scratch, isDirectory: true).deletingLastPathComponent())
    }
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .standardizedFileURL
    searchRoots.append(packageRoot.appendingPathComponent(".build", isDirectory: true))
    searchRoots.append(packageRoot.appendingPathComponent("build", isDirectory: true))

    var searchedPaths = Set<String>()
    for root in searchRoots where searchedPaths.insert(root.path).inserted {
        guard fileManager.fileExists(atPath: root.path),
              let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
              )
        else {
            continue
        }
        while let item = enumerator.nextObject() as? URL {
            if isBuildProductDirectory(item) {
                return item
            }
        }
    }

    throw NSError(
        domain: "AgentLensCoreProducts",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "could not locate the active AgentLensCore.o build product"]
    )
}

@Test func detectorFindsExecutableOnPath() throws {
    let dir = try fixtureRoot("find")
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
    let tmp = try fixtureRoot("off-path")
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
    let tmp = try fixtureRoot("npm")
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
    let tmp = try fixtureRoot("brew")
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
    let dir = try fixtureRoot("hanging-version")
    defer { try? FileManager.default.removeItem(at: dir) }

    let hangingBinary = try makeExecutable(script: "exec /bin/sleep 30", in: dir, named: "hanging-tool")
    let environment = fixtureEnvironment(pathEntries: [dir.path])

    let started = DispatchTime.now().uptimeNanoseconds
    let version = ToolDetector.queryVersion(
        executablePath: hangingBinary, environment: environment, timeout: 0.2
    )
    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000

    #expect(version == nil)          // unknown, not hung (D-007)
    #expect(elapsed >= 0.15 && elapsed < 1.0, "elapsed: \(elapsed)")
}

@Test func detectorDoesNotTreatDirectoryAsAnInstalledExecutable() throws {
    let root = try fixtureRoot("directory-candidate")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(
        at: root.appendingPathComponent("fakecli"), withIntermediateDirectories: true
    )

    let detector = ToolDetector(
        displayName: "FakeCLI", executableName: "fakecli", versionQuery: { _, _, _ in nil }
    )
    let tool = detector.detect(in: fixtureEnvironment(pathEntries: [root.path]))

    #expect(tool.state == .notInstalled)
    #expect(tool.entryPath == nil)
}

@Test func detectorSkipsBrokenSymlinkAndKeepsFirstLivePathWinner() throws {
    let root = try fixtureRoot("symlink-order")
    let directoryRoot = root.appendingPathComponent("directory")
    let brokenRoot = root.appendingPathComponent("broken")
    let nonExecutableRoot = root.appendingPathComponent("non-executable")
    let directorySymlinkRoot = root.appendingPathComponent("directory-symlink")
    let liveRoot = root.appendingPathComponent("live")
    let laterRoot = root.appendingPathComponent("later")
    let targetRoot = root.appendingPathComponent("target")
    let directoryTarget = root.appendingPathComponent("directory-target", isDirectory: true)
    for directory in [directoryRoot, brokenRoot, nonExecutableRoot, directorySymlinkRoot,
                      liveRoot, laterRoot, targetRoot, directoryTarget] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    defer { try? FileManager.default.removeItem(at: root) }

    try FileManager.default.createDirectory(
        at: directoryRoot.appendingPathComponent("fakecli"), withIntermediateDirectories: true
    )
    let brokenLink = brokenRoot.appendingPathComponent("fakecli")
    try FileManager.default.createSymbolicLink(
        atPath: brokenLink.path,
        withDestinationPath: root.appendingPathComponent("missing-target").path
    )
    let nonExecutable = nonExecutableRoot.appendingPathComponent("fakecli")
    try Data("not executable\n".utf8).write(to: nonExecutable)
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: nonExecutable.path)
    try FileManager.default.createSymbolicLink(
        atPath: directorySymlinkRoot.appendingPathComponent("fakecli").path,
        withDestinationPath: directoryTarget.path
    )
    let target = try makeExecutable(script: "exit 0", in: targetRoot, named: "fakecli-target")
    let liveLink = liveRoot.appendingPathComponent("fakecli")
    try FileManager.default.createSymbolicLink(atPath: liveLink.path, withDestinationPath: target)
    _ = try makeExecutable(script: "exit 0", in: laterRoot, named: "fakecli")

    let detector = ToolDetector(
        displayName: "FakeCLI", executableName: "fakecli", versionQuery: { _, _, _ in nil }
    )
    let tool = detector.detect(in: fixtureEnvironment(
        pathEntries: [directoryRoot.path, brokenRoot.path, nonExecutableRoot.path,
                      directorySymlinkRoot.path, liveRoot.path, laterRoot.path]
    ))

    #expect(tool.state == .installedAndOnPath)
    #expect(tool.entryPath == liveLink.path)
    #expect(tool.resolvedPath == target)
}

@Test func detectorKeepsOrderAcrossEmptyPATHComponents() throws {
    let root = try fixtureRoot("empty-path-order")
    let firstRoot = root.appendingPathComponent("first")
    let secondRoot = root.appendingPathComponent("second")
    try FileManager.default.createDirectory(at: firstRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    _ = try makeExecutable(script: "exit 0", in: firstRoot, named: "fakecli")
    _ = try makeExecutable(script: "exit 0", in: secondRoot, named: "fakecli")
    let path = ":\(firstRoot.path)::\(secondRoot.path):"
    let environment = ShellEnvironmentResolver.buildEnvironment(
        shellPath: "/bin/sh",
        outcome: ShellEnvironmentResolver.CaptureOutcome(dump: ["PATH": path], timedOut: false)
    )
    let detector = ToolDetector(
        displayName: "FakeCLI", executableName: "fakecli", versionQuery: { _, _, _ in nil }
    )

    let tool = detector.detect(in: environment)

    #expect(environment.pathEntries == ["", firstRoot.path, "", secondRoot.path, ""])
    #expect(environment.pathJoined == path)
    #expect(environment.raw["PATH"] == path)
    #expect(tool.entryPath == firstRoot.appendingPathComponent("fakecli").path)
}

@Test func detectorAndVersionQueryHonorEmptyAndRelativeRootsInAnIsolatedWorkingDirectory() throws {
    let root = try fixtureRoot("isolated-relative-path")
    defer { try? FileManager.default.removeItem(at: root) }
    try makeExecutable(script: "printf 'cwd 3.4.5\\n'", in: root, named: "fakecli")
    let relativeRoot = root.appendingPathComponent("relative-bin")
    try FileManager.default.createDirectory(at: relativeRoot, withIntermediateDirectories: true)
    try makeExecutable(script: "printf 'relative 6.7.8\\n'", in: relativeRoot, named: "fakecli")

    let products = try agentLensCoreProductsDirectory()
    let source = root.appendingPathComponent("relative-path-probe.swift")
    let executable = root.appendingPathComponent("relative-path-probe")
    let sourceText = """
    import Foundation
    import AgentLensCore

    let detector = ToolDetector(displayName: "FakeCLI", executableName: "fakecli")
    let emptyEnvironment = ShellEnvironment(
        shellPath: "/bin/sh", pathEntries: ["", "relative-bin"],
        pathJoined: ":relative-bin", raw: ["PATH": ":relative-bin"], isDegraded: false
    )
    let relativeEnvironment = ShellEnvironment(
        shellPath: "/bin/sh", pathEntries: ["relative-bin"],
        pathJoined: "relative-bin", raw: ["PATH": "relative-bin"], isDegraded: false
    )
    let empty = detector.detect(in: emptyEnvironment)
    let relative = detector.detect(in: relativeEnvironment)
    print([empty.entryPath ?? "nil", empty.resolvedPath ?? "nil", empty.version ?? "nil"].joined(separator: "|"))
    print([relative.entryPath ?? "nil", relative.resolvedPath ?? "nil", relative.version ?? "nil"].joined(separator: "|"))
    """
    try Data(sourceText.utf8).write(to: source)

    func run(_ process: Process) throws -> (Int32, String, String) {
        let stdoutURL = root.appendingPathComponent("verifier-stdout-\(UUID().uuidString)")
        let stderrURL = root.appendingPathComponent("verifier-stderr-\(UUID().uuidString)")
        try Data().write(to: stdoutURL)
        try Data().write(to: stderrURL)
        let stdout = try FileHandle(forWritingTo: stdoutURL)
        let stderr = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdout.close()
            try? stderr.close()
            try? FileManager.default.removeItem(at: stdoutURL)
            try? FileManager.default.removeItem(at: stderrURL)
        }
        process.standardOutput = stdout
        process.standardError = stderr
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        try process.run()
        try stdout.close()
        try stderr.close()
        guard exited.wait(timeout: .now() + 30) == .success else {
            process.terminate()
            _ = kill(process.processIdentifier, SIGKILL)
            _ = exited.wait(timeout: .now() + 1)
            return (SIGKILL, "", "isolated verifier exceeded its 30-second watchdog")
        }
        let output = String(data: try Data(contentsOf: stdoutURL), encoding: .utf8) ?? ""
        let errors = String(data: try Data(contentsOf: stderrURL), encoding: .utf8) ?? ""
        return (process.terminationStatus, output, errors)
    }

    let compiler = Process()
    compiler.executableURL = URL(fileURLWithPath: "/usr/bin/swiftc")
    compiler.arguments = [
        "-I", products.path, source.path,
        products.appendingPathComponent("AgentLensCore.o").path,
        "-o", executable.path
    ]
    compiler.currentDirectoryURL = root
    let compile = try run(compiler)
    guard compile.0 == 0 else {
        Issue.record("isolated PATH verifier compilation failed: \(compile.1)\n\(compile.2)")
        return
    }

    let verifier = Process()
    verifier.executableURL = executable
    verifier.currentDirectoryURL = root
    let result = try run(verifier)
    let expected = [
        "fakecli|\(root.appendingPathComponent("fakecli").path)|3.4.5",
        "relative-bin/fakecli|\(relativeRoot.appendingPathComponent("fakecli").path)|6.7.8"
    ].joined(separator: "\n") + "\n"
    #expect(result.0 == 0, "isolated PATH verifier failed: \(result.2)")
    #expect(result.1 == expected, "isolated PATH verifier output differed: \(result.1)")
}

@Test func versionQueryKillsTerminationResistantProcessAfterEarlyStdoutEOF() throws {
    let root = try fixtureRoot("early-eof-version")
    defer { try? FileManager.default.removeItem(at: root) }
    let pidFile = root.appendingPathComponent("child.pid")
    let binary = try makeExecutable(
        script: "printf '%s' \"$$\" > '\(pidFile.path)'; exec 1>&-; trap '' TERM; exec /bin/sleep 30",
        in: root,
        named: "early-eof-tool"
    )
    let environment = fixtureEnvironment(pathEntries: [root.path])

    let started = DispatchTime.now().uptimeNanoseconds
    let version = ToolDetector.queryVersion(
        executablePath: binary, environment: environment, timeout: 2
    )
    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000
    let pidText = try String(contentsOf: pidFile, encoding: .utf8)
    let pid = try #require(pid_t(pidText))
    defer {
        if kill(pid, 0) == 0 { _ = kill(pid, SIGKILL) }
    }

    #expect(version == nil)
    #expect(elapsed >= 1.9 && elapsed < 2.8, "elapsed: \(elapsed)")
    #expect(kill(pid, 0) == -1)
}

@Test func versionQueryRejectsOutputFromNonzeroExit() throws {
    let root = try fixtureRoot("nonzero-version")
    defer { try? FileManager.default.removeItem(at: root) }
    let binary = try makeExecutable(
        script: "printf 'FakeCLI 9.8.7\\n'; exit 7", in: root, named: "failed-version-tool"
    )
    let environment = fixtureEnvironment(pathEntries: [root.path])

    let version = ToolDetector.queryVersion(
        executablePath: binary, environment: environment, timeout: 1
    )

    #expect(version == nil)
}

@Test func versionQueryRejectsTruncatedOutputEvenWhenTheFirstLineLooksValid() throws {
    let root = try fixtureRoot("truncated-version")
    defer { try? FileManager.default.removeItem(at: root) }
    let binary = try makeExecutable(
        script: "printf 'FakeCLI 9.8.7\\n'; /usr/bin/yes x | /usr/bin/head -c 1200000",
        in: root,
        named: "verbose-version-tool"
    )

    let version = ToolDetector.queryVersion(
        executablePath: binary,
        environment: fixtureEnvironment(pathEntries: [root.path]),
        timeout: 4
    )

    #expect(version == nil)
}

@Test func boundedProcessRunnerEnforcesDeadlineWhileStdoutRemainsReadable() throws {
    let root = try fixtureRoot("continuous-output")
    defer { try? FileManager.default.removeItem(at: root) }
    let pidFile = root.appendingPathComponent("continuous-writer.pid")
    let script = "printf '%s' \"$$\" > '\(pidFile.path)'; exec /usr/bin/yes x"

    let started = DispatchTime.now().uptimeNanoseconds
    let result = BoundedProcessRunner.run(
        executablePath: "/bin/sh",
        arguments: ["-c", script],
        environment: ["PATH": "/usr/bin:/bin"],
        timeout: 1.5
    )
    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000
    let pidText = try String(contentsOf: pidFile, encoding: .utf8)
    let pid = try #require(pid_t(pidText))
    defer {
        if kill(pid, 0) == 0 { _ = kill(pid, SIGKILL) }
    }

    #expect(result?.timedOut == false)
    #expect(result?.outputLimitExceeded == true)
    #expect((result?.standardOutput.count ?? .max) <= BoundedProcessRunner.maximumStandardOutputBytes)
    #expect(elapsed < 1.5, "elapsed: \(elapsed)")
    #expect(kill(pid, 0) == -1)
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
