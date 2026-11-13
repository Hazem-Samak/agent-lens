# M12-A independent review — Grok (read-only)

**Candidate:** `64a5056` (`feat(workflow): M12-A presentation-state foundation candidate`) on `milestone/m12-workflow`. Parent of the diff is `14e5f30`.
**Contract:** `briefs/M12-A-presentation-foundation.md`; `briefs/M12-plan.md` §3 and §5 M12-A; `briefs/M12-planning/judgment.md` R1, R2, R3, R4, R8, R12, R16.
**Reviewer:** Grok, independent, read-only. No product, test, or brief file was edited. No git mutation, no install, no subagent. This file is the only write. Builds and tests were not re-run; the orchestrator's green rerun (Core 467 + AppSupport 118, guard 21, packaging 9, both import guards clean) is taken as the execution record. This review is source inspection against that record.

## Verdict

**PASS** — 0 blocking, 0 high, 0 medium, 2 low, 3 info.

R1's confirmation-retargeting invariant holds in both directions: every mandated trigger releases a pending preview, a pure `detailPane` change does not, and a launched update or uninstall is not cancelled. R3's three kinds are the only kinds and the count counts tools. R4's slots match the current `ToolDetailView` controls for every shipped detector, and both `operationNotAccepted` strings are read from the Core enums. R8's `matches` haystack is untouched. The diff is inside the allow-list. The two low findings are unpinned negative cases, not wrong behavior.

## What was inspected

`git diff --name-status 14e5f30..64a5056` is exactly:

- `Sources/AgentLensAppSupport/InventorySnapshot.swift` (modified)
- `Sources/AgentLensAppSupport/InventoryViewModel.swift` (modified)
- `Sources/AgentLensAppSupport/WorkflowPresentation.swift` (new)
- `Tests/AgentLensAppSupportTests/InventoryViewModelTests.swift` (additions only; `git diff` has zero deleted lines)
- `Tests/AgentLensAppSupportTests/WorkflowPresentationTests.swift` (new)
- `walkthroughs/M12-A-implementation.md` (the allowed worker report)

`git diff --check 14e5f30..64a5056` exits 0. A path filter for `Sources/AgentLensCore`, `Sources/agent-lens`, `Sources/AgentLensApp`, `Package.swift`, `scripts`, `.github`, `Tests/Fixtures`, `Tests/Packaging`, `Resources`, `docs`, `DECISIONS.md`, `ROADMAP.md`, and `AGENT_LENS_SCOPE.md` is empty. `InventoryViewModel.swift` is +39/−5, and those five deletions are the old `filteredEntries` comment and the old `return entries` / `entries.filter` lines. `invalidatePendingUpdate` and `matches` are not in the diff; they only moved.

Compared, not just the new files: `ToolDetailView.swift` (Manage `:268-311`, Update button `:523-539`), `MainWindow.swift` sheet bindings (`:90-93`, `:115-118`), `PathDiagnostics.swift` `PathSelection` and `shadowedInstallationCount` (`:78-83`, `:242-251`), `InstallationVersionObservation.swift`, `VersionStatus.swift`, `OperationModels.swift` (`:89`, `:334`), `DetectorMetadata.swift`, `ToolDetector.classifySource` (`:187-190`), and `DefaultDetectors.json` (only `codex` has `acceptedOperations`).

## R1 — confirmation retargeting: held, no missed vector

| Vector | Where | What it does |
|---|---|---|
| `listScope` | `InventoryViewModel.swift:105-109` | `didSet` calls `invalidatePendingUpdate()` only when the value differs |
| `updateStatusFilter` | `InventoryViewModel.swift:113-117` | same, and the hook is not conditioned on the current scope |
| `searchText` | `InventoryViewModel.swift:97-101` | pre-existing hook, unchanged |
| selection ID | `InventoryViewModel.swift:221-223` | `select` invalidates only when `registryID != selectedRegistryID` |
| `detailPane` | `InventoryViewModel.swift:120` | stored property, no observer |
| executing mutation | `InventoryViewModel.swift:649-655` | `isTearingDownMutation` return, then `if isExecutingUpdate \|\| isExecutingUninstall { return }` before any generation bump or `cancel()` |

