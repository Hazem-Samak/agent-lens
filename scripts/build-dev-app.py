#!/usr/bin/env python3
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

    match = re.search(r'let\s+bundleName\s*=\s*"([^"]+)"', content)
    if not match:
        sys.stderr.write(f"build-dev-app: error: failed to extract bundleName from compiled accessor under {spm_scratch}\n")
        sys.exit(1)
    bundle_name = match.group(1)

    # Verify supported known accessor shape
    if "Bundle.main.resourceURL" not in content:
        sys.stderr.write("build-dev-app: error: compiled accessor does not include supported Bundle.main.resourceURL candidate\n")
        sys.exit(1)
    if 'bundleName + ".bundle"' not in content and f'"{bundle_name}.bundle"' not in content:
        sys.stderr.write("build-dev-app: error: compiled accessor does not use supported bundle suffix lookup\n")
        sys.exit(1)
    if "Bundle.init(url:)" not in content and "Bundle(url:)" not in content:
        sys.stderr.write("build-dev-app: error: compiled accessor does not initialize Bundle from candidate url\n")
        sys.exit(1)

    bundle_filename = f"{bundle_name}.bundle"
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
