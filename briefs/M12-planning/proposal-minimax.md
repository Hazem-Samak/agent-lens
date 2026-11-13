# M12 — complete native diagnostic and operation workflow: council proposal

Council member: **MiniMax M3.1-Flash / xhigh (mcode)**. Written independently, 2026-11-13.
Authority: `briefs/M12-planning/council-brief.md`. Output file: this file only.

Nothing in this proposal was executed, built, or launched. Every code claim below is a
**static read** of the working tree at `milestone/m11-catalogue` tip `0589fac` with the file:line
citation given. Where I could not verify something by reading, I say so explicitly and mark it
`unverified`. I did not read `proposal-grok.md`.

---

## 0. Summary for the judge

**Six phases** (M12-A … M12-F) on the single milestone branch `milestone/m12-workflow`.

**The single most important technical conclusion of this audit:** the M10 confirmation-retargeting
invariant is currently enforced by *four* explicit call sites in `InventoryViewModel`, and M12
introduces **five new ways to change what is selected or displayed**. If the implementer adds a
category filter, an update filter, a sidebar destination switch, and an Updates-destination action
without extending that trigger set, a pending preview can survive a change that should have
released it. That is the highest-severity defect this milestone can ship, and M12-A exists
specifically to close it before any new surface is built. Details in §C.5.

**Second conclusion:** there is **no capability model in the product code at all.** `grep -rn
"apability" Sources/` returns nothing; `docs/capability-matrix.md` is a *Markdown document*
enforced by a test (`Tests/AgentLensCoreTests/CapabilityMatrixTests.swift`), not a type. The
"capability-driven UI" that M13–M15 must reuse therefore has to be built in M12 — in **AppSupport**,
never in Core, and it must be a *new* vocabulary, not a reinterpretation of the npm-specific
`NpmUpdateUnavailableReason` / `NpmUninstallUnavailableReason` enums.

**Third conclusion:** the M8 keyboard gate cannot be closed by an AX *press* action. AXPress
bypasses keyboard activation entirely. The measurement must post **real key events** and observe
focus traversal. §F.1 specifies that method.

---

## A. Current-state audit

### A.1 Council-brief §3 claims, verified

| §3 claim | Verdict | Evidence |
|---|---|---|
| Sidebar has exactly two destinations, Inventory and Diagnostics | **Verified** | `Sources/AgentLensApp/MainWindow.swift:6-11` (`NavigationDestination` has exactly `inventory` and `diagnostics`); `:193` renders `NavigationDestination.allCases`; `:227-234` `destinationIcon` switches over exactly those two; `:238-280` `detailView` switches over the same two. No Overview, no per-category destination, no Updates, no Settings, no conflict summary anywhere in `Sources/`. |
| `ToolListView` already has `.searchable` over `model.filteredEntries` | **Verified** | `Sources/AgentLensApp/ToolListView.swift:25-29` (`.searchable(text: $model.searchText, placement: .toolbar, prompt: "Search name, executable, or path")`); `Sources/AgentLensAppSupport/InventoryViewModel.swift:181-185` derives `filteredEntries` from `searchText`; match predicate at `:938-960`. |
| Counts exist in toolbar/sidebar | **Verified** | `MainWindow.swift:199-203` sidebar badge `installedToolCount/knownToolCount`; `:321-328` toolbar `knownToolCount`, `installedToolCount`, `updateAvailableCount`. Sources: `InventorySnapshot.swift:88` (`knownToolCount` = entry count = definitions), `:92-94` (`installedToolCount` counts `installState != .notInstalled`, i.e. `installedNotOnPath` counts), `:98-103` (`updateAvailableCount` counts **only** `.updateAvailable` — unknown never inflates). |
| `ToolDetailView` carries M8 Copy Path / Reveal in Finder on both path rows | **Verified** | `ToolDetailView.swift:224-234` renders the two `GridRow`s "Selected Entry" and "Resolved Target" through `pathActionRow`; `:411-435` builds the row; `Sources/AgentLensApp/PathActions.swift:56-104` renders both buttons (`:65-73` Copy Path, `:75-83` Reveal in Finder), both `.disabled(!target.isActionable)`. |
| M9 ownership verification present | **Verified** | `ToolDetailView.swift:245-255` → `Sources/AgentLensApp/OwnershipVerificationView.swift:11-222`; eligibility rule at `ToolDetailView.swift:257-264`. |
| M10 Update/Uninstall preparation + confirmation/progress/output/result sheets | **Verified** | `ToolDetailView.swift:280-311` (Manage / Uninstall), `:523-539` (Update); sheets wired at `MainWindow.swift:87-136` into `UpdateOperationView` / `UninstallOperationView`. |
| Registry has 14 entries, 3 categories, only `codex` carries `acceptedOperations` | **Verified** | `Sources/AgentLensCore/Detection/DetectorMetadata.swift:46-58` `ToolCategory` = `aiAgent`/`aiCodingTool`/`aiHarness`; `:78-81` `AcceptedOperation` closed vocabulary `npmUpdate`/`npmUninstall`; `docs/capability-matrix.md:26-41` lists exactly 14 rows with only `codex` (row at `:28`) claiming `yes: npm`, every other row `informational: no accepted mutation scenario (M11)`. |
| Every other entry is informational with a Core reason surfaced in app/CLI | **Verified (app)** / **partially verified (CLI)** | App: `ToolDetailView.swift:284-287` and `:534-538` render `Npm*UnavailableReason.operationNotAccepted.message`. CLI: `Sources/agent-lens/main.swift` — I did **not** read the CLI's reason-rendering branch line by line; the M11-B acceptance record (`walkthroughs/M11-B-acceptance.md:76`) records CLI mutation rendering as *vacuous by ruling (D-022)*. Treat CLI mirroring as **not applicable** for M12. |
| Shipping CLI dispatches only `scan`, `verify-installation`, `debug-env` | **Verified** | `Sources/agent-lens/main.swift:61-63` (`case "scan"`), `:114-116` (`case "verify-installation"`), `:160-163` (`case "debug-env"`). No other command case exists. |
| Local suite 547 (467 Core + 80 AppSupport); CI floors match | **Verified from CI config, not re-measured** | `.github/workflows/ci.yml:193-197` (Core floor 467, AppSupport floor 80, `total_floor` 547, `combined_total_floor` 547), `:154` ("M11-F final (measured at this candidate): 547 = Core 467 + AppSupport 80"), `:181` guard-fixtures floor 21, `:207` packaging floor 9, `:585-586` the seven gate names. I did not run the suite (read-only constraint). |
| Core stays UI-free | **Verified as an enforced gate** | `scripts/check-core-ui-imports.py` (CI gate `guard`) and `Tests/Packaging/test_core_ui_imports.py` (21 behavioral fixtures, `ci.yml:181`). |
| M8 keyboard-only Copy/Reveal measurement is OPEN and is a required M12 gate | **Verified** | `briefs/README.md:56` and `:73`; `DECISIONS.md:286` ("Native keyboard-only activation remains unverified, not a passed gate") and `:287`; `ROADMAP.md:43` ("M8 keyboard check remains open") and `:101`. |

### A.2 Findings the council brief did **not** list (verified, and they shape the plan)

