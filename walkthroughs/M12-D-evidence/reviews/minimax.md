# M12-D independent review — MiniMax (read-only)

**Candidate:** `6c1405a` on `milestone/m12-workflow` (HEAD), frozen.
**Base for the candidate diff:** `2229ddf` (M12-C accepted tip); dispatch-brief commit `d057ea8`.
**Contract:** `briefs/M12-D-operation-journey.md`; `briefs/M12-plan.md` §3, §5 M12-D;
`briefs/M12-planning/judgment.md` R4, R5, R6, R13 (binding, incl. contract decision **C-1**).
**Reviewer:** MiniMax M3.1-Flash, independent, read-only. No product/test/brief file was edited, no
git mutation, no install, no subagent, no destructive fixture. This file is the only write.

## Verdict

**PASS** — 0 blocking, 0 high, 0 medium, 1 low, 4 info.

**C-1 adjudication: SAFE and JUSTIFIED — approve.** The change is implemented exactly as R5 rules
it, it strictly *removes* a keyboard path to a destructive action, it breaks no accepted M10
evidence, and it restores a constraint the accepted M10-D planning record had already required but
the shipped M10-C update sheet had violated. No accepted M10 safety property is weakened; one is
restored.

The candidate renders the frozen `ManagementPresentation` with no view-side eligibility predicate
left, keeps the codex affordances byte-identical, reads every Core reason string through the model
rather than retyping it, adds the R6 progress region without touching stdout, the outcome model,
or any public initializer, and changes nothing outside the three-file allow-list.

---

## 1. C-1 — the named contract change (required adjudication)

### 1.1 Implementation: exactly as ruled

`Sources/AgentLensApp/UpdateOperationView.swift:61-83` (preview branch at :71-81) and
`Sources/AgentLensApp/UninstallOperationView.swift:62-88` (preview branch at :72-86):

| | base (`2229ddf`) | candidate (`6c1405a`) |
|---|---|---|
| Update preview — Cancel | *no shortcut* | `.keyboardShortcut(.cancelAction)` (:75), `.disabled(isCancelling)` unchanged |
| Update preview — "Confirm Update" | **`.keyboardShortcut(.defaultAction)`** | **removed** — no key equivalent (:77-80), `.disabled(isExecuting \|\| isCancelling)` unchanged |
| Uninstall preview — Cancel | **`.keyboardShortcut(.defaultAction)`** | `.keyboardShortcut(.cancelAction)` (:76), `.disabled(isCancelling)` unchanged |
| Uninstall preview — "Uninstall Package" | *no shortcut* | unchanged — still no key equivalent (:78-85), role `.destructive` unchanged |
| RESULT — "Done" | `.defaultAction` | `.defaultAction` kept (:67 / :68) |
| UNAVAILABLE — "Close" | `.defaultAction` | `.defaultAction` kept (:70 / :71) |

So in the preview state of **both** sheets no button holds `.defaultAction`, Cancel is Escape, and
the destructive confirm has no key equivalent. R5's three bullet points are met literally.

I also took the App-wide inventory of key equivalents, which is the decisive check that no
Return-to-confirm path survives anywhere:

```text
Sources/AgentLensApp/UpdateOperationView.swift:67    .keyboardShortcut(.defaultAction)   // result Done
Sources/AgentLensApp/UpdateOperationView.swift:70    .keyboardShortcut(.defaultAction)   // unavailable Close
Sources/AgentLensApp/UpdateOperationView.swift:75    .keyboardShortcut(.cancelAction)    // preview Cancel
Sources/AgentLensApp/UninstallOperationView.swift:68  .keyboardShortcut(.defaultAction)   // result Done
Sources/AgentLensApp/UninstallOperationView.swift:71  .keyboardShortcut(.defaultAction)   // unavailable Close
Sources/AgentLensApp/UninstallOperationView.swift:76  .keyboardShortcut(.cancelAction)    // preview Cancel
```

