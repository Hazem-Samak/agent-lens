# M11 proposal — Grok (planning council)

Date: 2026-11-12. Member: Grok. Output file: `briefs/M11-planning/proposal-grok.md`.
This proposal was written without reading `proposal-minimax.md`. It does not edit product code, choose a license, or name an implementer.

Authority for the milestone is ROADMAP.md §4 (M11 detection and contributor foundation; M12 is the native workflow boundary; M13–M15 are the Homebrew, uv, and Cargo mutation adapters). Settled decisions D-001…D-020 are not reopened. `main` is the council brief’s cited head `d0a2b417e8c7d05f3c715a24e93f17851f7ab904` after PR #1 merge `65f7a82`. This member did not re-run git.

Fact marks used below:

- **verified-docs** — a primary vendor doc, official repo, or official package listing read in this council assignment.
- **observed-local** — a read-only measurement on this machine on 2026-11-12 (`command -v` / `which -a`, `--version` / `--help`, `file`, or reading an already-installed `package.json`). Nothing was installed, updated, uninstalled, or mutated. No `brew install`, `brew update`, `npm install`, or other mutating manager command was run. `brew info` was not run.
- **unverified** — not confirmed. A coding phase must not turn an unverified fact into a registry field.

The current registry is schemaVersion 2 with three detectors: `codex` (fixture `npmGlobal` / `npm`), `opencode` (`singleDirectory` / `standalone`), `grok` (`singleDirectory` / `standalone`). All three are `aiAgent`. Known layouts are `npmGlobal`, `singleDirectory`, `brewCellar`. Known sources are `npm`, `brew`, `standalone`. Declarable managers are only `npm`, `homebrewFormula`, and `homebrewCask`. A declared package is not ownership. `classifySource` returns `npm` when the resolved path contains `/lib/node_modules/`, `brew` when it contains `/Cellar/`, and `standalone` otherwise (`Sources/AgentLensCore/Detection/ToolDetector.swift`). The version token is the first match of `[0-9]+(\.[0-9]+){1,3}(-[0-9A-Za-z.]+)?`. Homebrew formula and cask names are one component or three `user/repo/name` components, each matching `^[A-Za-z0-9][A-Za-z0-9._+@-]*$` (`DetectorMetadata.swift`). That class includes `@`, so a single-component name such as `claude-code@latest` matches the current validator. The implementer still proves it by loading the JSON, rather than by this reading alone.

---

## A. Phase decomposition

One milestone branch for every phase. Suggested name: `milestone/m11-catalogue`. The owner confirms the name (decision 10). Phases run in order. One implementer writes each phase. Reviewers stay read-only. The orchestrator runs acceptance (D-013, D-014, briefs/README.md). Research is M11-A and is not folded into a coding phase.

Shared protected set, every phase:

- `DECISIONS.md`, `ROADMAP.md`, `AGENT_LENS_SCOPE.md`, historical files under `briefs/` (except the new identity doc in A and the new contributor doc in E), and everything under `walkthroughs/`.
- `Package.swift` (zero dependencies stays).
- `Sources/AgentLensApp/**` (SwiftUI, navigation, tool list, tool detail, diagnostics). M12 owns workflow UI.
- Detection, ownership, and operation behavior: `ToolDetector.swift`, `DetectorMetadata.swift`, `DetectorRegistry.swift`, npm ownership, Homebrew latest-check, and any Update/Uninstall adapter. M11 may add registry JSON and tests that call the existing APIs. M11 may not change classification, version parsing, or mutation behavior.
- `scripts/**`, except that no phase is authorized to change them. `scripts/build-dev-app.py` already accepts `registry_count=<digits>`; it does not hardcode 3.
- A `LICENSE` file. The owner chooses MIT or Apache-2.0 later (decision 6).

If an implementer finds a SwiftUI or scanner change that seems required, the phase stops. The orchestrator decides whether that work is a later milestone.

### M11-A — Identity freeze

**Goal.** Write `docs/catalogue-identities.md`, a row-by-row freeze of section B of this proposal. Re-check only the open flags listed in this phase, read-only. Coding phases may copy a row only after this file marks that row frozen.

**Non-goals.** No edit to `DefaultDetectors.json`. No new detector. No install. No resolution of DSH by guesswork. No license file. No matrix. No scanner or UI change.

**Allow-list.**

- `docs/catalogue-identities.md` (new).

**Protected.** The shared set, plus `Sources/`, `Tests/`, `.github/`, `README.md`, and `scripts/`.

**Work the implementer actually does.**

1. Copy each section B row into the freeze doc with its URL and mark. Do not upgrade a mark.
2. Read-only re-check, then record the result:
   - `https://formulae.brew.sh/formula/gemini-cli` — **unverified** in this proposal. Freeze `homebrewFormula` `gemini-cli` only if that page exists and names binary `gemini`. The install sentence on `https://geminicli.com/docs/get-started/installation/` is already **verified-docs** and is not, by itself, the listing page.
   - Aider version query. This proposal did not find a `--version` sentence on `https://aider.chat/docs/install.html`. Read the official CLI reference. If the flag, stream, and line are still absent, mark the version query **unverified** and hold Aider out of M11-C. `aider` was not on PATH here, so there is no local measurement to copy.
   - Kiro package kind. Re-read `https://kiro.dev/docs/getting-started/installation/`. This proposal already found conflicting formula-vs-cask sentences. If both sentences remain, packages stay empty.
   - DSH. Record the DeepSeek Harness candidate and the owner question. Optional read-only `brew info dsh` may show whether a formula name exists. A formula hit is not identity. Do not add a package.
   - Qoder command name. Record both official wordings. Do not pick for the registry. Decision 4 picks.
   - Codex information URL. `https://developers.openai.com/codex/cli` redirected, in this assignment, toward `https://learn.chatgpt.com/docs/codex/cli`, and that fetch did not return an install body. Keep the current registry URL unless the re-check finds a stable install page. The GitHub README remains the install authority either way.
3. Fetching an official install-script URL to read it is allowed. Executing it is not. If a script’s destination directory is not in the fetched text, `extraSearchRoots` stays empty for that tool.

**Acceptance.** Orchestrator citation review, not a Swift test. Evidence is the freeze doc: every catalogue id has a vendor, executable, category, package list (possibly empty), fixture layout, version-query status, URLs, and marks. Rows that are held say `held` and name the decision number. No other file changes (`git diff --stat` shows only the new doc).

**Depends / stop.** Depends on nothing in M11. Stop if a re-check contradicts a **verified-docs** claim in this proposal and the contradiction cannot be resolved from two primary URLs. Stop rather than picking a winner. DSH remaining an owner question is a successful A, not a failure.

**Model tier.** Strongest reasoning (§29.6). The risk is a wrong package name, not typing volume.

### M11-B — Settled registry batch

**Goal.** Add Claude Code, Gemini CLI, and Cline CLI, and apply the frozen corrections for Codex, OpenCode, and Grok CLI. After this phase the bundled registry loads, each shipped id has one synthetic fixture, and CI’s required-passed anchor names a real test function.

**Non-goals.** No Aider, Goose, Kiro, Hermes, Qoder, DSH, OMP, or AGY. No new layout. No mutation adapter. No UI. No floor-number change. No desktop cask `opencode-desktop`. No Cline shim path. No version pins.

**Allow-list.**

