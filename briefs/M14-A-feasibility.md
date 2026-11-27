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

---

## 4. 2026-11-27 Supplement — Real `uv` lifecycle, explicit roots and pip/pipx layouts

**Status:** Worker evidence supplement, appended after the committed report. The §3 worker verdict above is superseded for M14-A gating by this supplement. This is **not** an orchestrator PASS and authorizes no M14-B dispatch: D-014 requires the orchestrator to independently observe acceptance. No product source file was modified. **Post-review correction:** §5 supersedes the over-broad historical/generic statements in this report; §4 remains the observed evidence.

### 4.1 Reproducible setup, provenance and isolation

- **Scratch:** `/private/tmp/agent-lens-m14a.fbGo6h` (mode `0700`). All target environments, homes, caches, local indexes and receipts live here. Personal `.cache` scratch used during drafting was moved here and removed.
- **Script:** `probe_m14a.py`, SHA-256 `aa4313babcbf717bf24d91e8d201fc13db38bc1255358e6f37f5c8d34345a168`. Rerun from the scratch root with `/opt/homebrew/bin/python3.15 probe_m14a.py`. Each run creates a fresh `runs/<UTC timestamp>/`; `--skip-public-network` leaves public-PyPI observations unknown instead of skipped silently.
- **Reproducibility:** two consecutive runs of this exact script hash produced the same result: `runs/20261127T143914Z` and `runs/20261127T143957Z`, each **94 checks passed, 0 failed, 3 warnings, 86 commands**, `targets_cleaned: true`. Canonical evidence run: `runs/20261127T143957Z`.
- **Workstation:** macOS `darwin 27.2.0`, arm64; `/opt/homebrew/bin/python3.15` = Python 3.15.2; `python3.15 -m pip` = pip 26.2.2; `/usr/bin/python3` = Python 3.9.6 (pip 21.2.4); `/opt/homebrew/bin/pip3` = pip 26.2.2; pipx 1.18.11.
- **uv provenance (pinned, official artifact):**

| Item | Value |
| --- | --- |
| Pin | `uv 0.13.10 (e3e7c1eac 2026-11-24 aarch64-apple-darwin)` |
| Artifact | `https://github.com/astral-sh/uv/releases/download/0.13.10/uv-aarch64-apple-darwin.tar.gz` |
| Official checksum | `https://github.com/astral-sh/uv/releases/download/0.13.10/uv-aarch64-apple-darwin.tar.gz.sha256` |
| Official/observed tarball SHA-256 | `e419bf07533bdbf48795fc793601c834dd79db57a8c49ce8e25cfe3a8639958d` |
| Extracted binary SHA-256 | `4ff271e49765b1d8ed72cfbf720401941efccac6b2997ce87bb05ee790312ab3` |
| Tarball size | `14,700,626` bytes |

- **Isolation scope (not a blanket no-write proof):** all commands used scratch `HOME`, `XDG_*`, `TMPDIR`, `UV_CACHE_DIR`, `UV_PYTHON_INSTALL_DIR`, `PIP_CACHE_DIR`, `PIPX_HOME`/`PIPX_BIN_DIR` and scratch `UV_TOOL_DIR`/`UV_TOOL_BIN_DIR`. The before/after check snapshotted only the **existing** paths among `~/.local/bin`, `~/.local/share/uv`, `~/.cache/uv`, `~/.config/uv`, `~/Library/Python`, `~/.local/pipx`, `~/.cache/pip`; each manifest was capped at 3000 entries. The five existing roots (`~/.cache/uv`, `~/.config/uv`, `~/.local/bin`, `~/.local/share/uv`, `~/Library/Python`) had empty diffs; `~/.local/pipx` and `~/.cache/pip` were absent in both snapshots (a creation would have surfaced as `created_during_probe`). Homebrew was checked only by `lstat` of the `python@3.15` runtime path, not by scanning all of `/opt/homebrew`, and no write test was done. This does not prove absence of writes elsewhere and makes no general claim about receipt configuration. Disposable targets/caches were deleted after receipts were copied; the canonical receipt tree is unchanged by cleanup (636 files, 199,293 bytes, tree SHA-256 `b76b6e95cbfddf3353e2a9785cd616f9adb90b2ffea63d3b126e1e89b58d325c`). See §5.2.
- **Evidence layout:** every argv, sanitized environment, stdout, stderr and exit status is in `logs/cmd/*.json` and `logs/commands.log`; raw receipts are in `logs/files/`; structured summaries in `logs/inspect/`; SHA-256/size manifest of evidence in `logs/evidence-files.json`; built-wheel hashes in `logs/wheels.json`. `README.md` and `BLOCKERS.md` in the scratch root index the bundle.

### 4.2 Root queries and real `uv` lifecycle (R1.5, R5, R7)

`uv tool dir` and `uv tool dir --bin` were queried with no config, with each environment variable set alone, and with both set. Outputs were exact absolute paths, no multi-line or relative output:

