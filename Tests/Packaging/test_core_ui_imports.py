#!/usr/bin/env python3
"""Behavioral fixtures for `scripts/check-core-ui-imports.py` (D-002 boundary guard).

Direct entrypoint: `python3 Tests/Packaging/test_core_ui_imports.py` returns nonzero if any
case fails. These are behavior tests: each case writes Swift source into a disposable
source-root copy and invokes the real guard CLI, asserting accept/reject and — for rejects —
that the reported location names the offending file and line. They never touch the real
`Sources/AgentLensCore` and never snapshot the guard's implementation text.

The plant/fail/clean/pass cycle runs against a copy of the REAL source tree, so a regression in
the shipping sources is caught the same way CI catches it.
"""
import sys

sys.dont_write_bytecode = True

import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
GUARD = REPO_ROOT / "scripts" / "check-core-ui-imports.py"
REAL_SOURCE_ROOT = REPO_ROOT / "Sources" / "AgentLensCore"


def run_guard(source_root):
    return subprocess.run(
        [sys.executable, str(GUARD), "--source-root", str(source_root)],
        capture_output=True,
        text=True,
    )


class CoreUIImportGuardTests(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory(prefix="agentlens-core-guard-")
        self.addCleanup(self.tempdir.cleanup)
        self.root = pathlib.Path(self.tempdir.name)

    def make_tree(self, files):
        """Write `{relative path: source}` into a fresh root and return it."""
        for relative, source in files.items():
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(source, encoding="utf-8")
        return self.root

    def assert_rejected(self, files, *, module, method_name="test_forbidden_import_is_rejected"):
        root = self.make_tree(files)
        result = run_guard(root)
        self.assertEqual(result.returncode, 1, f"expected rejection; stdout={result.stdout!r} stderr={result.stderr!r}")
        self.assertIn("forbidden", result.stdout, result.stdout)
        self.assertIn(module, result.stdout, result.stdout)
        for relative in files:
            self.assertIn(str(root / relative), result.stdout, "violation must name the source path")
        return result

    # -- acceptance: the real tree and legal Foundation/comments/strings ----------------------

    def test_real_source_tree_is_clean(self):
        self.assertTrue(REAL_SOURCE_ROOT.is_dir())
        result = run_guard(REAL_SOURCE_ROOT)
        self.assertEqual(result.returncode, 0, f"stdout={result.stdout!r} stderr={result.stderr!r}")
        self.assertIn("no SwiftUI/AppKit imports", result.stdout)

    def test_foundation_and_mentions_in_comments_and_strings_are_accepted(self):
        root = self.make_tree(
            {
                "Engine/Acceptable.swift": (
                    "import Foundation\n"
                    "// AppKit and SwiftUI are forbidden here (D-002).\n"
                    "/* import AppKit\n"
                    "   import SwiftUI */\n"
                    "let note = \"import SwiftUI is not allowed\"\n"
                    "let appKitName = \"AppKit\"\n"
                    "let raw = #\"import AppKit\"#\n"
                    "let multiline = \"\"\"\n"
                    "import SwiftUI\n"
                    "\"\"\"\n"
                    "let nested = \"\"\"\n"
                    "/* import AppKit */\n"
                    "\"\"\"\n"
                    "struct ImportPolicy { let module = \"SwiftUI\" }\n"
                    "import AppKitShim\n"
                ),
            }
        )
        result = run_guard(root)
        self.assertEqual(result.returncode, 0, f"stdout={result.stdout!r} stderr={result.stderr!r}")

    # -- rejection: plain, attributed, scoped, conditional, multiline ------------------------

    def test_plain_swiftui_import_is_rejected_with_location(self):
        result = self.assert_rejected(
            {"Engine/A.swift": "import Foundation\nimport SwiftUI\n"},
            module="SwiftUI",
        )
        self.assertIn("A.swift:2:", result.stdout)

    def test_plain_appkit_import_is_rejected(self):
        self.assert_rejected({"Engine/B.swift": "import AppKit\n"}, module="AppKit")

    def test_attributed_and_conditional_imports_are_rejected(self):
        self.assert_rejected(
            {
                "Engine/Attributed.swift": (
                    "import Foundation\n"
                    "@preconcurrency import AppKit\n"
                ),
            },
            module="AppKit",
        )
        self.assert_rejected(
            {
                "Engine/Conditional.swift": (
                    "import Foundation\n"
                    "#if canImport(SwiftUI)\n"
                    "import SwiftUI\n"
                    "#endif\n"
                ),
            },
            module="SwiftUI",
        )

    def test_scoped_imports_are_rejected(self):
        for declaration, module in (
            ("struct", "AppKit"),
            ("class", "AppKit"),
            ("enum", "AppKit"),
            ("protocol", "AppKit"),
            ("typealias", "AppKit"),
            ("func", "AppKit"),
            ("var", "AppKit"),
            ("let", "AppKit"),
        ):
            with self.subTest(declaration=declaration):
                self.assert_rejected(
                    {"Engine/Scoped.swift": f"import {declaration} {module}.SomeMember\n"},
                    module=module,
                )

    def test_multiline_and_whitespace_spellings_are_rejected(self):
        self.assert_rejected(
            {
                "Engine/Multiline.swift": "import   SwiftUI\n",
            },
            module="SwiftUI",
        )
        self.assert_rejected(
            {
                "Engine/Split.swift": (
                    "@available(macOS, deprecated: 26.0)\n"
                    "import AppKit\n"
                ),
            },
            module="AppKit",
        )

    def test_statement_boundaries_semicolons_and_escaped_identifiers_are_rejected(self):
        # Each of these is valid Swift that an earlier line-anchored matcher missed.
        cases = {
            "trailing_semicolon": ("import AppKit;\n", 1),
            "second_statement_same_line": ("import Foundation; import AppKit\n", 1),
            "escaped_module_identifier": ("import `AppKit`\n", 1),
            "scoped_escaped_member": ("import `SwiftUI`.`View`\n", 1),
            "after_closing_brace": ("struct S {}\nimport SwiftUI\n", 2),
        }
        for name, (source, line_number) in cases.items():
            with self.subTest(name=name):
                directory = self.root / name
                directory.mkdir(parents=True, exist_ok=True)
                (directory / "Probe.swift").write_text(source, encoding="utf-8")
                result = run_guard(directory)
                self.assertEqual(
                    result.returncode, 1,
                    f"{name} must be rejected; stdout={result.stdout!r} stderr={result.stderr!r}",
                )
                self.assertIn("forbidden", result.stdout)
                self.assertIn(f"Probe.swift:{line_number}:", result.stdout, "the reported line must be accurate")

    def test_identifier_that_merely_contains_a_module_name_is_accepted(self):
        root = self.make_tree(
            {
                "Engine/Lookalikes.swift": (
                    "import Foundation\n"
                    "import AppKitShim\n"
                    "let reimportedSwiftUI = 1\n"
                    "let dotted = \"a.AppKit.b\"\n"
                ),
            }
        )
        result = run_guard(root)
        self.assertEqual(result.returncode, 0, f"stdout={result.stdout!r} stderr={result.stderr!r}")

    def test_nested_source_directory_is_scanned(self):
        self.assert_rejected(
            {"Deep/Nested/Path/Violation.swift": "import SwiftUI\n"},
            module="SwiftUI",
        )

    # -- failure modes: missing / unreadable root -------------------------------------------

    def test_missing_source_root_fails(self):
        missing = self.root / "does-not-exist"
        result = run_guard(missing)
        self.assertEqual(result.returncode, 2, f"stdout={result.stdout!r} stderr={result.stderr!r}")
        self.assertIn("source root is not a directory", result.stderr)

    def test_file_instead_of_directory_fails(self):
        not_a_directory = self.root / "Sources.swift"
        not_a_directory.write_text("import Foundation\n", encoding="utf-8")
        result = run_guard(not_a_directory)
        self.assertEqual(result.returncode, 2, f"stdout={result.stdout!r} stderr={result.stderr!r}")

    @unittest.skipIf(os.geteuid() == 0, "root bypasses file permissions")
    def test_unreadable_input_fails(self):
        root = self.make_tree({"Engine/Unreadable.swift": "import Foundation\n"})
        target = root / "Engine" / "Unreadable.swift"
        target.chmod(0o000)
        self.addCleanup(lambda: target.chmod(0o644))
        result = run_guard(root)
        self.assertEqual(result.returncode, 2, f"stdout={result.stdout!r} stderr={result.stderr!r}")
        self.assertIn("Unreadable.swift", result.stderr)

    @unittest.skipIf(os.geteuid() == 0, "root bypasses directory permissions")
    def test_unreadable_source_root_fails_closed(self):
        # An inaccessible ROOT must be a hard failure. A traversal that silently skips it would
        # report "0 Swift files ... clean" and hide a real forbidden import sitting right there.
        root = self.make_tree({"Engine/Hidden.swift": "import AppKit\n"})
        try:
            root.chmod(0o000)
            result = run_guard(root)
        finally:
            root.chmod(0o755)
        self.assertEqual(result.returncode, 2, f"stdout={result.stdout!r} stderr={result.stderr!r}")
        self.assertIn("Permission denied", result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        self.assertNotIn("no SwiftUI/AppKit imports", result.stdout)

    @unittest.skipIf(os.geteuid() == 0, "root bypasses directory permissions")
    def test_unreadable_nested_directory_fails_closed(self):
        # A partial scan must never pass: the forbidden import lives inside the unreadable subtree.
        root = self.make_tree(
            {
                "Engine/Visible.swift": "import Foundation\n",
                "Engine/Nested/Hidden.swift": "import SwiftUI\n",
            }
        )
        nested = root / "Engine" / "Nested"
        try:
            nested.chmod(0o000)
            result = run_guard(root)
        finally:
            nested.chmod(0o755)
        self.assertEqual(result.returncode, 2, f"stdout={result.stdout!r} stderr={result.stderr!r}")
        self.assertIn("Permission denied", result.stderr)
        self.assertIn("Nested", result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        self.assertNotIn("no SwiftUI/AppKit imports", result.stdout)

    @unittest.skipIf(os.geteuid() == 0, "root bypasses directory permissions")
    def test_restored_permissions_allow_a_real_scan_again(self):
        # The previous two cases must leave the tree usable: restoration is verified by outcome.
        root = self.make_tree({"Engine/Nested/Hidden.swift": "import AppKit\n"})
        nested = root / "Engine" / "Nested"
        try:
            nested.chmod(0o000)
            self.assertEqual(run_guard(root).returncode, 2)
        finally:
            nested.chmod(0o755)
        result = run_guard(root)
        self.assertEqual(result.returncode, 1, f"stdout={result.stdout!r} stderr={result.stderr!r}")
        self.assertIn("Hidden.swift:1:", result.stdout)

    # -- symlinked entries must fail closed, never be silently skipped ----------------------

    @unittest.skipIf(os.geteuid() == 0, "root bypasses directory permissions")
    def test_symlinked_directory_is_refused_by_name(self):
        # A symlinked directory could hold a forbidden import. Following it may escape the tree or
        # loop; ignoring it silently excludes what it points at. Both are refused by name.
        real = self.root / "real"
        real.mkdir(parents=True)
        (real / "Hidden.swift").write_text("import AppKit" + chr(10), encoding="utf-8")
        root = self.root / "inspect"
        root.mkdir()
        (root / "linked").symlink_to(real, target_is_directory=True)

        result = run_guard(root)
        self.assertEqual(result.returncode, 2, f"stdout={result.stdout!r} stderr={result.stderr!r}")
        self.assertIn("symlinked source dir is not supported", result.stderr)
        self.assertIn("linked", result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        self.assertNotIn("no SwiftUI/AppKit imports", result.stdout)

    @unittest.skipIf(os.geteuid() == 0, "root bypasses directory permissions")
    def test_symlinked_swift_file_is_refused_by_name(self):
        real = self.root / "real.swift"
        real.write_text("import SwiftUI" + chr(10), encoding="utf-8")
        root = self.root / "inspect"
        root.mkdir()
        (root / "Linked.swift").symlink_to(real)

        result = run_guard(root)
        self.assertEqual(result.returncode, 2, f"stdout={result.stdout!r} stderr={result.stderr!r}")
        self.assertIn("symlinked source file is not supported", result.stderr)
        self.assertNotIn("Traceback", result.stderr)

    @unittest.skipIf(os.geteuid() == 0, "root bypasses directory permissions")
    def test_looping_and_dangling_symlinks_are_refused(self):
        root = self.root / "inspect"
        root.mkdir()
        (root / "loop").symlink_to(root / "loop")
        result = run_guard(root)
        self.assertEqual(result.returncode, 2, f"stdout={result.stdout!r} stderr={result.stderr!r}")
        self.assertIn("symlinked source", result.stderr)
        self.assertNotIn("Traceback", result.stderr)

        (root / "loop").unlink()
        (root / "dangling").symlink_to(root / "missing-target", target_is_directory=True)
        result = run_guard(root)
        self.assertEqual(result.returncode, 2, f"stdout={result.stdout!r} stderr={result.stderr!r}")
        self.assertIn("symlinked source", result.stderr)

    def test_regular_tree_without_symlinks_still_passes(self):
        root = self.make_tree({"Engine/Plain.swift": "import Foundation" + chr(10)})
        result = run_guard(root)
        self.assertEqual(result.returncode, 0, f"stdout={result.stdout!r} stderr={result.stderr!r}")

    # -- entrypoint contract: plant / fail / clean / pass against a real-tree copy -----------

    def test_plant_fail_clean_pass_cycle_on_real_tree_copy(self):
        copy_root = self.root / "AgentLensCore"
        shutil.copytree(REAL_SOURCE_ROOT, copy_root)

        clean = run_guard(copy_root)
        self.assertEqual(clean.returncode, 0, f"copied baseline must pass; stderr={clean.stderr!r}")

        planted = copy_root / "PlantedForbiddenImport.swift"
        planted.write_text("import Foundation\nimport SwiftUI\n", encoding="utf-8")
        failed = run_guard(copy_root)
        self.assertEqual(failed.returncode, 1, f"plant must fail; stdout={failed.stdout!r}")
        self.assertIn("PlantedForbiddenImport.swift:2:", failed.stdout)
        self.assertIn("SwiftUI", failed.stdout)

        planted.unlink()
        passed = run_guard(copy_root)
        self.assertEqual(passed.returncode, 0, f"removal must restore a clean pass; stderr={passed.stderr!r}")

        self.assertTrue(REAL_SOURCE_ROOT.is_dir(), "the real source tree must never be the edit target")
        self.assertFalse((REAL_SOURCE_ROOT / "PlantedForbiddenImport.swift").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)