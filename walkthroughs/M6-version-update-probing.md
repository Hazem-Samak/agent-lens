# M6 — Version / update probing

Branch: `feat/m6-version-update-probing` (from `main` at `460000b`, accepted M5).
Status: **independently accepted by the parent on 2026-10-14 (EEST); Git publication and branch closeout are parent-owned.**
This walkthrough records the parent's acceptance evidence; the worker's earlier self-review is not an
independent approval. M7 has not started.

## Independent parent acceptance — 2026-10-14 (EEST)

The parent accepted the exact corrected source/test snapshot after two distinct fresh builds and full
suite runs. The reviewed source/test hashes were unchanged through those gates and both read-only review
axes; the real Agent Lens cache content hash was unchanged. The parent acceptance ledger is
`/Users/corvette/.hermes/cache/scratch/agent-lens-m6-corrections.34ox7alx/corrected-final-parent-acceptance.json`.
Raw evidence root:
`/Users/corvette/.hermes/cache/scratch/agent-lens-m6-corrections.34ox7alx/parent-corrected-final.kd8vv4e9`.

The final test runs used a fresh build directory each time and the invocation-local Swift Testing macro
plugin load. This Mac's ordinary macro discovery is intermittent; no `Package.swift` change, dependency
change, or toolchain installation was made. The parent launched `swift test` with the exact argv below
(the parent used `subprocess.run`, not a shell). Only relevant fixture variables are listed; inherited
environment values are intentionally not reproduced.

Run A — `fresh-explicit`:

```text
argv: ["swift", "test", "--build-system", "swiftbuild", "--scratch-path",
      "/Users/corvette/.hermes/cache/scratch/agent-lens-m6-corrections.34ox7alx/parent-corrected-final.kd8vv4e9/fresh-explicit-build",
      "-Xswiftc", "-load-plugin-library", "-Xswiftc",
      "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"]
TMPDIR=/Users/corvette/.hermes/cache/scratch
AGENT_LENS_TEST_PRODUCTS=unset
AGENT_LENS_TEST_SCRATCH=/Users/corvette/.hermes/cache/scratch/agent-lens-m6-corrections.34ox7alx/parent-corrected-final.kd8vv4e9/fixtures
```

Verbatim excerpts from
`/Users/corvette/.hermes/cache/scratch/agent-lens-m6-corrections.34ox7alx/parent-corrected-final.kd8vv4e9/fresh-explicit.log`:

```text
Build complete! (20.61 secs)
✔ Test run with 180 tests in 0 suites passed after 23.447 seconds.
```

Parent acceptance ledger exit: `0`.

Run B — `fresh-no-overrides` (a distinct fresh build; both optional overrides unset):

```text
argv: ["swift", "test", "--build-system", "swiftbuild", "--scratch-path",
      "/Users/corvette/.hermes/cache/scratch/agent-lens-m6-corrections.34ox7alx/parent-corrected-final.kd8vv4e9/fresh-no-overrides-build",
      "-Xswiftc", "-load-plugin-library", "-Xswiftc",
      "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"]
TMPDIR=/Users/corvette/.hermes/cache/scratch
AGENT_LENS_TEST_PRODUCTS=unset
AGENT_LENS_TEST_SCRATCH=unset
```

Verbatim excerpts from
`/Users/corvette/.hermes/cache/scratch/agent-lens-m6-corrections.34ox7alx/parent-corrected-final.kd8vv4e9/fresh-no-overrides.log`:

```text
Build complete! (21.94 secs)
✔ Test run with 180 tests in 0 suites passed after 22.716 seconds.
```

Parent acceptance ledger exit: `0`. The two final raw logs are combined build/test output; the ledger
records the actual process exits. Earlier 177-test runs are historical intermediate gates, not the final
total.

An earlier ordinary `swift build` also exited 0; its raw excerpt is `Build complete! (16.40 secs)` in
`/Users/corvette/.hermes/cache/scratch/agent-lens-m6-corrections.34ox7alx/parent-final.65s3hqww/ordinary-build.log`.
That build preceded the final source-only blocker corrections; the two fresh final test runs above rebuilt
the corrected accepted source/test snapshot.

### Parent CLI smoke matrix and live M5 prefix

The parent ran the built CLI from the `fresh-no-overrides-build` products for all 12 forms. The per-form
stdout/stderr files are `cli-0.stdout` through `cli-11.stderr` under the raw evidence root above. Exact
status and stream expectations observed by the parent:

