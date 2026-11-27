# M13 proposal — Grok 4.7 (independent)

Date: 2026-11-21. Council member: Grok 4.7 / high. This file is the only product write.
No other member proposal was read. No file under `Sources/`, `Tests/`, `scripts/`,
`Resources/`, `Package.swift`, `.github/`, or any existing brief, walkthrough, or doc was
edited. No git mutation, build, test, or app launch was run.

**Base.** `milestone/m13-homebrew` at `9b37a334eefd06802daa7bd006c6e995f8698af2`
(`9b37a33`), confirmed with `git rev-parse HEAD` and `git branch --show-current`.
Working tree at planning time: untracked `briefs/M13-planning/` only.

**Revision.** Re-read against the brief after the coordinator clarified that this file may be re-read. `proposal-minimax.md` was not read. Corrections below replace the earlier wording where they disagree: one verifier dispatch rule; a non-string `installed` is only `.invalidManagerOutput`; `brew list --pinned` matches a formula rack basename or a cask token; an older cask absent from plain `outdated` is not `updateAvailable`; cask upgrade keeps an explicit saved app directory and the operation unsets `HOMEBREW_CASK_OPTS`; latest-check cells that declare a cask gain `yes: homebrewCask` (codex and claude included) while their Update/Uninstall cells do not.

**Baseline.** The dispatch states that the orchestrator baseline at `9b37a33` is green
(all 8 local gates exit 0). This proposal did not re-run those gates. Hosted history
cited from `ROADMAP.md` (seven gates, floors Core 467 / AppSupport 119 / total 586,
guard 21, packaging 9) was not re-measured here.

**Homebrew observed for this proposal.** Read-only, with
`HOMEBREW_NO_AUTO_UPDATE=1` and `HOMEBREW_NO_ANALYTICS=1`:

- `brew --version` → `Homebrew 7.0.15-76-g456c79a`
- `brew --prefix` → `/opt/homebrew`
- `brew --cellar` → `/opt/homebrew/Cellar`
- `brew --caskroom` → `/opt/homebrew/Caskroom`
- `brew list --pinned` → empty stdout
- `brew upgrade --help`, `brew uninstall --help`, `brew outdated --help`,
  `brew list --help`, `brew info --help`, `brew pin --help`
- `brew info --json=v2 --cask antigravity-cli`
- `brew info --json=v2 --cask antigravity-cli codex` (two records, exit 0)
- `brew info --json=v2 --cask codex claude-code claude-code@latest kiro-cli antigravity-cli`
- `brew info --json=v2 --formula hermes-agent`
- `brew info --json=v2 --formula gemini-cli cline aider block-goose-cli`
- `brew outdated --json=v2 --cask` (envelope present, `casks` empty)
- `brew outdated --json=v2 --formula` (envelope present; record keys cited below, no package names)

Local Homebrew source reads (not brew mutations), at that same checkout
(`git -C /opt/homebrew rev-parse --short HEAD` → `456c79a994`):
`cmd/uninstall.rb`, `cmd/list.rb`, `cmd/outdated.rb`, `cask/cask.rb`,
`cask/artifact/moved.rb`, `cask/artifact/app.rb`, `cask/artifact/binary.rb`,
`cask/artifact/command_wrapper.rb`, `cask/artifact/symlinked.rb`, `env_config.rb`.
`git -C /opt/homebrew check-ignore -v Cellar Caskroom` both match `.gitignore:2:/*`.
Tracked file count 3536. `.git` is 792K. A clone of the brew repo does not track
Cellar or Caskroom. Do not copy the 4.8G prefix.

---

## A. Current-state audit

### Verified, preserve

These are accepted and phases must not redo or weaken them.

| Fact | Evidence |
|---|---|
| Formula ownership is exactly three queries: `--cellar`, `info --json=v2 --formula <declared>`, `list --verbose --formula <full-name>`. `--installed` is never used. Ownership does not depend on semver or update availability. | `HomebrewOwnershipProbe.swift:1-7`, queries at `:69`, `:131`, `:177` |
| Cask-only declarations on the formula route return `.unsupportedCask` before a manager query, and only after the source was already `"brew"`. | `HomebrewOwnershipProbe.swift:101-105`; `InstallationOwnershipVerifier.swift:146-149` |
| `FormulaProof.revalidate()` re-observes selection, manager, cellar, and keg. | `HomebrewOwnershipProbe.swift:35-52` |
| Manager resolution is the first live `brew` on the ordered login-shell PATH. No inherited PATH, `which`, or hardcoded prefix. | `HomebrewIdentity.swift:25-37` |
| Keg parse is path components under the manager Cellar, not a `/Cellar/` substring. | `HomebrewIdentity.swift:76-102` |
| Formula latest-check batch is at most three commands, `queryTimeout = 10`, diagnostic env sets `HOMEBREW_NO_AUTO_UPDATE=1` and `HOMEBREW_NO_ANALYTICS=1`. | `HomebrewUpdateProbe.swift:1-8`, `:203-204`, `:488-531`, `:542-548` |
| `parseOutdated` reads only `formulae`. Cask payload is not consumed. | `HomebrewUpdateProbe.swift:259-263`, `jsonFormulaRecords` at `:283-300` |
| Formula status uses `homebrewStable`, alias poisoning, and outdated cross-check. Unknown reasons stay typed. | `HomebrewStatusResolver.status` `HomebrewUpdateProbe.swift:554-692`; grammar `VersionComparison.swift:86-110` |
| Formula cache is schema 3, TTL 21600, 1 MiB, full identity keys. npm cache is a different file. | `UpdateMetadataCache.swift:241-256`; `NpmUpdateMetadataCache.swift:287-302` (`npm-update-metadata-v1.json` beside the formula file) |
| `AcceptedOperation` is exactly `npmUpdate`, `npmUninstall`. Absent → `[]`. Null, non-array, non-string, unknown, and duplicate are named errors on both decode paths. | `DetectorMetadata.swift:78-81`, `:270-294` (reason string at `:282`); Codable path `DetectorRegistry.swift:215-239`; JSONSerialization path `DetectorRegistry.swift:1076-1107`. Registry `schemaVersion` is 2 (`DefaultDetectors.json:2`). |
| npm prepare refuses `.operationNotAccepted` as the second statement, after cancellation, before scratch, observation, or a process. | `NpmUpdateOperation.swift:61-63`; `NpmUninstallOperation.swift:51-53` |
| One process-wide mutation gate. Exit zero is not success. Preparations are claim-once. | `OperationModels.swift:104-139`, `:261-278`, `:349-382`; `NpmUpdateOperation.swift:7`, `:209-227`, `:328-355` |
| Budgets: prepare 60s, confirm 60s, mutation 120s. Dual-stream cap 1 MiB per stream. | `NpmUpdateOperation.swift:46-48`; `BoundedProcessRunner.swift:14` used by `runDualStream` (`OperationProcessRunner.swift:51-58`) |
| Pre-launch identity mismatch is `.failed` with `processStarted: false`. No retry. | `NpmUpdateOperation.swift:266-355` |
| Source heuristic: `/lib/node_modules/` → `npm`, `/Cellar/` → `brew`, else `standalone`. Not ownership. | `ToolDetector.swift:184-190` |
| Verifier dispatches only on that heuristic. Standalone never reaches Homebrew. | `InstallationOwnershipVerifier.swift:61-81` |
| CLI dispatches only `scan`, `verify-installation`, `debug-env`. | `main.swift:61-174` (D-022) |
| `ManagementPresentation` is the single affordance source. Formula and cask limits are text. Core `operationNotAccepted` strings are read, not retyped. | `WorkflowPresentation.swift:152-237`, messages at `OperationModels.swift:89` and `:334` |
| Sheets bind to preview / preparation / outcome. C-1: Escape cancels; confirm has no key equivalent. | `UpdateOperationView.swift:73-83`; `UninstallOperationView.swift:73-88`. Public inits at `UpdateOperationView.swift:17` and `UninstallOperationView.swift:18` |
| Invalidation releases a pending preview and does not cancel an executing mutation. | `InventoryViewModel.swift:649-655` |
| Matrix rule: Update/Uninstall `yes` requires the accepted npm operation and an npm declaration. Cask latest-check `yes` is rejected. | `docs/capability-matrix.md:18-21`; `CapabilityMatrixTests.swift:143-232` |
| Only `codex` has `acceptedOperations`. | `DefaultDetectors.json:18` |

Formula-declared catalogue entries (names copied from `DefaultDetectors.json`):
opencode (`anomalyco/tap/opencode-v2`, `anomalyco/tap/opencode`, `opencode`) `:39-41`;
gemini `gemini-cli` `:104`; cline `cline` `:126`; hermes `hermes-agent` `:146`;
aider `aider` `:167`; goose `block-goose-cli` `:187`; omp `can1357/tap/omp` `:229`.
Cask-declared: codex `codex` `:16`; claude `claude-code` and `claude-code@latest` `:81-82`;
kiro-cli `kiro-cli` `:207`; agy `antigravity-cli` `:249`.
Matrix rows for hermes/aider/goose say "formula adapter M13"
(`docs/capability-matrix.md:36-38`). agy row records source `auto_updates: true`
(`docs/capability-matrix.md:39`). kiro-cli and agy latest-check cells are
`disabled: cask latest-check not shipped`.

### ADD

- A cask ownership route that does not use Cellar layout.
- A cask latest-check batch and a separate cache document.
- Four `AcceptedOperation` cases and four Core operations.
- Brew preview types, effect texts, and sheet presentation that keep the npm types unchanged.
- Matrix rules for formula and cask latest-check and for brew mutations.
- A disposable scratch-prefix acceptance harness.
- Typed reasons for cask version grammar, auto-updates, pins, and disabled packages.

### CHANGE (narrow)

