# M12-A dispatch brief — presentation-state foundation (AppSupport only)

Status: **FROZEN dispatch brief.** Implementer receives ONLY this brief (not the scope document).
Authority: `briefs/M12-plan.md` (frozen master plan) and `briefs/M12-planning/judgment.md`
(rulings R1–R16, binding). This brief quotes the rulings that govern M12-A.

```text
MILESTONE:   M12 — complete native diagnostic and operation workflow
PHASE:       M12-A — presentation-state foundation (AppSupport only; safety phase)
BASE:        1f251d4 (milestone/m12-workflow; frozen plan commit). Product base 0589fac.
BRANCH:      milestone/m12-workflow (already checked out; do NOT switch/rebase/branch)
WORKER:      DeepSeek V4.1 Flash 1017 via OMP (river/deepseek-ai/DeepSeek-V4.1-Flash-1017), max
GOAL:        A testable, UI-free AppSupport presentation model exists for list scope, detail pane,
             the update-status filter, conflict classification, management availability, derived
             counts, and the extended confirmation-invalidation trigger set. The app is visually
             UNCHANGED at the end of this phase. The behavioral change: any future scope/filter/
             selection change releases a pending preview with zero mutation.
```

## 1. Required reading (in this order)

1. `briefs/M12-plan.md` §3 (safety envelope), §4 (rulings summary), §5 M12-A, §6 (evidence).
2. `briefs/M12-planning/judgment.md` rulings **R1, R2, R3, R4, R8, R12, R16** (full text).
3. `Sources/AgentLensAppSupport/InventoryViewModel.swift` — especially `searchText.didSet` (:97-101),
   `select(registryID:)` (:196-214), `filteredEntries` (:181-185), `matches` (:938-960),
   `invalidatePendingUpdate()` (:615-677, the executing early-return at :621),
   `prepareSelectedUpdate` (:306-367), `prepareSelectedUninstall` (:458-520),
   `verifySelectedInstallation` (:248-302), `run` (:689-757), `reconcileSelection` (:905-915),
   `ObservedSelection` (:919-934).
4. `Sources/AgentLensAppSupport/InventorySnapshot.swift` — `InventoryEntry`, the three counts.
5. `Sources/AgentLensCore/Diagnostics/PathDiagnostics.swift` — `PathSelection` (:78-83),
   `ToolPathDiagnostic` fields (:85-97), `shadowedInstallationCount` derivation (:242-251),
   `installationVersions`, `canonicalTargetCount`, `liveCandidates`.
6. `Sources/AgentLensCore/Detection/DetectorMetadata.swift` — `ToolCategory` (:46-58),
   `PackageManager` (:61-73), `AcceptedOperation` (:78-81), `DetectorDefinition`.
7. `Sources/AgentLensCore/Operations/OperationModels.swift` — `NpmUpdateUnavailableReason` /
   `NpmUninstallUnavailableReason` (the `operationNotAccepted.message` strings; read, never retype).
8. `Sources/AgentLensApp/ToolDetailView.swift` — the current button predicates you must reproduce
   exactly: Manage section (:280-311), Update button (:523-539), `hasDeclaredNpmPackage` (:268-270).
9. `Tests/AgentLensAppSupportTests/InventoryViewModelTests.swift` — the existing test style and the
   fake service/clock seams. Do NOT weaken any existing case.

## 2. FILES — explicit allow-list

Production (modify):
- `Sources/AgentLensAppSupport/InventoryViewModel.swift`
- `Sources/AgentLensAppSupport/InventorySnapshot.swift` (additive derived count helpers ONLY)

Production (new):
- `Sources/AgentLensAppSupport/WorkflowPresentation.swift`

Tests (new):
- `Tests/AgentLensAppSupportTests/WorkflowPresentationTests.swift`

Tests (modify — new tests only, never weaken existing):
- `Tests/AgentLensAppSupportTests/InventoryViewModelTests.swift`

Worker report (new):
- `walkthroughs/M12-A-implementation.md` (labeled WORKER EVIDENCE, not acceptance)

## 3. DO NOT TOUCH (binding — stop and ask, never edit)

