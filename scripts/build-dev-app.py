#!/usr/bin/env python3
# Postponed annotations keep this file importable on the oldest supported interpreter: PEP 604
# unions such as `str | None` in helper annotations would otherwise evaluate at import time and
# fail on Python 3.9, which the unmodified builder already ran under. The annotations are
# documentation only; no runtime logic depends on evaluating them.
from __future__ import annotations

import sys
sys.dont_write_bytecode = True

import argparse
import os
import pathlib
import plistlib
import re
import shutil
import subprocess

def is_contained_in(path: pathlib.Path, base: pathlib.Path) -> bool:
    try:
        return path == base or path.is_relative_to(base)
    except AttributeError:
        return path == base or base in path.parents

class AccessorInterpretationError(Exception):
    """Raised by interpret_resource_accessor for any unsupported, ambiguous or unsafe accessor.

    Messages are stable and path-free (no absolute build paths) so the caller can prefix them
    with its own diagnostic channel without leaking scratch locations.
    """


def _refuse_swift_literal_escapes(literal: str, origin: str) -> None:
    # The extracted text is used verbatim as a filesystem name/path component. A backslash or
    # an embedded quote means the literal was not fully understood; escapes are NEVER decoded.
    if "\\" in literal:
        raise AccessorInterpretationError(f"{origin} contains a Swift string escape")
    if '"' in literal:
        raise AccessorInterpretationError(f"{origin} contains an embedded quote")
    if "\x00" in literal:
        raise AccessorInterpretationError(f"{origin} contains NUL")


def _validated_bundle_filename(filename: str, origin: str) -> str:
    # Exactly one safe path component ending in `.bundle`: no separators, no traversal, no
    # leading dot, no empty stem, no doubled suffix.
    if not filename:
        raise AccessorInterpretationError(f"{origin} is empty")
    if "/" in filename or "\\" in filename:
        raise AccessorInterpretationError(f"{origin} contains a path separator")
    if filename in (".", "..") or filename.startswith("."):
        raise AccessorInterpretationError(f"{origin} is a dot or hidden component")
    if not filename.endswith(".bundle"):
        raise AccessorInterpretationError(f"{origin} does not end in .bundle")
    if filename.endswith(".bundle.bundle"):
        raise AccessorInterpretationError(f"{origin} has a doubled .bundle suffix")
    stem = filename[: -len(".bundle")]
    if not stem:
        raise AccessorInterpretationError(f"{origin} has an empty bundle stem")
    if any(ch.isspace() or ord(ch) < 0x20 or ord(ch) == 0x7F for ch in stem):
        raise AccessorInterpretationError(f"{origin} contains whitespace or control characters")
    return filename


def _lexical_view(content: str) -> tuple[str, str]:
    """Split one Swift source into (code view, literal view) with identical offsets.

    This is a lexical splitter, not a Swift parser: it exists only so that a declaration or a
    call is recognised in CODE position and never inside a comment or an unrelated string. Both
    results have exactly `len(content)` characters; the code view replaces every comment
    character and every string-literal character with a space, while the literal view keeps the
    ORIGINAL characters only inside string literals and spaces everywhere else. A character
    therefore belongs to code, to a literal, or to a comment.

    Supported lexical shapes are only those that appear in generated accessors: `//` line
    comments, nested `/* */` block comments, and single-line `"..."` string literals without
    interpolation. Interpolation, multi-line literals and unknown escapes are refused by the
    caller's literal validation rather than guessed at.
    """
    code = list(content)
    literal = [" "] * len(content)
    i = 0
    n = len(content)
    while i < n:
        ch = content[i]
        if ch == "/" and i + 1 < n and content[i + 1] == "/":
            while i < n and content[i] != "\n":
                code[i] = " "
                i += 1
            continue
        if ch == "/" and i + 1 < n and content[i + 1] == "*":
            depth = 1
            code[i] = code[i + 1] = " "
            i += 2
            while i < n and depth:
                if content[i] == "/" and i + 1 < n and content[i + 1] == "*":
                    depth += 1
                    code[i] = code[i + 1] = " "
                    i += 2
                    continue
                if content[i] == "*" and i + 1 < n and content[i + 1] == "/":
                    depth -= 1
                    code[i] = code[i + 1] = " "
                    i += 2
                    continue
                code[i] = " "
                i += 1
            continue
        if ch == "\"":
            # String literal. Quotes stay in the code view (they are code); only the CONTENT is
            # blanked there and preserved in the literal view. `"""..."""` spans lines; the
            # shorter form stops at a newline, so a malformed source fails closed.
            if content.startswith('"""', i):
                i += 3
                while i < n and not content.startswith('"""', i):
                    literal[i] = content[i]
                    code[i] = " "
                    i += 1
                i = min(i + 3, n)
                continue
            i += 1
            while i < n and content[i] != "\"" and content[i] != "\n":
                literal[i] = content[i]
                code[i] = " "
                i += 1
            if i < n and content[i] == "\"":
                i += 1
            continue
        i += 1
    return "".join(code), "".join(literal)