| # | CLI form | Exit | stdout | stderr |
|---:|---|---:|---|---|
| 0 | `agent-lens scan` | 0 | M5 report + update section | empty |
| 1 | `agent-lens scan --offline` | 0 | M5 report + update section | empty |
| 2 | `agent-lens scan --check-updates` | 0 | M5 report + update section | empty |
| 3 | `agent-lens scan --refresh-updates` | 0 | M5 report + update section | empty |
| 4 | `agent-lens debug-env` | 0 | `cli-4.stdout` (not reproduced; contains environment diagnostics) | empty |
| 5 | no arguments | 0 | one-line usage | empty |
| 6 | `agent-lens unknown-command` | 1 | empty | one-line usage |
| 7 | `agent-lens scan --unknown-flag` | 1 | empty | one-line usage |
| 8 | `agent-lens scan --check-updates --offline` | 1 | empty | one-line usage |
| 9 | `agent-lens scan --offline --offline` | 1 | empty | one-line usage |
| 10 | `agent-lens debug-env --offline` | 1 | empty | one-line usage |
| 11 | `agent-lens scan extra-operand` | 1 | empty | one-line usage |

The six valid forms have empty stderr; invalid syntax has empty stdout and the usage line on stderr.
The usage excerpt, verbatim from the raw invalid-form files, is:

```text
usage: agent-lens <scan [--check-updates|--refresh-updates|--offline]|debug-env>
```

The live inventory still reports Codex `0.162.1` from npm, OpenCode `2.0.28` standalone, and Grok CLI
`1.0.52` standalone. No default detected tool is Homebrew-formula-managed, so live update results are
honestly unknown and the count is zero. Verbatim excerpt from `cli-0.stdout`:

```text
VERSION / UPDATE STATUS
Codex  installed 0.162.1  latest known —  unknown — unsupported installation manager
OpenCode  installed 2.0.28  latest known —  unknown — no registry
Grok CLI  installed 1.0.52  latest known —  unknown — no registry
0 updates available
```

The parent compared the live M5 output prefix with
`/Users/corvette/.hermes/cache/scratch/agent-lens-m6-corrections.34ox7alx/parent-corrected-final.kd8vv4e9/baseline-live.stdout`,
captured from the untouched `460000b` binary. The parent ledger records `m5_prefix: true`; the current
prefix is the 33-line M5 report, followed by exactly one appended update section. This is the parent
comparison, not the older worker's 32-line count.

### Final regression and review disposition

The final fresh 177-test run in
`/Users/corvette/.hermes/cache/scratch/agent-lens-m6-corrections.34ox7alx/parent-final.65s3hqww/fresh-full.log`
failed on the process-test startup proof; a warm 177-test run was green but did not erase that failure.
The exact failure excerpts were:

```text
✘ Test productionProcessOutcomesReachTheCoordinatorWithinTheirRealBounds() recorded an issue at UpdateProbeCoordinatorTests.swift:1683:13: Expectation failed: markerReady
✘ Test productionProcessOutcomesReachTheCoordinatorWithinTheirRealBounds() failed after 4.714 seconds with 2 issues.
✘ Test run with 177 tests in 0 suites failed after 5.810 seconds with 2 issues.
```

The recovery corrected the test's startup/readiness and PID-cleanup proof with a test-only seven-second
deadline; production remains at the unchanged ten-second per-process deadline. Full artifact review also
found and the final correction/re-review resolved two data-path issues: selected formula operands now
derive from the manager-reported Cellar (including nested-prefix controls), and upstream stable text
cannot smuggle an embedded revision suffix—the separate Homebrew `revision` field remains supported.
The final 180-test gates pass the regression tests, including
`productionProcessOutcomesReachTheCoordinatorWithinTheirRealBounds`,
`batchUsesAtMostThreeQueriesWithDeduplicatedMetadataArguments`,
`selectedTargetMustBelongToTheManagerCellarByPathComponents`,
`nestedCellarComponentsKeepTheManagerVerifiedCellarAndCacheIdentity`, and
`stableSuffixCannotForgeARevisionAndSeparateManagerRevisionRemainsSupported`.

The parent independently ran the acceptance gates. Two separate artifact-only, read-only review axes
returned `passed: true` with no security, logic, or specification blockers after the corrections; targeted
rereview of the corrected blockers also passed. The earlier worker self-review is not counted as approval.
Nonblocking duplicate-ownership cleanup was explicitly deferred and not added.

### Approved scope exceptions and implementation boundaries

The accepted implementation includes eight production files under `Sources/AgentLensCore/Updates/`:
`HomebrewIdentity.swift`, `HomebrewUpdateProbe.swift`, `ProcessUpdateCommandRunner.swift`,
`UpdateMetadataCache.swift`, `UpdateProbeCoordinator.swift`, `UpdateScanRenderer.swift`,
`VersionComparison.swift`, and `VersionStatus.swift`. `ProcessUpdateCommandRunner.swift` is the
additional eighth production filename; it provides the required async bridge to the existing bounded
runner. The original brief's strict filename allow-list was explicitly and narrowly waived for it.

