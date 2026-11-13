# M12 — combined acceptance record: native diagnostic and operation workflow

**Date:** 2026-11-13. Orchestrator: Qoder (Herdr `t7x`). Milestone branch: `milestone/m12-workflow`.
**Accepted product candidate:** `a411661` ("feat(workflow): M12-F measurement + R2 hint fix") — the
only product change since the M12-E accepted base `775d5bc` is
`Sources/AgentLensApp/PathActions.swift` (the two-line hint fix). **Last code-bearing SHA:**
`e3e8c0538216ea5c2e17f002808bc1c4333c216b`, all seven hosted gates green (run 43433596183).
Subsequent commits on this branch are documentation-only.

**Decision: M12 is ACCEPTED.** The complete native diagnostic and operation workflow is finished.
Both mandatory independent reviews (MiniMax M3.1-Flash/xhigh; Grok 4.7/high) returned PASS with
zero blocking issues — the M8 keyboard-only Copy/Reveal gate and its R2 hint fix both closed; all
seven hosted CI gates are green at the final SHA; and the orchestrator independently reran the full
local gate set (D-014) with identical results. The branch is pushed and clean. PR creation and the
merge decision rest with the owner. **NOT MERGED.**

## Milestone goal (ROADMAP §4) vs achieved

| User result | Status |
|---|---|
| Overview, AI Agents, AI Coding Tools, AI Harnesses, Updates, Diagnostics, focused Settings make the catalogue understandable and manageable | Done (M12-A/B) |
| Category/update filters, counts, package/source details, conflict summary → per-installation PATH evidence/versions | Done (M12-A/C) |
| Complete npm confirmation/progress/output/result journey; future managers explicit unavailable | Done (M12-D) |
| Local-first launch, search, neutral unknowns, loading/empty/failure states, Copy/Reveal preserved | Done (all phases) |
| Native menus, keyboard navigation/shortcuts, VoiceOver labels/spoken checks, large text, narrow windows, light/dark | Done (M12-E/F) |
| Settings control only delivered features | Done (M12-E) |
| **Close the M8 keyboard-only Copy/Reveal measurement** | **CLOSED (M12-F)** |

## Phase-by-phase acceptance (A–F)

| Phase | Candidate | Reviews | Decision |
|---|---|---|---|
| M12-A presentation foundation | `64a5056` + R1 `2ed3a77` | MiniMax 0 blk/3 low/4 info PASS; Grok 0 blk/2 low/3 info PASS | **accepted** |
| M12-B seven-destination navigation shell | `ea08ad8` | orchestrator + native spot-check (App-only, R15) | **accepted** |
| M12-C conflict summary + Updates filter | `e66872d` | orchestrator + native spot-check (App-only, R15) | **accepted** |
| M12-D operation-journey completion (incl. C-1) | `6c1405a` | MiniMax 0 blk/1 low; Grok 0 blk — both PASS, C-1 SAFE | **accepted** |
| M12-E menus/a11y/layout | `5214d63` + R1 `407882b` | Initial: MiniMax CHANGES_REQUIRED 0 blk/2 med/1 low; Grok CHANGES_REQUIRED 0 blk/1 med/2 low. After R1: MiniMax PASS 0 blk/0 med/0 low/3 info; Grok PASS | **accepted** |
| M12-F M8 keyboard gate + measurement + R2 hint fix | `255fd9c` (R1) + `a411661` (R2) | R1: MiniMax 0 blk/1 low/4 info PASS, Grok 0 blk/1 low/3 info PASS. R2: MiniMax 0 blk/1 low/2 info PASS, Grok 0 blk/0 low/1 info PASS | **accepted** |

Combined independent reviews are at:

- M12-A: [minimax.md](M12-A-evidence/reviews/minimax.md), [grok.md](M12-A-evidence/reviews/grok.md)
- M12-B/C: orchestrator acceptance + native spot-check (App-only)
- M12-D: [minimax.md](M12-D-evidence/reviews/minimax.md), [grok.md](M12-D-evidence/reviews/grok.md)
- M12-E: [minimax.md](M12-E-evidence/reviews/minimax.md), [grok.md](M12-E-evidence/reviews/grok.md) (+ R1)
- M12-F R1 (sidebar): [minimax.md](M12-F-evidence/reviews/minimax.md), [grok.md](M12-F-evidence/reviews/grok.md)
- M12-F R2 (hint fix): [minimax-r2.md](M12-F-evidence/reviews/minimax-r2.md), [grok-r2.md](M12-F-evidence/reviews/grok-r2.md)

## Hosted CI gates — all seven green at final SHA

**Final SHA `e3e8c0538216ea5c2e17f002808bc1c4333c216b`** — run **43433596183**
(`push` → `refs/heads/milestone/m12-workflow`, event `push`), all seven gates green, aggregate
208.088s:

| Gate | Result | Detail |
|---|---|---|
| guard | passed | 0.182s |
| guard-fixtures | passed | 21 cases, 0 skipped |
| swift-build | passed | 27.244s |
| isolation-gate | passed | 1 case, 0 skipped |
| full-test-suite | passed | **586 cases** in 1 combined summary (85.490s), 0 skipped, no failure/issue events, all four anchors PASSED |
| build-dev-app | passed | 30.059s |
| packaging | passed | 9 cases, 0 skipped |

Previous candidate `c0aec94` — run **43421859618** (also `push`), all seven gates green, aggregate
200.983s, 586 cases, 0 skipped: guard, guard-fixtures 21, swift-build 35.772s, isolation-gate 1,
full-test-suite 586, build-dev-app 28.275s, packaging 9. Receipts verified per gate
(`producer_exit=0`, `verification_exit=0` throughout).