`filteredEntries` (`:201-210`) is `entries` → `listScope.includes` → (only when `listScope == .updates`) `updateStatusFilter.includes` → existing `matches`, with `filter` and no sort. A hidden row keeps its selection because nothing in those `didSet`s writes `selectedRegistryID`.

`showPathEvidence` (`:244-248`) refuses an unknown ID before `select`, so a bad ID does not release a preview and does not move the pane. A published ID goes through `select` (invalidates only when the ID differs) and then sets `detailPane = .diagnostics`. The pane assignment cannot invalidate, because `detailPane` has no hook. Same-ID evidence keeps the preview. That is the safe direction of the "mirror `select`" sentence: `select` itself still invalidates before its unknown-ID guard (`:222` then `:231`), which is the pre-existing trigger and was not changed.

Other writers of `selectedRegistryID` were checked and are not a pending-preview hole:

- `reconcileSelection` (`:939-948`) assigns the ID directly and does not call `invalidatePendingUpdate`. Its callers are `publish`, `publishClearedUpdates`, `publishOwnership`, and `clearOwnership`.
- `run` (`:724`) and `verifySelectedInstallation` (`:283`) invalidate before they publish. A pending preparation is already released before reconciliation can move the ID.
- `clearOwnership` and the post-execute `publish` run while `isExecutingUninstall` / `isExecutingUpdate` is still true (`:576-583`, `:423-426`). They must not cancel. They don't, because they never enter `invalidatePendingUpdate`.
- Completion does not re-read `selectedEntry`. `confirmSelectedUpdate` (`:418-426`) publishes `result.outcome` under `generation == self.updateGeneration` only. The executing early-return skips the generation bump, so a selection change during the gated command cannot void the outcome. The uninstall path is the same shape (`:573-575`).

Sheets already bind to preview / preparation / outcome / unavailable, not `selectedEntry`. `isUpdateSheetPresented` (`:180-183`) and `isUninstallSheetPresented` (`:188-190`) are those four slots. `MainWindow.swift:90-93` and `:115-118` pass `model.updatePreview ?? model.updatePreparation?.preview` (and the uninstall twin). This phase does not touch the App, and it does not regress that binding. `ToolDetailView` still receives `selectedEntry`, which is the detail column, not the confirmation sheet.

The launched-operation tests park the destructive runner and then apply scope, filter, search, and selection (`InventoryViewModelTests.swift:1633-1641` and `:1764-1772`). They assert the executing flag stays true, the outcome stays nil until release, and the preview registry ID stays `codex-id` after the selection has moved to `beta-id`. That is the retargeting invariant: the sheet identity does not follow the new selection.

## R2 — Updates membership: held

`ListScope.updates.includes` is `installState != .notInstalled` (`WorkflowPresentation.swift:33-35`). The status filter (`:57-74`) is `.updateAvailable` / `.upToDate` / `.unknown` by the optional case, and `.notChecked` by `entry.update == nil`. Unknown is not up to date and is not "not checked". `updateAvailableCount` (`InventorySnapshot.swift:98-102`) is unchanged and still counts only `.updateAvailable`, so an unknown does not inflate the badge. Counts live on the snapshot; `InventoryViewModel.updateAvailableCount` (`:169`) reads that, so a search or filter cannot move it.

`InventoryViewModelTests.swift:1795-1801` sets `.updateAvailable`, then searches `"beta"`, and expects an empty list. Beta is the neutral/unknown row, so a name match does not pull it into the update-available filter. The pure membership tests are `WorkflowPresentationTests.swift:376-438`.

## R3 — conflict kinds: held, and the negatives are real

`ToolConflictKind` is exactly `shadowedCopy`, `offPathCopy`, `inconsistentDiagnostics` in that order (`WorkflowPresentation.swift:79-83`). `kinds(for:)` (`:102-117`) appends shadowed when `(shadowedInstallationCount ?? 0) > 0`, then off-PATH, then inconsistent. `.winner` and `.notInstalled` add no kind. `sameTargetAliasCount` and `repeatedPathSlotCount` are not read.

