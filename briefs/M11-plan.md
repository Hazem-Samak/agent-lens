# M11 — original catalogue and contributor foundation: frozen master plan

Status: **FROZEN — awaiting owner approval.** Planning council held 2026-11-12; orchestrator
judgment recorded in `briefs/M11-planning/judgment.md`. This is the milestone master plan, not a
dispatch brief. Bounded per-phase dispatch briefs are written only after the owner approves scope,
answers §7, and names the implementer and independent reviewers.

## 1. Identity and authority

- Milestone: M11 (ROADMAP §4). Base commit: `d0a2b417e8c7d05f3c715a24e93f17851f7ab904` (`main`,
  clean at council start; M10 delivered via PR #1 merge `65f7a82`).
- Milestone branch: `milestone/m11-catalogue` (owner confirms, OD-9). One branch, sequential
  phases, one product writer at a time; reviewers read-only; orchestrator runs acceptance and any
  Git delivery (D-013, D-014).
- Authority: ROADMAP.md, DECISIONS.md D-001…D-020, AGENT_LENS_SCOPE.md §2/§11/§17/§27/§29,
  briefs/README.md. Council inputs: `briefs/M11-planning/proposal-grok.md`,
  `briefs/M11-planning/proposal-minimax.md`, shared task `council-brief.md`.
- Council: MiniMax M3.1-Flash/xhigh (mcode v0.7.6) and Grok 4.7/high (grok 1.0.77), orchestrated
  through Herdr Core. Judge: Qoder orchestrator. Rulings R1–R12 in judgment.md are binding on the
  dispatch briefs; where a proposal conflicted with verified code or primary registries, the
  verified fact won.

## 2. Goal and non-goals

**User result:** Agent Lens detects the originally named 14 families with truthful categories,
package candidates, official links, and measured version behavior; a published capability matrix
states exactly what is and is not manageable; a new tool on an existing layout is a data-only
contribution.

**Non-goals (binding):**
- No new manager mutation adapters (Homebrew M13, uv/pip M14, Cargo M15). The npm adapter's
  semantics are unchanged; its reach is narrowed by the acceptance gate (§5, M11-B).
- No M12 UI/workflow work: no category navigation, filters, counts, conflict summary, keyboard or
  VoiceOver work. The only app edits are the gate's reason surfacing in existing detail views.
- No new fixture layouts, source labels, or PackageManager enum values (R2). uv/pip/cargo/bun
  identities are documented, not declared. No `alternateExecutableNames`.
- No speculative scanner refactor, no per-tool shell scripts, no executed vendor installers.
- No license choice on the owner's behalf, no LICENSE file without the owner's recorded choice,
  no public contribution invitation, no release/signing/publication.
- No personal installation as an acceptance target; no live version pinned as registry data.

## 3. Safety envelope

- ROADMAP §6 invariants apply in full: Core UI-free; login-shell environment for every process;
  tri-state install/version; declared candidates are never ownership proof; preview→revalidate→
  execute; one mutation at a time; no shell interpolation, implicit sudo, hidden refresh, retry,
  claimed rollback, broad cleanup, or config/cache deletion.
- **New invariant for M11 (R1):** mutation eligibility is fail-closed per entry. A detector
  without accepted operations offers no Update/Uninstall, with a truthful reason, even if npm
  ownership verifies. The gate is enforced in Core before any manager process is constructed and
  mirrored in AppSupport/App/CLI. Ownership verification remains diagnostic; latest-check remains
  available per the existing M6/M10-B contracts (read-only, tri-state).
- Acceptance fixtures and scratch roots are disposable and authorized. Research installs (M11-A
  version measurements) happen only in an owner-authorized scratch (OD-8), never on personal
  installs, and are removed afterwards.

## 4. Catalogue summary (judge-verified; full citations frozen in M11-A)

Marks: VD = verified-docs, OL = observed-local, UV = unverified. Full per-field citations and
raw version lines live in `docs/catalogue-identities.md` (M11-A deliverable). Registry rows may
only copy frozen facts.

| id | Display name | Category | Executable | Declared packages (candidates only) | Fixture | Notes / limits |
|---|---|---|---|---|---|---|
| codex | Codex | aiAgent | codex | npm `@openai/codex`; cask `codex` | npmGlobal/npm | keep; `acceptedOperations: [npmUpdate, npmUninstall]` (M10); optional-dep failure → unknown version; info URL recheck in A |
| opencode | OpenCode | aiAgent | opencode | npm `@opencode/cli`, `opencode-ai`; formulae `anomalyco/tap/opencode-v2`, `anomalyco/tap/opencode`, **core `opencode`** (VD) | singleDirectory/standalone | `opencode2` second bin = known limit; taps re-verified in A |
| grok | Grok CLI | aiAgent | grok | none | singleDirectory/standalone | keep; no invented package |
| claude | Claude Code | aiAgent | claude | npm `@anthropic-ai/claude-code`; casks `claude-code`, `claude-code@latest` (VD) | singleDirectory/standalone | native launcher `~/.local/bin` → versions dir = limit; version shape UV → A |
| gemini | Gemini CLI | aiAgent | gemini | npm `@google/gemini-cli`; formula `gemini-cli` (VD) | npmGlobal/npm | formula **deprecated 2026-06-18, disabled 2026-12-18, replacement cask antigravity-cli** = limit; transition banner = limit; version shape UV → A |
| cline | Cline CLI | aiAgent | cline | npm `cline`; formula `cline` (VD) | npmGlobal/npm | formula **deprecated 2026-05-18, disabled 2027-05-18** = limit; personal signature shim is not a layout; OL `3.0.74` |
| hermes | Hermes | aiAgent | hermes | formula `hermes-agent` (VD, official core) | singleDirectory/standalone | git-checkout install = standalone heuristic + limit; PyPI `hermes-agent` documented, not declarable; extra bins `hermes-agent`/`hermes-acp` = limit; OL multi-field version line, first token wins |
| aider | Aider | aiCodingTool | aider | formula `aider` (VD) | singleDirectory/standalone | uv/pip `aider-chat` documented, not declarable; version flag/shape UV → A confirms or holds entry |
| goose | Goose | aiCodingTool | goose | formula `block-goose-cli` (VD) | singleDirectory/standalone | basename shared with pressly formula `goose` = limit; cask `block-goose` is desktop, never declared; version shape UV → A |
| kiro-cli | Kiro CLI | aiCodingTool | kiro-cli | cask `kiro-cli` (VD; formula 404) | singleDirectory/standalone | never detect `kiro` (IDE/router); script dest `~/.local/bin/kiro-cli` per cask zap, confirm from installer text in A; version shape UV → A |
| qodercli | Qoder | aiCodingTool | qodercli | npm `@qoder-ai/qodercli` (VD, legacy-documented) | singleDirectory/standalone | OD-4; dispatcher `qoder` is not the detector; cask `qoder` is the IDE, never declared; OL `1.1.88` |
| dsh | DeepSeek Harness | aiHarness | dsh | npm `@deepseek-ai/dsh` (VD+OL) | npmGlobal/npm | OD-2; never brew formula `dsh` (Dancer's shell) or third-party PyPI names; prerelease tokens normal |
| omp | Oh My Pi | aiHarness | omp | npm `@oh-my-pi/pi-coding-agent` (VD); formula `can1357/tap/omp` (VD) | singleDirectory/standalone | never `@oh-my-pi/cli` (different project); Tern-copied binary is not tap proof; OL `omp/18.19.0` |
| agy | Antigravity CLI | aiHarness | agy | cask `antigravity-cli` (VD, official Google) | singleDirectory/standalone | OD-3; script install `~/.local/bin/agy`; legacy `~/.gemini/bin` root OL-marked; cask `auto_updates` + `agy update` = limits, never invoked |

**Do-not-declare table (binding):** brew formula `dsh`; npm `goose`, PyPI `goose`, brew formula
`goose` (pressly); npm `kiro-cli` (placeholder, bin `kirox`); brew cask `qoder` (IDE); npm
`@oh-my-pi/cli`; PyPI `deepseek-harness`/`deepseek-harness-cli` (third party); npm `qoder`,
`@qoder-ai/qoder`, `@aws/kiro-cli` (404); desktop casks `opencode-desktop`, `block-goose`;
`google-antigravity` PyPI SDK. Second executables (`opencode2`, `hermes-agent`, `hermes-acp`,
`qoder` dispatcher) are known limits, not detectors, in M11.

## 5. Phases

Shared protected set (every phase): `Package.swift`, `DECISIONS.md`, `ROADMAP.md`,
`AGENT_LENS_SCOPE.md`, historical `briefs/**` and `walkthroughs/**`, `scripts/**`,
`Tests/Packaging/**` except where a phase names one file, `.github/**` except where named,
`Sources/AgentLensApp/**` except M11-B's named reason-surfacing edits. Zero new dependencies.
Every phase: raw transcripts + SHA-256 manifest of changed files + protected-file hash check +
written worker report under the phase evidence root; orchestrator reruns acceptance independently.

### M11-A — Catalogue identity freeze (research; docs only)
- **Goal:** `docs/catalogue-identities.md` — per-entry vendor, executable, category, package
  identities, layouts, version-query behavior with raw measured lines, links, evidence marks,
  source URLs; the do-not-declare table; hash-frozen. Coding phases copy only frozen rows.
- **Work:** re-check the open flags read-only: Gemini/Cline/Hermes formula listings and
  deprecations (judge-verified, re-cite); Aider version flag from official CLI reference; Kiro
  installer script text (read, never execute) for destination + version shape; Qoder doc wordings;
  Codex information URL stability; OpenCode taps live. With OD-8 authorization, measure the five
  unverified `--version` shapes in a disposable scratch (npm `--prefix`, uv into scratch); record
  raw lines; destroy scratch. No registry edit, no product code, no install outside scratch.
- **Acceptance:** orchestrator citation review; every field marked; held rows name the decision;
  diff shows only the new doc. Independent re-read of every VD claim.
- **Tier:** strongest reasoning. **Review:** orchestrator citation review (no code).
- **Stop:** primary source unreachable or identity cannot be disambiguated → hold the row, report.

### M11-B — Mutation acceptance gate (Core behavior; safety phase)
- **Goal:** fail-closed per-entry mutation eligibility (R1). Additive optional registry field
  `acceptedOperations` (closed vocabulary `npmUpdate`, `npmUninstall`; absent/empty = none;
  unknown values/duplicates rejected with named errors; schemaVersion stays 2, additive change
  recorded as a new DECISIONS entry at acceptance). Seed `codex` with both; all other entries none.
- **Allow-list sketch:** `DetectorMetadata.swift` (field type), `DetectorRegistry.swift`
  (validation), `DefaultDetectors.json` (codex seed only), `Operations/NpmUpdateOperation.swift`
  + `NpmUninstallOperation.swift` (refuse in `prepare` before any process, typed reason),
  `Operations/OperationModels.swift` (reason), `AppSupport/InventoryService.swift` +
  `InventoryViewModel.swift` (eligibility + reason), `App/ToolDetailView.swift` (+ operation
  views only as needed to render the reason in existing style), `agent-lens/main.swift` (same
  reason), focused new tests + affected existing tests. No ownership-verifier behavior change,
  no latest-probe change, no new layout/manager.
- **Contract:** gate checked before any manager process is constructed; refusal creates no
  operation; reason identical in CLI and app; Verify (diagnostic ownership) still offered for
  declared npm candidates; codex M10 journey byte-for-byte unchanged in behavior.
- **Acceptance:** flip-row test → zero child processes from the injected runner, no operation
  control, reason surfaced identically in CLI/app; codex regression (M10 scenarios); full suite;
  dev app + packaging; **orchestrator-observed native spot-check** of an informational entry
  (reason shown, no destructive control) and of codex (journey intact).
- **Tier:** strongest reasoning. **Review: mandatory independent read-only review** (mutation
  contract, ROADMAP §5.4).
- **Stop:** gate cannot be enforced without changing M10 confirmation semantics → stop, report.

### M11-C — Settled registry batch (data)
- **Goal:** add `claude`, `gemini`, `cline` from frozen rows; apply corrections to `codex`,
  `opencode` (core formula), `grok`. All new entries informational for mutation (no
  `acceptedOperations`).
- **Allow-list sketch:** `DefaultDetectors.json`; exact-set id-list updates in
  `DetectorRegistryTests.swift`, `BundledRegistryResourceTests.swift`, `BundleResourceTests.swift`,
  `UpdateCLIIntegrationTests.swift`; `Tests/Packaging/test_dev_app_bundle.py` (full-registry
  expectation only, spare the two-id fixture); `.github/workflows/ci.yml` **only** the
  CORE_ANCHORS rename `bundledDefaultDetectorsIsValidWithThreeTools` →
  `bundledDefaultDetectorsMatchFrozenCatalogue` (same phase as the test rename) plus any comment
  that would become false; one README id sentence. No floor changes here.
- **Contract:** exact-set assertions stay exact (R7); fixture loop covers every bundled
  definition; registry order stable (existing three first); no live version pins.
- **Acceptance:** filtered registry/fixture tests → full `swift test --no-parallel` → import
  guards → dev app → packaging; preflight `registry_ids` equals the frozen C list; diff within
  allow-list.
- **Tier:** flash (rows frozen). **Review:** orchestrator acceptance; independent review optional
  (data-only, gate already reviewed).
- **Stop:** A held any of the three; validator rejects a frozen name; an out-of-allow-list test
  pins the trio → stop and request scope, never silently edit.

### M11-D — Collision batch (data; high identity risk)
- **Goal:** add `hermes`, `aider` (only if A froze its version query), `goose`, `kiro-cli`, `omp`,
  `agy` from frozen rows, with the do-not-declare table binding. All informational for mutation.
- **Allow-list sketch:** same registry/test/packaging/README files as C (id-list updates);
  `ci.yml` NOT touched (anchor name carries no count).
- **Acceptance:** as C, against the expanded exact id list; a held Aider is absent and its absence
  recorded; collision limits present in fixtures/tests where observable.
- **Tier:** strongest reasoning (wrong package here becomes a wrong mutation target later).
  **Review:** independent read-only review recommended (identity/collision risk); owner names
  reviewers.
- **Stop:** any row unfrozen; any proposal to declare a do-not-declare name; distinguishing Goose
  from pressly would require a scanner change → stop.

### M11-E — Owner-unblocked remainder (data; skippable)
- **Goal:** add `dsh` and/or `qodercli` only after written owner answers (OD-2, OD-4).
- **Dispatch rule:** empty unblock list → skip and record the skip; a skip is a successful M11.
- **Allow-list / acceptance / tier / review:** as D.
- **Stop:** ambiguous answer; an answer selecting `qoder` reopens research instead of dispatching.

### M11-F — Capability matrix and contributor foundation
- **Goal:** publish `docs/capability-matrix.md` (columns: tool, category, tested layouts,
  latest-check, Update, Uninstall, known limits) enforced by one Swift agreement test; publish
  `docs/CONTRIBUTING.md`; prove data-only contribution; raise CI floors to the measured count.
- **Allow-list sketch:** the two new docs; one new/extended Core test file (matrix agreement +
  JSON-only extra-tool proof); `DetectorRegistryTests.swift` (add proof, keep constructor test);
  README links + truthful id sentence; `ci.yml` floor numbers only (Core/AppSupport/total raised
  to the orchestrator-measured count; guard 21 / packaging 9 unchanged; anchors as C set them).
  LICENSE only if OD-7 chose a license (owner-authorized addition).
- **Matrix contract (R3):** Update/Uninstall `yes` only for npm with `acceptedOperations` and only
  for copies the ownership probe verifies as npm-global; latest-check `yes` only for declared npm
  or homebrewFormula; everything else `informational`/`disabled: <reason>`; vendor self-updaters
  never an operation; fixture cells say `synthetic <layout>`, never "verified" against vendor
  trees; every registry id appears once; categories/packages match the JSON.
- **Contribution proof:** test loads registry-shaped JSON with one extra `singleDirectory` tool
  through the existing validated loader and detects it; production id list asserted unchanged.
- **Acceptance:** matrix/proof filters → full suite → guards → dev app → packaging; orchestrator
  counts tests before any floor edit; corruption of a matrix row fails the test.
- **Tier:** strongest reasoning (a false capability cell is a safety defect). **Review:**
  orchestrator acceptance + independent review of the matrix truth rules recommended.
- **Stop:** matrix satisfiable only by hand-waving an unchecked cell; proof needs a new
  layout/manager; local vs orchestrator counts differ → no floor edit.

### Combined M11 gate (orchestrator-run; not an implementer phase)
1. Full local suite `swift test --no-parallel` (zero skips/failures), `swift build`, import guards,
   fresh dev app, all 9 packaging checks — orchestrator reruns, raw logs retained.
2. All seven hosted gates at the exact candidate SHA (guard, 21 guard fixtures, package build,
   isolation gate, full suite with renamed anchor + measured floors, dev app, 9 packaging).
3. CLI/app fact agreement for every entry (same registry; mechanical transcript comparison).
4. End-to-end data-only contribution proof: synthetic fifteenth tool via JSON + fixture only, no
   `Sources/**` scanner/UI edits, observed in CLI and app, then reverted.
5. Gate regression: codex M10 journey intact; unaccepted npm entry shows Verify + reason, no
   mutation control, zero mutation processes; native spot-check observed by the orchestrator.
6. Protected-file SHA-256 manifests clean; evidence index written; limitations recorded (held
   rows, unverified shapes, deprecations).
7. Milestone log entry in DECISIONS.md + walkthrough; owner separately authorizes any Git
   delivery/merge. No release.

## 6. Acceptance evidence format

Per phase: exact argv, raw stdout/stderr, exit codes, durations; SHA-256 of every changed file;
protected-file hash comparison; explicit list of unverified/unobserved items (never claimed as
passed); worker report labeled as worker evidence, not acceptance. Evidence root outside the
repository (scratch), disposable, authorized. Hosted receipts retained with run IDs and artifact
digests as in M10.

## 7. Owner decisions (answer before dispatch)

| ID | Decision | Recommendation |
|---|---|---|
| OD-1 | Approve M11 scope **including the mutation acceptance gate** (M11-B), the only Core behavior change | Approve — verified safety gap; fail-closed, codex unchanged |
| OD-2 | DSH = DeepSeek Harness, npm `@deepseek-ai/dsh`, executable `dsh` | Confirm (VD+OL evidence; brew `dsh` is unrelated) |
| OD-3 | AGY = Google Antigravity CLI, executable `agy`, cask `antigravity-cli` | Confirm (official docs + official cask) |
| OD-4 | Qoder detector executable: `qodercli` vs `qoder` | `qodercli`; `qoder` dispatcher can launch the IDE |
| OD-5 | New npm entries informational until per-tool accepted mutation scenarios; promotions are separate owner-authorized dispatches | Approve; defer promotions (M10-style controlled scenarios per tool) |
| OD-6 | Keep Gemini CLI in the catalogue despite deprecation/transition to Antigravity | Keep — scope §2 names it; matrix carries the limits |
| OD-7 | License: MIT vs Apache-2.0; decide now vs later (≤ M18, before public invitations) | MIT (both members); deciding now lets the contributor guide name it |
| OD-8 | Authorize disposable-scratch version measurements in M11-A (npm/uv installs into scratch only, destroyed after) | Authorize — closes the five unverified shapes without touching personal installs |
| OD-9 | Branch name `milestone/m11-catalogue` | Confirm |
| OD-10 | Raise CI floors in M11-F to the orchestrator-measured count (never lower) | Approve |

Technical rulings R1–R12 (judgment.md) are settled by the judge under the lean protocol; the
owner may override any of them explicitly before dispatch.

## 8. Ranked risks

1. **Silent mutation expansion** — closed by M11-B before any new npm entry (R1); regression-proof
   codex journey; independent review.
2. **Name collisions → wrong future mutation targets** — do-not-declare table binding; identity
   freeze; collision batch at strongest tier; declared candidates never ownership.
3. **Unverified version shapes** — measure in scratch or hold; unknown is neutral, never guessed.
4. **Deprecation drift** (gemini-cli disables 2026-12-18, cline 2027-05-18) — matrix limits;
   identity freeze re-cites; future catalogue maintenance is a contributor-path exercise.
5. **Source-heuristic surprises** — cask/script/uv installs classify `standalone`; npm under
   `/opt/homebrew/bin` is not a formula; Tern copies are not taps. Matrix states each limitation;
   no classifier change in M11 (R2).
6. **CI integrity** — anchor rename synchronized with test rename; exact-set pins; floors only to
   measured counts; hosted gates at exact SHA.
7. **Scope creep into M12/M13–M15** — binding non-goals, allow-lists, stop conditions.

## 9. Dispatch checklist

| Phase | Tier | Writes | Independent review | Skip when |
|---|---|---|---|---|
| M11-A | strongest | `docs/catalogue-identities.md` | citation review (orchestrator) | never |
| M11-B | strongest | gate field + Core/AppSupport/App/CLI seams + tests | **mandatory** | never |
| M11-C | flash | registry + id-list tests + anchor rename + README sentence | optional | A held claude/gemini/cline |
| M11-D | strongest | collision rows + id-list tests + README sentence | recommended | rows unfrozen (omit row, never guess) |
| M11-E | strongest | dsh/qodercli rows | recommended | owner unblock list empty (success) |
| M11-F | strongest | matrix + guide + proofs + measured floors | recommended | B–E incomplete |
| Combined | orchestrator | no feature work | orchestrator acceptance | any phase stop open |

After owner approval and implementer/reviewer selection, the orchestrator writes the bounded
M11-A dispatch brief (base commit, branch, allow-list, contracts, acceptance matrix, commands,
evidence root, stop conditions) and freezes it before dispatch. Later briefs follow accepted
dependencies.