# M1 — Walking skeleton

> **Hand this to the orchestrator.** The orchestrator may narrow it before passing it to the implementer.
> Acceptance is judged by the orchestrator, not the implementer (D-014).
> Read `briefs/README.md` first for the rules that apply to every brief.

---

## Goal

`agent-lens scan` prints **one hardcoded tool**. No real detection.

**Purpose:** prove the entire path — repository → build → run → observable output → test — before any real logic exists. If something is structurally wrong with the project, this milestone finds it cheaply.

**Flash-tier implementer is acceptable for this milestone** (§29.6) — it is low-ambiguity scaffolding.

---

## Files

Allowed to create or modify:

- `Sources/agent-lens/main.swift`
- `Sources/AgentLensCore/Models/` — new files as needed
- `Sources/AgentLensCore/AgentLensCore.swift`
- `Tests/AgentLensCoreTests/` — new test files as needed

---

## DO NOT TOUCH

- `AGENT_LENS_SCOPE.md`, `DECISIONS.md`, `briefs/` — read-only reference
- `Package.swift` — do not add dependencies. There must be none.

And do not write, in this milestone:

- Any filesystem scanning
- Any process execution or `Process` usage
- Any network calls
- Any detectors
- Any UI or SwiftUI code
- Any code that looks at the real machine

**The output is hardcoded.** Do not attempt to detect anything real.

---

## Required behaviour

Running `agent-lens scan` prints a short report containing one tool. The values are literals in the source.

Shape of the output (formatting may vary; the content may not):

```
AI AGENTS                         1

✓ Codex          0.154.0    npm
```

### The command must be dispatched by argument

- `agent-lens scan` → prints the report, exits 0
- `agent-lens` with no argument → prints a one-line usage message, exits 0
- `agent-lens <anything else>` → prints the usage message, exits **non-zero**

The third case matters: it establishes that the command dispatch is real and not a hardcoded print.

---

## Acceptance

Run in Terminal, from the project folder:

```bash
swift run agent-lens scan
echo "exit code: $?"
```

**Required:**
- `exit code: 0`
- stdout contains the literal text `AI AGENTS`
- stdout contains `Codex`
- stdout contains `0.154.0`
- stdout contains `npm`

```bash
swift run agent-lens bogus-command
echo "exit code: $?"
```

**Required:** `exit code:` is **not** 0.

```bash
swift test
echo "exit code: $?"
```

**Required:** `exit code: 0`

---

## Evidence required

Paste the **raw, unedited** terminal output of all three commands.

Do not summarise. Do not write "it works".

---

## Done when

- [ ] `swift run agent-lens scan` exits 0 and the output contains all four required strings
- [ ] `swift run agent-lens bogus-command` exits non-zero
- [ ] A test exists in `Tests/AgentLensCoreTests/` that asserts the scan output contains `AI AGENTS`, `Codex`, `0.154.0`, and `npm`
- [ ] `swift test` exits 0
- [ ] Raw transcripts of all three commands are attached
- [ ] One commit on the milestone branch

---

## Why the test matters here

The test is nearly circular — it asserts that hardcoded output contains hardcoded strings. That is fine. **The test is not the point; the test harness is the point.**

From M2 onward, the tests stop being circular and become the only way to tell working code from plausible-looking code (D-012). Establishing the harness now, while the stakes are zero, is what makes that possible later.

---

## If it fails

| Symptom | Likely cause |
|---|---|
| `error: no such module 'AgentLensCore'` | The executable target is missing its dependency in `Package.swift` |
| Usage message printed for `scan` | Argument matching is off — check `CommandLine.arguments` handling (index 1 is the subcommand) |
| `bogus-command` exits 0 | The exit code is not being propagated — use `exit(1)` explicitly |
| Test target not found | `AgentLensCoreTests` missing from `Package.swift`, or the test file is in the wrong directory |
