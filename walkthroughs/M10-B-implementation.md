# M10-B — npm `latest` metadata: worker implementation evidence

> **Worker handoff artifact. This is NOT acceptance.** D-014: coordinator runs independent
> acceptance; a worker success claim is not a coordinator verdict. The selected worker was
> Qoder CLI (`E/worker/qoder-flash`); per the frozen brief no provider-enforced max-effort is
> claimed. Hosted exact-SHA gates remain **PENDING** (no commit/push was authorized). See §Limits.

## 1. Identity

| Field | Value |
|---|---|
| Branch | `codex/m10-npm-management` |
| Product baseline | `b667be6a177d42f26def815e9acd6f801aa6d52c` |
| Candidate state | **uncommitted working tree** — no `git add/commit/push/stash/reset/clean/branch/PR` performed by the worker |
| Frozen brief | `briefs/M10-B-npm-latest.md` SHA256 `1270cb3dc660195c71e67977f6bbab883e9b0dcbb730e34c484f4c424ec0c35c` (verified unchanged) |
| Evidence root `E` | `/private/tmp/agent-lens-m10b-implementation-9jaujmja` |
| This batch (`r1-batch3`) | `E/worker/qoder-flash/r1-batch3` — `logs/`, `products/`, `products-final/`, `devapp/`, `native/`, `transport/`, `cache-repro/`, `cli/` |
| Command receipts | `E/worker/qoder-flash/r1-batch3/logs/<name>.argv` (NUL-separated argv), `.argv.txt`, `.stdout`, `.stderr`, `.exit`, `.elapsed` |
| Read-only inputs | `E/fixture` (prepared fixture), `E/parent` (coordinator evidence) — the worker wrote to neither |

## 2. Worker scope vs. coordinator-owned scope

Product code/tests the **worker** created or modified (allow-list, brief §File authority):

- **Added** `Sources/AgentLensCore/Updates/NpmUpdateProbe.swift` — scoped registry resolution, strict
  `view` JSON parser, typed metadata, scratch env, ownership-group orchestration.
- **Added** `Sources/AgentLensCore/Updates/NpmUpdateMetadataCache.swift` — separate bounded
  `npm-update-metadata-v1.json` doc, schema1, 1 MiB cap, merge/prune/preserve, stable key digest.
- **Modified** `Sources/AgentLensCore/Updates/UpdateProbeCoordinator.swift` — carries `DetectorDefinition`
  on each subject, npm routing/admission gate/60 s stage budget/deadline-clipped runner, Homebrew-first
  then npm in registry order, `npmScratchBaseURL: URL? = nil` injection.
- **Modified** `Sources/AgentLensCore/Updates/VersionStatus.swift` — **purely additive** `UnknownReason`
  cases (`unsupportedRegistry`, `unsupportedChannel`, `budgetExhausted`, `metadataInvalid`,
  `queryTimedOut`); `evaluate` untouched.
- **Modified** `Sources/AgentLensCore/Updates/UpdateScanRenderer.swift` — npm-aware / manager-neutral
  unknown wording.
- **Modified** `Sources/AgentLensCore/Ownership/NpmOwnershipProbe.swift` — additive `NpmOwnershipProof`
  + `verifyWithProof(...)` + `resolveNpmManager(...)`; public `verify` delegates and discards proof.
- **Modified** `Sources/AgentLensAppSupport/InventoryService.swift` — thread `npmScratchBaseURL`.
- **Modified** `Sources/AgentLensApp/ToolDetailView.swift` — npm identity/registry/tag/version + reason text.
- **Modified** `Sources/agent-lens/main.swift` — subject construction migrated.
- **Added** `Tests/AgentLensCoreTests/NpmUpdateProbeTests.swift` (29 `@Test` on this candidate),
  `Tests/AgentLensCoreTests/NpmUpdateMetadataCacheTests.swift` (22 `@Test`).
- **Modified** `Tests/AgentLensCoreTests/UpdateProbeCoordinatorTests.swift` — `UpdateProbeSubject`
  constructor migration; one npm reason → `.identityUnverified`.

**R1 batch3 corrections applied on top of the same files:**

