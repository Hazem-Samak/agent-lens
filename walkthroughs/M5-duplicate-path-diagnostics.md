# M5 — Duplicate / PATH diagnostics

Branch: `feat/m5-path-diagnostics`.
Status: M5 implementation and parent independent acceptance are complete, including the final test-fixture fallback correction. Final acceptance evidence is recorded below.

## TDD evidence

The first focused run used the scanner scaffold and failed on behavior (not compilation): the detector found installed executables but the diagnostic report had no first live candidate, no verified winner, and no shadowed-target count.

Raw terminal excerpt:

```text
Build complete! (18.37 secs)
◇ Test run started.
↳ Testing Library Version: 2084
↳ Target Platform: arm64e-apple-macos14.0
◇ Test pathDiagnosticsReportTheFirstLivePathWinner() started.
✘ Test pathDiagnosticsReportTheFirstLivePathWinner() recorded an issue at PathDiagnosticsTests.swift:54:5: Expectation failed: report.firstLiveCandidate?.entryPath == firstEntry
↳ report.firstLiveCandidate?.entryPath == firstEntry → false
↳   report.firstLiveCandidate?.entryPath → nil
✘ Test pathDiagnosticsReportTheFirstLivePathWinner() recorded an issue at PathDiagnosticsTests.swift:55:5: Expectation failed: report.selection == .winner(report.firstLiveCandidate ?? PathCandidateObservation(
↳ report.selection → .inconsistent("PATH diagnostic walk is unavailable")
✘ Test pathDiagnosticsReportTheFirstLivePathWinner() recorded an issue at PathDiagnosticsTests.swift:61:5: Expectation failed: report.shadowedInstallationCount == 1
↳ report.shadowedInstallationCount → nil
✘ Test run with 1 test in 0 suites failed after 0.008 seconds with 3 issues.
raw exit code: 1
```

## Focused M5 tests — final implementation

Command executed with a new Hermes scratch root:

```sh
scratch="$HOME/.hermes/cache/scratch/agent-lens-m5-focused-CE08EE7D-C821-4293-973A-0F952793837A"
mkdir -p "$scratch/fixtures"
AGENT_LENS_TEST_SCRATCH="$scratch/fixtures" swift test --build-system swiftbuild --scratch-path "$scratch/build" -Xswiftc -load-plugin-library -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib --filter 'pathDiagnostics|diagnosticsRenderer'
```

Raw test-run output:

```text
Build complete! (18.09 secs)
◇ Test run started.
↳ Testing Library Version: 2084
↳ Target Platform: arm64e-apple-macos14.0
◇ Test pathDiagnosticsMatchesDetectorForEmptySlotAndRelativeLiveRoots() started.
◇ Test pathDiagnosticsTreatsInvalidOnlyAndAbsentCandidatesAsNotInstalled() started.
◇ Test pathDiagnosticsReportTheFirstLivePathWinner() started.
◇ Test pathDiagnosticsRefusesAChangedTargetInsteadOfClaimingAFalseWinner() started.
◇ Test pathDiagnosticsResolvesEmptyAndRelativeRootsAgainstInjectedWorkingDirectory() started.
◇ Test diagnosticsRendererPreservesRegistryOrderDashVersionAndDegradedWarning() started.
◇ Test pathDiagnosticsRetainInvalidFilesystemEvidenceBeforeTheWinner() started.
◇ Test pathDiagnosticsSeparateRepeatedSlotsAliasesAndShadowedTargets() started.
◇ Test pathDiagnosticsReportsKnownExtraRootAsOffPathWithoutCallingItWinner() started.
◇ Test pathDiagnosticsDoesNotDoubleCountAnExtraRootOverlappingLivePath() started.
✔ Test pathDiagnosticsDoesNotDoubleCountAnExtraRootOverlappingLivePath() passed after 0.008 seconds.
✔ Test pathDiagnosticsReportTheFirstLivePathWinner() passed after 0.009 seconds.
✔ Test pathDiagnosticsMatchesDetectorForEmptySlotAndRelativeLiveRoots() passed after 0.009 seconds.
✔ Test pathDiagnosticsResolvesEmptyAndRelativeRootsAgainstInjectedWorkingDirectory() passed after 0.009 seconds.
✔ Test pathDiagnosticsTreatsInvalidOnlyAndAbsentCandidatesAsNotInstalled() passed after 0.009 seconds.
✔ Test pathDiagnosticsRefusesAChangedTargetInsteadOfClaimingAFalseWinner() passed after 0.009 seconds.
✔ Test pathDiagnosticsReportsKnownExtraRootAsOffPathWithoutCallingItWinner() passed after 0.010 seconds.
✔ Test pathDiagnosticsSeparateRepeatedSlotsAliasesAndShadowedTargets() passed after 0.010 seconds.
✔ Test diagnosticsRendererPreservesRegistryOrderDashVersionAndDegradedWarning() passed after 0.012 seconds.
✔ Test pathDiagnosticsRetainInvalidFilesystemEvidenceBeforeTheWinner() passed after 0.013 seconds.
✔ Test run with 10 tests in 0 suites passed after 0.013 seconds.
M5 focused exit code: 0
```

