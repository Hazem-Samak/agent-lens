# M13 — complete Homebrew management: frozen master plan

Status: **FROZEN 2026-11-21 after Planning Council.** Orchestrator judgment recorded in
`briefs/M13-planning/judgment.md` (rulings R1–R16, binding). This is the milestone master plan, not
a dispatch brief. Bounded per-phase dispatch briefs are written before each dispatch and quote the
rulings verbatim. **Authorization scope: planning + freeze/commit ONLY. Implementation is NOT
authorized; no implementer is selected.** Push, promotions (OD-M13-1), publication, and any
release are separate owner decisions.

## 1. Identity and authority

- Milestone: M13 (ROADMAP §4). Base commit: `9b37a334eefd06802daa7bd006c6e995f8698af2`
  (`9b37a33`, `main` tip — M0–M12 delivered, M8 keyboard gate closed, MIT D-023).
- Milestone branch: `milestone/m13-homebrew` (created from the base). Nothing stacks; no rebase
  onto `main`. One branch, sequential phases, one product writer at a time; reviewers read-only;
  orchestrator runs acceptance and any Git delivery (D-013, D-014).
- Authority: ROADMAP.md, DECISIONS.md D-001…D-023, AGENT_LENS_SCOPE.md §5/§6/§21/§22/§27/§29,
  briefs/README.md. Council inputs: `briefs/M13-planning/proposal-minimax.md`,
  `proposal-grok.md` (revised), shared task `council-brief.md`.
- Council: MiniMax M3.1-Flash/xhigh (mcode v0.7.6) and Grok 4.7/high (grok 1.0.89), orchestrated
  through Herdr Core with visible panels. Judge: Hermes orchestrator (`t12k`). Rulings R1–R16 in
  judgment.md are binding; where a proposal conflicted with verified code or a probe fact, the
  verified fact won (notably R7, the cask support-class correction to BOTH proposals).
- Sole product writer: **not selected — implementation not authorized.** Standing independent
  reviewers (owner-selected): MiniMax M3.1-Flash/xhigh (mcode) and Grok 4.7/high (grok CLI),
  summoned through Herdr/hc only.
- Verified baseline at the base (orchestrator-run, `swift test --no-parallel`, CLT plugin flag):
  **467 Core + 119 AppSupport = 586 passed, zero skips/failures**, exit 0. Guard fixtures 21,
  packaging 9, both import guards clean, dev-app built, `git diff --check` clean. Unlike M12,
  M13 EXPECTS Core growth; floors are minima and move only upward at the combined gate (R12).
- Judge feasibility probe: six disposable scratch-prefix rounds COMPLETE (judgment.md evidence).
  The acceptance environment is PROVEN and unblocked (R13): real brew at a pinned revision in a
  scratch prefix, vendored ruby, stub core tap, `brew trust`, offline file:// local tap, binary
  and app cask lifecycles, pin/dependent/broken refusals, multi-keg uninstall truth, sudo-stanza
  hazard, auto_updates provenance, personal sentinels byte-identical.

## 2. Goal and non-goals

**User result (ROADMAP §4):** verified formula and supported cask installations can be checked,
updated, and uninstalled through the finished native workflow. Formula versus cask, exact manager
prefix, and full package identity are shown. Cask removal discloses that a companion app may be
removed, not only a CLI. Pins and manager restrictions are respected. Never force, unpin, relink,
broad cleanup, or hidden `brew update`.

**Non-goals (binding):**
- No uv/pip (M14), Cargo (M15), cached launch/menu bar/opt-in checks (M16), bundled CLI (M17),
  release/signing/notarization/publication (M18–M19); no public contribution invitation.
- No CLI mutation syntax (D-022); `Sources/agent-lens/main.swift` dispatch is byte-identical and in
  no allow-list (R11). No formula/cask INSTALL operation — only Update/Uninstall of an already
  verified installation.
- No `brew update`/`install`/`cleanup`/`autoremove`/`pin`/`unpin`/`tap`/`untap`/`reinstall`/
  `migrate`/`link`/`unlink` by Agent Lens; no `--force`/`--zap`/`--ignore-dependencies`/`--greedy*`/
  `--all`/`--dry-run`/`--overwrite`/`--build-from-source` on any operation argv (R5).
- No weakening of accepted npm/codex behavior, the npm public vocabulary/effect texts/sheets/
  initializers, the M12 R1 invalidation contract, the C-1 footer contract, the D-021 fail-closed
  gate, or D-007/D-019 truthfulness (R4/R11/R12).
- No personal installation as an acceptance target; no mutation of the personal prefix, Cellar,
  Caskroom, `/Applications`, or personal caches; no receipt parser (R1); no invented cask version
  comparator (R2); no `classifySource` change (R10).
