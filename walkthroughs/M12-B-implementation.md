# M12-B implementation — WORKER EVIDENCE (not acceptance)

**This document is worker evidence, not acceptance.** The orchestrator reruns every gate and
performs the read-only native spot-check independently (D-014). Phase M12-B (seven-destination
navigation shell + Overview + Settings + row details) of milestone M12, implemented against the
frozen dispatch brief `briefs/M12-B-navigation-shell.md` and judgment rulings R1/R7/R14 (plus
R12/R16).

- Base: `bf0b832` (M12-A accepted tip). Dispatch-brief commit `47ed9b2`; branch
  `milestone/m12-workflow`.
- Candidate state: **uncommitted working tree** on top of `47ed9b2`. No stage/commit/branch/reset/
  merge/push was performed.
- `Sources/AgentLensAppSupport/**` is untouched (the M12-A model is frozen and consumed as-is).
- Evidence root: `$HOME/.hermes/cache/scratch/agent-lens-m12-b` (outside the repository).

## 1. What was built

| File | Change | Contract |
|---|---|---|
| `Sources/AgentLensApp/MainWindow.swift` | modified | seven raw-value destinations; destination → `listScope`/`detailPane` writes; sidebar badges; toolbar conflict count; content/detail routing |
| `Sources/AgentLensApp/ToolListView.swift` | modified | shared `InventoryEmptyStateView`; row local version, `Source:` fact, declared packages; Updates tri-state cell; extended accessibility label |
| `Sources/AgentLensApp/OverviewView.swift` | new | summary tiles, degraded banner, search-match navigation, shared empty/loading/failed states; M12-C conflict-section placement marked, not built |
| `Sources/AgentLensApp/SettingsView.swift` | new | read-only truthful Settings surface; no control of any kind |
| `walkthroughs/M12-B-implementation.md` | new | this worker report |

No AppSupport/Core/CLI/registry/`Package.swift`/scripts/`.github`/fixture change. No new
dependency. Operation sheets and every operation view are untouched.

### Destination table as implemented

| Destination (raw value) | `listScope` write | `detailPane` write | Content | Detail |
|---|---|---|---|---|
| Overview | `.all` | `.tool` | `OverviewView` | `ToolDetailView` |
| AI Agents | `.category(.aiAgent)` | `.tool` | `ToolListView` | `ToolDetailView` |
| AI Coding Tools | `.category(.aiCodingTool)` | `.tool` | `ToolListView` | `ToolDetailView` |
| AI Harnesses | `.category(.aiHarness)` | `.tool` | `ToolListView` | `ToolDetailView` |
| Updates | `.updates` | `.tool` | `ToolListView` (tri-state cells) | `ToolDetailView` |
| Diagnostics | unchanged | `.diagnostics` | `ToolListView` (current membership) | `DiagnosticsView` |
| Settings | unchanged | `.settings` | static one-sentence pane | `SettingsView` |

- Writes happen on `.onChange(of: selectedDestination)` and once on `.onAppear`; the launch
  destination is Overview, so the appear write is value-identical and the ViewModel's
  compare-before-release hooks do not invalidate anything.
- The App never calls `invalidatePendingUpdate`, never re-prepares, and never binds a sheet to
  `selectedEntry`. Sheets keep the accepted `preview`/`preparation` bindings.
- Diagnostics and Settings deliberately do not write `listScope` (R1: a pure pane switch neither
  retargets nor releases).

### Overview (R14)

- Tiles: known, installed, off-PATH (`snapshot?.offPathToolCount ?? 0`), update-available, conflict
  tools (`snapshot?.conflictToolCount ?? 0`). Tiles are not buttons and a zero renders `0`.
- Degraded-environment banner reuses the accepted detail-view sentence.
- A non-empty search shows `model.filteredEntries` (scope `.all`, registry order) as rows with no
  prepare control; choosing a row sets the sidebar destination to that entry's category and selects
  its registry ID. The destination write performs the scope change through the ViewModel's R1 hook.
