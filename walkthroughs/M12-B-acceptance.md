# M12-B acceptance — seven-destination navigation shell

Date: 2026-11-13. Orchestrator: Qoder (Herdr `t7x`). Milestone branch: `milestone/m12-workflow`.
**Accepted candidate: `ea08ad8`.** Phase M12-B of `briefs/M12-plan.md`; dispatch brief
`briefs/M12-B-navigation-shell.md`; binding rulings R1/R7/R14 (and R12/R16).

**Decision: M12-B is TECHNICALLY ACCEPTED** by orchestrator acceptance + native spot-check (R15:
App-only phase, no independent council review required because the diff does not enter the ViewModel
or the operation views). The orchestrator independently reran every gate (D-014) and observed the
real app.

## Orchestrator gate results (D-014, independent rerun)

Fresh scratch `agent-lens-m12-b-orch`, `swift test --no-parallel` + CLT TestingMacros flag:

- Full suite: **467 Core + 119 AppSupport = 586 passed, zero skips/failures**, exit 0 (no test-count
  change — the App layer has no automated test surface; A's model tests are unchanged).
- Core/UI import guard clean (32 Core files); AppSupport import guard clean (6 files).
- Guard behavioral fixtures 21 OK; packaging 9 OK; dev app built; `git diff --check` clean.
- Diff inside the allow-list: `MainWindow.swift`, `ToolListView.swift`, `OverviewView.swift` (new),
  `SettingsView.swift` (new), worker report. **No AppSupport/Core/CLI/registry/Package/scripts/.github
  diff** — the M12-A model is frozen and untouched.

## Native spot-check (orchestrator-observed, real debug app, read-only)

The dev app was launched (it scans the real login shell, local-first, read-only) and driven via
Accessibility + keyboard. Screenshots: `agent-lens-m12-b-orch/evidence/native/` (overview, settings,
diagnostics, category lists). Observations:

- **Seven destinations** in the sidebar in order: Overview, AI Agents, AI Coding Tools, AI Harnesses,
  Updates, Diagnostics, Settings. Badges: Overview = conflict-tool count (4 on this machine); AI
  Agents = 5 installed; AI Coding Tools = 1; AI Harnesses = 3; Updates = 0 (no check run yet);
  Diagnostics/Settings no badge. Zero badges show `0`.
- **Overview** shows summary tiles (Known tools 14, Installed 9, Off PATH 0, Update available 0,
  Conflict tools 4) + the degraded banner when applicable; NO full all-tools table (R14). The detail
  column shows the selected tool (Codex) with the unchanged M8/M9/M10 surface.
- **Category filtering**: AI Coding Tools lists exactly Aider, Goose, Kiro CLI, Qoder; AI Agents lists
  Codex, OpenCode, Grok CLI, … — the scope filter partitions the registry. Not-installed tools remain
  in their category lists (correct).
- **Extended row accessibility labels** observed: "Qoder, qodercli, Installed and on PATH, AI Coding
  Tool, version 1.1.88"; "Aider, aider, Not installed, AI Coding Tool, version unknown"; "Codex, …,
  conflict: shadowed copy" — category, local version (or "version unknown"), and conflict kind are
  spoken; unknown adds no "up to date"/"update available".
- **Settings is read-only**: content pane "Settings apply to this window. There are no preferences to
  turn on."; SettingsView shows Catalogue (14 known; AI Agent 7 / AI Coding Tool 4 / AI Harness 3),
  Managed Operations (codex-only statement + the Core `operationNotAccepted` reason read from the
  enum), Environment ("The window follows the system appearance."), and the four absence statements.
  Every element is `AXStaticText` — NO Toggle, no flippable control, no second Settings scene (R7).
- **Selection persistence**: switching category keeps the selected registry ID (Codex detail persists
  while viewing AI Coding Tools); the detail shows the selected tool regardless of the list scope (R1).
- **Navigation works via keyboard** (arrow keys move the sidebar selection and the content scope
  updates). Toolbar shows "14 known, 9 installed • 4 conflict tools" + Rescan/Check/Refresh + search.
- Light/dark: observed in the system (dark) appearance; semantic colors render correctly.

## Forward note for M12-E (accessibility)

Driving the sidebar rows via the Accessibility `AXPress` action did not change the selection, while
keyboard arrow navigation did. This is a SwiftUI `NavigationSplitView` sidebar characteristic (the row
press action is not wired to selection); a real mouse click selects normally. M12-E owns the full
VoiceOver/keyboard pass and must ensure sidebar destinations are activatable by VoiceOver users
(VO navigation + activate), not only by arrow keys. Recorded here so M12-E addresses it deliberately;
it is not an M12-B blocker (keyboard navigation and the code wiring are correct).

## Requirement-to-evidence

| Ruling | Evidence |
|---|---|
| R1 seven destinations, orthogonal scope/pane, selection persistence, sheets unchanged | `MainWindow.applyDestination`/`contentView`/`detailView`; native spot-check; sheet bindings still on preview/preparation |
| R7 snapshot-derived badges; read-only truthful Settings | `badgeCount`/`installedCount`; `SettingsView` (all static text); native spot-check |
| R14 Overview summary not a second inventory; row details | `OverviewView` tiles (no table); `ToolRow` version/source/packages + extended a11y label; native spot-check |
| R12 zero Core/AppSupport change | protected manifest; import guards; Core 467 / AppSupport 119 unchanged |

## Limitations (honest)

- The App layer has no automated test surface; the native spot-check is the App evidence (M11-B
  precedent). Visual invariance of the operation sheets is inferred from zero diff to those files.
- The conflict summary SECTION is M12-C (not built here); Overview marks its placement.
- The Updates status-filter control is M12-C; Updates currently lists installed entries with tri-state
  cells (default filter `.all`).
- Sidebar `AXPress` activation noted for M12-E (above).

## Owner authorizations

M12-C dispatch proceeds under the owner's pre-authorized flow. Merge to `main` is NOT authorized.
OD-M12-1 remains the one open owner gate (blocks M12-F only). No release.

## Evidence index

`R = $HOME/.hermes/cache/scratch/agent-lens-m12-b-orch`: `evidence/` (build/full-suite/guard/dev-app/
packaging logs), `evidence/native/` (overview/settings/diagnostics/category screenshots). Worker
report: `walkthroughs/M12-B-implementation.md` (worker evidence).