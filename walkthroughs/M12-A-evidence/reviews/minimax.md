# M12-A independent review — MiniMax (read-only)

**Candidate:** `64a5056` on `milestone/m12-workflow` (HEAD), frozen.
**Base for the candidate diff:** `14e5f30` (dispatch-brief commit; product base `1f251d4`).
**Contract:** `briefs/M12-A-presentation-foundation.md`; `briefs/M12-plan.md` §3, §5 M12-A;
`briefs/M12-planning/judgment.md` R1, R2, R3, R4, R8, R12, R16.
**Reviewer:** MiniMax M3.1-Flash, independent, read-only. No product/test/brief file was edited,
no git mutation, no install, no subagent. This file is the only write.

## Verdict

**PASS** — 0 blocking, 0 high, 0 medium, 3 low, 4 info.

The candidate implements R1/R2/R3/R4/R8/R12 as written, keeps the confirmation-retargeting
invariant intact in both directions (every mandated trigger fires, `detailPane` does not, and a
launched mutation is never cancelled), reproduces the `ToolDetailView` affordance predicates
exactly, reads every Core refusal string from the Core enums, and touches nothing outside the
allow-list. The three low findings are test-pinning and forward-scoping observations, not defects
in the shipped behavior. Nothing here blocks acceptance of M12-A.

---

## 1. Method and scope of inspection

Read-only Git: `git show 64a5056`, `git diff 14e5f30..64a5056`, `git diff --name-only`,
`git diff --check 14e5f30..64a5056`, `git rev-parse HEAD`, `git branch --show-current`.

Files read in full or by focused excerpt: `Sources/AgentLensAppSupport/WorkflowPresentation.swift`
(new), `Sources/AgentLensAppSupport/InventoryViewModel.swift`, `Sources/AgentLensAppSupport/InventorySnapshot.swift`,
`Tests/AgentLensAppSupportTests/WorkflowPresentationTests.swift` (new),
`Tests/AgentLensAppSupportTests/InventoryViewModelTests.swift` (new tests),
`Sources/AgentLensApp/ToolDetailView.swift` (the predicates that must be reproduced),
`Sources/AgentLensApp/MainWindow.swift` (sheet bindings), and the read-only Core facts
`Sources/AgentLensCore/Diagnostics/PathDiagnostics.swift`,
`Sources/AgentLensCore/Diagnostics/InstallationVersionObservation.swift`,
`Sources/AgentLensCore/Operations/OperationModels.swift`,
`Sources/AgentLensCore/Detection/DetectorMetadata.swift` / `ToolDetector.swift`,
`Sources/AgentLensCore/Detectors/DefaultDetectors.json`.