- `Sources/AgentLensCore/Detectors/DefaultDetectors.json`
- `Tests/AgentLensCoreTests/DetectorRegistryTests.swift` (the bundled-id test and any new schema assertion for `claude-code@latest`; the synthetic fixture loop already walks every definition)
- `Tests/AgentLensCoreTests/BundledRegistryResourceTests.swift` (the assertion at the bundled id list; leave the unrelated `zeta-fixture` / `alpha-fixture` case alone)
- `Tests/AgentLensAppSupportTests/BundleResourceTests.swift` (id and `executableName` lists only)
- `Tests/AgentLensCoreTests/UpdateCLIIntegrationTests.swift` (the assertion `Set(detectorCalls) == Set(["codex", "opencode", "grok"])` and any sibling that assumes those three are the entire default set)
- `Tests/Packaging/test_dev_app_bundle.py` (the full-registry id list and the matching `registry_count=3 registry_ids=codex opencode grok` preflight expectation). Do not rewrite the separate two-id fixture expectation (`registry_count=2 registry_ids=opencode codex`).
- `.github/workflows/ci.yml` — only the `CORE_ANCHORS` entry `bundledDefaultDetectorsIsValidWithThreeTools`, and any comment that would become false if it still says the test is the three-tool function. Do not change floor numbers (Core 456, AppSupport 79, total 535, guard-fixtures 21, packaging 9).
- `README.md` — one sentence: `verify-installation` accepts the registry ids shipped at the end of this phase, not a hardcoded trio. Do not rewrite the README.

**Protected.** The shared set. Also every source file under `Sources/` except the registry JSON. App Swift sources currently take `executableName` from the loaded definition (`ToolListView.swift`, `ToolDetailView.swift`, `DiagnosticsView.swift`) and the preflight line prints `loadedDefinitions.count` (`AgentLensApp.swift`). If a later reading finds a hardcoded trio in an app screen, stop. That discovery is not permission to start M12.

**Registry rows to add, only if A froze them.** Order stays the existing three first, then the new agents, so the diff stays reviewable. Ids equal `executableName`.

| id | displayName | category | fixture | packages | extraSearchRoots | versionQuery |
|---|---|---|---|---|---|---|
| `claude` | Claude Code | `aiAgent` | `singleDirectory` / `standalone` | npm `@anthropic-ai/claude-code`; cask `claude-code`; cask `claude-code@latest` | `~/.local/bin` | `--version`, stdout, first. Stream is **unverified** (binary not installed). Unknown version is acceptable. |
| `gemini` | Gemini CLI | `aiAgent` | `npmGlobal` / `npm` | npm `@google/gemini-cli`; formula `gemini-cli` only if A marked the formula listing **verified-docs** | none | `--version`, stdout, first. Stream **unverified**. Do not pin `0.64.0`. |
| `cline` | Cline CLI | `aiAgent` | `npmGlobal` / `npm` | npm `cline` | none | `--version`, stdout, first. **observed-local** stdout `3.0.74` on this machine. Do not pin that version in JSON. |

Corrections, not new products:

- Codex. Keep npm `@openai/codex` and cask `codex`. Keep fixture `npmGlobal` / `npm`. Keep `extraSearchRoots` `~/.local/bin`. Standalone `https://chatgpt.com/codex/install.sh` is documented in the identity doc and is not a second fixture. Do not delete the cask because local copies happened to be npm layouts. Do not add an unrelated cask named `opencodex`.
- OpenCode. Add `homebrewFormula` `opencode` (homebrew-core, one component). Keep npm `@opencode/cli` and `opencode-ai`, and formulae `anomalyco/tap/opencode-v2` and `anomalyco/tap/opencode`. Keep the uninstall URL and the `singleDirectory` / `standalone` fixture. Do not add cask `opencode-desktop`.
- Grok CLI. No package, no URL, and no `extraSearchRoots` change. Empty `packages` stays. D-018’s `1.0.52` is a historical measurement. This machine printed `grok 1.0.77 (...)`. Do not pin `1.0.77` and do not invent `grok update` or an npm/Homebrew name.

Information URLs, all HTTPS:

- Claude Code: `https://code.claude.com/docs/en/setup`
- Gemini CLI: `https://geminicli.com/docs/get-started/installation/`
- Cline: `https://docs.cline.bot/cline-cli/installation`
- Codex and Grok: unchanged unless A froze a replacement Codex URL.
- OpenCode: keep `https://opencode.ai/v2/docs/`.

**Test contract.** Rename `bundledDefaultDetectorsIsValidWithThreeTools` to `bundledDefaultDetectorsMatchFrozenCatalogue` in the same phase as the `CORE_ANCHORS` edit. The new function asserts the exact id list shipped by this phase, the new fixtures, categories, and packages, and that `claude-code@latest` validates. Keeping the old function name while the list grows leaves a dishonest CI anchor. `bundledFixtureDefinitionsMatchSyntheticLayouts` must stay green for every bundled definition, including the new ones. `addingAFourthDefinitionRequiresNoSourceChanges` stays as the Swift-constructor proof; the JSON-only proof is M11-E. Update the other allow-listed assertions to the same id list. Assert the exact set. Do not weaken them to “nonempty” or “contains”.

**Acceptance.** From the repo root, with the README’s scratch rules (do not point tests at the real Agent Lens cache):

```sh
python3 scripts/check-core-ui-imports.py
python3 Tests/Packaging/test_core_ui_imports.py
swift test --no-parallel --filter bundledDefaultDetectorsMatchFrozenCatalogue
swift test --no-parallel --filter bundledFixtureDefinitionsMatchSyntheticLayouts
```

Then the full local gate once the filtered tests pass:

```sh
swift build
swift test --no-parallel
python3 scripts/build-dev-app.py --scratch-root <fresh-root> --configuration debug
python3 Tests/Packaging/test_dev_app_bundle.py --app <fresh-root>/AgentLensApp-debug.app
```

Observable results: the renamed test passes; the fixture loop passes for `claude`, `gemini`, and `cline`; preflight prints `registry_ids` equal to the frozen B list; import guard exits 0. Evidence is the command transcript plus `git diff --stat` limited to the allow-list. Hosted CI is the orchestrator’s job at the combined gate. A green local suite does not authorise raising floors.

**Depends / stop.** Depends on M11-A freeze for `claude`, `gemini`, and `cline`. Stop if A held any of those three. Stop if `claude-code@latest` is rejected by the validator. Stop if a test outside the allow-list fails because it hardcodes the trio: add that file to the phase only with orchestrator approval, and do not “fix” it by editing a walkthrough or `DECISIONS.md`. Codex’s broken user-prefix install (missing optional npm dependency, **observed-local**) is not an acceptance failure.

**Model tier.** Flash (§29.6). Rows are frozen. The anchor rename is specified here so the implementer does not redesign CI. The orchestrator reviews the anchor diff; a flash implementer does not choose a new workflow.

### M11-C — Collision batch

**Goal.** Add the tools whose executable or package name can be confused with a different product, using only rows A marked frozen: Hermes, Aider (if the version query was verified), Goose, Kiro CLI, OMP, and AGY.

**Non-goals.** No DSH. No Qoder. No new layout or source classifier. No formula named `goose`. No cask `block-goose`. No npm `@oh-my-pi/cli`. No Kiro package. No AGY package. No detection of executable `kiro`. No uv/pip/cargo package field. No floor change.

**Allow-list.**

- `Sources/AgentLensCore/Detectors/DefaultDetectors.json`
- The same four test files as M11-B, updating the expected id list and package assertions only.
- `Tests/Packaging/test_dev_app_bundle.py`, same narrow update, still sparing the two-id fixture.
- `README.md`, the same one-sentence id list, updated to the C catalogue.

`ci.yml` is not on this allow-list. The anchor name from B does not contain a count.

**Protected.** The shared set, plus `.github/workflows/ci.yml` and every file outside the allow-list.

**Rows.**

