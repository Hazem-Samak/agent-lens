# M11 delivery plan — independent proposal (MiniMax council member)

Author: MiniMax (council member). Date: 2026-11-12. Planning baseline: `main` = `d0a2b417e8c7d05f3c715a24e93f17851f7ab904`.
Authority used: ROADMAP §4 M11 and §6 invariants, DECISIONS.md D-001…D-020, AGENT_LENS_SCOPE.md §2/§11/§17/§20.4/§21/§22/§27/§29, briefs/README.md.
Read-only posture honoured: nothing under `Sources/`, `Tests/`, `scripts/`, `Resources/`, `Package.swift`, `.github/` or any existing brief/walkthrough was edited; no git mutation; no install, update or uninstall was performed; no subagent or second CLI was started. The only file written is this one.

**Evidence convention used throughout.** `verified-docs` = confirmed against a primary vendor source (official docs, official repository, npm/PyPI/Homebrew registry API) and the URL is given. `observed-local` = measured read-only on the author's machine on 2026-11-12 (`command -v`, `--version`, `ls`, `git remote -v`, registry API reads). `unverified` = could not be confirmed; no inference was substituted. A fact that is both is marked with both tags. "Do not declare" entries are explicit warnings, not omissions.

---

## 0. Executive summary for the judge

1. **Both named research blockers are resolved from primary sources.** DSH = **DeepSeek Harness** (`@deepseek-ai/dsh` on npm, `deepseek-ai/deepseek-harness`, docs at `deepseekdocs.com`). AGY = **Google Antigravity CLI** (`agy`, installed by `https://antigravity.google/cli/install.sh`, docs at `antigravity.google/docs/cli`). OMP = **Oh My Pi** (`@oh-my-pi/pi-coding-agent`, `can1357/oh-my-pi`, `omp.sh`). Hermes = **Hermes Agent** by Nous Research (`NousResearch/hermes-agent`, PyPI `hermes-agent`, Homebrew formula `hermes-agent`). The blockers are no longer identity-ambiguous; what remains unresolved is *version-query shape* for five tools and *one naming decision* (OD-4), not identity.
2. **M11 as currently scoped has a safety gap that must be closed inside M11.** `InstallationOwnershipVerifier.verifyNpm` (`Sources/AgentLensCore/Ownership/InstallationOwnershipVerifier.swift:121`) makes npm ownership generic: any detector that declares an npm candidate and is detected as `npm` becomes eligible for the M10 Update/Uninstall workflow. Adding five npm-distributed tools in M11 would therefore silently expose mutation buttons on tools whose npm path was never accepted. The proposal adds a **fail-closed per-entry capability record** that gates mutation eligibility (phases M11-A/M11-B). This is the single highest-value structural recommendation in this proposal.
3. **Eight bounded phases** on one milestone branch, each sized for one implementer dispatch, with research isolated in M11-0 and mutation-path work isolated in M11-B for independent review.
4. **Name collisions are real and dangerous** — `dsh` is an unrelated Homebrew core formula ("Dancer's shell"), `goose` exists on npm and PyPI as unrelated tools, the npm package `kiro-cli` is an unrelated placeholder whose binary is `kirox`, and the Homebrew cask `qoder` is the desktop IDE rather than the CLI. A wrong `packages` entry today becomes a wrong *mutation target* later. §F ranks these and §B lists explicit "do not declare" entries.
5. **Ten owner decisions** are listed in §F. Six are technical-but-owner-owned (registry vocabulary scope, source classification truthfulness, executable choice, matrix enforcement depth, npm mutability default, Kiro/AGY edge entries) and one is the MIT-vs-Apache-2.0 license gate, which the owner must choose; the recommendation is MIT, with the tradeoff stated in §D. The choice is not made here.

---

## A. Phase decomposition

**Branch:** one milestone branch, `milestone/m11-catalogue`, branched from `main` at `d0a2b41`. All phases are sequential on it (D-013). One product writer at a time; reviewers read-only.

**Standing constraints for every phase.** `DO NOT TOUCH` = `Package.swift`, `.github/workflows/**` (unless a phase explicitly names one step), `scripts/build-dev-app.py`, `scripts/check-core-ui-imports.py`, `Tests/Packaging/**`, all historical `briefs/*.md` except the orchestrator-owned M11 set, all `walkthroughs/**`, `DECISIONS.md`, `ROADMAP.md`, `AGENT_LENS_SCOPE.md`, `README.md`. No dependency may be added (zero-dependency rule, D-001/D-017). No manager mutation subcommand may be executed during any phase. No personal installation may be used as an acceptance target.

**Standing gates for every phase.** `swift test` (full suite) exit 0; fresh debug app build exit 0; `python3 Tests/Packaging/test_dev_app_bundle.py --app <built app>` exit 0; `python3 scripts/check-core-ui-imports.py` exit 0; a SHA-256 snapshot of every protected file proving no drift; a written implementer report with raw transcripts under the phase evidence root.

### M11-0 — Catalogue identity freeze (research; no product code)

