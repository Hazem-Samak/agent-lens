# M13 Planning Council — shared task brief

Date: 2026-11-21. Orchestrator/main judge: Hermes (Herdr terminal `t12k`).
Council members plan **independently**; the orchestrator judges, reconciles, and freezes the final plan.

## 1. Context

Agent Lens is a native Swift 6 / SwiftUI macOS app (zero external dependencies) that diagnoses
AI CLI installations (which copy PATH runs, duplicates, versions, ownership) and delegates
Update/Uninstall to package managers. **M0–M12 are delivered to `main`** (M10 PR #1 `65f7a82`,
M11 PR #2 `8d07ba4`, M12 PR #3 `934a26c`; hosted CI green on each merge). The M8 keyboard gate
is closed. Only `codex` has accepted npm Update/Uninstall (D-021). No public release exists.

The next milestone is **M13 — complete Homebrew management** (ROADMAP §4). Its user result:
*verified formula and supported cask installations can be checked, updated, and uninstalled
through the finished native workflow.*

ROADMAP §4 M13 requirements (binding):

- Reuse formula identity/metadata and add cask ownership and appropriate metadata; do not apply
  Cellar-shaped assumptions to casks.
- Show formula versus cask, exact manager prefix, and full package identity. Disclose that cask
  removal may remove a companion app, not only a CLI.
- Respect pins and manager restrictions. Never force, unpin, relink, perform broad cleanup, or
  run hidden `brew update`.

M13 acceptance (ROADMAP): disposable formula and cask scenarios cover preview/Cancel, Update,
Uninstall, stale identity, pins/unsupported versions, manager failure, and accurate
post-operation inventory. Include a real Homebrew path in a disposable environment and visible
whole-cask disclosure.

**Branch and base:** `milestone/m13-homebrew`, created from `main` tip
`9b37a334eefd06802daa7bd006c6e995f8698af2` (`9b37a33`). M11/M12 are merged; nothing stacks.
Do not switch branches, do not rebase.

**Authorization already given (owner message 2026-11-21):** the owner authorized M13 PLANNING
with this council (MiniMax M3.1-Flash/xhigh via mcode; Grok 4.7/high via grok CLI), Herdr/hc
orchestration with visible panels, and — after agreement — freeze and commit of the plan on the
milestone branch. **Implementation is NOT authorized. No implementer is selected.** Push,
publication, per-tool mutation promotions, and any release remain separate owner decisions.
Technical decisions are delegated to the orchestrator/judge under the lean protocol (ROADMAP §5);
genuine product choices go back to the owner as numbered OD-M13 items with recommendations.
Your proposal must therefore be dispatch-ready: bounded phases, exact allow-lists, measurable
gates, and design decisions resolved or explicitly flagged as owner decisions.

## 2. Required reading (in this order)

1. `ROADMAP.md` — §2 finish line, §4 M13 (and M10/M12/M14 for boundaries), §5 operating protocol,
   §6 architecture/safety invariants, §7 owner gates, §8 next action.
2. `DECISIONS.md` — D-001…D-023, especially D-004 (delegate, never become a manager), D-006/007
   (tri-state), D-008 (uninstall policy; config/caches never touched), D-012/013/014 (tests, one
   branch, orchestrator acceptance), D-019 (formula-only opt-in update checks; cask latest-check
   not shipped), D-021 (fail-closed per-entry mutation gate; closed vocabulary), D-022 (shipping
   CLI read-only), D-023 (MIT). Do not re-litigate settled decisions.
3. `AGENT_LENS_SCOPE.md` — §5 Update, §6 Uninstall, §21 version/update model, §22 uninstall
   policy, §27 implementation notes, §29 operating protocol (read selectively; the file is large).
4. `briefs/README.md` — brief rules (one branch per milestone, read-only reviewers, orchestrator
   runs acceptance, DO NOT TOUCH is binding, implementer gets the brief not the scope document).
5. Core Homebrew seams (read all): `Sources/AgentLensCore/Updates/HomebrewIdentity.swift`,
   `Updates/HomebrewUpdateProbe.swift`, `Ownership/HomebrewOwnershipProbe.swift`,
   `Ownership/InstallationOwnership.swift`, `Ownership/InstallationOwnershipVerifier.swift`,
   `Updates/UpdateMetadataCache.swift`, `Updates/UpdateProbeCoordinator.swift`,
   `Updates/VersionComparison.swift` (Homebrew stable grammar), `Updates/VersionStatus.swift`.
6. Core operation seams (read all): `Operations/OperationModels.swift`,
   `Operations/NpmUpdateOperation.swift`, `Operations/NpmUninstallOperation.swift`,
   `Operations/OperationProcessRunner.swift`, `Detection/DetectorMetadata.swift`
   (`AcceptedOperation`, `PackageManager`, declared-package validation),
   `Detection/DetectorRegistry.swift` (both decode paths), `Detectors/DefaultDetectors.json`.
7. Presentation/app surface: `Sources/AgentLensAppSupport/InventoryViewModel.swift` (prepare/
   confirm/verify/invalidate seams), `WorkflowPresentation.swift` (`ManagementPresentation`),
   `InventoryService.swift`, `InventorySnapshot.swift`; `Sources/AgentLensApp/ToolDetailView.swift`,
   `UpdateOperationView.swift`, `UninstallOperationView.swift`, `OwnershipVerificationView.swift`,
   `MainWindow.swift`. Shipping CLI: `Sources/agent-lens/main.swift` (read-only, D-022).
8. Gates and evidence precedent: `.github/workflows/ci.yml` (seven hosted gates; floors Core 467 /
   AppSupport 119 / total 586, guard 21, packaging 9; anchors); `docs/capability-matrix.md` +
   `Tests/AgentLensCoreTests/CapabilityMatrixTests.swift` (test-enforced matrix rules);
   `Tests/Fixtures/M10C/npm_update_acceptance.py` and `Tests/Fixtures/M10D/npm_uninstall_acceptance.py`
   (disposable controlled-manager acceptance precedent); `walkthroughs/M10-D-implementation.md`
   (native click-through method); `briefs/M10-C-npm-update.md` (operation-brief format calibration);
   `briefs/M12-plan.md` + `briefs/M12-planning/judgment.md` (frozen-plan and ruling format).

## 3. Verified starting point (judge-audited 2026-11-21; re-verify anything you rely on)

Code (file:line at base `9b37a33`):

- `HomebrewOwnershipProbe.swift` — formula-only ownership (M9-B). Exactly three queries:
  `brew --cellar` (:69), `brew info --json=v2 --formula <declared-name>` (:131),
  `brew list --verbose --formula <full-name>` (:177). `--installed` is never used (:5-6).
  Cask declarations return `.unsupportedCask` (:101-105). `FormulaProof.revalidate()` (:35-52)
  re-observes selection/manager/cellar/keg identities. Ownership never depends on semver support
  or update availability (:7).
- `HomebrewIdentity.swift` — `HomebrewManagerResolver.resolve` (:25-38) takes the first live
  `brew` in the ordered login-shell PATH (never inherited PATH/`which`/hardcoded prefix).
  `HomebrewTargetParser.parse` (:79-102) decomposes `<cellar>/<formula>/<keg-version>/<rel>`
  by PATH COMPONENTS, not substrings.
- `HomebrewUpdateProbe.swift` — M6 batch: at most three commands (`--cellar`,
  `info --json=v2 --formula <names>`, `outdated --json=v2 --formula`) (:1-8, :488-531);
  `queryTimeout = 10` (:204); `diagnosticEnvironment` adds `HOMEBREW_NO_AUTO_UPDATE=1` and
  `HOMEBREW_NO_ANALYTICS=1` (:543-548). `parseOutdated` tolerates cask data but NEVER consumes
  it (:259-261). `HomebrewStatusResolver.status` (:554-692): homebrewStable ordering with
  revision suffix, alias/identity poisoning, outdated cross-check; unknown reasons are typed.
- `UpdateMetadataCache` — formula-only, schema 3, six-hour TTL, 1 MiB cap, full identity keys,
  context digest (README "Update status limitations"). npm metadata lives in a SEPARATE document
  so ecosystems can never cross-read (M10-B pattern).
- `DetectorMetadata.swift:78-81` — `AcceptedOperation` closed vocabulary is exactly
  `npmUpdate`, `npmUninstall`. Validation (:270-295) rejects anything else with
  "must be one of npmUpdate, npmUninstall" on both decode paths (D-021, additive schema-2 field).
  `PackageManager` (:61-73) already has `homebrewFormula` and `homebrewCask` declaration cases.
  Declared formula/cask names accept bare or `user/repo/name` tap form (:144-157).
- `OperationModels.swift` — npm-shaped public vocabulary: `NpmUpdatePreview` (:26),
  `NpmUninstallPreview` (:290), effect texts (:20, :284), opaque preparations with
  claim/release-once (:104, :349), `InstallationDelta` (:143) / `NpmUninstallDelta` (:387)
  reconciliation (exit zero alone is never success), `OperationExecutionGate.shared` (:261-278)
  process-wide ONE-mutation gate, injectable `OperationCommandRunner` (:250).
- `NpmUpdateOperation.swift` / `NpmUninstallOperation.swift` — the D-021 acceptance guard is the
  second statement (after cancellation), before any scratch claim/observation/process (M12
  judgment; re-verify). Prepare re-verifies ownership + fresh metadata; execute revalidates the
  exact plan; one owned operation scratch per invocation; bounded dual-stream output.
- Registry: 14 entries; only `codex` carries `acceptedOperations` (capability matrix).
  Formula-declared entries: opencode (taps), gemini (`gemini-cli`, DEPRECATED/DISABLED), cline
  (`cline`, DEPRECATED/DISABLED), hermes (`hermes-agent`), aider (`aider`), goose
  (`block-goose-cli`), omp (`can1357/tap/omp`). Cask-declared entries: codex (`codex`), claude
  (`claude-code`, `claude-code@latest`), kiro-cli (`kiro-cli`), agy (`antigravity-cli`,
  matrix says `auto_updates: true`). The matrix marks hermes/aider/goose "formula adapter M13".
- Source classification is a heuristic: `/Cellar/` in the resolved path → `brew`; cask binaries
  (Caskroom or app-bundle targets) classify `standalone` today (capability matrix cross-row note).
  Cask ownership therefore needs a new verification route, not a Cellar-shaped assumption.
- `docs/capability-matrix.md:18-21` — the test-enforced rule: Update/Uninstall `yes` requires
  acceptedOperations + an npm declaration + verified npm-global ownership. M13 must extend this
  rule (and `CapabilityMatrixTests`) for Homebrew — a named contract change.
- Shipping CLI dispatches only `scan`, `verify-installation`, `debug-env` (D-022). No CLI
  mutation syntax may be added. `verify-installation` already verifies Homebrew-formula ownership
  read-only; cask verification is a natural read-only extension.
- App: `ManagementPresentation` (M12-A) is the single source of "control offered, and why not";
  formula/cask limits are truthful TEXT today (M12-D). Sheets bind to preview/preparation/outcome/
  unavailable, never `selectedEntry`; the M12 R1 invalidation contract and C-1 footer contract
  (no Return-to-confirm; Cancel on Escape; destructive confirm has no key equivalent) are accepted
  behavior and must not be weakened. Public sheet initializers are source-compatible with the
  M10-D Python fixture host.
- Baseline: M12 delivered 467 Core + 119 AppSupport = 586 tests, guard 21, packaging 9, all seven
  hosted gates green at `934a26c`. The judge's fresh baseline rerun at `9b37a33` is in progress
  (Herdr `t12m`); its measured result is recorded in the judgment before freeze. Unlike M12,
  M13 EXPECTS Core growth (new adapters/operations/tests); floors move only upward at combined
  acceptance, only to orchestrator-measured counts.

Local Homebrew facts (judge-verified read-only on this workstation, 2026-11-21;
Homebrew 7.0.15-76-g456c79a, prefix `/opt/homebrew`, Caskroom `/opt/homebrew/Caskroom`;
no pinned formulae; installed casks `homebrew-app`, `vorssaint` are PERSONAL — never targets):

- `brew upgrade --help` (verbatim, load-bearing): "Upgrade outdated, unpinned packages… If cask
  or formula are specified, upgrade only the given cask or formula (unless they are pinned…)".
  "Unless $HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK is set, brew upgrade or brew reinstall will be
  run for outdated dependents and dependents with broken linkage, respectively."
  "Unless $HOMEBREW_NO_INSTALL_CLEANUP is set, brew cleanup will then be run for the upgraded
  formulae and casks or, every 30 days, for all packages."
  → A bounded single-package operation must decide and disclose the dependents-check and
  post-upgrade cleanup policy (ROADMAP forbids broad cleanup; one mutation at a time).
- `brew uninstall --help`: `--force` deletes all versions/ignores errors; `--zap` removes ALL
  associated files (may be shared); `--ignore-dependencies` bypasses the dependent check;
  `--formula`/`--cask` disambiguate. Default uninstall FAILS when the formula is a dependency of
  installed formulae. None of `--force`, `--zap`, `--ignore-dependencies` is permitted (D-008,
  ROADMAP §6); the honest failure is a result, not something to bypass.
- `brew outdated --help`: `--greedy` includes `version :latest` and `auto_updates true` casks
  that are otherwise SKIPPED; `--greedy-latest` / `--greedy-auto-updates` are the partial forms.
  → Plain `outdated --json=v2 --cask` absence is NOT proof of currency for those casks.
- `brew info --json=v2 --cask <token>` (observed keys): `token`, `full_token`, `name` (array),
  `version` (string; may be `latest` or comma-separated multi-part, e.g.
  `1.5.13,5999302598852608`), `installed` (string or null), `auto_updates` (bool or null),
  `pinned`, `pinned_version`, `deprecated`/`disabled` (+dates/reasons/replacements), `artifacts`
  (e.g. `{"uninstall":[{"quit":…}]}`, `{"app":["X.app"],"target":"/Applications/X.app"}`,
  `{"zap":[{"trash":[…]}]}`), `tap`, `old_tokens`, `rename`, `outdated`, `installed_time`.
  Observed caveat: for the NOT-installed cask `antigravity-cli` the API returned
  `auto_updates: null` while the frozen M11 matrix records `auto_updates: true` from the cask
  source — treat `auto_updates` provenance (API vs installed receipt vs cask source) as a
  research item, never guess.
- `brew info --json=v2 --formula <name>` (observed keys include): `pinned` (bool), `linked_keg`,
  `installed` (array of objects with `version`, `used_options`, `built_as_bottle`,
  `poured_from_bottle`, `runtime_dependencies`), `keg_only`, `deprecated`/`disabled`,
  `version_scheme`, `aliases`, `oldnames`, `versions.stable`, `revision`.
- `brew list --verbose --cask <token>` lists the installed artifact paths, e.g.
  `Caskroom/<token>/.metadata/INSTALL_RECEIPT.json`, `.metadata/config.json`,
  `.metadata/<version>/<timestamp>/Casks/<token>.json`, and the staged/target artifact
  (`Caskroom/vorssaint/3.4.3/Vorssaint.app`). A `binary`-artifact cask's listed paths are the
  ownership evidence analogue of the formula `list --verbose` membership check.

## 4. Your task

Write an independent M13 delivery plan proposal to **your assigned output file** (given in the
dispatch message). Cover, with concrete specifics rather than generalities:

### A. Current-state audit
Verify §3 against the code. List what M13 must ADD vs CHANGE vs PRESERVE, with file:line
citations. Mark anything you could not verify. Identify what is already accepted (formula
ownership, formula latest-check, npm operation lifecycle, native workflow, invalidation contract)
so phases do not redo or weaken it.

### B. Phase decomposition
Split M13 into bounded, sequential phases on the ONE milestone branch (suggested naming
`M13-A`, `M13-B`, …; you choose the split). For each phase give: observable goal and non-goals;
exact allow-list (production + tests) and protected files; contracts that must not change;
acceptance outline with exact commands and expected observable results; dependencies and stop
conditions; review recommendation (mandatory independent review by BOTH council models for
ownership/mutation/safety phases; orchestrator acceptance for routine read-only phases).
Phases must be small enough for one implementer dispatch each and unambiguous enough for a
flash-tier implementer: resolve design decisions in the plan, do not leave them to the
implementer. Suggested ordering logic (yours to justify or replace): cask identity/ownership
(read-only) → cask metadata/latest-check (read-only) → operation vocabulary + formula operations
→ cask operations → promotion/matrix → app/CLI integration → combined gate.

### C. Cask identity and ownership
Design the cask ownership proof without Cellar-shaped assumptions: Caskroom layout
(`<caskroom>/<token>/<version>/…`, `.metadata` receipts), `binary` vs `app` artifacts, staged
artifact vs final target (e.g. `/Applications/…`), symlinked CLI binaries. Which exact read-only
queries prove that the SELECTED executable belongs to the declared cask (analogue of the formula
three-query proof)? How are `version :latest`, `auto_updates`, deprecated/disabled casks, renamed
tokens (`old_tokens`/`rename`), tap casks (`full_token`), and multi-part comma versions handled?
What is the typed unknown reason for each refusal? How does cask verification reach
`verify-installation` and the app when the source heuristic classifies cask copies `standalone`
today? Never let a declaration, basename, or Caskroom substring alone prove ownership.

### D. Formula and cask Update/Uninstall operations
Design the Core operation adapters reusing the M10 lifecycle (prepare → preview → Cancel releases
scratch → Confirm revalidates → execute exact literal argv → bounded dual-stream output →
rescan + reconciliation; exit zero alone is never success; one mutation at a time via the shared
gate; interruption/window-close reconciliation; no automatic retry). Specify:
- exact argv for formula Update (`brew upgrade --formula <full-name>`?), formula Uninstall,
  cask Update (`brew upgrade --cask <token>`?), cask Uninstall — and the target-version semantics
  (brew upgrades to the latest KNOWN metadata; the preview must disclose the exact observed
  target and invalidate when it changes);
- pin handling (formula AND cask `pinned` fields; `brew list --pinned`): refuse with a typed
  reason, never unpin;
- the dependents-check and post-upgrade cleanup policy (see §3 brew help): which
  `HOMEBREW_NO_*` toggles the operation environment sets, and the exact disclosure text;
- dependent-formula uninstall refusal as an honest failure result;
- whole-cask disclosure: uninstall runs the cask's `uninstall` stanza (quit/delete/pkgutil/
  launchctl…) and may remove a companion APP, not only a CLI; `zap` is never run; config/caches
  are never targeted by Agent Lens;