No other file in `Sources/AgentLensApp/**` contains a `keyboardShortcut` at all. Return therefore
cannot confirm a mutation from anywhere in the app, and the destructive buttons remain reachable
only by Tab + Space or click, exactly as R5 requires.

### 1.2 Is C-1 safe?

Yes, and in the strictly safer direction.

1. **It removes a destructive keyboard path.** In the base, Return in the update preview sheet
   activated "Confirm Update" — a destructive npm mutation, one keystroke away from a reflexive
   Return in a confirmation dialog. C-1 deletes that path. The confirmation now requires a
   deliberate act on the specific destructive control.
2. **It adds exactly one keyboard path, and that path is zero-mutation.** Escape now invokes the
   Cancel button, i.e. `onCancel` → `InventoryViewModel.cancelUpdate()` /
   `cancelUninstall()`. That path releases the unconsumed preparation
   (`service.cancelUpdate(preparation)`) and clears the preview — it never launches a manager
   process. C-1 therefore adds a keyboard route to *stopping* a mutation, not to starting one.
3. **The sheet still closes on Escape.** This is the non-obvious risk of binding Escape to a
   button instead of leaving it to the sheet's implicit dismissal, so I traced it:
   `MainWindow.swift:94-96` / `:119-121` present the sheet with
   `isPresented: model.isUpdateSheetPresented`, and that property
   (`InventoryViewModel.swift:180-183`) is derived from the preview/preparation/outcome/unavailable
   state. `cancelUpdate()` clears the preview and the preparation, so the binding goes false,
   SwiftUI dismisses the sheet, and `onDismiss` → `dismissUpdate()`
   (`InventoryViewModel.swift:476-488`) is then a no-op on already-cleared state. Escape therefore
   still ends in *cancel + sheet closed + zero mutation*, which is the base outcome.
4. **The confirmation pipeline is untouched.** `onConfirm` still calls `confirmSelectedUpdate()` /
   `confirmSelectedUninstall()`, which re-validate every bound fact at execute time and refuse on
   drift (M10 Core). C-1 changes only how the destructive button is *reached*, never what it does.
5. **No accepted M10 property is weakened.** `interactiveDismissDisabled(isExecuting)` is still
   applied by `MainWindow` (untouched file), `disabled(isCancelling)` on Cancel and
   `disabled(isExecuting || isCancelling)` on the confirm button are unchanged, and the button
   titles, roles, and system images are unchanged.

### 1.3 Does it break accepted M10 evidence? — No, verified in the accepted record

The brief asserts "no accepted M10 evidence depends on Return-to-confirm (the M10-D click-through
used AXPress)". I checked that against the accepted walkthroughs rather than taking it on faith:

- `walkthroughs/M10-D-implementation.md:141-153` — the accepted native click-through drove the
  sheet through Accessibility by *activating the buttons*: "2. `Uninstall…` → the destructive sheet
  exposed `Cancel` and `Uninstall Package`", "3. `Cancel` → prefix SHA-256 manifest was
  byte-identical before/after", "4. Fresh `Uninstall…` → `Uninstall Package` → result sheet". No
  Return keypress is recorded anywhere in that journey.
- `walkthroughs/M10-C-implementation.md:141` / `:181` — the accepted update journey is recorded as
  "Check → Prepare → Confirm succeeded `0.165.0 → 0.166.0`", i.e. button activations of Prepare and
  Confirm, not a key equivalent.

So neither accepted M10 artifact depended on the removed Return-to-confirm or Return-to-cancel
paths. The M10-D native journey remains reproducible under C-1.

### 1.4 C-1 restores an already-accepted planning constraint

This is the strongest point in C-1's favour and it is not visible from the dispatch brief alone:
`walkthroughs/M10-D-planning.md:32` records, under "Plan revisions → P1 — coordinator self-review":

> "Required the native destructive confirmation not to be the Return-key default."