- **R06 residual** (`NpmUpdateMetadataCache.swift`) — contamination is now classified per **complete
  identity before any per-record pruning**: if any stored record of an identity fails the strict rules, every
  record of that identity is dropped, so an unrelated tool's save can no longer prune the poison and promote
  the valid-looking sibling into a hit this process never verified. Fully valid duplicate identities of
  another tool still survive an unrelated save and still resolve as ambiguity misses. Regression:
  `unrelatedSaveNeverPromotesTheValidSiblingOfAContaminatedIdentity`.
- **R07** (`NpmUpdateProbe.swift`) — the injected scratch **base** is validated before any launch (`lstat` of
  the base component itself: missing / symlink / non-directory / foreign-owned / group-or-other-writable all
  refuse with **zero** npm commands, while symlinked **ancestors** stay tolerated so the sanctioned default
  `TMPDIR` `/var/…` physical alias keeps working). Each claimed **child** is a unique mode-0700 direct physical
  child of the base, never adopted on collision, and recorded by device + inode + resolved physical name.
  Cleanup is anchored to that record and refuses a child replaced by a different directory or reachable
  through a retargeted ancestor. Any cleanup failure is propagated through a per-run ledger to the final gate:
  the tool reports neutral `probeFailed` and nothing is published or cached. Seven new `@Test` cases cover it
  (§7 inventory). `Sources/AgentLensCore/Process/**` was not touched.
- **R08** (`README.md`) — usage and "Update status limitations" migrated off the Homebrew-only wording.

**Worker did NOT touch** (coordinator/orchestrator-owned records): `ROADMAP.md`, `briefs/README.md`,
`briefs/M10-B-*.md` (planning briefs), `walkthroughs/M10-B-planning.md` +
`walkthroughs/M10-B-planning-evidence/`, and every milestone-status/acceptance sentence in `README.md`
(the M10-A record, the frozen-planning pointer, the CI/local-fallback sections and all links are retained
verbatim). Brief line 7 marks the README *status* corrections orchestrator-owned; the R08 dispatch
explicitly authorized only the usage-migration edits, and the worker made no other change to that file.

## 3. Protected scope (DO NOT TOUCH) — confirmed absent from the change set

`git diff --name-only` + untracked list contain **none** of: `Sources/AgentLensCore/Process/**`,
`Sources/AgentLensCore/Updates/ProcessUpdateCommandRunner.swift`, `Package.swift`/dependencies, bundled
registry/schema/resources, Homebrew probe/cache/comparison (`HomebrewUpdateProbe.swift`,
`UpdateMetadataCache.swift`, `VersionComparison.swift`), `.github/**`/CI, `scripts/**`,
`Tests/Packaging/**`, scope/decisions, personal install/cache/npmrc/shell/toolchain. No new dependency
or manager mutation. Allow-list satisfied.

## 4. Candidate SHA256

Measured on the delivered working tree after the last edit (`r1-batch3`, gates in §5 run against exactly this tree):

```
b2015789de23ae735b59ebaf6716e7eee9eb53b840e65a859ad0d683226f432c  Sources/AgentLensCore/Updates/NpmUpdateProbe.swift
2ff37cc2183aa9a217f65f85fa5cc66be416691305aac4e3a0b26232cabaa644  Sources/AgentLensCore/Updates/NpmUpdateMetadataCache.swift
abaecf524e21ee832add60c7c01b9602815944581f725b2d19e72607e6f9b8cd  Sources/AgentLensCore/Updates/UpdateProbeCoordinator.swift
0c14cf5a0dca2cfaa0a81090f04d71752bbbb6824cadfc5046bb58aa8e971779  Sources/AgentLensCore/Updates/UpdateScanRenderer.swift
87d1951c94439b754732d14d8092638ec68ca940c26a83aabe22ee882b041731  Sources/AgentLensCore/Updates/VersionStatus.swift
3a87c40680d438d3633c78eafa56471e9dc61337f89fd15b0e9627f139754d19  Sources/AgentLensCore/Ownership/NpmOwnershipProbe.swift
8888c871f7f6a38c1d72f84321b7cbd4aad2ca2ab1cd3ccda0b20715850cb9a7  Sources/AgentLensAppSupport/InventoryService.swift
f742b8cff97dbea9c0aa621579f362a13ab55c31e3f34d43aae91d46e1b945c5  Sources/AgentLensApp/ToolDetailView.swift
1e5b8a47ba8ed3841dcb961de20c87c65a6f3babc33438c2acc3e2b90a78f5d9  Sources/agent-lens/main.swift
675736f04da65add420d28473995086ab71b80c75cb659b203bc68bb635eab34  Tests/AgentLensCoreTests/NpmUpdateProbeTests.swift
c8b2c70287038eb3a25a22e113e9dd0db9dab4994aa07a7ee54aeef3df11cd04  Tests/AgentLensCoreTests/NpmUpdateMetadataCacheTests.swift
f407b4f387df8ed8c8243316563f1fa9aecc07ca8aa880d188f075c75547982f  Tests/AgentLensCoreTests/UpdateProbeCoordinatorTests.swift
0af58d5135b10b38a1ac6ba9ac5f6ac8c744672a591935b9cbd2fddcd3a27abb  README.md
```

