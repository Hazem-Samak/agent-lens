# Walkthrough — M4: Detector schema + registry (3 tools)

**Date:** 2026-10-13
**Brief:** `briefs/M4-detector-registry.md`
**Decisions applied:** D-017 (schema format: **JSON**, chosen by the builder's delegation) and D-018 (first set: **Codex, OpenCode, Grok CLI**), both recorded in `DECISIONS.md` before implementation
**Commits:** `M4: data-driven detector registry — versioned JSON, strict validation, three tools` → `M4: walkthrough and milestone log entry`
**Live at:** [github.com/Hazem-Samak/agent-lens](https://github.com/Hazem-Samak/agent-lens)

---

## What this milestone was for

Deliver D-010 in full: detectors are now **declarative data**, not Swift code. The one hardcoded M3 detector became a **versioned JSON registry** (`schemaVersion: 1`) with strict validation and per-detector fixture tests. Scan now covers 3 real tools — and a 4th can be added by editing one JSON file (proven live below).

## What was built

| File | Purpose |
|---|---|
| `Sources/AgentLensCore/Detectors/DefaultDetectors.json` | The registry: schemaVersion 1, three D-018 tools with ids, roots, and per-detector fixture definitions. Bundled into `AgentLensCore` via SwiftPM `.copy` (a resource **declaration**, not a dependency — Package.swift remains at zero external packages). |
| `Sources/AgentLensCore/Detection/DetectorRegistry.swift` | Strict, fail-closed validation (M4 req. 3): schemaVersion present and equal to 1; non-empty `id` / `displayName` / `executableName`; unique ids; fixture layout and expectedSource both from known sets. Any violation throws a **named** error (`.duplicateId("x")`, `.unknownLayout(...)`, etc.). Cases are auto-generated for scan diagnostics: - missingSchemaVersion / unsupportedSchemaVersion - missingField / emptyField, with detector index or id - duplicateId - unknownLayout / unknownExpectedSource - badJSON (wrapped underlying cause) - noDetectors. The CLI prints it on stderr and exits non-zero — a broken registry is loud, never a silently reduced scan. |
| `Sources/AgentLensCore/Detection/ToolDetector.swift` + `ScanRenderer.swift` | `DetectorDefinition.makeDetector()` bridges data → runtime. `CoreDetectors` (the M3 hardcoded tool) removed — the registry is the single source of truth. |
| `Sources/agent-lens/main.swift` | `scan` iterates the whole registry in file order; do/catch fails loud. |
| `Tests/AgentLensCoreTests/DetectorRegistryTests.swift` | 4 new tests: bundled file validates with exactly the three D-018 tools; **9 schema-violation cases** each rejected with the named error incl. duplicate id and JSON root non-object; **per-detector fixture tests** that build each tool's declared layout (npmGlobal, singleDirectory, brewCellar) synthetically and prove classification matches `expectedSource`; and D-010's promise as a test. |

## Acceptance — raw results

**1. Build:**
```
$ swift build
Build complete! (0.88 secs)
```

**2. Real scan of three tools:**
```
$ .build/debug/agent-lens scan
AI AGENTS                         3

✓ Codex          0.162.1    npm
✓ OpenCode          2.0.28    standalone
✓ Grok CLI          1.0.52    standalone

scan exit: 0
```

**3. Version cross-checks, diff-judged per tool (row-filtered):**
```
codex:    0.162.1 vs 0.162.1    MATCH
opencode: 2.0.28  vs 2.0.28     MATCH
grok:     1.0.52  vs 1.0.52     MATCH
```
(The `v` in `opencode v2.0.28` is stripped by the M3 token rule; grok's trailing `(0920c8169e27)` build hash is not swallowed.)

**4. Structural evidence — D-010 demonstrated live:** appended a `node` detector to the JSON **only** (no source edits), rebuilt, scanned:
```
appended node; count: 4
Build complete! (1.02 secs)
AI AGENTS                         4

✓ Codex          0.162.1    npm
✓ OpenCode          2.0.28    standalone
✓ Grok CLI          1.0.52    standalone
✓ Node.js          22.23.2    standalone

evidence exit: 0
```
then reverted the file and confirmed `scan` is back to `AI AGENTS 3` with **0 modified files** in the tree. The tree ships exactly D-018's three tools.

**5. Tests:**
```
$ swift test
...
✔ Test bundledDefaultDetectorsIsValidWithThreeTools() passed
✔ Test schemaViolationsAreRejectedLoudly() passed
✔ Test bundledFixtureDefinitionsMatchSyntheticLayouts() passed
✔ Test addingAFourthDefinitionRequiresNoSourceChanges() passed
...
✔ Test run with 22 tests in 0 suites passed after 0.509 seconds.
test exit: 0
```

## Failures found and fixed (honest log)

1. **My acceptance command had a grep trap — caught by the diff itself.** The per-tool version loop filtered versions from the **whole scan report**, so every `/tmp/al_$t.txt` contained all three tools' tokens and every diff failed. The detector was right; the *check* was wrong. Corrected to filter the tool's own row first (`grep "$name" |`), recorded, and the brief's acceptance block was fixed to match so nobody re-steps on it.
2. **Registry validation hole caught while reviewing my own code:** the first draft's helper fabricated an error-name for a missing `id` (like `"(missing id, detector #0)"`) but never actually threw — a detector without an id would have been silently accepted. Fixed: missing/empty `id` now throws `.missingField`/`.emptyField`, failing closed.
3. **First `DetectorRegistry.swift` draft had placeholder scaffolding** (a compile-breaking `private extension`). Replaced whole-file rather than patched patchwork.
4. **Two Swift Testing API mismatches in the new test:** `#expect` takes no `file:`/`line:` arguments (macro-constrained), and an IIFE inferred `nil` without a contextual type. Rewritten with a plain `do/catch` and a typed local.
5. **The TestingMacros plugin flake recurred twice on test reloads** (same known environmental stale-build issue from M3); cleared both times by `swift package reset` with zero code changes. Verified again in the final clean rerun.

## Done-when checklist

- [x] Registry JSON in place, schemaVersion 1, the three D-018 tools
- [x] `scan` shows `AI AGENTS 3` and three rows; per-tool version diffs clean (row-filtered)
- [x] Synthetic fixture tests pass for all three declared layouts
- [x] Schema-violating JSON rejected with named errors (9 cases tested)
- [x] `CoreDetectors` removed; 4th-tool data-only addition proven live, then reverted (0 modified files)
- [x] `swift test` exits 0 (22 tests); M0–M3 still green
- [x] Raw transcripts above
- [x] One commit on the milestone branch

## What changes next (M5 — duplicate/PATH diagnostics)

Per the plan, M5 is the product's differentiator (strongest-model assignment, per `briefs/README.md`): **which copy of a tool actually wins** when multiple exist — duplicate detection across PATH entries with ordering context (D-015), plus `installedNotOnPath` fact-checking against configurations rather than a single declared root list. The registry format added here (per-tool declarative data) is the vehicle: duplicate diagnostics will hang off per-tool metadata, not more hardcoded lists.