| id | displayName | category | fixture | packages | extraSearchRoots | versionQuery |
|---|---|---|---|---|---|---|
| `hermes` | Hermes | `aiAgent` | `singleDirectory` / `standalone` | empty | `~/.local/bin` | `--version`, stdout, first. **observed-local** line begins `Hermes Agent v0.23.1 (2026.9.24)`. The token is `0.23.1` because the first match wins over the date. Do not pin it. |
| `aider` | Aider | `aiCodingTool` | `singleDirectory` / `standalone` | formula `aider` only | none, unless A quoted a destination from the official install script | whatever A verified. If A did not verify, omit the row. |
| `goose` | Goose | `aiCodingTool` | `singleDirectory` / `standalone` | formula `block-goose-cli` only | none, unless A quoted `GOOSE_BIN_DIR` behavior from the official script as a path that is off PATH | `--version`, stdout, first. Flag is **verified-docs**. Stream shape is **unverified**. |
| `kiro-cli` | Kiro CLI | `aiCodingTool` | `singleDirectory` / `standalone` | empty | empty unless A quoted the install-script destination | `--version`, stdout, first. Shape **unverified**. |
| `omp` | Oh My Pi | `aiHarness` | `singleDirectory` / `standalone` | formula `can1357/tap/omp` | none | `--version`, stdout, first. **observed-local** stdout `omp/18.19.0`. Do not point the query at `--help`. |
| `agy` | Antigravity CLI | `aiHarness` | `singleDirectory` / `standalone` | empty | `~/.local/bin` | `--version`, stdout, first. **observed-local** stdout `1.5.6`. |

Information URLs:

- Hermes: `https://hermes-agent.nousresearch.com/docs/getting-started/installation`
- Aider: `https://aider.chat/docs/install.html`
- Goose: `https://goose-docs.ai/docs/guides/goose-cli-commands`
- Kiro CLI: `https://kiro.dev/docs/cli/`
- OMP: `https://omp.sh/docs/quickstart`
- AGY: `https://antigravity.google/docs/cli/install/`

**Known limits the tests must not “fix” by changing the scanner.**

- Goose’s basename `goose` also belongs to the pressly database tool published as Homebrew formula `goose`, which `conflicts_with` `block-goose-cli`. The detector’s executable is still `goose`. Identity for mutation is the declared formula, and mutation is not this milestone. The matrix says the basename is shared.
- A Homebrew-prefix path is not a formula. This machine’s `/opt/homebrew/bin/omp` resolved to a Tern version store, not `/Cellar/`. Tern is not a declarable manager.
- `@oh-my-pi/cli` is a different project that also exposes `omp`. It is not declared.
- `kiro` without `-cli` is the IDE unless the user installed the command router. The router is not the detector.
- AGY’s `agy update` and Goose’s `goose update` are vendor self-updates. They are not Agent Lens operations.
- Flutter’s example `agy version 2.0.0` is not the contract. The Google install page’s `agy --version`, plus the local stdout `1.5.6`, is.

**Acceptance.** Same command pattern as B, with the filter pointed at `bundledDefaultDetectorsMatchFrozenCatalogue` and the fixture loop. The expected id list is the B list plus the C rows that were actually added. A held Aider is absent from that list and the absence is written in the phase evidence. Full `swift test --no-parallel` and the dev-app packaging check follow a green filter.

**Depends / stop.** Depends on A and on B having renamed the anchor. Stop if A did not freeze a row. Stop if the only way to distinguish Goose from pressly/goose is a scanner change. Stop if someone proposes formula `goose`, cask `block-goose`, npm `@oh-my-pi/cli`, or executable `kiro`. AGY does not wait on a second identity: Google’s install page names Antigravity CLI (`agy`). The owner may still veto it (decision 2). If the veto arrives before C is dispatched, omit `agy`.

**Model tier.** Strongest reasoning (§29.6). A wrong package here becomes a later mutation target.

### M11-D — Owner-unblocked remainder

**Goal.** Add only the rows the owner unblocked after A: DSH if decision 1 confirms DeepSeek Harness, and Qoder if decision 4 confirms executable `qodercli`.

**Non-goals.** No guessed DSH. No detector whose executable is `qoder`. No Homebrew package for either tool. No desktop Qoder IDE detector.

**Allow-list.** Same registry, test, packaging, and README files as C, id-list updates only.

**Dispatch rule.** If the unblock list is empty, do not dispatch this phase. Record the skip in the milestone evidence. An empty skip is a successful M11.

**Rows, only when unblocked.**

- DSH. id `dsh`, displayName `DeepSeek Harness`, category `aiHarness`, executable `dsh`, fixture `npmGlobal` / `npm`, package npm `@deepseek-ai/dsh`, information URL `https://github.com/deepseek-ai/deepseek-harness`, versionQuery `--version` stdout first. **observed-local** stdout on this machine was `0.2.2-rc.1`, which the existing prerelease regex matches. Do not pin it. Do not invent a Python wheel name. The product is a developer preview; the matrix says breaking changes are upstream, not an Agent Lens defect.
- Qoder. id `qodercli`, displayName `Qoder`, category `aiCodingTool`, executable `qodercli`, fixture `singleDirectory` / `standalone`, package npm `@qoder-ai/qodercli` (official docs call this legacy and still document it), information URL `https://docs.qoder.com/cli/installation`, extraSearchRoots only if A recorded an off-PATH directory. **observed-local** `--version` stdout was `1.1.88` for both `qodercli` and the dispatcher `qoder`. Do not pin it. The dispatcher at `~/.qoder/entry/qoder` can launch the IDE. It is not the detector.

**Acceptance.** Same as C, against the expanded id list. If the phase was skipped, acceptance is the written skip plus a registry that still has no `dsh` or `qoder`/`qodercli` id.

**Depends / stop.** Depends on C and on a written owner answer. Stop if the answer is ambiguous. Stop if the Qoder answer selects `qoder`: that choice reopens A, because the dispatcher is not a stable CLI identity. Do not silently implement it.

**Model tier.** Strongest reasoning if dispatched. The rows are short; the risk is implementing a “yes” the owner did not give.

### M11-E — Capability matrix and contributor proof

**Goal.** Publish a matrix that cannot claim an operation the app cannot perform, and prove that one extra tool in a JSON registry is detected without a source edit under `Sources/` other than the production registry staying unchanged.

**Non-goals.** No new production detector. No fake tool left in `DefaultDetectors.json`. No `LICENSE` file. No public contribution invitation. No generator that writes product source. No scanner refactor. No README rewrite beyond the id sentence if D changed the list, plus a link to the new docs.

**Allow-list.**

- `docs/capability-matrix.md` (new)
- `docs/detectors.md` (new contributor guide)
- `Tests/AgentLensCoreTests/CapabilityMatrixTests.swift` (new) or an added test in `DetectorRegistryTests.swift` if a new file is awkward for the existing target. One file, not both.
- `Tests/AgentLensCoreTests/DetectorRegistryTests.swift` — add the JSON-only extra-tool test. Do not delete the Swift-constructor test.
- `README.md` — link the matrix and the detector guide; keep the id sentence truthful.
- `.github/workflows/ci.yml` — floor numbers only, and only after the orchestrator has counted `swift test --no-parallel` on this branch. Raise Core and the combined total to that count. Do not lower any floor. Do not change guard-fixtures 21 or packaging 9 unless this phase added a Python test, which it must not. Leave `CORE_ANCHORS` as B set them. The new tests do not need to become anchors.

**Protected.** The shared set. Production `DefaultDetectors.json` may be read and must not gain a fixture tool. `Sources/AgentLensApp/**` stays untouched.

**Matrix contract.** See section C. The Swift test fails when a markdown row’s id, category, declared packages, or fixture layout drifts from `DefaultDetectors.json`, and fails when a row claims Update or Uninstall for any manager other than npm, or latest-check for any manager other than npm and `homebrewFormula`.

**JSON-only proof.** A test builds a schemaVersion 2 JSON string (or loads a fixture under `Tests/`, not the bundled resource) that contains the current detectors plus one extra definition using `singleDirectory` / `standalone` and an id that is not shipped. It loads that data through `DetectorRegistry.validate` / the existing detector builder and detects a synthetic executable. The production file’s id list is asserted unchanged in the same test. The extra tool’s name must not collide with a catalogue id (`newtool` is already used by the Swift-constructor test and may be reused).

