#!/usr/bin/env python3
"""Core/UI import-boundary guard (D-002).

`AgentLensCore` is the UI-free engine. This guard fails if any Swift source file below the
inspected root imports SwiftUI or AppKit, in any legal spelling:

    import AppKit
    import SwiftUI
    @preconcurrency import AppKit
    @available(macOS, deprecated: 26.0) import AppKit
    import struct AppKit.NSRect
    import class AppKit.NSView
    import func AppKit.NSApplicationMain
    import typealias AppKit.NSInteger
    import enum AppKit.NSWindowStyleMask
    import protocol AppKit.NSApplicationDelegate
    import var AppKit.NSApp
    import let AppKit.NSBeep
    import _Concurrency          # unrelated
    #if canImport(AppKit)
    import AppKit
    #endif

Text that merely contains the words — line comments, nested block comments, string
literals, multiline string literals, raw strings — is NOT an import and must pass. The
scanner therefore strips comments and string literals before matching and preserves line
structure so reported line numbers match the file.

No compiler plugin and no third-party parser: the scanner is a small lexer that only needs to
know enough Swift to not be fooled by comments/strings.

Usage:
    check-core-ui-imports.py                  # inspect Sources/AgentLensCore from repo root
    check-core-ui-imports.py --source-root P  # inspect an explicit root (fixtures)

Exit status: 0 clean, 1 violations found, 2 usage/IO failure (missing or unreadable root).
"""

import argparse
import os
import pathlib
import re
import sys

FORBIDDEN_MODULES = ("SwiftUI", "AppKit")

# Optional `import` decorations, then the module name, optionally followed by a scoped
# declaration such as `.NSRect`. The module token is matched as a whole identifier so
# `AppKitShim` is a different module and stays legal.
IMPORT_RE = re.compile(
    # Statement boundary, then any run of attributes (`@preconcurrency`,
    # `@available(macOS, deprecated: 26.0)`) which may span lines. `import` is not anchored to a
    # line start: Swift allows several statements on one line (`import Foundation; import AppKit`)
    # and a trailing `;`. The boundary set prevents matching `reimport`/`.import`.
    r"(?:^|(?<=[;{}]))[^;{}]*?"
    r"\bimport\s+"
    r"(?:(?:typealias|struct|class|enum|protocol|var|let|func)\s+)?"
    # A module identifier may be escaped with backticks: ``import `AppKit` ``.
    r"(?P<module>`?[A-Za-z_][A-Za-z0-9_]*`?)"
    r"(?:\s*\.\s*`?[A-Za-z_][A-Za-z0-9_]*`?)?",
    re.MULTILINE,
)

DEFAULT_SOURCE_ROOT = pathlib.Path("Sources") / "AgentLensCore"


class NotSwift:
    """Placeholder: the scanner rewrites non-code characters to spaces in place."""


def strip_noncode(text):
    """Return `text` with comments and string literals blanked, preserving newlines/offsets.

    A small state machine is enough: Swift has line comments, nestable block comments, and
    four string forms (single-line, multiline, raw single-line, raw multiline). Replacing
    literals with spaces keeps every offset stable so error line numbers are exact.
    """
    out = list(text)
    i = 0
    n = len(text)

    def blank(start, stop):
        for k in range(start, stop):
            if out[k] != "\n":
                out[k] = " "

    while i < n:
        char = text[i]
        nxt = text[i + 1] if i + 1 < n else ""

        if char == "/" and nxt == "/":
            end = text.find("\n", i)
            end = n if end < 0 else end
            blank(i, end)
            i = end
            continue

        if char == "/" and nxt == "*":
            depth = 1
            j = i + 2
            while j < n and depth:
                if text.startswith("/*", j):
                    depth += 1
                    j += 2
                elif text.startswith("*/", j):
                    depth -= 1
                    j += 2
                else:
                    j += 1
            blank(i, j)
            i = j
            continue

        # Raw string: one or more '#' then a quote.
        if char == "#":
            j = i
            while j < n and text[j] == "#":
                j += 1
            hashes = j - i
            if j < n and text[j] == '"':
                multiline = text.startswith('"""', j)
                quote = '"""' if multiline else '"'
                terminator = quote + "#" * hashes
                end = text.find(terminator, j + len(quote))
                end = n if end < 0 else end + len(terminator)
                blank(i, end)
                i = end
                continue
            i = j if j > i else i + 1
            continue

        if char == '"':
            multiline = text.startswith('"""', i)
            quote = '"""' if multiline else '"'
            j = i + len(quote)
            while j < n:
                if text[j] == "\\":
                    j += 2
                    continue
                if text.startswith(quote, j):
                    j += len(quote)
                    break
                # An unterminated single-line string ends at the newline, like the compiler.
                if not multiline and text[j] == "\n":
                    break
                j += 1
            blank(i, j)
            i = j
            continue

        i += 1

    return "".join(out)