**F-1 — There is no App test target.** `Package.swift:40-43` declares `AgentLensApp` as an
`executableTarget`; the only test targets are `AgentLensCoreTests` (`:25-28`) and
`AgentLensAppSupportTests` (`:35-38`). `Tests/Packaging/` holds Python checks, not Swift tests.
Consequence: **anything M12 adds to the SwiftUI layer has no automated test surface.** The
M11-B reviewers already hit this (F-5 in `walkthroughs/M11-B-acceptance.md:42-43`: "No App test
target exists (`Package.swift` protected)… The orchestrator's native spot-check is the App-mirror
evidence"). *Design consequence:* all M12 logic that can be tested **must live in AppSupport**,
and the App layer stays a thin mirror. See OD-M12-6.

**F-2 — The two operation sheets disagree about the Return key.**
`Sources/AgentLensApp/UpdateOperationView.swift:74-78` gives **"Confirm Update"**
`.keyboardShortcut(.defaultAction)`, so **Return executes a mutation**.
`Sources/AgentLensApp/UninstallOperationView.swift:73-75` gives **"Cancel"**
`.keyboardShortcut(.defaultAction)`, and the destructive "Uninstall Package" button (`:76-83`) has
**no** key equivalent. So Return confirms an Update but cancels an Uninstall. The council brief
requires that shortcuts "must never execute a mutation directly". This is a real, citable
inconsistency and it must be fixed in M12-D as a *named* contract decision (§D.4).

**F-3 — Availability logic is npm-specific and lives in the view.**
`ToolDetailView.swift:268-270` (`hasDeclaredNpmPackage`), `:284` (npm-uninstall acceptance),
`:523-526` (npm-package + npm-update acceptance). `Sources/AgentLensCore/Operations/OperationModels.swift:54-94`
and `:317-339` are npm-only reason enums. There is **no manager-agnostic availability type in
Core** (verified: no `capability` identifier anywhere under `Sources/`). M12 must introduce one in
AppSupport.

**F-4 — The D-021 Core gate is correctly fail-closed and early.**
`Sources/AgentLensCore/Operations/NpmUpdateOperation.swift:61-64` — the acceptance guard is the
**second** statement, immediately after the cancellation check and **before** any scratch-root
claim, observation, or runner use. `NpmUninstallOperation.swift:51-54` is identical. This is the
contract M12 must not weaken.

**F-5 — The invalidation trigger set is currently four call sites.**
`InventoryViewModel.swift:99` (`searchText.didSet`), `:197` (`select`), `:249`
(`verifySelectedInstallation`), `:690` (`run` — covers launch/rescan/check/refresh). The
implementation is `invalidatePendingUpdate()` at `:615-677`, which (a) releases an unconsumed
preparation with zero mutation, (b) cancels in-flight preparation pipelines, and (c) at `:621`
**explicitly does not** invalidate a *launched* operation. That last part is the M10 contract and
must be preserved exactly.

**F-6 — Post-operation output is not reviewable after the sheet closes.**
`InventoryViewModel.swift:442-454` `dismissUpdate()` clears `updateOutcome`, `updatePreview` and
`updateUnavailableReason`; `:600-612` does the same for Uninstall. The M10 journey lets you
"review output" **only while the sheet is open**. M12's user result says "review output" as a step
in the journey, so a retained, per-tool last-operation summary is a genuine ADD (§D.3).

**F-7 — There are no native menus and no app commands.**
`Sources/AgentLensApp/AgentLensApp.swift:158-167` declares exactly one `Window` scene with
`.defaultSize(width: 960, height: 600)` and **no `.commands` modifier**. So: no menu bar at all
beyond the default app menu, no ⌘-shortcuts, no `Settings` scene. Also note **no window minimum
size** is set — relevant to the narrow-window requirement.

**F-8 — Operation sheets have no accessibility labels.**
`UpdateOperationView.swift` and `UninstallOperationView.swift` contain no `.accessibilityLabel`,
`.accessibilityHint`, `.accessibilityValue` or announcement calls anywhere. The preview `Grid`
rows (`UpdateOperationView.swift:89-100` / `UninstallOperationView.swift:94-106`), the stdout/stderr
output panes (`UpdateOperationView.swift:182-203` / `UninstallOperationView.swift:198-219`), the
reconciliation delta (`UpdateOperationView.swift:166-180` / `UninstallOperationView.swift:169-197`),
and the unavailable view (`UpdateOperationView.swift:127-135`) are all unlabeled. By
contrast `ToolListView.swift:104-105,146-163`, `PathActions.swift:72,82,100` and
`OwnershipVerificationView.swift:86,92` *do* carry labels. The VoiceOver spoken-check requirement
therefore has real work to do in M12-E, not just new-surface labeling.

**F-9 — Transient path-action feedback is visible but not announced.**
`PathActions.swift:95-101` renders the feedback `Text` with `.accessibilityLabel(feedback)`. A
label on an unmanaged `Text` is *not* a live announcement; a VoiceOver user is not told "Copied
path to clipboard." without moving focus. §E.4 specifies the announcement fix.

**F-10 — Fixed hues are used for state.**
`ToolDetailView.swift:119,138,157,391` (`.orange`), `OwnershipVerificationView.swift:66`
(`.green`), `ToolListView.swift:124` (`.orange`), `DiagnosticsView.swift:189,235`
(`.orange`), plus `Color.secondary.opacity(...)` panel backgrounds. Fixed hues do not adapt to
appearance. Mitigation: the *text* always carries the meaning (e.g. "Installed, off PATH",
"Consistency Failure: …"), so §E.6 makes color decoration-only and forbids removing text.

**F-11 — No window minimum size; sheets have a hard minimum.**
`AgentLensApp.swift:165` sets only a *default* size. `UpdateOperationView.swift:58` and
`UninstallOperationView.swift:59` set `.frame(minWidth: 640, minHeight: 500)` — a **minimum**, so
the sheets cannot be narrower than 640 pt, which is fine, but the *window* has no floor and
`NavigationSplitView` will compress the detail column to nothing.

**F-12 — `DiagnosticsView` already carries every fact the conflict summary needs.**
`Sources/AgentLensCore/Diagnostics/PathDiagnostics.swift:85-97` — `ToolPathDiagnostic` exposes
`pathCandidates`, `targetGroups`, `repeatedPathSlotCount`, `sameTargetAliasCount`, `selection`,
`shadowedInstallationCount: Int?`, `installationVersions`; `:121` `liveCandidates`, `:125`
`invalidCandidates`, `:129` `distinctLiveEntryPathCount`, `:133` `canonicalTargetCount`. And
`DiagnosticsView.swift:243-282` already renders the counts. **No Core change is needed for the
conflict summary.** This is the single most useful fact for bounding M12-C.

### A.3 ADD / CHANGE / PRESERVE

**ADD**

| Item | Why M12 needs it | Citation |
|---|---|---|
| Seven-destination navigation | ROADMAP §4 M12 user result names Overview / AI Agents / AI Coding Tools / AI Harnesses / Updates / Diagnostics / Settings | `ROADMAP.md:95` |
| Overview destination (dashboard) | "make the complete catalogue understandable" | `ROADMAP.md:95` |
| Per-category destinations and counts | scope §7 filter list; `ToolCategory` exists but is only shown in one detail row | `ToolDetailView.swift:324-327` |
| Update-status filter | ROADMAP §4: "Add category/update filters, counts" | `ROADMAP.md:97` |
| Conflict summary | ROADMAP §4: "a conflict summary that leads to per-installation PATH evidence and versions" | `ROADMAP.md:97` |
| Package/source details in list rows | same requirement; today only in the detail view | `ToolDetailView.swift:218-222,330-334` |
| Updates destination | ROADMAP §4 M12 user result | `ROADMAP.md:95` |
| Settings destination (minimal, truthful) | ROADMAP §4 M12 user result; "Settings only control delivered features" | `ROADMAP.md:95,100` |
| Native menus / commands | ROADMAP §4: "Finish native menus, keyboard navigation/shortcuts" | `ROADMAP.md:100` |
| Capability-driven availability model | "Future manager capabilities use the same capability-driven UI" | `ROADMAP.md:98` |
| Retained last-operation summary | journey step "review output" is currently only possible with the sheet open | `InventoryViewModel.swift:442-454,600-612` |
| Keyboard-activation evidence for Copy/Reveal | required M12 gate | `ROADMAP.md:101` |

**CHANGE (minimal, deliberate)**

| Change | Justification |
|---|---|
| `NavigationDestination` grows from 2 to 7 cases | `MainWindow.swift:6-11`; the icon switch (`:227-234`) and detail switch (`:238-280`) are exhaustive, so this is compiler-checked |
| `InventoryViewModel` gains filter + destination state; `invalidatePendingUpdate()` gains 5 new triggers | §C.5 — the retargeting invariant |
| `matches(...)` haystack gains category label and declared package names | "find" must work on the facts the new surfaces show; selection is still excluded (`InventoryViewModel.swift:938-960`) |
| `UpdateOperationView` / `UninstallOperationView` footer key equivalents normalized | F-2 — Return must never execute a mutation |
| ToolDetailView's npm-specific availability branches replaced by the AppSupport capability model | F-3 — one source of truth; the **rendered Core reason text stays byte-identical** |
| Window minimum size added | F-11 |
| Announcement of transient path-action feedback | F-9 |
| CI floors raised (never lowered) to orchestrator-measured counts | `ci.yml:152-157` |

**PRESERVE (do not redo accepted work)**

- Local-first launch: `InventoryViewModel.swift:223-226` (`launch()` runs only from `.idle`, local
  facts only, no manager command, no cache read, no update probe). ✔ already satisfied.
- Search: `ToolListView.swift:25-29` + `InventoryViewModel.swift:181-185,938-960`. ✔ satisfied.
- Neutral unknowns: `InventorySnapshot.swift:98-103`; `ToolDetailView.swift:553-555` renders
  "Unknown"; `:489-496` renders the typed reason. ✔ satisfied.
- Loading / empty / failure states: `ToolListView.swift:47-77` (loading, scan-failed-with-rescan,
  no-definitions). ✔ satisfied **for the Inventory list** — but each new destination needs its own
  equivalent; do not reuse the Inventory empty state blindly (an empty *Updates* list and an empty
  *inventory* are different facts and must read differently).
- Copy/Reveal behavior and policy: `PathActionTarget.swift:95-128,135-167` and
  `PathActionDispatcher.perform` at `:188-213` — copy does not consult existence, reveal does;
  lstat semantics at `PathActions.swift:142-145`. ✔ satisfied, do not change.
- M10 confirmation semantics: `UpdateOperationView.swift` / `UninstallOperationView.swift` preview,
  progress, output, result; `OperationModels.swift:104-140,349-383` (one-shot `claim()` /
  `releaseUnconsumed()`); `OperationExecutionGate` (`:261-278`, one mutation at a time);
  `InstallationDelta` (`:143-167`) / `NpmUninstallDelta` (`:387-428`) — measured deltas, never
  rollback claims. ✔ satisfied.
- D-021 fail-closed gate, Core reason text, and the D-022 CLI ruling. ✔ satisfied; M12 does not
  touch Core.
- Login-shell environment resolution, degraded-PATH banner, tri-state install state. ✔ satisfied.

---

## B. Phase decomposition

Six sequential phases on `milestone/m12-workflow` (base `0589fac`). One implementer
(DeepSeek V4.1 Flash 1017 via OMP), one writer, no concurrent candidates (D-013).

**Ordering rationale.** The council brief's suggested order
(*presentation-state foundations → navigation/filters/counts → conflict summary → operation-journey
completion → accessibility/native polish → M8 keyboard gate + combined hardening*) is right and I
keep it, with one deliberate change: I put the **conflict summary** in the same phase as the
navigation shell rather than a separate phase, because the summary is *rendered inside Overview*
and splitting it would force a second navigation rewrite. That trades one more phase away for one
less App-wide refactor. Everything else follows the suggested order.

I also **reorder one thing the brief did not sequence**: M12-A (AppSupport) comes first and is
deliberately App-free, because every later phase needs the filter/capability/invalidation model,
and because the retargeting invariant must be fixed *before* new surfaces exist that can break it.

---

### M12-A — Presentation-state foundation (AppSupport only, no App changes)

**Observable goal.** A testable, UI-free presentation model exists for (a) the filter state, (b) the
derived counts, (c) the conflict summary, (d) the manager-agnostic operation capability, and (e) the
extended invalidation trigger set. The app is **visually unchanged** at the end of this phase; the
behavioural change is that any future filter/destination change will release a pending preview.

**Explicit non-goals.** No SwiftUI view is touched. No Core file is touched. No CLI change. No
registry / schema / detector change. No menu, shortcut, appearance, or Settings work. No new
dependency. No `Package.swift` change.

**Allow-list — production**
- `Sources/AgentLensAppSupport/InventoryViewModel.swift` (modified)
- `Sources/AgentLensAppSupport/InventorySnapshot.swift` (modified — derived counts only)
- `Sources/AgentLensAppSupport/InventoryFilter.swift` (**new**)
- `Sources/AgentLensAppSupport/ToolConflictSummary.swift` (**new**)
- `Sources/AgentLensAppSupport/OperationCapability.swift` (**new**)

**Allow-list — tests**
- `Tests/AgentLensAppSupportTests/InventoryViewModelTests.swift` (modified)
- `Tests/AgentLensAppSupportTests/InventoryFilterTests.swift` (**new**)
- `Tests/AgentLensAppSupportTests/ToolConflictSummaryTests.swift` (**new**)
- `Tests/AgentLensAppSupportTests/OperationCapabilityTests.swift` (**new**)

**DO NOT TOUCH.** `Sources/AgentLensCore/**`, `Sources/AgentLensApp/**`, `Sources/agent-lens/**`,
`Package.swift`, `scripts/**`, `Tests/Packaging/**`, `.github/**`, `Resources/**`, `docs/**`,
`briefs/**` (existing), `walkthroughs/**` (existing), `ROADMAP.md`, `DECISIONS.md`.

**Contracts that must not change**
- C-A1 `InventorySnapshot.updateAvailableCount` keeps counting **only** `.updateAvailable`
  (`InventorySnapshot.swift:98-103`). Unknown never inflates it.
- C-A2 `installedToolCount` keeps counting `installedNotOnPath` as installed
  (`InventorySnapshot.swift:92-94`).
- C-A3 Core's typed facts are consumed **verbatim**; no re-derivation of `ToolPathDiagnostic`,
  `VersionStatus`, `InstallationOwnershipResult` or `InstallationDelta` in AppSupport.
- C-A4 `PathSelection` / `InstallState` tri-state semantics unchanged
  (`PathActionTarget.swift:95-113`).
- C-A5 `invalidatePendingUpdate()` keeps its current behaviour for the four existing triggers and
  keeps `:621` ("a launched mutation is not a pending preview").

**Design decisions resolved here (the flash implementer must not re-decide these)**

- **D-A1 — Filter shape.** `InventoryFilter` is a value type (`Equatable`, `Sendable`) with
  exactly **two** axes:
  - `category: ToolCategory?` — `nil` means "all categories".
  - `update: UpdateStatusFilter` — an enum with cases `all`, `updateAvailable`, `upToDate`,
    `unknown`, `notChecked`.
  There is **no conflict filter axis**: conflicts are a *summary surface*, not a list filter.
  There is **no "installed only" axis**: `notInstalled` is already visible in the row badge and
  adding a filter for it is speculative.

- **D-A2 — Category axis vs the sidebar.** The sidebar *is* the category filter (M12-B). The
  `InventoryFilter.category` axis exists in AppSupport because the AppSupport model must be
  testable without a UI, and because the Overview "All tools" section needs a category dimension.
  The App layer must **not** render a second, redundant category picker next to the sidebar.

- **D-A3 — Filter × search interaction.** Filters narrow the candidate set first; search narrows
  within that set; the two are ANDed. `filteredEntries` becomes:
  `entries → filter → search`. Search text is trimmed, lowercased and compared with
  `contains`, exactly as today (`InventoryViewModel.swift:182-184`).

- **D-A4 — Search haystack extension.** `matches(_:query:)` gains two fact sources:
  `entry.definition.category.label` and each `entry.definition.packages[].name`. Selection is
  **still** excluded from the predicate (today's comment at `:936-937` is binding). No new
  synthesized text (no display-name-derived manager strings, no path synthesis).

- **D-A5 — Counts are snapshot-derived, not list-derived.** Every count is computed from the
  **unfiltered** `snapshot.entries`, so a count never changes because the user typed in the search
  field. The only count that is list-derived is the visible row count, and it is labelled as such
  ("showing N of M").

- **D-A6 — Conflict model.** `ToolConflict` is a value type with:
  - `kind: ToolConflictKind` — exactly these cases:
    `multipleLiveCopies` (more than one distinct live entry path **or** more than one canonical
    target), `shadowedCopy` (`shadowedInstallationCount > 0`), `versionSkew` (two or more
    canonical targets whose measured local versions differ), `offPathCopy` (`selection == .offPath`),
    `inconsistentDiagnostics` (`selection == .inconsistent`), `aliasOnly`
    (`sameTargetAliasCount > 0` with a single canonical target), `repeatedPathSlot`
    (`repeatedPathSlotCount > 0`).
  - `severity: ToolConflictSeverity` — `.actionable` (the user must decide which copy runs:
    `multipleLiveCopies`, `shadowedCopy`, `versionSkew`, `offPathCopy`, `inconsistentDiagnostics`)
    vs `.informational` (`aliasOnly`, `repeatedPathSlot`).
  - `toolRegistryID`, `displayName`, `copyCount`, `versions: [String]` (measured local versions
    only — never latest versions).
  All inputs come from `ToolPathDiagnostic` and `InstallationVersionObservation`. **A conflict
  record never contains a synthesized path, a guessed winner, or a latest version.**

- **D-A7 — Capability model.** `OperationCapability` is a new AppSupport vocabulary, deliberately
  *not* a generalization of the Core npm enums (Core is untouched):
  ```swift
  enum OperationCapability {
      case eligible(OperationKind)          // an Update/Uninstall may be PREPARED
      case notAccepted(OperationKind)        // the tool has no accepted mutation scenario
      case ownershipNotVerified(OperationKind)
      case notApplicable(OperationKind)      // no manager owns this installation
  }
  enum OperationKind { case update, uninstall }
  ```
  Mapping rules (exact):
  - `update`: eligible iff `entry.definition.acceptedOperations.contains(.npmUpdate)` **and**
    `entry.update?.npmPackage != nil` **and** `entry.updateStatus == .updateAvailable`.
    Otherwise `notAccepted` when the operation is not in `acceptedOperations`;
    `notApplicable` when the entry declares no npm package; and not eligible (with the reason
    coming from Core at prepare time) otherwise.
  - `uninstall`: eligible iff `entry.definition.acceptedOperations.contains(.npmUninstall)`
    **and** `entry.ownership?.verifiedInstallation?.manager == .npm`.
    Otherwise `notAccepted` / `ownershipNotVerified` per the same rules.
  - The **reason text** for `notAccepted` is `NpmUpdateUnavailableReason.operationNotAccepted.message`
    / `NpmUninstallUnavailableReason.operationNotAccepted.message` — **read from the Core enum, never
    retyped** (D-021 / M11-B contract 8). `ownershipNotVerified` reuses the *existing accepted*
    hint string "Verify Installation to enable Uninstall for this npm package."
    (`ToolDetailView.swift:306`). `notApplicable` uses one new, honest sentence:
    "Agent Lens diagnoses this installation but does not manage it."
  - This type is the **single source** for "is this control offered, and why not?" in M12-B/D/E.

- **D-A8 — Invalidation trigger set.** The following MUST release an unconsumed preparation with
  zero mutation and clear the preview. Today four of these exist; M12-A adds the rest:
  1. search text change *(exists, `:99`)*
  2. selection change to a different registry ID *(exists, `:197`)*
  3. verify ownership *(exists, `:249`)*
  4. launch / rescan / check / refresh *(exists, `:690`)*
  5. **category filter change** *(new)*
  6. **update-status filter change** *(new)*
  7. **sidebar destination change** *(new — state owned by the ViewModel so the App cannot bypass it)*
  8. **a jump to a different tool from the conflict summary / Overview row** *(new — goes through
     `select(registryID:)`, so it inherits trigger 2)*
  9. **an Updates-destination action on a tool that is not the current selection** *(new — the
     action MUST change the selection through `select(registryID:)`, never bypass it)*

  And the counterpart, which must NOT change: **a launched operation is never invalidated by a
  filter, search, destination or selection change** — it runs to completion and publishes its own
  reconciliation snapshot (`:621`).

- **D-A9 — Destination state lives in the ViewModel.** The active `NavigationDestination` becomes
  AppSupport state (`InventoryViewModel.activeDestination`), not `@State` inside `MainWindow`. This
  is what makes trigger 7 enforceable at all: if the sidebar selection were view-local, a
  destination switch could not invalidate a pending preview. `MainWindow.swift:20-24` moves to the
  ViewModel.

- **D-A10 — Last-operation summary.** `InventoryViewModel` retains, per registry ID, the last
  completed operation's summary: `OperationKind`, `OperationState`, exit status, captured stdout /
  stderr text with truncation flags, the reconciliation delta, and the observation time. It is
  cleared by a fresh local scan for that entry and by a new operation on that entry. It is **not**
  cleared by a filter or a destination change (it is a record, not a pending authorisation). It is
  never persisted to disk and never leaves the process.

**Acceptance outline (M12-A)**

```sh
env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS swift build
env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS swift test --no-parallel
python3 scripts/check-core-ui-imports.py
python3 Tests/Packaging/test_core_ui_imports.py
```

Observable results:
- The full suite passes with **zero** skips and zero failures; the Core count is unchanged at
  **467** (M12-A adds no Core test) and the AppSupport count **rises above 80**.
- A seeded-corruption style test proves the new logic is non-vacuous (e.g. a conflict test that
  fails when the kind is mutated; a capability test that fails when the `acceptedOperations` gate
  is removed).
- `check-core-ui-imports.py` reports the same Core file count as the baseline — **zero Core files
  changed** (protected-file manifest proves it).

Evidence format: raw argv, stdout/stderr, exit codes, durations, under the phase evidence root;
SHA-256 of every changed file; a protected-file manifest diff showing only allow-listed files
changed.

**Dependencies / stop conditions.** Depends on nothing (first phase). Stop and report if: a
capability decision requires a Core type that does not exist (it must not — say so and propose an
AppSupport-only alternative); if any test outside the allow-list fails for a reason that cannot be
migrated inside it; if the AppSupport floor cannot be raised to a measured count.

**Review recommendation.** **One mandatory independent council review.** Rationale: this phase
changes the confirmation-retargeting trigger set — a safety contract. Not both reviewers; one is
enough for AppSupport presentation state.

---

### M12-B — Seven-destination navigation shell + Overview dashboard

**Observable goal.** The sidebar offers Overview, AI Agents, AI Coding Tools, AI Harnesses,
Updates, Diagnostics, Settings, each with a truthful count badge. Overview renders a dashboard:
counts, the conflict summary, and the updates-available list. The three category destinations
render filtered tool lists using the **existing** `ToolRow` component, unchanged in appearance.

**Explicit non-goals.** No update-status filter UI (that is M12-C). No operation controls in the
Updates destination (that is M12-D). No menus/shortcuts (M12-E). No Settings content beyond a
placeholder-free truthful first cut (M12-E owns the final content). No Core change. No change to
`ToolRow`, `ToolDetailView` or `DiagnosticsView` in this phase.

**Allow-list — production**
- `Sources/AgentLensApp/MainWindow.swift` (modified)
- `Sources/AgentLensApp/ToolListView.swift` (modified — scope parameter only; the row component
  itself is untouched)
- `Sources/AgentLensApp/OverviewView.swift` (**new**)
- `Sources/AgentLensApp/ConflictSummaryView.swift` (**new** — the presentational half; the model is
  M12-A's `ToolConflictSummary.swift`)
- `Sources/AgentLensAppSupport/InventoryViewModel.swift` (modified — destination/count plumbing)

**Allow-list — tests**
- `Tests/AgentLensAppSupportTests/InventoryViewModelTests.swift` (modified — destination + counts)
- `Tests/AgentLensAppSupportTests/ToolConflictSummaryTests.swift` (modified if M12-B changes the
  model's navigation intent; otherwise unchanged)

**DO NOT TOUCH.** Everything in M12-A's DO NOT TOUCH list, plus
`Sources/AgentLensApp/ToolDetailView.swift`, `Sources/AgentLensApp/DiagnosticsView.swift`,
`Sources/AgentLensApp/PathActions.swift`, `Sources/AgentLensApp/OwnershipVerificationView.swift`,
`Sources/AgentLensApp/UpdateOperationView.swift`, `Sources/AgentLensApp/UninstallOperationView.swift`,
`Sources/AgentLensApp/AgentLensApp.swift`, `Sources/AgentLensAppSupport/InventorySnapshot.swift`,
`Sources/AgentLensAppSupport/PathActionTarget.swift`.

**Design decisions resolved here**

- **D-B1 — The seven destinations and their content column.**

  | Destination | Content column | Detail column | Badge |
  |---|---|---|---|
  | Overview | `OverviewView`: counts row, conflict summary section, "Updates available" section, "All tools" table (all 14 entries, one row each, with state + category + source) | `ToolDetailView` for the selected entry | `installed/known` (global) |
  | AI Agents | tool list filtered to `ToolCategory.aiAgent` | `ToolDetailView` | that category's `installed/known` |
  | AI Coding Tools | tool list filtered to `.aiCodingTool` | `ToolDetailView` | that category's `installed/known` |
  | AI Harnesses | tool list filtered to `.aiHarness` | `ToolDetailView` | that category's `installed/known` |
  | Updates | tool list of installed entries with tri-state cells (full behaviour in M12-D) | `ToolDetailView` | global `update-available` count |
  | Diagnostics | per-tool PATH evidence (the **existing** `DiagnosticsView`, unchanged) | `DiagnosticsView` for the selected entry | none |
  | Settings | `SettingsView` (content final in M12-E) | short "About Agent Lens" text | none |

  The "All tools" table in Overview is the only complete-catalogue list; the three category
  destinations are the same list partitioned. **The Inventory destination is replaced, not kept** —
  ROADMAP §4 names seven destinations and does not include "Inventory". The complete catalogue is
  therefore visible in one place (Overview) and partitioned in three (categories).

- **D-B2 — The conflict summary is rendered in Overview only.** It is one component, used once.
  Diagnostics remains the per-tool evidence surface; the summary's rows **navigate** to it
  (change selection + destination) rather than re-rendering evidence. This is how the ROADMAP's
  "conflict summary that leads to per-installation PATH evidence and versions" is satisfied
  *without duplicating `DiagnosticsView`*.

- **D-B3 — The Overview "Updates available" section is a summary, not a control.** It lists the
  entries whose status is `.updateAvailable` and links to the detail. It never offers a mutation
  control in M12-B (that is M12-D's job, and it belongs in the Updates destination).

- **D-B4 — Badge counts.** A badge is `installed/known` for Overview and the three category
  destinations, and the update-available count for Updates. Badges show `known` (definitions) and
  `installed` (D-006 tri-state), matching today's sidebar badge at `MainWindow.swift:199-203`.
  Diagnostics and Settings carry no badge. A zero badge is shown as `0/7`, never hidden.

- **D-B5 — Empty / loading / failure states per destination.** Each destination gets its own
  state text. The Inventory empty text "The detector registry contains no tool definitions."
  (`ToolListView.swift:71-75`) is **wrong** for Updates and must not be copied there. Required
  texts: Overview with no conflicts → "No conflicts detected across the known tools."; Updates
  with nothing installed → "No tools are installed."; Updates with nothing checked → "No update
  check has run yet. Use Check Updates."; a *failed rescan* keeps the retained snapshot and shows
  the existing "Rescan Failed" banner (`ToolDetailView.swift:135-152`) beside the retained list.

- **D-B6 — Search placement.** The `.searchable` modifier stays on the content column
  (`ToolListView.swift:25-29`) for the three category destinations and the Updates destination.
  For Overview, the search field filters the "All tools" table. The Diagnostics and Settings
  destinations have no search field (nothing to search). **One** search field is visible at a
  time; it is never duplicated across columns.

- **D-B7 — Selection semantics are unchanged.** Selection is by registry ID
  (`InventoryViewModel.swift:105,196-214`), a hidden-by-filter selection is retained (not cleared)
  exactly as today, and the detail column shows "No Tool Selected" when appropriate
  (`ToolDetailView.swift:61-65`).

**Acceptance outline (M12-B)**
- The full M12-A gate set passes; Core count still 467.
- The orchestrator performs a native spot-check (the App evidence, per F-1): build the dev app,
  launch it, and observe — seven sidebar items with the specified badges; each category
  destination lists exactly the entries of that category; Overview shows the counts row, the
  conflict summary and the all-tools table; Diagnostics still renders the M10/M9 detail for the
  selected tool; selecting a row in a category destination selects the same registry ID.
- **A new AppSupport test** proves the destination switch releases a pending preparation (trigger
  7) and that the launched-operation exemption still holds.

**Dependencies / stop conditions.** Depends on M12-A accepted. Stop if the seven-destination
`NavigationSplitView` cannot be built without changing `DiagnosticsView` or `ToolDetailView`
(those are protected here) — report and request the boundary change.

**Review recommendation.** **Orchestrator acceptance** (routine UI), plus the orchestrator's
native spot-check. No independent council review required for this phase alone.

---

### M12-C — Filters, counts, and the conflict summary surface

**Observable goal.** The Updates destination gains an update-status filter (All / Update available /
Up to date / Unknown / Not checked). List rows and Overview rows carry package and source details.
The conflict summary is complete: every actionable conflict is listed with its kind, the copy count
and the measured local versions, and each row leads to the per-installation PATH evidence and
versions in Diagnostics.

**Explicit non-goals.** No operation controls. No menu/shortcut work. No appearance work. No Core
change. No new detector. No capability-model change beyond M12-A (the capability model is
consumed, not extended, here).

**Allow-list — production**
- `Sources/AgentLensApp/ToolListView.swift` (modified — row gains source/package detail; filter
  control)
- `Sources/AgentLensApp/OverviewView.swift` (modified)
- `Sources/AgentLensApp/ConflictSummaryView.swift` (modified)
- `Sources/AgentLensApp/UpdatesView.swift` (**new**)
- `Sources/AgentLensAppSupport/InventoryViewModel.swift` (modified — filter application)

**Allow-list — tests**
- `Tests/AgentLensAppSupportTests/InventoryFilterTests.swift` (modified)
- `Tests/AgentLensAppSupportTests/ToolConflictSummaryTests.swift` (modified)
- `Tests/AgentLensAppSupportTests/InventoryViewModelTests.swift` (modified)

**DO NOT TOUCH.** M12-A's and M12-B's DO NOT TOUCH lists, plus the operation sheets and
`ToolDetailView`.

**Design decisions resolved here**

- **D-C1 — Filter × search × count.** Filter applies first, search second; counts in the toolbar
  and sidebar always reflect the **whole snapshot**, never the filtered list. The list header shows
  "showing N of M" where M is the filtered total and the badge shows the global total. This keeps
  the badge a fact about the machine, not about the current query.

- **D-C2 — Unknown is a first-class row in Updates.** The Updates destination lists every
  **installed** entry (`installState != .notInstalled`) that has any update information, including
  `unknown` rows with their typed reason. `notInstalled` entries are excluded from Updates (an
  update to a tool that is not installed is not a thing Agent Lens can act on, and there is no
  install adapter in scope — D-004). A row whose latest has never been checked shows
  `notChecked` with the "Check Updates" affordance, never "Up to date".

- **D-C3 — Latest-check support is read from the declared packages, never invented.** A latest
  version is shown only when the shipped probe actually produced one. The capability matrix rules
  are the truth (`docs/capability-matrix.md:9-24`): latest-check is `yes` for npm and
  `homebrewFormula` candidates, never for `homebrewCask`. A cask-only tool (kiro-cli, agy) shows
  Unknown with a truthful reason — **no latest version is fabricated, and no cask cell says
  `yes`** (enforced today by `Tests/AgentLensCoreTests/CapabilityMatrixTests.swift`,
  `latestCheckProblems`).

- **D-C4 — Conflict row content.** Each conflict row shows: tool display name, the conflict kind
  in plain language, the number of distinct live copies, and the **measured local versions** of the
  canonical targets (from `installationVersions`, `ToolPathDiagnostic`), each with its discovery
  origin label. It shows **no** latest version and **no** verdict about which copy is "better" —
  except the PATH winner, which is a measured fact (`selection == .winner`) and is labelled as
  "PATH winner".

- **D-C5 — Conflict → evidence navigation.** Activating a conflict row (a) sets the selection to
  that registry ID through `select(registryID:)` — inheriting invalidation trigger 2 — and
  (b) sets the destination to `.diagnostics`. The Diagnostics column then renders the **existing**
  `DiagnosticsView`, which already shows the per-installation PATH evidence
  (`DiagnosticsView.swift:388-474`) and the per-canonical-target versions (`:291-309`). No new
  evidence rendering is introduced. The Overview conflict section is not duplicated in
  Diagnostics.

- **D-C6 — "Informational" conflicts are listed separately.** `aliasOnly` and `repeatedPathSlot`
  are listed under a distinct "Other PATH notes" heading, never mixed into the actionable list, so
  the actionable count is not inflated.

**Acceptance outline (M12-C)**
- Full gate set passes; Core count still 467.
- AppSupport tests prove: filter × search composition; that filter change releases a pending
  preparation (triggers 5 and 6); that a conflict classification is correct for each of the seven
  kinds, including the *negative* cases (a single copy produces **no** conflict); that unknown
  versions never enter the update-available count; that cask-only entries produce no latest.
- Orchestrator native spot-check: the filter changes the visible rows; the conflict summary lists a
  synthetic multi-copy tool and activating it lands on the Diagnostics destination for that tool
  with the correct per-installation evidence visible.

**Dependencies / stop conditions.** Depends on M12-B accepted. Stop if a conflict kind cannot be
computed from `ToolPathDiagnostic` alone without inventing a fact — report the gap rather than
synthesizing.

**Review recommendation.** **One mandatory independent council review** — conflict semantics
touch diagnostic truthfulness, and the filtering path touches the retargeting invariant.

---

### M12-D — Updates destination behaviour + operation-journey completion + capability-driven unavailable UI

**Observable goal.** The full npm journey is reachable and reviewable end to end:
*find/filter → inspect competing copies → confirm or cancel an eligible operation → review output →
observe the post-rescan winner/version.* Future managers (M13–M15) can be plugged in later against
the **same** capability-driven UI without any new UI vocabulary.

**Explicit non-goals.** No new manager adapter. No per-tool mutation promotion (only `codex` may
mutate — D-021). No Homebrew/uv/Cargo code. No change to the Core prepare/execute semantics, the
Core reason texts, the CLI, the registry, or the schema. No change to the M10 preview content
(except the footer key equivalents, below).

**Allow-list — production**
- `Sources/AgentLensApp/UpdatesView.swift` (modified)
- `Sources/AgentLensApp/ToolDetailView.swift` (modified — availability branches now read the
  capability model; **rendered Core reason text must stay byte-identical**)
- `Sources/AgentLensApp/UpdateOperationView.swift` (modified — footer key equivalents + a11y)
- `Sources/AgentLensApp/UninstallOperationView.swift` (modified — same)
- `Sources/AgentLensApp/OverviewView.swift` (modified — updates-available rows link to Updates)
- `Sources/AgentLensAppSupport/InventoryViewModel.swift` (modified — prepare-on-behalf-of-a-tool,
  last-operation summary exposure)

**Allow-list — tests**
- `Tests/AgentLensAppSupportTests/InventoryViewModelTests.swift` (modified)
- `Tests/AgentLensAppSupportTests/OperationCapabilityTests.swift` (modified)
- `Tests/AgentLensAppSupportTests/PathActionTests.swift` (**unmodified** — but must still pass
  unchanged; it is a protected regression witness)

**DO NOT TOUCH.** `Sources/AgentLensCore/**` entirely. `Sources/agent-lens/main.swift`.
`Sources/AgentLensApp/PathActions.swift`, `OwnershipVerificationView.swift`,
`DiagnosticsView.swift`, `MainWindow.swift`, `ToolListView.swift`.
`Sources/AgentLensAppSupport/InventorySnapshot.swift`, `PathActionTarget.swift`,
`InventoryService.swift`, `SessionEnvironmentProvider.swift`. `Package.swift`, `scripts/**`,
`Tests/Packaging/**`, `.github/**`, `Resources/**`, `docs/**`.

**Design decisions resolved here**

- **D-D1 — The Updates row's operation control *prepares*, never confirms.** A row for a tool whose
  capability is `.eligible(.update)` offers a "Prepare Update…" control that calls
  `prepareSelectedUpdate()` (or the new explicit-registry-ID variant). **Confirm Update remains
  reachable only from inside the confirmation sheet**, with the reviewed preview. This is the
  existing M10 discipline (`ToolDetailView.swift:527-532`) and it is preserved.

- **D-D2 — Preparing for a non-selected tool.** A new ViewModel entry point
  `prepareUpdate(forRegistryID:)` is required, because the Updates destination may act on a tool
  that is not the current selection. It MUST: (a) go through `select(registryID:)` first (so
  trigger 2 fires), (b) bind the preparation to that registry ID and to the observed selection
  (`entryPath` + `canonicalTarget`) captured at prepare time — the same `ObservedSelection`
  comparison already used at `InventoryViewModel.swift:336` and `:489` — and (c) refuse to publish
  a result if the selection or observed target changed underneath it. It must never read "the
  currently selected tool" implicitly.

- **D-D3 — Capability-driven unavailable UI.** Where the capability is not `.eligible`, the UI
  shows the reason **in place of the control** — never a hidden control and never a disabled
  control with no explanation. Reason text comes from `OperationCapability` (M12-A), whose
  `notAccepted` text is the Core enum's own string. The existing detail-view Manage section
  behaviour accepted in M11-B is **preserved exactly**: a package-less entry (grok) still has no
  Manage section, and an npm-declared but unaccepted entry (opencode) still shows the exact Core
  uninstall reason with no button (`walkthroughs/M11-B-acceptance.md:60-66`). The capability model
  *replaces the branching*, not the accepted outcome.

- **D-D4 — Footer key equivalents (the F-2 fix).** In the **preview** state of both sheets:
  - the destructive confirm button gets **no key equivalent at all**;
  - Cancel becomes `.keyboardShortcut(.cancelAction)` (Escape);
  - **no** button holds `.keyboardShortcut(.defaultAction)` in the preview state.
  In the **result** and **unavailable** states, `Done` / `Close` keep
  `.keyboardShortcut(.defaultAction)` (safe, non-mutating).
  This is a **named contract change to accepted M10 UI behaviour** (M12-D/C-1): it removes the
  Return-to-confirm-update path at `UpdateOperationView.swift:77` and keeps Return-to-cancel in the
  Uninstall sheet (`UninstallOperationView.swift:74`). Justification: the council brief requires
  that shortcuts never execute a mutation directly, and the two sheets currently disagree. No
  accepted M10 *evidence* depends on the old behaviour: the M10-D native click-through pressed the
  buttons through Accessibility AXPress, not the Return key
  (`walkthroughs/M10-D-implementation-evidence/native/native-actions.txt`, steps 2–4).

- **D-D5 — "Review output" survives sheet dismissal.** After a result sheet is dismissed, the
  Updates row for that tool shows a retained "Last operation" section: state, exit status,
  observed time, the captured stdout/stderr (with the existing truncation marker), and the
  reconciliation delta (`InstallationDelta` / `NpmUninstallDelta`, verbatim). It is cleared by a
  fresh local scan of that entry or by a new operation on it, and survives filter/destination
  changes (D-A10).

- **D-D6 — Post-rescan winner/version is observable.** After a completed operation the ViewModel
  publishes the service's fresh snapshot (`InventoryViewModel.swift:389-391`, `:542-544`) and
  reconciles selection by registry ID (`:905-915`), so the tool row shows the new winner and the
  new local version. The Updates row must additionally surface the post-operation winner
  explicitly ("PATH winner now: …"), because "observe the post-rescan winner/version" is a named
  M12 acceptance step.

- **D-D7 — No adapter, no new operation type, no speculative capability.** `AcceptedOperation`
  stays closed at `npmUpdate`/`npmUninstall` (`DetectorMetadata.swift:78-81`). The capability model
  describes what *could* be offered for a future manager, but the UI must never claim a Homebrew,
  uv or Cargo operation is available, and must never show a "Homebrew Update…" control.

- **D-D8 — Missing manager and other prepare-time refusals keep the Core reason.** If preparation
  is refused (`managerUnavailable`, `identityUnverified`, `operationRootUnsafe`, …), the existing
  unavailable sheet renders the Core message (`UpdateOperationView.swift:127-135`,
  `UninstallOperationView.swift` equivalent). M12 changes neither the Core enums nor their texts.

**Acceptance outline (M12-D)**
- Full gate set passes; **Core count still 467** (M12-D touches no Core test).
- The **disposable npm fixture** drives the journey. Fixtures and their exact CLI:
  ```sh
  python3 Tests/Fixtures/M10C/npm_update_acceptance.py --root <root> --scenario controlled \
      --products <products>
  python3 Tests/Fixtures/M10D/npm_uninstall_acceptance.py --root <root> --scenario controlled \
      --products <products>
  python3 Tests/Fixtures/M10D/npm_uninstall_acceptance.py --root <root> --scenario combined \
      --products <products>
  ```
  (Scenario names verified from the fixtures' own argument parsers: M10-C accepts
  `controlled|serve-native|stop-native|record-native|prepare-public|verify-public` with
  `--cli/--products/--app`; M10-D accepts `controlled|combined|public|render` with
  `--root/--products`.) The root must not pre-exist and is never deleted.
- The orchestrator runs the native journey in the ordinary app against that disposable environment
  (M10-D recipe, `walkthroughs/M10-D-implementation.md:141-160`): find/filter → inspect competing
  copies → **Cancel** (prefix SHA-256 manifest byte-identical before/after) → fresh prepare →
  **Confirm** → result sheet → post-rescan winner/version visible. Screenshots + an AX action
  transcript are retained.
- Negative proof: a tool whose capability is `.notAccepted` shows the Core reason and offers no
  control; a tool with a cask-only package shows no latest version.
- **Key-equivalent proof:** with the preview sheet open, pressing Return does **not** confirm;
  Escape cancels; the destructive button is reachable by Tab and activates with Space.

**Dependencies / stop conditions.** Depends on M12-C accepted. Stop if (a) the capability model
cannot produce the D-021 reason text without retyping it, (b) preparing for a non-selected tool
would require weakening the `ObservedSelection` guard, (c) the destructive confirm cannot be made
un-triggerable by a key, (d) any Core change appears necessary.

**Review recommendation.** **Mandatory independent review by BOTH council models** (MiniMax
M3.1-Flash/xhigh via mcode and Grok 4.7/high via grok CLI), summoned by the orchestrator through
Herdr/hc after the candidate is frozen. This phase touches operation and mutation contracts.

---

### M12-E — Native menus, keyboard navigation, VoiceOver, appearance, large text, narrow windows, Settings

**Observable goal.** The app has a native menu bar with real commands and key equivalents, full
keyboard navigation, VoiceOver labels and announcements on every surface including the operation
sheets, correct behavior at accessibility text sizes, a sensible narrow-window floor, correct
light/dark appearance, and a truthful Settings surface.

**Explicit non-goals.** No operation-contract change (except the already-decided F-2 fix, which
belongs to M12-D). No new detection. No M16 features (cached launch, menu-bar presence, opt-in
periodic checks) and therefore **no toggles for them**. No persisted inventory facts. No Core
change.

**Allow-list — production**
- `Sources/AgentLensApp/AgentLensApp.swift` (modified — `.commands`, `Settings` scene, window
  minimum size)
- `Sources/AgentLensApp/MainWindow.swift` (modified — menu command wiring, focus handling)
- `Sources/AgentLensApp/ToolListView.swift` (modified — a11y labels, focus, large text)
- `Sources/AgentLensApp/OverviewView.swift` (modified)
- `Sources/AgentLensApp/ConflictSummaryView.swift` (modified)
- `Sources/AgentLensApp/UpdatesView.swift` (modified)
- `Sources/AgentLensApp/SettingsView.swift` (**new**)
- `Sources/AgentLensApp/PathActions.swift` (modified — announcement of transient feedback)
- `Sources/AgentLensApp/UpdateOperationView.swift` (modified — a11y labels only)
- `Sources/AgentLensApp/UninstallOperationView.swift` (modified — a11y labels only)
- `Sources/AgentLensApp/AppearancePreference.swift` (**new** — appearance + its storage)

**Allow-list — tests**
- `Tests/AgentLensAppSupportTests/InventoryViewModelTests.swift` (modified — only if a
  presentation-state value moves to AppSupport; otherwise no test change)

**DO NOT TOUCH.** `Sources/AgentLensCore/**`, `Sources/agent-lens/**`,
`Sources/AgentLensAppSupport/InventoryService.swift`, `InventorySnapshot.swift`,
`PathActionTarget.swift`, `SessionEnvironmentProvider.swift`, `ToolDetailView.swift`,
`OwnershipVerificationView.swift`, `DiagnosticsView.swift`, `Package.swift`, `scripts/**`,
`Tests/Packaging/**`, `.github/**`, `Resources/**`, `docs/**`.

**Design decisions resolved here**

- **D-E1 — Menu bar structure and key equivalents.** `AgentLensApp.swift` gains `.commands`:

  | Menu | Item | Key |
  |---|---|---|
  | Agent Lens (app) | Settings… | ⌘, |
  | File | Rescan | ⌘R |
  | File | Check for Updates | ⌘U |
  | File | Refresh Update Metadata | ⌘⇧U |
  | Edit | Find / Search | ⌘F (focus the content column's search field) |
  | View | Overview, AI Agents, AI Coding Tools, AI Harnesses, Updates, Diagnostics, Settings | ⌘1 … ⌘7 |

  **No menu item executes, prepares, or confirms a mutation.** No mutation-related command is
  added to any menu. The Edit menu keeps the **standard** ⌘C / ⌘X / ⌘V / ⌘A — Agent Lens must
  **not** override ⌘C, because ⌘C is the platform copy shortcut and path actions are reachable
  through focus + Space (see D-E3).
  **⌘K is deliberately not implemented in M12.** Scope §7 suggested ⌘K for a command/search
  palette, but a palette is a feature beyond M12's stated requirements; it is recorded as a
  deliberate deferral, not an omission. ⌘F is the native "find" convention and is what M12 ships.

- **D-E2 — Bare-letter shortcuts are not used.** Scope §7 suggested `U` (update), `R` (remove),
  `S` (scan). These collide with text entry in the search field and with the sidebar's type-ahead.
  M12 ships **no bare-letter shortcut**. List navigation (↑/↓) is the native `List` behaviour and
  needs no custom code; **Return** in the list moves focus to the detail column; **Escape**
  clears the search field when focused, or dismisses a sheet.

- **D-E3 — Path actions are activated by focus + Space/Return, not by a global shortcut.** The two
  path-action buttons per path row are already `Button`s (`PathActions.swift:65-83`) and are
  therefore in the AppKit focus order. M12-E guarantees: both buttons of **both** rows are
  reachable by Tab; each has a unique `accessibilityLabel` (already the case —
  `actionLabel(_:)` at `:51-54` distinguishes verb, row and tool); the transient feedback is
  **announced** (D-E4); and the focused button exposes a `.help`/accessibility hint naming its
  action. No global ⌘-shortcut is added for Copy/Reveal.

- **D-E4 — Announcing transient feedback.** The path-action feedback text (`PathActions.swift:95-101`)
  is posted as an accessibility announcement using the AppKit accessibility announcement API
  (`NSAccessibility.post(element:notification:userInfo:)` with the announcement notification and an
  `.announcement` user-info value). **The implementer confirms the exact selector at build time
  and reports it** — this proposal does not claim the symbol is available, only that an AppKit
  announcement path exists. If it is unavailable in this toolchain, the agreed fallback is to
  expose the feedback text as the focused element's accessibility value. Either way the
  requirement is "a VoiceOver user is told the outcome without hunting for it". This is not a
  blocker.

- **D-E5 — VoiceOver labels, per surface.** Required spoken content:
  - **List row**: name, executable, install state, update state (already implemented at
    `ToolListView.swift:146-163` — preserve verbatim, extend only with the new source/package
    cells from M12-C).
  - **Detail sections**: each `Grid` row's label and value must be individually addressable or
    clearly grouped; the currently unlabeled `Grid` rows in `ToolDetailView` and
    `DiagnosticsView` gain `.accessibilityElement(children: .combine)` + a spoken label.
  - **Path actions**: "Copy Selected Entry path for Codex" / "Reveal in Finder Resolved Target
    path for Codex" (existing pattern, `PathActions.swift:51-54`) — preserved.
  - **Operation sheets (new work)**: the preview must be announced as a *confirmation of a
    destructive operation* including the target package, the version change, and the fact that
    it is not yet executed; the output panes must be announced as "stdout"/"stderr" with a
    truncation flag; the result must be announced with its `OperationState` and exit status; an
    unavailable sheet must be announced with the Core reason.
  - **Error states**: every banner (`ToolDetailView.swift:116-171`) must be an
    `accessibilityElement` with a label that names the failure, not just an icon.

- **D-E6 — Large text.** Every M12 view uses semantic text styles (`.body`, `.headline`,
  `.caption`, …) and **no fixed point sizes**. The existing sheets use `.system(.caption,
  design: .monospaced)` for monospaced output (`UpdateOperationView.swift:111`), which scales with
  Dynamic Type. The implementer must verify the largest accessibility size for each new surface
  and record the result; no clipping, no overlapping, no truncation of safety text.

- **D-E7 — Narrow windows.** Add an explicit window minimum (recommendation **720 × 480**) at the
  root view, so the `NavigationSplitView` cannot collapse the detail column to nothing. Keep the
  existing sheet minimums (`UpdateOperationView.swift:58`, `UninstallOperationView.swift:59` —
  640 × 500) and verify the sheets are fully usable at that size. Every path/version text stays
  selectable and wrapping (`PathActions.swift:61`, `DiagnosticsView.swift:571-577`,
  `ToolDetailView.swift:365-366,377`). The npm effect disclosure (the safety text) must never be
  clipped at any size — it already uses `fixedSize(horizontal: false, vertical: true)`
  (`UpdateOperationView.swift:103-106`); that pattern is mandatory for every long disclosure.

- **D-E8 — Appearance.** Replace fixed-hue state colours with appearance-adaptive ones **only
  where it does not remove meaning**: the *text* must keep carrying the state
  ("Installed, off PATH", "Consistency Failure: …", "Shadowed because it appears later in PATH").
  The implementer may change hues (`ToolDetailView.swift:119,138,157,391`, `ToolListView.swift:124`,
  `OwnershipVerificationView.swift:66`, `DiagnosticsView.swift:189,235`) but **must not remove or
  reword** any state text, and must verify contrast in **both** light and dark. The app must
  follow the system appearance by default.

- **D-E9 — Settings honesty.** The Settings surface contains exactly:
  1. **Appearance**: System / Light / Dark. This controls a **delivered** M12 feature (the
     light/dark appearance requirement) and nothing else. It is persisted in `UserDefaults` under
     an app-scoped key and stores **no inventory fact, no path, no environment, no credential**
     (D-003; M16's "persist only minimal display facts" is about inventory facts and is not
     violated by a UI preference).
  2. **About**: app name, version, the number of known registry entries, the fact that the
     catalogue is the 14-entry set, the MIT licence line, and links to the project's
     documentation.
  3. **Manageability (truthful statement)**: a short, non-interactive statement of what Agent Lens
     can manage today — npm Update/Uninstall for ownership-verified npm-global copies of the
     `codex` entry only, with every other entry informational — and an explicit statement that
     Homebrew/uv/Cargo management, cached launch, menu-bar presence and opt-in periodic checks
     are **not delivered** and therefore **not configurable here**.

  **No other toggles.** Specifically **no** "check for updates on launch" (M16), **no** "menu bar
  item" (M16), **no** "use cached results" (M16), **no** "automatic refresh" (M16), **no**
  "include off-PATH tools" (changes D-006 semantics), **no** theme picker beyond appearance, and
  **no** telemetry/analytics/network toggles (D-003).

- **D-E10 — Settings is reachable twice, from one implementation.** `SettingsView` is rendered in
  the Settings sidebar destination's content column **and** in a native `Settings` scene bound to
  ⌘,. One implementation, two entry points. The Settings scene must not change app state.

**Acceptance outline (M12-E)**
- Full gate set passes; Core count still 467.
- **No AppSupport test changes are expected** (if a test change is needed, the implementer reports
  why; it is a deviation signal).
- Orchestrator native checks: every menu item appears with the specified key equivalent; ⌘1–⌘7
  switch destinations; ⌘R rescans; ⌘U checks updates; ⌘F focuses the search field; ⌘, opens
  Settings; **no menu item can trigger a mutation** (the implementer demonstrates that every
  mutation control is reachable only from the sheet).
- Appearance screenshots in light and dark for Overview, a category list, a tool detail, an
  operation preview and an operation result.
- Large-text screenshots at the largest accessibility size for the same five surfaces.
- Narrow-window screenshots at the 720 × 480 floor.
- VoiceOver spoken checks: see §F.2.

**Dependencies / stop conditions.** Depends on M12-D accepted. Stop if (a) a VoiceOver spoken
string would have to lie about a state, (b) the Settings surface cannot be built without a
delivered-feature toggle, (c) the window minimum cannot be set without changing layout
architecture, (d) the announcement API path (D-E4) turns out to be unavailable in this toolchain
**and** the fallback would change a visible string.

**Review recommendation.** **One mandatory independent council review** — accessibility work
carries regression risk and the previous model (MiniMax) is preferred for the a11y axis.

---

### M12-F — M8 keyboard gate closure + combined M12 acceptance

**Observable goal.** The outstanding M8 keyboard-only Copy/Reveal measurement is **closed with
evidence**, and the combined M12 acceptance passes.

**Explicit non-goals.** No new features. No Core change. No acceptance performed by the
implementer (D-014: the orchestrator re-runs every gate itself).

**Allow-list — production**
- `Sources/AgentLensApp/PathActions.swift` (modified **only if** the M12-F measurement shows the
  path-action buttons are not reachable by keyboard or their labels are not unique)
- `Sources/AgentLensApp/ToolDetailView.swift` (modified **only if** the measurement shows the
  path rows are not in the focus order)

**Allow-list — tests**
- `Tests/AgentLensAppSupportTests/PathActionTests.swift` (modified only if the policy changes —
  it must not)

**DO NOT TOUCH.** Everything else.

**Design decisions resolved here**

- **D-F1 — The measurement is keyboard-event-driven, not AX-press-driven.** AXPress bypasses
  keyboard activation and therefore **cannot** close this gate. The orchestrator posts real key
  events (see §F.1) and records the focus traversal.

- **D-F2 — If the measurement fails, the fix is a code change, re-measured, and re-reviewed.** The
  implementer may not "adjust the transcript". A failed measurement is a defect in the product,
  not in the method.

- **D-F3 — The M8 gate is closed only when all four of the following hold, for **both** path rows
  of **both** the Selected Entry and the Resolved Target:
  1. the button is reachable by keyboard focus traversal alone;
  2. a documented activation key (Space and Return, separately) activates it;
  3. the observable effect matches the expected effect byte-for-byte (clipboard) or path-for-path
     (Finder selection);
  4. the transient feedback appears and is announced, and does not leak to another tool.

**Acceptance outline (M12-F).** The combined M12 gate — see §G.3.

**Dependencies / stop conditions.** Depends on M12-E accepted.

**Review recommendation.** The orchestrator performs the measurement and the combined gate. The
implementation delta in M12-F, if any, gets **one independent council review**.

---

## C. Information architecture and navigation

### C.1 The seven destinations

Designed in D-B1 (table above). The governing shape: **the sidebar selects a scope; the content
column always shows that scope's content; the detail column always shows the selected tool.**
Diagnostics is the only destination whose detail differs from the tool detail.

### C.2 What each destination shows, and where the counts come from

| Destination | Content | Count source (all snapshot-derived) |
|---|---|---|
| Overview | Counts row (known / installed / update-available / conflicts / unknown-latest), conflict summary, updates-available summary, all-tools table | `InventorySnapshot.knownToolCount` (`:88`), `installedToolCount` (`:92-94`), `updateAvailableCount` (`:98-103`); conflict count from `ToolConflictSummary`; unknown-latest count from `VersionStatus.unknown` entries |
| AI Agents | `ToolCategory.aiAgent` entries | the same predicates restricted to the category |
| AI Coding Tools | `.aiCodingTool` entries | ditto |
| AI Harnesses | `.aiHarness` entries | ditto |
| Updates | installed entries with tri-state update cells | `updateAvailableCount` for the badge; per-row status from `entry.updateStatus` |
| Diagnostics | the existing per-tool PATH evidence view | none |
| Settings | the truthful Settings surface | none |

**Counts never come from the filtered list** (D-A5, D-C1). A badge is a fact about the machine.

### C.3 Category and update filters, and their interaction with search

- **The sidebar is the category filter.** M12 does **not** add a redundant category picker to the
  content column (D-A2). The `InventoryFilter.category` axis is the AppSupport representation of
  the sidebar selection.
- **The update filter lives in the Updates destination** as a segmented control with exactly the
  five cases from D-A1 (`all`, `updateAvailable`, `upToDate`, `unknown`, `notChecked`).
- **Search** applies to the content column's list (and to Overview's all-tools table) exactly as
  today, with the haystack extended per D-A4.
- Composition: **filter → search (AND)**. Changing either releases a pending preview (D-A8).
- **Search text survives a destination switch?** **Decision: no.** Switching destination clears the
  search field, because the same query means different things in different scopes (e.g. "npm" in
  Overview is a package-name match across 14 entries; in AI Agents it is 7 entries). Clearing it
  also removes a whole class of "the user thinks they filtered to X but the list is unfiltered"
  confusion. The search field is per-destination state, reset on destination change.

### C.4 The conflict summary

**What counts as a conflict** — the seven kinds in D-A6, with the actionable/informational split.

What explicitly does **not** count:
- An unknown latest version (that is tri-state update information, D-007 — `InventorySnapshot.swift:98-103`
  keeps it out of the update count, and the conflict list keeps it out too).
- A single copy with a single canonical target.
- A declared package with no accepted operation (that is a *capability* fact, shown in the Updates
  row and the detail view — not a PATH conflict).

**How it leads to per-installation PATH evidence and versions without duplicating `DiagnosticsView`:**
the summary is a **compact index**; `DiagnosticsView` is the **evidence**. Activating a conflict
row selects the tool and switches to the Diagnostics destination, where the existing
`DiagnosticsView` already renders:
- the selection status and its reason (`:137-239`),
- the summary counts (`:243-282`),
- the canonical installation versions with their discovery origins (`:291-309`),
- the live, off-PATH and invalid candidates (`:388-474`).

The M12 conflict summary adds **no new per-installation rendering**. It adds a way to *find* the
tools that have a conflict, and it carries the measured versions in the row itself (from
`installationVersions`) so the index is useful without opening the evidence.

### C.5 Updates section semantics under the tri-state rules

1. **Unknown never counts as up-to-date and never inflates the update count.** The badge uses
   `InventorySnapshot.updateAvailableCount` (`:98-103`), which counts only `.updateAvailable`.
   `VersionStatus.unknown` renders as "Unknown" with its typed reason
   (`ToolDetailView.swift:553-555`, `:489-496`, `:577-618`) — never as a dash that reads as
   "current", and never as an error.
2. **Only capability-matrix-supported latest checks.** The shipped probe supports npm and
   `homebrewFormula`; a cask-only entry has no latest check and shows Unknown with a truthful
   reason. The matrix rules that already exist
   (`docs/capability-matrix.md:9-24`, enforced by
   `Tests/AgentLensCoreTests/CapabilityMatrixTests.swift`) are the source of truth, and M12 does
   not change them.
3. **Mutation controls only where D-021 accepts them.** Today that is `codex` npm-global verified
   copies only. Every other entry shows a reason, not a control (D-D3).
4. **Not-installed entries are excluded from Updates** (D-C2) — there is no install adapter in
   scope (D-004).

### C.6 Selection / filter safety — the enumeration and the invariant

**The exact invariant (binding for every phase):**

> A pending (unconsumed) Update or Uninstall preparation is bound to the registry ID and to the
> observed selection — the selected entry path and the canonical target — captured at prepare
> time. **Any** change to the selected registry ID, the selected entry path, the canonical target,
> the category filter, the update-status filter, the search text, the active destination, or a
> fresh local scan **invalidates and releases** the preparation with zero mutation and clears the
> preview. A **launched** operation is never invalidated by a filter, search, destination or
> selection change: it completes and publishes its own reconciliation snapshot.
>
> Independently and unchanged: at execute time, a changed target, manager, package, registry or
> prefix invalidates the preview (the M10 Core contract). M12 does not modify Core.

**The nine ways a filter, search, category switch or rescan could retarget an existing
confirmation, and the mechanism that prevents each:**

| # | Retargeting vector | Prevented by | Test |
|---|---|---|---|
| 1 | Search text changed while a preview is open | `searchText.didSet` → `invalidatePendingUpdate()` (`InventoryViewModel.swift:99`) | existing M10/AppSupport test |
| 2 | The user selects a different tool | `select(registryID:)` → `invalidatePendingUpdate()` when the ID differs (`:197`) | existing |
| 3 | Rescan / Check / Refresh | `run()` → `invalidatePendingUpdate()` (`:690`) | existing |
| 4 | Verify ownership | `verifySelectedInstallation()` → `invalidatePendingUpdate()` (`:249`) | existing |
| 5 | **Category filter changes** | **new trigger (D-A8.5)** | **new** |
| 6 | **Update-status filter changes** | **new trigger (D-A8.6)** | **new** |
| 7 | **Sidebar destination changes** | **new trigger (D-A8.7) + destination state in the ViewModel (D-A9)** | **new** |
| 8 | **A conflict/Overview row navigates to another tool** | goes through `select(registryID:)` → trigger 2 | **new** |
| 9 | **An Updates row acts on a tool that is not the current selection** | `prepareUpdate(forRegistryID:)` selects first (D-D2) and binds the preparation to the registry ID + observed selection | **new** |

Two further, already-correct behaviours that M12 must not break:
- A **launched** mutation is not cancelled by a competing selection or filter
  (`InventoryViewModel.swift:621`).
- A **late** preparation result whose selection or observed target changed is discarded and its
  preparation released (`:336`, `:338`, `:489`, `:491`).

**Required tests (all in `Tests/AgentLensAppSupportTests/InventoryViewModelTests.swift`):** one
per row of the table above, each asserting (a) the preparation is released, (b) the preview is
cleared, (c) **no** mutation pipeline was started, and (d) for a launched operation, the operation
**completed** and published its own snapshot despite the filter change. Plus one test proving a
seeded corruption of the trigger set (removing trigger 7) fails.

### C.7 Core vs AppSupport vs App

| Layer | M12 content | Rule |
|---|---|---|
| **AgentLensCore** | **Nothing.** No Core file changes in any M12 phase. | D-002 / ROADMAP §6: Core never imports SwiftUI/AppKit; discovery, ownership, version comparison and operations live in Core. Everything M12 needs from Core already exists (F-12). |
| **AgentLensAppSupport** | `InventoryFilter`, `ToolConflictSummary` / `ToolConflict`, `OperationCapability`, the derived counts, the destination state, the last-operation summary, and the extended invalidation triggers. | Presentation state only; never SwiftUI/AppKit; pure value types where possible so they are testable in `AgentLensAppSupportTests` (F-1). |
| **AgentLensApp** | `OverviewView`, `UpdatesView`, `SettingsView`, `ConflictSummaryView`, the seven-destination `MainWindow`, menus/commands, accessibility labels and announcements, appearance preference. | Native effects, native interaction, native accessibility. |

**Rule of thumb for the implementer:** *if it can be a value type in AppSupport, it must be.* The
App layer should be a rendering of AppSupport state, because the App layer has **no automated
test surface** (F-1).

---

## D. Operation journey completion

### D.1 What is already accepted (M10) and must not be redone

- Preparation is an opaque, one-shot authorization object (`OperationModels.swift:104-140`,
  `:349-383`); it cannot be built from display strings.
- The preview is fully reviewable: registry ID, installed/target versions, package, registry/tag,
  manager path, prefix, working directory, selected entry, selected target, the literal argv, and
  the effect disclosure (`OperationModels.swift:26-51`, `:290-314`).
- The destructive effect text is a single constant (`OperationModels.swift:20-22`, `:284-286`) and
  is presentation-only — never executed.
- Cancel performs zero mutation; the result is a measured delta, never a rollback claim
  (`:143-167`, `:387-428`).
- One mutation at a time (`OperationExecutionGate`, `:261-278`).
- D-021 fail-closed, before any observation or scratch claim
  (`NpmUpdateOperation.swift:61-64`, `NpmUninstallOperation.swift:51-54`).

### D.2 What is actually missing for M12

| Gap | Evidence | M12 response |
|---|---|---|
| No entry point to an operation except the bottom of a tool detail | `ToolDetailView.swift:280-311,523-539` | M12-D: the Updates destination offers a prepare control per eligible row |
| The Updates destination itself does not exist | — | M12-B/C/D |
| Availability is npm-specific and view-local | F-3 | M12-A's `OperationCapability`; M12-D's D-D3 |
| "Review output" is impossible after the sheet closes | F-6 | M12-A's last-operation summary; M12-D's D-D5 |
| The post-rescan winner/version is not surfaced as an explicit step | `:389-391` publish the snapshot, but no surface states the new winner | M12-D's D-D6 |
| Return confirms an Update but cancels an Uninstall | F-2 | M12-D's D-D4 |
| The operation sheets have no accessibility labels | F-8 | M12-E's D-E5 |

**Explicitly NOT missing** and therefore NOT to be redone: the prepare/confirm/execute pipeline,
the Core operations, the CLI, the D-021 gate, the effect texts, the reconciliation model, the
cancellation semantics, the busy-gate, the cleanup warnings.

### D.3 The capability-driven availability pattern M13–M15 will reuse

The pattern has four states and one rule:

- **Rule:** *a control is offered only when the capability is `.eligible`; otherwise the reason is
  shown in place of the control.* Never hidden, never a disabled button with no explanation, never
  speculative.
- The states and their reason sources are fixed in D-A7.
- **M13's Homebrew adapter will slot into `OperationCapability` as a new `OperationKind`-scoped
  case plus its own Core reason enum — with no change to the M12 UI.** The AppSupport type is
  deliberately manager-agnostic in *shape* while today only npm is eligible.
- **M12 does not add a `HomebrewUpdateUnavailableReason`, does not add a "Homebrew Update…"
  button, and does not add a Homebrew capability case.** Those are M13's work, in M13's own phase.
  Adding them now would be a speculative surface (brief §I).

---

## E. Native polish, accessibility, and Settings

### E.1 Native menu bar commands

Fixed in D-E1. Summary: app menu (Settings… ⌘,), File (Rescan ⌘R, Check for Updates ⌘U, Refresh
Update Metadata ⌘⇧U), Edit (standard + Find ⌘F), View (⌘1…⌘7), Window (standard). **No mutation
command exists in any menu.**

### E.2 Keyboard navigation and shortcuts

- ↑/↓: native `List` selection (no code).
- Return (in a list): move focus to the detail column.
- Return (in a sheet): **never** confirms a mutation (D-D4). Escape cancels.
- Tab / Shift-Tab: full focus traversal, including both path-action buttons on both path rows.
- ⌘F: focus the search field. ⌘1–⌘7: switch destination. ⌘R/⌘U/⌘⇧U: rescan/check/refresh.
- **No bare-letter shortcuts** (D-E2). **No ⌘K palette in M12** (D-E1).
- **No shortcut ever executes a mutation.** Prepare is a control in a surface; Confirm is a
  control in a sheet with no key equivalent.

### E.3 VoiceOver labels, hints, and spoken checks

Per-surface requirements in D-E5; the measurement method in §F.2.

### E.4 Transient feedback announcement

D-E4.

### E.5 Large text and narrow windows

D-E6 and D-E7.

### E.6 Light/dark appearance

D-E8.

### E.7 Settings honesty — the enumeration the brief asks for

**What delivered features could legitimately be controlled today?**

| Feature | Delivered? | Legitimately controllable? | Why |
|---|---|---|---|
| Light/dark appearance | **Yes** (M12-E) | **Yes** | It is itself a delivered M12 feature; the control is presentational and stores no inventory fact |
| Update-check behaviour (Check vs Refresh) | Yes, as two explicit commands | **No** — a preference would be a third behaviour, and "check automatically" is M16 | Two explicit commands already cover it truthfully |
| Copy/Reveal behaviour | Yes | No | No meaningful option exists; behaviour is already fail-closed per path |
| Inventory scope (on-PATH / off-PATH) | Yes | No | Changing the counts would change D-006 semantics |
| Detail verbosity (raw PATH evidence) | Yes (Diagnostics) | No | The evidence is the product's reason to exist; hiding it is not a preference |
| Cached launch / menu-bar presence / opt-in periodic checks | **No** (M16) | **No** — M12 must not expose them | ROADMAP §4 M16; exposing them would be a speculative toggle |
| Telemetry / analytics / account | No, and out of scope | **No** | D-003: zero backend, no accounts, no telemetry |

**Conclusion:** exactly **one** legitimate toggle exists today — Appearance. The Settings surface
is therefore minimal and truthful: Appearance, About, and a plain-language statement of what is
manageable today and what is not delivered. See D-E9.

**Recorded reason for anything not offered:** every absent control is either an M16/M17/M18/M19
feature or a semantic change to a settled decision. That reason is stated *in the product*, in the
"Manageability" section of Settings — so the absence is explained, not silent.

---

## F. M8 keyboard gate closure and the accessibility measurement method

### F.1 The keyboard-only Copy/Reveal measurement

**What must be proven.** In the **real app**, with **no mouse**, for **both** path rows of
**both** the Selected Entry and the Resolved Target:
1. the path-action button is reachable by **keyboard focus traversal**;
2. a documented **activation key** activates it;
3. the **observable effect** is exactly correct;
4. the transient feedback appears (and is announced) and does not leak to another tool.

**Why AXPress is insufficient.** An AX `AXPress` action invokes the control's action directly; it
does not exercise focus traversal or key activation. It therefore **cannot** close a gate that is
specifically about *keyboard-only activation*. The M10-D precedent used AXPress for a
*click-through* (`walkthroughs/M10-D-implementation-evidence/native/native-actions.txt`) — valid
for that purpose, insufficient for this one.

**Method (executable on this machine by the orchestrator).**

*Environment.*
- Build the ordinary debug app with the existing builder:
  `python3 scripts/build-dev-app.py --scratch-root <scratch>/app --configuration debug`.
- Launch it under the M10-D recipe: synthetic `HOME`/`ZDOTDIR`/`TMPDIR`/`PATH` and the strict
  profile, so the scan sees a disposable, controlled environment
  (`walkthroughs/M10-D-implementation.md:141-160`).
- **Copy/Reveal are read-only with respect to the machine** (they write the clipboard and ask
  Finder to select an item). The M12 keyboard measurement may therefore run against **live
  installed tools** for the *real* app. The disposable npm fixture is required only for the
  *mutation* journey (M12-D), never for path actions.
- **TCC prerequisites** (state these in the plan; they were previously granted for M10-D —
  `walkthroughs/M10-D-implementation.md:143` "After the owner granted Accessibility"):
  - **Accessibility** permission for the driving process (to post key events and to read the
    accessibility tree);
  - **Automation** permission if AppleScript is used to query Finder's selection;
  - **Screen Recording** permission for `screencapture` (if screenshots are taken);
  - **VoiceOver** enabled/disabled is a *system preference change* — the orchestrator must record
    the before-state and restore it. Owner approval is recommended before flipping it.

*Procedure (per path row).*
1. Bring the app to the front; **do not use the mouse at all** from this point.
2. Post real key events to move focus into the content/detail column, then traverse with Tab
   (and Shift-Tab in reverse) until the accessibility focus lands on the target button.
   - Record, for every step, the focused element's **role, title, description, enabled state and
     AXFocused value**. This is the **focus-traversal transcript**.
   - Record the **key sequence** that reached the button.
3. Press **Space**. Observe: the button's action fires, the transient feedback text appears, and
   focus remains on (or returns to) the button.
4. Press **Return** on a fresh traversal. Observe the same effect.
5. **Clipboard read-back**: `pbpaste` must equal the exact displayed path, byte-for-byte.
   Compare `pbpaste | shasum -a 256` against `printf '%s' "$expected_path" | shasum -a 256` and
   record both digests plus the literal strings.
6. **Finder selection observation**: after activating "Reveal in Finder" on the Resolved Target,
   record (a) the frontmost application (`osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true'`) and (b) the path Finder has selected
   (`osascript -e 'tell application "Finder" to POSIX path of (selection as alias)'` or, via the
   accessibility tree of the Finder window, the selected row's URL). The selected path must equal
   the recorded canonical target exactly — not the parent, not a newly re-resolved symlink.
7. **Negative controls:**
   - a **non-actionable** row (a tool with `.notInstalled` or `.inconsistent` selection) exposes no
     enabled action, and traversal must not be able to activate anything;
   - after switching to another tool, the previous tool's feedback must **not** be visible
     (the `.id(identity)` reset at `ToolDetailView.swift:434` must still work);
   - the clipboard must be **unchanged** by a traversal that only focuses a disabled control.
8. Repeat steps 2–7 for the **other** path row, and then for a second tool, to prove the labels
   are unique and the feedback does not leak.

*Evidence format.* A single markdown transcript plus the raw artifacts:
`keyboard-actions.txt` (the focus traversal, key by key, with AX facts), `clipboard-readback.txt`
(the two digests and the literal strings), `finder-selection.txt` (frontmost app + selected path),
and screenshots of the focused button and the resulting feedback. Format modelled on
`walkthroughs/M10-D-implementation-evidence/native/native-actions.txt`.

*What counts as a failure.* Any of: the button cannot be reached by keyboard; Space or Return
does not activate it; the clipboard does not match byte-for-byte; Finder does not select the
recorded target (or selects the parent or a re-resolved symlink); the feedback is missing, stale
or attached to the wrong tool; a disabled control can be activated; the labels are ambiguous
between the two rows or two tools.

*Note on the shipped clipboard.* Copy writes the exact literal text with no newline, no quoting and
no `file://` prefix (`PathActions.swift:148-152`; `PathActionDispatcher` at
`PathActionTarget.swift:203-208`). The read-back expectation is the **exact path string**, and a
trailing newline would be a failure.

### F.2 The VoiceOver spoken-check method

Two layers, because spoken output cannot be captured programmatically on this machine with the
project's zero-dependency constraint.

**Layer 1 — structural (automatable, AX).** For every element the user must hear, the orchestrator
records `AXRole`, `AXTitle`, `AXDescription`, `AXValue`, `AXHelp`, `AXEnabled`, `AXSelected` and
`AXFocused`. The check is a **presence and consistency rule**:
- every interactive element has a non-empty `AXTitle` **or** `AXDescription`;
- the spoken string **never contradicts** the visible string or the underlying fact — in
  particular an `unknown` update status is never announced as "up to date" or "current"
  (D-007), and a destructive control is announced as destructive;
- the two path rows of one tool and two tools' controls have **distinct** spoken names.

The output is a machine-checkable element inventory: a table of element → spoken string, plus a
list of elements that failed the presence rule.

**Layer 2 — audible (orchestrator-performed, transcribed).** With VoiceOver enabled, the
orchestrator performs the journey by keyboard only and, for each surface (list row, detail,
path action, ownership, update status, operation preview, operation output, operation result,
unavailable reason, error banner, Settings), **writes down the exact announcement heard** and
cross-checks it against the Layer-1 expected string. The transcript is filed with a timestamp and
an explicit note that it is a **manual transcription, not an automated capture**. If a spoken
string differs from the expected string in a way that changes meaning, that is a defect.

**Prerequisites.** Accessibility permission; VoiceOver enabled (a system preference change — record
and restore the before-state; owner approval recommended); for the audible layer, a human listener
(the orchestrator).

**What counts as a failure.** An interactive element with no spoken identity; a spoken string that
contradicts the visible text or the underlying typed fact (especially `unknown` read as
"up-to-date"); a disabled control announced as available; a destructive control announced without
its destructive nature; a spoken string that omits the tool or the row it belongs to.

---

## G. Acceptance strategy

### G.1 Per-phase gates

Every phase runs and records, in a fresh scratch root outside the repository:

```sh
env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS swift build
env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS swift test --no-parallel
python3 scripts/check-core-ui-imports.py
python3 Tests/Packaging/test_core_ui_imports.py
python3 scripts/build-dev-app.py --scratch-root <scratch>/app --configuration debug
python3 Tests/Packaging/test_dev_app_bundle.py --app <scratch>/app/AgentLensApp-debug.app
```

On this CLT-only workstation the `swift test` invocation needs the documented invocation-local
TestingMacros plugin flag (`briefs/M8-path-actions.md:183-187`; also
`briefs/M11-B-mutation-gate.md:139-145`). The implementer uses the documented fallback; it must
**not** install or modify the toolchain, and must report the exact failure if the plugin path is
unavailable.

Additionally, per phase:
- SHA-256 of every changed file, and a **protected-file manifest diff** proving that only
  allow-listed files changed;
- the **Core test count must remain 467** in every phase (no Core change is permitted) — a change
  is a scope violation and must be reported, not absorbed;
- the **AppSupport count** rises above 80 and the **total** above 547. The CI floors are raised
  **only** to the orchestrator-measured counts, **never lowered** (`ci.yml:152-157`, `:193-197`).

### G.2 The combined M12 gate — the ROADMAP journey matrix

Every row is exercised **in the actual app**, in the disposable environment for anything that
mutates, and against live read-only tools for anything that does not.

| # | Journey / condition | Observable result required | Fixture / method |
|---|---|---|---|
| 1 | **find/filter** | Search text narrows the list; the category destination narrows to its category; the update filter narrows by tri-state; counts stay global | AppSupport tests + native spot-check |
| 2 | **inspect competing copies** | The conflict summary lists the tool with its kind, copy count and measured versions; activating it lands on the per-installation PATH evidence and versions in Diagnostics | AppSupport tests + native spot-check with a synthetic multi-copy tree |
| 3 | **confirm an eligible operation** | Codex (npm-global, ownership-verified) → Prepare Update/Uninstall → preview sheet with the full reviewable preview | `Tests/Fixtures/M10C/npm_update_acceptance.py --scenario controlled`; `Tests/Fixtures/M10D/npm_uninstall_acceptance.py --scenario controlled`; native sheet in the disposable app |
| 4 | **cancel an eligible operation** | Cancel → **zero** mutation; the prefix SHA-256 manifest is byte-identical before/after | same fixtures; the M10-D Cancel-unchanged pattern (`walkthroughs/M10-D-implementation.md:149`) |
| 5 | **review output** | The result sheet shows state, exit status, stdout, stderr (with the truncation marker) and the reconciliation delta; **and** the retained last-operation summary survives dismissal | native click-through + a D-05 AppSupport test |
| 6 | **observe the post-rescan winner/version** | The tool row shows the new winner and the new local version; the Updates row states the new PATH winner explicitly | native screenshot + the fixture's own verification (`M10D --scenario combined`) |
| 7 | **empty inventory** | The app shows a truthful empty state (not an error), and every destination's empty state is distinct | AppSupport test + native spot-check with an empty registry override in the disposable environment |
| 8 | **offline** | The local inventory still works; latest checks degrade to `unknown` with a typed reason; unknown never counts as up-to-date | `agent-lens scan --offline` parity + native; M6's offline contract |
| 9 | **failed rescan** | The retained snapshot stays published beside a "Rescan Failed" banner; no stale update badge is presented as current | `InventoryViewModel.runPipeline` (`:804-811`) + native |
| 10 | **missing manager** | Preparation is refused with the Core reason (`managerUnavailable`), not an error and not a silent absence | AppSupport test + the Core reason text |
| 11 | **permission denial** | The refusal is a truthful typed reason (e.g. `operationRootUnsafe`), never a claimed success | AppSupport/Core test |
| 12 | **long paths** | Long paths wrap; no safety text is clipped; the path remains selectable and copyable verbatim | native screenshots at the narrow floor + a long-path fixture |
| 13 | **keyboard-only** | The M8 gate is closed per §F.1, for both rows and both actions | the §F.1 measurement, with the transcript |
| 14 | **VoiceOver** | Every surface has a truthful spoken identity; the Layer-1 inventory and the Layer-2 transcription are on file | the §F.2 method |
| 15 | **capability truthfulness** | A non-accepted entry shows the exact Core reason and no control; a cask-only entry shows no latest version; no Homebrew/uv/Cargo control exists anywhere | AppSupport tests + native spot-check |
| 16 | **shortcut safety** | No key anywhere executes a mutation; Return never confirms; the destructive button has no key equivalent | native + AX transcript |

**Mutation rows (3, 4, 5, 6) run only against the disposable npm fixture.** **No personal
installation is ever an acceptance target** (ROADMAP §4 M12 acceptance; ROADMAP §6).

### G.3 Combined gate mechanics

- **Local:** the full gate set of §G.1, rerun by the orchestrator in a clean shell (D-014), at the
  frozen candidate SHA.
- **Hosted:** all **seven** gates at the **exact candidate SHA**
  (`ci.yml:585-586`: `guard`, `guard-fixtures`, `swift-build`, `isolation-gate`,
  `full-test-suite`, `build-dev-app`, `packaging`), with the floors raised to the measured counts
  and the two anchor groups (`ci.yml:198-204`) present.
- **Floor policy:** raise only to orchestrator-measured counts; **never lower** a floor; never
  change an anchor.
- **Protected-file manifests:** a SHA-256 manifest of every repository file at the phase baseline,
  compared at the phase acceptance; every difference must be inside the phase allow-list.
- **Evidence:** raw argv, stdout/stderr, exit codes and durations for every command; SHA-256 of
  every changed file; the protected-file diff; the native transcripts and screenshots; the
  fixture receipts.

### G.4 What is NOT an acceptance target

- Personal installations of any tool (never mutated, never used as a mutation target).
- A specific count of installed tools, a specific update-available count, or any absolute number
  of conflicts — these are machine facts, not acceptance criteria.
- The user's real clipboard contents (the read-back must match the path that was copied, and the
  prior clipboard is preserved/restored where feasible — `briefs/M8-path-actions.md:145-146`).
- Performance or launch-time budgets (M16 owns the sub-300 ms cached-launch target; M12 measures
  nothing of the kind).
- Any M13–M16 capability.
- The other council member's proposal.

---

## H. Risks and open questions

### H.1 Ranked risks

| # | Risk | Severity | Mitigation in this plan |
|---|---|---|---|
| R1 | **A new filter, destination or list action retargets a pending confirmation** — the preview would then describe a different tool than the one that gets confirmed | **High** (safety) | D-A8 enumerates nine triggers; D-A9 puts destination state in the ViewModel; D-D2 binds preparations to registry ID + observed selection; C.6 requires one test per trigger plus a seeded-corruption test; the trigger set is the first thing M12-A does, before any surface exists |
| R2 | **The M8 keyboard gate is "closed" with an AXPress transcript**, which does not demonstrate keyboard activation | **High** (gate integrity) | §F.1 requires real key events and explicitly rejects AXPress as sufficient; D-F1/D-F2 forbid editing a transcript to make it pass |
| R3 | **Scope creep into M13–M16** — a Homebrew button, an auto-check toggle, a cached-launch preference | **Medium–High** | Brief §I is binding; D-D7 forbids speculative capabilities; D-E9 enumerates the *only* legitimate toggle; "no speculative Settings toggles" is an acceptance row (G.2 #15) and a stop condition in M12-E |
| R4 | **Flash-tier implementer ambiguity** — the implementer invents a filter, a shortcut, or an unavailable-state wording | **Medium** | Every phase resolves its design decisions explicitly (D-A1…D-A10, D-B1…D-B7, D-C1…D-C6, D-D1…D-D8, D-E1…D-E10, D-F1…D-F3); each phase's brief must quote the decision list verbatim; anything not in the list is a stop, not a judgement call |
| R5 | **App-layer logic is untestable** (F-1) and regresses silently | **Medium** | The Core→AppSupport→App layering rule (C.7) plus the "if it can be a value type in AppSupport, it must be" rule; the orchestrator's native spot-check is the App evidence, exactly as M11-B accepted (F-5) |
| R6 | **Accessibility regressions** — new surfaces ship without labels, or the F-2 fix changes an accepted interaction | **Medium** | M12-E has its own phase and its own review; D-E5 enumerates the required spoken content; G.2 rows 13–14 are acceptance gates, not "nice to have" |
| R7 | **CI integrity** — floors lowered, anchors changed, a Core file touched to make a UI change easier | **Medium** | G.1: Core count must remain 467 in every phase; floors raise-only; anchors frozen; the protected-file manifest catches a Core edit immediately |
| R8 | **Native-measurement feasibility** — TCC/Automation/Screen Recording permissions are missing, or VoiceOver speech cannot be captured | **Medium** | §F.1/F.2 state the prerequisites up front and require the orchestrator to report a permission blocker rather than substitute a weaker method; Layer 2 is explicitly a manual transcription and is labelled as such |
| R9 | **The capability model drifts from the published matrix** (`docs/capability-matrix.md`) | **Low–Medium** | D-A7 derives availability from the **registry's** `acceptedOperations` (the single source the matrix test already enforces), not from the Markdown; the matrix test keeps the document and the registry in agreement, so the model cannot drift from either |
| R10 | **The M12-D footer key-equivalent change invalidates accepted M10 evidence** | **Low** | D-D4 names the change explicitly, shows that the M10-D native click-through used AXPress rather than the Return key, and requires the M12-D independent reviews |
| R11 | **A returned `InventoryEntry` per operation makes the ViewModel heavy** and the flash implementer over-engineers | **Low** | D-A10 scopes the summary to state/exit/output/delta/time, per registry ID, in-memory only, never persisted |

### H.2 Owner decisions (only the owner can make)

**OD-M12-1 — Does the M12 Settings surface include an Appearance control?**
*Recommendation: **yes** — System / Light / Dark only.*
Rationale: appearance is itself a delivered M12 feature, so the control governs a delivered
feature rather than a speculative one; it stores no inventory fact. The alternative — a Settings
destination with **zero** controls (About + truthful statements only) — is also defensible and is
strictly more conservative.
*If declined:* M12-E ships Settings with About + the manageability statement only, and the
appearance remains system-driven. Nothing else changes; the phase is not blocked either way.

**OD-M12-2 — Should the Updates destination show rows whose latest version is unknown?**
*Recommendation: **yes** — as neutral rows with the typed reason.*
Rationale: hiding them would make the catalogue *less* understandable and would contradict the
"unknown is neutral and truthful" invariant (D-007); the counts already keep them out of the
update-available badge. The alternative (only actionable rows) makes the destination look empty
on a machine with no network.
*If declined:* the Updates destination lists only `.updateAvailable` rows, and the unknown count
appears only in Overview.

**OD-M12-3 — Is Overview a separate dashboard, or a filtered view of the tool list?**
*Recommendation: **a separate dashboard** (counts + conflict summary + updates available + a
complete all-tools table).
Rationale: the ROADMAP user result is that the seven destinations "make the complete catalogue
understandable", which requires a place where the whole catalogue is visible at once; the three
category destinations alone would not.
*If declined:* Overview becomes a fifth list scope (all tools), and the conflict summary moves
into the Diagnostics destination (which changes C.4 and the C.5 navigation design).

**OD-M12-4 — Should the conflict summary be its own destination or a section?**
*Recommendation: **a section inside Overview**, with rows navigating to Diagnostics.*
Rationale: it is an index of the per-tool evidence, not evidence itself; a separate eighth
destination would contradict the ROADMAP's seven and would duplicate `DiagnosticsView`.
*If declined:* it becomes an eighth destination; the phase grows, and the "no duplication" rule
must be restated as "no duplication of the *evidence*".

**OD-M12-5 — Should M12 add an `AgentLensAppTests` Swift test target?**
*Recommendation: **no — do not add it in M12.***
Rationale: it changes `Package.swift` and the CI floor/anchor configuration, and the plan already
mitigates the underlying problem by keeping all testable logic in AppSupport (C.7). M11-B
already accepted orchestrator-native-spot-check as the App evidence (F-5). Adding a target is a
project-structure change that deserves its own decision.
*If you want it:* it must be a separate phase with its own baseline, its own floor change, and a
decision about how App-layer SwiftUI views are made testable at all (SwiftUI view testing is
fragile; the better investment is the AppSupport extraction).

**OD-M12-6 — Is the `⌘K` command palette in or out of M12?**
*Recommendation: **out.*** ⌘F (Find) ships instead, which is the native macOS convention for
focusing a search field. A palette is a feature beyond M12's stated requirements and would need
its own design and acceptance.
*If you want it in:* it adds a new surface, a new command model, and an accessibility surface to
M12-E — a materially larger phase, and it would need its own acceptance rows.

**OD-M12-7 — Does the owner approve the orchestrator flipping VoiceOver on this machine for the
spoken checks?**
*Recommendation: **yes, with a recorded restore.*** Layer 2 of §F.2 cannot be produced without
VoiceOver enabled. The orchestrator records the before-state and restores it afterwards.
*If declined:* Layer 2 is replaced by the Layer-1 structural inventory only, and the combined
gate records the audible layer as **not evidenced** — which is an honest limitation, not a pass.

### H.3 Things I could not resolve

1. **I did not re-read `Sources/agent-lens/main.swift` beyond its dispatch table**, so I cannot
   assert with certainty that no CLI surface renders an update/uninstall control. D-022 and the
   M11-B ruling (CLI mutation surface is vacuous by ruling) make this almost certainly irrelevant
   to M12, but it is **unverified** at the line level.
2. **I did not re-measure the test suite.** The 547 / 467 / 80 / 21 / 9 figures are read from
   `.github/workflows/ci.yml:152-207` and the M11-F acceptance record, not from a run. The brief
   forbids running tests; the orchestrator must re-measure the baseline at dispatch.
3. **`InventoryService.swift`'s internal prepare/execute bodies were not read line by line** (only
   its public API surface was enumerated). M12 does not modify that file, so the risk is limited
   to my claims about the reconciliation flow — which I take from
   `InventoryViewModel.swift:389-391,542-544` and the M10-D acceptance record, both visible.
4. **The AppKit accessibility announcement API** (D-E4) is named by its conventional selector, but
   I have not verified its exact availability in this toolchain. The plan makes the implementer
   confirm it and provides a fallback; this is deliberately not a blocker.
5. **VoiceOver speech capture is not automatable here** without a dependency the project forbids;
   §F.2 Layer 2 is therefore explicitly a manual transcription and is labelled as such.

---

## I. Explicit non-goals (binding)

Reproduced from the council brief and re-affirmed for this plan:

- **No new manager mutation adapters** (M13–M15). No Homebrew, uv/pip, Cargo or any other
  operation code, and no speculative capability cases for them (D-D7).
- **No per-tool mutation promotions.** `codex` remains the only entry whose
  `acceptedOperations` contains `npmUpdate`/`npmUninstall` (D-021).
- **No cached launch, menu-bar presence, or opt-in periodic checks** (M16) — and no Settings
  toggles for them (D-E9).
- **No bundled CLI** (M17). **No release, signing, notarization or publication** (M18–M19).
- **No CLI mutation syntax** (D-022). `Sources/agent-lens/main.swift` is not in any phase's
  allow-list.
- **No registry / schema / detector changes.** `Sources/AgentLensCore/Detectors/DefaultDetectors.json`
  and the schema version are protected in every phase. The `acceptedOperations` vocabulary stays
  closed (`DetectorMetadata.swift:78-81`).
- **No new dependencies.** The package stays at zero external packages (`Package.swift`).
- **No speculative Settings toggles** (D-E9, OD-M12-1).
- **No public contribution invitation.**
- **No personal installation as an acceptance target** (G.2).
- **No Core changes at all** in M12 — the Core test count must remain 467 in every phase (G.1).
- **No change to the CLI dispatch**, the M10 preview semantics, the Core reason texts, or the
  D-021 gate ordering.
- **No transcript editing, re-shooting, or re-narrating** of native evidence to make a gate pass
  (D-F2).

---

## Appendix — citation index

Everything cited above is in the working tree at `milestone/m11-catalogue` tip `0589fac`.

| Path | Lines cited | Used for |
|---|---|---|
| `Sources/AgentLensApp/MainWindow.swift` | 6-11, 20-24, 54-64, 87-136, 137-148, 153-184, 192-225, 227-234, 238-280, 317-379, 443-487, 492-507 | navigation, sidebar, toolbar, sheets, lifecycle |
| `Sources/AgentLensApp/ToolListView.swift` | 14-30, 32-45, 47-77, 80-106, 146-163 | search, list, empty states, row accessibility |
| `Sources/AgentLensApp/ToolDetailView.swift` | 56-112, 199-238, 245-255, 268-270, 280-311, 318-354, 402-435, 439-541, 577-618 | detail sections, path rows, manage/update availability |
| `Sources/AgentLensApp/PathActions.swift` | 18-104, 106-135, 142-159 | path action controls, dispatcher wiring, native effects |
| `Sources/AgentLensApp/OwnershipVerificationView.swift` | 11-115, 118-171 | ownership UI, labels, fixed-hue colour |
| `Sources/AgentLensApp/UpdateOperationView.swift` | 36-59, 62-81, 83-135, 137-203, 215-223 | update sheet, footer key equivalents |
| `Sources/AgentLensApp/UninstallOperationView.swift` | 55-86, 88-129, 141-219 | uninstall sheet, footer key equivalents, result/output panes |
| `Sources/AgentLensApp/AgentLensApp.swift` | 6-19, 158-167 | entry point, scene, default size |
| `Sources/AgentLensAppSupport/InventoryViewModel.swift` | 34-42, 85-132, 141-214, 223-302, 306-454, 458-612, 615-677, 689-757, 787-831, 836-915, 919-960 | presentation state, invalidation, selection, pipeline |
| `Sources/AgentLensAppSupport/InventorySnapshot.swift` | 19-70, 73-103 | entry/snapshot model, counts |
| `Sources/AgentLensAppSupport/PathActionTarget.swift` | 21-168, 174-213 | path eligibility, dispatcher |
| `Sources/AgentLensAppSupport/InventoryService.swift` | 25-52, 122-135, 215-217, 270-298, 364-412, 418-471 | public service surface |
| `Sources/AgentLensCore/Detection/DetectorMetadata.swift` | 46-58, 61-73, 78-81, 84-160, 263-316 | category, managers, accepted operations, validation |
| `Sources/AgentLensCore/Operations/OperationModels.swift` | 20-22, 26-51, 54-94, 97-140, 143-167, 170-212, 261-278, 284-339, 349-383, 387-471 | previews, reasons, preparations, deltas, outcomes |
| `Sources/AgentLensCore/Operations/NpmUpdateOperation.swift` | 61-64 | D-021 Core gate ordering |
| `Sources/AgentLensCore/Operations/NpmUninstallOperation.swift` | 51-54 | D-021 Core gate ordering |
| `Sources/AgentLensCore/Diagnostics/PathDiagnostics.swift` | 78-97, 121-136 | conflict inputs |
| `Sources/agent-lens/main.swift` | 61-63, 114-116, 160-163 | CLI dispatch (read-only) |
| `Package.swift` | 6-8, 14-44 | targets, no App test target |
| `.github/workflows/ci.yml` | 152-157, 179-208, 585-586 | floors, anchors, seven gates |
| `AGENT_LENS_SCOPE.md` | 196-219, 250-271, 821-828, 1006-1021 | §7 filters/shortcuts, §9 UI, §27 notes |
| `ROADMAP.md` | 43-51, 93-105, 194-224, 226-238 | M12 requirements, protocol, owner gates |
| `DECISIONS.md` | 19-120, 365-491 | settled decisions, D-019…D-023 |
| `briefs/README.md` | 19-27, 56, 62-73, 77-79 | brief rules, M11 records, M8 keyboard gap |
| `briefs/M11-B-mutation-gate.md` | 1-167 | format calibration, gate commands, D-021 contract |
| `briefs/M8-path-actions.md` | 39-84, 114-195 | M8 contract, the open keyboard gate, CLT plugin flag |
| `walkthroughs/M10-D-implementation.md` | 141-160 | native click-through precedent |
| `walkthroughs/M10-D-implementation-evidence/native/native-actions.txt` | 1-30 | native transcript format |
| `walkthroughs/M11-B-acceptance.md` | 11-86 | review precedent, native spot-check, matrix |
| `docs/capability-matrix.md` | 9-24, 26-41, 43-53 | capability rules, 14 rows |
| `Tests/AgentLensCoreTests/CapabilityMatrixTests.swift` | whole file | matrix enforcement rules |
| `Tests/Fixtures/M10C/npm_update_acceptance.py` | 1407-1414 | fixture CLI surface |
| `Tests/Fixtures/M10D/npm_uninstall_acceptance.py` | 1040-1044 | fixture CLI surface |
