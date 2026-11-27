# M14 Master Plan — Python Tool Support (`uv` Management & `pip` Diagnostics)

- **Date:** 2026-11-27
- **Branch:** `milestone/m14-python` (created from `main` at `882afd3517cda6f10c901dd973dc8f5e4083b2c2`)
- **Planning Mode:** Solo Owner-Directed Planning + Two-Pass Adversarial Self-Review (`briefs/M14-planning/self-review.md`)
- **Status:** M14-B ownership contract frozen from the M14-A live probe and independent replay. Dispatch B only after the Phase A evidence supplement is committed and both owner-designated reviewers clear that gate. This freeze does not authorize C or later phases.

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
   - **`pip` (`pip`)** supports verified read-only diagnostics (environment root, site-packages root, installed package version, interpreter version where established, installer provenance, and environment kind). PyPI latest checks require eligible index evidence (R3). No `pip` mutation vocabulary or affordance exists. The shipping CLI remains read-only (D-022).

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
   - A typical venv console script is a regular file beneath its venv's `bin` directory. A symlink into that directory resolves to the script, not the script's shebang interpreter. The heuristic still describes the *canonical script path*, not the manager. A canonical path in a Python runtime keg can still be `"brew"`; resolve that case through the verified layout in R1.3, not a source-label change.
3. **Deterministic Multi-Manager Routing in `Sources/AgentLensCore/Ownership/InstallationOwnershipVerifier.swift`:**
   - For a detected tool with `definition.packages`:
     1. **`source == "npm"` and declares `.npm`:** route to `verifyNpm`.
     2. **`source == "brew"` and declares `.homebrewFormula`:**
        - Switch to pip only for an anchored, supported system layout (R1.6) whose runtime rack is distinct from every declared formula. The Homebrew framework-to-site-packages symlink observed in A is not a supported pip ownership route; leave it on the existing Homebrew path or report unsupported, as applicable. A failed formula proof is not pip proof.
        - Otherwise, route to `verifyHomebrew`.
     3. **Otherwise (including `source == "standalone"` or `source == "brew"` without `.homebrewFormula`):**
        - If the detector declares `.homebrewCask`, run `verifyHomebrewCask`. If `.verified` (or if the detector declares neither `.uvTool` nor `.pip`), return that outcome. If `verifyHomebrewCask` returns `.unknown(.managerRootMismatch)` or `.unknown(.unsupportedInstallationLayout)` because the selected binary is outside Caskroom **and** the detector also declares `.uvTool` or `.pip`, continue to Python ownership verification.
        - If the detector declares `.uvTool` or `.pip`, run the **Anchored Python Environment Classifier** using pure local filesystem `lstat` (before requiring `uv` to exist on `PATH`, so a machine without `uv` installed can still verify `.pip` virtualenvs):
          - Derive candidate `<env-root>` as the parent directory of `<bin-dir>` where `selection.canonicalTarget` resides (`<env-root>/bin/<executableName>`).
          - **Case A (`uv` evidence):** A receipt of any filesystem type, or the canonical target being contained in an observed `uv tool dir` environment, reserves the selection for `uv`. Failed or indeterminate receipt inspection is not absence; missing, tampered or unsupported receipts in known uv environments never fall through to pip. Being in `uv tool dir --bin` alone is **not** evidence: uv and pipx can share `~/.local/bin`. Require a declared `.uvTool` candidate to verify. Resolve the roots at most once per invocation and reuse that snapshot; use component containment, not string prefixes.
          - **Case B (`pip` evidence):** With proven receipt absence and no known uv root match, route to `verifyPip` only for a declared `.pip` candidate in an evidenced layout. Prove ownership independently through installer and executable records; a skipped/unavailable uv query does not itself recategorize an environment. No uv installation is required for positive pip proof.
          - **Case C (no Python evidence):** Retain the existing no-declaration/unsupported-source result as applicable. Do not run `uv` solely because a standalone executable has a Python package candidate. For tools with no Python declarations, preserve all existing routing and refusal reasons.
4. **Python Environment Metadata on `VerifiedInstallation` (`Sources/AgentLensCore/Ownership/InstallationOwnership.swift`):**
   - Add `PythonEnvironmentKind` (`.uvTool`, `.virtualEnvironment`, `.pipxEnvironment`, `.externallyManagedSystem`, `.sharedPrefix`), `PythonIndexProvenance` (`.publicPyPI`, `.customIndex`, `.nonRegistrySource`, `.unknown`), and `PythonEnvironmentMetadata` (installed version, observed interpreter version if available, `Requires-Python`, environment kind, installer, index provenance, and redacted receipt constraint/extra summaries where applicable). Keep internal evidence used to revalidate operations separate from display strings. `.publicPyPI` requires affirmative source evidence; never expose raw credential-bearing URLs, config, or receipts in app/CLI output.
   - Add `public let pythonEnvironment: PythonEnvironmentMetadata?` to `VerifiedInstallation` with a default value of `nil` in `VerifiedInstallation.init(...)` so all existing M9–M13 call sites and tests compile without modification.
