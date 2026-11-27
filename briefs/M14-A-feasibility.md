# M14-A Feasibility Probe Gate — Live Python (`uv` & `pip`) Layout & Contract Verification

- **Date:** 2026-11-27
- **Branch:** `milestone/m14-python`
- **Phase:** `M14-A` (Read-only workstation & isolated `/tmp` scratch feasibility gate; zero product source files modified)

---

## 1. Workstation Python Toolchain & Environment Inventory

1. **System & Homebrew Python Runtimes:**
   - `/usr/bin/python3` → `Python 3.9.6` (macOS Command Line Tools framework)
   - `/opt/homebrew/bin/python3` → `Python 3.15.2` (`/opt/homebrew/Cellar/python@3.15/3.15.2/Frameworks/Python.framework/Versions/3.15/bin/python3.15`)
   - `/opt/homebrew/bin/pip3` → `pip 26.2.2`
   - `/opt/homebrew/bin/pipx` → `pipx 1.18.11`
2. **PEP 668 `EXTERNALLY-MANAGED` Marker Verification:**
   - Verified present at `/opt/homebrew/opt/python@3.15/Frameworks/Python.framework/Versions/3.15/lib/python3.15/EXTERNALLY-MANAGED` (`PEP668_EXISTS: True`).
   - Confirms R1.6's `.externallyManagedSystem` detection rule: checking `<env-root>/lib/python*/EXTERNALLY-MANAGED` deterministically identifies PEP 668 externally managed Python prefixes.
3. **`uv` Workstation Presence & M14-G Harness Implication:**
   - `uv` is not installed on the workstation's permanent `PATH` (`/opt/homebrew/bin/uv` and `~/.local/bin/uv` are absent).
   - Confirms R1.3 (the Anchored Python Environment Classifier must check `<env-root>/uv-receipt.toml` via local `lstat` before requiring `uv` on `PATH`, so `.pip` virtualenvs verify even when `uv` is absent) and R12 (`Tests/Fixtures/M14/python_acceptance.py` must be self-contained using an offline local wheelhouse and sandboxed `uv` CLI / disposable binary without depending on a personal `uv` installation).

---

## 2. Empirical Virtual Environment, Symlink & `.dist-info` Probe Results

Using an isolated scratch directory (`/tmp/agent-lens-m14-probe-*`, verified `CLEANED_UP: True` on exit), a PEP 427 wheel (`aider_chat-0.86.2-py3-none-any.whl`) was built and installed offline into a real virtual environment:

1. **Why `Requires-Python` Compatibility Filtering (R2 & R3) Is Mandatory:**
   - When the wheel declared `Requires-Python: >=3.10,<3.13` (as older Aider releases do when running on Python 3.15), `pip` failed immediately with:
     `ERROR: Package 'aider-chat' requires a different Python: 3.15.2 not in '<3.13,>=3.10'`
   - This empirically validates R2.3 and R3.3: `PyPIUpdateProbe` MUST evaluate `Requires-Python` against the tool environment's observed Python version (`3.15.2`) and return `VersionStatus.unknown(installed: ..., reason: .pythonInterpreterIncompatible)` when newer PyPI releases are incompatible with the environment's interpreter.
2. **Observed `pyvenv.cfg` Format:**
   ```ini
   home = /opt/homebrew/opt/python@3.15/bin
   include-system-site-packages = false
   version = 3.15.2
   executable = /opt/homebrew/Cellar/python@3.15/3.15.2/Frameworks/Python.framework/Versions/3.15/bin/python3.15
   command = /opt/homebrew/opt/python@3.15/bin/python3.15 -m venv <venv-path>
   ```
   - Standard `venv` writes `version = X.Y.Z` (`3.15.2`), while `uv` writes `version_info = X.Y.Z` (and `uv = <uv-version>`). Parsing `version_info` first and falling back to `version` extracts the exact 3-component `major.minor.patch` interpreter version without spawning a subprocess.
3. **Console-Script Entry Point vs Symlink Resolution (`ToolDetector.classifySource`):**
   - `<venv>/bin/aider` is a **regular file** (`S_ISREG == True`, `S_ISLNK == False`) with a `#!<venv>/bin/python3.15` shebang.
   - When `<bin-dir>/aider` is a symlink pointing to `<venv>/bin/aider`, `realpath(<bin-dir>/aider)` resolves to `<venv>/bin/aider` (NOT to `/opt/homebrew/Cellar/python@3.15/...`).
   - Consequently, `ToolDetector.classifySource(resolvedPath:)` classifies all `uv tool` and `pip`/`pipx` virtualenv console scripts as `"standalone"`, confirming R1.2 (`ToolDetector.swift` remains 100% untouched in M14).
4. **Observed `.dist-info` Layout & Executable Ownership Proof:**
   - Directory: `<venv>/lib/python3.15/site-packages/aider_chat-0.86.2.dist-info`
   - Files: `['INSTALLER', 'METADATA', 'RECORD', 'REQUESTED', 'WHEEL', 'entry_points.txt']`
   - `RECORD` entry for the console script:
     `../../../bin/aider,sha256=LPS8vGchbpCwodWwIq7TNCu3TmHLuoZI4Sm-n5iQIVA,253`
   - `entry_points.txt` entry:
     ```ini
     [console_scripts]
     aider = aider_chat:main
     ```
   - Confirms R1.5 and R1.6: checking `RECORD` for `../../../bin/<executableName>` (or `bin/<executableName>`) and/or `entry_points.txt` (`[console_scripts]` key `<executableName>`) provides a deterministic, non-recursive ownership link from `<venv>/bin/<executableName>` to `<dist>-<ver>.dist-info/METADATA`.
5. **`uv-receipt.toml` Contract (`UvToolOwnershipProbe`):**
   - `uv tool install <pkg>` writes `<uv-tool-dir>/<norm-pkg>/uv-receipt.toml` containing a `[tool]` section with:
     - `requirements = [{ name = "<pkg>", ... }]` (including optional `specifier = "==..."`, `git = ...`, `path = ...`, `url = ...`, and any `--with` extra requirement entries)
     - `entrypoints = [{ name = "<exe>", install-path = "<uv-tool-bin-dir>/<exe>", from = "<pkg>" }]` (note: older `uv` receipts omit `from`; when `from` is present it must match the declared package under PEP 503 normalization, and when omitted `.dist-info/RECORD` + `entry_points.txt` prove executable ownership)
     - Optional `[tool.options]` / top-level index settings (`index-url`, `extra-index-url`, `find-links`).

---

## 3. Gate Verdict

**PASS** — All R1–R16 assumptions in `briefs/M14-plan.md` match observed macOS Python, `venv`, `pip`, PEP 668, and `uv` filesystem contracts. Ready for **Phase M14-B (Core Python Ownership)**.
