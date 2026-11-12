# M11-D — collision batch: orchestrator acceptance record

Date: 2026-11-12. Orchestrator: Qoder (Herdr `t7x`). Phase brief:
[briefs/M11-D-collision-batch.md](../briefs/M11-D-collision-batch.md) (frozen at `8ac1b50`).
Implementer: DeepSeek V4.1 Flash 1017 via OMP (`river`), max reasoning, sole writer.

**Decision: M11-D is technically accepted at candidate `cdd8ccc3eb488fd980f6f6182df451f1f7d4f7c7`
on `milestone/m11-catalogue`.** The registry ships twelve entries; the do-not-declare regression
is permanent and non-vacuous; both mandatory independent reviews PASS.

## Independent reviews (required by the dispatch brief — identity/collision risk)

| Reviewer | Verdict | Findings | Report |
|---|---|---|---|
| MiniMax M3.1-Flash/xhigh (mcode) | **PASS** | 0 blocking/high/medium, 1 low, 3 info | [minimax.md](M11-D-evidence/reviews/minimax.md) |
| Grok 4.7/high (grok CLI) | **PASS** | 0 | [grok.md](M11-D-evidence/reviews/grok.md) |

Both verified row-by-row against the frozen packet, parsed the registry for forbidden identities,
traced the hermetic fixture, and confirmed ci.yml/floors untouched and the existing six rows
unchanged. MiniMax additionally ran an independent seed-corruption of the bundled registry
(npm `goose`) → regression failed as designed → restored byte-identically (SHA-256 verified).

## Orchestrator rulings

- **MiniMax #1 (LOW): accepted; carried into M11-F as a requirement.** The in-test seeded control
  covers only the npm branch of the forbidden map. M11-F must extend it with one homebrewFormula
  and one homebrewCask violation so all three branches are permanently non-vacuous. No M11-D
  defect (keys verified against `PackageManager` raw values).
- **MiniMax #2 (INFO): carried into M11-F.** The agy `~/.gemini/bin` legacy root's R10
  `observed-local` limit must appear in the capability matrix row (the registry schema has no
  notes field by design).
- **MiniMax #3 (INFO): accepted as documented.** Hermeticity rests on PATH-first lookup ordering
  (traced in `ToolDetector.locate` / `PathDiagnostics`); extra roots are consulted only without a
  live PATH candidate. Residual host-dependence of the exact-set assertion is recorded; no M11
  action.
- **MiniMax #4 (INFO): carried forward.** pressly/goose basename collision remains a runtime
  limit; any future mutation must target the declared formula `block-goose-cli`, never the
  basename. Matrix (M11-F) and M13 briefs must carry this.
- **Worker deviations D-1…D-4: accepted.** D-1 the known CLT-only TestingMacros invocation-local
  workaround (both runs recorded; orchestrator reproduced and reran flagged, exit 0); D-2 the
  ten-tool exact invoked set (gemini/cline truthfully absent); D-3 dispatch HEAD vs product
  baseline (docs-only difference); D-4 temporary seed probe restored byte-identically (SHA
  verified by worker and by MiniMax independently).

## Orchestrator independent verification

- Full diff review: six new rows exact per contract (packages, roots, categories, fixtures, URLs,
  `["--version"]`/stdout/first); `acceptedOperations` absent on all new rows; codex seed intact;
  order preserved; ci.yml and floors untouched; scope = 7 allow-listed files + worker report.
- Gates rerun personally (`R/evidence/d/parent-*.log`): build exit 0; suite **464 Core + 80
  AppSupport = 544, zero skips/failures**, exit 0 (invocation-local plugin path); import guard
  clean; 21 guard fixtures OK; fresh dev app exit 0; 9 packaging OK; preflight
  `registry_count=12` with the exact id list.
- CLI parity: built `agent-lens scan --offline` shows twelve entries with truthful states
  (Hermes 0.23.1, OMP 18.19.0, AGY 1.5.6 detected; Aider/Goose/Kiro not installed → `–`;
  Codex version unknown from the measured optional-dependency failure).

## Limits and carry-forward

- New entries informational (D-021); promotion requires separate owner-authorized scenarios.
- M11-F requirements added: seeded-control extension (all three manager branches); agy legacy-root
  matrix limit; goose basename limit; deprecation calendar; Aider cold-start limit.
- No merge, no release. M11 continues with M11-E (owner-confirmed remainder: dsh, qodercli).

## Team and process

Sole implementer DeepSeek V4.1 Flash 1017/OMP max; mandatory independent reviewers MiniMax + Grok;
Herdr/hc orchestration only. Candidate frozen before review; no post-review code change needed.