**Contributor guide contract.** See section D. It states that the license is not selected and that public invitations stay closed.

**Acceptance.**

```sh
swift test --no-parallel --filter CapabilityMatrix
swift test --no-parallel --filter addingAFourthDefinitionRequiresNoSourceChanges
python3 scripts/check-core-ui-imports.py
```

Then the full README gate (`swift test --no-parallel`, dev app, packaging). The orchestrator records the Swift Testing summary count and only then accepts a floor edit that matches that count exactly. Evidence includes the matrix test name, the JSON-proof test name, and the measured count.

**Depends / stop.** Depends on B and C, and on D if D was dispatched. Stop if the matrix can be satisfied only by hand-waving a cell the test does not check. Stop if the JSON proof requires a new layout, a new manager, or an edit under `Sources/` other than reading the existing registry API. Stop before raising floors if the local count and the orchestrator’s count differ.

**Model tier.** Strongest reasoning (§29.6). A matrix cell that says Update is available for a cask, a formula, uv, or a standalone install is a safety defect, because a later milestone could treat the matrix as permission.

### Combined M11 gate (orchestrator, not an implementer phase)

One branch contains A through E, with D skipped if nothing was unblocked. The orchestrator, not the implementer, runs:

- `python3 scripts/check-core-ui-imports.py` and `python3 Tests/Packaging/test_core_ui_imports.py`
- `swift build` and `swift test --no-parallel`
- `python3 scripts/build-dev-app.py --scratch-root <fresh-root> --configuration debug`
- `python3 Tests/Packaging/test_dev_app_bundle.py --app <fresh-root>/AgentLensApp-debug.app`
- The hosted workflow’s seven gates: `guard`, `guard-fixtures` (floor 21), `swift-build`, `isolation-gate`, `full-test-suite` (floors at or above the pre-M11 456/79/535, raised only to the measured count), `build-dev-app`, `packaging` (floor 9). Runner is `macos-15` with `DEVELOPER_DIR` `/Applications/Xcode_26.3.app/Contents/Developer`, as `.github/workflows/ci.yml` already sets.

CLI and app must agree because they load the same registry. The check is the dev-app preflight id list versus `DetectorRegistry.loadDefault()` in the Swift test, not a new UI feature. Personal installations are not the oracle.

---

## B. Catalogue identity

Fourteen entries. “M11 action” is what the coding phases may do after A. Local version strings are measurements, not registry pins.

### Already shipped

**Codex** — OpenAI. Category `aiAgent`. Executable `codex`.

- **verified-docs.** `https://github.com/openai/codex/blob/main/README.md` documents three installs: standalone `curl -fsSL https://chatgpt.com/codex/install.sh | sh` (downloads from `https://releases.openai.com/codex`, with a GitHub Releases fallback), npm `@openai/codex`, and `brew install --cask codex`.
- **verified-docs.** `https://formulae.brew.sh/cask/codex` on 2026-11-12 listed cask version `0.167.2`, artifact `bin/codex`, homepage `github.com/openai/codex`.
- **verified-docs (historical).** The old Homebrew formula `codex` was replaced by the cask. `https://formulae.brew.sh/formula/codex` was reported 404 in upstream issues #5317 / #5607. This proposal did not re-fetch that 404 on the write-up turn. Do not re-add a formula named `codex`.
- **observed-local.** `~/.local/bin/codex` and `/opt/homebrew/bin/codex` are both npm shims into `lib/node_modules/@openai/codex/` (package versions `0.167.2` and `0.167.0`). The user-prefix binary exited 1 because optional dependency `@openai/codex-darwin-arm64` was missing. The Homebrew-prefix copy printed `codex-cli 0.167.0` on stdout. Neither path is the cask. A `/opt/homebrew/bin` path is not proof of a formula.
- Registry today already has npm `@openai/codex`, cask `codex`, fixture `npmGlobal`/`npm`, `extraSearchRoots` `~/.local/bin`, information URL `https://developers.openai.com/codex/cli`. That URL redirected during this assignment and did not yield an install body (**unverified** as a living install page). The README is the install authority.
- M11 action: keep the two package declarations and the npm fixture. Document the standalone installer as a layout the classifier will call `standalone` when the path is outside `node_modules` and `Cellar`. Cask ownership and cask Update/Uninstall are not M11. Do not treat the broken local optional-dependency as a product bug to fix here.

**OpenCode.** Category `aiAgent`. Executable `opencode`.

- **verified-docs.** `https://opencode.ai/download` documents the curl installer into `~/.opencode/bin`, npm `@opencode/cli`, a bun install, and `brew install anomalyco/tap/opencode-v2`. Desktop cask `opencode-desktop` is a different surface.
- **verified-docs.** `https://formulae.brew.sh/formula/opencode` on 2026-11-12 listed binary `opencode`, version `2.2.7`, homepage `https://opencode.ai`, license MIT.
- **observed-local.** `~/.opencode/bin/opencode` is a regular file. `--version` stdout `opencode v2.2.7`, exit 0. The token is `2.2.7`. D-018 recorded `2.0.28`. Do not pin either.
- Registry today has npm `@opencode/cli` and `opencode-ai`, formulae `anomalyco/tap/opencode-v2` and `anomalyco/tap/opencode`, fixture `singleDirectory`/`standalone`, information URL `https://opencode.ai/v2/docs/`, uninstall URL `https://opencode.ai/v2/docs/cli/#uninstall`, `extraSearchRoots` `~/.opencode/bin`.
- M11 action: add homebrew-core formula `opencode`. Keep the tap formulae and both npm names. Do not add `opencode-desktop`. Do not retarget the fixture at the live tree.

**Grok CLI** — xAI. Category `aiAgent`. Executable `grok`.

- **verified-docs.** `https://docs.x.ai/build/overview` documents `curl -fsSL https://x.ai/cli/install.sh | bash`, config `~/.grok/config.toml`, optional `GROK_HOME`. This assignment found no npm or Homebrew package there.
- **observed-local.** `~/.local/bin/grok` → `~/.grok/bin/grok` → `~/.grok/downloads/grok-1.0.77-macos-aarch64`. `--version` stdout `grok 1.0.77 (50ca579fa996) [stable]`. The token is `1.0.77`. The hash is not a version. `extraSearchRoots` `~/.grok/bin` still matches this layout.
- M11 action: none structural. Empty `packages` stays. Do not invent a package or a `grok update` adapter. The information URL is already correct. There is still no `uninstallInstructionsURL`; do not invent one.

### AI Agents to add

**Claude Code** — Anthropic. Category `aiAgent`. Executable `claude`.

- **verified-docs.** `https://code.claude.com/docs/en/setup`: native `curl -fsSL https://claude.ai/install.sh | bash`; launcher `~/.local/bin/claude` symlink into `~/.local/share/claude/versions/`; Homebrew casks `claude-code` (stable) and `claude-code@latest`; npm `@anthropic-ai/claude-code` documented and not recommended; Node 22+; optional platform package such as `@anthropic-ai/claude-code-darwin-arm64`; the installed binary does not invoke Node. WinGet id `Anthropic.ClaudeCode` is not a declarable manager. The same page shows version examples `2.1.211 (Claude Code)` and pinned `2.1.89 (Claude Code)`. Those are documentation examples, not **observed-local** (not installed). Which stdio stream carries them is **unverified**.
- **verified-docs.** The GitHub README also says npm is deprecated and documents `brew install --cask claude-code`.
- M11 action: id `claude`. Fixture `singleDirectory`/`standalone` proves classification only. It does not reproduce the `versions/` symlink, and M11 must not add a layout to reproduce it. Do not put the `versions/` directory on `extraSearchRoots`. Declare the npm package and both casks. Update/Uninstall stays informational for the native launcher and the cask. npm Update/Uninstall applies only when the ownership probe verifies that copy as npm-global. No formula.

