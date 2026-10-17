# M7 — First Native UI

Implementation branch: `feat/m7-first-ui` (historical; merged and removed).
Status: **passed and delivered** — implementation and parent independent technical acceptance complete; user visual approval of the initial native UI obtained 2026-10-16 (Africa/Cairo). Source and closeout documentation are committed and pushed to `main` as `36a3f1c`; delivery refs independently rechecked 2026-10-17. The app remains an unsigned local development build.

This walkthrough records the measured M7 implementation/acceptance. The frozen plan remains in [brief](../briefs/M7-first-ui.md) (historical plan, untouched); this document records current status.

## Evidence root

`R = /Users/corvette/.hermes/cache/scratch/agent-lens-m7-resume-20261016-014304` — the read-only evidence root for this closeout. Evidence paths `R/...` refer to that absolute external root; repository file paths are relative to the project root; Markdown links are relative to this document's directory. Raw excerpts are copied exactly from the logs; no transcript is fabricated or reconstructed.

## What was built

A first native SwiftUI macOS app over the accepted M0–M6 engine, added at M7 per D-011. The app consumes typed `AgentLensCore` models directly — never CLI presentation text — in one `NavigationSplitView` window: Inventory (every registry definition, missing tools distinguished from installed), Diagnostics (first-class destination), and selected-tool details. Search matches display name, executable name, and observed entry/target path; selection reconciles by registry ID and survives filtering/rescan. Details show local version, source heuristic, install state, selected entry/target, and matching PATH evidence; unknown versions stay neutral (never "up to date"). Native light/dark appearance, keyboard focus/navigation, selectable path text, and VoiceOver accessibility labels; no custom design system, no fabricated categories/icons.

Launch displays the window/loading shell immediately and runs a local-only scan asynchronously; no auto-check of updates on launch, activation, timer, or focus. Explicit Rescan captures a fresh login-shell environment; Check Updates uses the M6 cache; Refresh Updates bypasses it. Local-only/offline perform zero manager/cache I/O.

**Product vs hosted separation.** The actual product is the native SwiftUI app built from this repository (`Sources/AgentLensApp/`, `Sources/AgentLensAppSupport/`, `scripts/build-dev-app.py`). Host source/package live under `R/hosted-proof/` and the built app under `R/hosted-parent-r4-build/`; `R/hosted-parent-r4-evidence/` holds receipts, not host source. The external host runs byte-identical copied product views plus one imports-only entry stub (`AgentLensApp.swift`) for lifecycle observation. `R/hosted-parent-r4-evidence/copied-sources-verification.json` verifies 26 copied files = 25 byte-identical product source/resource files + 1 imports-only entry stub; `Sources/AgentLensApp/AgentLensApp.swift` in the host differs (imports-only stub). The host is not the product entry app.

New production files (frozen brief allow-list): `Sources/AgentLensAppSupport/InventorySnapshot.swift`, `InventoryService.swift`, `SessionEnvironmentProvider.swift`, `InventoryViewModel.swift`; `Sources/AgentLensApp/AgentLensApp.swift`, `MainWindow.swift`, `ToolListView.swift`, `ToolDetailView.swift`, `DiagnosticsView.swift`; `Resources/AgentLensApp/Info.plist`; `scripts/build-dev-app.py`. `Package.swift` was modified to add the `AgentLensAppSupport` target, the `AgentLensApp` executable, and the app-support test target. Core/CLI original files are protected and unchanged. New tests under `Tests/AgentLensAppSupportTests/` and `Tests/Packaging/test_dev_app_bundle.py`.

## Gate evidence (parent independent acceptance)

Toolchain, fresh parent check 2026-10-16: macOS 27.0.1 build 26A434; Apple Swift 6.4 (swiftlang-6.4.0.34.1); swift-driver 1.168.6; arm64-apple-macosx 27.0.0. Existing CLT validating-UTF8 and framework-search-path warnings are not new failures. A fresh read-only `swift --version` observation on 2026-10-17 (`R/closeout-toolchain-observation-20261017.txt`, exit 0) confirms `swift-driver version: 1.168.6` — a fresh observation, not a retroactive record of 2026-10-16.

Gates, all exit 0:

