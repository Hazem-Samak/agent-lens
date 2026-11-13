# M12 — complete native diagnostic and operation workflow: frozen master plan

Status: **FROZEN 2026-11-13 after Planning Council.** Orchestrator judgment recorded in
`briefs/M12-planning/judgment.md` (rulings R1–R16, binding). This is the milestone master plan, not
a dispatch brief. Bounded per-phase dispatch briefs are written before each dispatch and quote the
rulings verbatim. The owner pre-authorized the full flow (plan → freeze/commit → implement →
independent review → PR → owner merge decision); **merge is NOT authorized in advance.**

## 1. Identity and authority

- Milestone: M12 (ROADMAP §4). Base commit: `0589fac3cf8f57cf3639ed65077211ab7f2dcd80`
  (`0589fac`, `milestone/m11-catalogue` tip — M11 accepted content + MIT D-023 + PR #2 record).
- Milestone branch: `milestone/m12-workflow` (created from the base). M12 stacks on unmerged M11
  (PR #2 open). One branch, sequential phases, one product writer at a time; reviewers read-only;
  orchestrator runs acceptance and any Git delivery (D-013, D-014). No rebase onto `main`.
- Authority: ROADMAP.md, DECISIONS.md D-001…D-023, AGENT_LENS_SCOPE.md §2/§4–§9/§12/§27/§29,
  briefs/README.md. Council inputs: `briefs/M12-planning/proposal-minimax.md`,
  `proposal-grok.md`, shared task `council-brief.md`.
- Council: MiniMax M3.1-Flash/xhigh (mcode v0.7.6) and Grok 4.7/high (grok 1.0.77), orchestrated
  through Herdr Core. Judge: Qoder orchestrator. Rulings R1–R16 in judgment.md are binding; where a
  proposal conflicted with verified code or a settled decision, the verified fact won.
- Sole product writer (owner-selected): DeepSeek V4.1 Flash 1017 via OMP
  (`river/deepseek-ai/DeepSeek-V4.1-Flash-1017`, max reasoning). Standing independent reviewers
  (owner-selected): MiniMax M3.1-Flash/xhigh (mcode) and Grok 4.7/high (grok CLI), summoned through
  Herdr/hc only.
- Verified baseline at the base (orchestrator-run, `swift test --no-parallel`, CLT plugin flag):
  **467 Core + 80 AppSupport = 547 passed, zero skips/failures**, exit 0. Guard fixtures 21,
  packaging 9. Repo integrity audit at freeze: only `briefs/M12-planning/` is new; no product file
  or historical brief/walkthrough changed; HEAD `0589fac`.

## 2. Goal and non-goals

**User result (ROADMAP §4):** Overview, AI Agents, AI Coding Tools, AI Harnesses, Updates,
Diagnostics, and focused Settings make the complete catalogue understandable and manageable.
Category/update filters, counts, package/source details, and a conflict summary lead to
per-installation PATH evidence and versions. The npm confirmation/progress/output/result journey is
complete; future manager capabilities use the same capability-driven UI and remain explicitly
unavailable until their adapters land. Local-first launch, search, neutral unknowns,
loading/empty/failure states, and Copy/Reveal are preserved. Selection or filtering cannot retarget
an existing confirmation. Native menus, keyboard navigation/shortcuts, VoiceOver labels and spoken
checks, large text, narrow windows, and light/dark appearance are finished. Settings only control
delivered features. **The outstanding M8 keyboard-only Copy/Reveal measurement is closed here.**

**Non-goals (binding):**
- No new manager mutation adapters (Homebrew M13, uv/pip M14, Cargo M15); no per-tool mutation
  promotion (`codex` remains the only accepted entry, D-021); no speculative capability cases or
  buttons for unshipped managers; no command names for unshipped managers in any sentence.
- No cached launch, menu-bar presence, or opt-in periodic checks (M16); no bundled CLI (M17); no
  release/signing/notarization/publication (M18–M19); no public contribution invitation.
- No CLI mutation syntax (D-022); `Sources/agent-lens/main.swift` is in no allow-list.
- No registry/schema/detector change; no capability-matrix edit; no new `AcceptedOperation` case.
- No Core change at all (Core test count stays 467 every phase); no `Package.swift` change; no new
  App test target; no new dependency.
- No speculative Settings toggles; no appearance override; no command palette; no bare-letter
  shortcuts; no ⌘C override; no menu item or key that confirms a mutation.
- No personal installation as an acceptance target; no product fixture mode or launch argument that
  forces text size/appearance; no transcript editing to make a gate pass.

## 3. Safety envelope

- ROADMAP §6 invariants apply in full: Core UI-free; login-shell environment for every process;
  tri-state install/version; declared candidates never ownership proof; preview→revalidate→execute;
  one mutation at a time; no shell interpolation, implicit sudo, hidden refresh, retry, claimed
  rollback, broad cleanup, or config/cache deletion.
- **Confirmation-retargeting invariant (R1, binding):** a pending (unconsumed) Update/Uninstall
  preparation is bound to the registry ID and the observed selection (entry path + canonical target)
  captured at prepare time. Any change to the selected registry ID, `listScope`, `updateStatusFilter`,
  or `searchText`, and any fresh local scan/check/refresh/verify, invalidates and releases the
  preparation with zero mutation and clears the preview. A pure `detailPane` switch
  (Diagnostics/Settings) that changes neither scope nor selection does NOT invalidate. A LAUNCHED
  operation is never invalidated by filter/search/destination/selection change — it completes and
  publishes its own reconciliation snapshot (preserve `InventoryViewModel.swift:621`). Sheets bind
  to preview/preparation/outcome/unavailable, NEVER `selectedEntry`. Independently unchanged: at
  execute time a changed target/manager/package/registry/prefix invalidates the preview (M10 Core).
- D-021 fail-closed gate ordering and Core reason strings are untouched (R4/R12).
- Acceptance fixtures and scratch roots are disposable and authorized; mutation journeys run only
  against the M10 disposable npm fixtures; Copy/Reveal measurement uses a disposable fixture
  executable + symlink on the resolved login-shell PATH, never a personal path.

## 4. Design rulings (summary; full text in judgment.md)

R1 orthogonal `listScope`/`detailPane`, precise invalidation · R2 Updates = installed tri-state rows
+ status filter · R3 three conflict kinds (shadowed/off-PATH/inconsistent), aliases/repeated-slots
not conflicts, versions displayed · R4 `ManagementPresentation` covers all installed entries, Core
reason text read never retyped · R5 contract decision M12-D/C-1: Return never confirms a mutation
(both sheets), mandatory both-reviewer adjudication · R6 in-sheet progress region · R7 read-only
truthful Settings, system appearance · R8 search predicate preserved · R9 synthesized menu/shortcut
table, no confirm/bare-key/⌘K/⌘C · R10 M8 gate via real key events + VoiceOver caption panel ·
R11 760×480 minimum, semantic text, offscreen large-text proof · R12 zero Core/CLI/registry change,
floors raise-only at combined · R13 journey via accepted detail controls, no new prepare entry point,
retained operation summary deferred · R14 Overview = tiles + conflicts, no second inventory ·
R15 risk-matched review matrix · R16 `swift test --no-parallel` + CLT plugin flag authoritative.

## 5. Phases

Shared protected set (every phase): `Package.swift`, `Sources/AgentLensCore/**`,
`Sources/agent-lens/**`, `Sources/AgentLensCore/Detectors/DefaultDetectors.json`, `Tests/Fixtures/**`,
`Tests/Packaging/**`, `scripts/**`, `.github/**`, `Resources/**`, `docs/**`, `DECISIONS.md`,
`ROADMAP.md`, `AGENT_LENS_SCOPE.md`, historical `briefs/**` and `walkthroughs/**`. The one new file a
phase may add under `walkthroughs/` is its worker report `M12-<phase>-implementation.md` (labeled
worker evidence, not acceptance). Zero new dependencies. Every phase: raw transcripts + SHA-256 of
changed files + protected-file manifest diff + orchestrator rerun of acceptance (D-014). Evidence
root `R` is assigned outside the repository at dispatch; nothing under `R` is committed.

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
Expected: exit 0; Core 467 unchanged; AppSupport > 80; total > 547; zero skips/failures; guard 21;
packaging 9. The implementer never edits `ci.yml`; floors move only at combined acceptance (R12).

### M12-A — Presentation-state foundation (AppSupport only; safety phase)
- **Goal:** a testable, UI-free presentation model for list scope, detail pane, the update-status
  filter, conflict classification, management availability, derived counts, and the extended
  invalidation trigger set. The app is visually unchanged; the behavioral change is that any future
  scope/filter/selection change releases a pending preview.
- **Allow-list (production):** `Sources/AgentLensAppSupport/InventoryViewModel.swift` (modify);
  `Sources/AgentLensAppSupport/WorkflowPresentation.swift` (new — `ListScope`, `DetailPane`,
  `UpdateStatusFilter`, `ToolConflictKind`, `ToolConflict`, `ManagementPresentation` + pure
  functions); `Sources/AgentLensAppSupport/InventorySnapshot.swift` (modify — additive derived
  count helpers only).
- **Allow-list (tests):** `Tests/AgentLensAppSupportTests/WorkflowPresentationTests.swift` (new);
  `Tests/AgentLensAppSupportTests/InventoryViewModelTests.swift` (new tests only; never weaken
  existing cases).
- **Contracts:** R1/R2/R3/R4/R8/R12. `filteredEntries` = entries → `listScope` → (if `.updates`)
  `updateStatusFilter` → existing `matches`, registry order preserved; search fields unchanged.
  `listScope`/`detailPane`/`updateStatusFilter` live on the ViewModel. Invalidation fires on
  `listScope`, `updateStatusFilter`, `searchText`, selection-ID change via the existing
  `invalidatePendingUpdate()`; `detailPane` alone does not; executing early-return (:621) preserved.
  `showPathEvidence(registryID:)` selects the ID (invalidates if different) and sets
  `detailPane = .diagnostics`. Conflict kinds and `ManagementPresentation` exactly per R3/R4
  (Grok TD-3/TD-6 tables); `codex` button predicates and Core reason strings byte-identical.
- **Acceptance:** new tests RED then GREEN, one per invalidation vector (R1 table) asserting
  preparation released + preview cleared + no mutation pipeline started, plus the launched-operation
  exemption; a seeded-corruption test (removing a trigger fails); conflict classification positive +
  negative cases (single copy → no conflict; inconsistent nil shadowed → `.inconsistent`; off-PATH
  with positive shadowed → both kinds); `ManagementPresentation` codex/formula/cask/standalone cases;
  counts snapshot-derived (unknown never inflates). Full gate set; Core 467; AppSupport > 80.
- **Tier:** strongest reasoning. **Review: mandatory independent review by BOTH** (R15).
- **Stop:** a Core/registry change appears necessary; `invalidatePendingUpdate`'s executing
  early-return would change; `filteredEntries` would re-sort; a search field would grow.

### M12-B — Seven-destination shell + Overview + Settings + row details
- **Goal:** the sidebar offers Overview, AI Agents, AI Coding Tools, AI Harnesses, Updates,
  Diagnostics, Settings with truthful badges; Overview shows summary tiles + degraded banner;
  category destinations render filtered lists; list rows carry local version, source heuristic, and
  declared packages; Settings is the read-only truthful surface.
- **Allow-list (production):** `Sources/AgentLensApp/MainWindow.swift`,
  `Sources/AgentLensApp/ToolListView.swift`, `Sources/AgentLensApp/OverviewView.swift` (new),
  `Sources/AgentLensApp/SettingsView.swift` (new).
- **Contracts:** R1/R7/R14 (Grok TD-1/TD-7/TD-8). `NavigationDestination` raw values exactly
  `Overview`, `AI Agents`, `AI Coding Tools`, `AI Harnesses`, `Updates`, `Diagnostics`, `Settings`.
  Selecting a destination writes `listScope`/`detailPane` per R1. Overview = tiles (known/installed/
  off-PATH/update-available/conflict-tool count) + degraded banner; NO full 14-row table; a non-empty
  Overview query shows matches across all categories that navigate into the tool's category scope.
  Category badge = installed count for that category; Updates badge = global `updateAvailableCount`;
  Diagnostics/Settings no badge. Rows add local version or `—`, `Source: <heuristic>` or `—`, and
  each declared package as `manager label: name` (declaration ≠ ownership; source ≠ proof). Settings
  content per R7 (no Toggle, no second scene). Sheet bindings stay on preview/preparation.
- **Acceptance:** full gate set; orchestrator read-only native spot-check (seven destinations,
  category partition of the 14 IDs, Overview tiles, Settings has no flippable control, search within
  a category, destination switch keeps selection); screenshot set (Overview, a category, Updates
  empty, Settings, light). No Core diff; diff inside allow-list.
- **Tier:** flash. **Review:** orchestrator acceptance + native spot-check; STOPS if the diff enters
  `InventoryViewModel.swift` or an operation view (request an A revision instead).
- **Stop:** a needed ViewModel fact is missing from A; a destination change would retarget a sheet.

### M12-C — Conflict summary surface + Updates status filter
- **Goal:** Overview lists each conflict tool (kind labels, copy count, measured local versions) and
  `Show PATH evidence` opens that tool's existing Diagnostics; the Updates destination gains the
  update-status filter control.
- **Allow-list (production):** `Sources/AgentLensApp/OverviewView.swift`,
  `Sources/AgentLensApp/ConflictSummaryView.swift` (new),
  `Sources/AgentLensApp/ToolListView.swift` (Updates status filter control),
  `Sources/AgentLensApp/MainWindow.swift` (invoke `showPathEvidence` only),
  `Sources/AgentLensApp/DiagnosticsView.swift` (empty-selection description string only).
- **Contracts:** R2/R3/R14 (Grok TD-3/TD-5). Conflict rows per R3; `.inconsistent` shows the stored
  reason, no invented winner; aliases/repeated-slots stay in Diagnostics counts. `Show PATH evidence`
  calls `showPathEvidence(registryID:)` (A's locked function); DiagnosticsView is the only
  per-candidate surface; no second candidate table. Updates filter binds A's `updateStatusFilter`;
  unknown rows neutral with typed reason; empty copy truthful. Empty-selection copy becomes
  "Select a tool to view its PATH diagnostics."
- **Acceptance:** full gate set; A's classification/navigation tests still pass; orchestrator
  spot-check on a disposable multi-copy fixture (or unit-fixture proof + recorded "no live conflict
  observed" — never install a second personal copy); activating a conflict row lands on Diagnostics
  for that tool; filter changes visible rows; counts stay global.
- **Tier:** flash. **Review:** orchestrator acceptance + spot-check; independent review only if the
  diff changes `showPathEvidence`/`invalidatePendingUpdate` (A locks those; C only calls them).
- **Stop:** the summary needs a diagnostic field that does not exist (do not add it in Core).

### M12-D — Operation-journey completion (mutation presentation; safety phase)
- **Goal:** the detail view renders `ManagementPresentation`; both sheets show an in-flight progress
  region bound to the prepared preview; the footer key equivalents are normalized (C-1); future
  managers stay explicitly unavailable; `codex` npm behavior unchanged.
- **Allow-list (production):** `Sources/AgentLensApp/ToolDetailView.swift`,
  `Sources/AgentLensApp/UpdateOperationView.swift`,
  `Sources/AgentLensApp/UninstallOperationView.swift`.
- **Contracts:** R4/R5/R6/R13 (Grok TD-6/TD-11; contract decision C-1). The view renders
  `ManagementPresentation` and re-derives no predicate; `codex` button predicates/titles/roles and
  every Core reason string byte-identical; non-npm limit sentences are text, not buttons, and never
  hide a codex button. Progress region per R6 (no stdout subscription, no new outcome state, no
  initializer change). **C-1:** preview state of both sheets — no `.defaultAction`; Cancel =
  `.cancelAction` (Escape); destructive confirm has no key equivalent (Tab+Space or click); result/
  unavailable states keep Done/Close `.defaultAction`. Public view initializers stay source-compatible
  (the M10-D Python host constructs `UninstallOperationView`; a parameter change is a phase failure).
  Mutation controls remain in the detail view; Updates rows have no prepare button (R13).
- **Acceptance:** full gate set; A's presentation tests still describe the buttons (no parallel
  predicate); orchestrator read-only native spot-check (M11-B standard: codex controls intact,
  unaccepted npm shows Core sentence + no button, formula/cask/standalone sentences present, grok
  no Manage npm block); M10 fixture scripts unedited and their accepted non-personal paths rerun;
  key-equivalent proof (Return does not confirm, Escape cancels, destructive button Tab+Space).
- **Tier:** strongest reasoning. **Review: mandatory independent review by BOTH**, who must
  specifically adjudicate C-1 (R5/R15).
- **Stop:** the progress region needs streaming output/a new outcome state/an initializer parameter;
  a non-npm sentence would hide a codex button; the capability model needs a Core change.

### M12-E — Native menus, keyboard, accessibility, layout, appearance
- **Goal:** native menus + R9 shortcuts; VoiceOver labels/hints per R10; safety text wraps; 760×480
  content minimum; system appearance; transient path-action feedback announced.
- **Allow-list (production):** `Sources/AgentLensApp/AgentLensApp.swift` (`.commands`),
  `MainWindow.swift`, `ToolListView.swift`, `ToolDetailView.swift`, `PathActions.swift`
  (announcement), `OverviewView.swift`, `SettingsView.swift`, `DiagnosticsView.swift`,
  `UpdateOperationView.swift` (a11y labels/wrapping only), `UninstallOperationView.swift` (same).
- **Contracts:** R9/R10/R11 (Grok TD-9/TD-10/TD-12). Menu/shortcut table per R9; menu actions call
  existing ViewModel methods; Tool prepare/verify chords call prepare/verify ONLY, never confirm,
  disabled when busy/sheet presented/not eligible; no path menu items; ⌘C not overridden; ⌘F is the
  searchable field's own shortcut. Semantic text styles only (no `.font(.system(size:))` literal);
  safety/unavailable/effect text wraps with vertical `fixedSize`, no truncating `lineLimit`. Split
  root `.frame(minWidth: 760, minHeight: 480)`; default 960×600; sheet minimums stay; no
  `preferredColorScheme`, no `windowResizability`. Accessibility phrases per R10/Grok §F.2 (list row
  extends current label with category, local version or "version unknown", conflict kind labels;
  unknown adds no "up to date"/"update available"; path buttons keep labels + hints; sheet titles/
  confirm/cancel hints; progress label; error banners). Path-action transient feedback announced via
  the AppKit accessibility announcement API (implementer confirms the exact selector at build time;
  fallback = focused element's accessibility value; requirement = a VoiceOver user is told the
  outcome). M12-E does not flip system settings (measurement is F).
- **Acceptance:** full gate set; grep shows no new fixed point size / `preferredColorScheme`;
  orchestrator AX read of a list row, both path buttons, an unavailable sentence, both sheet button
  labels; independent review confirms no menu item calls `confirmSelectedUpdate`/`confirmSelectedUninstall`.
- **Tier:** strongest reasoning. **Review: mandatory independent review by BOTH** (menus can prepare
  a mutation; accessibility regression risk).
- **Stop:** a shortcut collides with search entry or ⌘C; a button is keyboard-reachable only via a
  new global bare key; a spoken string would lie about a state; the announcement API is unavailable
  AND the fallback would change a visible string.

### M12-F — M8 keyboard gate + VoiceOver + combined acceptance (orchestrator-run)
- **Goal:** close the outstanding M8 keyboard-only Copy/Reveal measurement with evidence; record
  VoiceOver spoken checks; run the combined journey matrix; pass all seven hosted gates at the
  frozen candidate SHA. No feature work is dispatched with F.
- **Requires:** OD-M12-1 answered YES (owner). If NO, F stays open and M12 is not accepted; an
  AX-only dump is never a VoiceOver pass.
- **Method:** R10/R11 (MiniMax §F.1 + Grok §F.2/F.3/F.4). Real key events (Space on focused button),
  never AXPress/mouse/menu, for all four controls; clipboard read-back byte-for-byte; Finder selects
  the exact recorded target; feedback announced + non-leaking; disabled rows expose no activatable
  control; Full Keyboard Access enabled (record/restore); disposable M10-D environment with fixture
  exe + symlink on the resolved login-shell PATH (stop if `debug-env` omits it; never a personal
  path); clipboard preserved/restored; fixture hashes unchanged. VoiceOver caption-panel screenshots
  + AX dump for the R10 stops. Large text offscreen `NSHostingView` `.accessibility5` AX proof;
  light/dark + narrow-window screenshots under OD-M12-1, restored.
- **Revision rule:** a failed check returns to the implementer as a revision brief naming the failed
  requirement, reproduction, correction, narrowed allow-list (usually `PathActions.swift` + the
  `ToolDetailView` path rows for a focus failure), and rerun gates. The orchestrator does not "fix
  forward"; the implementer may not adjust a transcript. Changed safety behavior is re-reviewed.
- **Review:** orchestrator runs F; both council models review the evidence read-only; they do not
  re-run destructive fixtures against personal installs.

### Combined M12 gate (orchestrator-run; R12/R15)
1. Full local gate set rerun by the orchestrator at the frozen candidate SHA (D-014); record Core
   and AppSupport counts separately (local two-summary layout) and the combined total (hosted).
2. All seven hosted gates at the exact candidate SHA (guard, guard-fixtures, swift-build,
   isolation-gate, full-test-suite, build-dev-app, packaging); floors raised only to the
   orchestrator-measured counts, never lowered (467/80/547/21/9), anchors frozen, in a separate
   orchestrator commit after the recount.
3. Actual-app journey matrix (ROADMAP M12 acceptance; mutation rows only against the disposable npm
   fixtures `Tests/Fixtures/M10C/npm_update_acceptance.py`, `M10D/npm_uninstall_acceptance.py`):
   find/filter → inspect competing copies → confirm or cancel an eligible operation → review output
   → observe post-rescan winner/version; plus empty inventory, offline/unknown latest, failed
   rescan, missing manager, permission denial/unverified ownership, long paths, keyboard-only (F),
   VoiceOver (F), capability truthfulness, shortcut safety, retarget attempt (R1). Cancel rows keep
   the prefix SHA-256 manifest byte-identical (M10-D pattern).
4. Protected-file SHA-256 manifest clean (Core/CLI/registry/fixtures/Package.swift/scripts/docs/
   historical briefs match the base except the orchestrator floor commit); evidence index written;
   limitations recorded honestly (e.g. "no live conflict observed", any un-evidenced spoken stop).
5. Milestone log entry in DECISIONS.md + walkthrough; owner separately authorizes the PR merge. No
   release.

## 6. Acceptance evidence format

Per phase: exact argv, raw stdout/stderr, exit codes, durations; SHA-256 of every changed file;
protected-file manifest diff; explicit list of unverified/unobserved items (never claimed as passed);
worker report labeled as worker evidence, not acceptance. Evidence root outside the repository,
disposable, authorized. Hosted receipts retained with run IDs and artifact digests (M10/M11 pattern).
Native evidence: focus-traversal transcript, clipboard read-back digests + literal strings, Finder
selection path, VoiceOver caption screenshots + AX dump, before/after notes for every system toggle.

## 7. Owner decisions

| ID | Decision | Recommendation |
|---|---|---|
| OD-M12-1 | During M12-F only, temporarily enable Full Keyboard Access + VoiceOver and toggle appearance (optionally larger system text size), restoring each previous value before finishing | **YES** — required to evidence the M8 keyboard gate and VoiceOver spoken checks; A–E proceed while open; if unanswered by F, toggle nothing and leave F open |
| OD-M12-2 | Decline scope §7 bare keys U/R/S and the ⌘K palette (R9) | Accept the decline (both councils); chorded Tool items prepare, never confirm; owner may object before freeze |

Rulings R1–R16 are settled by the judge under the lean protocol (owner delegated technical
decisions); the owner may override any explicitly before dispatch. MiniMax's OD-M12-1…6 are resolved
by the rulings (judgment.md). The optional diagnostic beta (ROADMAP §7) is a post-M12 owner decision,
not an M12 question. License is MIT (D-023). Merge of M11 (PR #2) and M12 stays with the owner.

## 8. Ranked risks

1. **Confirmation retargeting** (High, safety) — R1 precise invalidation locked in A before any new
   surface; one test per vector + seeded corruption; sheets bind to preview not selectedEntry;
   mandatory A/D review.
2. **M8 gate falsely closed with AXPress** (High, gate integrity) — R10 requires real key events;
   AXPress/mouse/menu forbidden as activation; failed measurement is a product defect, not a method
   adjustment.
3. **Scope creep into M13–M16** (Med-High) — binding non-goals; R4 sentences never name unshipped
   commands; R7 no toggles; allow-lists exclude Core operations.
4. **Flash-tier ambiguity** (Med) — R1–R16 close every design decision; each brief quotes them; any
   unlisted choice is a stop, not a judgement call.
5. **App-layer logic untestable** (Med) — R12/R13 keep testable logic in AppSupport; orchestrator
   native spot-check is the App evidence (M11-B precedent).
6. **Accessibility regression / C-1 changes accepted interaction** (Med) — R10 label list + spoken
   checks; C-1 named and adjudicated by both reviewers; E mandatory review.
7. **CI integrity** (Med) — Core 467 every phase; floors raise-only; anchors frozen; implementer
   cannot edit `.github/`/`scripts/`; protected manifest catches a Core edit.
8. **Native-measurement feasibility** (Med) — OD-M12-1 explicit; TCC re-checked; a refused permission
   leaves F open, never a silent pass; fixture PATH verified via debug-env.
9. **Initializer drift breaks M10 fixture host** (Low-Med) — R5/R6 forbid initializer changes; a
   compile failure in the M10-D host is a D failure.
10. **Overview as a second inventory** (Low) — R14 tiles + conflicts only; category lists partition
    the catalogue.

## 9. Dispatch checklist

| Phase | Tier | Writes | Independent review | Skip when |
|---|---|---|---|---|
| M12-A | strongest | AppSupport presentation model + invalidation + tests | **mandatory BOTH** | never |
| M12-B | flash | seven-destination shell + Overview + Settings + row details | orchestrator + spot-check | A unaccepted |
| M12-C | flash | conflict surface + Updates filter + navigation | orchestrator + spot-check | B unaccepted |
| M12-D | strongest | ManagementPresentation render + progress + C-1 | **mandatory BOTH** | C unaccepted |
| M12-E | strongest | menus + keyboard + a11y + layout + appearance | **mandatory BOTH** | D unaccepted |
| M12-F | orchestrator | no feature work; M8 gate + VoiceOver + combined | both read evidence | E unaccepted / OD-M12-1 no |
| Combined | orchestrator | floor commit + acceptance record | orchestrator acceptance | any phase stop open |

After freeze, the orchestrator writes the bounded M12-A dispatch brief (base commit, branch,
allow-list, contracts quoting R1–R16, acceptance matrix, commands, evidence root, stop conditions)
and freezes it before dispatch. Later briefs follow accepted dependencies. The implementer receives
only the brief, never the scope document (briefs/README.md). Reviewers never edit; no two agents
write the same candidate concurrently.