# M12-B dispatch brief — seven-destination shell + Overview + Settings + row details

Status: **FROZEN dispatch brief.** Implementer receives ONLY this brief (not the scope document).
Authority: `briefs/M12-plan.md` §5 M12-B and `briefs/M12-planning/judgment.md` rulings R1/R7/R14
(binding). M12-A is accepted at `bf0b832`; the AppSupport presentation model it built is FROZEN —
this phase wires the UI to it and must not change it.

```text
MILESTONE:   M12 — complete native diagnostic and operation workflow
PHASE:       M12-B — seven-destination navigation shell + Overview + Settings + row details
BASE:        bf0b832 (milestone/m12-workflow; M12-A accepted tip). Product base 0589fac.
BRANCH:      milestone/m12-workflow (already checked out; do NOT switch/rebase/branch)
WORKER:      DeepSeek V4.1 Flash 1017 via OMP (river/deepseek-ai/DeepSeek-V4.1-Flash-1017), max
GOAL:        The window shows seven sidebar destinations (Overview, AI Agents, AI Coding Tools,
             AI Harnesses, Updates, Diagnostics, Settings) with truthful badges; Overview shows
             summary tiles + the degraded banner; category destinations render filtered lists;
             list rows carry local version, source heuristic, and declared packages; Settings is
             the read-only truthful surface. Operation sheets are UNCHANGED.
```

## 1. Required reading (in this order)

1. `briefs/M12-plan.md` §3 (safety envelope), §4 (rulings), §5 M12-B, §6 (evidence).
2. `briefs/M12-planning/judgment.md` rulings **R1, R7, R14** (full text) and R12/R16.
3. `briefs/M12-A-acceptance.md` — what A built and the forward notes (the model is frozen).
4. `Sources/AgentLensAppSupport/WorkflowPresentation.swift` — `ListScope`, `DetailPane`,
   `UpdateStatusFilter`, `ToolConflict`, `ManagementPresentation` (consume, do not modify).
5. `Sources/AgentLensAppSupport/InventoryViewModel.swift` — the published API you wire to:
   `listScope`, `detailPane`, `updateStatusFilter`, `filteredEntries`, `entries`, `selectedEntry`,
   `selectedRegistryID`, `select(registryID:)`, `showPathEvidence(registryID:)`, `searchText`,
   `knownToolCount`, `installedToolCount`, `updateAvailableCount`, `isDegradedEnvironment`,
   `snapshot?.offPathToolCount`, `snapshot?.conflictToolCount`, `phase`, `isBusy`, the sheet
   presentation flags. Do NOT modify this file.
6. `Sources/AgentLensApp/MainWindow.swift` — the current `NavigationDestination` (2 cases),
   sidebar, content/detail columns, toolbar, sheet bindings (:87-136), lifecycle.
7. `Sources/AgentLensApp/ToolListView.swift` — `.searchable`, `ToolRow`, empty/loading/failed states.
8. `Sources/AgentLensApp/ToolDetailView.swift` and `DiagnosticsView.swift` — the detail views you
   reuse UNCHANGED (do not edit them this phase).
9. `Sources/AgentLensCore/Detection/DetectorMetadata.swift` — `ToolCategory.label`,
   `PackageManager.label` (read for row/badge text).

## 2. FILES — explicit allow-list

Production (modify):
- `Sources/AgentLensApp/MainWindow.swift`
- `Sources/AgentLensApp/ToolListView.swift`

Production (new):
- `Sources/AgentLensApp/OverviewView.swift`
- `Sources/AgentLensApp/SettingsView.swift`

Worker report (new):
- `walkthroughs/M12-B-implementation.md` (labeled WORKER EVIDENCE, not acceptance)

No new test target. No AppSupport test change is expected (A already tests the model). If you believe
a test change is required, STOP and report — it is a deviation signal.

## 3. DO NOT TOUCH (binding — stop and ask, never edit)

`Sources/AgentLensAppSupport/**` (ALL of it — the model is frozen; if a needed fact is missing, STOP
and request an A revision), `Sources/AgentLensCore/**`, `Sources/agent-lens/**`,
`Sources/AgentLensApp/ToolDetailView.swift`, `DiagnosticsView.swift`, `PathActions.swift`,
`OwnershipVerificationView.swift`, `UpdateOperationView.swift`, `UninstallOperationView.swift`,
`AgentLensApp.swift` (menus/commands are M12-E), `Package.swift`, `Tests/**`, `Tests/Fixtures/**`,
`Tests/Packaging/**`, `scripts/**`, `.github/**`, `Resources/**`, `docs/**`, `DECISIONS.md`,
`ROADMAP.md`, `AGENT_LENS_SCOPE.md`, every existing `briefs/**` and `walkthroughs/**` (except the new
worker report). No new dependency. Personal installations, the real Agent Lens cache, and credentials
are out of bounds. If a file outside this allow-list seems necessary, STOP and report — do not edit it.
**If satisfying this brief would require editing `InventoryViewModel.swift` or either operation view,
STOP instead of expanding the phase.**

