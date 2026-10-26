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