- No all-tools table. The conflict-summary section is marked by a comment for M12-C and not built.
- Empty / loading / failed states reuse the list's copy through the new shared
  `InventoryEmptyStateView` (extracted from `ToolListView`'s previous private view; identical copy).

### Settings (R7)

Static text only: catalogue size and the three category definition counts; the accepted-operation
statement; `NpmUpdateUnavailableReason.operationNotAccepted.message` read from Core; the
degraded-environment note when applicable; "The window follows the system appearance."; and the four
absence statements. No `Toggle`, no bindable preference, no `preferredColorScheme`, no second
`Settings` scene. The content column is the static sentence "Settings apply to this window. There
are no preferences to turn on."

### Rows

Under the executable name: the local version or `—`; `Source: <heuristic>` for an installed tool
(`—` when not installed/no observation); each declared package as `manager label: name`. The install
badge is unchanged. The update badge remains only for `.updateAvailable` everywhere.

Updates destination tri-state: the brief's destination table requires tri-state cells while the row
contract forbids an update badge for any non-available state, so Updates rows show a neutral text
cell for `upToDate` / `unknown` / not-checked (`Up to date` / `Unknown` / `Not checked`) and keep the
existing badge for `updateAvailable`. Unknown therefore never reads as current and never gains an
update affordance.

Accessibility label keeps the accepted parts and adds the category label, `version <n>` or
`version unknown`, and the conflict kind labels when non-empty. Unknown adds neither "up to date"
nor "update available".

## 2. Counts

| Target | Baseline | Candidate | Gate |
|---|---|---|---|
| `AgentLensCoreTests` | 467 | 467 | unchanged |
| `AgentLensAppSupportTests` | 119 | 119 | unchanged (no AppSupport edit) |
| Total | 586 | 586 | unchanged |
| Guard fixtures | 21 | 21 | unchanged |
| Packaging checks | 9 | 9 | unchanged |

## 3. Acceptance commands and raw evidence

All commands ran from the repository root with `R="$HOME/.hermes/cache/scratch/agent-lens-m12-b"`,
`$R/tmp` as TMPDIR, and a fresh `$R/full-suite` scratch. Runner: `$R/run-acceptance.sh`; raw argv +
stdout/stderr + exit code + duration in `$R/evidence/<name>.{log,meta}`.

| Command | Exit | Duration | Raw log |
|---|---|---|---|
| `env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS swift build` | 0 | 1s | `build.log` |
| full suite (fresh scratch, `--no-parallel`, CLT plugin flag) | 0 | 155s | `full-suite.log` |
| `python3 scripts/check-core-ui-imports.py` | 0 | 0s | `guard-core.log` |
| `python3 scripts/check-core-ui-imports.py --source-root Sources/AgentLensAppSupport` | 0 | 0s | `guard-appsupport.log` |
| `python3 Tests/Packaging/test_core_ui_imports.py` | 0 | 1s | `guard-fixtures.log` |
| `python3 scripts/build-dev-app.py --scratch-root "$R/dev-app" --configuration debug` | 0 | 26s | `dev-app.log` |
| `python3 Tests/Packaging/test_dev_app_bundle.py --app "$R/dev-app/AgentLensApp-debug.app"` | 0 | 2s | `packaging.log` |
| `git diff --check` | 0 | — | `diff-check.log` |

Observed results (worker run; orchestrator will rerun and spot-check):

- `full-suite.log`: `✔ Test run with 467 tests in 0 suites passed` (Core) and
  `✔ Test run with 119 tests in 5 suites passed` (AppSupport); no failure, no skip, no issue line.
- `guard-core.log`: `32 Swift file(s) under Sources/AgentLensCore; no SwiftUI/AppKit imports`.
- `guard-appsupport.log`: `6 Swift file(s) under Sources/AgentLensAppSupport; no SwiftUI/AppKit imports`.
- `guard-fixtures.log`: `Ran 21 tests ... OK`. `packaging.log`: `Ran 9 tests ... OK`.
- `dev-app.log`: `Build complete!` and `$R/dev-app/AgentLensApp-debug.app`.

## 4. Changed-file hashes and protected manifest

`evidence/changed-files.sha256` and the manifests vs base `bf0b832` and vs HEAD `47ed9b2` were
regenerated at the candidate. Result: only the two allow-listed modified files differ in the tracked
manifest; the only untracked additions are the two allow-listed new views plus this report. The only
committed delta `bf0b832..HEAD` is `briefs/M12-B-navigation-shell.md` (orchestrator dispatch-brief
commit `47ed9b2`), not an implementer change.

Candidate SHA-256 (`evidence/changed-files.sha256`):

```text
d21eac44f42746ccb032ae1174077cdd7a92184cb0d55deeb89567dff201e30a  Sources/AgentLensApp/MainWindow.swift
dfdb6cc406d1f6d5b80eeecae89fd8e67faad22584f3e9e01476cd538226dd3d  Sources/AgentLensApp/ToolListView.swift
7bb488ab40e1534911b56efc76ae5bdbc4f3bec718be06cae3f76d6e0a49e03d  Sources/AgentLensApp/OverviewView.swift
ed5b02ead962339d377286bc9e5aff611d9cc1ac34b428bd98dc3993c9baede1  Sources/AgentLensApp/SettingsView.swift
```

This report's own SHA-256 is recorded in the same evidence file after the report's final write.

## 5. Stop-condition audit

- No ViewModel fact was missing; AppSupport was not edited (frozen).
- No destination change binds a sheet to selection; sheet bindings are byte-identical in intent to
  the accepted ones.
- No operation view, Core file, CLI, registry, test, script, or packaging file was edited.
- Design choices: (a) Updates tri-state cells are neutral text, badge unchanged for
  `updateAvailable` (resolves the brief's "tri-state cells" against "update badge only for
  `.updateAvailable`"); (b) the list's empty/loading/failed copy is shared via
  `InventoryEmptyStateView` instead of duplicated; (c) Settings category counts are definition
  counts (catalogue), matching "catalogue size + the three category counts"; (d) category/Overview
  badges derive from published `entries` in the App, exactly as R7 permits.

## 6. Unverified / unobserved

- No native app launch or visual spot-check was performed by the worker; the brief assigns that to
  the orchestrator. The app layer has no automated test target, so the acceptance evidence here is
  build/test/guard/packaging only.
- The conflict-summary section is intentionally not built (M12-C).
- Review/acceptance is not claimed.
