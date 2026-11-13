# M12-E independent review — MiniMax (read-only)

**Candidate:** `5214d63` on `milestone/m12-workflow` (HEAD), frozen.
**Base for the candidate diff:** `1f2b62b` (M12-D accepted tip); dispatch-brief commit `c9012b9`.
**Contract:** `briefs/M12-E-native-accessibility.md`; `briefs/M12-plan.md` §3, §5 M12-E;
`briefs/M12-planning/judgment.md` R9, R10, R11 (binding).
**Reviewer:** MiniMax M3.1-Flash, independent, read-only. No product/test/brief file was edited, no
git mutation, no install, no subagent, no build/test run, no system-setting flip. This file is the
only write.

## Verdict

**CHANGES_REQUIRED** — 0 blocking, 0 high, 2 medium, 1 low, 4 info.

Nothing here is a safety hole: no menu item can reach a mutation confirm, the C-1 footer is
intact, and the diff stays inside the allow-list. But two findings are real, concrete, and cheap to
fix, and both should be closed before this phase is accepted:

1. **The "Verify Installation" menu item is not gated on "a sheet is presented"**, which the binding
   ruling R9 states for *all three* Tool items — the frozen brief's table narrowed it to
   Verify alone. The consequence is that ⌥⌘I stays live while a confirmation sheet is open, and
   activating it silently releases the pending preparation (zero mutation, but the user's
   in-progress confirmation dies from a keystroke).
2. **`.accessibilityLabel(destination.rawValue)` drops the sidebar badge count from the spoken
   label** — a regression against the base, in the one subject area this phase exists to improve.

The implementation is otherwise strong and, in several places, better than the brief asked: the
announcement path uses the real AppKit API (not the fallback), the File items fail closed when no
window is focused, the menu's actions reuse the toolbar's `runAction` lifetime, and the
destination write keeps the ViewModel's R1 hooks as the single invalidation path.

---

## 1. Menu safety (R9)

### 1.1 No menu item can confirm a mutation — **verified**

```text
grep -rn "confirmSelected" Sources/AgentLensApp/
  MainWindow.swift:107   await model.confirmSelectedUpdate()      // the accepted sheet callback
  MainWindow.swift:132   await model.confirmSelectedUninstall()  // the accepted sheet callback
```

Only the two accepted sheet callbacks call confirm. The Tool menu's three actions are
`actions?.prepareUpdate()` / `actions?.prepareUninstall()` / `actions?.verifyInstallation()`
(`AgentLensApp.swift:262-280`), which MainWindow binds to `model.prepareSelectedUpdate()`,
`model.prepareSelectedUninstall()` and `model.verifySelectedInstallation()`
(`MainWindow.swift:318-338`) — prepare/verify only ✓. A destructive confirmation remains
reachable only through the sheet's own button, whose key equivalent was removed by C-1 in M12-D
and is unchanged here.

### 1.2 The R9 shortcut table — **matches, item for item**

| R9 table | Candidate | File:line |
|---|---|---|
| Agent Lens · Settings… ⌘, | `CommandGroup(replacing: .appSettings)`, `.keyboardShortcut(",", modifiers: .command)` | `AgentLensApp.swift:197-200` |
| File · Rescan ⌘R | `.keyboardShortcut("r", modifiers: .command)` | `AgentLensApp.swift:205-208` |
| File · Check for Updates ⌘U | `.keyboardShortcut("u", modifiers: .command)` | `AgentLensApp.swift:210-214` |
| File · Refresh Update Metadata ⌘⇧U | `.keyboardShortcut("u", modifiers: [.command, .shift])` | `AgentLensApp.swift:216-220` |
| View · ⌘1…⌘7 (seven destinations) | ⌘1…⌘7 → `.overview`, `.aiAgents`, `.aiCodingTools`, `.aiHarnesses`, `.updates`, `.diagnostics`, `.settings` | `AgentLensApp.swift:225-259` |
| Tool · Prepare Update… ⌥⌘U | `.keyboardShortcut("u", modifiers: [.command, .option])` | `AgentLensApp.swift:262-266` |
| Tool · Prepare Uninstall… ⌥⌘⌫ | `.keyboardShortcut(.delete, modifiers: [.command, .option])` | `AgentLensApp.swift:268-272` |
| Tool · Verify Installation ⌥⌘I | `.keyboardShortcut("i", modifiers: [.command, .option])` | `AgentLensApp.swift:276-280` |

