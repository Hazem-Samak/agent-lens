# M14 Master Plan — Python Tool Support (`uv` Management & `pip` Diagnostics)

- **Date:** 2026-11-27
- **Branch:** `milestone/m14-python` (created from `main` at `882afd3517cda6f10c901dd973dc8f5e4083b2c2`)
- **Planning Mode:** Solo Owner-Directed Planning + Two-Pass Adversarial Self-Review (`briefs/M14-planning/self-review.md`)
- **Status:** Frozen after Two-Pass Self-Review — ready for owner approval before M14-A implementation dispatch

---

## 1. Objective & Scope

M14 delivers **Python tool support** per `ROADMAP.md` §4 and `AGENT_LENS_SCOPE.md` §§5, 6, 21.4, and 22.2:

> **User result:** `uv`-installed tools are recognized and manageable; supported `pip` installations show accurate environment/package details and safe guidance.
>
> - Discover verified `uv` tool environments and known `pip`-managed executables without recursively scanning arbitrary Python projects.
> - Implement PEP 440-compatible ordering and registry metadata with interpreter compatibility, prerelease, and index-provenance rules. Do not reuse semver blindly.
> - Add `uv` Update/Uninstall through the existing workflow. Keep system/shared/ambiguous `pip` environments informational.
> - **Acceptance:** disposable `uv` installs upgrade and uninstall through the app; environments cannot be cross-targeted; `uv`/`pip` ownership is distinguished; custom/unavailable indexes and unsupported compatibility remain truthful; local inventory works offline.

M14 extends the three-layer architecture (D-001) across **eight sequential phases (`M14-A` through `M14-H`)** while preserving every M0–M13 contract:

1. **Catalogue & Do-Not-Declare Discipline (`docs/catalogue-identities.md`):**
   - Only **two** catalogue tools have verified official PyPI CLI distributions from M11-A:
     - **`aider`** (`Aider`, `executableName`: `"aider"`): PyPI package **`aider-chat`** (currently declares `homebrewFormula:aider`; M14 adds `uvTool:aider-chat` and `pip:aider-chat`, plus `"~/.local/bin"` in `extraSearchRoots` so standard `uv tool` / `pipx` user-bin shims are discoverable even when `~/.local/bin` is absent from a non-standard login shell `PATH`).
     - **`hermes`** (`Hermes`, `executableName`: `"hermes"`): PyPI package **`hermes-agent`** (currently declares `homebrewFormula:hermes-agent` and `extraSearchRoots: ["~/.local/bin"]`; M14 adds `uvTool:hermes-agent` and `pip:hermes-agent`).
   - **Binding Do-Not-Declare PyPI Identities:** M14 MUST NEVER declare PyPI `goose` (`steder/goose` 1.0.0 unrelated SQL migration tool), PyPI `deepseek-harness` or `deepseek-harness-cli` (third-party `HenryZ838978` packages), or PyPI `google-antigravity` (Python SDK `antigravity-sdk-python`, not the `agy` CLI). The remaining 12 catalogue tools retain their existing declarations unchanged.
2. **Strict `uv` vs `pip` Capability Boundary:**
   - **`uvTool` (`uv tool`)** supports verified ownership, PyPI latest-version probing, **Update (`uv tool upgrade`)**, and **Uninstall (`uv tool uninstall`)** gated by D-021 `acceptedOperations: ["uvToolUpdate", "uvToolUninstall"]`.
   - **`pip` (`pip`)** supports verified read-only diagnostic ownership (environment root, site-packages root, installed package version, Python interpreter version, installer provenance, and PEP 668 `EXTERNALLY-MANAGED` / `pipx` / `venv` / shared-prefix classification) and PyPI latest-version probing, but is **strictly informational (`Read-only` in V1)** with **zero** D-021 mutation operations (`AcceptedOperation` defines no `pip*` cases).

---

## 2. Architecture & Design Rulings (`R1`–`R16`)

### R1 — Python Manager Vocabulary, Heuristic Source Stability & Ownership Proofs (`uvTool` vs `pip`)

1. **`PackageManager` Vocabulary Extension (`Sources/AgentLensCore/Detection/DetectorMetadata.swift` & `DetectorRegistry.swift`):**
   - Extend `PackageManager` with two distinct Python cases:
     - `case uvTool` (`rawValue`: `"uvTool"`, `label`: `"uv tool"`)
     - `case pip` (`rawValue`: `"pip"`, `label`: `"pip"`)
   - Update the invalid-manager error reason in both `DeclaredPackage.init(from:)` (`DetectorMetadata.swift`) and `DetectorRegistry.parsePackages` (`DetectorRegistry.swift`) to:
     `"must be one of npm, homebrewFormula, homebrewCask, uvTool, pip"`.
   - Update `DetectorMetadataTests.unknownPackageManagerIsRejectedWithTheManagerField` (which previously used `"pip"` as its example of an unknown manager string) to use `"cargo"` and add positive decoding assertions for `.uvTool` and `.pip`.
   - **Package-name validation (`DeclaredPackage.validationFailure`):** Both `.uvTool` and `.pip` enforce PEP 508 / PEP 503 package-name grammar: single path component (no `/`), non-empty ASCII matching `^[A-Za-z0-9]([A-Za-z0-9._-]*[A-Za-z0-9])?$` (no version specifiers, no extras `[...]`, no whitespace, no leading `-`). Canonical comparison uses PEP 503 normalization (`lowercased()`, replacing runs of `[-_.]` with a single `-`).
2. **Heuristic `ToolDetector.classifySource(resolvedPath:)` Remains Unchanged:**
   - `ToolDetector.classifySource(resolvedPath:)` in `Sources/AgentLensCore/Detection/ToolDetector.swift` continues to return `"npm"` (contains `/lib/node_modules/`), `"brew"` (contains `/Cellar/`), or `"standalone"` (everything else).
   - **Why:** In Python virtual environments (`uv tool` and `pip` venvs), the entry-point script `<venv>/bin/<executableName>` is a **regular file** with a `#!<venv>/bin/python3` shebang, and `<bin-dir>/<executableName>` (e.g., `~/.local/bin/aider`) is a symlink to `<venv>/bin/<executableName>`. Therefore, `resolvingSymlinksInPath()` resolves `selection.canonicalTarget` to `<venv>/bin/<executableName>` (NOT to `/opt/homebrew/Cellar/python@3.x/...`), which naturally classifies as `"standalone"`. Keeping `classifySource` untouched preserves all 14 existing synthetic fixture tests (`DetectorRegistryTests`) and `DetectorRegistry.knownSources` (`["npm", "brew", "standalone"]`).
   - **Edge case — `pip install --break-system-packages` directly into Homebrew Python's Cellar framework prefix (`/opt/homebrew/Cellar/python@3.x/<ver>/.../bin/<executableName>`):** Here `selection.canonicalTarget` contains `/Cellar/python@3.x/`, so `classifySource` returns `"brew"`. Routing in `InstallationOwnershipVerifier` (below) handles this explicitly so a tool installed into Homebrew's `python@3.x` Cellar prefix does not get stranded on a spurious `.formulaRecordMismatch` when the detector declares both `homebrewFormula` and `pip`.
3. **Deterministic Multi-Manager Routing in `Sources/AgentLensCore/Ownership/InstallationOwnershipVerifier.swift`:**
   - For a detected tool with `definition.packages`:
     1. **`source == "npm"` and declares `.npm`:** route to `verifyNpm`.
     2. **`source == "brew"` and declares `.homebrewFormula`:**
        - If the detector also declares `.pip`, inspect whether `selection.canonicalTarget` sits inside a Homebrew Python runtime keg (`/Cellar/python/` or `/Cellar/python@*/`) whose formula rack name does NOT match any declared `.homebrewFormula` package name and whose `<env-root>/lib/python*/site-packages` (or framework `lib/python*/site-packages`) exists. If so, route directly to `verifyPip`.
        - Otherwise, route to `verifyHomebrew`.
     3. **Otherwise (including `source == "standalone"` or `source == "brew"` without `.homebrewFormula`):**
        - If the detector declares `.homebrewCask`, run `verifyHomebrewCask`. If `.verified` (or if the detector declares neither `.uvTool` nor `.pip`), return that outcome. If `verifyHomebrewCask` returns `.unknown(.managerRootMismatch)` or `.unknown(.unsupportedInstallationLayout)` because the selected binary is outside Caskroom **and** the detector also declares `.uvTool` or `.pip`, continue to Python ownership verification.
        - If the detector declares `.uvTool` or `.pip`, run the **Anchored Python Environment Classifier** using pure local filesystem `lstat` (before requiring `uv` to exist on `PATH`, so a machine without `uv` installed can still verify `.pip` virtualenvs):
          - Derive candidate `<env-root>` as the parent directory of `<bin-dir>` where `selection.canonicalTarget` resides (`<env-root>/bin/<executableName>`).
          - **Case A (`uv` tool environment):** If `<env-root>/uv-receipt.toml` exists (`lstat` regular file or symlink—never downgraded to `.pip` even if tampered), OR if `uv` is resolvable on `PATH` and `selection.canonicalTarget` / `selection.entryPath` resides under `uv tool dir` / `uv tool dir --bin`, route exclusively to **`verifyUvTool`**.
          - **Case B (`pip` environment):** Otherwise, if the detector declares `.pip` and `<env-root>/pyvenv.cfg` exists or `<env-root>/lib/python*/site-packages` exists (a non-`uv` virtual environment, `pipx` venv, user site, or framework prefix), route to **`verifyPip`**.
          - **Case C (outside all Python roots — e.g., standalone shell/git wrapper like `~/.hermes/hermes-agent/.hermes/bin/hermes`):** If `.uvTool` is declared, route to `verifyUvTool` (which returns `.unknown(.managerRootMismatch)` when `uv` is present or `.unknown(.managerUnavailable)` / `.unknown(.managerRootMismatch)` when outside any Python environment).