- `InstallationOwnershipVerifier` dispatch, so a standalone selection with a declared cask can reach the new probe. The `"brew"` + formula path stays the current probe.
- `UpdateProbeCoordinator` eligibility, so a standalone cask declaration is not forced to `.noRegistry` (`UpdateProbeCoordinator.swift:216-218`).
- Exhaustive `UnknownReason` switches, listed in M13-B. Existing arms stay byte-identical.
- `ManagementPresentation` only in M13-G, and only so an accepted brew operation can become a button. Codex npm predicates stay.
- `docs/capability-matrix.md` and `CapabilityMatrixTests.swift` when the rule changes. Not before the behavior exists.
- `ci.yml` floors only at the combined gate, upward, to orchestrator-measured counts.

### Do not change

`Package.swift`, npm operation control flow, npm preview structs, npm effect texts, the shared gate's semantics, formula batch command list, formula cache schema 3, CLI subcommand set, C-1, the M12 executing-mutation early return, detector schema version 2.

### Not verified in this session

- A non-null cask `installed` string. Every catalogue cask queried here returned `installed: null`. The council brief reports a string-or-null field from an earlier personal observation. The scratch probe must show a string on an installed synthetic cask before M13-A treats that shape as implemented truth.
- A live `outdated --json=v2 --cask` record. This session's `casks` array was empty. The record shape below is from Homebrew source at `456c79a994`, not from a captured cask transcript.
- `list --verbose` output for an installed app cask. The symlink rule is from `moved.rb` and `list.rb`, not from a captured listing.
- Whether a nonstandard prefix will install a local-tap formula and cask with network denied. That is the judge's probe, not a guess here.
- `gemini-cli` / `cline` disable dates are future relative to 2026-11-21, and `disabled` is JSON `false` today. See OD-M13-1.

---

## B. Phase decomposition

Nine sequential phases on `milestone/m13-homebrew`. One product writer at a time.
No phase edits `ci.yml` except M13-I. No phase promotes a catalogue entry except
M13-H, and only after the owner answers OD-M13-1. If the owner selects no
promotions, M13-H is recorded vacuous and M13-I still runs.

Shared local gate for A–H (same commands as `briefs/M12-plan.md` §5; floors are
minima, so Core growth does not by itself fail them):

```sh
env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS swift build
env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS \
  swift test --build-system swiftbuild --scratch-path <scratch>/full-suite --no-parallel \
  -Xswiftc -load-plugin-library \
  -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib
python3 scripts/check-core-ui-imports.py
python3 scripts/check-core-ui-imports.py --source-root Sources/AgentLensAppSupport
python3 Tests/Packaging/test_core_ui_imports.py
python3 scripts/build-dev-app.py --scratch-root <scratch>/app --configuration debug
python3 Tests/Packaging/test_dev_app_bundle.py --app <scratch>/app/AgentLensApp-debug.app
git diff --check
```

Expected for A–H: exit 0; zero skips and failures; guard 21; packaging 9;
Core ≥ 467; AppSupport ≥ 119. The implementer prints the observed counts and
does not edit floors. `git diff --check` is local only. Hosted CI stays the
seven gates in `.github/workflows/ci.yml`.

Protected in every phase unless that phase's allow-list names the file:
`Package.swift`, `Sources/agent-lens/main.swift` (dispatch), `DefaultDetectors.json`
accepted-operations values, npm operation files' control flow, formula probe
command list, formula cache schema, historical briefs and walkthroughs,
`ROADMAP.md`, `DECISIONS.md`, `AGENT_LENS_SCOPE.md`. A phase that must touch a
protected file stops.

**M13-A does not start until the judge's feasibility probe in section G passes
the demonstrations marked BLOCKING.**

### M13-A — Cask ownership (read-only)

- **Goal.** A selected executable is verified as a declared cask only by the four-query proof in section C. `verify-installation` gains that route with no new CLI syntax.
- **Non-goals.** Latest-check, cache, operations, promotions, sheet changes, source-heuristic edits, `DefaultDetectors.json` edits.
- **Allow-list (production).** New `Sources/AgentLensCore/Ownership/HomebrewCaskOwnershipProbe.swift`. New `Sources/AgentLensCore/Updates/HomebrewCaskIdentity.swift` (path-component parser only). Modify `InstallationOwnership.swift` (new reason cases and their `message` arms only; existing messages byte-identical). Modify `InstallationOwnershipVerifier.swift` (dispatch only, per section C).
- **Allow-list (tests).** New `Tests/AgentLensCoreTests/HomebrewCaskOwnershipTests.swift`. Additive cases in `InstallationOwnershipTests.swift` only where an existing assertion would otherwise require the old standalone-cask result.
- **Do not edit** even if convenient: `ToolDetector.swift`, `HomebrewOwnershipProbe.swift`, `HomebrewUpdateProbe.swift`, `main.swift`, `WorkflowPresentation.swift`, `DefaultDetectors.json`. `NpmUpdateProbe.mapOwnershipReason` and `NpmUninstallOperation.map` already have `default` arms (`NpmUpdateProbe.swift:1369`, `NpmUninstallOperation.swift:672`). Leave them. New cask reasons must not be routed through those mappers.
- **Contracts.** Formula three-query proof unchanged. A `/Cellar/` or `/Caskroom/` substring is never proof. Declaration and basename are never proof. `.metadata` paths are never proof. npm-classified selections never enter the cask probe (codex npm stays npm).
- **Review.** Both council models. Ownership.
- **Acceptance.** New tests RED then GREEN for every refusal in section C, plus one positive binary-style fixture and one positive moved-app symlink fixture, using a scripted `UpdateCommandRunner` and a synthetic filesystem. No personal prefix. Orchestrator reruns the shared local gate.
- **Stop.** Probe BLOCKING items failed. Compiler names an exhaustive switch outside the allow-list. Any test rewrites a formula-ownership assertion to make it pass.

### M13-B — Cask latest-check and separate cache (read-only)

- **Goal.** Opt-in cask latest-check with the tri-state rules in section F. Unknown never becomes up to date and never increments the update count.
- **Non-goals.** Mutations, promotions, `--greedy`, `brew update`, UI buttons.
- **Allow-list (production).** New `Sources/AgentLensCore/Updates/HomebrewCaskUpdateProbe.swift`. New `Sources/AgentLensCore/Updates/CaskUpdateMetadataCache.swift`. Modify `VersionStatus.swift` (four new `UnknownReason` cases only). Modify `UpdateScanRenderer.swift` (`explanation` at `:101`) and `ToolDetailView.swift` (`plainLanguageReason` at `:619`) for the new arms only; existing strings byte-identical. Modify `NpmUpdateOperation.swift` `map(_: UnknownReason)` at `:627` for the new arms only, each mapping to `.probeFailed`; existing arms byte-identical. Modify `UpdateProbeCoordinator.swift` to run the cask batch after the formula batch under the existing admission gate.
- **Allow-list (tests).** New cask probe, cache, and coordinator tests. Modify `CapabilityMatrixTests.swift` (`latestCheckProblems` at `:207-233`) and `docs/capability-matrix.md` latest-check cells only, using the rule in section E. Mutation cells are not edited in this phase. `yes: homebrewCask` means the read-only probe is shipped, not that a comparison succeeded. The cross-row note still says cask paths classify `standalone`.
- **Review.** Both council models. Truthfulness of latest-check is a safety invariant (D-007).
- **Stop.** Another exhaustive `UnknownReason` switch fails the build. Add that file only for the new arms, and stop if the edit would change an existing arm. Do not weaken `CapabilityMatrixTests.swift:230` until the new rule replaces it in the same commit.

### M13-C — Vocabulary and formula Update/Uninstall

- **Goal.** Closed vocabulary gains formula operations. Formula prepare/execute implements section D. Shipping registry still accepts no formula operation. Codex npm behavior stays.
- **Non-goals.** Cask operations, catalogue promotion, UI buttons, CLI mutation syntax.
- **Allow-list (production).** `DetectorMetadata.swift` (`AcceptedOperation` and the validation reason string). `DetectorRegistry.swift` only if a test shows a path still hardcodes the old reason (both paths call `DetectorMetadataValidation.acceptedOperations`, so a one-line reason change in the helper covers both). New `Sources/AgentLensCore/Operations/HomebrewFormulaUpdateOperation.swift` and `HomebrewFormulaUninstallOperation.swift`. Modify `OperationModels.swift` by appending formula preview types, reasons, effect texts, and deltas. Do not edit npm structs or npm effect texts. Scratch: call existing `NpmScratchRoot.claim` and `releaseOperationRoot`. Do not rename them.
- **Allow-list (tests).** New formula operation tests. Registry rejection tests on both decode paths for the new names, plus the old rejection cases still failing closed.
- **Review.** Both council models. Mutation and D-021.
- **Acceptance.** Scripted runner. Assert the exact argv and the exact environment keys in section D. Assert acceptance guard ordering with a runner that fails the test if `run` is called. Assert shared-gate exclusion against a second acquisition. Assert Cancel releases the scratch and launches nothing. Assert pre-launch target-string mismatch launches nothing (`processStarted == false`, state `.failed`). No real `brew` in this phase.
- **Stop.** Any diff inside `NpmUpdateOperation` execute control flow, or any change to `npmUpdateEffectText` / `npmUninstallEffectText`.

### M13-D — Cask Update/Uninstall

- **Goal.** Cask operations from section D, including the whole-cask effect text on the Core preview.
- **Non-goals.** Promotion, UI, `--zap`, `--greedy`.
- **Allow-list.** New `HomebrewCaskUpdateOperation.swift` and `HomebrewCaskUninstallOperation.swift`. Append cask preview types to `OperationModels.swift`. Tests in a new file.
- **Review.** Both council models. Mutation. A preview whose effect text does not contain the companion-app sentence and the zap refusal is a failed phase even if the process is correct.
- **Acceptance.** Scripted. Argv assertions. A fixture cask whose zap stanza names a sentinel path: the argv must not contain `--zap` and the plan must not contain that path as an argument. Cancel leaves the scratch prefix hash unchanged (hash helper lands in M13-E; this phase asserts no process launch).

### M13-E — Disposable real-Homebrew harness

