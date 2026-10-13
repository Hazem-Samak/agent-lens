# M3 — One real detector

> **Hand this to the orchestrator.** Acceptance is judged by the orchestrator, not the implementer (D-014).
> Read `briefs/README.md` first for the rules that apply to every brief.
>
> Underlying plan: M3 onward are written after M2's outcome. M2 passed with a byte-exact `diff MATCH`, so M3 is built on the now-proven `ShellEnvironment` resolution.
>
> **Model assignment (§29.6):** strongest reasoning model — first real integration with the machine.

---

## Goal

`agent-lens scan` detects **one real tool** (Codex) on the machine, using the login-shell environment resolved in M2, and reports where it came from and which version is installed.

**No detector schema yet** (that is M4 / O-003). No latest-version probing (M6 / D-007). No additional tools (O-004 full set at M4). The one-tool definition may be hardcoded in code for this milestone.

---

## Part 1 — The builder does this (not an agent)

Pre-verified while drafting this brief (2026-10-13):

```bash
$ command -v codex
/Users/corvette/.local/bin/codex           # symlink -> ../lib/node_modules/@openai/codex/bin/codex.js
$ codex --version
codex-cli 0.162.1
```

If `command -v codex` stops finding it, the milestone acceptance changes shape — see "If it fails".

---

## Requirements

1. Discovery consults **only** `ShellEnvironment` from M2 — its `pathEntries` for search, its `raw` as the `Process.environment` for execution. **No `ProcessInfo.processInfo.environment["PATH"]`** (M2 req. 7 carries forward; keep the binding comment true).
2. Resolve symlinks: the report shows the **real path** of the executable (`codex.js`, not the shim).
3. Installation source is classified by the *resolved* path, per D-004 (detect mechanism, never reimplement):
   - resolved path contains `/lib/node_modules/` → `npm`
   - resolved path contains `/Cellar/` or a Homebrew tree → `brew`
   - otherwise → `standalone`
4. Installation state is tri-state (D-006). `installedNotOnPath` is real functionality, not a string:
   - executable found on a `pathEntries` root → `installedAndOnPath`
   - not on PATH, but found in a configured list of extra search roots (for the fixture tool: `~/.local/bin`) → `installedNotOnPath`
   - neither → `notInstalled`
5. Installed version is obtained **locally** (D-007): run the found executable with `--version` (3-second timeout, kill on timeout) and extract the first version token (e.g. `0.162.1` from `codex-cli 0.162.1`; strip a leading `v`). On failure or timeout: version is unknown and renders as `–` (dash). It is never an error and never fabricated.
6. Executable selection uses `FileManager.isExecutableFile`. Version query may fail; detection must not.

### Required output format

`agent-lens scan` keeps the M1 report shape, now populated from real detection (one fixture tool for this milestone):

```
AI AGENTS                         1

✓ Codex          0.162.1    npm
```

- `AI AGENTS` header and tool count remain.
- Row marker by state: `✓` `installedAndOnPath`, `!` `installedNotOnPath` (with ` (not on PATH)` appended), `–` `notInstalled` (version and source columns render as `–`).
- Unknown version renders as `–` in the version column.

### CLI dispatch (extends M1)

- `agent-lens scan` → real single-tool report, exit 0
- `agent-lens debug-env` → unchanged (M2)
- no argument or unknown command → unchanged (M1: usage; unknown exits non-zero)

---

## Files

Allowed to create or modify:

- `Sources/AgentLensCore/Detection/` — new directory, new files as needed
- `Sources/AgentLensCore/Tests` mirror in `Tests/AgentLensCoreTests/` — new test files as needed
- `Sources/agent-lens/main.swift` — dispatch change only

## DO NOT TOUCH

- `AGENT_LENS_SCOPE.md`, `DECISIONS.md`, `briefs/` — read-only reference
- `Package.swift` — no dependencies, ever
- `Sources/AgentLensCore/AgentLensCore.swift` and the `WalkingSkeleton` code — M1 artifact, its tests must stay green untouched
- `Sources/AgentLensCore/Environment/` — M2 artifact; consume it, don't edit it (except, if strictly needed, adding a public memberwise-style initialiser that M2's own tests still pass)

And do not write, in this milestone:

- Any detector beyond the one fixture tool
- Any detector schema / registry (M4, O-003)
- Any latest-version or network probing (M6, D-007)
- Any UI or SwiftUI code
- Any modification of the M2 resolution logic

---

## Acceptance

Run in Terminal, from the project folder. Deep-build first.

```bash
swift build
echo "exit code: $?"
```

**Required:** exit 0.

Then the version cross-check — the report's version token must equal what the real binary says, judged by `diff`, never by eye:

```bash
.build/debug/agent-lens scan | grep 'Codex' | grep -o '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*' > /tmp/agentlens_ver.txt
codex --version | grep -o '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*' > /tmp/shell_ver.txt
diff /tmp/agentlens_ver.txt /tmp/shell_ver.txt && echo "VERSION MATCH"
```

**Required:** `VERSION MATCH` printed, exit 0.

Source cross-check — the report must say `npm` iff the real executable's resolved path is npm-managed:

```bash
.build/debug/agent-lens scan | grep 'Codex' | grep 'npm'
python3 -c "import os; print(os.path.realpath('$(command -v codex)'))" | grep 'lib/node_modules/'
echo "exit code: $?"
```

**Required:** exit 0 — both lines present (report says npm; real path proves npm ownership).

And full test:

```bash
swift test
echo "exit code: $?"
```

**Required:** exit 0, with M0–M2 tests still green and new M3 tests passing.

## Evidence required

Raw, unedited terminal output of all four blocks in the walkthrough. No summaries, no "it works".

## Done when

- [ ] `swift build` exits 0
- [ ] `agent-lens scan` exits 0 and its version equals `codex --version` (diff-verified `VERSION MATCH`)
- [ ] Source classification proven against the real symlink target (`npm`)
- [ ] Unit test: notInstalled / installedAndOnPath / installedNotOnPath via injected roots
- [ ] Unit test: source classification (node_modules → npm; Cellar → brew; else standalone)
- [ ] Unit test: version extraction incl. `v`-prefix; and a hanging `--version` times out to unknown
- [ ] Unit test: unknown version renders as `–`, `installedNotOnPath` row carries ` (not on PATH)`
- [ ] All M0–M2 tests still pass; `swift test` exits 0
- [ ] Raw transcripts attached in the walkthrough
- [ ] One commit on the milestone branch

---

## If it fails

| Symptom | Likely cause |
|---|---|
| `codex` reported notInstalled | PATH search not using `ShellEnvironment.pathEntries`, or isExecutableFile rejects a symlink |
| Version blank but binary works | Version query: wrong executable invoked, no timeout/kill, or token regex misses `codex-cli 0.162.1` shape |
| Report says `brew` | Classification checked the shim's directory, not the *resolved* target |
| `installedNotOnPath` never reachable | Extra search roots not consulted, or `~` not expanded |
| M0–M2 tests break | WalkingSkeleton or Environment file was touched against the DO-NOT-TOUCH list |
| `command -v codex` empty at Part 1 | Fixture tool was uninstalled mid-project; stop and re-brief with a different fixture tool — do not silently change acceptance |