## Fresh full suite

Command executed with a separate new Hermes scratch root:

```sh
scratch="$HOME/.hermes/cache/scratch/agent-lens-m5-full-E75135A5-2F1A-4201-B7A8-254E2EEF7B49"
mkdir -p "$scratch/fixtures"
AGENT_LENS_TEST_SCRATCH="$scratch/fixtures" swift test --build-system swiftbuild --scratch-path "$scratch/build" -Xswiftc -load-plugin-library -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib
```

Raw final test-run output:

```text
Build complete! (17.55 secs)
◇ Test run started.
↳ Testing Library Version: 2084
↳ Target Platform: arm64e-apple-macos14.0
◇ Test pathDiagnosticsResolvesEmptyAndRelativeRootsAgainstInjectedWorkingDirectory() started.
◇ Test scanReportContainsRequiredStrings() started.
◇ Test pathDiagnosticsReportTheFirstLivePathWinner() started.
◇ Test buildEnvironmentIsDegradedOnTimeoutAndUsesFallbackPath() started.
◇ Test pathDiagnosticsRefusesAChangedTargetInsteadOfClaimingAFalseWinner() started.
◇ Test versionTokenExtractionHandlesKnownOutputShapes() started.
◇ Test detectorFindsExecutableOnPath() started.
◇ Test boundedProcessRunnerEnforcesDeadlineWhileStdoutRemainsReadable() started.
◇ Test captureDiscardsLargeStderrWithoutBlocking() started.
◇ Test schemaViolationsAreRejectedLoudly() started.
◇ Test buildEnvironmentPreservesLeadingTrailingAndInternalEmptyPATHComponents() started.
◇ Test parseEnvironmentDumpExtractsSentinelDelimitedPairs() started.
◇ Test parseEnvironmentDumpReturnsNilWithoutSentinels() started.
◇ Test pathDiagnosticsReportsKnownExtraRootAsOffPathWithoutCallingItWinner() started.
◇ Test versionQueryTimesOutAgainstHangingBinary() started.
◇ Test buildEnvironmentPassesRawEnvironmentThroughForProcess() started.
◇ Test pathDiagnosticsTreatsInvalidOnlyAndAbsentCandidatesAsNotInstalled() started.
◇ Test pathDiagnosticsMatchesDetectorForEmptySlotAndRelativeLiveRoots() started.
◇ Test scanRendererShapesAllThreeStates() started.
◇ Test versionQueryRejectsTruncatedOutputEvenWhenTheFirstLineLooksValid() started.
◇ Test detectorKeepsOrderAcrossEmptyPATHComponents() started.
◇ Test versionQueryRejectsOutputFromNonzeroExit() started.
◇ Test detectorDoesNotTreatDirectoryAsAnInstalledExecutable() started.
◇ Test versionQueryKillsTerminationResistantProcessAfterEarlyStdoutEOF() started.
◇ Test detectorAndVersionQueryHonorEmptyAndRelativeRootsInAnIsolatedWorkingDirectory() started.
◇ Test detectorUsesExtraRootsForInstalledNotOnPath() started.
◇ Test pathDiagnosticsSeparateRepeatedSlotsAliasesAndShadowedTargets() started.
◇ Test diagnosticsRendererPreservesRegistryOrderDashVersionAndDegradedWarning() started.
◇ Test captureParsesASuccessfulRealShellRun() started.
◇ Test scanReportCountsExactlyOneTool() started.
◇ Test buildEnvironmentIsDegradedWhenDumpHasNoPath() started.
◇ Test detectorReportsNotInstalledWhenNothingFound() started.
◇ Test captureTimesOutAgainstAHangingShell() started.
◇ Test unknownCommandHasNonZeroSemanticsViaUsageText() started.
◇ Test pathDiagnosticsDoesNotDoubleCountAnExtraRootOverlappingLivePath() started.
◇ Test pathDiagnosticsRetainInvalidFilesystemEvidenceBeforeTheWinner() started.
◇ Test captureKillsTerminationResistantProcessAfterEarlyStdoutEOF() started.
◇ Test captureRejectsSentinelsFromANonzeroShellExit() started.
◇ Test bundledFixtureDefinitionsMatchSyntheticLayouts() started.
◇ Test bundledDefaultDetectorsIsValidWithThreeTools() started.
◇ Test detectorClassifiesCellarAsBrew() started.
◇ Test addingAFourthDefinitionRequiresNoSourceChanges() started.
◇ Test detectorClassifiesNpmByResolvedSymbolicLinkTarget() started.
◇ Test detectorSkipsBrokenSymlinkAndKeepsFirstLivePathWinner() started.
✔ Test buildEnvironmentPreservesLeadingTrailingAndInternalEmptyPATHComponents() passed after 0.033 seconds.
✔ Test parseEnvironmentDumpExtractsSentinelDelimitedPairs() passed after 0.034 seconds.
✔ Test parseEnvironmentDumpReturnsNilWithoutSentinels() passed after 0.034 seconds.
✔ Test buildEnvironmentIsDegradedOnTimeoutAndUsesFallbackPath() passed after 0.034 seconds.
✔ Test buildEnvironmentPassesRawEnvironmentThroughForProcess() passed after 0.034 seconds.
✔ Test schemaViolationsAreRejectedLoudly() passed after 0.034 seconds.
✔ Test versionTokenExtractionHandlesKnownOutputShapes() passed after 0.034 seconds.
✔ Test scanReportContainsRequiredStrings() passed after 0.034 seconds.
✔ Test pathDiagnosticsResolvesEmptyAndRelativeRootsAgainstInjectedWorkingDirectory() passed after 0.034 seconds.
✔ Test scanRendererShapesAllThreeStates() passed after 0.034 seconds.
✔ Test detectorFindsExecutableOnPath() passed after 0.034 seconds.
✔ Test pathDiagnosticsReportTheFirstLivePathWinner() passed after 0.034 seconds.
✔ Test pathDiagnosticsMatchesDetectorForEmptySlotAndRelativeLiveRoots() passed after 0.034 seconds.
✔ Test pathDiagnosticsTreatsInvalidOnlyAndAbsentCandidatesAsNotInstalled() passed after 0.034 seconds.
✔ Test pathDiagnosticsReportsKnownExtraRootAsOffPathWithoutCallingItWinner() passed after 0.034 seconds.
✔ Test pathDiagnosticsRefusesAChangedTargetInsteadOfClaimingAFalseWinner() passed after 0.034 seconds.
✔ Test detectorDoesNotTreatDirectoryAsAnInstalledExecutable() passed after 0.034 seconds.
✔ Test detectorKeepsOrderAcrossEmptyPATHComponents() passed after 0.034 seconds.
✔ Test detectorUsesExtraRootsForInstalledNotOnPath() passed after 0.034 seconds.
✔ Test scanReportCountsExactlyOneTool() passed after 0.034 seconds.
✔ Test buildEnvironmentIsDegradedWhenDumpHasNoPath() passed after 0.034 seconds.
✔ Test detectorReportsNotInstalledWhenNothingFound() passed after 0.034 seconds.
✔ Test pathDiagnosticsSeparateRepeatedSlotsAliasesAndShadowedTargets() passed after 0.034 seconds.
✔ Test unknownCommandHasNonZeroSemanticsViaUsageText() passed after 0.034 seconds.
✔ Test pathDiagnosticsDoesNotDoubleCountAnExtraRootOverlappingLivePath() passed after 0.034 seconds.
✔ Test diagnosticsRendererPreservesRegistryOrderDashVersionAndDegradedWarning() passed after 0.034 seconds.
✔ Test pathDiagnosticsRetainInvalidFilesystemEvidenceBeforeTheWinner() passed after 0.034 seconds.
✔ Test boundedProcessRunnerEnforcesDeadlineWhileStdoutRemainsReadable() passed after 0.034 seconds.
✔ Test bundledFixtureDefinitionsMatchSyntheticLayouts() passed after 0.034 seconds.
✔ Test bundledDefaultDetectorsIsValidWithThreeTools() passed after 0.034 seconds.
✔ Test detectorClassifiesCellarAsBrew() passed after 0.034 seconds.
✔ Test detectorClassifiesNpmByResolvedSymbolicLinkTarget() passed after 0.034 seconds.
✔ Test captureParsesASuccessfulRealShellRun() passed after 0.034 seconds.
✔ Test addingAFourthDefinitionRequiresNoSourceChanges() passed after 0.034 seconds.
✔ Test detectorSkipsBrokenSymlinkAndKeepsFirstLivePathWinner() passed after 0.034 seconds.
✔ Test captureRejectsSentinelsFromANonzeroShellExit() passed after 0.091 seconds.
✔ Test captureDiscardsLargeStderrWithoutBlocking() passed after 0.110 seconds.
✔ Test captureKillsTerminationResistantProcessAfterEarlyStdoutEOF() passed after 0.128 seconds.
✔ Test versionQueryTimesOutAgainstHangingBinary() passed after 0.209 seconds.
✔ Test versionQueryRejectsTruncatedOutputEvenWhenTheFirstLineLooksValid() passed after 0.224 seconds.
✔ Test versionQueryRejectsOutputFromNonzeroExit() passed after 0.267 seconds.
✔ Test captureTimesOutAgainstAHangingShell() passed after 0.519 seconds.
✔ Test detectorAndVersionQueryHonorEmptyAndRelativeRootsInAnIsolatedWorkingDirectory() passed after 1.065 seconds.
✔ Test versionQueryKillsTerminationResistantProcessAfterEarlyStdoutEOF() passed after 2.017 seconds.
✔ Test run with 44 tests in 0 suites passed after 2.018 seconds.
Full-suite exit code: 0
```