- effect texts, preview fields (manager prefix, formula-vs-cask, full package identity, literal
  argv), reconciliation facts (keg absent/replaced, Caskroom artifact absent, target released,
  residue, observation failure), owned operation scratch and Homebrew's own cache/log writes
  (which `HOMEBREW_CACHE`/`HOMEBREW_LOGS`/`HOMEBREW_TEMP` policy, disclosed);
- timeouts and budgets consistent with the M10 operation bounds; stale-identity invalidation.

### E. Mutation gate, promotion, and capability matrix
Design the D-021 vocabulary extension: new `AcceptedOperation` cases (propose exact names),
additive schema-2 semantics (absent → `[]`; null/non-array/unknown/duplicate rejected with named
errors on BOTH decode paths), Core prepare-seam refusal ordering unchanged, AppSupport/App mirror
with single-source Core reason text. Propose the promotion set (which catalogue entries get
which accepted operations) as an OWNER decision (OD) with a recommendation and rationale —
consider: hermes/aider/goose (homebrew-core formulae, matrix anticipates M13), gemini/cline
(deprecated/disabled formulae), opencode/omp (third-party taps), codex/claude/kiro-cli casks,
agy (`auto_updates`). Every promotion needs its own controlled acceptance scenario. Design the
capability-matrix rule extension and `CapabilityMatrixTests` changes (the matrix is test-enforced;
CLI/app facts must agree).