`UpdateScanRenderer.swift`, `VersionStatus.swift`, `InventoryService.swift`, `ToolDetailView.swift` and
`main.swift` are byte-identical to the previous batch's hashes. The seven that changed are
`NpmUpdateProbe.swift` (R07), `NpmUpdateMetadataCache.swift` (R06 residual), `UpdateProbeCoordinator.swift`,
`NpmOwnershipProbe.swift` (coordinator-adjudicated identity repair retained), `NpmUpdateProbeTests.swift`,
`NpmUpdateMetadataCacheTests.swift`, `UpdateProbeCoordinatorTests.swift`, plus
`README.md` (R08).

Worker-owned external harness artifacts (NOT product code, NOT part of the candidate):

```
3fe5823d622ff72546f80e49639a3f0d2d3c8c3d4c55adb55ecd2ea7e40ba704  E/worker/qoder-flash/r1-batch3/transport/TransportHarness.swift
cd3f7b1c5d6ff7f445f258ecc6bf88ed0aae5e65448d0a598103653e111a523e  E/worker/qoder-flash/r1-batch3/transport/registry-server.py
b2f2086e88a4cc796f3f08c7d38466e1d63206883fb1cefa2393ca2120f0cd5a  E/worker/qoder-flash/r1-batch3/transport/run-transport.sh
dbbedf000bdf455a3725e216e4d49894bb05d8019a4c3b3d9943b5121ddb141a  E/worker/qoder-flash/r1-batch3/native/FixtureHost.swift
9ec2b73598e5f725bb3c9e6996324bd2c0fd85d40559b4c2917d32ae54d66d46  E/worker/qoder-flash/r1-batch3/cache-repro/CacheProbeR3.swift
```

## 5. Worker-run gates — raw receipts (single frozen candidate)

Hosted command form is unchanged (`swift test --no-parallel`). Swift 6.4 does not auto-discover the
local `TestingMacros` macro plugin, so the **test-only** local fallback adds the plugin load path
(documented for M10-A; brief line 131 permits it; it does not alter the hosted command):

`swift test --no-parallel -Xswiftc -load-plugin-library -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib`

| Gate | argv (tail) | exit | result | elapsed |
|---|---|---|---|---|
| fresh build | `env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS swift build --scratch-path "$R/products-final"` | 0 | `Build complete! (29.86 secs)` — real compile of every target, **no `--skip-build` substitute, no reuse of the older `products/` root** | 30.98 s |
| full test suite | `env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS swift test --no-parallel --scratch-path "$R/products-final" --build-system swiftbuild -Xswiftc -load-plugin-library -Xswiftc …/libTestingMacros.dylib` | 0 | `Test run with 395 tests in 0 suites passed after 66.072 seconds` + `Test run with 71 tests in 5 suites passed after 4.418 seconds` = **466**, zero failures, zero skips | 100.41 s |
| core-ui guard | `python3 scripts/check-core-ui-imports.py` | 0 | `28 Swift file(s) under Sources/AgentLensCore; no SwiftUI/AppKit imports` | 0.10 s |
| core-ui packaging | `python3 Tests/Packaging/test_core_ui_imports.py` | 0 | `Ran 21 tests in 1.143s` `OK` (≥ 21 floor) | 1.23 s |
| debug app build | `python3 scripts/build-dev-app.py --scratch-root "$R/devapp" --configuration debug` | 0 | printed `…/r1-batch3/devapp/AgentLensApp-debug.app`; `Build complete! (28.20 secs)` | 30.56 s |
| dev bundle packaging | `python3 Tests/Packaging/test_dev_app_bundle.py --app "$R/devapp/AgentLensApp-debug.app"` | 0 | `Ran 9 tests in 1.642s` `OK` — all nine original checks | 1.74 s |
| whitespace check | `git diff --check` | 0 | clean (no output) | <1 s |
| targeted npm rerun | `swift test --no-parallel … --filter NpmUpdate` | 0 | `Test run with 51 tests … passed` (29 probe + 22 cache) | 11.28 s |
| targeted joint rerun | `swift test --no-parallel … --filter` coordinator/npm-ownership/CLI-registry/Homebrew/cache/`InstallationOwnership` | 0 | `Test run with 191 tests … passed` | 63.11 s |

