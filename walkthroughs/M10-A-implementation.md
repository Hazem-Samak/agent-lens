# M10-A — implementation report (worker)

**Status: worker candidate submitted. NOT independent acceptance, NOT M10-A complete.**

- Date: 2026-10-26 (Africa/Cairo)
- Branch: `codex/m10-npm-management`; `HEAD` `0005dcf3eb0f7a0bb4416c10ffa181e99834d244` (unchanged)
- Route: OMP 18.12.6, provider `workbuddy`, model `deepseek-v4.1-flash`
- Evidence root `E`: `/private/tmp/agent-lens-m10a-impl-20261026-4_wjuwpb`
- Amendment receipts: `E/worker/amendment/`. Earlier receipts preserved.
- No commit, stage, stash, push, PR, hosted CI or provider change. No subagents.

## Revision notice — this report supersedes its own R1 text

1. **Workflow body validation was retracted.** The R1 claim rested on replicating step text, not
   executing the YAML's own `run` bodies. Four bodies wrapped command+args in one quote pair (the
   shell saw one filename); three single-line `run:` entries relied on YAML quoting the parser strip
   before the shell sees it. Corrected in R2/R3; parent validator passes 28/28.
2. **The guard's unreadable-directory handling was a false negative.** `Path.rglob` suppresses
   traversal errors, so an unreadable root/subtree gave "0 Swift files … clean" / exit 0. Now an
   explicit `os.scandir` walk exits 2.

Git behavior across the phase is **not** uniform: an earlier interrupted attempt created a
worker-created stash (retained as a backup, recorded in `E/evidence/recovery.json`); all
post-recovery work made no Git mutations. The accurate statement is "one stash occurred in this
phase, before recovery", not "no stash occurred".

## Approved amendment (user-approved, implemented)

Production defect, measured before the change (`E/worker/amendment/probe/baseline-probe.out`): the
opener walked `URL(...).standardizedFileURL.pathComponents`, which rewrites `/private/var` back to
`/var`; `/var` is a symlink that `O_NOFOLLOW` refuses. **Both** logical and physical spellings failed
to open (`opened=false`), breaking anchored npm manifest opens.

`Sources/AgentLensCore/Process/ExecutableIdentity.swift`:

- `DirectoryIdentity` gains an internal, non-public `physicalPath`, captured with POSIX `realpath(3)`
  at observation and required to name the same device/inode. Resolution failure yields no observation.
- `openVerifiedDirectory(path:expected:)` keeps its signature and requires `path == expected.canonicalPath`
  as a consistency check. The walk consumes only the recorded physical string, split directly (no URL
  standardization), rejecting empty/`.`/`..` components rather than repairing them; every component is
  `O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC`; the opened descriptor is verified against the
  recorded device/inode.
- Canonical fields keep their existing consumers (containment, presentation, cache keys). No public
  accessor, serialization, cache-key change or production logging of the new field. No caller edits.

Fixture corrections (narrow): `PathDiagnosticsTests` derives a real `~/` route from the actual home
to the owned extra root via the existing `relativePath` helper, so tilde coverage is retained **even
when scratch is outside HOME** (the default-TMPDIR case being repaired) and no fixture files are
written under personal HOME. `UpdateProbeCoordinatorTests` **requires** the physical resolution
(`try #require`, no fallback) for the child's `getcwd()` and compares that, keeping
`counts=3,0;inputs=true;identity=true;cacheHit=true`, exit and empty-stderr assertions exact.

### R4 hardening (same four files)

- **Malformed recorded bindings are rejected before descriptor work.** A parent probe had shown the
  opener accepting a relative-prefixed binding (`"ignored" + valid`) and a NUL-suffixed one
  (`valid + NUL + …`) — both reached the SAME valid inode, because `dropFirst()` discarded the prefix
  and `withCString` truncated at the NUL. The binding must now be absolute and NUL-free, with
  non-empty components, and `.`/`..` rejected rather than repaired. The focused regression covers
  relative-prefix, relative-prefix-slash, NUL-suffix, NUL-embedded, `.`/`..`, trailing-slash and
  double-slash shapes, each built from the same directory's valid physical path, plus a control that
  the genuine binding still opens.
- **No-follow tests are load-bearing.** The ancestor and final-component cases now MOVE the observed
  directory aside and place a symlink at the recorded old location pointing to that **same original
  inode**. The test asserts the moved target has the same device/inode, so following the link would
  make the assertion fail; refusal can only come from `O_NOFOLLOW`. Directory replacement and
  grafted-binding checks remain separate identity guards.

## Final gate results

All runs: inherited ordinary `TMPDIR`, both Agent Lens overrides unset unless marked explicit, local
macro fallback in a fresh scratch child.