def _literal_at(content: str, literal_view: str, start: int, end: int) -> str:
    """The literal text between the quotes spanning [start, end), taken from the ORIGINAL source."""
    return literal_view[start:end]


def _swift_build_stem(content: str) -> str | None:
    """Return the bundle stem for the Swift Build family, or None when that family is absent.

    Presence requires, all in CODE position: a `let bundleName = "<stem>"` declaration whose
    literal is the binding, and the candidate-lookup shape that consumes that same binding.
    Comment- or string-embedded lookalikes contribute nothing, and a duplicated declaration is
    ambiguous and refused.
    """
    code, literal_view = _lexical_view(content)
    declarations = list(re.finditer(r'let\s+bundleName\s*=\s*"', code))
    # The generator appends a suffix to the binding. The suffix must be exactly the literal
    # ".bundle" and must happen exactly once: a `+ ".wrong"`, a doubled append, or several
    # conflicting appends are all unsupported expressions and are refused rather than assumed.
    suffix_literals = []
    for match in re.finditer(r"\bbundleName\s*\+\s*\"", code):
        suffix_start = match.end()
        suffix_match = re.match(r'([^"\n]*)"', code[suffix_start:])
        if suffix_match is None:
            raise AccessorInterpretationError(
                "unsupported bundle suffix expression: not a single-line literal"
            )
        suffix_literals.append(
            _literal_at(content, literal_view, suffix_start, suffix_start + len(suffix_match.group(1)))
        )
        # A chain such as `+".bundle" + ".bundle"` is not the generated expression. Only a
        # single append is supported, and only with the exact `.bundle` suffix.
        after = code[suffix_start + len(suffix_match.group(1)) + 1:]
        if re.match(r'\s*\+', after):
            raise AccessorInterpretationError(
                "unsupported bundle suffix expression: chained append"
            )
    has_candidate_list = (
        "Bundle.main.resourceURL" in code
        and bool(suffix_literals)
        and ("Bundle.init(url:)" in code or "Bundle(url:)" in code)
    )
    if len(suffix_literals) > 1:
        raise AccessorInterpretationError(
            "ambiguous accessor: bundleName suffix is appended more than once"
        )
    if suffix_literals and suffix_literals[0] != ".bundle":
        raise AccessorInterpretationError(
            "unsupported bundle suffix literal: expected \".bundle\""
        )
    if not declarations:
        if has_candidate_list:
            raise AccessorInterpretationError(
                "Swift Build candidate lookup without a literal bundleName"
            )
        return None
    if len(declarations) > 1:
        raise AccessorInterpretationError("ambiguous accessor: duplicate bundleName declaration")
    if not has_candidate_list:
        raise AccessorInterpretationError(
            "bundleName declaration without the supported Swift Build candidate lookup"
        )

    match = re.match(r'([^"\n]*)"', code[declarations[0].end():])
    if match is None or declarations[0].end() + len(match.group(1)) >= len(code):
        raise AccessorInterpretationError("bundleName literal is not a single-line string")
    stem = _literal_at(
        content, literal_view,
        declarations[0].end(), declarations[0].end() + len(match.group(1)),
    )
    _refuse_swift_literal_escapes(stem, "bundleName")
    if stem.endswith(".bundle"):
        raise AccessorInterpretationError("Swift Build bundleName already carries .bundle")
    return stem