The record (`:120-149`) copies `canonicalTargetCount`, keeps only `.measured` outcomes in observation order, sets `winnerEntryPath` only for `.winner` (`candidate.entryPath`), `offPathRoot` only for `.offPath`'s root (the enum is `offPath(candidate:root:)`, and the test locks the root string), and `inconsistencyReason` only for `.inconsistent`. No winner path is invented for an inconsistent selection.

`conflictToolCount` (`InventorySnapshot.swift:115-117`) counts entries whose kind list is non-empty. One tool with two kinds counts once. `WorkflowPresentationTests.swift:344-371` builds a two-kind entry, a one-kind entry, and a clean entry and expects `2`, which fails if the count summed kinds.

The required negatives are non-vacuous:

- Single canonical target, shadowed `0` → no record (`:205-212`).
- Alias count `2` and repeated slots `3` on that same single-target winner → still no record (`:287-303`). If either count became a kind, this fails. `allCases` is pinned to the three-kind order.
- Inconsistent with `shadowed: nil` → `[.inconsistentDiagnostics]`, stored reason preserved, both paths nil (`:241-256`).
- Off-PATH plus shadowed `1` → `[.shadowedCopy, .offPathCopy]` (`:258-285`).
- Measured `"1.0.0"`, an unmeasured sibling, and an update whose latest is `"9.9.9"` → `localVersions == ["1.0.0"]` (`:313-341`). A latest leak or an unknown-outcome leak fails this.

Core's scanner sets `shadowedInstallationCount` to `0` for `.offPath` and `.notInstalled`, and to `nil` for `.inconsistent` (`PathDiagnostics.swift:242-251`). The both-kinds row is therefore a synthetic diagnostic. That is what R3 asks the pure function to do: classify the fields it is given, and not re-derive the scanner. A live off-PATH tool is `.offPathCopy` alone. See INFO-1 and LOW-2.

## R4 — ManagementPresentation: held for shipped tools

Update slot (`WorkflowPresentation.swift:193-201`), compared with `ToolDetailView.swift:523-539`:

- `.updateAvailable` and `entry.update?.npmPackage != nil` and `.npmUpdate` accepted → `.prepareNpmUpdate` (the view's button).
- Those same facts and `.npmUpdate` absent → `.unavailable(NpmUpdateUnavailableReason.operationNotAccepted.message)`. The string is the enum property, not a literal. A repo search of AppSupport for the Core sentence "not yet accepted" finds nothing.
- `.updateAvailable` and `npmPackage == nil` → the fixed newer-version sentence (`:175-176`). The view is silent here. The brief's third update bullet requires the sentence. See INFO-2.
- Otherwise `.hidden`. Not-checked, up to date, and unknown grow no update affordance (`WorkflowPresentationTests.swift:637-668`).

Uninstall slot (`:205-222`), compared with `ToolDetailView.swift:284-309` inside the `hasDeclaredNpmPackage` gate (`:96-98`, predicate `:268-270`):

- Accepted `.npmUninstall`, `verifiedInstallation?.manager == .npm`, selection `.winner` or `.offPath` → `.prepareNpmUninstall`.
- Declared npm and `.npmUninstall` absent → the Core uninstall `operationNotAccepted.message` (`:217`). The test at `WorkflowPresentationTests.swift:670-683` keeps verified npm ownership in place, so operation-not-accepted wins over the prepare branch. That matches the view, which checks `!contains(.npmUninstall)` first.
- Accepted and the verified-npm condition false (unverified, verified non-npm, or inconsistent selection) → the view's exact sentence "Verify Installation to enable Uninstall for this npm package." (`:218`, tests `:685-716`).
- No declared npm and the operation not accepted → `.hidden` (`:718-725`).

`hasSelectedInstallation` (`:205-211`) is the same four-case split as `ToolDetailView.hasSelectedInstallation` (`:272-277`).

`otherLimits` (`:225-236`) appends only when `installState != .notInstalled`, at most once, in the order formula, cask, standalone. The three sentences match the brief character for character (`:179-184`). `source == "npm"` does not add the standalone sentence (`WorkflowPresentationTests.swift:553-558`). `source == "standalone"` matches `ToolDetector.classifySource`, which returns that literal (`ToolDetector.swift:187-190`). No sentence names uv, pip, cargo, `brew upgrade`, `brew uninstall`, or a self-updater.

Codex, the only shipped detector with accepted operations (`DefaultDetectors.json:14-18`: npm `@openai/codex`, cask `codex`, both npm operations), is the fixture at `WorkflowPresentationTests.swift:472-498`: both prepare cases, plus the cask sentence as additional text. The cask sentence does not replace either npm slot. A formula-only and a cask-only entry offer no prepare case (`:500-536`).

## R8 — search predicate: unchanged

`matches` (`InventoryViewModel.swift:972-994`) is not in the diff. The haystack is still display name, executable name, registry ID, detected entry and resolved paths, each candidate's entry path and canonical target, and the winner entry path or the off-PATH entry path plus root. Category label and package name are absent. `ToolCategory.aiAgent.label` is `"AI Agent"` (`DetectorMetadata.swift:51-56`). `InventoryViewModelTests.swift:1844-1852` searches `"AI Agent"` and `"beta-formula"` and expects an empty list, then `"codex"` and expects only `codex-id`. Adding either excluded field fails that test. Category scope then search is an intersection (`:1818-1832`); registry order is the filter order.

## R12 — zero Core/CLI/registry change: held

The new file imports `AgentLensCore` only (`WorkflowPresentation.swift:13`). AppSupport has no `import SwiftUI`, `AppKit`, or `Cocoa`. `InventoryViewModel.swift:26` still imports `Observation`, which was already there and is not a UI kit. No `Package.swift` edit, no new dependency, no `AcceptedOperation` case. `Sources/AgentLensApp/**` has no diff, so the running app is visually unchanged. `@Test` functions under `Tests/AgentLensAppSupportTests` recount to 118 (38 new: 15 view-model + 23 presentation; 80 existing, including the `@Test("…")` cases in `PathActionTests.swift` and `BundleResourceTests.swift`). That matches the orchestrator's AppSupport 118. Core is untouched, so 467 holds.

## Tests are non-vacuous where the brief required a seeded failure

`seededPendingPreviewDiesOnlyOnATrigger` (`InventoryViewModelTests.swift:1519-1541`) seeds a real `prepareSelectedUpdate` preparation, then applies three non-triggers (`detailPane = .diagnostics`, `listScope = .all` which is already the value, `select` of the same ID) and asserts the preparation and preview are still present. It then sets `listScope = .category(.aiAgent)` and asserts both are nil and `isBusy` is false.

Removing the `listScope` `didSet` call to `invalidatePendingUpdate()` makes that last assertion fail: the preparation is still non-nil. The comment at `:1529-1531` has the direction backwards (it says a removed hook would make the last assertion pass because the preview would already be gone). The assertions do the opposite. The test is discriminating.

The four vector tests (`:1429`, `:1450`, `:1482`, `:1500`) each require a non-nil preparation first, then require preparation nil, preview nil, outcome nil, not executing, not busy, and `VMCountingOperationRunner.invocations == 0`. That runner increments on every `run()` (`:1185-1198`), which is the destructive command. A trigger that started a mutation fails the counter. The filter test's second half (`:1469-1478`) re-prepares under `listScope = .all` and then changes the filter, so the trigger is the filter change itself and not "the row disappeared."

`updatesScopeListsInstalledEntriesAndNarrowsByTriState` does not itself contain a not-installed row. The exclusion is pinned on the pure function the view model calls: `WorkflowPresentationTests.swift:383-384`, `!ListScope.updates.includes(notInstalled)`.

## Findings

### Blocking — none

### High — none

### Medium — none

### Low

**LOW-1 — The "status filter applies only while `listScope == .updates`" guard is correct and unpinned.**

`InventoryViewModel.swift:203-205` returns the scoped entry before consulting `updateStatusFilter` unless the scope is `.updates`. No test sets a non-`.all` filter while the scope is `.all` or `.category` and then asserts the list is unchanged. `InventoryViewModelTests.swift:1784-1816` stays on `.updates` for every membership assertion. `:1471-1476` sets `.notChecked` under `.all`, but only asserts that the preview was released.

Dropping the `listScope == .updates` guard would still pass the suite: under `.all`, `.updateAvailable` would hide beta, and nothing checks that list. Suggested pin, not a behavior fix: with both fixture tools installed and the scope `.all`, set `updateStatusFilter = .updateAvailable` and expect both registry IDs.

**LOW-2 — `notInstalled` suppresses a conflict only because Core publishes `shadowedInstallationCount == 0`, and the negative test uses that shape.**

`WorkflowPresentation.swift:103-116` never reads `installState`. A hand-built `.notInstalled` selection with `shadowedInstallationCount > 0` becomes `[.shadowedCopy]`. That follows the kind rule `shadowedInstallationCount ?? 0 > 0` and does not follow an absolute reading of "a not-installed tool is never a conflict." Core cannot publish the counterexample: `PathDiagnostics.swift:246-247` forces the count to `0` for `.notInstalled`. `WorkflowPresentationTests.swift:305-311` uses `notInstalledDiagnostic()`, which sets `shadowed: 0` (`:122-124`). The production invariant holds. The test would not catch a future classifier that treated a poisoned not-installed diagnostic as a conflict, nor one that special-cased `installState` the other way. No code change is required for R3 as written.

### Info

**INFO-1 — Off-PATH plus a positive shadowed count is synthetic.**

Core sets `shadowedInstallationCount = 0` for `.offPath` (`PathDiagnostics.swift:248-249`). A real off-PATH tool is `.offPathCopy` only. `WorkflowPresentationTests.swift:258-285` is still the right pin for the pure function. M12-C should not expect a live two-kind row from today's scanner.

**INFO-2 — The newer-version update sentence is new text relative to today's detail view, and it is the sentence the brief requires.**

`WorkflowPresentation.swift:197-198` returns the fixed "A newer version is reported by the supported latest check…" sentence when status is `.updateAvailable` and `npmPackage` is nil. `ToolDetailView.swift:523-525` shows nothing in that case, because the whole block sits inside `npmPackage != nil`. The dispatch brief's update-slot bullets require this sentence, and R4's point is that a formula-only tool gets an explanation the view does not show yet. M12-A does not render it (the App is untouched). M12-D, when it renders `ManagementPresentation`, will show that sentence for the first time. Codex is unaffected: it has an npm package, and its prepare/unavailable split matches the current button.

The uninstall slot's "no declared npm package → `.hidden`" bullet is the residual `else` (`WorkflowPresentation.swift:220-221`), not an outer conjunct of `.prepareNpmUninstall` or `.needsVerification`. A constructible definition that accepts `.npmUninstall`, declares no npm package, and has verified npm ownership on a winner would get `.prepareNpmUninstall`, while `ToolDetailView` would not render Manage at all (`:96`). The shipped registry cannot do this: the only `acceptedOperations` entry is `codex`, which declares npm. The bullet order in the brief lists prepare and needs-verification without a declared-package conjunct, and the code follows that order. No change.

**INFO-3 — The worker report's floor sentence says 117. The candidate is 118.**

`walkthroughs/M12-A-implementation.md:64` records the GREEN run as 118 tests. `:154` says the floor was raised to 117, which is the RED count from before `launchedUninstallSurvives…` was added (`:67-68`). The report is labeled worker evidence. The committed tree's `@Test` count is 118. This is a transcription slip, not a product defect.

## Residual notes (not findings)

`InventorySnapshot.swift` still has no trailing newline. The base blob at `14e5f30` also has no trailing newline, so this commit did not introduce it, and `git diff --check` is clean.

`updateStatusFilter`'s `didSet` invalidates even when the scope is not `.updates` (`InventoryViewModel.swift:113-117`). R1 names that field as a trigger with no scope condition. Over-releasing a pending preview is the safe direction.

Direct `select` of an unknown ID still invalidates before refusing (`:222-231`). `showPathEvidence` does not (`:245`). Keeping the preview when the selection does not change is the retargeting rule. The pre-existing `select` quirk was required to stay.

## Conclusion

Accept M12-A at `64a5056`. The safety invariant is implemented on the existing `invalidatePendingUpdate` path, the executing early-return is unchanged, and the new presentation values do not invent conflict kinds, versions, or Core refusal text. LOW-1 and LOW-2 are pins worth adding later; they do not block this phase.