5. **6-Step `uvTool` Ownership Proof (`Sources/AgentLensCore/Ownership/UvToolOwnershipProbe.swift`):**
   1. **Manager Resolution & Pre-Query Snapshot:** Resolve `uv` from `ShellEnvironment.pathEntries` using `FileIdentityObserver.observeExecutable` (capturing `managerEntryPath`, `managerTarget`, `managerFingerprint`). If `uv` is not found on `PATH`, return `.unknown(.managerUnavailable)`.
   2. **Roots Query (`uv tool dir` and `uv tool dir --bin`):**
      - Run `[manager.canonicalTarget, "tool", "dir"]` and `[manager.canonicalTarget, "tool", "dir", "--bin"]` once via `UpdateCommandRunner` with timeout `5.0s` each and `UV_NO_CACHE=1`, `UV_NO_PROGRESS=1`, `UV_OFFLINE=1`. Query using the same root-selection inputs as mutation; do not silently default away an explicit custom root.
      - Reject malformed, truncated, multi-line or nonabsolute paths; canonicalize and bind both directory identities, and re-observe `uv` and the selected entry/target around queries.
   3. **Selected Entry & Canonical Target Containment Proof:**
      - `selection.canonicalTarget` MUST decompose as `<uv-tool-dir>/<tool-dir>/bin/<executableName>` where `<tool-dir>` matches a declared `.uvTool` package name under PEP 503 normalization and `<executableName>` matches `definition.executableName`. (If outside `<uv-tool-dir>`, return `.unknown(.managerRootMismatch)`.)
      - Bind the exact manager-owned shim `<uv-tool-bin-dir>/<executableName>` and prove it resolves to the canonical script with the same executable fingerprint. A different selected entry pointing to the same target is not that shim; it cannot authorize mutation.
   4. **Anchored `uv-receipt.toml` Proof (Bounded `O_NOFOLLOW` Regular-File Read, Cap 64 KiB):**
      - Traverse from already verified directories with descriptor-relative, no-symlink opens for directory components. Bound receipt reads to 64 KiB and reject symlinks, non-regular nodes and ambiguous/malformed TOML. R15 applies to every proof file, not just the receipt.
      - Support the captured uv 0.13.10 receipt shape: `[tool]` with `requirements` (first is primary), `entrypoints` (matching `name`, absolute `install-path` and normalized `from` required), and the observed optional settings. Unobserved/legacy receipts missing `from` remain unsupported. Use a bounded, in-process Swift parser for the observed TOML subset, with strict syntax and duplicate-key rejection: basic quoted strings and escaping, scalars, inline tables, arrays (including multiline arrays of inline tables), and `[tool]` / `[tool.options]`. No regex extraction from malformed TOML, external dependency, Python or shell subprocess. Reject unproved shape or semantics rather than deriving ownership from an unparsed receipt.
   5. **Anchored `.dist-info` & `pyvenv.cfg` Proof (Zero Recursive Crawling):**
      - Read `<env-root>/pyvenv.cfg` via bounded `O_NOFOLLOW` regular-file read (cap 32 KiB), bind `<env-root>/bin/python*` to the selected script, and report `version_info` (e.g., `3.15.2`). The receipt's install-time `python` field may be stale after an upgrade; never use it as current interpreter proof.
      - Inspect only the evidenced venv's `lib/pythonX.Y/site-packages` and find a unique matching `.dist-info` within the entry cap. Bind its identity, require `INSTALLER=uv`, and read bounded `METADATA` to obtain the normalized `Name:`, `Version:` and optional `Requires-Python:`.
      - Require a parsed `RECORD` CSV entry that resolves from site-packages to the **exact** canonical selected script with the matching identity. For the observed console-script layouts require the supplied SHA-256 and byte count to match that file. `entry_points.txt` is corroboration, never a substitute for installed-file ownership. Reject conflicting ownership, ambiguous layouts, escapes and evidence-budget overflow.
      - Read `direct_url.json` (if present, 64 KiB) as direct-source evidence. Absence proves neither the index nor PyPI (R3).
   6. **Post-Read Re-Observation & `VerifiedInstallation` Construction:**
      - Revalidate both roots, selected entry/target, managed shim, manager, interpreter binding and all positive/negative metadata used in the proof (including receipt, RECORD and source evidence). On drift or inability to re-observe, return unknown; do not publish a partially refreshed identity.
      - Return `.verified(VerifiedInstallation(manager: .uvTool, packageName: declared.name, managerEntryPath: manager.entryPath, managerTarget: manager.canonicalTarget, managerFingerprint: manager.fingerprint, managerRoot: uvToolDir, installationRoot: envRoot, selection: ..., pythonEnvironment: ...))`.
6. **5-Step `pip` Diagnostic Ownership Proof (`Sources/AgentLensCore/Ownership/PipOwnershipProbe.swift` — Read-Only):**
   1. **Bounded Supported Layouts:** Derive candidates only from the selected canonical script. Inspect `lib/pythonX.Y/site-packages` within the script's prefix for the observed venv/pipx and `pip --prefix` layouts. For the observed framework user scheme, require the script under the captured home’s `Library/Python/X.Y/bin` and inspect that versioned prefix's `lib/python/site-packages`. Require no uv receipt. Refuse all other splits, unobserved layouts, and symlinked proof ancestors. In particular the Homebrew framework symlink layout was inspected, not accepted as a complete ownership proof.
   2. **Interpreter Binding:** For venvs, bind the script's absolute interpreter to the environment's `bin/python*` and use the validated `pyvenv.cfg`. For the observed direct-shebang `pip --prefix` and framework `--user` shapes, bind the named live absolute interpreter (which is outside the installation prefix); report interpreter patch version unknown unless local evidence establishes it. Do not execute interpreter, pip, shebang wrapper or arbitrary tool to prove ownership. No PATH-wide interpreter search. Split installs prove who installed the script, not whether it presently imports and runs.
   3. **Environment Kind:** Classify pipx only from validated `pipx_metadata.json` 0.12 with `backend=pip`, main package identity, exposed app name and exact app path, consistent with the venv proof. Ordinary venvs are `.virtualEnvironment`. Split prefix/user installs are `.sharedPrefix`. Use `.externallyManagedSystem` only for an independently proved non-venv system prefix with the marker in that interpreter's matching stdlib ([PEP 668](https://packaging.python.org/en/latest/specifications/externally-managed-environments/)); a venv or shared/user prefix does not inherit the marker of its base interpreter.
   4. **Installer and File Proof:** Require `INSTALLER=pip` and exact path, SHA-256 and size verification via `RECORD` as in R1.5. Only for the validated pipx shape allow the measured rewrite: remove exactly terminal ASCII ` -E` from the first shebang line of the selected script and compare the resulting bytes against **both** RECORD SHA-256 and size. No other changed bytes, switches, decorators, or generic hash exceptions. Re-observe all consumed positive/negative paths and identities before returning. Missing/conflicting provenance does not prevent valid local ownership diagnostics.
   5. **Record Construction:**
      - Return `.verified(VerifiedInstallation(manager: .pip, packageName: declared.name, ..., managerRoot: sitePackagesPath, installationRoot: envRoot, selection: ..., pythonEnvironment: ...))`.

### R2 — PEP 440 Version Parsing, Ordering & `requires_python` Compatibility (`Sources/AgentLensCore/Updates/PEP440Version.swift`)

1. **`VersionScheme` Extension (`Sources/AgentLensCore/Updates/VersionStatus.swift` & `VersionComparison.swift`):**
   - Extend `VersionScheme` in `VersionStatus.swift` with `case pep440`.
   - Extend `VersionComparison.ordering(_:_:scheme:)` in `VersionComparison.swift` so `.pep440` delegates to `PEP440Version.compare(_:_:)`.
   - When a tool's verified ownership is `.uvTool` or `.pip`, `PyPIUpdateProbe` and `UpdateProbeCoordinator` evaluate versions using `VersionScheme.pep440` (rather than strict 3-component `.semanticVersion`, which rejects valid 2-segment Python versions like `0.86` and post/dev releases like `0.86.2.post1`).