**Gemini CLI** — Google, repo `google-gemini/gemini-cli`. Category `aiAgent`. Executable `gemini`. Not installed here.

- **verified-docs.** `https://geminicli.com/docs/get-started/installation/`: npm `@google/gemini-cli`, `brew install gemini-cli`, MacPorts `gemini-cli`, and npx. MacPorts is not declarable.
- **verified-docs.** The FAQ on that site documents `gemini --version` or `-v`. Stdout shape is **unverified**. A release note mentioned stable `v0.64.0` (2026-10-13). Do not pin it.
- **verified-docs.** The same docs carry a banner: on 2026-06-18, unpaid and Google One users were directed to Antigravity CLI, and Gemini CLI is not the optimized surface for Gemini 4 Argon. That banner is a known limit. It does not make Gemini CLI the same product as AGY. Scope §2 still names Gemini CLI. Default: include it (decision 8).
- **unverified.** `https://formulae.brew.sh/formula/gemini-cli` was not fetched. A must fetch it before B declares the formula.
- M11 action: fixture `npmGlobal`/`npm`, because that layout can be synthesized without calling an unobserved Cellar “verified”. Declare the formula only after A’s listing-page check. Cellar ownership remains unverified even then.

**Hermes** — Nous Research Hermes Agent. Category `aiAgent`. Executable `hermes`.

- **verified-docs.** `https://hermes-agent.nousresearch.com/docs/getting-started/installation`: the POSIX script clones into `~/.hermes/hermes-agent/`, the CLI entry is a `~/.local/bin/hermes` wrapper, data lives under `~/.hermes/`. The script bootstraps uv and does not use a uv already on PATH. Python 3.14 is part of that story. The page also documents a desktop installer, a Windows script, Docker, and Termux APT. No npm or Homebrew package was on the page this assignment read. A third-party `pip install hermes-agent` is not an official name and must not be declared. uv is the bootstrap tool. Scope’s “Hermes 0.20.5 uv” example is a stale label, not a package identity.
- **observed-local.** `~/.local/bin/hermes` is a 76-byte wrapper that execs `~/.hermes/hermes-agent/.hermes/bin/hermes`. `--version` stdout: `Hermes Agent v0.23.1 (2026.9.24) · stable · local 3b4215785882`, install directory `~/.hermes/hermes-agent`, install method `git`, Python `3.14.9`. Token `0.23.1`.
- Ambiguity: the common word “Hermes” could mean other software. The official executable name, the install page, and the scope’s own example line up. That residual is not an owner blocker if the matrix says packages are empty and the source is standalone/git.
- M11 action: C adds id `hermes`, packages empty, fixture `singleDirectory`/`standalone`.

**Cline CLI** — Cline. Category `aiAgent`. Executable `cline`. The VS Code extension and the desktop app are different surfaces.

- **verified-docs.** `https://docs.cline.bot/getting-started/installing-cline` and `https://docs.cline.bot/cline-cli/installation`: `npm install -g cline`; verify with `cline version` or `cline --version` / `-V`. Docs also mention `cline update`, which is not an Agent Lens adapter. No Homebrew formula was in the docs this assignment reviewed (**unverified** that none exists on formulae.brew.sh; do not declare one).
- **observed-local.** npm package `cline` at `3.0.74`, bin `cline`, homepage `https://cline.bot`, repository `github.com/cline/cline` directory `apps/cli`. `~/.local/bin/cline` and `/opt/homebrew/bin/cline` are npm shims into `lib/node_modules/cline`. `--version` stdout `3.0.74`. The Homebrew-prefix copy is npm-under-prefix, not a confirmed formula. `~/.local/shims/cline` is a personal signature-repair shim on this machine. It must not become a layout, a fixture, or an `extraSearchRoots` entry.
- M11 action: B adds id `cline`, fixture `npmGlobal`/`npm`, package npm `cline` only.

### AI Coding Tools

**Aider** — Aider-AI. Category `aiCodingTool`. Executable `aider`. Not on PATH here.

- **verified-docs.** `https://aider.chat/docs/install.html`: `python -m pip install aider-install` then `aider-install`; `curl -LsSf https://aider.chat/install.sh | sh` uses uv to install `aider-chat@latest`; also `uv tool install ... aider-chat@latest`; pipx and pip use `aider-chat`. uv and pip are not declarable managers. The Python distribution name `aider-chat` must not be stuffed into an npm or Homebrew field.
- **verified-docs.** `https://formulae.brew.sh/formula/aider` on 2026-11-12: binary `aider`, homepage `https://aider.chat/`, Apache-2.0, stable `0.86.2` in that snapshot. Do not pin `0.86.2`.
- **unverified.** The version-query flag and stdout shape. This assignment did not confirm them on the install page, and the binary is not installed. M11-A must confirm them from a primary page before any `versionQuery` is written. Until then Aider is held out of M11-C.
- M11 action, after A: formula `aider` only, fixture `singleDirectory`/`standalone` (a uv tool bin is not a Cellar path).

**Goose** — Block’s AI agent, current docs under the `aaif-goose` GitHub org. Category `aiCodingTool`. Executable `goose`. Not installed here. This is not pressly/goose.

- **verified-docs.** `https://formulae.brew.sh/formula/block-goose-cli`: AI CLI, homepage `https://goose-docs.ai/`, Apache-2.0, binary `goose`, snapshot stable `1.59.0`, `conflicts_with` formula `goose`.
- **verified-docs.** `https://formulae.brew.sh/formula/goose`: database migration CLI (pressly), `conflicts_with` `block-goose-cli`, because both install a binary named `goose`.
- **verified-docs.** Cask `block-goose` is the desktop `Goose.app` (same snapshot version `1.59.0` was seen for the cask). It is not the CLI and must not be declared.
- **verified-docs.** `https://goose-docs.ai/docs/guides/goose-cli-commands` documents `goose --version` and `goose update`. Stdout shape is **unverified**. `goose update` is not an Agent Lens operation.
- **verified-docs.** The CLI install script cited from the project’s CI/docs is `curl -fsSL https://github.com/aaif-goose/goose/releases/download/stable/download_cli.sh`, with `GOOSE_BIN_DIR` / `GOOSE_VERSION`. Older issues say the org was `block/goose`. Do not collapse the two org names into one package. The Homebrew formula name is the package identity M11 is allowed to declare.
- M11 action: formula `block-goose-cli` only. Fixture `singleDirectory`/`standalone`. The basename collision is a known limit (decision 5), not a scanner project. A synthetic `brewCellar` fixture whose directory is `Cellar/goose/...` would look like the pressly path. Do not use it.

**Kiro CLI** — Amazon / Kiro. Category `aiCodingTool`. Executable `kiro-cli`. Not installed here.

- **verified-docs.** `https://kiro.dev/docs/cli/` and `https://kiro.dev/docs/getting-started/installation/`: the CLI command is `kiro-cli`. Install script `curl -fsSL https://cli.kiro.dev/install | bash`. An optional command router (`kiro-cli integrations install kiro-command-router`, then `kiro set-default cli`) makes `kiro` invoke the CLI. That router must not become the detector. `--version`, `-V`, and `kiro-cli version` are documented. A non-primary Arm snippet showed `kiro-cli 1.21.0`; that shape is **unverified**.
- **Conflict, still open.** The installation page, as read this assignment, says both `brew install kiro-cli` and that “the Homebrew cask installs the kiro-cli binary”, and another sentence says `brew install --cask kiro-cli`. Formula versus cask is **unverified**. Packages stay empty until one official listing is the only listing (decision 3). A re-read that still shows both sentences freezes empty packages. That is a complete Kiro row, not a hold.
- M11 action: id and executable `kiro-cli`. Do not detect `kiro`. Fixture `singleDirectory`/`standalone`. `extraSearchRoots` empty unless A quotes a destination from the fetched script text.

