# M12-C acceptance — conflict summary + Updates status filter

Date: 2026-11-13. Orchestrator: Qoder (Herdr `t7x`). Milestone branch: `milestone/m12-workflow`.
**Accepted candidate: `e66872d`.** Phase M12-C of `briefs/M12-plan.md`; dispatch brief
`briefs/M12-C-conflict-summary.md`; binding rulings R2/R3/R14 (and R1/R12/R16).

**Decision: M12-C is TECHNICALLY ACCEPTED** by orchestrator acceptance + native spot-check (R15:
App-only phase; the diff calls A's locked `showPathEvidence` but does not change it or
`invalidatePendingUpdate` — no AppSupport diff — so no independent council review is required). The
orchestrator independently reran every gate (D-014) and observed the real app.

## Orchestrator gate results (D-014, independent rerun)

Fresh scratch `agent-lens-m12-c-orch`, `swift test --no-parallel` + CLT TestingMacros flag:

- Full suite: **467 Core + 119 AppSupport = 586 passed, zero skips/failures**, exit 0.
- Core/UI import guard clean (32 Core files); AppSupport import guard clean (6 files).
- Guard behavioral fixtures 21 OK; packaging 9 OK; dev app built; `git diff --check` clean.
- Diff inside the allow-list: `ConflictSummaryView.swift` (new), `OverviewView.swift`,
  `ToolListView.swift`, `MainWindow.swift`, `DiagnosticsView.swift` (empty-copy line only), worker
  report. **No AppSupport/Core/CLI/registry/Package/scripts/.github diff.**

## Native spot-check (orchestrator-observed, real debug app, read-only)

Screenshots: `agent-lens-m12-c-orch/evidence/native/` (overview-conflicts, cline-diagnostics,
updates-filter, updates-filtered). Observations:

- **Conflict summary** in Overview: heading "Conflicts" + count 4; four live conflict tools — Codex
  (Shadowed copy, copy count 2), Cline CLI (Shadowed copy, 3), Oh My Pi (Shadowed copy, 2), DeepSeek
  Harness (Shadowed copy, 2). Each row shows kind labels, copy count, measured versions, and a
  "Show PATH evidence for <tool>" button. Row accessibility label: "Codex, conflict: Shadowed copy,
  copy count 2". No personal conflict was manufactured — these are real shadowed copies on this
  machine.
- **Show PATH evidence navigation**: activating "Show PATH evidence for Cline CLI" selected Cline CLI
  and switched the detail to the existing `DiagnosticsView` (Selection Status section). No second
  candidate table; the evidence is the existing per-tool view (R14/TD-5).
- **Updates status filter**: the Updates destination shows an "Update status" segmented control with
  exactly five options (All / Update available / Up to date / Unknown / Not checked). The default
  `.all` lists installed entries (Codex, OpenCode, Grok CLI, …); selecting "Update available" narrows
  to the truthful empty state "No verified updates. Check Updates reads supported latest versions.
  Unknown stays unknown." (no check has run, so no update-available rows). The badge stays the global
  `updateAvailableCount` (0), unaffected by the filter.
- **Selection persistence**: the detail kept Cline CLI selected after the filter change (R1).
- Diagnostics empty-selection copy is now "Select a tool to view its PATH diagnostics."

## Requirement-to-evidence

| Ruling | Evidence |
|---|---|
| R3 three conflict kinds, measured versions, count counts tools, no aliases/repeated-slots | `ConflictSummaryView` from `ToolConflict`; native spot-check (4 live tools); A's classification tests |
| R14 conflict summary in Overview only; Show PATH evidence → existing DiagnosticsView | `OverviewView` placement; `MainWindow.onShowPathEvidence` → `showPathEvidence`; native navigation observed |
| R2 Updates five-option status filter; unknown neutral; counts global | `ToolListView.updatesFilterBar` bound to `updateStatusFilter`; native filter narrowing observed |
| R12 zero Core/AppSupport change | protected manifest; import guards; Core 467 / AppSupport 119 unchanged |

## Limitations (honest)

- App layer has no automated test surface; the native spot-check is the App evidence (M11-B precedent).
- `localVersions` is a flat measured list (A's exposure); the row shows no per-copy attribution (R3 as
  written; INFO-2 from A's reviews).
- Live off-PATH tools would show `.offPathCopy` alone (Core sets shadowed 0 for off-PATH); the
  observed live conflicts are all shadowed copies.

## Owner authorizations

M12-D dispatch proceeds under the owner's pre-authorized flow. Merge to `main` is NOT authorized.
OD-M12-1 remains the one open owner gate (blocks M12-F only). No release.

## Evidence index

`R = $HOME/.hermes/cache/scratch/agent-lens-m12-c-orch`: `evidence/` (gate logs), `evidence/native/`
(conflict/diagnostics/updates screenshots). Worker report: `walkthroughs/M12-C-implementation.md`.