Negative checks, all clean:

- **No bare keys.** All 14 new shortcuts carry ⌘ or ⌥⌘; the full App inventory is 20 shortcuts
  (14 new menu items + the 6 pre-existing sheet-footer ones from M12-D), all with modifiers.
- **No ⌘K palette**, **no ⌘F custom item**, **no path menu items** — the menus expose no
  Copy/Reveal entry; path actions stay the detail-view buttons, as R9 requires.
- **⌘C not overridden.** The candidate replaces only the `.appSettings` group and adds to
  `.newItem` and `.sidebar`; the Edit menu is untouched, so ⌘C/⌘X/⌘V/⌘A remain the system items.
- **No second Settings scene.** `CommandGroup(replacing: .appSettings)` removes the system
  "Settings…" item and replaces it with a destination selection — R7's "no second Settings scene"
  holds ✓.
- **No ⌘K/⌘1 collision with the sidebar's standard ⌘⌃S.** The seven destination items live in
  `CommandGroup(after: .sidebar)`, i.e. in the View menu below the standard sidebar items behind a
  divider; no standard View shortcut is shadowed.

### 1.3 Disabled-when rules — **one deviation from R9's prose** (finding MEDIUM-1)

```swift
private var canPrepareUpdate: Bool {          // AgentLensApp.swift:288-291
    return !actions.isBusy && !actions.isSheetPresented && actions.updateAffordanceIsPrepare
}
private var canPrepareUninstall: Bool {        // AgentLensApp.swift:293-296
    return !actions.isBusy && !actions.isSheetPresented && actions.uninstallAffordanceIsPrepare
}
private var canVerifyInstallation: Bool {      // AgentLensApp.swift:298-301
    return !actions.isBusy && actions.canVerifyInstallation   // ← no sheet gate
}
```

See MEDIUM-1 below.

### 1.4 Busy gate and lifecycle — **correct and fail-closed**

- `fileItemsDisabled = actions?.isBusy ?? true` (`AgentLensApp.swift:284-286`) — when no focused
  window supplies actions the File items are **disabled**, not enabled ✓ fail-closed.
- Every menu action runs through MainWindow's `runAction` (`MainWindow.swift:162-172`), which
  itself guards `activeActionTask == nil, !model.isBusy` — so the busy gate is enforced twice, and
  the action lifetime is tracked by the termination gate exactly like a toolbar action ✓.
- The two Prepare items additionally read `ManagementPresentation(entry:)` for the selected entry
  (`MainWindow.swift:289-294`) and enable only on `.prepareNpmUpdate` / `.prepareNpmUninstall` —
  the affordance rule comes from the frozen model, not from a re-derived predicate ✓.

### 1.5 One invalidation path — **verified**

`selectDestination` writes `selectedDestination` (`MainWindow.swift:295-297`), the same State the
sidebar writes; `.onChange(of: selectedDestination)` then calls `applyDestination`
(`MainWindow.swift:250-272`), which writes **only** `model.listScope` and `model.detailPane`.
Both are the ViewModel's R1-observed properties, so the single invalidation trigger is the
ViewModel's `didSet` hook — the App adds no second one ✓. Consistent with R9:
⌘2/⌘3/⌘4/⌘5 change `listScope` and therefore invalidate a pending preview; ⌘,/⌘6/⌘7 write only
`detailPane` and do not ✓. The launch-time `applyDestination(selectedDestination)` in `.onAppear`
writes the values the ViewModel already holds, and the `didSet` compares before releasing, so
launch does not spuriously invalidate ✓.

The sidebar's VoiceOver activation (`.accessibilityAction { selectedDestination = destination }`,
`MainWindow.swift:366-368`) writes the same State as a click → same path ✓.

---

## 2. VoiceOver (R10)

