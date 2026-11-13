# M12-E independent review — Grok (read-only)

**Candidate:** `5214d63` (`feat(workflow): M12-E native menus + accessibility + layout candidate`) on `milestone/m12-workflow`. Diff range requested: `1f2b62b..5214d63`. That range also contains two orchestrator commits (`efd4f33` M12-D reviews, `c9012b9` the M12-E brief). The product candidate is `5214d63` alone.
**Contract:** `briefs/M12-E-native-accessibility.md`; `briefs/M12-plan.md` §3 and §5 M12-E; `briefs/M12-planning/judgment.md` R9, R10, R11 (R1 for invalidation).
**Reviewer:** Grok, independent, read-only. No product, test, brief, or fixture file was edited. No git mutation, no install, no subagent, no build, no test. This file is the only write. The orchestrator's green rerun (Core 467 + AppSupport 119 = 586, guard 21, packaging 9) is the execution record. This review is source inspection. Spoken VoiceOver, the sidebar AX tree, and large-text/light-dark measurement are M12-F and were not performed here.

## Verdict

**CHANGES_REQUIRED** — 0 blocking, 0 high, 1 medium, 2 low, 3 info.

No menu item calls `confirmSelectedUpdate` or `confirmSelectedUninstall`. Prepare Update and Prepare Uninstall are gated on busy, sheet, and the frozen affordance. C-1, the public initializers, and the allow-list hold. The miss is Tool > Verify Installation: plan §5 and R9 disable it while a sheet is presented; the code does not. Opt-Cmd-I in that state calls `verifySelectedInstallation()`, whose first act releases the pending preview (and a finished result) with zero mutation. It does not confirm. That is why it is not blocking. It is still the sheet gate the menu-safety rule requires.

## What changed

`git show --stat 5214d63` is the allow-list except `ToolListView.swift`, plus the worker report:

- `Sources/AgentLensApp/AgentLensApp.swift` (`.commands`, `AppCommandActions`)
- `Sources/AgentLensApp/MainWindow.swift` (wiring, 760×480, sidebar action)
- `Sources/AgentLensApp/PathActions.swift`
- `Sources/AgentLensApp/ToolDetailView.swift`
- `Sources/AgentLensApp/DiagnosticsView.swift`
- `Sources/AgentLensApp/OverviewView.swift`
- `Sources/AgentLensApp/SettingsView.swift`
- `Sources/AgentLensApp/UpdateOperationView.swift`
- `Sources/AgentLensApp/UninstallOperationView.swift`
- `walkthroughs/M12-E-implementation.md`

`git diff --check 1f2b62b..5214d63` exits 0. No diff under `Sources/AgentLensCore`, `Sources/AgentLensAppSupport`, `Sources/agent-lens`, `Package.swift`, `Tests/**`, `scripts/**`, `Resources/**`, or `.github/**`. `ConflictSummaryView.swift` is untouched. The two deletions in the candidate are the stale Uninstall file-comment lines.

## Menu safety

`AgentLensCommands` (`AgentLensApp.swift:188-296`) is the only new command surface. A grep of `confirmSelectedUpdate` / `confirmSelectedUninstall` hits only the pre-existing sheet `onConfirm` closures in `MainWindow.swift:107` and `:132`. Those still go through `runAction` to the model confirm methods. No menu button calls them.

Shortcut table as implemented:

| Item | Shortcut | Call | Disabled when |
|---|---|---|---|
| Settings… | ⌘, | `selectDestination(.settings)` | never (`AgentLensApp.swift:195-199`) |
| Rescan | ⌘R | `rescan()` | `isBusy`, or no focused actions (`:203-207`, `:282-284`) |
| Check for Updates | ⌘U | `checkForUpdates()` | same |
| Refresh Update Metadata | ⌘⇧U | `refreshUpdates()` | same |
| Overview … Settings | ⌘1…⌘7 | the seven `NavigationDestination` cases in `CaseIterable` order (`MainWindow.swift:6-13`) | never |
| Prepare Update… | ⌥⌘U | `prepareSelectedUpdate()` | busy, sheet, or affordance ≠ `.prepareNpmUpdate` (`AgentLensApp.swift:286-289`) |
| Prepare Uninstall… | ⌥⌘⌫ | `prepareSelectedUninstall()` | busy, sheet, or affordance ≠ `.prepareNpmUninstall` (`:291-294`) |
| Verify Installation | ⌥⌘I | `verifySelectedInstallation()` | busy, or selection not winner/off-PATH (`:296-299`) — **sheet omitted** |