| Gate | Count | Result | Evidence (relative to `R`) |
|---|---|---|---|
| Swift Core tests | 184 | pass | `n1-parent/full.log:469` |
| Swift AppSupport tests | 38 | pass | `n1-parent/full.log:551` |
| Swift total | 222 | pass | `n1-parent/full.log` (184 + 38) |
| Python packaging tests | 9 | pass | `n1-parent/packaging.log:3-5` |
| Hosted self-checks | 8 | pass | `hosted-parent-r4-evidence/selfcheck.log:2` |

Latest parent product build: `R/n1-parent/{builder,packaging,full}.{log,exit}`, builder/packaging/full exit 0. Packaging R2 debug/release builders and CLI logs: `R/parent-r2-builder.{log,exit}`, `R/parent-r2-release-builder.{log,exit}`, `R/parent-r2-packaging.{log,exit}`, `R/parent-r2-cli.{log,exit}`, `R/parent-r2-full.{log,exit}`, exit 0. Fresh parent R4 external harness build exit 0 and selfcheck 8/8 exit 0: `R/hosted-parent-r4-evidence/{build,selfcheck}.{log,exit}`.

## Raw evidence excerpts (copied exactly from logs)

`R/n1-parent/builder.log:70`:

```
Build complete! (31.12 secs)
```

`R/n1-parent/full.log:469`:

```
✔ Test run with 184 tests in 0 suites passed after 22.980 seconds.
```

`R/n1-parent/full.log:551`:

```
✔ Test run with 38 tests in 1 suite passed after 0.390 seconds.
```

`R/n1-parent/packaging.log:3`:

```
Ran 9 tests in 1.299s
```

`R/n1-parent/packaging.log:5`:

```
OK
```

`R/hosted-parent-r4-evidence/selfcheck.log:2`:

```
ProbeHost self-check: 8 tests, 0 failure(s)
```

Acceptance receipts cited: `R/parent-final-technical-acceptance.json`, `R/parent-n1-acceptance.json`, `R/parent-r2-gates.json`, `R/parent-r2-direct-proof.json`, `R/parent-packaging-artifact-acceptance.json`, `R/parent-r2-adjudication.json`, `R/l1-parent-r2/parent-verification.json`, `R/final-technical-acceptance-matrix.md`, `R/deepseek-final-r4-review.md`, `R/user-visual-approval.json`, `R/final-toolchain.txt`, `R/native-n1-smoke.json`, `R/hosted-parent-r4-evidence/native-verification.json`.

## Reproduction commands

Command shapes are reproducible, invocation-local scratch outside repo/protected roots; `AGENT_LENS_TEST_SCRATCH`/`AGENT_LENS_TEST_PRODUCTS` unset for the full-suite gate. The builder default configuration is `debug` (`scripts/build-dev-app.py` parser, `choices=[debug, release]`). Different fresh debug/release roots outside protected paths are used; ordinary default-Darwin `TMPDIR` portability is not proven. The accepted full-suite invocation shape (invocation-local CLT plugin) is below with approved `TMPDIR` and optional overrides unset; the plain `swift test` shape is an optional alternative, not verified as the acceptance gate. The builder uses its actual script flags; no manually supplied plugin is asserted for the app build unless present in the raw command.

```sh
m7_root="$HOME/.hermes/cache/scratch/agent-lens-m7-$(uuidgen)"
mkdir -p "$m7_root/tmp" "$m7_root/tmp-explicit" "$m7_root/dev-app" "$m7_root/dev-app-release"

# Default debug build (builder default configuration)
TMPDIR="$m7_root/tmp" swift build --configuration debug --product AgentLensApp --scratch-path "$m7_root/app-build"
TMPDIR="$m7_root/tmp" swift build --configuration debug --product agent-lens --scratch-path "$m7_root/cli-build"

# Optional alternative (plain `swift test`), not verified as the acceptance gate
env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS \
  TMPDIR="$m7_root/tmp" \
  swift test --scratch-path "$m7_root/full-suite"

# Packaging: debug .app into a fresh scratch root
TMPDIR="$m7_root/tmp" python3 scripts/build-dev-app.py \
  --scratch-root "$m7_root/dev-app" --configuration debug
TMPDIR="$m7_root/tmp" python3 Tests/Packaging/test_dev_app_bundle.py \
  --app "$m7_root/dev-app/AgentLensApp-debug.app"

# Release build shape (separate fresh root, outside protected paths)
TMPDIR="$m7_root/tmp" swift build --configuration release --product AgentLensApp --scratch-path "$m7_root/app-release"
TMPDIR="$m7_root/tmp" python3 scripts/build-dev-app.py \
  --scratch-root "$m7_root/dev-app-release" --configuration release
```

