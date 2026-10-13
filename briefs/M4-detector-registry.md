# M4 — Detector schema + registry (3 tools)

> **Hand this to the orchestrator.** Acceptance is judged by the orchestrator, not the implementer (D-014).
> Read `briefs/README.md` first. Underlying plan: M4 settles O-003 and O-004 — both now recorded as **D-017** (JSON) and **D-018** (Codex, OpenCode, Grok CLI) in `DECISIONS.md`.
>
> **Model assignment (§29.6):** flash-tier acceptable for volume; schema-validation design needs care.

---

## Goal

The detector definitions move out of Swift code into a **versioned JSON registry file**, and `agent-lens scan` covers **3 real tools** (D-010, D-017, D-018). Adding a 4th tool afterwards must require **zero source changes** — editing the JSON is all.

No latest-version probing (M6, D-007). No duplicate/PATH diagnostics beyond the tri-state (M5). No UI (M7).

---

## Part 1 — The builder does this (not an agent)

Pre-verified while drafting (2026-10-13):

```
$ command -v codex     ~/.local/bin/codex        ->  ../lib/node_modules/@openai/codex/bin/codex.js    codex-cli 0.162.1    [npm]
$ command -v opencode  ~/.opencode/bin/opencode  (real binary, no symlink)                             opencode v2.0.28     [standalone]
$ command -v grok      ~/.grok/bin/grok          ->  ../downloads/grok-1.0.52-macos-aarch64            grok 1.0.52 (0920c8169e27) [stable]  [standalone]
```

All three on the login-shell PATH. Facts recorded in D-018.

---

## Requirements

### The registry file (D-010, D-017)

1. Created: `Sources/AgentLensCore/Detectors/DefaultDetectors.json`, bundled into the `AgentLensCore` target via SwiftPM `.copy` resource (a **resource declaration, not a dependency** — Package.swift stays at zero external packages).
2. Shape (schema version 1):

   ```json
   {
     "schemaVersion": 1,
     "detectors": [
       {
         "id": "codex",
         "displayName": "Codex",
         "executableName": "codex",
         "extraSearchRoots": ["~/.local/bin"],
         "fixture": { "layout": "npmGlobal", "expectedSource": "npm" }
       },
       {
         "id": "opencode",
         "displayName": "OpenCode",
         "executableName": "opencode",
         "extraSearchRoots": ["~/.opencode/bin"],
         "fixture": { "layout": "singleDirectory", "expectedSource": "standalone" }
       },
       {
         "id": "grok",
         "displayName": "Grok CLI",
         "executableName": "grok",
         "extraSearchRoots": ["~/.grok/bin"],
         "fixture": { "layout": "singleDirectory", "expectedSource": "standalone" }
       }
     ]
   }
   ```

3. Registry validation is **strict** (fail closed, never guess):
   - `schemaVersion` present and equal to `1`
   - every detector has non-empty `id`, `displayName`, `executableName`
   - `id`s unique across the file
   - `fixture.layout` ∈ {`npmGlobal`, `singleDirectory`, `brewCellar`}; `fixture.expectedSource` ∈ {`npm`, `brew`, `standalone`}
   - any violation → throw with a message naming the offending detector; the CLI prints it on **stderr** and exits non-zero. No silent skipping.

### The registry types

4. `DetectorDefinition` (Codable) ≅ the per-tool entry; `DetectorRegistry.loadDefault()` reads the bundled JSON and validates; `DetectorRegistry.validate(data:)` is exposed pure for tests.
5. `ToolDetector` gains an initialiser from a `DetectorDefinition`. Its M3 behavior does not change; no modifications to Environment/ or WalkingSkeleton files are permitted.

### CLI

6. `agent-lens scan` iterates **all registry detectors in file order** and renders one row per tool (M3 renderer unchanged). The old hardcoded `CoreDetectors` disappears — the registry is the single source of truth for which tools exist.
7. Usage message gains nothing (still `usage: agent-lens <scan|debug-env>`).

### Fixture tests (D-010: "each with a fixture test")

8. For every detector in the registry, a test builds a synthetic install layout from its `fixture.layout`:
   - `npmGlobal`: `<root>/bin/<exe>` symlink → `<root>/lib/node_modules/<id>/bin/<exe>.js`
   - `singleDirectory`: `<root>/<exe>` real executable
   - `brewCellar`: `<root>/Cellar/<id>/1.0/bin/<exe>`
   then runs the actual `ToolDetector` against an injected `ShellEnvironment` with that fake root, and asserts the **state** and that `source == fixture.expectedSource`. These tests fail when either the fixture data or the classifier drifts — that is the point.