4. **Python Environment Metadata on `VerifiedInstallation` (`Sources/AgentLensCore/Ownership/InstallationOwnership.swift`):**
   - Add `PythonEnvironmentKind` (`.uvTool`, `.virtualEnvironment`, `.pipxEnvironment`, `.externallyManagedSystem`, `.sharedPrefix`), `PythonIndexProvenance` (`.publicPyPI`, `.customIndex(String)`, `.nonRegistrySource(String)`), and `PythonEnvironmentMetadata` (`installedVersion: String`, `interpreterVersion: String?`, `requiresPython: String?`, `environmentKind: PythonEnvironmentKind`, `indexProvenance: PythonIndexProvenance`, `isVersionPinned: Bool`, `extraRequirements: [String]`).
   - Add `public let pythonEnvironment: PythonEnvironmentMetadata?` to `VerifiedInstallation` with a default value of `nil` in `VerifiedInstallation.init(...)` so all existing M9–M13 call sites and tests compile without modification.
5. **6-Step `uvTool` Ownership Proof (`Sources/AgentLensCore/Ownership/UvToolOwnershipProbe.swift`):**
   1. **Manager Resolution & Pre-Query Snapshot:** Resolve `uv` from `ShellEnvironment.pathEntries` using `FileIdentityObserver.observeExecutable` (capturing `managerEntryPath`, `managerTarget`, `managerFingerprint`). If `uv` is not found on `PATH`, return `.unknown(.managerUnavailable)`.
   2. **Roots Query (`uv tool dir` and `uv tool dir --bin`):**
      - Run `[manager.canonicalTarget, "tool", "dir"]` and `[manager.canonicalTarget, "tool", "dir", "--bin"]` via `UpdateCommandRunner` with timeout `5.0s` and read-only environment (`UV_NO_CACHE=1`, `UV_NO_PROGRESS=1`, `UV_OFFLINE=1`).
      - Re-observe `uv` and `selection` around the query; if either changed, return `.unknown(.managerChanged)` or `.unknown(.selectedExecutableChanged)`.
      - Canonicalize `<uv-tool-dir>` and `<uv-tool-bin-dir>` via `realpath` and bind their directory `FileIdentity`.
   3. **Selected Entry & Canonical Target Containment Proof:**
      - `selection.canonicalTarget` MUST decompose as `<uv-tool-dir>/<tool-dir>/bin/<executableName>` where `<tool-dir>` matches a declared `.uvTool` package name under PEP 503 normalization and `<executableName>` matches `definition.executableName`. (If outside `<uv-tool-dir>`, return `.unknown(.managerRootMismatch)`.)
      - Verify `<uv-tool-bin-dir>/<executableName>` exists via `lstat`, and resolves to `selection.canonicalTarget` with matching `ExecutableFingerprint` (if missing or pointing elsewhere, return `.unknown(.managerEntryMismatch)`).
   4. **Anchored `uv-receipt.toml` Proof (Bounded `O_NOFOLLOW` Regular-File Read, Cap 64 KiB):**
      - Open `<uv-tool-dir>/<tool-dir>/uv-receipt.toml` with `O_RDONLY | O_NOFOLLOW | O_CLOEXEC`, verify `fstat` is `S_IFREG` and size <= `65,536` bytes, and capture its file fingerprint before and after reading.
      - Parse the `[tool]` table: verify `requirements` contains the primary package matching the declared `.uvTool` package name (PEP 503 normalized). Extract whether the primary requirement carries an exact version pin (`==` / `===`), any extra requirements (`--with`), `entrypoints` (when present, confirming an entrypoint with `name == definition.executableName` and `from` matching the declared package), and index/source options (`index-url`, `extra-index-url`, `find-links`, git/path/url sources).
   5. **Anchored `.dist-info` & `pyvenv.cfg` Proof (Zero Recursive Crawling):**
      - Read `<env-root>/pyvenv.cfg` via bounded `O_NOFOLLOW` regular-file read (cap 32 KiB) to extract `version_info` or `version` (e.g., `3.12.8`).
      - List only the single directory level `<env-root>/lib/python*/site-packages` (max 256 entries, zero recursion) to find the unique `<dist>-<ver>.dist-info` directory whose PEP 503-normalized `<dist>` prefix matches the declared package name.
      - Read `METADATA` (`O_NOFOLLOW`, cap 256 KiB) to confirm `Name:` matches the declared package and extract `Version:` and `Requires-Python:`.
      - Read `RECORD` (`O_NOFOLLOW`, cap 1 MiB) or `entry_points.txt` (`O_NOFOLLOW`, cap 64 KiB) to verify `../../../bin/<executableName>` or `[console_scripts]` `<executableName>` is owned by this distribution (if absent, return `.unknown(.executableNotDeclared)`).
      - Inspect `direct_url.json` (if present, `O_NOFOLLOW`, cap 64 KiB) to classify VCS/local/archive installs vs registry installs.
   6. **Post-Read Re-Observation & `VerifiedInstallation` Construction:**
      - Re-observe `selection`, `manager`, `uv-receipt.toml`, and `METADATA`; if any fingerprint drifted, return `.unknown(.proofChanged)` or `.unknown(.selectedExecutableChanged)`.
      - Return `.verified(VerifiedInstallation(manager: .uvTool, packageName: declared.name, managerEntryPath: manager.entryPath, managerTarget: manager.canonicalTarget, managerFingerprint: manager.fingerprint, managerRoot: uvToolDir, installationRoot: envRoot, selection: ..., pythonEnvironment: ...))`.
6. **5-Step `pip` Diagnostic Ownership Proof (`Sources/AgentLensCore/Ownership/PipOwnershipProbe.swift` — Read-Only):**
   1. **Anchored Environment Boundary Check (Zero Recursive Filesystem Scanning):**
      - Starting strictly from `selection.canonicalTarget` (`<env-root>/bin/<executableName>`), derive `<env-root>` as the parent of `bin`. Never scan `$HOME`, project directories, or arbitrary virtualenv roots.
      - Verify `<env-root>/uv-receipt.toml` does NOT exist (a `uv` tool environment is never misclassified as `.pip`).
      - Locate `<site-packages>` via bounded single-level lookup `<env-root>/lib/python*/site-packages`. If absent, return `.unknown(.managerRootMismatch)`.
   2. **Environment Interpreter Binding:**
      - Observe `<env-root>/bin/python3` (or `<env-root>/bin/python`) via `FileIdentityObserver.observeExecutable` to populate `managerEntryPath`, `managerTarget`, and `managerFingerprint` on `VerifiedInstallation` (no global `pip` on `PATH` required; if the environment has no valid Python binary, return `.unknown(.managerUnavailable)`).
   3. **Environment Classification (`PythonEnvironmentKind`):**
      - Inspect `<env-root>/pyvenv.cfg` and `<env-root>/lib/python*/EXTERNALLY-MANAGED` (PEP 668 marker):
        - `.externallyManagedSystem` (`EXTERNALLY-MANAGED` file exists, e.g., Homebrew system Python)
        - `.pipxEnvironment` (`<env-root>/pipx_metadata.json` exists or `<env-root>` is inside a `pipx/venvs/` root)
        - `.virtualEnvironment` (`pyvenv.cfg` exists without `uv-receipt.toml` or `pipx_metadata.json`)
        - `.sharedPrefix` (no `pyvenv.cfg` and no `EXTERNALLY-MANAGED`, e.g., `--user` or custom prefix)
   4. **Anchored `.dist-info` Verification & TOCTOU Check:**
      - Locate the unique `<site-packages>/<dist>-*.dist-info` matching the declared `.pip` package name (PEP 503 normalized).
      - Read `METADATA` (`O_NOFOLLOW`, cap 256 KiB) to verify `Name:` and extract `Version:` and `Requires-Python:`.
      - Verify executable ownership via `RECORD` (`../../../bin/<executableName>`) or `entry_points.txt` (`[console_scripts]` `<executableName>`).
      - Inspect `direct_url.json` (if present, `O_NOFOLLOW`, cap 64 KiB) for index/source provenance.
      - Re-observe `selection`, interpreter, and `METADATA` fingerprints for TOCTOU consistency.
   5. **Record Construction:**
      - Return `.verified(VerifiedInstallation(manager: .pip, packageName: declared.name, ..., managerRoot: sitePackagesPath, installationRoot: envRoot, selection: ..., pythonEnvironment: ...))`.

### R2 — PEP 440 Version Parsing, Ordering & `requires_python` Compatibility (`Sources/AgentLensCore/Updates/PEP440Version.swift`)

1. **`VersionScheme` Extension (`Sources/AgentLensCore/Updates/VersionStatus.swift` & `VersionComparison.swift`):**
   - Extend `VersionScheme` in `VersionStatus.swift` with `case pep440`.
   - Extend `VersionComparison.ordering(_:_:scheme:)` in `VersionComparison.swift` so `.pep440` delegates to `PEP440Version.compare(_:_:)`.
   - When a tool's verified ownership is `.uvTool` or `.pip`, `PyPIUpdateProbe` and `UpdateProbeCoordinator` evaluate versions using `VersionScheme.pep440` (rather than strict 3-component `.semanticVersion`, which rejects valid 2-segment Python versions like `0.86` and post/dev releases like `0.86.2.post1`).