def _native_literal_paths(content: str) -> tuple[str, str] | None:
    """Return (mainPath component, buildPath literal) for the native family, else None.

    The generated body binds `mainPath` and `buildPath`, then loads
    `Bundle(path: mainPath)` and falls back to `Bundle(path: buildPath)`. Recognition requires
    those EXACT bindings in code position: a `Bundle(path:)` call on some other expression does
    not establish this family, and duplicated bindings are ambiguous.
    """
    code, literal_view = _lexical_view(content)
    main_decls = list(re.finditer(r'let\s+mainPath\s*=\s*Bundle\.main\.bundleURL'
                                 r'\.appendingPathComponent\(\s*"', code))
    build_decls = list(re.finditer(r'let\s+buildPath\s*=\s*"', code))
    if not main_decls and not build_decls:
        return None
    if not main_decls or not build_decls:
        raise AccessorInterpretationError(
            "incomplete native accessor: mainPath and buildPath must both be literals"
        )
    if len(main_decls) > 1 or len(build_decls) > 1:
        raise AccessorInterpretationError(
            "ambiguous native accessor: duplicate mainPath or buildPath declaration"
        )
    if "WASI" in code:
        raise AccessorInterpretationError("WASI resource accessor shapes are not supported")

    loads_main = re.search(r'Bundle\(\s*path:\s*mainPath\s*\)', code) is not None
    loads_build = re.search(r'Bundle\(\s*path:\s*buildPath\s*\)', code) is not None
    if not (loads_main and loads_build):
        raise AccessorInterpretationError(
            "native accessor does not load its bundle from the mainPath/buildPath bindings"
        )
    if "Bundle.path(forResource:" in code or "appendingPathComponent" not in code:
        raise AccessorInterpretationError("unsupported native resource lookup shape")

    main_start = main_decls[0].end()
    main_match = re.match(r'([^"\n]*)"', code[main_start:])
    if main_match is None:
        raise AccessorInterpretationError("native mainPath component is not a single-line string")
    main_component = _literal_at(content, literal_view, main_start, main_start + len(main_match.group(1)))

    build_start = build_decls[0].end()
    build_match = re.match(r'([^"\n]*)"', code[build_start:])
    if build_match is None:
        raise AccessorInterpretationError("native buildPath is not a single-line string")
    build_literal = _literal_at(content, literal_view, build_start, build_start + len(build_match.group(1)))

    _refuse_swift_literal_escapes(main_component, "native mainPath component")
    _refuse_swift_literal_escapes(build_literal, "native buildPath")
    return main_component, build_literal