## 4. Contracts (quote of the binding rulings)

**R1 / R14 — seven destinations, orthogonal scope/pane.** `NavigationDestination` raw values are
EXACTLY: `Overview`, `AI Agents`, `AI Coding Tools`, `AI Harnesses`, `Updates`, `Diagnostics`,
`Settings` (CaseIterable, in that order). The sidebar lists `allCases`. Selecting a destination writes
the ViewModel's `listScope` and `detailPane`:

| Destination | listScope | detailPane | Content column | Detail column |
|---|---|---|---|---|
| Overview | `.all` | `.tool` | `OverviewView` (tiles + degraded banner) | existing `ToolDetailView` |
| AI Agents | `.category(.aiAgent)` | `.tool` | `ToolListView` | existing `ToolDetailView` |
| AI Coding Tools | `.category(.aiCodingTool)` | `.tool` | `ToolListView` | existing `ToolDetailView` |
| AI Harnesses | `.category(.aiHarness)` | `.tool` | `ToolListView` | existing `ToolDetailView` |
| Updates | `.updates` | `.tool` | `ToolListView` (installed entries, tri-state cells) | existing `ToolDetailView` |
| Diagnostics | unchanged | `.diagnostics` | the current scope's list (unchanged membership) | existing `DiagnosticsView` |
| Settings | unchanged | `.settings` | static one-sentence pane | `SettingsView` |

The old `Inventory` destination is REMOVED (replaced by Overview + the three categories). The content
column for a category or Updates is the existing `ToolListView` over `model.filteredEntries` (the
ViewModel already applies scope→filter→search). Do NOT add a second invalidation path: writing
`listScope`/`detailPane`/`searchText` already invalidates through the ViewModel's hooks (R1); the App
must not call `invalidatePendingUpdate` or re-prepare. Sheet bindings stay on
`updatePreview`/`updatePreparation`/`uninstallPreview`/`uninstallPreparation` (MainWindow :87-136),
NEVER on `selectedEntry`. Selection stays by registry ID; a destination switch that does not change
scope or selection keeps the selected ID and any pending preview.

**R14 — Overview is a summary, NOT a second inventory.** `OverviewView` shows summary tiles derived
from the snapshot: known (`knownToolCount`), installed (`installedToolCount`), off-PATH
(`snapshot?.offPathToolCount ?? 0`), update-available (`updateAvailableCount`), conflict-tool count
(`snapshot?.conflictToolCount ?? 0`); plus the degraded-environment banner when
`isDegradedEnvironment`. Tiles are NOT buttons. NO full 14-row all-tools table. The conflict summary
SECTION is M12-C (not this phase) — leave a clean placement for it but do not build it. A non-empty
`searchText` on Overview replaces the tiles with matches from scope `.all` in registry order
(`model.filteredEntries`); choosing a match selects that registry ID and sets `listScope` to the
entry's category (a scope change → invalidation, via the ViewModel). The match list has NO prepare
button. Empty/loading/failed states reuse the list's existing copy when the snapshot is nil or phase
is `.loadingLocal`/`.failed`; a populated snapshot with zero conflicts still shows `0`.

**R7 — badges (all snapshot-derived).** Overview badge = conflict-tool count. Each category badge =
installed count for that category (`installState != .notInstalled`); you may derive this in the App
from `model.entries` filtered by category (a presentation derivation of published snapshot facts —
NOT a Core re-derivation, and NOT an AppSupport edit). Updates badge = global `updateAvailableCount`
(so it cannot drift from the toolbar). Diagnostics and Settings: no badge. A zero badge shows `0`,
never hidden. The toolbar keeps `knownToolCount`, `installedToolCount`, `updateAvailableCount` and
adds the conflict-tool count with the same "only if greater than zero" pattern as the update count.
Unknown never increments an update badge.

**Row details (R14 / plan §5 M12-B).** `ToolRow` adds, under the executable name: the local version
or `—`; the source heuristic prefixed `Source:` (from `diagnostic.detectedTool.source`) or `—`; and
each declared package as `manager label: name` (using `PackageManager.label`). A declaration is not
ownership and a source string is not proof — label them as facts, not verdicts. Rows still show the
install badge and the update badge ONLY for `.updateAvailable`. Preserve the existing row
accessibility label and extend it with category label, local version or "version unknown", and (when
non-empty) conflict kind labels — unknown adds NO "up to date" and NO "update available". Keep the
existing `.searchable` binding to `model.searchText` (one search field, content column).

