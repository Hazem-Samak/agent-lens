# M12-C implementation — WORKER EVIDENCE (not acceptance)

**This document is worker evidence, not acceptance.** The orchestrator reruns every gate and performs
the native spot-check independently (D-014). Phase M12-C (conflict summary surface + Updates status
filter) of milestone M12, implemented against the frozen dispatch brief
`briefs/M12-C-conflict-summary.md` and judgment rulings R2/R3/R14 (plus R1/R12/R16).

- Base: `834fabf` (M12-B accepted tip). Dispatch-brief commit `054ceaa`; branch
  `milestone/m12-workflow`.
- Candidate state: **uncommitted working tree** on top of `054ceaa`. No stage/commit/branch/reset/
  merge/push was performed.
- `Sources/AgentLensAppSupport/**` is untouched (A/B model frozen and consumed as-is).
- Evidence root: `$HOME/.hermes/cache/scratch/agent-lens-m12-c` (outside the repository).

## 1. What was built

| File | Change | Contract |
|---|---|---|
| `Sources/AgentLensApp/ConflictSummaryView.swift` | new | one row per conflict tool from `ToolConflict(entry:)`: plain-language kinds in the ruled order, copy count, flat measured versions, winner/off-PATH/reason facts, "Show PATH evidence"; empty state |
| `Sources/AgentLensApp/OverviewView.swift` | modified | renders `ConflictSummaryView` at the M12-B marked placement; new evidence closure |
| `Sources/AgentLensApp/MainWindow.swift` | modified | wires the conflict row to `model.showPathEvidence(registryID:)` (destination `.diagnostics` + the locked model call) |
| `Sources/AgentLensApp/ToolListView.swift` | modified | Updates-only segmented `Picker` bound to `model.updateStatusFilter`; truthful Updates empty copy |
| `Sources/AgentLensApp/DiagnosticsView.swift` | modified | empty-selection description string only |
| `walkthroughs/M12-C-implementation.md` | new | this worker report |

No AppSupport/Core/CLI/registry/`Package.swift`/scripts/`.github`/fixture change. No new dependency.
No second candidate table: `DiagnosticsView` remains the only per-candidate surface.

### Conflict summary (R3)

- Built by `model.entries.compactMap { ToolConflict(entry: $0) }`; a tool with no kind is absent.
- Heading "Conflicts" plus the conflict-tool count. Empty state: "No conflicts detected across the
  known tools."
- Per row: display name; registry ID; kind labels in A's ruled order ("Shadowed copy", "Off PATH",
  "Inconsistent diagnostics"); `Copy count: <n>`; `Measured local versions: <flat list>` (`—` when
  no measurement); winner entry path only for `.winner`; off-PATH root only for `.offPath`; stored
  reason only for `.inconsistent` with no winner path. Aliases and repeated PATH slots never appear.
- The row's fact block is one combined accessibility element labelled with the tool and its kinds;
  the "Show PATH evidence" button keeps its own action and an explicitly labelled accessible name.
- Rendered in Overview only, at the M12-B placement. A non-empty Overview search replaces the whole
  summary with match rows (unchanged M12-B behavior).

### Navigation to evidence (R14 / TD-5)

`MainWindow` passes an `onShowPathEvidence` closure into `OverviewView`; activating a row sets the
sidebar destination to Diagnostics and calls `model.showPathEvidence(registryID:)`. The destination
switch is how the accepted M12-B detail routing actually renders `DiagnosticsView`; `showPathEvidence`
itself selects the registry ID (invalidating a pending preview if the ID differs) and sets
`detailPane = .diagnostics`. The App never calls `invalidatePendingUpdate` and never re-prepares.

### Updates status filter (R2)

- A segmented `Picker` with exactly five options in the ruled order: All, Update available, Up to
  date, Unknown, Not checked. It is bound to `model.updateStatusFilter`, so the change flows through
  the ViewModel's R1 invalidation hook; the App adds no second trigger.
- The control is parameterized to the Updates destination (`showsUpdateFilter`), so it appears only
  there — not in a category list and not in Diagnostics even when Diagnostics preserves the Updates
  scope.
- The list is `model.filteredEntries` (scope → filter → search). Unknown rows keep the neutral
  tri-state cell from M12-B and are never counted in the global `updateAvailableCount` badge.
