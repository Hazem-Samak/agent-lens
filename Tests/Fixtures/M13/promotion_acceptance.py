#!/usr/bin/env python3
"""M13-F owner-promotion acceptance driver (test-only; not an acceptance verdict).

One explicitly named scenario per owner-approved promotion candidate, over the existing M13-C
disposable Homebrew harness: real scratch manager, closed environment, seatbelt containment,
manifest window, literal argv receipts and fd 198 inherited-sandbox protocol.

* ``hermes``    formula ``hermes-agent`` -> ``hermes`` plus ``hermes-agent``/``hermes-acp``.
* ``aider``     formula ``aider`` -> ``aider``.
* ``goose``     formula ``block-goose-cli`` -> ``goose`` plus helpers. Pressly formula ``goose`` is
  installed first as a live basename collision; the product must refuse it, and its keg digest must
  stay identical after it is left installed-unlinked.
* ``kiro-cli``  binary cask ``kiro-cli`` -> ``kiro-cli`` with a zap target sentinel.

Modes: ``pre-promotion`` derives from the real bundled bytes and overlays only the exact expected
operation pair in memory; ``final`` uses those bytes with no overlay and requires the exact pair.
Payloads are deterministic local tarballs; no vendor release, network, vendor execution or native
app mutation is modeled.

    swiftc -parse-as-library -I "$SCRATCH/out/Products/Debug" \
      Tests/Fixtures/M13/PromotionAcceptanceHost.swift \
      "$SCRATCH/out/Products/Debug/AgentLensCore.o" -o "$SCRATCH/PromotionAcceptanceHost"
    python3 -B Tests/Fixtures/M13/promotion_acceptance.py \
      --root "$SCRATCH/m13-f" --host "$SCRATCH/PromotionAcceptanceHost" \
      [--scenario hermes|aider|goose|kiro-cli] [--mode pre-promotion|final] [--registry FILE]

Every scenario writes ``<root>/evidence/promotion/<id>.json`` and a failed check stops later
mutation scenarios with a nonzero exit. Exit codes are the M13-C harness's.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import sys
from pathlib import Path

sys.dont_write_bytecode = True

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parents[2]
FIXTURE = HERE / "homebrew_acceptance.py"
DEFAULT_REGISTRY = REPO_ROOT / "Sources/AgentLensCore/Detectors/DefaultDetectors.json"
SHORT_TIMEOUT_SECONDS = 30
HOST_TIMEOUT_SECONDS = 240
PRESSLY_GOOSE_VERSION = "3.30.1"

FORMULAS = {
    "hermes": {
        "id": "hermes", "manager": "formula", "package": "hermes-agent",
        "executable": "hermes", "siblings": ["hermes-agent", "hermes-acp"],
        "old": "0.23.1", "new": "0.24.0",
    },
    "aider": {
        "id": "aider", "manager": "formula", "package": "aider",
        "executable": "aider", "siblings": [], "old": "0.86.2", "new": "0.87.0",
    },
    "goose": {
        "id": "goose", "manager": "formula", "package": "block-goose-cli",
        "executable": "goose", "siblings": ["generate_manpages", "mcp_conformance_driver"],
        "old": "1.59.0", "new": "1.60.0",
    },
}
CASK = {
    "id": "kiro-cli", "manager": "cask", "package": "kiro-cli",
    "executable": "kiro-cli", "artifact": "kirocli/bin/kiro-cli",
    "old": "3.6.1", "new": "3.6.2",
}

HOST = None
REGISTRY = None
MODE = "pre-promotion"


def load_fixture():
    spec = importlib.util.spec_from_file_location("m13_fixture", FIXTURE)
    if spec is None or spec.loader is None:
        raise SystemExit("cannot load %s" % FIXTURE)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


m = load_fixture()


def _line(case, executable, version):
    if case["id"] == "hermes" and executable == "hermes":
        return "Hermes Agent v%s" % version
    return "%s %s" % (executable, version)


def _script(case, executable, version):
    return ("#!/bin/sh\necho \"%s\"\n" % _line(case, executable, version)).encode("utf-8")


def _class_name(name):
    return "".join(part.capitalize() for part in name.split("-"))


def _build_payloads(h):
    base = h.root / "payloads"
    payloads = {}
    for case in FORMULAS.values():
        names = [case["executable"]] + list(case["siblings"])
        for version in (case["old"], case["new"]):
            path = base / ("promotion-%s-%s.tar.gz" % (case["package"], version))
            digest = m.write_tar_gz(path, {
                name: (_script(case, name, version), 0o755) for name in names
            })
            payloads[(case["package"], version)] = {
                "path": path, "sha256": digest, "executables": names,
            }
    path = base / ("promotion-goose-pressly-%s.tar.gz" % PRESSLY_GOOSE_VERSION)
    digest = m.write_tar_gz(path, {"goose": (
        ("#!/bin/sh\necho \"goose %s (pressly fixture collision)\"\n"
         % PRESSLY_GOOSE_VERSION).encode("utf-8"), 0o755
    )})
    payloads[("goose", PRESSLY_GOOSE_VERSION)] = {
        "path": path, "sha256": digest, "executables": ["goose"],
    }
    for version in (CASK["old"], CASK["new"]):
        path = base / ("promotion-kiro-cli-%s.tar.gz" % version)
        digest = m.write_tar_gz(path, {CASK["artifact"]: (
            ("#!/bin/sh\necho \"kiro-cli %s\"\n" % version).encode("utf-8"), 0o755
        )})
        payloads[("kiro-cli", version)] = {
            "path": path, "sha256": digest, "executables": [CASK["artifact"]],
        }
    h.promotion_payloads = payloads
    m.write_json(h.events.evidence / "promotion-payloads.json", {
        "label": "deterministic local M13-F promotion payloads",
        "payloads": [
            {"name": key[0], "version": key[1], "path": str(value["path"]),
             "sha256": value["sha256"], "executables": value["executables"]}
            for key, value in sorted(payloads.items())
        ],
    })


def _formula_text(h, case, version):
    payload = h.promotion_payloads[(case["package"], version)]
    installs = "\n".join('    bin.install "%s"' % name for name in payload["executables"])
    return (
        'class %s < Formula\n  desc "M13-F fixture %s formula"\n'
        '  homepage "https://example.invalid/%s"\n  url "%s"\n'
        '  sha256 "%s"\n  version "%s"\n\n  def install\n%s\n  end\nend\n'
    ) % (_class_name(case["package"]), case["package"], case["package"],
         m.file_url(payload["path"]), payload["sha256"], version, installs)


def _pressly_formula_text(h):
    payload = h.promotion_payloads[("goose", PRESSLY_GOOSE_VERSION)]
    return (
        'class Goose < Formula\n  desc "M13-F uninstalled pressly goose collision"\n'
        '  homepage "https://example.invalid/pressly-goose"\n  url "%s"\n'
        '  sha256 "%s"\n  version "%s"\n\n  def install\n    bin.install "goose"\n'
        '  end\nend\n'
    ) % (m.file_url(payload["path"]), payload["sha256"], PRESSLY_GOOSE_VERSION)


def _cask_text(h, version):
    payload = h.promotion_payloads[("kiro-cli", version)]
    return (
        'cask "kiro-cli" do\n  version "%s"\n  sha256 "%s"\n  url "%s"\n'
        '  name "Kiro CLI"\n  desc "M13-F fixture Kiro CLI binary cask"\n'
        '  homepage "https://kiro.dev/docs/cli/"\n  depends_on macos: ">= :big_sur"\n\n'
        '  binary "kirocli/bin/kiro-cli"\n\n  zap trash: ["%s"]\nend\n'
    ) % (version, payload["sha256"], m.file_url(payload["path"]),
         h.promotion_kiro_zap_sentinel)


def _commit(h, purpose, repo, message):
    for label, arguments in (
        ("add", ["-C", str(repo), "add", "-A"]),
        ("commit", ["-C", str(repo), "commit", "-q", "-m", message]),
    ):
        receipt = h._git("%s %s" % (purpose, label), arguments)
        if receipt["exit"] != 0:
            m.blocked("%s %s failed: %s" % (purpose, label, receipt["stderr"][-800:]))
    head = h._git("%s head" % purpose, ["-C", str(repo), "rev-parse", "HEAD"])
    if head["exit"] != 0:
        m.blocked("%s head failed: %s" % (purpose, head["stderr"][-500:]))
    return head["stdout"].strip()


class PromotionHarness(m.Harness):
    """M13-C Harness plus scratch-local bare-identity promotion fixtures."""

    def build_payloads(self):
        super().build_payloads()
        _build_payloads(self)
        self.promotion_taps_ready = False
        self.promotion_failed = False

    def install_tap_and_trust(self):
        super().install_tap_and_trust()
        self.setup_promotion_taps()

    def setup_promotion_taps(self):
        if getattr(self, "promotion_taps_ready", False):
            return
        sentinel = self.root / "sentinels" / "promotion" / "kiro-zap-sentinel.txt"
        sentinel.parent.mkdir(parents=True, exist_ok=True)
        sentinel.write_text("M13-F Kiro zap-target sentinel; the zap step must never run.\n")
        os.chmod(sentinel, 0o644)
        self.promotion_kiro_zap_sentinel = sentinel

        core = self.prefix / "Library/Taps/homebrew/homebrew-core"
        if not (core / ".git").exists():
            m.blocked("scratch stub homebrew/core tap is missing: %s" % core)
        for case in FORMULAS.values():
            path = core / "Formula" / (case["package"] + ".rb")
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(_formula_text(self, case, case["old"]))
            os.chmod(path, 0o644)
        pressly = core / "Formula" / "goose.rb"
        pressly.write_text(_pressly_formula_text(self))
        os.chmod(pressly, 0o644)
        core_head = _commit(self, "M13-F promotion core tap v0", core,
                            "v0: M13-F promotion core fixtures")

        cask_tap = self.prefix / "Library/Taps/homebrew/homebrew-cask"
        cask_tap.mkdir(parents=True, exist_ok=True)
        (cask_tap / "Casks").mkdir(exist_ok=True)
        (cask_tap / "README.md").write_text(
            "M13-F scratch-local homebrew/cask fixture tap. It has no remote.\n"
        )
        cask_path = cask_tap / "Casks" / (CASK["package"] + ".rb")
        cask_path.write_text(_cask_text(self, CASK["old"]))
        os.chmod(cask_path, 0o644)
        init = self._git("M13-F promotion cask tap init",
                         ["init", "-q", "--initial-branch=main"], cwd=cask_tap)
        if init["exit"] != 0:
            m.blocked("M13-F promotion cask tap init failed: %s" % init["stderr"][-800:])
        cask_head = _commit(self, "M13-F promotion cask tap v0", cask_tap,
                            "v0: M13-F promotion cask fixture")
        self.promotion_taps_ready = True
        self.promotion_taps = {
            "core": str(core), "core_v0_head": core_head,
            "cask": str(cask_tap), "cask_v0_head": cask_head,
            "cask_full_token_expected": CASK["package"],
        }
        m.write_json(self.events.evidence / "promotion-taps.json", dict(
            self.promotion_taps, sentinel=str(sentinel),
            label="scratch-local taps with bare identities; no remote"
        ))

    def bump_formula(self, case, version, message):
        self.require_containment("M13-F bump %s to %s" % (case["package"], version))
        core = self.prefix / "Library/Taps/homebrew/homebrew-core"
        path = core / "Formula" / (case["package"] + ".rb")
        path.write_text(_formula_text(self, case, version))
        os.chmod(path, 0o644)
        return _commit(self, "M13-F bump %s" % case["package"], core, message)

    def bump_cask(self, version, message):
        self.require_containment("M13-F bump kiro-cli cask to %s" % version)
        cask_tap = self.prefix / "Library/Taps/homebrew/homebrew-cask"
        path = cask_tap / "Casks" / (CASK["package"] + ".rb")
        path.write_text(_cask_text(self, version))
        os.chmod(path, 0o644)
        return _commit(self, "M13-F bump kiro-cli cask", cask_tap, message)

    def cask_info(self, scenario):
        data = self._brew_json(scenario + " cask info kiro-cli",
                               ["info", "--json=v2", "--cask", CASK["package"]])
        casks = data.get("casks", [])
        if len(casks) != 1:
            m.blocked("promotion cask info did not identify exactly one cask")
        return casks[0]

    def sentinel_state(self):
        path = Path(self.promotion_kiro_zap_sentinel)
        return {"path": str(path), "present": path.is_file(),
                "sha256": m.sha256_file(path) if path.is_file() else None}


def _expect(h, scenario, name, ok, detail=None):
    h.events.check(scenario, name, ok, detail)
    if not ok:
        h.promotion_failed = True
        m.blocked("%s: %s" % (scenario, name))


def _host(h, case, action, scenario):
    h.require_containment("M13-F product host %s %s" % (action, case["id"]))
    argv = [
        str(HOST), "--root", str(h.root), "--registry", str(REGISTRY),
        "--mode", MODE, "--id", case["id"], "--action", action,
        "--manager", case["manager"], "--package", case["package"],
        "--executable", case["executable"],
        "--old-version", case["old"], "--new-version", case["new"],
    ]
    # Registry extra roots are expanded by Foundation, not by the child shell.
    env = dict(h.env, CFFIXED_USER_HOME=str(h.root / "home"))
    receipt = h._execute(
        "Agent Lens M13-F product %s %s" % (action, case["id"]), argv,
        timeout=HOST_TIMEOUT_SECONDS, inherit_homebrew_fd=True, env=env,
    )
    _expect(h, scenario, "product host %s exited 0" % action, receipt["exit"] == 0,
            {"step": receipt["seq"], "stderr": receipt["stderr"][-1200:]})
    _expect(
        h, scenario, "product host %s ran contained with fd 198" % action,
        receipt.get("sandboxed") is True
        and receipt.get("inherited_sandbox_fd") == 198
        and receipt.get("profile_sha256") == h.profile_digest
        and bool(receipt.get("cwd"))
        and m.physically_within(Path(receipt["cwd"]), h.root),
        {"fd": receipt.get("inherited_sandbox_fd"), "cwd": receipt.get("cwd")},
    )
    lines = [line for line in receipt["stdout"].splitlines() if line.strip()]
    try:
        payload = json.loads(lines[-1]) if lines else None
    except json.JSONDecodeError:
        payload = None
    if not isinstance(payload, dict):
        _expect(h, scenario, "product host %s emitted JSON evidence" % action, False,
                receipt["stdout"][-2000:])
    reported = payload.get("expected") or {}
    _expect(
        h, scenario, "product host %s identity matches the scenario" % action,
        reported.get("id") == case["id"]
        and reported.get("action") == action
        and reported.get("mode") == MODE,
        reported,
    )
    failed = [check for check in payload.get("checks", []) if not check.get("ok")]
    _expect(h, scenario, "product host %s internal checks all passed" % action,
            not failed, failed)
    return receipt, payload


def _readlink(path):
    return os.readlink(str(path)) if path.is_symlink() else None


def _same_entry(reported, expected):
    # Foundation may preserve either /var or /private/var. Bind the physical directory and
    # entry name without following the symlink at the leaf being proved.
    if not isinstance(reported, str):
        return False
    entry = Path(reported)
    return (entry.is_absolute() and entry.name == expected.name
            and entry.parent.resolve() == expected.parent.resolve())


def _one_binary_target(preview, expected):
    targets = preview.get("artifactTargets") or []
    return (len(targets) == 1 and targets[0].get("kind") == "binary"
            and _same_entry(targets[0].get("target"), expected))


def _run_binary(h, scenario, path, expected_line):
    receipt = h._execute("%s run %s" % (scenario, path.name), [str(path)],
                         timeout=SHORT_TIMEOUT_SECONDS)
    _expect(h, scenario, "%s reports the fixture version" % path.name,
            receipt["exit"] == 0 and expected_line in receipt["stdout"],
            {"exit": receipt["exit"], "stdout": receipt["stdout"][-400:],
             "stderr": receipt["stderr"][-400:]})
    return receipt


def _preview(h, scenario, payload, argv):
    preview = payload.get("preview") or {}
    _expect(h, scenario, "preview binds the exact literal argv",
            preview.get("arguments") == argv, preview.get("arguments"))
    _expect(h, scenario, "preview binds the 900 s timeout",
            preview.get("timeoutSeconds") == 900, preview.get("timeoutSeconds"))
    _expect(h, scenario, "preview effect states the 900 s bound",
            "900 seconds" in (preview.get("effect") or ""), preview.get("effect"))
    return preview


def _outcome(h, scenario, payload, argv):
    outcome = payload.get("outcome") or {}
    launches = payload.get("mutationLaunches") or []
    _expect(h, scenario, "mutation succeeded exactly once",
            outcome.get("state") == "succeeded"
            and outcome.get("processStarted") is True
            and outcome.get("exitStatus") == 0
            and outcome.get("cleanupWarnings") == []
            and len(launches) == 1 and launches[0].get("argv") == argv,
            {"outcome": outcome, "launches": launches})
    _expect(h, scenario, "no mutation policy attempt was refused",
            payload.get("mutationAttempts") == [], payload.get("mutationAttempts"))


def _scan(h, scenario, payload, label, state, version=None, owner="verified",
          source=None):
    scan = payload.get(label) or {}
    ownership = scan.get("ownership") or {}
    _expect(h, scenario, "%s state is %s" % (label, state),
            scan.get("state") == state, scan)
    if version is not None:
        _expect(h, scenario, "%s version is %s" % (label, version),
                scan.get("version") == version, scan)
    if source is not None:
        _expect(h, scenario, "%s source is %s" % (label, source),
                scan.get("source") == source, scan)
    result = "unknown" if owner == "notInstalled" else owner
    _expect(h, scenario, "%s ownership result is %s" % (label, result),
            ownership.get("result") == result, ownership)
    if owner == "verified":
        expected_package = (payload.get("expected") or {}).get("package")
        _expect(h, scenario, "%s ownership names the declared package" % label,
                ownership.get("packageName") == expected_package, ownership)
        if version is not None and scenario == CASK["id"]:
            token_root = h.prefix / "Caskroom" / expected_package
            target = token_root / version / CASK["artifact"]
            _expect(h, scenario, "%s ownership binds the token root and staged binary" % label,
                    _same_entry(ownership.get("installationRoot"), token_root)
                    and _same_entry(ownership.get("selectionTarget"), target), ownership)
        elif version is not None:
            _expect(h, scenario, "%s installation root names version %s" % (label, version),
                    "/%s" % version in (ownership.get("installationRoot") or ""),
                    ownership)
    elif owner == "notInstalled":
        _expect(h, scenario, "%s ownership reason is notInstalled" % label,
                ownership.get("reason") == "notInstalled", ownership)


def _cancel(h, scenario, payload, before, after, link_before, link_after,
            versions_before, versions_after, sentinel_before=None, sentinel_after=None):
    _expect(h, scenario, "preview cancel was accepted", payload.get("cancel") is True,
            payload.get("cancel"))
    _expect(h, scenario, "cancel launched no mutation",
            payload.get("mutationLaunches") == []
            and payload.get("mutationAttempts") == [],
            {"launches": payload.get("mutationLaunches"),
             "attempts": payload.get("mutationAttempts")})
    _expect(h, scenario, "Cancel leaves inventory and digests unchanged",
            before["digest"] == after["digest"]
            and link_before == link_after
            and versions_before == versions_after,
            {"before": before["digest"], "after": after["digest"],
             "link": link_after, "versions": versions_after})
    if sentinel_before is not None:
        _expect(h, scenario, "Cancel leaves the zap sentinel unchanged",
                sentinel_before == sentinel_after, sentinel_after)


def _formula_args(name):
    return ["upgrade", "--formula", "--yes", name], ["uninstall", "--formula", name]


def _formula_body(h, case):
    s = case["id"]
    name, executable = case["package"], case["executable"]
    old, new = case["old"], case["new"]
    if not getattr(h, "promotion_taps_ready", False):
        h.setup_promotion_taps()
    link = h.prefix / "bin" / executable
    update_argv, uninstall_argv = _formula_args(name)
    digests = {}

    install = h._brew_ok("M13-F install %s %s" % (name, old), ["install", "--yes", name])
    digests["install_step"] = install["seq"]
    _expect(h, s, "old keg is installed", h.installed_kegs(name) == [old],
            h.installed_kegs(name))
    _expect(h, s, "bin link targets the old keg",
            link.is_symlink() and old in (_readlink(link) or ""), _readlink(link))
    _run_binary(h, s, link, _line(case, executable, old))
    for sibling in case["siblings"]:
        _expect(h, s, "sibling executable %s is present" % sibling,
                (h.prefix / "bin" / sibling).is_symlink(),
                _readlink(h.prefix / "bin" / sibling))

    _, payload = _host(h, case, "scan", s)
    _scan(h, s, payload, "scan", "installedAndOnPath", old)

    h.bump_formula(case, new, "v1: M13-F %s to %s" % (name, new))
    info = h._brew_json("M13-F %s info after bump" % name,
                        ["info", "--json=v2", "--formula", name])
    _expect(h, s, "manager advertises the new formula version",
            (info.get("formulae") or [{}])[0].get("versions", {}).get("stable") == new,
            info.get("formulae", [])[:1])

    cellar = h.prefix / "Cellar" / name
    before = h.tree_digest(cellar, "promotion-%s-cellar-before-update-cancel" % s)
    link_before, versions_before = _readlink(link), h.installed_versions(name)
    _, payload = _host(h, case, "update-preview", s)
    preview = _preview(h, s, payload, update_argv)
    _expect(h, s, "formula Update preview binds the selected old keg and target version",
            preview.get("fullName") == name
            and preview.get("selectedKegVersion") == old
            and preview.get("targetVersion") == new
            and preview.get("installedKegs") == [old]
            and _same_entry(preview.get("selectedEntryPath"), link),
            preview)
    after = h.tree_digest(cellar, "promotion-%s-cellar-after-update-cancel" % s)
    _cancel(h, s, payload, before, after, link_before, _readlink(link),
            versions_before, h.installed_versions(name))

    _, payload = _host(h, case, "update-execute", s)
    _outcome(h, s, payload, update_argv)
    delta = payload.get("delta") or {}
    _expect(h, s, "formula Update reconciles the new keg and old-keg preservation",
            delta.get("versionMatchesTarget") is True
            and delta.get("previousKegReplaced") is True
            and delta.get("previousKegStillPresent") is True
            and delta.get("afterSelectedKegVersion") == new
            and delta.get("afterInstalledKegs") == sorted([old, new])
            and delta.get("observationFailed") is False, delta)
    _scan(h, s, payload, "postScan", "installedAndOnPath", new)
    _expect(h, s, "manager keeps the old keg and links the new one",
            h.installed_kegs(name) == sorted([old, new])
            and link.is_symlink() and new in (_readlink(link) or ""),
            {"kegs": h.installed_kegs(name), "link": _readlink(link)})
    _run_binary(h, s, link, _line(case, executable, new))

    before = h.tree_digest(cellar, "promotion-%s-cellar-before-uninstall-cancel" % s)
    link_before, versions_before = _readlink(link), h.installed_versions(name)
    _, payload = _host(h, case, "uninstall-preview", s)
    preview = _preview(h, s, payload, uninstall_argv)
    _expect(h, s, "formula Uninstall preview binds the linked new keg",
            preview.get("fullName") == name
            and preview.get("selectedKegVersion") == new
            and preview.get("installedKegs") == sorted([old, new])
            and _same_entry(preview.get("selectedEntryPath"), link)
            and "residue" in (preview.get("remainingKegDisclosure") or "").lower()
            and "--ignore-dependencies" in
                (preview.get("dependentRefusalDisclosure") or ""), preview)
    after = h.tree_digest(cellar, "promotion-%s-cellar-after-uninstall-cancel" % s)
    _cancel(h, s, payload, before, after, link_before, _readlink(link),
            versions_before, h.installed_versions(name))

    _, payload = _host(h, case, "uninstall-execute", s)
    _outcome(h, s, payload, uninstall_argv)
    delta = payload.get("delta") or {}
    _expect(h, s, "formula Uninstall removes only the linked keg and reports residue",
            delta.get("recordedKegAbsent") is True
            and delta.get("selectedTargetReleased") is True
            and delta.get("observationFailed") is False
            and delta.get("remainingKegs") == [old]
            and delta.get("formulaStillInstalledViaRemainingKeg") is True, delta)
    _scan(h, s, payload, "postScan", "notInstalled", owner="notInstalled")
    _expect(h, s, "manager retains the old keg and no longer links the formula",
            h.installed_kegs(name) == [old] and not os.path.lexists(str(link)),
            {"kegs": h.installed_kegs(name), "link": _readlink(link)})
    digests["final_kegs"] = h.installed_kegs(name)
    digests["final_versions"] = h.installed_versions(name)
    digests["final_link"] = _readlink(link)
    return digests


def _goose_body(h, case):
    s, name = case["id"], case["package"]
    link = h.prefix / "bin" / "goose"
    if not getattr(h, "promotion_taps_ready", False):
        h.setup_promotion_taps()

    h._brew_ok("M13-F install pressly goose collision", ["install", "--yes", "goose"])
    _expect(h, s, "pressly goose collision is installed",
            h.installed_kegs("goose") == [PRESSLY_GOOSE_VERSION],
            h.installed_kegs("goose"))
    _expect(h, s, "pressly goose collision is the live basename selected by PATH",
            link.is_symlink() and PRESSLY_GOOSE_VERSION in (_readlink(link) or ""),
            _readlink(link))
    pressly_cellar = h.prefix / "Cellar" / "goose"
    before = h.tree_digest(pressly_cellar, "promotion-goose-pressly-before-collision")
    _, payload = _host(h, case, "collision", s)
    _expect(h, s, "collision scan selects the pressly goose entry",
            _same_entry((payload.get("scan") or {}).get("entryPath"), link)
            and (payload.get("scan") or {}).get("version") == PRESSLY_GOOSE_VERSION,
            payload.get("scan"))
    _expect(h, s, "collision ownership is not verified",
            (payload.get("scan") or {}).get("ownership", {}).get("result") == "unknown",
            payload.get("scan"))
    _expect(h, s, "collision preparation is refused with no product launch",
            payload.get("refusal") is not None
            and payload.get("mutationLaunches") == []
            and payload.get("mutationAttempts") == [],
            {"refusal": payload.get("refusal"),
             "launches": payload.get("mutationLaunches")})

    h._brew_ok("M13-F leave pressly goose installed-unlinked", ["unlink", "goose"])
    _expect(h, s, "pressly goose is now installed unlinked",
            not os.path.lexists(str(link))
            and h.installed_kegs("goose") == [PRESSLY_GOOSE_VERSION],
            {"link": _readlink(link), "kegs": h.installed_kegs("goose")})
    unlinked = h.tree_digest(pressly_cellar, "promotion-goose-pressly-after-unlink")
    _expect(h, s, "unlinking pressly goose leaves its keg byte-identical",
            unlinked["digest"] == before["digest"],
            {"before": before["digest"], "after": unlinked["digest"]})

    observations = _formula_body(h, case)
    final = h.tree_digest(pressly_cellar, "promotion-goose-pressly-after-scenario")
    _expect(h, s, "pressly goose keg stays byte-identical through the promoted workflow",
            final["digest"] == before["digest"],
            {"before": before["digest"], "final": final["digest"]})
    _expect(h, s, "pressly goose stays installed and unlinked",
            h.installed_kegs("goose") == [PRESSLY_GOOSE_VERSION]
            and not os.path.lexists(str(link)),
            {"kegs": h.installed_kegs("goose"), "link": _readlink(link)})
    observations["pressly_collision"] = {
        "version": PRESSLY_GOOSE_VERSION, "before": before["digest"],
        "after_unlink": unlinked["digest"], "final": final["digest"],
    }
    return observations


def _cask_body(h, case):
    s, token = case["id"], case["package"]
    old, new = case["old"], case["new"]
    if not getattr(h, "promotion_taps_ready", False):
        h.setup_promotion_taps()
    link = h.prefix / "bin" / case["executable"]
    caskroom = h.prefix / "Caskroom" / token
    update_argv = ["upgrade", "--cask", "--yes", token]
    uninstall_argv = ["uninstall", "--cask", token]
    sentinel_before = h.sentinel_state()
    observations = {}

    install = h._brew_ok("M13-F install cask %s %s" % (token, old),
                         ["install", "--cask", "--yes", token])
    observations["install_step"] = install["seq"]
    info = h.cask_info(s)
    artifacts = info.get("artifacts", [])
    _expect(h, s, "manager reports the old cask installation",
            info.get("installed") == old and info.get("version") == old,
            {"installed": info.get("installed"), "version": info.get("version")})
    _expect(h, s, "fixture cask is binary-only, zap-bearing, macOS-eligible and dependency-free",
            info.get("auto_updates") is not True
            and any(isinstance(a, dict) and "binary" in a for a in artifacts)
            and any(isinstance(a, dict) and "zap" in a for a in artifacts)
            and not any(isinstance(a, dict) and ("uninstall" in a or "app" in a)
                        for a in artifacts)
            and not (info.get("depends_on") or {}).get("formula")
            and not (info.get("depends_on") or {}).get("cask")
            and "macos" in (info.get("depends_on") or {}),
            {"artifacts": artifacts, "depends_on": info.get("depends_on")})
    _expect(h, s, "manager staged the old cask and prefix link",
            (caskroom / old).is_dir() and link.is_symlink()
            and old in (_readlink(link) or ""),
            {"caskroom": str(caskroom / old), "link": _readlink(link)})
    _run_binary(h, s, link, "kiro-cli %s" % old)
    _, payload = _host(h, case, "scan", s)
    _scan(h, s, payload, "scan", "installedAndOnPath", old, source="standalone")

    h.bump_cask(new, "v1: M13-F kiro-cli cask to %s" % new)
    info = h.cask_info(s)
    _expect(h, s, "manager advertises the new cask while the old remains installed",
            info.get("version") == new and info.get("installed") == old,
            {"version": info.get("version"), "installed": info.get("installed")})

    before = h.tree_digest(caskroom, "promotion-%s-caskroom-before-update-cancel" % s)
    link_before = _readlink(link)
    installed_before = h.cask_info(s).get("installed")
    _, payload = _host(h, case, "update-preview", s)
    preview = _preview(h, s, payload, update_argv)
    _expect(h, s, "cask Update preview binds the token, versions and binary artifact",
            preview.get("token") == token and preview.get("fullToken") == token
            and preview.get("tap") == "homebrew/cask"
            and preview.get("installedVersion") == old
            and preview.get("targetVersion") == new
            and _same_entry(preview.get("selectedEntryPath"), link)
            and _one_binary_target(preview, link)
            and preview.get("zapDeclared") is True, preview)
    after = h.tree_digest(caskroom, "promotion-%s-caskroom-after-update-cancel" % s)
    _cancel(h, s, payload, before, after, link_before, _readlink(link),
            [installed_before], [h.cask_info(s).get("installed")],
            sentinel_before, h.sentinel_state())

    _, payload = _host(h, case, "update-execute", s)
    _outcome(h, s, payload, update_argv)
    delta = payload.get("delta") or {}
    _expect(h, s, "cask Update reconciles the new version and staged membership",
            delta.get("versionMatchesTarget") is True
            and delta.get("tokenMatches") is True
            and delta.get("stagedMembershipConfirmed") is True
            and delta.get("afterInstalledVersion") == new
            and delta.get("managedTargetsReleased") is True
            and delta.get("observationFailed") is False, delta)
    _scan(h, s, payload, "postScan", "installedAndOnPath", new, source="standalone")
    info = h.cask_info(s)
    _expect(h, s, "manager and product agree the cask installs the new version",
            info.get("installed") == new and link.is_symlink()
            and new in (_readlink(link) or "")
            and h.sentinel_state() == sentinel_before,
            {"installed": info.get("installed"), "link": _readlink(link),
             "sentinel": h.sentinel_state()})
    _run_binary(h, s, link, "kiro-cli %s" % new)

    before = h.tree_digest(caskroom, "promotion-%s-caskroom-before-uninstall-cancel" % s)
    link_before = _readlink(link)
    installed_before = h.cask_info(s).get("installed")
    _, payload = _host(h, case, "uninstall-preview", s)
    preview = _preview(h, s, payload, uninstall_argv)
    _expect(h, s, "cask Uninstall preview binds identity, disclosures and artifact",
            preview.get("token") == token and preview.get("fullToken") == token
            and preview.get("tap") == "homebrew/cask"
            and preview.get("installedVersion") == new
            and _one_binary_target(preview, link)
            and "companion app" in (preview.get("companionAppDisclosure") or "").lower()
            and "does not run the zap" in (preview.get("zapDisclosure") or "").lower()
            and preview.get("zapDeclared") is True, preview)
    after = h.tree_digest(caskroom, "promotion-%s-caskroom-after-uninstall-cancel" % s)
    _cancel(h, s, payload, before, after, link_before, _readlink(link),
            [installed_before], [h.cask_info(s).get("installed")],
            sentinel_before, h.sentinel_state())

    _, payload = _host(h, case, "uninstall-execute", s)
    _outcome(h, s, payload, uninstall_argv)
    delta = payload.get("delta") or {}
    _expect(h, s, "cask Uninstall reconciles manager absence and target release",
            delta.get("infoInstalledAbsent") is True
            and delta.get("tokenDirectoryAbsent") is True
            and delta.get("selectedTargetReleased") is True
            and delta.get("managedTargetsReleased") is True
            and delta.get("observationFailed") is False, delta)
    _scan(h, s, payload, "postScan", "notInstalled", owner="notInstalled")
    info = h.cask_info(s)
    _expect(h, s, "Caskroom and link are gone while the zap sentinel survives",
            info.get("installed") is None
            and not os.path.lexists(str(caskroom))
            and not os.path.lexists(str(link))
            and h.sentinel_state() == sentinel_before,
            {"installed": info.get("installed"),
             "caskroom": os.path.lexists(str(caskroom)),
             "link": os.path.lexists(str(link)), "sentinel": h.sentinel_state()})
    observations.update({
        "final_cask_installed": info.get("installed"),
        "final_link": _readlink(link),
        "final_sentinel": h.sentinel_state(),
        "sentinel_before": sentinel_before,
    })
    return observations


def _run_case(h, case, body):
    scenario = case["id"]
    if getattr(h, "promotion_failed", False):
        m.blocked("an earlier promotion scenario failed; no later scenario or mutation runs")
    start = len(h.events.checks)
    observations = {}
    error = None
    try:
        observations = body(h, case) or {}
    except BaseException as failure:
        error = failure
        raise
    finally:
        checks = [check for check in h.events.checks[start:]
                  if check["scenario"] == scenario]
        failures = [check for check in checks if not check["ok"]]
        status = "failed" if error is not None or failures else "passed"
        if status == "failed":
            h.promotion_failed = True
        m.write_json(h.events.evidence / "promotion" / (scenario + ".json"), {
            "scenario": scenario,
            "label": "fixture evidence, not an acceptance verdict (D-014)",
            "mode": MODE,
            "fixture": case,
            "host": str(HOST),
            "observations": observations,
            "checks": checks,
            "failed_checks": failures,
            "status": status,
        })
    if failures:
        h.promotion_failed = True
        m.blocked("promotion scenario %s failed; no registry promotion is implied" % scenario)


def hermes(harness):
    """hermes: formula hermes-agent -> hermes plus hermes-agent/hermes-acp."""
    _run_case(harness, FORMULAS["hermes"], _formula_body)


def aider(harness):
    """aider: formula aider -> aider."""
    _run_case(harness, FORMULAS["aider"], _formula_body)


def goose(harness):
    """goose: formula block-goose-cli -> goose plus helpers, refusing the pressly collision."""
    _run_case(harness, FORMULAS["goose"], _goose_body)


def kiro_cli(harness):
    """kiro-cli: binary cask kirocli/bin/kiro-cli -> kiro-cli with zap sentinel."""
    _run_case(harness, CASK, _cask_body)


kiro_cli.__name__ = "kiro-cli"
SCENARIO_FUNCTIONS = {
    "hermes": hermes, "aider": aider, "goose": goose, "kiro-cli": kiro_cli,
}
SCENARIO_ORDER = ["hermes", "aider", "goose", "kiro-cli"]


def build_parser():
    parser = argparse.ArgumentParser(
        prog="promotion_acceptance.py",
        description="M13-F owner-promotion scenarios over the M13-C disposable Homebrew harness.",
        epilog="Host binary is built in orchestrator scratch. Use python3 -B. Root is retained.",
    )
    parser.add_argument("--root", required=True,
                        help="absolute, non-existent operator-owned scratch root")
    parser.add_argument("--host", required=True,
                        help="compiled PromotionAcceptanceHost binary in orchestrator scratch")
    parser.add_argument("--source", default=m.DEFAULT_SOURCE,
                        help="local Homebrew git source (read-only)")
    parser.add_argument("--registry", default=str(DEFAULT_REGISTRY),
                        help="candidate bundled registry JSON; final mode never overlays")
    parser.add_argument("--mode", choices=("pre-promotion", "final"),
                        default="pre-promotion",
                        help="in-memory exact pair overlay, or bundled bytes with no overlay")
    parser.add_argument("--scenario", choices=SCENARIO_ORDER,
                        help="run one named scenario for narrow repair; default runs all four")
    return parser


def main(argv=None):
    global HOST, MODE, REGISTRY
    parser = build_parser()
    args = parser.parse_args(argv)
    host, registry = Path(args.host), Path(args.registry)
    if not host.is_absolute() or not host.is_file() or not os.access(str(host), os.X_OK):
        print("REFUSED: --host must be an absolute executable file: %s" % host,
              file=sys.stderr)
        return 2
    if not registry.is_absolute() or not registry.is_file():
        print("REFUSED: --registry must be an absolute file: %s" % registry,
              file=sys.stderr)
        return 2
    HOST, REGISTRY, MODE = host, registry, args.mode
    selected = [args.scenario] if args.scenario else list(SCENARIO_ORDER)
    m.Harness = PromotionHarness
    m.SCENARIOS[:] = [SCENARIO_FUNCTIONS[name] for name in selected]
    status = m.main(["--root", args.root, "--source", args.source])
    print(json.dumps({
        "mode": MODE, "scenarios": selected, "status": status,
        "receipts": [str(Path(args.root) / "evidence" / "promotion" / (name + ".json"))
                     for name in selected],
        "label": "fixture evidence, not an acceptance verdict (D-014)",
    }, indent=2, sort_keys=True))
    return status


if __name__ == "__main__":
    sys.exit(main())