- **Goal.** The section G fixture, run by the orchestrator against a scratch prefix. Proves preview/Cancel, formula Update, formula Uninstall, pin refusal, dependent-uninstall failure, manager failure, stale target, cask Update, cask Uninstall with the scratch app removed and the zap sentinel left, interruption, and concurrent confirm.
- **Non-goals.** Personal prefix. `/Applications`. Catalogue promotion. Network.
- **Allow-list.** New `Tests/Fixtures/M13/homebrew_acceptance.py` and a short README beside it that states it is a fixture, not acceptance evidence. No `Sources/` edits unless a fixture bug forces a one-file correction; that correction returns as a revision of C or D, not a silent harness patch.
- **Review.** Both council models. Real mutation.
- **Acceptance.** Orchestrator runs the fixture. Implementer transcript is not acceptance (D-014). Sentinel hashes match. Personal prefix `brew --prefix` still `/opt/homebrew` after the run.

### M13-F — Capability-matrix mutation rule, zero promotions

- **Goal.** Test-enforced rule in section E. No `acceptedOperations` value changes. Every brew mutation cell stays `informational:` or `disabled:`.
- **Allow-list.** `docs/capability-matrix.md`, `CapabilityMatrixTests.swift`, and the contributor sentence that points at the matrix if a test already requires it to mention the new rule. No registry JSON edits.
- **Review.** Both council models. The matrix is the public contract.
- **Stop.** Any row's Update/Uninstall cell becomes `yes`.

### M13-G — App and CLI presentation

- **Goal.** Section H. Brew sheets reuse the C-1 footer and the M12 invalidation contract. CLI stays read-only.
- **Allow-list.** `WorkflowPresentation.swift`, `InventoryViewModel.swift`, `InventoryService.swift` (only to forward the new Core prepare/execute), new brew sheet views under `Sources/AgentLensApp/`, `ToolDetailView.swift` only to present the new sheets, AppSupport tests. `main.swift` is not edited. `verify-installation` already calls the verifier. `scan --check-updates` already calls the coordinator.
- **Review.** Both council models. Confirmation safety.
- **Acceptance.** AppSupport tests for affordance truth table. A host-level test that the public `UpdateOperationView` initializer still accepts `NpmUpdatePreview` (source compatibility with the M10-D host). Native click-through is orchestrator-run with the M13-E fixture, method in section H. Codex npm Cancel/Confirm strings unchanged.

### M13-H — Owner promotions (OD-M13-1)

- **Goal.** Apply only the owner's list. Each promoted entry gets its own fixture scenario in the M13-E harness, using a synthetic package that stands in for that identity's manager kind (formula vs cask), not the personal install.
- **Allow-list.** `DefaultDetectors.json` `acceptedOperations` for the named ids only. Matrix cells for those ids only. One new fixture scenario per id.
- **Review.** Both council models if any id is promoted.
- **Stop.** The owner has not answered. An id not on the owner's list. A cask promotion while `auto_updates` is still null in `brew info` for that token (section E). Empty owner list → vacuous phase, no commit required beyond the judgment note.

### M13-I — Combined gate (orchestrator)

- **Goal.** Rerun A–H evidence plus the full local gate and the seven hosted gates at one SHA. Bump floors upward to the measured Core and AppSupport counts only. No feature edits.
- **Allow-list.** `.github/workflows/ci.yml` floor numbers only, plus the walkthrough the orchestrator writes. The implementer does not write this phase.
- **Review.** Orchestrator acceptance. No second product writer.

---

## C. Cask identity and ownership

### What must not be reused

Cellar decomposition (`HomebrewTargetParser.parse`) does not apply. Cask binaries classify `standalone` today (`ToolDetector.swift:187-190`, matrix lines 45-49). Do not add a `/Caskroom/` substring to `classifySource`. That would both false-positive and send casks into the formula probe.

### Manager facts this design uses

`brew list --help`: named casks are allowed as a list (`installed_formula|installed_cask ...`).
With `--verbose`, or whenever stdout is not a TTY, `cmd/list.rb:200-204` runs
`find <each caskroom_path> -not -type d -not -name .DS_Store -print`.
Directories are omitted. A symlink is printed.

`cask/artifact/moved.rb:176-178` `post_move` runs `FileUtils.ln_sf target, source`
after an app (or other moved artifact) is moved. The staged path inside the
Caskroom becomes a symlink to the final target. `App` is a `Moved`
(`cask/artifact/app.rb:10`).

`Binary` is a `Symlinked` (`cask/artifact/binary.rb:9`). The staged file stays
in the Caskroom and a symlink is created at the target (prefix `bin` by default).
`CommandWrapper` subclasses `Binary` (`cask/artifact/command_wrapper.rb:13`).

So the selected executable is proved by a path the manager listed, not by a
declaration:

- **Binary / command_wrapper.** The PATH entry's canonical target is the staged file under `<caskroom>/<token>/<installed-version>/…`. That file is a `find` line. Canonical-path equality.
- **Moved app.** `find` prints the staged symlink, not files inside `/Applications`. The selected canonical path must be a strict descendant of that symlink's resolved target (or equal to it). Use `FileIdentityObserver.isStrictDescendant` (already used at `HomebrewOwnershipProbe.swift:117`).

`.metadata/**` lines are ignored for membership. They never prove ownership.
A match on basename, on a Caskroom substring, or on an `info` artifact target
string alone is a failed test, not a success.

### Queries (one verification, in order)

Re-observe the selected executable and the manager around every query, same as
the formula probe. Environment is `HomebrewUpdateProbe.diagnosticEnvironment`
(`:542-548`). Timeout is `queryTimeout` (10s). Runner is the existing
`UpdateCommandRunner`. Never `--installed`.

1. `brew --prefix` → one absolute path. This is the manager prefix.
2. `brew --caskroom` → one absolute path. Do not derive it from the prefix.
   `HOMEBREW_CASKROOM` can differ. Do not require the Caskroom to be inside the prefix.
3. `brew info --json=v2 --cask <declared names…>` once, for every declared
   `homebrewCask` on this detector. Cap 4 names. More than 4 → `.ambiguousOwnership`
   with no process. Claude declares 2 (`DefaultDetectors.json:81-82`).
4. `brew list --verbose --cask <full_token>` once, and only after step 3
   produced exactly one installed record. `full_token` is the argument, not the
   executable basename.

That is four queries, not three. Formula needs one root (`--cellar`). Cask
needs prefix and Caskroom separately. Do not merge them by string-trimming
the prefix.

### Record match

From the live `info --json=v2 --cask` envelope (`root` keys `casks` and
`formulae`; this session, antigravity-cli and the five-token batch):

- Use the `casks` array only. A missing `casks` array, a non-object element, or
  a non-UTF-8 body (same BOM/NUL rules as `HomebrewUpdateProbe.strictUTF8Text`,
  `:312-319`) is `.invalidManagerOutput`.
- Exactly one record may match. Zero → `.noMatchingPackage`. Two → `.ambiguousOwnership`.
- Match rule: declared name equals `full_token`, or declared name equals `token`
  while `full_token == token`. A tap-form declaration must equal `full_token`
  exactly. This session's five catalogue casks all had `full_token == token`
  (core cask tap in the `tap` field, not inside `full_token`). A third-party
  tap whose `full_token` is not the declared string fails closed
  (`.caskRecordMismatch`). The probe must install one tap cask and record the
  real `full_token` before any tap cask is promotable. opencode/omp are formulae,
  not casks.
- `old_tokens` was a string list (`kiro-cli`: `amazon-q`, `codewhisperer`).
  If the declared name is in `old_tokens` and is not `token` / `full_token`,
  refuse `.caskTokenRenamed`. Do not retarget to the new token.
- `rename` was an empty list on every catalogue cask queried. Element shape is
  unverified. A non-empty `rename` refuses `.caskTokenRenamed` without parsing
  elements.
- `installed: null` → `.packageNotInstalled` (existing reason; message already
  says the package is not installed). Do not verify.
- `installed` a string → the version path component must equal that string.
  Mismatch → new reason `.selectedCaskNotInstalled`.
- `installed` any other JSON type → `.invalidManagerOutput` only. Do not also
  emit `.caskRecordMismatch` for the same value. The non-null string is
  probe-gated (section A).
- Version directory parse: path components of the listed file must be
  `<caskroom>/<token>/<installed>/<rest…>` with no empty, `.`, or `..` component.
  Same discipline as `HomebrewTargetParser` (`HomebrewIdentity.swift:88-94`).

### Version grammar is not ownership

Ownership succeeds for `version == "latest"` and for comma versions
(`antigravity-cli` version `1.5.13,5999302598852608` this session) when the
path and `installed` string agree. `parseHomebrewStable` returning nil
(`VersionComparison.swift:91-110`) must not fail ownership. The formula probe
already states this (`HomebrewOwnershipProbe.swift:7`).

`claude-code@latest` reported version `2.1.329`, not the string `latest`.
The `@latest` in the token is an identity character allowed by
`DetectorMetadata.swift:151`. Only the exact version string `latest` is the
`:latest` grammar.

### auto_updates, deprecated, disabled, pins

These do not block ownership.

- `auto_updates` on all five catalogue casks was JSON `null` this session,
  including `antigravity-cli`, while `docs/capability-matrix.md:39` says the
  cask source sets `auto_updates: true`. Provenance is unresolved. Do not treat
  null as false.
- `deprecated` and `disabled` were JSON bools. `gemini-cli`: `deprecated true`,
  date `2026-06-18`, reason `unsupported`, `disabled false`, `disable_date`
  `2026-12-18`. `cline`: `deprecated true`, date `2026-05-18`, `disabled false`,
  `disable_date` `2027-05-18`. Future disable dates are not `disabled: true`.
- `pinned` was a bool and `pinned_version` was null on the uninstalled casks.
  A pinned cask is still owned.

### New `InstallationOwnershipReason` cases

Add cases; do not change existing messages (`InstallationOwnership.swift:96-160`).

| Case | When |
|---|---|
| `caskRecordMismatch` | `token`, `full_token`, or the declaration rule disagree, as specified above. Not used for a bad `installed` JSON type. |
| `caskTokenRenamed` | Declared name is only an `old_tokens` entry, or `rename` is non-empty |
| `selectedCaskNotInstalled` | `installed` is a string and does not equal the version path component |
| `selectedCaskNotConfirmed` | At least one non-metadata line sits under `<caskroom>/<token>/<installed>/`, and none of those lines equals the selected path or is a symlink whose target is an ancestor of it |
| `caskArtifactUnlinked` | The cask is installed, the listing is well-formed, and no non-metadata line resolves to the selected executable (the moved-app symlink is missing). Do not use this when a line under the version directory exists but names a different file; that is `selectedCaskNotConfirmed`. |