- When Updates has no rows and no search query, the empty copy reads "No verified updates. Check
  Updates reads supported latest versions. Unknown stays unknown."

### Diagnostics

Only the empty-selection description changed to "Select a tool to view its PATH diagnostics."; the
"No Tool Selected" title and every diagnostics section are unchanged.

## 2. Counts

| Target | Baseline | Candidate |
|---|---|---|
| `AgentLensCoreTests` | 467 | 467 |
| `AgentLensAppSupportTests` | 119 | 119 |
| Total | 586 | 586 |
| Guard fixtures | 21 | 21 |
| Packaging checks | 9 | 9 |

## 3. Acceptance commands and raw evidence

Runner: `$R/run-acceptance.sh`; raw argv + stdout/stderr + exit code + duration in
`$R/evidence/<name>.{log,meta}`. `R="$HOME/.hermes/cache/scratch/agent-lens-m12-c"`.

| Command | Exit | Duration | Raw log |
|---|---|---|---|
| `env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS swift build` | 0 | 1s | `build.log` |
| full suite (fresh scratch, `--no-parallel`, CLT plugin flag) | 0 | 117s | `full-suite.log` |
| `python3 scripts/check-core-ui-imports.py` | 0 | 1s | `guard-core.log` |
| `python3 scripts/check-core-ui-imports.py --source-root Sources/AgentLensAppSupport` | 0 | 0s | `guard-appsupport.log` |
| `python3 Tests/Packaging/test_core_ui_imports.py` | 0 | 1s | `guard-fixtures.log` |
| `python3 scripts/build-dev-app.py --scratch-root "$R/dev-app" --configuration debug` | 0 | 24s | `dev-app.log` |
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

`evidence/changed-files.sha256` and the manifests vs base `834fabf` and vs HEAD `054ceaa` were
regenerated at the candidate. Result: only the four allow-listed modified files differ in the tracked
manifest; the only untracked additions are the allow-listed new view plus this report. The only
committed delta `834fabf..HEAD` is `briefs/M12-C-conflict-summary.md` (orchestrator dispatch-brief
commit `054ceaa`), not an implementer change.

Candidate SHA-256 (`evidence/changed-files.sha256`):

```text
cd89c96b13b947191a6e6b1df937ca551d781c41ffd38963ac7f0eb05d661060  Sources/AgentLensApp/DiagnosticsView.swift
50563a10b7670147a8f2da3e2d9929fb1e20323348a0ca3cb98a3d739803ce34  Sources/AgentLensApp/MainWindow.swift
be1ae8a35417328c27397b5669c6b2dfe0db3c4c04f9cb6cca263af25848ec09  Sources/AgentLensApp/OverviewView.swift
49cc4e42f1684b2853a23c2928205be889c589a70eba3a9c1c6d13bb937ceb2e  Sources/AgentLensApp/ToolListView.swift
111b7353509ddc86cdb1a7868e7db8dd524439c2b352c1729fd870620747b16b  Sources/AgentLensApp/ConflictSummaryView.swift
```

This report's own SHA-256 is recorded in the same evidence file after the report's final write.

## 5. Stop-condition audit

- No missing diagnostic field or ViewModel fact; AppSupport was not edited.
- No diagnostics candidate section was duplicated; no `invalidatePendingUpdate`/re-prepare call was
  added in the App.
- No operation view, Core file, CLI, registry, test, script, or packaging file was edited.
- Design notes: (a) the Updates filter is destination-parameterized (`showsUpdateFilter`) so it
  cannot appear in Diagnostics; (b) activating a conflict row switches the sidebar destination to
  Diagnostics in addition to the locked `showPathEvidence` call because M12-B routes the detail
  column by destination — the alternative would be rewriting accepted routing; (c) the Updates
  empty copy is shown only for the Updates destination with no search query (a filtered-empty search
  elsewhere keeps the accepted search copy).

## 6. Unverified / unobserved

- No native app launch or visual spot-check was performed by the worker; the brief assigns that to
  the orchestrator. The App layer has no automated test target, so the worker evidence is
  build/test/guard/packaging only.
- No live conflict was manufactured or inspected by the worker. Classification proof remains A's
  unit fixtures; the native check on this machine observes the real conflict, if any.
- Review/acceptance is not claimed.