| Environment | `uv tool dir` | `uv tool dir --bin` |
| --- | --- | --- |
| default (`XDG_DATA_HOME`, `XDG_BIN_HOME`) | `<RUN>/xdg-data/uv/tools` | `<RUN>/xdg-bin` |
| `UV_TOOL_DIR` only | `<RUN>/x-tools` | `<RUN>/xdg-bin` |
| `UV_TOOL_BIN_DIR` only | `<RUN>/xdg-data/uv/tools` | `<RUN>/x-bin` |
| both explicit | `<RUN>/x-tools` | `<RUN>/x-bin` |

Exact roots for the lifecycle were `<RUN>/targets/uv-tools-lifecycle` and `<RUN>/targets/uv-bin-lifecycle`; all commands exited 0 unless noted. `<RUN>` is the canonical run; full argv/environment are in `logs/cmd/`.

- **Install:** `uv tool install --no-config --no-progress --allow-insecure-host 127.0.0.1 --python /opt/homebrew/bin/python3.15 --default-index <local-index> aider-chat` → exit 0, installed 0.85.0 and shim `aider`; the sibling `uv tool install ... hermes-agent` → exit 0, installed 1.0.0 and shim `hermes`.
- **Unpinned upgrade:** `uv tool upgrade --no-config --no-progress --python /opt/homebrew/bin/python3.15 aider-chat` (no `--default-index`) → exit 0, output `Updated aider-chat v0.85.0 -> v0.86.2`; uv read the receipt's `[tool.options].index`. No `--no-cache` was required in this run.
- **Uninstall (exact R7 vector):** `uv tool uninstall --no-progress aider-chat`, with `UV_TOOL_DIR`, `UV_TOOL_BIN_DIR`, `UV_OFFLINE=1`, `UV_NO_CONFIG=1` → exit 0, `Uninstalled 1 executable: aider`; tool environment directory and shim both absent afterward.
- **Sibling unchanged:** before/after manifest of the existing `hermes-agent` environment entries (receipt, pyvenv, dist-info, script, interpreter) and of its shim had empty `added`/`removed`/`changed` lists after both the aider upgrade and the aider uninstall; the environment was small enough not to hit the 4000-entry manifest cap. `uv tool list` before/after: both tools present after upgrade; only `hermes-agent` after uninstall.

Lifecycle receipt after upgrade (`logs/files/lifecycle-aider-after-receipt/uv-receipt.toml`):

```toml
[tool]
requirements = [{ name = "aider-chat" }]
python = "/opt/homebrew/bin/python3.15"
entrypoints = [
    { name = "aider", install-path = "<RUN>/targets/uv-bin-lifecycle/aider", from = "aider-chat" },
]

[tool.options]
index = [{ url = "<local-index>", explicit = false, default = true, format = "simple", authenticate = "auto" }]
```

- `pyvenv.cfg` after upgrade: `version_info = 3.15.2`, `home = /opt/homebrew/opt/python@3.15/bin`, `uv = 0.13.10`.
- `aider` script is a regular file with `#!/<RUN>/targets/uv-tools-lifecycle/aider-chat/bin/python`; `RECORD` row `../../../bin/aider,sha256=…,386` matched the script's actual hash and size; `INSTALLER` was `uv`; `entry_points.txt` was `[console_scripts] aider = aider_chat.cli:main`.
- The managed shim `<RUN>/targets/uv-bin-lifecycle/aider` was a symlink resolving exactly to the venv script; the sibling `hermes` shim's inode/mtime/hash were unchanged.
- Upgrade without an explicit index did not add a duplicate `[tool.options].index` entry (1 → 1). This is the clean case; §4.3 records the explicit-index and ambient-environment mutations.

### 4.3 Receipt variants, source evidence, and what uv cannot prove (R3, R5, R6, OD-M14-3)

`aider-chat` and `hermes-agent` wheels were built locally and served from a loopback PEP 503 index; the version visible in the index was controlled per scenario. Raw receipts and list output are in `logs/files/` and `logs/inspect/`.

