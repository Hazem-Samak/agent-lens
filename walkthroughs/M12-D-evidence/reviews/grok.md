# M12-D independent review — Grok (read-only)

**Candidate:** `6c1405a` (`feat(workflow): M12-D operation-journey completion candidate`) on `milestone/m12-workflow`. Diff base `2229ddf`. The dispatch brief itself landed in the parent commit `d057ea8`; it is not part of the candidate.
**Contract:** `briefs/M12-D-operation-journey.md`; `briefs/M12-plan.md` §3 and §5 M12-D; `briefs/M12-planning/judgment.md` R4, R5, R6, R13.
**Reviewer:** Grok, independent, read-only. No product, test, brief, or fixture file was edited. No git mutation, no install, no subagent, no build, no test, no destructive fixture. This file is the only write. The orchestrator's green rerun (Core 467 + AppSupport 119 = 586, guard 21, packaging 9) is the execution record. This review is source inspection.

## Verdict

**PASS** — 0 blocking, 0 high, 0 medium, 0 low, 1 info.

**C-1 adjudication: accept.** In the preview state of both sheets, Return no longer confirms a mutation. Cancel is Escape. The destructive confirm has no key equivalent. Result and unavailable keep Done/Close on Return. This removes the accepted M10 Update Return-to-confirm path and does not weaken any M10 safety property. Uninstall never confirmed on Return; it only loses Return-as-cancel, and Escape still cancels.

## What changed

`git show --stat 6c1405a` is exactly the allow-list plus the worker report:

- `Sources/AgentLensApp/ToolDetailView.swift`
- `Sources/AgentLensApp/UpdateOperationView.swift`
- `Sources/AgentLensApp/UninstallOperationView.swift`
- `walkthroughs/M12-D-implementation.md`

`git diff --check 2229ddf..6c1405a` exits 0. No diff under `Sources/AgentLensCore`, `Sources/AgentLensAppSupport`, `Sources/agent-lens`, `MainWindow.swift`, `ToolListView.swift`, `Package.swift`, `Tests/**`, `scripts/**`, or `.github/**`. AppSupport stays 119 because this commit adds no test. Public initializers of both operation views are absent from the diff.

## C-1 — accept; it does not weaken M10

Preview footers, and only those branches:

- Update (`UpdateOperationView.swift:71-81`): Cancel calls `onCancel`, `.keyboardShortcut(.cancelAction)`, `.disabled(isCancelling)`. Confirm Update / Installing… / Cancelling… calls `onConfirm`, has no `keyboardShortcut`, and is `.disabled(isExecuting || isCancelling)`.
- Uninstall (`UninstallOperationView.swift:72-86`): same shape. The confirm button keeps `role: .destructive` and the title "Uninstall Package" (the M10 sheet title; the detail button remains "Uninstall…"). It has no key equivalent and is disabled while executing or cancelling.

The only `.defaultAction` shortcuts in either file are Done and Close (`UpdateOperationView.swift:65-70`, `UninstallOperationView.swift:66-71`). Those branches are `if outcome != nil` and `else if unavailable != nil`, so they are not in the view tree while the preview footer is. A grep of `keyboardShortcut` in the three production files finds those four default-action buttons and the two cancel-action buttons, and nothing else. The detail Prepare / Uninstall buttons have no shortcut.

Body priority is outcome, then preview, then unavailable (`UpdateOperationView.swift:41-47`, same in Uninstall). Progress and the confirm footer therefore cannot sit under a result. When `outcome != nil`, Return dismisses through Done. That dismissal calls `onDismiss`, which is the existing non-mutating close.

What M10 actually did, from the parent of this diff:

- Update preview: Confirm Update held `.defaultAction` (Return executed `onConfirm` → `confirmSelectedUpdate`).
- Uninstall preview: Cancel held `.defaultAction` (Return executed `onCancel`). The destructive button already had no shortcut.

C-1 deletes the Update Return path. That path was a direct mutation shortcut. The council brief and R5 require that a shortcut never execute a mutation. No accepted M10 safety property depends on it: preview → revalidate → execute, one mutation at a time, cancel-releases-without-mutation, no shell interpolation, and confirmation required all stay. The M10-D host still only constructs the view for a render (`Tests/Fixtures/M10D/npm_uninstall_acceptance.py:480-481` and `:499-500`); it does not send Return. R5 records that the M10-D click-through used AXPress. I did not re-run that fixture.

Uninstall is not made easier to confirm. Return used to cancel it. Return now does nothing in that preview, and Escape cancels. The destructive control is still click or Tab + Space, and it is disabled for the whole execution. Losing Return-as-cancel is a smaller safe accelerator, not a new confirm path. Escape is the cancel key R5 names.

`interactiveDismissDisabled(isExecuting)` stays on the sheet in `MainWindow.swift`, which this commit does not touch. Cancel stays enabled during execution and disabled only while `isCancelling`, so Escape can still abort an in-flight command and cannot confirm it. That matches "keep the Cancel `disabled(isCancelling)` behavior."

I would not block C-1. Both reviewers were told to block only if it weakens safety. It does the opposite for Update and stays at least as strict for Uninstall.

