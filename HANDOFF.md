# M12 hand-off — safe stop point (2026-11-13)

> **STATUS: SUPERSEDED — M12 IS COMPLETE.** This file is retained as the historical pause snapshot
> only. Resume tasks 1–5 below were all executed on 2026-11-13 after the pause. For the authoritative
> record read **[walkthroughs/M12-combined-acceptance.md](walkthroughs/M12-combined-acceptance.md)**
> and the M12-F entry in `DECISIONS.md`. Current state: branch `milestone/m12-workflow` pushed and
> clean; all A–F phases accepted; M8 keyboard gate closed; hint fix re-reviewed by both council
> models (both PASS); all seven hosted gates green at the final SHA; **PR #3 open and mergeable
> (`mergeStateStatus: CLEAN`) — NOT merged, owner decision pending.**
>
> Corrections to what follows: PR #2 (`milestone/m11-catalogue`) was **merged** to `main`
> (`8d07ba4`) after the pause, so the branch is no longer stacked on an open PR — its merge-base with
> `origin/main` is `0589fac` and it merges cleanly. The 93 unpushed commits were already on origin at
> resume time.

Resume here. This file is the orchestrator's hand-off after an owner-requested pause (laptop
shutdown). It is a status snapshot, not a frozen brief or acceptance record.

## Where things stand

- **Project:** Agent Lens (native Swift 6 / SwiftUI macOS app). Repo remote:
  `https://github.com/Hazem-Samak/agent-lens.git` (use this exact URL; no proxies).
- **Branch:** `milestone/m12-workflow` (stacks on unmerged M11; PR #2 `milestone/m11-catalogue → main`
  is still open and NOT merged). Base product commit `0589fac`. Local HEAD `6b8e2f4`, working tree
  clean, **22 commits ahead of origin — PUSH THE BRANCH FIRST on resume** (back up before any work).
- **Milestone plan:** `briefs/M12-plan.md` (frozen), rulings R1–R16 in
  `briefs/M12-planning/judgment.md`. Council: MiniMax M3.1-Flash/xhigh (mcode) + Grok 4.7/high (grok).
  Sole implementer: DeepSeek V4.1 Flash 1017 via OMP (`river/deepseek-ai/DeepSeek-V4.1-Flash-1017`,
  `--thinking max`). All agents summoned via Herdr/hc only.

## Phase status

| Phase | Status | Candidate | Reviews |
|---|---|---|---|
| M12-A presentation foundation | **ACCEPTED** | `64a5056`+R1 `2ed3a77` | both PASS |
| M12-B navigation shell | **ACCEPTED** | `ea08ad8` | orchestrator + native spot-check |
| M12-C conflict summary + Updates filter | **ACCEPTED** | `e66872d` | orchestrator + native spot-check |
| M12-D operation journey + C-1 | **ACCEPTED** | `6c1405a` | both PASS (C-1 adjudicated safe) |
| M12-E menus/a11y/layout | **ACCEPTED** | `5214d63`+R1 `407882b` | both PASS after R1 |
| M12-F M8 keyboard gate + measurement | **fix done, acceptance pending** | `255fd9c` (sidebar) + `a411661` (hint fix) | sidebar both PASS; hint fix re-review pending |

- **M8 keyboard-only gate: CLOSED** on the disposable fixture (full matrix: Tab reaches all four
  path buttons; Space activates each; Copy Selected/Resolved byte-equal with SHA match; Reveal
  Selected/Resolved selects the exact symlink/canonical target in Finder; category-list Tab traversal
  works; clipboard + fixture restored). Evidence:
  `~/.hermes/cache/scratch/agent-lens-m12-f-measure/evidence/` (INDEX.md).
- **Hint defect fixed** (`a411661`): `PathActions.swift` `.help()` now carries the hint text so AXHelp
  is not masked. Implementer R2 gates green (586). **Independent re-review of the hint fix is pending.**
- **VoiceOver:** captions captured for path buttons, unavailable sentence, path-feedback announcement;
  list row / Settings recorded with AX evidence where captions were not observed (partial — see
  `walkthroughs/M12-F-measurement.md`). Large-text: macOS semantic-text scaling limitation recorded;
  safety text wraps fully; light/dark + narrow-window screenshots captured.
- **CI floors raised** (`3212255`): Core 467, AppSupport 119, total/combined 586; guard 21, packaging 9;
  anchors frozen. Suite green throughout (467 Core + 119 AppSupport = 586, zero skips/failures).
- **OD-M12-1 SETTLED** (owner approved): temporary FKA/VoiceOver/appearance toggles for M12-F, restored.
  **System settings already restored** (FKA unset/off, VoiceOver off, appearance Dark).

## What remains (resume tasks, in order)

1. **Push the branch** to origin (back up the 22 local commits): `git push -u origin milestone/m12-workflow`.
2. **Independent re-review of the hint fix** (`a411661`, PathActions.swift only) by BOTH council models
   (small; confirm AXHelp = hint, labels preserved, no behavior change). Reuse reviewer terminals or
   summon fresh. File `walkthroughs/M12-F-evidence/reviews/{minimax,grok}-r2.md`.
