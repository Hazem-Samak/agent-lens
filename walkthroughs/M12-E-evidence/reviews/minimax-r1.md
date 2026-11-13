# M12-E R1 independent re-review — MiniMax (read-only)

**R1 candidate:** `407882b` on `milestone/m12-workflow` (HEAD).
**Pre-R1 candidate:** `5214d63` (my prior review: CHANGES_REQUIRED — 0 blocking, 0 high, 2 medium,
1 low, 4 info; `walkthroughs/M12-E-evidence/reviews/minimax.md`).
**R1 delta inspected:** `git diff 5214d63..407882b`.
**Contract:** `briefs/M12-E-native-accessibility.md`; `briefs/M12-plan.md` §3, §5 M12-E;
`briefs/M12-planning/judgment.md` R9, R10, R11.
**Reviewer:** MiniMax M3.1-Flash, independent, read-only. No product/test/brief file was edited, no
git mutation, no install, no subagent, no build/test run, no system-setting flip. This file is the
only write.

## Verdict

**PASS** — 0 blocking, 0 high, 0 medium, 0 low, 3 info (residual observations only).

All four corrections are correct, minimal, and verified in source. Every finding from my prior
review is closed:

| Prior finding | R1 correction | Verified at | Disposition |
|---|---|---|---|
| **MEDIUM-1** Verify not gated on "sheet presented" | `!actions.isSheetPresented` added | `Sources/AgentLensApp/AgentLensApp.swift:298-302` | **closed** |
| **MEDIUM-2** sidebar badge count dropped from the spoken label | `accessibilityLabel(for:)` restores it | `Sources/AgentLensApp/MainWindow.swift:353`, `:396-400` | **closed** |
| **LOW-1** winner/off-PATH predicate duplicated in the App | duplicate deleted; the detail view's rule is now the only one | `Sources/AgentLensApp/MainWindow.swift:296`, `Sources/AgentLensApp/ToolDetailView.swift:268-275` | **closed** |
| **INFO-3** Overview "Conflicts" heading was not a header | `.accessibilityAddTraits(.isHeader)` added | `Sources/AgentLensApp/ConflictSummaryView.swift:32` | **closed** (bonus fix) |

Nothing in the R1 delta touches the mutation path, the sheet footers, the shortcut table, or any
frozen module. The candidate is safe to accept on this evidence; the three remaining items are
informational observations that need no action in this phase.

---

## 1. Finding-by-finding verification

### MEDIUM-1 — Verify is now disabled while a sheet is presented — **closed**

`Sources/AgentLensApp/AgentLensApp.swift:298-302`:

```swift
private var canVerifyInstallation: Bool {
    guard let actions else { return false }
    // R9: no menu action may run while a confirmation sheet owns the mutation slot.
    return !actions.isBusy && !actions.isSheetPresented && actions.canVerifyInstallation
}
```