## Final-review fixture fallback — RED

The parent review ran the focused M5 tests with `AGENT_LENS_TEST_SCRATCH` unset:

```sh
env -u AGENT_LENS_TEST_SCRATCH swift test --skip-build --build-system swiftbuild --scratch-path /Users/corvette/.hermes/cache/scratch/agent-lens-m5-parent.UtulEL/build -Xswiftc -load-plugin-library -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib --filter 'pathDiagnostics|diagnosticsRenderer'
```

Parent-reported result (summary, not a reproduced raw transcript): all 10 M5 tests failed immediately with `PathDiagnosticsTests` code 1 from fixture setup; no product assertions failed (exit 1). The helper incorrectly required orchestration to provide the environment variable.

The helper now uses a non-empty `AGENT_LENS_TEST_SCRATCH` override when provided, otherwise an isolated UUID-named fixture directory under `$HOME/.hermes/cache/scratch`. Existing per-test `defer` cleanup remains in place. The real home-relative tilde-expansion case and all assertions are retained; no production source or earlier stabilization test was changed.

## Final worker verification after the fallback fix

All build and test artifacts remained under Hermes scratch. The focused test build used:

```sh
scratch="$HOME/.hermes/cache/scratch/agent-lens-m5-worker-focused-6D74705D-B0FB-47AA-B94C-D6C9D56F63F0"
mkdir -p "$scratch/fixtures"
AGENT_LENS_TEST_SCRATCH="$scratch/fixtures" swift test --build-system swiftbuild --scratch-path "$scratch/build" -Xswiftc -load-plugin-library -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib --filter 'pathDiagnostics|diagnosticsRenderer'
```