- No new dependencies; no `Package.swift` change; no speculative Settings toggles; no cask
  operation for app-artifact or uninstall-stanza-bearing casks in M13 (R7/OD-M13-8).

## 3. Safety envelope

- ROADMAP §6 invariants apply in full: Core UI-free; login-shell environment for every process;
  tri-state install/version; declared candidates never ownership proof; preview→revalidate→
  execute; one mutation at a time via the SHARED `OperationExecutionGate.shared`; no shell
  interpolation, implicit sudo, hidden manager refresh, automatic retry, claimed rollback/
  atomicity, broad cleanup, or config/cache deletion.
- **Homebrew side-effect suppression (R6, binding):** every brew mutation sets
  `HOMEBREW_NO_AUTO_UPDATE=1`, `HOMEBREW_NO_ANALYTICS=1`, `HOMEBREW_NO_INSTALL_CLEANUP=1`,
  `HOMEBREW_NO_AUTOREMOVE=1`; upgrade additionally sets `HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1`
  (uninstall keeps brew's default dependent refusal). Unset if present: `HOMEBREW_UPGRADE_GREEDY`,
  `HOMEBREW_UPGRADE_GREEDY_CASKS`, `HOMEBREW_NO_UPGRADE_QUIT_CASKS`, `HOMEBREW_CASK_OPTS`,
  `HOMEBREW_AUTOREMOVE`. `--yes` is in the upgrade argv (visible disclosure; ask mode is the
  manager default). No production cache/log/temp redirect; the effect text discloses manager
  writes. One environment builder, exact keys asserted by tests.
- **No interactive prompt can block a mutation (R6/R7):** mutation processes spawn with no
  controlling TTY (SETSID, named contract change OD-M13-7, BOTH-adjudicated + npm regression);
  casks with elevating/interactive uninstall stanzas or app artifacts are refused from `artifacts`
  metadata BEFORE any process (R7). Agent Lens never enters a password or triggers a TCC prompt.
- **Confirmation-retargeting invariant (M12 R1, preserved):** a pending brew preparation is bound
  to the registry ID + observed selection at prepare time; any scope/filter/search/selection
  change and any fresh scan/check/refresh/verify invalidates and releases it with zero mutation;
  a LAUNCHED operation is never invalidated by those changes (executing early-return preserved);
  sheets bind to preview/preparation/outcome/unavailable, NEVER `selectedEntry`. At execute, a
  changed target/manager/package/prefix/identity invalidates the preview (R5).
- D-021 fail-closed gate ordering and Core reason strings untouched in shape; the vocabulary grows
  additively (R4). Acceptance fixtures and scratch roots are disposable and authorized; mutation
  journeys run only against the M13 scratch-prefix harness; the personal prefix is read-only and
  hash-manifested (R13).

## 4. Design rulings (summary; full text in judgment.md)

R1 declared-candidate cask routing + four-query membership proof, no receipt parser · R2 manager
verdict oracle, no cask comparator, auto_updates null = not declared · R3 separate cask cache
document · R4 four per-kind×operation vocabulary cases, additive schema 2, shared gate · R5 M10
lifecycle + literal argv with `--yes`, target re-resolution disclosed · R6 suppression env +
no-controlling-TTY spawn, no production cache redirect · R7 cask operations only for no-stanza
CLI casks (corrects both proposals) · R8 whole-cask disclosure + multi-keg uninstall truth ·
R9 pin/deprecated/disabled/version refusals, pinned-newer counts · R10 promotion OD + matrix rule
+ agy correction · R11 new brew sheets, npm byte-identical, CLI dispatch unchanged · R12 floors
raise-only at combined · R13 proven scratch-prefix harness · R14 risk-matched review matrix ·
R15 900s brew mutation timeout (OD) · R16 serial CLT-plugin local suite.

## 5. Phases

Shared protected set (every phase): `Package.swift`, `Resources/**`, `scripts/**`, `.github/**`,
`Sources/agent-lens/**`, npm operation files' control flow/effect texts/public vocabulary,
`NpmOwnershipProbe.swift`, `HomebrewUpdateProbe.swift` formula batch + `HomebrewStatusResolver`,
`UpdateMetadataCache.swift`, `NpmUpdateMetadataCache.swift`, `Tests/Fixtures/M10C/**`,
`Tests/Fixtures/M10D/**`, `Tests/Packaging/**`, `DECISIONS.md`, `ROADMAP.md`,
`AGENT_LENS_SCOPE.md`, `docs/**` (except `docs/capability-matrix.md` + the agy note in F),
historical `briefs/**` and `walkthroughs/**`. The one new file a phase may add under
`walkthroughs/` is its worker report `M13-<phase>-implementation.md` (labeled worker evidence, not
acceptance). Zero new dependencies. Every phase: raw transcripts + SHA-256 of changed files +
protected-file manifest diff + orchestrator rerun of acceptance (D-014). Evidence root `R` is
assigned outside the repository at dispatch; nothing under `R` is committed.

Local gate set (every phase, fresh scratch, R16):
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
Expected: exit 0; Core ≥ 467; AppSupport ≥ 119; zero skips/failures; guard 21; packaging 9. The
implementer prints observed counts and never edits `ci.yml`; floors move only at H (R12).

### M13-A — Cask identity and ownership proof (Core, read-only; safety phase)
- **Goal:** a cask-installed CLI is proven to belong to a declared cask by the manager's own
  evidence (R1), and `verify-installation` reports it. No mutation, no latest-check, no App change.
- **Allow-list (production):** `Sources/AgentLensCore/Ownership/HomebrewCaskOwnershipProbe.swift`
  (new); `Ownership/HomebrewCaskIdentity.swift` (new — Caskroom component parser, opaque version
  dir); `Ownership/InstallationOwnership.swift` (additive cask reason cases + messages only);
  `Ownership/InstallationOwnershipVerifier.swift` (cask routing branch only);
  `Ownership/InstallationOwnershipRenderer.swift` (cask fields only).
- **Allow-list (tests):** `Tests/AgentLensCoreTests/HomebrewCaskOwnershipProbeTests.swift` (new);
  `InstallationOwnershipTests.swift` (new cases only; never weaken existing assertions).
- **Contracts:** R1. npm/formula verifier branches byte-identical; `.unsupportedCask` remains for
  the formula route's cask-only declaration. Proof: `--prefix` + `--caskroom` + component
  decomposition + `info --json=v2 --cask <declared, cap 4>` + `list --verbose --cask <full_token>`
  membership + revalidation. Binary/command_wrapper: canonical equality with a listed staged file;
  moved app: listed staged symlink + equal/strict-descendant of resolved target; `.metadata` never
  membership; malformed listing stays invalid; cap 4096 lines/1 MiB. `installed` null →
  `.packageNotInstalled`; non-string → `.invalidManagerOutput`; string ≠ version-dir →
  `.selectedCaskNotInstalled`. Declaration matching only `old_tokens` → `.caskTokenRenamed`
  (fail-closed). Ownership independent of version grammar/auto_updates/pins/deprecated/disabled.
  No receipt parser. New reasons additive; existing messages byte-identical; cask reasons never
  route through npm ownership mappers.
- **Acceptance:** scripted-runner tests RED then GREEN for every refusal + positive binary,
  command_wrapper, and moved-app-symlink fixtures (synthetic filesystem); tap cask `full_token`
  match; manager/selection changed mid-proof; a read-only live observation against the personal
  casks (observation only, never a target) recording exact argv/output + personal-prefix SHA-256
  manifest before/after. Full gate set; orchestrator rerun.
- **Tier:** strongest reasoning. **Review: mandatory BOTH** (ownership contract).
- **Stop:** a Cellar-shaped assumption; an npm/brew branch change; trusting a declaration without
  manager confirmation; touching `/Applications` or the personal prefix; a needed exhaustive
  switch outside the allow-list.

### M13-B — Cask latest-check, tri-state, and separate cache (Core, read-only)
- **Goal:** opt-in cask latest-check with the manager-verdict oracle (R2), cached in its own
  document (R3), surfaced in the existing Update-Status surface; unknown never collapses to
  up-to-date and never inflates counts.
- **Allow-list (production):** `Updates/HomebrewCaskUpdateProbe.swift` (new);
  `Updates/CaskUpdateMetadataCache.swift` (new); `Updates/UpdateProbeCoordinator.swift` (cask
  stage after the formula batch under the existing admission gate; eligibility change only);
  `Updates/VersionStatus.swift` (additive UnknownReason cases); `Updates/UpdateScanRenderer.swift`
  (new reason arms + cask provenance only); `Sources/AgentLensApp/ToolDetailView.swift`
  (`plainLanguageReason` new arms only); `Operations/NpmUpdateOperation.swift` (`map(_:
  UnknownReason)` new arms only → existing npm reasons; existing arms byte-identical).
- **Allow-list (tests):** new cask probe/cache/coordinator tests; `UpdateProbeCoordinatorTests.swift`,
  `UpdateCLIIntegrationTests.swift` (cask cases); `CapabilityMatrixTests.swift` +
  `docs/capability-matrix.md` ONLY so a cask-declaring row's latest-check cell may be
  `yes: homebrewCask` (mutation cells unchanged; the blanket prohibition replaced by the new rule
  in the same commit).
- **Contracts:** R2/R3. Batch ≤5 commands (`--prefix`, `--caskroom`, `info --cask <tokens cap 16>`,
  `outdated --json=v2 --cask` plain, `list --verbose --cask <installed tokens>`); zero when no
  eligible cask; formula/npm batches, 60s stage budget, 10s query bound unchanged. Tri-state per
  R2 (manager verdict oracle; string equality; identity cross-checks; token keying; auto_updates
  null = not declared → proceed; true/:latest/disabled → typed unknown; pinned-newer →
  updateAvailable + pin flag). No `--greedy`. Cache: separate document, schema 1, TTL 21600, cap
  1 MiB, full identity keys + context digest, only successful comparisons, unknown never cached,
  ecosystem isolation, restore fails closed. Operations never read the cache.
- **Acceptance:** unit tests per tri-state branch (:latest, auto_updates true/null, comma,
  deprecated, disabled, pinned, inconsistent, offline, manager failure); cache TTL/cap/digest/
  ambiguity/isolation tests; read-only live observation of `info --cask` + `outdated --cask`
  recorded verbatim. Full gate set; orchestrator rerun.
- **Tier:** strongest reasoning. **Review: mandatory BOTH** (truthfulness + second cache document).
- **Stop:** inventing a cask comparator; unknown reported as up-to-date; extending the formula
  cache in place; an existing reason arm changes.

### M13-C — Disposable real-Homebrew acceptance harness (test-only; no product code)
- **Goal:** formalize the PROVEN scratch-prefix environment (R13) as the reusable harness later
  phases and the combined gate run. No product source change; no acceptance verdict.
- **Allow-list (tests only):** `Tests/Fixtures/M13/homebrew_acceptance.py` (new, stdlib only);
  `Tests/Fixtures/M13/README.md` (new — harness notes, labeled fixture not acceptance).
- **Contracts:** R13. Operator `--root` must not pre-exist, never a cleanup target; seatbelt denies
  personal-home writes + network (M10C shape); clone --no-hardlinks at pinned revision; vendored
  ruby copy; stub core tap; `brew trust`; offline file:// tap; fixture-only cache/logs/temp
  redirect; --appdir scratch; synthetic formulae (old→new, sentinel, lib/consumer, pinned, broken)
  and casks (binary success; app NO-stanza success; app/stanza REFUSAL; delete-stanza REFUSAL;
  auto_updates; :latest; comma). Personal prefix/Cellar/Caskroom//Applications/caches hash
  manifests before/after. Raw argv/stdout/stderr/exit/elapsed per step.
- **Acceptance:** orchestrator runs the harness; it proves environment setup + each synthetic
  package installs/links + upgrade/uninstall inside scratch + pin/dependent/broken refusals +
  stanza-cask refusal with sentinels intact + personal manifests byte-identical. Implementer
  transcript is not acceptance (D-014).
- **Tier:** flash (test code). **Review:** orchestrator acceptance + one council read-only honesty
  note.
- **Stop:** any scenario needs the personal prefix, `/Applications`, a personal cache, or network
  beyond the local file:// payloads; a sentinel cannot be proven.

### M13-D — Vocabulary extension + formula Update/Uninstall (Core, mutation; safety phase)
- **Goal:** `AcceptedOperation` expresses Homebrew operations (R4); a verified formula copy updates
  and uninstalls through the M10 lifecycle (R5/R6/R8/R9) with literal argv, honest effect text, and
  reconciliation that never trusts exit zero. Shipping registry accepts no formula operation yet.
- **Allow-list (production):** `Detection/DetectorMetadata.swift` (4 new cases + validator
  message); `Detection/DetectorRegistry.swift` (shared-validator message only if a path hardcodes
  it); `Operations/HomebrewOperationModels.swift` (new — formula previews/reasons/deltas/effect
  texts); `Operations/HomebrewOperationEnvironment.swift` (new — one env builder);
  `Operations/HomebrewFormulaUpdateOperation.swift` (new);
  `Operations/HomebrewFormulaUninstallOperation.swift` (new); `Process/BoundedProcessRunner.swift`
  (SETSID no-controlling-TTY spawn ONLY — OD-M13-7, named contract change).
- **Allow-list (tests):** new formula operation tests; `DetectorMetadataTests.swift` +
  `DetectorRegistryTests.swift` (vocabulary list + the two pinned-message assertions updated, not
  weakened); npm regression rerun evidence for the runner change.
- **Contracts:** R4/R5/R6/R8/R9. D-021 guard position exact (cancel → accepted containment →
  before observation/scratch/process). Shared gate. argv `upgrade --formula --yes <full_name>` /
  `uninstall --formula <full_name>`; forbidden flags impossible by construction + asserted.
  Suppression env exact (R6); uninstall keeps dependent refusal; multi-keg uninstall truth (R8);
  pin/deprecated/disabled refusals (R9); target re-resolution disclosed + stale invalidation.
  npm vocabulary/control flow/effect texts byte-identical; npm acceptance scenarios rerun green
  after the runner change.
- **Acceptance:** scripted-runner tests: refusal ordering (counting runner observes zero calls);
  cancel-before-gate releases scratch, no process; preview content (prefix, kind, full identity,
  literal argv, effect text, all installed kegs); stale-identity invalidation (manager/prefix/
  cellar/keg/selection/observed target); execute revalidation; exit-zero-without-change → not
  success; interruption → interrupted/uncertain + reconciliation; gate contention; exact env keys;
  one-target argv. Live formula scenarios via the M13-C harness (orchestrator). Full gate set.
- **Tier:** strongest reasoning. **Review: mandatory BOTH** (mutation + gate + runner contract).
- **Stop:** npm vocabulary changes; the gate moves; a second gate appears; argv needs >1 target;
  the runner change breaks npm acceptance; OD-M13-3/OD-M13-7 unanswered/BLOCKed.

### M13-E — Cask Update/Uninstall (Core, mutation; safety phase)
- **Goal:** a verified SUPPORTED cask (R7: no uninstall stanza, binary/command_wrapper artifact)
  updates and uninstalls with whole-cask disclosure (R8), zap never used, cask-specific
  reconciliation. Stanza-bearing/app casks refuse with a typed reason, no process.
- **Allow-list (production):** `Operations/HomebrewCaskUpdateOperation.swift` (new);
  `Operations/HomebrewCaskUninstallOperation.swift` (new);
  `Operations/HomebrewOperationModels.swift` (cask previews/reasons/deltas/effect texts);
  `Operations/HomebrewOperationEnvironment.swift` (cask env policy).
- **Allow-list (tests):** new cask operation tests.
- **Contracts:** R5/R6/R7/R8/R9. argv `upgrade --cask --yes <full_token>` /
  `uninstall --cask <full_token>`. Support classification from fresh `artifacts` at prepare AND
  revalidated at execute; app-artifact/stanza-bearing → `.caskOperationUnsupported`/
  `.caskUninstallRequiresElevation`, zero process. Whole-cask disclosure from manager artifacts
  (identity, targets, companion-app consequence, zap exclusion). auto_updates true/:latest refuse
  Update; comma NOT refused (manager resolves); uninstall not refused for
  deprecated/disabled/:latest/comma/auto_updates. Reconciliation: staged dir/receipt/target facts;
  zap paths expected present; observation failure never success. Forbidden flags impossible.
- **Acceptance:** scripted tests: support-class refusal (counting runner zero calls); disclosure
  content (companion-app + zap exclusion present); pin/disabled/auto_updates/:latest refusals;
  argv/env assertions; reconciliation facts; interruption; gate contention. Live cask scenarios
  via the harness: binary success, app-no-stanza success (scratch appdir, /Applications absent),
  stanza/delete REFUSAL with sentinels intact. Full gate set.
- **Tier:** strongest reasoning. **Review: mandatory BOTH** (mutation + destructive disclosure).
- **Stop:** a preview promises a version; `--zap` appears; a manager refusal is bypassed; a
  stanza-bearing cask would launch; a second gate appears.

### M13-F — Capability matrix rule, agy correction, and owner promotions (data + tests)
- **Goal:** the test-enforced matrix gains Homebrew cells (R10); the stale agy auto_updates claim
  is corrected with dated evidence; the owner's promotion list (OD-M13-1) is applied as registry
  data, each promoted id with its own harness scenario. Zero promotions is legitimate.
- **Allow-list (production/docs):** `Detectors/DefaultDetectors.json` (`acceptedOperations` for the
  owner-named ids ONLY); `docs/capability-matrix.md` (cell grammar + agy correction);
  `docs/catalogue-identities.md` (APPENDED dated agy correction note only, not a rewrite).
- **Allow-list (tests):** `CapabilityMatrixTests.swift` (rule extension);
  `BundledRegistryResourceTests.swift` (frozen-catalogue assertions if they pin accepted
  operations); one new harness scenario per promoted id.
- **Contracts:** R10. Mutation `yes` requires matching accepted operation + matching declared
  kind; exact cell strings; latest-check `yes: homebrewCask` for cask-declaring rows; cross-row
  note keeps standalone-classification + adds verified-cask-owned distinction; seeded corruption
  fails the same function; frozen 14-id catalogue holds; registry validates on both decode paths.
  agy row reflects the live manager (auto_updates not declared since 2026-11-13; command_wrapper +
  AGY_CLI_DISABLE_AUTO_UPDATE). No Core logic change; no behavior for non-promoted entries.
- **Acceptance:** matrix test green with new grammar + seeded-corruption failures; per-promotion
  harness scenario receipts (D-021); CLI/app facts agree. Full gate set.
- **Dependencies:** D and E accepted. **Gated on OD-M13-1**; without an answer, F ships only the
  rule extension + agy correction, zero promotions.
- **Tier:** flash (data + test). **Review: mandatory BOTH** (mutation-authority surface).
- **Stop:** a `yes` cell without a proved capability; a promotion without its own scenario or
  owner authorization; the agy row keeps a claim the live manager contradicts.

### M13-G — AppSupport / App / CLI integration (mutation presentation; safety phase)
- **Goal:** brew management reachable from the native workflow with truthful presentation (R11),
  M12 invalidation + C-1 preserved, CLI read-only.
- **Allow-list (production):** `AgentLensAppSupport/WorkflowPresentation.swift` (brew affordances +
  new sentences); `AgentLensAppSupport/InventoryService.swift` (brew prepare/execute/cancel
  forwarding); `AgentLensAppSupport/InventoryViewModel.swift` (brew pipelines + invalidation enum
  slots); `AgentLensApp/HomebrewUpdateOperationView.swift` (new);
  `AgentLensApp/HomebrewUninstallOperationView.swift` (new); `AgentLensApp/ToolDetailView.swift`
  (brew Manage block, manager-aware version-cell label, present new sheets);
  `AgentLensApp/MainWindow.swift` (brew sheet bindings).
- **Allow-list (tests):** `WorkflowPresentationTests.swift`, `InventoryServiceTests.swift`,
  `InventoryViewModelTests.swift`, `OwnershipVerificationTests.swift` (AppSupport).
- **Contracts:** R11. npm sheets/initializers/predicates/sentences byte-identical (M10-D host
  compiles/runs unchanged); brew sheets follow C-1; ManagementPresentation brew gates
  (updateAvailable + verified Homebrew manager + matching accepted operation); Core reason strings
  read never retyped; needsVerification brew strings; standaloneLimit suppressed when cask owned;
  R1 invalidation releases brew preparations on every trigger; executing early-return preserved;
  shared busy slot + gate; sheets never bind selectedEntry; `main.swift` dispatch byte-identical
  (cask surfaces via verifier/renderer/coordinator); a11y labels/hints per M12-E/R10.
- **Acceptance:** AppSupport affordance truth-table tests; R1 trigger set releases a brew
  preparation per trigger; C-1 footer proof for brew sheets; host-level test that
  `UpdateOperationView.init` still accepts `NpmUpdatePreview`; orchestrator native spot-check
  (brew preview shows prefix/kind/identity/argv/whole-cask disclosure; Return does not confirm;
  Escape cancels); codex npm Cancel/Confirm strings unchanged. Full gate set.
- **Tier:** strongest reasoning. **Review: mandatory BOTH** (confirmation safety).
- **Stop:** npm sheets change; a reason string is retyped; a brew sheet binds selectedEntry; a CLI
  mutation verb appears; a needed main.swift call-site change (stop-and-ask).

### M13-H — Combined acceptance (orchestrator-run)
- **Goal:** the ROADMAP M13 acceptance end to end on the frozen candidate.
- **Method:** full local gate set rerun by the orchestrator at the frozen SHA (D-014); the M13
  harness run for EVERY promoted entry (preview → Cancel byte-identical prefix hashes → preview →
  Confirm → reconciled result → post-rescan inventory) plus the R7/R8 corrected scenarios
  (stanza refusal, multi-keg residue, app removal, zap survival, pin/dependent/broken refusals,
  interruption, concurrent confirm); native ordinary-app journey via Accessibility (M10-D method)
  against the scratch prefix with fixture-registry acceptance; CLI parity (`scan --check-updates`,
  `verify-installation`); personal prefix/Cellar/Caskroom//Applications/caches SHA-256 manifests
  byte-identical; all seven hosted gates at the exact SHA with floors raised ONLY upward to
  orchestrator-measured counts in a separate orchestrator commit; anchors frozen; capability
  matrix agrees with registry + runtime; protected-file manifest clean; evidence index +
  honest limitations; DECISIONS.md milestone log + new D-024 (cask latest-check shipped,
  supersedes D-019's consequence) + walkthrough. Owner separately authorizes any PR merge. No
  release.
- **Tier:** orchestrator. **Review:** both council models read evidence read-only; never re-run
  destructive scenarios against personal installs.

## 6. Acceptance evidence format

Per phase: exact argv, raw stdout/stderr, exit codes, durations; SHA-256 of every changed file;
protected-file manifest diff; explicit list of unverified/unobserved items (never claimed passed);
worker report labeled worker evidence, not acceptance. Evidence root outside the repository,
disposable, authorized. Hosted receipts retained with run IDs + artifact digests (M10/M11/M12
pattern). Native evidence: Accessibility action transcript, clipboard/hash read-backs, Finder
selection, before/after notes for every system toggle, screenshots supplemental. Harness evidence:
per-scenario JSON receipts + personal-prefix manifests + sentinel hashes.

## 7. Owner decisions

| ID | Decision | Recommendation |
|---|---|---|
| OD-M13-1 | Promotion set (R10) | (b) hermes/aider/goose formula Update+Uninstall + kiro-cli cask Update+Uninstall; options (a) formulae only, (c) +agy, (d) empty; each id own scenario; gates F promotion only |
| OD-M13-3 | Brew mutation timeout (R15) | 900s brew, disclosed; npm 120s unchanged; confirm before D dispatch |
| OD-M13-4 | Ship cask latest-check (revises D-019 consequence) | YES; record D-024 at acceptance |
| OD-M13-8 | Cask support class = no-stanza CLI casks (R7) | YES; app/stanza casks informational; widening later owner decision |

Ruled technical (owner may override before dispatch): OD-M13-2 pinned-newer counts (YES);
OD-M13-5 keep standalone heuristic + explain (YES); OD-M13-6 list --pinned cross-check (YES);
OD-M13-7 SETSID no-TTY spawn contract (YES + npm regression + BOTH adjudication; fallback
pre-refusal-only if BLOCKed). The agy correction is ruled YES (factual). Diagnostic beta,
publication, expenses, contribution invitations remain separate post-M13 owner decisions.

**Owner decisions SETTLED 2026-11-21** (owner: "I agree with your 4 recommendations"): OD-M13-1 =
option (b) hermes/aider/goose formula Update+Uninstall + kiro-cli cask Update+Uninstall;
OD-M13-3 = 900s brew mutation timeout (npm 120s unchanged); OD-M13-4 = ship the cask latest-check;
OD-M13-8 = no-uninstall-stanza CLI casks only. Recorded in DECISIONS.md ("M13 — planning freeze and
owner decisions"). The table above is the frozen recommendation record; this banner records the
settlement and does not alter rulings R1–R16. Implementation remains NOT authorized; each
promotion still needs its own controlled scenario at implementation (D-021).

## 8. Ranked risks

1. **Homebrew side effects beyond the named package** (High, safety) — R6 suppression env +
   `--yes` + no-TTY spawn; one builder, exact-env tests, effect text names each switch; sentinel
   hashes; mandatory D/E review.
2. **Cask ownership mis-proof** (High, safety) — R1 four-query membership proof; basename/
   declaration/Caskroom-substring never proof; app-symlink strict-descendant probe-proven;
   mandatory A review.
3. **Elevating/interactive cask stanzas** (High, safety — JUDGE FINDING) — R7 support-class
   pre-refusal from artifacts; sudo delete-stanza probe-proven; no password/TCC ever; mandatory
   E review; OD-M13-8.
4. **Whole-cask consequence understated** (High, honesty) — R8 disclosure from manager artifacts;
   companion-app + zap-exclusion sentences; zap survival asserted; multi-keg residue disclosed.
5. **npm regression** (Med-High) — PRESERVE list enforced per phase; npm sheets/vocabulary/
   control flow byte-identical; M10-D host compiles/runs; runner SETSID change re-runs npm
   acceptance; codex journey re-run at H.
6. **Cask version truthfulness** (Med) — R2 manager-verdict oracle, no comparator; :latest/
   auto_updates/disabled unknown never up-to-date; auto_updates provenance probe-resolved; agy
   row corrected.
7. **Scratch-prefix harness drift** (Med) — R13 probe-proven route; stub core + trust + offline
   file://; a harness failure is a stop, never a personal-prefix workaround.
8. **Promotion scope creep** (Med) — OD-M13-1 with per-entry reasons; each promotion own scenario;
   opencode stem ambiguity / omp tap presence / claude two-cask conflict deferred.
9. **CI integrity** (Med) — floors minima, raise-only at H to measured counts; anchors frozen;
   implementer never edits ci.yml; protected manifest catches a Core edit.
10. **Flash-tier ambiguity** (Med) — R1–R16 fix every design decision; briefs quote them verbatim;
    anything unlisted is a stop, not a judgement call.

## 9. Dispatch checklist

| Phase | Tier | Writes | Independent review | Skip when |
|---|---|---|---|---|
| M13-A | strongest | Core cask ownership + routing + tests | **mandatory BOTH** | never |
| M13-B | strongest | Core cask latest-check + cache + coordinator + tests | **mandatory BOTH** | A unaccepted |
| M13-C | flash | test-only harness | orchestrator + one council note | B unaccepted |
| M13-D | strongest | vocabulary + formula ops + env + runner SETSID + tests | **mandatory BOTH** | C unaccepted; OD-M13-3/7 open |
| M13-E | strongest | cask ops + support class + tests | **mandatory BOTH** | D unaccepted |
| M13-F | flash | matrix rule + agy correction + owner promotions + tests | **mandatory BOTH** | E unaccepted; OD-M13-1 for promotions |
| M13-G | strongest | AppSupport/App brew presentation + tests | **mandatory BOTH** | F unaccepted |
| M13-H | orchestrator | floor commit + acceptance record + D-024 | orchestrator acceptance; both read | any phase stop open |

After freeze, the orchestrator writes the bounded M13-A dispatch brief (base commit, branch,
allow-list, contracts quoting R1–R16, acceptance matrix, commands, evidence root, stop conditions)
and freezes it before dispatch — **only after the owner authorizes implementation and selects the
implementer**. Later briefs follow accepted dependencies. The implementer receives only the brief,
never the scope document (briefs/README.md). Reviewers never edit; no two agents write the same
candidate concurrently. Implementation, push, PR, merge, promotions, and release are separate
owner authorizations; none is granted by this freeze.

## 10. Delivery status (appended 2026-11-27, after the freeze)

This note is appended after the freeze. Sections 1–9 and rulings R1–R16 are unchanged; nothing in
this note rewrites the planning-time authorization scope.

**M13-A through M13-H are implemented and technically accepted on `milestone/m13-homebrew`.**
The delivery is [PR #4](https://github.com/Hazem-Samak/agent-lens/pull/4) and the acceptance record
is [`../walkthroughs/M13-combined-acceptance.md`](../walkthroughs/M13-combined-acceptance.md):
888 local Swift tests (726 Core + 162 AppSupport, zero failures, zero skips), 21 guard fixtures, 9
packaging checks, all seven hosted gates at the exact SHA, four contained promotion lifecycles, a
native cask Cancel/Confirm/rescan journey and shipping-CLI parity. The shipped product is frozen at
`00ed6ec`; `17ff7fb` adds only the CI floor calibration and the capability-matrix correction, and
`71a8d43` adds only the acceptance record and D-024. The promotion set is exactly OD-M13-1:
`hermes`, `aider`, `goose` formulae and the `kiro-cli` cask.

The authorization statements above — "planning + freeze/commit ONLY", "implementation is NOT
authorized; no implementer is selected" — recorded the state of the planning phase on 2026-11-21.
The implementation authorization that followed is not recorded in this repository, so this note
states only what is verifiable: the phases were implemented, the combined acceptance passed, and
the branch was pushed with an open PR. The owner subsequently cleared the merge;
[PR #4](https://github.com/Hazem-Samak/agent-lens/pull/4) merged to `main` on 2026-11-27 at merge
commit `37bf2f4`, hosted CI on that merge passed
([run 45968760057](https://github.com/Hazem-Samak/agent-lens/actions/runs/45968760057)), and the
milestone branch was deleted after the merge. Any release remains a separate owner decision
under §9.

Three deviations from the per-phase allow-lists in §5 were found in the merged-candidate review on
2026-11-27 and are ratified here rather than silently absorbed:

1. `Sources/AgentLensApp/SettingsView.swift` and `Sources/AgentLensApp/OwnershipVerificationView.swift`
   are not in any phase allow-list. Both edits remove sentences that the shipped feature makes
   false ("updates or uninstalls remain unavailable"); the plan's allow-list was incomplete, not the
   code. Ratified as required truthfulness corrections.
2. `Sources/AgentLensCore/Operations/HomebrewOperationEnvironment.swift` adds `HOMEBREW_NO_SUDO=1`
   for cask mutations and removes `SUDO_ASKPASS` and `HOMEBREW_SUDO_THROUGH_SUDO_USER` for cask
   mutations only, beyond R6's closed key list. Both are fail-closed against elevation and are
   disclosed in the effect text. Ratified as an additive safety strengthening.
3. `docs/CONTRIBUTING.md` was edited in M13-B although §5 protects `docs/**` except
   `docs/capability-matrix.md`. The edit is ratified, and the same change corrects the file's
   remaining closed-vocabulary and cell-grammar rules so they match the shipped registry and matrix.

No ruling R1–R16 is changed, widened or narrowed by this note.
