# M12 proposal — Grok (Planning Council)

Status: independent council proposal, 2026-11-13. Not a frozen brief and not acceptance evidence.
The orchestrator judges, reconciles, and freezes the plan. Sole later product writer remains
DeepSeek V4.1 Flash 1017 via OMP, as already authorized. This file is the only artifact this
council member wrote.

Verified base: `milestone/m12-workflow` at `0589fac3cf8f57cf3639ed65077211ab7f2dcd80`
(`0589fac`, commit subject records PR #2 open for owner review). `0589fac` is HEAD, not merely an
ancestor. Live GitHub PR state was not re-queried. The suite count 547 was not re-executed; the
floor literals were read from CI.

## How to read this proposal

Sections C–F are the design authority. Section B cuts that design into sequential dispatches.
A flash-tier implementer receives one phase brief extracted from B, with the matching contracts
from C–F pasted in. The implementer does not receive `AGENT_LENS_SCOPE.md`.

Frozen technical decisions are TD-1…TD-12 at the end of H. They are resolved here so the
implementer does not choose them. Owner decisions are OD-M12-1 and OD-M12-2. Neither blocks
dispatch of M12-A through M12-E. M12-F cannot pass without OD-M12-1.

---

## A. Current-state audit

### A.1 Verified against the code

| Claim in the council brief | Evidence | Verdict |
|---|---|---|
| Sidebar destinations are Inventory and Diagnostics only | `NavigationDestination` has exactly `inventory` and `diagnostics` (`Sources/AgentLensApp/MainWindow.swift:6-8`). The sidebar lists `allCases` (`MainWindow.swift:193-209`). | Verified. No Overview, category destinations, Updates, or Settings. |
| Search over name / executable / path | `.searchable` prompt at `ToolListView.swift:25-29`. Predicate is display name, executable name, registry ID, detected entry/resolved paths, every candidate path, and the winner or off-PATH root (`InventoryViewModel.swift:936-956`). | Verified. Category label and package name are not in the haystack. |
| Counts in toolbar and sidebar | Sidebar `installed/known` (`MainWindow.swift:199-202`). Toolbar known, installed, and update-available (`MainWindow.swift:321-327`). Counts come from the snapshot (`InventorySnapshot.swift:88-102`). | Verified. |
| Update count ignores unknown | `updateAvailableCount` returns true only for `.updateAvailable` (`InventorySnapshot.swift:96-102`). `VersionStatus` is `upToDate` / `updateAvailable` / `unknown` (`VersionStatus.swift:49-52`). | Verified. |
| Detail has Copy / Reveal, ownership, Update / Uninstall | Path rows (`ToolDetailView.swift:224-233`, `PathActions.swift:64-83`). Ownership (`ToolDetailView.swift:245-254`). Uninstall block (`ToolDetailView.swift:280-310`). Update button (`ToolDetailView.swift:523-538`). | Verified. |
| Sheets are the M10 confirmation / result journey | `UpdateOperationView.swift:36-80`, `UninstallOperationView.swift:37-85`, presented from `MainWindow.swift:87-136`. | Verified. See A.3 for what is still missing. |
| 14 registry entries, three categories, only `codex` accepted | `DefaultDetectors.json`: one `acceptedOperations` key, on `codex` (line 18). Categories below. | Verified by reading the registry. |
| CLI is read-only | `main.swift:62` `scan`, `:114` `verify-installation`, `:160` `debug-env`. No update/uninstall case. | Verified. |
| CI floors | `ci.yml:154` and `:193-207`: Core 467, AppSupport 80, total 547, guard fixtures 21, packaging 9. | Floor literals verified. Fresh test execution was not run. |
| App has no test target | `Package.swift:14-44`: test targets are `AgentLensCoreTests` and `AgentLensAppSupportTests` only. `Tests/` has those two Swift trees plus `Fixtures/` and `Packaging/`. | Verified. |
| Branch | Read-only `git rev-parse`: `milestone/m12-workflow`, HEAD `0589fac`. | Verified. |

Category census from `DefaultDetectors.json` (id → category):

- `aiAgent` (7): codex, opencode, grok, claude, gemini, cline, hermes.
- `aiCodingTool` (4): aider, goose, kiro-cli, qodercli.
- `aiHarness` (3): omp, agy, dsh.

`ToolCategory` is documented as detector metadata, not a navigation model
(`DetectorMetadata.swift:44-45`). M12 must keep that enum in Core and build navigation outside Core.

`PackageManager` is `npm`, `homebrewFormula`, `homebrewCask` only (`DetectorMetadata.swift:61-64`).
There is no uv, pip, or cargo declaration to render. `DetectedTool.source` is the heuristic
`"npm"` / `"brew"` / `"standalone"` (`ToolDetector.swift:31-32`).

Conflict inputs already exist on `ToolPathDiagnostic` and are not a separate model:

- Selection is `.winner` / `.offPath` / `.notInstalled` / `.inconsistent` (`PathDiagnostics.swift:78-83`).
- For a winner, `shadowedInstallationCount` is `max(0, targetGroups.count - 1)`. For off-PATH and not-installed it is `0`. For inconsistent it is `nil` (`PathDiagnostics.swift:242-251`).
- `sameTargetAliasCount` and `repeatedPathSlotCount` are separate fields (`PathDiagnostics.swift:90-91`). Diagnostics already prints them (`DiagnosticsView.swift:243-277`).

### A.2 Already satisfied — do not rebuild

These stay as they are. Phases call them; they do not replace them.

1. Local-first launch. `launch()` runs only from `.idle` and passes `updateMode: nil` (`InventoryViewModel.swift:223-226`). The file header states no manager command and no cache read on launch (`InventoryViewModel.swift:10-12`).
2. Search, empty inventory, failed scan, and no-search-hits states (`ToolListView.swift:14-76`).
3. Registry-ID selection. Filtering hides a row without dropping the ID (`InventoryViewModel.swift:95-96`, `:187-192`). `reconcileSelection` keeps the ID when it still exists (`InventoryViewModel.swift:905-914`).
4. Pending-preview invalidation on search, selection change, and scan/check/refresh (`InventoryViewModel.swift:97-100`, `:196-197`, `:690`). An executing mutation is left alone (`InventoryViewModel.swift:614-621`).
5. Prepare-time identity check: generation, registry ID, and observed entry path plus canonical target must still match or the preparation is cancelled (`InventoryViewModel.swift:331-339` and `:484-492`).
6. Tri-state version rendering, including an em dash for unknown latest (`ToolDetailView.swift:544-574`).
7. D-021 surfacing for npm-declared tools (`ToolDetailView.swift:284-287` and `:526-537`), using `NpmUpdateUnavailableReason.operationNotAccepted.message` and the uninstall twin (`OperationModels.swift:89` and the uninstall message at the cited `operationNotAccepted` case).
8. Copy / Reveal policy in `PathActionTarget` / `PathActionDispatcher` (`PathActionTarget.swift:11-20`, `:189-213`) and native effects in `PathActions.swift:142-158`.
9. Update and Uninstall sheet contents: preview identity, effect text, argv rendering, Cancel versus Confirm roles, stdout/stderr, reconciliation delta (`UpdateOperationView.swift:62-80`, `:83-163`; `UninstallOperationView.swift:63-85`, `:88-166`). Uninstall's default button is Cancel (`UninstallOperationView.swift:73-74`). Update's default button is Confirm Update (`UpdateOperationView.swift:74-77`).
10. One mutation slot. `isBusy` includes both pipelines (`InventoryViewModel.swift:156-158`). The sheets are mutually exclusive by the presentation flags (`InventoryViewModel.swift:166-167`).
11. Diagnostics detail for one selected tool: selection, counts, per-installation versions, candidates (`DiagnosticsView.swift:35-64`).

### A.3 What M12 must ADD

1. Seven sidebar destinations: Overview, AI Agents, AI Coding Tools, AI Harnesses, Updates, Diagnostics, Settings.
2. A list scope (category or updates) intersected with the existing search predicate.
3. Sidebar and header counts derived from the snapshot, including a conflict count.
4. Package and source details on list rows, labeled so a declaration is not ownership and a source string is not proof.
5. A conflict summary computed from the existing diagnostic fields, with a navigation action into the existing `DiagnosticsView`.
6. An explicit in-sheet progress region while `isExecuting` is true and no outcome exists yet. Today the body stays on the preview and only the button title changes (`UpdateOperationView.swift:36-47` and `:74-75`).
7. One capability-driven availability model for declared Homebrew formula/cask and for a standalone classification, rendered as text with no button. Today the Manage section is omitted unless an npm package is declared (`ToolDetailView.swift:96-99`, `:268-270`), so a formula-only tool such as `hermes` has no unavailable explanation. A Homebrew `updateAvailable` with a nil `npmPackage` shows the status and no explanation that managed update is absent (`ToolDetailView.swift:523-538`).
8. Native menus and chorded shortcuts that call existing actions.
9. VoiceOver labels/hints, a window minimum, wrapping safety text, and appearance that follows the system.
10. The M8 keyboard-only Copy/Reveal measurement, as an orchestrator gate (M12-F), plus VoiceOver spoken checks.

### A.4 What M12 must CHANGE

1. `NavigationDestination` and the sidebar, replacing the Inventory row with the seven destinations. The content column remains a list for the three category scopes and for Updates.
2. `filteredEntries`, so it applies `listScope` and then the existing `matches` predicate. Search text, match fields, and registry order stay.
3. Tool-row accessibility text, adding category, local version, and conflict kind. The current label is name, executable, install state, and "Update available" (`ToolListView.swift:146-162`). It does not say "up to date" for unknown. Keep that.
4. The operation sheet body, so an in-flight operation shows a progress region bound to the same preview. Initializers stay source-compatible. `Tests/Fixtures/M10D/npm_uninstall_acceptance.py` constructs `UninstallOperationView` with the current initializer (around the host at lines 480 and 499).
5. Manage / Update Status rendering, so it reads `ManagementPresentation` (TD-6). The `codex` button predicates stay byte-identical.

### A.5 What M12 must PRESERVE

- M10 prepare / confirm / cancel / execute / reconcile semantics, preview fields, effect text, and button roles.
- D-021 fail-closed gate, including the Core reason strings.
- D-006 and D-007 tri-state behavior. Unknown never increments `updateAvailableCount`.
- D-022. `Sources/agent-lens/main.swift` is not on any allow-list.
- Core stays free of SwiftUI and AppKit (`Package.swift:10-12`). AppSupport stays free of SwiftUI and AppKit (`Package.swift:29-30`). The import guard's default root is `Sources/AgentLensCore` only (`scripts/check-core-ui-imports.py:64`). Do not edit that script. The orchestrator also runs it with `--source-root Sources/AgentLensAppSupport`.
- Selection by registry ID. Destination switches that do not change scope, search, or selection do not invalidate a pending preview (TD-4). This matches today: changing Inventory/Diagnostics does not call `invalidatePendingUpdate`.
- Copy/Reveal eligibility, literal clipboard text, and lstat-style reveal (`PathActions.swift:139-158`).
- Loading, empty, failed-rescan, and degraded-environment banners already in the list, detail, and diagnostics views.
- Registry schema, detector JSON, and the capability matrix document.

### A.6 Not verified

- Fresh `swift test` count. Floors are the authority until the orchestrator recounts.
- Whether Full Keyboard Access, VoiceOver, or Dark Mode is currently on. Not inspected, and not changed.
- The exact M10-D process argv for the synthetic-HOME launch. The walkthrough records the method (`walkthroughs/M10-D-implementation.md:141-154`) and does not include the argv in the section read. M12-F copies the accepted recipe from that evidence rather than inventing one.
- `windowResizability` on the macOS 14 deployment target (`Package.swift:7`). Unverified. Forbidden (TD-10).
- Any behavior of `proposal-minimax.md`. Not read. The directory listing at start contained only `council-brief.md`.

---

## B. Phase decomposition

Six phases, one milestone branch, one product writer, sequential. M12-A through M12-E are implementer
dispatches. M12-F is the orchestrator's measurement and combined gate. A failed F returns to the
implementer as a revision brief that names the failed check, the files, and the rerun. F is not a
feature backlog.

Every phase:

- Branch: `milestone/m12-workflow`. Base for M12-A is `0589fac`. Each later phase bases on the
  accepted tip of the previous phase. No rebase onto `main`. No second branch.
- The implementer does not stage, commit, branch, reset, merge, or push.
- Evidence root `R` is assigned by the orchestrator outside the repository at dispatch. Nothing
  under `R` is committed. Scaffolds do not enter the repo.
- Protected in every phase, even if unstated below: `Package.swift`, `Sources/AgentLensCore/**`,
  `Sources/agent-lens/**`, `Sources/AgentLensCore/Detectors/DefaultDetectors.json`,
  `Tests/Fixtures/**`, `Tests/Packaging/**`, `scripts/**`, `.github/**`, `Resources/**`,
  `docs/**`, `DECISIONS.md`, `ROADMAP.md`, `AGENT_LENS_SCOPE.md`, `briefs/**` (including this
  proposal), and every existing walkthrough. The one new file a phase may add under
  `walkthroughs/` is the worker report named in that phase. Personal installations, the real
  Agent Lens cache, and credentials are out of bounds.
- If a file outside the allow-list seems necessary, stop and report. Do not edit it.
- Local suite command, from the repo root, fresh scratch, no package or toolchain change:

```sh
env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS swift test --no-parallel
```

If that fails before any test with `TestingMacros` plugin-not-found, rerun with
`-Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing`
and keep both logs. This is the M11-F invocation. Do not switch `xcode-select`. Hosted CI is
unchanged and does not need the flag.

- Also, each phase: `swift build` under the same `env -u`, `python3 scripts/check-core-ui-imports.py`,
  `python3 scripts/check-core-ui-imports.py --source-root Sources/AgentLensAppSupport`,
  `python3 Tests/Packaging/test_core_ui_imports.py`, a fresh `python3 scripts/build-dev-app.py`,
  and `python3 Tests/Packaging/test_dev_app_bundle.py` (9 checks). Exit 0. Floors stay
  467 / 80 / 547, guard fixtures 21, packaging 9. The implementer never edits `ci.yml`.
  Extra tests are allowed. A count below a floor fails the phase.
- Worker report: `walkthroughs/M12-<phase>-implementation.md`, labeled worker evidence.
- Reviewers are read-only. Mandatory independent review means both standing council models
  (MiniMax M3.1-Flash/xhigh via mcode, Grok 4.7/high via grok CLI), summoned by the orchestrator
  through Herdr/hc after the candidate is frozen.

### M12-A — presentation state

**Goal.** AppSupport can scope the inventory, classify conflicts, describe management
availability, and invalidate a pending preview when the scope, the search text, or the selection
changes. The app still shows Inventory and Diagnostics. No new window behavior.

**Non-goals.** No SwiftUI. No menus. No copy changes in the sheets. No Core, registry, CLI, or
fixture edits. No new operation type. No change to `matches` search fields.

**Allow-list.**

- `Sources/AgentLensAppSupport/InventoryViewModel.swift`
- `Sources/AgentLensAppSupport/WorkflowPresentation.swift` (new)
- `Tests/AgentLensAppSupportTests/WorkflowPresentationTests.swift` (new)
- `Tests/AgentLensAppSupportTests/InventoryViewModelTests.swift` (new tests only; do not weaken
  existing cases)
- `walkthroughs/M12-A-implementation.md` (new worker report)

**Contracts.** Implement TD-2, TD-3, TD-4, TD-5, and TD-6 exactly. `filteredEntries` becomes
scope-then-search, registry order preserved (`InventoryViewModel.swift:181-185` is the current
search-only version). `listScope` and `detailPane` are stored on the view model. `detailPane`
does not invalidate. `listScope` and `searchText` do, through the existing
`invalidatePendingUpdate()`. An executing update or uninstall still returns immediately
(`InventoryViewModel.swift:621`). Public initializers of the operation views are untouched
because this phase does not touch those files.

`WorkflowPresentation.swift` imports Foundation and AgentLensCore only.

**Acceptance outline.**

- New tests, red before the implementation exists, then green:
  - Updates scope contains only `.updateAvailable`. `.unknown`, `.upToDate`, and a nil update
    are absent. An unknown whose name matches the query is still absent.
  - Category scope intersects search. A coding-tool query typed while scope is `.category(.aiAgent)`
    yields empty.
  - Search fields are unchanged: category label and package name do not match.
  - Conflict kinds match TD-3, including alias-only and repeated-slot fixtures that produce no
    kind, an inconsistent fixture with nil shadowed count that produces `.inconsistent`, and a
    hand-built off-PATH fixture with a positive shadowed count that produces both kinds.
  - `codex`-shaped affordances match the current button predicates (TD-6 table). Formula-only
    and cask-only fixtures produce the fixed sentences and no prepare case.
  - Changing `listScope` or `searchText` while a preview is pending clears that preview and
    does not call execute. The same change during `isExecutingUpdate` or `isExecutingUninstall`
    leaves the outcome slot and the preview identity in place.
  - Setting `detailPane` to `.diagnostics` or `.settings` leaves a pending preview in place.
  - `showPathEvidence` for the already selected ID sets `detailPane` to `.diagnostics` and
    keeps the preview. The same call for a different published ID invalidates the preview and
    selects that ID.
- Full gates from the phase preamble. Expected: exit 0, counts at or above 467 / 80 / 547,
  zero skips and failures.
- `git diff --check` clean. Diff stays inside the allow-list.

**Depends on.** M11 accepted content at `0589fac`. Nothing else.

**Stop.** Stop if a test seems to require a Core change, a registry edit, or a change to
`invalidatePendingUpdate`'s executing-early-return. Stop if `filteredEntries` would re-sort.

**Review.** Mandatory independent review. This phase changes when a pending confirmation dies.

### M12-B — seven destinations, filters, counts, Settings

**Goal.** The window shows the seven destinations. Category and Updates lists, counts, list-row
package/source details, the Overview summary tiles, and the truthful Settings surface are visible.
Conflict rows are not in this phase (M12-C). Operation sheets are unchanged.

**Non-goals.** No menu bar commands (M12-E). No conflict navigation. No sheet progress region.
No predicate edits. If a view-model API from A is missing, stop and ask for an A revision.

**Allow-list.**

- `Sources/AgentLensApp/MainWindow.swift`
- `Sources/AgentLensApp/ToolListView.swift`
- `Sources/AgentLensApp/OverviewView.swift` (new)
- `Sources/AgentLensApp/SettingsView.swift` (new)
- `walkthroughs/M12-B-implementation.md` (new)

**Contracts.** TD-1, TD-7, and TD-8. Menus and shortcuts are M12-E (TD-9), not this phase.
`NavigationDestination` raw values are exactly:
`Overview`, `AI Agents`, `AI Coding Tools`, `AI Harnesses`, `Updates`, `Diagnostics`, `Settings`.
Selecting a destination writes `listScope` and `detailPane` per TD-1. The content column for a
category or for Updates is the existing `ToolListView` over `filteredEntries`. Overview's content
is `OverviewView`. Settings uses `SettingsView` in the detail column and a static content pane
with the sentence `Settings apply to this window. There are no preferences to turn on.`
Diagnostics keeps the current `listScope` and sets `detailPane` to `.diagnostics`; the content
list does not change membership because of that selection.

List rows add, under the executable name: the local version or `—`, the source heuristic or `—`
prefixed with `Source`, and each declared package as `manager label: name`. Declared lines use
`PackageManager.label`. The source line uses `DetectedTool.source` and is the heuristic already
labeled "Source (heuristic)" in the detail. Rows still show the install badge and the update
badge only for `.updateAvailable`.

Sidebar badges, all from snapshot facts via the A helpers:

- Overview: conflict-tool count (tools, not kinds).
- Each category: installed count for that category (`installState != .notInstalled`).
- Updates: `updateAvailableCount`.
- Diagnostics and Settings: no badge.

The toolbar keeps `knownToolCount`, `installedToolCount`, and `updateAvailableCount`. It adds
the conflict-tool count with the same "only if greater than zero" pattern as the update count
(`MainWindow.swift:324-327`).

Overview tiles: known, installed, off-PATH (`selection` is `.offPath`), update-available,
conflict-tool count, and the degraded-environment banner when `isDegradedEnvironment` is true.
Tiles are not buttons. A non-empty `searchText` on Overview replaces the tiles with matches
from scope `.all`, in registry order. Choosing a match selects that registry ID and sets
`listScope` to the entry's category (TD-1, TD-4). The match list has no prepare button.
Empty, loading, and failed states reuse the list's existing copy when the snapshot is nil or
the phase is `.loadingLocal` or `.failed`. A populated snapshot with zero conflicts still
shows `0`.

Settings content is TD-8, read-only, no `Toggle`.

**Acceptance outline.**

- Orchestrator native spot-check of the debug app, read-only, no mutation: each destination
  shows the specified title; category lists partition the 14 registry IDs; Updates is empty
  before Check Updates and, after a check, contains only rows whose status is update-available;
  an unknown row is absent there; Settings contains no control that can flip; search inside
  AI Agents hides non-matches and does not show a harness; a non-empty Overview query lists
  matches and choosing one lands in that tool's category; switching to Diagnostics leaves the
  same registry ID selected.
- Screenshot set: Overview, one category, Updates empty state, Settings, light appearance.
- Full gates. Allow-list diff. No Core diff.

**Depends on.** M12-A accepted.

**Stop.** Stop if the view needs a new view-model fact that A does not publish. Stop if a
destination change would retarget a sheet. The sheet bindings stay on `updatePreview` /
`updatePreparation` / `uninstallPreview` / `uninstallPreparation` (`MainWindow.swift:90-91` and
`:115-116`), never on `selectedEntry`.

**Review.** Orchestrator acceptance. Independent review is not required for this phase unless
the diff touches `InventoryViewModel.swift` or either operation view. If it does, the phase
stops instead of expanding.

### M12-C — conflict summary that opens Diagnostics

**Goal.** Overview lists each conflict tool and can open that tool's existing diagnostics.
Diagnostics itself is not rewritten.

**Non-goals.** No second candidate table. No new scanner. No alias counting. No change to
path-action eligibility.

**Allow-list.**

- `Sources/AgentLensApp/OverviewView.swift`
- `Sources/AgentLensApp/MainWindow.swift` (only to invoke `showPathEvidence` from the overview
  action)
- `Sources/AgentLensApp/DiagnosticsView.swift` (only the empty-selection description string,
  currently `ToolListView`-adjacent copy at `DiagnosticsView.swift:25-29`)
- `walkthroughs/M12-C-implementation.md` (new)

**Contracts.** TD-3 and TD-5. Each conflict row shows display name, registry ID, the kind
labels in TD-3 order, the winner entry path or the off-PATH root, and the selected local
version or `—`. A row whose kind is `.inconsistent` shows the inconsistency string already
stored on `PathSelection` and does not show a path as a winner. The action label is
`Show PATH evidence`. It calls `showPathEvidence(registryID:)`. The detail then shows the
existing diagnostics sections (selection, summary counts, canonical installation versions,
candidates). Those sections stay the only per-candidate listing.

Empty-selection copy becomes `Select a tool to view its PATH diagnostics.` The "No Tool
Selected" title stays.

**Acceptance outline.**

- View-model tests from A still pass, plus a UI spot-check on a disposable fixture inventory
  if the orchestrator has one that produces two canonical targets. If the live login shell
  has no such tool, the spot-check uses the A unit fixtures as the proof of classification
  and records the live inventory as "no conflict row observed" rather than manufacturing one
  against a personal install. Do not install a second copy of a personal tool to create a
  conflict.
- Activating `Show PATH evidence` on the already selected tool leaves a pending preview in
  place (A's test). Activating it for a different tool clears a pending preview (A's test).
  The spot-check confirms the destination detail is `DiagnosticsView` and the candidate list
  is that view's existing list.
- Full gates. Allow-list diff.

**Depends on.** M12-B accepted.

**Stop.** Stop if the summary needs a diagnostic field that does not exist. Do not add one in
Core.

**Review.** Orchestrator acceptance. Mandatory independent review only if the diff changes
`showPathEvidence` or `invalidatePendingUpdate`. A should already have locked those; C should
only call them.

### M12-D — operation journey completion

**Goal.** The detail view renders `ManagementPresentation`. The existing sheets show an
in-flight progress region bound to the already prepared preview. Future managers stay
explicitly unavailable. `codex` npm behavior is unchanged.

**Non-goals.** No new adapter. No new `AcceptedOperation` case. No CLI syntax. No change to
prepare, execute, cancel, preview fields, effect text, argv, or button roles. No change to
public view initializers. No update-all.

**Allow-list.**

- `Sources/AgentLensApp/ToolDetailView.swift`
- `Sources/AgentLensApp/UpdateOperationView.swift`
- `Sources/AgentLensApp/UninstallOperationView.swift`
- `walkthroughs/M12-D-implementation.md` (new)

`WorkflowPresentation.swift` is frozen in A. If the view cannot render it without a model
change, stop and request an A revision. Do not re-derive the predicates in the view.

**Contracts.** TD-6 and TD-11. Button visibility:

| Condition (already in the view) | Still true after D |
|---|---|
| Update button when `.updateAvailable`, `npmPackage != nil`, and `.npmUpdate` is accepted (`ToolDetailView.swift:523-532`) | Same. Title stays `Prepare Update…` / `Preparing Update…`. |
| Unaccepted npm update uses the Core message (`ToolDetailView.swift:535-537`) | Same string, via the presentation value. |
| Uninstall button when `.npmUninstall` is accepted, ownership is verified npm, and selection is winner or off-PATH (`ToolDetailView.swift:284-304`) | Same. Title stays `Uninstall…` / `Preparing Uninstall…`. Role stays `.destructive`. |
| Accepted npm uninstall without verification shows `Verify Installation to enable Uninstall for this npm package.` (`ToolDetailView.swift:306-308`) | Same. |
| Unaccepted npm uninstall shows the Core message (`ToolDetailView.swift:284-287`) | Same. |
| Manage section hidden when no npm package is declared (`ToolDetailView.swift:96-99`) | The npm block follows the presentation. Non-npm limit sentences may appear for an installed tool that declares a formula or cask or whose source is `standalone`. They are text. They are not buttons. |

Progress region, both sheets: when `isExecuting` is true, `outcome` is nil, and `preview` is
non-nil, show a `ProgressView` and the text `Update in progress` or `Uninstall in progress`,
plus the preview's registry ID, package name, and prefix. Keep the preview grid above or
below that region. Do not subscribe to stdout. When `outcome` is non-nil, the existing result
view is the only body. When `unavailable` is set and there is no preview and no outcome, the
existing unavailable view is the only body. Footer buttons, default-action shortcuts, Cancel
role on Uninstall, and `interactiveDismissDisabled` stay as they are.

**Acceptance outline.**

- A's presentation tests still describe the buttons. D adds no parallel predicate.
- Orchestrator read-only native spot-check, same standard as M11-B
  (`walkthroughs/M11-B-acceptance.md:60-66`): Codex still offers the M10 controls when its
  facts qualify, and withholds Update when the status is not update-available. An unaccepted
  npm-declared tool shows the Core sentence and no button. A formula-declared tool shows the
  formula sentence and no brew button. Grok, which declares no package, shows no Manage npm
  block; the standalone sentence appears only when a copy is installed and `source` is
  `standalone`.
- Fixture scripts `Tests/Fixtures/M10C/npm_update_acceptance.py` and
  `Tests/Fixtures/M10D/npm_uninstall_acceptance.py` are not edited. The orchestrator reruns
  the accepted non-personal paths those scripts already have. A compile failure inside the
  M10-D host because an initializer changed is a D failure.
- Full gates. Allow-list diff.

**Depends on.** M12-C accepted. The journey must be reachable from Updates and from a category
list before D's spot-check, which is why D follows B and C.

**Stop.** Stop if completing the progress region seems to require streaming output, a new
outcome state, or an initializer parameter. Stop if a non-npm sentence would hide a `codex`
button.

**Review.** Mandatory independent review. The diff sits on the mutation presentation.

### M12-E — menus, keyboard, accessibility, layout, appearance

**Goal.** Native menus and the TD-9 shortcuts exist. VoiceOver labels and hints match section F.
Safety text wraps. The window has a content minimum. Appearance follows the system.

**Non-goals.** No command palette. No bare-key shortcuts. No confirm shortcut. No appearance
picker. No settings toggle. No change to prepare/execute semantics. No product fixture mode
and no launch argument that forces a text size or appearance.

**Allow-list.**

- `Sources/AgentLensApp/AgentLensApp.swift`
- `Sources/AgentLensApp/MainWindow.swift`
- `Sources/AgentLensApp/ToolListView.swift`
- `Sources/AgentLensApp/ToolDetailView.swift`
- `Sources/AgentLensApp/PathActions.swift`
- `Sources/AgentLensApp/OverviewView.swift`
- `Sources/AgentLensApp/SettingsView.swift`
- `Sources/AgentLensApp/DiagnosticsView.swift`
- `Sources/AgentLensApp/UpdateOperationView.swift` (accessibility labels and wrapping only)
- `Sources/AgentLensApp/UninstallOperationView.swift` (accessibility labels and wrapping only)
- `walkthroughs/M12-E-implementation.md` (new)

**Contracts.** TD-9, TD-10, TD-12. Menu actions call the existing view-model methods. The
prepare items call `prepareSelectedUpdate` and `prepareSelectedUninstall` only. They are
disabled when `isBusy` is true, when a sheet is presented, or when the affordance is not the
matching `.prepareNpmUpdate` / `.prepareNpmUninstall`. Path menu items call
`PathActionDispatcher` with the same targets as the buttons, and they are disabled while a
sheet is presented. None of the four path menu items uses ⌘C.

New and edited text uses semantic styles (`.body`, `.headline`, `.caption`, and the existing
monospaced design). No `.font(.system(size:))` literal in the allow-listed views. Unavailable
reasons, effect text, and path ineligibility reasons use
`.fixedSize(horizontal: false, vertical: true)` and do not set a truncating `lineLimit`.

The split view's root sets `.frame(minWidth: 760, minHeight: 480)`. Default size stays
960×600 (`AgentLensApp.swift:165`). Do not set `preferredColorScheme`. Do not add
`windowResizability` (unverified on macOS 14).

Accessibility additions required for F, using the phrases in F.2:

- List row label extends the current `accessibilityDescription` (`ToolListView.swift:146-162`)
  with category `label`, local version or `version unknown`, and any conflict kind labels.
  Unknown update status adds no "up to date" and no "update available".
- Section titles in detail, diagnostics, overview, and settings are headers.
- Path buttons keep their current labels (`PathActions.swift:52-54`) and gain hints
  `Copies the path text.` and `Asks Finder to select this path.`
- Sheet titles and the confirm/cancel buttons expose their visible titles as labels. The
  Uninstall confirm hint is `Removes the reviewed npm package after this confirmation.` The
  Update confirm hint is `Applies the reviewed npm update after this confirmation.` Cancel's
  hint is `Closes this confirmation without a change.`
- Progress region label is the progress sentence plus the registry ID.

**Acceptance outline.**

- Full gates. Allow-list diff. Grep of the allow-listed views shows no new
  `.font(.system(size:` and no `preferredColorScheme`.
- Orchestrator AX read of one list row, both path buttons, one unavailable sentence, and both
  sheet button labels, from the debug app. This is the label contract. Spoken VoiceOver is
  M12-F, not this phase.
- Independent review confirms no menu item calls `confirmSelectedUpdate` or
  `confirmSelectedUninstall`.

**Depends on.** M12-D accepted. Labels describe the D progress region and the C conflict rows.

**Stop.** Stop if a shortcut collides with search text entry or with ⌘C. Stop if the only way
to reach a button from the keyboard seems to be a new global bare key.

**Review.** Mandatory independent review, because menu items can prepare a mutation.

### M12-F — M8 keyboard gate and combined acceptance

**Goal.** The orchestrator measures keyboard-only Copy and Reveal in the real app, measures
VoiceOver captions, and runs the combined journey matrix in G. No feature work is dispatched
with F.

**Non-goals.** The implementer does not start F. The orchestrator does not "fix forward."
A failure becomes a revision brief with a narrowed allow-list: only the files that own the
failed behavior, usually `PathActions.swift` and the path rows in `ToolDetailView.swift` for a
focus failure.

**Depends on.** M12-E accepted, and OD-M12-1 answered yes. If OD-M12-1 is no, F stays open and
M12 is not accepted.

**Review.** The orchestrator runs F. The two council models review the evidence read-only.
They do not re-run destructive fixtures against personal installs.

**Stop.** Stop the measurement if the disposable environment's login-shell PATH does not
contain the fixture executable. Record the resolved PATH. Do not point the gate at a personal
installation. Stop if activation would require a mouse event or `AXPress`.

---

## C. Information architecture and navigation

### C.1 Destinations (TD-1)

The shell stays a three-column `NavigationSplitView` (`MainWindow.swift:54-64`).

Two orthogonal fields, both on `InventoryViewModel`:

- `listScope`: `.all`, `.category(ToolCategory)`, or `.updates`.
- `detailPane`: `.tool`, `.diagnostics`, or `.settings`.

| Destination | Writes listScope | Writes detailPane | Content column | Detail column |
|---|---|---|---|---|
| Overview | `.all` | `.tool` | Summary tiles, and conflict rows after M12-C. A non-empty search replaces the tiles with matches across all categories. | Selected tool's existing detail, or the empty selection view. |
| AI Agents | `.category(.aiAgent)` | `.tool` | `ToolListView` | Existing `ToolDetailView` |
| AI Coding Tools | `.category(.aiCodingTool)` | `.tool` | `ToolListView` | Existing `ToolDetailView` |
| AI Harnesses | `.category(.aiHarness)` | `.tool` | `ToolListView` | Existing `ToolDetailView` |
| Updates | `.updates` | `.tool` | `ToolListView` of update-available rows | Existing `ToolDetailView` |
| Diagnostics | unchanged | `.diagnostics` | The current scope's list, unchanged | Existing `DiagnosticsView` |
| Settings | unchanged | `.settings` | Static one-sentence pane | `SettingsView` |

Overview is a summary. It is not a second copy of the 14-row inventory. The old Inventory
destination is removed. Not-installed tools remain in their category lists, which is the
current inventory behavior (`InventorySnapshot.swift:3-6`). The sidebar badge for a category
is the installed count. The list header shows `installed/known` for that scope.

Search stays one field, the existing `.searchable` binding to `searchText`. It applies after
the scope filter. Overview with an empty query shows tiles. Overview with a query shows
matches from `.all`, in registry order. Choosing a match selects that registry ID and sets
`listScope` to that entry's category, which is a scope change and invalidates a pending
preview (TD-4). The detail then shows the tool. The match list does not contain a prepare
button.

### C.2 Counts

All counts are derived from `snapshot.entries`. Nothing is counted from button titles or
badge strings.

- Known: `entries.count` for the scope, or `knownToolCount` globally.
- Installed: `installState != .notInstalled`. `installedNotOnPath` counts as installed
  (`InventorySnapshot.swift:90-94`).
- Off-PATH: `selection` is `.offPath`.
- Update-available: `.updateAvailable` only.
- Conflict tools: entries whose TD-3 kind list is non-empty. One tool with two kinds counts
  once.

The Updates badge equals the global `updateAvailableCount`, so it cannot drift from the
toolbar. A category header may also show how many of that category are update-available.
That smaller number is not the Updates badge.

### C.3 Conflict summary (TD-3, TD-5)

A conflict kind exists only when the published diagnostic says so:

1. **Shadowed copies.** `shadowedInstallationCount` is greater than zero. The label includes
   that integer. This is the duplicate-installation fact: more than one canonical target while
   a winner exists (`PathDiagnostics.swift:244-245`). The summary does not keep a second
   "duplicates" counter.
2. **Off PATH.** `selection` is `.offPath`. The production scanner sets the shadowed count to
   0 in this case (`PathDiagnostics.swift:248-249`), so the row's kind is off-PATH. The root
   string on `.offPath` is the path text the row shows.
3. **Inconsistent.** `selection` is `.inconsistent`. The summary shows the reason string. It
   does not invent a winner path. `shadowedInstallationCount` is nil here
   (`PathDiagnostics.swift:250-251`) and is not treated as zero conflicts.

Same-target aliases (`sameTargetAliasCount`) and repeated PATH slots (`repeatedPathSlotCount`)
are not kinds. They remain visible in Diagnostics summary counts
(`DiagnosticsView.swift:261-270`). Invalid candidates (broken symlinks and the other
non-live kinds) are not kinds. `notInstalled` is not a conflict.

`Show PATH evidence` selects the registry ID and sets `detailPane` to `.diagnostics`. The
user then sees the existing selection section, summary counts, canonical installation
versions, and candidates (`DiagnosticsView.swift:52-63`). M12 does not copy those sections
into Overview.

### C.4 Updates and tri-state rules

The Updates list's membership test is `if case .updateAvailable = entry.updateStatus`.
Unknown, up to date, and not-checked are excluded. They do not increment the badge. The empty
copy is `No verified updates. Check Updates reads supported latest versions. Unknown stays
unknown.`

Latest checks that already exist stay available: npm metadata and Homebrew formula metadata
(D-019, capability matrix `latest-check` column). A formula `updateAvailable` appears in the
list. Its detail shows the status. Managed update appears only through TD-6, which requires
an accepted npm operation. The list row itself has no Update or Uninstall button.

Mutation controls remain where they are today: the detail view, and only for the accepted
npm cases. Today that is a verified npm-global `codex` copy (`DefaultDetectors.json:18`,
D-021).

### C.5 Selection and filter safety (TD-4)

Ways the new UI could retarget a confirmation, and the required behavior:

| Event | Required behavior | Test |
|---|---|---|
| Search text changes | Pending preview is invalidated. Selection ID is kept even if the row hides. | View-model test in A. |
| `listScope` changes (category, Updates, Overview) | Pending preview is invalidated. The sheet must not rebuild its preview from the newly selected row. | View-model test in A. |
| Overview search result chooses another registry ID | Selection change invalidates, then the scope change invalidates again. One preview cannot be swapped for the other tool's package. | View-model test in A. |
| `showPathEvidence` for a different ID | Selection change invalidates. | View-model test in A. |
| `showPathEvidence` for the same ID, or Diagnostics/Settings with no scope or selection change | Pending preview stays. The sheet still shows the original registry ID, package, prefix, and target. | View-model test in A. |
| Rescan, Check, Refresh, Verify | Existing `run` / verify paths call `invalidatePendingUpdate()` before work (`InventoryViewModel.swift:249`, `:307`, `:459`, `:690`). | Existing tests stay green. |
| Executing update or uninstall while any of the above happens | `invalidatePendingUpdate` returns without cancelling (`InventoryViewModel.swift:621`). The sheet stays bound to `updatePreview` or `uninstallPreview`, which were captured before execute (`InventoryViewModel.swift:378-379`, `:531-532`). | View-model test in A. |
| Prepare completes after the user has changed selection or the observed entry/target | Existing generation and `observedSelection` guard cancels the preparation (`InventoryViewModel.swift:331-339`). | Existing tests stay green. |
| A view binds the sheet to `selectedEntry` | Forbidden. Bindings stay on the preview / preparation / outcome / unavailable properties (`MainWindow.swift:90-91`, `:115-116`). | Reviewer checks the diff. |

Invalidation means the existing function: cancel an unconsumed preparation with zero
mutation, drop the preview, and do not execute. It does not mean "re-prepare for the new
row."

### C.6 Module boundary

- Core: diagnostics, versions, ownership, operations. No new type for navigation, conflict
  badges, or settings. `ToolCategory` stays metadata (`DetectorMetadata.swift:44-45`).
- AppSupport: `listScope`, `detailPane`, conflict classification, management presentation,
  counts, invalidation. Foundation and AgentLensCore imports only.
- App: SwiftUI destinations, menus, sheets, pasteboard, Finder, accessibility. Native effects
  stay in the app target, as `PathActionTarget.swift:7-9` already requires.

---

## D. Operation journey completion

### D.1 What M10 already accepted

The npm journey already has these states, and M12 keeps them:

1. **Prepare.** `prepareSelectedUpdate` / `prepareSelectedUninstall` build one preview or a
   typed unavailable reason. D-021 is checked in the view model before the service call
   (`InventoryViewModel.swift:313-316`, `:466-469`) and again inside Core prepare (D-021).
2. **Confirm.** The sheet shows registry ID, versions or package facts, prefix, paths, effect
   text, and the argv as text that is not executed (`UpdateOperationView.swift:83-122`,
   `UninstallOperationView.swift:88-128`).
3. **Cancel.** Cancel drops a pending preview with no mutation (`InventoryViewModel.swift:411-437`
   and `:570-595`). Uninstall's default button is Cancel.
4. **Result.** Outcome state, exit status, reconciliation delta, stdout, stderr, truncation
   (`UpdateOperationView.swift:137-163`). Execute publishes the post-operation snapshot
   (`InventoryViewModel.swift:389-391`).
5. **One at a time, revalidation, no automatic retry.** Unchanged. M12 does not open those
   files in Core.

M10-D's ordinary-app evidence drove the sheet with Accessibility actions
(`walkthroughs/M10-D-implementation.md:145-154`). That closed the click path. It did not close
keyboard-only Copy/Reveal. M12-F does not restage that click-through as if it were the keyboard
gate.

### D.2 What "complete the journey" means here

Three additions, all presentation:

1. The journey is reachable from a category list, from Updates, and after a conflict inspection,
   without retargeting (section C).
2. While `isExecuting` is true and the outcome is still nil, the sheet shows a progress region
   for the bound preview (M12-D). Core does not publish incremental stdout. The result view
   remains the place output appears. No new `OperationState` case.
3. Tools whose manager is not an accepted npm operation show a fixed unavailable sentence
   (TD-6). The sentence is not a disabled button. Disabled buttons read as features that can
   be turned on.

No contract decision changes M10. The progress region is justified as presentation because
`isExecuting` already exists (`UpdateOperationView.swift:10`) and the body previously stayed
on the preview for the whole execution (`UpdateOperationView.swift:36-47`). Confirm, Cancel,
and the result view keep their roles.

### D.3 Capability-driven availability (TD-6)

`ManagementPresentation` is a pure function of one `InventoryEntry`. The view renders it and
does not reimplement the conditions.

Update slot:

- `.prepareNpmUpdate` when status is `.updateAvailable`, `update.npmPackage != nil`, and
  `acceptedOperations` contains `.npmUpdate`.
- `.unavailable(NpmUpdateUnavailableReason.operationNotAccepted.message)` when those version
  and package facts hold and `.npmUpdate` is absent.
- `.unavailable("A newer version is reported by the supported latest check. Managed update is not available for this installation in this version.")`
  when status is `.updateAvailable` and `npmPackage` is nil.
- `.hidden` otherwise. Not-checked and unknown do not grow an update button.

Uninstall slot:

- `.prepareNpmUninstall` when `.npmUninstall` is accepted, `ownership.verifiedInstallation.manager == .npm`,
  and selection is `.winner` or `.offPath`.
- `.unavailable` with the Core uninstall `operationNotAccepted` message when an npm package is
  declared and `.npmUninstall` is absent.
- `.needsVerification("Verify Installation to enable Uninstall for this npm package.")` when
  `.npmUninstall` is accepted and the verified-npm condition is false.
- `.hidden` when no npm package is declared.

`otherLimits`, included only when `installState != .notInstalled`, each at most once:

- A declared `homebrewFormula`: `Homebrew formula update and uninstall are not available in this version.`
- A declared `homebrewCask`: `Homebrew cask update and uninstall are not available in this version.`
- `DetectedTool.source == "standalone"`: `This copy is classified as standalone. Agent Lens does not delete standalone files.`

`codex` declares npm and a cask. Its npm buttons follow the first two slots. The cask sentence
is additional text. It must not replace the npm buttons. A `source` of `npm` does not add the
standalone sentence.

No sentence names uv, pip, cargo, `brew upgrade`, `brew uninstall`, or a vendor self-updater.
Those adapters are M13–M15 or out of scope (capability matrix, D-004, D-008). The pattern M13
will extend is this value type: a new prepare case arrives with the adapter, in a later
milestone, and until then the sentence stays.

Sheet unavailable reasons that Core already returns (`unsupportedManager`, `managerUnavailable`,
`operationNotAccepted`, and the rest of `NpmUpdateUnavailableReason`) continue to use
`reason.message`. The app does not paraphrase them.

---

## E. Native polish, accessibility, and Settings

### E.1 Menus (TD-9)

Commands live on the `Window` scene in `AgentLensApp.swift`. There is one Settings surface,
the sidebar destination. The menu item Settings selects that destination. It does not open a
second SwiftUI `Settings` scene.

| Menu | Item | Shortcut | Calls | Disabled when |
|---|---|---|---|---|
| Agent Lens | Settings… | ⌘, | `detailPane = .settings` | never |
| File | Rescan | ⌘R | `rescan()` | `isBusy` |
| File | Check for Updates | ⌘⇧U | `checkForUpdates()` | `isBusy` |
| File | Refresh Update Metadata | ⌘⇧R | `refreshUpdates()` | `isBusy` |
| View | Overview | ⌘1 | destination Overview | never |
| View | AI Agents | ⌘2 | destination AI Agents | never |
| View | AI Coding Tools | ⌘3 | destination AI Coding Tools | never |
| View | AI Harnesses | ⌘4 | destination AI Harnesses | never |
| View | Updates | ⌘5 | destination Updates | never |
| View | Diagnostics | ⌘6 | destination Diagnostics | never |
| View | Settings | ⌘7 | destination Settings | never |
| Tool | Prepare Update… | ⌥⌘U | `prepareSelectedUpdate()` | busy, sheet presented, or update slot is not `.prepareNpmUpdate` |
| Tool | Prepare Uninstall… | ⌥⌘⌫ | `prepareSelectedUninstall()` | busy, sheet presented, or uninstall slot is not `.prepareNpmUninstall` |
| Tool | Verify Installation | ⌥⌘I | `verifySelectedInstallation()` | busy, or selection is not winner/off-PATH |
| Tool | Copy Selected Entry Path | none | dispatcher `.copyPath` for `.selectedEntry` | ineligible, or sheet presented |
| Tool | Reveal Selected Entry in Finder | none | dispatcher `.revealInFinder` for `.selectedEntry` | ineligible, or sheet presented |
| Tool | Copy Resolved Target Path | none | dispatcher `.copyPath` for `.resolvedTarget` | ineligible, or sheet presented |
| Tool | Reveal Resolved Target in Finder | none | dispatcher `.revealInFinder` for `.resolvedTarget` | ineligible, or sheet presented |

Edit's Cut/Copy/Paste stay the system items. ⌘C is not overridden. ⌘F stays the searchable
field's own shortcut. No item is added for it.

Scope §7 listed ↑/↓, Enter, U, R, S, and ⌘K. The resolution (OD-M12-2, default proceed):

- ↑/↓ and list selection stay the native `List` behavior (`ToolListView.swift:33-43`). M12
  does not reimplement them.
- Enter does not prepare or confirm an operation.
- U, R, and S are not bound. A bare key fires while the search field is focused and would
  type, or it would sit one key away from prepare. Rescan is ⌘R. Prepare is the chorded Tool
  items above. Those chords call prepare, never `confirmSelectedUpdate` or
  `confirmSelectedUninstall`.
- ⌘K is not bound. A command palette is a new surface and is outside M12.
- The sheet's existing `.keyboardShortcut(.defaultAction)` stays. For Uninstall that remains
  Cancel (`UninstallOperationView.swift:73-74`). For Update that remains Confirm Update.
  M12 does not add a second confirm shortcut.

View shortcuts that change `listScope` invalidate a pending preview through TD-4. Settings
and Diagnostics (⌘, ⌘6, ⌘7) do not change `listScope` and do not invalidate by themselves.

### E.2 VoiceOver labels and hints

Phrases the accessibility tree must expose, and that VoiceOver is expected to speak. M12-E
puts them on the controls. M12-F records them.

- List row: display name, executable name, category label, install-state phrase already used
  (`Installed and on PATH`, `Installed off PATH`, `Not installed`), local version or
  `version unknown`, `Update available` only for `.updateAvailable`, and a conflict kind
  label when the kind list is non-empty.
- Path buttons: keep `Copy Selected Entry path for <display name>` and the three sibling
  labels from `actionLabel` (`PathActions.swift:52-54`). Hints: `Copies the path text.` and
  `Asks Finder to select this path.`
- Ineligibility and failure feedback stay the existing `reason.reason` and the reveal-missing
  sentence (`PathActions.swift:88-98`, `:123-126`), each an accessibility element.
- Operation sheet: visible title (`Update <name>`, `Uninstall <name>`, `Update Unavailable`,
  `Uninstall Unavailable`, or the result title). Confirm and Cancel hints from M12-E.
- Progress: `Update in progress` or `Uninstall in progress`, plus the registry ID.
- Error banners keep their visible titles (`Rescan Failed`, `Update Check Failed`,
  `Degraded Environment`).
- Settings: each limit is a static text element. No control role.

Unknown is spoken as unknown or omitted. It is never spoken as up to date.

### E.3 Large text, narrow windows, appearance (TD-10)

- Semantic text styles only in new and edited views. Monospaced path and argv text may keep
  `.fontDesign(.monospaced)` or the existing `.font(.system(.caption, design: .monospaced))`
  already in the sheets. Do not add fixed point sizes.
- Safety text, unavailable sentences, and effect text wrap with vertical `fixedSize` and no
  truncating line limit.
- Content minimum 760×480 points via `.frame(minWidth:minHeight:)` on the split view. The
  operation sheets already request a minimum of 640×500 (`UpdateOperationView.swift:58`).
  Leave that. A sheet may be taller than the window minimum; the sheet's own scroll view
  already exists.
- No `preferredColorScheme`. Colors stay the semantic ones already used (`.secondary`,
  `.orange`, `.accentColor`, `.primary`). Do not introduce a new non-semantic palette.
- M12-E does not flip system appearance or the user's text size. Measurement is M12-F.

### E.4 Settings honesty (TD-8)

Delivered facts the window can show without a new preference:

- The catalogue size and the three category counts, from the snapshot.
- Which accepted operations exist, from `acceptedOperations` on the loaded definitions. Today
  the true sentence is `Codex is the only tool with an accepted managed operation: npm Update and npm Uninstall, after ownership verification.`
- The Core reason, quoted, that other tools are detected and not mutation-accepted.
- Whether this session's environment is degraded, from `isDegradedEnvironment`.
- One line: `The window follows the system appearance.`
- Three statements of absence, as sentences, with no switch control:
  - `Agent Lens does not keep a saved inventory between launches.`
  - `Agent Lens does not add a menu-bar item.`
  - `Agent Lens does not schedule update checks.`
- One more: `Agent Lens does not install a command-line tool for you.`

M16 (cached launch, menu bar, opt-in checks) and M17 (bundled CLI link) are not delivered.
A toggle for any of them would be speculative. There is no telemetry, account, or theme
preference to expose (D-003, D-001). Check Updates and Refresh stay toolbar and File-menu
actions, not settings.

The destination exists because the M12 user result names Settings. The surface is truthful
and minimal. It is not deferred.

---

## F. M8 keyboard gate and VoiceOver method

### F.1 What is still open

M8 required standard keyboard focus and activation of both path rows
(`briefs/M8-path-actions.md:44-45` and the native step at `:140-141`). Delivery recorded the
keyboard-only check as unverified (`DECISIONS.md` M8 row; `briefs/README.md` M8 paragraph).
ROADMAP M12 makes it a required gate. A mouse click, an `AXPress`, or a menu command does
not close it. M10-D's click-through used Accessibility actions on the Uninstall buttons
(`walkthroughs/M10-D-implementation.md:145-150`). That method is the precedent for driving
the real app and for saving screenshots plus a transcript. It is not the keyboard evidence.

### F.2 Keyboard-only Copy and Reveal

**Preconditions.**

- OD-M12-1 is yes: the orchestrator may turn Keyboard navigation (Full Keyboard Access) and
  VoiceOver on for the session and restore the previous values afterward.
- Accessibility permission for the orchestrator's driver is already the permission M10-D used.
  If a fresh check shows it off, stop and ask. Do not approve unrelated TCC prompts.
- The debug app is built with `scripts/build-dev-app.py` and launched under the disposable
  public-fixture environment from the M10-D evidence (synthetic HOME, synthetic config and
  cache, strict profile). Copy the accepted launch recipe from that evidence. Do not invent
  a new sandbox.
- The fixture directory contains one regular executable file and one symlink to it, on the
  PATH that the login-shell resolver reports inside that environment. If `debug-env` in that
  environment does not list the fixture directory, stop. Do not fall back to a personal path.
- Clipboard: read the current pasteboard text, restore it at the end, and record that the
  restore happened. The measurement writes only the fixture path.

**Traversal and activation.** No mouse move, no click, and no `AXPress` as the activating
event. `AXUIElement` is used to observe focus and titles. Activation is a keyboard event
(Space on the focused button). Tab order starts at the window. If Tab does not reach buttons
until Keyboard navigation is enabled, enable it, record the previous value, and continue.
That enablement is part of OD-M12-1.

For each of the four controls, in this order: Copy Selected Entry, Reveal Selected Entry,
Copy Resolved Target, Reveal Resolved Target.

1. Tab until the focused element's label equals the `actionLabel` for that control and the
   fixture tool's display name.
2. Read the path text from the same row's accessible value. It is the expected clipboard or
   Finder target.
3. Press Space.
4. Copy: read `NSPasteboard` plain string. It equals the row text, with no `file://` prefix,
   no added quotes, and no trailing newline.
5. Reveal: observe Finder. The selection is that path. The other row's path is not the
   selection. A parent directory is not an acceptable substitute. Finder returns no success
   flag from `activateFileViewerSelecting` (`briefs/M8-path-actions.md:76-78`). The
   observation is the Finder selection via Accessibility, plus a screenshot. If Finder cannot
   be observed, the check is failed, not passed.

Then repeat the focus traversal after a Rescan keyboard command (⌘R) and confirm the four
labels still include the same tool name and the feedback from the previous tool is gone
(`PathActions.swift` identity reset is owned by `ToolDetailView.pathActionRow`).

**Failure.** Any of: mouse or `AXPress` used to activate; focus never lands on one of the
four buttons; clipboard differs from the row; Reveal selects the wrong path or the parent;
only one row works; the menu item was used instead of the focused button; the fixture path
was replaced by a personal path; Keyboard navigation was left on after the run.

**Evidence.** `R/evidence/f/keyboard-actions.txt` listing each focus label, the key sent, the
clipboard read-back, and the Finder selection path. Screenshots of the detail with focus on
each button, and of Finder after each Reveal. A short note of the Keyboard-navigation value
before and after. Hashes of the fixture files before and after, which must match, because
Copy and Reveal do not modify them.

### F.3 VoiceOver spoken checks

**Method.** Turn VoiceOver on (the usual ⌘F5), move with VoiceOver navigation
(Control-Option and the arrow keys) rather than with a click, and capture the caption panel
for each stop below. Also write the AX title, description, and help for the same element
into the transcript. The caption is the spoken-check evidence. The AX dump is the supporting
contract from M12-E. An AX dump alone does not pass this gate.

Stops, in order:

1. A category list row for an installed tool, and a row for a not-installed tool.
2. An Updates row, if one exists in the fixture. If none exists, record that the empty
   Updates copy was spoken, and do not treat a missing row as a failure.
3. The tool detail title, the update status line when the status is unknown (must include
   unknown or `—`, and must not include "up to date"), and one unavailable sentence.
4. Both path buttons on both rows, including the hints.
5. The Update or Uninstall sheet opened through the Tool menu chord, then Cancel, for a
   fixture package that is eligible. If the fixture package is not eligible, open the
   unavailable state instead and record the Core message. Do not confirm a mutation in this
   spoken pass. The mutation journey is a separate G row and uses the disposable npm
   fixture.
6. A failed-rescan banner, produced by the existing failure injection the test suite already
   has, observed in the app only if the orchestrator can surface it without a personal
   install. If that banner cannot be produced in the real fixture app, the AX contract test
   from the view-model failure value is recorded and the spoken banner stays an open limit.
   Do not invent a fault in the user's shell to force it.

**Failure.** Caption missing the tool name; a path button spoken only as "button"; unknown
spoken as up to date; Uninstall's default spoken action is the destructive button; a
settings control is spoken as a switch; VoiceOver left on after the run.

**Evidence.** Caption screenshots, `R/evidence/f/voiceover-transcript.txt`, and the before/
after note that VoiceOver is off.

### F.4 Large text and appearance measurement

- Narrow window: resize the real debug app to the 760×480 minimum with Accessibility or the
  window frame API. Screenshot Overview, a detail with a long fixture path, and an operation
  sheet. Pass when the unavailable or effect text is fully present in the AX value, not only
  when the pixels look wrapped.
- Large text: do not change the user's global text size. Host the shipping Overview,
  detail, and sheet views in a throwaway `NSHostingView` with
  `.environment(\.dynamicTypeSize, .accessibility5)`, the same offscreen-host idea as M10-D
  (`walkthroughs/M10-D-implementation.md:133-139`). Read the AX values. Pass when safety
  sentences are complete. Label this as layout evidence. If OD-M12-1 also allows a temporary
  system text-size change, one real-app screenshot may be added and the previous size must
  be restored. Absence of that extra screenshot does not fail the gate when the offscreen
  AX proof passed.
- Light and dark: under OD-M12-1, set the app's appearance for the session, screenshot
  Overview and a detail in both, and restore. Pass when text is present in both shots and
  the app did not set `preferredColorScheme`. If appearance cannot be toggled, record the
  gate as unverified. Do not mark it passed from a single-appearance run.

### F.5 TCC prerequisites

- Accessibility for the driver (already granted for M10-D; re-check, do not assume a new
  terminal inherits it).
- Keyboard navigation, VoiceOver, and appearance toggles only after OD-M12-1, each restored.
- No Screen Recording grant is required for AX text. Screenshots that use a screen capture
  may need it. If capture is refused, the AX transcript still has to be written, and the
  missing images are a limit, not a silent pass.
- No Automation prompt beyond System Events keystrokes. Refuse any prompt that is not the
  one the orchestrator just initiated.

---

## G. Acceptance strategy

### G.1 Per-phase gates

Each of A–E runs the preamble commands in B: full `swift test --no-parallel` (plugin-path
rerun only if the TestingMacros failure appears), `swift build`, both import-guard
invocations, guard behavioral fixtures (floor 21), fresh debug app, packaging (floor 9),
`git diff --check`, and an allow-list review. The orchestrator reruns those commands. The
implementer's log is evidence to inspect (D-014).

Phase-specific observations:

- A: the new view-model and presentation tests, including the invalidation table in C.5.
- B: read-only destination spot-check.
- C: conflict navigation spot-check, or an explicit "no live conflict" limit plus the unit
  fixtures.
- D: M11-B style read-only mutation-surface spot-check, plus the existing M10 fixture scripts
  unedited.
- E: AX label dump and the menu-item review (no confirm calls).

Floors move only at combined acceptance, only upward, only to counts the orchestrator
measured at the candidate SHA. The implementer does not edit `.github/workflows/ci.yml`.

### G.2 Combined M12 gate

On the frozen candidate SHA, the orchestrator:

1. Reruns the full local suite, both guards, guard fixtures, debug app, and packaging.
2. Records Core and AppSupport counts separately when the local runner prints two summaries,
   and the combined total when hosted CI prints one (`ci.yml:162-166`).
3. Raises `ci.yml` floors only if the measured counts are higher. Never lowers 467, 80, 547,
   21, or 9. Anchor names in `ci.yml:169-177` stay. A floor edit is a separate orchestrator
   commit after the recount, not hidden inside a feature diff.
4. Pushes nothing until the owner authorizes a PR. This proposal does not authorize the PR
   or the merge. The council brief says the orchestrator opens the PR after acceptance and
   the owner decides the merge.
5. Hosted CI must be green at that exact SHA, all seven gates
   (`ci.yml` gate list around `:585-586`: guard, guard-fixtures, swift-build, isolation-gate,
   full-test-suite, build-dev-app, packaging).

Protected-file manifest: hash every file outside the union of A–E allow-lists plus the
orchestrator's floor commit. `Sources/AgentLensCore/**`, `Sources/agent-lens/**`,
`Package.swift`, `Tests/Fixtures/**`, `docs/capability-matrix.md`, and historical briefs
must match the M12 base except for the floor file in the orchestrator commit.

### G.3 Actual-app journey matrix

All mutation rows use `Tests/Fixtures/M10C/npm_update_acceptance.py` and
`Tests/Fixtures/M10D/npm_uninstall_acceptance.py` in a disposable prefix. No personal
installation is a target. Cancel rows keep the prefix hash unchanged, as M10-D did.

| ID | Journey | Pass |
|---|---|---|
| J1 | Find/filter. Search inside AI Agents, then open Updates. | The agent list filters by the existing predicate. Updates shows only `.updateAvailable`. An unknown tool is absent. |
| J2 | Inspect competing copies. From Overview, `Show PATH evidence` on a conflict fixture, or the unit-fixture proof plus a live "none observed" limit. | Diagnostics shows that tool's candidates and versions. Overview does not contain a second candidate table. |
| J3 | Confirm an eligible npm update in the disposable prefix. | Preview registry ID, package, and prefix match the fixture. Progress region shows that same registry ID. Result shows output and the reconciliation. After dismiss, the detail version matches the post-rescan snapshot. |
| J4 | Cancel an eligible npm update, then cancel an eligible uninstall. | Prefix hashes unchanged. Sheet dismissed. No second operation started. |
| J5 | Confirm an eligible uninstall in the disposable prefix. | Result state, exit status, and install-state delta match the M10-D shape (`notInstalled`, package directory gone). Shipping CLI `scan` in that same environment agrees. CLI gains no mutation syntax. |
| J6 | Retarget attempt. Prepare a preview, then change search, category, and selection. | The pending sheet disappears or stays on the original preview until invalidation clears it. It never shows the other tool's package. An in-flight operation is not cancelled by the scope change and its result stays bound to the original registry ID. |
| J7 | Empty inventory. | Existing empty copy (`ToolListView.swift:71-75`) when the snapshot has no definitions. A normal 14-entry registry is not emptied to test this. Use the test seam. |
| J8 | Offline / unknown latest. | Local rows still render. Unknown is an em dash and is absent from the Updates list and the update count. |
| J9 | Failed rescan. | Existing freshness banner. The previous snapshot remains. |
| J10 | Missing manager. | Core `managerUnavailable` message on the sheet when the fixture PATH has no npm. No mutation. |
| J11 | Permission denial / unverified ownership. | Uninstall shows the verification sentence. Prepare is not offered. No process against a personal prefix. |
| J12 | Long paths. | A fixture path with spaces is fully present in the AX value at the 760-point width and in the large-text host. |
| J13 | Keyboard-only. | F.2 transcript. |
| J14 | VoiceOver. | F.3 caption transcript. |
| J15 | Unaccepted tool. | Core `operationNotAccepted` message, no button, for an npm-declared tool that is not `codex`. Formula and cask sentences for a tool that declares them. |

J3 and J5 are the destructive rows. They run only in the disposable prefix. J4 proves Cancel
on that same prefix before any confirm.

### G.4 What is not an acceptance target

- A personal Homebrew, npm, or standalone installation.
- Promoting any non-`codex` tool into `acceptedOperations`.
- A new manager adapter, a CLI mutation command, or a settings toggle.
- Hosted CI on a moving branch tip. The SHA is frozen first.
- The implementer's own PASS.
- An `AXPress` or mouse click offered as the M8 keyboard result.
- An offscreen render offered as the only proof of the real-app journey. Offscreen is the
  large-text layout evidence and a supplement, which is how M10-D treated it
  (`walkthroughs/M10-D-implementation.md:139-160`).

---

## H. Risks, owner decisions, frozen technical decisions

### H.1 Ranked risks

1. **Confirmation retargeting.** Highest. A view that binds the sheet to `selectedEntry`, or
   a scope change that re-prepares, would mutate the wrong package. Mitigation: TD-4 tests in
   A, sheet bindings called out in B and D, mandatory review on A, D, and E.
2. **Flash-tier ambiguity.** The implementer will invent a shortcut or a second conflict
   count if the brief is soft. Mitigation: TD-1…TD-12 are closed, and each phase says stop
   rather than improvise.
3. **Keyboard measurement is not a click-through.** Reusing M10-D `AXPress` would falsely
   close M8. Mitigation: F.2 forbids `AXPress` as the activation and requires clipboard and
   Finder observation.
4. **Fixture PATH versus the login shell.** The real app resolves the login shell (D-005).
   A fixture bin that is only in the parent process environment will not appear. Mitigation:
   F stops and reports. It does not use a personal tool.
5. **Accessibility regression.** New sidebar and sheets can drop labels or steal ⌘C.
   Mitigation: E's label list, F's captions, and the ⌘C prohibition.
6. **Scope creep into M13–M16.** Formula sentences can turn into brew buttons, and Settings
   can grow toggles. Mitigation: TD-6 forbids command names for unshipped managers. TD-8
   forbids toggles. Allow-lists exclude Core operations.
7. **CI integrity.** Lowering a floor or editing the guard to make AppSupport "pass" would
   hide a regression. Mitigation: the implementer cannot edit `.github/` or `scripts/`. The
   extra AppSupport import check is a command-line `--source-root`, not a script change.
8. **Native measurement feasibility.** VoiceOver captions and Finder selection can be refused
   by TCC, or Keyboard navigation may be off. Mitigation: OD-M12-1 is an explicit permission.
   A refused permission leaves F open. It is not recorded as a pass.
9. **Initializer drift.** M10-D's Python host constructs `UninstallOperationView` with the
   current initializer. Adding a parameter breaks a protected fixture. Mitigation: D forbids
   initializer changes.
10. **Overview search as a second inventory.** If Overview lists all 14 tools and also has
    category lists, the two can disagree. Mitigation: TD-1. Overview is tiles plus conflicts,
    and a query shows matches that navigate into the category scope.

### H.2 Owner decisions

**OD-M12-1.** May the orchestrator, during M12-F only, turn on Keyboard navigation and
VoiceOver, and toggle appearance (and, optionally, a larger system text size), restoring each
previous value before finishing?

Recommendation: yes. Without it, F.2 and F.3 cannot pass, and M12 cannot be accepted.
M12-A through M12-E do not need this permission and can be dispatched while it is open.
Default if the owner has not answered by F: do not toggle anything, leave F open, and do not
treat AX-only dumps as a VoiceOver pass.

**OD-M12-2.** Scope §7 named bare keys U, R, and S, and ⌘K. This plan does not bind them
(E.1).

Recommendation: accept that decline. The chords in E.1 prepare an operation and never confirm
it. A command palette would be new scope. This is not a dispatch blocker. If the owner objects
before the plan is frozen, the orchestrator stops E and revises the shortcut table. The
implementer does not choose a third table.

No other owner decision is required to dispatch M12. The optional diagnostic beta (ROADMAP §7)
is not an M12 question. License is already MIT (D-023). Merge of M11 and of M12 stays with
the owner and is not requested here.

### H.3 Frozen technical decisions

- **TD-1.** Seven destinations, with `listScope` orthogonal to `detailPane`, as in C.1.
  Overview is a summary, not the unfiltered inventory. Diagnostics and Settings do not change
  `listScope`.
- **TD-2.** `filteredEntries` applies `listScope`, then the current `matches` predicate, in
  registry order. Search fields do not grow.
- **TD-3.** Conflict kinds are shadowed copies (`shadowedInstallationCount > 0`), off-PATH
  selection, and inconsistent selection, in that order. Aliases and repeated PATH slots are
  not kinds. The conflict count counts tools.
- **TD-4.** Pending previews invalidate on `listScope`, `searchText`, and selection-ID
  changes, via the existing `invalidatePendingUpdate`. `detailPane` does not invalidate.
  Executing mutations are not cancelled by those changes. Sheets bind to the preview, not to
  `selectedEntry`.
- **TD-5.** `showPathEvidence(id)` selects that ID and sets `detailPane` to `.diagnostics`.
  The existing `DiagnosticsView` is the only per-candidate surface.
- **TD-6.** `ManagementPresentation` as specified in D.3. `codex` button predicates and Core
  reason strings stay. Unshipped managers are sentences, not buttons, and the sentences do
  not name unshipped commands.
- **TD-7.** Sidebar badges: category installed counts, Updates = `updateAvailableCount`,
  Overview = conflict-tool count, Diagnostics and Settings unlabeled. Unknown never increments
  an update badge.
- **TD-8.** Settings is the read-only surface in E.4. No toggles. No second settings window.
- **TD-9.** Shortcut and menu table in E.1. No bare U/R/S, no ⌘K, no ⌘C override, no menu
  item that confirms a mutation.
- **TD-10.** Semantic text, wrapping safety copy, 760×480 content minimum, system appearance.
  No `preferredColorScheme`. No `windowResizability` unless a later revision cites Apple
  documentation that the API is available on macOS 14. This proposal did not verify that.
- **TD-11.** In-sheet progress uses `isExecuting` and the existing preview. No new outcome
  state, no stdout subscription, no initializer change.
- **TD-12.** Path actions keep `PathActionDispatcher` behavior. Menu items are an additional
  way to call it. The M8 gate is the focused buttons, not the menu.

### H.4 Unresolved, and why

- The exact M10-D launch argv was not in the walkthrough section that was read. F copies it
  from the accepted evidence at measurement time. Guessing an argv would risk the personal
  home directory.
- Whether the live machine currently has a multi-install conflict was not scanned. C allows
  a recorded "none observed" plus unit fixtures. A personal second install is not created
  to make the screenshot prettier.
- The fresh test count is the CI floor until the orchestrator reruns the suite.
- `windowResizability` on macOS 14 remains unverified and unused.

---

## I. Explicit non-goals

Binding for every phase:

- No new manager mutation adapters (M13–M15) and no per-tool mutation promotions.
- No cached launch, menu bar, or opt-in periodic checks (M16).
- No bundled CLI install (M17) and no CLI mutation syntax (D-022).
- No release, signing, notarization, or publication (M18–M19).
- No registry, schema, or detector changes. No capability-matrix edit.
- No new dependencies. `Package.swift` stays untouched.
- No speculative Settings toggles and no command palette.
- No public contribution invitation.
- No personal installation as an acceptance target.
- No update-all, no remove-all, no shell-interpolated commands, no automatic retry, no
  claimed rollback.
- No product fixture mode and no launch argument that forces text size or appearance.
- No edit to historical briefs, walkthroughs, `DECISIONS.md`, or `ROADMAP.md` by the
  implementer. The orchestrator records acceptance separately, after the gate.

---

## Dispatch order

M12-A → review → M12-B → M12-C → M12-D → review → M12-E → review → M12-F (orchestrator,
after OD-M12-1) → combined hosted gate at the frozen SHA → owner PR decision.

A, D, and E require both standing independent reviewers. B and C require orchestrator
acceptance, and they stop if their diff enters the view model or the operation views.
F's reviewers read the measurement. They do not re-run the disposable npm mutation.