Four existing M2–M5 test files have only fixture-root helper changes:
`DetectorRegistryTests.swift`, `PathDiagnosticsTests.swift`, `ShellEnvironmentResolverTests.swift`, and
`ToolDetectorTests.swift`. Those helpers use a nonempty `AGENT_LENS_TEST_SCRATCH` override when supplied,
otherwise standard `TMPDIR`, canonicalize the chosen root, and fail closed if no authorized writable root
is available. Existing product assertions were not changed. Both overrides remain optional; the accepted
no-overrides run proves the standard macOS `TMPDIR` path works. These helper-only changes were also an
explicit user-approved exception to the original brief, not an unnoticed expansion.

The CLI integration-test sandbox uses macOS `sandbox-exec` to deny access to the real Agent Lens cache;
the production app remains unsandboxed as settled in D-009. `sandboxDeniesAllAccessToTheRealAgentLensCache`
and `sandboxedCheckUpdatesPublishesNoReusableCacheAcrossTwoRuns` pass in both final runs. Plain/offline
no-cache behavior is covered by `plainScanReportsNotCheckedAndMakesNoManagerCall`,
`offlineModeLaunchesNoProbeAndReadsNoCache`, and `offlineThroughRealCLIMakesZeroManagerCalls`; coordinator
mode gating keeps cache lookup out of those modes. The tests assert zero runner calls and unchanged seeded
cache bytes; there is no syscall-count seam, so no OS-level read counter is claimed.

The cache document is schema 3, rejects older incomplete documents, has a 21,600-second TTL and a 1 MiB
read/write limit. A successful entry stores registry ID; manager entry, canonical target, and fingerprint;
manager-verified Cellar; formula stem and full identity; selected entry, keg version, and canonical target;
probe-context digest; stable upstream version, separate revision, installed versions, and observation time.
It stores no raw environment, credentials, or unrelated package inventory. Cache keys use a stable SHA-256
digest. Actual subprocess working-directory context is verified by
`actualSubprocessWorkingDirectoryControlsCoordinatorCacheContext` and
`effectiveEnvironmentAndWorkingDirectoryEachInvalidateCoordinatorCacheKeys`.

Query/process and concurrency evidence in the final 180-test runs includes:

- At most three queries for an eligible formula batch; the synthetic current/update CLI paths assert
  `--cellar`, one deduplicated `info --json=v2 --formula …`, and one `outdated --json=v2 --formula` query.
  `checkUpdatesThroughRealCLIReportsSupportedBrewCurrentWithThreeQueries` passes. Empty eligibility and
  fresh cache hits each use zero queries via `batchWithNoEligibleFormulaRunsZeroQueries` and
  `checkUpdatesProbesOnceThenHitsTheSixHourCacheWithoutAnotherQuery`.
- Six-hour cache behavior is proved by `cacheHitBeforeTheSixHourBoundaryReturnsTheStoredMetadata` and
  `exactlySixHoursIsAMissAndAFutureTimestampIsAMiss`; refresh behavior by
  `refreshBypassesTheCacheAndAFailedRefreshDoesNotRenewOldSuccess`.
- The test-only process deadline is seven seconds for cold-start margin; production remains ten seconds
  and stdout remains bounded to 1 MiB. Process and cleanup proofs include
  `productionProcessHandlesParentExitBeforeItsHangingDescendant`,
  `captureKillsTerminationResistantProcessAfterEarlyStdoutEOF`,
  `versionQueryRejectsTruncatedOutputEvenWhenTheFirstLineLooksValid`, and
  `productionProcessOutcomesReachTheCoordinatorWithinTheirRealBounds`.
- Streaming, responsiveness, and one-batch admission are covered by
  `delayedManagerLeavesFlushedM5InventoryVisibleBeforeOneAppendedUpdateSection`,
  `realDelayedProcessLeavesMainActorResponsive`, and
  `overlappingRefreshCallsShareOneManagerBatchAdmission`.
- Cancellation and late-result/cache suppression are covered by
  `cancellationWhileWaitingLaunchesNoCommandsAndDoesNotCache`,
  `cancellationDuringFirstOrFinalQueryRejectsLateSuccessAndReleasesAdmission`,
  `cancellingARealHangingQueryWaitsForCleanupAndStopsTheBatch`, and
  `cancelledRealFinalQueryCannotPublishItsLateSuccessfulMetadata`.

### All 24 acceptance areas mapped to final tests

Each named test below passed in both current 180-test runs. The complete brief-to-assertion ledger is
`/Users/corvette/.hermes/cache/scratch/agent-lens-m6-corrections.34ox7alx/luna-stage4b/matrix-evidence.json`.

