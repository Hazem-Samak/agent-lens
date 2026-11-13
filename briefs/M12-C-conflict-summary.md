# M12-C dispatch brief — conflict summary surface + Updates status filter

Status: **FROZEN dispatch brief.** Implementer receives ONLY this brief (not the scope document).
Authority: `briefs/M12-plan.md` §5 M12-C and `briefs/M12-planning/judgment.md` rulings R2/R3/R14
(binding). M12-A/B are accepted at `834fabf`; the AppSupport model is FROZEN — consume it, do not
change it.

```text
MILESTONE:   M12 — complete native diagnostic and operation workflow
PHASE:       M12-C — conflict summary surface + Updates status filter
BASE:        834fabf (milestone/m12-workflow; M12-B accepted tip). Product base 0589fac.
BRANCH:      milestone/m12-workflow (already checked out; do NOT switch/rebase/branch)
WORKER:      DeepSeek V4.1 Flash 1017 via OMP (river/deepseek-ai/DeepSeek-V4.1-Flash-1017), max
GOAL:        Overview lists each conflict tool (kind labels, copy count, measured local versions)
             and "Show PATH evidence" opens that tool's existing Diagnostics; the Updates
             destination gains the update-status filter control. Diagnostics is not rewritten.
```

## 1. Required reading (in this order)