| Gate | Exit | Result |
|---|---|---|
| **Full Swift suite** (R4) | **0** | **Core 275 passed (0 failures), AppSupport 71 passed** — total 346 |
| `ExecutableIdentityTests` (new) | 0 | 9 tests passed (incl. malformed bindings + same-inode no-follow) |
| `InstallationOwnershipTests` (unchanged file) | 0 | 30 tests passed |
| off-PATH extra root | 0 | 1 passed |
| actual-subprocess cwd context | 0 | 1 passed |
| npm positive CLI ownership | 0 | 1 passed |
| npm FIFO manifest watchdog | 0 | 1 passed |
| guard fixtures | 0 | Ran 17 tests — OK |
| guard real tree | 0 | 26 files, no SwiftUI/AppKit |
| isolation (default / explicit) | 0 / 0 | 1 passed each |
| no-reuse two-run (default / explicit) | 0 / 0 | 1 passed each |
| debug app builder | 0 | app produced |
| packaging | 0 | Ran 9 tests — OK |

**Failure map status:** every case in `E/evidence/baseline-candidate-failure-map.json` passes. The
original baseline was 329 tests; the final suite is **346** (275 Core + 71 AppSupport). Additions are
declared: 8 M10-A guard/helper-side Swift cases already counted in the frozen R3 candidate plus the 9
new identity tests, with the two candidate-only CLI regressions corrected inside already-authorized R1
scope. Zero tests removed, disabled or skipped — no `.disabled` traits exist, and the eight
"skip"-matching lines are test *names* that all passed. No assertion was weakened.

## Limits

- **Hosted CI has never run. AC08 pending; local results are not hosted evidence.** No run URL.
- Native macro discovery is intermittent on this workstation; the documented invocation-local fallback
  was used and is labelled local-only. It does not certify native hosted behavior.
- The two-run `--check-updates` result is indirect no-reuse evidence (manager-query counts), not
  syscall-level proof about the personal cache.
- The sandbox decoy proves mechanism behavior only at its measured path.
- `actionlint` is unavailable locally; workflow validity rests on YAML parsing and actual body execution.
- Amendment scope was exactly the four approved paths; no other production file changed.

## Files changed in this amendment

`Sources/AgentLensCore/Process/ExecutableIdentity.swift` (physical binding + anchored walk),
`Tests/AgentLensCoreTests/ExecutableIdentityTests.swift` (new, 9 focused tests),
`Tests/AgentLensCoreTests/PathDiagnosticsTests.swift` (tilde derivation only),
`Tests/AgentLensCoreTests/UpdateProbeCoordinatorTests.swift` (physical cwd expectation only).
Prior M10-A paths remain as reported; the frozen R3 guard/helper/workflow candidate was not reopened.
## R5 — final review corrections (supersedes the R3 frozen statement above)

The earlier "frozen R3 guard/helper/workflow candidate was not reopened" statement is **superseded**: R5
reopened exactly the guard, the fixture-isolation helper/tests, the workflow and the two prose files.

Changed in R5:

- `CLIFixtureIsolation` / its tests: denial now requires the probe script to complete successfully with
  exactly one valid write and one valid read status (rejecting missing, duplicate, malformed, negative
  and out-of-range values), real pre-operation sentinel bytes, an unchanged expected sentinel and an
  absent denied leaf. Marker-plus-missing-receipt no longer reads as a proven denial. Fake-launcher
  regressions cover marker-only, truncated, duplicate, malformed, negative and post-marker nonzero exit;
  the real sandbox positive and unsandboxed negative controls remain.
- `CLIFixtureIsolationTests`: the authorized default base is derived from the inherited
  `TMPDIR` / `AGENT_LENS_TEST_SCRATCH` keys with no `NSTemporaryDirectory` fallback; a direct physical
  spelling of that base is tested alongside the alias, and the test-only resolver rejects NUL input.
- `scripts/check-core-ui-imports.py` + `Tests/Packaging/test_core_ui_imports.py`: symlinked directories
  and Swift-file symlinks fail closed with a named error instead of being silently skipped; loop and
  dangling links are covered. Guard fixtures are now **21**.
- `.github/workflows/ci.yml`: each gate keeps raw separate stdout/stderr and the producer exit verbatim,
  then a generated runner-temp verifier writes per-gate metrics JSON with producer, verification and
  effective exits. Count-bearing gates fail on absent, zero, under-floor or actually-skipped results.
  Floors: full suite Core **282** + AppSupport **71** = **353** total, guard fixtures **21**, packaging
  **9**, isolation **>=1**; the three registry/schema/query tests are asserted as PASSED events, not file
  names. The two Swift summaries are matched to floors by observed count, not position, and the parser
  accepts the real singular `1 test in 0 suites` shape. Summary reports passed / failed / NOT RUN with
  counts, skips, per-gate and aggregate elapsed.
- `README.md`: `AGENT_LENS_TEST_PRODUCTS` is a **directory** containing a regular executable
  `agent-lens`; Foundation/Seatbelt spelling behavior is described as measured on this workstation, not
  as universal macOS behavior, and the indirect no-reuse and decoy limits are preserved.

Evidence provenance:

- **Parent-executed (not mine):** 353 Swift tests (Core 282 + AppSupport 71) with the documented explicit
  plugin flags after a fresh native macro-discovery failure on this workstation; guard fixtures 21;
  explicit scratch 15 plus the CLI 2 in separate commands; actual generated-runner count cases **25**;
  actual YAML gate body argv/exit cases **28**. Packaging 9 was previously measured on the same shipping
  inputs and is unchanged.
- **My own executed checks:** YAML parse of the workflow and bash syntax of every `run` body; the count
  verifier against the real singular isolation output and the real 275/71 and 282/71 full-suite streams.
  My separate body-replay harness never produced a green result and is **superseded, not claimed green**;
  the parent's own replay is the authoritative body evidence.
- Native macro discovery remains intermittent here, so the parent's 353-test result used the documented
  invocation-local fallback and is labelled local-only.
- **Hosted CI has still never run and no Git delivery was authorized.** Action pins were verified by the
  parent against official refs; hosted behavior remains unproven.

## R6 — hosted constructor compatibility (user-approved, applied)

User approved the one-file amendment for `Sources/AgentLensApp/PathActions.swift` (explicit internal
initializer for `PathActionRow`). Applied exactly the hunk in
`E/parent/hosted-constructor-proposal/proposed.patch`: six inserted lines, zero deletions, no other
change in that file. Existing `private State` declarations/defaults, body, access levels and the
`ToolDetailView` caller are byte-identical.

- SHA256 before: `2099bd143585d65b4c7e4fee11eb5905cce824505d88ec7204be61ebdc8a9584`
- SHA256 after: `fadba4e513b3b0e926dcffbc30a06ef06f602d30695dbcd4c707a7de321e6084` (matches the approved after-hash)
- `git diff -U0`: `1 file changed, 6 insertions(+)`

Not executed by me: no build, no tests, no app launch, no hosted CI, no Git operations. Nothing here
asserts hosted acceptance; only a native hosted run can establish that.

## R7 (partial) — hosted fixture and summary portability, in-scope half only

Scope executed: the two authorized in-scope items from `briefs/M10-A-R7-hosted-portability.md`.
The protected-helper repair (aggregate `AgentLensCore.o` discovery in `ToolDetectorTests`,
`DetectorMetadataTests`, `UpdateProbeCoordinatorTests`) is **NOT done** — its human amendment is still
pending, so the three compiled-Core subprocess failures remain.

### 1. CLI fixture repair — `Tests/AgentLensCoreTests/UpdateCLIIntegrationTests.swift`

`writeRC` now takes the owned scenario `HOME` and writes the identical POSIX `export PATH=…` payload
to both `ZDOTDIR/.zshrc` and `HOME/.bash_profile`. All four scenario setups pass their existing owned
`home`. Production still resolves the login shell via `getpwuid`; no `$SHELL` override, no global
shell, no real rc file read, no change to the launch profiles, environments, watchdogs, assertions,
prefixes, query counts or exit/stderr checks.

Measured control (`E/worker/r7-in-scope/shell-fixture-control.json`), `/bin/bash -l -i` versus
`/bin/zsh -l -i` under one owned HOME/ZDOTDIR, closed fixture PATH, no tool discovery or managers:

| fixture state | `/bin/bash` | `/bin/zsh` |
|---|---|---|
| `.zshrc` only | real system PATH (fixture entry **absent**) | exact closed PATH |
| `.zshrc` + `.bash_profile` | exact closed PATH | exact closed PATH |

That reproduces the hosted defect (`bash` resolved, fixture silently missed) and shows the repair.

New real-process regression `loginShellFixtureExportsTheExactClosedPathForBothZshAndBash` runs both
shells with login+interactive flags under the standard cache-denial profile and asserts the PATH the
shell itself exports. Adds exactly **1** case.

Executed here (local, default `TMPDIR`, no overrides):

| run | exit | result |
|---|---|---|
| new shell case | 0 | 1 test passed, 0.181 s |
| `validDebugEnvironment…` | 0 | 1 test passed |
| `checkUpdates…ThreeQueries` | 0 | 1 test passed |
| `verifyInstallationNpm…` | 0 | 1 test passed |
| `sandboxedCheckUpdates…TwoRuns` | 0 | 1 test passed |
| Core target | 0 | **283 tests** passed |
| AppSupport target | 0 | **71 tests** passed |

Intermediate inventory **354 = Core 283 + AppSupport 71**, matching the declared floor.

### 2. CI summary repair — `.github/workflows/ci.yml`

The full-suite spec now accepts **exactly one combined summary or exactly two component summaries**
(`summaries: [1, 2]`). Combined mode enforces `combined_total_floor` 354 and the sum of component
floors, and reports only the observed total — it never fabricates per-target counts. Two-summary mode
keeps the multiset floors (Core 283, AppSupport 71) plus total 354. Both anchor groups (Core
registry/schema/query and AppSupport `productionWiringUsesOnlyTheCoreLoginShellSeams`) must be present
as PASSED events in either layout. Missing/zero/underfloor/three summaries, skip evidence, FAILED
verdicts and missing anchors stay red. Isolation gate (`summaries: 1`, floor 1), guard-fixtures (21)
and packaging (9) are unchanged, as are producer-exit authority, raw stream capture, metrics per gate,
the seven gate commands, unsets, pins, permissions, timeouts and the build backend.