Every shortcut carries a modifier. There is no bare U/R/S, no ⌘K, no `Command("c")`, no path item, and no custom Find item. ⌘F stays the `.searchable` shortcut on `OverviewView.swift:47` and `ToolListView.swift:31`. Edit is untouched, so the system ⌘C/⌘X/⌘V/⌘A items remain. There is no second Settings scene; `CommandGroup(replacing: .appSettings)` is the ⌘, item. Default size stays `.defaultSize(width: 960, height: 600)` (`AgentLensApp.swift:311`).

Placement matches the menus: `.appSettings`, `after: .newItem` (File), `after: .sidebar` (View), `CommandMenu("Tool")`.

Actions are `@MainActor` closures. File, prepare, and verify all use the toolbar `runAction` (`MainWindow.swift:162-171`), which returns immediately when `activeActionTask != nil` or `model.isBusy`. Disabled is therefore not the only busy gate. Prepare's affordance bit is `ManagementPresentation(entry:).update == .prepareNpmUpdate` and the uninstall twin (`MainWindow.swift:290-295`), the same frozen model the detail buttons switch on. It is not a re-derived predicate. `canVerifySelection` (`:333-340`) is the same winner/off-PATH split as `InventoryViewModel.observedSelection` (`InventoryViewModel.swift:958-967`): `.winner` and `.offPath` yes; `.notInstalled` and `.inconsistent` no.

Destination changes write `selectedDestination` and nothing else (`MainWindow.swift:297-299` and the sidebar action at `:366-368`). `onChange` calls the existing `applyDestination` (`:250-271`). Scope writes go through `listScope`'s R1 hook. Diagnostics and Settings write only `detailPane`, so ⌘, / ⌘6 / ⌘7 do not change scope and do not invalidate by themselves. The menu does not call `invalidatePendingUpdate`.

Sheet flags used for the prepare gates are the real presentation flags: preview, preparation, outcome, or unavailable (`InventoryViewModel.swift:180-190`).

## VoiceOver and layout (what holds)

List rows were not edited. `ToolListView.swift:270-296` still speaks display name, executable, install state, `category.label`, `version <measured>` or `version unknown`, and conflict kind labels only when non-empty. "Update available" is appended only for `.updateAvailable`. Unknown does not become "up to date".

Section headlines in detail, diagnostics, and settings carry `.isHeader` (detail title plus Installation, Manage, Tool Metadata, Update Status; diagnostics title plus Selection Status, Summary Counts, Canonical Installation Versions, Observed Candidates, and the three candidate subheads; settings Catalogue, Managed Operations, Environment, What Agent Lens Does Not Do). Overview has no headline of its own. The degraded / rescan / update-check banners in Overview, Diagnostics, and Tool Detail are `.accessibilityElement(children: .combine)`, so the spoken label starts with "Degraded Environment", "Rescan Failed", or "Update Check Failed".

Path buttons keep `actionLabel`, which is `"\(verb) \(rowLabel) path for \(toolName)"` (`PathActions.swift:52-53`), and gain the two required hints (`:73`, `:84`). `setFeedback` posts `NSAccessibility.post` on `NSApplication.shared` with `.announcementRequested` and user-info `.announcement` set to the same string the label shows (`:134-148`). Visible feedback strings are unchanged. Ineligibility and feedback text already wrap.

Sheet hints match R10: Cancel "Closes this confirmation without a change."; Update confirm "Applies the reviewed npm update after this confirmation."; Uninstall confirm "Removes the reviewed npm package after this confirmation." Progress labels stay "Update/Uninstall in progress" plus registry ID, package, and prefix. Unavailable labels are `"Update unavailable. \(reason.message)"` and the uninstall twin, so the Core `message` is read, not retyped, and announced on appear. Result titles are labeled and announced as `resultTitle(state)` plus exit status. Preview titles are the visible strings ("Update \(displayName)" / "Uninstall \(displayName)") with `.isHeader` and no replacement label.

Split root is `.frame(minWidth: 760, minHeight: 480)` (`MainWindow.swift:69`). Both sheets stay `.frame(minWidth: 640, minHeight: 500)`. No `preferredColorScheme`, no `windowResizability`, no `.font(.system(size:))`. New wrapping uses `.fixedSize(horizontal: false, vertical: true)`. The only `lineLimit` values in these views are `lineLimit(nil)`.

Sidebar rows set `.accessibilityLabel(destination.rawValue)` and `.accessibilityAction { selectedDestination = destination }` (`MainWindow.swift:363-368`). That is the same write a click makes through the list selection binding. Whether the row now exposes AXPress is an orchestrator/M12-F measurement; the action does not add an invalidation path.

## C-1 and initializers

Both public initializers are still `(preview, outcome, unavailable, isExecuting, isCancelling, onConfirm, onCancel, onDismiss)` (`UpdateOperationView.swift:17-35`, `UninstallOperationView.swift:18-36`). The diff adds `import AppKit` and the announcement helper; it does not add a parameter.