def scan_text(text):
    """Yield `(line_number, module, line_text)` for each forbidden import in `text`."""
    cleaned = strip_noncode(text)
    original_lines = text.splitlines()
    for match in IMPORT_RE.finditer(cleaned):
        module = match.group("module").strip("`")
        if module not in FORBIDDEN_MODULES:
            continue
        line_number = cleaned.count("\n", 0, match.start("module")) + 1
        line_text = original_lines[line_number - 1].strip() if line_number <= len(original_lines) else ""
        yield line_number, module, line_text


def collect_swift_files(source_root):
    """Return every `*.swift` path below `source_root`, failing closed on anything unscannable.

    Two silent-skip hazards are refused rather than tolerated, because each would let a forbidden
    import sit in a subtree the guard never inspected while still reporting "clean":

    * `pathlib.Path.rglob` suppresses directory-listing errors, so an unreadable root or nested
      directory produced a partial list and exit 0. This walk uses `os.scandir`, which raises.
    * A symlink is neither followed nor ignored. Following it could escape the inspected tree or
      recurse forever through a loop; ignoring it silently excludes whatever it points at. Both a
      symlinked directory (including loop and dangling links) and a symlinked `*.swift` file are
      named errors. Scanning symlinked source is deliberately not supported: copy the real tree.

    Returns a sorted list of real `*.swift` paths.
    """
    stack = [source_root]
    files = []
    while stack:
        directory = stack.pop()
        # Raises PermissionError/NotADirectoryError/OSError; never swallowed.
        with os.scandir(directory) as entries:
            for entry in entries:
                try:
                    is_symlink = entry.is_symlink()
                    is_directory = entry.is_dir(follow_symlinks=False)
                except OSError as error:
                    raise OSError(f"cannot inspect {entry.path}: {error}") from error
                if is_symlink:
                    # The rejection never depends on what the link resolves to; only the label does.
                    # A loop (ELOOP) or a dangling target simply stays labelled "file", so the
                    # error is still raised by name rather than becoming a resolution failure.
                    try:
                        kind = "dir" if entry.is_dir() else "file"
                    except OSError:
                        kind = "file"
                    raise OSError(
                        f"symlinked source {kind} is not supported: {entry.path} "
                        "(copy the real tree instead of linking)"
                    )
                if is_directory:
                    stack.append(pathlib.Path(entry.path))
                elif entry.name.endswith(".swift"):
                    files.append(pathlib.Path(entry.path))
    return sorted(files)


def scan_root(source_root):
    """Return a list of human-readable violation strings for `source_root`."""
    if not source_root.is_dir():
        raise FileNotFoundError(f"source root is not a directory: {source_root}")

    files = collect_swift_files(source_root)
    violations = []
    unreadable = []
    for path in files:
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as error:
            unreadable.append(f"{path}: {error}")
            continue
        for line_number, module, line_text in scan_text(text):
            violations.append(f"{path}:{line_number}: forbidden {module} import in AgentLensCore: {line_text}")

    if unreadable:
        raise OSError("; ".join(unreadable))
    return violations, len(files)


def main(argv):
    parser = argparse.ArgumentParser(description="Fail if AgentLensCore imports SwiftUI or AppKit.")
    parser.add_argument(
        "--source-root",
        default=None,
        metavar="PATH",
        help=f"Swift source root to inspect (default: {DEFAULT_SOURCE_ROOT} from the repo root)",
    )
    arguments = parser.parse_args(argv)

    source_root = pathlib.Path(arguments.source_root) if arguments.source_root else DEFAULT_SOURCE_ROOT
    try:
        violations, file_count = scan_root(source_root)
    except (FileNotFoundError, OSError) as error:
        print(f"core-ui-import-guard: {error}", file=sys.stderr)
        return 2

    if violations:
        for violation in violations:
            print(violation)
        print(
            f"core-ui-import-guard: {len(violations)} forbidden import(s) in {source_root} "
            f"(D-002: AgentLensCore must stay UI-free)",
            file=sys.stderr,
        )
        return 1

    print(f"core-ui-import-guard: {file_count} Swift file(s) under {source_root}; no SwiftUI/AppKit imports")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))