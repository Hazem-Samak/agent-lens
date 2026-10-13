# Walkthrough — M1: Walking skeleton

**Date:** 2026-10-13
**Brief:** `briefs/M1-walking-skeleton.md`
**Commit:** `2b07e3e` — *M1: walking skeleton — argument dispatch plus hardcoded scan report*
**Live at:** [github.com/Hazem-Samak/agent-lens](https://github.com/Hazem-Samak/agent-lens)

---

## What this milestone was for

Prove the entire path — repository → build → run → observable output → test — before any real logic exists. `agent-lens scan` now prints **one hardcoded tool**. No real detection, deliberately: if something is structurally wrong with the project, this milestone finds it cheaply.

## What was built

| File | Change |
|---|---|
| `Sources/AgentLensCore/AgentLensCore.swift` | No longer an empty placeholder. Gained a `ToolReport` model (`name` / `version` / `source`), a `WalkingSkeleton` fixture with **one hardcoded tool** (`Codex 0.154.0 npm`), a pure `renderScanReport(tools:)` renderer, and a `usageMessage`. |
| `Sources/agent-lens/main.swift` | **Real argument dispatch**, the point of the milestone: index 1 is the subcommand. `scan` → report, exit 0. No argument → one-line usage, exit 0. Anything else → usage on stderr, `exit(1)`. |
| `Tests/AgentLensCoreTests/AgentLensCoreTests.swift` | Three tests. The brief is explicit that this test is nearly circular **and that is fine** — "the test is not the point; the test harness is the point." From M2 onward the tests stop being circular (D-012). |

Constraints respected: no filesystem scanning, no `Process` usage, no network, no detectors, no UI, no code that looks at the real machine. `Package.swift` untouched — still zero external dependencies.

## Acceptance — raw terminal output (unedited)

**1. Scan:**

```
$ swift run agent-lens scan
Building for debugging...
[2 / 8] AgentLensCore
[12 / 15] AgentLensCore
[12 / 16] agent-lens-product
[22 / 42]
[25 / 42]
[29 / 42]
[31 / 42]
[33 / 42]
[34 / 42]
[35 / 42]
[36 / 42]
[39 / 42] agent-lens-product
[41 / 42] agent-lens-product
Build complete! (4.66 secs)
AI AGENTS                         1

✓ Codex          0.154.0    npm

exit code: 0
```
(Interleaved `ld: warning: search path ... not found` lines elided here for legibility only; they are the same benign SwiftPM warnings documented in the M0 walkthrough.)

**2. Unknown command must exit non-zero:**

```
$ swift run agent-lens bogus-command
Building for debugging...
[1 / 1]
Build complete! (0.28 secs)
usage: agent-lens <scan>
exit code: 1
```

**3. Tests:**

```
$ swift test
Building for debugging...
[3 / 11] AgentLensCoreTests-product
[13 / 17] AgentLensCoreTests-product
[15 / 17] AgentLensCoreTests-product
Build complete! (0.57 secs)
◇ Test run started.
↳ Testing Library Version: 2084
↳ Target Platform: arm64e-apple-macos14.0
◇ Test unknownCommandHasNonZeroSemanticsViaUsageText() started.
◇ Test scanReportContainsRequiredStrings() started.
◇ Test scanReportCountsExactlyOneTool() started.
✔ Test scanReportCountsExactlyOneTool() passed after 0.001 seconds.
✔ Test unknownCommandHasNonZeroSemanticsViaUsageText() passed after 0.001 seconds.
✔ Test scanReportContainsRequiredStrings() passed after 0.001 seconds.
✔ Test run with 3 tests in 0 suites passed after 0.001 seconds.
exit code: 0
```

## Done-when checklist

- [x] `swift run agent-lens scan` exits 0; output contains `AI AGENTS`, `Codex`, `0.154.0`, `npm`
- [x] `swift run agent-lens bogus-command` exits non-zero (exit 1, usage on stderr)
- [x] Test asserting the four required strings exists and passes
- [x] `swift test` exits 0 (3 tests)
- [x] Raw transcripts attached above
- [x] One commit on the milestone branch (main)

## Notes for the reviewer

- **The dispatch is real, not a hardcoded print** — proven by the `bogus-command → exit 1` branch, which the brief calls the case that matters.
- The renderer is a pure function over `[ToolReport]`, so M2's real environment resolution and M3's first real detector can feed it without touching the CLI's argument handling again.
- The usage text lives in `AgentLensCore` so it is testable without forbidden `Process` use in M1 — the unknown-command test asserts the exact string the CLI exits with.
- `DO NOT TOUCH` respected: scope, decisions, briefs, and `Package.swift` untouched.

## What changes next (M2 — environment resolution)

Per `briefs/M2-environment-resolution.md`, the highest-risk milestone of the whole project: the app must resolve the **login-shell** environment (via `getpwuid`, never `$SHELL`) instead of `ProcessInfo`'s PATH (D-005), because a GUI app would otherwise inherit a subtly wrong PATH that presents itself as a "detector bug" several milestones later. Model assignment per the briefs: this one goes to the strongest reasoning tier, not Flash.