Expected: each build/test exits 0; builder prints the absolute `.app` path; packaging unittest passes structural, relocation/resource, missing-resource, and original-build-path-read-denied tests and preserves the original build tree. `git diff --check` exits 0.

Accepted full-suite invocation shape (invocation-local CLT plugin):

```sh
test -r /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib
env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS \
  TMPDIR="$m7_root/tmp-explicit" \
  swift test --build-system swiftbuild --scratch-path "$m7_root/full-suite-explicit" \
  -Xswiftc -load-plugin-library \
  -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib
```

User launch example (built product, do not hardcode user-installed tools as stable global truth):

```sh
open /absolute/path/to/scratch/AgentLensApp-debug.app
```

## Native smoke evidence (actual relocated product)

Actual product app `R/n1-parent/dev-app/packaging/relocated/AgentLensApp-debug.app` launched via `cua.getApp`/macOS Launch Services after quitting the old build — no terminal `PATH` dependency. Launch-to-populated-AX observation 1209 ms (includes automation; observed upper bound, not isolated renderer timing; no sub-300 ms claim).

Observed (CUA, displayed on screen; no screenshot archive claimed):

- Visible toolbar search AX field; filter by display name (Grok CLI), executable (`grok`), and observed path (`opencode`); empty query restores all 3; no-results state.
- Hidden OpenCode selection and details retained when filtered; clear restores the selected OpenCode row.
- Inventory and Diagnostics destinations; keyboard `Down` selection; Rescan retains selection and destination.
- Exact path selected; native Edit Copy enabled for the selected path (`/Users/corvette/.opencode/bin/opencode`, triple-click selected exact path reported by AX).
- Native zoom to large and restore; all toolbar/search controls remain available. Narrow edge-drag resize attempted but window size unchanged in automation — drag-resize not claimed proven.
- Meaningful AX labels: tool row names combine display name/executable/install state; toolbar actions expose Rescan/Check Updates/Refresh Updates and help; search labeled.
- VoiceOver accessibility-tree labels verified; spoken output not exercised.
- Light/dark appearance and 760×500 narrow wrapping/native scroll verified on byte-identical copied product views in the external host.

## Same-identity and lifecycle proof (exact log locators)

Process-isolated explicit-repeat receipt (PID 7072): `R/hosted-parent-r4-evidence/explicit-repeat-process-7072-events.jsonl`. One `app_launch` seq 3. Old session AF0244E0, old run `2074DAFE` — hold seq 21, close seq 22, release seq 36, complete seq 39 (synth-a only); old second detector absent. Reopen in-process to new session `F7CD1C6B`, new run `BC1D34A7` — both detectors complete (synth-a seq 40, synth-b seq 42). Close/reopen evidence completes at seq 42; the process receipt continues through the service swap at seq 43 and the post-swap rescan at seqs 47/49, ending at seq 51.

Within `F7CD1C6B` session: two registry invocations / two scan runs (`BC1D34A7` and rescan `65E1552E`), four detector completions (synth-a 40, synth-b 42; rescan synth-a 47, synth-b 49); B zero registry/scanner events.

Master log: `R/hosted-parent-r4-evidence/native-all-events.jsonl`. Service swap to B at seq 43; post-swap rescan run `65E1552E` invokes A's registry only (seq 44) and completes both detectors (seq 47 synth-a, seq 49 synth-b). The swap and post-swap rescan are recorded in both the process-specific receipt and the master log.

Initial receipt (PID 83373, `native-all-events.jsonl`): old run `8CFF92C5` synth-a completes seq 29; new run `33D80C6B` synth-a completes seq 28 and synth-b completes seq 31 — seq 29 is the old run completion, not new.

Interrupted explicit R4 run timed out and is INVALID/excluded; a clean repeat (process 7072) supplies the cancellation proof. R3 host crash (PID 73359) occurred in the external host harness, was repaired in R4, and was not reproduced in R4; there is no evidence it was a product defect — this is not a categorical claim that no product lifetime bug can ever recur. Parent-attested screenshots exist as observation records; no screenshot file archive is claimed.