The shipped M10-C update sheet **did** make the destructive confirmation the Return-key default
(`.defaultAction` on "Confirm Update" in the base at `2229ddf`), so the accepted M10-D planning
constraint was not honoured by the implementation. C-1 removes that deviation. The uninstall sheet
had complied (its destructive button never held a shortcut; only Cancel was the default).

**Adjudication:** C-1 is a safe, justified, and in fact corrective contract change. It strengthens
the confirmation-retargeting/confirm-before-mutate discipline, makes the two sheets consistent,
breaks no accepted M10 evidence, and resolves a pre-existing drift from the M10-D planning record.
I approve C-1.

---

## 2. R4 — the detail view renders the frozen model

`Sources/AgentLensApp/ToolDetailView.swift:72` computes `ManagementPresentation(entry: entry)` once
and passes it to both slots; the view re-derives **no** eligibility predicate:

- `acceptedOperations.contains` — **gone** from the file (it appears nowhere in the candidate).
- `hasSelectedInstallation(_:)` — **deleted** from the App (`ToolDetailView.swift:272-277` in the
  base) rather than duplicated.
- The remaining `updateStatus` / `npmPackage` references in the file are status-label and
  metadata-grid *displays* of the probe result (`ToolDetailView.swift:469`, `:480`, `:488`, `:513`,
  `:573`, `:650`), not affordance decisions — the same distinction the worker report draws at
  `walkthroughs/M12-D-implementation.md:33-34`. The single remaining `verifiedInstallation` read
  (`ToolDetailView.swift:304`) renders the verified package *name* inside the
  `.prepareNpmUninstall` branch that the model already selected; it decides nothing.

**Codex affordances, byte-identical.**

- Update: `.prepareNpmUpdate` → `ToolDetailView.swift:554-562` renders
  `Label(isPreparingUpdate ? "Preparing Update…" : "Prepare Update…", systemImage: "arrow.down.circle")`,
  action `onPrepareUpdate()`, `.disabled(isBusy)` — identical to the base button
  (`2229ddf:ToolDetailView.swift:527-534`), including the title strings, the system image, and the
  busy rule.
- Uninstall: `.prepareNpmUninstall` → `ToolDetailView.swift:303-323` renders the same
  "Verified npm-global package: …" line, the same
  `Button(role: .destructive) { onPrepareUninstall() }` with
  `Label(isPreparingUninstall ? "Preparing Uninstall…" : "Uninstall…", systemImage: "trash")` and
  `.disabled(isBusy)`, and the same "Prepares an exact preview first…" caption — byte-identical to
  the base.
- `.unavailable(text)` / `.needsVerification(text)` render the model's text as caption/secondary
  wrapping text with **no button** (`ToolDetailView.swift:324-330`, `:564-569`); `.hidden` renders
  `EmptyView()` (`:331`, `:570`).

**Core reason strings are read, never retyped.** `NpmUpdateUnavailableReason.operationNotAccepted.message`
and `NpmUninstallUnavailableReason.operationNotAccepted.message` no longer appear in the App at
all — the only remaining reference to a Core reason enum in the App is
`Sources/AgentLensApp/SettingsView.swift:77`, which *reads* the enum (and is outside D's
allow-list, untouched). The App receives both strings through `ManagementPresentation`
(`Sources/AgentLensAppSupport/WorkflowPresentation.swift:196` and `:217`), which reads them from the
Core enums. The newer-version sentence also comes from the model
(`WorkflowPresentation.swift:175-176`), so the App never retypes any of the four fixed sentences
either.

**Non-npm limits are text, never buttons, and never hide a codex affordance.**
`ToolDetailView.swift:288-294` renders `presentation.otherLimits` through a `ForEach` as
`Text(limit)` — no button, no action. Ordering is the model's (formula → cask → standalone). The
npm block is rendered *before* the limits (`ToolDetailView.swift:280-287`), so for codex both npm
controls appear **and** the cask sentence appears as additional text — the cask sentence cannot
displace or hide the npm button, because the button is emitted solely from the model's
`.prepareNpmUpdate` / `.prepareNpmUninstall` cases.