Suite conditions, exactly as dispatched: `TMPDIR` inherited (`/var/folders/…/T/`, the sanctioned physical
alias) and **both** `AGENT_LENS_TEST_SCRATCH` and `AGENT_LENS_TEST_PRODUCTS` unset; the `env -u …` prefix
proves the unset rather than relying on shell state.

Baseline floor 406 = 335 Core + 71 AppSupport; the previously recorded post-change baseline was 458
(387 Core + 71 AppSupport). This candidate is **395 Core** (+8 R06/R07 regressions) + **71 AppSupport** =
**466** ≥ 458 ≥ 406; no pre-existing case was removed, renamed away or skipped. `ld: warning: search path
…/Developer/… not found` lines are pre-existing CommandLineTools toolchain noise, not compile errors
(build EXIT=0).

## 6. Actual-CLI receipts (isolated: real binary, prepared Seatbelt profile, fixture PATH)

Each run used the binary from this batch's fresh build
(`$R/products-final/debug/agent-lens`) under the prepared profile
`sandbox-exec -f E/fixture/cli-isolation.sb`, which denies `~/Library/Caches/AgentLens`, `~/.npm`,
`~/.opencode`, `~/.grok` and `~/.local/bin`, with `PATH` pinned to the fixture
(`E/fixture/npm-prefix/bin:E/fixture/manager-bin:/usr/bin:/bin`) and both `AGENT_LENS_TEST_*` overrides
unset. Only **no-network, no-persistent-write** modes were run; `--check-updates` / `--refresh-updates`
against the live machine would hit the **public** registry and stay coordinator-owned (AC09 was instead
exercised through the controlled-transport harness in §9).

| receipt | argv tail | exit | elapsed | observed |
|---|---|---|---|---|
| `cli-scan-local-01` | `… agent-lens scan` | 0 | 0.15 s | `Codex installed 1.0.0 latest known — unknown — update check not requested`; `OpenCode … / Grok CLI … unknown — no registry`; `0 updates available`; empty stderr |
| `cli-scan-offline-01` | `… agent-lens scan --offline` | 0 | 0.12 s | same inventory, `unknown — offline mode was requested`; empty stderr |
| `cli-mutual-exclusion-01` | `… agent-lens scan --check-updates --refresh-updates` | 1 | 0.02 s | usage line on **stderr**, nothing on stdout — rejected at parse before any environment capture or manager launch |
| `cli-unknown-flag-01` | `… agent-lens scan --registry https://example.invalid` | 1 | 0.02 s | same usage rejection — **the product has no registry-override switch**, so a redirected registry cannot even be requested |

`~/Library/Caches/AgentLens` was still **absent** after all four runs (`ls: … No such file or directory`),
so plain/offline read and wrote neither metadata document, and the profile denied it regardless.

## 7. Requirements → evidence matrix (AC01–AC11)

Legend: **W** = worker-evidenced on this candidate (unit/CLI); **C** = coordinator-pending acceptance.