| Case | Observed receipt / behavior |
| --- | --- |
| Unpinned local index | `requirements = [{ name = "aider-chat" }]`; `[tool.options].index` recorded the local index; upgrade 0.85.0 → 0.86.2 |
| `--with m14-sentinel` | `requirements` had both `aider-chat` and `m14-sentinel`; after upgrade both remained; `uv tool list` showed `[with: m14-sentinel]`; sentinel import printed `1.0.0` |
| Exact pin `aider-chat==0.85.0` | `requirements = [{ name = "aider-chat", specifier = "==0.85.0" }]`; upgrade exit 0 with `Nothing to upgrade` plus hint `pinned to 0.85.0`; version stayed 0.85.0; list showed `[required: ==0.85.0]` |
| Direct wheel path | `requirements = [{ name = "aider-chat", path = ".../aider_chat-0.85.0-py3-none-any.whl" }]`; `direct_url.json` contained the same `file://` URL; upgrade exit 0 `Nothing to upgrade`, version stayed 0.85.0 |
| Direct HTTP wheel URL | `requirements = [{ name = "aider-chat", url = ".../aider_chat-0.85.0-py3-none-any.whl" }]`; `direct_url.json` contained the same HTTP URL; list showed `[required: <url>]` |
| Public PyPI, default index | No `[tool.options]` section at all; no `direct_url.json`; uninstall exit 0. This is **unknown provenance**, not affirmative PyPI proof. |
| Public PyPI, explicit `--default-index https://pypi.org/simple` | `[tool.options].index = [{ url = "https://pypi.org/simple", ... }]`; no `direct_url.json`. This is affirmative public-PyPI evidence. |
| Install via user `uv.toml` (`[[index]]`) | Receipt recorded the config index; a later `--no-config` upgrade used the receipt index and ignored a changed ambient config (0.85.0 → 0.86.2); the ambient upgrade also stayed 0.86.2 but appended the new config index to the receipt |
| No receipt index (public `pycowsay`) + ambient config | `--no-config` upgrade stayed 0.0.0.2; ambient-config upgrade changed resolution to local 1.0.0. Observed on uv 0.13.10: ambient config affected resolution only when the receipt had no index. This is an observation, not a general uv contract. |
| Hostile `UV_INDEX_URL` (dead) with receipt index | Resolution still used the receipt index (0.86.2 → 0.86.3), but the dead URL was persisted as top-level `index-url = "http://127.0.0.1:9/simple"` in the receipt |
| Explicit `--default-index` on upgrade | Appended a duplicate identical `[tool.options].index` entry (1 → 2); after a hostile-env upgrade the duplicate plus the dead top-level `index-url` persisted |
| Clean upgrade after hostile receipt | Still reached 0.86.5; the stale top-level `index-url` did not block this tested upgrade |

Key raw files: `logs/files/public-default-pycowsay-receipt/uv-receipt.toml` (no options), `logs/files/public-explicit-pycowsay-receipt/uv-receipt.toml` (PyPI index), `logs/files/custom-after-hostile-env-receipt/uv-receipt.toml` (live options plus dead top-level `index-url`), `logs/files/custom-after-explicit-receipt/uv-receipt.toml` (duplicate options plus dead top-level), `logs/files/inherited-after-ambient-receipt/uv-receipt.toml` (old plus new config index), `logs/inspect/config-effect.json`.

What uv 0.13.10 does **not** prove:

- Absence of `[tool.options].index` does not distinguish public PyPI from a mirror or unknown source. Only an affirmative recorded index (or `direct_url.json` for a direct source) is evidence; default public installs remain unknown provenance.
- The receipt is mutable by `uv tool upgrade`: duplicate index entries can appear, and ambient configuration/environment can be written into it even when it did not determine resolution.
- `[tool].python` is install-time evidence. After `uv tool upgrade --python /usr/bin/python3` rebuilt the environment to 3.9.6, `[tool].python` still named `/opt/homebrew/bin/python3.15`; `pyvenv.cfg` was the current truth.
- `uv tool list` reports installed version, constraints, `[with: ...]`, and paths, but not index provenance.

### 4.4 Interpreter retention, exact flags and env leakage (R5.2)

- Install with `--python /opt/homebrew/bin/python3.15` → `pyvenv.cfg` `version_info = 3.15.2`; receipt `python = /opt/homebrew/bin/python3.15`.
- Upgrade with no `--python` flag → retained `version_info = 3.15.2` and advanced to 1.1.0.
- Upgrade with `--python /usr/bin/python3` → rebuilt the environment to `version_info = 3.9.6` and advanced to 1.2.0. In this tested uv version, this demonstrates `--python` is an interpreter binding, not a preference; it is not a claim about all uv versions. The receipt `python` field did **not** update.
- `UV_PYTHON=/opt/homebrew/bin/python3.15` in the environment, with no `--python` flag, rebuilt the same environment back to `3.15.2`. Production must sanitize `UV_PYTHON`.
- `--python /nonexistent/python3.99 --no-python-downloads` exited 2 with `error: No interpreter found at path '/nonexistent/python3.99'`; no managed Python was downloaded.
- `uv tool upgrade --help` contains `--python`, `--no-config`, `--no-progress`, `--no-python-downloads`, `--default-index`, `--no-cache`, `--offline`, `--allow-insecure-host`; `uv tool install --help` contains `--with`; `uv tool uninstall --help` contains `--no-progress`. Captured under `logs/help/`.

The exact production argv remains a plan decision: the evidence supports binding the selected interpreter with `--python` and sanitizing ambient env; it also shows that passing `--default-index` on upgrade mutates the receipt (§4.3), so the index strategy must be chosen deliberately.

### 4.5 pip, pipx, prefix/user and Homebrew layouts (R1.6, R12)