## Packaging trust boundary proof (compact)

P1 — Root policy: `scripts/build-dev-app.py` `validate_scratch_root` allows Hermes scratch (`$HOME/.hermes/cache/scratch/...`) and normal temp roots (`/tmp/...`, `/private/tmp/...`, `/private/var/folders/...`) but rejects `/Applications` descendants, the real app cache (`$HOME/Library/Caches/AgentLens`), repository descendants, and broad system/user roots (`/`, `$HOME`, `/private`, `/var`, `/tmp`, etc.) without writing restricted paths.

P2 — Guard uses real compiled accessor-derived resource and loader coupling: `build-dev-app.py` discovers `resource_bundle_accessor.swift` under the build root for `AgentLensCore` in the current configuration, extracts `bundleName`, verifies the `Bundle.main.resourceURL` / `Bundle.init(url:)` shape, copies the compiled bundle into the `.app`, and runs `--bundle-preflight`, which checks `AgentLensCoreResourceBundlePath` and `AgentLensCoreResourceBundleName` consistency. The decoy single-field schema-999 probe fails closed: exit 1, `bundle-preflight: failed: resource bundle path and name inconsistent`.

P3 — Current configuration Core accessor provenance validated: compiled accessor at `R/dev-app/swiftpm/out/Intermediates.noindex/AgentLens.build/Debug/AgentLensCore-t.build/DerivedSources/resource_bundle_accessor.swift`; original build preserved (`original_build_preserved: true`).

Results:

| Check | Result | Evidence |
|---|---|---|
| Original resource outside control read | exit 0, sha256 `8bba15dfafd9fd3135a3368edad647009ecdd3233b269e32b158e8191e21ea4e` | `R/parent-r2-direct-proof.json` `outside_control` |
| Same-sandbox read denied | exit 1, `Operation not permitted` | `R/parent-r2-direct-proof.json` `inside_control` |
| Relocated preflight | exit 0, `bundle-preflight: ok registry_count=3 registry_ids=codex opencode grok` | `R/parent-r2-direct-proof.json` `relocated_same_sandbox_preflight` |
| P2 schema-999 decoy fail-closed | exit 1, `bundle-preflight: failed: resource bundle path and name inconsistent` | `R/parent-r2-direct-proof.json` `P2_original_single_field_schema999_probe` |
| Originals preserved | `original_build_preserved: true` | `R/parent-r2-direct-proof.json` |

Receipts: `R/parent-r2-direct-proof.json` (P1/P2/P3 direct proof), `R/parent-packaging-artifact-acceptance.json` (P1/P2/P3 closed; L1 closed; all gates exit 0), `R/parent-r2-adjudication.json` (trust boundary), `R/l1-parent-r2/parent-verification.json` (L1 correction gates 0; freshness probe is a disposable fixture, not real-build proof).

Trust boundary: **trusted compiled-accessor-derived development-artifact metadata; no coordinated hostile executable/all-metadata tampering guarantee**. Packaging tests copy the actual relocated app for negative fixtures; the parent's disposable stale-marker control (test 02) refreshes the relocated copy; see `R/l1-parent-r2/parent-verification.json` and `R/deepseek-r3-review.txt`.

## Requirement → proof mapping (compact)

Uses `R/final-technical-acceptance-matrix.md` test names and receipts; not the full history. Native testing of every fixture is not claimed.