| AC | Worker evidence (W) | Coordinator-pending (C) |
|---|---|---|
| **AC01 modes** | CLI local/offline exit 0, no persistent doc, no npm scratch, no `view`; §6. `missingSelectionLaunchesNoCommands`, `managerAbsentFromPathLaunchesNoCommands`; coordinator returns before admission/cache/query in plain/offline | native-app launch/rescan parity |
| **AC02 proof** | Real on-disk npm fixture; `NpmOwnershipProof` full initial+final re-verify gates publication; `exhaustedStageStopsAfterInitialOwnershipAndPreservesIdentity` | two-prefix/alias/shadowed/forged-hint adversarial matrix (M9 `InstallationOwnershipTests`, unmodified) |
| **AC03 registry** | `customBaseRegistryRefusesWithZeroViewCalls`, `customScopeRegistryRefusesWithZeroViewCalls`, `scopedCheckBindsBothRegistryFlagsAndReportsUpToDate`; base+scoped pin after eligibility; final registry re-read | populated-config/project-ignored-in-global real-npm precedence |
| **AC04 metadata** | `malformedViewOutputIsMetadataInvalidWithOneViewCall` — strict single-object three-flat-key parse on the measured npm10.9.8 shape (fixture); the same parser accepted **real** `npm view` output in the controlled-transport run (`@openai/codex` → `2.0.0`, §9) | coordinator's authoritative transport parse, plus the adversarial-output matrix |
| **AC05 versions** | `prereleaseLatestIsUnsupportedChannelAndNeverPersisted`, `installedNewerThanKnownMetadataIsUnknownAndNotPersisted` (stable-vs-prerelease ordering, no downgrade) | `+build` comparator-only (pre-existing `VersionComparisonTests`); real large-numeric end-to-end |
| **AC06 cache** | 22 cache cases (TTL just-before/exact-6 h/future, corrupt/oversize/duplicate, merge/prune/preserve, sibling-of-Homebrew, poisoned-record/refuses-incoming, stored-field drift) + `checkCacheHitSkipsViewAndPreservesOriginalObservation`; context digest excludes volatile scratch keys so distinct scratch roots reuse the record. **R06 residual:** `unrelatedSaveNeverPromotesTheValidSiblingOfAContaminatedIdentity`, re-verified as a compiled program against this candidate (§9 `CacheProbeR3`: `before hit=false`, `after-unrelated-save hit=false`, `survivingARecords=0`, `noPoisonInDocument=true`, repair→`3.0.0`, re-contamination→miss, `verdict=PASS`, exit 0) | "two consecutive Check, distinct roots, one record" at CLI level = AC08 |
| **AC07 lifecycle** | budget-exhausted stops after initial ownership with identity preserved (unit); **R07:** `unsafeScratchBasesRefuseWithZeroNpmLaunches`, `symlinkedAncestorScratchBaseStillRunsAndLeavesNoOwnedChild`, `claimedScratchChildIsOwnedMode0700DirectPhysicalChildOfBase`, `anchoredCleanupRemovesOnlyTheRecordedOwnedChild`, `anchoredCleanupRefusesAChildReplacedByADifferentDirectory`, `anchoredCleanupRefusesARetargetedAncestorAndLeavesTheRecordedChild`, `scratchCleanupFailureIsPropagatedAndNeverPublishedAsVerified` | Homebrew-first ordering + npm exhaustion retaining completed Homebrew results (coordinator `UpdateProbeCoordinatorTests` + injected-monotonic), app concurrency/window-close, per-group 0700 removal at process level |
| **AC08 CLI/native parity** | **actual isolated CLI** (§6); native SwiftUI host source compiled clean against this candidate (`native/M10BFixtureHost`, exit 0, 3.09 s) | controlled native host **interaction**: window launch, Check/Refresh twice, screenshots + interaction receipts (C) |
| **AC09 real npm** | **worker ran real `npm` 10.9.8** from the prepared fixture through the shipping path (`InventoryService` → coordinator → `NpmUpdateProbe` → `ProcessUpdateCommandRunner`) over a loopback registry: production argv asserted with **both** public pins, then only those two flags substituted; Check→fresh, Check→cache with the original observation time, Refresh→fresh; two HTTP requests total; scratch base empty after every run (§9) | coordinator's own controlled-transport run as the authoritative verdict, plus the public-registry CLI `--check-updates` observation |
| **AC10 regression** | 466 Swift pass (395 Core + 71 AppSupport) ≥ 458 prior baseline ≥ 406 floor, guard 21, packaging 9, fresh build + dev-app green, zero failures/skips; Homebrew statuses/cache/provenance/counts preserved (unmodified impl, unmodified Homebrew fixtures) | exact-SHA hosted all-7 = AC11 |
| **AC11 scope/hosted** | allow-list met; protected hashes absent from change set; no new dependency/manager mutation (§3, §4) | exact-SHA hosted all-7 gates **PENDING** — no commit/push authorized |

### New test inventory (exact names)