| R10 requirement | Status | Evidence |
|---|---|---|
| List row: category, version or "version unknown", conflict kinds; unknown adds no "up to date" | preserved verbatim | `ToolListView.swift` untouched by this diff (`git diff` empty) |
| Section titles are headers | done | `.accessibilityAddTraits(.isHeader)` in `ToolDetailView.swift:186-189, 210-213, 290-293, 345-348, 470-473`, `DiagnosticsView.swift:119-122, 143-146, 252-255, 301-304, 399-402, 407-410, 425-428, 461-464`, `SettingsView.swift:45-48, 72-75, 89-92, 107-110`, both sheet titles (`UpdateOperationView.swift:94-97`, `UninstallOperationView.swift:99-102`) |
| Path buttons keep labels, gain hints | done | `PathActions.swift:73` "Copies the path text.", `:84` "Asks Finder to select this path."; existing labels untouched |
| Sheets: visible title as label; confirm/cancel hints | done | `UpdateOperationView.swift:78, 83`; `UninstallOperationView.swift:79, 88` |
| Progress region label = sentence + registry ID | preserved | M12-D's combined label is unchanged |
| Result announced with state + exit status | done | `UpdateOperationView.swift:186-189, 213-218`; `UninstallOperationView.swift:190-193, 216-221` |
| Unavailable announced with the Core reason | done | `UpdateOperationView.swift:172-176`; `UninstallOperationView.swift:176-180` — the reason string is the Core enum's own `reason.message`, not retyped ✓ |
| Error banners are elements whose label names the failure | done | `.accessibilityElement(children: .combine)` on the degraded/rescan-failure/update-failure banners in `ToolDetailView.swift:135, 156, 173`, `DiagnosticsView.swift:88, 109`, `OverviewView.swift:125` |
| Sidebar destinations activatable by VoiceOver | done | `.accessibilityAction` at `MainWindow.swift:366-368` — but see MEDIUM-2 for the label side effect |
| Transient path feedback announced | done, **with the real API** | `PathActions.swift:137-150` |

**Announcement API path (the brief asked which path was used).** The candidate used the real
AppKit announcement, not the fallback:

```swift
NSAccessibility.post(
    element: NSApplication.shared,
    notification: .announcementRequested,
    userInfo: [
        .announcement: text,
        .priority: NSAccessibilityPriorityLevel.high.rawValue,
    ]
)
```

`PathActions.swift:142-150` posts the visible feedback text on every transient outcome
(`setFeedback` at :134-138 → `Self.announce(text)`), and both sheets post their terminal state
via `.onAppear` on the result and unavailable views. **No visible string was changed** — the
announcement text is the same string the user sees ✓ (R10: "Do NOT change any visible string").

---

## 3. Layout, text, appearance (R11)

- **Content minimum**: `.frame(minWidth: 760, minHeight: 480)` on the `NavigationSplitView` root
  (`MainWindow.swift:69`) ✓; scene default size stays 960×600 (`AgentLensApp.swift:311`) ✓; the
  operation sheets keep `640×500` (`UpdateOperationView.swift:59`,
  `UninstallOperationView.swift:60`) ✓.
- **Semantic text only**: `grep -rn "\.font(\.system(size:" Sources/AgentLensApp/` → **no match** ✓.
- **No appearance/resizability overrides**: `grep -rn "preferredColorScheme\|windowResizability"`
  over `Sources/AgentLensApp/` → **no match** ✓.
- **No truncating limit**: the only `lineLimit` uses are `.lineLimit(nil)` — unlimited — in
  `OwnershipVerificationView.swift:210` and `ToolDetailView.swift:392, 403` ✓.
- **Wrapping**: `.fixedSize(horizontal: false, vertical: true)` added to the degraded/failure
  banner text (`ToolDetailView.swift:131, 152, 169`, `DiagnosticsView.swift:85, 106`), the
  inconsistent-selection and empty-observation text (`DiagnosticsView.swift:233, 243`), and the
  unavailable/result message text in both sheets ✓.
- **No non-semantic palette**: the only color added is `Color.accentColor.opacity(0.08)` for the
  progress region, which came in with M12-D, plus the pre-existing `Color.orange.opacity(0.1)`
  banners ✓. State continues to be carried by text.

