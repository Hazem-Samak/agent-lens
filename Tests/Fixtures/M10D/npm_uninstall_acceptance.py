#!/usr/bin/env python3
"""Secret-free M10-D npm uninstall acceptance fixture.

Reuses the M10-C standard-library registry/tarball/identity helpers. Every created path is beneath
the operator-supplied --root; the root must not pre-exist and is never deleted.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve()
sys.path.insert(0, str(HERE.parents[1] / "M10C"))
import npm_update_acceptance as base  # noqa: E402

PACKAGE = base.PACKAGE
TARGET_OLD = base.TARGET_OLD
TARGET_NEW = base.TARGET_NEW

HOST_SOURCE = r'''
import Foundation
import AgentLensCore

final class FakeNpmRunner: UpdateCommandRunner, @unchecked Sendable {
    let prefix: String
    let root: String
    init(prefix: String, root: String) { self.prefix = prefix; self.root = root }
    func run(executablePath: String, arguments: [String],
             environment: [String: String], timeout: TimeInterval) async -> CommandOutcome {
        if arguments.contains("prefix") { return .success(Data((prefix + "\n").utf8)) }
        if arguments.contains("root") { return .success(Data((root + "\n").utf8)) }
        return .failure(.spawnFailure)
    }
}

final class RecordingUninstallRunner: OperationCommandRunner, @unchecked Sendable {
    let record: URL
    let inner = ProcessOperationCommandRunner()
    private let lock = NSLock()
    init(record: URL) { self.record = record }

    private func note(_ value: [String: Any]) {
        lock.lock()
        var existing = (try? Data(contentsOf: record)) ?? Data()
        if !existing.isEmpty { existing.append(10) }
        let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        existing.append(data)
        try? existing.write(to: record)
        lock.unlock()
    }

    func run(executablePath: String, arguments: [String],
             environment: [String: String], currentDirectory: String,
             timeout: TimeInterval) async -> OperationCommandResult {
        note(["argv": [executablePath] + arguments])
        return await inner.run(executablePath: executablePath, arguments: arguments,
                               environment: environment, currentDirectory: currentDirectory,
                               timeout: timeout)
    }
}

@main
struct UninstallHost {
    static func main() async throws {
        let args = CommandLine.arguments
        let manager = args[1], prefix = args[2], root = args[3], alias = args[4]
        let resultPath = args[5], recordPath = args[6], operationBase = args[7]
        let environmentRaw = ProcessInfo.processInfo.environment
        let path = environmentRaw["PATH"] ?? "/usr/bin:/bin"
        let entries = path.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        var raw: [String: String] = ["PATH": path]
        for key in ["HOME", "TMPDIR", "CFFIXED_USER_HOME", "ZDOTDIR",
                    "npm_config_cache", "npm_config_logs_dir", "npm_config_userconfig",
                    "npm_config_globalconfig"] {
            if let value = environmentRaw[key] { raw[key] = value }
        }
        let environment = ShellEnvironment(shellPath: "/bin/zsh", pathEntries: entries,
            pathJoined: path, raw: raw, isDegraded: false)
        let definitionData = Data("""
        {"schemaVersion":2,"detectors":[{"id":"codex-id","displayName":"Codex","executableName":"codex","category":"aiAgent","packages":[{"manager":"npm","name":"@openai/codex"}],"acceptedOperations":["npmUninstall"],"versionQuery":{"arguments":["--version"],"stream":"stdout","line":"first"}}]}
        """.utf8)
        let definition = try DetectorRegistry.validate(data: definitionData)[0]
        let diagnostic = PathDiagnosticsScanner.scan(
            detector: definition.makeDetector(), environment: environment,
            currentDirectory: root)
        let updateRunner = FakeNpmRunner(prefix: prefix, root: prefix + "/lib/node_modules")
        let operationRunner = RecordingUninstallRunner(record: URL(fileURLWithPath: recordPath))
        let baseURL = URL(fileURLWithPath: operationBase)

        let ownership = await InstallationOwnershipVerifier.verify(
            definition: definition, diagnostic: diagnostic, environment: environment,
            runner: updateRunner, currentDirectory: root, now: { Date() })
        var probeReason = "verified"
        if case .unknown(let reason) = ownership.outcome { probeReason = String(describing: reason) }
        FileHandle.standardError.write(Data(("OWNERSHIP-PROBE: " + probeReason + "\n").utf8))

        let prepared = await NpmUninstallOperation.prepare(
            definition: definition, diagnostic: diagnostic, environment: environment,
            currentDirectory: root, runner: updateRunner, operationRootBaseURL: baseURL)
        guard case .ready(let preparation) = prepared else {
            var value: [String: Any] = ["state": "unavailable"]
            if case .unavailable(let reason) = prepared { value["reason"] = reason.rawValue }
            let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
            try data.write(to: URL(fileURLWithPath: resultPath))
            if let reason = value["reason"] as? String {
                FileHandle.standardError.write(Data(("UNAVAILABLE: " + reason + "\n").utf8))
            }
            exit(2)
        }
        let outcome = await NpmUninstallOperation.execute(
            confirmed: preparation, environment: environment,
            scan: { _, env, cwd in
                PathDiagnosticsScanner.scan(detector: definition.makeDetector(),
                    environment: env, currentDirectory: cwd)
            },
            reconcileAfterLaunch: { _ in
                (PathDiagnosticsScanner.scan(detector: definition.makeDetector(),
                    environment: environment, currentDirectory: root), environment)
            },
            updateRunner: updateRunner, operationRunner: operationRunner,
            gate: OperationExecutionGate())
        let value: [String: Any] = [
            "state": outcome.state.rawValue,
            "processStarted": outcome.processStarted,
            "exit": outcome.exitStatus as Any,
            "stdout": outcome.stdoutText,
            "stderr": outcome.stderrText,
            "packageDirectoryAbsent": outcome.reconciliation?.packageDirectoryAbsent as Any,
            "selectedTargetReleased": outcome.reconciliation?.selectedTargetReleased as Any,
            "selectedEntryResidue": outcome.reconciliation?.selectedEntryResidue as Any,
            "observationFailed": outcome.reconciliation?.observationFailed as Any,
            "afterInstallState": outcome.reconciliation?.afterInstallState.rawValue as Any,
            "cleanupWarnings": outcome.cleanupWarnings,
            "message": outcome.message as Any,
            "previewArguments": preparation.preview.arguments,
        ]
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: resultPath))
    }
}
'''


COMBINED_HOST_SOURCE = r'''
import Foundation
import AgentLensCore

final class CombinedUpdateRunner: UpdateCommandRunner, @unchecked Sendable {
    let prefix: String
    let root: String
    let latest: String
    init(prefix: String, root: String, latest: String) {
        self.prefix = prefix; self.root = root; self.latest = latest
    }
    func run(executablePath: String, arguments: [String],
             environment: [String: String], timeout: TimeInterval) async -> CommandOutcome {
        if arguments.contains("prefix") { return .success(Data((prefix + "\n").utf8)) }
        if arguments.contains("root") { return .success(Data((root + "\n").utf8)) }
        if arguments.contains("view") {
            return .success(Data("{\"name\":\"@openai/codex\",\"version\":\"\(latest)\",\"dist-tags.latest\":\"\(latest)\"}".utf8))
        }
        if arguments.contains("--version") { return .success(Data("10.9.8\n".utf8)) }
        if arguments.contains(where: { $0.hasSuffix(":registry") }) {
            return .success(Data("undefined\n".utf8))
        }
        if arguments.contains("registry") {
            return .success(Data("https://registry.npmjs.org/\n".utf8))
        }
        return .failure(.spawnFailure)
    }
}

final class LoopbackUpdateRunner: OperationCommandRunner, @unchecked Sendable {
    let loopback: String
    let record: URL
    let inner = ProcessOperationCommandRunner()
    private let lock = NSLock()
    init(loopback: String, record: URL) { self.loopback = loopback; self.record = record }
    private func note(_ value: [String: Any]) {
        lock.lock()
        var data = (try? Data(contentsOf: record)) ?? Data()
        if !data.isEmpty { data.append(10) }
        data.append(try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]))
        try? data.write(to: record)
        lock.unlock()
    }
    func run(executablePath: String, arguments: [String],
             environment: [String: String], currentDirectory: String,
             timeout: TimeInterval) async -> OperationCommandResult {
        let original = [executablePath] + arguments
        let baseFlags = arguments.filter { $0.hasPrefix("--registry=") }
        let scopeFlags = arguments.filter { $0.hasPrefix("--@") && $0.contains(":registry=") }
        guard baseFlags == ["--registry=https://registry.npmjs.org/"],
              scopeFlags == ["--@openai:registry=https://registry.npmjs.org/"] else {
            note(["original": original, "guardRejected": true])
            return OperationCommandResult(stdout: Data(), stderr: Data("registry guard refused\n".utf8),
                stdoutTruncated: false, stderrTruncated: false, exitStatus: 126,
                processStarted: false, timedOut: false, cancelled: false, cleanupWarning: false)
        }
        let mapped = arguments.map { argument -> String in
            if argument.hasPrefix("--registry=") { return "--registry=\(loopback)" }
            if argument.hasPrefix("--@") && argument.contains(":registry=") {
                let scope = argument.split(separator: ":", maxSplits: 1).first.map(String.init) ?? "--"
                return "\(scope):registry=\(loopback)"
            }
            return argument
        }
        note(["original": original, "executed": [executablePath] + mapped])
        return await inner.run(executablePath: executablePath, arguments: mapped,
            environment: environment, currentDirectory: currentDirectory, timeout: timeout)
    }
}

final class PlainRecordRunner: OperationCommandRunner, @unchecked Sendable {
    let record: URL
    let inner = ProcessOperationCommandRunner()
    private let lock = NSLock()
    init(record: URL) { self.record = record }
    private func note(_ argv: [String]) {
        lock.lock()
        var data = (try? Data(contentsOf: record)) ?? Data()
        if !data.isEmpty { data.append(10) }
        data.append(try! JSONSerialization.data(withJSONObject: ["argv": argv],
            options: [.sortedKeys]))
        try? data.write(to: record)
        lock.unlock()
    }
    func run(executablePath: String, arguments: [String],
             environment: [String: String], currentDirectory: String,
             timeout: TimeInterval) async -> OperationCommandResult {
        note([executablePath] + arguments)
        return await inner.run(executablePath: executablePath, arguments: arguments,
            environment: environment, currentDirectory: currentDirectory, timeout: timeout)
    }
}

@main
struct CombinedHost {
    static func waitForFile(_ url: URL, timeout: TimeInterval = 20) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: url.path) { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return FileManager.default.fileExists(atPath: url.path)
    }

    static func main() async throws {
        let args = CommandLine.arguments
        let manager = args[1], prefix = args[2], root = args[3], alias = args[4]
        let loopback = args[5], updateRecordPath = args[6], uninstallRecordPath = args[7]
        let resultPath = args[8], operationBase = args[9]
        let updateStartedPath = args[10], interruptStartedPath = args[11]
        let interruptFlagPath = args[12]
        let updateStarted = URL(fileURLWithPath: updateStartedPath)
        let interruptStarted = URL(fileURLWithPath: interruptStartedPath)
        let interruptFlag = URL(fileURLWithPath: interruptFlagPath)
        let rawEnv = ProcessInfo.processInfo.environment
        let path = rawEnv["PATH"] ?? "/usr/bin:/bin"
        let entries = path.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        var raw: [String: String] = ["PATH": path]
        for key in ["HOME", "TMPDIR", "CFFIXED_USER_HOME", "ZDOTDIR",
                    "npm_config_cache", "npm_config_logs_dir", "npm_config_userconfig",
                    "npm_config_globalconfig"] {
            if let value = rawEnv[key] { raw[key] = value }
        }
        let environment = ShellEnvironment(shellPath: "/bin/zsh", pathEntries: entries,
            pathJoined: path, raw: raw, isDegraded: false)
        let definitionData = Data("""
        {"schemaVersion":2,"detectors":[{"id":"codex-id","displayName":"Codex","executableName":"codex","category":"aiAgent","packages":[{"manager":"npm","name":"@openai/codex"}],"acceptedOperations":["npmUpdate","npmUninstall"],"versionQuery":{"arguments":["--version"],"stream":"stdout","line":"first"}}]}
        """.utf8)
        let definition = try DetectorRegistry.validate(data: definitionData)[0]
        let scan: @Sendable () -> ToolPathDiagnostic = {
            PathDiagnosticsScanner.scan(detector: definition.makeDetector(),
                environment: environment, currentDirectory: root)
        }
        _ = manager
        _ = alias
        let updateRunner = CombinedUpdateRunner(prefix: prefix,
            root: prefix + "/lib/node_modules", latest: "2.0.0")
        let updateOperationRunner = LoopbackUpdateRunner(
            loopback: loopback, record: URL(fileURLWithPath: updateRecordPath))
        let uninstallOperationRunner = PlainRecordRunner(
            record: URL(fileURLWithPath: uninstallRecordPath))
        let gate = OperationExecutionGate()
        let baseURL = URL(fileURLWithPath: operationBase)

        let updatePrepared = await NpmUpdateOperation.prepare(
            definition: definition, diagnostic: scan(), environment: environment,
            currentDirectory: root, runner: updateRunner, operationRootBaseURL: baseURL)
        guard case .ready(let updatePreparation) = updatePrepared else {
            try Data("update preparation refused\n".utf8).write(to: URL(fileURLWithPath: resultPath))
            exit(2)
        }

        // Deliberate concurrent confirm: the first execution is already inside its launched
        // process (the wrapper writes its marker before exec) when the second attempt runs.
        let updateTask = Task {
            await NpmUpdateOperation.execute(
                confirmed: updatePreparation, environment: environment,
                scan: { _, _, _ in scan() },
                reconcileAfterLaunch: { _ in (scan(), environment) },
                updateRunner: updateRunner, operationRunner: updateOperationRunner, gate: gate)
        }
        let updateStartedObserved = await waitForFile(updateStarted)
        let competing = await NpmUpdateOperation.execute(
            confirmed: updatePreparation, environment: environment,
            scan: { _, _, _ in scan() },
            reconcileAfterLaunch: { _ in (scan(), environment) },
            updateRunner: updateRunner, operationRunner: updateOperationRunner, gate: gate)
        let updateOutcome = await updateTask.value
        let afterUpdate = scan()

        let uninstallPrepared = await NpmUninstallOperation.prepare(
            definition: definition, diagnostic: afterUpdate, environment: environment,
            currentDirectory: root, runner: updateRunner, operationRootBaseURL: baseURL)
        guard case .ready(let uninstallPreparation) = uninstallPrepared else {
            try Data("uninstall preparation refused\n".utf8).write(to: URL(fileURLWithPath: resultPath))
            exit(3)
        }

        // Window-close/interruption equivalent: cancel the in-flight operation after the wrapper
        // has launched and signalled; Core must reconcile and report .interrupted.
        try? Data().write(to: interruptFlag)
        let uninstallTask = Task {
            await NpmUninstallOperation.execute(
                confirmed: uninstallPreparation, environment: environment,
                scan: { _, _, _ in scan() },
                reconcileAfterLaunch: { _ in (scan(), environment) },
                updateRunner: updateRunner, operationRunner: uninstallOperationRunner, gate: gate)
        }
        let interruptStartedObserved = await waitForFile(interruptStarted)
        uninstallTask.cancel()
        let interrupted = await uninstallTask.value
        let afterInterrupt = scan()

        let finalPrepared = await NpmUninstallOperation.prepare(
            definition: definition, diagnostic: afterInterrupt, environment: environment,
            currentDirectory: root, runner: updateRunner, operationRootBaseURL: baseURL)
        guard case .ready(let finalPreparation) = finalPrepared else {
            try Data("final uninstall preparation refused\n".utf8).write(to: URL(fileURLWithPath: resultPath))
            exit(4)
        }
        let finalOutcome = await NpmUninstallOperation.execute(
            confirmed: finalPreparation, environment: environment,
            scan: { _, _, _ in scan() },
            reconcileAfterLaunch: { _ in (scan(), environment) },
            updateRunner: updateRunner, operationRunner: uninstallOperationRunner, gate: gate)

        let value: [String: Any] = [
            "updateState": updateOutcome.state.rawValue,
            "updateProcessStarted": updateOutcome.processStarted,
            "updateExit": updateOutcome.exitStatus as Any,
            "updateAfterVersion": updateOutcome.reconciliation?.afterVersion as Any,
            "updateStartedObserved": updateStartedObserved,
            "competingState": competing.state.rawValue,
            "competingProcessStarted": competing.processStarted,
            "competingCleanupWarnings": competing.cleanupWarnings,
            "competingMessage": competing.message as Any,
            "interruptedState": interrupted.state.rawValue,
            "interruptedProcessStarted": interrupted.processStarted,
            "interruptedReconciliationPresent": interrupted.reconciliation != nil,
            "interruptedAfterInstallState": interrupted.reconciliation?.afterInstallState.rawValue as Any,
            "interruptedMessage": interrupted.message as Any,
            "interruptStartedObserved": interruptStartedObserved,
            "uninstallState": finalOutcome.state.rawValue,
            "uninstallProcessStarted": finalOutcome.processStarted,
            "uninstallExit": finalOutcome.exitStatus as Any,
            "packageDirectoryAbsent": finalOutcome.reconciliation?.packageDirectoryAbsent as Any,
            "packageDirectoryReplaced": finalOutcome.reconciliation?.packageDirectoryReplaced as Any,
            "selectedTargetReleased": finalOutcome.reconciliation?.selectedTargetReleased as Any,
            "observationFailed": finalOutcome.reconciliation?.observationFailed as Any,
            "selectedEntryResidue": finalOutcome.reconciliation?.selectedEntryResidue as Any,
            "finalAfterInstallState": finalOutcome.reconciliation?.afterInstallState.rawValue as Any,
            "updateArguments": updatePreparation.preview.arguments,
            "uninstallArguments": finalPreparation.preview.arguments,
        ]
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: resultPath))
    }
}
'''


RENDER_HOST_SOURCE = r'''
import AppKit
import SwiftUI
import AgentLensCore
import Foundation

final class RenderNpmRunner: UpdateCommandRunner, @unchecked Sendable {
    let prefix: String
    let root: String
    init(prefix: String, root: String) { self.prefix = prefix; self.root = root }
    func run(executablePath: String, arguments: [String],
             environment: [String: String], timeout: TimeInterval) async -> CommandOutcome {
        if arguments.contains("prefix") { return .success(Data((prefix + "\n").utf8)) }
        if arguments.contains("root") { return .success(Data((root + "\n").utf8)) }
        return .failure(.spawnFailure)
    }
}

final class RenderRemovingRunner: OperationCommandRunner, @unchecked Sendable {
    let packageRoot: String
    let prefixBin: String
    init(packageRoot: String, prefixBin: String) {
        self.packageRoot = packageRoot; self.prefixBin = prefixBin
    }
    func run(executablePath: String, arguments: [String],
             environment: [String: String], currentDirectory: String,
             timeout: TimeInterval) async -> OperationCommandResult {
        try? FileManager.default.removeItem(atPath: packageRoot)
        try? FileManager.default.removeItem(atPath: prefixBin)
        return OperationCommandResult(stdout: Data("removed 1 package\n".utf8), stderr: Data(),
            stdoutTruncated: false, stderrTruncated: false, exitStatus: 0,
            processStarted: true, timedOut: false, cancelled: false, cleanupWarning: false)
    }
}

@MainActor
func render<V: View>(_ view: V, to url: URL) throws {
    let hosting = NSHostingView(rootView: view.frame(width: 760, height: 760))
    hosting.frame = NSRect(x: 0, y: 0, width: 760, height: 760)
    let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless],
        backing: .buffered, defer: false)
    window.contentView = hosting
    hosting.layoutSubtreeIfNeeded()
    window.displayIfNeeded()
    guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
        throw NSError(domain: "Render", code: 1)
    }
    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "Render", code: 2)
    }
    try png.write(to: url)
}

@main
struct RenderHost {
    static func main() async throws {
        let args = CommandLine.arguments
        let manager = args[1], prefix = args[2], root = args[3], alias = args[4], output = args[5]
        _ = manager
        _ = alias
        let rawEnv = ProcessInfo.processInfo.environment
        let path = rawEnv["PATH"] ?? "/usr/bin:/bin"
        let entries = path.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        var raw: [String: String] = ["PATH": path]
        for key in ["HOME", "TMPDIR", "CFFIXED_USER_HOME", "ZDOTDIR",
                    "npm_config_cache", "npm_config_logs_dir", "npm_config_userconfig",
                    "npm_config_globalconfig"] {
            if let value = rawEnv[key] { raw[key] = value }
        }
        let environment = ShellEnvironment(shellPath: "/bin/zsh", pathEntries: entries,
            pathJoined: path, raw: raw, isDegraded: false)
        let definitionData = Data("""
        {"schemaVersion":2,"detectors":[{"id":"codex-id","displayName":"Codex","executableName":"codex","category":"aiAgent","packages":[{"manager":"npm","name":"@openai/codex"}],"acceptedOperations":["npmUninstall"],"versionQuery":{"arguments":["--version"],"stream":"stdout","line":"first"}}]}
        """.utf8)
        let definition = try DetectorRegistry.validate(data: definitionData)[0]
        let scan = PathDiagnosticsScanner.scan(detector: definition.makeDetector(),
            environment: environment, currentDirectory: root)
        let baseURL = URL(fileURLWithPath: root).appendingPathComponent("operation-base")
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        let fake = RenderNpmRunner(prefix: prefix, root: prefix + "/lib/node_modules")
        let prepared = await NpmUninstallOperation.prepare(
            definition: definition, diagnostic: scan, environment: environment,
            currentDirectory: root, runner: fake, operationRootBaseURL: baseURL)
        guard case .ready(let preparation) = prepared else {
            try Data("prepare refused\n".utf8).write(to: URL(fileURLWithPath: output + "/status.txt"))
            exit(2)
        }
        _ = NSApplication.shared
        try await render(
            UninstallOperationView(preview: preparation.preview, outcome: nil, unavailable: nil,
                isExecuting: false, isCancelling: false, onConfirm: {}, onCancel: {}, onDismiss: {}),
            to: URL(fileURLWithPath: output + "/preview.png"))
        let outcome = await NpmUninstallOperation.execute(
            confirmed: preparation, environment: environment,
            scan: { _, env, cwd in
                PathDiagnosticsScanner.scan(detector: definition.makeDetector(),
                    environment: env, currentDirectory: cwd)
            },
            reconcileAfterLaunch: { _ in
                (PathDiagnosticsScanner.scan(detector: definition.makeDetector(),
                    environment: environment, currentDirectory: root), environment)
            },
            updateRunner: fake,
            operationRunner: RenderRemovingRunner(
                packageRoot: prefix + "/lib/node_modules/@openai/codex",
                prefixBin: prefix + "/bin/codex"),
            gate: OperationExecutionGate())
        try await render(
            UninstallOperationView(preview: nil, outcome: outcome, unavailable: nil,
                isExecuting: false, isCancelling: false, onConfirm: {}, onCancel: {}, onDismiss: {}),
            to: URL(fileURLWithPath: output + "/result.png"))
        let value: [String: Any] = [
            "state": outcome.state.rawValue,
            "packageDirectoryAbsent": outcome.reconciliation?.packageDirectoryAbsent as Any,
            "selectedTargetReleased": outcome.reconciliation?.selectedTargetReleased as Any,
            "selectedEntryResidue": outcome.reconciliation?.selectedEntryResidue as Any,
            "observationFailed": outcome.reconciliation?.observationFailed as Any,
            "previewArguments": preparation.preview.arguments,
        ]
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: output + "/render-result.json"))
    }
}
'''


def render(args) -> None:
    root = Path(args.root)
    base.owned_root(root)
    fixtures, old_tar, _new_tar = base.make_controlled_tarballs(root)
    npm, node_dir = base.npm_path()
    home = root / "home"; home.mkdir()
    env = base.synthetic_npm_env(root, home, node_dir)
    repo = Path(__file__).resolve().parents[3]
    profile = base.strict_profile(root, (Path(node_dir).parent, repo))
    sentinels = base.write_sentinels(root)
    server, base_url, requests, thread = base.start_registry()
    try:
        base.RegistryHandler.packument = base.build_packument(base_url)
        base.RegistryHandler.tarballs = {f"codex-{TARGET_OLD}.tgz": old_tar}
        prefix = root / "prefix"
        install = [npm, "install", f"{PACKAGE}@{TARGET_OLD}", "--global", "--prefix", str(prefix),
                   f"--registry={base_url}", f"--{PACKAGE.split('/')[0]}:registry={base_url}",
                   "--no-audit", "--no-fund", "--package-lock=false", "--no-save",
                   "--fetch-retries=0", "--fetch-timeout=30000"]
        if base.run(install, env, root, root / "receipts" / "install-old", profile=profile).returncode != 0:
            base.fail("render old npm install failed")
        manager_dir = root / "manager-bin"; manager_dir.mkdir()
        manager = manager_dir / "npm"; manager.symlink_to(npm)
        alias_dir = root / "alias-bin"; alias_dir.mkdir()
        alias = alias_dir / "codex"; alias.symlink_to(prefix / "bin/codex")
        output = root / "render"; output.mkdir()
        products = Path(args.products).resolve()
        product_dir = products if (products / "AgentLensCore.o").exists() else products / "out/Products/Debug"
        if not (product_dir / "AgentLensCore.o").exists():
            base.fail(f"AgentLensCore.o not found under {products}")
        source = root / "render-host.swift"; source.write_text(RENDER_HOST_SOURCE)
        view = repo / "Sources/AgentLensApp/UninstallOperationView.swift"
        host = root / "render-host"
        compile_result = base.run(
            base.compiler_argv(root, ["swiftc", "-parse-as-library", "-I", str(product_dir),
                                      str(source), str(view), str(product_dir / "AgentLensCore.o"),
                                      "-o", str(host)]),
            base.compiler_env(root), root, root / "receipts" / "render-compile",
            timeout=240, profile=profile)
        if compile_result.returncode != 0:
            base.fail("render host compilation failed")
        command_env = {**env, "PATH": f"{manager_dir}:{alias_dir}:{node_dir}:/usr/bin:/bin"}
        run_result = base.run(
            [str(host), str(manager), str(prefix), str(root), str(alias), str(output)],
            command_env, root, root / "receipts" / "render-host", timeout=300, profile=profile)
        if run_result.returncode != 0:
            base.fail("render host failed")
        result = json.loads((output / "render-result.json").read_text())
        if result.get("state") != "succeeded":
            base.fail(f"render operation did not succeed: {result}")
        for name in ["preview.png", "result.png"]:
            path = output / name
            if not path.exists() or path.stat().st_size < 10_000:
                base.fail(f"missing or empty render asset: {path}")
        sentinel_unchanged = base.sentinel_manifest(root / "sentinel") == sentinels
        if not sentinel_unchanged:
            base.fail("render sentinels changed")
        base.write_json(root / "render-summary.json", {
            "result": result,
            "previewBytes": (output / "preview.png").stat().st_size,
            "resultBytes": (output / "result.png").stat().st_size,
            "sentinelUnchanged": sentinel_unchanged,
        })
        print("RENDER OK")
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)
        if thread.is_alive():
            base.fail("render registry thread did not stop")


PUBLIC_HOST_SOURCE = r'''
import Foundation
import AgentLensCore
import AgentLensAppSupport

final class PublicRecordRunner: OperationCommandRunner, @unchecked Sendable {
    let record: URL
    let inner = ProcessOperationCommandRunner()
    private let lock = NSLock()
    init(record: URL) { self.record = record }
    private func note(_ argv: [String]) {
        lock.lock()
        var data = (try? Data(contentsOf: record)) ?? Data()
        if !data.isEmpty { data.append(10) }
        data.append(try! JSONSerialization.data(withJSONObject: ["argv": argv], options: [.sortedKeys]))
        try? data.write(to: record)
        lock.unlock()
    }
    func run(executablePath: String, arguments: [String], environment: [String: String],
             currentDirectory: String, timeout: TimeInterval) async -> OperationCommandResult {
        note([executablePath] + arguments)
        return await inner.run(executablePath: executablePath, arguments: arguments,
            environment: environment, currentDirectory: currentDirectory, timeout: timeout)
    }
}

@main
struct PublicHost {
    static func main() async throws {
        let args = CommandLine.arguments
        let registryPath = args[1], root = args[2], resultPath = args[3], recordPath = args[4]
        let rawEnv = ProcessInfo.processInfo.environment
        let path = rawEnv["PATH"] ?? "/usr/bin:/bin"
        let entries = path.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        var raw: [String: String] = ["PATH": path]
        for key in ["HOME", "TMPDIR", "CFFIXED_USER_HOME", "ZDOTDIR",
                    "npm_config_cache", "npm_config_logs_dir", "npm_config_userconfig",
                    "npm_config_globalconfig", "npm_config_prefix", "NPM_CONFIG_PREFIX"] {
            if let value = rawEnv[key] { raw[key] = value }
        }
        let environment = ShellEnvironment(shellPath: "/bin/zsh", pathEntries: entries,
            pathJoined: path, raw: raw, isDegraded: false)
        let all = try DetectorRegistry.validate(data: Data(contentsOf: URL(fileURLWithPath: registryPath)))
        guard let definition = all.first(where: { $0.id == "codex" }) else {
            try Data("missing codex definition\n".utf8).write(to: URL(fileURLWithPath: resultPath))
            exit(2)
        }
        let operationBase = URL(fileURLWithPath: root).appendingPathComponent("operation-base")
        try? FileManager.default.createDirectory(at: operationBase, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        let source = SessionEnvironmentSource(
            resolve: { environment }, loginShellPath: { "/bin/sh" },
            capture: { _ in ShellEnvironmentResolver.CaptureOutcome(dump: environment.raw, timedOut: false) },
            build: { _, _ in environment })
        let service = InventoryService(
            environment: SessionEnvironmentProvider(source: source),
            registry: { [definition] },
            scanner: { detector, env, cwd in
                PathDiagnosticsScanner.scan(detector: detector, environment: env, currentDirectory: cwd)
            },
            updateRunner: ProcessUpdateCommandRunner(),
            operationRunner: PublicRecordRunner(record: URL(fileURLWithPath: recordPath)),
            operationGate: OperationExecutionGate(),
            operationRootBaseURL: operationBase,
            updateCacheURL: URL(fileURLWithPath: root + "/update-cache.json"),
            npmScratchBaseURL: URL(fileURLWithPath: root + "/npm-scratch"),
            currentDirectory: root,
            clock: { Date() })
        let local = try await service.localSnapshot()
        guard let entry = local.entries.first(where: { $0.registryID == "codex" }),
              entry.installState != .notInstalled else {
            try Data("public Codex is not installed\n".utf8).write(to: URL(fileURLWithPath: resultPath))
            exit(3)
        }
        let ownership = await service.verifyingOwnership(of: entry)
        guard ownership.verifiedInstallation != nil else {
            let value: [String: Any] = ["state": "ownership-refused"]
            try JSONSerialization.data(withJSONObject: value).write(to: URL(fileURLWithPath: resultPath))
            exit(4)
        }
        let ownedEntry = InventoryEntry(definition: entry.definition, diagnostic: entry.diagnostic,
            update: entry.update, ownership: ownership)
        let prepared = await service.prepareUninstall(for: ownedEntry)
        guard case .ready(let preparation) = prepared else {
            var value: [String: Any] = ["state": "prepare-refused"]
            if case .unavailable(let reason) = prepared { value["reason"] = reason.rawValue }
            try JSONSerialization.data(withJSONObject: value).write(to: URL(fileURLWithPath: resultPath))
            exit(5)
        }
        let result = await service.executeUninstall(preparation)
        let value: [String: Any] = [
            "state": result.outcome.state.rawValue,
            "processStarted": result.outcome.processStarted,
            "exit": result.outcome.exitStatus as Any,
            "stdout": result.outcome.stdoutText,
            "stderr": result.outcome.stderrText,
            "packageDirectoryAbsent": result.outcome.reconciliation?.packageDirectoryAbsent as Any,
            "packageDirectoryReplaced": result.outcome.reconciliation?.packageDirectoryReplaced as Any,
            "selectedTargetReleased": result.outcome.reconciliation?.selectedTargetReleased as Any,
            "selectedEntryResidue": result.outcome.reconciliation?.selectedEntryResidue as Any,
            "observationFailed": result.outcome.reconciliation?.observationFailed as Any,
            "afterInstallState": result.snapshot?.entries.first?.installState.rawValue as Any,
            "previewArguments": preparation.preview.arguments,
        ]
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: resultPath))
    }
}
'''


def public_scenario(args) -> None:
    root = Path(args.root)
    fixture = json.loads((root / "public-fixture.json").read_text())
    prefix = Path(fixture["prefix"])
    if not (prefix / "bin/codex").exists():
        base.fail("public Codex is not installed in the fixture prefix")
    products = Path(args.products).resolve()
    product_dir = products if (products / "AgentLensCore.o").exists() else products / "out/Products/Debug"
    for name in ["AgentLensCore.o", "AgentLensAppSupport.o"]:
        if not (product_dir / name).exists():
            base.fail(f"{name} not found under {products}")
    repo = Path(__file__).resolve().parents[3]
    registry = root / "shipping-detectors.json"
    registry.write_bytes((repo / "Sources/AgentLensCore/Detectors/DefaultDetectors.json").read_bytes())
    source = root / "public-host.swift"
    source.write_text(PUBLIC_HOST_SOURCE)
    host = root / "public-host"
    profile = Path(fixture["profile"])
    compile_result = base.run(
        base.compiler_argv(root, ["swiftc", "-parse-as-library", "-I", str(product_dir),
                                  str(source), str(product_dir / "AgentLensCore.o"),
                                  str(product_dir / "AgentLensAppSupport.o"), "-o", str(host)]),
        base.compiler_env(root), root, root / "receipts" / "public-compile", timeout=240,
        profile=profile)
    if compile_result.returncode != 0:
        base.fail("public host compilation failed")
    env = {
        "HOME": fixture["home"],
        "ZDOTDIR": fixture["zdot"],
        "TMPDIR": str(root / "tmp"),
        "CFFIXED_USER_HOME": fixture["home"],
        "PATH": ":".join([str(prefix / "bin"), fixture["node_dir"], "/usr/bin", "/bin"]),
        "npm_config_prefix": str(prefix),
        "NPM_CONFIG_PREFIX": str(prefix),
        "npm_config_userconfig": str(root / "home/.npmrc"),
        "npm_config_globalconfig": str(root / "global.npmrc"),
        "npm_config_cache": str(root / "npm-cache"),
        "npm_config_logs_dir": str(root / "npm-logs"),
        "npm_config_update_notifier": "false",
        "npm_config_fund": "false",
        "npm_config_audit": "false",
    }
    result_path = root / "public-result.json"
    record_path = root / "public-argv.jsonl"
    run_result = base.run(
        [str(host), str(registry), str(root), str(result_path), str(record_path)],
        env, root, root / "receipts" / "public-host", timeout=300, profile=profile)
    if run_result.returncode != 0 or not result_path.exists():
        base.fail("public host failed")
    result = json.loads(result_path.read_text())
    if result.get("state") != "succeeded" or not result.get("processStarted"):
        base.fail(f"public uninstall did not succeed: {result}")
    if result.get("packageDirectoryAbsent") is not True or result.get("selectedTargetReleased") is not True:
        base.fail(f"public removal facts are incomplete: {result}")
    if result.get("observationFailed") is not False:
        base.fail(f"public observation failed: {result}")
    if (prefix / "bin/codex").exists():
        base.fail("public prefix bin still exists after uninstall")
    invocations = [json.loads(line) for line in record_path.read_text().splitlines() if line.strip()]
    if len(invocations) != 1:
        base.fail(f"public expected one uninstall invocation, got {len(invocations)}")
    argv = invocations[0]["argv"]
    for required in ["uninstall", PACKAGE, "--global", "--prefix",
                     "--registry=https://registry.npmjs.org/",
                     f"--{PACKAGE.split('/')[0]}:registry=https://registry.npmjs.org/"]:
        if required not in argv:
            base.fail(f"public uninstall missing argv item: {required}")
    base.write_json(root / "public-uninstall-summary.json", {
        "result": result,
        "argv": argv,
        "sentinelUnchanged": base.sentinel_manifest(root / "sentinel") == fixture["sentinels"],
    })
    if not base.sentinel_manifest(root / "sentinel") == fixture["sentinels"]:
        base.fail("public sentinels changed")
    print("PUBLIC-UNINSTALL OK")


def combined(args) -> None:
    root = Path(args.root)
    base.owned_root(root)
    fixtures, old_tar, new_tar = base.make_controlled_tarballs(root)
    npm, node_dir = base.npm_path()
    home = root / "home"; home.mkdir()
    env = base.synthetic_npm_env(root, home, node_dir)
    profile = base.strict_profile(root, (Path(node_dir).parent,))
    sentinels = base.write_sentinels(root)
    server, base_url, requests, thread = base.start_registry()
    try:
        base.RegistryHandler.packument = base.build_packument(base_url)
        base.RegistryHandler.tarballs = {
            f"codex-{TARGET_OLD}.tgz": old_tar,
            f"codex-{TARGET_NEW}.tgz": new_tar,
        }
        prefix = root / "prefix"
        install = [npm, "install", f"{PACKAGE}@{TARGET_OLD}", "--global", "--prefix", str(prefix),
                   f"--registry={base_url}", f"--{PACKAGE.split('/')[0]}:registry={base_url}",
                   "--no-audit", "--no-fund", "--package-lock=false", "--no-save",
                   "--fetch-retries=0", "--fetch-timeout=30000"]
        if base.run(install, env, root, root / "receipts" / "install-old", profile=profile).returncode != 0:
            base.fail("combined old npm install failed")
        package_root = prefix / "lib/node_modules" / PACKAGE
        prefix_bin = prefix / "bin/codex"
        if not package_root.exists() or not prefix_bin.exists():
            base.fail("npm did not create the old package/bin")
        manager_dir = root / "manager-bin"; manager_dir.mkdir()
        update_started = root / "update-started"
        interrupt_started = root / "interrupt-started"
        interrupt_flag = root / "interrupt-uninstall"
        manager = manager_dir / "npm"
        manager.write_text(
            "#!/bin/sh\n"
            'for arg in "$@"; do\n'
            '  if [ "$arg" = "install" ]; then\n'
            f'    printf \'%s\' "$$" > "{update_started}"\n'
            "    /bin/sleep 0.5\n"
            "    break\n"
            "  fi\n"
            '  if [ "$arg" = "uninstall" ]; then\n'
            f'    if [ -f "{interrupt_flag}" ]; then\n'
            f'      rm -f "{interrupt_flag}"\n'
            f'      printf \'%s\' "$$" > "{interrupt_started}"\n'
            "      /bin/sleep 30\n"
            "    fi\n"
            "    break\n"
            "  fi\n"
            "done\n"
            f'exec "{npm}" "$@"\n'
        )
        manager.chmod(0o755)
        alias_dir = root / "alias-bin"; alias_dir.mkdir()
        alias = alias_dir / "codex"; alias.symlink_to(prefix_bin)
        operation_base = root / "operation-base"; operation_base.mkdir(mode=0o700)

        products = Path(args.products).resolve()
        product_dir = products if (products / "AgentLensCore.o").exists() else products / "out/Products/Debug"
        if not (product_dir / "AgentLensCore.o").exists():
            base.fail(f"AgentLensCore.o not found under {products}")
        source = root / "combined-host.swift"; source.write_text(COMBINED_HOST_SOURCE)
        host = root / "combined-host"
        compile_result = base.run(
            base.compiler_argv(root, ["swiftc", "-parse-as-library", "-I", str(product_dir),
                                      str(source), str(product_dir / "AgentLensCore.o"), "-o", str(host)]),
            base.compiler_env(root), root, root / "receipts" / "compile", timeout=180,
            profile=profile)
        if compile_result.returncode != 0:
            base.fail("combined host compilation failed")

        update_record = root / "update-argv.jsonl"
        uninstall_record = root / "uninstall-argv.jsonl"
        result_path = root / "combined-result.json"
        command_env = {**env, "PATH": f"{manager_dir}:{alias_dir}:{node_dir}:/usr/bin:/bin"}
        host_result = base.run(
            [str(host), str(manager), str(prefix), str(root), str(alias), base_url,
             str(update_record), str(uninstall_record), str(result_path), str(operation_base),
             str(update_started), str(interrupt_started), str(interrupt_flag)],
            command_env, root, root / "receipts" / "combined-host", timeout=300, profile=profile)
        if host_result.returncode != 0 or not result_path.exists():
            base.fail("combined host failed")
        result = json.loads(result_path.read_text())
        if result.get("updateState") != "succeeded" or not result.get("updateProcessStarted"):
            base.fail(f"combined update did not succeed: {result}")
        if result.get("updateAfterVersion") != TARGET_NEW:
            base.fail(f"combined update did not reach {TARGET_NEW}: {result}")
        if not result.get("updateStartedObserved"):
            base.fail(f"combined concurrent-confirm update marker was not observed: {result}")
        if result.get("competingProcessStarted") is not False:
            base.fail(f"combined concurrent confirm launched a second process: {result}")
        if result.get("competingState") not in ("cancelled", "failed"):
            base.fail(f"combined concurrent confirm returned an unexpected state: {result}")
        if result.get("competingCleanupWarnings"):
            base.fail(f"combined concurrent confirm reported a cleanup warning: {result}")
        if result.get("interruptedState") != "interrupted":
            base.fail(f"combined window-close/interruption did not interrupt: {result}")
        if not result.get("interruptedProcessStarted"):
            base.fail(f"combined interruption did not start a process: {result}")
        if not result.get("interruptedReconciliationPresent"):
            base.fail(f"combined interruption did not reconcile: {result}")
        if result.get("interruptedAfterInstallState") != "installedAndOnPath":
            base.fail(f"combined interruption changed the install state: {result}")
        if not result.get("interruptStartedObserved"):
            base.fail(f"combined interruption marker was not observed: {result}")
        if interrupt_flag.exists():
            base.fail("combined interruption flag was not consumed")
        if result.get("uninstallState") != "succeeded":
            base.fail(f"combined uninstall did not succeed: {result}")
        if result.get("packageDirectoryAbsent") is not True or result.get("selectedTargetReleased") is not True:
            base.fail(f"combined uninstall removal facts are incomplete: {result}")
        if result.get("observationFailed") is not False:
            base.fail(f"combined uninstall observation failed: {result}")
        if result.get("selectedEntryResidue") is not True:
            base.fail(f"combined uninstall did not report the dangling residue: {result}")
        if result.get("finalAfterInstallState") != "notInstalled":
            base.fail(f"combined final scan did not report notInstalled: {result}")
        if package_root.exists() or prefix_bin.exists():
            base.fail("combined uninstall left the package or prefix bin")
        if base.sentinel_manifest(root / "sentinel") != sentinels:
            base.fail("combined sentinels changed")
        if list(operation_base.iterdir()):
            base.fail("combined operation base was not cleaned")
        update_invocations = [json.loads(line) for line in update_record.read_text().splitlines() if line.strip()]
        uninstall_invocations = [json.loads(line) for line in uninstall_record.read_text().splitlines() if line.strip()]
        if len(update_invocations) != 1 or len(uninstall_invocations) != 2:
            base.fail(
                "combined expected one update and two uninstall invocations "
                f"(interrupted + final), got {len(update_invocations)}/{len(uninstall_invocations)}")
        update_executed = update_invocations[0].get("executed", [])
        if not any(arg.startswith(f"--registry={base_url}") for arg in update_executed):
            base.fail("combined update did not use the controlled registry")
        for invocation in uninstall_invocations:
            uninstall_argv = invocation["argv"]
            for required in ["uninstall", PACKAGE, "--global", "--prefix"]:
                if required not in uninstall_argv:
                    base.fail(f"combined uninstall missing argv item: {required}")
        if any("uninstall" in request.lower() for request in requests):
            base.fail("combined uninstall unexpectedly used the registry")
        base.write_json(root / "combined-summary.json", {
            "result": result,
            "updateInvocations": update_invocations,
            "uninstallInvocations": uninstall_invocations,
            "sentinelUnchanged": True,
        })
        print("COMBINED-CONTROLLED OK")
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)
        if thread.is_alive():
            base.fail("combined registry thread did not stop")


def controlled(args) -> None:
    root = Path(args.root)
    base.owned_root(root)
    fixtures, old_tar, _new_tar = base.make_controlled_tarballs(root)
    npm, node_dir = base.npm_path()
    home = root / "home"
    home.mkdir()
    env = base.synthetic_npm_env(root, home, node_dir)
    profile = base.strict_profile(root, (Path(node_dir).parent,))
    sentinels = base.write_sentinels(root)
    server, base_url, requests, thread = base.start_registry()
    try:
        base.RegistryHandler.packument = base.build_packument(base_url)
        base.RegistryHandler.tarballs = {f"codex-{TARGET_OLD}.tgz": old_tar}
        prefix = root / "prefix"
        install = [npm, "install", f"{PACKAGE}@{TARGET_OLD}", "--global", "--prefix", str(prefix),
                   f"--registry={base_url}", f"--{PACKAGE.split('/')[0]}:registry={base_url}",
                   "--no-audit", "--no-fund", "--package-lock=false", "--no-save",
                   "--fetch-retries=0", "--fetch-timeout=30000"]
        proc = base.run(install, env, root, root / "receipts" / "install-old", profile=profile)
        if proc.returncode != 0:
            base.fail("controlled old npm install failed")
        package_root = prefix / "lib/node_modules" / PACKAGE
        prefix_bin = prefix / "bin/codex"
        if not package_root.exists() or not prefix_bin.exists():
            base.fail("npm did not create the old package/bin")
        manager_dir = root / "manager-bin"; manager_dir.mkdir()
        manager = manager_dir / "npm"; manager.symlink_to(npm)
        alias_dir = root / "alias-bin"; alias_dir.mkdir()
        alias = alias_dir / "codex"; alias.symlink_to(prefix_bin)
        operation_base = root / "operation-base"
        operation_base.mkdir(mode=0o700)

        products = Path(args.products).resolve()
        product_dir = products if (products / "AgentLensCore.o").exists() else products / "out/Products/Debug"
        if not (product_dir / "AgentLensCore.o").exists():
            base.fail(f"AgentLensCore.o not found under {products}")
        host_source = root / "uninstall-host.swift"
        host_source.write_text(HOST_SOURCE)
        host = root / "uninstall-host"
        compile_result = base.run(
            base.compiler_argv(root, ["swiftc", "-parse-as-library", "-I", str(product_dir),
                                      str(host_source), str(product_dir / "AgentLensCore.o"),
                                      "-o", str(host)]),
            base.compiler_env(root), root, root / "receipts" / "compile", timeout=180,
            profile=profile)
        if compile_result.returncode != 0:
            base.fail("uninstall host compilation failed")

        record = root / "argv.jsonl"
        result_path = root / "result.json"
        command_env = {**env, "PATH": f"{manager_dir}:{alias_dir}:{node_dir}:/usr/bin:/bin"}
        host_result = base.run(
            [str(host), str(manager), str(prefix), str(root), str(alias),
             str(result_path), str(record), str(operation_base)],
            command_env, root, root / "receipts" / "uninstall-host", timeout=180,
            profile=profile)
        if host_result.returncode != 0 or not result_path.exists():
            base.fail("uninstall host failed")
        result = json.loads(result_path.read_text())
        if result.get("state") != "succeeded" or not result.get("processStarted"):
            base.fail(f"uninstall did not succeed: {result}")
        if result.get("packageDirectoryAbsent") is not True:
            base.fail("package directory is still present after uninstall")
        if result.get("selectedTargetReleased") is not True:
            base.fail("selected target is still live after uninstall")
        if result.get("selectedEntryResidue") is not True:
            base.fail("dangling selected-entry residue was not reported")
        if result.get("observationFailed") is not False:
            base.fail("successful removal reported a failed observation")
        if result.get("afterInstallState") != "notInstalled":
            base.fail("fresh scan did not report notInstalled")
        if package_root.exists() or prefix_bin.exists():
            base.fail("the installed package or prefix bin survived uninstall")
        if base.sentinel_manifest(root / "sentinel") != sentinels:
            base.fail("unrelated sentinels changed during uninstall")
        if list(operation_base.iterdir()):
            base.fail("the owned operation base was not cleaned")
        invocations = [json.loads(line) for line in record.read_text().splitlines() if line.strip()]
        if len(invocations) != 1:
            base.fail(f"expected exactly one uninstall invocation, observed {len(invocations)}")
        argv = invocations[0]["argv"]
        for required in ["uninstall", PACKAGE, "--global", "--prefix",
                         "--registry=https://registry.npmjs.org/",
                         f"--{PACKAGE.split('/')[0]}:registry=https://registry.npmjs.org/"]:
            if required not in argv:
                base.fail(f"missing required uninstall argv item: {required}")
        prefix_argument = argv[argv.index("--prefix") + 1]
        if Path(prefix_argument).resolve() != prefix.resolve():
            base.fail(f"uninstall argv does not carry the verified prefix: {argv}")
        for forbidden in ["--force", "--ignore-scripts", "--dry-run", "prune", "update"]:
            if forbidden in argv:
                base.fail(f"forbidden uninstall argv item: {forbidden}")
        if any("uninstall" in request.lower() for request in requests):
            base.fail("uninstall unexpectedly used the controlled registry")
        base.write_json(root / "uninstall-summary.json", {
            "result": result,
            "argv": argv,
            "sentinelUnchanged": True,
            "registryRequests": list(requests),
        })
        print("UNINSTALL-CONTROLLED OK")
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)
        if thread.is_alive():
            base.fail("controlled registry thread did not stop")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--scenario", choices=["controlled", "combined", "public", "render"], required=True)
    parser.add_argument("--products", required=True)
    args = parser.parse_args()
    if args.scenario == "controlled":
        controlled(args)
    elif args.scenario == "combined":
        combined(args)
    elif args.scenario == "public":
        public_scenario(args)
    elif args.scenario == "render":
        render(args)


if __name__ == "__main__":
    main()