| Layout | Evidence |
| --- | --- |
| pip venv, direct wheel | `<venv>/pyvenv.cfg` 3.15.2; `<venv>/bin/aider` regular file, shebang `<venv>/bin/python`; `INSTALLER=pip`; `RECORD` row `../../../bin/aider,sha256=…,237` matched hash and size; `direct_url.json` with `file://` wheel URL; no `EXTERNALLY-MANAGED` in the venv despite the Homebrew base having one |
| pip venv, index install | Same venv/script/interpreter relationship; `INSTALLER=pip`; `direct_url.json` absent; `RECORD` row `../../../bin/aider,sha256=…,236` matched; this is the "unknown index provenance" shape |
| pipx, wheel path | `PIPX_HOME/venvs/aider-chat`; shim `PIPX_BIN_DIR/aider` → venv `bin/aider`; `INSTALLER=pip`; `pipx_metadata.json` version `0.12`, `backend: pip`, `main_package.package: aider-chat`, `package_or_url: <wheel path>`, `apps: ["aider"]`, `pip_args: []`, `python_version: Python 3.15.2`, `source_interpreter` framework Python 3.15.2 |
| pipx, local index | `package_or_url: "aider-chat==0.85.0"`, `pip_args: ["--index-url", "<local>", "--trusted-host", "127.0.0.1"]`, same backend/metadata shape |
| pipx 1.18.11 RECORD | Raw final script does not match RECORD: path install 251 bytes vs 248, index install 257 vs 254, hashes differ. The only difference is a terminal ` -E` appended to the shebang. Removing exactly that terminal option reconstructs **both** the recorded size and SHA-256 in both cases (normalized 248/248 and 254/254, hash match true). This is a narrow exact-rewrite proof, not a blanket hash exception. |
| pipx with uv absent | `pipx list --json` exit 0 with `PATH` excluding uv; pipx does not require uv |
| Shared bin (uv + pipx) | One `shared-bin` contained `aider` → `<uv-tools>/aider-chat/bin/aider` and `hermes` → `<pipx-home>/venvs/hermes-agent/bin/hermes`; the uv env had a receipt, the pipx env had none; uninstalling the uv aider removed only its shim and left the pipx environment and hermes shim byte-identical |
| `pip --prefix` | `<prefix>/bin/aider` regular file; no `<prefix>/bin/python`; shebang `/opt/homebrew/opt/python@3.15/bin/python3.15` (outside prefix); site-packages `<prefix>/lib/python3.15/site-packages`; no `pyvenv.cfg`; `INSTALLER=pip`; RECORD hash/size matched |
| `pip --user` (scratch HOME) | User base `<HOME>/Library/Python/3.15`; site `<HOME>/Library/Python/3.15/lib/python/site-packages`; script `<HOME>/Library/Python/3.15/bin/aider`; no `<HOME>/Library/Python/3.15/bin/python`; no `pyvenv.cfg`; `INSTALLER=pip`; RECORD hash/size matched. `--break-system-packages` was used only to target scratch, not a recommendation. |
| Homebrew externally managed (read-only) | `/opt/homebrew/opt/python@3.15` → Cellar `3.15.2`; `EXTERNALLY-MANAGED` present at `lib/python3.15/EXTERNALLY-MANAGED` with the Homebrew text; `pip3` symlink to Cellar with shebang there; site-packages symlink into Cellar; `pip3 install --dry-run` exited 1 with `externally-managed-environment`. No write was attempted. |

For the tested pip/venv/prefix/user layouts, `RECORD` path `../../../bin/<exe>` resolved to the exact selected script and matched raw bytes. For pipx 1.18.11, only the exact terminal ` -E` normalization above matched; any other pipx rewrite or mismatch must remain unverified. These are version- and layout-scoped observations, not a generic RECORD rule.

### 4.6 Findings that constrain M14-B, and later policy findings

**Constrain M14-B (ownership/diagnostics):**

1. **pipx RECORD normalization:** R1.6 must either accept exactly the observed terminal ` -E` shebang rewrite only when normalized hash and size both match, or leave pipx unverified. A literal raw-hash rule fails on real pipx 1.18.11.
2. **Split layouts:** `pip --prefix` and `pip --user` have no interpreter under `<root>/bin`; the interpreter comes from the script shebang/base runtime while site-packages is under `<root>/lib`. `<root>/bin` alone is not an interpreter binding.
3. **Receipt `python` is stale after `--python` rebuild:** use `pyvenv.cfg` for the current interpreter; do not publish receipt `python` as current proof.
4. **Default public provenance is unknown:** only affirmative index/`direct_url` evidence can claim PyPI; absence is not proof. This supports R3's provenance rule.
5. **Shared bin is not ownership evidence:** uv and pipx shims can share a bin directory; the receipt/venv roots and exact shim target are the discriminator. The uv tool env had a receipt; the pipx env did not.
6. **pipx metadata is affirmative and rich:** `pipx_metadata.json` version 0.12 carries backend, main package, app paths, `package_or_url`, `pip_args`, Python version and source interpreter; `INSTALLER` is `pip`. Use it as pipx evidence, not directory-name inference.

