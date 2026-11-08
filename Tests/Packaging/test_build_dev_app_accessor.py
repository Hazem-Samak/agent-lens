#!/usr/bin/env python3
# Focused pure-parser controls for scripts/build-dev-app.py step 3.
#
# LOCAL ONLY: this file is run explicitly with `python3 Tests/Packaging/test_build_dev_app_accessor.py`.
# The frozen CI packaging step invokes the ORIGINAL Tests/Packaging/test_dev_app_bundle.py --app
# directly, so it does not discover this file. The real native builder run in CI is what gates the
# native family end-to-end; these are the pure negative controls.
import sys
sys.dont_write_bytecode = True

import contextlib
import importlib.util
import io
import pathlib
import unittest

SCRIPT_PATH = pathlib.Path(__file__).resolve().parent.parent.parent / "scripts" / "build-dev-app.py"

# Captured verbatim from a real native SwiftPM 6.2.4 build (Bundle(path:) family).
NATIVE_624 = '''import Foundation

extension Foundation.Bundle {
    static nonisolated let module: Bundle = {
        let mainPath = Bundle.main.bundleURL.appendingPathComponent("AgentLens_AgentLensCore.bundle").path
        let buildPath = "/private/tmp/agent-lens-m10a-impl-20261026-4_wjuwpb/parent/r8-native-dev-app-before/swiftpm/arm64-apple-macosx/debug/AgentLens_AgentLensCore.bundle"

        let preferredBundle = Bundle(path: mainPath)

        guard let bundle = preferredBundle ?? Bundle(path: buildPath) else {
            // Users can write a function called fatalError themselves, we should be resilient against that.
            Swift.fatalError("could not load resource bundle: from \\(mainPath) or \\(buildPath)")
        }

        return bundle
    }()
}
'''

NATIVE_BIN_PATH = pathlib.Path(
    "/private/tmp/agent-lens-m10a-impl-20261026-4_wjuwpb/parent"
    "/r8-native-dev-app-before/swiftpm/arm64-apple-macosx/debug"
)

# The SwiftPM 6.4 local spelling of the same statement: `static let module` without `nonisolated`.
# Recognition must not key on the declaration spelling.
NATIVE_64 = NATIVE_624.replace("static nonisolated let module", "static let module")

# Captured verbatim from a real Swift Build (default backend) build: `bundleName` family.
SWIFT_BUILD = '''import class Foundation.Bundle
import class Foundation.ProcessInfo
import struct Foundation.URL

private class BundleFinder {}

extension Foundation.Bundle {
    /// Returns the resource bundle associated with the current Swift module.
    static nonisolated let module: Bundle = {
        let bundleName = "AgentLens_AgentLensCore"

        let overrides: [URL]
        #if DEBUG
        // The 'PACKAGE_RESOURCE_BUNDLE_PATH' name is preferred since the expected value is a path. The
        // check for 'PACKAGE_RESOURCE_BUNDLE_URL' will be removed when all clients have switched over.
        // This removal is tracked by rdar://107766372.
        if let override = ProcessInfo.processInfo.environment["PACKAGE_RESOURCE_BUNDLE_PATH"]
                       ?? ProcessInfo.processInfo.environment["PACKAGE_RESOURCE_BUNDLE_URL"] {
            overrides = [URL(fileURLWithPath: override)]
        } else {
            overrides = []
        }
        #else
        overrides = []
        #endif

        let candidates = overrides + [
            // Bundle should be present here when the package is linked into an App.
            Bundle.main.resourceURL,

            // Bundle should be present here when the package is linked into a framework.
            Bundle(for: BundleFinder.self).resourceURL,

            // For command-line tools.
            Bundle.main.bundleURL,
        ]

        for candidate in candidates {
            let bundlePath = candidate?.appendingPathComponent(bundleName + ".bundle")
            if let bundle = bundlePath.flatMap(Bundle.init(url:)) {
                return bundle
            }
        }
        fatalError("unable to find bundle named AgentLens_AgentLensCore")
    }()
}
'''