`NpmUpdateProbeTests` (29):
`unscopedUpdateAvailablePublishesNpmIdentityAndFreshProvenance`,
`scopedCheckBindsBothRegistryFlagsAndReportsUpToDate`,
`scopedUnsetConfigStillPinsBothRegistryFlags`,
`customBaseRegistryRefusesWithZeroViewCalls`,
`customScopeRegistryRefusesWithZeroViewCalls`,
`blankScopeOutputRefusesAsMalformedWithZeroViewCalls`,
`prereleaseLatestIsUnsupportedChannelAndNeverPersisted`,
`installedNewerThanKnownMetadataIsUnknownAndNotPersisted`,
`malformedViewOutputIsMetadataInvalidWithOneViewCall`,
`checkCacheHitSkipsViewAndPreservesOriginalObservation`,
`tamperedCacheRecordRefusesTheHitAndRefetchesBoundedOnce`,
`samePathBinReplacementInvalidatesCacheHitWithFreshView`,
`samePathManifestReplacementNeverReusesCachedProofMetadata`,
`replacedManagerCannotReusePriorProofIdentity`,
`replacedRootDirectoryRefusesNeverReusingPriorProof`,
`selectionReplacementDuringFinalScopeReadRefusesAndPersistsNothing`,
`laterDeclarationMatchUsesVerifiedPackageNameForEveryLookup`,
`unmatchedDeclarationAuthorizesZeroLookupsAndPersistsNothing`,
`exhaustedStageStopsAfterInitialOwnershipAndPreservesIdentity`,
`deadlineExhaustedAfterFinalQueryMapsToBudgetExhaustedOnCacheHit`,
`missingSelectionLaunchesNoCommands`,
`managerAbsentFromPathLaunchesNoCommands`,
**R07 (7 new)** `unsafeScratchBasesRefuseWithZeroNpmLaunches`,
`symlinkedAncestorScratchBaseStillRunsAndLeavesNoOwnedChild`,
`claimedScratchChildIsOwnedMode0700DirectPhysicalChildOfBase`,
`anchoredCleanupRemovesOnlyTheRecordedOwnedChild`,
`anchoredCleanupRefusesAChildReplacedByADifferentDirectory`,
`anchoredCleanupRefusesARetargetedAncestorAndLeavesTheRecordedChild`,
`scratchCleanupFailureIsPropagatedAndNeverPublishedAsVerified`.

`NpmUpdateMetadataCacheTests` (22): `freshEntryIsFoundWithinTTL`, `entryExactlyAtSixHoursIsAMiss`,
`futureObservationIsAMissAndStaysOutOfStoreAfterSave`, `corruptDocumentIsAMissNotAThrow`,
`oversizeDocumentIsAMiss`, `duplicateCompleteIdentityRecordsAreAMiss`,
`savePreservesOtherToolAndReplacesOnlyMatchingIdentity`, `savePrunesExpiredRecords`,
`saveRejectsIncoherentEntryAndLeavesStoreUnchanged`, `npmDocumentIsASeparateSiblingOfTheHomebrewCache`,
`poisonedRecordForAnIdentityIsNotReplacedBySilentlyChoosingAnother`,
`saveRefusesPoisonedIncomingRecordWithoutDisturbingStoredRecords`,
`simultaneousSavesOfDistinctIdentitiesAllSurvive`,
`unrelatedSaveNeverCollapsesAnAmbiguousIdentityAndNeverTouchesHomebrew`,
`storedNameDifferingFromPackageIsAMissAndCannotBeSaved`,
`storedPackageOutsideCatalogueGrammarIsAMissAndCannotBeSaved`,
`storedPrereleaseVersionIsAMissAndCannotBeSaved`,
`storedTwoComponentVersionIsAMissAndCannotBeSaved`,
`storedUnsupportedRegistryIsAMissAndCannotBeSaved`,
`storedUnsupportedTagIsAMissAndCannotBeSaved`,
`storedVersionDivergingFromLatestTagIsAMissAndCannotBeSaved`,
**R06 residual (1 new)** `unrelatedSaveNeverPromotesTheValidSiblingOfAContaminatedIdentity`.

## 8. Isolation & cleanup proof (secret-free)

- Personal `~/.npm` mtime `Oct 27 00:52:21 2026` — unchanged across the whole `r1-batch3` session, including
  the real-`npm` transport runs (which pointed `--cache`/`--logs-dir` at worker-owned children).
- `~/Library/Caches/AgentLens` **absent** after every gate and after the transport runs — the worker created
  no persistent npm/Homebrew document on the personal machine; the CLI receipts run under the profile that
  denies it anyway.