PR #3 CI (`pull_request` event) also ran green for the same content:
https://github.com/Hazem-Samak/agent-lens/pull/3.

Check-receipts artifacts (check-receipts) downloaded and verified for both runs: every `verification_exit=0`, every
producer exit `0`, no skip/issue/failure glyph events in the full-suite stream, anchor events
(`bundledDefaultDetectorsMatchFrozenCatalogue`, `unknownKeysAreRejectedAtRootDefinitionFixturePackageAndQueryLevels`,
`makeDetectorUsesRegistryArgumentsInTheProductionPath`, `productionWiringUsesOnlyTheCoreLoginShellSeams`)
all present and passing.

## Orchestrator gate rerun (D-014, independent, fresh scratch)

Fresh scratch `scratch-m12-d14`, `swift test --no-parallel` + CLT TestingMacros flag, HEAD
`c0aec94dd73042b8b6e2e95e1ef11255a8afebf1`:

- `swift build`: 24.91s, exit 0.
- Full suite: **467 Core + 119 AppSupport = 586 tests, zero skips/failures**, exit 0 (Core 467 after
  105.329s; AppSupport 119 after 16.344s).
- Core/UI import guard: 32 Core Swift files, no SwiftUI/AppKit imports. AppSupport guard: 6 files,
  no SwiftUI/AppKit imports.
- Guard behavioral fixtures: 21 OK. Packaging: 9 OK. Dev app built
  (`/tmp/m12-dev-app/AgentLensApp-debug.app`).
- `git diff --check`: exit 0; working tree clean.

## M8 keyboard-only gate (R10) — CLOSED on the disposable fixture

Real `CGEvent` Tab/Space + AX focus reads (full Keyboard Access `AppleKeyboardUIMode=3`; never
`AXPress`); disposable fixture only — no personal installation touched. `tab 1` = content scroll bar;
the four detail path buttons are Tab stops 2–5:

| Tab stop | Button | Space activation evidence |
|---|---|---|
| 2 | Copy Selected Entry path for Codex | clipboard byte-equal to `env/bin/codex`; SHA-256 `3c6b4be7…` = expected; clipboard restored |
| 3 | Reveal in Finder Selected Entry path for Codex | Finder selection = alias `codex` of folder `bin` of folder `env` (the symlink) |
| 4 | Copy Resolved Target path for Codex | clipboard byte-equal to the canonical target path; SHA-256 `f9cea9fd…`; clipboard restored |
| 5 | Reveal in Finder Resolved Target path for Codex | Finder selection = canonical target under `env/prefix/lib/node_modules/@openai/...` |

Category content-list Tab traversal: Tab leaves the list and reaches the four detail buttons plus
Verify (Tab stops 2–6). Fixture digest unchanged after measurement; clipboard clean before/after.
Evidence root: `$HOME/.hermes/cache/scratch/agent-lens-m12-f-measure/evidence/INDEX.md`.

**R2 hint fix (`a411661`, two lines, `PathActions.swift:74` / `85`):** `.help()` previously passed
the long action label, which masked `AXHelp`. Now `.help()` carries the R10-required hint text
("Copies the path text." / "Asks Finder to select this path.") while `.accessibilityHint`,
`.accessibilityLabel`, the visible `Label` titles, dispatch, eligibility, and feedback are untouched.
AX proof (`agent-lens-m12-f-r2/evidence/hint-fix-ax.log`): all four path buttons report the short
`help=` value. Both independent R2 reviews PASS (0 blocking/High/Medium; 1 low on MiniMax — visible
tooltip loses the tool/target distinction, which survives in the accessible name and row label —
0 low on Grok).

## Protected-tree audit

Diff vs M12-E accepted base `775d5bc`:

- **Product code:** `Sources/AgentLensApp/PathActions.swift` only (the hint fix).
- **CI floors (orchestrator commit 3212255):** `ci.yml` — AppSupport 80→119, total/combined
  547→586, Core floor unchanged at 467 (upward only, R12-compliant, in the orchestrator's own
  commit; implementer never edits `ci.yml`).
- **Docs/reviews/worker reports** (M12-A–F acceptance, measurement, implementation, R1/R2 reviews).
- Zero Core/CLI/registry/detector change; Core stays 467; no new dependencies; `Package.swift`
  untouched.

## Limitations (honest)

- **VoiceOver list row / Settings captions (PARTIAL):** with the VO cursor inside the app's
  scroll-area text, the caption panel emitted help/interact instructions rather than the row or
  Settings element label; no dedicated caption was obtained despite repeated attempts. AX evidence
  remains exact (row value `Codex, codex, Installed and on PATH, AI Agent, version 0.0.1`;
  Settings dump contains the read-only headings/statements).
- **Large text (environment limitation, not a pass):** `dynamicTypeSize(.accessibility5)` did not
  increase macOS semantic font sizes in the measurement environment; at 320pt width the safety
  sentence wraps to two lines with the full AX value intact (no truncation) — the wrap behavior is
  the measurement, not a proven scale pass.
- **App-layer automated tests:** App layer has no automated test surface (no App test target); the
  evidence model is static audit + real-keyboard/VoiceOver measurement + independent reviews.
- Test suites are authoritative under `swift test --no-parallel` + CLT plugin flag (the M12-E
  orchestrator rerun discarded a load-sensitive parallel run).

## Owner authorizations

**OD-M12-1 SETTLED (owner approved 2026-11-13):** temporary FKA/VoiceOver/appearance/text-size
toggles during M12-F only, each restored to its prior value before finishing.

## Next steps (owner-authorized only)

1. Create PR `milestone/m12-workflow → main` (title < 70 chars; it stacks on unmerged M11 PR #2,
   which GitHub auto-retargets when #2 merges, or retarget manually).
2. Owner decides merge; NOT merged at record time. No release.