| Acceptance area | Representative passing test names |
|---|---|
| Three statuses | `equalVerifiedVersionsAreUpToDate`; `olderVerifiedVersionIsUpdateAvailable`; `unsupportedSchemeRetainsLocalTextAndNeverFabricatesLatest` |
| Numeric ordering | `semanticNumericComponentsCompareNumerically`; `semanticLargeComponentsDoNotOverflow` |
| SemVer | `prereleaseIdentifiersFollowSemVerPrecedence`; `shorterEqualPrereleasePrefixComesFirst`; `numericPrereleaseIdentifiersPrecedeAlphanumericOnes`; `buildMetadataDoesNotAffectPrecedence` |
| Homebrew revision | `homebrewRevisionOrdersSamePackageVersion`; `homebrewRevisionDifferenceIsAnUpdateNotAnUpToDate`; `kegRevisionStaysSeparateFromTwoComponentUpstream` |
| Unsupported formats | `strictSemanticParserRejectsMalformedText`; `unsupportedUpstreamFormatsRemainUnknownWithoutLexicalGuessing`; `selectedPackageNewerThanMetadataIsUnknownNotDowngrade` |
| Selected package | `selectedTargetMustBelongToTheManagerCellarByPathComponents`; `legitimateTappedFormulaAssociatesAnAgreeingOutdatedRecordByFullName`; `localVersionMustAgreeWithTheSelectedKegUpstream` |
| Identity failures | `foreignCellarSubstringNeverBorrowsAHomebrewCacheIdentity`; `duplicateFullIdentitiesAreAmbiguousNotGuessed`; `selectedEntryMutationDuringFinalQueryNeverPublishesOrPersistsVerifiedStatus`; `replacedManagerDuringFinalQueryCannotOwnTheOldMetadata` |
| Multiple kegs | `selectedOlderKegStaysUpdateEvenWhenACurrentKegIsInstalled`; `selectedCurrentKegStaysUpToDateDespiteOlderUnselectedKegInCellar`; `selectedCurrentKegStaysUpToDateWhenOnlyAnUnselectedOldKegIsOutdated` |
| Batch behavior | `batchUsesAtMostThreeQueriesWithDeduplicatedMetadataArguments`; `batchAlwaysSetsDiagnosticEnvironmentWithoutMutatingOriginal` |
| Empty eligibility | `batchWithNoEligibleFormulaRunsZeroQueries`; `npmAndMissingToolsInvokeZeroManagerCommandsAndCarryTypedReasons` |
| Manager lookup | `homebrewManagerIsTheFirstLivePathWinner`; `homebrewManagerSkipsBrokenLinksDirectoriesAndNonExecutablesThenResolvesASymlink`; `homebrewManagerResolvesEmptyAndRelativeRootsAgainstTheSuppliedDirectory`; `managerReportedCellarSupportsRepositorySymlinkLayoutAndZeroQueryHit` |
| Process bounds | `productionProcessOutcomesReachTheCoordinatorWithinTheirRealBounds`; `productionProcessHandlesParentExitBeforeItsHangingDescendant`; `versionQueryKillsTerminationResistantProcessAfterEarlyStdoutEOF`; `versionQueryRejectsTruncatedOutputEvenWhenTheFirstLineLooksValid` |
| JSON | `invalidEnvelopesFailClosed`; `infoParserToleratesExtraFieldsAndIgnoresCasks`; `malformedRelevantRecordBecomesAnInvalidMarkerNotAnOmission`; `utf16TranscriptFailsTheBatchAsInvalidOutput` |
| Offline/disabled | `offlineModeLaunchesNoProbeAndReadsNoCache`; `plainScanReportsNotCheckedAndMakesNoManagerCall`; `refreshBypassesTheCacheAndAFailedRefreshDoesNotRenewOldSuccess` |
| Reason honesty | `typedManagerFailuresKeepTheirEvidenceAndOpaqueExitStaysProbeFailed`; `rendererDistinguishesOfflinePolicyTypedNetworkEvidenceAndOpaqueExit` |
| Cache TTL | `cacheHitBeforeTheSixHourBoundaryReturnsTheStoredMetadata`; `exactlySixHoursIsAMissAndAFutureTimestampIsAMiss`; `changedIdentityOrFingerprintsAreMisses`; `corruptWrongSchemaAndAbsentFilesAreMisses` |
| Cache refresh | `refreshBypassesTheCacheAndAFailedRefreshDoesNotRenewOldSuccess`; `checkUpdatesProbesOnceThenHitsTheSixHourCacheWithoutAnotherQuery` |
| Cache storage | `writeFailureIsNeutralAndDoesNotThrowIntoInventory`; `successfulSaveReplacesTheDocumentAtomicallyAndKeepsOnlySelectedRecords`; `storedDigestIsAStableCryptographicSHA256NotHasherRandomized` |
| Reassociation | `resultsAreAssociatedByRegistryIDNotCompletionOrder`; `installedVersionChangeRecomputesStatusFromTheSameCachedMetadata`; `inconsistentM5SelectionSuppressesAnyStatusClaim` |
| Async behavior | `delayedManagerLeavesFlushedM5InventoryVisibleBeforeOneAppendedUpdateSection`; `realDelayedProcessLeavesMainActorResponsive`; `overlappingRefreshCallsShareOneManagerBatchAdmission` |
| Cancellation | `cancellationWhileWaitingLaunchesNoCommandsAndDoesNotCache`; `cancellationDuringFirstOrFinalQueryRejectsLateSuccessAndReleasesAdmission`; `cancellingARealHangingQueryWaitsForCleanupAndStopsTheBatch`; `cancelledRealFinalQueryCannotPublishItsLateSuccessfulMetadata` |
| Output/count | `rendererCountsOnlySelectedUpdatesAndUsesDeterministicUTC`; `diagnosticsRendererPreservesRegistryOrderDashVersionAndDegradedWarning`; `rendererDistinguishesOfflinePolicyTypedNetworkEvidenceAndOpaqueExit` |
| CLI syntax | `cliRejectsCombinedAndRepeatedScanFlagsWithUsageOnStderr`; `cliNoArgumentsAndUnknownCommandKeepTheirExitStatuses`; `validDebugEnvironmentCommandUsesTheFixturePathWithoutManagerProbes`; `refreshThroughRealCLIIsAValidScanModeAndRunsOneBoundedBatch` |
| M5 preservation | `checkUpdatesThroughRealCLIReportsSupportedBrewCurrentWithThreeQueries`; `realCLIAppendsAfterTheExactM5WinnerAliasShadowedAndInvalidPrefix`; `syntheticOffPathDegradedM5ReportRemainsTheExactBytePrefix`; `delayedManagerLeavesFlushedM5InventoryVisibleBeforeOneAppendedUpdateSection` |