1. `briefs/M12-plan.md` §3, §4, §5 M12-C, §6.
2. `briefs/M12-planning/judgment.md` rulings **R2, R3, R14** (full text) and R1/R12/R16.
3. `briefs/M12-A-acceptance.md` and `briefs/M12-B-acceptance.md` — forward notes (localVersions is a
   flat measured-version list; live off-PATH is `.offPathCopy` alone; the Updates filter
   scope-conditioning is already pinned by A's R1 test).
4. `Sources/AgentLensAppSupport/WorkflowPresentation.swift` — `ToolConflict` (registryID, displayName,
   kinds, copyCount, localVersions, winnerEntryPath, offPathRoot, inconsistencyReason),
   `ToolConflictKind`, `UpdateStatusFilter`. Consume; do not modify.
5. `Sources/AgentLensAppSupport/InventoryViewModel.swift` — `showPathEvidence(registryID:)`,
   `updateStatusFilter`, `listScope`, `filteredEntries`, `snapshot?.conflictToolCount`, `entries`,
   `select(registryID:)`. Do NOT modify.
6. `Sources/AgentLensApp/OverviewView.swift` — the marked conflict-section placement (between the
   tiles and the absent all-tools content).
7. `Sources/AgentLensApp/ToolListView.swift` — where the Updates status-filter control goes.
8. `Sources/AgentLensApp/DiagnosticsView.swift` — the empty-selection description string (:25-29)
   and the existing per-candidate sections (the ONLY per-candidate surface; do not duplicate them).
9. `Sources/AgentLensApp/MainWindow.swift` — the Overview `onSelectMatch` wiring (for the conflict
   row navigation pattern).

## 2. FILES — explicit allow-list

Production (modify):
- `Sources/AgentLensApp/OverviewView.swift` (render the conflict section)
- `Sources/AgentLensApp/ToolListView.swift` (Updates status-filter control)
- `Sources/AgentLensApp/MainWindow.swift` (invoke `showPathEvidence` from the conflict row ONLY)
- `Sources/AgentLensApp/DiagnosticsView.swift` (empty-selection description string ONLY)

Production (new):
- `Sources/AgentLensApp/ConflictSummaryView.swift`

Worker report (new):
- `walkthroughs/M12-C-implementation.md` (labeled WORKER EVIDENCE, not acceptance)

No new test target. No AppSupport test change expected (A already tests classification/navigation).
If a test change seems required, STOP and report.

## 3. DO NOT TOUCH (binding — stop and ask, never edit)

`Sources/AgentLensAppSupport/**` (frozen — if a needed fact is missing, STOP and request an A
revision), `Sources/AgentLensCore/**`, `Sources/agent-lens/**`,
`Sources/AgentLensApp/ToolDetailView.swift`, `PathActions.swift`, `OwnershipVerificationView.swift`,
`UpdateOperationView.swift`, `UninstallOperationView.swift`, `SettingsView.swift`,
`AgentLensApp.swift`, `Package.swift`, `Tests/**`, `scripts/**`, `.github/**`, `Resources/**`,
`docs/**`, `DECISIONS.md`, `ROADMAP.md`, `AGENT_LENS_SCOPE.md`, every existing `briefs/**` and
`walkthroughs/**` (except the new worker report). No new dependency. Personal installations, the real
Agent Lens cache, and credentials are out of bounds. **Do NOT install a second copy of a personal
tool to manufacture a conflict.** If a file outside the allow-list seems necessary, STOP and report.

## 4. Contracts (quote of the binding rulings)

**R3 — conflict summary content.** `ConflictSummaryView` renders one row per conflict tool from
`ToolConflict(entry:)` over `model.entries` (a tool with no kind is absent). Each row shows: display
name, registry ID, the kind labels in the ruled order (`shadowedCopy` → "Shadowed copy",
`offPathCopy` → "Off PATH", `inconsistentDiagnostics` → "Inconsistent diagnostics" — use clear
plain-language labels), the copy count (`copyCount`), and the measured local versions
(`localVersions`, a flat list; render as a comma-separated list or one per line — do NOT invent
per-copy attribution that A did not expose). For `.winner` show the winner entry path
(`winnerEntryPath`); for `.offPath` show the off-PATH root (`offPathRoot`); for `.inconsistent` show
the stored reason (`inconsistencyReason`) and NO winner path. Aliases and repeated PATH slots are NOT
conflicts and do not appear here (they remain in Diagnostics summary counts). The section heading is
"Conflicts" with the conflict-tool count; an empty state reads "No conflicts detected across the
known tools." The section is rendered in Overview ONLY (R14), at the marked placement.

**R14 / TD-5 — navigation to evidence.** Each conflict row has an action labeled "Show PATH evidence"
that calls `model.showPathEvidence(registryID:)` (A's locked function: selects the ID — invalidating a
pending preview if the ID differs — and sets `detailPane = .diagnostics`). The detail then shows the
EXISTING `DiagnosticsView` (selection status, summary counts, canonical installation versions,
candidates). Do NOT build a second candidate table or copy those sections into Overview. Wire the
action through `MainWindow` (the Overview content closure), mirroring the existing `onSelectMatch`
pattern; the App must not call `invalidatePendingUpdate` or re-prepare.

**R2 — Updates status filter.** The Updates destination (`listScope == .updates`) gains a filter
control (a `Picker`/segmented control) bound to `model.updateStatusFilter` with exactly five options:
"All" (`.all`), "Update available" (`.updateAvailable`), "Up to date" (`.upToDate`), "Unknown"
(`.unknown`), "Not checked" (`.notChecked`). The control appears ONLY in the Updates destination.
Changing it writes `model.updateStatusFilter` (the ViewModel's R1 hook invalidates a pending preview;
the App adds no second invalidation). The list reflects `model.filteredEntries` (scope → filter →
search). Unknown rows render neutral with their typed reason — never "up to date", never counted in
the badge. The Updates empty copy (no installed tools / no check run) stays truthful, e.g. "No
verified updates. Check Updates reads supported latest versions. Unknown stays unknown." Counts stay
snapshot-derived (the badge is the global `updateAvailableCount`, unaffected by the filter).

**Diagnostics empty-selection copy.** Change the empty-selection description string to "Select a tool
to view its PATH diagnostics." (the "No Tool Selected" title stays). No other DiagnosticsView change.

**R12 — zero Core/AppSupport change.** Core 467 / AppSupport 119 unchanged. No new dependency.
Semantic text styles; safety text wraps; conflict rows are accessible (label names the tool + kinds).

## 5. Acceptance (exact commands + expected observable results)

Evidence root: `R = $HOME/.hermes/cache/scratch/agent-lens-m12-c`. Run from the repo root, fresh
scratch, no toolchain/package change:

```sh
R="$HOME/.hermes/cache/scratch/agent-lens-m12-c"; mkdir -p "$R/tmp" "$R/evidence"
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

Expected: every command exit 0; **Core 467 + AppSupport 119 = 586, zero skips/failures**; guard 21;
packaging 9; both import guards clean; dev app builds. (Plugin-flag workaround as in A/B; STOP and
report if the plugin path is unavailable or the failure differs.)

The orchestrator performs the native spot-check: this machine has live conflicts (e.g. Codex shows
"conflict: shadowed copy"), so the conflict summary should list real conflict tools; activating "Show
PATH evidence" lands on Diagnostics for that tool with the existing per-installation evidence; the
Updates filter narrows the list; counts stay global. If no live conflict were present, the unit
fixtures (A) are the classification proof and the spot-check records "no live conflict observed" —
never manufacture one against a personal install. You do NOT perform acceptance.

## 6. EVIDENCE (raw, unedited)

Under `$R/evidence`: raw argv + stdout/stderr + exit codes + durations; SHA-256 of every changed file;
a protected-file manifest diff proving ONLY allow-listed files changed (hash every tracked file at
base `834fabf`, compare at the candidate). Write `walkthroughs/M12-C-implementation.md` labeled WORKER
EVIDENCE: what you built, counts, changed-file hashes, stop-condition audit, unverified/unobserved
items. The orchestrator reruns every gate + the native spot-check independently (D-014).

## 7. STOP conditions (stop and report, never improvise)

- The summary needs a diagnostic field that does not exist (do NOT add it in Core; request an A
  revision if a model fact is missing).
- A needed ViewModel fact is missing from A (do not edit AppSupport).
- You would duplicate the DiagnosticsView candidate sections, or call `invalidatePendingUpdate` /
  re-prepare from the App.
- Any design choice not resolved in this brief or the rulings — report it, do not decide it.

## 8. DONE WHEN

The acceptance commands pass (orchestrator will rerun + spot-check); the diff is inside the allow-list
with a clean protected manifest; Core 467 / AppSupport 119 unchanged; the worker report + raw evidence
are filed. Then report:

```sh
hc send t7x "M12-C candidate ready: <state> — <Core/AppSupport counts>; <changed files>; <evidence root>; <blocker>"
```

Do NOT stage/commit/branch/reset/merge/push — the orchestrator owns Git delivery. Do NOT start
subagents or other CLIs. Do NOT grade your own work as accepted.