**Constrain later provenance/mutation policy (C/D/H):**

1. **Receipt mutation on upgrade:** explicit `--default-index` duplicates `[tool.options].index`; ambient config/env can be persisted as extra index/top-level `index-url` even when resolution used the receipt index. Define canonicalization/refusal before relying on "receipt unchanged".
2. **Config precedence:** when a receipt index exists, `uv tool upgrade` used it and ignored a changed ambient config; when the receipt had no index, ambient config changed resolution and was then recorded. This is observed behavior, not a required effect failure.
3. **Environment leakage:** `UV_PYTHON` rebuilt the environment with no `--python` flag; `UV_INDEX_URL` was persisted into the receipt. Sanitize the subprocess environment as R5.1 requires.
4. **`--python` behavior:** exact path binds and can rebuild the environment; omission retains the current interpreter. Receipt `python` does not follow.
5. **Pin/direct non-success is exit 0:** `uv tool upgrade` exited 0 with `Nothing to upgrade` for an exact pin and a direct source. R6's requirement that success be a strictly newer supported version is necessary; exit status alone is not success.
6. **`Requires-Python` in uv:** with 0.85.0 installed and 0.86.2 (`>=3.10`) plus 0.87.0 (`>=3.99`) in the local index, a 3.15.2 tool upgraded to 0.86.2, not 0.87.0. Local uv behavior agrees with the intended compatibility filter, but R3's own candidate filtering remains required for status.
7. **Index strategy:** if production passes `--default-index` on every upgrade, expect receipt growth; if it relies on the receipt index, it must validate and canonicalize the receipt and sanitize ambient config. This is an owner/plan decision, not resolved by this probe.

### 4.7 Unsupported, unknown and blockers

- **No M14-A execution blocker:** real uv install/upgrade/uninstall, explicit non-default roots, sibling isolation, pip/pipx/venv layouts and PEP 668 checks ran; personal-root isolation is scoped as described in §5.2, not a blanket no-write proof.
- **B wording decision:** pipx raw RECORD cannot be validated as-is; the exact ` -E` normalization is proved only for pipx 1.18.11 and the tested path/index cases. A general hash exception is not supported. See `BLOCKERS.md` B-1.
- **D/H policy decision:** uv receipt mutation and index duplication are observed; define immutable proof fields, receipt canonicalization and production flags. See `BLOCKERS.md` B-2/B-3.
- **Unknown:** public implicit installs have no recorded index (unknown provenance); only explicit `--default-index https://pypi.org/simple` was affirmative. Homebrew was read-only; no write test. `pip --user` required `--break-system-packages` into scratch; the production guidance remains read-only/informational. Only uv 0.13.10, pipx 1.18.11 and macOS arm64 were tested. The uv lifecycle used a local PEP 503 fixture, not production public PyPI; production public-index refusal policy remains separate.
- **Evidence:** canonical run `runs/20261127T143957Z`; raw receipts `logs/files/`; argv/exit `logs/cmd/`; structured `logs/inspect/`; `logs/help/`; `logs/summary.json` (94 passed, 0 failed, 3 warnings, 86 commands, `targets_cleaned: true`); `logs/evidence-files.json`; scratch `README.md` and `BLOCKERS.md`. Reproduce with `/opt/homebrew/bin/python3.15 probe_m14a.py` from `/private/tmp/agent-lens-m14a.fbGo6h` (network needed for the official uv artifact and public `pycowsay` observations; `--skip-public-network` records those as unknown).

**This supplement is evidence and a set of decisions, not an M14-A PASS.**

---

## 5. 2026-11-27 Post-Review Correction Note and Reproduction Appendix

**Status:** This section corrects the over-broad statements in §1–§4 after independent review, and supplies a self-contained reproduction appendix. It is still worker evidence, not an M14-A PASS.

**Version scope:** unless a sentence names otherwise, every behavioral statement in §4 and §5 is an observation on **uv 0.13.10**, **pipx 1.18.11**, **pip 26.2.2**, CPython **3.15.2** and **3.9.6**, on macOS `darwin 27.2.0` arm64. These are observations for those versions and layouts, not uv/pip/pipx contracts. Other versions may differ.

### 5.1 Historical PATH and generic ownership corrections