- Owned scratch cleanup under real `npm`: the harness base `$R/transport/npm-scratch` was empty
  (`scratchBase-before: []`, `scratchBase-after: []`) in all three runs and `scratchAfter=0` in the driver
  summary, while the receipts show a **distinct** child per invocation
  (`AE7350DB…`, `ECDF6245…`, `D7E9CC63…`, `10AC5B44…`, `72707DE3…`, `6D42E881…`, `A7C6F332…`, `85F317E7…`,
  `70FD0D1A…`, `81F405F3…`, `3199D5F0…`) — every claimed child removed, none adopted, none leaked.
- The coordinator-prepared `E/fixture/npm-scratch` is likewise empty and was never the harness base; no file
  was written anywhere under `E/fixture` or `E/parent` (all harness documents live under `$R`).
- R07 invariants are asserted in-suite, not just observed: unique mode-0700 direct physical child recorded by
  device+inode, cleanup anchored to that record, replacement/retarget refused, and a forced cleanup failure
  turning the result into neutral `probeFailed` with zero cache writes.
- No stray `npm-scratch*` under Foundation's temp directory outside the owned roots.
- Fixture packages/scratch never derive from real HOME; injected clock/URL only in unit tests.

## 9. Evidence-type distinctions

- **Actual CLI** (§6): the freshly built `agent-lens` binary under the prepared Seatbelt profile against the
  fixture PATH. Genuine product process, genuine argv/stdout/stderr/exit, local/offline/parse-rejection only.
- **Core-driver unit** (§7 W rows): `NpmUpdateProbe.run` / `NpmUpdateMetadataCache` exercised directly with a
  scripted `UpdateCommandRunner` returning the **measured** npm 10.9.8 three-key JSON shape over a real
  on-disk fixture tree. Proves parsing, eligibility, proof, cache, provenance and budget logic — not real `npm`.
- **Core-driver + REAL npm over controlled transport** (`$R/transport`, headless): the shipping path
  `InventoryService.localSnapshot()` → `applyingUpdates(to:mode:)` → `UpdateProbeCoordinator` →
  `NpmUpdateProbe` → production `ProcessUpdateCommandRunner`, launching the fixture's **real** `npm`
  (10.9.8) against a loopback registry started by this worker's own copy of the server. The runner is an
  external harness wrapper: it detects `view` by **parsed subcommand** (production emits the scratch flags
  `--cache <root> --logs-dir <root> --no-update-notifier` *before* `view`, so `first == "view"` never fires),
  asserts production pinned **both** `--registry=https://registry.npmjs.org/` and
  `--@openai:registry=https://registry.npmjs.org/`, and only then rewrites those two values. A `view` without
  both pins is refused, not launched. **No product debug or custom-registry switch exists** — the CLI rejects
  `--registry` outright (§6). Measured: 29 launches, 2 `view` launches, 2 substitutions, **2** HTTP requests
  total, Check 1 → `freshProbe(observedAt: 2026-10-27 16:40:31 +0000)` with
  `status=updateAvailable(installed: 1.0.0, latest: 2.0.0)`, Check 2 → `cache(observedAt: 2026-10-27
  16:40:31 +0000)` with **no** `view` launch, Refresh → `freshProbe(16:40:34)`. npm document
  `schemaVersion=1`, one record `@openai/codex 2.0.0 tag=latest registry=https://registry.npmjs.org/`
  (the reported registry stays the public origin, not the substituted loopback); Homebrew document absent;
  scratch base empty before and after each run. This is **worker evidence**, not the coordinator's AC09 verdict.
- **Compiled R06 probe** (`$R/cache-repro/CacheProbeR3`): a standalone program linked against this candidate's
  `AgentLensCore` objects replaying the coordinator's contamination sequence; §7 AC06 quotes its raw stdout.
  Confirms the residual defect is closed outside the test target as well.
- **Native host binary (compiled, NOT interacted)**: `$R/native/M10BFixtureHost` builds cleanly (exit 0,
  3.09 s) from the batch3 copy of `FixtureHost.swift` with the same parsed-subcommand/both-pins rule. Opening
  the SwiftUI window, clicking Check/Refresh and capturing screenshots is a GUI interaction and stays
  coordinator-owned (AC08) — the worker did not launch it.

## 10. Limits & honest non-claims