**grok has no Manage npm block.** `grok` in the shipped registry declares **no** packages at all
(`Sources/AgentLensCore/Detectors/DefaultDetectors.json`: `packages: []`,
`acceptedOperations: none`), so `hasDeclaredNpmPackage(grok)` is false and `ToolDetailView.swift:280`
skips the npm block entirely ✓. See INFO-1 for the exact visible expectation.

**The frozen model was really frozen.** `git diff bf0b832..6c1405a -- Sources/AgentLensAppSupport/
Sources/AgentLensCore/ Sources/agent-lens/ Tests/` returns **empty** — no AppSupport, Core, CLI, or
test file changed across M12-B, M12-C, and M12-D, and
`git diff 64a5056..6c1405a -- Sources/AgentLensAppSupport/WorkflowPresentation.swift` is empty, so
the model I reviewed in M12-A is byte-for-byte the model D consumes.

---

## 3. R6 — the in-sheet progress region

`UpdateOperationView.swift:87-89` and `UninstallOperationView.swift:92-94` render the region
inside the preview body, before the preview grid (R6 allows above or below):

- `ProgressView()` plus "Update in progress" / "Uninstall in progress"
  (`UpdateOperationView.swift:135-138`, `UninstallOperationView.swift:139-142`), and the preview's
  `registryID`, `packageName`, and `prefix` — all three fields exist on both Core previews
  (`Sources/AgentLensCore/Operations/OperationModels.swift:27-41` and `:291-304`), so the region is
  bound to the *prepared* preview, not to a re-derived or live fact.
- The three-condition rule holds exactly: the region is inside `previewView`, which is reached only
  when `preview != nil`; and the body's branch order is
  `if let outcome → resultView; else if let preview → previewView; else if let unavailable →
  unavailableView` (`UpdateOperationView.swift:40-46`, `UninstallOperationView.swift:41-47`), so
  when `outcome != nil` the result view is the only body and the progress region is not shown
  alongside it. When `unavailable != nil` and there is no preview/outcome, the unavailable view is
  the only body ✓.
- **No stdout subscription** — the region renders only static preview facts; nothing in either
  file reads process output. **No new `OperationState` case** — no Core change at all. **No new
  initializer parameter** — see §4.

---

## 4. Public initializers stay source-compatible

Both sheets' public `init` blocks are untouched (`UpdateOperationView.swift:16-34`,
`UninstallOperationView.swift:17-35`): same eight parameters, same names, same types, same order;
`git diff` shows no hunk in either declaration. `ToolDetailView`'s initializer is likewise
untouched (only private view builders were added).

The protected M10-D host constructs the sheet exactly as before —
`Tests/Fixtures/M10D/npm_uninstall_acceptance.py:480-481` and `:499-500`:

```swift
UninstallOperationView(preview: preparation.preview, outcome: nil, unavailable: nil,
    isExecuting: false, isCancelling: false, onConfirm: {}, onCancel: {}, onDismiss: {})
```

which still matches the current initializer parameter-for-parameter. `git diff --name-only
2229ddf..6c1405a -- Tests/` returns **empty** — the fixture was not edited, and nothing under
`Tests/**` changed at all.

---

## 5. R13 — mutation controls stay in the detail view

`Sources/AgentLensApp/ToolListView.swift` is untouched by D. Its only update-status logic is
display text — `ToolListView.swift:293-295` appends "Update available" to an accessibility label;
there is no prepare button in a list row, and no new prepare entry point was added anywhere. The
journey remains Updates → select tool → detail → Prepare ✓.

No retained per-tool operation history was added (deferred by R13) ✓.

---

## 6. R12 — zero Core/AppSupport/CLI/registry/fixture change

