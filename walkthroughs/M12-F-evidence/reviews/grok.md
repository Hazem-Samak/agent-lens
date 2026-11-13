# M12-F R1 independent review — Grok (read-only)

**Candidate:** `255fd9c` (`feat(workflow): M12-F R1 — keyboard focus traversal fix (M8 gate)`) on `milestone/m12-workflow`. Diff base `775d5bc`.
**Contract:** `briefs/M12-plan.md` §5 M12-F; `briefs/M12-planning/judgment.md` R1 and R10; `briefs/M8-path-actions.md` (keyboard activation of the two path rows). Worker evidence: `walkthroughs/M12-F-implementation.md` and `$HOME/.hermes/cache/scratch/agent-lens-m12-f-r1/evidence/`. The worker report is evidence, not acceptance.
**Reviewer:** Grok, independent, read-only. No product, test, brief, or fixture file was edited. No git mutation, no subagent, no build, no test, no fixture. This file is the only write. The orchestrator's green rerun (Core 467 + AppSupport 119 = 586) is the execution record. This review is the `MainWindow.swift` diff plus the cited focus logs.

## Verdict

**PASS** — 0 blocking, 0 high, 0 medium, 1 low, 3 info.

The sidebar is no longer a `List`. Each destination is one `Button`, Tab is not captured by list cells, and the four detail path buttons sit in the forward key order in `focus-traversal-attempt2.log` lines 11–14. Click, arrows, and the VoiceOver action still write only `selectedDestination`, which is the existing `applyDestination` path. Sheets, menus, and C-1 are untouched. One Space log copies `/Users/corvette/.local/bin/codex` after an accessibility set-focus, not after Tab, and the rest of R10 (the other three Spaces, Finder, the disposable fixture) is not in these logs.

## What changed

`git diff 775d5bc..255fd9c` is `Sources/AgentLensApp/MainWindow.swift` plus `walkthroughs/M12-F-implementation.md`. `git diff --check` exits 0. The protected manifest against `775d5bc` diffs only `MainWindow.swift`. No Core, AppSupport, CLI, registry, test, fixture, or script file.

The sidebar `List` / `NavigationLink` / `.listStyle(.sidebar)` is replaced by a `ScrollView` + `VStack` of `sidebarRow` buttons (`MainWindow.swift:341-416`). `FocusState` tracks which row is focused (`:39-43`). Nothing else in the window moved: `applyDestination` (`:256-271`), the sheet bindings (`:96-145`), `commandActions`, and the content/detail switch are absent from the diff.

## Selection, labels, keys

The button action, the `.accessibilityAction`, and `moveSidebarFocus` all assign `selectedDestination` and do not call `invalidatePendingUpdate` (`:372-374`, `:404-406`, `:420-425`). `onChange` still runs `applyDestination`. Scope changes still invalidate only through the ViewModel hook. Diagnostics and Settings still write only `detailPane`. Tab moves `.focused` and does not select, so tabbing the seven rows does not retarget a confirmation. Arrow keys select and move focus together (`:420-425`), which is the old list behavior of arrows, through that same write.

`badgeCount` is unchanged (`:430-444`). `accessibilityLabel(for:)` is unchanged and still applied (`:400`). The traversal log speaks `Overview, 4`, `Updates, 0`, and `Diagnostics` with no count. `.accessibilityAddTraits(.isSelected)` is applied only on the selected row (`:401`).

`onKeyPress` handles `.upArrow` and `.downArrow` only (`:408-415`). The arrows log matches: Down Overview → AI Agents → AI Coding Tools, Up back to AI Agents. Shift-Tab from Overview lands on the search field, then Refresh Updates, so reverse Tab leaves the sidebar.

## Traversal and Space

`focus-traversal-attempt2.log` (pid 39025) is key-loop order, not y-order: the toolbar sits at y=92 but is numbered after the detail. Lines 1–6 are the sidebar buttons after Overview, 7–10 are Overview "Show PATH evidence" buttons, and 11–14 are:

- `Copy Selected Entry path for Codex`
- `Reveal in Finder Selected Entry path for Codex`
- `Copy Resolved Target path for Codex`
- `Reveal in Finder Resolved Target path for Codex`

Line 15 is `Verify Installation for Codex`. `focus-traversal-attempt1.log` is the same text with a different pid. The file does not print the word "tab"; the order is the harness's forward sequence. It ends at Rescan (line 18). It does not show Check for Updates, Refresh, search, or wrap. Those are in the worker prose, not in this file.

`focus-space-activation.log` does not Tab onto Copy. Tabs 1–6 are the sidebar buttons; tabs 7–10 are empty `AXGroup`s; the harness then logs `set focus copy err=0` and Space. The pasteboard line is `/Users/corvette/.local/bin/codex`, with no `file://`, quotes, or newline. That is the Selected Entry path visible for Codex in `sidebar-focus-ring.png`. Clipboard save/restore is the worker's claim; the log line itself is only the after value. `focus-sidebar-space.log` is a failed run (Tab lands in text fields) and is not a pass. The worker says so.

## What did not regress

Menu shortcuts, prepare/verify gates, and the sheet `onConfirm` closures are not in the diff. `confirmSelectedUpdate` / `confirmSelectedUninstall` remain only those sheet closures. Conflict "Show PATH evidence" still appears in the key loop and was not rewired. C-1 and the operation-view initializers are not in the diff.

The sidebar column in `sidebar-focus-ring.png` still reads as a sidebar: seven named rows, icons, badges, a visible highlight on AI Agents, and the detail path buttons beside the recorded paths. It is not the system list selection material (see LOW/INFO below). It is not a broken column.

## Findings

### LOW-1 — Arrow navigation wraps

`MainWindow.swift:418-423`. `(index + offset + count) % count` wraps. Up from Overview selects Settings; Down from Settings selects Overview. A sidebar `List` does not wrap. The comment says this preserves list behavior. The selection write is still the one R1 path: Overview changes `listScope`, Settings does not. The arrows log does not exercise either end. Not a confirm, and not a second invalidation hook.

### INFO-1 — Space proof is set-focus, on a personal path; R10's other three controls are not in these logs

`focus-space-activation.log` focuses Copy with the accessibility API and then sends Space. R10's gate is Tab traversal to each of the four buttons and Space on that focused button, against the disposable fixture, never a personal path (`judgment.md:206-215`). This log is one control, one personal Codex path, arrived at by set-focus. Reachability of all four is the other file. Reveal's Finder selection, the second Copy, and the second Reveal are not Space-activated here. The product change does not need to be reverted for that gap; the full M8 matrix is not what these logs close.

### INFO-2 — Sidebar chrome is no longer a list

`MainWindow.swift:376-399`. Rows are plain buttons, multicolor symbols, and an `accentColor` 20% rounded fill instead of `.listStyle(.sidebar)`. The row is no longer an outline row ("n of 7"); it is an `AXButton` with the spoken label. That is the point of the fix (one key-view stop, a native press). The screenshot still shows a readable sidebar and a visible selected/focused row. No new non-semantic color.

### INFO-3 — The successful traversal is the Overview composition

Attempt 2's window title is Overview, and stops 7–10 are conflict actions. Category, Updates, and Diagnostics put `ToolListView`'s `List` in the content column. This diff does not change that list, and these logs do not show Tab leaving it. The reported trap was the sidebar list. The category-list key loop is unmeasured.

## Conclusion

Accept `255fd9c` as the sidebar focus fix. Destination selection, badges, spoken labels, the selected trait, the VoiceOver action, and arrow navigation stay on the existing R1 write, and the four path buttons are in the forward key order. Do not read these logs as a completed R10 pass for all four Spaces, Finder, or the fixture environment.