- **Goal.** Produce one frozen, cited identity packet covering all 14 entries, so that every later phase cites a single artifact instead of re-deriving identity.
- **Non-goals.** No product code, no registry edit, no test change, no matrix row, no UI.
- **Deliverable.** `docs/catalogue/M11-identity.md` (new file, orchestrator-written) containing, per entry: vendor, canonical project, executable name(s), package identity per manager, install layout(s) with the exact path pattern, version-query behaviour with the measured raw output line, category, official information URL, official uninstall URL or an explicit "none published", evidence mark per field, and the source URL per claim. This document is the seed for the rows in the capability matrix (§C) and is the citation target for phases M11-C…M11-E.
- **Remaining work this phase must close (from §B's open list).** (1) Measure `--version` raw output for the five tools that are not installed here (Claude Code, Gemini CLI, Aider, Goose, Kiro CLI) in a **disposable** environment (temporary HOME/prefix, `uv tool install --into <scratch>`, `npm install --prefix <scratch>`, cask-free formula copies) — never on a personal install; where that is impossible, the field stays `unverified` with the reason. (2) Establish Kiro CLI's install path from the installer script (read the script; do not execute it) — the docs excerpt does not state it. (3) Re-verify the two OpenCode tap formulae against the live taps. (4) Decide OD-4 with the owner. (5) Confirm whether `hermes-agent` (legacy second binary) and `opencode2` are in scope as separate detector ids or as alternate executables of one tool.
- **Acceptance.** Every field in the packet carries exactly one evidence mark and, for `verified-docs`, a URL. No field is left blank; ambiguous fields say what is ambiguous and what would resolve it. A second, independent reader re-checks every `verified-docs` claim against its URL and reports the ones that do not support the claim. Packet is frozen by hash and cited by later briefs.
- **Dependencies / stop conditions.** Depends on M10 combined acceptance (met — `65f7a82`). Stop if a primary source is unreachable, if a package identity cannot be disambiguated from a same-named third-party project, or if measurement would require touching a personal installation.
- **Model tier.** **Strongest reasoning** (§29.6 — ambiguity dominates; this is the phase that previously blocked the milestone).

### M11-A — Registry and capability-matrix vocabulary (Core schema; additive)

- **Goal.** Extend the declarative vocabulary so 14 truthful entries can be expressed, and so per-entry capability can be stated without any tool-specific code.
- **Non-goals.** No new tool entries. No catalogue data. No change to scanner search, resolution, or ownership logic. No new manager adapter. No UI.
- **Scope sketch (exact files).**
  - Modify `Sources/AgentLensCore/Detection/DetectorRegistry.swift` — extend `knownLayouts` and `knownSources` (currently `["npmGlobal","singleDirectory","brewCellar"]` and `["npm","brew","standalone"]` at lines 638-639); add the capability-matrix types if placed here.
  - Modify `Sources/AgentLensCore/Detection/DetectorMetadata.swift` — extend `PackageManager` (currently `npm`, `homebrewFormula`, `homebrewCask`) and its per-manager name validation, per OD-2; extend `ToolCategory` only if OD-2 forces it (it should not: `aiAgent`/`aiCodingTool`/`aiHarness` already match scope §2 exactly).
  - Add `Sources/AgentLensCore/Detection/CapabilityMatrix.swift` — the typed, validated capability record and its loader/validator (fail closed, named errors, mirroring `DetectorRegistryError` style).
  - Add `Sources/AgentLensCore/Detectors/CapabilityMatrix.json` — the data file (schemaVersion 1), seeded with rows for `codex`, `opencode`, `grok` only.
  - Add `Tests/AgentLensCoreTests/CapabilityMatrixTests.swift`.
  - Protected: `Sources/AgentLensCore/Detection/ToolDetector.swift` **except** the exact `classifySource` change decided in OD-3; `Sources/AgentLensCore/Ownership/**`; `Sources/AgentLensCore/Operations/**`; `Sources/AgentLensAppSupport/**`; `Sources/AgentLensApp/**`.
- **Behavioural contract.**
  1. **Additive only.** `schemaVersion` stays `2` for the detector registry. New enum *values* are added; existing values, existing entries and existing error vocabulary are unchanged. Schema 1 and 3 remain rejected (`DetectorRegistry.swift:637`). Rationale: the schema's meaning changes only by addition, so a strict version bump would reject every third-party registry a contributor wrote against schema 2. This is recorded as a new DECISIONS entry (D-021), never by editing D-017.
  2. **Capability record shape** (proposed, §C): per entry — `id`, `category`, `state` (`enabled` | `informational` | `disabled`), `latestCheck` (`support` + `source`/`reason`), `update` (`support` + `manager`/`reason`), `uninstall` (`support` + `manager`/`reason`), `testedLayouts`, `knownLimits`. Every non-`supported` support value **must** carry a non-empty human-readable reason. `state: informational` requires at least one non-empty reason.
  3. **Fail closed.** A detector id with no matrix row is treated as *no capability*: no Update, no Uninstall, no latest probe. A matrix row with an unknown detector id is a validation error naming the id.
  4. **Validation.** Unknown keys, wrong types, empty reasons, unknown ids and duplicate ids are rejected with named errors, in the same style and at the same strictness as the M9-A metadata work.
  5. **Layout/source vocabulary additions** (each needs a synthetic fixture and a test): `uvTool` (uv tool environment), `pipxVenv` (pipx venv), `cargoBin` (cargo install), `nativeInstaller` (self-contained binary installed by a vendor script), `gitSource` (vendor source checkout with its own launcher). Corresponding source values only if OD-3 says so.
  6. **Package-name validation per new manager**, following the existing conservative style: PyPI names (`aider-chat`, `hermes-agent`), crate names, and fully qualified taps (`can1357/tap/omp`). Reject paths, whitespace, NUL, option markers, as the npm/brew rules already do.
- **Acceptance outline.** `swift test --filter CapabilityMatrix` exit 0 with named-error cases for each invalid shape; `swift test` full suite exit 0; a round-trip encode/decode test; a test asserting the bundled matrix loads and every id matches a bundled detector; the Core/UI import guard still passes.
- **Dependencies / stop conditions.** After M11-0. Stop if implementing the matrix requires a scanner or ownership refactor, or if a new enum value cannot be justified by a cited primary source.
- **Model tier.** **Strongest reasoning** — this phase defines the safety vocabulary the whole catalogue depends on; low volume, high ambiguity.

### M11-B — Capability gate wiring (mutation eligibility consults the matrix)

- **Goal.** Make the per-entry capability record *actually* control the user-visible operation surface, so an entry without an accepted adapter is informational with a truthful reason rather than a live button.
- **Non-goals.** No new manager adapter (Homebrew/uv/Cargo are M13–M15). No redesign of the M10 confirmation journey. No new operation type. No category navigation.
- **Scope sketch.** Modify `Sources/AgentLensCore/Ownership/InstallationOwnershipVerifier.swift` (admit an npm subject only when the matrix marks `update`/`uninstall` as `supported` for manager `npm`), `Sources/AgentLensCore/Updates/UpdateProbeCoordinator.swift` (admit an npm latest probe only when the matrix marks `latestCheck` supported for `npm`), `Sources/AgentLensCore/Operations/OperationModels.swift` (carry the capability reason on a refused operation), `Sources/AgentLensAppSupport/InventoryService.swift` and `InventoryViewModel.swift` (surface the reason instead of an enabled control), `Sources/AgentLensApp/ToolDetailView.swift` and `UninstallOperationView.swift` (render the reason, keep the current native style), `Sources/agent-lens/main.swift` (CLI renders the same reason). Add `Tests/AgentLensCoreTests/CapabilityGateTests.swift` and extend `Tests/AgentLensAppSupportTests/`.
- **Behavioural contract.**
  1. The gate is an **allow-list**: unsupported means no control, plus a stated reason. It is never a silent omission.
  2. The gate is checked **before** any manager process is constructed (no probe, no ownership query, no command) — mirroring the existing fail-closed shape of `InstallationOwnershipVerifier`.
  3. The reason text comes from the matrix and is identical in CLI and app (the CLI/app fact-agreement requirement of §E).
  4. Existing M10 behaviour for `codex` is preserved exactly: npm update/uninstall remains offered and functional. The matrix seeds `codex` as `supported` for npm, so the M10 journey is unchanged.
  5. No new operation may be created by a gate refusal.
- **Acceptance outline.** A test that flips one matrix row to `informational` and observes: no update probe runs (assert zero child processes via the injected runner), no Uninstall control is offered, and the reason string is surfaced identically in CLI output and in the app's tool detail. Full suite exit 0; app build and packaging exit 0. A native click-through in the built app confirms the informational entry shows its reason and offers no destructive control.
- **Dependencies / stop conditions.** After M11-A. **Independent read-only review is mandatory for this phase** (ROADMAP §5.4 — it touches ownership/mutation). Stop if the gate cannot be enforced without changing the M10 confirmation semantics.
- **Model tier.** **Strongest reasoning** + independent review.

### M11-C — Catalogue batch 1: npm-distributed entries

- **Goal.** Add the npm-distributed part of the catalogue as data, with fixtures and measured version behaviour.
- **Non-goals.** No native-installer, Python or Homebrew-only entries. No capability change beyond the seeded rows. No UI.
- **Entries.** Claude Code (`claude`), Gemini CLI (`gemini`), Cline CLI (`cline`), DSH (`dsh`), Qoder CLI (`qoder`/`qodercli` — per OD-4). Codex is corrected, not added (its npm identity is unchanged; see §B).
- **Scope sketch.** Modify only `Sources/AgentLensCore/Detectors/DefaultDetectors.json`, add `Sources/AgentLensCore/Detectors/CapabilityMatrix.json` rows for these ids, add per-entry fixtures in `Tests/AgentLensCoreTests/`, and **replace the catalogue-pinning assertion** in `Tests/AgentLensCoreTests/DetectorRegistryTests.swift:82` (`#expect(ids == ["codex", "opencode", "grok"])`) with a generic, set-based assertion — pinning the catalogue in a test is the defect that would block every later entry. Modify `Sources/AgentLensCore/Detection/DetectorRegistry.swift` **only** if a new fixture layout is needed (M11-A should have added it).
- **Behavioural contract.** Every entry declares: category from scope §2 (Claude Code, Gemini CLI, Cline CLI → `aiAgent`; DSH → `aiHarness`; Qoder → `aiCodingTool`), executable name, `extraSearchRoots` for observed off-PATH layouts, npm package candidates, `informationURL` (HTTPS, validated), `uninstallInstructionsURL` only where a real uninstall page exists, and a `versionQuery` matching the **measured** output shape from M11-0 (arguments, stream, line). Where the measured shape is `unverified`, the entry declares the default query and the matrix records the limit; the version then renders as unknown, which is truthful.
- **Acceptance outline.** `swift test` exit 0; each new id has a fixture that constructs its layout and asserts `installedAndOnPath` + the declared source; a CLI run shows the new entries with the correct category, candidates and links; the app shows them with the same facts (CLI/app agreement). The registry loads with 8 entries and the matrix has 8 rows, proven by a test.
- **Dependencies / stop conditions.** After M11-A and M11-B (the gate must exist before new npm entries appear, so that mutability is opt-in per row). Stop if an entry's identity is not confirmed by M11-0, or if a package name in the entry is not exactly what the registry publishes.
- **Model tier.** **Flash tier** — high-volume, low-ambiguity data work, with a strong reviewer for the per-entry facts (briefs/README model table: M4/M6 precedent).

### M11-D — Catalogue batch 2: native/standalone entries + corrections to delivered entries

- **Goal.** Add the self-contained-binary entries and correct the three delivered entries against current primary sources.
- **Non-goals.** No Python/Homebrew-only entries. No capability rows for managers whose adapters do not exist. No UI.
- **Entries.** AGY (Antigravity CLI, `agy`), Kiro CLI (`kiro-cli`), OMP (`omp`). Corrections: Codex (measured failure mode), OpenCode (second executable + current off-PATH layout), Grok CLI (current version shape, layout, links).
- **Scope sketch.** Same file set as M11-C (`DefaultDetectors.json`, `CapabilityMatrix.json`, tests). `Sources/AgentLensCore/Detection/ToolDetector.swift` only for the OD-3 `classifySource` decision.
- **Behavioural contract.**
  1. These entries declare **no package candidates** where no manager package exists (AGY, Kiro CLI) and are `informational` for update/uninstall with the reason "installed by a vendor script; no package-manager ownership" (D-008/D-020). OMP declares its npm package and its `can1357/tap/omp` tap formula; both are candidates, never proof.
  2. `extraSearchRoots` must cover the observed off-PATH layouts, e.g. Antigravity's older `~/.gemini/bin/agy` (observed-local, version 1.2.12 while the PATH copy is 1.5.6) so the `installedNotOnPath` state (D-006) is reachable and a second copy is visible as a duplicate.
  3. Version queries match the measured shapes: `agy --version` → `1.5.6` (bare), `omp --version` → `omp/18.19.0` (prefixed token — the existing bounded token parser yields `18.19.0`, which is correct), `grok --version` → `grok 1.0.77 (50ca579fa996) [stable]` (yields `1.0.77`). Kiro CLI's shape stays `unverified` until M11-0 measures it.
  4. **Self-updaters are never invoked.** `agy update`, `qoder update`, `hermes update` exist upstream (verified-docs) and are recorded as known limits; Agent Lens does not call them.
- **Acceptance outline.** `swift test` exit 0; a CLI scan on the author's machine shows AGY, OMP and the corrected entries with truthful categories and no false ownership; the OpenCode entry correctly reports `installedNotOnPath` when the binary is off PATH (this exact condition exists on the author's machine — observed-local).
- **Dependencies / stop conditions.** After M11-C. Stop if AGY↔Antigravity or OMP↔Oh My Pi cannot be re-confirmed from a primary source, or if Kiro CLI's install path is still unknown.
- **Model tier.** **Flash tier** with a strong reviewer; the three corrections to delivered entries deserve extra care because they change what users see for already-shipped tools.

### M11-E — Catalogue batch 3: Python and Homebrew-family entries

