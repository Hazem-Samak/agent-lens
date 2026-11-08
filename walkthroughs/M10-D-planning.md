# M10-D — npm Uninstall and combined npm acceptance planning

Status: **frozen planning record**, 2026-11-08 (Africa/Cairo). Implementation is authorized by the
owner and is recorded separately. This document does not claim implementation, native, or hosted
acceptance.

## Baseline and authority

- Branch: `codex/m10-npm-management`.
- Planning baseline: `4b828c72d4d443bcaeb9ec37b654118ce2e4583e`, which contains accepted M10-C
  implementation `fff287d79884bf2163642dfa6ef3543da5682565` plus documentation/evidence only.
- Brief: [`briefs/M10-D-npm-uninstall.md`](../briefs/M10-D-npm-uninstall.md).
- Owner authorization: 2026-11-08. The orchestrator is also the sole product writer (owner-authorized
  D-014 exception); independent reviewers are read-only. Plan reviewer route requested: OpenCode
  `opencode/glm-5.3-flash-free#max`. Implementation reviewers: mcode
  `minimax/MiniMax-M3.1-Flash` at `xhigh`, then agy `gemini-3.8-flash-high` at `high`. Perch
  `glm-5.3-flash-starter` at `max` is the emergency alternate.
- No implementation, Git delivery, merge, or release is authorized by planning alone.

## Plan revisions

### P1 — coordinator self-review

Reviewed the first draft against M10-C's accepted safety contracts and the roadmap:

- Made the public authorization surface an opaque `NpmUninstallPreparation` with no public
  initializer.
- Required `--dry-run` to remain probe-only and forbade log-level suppression in production.
- Closed the removal-criteria loophole: a still-live old selected target is not clean removal even
  when the package path is absent.
- Required the published ownership observation to be cleared after any launched Uninstall.
- Required the native destructive confirmation not to be the Return-key default.
- Tied both implementation review/revision rounds and exact-SHA hosted CI to the combined gate.
- Recorded the owner-authorized D-014 separation exception rather than implying independent
  coordinator acceptance.

### Independent review attempt

OpenCode plan agent (`opencode/glm-5.3-flash-free#max`) read the brief, roadmap, decisions, operations,
ownership, AppSupport, app views, tests, and fixture. Two invocations were time-boxed; both were
interrupted after extended stalls before a final report. The partial transcript is retained at
`M10-D-planning-evidence/opencode-review-partial.txt`.

One material finding was completed before the stall: the brief's claim that npm uninstall runs
`preuninstall`/`postuninstall` lifecycle scripts contradicts npm's primary documentation. npm v7+
does not implement uninstall lifecycle scripts. Verified independently against
[npm v10 scripts](https://docs.npmjs.com/cli/v10/using-npm/scripts): "uninstall lifecycle scripts are
not implemented and will not function." The brief, effect text, and acceptance wording were corrected
to state that npm does not run uninstall lifecycle scripts and that Agent Lens adds no script-policy
override.

Because the requested OpenCode route did not return a complete verdict, mcode and agy were started as
read-only fallback plan reviews. mcode (`minimax/MiniMax-M3.1-Flash`, `xhigh`) returned **BLOCK**
with four blocking findings: nil removal observations conflated absence with unreadability; ownership
stayed armed after a launched removal whose rescan failed; the acceptance matrix omitted removal
edge cases; and AC11's BLOCKED wording was ambiguous. The full review is retained at
`M10-D-planning-evidence/mcode-plan-review.txt`; corrections are frozen in
[`briefs/M10-D-R1-review-corrections.md`](../briefs/M10-D-R1-review-corrections.md). agy did not
return a plan verdict before being stopped. The OpenCode timeout is disclosed; no timed-out review
is represented as a PASS.

### P2 — revision after independent findings

- Corrected the npm uninstall lifecycle-script claim everywhere.
- Added a review-finding disposition record in the brief's planning section.
- Preserved the exact closed argv, optional version binding, no-metadata removal path, single gate,
  mandatory reconciliation, and combined Update/Uninstall gate.
- Re-ran structural checks: sequential D01–D07 and AC01–AC13 rows, balanced code fences, no
  production `--dry-run`/`--force`/`--ignore-scripts`, and baseline ancestry.

## Freeze and later revision

The base brief was committed and frozen at `3d6129d` before product implementation was committed.
mcode's plan review returned **BLOCK**; the accepted corrections were separately frozen in
[`briefs/M10-D-R1-review-corrections.md`](../briefs/M10-D-R1-review-corrections.md) at `46778d2`.
Implementation started in the working tree after plan freeze; the product commit is separate and
must cite these planning records. Planning freeze does not attest any implementation, native,
runtime, or hosted gate.

## Evidence

- `M10-D-planning-evidence/opencode-review-partial.txt` — unedited OpenCode transcript before the
  timeout; contains the verified lifecycle-script finding.
- `M10-D-planning-evidence/opencode-review-compact-partial.txt` — compact retry transcript; no
  verdict.
- `M10-D-planning-evidence/fallback-review-status.txt` — mcode/agy fallback invocation status.
