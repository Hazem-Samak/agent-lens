# Walkthrough — M3: One real detector

**Date:** 2026-10-13
**Brief:** `briefs/M3-real-detector.md` (drafted as part of this milestone, per `briefs/README.md` — M3+ briefs are written after M2's outcome)
**Commits:** brief drafted in-repo; `M3: first real detector — Codex detected via ShellEnvironment with npm classification and local version`
**Live at:** [github.com/Hazem-Samak/agent-lens](https://github.com/Hazem-Samak/agent-lens)

---

## What this milestone was for

First real integration with the machine. Until M3, `agent-lens scan` printed one hardcoded tool (M1). Now it detects the tool **for real**: is it installed, where the executable actually lives (symlinks resolved), which package manager owns it, and which version is installed locally. Still no detector schema (M4), no latest-version probing (M6), no extra tools (O-004).

## What was built

| File | Purpose |
|---|---|
| `Sources/AgentLensCore/Detection/ToolDetector.swift` | One tool, real detection. Searches `ShellEnvironment.pathEntries` for the executable, then configured extra roots (making `installedNotOnPath` reachable, D-006). Resolves symlinks to the real path. Classifies source **by the resolved target** (`/lib/node_modules/` → `npm`, `/Cellar/` → `brew`, else `standalone`) — mechanism wins even when the shim catalog looks like brew (D-004). Runs `--version` locally with a 3s timeout; the version query is injectable so unit tests never touch the real machine. Execution environment comes from `ShellEnvironment.raw` — never the inherited one (M2 req. 7 stays binding). |
| `Sources/AgentLensCore/Detection/ScanRenderer.swift` | Report rendering: `✓` on-path, `!` … `(not on PATH)`, `–` not installed; unknown version renders as `–` (D-007). Also hosts `CoreDetectors.codex` — the single hardcoded fixture detector (by design until M4). |
| `Sources/agent-lens/main.swift` | `scan` now renders real detection. Dispatch structure unchanged from M1. Usage text now lists both commands: `agent-lens <scan|debug-env>`. |
| `Sources/AgentLensCore/Environment/ShellEnvironmentResolver.swift` | Only addition: a public memberwise initialiser on `ShellEnvironment` so tests can inject synthetic environments. M2 logic untouched. |
| `Tests/AgentLensCoreTests/ToolDetectorTests.swift` | 8 new tests: all three tri-states, npm classification via a real symlink chain, brew classification, version-token shapes (`codex-cli 0.162.1`, `v1.2.3`, `1.0.0-beta.2 (build 7)`), a hanging `--version` timed out to "unknown", renderer shapes. |
| `Tests/AgentLensCoreTests/AgentLensCoreTests.swift` | One test updated: the M1 exact-string usage assertion now also expects `debug-env`, the documented M3 usage change. |

M1's `WalkingSkeleton` code and tests untouched — the fixture still proves the harness (D-012).

## Part 1 pre-flight (recorded in the brief before implementation)

```
$ command -v codex
/Users/corvette/.local/bin/codex
$ ls -l /Users/corvette/.local/bin/codex
lrwxr-xr-x@ ... codex -> ../lib/node_modules/@openai/codex/bin/codex.js
$ codex --version
codex-cli 0.162.1
```

Notable: the M1 walking skeleton's hardcoded fixture said Codex was `0.154.0`. The tool has since updated itself — the real install is `0.162.1`. A hardcoded list rots; a detector doesn't. That's the best possible advertisement for this milestone.

## Acceptance 1 — build

```
$ swift build
Build complete! (0.81 secs)
exit code: 0
```

## Acceptance 2 — the version cross-check (diff, not eyeball)

```
$ .build/debug/agent-lens scan | grep 'Codex' | grep -o '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*' > /tmp/agentlens_ver.txt
$ codex --version | grep -o '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*' > /tmp/shell_ver.txt
$ diff /tmp/agentlens_ver.txt /tmp/shell_ver.txt && echo "VERSION MATCH"
VERSION MATCH
```

Same discipline as M2's PATH `diff`: the version the CLI reports is byte-identical to what the real binary says. Not "close" — identical.

## Acceptance 3 — source classification proven against reality

```
$ .build/debug/agent-lens scan | grep 'Codex' | grep 'npm'
✓ Codex          0.162.1    npm
$ python3 -c "import os; print(os.path.realpath('$(command -v codex)'))" | grep 'lib/node_modules/'
/Users/corvette/.local/lib/node_modules/@openai/codex/bin/codex.js
exit code: 0
```

Report says `npm`; the resolved symlink target proves `npm ownership → ~/.local/lib/node_modules/`. The shim lives in `~/.local/bin`, but classification followed the *resolved* path — the brief's rule 3, tested.

## Acceptance 4 — the real scan output

```
$ swift run agent-lens scan
AI AGENTS                         1

✓ Codex          0.162.1    npm

scan exit: 0
```

## Acceptance 5 — tests

```
$ swift test
✔ Test buildEnvironmentPassesRawEnvironmentThroughForProcess() passed
✔ Test parseEnvironmentDumpExtractsSentinelDelimitedPairs() passed
✔ Test versionTokenExtractionHandlesKnownOutputShapes() passed
✔ Test detectorReportsNotInstalledWhenNothingFound() passed
✔ Test detectorFindsExecutableOnPath() passed
✔ Test detectorClassifiesCellarAsBrew() passed
✔ Test detectorUsesExtraRootsForInstalledNotOnPath() passed
✔ Test detectorClassifiesNpmByResolvedSymbolicLinkTarget() passed
✔ Test captureParsesASuccessfulRealShellRun() passed
✔ Test versionQueryTimesOutAgainstHangingBinary() passed (0.270s)
✔ Test captureTimesOutAgainstAHangingShell() passed (0.505s)
✔ Test run with 18 tests in 0 suites passed after 0.506 seconds.
exit code: 0
```

(All 18 listed in the raw transcript; M0–M2 tests all still green.)

## Failures found and fixed (honest log)

Tests did their job here — two failures surfaced, both fixed at the cause:

1. **Regex bug caught by test.** `extractVersionToken(from: "mytool 1.0.0-beta.2 (build 7)")` returned `1.0.0-beta` — the suffix class didn't include the dot in prerelease suffixes (`-beta.2`). Fixed the regex to `[0-9]+(\.[0-9]+){1,3}(-[0-9A-Za-z.]+)?`; all three shape assertions now pass. *This is exactly the class of subtle bug the briefs warn about — caught in a test, not in production output.*
2. **Stale M1 assertion.** `unknownCommandHasNonZeroSemanticsViaUsageText` asserted the exact M1 usage string. The usage text intentionally gained `debug-env` in M2/M3; the assertion was updated to check both commands while keeping the original intent (no-arg and unknown command share the usage message; unknown still exits non-zero).
3. **Environmental flake, not a code issue:** one `swift test` run failed with `external macro implementation 'TestingMacros' could not be found` — a stale incremental-build artifact from Swift Testing's macro plugin. It cleared on rebuild with zero code changes; noted for the record so a future reader doesn't chase a ghost.

## Done-when checklist

- [x] `swift build` exits 0
- [x] `agent-lens scan` exits 0; version equals `codex --version` — `VERSION MATCH`
- [x] Source proven `npm` against the real symlink resolution
- [x] Tri-state unit tests via injected roots
- [x] Source classification unit tests (node_modules → npm; Cellar → brew; else standalone)
- [x] Version extraction shapes + hanging-binary timeout to "unknown"
- [x] Renderer: dash for unknown version, `(not on PATH)` suffix, `–` row
- [x] M0–M2 tests still green; `swift test` 18/18
- [x] Raw transcripts above
- [x] One commit on the milestone branch

## What changes next (M4 — detector schema + 3–5 tools)

Per the plan, M4 turns the single hardcoded detector into a **versioned, data-driven registry** (D-010) and settles O-003 (YAML vs JSON) and O-004 (which tools). The brief will need a real decision from you on the format — that's an open question the milestone exists to close. This is also where `installedNotOnPath` adults from one configured root list to per-detector declared search cards.