---

## 4. C-1, initializers, and the stale comment — **intact**

- The sheet footers are unchanged: exactly three `keyboardShortcut`s per sheet — Done and Close
  keep `.defaultAction`, Cancel keeps `.cancelAction`, and the destructive confirm still has
  **none** (`UpdateOperationView.swift:68, 71, 76`; `UninstallOperationView.swift:69, 72, 77`).
  The full App inventory is 20 shortcuts, of which exactly these 6 are the sheet ones — C-1 is
  intact ✓.
- **No public initializer was touched.** The E diff contains no hunk in any `init` or property
  declaration of `UpdateOperationView`, `UninstallOperationView`, or `ToolDetailView` ✓, so the
  protected M10-D host (`Tests/Fixtures/M10D/npm_uninstall_acceptance.py:480, :499`) still
  constructs `UninstallOperationView` correctly.
- **The stale Cancel comment is corrected**: `UninstallOperationView.swift:5-6` now reads "Cancel is
  the Escape action; the destructive confirmation has no key equivalent and is explicit." — the
  old "Cancel is the safe default action" wording was factually wrong after C-1 ✓ (this is the
  carried note from `briefs/M12-D-operation-journey.md` §1.4).

---

## 5. R12 — zero Core/AppSupport/CLI/registry change — **verified**

```text
git diff --name-only 1f2b62b..5214d63
  Sources/AgentLensApp/{AgentLensApp,DiagnosticsView,MainWindow,OverviewView,PathActions,
                         SettingsView,ToolDetailView,UninstallOperationView,UpdateOperationView}.swift
  briefs/M12-E-native-accessibility.md        (orchestrator dispatch-brief commit c9012b9)
  walkthroughs/M12-D-evidence/reviews/{grok,minimax}.md   (orchestrator/reviewer artifacts)
  walkthroughs/M12-E-implementation.md        (the allow-listed worker report)
```

Filtering for `AgentLensCore`, `agent-lens`, `AgentLensAppSupport`, `Package.swift`, `scripts/`,
`.github`, `Tests/`, `Resources/`, `docs/`, `DECISIONS.md`, `ROADMAP.md`, `AGENT_LENS_SCOPE.md`,
`ConflictSummaryView`, `ToolListView` → **no match** ✓. No new dependency, no new
`AcceptedOperation` case, no CLI mutation syntax, no second Settings scene, no system setting
flipped. `git diff --check 1f2b62b..5214d63` → exit 0 ✓. Core 467 / AppSupport 119 unchanged ✓.

**Evidence integrity**: all nine committed App-file SHA-256 values match the worker report's
manifest exactly (`2e72a846…`, `b8c460fd…`, `40c33bfe…`, `4cdba1c3…`, `ae6fc4f3…`, `b22aeba9…`,
`c8e10664…`, `c20eaff7…`, `371c6dd1…`), so the reviewed tree is the tree the worker measured.

---

## 6. Severity-ranked findings

### BLOCKING — none
### HIGH — none

### MEDIUM

**MEDIUM-1 — "Verify Installation" (⌥⌘I) is not disabled while a sheet is presented, contradicting
R9's prose; the frozen brief's table narrowed the rule, so the contract chain itself is
inconsistent.**
`Sources/AgentLensApp/AgentLensApp.swift:298-301` and `:276-280`.

R9 (binding, `briefs/M12-planning/judgment.md:197-200`) reads:

> "Tool: Prepare Update… ⌥⌘U; Prepare Uninstall… ⌥⌘⌫; Verify Installation ⌥⌘I — these call
> `prepareSelectedUpdate`/`prepareSelectedUninstall`/`verifySelectedInstallation` ONLY, never
> `confirmSelected*`, **and are disabled when busy, a sheet is presented, or the matching affordance
> is not eligible**."