Observed: 10 tests passed; focused exit 0. The same focused build then passed with the override removed and `--skip-build`: 10 tests passed; exit 0.

The no-override rerun was:

```sh
env -u AGENT_LENS_TEST_SCRATCH swift test --skip-build --build-system swiftbuild --scratch-path "$scratch/build" -Xswiftc -load-plugin-library -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib --filter 'pathDiagnostics|diagnosticsRenderer'
```

The fresh full-suite build used:

```sh
scratch="$HOME/.hermes/cache/scratch/agent-lens-m5-worker-full-522F120B-6E58-4F25-99C0-38538232E032"
mkdir -p "$scratch/fixtures"
AGENT_LENS_TEST_SCRATCH="$scratch/fixtures" swift test --build-system swiftbuild --scratch-path "$scratch/build" -Xswiftc -load-plugin-library -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib
```

Observed: 44 tests passed after 2.023 seconds; exit 0. The same full build then passed with the override removed and `--skip-build`: 44 tests passed after 2.013 seconds; exit 0. A post-run check found the override fixture directories empty and no fallback fixture roots left behind. The build emitted existing deprecation, redundant-`#require`, and linker search-path warnings; no test failed.

The no-override rerun was:

```sh
env -u AGENT_LENS_TEST_SCRATCH swift test --skip-build --build-system swiftbuild --scratch-path /Users/corvette/.hermes/cache/scratch/agent-lens-m5-worker-full-522F120B-6E58-4F25-99C0-38538232E032/build -Xswiftc -load-plugin-library -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib
```