### Product limitations and nonclaims

- The only live adapter is for Homebrew formulae. There are no cask, npm, standalone, uv/pip, or Cargo
  adapters. The real default inventory has no Homebrew-managed detected tool; current/update success paths
  are proven with synthetic fixtures, not a live tool installation.
- No `brew update` runs. “Latest” is the latest version known to the manager metadata at observation time,
  not a claim about globally latest upstream releases.
- The production bounded runner cannot distinguish DNS/HTTP 429 from arbitrary process failures; opaque
  failures are `probeFailed`. `networkUnavailable`/`rateLimited` require explicit policy or typed evidence
  from a controlled/future adapter; M6 does not infer them from empty output.
- No M7 UI, dependencies, package-manager modifications, or SwiftUI/AppKit imports in core were added.
  The repository had no GitHub Actions workflows, so no GitHub CI result is claimed.

### Historical test/cache/fixture disclosures

These events are retained as history, not treated as current acceptance evidence:

- The initial worker reported a 112-test run while awaiting parent acceptance. Earlier parent stage gates
  reported 114, 147, 159, 169, and 177 passing tests; their raw summaries remain in the stage logs under
  `/Users/corvette/.hermes/cache/scratch/agent-lens-m6-corrections.34ox7alx/`. They are intermediate totals.
- An ordinary test invocation that treated `AGENT_LENS_TEST_PRODUCTS` as mandatory failed seven tests.
  A fake HOME did not isolate Foundation's real cache directory, and an earlier successful synthetic CLI
  fixture wrote a synthetic metadata entry to the real Agent Lens cache. The parent disclosed and
  preserved that existing file; it was not deleted, reconstructed, or “restored” from a guess. Later
  macOS sandbox tests deny reads/writes to the real Agent Lens cache, and the final parent ledger records
  that its content hash remained unchanged during final acceptance.
- An early fixture allowed inherited PATH entries to precede the fake manager, so the real Homebrew
  executable was resolved and queried. Therefore the earlier categorical statement “no real Homebrew
  query occurred” was incorrect and is withdrawn. Later acceptance uses a closed fixture PATH with fake
  detector tools and fake Homebrew; the real-cache denial is separately enforced with macOS sandboxing.
- No Homebrew install, upgrade, uninstall, update, pin, unpin, relink, or tap mutation occurred. No
  package/dependency changes were made. The inaccurate historical fixture-isolation claim is not used to
  erase or minimize the real-cache write or early real-Homebrew query disclosures above.

The original frozen implementation contract and the staged RED/GREEN history below are preserved. Their
early test totals and worker-era scope notes are historical; the parent 180/180 gates and approved
exceptions above are the current acceptance record.