2. **PEP 440 Parsing and Ordering:**
   - Implement the [version specifiers standard](https://packaging.python.org/en/latest/specifications/version-specifiers/) separately from Agent Lens's stable-channel policy. Compare numeric magnitudes without fixed-width overflow. Support case-insensitive spellings and the normative ordering below:
     - Optional leading `v`/`V` and ASCII whitespace trimming.
     - **Epoch:** `N!` (non-negative integer, defaults to `0`).
     - **Release segment:** 1 or more dot-separated non-negative integers (`[0-9]+(\.[0-9]+)*`). Trailing `.0` segments are stripped during comparison normalization so `1.2 == 1.2.0 == 1.2.0.0`.
     - **Pre-release segment:** `[._-]?(a|b|c|rc|alpha|beta|pre|preview)[._-]?[0-9]*` normalized to `.alpha(N)`, `.beta(N)`, `.rc(N)` (implicit number defaults to `0`; `c`, `pre`, `preview` normalize to `.rc`).
     - **Post-release segment:** `(?:[._-]?(?:post|rev|r)[._-]?[0-9]*)|(?:-[0-9]+)` normalized to `.post(N)` (implicit number defaults to `0`).
     - **Dev-release segment:** `[._-]?dev[._-]?[0-9]*` normalized to `.dev(N)` (implicit number defaults to `0`).
     - **Local version label:** Parse and order per PEP 440. Public PyPI candidates with local labels are excluded and installed local labels produce `.unsupportedVersion` at the probe boundary, rather than changing the comparator's rules.
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
   - **Interpreter evidence:** Use the bounded, identity-bound local metadata from R1 (`version_info` or `version` for supported virtualenvs; supported system evidence from M14-A). Do not execute an arbitrary interpreter to fill in missing data. Missing interpreter evidence cannot satisfy a nonempty requirement. Distinguish malformed specifiers (`.metadataInvalid` when decisive) from valid constraints that cannot be satisfied or evaluated. Verify the normative boundaries: wildcard release padding, `~=` arity, exclusive `<`/`>` prerelease/postrelease rules, and `===` arbitrary equality.

### R3 — PyPI Latest-Version Probe, Index Provenance & Separate Cache Document (`Sources/AgentLensCore/Updates/PyPIUpdateProbe.swift` & `PyPIUpdateMetadataCache.swift`)

1. **Additive `UnknownReason` Cases (`Sources/AgentLensCore/Updates/VersionStatus.swift`):**
   - Reuse existing `UnknownReason` cases wherever semantics match (`.networkUnavailable`, `.queryTimedOut`, `.rateLimited`, `.metadataInvalid`, `.unsupportedChannel`, `.unsupportedVersion`, `.newerThanKnownMetadata`, `.unsupportedRegistry`).
   - Add **one** Python-specific additive case to `UnknownReason`:
     - `case pythonInterpreterIncompatible` — when newer stable releases exist on PyPI, but every release newer than `installedVersion` fails `Requires-Python` for the tool environment's Python interpreter version (or requires an interpreter version that could not be verified).
   - Use `.unsupportedRegistry` for custom, direct, or unknown sources, with distinct read-only explanations; do not describe an unknown source as a known private index.
2. **Provenance Check Before Cache or Network:** Only affirmative supported PyPI evidence authorizes a PyPI check. For the uv receipt variant observed in A, require a sole supported public default index at `https://pypi.org/simple`, no conflicting index/source options, and no direct-source metadata. Do not interpret the receipt's `explicit = false` as absence of a recorded index. Direct/custom sources are distinct; an implicit index, duplicate/conflicting evidence or absence of `direct_url.json` cannot establish PyPI ([PEP 610](https://packaging.python.org/en/latest/specifications/direct-url/)). Ownership diagnostics still work. Before C dispatch, resolve with the owner whether to keep strict affirmative provenance (ordinary default uv installs remain unknown) or authorize a separately specified public-reference policy; do not expose a package name or start a network/cache check for unknown provenance in B.
3. **PyPI JSON Metadata Query & Candidate Selection:**
   - Initially use the documented [PyPI project JSON API](https://docs.pypi.org/api/json/) with the injectable `UpdateCommandRunner`, 8.0s timeout and 1 MiB bounded output. The `releases` key is deprecated: before C dispatch, document that the promoted projects fit the cap and that the required fields are supplied, or revise C to use the Simple Index API. On a missing/oversized response return typed unknown; never use `info.version` as a compatibility fallback. Restrict the request and redirects to the supported HTTPS endpoint policy; report only errors the process seam actually distinguishes.
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
          - Newer stable releases exist, but none is known to satisfy the bound interpreter's `Requires-Python` check. Do not infer that every incompatibility means “needs newer Python.”
        - Otherwise, compare `installedVersion` against `highestCompatibleStable` using `VersionStatus.evaluate(installed: ..., latest: ..., scheme: .pep440)`:
          - `installed < highestCompatibleStable` → `.updateAvailable(installed: ..., latest: ...)`
          - `installed == highestCompatibleStable` → `.upToDate(installed: ..., latest: ...)`
          - `installed > highestCompatibleStable` → `.unknown(installed: ..., reason: .newerThanKnownMetadata)`
4. **Separate Ecosystem Cache Document (`pypi-update-metadata-v1.json` in `PyPIUpdateMetadataCache.swift`):**
   - Stored in the cache directory alongside `npm-update-metadata-v1.json`, `homebrew-update-metadata-v1.json`, and `homebrew-cask-update-metadata-v1.json`.
   - Schema version `1`, TTL `6 hours` (`21,600s`), max size `1 MiB` (`1,048,576` bytes), `O_NOFOLLOW` regular-file read validation, atomic temp-file + rename persistence.
   - Key cache and in-flight requests by `(normalizedPackageName, interpreterMajorMinorPatch)` (explicit unknown interpreter key if needed). Store candidate facts, not a final installed-version-dependent status; re-evaluate each selected installation separately. As in existing update modes, local-only/offline never starts a PyPI request. A compatible candidate is release metadata, not a claim that uv's resolver, artifacts, constraints, or dependency graph will install it.

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
   - Use the same process-wide `OperationExecutionGate.shared` for prepare and execute; acquire/release separately for each call. Do not hold it across UI confirmation. Execute revalidates under the gate before launching; another operation may finish during preview.

### R5 — `uv` Environment Isolation, Pin/Constraint Guardrails & Execution Contract (`Sources/AgentLensCore/Operations/UvToolOperationModels.swift`)

1. **Bound Execution Context:** Use `OperationCommandRunner` / `ProcessOperationCommandRunner`, direct argv, and the existing process-group cancellation. Allowlist the subprocess environment. Set `UV_TOOL_DIR` and `UV_TOOL_BIN_DIR` to the canonical verified roots, bind both directory identities plus the exact package, managed shim, working directory and relevant receipt/settings, and revalidate under the gate just before spawn. Do not inherit registry, Python, root, config or loader overrides that can change the frozen command. Production must not expose fixture-only overrides.
2. **Configuration and Interpreter:** [uv tool configuration](https://docs.astral.sh/uv/concepts/configuration-files/) can come from user/system files or environment and can change resolution independently of the receipt. Prove the effective configuration for the supported case; refuse custom/ambiguous inputs rather than silently substituting a registry or interpreter. Disable ambient config after establishing parity; explicitly bind the supported index and selected environment's observed base interpreter in the update command. Prove these exact flags and their effect in M14-A with the [uv CLI contract](https://docs.astral.sh/uv/reference/cli/#uv-tool-upgrade); a Python preference is not an interpreter binding. Do not download Python or silently replace the interpreter.
3. **Prepare, Claim, Execute:** Check the matching D-021 grant before any observation, query, or process. Both operations perform fresh ownership proof and bind a single-use preparation to all relevant facts. Only Update requests fresh registry metadata. Execute claims once, repeats live preconditions, refuses drift (`.preconditionChanged`) and reconciles after any launch. Cancel, timeout, or nonzero exit cannot imply state intact.
4. **Update Constraints:** Refuse custom, direct or unknown effective sources, unsupported receipt settings/channel, and exact pins (`==` without wildcard, or `===`) on any receipt requirement. Respect non-exact constraints, including upper bounds and `==X.*`; an update preview requires a newer stable candidate satisfying the primary receipt specifier as well as `Requires-Python`. Standard extras can be reported and preserved only after a real-uv case proves preservation (OD-M14-3). An uninstall does not require registry access or an unpinned version; it does require exact ownership and accounting for every receipt-managed shim it may remove.

### R6 — `uv tool upgrade` Operation & Post-Upgrade Reconciliation (`Sources/AgentLensCore/Operations/UvToolUpdateOperation.swift`)

1. **Command contract:** One normalized package, no `--all`/force/reinstall, verified tool/bin roots, no ambient config, no Python download and no channel widening. The exact production argv (including explicit supported index and existing interpreter) is frozen from M14-A evidence, not inferred from flag names. Timeout: `180.0s`. Preview names target, environment, interpreter, receipt constraints, and effects; it does not promise a version.
2. **Reconciliation:** Re-detect and verify the same manager/roots/package, installed script and managed shims, interpreter, and receipt constraints. Success requires exit zero, intact identity/constraints and a strictly newer supported PEP 440 version. PEP 440 equality (not raw text equality) is unchanged, not success. Downgrade, incomparable version, changed-on-error, verification loss, cancellation and timeout must have truthful, non-success outcomes and re-observed state. Invalidate affected metadata whenever the launched action may have changed installation state; a failed command can mutate before exiting.

### R7 — `uv tool uninstall` Operation & Post-Uninstall Reconciliation (`Sources/AgentLensCore/Operations/UvToolUninstallOperation.swift`)

1. **Exact Command Vector:**
   - `[manager.canonicalTarget, "tool", "uninstall", "--no-progress", verified.packageName]`, with R5's verified roots and frozen execution context (confirm exact argv in M14-A).
   - Timeout: **`60.0s`** (`defaultExecutionTimeoutSeconds: 60.0`).
2. **3-Step Post-Uninstall Reconciliation & Shadowed Binary Disclosure:**
   - After `uv tool uninstall <package>` completes:
     1. Confirm `verified.installationRoot` (`<uv-tool-dir>/<tool-dir>`) no longer exists (`lstat` returns `ENOENT`).
     2. Confirm all receipt-managed shims are removed from the verified bin root. An entry replaced by another manager is not proof of clean removal; do not delete it. Preserve the result of the lock/identity checks and distinguish still-present, stale/unknown, and mixed state.
     3. Re-run `ToolDetector` and `PathDiagnostics`: with a clean exit and the proved target and shims absent, report `.uninstalled` or `.uninstalledWithRemainingExecutable(remainingPath: ...)` as observed. Nonzero/cancelled/timed-out exits with changed state and partial removals are not success or “state intact.” Report observed post-state and invalidate affected metadata as in R6.

### R8 — Mandatory Refusal & Informational Semantics (`pip` vs `uvTool`)

1. **`pip` Is Informational-Only by Construction:**
   - Tools verified under `.pip` NEVER expose Update or Uninstall action buttons in `ToolDetailView` and NEVER pass `WorkflowPresentation` mutation gating.
   - `ToolDetailView`, `OwnershipVerificationView`, and `InstallationOwnershipRenderer` display read-only Python diagnostics. CLI diagnostics are available through `agent-lens verify-installation <tool-id>` and the existing `agent-lens scan` update modes as applicable:
     - **Environment Root:** `<env-root>` (e.g. `~/.local/pipx/venvs/aider-chat` or `/opt/homebrew/Cellar/python@3.15/...`)
     - **Environment Type:** `Virtual environment (venv)`, `pipx environment`, `Externally managed Python (PEP 668)`, or `Shared Python prefix`
     - **Python Interpreter:** `Python X.Y.Z`
     - **Safe guidance:** Distinguish pipx, venv, externally managed system Python, and shared prefixes. A shared prefix is read-only without necessarily being PEP 668 managed.
2. **Shipping CLI remains read-only (D-022):** No new verbs, including `update`, `uninstall`, `updates`, or `verify-ownership`. Existing unknown-command refusal still applies, without scanning or invoking a manager.

### R9 — Capability Matrix Grammar Extension (`docs/capability-matrix.md` & `CapabilityMatrixTests.swift`)

1. **Catalogue Parity Contract (`Tests/AgentLensCoreTests/CapabilityMatrixTests.swift`):**
   - `CapabilityMatrixTests` enforces bidirectional parity between `DefaultDetectors.json` and `docs/capability-matrix.md`.
   - Extend package/operation parity for `uvTool:<pkg>`, `pip:<pkg>`, `uvToolUpdate`, and `uvToolUninstall`. Extend `latest-check` and mutation-cell rules, not just token parsing. Append `uvTool` and `pip` after the existing manager order for latest-check, and qualify both on verified supported PyPI provenance. Append `yes: uvTool (verified uv tool copies only)` after the existing mutation managers, only for the matching declared manager and accepted operation. Never emit a `pip` mutation cell. Assert rejection of unsupported or ungranted claims.
   - Change `docs/capability-matrix.md` in lockstep with `DefaultDetectors.json`: declarations and latest-check grammar in E, accepted per-tool grants and matching mutation cells at the H promotion gate (R10). Do not claim runtime support on paths that proof does not cover.

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
   - E preserves existing Homebrew operation grants. H may append `uvToolUpdate` and `uvToolUninstall` only with the owner-authorized, accepted per-tool evidence below.
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
   - E preserves existing Homebrew operation grants. H may append `uvToolUpdate` and `uvToolUninstall` only after a separate `hermes-agent` scenario is accepted; neither a sibling-isolation check nor `aider-chat` acceptance qualifies. The observed standalone Hermes wrapper remains unverified unless the exact selected executable has affirmative manager proof.
3. **Frozen Catalogue Anchor Updates (`BundledRegistryResourceTests.swift` & `DetectorRegistryTests.swift`):**
   - Update the `aider` and `hermes` catalogue assertions with each E/H change. Verify `goose`, `dsh`, and `agy` get no Python candidates. **D-021:** Collect independent evidence of Update and Uninstall for each proposed ID in G using test-only definitions. H can grant only operations the owner authorized and whose per-ID evidence the orchestrator accepted. No approval or incomplete evidence means no corresponding grant.

### R11 — CLI, AppSupport & SwiftUI Surface Parity

1. **Read-only CLI parity:** `verify-installation` renders verified Python ownership via `InstallationOwnershipRenderer`; `scan --check-updates`, `scan --refresh-updates`, and `scan --offline` use the usual coordinator and renderer. Preserve existing verbs, return codes, login-shell seams, and no-network local/offline behavior. Mutation is native AppSupport/App only.
2. **AppSupport (`Sources/AgentLensAppSupport/WorkflowPresentation.swift`, `InventoryViewModel.swift`, `InventoryService.swift`):**
   - `WorkflowPresentation` enables Update and Uninstall workflow availability for `.uvTool` when `acceptedOperations` contains `.uvToolUpdate` / `.uvToolUninstall` and ownership is `.verified` with `manager == .uvTool`.
   - For `.pip` verified ownership, `WorkflowPresentation` returns read-only informational state with specific Python environment guidance (`pipx`, `venv`, `PEP 668 externally managed`, or `shared prefix`).
   - `InventoryService` wires `PyPIUpdateMetadataCache` into cache clearing and wires `UvToolUpdateOperation` / `UvToolUninstallOperation` into live operation execution.
3. **App (`Sources/AgentLensApp/ToolDetailView.swift`, `OwnershipVerificationView.swift`, `UvToolUpdateOperationView.swift`, `UvToolUninstallOperationView.swift`, `SettingsView.swift`, `MainWindow.swift`):**
   - Use the native preview → running → reconciled outcome sheet pattern, preserving M12 preparation invalidation and C-1 confirmation/cancellation. Changing a selection, scan or eligibility must not retarget an open confirmation. Do not invalidate an already-running operation as if it never started.
   - Extend `OwnershipVerificationView.swift` to surface Python interpreter version and environment kind when `pythonEnvironment` is present on `VerifiedInstallation`.
   - Extend `SettingsView.swift` ("Clear Cached Metadata") so clearing update caches also clears `pypi-update-metadata-v1.json`.

### R12 — Disposable Acceptance Harness & Workstation `uv` Provisioning Strategy (`Tests/Fixtures/M14/`)

1. **Real-manager prerequisite:** Pin a real uv version and verify the binary's official artifact digest. Provision outside personal prefixes, into per-run `mkdtemp` (or pass a verified binary into that run). Provisioning and execution are separate: network access for fetching the verified artifact is not part of the offline fixture run. An unavailable real uv binary blocks the real-manager gate; a shim is never equivalent evidence.
2. **Isolated real execution:** Use scratch `HOME`, `XDG_*`, tool/bin/cache/temp roots and disposable Python environments. Build real wheels, with old/new `aider-chat` **and** `hermes-agent` versions, a `Requires-Python` rejection case, and independent sentinel installs. Use a local index with only the old wheel initially; install by unpinned name and expose the next release afterward. Do not edit receipts, install with `==old` for the success case, or treat a production-refused `--find-links` source as public PyPI. In A, prove a fixture route for real uv using isolated test configuration/transport; production keeps its public-index refusal policy. In G, any endpoint substitution must exist only at the host's injected test boundary; separately prove the unmodified production policy rejects that custom source. Do not count host-only evidence as a native UI journey.
3. **7 End-to-End Acceptance Scenarios (`python_acceptance.py` + `PythonAcceptanceHost.swift`):**
   1. **Disposable `uv tool` Upgrade Lifecycle:** Run separately for `aider-chat` and `hermes-agent` with test-only D-021 definitions. Prove ownership, preview, Cancel without mutation, re-prepare and Confirm through `InventoryViewModel`, verified version advance and proper cache invalidation. Capture real uv commands/results and environment/receipt checks.
   2. **Disposable `uv tool` Uninstall Lifecycle:** Run separately for each ID after update. Verify removal of the target and its managed shims, truthful post-rescan state, and shadowed-copy disclosure. Also observe a native-app Cancel/Confirm/rescan journey against a disposable validated install; distinguish the native receipt from the fixture-host receipt.
   3. **Cross-Environment Isolation Proof:** Install both `aider-chat` (`uv tool`) and `hermes-agent` (`uv tool`) plus a separate `pip` venv `<pip-venv>/bin/aider`; prove upgrading/uninstalling `aider-chat` in `uv-tools` leaves `hermes-agent` and `<pip-venv>` completely untouched (byte-identical mtimes/inodes) and refuses cross-targeted symlinks.
   4. **`uv` vs `pip` Ownership Distinction:** Prove native read-only pip/venv and pipx diagnostics with `uv` absent, no mutation availability or execution through AppSupport, and diagnostic CLI parity. The CLI rejects mutation verbs regardless of manager.
   5. **Index and Source Truthfulness:** Separately test a custom registry, a direct source, unknown provenance (including a named pip installation missing `direct_url.json`), an unavailable supported registry, and hostile ambient configuration. The first three cause no public request or cache lookup; an unavailable eligible registry stays unknown unless a valid cache fact is applicable. No custom/unknown uv update.
   6. **`requires_python` Interpreter Compatibility Proof:** Against a fixture PyPI payload where `0.86.2` requires `>=3.10` and `0.87.0` requires `>=3.99`, verify an environment running Python `3.12`/`3.15` recommends `0.86.2` when on `0.85.0`, and reports `.unknown(installed: ..., reason: .pythonInterpreterIncompatible)` when already on `0.86.2` and only `0.87.0` is newer.
   7. **100% Offline Local Inventory & Ownership Proof:** With network blocked / unreachable PyPI endpoint, verify `ToolDetector` and `InstallationOwnershipVerifier` discover and verify both `uvTool` and `pip` installations cleanly with zero network dependency.

### R13 — Phase Sequencing & Strict File Allow-Lists

M14 is divided into eight sequential phases (`M14-A` through `M14-H`) using verified repository paths:

| Phase | Scope | Allowed Files to Create / Modify |
| --- | --- | --- |
| **M14-A** | Live `uv`, `pip` and `pipx` feasibility; close missing evidence and independently accept the gate | `briefs/M14-A-feasibility.md` (append a dated supplement; retain the committed evidence and label its original verdict as superseded once independently decided) |
| **M14-B** | Core Python ownership and local diagnostics; no Python mutation or network probes | `Sources/AgentLensCore/Detection/DetectorMetadata.swift`, `Sources/AgentLensCore/Detection/DetectorRegistry.swift`, `Sources/AgentLensCore/Ownership/InstallationOwnership.swift`, `Sources/AgentLensCore/Ownership/InstallationOwnershipVerifier.swift`, `Sources/AgentLensCore/Ownership/InstallationOwnershipRenderer.swift`, `Sources/AgentLensCore/Ownership/UvToolOwnershipProbe.swift` *(new)*, `Sources/AgentLensCore/Ownership/PipOwnershipProbe.swift` *(new)*, `Sources/AgentLensCore/Updates/UpdateProbeCoordinator.swift`, `Sources/AgentLensAppSupport/WorkflowPresentation.swift`, `Sources/AgentLensAppSupport/InventoryViewModel.swift`, `Sources/AgentLensApp/OwnershipVerificationView.swift`, `Tests/AgentLensCoreTests/DetectorMetadataTests.swift`, `Tests/AgentLensCoreTests/InstallationOwnershipTests.swift`, `Tests/AgentLensCoreTests/UvToolOwnershipTests.swift` *(new)*, `Tests/AgentLensCoreTests/PipOwnershipTests.swift` *(new)*, `Tests/AgentLensAppSupportTests/OwnershipVerificationTests.swift` |
| **M14-C** | PEP 440, PyPI/update orchestration and cache, exhaustive reasons at the same build boundary | `Sources/AgentLensCore/Updates/VersionComparison.swift`, `Sources/AgentLensCore/Updates/VersionStatus.swift`, `Sources/AgentLensCore/Updates/PEP440Version.swift` *(new)*, `Sources/AgentLensCore/Updates/PyPIUpdateProbe.swift` *(new)*, `Sources/AgentLensCore/Updates/PyPIUpdateMetadataCache.swift` *(new)*, `Sources/AgentLensCore/Updates/UpdateProbeCoordinator.swift`, `Sources/AgentLensCore/Updates/UpdateScanRenderer.swift`, `Sources/AgentLensCore/Operations/NpmUpdateOperation.swift` *(exhaustive mapping of the new Python-only reason only; R14)*, `Sources/AgentLensAppSupport/WorkflowPresentation.swift`, `Sources/AgentLensAppSupport/InventoryService.swift`, `Sources/AgentLensAppSupport/InventoryViewModel.swift`, `Sources/AgentLensApp/ToolDetailView.swift`, `Sources/AgentLensApp/SettingsView.swift`, `Tests/AgentLensCoreTests/VersionComparisonTests.swift`, `Tests/AgentLensCoreTests/VersionStatusTests.swift`, `Tests/AgentLensCoreTests/PEP440VersionTests.swift` *(new)*, `Tests/AgentLensCoreTests/PyPIUpdateProbeTests.swift` *(new)*, `Tests/AgentLensCoreTests/PyPIUpdateMetadataCacheTests.swift` *(new)*, `Tests/AgentLensCoreTests/UpdateProbeCoordinatorTests.swift`, `Tests/AgentLensCoreTests/UpdateCLIIntegrationTests.swift` |
| **M14-D** | Core uv operations and D-021 vocabulary (no CLI mutation) | `Sources/AgentLensCore/Detection/DetectorMetadata.swift`, `Sources/AgentLensCore/Operations/UvToolOperationModels.swift` *(new)*, `Sources/AgentLensCore/Operations/UvToolUpdateOperation.swift` *(new)*, `Sources/AgentLensCore/Operations/UvToolUninstallOperation.swift` *(new)*, `Tests/AgentLensCoreTests/DetectorMetadataTests.swift`, `Tests/AgentLensCoreTests/DetectorRegistryTests.swift` *(AcceptedOperation error-vocabulary pin only)*, `Tests/AgentLensCoreTests/UvToolOperationTests.swift` *(new)*, `Tests/AgentLensCoreTests/MutationAcceptanceGateTests.swift` |
| **M14-E** | Read-only Python catalogue declarations and matrix parity; no new mutation grants | `Sources/AgentLensCore/Detectors/DefaultDetectors.json`, `docs/capability-matrix.md`, `Tests/AgentLensCoreTests/CapabilityMatrixTests.swift`, `Tests/AgentLensCoreTests/BundledRegistryResourceTests.swift`, `Tests/AgentLensCoreTests/DetectorRegistryTests.swift`, `Tests/AgentLensCoreTests/UpdateCLIIntegrationTests.swift` *(only directly affected detection/diagnostic expectations)* |
| **M14-F** | AppSupport and native workflow parity | `Sources/AgentLensAppSupport/WorkflowPresentation.swift`, `Sources/AgentLensAppSupport/InventoryViewModel.swift`, `Sources/AgentLensAppSupport/InventoryService.swift`, `Sources/AgentLensApp/UvToolUpdateOperationView.swift` *(new)*, `Sources/AgentLensApp/UvToolUninstallOperationView.swift` *(new)*, `Sources/AgentLensApp/ToolDetailView.swift`, `Sources/AgentLensApp/OwnershipVerificationView.swift`, `Sources/AgentLensApp/MainWindow.swift`, `Tests/AgentLensAppSupportTests/WorkflowPresentationTests.swift`, `Tests/AgentLensAppSupportTests/InventoryViewModelTests.swift`, `Tests/AgentLensAppSupportTests/InventoryServiceTests.swift` |
| **M14-G** | Disposable End-to-End Acceptance Harness & Packaging Parity | `Tests/Fixtures/M14/README.md` *(new)*, `Tests/Fixtures/M14/python_acceptance.py` *(new)*, `Tests/Fixtures/M14/PythonAcceptanceHost.swift` *(new)*, `Tests/Packaging/test_dev_app_bundle.py`, `walkthroughs/M14-python-acceptance.md` *(new)* |
| **M14-H** | D-021 grants backed by accepted per-ID evidence, final CI floors and closeout | `.github/workflows/ci.yml`, `DECISIONS.md`, `HANDOFF.md`, `ROADMAP.md`, `README.md`, `docs/CONTRIBUTING.md`, `docs/catalogue-identities.md`, `Sources/AgentLensCore/Detectors/DefaultDetectors.json`, `docs/capability-matrix.md`, `Tests/AgentLensCoreTests/CapabilityMatrixTests.swift`, `Tests/AgentLensCoreTests/BundledRegistryResourceTests.swift`, `Tests/AgentLensCoreTests/DetectorRegistryTests.swift`, `Tests/Packaging/test_dev_app_bundle.py` |

### R14 — Protected File Set

The following files enforce existing isolation and remain byte-identical unless narrowly excepted below. `Package.swift`, `Sources/agent-lens/main.swift` and historical records are protected; diagnostics change through existing renderer/coordinator seams. A newly discovered necessary change outside the allow-list is a planning stop, not permission to edit.

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
- `Sources/AgentLensCore/Operations/NpmUpdateOperation.swift` (C only: one exhaustive mapping for the Python-only `UnknownReason` in `map(_:)`; no reachable npm behavior change)
- `Sources/AgentLensCore/Operations/NpmUninstallOperation.swift`
- `Sources/AgentLensCore/Operations/HomebrewOperationModels.swift`
- `Sources/AgentLensCore/Operations/HomebrewFormulaUpdateOperation.swift`
- `Sources/AgentLensCore/Operations/HomebrewFormulaUninstallOperation.swift`
- `Sources/AgentLensCore/Operations/HomebrewCaskUpdateOperation.swift`
- `Sources/AgentLensCore/Operations/HomebrewCaskUninstallOperation.swift`
- `Tests/Fixtures/M9/*`, `Tests/Fixtures/M11/*`, `Tests/Fixtures/M12/*`, `Tests/Fixtures/M13/*`

### R15 — Quantitative Timeout Budgets & Resource Caps

Use the existing runner's 1 MiB hard cap and reject uv root output above 64 KiB before parsing. For files, caps are byte limits applied **during** reads, even after a successful `fstat`. Open proof files descriptor-relative with `O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC`, check regular type before reading, use bounded single-level enumeration, and revalidate directories/proof before publishing or mutating. A symlink in a proof directory is not made safe by `O_NOFOLLOW` on just the leaf.

| Operation / Seam | Timeout Budget | Size / Entry Cap |
| --- | --- | --- |
| `uv tool dir` / `uv tool dir --bin` probe | `5.0s` each | Reject more than `64 KiB` stdout |
| `uv-receipt.toml`, `direct_url.json`, `pipx_metadata.json` | Local bounded read | `64 KiB` each |
| `pyvenv.cfg` / `INSTALLER` | Local bounded read | `32 KiB` / `4 KiB` |
| `.dist-info/METADATA` | Local bounded read | `256 KiB`; 256 entries per enumerated directory, with realistic layouts checked in A |
| `.dist-info/RECORD` / `entry_points.txt` | Local bounded read | `1 MiB` / `64 KiB` |
| PyPI JSON API fetch | `8.0s` | `1 MiB`; supported provenance only |
| `pypi-update-metadata-v1.json` cache | `6h` TTL | `1 MiB`; regular-file bounded read, atomic replacement |
| `uv tool upgrade` | `180.0s` | Existing dual-stream operation runner cap |
| `uv tool uninstall` | `60.0s` | Existing dual-stream operation runner cap |

### R16 — Verification & CI Gate Commands

Use the phase-specific tests plus a clean build across Core, CLI, AppSupport and App at every product phase boundary. On this Command Line Tools workstation, use the invocation-local Swift Testing plugin workaround where needed; do not change `Package.swift`, the selected toolchain or hosted CI to compensate.

```bash
# SCRATCH is a fresh directory outside the repository and personal install roots.
env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS \
  swift build --scratch-path "$SCRATCH/build"
env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS \
  swift test --build-system swiftbuild --scratch-path "$SCRATCH/tests" --no-parallel \
  -Xswiftc -load-plugin-library \
  -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib \
  --filter "$PHASE_FILTER"
```

Verify the existing named regression anchors with the affected changes and in the combined gate: `bundledDefaultDetectorsMatchFrozenCatalogue`, `unknownKeysAreRejectedAtRootDefinitionFixturePackageAndQueryLevels`, `makeDetectorUsesRegistryArgumentsInTheProductionPath`, and `productionWiringUsesOnlyTheCoreLoginShellSeams`. For G/H, also run the existing Core/AppSupport import checks, build the debug app via `scripts/build-dev-app.py --scratch-root "$SCRATCH/app" --configuration debug`, and run `python3 Tests/Packaging/test_dev_app_bundle.py --app "$SCRATCH/app/AgentLensApp-debug.app"`. Use the G harness only once it exists, with a verified `uv` binary and isolated homes. H uses the existing hosted full build/test and packaging gates, zero skips/failures, and raises count floors from observed passing results only.

Compare each candidate against its pinned phase base (names and content), including `git diff --check <phase-base>...<candidate>` and the R13/R14 path/exception audit. A clean worktree does not prove a committed patch was docs-only. Implementer transcripts and test receipts are not acceptance: the orchestrator independently observes the phase gates (D-014), gets read-only independent reviews from the owner-designated reviewers, and records the verdict before the next dispatch. No implementation, commit, push, merge or release authorization follows from this plan.

---

## 3. Detailed Phase Breakdown (`M14-A` through `M14-H`)

### Phase M14-A — Live `uv` & `pip` Feasibility Probe Gate
- **What the committed report establishes:** `5ae73e5` adds only `briefs/M14-A-feasibility.md`. Its record includes an isolated stdlib venv and pip install, `Requires-Python` rejection, a PEP 668 marker on the observed Homebrew runtime, a sample shim target, and a `RECORD` row. Keep these observations. A receipt schema description and the observation that uv was not on the normal PATH do not establish that the required real-uv lifecycle was run. The report's blanket PASS is not accepted.
- **What must be added:** Pinned real `uv` identity/version/digest; exact commands, relevant sanitized environment, separate output and exit statuses for `tool dir`, `tool dir --bin`, install, upgrade and uninstall in isolated roots; actual `pyvenv.cfg`, receipt and shim/RECORD excerpts before/after. Show an unpinned upgrade and an uninstall in explicit non-default roots with a sibling environment unchanged. Include primary vs `--with`, index/direct source and constraint evidence (including what is *not* persisted), and verify interpreter retention and exact flags. Check real pipx pip/installer metadata and the selected script-to-site-packages/interpreter relationship for each claimed pip layout. Observe Homebrew's layout read-only or reproduce it in scratch; never install into `/opt/homebrew` or a personal prefix. Record ambiguities or unsupported layouts for an owner decision rather than calling them verified.
- **Exit Gate:** Reproducible commands and representative receipts in the report, with raw scratch paths treated as ephemeral. Verify the scoped isolation observations and clean disposable targets. The Phase A evidence commit changes only `briefs/M14-A-feasibility.md`, on top of the separate master-plan revision. Both owner-designated reviewers and the orchestrator must independently clear the pinned evidence; record the result before dispatch. Conclusions apply to the tested tools and layouts only, not future product phases.

### Phase M14-B — Core Python Ownership (`uvTool` & `pip`)
- **Goal:** Add Python vocabulary, bounded ownership proof and read-only diagnostics per R1; all product targets compile with Python actions disabled and no PyPI requests. Keep bundled declarations unchanged until E.
- **Key Tests (`UvToolOwnershipTests.swift`, `PipOwnershipTests.swift`):** Use the A receipts as fixture shapes. Verify the selected canonical script, exact managed shim and distro's installed-file evidence. Refuse cross-target roots/shims, missing or stale proof, symlinked/faulting proof components, receipt mismatch or malformed input, and the same distribution declaring a console script without owning the selected file. Prove pipx both with uv absent and with a shared uv/pipx bin directory; receipt/root evidence → no pip fallback. Distinguish pip, pipx, a marker-bearing system runtime, shared prefix, another Python installer, and standalone wrappers. Confirm the most common supported paths, not just a hand-built tree.

### Phase M14-C — Core PEP 440 Engine, `requires_python` & PyPI Update Probe
- **Goal:** Implement `PEP440Version` and `PEP440SpecifierSet` in `PEP440Version.swift`, extend `VersionScheme` with `.pep440` and `UnknownReason` with `.pythonInterpreterIncompatible`, implement `PyPIUpdateProbe` and `PyPIUpdateMetadataCache` (`pypi-update-metadata-v1.json`), and wire `.uvTool` and `.pip` into `UpdateProbeCoordinator`.
- **Key Tests Added (`PEP440VersionTests.swift`, `PyPIUpdateProbeTests.swift`, `PyPIUpdateMetadataCacheTests.swift`):**
  - PEP 440 ordering across epochs (`1!0.1 > 9.9.9`), zero-padded release segments (`1.2 == 1.2.0`), pre-releases (`0.86.2a1 < 0.86.2b1 < 0.86.2rc1 < 0.86.2`), alternative pre/post spellings (`1.0-1 == 1.0.post1`, `1.0c1 == 1.0rc1`), dev releases (`0.86.2.dev1 < 0.86.2a1` and `0.86.2 < 0.86.2.post1.dev1 < 0.86.2.post1`), and local labels (`+local`).
  - `PEP440SpecifierSet` evaluation for `~=`, `==` (with `.*`), `!=` (with `.*`), `<=`, `>=`, `<`, `>`, `===`, parenthesized expressions, and compound comma-separated clauses.
  - PyPI candidate filtering: yanked release rejection, prerelease filtering, `requires_python` compatibility filtering (selecting highest compatible release when available, or reporting `.unknown(installed: ..., reason: .pythonInterpreterIncompatible)` when all newer releases require a newer Python interpreter), custom index / VCS provenance refusal (`.unsupportedRegistry`), and 6-hour cache TTL + interpreter-keyed cache isolation.

### Phase M14-D — Core `uv tool` Update & Uninstall Operations
- **Goal:** Add the uv-only D-021 vocabulary and Core operation adapters, serialize through `OperationExecutionGate.shared`, and prove R5–R8 refusals and reconciliation. No CLI mutation verbs or bundled grants.
- **Key Tests Added (`UvToolOperationTests.swift`, `MutationAcceptanceGateTests.swift`):**
  - D-021 refusal before I/O; unverified/stale selection, changed roots/config/interpreter, exact pins including extras, unsupported provenance/channel and candidates outside receipt bounds do not launch Update.
  - Confirm cannot execute in another uv domain; evidence drift and repeated claims refuse. Uninstall binds every managed shim and remains offline.
  - Reconcile normalized version equality, downgrade, success, changed-on-error, partial removal, missing proof, cancellation, timeout, and remaining executable on a different path.

### Phase M14-E — Read-Only Registry Declarations & Capability Matrix Parity
- **Goal:** Add Python package declarations for `aider` and `hermes`, plus the `aider` extra search root, in `DefaultDetectors.json` and the capability matrix. Preserve current Homebrew grants. Add no built-in uv grants here; G uses controlled fixture definitions and H applies owner-authorized, accepted grants.
- **Key Verifications:**
  - All 4 frozen anchors pass.
  - Do-Not-Declare PyPI assertions added to `BundledRegistryResourceTests` verifying that `goose`, `dsh`, and `agy` declare zero `.uvTool` or `.pip` entries.

### Phase M14-F — AppSupport & SwiftUI Workflow Parity
- **Goal:** Wire `UvToolUpdateOperationView` and `UvToolUninstallOperationView` into `ToolDetailView`, `MainWindow`, and `InventoryViewModel`. Update `WorkflowPresentation` to enable verified, granted `uv tool` mutations and render context-specific read-only pip guidance. Extend `OwnershipVerificationView` as needed; the cache-clearing `SettingsView` change ships in C.
- **Key Tests Added (`WorkflowPresentationTests.swift`, `InventoryViewModelTests.swift`, `InventoryServiceTests.swift`):**
  - Action availability and read-only badge/guidance copy for `.uvTool` vs `.pip` (`.virtualEnvironment`, `.pipxEnvironment`, `.externallyManagedSystem`, `.sharedPrefix`).
  - Full ViewModel state transitions for `uvTool` update and uninstall preview → execute → reconcile → inventory refresh + PyPI cache invalidation.

### Phase M14-G — Disposable Acceptance Harness & Packaging Parity
- **Goal:** Author `Tests/Fixtures/M14/python_acceptance.py`, `Tests/Fixtures/M14/PythonAcceptanceHost.swift`, `Tests/Fixtures/M14/README.md`, and `walkthroughs/M14-python-acceptance.md`; extend `Tests/Packaging/test_dev_app_bundle.py` for the Python declarations before any mutation grants. Run the native journey with a separately staged scratch app bundle carrying test-only grants and fixture environment; never change the shipped registry to enable the test.
- **Exit Gate:** Real uv passes all R12 scenarios in scratch, and the orchestrator separately observes the native journey. Retain per-ID Update/Uninstall receipts, negative policy cases and no-personal-mutation evidence. Packaging asserts Python declarations with existing grants unchanged; test-only fixtures do not grant production authority.

### Phase M14-H — CI Floors, Decision Records & Documentation Closeout
- **Goal:** Apply only accepted and separately authorized D-021 grants at the final gate; update catalogue, matrix, and packaging expectations together. Ratchet CI floors from observed passing counts and run the real-uv harness using pinned CI provisioning. Record rulings and accepted evidence in `DECISIONS.md`, refresh living docs, and preserve separate owner merge/release decisions.

---

## 4. Owner Decisions (`OD-M14-1` through `OD-M14-3`)

1. **`OD-M14-1` — Two Distinct Python `PackageManager` Cases (`.uvTool` and `.pip`) vs a Single `.python` Case:**
   - **Recommended Ruling:** Use two distinct `PackageManager` cases: `.uvTool` (`"uvTool"`, label `"uv tool"`) and `.pip` (`"pip"`, label `"pip"`).
   - **Rationale:** `ROADMAP.md` §4 requires that "`uv`/`pip` ownership is distinguished" and "`uv` Update/Uninstall through the existing workflow; keep system/shared/ambiguous `pip` environments informational." Encoding `.uvTool` and `.pip` as distinct `PackageManager` cases makes the D-021 mutation boundary structural (`AcceptedOperation` has `uvToolUpdate`/`uvToolUninstall` and zero `pip*` cases) rather than relying on fragile runtime boolean flags.
2. **`OD-M14-2` — Adding `"~/.local/bin"` to `aider.extraSearchRoots` in `DefaultDetectors.json`:**
   - **Recommended Ruling:** Add `"~/.local/bin"` to `aider`'s `extraSearchRoots` (matching `hermes`, `claude`, `kiro-cli`, `omp`, `dsh`, and `qodercli`).
   - **Rationale:** `uv tool install` places entry-point symlinks in `uv tool dir --bin`, which defaults to `~/.local/bin` under the XDG Base Directory specification. On macOS machines where the user installed `uv` or `pipx` without adding `~/.local/bin` to `/etc/paths` or `~/.zprofile`, `aider` installed via `uv tool install aider-chat` would be missed by `ToolDetector` unless `"~/.local/bin"` is in `extraSearchRoots`.
3. **`OD-M14-3` — Handling `--with` Extra Requirements in `uv-receipt.toml` During `uv tool upgrade`:**
   - **Proposed, not settled:** Allow standard PyPI extras and disclose them only after the real-uv gate proves they survive upgrade without index/interpreter/constraint changes. Exact pins on any receipt requirement and direct/custom/unknown sources remain outside update scope. Refuse unproven receipt variants.
   - **Approval boundaries:** The owner approves the plan and supported layouts before B, names the implementer and independent reviewers, and approves D-021 grants per ID after accepted evidence. Keep CLI mutation out of M14 absent a separate authorized decision under D-022.

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
   - *Mitigation:* Pin and verify a real uv version, isolate or supply the binary, and stop if the real-manager gate cannot run. The fixture wheel/index lifecycle is offline from the public network; it does not simulate uv.
4. **Risk 4 (Medium) — Exhaustive Enum Switch & Error-String Test Pin Cascades:**
   - *Failure mode:* Adding `.uvTool` and `.pip` to `PackageManager`, `.pep440` to `VersionScheme`, `.pythonInterpreterIncompatible` to `UnknownReason`, and `.uvToolUpdate`/`.uvToolUninstall` to `AcceptedOperation` affects compiler exhaustiveness and error-string pins in `DetectorMetadataTests.swift` and `DetectorRegistry.swift`.
   - *Mitigation:* Add each enum case and all affected exhaustive arms/test changes at the same phase boundary. In particular C must update `ToolDetailView.plainLanguageReason` and the narrowly excepted `NpmUpdateOperation.map(_:)`. Compile all product targets, not only the Core test filter.