- **Historical PATH assertion:** §1.3 recorded uv as absent. It is not a current-host invariant: `~/.local/bin/uv` now exists (`uv 0.13.10`). No personal uv installation was changed. Early read-only version/help/root inventory used it; all lifecycle commands used the independently verified scratch binary. The pip/pipx probes used a PATH excluding uv.
- **Generic RECORD/entry_points assertion:** the committed §2.4 wording that a `RECORD` entry and/or `entry_points.txt` provides a deterministic ownership link is superseded. For the tested uv and pip venv/prefix/user layouts, the affirmative evidence is the exact `RECORD` row `../../../bin/<exe>` resolving to the selected script with matching hash and size. `entry_points.txt` is corroboration, not ownership: a distribution can declare a console script without owning the selected installed file. For pipx 1.18.11, raw `RECORD` hash/size does not match the final script; only the exact terminal ` -E` shebang normalization above matches both. There is no generic "entry_points and/or RECORD" rule and no blanket hash exception.
- **No general receipt-config claim:** the receipt observations in §4 are uv 0.13.10 observations. They do not assert stable receipt semantics across uv versions. In the tested version the receipt can be rewritten by upgrade (duplicate index entries, persisted ambient `index-url`/config) even when that configuration did not determine resolution; treat receipt configuration as mutable and version-scoped evidence, not as an immutable contract.

### 5.2 Scoped isolation and scratch cleanup

- **Isolation scope:** only the existing paths among the seven candidates in §4.1 were manifest-snapshotted; each manifest was capped at 3000 entries. The five existing roots were `~/.cache/uv`, `~/.config/uv`, `~/.local/bin`, `~/.local/share/uv`, `~/Library/Python`; their before/after diffs were empty. `~/.local/pipx` and `~/.cache/pip` were absent in both snapshots; creation would have appeared as `created_during_probe` and did not. This is not a general "no personal writes" proof and does not cover paths outside the list. Homebrew was checked only by `lstat` of the `python@3.15` runtime path, not all of `/opt/homebrew`; no write test was done there. No general claim is made about receipt configuration (§5.1).
- **Cleanup performed after review:** 24 leftover disposable paths were removed, all under `/private/tmp/agent-lens-m14a.fbGo6h` and only after canonical receipts were copied. This included the earlier run-local pipx shared environment `runs/20261127T143358Z/0` (11,770,024 bytes), `runs/20261127T142045Z/home` (4,346,178 bytes), and empty target/cache/tmp/xdg directories. Total deleted: 16,116,265 bytes. Deletion list and retained set: `CLEANUP-20261127.json` and `CLEANUP-20261127.md` in the scratch root. Separately, four fresh prefix/user verification targets were deleted after copying and are recorded in `VERIFY-20261127/CLEANUP-20261127-verify.json`.
- **Retained evidence:** canonical run `runs/20261127T143957Z`; canonical raw receipts `logs/files` = 636 files, 199,293 bytes, tree SHA-256 `b76b6e95cbfddf3353e2a9785cd616f9adb90b2ffea63d3b126e1e89b58d325c`, unchanged by cleanup. Earlier run `logs/`, `index/`, `index2/`, `wheels/`, `help/` and `console/` were retained; no earlier logs were deleted. The scratch `artifacts/`, `toolchains/`, `probe_m14a.py`, `README.md` and `BLOCKERS.md` remain. No target environment remains in the scratch tree. Canonical receipt `entrypoints.install-path` values still name the now-deleted disposable targets; those receipts are preserved evidence, not live paths.

### 5.3 Split `pip --prefix` / `--user` linkage verification

The canonical prefix and user console scripts both begin with the same exact shebang:

```text
#!/opt/homebrew/opt/python@3.15/bin/python3.15
```

Independent bounded read-only verification (no personal changes; fresh scratch prefix and scratch `HOME` user install, then target dirs removed):

| Check | Prefix | User |
| --- | --- | --- |
| Script | `<root>/bin/aider` regular file | `<root>/bin/aider` regular file |
| Shebang target | `/opt/homebrew/opt/python@3.15/bin/python3.15`, absolute | same |
| Shebang target status | symlink to `../Frameworks/Python.framework/Versions/3.15/bin/python3.15`; realpath `/opt/homebrew/Cellar/python@3.15/3.15.2/.../python3.15`; exists, executable; `--version` `Python 3.15.2` | same |
| Interpreter under root | none (`bin` contains only `aider`) | none (`bin` contains only `aider`) |
| `pyvenv.cfg` | absent | absent |
| Site-packages | `<root>/lib/python3.15/site-packages` | `<root>/lib/python/site-packages` |
| `INSTALLER` | `pip` | `pip` |
| RECORD row | `../../../bin/aider,sha256=tmt4js3w6r07mZziucHxdLEFCRDPtUb46xkxI7gs9dE,189` hash/size matched | same row, hash/size matched |

Evidence: `VERIFY-20261127/VERIFY-20261127.json`, `VERIFY-20261127/prefix-script`, `VERIFY-20261127/user-script`; the fresh verification `prefix`, scratch `user-home`, `pip-cache` and `tmp` targets were removed after copying, and the deleted/retained paths are recorded in `VERIFY-20261127/CLEANUP-20261127-verify.json`. This closes the layout condition as **read-only installation linkage**: the script is linked to a live absolute base interpreter and to installed distribution bytes, without requiring an interpreter under the prefix/user root. It does **not** claim that the installed tool is runnable, that its dependency graph is complete, or that arbitrary prefix/user layouts behave the same. No prefix/user interpreter was executed from the installed tool.