**Qoder.** Category `aiCodingTool`. Held for decision 4.

- **verified-docs.** `https://docs.qoder.com/cli/installation` recommends `curl -fsSL https://qoder.com/install | bash` and legacy `npm install -g @qoder-ai/qodercli`, and tells the reader to verify with `qoder --version`.
- **verified-docs.** `https://docs.qoder.com/cli/cli-reference`, `https://docs.qoder.com/en/cli/using-cli`, and the markdown quick start call the command `qodercli`. `https://qoder.com/cli` repeats the install script.
- **observed-local.** `~/.qoder/entry/qoder` is a bash “Qoder Command Dispatcher” that routes to `qodercli` or the IDE. `~/.local/bin/qodercli` → `~/.qoder/bin/qodercli/qodercli-1.1.88`. Both `qoder --version` and `qodercli --version` printed `1.1.88`.
- **unverified.** Any Homebrew formula or cask.
- Recommendation, not a registry edit: id `qodercli`, executable `qodercli`, displayName `Qoder`, npm `@qoder-ai/qodercli`, fixture `singleDirectory`/`standalone`. The dispatcher is the wrong detector. M11-D implements this only after decision 4 says `qodercli`.

### AI Harnesses

**DSH** — named research blocker. Not frozen.

- Candidate, **verified-docs**: `https://github.com/deepseek-ai/deepseek-harness` describes DeepSeek Harness (`dsh`) as an open-source agent harness from DeepSeek AI. Docs site: `https://deepseek-harness.github.io/deepseek-harness/`. npm package `@deepseek-ai/dsh` is documented for `npx @deepseek-ai/dsh web`. In-repo CLI help documents `-V, --version`.
- **observed-local.** `~/.local/bin/dsh` and `/opt/homebrew/bin/dsh` are npm shims to `@deepseek-ai/dsh` `lib/bin.js`, version `0.2.2-rc.1`, description beginning “dsh CLI”, license MIT, repository `git+https://github.com/deepseek-ai/deepseek-harness.git` directory `apps/cli`. `--version` stdout `0.2.2-rc.1`. The existing regex matches that prerelease token.
- Why this is still blocked. Scope never defines the acronym. Other projects ship a command named `dsh`. `brew info dsh` was not run, so a Homebrew name collision is **unverified**. A local npm install is evidence about this machine, not about the owner’s catalogue meaning.
- Owner question (decision 1): does catalogue entry DSH mean DeepSeek Harness CLI, npm `@deepseek-ai/dsh`, executable `dsh`, repository `deepseek-ai/deepseek-harness`, and not another `dsh`? Until the answer is yes, no phase has `dsh` on its coding allow-list. If the answer is yes, the row is category `aiHarness`, fixture `npmGlobal`/`npm`, npm package only, no formula, no invented wheel name.

**OMP** — Oh My Pi, the coding agent. Category `aiHarness`. Executable `omp`.

- **verified-docs.** `https://omp.sh/docs/quickstart`, `https://nibblebot.github.io/oh-my-pi/getting-started/installation/`, and the GitHub `can1357/oh-my-pi` CLI reference. Installs: `curl -fsSL https://omp.sh/install | sh`; `brew install can1357/tap/omp`; `bun install -g @oh-my-pi/pi-coding-agent`; a Windows script; mise `github:can1357/oh-my-pi`. `--version` is documented. Bun is not a declarable manager, so `@oh-my-pi/pi-coding-agent` is not a registry package.
- **verified-docs, different product.** npm `@oh-my-pi/cli` is a plugin manager that also exposes `omp`. Do not declare it.
- **observed-local.** `~/.local/bin/omp` is a Mach-O. `--version` printed `omp/18.19.0`. `--help` starts `omp v18.19.0` and matches Oh My Pi flags (`PI_SMOL_MODEL`, `--model`, `--smol`, `--slow`, `--plan`). Use `--version` so the token is `18.19.0` and not a different number from the help text. `strings` on the binary was dominated by the embedded Bun runtime and did not prove identity; the help text did.
- **observed-local.** `/opt/homebrew/bin/omp` → Tern store `~/Library/Application Support/Tern/omp/bin/omp` realpath `versions/18.18.8`. Tern’s `manager.json` names Tern. That copy is not `/Cellar/` and is not proof of tap `can1357/tap/omp`.
- M11 action: formula `can1357/tap/omp` (three components, valid shape). Fixture `singleDirectory`/`standalone`. Do not declare the npm plugin manager. Do not encode Tern as a manager or a search root.

**AGY** — named research blocker in ROADMAP §4. The primary-source question is answered. A residual owner veto remains (decision 2).

- **verified-docs.** `https://antigravity.google/docs/cli/install/`: product name Antigravity CLI (`agy`); macOS/Linux `curl -fsSL https://antigravity.google/cli/install.sh | bash`; binary `~/.local/bin/agy`; verify `agy --version`. Getting started: `https://antigravity.google/docs/getting-started/`. GitHub `google-antigravity/antigravity-cli` points at `https://antigravity.google/docs/cli/overview`. Gemini CLI’s own docs mention the 2026-06-18 move toward Antigravity.
- **unverified / do not adopt.** `https://docs.flutter.dev/ai/antigravity-cli` uses installer URL `https://antigravity.google/install.sh` and example `agy version 2.0.0`. That disagrees with the Google CLI install page and with this machine. It is not the contract.
- **observed-local.** `~/.local/bin/agy` is a Mach-O of about 233MB. `--version` stdout `1.5.6`. `--help` wrote `Usage of agy:` on stderr (capture truncated). `strings` included `antigravity-cli`, “Antigravity plugin CLI”, and `com.google.antigravity`.
- **unverified.** Any npm or Homebrew package. Do not invent one. `agy update` is a vendor self-update, not an adapter. The desktop Antigravity app is a different surface.
- No second primary candidate was found. M11-C may add id `agy`, packages empty, fixture `singleDirectory`/`standalone`, `extraSearchRoots` `~/.local/bin`, unless the owner vetoes the row before dispatch. Category `aiHarness`.

### What M11 must not treat as verified

- Any Cellar tree for Gemini, Goose, Aider, OpenCode’s new core formula, or OMP’s tap. Declaring a formula is not a `brewCellar` fixture and is not a verified source.
- Any cask binary’s source label. Outside `node_modules` and `Cellar`, `classifySource` returns `standalone`. Codex cask and Claude casks will look standalone until a later ownership milestone. That is a known limit.
- Personal paths: the broken Codex optional dependency, the Cline shim under `~/.local/shims`, the Tern `omp` store, the Hermes git checkout as a required fixture version, and the Qoder versioned filename `qodercli-1.1.88`.
- Live version numbers as registry data.

---

## C. Capability matrix

**Where it lives.** `docs/capability-matrix.md`, one Markdown table, plus `Tests/AgentLensCoreTests/CapabilityMatrixTests.swift` (name flexible, there must be one Swift test). The markdown is the page a reader opens. The test is what keeps it true. A second JSON matrix would drift. A generator is allowed only as a test helper in that test file. No new file under `scripts/` and no write into `Sources/`.

**Columns.** tool id, display name, category, tested fixture layout, declared packages, latest-check, Update, Uninstall, known limits.

**Legal cell values for the three operation columns.**

- `yes` — only where a shipped adapter exists.
- `informational` — the product is detected, and the operation is shown as unavailable with a reason.
- `disabled: <short reason>` — same truth, for a row that must not be clicked or invoked. M11 does not build the click. The word is for the matrix and for any later UI that reads it.

**Rules the test enforces, matching shipped code today.**