```text
git diff --name-only 2229ddf..6c1405a
  Sources/AgentLensApp/ToolDetailView.swift
  Sources/AgentLensApp/UninstallOperationView.swift
  Sources/AgentLensApp/UpdateOperationView.swift
  briefs/M12-D-operation-journey.md            (orchestrator dispatch-brief commit d057ea8)
  walkthroughs/M12-D-implementation.md         (the allow-listed worker report)
```

Exactly the three production files in the allow-list, plus the dispatch brief and the worker report.
No `Sources/AgentLensAppSupport/**`, no `Sources/AgentLensCore/**`, no `Sources/agent-lens/**`, no
`Package.swift`, no `Tests/**`, no `Tests/Fixtures/**`, no `Tests/Packaging/**`, no `scripts/**`, no
`.github/**`, no `Resources/**`, no `docs/**`, no `DECISIONS.md` / `ROADMAP.md` /
`AGENT_LENS_SCOPE.md`, and no other App file (`MainWindow.swift`, `ToolListView.swift`,
`OverviewView.swift`, `ConflictSummaryView.swift`, `SettingsView.swift`, `DiagnosticsView.swift`,
`PathActions.swift`, `OwnershipVerificationView.swift`, `AgentLensApp.swift` are all untouched). No
new dependency, no new `AcceptedOperation` case, no CLI mutation syntax.

`git diff --check 2229ddf..6c1405a` → exit 0 ✓. The AppSupport count is 119 (I recounted: 10 + 16
+ 31 + 8 + 24 + 7 + 23) and Core is untouched at 467 ✓.

---

## 7. Severity-ranked findings

### BLOCKING — none
### HIGH — none
### MEDIUM — none

### LOW

**LOW-1 — Escape becomes an explicit, consumed key target in the Update sheet; the orchestrator's
key-equivalent proof must assert "cancels AND closes the sheet", not only "does not confirm".**
`Sources/AgentLensApp/UpdateOperationView.swift:75`. In the base, the Update sheet's Cancel had no
shortcut, so Escape reached the sheet's implicit dismissal (`onDismiss` → `dismissUpdate()`,
`InventoryViewModel.swift:476-479`). In the candidate, Escape is claimed by the Cancel button's
`.cancelAction` and runs `onCancel` → `cancelUpdate()` instead. The user-visible outcome is the same
— the preparation is released with zero mutation and the sheet closes, because
`isUpdateSheetPresented` (`InventoryViewModel.swift:180-183`) is derived from the
preview/preparation/outcome/unavailable state that `cancelUpdate()` clears — but the code path
differs, and `.cancelAction` *consumes* the key rather than letting it fall through to the sheet's
dismissal. This is not a defect: cancelling is the safe direction, the action already existed as a
visible enabled button, and no destructive capability is added. It is flagged only so the
orchestrator's native proof exercises the full outcome (Escape → preview released, sheet closed,
no process launched) rather than only "Return does not confirm".

### INFO