### 5.4 Self-contained reproduction appendix

This appendix is intentionally inline: no tracked script is added. Raw evidence lives under `/private/tmp` and is ephemeral (§5.5).

**Setup and official uv fetch:** Start a clean interactive shell with `env -i PATH=/opt/homebrew/bin:/usr/bin:/bin /bin/sh`, then paste the following three blocks into that shell. Exit it after the last block to stop the index and remove its private scratch.

```sh
set -eu
umask 077
S="$(mktemp -d /private/tmp/agent-lens-m14a-repro.XXXXXX)"
trap 'if [ -n "${index_pid:-}" ]; then kill "$index_pid" 2>/dev/null || :; wait "$index_pid" 2>/dev/null || :; fi; rm -rf -- "$S"' 0
cd "$S"
mkdir -p "$S/home" "$S/tmp" "$S/xdg-cache" "$S/xdg-config" "$S/xdg-data" "$S/xdg-state" "$S/xdg-bin" \
         "$S/uv-cache" "$S/uv-python" "$S/tools" "$S/bin" "$S/pip-cache"
export HOME="$S/home" TMPDIR="$S/tmp" XDG_CACHE_HOME="$S/xdg-cache" XDG_CONFIG_HOME="$S/xdg-config" \
       XDG_DATA_HOME="$S/xdg-data" XDG_STATE_HOME="$S/xdg-state" XDG_BIN_HOME="$S/xdg-bin" \
       UV_CACHE_DIR="$S/uv-cache" UV_PYTHON_INSTALL_DIR="$S/uv-python" UV_TOOL_DIR="$S/tools" \
       UV_TOOL_BIN_DIR="$S/bin" PIP_CACHE_DIR="$S/pip-cache"
export UV_PYTHON_DOWNLOADS=never UV_NO_PROGRESS=1
curl -fsSLO https://github.com/astral-sh/uv/releases/download/0.13.10/uv-aarch64-apple-darwin.tar.gz
curl -fsSLO https://github.com/astral-sh/uv/releases/download/0.13.10/uv-aarch64-apple-darwin.tar.gz.sha256
shasum -a 256 -c uv-aarch64-apple-darwin.tar.gz.sha256
tar -xzf uv-aarch64-apple-darwin.tar.gz
UV="$S/uv-aarch64-apple-darwin/uv"
"$UV" --version      # uv 0.13.10 (e3e7c1eac 2026-11-24 aarch64-apple-darwin)
```

**Minimal real wheels and local PEP 503 index:**

```sh
mkdir -p "$S/wheels" "$S/idx/wheels" "$S/idx/simple/aider-chat"
python3 - <<'PY'
import base64, hashlib, zipfile
from pathlib import Path
def wheel(ver, requires_python):
    dist, di = "aider_chat", f"aider_chat-{ver}.dist-info"
    files = {
        f"{dist}/__init__.py": f'__version__ = "{ver}"\n'.encode(),
        f"{dist}/cli.py": b"def main():\n    print('aider')\n    return 0\n",
        f"{di}/METADATA": (f"Metadata-Version: 2.1\nName: aider-chat\nVersion: {ver}\n"
                           f"Requires-Python: {requires_python}\n\n").encode(),
        f"{di}/WHEEL": b"Wheel-Version: 1.0\nRoot-Is-Purelib: true\nTag: py3-none-any\n",
        f"{di}/entry_points.txt": b"[console_scripts]\naider = aider_chat.cli:main\n",
    }
    record = []
    for name, data in sorted(files.items()):
        h = base64.urlsafe_b64encode(hashlib.sha256(data).digest()).rstrip(b"=").decode()
        record.append(f"{name},sha256={h},{len(data)}")
    record.append(f"{di}/RECORD,,")
    files[f"{di}/RECORD"] = ("\n".join(record) + "\n").encode()
    out = Path("wheels") / f"{dist}-{ver}-py3-none-any.whl"
    with zipfile.ZipFile(out, "w") as z:
        for name, data in files.items(): z.writestr(name, data)
wheel("0.85.0", ">=3.9")
wheel("0.86.2", ">=3.10")
PY
cp wheels/aider_chat-0.85.0-py3-none-any.whl idx/wheels/
printf '<a href="../../wheels/aider_chat-0.85.0-py3-none-any.whl">aider_chat-0.85.0-py3-none-any.whl</a>\n' \
  > idx/simple/aider-chat/index.html
python3 -u - >"$S/index.port" 2>"$S/index.log" <<'PY' &
import os
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
os.chdir("idx")
with ThreadingHTTPServer(("127.0.0.1", 0), SimpleHTTPRequestHandler) as server:
    print(server.server_port, flush=True)
    server.serve_forever()
PY
index_pid=$!
for n in 1 2 3 4 5 6 7 8 9 10; do
    [ -s "$S/index.port" ] && break
    sleep 1
done
test -s "$S/index.port"
INDEX="http://127.0.0.1:$(cat "$S/index.port")/simple"
```