3. **Hosted gates at the final candidate SHA**: push triggers CI; verify all seven gates green at the
   exact SHA (guard, guard-fixtures, swift-build, isolation-gate, full-test-suite [586, anchors],
   build-dev-app, packaging). Use `gh run watch <id> --exit-status`. Record the run ID + receipt.
4. **Combined M12 acceptance record**: `walkthroughs/M12-combined-acceptance.md` (orchestrator-run;
   requirement-to-evidence across A–F; the ROADMAP journey matrix; honest limitations: VoiceOver
   list-row/Settings captions partial, macOS large-text scaling note). Update `DECISIONS.md` milestone
   log (M12-F + combined). The orchestrator reruns the full local gate set itself (D-014).
5. **Create the PR** `milestone/m12-workflow → main` (note it stacks on unmerged PR #2; GitHub
   auto-retargets when #2 merges, or retarget manually). Title < 70 chars; body summarizes the phase,
   evidence, reviews, limitations. **Do NOT merge** — owner authorizes merge separately.
6. **Merge-readiness assessment** to the owner: ready / not-ready, with the honest limitations.

## Key commands / environment

- Local suite (CLT-only workstation; documented plugin flag, `--no-parallel` is authoritative):
  ```sh
  env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS \
    swift test --build-system swiftbuild --scratch-path <scratch>/full-suite --no-parallel \
    -Xswiftc -load-plugin-library \
    -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib
  ```
  Run slow commands in an `hc` terminal (`hc run --bg --name <n> ... ; hc wait <n>`), not the shell.
  Under concurrent-agent load the Core version-query tests can flake; a clean serial rerun is authoritative.
- Guards: `python3 scripts/check-core-ui-imports.py` (+ `--source-root Sources/AgentLensAppSupport`);
  `python3 Tests/Packaging/test_core_ui_imports.py` (21); dev app `python3 scripts/build-dev-app.py
  --scratch-root <s>/app --configuration debug`; packaging `python3 Tests/Packaging/test_dev_app_bundle.py
  --app <s>/app/AgentLensApp-debug.app` (9).
- CLI launch paths: mcode `/Users/corvette/.minimax-code/bin/mcode` (default model M3.1-Flash; effort
  xhigh via TUI; launch WITHOUT `-m`); grok `/Users/corvette/.local/bin/grok -m grok-4.7
  --reasoning-effort high`; omp `/Users/corvette/.local/bin/omp --model
  river/deepseek-ai/DeepSeek-V4.1-Flash-1017 --thinking max`. Use absolute paths (hc spawn PATH differs).
- Herdr: orchestrator terminal `t7x`; Agent Lens space `sp1a17b60a6b77c9dbc2c8772fae054522`.
  `hc --skill` / `herdr-app --skill` for the manuals. Reviewer terminals were `t9q` (minimax),
  `t9r` (grok); implementer `t9n` (omp). These end on laptop shutdown — resummon on resume.
- Native driving: `cua-driver` (daemon has Accessibility + Screen Recording). The orchestrator's own
  shell context LACKS the system-wide-focus TCC grant; the implementer's omp context HAS it (use it for
  CGEvent key + AX focus measurement). System Events `entire contents` can read focus but `description`
  reads generically; the implementer's Swift AXUIElement reader reads kAXDescriptionAttribute correctly.

## Process rules (binding)

- One milestone branch, sequential phases, one product writer; reviewers read-only; orchestrator runs
  acceptance (D-014) and owns Git delivery. Implementer gets the brief, not the scope doc.
- Zero Core/CLI/registry change in M12 (Core stays 467). Floors raise-only to measured counts.
- Mutation acceptance only against disposable npm fixtures (`Tests/Fixtures/M10C`, `M10D`); never a
  personal installation. Copy/Reveal are read-only.
- Evidence roots under `~/.hermes/cache/scratch/agent-lens-m12-*` (outside the repo). Raw transcripts,
  SHA-256 manifests, protected-file diffs. Worker reports labeled worker evidence, not acceptance.
- **Note:** the omp implementer used its git `checkpoint` tool and created commits (`a411661`,
  `6b8e2f4`) despite the "do not commit" instruction. The commits are coherent checkpoints and the
  work is intact; on resume, reassert "do not commit/push — orchestrator owns Git" if continuing to use
  omp, or disable its checkpoint tool.

## Resume prompt (paste to continue)

> Continue M12 from the hand-off in `HANDOFF.md` on branch `milestone/m12-workflow`. You are the
> orchestrator/main judge; planning council and independent reviewers are MiniMax M3.1-Flash/xhigh
> (mcode) and Grok 4.7/high (grok CLI); implementer is DeepSeek V4.1 Flash 1017 via OMP (max). Use
> Herdr/hc for all agents. First push the branch to back it up. Then: (1) independent re-review of the
> M12-F hint fix (commit a411661, PathActions.swift) by both reviewers; (2) verify all seven hosted CI
> gates green at the final candidate SHA; (3) write the combined M12 acceptance record + DECISIONS log
> (orchestrator reruns the local gates); (4) create the PR milestone/m12-workflow → main (stacks on
> unmerged PR #2); (5) give me a merge-readiness assessment. Do NOT merge until I authorise. M12-A…E
> are accepted; the M8 keyboard gate is closed on the disposable fixture; CI floors are raised to 586.