## Worker-observed CLI checks

Ran the freshly built CLI from the full-suite scratch build. `agent-lens scan` exited 0 and reported three registry rows: Codex `0.162.1` (npm), OpenCode `2.0.28` (standalone), Grok CLI `1.0.52` (standalone). Verified renderer output:

- Codex winner `/Users/corvette/.local/bin/codex` → `/Users/corvette/.local/lib/node_modules/@openai/codex/bin/codex.js`, PATH slot 6; 1 live entry, 1 target, 0 aliases, 0 repeated slots, 0 shadowed installations.
- OpenCode winner `/Users/corvette/.opencode/bin/opencode`, PATH slot 5; alias `/Users/corvette/.hermes/bin/opencode`, slot 33; 2 live entries, 1 target, 1 alias, 0 repeated slots, 0 shadowed installations.
- Grok winner `/Users/corvette/.grok/bin/grok` → `/Users/corvette/.grok/downloads/grok-1.0.52-macos-aarch64`, PATH slot 1; alias `/Users/corvette/.local/bin/grok`, slot 6; 2 live entries, 1 target, 1 alias, 0 repeated slots, 0 shadowed installations.

`debug-env` exited 0 and reported shell `/bin/zsh`, degraded `false` (PATH itself omitted here). No arguments printed usage and exited 0; an unknown command printed usage and exited 1. CLI `PATH slot N` values above are one-based renderer numbers; scanner `origin.path(slotIndex:)` values are zero-based and the renderer adds 1.

## Parent independent acceptance summary — separate from worker runs

The parent independently reported product acceptance before this final test-fixture correction: its fresh full suite passed 44 tests in 2.011 seconds; live scan winners matched the results above; debug-env reported `/bin/zsh`, degraded `false`, with login/interactive shell PATH matching independently; no arguments exited 0 with usage, and an unknown command exited 1 with usage on stderr. Its Python cross-check reported exact path, target, count, and version matches for all three tools. The parent also compared 13 protected core/package/registry/stabilization-test hashes against the pre-M5 snapshot and reported them unchanged. These are parent-reported facts, not raw worker transcripts. At the time of that earlier summary, parent acceptance of the latest test-only fallback repair was pending; its later acceptance is recorded below.