The Verify item now carries exactly the same three-part gate as its two siblings — busy, sheet
presented, affordance (`canPrepareUpdate` at `:288-291`, `canPrepareUninstall` at `:293-296`) — so
⌥⌘I can no longer reach `verifySelectedInstallation()` while a confirmation sheet owns the
mutation slot, and the pending preparation can no longer be released by a keystroke from the menu.
The comment states the governing rule, and the worker report's shortcut table was updated to match
(`walkthroughs/M12-E-implementation.md:62`: "busy, a sheet presented, or selection not
winner/off-PATH"). This also closes the contract-chain defect I flagged: R9's prose governs, and
the deviation is now recorded rather than left implicit.

### MEDIUM-2 — the spoken sidebar label restores the badge count — **closed**

`Sources/AgentLensApp/MainWindow.swift:353` now calls a helper (`:396-400`):

```swift
private func accessibilityLabel(for destination: NavigationDestination) -> String {
    guard let badge = badgeCount(destination) else { return destination.rawValue }
    return "\(destination.rawValue), \(badge)"
}
```

This is a faithful restoration of the base behaviour rather than an approximation: the helper is
driven by the **same** `badgeCount(destination)` function (`:389-404`) that renders the visible
badge, so the spoken label and the visible row cannot diverge — "AI Agents, 5" when the row shows
5, "Overview, 0" when the row shows 0, and the bare name for Diagnostics and Settings, which have
no badge (`badgeCount` returns `nil` for those two, and the row renders no badge `Text` for them).
The base's SwiftUI-derived label was exactly this composition, so nothing that was spoken before
is lost now. `.accessibilityAction` (`:355-357`) is unchanged, so VoiceOver activation still
writes the same `selectedDestination` State as a click — one invalidation path.

### LOW-1 — the verify predicate is deduplicated — **closed**

`Sources/AgentLensApp/ToolDetailView.swift:268-275` — the rule is now module-internal and carries a
doc comment stating that the menu bar reuses it:

```swift
/// The single winner/off-PATH ownership-verification rule. The menu bar reuses this predicate,
/// so the eligibility rule exists in exactly one place.
static func canVerifyOwnership(_ entry: InventoryEntry) -> Bool { … }
```

`Sources/AgentLensApp/MainWindow.swift:296` consumes it —
`canVerifyInstallation: model.selectedEntry.map(ToolDetailView.canVerifyOwnership) ?? false` — and
MainWindow's duplicate `canVerifySelection` is deleted. I compared the two implementations
line by line: the new call is **exactly equivalent** to the deleted helper for every case
(no selection → `false`; `.winner`/`.offPath` → `true`; `.notInstalled`/`.inconsistent` → `false`),
so this is a pure de-duplication with no behavioral change. The detail view still uses the same
function for its own Verify control (`ToolDetailView.swift:261`), so the menu and the detail view
can no longer disagree about when verification is eligible.

### INFO-3 — the Overview "Conflicts" heading is now a header — **closed (bonus)**

`Sources/AgentLensApp/ConflictSummaryView.swift:32` adds `.accessibilityAddTraits(.isHeader)` to
the `Text("Conflicts")` title. The sibling `Text("\(conflicts.count)")` is left untouched and
remains its own element, so the count is still announced and the heading is now exposed in
VoiceOver's rotor as a heading. The brief lists this file as DO NOT TOUCH "unless a label is
missing" (`briefs/M12-E-native-accessibility.md:59`); the R1 dispatch authorized exactly this one
trait, and it is the minimum change that closes the gap I raised.

---

## 2. Re-confirmed invariants

- **No menu item calls a confirm.** `grep -rn "confirmSelected" Sources/AgentLensApp/` still
  returns only `MainWindow.swift:107` (`confirmSelectedUpdate`) and `:132`
  (`confirmSelectedUninstall`) — the two accepted sheet `onConfirm` callbacks. The R1 delta does not
  touch either sheet or the commands' action bodies.
- **C-1 footer intact.** `git diff --name-only 5214d63..407882b -- …/UpdateOperationView.swift
  …/UninstallOperationView.swift` is **empty** — R1 did not touch either sheet at all, so the
  footer key equivalents, the destructive-button titles/roles, and the public initializers are
  byte-identical to the M12-D accepted state.
- **Shortcut table intact.** The App-wide inventory is still **20** shortcuts — 14 menu items
  (unchanged keys: ⌘, ⌘R, ⌘U, ⌘⇧U, ⌘1…⌘7, ⌥⌘U, ⌥⌘⌫, ⌥⌘I) and 6 pre-existing sheet-footer
  ones. The R1 delta changed exactly one line of `AgentLensApp.swift`, and it changed a *disabled
  condition*, not a key.
- **Zero Core/AppSupport/CLI/registry change.** Filtering the full phase range
  `1f2b62b..407882b` for `AgentLensCore`, `agent-lens`, `AgentLensAppSupport`, `Package.swift`,
  `scripts/`, `.github`, `Tests/`, `Resources/`, `docs/`, `DECISIONS.md`, `ROADMAP.md`,
  `AGENT_LENS_SCOPE.md` → **no match**. `git diff --check 1f2b62b..407882b` exits 0.
- **Evidence integrity.** All ten App-file SHA-256 values at `407882b` match the R1 worker
  manifest exactly (`c60a3349…`, `28e81cba…`, `75a4c19f…`, `448717f6…` for the four changed
  files; the six unchanged ones still carry their pre-R1 values).

---

## 3. Residual findings (informational only — no action required in this phase)

**INFO-A — the frozen brief still carries the narrowed Verify condition.**
`briefs/M12-E-native-accessibility.md:83` states Verify is disabled when "busy, or selection not
winner/off-PATH", which is the wording that produced MEDIUM-1. The brief is frozen and
DO NOT TOUCH, so it was correctly left unedited, and the resolution is recorded in
`walkthroughs/M12-E-implementation.md:62` and in the code comment at
`AgentLensApp.swift:300`. Worth noting only so that a future reader who consults the brief alone
derives the narrower (wrong) rule — the ruling's prose is the governing text.

**INFO-B — the R1 commit also carries the two reviewer artifacts.**
`407882b` contains the four product App files, the worker report, and
`walkthroughs/M12-E-evidence/reviews/{grok,minimax}.md` — the two review files written by the
council models, not by the implementer. Git delivery is the orchestrator's (the M12-D precedent
filed the reviews in a separate `docs:` commit), so this is an orchestrator-side accounting
detail rather than an implementer scope issue. The implementer's product delta is exactly four App
files plus its own report, and the worker report's protected-manifest accounting excludes the
review artifacts explicitly.