Generated-verifier controls (`E/worker/r7-in-scope/controls/`, driver `verify_counts.py`):

| control | expected | observed exit |
|---|---|---|
| **actual hosted failed stream 40325427147** | red | **1** — "combined executed 353, below floor 354" + "reported failure" |
| combined 354, both anchor groups | green | 0 |
| combined 353 | red | 1 |
| combined, missing AppSupport anchor | red | 1 |
| combined, missing Core anchors | red | 1 |
| two components 283+71 | green | 0 |
| two components 282+71 | red | 1 |
| three summaries | red | 1 |
| no summary | red | 1 |
| combined with a skip event | red | 1 |
| combined, FAILED verdict | red | 1 |
| isolation 1 summary / floor 1 | green | 0 |
| isolation 0 cases / two summaries | red / red | 1 / 1 |
| guard-fixtures 21 / 20 | green / red | 0 / 1 |
| packaging 9 / 8 / skipped=1 | green / red / red | 0 / 1 / 1 |
| real local two-summary content | green | 0 |
| same real content as one summary | green | 0 |

The real local streams (283 + 71) verify green in two-summary mode; the same event content collapsed
into one 354 summary verifies green in combined mode. **The actual hosted failed stream remains red**,
and its red reason is now the honest one (total + failure), not a layout mismatch.

Workflow still parses as YAML with all **11 steps** and all seven gate invocations unchanged. No build
backend, TMPDIR, `||true`, `continue-on-error` or count reduction was introduced; no test was skipped
or removed.

### Limits

- The parser repair is **not** green-test evidence. Hosted run 40325427147 remains a failure: 19 cases
  / 64 issues, of which 16 CLI cases this repair targets and 3 compiled-Core cases awaiting the
  protected-helper amendment.
- No hosted run, no full-suite gate, no debug-app or packaging run, and no Git operation was performed
  or authorized here. Only a fresh native hosted run can establish acceptance.

### R7 correction — exact stdout assertion in the dual-shell fixture

Parent review found the first version of `loginShellFixtureExportsTheExactClosedPathForBothZshAndBash`
too weak: `result.stdout.contains(expected)` would accept the closed fixture PATH with an inherited
suffix appended — precisely the defect the control exists to detect.

Corrections applied (test body and doc comment only):

- The assertion is now **exact** `result.stdout == expected + "\n"`, the literal printf payload.
- The incidental `expected.contains("/usr/local/bin")` / `expected.contains("/opt/homebrew")`
  substring checks were removed; exact dynamic payload equality is the real invariant, and an
  operator-authorized scratch base whose name merely contains such text must not be rejected.
- Exit status 0 is still required. stderr is still **not** asserted empty, with the explicit comment
  that an interactive shell may print its `no job control` banner.
- `writeRC` doc corrected from "a non-interactive bash reads" to "a login bash reads `~/.bash_profile`
  via `HOME` (the fixture launches `-l -i`)", matching the actual invocation.

Discriminating control (`E/worker/r7-in-scope/exact-assertion-control.json`), same owned
HOME/ZDOTDIR, `/bin/zsh -l -i` and `/bin/bash -l -i`:

| rc payload | exported PATH | exact equality | old `contains` |
|---|---|---|---|
| closed fixture PATH | `fixture-bin:/usr/bin:/bin` | accepted | accepted |
| closed + `:/usr/local/bin` appended | `fixture-bin:/usr/bin:/bin:/usr/local/bin` | **rejected** | **accepted (would have passed)** |

So the old form would have gone green on a leaking shell; the new form fails closed.

Executed with real tools, focused case only (native macro discovery failed on this workstation, so the
documented invocation-local plugin fallback was used; that is local-only):

| run | exit | result |
|---|---|---|
| `loginShellFixtureExportsTheExactClosedPathForBothZshAndBash` | 0 | 1 test passed, 0.209 s |

Not re-run: any other test, the full suite, CI parser, debug app or packaging. No protected helper,
production source, `Package.swift` or CI file changed in this correction, and no Git operation was
performed.

## R7 completed — native test-product repair (coordinator-scoped)

Applied the three protected-file test-product seams under the coordinator's control grant, plus the
CI floor constants and one README sentence. No production source, `Package.swift`, packaging builder,
resources/schema, dependencies, timeouts or original assertions were changed, and no Git operation was
performed.

### Shared typed selection (`Tests/AgentLensCoreTests/ToolDetectorTests.swift`)

`AgentLensCoreProducts` now carries explicit `configurationRoot`, `moduleSearchDirectory`,
`objectFiles` and a `Layout` (`.aggregate` / `.native`). Provenance is explicit: it is never inferred
from the object count, so a one-object native vector is still native.

Recognized layouts, both measured on disk:

| layout | module | objects |
|---|---|---|
| Swift Build | `AgentLensCore.swiftmodule` beside the root | single `AgentLensCore.o` |
| native SwiftPM | `Modules/AgentLensCore.swiftmodule` | sorted regular `AgentLensCore.build/*.o` |

