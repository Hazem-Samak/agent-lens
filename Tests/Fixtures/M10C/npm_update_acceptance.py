#!/usr/bin/env python3
"""Secret-free M10-C npm update acceptance fixture.

Only the Python standard library is used. Every created path is beneath the operator-supplied
--root; the root must not pre-exist for prepare/controlled scenarios and is never deleted.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import plistlib
import re
import shlex
import shutil
import signal
import socket
import subprocess
import sys
import tarfile
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

PACKAGE = "@openai/codex"
TARGET_OLD = "1.0.0"
TARGET_NEW = "2.0.0"
PREFERRED_PUBLIC_OLD = "0.165.0"
STABLE_SEMVER = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")


def semver_key(value: str) -> tuple[int, int, int] | None:
    if not isinstance(value, str) or not STABLE_SEMVER.fullmatch(value):
        return None
    return tuple(int(part) for part in value.split("."))  # type: ignore[return-value]


def strictly_older(old: str, latest: str) -> bool:
    old_key, latest_key = semver_key(old), semver_key(latest)
    return old_key is not None and latest_key is not None and old_key < latest_key


def sandbox_quote(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def strict_profile(root: Path, allowed_reads: tuple[Path, ...] = ()) -> Path:
    """Deny all writes outside the owned root and deny all personal-home reads.

    The profile is generated from the current home and owned root, never a fixed user path.
    Reads of system frameworks remain allowed; explicitly supplied tool install roots are allowed
    because the fixture's node/npm executable lives there. The synthetic HOME/TMPDIR keeps the
    app's own state under the owned root.
    """
    real_home = str(Path.home().resolve())
    profile = root / "ordinary-app.sb"
    lines = [
        "(version 1)",
        "(allow default)",
        "(deny file-write*)",
        f'(allow file-write* (subpath "{sandbox_quote(str(root.resolve()))}"))',
        '(allow file-write* (literal "/dev/null"))',
        '(allow file-write* (literal "/dev/tty"))',
        f'(deny file-read* (subpath "{sandbox_quote(real_home)}"))',
        f'(deny file-write* (subpath "{sandbox_quote(real_home)}"))',
    ]
    for path in allowed_reads:
        lines.append(f'(allow file-read* (subpath "{sandbox_quote(str(path.resolve()))}"))')
        for ancestor in tuple(Path(path).resolve().parents) + (Path(path).resolve(),):
            if ancestor != Path(path).resolve() and ancestor != Path(real_home):
                lines.append(f'(allow file-read-metadata (literal "{sandbox_quote(str(ancestor))}"))')
    lines.append(f'(allow file-read-metadata (literal "{sandbox_quote(real_home)}"))')
    lines.append(f'(allow file-read-metadata (literal "{sandbox_quote(str(Path(real_home) / ".hermes"))}"))')
    profile.write_text("\n".join(dict.fromkeys(lines)) + "\n")
    return profile


def sentinel_manifest(sentinel: Path) -> list[dict]:
    entries = []
    for path in sorted(p for p in sentinel.rglob("*") if p.is_file()):
        stat = path.stat()
        entries.append({
            "path": str(path.relative_to(sentinel)),
            "sha256": sha256(path),
            "device": stat.st_dev,
            "inode": stat.st_ino,
            "mode": stat.st_mode,
            "size": stat.st_size,
            "mtime_ns": stat.st_mtime_ns,
        })
    return entries


def write_sentinels(root: Path) -> list[dict]:
    sentinel = root / "sentinel"
    package = sentinel / "unrelated-package"
    prefix = sentinel / "unrelated-prefix"
    (package / "bin").mkdir(parents=True, exist_ok=True)
    (prefix / "bin").mkdir(parents=True, exist_ok=True)
    (package / "package.json").write_text(json.dumps({
        "name": "unrelated-sentinel", "version": "9.9.9",
        "bin": {"unrelated-sentinel": "bin/tool"},
    }, sort_keys=True))
    (package / "bin/tool").write_text("#!/bin/sh\necho unrelated-fixture-package\n")
    os.chmod(package / "bin/tool", 0o755)
    (package / "marker.txt").write_text("unrelated fixture package sentinel\n")
    (prefix / "bin/unrelated-tool").write_text("#!/bin/sh\necho unrelated-fixture-prefix\n")
    os.chmod(prefix / "bin/unrelated-tool", 0o755)
    (prefix / "marker.txt").write_text("unrelated fixture prefix sentinel\n")
    return sentinel_manifest(sentinel)


def fail(message: str) -> "None":
    raise SystemExit("BLOCKED: " + message)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_json(path: Path, value) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def owned_root(root: Path) -> dict:
    if root.exists():
        fail(f"root already exists and is not adopted: {root}")
    root.mkdir(parents=True, mode=0o700)
    os.chmod(root, 0o700)
    stat = root.stat()
    record = {
        "root": str(root.resolve()),
        "owner_uid": os.getuid(),
        "device": stat.st_dev,
        "inode": stat.st_ino,
        "created": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    write_json(root / "ownership.json", record)
    return record


def require_owned_root(root: Path) -> dict:
    record_path = root / "ownership.json"
    if not record_path.exists():
        fail(f"missing ownership record: {record_path}")
    record = json.loads(record_path.read_text())
    stat = root.stat()
    if (record.get("owner_uid") != os.getuid()
            or record.get("device") != stat.st_dev
            or record.get("inode") != stat.st_ino):
        fail("root ownership identity does not match")
    return record


def run(argv, env, cwd: Path, receipt: Path, timeout: int = 300,
        profile: Path | None = None) -> subprocess.CompletedProcess:
    receipt.parent.mkdir(parents=True, exist_ok=True)
    actual_argv = list(argv)
    if profile is not None:
        actual_argv = ["/usr/bin/sandbox-exec", "-f", str(profile.resolve()), *actual_argv]
    started = time.time()
    with (receipt.with_suffix(".stdout")).open("wb") as out, (receipt.with_suffix(".stderr")).open("wb") as err:
        try:
            proc = subprocess.run(actual_argv, env=env, cwd=cwd, stdout=out, stderr=err, timeout=timeout)
        except subprocess.TimeoutExpired as exc:
            raise SystemExit(f"BLOCKED: timed out: {actual_argv}: {exc}") from exc
    write_json(receipt.with_suffix(".json"), {
        "argv": actual_argv, "original_argv": list(argv), "sandbox_profile": str(profile) if profile else None,
        "cwd": str(cwd), "start": started, "end": time.time(),
        "exit": proc.returncode, "stdout": str(receipt.with_suffix(".stdout")),
        "stderr": str(receipt.with_suffix(".stderr")),
    })
    return proc


def npm_path() -> tuple[str, str]:
    npm = shutil.which("npm")
    node = shutil.which("node")
    if not npm or not node:
        fail("npm or node is unavailable")
    return os.path.realpath(npm), os.path.dirname(os.path.realpath(node))


def synthetic_npm_env(root: Path, home: Path, node_dir: str) -> dict:
    env = {
        "HOME": str(home),
        "PATH": f"{node_dir}:/usr/bin:/bin",
        "TMPDIR": str(root / "tmp"),
        "CFFIXED_USER_HOME": str(home),
        "ZDOTDIR": str(root / "zdot"),
        "npm_config_cache": str(root / "npm-cache"),
        "npm_config_logs_dir": str(root / "npm-logs"),
        "npm_config_update_notifier": "false",
        "npm_config_userconfig": str(home / ".npmrc"),
        "npm_config_globalconfig": str(root / "global.npmrc"),
        "npm_config_fund": "false",
        "npm_config_audit": "false",
    }
    (root / "tmp").mkdir(exist_ok=True, mode=0o700)
    os.chmod(root / "tmp", 0o700)
    (root / "npm-cache").mkdir(exist_ok=True)
    (root / "npm-logs").mkdir(exist_ok=True)
    home.mkdir(parents=True, exist_ok=True)
    (home / ".npmrc").write_text("")
    (home / ".npmrc").chmod(0o600)
    (root / "global.npmrc").write_text("")
    (root / "global.npmrc").chmod(0o600)
    return env


def compiler_env(root: Path) -> dict:
    """Give every compiler invocation owned home/temp/module caches.

    The parent reproduction showed a bare env{PATH} compile is denied under a strict
    write envelope because the driver falls back to personal compiler caches. These
    paths are owned and the module-cache flag is explicit; no personal cache is used.
    """
    home = root / "compiler-home"
    cache = root / "clang-module-cache"
    home.mkdir(exist_ok=True, mode=0o700)
    cache.mkdir(exist_ok=True, mode=0o700)
    os.chmod(home, 0o700)
    os.chmod(cache, 0o700)
    return {
        "PATH": "/usr/bin:/bin",
        "HOME": str(home),
        "CFFIXED_USER_HOME": str(home),
        "TMPDIR": str(root / "tmp"),
        "CLANG_MODULE_CACHE_PATH": str(cache),
    }


def compiler_argv(root: Path, argv: list[str]) -> list[str]:
    return [*argv, "-module-cache-path", str(root / "clang-module-cache")]


def clean_env_command(argv: list[str], env: dict, cwd: Path | None = None) -> str:
    parts = ["/usr/bin/env", "-i"]
    parts.extend(f"{key}={env[key]}" for key in sorted(env))
    parts.extend(str(part) for part in argv)
    command = " ".join(shlex.quote(part) for part in parts)
    if cwd is not None:
        command = f"cd {shlex.quote(str(cwd))}\n" + command
    return command


def write_recipe(path: Path, header: list[str], body: str) -> None:
    path.write_text("#!/bin/sh\nset -eu\n" + "\n".join(header) + "\n" + body.rstrip() + "\n")
    path.chmod(0o700)



def write_rc(root: Path, prefix: Path, node_dir: str) -> tuple[Path, Path]:
    home = root / "home"
    zdot = root / "zdot"
    home.mkdir(parents=True, exist_ok=True)
    zdot.mkdir(parents=True, exist_ok=True)
    path = ":".join([str(prefix / "bin"), node_dir, "/usr/bin", "/bin"])
    payload = (
        f"export PATH='{path}'\n"
        f"export TMPDIR='{root / 'tmp'}'\n"
        f"export CFFIXED_USER_HOME='{home}'\n"
        f"export npm_config_prefix='{prefix}'\n"
        f"export NPM_CONFIG_PREFIX='{prefix}'\n"
    )
    (zdot / ".zshrc").write_text(payload)
    (home / ".bash_profile").write_text(payload)
    return home, zdot


def npm_view(npm: str, env: dict, cwd: Path, args: list[str], receipt: Path,
             profile: Path | None = None) -> str:
    proc = run([npm, *args], env, cwd, receipt, profile=profile)
    if proc.returncode != 0:
        fail(f"npm query failed: {args}; see {receipt}")
    return receipt.with_suffix(".stdout").read_text().strip()



def make_controlled_tarballs(root: Path) -> tuple[Path, Path, Path]:
    fixtures = root / "registry"
    fixtures.mkdir(parents=True, exist_ok=True)
    tarballs = {}
    for version in (TARGET_OLD, TARGET_NEW):
        stage = root / f"stage-{version}"
        pkg = stage / "package"
        (pkg / "bin").mkdir(parents=True, exist_ok=True)
        manifest = {
            "name": PACKAGE, "version": version,
            "bin": {"codex": "bin/codex"},
        }
        if version == TARGET_NEW:
            manifest["scripts"] = {"postinstall": "printf 'lifecycle-ok' > lifecycle-ok"}
            manifest["dependencies"] = {"@openai/codex-helper": "1.0.0"}
            manifest["bundledDependencies"] = ["@openai/codex-helper"]
            helper = pkg / "node_modules/@openai/codex-helper"
            helper.mkdir(parents=True, exist_ok=True)
            (helper / "package.json").write_text(json.dumps({
                "name": "@openai/codex-helper", "version": "1.0.0",
            }, sort_keys=True))
        (pkg / "package.json").write_text(json.dumps(manifest, sort_keys=True))
        codex = pkg / "bin/codex"
        codex.write_text(f"#!/bin/sh\necho 'codex-cli {version}'\n")
        os.chmod(codex, 0o755)
        tarball = fixtures / f"codex-{version}.tgz"
        with tarfile.open(tarball, "w:gz") as archive:
            archive.add(pkg, arcname="package")
        tarballs[version] = tarball
    return fixtures, tarballs[TARGET_OLD], tarballs[TARGET_NEW]


def make_scripted_tarball(root: Path, label: str, *, scripts=None, engines=None) -> Path:
    stage = root / f"failure-stage-{label}"
    pkg = stage / "package"
    (pkg / "bin").mkdir(parents=True, exist_ok=True)
    manifest = {"name": PACKAGE, "version": TARGET_NEW, "bin": {"codex": "bin/codex"}}
    if scripts:
        manifest["scripts"] = scripts
    if engines:
        manifest["engines"] = engines
    (pkg / "package.json").write_text(json.dumps(manifest, sort_keys=True))
    codex = pkg / "bin/codex"
    codex.write_text(f"#!/bin/sh\necho 'codex-cli {TARGET_NEW}'\n")
    os.chmod(codex, 0o755)
    tarball = root / "registry" / f"codex-2.0.0-{label}.tgz"
    with tarfile.open(tarball, "w:gz") as archive:
        archive.add(pkg, arcname="package")
    return tarball


class RegistryHandler(BaseHTTPRequestHandler):
    server_version = "AgentLensM10CFixture/1"
    packument = b""
    tarballs: dict[str, Path] = {}
    requests: list[str] = []

    def log_message(self, *_args):
        return

    def do_GET(self):
        RegistryHandler.requests.append(self.path)
        if self.path.endswith(".tgz"):
            path = RegistryHandler.tarballs.get(Path(self.path).name)
            if path is None:
                self.send_response(404); self.end_headers(); return
            data = path.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers(); self.wfile.write(data); return
        if "codex" in self.path.lower():
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(RegistryHandler.packument)))
            self.end_headers(); self.wfile.write(RegistryHandler.packument); return
        self.send_response(404); self.end_headers()


def start_registry(port: int = 0) -> tuple[ThreadingHTTPServer, str, list[str], threading.Thread]:
    server = ThreadingHTTPServer(("127.0.0.1", port), RegistryHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server, f"http://127.0.0.1:{server.server_port}/", RegistryHandler.requests, thread


def build_packument(base: str) -> bytes:
    versions = {}
    for version in (TARGET_OLD, TARGET_NEW, "3.0.0-beta.1"):
        tarball = f"{base}@openai/codex/-/codex-{version}.tgz"
        entry = {
            "name": PACKAGE, "version": version,
            "bin": {"codex": "bin/codex"},
            "dist": {"tarball": tarball},
        }
        if version == TARGET_NEW:
            entry["scripts"] = {"postinstall": "printf 'lifecycle-ok' > lifecycle-ok"}
            entry["dependencies"] = {"@openai/codex-helper": "1.0.0"}
            entry["bundledDependencies"] = ["@openai/codex-helper"]
        versions[version] = entry
    return json.dumps({
        "name": PACKAGE, "dist-tags": {"latest": TARGET_NEW, "next": "3.0.0-beta.1"},
        "versions": versions,
    }).encode()


HOST_SOURCE = r'''
import Foundation
import AgentLensCore

final class FakeUpdateRunner: UpdateCommandRunner, @unchecked Sendable {
    let prefix: String
    let root: String
    let target: String
    private let lock = NSLock()
    private var calls: [[String]] = []
    init(prefix: String, root: String, target: String) {
        self.prefix = prefix; self.root = root; self.target = target
    }
    var invocations: [[String]] { lock.lock(); defer { lock.unlock() }; return calls }
    func note(_ arguments: [String]) { lock.lock(); calls.append(arguments); lock.unlock() }
    func run(executablePath: String, arguments: [String],
             environment: [String: String], timeout: TimeInterval) async -> CommandOutcome {
        note(arguments)
        if arguments.contains("prefix") { return .success(Data((prefix + "\n").utf8)) }
        if arguments.contains("root") { return .success(Data((root + "\n").utf8)) }
        if arguments.contains("view") {
            let value = "{\"name\":\"@openai/codex\",\"version\":\"\(target)\",\"dist-tags.latest\":\"\(target)\"}"
            return .success(Data(value.utf8))
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

final class ControlledOperationRunner: OperationCommandRunner, @unchecked Sendable {
    let loopback: String
    let record: URL
    let prefix: String
    let permissionFailure: Bool
    let inner = ProcessOperationCommandRunner()
    private let lock = NSLock()
    init(loopback: String, record: URL, prefix: String, permissionFailure: Bool = false) {
        self.loopback = loopback; self.record = record; self.prefix = prefix
        self.permissionFailure = permissionFailure
    }
    func note(_ value: [String: Any]) {
        lock.lock(); defer { lock.unlock() }
        let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        var existing = (try? Data(contentsOf: record)) ?? Data()
        if !existing.isEmpty { existing.append(10) }
        existing.append(data)
        try? existing.write(to: record)
    }
    func run(executablePath: String, arguments: [String], environment: [String: String],
             currentDirectory: String, timeout: TimeInterval) async -> OperationCommandResult {
        note(["original": [executablePath] + arguments, "executed": NSNull()])
        let expectedBase = "--registry=https://registry.npmjs.org/"
        let expectedScope = "--@openai:registry=https://registry.npmjs.org/"
        let baseFlags = arguments.filter { $0.hasPrefix("--registry=") }
        let scopeFlags = arguments.filter { $0.hasPrefix("--@") && $0.contains(":registry=") }
        guard baseFlags == [expectedBase], scopeFlags == [expectedScope] else {
            note(["guardRejected": [executablePath] + arguments])
            return OperationCommandResult(stdout: Data(),
                stderr: Data("unreviewed registry transport; public base/scope was not preserved\n".utf8),
                stdoutTruncated: false, stderrTruncated: false, exitStatus: 126,
                processStarted: false, timedOut: false, cancelled: false, cleanupWarning: false)
        }
        let mapped = arguments.map { argument -> String in
            if argument.hasPrefix("--registry=") {
                return "--registry=\(loopback)"
            }
            if argument.hasPrefix("--@") && argument.contains(":registry=") {
                let scope = argument.split(separator: ":", maxSplits: 1).first.map(String.init) ?? "--"
                return "\(scope):registry=\(loopback)"
            }
            return argument
        }
        note(["original": NSNull(), "executed": [executablePath] + mapped])
        let protectedPaths = [prefix, prefix + "/lib", prefix + "/lib/node_modules", prefix + "/bin"]
        if permissionFailure {
            for path in protectedPaths { try? FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: path) }
        }
        defer {
            if permissionFailure {
                for path in protectedPaths { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path) }
            }
        }
        let result = await inner.run(executablePath: executablePath, arguments: mapped,
                                     environment: environment, currentDirectory: currentDirectory,
                                     timeout: timeout)
        return result
    }
}

final class ScanState: @unchecked Sendable {
    let definition: DetectorDefinition
    let environment: ShellEnvironment
    let currentDirectory: String
    private let lock = NSLock()
    private var count = 0
    init(definition: DetectorDefinition, environment: ShellEnvironment, currentDirectory: String) {
        self.definition = definition; self.environment = environment; self.currentDirectory = currentDirectory
    }
    func next() -> ToolPathDiagnostic {
        lock.lock(); count += 1; let _ = count; lock.unlock()
        return PathDiagnosticsScanner.scan(detector: definition.makeDetector(),
                                            environment: environment,
                                            currentDirectory: currentDirectory)
    }
}

@main
struct ControlledHost {
    static func main() async throws {
        let args = CommandLine.arguments
        let manager = args[1], prefix = args[2], root = args[3], alias = args[4]
        let target = args[5], loopback = args[6], record = args[7], resultPath = args[8]
        let operationRoot = args.count > 10 ? args[10] : root
        let permissionFailure = args.count > 9 && args[9] == "permission"
        let definitionData = Data("""
        {"schemaVersion":2,"detectors":[{"id":"codex-id","displayName":"Codex","executableName":"codex","category":"aiAgent","packages":[{"manager":"npm","name":"@openai/codex"}],"acceptedOperations":["npmUpdate"],"versionQuery":{"arguments":["--version"],"stream":"stdout","line":"first"}}]}
        """.utf8)
        let definition = try DetectorRegistry.validate(data: definitionData)[0]
        let aliasDir = (alias as NSString).deletingLastPathComponent
        let managerDir = (manager as NSString).deletingLastPathComponent
        let path = ProcessInfo.processInfo.environment["PATH"]
            ?? [aliasDir, managerDir, "/usr/bin", "/bin"].joined(separator: ":")
        let entries = path.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        var raw: [String: String] = ["HOME": ProcessInfo.processInfo.environment["HOME"] ?? "/tmp", "PATH": path]
        if let tmp = ProcessInfo.processInfo.environment["TMPDIR"] {
            raw["TMPDIR"] = tmp
        }
        if let engine = ProcessInfo.processInfo.environment["NPM_CONFIG_ENGINE_STRICT"] {
            raw["NPM_CONFIG_ENGINE_STRICT"] = engine
        }
        if let cache = ProcessInfo.processInfo.environment["NPM_CONFIG_CACHE"] {
            raw["NPM_CONFIG_CACHE"] = cache
        }
        let environment = ShellEnvironment(shellPath: "/bin/zsh",
            pathEntries: entries,
            pathJoined: path, raw: raw,
            isDegraded: false)
        let scan = ScanState(definition: definition, environment: environment,
                             currentDirectory: root)
        let updateRunner = FakeUpdateRunner(prefix: prefix, root: root + "/lib/node_modules", target: target)
        let controlled = ControlledOperationRunner(
            loopback: loopback, record: URL(fileURLWithPath: record), prefix: prefix,
            permissionFailure: permissionFailure)
        let base = operationRoot + "/operation-base"
        try FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        let prepared = await NpmUpdateOperation.prepare(
            definition: definition, diagnostic: scan.next(), environment: environment,
            currentDirectory: root, runner: updateRunner,
            operationRootBaseURL: URL(fileURLWithPath: base))
        guard case .ready(let preparation) = prepared else {
            if case .unavailable(let reason) = prepared {
                let value: [String: Any] = ["state": "unavailable", "reason": reason.rawValue]
                let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: URL(fileURLWithPath: resultPath))
            } else {
                try Data("preparation refused\n".utf8).write(to: URL(fileURLWithPath: resultPath))
            }
            exit(2)
        }
        let outcome = await NpmUpdateOperation.execute(
            confirmed: preparation, environment: environment,
            scan: { _, _, _ in scan.next() },
            reconcileAfterLaunch: { _ in (scan.next(), environment) },
            updateRunner: updateRunner,
            operationRunner: controlled, gate: OperationExecutionGate())
        let ownershipVerified: Any
        let ownershipReason: Any
        if let ownership = outcome.reconciliation?.ownership {
            switch ownership {
            case .verified:
                ownershipVerified = true; ownershipReason = NSNull()
            case .unknown(let reason):
                ownershipVerified = false; ownershipReason = String(describing: reason)
            }
        } else {
            ownershipVerified = false; ownershipReason = "no reconciliation"
        }
        let value: [String: Any] = [
            "state": outcome.state.rawValue,
            "processStarted": outcome.processStarted,
            "exit": outcome.exitStatus as Any,
            "stdout": outcome.stdoutText,
            "stderr": outcome.stderrText,
            "afterVersion": outcome.reconciliation?.afterVersion as Any,
            "versionMatchesTarget": outcome.reconciliation?.versionMatchesTarget as Any,
            "ownershipVerified": ownershipVerified,
            "ownershipReason": ownershipReason,
            "message": outcome.message as Any,
            "originalArguments": preparation.preview.arguments,
        ]
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: resultPath))
    }
}
'''


NATIVE_HOST_SOURCE = r'''
import AppKit
import SwiftUI
import AgentLensCore
import AgentLensAppSupport
import Foundation

final class NativeFakeUpdateRunner: UpdateCommandRunner, @unchecked Sendable {
    let prefix: String
    let root: String
    let target: String
    init(prefix: String, root: String, target: String) {
        self.prefix = prefix; self.root = root; self.target = target
    }
    func run(executablePath: String, arguments: [String], environment: [String: String], timeout: TimeInterval) async -> CommandOutcome {
        if arguments.contains("prefix") { return .success(Data((prefix + "\n").utf8)) }
        if arguments.contains("root") { return .success(Data((root + "\n").utf8)) }
        if arguments.contains("view") {
            return .success(Data("{\"name\":\"@openai/codex\",\"version\":\"\(target)\",\"dist-tags.latest\":\"\(target)\"}".utf8))
        }
        if arguments.contains("--version") { return .success(Data("10.9.8\n".utf8)) }
        if arguments.contains(where: { $0.hasSuffix(":registry") }) { return .success(Data("undefined\n".utf8)) }
        if arguments.contains("registry") { return .success(Data("https://registry.npmjs.org/\n".utf8)) }
        return .failure(.spawnFailure)
    }
}

final class NativeControlledRunner: OperationCommandRunner, @unchecked Sendable {
    let loopback: String
    let prefix: String
    let record: URL
    let delayScript: String?
    let inner = ProcessOperationCommandRunner()
    private let lock = NSLock()
    init(loopback: String, prefix: String, record: URL, delayScript: String? = nil) {
        self.loopback = loopback; self.prefix = prefix; self.record = record
        self.delayScript = delayScript
    }
    func run(executablePath: String, arguments: [String], environment: [String: String], currentDirectory: String, timeout: TimeInterval) async -> OperationCommandResult {
        lock.lock()
        let original = [executablePath] + arguments
        let expectedBase = "--registry=https://registry.npmjs.org/"
        let expectedScope = "--@openai:registry=https://registry.npmjs.org/"
        let baseFlags = arguments.filter { $0.hasPrefix("--registry=") }
        let scopeFlags = arguments.filter { $0.hasPrefix("--@") && $0.contains(":registry=") }
        guard baseFlags == [expectedBase], scopeFlags == [expectedScope] else {
            let rejected = try! JSONSerialization.data(withJSONObject: ["original": original,
                "guardRejected": original], options: [.sortedKeys])
            var existing = (try? Data(contentsOf: record)) ?? Data()
            if !existing.isEmpty { existing.append(10) }
            existing.append(rejected)
            try? existing.write(to: record)
            lock.unlock()
            return OperationCommandResult(stdout: Data(),
                stderr: Data("unreviewed registry transport; public base/scope was not preserved\n".utf8),
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
        let executed = [executablePath] + mapped
        let data = try! JSONSerialization.data(withJSONObject: ["original": original,
            "executed": executed, "registryGuard": "reviewed-public-base-and-scope"], options: [.sortedKeys])
        var existing = (try? Data(contentsOf: record)) ?? Data()
        if !existing.isEmpty { existing.append(10) }
        existing.append(data)
        try? existing.write(to: record)
        lock.unlock()
        return await inner.run(executablePath: delayScript ?? executablePath, arguments: mapped,
                               environment: environment, currentDirectory: currentDirectory,
                               timeout: timeout)
    }
}

func makeNativeService(manager: String, prefix: String, root: String, alias: String, target: String,
                       loopback: String, record: URL, home: String, nodeDir: String,
                       mode: String? = nil) throws -> InventoryService {
    let data = Data("""
    {"schemaVersion":2,"detectors":[{"id":"codex-id","displayName":"Codex","executableName":"codex","category":"aiAgent","packages":[{"manager":"npm","name":"@openai/codex"}],"acceptedOperations":["npmUpdate"],"versionQuery":{"arguments":["--version"],"stream":"stdout","line":"first"}}]}
    """.utf8)
    let definition = try DetectorRegistry.validate(data: data)[0]
    let aliasDir = (alias as NSString).deletingLastPathComponent
    let managerDir = (manager as NSString).deletingLastPathComponent
    let path = [aliasDir, managerDir, nodeDir, "/usr/bin", "/bin"].joined(separator: ":")
    let environment = ShellEnvironment(shellPath: "/bin/zsh",
        pathEntries: path.split(separator: ":", omittingEmptySubsequences: false).map(String.init),
        pathJoined: path, raw: [
            "HOME": home, "PATH": path, "TMPDIR": root + "/tmp",
            "CFFIXED_USER_HOME": home, "ZDOTDIR": root + "/zdot",
            "npm_config_userconfig": home + "/.npmrc",
            "npm_config_globalconfig": root + "/global.npmrc",
            "npm_config_cache": root + "/npm-cache",
            "npm_config_logs_dir": root + "/npm-logs",
            "npm_config_prefix": prefix, "NPM_CONFIG_PREFIX": prefix,
            "npm_config_update_notifier": "false",
            "npm_config_fund": "false", "npm_config_audit": "false"
        ], isDegraded: false)
    let source = SessionEnvironmentSource(
        resolve: { environment }, loginShellPath: { "/bin/sh" },
        capture: { _ in ShellEnvironmentResolver.CaptureOutcome(dump: environment.raw, timedOut: false) },
        build: { _, _ in environment })
    let operationBase = root + "/operation-base"
    try FileManager.default.createDirectory(atPath: operationBase, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
    let scratch = root + "/scratch"
    try FileManager.default.createDirectory(atPath: scratch, withIntermediateDirectories: true)
    var delayScript: String? = nil
    if mode == "delay" {
        let wrapper = root + "/delayed-npm"
        let script = "#!/bin/sh\ntrap '' TERM\nprintf '%s' \"$$\" > '"
            + root + "/delayed-child.pid'\nsleep 120\nexec '" + manager + "' \"$@\"\n"
        try Data(script.utf8).write(to: URL(fileURLWithPath: wrapper))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper)
        delayScript = wrapper
    }
    return InventoryService(
        environment: SessionEnvironmentProvider(source: source),
        registry: { [definition] },
        scanner: { detector, env, directory in
            PathDiagnosticsScanner.scan(detector: detector, environment: env, currentDirectory: directory)
        },
        updateRunner: NativeFakeUpdateRunner(prefix: prefix, root: prefix + "/lib/node_modules", target: target),
        operationRunner: NativeControlledRunner(
            loopback: loopback, prefix: prefix, record: record, delayScript: delayScript),
        operationGate: OperationExecutionGate(),
        operationRootBaseURL: URL(fileURLWithPath: operationBase),
        updateCacheURL: URL(fileURLWithPath: root + "/update-cache.json"),
        npmScratchBaseURL: URL(fileURLWithPath: scratch),
        currentDirectory: prefix,
        clock: { Date() })
}

final class NativeHostDelegate: AgentLensTerminationDelegate {
    let service: InventoryService
    let closeTrigger: String
    private var window: NSWindow?
    private var closeTask: Task<Void, Never>?
    init(service: InventoryService, closeTrigger: String) {
        self.service = service; self.closeTrigger = closeTrigger
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(contentRect: NSRect(x: 120, y: 120, width: 960, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Agent Lens M10C Controlled"
        window.contentView = NSHostingView(rootView: MainWindow(service: service))
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        closeTask = Task { [weak self] in
            while !Task.isCancelled {
                if FileManager.default.fileExists(atPath: self?.closeTrigger ?? "") {
                    await MainActor.run {
                        self?.window?.close()
                    }
                    break
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }
}

@main
enum NativeHostMain {
    static func main() {
        let args = CommandLine.arguments
        let service = try! makeNativeService(manager: args[1], prefix: args[2], root: args[3],
                                             alias: args[4], target: args[5], loopback: args[6],
                                             record: URL(fileURLWithPath: args[7]), home: args[8],
                                             nodeDir: args[9], mode: args.count > 10 ? args[10] : nil)
        let app = NSApplication.shared
        let delegate = NativeHostDelegate(service: service, closeTrigger: args[3] + "/close-trigger")
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}
'''


def run_controlled_failure(root: Path, host: Path, npm: str, node_dir: str, old_tar: Path,
                           profile: Path, label: str, loopback: str,
                           registry_base: str, env_extra: dict | None = None,
                           registry_empty: bool = False,
                           require_permission_error: bool = False) -> dict:
    """Run one real-npm failure in an owned prefix and return observed facts."""
    failure = root / f"failure-{label}"
    failure.mkdir(mode=0o700)
    prefix = root / "prefix"
    env = {**synthetic_npm_env(root, root / "home", node_dir)}
    manifest = prefix / "lib/node_modules" / PACKAGE / "package.json"
    current_old = False
    if manifest.exists():
        try:
            current_old = json.loads(manifest.read_text()).get("version") == TARGET_OLD
        except Exception:
            current_old = False
    if not current_old or not (prefix / "bin/codex").exists():
        if prefix.exists():
            shutil.rmtree(prefix)
        prefix.mkdir(mode=0o700)
        install = [npm, "install", f"{PACKAGE}@{TARGET_OLD}", "--global", "--prefix", str(prefix),
                   f"--registry={registry_base}", f"--{PACKAGE.split('/')[0]}:registry={registry_base}",
                   "--no-audit", "--no-fund", "--package-lock=false", "--no-save",
                   "--fetch-retries=0", "--fetch-timeout=30000"]
        proc = run(install, env, root, root / "receipts" / f"failure-{label}-install", profile=profile)
        if proc.returncode != 0:
            fail(f"failure fixture {label} could not install the old package")
    if not (prefix / "bin/codex").exists():
        fail(f"failure fixture {label}: npm did not create the old bin link")
    if registry_empty:
        RegistryHandler.packument = b""
    manager_dir = root / "manager-bin"; manager_dir.mkdir(exist_ok=True)
    manager = manager_dir / "npm"
    if not manager.exists():
        manager.symlink_to(npm)
    alias_dir = root / "alias-bin"; alias_dir.mkdir(exist_ok=True)
    alias = alias_dir / "codex"
    if not alias.exists():
        alias.symlink_to(prefix / "bin/codex")
    record = failure / "argv.jsonl"
    result_path = failure / "result.json"
    operation_scratch = root / "operation-scratch"
    if operation_scratch.exists():
        shutil.rmtree(operation_scratch)
    operation_scratch.mkdir(mode=0o700)
    host_root = prefix
    command_env = {**env, "PATH": f"{manager_dir}:{alias_dir}:{node_dir}:/usr/bin:/bin",
                   "NPM_CONFIG_CACHE": str(root / "ownership-cache-sentinel")}
    if env_extra:
        command_env.update(env_extra)
    result = None
    try:
        host_result = run(
            [str(host), str(manager), str(prefix), str(host_root), str(alias), TARGET_NEW,
             loopback, str(record), str(result_path)]
                + (["permission"] if label == "permission" else ["normal"])
                + [str(operation_scratch)],
            command_env, root, root / "receipts" / f"failure-{label}-host", timeout=180,
            profile=profile)
        if host_result.returncode != 0 or not result_path.exists():
            fail(f"failure fixture {label} host failed")
        result = json.loads(result_path.read_text())
    finally:
        for path in (prefix, prefix / "lib", prefix / "lib/node_modules", prefix / "bin"):
            if path.exists():
                os.chmod(path, 0o755)
    if result is None:
        fail(f"failure fixture {label} produced no result")
    if result.get("state") != "failed" or not result.get("processStarted"):
        fail(f"failure fixture {label} did not fail after a launched process: {result}")
    if result.get("exit") in (None, 0):
        fail(f"failure fixture {label} did not retain a nonzero exit: {result}")
    if result.get("versionMatchesTarget") is not False:
        fail(f"failure fixture {label} falsely matched target: {result}")
    if result.get("afterVersion") is None:
        fail(f"failure fixture {label} lost its measured after-state: {result}")
    if "stdout" not in result or "stderr" not in result:
        fail(f"failure fixture {label} lost a stream: {result}")
    if require_permission_error:
        stderr_text = result.get("stderr") or ""
        if not re.search(r"\b(EACCES|EPERM)\b", stderr_text):
            fail(f"failure fixture {label} did not report an actual EACCES/EPERM permission denial: {stderr_text!r}")
    invocations = [line for line in record.read_text().splitlines() if line.strip()] if record.exists() else []
    if len(invocations) != 2:
        fail(f"failure fixture {label} did not launch exactly one operation: {len(invocations)} records")
    result["operationInvocationCount"] = len(invocations)
    result["noRetry"] = len(invocations) == 2
    return result


def controlled(args) -> None:
    root = Path(args.root)
    ownership = owned_root(root)
    fixtures, old_tar, _new_tar = make_controlled_tarballs(root)
    npm, node_dir = npm_path()
    home = root / "home"; home.mkdir()
    env = synthetic_npm_env(root, home, node_dir)
    profile = strict_profile(root, (Path(node_dir).parent,))
    sentinels = write_sentinels(root)
    cache_sentinel = root / "ownership-cache-sentinel"
    cache_sentinel.mkdir(mode=0o700)
    server, base, requests, registry_thread = start_registry()
    try:
        RegistryHandler.packument = build_packument(base)
        RegistryHandler.tarballs = {
            f"codex-{TARGET_OLD}.tgz": old_tar,
            f"codex-{TARGET_NEW}.tgz": fixtures / f"codex-{TARGET_NEW}.tgz",
        }
        prefix = root / "prefix"
        operation_scratch = root / "operation-scratch"
        operation_scratch.mkdir(mode=0o700)
        install = [npm, "install", f"{PACKAGE}@{TARGET_OLD}", "--global", "--prefix", str(prefix),
                   f"--registry={base}", f"--{PACKAGE.split('/')[0]}:registry={base}",
                   "--no-audit", "--no-fund", "--package-lock=false", "--no-save",
                   "--fetch-retries=0", "--fetch-timeout=30000"]
        proc = run(install, env, root, root / "receipts" / "controlled-install-old", profile=profile)
        if proc.returncode != 0:
            fail("controlled old npm install failed")
        if not (prefix / "bin/codex").exists():
            fail("npm did not create the controlled old bin link")
        alias_dir = root / "alias-bin"; alias_dir.mkdir()
        alias = alias_dir / "codex"
        target = prefix / "bin/codex"
        alias.symlink_to(target)
        manager_dir = root / "manager-bin"; manager_dir.mkdir()
        manager = manager_dir / "npm"
        manager.symlink_to(npm)
        host_source = root / "controlled-host.swift"
        host_source.write_text(HOST_SOURCE)
        products = Path(args.products).resolve()
        product_dir = products if (products / "AgentLensCore.o").exists() else products / "out/Products/Debug"
        object_file = product_dir / "AgentLensCore.o"
        if not object_file.exists():
            fail(f"AgentLensCore.o not found under {products}")
        host = root / "controlled-host"
        compile_result = run(
            compiler_argv(root, ["swiftc", "-parse-as-library", "-I", str(product_dir), str(host_source), str(object_file), "-o", str(host)]),
            compiler_env(root), root, root / "receipts" / "controlled-compile", timeout=180,
            profile=profile)
        if compile_result.returncode != 0:
            fail("controlled host compilation failed")
        result_path = root / "controlled-result.json"
        record_path = root / "controlled-argv.jsonl"
        failures = {}

        def reset_packument(tarballs, *, scripts=None, engines=None):
            document = json.loads(build_packument(base))
            if scripts:
                document["versions"][TARGET_NEW]["scripts"] = scripts
                document["versions"][TARGET_NEW].pop("dependencies", None)
                document["versions"][TARGET_NEW].pop("bundledDependencies", None)
            if engines:
                document["versions"][TARGET_NEW]["engines"] = engines
                document["versions"][TARGET_NEW].pop("dependencies", None)
                document["versions"][TARGET_NEW].pop("bundledDependencies", None)
            RegistryHandler.packument = json.dumps(document).encode()
            RegistryHandler.tarballs = tarballs

        reset_packument({f"codex-{TARGET_OLD}.tgz": old_tar})
        failures["tarball"] = run_controlled_failure(
            root, host, npm, node_dir, old_tar, profile, "tarball", base, base)

        reset_packument({f"codex-{TARGET_OLD}.tgz": old_tar})
        failures["registry"] = run_controlled_failure(
            root, host, npm, node_dir, old_tar, profile, "registry", base, base,
            registry_empty=True)

        failures["network"] = run_controlled_failure(
            root, host, npm, node_dir, old_tar, profile, "network", "http://127.0.0.1:1/", base)

        reset_packument({f"codex-{TARGET_OLD}.tgz": old_tar,
                        f"codex-{TARGET_NEW}.tgz": fixtures / f"codex-{TARGET_NEW}.tgz"})
        failures["permission"] = run_controlled_failure(
            root, host, npm, node_dir, old_tar, profile, "permission", base, base,
            require_permission_error=True)

        lifecycle_tar = make_scripted_tarball(root, "lifecycle", scripts={"preinstall": "exit 9"})
        reset_packument({f"codex-{TARGET_OLD}.tgz": old_tar, "codex-2.0.0.tgz": lifecycle_tar},
                        scripts={"preinstall": "exit 9"})
        failures["lifecycle"] = run_controlled_failure(
            root, host, npm, node_dir, old_tar, profile, "lifecycle", base, base)

        engine_tar = make_scripted_tarball(root, "engine", engines={"node": ">=99.0.0"})
        reset_packument({f"codex-{TARGET_OLD}.tgz": old_tar, "codex-2.0.0.tgz": engine_tar},
                        engines={"node": ">=99.0.0"})
        failures["engine"] = run_controlled_failure(
            root, host, npm, node_dir, old_tar, profile, "engine", base, base,
            env_extra={"NPM_CONFIG_ENGINE_STRICT": "1"})

        if sentinel_manifest(root / "sentinel") != sentinels:
            fail("unrelated controlled sentinel changed during failure scenarios")
        for failure in failures.values():
            failure["sentinelUnchanged"] = True
            failure["sentinelManifest"] = sentinels
        write_json(root / "controlled-failures.json", failures)
        if operation_scratch.exists():
            shutil.rmtree(operation_scratch)
        operation_scratch.mkdir(mode=0o700)
        reset_packument({
            f"codex-{TARGET_OLD}.tgz": old_tar,
            f"codex-{TARGET_NEW}.tgz": fixtures / f"codex-{TARGET_NEW}.tgz",
        })
        host_result = run(
            [str(host), str(manager), str(prefix), str(prefix),
             str(alias), TARGET_NEW, base, str(record_path), str(result_path), "normal", str(operation_scratch)],
            {**env, "PATH": f"{manager_dir}:{alias_dir}:{node_dir}:/usr/bin:/bin",
             "NPM_CONFIG_CACHE": str(cache_sentinel)},
            root, root / "receipts" / "controlled-host", timeout=180, profile=profile)
        if host_result.returncode != 0:
            fail("controlled host failed")
        result = json.loads(result_path.read_text())
        if result.get("state") != "succeeded":
            fail(f"controlled operation did not succeed: {result}")
        if result.get("ownershipVerified") is not True:
            fail(f"controlled success did not expose verified ownership: {result}")
        installed_package = prefix / "lib/node_modules" / PACKAGE
        if not (prefix / "bin/codex").exists():
            fail("npm did not create the installed package bin link")
        if not (installed_package / "lifecycle-ok").exists():
            fail("the harmless lifecycle fixture did not run inside the owned prefix")
        if not (installed_package / "node_modules/@openai/codex-helper/package.json").exists():
            fail("the bundled dependency fixture is missing after npm install")
        if list(cache_sentinel.iterdir()):
            fail("passing operation wrote into the captured shared npm cache sentinel")

        native_prefix = root / "native-prefix"
        native_prefix.mkdir(mode=0o700)
        native_install = [npm, "install", f"{PACKAGE}@{TARGET_OLD}", "--global",
                          "--prefix", str(native_prefix),
                          f"--registry={base}", f"--{PACKAGE.split('/')[0]}:registry={base}",
                          "--no-audit", "--no-fund", "--package-lock=false", "--no-save",
                          "--fetch-retries=0", "--fetch-timeout=30000"]
        native_install_result = run(native_install, env, root,
                                    root / "receipts" / "controlled-native-install-old",
                                    profile=profile)
        if native_install_result.returncode != 0:
            fail("real npm could not seed the distinct native old prefix")
        native_manifest = native_prefix / "lib/node_modules" / PACKAGE / "package.json"
        native_version = json.loads(native_manifest.read_text()).get("version")
        if native_version != TARGET_OLD:
            fail(f"native prefix was not seeded at the real old version: {native_version}")
        native_bin = native_prefix / "bin/codex"
        if not native_bin.exists() or native_bin.is_symlink() and not native_bin.resolve().exists():
            fail("real npm did not create the native old prefix bin link")
        native_alias_dir = root / "native-alias-bin"
        native_alias_dir.mkdir()
        native_alias = native_alias_dir / "codex"
        native_alias.symlink_to(native_bin)
        native_seed = {
            "prefix": str(native_prefix),
            "version": native_version,
            "bin": str(native_bin),
            "bin_inode": os.lstat(native_bin).st_ino,
            "bin_target": str(native_bin.resolve()),
            "alias": str(native_alias),
            "alias_target": str(native_alias.resolve()),
            "install_receipt": str(root / "receipts" / "controlled-native-install-old.json"),
            "npm_created_bin": True,
        }
        (root / "native-seed.json").write_text(json.dumps(native_seed, indent=2, sort_keys=True) + "\n")

        (root / "controlled-requests.json").write_text(json.dumps(requests, indent=2))
        native_recipe = build_native_host(root, product_dir, env, node_dir,
                                          native_prefix, native_alias, native_seed)
        print(f"CONTROLLED-CORE OK root={root} native_recipe={native_recipe}")
    finally:
        server.shutdown()
        server.server_close()
        registry_thread.join(timeout=5)
        write_json(root / "registry-receipt.json", {
            "server_pid": os.getpid(), "base": base, "stopped": True,
            "thread_alive_after_join": registry_thread.is_alive(),
        })
        if registry_thread.is_alive():
            fail("loopback registry thread did not join")
    print(f"CONTROLLED OK root={root}")


def build_native_host(root: Path, product_dir: Path, env: dict, node_dir: str,
                      native_prefix: Path, native_alias: Path, native_seed: dict) -> Path:
    ownership = json.loads((root / "ownership.json").read_text())
    """Build a reproducible AppKit host around the shipping SwiftUI views.

    This is intentionally outside the production module: it injects the owned service, fake update
    metadata, and loopback operation transport. The fixture writes the source and app bundle beneath
    the owned root, so the native recipe is not an ad-hoc external artifact. The recipe is exposed for
    the native journey; fixture-controlled automated native interaction remains the caller's job.
    """
    core_object = product_dir / "AgentLensCore.o"
    support_object = product_dir / "AgentLensAppSupport.o"
    if not core_object.exists() or not support_object.exists():
        fail(f"product objects missing under {product_dir}")
    repo = Path(__file__).resolve().parents[3]
    shipping = [
        repo / "Sources/AgentLensApp/MainWindow.swift",
        repo / "Sources/AgentLensApp/ToolDetailView.swift",
        repo / "Sources/AgentLensApp/ToolListView.swift",
        repo / "Sources/AgentLensApp/DiagnosticsView.swift",
        repo / "Sources/AgentLensApp/OwnershipVerificationView.swift",
        repo / "Sources/AgentLensApp/PathActions.swift",
        repo / "Sources/AgentLensApp/UpdateOperationView.swift",
    ]
    missing = [str(path) for path in shipping if not path.exists()]
    if missing:
        fail(f"shipping view source missing: {missing}")
    native_source = root / "controlled-native-host.swift"
    native_source.write_text(NATIVE_HOST_SOURCE)
    app = root / "ControlledNative.app"
    binary = app / "Contents/MacOS/ControlledNative"
    binary.parent.mkdir(parents=True, exist_ok=True)
    (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
        "CFBundleDevelopmentRegion": "en",
        "CFBundleExecutable": "ControlledNative",
        "CFBundleIdentifier": "com.agentlens.m10c.controlled-native",
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": "Agent Lens M10C Controlled",
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": "0.1.0",
        "CFBundleVersion": "1",
        "LSMinimumSystemVersion": "14.0",
        "NSHighResolutionCapable": True,
    }))
    compile_argv = compiler_argv(root, ["swiftc", "-parse-as-library", "-I", str(product_dir), "-o", str(binary),
                    str(native_source), *[str(path) for path in shipping],
                    str(core_object), str(support_object)])
    profile = strict_profile(root, (Path(node_dir).parent, repo))
    compiled = run(compile_argv, compiler_env(root), root,
                   root / "receipts" / "controlled-native-compile", timeout=240,
                   profile=profile)
    if compiled.returncode != 0:
        fail("controlled native host compilation failed")
    recipe = root / "controlled-native-recipe.txt"
    native_path = ":".join([str(root / "manager-bin"), str(native_alias.parent), node_dir, "/usr/bin", "/bin"])
    native_env = {
        **env,
        "HOME": str(root / "home"),
        "ZDOTDIR": str(root / "zdot"),
        "TMPDIR": str(root / "tmp"),
        "CFFIXED_USER_HOME": str(root / "home"),
        "PATH": native_path,
        "npm_config_prefix": str(native_prefix),
        "NPM_CONFIG_PREFIX": str(native_prefix),
    }
    launch = [
        "/usr/bin/sandbox-exec", "-f", str(profile),
        str(binary),
        str(root / "manager-bin/npm"),
        str(native_prefix),
        str(root),
        str(native_alias),
        TARGET_NEW,
        "http://127.0.0.1:59933/",
        str(root / "controlled-native-argv.jsonl"),
        str(root / "home"),
        node_dir,
    ]
    fixture = str(Path(__file__).resolve())
    registry = clean_env_command([sys.executable, fixture, "--root", str(root), "--scenario", "serve-native"], native_env)
    stop = clean_env_command([sys.executable, fixture, "--root", str(root), "--scenario", "stop-native"], native_env)

    def script(launch_args: list[str], close_mode: bool) -> str:
        extra = "# Launch, assert the delayed child, then create root/close-trigger.\n" if close_mode else ""
        return (
            "rm -f native-registry.json native-base.txt controlled-native-argv.jsonl close-trigger\n"
            f"{registry} &\n"
            "registry_pid=$!\n"
            f"cleanup() {{ {stop} >/dev/null 2>&1 || true; }}\n"
            "trap cleanup EXIT INT TERM\n"
            "i=0\n"
            "while [ ! -s native-base.txt ]; do\n"
            "  i=$((i + 1))\n"
            "  if [ \"$i\" -gt 100 ]; then echo 'native registry did not start' >&2; exit 1; fi\n"
            "  sleep 0.1\n"
            "done\n"
            + extra
            + clean_env_command(launch_args, native_env) + "\n"
        )

    write_recipe(recipe, [f"cd {shlex.quote(str(root))}"], script(launch, False))
    close_recipe = root / "controlled-native-close-recipe.txt"
    write_recipe(close_recipe, [f"cd {shlex.quote(str(root))}"], script(launch + ["delay"], True))
    write_json(root / "controlled-native.json", {
        "source": str(native_source),
        "source_sha256": sha256(native_source),
        "app": str(app),
        "app_sha256": sha256(binary),
        "recipe": str(recipe),
        "recipe_sha256": sha256(recipe),
        "close_recipe": str(close_recipe),
        "close_recipe_sha256": sha256(close_recipe),
        "profile": str(profile),
        "profile_sha256": sha256(profile),
        "ownership": ownership,
        "native_seed": native_seed,
        "native_prefix": str(native_prefix),
        "native_alias": str(native_alias),
        "native_prefix_version": native_seed["version"],
        "native_prefix_bin_inode": native_seed["bin_inode"],
        "shipping_sources": [str(path) for path in shipping],
        "compile_argv": compile_argv,
        "compile_env": compiler_env(root),
        "compile_profile": str(profile),
        "transport_guard": "reviewed-public-base-and-scope",
    })
    return recipe


def serve_native(args) -> None:
    root = Path(args.root)
    require_owned_root(root)
    try:
        server, base, _requests, registry_thread = start_registry(port=59933)
    except OSError as exc:
        fail(f"native registry endpoint 59933 is unavailable; no process was killed: {exc}")
    RegistryHandler.packument = build_packument(base)
    RegistryHandler.tarballs = {
        f"codex-{TARGET_OLD}.tgz": root / "registry" / f"codex-{TARGET_OLD}.tgz",
        f"codex-{TARGET_NEW}.tgz": root / "registry" / f"codex-{TARGET_NEW}.tgz",
    }
    write_json(root / "native-registry.json", {
        "server_pid": os.getpid(), "base": base, "started": True,
    })
    (root / "native-base.txt").write_text(base + "\n")
    print(f"NATIVE-REGISTRY {base} root={root}", flush=True)
    def stop(_signum, _frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, stop)
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        pass
    finally:
        server.shutdown()
        server.server_close()
        registry_thread.join(timeout=5)
        write_json(root / "native-registry.json", {
            "server_pid": os.getpid(), "base": base, "stopped": True,
            "thread_alive_after_join": registry_thread.is_alive(),
        })
        if registry_thread.is_alive():
            fail("native registry thread did not join")


def stop_native(args) -> None:
    root = Path(args.root)
    require_owned_root(root)
    record_path = root / "native-registry.json"
    if not record_path.exists():
        fail("native registry receipt is missing")
    record = json.loads(record_path.read_text())
    pid = record.get("server_pid")
    if not isinstance(pid, int) or pid <= 1:
        fail("native registry PID is not recorded")
    command = subprocess.run(["ps", "-p", str(pid), "-o", "command="],
                             capture_output=True, text=True).stdout
    if "npm_update_acceptance.py" not in command or str(root) not in command:
        fail("recorded native registry PID identity does not match this owned root")
    os.kill(pid, signal.SIGTERM)
    deadline = time.time() + 5
    while time.time() < deadline:
        try:
            updated = json.loads(record_path.read_text())
        except Exception:
            updated = {}
        if updated.get("stopped") is True and updated.get("thread_alive_after_join") is False:
            print(f"STOP-NATIVE OK pid={pid} root={root}")
            return
        time.sleep(0.1)
    fail("recorded native registry did not stop/join within the bounded wait")


def record_native(args) -> None:
    root = Path(args.root)
    ownership = require_owned_root(root)
    seed = json.loads((root / "native-seed.json").read_text())
    manifest = root / "native-prefix/lib/node_modules" / PACKAGE / "package.json"
    version = json.loads(manifest.read_text()).get("version")
    if version != TARGET_NEW:
        fail(f"native operation did not reach the target version: {version}")
    registry = json.loads((root / "native-registry.json").read_text())
    if registry.get("stopped") is not True or registry.get("thread_alive_after_join") is not False:
        fail("native registry was not stopped/joined before recording the result")
    argv_path = root / "controlled-native-argv.jsonl"
    records = [json.loads(line) for line in argv_path.read_text().splitlines() if line.strip()]
    if not records:
        fail("native operation argv receipt is missing")
    for record in records:
        original = record.get("original", [])
        executed = record.get("executed", [])
        if "--registry=https://registry.npmjs.org/" not in original:
            fail("native original argv did not preserve the public base registry")
        if "--@openai:registry=https://registry.npmjs.org/" not in original:
            fail("native original argv did not preserve the public scoped registry")
        if not any(arg.startswith("--registry=http://127.0.0.1:59933/") for arg in executed):
            fail("native transport did not map the base registry to the owned loopback")
        if "registryGuard" not in record:
            fail("native transport guard receipt is missing")
    operation_base = root / "operation-base"
    leftovers = [str(path) for path in operation_base.iterdir()] if operation_base.exists() else []
    if leftovers:
        fail(f"native operation scratch was not released: {leftovers}")
    receipt = {
        "state": "succeeded",
        "afterVersion": version,
        "targetVersion": TARGET_NEW,
        "ownership": ownership,
        "nativeSeed": seed,
        "registry": registry,
        "argv": records,
        "operationBaseEmpty": True,
        "nativePrefixManifest": str(manifest),
        "note": "Native UI reconciliation received the target after-state; Core result schema separately records ownershipVerified. This receipt records the owning root and real npm-created native seed.",
    }
    write_json(root / "native-result.json", receipt)
    print(f"RECORD-NATIVE OK root={root} version={version} registry_stopped=yes")


def prepare_public(args) -> None:
    root = Path(args.root)
    ownership = owned_root(root)
    npm, node_dir = npm_path()
    home = root / "home"; home.mkdir()
    env = synthetic_npm_env(root, home, node_dir)
    app = str(Path(args.app).resolve())
    profile = strict_profile(root, (Path(node_dir).parent, Path(app), Path(args.cli).resolve()))
    latest = npm_view(npm, env, root, ["view", PACKAGE, "dist-tags.latest", "--json"],
                      root / "receipts" / "public-latest", profile=profile)
    try:
        latest_value = json.loads(latest)
    except Exception:
        fail(f"public latest query was not JSON: {latest!r}")
    if not isinstance(latest_value, str):
        fail(f"public latest query was not a string: {latest_value!r}")
    latest_text = latest_value.strip()
    if semver_key(latest_text) is None:
        fail(f"public latest is not a stable semantic version: {latest_text!r}")
    versions_text = npm_view(npm, env, root, ["view", PACKAGE, "versions", "--json"],
                             root / "receipts" / "public-versions", profile=profile)
    versions = json.loads(versions_text)
    if not isinstance(versions, list):
        fail("public versions query was not a list")
    stable = sorted(v for v in versions if semver_key(v) is not None)
    older = [v for v in stable if strictly_older(v, latest_text)]
    if not older:
        fail(f"no stable public Codex version is strictly older than fresh latest {latest_text}")
    old = PREFERRED_PUBLIC_OLD if PREFERRED_PUBLIC_OLD in older else older[-1]
    if old == latest_text or not strictly_older(old, latest_text):
        fail("selected public old version is not strictly older than latest")
    prefix = root / "prefix"
    install = [npm, "install", f"{PACKAGE}@{old}", "--global", "--prefix", str(prefix),
               "--registry=https://registry.npmjs.org/", "--no-audit", "--no-fund",
               "--package-lock=false", "--no-save", "--fetch-retries=0", "--fetch-timeout=30000"]
    proc = run(install, env, root, root / "receipts" / "public-install-old", timeout=300,
               profile=profile)
    if proc.returncode != 0:
        fail("public old npm install failed")
    if not (prefix / "bin/codex").exists():
        fail("npm did not create the public old bin link")
    home, zdot = write_rc(root, prefix, node_dir)
    sentinels = write_sentinels(root)
    (root / "sentinel-manifest.json").write_text(json.dumps(sentinels, indent=2, sort_keys=True) + "\n")
    recipe = root / "ordinary-app-recipe.txt"
    command = [str(app) + "/Contents/MacOS/AgentLensApp"]
    recipe_env = {
        **env,
        "HOME": str(home),
        "ZDOTDIR": str(zdot),
        "TMPDIR": str(root / "tmp"),
        "CFFIXED_USER_HOME": str(home),
        "PATH": ":".join([str(prefix / "bin"), node_dir, "/usr/bin", "/bin"]),
        "npm_config_prefix": str(prefix),
        "NPM_CONFIG_PREFIX": str(prefix),
    }
    write_recipe(recipe, [f"cd {shlex.quote(str(root))}"],
                 clean_env_command(["/usr/bin/sandbox-exec", "-f", str(profile), *command], recipe_env))
    write_json(root / "public-fixture.json", {
        "root": str(root), "old": old, "latest": latest_text,
        "old_is_strictly_older": strictly_older(old, latest_text),
        "versions_checked": len(stable),
        "prefix": str(prefix), "home": str(home), "zdot": str(zdot),
        "npm": npm, "node_dir": node_dir, "app": app, "profile": str(profile),
        "profile_sha256": sha256(profile),
        "ownership": ownership,
        "sentinels": sentinels,
    })
    print(f"PREPARE-PUBLIC OK root={root} old={old} latest={latest_text} strict-older=yes")


def verify_public(args) -> None:
    root = Path(args.root)
    require_owned_root(root)
    data = json.loads((root / "public-fixture.json").read_text())
    profile = Path(data["profile"])
    if not profile.is_file():
        fail(f"strict synthetic profile is missing: {profile}")
    if sha256(profile) != data.get("profile_sha256"):
        fail("strict synthetic profile content changed after preparation")
    npm, node_dir = npm_path()
    env = {**synthetic_npm_env(root, root / "home", node_dir)}
    env["ZDOTDIR"] = str(root / "zdot")
    env["CFFIXED_USER_HOME"] = str(root / "home")
    env["PATH"] = f"{root / 'prefix/bin'}:{node_dir}:/usr/bin:/bin"
    receipt = root / "receipts" / "public-cli-parity"
    proc = run([str(Path(args.cli).resolve()), "scan", "--offline"], env, root, receipt,
               profile=profile)
    if proc.returncode != 0:
        fail("public CLI parity scan failed")
    text = receipt.with_suffix(".stdout").read_text()
    manifest = root / "prefix/lib/node_modules" / PACKAGE / "package.json"
    installed = json.loads(manifest.read_text()).get("version")
    if not isinstance(installed, str) or not installed:
        fail("cannot read the installed public package version from the owned prefix")
    codex_lines = [line for line in text.splitlines() if "Codex" in line and installed in line]
    if not codex_lines:
        fail(f"CLI parity did not report the installed public version {installed}")
    current = sentinel_manifest(root / "sentinel")
    if current != data.get("sentinels"):
        fail("one or both unrelated sentinels changed")
    print(f"VERIFY-PUBLIC OK root={root} sentinels=2 sandboxed=yes")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--scenario", choices=["controlled", "serve-native", "stop-native", "record-native", "prepare-public", "verify-public"], required=True)
    parser.add_argument("--cli")
    parser.add_argument("--products")
    parser.add_argument("--app")
    args = parser.parse_args()
    if args.scenario == "controlled":
        if not args.products:
            parser.error("--products is required for controlled")
        controlled(args)
    elif args.scenario == "serve-native":
        serve_native(args)
    elif args.scenario == "stop-native":
        stop_native(args)
    elif args.scenario == "record-native":
        record_native(args)
    elif args.scenario == "prepare-public":
        if not args.cli or not args.app:
            parser.error("--cli and --app are required for prepare-public")
        prepare_public(args)
    else:
        if not args.cli:
            parser.error("--cli is required for verify-public")
        verify_public(args)


if __name__ == "__main__":
    main()