- Latest-check may be `yes` only for a declared `npm` package (M10-B) or a declared `homebrewFormula` (M6, no `brew update`, D-019).
- Update and Uninstall may be `yes` only for a declared `npm` package, and the matrix’s known-limits cell must say that `yes` applies to a copy the ownership probe has verified as npm-global. A declaration alone is not ownership.
- `homebrewCask`, empty packages, standalone, uv, pip, cargo, and bun are `informational` or `disabled` for Update and Uninstall. Homebrew cask latest-check is `disabled: cask latest-check is not shipped`. uv and cargo wait for M14 and M15.
- Vendor self-update commands (`claude update`, `agy update`, `goose update`, `cline update`, installer reruns) are `disabled: vendor self-update is not an Agent Lens operation`.
- A row cannot say the fixture layout was “verified” against a real vendor tree. The cell is `synthetic <layout>`.
- Every bundled detector id appears once. Every matrix id exists in the registry. Categories and package names match the JSON.

**Illustrative cells (the test is the authority once E lands).**

| id | fixture the test builds | latest-check | Update / Uninstall | limit that must be written |
|---|---|---|---|---|
| `codex` | synthetic `npmGlobal` | npm `yes`; cask `disabled` | npm `yes` only if that copy verifies as npm-global; cask `informational` | standalone installer and cask both classify as `standalone` |
| `opencode` | synthetic `singleDirectory` | npm `yes`; formulae `yes` for latest-check only | npm only when verified; formulae `disabled: M13` | core formula `opencode` is a declaration; desktop cask is absent on purpose |
| `grok` | synthetic `singleDirectory` | `disabled: no declared package` | `disabled: no declared package` | no npm or Homebrew identity in the docs reviewed |
| `claude` | synthetic `singleDirectory` | npm `yes`; casks `disabled` | npm only when verified; native and cask `informational` | fixture does not reproduce the `versions/` symlink |
| `gemini` | synthetic `npmGlobal` | npm `yes`; formula `yes` only if declared | npm only when verified; formula `disabled: M13` | Antigravity transition banner; formula listing depends on A |
| `cline` | synthetic `npmGlobal` | npm `yes` | npm only when verified | personal shim is not a layout; prefix npm is not a formula |
| `hermes` | synthetic `singleDirectory` | `disabled` | `disabled` | uv is the bootstrap, not a package; install method git |
| `aider` | synthetic `singleDirectory`, and only if the row exists | formula latest-check `yes`; uv/pip not representable | `disabled: M13`; uv not an adapter | version query absent until A verifies it |
| `goose` | synthetic `singleDirectory` | formula `block-goose-cli` latest-check `yes` | `disabled: M13` | basename shared with pressly formula `goose`; cask `block-goose` is the desktop app |
| `kiro-cli` | synthetic `singleDirectory` | `disabled: packages empty` | `disabled` | do not detect `kiro`; formula vs cask unresolved |
| `omp` | synthetic `singleDirectory` | formula `can1357/tap/omp` latest-check `yes` | `disabled: M13` | not npm `@oh-my-pi/cli`; Tern copy is not the tap |
| `agy` | synthetic `singleDirectory` | `disabled: packages empty` | `disabled` | `agy update` is not an adapter; Flutter `2.0.0` example is not the contract |
| `dsh` / `qodercli` | only after D | as their package rules say | npm only when verified, for DSH and for Qoder’s legacy npm name | absent from the matrix when the phase was skipped |

Entries without an adapter stay informational. The app already has that behavior for non-npm installs. M11 does not add a new disabled-state engine in the UI.

---

## D. Contributor foundation

**Docs.** `docs/detectors.md` is the contributor page. It documents the fields that already exist, in the words the validator uses:

- `schemaVersion` must be 2. Schema 1 and 3 are rejected. There is no compatibility shim.
- Required identity: `id`, `displayName`, `executableName`. Prefer `id` equal to `executableName`. Kiro’s id is `kiro-cli` for that reason. A display name may contain spaces (“Claude Code”, “Kiro CLI”).
- `category`: `aiAgent`, `aiCodingTool`, or `aiHarness`.
- `fixture` is one of the three layouts and one of the three sources. The fixture is a synthetic tree the suite builds. It is not a copy of a vendor install.
- `packages` entries use only `npm`, `homebrewFormula`, and `homebrewCask`. Names must pass the existing alphabets. One formula component or three `user/repo/name` components. A package declaration does not mean Agent Lens owns the install.
- `versionQuery`: 1 to 8 arguments, stream `stdout` or `stderr`, line `first` or `firstNonempty`. The token regex is the one in `ToolDetector.extractVersionToken`. First match wins. Prerelease suffixes such as `0.2.2-rc.1` match. A date later in the same line must not be the declared version.
- `informationURL` is HTTPS. `uninstallInstructionsURL` is optional HTTPS and is documentation, not an adapter.
- `extraSearchRoots` are extra directories, not a private install algorithm. Do not add a personal shim, a version store, or a `versions/` directory.

**The change that adds a tool on an existing layout.** Edit `DefaultDetectors.json`. The loop in `bundledFixtureDefinitionsMatchSyntheticLayouts` already builds a synthetic tree for every definition. Add an expectation to `bundledDefaultDetectorsMatchFrozenCatalogue` and to the other exact id-list tests named in M11-B, and update the README id sentence. No edit under `Sources/AgentLensCore` besides the JSON, and no edit under `Sources/AgentLensApp`. If the new tool needs a fourth layout, a fourth source label, or a fourth manager, it is not an M11 contribution. Stop and write a later milestone.

**Proof.** M11-E’s JSON test loads an extra detector from a string and detects it. The production registry does not keep that extra detector. The existing `addingAFourthDefinitionRequiresNoSourceChanges` test builds a Swift value. It stays, and it is not the contribution proof by itself, because contributors do not add tools by calling the Swift initializer (D-017).

**Schema-validation CI.** The existing Swift rejection tests plus `python3 scripts/check-core-ui-imports.py` and `Tests/Packaging/test_core_ui_imports.py`. M11 does not add a schema version and does not weaken a rejection test. Hosted gates stay the seven in `ci.yml`.

**License gate.** No `LICENSE` file exists as a chosen project license (scope §17 names MIT or Apache-2.0; the owner has not picked). Public contribution invitations stay closed through this milestone (ROADMAP §7, D-020). The detector guide must say: the license is not selected; do not invite public contributions until the owner records MIT or Apache-2.0, no later than M18.

Tradeoff, for the owner, not a decision:

- MIT is the lower-friction choice for a solo, non-coder operating model that will eventually accept small registry contributions. It is what homebrew-core’s OpenCode formula snapshot used, and it is the usual “read the registry JSON and send a patch” license.
- Apache-2.0 adds an explicit patent grant. Several upstream CLIs this catalogue detects use it (Codex’s project family, Cline, and the Aider and `block-goose-cli` formula listings observed on formulae.brew.sh). Choose it if that grant matters more than the shorter MIT text.

Recommendation: MIT, with Apache-2.0 as the alternative if the owner wants the patent grant. M11 does not add the file. Decision 6 remains open on purpose.

---

## E. Acceptance strategy

**Per phase.**

- A: citation review of `docs/catalogue-identities.md`. No Swift command. Diff is that file only.
- B and C (and D if dispatched): filtered registry and fixture tests, then `swift build`, `swift test --no-parallel`, import guards, dev app, packaging test. Id lists match across the Swift tests and `test_dev_app_bundle.py`. Preflight `registry_ids` matches. Version behavior is asserted only where section B has an **observed-local** or **verified-docs** shape, and only inside synthetic or already-recorded bounds. A missing binary on the acceptance machine yields install state “not installed”, which is a pass. Unknown version text is a pass (D-006, D-007). Latest is never fabricated.
- E: matrix test, JSON-only extra-tool test, production id list unchanged, floors raised only to a count the orchestrator measured.