Validation is now fail-closed rather than best-effort:

- An **invalid override fails before any fallback**, including `AGENT_LENS_TEST_PRODUCTS=""`; relative
  and NUL-containing values are rejected rather than being URL-converted to the CWD. Absolute directory
  semantics are unchanged.
- A root holding **both** complete signatures is refused as ambiguous instead of picking aggregate by
  precedence.
- Every recognized-invalid layout error is **terminal**: only the `noLayout` code may keep climbing
  ancestors, so a nearer broken active root can never silently resolve to a valid (possibly stale)
  ancestor.
- A native vector containing an external or symlinked `.o` is **refused**, not filtered: dropping it
  would link an incomplete Core that still exits 0. A symlinked `AgentLensCore.build` directory is
  refused for the same reason. An escaping aggregate module/object is refused (the parent's prior
  aggregate-symlink measurement is preserved as a regression).
- Inputs are compared through the POSIX `realpath(3)` seam, so a legitimate `/var` ↔ `/private/var`
  alias of the same directory is accepted while anything outside the one canonical root is not.

Diagnostics are test-parent only, one line per selection, prefixed `core-probe` and naming
layout/root/module/object-count/`compiler=/usr/bin/swiftc` (the actual unchanged proxy). They never
reach a probe child's stdout/stderr, so no compile assertion is polluted. Compiler processes keep
their inherited environment (`DEVELOPER_DIR` included); the verifier's synthetic env is untouched.

Adapted seams only: the compile argv in `ToolDetectorTests` and `DetectorMetadataTests`, and the
context-verifier selection/argv in `UpdateProbeCoordinatorTests` (whose duplicate helper was deleted
because the shared seam now covers it). The approved physical-cwd fixture and the counts
`3,0`/inputs/identity/cacheHit/cwd/exit/stderr assertions are unchanged.

### Executed evidence (`E/worker/r7-products`, raw separated logs, producer exit captured)

| run | exit | result |
|---|---|---|
| 14 focused selection controls | 0 | 14 passed |
| `detectorAndVersionQueryHonor…IsolatedWorkingDirectory` | 0 | 1 passed, aggregate, objects=1 |
| `dangerousSchemaVersionsAreRejectedWithoutTrapping…` | 0 | 1 passed, aggregate, objects=1 |
| `actualSubprocessWorkingDirectoryControlsCoordinator…` | 0 | 1 passed, aggregate, objects=1 |
| the same three with `AGENT_LENS_TEST_PRODUCTS` = real native root | 0/0/0 | all passed, **layout=native, objects=27** |
| `AgentLensCoreTests` target | 0 | **297 tests** passed |

The 14 controls cover: aggregate selection; sorted, target-scoped native vector; one-object native
labelling; empty override with a valid bundle present; relative/NUL overrides; invalid override proven
not to fall back although the bundle alone would succeed; dual-layout ambiguity; incomplete active root;
**invalid nearer root with a valid ancestor** (load-bearing, throws); escaping module; external object
symlink; symlinked object directory; physical alias acceptance; active-bundle discovery with no CWD
fallback.

### Inventory and CI floors

353 existing cases are intact, plus the R7 shell-control case = 354, plus **14** new focused controls =
**368 = Core 297 + AppSupport 71**. Workflow floors updated to exactly that: Core 297, `total_floor`
368, `combined_total_floor` 368. Verified against the real streams:

| stream | verifier exit |
|---|---|
| real local 297 + 71 | **0** (two-summary) |
| 296 + 71 | 1 (underfloor) |
| actual hosted failed 353 stream | **1** — `combined executed 353, below floor 368` + `reported failure` |

Workflow still parses as YAML with 11 steps and the generated verifier still compiles.

### Limits (worker vs parent vs hosted)

- **Worker (this note):** local default Swift Build backend on this workstation, using the documented
  invocation-local plugin fallback because native macro discovery is intermittent here. Local only.
- The local deprecated native backend cannot import `Testing`, so a native-backend full-suite pass is
  **not** claimed. Native layout was instead exercised against the real 27-object product root through
  the explicit override on the supported default test runner.
- **Parent (not claimed here):** the full default suite, fresh debug app and all nine packaging checks.
- **Hosted:** no run has executed these changes. Hosted CI for this phase remains pending, and the
  failed runs 40300975808 / 40325427147 stay red as before-evidence.

### R7 final correction — physical (not lexical) bundle ancestry

Parent finding: the hint was resolved to a physical path only for the existence check, then ancestry
climbed the **lexical** parent. With an active `.xctest` SYMLINK living under a different complete
product root and pointing at the real bundle in another complete root, the seam selected the unrelated
lexical root.

Fix (selector hint initialization only): `physicalHint = canonicalPhysicalPath(hint)`, then the walk
starts at `physicalHint`'s `deletingLastPathComponent()` and continues over physical ancestors, bounded
to 8. Absolute physical configuration and the no-layout-only climbing rule are unchanged, so a nearer
invalid root still terminates the search.