- **Goal.** Add the entries whose install mechanism is Python/uv/pipx or Homebrew, which is where the current classifier is weakest.
- **Non-goals.** No uv/Cargo/Python mutation adapter (M14/M15). No PEP 440 comparison work. No Homebrew formula ownership work (M13).
- **Entries.** Hermes (`hermes`), Aider (`aider`), Goose (`goose`).
- **Scope sketch.** Same file set as M11-C/D, plus `Sources/AgentLensCore/Detection/ToolDetector.swift` only if OD-3 adds a uv/cargo source rule, plus `Sources/AgentLensCore/Updates/VersionComparison.swift` **only** if a measured version shape in this batch exposes a genuine ordering defect (e.g. `aider-chat` 0.86.2 versus a `1.x` scheme) — this phase must not start a general versioning project.
- **Behavioural contract.**
  1. **Package-name discipline is the point of this phase.** Declare `aider-chat` (PyPI) and `aider` (Homebrew formula) for Aider; `hermes-agent` (PyPI and Homebrew formula) for Hermes; `block-goose-cli` (Homebrew formula) for Goose. **Do not declare** npm `goose` (an unrelated project, `jiyinyiyong/goose`), PyPI `goose` (a SQL migration tool), Homebrew core `goose` (the Go migration tool), npm `kiro-cli` (an unrelated placeholder whose binary is `kirox`), Homebrew core `dsh` ("Dancer's shell"), or Homebrew cask `qoder` (the desktop IDE) — see §B "do-not-declare" table.
  2. Hermes' git-source install is a distinct layout from its PyPI/Homebrew installs and is **informational** (a git checkout has no manager ownership Agent Lens can verify). Its version line contains several numbers (`Hermes Agent v0.23.1 (2026.9.24) · stable · local 3b4215785882` — observed-local); the bounded parser takes the first token `0.23.1`, which is the product version; the matrix records that the remaining numbers are a release date and a commit id, so a future parser change is not silently needed.
  3. If OD-3 says uv/pip installs must not be labelled `standalone`, the source label for these entries is `uv` (or `unknown`) and the matrix says why; if OD-3 says otherwise, the matrix carries an explicit "source heuristic limitation" limit for these entries rather than leaving the app silently wrong.
- **Acceptance outline.** `swift test` exit 0; fixtures for the `uvTool`, `pipxVenv` and `brewCellar` layouts; a measured-version fixture for each of the three; a CLI run showing Aider, Goose and Hermes with truthful package candidates and no ownership claim.
- **Dependencies / stop conditions.** After M11-D. Stop if the uv/venv layout cannot be modelled without a scanner change beyond OD-3.
- **Model tier.** **Flash tier** for the data, **strongest reasoning** for the OD-3 consequence check inside this phase (it is where a wrong source label becomes a user-visible lie).

### M11-F — Capability matrix publication and contributor foundation