def load_build_dev_app_module():
    spec = importlib.util.spec_from_file_location("build_dev_app_accessor", SCRIPT_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


MODULE = load_build_dev_app_module()


class AccessorParserTests(unittest.TestCase):

    def interpret(self, content, bin_path=NATIVE_BIN_PATH):
        return MODULE.interpret_resource_accessor(content, bin_path)

    def assertRefused(self, content, *, bin_path=NATIVE_BIN_PATH, needle=None):
        with self.assertRaises(MODULE.AccessorInterpretationError) as cm:
            self.interpret(content, bin_path)
        message = str(cm.exception)
        self.assertNotIn("/private/tmp", message, "refusal text must not leak absolute build paths")
        if needle is not None:
            self.assertIn(needle, message)
        return message

    # MARK: Both measured families

    def test_native_624_family_yields_extension_free_stem(self):
        result = self.interpret(NATIVE_624)
        self.assertEqual(result["family"], "native")
        self.assertEqual(result["bundle_stem"], "AgentLens_AgentLensCore")
        self.assertEqual(result["bundle_filename"], "AgentLens_AgentLensCore.bundle")
        self.assertEqual(result["relative_bundle_path"], "Contents/Resources/AgentLens_AgentLensCore.bundle")

    def test_native_64_declaration_spelling_is_recognized(self):
        # `static let` instead of `static nonisolated let`: same family, same identity.
        self.assertEqual(self.interpret(NATIVE_64), self.interpret(NATIVE_624))

    def test_swift_build_family_yields_extension_free_stem(self):
        result = self.interpret(SWIFT_BUILD)
        self.assertEqual(result["family"], "swift-build")
        self.assertEqual(result["bundle_stem"], "AgentLens_AgentLensCore")
        self.assertEqual(result["bundle_filename"], "AgentLens_AgentLensCore.bundle")

    def test_cross_family_normalized_stem_path_and_filename_are_equal(self):
        native = self.interpret(NATIVE_624)
        swift_build = self.interpret(SWIFT_BUILD)
        self.assertEqual(native["bundle_stem"], swift_build["bundle_stem"])
        self.assertEqual(native["bundle_filename"], swift_build["bundle_filename"])
        self.assertEqual(native["relative_bundle_path"], swift_build["relative_bundle_path"])
        # Never `.bundle.bundle` and never a bare stem without the suffix.
        self.assertFalse(native["relative_bundle_path"].endswith(".bundle.bundle"))
        self.assertFalse(native["relative_bundle_path"].endswith("/"))
        self.assertEqual(
            native["relative_bundle_path"].rsplit("/", 1)[1],
            native["bundle_filename"],
        )

    def test_discriminating_before_case_native_shape_is_no_longer_refused(self):
        # Before the amendment the builder only matched `let bundleName = ...`; the native file
        # therefore failed at step 3. This is the discriminating regression control.
        import re
        self.assertIsNone(re.search(r'let\s+bundleName\s*=\s*"([^"]+)"', NATIVE_624))
        self.assertEqual(self.interpret(NATIVE_624)["bundle_stem"], "AgentLens_AgentLensCore")

    # MARK: Native buildPath pairing

    def test_native_buildpath_parent_mismatch_is_refused(self):
        mismatched = NATIVE_624.replace(
            "/private/tmp/agent-lens-m10a-impl-20261026-4_wjuwpb/parent/r8-native-dev-app-before/"
            "swiftpm/arm64-apple-macosx/debug/AgentLens_AgentLensCore.bundle",
            "/private/tmp/agent-lens-m10a-impl-20261026-4_wjuwpb/parent/other-build/"
            "arm64-apple-macosx/debug/AgentLens_AgentLensCore.bundle",
        )
        self.assertNotEqual(mismatched, NATIVE_624)
        self.assertRefused(mismatched, needle="does not equal the discovered bin-path")

    def test_native_buildpath_basename_mismatch_is_refused(self):
        mismatched = NATIVE_624.replace(
            'debug/AgentLens_AgentLensCore.bundle"',
            'debug/AgentLens_OtherCore.bundle"',
        )
        self.assertNotEqual(mismatched, NATIVE_624)
        self.assertRefused(mismatched, needle="basename does not match")

    def test_native_relative_buildpath_is_refused(self):
        relative = NATIVE_624.replace(
            'let buildPath = "/private/tmp/agent-lens-m10a-impl-20261026-4_wjuwpb/parent/'
            'r8-native-dev-app-before/swiftpm/arm64-apple-macosx/debug/AgentLens_AgentLensCore.bundle"',
            'let buildPath = "arm64-apple-macosx/debug/AgentLens_AgentLensCore.bundle"',
        )
        self.assertNotEqual(relative, NATIVE_624)
        self.assertRefused(relative, needle="not an absolute literal")

    def test_native_incomplete_accessor_is_refused(self):
        without_build_path = NATIVE_624.replace(
            '        let buildPath = "/private/tmp/agent-lens-m10a-impl-20261026-4_wjuwpb/parent/'
            'r8-native-dev-app-before/swiftpm/arm64-apple-macosx/debug/AgentLens_AgentLensCore.bundle"\n',
            "",
        )
        self.assertRefused(without_build_path, needle="incomplete native accessor")

    def test_native_missing_main_path_is_refused(self):
        without_main_path = NATIVE_624.replace(
            '        let mainPath = Bundle.main.bundleURL.appendingPathComponent('
            '"AgentLens_AgentLensCore.bundle").path\n',
            "",
        )
        self.assertNotEqual(without_main_path, NATIVE_624)
        self.assertRefused(without_main_path, needle="incomplete native accessor")

    def test_native_without_bundle_path_initializer_is_refused(self):
        stripped = NATIVE_624.replace("Bundle(path:", "Bundle(contentsOf:")
        self.assertRefused(stripped, needle="does not load its bundle from")

    def test_wasi_signature_is_refused(self):
        wasi = NATIVE_624.replace(
            "extension Foundation.Bundle {",
            "extension Foundation.Bundle {\n    let wasiMode = isWASI()\n",
        )
        self.assertNotEqual(wasi, NATIVE_624)
        self.assertRefused(wasi, needle="WASI")

    def test_wasi_mention_inside_a_comment_does_not_refuse_a_valid_native_file(self):
        # A comment mentioning WASI is not a WASI accessor; the real generated body still parses.
        annotated = NATIVE_624.replace(
            "import Foundation", "import Foundation\n// Not a WASI build.\n"
        )
        self.assertEqual(self.interpret(annotated)["bundle_stem"], "AgentLens_AgentLensCore")

    # MARK: Unsafe names and literal escapes

    def test_native_traversal_name_is_refused(self):
        traversal = NATIVE_624.replace(
            'appendingPathComponent("AgentLens_AgentLensCore.bundle")',
            'appendingPathComponent("../AgentLens_AgentLensCore.bundle")',
        )
        self.assertRefused(traversal, needle="path separator")

    def test_native_absolute_name_component_is_refused(self):
        absolute = NATIVE_624.replace(
            'appendingPathComponent("AgentLens_AgentLensCore.bundle")',
            'appendingPathComponent("/tmp/AgentLens_AgentLensCore.bundle")',
        )
        self.assertRefused(absolute, needle="path separator")

    def test_native_missing_bundle_suffix_is_refused(self):
        unsuffixed = NATIVE_624.replace('appendingPathComponent("AgentLens_AgentLensCore.bundle")',
                                        'appendingPathComponent("AgentLens_AgentLensCore")')
        self.assertRefused(unsuffixed, needle="does not end in .bundle")

    def test_native_doubled_bundle_suffix_is_refused(self):
        doubled = NATIVE_624.replace("AgentLens_AgentLensCore.bundle", "AgentLens_AgentLensCore.bundle.bundle")
        self.assertRefused(doubled, needle="doubled .bundle")

    def test_native_swift_escape_in_literal_is_refused(self):
        escaped = NATIVE_624.replace(
            'appendingPathComponent("AgentLens_AgentLensCore.bundle")',
            'appendingPathComponent("AgentLens\\u{5F}AgentLensCore.bundle")',
        )
        self.assertNotEqual(escaped, NATIVE_624)
        self.assertRefused(escaped, needle="Swift string escape")

    def test_native_backslash_in_buildpath_is_refused(self):
        backslash = NATIVE_624.replace(
            'debug/AgentLens_AgentLensCore.bundle"',
            'debug\\\\AgentLens_AgentLensCore.bundle"',
        )
        self.assertNotEqual(backslash, NATIVE_624)
        self.assertRefused(backslash, needle="Swift string escape")

    def test_swift_build_escaped_bundle_name_is_refused(self):
        escaped = SWIFT_BUILD.replace('let bundleName = "AgentLens_AgentLensCore"',
                                      'let bundleName = "AgentLens\\u{5F}AgentLensCore"')
        self.assertRefused(escaped, needle="Swift string escape")

    def test_swift_build_bundle_name_carrying_suffix_is_refused(self):
        suffixed = SWIFT_BUILD.replace('let bundleName = "AgentLens_AgentLensCore"',
                                       'let bundleName = "AgentLens_AgentLensCore.bundle"')
        self.assertRefused(suffixed, needle="already carries .bundle")

    def test_swift_build_slash_in_bundle_name_is_refused(self):
        slashed = SWIFT_BUILD.replace('let bundleName = "AgentLens_AgentLensCore"',
                                      'let bundleName = "nested/AgentLens_AgentLensCore"')
        self.assertRefused(slashed, needle="path separator")

    # MARK: False matches in comments and strings

    def test_line_comment_only_template_is_refused(self):
        # Every line of a COMPLETE Swift Build template, commented out. Nothing is declared in
        # code position, so nothing may be accepted.
        commented = "\n".join("// " + line for line in SWIFT_BUILD.splitlines())
        self.assertRefused(commented, needle="unsupported compiled accessor shape")

    def test_block_comment_only_template_is_refused(self):
        commented = "/*\n" + SWIFT_BUILD + "\n*/"
        self.assertRefused(commented, needle="unsupported compiled accessor shape")

    def test_single_line_comment_bundle_name_is_refused(self):
        bait = '// let bundleName = "AgentLens_AgentLensCore"\n'
        self.assertRefused(bait, needle="unsupported compiled accessor shape")

    def test_string_only_template_is_refused(self):
        # A complete template inside one multi-line string literal: it is data, not code.
        quoted = 'let decoy = """\n' + SWIFT_BUILD + '\n"""\n'
        self.assertRefused(quoted)

    def test_duplicate_bundle_name_declarations_are_refused(self):
        duplicated = SWIFT_BUILD.replace(
            'let bundleName = "AgentLens_AgentLensCore"',
            'let bundleName = "AgentLens_AgentLensCore"\n        let bundleName = "AgentLens_Other"',
        )
        self.assertNotEqual(duplicated, SWIFT_BUILD)
        self.assertRefused(duplicated, needle="duplicate bundleName declaration")

    def test_duplicate_native_build_path_declarations_are_refused(self):
        line = ('        let buildPath = "/private/tmp/agent-lens-m10a-impl-20261026-4_wjuwpb/parent/'
                'r8-native-dev-app-before/swiftpm/arm64-apple-macosx/debug/'
                'AgentLens_AgentLensCore.bundle"')
        duplicated = NATIVE_624.replace(line, line + "\n" + line)
        self.assertNotEqual(duplicated, NATIVE_624)
        self.assertRefused(duplicated, needle="duplicate mainPath or buildPath declaration")

    def test_native_loader_on_unrelated_bindings_is_refused(self):
        # Both declarations are literal but the loader uses different identifiers.
        wrong = NATIVE_624.replace("Bundle(path: mainPath)", "Bundle(path: someOtherPath)")
        self.assertNotEqual(wrong, NATIVE_624)
        self.assertRefused(
            wrong, needle="does not load its bundle from the mainPath/buildPath bindings"
        )

    def test_native_loader_on_another_literal_is_refused(self):
        wrong = NATIVE_624.replace("Bundle(path: buildPath)", 'Bundle(path: "/tmp/elsewhere.bundle")')
        self.assertNotEqual(wrong, NATIVE_624)
        self.assertRefused(
            wrong, needle="does not load its bundle from the mainPath/buildPath bindings"
        )

    def test_native_commented_loader_does_not_satisfy_the_loader(self):
        wrong = NATIVE_624.replace("Bundle(path: buildPath)", "Bundle(contentsOf: buildPath)")
        wrong = wrong.replace(
            "let preferredBundle", "// Bundle(path: buildPath)\n        let preferredBundle"
        )
        self.assertNotEqual(wrong, NATIVE_624)
        self.assertRefused(
            wrong, needle="does not load its bundle from the mainPath/buildPath bindings"
        )

    def test_swift_build_wrong_suffix_literal_is_refused(self):
        # The bound suffix is the thing that becomes the filename; guessing `.bundle` from a
        # `+ ".wrong"` expression would fabricate an identity the accessor never asks for.
        wrong = SWIFT_BUILD.replace('bundleName + ".bundle"', 'bundleName + ".wrong"')
        self.assertNotEqual(wrong, SWIFT_BUILD)
        self.assertRefused(wrong, needle='unsupported bundle suffix literal: expected ".bundle"')

    def test_swift_build_doubled_suffix_append_is_refused(self):
        doubled = SWIFT_BUILD.replace(
            'bundleName + ".bundle"',
            'bundleName + ".bundle" + ".bundle"',
        )
        self.assertNotEqual(doubled, SWIFT_BUILD)
        self.assertRefused(doubled, needle="chained append")

    def test_swift_build_suffix_in_a_comment_does_not_satisfy_the_lookup(self):
        commented = SWIFT_BUILD.replace('bundleName + ".bundle"', 'bundleName + suffixName')
        commented = commented.replace(
            "let candidates", '// bundleName + ".bundle"\n        let candidates'
        )
        self.assertRefused(commented, needle="without the supported Swift Build candidate lookup")

    def test_candidate_list_without_bundle_name_is_refused(self):
        bait = SWIFT_BUILD.replace('let bundleName = "AgentLens_AgentLensCore"',
                                   'let notBundleName = "AgentLens_AgentLensCore"')
        self.assertRefused(bait, needle="without a literal bundleName")

    def test_arbitrary_text_is_refused(self):
        self.assertRefused("", needle="unsupported compiled accessor shape")
        self.assertRefused("let module = Bundle.module\n", needle="unsupported compiled accessor shape")

    def test_dual_family_accessor_is_refused(self):
        dual = SWIFT_BUILD + "\n" + NATIVE_624
        self.assertRefused(dual, needle="both the Swift Build and native families")

    def test_non_text_content_is_refused(self):
        with self.assertRaises(MODULE.AccessorInterpretationError) as cm:
            MODULE.interpret_resource_accessor(b"bytes", NATIVE_BIN_PATH)
        self.assertIn("not text", str(cm.exception))

    # MARK: Scratch-root policy is unchanged by this amendment

    def test_validate_scratch_root_still_rejects_broad_roots(self):
        repo_root = SCRIPT_PATH.parent.parent
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as cm:
                MODULE.validate_scratch_root(pathlib.Path("/private/tmp"), repo_root)
        self.assertEqual(cm.exception.code, 1)


if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0]] + sys.argv[1:])