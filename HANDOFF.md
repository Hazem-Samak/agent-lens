# M12 HANDOFF — safe stop point (2026-11-13)

Resume prompt is at the bottom. Everything below is committed; the working tree is clean.

## Where the project is

Agent Lens, milestone **M12 — complete native diagnostic and operation workflow**, on branch
`milestone/m12-workflow` (stacks on unmerged M11 / PR #2; base `0589fac`). Orchestrator/main judge:
Qoder. Planning Council + standing independent reviewers: **MiniMax M3.1-Flash/xhigh via `mcode`**
and **Grok 4.7/high via `grok`**. Sole implementer: **DeepSeek V4.1 Flash 1017 via `omp`**
(`river/deepseek-ai/DeepSeek-V4.1-Flash-1017`, `--thinking max`). All agents run through **Herdr
Core (`hc`)** in the "Agent Lens" space (tabs: M12 Planning Council, M12 Implementer, M12 Reviews).

**HEAD: `6b8e2f4`** (clean tree). Remote: `https://github.com/Hazem-Samak/agent-lens.git`.

## Completed and accepted (all committed)

| Phase | Content | Candidate | Reviews |
|---|---|---|---|
| Plan | Council proposals + judgment R1–R16 + frozen `briefs/M12-plan.md` | `1f251d4` | council |
| M12-A | AppSupport presentation foundation (scope/filter/conflict/capability/invalidation) | `64a5056`+R1 `2ed3a77` | both PASS |
| M12-B | Seven-destination navigation shell + Overview + read-only Settings + row details | `ea08ad8` | orchestrator + native spot-check |
| M12-C | Conflict summary + Updates status filter | `e66872d` | orchestrator + native spot-check |
| M12-D | Operation journey: ManagementPresentation render, progress region, **C-1** (Return never confirms) | `6c1405a` | both PASS, C-1 adjudicated safe |
| M12-E | Native menus + VoiceOver labels + layout/appearance | `5214d63`+R1 `407882b` | both PASS (after R1) |
| M12-F | **M8 keyboard gate CLOSED** + sidebar focus fix + hint fix | `255fd9c` (fix) + `a411661` (measure+R2) | both PASS (sidebar) |
| CI | Floors raised to measured counts (Core 467 / AppSupport 119 / total 586) | `3212255` | orchestrator |

Acceptance records: `walkthroughs/M12-{A,B,C,D,E}-acceptance.md`. Measurement:
`walkthroughs/M12-F-measurement.md`. Reviews under `walkthroughs/M12-*-evidence/reviews/`.
Milestone log: `DECISIONS.md` (M12 section). **OD-M12-1 owner-approved** (temporary FKA/VoiceOver/
appearance for measurement, restored after).

**Test suite: 467 Core + 119 AppSupport = 586, zero skips/failures** (orchestrator-rerun, multiple
times). Guards 21, packaging 9, both import guards clean, dev-app builds.

**M8 keyboard gate is CLOSED** on the disposable fixture: Tab reaches all four path buttons, Space
activates each; Copy Selected/Resolved byte-equal (SHA match); Reveal Selected/Resolved selects the
exact symlink/canonical target in Finder; category-list Tab traversal works; clipboard+fixture
restored. Evidence: `~/.hermes/cache/scratch/agent-lens-m12-f-measure/evidence/` (INDEX.md).

**System settings RESTORED**: Full Keyboard Access off (`AppleKeyboardUIMode` unset), VoiceOver off,
appearance Dark, window 960×600, clipboard empty.

## Remaining work (NOT done — resume here)

1. **Hosted CI gates at the exact candidate SHA.** Push the branch (if not pushed) and verify all
   seven hosted gates pass at HEAD (`guard`, `guard-fixtures`, `swift-build`, `isolation-gate`,
   `full-test-suite` with floors 467/119/586 + anchors, `build-dev-app`, `packaging`). Use
   `gh run watch <id> --exit-status`. The local suite is green; hosted confirmation is pending.
2. **Combined M12 acceptance record** (`walkthroughs/M12-combined-acceptance.md`) + DECISIONS.md
   combined entry: requirement-to-evidence matrix (ROADMAP M12 acceptance), hosted receipt, limits.
3. **Create the PR** (`milestone/m12-workflow` → `main`; note it stacks on unmerged PR #2). Review it
   and give the owner a **merge-readiness assessment**. **DO NOT MERGE** — owner authorizes merge.
4. **Optional cleanup**: remove this HANDOFF.md before the PR (or keep as a record); kill leftover
   hc terminals.

## Known limitations to disclose honestly in the PR/assessment

- **VoiceOver spoken check is PARTIAL**: caption panel captured the path buttons, the unavailable
  sentence, and the path-feedback announcement. The **list row and Settings** could not be captioned
  (VoiceOver Item-Chooser/interact mode replaces the element caption with interaction instructions);
  exact AX evidence is retained and the reason is recorded in `M12-F-measurement.md`. The labels are
  implemented and AX-verified; the audible confirmation for those two surfaces is limited.
- **Large-text**: `.dynamicTypeSize(.accessibility5)` did not scale macOS semantic text (a macOS
  behavior, recorded); safety text wraps with full AX value at narrow width (320 pt). Light/dark +
  narrow-window (760×480 content) screenshots captured.
- The M8 measurement used the disposable fixture (correct); an earlier partial proof used a live
  read-only path (superseded by the full fixture matrix).
- Sidebar changed from `List` to Button rows (M12-F fix) — a visual surface change vs M12-B; both
  reviewers PASS, noted for the light/dark comparison.

## Key reference facts

- Local suite command (CLT-only workstation; `--no-parallel` is REQUIRED — parallel runs give
  load-sensitive Core version-query failures):
  ```sh
  env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS \
    swift test --build-system swiftbuild --scratch-path <scratch> --no-parallel \
    -Xswiftc -load-plugin-library \
    -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib
  ```
- Dev app: `python3 scripts/build-dev-app.py --scratch-root <dir> --configuration debug`.
- Evidence roots: `~/.hermes/cache/scratch/agent-lens-m12-{a,b,c,d,e,f,f-r1,f-measure,f-r2}*`.
- hc agent terminals (may be dead after shutdown): implementer `m12a-impl`, reviewers
  `review-minimax`/`review-grok`, council `council-minimax`/`council-grok`. Restart with
  `hc run --bg --name <name> --cwd "<repo>" --label herdr.space=<AgentLens-space-id> <cli> ...`.
  mcode: launch without `-m` (default M3.1-Flash), effort xhigh via `/model`. grok:
  `-m grok-4.7 --reasoning-effort high`. omp: `--model river/deepseek-ai/DeepSeek-V4.1-Flash-1017
  --thinking max --approval-mode yolo`.
- The orchestrator's shell context lacks the Accessibility TCC grant for system-wide focus reads;
  the implementer's omp context has it (use it for keyboard/VoiceOver measurement).

## RESUME PROMPT (paste this to continue)

> Continue Agent Lens milestone M12 from the safe stop point in HANDOFF.md (branch
> `milestone/m12-workflow`, HEAD `6b8e2f4`, clean tree). Phases A–F are implemented and accepted;
> the M8 keyboard gate is closed; CI floors are raised to 586; system settings are restored. You are
> the orchestrator/main judge; the Planning Council/independent reviewers are MiniMax M3.1-Flash
> (xhigh, `mcode`) and Grok 4.7 (high, `grok`); the implementer is DeepSeek V4.1 Flash 1017 (`omp`,
> `river/deepseek-ai/DeepSeek-V4.1-Flash-1017`, max). Use Herdr Core (`hc`) for agents. Remaining:
> (1) push the branch and verify all seven hosted CI gates pass at the exact candidate SHA;
> (2) write the combined M12 acceptance record + DECISIONS.md entry with the requirement-to-evidence
> matrix and honest limitations (VoiceOver list-row/Settings captions partial; large-text macOS
> behavior); (3) create the PR to main (stacks on unmerged PR #2), review it, and tell me if it is
> ready to merge. DO NOT MERGE until I authorise. Read HANDOFF.md, briefs/M12-plan.md,
> briefs/M12-planning/judgment.md, and walkthroughs/M12-F-measurement.md first.