## Preflight and baseline

Recorded before any change (raw output).

```text
$ git rev-parse HEAD
460000b6183e5766a844a109fb0bbb3f7dd77594
$ git branch --show-current
main
$ git status --short
?? briefs/M6-version-update-probing.md
$ swift --version
swift-driver version: 1.168.6 Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1)
Target: arm64-apple-macosx27.0.0
$ swift build                       -> Build complete! (16.25 secs), exit 0
```

Baseline `swift test` with the default toolchain fails to load the Swift Testing macro plugin
(`external macro implementation type 'TestingMacros.TestDeclarationMacro' could not be found`). This is the
machine-specific condition the brief names. The documented `swiftbuild` fallback was used for every test run
in this milestone, with no change to `Package.swift`:

```sh
AGENT_LENS_TEST_SCRATCH="$root/fixtures" AGENT_LENS_TEST_PRODUCTS="$root/build/out/Products/Debug" \
swift test --build-system swiftbuild --scratch-path "$root/build" \
  -Xswiftc -load-plugin-library \
  -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib
```

Baseline suite under the fallback: **46 tests, exit 0** (historical M5 figure reproduced).

Baseline M5 CLI (captured before change, `/tmp/m6/baseline/scan.out`), exit 0:

```text
AI AGENTS                         3
...
PATH DIAGNOSTICS
Codex
  verified winner: /Users/corvette/.local/bin/codex -> .../@openai/codex/bin/codex.js (PATH slot 6; matches detector)
...
```

## Red/green evidence

### Step 2 — comparison and status (RED on semantics, not compilation)

The scaffold compiled with wrong values; the first run failed on behaviour:

```text
✘ Test semanticNumericComponentsCompareNumerically() ... Expectation failed: VersionComparison.ordering("1.9.0", "1.10.0", scheme: .semanticVersion) == .older
✘ Test homebrewRevisionOrdersSamePackageVersion() ... Expectation failed: VersionComparison.ordering("1.2.3_1", "1.2.3", scheme: .homebrewStable) == .newer
✘ Test strictSemanticParserRejectsMalformedText() ... Expectation failed: VersionComparison.ordering(text, "1.0.0", scheme: .semanticVersion) == nil
✘ Test run with 16 tests in 0 suites failed after 0.004 seconds with 41 issues.
```

GREEN after implementation: `✔ Test run with 16 tests in 0 suites passed after 0.004 seconds.` (exit 0)

Two scaffold-only compile errors were fixed before the RED run (`Result` failure types needed `Error`). They are
scaffold defects, not acceptance evidence, and are disclosed here.

### Step 3 — identity, JSON adapter, status resolver (RED → GREEN)

RED (scaffold), 22 of 26 failing on behaviour:

```text
✘ Test homebrewRevisionOrdersSamePackageVersion() ... failed after 0.003 seconds with 4 issues.
✘ Test batchUsesAtMostThreeQueriesWithDeduplicatedMetadataArguments() ... runner.calls.count == 3
✘ Test batchRejectsInvalidFormulaTokensBeforeAnyProcessStarts() ... result == .failure(.invalidFormulaName)
✘ Test selectedCurrentKegWithOlderUnselectedKegIsStillUpdateAvailableWhenMetadataIsNewer() ... == .updateAvailable
✘ Test run with 26 tests in 0 suites failed after 0.002 seconds with 36 issues.
```

GREEN: `✔ Test run with 26 tests in 0 suites passed after 0.019 seconds.` (exit 0)

### Step 4 — cache and coordinator (RED → GREEN)

RED (scaffold), 23 issues across 18 tests, including:

```text
✘ Test checkUpdatesProbesOnceThenHitsTheSixHourCacheWithoutAnotherQuery() ... runner.invocationCount == 3
✘ Test cancellationStopsBeforeLaterQueriesAndPublishesNothing() ... runner.invocationCount < 3
✘ Test storedDigestIsAStableCryptographicSHA256NotHasherRandomized() ... stableDigest("abc") == "ba7816bf..."
✘ Test run with 18 tests in 0 suites failed after 0.036 seconds with 23 issues.
```

GREEN: `✔ Test run with 18 tests in 0 suites passed after 0.074 seconds.` (exit 0)

### Step 5 — CLI syntax and usage (RED → GREEN)

RED on the M5 binary (the new flags were not yet parsed):

```text
✘ Test usageStringDocumentsTheExactScanModes() ... usage.contains("--check-updates") → false
✘ Test cliRejectsCombinedAndRepeatedScanFlagsWithUsageOnStderr() ... result.status == 1 → false  (got 0)
✘ Test run with 3 tests in 0 suites failed after 0.001 seconds with 5 issues.
```