def interpret_resource_accessor(
    content: str,
    bin_path: pathlib.Path,
) -> dict:
    """Interpret a compiled `resource_bundle_accessor.swift`; return the bundle identity.

    Pure: no filesystem reads, no Swift evaluation, no bundle-name guessing and no directory
    searching. Exactly two generated accessor families are recognised, keyed on their emitted
    statements rather than on incidental declaration spelling:

      family "swift-build" — `let bundleName = "<stem>"` plus the candidate list that appends
        `<bundleName> + ".bundle"` and loads it with `Bundle.init(url:)`.
      family "native" — a literal `Bundle.main.bundleURL.appendingPathComponent("<file>.bundle").path`
        paired with an absolute literal `buildPath` of the same basename, loaded via
        `Bundle(path:)`.

    Both return the SAME extension-free `bundle_stem`; downstream code appends `.bundle` once.
    For the native family, `buildPath`'s physically resolved parent must equal `bin_path`
    (the discovered `--show-bin-path`, passed explicitly), so a cross-build pairing is refused.

    Raises AccessorInterpretationError for missing, ambiguous, dual-family, unknown, WASI and
    unsafe shapes.
    """
    if not isinstance(content, str):
        raise AccessorInterpretationError("accessor content is not text")

    swift_build_stem = _swift_build_stem(content)
    native = _native_literal_paths(content)

    if swift_build_stem is not None and native is not None:
        raise AccessorInterpretationError(
            "accessor matches both the Swift Build and native families"
        )
    if swift_build_stem is None and native is None:
        raise AccessorInterpretationError("unsupported compiled accessor shape")

    if swift_build_stem is not None:
        bundle_filename = _validated_bundle_filename(swift_build_stem + ".bundle", "bundleName")
        return {
            "family": "swift-build",
            "bundle_stem": bundle_filename[: -len(".bundle")],
            "bundle_filename": bundle_filename,
            "relative_bundle_path": f"Contents/Resources/{bundle_filename}",
        }

    main_filename, build_path_literal = native
    bundle_filename = _validated_bundle_filename(main_filename, "native mainPath component")
    if not build_path_literal.startswith("/"):
        raise AccessorInterpretationError("native buildPath is not an absolute literal")
    build_filename = pathlib.PurePosixPath(build_path_literal).name
    if build_filename != bundle_filename:
        raise AccessorInterpretationError(
            "native buildPath basename does not match the mainPath component"
        )
    if pathlib.Path(build_path_literal).parent.resolve() != bin_path:
        raise AccessorInterpretationError(
            "native buildPath parent does not equal the discovered bin-path"
        )

    return {
        "family": "native",
        "bundle_stem": bundle_filename[: -len(".bundle")],
        "bundle_filename": bundle_filename,
        "relative_bundle_path": f"Contents/Resources/{bundle_filename}",
    }


def validate_scratch_root(scratch_root: pathlib.Path, repo_root: pathlib.Path) -> None:
    resolved = scratch_root.resolve()
    resolved_repo = repo_root.resolve()
    home = pathlib.Path.home().resolve()

    # 1. Broad system or user roots (equality rejection)
    broad_roots = {
        pathlib.Path("/").resolve(),
        home,
        pathlib.Path("/private").resolve(),
        pathlib.Path("/var").resolve(),
        pathlib.Path("/tmp").resolve(),
        pathlib.Path("/private/var").resolve(),
        pathlib.Path("/private/tmp").resolve(),
    }
    if resolved in broad_roots:
        sys.stderr.write(f"build-dev-app: error: broad system or user root chosen for scratch root: {resolved}\n")
        sys.exit(1)

    # 2. Protected subtrees: reject if equal to OR descendant of these roots
    protected_subtrees = [
        pathlib.Path("/Applications"),
        pathlib.Path("/System"),
        pathlib.Path("/Library"),
        pathlib.Path("/usr"),
        pathlib.Path("/bin"),
        pathlib.Path("/sbin"),
        pathlib.Path("/etc"),
        pathlib.Path("/opt"),
        pathlib.Path("/dev"),
        pathlib.Path("/cores"),
        home / "Library",
        home / "Applications",
        home / ".Trash",
        resolved_repo,
    ]

    for p in protected_subtrees:
        if is_contained_in(resolved, p.resolve()):
            sys.stderr.write(f"build-dev-app: error: protected system, application, or repository path chosen for scratch root: {resolved}\n")
            sys.exit(1)

    # Reject if scratch_root is an ancestor of repository root
    if is_contained_in(resolved_repo, resolved):
        sys.stderr.write(f"build-dev-app: error: repository ancestor path chosen for scratch root: {resolved}\n")
        sys.exit(1)