Preview footers have no `.defaultAction`. Cancel is `.keyboardShortcut(.cancelAction)` and `.disabled(isCancelling)`. Confirm Update and the destructive Uninstall Package button have no key equivalent and stay `.disabled(isExecuting || isCancelling)`. Done and Close keep `.defaultAction` on the outcome and unavailable branches only (`UpdateOperationView.swift:66-84`, `UninstallOperationView.swift:67-89`). The Uninstall file comment now says Cancel is the Escape action and the destructive confirmation has no key equivalent (`UninstallOperationView.swift:4-7`). The C-1 footer comment is still accurate.

## Findings

### MEDIUM-1 — Verify Installation stays enabled while a sheet is presented

`AgentLensApp.swift:296-299` and `MainWindow.swift:325-328`.

Plan §5 M12-E (`briefs/M12-plan.md:236`) and R9 (`judgment.md:197-200`) disable all three Tool items when busy, a sheet is presented, or the item is not eligible. Prepare Update and Prepare Uninstall implement that (`AgentLensApp.swift:286-294`, using `isUpdateSheetPresented || isUninstallSheetPresented`). Verify implements only busy plus winner/off-PATH.

The frozen brief's table (`briefs/M12-E-native-accessibility.md:83`) drops the sheet conjunct for Verify and says "busy, or selection not winner/off-PATH". The code matches that table. The brief's own authority line says the plan and R9 are binding, and both of those keep the sheet conjunct for the Tool menu as a group. The table is a narrower quote, not a relaxation I can treat as accepted.

The steady preview state is not busy: prepare has finished, `updatePipeline` is nil, and `isBusy` is false (`InventoryViewModel.swift:175-177`), while `isUpdateSheetPresented` is true because `updatePreview` or `updatePreparation` is set (`:180-183`). The result and unavailable states are the same shape with a nil pipeline. The sheet is modal for the window, not for the menu bar, so Opt-Cmd-I is reachable.

The call is `verifySelectedInstallation()` (`InventoryViewModel.swift:282-287`). Its first line is `invalidatePendingUpdate()`. When no update/uninstall pipeline is running, that method cancels an unconsumed preparation and then nils preview, outcome, and unavailable for both operations (`:656-672`). A launched mutation is spared (`:655`, and the menu is also disabled because executing is busy). So Opt-Cmd-I does not confirm, and `runAction` still coalesces with a confirm click. It does dismiss the confirmation the user is reading, and it also clears a finished result sheet, without Cancel or Done.

Required change: `canVerifyInstallation` must also require `!actions.isSheetPresented`, the same flag Prepare already uses. No AppSupport change. No new invalidation path.

### LOW-1 — Sidebar label drops the badge count

`MainWindow.swift:363`.

`.accessibilityLabel(destination.rawValue)` replaces the row's combined children. The visible name is right, and it avoids speaking the SF Symbol. The badge that `badgeCount` draws (`:389-403`) — conflict tools, installed-in-category, update-available count — is no longer part of the accessible name. The count remains on screen. This is a spoken regression beside the activation fix, not a failed activation.

### LOW-2 — Overview section title "Conflicts" is not a header

`ConflictSummaryView.swift:30-31`.

R10 says section titles in overview are headers. "Conflicts" is a `.headline` and is the only section title on Overview (`OverviewView.swift:69-72` embeds this view). It has no `.accessibilityAddTraits(.isHeader)`. The brief tells the worker not to edit this file unless a label is missing, and the row labels are present (`ConflictSummaryView.swift:76-81`). The worker obeyed that exclusion. The R10 gap is still there. It is pre-existing, not an allow-list violation.

### INFO-1 — File items stay enabled during a sheet

R9's File row disables Rescan, Check, and Refresh only when `isBusy`. The code does that. Those methods already release an unconsumed preview (plan §3: scan/check/refresh/verify invalidate). The menu does not add a second trigger; it calls the same methods as the toolbar, which the sheet used to cover. Recorded so the Verify miss is not confused with this allowed path.

### INFO-2 — Settings states the degraded sentence without the banner title

`SettingsView.swift:93-97`. The Environment section speaks the login-shell sentence, which names the failure, under a header. It is not a combined element titled "Degraded Environment". The titled banners in Overview, Diagnostics, and Tool Detail are. Not a lie.

### INFO-3 — AX and spoken checks are not this review

The sidebar action, the announcement posts, and the new labels are present in source. This review did not dump the AX tree or turn VoiceOver on. The orchestrator's AX read and M12-F own that measurement.

## Conclusion

Accept the menu structure, the prepare gates, the R1 wiring, the C-1 footer, the initializers, the announcement API, and the layout rules. Do not accept the candidate until Verify Installation is disabled while either operation sheet is presented. That is one conjunct on `canVerifyInstallation`. Nothing else in this review requires a product change.