The dispatch brief's table (`briefs/M12-E-native-accessibility.md:83`) restates Verify's condition
as "busy, or selection not winner/off-PATH" — dropping "a sheet is presented". The candidate
implemented the table exactly, so it is compliant with the brief it was handed; but R9 is the
binding ruling and the brief is derived from it, so the brief's narrowing is a contract defect that
the implementer could not see. Consequence of the current code: with a confirmation sheet open and
a pending preparation, ⌥⌘I is enabled, and activating it calls
`model.verifySelectedInstallation()`, whose first statement is `invalidatePendingUpdate()`
(`Sources/AgentLensAppSupport/InventoryViewModel.swift:283`) — the pending preparation is released
with **zero mutation** and the sheet closes, after which a read-only ownership verification runs.
No mutation can occur, and during an *executing* mutation the call is refused outright
(`InventoryViewModel.swift:284` requires `updatePipeline == nil`), so this is not a safety hole.
It is nonetheless a keyboard action that can silently cancel a confirmation the user is in the
middle of, and it is inconsistent with its two sibling items, which are simply disabled in that
state. **Suggested fix (one condition):** `return !actions.isBusy && !actions.isSheetPresented &&
actions.canVerifyInstallation`. The orchestrator should decide which text governs — the ruling's
prose or the brief's table — and, if the table is meant to govern, record that decision rather
than leaving the ruling and the brief in conflict.

**MEDIUM-2 — `.accessibilityLabel(destination.rawValue)` drops the sidebar badge count from the
spoken label: an accessibility regression against the base.**
`Sources/AgentLensApp/MainWindow.swift:363`.

The sidebar row renders a badge next to the destination name
(`MainWindow.swift:350-357`: `Text(destination.rawValue)` plus `Text("\(badge)")` where the badge
is the conflict-tool count for Overview, the installed count for each category, and the global
update-available count for Updates — `MainWindow.swift:389-404`). In the base (`1f2b62b`) the row
carried **no** accessibility modifier, so SwiftUI derived the element's label from the row's text
and VoiceOver announced the name **and** the count ("AI Agents, 5"). The candidate's explicit
`.accessibilityLabel(destination.rawValue)` replaces that with the bare name, so the count — which
a sighted user sees next to the destination — is no longer spoken for any destination that has a
badge. This is a loss of truthful spoken information in the exact area the phase exists to improve
(R10: "VoiceOver labels/hints (every surface)"; the M12-B acceptance record treats the badge
counts as meaningful facts). It does not *lie* about a state and it does not affect safety, but it
is a measurable information-parity regression versus the accepted base.
**Suggested fix (one line):** include the badge in the label, e.g.
`.accessibilityLabel(badge.map { "\(destination.rawValue), \($0)" } ?? destination.rawValue)`, or
keep the name as the label and add the count as `.accessibilityValue("\(badge)")`.

### LOW

**LOW-1 — The "winner/off-PATH" verify predicate now exists twice in the App.**
`Sources/AgentLensApp/MainWindow.swift:334-341` (`canVerifySelection`) duplicates
`Sources/AgentLensApp/ToolDetailView.swift:268-275` (`canVerifyOwnership`) — the same switch on
`entry.diagnostic.selection`, and the same rule also lives in the frozen model at
`Sources/AgentLensAppSupport/WorkflowPresentation.swift:207`. M12-D's whole point was that the view
must not re-derive an eligibility predicate, and `hasSelectedInstallation` was *deleted* from
`ToolDetailView` for exactly that reason; the Tool menu now reintroduces the rule in a second
place. The two copies agree in meaning today, so there is no behavioral divergence — but a future
change to the selection model could update one and not the other, and the menu's enablement would
then silently disagree with the detail view's Verify button. `ToolDetailView.swift` was in M12-E's
allow-list, so the duplication was avoidable inside this phase (make the existing helper internal
and reuse it). The durable fix is one public predicate on the frozen model, which M12-E could not
make because AppSupport is frozen.

### INFO

**INFO-1 — The result view announces the exit status twice.** The result title's accessibility
label carries "…, exit status 0" (`UpdateOperationView.swift:186-189`,
`UninstallOperationView.swift:190-193`) while a separate visible row also shows "Exit status: 0"
just below it. Redundant rather than wrong; a VoiceOver user hears it twice.