No build and no test suite was run (the orchestrator's independent rerun is authoritative).
One read-only lint was run independently — `python3 scripts/check-core-ui-imports.py --source-root
Sources/AgentLensAppSupport` → exit 0, "6 Swift file(s) … no SwiftUI/AppKit imports" — to confirm
R12's import guard rather than take the report's word for it. No fixture, registry, cache, manager,
or personal path was touched.

---

## 2. Contract-by-contract verification

### R1 — navigation + invalidation: **satisfied**

Four mandated triggers, each verified in source *and* pinned by a test:

| Vector | Implementation | Test |
|---|---|---|
| `listScope` | `InventoryViewModel.swift:105-109` (`didSet` → `invalidatePendingUpdate()`) | `InventoryViewModelTests.swift:1429` |
| `updateStatusFilter` | `InventoryViewModel.swift:113-117` | `InventoryViewModelTests.swift:1450` |
| `searchText` | `InventoryViewModel.swift:97-101` (pre-existing, unchanged) | `InventoryViewModelTests.swift:1482` |
| selection-ID | `InventoryViewModel.swift:221-223` (`select` invalidates only when the ID differs) | `InventoryViewModelTests.swift:1500` |

- **Pure `detailPane` change does NOT invalidate.** `InventoryViewModel.swift:120` declares
  `detailPane` with no observer at all; pinned by `InventoryViewModelTests.swift:1545`
  (preview and preparation survive `.diagnostics` and `.settings`).
- **A launched mutation is never cancelled by these.** The executing early-return at
  `InventoryViewModel.swift:655` (`if isExecutingUpdate || isExecutingUninstall { return }`) is
  byte-identical to the base — `git diff` shows no hunk anywhere in `invalidatePendingUpdate`
  (base :615-677 → candidate :649-711; only line numbers moved). The early return precedes both
  the generation bump (:675-676) and the pipeline cancellation, so a scope/filter/search/selection
  change during execution neither bumps the generation nor cancels the running pipeline. Pinned
  twice: `InventoryViewModelTests.swift:1616` (update) and `:1680` (uninstall) park a gated runner
  inside the destructive command, apply all four changes, and assert the operation is still
  executing, that `updateOutcome`/`uninstallOutcome` are still nil, and that the preview identity
  stays bound to `codex-id`.
- **Outcome/preview identity stays bound to the original registry ID.** Verified in source, not
  only in the test: `confirmSelectedUpdate` (`InventoryViewModel.swift:405-443`) captures the
  consumed `preparation` and publishes `result.outcome` — the preparation's own preview — with the
  only completion guard being `generation == self.updateGeneration` (:421). Because the executing
  early-return skips the generation bump, a concurrent selection change cannot void it, and nothing
  in the completion path re-reads `selectedEntry`.
- **No missed vector.** I checked the other paths that can move `selectedRegistryID`:
  `reconcileSelection` (`InventoryViewModel.swift:939-949`) writes it directly, but only inside a
  scan whose `run()` already calls `invalidatePendingUpdate()` (`InventoryViewModel.swift:724`);
  `select` is the only user-facing mutation of the selection. A scope change during an in-flight
  *prepare* is also safe: `prepareSelectedUpdate` is generation-guarded
  (`InventoryViewModel.swift:365-374`), and `invalidatePendingUpdate` bumps `updateGeneration`
  when a pipeline is live, so a late preparation result is discarded and its preparation is
  cancelled (`service.cancelUpdate`) instead of being published — released with zero mutation.
- **`showPathEvidence(registryID:)`** (`InventoryViewModel.swift:244-247`): refuses an unpublished
  ID *before* touching selection or pane; for the already-selected ID `select` does not invalidate
  (same-ID guard at :221) so the pending preview survives; for a different ID it invalidates and
  then selects, then sets `.diagnostics`. Pinned at `InventoryViewModelTests.swift:1564`, `:1581`,
  `:1599`.
- **Sheets bind to preview/preparation, never `selectedEntry`.** `MainWindow.swift:91` and `:116`
  already bind `preview: model.updatePreview ?? model.updatePreparation?.preview` plus
  `outcome:`/`unavailable:`; the only `selectedEntry` uses in the App are the detail view
  (`MainWindow.swift:243`, `:275`), which is not a sheet. The App is unchanged in this phase, so
  this contract holds without a single App edit.

### R2 — Updates scope: **satisfied**

- `ListScope.updates.includes` excludes `installState == .notInstalled`
  (`WorkflowPresentation.swift:33-36`).
- `UpdateStatusFilter` narrows by tri-state exactly as ruled (`WorkflowPresentation.swift:57-74`):
  `.updateAvailable` / `.upToDate` / `.unknown` match the optional status case; `.notChecked` is
  `entry.update == nil`; `.all` narrows nothing. Because an unknown outcome is a non-nil result
  carrying `.unknown`, the `.unknown` and `.notChecked` cells are disjoint — pinned at
  `WorkflowPresentationTests.swift:436-437`.
- Order of operations in `filteredEntries` (`InventoryViewModel.swift:201-212`) is
  scope → (only under `.updates`) status filter → search, registry order preserved, no sort.
- **Unknown is neutral.** `updateAvailableCount` (`InventorySnapshot.swift:98-103`) counts only
  `.updateAvailable`; unknown and up-to-date never inflate it — pinned at
  `WorkflowPresentationTests.swift:440-468` and again at the ViewModel level
  (`InventoryViewModelTests.swift:1809-1811`).
- The required "an unknown whose name matches the query is still absent under `.updateAvailable`"
  case is genuinely pinned: `InventoryViewModelTests.swift:1791-1795` sets filter `.updateAvailable`
  **and** query `"beta"` and asserts the list is empty — the unknown row stays absent even though
  its name matches.

### R3 — conflict classification: **satisfied, non-vacuous**

`WorkflowPresentation.swift:103-117` implements exactly the three kinds, in the ruled order
(`shadowedCopy` → `offPathCopy` → `inconsistentDiagnostics`), from the diagnostic only:

- `shadowedCopy` ⇔ `(diagnostic.shadowedInstallationCount ?? 0) > 0` (:105-107);
- `offPathCopy` ⇔ `selection == .offPath` (:109-110);
- `inconsistentDiagnostics` ⇔ `selection == .inconsistent` (:111-112);
- `.winner` and `.notInstalled` contribute nothing (:113-114).

Record fields per R3 (`WorkflowPresentation.swift:120-149`): `copyCount = canonicalTargetCount`
(:127), `localVersions` from `installationVersions` with `.measured` outcomes only and unknown
observations dropped (:129-132), `winnerEntryPath` only for `.winner`, `offPathRoot` only for
`.offPath`, `inconsistencyReason` only for `.inconsistent` with no invented winner (:133-148).

Non-vacuity is real, not tautological: single copy → no conflict
(`WorkflowPresentationTests.swift:205-212`); inconsistent with nil shadowed → exactly
`.inconsistentDiagnostics` with the stored reason and no winner path (:241-256); off-PATH with
positive shadowed → both kinds in ruled order (:258-285); alias-only and repeated-slot fixtures →
no kind, and the closed vocabulary is asserted as
`ToolConflictKind.allCases == [.shadowedCopy, .offPathCopy, .inconsistentDiagnostics]` (:287-303);
not-installed → no conflict (:305-311); a latest version present in the update result is proven
absent from `localVersions` (:313-342); the count counts tools, not kinds (:344-372, two kinds on
one tool ⇒ `conflictToolCount == 2` for two tools). Aliases and repeated slots are read nowhere in
the kind derivation ✓; `notInstalled` is not a kind ✓.

### R4 — ManagementPresentation: **satisfied, byte-identical to the current controls**

I reproduced the current `ToolDetailView` predicates and compared them line by line.

*Update slot* — App: `ToolDetailView.swift:523-539` shows the button only when
`case .updateAvailable = entry.updateStatus` **and** `entry.update?.npmPackage != nil`, and inside
that block shows the Core refusal text when `.npmUpdate` is not accepted; otherwise nothing.
Candidate: `WorkflowPresentation.swift:193-201` gives `.prepareNpmUpdate` (accepted) /
`.unavailable(NpmUpdateUnavailableReason.operationNotAccepted.message)` (not accepted) / the fixed
newer-version sentence / `.hidden`. The two refusal strings are **read from the Core enums, never
retyped** (`WorkflowPresentation.swift:196` and `:217` reference
`NpmUpdateUnavailableReason.operationNotAccepted.message` and
`NpmUninstallUnavailableReason.operationNotAccepted.message`); the four fixed sentences live as
named constants at `WorkflowPresentation.swift:175-184` and are asserted verbatim in the tests
(`WorkflowPresentationTests.swift:495-497`, `:514-516`, `:533-535`, `:548-550`, `:584-588`).

*Uninstall slot* — App: `ToolDetailView.swift:280-311` shows the Core refusal text when
`.npmUninstall` is absent, the prepare button when accepted **and** verified-npm **and** a selected
installation, else the "Verify Installation…" text; and the whole Manage section is rendered only
for npm-declaring tools (`ToolDetailView.swift:96`). Candidate: `WorkflowPresentation.swift:205-222`
reproduces all four cases including the npm-declared gate (`.hidden` when no npm package is
declared) — verified against the App's render guard, so `.hidden` is behaviorally identical to the
App showing no Manage section at all. Pinned by
`WorkflowPresentationTests.swift:470-498` (codex), `:591-613`, `:670-683`, `:685-716`, `:718-725`.

*`otherLimits`* — `WorkflowPresentation.swift:226-236`: only when `installState != .notInstalled`,
each manager at most once, in the fixed order formula → cask → standalone, and only for
`source == "standalone"`. The npm source adds no standalone sentence
(`WorkflowPresentationTests.swift:553-573`).

*codex affordances unchanged* — the shipped registry entry for `codex`
(`Sources/AgentLensCore/Detectors/DefaultDetectors.json`: packages `npm` + `homebrewCask`,
accepted `npmUpdate` + `npmUninstall`) is mirrored exactly by the candidate's codex fixture
(`WorkflowPresentationTests.swift:472-498`), where the cask sentence is **additional** text and
both npm controls are still offered (`update == .prepareNpmUpdate`, `uninstall == .prepareNpmUninstall`).
No sentence names an unshipped manager's command: grep for `brew upgrade|brew uninstall|uv|pip|cargo|self-updater`
over `WorkflowPresentation.swift` returns nothing.

### R8 — search predicate: **satisfied**

`matches` is byte-identical to the base predicate — `git diff` shows the function only shifted
(base :938-960 → candidate :972-994), with the same haystack (display name, executable name,
registry ID, entry path, resolved path, candidate entry paths and canonical targets, and the
selection's entry path / off-PATH root) and the same `contains` test. No category label, no
package name, no sorting. Pinned from both sides at `InventoryViewModelTests.swift:1836-1854`
("AI Agent" and "beta-formula" match nothing; "codex" matches only `codex-id`).

### R12 — zero Core/CLI/registry change: **satisfied**

`git diff --name-only 14e5f30..64a5056` returns exactly six paths:
`Sources/AgentLensAppSupport/{InventorySnapshot,InventoryViewModel,WorkflowPresentation}.swift`,
`Tests/AgentLensAppSupportTests/{InventoryViewModelTests,WorkflowPresentationTests}.swift`,
`walkthroughs/M12-A-implementation.md`. Filtering for `Sources/AgentLensCore`, `Sources/agent-lens`,
`Package.swift`, `scripts/`, `.github/`, `Tests/Fixtures`, `Tests/Packaging`, `Resources/`, `docs/`,
`DECISIONS.md`, `ROADMAP.md`, `AGENT_LENS_SCOPE.md` returns **nothing**. No new dependency; no
`AcceptedOperation` case; `InventoryService.swift`, `PathActionTarget.swift`, and
`SessionEnvironmentProvider.swift` are untouched. `Sources/AgentLensApp/**` has zero diff, so the
app is visually unchanged as the phase requires.

AppSupport imports: the new file imports `AgentLensCore` only (`WorkflowPresentation.swift:13`);
no SwiftUI/AppKit anywhere (independently re-ran the guard, exit 0).

### R16 / gates / evidence integrity

- The candidate is `64a5056` on `milestone/m12-workflow` ✓. `git diff --check 14e5f30..64a5056`
  exits 0 ✓. The missing trailing newline at the end of `InventorySnapshot.swift` is **pre-existing**
  (the base file's last bytes are identical) — not introduced here.
- **The committed tree is the tree the worker measured.** All five SHA-256 values in
  `walkthroughs/M12-A-implementation.md:138-142` match the committed files at `64a5056` exactly
  (recomputed independently). The evidence is therefore about this candidate, not a different tree.
- AppSupport test count: the file set now yields 118 `@Test` cases (23 new in
  `WorkflowPresentationTests.swift`, 15 new in `InventoryViewModelTests.swift`, 80 pre-existing),
  matching the reported 118 and the orchestrator's rerun. Core is untouched, so 467 holds.

---

## 3. Severity-ranked findings

### BLOCKING — none

### HIGH — none

### MEDIUM — none

### LOW

**LOW-1 — The "status filter applies only when `listScope == .updates`" clause is implemented but not pinned by any test.**
`Sources/AgentLensAppSupport/InventoryViewModel.swift:201-212` correctly guards the filter behind
`guard listScope == .updates else { return true }`. No test exercises a non-`.all`
`updateStatusFilter` while the scope is *not* `.updates` and then asserts the list is unaffected:
`InventoryViewModelTests.swift:1784-1816` keeps the scope at `.updates` for the whole test, and
`:1450-1479` sets `.notChecked` under `.all` but asserts only the preview release, never the list.
Consequence: a future regression that applies the status filter unconditionally (i.e. dropping the
scope guard) would pass the whole suite. The implementation is correct today; this is a pinning gap
in a contract clause the brief states explicitly ("applies only when `listScope == .updates`").
Suggested fix (one assertion, not blocking): under `listScope = .all`, set
`updateStatusFilter = .updateAvailable` and assert both fixture tools remain listed.

**LOW-2 — "not installed is not a conflict" holds only implicitly, and no test would catch a hand-built diagnostic that breaks it.**
`WorkflowPresentation.swift:103-117` derives the kinds from `shadowedInstallationCount` and
`selection` alone; it never consults `installState`. For every diagnostic Core actually produces
this is safe, because Core derives `shadowedInstallationCount = 0` for `.notInstalled`
(`Sources/AgentLensCore/Diagnostics/PathDiagnostics.swift:242-251`) — but that coupling is
undocumented in the model and untested at the boundary: the negative test
(`WorkflowPresentationTests.swift:305-311`) uses `shadowed: 0`. A fixture that paired
`state: .notInstalled` with a positive shadowed count would yield a conflict record for a tool
that is not installed. R3's rule is satisfied in production; the gap is only in explicit pinning.

**LOW-3 — The update slot's "newer version" sentence has no counterpart in the current `ToolDetailView`; M12-D will add a visible sentence where the app is silent today.**
`WorkflowPresentation.swift:197-198` returns
`"A newer version is reported by the supported latest check. Managed update is not available for this installation in this version."`
when the status is `.updateAvailable` and `npmPackage` is nil. The current App renders **nothing**
in that case (`Sources/AgentLensApp/ToolDetailView.swift:523-539` — the whole block is inside the
`npmPackage != nil` condition), so this is the one place where R4's "reproduce the current
predicates EXACTLY" and R4's own enumerated third bullet diverge. The candidate followed the
enumeration, which is the binding, more specific text, and it is also what R4 intends ("a
formula-only tool such as `hermes` gets a truthful unavailable explanation today it lacks"), so
this is **not** an M12-A defect. It is flagged because M12-D will render this string for the first
time, and that is a user-visible app change that M12-D's "codex button predicates byte-identical"
acceptance should be checked against deliberately rather than discovered.

### INFO

**INFO-1 — The "off-PATH with positive shadowed ⇒ both kinds" case is unreachable from Core.**
Core derives `shadowedInstallationCount = 0` for an `.offPath` selection
(`Sources/AgentLensCore/Diagnostics/PathDiagnostics.swift:242-251`), so a real diagnostic can only
ever yield `.offPathCopy` alone. The rule and its test
(`WorkflowPresentationTests.swift:258-285`) are correct and future-proof against a Core change,
but the test exercises a synthetic diagnostic. Noted so M12-C's acceptance does not expect a live
two-kind row.

**INFO-2 — `ToolConflict.localVersions` is a flat, unattributed list of version strings.**
`WorkflowPresentation.swift:129-132` flattens `installationVersions` to `[String]` with no
canonical-target association. That satisfies R3 as written ("the measured local versions from
`diagnostic.installationVersions`"), and version skew is visible. But M12-C's conflict rows live in
`Sources/AgentLensApp/**`, whose allow-list contains no AppSupport file, so if the row ever needs
"copy A: 2.0.0, copy B: 1.0.0" rather than "2.0.0, 1.0.0", A is the phase that would have had to
expose it. Worth confirming with the M12-C dispatch rather than discovering mid-phase.

**INFO-3 — The worker report states the AppSupport floor as 117 in one place and 118 in another.**
`walkthroughs/M12-A-implementation.md:86` says 118 (correct — I recounted 118 `@Test` cases) while
`:154` says "raised to a measured 117". 117 was the RED-run count before the last test was added.
The report is correctly labeled WORKER EVIDENCE and makes no acceptance claim; this is a
transcription slip only.

**INFO-4 — `updateStatusFilter` invalidates even while the scope is not `.updates`.**
`InventoryViewModel.swift:113-117` fires the hook on any change of the filter, regardless of
whether the filter currently narrows anything. R1's trigger list names `updateStatusFilter`
unconditionally, so this is compliant; the direction of the error is the safe one (over-releases a
preview rather than under-releases), and the candidate documented the decision
(`walkthroughs/M12-A-implementation.md:36-37`). Recorded so that M12-C/M12-E do not assume the
filter is inert outside the Updates destination.

---

## 4. Test-quality assessment (the non-vacuity requirement)

The brief demanded a seeded-corruption test proving the trigger set is non-vacuous. The candidate
provides `InventoryViewModelTests.swift:1519-1542` (`seededPendingPreviewDiesOnlyOnATrigger`),
and it is genuinely discriminating: the preview is seeded by the accepted
`prepareSelectedUpdate` path, the test first asserts that the *non-triggers* (`detailPane`,
setting `listScope` to its existing value, re-selecting the same ID) leave the preparation and
preview intact, and only then asserts that a real scope change destroys them. Remove the
`listScope` `didSet` hook and the final `#expect(viewModel.updatePreparation == nil)` fails —
the test is not satisfied by "eventually nil", and the comment at :1532-1534 says so explicitly.

Each of the other three triggers has its own dedicated test that would fail if its hook were
removed, and `pureDetailPaneChangeKeepsThePendingPreview` (:1545) would fail if `detailPane` ever
acquired an invalidation hook. Both halves of the executing exemption are pinned separately
(:1616 update, :1680 uninstall), so removing either half of the
`isExecutingUpdate || isExecutingUninstall` guard fails a test. The "no mutation pipeline started"
requirement is pinned by a counting operation runner whose invocation count is asserted to be 0
in every invalidation-vector test. No existing test was weakened — the diff to
`InventoryViewModelTests.swift` is purely additive (556 added lines, 0 removed).

---

## 5. Residual risks and forward notes (not findings against this candidate)

1. M12-D inherits LOW-3: rendering `ManagementPresentation` will surface the newer-version sentence
   in a spot where the app is currently silent. It must not be allowed to displace or re-word the
   codex affordances.
2. M12-C inherits LOW-1's subject matter: the Updates filter control binds A's
   `updateStatusFilter`, whose scope-conditioning is correct but unpinned — worth adding the
   missing assertion before C changes that filter's rendering.
3. M12-C inherits INFO-2: the conflict row's version display is limited to what A exposed.
4. `ManagementPresentation`'s fixed sentences are module-internal `static let`s
   (`WorkflowPresentation.swift:175-184`); M12-D receives them inside the enum cases, so the App
   never needs to re-derive or re-type them. The Core refusal strings are read from the enums at
   both call sites — the one thing the App must not do is re-type them, and M12-D's allow-list
   keeps the strings inside `ManagementPresentation`.
5. `detailPane` and `listScope` are currently written by no App code (the App is untouched this
   phase, by design). M12-B is the phase that wires them, and R1's invalidation hooks will fire
   from the first real sidebar switch — the behavior is therefore already live in the model, and
   the App must not add a second invalidation path in B.

---

## 6. Reproducible checks performed

```text
git rev-parse HEAD                                  → 64a5056c80b3ab2c78521288bc15565b9b50268b
git branch --show-current                           → milestone/m12-workflow
git diff --name-only 14e5f30..64a5056              → 6 paths, all inside the §2 allow-list
git diff --name-only 14e5f30..64a5056 | grep -E "AgentLensCore|agent-lens|Package.swift|
                                                    scripts/|\.github|Tests/Fixtures|
                                                    Tests/Packaging|Resources/|docs/"  → empty
git diff --check 14e5f30..64a5056                  → exit 0
git show 14e5f30:…/InventoryViewModel.swift  vs candidate "static func matches"  → byte-identical
git diff 14e5f30..64a5056 -- …/InventoryViewModel.swift  → no hunk in invalidatePendingUpdate
python3 scripts/check-core-ui-imports.py --source-root Sources/AgentLensAppSupport
                                                    → exit 0, 6 files, no SwiftUI/AppKit
shasum -a 256 of the 5 changed product/test files   → identical to the worker report's manifest
grep -nE "brew upgrade|brew uninstall|\buv\b|\bpip\b|cargo" WorkflowPresentation.swift → no match
```

No product, test, brief, or walkthrough file was modified; no git state was changed; no build or
test suite was executed by this reviewer.
