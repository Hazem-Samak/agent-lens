# M12-E R1 independent review — Grok (read-only)

**Candidate:** `407882b` (`feat(workflow): M12-E R1 — Verify sheet gate + sidebar spoken badge + a11y fixes`) on `milestone/m12-workflow`. Diff base `5214d63` (the M12-E candidate this review previously marked CHANGES_REQUIRED).
**Prior review:** `walkthroughs/M12-E-evidence/reviews/grok.md` — CHANGES_REQUIRED, 0 blocking. MEDIUM-1 Verify sheet gate, LOW-1 sidebar badge label, LOW-2 Conflicts header.
**Reviewer:** Grok, independent, read-only. No product, test, brief, or fixture file was edited. No git mutation, no subagent, no build, no test. This file is the only write. The orchestrator's R1 rerun (Core 467 + AppSupport 119 = 586, zero failures) is the execution record. This review is source inspection of `git diff 5214d63..407882b`.

## Verdict

**PASS** — 0 blocking, 0 high, 0 medium, 0 low, 1 info.

All three prior findings are fixed in the product diff. The menu still cannot confirm a mutation. C-1, the public initializers, and the shortcut table are unchanged. The product delta is four App files.

## What changed

Product files in `5214d63..407882b`:

- `Sources/AgentLensApp/AgentLensApp.swift` — Verify's disabled predicate gains the sheet conjunct.
- `Sources/AgentLensApp/MainWindow.swift` — spoken sidebar label includes the badge; verify eligibility calls `ToolDetailView.canVerifyOwnership`; the local copy of that switch is deleted.
- `Sources/AgentLensApp/ToolDetailView.swift` — `canVerifyOwnership` is now module-visible and is the only copy of the winner/off-PATH rule.
- `Sources/AgentLensApp/ConflictSummaryView.swift` — "Conflicts" gains `.isHeader`.

The same range also adds the two M12-E review files and updates `walkthroughs/M12-E-implementation.md`. Those are records, not product. `git diff --check 5214d63..407882b` exits 0. No diff under `Sources/AgentLensCore`, `Sources/AgentLensAppSupport`, `Sources/agent-lens`, `Package.swift`, `Tests/**`, `scripts/**`, or `Resources/**`. `UpdateOperationView.swift` and `UninstallOperationView.swift` are absent from the diff.

## Prior findings

### MEDIUM-1 — closed

`AgentLensApp.swift:298-302`:

```swift
private var canVerifyInstallation: Bool {
    guard let actions else { return false }
    return !actions.isBusy && !actions.isSheetPresented && actions.canVerifyInstallation
}
```

`isSheetPresented` is still `model.isUpdateSheetPresented || model.isUninstallSheetPresented` (`MainWindow.swift:293`), which is preview, preparation, outcome, or unavailable. Prepare Update and Prepare Uninstall keep the same three conjuncts (`AgentLensApp.swift:288-295`). With no focused actions the item stays disabled. Opt-Cmd-I can no longer call `verifySelectedInstallation()` while either sheet is presented, so it can no longer reach `invalidatePendingUpdate()` under an open confirmation or result.

The button still calls `actions?.verifyInstallation()` (`AgentLensApp.swift:276-280`), which is `runAction { await model.verifySelectedInstallation() }` (`MainWindow.swift:325-328`). It does not confirm.

### LOW-1 — closed

`MainWindow.swift:353` now uses `accessibilityLabel(for:)`. `MainWindow.swift:398-401` returns `destination.rawValue` when `badgeCount` is nil (Diagnostics, Settings) and `"\(destination.rawValue), \(badge)"` otherwise. `badgeCount` (`:379-393`) is the same function the visible badge uses, including a shown zero. The activation action is unchanged: it still assigns `selectedDestination` and nothing else (`:356-358`).

### LOW-2 — closed

`ConflictSummaryView.swift:30-32`: `Text("Conflicts")` is `.font(.headline)` and `.accessibilityAddTraits(.isHeader)`. The count remains a sibling, not a second title. No other line in that file changed.

### Deduplicated predicate

`ToolDetailView.canVerifyOwnership` (`ToolDetailView.swift:270-277`) is the same switch as the deleted `MainWindow.canVerifySelection`: `.winner` and `.offPath` true; `.notInstalled` and `.inconsistent` false. It is `static` and not `public`, so the view's public surface is unchanged. The detail section still passes `Self.canVerifyOwnership(entry)` (`ToolDetailView.swift:261`). The menu uses `model.selectedEntry.map(ToolDetailView.canVerifyOwnership) ?? false` (`MainWindow.swift:296`). No second copy remains.

## Re-checked safety

`confirmSelectedUpdate` / `confirmSelectedUninstall` still appear only as the sheet `onConfirm` closures (`MainWindow.swift:107` and `:132`). The Tool menu items are still Prepare Update (`prepareUpdate`), Prepare Uninstall (`prepareUninstall`), and Verify Installation (`verifyInstallation`).

Shortcuts are unchanged: Settings ⌘,; Rescan ⌘R; Check ⌘U; Refresh ⌘⇧U; View ⌘1…⌘7; Prepare Update ⌥⌘U; Prepare Uninstall ⌥⌘⌫; Verify ⌥⌘I (`AgentLensApp.swift:199-279`). No new bare key, no ⌘K, no ⌘C item, no path item. File items stay disabled only for busy (or no focused actions), which is the R9 File row.

C-1 and the public initializers were not edited. The operation-view `keyboardShortcut` sites are still Done/Close `.defaultAction` and Cancel `.cancelAction` only (`UpdateOperationView.swift:68-76`, `UninstallOperationView.swift:69-77`). The confirm buttons have no shortcut.

## Findings

### INFO-1 — Verify's comment overstates the sheet rule

`AgentLensApp.swift:300` says "no menu action may run while a confirmation sheet owns the mutation slot." The line it comments gates Verify only. File > Rescan, Check for Updates, and Refresh Update Metadata stay enabled during a sheet (`fileItemsDisabled` is busy-only, `AgentLensApp.swift:284-286`), which R9's File row requires. The predicate is correct. The sentence is not.

## Conclusion

R1 closes MEDIUM-1, LOW-1, and LOW-2 without moving the confirm path, the C-1 footer, the initializers, or the shortcut table, and without a Core, AppSupport, CLI, or registry edit. Accept `407882b`.