**INFO-2 — `.onAppear`-based announcements can repeat.** The result and unavailable views announce
in `.onAppear` (`UpdateOperationView.swift:213-218`, `UninstallOperationView.swift:216-221`). If
the sheet is re-presented or the view's identity changes, the announcement is posted again. This
is benign (announcements are transient) but it is worth knowing before M12-F's spoken check, which
should not treat a duplicate announcement as a defect.

**INFO-3 — The Overview "Conflicts" heading is not a header trait.** `Text("Conflicts")` at
`Sources/AgentLensApp/ConflictSummaryView.swift:30` has no `.accessibilityAddTraits(.isHeader)`,
because that file is DO NOT TOUCH for this phase. The worker report discloses this
(`walkthroughs/M12-E-implementation.md:213-214`). The consequence is that VoiceOver's rotor does
not expose the conflict section as a heading on the Overview surface — a small navigation-structure
gap that M12-F's VoiceOver pass will encounter. The phase's own rule ("leave unless a label is
missing") arguably covers this, so I am not treating it as a finding; it is a candidate for the
next phase's allow-list.

**INFO-4 — The seven destinations share the View menu's sidebar group.** They are added with
`CommandGroup(after: .sidebar)` (`AgentLensApp.swift:225`), so they render in the View menu below
the standard sidebar items behind a divider, rather than as their own group. They are in the View
menu as R9 requires and no standard shortcut is shadowed; noting it only so the orchestrator's AX
read of "the menu items" knows where to look.

---

## 7. Residual risks and forward notes

1. **M12-F's VoiceOver pass will land on MEDIUM-2 and MEDIUM-1.** Both are one-line fixes; if the
   orchestrator prefers to measure first, the expected observations are: sidebar rows announce
   "AI Agents" without the count, and the Tool menu's Verify Installation item is enabled while a
   confirmation sheet is open.
2. **M12-F should also re-assert C-1 mechanically.** The menu work is the first phase to touch
   key equivalents since D; the 20-shortcut inventory above is the current baseline, and a future
   menu addition could reintroduce a Return-to-confirm path. My M12-D review noted that nothing in
   CI protects that property; the R10 real-key-event gate remains the only automated guard.
3. **The announcement API is confirmed available**, so M12-F can rely on `NSAccessibility.post` and
   does not need the focused-element-value fallback. Worth recording as a settled fact for the
   remaining phases.
4. **`ToolListView` needed no edit** and was correctly left untouched; the M12-B row description
   (category, version or "version unknown", conflict kinds) is preserved verbatim, and unknown is
   still never spoken as current ✓.

---

## 8. Reproducible checks performed

```text
git rev-parse HEAD                                     → 5214d6350ebe33b23ea1628fd7132b625a9c8106
git branch --show-current                              → milestone/m12-workflow
git diff --name-only 1f2b62b..5214d63                  → 9 App files + brief + M12-D reviews + report
git diff --name-only 1f2b62b..5214d63 | grep -E "AgentLensCore|agent-lens|AgentLensAppSupport|
    Package.swift|scripts/|\.github|Tests/|Resources/|docs/|DECISIONS.md|ROADMAP.md|
    AGENT_LENS_SCOPE.md|ConflictSummaryView|ToolListView"                            → empty
git diff --check 1f2b62b..5214d63                     → exit 0
shasum -a 256 of the 9 changed App files               → identical to the worker report manifest
grep -rn "confirmSelected" Sources/AgentLensApp/       → only the 2 accepted sheet callbacks
grep -rn "keyboardShortcut" Sources/AgentLensApp/*.swift → 20 (14 new menu + 6 pre-existing sheet)
grep -rn "preferredColorScheme|windowResizability|\.font(\.system(size:" Sources/AgentLensApp/ → none
grep -rn "lineLimit" Sources/AgentLensApp/             → only .lineLimit(nil) (non-truncating)
git show 1f2b62b:Sources/AgentLensApp/MainWindow.swift → base sidebar row had NO a11y modifier
```

Read but not executed: `Tests/Fixtures/M10D/npm_uninstall_acceptance.py:480`, `:499`. No build, no
test suite, no destructive fixture, no system-setting change, and no product file was touched by
this reviewer.