1. **Hosted PENDING**: every gate in §5 is local. No commit/push was authorized, so exact-SHA hosted all-7
   (AC11) has **not** run, and nothing here is a hosted-CI claim.
2. **Real npm was run — but only against a loopback registry.** The transport harness served the fixture
   package `@openai/codex` from `E/fixture`-derived data; the public registry was never contacted, no other
   package was measured, and the coordinator's server remains the authoritative AC09 setup. The public-registry
   CLI `--check-updates` observation is deliberately not run by the worker.
3. **No native-host interaction.** The batch3 host binary compiles; the window was never opened, so AC08
   screenshots/parity remain coordinator acceptance.
4. **Registry redirection is harness-side, not product-side.** Substitution to `127.0.0.1` happens in the
   external wrapper after it verifies both public pins; the product has no custom-registry flag, env var or
   debug switch (the CLI rejects `--registry`, §6).
5. **AC07 integration**: cross-manager Homebrew-first ordering, npm-exhaustion result retention and app
   concurrency/window-close remain coordinator acceptance; the worker proves the probe-level and R07
   base/child/ledger semantics by unit regression plus the observed empty scratch base. Removal failure is
   verified to neutralize the result, not to be impossible.
6. **Not a filesystem freeze.** R07 anchors cleanup to the recorded device+inode+physical name and refuses to
   delete anything else; a concurrent attacker who swaps the tree between the check and the removal is bounded
   by that refusal, not by an atomic rename guarantee.
7. **Path-spelling trap found while implementing R07**: Foundation's `standardizedFileURL` rewrites the
   physical `/private/var/…` `TMPDIR` spelling back to the `/var/…` alias, so anchoring a claimed child on
   Foundation normalization fails closed on this workstation (an intermediate version of the claim check made
   50/51 probe cases report `probeFailed`). The fix anchors on `realpath(3)` output plus the child's own last
   path component, and `symlinkedAncestorScratchBaseStillRunsAndLeavesNoOwnedChild` pins that behaviour.
8. **Benign warnings (non-fatal)**: CommandLineTools `ld: search path …/Developer/… not found` noise,
   `String(validatingUTF8:)` deprecation in the environment resolver (pre-existing), and a discarded
   `seekToEnd` result in the harness receipt writer.
9. **Local fallback**: the `-Xswiftc -load-plugin-library` TestingMacros path is test-only and does not change
   the hosted command; hosted CI must still pass plain `swift test --no-parallel` with native macro discovery.
10. **Working tree not committed**: candidate identity is the hashed uncommitted files in §4. The README
    migration (§2, R08) is a documentation change on this candidate and carries no acceptance or status claim.
11. **Worker evidence ≠ acceptance** (D-014): the coordinator re-runs the gates independently; this document is
    input to that verdict, not the verdict.

## 11. Coordinator handoff checklist

- [ ] Independently verify §3 protected scope + §4 hashes against the delivered tree (including the seven files
      whose hashes moved this batch and `README.md`).
- [ ] Re-run all §5 gates on the frozen candidate; confirm **466** (395 Core + 71 AppSupport) with zero
      failures/skips, guard 21, packaging 9, on inherited `TMPDIR` with both overrides unset.
- [ ] Re-run the R07 additions and, if useful, the compiled `cache-repro/CacheProbeR3` to reproduce the R06
      verdict outside the test target.
- [ ] Run AC08 controlled native host (binaries at `$R/native/M10BFixtureHost`, `$R/transport/M10BTransportHarness`)
      — window launch, Check/Refresh twice, screenshots + interaction receipts.
- [ ] Run the authoritative AC09 controlled-transport real npm; record original vs executed argv, secret-free.
      The worker's loopback copy under `$R/transport` is available for reproduction; `E/fixture` and `E/parent`
      were left untouched.
- [ ] Confirm AC06 two-distinct-scratch-root single-record reuse at CLI/native level; AC07 Homebrew-first
      retention via injected monotonic; mixed Homebrew/npm never overlap.
- [ ] Check the R08 README migration against observed behaviour (usage lines, both documents, scratch wording)
      and restate the milestone status sentences that the worker was not authorized to change.
- [ ] After separate Git authorization: commit/push, then require **exact-SHA hosted all-7** — not prior branch green.
- [ ] Only after technical acceptance: coordinator records the new capability in the milestone log.
      M10-B acceptance does not authorize M10-C/D or release.