`Sources/AgentLensCore/**` (ALL of it), `Sources/AgentLensApp/**` (ALL of it),
`Sources/agent-lens/**`, `Sources/AgentLensCore/Detectors/DefaultDetectors.json`,
`Sources/AgentLensAppSupport/InventoryService.swift`, `PathActionTarget.swift`,
`SessionEnvironmentProvider.swift`, `Package.swift`, `Tests/AgentLensCoreTests/**`,
`Tests/Fixtures/**`, `Tests/Packaging/**`, `scripts/**`, `.github/**`, `Resources/**`, `docs/**`,
`DECISIONS.md`, `ROADMAP.md`, `AGENT_LENS_SCOPE.md`, every existing `briefs/**` and
`walkthroughs/**` (except the new worker report above). No new dependency. No Core file. No SwiftUI
or AppKit import in AppSupport. Personal installations, the real Agent Lens cache, and credentials
are out of bounds. If a file outside this allow-list seems necessary, STOP and report the exact
reason and proposed files — do not edit it.

## 4. Contracts (quote of the binding rulings)

**R1 — navigation + invalidation (the core of this phase).** Add two orthogonal fields to
`InventoryViewModel`:
- `listScope`: `.all`, `.category(ToolCategory)`, `.updates` (default `.all`).
- `detailPane`: `.tool`, `.diagnostics`, `.settings` (default `.tool`).
- `updateStatusFilter`: `.all`, `.updateAvailable`, `.upToDate`, `.unknown`, `.notChecked`
  (default `.all`; applies only when `listScope == .updates`).

