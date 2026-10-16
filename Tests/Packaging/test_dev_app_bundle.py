#!/usr/bin/env python3
import sys
sys.dont_write_bytecode = True

import argparse
import contextlib
import importlib.util
import io
import json
import os
import pathlib
import plistlib
import re
import shutil
import subprocess
import unittest

APP_PATH = None

def load_build_dev_app_module():
    script_path = pathlib.Path(__file__).resolve().parent.parent.parent / "scripts" / "build-dev-app.py"
    spec = importlib.util.spec_from_file_location("build_dev_app", script_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

class DevAppBundlePackagingTests(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        if APP_PATH is None:
            raise RuntimeError("APP_PATH is not set; provide --app <path>")
        cls.app_path = APP_PATH.resolve()
        if not cls.app_path.is_dir():
            raise RuntimeError(f"Target app does not exist or is not a directory: {cls.app_path}")

        cls.root = cls.app_path.parent
        cls.swiftpm_dir = cls.root / "swiftpm"
        if not cls.swiftpm_dir.is_dir():
            raise RuntimeError(f"Derived swiftpm build directory does not exist: {cls.swiftpm_dir}")

        cls.packaging_dir = cls.root / "packaging"
        cls.packaging_dir.mkdir(parents=True, exist_ok=True)

        cls.clean_env = dict(os.environ)
        cls.clean_env.pop("PACKAGE_RESOURCE_BUNDLE_PATH", None)
        cls.clean_env.pop("PACKAGE_RESOURCE_BUNDLE_URL", None)

        cls.repo_root = pathlib.Path(__file__).resolve().parent.parent.parent

    def ensure_sandbox_profile(self) -> pathlib.Path:
        sb_file = self.packaging_dir / "deny-original-build.sb"
        if not sb_file.exists():
            profile_content = f"""(version 1)
(allow default)
(deny file-read* (subpath "{self.swiftpm_dir.resolve()}"))
"""
            sb_file.write_text(profile_content, encoding="utf-8")
        return sb_file

    def ensure_relocated_good_app(self, refresh: bool = False) -> pathlib.Path:
        """Ensure the canonical relocated good app exists (copy original, never move).

        Returns the path to <packaging_dir>/relocated/<app-name>. On first use it
        is copied from the original build; afterwards the existing copy is reused
        unless refresh=True, in which case the existing relocated copy is removed
        and rebuilt from the current original build. Never deletes or moves the
        original build, and never alters the original. The relocated copy itself is
        refreshed from the current original when requested, then left intact.
        Independent of test order: creates the relocation from the original on a
        clean packaging dir, so negative tests can run standalone.
        """
        relocated_dir = self.packaging_dir / "relocated"
        relocated_dir.mkdir(parents=True, exist_ok=True)
        relocated_app = relocated_dir / self.app_path.name
        if refresh and relocated_app.exists():
            # Fresh relocation of the current original app each invocation.
            # Remove only the known-owned relocated test copy, never the original.
            shutil.rmtree(relocated_app)
        if not relocated_app.exists():
            shutil.copytree(self.app_path, relocated_app, symlinks=False)
        return relocated_app

    def test_01_bundle_structure_and_metadata(self):
        macos_dir = self.app_path / "Contents" / "MacOS"
        executable = macos_dir / "AgentLensApp"
        self.assertTrue(executable.is_file(), f"Executable not found at {executable}")
        self.assertTrue(os.access(executable, os.X_OK), f"Executable {executable} is not executable")

        info_plist_path = self.app_path / "Contents" / "Info.plist"
        self.assertTrue(info_plist_path.is_file(), f"Info.plist not found at {info_plist_path}")

        with open(info_plist_path, "rb") as fp:
            plist = plistlib.load(fp)

        self.assertEqual(plist.get("CFBundleExecutable"), "AgentLensApp")
        self.assertEqual(plist.get("CFBundlePackageType"), "APPL")
        self.assertEqual(plist.get("CFBundleIdentifier"), "com.agentlens.AgentLensApp")
        self.assertEqual(plist.get("CFBundleName"), "Agent Lens")
        self.assertEqual(plist.get("CFBundleShortVersionString"), "0.1.0")
        self.assertEqual(plist.get("CFBundleVersion"), "1")
        self.assertEqual(plist.get("LSMinimumSystemVersion"), "14.0")

        bundle_name = plist.get("AgentLensCoreResourceBundleName")
        self.assertIsNotNone(bundle_name, "Missing AgentLensCoreResourceBundleName in Info.plist")
        self.assertTrue(len(bundle_name) > 0)

        bundle_rel_path = plist.get("AgentLensCoreResourceBundlePath")
        self.assertIsNotNone(bundle_rel_path, "Missing AgentLensCoreResourceBundlePath in Info.plist")
        self.assertFalse(bundle_rel_path.startswith("/"), "AgentLensCoreResourceBundlePath must be relative")
        self.assertNotIn("..", bundle_rel_path, "AgentLensCoreResourceBundlePath must not contain traversal")

        expected_rel_path = f"Contents/Resources/{bundle_name}.bundle"
        self.assertEqual(bundle_rel_path, expected_rel_path, "Bundle path and name metadata must be consistent")

        bundled_resource_dir = self.app_path / bundle_rel_path
        self.assertTrue(bundled_resource_dir.is_dir(), f"Referenced resource bundle {bundled_resource_dir} is missing")

        # Check DefaultDetectors.json inside the bundled resource
        candidate_files = [
            bundled_resource_dir / "Contents" / "Resources" / "DefaultDetectors.json",
            bundled_resource_dir / "DefaultDetectors.json"
        ]
        detector_file = next((f for f in candidate_files if f.is_file()), None)
        self.assertIsNotNone(detector_file, "DefaultDetectors.json missing from packaged resource bundle")

        # Validate JSON content against expected registry schema
        with open(detector_file, "r", encoding="utf-8") as fp:
            data = json.load(fp)
        self.assertEqual(data.get("schemaVersion"), 1)
        detectors = data.get("detectors", [])
        self.assertEqual(len(detectors), 3)
        self.assertEqual([d["id"] for d in detectors], ["codex", "opencode", "grok"])

    def test_02_relocation_sandbox_denial_and_preflight(self):
        # 1. Fresh relocation of the current original app each invocation
        # (copy original, never move; never touches the original build)
        relocated_app = self.ensure_relocated_good_app(refresh=True)

        # Confirm original build is preserved intact
        self.assertTrue(self.app_path.is_dir())
        self.assertTrue(self.swiftpm_dir.is_dir())

        # 2. Find an existing file in original swiftpm dir to prove read denial
        control_files = list(self.swiftpm_dir.rglob("DefaultDetectors.json"))
        if not control_files:
            control_files = [f for f in self.swiftpm_dir.rglob("*") if f.is_file()]
        self.assertTrue(len(control_files) > 0, "No control file found in swiftpm build directory")
        control_file = control_files[0]

        # 3. Create sandbox profile denying read access to original build directory
        sb_file = self.ensure_sandbox_profile()

        # 4. Outside sandbox control read must succeed
        outside_res = subprocess.run(
            ["cat", str(control_file)],
            capture_output=True,
            text=True,
            timeout=10
        )
        self.assertEqual(outside_res.returncode, 0, "Outside sandbox read of control file must succeed")
        self.assertTrue(len(outside_res.stdout) > 0)

        # 5. Inside sandbox control read must fail with permission denial
        inside_res = subprocess.run(
            ["sandbox-exec", "-f", str(sb_file), "cat", str(control_file)],
            capture_output=True,
            text=True,
            timeout=10
        )
        self.assertNotEqual(inside_res.returncode, 0, "Inside sandbox read of control file must be denied")
        self.assertIn("Operation not permitted", inside_res.stderr)

        # 6. Run relocated app's preflight under the EXACT SAME sandbox
        relocated_binary = relocated_app / "Contents" / "MacOS" / "AgentLensApp"
        preflight_proc = subprocess.run(
            ["sandbox-exec", "-f", str(sb_file), str(relocated_binary), "--bundle-preflight"],
            env=self.clean_env,
            capture_output=True,
            text=True,
            timeout=15
        )
        self.assertEqual(preflight_proc.returncode, 0, f"Relocated preflight failed: {preflight_proc.stderr}")
        self.assertEqual(
            preflight_proc.stdout.strip(),
            "bundle-preflight: ok registry_count=3 registry_ids=codex opencode grok"
        )
        self.assertEqual(preflight_proc.stderr.strip(), "")

    def test_03_discriminating_disposable_copy_registry(self):
        # Create disposable copy to prove real loader follows the bundle contents
        relocated_app = self.ensure_relocated_good_app()
        disp_dir = self.packaging_dir / "disposable-custom"
        disp_dir.mkdir(parents=True, exist_ok=True)
        disp_app = disp_dir / self.app_path.name
        if disp_app.exists():
            shutil.rmtree(disp_app)
        shutil.copytree(relocated_app, disp_app, symlinks=False)

        info_plist_path = disp_app / "Contents" / "Info.plist"
        with open(info_plist_path, "rb") as fp:
            plist = plistlib.load(fp)
        rel_bundle = plist["AgentLensCoreResourceBundlePath"]
        bundle_dir = disp_app / rel_bundle

        candidate_files = [
            bundle_dir / "Contents" / "Resources" / "DefaultDetectors.json",
            bundle_dir / "DefaultDetectors.json"
        ]
        detector_file = next((f for f in candidate_files if f.is_file()), None)
        self.assertIsNotNone(detector_file)

        # Write custom valid registry with different IDs and swapped order
        custom_registry = {
            "schemaVersion": 1,
            "detectors": [
                {
                    "id": "opencode",
                    "displayName": "OpenCode",
                    "executableName": "opencode",
                    "extraSearchRoots": ["~/.opencode/bin"],
                    "fixture": {
                        "layout": "singleDirectory",
                        "expectedSource": "standalone"
                    }
                },
                {
                    "id": "codex",
                    "displayName": "Codex",
                    "executableName": "codex",
                    "extraSearchRoots": ["~/.local/bin"],
                    "fixture": {
                        "layout": "npmGlobal",
                        "expectedSource": "npm"
                    }
                }
            ]
        }
        detector_file.write_text(json.dumps(custom_registry, indent=2), encoding="utf-8")

        binary = disp_app / "Contents" / "MacOS" / "AgentLensApp"
        sb_file = self.ensure_sandbox_profile()
        proc = subprocess.run(
            ["sandbox-exec", "-f", str(sb_file), str(binary), "--bundle-preflight"],
            env=self.clean_env,
            capture_output=True,
            text=True,
            timeout=15
        )
        self.assertEqual(proc.returncode, 0, f"Preflight on custom registry failed: {proc.stderr}")
        self.assertEqual(
            proc.stdout.strip(),
            "bundle-preflight: ok registry_count=2 registry_ids=opencode codex"
        )
        shutil.rmtree(disp_dir)

    def test_04_missing_resource_and_bundle_cases(self):
        relocated_app = self.ensure_relocated_good_app()
        # Case A: Missing DefaultDetectors.json
        disp_dir_1 = self.packaging_dir / "disp-missing-file"
        disp_dir_1.mkdir(parents=True, exist_ok=True)
        disp_app_1 = disp_dir_1 / self.app_path.name
        if disp_app_1.exists():
            shutil.rmtree(disp_app_1)
        shutil.copytree(relocated_app, disp_app_1, symlinks=False)

        info_plist_path = disp_app_1 / "Contents" / "Info.plist"
        with open(info_plist_path, "rb") as fp:
            plist = plistlib.load(fp)
        bundle_dir = disp_app_1 / plist["AgentLensCoreResourceBundlePath"]

        for cand in [bundle_dir / "Contents" / "Resources" / "DefaultDetectors.json", bundle_dir / "DefaultDetectors.json"]:
            if cand.is_file():
                cand.unlink()

        binary = disp_app_1 / "Contents" / "MacOS" / "AgentLensApp"
        proc = subprocess.run(
            [str(binary), "--bundle-preflight"],
            env=self.clean_env,
            capture_output=True,
            text=True,
            timeout=15
        )
        self.assertNotEqual(proc.returncode, 0, "Missing detector file must exit nonzero")
        self.assertGreater(proc.returncode, 0, "Must exit with ordinary code, not terminated by signal/fatalError")
        self.assertIn("bundle-preflight: failed:", proc.stderr)
        self.assertNotIn(str(self.packaging_dir), proc.stderr)
        self.assertNotIn("/Users/", proc.stderr)
        shutil.rmtree(disp_dir_1)

        # Case B: Missing resource bundle directory
        disp_dir_2 = self.packaging_dir / "disp-missing-bundle"
        disp_dir_2.mkdir(parents=True, exist_ok=True)
        disp_app_2 = disp_dir_2 / self.app_path.name
        if disp_app_2.exists():
            shutil.rmtree(disp_app_2)
        shutil.copytree(relocated_app, disp_app_2, symlinks=False)

        info_plist_path = disp_app_2 / "Contents" / "Info.plist"
        with open(info_plist_path, "rb") as fp:
            plist = plistlib.load(fp)
        bundle_dir = disp_app_2 / plist["AgentLensCoreResourceBundlePath"]
        if bundle_dir.exists():
            shutil.rmtree(bundle_dir)

        binary = disp_app_2 / "Contents" / "MacOS" / "AgentLensApp"
        proc = subprocess.run(
            [str(binary), "--bundle-preflight"],
            env=self.clean_env,
            capture_output=True,
            text=True,
            timeout=15
        )
        self.assertNotEqual(proc.returncode, 0, "Missing bundle directory must exit nonzero")
        self.assertGreater(proc.returncode, 0, "Must exit with ordinary code, not terminated by signal/fatalError")
        self.assertIn("bundle-preflight: failed:", proc.stderr)
        self.assertNotIn(str(self.packaging_dir), proc.stderr)
        self.assertNotIn("/Users/", proc.stderr)
        shutil.rmtree(disp_dir_2)

    def test_05_invalid_json_and_schema_cases(self):
        relocated_app = self.ensure_relocated_good_app()
        # Case A: Corrupted JSON
        disp_dir_3 = self.packaging_dir / "disp-invalid-json"
        disp_dir_3.mkdir(parents=True, exist_ok=True)
        disp_app_3 = disp_dir_3 / self.app_path.name
        if disp_app_3.exists():
            shutil.rmtree(disp_app_3)
        shutil.copytree(relocated_app, disp_app_3, symlinks=False)

        info_plist_path = disp_app_3 / "Contents" / "Info.plist"
        with open(info_plist_path, "rb") as fp:
            plist = plistlib.load(fp)
        bundle_dir = disp_app_3 / plist["AgentLensCoreResourceBundlePath"]
        detector_file = next((f for f in [bundle_dir / "Contents" / "Resources" / "DefaultDetectors.json", bundle_dir / "DefaultDetectors.json"] if f.is_file()), None)
        self.assertIsNotNone(detector_file)
        detector_file.write_text("{ not json at all", encoding="utf-8")

        binary = disp_app_3 / "Contents" / "MacOS" / "AgentLensApp"
        proc = subprocess.run(
            [str(binary), "--bundle-preflight"],
            env=self.clean_env,
            capture_output=True,
            text=True,
            timeout=15
        )
        self.assertNotEqual(proc.returncode, 0, "Invalid JSON must exit nonzero")
        self.assertGreater(proc.returncode, 0, "Must exit with ordinary code, not signal")
        self.assertIn("bundle-preflight: failed: invalid detector registry data", proc.stderr)
        self.assertNotIn(str(self.packaging_dir), proc.stderr)
        self.assertNotIn("/Users/", proc.stderr)
        shutil.rmtree(disp_dir_3)

        # Case B: Unsupported schema version
        disp_dir_4 = self.packaging_dir / "disp-invalid-schema"
        disp_dir_4.mkdir(parents=True, exist_ok=True)
        disp_app_4 = disp_dir_4 / self.app_path.name
        if disp_app_4.exists():
            shutil.rmtree(disp_app_4)
        shutil.copytree(relocated_app, disp_app_4, symlinks=False)

        info_plist_path = disp_app_4 / "Contents" / "Info.plist"
        with open(info_plist_path, "rb") as fp:
            plist = plistlib.load(fp)
        bundle_dir = disp_app_4 / plist["AgentLensCoreResourceBundlePath"]
        detector_file = next((f for f in [bundle_dir / "Contents" / "Resources" / "DefaultDetectors.json", bundle_dir / "DefaultDetectors.json"] if f.is_file()), None)
        self.assertIsNotNone(detector_file)
        detector_file.write_text(json.dumps({"schemaVersion": 999, "detectors": []}), encoding="utf-8")

        binary = disp_app_4 / "Contents" / "MacOS" / "AgentLensApp"
        proc = subprocess.run(
            [str(binary), "--bundle-preflight"],
            env=self.clean_env,
            capture_output=True,
            text=True,
            timeout=15
        )
        self.assertNotEqual(proc.returncode, 0, "Unsupported schema version must exit nonzero")
        self.assertGreater(proc.returncode, 0, "Must exit with ordinary code, not signal")
        self.assertIn("bundle-preflight: failed: invalid detector registry data", proc.stderr)
        self.assertNotIn(str(self.packaging_dir), proc.stderr)
        self.assertNotIn("/Users/", proc.stderr)
        shutil.rmtree(disp_dir_4)

    def test_06_unsupported_argument_shapes(self):
        binary = self.app_path / "Contents" / "MacOS" / "AgentLensApp"

        # Multi-argument with --bundle-preflight
        proc1 = subprocess.run(
            [str(binary), "--bundle-preflight", "--extra"],
            env=self.clean_env,
            capture_output=True,
            text=True,
            timeout=15
        )
        self.assertNotEqual(proc1.returncode, 0)
        self.assertIn("bundle-preflight: failed: unsupported argument vector", proc1.stderr)

        # Unrecognized argument
        proc2 = subprocess.run(
            [str(binary), "--unrecognized"],
            env=self.clean_env,
            capture_output=True,
            text=True,
            timeout=15
        )
        self.assertNotEqual(proc2.returncode, 0)
        self.assertIn("bundle-preflight: failed: unsupported argument vector", proc2.stderr)

    def test_07_preserve_original_build_and_relocated_intact(self):
        self.assertTrue(self.app_path.is_dir(), "Original .app must remain intact")
        self.assertTrue(self.swiftpm_dir.is_dir(), "Original swiftpm build directory must remain intact")
        relocated_app = self.packaging_dir / "relocated" / self.app_path.name
        self.assertTrue(relocated_app.is_dir(), "Relocated app must remain intact")

    def test_08_scratch_root_policy_rejection_and_controls(self):
        build_module = load_build_dev_app_module()
        validator = build_module.validate_scratch_root
        home = pathlib.Path.home().resolve()

        # Pure rejection tests: broad roots
        broad_roots = [
            pathlib.Path("/"),
            home,
            pathlib.Path("/private"),
            pathlib.Path("/var"),
            pathlib.Path("/tmp"),
            pathlib.Path("/private/var"),
            pathlib.Path("/private/tmp"),
        ]
        with contextlib.redirect_stderr(io.StringIO()):
            for root_path in broad_roots:
                with self.assertRaises(SystemExit, msg=f"Should reject broad root {root_path}") as cm:
                    validator(root_path, self.repo_root)
                self.assertEqual(cm.exception.code, 1)

            # Pure rejection tests: protected subtrees and descendants
            protected_paths = [
                pathlib.Path("/Applications"),
                pathlib.Path("/Applications/AgentLensProbeDoNotCreate"),
                home / "Library",
                home / "Library" / "Caches" / "AgentLens",
                home / "Applications",
                home / "Applications" / "AgentLensTest",
                home / ".Trash",
                home / ".Trash" / "scratch",
                pathlib.Path("/System"),
                pathlib.Path("/System" / pathlib.Path("Volumes")),
                pathlib.Path("/Library"),
                pathlib.Path("/Library" / pathlib.Path("Caches")),
                pathlib.Path("/usr"),
                pathlib.Path("/usr/local/bin"),
                pathlib.Path("/bin"),
                pathlib.Path("/sbin"),
                pathlib.Path("/etc"),
                pathlib.Path("/etc/dummy"),
                pathlib.Path("/private/etc/dummy"),
                pathlib.Path("/opt"),
                pathlib.Path("/dev"),
                pathlib.Path("/cores"),
                self.repo_root,
                self.repo_root / "build",
                self.repo_root / "scratch",
                self.repo_root.parent,
            ]
            for p in protected_paths:
                with self.assertRaises(SystemExit, msg=f"Should reject protected path {p}") as cm:
                    validator(p, self.repo_root)
                self.assertEqual(cm.exception.code, 1)

            # Positive controls: valid explicit scratch roots must not raise
            valid_controls = [
                self.root,
                home / ".hermes" / "cache" / "scratch" / "test-sub",
                pathlib.Path("/tmp/agentlens-scratch-control-test"),
                pathlib.Path("/private/tmp/agentlens-scratch-control-test"),
                pathlib.Path("/private/var/folders/zz/agentlens-scratch-control"),
            ]
            for p in valid_controls:
                try:
                    validator(p, self.repo_root)
                except SystemExit as e:
                    self.fail(f"Valid scratch root {p} unexpectedly raised SystemExit({e.code})")

    def test_09_metadata_and_decoy_mismatches(self):
        relocated_app = self.ensure_relocated_good_app()
        # Case A: Single-field decoy path mismatch with valid decoy
        disp_dir_a = self.packaging_dir / "disp-decoy-single-field"
        disp_dir_a.mkdir(parents=True, exist_ok=True)
        disp_app_a = disp_dir_a / self.app_path.name
        if disp_app_a.exists():
            shutil.rmtree(disp_app_a)
        shutil.copytree(relocated_app, disp_app_a, symlinks=False)

        info_plist_path = disp_app_a / "Contents" / "Info.plist"
        with open(info_plist_path, "rb") as fp:
            plist = plistlib.load(fp)

        # Create valid decoy bundle
        resources_dir = disp_app_a / "Contents" / "Resources"
        decoy_bundle = resources_dir / "decoy.bundle"
        decoy_res = decoy_bundle / "Contents" / "Resources"
        decoy_res.mkdir(parents=True, exist_ok=True)
        valid_detector_data = {
            "schemaVersion": 1,
            "detectors": [
                {
                    "id": "codex",
                    "displayName": "Codex",
                    "executableName": "codex",
                    "extraSearchRoots": []
                }
            ]
        }
        (decoy_res / "DefaultDetectors.json").write_text(json.dumps(valid_detector_data), encoding="utf-8")

        # Set path to decoy, but leave name intact (single-field mismatch)
        plist["AgentLensCoreResourceBundlePath"] = "Contents/Resources/decoy.bundle"
        with open(info_plist_path, "wb") as fp:
            plistlib.dump(plist, fp, fmt=plistlib.FMT_XML)

        binary = disp_app_a / "Contents" / "MacOS" / "AgentLensApp"
        proc = subprocess.run(
            [str(binary), "--bundle-preflight"],
            env=self.clean_env,
            capture_output=True,
            text=True,
            timeout=15
        )
        self.assertNotEqual(proc.returncode, 0, "Single-field path mismatch must exit nonzero")
        self.assertGreater(proc.returncode, 0, "Must exit with ordinary code")
        self.assertIn("bundle-preflight: failed: resource bundle path and name inconsistent", proc.stderr)
        self.assertNotIn("/Users/", proc.stderr)
        shutil.rmtree(disp_dir_a)

        # Case B: Referenced invalid schema fixture in decoy bundle (P2 parent probe fixture)
        disp_dir_b = self.packaging_dir / "disp-decoy-invalid-schema"
        disp_dir_b.mkdir(parents=True, exist_ok=True)
        disp_app_b = disp_dir_b / self.app_path.name
        if disp_app_b.exists():
            shutil.rmtree(disp_app_b)
        shutil.copytree(relocated_app, disp_app_b, symlinks=False)

        info_plist_path = disp_app_b / "Contents" / "Info.plist"
        with open(info_plist_path, "rb") as fp:
            plist = plistlib.load(fp)

        resources_dir = disp_app_b / "Contents" / "Resources"
        probe_bundle = resources_dir / "metadata-probe.bundle"
        probe_res = probe_bundle / "Contents" / "Resources"
        probe_res.mkdir(parents=True, exist_ok=True)
        invalid_schema_data = {"schemaVersion": 999, "detectors": []}
        (probe_res / "DefaultDetectors.json").write_text(json.dumps(invalid_schema_data), encoding="utf-8")

        # Set both name and path to decoy bundle
        plist["AgentLensCoreResourceBundleName"] = "metadata-probe"
        plist["AgentLensCoreResourceBundlePath"] = "Contents/Resources/metadata-probe.bundle"
        with open(info_plist_path, "wb") as fp:
            plistlib.dump(plist, fp, fmt=plistlib.FMT_XML)

        binary = disp_app_b / "Contents" / "MacOS" / "AgentLensApp"
        proc = subprocess.run(
            [str(binary), "--bundle-preflight"],
            env=self.clean_env,
            capture_output=True,
            text=True,
            timeout=15
        )
        self.assertNotEqual(proc.returncode, 0, "Referenced invalid schema must exit nonzero")
        self.assertGreater(proc.returncode, 0, "Must exit with ordinary code")
        self.assertIn("bundle-preflight: failed: invalid detector registry data", proc.stderr)
        self.assertNotIn("/Users/", proc.stderr)
        shutil.rmtree(disp_dir_b)

        # Case C: Decoy exists with valid schema, both name and path set to decoy, but original bundle retained
        disp_dir_c = self.packaging_dir / "disp-decoy-definition-mismatch"
        disp_dir_c.mkdir(parents=True, exist_ok=True)
        disp_app_c = disp_dir_c / self.app_path.name
        if disp_app_c.exists():
            shutil.rmtree(disp_app_c)
        shutil.copytree(relocated_app, disp_app_c, symlinks=False)

        info_plist_path = disp_app_c / "Contents" / "Info.plist"
        with open(info_plist_path, "rb") as fp:
            plist = plistlib.load(fp)

        resources_dir = disp_app_c / "Contents" / "Resources"
        mismatch_bundle = resources_dir / "mismatch.bundle"
        mismatch_res = mismatch_bundle / "Contents" / "Resources"
        mismatch_res.mkdir(parents=True, exist_ok=True)
        mismatch_data = {
            "schemaVersion": 1,
            "detectors": [
                {
                    "id": "single-decoy",
                    "displayName": "Decoy",
                    "executableName": "decoy",
                    "extraSearchRoots": []
                }
            ]
        }
        (mismatch_res / "DefaultDetectors.json").write_text(json.dumps(mismatch_data), encoding="utf-8")

        plist["AgentLensCoreResourceBundleName"] = "mismatch"
        plist["AgentLensCoreResourceBundlePath"] = "Contents/Resources/mismatch.bundle"
        with open(info_plist_path, "wb") as fp:
            plistlib.dump(plist, fp, fmt=plistlib.FMT_XML)

        binary = disp_app_c / "Contents" / "MacOS" / "AgentLensApp"
        proc = subprocess.run(
            [str(binary), "--bundle-preflight"],
            env=self.clean_env,
            capture_output=True,
            text=True,
            timeout=15
        )
        self.assertNotEqual(proc.returncode, 0, "Guarded vs loaded definition mismatch must exit nonzero")
        self.assertGreater(proc.returncode, 0, "Must exit with ordinary code")
        self.assertIn("bundle-preflight: failed: loaded registry mismatch with guarded bundle", proc.stderr)
        self.assertNotIn("/Users/", proc.stderr)
        shutil.rmtree(disp_dir_c)

        # Case D: Actual expected Core bundle absent while a decoy exists and path points to it
        disp_dir_d = self.packaging_dir / "disp-expected-bundle-absent"
        disp_dir_d.mkdir(parents=True, exist_ok=True)
        disp_app_d = disp_dir_d / self.app_path.name
        if disp_app_d.exists():
            shutil.rmtree(disp_app_d)
        shutil.copytree(relocated_app, disp_app_d, symlinks=False)

        info_plist_path = disp_app_d / "Contents" / "Info.plist"
        with open(info_plist_path, "rb") as fp:
            plist = plistlib.load(fp)

        # Remove the actual expected bundle
        expected_rel = plist["AgentLensCoreResourceBundlePath"]
        expected_dir = disp_app_d / expected_rel
        if expected_dir.exists():
            shutil.rmtree(expected_dir)

        # Create decoy bundle
        resources_dir = disp_app_d / "Contents" / "Resources"
        decoy_bundle_d = resources_dir / "decoy-d.bundle"
        decoy_res_d = decoy_bundle_d / "Contents" / "Resources"
        decoy_res_d.mkdir(parents=True, exist_ok=True)
        (decoy_res_d / "DefaultDetectors.json").write_text(json.dumps(valid_detector_data), encoding="utf-8")

        # Point path to decoy, while name still specifies expected bundle
        plist["AgentLensCoreResourceBundlePath"] = "Contents/Resources/decoy-d.bundle"
        with open(info_plist_path, "wb") as fp:
            plistlib.dump(plist, fp, fmt=plistlib.FMT_XML)

        binary = disp_app_d / "Contents" / "MacOS" / "AgentLensApp"
        proc = subprocess.run(
            [str(binary), "--bundle-preflight"],
            env=self.clean_env,
            capture_output=True,
            text=True,
            timeout=15
        )
        self.assertNotEqual(proc.returncode, 0, "Absent expected bundle must exit nonzero")
        self.assertGreater(proc.returncode, 0, "Must exit with ordinary code, not fatalError crash")
        self.assertIn("bundle-preflight: failed:", proc.stderr)
        self.assertNotIn("/Users/", proc.stderr)
        shutil.rmtree(disp_dir_d)

        # Case E: Missing generated name metadata
        disp_dir_e = self.packaging_dir / "disp-missing-name-metadata"
        disp_dir_e.mkdir(parents=True, exist_ok=True)
        disp_app_e = disp_dir_e / self.app_path.name
        if disp_app_e.exists():
            shutil.rmtree(disp_app_e)
        shutil.copytree(relocated_app, disp_app_e, symlinks=False)

        info_plist_path = disp_app_e / "Contents" / "Info.plist"
        with open(info_plist_path, "rb") as fp:
            plist = plistlib.load(fp)
        plist.pop("AgentLensCoreResourceBundleName", None)
        with open(info_plist_path, "wb") as fp:
            plistlib.dump(plist, fp, fmt=plistlib.FMT_XML)

        binary = disp_app_e / "Contents" / "MacOS" / "AgentLensApp"
        proc = subprocess.run(
            [str(binary), "--bundle-preflight"],
            env=self.clean_env,
            capture_output=True,
            text=True,
            timeout=15
        )
        self.assertNotEqual(proc.returncode, 0, "Missing name metadata must exit nonzero")
        self.assertGreater(proc.returncode, 0, "Must exit with ordinary code")
        self.assertIn("bundle-preflight: failed: missing AgentLensCoreResourceBundleName in Info.plist", proc.stderr)
        self.assertNotIn("/Users/", proc.stderr)
        shutil.rmtree(disp_dir_e)

        # Case F: Debug override environment present
        binary = self.app_path / "Contents" / "MacOS" / "AgentLensApp"
        for env_var in ["PACKAGE_RESOURCE_BUNDLE_PATH", "PACKAGE_RESOURCE_BUNDLE_URL"]:
            override_env = dict(self.clean_env)
            override_env[env_var] = "/tmp/fake-override-path"
            proc = subprocess.run(
                [str(binary), "--bundle-preflight"],
                env=override_env,
                capture_output=True,
                text=True,
                timeout=15
            )
            self.assertNotEqual(proc.returncode, 0, f"Override env {env_var} must exit nonzero")
            self.assertGreater(proc.returncode, 0, "Must exit with ordinary code")
            self.assertIn("bundle-preflight: failed: resource override environment present", proc.stderr)
            self.assertNotIn("/tmp/fake-override-path", proc.stderr)
            self.assertNotIn("/Users/", proc.stderr)

def parse_args():
    parser = argparse.ArgumentParser(description="Test development macOS app bundle packaging and preflight.")
    parser.add_argument("--app", required=True, type=pathlib.Path, help="Path to the built .app bundle.")
    args, remaining = parser.parse_known_args()
    return args, remaining

if __name__ == "__main__":
    args, remaining = parse_args()
    APP_PATH = args.app
    unittest.main(argv=[sys.argv[0]] + remaining)