GREEN: `✔ Test run with 3 tests in 0 suites passed after 0.262 seconds.` (exit 0)

## Historical implementer self-review findings (not independent approval)

The table below records the implementer's earlier self-review only. It is not an independent approval;
the parent's independent gates and the two read-only review axes are recorded in the current acceptance
section above. Each listed finding below was reproduced as a failing test before being fixed.

| # | Finding | Severity | Evidence | Disposition |
|---|---|---|---|---|
| 1 | Cancellation not observed: the runner ran all three queries after cancel | High | RED `invocationCount < 3` failed | Fixed: `Task.isCancelled` checked before each query and before cache publication |
| 2 | Only `upToDate` was cached; a verified `updateAvailable` re-probed every scan | High | RED `invocationCount == 3` on second scan (`successfulUpdateAvailable…`) | Fixed: persist any verified comparison (`isVerifiedComparison`); unknowns never cached |
| 3 | Cache key derived by `"/Cellar/"` substring, which the brief forbids | Medium | Regression `foreignCellarSubstringNeverBorrowsAHomebrewCacheIdentity` | Fixed: key built from path components; ownership still enforced at status time |
| 4 | A changed manager file had to invalidate the cache identity | Medium | `changedManagerExecutableInvalidatesTheCachedIdentity` | Verified: manager fingerprint (size + mtime digest) changes → fresh probe |
| 5 | Misleading comment described a cache-lookup dependency that no longer existed | Low | Code read | Corrected to describe actual behaviour |
| 6 | A transient stub `cellarFor` returned `nil` and would silently disable the cache | High (self-introduced) | Caught on re-read before any test ran | Removed; replaced by the path-component key |

Finding 6 was introduced during this milestone and removed before it reached a test run. It is recorded
because an orchestrator reviewing the diff should not have to rediscover it.

## Historical implementation notes reconciled with final acceptance

- **Live Homebrew success path is not exercised on this Mac.** No brew-managed default tool is installed.
  Current/update-available success is proven only through synthetic CLI tests with a fake `brew`; the live
  default inventory honestly reports unknown.
- **Opaque process outcomes.** The production bounded runner exposes spawn/timeout/output-limit/nonzero
  outcomes, not DNS or HTTP status. Opaque failures map to `probeFailed`; explicit offline policy maps to
  `networkUnavailable`, while network/rate-limit classifications require typed test/future-adapter evidence.
- An earlier worker note described Cellar-component selection using `lastIndex`. That observation belongs
  to the pre-final snapshot and is superseded by the accepted manager-reported-Cellar operand and nested
  Cellar identity regressions listed above; it is not a current limitation.
