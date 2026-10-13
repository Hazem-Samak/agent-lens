# Pre-M5 stabilization (accepted; M5 subsequently accepted)

Branch: `stabilize/pre-m5` (no commit, push, merge, or branch switch). The stabilization source fixes and independent acceptance are complete; M5 was subsequently implemented and accepted (see [M5 walkthrough](M5-duplicate-path-diagnostics.md)). Runtime reports `gpt-6-luna` via `openai-codex`; Max-reasoning setting is not exposed.

This walkthrough records the worker's stabilization runs and the parent's separate acceptance of the final sources. The M5 specification, implementation, and independent acceptance are now documented in the [M5 walkthrough](M5-duplicate-path-diagnostics.md). Existing source/test changes remain uncommitted. `Package.swift`, `DECISIONS.md`, and `AGENT_LENS_SCOPE.md` were not changed.

## Toolchain diagnosis

Observed toolchain: Apple Swift 6.4 (`swift-driver 1.168.6`), `xcode-select -p` = `/Library/Developer/CommandLineTools`; `/Applications/Xcode.app` is absent and `xcodebuild -version` reports that Xcode is required. The actual macro library exists and is executable:

`/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib`

`swift test --help` advertises `--scratch-path`, `--build-system`, and `-Xswiftc`; `swiftc -frontend -help` advertises `-load-plugin-library`.

Two fresh default `swift test --scratch-path ...` attempts completed the original 22 tests (22/22, exit 0). Other fresh default attempts failed before tests with `TestingMacros.TestDeclarationMacro ... plugin for module 'TestingMacros' not found`; one happened while default and native builds were run concurrently, and another occurred after adding regressions. The legacy native build system failed with `no such module 'Testing'`. Thus the failure is in toolchain/plugin discovery, not 22 failing tests; the default outcome was not repeatable in this session. Explicitly passing the installed Testing macro library allowed compilation and execution without Xcode, package dependencies, installs, or system configuration changes:

```sh
scratch=/Users/corvette/.hermes/cache/scratch/agent-lens-forced-macro
mkdir -p "$scratch/fixtures"
AGENT_LENS_TEST_SCRATCH="$scratch/fixtures" swift test --build-system swiftbuild --scratch-path "$scratch/build" \
  -Xswiftc -load-plugin-library \
  -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib \
  --filter versionQueryRejectsOutputFromNonzeroExit
```

Raw result after the plugin was explicitly loaded (RED was expected):

```text
Build complete! (16.70 secs)
◇ Test versionQueryRejectsOutputFromNonzeroExit() started.
✘ Test versionQueryRejectsOutputFromNonzeroExit() ... Expectation failed: version == nil
↳ version → "9.8.7"
✘ Test run with 1 test in 0 suites failed after 0.209 seconds with 1 issue.
raw exit code: 1
```

Use a separate scratch path for each clean run. Set `AGENT_LENS_TEST_SCRATCH` so fixture directories from the touched test files stay under Hermes scratch; Swift's `FileManager.default.temporaryDirectory` ignored a test `TMPDIR` override on this machine.

## Regression RED evidence (before product fixes)

The explicit-plugin focused run selected nine new/updated tests. Raw observed failures included:

```text
buildEnvironmentPreservesLeadingTrailingAndInternalEmptyPATHComponents: expected ["", "/first", "", "/second", ""], got ["/first", "/second"]
detectorDoesNotTreatDirectoryAsAnInstalledExecutable: got installedAndOnPath for a directory
versionQueryRejectsOutputFromNonzeroExit: got "9.8.7"
captureDiscardsLargeStderrWithoutBlocking: timedOut=true, dump=nil
captureKillsTerminationResistantProcessAfterEarlyStdoutEOF: timedOut=false, elapsed: 2.013808
```

After strengthening the version timeout fixture to record its PID and ignore SIGTERM, its focused RED run reported:

```text
✘ Test versionQueryKillsTerminationResistantProcessAfterEarlyStdoutEOF() ... Expectation failed: elapsed >= 0.4 && elapsed < 1.5
↳ elapsed: 2.335017
raw exit code: 1
```

The original false-positive fixture was corrected from `sleep 30` (not found with fixture-only PATH) to `exec /bin/sleep 30`, with a 0.2s timeout and elapsed-time bounds.

## Implementation and worker verification (GREEN)

Source/test changes are limited to the stabilization work:

- `Sources/AgentLensCore/Process/BoundedProcessRunner.swift`: deadline checks now run inside stdout draining; stdout storage is capped at 1,048,576 bytes. Overflow kills/reaps the process group within bounded cleanup and returns a distinct `outputLimitExceeded` result, never a timeout or successful partial capture.
- `Sources/AgentLensCore/Environment/ShellEnvironmentResolver.swift`: capture accepts only a non-overflow result from exit status 0; failed-shell output is rejected without logging or rendering the captured environment.
- `Sources/AgentLensCore/Detection/ToolDetector.swift`: version queries reject overflow, timeout, and nonzero exits.
- `Tests/AgentLensCoreTests/ToolDetectorTests.swift`: overflow assertions cover the 1 MiB cap, fail-fast behavior, bounded elapsed time, and killed writer; relative/empty-CWD verification discovers the active product directory from build/executable artifacts, supports `AGENT_LENS_TEST_PRODUCTS`, and has a no-scratch-env fallback. Its compiler/verifier output is file-backed to avoid pipe deadlocks.
- `Tests/AgentLensCoreTests/ShellEnvironmentResolverTests.swift` and `DetectorRegistryTests.swift`: prior scratch-fixture updates and safe boolean assertions were preserved and covered by the green suite.

The requested process-group PID assertions remain in place. The shell test uses its existing 0.1-second timeout and passed under concurrent full-suite runs; the version test retains its 2-second timeout and `/bin/sleep 30` PID marker.

Failed runs during this stabilization, with safe diagnostics only:

- First post-edit focused build: exit 1, `BoundedProcessRunner.swift:219: invalid redeclaration of 'now'`. Renamed the later poll timestamp; subsequent builds passed.
- First focused run after compilation: exit 1 in the isolated verifier link, with undefined `ToolDetector` / `ShellEnvironment` symbols. Artifact discovery was too broad around same-named intermediate and product objects; it now requires the module and a product/configuration directory. The focused run then passed.
- Handoff starting state: the first 30-test run was 29 passed / 1 failed because the early-EOF version test's PID marker was absent. The focused repeat subsequently passed in 0.508 seconds. That focused pass does not change the fact that the first full run failed; later full-suite runs are recorded separately below.

Final focused result (fresh scratch `agent-lens-luna-focused-20261013-c`): 11 tests passed, exit 0. The relative/empty-root integration test was also run in a fresh scratch with `AGENT_LENS_TEST_SCRATCH` unset: 1 test passed, exit 0, proving the ordinary-environment fallback.

Fresh worker full-suite results, each with a separate scratch root and serial builds:

- `agent-lens-luna-full-20261013-a`: 34 tests passed, exit 0.
- `agent-lens-luna-full-20261013-b`: 34 tests passed, exit 0.
- An additional fresh run, `agent-lens-luna-cli-20261013`: 34 tests passed, exit 0.

All runs used the installed Testing macro library, with no installs or dependency changes. Exact repeatable full-suite command (generates a new scratch root):

```sh
scratch="$HOME/.hermes/cache/scratch/agent-lens-stabilization-$(uuidgen)"
mkdir -p "$scratch/fixtures"
AGENT_LENS_TEST_SCRATCH="$scratch/fixtures" swift test --build-system swiftbuild --scratch-path "$scratch/build" \
  -Xswiftc -load-plugin-library \
  -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib
```

Focused regression command uses the same setup and appends:

```sh
--filter 'capture|versionQuery|boundedProcessRunner|detectorAndVersionQuery'
```

Live CLI verification from the `full-20261013-b` product:

```text
AI AGENTS                         3
✓ Codex          0.162.1    npm
✓ OpenCode          2.0.28    standalone
✓ Grok CLI          1.0.52    standalone
scan exit code: 0

shell:       /bin/zsh
degraded:    false
debug-env exit code: 0
```

`debug-env` also printed the resolved PATH and its entries, not the inherited environment dump. Post-run process check found zero live `yes`, `sleep`, `swiftc`, `swift-frontend`, `swift-driver`, or `clang` processes. At the time of these worker runs, `git diff --check` passed. No commit/push/merge was made. At that point, no M5 brief or plan/decision/registry/CLI/package files had been edited; the doc-only M5 brief revision is recorded below.

## Parent's independent acceptance of final sources

This acceptance was run independently by the parent against the final stabilization sources, from fresh Hermes scratch root:

`/Users/corvette/.hermes/cache/scratch/agent-lens-final-review.jRtnR2`

The parent ran:

```sh
AGENT_LENS_TEST_SCRATCH=/Users/corvette/.hermes/cache/scratch/agent-lens-final-review.jRtnR2/fixtures swift test --build-system swiftbuild --scratch-path /Users/corvette/.hermes/cache/scratch/agent-lens-final-review.jRtnR2/build \
  -Xswiftc -load-plugin-library \
  -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib
```

Recorded result: exit 0; 34 tests passed after 2.029 seconds. The parent then repeated the same invocation with `--skip-build`: exit 0; 34 tests passed after 2.025 seconds. These are the parent's independent result summaries, not a reproduced raw terminal transcript.

The parent also independently built and ran the CLI scan: exit 0, reporting Codex `0.162.1` / npm, OpenCode `2.0.28` / standalone, and Grok `1.0.52` / standalone. Each version was separately checked with `/bin/zsh -l -i -c '<tool> --version'` and matched. `debug-env` exited 0 with shell `/bin/zsh` and `degraded: false`; its PATH matched an independent login+interactive shell byte-for-byte. The parent confirmed no UI imports in core, protected package/decision/scope/default-registry/CLI files unchanged, `git diff --check` clean, branch still `stabilize/pre-m5`, and HEAD still `62e1816`. No commit was made.

These version and path observations are snapshots, not fixed future acceptance values. The M5 brief carries the run-time cross-check procedure and the last measured shape (Codex 1 path/1 target, OpenCode 2 paths/1 target, Grok 2 paths/1 target). At the time of this stabilization acceptance, no M5 implementation or M5 acceptance had been performed; M5 was subsequently implemented and accepted (see [M5 walkthrough](M5-duplicate-path-diagnostics.md)).

## Corrected M5 planning note

The original untracked M5 brief incorrectly described `ToolDetector.existingPath`, `existingPaths`, and `ScanEntry` as existing APIs and promised stale/orphan/history claims unsupported by evidence. The corrected draft replaces those assumptions with the actual public APIs: `ToolDetector.detect(in:)`, configured `extraSearchRoots`, `versionQuery`/`queryVersion`, `classifySource`, `ShellEnvironment.pathEntries`/`raw`/`isDegraded`, `DetectorDefinition.makeDetector`, `DetectorRegistry.loadDefault`, and `ScanRenderer.render`.

The brief specifies a new diagnostics enumerator and models; first-live winner alignment with the existing detector; separate counts for repeated slots, same-target aliases, and shadowed canonical targets; literal broken-link/non-executable/directory evidence; preserved tri-state/off-PATH semantics; degraded-environment warning; synthetic scratch-only acceptance; and deferral of orphan, ownership, and history claims. It allows new `Diagnostics` and test files plus narrow `scan` integration, while keeping existing shared detector, resolver, runner, registry/default JSON, renderer, package, and planning files read-only absent parent approval. At the time this planning note was written, the brief awaited review and M5 had not started; the brief has since been approved and M5 implemented and accepted (see [M5 walkthrough](M5-duplicate-path-diagnostics.md)).