**INFO-1 — grok's spot-check expectation should be stated precisely.**
`Sources/AgentLensApp/ToolDetailView.swift:99`. grok declares no packages and its registry fixture
expects source `"standalone"`, so grok renders **no npm block** ✓ — but if installed, it now also
renders a Manage section whose only content is the standalone sentence ("This copy is classified as
standalone. Agent Lens does not delete standalone files."), because `otherLimits` is emitted for any
installed tool. The correct observation for the spot-check is therefore "grok has **no Manage npm
block**; it shows the standalone sentence only" — a literal reading of "grok shows nothing" would
be wrong. This follows R4 ("standalone (fixed sentence)") and the D brief's wording, and it is
disclosed in the worker report (`walkthroughs/M12-D-implementation.md:52-53`).

**INFO-2 — the "Manage" heading now appears over text-only content.**
`Sources/AgentLensApp/ToolDetailView.swift:99`, `:278-296`. For a formula-only, cask-only, or
standalone tool, the section reads "Manage" followed by an explanatory sentence and offers no
control. D's allow-list contains no other surface, so the limit sentences have nowhere else to
live; the heading is a minor cosmetic artifact of a contract-forced placement, not a defect. M12-E
may want to reconsider the heading wording for a section that never offers a control.

**INFO-3 — the accessibility labels on the progress region land in D rather than in M12-E.**
`Sources/AgentLensApp/UpdateOperationView.swift:155-158` and
`Sources/AgentLensApp/UninstallOperationView.swift:159-162` add `.accessibilityElement(children:
.combine)` with a combined label. R10/M12-E owns accessibility labels and these two files are in
E's allow-list, so this is a small scope overlap — harmless and arguably necessary for the region to
be perceivable at all — but M12-E should not be surprised to find labels already present, and should
verify the combined label does not swallow the preview grid's own semantics.

**INFO-4 — nothing in CI protects the C-1 footer state.**
The App has no test target (R12 forbids adding one), so the single most safety-critical UI property
in this milestone — "Return never confirms a mutation" — is verified only by inspection plus the
orchestrator's native key-equivalent proof. A later refactor could re-add
`.keyboardShortcut(.defaultAction)` to the confirm button and the whole suite would stay green. The
first automated guard will be M12-E's keyboard gate (R10). Worth carrying forward explicitly so the
property is not treated as unowned after M12-F.

---

## 8. Residual risks and forward notes

1. **M12-E / M12-F should re-verify the C-1 property mechanically.** The R10 real-key-event gate is
   the natural place, and the M12-F journey matrix should include "Return does not confirm" for
   both sheets, not only for the update sheet.
2. **M12-E should check the new "Manage" text-only sections under large text and narrow windows.**
   The limit sentences use `.fixedSize(horizontal: false, vertical: true)` and no truncating
   `lineLimit` ✓ (R12), but their first appearance under a heading is new in this milestone.
3. **The frozen model is doing all the work.** `ToolDetailView` now contains no eligibility
   predicate at all, which is exactly the R4 intent; any future change to what is offered must go
   through `Sources/AgentLensAppSupport/WorkflowPresentation.swift` (frozen for M12-D, and the
   review focus of M12-A). A future phase that needs a new affordance must not re-derive it in the
   App.
4. **The evidence is about this exact tree.** All three committed file SHA-256 values match the
   worker report's manifest exactly (`8dde3555…`, `3c9d696f…`, `6f0fd735…`), so the reviewed tree
   is the tree the worker measured. The worker report is correctly labeled WORKER EVIDENCE and
   claims no acceptance; it also discloses that no native sheet was keyboard-driven by the worker
   and that the destructive journey was not run — both are the orchestrator's to perform.

---

## 9. Reproducible checks performed

```text
git rev-parse HEAD                                     → 6c1405a7cbe247947185ffbcb3d7d745e7867fe8
git branch --show-current                              → milestone/m12-workflow
git diff --name-only 2229ddf..6c1405a                 → 3 product files + brief + worker report
git diff --name-only bf0b832..6c1405a -- Sources/AgentLensAppSupport/ Sources/AgentLensCore/
                                                          Sources/agent-lens/ Tests/   → empty
git diff 64a5056..6c1405a -- Sources/AgentLensAppSupport/WorkflowPresentation.swift → empty (frozen)
git diff --name-only 2229ddf..6c1405a -- Tests/       → empty (M10-D fixture untouched)
git diff --check 2229ddf..6c1405a                     → exit 0
shasum -a 256 of the 3 changed App files               → identical to the worker report manifest
grep -rn "keyboardShortcut" Sources/AgentLensApp/*.swift → exactly 6 hits, all accounted for above
grep -n "acceptedOperations\|hasSelectedInstallation" Sources/AgentLensApp/ToolDetailView.swift
                                                          → no matches (predicates removed)
grep -c "@Test" Tests/AgentLensAppSupportTests/*.swift → 119 total (467 Core untouched)
```

Read but not executed: `Tests/Fixtures/M10D/npm_uninstall_acceptance.py:480`, `:499` (initializer
call sites). No build, no test suite, no destructive fixture, and no product file was touched by
this reviewer.