- **Partial cache hits** fall through to one full batch for all pending tools (the brief's one-batch rule).
  This is intentional, not a defect, but it means a mixed hit does not save queries.
- The old M5 extra-root fixture helper depended on `NSHomeDirectory()` and failed when scratch was outside
  `$HOME`. The accepted, user-approved helper-only fixture-root change is documented above; this is not
  left as an unresolved test requirement.

## Historical worker full-suite gate (112 tests; not final acceptance)

This earlier worker run is retained as implementation history. It predates later tests, corrections, and the
parent's final acceptance; it must not be reported as the final suite total.

```text
$ ACC=$HOME/.hermes/cache/scratch/agent-lens-m6-full.G0LH
$ AGENT_LENS_TEST_SCRATCH=$ACC/fixtures AGENT_LENS_TEST_PRODUCTS=$ACC/build/out/Products/Debug \
  swift test --build-system swiftbuild --scratch-path $ACC/build -Xswiftc -load-plugin-library \
  -Xswiftc .../libTestingMacros.dylib
✔ Test run with 112 tests in 0 suites passed after 2.078 seconds.
exit 0
```

Composition: 46 pre-existing tests (unchanged) + 66 new M6 tests.

## Historical worker CLI smoke matrix (superseded by parent matrix above)

```text
$ ./.build/debug/agent-lens scan                       exit=0  stdout_lines=37 stderr=""
$ ./.build/debug/agent-lens scan --offline             exit=0  stdout_lines=37
$ ./.build/debug/agent-lens scan --check-updates       exit=0  stdout_lines=37
$ ./.build/debug/agent-lens scan --refresh-updates     exit=0  stdout_lines=37
$ ./.build/debug/agent-lens debug-env                  exit=0  stdout_lines=27
$ ./.build/debug/agent-lens                            exit=0  stdout_lines=1
$ ./.build/debug/agent-lens unknown-command            exit=1  stdout_lines=0  stderr="usage: agent-lens <scan [--check-updates|--refresh-updates|--offline]|debug-env>"
$ ./.build/debug/agent-lens scan --unknown-flag        exit=1  stdout_lines=0
$ ./.build/debug/agent-lens scan --check-updates --offline  exit=1  stdout_lines=0
$ ./.build/debug/agent-lens scan --offline --offline   exit=1  stdout_lines=0
$ ./.build/debug/agent-lens debug-env --offline        exit=1  stdout_lines=0
$ ./.build/debug/agent-lens scan extra-operand         exit=1  stdout_lines=0
```

Matches the brief: six forms exit 0; six exit 1 with usage on stderr.

## Historical worker M5 preservation excerpt (32 lines; current parent comparison is above)

```text
$ ./.build/debug/agent-lens scan > after-scan.out
$ head -n 32 after-scan.out | diff baseline/scan.out -   -> no difference
M5 PREFIX: byte-identical to baseline (32 lines)
```

The appended section follows it:

```text
VERSION / UPDATE STATUS
Codex  installed 0.162.1  latest known —  unknown — unsupported installation manager
OpenCode  installed 2.0.28  latest known —  unknown — no registry
Grok CLI  installed 1.0.52  latest known —  unknown — no registry
0 updates available
```

## Offline and no-probe proof

Synthetic fake `brew` logs every invocation to scratch. Offline and plain scans must produce an empty log:

```text
$ scan --offline   (synthetic brew on PATH) -> brew.log: <empty>; cache file absent
$ scan             (synthetic brew on PATH) -> brew.log: <empty>; "update check not requested"
```

Covered by `offlineThroughRealCLIMakesZeroManagerCallsAndWritesNoCache` and
`plainScanMakesZeroManagerCallsAndReportsNotChecked`, both green.

## Fake-manager query counts

- Current/update synthetic run: `--cellar`, `info --json=v2 --formula codex`, `outdated --json=v2 --formula`
  → **3 queries** (`checkUpdatesThroughRealCLIReportsSupportedBrewCurrentWithThreeQueries`).
- Zero-eligible batch: **0 queries** (`batchWithNoEligibleFormulaRunsZeroQueries`).
- Fresh cache hit: **0 queries** (`checkUpdatesProbesOnceThenHitsTheSixHourCacheWithoutAnotherQuery`).

## Fixture history and accepted diff scope

An early CLI fixture put fake Homebrew after inherited PATH entries. The real Homebrew executable was
resolved and queried; that early run was not an isolated synthetic-manager test. Later accepted tests use
a closed fixture PATH with fake detector tools and fake Homebrew. A separate earlier fake-HOME attempt did
not isolate Foundation's real cache; the actual-cache write and subsequent denial/hash verification are
disclosed above. A stale `.build/debug/agent-lens` killed with SIGKILL (exit 137) from an earlier `swiftbuild`
run also caused an exit-9 test failure; current CLI tests select only the binary from their own products
directory when `AGENT_LENS_TEST_PRODUCTS` is supplied, and the final no-overrides test gate passes.

The accepted change set is limited to the M6 implementation and documentation: `Sources/AgentLensCore/AgentLensCore.swift`
(usage string), `Sources/agent-lens/main.swift` (CLI dispatch/orchestration), the eight update files listed
above, six new M6 test files listed in the matrix evidence, the four approved fixture-helper-only test
changes listed above, `README.md`, this status-updated brief, this walkthrough, and the M6 row plus D-019
in `DECISIONS.md`. The helper changes and additional async bridge were explicit user-approved exceptions
to the original frozen allow-list. `Package.swift`, dependencies, detector registry/schema/default JSON,
M5 production diagnostics, and unrelated files were not changed. `AgentLensCoreTests.swift` remains
unchanged. The parent verified the reviewed source/test hashes against the final accepted snapshot.

The source remains in `AgentLensCore` without SwiftUI/AppKit imports; D-009's production app remains
unsandboxed. No GitHub Actions workflow was present, so no GitHub CI check is claimed.

## Package-manager actions and remaining work

- No `brew install`, `upgrade`, `uninstall`, `update`, `pin`, `unpin`, `link`, or tap change occurred.
- An early fixture did query real Homebrew as disclosed above; the final live inventory had zero eligible
  formulae and therefore no update query. Do not repeat the old blanket claim that no real Homebrew query
  ever occurred.
- At the acceptance checkpoint, no M7 work, dependency changes, or package operations had occurred. The
  parent owned publication and branch cleanup; this walkthrough records accepted code, not publication.
  Current publication truth is Git refs/history and the parent's publication report.

## Handoff

The parent completed independent M6 acceptance and recorded the M6 decision/log entry. At the acceptance
checkpoint, remaining work was parent-owned documentation validation, authorized commit/push to `main`,
and branch cleanup after verified inclusion. Current publication truth is Git refs/history and the parent's
publication report. M7 remains outside this closeout.