**Combined gate.** Section A’s orchestrator list. CLI facts and app preflight facts come from the same JSON. Schema failures still name the existing `DetectorRegistryError` cases. Hosted `full-test-suite` still requires the passed-event anchor, now `bundledDefaultDetectorsMatchFrozenCatalogue`.

**Not acceptance targets.**

- This machine’s personal installs, including the broken Codex user-prefix, the Cline shim, the Tern `omp`, the Hermes git checkout version, and any live `1.0.77` / `2.2.7` / `3.0.74` / `1.5.6` pin.
- Labeling an unobserved Cellar, cask payload, or install-script directory as verified.
- New mutation adapters, `brew update`, uv/cargo classifiers, or per-tool shell scripts.
- M12 sidebar, filters, keyboard workflow, or any SwiftUI redesign.
- A chosen LICENSE file.
- Green hosted CI claimed by the implementer without a hosted run. The orchestrator runs hosted CI.
- Rewriting historical briefs, walkthroughs, or D-018’s recorded versions.

---

## F. Risks and owner decisions

**Ranked risks.**

1. Identity. DSH is still an acronym. Qoder’s docs disagree about the command. Kiro’s docs disagree about formula versus cask. A coding phase that “picks the likely one” will encode the wrong package.
2. Basename collisions. Formula `goose` is a database tool. `@oh-my-pi/cli` is not Oh My Pi the coding agent. Other `dsh` tools exist. A declared package is the only mutation identity, and M11 does not mutate, so the danger is a matrix or a later milestone inheriting a bad declaration.
3. Layout drift. Codex is npm, cask, and a standalone script. Claude’s launcher is a symlink into a versions directory. Grok’s binary is a versioned file under `~/.grok/downloads` reached through `~/.grok/bin`. Cline and Codex both appear under `/opt/homebrew/bin` as npm. OMP appears there as Tern. The classifier will call several of these `standalone`. That is correct for today’s code and surprising if the matrix says “Homebrew” because the path contains `homebrew`.
4. Fixture realism. Synthetic layouts prove `classifySource` and the fixture switch. They do not prove a vendor tree. Shipping them under the word “verified” would be a false acceptance.
5. Scope creep into M12 UI, M13–M15 adapters, a new layout, or a uv/cargo classifier. The stop conditions in section A are the control.
6. CI integrity. Tests and `test_dev_app_bundle.py` pin the exact trio. The hosted anchor is the function name `bundledDefaultDetectorsIsValidWithThreeTools`. Renaming the test without editing `CORE_ANCHORS` fails the gate. Raising floors before counting, or lowering them, hides a dropped test.
7. Version-output variance. `omp/18.19.0` versus `omp v18.19.0`, Claude’s `2.x (Claude Code)`, Hermes’s multi-field line, DSH’s prerelease, Flutter’s `agy version 2.0.0` versus observed `1.5.6`, and Aider’s unconfirmed flag. First-match extraction already handles Hermes and the DSH prerelease. It will also extract a date if the date appears first. Aider must not get a guessed argv.
8. Gemini’s transition banner. A detector for a product upstream is steering some users away from can look stale. The catalogue still names it. The matrix carries the banner. Merging Gemini CLI into AGY would be a catalogue error.
9. A capability cell that says Update or Uninstall for anything except verified npm-global. That is the safety defect M11-E’s test exists to prevent.

**Decisions only the owner can make.**

1. Confirm that DSH means DeepSeek Harness, npm `@deepseek-ai/dsh`, executable `dsh`, repo `deepseek-ai/deepseek-harness`. Any other answer, or silence, leaves DSH out of the registry.
2. Veto or accept AGY as Google Antigravity CLI, executable `agy`. Research supports that identity. Silence is acceptance of the M11-C row. A veto before C is dispatched omits the row.
3. Kiro packages: leave them empty (recommended while the official page states both a formula and a cask), or name exactly one of formula `kiro-cli` or cask `kiro-cli` after A quotes a single listing. The executable is `kiro-cli` either way.
4. Qoder detector executable: `qodercli` (recommended) or a written instruction to stop and reopen research. `qoder` is the dispatcher and is not a recommended default.
5. Accept Goose as formula `block-goose-cli` only, with the pressly `goose` basename collision recorded as a known limit and no scanner change.
6. Choose MIT (recommended for this operating model) or Apache-2.0 (patent grant). Not in M11. Required before any public contribution invitation, no later than M18.
7. Add homebrew-core formula `opencode` (recommended; formulae.brew.sh lists it) and keep Codex cask `codex` (recommended; the README still documents npm, the cask, and the standalone script).
8. Keep Gemini CLI in the catalogue despite the Antigravity banner (recommended, because scope §2 names it) or drop it. Dropping it is an owner edit to the catalogue, not an implementer choice.
9. Raise the Swift test floors in M11-E to the measured count (recommended) or leave them at 535 while new tests still pass as extras. Do not lower them.
10. Confirm the single branch name `milestone/m11-catalogue`, or substitute one name. Phases do not get their own branches.

**Unresolved on purpose, with the reason.**

- DSH Homebrew name: `brew info` was not run, and a hit would not define the acronym.
- Gemini formula listing page: not fetched. The install doc’s `brew install gemini-cli` sentence is not that page.
- Aider argv: not in the install page this assignment relied on, and the binary is absent locally.
- Kiro formula versus cask: both are written on the official installation page.
- Qoder command: both are written on official Qoder pages.
- Stdout versus stderr for Claude, Gemini, Goose, Kiro, and Aider: those binaries were not installed, and the docs that mention a flag do not name the file descriptor.
- Codex information URL after the redirect: the GitHub README is sufficient for install facts; the registry URL can stay.
- Whether any new test outside the allow-list also pins the trio. B’s stop condition covers a discovery. This proposal’s search found the pin in `DetectorRegistryTests.swift`, `BundledRegistryResourceTests.swift` (bundled id list only), `BundleResourceTests.swift`, `UpdateCLIIntegrationTests.swift`, `test_dev_app_bundle.py`, and the README sentence. Historical briefs and walkthroughs also mention the trio and are protected.

---

## G. Explicit non-goals

- No new manager mutation adapter. Homebrew Update/Uninstall remains M13. uv remains M14. Cargo remains M15. npm Update/Uninstall already exists and is unchanged.
- No M12 UI or workflow work: no sidebar, filters, keyboard map, or SwiftUI redesign. No app source edits.
- No speculative scanner refactor: no new layout, no new source label, no new package manager, no change to `classifySource` or `extractVersionToken`, no search of version stores.
- No per-tool shell scripts and no executed vendor installers.
- No license file and no public contribution invitation. The recommendation in section D is not a choice.
- No install, update, uninstall, `brew update`, or mutating manager command in any phase.
- No pin of a live version, build hash, or date.
- No edit to `Package.swift`, `DECISIONS.md`, `ROADMAP.md`, or historical walkthroughs.
- No detection row for the OpenCode desktop cask, the Goose desktop cask, the Cline editor extension, the Qoder IDE, the Antigravity desktop app, the Kiro IDE, pressly/goose, or `@oh-my-pi/cli`.

---

## Dispatch checklist

| Phase | Tier | Writes | Skip when |
|---|---|---|---|
| M11-A | strongest | `docs/catalogue-identities.md` | never |
| M11-B | flash | registry, listed tests, anchor name, one README sentence | A held `claude`, `gemini`, or `cline` |
| M11-C | strongest | registry rows for frozen collision tools, same tests and README sentence | a row is not frozen; omit that row rather than guessing. Omit `agy` if decision 2 vetoes it |
| M11-D | strongest | DSH and/or `qodercli` only | unblock list empty (success) |
| M11-E | strongest | matrix, detector guide, JSON proof, optional measured floor raise | B or C incomplete |
| Combined | orchestrator | no feature work | a phase stop is open |