New focused control `productSelectionFollowsThePhysicalBundleNotTheLexicalParentRoot`: a complete
aggregate root holds the real `Active.xctest`; a second complete aggregate root holds `Linked.xctest` as
a symlink to it. Selection must be the real bundle's root and must differ from the decoy. This is a
different-parent case, so the existing `/var` ↔ `/private/var` alias control cannot catch it.

Discriminating measurement (`E/worker/r7-products/physical-bundle-control.json`) over the same fixture
shape with raw POSIX paths:

| walk | selected root | correct |
|---|---|---|
| lexical ancestors of the unresolved hint (old) | `lexical-decoy` | **no** |
| physical ancestors of the resolved hint (new) | `physical-active` | **yes** |

Executed after the fix:

| run | exit | result |
|---|---|---|
| 15 focused selection controls | 0 | 15 passed |
| `AgentLensCoreTests` target | 1 | `298 tests`, one issue: `productionProcessHandlesParentExitBeforeItsHangingDescendant` elapsed 9.731 s vs its unchanged `< 9` bound |
| that same untouched case re-run in isolation | 0 | passed in 7.009 s |

The timing case is unchanged by this work (no budget or assertion edited); it exceeded its bound while
the whole suite ran under load. It is reported as observed, not claimed green from the full run.

Final inventory: 353 existing + 1 shell-control + **15** focused controls = **369 = Core 298 +
AppSupport 71**. Workflow floors now say exactly that.

### Correction — the 298+71 "green" control was synthetic, and it exposed a verifier gap

An earlier revision of this note claimed a **real** 298 + 71 stream verified green at exit 0. **That was
wrong.**
The Core run behind it was **red** (`✘ Test run with 298 tests in 0 suites failed … with 1 issue`,
`productionProcessHandlesParentExitBeforeItsHangingDescendant` elapsed 9.731 s against its unchanged
`< 9` bound). The control used to prove the floor was built by rewriting only the summary line of that
red stream to `✔ … passed` while keeping its failed-case and `recorded an issue` lines:

```
core = core_suite_stdout.replace('✘ Test run with 298 tests … with 1 issue.',
                                 '✔ Test run with 298 tests … passed.')
```

That is a **SYNTHETIC summary-altered copy**, not a passing stream, and it is not gate evidence. No raw
run artifact was rewritten; the original red receipts are intact. The local Core result is **red as
observed**, with the single timing case re-run in isolation green (7.009 s).

The synthetic copy also **exposed a verifier contradiction gap**: the generated verifier computed the
Swift Testing failure/issue events but never used them, so the altered stream verified **exit 0** while
its own output still contained a failing case. Reproduced against the pre-fix verifier from `HEAD`.

Repair (`.github/workflows/ci.yml`, failure-event detection only; floors, counts, gates, `producer_exit`
handling, pins and scope unchanged): `parse_swift` now rejects any line-anchored failure glyph
(`✘`/`✗` `Test`/`Suite`) or `recorded an issue` line independently of the summary verdict, and reports
`failure_event_count` / `issue_event_count` in the receipt.

Controls (generated verifier `E/worker/r7-verifier-contradiction/verify_counts.py`,
`sha256 26916c10…ab624`; driver inputs untouched):

| control | producer_exit | expected | observed |
|---|---|---|---|
| untouched real red local 298+71 | 1 | red | **1** — summary failure + 3 glyph events + 1 issue + contradiction |
| untouched real red local 298+71 | 0 | red (contradiction guard alone) | **1** — same reasons |
| **SYNTHETIC** summary-flip 298+71 | 0 | red | **1** — 2 glyph events + 1 issue + contradiction |
| pre-fix verifier on that same synthetic copy | 0 | — | **0** ← the gap |
| SYNTHETIC clean 298+71 (failure lines removed) | 0 | green | **0** |
| SYNTHETIC clean 297+71 | 0 | red | **1** — underfloor 298, total 368 < 369 |
| hosted failed 353 stream (40325427147), untouched | 1 | red | **1** — underfloor + summary failure + 84 glyph + 64 issue |
| SYNTHETIC, all summaries stripped, failure lines kept | 0 | red | **1** — missing summaries + floors + failure/issue events |

This guard makes an internally contradictory stream fail closed. It is **not** provenance proof: bytes a
verifier never saw produced cannot be authenticated, so the gate still relies on running the real suite.
Hosted CI remains pending; only the parent's actual full passing streams can establish the green gate.
Workflow parses with 11 steps; the verifier compiles.

---

## R8 implementation (worker report)

Scope: the five approved paths only. No Git mutation, no settings/credentials change, no
`Package.swift`/`Resources`/`AppEntry`/`InventoryService`/original-nine-test edit.

### Files

