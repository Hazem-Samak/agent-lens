# M12-A implementation — WORKER EVIDENCE (not acceptance)

**This document is worker evidence, not acceptance.** The orchestrator reruns every gate
independently (D-014); nothing here is claimed as an accepted milestone artifact. Phase M12-A
(presentation-state foundation) of milestone M12, implemented against the frozen dispatch brief
`briefs/M12-A-presentation-foundation.md` and judgment rulings R1/R2/R3/R4/R8/R12/R16.

- Base: `1f251d4` (frozen plan commit). Product base `0589fac`. Dispatch-brief commit `14e5f30`.
- Candidate state: **uncommitted working tree** on `milestone/m12-workflow` at HEAD `14e5f30`.
  No stage/commit/branch/reset/merge/push was performed (orchestrator owns Git delivery).
- Evidence root: `$HOME/.hermes/cache/scratch/agent-lens-m12-a` (outside the repository).
- Product behavior: the SwiftUI app is untouched (`Sources/AgentLensApp/**` has no diff), so the app
  is visually unchanged. The behavioral change is in AppSupport: a pending preview is released by
  `listScope`, `updateStatusFilter`, `searchText`, and selection-ID changes, with zero mutation.

## 1. What was built

| File | Change | Contract |
|---|---|---|
| `Sources/AgentLensAppSupport/WorkflowPresentation.swift` | new | `ListScope`, `DetailPane`, `UpdateStatusFilter`, `ToolConflictKind`, `ToolConflict`, `ManagementPresentation` — all pure; imports `AgentLensCore` only |
| `Sources/AgentLensAppSupport/InventoryViewModel.swift` | modified | R1 fields (`listScope`/`detailPane`/`updateStatusFilter`), invalidation hooks, scope→filter→search `filteredEntries`, `showPathEvidence(registryID:)` |
| `Sources/AgentLensAppSupport/InventorySnapshot.swift` | modified | additive derived counts only: `offPathToolCount`, `conflictToolCount` |
| `Tests/AgentLensAppSupportTests/WorkflowPresentationTests.swift` | new | 23 pure tests: conflict classification, scope/status membership, `ManagementPresentation`, snapshot counts |
| `Tests/AgentLensAppSupportTests/InventoryViewModelTests.swift` | modified (new tests only) | 15 tests: the R1 invalidation matrix, seeded-trigger non-vacuity, both launched-operation exemptions, Updates/category scope, unchanged search fields, defaults |
| `walkthroughs/M12-A-implementation.md` | new | this worker report |

No Core/CLI/registry/Package.swift/scripts/`.github` fixture/wiring change. No new dependency. No
SwiftUI/AppKit import in AppSupport. `InventoryService.swift`, `PathActionTarget.swift`, and
`SessionEnvironmentProvider.swift` are untouched.

### Contract notes (decisions the brief/R1–R16 fix — no improvisation)

- `filteredEntries`: `entries` → `listScope.includes` → (only `.updates`) `updateStatusFilter.includes`
  → existing `matches(searchText)`. Registry order is preserved (filter only, never sort). The
  `matches` haystack and category/package exclusion are unchanged (R8).
- `updateStatusFilter` changes invalidate even while `listScope != .updates`: R1 states a filter
  change is a trigger, and the implementation does not condition the hook on current membership.
- `detailPane` has no invalidation hook; `showPathEvidence` refuses unknown IDs before selecting or
  switching the pane, so a refused ID changes neither selection nor pane.
- `updateStatusFilter.notChecked` is `entry.update == nil`; `.unknown` is a non-nil neutral result.
  Unknown never enters `updateAvailableCount` (existing snapshot rule).
- `ToolConflict`: kinds in fixed order `shadowedCopy`, `offPathCopy`, `inconsistentDiagnostics`;
  `copyCount = canonicalTargetCount`; `localVersions` = `.measured` outcomes only; winner path only
  for `.winner`; off-PATH root only for `.offPath`; stored reason only for `.inconsistent`;
  aliases/repeated slots/not-installed are not kinds; the count counts tools.