**R7 — Settings is read-only and truthful (no Toggle, no second scene).** `SettingsView` shows:
catalogue size + the three category counts (from the snapshot); the accepted-operation statement
"Codex is the only tool with an accepted managed operation: npm Update and npm Uninstall, after
ownership verification."; the quoted Core reason other tools are detected and not mutation-accepted
(read `NpmUpdateUnavailableReason.operationNotAccepted.message`); the degraded-environment note when
applicable; "The window follows the system appearance."; and the absence statements as static text:
"Agent Lens does not keep a saved inventory between launches.", "Agent Lens does not add a menu-bar
item.", "Agent Lens does not schedule update checks.", "Agent Lens does not install a command-line
tool for you." NO control that can flip; NO `Toggle`; NO `preferredColorScheme`; NO second SwiftUI
`Settings` scene (the menu item that opens Settings is M12-E). The Settings content pane is the static
sentence "Settings apply to this window. There are no preferences to turn on." with `SettingsView` in
the detail column.

**R12 — zero Core/CLI/registry change; AppSupport frozen.** Core test count stays 467; AppSupport
stays 119 (no AppSupport edit). No new dependency. Semantic text styles; safety text wraps.

## 5. Acceptance (exact commands + expected observable results)

Evidence root (assigned, outside the repo): `R = $HOME/.hermes/cache/scratch/agent-lens-m12-b`.
Run from the repo root, fresh scratch, no toolchain/package change:

```sh
R="$HOME/.hermes/cache/scratch/agent-lens-m12-b"; mkdir -p "$R/tmp" "$R/evidence"
env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS swift build 2>&1 | tee "$R/evidence/build.log"
env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS \
  TMPDIR="$R/tmp" swift test --build-system swiftbuild --scratch-path "$R/full-suite" --no-parallel \
  -Xswiftc -load-plugin-library \
  -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib \
  2>&1 | tee "$R/evidence/full-suite.log"
python3 scripts/check-core-ui-imports.py 2>&1 | tee "$R/evidence/guard-core.log"
python3 scripts/check-core-ui-imports.py --source-root Sources/AgentLensAppSupport 2>&1 | tee "$R/evidence/guard-appsupport.log"
python3 Tests/Packaging/test_core_ui_imports.py 2>&1 | tee "$R/evidence/guard-fixtures.log"
TMPDIR="$R/tmp" python3 scripts/build-dev-app.py --scratch-root "$R/dev-app" --configuration debug 2>&1 | tee "$R/evidence/dev-app.log"
TMPDIR="$R/tmp" python3 Tests/Packaging/test_dev_app_bundle.py --app "$R/dev-app/AgentLensApp-debug.app" 2>&1 | tee "$R/evidence/packaging.log"
git diff --check
```

Expected: every command exit 0; full suite **Core 467 + AppSupport 119 = 586, zero skips/failures**
(no test count change this phase); guard fixtures 21; packaging 9; both import guards clean; dev app
builds. If `swift test` fails before any test with `TestingMacros … plugin not found`, the flag above
is the documented workaround; if the plugin path is unavailable or the failure differs, STOP and
report (do not install/modify tooling, do not switch xcode-select).

The orchestrator performs the read-only native spot-check (the App evidence, since the App layer has
no automated test surface): build the dev app, launch it, and observe — seven sidebar items with the
specified badges; each category destination lists exactly that category's registry IDs; Overview
shows the tiles (no full table); Updates lists installed entries; Settings has no flippable control;
search within a category hides non-matches; a destination switch keeps the selected registry ID;
Diagnostics still renders the existing per-tool evidence. You do NOT perform acceptance; file the
build evidence and let the orchestrator observe the app.

## 6. EVIDENCE (raw, unedited)

Under `$R/evidence`: raw argv + stdout/stderr + exit codes + durations; SHA-256 of every changed file;
a protected-file manifest diff proving ONLY allow-listed files changed (hash every tracked file at
base `bf0b832`, compare at the candidate). Write `walkthroughs/M12-B-implementation.md` labeled WORKER
EVIDENCE: what you built, the counts, the changed-file hashes, the stop-condition audit, and any
unverified/unobserved item (never claimed as passed). The orchestrator reruns every gate and the
native spot-check independently (D-014).

## 7. STOP conditions (stop and report, never improvise)

- A needed ViewModel fact is missing from A (request an A revision; do not edit AppSupport).
- A destination change would retarget a sheet, or you would bind a sheet to `selectedEntry`.
- Satisfying the brief requires editing `InventoryViewModel.swift`, an operation view, or any
  DO-NOT-TOUCH file.
- Any design choice not resolved in this brief or the rulings (R1–R16) — report it, do not decide it.

## 8. DONE WHEN

The acceptance commands pass (orchestrator will rerun + spot-check); the diff is inside the allow-list
with a clean protected manifest; Core 467 / AppSupport 119 unchanged; the worker report + raw evidence
are filed. Then report:

```sh
hc send t7x "M12-B candidate ready: <state> — <Core/AppSupport counts>; <changed files>; <evidence root>; <blocker>"
```

Do NOT stage/commit/branch/reset/merge/push — the orchestrator owns Git delivery. Do NOT start
subagents or other CLIs. Do NOT grade your own work as accepted.