| path | change |
|---|---|
| `scripts/build-dev-app.py` | step 3 replaced by a pure `interpret_resource_accessor(content, bin_path)` seam (plus `AccessorInterpretationError` and lexical helpers). All other steps, guards, overrides and budgets are unchanged. |
| `Tests/Packaging/test_build_dev_app_accessor.py` | NEW, local-only pure parser controls (36 cases). Not discovered by the frozen CI packaging command. |
| `Sources/AgentLensCore/Detection/DetectorRegistry.swift` | `loadDefault()` resolves app-declared markers first; NEW internal `AppRegistryResourceError` + `AppRegistryResourceLocator`; internal injected `lazyFallback` on `loadDefaultRegistryData`. `validate(data:)` and the public error enum are untouched. |
| `Tests/AgentLensCoreTests/BundledRegistryResourceTests.swift` | NEW, 31 Swift Testing cases. |
| `.github/workflows/ci.yml` | floors/comments only: Core 298 to 329, total 369 to 400. No command/pin/timeout/step change. |

### Both generated accessor families

Recognition runs against a lexical code view (comments and string-literal contents blanked,
offsets preserved), so a declaration or call is matched only in code position:

* Swift Build: `let bundleName = "<stem>"` plus `bundleName + ".bundle"` consumed by
  `Bundle.init(url:)`. Duplicate declarations are ambiguous and refused.
* native: literal `mainPath` component and absolute literal `buildPath`, loaded through
  `Bundle(path: mainPath)` and `Bundle(path: buildPath)`; unrelated identifiers or a commented
  loader do not satisfy it. `buildPath`'s resolved parent must equal the observed `--show-bin-path`.

Both normalize to the same extension-free stem `AgentLens_AgentLensCore`; the builder appends
`.bundle` exactly once. Declaration spelling (`static let` vs `static nonisolated let`) is irrelevant.
Triple-quoted literals, nested block comments, WASI signatures, escapes/backslashes and
separator/traversal/doubled-suffix names fail closed; no unescaping and no bundle-name guessing.

### Core resource location

When either marker key is present both are authoritative: the name must be one safe component,
the path must be exactly `Contents/Resources/<name>.bundle`, the app resource root must physically be
the app's own `Contents/Resources`, and the bundle must resolve inside it. The registry file is found
with Foundation's `Bundle(url:).url(forResource:withExtension:)` (the frozen preflight's mechanism)
because the two real layouts differ (Swift Build nests under `Contents/Resources`, native is flat), then
containment, a real `lstat` regular-file check, and readability are enforced. Only when both keys
are absent does the legacy `Bundle.module` guard run, unchanged including its `fatalError` text.

### Measured results (raw streams under E/worker/r8-builder, E/worker/r8-core)

* parser controls: `python3 Tests/Packaging/test_build_dev_app_accessor.py` -> 36 ran, OK, exit 0.
* parent control matrix replayed: 8/8 as wanted (2 real accepts with equal normalized identity,
  6 refusals: comment-only line/block, string-only, duplicate name, duplicate native buildPath,
  wrong loader identifiers).
* locator probe built from the production seam against the parent's own fixtures:
  real R6 structured app ACCEPT, FIFO REJECT registry file is not a regular file (no read).
* focused Core: 31 new cases pass (`swift test --filter BundledRegistryResourceTests`), exit 0.
* full suite in an owned external scratch: Test run with 332 tests and Test run with 71 tests,
  both passed, exit 0, so Core 332 = 298 + 34 and total 403 = 403.

### R8 corrections after parent-executed counterexamples

Two executed counterexamples in the approved paths were fixed and re-verified:

* **Swift Build bound suffix.** `has_candidate_list` previously accepted any `bundleName + "..."`.
  A template with `bundleName + ".wrong"` was accepted and a `.bundle` identity was fabricated.
  The suffix literal is now read through the literal view: it must be exactly `.bundle`, must
  occur exactly once, and a chained or non-literal expression is refused. Parent matrix replay is
  now 10/10 (adds `wrong-swiftbuild-suffix` and `raw-string-only`), and three new Python negatives
  cover wrong literal, chained append, and a suffix that only appears in a comment. Parser controls:
  `Ran 39 tests`, OK, exit 0.
* **Partial injected context.** `loadDefaultRegistryData` previously required BOTH
  `infoDictionary` and `mainBundleURL` to use injected context, so a supplied marker dictionary
  with no app URL was silently replaced by process metadata and reached the fallback
  (measured `invalid-injected-marker:ACCEPT:fallback-calls=1`). Now a supplied dictionary is never
  discarded: any injected argument means the supplied values are used, and a marker-present
  dictionary without an app URL throws the new internal
  `AppRegistryResourceError.missingInjectedContext`. The parent's exact driver now reports
  `invalid-injected-marker:REJECT:fallback-calls=0`. A filled-in matrix probe confirms
  name-only, path-only and URL-without-dictionary all reject with `calls=0`, while the
  nothing-supplied production path still accepts with `calls=1` (the only fallback route).
  Three new Swift cases pin this on the same seam with invocation counters.

Local macro discovery failed first (`plugin for module 'TestingMacros' not found`), so the documented
invocation-local `-load-plugin-library .../libTestingMacros.dylib` fallback was used for local runs only.
Not claimed: hosted CI, parent acceptance, or any backend/native-suite result.