- **Goal.** Publish the matrix as a truthful, regenerable artifact and make "add a tool" a data-only, validated contribution (§D).
- **Non-goals.** No UI rendering of the matrix (M12 owns that). No license selection on the owner's behalf. No public contribution invitation. No packaging/release changes.
- **Scope sketch.** Add `scripts/render-catalogue.py` (renders markdown from `DefaultDetectors.json` + `CapabilityMatrix.json`); add `scripts/validate-catalogue.py` (offline validator: id-set equality, required fields, non-empty reasons, HTTPS link shape, package-name rules, matrix/registry agreement, every entry's version query present); add `docs/CATALOGUE.md` (generated); add `docs/CONTRIBUTING.md` (contributor guide); add a CI step in `.github/workflows/ci.yml` (validator + regenerate-and-diff) — this is the **only** phase permitted to touch `.github/`, and only by adding one step to the existing job, never by editing an existing gate; extend `Tests/AgentLensCoreTests/CapabilityMatrixTests.swift` with the registry↔matrix agreement assertions.
- **Behavioural contract.**
  1. `docs/CATALOGUE.md` is **generated**. The CI step regenerates it into a temporary file and fails on any byte difference. A hand-edited matrix fails CI.
  2. The published matrix has exactly the columns ROADMAP M11 requires: tool, category, tested layouts, latest-check support, Update support, Uninstall support, known limits.
  3. The contribution path is genuinely data-only: a contributor edits `DefaultDetectors.json` + `CapabilityMatrix.json` + adds a fixture, and changes **no** scanner or UI source. The M11-G acceptance proves this end to end (§E).
  4. The validator is deterministic and offline (no network in CI for validation). The matrix generator never fetches anything.
  5. `docs/CONTRIBUTING.md` states the evidence rules used in §B (`verified-docs` / `observed-local` / `unverified`), the rule that a declared package candidate is never ownership proof, the rule that an unobserved layout may not be labelled verified, and the rule that a fixture proves the detector, never a real installation.
- **Acceptance outline.** CI green with the new step; `python3 scripts/validate-catalogue.py` exit 0 on the committed tree; deliberately corrupting a matrix row in a scratch copy makes the validator exit non-zero with a named message; `docs/CATALOGUE.md` regenerates byte-identically.
- **Dependencies / stop conditions.** After M11-E (the matrix needs all 14 rows to be meaningful). Stop if the generator cannot be made deterministic, or if a CI step would have to replace an existing gate.
- **Model tier.** **Strongest reasoning** for the validator and the CI gate (a false-negative validator silently disables the whole contributor safety net); the prose may be drafted in the same dispatch by the same writer.

### M11-G — Combined M11 acceptance gate (orchestrator-run)

- **Goal.** Independent acceptance of M11 as a whole.
- **Non-goals.** No implementation. No fixing. The orchestrator reruns everything itself (D-014).
- **Scope sketch.** No product files. Orchestrator-only execution; the implementer of the last phase supplies raw transcripts and a SHA-256 candidate manifest.
- **Acceptance outline.** See §E for the full combined gate.
- **Dependencies / stop conditions.** After M11-F. The orchestrator, not an implementer, runs it.
- **Model tier.** **Orchestrator** (Qoder) runs it; no implementer model.

**Phase dependency graph.** `M11-0 → M11-A → M11-B → M11-C → M11-D → M11-E → M11-F → M11-G`. M11-C/D/E are strictly sequential even though they touch different entries, because they touch the *same two data files* — three concurrent writers on one file is precisely the branch-conflict failure D-013 forbids.

---

## B. Catalogue identity research (preliminary, primary-source)

Read set for this section: npm registry API (`npm view`), PyPI JSON API (`https://pypi.org/pypi/<name>/json`), Homebrew API (`https://formulae.brew.sh/api/formula|cask/<name>.json`), vendor documentation, official repositories, plus read-only inspection of the author's machine on 2026-11-12.

### B.1 Summary matrix

| # | Tool | Category (scope §2) | Executable | Package identities | Layout(s) | Version query | Evidence |
|---|---|---|---|---|---|---|---|
| 1 | Codex | aiAgent | `codex` | npm `@openai/codex`; cask `codex` | npmGlobal; cask | `--version` stdout first — **fails on this machine** (non-zero exit) | verified-docs / observed-local |
| 2 | Claude Code | aiAgent | `claude` | npm `@anthropic-ai/claude-code`; cask `claude-code`; native installer `~/.local/bin/claude` | npmGlobal; cask; nativeInstaller | `--version` — shape **unverified** | verified-docs |
| 3 | Gemini CLI | aiAgent | `gemini` | npm `@google/gemini-cli`; formula `gemini-cli` | npmGlobal; brewCellar | `--version` — shape **unverified** | verified-docs |
| 4 | OpenCode | aiAgent | `opencode` (+`opencode2`) | npm `@opencode/cli`, `opencode-ai`; tap `anomalyco/tap/opencode-v2`, `anomalyco/tap/opencode` | npmGlobal; standalone `~/.opencode/bin` | `--version` → bare token | verified-docs (M9-A packet) / observed-local |
| 5 | Hermes | aiAgent | `hermes` (+`hermes-agent`, `hermes-acp`) | PyPI `hermes-agent`; formula `hermes-agent`; official git install | gitSource `~/.hermes/hermes-agent`; uvTool; brewCellar | `--version` → `Hermes Agent v0.23.1 (2026.9.24) · stable · local 3b4215785882` | verified-docs / observed-local |
| 6 | Cline CLI | aiAgent | `cline` | npm `cline`; formula `cline` | npmGlobal; brewCellar | `--version` → `3.0.74` | verified-docs / observed-local |
| 7 | Aider | aiCodingTool | `aider` | PyPI `aider-chat` (+`aider-install`); formula `aider`; uv/pipx | uvTool; pipxVenv; brewCellar; standalone venv | `--version` — shape **unverified** | verified-docs |
| 8 | Goose | aiCodingTool | `goose` | formula `block-goose-cli`; script install | nativeInstaller `~/.local/bin/goose`; brewCellar | `--version` — shape **unverified** | verified-docs |
| 9 | Kiro CLI | aiCodingTool | **`kiro-cli`** | **none** (no npm/brew package) | nativeInstaller — path **unverified** | `--version` — shape **unverified** | verified-docs |
| 10 | Qoder | aiCodingTool | `qoder` (dispatcher) / `qodercli` (runtime) | npm `@qoder-ai/qodercli`; script install | nativeInstaller `~/.qoder/…`; npmGlobal | `--version` → `1.1.88` (both) | verified-docs / observed-local |
| 11 | DSH | aiHarness | `dsh` | npm `@deepseek-ai/dsh` | npmGlobal; `$DSH_HOME` data dir | `--version` → `0.2.2-rc.1` | verified-docs / observed-local |
| 12 | OMP | aiHarness | `omp` | npm `@oh-my-pi/pi-coding-agent`; tap `can1357/tap/omp` | nativeInstaller; npmGlobal/bun | `--version` → `omp/18.19.0` | verified-docs / observed-local |
| 13 | AGY (Antigravity CLI) | aiHarness | `agy` | **none** (script install only) | nativeInstaller `~/.local/bin/agy`; legacy `~/.gemini/bin/agy` | `--version` → `1.5.6` | verified-docs / observed-local |
| 14 | Grok CLI | aiAgent | `grok` | **none** | standalone `~/.grok/downloads/…` + `~/.grok/bin/grok` | `--version` → `grok 1.0.77 (50ca579fa996) [stable]` | verified-docs (M9-A packet) / observed-local |

### B.2 Per-entry detail with sources

**1 — Codex (OpenAI).** Executable `codex`. npm `@openai/codex` 0.167.2, bin `codex → bin/codex.js`, repo `github.com/openai/codex` (verified-docs, npm registry). Homebrew **cask** `codex` 0.167.2, homepage `github.com/openai/codex` (verified-docs, Homebrew API). Information URL `https://developers.openai.com/codex/cli` (carried from the M9-A verified packet). **Observed-local:** `~/.local/bin/codex → ~/.local/lib/node_modules/@openai/codex/bin/codex.js` (npm global under a `~/.local` prefix), and `codex --version` **fails** with `Error: Missing optional dependency @openai/codex-darwin-arm64` and a non-zero exit. **M11 implication:** the entry must render version `—` (unknown) in that state, not an error; this is the same optional-dependency/postinstall failure mode Anthropic documents for `@anthropic-ai/claude-code` (see entry 2), so M11 should treat "npm package installed but native binary absent" as a first-class, expected unknown-version case, and the matrix should list it under known limits. No package change needed; only the known-limit note and the extra root for the `/opt/homebrew` npm prefix.

**2 — Claude Code (Anthropic).** Executable `claude`. npm `@anthropic-ai/claude-code` 2.1.322, bin `claude` (verified-docs, npm registry). Homebrew **cask** `claude-code` 2.1.311 (verified-docs, Homebrew API). Native installer `curl -fsSL https://claude.ai/install.sh | bash` places the binary at `~/.local/bin/claude`; the docs state "`~/.local/bin/claude` is the native installer, `~/.claude/local/` is a legacy local npm install created by older versions of Claude Code" (verified-docs, `https://code.claude.com/docs/en/troubleshoot-install`). Install methods table lists macOS/Linux/WSL script, Homebrew cask, and npm (verified-docs, `https://support.claude.com/en/articles/14552382-your-first-day-in-claude-code`). Verification command documented as `claude --version` (verified-docs). **unverified:** the exact output shape of `claude --version` (not installed on the author's machine; M11-0 must measure it in a disposable environment). **M11 implication:** three layouts, one executable name → `extraSearchRoots` must include `~/.local/bin` (native) and the npm prefix. The npm package downloads a per-platform optional dependency and replaces a placeholder script at postinstall; when that postinstall is skipped the placeholder prints an error and exits non-zero (verified-docs) → same expected unknown-version handling as Codex.

**3 — Gemini CLI (Google).** Executable `gemini`. npm `@google/gemini-cli` 0.68.0, bin `gemini → bundle/gemini.js`, repo `github.com/google-gemini/gemini-cli` (verified-docs, npm registry). Homebrew formula `gemini-cli` 0.68.0, homepage `geminicli.com` (verified-docs, Homebrew API). **unverified:** `--version` output shape (not installed here). **M11 implication:** straightforward npm + brew entry; both candidate managers are real and distinct, so both belong in `packages` with the caveat that a candidate is never ownership proof.

**4 — OpenCode (Anomaly).** Executable `opencode`. npm `@opencode/cli` 2.2.7 with bins `opencode` **and** `opencode2`; npm `opencode-ai` 1.19.5 with bin `opencode`; repo `github.com/anomalyco/opencode` (verified-docs, npm registry). Tap formulae `anomalyco/tap/opencode-v2` and `anomalyco/tap/opencode` (verified-docs, carried from the M9-A catalogue packet; M11-0 must re-verify the taps are live). Standalone layout `~/.opencode/bin/opencode` (verified-docs M9-A; observed-local: 231 MB native binary dated 2026-11-10, plus a 47-byte `opencode2` shell shim in the same directory). Information `https://opencode.ai/v2/docs/`, uninstall `https://opencode.ai/v2/docs/cli/#uninstall` (carried from M9-A). **Observed-local, important:** the binary is **not on the login-shell PATH** on the author's machine — `~/.opencode/bin` is absent from the resolved PATH — so OpenCode is currently an `installedNotOnPath` case. The registry's existing `extraSearchRoots: ["~/.opencode/bin"]` is exactly the mechanism that surfaces it (D-006). **M11 implication:** keep the entry, keep the extra root, add `opencode2` as an alternate executable or a separate id (OD-4), and add a known limit "npm package publishes a second executable name".

**5 — Hermes (Nous Research).** Executable `hermes`; the install also publishes `hermes-agent` (legacy single-query runner) and `hermes-acp` (verified-docs, `hermes-agent/website/docs/reference/cli-commands.md`). Project **Hermes Agent**, repository `NousResearch/hermes-agent`, docs `hermes-agent.nousresearch.com` (verified-docs). Official install `curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash`; the installer script itself names `REPO_URL="https://github.com/NousResearch/hermes-agent.git"`, bootstraps uv, and stages the checkout under the install directory (verified-docs, `https://hermes-agent.nousresearch.com/install.sh`). Also installable as PyPI `hermes-agent` 0.19.0 (verified-docs, PyPI API, summary "The self-improving AI agent — creates skills from experience") and as Homebrew **formula** `hermes-agent` 0.22.4, homepage `hermes-agent.nousresearch.com` (verified-docs, Homebrew API). Version: `hermes --version` documented as "Show version and exit" (verified-docs). **Observed-local:** the author's install is the **git** variant — `~/.hermes/hermes-agent/.install_method` contains `git`, `git remote -v` shows `origin https://github.com/NousResearch/hermes-agent.git`, the real executable is `~/.hermes/hermes-agent/.hermes/bin/hermes`, and `~/.local/bin/hermes` is a three-line shell shim that execs it. `hermes --version` prints `Hermes Agent v0.23.1 (2026.9.24) · stable · local 3b4215785882` followed by `Install directory: …`, `Install method: git`, `Python: 3.14.9` (observed-local; first line's first numeric token is `0.23.1`). Upstream ships `hermes update` and a `hermes` update command (verified-docs) → recorded as a known limit; never invoked by Agent Lens. **M11 implication:** the scope's illustrative line "✓ Hermes 0.20.5 uv" (SCOPE §3.1) reflects the **PyPI/uv** distribution, while the observed local install is git. Both are real; the entry must declare `hermes-agent` as a uv/PyPI candidate and treat the git checkout as an informational layout with reason "source checkout — no package-manager ownership". The scope's sample text is illustrative, not a measurement, and must not be copied into the app as a fact.

**6 — Cline CLI (Cline).** Executable `cline`. npm `cline` 3.0.74, bin `cline → bin/cline`, repo `github.com/cline/cline`, homepage `cline.bot` (verified-docs, npm registry). Homebrew formula `cline` 3.0.3, homepage `cline.bot` (verified-docs, Homebrew API). Official install `npm install -g cline`; Node.js 22+ recommended (verified-docs, `https://docs.cline.bot/getting-started/installing-cline`, `https://docs.cline.bot/usage/cli-overview`, `https://cline.bot/cli`). **Observed-local:** `cline --version` → `3.0.74` (bare token, parses cleanly). **Observed-local, three copies on the login-shell PATH:** `~/.local/bin/cline` (npm global, prefix `~/.local`), `~/.local/shims/cline` (shim), `/opt/homebrew/bin/cline` (npm global under the Homebrew npm prefix) — all three report `3.0.74`. This is a live duplicate-diagnostics case for the product's primary value proposition (D-015). The shim in `~/.local/shims` is not an npm `node_modules` path, so the current `classifySource` would label that copy `standalone` even though it fronts the same npm package — a truthfulness caveat worth recording as a known limit (and an input to OD-3).

**7 — Aider (Aider-AI).** Executable `aider`. Install methods, all from `https://aider.chat/docs/install.html` (verified-docs): `python -m pip install aider-install` then `aider-install`; one-liner `curl -LsSf https://aider.chat/install.sh | sh` (uv-based, installs Python 3.12 if needed); `uv tool install --force --python python3.12 --with pip aider-chat@latest`; `pipx install aider-chat`; `pip install -U --upgrade-strategy only-if-needed aider-chat`. PyPI `aider-chat` 0.86.2 (verified-docs, PyPI API). Homebrew formula `aider` 0.86.2, homepage `aider.chat` (verified-docs, Homebrew API). The same docs caution that system package managers "often install aider with incorrect dependencies" (verified-docs) — a known limit worth quoting in the matrix. **unverified:** `--version` output shape (not installed here). **M11 implication:** Aider has five install mechanisms; the entry should declare `aider-chat` (PyPI/uv/pipx) and `aider` (Homebrew formula) as candidates and cover the layouts `uvTool`, `pipxVenv`, `brewCellar` and the standalone venv from `aider-install`.

**8 — Goose (Agentic AI Foundation; formerly Block).** Executable `goose`. Official CLI install `curl -fsSL https://github.com/aaif-goose/goose/releases/download/stable/download_cli.sh | bash`; the script reads `GOOSE_BIN_DIR` defaulting to `$HOME/.local/bin` and moves the extracted `goose` binary there (verified-docs, script body). Homebrew formula `block-goose-cli` 1.59.0, homepage `goose-docs.ai`; desktop cask `block-goose` 1.59.0 (verified-docs, Homebrew API). Project moved from `block/goose` to `aaif-goose/goose` and the docs site to `goose-docs.ai`; binary and package names still say "block" for compatibility (verified-docs). Verification command documented as `goose --version` (verified-docs). **unverified:** output shape (not installed here). **M11 implication:** declare `block-goose-cli` only; the cask is the desktop app, not the CLI.

**9 — Kiro CLI (AWS).** Executable **`kiro-cli`** — not `kiro` (verified-docs, `https://kiro.dev/docs/cli/` and `https://kiro.dev/docs/cli/installation/`). Official install `curl -fsSL https://cli.kiro.dev/install | bash` (verified-docs). "Kiro CLI 3.0.0 or later is a single standalone `kiro-cli` binary: the desktop app and inline shell autocomplete are retired" (verified-docs). **No npm and no Homebrew package exists**: `npm view @aws/kiro-cli` → 404, and the npm package named `kiro-cli` (0.0.1) is an unrelated placeholder whose bin is `kirox` (verified-docs, npm registry + npm search). **unverified:** the install path the script uses (the docs excerpt does not state it — M11-0 must read the script without executing it) and the `--version` output shape. **M11 implication:** this entry has no manager candidate and therefore no ownership; it is informational with reason "installed by a vendor script; no package-manager ownership". If its install path cannot be established, ship the entry limited to the PATH-resolved binary and state that limit in the matrix rather than guessing a directory.

**10 — Qoder (Alibaba).** Two executables: `qoder` and `qodercli` (verified-docs, npm registry: `@qoder-ai/qodercli` 1.1.88 with bins `qoder → bundle/qoder-npm-dispatcher.cjs` and `qodercli → bundle/qodercli.js`). Recommended install `curl -fsSL https://qoder.com/install | bash` → native standalone executable; legacy npm `npm install -g @qoder-ai/qodercli` runs the JS bundle on Node.js and is "not recommended for new installations" (verified-docs, `https://docs.qoder.com/cli/installation`, `https://qoder.com/en/cli`). Verification command `qoder --version` (verified-docs). Homebrew **cask** `qoder` 0.5.7 exists but is described as "Agentic coding platform" with homepage `qoder.com` — it is the Qoder desktop/IDE, **not** the CLI (verified-docs, Homebrew API). **Observed-local:** `qoder` resolves to `~/.qoder/entry/qoder`, a 4150-byte bash dispatcher that routes to `qodercli` when present and otherwise to the IDE; the CLI runtime is versioned under `~/.qoder/bin/qodercli/` with `qodercli-1.1.85`, `-1.1.86` and `-1.1.88` retained; `qoder --version` and `qodercli --version` both print `1.1.88`. The separate `qoderwake` CLI documented at `docs.qoder.com/qoderwake/cli-reference` is a different product (QoderWake) and is **out of scope**. **M11 implication:** OD-4 — pick the detector executable. My recommendation: detect `qoder` (the user-facing command) and treat `qodercli` as the runtime it dispatches to, and additionally declare `~/.qoder/bin` and `~/.qoder/entry` as search roots. `qoder update` exists (verified-docs) → known limit, never invoked.

**11 — DSH (DeepSeek).** **Named research blocker — resolved.** Project **DeepSeek Harness**; npm `@deepseek-ai/dsh`, current `latest` 0.2.2-rc.1, bin `dsh → lib/bin.js`, repo `github.com/deepseek-ai/deepseek-harness`, homepage `github.com/deepseek-ai/deepseek-harness` (verified-docs, npm registry). Official docs: `https://deepseekdocs.com/en/docs/getting-started/quickstart` and `https://deepseekdocs.com/en/docs/user-guide/cli`; the CLI README states "The `dsh` command is the sole supported Node application launcher: profiles are ordered stacks of plugin-bundle patch layers" and that "The Python runtime wheel packages this same command" (verified-docs, `github.com/deepseek-ai/deepseek-harness/blob/master/apps/cli/README.md`). Install `npm i @deepseek-ai/dsh` (verified-docs). Release channels exist: npm `latest`/`next` vs `alpha` (verified-docs, docs page dated 2026-09-09 cites source `0.1.5-alpha.1`, npm latest `0.1.2-rc.1`) — so prerelease identifiers are normal for this tool and the version comparator must tolerate them. **Observed-local:** `~/.local/bin/dsh → ~/.local/lib/node_modules/@deepseek-ai/dsh/lib/bin.js`; `dsh --version` → `0.2.2-rc.1` (parses as `0.2.2-rc.1`, a semver prerelease). **Collision to avoid:** Homebrew core has a formula literally named `dsh` 0.25.10, described as "Dancer's shell, or distributed shell" (verified-docs, Homebrew API) — a completely unrelated project; **do not declare `homebrewFormula: dsh`**. Also do not declare any PyPI package: the PyPI names `deepseek-harness` / `deepseek-harness-cli` were **not** transferred to DeepSeek and belong to a third-party project that also installs a `dsh` command (verified-docs, third-party project README — cited here only as evidence of the collision, not as a source of truth). **M11 implication:** DSH is an npm-managed AI harness; declaring the npm package makes it eligible for the npm path — which is exactly why M11-B's gate matters.

**12 — OMP (Oh My Pi).** **Research blocker adjacent — resolved.** Project **Oh My Pi**, "a fork of Pi by Mario Zechner", built by Stencil Labs; repository `can1357/oh-my-pi`; site `omp.sh` (verified-docs, `github.com/can1357/oh-my-pi` README). npm `@oh-my-pi/pi-coding-agent` 18.19.0, bin `omp → dist/cli.js`, repo `github.com/can1357/oh-my-pi` (verified-docs, npm registry). Homebrew formula **`can1357/tap/omp`** (verified-docs, official README) — a third-party tap, not homebrew-core: the Homebrew API returns 404 for both `omp` and `oh-my-pi` (verified-docs). Standalone install `curl -fsSL https://omp.sh/install | sh`, which fetches a prebuilt binary from `build.stencil.so` and **checks its SHA-256** before installing (verified-docs). Bun install `bun install -g @oh-my-pi/pi-coding-agent` (verified-docs). **Observed-local:** `~/.local/bin/omp` is a 222 MB Mach-O binary reporting `omp/18.19.0` (the bounded token parser yields `18.19.0` — correct); a **second, older copy** exists at `/opt/homebrew/bin/omp → /Users/corvette/Library/Application Support/Tern/omp/versions/18.18.8` reporting `omp/18.18.8` (observed-local). The PATH winner is `~/.local/bin/omp` (18.19.0) because `~/.local/bin` precedes `/opt/homebrew/bin` in the resolved login-shell PATH (observed-local). This is a two-copy, two-version duplicate case that the product's PATH diagnostics exist to surface.

**13 — AGY (Google Antigravity CLI).** **Named research blocker — resolved.** Product **Google Antigravity CLI**; the command is `agy`. Official install on macOS/Linux: `curl -fsSL https://antigravity.google/cli/install.sh | bash`, "Default binary location: `~/.local/bin/agy`"; Windows variants install to `%LOCALAPPDATA%\agy\bin` (verified-docs, `https://antigravity.google/docs/cli/install`, `https://antigravity.google/docs/cli`, `https://antigravity.google/docs/getting-started/`). Verification command `agy --version` (verified-docs). The docs also describe `agy update` for upgrading an existing installation (verified-docs) → known limit, never invoked. A separate Python SDK package `google-antigravity` (pip/uv) exists (verified-docs) but it is the **SDK**, not the CLI, and must not be declared as this tool's package candidate. **Observed-local:** `~/.local/bin/agy` is a 233 MB Mach-O binary reporting `1.5.6`; an **older second copy** at `~/.gemini/bin/agy` reports `1.2.12` and `~/.gemini/bin` is **not** on the login-shell PATH (observed-local) → a genuine `installedNotOnPath` duplicate. **Naming note, stated honestly:** no vendor document uses the product name "AGY"; the mapping AGY → Google Antigravity CLI rests on the official binary name `agy` being Antigravity's documented CLI command (verified-docs) plus the local binary matching that product's version and footprint. This is recorded as owner decision **OD-10** for explicit confirmation rather than asserted silently.

**14 — Grok CLI (xAI).** Executable `grok`. No npm or Homebrew package — M9-A explicitly recorded "Do not invent a Grok npm or Homebrew package" (carried, verified-docs). Information URL `https://docs.x.ai/build/overview`; `x.ai/cli` redirects to `x.ai/build` (carried). **Observed-local:** `~/.grok/bin/grok → ~/.grok/downloads/grok-1.0.77-macos-aarch64` (native binary), and `grok --version` → `grok 1.0.77 (50ca579fa996) [stable]` → token `1.0.77`. M9-A's D-018 recorded version 1.0.52 — the tool has moved, so the M9-A figure is stale and must not be repeated as current. **M11 implication:** keep `packages: []`; add `extraSearchRoots: ["~/.grok/bin"]` (already present) and a known limit for the bracket/hash noise in the version line.

### B.3 Explicit "do not declare" table (same-name, different project)

| Name that looks right | What it actually is | Evidence | Rule |
|---|---|---|---|
| Homebrew formula `dsh` | "Dancer's shell, or distributed shell" 0.25.10 | verified-docs (Homebrew API) | Never declare for DeepSeek Harness |
| npm `goose` 0.0.3 | `jiyinyiyong/goose` — unrelated | verified-docs (npm registry) | Never declare for Goose |
| PyPI `goose` 1.0.0 | "Basic SQL migration tool" | verified-docs (PyPI API) | Never declare for Goose |
| Homebrew formula `goose` | "Go Language's command-line interface for database migrations" | verified-docs (Homebrew API) | Use `block-goose-cli` instead |
| npm `kiro-cli` 0.0.1 | Unrelated placeholder; bin is `kirox` | verified-docs (npm registry) | Never declare for Kiro CLI |
| Homebrew cask `qoder` 0.5.7 | Qoder desktop/IDE ("Agentic coding platform") | verified-docs (Homebrew API) | Never declare for the Qoder **CLI** |
| PyPI `deepseek-harness-cli` | Third-party project that also ships a `dsh` command; PyPI names not transferred to DeepSeek | verified-docs (third-party README) | Never declare for DSH |
| npm `qoder` / `@qoder-ai/qoder` | 404 — not published | verified-docs (npm registry) | Only `@qoder-ai/qodercli` exists |
| npm `@aws/kiro-cli` | 404 — not published | verified-docs (npm registry) | Kiro CLI has no npm package |

### B.4 Open items carried into M11-0 (honest unknowns)

1. `claude --version` output shape — **unverified**.
2. `gemini --version` output shape — **unverified**.
3. `aider --version` output shape — **unverified**.
4. `goose --version` output shape — **unverified**.
5. `kiro-cli --version` output shape **and** install path — **unverified**.
6. Kiro CLI version scheme: docs describe "Kiro CLI 3.0.0 or later" (verified-docs) — the *installed* version string format is unverified.
7. Whether the OpenCode tap formulae `anomalyco/tap/opencode-v2` and `anomalyco/tap/opencode` are still live — carried from M9-A, to be re-verified.
8. Whether Goose's `aaif-goose/goose` release assets are still published under the `stable` tag path — the docs and script agree (verified-docs), but the script body is from a fork copy in the search results; M11-0 should read the canonical script.

---

## C. Capability matrix

### C.1 Where it lives, and why there are two artifacts

- **Source of truth (machine-readable):** `Sources/AgentLensCore/Detectors/CapabilityMatrix.json`, `schemaVersion: 1`, sitting beside `DefaultDetectors.json` inside the existing Core resource bundle. It is bundled so the app can read it **offline** and enforce the gate without any network call. It is a *declarative* file: no code reads it conditionally per tool.
- **Published artifact (human-facing):** `docs/CATALOGUE.md`, **generated** from the two JSON files by `scripts/render-catalogue.py`. CI regenerates it and fails on any byte difference, so the published matrix cannot drift from the shipped data. This is the "kept truthful" mechanism: a single source, a deterministic renderer, a CI diff gate.
- **In-app surface:** none in M11. M12 renders the matrix in the Overview/category UI. M11 delivers the data and the gate; M12 delivers the presentation. That keeps the M11/M12 boundary clean (ROADMAP M11 is "detection + contributor foundation"; M12 is "complete native diagnostic and operation workflow").

### C.2 Proposed record shape

```json
{
  "schemaVersion": 1,
  "entries": [
    {
      "id": "codex",
      "category": "aiAgent",
      "state": "enabled",
      "latestCheck": { "support": "supported", "manager": "npm", "source": "npm registry dist-tag" },
      "update":      { "support": "supported", "manager": "npm" },
      "uninstall":   { "support": "supported", "manager": "npm" },
      "testedLayouts": ["npmGlobal"],
      "knownLimits": [
        "npm optional-dependency install failure yields an unknown version, not an error"
      ]
    },
    {
      "id": "agy",
      "category": "aiHarness",
      "state": "informational",
      "latestCheck": { "support": "unsupported", "reason": "no package registry — installed by a vendor script" },
      "update":      { "support": "informational", "reason": "no manager adapter for script installs (M13–M15)" },
      "uninstall":   { "support": "informational", "reason": "no manager adapter for script installs (M13–M15)" },
      "testedLayouts": ["nativeInstaller"],
      "knownLimits": ["vendor self-updater (agy update) is never invoked by Agent Lens"]
    }
  ]
}
```

### C.3 Rules

1. **Fail closed.** A detector id with no matrix row gets **no** update, **no** uninstall and **no** latest probe. A matrix row with no matching detector id is a validation error naming the id.
2. **Every non-`supported` value carries a non-empty reason.** The reason is user-facing text, shown in the CLI and the app, and it must name the *cause*, not a placeholder ("no manager adapter delivered (M13)" is acceptable; "n/a" is not).
3. **`state`** summarises the entry: `enabled` (a delivered capability applies), `informational` (detected and described, but no action), `disabled` (declared but not surfaced — reserved for an entry whose identity is not yet trustworthy). `informational` and `disabled` both require a reason.
4. **Declared package candidates are never ownership proof.** The matrix records a *manager* for a supported capability; the runtime proof remains the M9 ownership verification.
5. **`testedLayouts` is a closed vocabulary** matching the fixture layouts the registry actually exercises. A layout the matrix lists but no fixture covers is a validation error — the matrix must never over-claim.
6. **`knownLimits` are specific facts**, e.g. "the npm package publishes a second executable name (`opencode2`)", "the version line contains a release date and a commit id after the version token", "the Homebrew package name retains the former vendor name".
7. **The matrix is additive to the registry, not a replacement.** The registry stays the detector definition; the matrix stays the capability statement. A tool appears in the app exactly when it is in the registry.

### C.4 How informational-only entries are marked

In the **CLI**: the entry is listed with its category and a capability line such as `Update: informational — no manager adapter for script installs (M13–M15)`. In the **app**: the Update/Uninstall controls are absent and the reason is shown as static text in the tool detail. **No control is ever shown disabled-but-present for an unsupported capability** — that invites a click that can only fail.

---

## D. Contributor foundation

### D.1 What must exist so a new tool is a data-only contribution

1. **`docs/CONTRIBUTING.md`** — the contract. It must contain: (a) the exact files to edit (`Sources/AgentLensCore/Detectors/DefaultDetectors.json`, `Sources/AgentLensCore/Detectors/CapabilityMatrix.json`, and the fixture in `Tests/AgentLensCoreTests/`); (b) the required fields and the vocabulary of each enum; (c) the evidence rules — every package identity and every version behaviour needs a primary source, and the source URL is recorded in the PR description; (d) the rule that a **fixture proves the detector, never a real installation**, and that an unobserved layout must not be labelled verified; (e) the rule that a declared package candidate is never ownership proof; (f) the license, once chosen; (g) a PR checklist naming the exact local commands.
2. **A validating script** — `scripts/validate-catalogue.py`, runnable offline, deterministic, exit 0 / non-zero with a named message. It checks: registry↔matrix id-set equality; every matrix row's required fields; non-empty reasons for every unsupported capability; HTTPS link shape; package-name shape per manager; every `testedLayouts` value having a fixture; every detector having a version query. A contributor's PR fails in CI before a human reads it.
3. **A generator** — `scripts/render-catalogue.py` → `docs/CATALOGUE.md`, plus the CI regenerate-and-diff step. The published matrix is therefore always true by construction.
4. **A fixture convention** — one synthetic layout per detector, plus a table-driven test that every bundled detector has a fixture that constructs its layout and asserts the declared state and source. The current per-layout switch in `Tests/AgentLensCoreTests/DetectorRegistryTests.swift:177-207` is the natural place to extend; adding a layout must not require touching the scanner.
5. **A documented "no source changes needed" proof** — the contribution guide names the exact commands that demonstrate it, and the acceptance gate (§E) runs them on a synthetic fifteenth tool.
6. **A schema-validation CI behaviour** — an invalid registry or matrix must fail the hosted CI with a named error and a non-zero exit, never a warning.

### D.2 License gate — recommendation and tradeoff (the choice remains the owner's)

**Constraint.** ROADMAP M11 and §7 require the owner to choose **MIT** or **Apache-2.0** *before* public contribution invitations* and **no later than M18**. The repository currently has **no LICENSE file** (observed on the author's machine, 2026-11-12). DECISIONS.md records no license decision to date.

| | MIT | Apache-2.0 |
|---|---|---|
| Length / contributor friction | ~1 page, near-universal familiarity for individual contributors | ~11 pages, legal review more often requested by contributors |
| Patent grant | None | Express grant; patent-retaliation clause |
| Notice obligations | Attribution only | `NOTICE` propagation for redistributed code |
| Corporate adoption comfort | Lower | Higher — many companies require Apache-2.0 internally |
| Dependency/licensing interaction | Simple | Explicit patent + termination clauses, safer for a project that may grow |

**Recommendation: MIT.** Reasons specific to *this* project: (a) the codebase is a zero-dependency native Swift 6 app with a small surface and a narrow contributor audience — the Apache-2.0 patent and NOTICE machinery buys protection that a solo-maintained macOS utility is unlikely to need; (b) MIT's one-page text maximises the chance that an outside contributor ships a detector without a legal round-trip, which is precisely the M11 goal; (c) the repository's existing style and the surrounding ecosystem of comparable macOS CLIs lean permissive/MIT.

**Counter-consideration to weigh:** if the owner expects contributions from a company whose legal policy requires an inbound patent grant, Apache-2.0 is the safer choice; choosing later is possible (licence can be changed for new contributions), but relicensing an existing codebase requires contributor consent, so choosing early is strictly cheaper.

**Timing recommendation.** Although the deadline is M18, the license should be decided **during M11** — M11 is the phase that builds the contributor foundation, and publishing a contribution guide that names no license is a defect. This is owner decision **OD-1**; this proposal does not select a license.

---

## E. Acceptance strategy

### E.1 Per-phase gates

Every phase must produce: the exact commands run, raw stdout/stderr/exit status, a SHA-256 manifest of every changed file, an explicit list of *unverified* observations (especially anything native/UI the implementer could not personally observe), and a written report. The implementer's PASS is a candidate, not acceptance (D-014).

- **M11-0:** every identity field carries one evidence mark and a URL for `verified-docs`; an independent re-read of every cited URL agrees with the claim; the open-items list in §B.4 is either closed or restated with a reason; the packet is hash-frozen.
- **M11-A:** new invalid shapes each produce a named error; the bundled matrix loads and matches the bundled detectors; the existing schema-2 rejection behaviour is unchanged; full `swift test` exit 0; Core/UI import guard exit 0.
- **M11-B:** flipping one matrix row to `informational` produces **zero** child processes from the injected runner, no enabled operation control, and the identical reason string in CLI and app; `codex` npm update/uninstall behaviour is byte-for-byte unchanged from M10 acceptance; full suite exit 0; a native click-through in the built app confirms the informational entry shows its reason and offers no destructive control.
- **M11-C/D/E:** every new detector has a fixture asserting state and source; every matrix row matches its detector; the CLI and the app report the same category, candidates, links and version for each entry; the catalogue-pinning assertion is replaced by set-based assertions; full suite exit 0; app build and packaging exit 0.
- **M11-F:** the validator exits 0 on the committed tree and non-zero with a named message on each seeded corruption; `docs/CATALOGUE.md` regenerates byte-identically; the CI step fails on a hand-edited `docs/CATALOGUE.md`.
- **M11-G:** the combined gate below.

### E.2 Combined M11 gate

1. **Validated fixture per named entry.** All 14 entries have a fixture that constructs the declared layout and asserts `installedAndOnPath` + the declared source. A missing or skipped fixture fails the gate.
2. **Measured version behaviour where available.** For every entry whose version shape was measurable, the measured raw first line and the extracted token are recorded in the evidence root and asserted by a fixture. For entries that remain `unverified` (the five in §B.4), the matrix states the limit and the rendered version is `—` (unknown), never a guess. A fixture asserts that a tool whose `--version` exits non-zero (the observed Codex case) yields unknown rather than an error.
3. **CLI/app fact agreement.** For every entry, the CLI output and the app's tool detail agree on: display name, category, declared package candidates, official links, detected state, source label, and version. The comparison is mechanical (a recorded transcript diff), not visual.
4. **Data-only contribution proof.** A synthetic fifteenth tool is added by editing **only** `DefaultDetectors.json`, `CapabilityMatrix.json` and one fixture. The build succeeds, the CLI and the app show it, and the diff shows **no** change under `Sources/AgentLensCore/Detection/`, `Sources/AgentLensCore/Ownership/`, `Sources/AgentLensCore/Operations/`, `Sources/AgentLensAppSupport/` or `Sources/AgentLensApp/`. The change is then reverted. This is the direct proof of ROADMAP M11's acceptance clause and of D-010.
5. **Schema-validation CI behaviour.** Deliberately malformed registry and matrix inputs (missing schemaVersion, schemaVersion 1 and 3, unknown category, unknown layout, duplicate id, missing reason on an unsupported capability, registry/matrix id mismatch) are each rejected with a named message and a non-zero exit, in the bundled loader and in the offline validator.
6. **Existing hosted gates, all seven, at the exact candidate SHA.** Guard (Core/UI import boundary), the 21 guard behavioural fixtures, package build, the early native-macro isolation capability gate, the full Swift test suite, the fresh debug development app build, and all nine packaging checks. Each with its receipt. (Gate names taken from `.github/workflows/ci.yml`; the seven-gate set is the M10-B/C/D accepted set.)
7. **Matrix/renderer agreement.** `docs/CATALOGUE.md` regenerates byte-identically from the committed JSON, and every column ROADMAP M11 requires is present.
8. **Native spot-check.** The built app is launched and the fourteen entries are inspected for category, links, and the presence/absence of operation controls — the parent observes it personally, and any entry the parent could not observe is recorded as unverified rather than passed.

### E.3 Explicitly NOT acceptance targets

- **Personal installations.** No acceptance step may depend on, modify, or depend on the state of the author's personal tools. The author's machine is a *read-only observation source* (marked `observed-local`), never an acceptance environment. Where a disposable environment is used, it must be created and destroyed inside the phase evidence root.
- **Unobserved real layouts labelled verified.** A layout that was never measured must be recorded as `unverified` with the reason. A fixture proves the detector logic, not the existence of a real installation.
- **Mutation adapters.** M11 adds no Homebrew/uv/Cargo/Python mutation capability. The npm path delivered in M10 stays exactly as accepted; M11 must not broaden it beyond what the matrix marks supported.
- **M12 UI work.** No category navigation, no update filters, no counts, no conflict summary, no VoiceOver/keyboard work. The M12 boundary is not crossed.
- **Public contribution invitations and release.** Nothing in M11 publishes anything or invites anyone. The license decision is recorded, not enacted.
- **Third-party package updates.** M11 does not update, install, or remove any tool anywhere.
- **Newest-version claims for standalone tools.** "Latest" stays unknown for entries with no registry (D-007); M11 does not add a latest-probe source for them.

---

## F. Risks and open questions

### F.1 Ranked risks

1. **High — silent expansion of the mutation surface.** Adding npm-distributed entries makes them npm-eligible through a generic verifier, with no per-tool accepted evidence. *Mitigation:* M11-B's fail-closed capability gate; per-entry matrix rows defaulting to `informational` until individually accepted; the M10 `codex` journey proven unchanged.
2. **High — name collisions turning into wrong mutation targets.** `dsh`, `goose`, `kiro-cli` and `qoder` each collide with an unrelated project or a different product (§B.3). A wrong `packages` entry is harmless today and dangerous the moment an adapter lands. *Mitigation:* the explicit do-not-declare table in the frozen identity packet; the gate in M11-B; M9 ownership re-verification before any future execution.
3. **High — unverified version shapes presented as versions.** Five tools have unverified `--version` shapes; a wrong guess produces a confidently wrong version. *Mitigation:* measure in a disposable environment (M11-0); where not measurable, the entry renders `—`; the matrix lists the limit; a fixture asserts unknown-on-nonzero-exit.
4. **Medium-high — source misclassification.** `classifySource` (`ToolDetector.swift:187-191`) knows only npm, brew and standalone, so a uv/pip install (Aider via uv, Hermes via PyPI) is reported as `standalone`, and a shim copy (`~/.local/shims/cline`) is reported as `standalone` although it fronts an npm package. *Mitigation:* OD-3 decides explicitly between extending the classifier and relabelling; either way the matrix records the limitation for those entries rather than leaving the app quietly wrong.
5. **Medium — layout drift.** Real installs vary by prefix, shim, versioned runtime directory and vendor script (observed-local: `~/.local/shims`, `~/Library/Application Support/Tern/omp/versions/18.18.8`, `~/.qoder/bin/qodercli/qodercli-1.1.88`, `~/.gemini/bin/agy`, `~/.grok/downloads/…`). *Mitigation:* `extraSearchRoots` per entry covering observed roots; the matrix's `testedLayouts` states exactly what is tested; drift is a known limit, not a silent failure.
6. **Medium — fixture realism.** Synthetic fixtures cannot prove a real installation exists. *Mitigation:* the matrix distinguishes fixture-verified from observed; the contribution guide states the rule; "verified" is only claimed for measured layouts.
7. **Medium — scope creep into M12/M13–M15.** Category navigation, filters, counts, new manager adapters and self-update invocations are all adjacent and tempting. *Mitigation:* the non-goals in §G and per-phase allow-lists; `DO NOT TOUCH` binding.
8. **Medium — the catalogue-pinning test.** `DetectorRegistryTests.swift:82` asserts exactly three ids; it must become set-based or it blocks the milestone. *Mitigation:* explicitly in M11-C's scope.
9. **Low-medium — schema-version semantics.** Adding enum values to schema 2 without a version bump could look like a silent schema change to contributors. *Mitigation:* record it as a new DECISIONS entry (D-021) documenting the additive change; keep the strict unknown-version rejection; state the additive rule in the contribution guide.
10. **Low-medium — package-name validation over-restriction.** The current per-manager patterns are conservative; a wrong extension would reject a legitimate name (e.g. a PyPI name with a dot, or a crate name with an underscore). *Mitigation:* each new manager pattern gets positive and negative tests drawn from the real catalogue names in §B.1.
11. **Low — capability-matrix rot.** A hand-maintained matrix drifts from reality. *Mitigation:* single source of truth + generated artifact + CI regenerate-and-diff + registry↔matrix id equality test.

### F.2 Decisions only the owner can make

| ID | Decision | Recommendation | Deadline |
|---|---|---|---|
| OD-1 | **License: MIT or Apache-2.0** | **MIT** (tradeoff in §D.2); the choice is the owner's | Before public invitations, ≤ M18 — recommend deciding in M11, since M11 publishes the contributor guide |
| OD-2 | Does M11 extend the declared-package vocabulary with `uv`/`pip`/`cargo`, or keep npm/brew only and record the rest as matrix text? | Extend with `uv` and `cargo` as **candidates only** (no adapters), because Aider/Hermes/Goose have real identities there; keep `pip`/`pipx` as layout-only until M14 defines ownership | M11-A dispatch |
| OD-3 | Does M11 extend `classifySource` with uv/cargo path rules, or keep npm/brew/standalone and mark those entries' source as heuristic? | Keep the classifier as-is in M11 and state the limitation in the matrix; extend it in M14/M15 with the adapters that can verify ownership. Rationale: a source label without ownership proof is exactly what §6 forbids | M11-A dispatch |
| OD-4 | Which executable identifies Qoder — `qoder` (dispatcher) or `qodercli` (runtime) — and should one tool support several executables (Qoder, Hermes, OpenCode each ship 2–3)? | Detect `qoder` (the command a user runs) and declare `qodercli` as an **alternate executable**; add an `alternateExecutableNames` field to the registry rather than duplicating entries | M11-0 / M11-A |
| OD-5 | Is the capability matrix an enforced fail-closed gate, or advisory metadata? | **Enforced, fail-closed** — otherwise it is decoration and the M11 safety gap in risk 1 remains open | M11-B dispatch |
| OD-6 | Are new npm entries (Claude Code, Gemini CLI, Cline CLI, DSH, Qoder CLI) offered npm Update/Uninstall immediately, or informational until each is individually accepted? | **Informational by default**, each promoted to supported after its own accepted npm scenario — matching the M10 discipline of one accepted tool at a time | M11-C dispatch |
| OD-7 | Approve the two-artifact matrix design (JSON source of truth in the Core bundle + generated `docs/CATALOGUE.md`)? | **Approve as proposed**; a single hand-written document cannot be kept truthful | M11-A dispatch |
| OD-8 | Does M11 include source/git layouts (Hermes) as a first-class layout? | **Yes, as informational only** — a git checkout has no manager ownership, and the user's `installedNotOnPath` case must still be visible | M11-E dispatch |
| OD-9 | May M11 ship an entry (Kiro CLI) whose install path is unverified? | **Yes**, limited to the PATH-resolved binary, with the limit stated in the matrix; do not guess a directory | M11-D dispatch |
| OD-10 | Confirm that "AGY" in scope §2.3 means **Google Antigravity CLI** | Confirm; no vendor product is named "AGY", but the official Antigravity CLI binary is `agy` (verified-docs) and the local binary matches | M11-0 |

---

## G. Explicit non-goals for M11

- **No new manager mutation adapters.** No Homebrew, uv/pip, Cargo or script-installer mutation. M13–M15 own those.
- **No M12 UI/workflow work.** No category navigation, update filters, counts, conflict summary, search/selection rework, keyboard/VoiceOver work, cached launch or menu bar.
- **No speculative scanner refactor.** Search-root handling, detection order, ownership verification and the M10 operation machinery keep their current shape. The only permitted Core behaviour change is the `classifySource` outcome that OD-3 explicitly approves.
- **No per-tool bespoke shell scripts.** No wrapper scripts per tool, no tool-specific version parsing, no tool-specific detection code. Everything is a registry/matrix data change plus the shared vocabulary.
- **No license choice made on the owner's behalf.** §D.2 gives a recommendation and a tradeoff; the decision is OD-1.
- **No changes to the M10 npm journey's semantics.** No new operation type, no retry, no rollback, no batch update, no hidden refresh.
- **No public contribution invitation, no release, no signing, no publication.** The license decision may be *recorded*; nothing is published.
- **No install/update/uninstall of any tool on any machine, including this one.** All local inspection in this proposal was read-only.
- **No subagents and no second CLI.** This proposal was produced by one council member, alone.

---

## Appendix 1 — Local observation log (read-only, 2026-11-12)

Machine: macOS (Darwin 27.0.0, arm64). Commands used: `command -v`, `which -a`, `readlink -f`, `file -b`, `ls -l`, `cat` of a 76-byte launcher script, `git remote -v` / `cat .install_method`, `--version` with a 25 s alarm, `npm ls -g --depth=0`, `npm view`, `npm search`, `uv tool list`, `brew list`, and HTTP GETs against the npm, PyPI and Homebrew public registry APIs. No mutating subcommand of any manager was invoked; nothing was installed, updated or removed.

| Observation | Result |
|---|---|
| Executables on PATH | `codex`, `hermes`, `cline`, `qoder` (via `~/.qoder/entry`), `qodercli`, `dsh`, `omp`, `agy`, `grok`, `pi`; **not** on PATH: `claude`, `gemini`, `opencode`, `aider`, `goose`, `kiro-cli` |
| npm globals (prefix `~/.local`) | `@deepseek-ai/dsh@0.2.2-rc.1`, `@openai/codex@0.167.2`, `cline@3.0.74`, plus unrelated packages |
| Version outputs | `codex` → **fails** (missing `@openai/codex-darwin-arm64`, non-zero exit) · `hermes` → `Hermes Agent v0.23.1 (2026.9.24) · stable · local 3b4215785882` · `cline` → `3.0.74` · `qoder`/`qodercli` → `1.1.88` · `dsh` → `0.2.2-rc.1` · `omp` → `omp/18.19.0` · `agy` → `1.5.6` · `grok` → `grok 1.0.77 (50ca579fa996) [stable]` |
| Version-query latency | 0.02–0.78 s for all measured tools — far inside the 3 s budget (`ToolDetector.versionTimeout`) |
| Duplicate copies on PATH | `cline` ×3 (`~/.local/bin`, `~/.local/shims`, `/opt/homebrew/bin`) · `omp` ×2 (**18.19.0** at `~/.local/bin` vs **18.18.8** at `/opt/homebrew/bin` → `~/Library/Application Support/Tern/omp/versions/18.18.8`) · `dsh` ×2 (same version, two npm prefixes) |
| Off-PATH copies | `~/.opencode/bin/opencode` (231 MB) — `~/.opencode/bin` absent from the login-shell PATH → `installedNotOnPath`; `~/.gemini/bin/agy` **1.2.12** vs PATH copy **1.5.6** — `~/.gemini/bin` also absent from PATH |
| Install roots present | `~/.local/bin`, `~/.local/shims`, `~/.opencode/bin`, `~/.grok/bin`, `~/.grok/downloads`, `~/.cargo/bin` (Rust toolchain only, no AI CLI), `~/.local/share/uv/tools` (`skill-lens-cli`, `trafilatura` — unrelated), `~/.hermes/hermes-agent` (git checkout), `~/.qoder/`, `~/.kiro/skills` (no CLI binary) |
| Homebrew (read-only listing) | casks `codex`, `claude-code`, `qoder`, `block-goose`; formulae `gemini-cli`, `aider`, `cline`, `hermes-agent`, `block-goose-cli`. The core formulae `goose` and `dsh` exist upstream but are **unrelated projects** and are not installed here |
| Registry API cross-check | `block-goose-cli` 1.59.0 · `hermes-agent` 0.22.4 · `cline` 3.0.3 · `gemini-cli` 0.68.0 · `aider` 0.86.2 · cask `codex` 0.167.2 · cask `claude-code` 2.1.311 · cask `qoder` 0.5.7 · 404 for `omp`, `oh-my-pi`, `qoder` (npm), `@aws/kiro-cli`, `@qoder-ai/qoder` |
| Repo state | `main` = `d0a2b417e8c7d05f3c715a24e93f17851f7ab904` (matches the council brief); `briefs/M11-planning/` untracked; no LICENSE file; one CI workflow (`.github/workflows/ci.yml`) with the seven gates; `scripts/` = `build-dev-app.py`, `check-core-ui-imports.py` |

## Appendix 2 — Sources relied on

npm registry (npmjs.com package metadata) · PyPI JSON API (pypi.org) · Homebrew API (formulae.brew.sh/api) · `github.com/openai/codex` · `developers.openai.com/codex/cli` · `code.claude.com/docs/en/troubleshoot-install` · `docs.claude.com/en/docs/claude-code/setup` · `support.claude.com/en/articles/14552382-your-first-day-in-claude-code` · `github.com/google-gemini/gemini-cli` · `geminicli.com` · `opencode.ai/v2/docs/` · `github.com/cline/cline` · `docs.cline.bot/getting-started/installing-cline` · `docs.cline.bot/usage/cli-overview` · `cline.bot/cli` · `aider.chat/docs/install.html` · `github.com/Aider-AI/aider` · `goose-docs.ai/docs/getting-started/installation/` · `github.com/aaif-goose/goose` · `github.com/block/goose/releases/download/stable/download_cli.sh` (script body, also mirrored in a fork copy) · `kiro.dev/docs/cli/` · `kiro.dev/docs/cli/installation/` · `kiro.dev/docs/getting-started/installation/` · `docs.qoder.com/cli/installation` · `docs.qoder.com/cli/overview` · `qoder.com/en/cli` · `docs.qoder.com/qoderwake/cli-reference` (scope exclusion only) · `deepseekdocs.com/en/docs/user-guide/cli` · `deepseekdocs.com/en/docs/getting-started/quickstart` · `github.com/deepseek-ai/deepseek-harness/blob/master/apps/cli/README.md` · `github.com/can1357/oh-my-pi` (README) · `omp.sh` · `antigravity.google/docs/cli/install` · `antigravity.google/docs/cli` · `antigravity.google/docs/getting-started/` · `github.com/NousResearch/hermes-agent` · `hermes-agent.nousresearch.com/docs/getting-started/installation` · `hermes-agent.nousresearch.com/install.sh` · `github.com/NousResearch/hermes-agent/blob/v0.21.6/website/docs/reference/cli-commands.md` · `docs.x.ai/build/overview` (carried from the M9-A verified packet) · third-party project README for `HenryZ838978/deepseek-harness` (used **only** as evidence of the `dsh` name collision, not as a source of truth) · in-repo `ROADMAP.md`, `DECISIONS.md`, `AGENT_LENS_SCOPE.md`, `briefs/README.md`, `briefs/M9-A-detector-metadata.md`, `Sources/AgentLensCore/Detection/*.swift`, `Tests/AgentLensCoreTests/*.swift`, `.github/workflows/ci.yml`.