## Final parent independent acceptance — after fixture fallback correction

The parent reran the complete suite against the final implementation from fresh Hermes scratch root `/Users/corvette/.hermes/cache/scratch/agent-lens-m5-final.Kc1Ag1`. Both full-suite invocations exited 0.

With `AGENT_LENS_TEST_SCRATCH` set:

```sh
AGENT_LENS_TEST_SCRATCH=/Users/corvette/.hermes/cache/scratch/agent-lens-m5-final.Kc1Ag1/fixtures swift test --build-system swiftbuild --scratch-path /Users/corvette/.hermes/cache/scratch/agent-lens-m5-final.Kc1Ag1/build -Xswiftc -load-plugin-library -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib
```

Short raw excerpts from the parent's tool output:

```text
Build complete! (18.30 secs)
✔ Test run with 44 tests in 0 suites passed after 2.018 seconds.
```

With the override removed and the same built products:

```sh
env -u AGENT_LENS_TEST_SCRATCH swift test --build-system swiftbuild --scratch-path /Users/corvette/.hermes/cache/scratch/agent-lens-m5-final.Kc1Ag1/build -Xswiftc -load-plugin-library -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib --skip-build
```

Short raw excerpt from the parent's tool output:

```text
✔ Test run with 44 tests in 0 suites passed after 2.017 seconds.
```

Additional parent-observed acceptance checks (summaries, not full transcripts):

- Final CLI scan exited 0 and produced three verified winner rows. Parsed live counts were Codex (1 entry, 1 target, 0 repeats, 0 aliases, 0 shadowed), OpenCode (2, 1, 0, 1, 0), and Grok CLI (2, 1, 0, 1, 0). Winner versions were Codex `0.162.1` / npm, OpenCode `2.0.28` / standalone, and Grok `1.0.52` / standalone. The independent Python cross-check matched paths, targets, counts, and versions for all three.
- `debug-env` reported `/bin/zsh`, `degraded: false`; its PATH matched the independent login+interactive shell. No arguments printed usage and exited 0; an unknown command printed usage on stderr and exited 1.
- Protected baseline: 13/13 unchanged, no mismatches. Core UI import violations: none. Declared test count: 44. Branch remained `feat/m5-path-diagnostics`, HEAD `62e1816`; no commit or push was made. Source hashes were confirmed and no product changes were made after these checks.
- The installed Swift Testing macro library still requires the documented explicit plugin flag in this environment; existing build warnings were nonblocking. No M6, GUI, or latest-version probes were started. Orphan/history/ownership inference remains outside the accepted M5 scope.

## Final pre-commit review fix and acceptance

An earlier independent review proved a false winner when verification re-resolved a captured target after the filesystem changed. The two-line fix carries the captured resolved target through `verifyPathWinner` and off-path verification instead of resolving it again. The parent reviewed the fix and two regression tests: preserve original target A while the changed target becomes symlink B, then require a consistency failure and no verified winner. This was independent-review evidence; no worker RED transcript is claimed.

Parent final acceptance used fresh scratch root `/Users/corvette/.hermes/cache/scratch/agent-lens-fixed-precommit.WIYv3i` and the documented explicit CLT `TestingMacros` plugin flag. Raw summaries:

```text
Build complete! (17.12 secs)
✔ Test run with 46 tests in 0 suites passed after 2.016 seconds.
Full-suite exit code: 0
✔ Test run with 46 tests in 0 suites passed after 2.026 seconds.
No-override (--skip-build) full-suite exit code: 0
```

The second full run used `env -u AGENT_LENS_TEST_SCRATCH` with `--skip-build`; both runs exited 0. A fresh-built CLI scan exited 0 with three verified winners: Codex `0.162.1` (npm), OpenCode `2.0.28` (standalone), and Grok CLI `1.0.52` (standalone); aliases were 0/1/1 and each had 0 shadowed installations. `debug-env` PATH matched the independent login+interactive shell. No-argument dispatch still exited 0 and unknown-command dispatch exited 1. At documentation time, the final targeted read-only review of the fix was still running. No final commit or push has been made; those remain the parent's responsibility.