### R8 correction: interpreter compatibility of the builder parser

The new step-3 helpers annotated `str | None` / `tuple[str, str] | None`. Under `from __future__
import annotations` those are documentation only; without it they evaluate at import time and the
unmodified builder's interpreter floor is silently raised (measured: installed
`/usr/bin/python3` 3.9.6 raised `TypeError: unsupported operand type(s) for |: 'type' and 'NoneType'`
at `scripts/build-dev-app.py:132`, before a single parser control ran). The reviewed builder
imported fine there, so this was a regression introduced by the amendment, not a new requirement.

Fix is the single `from __future__ import annotations` statement plus a comment. No function body,
interpreter selection, toolchain, dependency or parser semantic changed, and the annotations keep
their exact spelling. Verified with the actual system interpreter:

* `/usr/bin/python3` 3.9.6 import of the builder: exit 0.
* `/usr/bin/python3 Tests/Packaging/test_build_dev_app_accessor.py`: 39 ran, OK, exit 0.
* current `python3` on the same file: 39 ran, OK, exit 0.
* `/usr/bin/python3 scripts/build-dev-app.py --help`: exit 0, usage intact.

No Swift file, CI file, packaging test or baseline builder body was modified in this correction.

### R8 correction: independent Core identity

The earlier marker-selected loader was rejected by the unchanged packaging suite. Both real builders
succeeded and the Swift suite passed, but BOTH unchanged packaging runs failed `test_09` at Case C:
paired valid markers named a decoy `mismatch.bundle` (1 detector) while the real Core bundle
(3 detectors) was retained, so the marker-selected loader read the SAME decoy the frozen preflight
had already validated and the equality check falsely passed (`AssertionError: 0 == 0`). Raw red
evidence is preserved at `E/parent/r8-default-packaging` and `E/parent/r8-native-packaging`;
methods 01-08 passed and 09 stopped at C, so D/E/F did not execute. The earlier 403 pass and the
builder successes are therefore partial candidates, not acceptance.

Identity is now independent of the declaration:

* `AppRegistryResourceLocator.compiledBundleStem = "AgentLens_AgentLensCore"` is a source-owned
  compiled project contract tied to the frozen `Package.swift` (package `AgentLens`, target
  `AgentLensCore`), never a heuristic, directory search or second candidate.
* The marker pair remains a BRANCH and VALIDITY signal: both keys, exact
  `Contents/Resources/<name>.bundle`, physical containment, Foundation bundle lookup, `lstat`
  regular + readable checks. Any defect throws the internal `AppRegistryResourceError`.
* Only after that validation does Core resolve ITS OWN compiled bundle under the same app resource
  root, with the same containment and regular/readable rules, and return those bytes.
* A valid declaration naming a different bundle therefore does NOT throw: Core loads the real
  payload, and the frozen `AgentLensAppEntry` compares different definitions and emits its existing
  `bundle-preflight: failed: loaded registry mismatch with guarded bundle` with ordinary exit 1.
* A missing compiled bundle while a valid decoy exists throws `bundleMissing` and does not consult
  the fallback; the decoy is never read as Core.
* Both markers absent still takes the exact historical lazy `Bundle.module` guard, including its
  `fatalError` statement. No stderr is emitted on any branch.

Shared resolution was factored into `resolvedAppRoots` and `registryFile(inBundle:)` so the
declaration check and the compiled lookup cannot drift apart. Doc comments that implied the markers
select Core's identity were corrected; markers are a branch/validity signal only.

New Core cases (fixtures now take the ACTUAL bundle name from
`AppRegistryResourceLocator.compiledBundleStem` and keep the decoy separate):

* `validDeclaredDecoyLoadsCompiledCorePayloadWithoutThrowing` - paired valid decoy, compiled
  bundle present: returns the compiled payload and order, does not throw, fallback 0.
* `compiledBundleMissingWhileValidDecoyExistsThrows` - internal `bundleMissing`, fallback 0.
* `customCompiledPayloadIsReadByContentAndOrder` - custom payload read verbatim in order.

Focused results (`E/worker/r8-identity`): `swift test --filter BundledRegistryResourceTests` ->
`Test run with 37 tests in 0 suites passed`, exit 0. Full suite in the owned external scratch ->
`Test run with 335 tests` and `Test run with 71 tests`, both passed, exit 0. So Core 335 = 298 + 37
and total 406 = 406; the earlier 403 figure is superseded. A seam-only probe built from this file
reported `paired-valid-decoy:bytes-equal-compiled=true:fallback-calls=0` and
`compiled-missing:REJECT:fallback-calls=0:...declared resource bundle is missing`.

Not changed: builder/Python (39 controls pass on both 3.9 and 3.15, `scripts/build-dev-app.py`
still derives the real name from the accessor), the original packaging suite, `AgentLensAppEntry`,
`Package.swift`, `Resources`, public API and public error cases. Parent owns the fresh default and
native builder runs against real packaging 9, the updated native-object probes and hosted CI.