**INFO-C — three observations from the prior review carry forward unchanged** (they were never
defects, and the R1 delta does not touch them): the result view announces the exit status twice
(once in the title's accessibility label, once in the visible "Exit status:" row); the
`.onAppear`-based sheet announcements can repeat if a sheet is re-presented; and the seven View
destinations share the View menu's standard sidebar group rather than a group of their own.

---

## 4. Note on the worker's gate evidence

The worker report discloses that the first R1 full-suite attempt exited 1 with three
load-sensitive Core version-query failures (`cancellingAfterSpawnInterruptsAndStillReconcilesWithoutOrphan`,
`plainScanMakesZeroManagerCallsAndReportsNotChecked`,
`probeFailureIsAResultValueAndScanStillExitsZero`), that a targeted rerun of exactly those three
passed in isolation, and that a fresh-scratch full-suite rerun passed 467 Core + 119 AppSupport =
586 with zero skips/failures. Both logs are filed unedited. I did not re-run the suite.

This is consistent with R16's documented load-sensitivity note, and the R1 delta touches only App
source files — no Core, AppSupport, or test file changed — so it cannot be the cause of failures in
Core's local version-query fixture path. The disclosure is honest and the orchestrator's
independent R1 rerun is green.

---

## 5. Checks performed

```text
git rev-parse HEAD                                   → 407882b2e983e09e62d25ccdd3445f58eda841cf
git diff --stat 5214d63..407882b                    → 4 App files + worker report + 2 review files
git diff 5214d63..407882b -- UpdateOperationView.swift UninstallOperationView.swift → empty
grep -rn "confirmSelected" Sources/AgentLensApp/     → only MainWindow.swift:107 and :132
grep -c "keyboardShortcut" Sources/AgentLensApp/*.swift → 20 (14 menu + 6 sheet)
git diff --name-only 1f2b62b..407882b | grep -E "AgentLensCore|agent-lens|AgentLensAppSupport|
    Package.swift|scripts/|\.github|Tests/|Resources/|docs/|DECISIONS.md|ROADMAP.md|
    AGENT_LENS_SCOPE.md"                                                   → empty
git diff --check 1f2b62b..407882b                   → exit 0
shasum -a 256 of the 10 App files                    → identical to the R1 worker manifest
grep -n "canVerifyOwnership\|canVerifySelection" Sources/AgentLensApp/*.swift
    → one definition (ToolDetailView.swift:270), two call sites, zero duplicates
```

No build, no test suite, no destructive fixture, no system-setting change, and no product file was
touched by this reviewer.