- `ManagementPresentation`: update/uninstall predicates reproduce `ToolDetailView`; every
  `operationNotAccepted` string is read from `NpmUpdateUnavailableReason` /
  `NpmUninstallUnavailableReason` (never retyped); `otherLimits` are the three fixed sentences, only
  for installed entries, each at most once, formula → cask → standalone.
- `conflictToolCount`/`offPathToolCount` are snapshot-derived and additive; exposed for M12-B
  Overview tiles without a future `InventorySnapshot.swift` edit (that file is not in B's allow-list).
- `invalidatePendingUpdate()` and its executing-mutation early-return (formerly :621) are untouched.

## 2. RED → GREEN transcript

The RED state was behavioural, not a compile failure: the complete API existed with neutral bodies
(scope/filter membership accepted everything, conflict classification returned no kinds,
`ManagementPresentation` returned `.hidden`/no limits, the ViewModel fields had no invalidation
hooks, `filteredEntries` ignored the scope, and `showPathEvidence` selected without switching the
pane). All tests then compiled and the new behavioural tests failed.

| Run | Command | Result | Raw log |
|---|---|---|---|
| RED | `swift test --skip-build --no-parallel --filter AgentLensAppSupportTests` (skeleton) | exit 1; **117 tests, 24 new tests failing, 44 issues**; the existing 80 pass; failures are assertion failures | `evidence/red-appsupport.log`, `evidence/red-appsupport.meta` |
| GREEN | same command (implemented candidate, 118 tests) | exit 0; **118 tests passed** (80 existing + 38 new) | `evidence/green-appsupport.log`, `evidence/green-appsupport.meta` |

The RED run predates the added `launchedUninstallSurvives…` pin (117 tests at that point; the pin
passes in both states because the :621 guard already existed).

RED failing tests (all new; the pre-existing `searchText`/`select` triggers already worked, so their
new pins pass in both states): scope membership, status-filter membership, conflict kind/count/
measured-version tests, all `ManagementPresentation` positive cases, `listScopeChange…`,
`updateStatusFilterChange…`, `seededPendingPreviewDiesOnlyOnATrigger`, all three
`showPathEvidence…` tests, `updatesScopeListsInstalledEntriesAndNarrowsByTriState`, and
`categoryScopeIntersectsSearchAndPreservesRegistryOrder`.

The GREEN fix after the first GREEN attempt was a test-fixture bug only (`singleWinnerDiagnostic`
did not forward its `source:` argument, so the two standalone-sentence assertions failed). No
production behavior changed for that fix; the corrected run is the GREEN log above.

## 3. Counts

| Target | Baseline | Candidate | Gate |
|---|---|---|---|
| `AgentLensCoreTests` | 467 | 467 (no Core change) | unchanged |
| `AgentLensAppSupportTests` | 80 | 118 | > 80 |
| Total | 547 | 585 | > 547 |
| Guard fixtures | 21 | 21 | unchanged |
| Packaging checks | 9 | 9 | unchanged |

New test split: 23 in `WorkflowPresentationTests.swift`, 15 in `InventoryViewModelTests.swift`
(80 + 38 = 118). The 15th ViewModel test (`launchedUninstallSurvives…`) was added after the RED run
as the second half of the launched-operation exemption; both slots are pinned so removing either
half of the `isExecutingUpdate || isExecutingUninstall` guard fails a test.

## 4. Acceptance commands and raw evidence

All commands ran from the repository root, with `R="$HOME/.hermes/cache/scratch/agent-lens-m12-a"`,
`$R/tmp` as TMPDIR, and a fresh `$R/full-suite` scratch path. Runner: `$R/run-acceptance.sh`
(raw argv, stdout+stderr, exit code, duration in `$R/evidence/<name>.{log,meta}`).

| Command | Exit | Duration | Raw log |
|---|---|---|---|
| `env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS swift build` | 0 | 3s | `build.log` |
| full suite (fresh scratch, `--no-parallel`, CLT plugin flag) | 0 | 157s | `full-suite.log` |
| `python3 scripts/check-core-ui-imports.py` | 0 | 0s | `guard-core.log` |
| `python3 scripts/check-core-ui-imports.py --source-root Sources/AgentLensAppSupport` | 0 | 0s | `guard-appsupport.log` |
| `python3 Tests/Packaging/test_core_ui_imports.py` | 0 | 2s | `guard-fixtures.log` |
| `python3 scripts/build-dev-app.py --scratch-root "$R/dev-app" --configuration debug` | 0 | 26s | `dev-app.log` |
| `python3 Tests/Packaging/test_dev_app_bundle.py --app "$R/dev-app/AgentLensApp-debug.app"` | 0 | 2s | `packaging.log` |
| `git diff --check` | 0 | — | `diff-check.log` |

Observed results (worker run at the final candidate; orchestrator will rerun):

- `full-suite.log`: `✔ Test run with 467 tests in 0 suites passed` (Core) and
  `✔ Test run with 118 tests in 5 suites passed` (AppSupport); no failure, no skip, no issue line.
- `guard-core.log`: `32 Swift file(s) under Sources/AgentLensCore; no SwiftUI/AppKit imports`.
- `guard-appsupport.log`: `6 Swift file(s) under Sources/AgentLensAppSupport; no SwiftUI/AppKit imports`.
- `guard-fixtures.log`: `Ran 21 tests ... OK`.
- `packaging.log`: `Ran 9 tests ... OK`.
- `dev-app.log`: `Build complete!` and the app path
  `$R/dev-app/AgentLensApp-debug.app`.

## 5. Changed-file hashes and protected manifest

`evidence/changed-files.sha256` (SHA-256 of every changed/added file) and
`evidence/protected-manifest-vs-head.log` / `evidence/protected-manifest-vs-base-1f251d4.log`
(every tracked file hashed at the base/HEAD and at the candidate).

Result: the only differences are the five allow-listed product/test files plus the worker report;
untracked additions are the two allow-listed new files. The only committed delta `1f251d4..HEAD` is
`briefs/M12-A-presentation-foundation.md` (orchestrator dispatch-brief commit `14e5f30`), not an
implementer change.

Candidate SHA-256 (from `evidence/changed-files.sha256`):

```text
1e7a41d64dced2ba98becbd4c2fa328704f2dd3f714ca7de67935fb71591c01c  Sources/AgentLensAppSupport/InventorySnapshot.swift
9b5257dab19b7d87d65018337c7b5b23fb1a01f2f633f4d960b7a566bb572b55  Sources/AgentLensAppSupport/InventoryViewModel.swift
420c20da464fddfdec84e9919feb44f95c23dab300247896b8d38a21657b93f4  Sources/AgentLensAppSupport/WorkflowPresentation.swift
1fc0f2cf23db2051f3d3ef75d99d0b1c44cbe1f06c3e11bbd28e6bc1155bbeca  Tests/AgentLensAppSupportTests/InventoryViewModelTests.swift
287b37ed14129bf0db18626f1916d14f983a0ff361bbd90a063d136e53424124  Tests/AgentLensAppSupportTests/WorkflowPresentationTests.swift
```

This report's own SHA-256 is recorded in the same evidence file after the report's final write.
(R1 supersedes this block's VM-test and report hashes; §8 records the R1 candidate state, the
external review artifacts, and the regenerated evidence.)

## 6. Stop-condition audit

- No Core/registry/CLI change was needed; Core file count and behavior untouched.
- `invalidatePendingUpdate`'s executing early-return was not changed; the launched-operation test
  demonstrates a scope/filter/search/selection change does not cancel an executing update and the
  outcome/preview stay bound to `codex-id`.
- `filteredEntries` does not re-sort; `matches` is byte-identical to the accepted predicate.
- The AppSupport floor is raised to a measured 118 at the reviewed candidate (119 after the R1
  pin; see §8); `ci.yml` was not edited.
- No design choice outside the brief/rulings was made. The unconditional `updateStatusFilter`
  invalidation follows R1's literal trigger list and is recorded above.

## 7. Unverified / unobserved

- No live native-app visual check was performed in this phase; the app is unmodified, and
  `build-dev-app.py` + packaging only prove the bundle builds and passes its checks. Visual
  invariance is expected from zero `Sources/AgentLensApp/**` diff, not observed.
- No real registry, personal installation, real Agent Lens cache, or manager command was touched by
  any test. The new tests use synthetic registries, fixtures under `TMPDIR`, and injected seams.
- Review/acceptance is not claimed. Both independent reviewers and the orchestrator's rerun are
  outside this report.

## 8. R1 focused corrections (post-review)

Both reviewers PASSed the candidate (0 blocking; 3 + 2 low findings). This R1 applies only the
findings that correct test pinning and this report. **No production code changed**; the allow-list
was `Tests/AgentLensAppSupportTests/InventoryViewModelTests.swift` and this report.

1. **LOW-1 — filter inertness outside Updates is now pinned.**
   `updateStatusFilterIsInertOutsideTheUpdatesScope` installs the normal two-tool fixture (both
   installed), sets `listScope = .all`, then `updateStatusFilter = .updateAvailable`, and asserts
   both registry IDs remain listed (`["codex-id", "beta-id"]`, including neutral `beta-id`). This
   discriminates the `guard listScope == .updates` in `filteredEntries`: dropping that
   scope-conditioning guard would leave only `codex-id` and fail the pin.
2. **Seeded-trigger comment direction corrected.** The previous comment claimed a removed hook would
   make the final assertion *pass*; the assertions do the opposite. The comment now states that
   removing the `listScope` hook leaves the preparation non-nil and makes
   `#expect(viewModel.updatePreparation == nil)` **fail**. No assertion was weakened or changed.
3. **Floor transcription corrected.** The stop-condition audit said 117; the reviewed candidate was
   118. Corrected above, with the post-R1 count recorded here.

**LOW-2 (not changed by instruction).** The conflict classifier does not special-case
`installState`; Core publishes `shadowedInstallationCount == 0` for `notInstalled`, so R3's
`shadowedCopy` rule already produces no conflict for a not-installed tool. This raises no Core
coupling beyond R3 as written.

Post-R1 counts and evidence (fresh scratch, `--no-parallel`, CLT plugin flag):

| Run | Result |
|---|---|
| AppSupport suite (`--filter AgentLensAppSupportTests`) | exit 0 — **119 tests passed** (80 baseline + 39 new) |
| Full gate set | every command exit 0 — Core **467**, AppSupport **119** (total **586**), zero failures/skips; guard fixtures **21**; packaging **9**; both import guards clean; dev-app built; `git diff --check` clean |

Raw R1 logs, argv, exit codes, and durations: `$R/evidence/r1/`. The changed-file SHA-256 list and
protected manifests were regenerated at the R1 candidate (`evidence/r1/` and `evidence/`).

R1 candidate state: the reviewed candidate was committed by the orchestrator as `64a5056`
(`feat(workflow): M12-A presentation-state foundation candidate`); these two R1 edits are
uncommitted on top of it. `walkthroughs/M12-A-evidence/reviews/{grok,minimax}.md` were filed by the
orchestrator/reviewers after that commit; they are **not** implementer changes and were not edited.
The R1 hashes therefore list the two R1 edits separately from the six allow-listed candidate files
(`evidence/r1/candidate-files.sha256`).