**Representative exact lifecycle commands (initial index has only 0.85.0):**

```sh
"$UV" tool dir --no-config                 # $S/tools; exit 0
"$UV" tool dir --bin --no-config           # $S/bin; exit 0
"$UV" tool install --no-config --no-progress --allow-insecure-host 127.0.0.1 \
  --python /opt/homebrew/bin/python3.15 --default-index "$INDEX" aider-chat
# exit 0; stderr includes: + aider-chat==0.85.0 / Installed 1 executable: aider
cp wheels/aider_chat-0.86.2-py3-none-any.whl idx/wheels/
printf '<a href="../../wheels/aider_chat-0.85.0-py3-none-any.whl">0.85.0</a>\n<a href="../../wheels/aider_chat-0.86.2-py3-none-any.whl">0.86.2</a>\n' \
  > idx/simple/aider-chat/index.html
"$UV" tool upgrade --no-config --no-progress --python /opt/homebrew/bin/python3.15 aider-chat
# exit 0; stderr: Updated aider-chat v0.85.0 -> v0.86.2
UV_OFFLINE=1 UV_NO_CONFIG=1 "$UV" tool uninstall --no-progress aider-chat
# exit 0; stderr: Uninstalled 1 executable: aider
```

For the pin non-success and pip/pipx evidence, the canonical run used:
`uv tool install ... aider-chat==0.85.0` then `uv tool upgrade ... aider-chat` → **exit 0**, stderr `Nothing to upgrade` plus the `pinned to 0.85.0` hint, version stayed 0.85.0. This is why R6 must require a strictly newer version rather than exit status alone. The direct wheel path and HTTP URL cases likewise stayed at 0.85.0 with `Nothing to upgrade`.

**Representative sanitized receipt and RECORD values from the canonical run:**

```toml
[tool]
requirements = [{ name = "aider-chat" }]
python = "/opt/homebrew/bin/python3.15"
entrypoints = [
  { name = "aider", install-path = "<RUN>/targets/uv-bin-lifecycle/aider", from = "aider-chat" },
]

[tool.options]
index = [{ url = "<LOCAL-INDEX>", explicit = false, default = true, format = "simple", authenticate = "auto" }]
```

```text
uv RECORD:     ../../../bin/aider,sha256=FLrIvI7b5ktCFNCIPRMVn38gu_FryPVgXlYkadSBfEA,386
pip prefix/user RECORD: ../../../bin/aider,sha256=tmt4js3w6r07mZziucHxdLEFCRDPtUb46xkxI7gs9dE,189
pipx path:     RECORD 248 bytes, actual 251; removing terminal ' -E' => 248 bytes and RECORD hash match
pipx index:    RECORD 254 bytes, actual 257; removing terminal ' -E' => 254 bytes and RECORD hash match
```

Public-default receipt had no `[tool.options]` section (unknown provenance); the explicit-public receipt recorded `https://pypi.org/simple`. The hostile-env custom receipt contained the live `[tool.options].index` plus top-level `index-url = "http://127.0.0.1:9/simple"`; the explicit-index upgrade receipt had the same live index twice plus that top-level value.

**Runnable extraction if the private evidence still exists:**

```sh
R=/private/tmp/agent-lens-m14a.fbGo6h/runs/20261127T143957Z
jq -r '.[] | "\(.sha256)  \(.path)"' "$R/logs/evidence-files.json" | shasum -a 256 -c -
```

The canonical run contains 636 copied receipt/metadata files, 86 command records, 94 checks and the structured `logs/inspect/*.json`; the scratch `probe_m14a.py` is the full executable probe, but it is not tracked in the repository.

### 5.5 Durability and unclosed conditions

- **Durability:** `/private/tmp/agent-lens-m14a.fbGo6h` is private scratch (mode `0700`) but **ephemeral**; it may be deleted on reboot or by the host. The report retains representative values and the inline reproduction recipe; raw evidence paths above are current, not durable. No tracked script or huge log is added to the repository.
- **No unclosed condition from the reviewed BLOCK:** the exact prefix/user shebang/linkage condition, scoped isolation, historical PATH correction, generic RECORD/entry_points correction, version scoping, cleanup record and reproduction appendix are now recorded. The remaining open items are plan decisions, not missing A evidence: B-1 pipx exact-normalization wording, and B-2/B-3 receipt-mutation/interpreter-currentness policy. If a reviewer requires a general receipt-config contract or a blanket pipx hash rule, that condition cannot be closed by this evidence and must be reported as unsupported.

**This section is a correction and evidence index, not an M14-A PASS.**