def main():
    repo_root = pathlib.Path(__file__).resolve().parent.parent

    parser = argparse.ArgumentParser(
        description="Build and package local development macOS .app for AgentLensApp without signing/notarization."
    )
    parser.add_argument(
        "--scratch-root",
        required=True,
        type=pathlib.Path,
        help="Explicit scratch directory where swiftpm build products and the output .app will be placed."
    )
    parser.add_argument(
        "--configuration",
        default="debug",
        choices=["debug", "release"],
        help="Build configuration (debug or release). Default is 'debug'."
    )

    args = parser.parse_args()
    scratch_root = args.scratch_root.resolve()
    config = args.configuration

    validate_scratch_root(scratch_root, repo_root)
    scratch_root.mkdir(parents=True, exist_ok=True)

    spm_scratch = scratch_root / "swiftpm"
    spm_scratch.mkdir(parents=True, exist_ok=True)

    # Clean child environment: unset bundle path overrides
    child_env = dict(os.environ)
    child_env.pop("PACKAGE_RESOURCE_BUNDLE_PATH", None)
    child_env.pop("PACKAGE_RESOURCE_BUNDLE_URL", None)

    # 1. Build the product AgentLensApp using swift build
    build_cmd = [
        "swift", "build",
        "--product", "AgentLensApp",
        "--configuration", config,
        "--scratch-path", str(spm_scratch)
    ]
    sys.stderr.write(f"build-dev-app: building AgentLensApp with SwiftPM ({config})...\n")
    build_proc = subprocess.run(build_cmd, cwd=repo_root, env=child_env, stdout=sys.stderr, stderr=sys.stderr)
    if build_proc.returncode != 0:
        sys.stderr.write(f"build-dev-app: error: swift build exited with {build_proc.returncode}\n")
        sys.exit(build_proc.returncode)

    # 2. Discover bin-path
    bin_path_cmd = [
        "swift", "build",
        "--product", "AgentLensApp",
        "--configuration", config,
        "--scratch-path", str(spm_scratch),
        "--show-bin-path"
    ]
    bin_proc = subprocess.run(bin_path_cmd, cwd=repo_root, env=child_env, capture_output=True, text=True)
    if bin_proc.returncode != 0:
        sys.stderr.write(f"build-dev-app: error: swift build --show-bin-path failed ({bin_proc.returncode}): {bin_proc.stderr}\n")
        sys.exit(bin_proc.returncode)

    bin_path = pathlib.Path(bin_proc.stdout.strip()).resolve()
    if not bin_path.is_dir():
        sys.stderr.write(f"build-dev-app: error: discovered bin-path does not exist: {bin_path}\n")
        sys.exit(1)

    # 3. Find generated compiled resource bundle accessor under this build root
    # Restrict discovery to AgentLensCore target in CURRENT configuration within this exact build root.
    accessor_candidates = []
    for p in spm_scratch.rglob("resource_bundle_accessor.swift"):
        parts_lower = [part.lower() for part in p.parts]
        has_target = any("agentlenscore" in part for part in parts_lower)
        has_config = any(config.lower() == part for part in parts_lower)
        if has_target and has_config:
            accessor_candidates.append(p)

    resolved_candidates = list({p.resolve(): p for p in accessor_candidates}.values())

    if not resolved_candidates:
        sys.stderr.write(
            f"build-dev-app: error: no compiled resource_bundle_accessor.swift found for target AgentLensCore ({config}) under {spm_scratch}\n"
        )
        sys.exit(1)
    if len(resolved_candidates) > 1:
        sys.stderr.write(
            f"build-dev-app: error: ambiguous compiled resource_bundle_accessor.swift found for target AgentLensCore ({config}) under {spm_scratch}\n"
        )
        sys.exit(1)

    accessor_file = resolved_candidates[0]
    try:
        content = accessor_file.read_text(encoding="utf-8")
    except Exception as e:
        sys.stderr.write(f"build-dev-app: error: failed to read compiled accessor {accessor_file}: {e}\n")
        sys.exit(1)

    try:
        interpretation = interpret_resource_accessor(content, bin_path)
    except AccessorInterpretationError as e:
        sys.stderr.write(f"build-dev-app: error: {e} (compiled accessor under {spm_scratch})\n")
        sys.exit(1)

    # Both generated formats normalize to ONE extension-free stem; `.bundle` is appended once.
    bundle_name = interpretation["bundle_stem"]
    bundle_filename = interpretation["bundle_filename"]
    built_bundle_path = bin_path / bundle_filename
    if not built_bundle_path.is_dir():
        sys.stderr.write(f"build-dev-app: error: compiled resource bundle {built_bundle_path} not found\n")
        sys.exit(1)

    relative_bundle_path = f"Contents/Resources/{bundle_filename}"

    # 4. Assemble the .app bundle
    app_dir = scratch_root / f"AgentLensApp-{config}.app"
    if app_dir.exists():
        if app_dir.is_dir():
            shutil.rmtree(app_dir)
        else:
            app_dir.unlink()

    contents_dir = app_dir / "Contents"
    macos_dir = contents_dir / "MacOS"
    resources_dir = contents_dir / "Resources"
    macos_dir.mkdir(parents=True, exist_ok=True)
    resources_dir.mkdir(parents=True, exist_ok=True)

    executable_src = bin_path / "AgentLensApp"
    if not executable_src.is_file():
        sys.stderr.write(f"build-dev-app: error: executable {executable_src} not found\n")
        sys.exit(1)
    executable_dst = macos_dir / "AgentLensApp"
    shutil.copy2(executable_src, executable_dst)
    executable_dst.chmod(0o755)

    dest_bundle_path = resources_dir / bundle_filename
    shutil.copytree(built_bundle_path, dest_bundle_path, symlinks=False)

    for extra_bundle in bin_path.glob("*.bundle"):
        extra_dest = resources_dir / extra_bundle.name
        if not extra_dest.exists():
            shutil.copytree(extra_bundle, extra_dest, symlinks=False)

    # 5. Generate Info.plist from checked-in template
    template_plist = repo_root / "Resources" / "AgentLensApp" / "Info.plist"
    if not template_plist.is_file():
        sys.stderr.write(f"build-dev-app: error: Info.plist template not found at {template_plist}\n")
        sys.exit(1)

    try:
        with open(template_plist, "rb") as fp:
            plist_data = plistlib.load(fp)
    except Exception as e:
        sys.stderr.write(f"build-dev-app: error: failed to read template Info.plist: {e}\n")
        sys.exit(1)

    plist_data["CFBundleExecutable"] = "AgentLensApp"
    plist_data["CFBundleIdentifier"] = "com.agentlens.AgentLensApp"
    plist_data["CFBundleName"] = "Agent Lens"
    plist_data["CFBundlePackageType"] = "APPL"
    plist_data["CFBundleShortVersionString"] = "0.1.0"
    plist_data["CFBundleVersion"] = "1"
    plist_data["LSMinimumSystemVersion"] = "14.0"
    plist_data["AgentLensCoreResourceBundlePath"] = relative_bundle_path
    plist_data["AgentLensCoreResourceBundleName"] = bundle_name

    dest_plist = contents_dir / "Info.plist"
    try:
        with open(dest_plist, "wb") as fp:
            plistlib.dump(plist_data, fp, fmt=plistlib.FMT_XML)
    except Exception as e:
        sys.stderr.write(f"build-dev-app: error: failed to write Info.plist: {e}\n")
        sys.exit(1)

    # 6. Validate structure, executable, and resources
    if not executable_dst.is_file() or not os.access(executable_dst, os.X_OK):
        sys.stderr.write("build-dev-app: error: destination executable is missing or not executable\n")
        sys.exit(1)
    if not dest_plist.is_file():
        sys.stderr.write("build-dev-app: error: destination Info.plist is missing\n")
        sys.exit(1)
    if not dest_bundle_path.is_dir():
        sys.stderr.write("build-dev-app: error: destination resource bundle is missing\n")
        sys.exit(1)

    # 7. Run pure --bundle-preflight verification
    preflight_cmd = [str(executable_dst), "--bundle-preflight"]
    preflight_proc = subprocess.run(
        preflight_cmd,
        cwd=scratch_root,
        env=child_env,
        capture_output=True,
        text=True,
        timeout=30
    )
    if preflight_proc.returncode != 0:
        sys.stderr.write(f"build-dev-app: error: bundle-preflight failed ({preflight_proc.returncode}): {preflight_proc.stderr}\n")
        sys.exit(preflight_proc.returncode)

    preflight_output = preflight_proc.stdout.strip()
    if not re.match(r"^bundle-preflight: ok registry_count=\d+ registry_ids=.+$", preflight_output):
        sys.stderr.write(f"build-dev-app: error: unexpected preflight output: {preflight_output}\n")
        sys.exit(1)

    print(str(app_dir.resolve()))
    sys.exit(0)

if __name__ == "__main__":
    main()