`filteredEntries` becomes: `entries → listScope filter → (if .updates) updateStatusFilter →
existing matches(searchText)`, in registry order, NEVER re-sorted. The `matches` predicate and its
haystack are UNCHANGED (R8: no category-label or package-name matching). Selection stays by registry
ID; a row hidden by a filter keeps its selection (today's behavior).

Invalidation: `listScope`, `updateStatusFilter`, and `searchText` changes, and selection-ID changes,
MUST call the existing `invalidatePendingUpdate()`. A pure `detailPane` change MUST NOT invalidate.
The executing-mutation early-return (`invalidatePendingUpdate` :621) is PRESERVED exactly: a launched
update/uninstall is never cancelled by a scope/filter/search/selection change. The existing four
triggers (searchText, select, verify, run) keep their behavior. Sheets bind to preview/preparation/
outcome/unavailable, NEVER `selectedEntry` (the App is unchanged this phase; this contract is locked
here for later phases).

Add `showPathEvidence(registryID:)`: selects that ID through `select(registryID:)` (so a different ID
invalidates) and sets `detailPane = .diagnostics`. For the already-selected ID it keeps a pending
preview; for a different published ID it invalidates then selects. An unknown ID is refused (mirror
`select`).

**R2 — Updates scope.** `listScope == .updates` includes only installed entries
(`installState != .notInstalled`). The `updateStatusFilter` then narrows by tri-state:
`.updateAvailable` → `if case .updateAvailable = entry.updateStatus`; `.upToDate` → `.upToDate`;
`.unknown` → `.unknown`; `.notChecked` → `entry.update == nil`; `.all` → no further narrowing.
Unknown is neutral: it never counts as up-to-date and never inflates `updateAvailableCount`.

**R3 — conflict classification (pure function of one InventoryEntry).** `ToolConflictKind` has
exactly three cases, in this order:
1. `shadowedCopy` — `diagnostic.shadowedInstallationCount ?? 0 > 0`.
2. `offPathCopy` — `diagnostic.selection == .offPath`.
3. `inconsistentDiagnostics` — `diagnostic.selection == .inconsistent(reason)`.
A tool's conflict record carries: registryID, displayName, the non-empty kind list (in order),
copyCount (`diagnostic.canonicalTargetCount`), the measured local versions from
`diagnostic.installationVersions` (`.measured` only; never a latest version, never a fabricated
version), the winner entry path (if `.winner`), the off-PATH root (if `.offPath`), and the
inconsistency reason (if `.inconsistent`; invent NO winner path). `sameTargetAliasCount` and
`repeatedPathSlotCount` are NOT conflict kinds. `notInstalled` is NOT a conflict. A single copy with
one canonical target produces NO conflict. The conflict-tool count counts TOOLS (one tool with two
kinds counts once). All inputs come from `ToolPathDiagnostic`; synthesize nothing.

**R4 — ManagementPresentation (pure function of one InventoryEntry; the single source of "is a
control offered, and why not").** Reproduce the current `ToolDetailView` predicates EXACTLY:

Update slot:
- `.prepareNpmUpdate` when `entry.updateStatus` is `.updateAvailable`, `entry.update?.npmPackage !=
  nil`, and `entry.definition.acceptedOperations.contains(.npmUpdate)`.
- `.unavailable(NpmUpdateUnavailableReason.operationNotAccepted.message)` when those version+package
  facts hold and `.npmUpdate` is absent. (Read the Core enum's string; NEVER retype it.)
- `.unavailable("A newer version is reported by the supported latest check. Managed update is not
  available for this installation in this version.")` when status is `.updateAvailable` and
  `npmPackage` is nil.
- `.hidden` otherwise (not-checked and unknown grow no update affordance).

Uninstall slot:
- `.prepareNpmUninstall` when `.npmUninstall` is accepted,
  `entry.ownership?.verifiedInstallation?.manager == .npm`, and selection is `.winner` or `.offPath`.
- `.unavailable(NpmUninstallUnavailableReason.operationNotAccepted.message)` when an npm package is
  declared and `.npmUninstall` is absent.
- `.needsVerification("Verify Installation to enable Uninstall for this npm package.")` when
  `.npmUninstall` is accepted and the verified-npm condition is false.
- `.hidden` when no npm package is declared.

`otherLimits` (included only when `installState != .notInstalled`, each at most once):
- a declared `homebrewFormula`: `"Homebrew formula update and uninstall are not available in this
  version."`
- a declared `homebrewCask`: `"Homebrew cask update and uninstall are not available in this version."`
- `diagnostic.detectedTool.source == "standalone"`: `"This copy is classified as standalone. Agent
  Lens does not delete standalone files."`
`codex` declares npm + cask: its npm slots follow the rules above; the cask sentence is ADDITIONAL
text and must not replace the npm affordances. A `source` of `"npm"` adds no standalone sentence. No
sentence names uv, pip, cargo, `brew upgrade`, `brew uninstall`, or a vendor self-updater. Sheet
unavailable reasons that Core already returns continue to use `reason.message` (the App keeps doing
this; this phase only builds the model).

**R12 — zero Core change.** Core test count stays 467. AppSupport rises above 80. No Core/CLI/
registry/Package.swift/scripts/.github edit. AppSupport imports Foundation and AgentLensCore only.

## 5. Acceptance (exact commands + expected observable results)

Evidence root (assigned, outside the repo): `R = $HOME/.hermes/cache/scratch/agent-lens-m12-a`.
Create `$R/tmp` and `$R/evidence`. Run from the repo root, fresh scratch, no toolchain/package change:

```sh
R="$HOME/.hermes/cache/scratch/agent-lens-m12-a"; mkdir -p "$R/tmp" "$R/evidence"
env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS swift build 2>&1 | tee "$R/evidence/build.log"
env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS \
  TMPDIR="$R/tmp" swift test --build-system swiftbuild --scratch-path "$R/full-suite" --no-parallel \
  -Xswiftc -load-plugin-library \
  -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib \
  2>&1 | tee "$R/evidence/full-suite.log"
python3 scripts/check-core-ui-imports.py 2>&1 | tee "$R/evidence/guard-core.log"
python3 scripts/check-core-ui-imports.py --source-root Sources/AgentLensAppSupport 2>&1 | tee "$R/evidence/guard-appsupport.log"
python3 Tests/Packaging/test_core_ui_imports.py 2>&1 | tee "$R/evidence/guard-fixtures.log"
TMPDIR="$R/tmp" python3 scripts/build-dev-app.py --scratch-root "$R/dev-app" --configuration debug 2>&1 | tee "$R/evidence/dev-app.log"
TMPDIR="$R/tmp" python3 Tests/Packaging/test_dev_app_bundle.py --app "$R/dev-app/AgentLensApp-debug.app" 2>&1 | tee "$R/evidence/packaging.log"
git diff --check
```

Expected: every command exit 0; full suite **Core 467 unchanged + AppSupport > 80, total > 547, zero
skips/failures**; guard fixtures 21; packaging 9; both import guards clean. If `swift test` fails
before any test with `TestingMacros … plugin not found`, the plugin flag above is the documented
workaround; if the plugin path is unavailable or the failure is different, STOP and report the exact
failure (do not install or modify tooling, do not switch xcode-select).

Required new tests (RED before the implementation exists, then GREEN — behavioral RED, not merely a
compile failure):
- One test per invalidation vector: `listScope` change, `updateStatusFilter` change, `searchText`
  change, selection-ID change — each asserts (a) the pending preparation is released, (b) the preview
  is cleared, (c) NO mutation pipeline started. Plus: a pure `detailPane` change leaves a pending
  preview in place; `showPathEvidence` for the same ID keeps the preview, for a different ID
  invalidates then selects.
- The launched-operation exemption: with `isExecutingUpdate`/`isExecutingUninstall` true, a scope/
  filter/search/selection change does NOT cancel the operation; the outcome slot and preview identity
  stay bound to the original registry ID.
- A seeded-corruption test proving the trigger set is non-vacuous (e.g. removing the `listScope`
  trigger makes a test fail).
- Updates scope membership: only installed entries; `.updateAvailable` filter excludes unknown/up-to-
  date/not-checked; an unknown whose name matches the query is still absent under `.updateAvailable`.
- Category scope intersects search; registry order preserved; search fields unchanged (category label
  and package name do NOT match).
- Conflict classification: positive + negative for each kind (single copy → no conflict; inconsistent
  with nil shadowed → `.inconsistent`; off-PATH with positive shadowed → both kinds; alias-only and
  repeated-slot fixtures → no kind).
- ManagementPresentation: codex-shaped affordances match the current button predicates exactly;
  formula-only, cask-only, standalone fixtures produce the fixed sentences and no prepare case; the
  npm `operationNotAccepted` text equals the Core enum's own string.
- Counts are snapshot-derived (a search/filter change does not change a badge count); unknown never
  inflates `updateAvailableCount`.

## 6. EVIDENCE (raw, unedited)

Under `$R/evidence`: raw argv + stdout/stderr + exit codes + durations for every command; SHA-256 of
every changed file; a protected-file manifest diff proving ONLY allow-listed files changed (hash every
tracked file at base `1f251d4`, compare at the candidate; every difference must be in §2). Record the
Core/AppSupport counts separately. Write `walkthroughs/M12-A-implementation.md` labeled WORKER
EVIDENCE (not acceptance): what you built, the RED→GREEN transcript, the counts, the changed-file
hashes, and any unverified/unobserved item (never claimed as passed). The orchestrator reruns every
gate independently (D-014); your PASS is evidence to inspect, not acceptance.

## 7. STOP conditions (stop and report, never improvise)

- A Core/registry/CLI change appears necessary.
- `invalidatePendingUpdate`'s executing early-return (:621) would have to change.
- `filteredEntries` would re-sort, or the `matches` haystack would grow.
- A test outside the allow-list fails for a reason that cannot be migrated inside it.
- The AppSupport floor cannot be raised to a measured count.
- Any design choice not resolved in this brief or the rulings (R1–R16) — report it, do not decide it.

## 8. DONE WHEN

The acceptance commands pass (orchestrator will rerun); the new tests are RED→GREEN with the
invalidation matrix covered; the diff is inside the allow-list with a clean protected manifest; Core
stays 467; the worker report + raw evidence are filed. Then report to the orchestrator:

```sh
hc send t7x "M12-A candidate ready: <commit-or-working-tree-state> — <Core/AppSupport counts>; <changed files>; <evidence root>; <any blocker>"
```

Do NOT stage, commit, branch, reset, merge, or push — the orchestrator owns Git delivery. Do NOT
start subagents or other CLIs. Do NOT grade your own work as accepted. Reviewers are read-only and
are summoned by the orchestrator after the candidate is frozen.