2. **Full Deterministic PEP 440 Parser & Total Ordering (`PEP440Version`):**
   - Implement the normative PEP 440 specification in `Sources/AgentLensCore/Updates/PEP440Version.swift`:
     - Optional leading `v`/`V` and ASCII whitespace trimming.
     - **Epoch:** `N!` (non-negative integer, defaults to `0`).
     - **Release segment:** 1 or more dot-separated non-negative integers (`[0-9]+(\.[0-9]+)*`). Trailing `.0` segments are stripped during comparison normalization so `1.2 == 1.2.0 == 1.2.0.0`.
     - **Pre-release segment:** `[._-]?(a|b|c|rc|alpha|beta|pre|preview)[._-]?[0-9]*` normalized to `.alpha(N)`, `.beta(N)`, `.rc(N)` (implicit number defaults to `0`; `c`, `pre`, `preview` normalize to `.rc`).
     - **Post-release segment:** `(?:[._-]?(?:post|rev|r)[._-]?[0-9]*)|(?:-[0-9]+)` normalized to `.post(N)` (implicit number defaults to `0`).
     - **Dev-release segment:** `[._-]?dev[._-]?[0-9]*` normalized to `.dev(N)` (implicit number defaults to `0`).
     - **Local version label:** `\+[a-zA-Z0-9]+([._-][a-zA-Z0-9]+)*`. Public PyPI releases with `+local` labels are rejected as invalid registry versions; if an installed version carries `+local`, `PEP440Version.compare` returns `nil` so `VersionStatus.evaluate` reports `.unknown(installed: ..., reason: .unsupportedVersion)`.
   - **Normative PEP 440 Sort Key Order within an Epoch & Normalized Release Tuple:**
     1. `.dev(M)` without pre/post (`1.0.dev1 < 1.0a1`)
     2. Pre-release with optional `.dev` or `.post`: `1.0a1.dev1 < 1.0a1 < 1.0a1.post1.dev1 < 1.0a1.post1 < 1.0b1 < 1.0rc1`
     3. Final release (`1.0`)
     4. Post-release with optional `.dev`: `1.0 < 1.0.post1.dev1 < 1.0.post1`
3. **`requires_python` Specifier Set Evaluator (`PEP440SpecifierSet`):**
   - Implement PEP 440 version specifiers for `Requires-Python` evaluation against the tool environment's observed Python interpreter version (`major.minor.patch`):
     - Strip optional outer parentheses `( ... )` and whitespace.
     - Operators: `~=`, `==` (including prefix wildcard `== 3.12.*`), `!=` (including `!= 3.11.*`), `<=`, `>=`, `<`, `>`, `===`.
     - Comma-separated clauses combine with logical AND (`>=3.9, <3.14, !=3.11.0`).
   - **Interpreter Version Extraction:**
     - Primary: `version_info` or `version` in `<env-root>/pyvenv.cfg` (written by both `uv` and stdlib `venv` / `virtualenv`).
     - Fallback (when `pyvenv.cfg` lacks a full `X.Y.Z` version key, e.g. system prefix): run a bounded `2.0s` read-only query `[interpreterTarget, "--version"]` (parsing `Python X.Y.Z`) during ownership or update probing.
     - If the environment's interpreter version cannot be determined or parsed, and a candidate PyPI release declares a non-empty `requires_python` constraint, `PyPIUpdateProbe` refuses to assume compatibility and returns `.unknown(installed: ..., reason: .pythonInterpreterIncompatible)`.

### R3 — PyPI Latest-Version Probe, Index Provenance & Separate Cache Document (`Sources/AgentLensCore/Updates/PyPIUpdateProbe.swift` & `PyPIUpdateMetadataCache.swift`)

1. **Additive `UnknownReason` Cases (`Sources/AgentLensCore/Updates/VersionStatus.swift`):**
   - Reuse existing `UnknownReason` cases wherever semantics match (`.networkUnavailable`, `.queryTimedOut`, `.rateLimited`, `.metadataInvalid`, `.unsupportedChannel`, `.unsupportedVersion`, `.newerThanKnownMetadata`, `.unsupportedRegistry`).
   - Add **one** Python-specific additive case to `UnknownReason`:
     - `case pythonInterpreterIncompatible` — when newer stable releases exist on PyPI, but every release newer than `installedVersion` fails `Requires-Python` for the tool environment's Python interpreter version (or requires an interpreter version that could not be verified).
   - Map custom `--index-url` / `--find-links` or non-PyPI `direct_url.json` (VCS/local/archive) provenance to the existing **`UnknownReason.unsupportedRegistry`** (rendered with context-specific copy in `UpdateScanRenderer` and `WorkflowPresentation` when `manager` is `.uvTool` or `.pip`).
2. **Index Provenance Check Before Any Network Call:**
   - Before querying `https://pypi.org/pypi/<package>/json` (or reading cache), `PyPIUpdateProbe` checks `verifiedInstallation.pythonEnvironment?.indexProvenance`:
     - If `.customIndex(_)` or `.nonRegistrySource(_)`, return `VersionStatus.unknown(installed: installedVersion, reason: .unsupportedRegistry)` immediately with zero network traffic.
