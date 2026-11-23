#!/usr/bin/env python3
"""M13-C disposable real-Homebrew acceptance fixture.

This file is fixture evidence, not a product capability and not an acceptance verdict.  It builds
a completely disposable Homebrew prefix from the pinned local source, redirects every cache,
log, temp and application path into an operator-owned scratch root, and runs the synthetic
formula/cask lifecycle only while an outer macOS seatbelt profile denies personal-home writes,
personal application writes and all networking.

Only the Python standard library is used.  Nothing in a personal home, /Applications, a personal
cache or the read-only source is created, modified or deleted.  The harness creates the owned
--root and one disposable synthetic canary directory beside it (retained with the evidence); it
never writes to a protected root.  --root must not pre-exist, is never a cleanup target, and is
retained on failure for inspection.  The harness never invokes sudo, never enters a password,
never launches a cask uninstall/zap stanza and never falls back to a personal Homebrew
installation.
"""
from __future__ import annotations

import argparse
import errno
import gzip
import hashlib
import io
import json
import os
import pwd
import re
import shutil
import signal
import stat
import subprocess
import sys
import tarfile
import time
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import quote

PINNED_REVISION = "456c79a9946d416cac0b675850a33b169ccdc19a"
DEFAULT_SOURCE = "/opt/homebrew"
TAP_NAME = "m13test/test"
TAP_REMOTE = "m13test"
TAP_REPO = "homebrew-test"
FORMULA_PREFIX = TAP_NAME + "/"
CASK_PREFIX = TAP_NAME + "/"
SANDBOX_EXEC = "/usr/bin/sandbox-exec"
RUBY_MAJOR = "4."
MAX_COMMAND_SECONDS = 300
SHORT_TIMEOUT_SECONDS = 30
PERSONAL_PROTECTED = (
    Path("/opt/homebrew"),
    Path("/Applications"),
    Path("/System"),
    Path("/Library"),
    Path("/usr"),
    Path("/bin"),
    Path("/sbin"),
    Path("/etc"),
    Path("/private/etc"),
    Path("/Volumes"),
)
UNSAFE_EXACT = (
    Path("/Users"),
    Path("/Users/Shared"),
    Path("/tmp"),
    Path("/private/tmp"),
    Path("/var/tmp"),
    Path("/private/var/tmp"),
    Path("/opt"),
)
DENIAL_ERRNOS = (errno.EPERM, errno.EACCES)


class HarnessBlocked(Exception):
    """A deliberate, evidence-preserving stop."""


class RootRefused(HarnessBlocked):
    """The operator-supplied destination failed safety validation."""


def blocked(message: str) -> "None":
    raise HarnessBlocked(message)


def refuse(message: str) -> "None":
    raise RootRefused(message)


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def read_json(path: Path):
    return json.loads(path.read_text())