## Files

Allowed to create or modify:

- `Sources/AgentLensCore/Detectors/DefaultDetectors.json` — new
- `Sources/AgentLensCore/Detection/DetectorRegistry.swift` — new
- `Sources/AgentLensCore/Detection/ToolDetector.swift` — add definition-based initialiser
- `Sources/AgentLensCore/Detection/ScanRenderer.swift` — remove `CoreDetectors` only
- `Sources/agent-lens/main.swift` — scan reads registry
- `Package.swift` — **only** the `.copy` resource declaration
- `Tests/AgentLensCoreTests/DetectorRegistryTests.swift` — new

## DO NOT TOUCH

- `AGENT_LENS_SCOPE.md`, `DECISIONS.md`, `briefs/` — read-only reference
- `Sources/AgentLensCore/AgentLensCore.swift` (WalkingSkeleton), `Sources/AgentLensCore/Environment/`
- Any network / latest-version probing / UI
- `.github/`, CI configuration

---

## Acceptance

From the project folder:

```bash
swift build
echo "exit code: $?"
```

**Required:** exit 0.

```bash
swift run agent-lens scan
echo "exit code: $?"
```

**Required:** exit 0; output contains `AI AGENTS                         3` and rows for all three tools.

Version cross-check per tool — diff-judged, never eyeballed. The scan must be filtered to the tool's OWN row first, or the whole report's version tokens leak into every diff (this exact trap bit the first run and is recorded in the walkthrough):

```bash
names=(Codex OpenCode Grok); tools=(codex opencode grok)
for i in 0 1 2; do
  t=${tools[$i]}; n=${names[$i]}
  .build/debug/agent-lens scan | grep "$n" | grep -o '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*' > /tmp/al_$t.txt
  "$t" --version 2>/dev/null | grep -o '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*' | head -1 > /tmp/sh_$t.txt
  diff /tmp/al_$t.txt /tmp/sh_$t.txt >/dev/null && echo "$t: MATCH" || echo "$t: DIFF FAILED"
done
```

**Required:** no `DIFF FAILED` lines. (Note: the scan row contains one version token per tool — if scan reported a version the real binary does not, or vice versa, the diff catches it.)

```bash
swift test
echo "exit code: $?"
```

**Required:** exit 0; includes registry fixture tests for all three detectors, schema-validation tests, and all M0–M3 tests.

### Structural acceptance (D-010's promise, demonstrated)

```bash
git stash
# (do NOT run this in a real review — it only proves the point manually:)
# append a 4th detector to DefaultDetectors.json, rebuild, and scan picks it up with zero source edits
git stash pop
```

The record (a 4-toolDry run appending a definition and showing scan output before reverting) belongs in the walkthrough, not the tree. **Tree must end with the 3 detectors of D-018.**

---

## Done when

- [ ] Registry JSON in place with schemaVersion 1 and the three D-018 tools
- [ ] `scan` output shows `AI AGENTS 3` and the three rows; per-tool version diffs clean
- [ ] Per-detector synthetic fixture tests pass for all three layouts
- [ ] Schema-violating JSON (bad version, duplicate id, unknown fixture source, empty field) is rejected with named errors — covered by tests
- [ ] `CoreDetectors` removed; adding a tool in the JSON alone makes `scan` report it (one-off evidence run in the walkthrough)
- [ ] `swift test` exits 0; raw transcripts in the walkthrough
- [ ] One commit on the milestone branch

---

## If it fails

| Symptom | Likely cause |
|---|---|
| Scan shows fewer rows than tools | Registry load error is being swallowed — errors must fail loud, not skip |
| Version mismatch for opencode | The `v` prefix in `opencode v2.0.28` — token extraction rule from M3 must strip it |
| Version matches but grok's shows build hash | Token regex swallowing `(0920c8169e27)` — extraction takes only the `1.0.52` token |
| `Bundle.module` not found in tests | The `.copy` resource declaration missing or the file is in the wrong directory |
| Fixture tests fail on source | Classifier checked the shim directory instead of the resolved target (M3 rule 3) |