Reuse existing cases for manager failure (`.managerQueryFailed`), bad output
(`.invalidManagerOutput`), layout that is not `<caskroom>/<token>/<version>/…`
(`.unsupportedInstallationLayout`), ambiguous declarations (`.ambiguousOwnership`),
cancellation, and changed files during the proof (`.selectedExecutableChanged`,
`.managerChanged`, `.proofChanged`).

`VerifiedInstallation` for a cask: `manager == .homebrewCask`, `packageName` is
`full_token`, `managerRoot` is the prefix from `--prefix`, `installationRoot`
is the canonical `<caskroom>/<token>` directory. The renderer already prints
those labels (`InstallationOwnershipRenderer.swift:18-27`). Do not add fields
to `VerifiedInstallation` in M13-A.

### Verifier dispatch

`InstallationOwnershipVerifier.verify` switches on source at `:61-81`. `"brew"`
calls `verifyHomebrew` (`:139-149`), which returns `.unsupportedCask` when no
formula is declared. Every other source returns `.unsupportedSource` at `:81`
before a cask declaration is considered. Replace that with this order only.
Do not add a second fall-through rule.

1. Source `"npm"` → existing npm probe. Stop. A cask declaration on the same detector is ignored. Codex (`DefaultDetectors.json:15-16`) stays npm when the copy classifies `npm`.
2. Source `"brew"` and the detector declares at least one formula → existing formula probe. Stop, including on `.noMatchingPackage` and `.unsupportedInstallationLayout`. Do not fall through to the cask probe. A path classified `brew` is a Cellar candidate; a failed formula proof stays a failed formula proof.
3. Source `"brew"` and the detector declares no formula but declares a cask → cask probe. This replaces the `.unsupportedCask` return at `:146-149`. Keep the enum case and its message byte-identical for any direct caller of the formula probe that still passes only casks.
4. Any other source, including `"standalone"`, and the detector declares a cask → cask probe. Do not run the formula probe on these paths. This is the route for cask binaries and moved apps.
5. Otherwise → existing `.unsupportedSource` (`:81`) or `.noDeclaredPackage`.

No catalogue row declares both a formula and a cask. A synthetic definition that does:
source `"brew"` uses rule 2 only, source `"npm"` uses rule 1 only, any other source uses rule 4 only.
One verification never runs both probes. Codex classified `standalone` uses rule 4 because it declares `homebrewCask:codex`.

### Latest-check batch membership (M13-B, same rule)

The batch may not call `list` once per tool. One
`brew list --verbose --cask <tokens…>` for every token whose `info.installed`
is a string. `list.rb:203` raises if a named cask is not installed, so
not-installed tokens are omitted. If that combined `list` fails, every cask
subject in the batch is `unknown(.probeFailed)`, never up to date. Lines are
partitioned by path components under each token's `<caskroom>/<token>/`.
A line under none or two of those directories is `.invalidManagerOutput` for
the subjects involved.

Cap the `find` output at 4096 lines or 1 MiB, matching
`BoundedProcessRunner.maximumStandardOutputBytes`. Over the cap →
`.invalidManagerOutput`, even if a match was already seen. Same "malformed
output stays invalid" rule as `HomebrewOwnershipProbe.listConfirmsSelectedPath`
(`:339-361`).

---

## D. Formula and cask operations

### Lifecycle (copy M10, do not invent a second one)

For each of the four operations:

1. `prepare`: if cancelled, return `.cancelled`. Next statement is the
   `acceptedOperations` guard, before scratch claim, cache, or any process.
   Then fresh ownership and fresh `info`. No cache read or write.
2. Build a preview bound to the observed target string. Claim one mode-0700
   `NpmScratchRoot` (`NpmUpdateProbe.swift:417`, `claim` at `:440`). Working directory of the
   later process is that scratch, not the repo and not the prefix.
3. `cancel` releases only that root (`releaseOperationRoot`).
4. `execute` acquires `OperationExecutionGate` (production: `.shared`). Failure
   to acquire releases the unconsumed preparation and does not launch.
   Re-scan, re-verify, re-fetch `info`. Any bound-fact mismatch → `.failed`,
   `processStarted: false`, same messages as `NpmUpdateOperation.swift:266-355`
   ("a new preview is required" / "no mutation was started").
5. Launch the exact argv once. Timeout 120s. Dual-stream, 1 MiB per stream.
6. After launch, always reconcile. Exit 0 is not success. No automatic retry.
   Cancellation after launch is `.interrupted` and still reconciles
   (M10-D walkthrough: a cancelled caller after launch is interrupted, not a
   silent success).
7. Prepare and confirm budgets are 60s each (`NpmUpdateOperation.swift:46-47`).

The preview target is the exact string observed at prepare:

- Formula: `HomebrewFormulaRecord.packageVersion` (`HomebrewUpdateProbe.swift:143-145`), which is `stable` or `stable_revision`.
- Cask: the `info` `version` string, and only when section F allows an update.

Execute invalidates when that string differs, even if `homebrewStable` ordering
would call the two strings equal. Brew's argv does not carry a version.
`HOMEBREW_NO_AUTO_UPDATE=1` keeps brew from refreshing taps during the command.
It does not freeze a target another `brew update` already changed. Revalidation
is what freezes it.

### Argv (literal; one package name; never a shell string)

Formula update:

```text
brew upgrade --formula --yes <full-name>
```

Cask update:

```text
brew upgrade --cask --yes <full_token>
```

Formula uninstall:

```text
brew uninstall --formula <full-name>
```

Cask uninstall:

```text
brew uninstall --cask <full_token>
```