def sandbox_quote(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def is_within(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def physical(path: Path) -> Path:
    return Path(os.path.realpath(str(path)))


def directory_identity(path: Path) -> tuple:
    """Device/inode identity for an existing directory or file."""
    st = os.stat(str(path))
    return (st.st_dev, st.st_ino)


def identity_chain(path: Path) -> list:
    """Physical directory identities from ``path`` up to ``/``."""
    chain = []
    current = Path(os.path.abspath(str(path)))
    while True:
        st = os.stat(str(current))
        if not stat.S_ISDIR(st.st_mode):
            raise NotADirectoryError(str(current))
        chain.append({"path": str(current), "identity": [st.st_dev, st.st_ino],
                      "uid": st.st_uid, "mode": stat.S_IMODE(st.st_mode),
                      "sticky": bool(st.st_mode & stat.S_ISVTX)})
        if current == current.parent:
            return chain
        current = current.parent


def physically_within(path: Path, parent: Path) -> bool:
    """Identity-based containment that survives case-insensitive path aliases."""
    try:
        parent_identity = directory_identity(parent)
        resolved = physical(path)
        return any(directory_identity(component) == parent_identity
                   for component in (resolved, *resolved.parents))
    except OSError:
        return False


def system_account_home() -> Path:
    """The invoking account's home from the password database, independent of HOME."""
    return Path(pwd.getpwuid(os.getuid()).pw_dir)


def protected_identities(source: Path) -> dict:
    """Map directory identity -> description for protected and excluded trees.

    Comparisons are by device/inode rather than by path string because this disk is
    case-insensitive and ``Path.realpath`` preserves the supplied letter case.  Aliases such as
    ``/OPT/HomeBrew``, ``/applications`` and ``/USERS/<name>`` therefore still match.
    """
    identities = {}
    protected = list(PERSONAL_PROTECTED)
    protected.append(system_account_home())
    protected.append(Path.home())
    protected.append(Path(source))
    for label, candidate in [("protected", path) for path in protected] + [
            ("unsafe-exact", path) for path in UNSAFE_EXACT]:
        try:
            st = os.stat(str(candidate))
        except OSError:
            continue
        if not stat.S_ISDIR(st.st_mode):
            continue
        identities.setdefault((st.st_dev, st.st_ino), (label, str(candidate)))
    return identities


def refuse_unsafe_destination(destination: Path, source: Path) -> dict:
    """Validate a destination without creating it.

    The destination must be absolute, non-existent (a broken link counts as existing), and its
    physical ancestor chain is inspected component by component using device/inode identities:

    * no component may be a protected personal tree or a shared/excluded tree (aliases match);
    * every component must be owned by the invoking account or root and must not be writable by
      another account unless the sticky bit prevents replacement; the destination parent itself
      must be owned by the invoking account;
    * the full chain up to ``/`` is checked, so the per-user Darwin TEMP route stays admissible
      while a writable or foreign-owned component above it does not.

    ``--root`` and ``--check-root`` both use exactly this function.
    """
    if not destination.is_absolute():
        refuse("destination must be an absolute path: %s" % destination)
    if str(destination) != os.path.normpath(str(destination)):
        refuse("destination must be a normalized path without '..' or duplicate separators: %s"
                % destination)
    if destination.name in ("", ".", ".."):
        refuse("destination has an unsafe basename: %s" % destination)
    if os.path.lexists(str(destination)):
        refuse("destination already exists (including broken links) and is never adopted or "
                "cleaned: %s" % destination)
    parent = destination.parent
    if not parent.exists():
        refuse("destination parent does not exist: %s" % parent)
    if not parent.is_dir():
        refuse("destination parent is not a directory: %s" % parent)
    resolved_parent = physical(parent)
    resolved_root = resolved_parent / destination.name
    if physical(Path(os.path.abspath(str(parent)))) != resolved_parent:
        refuse("destination parent does not resolve consistently: %s" % parent)
    try:
        chain = identity_chain(resolved_parent)
    except OSError as error:
        refuse("destination parent chain cannot be inspected: %s" % error)
    identities = protected_identities(source)
    for entry in chain:
        match = identities.get(tuple(entry["identity"]))
        if match:
            refuse("destination ancestor %s resolves to %s %s"
                    % (entry["path"], match[0], match[1]))
        if entry["uid"] not in (0, os.getuid()):
            refuse("destination ancestor is owned by another account: %s (uid %d)"
                    % (entry["path"], entry["uid"]))
        if (entry["mode"] & (stat.S_IWGRP | stat.S_IWOTH)) and not entry["sticky"]:
            refuse("destination ancestor is writable by another account: %s (mode %04o)"
                    % (entry["path"], entry["mode"]))
    parent_stat = os.stat(str(resolved_parent))
    if parent_stat.st_uid != os.getuid():
        refuse("destination parent is not owned by the invoking account: %s" % resolved_parent)
    return {
        "destination": str(destination),
        "physical_root": str(resolved_root),
        "physical_parent": str(resolved_parent),
        "parent_device": parent_stat.st_dev,
        "parent_inode": parent_stat.st_ino,
        "parent_uid": parent_stat.st_uid,
        "ancestor_chain": chain,
        "protected_identities": [{"label": value[0], "path": value[1],
                                  "identity": list(key)} for key, value in identities.items()],
        "checked_ancestors": [entry["path"] for entry in chain],
        "source": str(physical(source)),
        "validation": "identity-based; full chain to /; parent must be operator-owned; "
                      "no writable-by-other component; root/check-root share this function",
    }


def create_owned_root(destination: Path, source: Path) -> dict:
    """Create the fresh 0700 root and write a nonce ownership record.

    The root is never recursively cleaned.  Callers retain it on every failure path.
    """
    validated = refuse_unsafe_destination(destination, source)
    resolved = Path(validated["physical_root"])
    parent = Path(validated["physical_parent"])
    parent_before = os.stat(str(parent))
    try:
        os.mkdir(str(resolved), 0o700)
    except FileExistsError:
        refuse("destination was created concurrently and is refused: %s" % resolved)
    os.chmod(resolved, 0o700)
    parent_after = os.stat(str(parent))
    if (parent_before.st_dev, parent_before.st_ino) != (parent_after.st_dev, parent_after.st_ino):
        blocked("destination parent identity changed during creation: %s" % parent)
    st = resolved.lstat()
    if not stat.S_ISDIR(st.st_mode) or stat.S_ISLNK(st.st_mode):
        blocked("created root is not a real directory: %s" % resolved)
    if st.st_uid != os.getuid():
        blocked("created root is not owned by the invoking user: %s" % resolved)
    record = {
        "root": str(resolved),
        "requested": str(destination),
        "owner_uid": os.getuid(),
        "device": st.st_dev,
        "inode": st.st_ino,
        "parent_device": parent_after.st_dev,
        "parent_inode": parent_after.st_ino,
        "parent_uid": parent_after.st_uid,
        "mode": stat.S_IMODE(st.st_mode),
        "created_at": utc_now(),
        "nonce": sha256_bytes(os.urandom(32)),
        "cleanup": "never; retained for inspection",
    }
    ownership = resolved / "ownership.json"
    ownership.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
    os.chmod(ownership, 0o600)
    record["ownership_sha256"] = sha256_file(ownership)
    write_json(resolved / "requested-root.json", validated)
    return record


class RootGuard:
    """Reconfirm physical root and parent ownership/identity before each mutation."""

    def __init__(self, record: dict):
        self.record = record
        self.path = Path(record["root"])
        self.parent = self.path.parent
        self.ownership = self.path / "ownership.json"

    def revalidate(self, purpose: str) -> None:
        st = self.path.lstat()
        if stat.S_ISLNK(st.st_mode) or not stat.S_ISDIR(st.st_mode):
            blocked("root identity changed before %s: %s" % (purpose, self.path))
        if st.st_uid != self.record["owner_uid"]:
            blocked("root owner changed before %s: %s" % (purpose, self.path))
        if stat.S_IMODE(st.st_mode) != 0o700:
            blocked("root mode changed before %s: %s" % (purpose, self.path))
        if st.st_dev != self.record["device"] or st.st_ino != self.record["inode"]:
            blocked("root device/inode changed before %s: %s" % (purpose, self.path))
        if physical(self.path) != Path(self.record["root"]):
            blocked("root physical path changed before %s: %s" % (purpose, self.path))
        parent_st = self.parent.lstat()
        if stat.S_ISLNK(parent_st.st_mode) or not stat.S_ISDIR(parent_st.st_mode):
            blocked("root parent is no longer a real directory before %s: %s"
                    % (purpose, self.parent))
        if (parent_st.st_dev, parent_st.st_ino) != (self.record["parent_device"],
                                                    self.record["parent_inode"]):
            blocked("root parent identity changed before %s: %s" % (purpose, self.parent))
        if parent_st.st_uid != self.record["parent_uid"]:
            blocked("root parent owner changed before %s: %s" % (purpose, self.parent))
        if (parent_st.st_mode & (stat.S_IWGRP | stat.S_IWOTH)) and not (
                parent_st.st_mode & stat.S_ISVTX):
            blocked("root parent is writable by another account before %s: %s"
                    % (purpose, self.parent))
        if not self.ownership.is_file():
            blocked("ownership record missing before %s: %s" % (purpose, self.ownership))
        current = read_json(self.ownership)
        if current.get("nonce") != self.record["nonce"]:
            blocked("ownership nonce mismatch before %s: %s" % (purpose, self.ownership))
        if current.get("owner_uid") != self.record["owner_uid"]:
            blocked("ownership uid mismatch before %s: %s" % (purpose, self.ownership))


def manifest_tree(path: Path, output_jsonl: Path) -> dict:
    """Hash one tree without following symlinks.

    Every node is recorded: directories by metadata, regular files by SHA-256 of their contents,
    symlinks by target only.  Read/hash errors fail closed instead of silently dropping entries.
    """
    path = Path(path)
    if not os.path.lexists(str(path)):
        return {"path": str(path), "present": False, "entry_count": 0, "digest": None}
    entries = []

    def visit(node: Path, rel: str) -> None:
        try:
            st = node.lstat()
        except OSError as error:
            blocked("manifest lstats failed for %s: %s" % (node, error))
        base = {
            "rel": rel,
            "mode": stat.S_IMODE(st.st_mode),
            "uid": st.st_uid,
            "gid": st.st_gid,
            "mtime_ns": st.st_mtime_ns,
            "nlink": st.st_nlink,
        }
        if stat.S_ISLNK(st.st_mode):
            try:
                target = os.readlink(str(node))
            except OSError as error:
                blocked("manifest readlink failed for %s: %s" % (node, error))
            entries.append(dict(base, type="symlink", target=target))
            return
        if stat.S_ISDIR(st.st_mode):
            entries.append(dict(base, type="dir"))
            try:
                names = sorted(os.listdir(str(node)))
            except OSError as error:
                blocked("manifest listdir failed for %s: %s" % (node, error))
            for name in names:
                visit(node / name, name if rel == "." else rel + "/" + name)
            return
        if stat.S_ISREG(st.st_mode):
            try:
                digest = sha256_file(node)
            except OSError as error:
                blocked("manifest content hash failed for %s: %s" % (node, error))
            entries.append(dict(base, type="file", size=st.st_size, sha256=digest))
            return
        entries.append(dict(base, type="special"))

    visit(path, ".")
    entries.sort(key=lambda entry: entry["rel"])
    lines = [json.dumps(entry, sort_keys=True, separators=(",", ":")) for entry in entries]
    payload = ("\n".join(lines) + "\n").encode("utf-8")
    output_jsonl.parent.mkdir(parents=True, exist_ok=True)
    output_jsonl.write_bytes(payload)
    return {
        "path": str(path),
        "present": True,
        "entry_count": len(entries),
        "digest": sha256_bytes(payload),
        "jsonl": str(output_jsonl),
    }


def personal_manifest_roots(source: Path = None) -> list:
    """Personal state that must remain byte-identical; absent roots stay recorded.

    Entry paths and their physical targets are both manifested when they differ, so a symlinked
    Homebrew prefix, ``/Applications`` or cache entry cannot hide the tree it points at.  Home is
    the invoking account's password-database home, never the fixture HOME environment.
    """
    home = system_account_home()
    entries = [
        Path("/opt/homebrew"),
        Path("/Applications"),
        home / "Library/Caches/Homebrew",
        home / "Library/Logs/Homebrew",
        home / "Library/Caches/AgentLens",
        home / "Library/Caches/agent-lens",
        home / "Library/Logs/AgentLens",
        home / "Library/Application Support/Agent Lens",
    ]
    if source is not None:
        entries.append(Path(source))
    expanded = []
    seen = set()
    for entry in entries:
        for candidate in (entry, physical(entry)):
            key = str(candidate)
            if key in seen:
                continue
            seen.add(key)
            expanded.append(candidate)
    return expanded


def snapshot_personal_state(root: Path, label: str, source: Path = None) -> dict:
    base = root / "evidence" / "manifests" / label
    base.mkdir(parents=True, exist_ok=True)
    trees = []
    for index, path in enumerate(personal_manifest_roots(source)):
        slug = re.sub(r"[^A-Za-z0-9]+", "_", str(path)).strip("_")[-80:]
        trees.append(manifest_tree(path, base / ("%02d-%s.jsonl" % (index, slug))))
    canonical = [
        {"path": tree["path"], "present": tree["present"],
         "entry_count": tree["entry_count"], "digest": tree["digest"]}
        for tree in trees
    ]
    summary = {
        "label": label,
        "captured_at": utc_now(),
        "captured_after_step": 0,
        "equality": "node set equal and every recorded value equal: file SHA-256 contents, "
                    "mode, uid, gid, mtime_ns, nlink, symlink targets; no symlink entries followed",
        "trees": trees,
        "combined_digest": sha256_bytes(
            "\n".join(json.dumps(tree, sort_keys=True) for tree in canonical).encode("utf-8")
        ),
    }
    write_json(base / "summary.json", summary)
    return summary


def compare_personal_state(before: dict, after: dict) -> list:
    differences = []
    if before.get("combined_digest") != after.get("combined_digest"):
        differences.append("combined personal manifest digest changed")
    before_trees = {tree["path"]: tree for tree in before.get("trees", [])}
    after_trees = {tree["path"]: tree for tree in after.get("trees", [])}
    for path in sorted(set(before_trees) | set(after_trees)):
        left = before_trees.get(path)
        right = after_trees.get(path)
        if left is None or right is None:
            differences.append("manifest root set changed: %s" % path)
        elif left.get("digest") != right.get("digest"):
            differences.append("manifest changed: %s" % path)
    return differences


def write_seatbelt_profile(root: Path) -> Path:
    """Generate the outer containment profile from this root's physical paths.

    Writes are denied everywhere except the fixture root and ``/dev/null``.  There is no system
    temporary exception: every child runs with a scratch cwd, so Bash here-strings create their
    temporary file inside the fixture root (proved by the preflight control with the exact cwd
    used by manager launches).  All networking is denied first, then only Unix-domain socket
    traffic whose path is inside the fixture temp directory is re-allowed; IP networking has no
    path and therefore remains denied.
    """
    root = physical(root)
    fixture_tmp = root / "tmp"
    profile = root / "seatbelt.sb"
    lines = [
        "(version 1)",
        "(allow default)",
        "(deny network*)",
        '(allow network* network-outbound (subpath "%s"))' % sandbox_quote(str(fixture_tmp)),
        "(deny file-write*)",
        "(allow file-write*",
        '    (subpath "%s")' % sandbox_quote(str(root)),
        '    (literal "/dev/null")',
        ")",
    ]
    profile.write_text("\n".join(lines) + "\n")
    os.chmod(profile, 0o600)
    return profile


def fixture_environment(root: Path, prefix: Path) -> dict:
    """A closed environment: no inherited HOMEBREW_* flags, PATH cannot find a personal brew."""
    root = physical(root)
    prefix = physical(prefix)
    home = root / "home"
    return {
        "HOME": str(home),
        "CFFIXED_USER_HOME": str(home),
        "XDG_CONFIG_HOME": str(home / ".config"),
        "XDG_CACHE_HOME": str(home / ".cache"),
        "XDG_DATA_HOME": str(home / ".local/share"),
        "TMPDIR": str(root / "tmp"),
        "PATH": "%s/bin:/usr/bin:/bin:/usr/sbin:/sbin" % prefix,
        "PWD": str(root),
        "SHELL": "/bin/sh",
        "LC_ALL": "C",
        "LANG": "C",
        "GIT_CONFIG_GLOBAL": str(home / ".gitconfig"),
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_TERMINAL_PROMPT": "0",
        "HOMEBREW_CACHE": str(root / "cache"),
        "HOMEBREW_LOGS": str(root / "logs"),
        "HOMEBREW_TEMP": str(root / "tmp"),
        "HOMEBREW_NO_AUTO_UPDATE": "1",
        "HOMEBREW_NO_ANALYTICS": "1",
        "HOMEBREW_NO_ENV_HINTS": "1",
        "HOMEBREW_NO_COLOR": "1",
        "HOMEBREW_NO_EMOJI": "1",
        "HOMEBREW_NO_INSTALL_CLEANUP": "1",
        "HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK": "1",
        "HOMEBREW_NO_AUTOREMOVE": "1",
        "HOMEBREW_NO_INSTALL_FROM_API": "1",
        "HOMEBREW_NO_SUDO": "1",
    }


class EventLog:
    """Append-only receipts and a machine-readable pass/fail report."""

    def __init__(self, root: Path):
        self.root = physical(root)
        self.evidence = self.root / "evidence"
        self.steps_dir = self.evidence / "steps"
        self.steps_dir.mkdir(parents=True, exist_ok=True)
        self.checks = []
        self.failures = []
        self.steps = []
        self.scenario_results = []
        self.counter = 0
        self.started_at = utc_now()

    def step(self, purpose: str, argv: list, exit_code, stdout: str, stderr: str,
             elapsed: float, sandboxed: bool, extra: dict = None) -> dict:
        self.counter += 1
        receipt = {
            "seq": self.counter,
            "purpose": purpose,
            "argv": argv,
            "exit": exit_code,
            "stdout": stdout,
            "stderr": stderr,
            "elapsed_seconds": round(elapsed, 3),
            "sandboxed": sandboxed,
            "at": utc_now(),
        }
        if extra:
            receipt.update(extra)
        name = "%03d-%s.json" % (self.counter, re.sub(r"[^A-Za-z0-9]+", "-", purpose).strip("-")[:80])
        write_json(self.steps_dir / name, receipt)
        self.steps.append(receipt)
        return receipt

    def check(self, scenario: str, name: str, ok: bool, detail=None) -> bool:
        entry = {
            "scenario": scenario,
            "name": name,
            "ok": bool(ok),
            "detail": detail,
            "at": utc_now(),
        }
        self.checks.append(entry)
        if not ok:
            self.failures.append(entry)
        return bool(ok)

    def scenario(self, scenario_id: str, title: str, function) -> bool:
        started = time.monotonic()
        error = None
        failures_before = len(self.failures)
        try:
            function()
        except HarnessBlocked as failure:
            error = str(failure)
            self.check(scenario_id, "scenario completed", False, error)
        except Exception as failure:  # unexpected fixture bug still leaves evidence
            error = "%s: %s" % (type(failure).__name__, failure)
            self.check(scenario_id, "scenario completed", False, error)
        failed_checks = len(self.failures) - failures_before
        result = {
            "id": scenario_id,
            "title": title,
            "elapsed_seconds": round(time.monotonic() - started, 3),
            "status": "failed" if (error or failed_checks) else "passed",
            "error": error,
            "failed_checks": failed_checks,
        }
        self.scenario_results.append(result)
        write_json(self.evidence / "report.json", self.report("running"))
        return error is None and failed_checks == 0

    def report(self, status: str) -> dict:
        return {
            "status": status,
            "fixture": "M13-C homebrew_acceptance",
            "label": "fixture evidence, not an acceptance verdict",
            "root": str(self.root),
            "started_at": self.started_at,
            "finished_at": utc_now() if status != "running" else None,
            "scenarios": self.scenario_results,
            "checks": self.checks,
            "failures": self.failures,
            "steps": [{"seq": step["seq"], "purpose": step["purpose"], "exit": step["exit"]}
                      for step in self.steps],
        }


def file_url(path: Path) -> str:
    return "file://" + quote(str(physical(path)), safe="/")


def write_tar_gz(path: Path, files: dict) -> str:
    """Write a deterministic gzip tarball; return its SHA-256."""
    with path.open("wb") as raw:
        with gzip.GzipFile(fileobj=raw, mode="wb", mtime=0) as compressed:
            with tarfile.open(fileobj=compressed, mode="w") as archive:
                for arcname in sorted(files):
                    data, mode = files[arcname]
                    info = tarfile.TarInfo(arcname)
                    info.size = len(data)
                    info.mode = mode
                    info.mtime = 0
                    info.uid = 0
                    info.gid = 0
                    info.uname = ""
                    info.gname = ""
                    archive.addfile(info, io.BytesIO(data))
    return sha256_file(path)


def plist_xml(bundle_id: str, bundle_name: str, executable: str, short_version: str) -> bytes:
    return ("""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>%s</string>
  <key>CFBundleIdentifier</key><string>%s</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>%s</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>%s</string>
  <key>CFBundleVersion</key><string>%s</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
</dict>
</plist>
""" % (executable, bundle_id, bundle_name, short_version, short_version)).encode("utf-8")


def write_app_zip(path: Path, app_name: str, version: str, bundle_id: str) -> str:
    """Create a legitimate minimal app bundle whose Mach-O is the system /usr/bin/true."""
    executable = app_name[:-4]
    true_bytes = Path("/usr/bin/true").read_bytes()
    plist = plist_xml(bundle_id, executable, executable, version)
    version_marker = ("fixture app %s version %s\n" % (app_name, version)).encode("utf-8")
    entries = [
        (app_name + "/", b"", 0o755, True),
        (app_name + "/Contents/", b"", 0o755, True),
        (app_name + "/Contents/MacOS/", b"", 0o755, True),
        (app_name + "/Contents/Resources/", b"", 0o755, True),
        (app_name + "/Contents/Info.plist", plist, 0o644, False),
        (app_name + "/Contents/MacOS/" + executable, true_bytes, 0o755, False),
        (app_name + "/Contents/Resources/version.txt", version_marker, 0o644, False),
    ]
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, data, mode, is_dir in entries:
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.external_attr = (mode << 16) | (0x10 if is_dir else 0)
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, data)
    return sha256_file(path)


def formula_text(name: str, version: str, payload: Path, payload_sha: str,
                 depends=None, broken_install=False) -> str:
    class_name = "".join(part.capitalize() for part in name.split("-"))
    filename = name
    dependency = '  depends_on "%s"\n\n' % depends if depends else ""
    if broken_install:
        install = '    system "false"\n'
    else:
        install = '    bin.install "%s"\n' % filename
    return (
        'class %s < Formula\n'
        '  desc "M13-C fixture %s formula"\n'
        '  homepage "https://example.invalid/%s"\n'
        '  url "%s"\n'
        '  sha256 "%s"\n'
        '  version "%s"\n\n'
        '%s'
        '  def install\n'
        '%s'
        '  end\n'
        'end\n'
    ) % (class_name, name, name, file_url(payload), payload_sha, version, dependency, install)


def cask_text(token: str, version: str, payload: Path, payload_sha: str, *,
              binary=None, app=None, auto_updates=False, uninstall=None, zap=None) -> str:
    version_line = '  version :latest\n  sha256 :no_check\n' if version == "latest" else (
        '  version "%s"\n  sha256 "%s"\n' % (version, payload_sha)
    )
    lines = [
        'cask "%s" do' % token,
        version_line.rstrip("\n"),
        '  url "%s"' % file_url(payload),
        '  name "M13 %s"' % token.replace("-", " ").title(),
        '  desc "M13-C fixture %s cask"' % token,
        '  homepage "https://example.invalid/%s"' % token,
        "",
    ]
    if auto_updates:
        lines.append("  auto_updates true")
    if binary:
        lines.append('  binary "%s"' % binary)
    if app:
        lines.append('  app "%s"' % app)
    if uninstall:
        lines.append("")
        lines.extend("  " + line for line in uninstall)
    if zap:
        lines.append("")
        lines.extend("  " + line for line in zap)
    lines.append("end")
    return "\n".join(lines) + "\n"


def git_author_env(base: dict) -> dict:
    env = dict(base)
    env.update({
        "GIT_AUTHOR_NAME": "M13 Fixture",
        "GIT_AUTHOR_EMAIL": "m13-fixture@example.invalid",
        "GIT_COMMITTER_NAME": "M13 Fixture",
        "GIT_COMMITTER_EMAIL": "m13-fixture@example.invalid",
        "GIT_AUTHOR_DATE": "2026-01-01T00:00:00Z",
        "GIT_COMMITTER_DATE": "2026-01-01T00:00:00Z",
    })
    return env


FORMULA_VERSIONS = {
    "m13-old": ["1.0.0", "1.2.0"],
    "m13-sentinel": ["1.0.0", "1.0.1"],
    "m13-lib": ["1.0.0"],
    "m13-consumer": ["1.0.0"],
    "m13-pinned": ["1.0.0", "1.0.1"],
    "m13-broken": ["1.0.0", "1.0.1"],
}
CASK_VERSIONS = {
    "m13-cask-binary": ["1.0.0", "1.1.0"],
    "m13-cask-app": ["1.0.0", "1.1.0"],
    "m13-cask-appstanza": ["1.0.0"],
    "m13-cask-delete": ["1.0.0"],
    "m13-cask-escape": ["1.0.0"],
    "m13-cask-auto": ["1.0.0", "2.0.0"],
    "m13-cask-latest": ["latest"],
    "m13-cask-comma": ["1.2.3,9", "1.2.4,10"],
}
INITIAL_FORMULAE = {name: versions[0] for name, versions in FORMULA_VERSIONS.items()}
INITIAL_CASKS = {name: versions[0] for name, versions in CASK_VERSIONS.items()}
PROBE_SOURCE = r'''
import errno, json, os, socket, sys

kind = sys.argv[1]
target = sys.argv[2] if len(sys.argv) > 2 else None
result = {"probe": kind, "target": target}
try:
    if kind == "open-write":
        fd = os.open(target, os.O_WRONLY)
        os.close(fd)
    elif kind == "make-dir":
        os.mkdir(target, 0o700)
    elif kind == "write-new":
        with open(target, "w") as handle:
            handle.write("m13 probe")
    elif kind == "bind":
        sock = socket.socket()
        sock.bind(("127.0.0.1", 0))
    elif kind == "connect":
        sock = socket.socket()
        sock.settimeout(2)
        sock.connect(("127.0.0.1", 9))
    elif kind == "unix-bind-connect":
        os.chdir(target)
        server = socket.socket(socket.AF_UNIX)
        server.bind("m13-probe.sock")
        server.listen(1)
        client = socket.socket(socket.AF_UNIX)
        client.connect("m13-probe.sock")
    elif kind == "open-tty":
        fd = os.open("/dev/tty", os.O_RDWR)
        os.close(fd)
    else:
        raise SystemExit("unknown probe kind: " + kind)
    result["outcome"] = "allowed"
except OSError as error:
    result.update(outcome="oserror", errno=error.errno,
                  errno_name=errno.errorcode.get(error.errno), message=str(error))
print(json.dumps(result, sort_keys=True))
'''


class Harness:
    """Fixture state, containment proofs and contained subprocess execution."""

    def __init__(self, record: dict, source: Path, expected_revision: str):
        if expected_revision != PINNED_REVISION:
            blocked("the fixed revision set is required; refusing override %s" % expected_revision)
        self.record = record
        self.root = Path(record["root"])
        self.guard = RootGuard(record)
        self.source = physical(source)
        self.expected_revision = expected_revision
        self.events = EventLog(self.root)
        self.prefix = None
        self.profile = None
        self.profile_digest = None
        self.env = None
        self.containment_proofs = 0
        self.brew_version = None
        self.portable_ruby = None
        self.before_manifest = None
        self.after_manifest = None
        self.refused_casks = []
        self.cask_mutations = []
        self.canary_root = None
        self.unsafe_target = None

    def setup_fixture_dirs(self) -> None:
        self.guard.revalidate("fixture directory setup")
        for name in ("home", "cache", "logs", "tmp", "appdir", "payloads", "stage", "sentinels",
                     "tap-src", "evidence"):
            path = self.root / name
            path.mkdir(mode=0o700, exist_ok=True)
            os.chmod(path, 0o700)
        gitconfig = self.root / "home" / ".gitconfig"
        gitconfig.write_text(
            "[user]\n\tname = M13 Fixture\n\temail = m13-fixture@example.invalid\n"
            "[init]\n\tdefaultBranch = main\n"
            "[safe]\n\tdirectory = *\n"
        )
        os.chmod(gitconfig, 0o600)

    def setup_profile(self) -> None:
        self.guard.revalidate("seatbelt profile generation")
        self.profile = write_seatbelt_profile(self.root)
        self.profile_digest = sha256_file(self.profile)
        self.events.check("preflight", "profile has no system temporary write exception",
                          "/private/var/tmp" not in self.profile.read_text()
                          and "sh-thd" not in self.profile.read_text(), None)
        write_json(self.root / "evidence" / "seatbelt.json", {
            "profile": str(self.profile),
            "sha256": self.profile_digest,
            "profile_text": self.profile.read_text(),
            "write_exceptions": {
                "fixture_root": str(self.root),
                "device_null": "/dev/null",
                "note": "no system temp grant; every child runs with a scratch cwd so Bash "
                        "here-strings stay inside the root (see preflight)",
            },
            "unix_socket": "network* outbound/bind filtered to <root>/tmp only; no IP",
        })

    def _sandbox_argv(self, argv: list) -> list:
        return [SANDBOX_EXEC, "-f", str(self.profile)] + list(argv)

    def _environment(self) -> dict:
        return self.env or fixture_environment(self.root, self.prefix or self.root)

    def _egress_check(self, purpose: str, cwd: Path, env: dict) -> dict:
        """Reject an egress with a stale profile, non-scratch cwd, personal PATH or open env."""
        self.guard.revalidate("egress for " + purpose)
        if not self.profile or sha256_file(self.profile) != self.profile_digest:
            blocked("seatbelt profile missing or changed at egress for %s" % purpose)
        cwd = Path(cwd)
        if not cwd.is_dir():
            blocked("egress cwd is not a directory for %s: %s" % (purpose, cwd))
        if not physically_within(cwd, self.root):
            blocked("egress cwd escapes the scratch root for %s: %s" % (purpose, cwd))
        for key in ("HOME", "TMPDIR", "HOMEBREW_CACHE", "HOMEBREW_LOGS", "HOMEBREW_TEMP"):
            value = env.get(key)
            if not value or not physically_within(Path(value), self.root):
                blocked("egress %s escapes the scratch root for %s: %r" % (key, purpose, value))
        path_entries = [entry for entry in env.get("PATH", "").split(":") if entry]
        for personal in ("/opt/homebrew", "/usr/local/bin", "/usr/local/sbin"):
            if personal in path_entries:
                blocked("egress PATH resolves a personal manager for %s: %s" % (purpose, personal))
        for key in ("HOMEBREW_PREFIX", "HOMEBREW_CELLAR", "HOMEBREW_CASKROOM"):
            if key in env:
                blocked("egress environment carries inherited %s for %s" % (key, purpose))
        cwd_stat = os.stat(str(cwd))
        return {"cwd": str(cwd), "cwd_identity": [cwd_stat.st_dev, cwd_stat.st_ino],
                "profile_sha256": self.profile_digest}

    def _execute(self, purpose: str, argv: list, timeout: int = MAX_COMMAND_SECONDS,
                 sandboxed: bool = True, inherit_homebrew_fd: bool = False,
                 env: dict = None, cwd: Path = None) -> dict:
        if not sandboxed:
            blocked("every fixture command must run inside the outer seatbelt: %s" % purpose)
        actual_env = env if env is not None else self._environment()
        actual_cwd = Path(cwd if cwd is not None else self.root)
        egress = self._egress_check(purpose, actual_cwd, actual_env)
        full_argv = self._sandbox_argv(argv)
        fd = None
        if inherit_homebrew_fd:
            rubric = self.prefix / "Library/Homebrew/sandbox.rb"
            if not rubric.is_file():
                blocked("scratch sandbox.rb missing for inherited-sandbox protocol: %s" % rubric)
            fd = os.open(str(rubric), os.O_RDONLY)
            if fd != 198:
                os.dup2(fd, 198)
                os.close(fd)
                fd = 198
            os.set_inheritable(198, True)
        started = time.monotonic()
        receipt = None
        try:
            process = subprocess.Popen(
                full_argv,
                cwd=str(actual_cwd),
                env=actual_env,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                start_new_session=True,
                pass_fds=(fd,) if fd is not None else (),
            )
            timed_out = False
            try:
                stdout, stderr = process.communicate(timeout=timeout)
            except subprocess.TimeoutExpired:
                timed_out = True
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                stdout, stderr = process.communicate(timeout=30)
            exit_code = "timeout" if timed_out else process.returncode
            elapsed = time.monotonic() - started
            receipt = self.events.step(
                purpose, full_argv, exit_code,
                stdout.decode("utf-8", "replace"), stderr.decode("utf-8", "replace"),
                elapsed, sandboxed,
                {"cwd": egress["cwd"],
                 "cwd_identity": egress["cwd_identity"],
                 "profile_sha256": egress["profile_sha256"],
                 "env_sha256": sha256_bytes(json.dumps(actual_env, sort_keys=True).encode()),
                 "inherited_sandbox_fd": 198 if inherit_homebrew_fd else None},
            )
        finally:
            if fd is not None:
                os.close(fd)
        return receipt

    def _probe(self, purpose: str, kind: str, target: Path = None) -> tuple:
        """Run one OSError-reporting probe and return (receipt, parsed-json).

        The probe process itself always exits 0 when it can report a syscall outcome, so a
        nonzero exit is never mistaken for a denial.
        """
        arguments = ["/usr/bin/python3", "-B", "-c", PROBE_SOURCE, kind]
        if target is not None:
            arguments.append(str(target))
        receipt = self._execute(purpose, arguments, timeout=SHORT_TIMEOUT_SECONDS)
        parsed = None
        if receipt["exit"] == 0:
            lines = [line for line in receipt["stdout"].splitlines() if line.strip()]
            if lines:
                try:
                    parsed = json.loads(lines[-1])
                except json.JSONDecodeError:
                    parsed = None
        return receipt, parsed

    def _expect_allowed(self, scenario: str, purpose: str, kind: str, target: Path = None) -> dict:
        receipt, parsed = self._probe(purpose, kind, target)
        ok = bool(parsed) and parsed.get("outcome") == "allowed" and receipt["exit"] == 0
        self.events.check(scenario, purpose, ok,
                          {"exit": receipt["exit"], "probe": parsed,
                           "stderr_tail": receipt["stderr"][-500:]})
        return parsed or {}

    def _expect_denial(self, scenario: str, purpose: str, kind: str, target: Path = None,
                       errnos: tuple = DENIAL_ERRNOS) -> dict:
        """Require explicit EPERM/EACCES evidence, never an arbitrary nonzero exit."""
        receipt, parsed = self._probe(purpose, kind, target)
        ok = (bool(parsed) and parsed.get("outcome") == "oserror"
              and parsed.get("errno") in errnos)
        self.events.check(
            scenario, purpose, ok,
            {"expected_errnos": list(errnos), "exit": receipt["exit"], "probe": parsed,
             "stderr_tail": receipt["stderr"][-500:]},
        )
        return parsed or {}

    def _file_state(self, path: Path) -> dict:
        if not path.is_file():
            return {"path": str(path), "present": False}
        st = path.stat()
        return {"path": str(path), "present": True, "sha256": sha256_file(path),
                "mode": stat.S_IMODE(st.st_mode), "mtime_ns": st.st_mtime_ns,
                "size": st.st_size}

    def preflight_controls(self) -> None:
        """Prove the outer profile before any Homebrew mutation.

        Writes are only ever attempted inside disposable synthetic canaries that this harness
        owns, or against existing files with a write-only *open* that never writes data.  Nothing
        creates or removes a file in a personal home or /Applications when a profile is
        ineffective; protected roots are represented by read-only manifest equality instead.
        """
        self.guard.revalidate("seatbelt preflight")
        self.env = fixture_environment(self.root, self.prefix)
        events = self.events
        nonce = self.record["nonce"][:16]
        # A harmless write inside the fixture root must succeed.
        inside = self.root / "evidence" / "preflight-inside.txt"
        self._expect_allowed("preflight", "bounded write inside root succeeds",
                             "write-new", inside)
        events.check("preflight", "inside-root write left the expected file",
                     inside.is_file() and inside.read_text() == "m13 probe", None)
        # A disposable synthetic canary outside the root, owned by this harness.
        canary = self.root.parent / (".m13-canary-" + nonce)
        if os.path.lexists(str(canary)):
            blocked("synthetic canary unexpectedly pre-exists: %s" % canary)
        canary.mkdir(mode=0o700)
        self.canary_root = canary
        existing = canary / "existing.txt"
        existing.write_text("canary\n")
        os.chmod(existing, 0o600)
        canary_before = self._file_state(existing)
        self._expect_denial("preflight", "seatbelt denies write-open of an outside canary",
                            "open-write", existing)
        self._expect_denial("preflight", "seatbelt denies directory creation beside the root",
                            "make-dir", canary / "created-dir")
        created_dir = os.path.lexists(str(canary / "created-dir"))
        if created_dir:
            try:
                os.rmdir(str(canary / "created-dir"))
            except OSError:
                pass
        events.check("preflight", "outside canary was not modified or created",
                     not created_dir and self._file_state(existing) == canary_before,
                     {"created_dir": created_dir, "before": canary_before,
                      "after": self._file_state(existing)})
        self._expect_denial("preflight", "seatbelt denies synthetic shared-temp directory",
                            "make-dir", Path("/private/var/tmp") / (".m13-no-temp-" + nonce))
        shared_temp = Path("/private/var/tmp") / (".m13-no-temp-" + nonce)
        if os.path.lexists(str(shared_temp)):
            try:
                os.rmdir(str(shared_temp))
            except OSError:
                pass
        events.check("preflight", "shared-temp canary was not created",
                     not os.path.lexists(str(shared_temp)), str(shared_temp))
        # A real personal file is write-opened (never written) to evidence a path-specific EPERM.
        home_file = system_account_home() / ".CFUserTextEncoding"
        if home_file.is_file() and os.access(str(home_file), os.W_OK):
            home_before = self._file_state(home_file)
            self._expect_denial("preflight", "seatbelt denies personal-home file write-open",
                                "open-write", home_file)
            events.check("preflight", "personal-home canary file is bit-identical after probe",
                         self._file_state(home_file) == home_before,
                         {"before": home_before, "after": self._file_state(home_file)})
        else:
            events.check("preflight", "personal-home write-open candidate exists", False,
                         {"path": str(home_file), "present": home_file.is_file()})
        # The pinned source is the operator's other personal writable root; open-only probe.
        source_file = self.source / ".git/HEAD"
        if source_file.is_file() and os.access(str(source_file), os.W_OK):
            source_before = self._file_state(source_file)
            self._expect_denial("preflight", "seatbelt denies pinned-source file write-open",
                                "open-write", source_file)
            events.check("preflight", "pinned-source canary file is bit-identical after probe",
                         self._file_state(source_file) == source_before,
                         {"before": source_before, "after": self._file_state(source_file)})
        # IP networking is denied in both directions with explicit errno evidence.
        self._expect_denial("preflight", "seatbelt denies IP bind", "bind")
        self._expect_denial("preflight", "seatbelt denies IP connect", "connect")
        # Unix sockets are permitted only under fixture tmp.
        self._expect_allowed("preflight", "fixture-local Unix IPC works",
                             "unix-bind-connect", self.root / "tmp")
        self._expect_denial("preflight", "Unix IPC is scoped to fixture tmp",
                            "unix-bind-connect", self.root)
        outside_socket = self.root / "m13-probe.sock"
        if os.path.lexists(str(outside_socket)):
            try:
                outside_socket.unlink()
            except OSError:
                pass
        events.check("preflight", "Unix IPC outside fixture tmp created no socket",
                     not os.path.lexists(str(outside_socket)), str(outside_socket))
        # Bash here-strings work with the scratch cwd and no system temp exception.
        receipt = self._execute(
            "preflight Bash here-string with scratch cwd",
            ["/bin/bash", "-c",
             "read -r proof <<< 'seatbelt control'; test \"$proof\" = 'seatbelt control'"],
            timeout=SHORT_TIMEOUT_SECONDS, cwd=self.root,
        )
        events.check("preflight", "Bash here-string works with no system temp exception",
                     receipt["exit"] == 0 and receipt["cwd"] == str(self.root),
                     {"exit": receipt["exit"], "cwd": receipt["cwd"],
                      "stderr_tail": receipt["stderr"][-500:]})
        # /dev/null is the only non-root write target.
        self._expect_allowed("preflight", "write-open of /dev/null is allowed",
                             "open-write", Path("/dev/null"))
        # No controlling TTY is available to child processes.
        tty = self._expect_denial("preflight", "children have no controlling TTY",
                                  "open-tty", errnos=(errno.ENXIO, errno.ENOENT, errno.EPERM))
        events.check("preflight", "no-TTY evidence is an explicit errno", bool(tty.get("errno_name")),
                     tty)
        write_json(self.events.evidence / "preflight-canaries.json", {
            "inside_root": str(inside),
            "outside_canary": str(canary),
            "outside_canary_target": str(existing),
            "shared_temp_target": str(shared_temp),
            "personal_home_open_only": str(home_file),
            "source_open_only": str(source_file),
            "policy": "outside writes are attempted only in disposable synthetic canaries owned "
                      "by this harness; personal/source probes open existing files write-only "
                      "without writing data, so an ineffective profile cannot create or remove "
                      "anything there",
            "denial_evidence": "explicit errno EPERM/EACCES parsed from each probe; nonzero exit "
                               "alone is never accepted",
        })
        write_json(self.events.evidence / "report.json", self.events.report("running"))
        if self.events.failures:
            blocked("seatbelt preflight controls failed; no manager mutation attempted")

    def require_containment(self, purpose: str) -> None:
        """Fresh containment proof immediately before every manager mutation."""
        self.guard.revalidate(purpose)
        if not self.profile or sha256_file(self.profile) != self.profile_digest:
            blocked("seatbelt profile missing or changed before %s" % purpose)
        if not self.prefix:
            blocked("scratch prefix is not established before %s" % purpose)
        for name, path in (("prefix", self.prefix),
                           ("cellar", self.prefix / "Cellar"),
                           ("caskroom", self.prefix / "Caskroom"),
                           ("brew", self.prefix / "bin/brew")):
            if not physically_within(path, self.root):
                blocked("scratch %s escapes root before %s: %s" % (name, purpose, path))
        for component in (self.prefix, self.prefix / "Cellar", self.prefix / "Caskroom"):
            if physical(component) != component:
                blocked("scratch %s is an alias before %s: %s -> %s"
                        % (component.name, purpose, component, physical(component)))
        brew = self.prefix / "bin/brew"
        if os.access(str(brew), os.W_OK):
            blocked("scratch brew file is writable; inherited-sandbox protocol requires read-only: %s" % brew)
        if not self.env or not self.profile:
            blocked("fixed scratch environment is not established before %s" % purpose)
        receipt, parsed = self._probe("containment: IP bind denied before %s" % purpose, "bind")
        denied = (bool(parsed) and parsed.get("outcome") == "oserror"
                  and parsed.get("errno") in DENIAL_ERRNOS)
        if not denied:
            blocked("live seatbelt containment probe lacks explicit denial before %s: %r"
                    % (purpose, parsed))
        self.containment_proofs += 1

    def run_brew(self, purpose: str, arguments: list, timeout: int = MAX_COMMAND_SECONDS) -> dict:
        if arguments and arguments[0] in ("upgrade", "uninstall"):
            if "--formula" not in arguments or "--cask" in arguments:
                blocked("fixture cask upgrades and uninstalls require the artifact guard: %s"
                        % purpose)
        return self._launch_brew(purpose, arguments, timeout)

    def _launch_brew(self, purpose: str, arguments: list, timeout: int = MAX_COMMAND_SECONDS) -> dict:
        if not self.prefix:
            blocked("brew used before prefix verification: %s" % purpose)
        forbidden = [token for token in arguments if token in ("sudo", "zap", "--zap", "rm", "remove",
                                                               "--ignore-dependencies",
                                                               "--force", "-f")]
        if forbidden:
            blocked("fixture policy forbids brew argument(s) %s in %s" % (forbidden, purpose))
        self.require_containment(purpose)
        receipt = self._execute(
            purpose, [str(self.prefix / "bin/brew")] + list(arguments),
            timeout=timeout, sandboxed=True, inherit_homebrew_fd=True,
        )
        self.guard.revalidate("after " + purpose)
        return receipt


    def _git(self, purpose: str, arguments: list, cwd: Path = None,
             timeout: int = MAX_COMMAND_SECONDS) -> dict:
        return self._execute(
            purpose, ["/usr/bin/git"] + list(arguments),
            timeout=timeout, sandboxed=True, env=git_author_env(self.env),
            cwd=cwd if cwd is not None else self.root,
        )

    def verify_source(self) -> dict:
        if not self.source.is_dir():
            blocked("Homebrew source directory missing: %s" % self.source)
        if not (self.source / ".git").exists():
            blocked("Homebrew source is not a git repository: %s" % self.source)
        revision = self.expected_revision
        receipt = self._git("verify pinned source revision",
                            ["-C", str(self.source), "cat-file", "-e", revision + "^{commit}"])
        if receipt["exit"] != 0:
            blocked("pinned Homebrew revision is absent from local source: %s" % revision)
        ruby_current = self.source / "Library/Homebrew/vendor/portable-ruby/current"
        if not ruby_current.exists():
            blocked("vendored portable Ruby is missing: %s" % ruby_current)
        ruby_real = physical(ruby_current)
        ruby_bin = ruby_real / "bin/ruby"
        if not ruby_bin.is_file():
            blocked("vendored portable Ruby executable is missing: %s" % ruby_bin)
        receipt = self._execute("verify vendored portable Ruby", [str(ruby_bin), "-v"],
                                timeout=SHORT_TIMEOUT_SECONDS)
        if receipt["exit"] != 0 or not receipt["stdout"].startswith("ruby " + RUBY_MAJOR):
            blocked("vendored portable Ruby is not the required %s release: %s"
                    % (RUBY_MAJOR, receipt["stdout"].strip()[:200]))
        facts = {
            "source": str(self.source),
            "expected_revision": revision,
            "portable_ruby_source": str(ruby_real),
            "portable_ruby_output": receipt["stdout"].strip(),
        }
        write_json(self.root / "evidence" / "source.json", facts)
        return facts

    def clone_prefix(self) -> None:
        self.guard.revalidate("scratch prefix clone")
        if self.prefix is None:
            self.prefix = self.root / "prefix"
        if os.path.lexists(str(self.prefix)):
            blocked("scratch prefix already exists: %s" % self.prefix)
        clone_receipt = self._git("clone scratch prefix",
                                  ["clone", "--no-hardlinks", str(self.source), str(self.prefix)],
                                  cwd=self.root, timeout=MAX_COMMAND_SECONDS)
        if clone_receipt["exit"] != 0:
            blocked("scratch prefix clone failed: %s" % clone_receipt["stderr"][-1000:])
        checkout_receipt = self._git("checkout pinned revision",
                                     ["-C", str(self.prefix), "checkout", "--detach",
                                      self.expected_revision])
        if checkout_receipt["exit"] != 0:
            blocked("scratch checkout of pinned revision failed: %s"
                    % checkout_receipt["stderr"][-1000:])
        revision_receipt = self._git("verify scratch prefix revision",
                                     ["-C", str(self.prefix), "rev-parse", "HEAD"])
        observed = revision_receipt["stdout"].strip()
        if revision_receipt["exit"] != 0 or observed != self.expected_revision:
            blocked("scratch prefix revision mismatch: expected %s observed %s"
                    % (self.expected_revision, observed))
        brew = self.prefix / "bin/brew"
        if not brew.is_file():
            blocked("scratch brew executable missing after clone: %s" % brew)
        os.chmod(brew, 0o555)
        (self.prefix / "Cellar").mkdir(mode=0o700, exist_ok=True)
        (self.prefix / "Caskroom").mkdir(mode=0o700, exist_ok=True)
        write_json(self.root / "evidence" / "clone.json", {
            "source": str(self.source),
            "prefix": str(physical(self.prefix)),
            "revision": observed,
            "revision_step": revision_receipt["seq"],
            "clone_step": clone_receipt["seq"],
            "checkout_step": checkout_receipt["seq"],
            "clone_argv": clone_receipt["argv"],
            "clone_cwd": clone_receipt["cwd"],
            "no_hardlinks": "--no-hardlinks" in clone_receipt["argv"],
            "brew_sha256": sha256_file(brew),
            "brew_mode": oct(stat.S_IMODE(brew.stat().st_mode)),
            "step_order": [clone_receipt["seq"], checkout_receipt["seq"],
                           revision_receipt["seq"]],
        })

    def install_portable_ruby(self) -> None:
        source_vendor = self.source / "Library/Homebrew/vendor/portable-ruby"
        source_current = source_vendor / "current"
        if not source_current.exists():
            blocked("portable Ruby current link missing: %s" % source_current)
        source_real = physical(source_current)
        if not is_within(source_real, physical(source_vendor)):
            blocked("portable Ruby resolves outside its vendor directory: %s" % source_real)
        destination_root = self.prefix / "Library/Homebrew/vendor/portable-ruby"
        destination_root.mkdir(parents=True, exist_ok=True)
        destination = destination_root / source_real.name
        if os.path.lexists(str(destination)):
            blocked("portable Ruby destination already exists: %s" % destination)
        shutil.copytree(str(source_real), str(destination), symlinks=True)
        current = destination_root / "current"
        if os.path.lexists(str(current)):
            current.unlink()
        os.symlink(source_real.name, current)
        receipt = self._execute("verify scratch portable Ruby", [str(destination / "bin/ruby"), "-v"],
                                timeout=SHORT_TIMEOUT_SECONDS)
        if receipt["exit"] != 0 or not receipt["stdout"].startswith("ruby " + RUBY_MAJOR):
            blocked("scratch portable Ruby failed to run: %s" % receipt["stderr"][-500:])
        self.portable_ruby = {
            "source": str(source_real),
            "destination": str(destination),
            "current": source_real.name,
            "output": receipt["stdout"].strip(),
        }
        write_json(self.root / "evidence" / "portable-ruby.json", self.portable_ruby)

    def create_stub_core_tap(self) -> None:
        core = self.prefix / "Library/Taps/homebrew/homebrew-core"
        core.mkdir(parents=True, exist_ok=True)
        (core / "README.md").write_text(
            "M13-C stub homebrew-core tap. It is intentionally empty so dependent formula\n"
            "resolution never attempts a network clone of the real core tap.\n"
        )
        steps = [
            ("init stub core tap", ["init", "-q", "--initial-branch=main"]),
            ("add stub core tap", ["add", "README.md"]),
            ("commit stub core tap", ["commit", "-q", "-m", "M13-C stub core tap"]),
        ]
        for purpose, arguments in steps:
            receipt = self._git(purpose, ["-C", str(core)] + arguments)
            if receipt["exit"] != 0:
                blocked("stub core tap setup failed at %s: %s" % (purpose, receipt["stderr"][-500:]))
        head = self._git("record stub core tap revision", ["-C", str(core), "rev-parse", "HEAD"])
        write_json(self.root / "evidence" / "stub-core-tap.json", {
            "path": str(core),
            "revision": head["stdout"].strip(),
            "purpose": "prevent a network homebrew/core clone for depends_on",
        })

    def verify_brew_identity(self) -> dict:
        receipt = self.run_brew("brew version", ["--version"])
        if receipt["exit"] != 0:
            blocked("scratch brew --version failed: %s" % receipt["stderr"][-1000:])
        version_text = receipt["stdout"].strip()
        observed_revision = re.search(r"-g([0-9a-f]{7,40})", version_text)
        if ("Homebrew" not in version_text or observed_revision is None
                or not self.expected_revision.startswith(observed_revision.group(1))):
            blocked("scratch brew is not the pinned revision %s: %s"
                    % (self.expected_revision[:7], version_text[:300]))
        identity = {"version": version_text, "expected_revision": self.expected_revision}
        queries = (("prefix", ["--prefix"]), ("cellar", ["--cellar"]),
                   ("caskroom", ["--caskroom"]), ("repository", ["--repository"]))
        for label, arguments in queries:
            receipt = self.run_brew("brew identity %s" % label, arguments)
            value = receipt["stdout"].strip()
            if receipt["exit"] != 0 or not value:
                blocked("brew identity query failed for %s: %s" % (label, receipt["stderr"][-500:]))
            value_path = physical(Path(value))
            if not is_within(value_path, self.root):
                blocked("brew-reported %s escapes the fixture root: %s" % (label, value_path))
            identity[label] = str(value_path)
        if Path(identity["prefix"]) != physical(self.prefix):
            blocked("brew --prefix is not the scratch prefix: %s" % identity["prefix"])
        if Path(identity["cellar"]) != physical(self.prefix / "Cellar"):
            blocked("brew --cellar is not scratch Cellar: %s" % identity["cellar"])
        if Path(identity["caskroom"]) != physical(self.prefix / "Caskroom"):
            blocked("brew --caskroom is not scratch Caskroom: %s" % identity["caskroom"])
        (self.prefix / "Cellar").mkdir(exist_ok=True)
        (self.prefix / "Caskroom").mkdir(exist_ok=True)
        self.brew_version = version_text
        write_json(self.root / "evidence" / "brew-identity.json", identity)
        return identity

    def build_payloads(self) -> None:
        payloads = self.root / "payloads"
        self.payloads = {}
        for name, versions in FORMULA_VERSIONS.items():
            for version in versions:
                path = payloads / ("%s-%s.tar.gz" % (name, version))
                script = ("#!/bin/sh\necho \"%s %s\"\n" % (name, version)).encode("utf-8")
                digest = write_tar_gz(path, {"%s/%s" % (name, name): (script, 0o755)})
                self.payloads[(name, version)] = {"path": path, "sha256": digest, "kind": "formula"}
        binary_tokens = {
            "m13-cask-binary": ("m13cask", ("1.0.0", "1.1.0")),
            "m13-cask-auto": ("m13auto", ("1.0.0", "2.0.0")),
            "m13-cask-latest": ("m13latest", ("1.0.0",)),
            "m13-cask-delete": ("m13delete", ("1.0.0",)),
            "m13-cask-escape": ("m13escape", ("1.0.0",)),
        }
        for token, (binary_name, versions) in binary_tokens.items():
            for version in versions:
                path = payloads / ("%s-%s.tar.gz" % (token, version))
                script = ("#!/bin/sh\necho \"%s %s\"\n" % (binary_name, version)).encode("utf-8")
                digest = write_tar_gz(path, {binary_name: (script, 0o755)})
                self.payloads[(token, version)] = {
                    "path": path, "sha256": digest, "kind": "binary-cask"}
        for version in ("1.2.3,9", "1.2.4,10"):
            path = payloads / ("m13-cask-comma-%s.tar.gz" % version)
            script = ("#!/bin/sh\necho \"m13comma %s\"\n" % version).encode("utf-8")
            digest = write_tar_gz(path, {"m13comma": (script, 0o755)})
            self.payloads[("m13-cask-comma", version)] = {"path": path, "sha256": digest, "kind": "comma-cask"}
        for version in ("1.0.0", "1.1.0"):
            path = payloads / ("m13-cask-app-%s.zip" % version)
            digest = write_app_zip(path, "M13Test.app", version, "com.example.m13test.app")
            self.payloads[("m13-cask-app", version)] = {"path": path, "sha256": digest, "kind": "app-cask"}
        path = payloads / "m13-cask-appstanza-1.0.0.zip"
        digest = write_app_zip(path, "M13Stanza.app", "1.0.0", "com.example.m13stanza.app")
        self.payloads[("m13-cask-appstanza", "1.0.0")] = {
            "path": path, "sha256": digest, "kind": "app-stanza-cask"}
        self.sentinels = self.write_sentinels()
        write_json(self.root / "evidence" / "payloads.json", {
            "payloads": [{"name": key[0], "version": key[1], "path": str(value["path"]),
                          "sha256": value["sha256"], "kind": value["kind"]}
                         for key, value in sorted(self.payloads.items())],
            "sentinels": self.sentinels,
        })

    def write_sentinels(self) -> dict:
        sentinels = {}
        root = self.root / "sentinels"
        for name, content in (
            ("cask-delete/sentinel-one.txt", "m13 delete-stanza sentinel one\n"),
            ("cask-delete/sentinel-two.txt", "m13 delete-stanza sentinel two\n"),
            ("cask-zap/zap-sentinel.txt", "m13 zap-stanza sentinel must survive\n"),
        ):
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
            os.chmod(path, 0o644)
            sentinels[name] = {"path": str(path), "sha256": sha256_file(path)}
        # Synthetic unsafe target outside the fixture root.  It must never exist: the fixture
        # launch guard classifies it from fresh manager metadata before any mutation launch.
        self.unsafe_target = self.root.parent / (
            "m13-cask-escape-target-" + self.record["nonce"][:12])
        if os.path.lexists(str(self.unsafe_target)):
            blocked("synthetic unsafe-target canary unexpectedly exists: %s" % self.unsafe_target)
        sentinels["cask-escape/unsafe-target"] = {
            "path": str(self.unsafe_target), "sha256": None, "present": False,
            "inside_root": False,
        }
        return sentinels

    def _write_formula(self, name: str, version: str, tap: Path) -> Path:
        payload = self.payloads[(name, version)]
        depends = "m13-lib" if name == "m13-consumer" else None
        broken = name == "m13-broken" and version == "1.0.1"
        text = formula_text(name, version, payload["path"], payload["sha256"],
                            depends=depends, broken_install=broken)
        path = tap / "Formula" / (name + ".rb")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        os.chmod(path, 0o644)
        return path

    def _write_cask(self, token: str, version: str, tap: Path) -> Path:
        if token == "m13-cask-app":
            payload_key = ("m13-cask-app", version)
            binary = None
            app = "M13Test.app"
            extras = {}
        elif token == "m13-cask-appstanza":
            payload_key = ("m13-cask-appstanza", "1.0.0")
            binary = None
            app = "M13Stanza.app"
            extras = {"uninstall": ['uninstall quit: "com.example.m13stanza"']}
        elif token == "m13-cask-delete":
            payload_key = ("m13-cask-delete", "1.0.0")
            binary = "m13delete"
            app = None
            one = self.sentinels["cask-delete/sentinel-one.txt"]["path"]
            two = self.sentinels["cask-delete/sentinel-two.txt"]["path"]
            zap_path = self.sentinels["cask-zap/zap-sentinel.txt"]["path"]
            extras = {
                "uninstall": [
                    "uninstall delete: [",
                    '  "%s",' % one,
                    '  "%s",' % two,
                    "]",
                ],
                "zap": ['zap trash: ["%s"]' % zap_path],
            }
        elif token == "m13-cask-escape":
            payload_key = ("m13-cask-escape", "1.0.0")
            binary = "m13escape"
            app = None
            extras = {
                "uninstall": [
                    "uninstall delete: [",
                    '  "%s",' % self.unsafe_target,
                    "]",
                ],
            }
        elif token == "m13-cask-comma":
            payload_key = ("m13-cask-comma", version)
            binary = "m13comma"
            app = None
            extras = {}
        elif token == "m13-cask-auto":
            payload_key = ("m13-cask-auto", version)
            binary = "m13auto"
            app = None
            extras = {"auto_updates": True}
        elif token == "m13-cask-latest":
            payload_key = ("m13-cask-latest", "1.0.0")
            binary = "m13latest"
            app = None
            extras = {}
        else:
            payload_key = (token, version)
            binary = "m13cask"
            app = None
            extras = {}
        payload = self.payloads[payload_key]
        text = cask_text(token, version, payload["path"], payload["sha256"],
                         binary=binary, app=app, **extras)
        path = tap / "Casks" / (token + ".rb")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        os.chmod(path, 0o644)
        return path

    def write_initial_tap(self) -> None:
        tap = self.root / "tap-src"
        for name, version in INITIAL_FORMULAE.items():
            self._write_formula(name, version, tap)
        for token, version in INITIAL_CASKS.items():
            self._write_cask(token, version, tap)
        steps = [
            ("init fixture tap", ["init", "-q", "--initial-branch=main"]),
            ("add fixture tap", ["add", "-A"]),
            ("commit fixture tap v0", ["commit", "-q", "-m", "v0: M13 fixture tap initial"]),
        ]
        for purpose, arguments in steps:
            receipt = self._git(purpose, ["-C", str(tap)] + arguments)
            if receipt["exit"] != 0:
                blocked("fixture tap setup failed at %s: %s" % (purpose, receipt["stderr"][-800:]))
        self.tap_source = tap
        self.tap_initial_head = self._git(
            "record fixture tap v0", ["-C", str(tap), "rev-parse", "HEAD"]
        )["stdout"].strip()

    def tap_commit(self, message: str) -> str:
        tap = self.root / "tap-src"
        steps = [("add fixture tap change", ["-C", str(tap), "add", "-A"]),
                 ("commit fixture tap change", ["-C", str(tap), "commit", "-q", "-m", message])]
        for purpose, arguments in steps:
            receipt = self._git(purpose, arguments)
            if receipt["exit"] != 0:
                blocked("fixture tap commit failed at %s: %s" % (purpose, receipt["stderr"][-800:]))
        head = self._git("record fixture tap head", ["-C", str(tap), "rev-parse", "HEAD"])["stdout"].strip()
        self.sync_tap_clone(head)
        return head

    def sync_tap_clone(self, expected_head: str) -> None:
        clone = getattr(self, "tap_clone", None)
        if clone is None or not clone.exists():
            return
        receipt = self._git("sync fixture tap clone",
                            ["-C", str(clone), "pull", "--ff-only", "origin", "main"])
        if receipt["exit"] != 0:
            blocked("fixture tap clone sync failed: %s" % receipt["stderr"][-800:])
        observed = self._git("verify fixture tap clone head",
                             ["-C", str(clone), "rev-parse", "HEAD"])["stdout"].strip()
        if observed != expected_head:
            blocked("fixture tap clone head mismatch: %s != %s" % (observed, expected_head))

    def bump_formula(self, name: str, version: str, message: str) -> str:
        self._write_formula(name, version, self.root / "tap-src")
        return self.tap_commit(message)

    def bump_cask(self, token: str, version: str, message: str) -> str:
        self._write_cask(token, version, self.root / "tap-src")
        return self.tap_commit(message)

    def bump_casks(self, bumps: list, message: str) -> str:
        for token, version in bumps:
            self._write_cask(token, version, self.root / "tap-src")
        return self.tap_commit(message)

    def install_tap_and_trust(self) -> None:
        remote = file_url(self.tap_source)
        receipt = self.run_brew("tap fixture tap", ["tap", TAP_NAME, remote])
        if receipt["exit"] != 0:
            blocked("fixture tap installation failed: %s" % receipt["stderr"][-1000:])
        self.tap_clone = self.prefix / "Library/Taps/m13test/homebrew-test"
        if not (self.tap_clone / ".git").exists():
            blocked("fixture tap clone missing: %s" % self.tap_clone)
        origin = self._git("verify fixture tap origin",
                           ["-C", str(self.tap_clone), "remote", "get-url", "origin"])
        if origin["stdout"].strip() != remote:
            blocked("fixture tap origin mismatch: %s != %s" % (origin["stdout"].strip(), remote))
        receipt = self.run_brew("trust fixture tap", ["trust", TAP_NAME])
        if receipt["exit"] != 0:
            blocked("fixture tap trust failed: %s" % receipt["stderr"][-1000:])
        trust_path = self.root / "home/.config/homebrew/trust.json"
        if not trust_path.is_file():
            blocked("fixture trust store missing: %s" % trust_path)
        trust = read_json(trust_path)
        trusted_taps = [str(value).lower() for value in trust.get("trustedtaps", [])]
        if remote.lower() not in trusted_taps:
            blocked("fixture tap is not recorded as trusted: %s" % trust_path)
        info = self.run_brew("verify fixture tap metadata",
                             ["info", "--json=v2", "--cask", CASK_PREFIX + "m13-cask-binary"])
        if info["exit"] != 0:
            blocked("trusted fixture tap metadata is unreadable: %s" % info["stderr"][-800:])
        write_json(self.root / "evidence" / "tap.json", {
            "name": TAP_NAME,
            "remote": remote,
            "clone": str(self.tap_clone),
            "initial_head": self.tap_initial_head,
            "trust_store": str(trust_path),
            "trust": trust,
        })

    def bootstrap_environment(self) -> dict:
        self.setup_fixture_dirs()
        self.prefix = self.root / "prefix"
        self.setup_profile()
        self.env = fixture_environment(self.root, self.prefix)
        self.preflight_controls()
        source_facts = self.verify_source()
        self.clone_prefix()
        self.install_portable_ruby()
        self.create_stub_core_tap()
        identity = self.verify_brew_identity()
        self.build_payloads()
        self.write_initial_tap()
        self.install_tap_and_trust()
        events = self.events
        events.check("environment", "scratch prefix is pinned revision",
                     self._git("environment clone check",
                               ["-C", str(self.prefix), "rev-parse", "HEAD"])["stdout"].strip()
                     == self.expected_revision, self.expected_revision)
        events.check("environment", "brew reports scratch prefix",
                     Path(identity["prefix"]) == physical(self.prefix), identity["prefix"])
        events.check("environment", "stub core tap is present",
                     (self.prefix / "Library/Taps/homebrew/homebrew-core/.git").exists(), None)
        events.check("environment", "fixture tap is trusted",
                     (self.root / "home/.config/homebrew/trust.json").is_file(), None)
        if events.failures:
            blocked("environment construction checks failed; bootstrap proof is incomplete")
        write_json(events.evidence / "report.json", events.report("running"))
        environment = {
            "status": "environment-ready",
            "proof_scope": "bootstrap-only: environment construction and preflight controls; "
                            "zero lifecycle scenarios have run",
            "proof_counts": {"preflight_and_environment_checks": len(
                [check for check in events.checks if check["scenario"] in ("preflight", "environment")]),
                "containment_proofs": self.containment_proofs},
            "fixture": "M13-C homebrew_acceptance",
            "root": str(self.root),
            "source": source_facts,
            "prefix": str(physical(self.prefix)),
            "brew": identity,
            "portable_ruby": self.portable_ruby,
            "profile": str(self.profile),
            "profile_sha256": self.profile_digest,
            "containment_proofs": self.containment_proofs,
            "tap": TAP_NAME,
            "created_at": utc_now(),
        }
        write_json(self.root / "evidence" / "environment.json", environment)
        return environment


    def run_acceptance(self) -> int:
        """Run inside one manifest proof window that spans setup and the last command."""
        print("capturing personal-state manifests before any setup", file=sys.stderr, flush=True)
        try:
            self.before_manifest = snapshot_personal_state(self.root, "before", self.source)
        except HarnessBlocked as error:
            self.events.check("AC-MANIFESTS", "before personal manifest captured", False,
                              str(error))
            self.write_final_reports("failed")
            raise
        fatal = None
        try:
            self.bootstrap_environment()
            for function in SCENARIOS:
                title = (function.__doc__ or function.__name__).strip().split("\n")[0]
                self.events.scenario(function.__name__, title, lambda fn=function: fn(self))
            self.audit_manager_argv("AUDIT")
        except HarnessBlocked as error:
            fatal = error
            self.events.check("BOOTSTRAP", "bootstrap and all scenarios completed", False,
                              str(error))
        except Exception as error:  # unexpected fixture bug; still close the manifest window
            fatal = error
            self.events.check("BOOTSTRAP", "bootstrap and all scenarios completed", False,
                              "%s: %s" % (type(error).__name__, error))
        self.capture_after_manifest()
        status = "passed" if not self.events.failures and fatal is None else "failed"
        self.write_final_reports(status)
        if fatal is not None:
            raise fatal
        return 0 if status == "passed" else 3

    def capture_after_manifest(self) -> None:
        scenario = "AC-MANIFESTS"
        try:
            self.after_manifest = snapshot_personal_state(self.root, "after", self.source)
        except HarnessBlocked as error:
            self.events.check(scenario, "after personal manifest captured", False, str(error))
            return
        self.after_manifest["captured_after_step"] = len(self.events.steps)
        write_json(self.root / "evidence" / "manifests" / "after" / "summary.json",
                   self.after_manifest)
        differences = compare_personal_state(self.before_manifest, self.after_manifest)
        self.events.check(
            scenario,
            "personal trees are byte-identical in contents and recorded metadata",
            not differences, differences,
        )
        before = {tree["path"]: tree for tree in self.before_manifest["trees"]}
        after = {tree["path"]: tree for tree in self.after_manifest["trees"]}
        for path in sorted(before):
            self.events.check(
                scenario, "manifest unchanged: " + path,
                before[path].get("digest") == after.get(path, {}).get("digest"),
                {"before_entries": before[path].get("entry_count"),
                 "after_entries": after.get(path, {}).get("entry_count"),
                 "present": before[path].get("present")},
            )
        self.events.check(
            scenario,
            "manifest window spans before setup through the last recorded command",
            self.before_manifest.get("captured_after_step") == 0
            and len(self.events.steps) > 0
            and self.after_manifest.get("captured_after_step") == len(self.events.steps),
            {"before_step": self.before_manifest.get("captured_after_step"),
             "after_step": self.after_manifest.get("captured_after_step"),
             "total_steps": len(self.events.steps)},
        )

    def write_final_reports(self, status: str) -> None:
        report = self.events.report(status)
        write_json(self.events.evidence / "report.json", report)
        summary = {
            "status": status,
            "label": "fixture evidence, not an acceptance verdict (D-014)",
            "root": str(self.root),
            "report": str(self.events.evidence / "report.json"),
            "manifest_before": (self.before_manifest or {}).get("combined_digest"),
            "manifest_after": (self.after_manifest or {}).get("combined_digest"),
            "manifest_window": {
                "before_captured_before_setup": True,
                "before_step": (self.before_manifest or {}).get("captured_after_step"),
                "after_step": (self.after_manifest or {}).get("captured_after_step"),
                "total_steps": len(self.events.steps),
            },
            "scenarios": self.events.scenario_results,
            "check_count": len(self.events.checks),
            "failure_count": len(self.events.failures),
            "failures": self.events.failures[:20],
            "containment_proofs": self.containment_proofs,
            "proof_counts": {
                "containment_proofs": self.containment_proofs,
                "checks": len(self.events.checks),
                "steps": len(self.events.steps),
            },
            "refused_casks": self.refused_casks,
            "cask_mutations": self.cask_mutations,
            "brew_version": self.brew_version,
            "scratch_prefix": str(self.prefix),
            "note": "orchestrator acceptance is required; this process is not a verdict",
        }
        write_json(self.events.evidence / "summary.json", summary)
        print(json.dumps(summary, indent=2, sort_keys=True))
        print("fixture evidence %s; root retained at %s" % (status, self.root), file=sys.stderr)

    def _brew_ok(self, purpose: str, arguments: list) -> dict:
        receipt = self.run_brew(purpose, arguments)
        if receipt["exit"] != 0:
            blocked("%s failed with exit %s: %s"
                    % (purpose, receipt["exit"], receipt["stderr"][-1200:]))
        return receipt

    def _brew_json(self, purpose: str, arguments: list):
        receipt = self._brew_ok(purpose, arguments)
        try:
            return json.loads(receipt["stdout"])
        except json.JSONDecodeError as error:
            blocked("%s did not emit JSON: %s" % (purpose, error))

    def check_exit(self, scenario: str, purpose: str, receipt: dict, expected) -> bool:
        if isinstance(expected, int):
            expected = (expected,)
        ok = receipt["exit"] in expected
        return self.events.check(
            scenario, purpose + " exit", ok,
            {"expected": list(expected), "observed": receipt["exit"],
             "stderr_tail": receipt["stderr"][-1200:]},
        )

    def installed_kegs(self, name: str) -> list:
        cellar = self.prefix / "Cellar" / name
        if not cellar.is_dir():
            return []
        return sorted(path.name for path in cellar.iterdir()
                      if path.is_dir() and not path.is_symlink())

    def installed_versions(self, name: str) -> list:
        receipt = self.run_brew("list versions " + name, ["list", "--versions", name])
        if receipt["exit"] != 0:
            blocked("brew list --versions failed for %s: %s" % (name, receipt["stderr"][-500:]))
        tokens = receipt["stdout"].split()
        return tokens[1:]

    def cask_info(self, token: str) -> dict:
        data = self._brew_json("cask info " + token,
                               ["info", "--json=v2", "--cask", CASK_PREFIX + token])
        casks = data.get("casks", [])
        if len(casks) != 1:
            blocked("unexpected cask info payload for %s" % token)
        return casks[0]

    def tree_digest(self, path: Path, label: str) -> dict:
        output = self.events.evidence / "digests" / (label + ".jsonl")
        tree = manifest_tree(path, output)
        write_json(self.events.evidence / "digests" / (label + ".json"), tree)
        return tree

    def sentinel_hashes(self) -> dict:
        result = {}
        for key, entry in self.sentinels.items():
            path = Path(entry["path"])
            if not path.is_file():
                result[key] = {"present": False, "sha256": None}
            else:
                result[key] = {"present": True, "sha256": sha256_file(path)}
        return result

    def artifact_uninstall(self, artifacts: list) -> bool:
        return any(isinstance(artifact, dict) and "uninstall" in artifact
                   for artifact in artifacts)

    @staticmethod
    def _artifact_paths(value) -> list:
        """Absolute path strings found anywhere in an artifact value."""
        paths = []
        if isinstance(value, str):
            if value.startswith("/"):
                paths.append(value)
        elif isinstance(value, list):
            for item in value:
                paths.extend(Harness._artifact_paths(item))
        elif isinstance(value, dict):
            for item in value.values():
                paths.extend(Harness._artifact_paths(item))
        return paths

    def _path_within_root(self, value: str) -> bool:
        path = Path(value)
        if os.path.lexists(str(path)):
            return physically_within(path, self.root)
        # A not-yet-created target can still be lexically bound to the physical root.
        return is_within(physical(path), self.root)

    def classify_cask_artifacts(self, artifacts: list) -> dict:
        """Fixture-safe classification of fresh manager ``artifacts`` metadata.

        This is fixture policy, not a product verdict.  A cask is eligible for this harness's
        synthetic lifecycle only when it has artifacts, no uninstall/zap stanza, only the
        artifact kinds this fixture stages, and every absolute target is inside the scratch root.
        """
        allowed_kinds = {"binary", "app", "command_wrapper"}
        reasons = []
        kinds = set()
        targets = []
        for artifact in artifacts:
            if not isinstance(artifact, dict):
                reasons.append("malformedArtifact")
                continue
            keys = set(artifact) - {"target"}
            kinds |= keys
            if "uninstall" in keys:
                reasons.append("uninstallStanza")
            if "zap" in keys:
                reasons.append("zapStanza")
            for key in sorted(keys - allowed_kinds - {"uninstall", "zap"}):
                reasons.append("unsupportedArtifact:" + key)
            target = artifact.get("target")
            if isinstance(target, str) and target.startswith("/"):
                targets.append(target)
            for key in ("uninstall", "zap", "app", "binary", "command_wrapper"):
                if key in artifact:
                    targets.extend(self._artifact_paths(artifact[key]))
        outside = sorted({path for path in targets
                          if not self._path_within_root(path)})
        if outside:
            reasons.insert(0, "unsafeTarget")
        if not artifacts:
            reasons.append("noArtifacts")
        return {
            "eligible": not reasons,
            "reasons": reasons,
            "kinds": sorted(kinds),
            "targets": sorted(set(targets)),
            "unsafe_targets": outside,
            "label": "fixture launch-guard policy, not a product mutation eligibility verdict",
        }

    def guard_cask_mutation(self, action: str, token: str) -> dict:
        """Consume fresh manager metadata and refuse before launching a non-allowed cask.

        ``action`` is ``upgrade`` or ``uninstall``.  The fresh ``info`` step is recorded; no
        upgrade/uninstall process is launched when classification refuses the cask.
        """
        if action not in ("upgrade", "uninstall"):
            blocked("fixture launch guard only handles upgrade/uninstall: %s" % action)
        purposes = {"upgrade": "guard fresh info before cask upgrade",
                    "uninstall": "guard fresh info before cask uninstall"}
        info_receipt = self.run_brew(purposes[action] + " " + token,
                                     ["info", "--json=v2", "--cask", CASK_PREFIX + token])
        if info_receipt["exit"] != 0:
            blocked("fresh cask info failed before %s %s: %s"
                    % (action, token, info_receipt["stderr"][-800:]))
        try:
            payload = json.loads(info_receipt["stdout"])
        except json.JSONDecodeError as error:
            blocked("fresh cask info was not JSON before %s %s: %s" % (action, token, error))
        casks = payload.get("casks", [])
        if len(casks) != 1:
            blocked("fresh cask info did not identify exactly one cask for %s" % token)
        info = casks[0]
        if info.get("token") != token or info.get("full_token") != CASK_PREFIX + token:
            blocked("fresh cask info identity mismatch for %s" % token)
        artifacts = info.get("artifacts", [])
        classification = self.classify_cask_artifacts(artifacts)
        record = {
            "token": token,
            "action": action,
            "fresh_info_step": info_receipt["seq"],
            "fresh_info_at": info_receipt["at"],
            "installed": info.get("installed"),
            "version": info.get("version"),
            "artifacts_sha256": sha256_bytes(
                json.dumps(artifacts, sort_keys=True).encode("utf-8")),
            "classification": classification,
            "launched": False,
            "argv": None,
            "label": "fixture launch guard; harness launches only",
        }
        if not classification["eligible"]:
            record["decision"] = "fixture-refused"
            self.refused_casks.append(record)
            return record
        record["decision"] = "fixture-allowed"
        if action == "upgrade":
            arguments = ["upgrade", "--cask", "--yes", CASK_PREFIX + token]
        else:
            arguments = ["uninstall", "--cask", token]
        receipt = self._launch_brew("%s cask %s" % (action, token), arguments)
        record.update({"launched": True, "argv": receipt["argv"], "receipt_step": receipt["seq"],
                       "exit": receipt["exit"]})
        self.cask_mutations.append(record)
        if receipt["exit"] != 0:
            blocked("%s cask %s failed with exit %s: %s"
                    % (action, token, receipt["exit"], receipt["stderr"][-1200:]))
        return record

    def audit_manager_argv(self, scenario: str) -> dict:
        """Audit the harness's own scratch-manager launches over the whole run.

        Descendant processes are not enumerated; the claim is limited to argv this harness
        launched.  Refused casks must have no upgrade/uninstall launch anywhere in the run.
        """
        brew = str(self.prefix / "bin/brew") if self.prefix else ""
        refused = {record["token"] for record in self.refused_casks}
        launches = []
        for step in self.events.steps:
            argv = step["argv"]
            if brew not in argv:
                continue
            index = argv.index(brew)
            arguments = argv[index + 1:]
            action = next((arg for arg in arguments if not arg.startswith("-")), None)
            launches.append({"step": step["seq"], "purpose": step["purpose"],
                             "action": action, "arguments": arguments,
                             "exit": step["exit"]})
        mutation_launches = [launch for launch in launches
                             if launch["action"] in ("upgrade", "uninstall")]
        refused_launches = [launch for launch in mutation_launches
                            if any(arg.rsplit("/", 1)[-1] in refused
                                   for arg in launch["arguments"])]
        guarded_steps = {record.get("receipt_step") for record in self.cask_mutations}
        unguarded = [launch for launch in mutation_launches
                     if "--formula" not in launch["arguments"]
                     and launch["step"] not in guarded_steps]
        forbidden_tokens = {"sudo", "zap", "--zap", "--ignore-dependencies", "--force",
                            "--require-sha", "--quarantine"}
        forbidden = [launch for launch in launches
                     if forbidden_tokens & set(launch["arguments"])
                     or launch["action"] in ("zap", "sudo")]
        self.events.check(
            scenario,
            "full scratch manager argv audit: no upgrade/uninstall launch of a refused cask",
            not refused_launches, refused_launches,
        )
        self.events.check(
            scenario,
            "full scratch manager argv audit: every cask mutation came from the launch guard",
            not unguarded, unguarded,
        )
        self.events.check(
            scenario,
            "full scratch manager argv audit: no sudo, zap, force or ignore-dependencies launch",
            not forbidden, forbidden,
        )
        audit = {
            "brew": brew,
            "launch_count": len(launches),
            "mutation_launch_count": len(mutation_launches),
            "refused_tokens": sorted(refused),
            "refused_launch_count": len(refused_launches),
            "guarded_mutation_count": len(self.cask_mutations),
            "unguarded_cask_mutations": unguarded,
            "forbidden_launches": forbidden,
            "launches": launches,
            "label": "harness launches only; descendant processes are not enumerated",
        }
        write_json(self.events.evidence / "manager-argv-audit.json", audit)
        return audit


SCENARIOS = []


def scenario(function):
    SCENARIOS.append(function)
    return function


@scenario
def ac_environment(harness: Harness) -> None:
    """Re-verify isolation, pinned source, closed environment and contained manager calls."""
    h = harness
    s = "ENV"
    preflight = [check for check in h.events.checks if check["scenario"] == "preflight"]
    h.events.check(s, "all seatbelt preflight controls passed",
                   len(preflight) >= 10 and all(check["ok"] for check in preflight),
                   [check["name"] for check in preflight if not check["ok"]])
    profile_text = h.profile.read_text()
    h.events.check(s, "profile denies all networking before the scoped exception",
                   "(deny network*)" in profile_text, None)
    h.events.check(s, "profile denies writes outside the fixture root",
                   "(deny file-write*)" in profile_text, None)
    h.events.check(s, "profile scopes Unix sockets to fixture tmp",
                   '(allow network* network-outbound (subpath "%s"))'
                   % str(physical(h.root / "tmp")) in profile_text, None)
    h.events.check(s, "profile write allowlist is exactly the fixture root and /dev/null",
                   '    (literal "/dev/null")' in profile_text
                   and '(subpath "%s")' % str(physical(h.root)) in profile_text
                   and profile_text.count("(allow file-write*") == 1
                   and "/private/var/tmp" not in profile_text
                   and "/private/tmp" not in profile_text
                   and "sh-thd" not in profile_text, profile_text)
    h.events.check(s, "profile has no system temporary write exception",
                   all(token not in profile_text for token in
                       ("/private/tmp", "/var/tmp", "/tmp/", "sh-thd", "mkstemp")), None)
    denials = [check for check in preflight if "denies" in check["name"]]
    h.events.check(
        s, "every denial control carries an explicit EPERM/EACCES errno",
        len(denials) >= 6 and all(
            isinstance(check.get("detail"), dict)
            and isinstance(check["detail"].get("probe"), dict)
            and check["detail"]["probe"].get("errno") in (errno.EPERM, errno.EACCES)
            for check in denials
        ),
        [{"name": check["name"], "detail": check.get("detail")} for check in denials],
    )
    h.events.check(s, "synthetic canary is outside the fixture root",
                   h.canary_root is not None
                   and not physically_within(h.canary_root, h.root)
                   and physically_within(h.canary_root, h.root.parent), str(h.canary_root))
    h.events.check(s, "profile digest is stable",
                   sha256_file(h.profile) == h.profile_digest, h.profile_digest)
    head = h._git("environment prefix revision", ["-C", str(h.prefix), "rev-parse", "HEAD"])
    h.events.check(s, "scratch prefix is at the pinned revision",
                   head["stdout"].strip() == h.expected_revision, head["stdout"].strip())
    brew_stat = (h.prefix / "bin/brew").stat()
    h.events.check(s, "scratch brew file is read-only for inherited-sandbox protocol",
                   not (stat.S_IMODE(brew_stat.st_mode) & stat.S_IWUSR), oct(stat.S_IMODE(brew_stat.st_mode)))
    h.events.check(s, "scratch portable Ruby is 4.x",
                   "ruby " + RUBY_MAJOR in h.portable_ruby["output"], h.portable_ruby["output"])
    h.events.check(s, "fixture PATH cannot resolve personal brew",
                   "/opt/homebrew" not in h.env["PATH"], h.env["PATH"])
    h.events.check(s, "fixture HOME and caches are inside root",
                   all(physically_within(Path(h.env[key]), h.root)
                       for key in ("HOME", "TMPDIR", "HOMEBREW_CACHE", "HOMEBREW_LOGS", "HOMEBREW_TEMP")),
                   {key: h.env[key] for key in ("HOME", "TMPDIR", "HOMEBREW_CACHE",
                                                "HOMEBREW_LOGS", "HOMEBREW_TEMP")})
    h.events.check(s, "no inherited HOMEBREW_PREFIX/CELLAR/CASKROOM overrides",
                   all(key not in h.env for key in ("HOMEBREW_PREFIX", "HOMEBREW_CELLAR",
                                                    "HOMEBREW_CASKROOM")), None)
    non_contained = []
    non_egress = []
    for step in h.events.steps:
        if not step["sandboxed"]:
            non_contained.append({"purpose": step["purpose"], "reason": "unsandboxed"})
        if not step.get("cwd") or not physically_within(Path(step["cwd"]), h.root):
            non_egress.append({"purpose": step["purpose"], "cwd": step.get("cwd")})
        if step.get("profile_sha256") != h.profile_digest:
            non_egress.append({"purpose": step["purpose"],
                               "profile_sha256": step.get("profile_sha256")})
        if str(h.prefix / "bin/brew") not in step["argv"]:
            continue
        if step.get("inherited_sandbox_fd") != 198:
            non_contained.append({"purpose": step["purpose"], "exit": step["exit"],
                                  "sandboxed": step["sandboxed"],
                                  "fd": step.get("inherited_sandbox_fd")})
    h.events.check(s, "bootstrap brew calls ran in outer seatbelt with fd 198",
                   not non_contained, non_contained[:10])
    h.events.check(s, "bootstrap commands used a scratch cwd and the fixed profile digest",
                   not non_egress, non_egress[:10])
    h.events.check(s, "scratch prefix is not the personal manager",
                   physical(h.prefix) != Path("/opt/homebrew"), str(h.prefix))
    h.events.check(s, "stub core tap exists", (h.prefix / "Library/Taps/homebrew/homebrew-core/.git").is_dir(), None)
    h.events.check(s, "fixture tap trust store exists", (h.root / "home/.config/homebrew/trust.json").is_file(), None)
    h.events.check(s, "manifest roots include personal prefix, /Applications and source",
                   set(str(path) for path in personal_manifest_roots(h.source))
                   >= {"/opt/homebrew", "/Applications", str(h.source)}, None)


@scenario
def ac_formula_lifecycle(harness: Harness) -> None:
    """Formula install, outdated JSON, upgrade, multi-keg residue, uninstall and sentinels."""
    h = harness
    s = "AC-FORMULA"
    h._brew_ok("install m13-old 1.0.0", ["install", "--yes", FORMULA_PREFIX + "m13-old"])
    h.events.check(s, "m13-old 1.0.0 keg exists", h.installed_kegs("m13-old") == ["1.0.0"],
                   h.installed_kegs("m13-old"))
    link = h.prefix / "bin/m13-old"
    h.events.check(s, "m13-old bin link targets 1.0.0",
                   link.is_symlink() and "1.0.0" in os.readlink(str(link)),
                   os.readlink(str(link)) if link.is_symlink() else None)
    run = h._execute("run m13-old 1.0.0", [str(link)], timeout=SHORT_TIMEOUT_SECONDS)
    h.events.check(s, "installed m13-old runs from scratch prefix",
                   run["exit"] == 0 and run["stdout"].strip() == "m13-old 1.0.0",
                   {"exit": run["exit"], "stdout": run["stdout"].strip()})

    h._brew_ok("install m13-sentinel 1.0.0", ["install", "--yes", FORMULA_PREFIX + "m13-sentinel"])
    h.bump_formula("m13-sentinel", "1.0.1", "v1: bump m13-sentinel")
    h._brew_ok("upgrade m13-sentinel to two kegs",
               ["upgrade", "--formula", "--yes", FORMULA_PREFIX + "m13-sentinel"])
    h.events.check(s, "sentinel formula holds two kegs",
                   h.installed_kegs("m13-sentinel") == ["1.0.0", "1.0.1"],
                   h.installed_kegs("m13-sentinel"))
    sentinel_before = h.tree_digest(h.prefix / "Cellar/m13-sentinel", "sentinel-formula-before")
    h.events.check(s, "sentinel keg contents captured before target lifecycle",
                   sentinel_before["present"] and sentinel_before["entry_count"] > 2,
                   sentinel_before)

    h.bump_formula("m13-old", "1.2.0", "v2: bump m13-old to 1.2.0")
    outdated = h._brew_json("outdated formula JSON", ["outdated", "--json=v2", "--formula"])
    records = [item for item in outdated.get("formulae", [])
               if str(item.get("name", "")).endswith("m13-old")]
    h.events.check(s, "outdated formula record exists for m13-old", len(records) == 1,
                   [item.get("name") for item in outdated.get("formulae", [])])
    if records:
        record = records[0]
        h.events.check(s, "outdated record reports the full tap name",
                       record.get("name") == FORMULA_PREFIX + "m13-old", record.get("name"))
        h.events.check(s, "outdated installed_versions is 1.0.0",
                       record.get("installed_versions") == ["1.0.0"],
                       record.get("installed_versions"))
        h.events.check(s, "outdated current_version is 1.2.0",
                       record.get("current_version") == "1.2.0", record.get("current_version"))
        h.events.check(s, "outdated record is not pinned",
                       record.get("pinned") is False, record.get("pinned"))

    h._brew_ok("upgrade m13-old to 1.2.0",
               ["upgrade", "--formula", "--yes", FORMULA_PREFIX + "m13-old"])
    h.events.check(s, "upgrade links 1.2.0 and retains old 1.0.0 keg",
                   h.installed_kegs("m13-old") == ["1.0.0", "1.2.0"],
                   h.installed_kegs("m13-old"))
    h.events.check(s, "upgraded bin link targets 1.2.0",
                   link.is_symlink() and "1.2.0" in os.readlink(str(link)),
                   os.readlink(str(link)) if link.is_symlink() else None)
    sentinel_after_upgrade = h.tree_digest(h.prefix / "Cellar/m13-sentinel",
                                           "sentinel-formula-after-upgrade")
    h.events.check(s, "sentinel kegs are byte-identical after target upgrade",
                   sentinel_before["digest"] == sentinel_after_upgrade["digest"],
                   {"before": sentinel_before["digest"], "after": sentinel_after_upgrade["digest"]})

    uninstall = h._brew_ok("uninstall m13-old linked keg", ["uninstall", "--formula", "m13-old"])
    h.events.check(s, "uninstall removes only the linked 1.2.0 keg",
                   h.installed_kegs("m13-old") == ["1.0.0"], h.installed_kegs("m13-old"))
    h.events.check(s, "uninstall reports a remaining installed keg honestly",
                   "still installed" in (uninstall["stdout"] + uninstall["stderr"]).lower(),
                   (uninstall["stdout"] + uninstall["stderr"])[-1500:])
    h.events.check(s, "old installed-but-unlinked keg remains listed",
                   "1.0.0" in h.installed_versions("m13-old"),
                   h.installed_versions("m13-old"))
    h.events.check(s, "bin link is not relinked to the remaining keg",
                   not os.path.lexists(str(link)),
                   os.readlink(str(link)) if link.is_symlink() else None)
    sentinel_after_uninstall = h.tree_digest(h.prefix / "Cellar/m13-sentinel",
                                             "sentinel-formula-after-uninstall")
    h.events.check(s, "sentinel kegs are byte-identical after target uninstall",
                   sentinel_before["digest"] == sentinel_after_uninstall["digest"],
                   {"before": sentinel_before["digest"], "after": sentinel_after_uninstall["digest"]})
    h.formula_sentinel_digest = sentinel_before["digest"]


@scenario
def ac_formula_refusals(harness: Harness) -> None:
    """Pinned, broken-update and dependent-uninstall refusals with raw nonzero receipts."""
    h = harness
    s = "AC-FORMULA-REFUSALS"
    h._brew_ok("install m13-pinned 1.0.0", ["install", "--yes", FORMULA_PREFIX + "m13-pinned"])
    h._brew_ok("pin m13-pinned", ["pin", "m13-pinned"])
    pinned_list = h._brew_ok("list pinned", ["list", "--pinned"])
    h.events.check(s, "manager reports m13-pinned pinned",
                   "m13-pinned" in pinned_list["stdout"], pinned_list["stdout"].strip())
    h.bump_formula("m13-pinned", "1.0.1", "v3: bump pinned formula")
    outdated = h._brew_json("outdated pinned formula JSON",
                            ["outdated", "--json=v2", "--formula"])
    records = [item for item in outdated.get("formulae", [])
               if str(item.get("name", "")).endswith("m13-pinned")]
    h.events.check(s, "outdated record exposes pinned state", len(records) == 1, records)
    if records:
        record = records[0]
        h.events.check(s, "outdated record is pinned at 1.0.0",
                       record.get("pinned") is True
                       and str(record.get("pinned_version")) == "1.0.0",
                       {"pinned": record.get("pinned"),
                        "pinned_version": record.get("pinned_version")})
    refusal = h.run_brew("upgrade pinned m13-pinned",
                         ["upgrade", "--formula", "--yes", FORMULA_PREFIX + "m13-pinned"])
    h.check_exit(s, "pinned upgrade refusal", refusal, (1,))
    h.events.check(s, "pinned refusal stderr is the manager's exact pinned refusal",
                   "Error: Not upgrading 1 pinned package" in refusal["stderr"],
                   refusal["stderr"][-1500:])
    h.events.check(s, "pinned keg remains 1.0.0 with no 1.0.1",
                   h.installed_kegs("m13-pinned") == ["1.0.0"],
                   h.installed_kegs("m13-pinned"))
    unpin = h._brew_ok("unpin m13-pinned", ["unpin", "m13-pinned"])
    h.events.check(s, "unpin restores non-pinned state",
                   "m13-pinned" not in unpin["stdout"] and
                   "m13-pinned" not in h._brew_ok("list pinned after unpin",
                                                  ["list", "--pinned"])["stdout"], None)

    h._brew_ok("install m13-broken 1.0.0", ["install", "--yes", FORMULA_PREFIX + "m13-broken"])
    broken_link = h.prefix / "bin/m13-broken"
    h.events.check(s, "m13-broken 1.0.0 link is present before the broken update",
                   broken_link.is_symlink() and "1.0.0" in os.readlink(str(broken_link)),
                   os.readlink(str(broken_link)) if broken_link.is_symlink() else None)
    h.bump_formula("m13-broken", "1.0.1", "v4: break m13-broken update")
    broken = h.run_brew("upgrade broken m13-broken",
                        ["upgrade", "--formula", "--yes", FORMULA_PREFIX + "m13-broken"])
    h.check_exit(s, "broken update refusal", broken, (1,))
    h.events.check(s, "broken update output shows the failing false install command",
                   "==> false" in broken["stdout"] and "01.false.log" in broken["stdout"],
                   broken["stdout"][-2000:])
    h.events.check(s, "broken update leaves only the old keg",
                   h.installed_kegs("m13-broken") == ["1.0.0"],
                   h.installed_kegs("m13-broken"))
    h.events.check(s, "broken update retains the old 1.0.0 bin link",
                   broken_link.is_symlink() and "1.0.0" in os.readlink(str(broken_link)),
                   {"link": os.readlink(str(broken_link)) if broken_link.is_symlink() else None,
                    "kegs": h.installed_kegs("m13-broken")})

    h._brew_ok("install m13-lib 1.0.0", ["install", "--yes", FORMULA_PREFIX + "m13-lib"])
    h._brew_ok("install m13-consumer 1.0.0", ["install", "--yes", FORMULA_PREFIX + "m13-consumer"])
    h.events.check(s, "dependent consumer installed with library",
                   h.installed_kegs("m13-lib") == ["1.0.0"]
                   and h.installed_kegs("m13-consumer") == ["1.0.0"],
                   {"lib": h.installed_kegs("m13-lib"),
                    "consumer": h.installed_kegs("m13-consumer")})
    dependent = h.run_brew("dependent uninstall refusal",
                           ["uninstall", "--formula", "m13-lib"])
    h.check_exit(s, "dependent uninstall refusal", dependent, (1,))
    h.events.check(s, "dependent refusal names the requiring formula",
                   "required by" in dependent["stderr"].lower()
                   and "m13-consumer" in dependent["stderr"],
                   dependent["stderr"][-1500:])
    h.events.check(s, "dependent refusal leaves both kegs installed",
                   h.installed_kegs("m13-lib") == ["1.0.0"]
                   and h.installed_kegs("m13-consumer") == ["1.0.0"],
                   {"lib": h.installed_kegs("m13-lib"),
                    "consumer": h.installed_kegs("m13-consumer")})
    h.events.check(s, "no --ignore-dependencies retry was attempted",
                   all("--ignore-dependencies" not in step["argv"]
                       for step in h.events.steps), None)


@scenario
def ac_cask_binary(harness: Harness) -> None:
    """Binary cask install, populated outdated JSON, upgrade and clean uninstall."""
    h = harness
    s = "AC-CASK-BINARY"
    token = "m13-cask-binary"
    h._brew_ok("install binary cask 1.0.0",
               ["install", "--cask", "--yes", CASK_PREFIX + token])
    staged = h.prefix / "Caskroom" / token / "1.0.0"
    h.events.check(s, "binary cask staged 1.0.0", staged.is_dir(), str(staged))
    listing = h._brew_ok("list binary cask verbose", ["list", "--verbose", "--cask", token])
    h.events.check(s, "list --verbose prints staged Caskroom path",
                   str(staged) in listing["stdout"], listing["stdout"][-1200:])
    link = h.prefix / "bin/m13cask"
    h.events.check(s, "binary cask creates prefix bin symlink",
                   link.is_symlink() and str(staged) in os.path.realpath(str(link)),
                   os.readlink(str(link)) if link.is_symlink() else None)
    run = h._execute("run binary cask", [str(link)], timeout=SHORT_TIMEOUT_SECONDS)
    h.events.check(s, "installed cask binary runs", run["exit"] == 0
                   and run["stdout"].strip() == "m13cask 1.0.0",
                   {"exit": run["exit"], "stdout": run["stdout"].strip()})
    info = h.cask_info(token)
    h.events.check(s, "cask info installed is 1.0.0", info.get("installed") == "1.0.0",
                   info.get("installed"))

    h.bump_cask(token, "1.1.0", "v5: bump binary cask")
    outdated = h._brew_json("outdated binary cask JSON", ["outdated", "--json=v2", "--cask"])
    records = [item for item in outdated.get("casks", []) if item.get("name") == token]
    h.events.check(s, "outdated cask record exists", len(records) == 1,
                   [item.get("name") for item in outdated.get("casks", [])])
    if records:
        record = records[0]
        h.events.check(s, "outdated cask name is the bare token", record.get("name") == token,
                       record.get("name"))
        h.events.check(s, "outdated cask install_versions is 1.0.0",
                       str(record.get("installed_versions")) in ("['1.0.0']", '["1.0.0"]'),
                       record.get("installed_versions"))
        h.events.check(s, "outdated cask current_version is 1.1.0",
                       record.get("current_version") == "1.1.0", record.get("current_version"))
        h.events.check(s, "outdated cask not pinned", record.get("pinned") is False,
                       record.get("pinned"))
    guarded_upgrade = h.guard_cask_mutation("upgrade", token)
    h.events.check(s, "binary cask upgrade was launched by the fixture guard",
                   guarded_upgrade["decision"] == "fixture-allowed"
                   and guarded_upgrade["launched"] is True, guarded_upgrade)
    info = h.cask_info(token)
    h.events.check(s, "cask info installed is 1.1.0", info.get("installed") == "1.1.0",
                   info.get("installed"))
    h.events.check(s, "binary link targets upgraded staged file",
                   link.is_symlink() and "/1.1.0/" in os.path.realpath(str(link)),
                   os.readlink(str(link)) if link.is_symlink() else None)
    run = h._execute("run upgraded binary cask", [str(link)], timeout=SHORT_TIMEOUT_SECONDS)
    h.events.check(s, "upgraded cask binary reports 1.1.0", run["exit"] == 0
                   and run["stdout"].strip() == "m13cask 1.1.0",
                   {"exit": run["exit"], "stdout": run["stdout"].strip()})

    guarded_uninstall = h.guard_cask_mutation("uninstall", token)
    h.events.check(s, "binary cask uninstall was launched by the fixture guard",
                   guarded_uninstall["decision"] == "fixture-allowed"
                   and guarded_uninstall["launched"] is True, guarded_uninstall)
    h.events.check(s, "Caskroom token directory absent after uninstall",
                   not os.path.lexists(str(h.prefix / "Caskroom" / token)), None)
    h.events.check(s, "binary cask bin symlink absent after uninstall",
                   not os.path.lexists(str(link)), None)
    h.events.check(s, "cask info installed is null after uninstall",
                   h.cask_info(token).get("installed") is None, h.cask_info(token).get("installed"))


@scenario
def ac_cask_app(harness: Harness) -> None:
    """No-stanza app cask: scratch appdir, staged symlink, upgrade, clean removal."""
    h = harness
    s = "AC-CASK-APP"
    token = "m13-cask-app"
    appdir = h.root / "appdir"
    app = appdir / "M13Test.app"
    h._brew_ok("install no-stanza app cask",
               ["install", "--cask", "--yes", "--appdir=" + str(appdir), CASK_PREFIX + token])
    staged = h.prefix / "Caskroom" / token / "1.0.0"
    staged_app = staged / "M13Test.app"
    h.events.check(s, "app cask stages a symlink to the scratch app",
                   staged_app.is_symlink() and physical(staged_app) == physical(app),
                   {"staged": str(staged_app), "target": os.readlink(str(staged_app))
                    if staged_app.is_symlink() else None, "expected": str(app)})
    h.events.check(s, "scratch app bundle exists", app.is_dir(), str(app))
    h.events.check(s, "real /Applications app is absent", not os.path.lexists("/Applications/M13Test.app"),
                   None)
    listing = h._brew_ok("list app cask verbose", ["list", "--verbose", "--cask", token])
    h.events.check(s, "app cask list prints staged bundle path",
                   str(staged_app) in listing["stdout"], listing["stdout"][-1200:])
    h.events.check(s, "app cask info installed is 1.0.0",
                   h.cask_info(token).get("installed") == "1.0.0", h.cask_info(token).get("installed"))

    h.bump_cask(token, "1.1.0", "v6: bump no-stanza app cask")
    outdated = h._brew_json("outdated app cask JSON", ["outdated", "--json=v2", "--cask"])
    records = [item for item in outdated.get("casks", []) if item.get("name") == token]
    h.events.check(s, "outdated app cask record exists", len(records) == 1, records)
    if records:
        h.events.check(s, "outdated app cask current_version is 1.1.0",
                       records[0].get("current_version") == "1.1.0", records[0])
    guarded_upgrade = h.guard_cask_mutation("upgrade", token)
    h.events.check(s, "app cask upgrade was launched by the fixture guard",
                   guarded_upgrade["decision"] == "fixture-allowed"
                   and guarded_upgrade["launched"] is True, guarded_upgrade)
    info = h.cask_info(token)
    h.events.check(s, "app cask info installed is 1.1.0", info.get("installed") == "1.1.0",
                   info.get("installed"))
    h.events.check(s, "upgrade keeps the saved scratch appdir", app.is_dir(), str(app))
    h.events.check(s, "real /Applications app stays absent after upgrade",
                   not os.path.lexists("/Applications/M13Test.app"), None)
    version_file = app / "Contents/Resources/version.txt"
    h.events.check(s, "scratch app contents were upgraded to 1.1.0",
                   version_file.is_file() and "1.1.0" in version_file.read_text(),
                   version_file.read_text() if version_file.is_file() else None)
    staged_new = h.prefix / "Caskroom" / token / "1.1.0/M13Test.app"
    h.events.check(s, "upgraded staged app is a symlink into scratch appdir",
                   staged_new.is_symlink() and physical(staged_new) == physical(app),
                   os.readlink(str(staged_new)) if staged_new.is_symlink() else None)

    guarded_uninstall = h.guard_cask_mutation("uninstall", token)
    h.events.check(s, "app cask uninstall was launched by the fixture guard",
                   guarded_uninstall["decision"] == "fixture-allowed"
                   and guarded_uninstall["launched"] is True, guarded_uninstall)
    h.events.check(s, "scratch app removed on uninstall", not os.path.lexists(str(app)), None)
    h.events.check(s, "Caskroom token directory removed on uninstall",
                   not os.path.lexists(str(h.prefix / "Caskroom" / token)), None)
    h.events.check(s, "real /Applications remains untouched", not os.path.lexists("/Applications/M13Test.app"),
                   None)


@scenario
def ac_cask_variants(harness: Harness) -> None:
    """auto_updates, :latest and comma-version casks against real outdated JSON."""
    h = harness
    s = "AC-CASK-VARIANTS"
    for token in ("m13-cask-auto", "m13-cask-latest", "m13-cask-comma"):
        h._brew_ok("install variant cask " + token,
                   ["install", "--cask", "--yes", CASK_PREFIX + token])
    auto = h.cask_info("m13-cask-auto")
    latest = h.cask_info("m13-cask-latest")
    comma = h.cask_info("m13-cask-comma")
    h.events.check(s, "auto_updates cask reports true", auto.get("auto_updates") is True,
                   auto.get("auto_updates"))
    h.events.check(s, ":latest cask version and installed are latest",
                   latest.get("version") == "latest" and latest.get("installed") == "latest",
                   {"version": latest.get("version"), "installed": latest.get("installed")})
    h.events.check(s, "comma cask version and installed preserve CSV form",
                   comma.get("version") == "1.2.3,9" and comma.get("installed") == "1.2.3,9",
                   {"version": comma.get("version"), "installed": comma.get("installed")})
    h.events.check(s, "refusal casks are not installed during variant probe",
                   not os.path.lexists(str(h.prefix / "Caskroom/m13-cask-appstanza"))
                   and not os.path.lexists(str(h.prefix / "Caskroom/m13-cask-delete"))
                   and not os.path.lexists(str(h.prefix / "Caskroom/m13-cask-escape")), None)

    h.bump_casks([("m13-cask-auto", "2.0.0"), ("m13-cask-comma", "1.2.4,10")],
                 "v7: bump auto and comma casks")

    def names(arguments):
        data = h._brew_json("outdated variants " + " ".join(arguments),
                            ["outdated", "--json=v2", "--cask"] + arguments)
        return sorted(item.get("name") for item in data.get("casks", []))

    plain = names([])
    greedy = names(["--greedy"])
    greedy_auto = names(["--greedy-auto-updates"])
    greedy_latest = names(["--greedy-latest"])
    h.events.check(s, "plain outdated detects only the comma cask", plain == ["m13-cask-comma"], plain)
    h.events.check(s, "plain outdated skips auto_updates and :latest", "m13-cask-auto" not in plain
                   and "m13-cask-latest" not in plain, plain)
    h.events.check(s, "--greedy includes auto_updates and comma",
                   greedy == ["m13-cask-auto", "m13-cask-comma"], greedy)
    h.events.check(s, "--greedy-auto-updates includes auto_updates and comma",
                   greedy_auto == ["m13-cask-auto", "m13-cask-comma"], greedy_auto)
    h.events.check(s, "--greedy-latest includes comma but not :latest",
                   greedy_latest == ["m13-cask-comma"], greedy_latest)
    h.events.check(s, "comma versions are manager-comparable",
                   "m13-cask-comma" in plain, plain)
    write_json(h.events.evidence / "outdated-variants.json", {
        "plain": plain, "greedy": greedy, "greedy_auto_updates": greedy_auto,
        "greedy_latest": greedy_latest,
    })


@scenario
def ac_cask_refusals(harness: Harness) -> None:
    """Non-allowed casks are classified from fresh info and refused before a mutation launch."""
    h = harness
    s = "AC-CASK-REFUSALS"
    appdir = h.root / "appdir"
    sentinel_before = h.sentinel_hashes()
    expectations = {
        "m13-cask-appstanza": {
            "install": ["install", "--cask", "--yes", "--appdir=" + str(appdir),
                        CASK_PREFIX + "m13-cask-appstanza"],
            "reasons": {"uninstallStanza"},
            "artifacts": "uninstall quit stanza plus an app artifact",
        },
        "m13-cask-delete": {
            "install": ["install", "--cask", "--yes", CASK_PREFIX + "m13-cask-delete"],
            "reasons": {"uninstallStanza", "zapStanza"},
            "artifacts": "uninstall delete stanza plus a zap trash stanza",
        },
        "m13-cask-escape": {
            "install": ["install", "--cask", "--yes", CASK_PREFIX + "m13-cask-escape"],
            "reasons": {"unsafeTarget", "uninstallStanza"},
            "artifacts": "uninstall delete target outside the fixture root (synthetic, absent)",
        },
    }
    for token, expectation in expectations.items():
        install = h._brew_ok("install refusal cask " + token, expectation["install"])
        info = h.cask_info(token)
        artifacts = info.get("artifacts", [])
        h.events.check(s, token + " is installed before the fixture refusal",
                       info.get("installed") == "1.0.0", info.get("installed"))
        h.events.check(s, token + " metadata exposes an uninstall stanza",
                       h.artifact_uninstall(artifacts), artifacts)
        h.events.check(s, token + " Caskroom state is staged",
                       (h.prefix / "Caskroom" / token / "1.0.0").is_dir(), token)
        for action in ("upgrade", "uninstall"):
            refusal = h.guard_cask_mutation(action, token)
            h.events.check(
                s, "%s %s is refused by the fixture launch guard" % (token, action),
                refusal["decision"] == "fixture-refused"
                and refusal["launched"] is False
                and refusal["argv"] is None
                and refusal["fresh_info_step"] > install["seq"],
                refusal,
            )
            h.events.check(
                s, "%s %s classification names the unsafe metadata" % (token, action),
                expectation["reasons"] <= set(refusal["classification"]["reasons"]),
                refusal["classification"],
            )
        h.events.check(s, token + " remains installed after both fixture refusals",
                       h.cask_info(token).get("installed") == "1.0.0",
                       h.cask_info(token).get("installed"))

    h.events.check(s, "app-stanza scratch app remains after fixture refusal",
                   (appdir / "M13Stanza.app").is_dir(), str(appdir / "M13Stanza.app"))
    delete_paths = [path for key, path in h.sentinels.items() if key.startswith("cask-delete/")]
    h.events.check(s, "delete sentinel paths are inside the fixture root",
                   all(physically_within(Path(entry["path"]), h.root) for entry in delete_paths),
                   delete_paths)
    h.events.check(s, "unsafe-target canary remains absent",
                   not os.path.lexists(str(h.unsafe_target)), str(h.unsafe_target))
    after_hashes = h.sentinel_hashes()
    h.events.check(s, "delete, zap and escape sentinels remain in their original state",
                   after_hashes == sentinel_before, after_hashes)
    h.events.check(s, "zap step was never run and zap sentinel survives",
                   all(after_hashes[key]["present"] for key in after_hashes
                       if key.startswith("cask-zap/")), after_hashes)
    write_json(h.events.evidence / "cask-refusals.json", {
        "refused": h.refused_casks,
        "allowed_mutations": h.cask_mutations,
        "sentinel_before": sentinel_before,
        "sentinel_after": after_hashes,
        "unsafe_target": str(h.unsafe_target),
        "unsafe_target_present": os.path.lexists(str(h.unsafe_target)),
        "classification": "fixture launch-guard policy refusal, not a future Agent Lens verdict",
        "argv_audit": "harness launches only; descendant processes are not enumerated",
    })
    h.events.check(s, "installed cask list contains every refusal cask",
                   all(token in h._brew_ok("list installed casks", ["list", "--cask"])["stdout"]
                       for token in expectations), None)


@scenario
def ac_manifests(harness: Harness) -> None:
    """Residual sentinel and inventory state after all lifecycle scenarios."""
    h = harness
    s = "AC-MANIFESTS"
    initial = {key: value["sha256"] for key, value in h.sentinels.items()}
    observed = {key: value["sha256"] for key, value in h.sentinel_hashes().items()}
    h.events.check(s, "cask delete/list sentinels retain original hashes",
                   initial == observed, {"initial": initial, "observed": observed})
    if getattr(h, "formula_sentinel_digest", None):
        final = h.tree_digest(h.prefix / "Cellar/m13-sentinel", "sentinel-formula-final")
        h.events.check(s, "sentinel formula kegs retain original contents",
                       final["digest"] == h.formula_sentinel_digest,
                       {"initial": h.formula_sentinel_digest, "final": final["digest"]})
    versions = h._brew_ok("final formula inventory", ["list", "--versions"]).get("stdout", "")
    h.events.check(s, "residual formula inventory is recorded",
                   all(name in versions for name in ("m13-old", "m13-pinned", "m13-broken",
                                                     "m13-lib", "m13-consumer")), versions)
    casks = h._brew_ok("final cask inventory", ["list", "--cask"]).get("stdout", "")
    h.events.check(s, "residual cask inventory is recorded",
                   all(name in casks for name in ("m13-cask-auto", "m13-cask-latest",
                                                  "m13-cask-comma", "m13-cask-appstanza",
                                                  "m13-cask-delete", "m13-cask-escape")), casks)
    write_json(h.events.evidence / "residual-state.json", {
        "formulae": versions, "casks": casks,
        "formula_sentinel_digest": getattr(h, "formula_sentinel_digest", None),
        "sentinels": h.sentinel_hashes(),
        "unsafe_target_present": os.path.lexists(str(h.unsafe_target)),
    })

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="homebrew_acceptance.py",
        description=(
            "M13-C disposable Homebrew acceptance fixture (test-only). Builds a scratch prefix "
            "from the pinned local Homebrew source and exercises synthetic formula/cask "
            "lifecycles under an outer seatbelt profile. --root must not pre-exist and is "
            "never deleted."
        ),
        epilog=(
            "Exit codes: 0 fixture evidence passed (not an acceptance verdict); 2 unsafe or "
            "invalid root; 3 missing prerequisite, blocked or failed fixture check; 1 unexpected "
            "failure. Evidence and the scratch root are retained on every nonzero exit."
        ),
    )
    parser.add_argument("--root", help="absolute, non-existent operator-owned scratch root")
    parser.add_argument("--source", default=DEFAULT_SOURCE, help="local Homebrew git source (read-only)")
    parser.add_argument(
        "--expected-revision",
        default=PINNED_REVISION,
        help="fixed Homebrew revision; only the pinned revision is accepted",
    )
    parser.add_argument(
        "--check-root",
        metavar="PATH",
        help="validate a destination with exactly the --root requirements; exits 0 when acceptable",
    )
    parser.add_argument(
        "--bootstrap",
        action="store_true",
        help="create the owned root and record environment prerequisites only (not acceptance)",
    )
    return parser


def main(argv=None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.expected_revision != PINNED_REVISION:
        parser.error("the fixed revision set is required; %s is not accepted"
                     % args.expected_revision)
    try:
        source = Path(args.source)
        if args.check_root:
            report = refuse_unsafe_destination(Path(args.check_root), source)
            print(json.dumps(report, indent=2, sort_keys=True))
            return 0
        if not args.root:
            parser.error("--root is required unless --check-root or --help is used")
        destination = Path(args.root)
        record = create_owned_root(destination, source)
        harness = Harness(record, source, args.expected_revision)
        if args.bootstrap:
            print(json.dumps(harness.bootstrap_environment(), indent=2, sort_keys=True))
            return 0
        return harness.run_acceptance()
    except RootRefused as error:
        print("REFUSED: %s" % error, file=sys.stderr)
        return 2
    except HarnessBlocked as error:
        print("BLOCKED: %s" % error, file=sys.stderr)
        return 3
    except FileNotFoundError as error:
        print("BLOCKED: prerequisite missing: %s" % error, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
