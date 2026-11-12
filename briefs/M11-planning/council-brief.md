# M11 Planning Council — shared task brief

Date: 2026-11-12. Orchestrator/main judge: Qoder (Herdr terminal `t7x`).
Council members plan **independently**; the orchestrator judges, reconciles, and freezes the final plan.

## 1. Context

Agent Lens is a native Swift 6 / SwiftUI macOS app that diagnoses AI CLI installations
(which copy PATH runs, duplicates, versions, ownership) and delegates Update/Uninstall to
package managers. Milestones M0–M10 are delivered to `main` (PR #1 merge `65f7a82`;
current `main` head `d0a2b417e8c7d05f3c715a24e93f17851f7ab904`). The detector registry is
data-driven JSON (schemaVersion 2) and currently covers only Codex, OpenCode, and Grok CLI.

The next milestone is **M11 — original catalogue and contributor foundation**
(ROADMAP.md §4). Its user result: the app detects the originally named families instead of
only three tools. Target catalogue (14 entries):

| Category (scope §2) | Tools |
|---|---|
| AI Agents | Codex, Claude Code, Gemini CLI, OpenCode, Hermes, Cline CLI |
| AI Coding Tools | Aider, Goose, Kiro CLI, Qoder |
| AI Harnesses | DSH, OMP, AGY |
| (already delivered) | Grok CLI |

M11 is detection + contributor foundation only. Manager mutation adapters for Homebrew/uv/Cargo
are M13–M15; the complete native workflow is M12. New entries without a delivered adapter must
remain informational or disabled with a truthful reason.

After the council, the orchestrator freezes one plan and commits it. The owner then approves
scope and names the implementer and independent reviewers. Your proposal must therefore be
implementer-agnostic, bounded, and ready to be split into dispatch briefs.

## 2. Required reading (in this order)

1. `ROADMAP.md` — §2 finish line, §4 M11 (and M12 for the boundary), §5 operating protocol,
   §6 architecture/safety invariants, §7 owner gates, §8 next action.
2. `DECISIONS.md` — all settled decisions D-001…D-020. Do not re-litigate settled decisions.
3. `AGENT_LENS_SCOPE.md` — §2 categories, §11 catalogue, §17 detectors, §27 architecture,
   §29 operating protocol (read selectively; the file is large).
4. `briefs/README.md` — brief rules (one branch per milestone, read-only reviewers,
   orchestrator runs acceptance, DO NOT TOUCH is binding).
5. `Sources/AgentLensCore/Detectors/DefaultDetectors.json` — the current registry shape.
6. `Tests/AgentLensCoreTests/DetectorRegistryTests.swift`, `DetectorMetadataTests.swift`,
   `ToolDetectorTests.swift` — how detectors are validated and fixtured today.
7. One recent brief for format calibration: `briefs/M9-A-detector-metadata.md`.

## 3. Your task

Write an independent M11 delivery plan proposal to **your assigned output file** (given in the
dispatch message). It must cover, with concrete specifics rather than generalities:

### A. Phase decomposition
Split M11 into bounded, sequential phases on ONE milestone branch (suggested naming
`M11-A`, `M11-B`, …; you choose the split). For each phase give:
- observable goal and explicit non-goals;
- scope sketch: exact files/directories the implementer would touch, and protected files;
- acceptance outline: exact commands where possible, expected observable results, evidence format;
- dependencies and stop conditions;
- recommended model tier per scope §29.6 (ambiguity → strongest reasoning; volume → flash tier).
Phases must be small enough for one implementer dispatch each. Research/identity resolution
should be its own bounded phase, not silently folded into coding phases.

### B. Catalogue identity research (preliminary, primary-source)
For each of the 14 tools, establish from **primary documentation** (vendor docs, official
repos, official package listings): project/vendor, executable name(s), package identity per
install manager (npm name, Homebrew formula/cask, uv/pip name, cargo crate, standalone layout),
official installation layout(s), version-query behavior (`--version` shape), and category.
- Cite a source URL for every claim.
- Mark each fact: `verified-docs` (primary source), `observed-local` (measured read-only on this
  machine), or `unverified` (could not confirm).
- You MAY inspect this machine read-only (`command -v`, `--version`, reading package metadata,
  `ls` of install roots). Record what you actually observed. NEVER install, update, uninstall,
  or mutate anything; never run managers' mutating subcommands.
- **DSH and AGY are named research blockers** (ROADMAP §4 M11). Do not guess their identity.
  State precisely what is ambiguous and what question the owner must answer to unblock them.
- Hermes, Kiro CLI, and any other ambiguous name get the same honest treatment if primary
  sources conflict or are missing.
- Note which tools are already covered (Codex, OpenCode, Grok CLI) and what M11 must add or
  correct for them (e.g. categories, links, additional install layouts).

### C. Capability matrix
Design the published matrix required by ROADMAP M11: tool, category, tested layouts,
latest-check support, Update/Uninstall support, known limits. Where does it live (file format,
location), how is it generated/kept truthful, and how are informational-only entries marked?

### D. Contributor foundation
What documentation and validation must exist so a new tool using an existing layout can be
contributed via registry/fixtures without scanner or UI source changes (M11 acceptance)?
Include the license gate: owner must choose MIT or Apache-2.0 before public contribution
invitations (no later than M18). Give a short tradeoff summary and a recommendation, but the
choice remains the owner's.

### E. Acceptance strategy
Per-phase gates plus the combined M11 gate. Cover: validated fixture per named entry, measured
version behavior where available, CLI/app fact agreement, data-only contribution proof,
schema-validation CI behavior, and the existing hosted gates. State explicitly what is NOT an
acceptance target (personal installations, unobserved real layouts labeled verified, mutation
adapters, M12 UI work).

### F. Risks and open questions
Ranked risks (identity ambiguity, name collisions, layout drift, fixture realism, scope creep)
and a numbered list of decisions only the owner can make. Include anything you could not
resolve and why.

### G. Explicit non-goals
No new manager mutation adapters, no M12 UI/workflow work, no speculative scanner refactors,
no per-tool bespoke shell scripts, no license choice made on the owner's behalf.

## 4. Hard constraints

- **Read-only on the product.** Do not edit anything under `Sources/`, `Tests/`, `scripts/`,
  `Resources/`, `Package.swift`, `.github/`, or any existing brief/walkthrough. Do not run
  git commands that mutate state (no commit/branch/checkout/stash/reset/push). No installs.
- **Do not start subagents or other CLIs.** You are one council member.
- **Do not read the other member's proposal.** Independence is the point.
- The ONLY file you may write is your assigned proposal path under `briefs/M11-planning/`.
- Never fabricate package names, layouts, or version behavior. `unverified` is an acceptable
  and expected answer; a confident guess is not.
- If you are blocked (missing access, ambiguous instruction, tool failure), stop and report
  the blocker instead of improvising.

## 5. Reporting

When done — or stuck — report to the orchestrator:

```sh
hc send t7x "M11 proposal complete: briefs/M11-planning/<your-file>.md — <3-line summary: phase count, resolved tools, open blockers>"
```

Write the full proposal to the file; the message is only a pointer and summary.

## 6. How the judge will weigh proposals

1. Truthfulness and evidence quality (cited primary sources; honest unknowns).
2. Phase boundedness and dispatch-readiness (one writer, clear allow-lists, measurable gates).
3. Fidelity to settled decisions and safety invariants (DECISIONS.md, ROADMAP §6).
4. Contributor scalability (data-only additions, schema gates, docs).
5. Clear separation of owner decisions from technical recommendations.