## R4 — ManagementPresentation rendering

`detailContent` builds one `ManagementPresentation(entry:)` (`ToolDetailView.swift:72`) and passes it down. The update control is a switch on `presentation.update` only (`:550-569`):

- `.prepareNpmUpdate` → button title "Prepare Update…" / "Preparing Update…", image `arrow.down.circle`, `.disabled(isBusy)`, action `onPrepareUpdate`. Same title, image, and disabled rule as the deleted M10 block.
- `.unavailable(text)` → `Text(text)`, no button. The string is the model's associated value. The view does not contain the Core "not yet accepted" sentence or the newer-version sentence as a literal.
- `.hidden` → `EmptyView`.

The npm uninstall block is still behind `hasDeclaredNpmPackage` (`:271-273`, `:285-287`), which is the gate the brief says to preserve. Inside it, the switch is on `presentation.uninstall` (`:302-327`):

- `.prepareNpmUninstall` → destructive button "Uninstall…" / "Preparing Uninstall…", image `trash`, `.disabled(isBusy)`, action `onPrepareUninstall`, plus the existing preview-explanation caption. The "Verified npm-global package:" line still reads `verified.packageName`. It is a caption, not the gate: the button is outside that `if let`. `ManagementPresentation` emits `.prepareNpmUninstall` only when the verified manager is `.npm` and the selection is winner or off-PATH, so the caption appears on the same entries as the old view.
- `.unavailable(text)` and `.needsVerification(text)` → `Text(text)`, no button. Needs-verification copy is the model's string, not a retyped literal.
- `.hidden` → nothing.

`otherLimits` render as `Text` in a `ForEach` (`:288-293`), after the npm slot, each with wrapping `fixedSize` and no `lineLimit`. They are not buttons. Codex declares npm and a cask, so the section shows the npm control and then the cask sentence. The sentence cannot replace the button: the button is a different enum case, rendered first. The newer-version sentence is the update slot's `.unavailable` text, so it appears only when the model did not offer Prepare Update. It does not sit on the Codex prepare path.

Grok (`DefaultDetectors.json:52-61`) has `"packages": []`. `hasDeclaredNpmPackage` is false, so `uninstallAffordance` is not called. There is no Manage npm block and no npm button. If that copy is installed and classified standalone, `otherLimits` can still show the standalone sentence under the Manage headline. That is the required limit text, not an npm control. A not-installed grok has empty `otherLimits`, so the whole section stays hidden (`:99`).

No view predicate over `acceptedOperations`, `updateStatus`, or `hasSelectedInstallation` remains. `hasSelectedInstallation` was deleted. The status grid still displays `entry.update` facts; it does not decide the button.

## R6 — progress region

Both `previewView`s insert `progressRegion(preview)` only when `isExecuting` (`UpdateOperationView.swift:87-89`, `UninstallOperationView.swift:92-94`). `previewView` runs only when `outcome` is nil and `preview` is non-nil, so the three R6 conjuncts hold. The region is a `ProgressView` plus "Update in progress" or "Uninstall in progress" and that same preview's `registryID`, `packageName`, and `prefix` (`:135-159` and `:139-163`). The preview grid stays below it. There is no stdout read, no `onReceive`, and no stream. Stdout remains in `resultView` via `outputView`, which is unreachable until `outcome != nil`. `resultTitle` still switches the existing `OperationState` cases (`succeeded`, `failed`, `cancelled`, `interrupted`, `uncertain`). No case was added. Core was not edited.

Sheet minimums stay `.frame(minWidth: 640, minHeight: 500)`. New safety text uses semantic fonts and vertical `fixedSize`. No new truncating `lineLimit`.

## R13 and initializers

Prepare still enters only through the detail callbacks `onPrepareUpdate` / `onPrepareUninstall`. `ToolListView.swift` and `MainWindow.swift` are untouched, so Updates rows gain no prepare button and no second entry point. Nothing stores a per-tool operation history.

`UninstallOperationView.init` (`UninstallOperationView.swift:17-26`) is still `(preview, outcome, unavailable, isExecuting, isCancelling, onConfirm, onCancel, onDismiss)` in that order. The M10-D host call at `npm_uninstall_acceptance.py:480-481` and `:499-500` uses those argument labels. `UpdateOperationView.init` (`:16-25`) is the same shape and was not edited. A parameter change would have been a phase failure. There isn't one.

## Findings

### Blocking — none

### High — none

### Medium — none

### Low — none

### Info

**INFO-1 — The uninstall sheet's file comment still calls Cancel the default action.**

`UninstallOperationView.swift:4-6` says "Cancel is the safe default action." After C-1, Cancel is `.cancelAction` (`:76`), and the preview state has no default action. The footer code is what ships; the comment is stale. It does not affect keys or actions.

## Conclusion

Accept M12-D at `6c1405a`, including C-1. The detail view renders the frozen presentation model, Codex controls keep their titles, roles, and disabled rule, Core refusal text is displayed from the model, and both sheets show an in-flight progress region bound to the prepared preview without a new outcome state or an initializer change. Return confirms neither mutation.