| Requirement | Proof (test names / receipts) |
|---|---|
| Registry order / counts / missing / identity | `localSnapshotKeepsEveryRegistryEntryInRegistryOrderIncludingMissingTools`; `selectionAndSearchStayStableUnderDuplicateDisplayNamesAndRescan`; `selectionReconcilesToFirstEntryWhenTheSelectedToolDisappears` (38 AppSupport tests, `R/n1-parent/full.log:551`) |
| Local facts / GUI-Core parity | `localSnapshotPreservesTypedCoreFactsVerbatim`; `coordinatorProvenanceSurvivesTheServiceIntoTheSnapshot`; views consume typed snapshot, no CLI presentation parsing |
| Unknown / shadowed / update reasons | `quietModesLeaveEligibleToolsNeutralAndTouchNeitherManagerNorCache`; `coordinatorProvenanceSurvivesTheServiceIntoTheSnapshot`; 184 unchanged Core tests (`R/n1-parent/full.log:469`) |
| Environment | `SessionEnvironmentProviderTests` session reuse/fresh capture/raw environment/degraded fallback; actual app launched via macOS Launch Services, no terminal PATH |
| Local-first / no unsolicited manager/cache I/O | `idleViewModelHasNoFactsAndLaunchPublishesLocalOnlyCounts`; `repeatedLaunchPerformsOneRegistryAndLocalScan`; `localOnlyRunAgainstAnAbsentCacheURLCreatesNoCacheArtifacts` |
| Check / Refresh / recovery | `failedRefreshReplacesAVerifiedBadgeWithATypedProbeFailure`; `failedRescanRetainsLocalFactsAndClearsVerifiedUpdateBadges`; `invalidRegistryDataIsReportedAsATypedCoreError` |
| Concurrency | Model/service scan-boundary tests; R4 native controls loading responsive during held scan |
| Packaging | P1/P2/P3 direct proof; Python 9 fail-closed negative tests (`R/n1-parent/packaging.log`) |
| CLI regression | 184 existing Core tests including CLI fixture integration, same full run exit 0; Core/CLI original files hash-protected |

## Integrity / hash boundary

Historical documentation-closeout snapshot, before delivery: `R/closeout-before.json` pins 68 project files. Independent re-hash before/after closeout: 65 unchanged + exactly 3 allowlisted doc changes (`DECISIONS.md`, `README.md`, `briefs/README.md`) + 1 new walkthrough (`walkthroughs/M7-first-ui.md`) = 69 files total. All 29 Core/CLI source and test files unchanged; closeout changes only the 3 approved docs and adds one walkthrough. The changed index (`briefs/README.md`) is **not** included in the preserved count. `git diff --check` clean; local links inspected. No extra tests run. No prior evidence or worker reports edited. `R/closeout-review-before.json` confirms 0 mismatches during the R1 review. These counts and receipts describe that closeout snapshot, not the subsequent delivery-note update or M8 planning. They do not assert results for later review rounds.

## Limits (preserved, not overstated)

- VoiceOver AX labels only; speech output not exercised.
- Dark and 760×500 checks used byte-identical copied product views in the external host; actual product drag-resize unproven (native zoom/restore observed).
- Publication suppression proven by controlled synthetic model/service tests; native window destruction is not used to infer suppressed publication.
- 1209 ms is launch-to-populated AX including automation, not isolated renderer/performance budget.
- Screenshots displayed by CUA; no screenshot file archive claimed.
- Current/unknown/update/error fixture and source cases verified; not every fixture was natively rendered in the product app.
- Local-only launch and manager/cache-quiet boundaries; explicit Check cache/Refresh bypass; neutral unknowns; useful facts retained; no tool management.
- Packaging is local development only: unsigned `.app`, no signing, notarization, install, release, background work, dependencies, or Xcode project.
- All 29 Core/CLI source and test files unchanged.
- `T3 Code (Nightly)` `Info.plist` freshly read 2026-10-16: `CFBundleShortVersionString = CFBundleVersion = 0.1.1-nightly.20261016.3218`, recorded as observed at documentation closeout; not retroactively asserted to have run earlier acceptance gates.
- Ordinary default-Darwin `TMPDIR` portability not proven; no environment/global config fix.
- Do not hardcode user-installed tools as stable global truth. User launch example: `open /absolute/path/to/scratch/AgentLensApp-debug.app`.
- The documentation closeout did not expand source scope. Git delivery was authorized afterward; signed app distribution remains outside M7.

## Publication status

M7 source and closeout documentation were committed as `36a3f1cd4ce3c926deadb2565d8e2a6938161c9f` (`feat(ui): complete M7 native macOS app`) and delivered to GitHub `main`. The former implementation branch is merged and removed. On 2026-10-17, a read-only delivery check found local `main`, `origin/main`, and `git ls-remote origin refs/heads/main` at that same commit, with a clean worktree before this documentation update. This verifies Git delivery; it does not claim a signed/notarized app artifact or public release.

The acceptance transcripts, counts, and UI evidence above remain historical M7 evidence; no acceptance tests were rerun for this delivery-note update. M8 planning is now recorded separately in [the path-actions brief](../briefs/M8-path-actions.md). No M8 implementation has started.