### F. Cask latest-check and cache
Design the read-only cask latest-check: plain vs greedy `outdated --cask` semantics, `info`
`version`/`installed`/`auto_updates`/`pinned` fields, tri-state reasons for `:latest`,
`auto_updates`, unsupported/comma versions, deprecated/disabled, offline, manager failure.
Batch shape and query budget (M6 pattern: bounded queries per batch, never fan-out). Cache:
separate document (M10-B ecosystem-isolation pattern) vs schema extension — propose one, with
keys, TTL, cap, and validation rules. Unknown never becomes up-to-date and never inflates counts.
No `brew update` ever; latest means latest known to Homebrew metadata at observation time (D-019).

### G. Disposable acceptance environment
Design the disposable real-Homebrew acceptance setup (ROADMAP: "a real Homebrew path in a
disposable environment"). Candidate route (yours to justify, refine, or replace): a scratch
Homebrew prefix from a local `git clone /opt/homebrew` (real brew code, pinned revision, no
network), a local synthetic tap with test formulae (old→new versions, pinned variant, dependent
variant, failure variant) and test casks (`binary` artifact CLI; `app` artifact with a
scratch-safe target; `auto_updates` variant; `:latest` variant; uninstall-stanza effects confined
to scratch). NEVER the personal prefix, personal Cellar/Caskroom, or personal installations;
never `/Applications` targets; sentinels prove unrelated packages untouched. Specify the fixture
script shape (M10C/M10D precedent), the native real-app journey method (M10-D Accessibility
click-through precedent), CLI parity checks, Cancel-unchanged hash manifests, and the
interruption/concurrent-confirm cases. Name feasibility risks (unsupported-prefix warnings,
bottle vs source builds, API vs tap metadata in a scratch prefix) and how the plan proves or
stops on them. The judge will run a bounded scratch feasibility probe during planning; your
design should say exactly what that probe must demonstrate.

### H. AppSupport/App/CLI integration
Design the presentation integration: `ManagementPresentation` extension for accepted brew
operations (Core reason strings read, never retyped); sheet reuse vs new brew previews/sheets
(the public npm vocabulary and accepted codex behavior stay byte-identical; M10-D fixture host
initializer compatibility); the M12 R1 invalidation contract and C-1 footer contract preserved
for brew sheets; formula-vs-cask and whole-cask disclosure visible in the preview; accessibility
labels/hints for new controls; Updates/Diagnostics surfaces stay truthful. CLI: read-only
extensions only (`verify-installation` cask route, cask latest-check in `scan --check-updates`);
no mutation syntax (D-022).

### I. Risks and open questions
Ranked risks (cask ownership mis-proof, brew side-effect mutations (dependents/cleanup),
scratch-prefix feasibility, promotion scope creep, npm regression, CI integrity, flash-tier
ambiguity) and a numbered list of decisions only the owner can make (OD-M13-1, …), each with a
recommendation. Include anything you could not resolve and why.

### J. Explicit non-goals (binding)
No uv/pip (M14), Cargo (M15), cached launch/menu bar/opt-in checks (M16), bundled CLI (M17),
release/signing/notarization/publication (M18–M19); no CLI mutation syntax (D-022); no
`brew update`/`upgrade` without a named target/`--all`-style broad mutation; no force, unpin,
relink, `--zap`, `--ignore-dependencies`, broad cleanup, or config/cache deletion; no personal
installation as an acceptance target; no new dependencies; no public contribution invitation;
no weakening of accepted npm/codex behavior, the M12 invalidation contract, or C-1.

## 5. Hard constraints

- **Read-only on the product.** Do not edit anything under `Sources/`, `Tests/`, `scripts/`,
  `Resources/`, `Package.swift`, `.github/`, or any existing brief/walkthrough/doc. Do not run
  git commands that mutate state (no commit/branch/checkout/stash/reset/push). No installs, no
  builds, no test runs, no launching the app. The orchestrator runs all gates.
- **Read-only Homebrew queries ARE allowed** for research: `brew --version/--prefix/--cellar/
  --caskroom`, `brew info --json=v2 [--formula|--cask] <name>`, `brew list [--verbose]
  [--formula|--cask] [<name>]`, `brew outdated --json=v2 [--formula|--cask]`, `brew list
  --pinned`, and `brew <cmd> --help`, always with `HOMEBREW_NO_AUTO_UPDATE=1
  HOMEBREW_NO_ANALYTICS=1`. NEVER run install/upgrade/uninstall/update/pin/unpin/tap/untap/
  cleanup/reinstall/migrate or any mutating brew command, against any prefix. Personal
  installations are observation-only.
- **Do not start subagents or other CLIs.** You are one council member.
- **Do not read the other member's proposal.** Independence is the point.
- The ONLY file you may write is your assigned proposal path under `briefs/M13-planning/`.
- Never fabricate code behavior, API availability, or measurement results. `unverified` is an
  acceptable and expected answer; a confident guess is not. Cite file:line for code claims and
  the exact brew command for manager claims.
- If you are blocked (missing access, ambiguous instruction, tool failure), stop and report the
  blocker instead of improvising.

## 6. Reporting

When done — or stuck — report to the orchestrator:

```sh
hc send t12k "M13 proposal complete: briefs/M13-planning/<your-file>.md — <3-line summary: phase count, key design decisions, open blockers>"
```

Write the full proposal to the file; the message is only a pointer and summary. If `hc send`
fails because the coordinator address changed, report the delivery failure in your final screen
output rather than silently retrying a dead address.

## 7. How the judge will weigh proposals

1. Truthfulness and evidence quality (verified code citations; honest unknowns; exact brew
   semantics from primary help/JSON, not memory).
2. Phase boundedness and dispatch-readiness (one writer, clear allow-lists, measurable gates,
   design decisions resolved for a flash-tier implementer).
3. Fidelity to settled decisions and safety invariants (DECISIONS.md, ROADMAP §6, M10 operation
   contracts, D-021 gate, M12 invalidation/C-1 contracts, tri-state truthfulness).
4. Acceptance-environment rigor (disposable real Homebrew, whole-cask disclosure, sentinels,
   native journey evidence; never personal installations).
5. Clear separation of owner decisions (promotion set, expenses, publication) from technical
   recommendations.