`--yes` is required on upgrade because `brew upgrade --help` says ask mode is
the default ("Do not ask for confirmation… Ask mode is the default… if
`$HOMEBREW_NO_ASK` is set"). The in-app sheet is the confirmation. The flag is
visible in the preview. Uninstall help has no `--yes`; do not pass it.

Forbidden in every argv, asserted by tests: `--force`, `--zap`,
`--ignore-dependencies`, `--greedy`, `--greedy-latest`, `--greedy-auto-updates`,
`--overwrite`, `--build-from-source`, `--installed`, `--dry-run`, `--appdir`,
`--skip-cask-deps`, `update`, `pin`, `unpin`, `cleanup`, `autoremove`, and a
missing package name. Do not pass `--skip-cask-deps`: `cmd/upgrade.rb:135-137`
defines it as "Skip installing cask dependencies." Omitting it means a cask
upgrade may install dependencies the new cask requires. The effect text says
so. Unrelated casks are not named, so they are not upgraded.
`brew upgrade --formula` with no name upgrades all outdated formulae
(`brew upgrade --help`). The argv builder takes the verified full name and
refuses if it is empty or starts with `-`.

### Environment

Start from `diagnosticEnvironment` (already sets `HOMEBREW_NO_AUTO_UPDATE=1`
and `HOMEBREW_NO_ANALYTICS=1`). Then, for the mutation process only:

Set on upgrade and uninstall:

- `HOMEBREW_NO_INSTALL_CLEANUP=1` — `env_config.rb:603-607`: install, upgrade, and reinstall will not run cleanup, including the periodic full cleanup. `brew upgrade --help` states cleanup otherwise runs for the upgraded packages or, every 30 days, for all packages.
- `HOMEBREW_NO_AUTOREMOVE=1` — `env_config.rb:538-541`. `cmd/uninstall.rb:164-170` autoremoves after uninstall unless this is set. `cleanup.rb` autoremoves from cleanup unless this is set (tests in `test/cmd/uninstall_spec.rb` and `test/cleanup_spec.rb` at this checkout). Disabling cleanup is not a reason to leave autoremove on.

Set on upgrade only:

- `HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1` — `env_config.rb:596-600` and `brew upgrade --help`: otherwise upgrade or reinstall runs for outdated dependents and dependents with broken linkage. That is a second package mutation. Do not set this on uninstall. Uninstall's dependent failure is a different check (`--ignore-dependencies` in uninstall help) and must remain at brew's default so a depended-on formula fails honestly.

Unset if present, so the user's login environment cannot widen the command:

- `HOMEBREW_UPGRADE_GREEDY`
- `HOMEBREW_UPGRADE_GREEDY_CASKS`
- `HOMEBREW_NO_UPGRADE_QUIT_CASKS` (cask upgrade may quit a running app and then reopen it; the effect text says so; a user-set suppressor would make the disclosure false)
- `HOMEBREW_AUTOREMOVE` (`cmd/uninstall.rb:164-167` treats it as a no-op warning)
- `HOMEBREW_CASK_OPTS` on cask upgrade and cask uninstall only. See the app-directory paragraph below.

`HOMEBREW_NO_INSTALL_CLEANUP` is set on uninstall as well as upgrade so one
mutation environment cannot be copied onto an upgrade with cleanup left on.
`brew uninstall` itself does not consult that variable. It autoremoves unless
`HOMEBREW_NO_AUTOREMOVE` is set (`cmd/uninstall.rb:168-170`).
`env_config.rb:603-607` names install, upgrade, and reinstall for the cleanup
switch. The uninstall effect text claims autoremove, not cleanup.

### Cask app directory

Do not pass `--appdir`. Homebrew's default app directory is `/Applications`
(`cask/config.rb:23`). On upgrade, `cask/upgrade.rb:398` reads `old_cask.config`
and `:411` assigns `new_cask.config = new_cask.default_config.merge(old_config)`.
`Config#merge` (`cask/config.rb:231-232`) builds
`old_config.explicit.merge(default_config.explicit)`, so the new cask's
explicit keys win on collision. This plan passes no `--appdir`, so
`default_config.explicit` has no app directory and the saved explicit app
directory remains. Unsetting `HOMEBREW_CASK_OPTS` clears the env layer, which
is separate from explicit. An install that passed `--appdir` stores
that path in `explicit`. `merge` does not copy the saved `env` layer, so a
directory that was chosen only by `HOMEBREW_CASK_OPTS` at install time is not
what upgrade reuses. Lookup order after that is explicit, then the current
process `HOMEBREW_CASK_OPTS`, then the default (`cask/config.rb:218-221` and
the env reader at `:149-166`). Unsetting `HOMEBREW_CASK_OPTS` stops the current
process from filling a missing explicit directory. If the saved config has no
explicit app directory, Homebrew uses `/Applications`. The effect text says that.
The fixture installs `m13app` with `--appdir` inside the scratch so `explicit`
is set. The judge probe must show the upgraded app stays in that directory.

The installed cask object loads `.metadata/.../config.json` when that file
exists (`cask.rb:156-160`, path at `:423-425`). The installer writes it
(`cask/installer.rb:629-630`). Agent Lens does not parse that file for
ownership. Uninstall loads the installed cask, so it uses the saved config
rather than a fresh default, when the file exists.

Cask upgrade with quit enabled calls `reopen_apps_after_upgrade` when quit is
true (`cask/upgrade.rb:504`, implementation `:349-372`). Because this plan
unsets `HOMEBREW_NO_UPGRADE_QUIT_CASKS` and does not pass `--no-quit`, a running
app may be quit and then reopened. The effect text says both.

Do not set `HOMEBREW_CACHE`, `HOMEBREW_LOGS`, or `HOMEBREW_TEMP`. Homebrew keeps
its own cache, logs, and temp. Agent Lens does not delete them. Do not point
them at the operation scratch: deleting the scratch would then be cache
deletion (D-008). Disclose the writes in the effect text.

Do not set `HOMEBREW_NO_INSTALL_FROM_API` on production operations. The fixture
may set it so the scratch prefix does not touch the network. That setting stays
in the fixture's environment, not in `diagnosticEnvironment`.

### Effect texts (copy verbatim into `OperationModels.swift`)

Formula update:

```text
Homebrew will upgrade only the named formula to the observed target version. Agent Lens passes --yes because this confirmation is the review step; Homebrew's own ask prompt is suppressed. --force is not passed. Homebrew may install new dependencies that the new version requires. Already-installed dependents are not upgraded or reinstalled (HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1). Homebrew cleanup and autoremove are disabled for this command (HOMEBREW_NO_INSTALL_CLEANUP=1, HOMEBREW_NO_AUTOREMOVE=1), so old kegs, the download cache, and unused dependencies are left in place. brew update is not run. Homebrew may still write its own cache, logs, and temporary files. No rollback or atomicity is guaranteed.
```

Formula uninstall:

```text
Homebrew will uninstall only the named formula. If another installed formula depends on it, Homebrew fails and Agent Lens will not retry, force, or ignore dependencies. Autoremove of unused dependents is disabled (HOMEBREW_NO_AUTOREMOVE=1). --force, --zap, and --ignore-dependencies are not passed. Configuration, caches, and Homebrew's download cache are not deleted by Agent Lens. No rollback or atomicity is guaranteed.
```

Cask update:

```text
Homebrew will upgrade only the named cask to the observed target version. Agent Lens passes --yes because this confirmation is the review step. --greedy, --force, --zap, --appdir, and --skip-cask-deps are not passed. A running companion app may be quit and then reopened by Homebrew. Homebrew may install new dependencies that the new cask requires. Formula dependents are not upgraded (HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1). Cleanup and autoremove are disabled (HOMEBREW_NO_INSTALL_CLEANUP=1, HOMEBREW_NO_AUTOREMOVE=1). brew update is not run. An app directory recorded as an explicit install option is kept. If none was recorded, Homebrew's default app directory is /Applications. Agent Lens unsets HOMEBREW_CASK_OPTS so that variable cannot choose a directory. No rollback or atomicity is guaranteed.
```

Cask uninstall (whole-cask disclosure; required on the Core preview, not only the view):

```text
Homebrew will uninstall the named cask. This runs the cask's uninstall stanza and removes its linked artifacts. Cask removal may remove a companion app, not only the selected CLI. Agent Lens does not pass --zap, so files listed only in the zap stanza, including configuration and caches, are not targeted. --force and --ignore-dependencies are not passed. Autoremove of unused formula dependents is disabled (HOMEBREW_NO_AUTOREMOVE=1). No rollback or atomicity is guaranteed.
```

### Preview fields

Besides the npm-shaped identity fields (registry id, display name, selected
entry and target, manager executable, literal argv, working directory, effect):

- `kind`: `formula` or `cask`
- `packageName`: formula `full_name` or cask `full_token`
- `prefix`: `brew --prefix`
- `managerRoot`: Cellar for a formula, Caskroom for a cask
- `installationRoot`: keg directory or `<caskroom>/<token>`
- `installedVersion` and `targetVersion`: exact observed strings
- `pinned`: must be false for a ready update or uninstall preview
- `deprecation`: optional disclosed string when `deprecated == true`; does not by itself refuse
- `companionDisclosure`: the cask-uninstall effect text (non-empty). Empty for formulae.

### Pins

`brew pin --help`: pin exists for formulae and casks. Pinned packages are not
upgraded. "Pinned casks with auto_updates true may update themselves outside
Homebrew." Agent Lens never runs `brew unpin` or `brew pin`.

`info.pinned` must be a JSON boolean. Any other type, including a missing
field, is `.invalidManagerOutput`. `pinned_version` must be a string or null.
Any other type is `.invalidManagerOutput`.

`.pinned` is the refusal only when `info.pinned` is true and the unscoped
`brew list --pinned` match below is also true. A non-null `pinned_version`
while `pinned` is false is `.identityUnverified` even if the list matches.
`pinned: true` with `pinned_version` null is still a pin when the list matches.

`list.rb:283-287` prints a pinned formula as the rack basename, plus the pin
target only when `--versions` is passed. `list.rb:291-295` prints a pinned
cask as the token, same `--versions` rule. This plan does not pass
`--versions` or a package name. A named query warns when the package is not
pinned (`list.rb:255-258`). This session's unscoped command printed nothing,
so the line shape is from that source, not from a captured line.

Match a formula when a line equals the last `/` component of the verified
`full_name` (the whole string when there is no slash). Match a cask when a
line equals `token`. Do not require `user/repo/name` or `full_token` to appear.
If that short name appears on more than one line, the result is
`.identityUnverified`, not `.pinned`. Do not persist the full pinned list.
Keep only the boolean for this package. Empty stdout means nothing is pinned
(observed this session).

If `info.pinned` and that list boolean disagree → `.identityUnverified`, not a
silent upgrade and not an unpin. A pin that appears between prepare and
execute fails the revalidation and launches nothing.

Latest-check of a pinned but comparable formula may still be `updateAvailable`
when the selected keg is older than `packageVersion`. The Updates row must show
the pin reason and must not offer the button (M13-G). The count includes that
row because a newer version was actually observed (D-007 counts
`updateAvailable` only; a pin is not an unknown). OD-M13-2 if the owner wants
pinned rows excluded from the count.

### Disabled, deprecated, unsupported versions

Update prepare refuses:

- `disabled == true` → `.formulaDisabled` or `.caskDisabled`. Surface `disable_reason` when it is a string, truncated to 200 characters. `cask.rb:475` returns not-outdated for disabled casks, so absence from `outdated` is not currency.
- cask `auto_updates == true` → `.caskAutoUpdates`
- cask `auto_updates` null or missing → `.caskAutoUpdatesUnverified`
- cask version string exactly `latest` → `.caskTracksLatest`
- version not accepted by `parseHomebrewStable` / `isSupportedUpstreamVersion` (`HomebrewUpdateProbe.swift:372-377`) → `.unsupportedVersion`. This includes `antigravity-cli`'s comma version.
- pinned → `.pinned`
- not strictly older than the observed target → existing `.notUpdateAvailable` / `.newerThanMetadata` analogues

`deprecated == true` with `disabled == false` does not refuse. The preview shows
the deprecation date and reason. `gemini-cli` and `cline` are in this state
today (section A). They are not promotion candidates (OD-M13-1).

Uninstall prepare does not refuse for deprecated, disabled, `:latest`, comma
versions, or null `auto_updates`. It still refuses when ownership fails, the
operation is not accepted, the pin records disagree, or the manager cannot be
queried. A disabled package the user wants gone must remain uninstallable.
Uninstall still refuses `.pinned` rather than unpinning. If brew itself refuses
to uninstall a pinned cask, that nonzero exit is an honest `.failed` result.

### Dependent-formula uninstall

Do not preflight with `brew uses` or `brew deps`. Those commands are not part
of the pinned query budget, and a stale graph is not a reason to pass
`--ignore-dependencies`. Execute `brew uninstall --formula <full-name>`.
Nonzero exit, package still installed, sentinel packages unchanged → state
`.failed`, `processStarted: true`, reconciliation shows the keg still present.
The stderr is the result. No second attempt.

### Reconciliation

Formula update `.succeeded` only when all of these hold: exit 0; not truncated
into an unreadable result; fresh ownership verifies the same `full_name`; the
selected keg version string equals the previewed target; the previous keg is
not still the selected target; observation did not fail. Otherwise exit 0 is
`.uncertain` or `.failed`, never `.succeeded`.

Formula uninstall `.succeeded` only when exit 0, the selected target is
released, a fresh `info` no longer lists that keg as installed, and observation
did not fail. Residue (dangling symlink, keg directory still present) is not
success. Dependent refusal is `.failed` with the package still installed.

Cask update `.succeeded` only when exit 0, fresh `installed` string equals the
previewed target, and list-membership confirms the post-rescan selected
executable. A quit app that comes back at the new version is success. A missing
rescan is `.uncertain`.

Cask uninstall `.succeeded` only when exit 0, `info.installed` is null or the
token is not installed, the staged caskroom token directory is absent, and any
app target the preview recorded from a listed symlink is absent. Zap paths are
not required to be absent. If an app target remains, the state is `.uncertain`
or `.failed`, not success. Config and caches remaining is expected and is not
a failure.

Unrelated sentinel formula and sentinel files are part of the fixture's
reconciliation, not of the Core success struct. The Core struct records the
named package only. The fixture asserts the sentinels.

### Scratch and Homebrew's own files

One owned scratch per prepare, released on cancel, on pre-launch failure, and
after reconciliation. Homebrew's cache, logs, and temp stay on Homebrew's
defaults (`env_config.rb` `HOMEBREW_CACHE` and `HOMEBREW_LOGS` defaults were
read; values were not redirected). The effect text is the disclosure.

---

## E. Mutation gate, promotion, and matrix

### Vocabulary

Add to `AcceptedOperation`, raw values exactly:

- `homebrewFormulaUpdate`
- `homebrewFormulaUninstall`
- `homebrewCaskUpdate`
- `homebrewCaskUninstall`

No combined `homebrewUpdate`. A formula acceptance must not authorize a cask
command. Schema stays 2. Absent field → `[]` (`DetectorRegistry.swift:238-239`
and `:1080`). Null, non-array, non-string, unknown, and duplicate keep the
existing error shapes. The unknown-value reason string becomes:

```text
must be one of npmUpdate, npmUninstall, homebrewFormulaUpdate, homebrewFormulaUninstall, homebrewCaskUpdate, homebrewCaskUninstall
```

Both decode paths go through `DetectorMetadataValidation.acceptedOperations`
(`DetectorMetadata.swift:278-282`, `DetectorRegistry.swift:234` and `:1107`).
One string change covers both. Tests must still feed both a Codable payload and
a `JSONSerialization` payload.

Prepare-seam order stays: cancellation, then `acceptedOperations` containment,
then anything else. AppSupport and the app read `reason.message`. They do not
retype it (`WorkflowPresentation.swift:173-174`).

### Matrix rule (M13-F, test-enforced)

Replace the mutation rule in `CapabilityMatrixTests.mutationCellProblems`
(`:176-204`) and the prose at `docs/capability-matrix.md:18-21` with:

- Update `yes` is exactly one of:
  - `yes: npm (verified npm-global copies only)` when `npmUpdate` is accepted and an npm package is declared
  - `yes: homebrewFormula (verified formula copies only)` when `homebrewFormulaUpdate` is accepted and a formula is declared
  - `yes: homebrewCask (verified cask copies only)` when `homebrewCaskUpdate` is accepted and a cask is declared
- The same three strings with `Uninstall` / the matching uninstall case.
- A `yes` without the matching accepted operation and declaration is a test failure.
- Any other cell is `informational: <reason>` or `disabled: <reason>`.
- Latest-check (adjusted in M13-B, not F). Replace `latestCheckProblems` (`CapabilityMatrixTests.swift:207-233`). Build the expected cell from declarations, in this order, joined by `; `: `yes: npm` if an npm package is declared, `yes: homebrewFormula` if a formula is declared, `yes: homebrewCask` if a cask is declared. The cell must equal that string. A row with no npm, formula, or cask declaration stays `disabled: <reason>`. Delete the blanket rejection at `:230` in the same commit that adds the cask segment; do not leave both rules. `yes: homebrewCask` means the read-only probe is shipped. It does not mean a comparison succeeded. After M13-B the cells are: kiro-cli and agy exactly `yes: homebrewCask` (`docs/capability-matrix.md:37` and `:39` are `disabled: cask latest-check not shipped` today); codex `yes: npm; yes: homebrewCask` (today `yes: npm` at `:28`); claude `yes: npm; yes: homebrewCask` (today `yes: npm` at `:31`; claude declares npm and two casks). Formula-only and npm-plus-formula rows stay as they are. Null `auto_updates` does not keep the cell at `disabled`.
- Update and Uninstall for codex stay exactly `yes: npm (verified npm-global copies only)`. A cask declaration does not create a cask mutation `yes` unless `homebrewCaskUpdate` / `homebrewCaskUninstall` are accepted. They are not, under the recommendation below. Claude's mutation cells stay informational.

### Promotion recommendation (OD-M13-1; not applied by this plan)

Do not promote in M13-A through M13-G.

Recommend the owner authorize, after each id has its own M13-E scenario:

| id | Recommend | Why, from this session and the matrix |
|---|---|---|
| hermes, aider, goose | Formula update and uninstall | Matrix already says "formula adapter M13" (`capability-matrix.md:36-38`). `aider` and `block-goose-cli` info: `deprecated false`, `disabled false`, `pinned false`, stable `0.86.2` and `1.60.2`. `hermes-agent` info succeeded, `pinned false`, `installed` empty; stable text was not copied into this note. Identities are single core formulae. Goose's mutation name is `block-goose-cli`, never the basename (matrix line 38). |
| gemini, cline | No | `gemini-cli` deprecated 2026-06-18, disable date 2026-12-18, `disabled` still false. `cline` deprecated 2026-05-18, disable date 2027-05-18, `disabled` still false. Promoting them races a disable date. |
| opencode, omp | No | Third-party taps (`anomalyco/tap/…`, `can1357/tap/omp`). Higher identity risk. Not required for the first formula proof. |
| codex, claude, kiro-cli, agy | No cask promotion | All five tokens returned `auto_updates: null` from `brew info --json=v2 --cask`. The design refuses cask Update on null. A promotion would accept an operation prepare can never ready. agy's matrix row still says the cask source sets `auto_updates: true`, which the API did not show. kiro-cli `old_tokens` are `amazon-q` and `codewhisperer`; the declared token `kiro-cli` matches `token`, so rename is not the blocker. Codex already has npm acceptance; do not add a second channel in the same milestone. |

Cask Uninstall does not need `auto_updates`. It is still an owner decision
because removal can quit apps and run an uninstall stanza. Recommendation: no
cask uninstall promotion until the owner has seen the M13-E whole-cask
disclosure on a synthetic app cask.

Every promoted id needs its own scenario. Sharing the harness is fine. Sharing
one scenario across ids is not (D-021).

---

## F. Cask latest-check and cache

### Batch (at most five commands, once per check, zero when no cask subject)

Eligible subject: not `notInstalled`, not inconsistent, has a local version,
declares at least one `homebrewCask`, and did not take the formula batch.
Formula batch membership stays `source == "brew"` as today
(`UpdateProbeCoordinator.swift:240`). A standalone cask subject is removed from
the `.noRegistry` path and placed in the cask batch instead. A standalone
subject with no cask declaration stays `.noRegistry`.

Commands, under the existing `HomebrewBatchAdmissionGate`, after the formula
batch releases it:

1. `brew --prefix`
2. `brew --caskroom`
3. `brew info --json=v2 --cask <deduped declared tokens>` (cap 16 tokens; above the cap the excess are `.budgetExhausted`, not guessed)
4. `brew outdated --json=v2 --cask` with no `--greedy`
5. `brew list --verbose --cask <tokens whose installed field is a string>`

No `brew update`. No per-tool fan-out. No `--installed`.

### outdated semantics

`cmd/outdated.rb:67-78` puts casks in the `casks` array when `--cask` is set.
`cask.rb:529-536` builds each JSON object as `name` (the token, not
`full_token`), `installed_versions`, `current_version`, `pinned`,
`pinned_version`. This session did not capture a non-empty `casks` array.
Implement that key set. If the probe's live record uses different keys, stop
and do not guess aliases.

`cask.rb:473-508`: a disabled cask is not outdated; `version :latest` is not
outdated unless greedy; `auto_updates` without greedy is outdated only when
`upgrade_auto_updates_casks?` is on and the bundle looks outdated. Plain
absence is therefore not proof of currency. The resolver:

| Observed | Status |
|---|---|
| Membership or identity fails | `unknown(.identityUnverified)` |
| `disabled == true` | `unknown` with new reason `.caskDisabled` |
| `auto_updates == true` | `unknown(.caskAutoUpdates)` |
| `auto_updates` null or absent | `unknown(.caskAutoUpdatesUnverified)` |
| version string `latest` | `unknown(.caskTracksLatest)` |
| version not `homebrewStable` (comma, prerelease, extra components) | `unknown(.unsupportedVersion)` |
| `pinned` / list disagreement | `unknown(.identityUnverified)` |
| Comparable, installed string older than `info.version`, and the one outdated record has `name` equal to `token`, `installed_versions` containing that installed string, and `current_version` equal to `info.version` | `updateAvailable` |
| Comparable and equal, and the token is absent from outdated | `upToDate` |
| Comparable and older, and the token is absent from outdated | `unknown(.identityUnverified)`. Absence is not an update offer. |
| Outdated record present but `current_version` ≠ `info.version`, `name` ≠ `token`, or duplicate records for the token | `unknown(.identityUnverified)` |
| Installed newer than `info.version` | `unknown(.newerThanKnownMetadata)` |
| Command failure | existing `.probeFailed` / `.networkUnavailable` / `.queryTimedOut` / `.budgetExhausted` |
| Offline mode | `.networkUnavailable` without a process, same as the formula coordinator |

A pinned comparable update stays `updateAvailable` plus a pin flag the
presentation reads. It does not become `upToDate`.

New `UnknownReason` cases: `caskTracksLatest`, `caskAutoUpdates`,
`caskAutoUpdatesUnverified`, `caskDisabled`. Explanations, byte-stable for old
cases:

- `caskTracksLatest`: "cask version is :latest; no comparable latest version"
- `caskAutoUpdates`: "cask auto_updates is true; Homebrew does not treat plain outdated as currency"
- `caskAutoUpdatesUnverified`: "cask auto_updates was not a boolean; latest is unknown"
- `caskDisabled`: "cask is disabled; Homebrew will not upgrade it"

`NpmUpdateOperation.map` sends all four to `.probeFailed`. That mapper is npm-only.

### Cache

Separate document, M10-B pattern. Not a schema-4 extension of the formula file.
Formula schema 3 stays. Path: sibling of the injected update cache URL, file
name `cask-update-metadata-v1.json` (same construction as
`NpmUpdateMetadataCache.swift:296-302`).

- Schema version 1. Any other version is a miss. No migration.
- TTL 21600. Cap 1_048_576 bytes both directions.
- Store only a successful comparison (`upToDate` or `updateAvailable`). Unknown is never written.
- Key: registry id, manager entry, manager target, manager fingerprint, prefix, caskroom, token, full_token, installed version string, selected entry, selected target, and a context digest.
- Context digest uses the same length-prefixed framing as `UpdateProbeCoordinator.contextFingerprint` (`:847-855`) with domain label `agent-lens-cask-update-context-v1`. A formula digest must not decode as a cask hit.
- Do not store raw environment, the pinned-list output, zap paths, or stderr.
- Restore fails closed unless the record's prefix/caskroom/token/full_token agree and the selected target still membership-matches under the stored caskroom using the stored installed version. A hit does not skip a later operation revalidation. Operations do not read this cache.

---

## G. Disposable acceptance environment

### Why a scratch prefix

M10's npm fixture (`Tests/Fixtures/M10C/npm_update_acceptance.py`) uses an
operator-supplied `--root` that must not pre-exist, the Python standard library
only, a seatbelt profile that denies personal-home reads and denies writes
outside the root, and hash manifests for Cancel. M13 uses that shape and a real
`brew` whose prefix is inside the root.

Do not point the fixture at `/opt/homebrew`. Cellar and Caskroom are gitignored
there (`check-ignore` above). A `git clone --no-hardlinks` of `/opt/homebrew`
copies the brew repo (3536 tracked files, `.git` 792K) and does not copy Cellar.
`--no-hardlinks` so a later `git gc` in the scratch cannot touch the personal
object store. Pin the clone to `456c79a994` (`brew --version`
`7.0.15-76-g456c79a`). No `git fetch`. No network.

The fixture's `brew` is `<root>/homebrew/bin/brew`. Its `--prefix` must print
`<root>/homebrew`. The login-shell PATH injected into the app and CLI puts that
`bin` first, so `HomebrewManagerResolver` selects it (`HomebrewIdentity.swift:25-36`).

### Synthetic tap

A local tap under `<root>/tap` with no bottles and `url` fields that are
`file://` paths inside `<root>`. Formulae are one-file shell scripts so no
compiler and no bottle host are required.

| Package | Role |
|---|---|
| `agentlensfixture/m13/oldformula` | Installs 1.0.0. Tap is then rewritten to 1.2.0 for Update. Both versions are `homebrewStable`. |
| `agentlensfixture/m13/sentinel` | Installed. Never named by an operation. Hash of its keg must match after every scenario. |
| `agentlensfixture/m13/lib` and `agentlensfixture/m13/consumer` | `consumer` depends on `lib`. Uninstall of `lib` must exit nonzero and leave both installed. |
| `agentlensfixture/m13/pinned` | Installed, then `brew pin --formula` inside the fixture only. Update prepare returns `.pinned` and launches nothing. The pin symlink remains. |
| `agentlensfixture/m13/broken` | `install` exits 1. Update execute is `.failed`, previous keg remains, no retry. |
| Cask `m13binary` | `binary` artifact. CLI lands via Homebrew's symlink. Selected PATH entry must verify. |
| Cask `m13app` | `app` artifact installed with `brew install --cask --appdir <root>/Applications`. Uninstall must remove that app. `/Applications` is absent from every argv and from the seatbelt write allow. |
| Cask `m13zap` | Uninstall stanza deletes `<root>/stanza-sentinel`. Zap stanza deletes `<root>/zap-sentinel`. After uninstall, stanza sentinel is gone, zap sentinel remains, exit proves success only with the app/binary facts in section D. |
| Cask `m13latest` | `version :latest`. Ownership can succeed. Latest-check is `.caskTracksLatest`. Update prepare refuses. |
| Cask `m13auto` | `auto_updates true`. Latest-check is `.caskAutoUpdates`. Update prepare refuses. |
| Cask `m13comma` | version `1.2.3,9`. Latest-check `.unsupportedVersion`. Update refuses. Uninstall of an owned copy is allowed. |

The fixture never calls `brew update`, `brew cleanup`, `brew unpin`, `--force`,
`--zap`, or `--ignore-dependencies`. It may call `brew tap <local path>`,
`brew install`, `brew pin`, and the Agent Lens operations under test. Those
mutations are inside `<root>` only.

Seatbelt: deny writes to `/opt/homebrew` and to the real home, including if
they are not under the default home denial. Deny network. Allow reads of the
system frameworks and of the scratch brew. Same pattern as
`strict_profile` in `Tests/Fixtures/M10C/npm_update_acceptance.py:50-78`.

### Scenarios the orchestrator must observe

1. Preview then Cancel: scratch-prefix hash manifest identical; `processStarted` false; pin and sentinel unchanged.
2. Formula Update: 1.0.0 → 1.2.0, ownership re-verifies, sentinel hash unchanged, no second formula upgraded.
3. Formula Uninstall of the updated formula: success facts in section D.
4. Uninstall of `lib` while `consumer` is installed: nonzero, both remain, state `.failed`.
5. Pinned formula: no process.
6. `broken`: nonzero, old keg remains, no second launch.
7. Stale target: rewrite the tap version after prepare and before execute; launch does not happen; state `.failed`; `processStarted` false.
8. Cask binary Update and Uninstall.
9. Cask app Uninstall: scratch app directory absent; zap sentinel present; effect text visible in the preview transcript.
10. `:latest`, `auto_updates`, comma version: typed refusals, no process.
11. Interruption: kill the child during upgrade; outcome `.interrupted` or `.uncertain`; no automatic second launch. Same expectation as the M10-D interruption note in `walkthroughs/M10-D-implementation.md`.
12. Concurrent confirm: second caller gets the gate failure, `processStarted` false, first operation is the only mutation (`OperationModels.swift:261-273`).
13. CLI `verify-installation <fixture id>` prints `manager: Homebrew cask` or `Homebrew formula` and the scratch prefix. CLI `scan --check-updates` prints the typed unknown reasons for the three unsupported casks. `agent-lens` with any mutation subcommand is still a usage error (`main.swift:171-174`).

### Judge probe (BLOCKING before M13-A dispatch)

The orchestrator runs this during planning, in a scratch directory, then
destroys it. It must demonstrate all of the following or M13-A does not start:

1. `git clone --no-hardlinks` of `/opt/homebrew` at `456c79a994` into the scratch, then `<scratch>/homebrew/bin/brew --prefix` prints the scratch prefix. Record any "prefix not supported" warning verbatim.
2. With network denied and `HOMEBREW_NO_AUTO_UPDATE=1` `HOMEBREW_NO_ANALYTICS=1` `HOMEBREW_NO_INSTALL_FROM_API=1`, install `oldformula` and `sentinel` from the local tap. `brew info --json=v2 --formula oldformula` returns `versions.stable` `1.0.0` and an `installed` array whose `version` is `1.0.0`, offline.
3. Install `m13binary`. `brew list --verbose --cask m13binary` prints a file whose canonical path equals the selected CLI. Record one sample line shape, not a personal path.
4. Install `m13app` with `--appdir` inside the scratch. `brew list --verbose --cask m13app` prints a Caskroom symlink whose resolved target is the scratch `.app`, and the selected Mach-O inside that app is a strict descendant of that target. If no such symlink exists, stop. App-target ownership is then unsupported and M13-A ships binary/command_wrapper only, with app casks returning `.caskArtifactUnlinked`. Do not invent a receipt parser to fill the gap. Then read the installed `config.json` only as a probe observation (not as the product's ownership proof) and record whether `explicit.appdir` is the scratch app directory. Upgrade that cask with the section D environment, including `HOMEBREW_CASK_OPTS` unset, and with a hostile `HOMEBREW_CASK_OPTS=--appdir=/Applications` present in the parent environment to prove the operation's unset wins. The upgraded app must remain inside the scratch app directory, and nothing new may appear under `/Applications`. If `explicit.appdir` is absent or the upgrade leaves the scratch appdir, app-cask Update is unsupported: M13-D still ships binary cask Update, and app casks return `.caskArtifactUnlinked` for Update prepare. Uninstall of an ownership-verified app cask can remain if step 4's symlink proof passed.
5. `brew info --json=v2 --cask m13app` shows `installed` as a string equal to the version directory name. This closes the unverified non-null shape.
6. Rewrite `oldformula` to 1.2.0. `brew outdated --json=v2 --formula` includes a record with the keys `name`, `installed_versions`, `current_version`, `pinned`, `pinned_version`. `brew outdated --json=v2 --cask` after a cask version bump includes `name`, `installed_versions`, `current_version`, `pinned`, `pinned_version` as in `cask.rb:529-536`. If the live keys differ, the resolver stops.
7. `brew upgrade --formula oldformula` with the section D environment does not change `sentinel`, and does not run cleanup (a pre-created old keg of an unrelated formula remains). Then restore that tree from the fixture's own reinstall, not by hand in the personal prefix.
8. Uninstall of `lib` while `consumer` is installed exits nonzero and both remain, without `--ignore-dependencies`.
9. `brew pin --formula pinned` then `brew upgrade --formula pinned` does not change the keg and does not unpin. Agent Lens itself will refuse earlier; this step only proves brew's behavior matches the disclosure.
10. Personal `brew --prefix` is still `/opt/homebrew` at the end, and `brew list --pinned` on the personal prefix is still empty.

If step 1 cannot install into a nonstandard prefix, the milestone stops. There
is no fallback that uses the personal prefix.

### Native journey

After M13-G, the orchestrator drives the debug app built from the fixture host,
the same way as `walkthroughs/M10-D-implementation.md` lines 141-154: Accessibility
click-through, not a screenshot-only check.

1. Verify the fixture formula → Update… appears only because the fixture registry accepts `homebrewFormulaUpdate` (the shipping registry does not, until M13-H).
2. Preview shows formula vs cask, the scratch prefix, the full name, the literal argv including `--yes`, and the effect text.
3. Cancel. Hash manifest unchanged.
4. Confirm Update. Result sheet shows the delta. Sentinel unchanged.
5. Uninstall the app cask. The preview's visible text includes "companion app" and "zap". Confirm has no keyboard shortcut. Escape is Cancel. After confirm, the scratch app is gone and the zap sentinel remains.
6. Screenshots are supplemental. The Accessibility transcript and the hash manifests are the evidence.

---

## H. AppSupport, app, and CLI

### Affordances

`ManagementPresentation` (`WorkflowPresentation.swift:186-237`) today offers
Update only for `updateAvailable` plus an npm package plus `npmUpdate`, and
Uninstall only for accepted npm plus verified npm ownership. Formula and cask
limits are always appended as text when declared.

M13-G adds:

- Update button only when status is `updateAvailable`, the verified manager is `homebrewFormula` or `homebrewCask`, and the matching update operation is accepted. Otherwise the existing `newerVersionWithoutManagedUpdate` string, or `hidden` when there is no newer comparable version.
- Uninstall button only when the matching uninstall operation is accepted and ownership for that same manager is verified. Otherwise `needsVerification` with a new Core-owned string, parallel to `verifyToEnableUninstall` (`WorkflowPresentation.swift:177-178`): "Verify Installation to enable Uninstall for this Homebrew formula." and the cask twin. Do not reuse the npm sentence for a cask.
- The static limit sentences (`:179-182`) remain when the operation is not accepted. They are removed for a manager only when that manager's operation is accepted and the button or the verification hint is shown. A row must not say both "not available in this version" and show the button.
- `standaloneLimit` remains for source `standalone` when cask ownership is not verified. When cask ownership is verified, do not also call the copy standalone-deletable. The source heuristic string may still be `standalone` in diagnostics; the management limit must not tell the user Agent Lens refuses a verified cask for that reason.
- Codex npm branch stays byte-identical, including `prepareNpmUpdate` / `prepareNpmUninstall`.

Pin, disabled, auto-updates, and unsupported version are Core unavailable
reasons shown when the user invokes the button, and the button is not offered
when prepare would refuse for those reasons and the latest-check already
recorded them. If latest-check says `updateAvailable` and prepare then finds a
new pin, the sheet shows `.pinned` and does not launch. That is the M10 stale
path, not a new one.

### Sheets

Do not overload `NpmUpdatePreview`. Add brew preview structs. Keep
`UpdateOperationView.init` and `UninstallOperationView.init` source-compatible
(`UpdateOperationView.swift:17`, `UninstallOperationView.swift:18`).

New views copy the C-1 footer (`UpdateOperationView.swift:73-83`,
`UninstallOperationView.swift:73-88`):

- Cancel uses `.keyboardShortcut(.cancelAction)` and hint "Closes this confirmation without a change."
- Confirm Update has no shortcut. Hint: "Applies the reviewed Homebrew formula update after this confirmation." Cask hint names the cask.
- Uninstall uses `role: .destructive`, no shortcut. Cask hint: "Removes the reviewed Homebrew cask after this confirmation. This may remove a companion app, not only the selected CLI."
- The cask uninstall preview shows `companionDisclosure` as its own text block, not only inside a scrolling argv dump.
- Accessibility labels on the prefix, kind, package identity, and argv rows.

### Invalidation

`invalidatePendingUpdate` (`InventoryViewModel.swift:649-655`) already returns
immediately while `isExecutingUpdate` or `isExecutingUninstall`. Keep that.
Store brew preparations in the same update and uninstall slots via an enum
(`.npm` / `.formula` / `.cask`) so a selection change still releases whichever
preview is pending, and so two preparations cannot be live. `cancel` on the
enum calls the matching Core `cancel`. Executing brew uses the same busy slot
and the same shared gate as npm. A brew confirm while an npm mutation is
executing acquires nothing.

Window close during execute follows the existing cancel path
(`InventoryViewModel.swift:793-800`): an executing operation is cancelled and
joined, not abandoned, and reconciliation still runs inside Core.

### CLI

No new subcommand. No flags. D-022.

- `verify-installation` prints the cask result because it already calls `InstallationOwnershipVerifier` (`main.swift:141-151`).
- `scan --check-updates` and `--refresh-updates` print cask reasons because they already call `UpdateProbeCoordinator` (`main.swift:94-103`). M13-B changes the coordinator, not `main.swift`.
- `scan` with no mode and `--offline` must not launch brew. Existing mode switch (`UpdateProbeCoordinator.swift:227-231`).
- Unknown command still `usageError()` (`main.swift:171-174`).

### Updates and Diagnostics

An unknown cask status renders as the em dash / neutral reason, never as up to
date (`VersionStatus` rules, D-007). The update count counts only
`updateAvailable`. Diagnostics keep the source heuristic. Ownership, not the
heuristic, is what enables a button.

---

## I. Risks and owner decisions

### Ranked risks

1. **Cask ownership false proof.** A basename or artifact-target string would verify a standalone app that happens to share a name. Mitigation: membership is only a `list --verbose` path, resolved by components, with `.metadata` excluded. BLOCKING probe step 4. If it fails, app casks stay `.caskArtifactUnlinked` and are not promotable.
2. **Brew side effects.** Upgrade ask-mode, dependent upgrades, cleanup, periodic full cleanup, uninstall autoremove, cask-dependency installs, and cask quit/reopen are on unless the section D argv and environment suppress them (`uninstall.rb:168-170`, `cmd/upgrade.rb:135-140`, `cask/upgrade.rb:411` and `:504`). Mitigation: those exact argv and environment keys, asserted in tests, plus sentinel hashes and the appdir probe.
3. **Scratch prefix.** Homebrew may refuse a prefix other than `/opt/homebrew` or `/usr/local`, or may insist on bottles and the network. Mitigation: BLOCKING probe. No personal-prefix fallback.
4. **auto_updates null.** Every catalogue cask queried returned null, contradicting the agy matrix note. Promoting Update now would accept an operation that cannot become ready. Mitigation: refuse null; OD-M13-1 recommends zero cask promotions.
5. **Promotion scope.** The matrix sentence "formula adapter M13" is not owner authorization (D-021). Mitigation: M13-H is a separate phase.
6. **npm regression.** Shared gate, shared scratch type, shared `UnknownReason` switches, shared view-model slots. Mitigation: npm files' control flow and effect texts are protected; new enum arms are append-only; Codex predicates have a byte-level test.
7. **CI floors.** New tests raise counts. Hosted floors are minima (`.github/workflows/ci.yml` multiset `>=`). They stay until M13-I so a partial phase cannot lower them. Risk is the opposite: forgetting the upward bump and leaving the new tests unguarded. M13-I is mandatory.
8. **Flash-tier ambiguity.** Argv, environment, effect text, reason cases, and dispatch are fixed in this plan. The implementer does not choose `--greedy`, cache schema, or which ids to promote. Anything the probe contradicts is a stop, not a silent adaptation.
9. **Large cask downloads vs 120s.** Acceptance uses local file URLs so the bound holds. A real multi-gigabyte cask can time out; the outcome is interrupted plus reconciliation, not a retry. OD-M13-3 if the owner wants a longer bound later. This plan does not raise it.
10. **New formula dependencies.** `HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK` does not stop brew from installing dependencies the new formula itself requires. The effect text says so. The sentinel is not a dependency of the upgraded formula. Acceptance does not claim otherwise.

### OD-M13-1 — Which catalogue entries gain accepted operations?

Recommendation: after M13-E is green, promote `hermes`, `aider`, and `goose`
for `homebrewFormulaUpdate` and `homebrewFormulaUninstall` only. Promote
nothing else. Do not promote gemini, cline, opencode, omp, or any cask.
Rationale in section E. Empty is an acceptable owner answer; M13-H is then vacuous.

### OD-M13-2 — Do pinned updates count in the Updates badge?

Recommendation: yes. The version comparison is real. The button stays off and
the pin reason is visible. Excluding them would hide a newer version (D-007).

### OD-M13-3 — Keep the 120s mutation bound for casks?

Recommendation: yes, for parity with npm (`NpmUpdateOperation.swift:48`).
Revisit only if a later owner wants large-cask support. Not this milestone.

### OD-M13-4 — Diagnostic beta, publication, expenses

Out of M13. `ROADMAP.md` §7. No recommendation to start them here.

### Could not resolve, and why

- Live non-null `installed` string and live cask `outdated` record: not observed without querying or mutating an installed cask. Source and the brief describe them. Probe steps 5 and 6 close them.
- App-symlink membership on a real install: taken from `moved.rb:176-178` and `list.rb:200-204`. Probe step 4 is the proof. Until it passes, the plan's fallback is explicit (`.caskArtifactUnlinked`), not a receipt parser.
- That a scratch-prefix upgrade actually keeps `explicit.appdir`: taken from `cask/upgrade.rb:411` and `cask/config.rb:231-232`. Probe step 4 is the demonstration. Until it passes, app-cask Update stays unsupported as that step says.
- `brew list --pinned` line text on a non-empty list: personal stdout was empty. The match rule uses `list.rb:283-295` and fails closed on a duplicated short name.
- Whether `full_token` for a third-party tap cask equals `user/repo/token`: not observed. Core casks used `full_token == token`. Fail closed. No tap cask is promoted.
- `rename` element schema: not observed (empty lists). Non-empty refuses.
- Disabled-formula upgrade behavior when `disabled` is already true: not executed (would be a mutation, and no such installed formula was queried). Prepare refuses before launch. The probe does not need to upgrade a disabled formula.
- The 8 local gates: believed green because the dispatch says so. Not re-run here.

---

## J. Non-goals (binding)

No uv/pip (M14), Cargo (M15), cached launch, menu bar, or opt-in refresh (M16),
bundled CLI (M17), release, signing, notarization, or publication (M18–M19).
No CLI mutation syntax (D-022). No `brew update`. No `brew upgrade` or
`brew uninstall` without a named package. No `--formula` or `--cask` upgrade
that omits the name. No `--force`, `--zap`, `--ignore-dependencies`, `--greedy`,
`--greedy-latest`, `--greedy-auto-updates`, unpin, pin, relink, cleanup,
autoremove, or config/cache deletion by Agent Lens. No personal installation
as an acceptance target. No new package dependencies. No public contribution
invitation. No weakening of npm/codex behavior, the M12 invalidation contract,
or C-1. No Cellar-shaped cask proof. No use of `auto_updates: null` as either
true or false.