3. **PyPI JSON Metadata Query & Candidate Selection:**
   - Endpoint: `https://pypi.org/pypi/<normalized-package>/json` fetched via `UpdateCommandRunner` (`["/usr/bin/curl", "-fsSL", "--max-time", "8", "--max-filesize", "1048576", "-H", "Accept: application/json", url]`, matching the injectable `UpdateCommandRunner` architecture used across Core update probes with an 8.0s timeout and 1 MiB response cap).
   - **Candidate Filtering Rules across `releases` dictionary (`[String: [PyPIReleaseFile]]`):**
     1. If installed version is a PEP 440 pre-release or dev-release, return `.unknown(installed: installedVersion, reason: .unsupportedChannel)`.
     2. For each key in `releases`:
        - Discard if the file array is empty (`files.isEmpty`) or if **all** files have `"yanked": true`.
        - Parse the release key with `PEP440Version.parse`. Discard unparseable keys, local versions (`+...`), pre-releases, and dev-releases.
     3. **`requires_python` Compatibility Filtering:**
        - Evaluate `requires_python` on the non-yanked files of each stable release against the environment's observed Python interpreter `PEP440Version`. (If non-yanked files in the same release disagree on `requires_python`, a release is compatible if at least one non-yanked wheel or sdist file satisfies the environment's interpreter.)
        - Track `highestOverallStable` (across all non-yanked stable releases) and `highestCompatibleStable` (across stable releases compatible with the environment's Python interpreter).
        - If `highestCompatibleStable == nil`:
          - Return `.unknown(installed: installedVersion, reason: highestOverallStable != nil ? .pythonInterpreterIncompatible : .metadataInvalid)`.
        - If `highestOverallStable > highestCompatibleStable` AND `highestCompatibleStable <= installedPEP440` AND `highestOverallStable > installedPEP440`:
          - Newer releases exist on PyPI, but all of them require a newer Python interpreter than the environment has. Return **`.unknown(installed: installedVersion, reason: .pythonInterpreterIncompatible)`**.
        - Otherwise, compare `installedVersion` against `highestCompatibleStable` using `VersionStatus.evaluate(installed: ..., latest: ..., scheme: .pep440)`:
          - `installed < highestCompatibleStable` → `.updateAvailable(installed: ..., latest: ...)`
          - `installed == highestCompatibleStable` → `.upToDate(installed: ..., latest: ...)`
          - `installed > highestCompatibleStable` → `.unknown(installed: ..., reason: .newerThanKnownMetadata)`
4. **Separate Ecosystem Cache Document (`pypi-update-metadata-v1.json` in `PyPIUpdateMetadataCache.swift`):**
   - Stored in the cache directory alongside `npm-update-metadata-v1.json`, `homebrew-update-metadata-v1.json`, and `homebrew-cask-update-metadata-v1.json`.
   - Schema version `1`, TTL `6 hours` (`21,600s`), max size `1 MiB` (`1,048,576` bytes), `O_NOFOLLOW` regular-file read validation, atomic temp-file + rename persistence.
   - Cache entry key binds `(normalizedPackageName, interpreterMajorMinorPatch)` so compatibility-filtered results for Python 3.11 never cross-contaminate an environment on Python 3.13.
   - Deduplicate concurrent in-flight requests within `UpdateProbeCoordinator` by `(normalizedPackageName, interpreterMajorMinorPatch)`.

### R4 — D-021 Vocabulary Extension (`uvToolUpdate`, `uvToolUninstall`)

1. **`AcceptedOperation` Extension (`Sources/AgentLensCore/Detection/DetectorMetadata.swift`):**
   - Keep `DetectorRegistry.supportedSchemaVersion = 2`.
   - Extend `AcceptedOperation` with two additive cases:
     - `case uvToolUpdate`
     - `case uvToolUninstall`
   - Update `DetectorMetadataValidation.acceptedOperations` error reason string to:
     `"must be one of npmUpdate, npmUninstall, homebrewFormulaUpdate, homebrewFormulaUninstall, homebrewCaskUpdate, homebrewCaskUninstall, uvToolUpdate, uvToolUninstall"`.
   - **No `pip` cases exist in `AcceptedOperation`.** Any attempt to declare `"pipUpdate"` or `"pipUninstall"` in `DefaultDetectors.json` fails schema decoding at load time.
2. **Shared Serial Mutation Gate (`OperationExecutionGate.shared`):**
   - `UvToolUpdateOperation` and `UvToolUninstallOperation` acquire the process-wide `OperationExecutionGate.shared` (`Sources/AgentLensCore/Operations/OperationModels.swift`) across both `prepare` and `execute`, preventing concurrent mutations across npm, Homebrew formula, Homebrew cask, and `uv tool`.

### R5 — `uv` Environment Isolation, Pin/Constraint Guardrails & Execution Contract (`Sources/AgentLensCore/Operations/UvToolOperationModels.swift`)

1. **Clean Subprocess Environment (`UvToolOperationEnvironment`):**
   - Both `uv tool upgrade` and `uv tool uninstall` execute directly via `OperationProcessRunner` (literal argument vectors, no `/bin/sh -c`, process group isolation via `SETSID`) with a sanitized environment:
     - `UV_NO_PROGRESS=1` (suppresses terminal spinners/progress bars)
     - `UV_NO_MODIFY_PATH=1` (prevents `uv` from modifying shell RC files)
     - `NO_COLOR=1`, `TERM=dumb` (deterministic plain-text logs)
     - `UV_PYTHON_DOWNLOADS=never` (prevents `uv` from silently downloading a standalone Python distribution during a tool upgrade)
2. **Two-Phase `prepare` → `claim()` → `execute` Pattern (Matching M12/M13 Operations):**
   - Following `NpmUpdateOperation` / `HomebrewFormulaUpdateOperation` / `HomebrewCaskUpdateOperation`:
     - `prepare(...)` re-runs `UvToolOwnershipProbe.verify` and `PyPIUpdateProbe` live, binds the single-use `UvToolUpdatePreparation` / `UvToolUninstallPreparation` token (with observed fingerprints for `uv`, `selection`, `uv-receipt.toml`, and `METADATA`), and returns `.ready(preparation)` or `.unavailable(reason)`.
     - `execute(preparation:...)` claims the single-use preparation token (`preparation.claim()`), re-verifies all bound fingerprints immediately before spawning `uv` (failing closed with `.preconditionChanged` if anything shifted between preview and confirmation), runs the command, and executes post-action reconciliation.
3. **Pre-Flight Receipt Guardrails (No Silent Constraint Destruction):**
   - During `UvToolUpdateOperation.prepare`:
     - **D-021 Policy Check:** Verify `definition.acceptedOperations.contains(.uvToolUpdate)`.
     - **Custom Index / Non-Registry Source Refusal:** If `pythonEnvironment.indexProvenance` is `.customIndex` or `.nonRegistrySource`, return `.unavailable(.customIndexUnsupported)`.
     - **Version Pin Refusal:** If `pythonEnvironment.isVersionPinned == true` (primary requirement in `uv-receipt.toml` carries `==` or `===`), return `.unavailable(.versionPinnedInReceipt)`.
     - **`--with` Extra Packages Preservation:** Because `uv tool upgrade <package>` reads `<uv-tool-dir>/<tool-dir>/uv-receipt.toml` natively and preserves `[tool].requirements` extras automatically, standard PyPI `--with` extras are allowed and disclosed in `UvToolUpdatePreview.extraRequirements`.

### R6 — `uv tool upgrade` Operation & Post-Upgrade Reconciliation (`Sources/AgentLensCore/Operations/UvToolUpdateOperation.swift`)

1. **Exact Command Vector:**
   - `[manager.canonicalTarget, "tool", "upgrade", "--no-progress", "--python-preference", "system", verified.packageName]`
   - Timeout: **`180.0s`** (`defaultExecutionTimeoutSeconds: 180.0`).
2. **4-Step Post-Upgrade Reconciliation (Never Trust Exit Code `0` Alone):**
   - After subprocess termination, re-run `ToolDetector`, `PathDiagnostics`, and `UvToolOwnershipProbe` for the tool definition:
     1. Confirm `.uvTool` ownership still verifies for `verified.packageName` inside the same `installationRoot`.
     2. Read the post-upgrade `.dist-info/METADATA` `Version:` (`observedAfterVersion`).
     3. Confirm `<uv-tool-bin-dir>/<executableName>` and `<uv-tool-dir>/<tool-dir>/bin/<executableName>` exist and are executable.
     4. Evaluate outcome:
        - If exit code == `0` and `VersionComparison.ordering(beforeVersion, afterVersion, scheme: .pep440) == .older`: invalidate `pypi-update-metadata-v1.json` and return **`.updated`** (`previousVersion: beforeVersion`, `currentVersion: afterVersion`).
        - If exit code == `0` and `afterVersion == beforeVersion`: return **`.failed(.versionUnchanged)`** (an update operation is only prepared when `.updateAvailable` was proved, so remaining on `beforeVersion` after `uv tool upgrade` is truthfully reported as an unchanged-version failure).
        - If exit code != `0` and post-probe confirms the pre-upgrade version and ownership remain intact: return **`.failed(.commandFailedStateIntact)`**.
        - If post-probe fails ownership or executable verification: return **`.failed(.verificationLostAfterUpgrade)`**.

### R7 — `uv tool uninstall` Operation & Post-Uninstall Reconciliation (`Sources/AgentLensCore/Operations/UvToolUninstallOperation.swift`)

1. **Exact Command Vector:**
   - `[manager.canonicalTarget, "tool", "uninstall", "--no-progress", verified.packageName]`
   - Timeout: **`60.0s`** (`defaultExecutionTimeoutSeconds: 60.0`).
2. **3-Step Post-Uninstall Reconciliation & Shadowed Binary Disclosure:**
   - After `uv tool uninstall <package>` completes:
     1. Confirm `verified.installationRoot` (`<uv-tool-dir>/<tool-dir>`) no longer exists (`lstat` returns `ENOENT`).
     2. Confirm `verified.selection.entryPath` (`<uv-tool-bin-dir>/<executableName>`) no longer exists (or no longer resolves into `verified.installationRoot`).
     3. Re-run `ToolDetector` and `PathDiagnostics` for `definition`:
        - If both `<uv-tool-dir>/<tool-dir>` and its bin shim are gone and `ToolDetector` finds no remaining executable: invalidate `pypi-update-metadata-v1.json` and return **`.uninstalled`** (`remainedInstalled: false`).
        - If both `<uv-tool-dir>/<tool-dir>` and its bin shim are gone, **but** `ToolDetector` discovers another copy of `<executableName>` at a lower-precedence path (e.g., `/opt/homebrew/bin/aider` from Homebrew formula or a project venv): invalidate cache and return **`.uninstalledWithRemainingExecutable(remainingPath: ...)`** (matching M12/M13 multi-copy disclosure).
        - If `<uv-tool-dir>/<tool-dir>` or its shim still exists: return **`.failed(.installationStillPresent)`**.

### R8 — Mandatory Refusal & Informational Semantics (`pip` vs `uvTool`)

1. **`pip` Is Informational-Only by Construction:**
   - Tools verified under `.pip` NEVER expose Update or Uninstall action buttons in `ToolDetailView` and NEVER pass `WorkflowPresentation` mutation gating.
   - Instead, `ToolDetailView`, `OwnershipVerificationView`, `InstallationOwnershipRenderer`, and `agent-lensverify-ownership` / `agent-lensupdates` display rich read-only Python environment diagnostics:
     - **Environment Root:** `<env-root>` (e.g. `~/.local/pipx/venvs/aider-chat` or `/opt/homebrew/Cellar/python@3.15/...`)
     - **Environment Type:** `Virtual environment (venv)`, `pipx environment`, `Externally managed Python (PEP 668)`, or `Shared Python prefix`
     - **Python Interpreter:** `Python X.Y.Z`
     - **Safe Guidance Copy:** Context-specific read-only guidance (for `pipx`: *"Managed in a pipx virtual environment (read-only in Agent Lens)."* For PEP 668 / shared `pip`: *"Read-only in Agent Lens to protect externally managed or shared Python environments (PEP 668)."*).
2. **CLI Guardrails on `agent-lensupdate` and `agent-lensuninstall`:**
   - If the user invokes `agent-lensupdate <tool-id>` or `agent-lensuninstall <tool-id>` on a tool whose active ownership is `.pip`, the CLI exits with non-zero refusal status and clear diagnostic output explaining that `pip` environments are read-only in V1 and only verified `uv tool`, `Homebrew`, and `npm` global installs can be mutated.

### R9 — Capability Matrix Grammar Extension (`docs/capability-matrix.md` & `CapabilityMatrixTests.swift`)

1. **Catalogue Parity Contract (`Tests/AgentLensCoreTests/CapabilityMatrixTests.swift`):**
   - `CapabilityMatrixTests` enforces bidirectional parity between `DefaultDetectors.json` and `docs/capability-matrix.md`.
   - Extend `CapabilityMatrixTests` package and operation token parsers to recognize M14 tokens:
     - In the **Allowed Package Managers** column:
       - `` `uvTool:<pkg>` `` → `DeclaredPackage(manager: .uvTool, name: "<pkg>")`
       - `` `pip:<pkg>` `` → `DeclaredPackage(manager: .pip, name: "<pkg>")`
     - In the **Accepted Operations (`D-021`)** column:
       - `` `uvToolUpdate` `` → `AcceptedOperation.uvToolUpdate`
       - `` `uvToolUninstall` `` → `AcceptedOperation.uvToolUninstall`
   - Update `docs/capability-matrix.md` in the same phase (`M14-E`) as `DefaultDetectors.json` so `aider` and `hermes` rows list their `homebrewFormula`, `uvTool`, and `pip` declarations and `acceptedOperations` in lockstep.

### R10 — Promotions in `DefaultDetectors.json` (`aider` and `hermes`)

1. **`aider` (`Aider`):**
   - `extraSearchRoots`: update from `[]` to `["~/.local/bin"]` (so `uv tool install aider-chat` shims in `~/.local/bin/aider` are discovered deterministically even if the user's login shell has not added `~/.local/bin` to `PATH`).
   - `packages`:
     ```json
     [
       { "manager": "homebrewFormula", "name": "aider" },
       { "manager": "uvTool", "name": "aider-chat" },
       { "manager": "pip", "name": "aider-chat" }
     ]
     ```
   - `acceptedOperations`:
     ```json
     [
       "homebrewFormulaUpdate",
       "homebrewFormulaUninstall",
       "uvToolUpdate",
       "uvToolUninstall"
     ]
     ```
2. **`hermes` (`Hermes`):**
   - `extraSearchRoots`: remains `["~/.local/bin"]`.
   - `packages`:
     ```json
     [
       { "manager": "homebrewFormula", "name": "hermes-agent" },
       { "manager": "uvTool", "name": "hermes-agent" },
       { "manager": "pip", "name": "hermes-agent" }
     ]
     ```
   - `acceptedOperations`:
     ```json
     [
       "homebrewFormulaUpdate",
       "homebrewFormulaUninstall",
       "uvToolUpdate",
       "uvToolUninstall"
     ]
     ```
   - **Workstation Coexistence Note:** On the local workstation, `~/.local/bin/hermes` is a symlink to `~/.hermes/hermes-agent/.hermes/bin/hermes` (a standalone git checkout wrapper with no `uv-receipt.toml` and no `site-packages/*.dist-info` for `hermes-agent` owning the script). Under R1, it classifies as `"standalone"`, fails `uvTool` verification cleanly with `.managerRootMismatch` (or `.managerUnavailable` when `uv` is absent), and remains read-only standalone—proving that adding `uvTool:hermes-agent` and `pip:hermes-agent` never misclassifies a git-checkout install.
3. **Frozen Catalogue Anchor Updates (`BundledRegistryResourceTests.swift` & `DetectorRegistryTests.swift`):**
   - Update the expected `packages`, `acceptedOperations`, and `extraSearchRoots` assertions for `aider` and `hermes` in `BundledRegistryResourceTests` and `DetectorRegistryTests` in lockstep during `M14-E`, and add explicit negative assertions confirming `goose`, `dsh`, and `agy` declare zero `.uvTool` or `.pip` packages.

### R11 — CLI, AppSupport & SwiftUI Surface Parity

1. **CLI (`Sources/agent-lens/main.swift`):**
   - `verify-ownership` and `updates` render `.uvTool` (`"uv tool"`) and `.pip` (`"pip"`), including Python interpreter version, environment kind, and `UnknownReason.pythonInterpreterIncompatible`.
   - `update` and `uninstall` subcommands dispatch `.uvTool` verified tools to `UvToolUpdateOperation` / `UvToolUninstallOperation` (supporting `--dry-run` preview and `--confirm` execution) and refuse `.pip` with actionable diagnostic copy.
2. **AppSupport (`Sources/AgentLensAppSupport/WorkflowPresentation.swift`, `InventoryViewModel.swift`, `InventoryService.swift`):**
   - `WorkflowPresentation` enables Update and Uninstall workflow availability for `.uvTool` when `acceptedOperations` contains `.uvToolUpdate` / `.uvToolUninstall` and ownership is `.verified` with `manager == .uvTool`.
   - For `.pip` verified ownership, `WorkflowPresentation` returns read-only informational state with specific Python environment guidance (`pipx`, `venv`, `PEP 668 externally managed`, or `shared prefix`).
   - `InventoryService` wires `PyPIUpdateMetadataCache` into cache clearing and wires `UvToolUpdateOperation` / `UvToolUninstallOperation` into live operation execution.
3. **App (`Sources/AgentLensApp/ToolDetailView.swift`, `OwnershipVerificationView.swift`, `UvToolUpdateOperationView.swift`, `UvToolUninstallOperationView.swift`, `SettingsView.swift`, `MainWindow.swift`):**
   - Add `UvToolUpdateOperationView.swift` and `UvToolUninstallOperationView.swift` in `Sources/AgentLensApp/` following the 3-step preview → running → reconciled outcome sheet pattern from `HomebrewUpdateOperationView` / `HomebrewUninstallOperationView`.
   - Extend `OwnershipVerificationView.swift` to surface Python interpreter version and environment kind when `pythonEnvironment` is present on `VerifiedInstallation`.
   - Extend `SettingsView.swift` ("Clear Cached Metadata") so clearing update caches also clears `pypi-update-metadata-v1.json`.

### R12 — Disposable Acceptance Harness & Workstation `uv` Provisioning Strategy (`Tests/Fixtures/M14/`)

1. **Workstation `uv` Observation & Self-Contained Harness Design:**
   - Inspection during Milestone 1 confirmed that **`uv` is not permanently installed on the workstation's default `PATH`** (`/opt/homebrew/bin/uv` and `~/.local/bin/uv` do not exist; `/opt/homebrew/bin/python3` 3.15.2, `/opt/homebrew/bin/pip3` 26.2.2, and `/opt/homebrew/bin/pipx` 1.18.11 are installed).
   - Therefore, M14's disposable acceptance harness (`Tests/Fixtures/M14/python_acceptance.py`) MUST NOT depend on a pre-existing personal `uv` installation or mutate `~/.local/share/uv`, `~/.local/bin`, or `~/.cache/uv`.
2. **Two-Tier Real-Execution Harness (`Tests/Fixtures/M14/python_acceptance.py`):**
   - **Isolated Sandbox Root (`mkdtemp`):** Every acceptance run creates a temporary sandbox directory `SANDBOX` with isolated `UV_TOOL_DIR=$SANDBOX/uv-tools`, `UV_TOOL_BIN_DIR=$SANDBOX/uv-bin`, `UV_CACHE_DIR=$SANDBOX/uv-cache`, `PIP_CACHE_DIR=$SANDBOX/pip-cache`, and a local wheelhouse `$SANDBOX/wheelhouse`.
   - **Local Wheelhouse Generation (100% Offline, Deterministic Real Wheels):**
     - Using `/opt/homebrew/bin/python3` (or `/usr/bin/python3`), the harness builds real `.whl` archives in `$SANDBOX/wheelhouse` (`aider_chat-0.85.0-py3-none-any.whl` and `aider_chat-0.86.2-py3-none-any.whl`, plus an incompatible-Python wheel `aider_chat-0.87.0-py3-none-any.whl` with `Requires-Python: >=3.99` and a sibling `hermes_agent-0.19.0-py3-none-any.whl`) containing valid PEP 427 `.dist-info/{METADATA,WHEEL,RECORD,entry_points.txt}` and working console-script entry points (`aider --version`, `hermes --version`).
   - **`uv` Binary Resolution / Provisioning in `M14-A` & `M14-G`:**
     - The harness resolves `uv` in order: (1) `AGENT_LENS_UV_BIN` env override, (2) `which uv` on login shell `PATH`, (3) a hermetic disposable `uv` binary provisioned in `/tmp/agent-lens-m14-uv/bin/uv` (installed in a disposable venv during `M14-A` / `M14-G` without touching personal directories), or (4) on air-gapped CI runners without `uv`, a POSIX-compliant `uv` CLI fixture in `$SANDBOX/shim-bin/uv` backed by `python3 -m venv` + `pip install --no-index --find-links $SANDBOX/wheelhouse` that implements `uv tool dir`, `uv tool dir --bin`, `uv tool install`, `uv tool upgrade`, `uv tool uninstall`, and writes canonical `uv-receipt.toml` files.
     - **Mandatory Live-`uv` Proof Gate:** During `M14-A` (Feasibility Gate) and `M14-G` (Acceptance Gate) on this workstation, we will provision a real `uv` binary inside `/tmp/agent-lens-m14-uv` (never touching `/opt/homebrew` or `~/.local`) to verify real `uv` CLI flags, `uv-receipt.toml` formatting, exit codes, and full lifecycle upgrade/uninstall against the real `uv` binary, AND verify that the offline CI mode of `python_acceptance.py` passes identically when `uv` is absent on fresh runners.
3. **7 End-to-End Acceptance Scenarios (`python_acceptance.py` + `PythonAcceptanceHost.swift`):**
   1. **Disposable `uv tool` Upgrade Lifecycle:** Install `aider-chat` `0.85.0` into `$SANDBOX/uv-tools/aider-chat`, verify `.uvTool` ownership, probe latest `0.86.2`, execute `UvToolUpdateOperation` through `InventoryViewModel`, verify post-upgrade reconciliation advances installed version to `0.86.2` and invalidates `pypi-update-metadata-v1.json`.
   2. **Disposable `uv tool` Uninstall Lifecycle:** Execute `UvToolUninstallOperation` on `aider-chat` `0.86.2`, verify `<uv-tool-dir>/aider-chat` and `<uv-tool-bin-dir>/aider` are removed and post-uninstall scan reports not installed.
   3. **Cross-Environment Isolation Proof:** Install both `aider-chat` (`uv tool`) and `hermes-agent` (`uv tool`) plus a separate `pip` venv `<pip-venv>/bin/aider`; prove upgrading/uninstalling `aider-chat` in `uv-tools` leaves `hermes-agent` and `<pip-venv>` completely untouched (byte-identical mtimes/inodes) and refuses cross-targeted symlinks.
   4. **`uv` vs `pip` Ownership Distinction & Informational Enforcement:** Verify `<pip-venv>/bin/aider` proves `.pip` ownership (`environmentKind: .virtualEnvironment`), displays interpreter version and environment root, and refuses `update`/`uninstall` at both `WorkflowPresentation` and CLI levels.
   5. **Custom/Unavailable Index & Non-Registry Truthfulness:** Verify a `uv-receipt.toml` with custom `index-url = "https://corp.internal/simple"` or `direct_url.json` VCS source reports `.unknown(installed: ..., reason: .unsupportedRegistry)` without querying `pypi.org` and blocks `uv tool upgrade` with `.customIndexUnsupported`.
   6. **`requires_python` Interpreter Compatibility Proof:** Against a fixture PyPI payload where `0.86.2` requires `>=3.10` and `0.87.0` requires `>=3.99`, verify an environment running Python `3.12`/`3.15` recommends `0.86.2` when on `0.85.0`, and reports `.unknown(installed: ..., reason: .pythonInterpreterIncompatible)` when already on `0.86.2` and only `0.87.0` is newer.
   7. **100% Offline Local Inventory & Ownership Proof:** With network blocked / unreachable PyPI endpoint, verify `ToolDetector` and `InstallationOwnershipVerifier` discover and verify both `uvTool` and `pip` installations cleanly with zero network dependency.

### R13 — Phase Sequencing & Strict File Allow-Lists

M14 is divided into eight sequential phases (`M14-A` through `M14-H`) using verified repository paths:

| Phase | Scope | Allowed Files to Create / Modify |
| --- | --- | --- |
| **M14-A** | Live `uv` & `pip` Feasibility Probe Gate (read-only workstation + disposable `/tmp` scratch verification of `uv-receipt.toml`, `.dist-info`, `uv tool dir`, `uv tool upgrade/uninstall` flags) | `briefs/M14-A-feasibility.md` *(new, no product code changes)* |
| **M14-B** | Core Python Ownership (`PackageManager.uvTool`/`.pip`, `UvToolOwnershipProbe`, `PipOwnershipProbe`, `PythonEnvironmentMetadata`, routing in `InstallationOwnershipVerifier`, renderer & exhaustive switch updates) | `Sources/AgentLensCore/Detection/DetectorMetadata.swift`, `Sources/AgentLensCore/Detection/DetectorRegistry.swift`, `Sources/AgentLensCore/Ownership/InstallationOwnership.swift`, `Sources/AgentLensCore/Ownership/InstallationOwnershipVerifier.swift`, `Sources/AgentLensCore/Ownership/InstallationOwnershipRenderer.swift`, `Sources/AgentLensCore/Ownership/UvToolOwnershipProbe.swift` *(new)*, `Sources/AgentLensCore/Ownership/PipOwnershipProbe.swift` *(new)*, `Sources/AgentLensCore/Updates/UpdateProbeCoordinator.swift`, `Sources/agent-lens/main.swift`, `Sources/AgentLensAppSupport/WorkflowPresentation.swift`, `Sources/AgentLensAppSupport/InventoryViewModel.swift`, `Sources/AgentLensApp/OwnershipVerificationView.swift`, `Tests/AgentLensCoreTests/DetectorMetadataTests.swift`, `Tests/AgentLensCoreTests/InstallationOwnershipTests.swift`, `Tests/AgentLensCoreTests/UvToolOwnershipTests.swift` *(new)*, `Tests/AgentLensCoreTests/PipOwnershipTests.swift` *(new)*, `Tests/AgentLensAppSupportTests/OwnershipVerificationTests.swift` |
| **M14-C** | Core PEP 440 Engine, `requires_python` Specifier Set & PyPI Latest-Version Probe (`PEP440Version`, `PyPIUpdateProbe`, `PyPIUpdateMetadataCache`, `pypi-update-metadata-v1.json`, `UpdateProbeCoordinator` integration) | `Sources/AgentLensCore/Updates/VersionComparison.swift`, `Sources/AgentLensCore/Updates/VersionStatus.swift`, `Sources/AgentLensCore/Updates/PEP440Version.swift` *(new)*, `Sources/AgentLensCore/Updates/PyPIUpdateProbe.swift` *(new)*, `Sources/AgentLensCore/Updates/PyPIUpdateMetadataCache.swift` *(new)*, `Sources/AgentLensCore/Updates/UpdateProbeCoordinator.swift`, `Sources/AgentLensCore/Updates/UpdateScanRenderer.swift`, `Sources/AgentLensAppSupport/WorkflowPresentation.swift`, `Sources/AgentLensAppSupport/InventoryService.swift`, `Sources/AgentLensAppSupport/InventoryViewModel.swift`, `Sources/AgentLensApp/SettingsView.swift`, `Tests/AgentLensCoreTests/VersionComparisonTests.swift`, `Tests/AgentLensCoreTests/VersionStatusTests.swift`, `Tests/AgentLensCoreTests/PEP440VersionTests.swift` *(new)*, `Tests/AgentLensCoreTests/PyPIUpdateProbeTests.swift` *(new)*, `Tests/AgentLensCoreTests/PyPIUpdateMetadataCacheTests.swift` *(new)*, `Tests/AgentLensCoreTests/UpdateProbeCoordinatorTests.swift`, `Tests/AgentLensCoreTests/UpdateCLIIntegrationTests.swift` |
| **M14-D** | Core `uv tool` Update & Uninstall Operations (`AcceptedOperation.uvToolUpdate`/`.uvToolUninstall`, `UvToolOperationModels`, `UvToolUpdateOperation`, `UvToolUninstallOperation`, post-action reconciliation, CLI `update`/`uninstall` wiring) | `Sources/AgentLensCore/Detection/DetectorMetadata.swift`, `Sources/AgentLensCore/Operations/UvToolOperationModels.swift` *(new)*, `Sources/AgentLensCore/Operations/UvToolUpdateOperation.swift` *(new)*, `Sources/AgentLensCore/Operations/UvToolUninstallOperation.swift` *(new)*, `Sources/agent-lens/main.swift`, `Tests/AgentLensCoreTests/DetectorMetadataTests.swift`, `Tests/AgentLensCoreTests/UvToolOperationTests.swift` *(new)*, `Tests/AgentLensCoreTests/MutationAcceptanceGateTests.swift`, `Tests/AgentLensCoreTests/UpdateCLIIntegrationTests.swift` |
| **M14-E** | Registry Promotions (`aider`, `hermes`) & Capability Matrix Parity | `Sources/AgentLensCore/Detectors/DefaultDetectors.json`, `docs/capability-matrix.md`, `Tests/AgentLensCoreTests/CapabilityMatrixTests.swift`, `Tests/AgentLensCoreTests/BundledRegistryResourceTests.swift`, `Tests/AgentLensCoreTests/DetectorRegistryTests.swift` |
| **M14-F** | AppSupport & SwiftUI Workflow Parity (`UvToolUpdateOperationView`, `UvToolUninstallOperationView`, `ToolDetailView`, `OwnershipVerificationView`, `MainWindow`, `InventoryViewModel`, `InventoryService`, `WorkflowPresentation`) | `Sources/AgentLensAppSupport/WorkflowPresentation.swift`, `Sources/AgentLensAppSupport/InventoryViewModel.swift`, `Sources/AgentLensAppSupport/InventoryService.swift`, `Sources/AgentLensApp/UvToolUpdateOperationView.swift` *(new)*, `Sources/AgentLensApp/UvToolUninstallOperationView.swift` *(new)*, `Sources/AgentLensApp/ToolDetailView.swift`, `Sources/AgentLensApp/OwnershipVerificationView.swift`, `Sources/AgentLensApp/MainWindow.swift`, `Tests/AgentLensAppSupportTests/WorkflowPresentationTests.swift`, `Tests/AgentLensAppSupportTests/InventoryViewModelTests.swift`, `Tests/AgentLensAppSupportTests/InventoryServiceTests.swift` |
| **M14-G** | Disposable End-to-End Acceptance Harness & Packaging Parity | `Tests/Fixtures/M14/README.md` *(new)*, `Tests/Fixtures/M14/python_acceptance.py` *(new)*, `Tests/Fixtures/M14/PythonAcceptanceHost.swift` *(new)*, `Tests/Packaging/test_dev_app_bundle.py`, `walkthroughs/M14-python-acceptance.md` *(new)* |
| **M14-H** | CI Floors, Decision Records, Documentation Closeout & Milestone Merge Gate | `.github/workflows/ci.yml`, `DECISIONS.md`, `HANDOFF.md`, `ROADMAP.md`, `README.md`, `docs/CONTRIBUTING.md`, `docs/catalogue-identities.md` |

### R14 — Protected File Set (Must Remain Byte-Identical Throughout M14)

The following files enforce existing detection, npm, Homebrew formula, and Homebrew cask isolation and MUST NOT be modified during M14:

- `Sources/AgentLensCore/Detection/ToolDetector.swift` (heuristic `classifySource` and login-shell PATH snapshots remain frozen)
- `Sources/AgentLensCore/Ownership/NpmOwnershipProbe.swift`
- `Sources/AgentLensCore/Ownership/HomebrewOwnershipProbe.swift`
- `Sources/AgentLensCore/Ownership/HomebrewCaskOwnershipProbe.swift`
- `Sources/AgentLensCore/Updates/NpmUpdateProbe.swift`
- `Sources/AgentLensCore/Updates/NpmUpdateMetadataCache.swift`
- `Sources/AgentLensCore/Updates/HomebrewUpdateProbe.swift`
- `Sources/AgentLensCore/Updates/UpdateMetadataCache.swift`
- `Sources/AgentLensCore/Updates/HomebrewCaskUpdateProbe.swift`
- `Sources/AgentLensCore/Updates/CaskUpdateMetadataCache.swift`
- `Sources/AgentLensCore/Operations/OperationModels.swift` (`OperationExecutionGate.shared` remains frozen)
- `Sources/AgentLensCore/Operations/NpmUpdateOperation.swift`
- `Sources/AgentLensCore/Operations/NpmUninstallOperation.swift`
- `Sources/AgentLensCore/Operations/HomebrewOperationModels.swift`
- `Sources/AgentLensCore/Operations/HomebrewFormulaUpdateOperation.swift`
- `Sources/AgentLensCore/Operations/HomebrewFormulaUninstallOperation.swift`
- `Sources/AgentLensCore/Operations/HomebrewCaskUpdateOperation.swift`
- `Sources/AgentLensCore/Operations/HomebrewCaskUninstallOperation.swift`
- `Tests/Fixtures/M9/*`, `Tests/Fixtures/M11/*`, `Tests/Fixtures/M12/*`, `Tests/Fixtures/M13/*`

### R15 — Quantitative Timeout Budgets & Resource Caps

| Operation / Seam | Timeout Budget | Size / Entry Cap | File / Symlink Safety |
| --- | --- | --- | --- |
| `uv tool dir` / `uv tool dir --bin` probe | `5.0s` each | `64 KiB` stdout | Direct argv, `UV_NO_CACHE=1`, `UV_OFFLINE=1` |
| `uv-receipt.toml` & `direct_url.json` read | Synchronous local I/O | `64 KiB` | `O_RDONLY \| O_NOFOLLOW \| O_CLOEXEC`, regular file `fstat`, TOCTOU fingerprint |
| `pyvenv.cfg` read | Synchronous local I/O | `32 KiB` | `O_RDONLY \| O_NOFOLLOW \| O_CLOEXEC`, regular file `fstat` |
| `.dist-info/METADATA` read | Synchronous local I/O | `256 KiB` | `O_RDONLY \| O_NOFOLLOW \| O_CLOEXEC`, single-level `site-packages` glob (max 256 entries) |
| `.dist-info/RECORD` / `entry_points.txt` read | Synchronous local I/O | `1 MiB` / `64 KiB` | `O_RDONLY \| O_NOFOLLOW \| O_CLOEXEC` |
| Fallback `<venv>/bin/python3 --version` | `2.0s` | `4 KiB` stdout | Only run when `pyvenv.cfg` lacks version keys |
| PyPI JSON API fetch (`pypi.org/pypi/<pkg>/json`) | `8.0s` | `1 MiB` (`1,048,576` B) | HTTPS only, skipped for non-PyPI index provenance |
| `pypi-update-metadata-v1.json` cache | `6h` TTL (`21,600s`) | `1 MiB` (`1,048,576` B) | `O_NOFOLLOW` read, atomic temp-file rename write |
| `uv tool upgrade <pkg>` execution | `180.0s` | `256 KiB` output buffer | `OperationExecutionGate.shared`, `UV_NO_PROGRESS=1`, `UV_NO_MODIFY_PATH=1`, `UV_PYTHON_DOWNLOADS=never` |
| `uv tool uninstall <pkg>` execution | `60.0s` | `256 KiB` output buffer | `OperationExecutionGate.shared`, post-removal reconciliation |

### R16 — Verification & CI Gate Commands

Because this workstation uses Command Line Tools (Swift 6.4.2 without full Xcode), every Swift test command MUST pass the Testing macro plugin flag and serial swiftbuild flags:

```bash
# 1. Core test suite
swift test --build-system swiftbuild --no-parallel \
  -Xswiftc -load-plugin-library \
  -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib \
  --filter AgentLensCoreTests

# 2. AppSupport test suite
swift test --build-system swiftbuild --no-parallel \
  -Xswiftc -load-plugin-library \
  -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib \
  --filter AgentLensAppSupportTests

# 3. Frozen regression anchors
for anchor in \
  bundledDefaultDetectorsMatchFrozenCatalogue \
  unknownKeysAreRejectedAtRootDefinitionFixturePackageAndQueryLevels \
  makeDetectorUsesRegistryArgumentsInTheProductionPath \
  productionWiringUsesOnlyTheCoreLoginShellSeams; do
  swift test --build-system swiftbuild --no-parallel \
    -Xswiftc -load-plugin-library \
    -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib \
    --filter "$anchor"
done

# 4. Guard fixtures, packaging smoke tests & M14 disposable acceptance harness
python3 Tests/Fixtures/M9/run_guard_fixtures.py
python3 Tests/Packaging/test_dev_app_bundle.py
python3 Tests/Fixtures/M14/python_acceptance.py

# 5. Formatting & protected-file verification
git diff --check
git diff --name-only main -- \
  Sources/AgentLensCore/Detection/ToolDetector.swift \
  Sources/AgentLensCore/Ownership/NpmOwnershipProbe.swift \
  Sources/AgentLensCore/Ownership/HomebrewOwnershipProbe.swift \
  Sources/AgentLensCore/Ownership/HomebrewCaskOwnershipProbe.swift \
  Sources/AgentLensCore/Updates/NpmUpdateProbe.swift \
  Sources/AgentLensCore/Updates/NpmUpdateMetadataCache.swift \
  Sources/AgentLensCore/Updates/HomebrewUpdateProbe.swift \
  Sources/AgentLensCore/Updates/UpdateMetadataCache.swift \
  Sources/AgentLensCore/Updates/HomebrewCaskUpdateProbe.swift \
  Sources/AgentLensCore/Updates/CaskUpdateMetadataCache.swift \
  Sources/AgentLensCore/Operations/OperationModels.swift \
  Sources/AgentLensCore/Operations/NpmUpdateOperation.swift \
  Sources/AgentLensCore/Operations/NpmUninstallOperation.swift \
  Sources/AgentLensCore/Operations/HomebrewOperationModels.swift \
  Sources/AgentLensCore/Operations/HomebrewFormulaUpdateOperation.swift \
  Sources/AgentLensCore/Operations/HomebrewFormulaUninstallOperation.swift \
  Sources/AgentLensCore/Operations/HomebrewCaskUpdateOperation.swift \
  Sources/AgentLensCore/Operations/HomebrewCaskUninstallOperation.swift
```

---

## 3. Detailed Phase Breakdown (`M14-A` through `M14-H`)

### Phase M14-A — Live `uv` & `pip` Feasibility Probe Gate
- **Goal:** Verify real `uv` CLI output formats (`uv tool dir`, `uv tool dir --bin`, `uv-receipt.toml` schema, `uv tool upgrade` / `uv tool uninstall` flags and exit codes) and local `pip`/`pipx` `.dist-info` + `pyvenv.cfg` layouts inside an isolated `/tmp/agent-lens-m14-probe` scratch directory without modifying any personal environment.
- **Deliverable:** `briefs/M14-A-feasibility.md` recording exact observed `uv-receipt.toml` TOML structure, `pyvenv.cfg` keys, `.dist-info/{METADATA,RECORD,INSTALLER,entry_points.txt,direct_url.json}` layouts, and exit code behavior.
- **Exit Gate:** `git status --short` shows only `briefs/M14-A-feasibility.md`; `/tmp/agent-lens-m14-probe` cleaned up or isolated.

### Phase M14-B — Core Python Ownership (`uvTool` & `pip`)
- **Goal:** Add `.uvTool` and `.pip` to `PackageManager`, implement `UvToolOwnershipProbe` and `PipOwnershipProbe` with `PythonEnvironmentMetadata`, wire deterministic routing in `InstallationOwnershipVerifier`, and update exhaustive switches in `UpdateProbeCoordinator`, CLI, AppSupport, and App views so the entire project compiles cleanly and passes all unit tests.
- **Key Tests Added (`UvToolOwnershipTests.swift`, `PipOwnershipTests.swift`):**
  - Verified `uv` tool layout with valid `uv-receipt.toml`, `pyvenv.cfg`, `.dist-info/METADATA`, and `RECORD` / `entry_points.txt`.
  - Refusal when `<uv-tool-bin-dir>/<exe>` symlink points to a different package's venv (cross-environment symlink hijack defense).
  - Refusal when `uv-receipt.toml` is a symlink (`O_NOFOLLOW`), oversized (> 64 KiB), missing, or declares a mismatched primary requirement.
  - Verified `pip` ownership across `.virtualEnvironment`, `.pipxEnvironment`, `.externallyManagedSystem` (PEP 668 `EXTERNALLY-MANAGED`), and `.sharedPrefix` even when `uv` is not installed on `PATH`, plus Cellar Python (`python@3.15`) fallthrough when a detector declares both `homebrewFormula` and `pip`.
  - Standalone git checkout wrapper (`~/.hermes/hermes-agent/.hermes/bin/hermes`) remains unverified and is never misclassified as `uvTool` or `pip`.

### Phase M14-C — Core PEP 440 Engine, `requires_python` & PyPI Update Probe
- **Goal:** Implement `PEP440Version` and `PEP440SpecifierSet` in `PEP440Version.swift`, extend `VersionScheme` with `.pep440` and `UnknownReason` with `.pythonInterpreterIncompatible`, implement `PyPIUpdateProbe` and `PyPIUpdateMetadataCache` (`pypi-update-metadata-v1.json`), and wire `.uvTool` and `.pip` into `UpdateProbeCoordinator`.
- **Key Tests Added (`PEP440VersionTests.swift`, `PyPIUpdateProbeTests.swift`, `PyPIUpdateMetadataCacheTests.swift`):**
  - PEP 440 ordering across epochs (`1!0.1 > 9.9.9`), zero-padded release segments (`1.2 == 1.2.0`), pre-releases (`0.86.2a1 < 0.86.2b1 < 0.86.2rc1 < 0.86.2`), alternative pre/post spellings (`1.0-1 == 1.0.post1`, `1.0c1 == 1.0rc1`), dev releases (`0.86.2.dev1 < 0.86.2a1` and `0.86.2 < 0.86.2.post1.dev1 < 0.86.2.post1`), and local labels (`+local`).
  - `PEP440SpecifierSet` evaluation for `~=`, `==` (with `.*`), `!=` (with `.*`), `<=`, `>=`, `<`, `>`, `===`, parenthesized expressions, and compound comma-separated clauses.
  - PyPI candidate filtering: yanked release rejection, prerelease filtering, `requires_python` compatibility filtering (selecting highest compatible release when available, or reporting `.unknown(installed: ..., reason: .pythonInterpreterIncompatible)` when all newer releases require a newer Python interpreter), custom index / VCS provenance refusal (`.unsupportedRegistry`), and 6-hour cache TTL + interpreter-keyed cache isolation.

### Phase M14-D — Core `uv tool` Update & Uninstall Operations
- **Goal:** Add `.uvToolUpdate` and `.uvToolUninstall` to `AcceptedOperation` (while keeping `pip` absent from `AcceptedOperation`), implement `UvToolOperationModels.swift`, `UvToolUpdateOperation.swift`, and `UvToolUninstallOperation.swift` serialized through `OperationExecutionGate.shared`, and wire CLI `agent-lensupdate` and `agent-lensuninstall` with `--dry-run` and `--confirm`.
- **Key Tests Added (`UvToolOperationTests.swift`, `MutationAcceptanceGateTests.swift`):**
  - Pre-flight refusal when ownership is unverified, when `acceptedOperations` lacks `uvToolUpdate`/`uvToolUninstall`, when `uv-receipt.toml` contains an exact version pin (`==`), or when `uv-receipt.toml` specifies a custom `--index-url` / VCS source.
  - TOCTOU refusal (`.preconditionChanged`) when `uv-receipt.toml`, `METADATA`, or the executable fingerprint changes between `prepare` and `execute`.
  - Post-upgrade reconciliation: `.updated` when version advances, `.failed(.versionUnchanged)` when exit 0 fails to advance an outdated version, `.failed(.commandFailedStateIntact)` when exit != 0 leaves prior version intact, and `.failed(.verificationLostAfterUpgrade)` when environment is corrupted.
  - Post-uninstall reconciliation: `.uninstalled`, `.uninstalledWithRemainingExecutable` when a shadowed copy remains on `PATH`, and `.failed(.installationStillPresent)` when `<uv-tool-dir>/<pkg>` survives exit 0.
  - Explicit CLI policy refusal when `update` or `uninstall` is invoked on a `.pip`-owned tool.

### Phase M14-E — Registry Promotions (`aider`, `hermes`) & Capability Matrix Parity
- **Goal:** Promote `aider` (`uvTool:aider-chat`, `pip:aider-chat`, `extraSearchRoots: ["~/.local/bin"]`, `uvToolUpdate`, `uvToolUninstall`) and `hermes` (`uvTool:hermes-agent`, `pip:hermes-agent`, `uvToolUpdate`, `uvToolUninstall`) in `DefaultDetectors.json` and `docs/capability-matrix.md`, and update `CapabilityMatrixTests`, `BundledRegistryResourceTests`, and `DetectorRegistryTests`.
- **Key Verifications:**
  - All 4 frozen anchors pass.
  - Do-Not-Declare PyPI assertions added to `BundledRegistryResourceTests` verifying that `goose`, `dsh`, and `agy` declare zero `.uvTool` or `.pip` entries.

### Phase M14-F — AppSupport & SwiftUI Workflow Parity
- **Goal:** Wire `UvToolUpdateOperationView` and `UvToolUninstallOperationView` into `ToolDetailView`, `MainWindow`, and `InventoryViewModel`, update `WorkflowPresentation` to enable `uv tool` mutations and render context-specific read-only guidance for `.pip` environment kinds, and update `OwnershipVerificationView` and `SettingsView`.
- **Key Tests Added (`WorkflowPresentationTests.swift`, `InventoryViewModelTests.swift`, `InventoryServiceTests.swift`):**
  - Action availability and read-only badge/guidance copy for `.uvTool` vs `.pip` (`.virtualEnvironment`, `.pipxEnvironment`, `.externallyManagedSystem`, `.sharedPrefix`).
  - Full ViewModel state transitions for `uvTool` update and uninstall preview → execute → reconcile → inventory refresh + PyPI cache invalidation.

### Phase M14-G — Disposable Acceptance Harness & Packaging Parity
- **Goal:** Author `Tests/Fixtures/M14/python_acceptance.py`, `Tests/Fixtures/M14/PythonAcceptanceHost.swift`, `Tests/Fixtures/M14/README.md`, and `walkthroughs/M14-python-acceptance.md`, and extend `Tests/Packaging/test_dev_app_bundle.py` to assert bundled `DefaultDetectors.json` carries the M14 `aider` and `hermes` Python promotions.
- **Exit Gate:** All 7 end-to-end scenarios in `python_acceptance.py` pass with zero touches to real `$HOME/.local` or `/opt/homebrew`.

### Phase M14-H — CI Floors, Decision Records & Documentation Closeout
- **Goal:** Ratchet test count floors in `.github/workflows/ci.yml` to the new M14 baseline, add `python_acceptance.py` to CI, record M14 architectural decisions in `DECISIONS.md`, and update `HANDOFF.md`, `ROADMAP.md`, `README.md`, `docs/CONTRIBUTING.md`, and `docs/catalogue-identities.md`.

---

## 4. Owner Decisions (`OD-M14-1` through `OD-M14-3`)

1. **`OD-M14-1` — Two Distinct Python `PackageManager` Cases (`.uvTool` and `.pip`) vs a Single `.python` Case:**
   - **Recommended Ruling:** Use two distinct `PackageManager` cases: `.uvTool` (`"uvTool"`, label `"uv tool"`) and `.pip` (`"pip"`, label `"pip"`).
   - **Rationale:** `ROADMAP.md` §4 requires that "`uv`/`pip` ownership is distinguished" and "`uv` Update/Uninstall through the existing workflow; keep system/shared/ambiguous `pip` environments informational." Encoding `.uvTool` and `.pip` as distinct `PackageManager` cases makes the D-021 mutation boundary structural (`AcceptedOperation` has `uvToolUpdate`/`uvToolUninstall` and zero `pip*` cases) rather than relying on fragile runtime boolean flags.
2. **`OD-M14-2` — Adding `"~/.local/bin"` to `aider.extraSearchRoots` in `DefaultDetectors.json`:**
   - **Recommended Ruling:** Add `"~/.local/bin"` to `aider`'s `extraSearchRoots` (matching `hermes`, `claude`, `kiro-cli`, `omp`, `dsh`, and `qodercli`).
   - **Rationale:** `uv tool install` places entry-point symlinks in `uv tool dir --bin`, which defaults to `~/.local/bin` under the XDG Base Directory specification. On macOS machines where the user installed `uv` or `pipx` without adding `~/.local/bin` to `/etc/paths` or `~/.zprofile`, `aider` installed via `uv tool install aider-chat` would be missed by `ToolDetector` unless `"~/.local/bin"` is in `extraSearchRoots`.
3. **`OD-M14-3` — Handling `--with` Extra Requirements in `uv-receipt.toml` During `uv tool upgrade`:**
   - **Recommended Ruling:** Allow `uv tool upgrade <package>` when `uv-receipt.toml` includes standard PyPI `--with` extras (disclosing them in the preview sheet), because `uv tool upgrade` reads `uv-receipt.toml` natively and preserves `[tool].requirements` extras; refuse only when any requirement in `uv-receipt.toml` uses an exact version pin (`==` / `===`), a custom `--index-url` / `--find-links`, or a non-registry VCS/path/URL source.
   - **Rationale:** Users commonly install Python tools with plugins (e.g. `uv tool install aider-chat --with playwright`); blocking upgrades on benign PyPI `--with` extras would needlessly degrade UX when `uv` natively preserves them.

---

## 5. Ranked Technical Risks & Mitigations

1. **Risk 1 (High) — Multi-Manager Ownership Collision (`homebrewFormula` vs `uvTool` vs `pip`):**
   - *Failure mode:* `aider` and `hermes` declare `homebrewFormula`, `uvTool`, and `pip`. A naïve loop over `packages` could test `uvTool` on a Homebrew formula binary, fail with `.managerUnavailable` on a `pip` virtualenv when `uv` is not installed, or fail with `.formulaRecordMismatch` on a `pip install --break-system-packages` binary inside `/opt/homebrew/Cellar/python@3.15/...`.
   - *Mitigation:* R1's Anchored Environment Classifier checks the Cellar rack name (routing `python@*` Cellar paths to `verifyPip` when `pip` is declared) and inspects `<env-root>/uv-receipt.toml` via local `lstat` before requiring `uv` on `PATH`, dispatching cleanly between `verifyUvTool` and `verifyPip`.
2. **Risk 2 (High) — PEP 440 vs Semver Divergence & `requires_python` Breakage:**
   - *Failure mode:* Python packages frequently publish 2-segment versions (`0.86`), post-releases (`0.86.2.post1`), or drop older Python minor versions in newer releases (`Requires-Python: >=3.12`). Reusing `SemanticVersion` would fail to parse valid PyPI releases, and ignoring `requires_python` would recommend upgrades that fail or break the tool's virtualenv.
   - *Mitigation:* R2 and R3 implement a dedicated `PEP440Version` + `PEP440SpecifierSet` engine and filter PyPI releases against the environment's observed Python interpreter version, surfacing `.unknown(installed: ..., reason: .pythonInterpreterIncompatible)` when newer releases require a newer Python runtime.
3. **Risk 3 (Medium) — Workstation & CI Runner `uv` Availability:**
   - *Failure mode:* `uv` is not pre-installed on the developer workstation's default `PATH` or on standard GitHub Actions macOS runners.
   - *Mitigation:* R12 designs `Tests/Fixtures/M14/python_acceptance.py` with a local offline wheelhouse and dual-mode `uv` resolution (verifying against a real disposable `uv` binary in `/tmp` during `M14-A`/`M14-G` while remaining self-contained on clean CI runners without touching `$HOME`).
4. **Risk 4 (Medium) — Exhaustive Enum Switch & Error-String Test Pin Cascades:**
   - *Failure mode:* Adding `.uvTool` and `.pip` to `PackageManager`, `.pep440` to `VersionScheme`, `.pythonInterpreterIncompatible` to `UnknownReason`, and `.uvToolUpdate`/`.uvToolUninstall` to `AcceptedOperation` affects compiler exhaustiveness and error-string pins in `DetectorMetadataTests.swift` and `DetectorRegistry.swift`.
   - *Mitigation:* R1, R4, and R13 explicitly account for every error string pin and open the exact downstream files in `M14-B`, `M14-C`, and `M14-D` so every phase compiles and passes tests at its own boundary.
