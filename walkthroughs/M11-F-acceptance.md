# M11-F — capability matrix and contributor foundation: orchestrator acceptance record

Date: 2026-11-12. Orchestrator: Qoder (Herdr `t7x`). Phase brief:
[briefs/M11-F-matrix-contributor.md](../briefs/M11-F-matrix-contributor.md) (frozen at `62aa642`);
revision [M11-F-R1](../briefs/M11-F-R1-guide-corrections.md) (frozen at `fce78af`).
Implementer: DeepSeek V4.1 Flash 1017 via OMP (`river`), max reasoning, sole writer.

**Decision: M11-F is technically accepted** — candidate `d3f0324` plus the R1 guide correction.
Both mandatory independent reviews PASS; the single LOW finding was returned to the implementer,
corrected, and verified. All implementation phases of M11 (A–F) are now accepted.

## Independent reviews

| Reviewer | Verdict | Findings | Report |
|---|---|---|---|
| Grok 4.7/high | **PASS** | 0 blocking, 1 low | [grok.md](M11-F-evidence/reviews/grok.md) |
| MiniMax M3.1-Flash/xhigh | **PASS** | 0 blocking/high/medium/low, 5 info | [minimax.md](M11-F-evidence/reviews/minimax.md) |

Both re-derived matrix truth programmatically against the registry, verified the parser and
seeded corruptions, the contribution proof, the three-branch collision control, the floors, the
guide's license stance and vocabularies, and the allow-list scope.

## Findings and rulings

- **Grok LOW (guide edit-list omission): CORRECTED via R1.** `docs/CONTRIBUTING.md` omitted
  `CapabilityMatrixTests.swift` (its `frozenCatalogue` id list must be extended when a tool is
  added). R1 added it as item 7 with both obligations (frozen list + matrix row), renumbered
  README to item 8. Orchestrator verified the diff; CapabilityMatrix filter 3/3 exit 0; protected
  manifest diff empty. Finding closed.
- **MiniMax INFO-1 (prose stricter than test): accepted.** The ownership-verification clause in
  the matrix prose is a runtime truth, not a third test-enforced rule; asymmetry is in the safe
  direction. Recorded so later phases don't misread it.
- **MiniMax INFO-2 (7 pinned markers vs ~40 limit facts): accepted.** The test pins exactly the
  brief's seven required substrings; all other limits were content-verified by both reviewers.
  Widening the marker map is a future-phase decision (M12+ backlog), not an M11 defect.
- **MiniMax INFO-3 (cask-only disabled wording, worker D-3): accepted as correct.** agy/kiro-cli
  declare casks, so `disabled: no declared npm package; cask mutation not shipped` is the truthful
  cause; the brief's example was illustrative ("e.g.").
- **MiniMax INFO-4 (report provenance wording): CORRECTED via R1.** The git-status snapshot
  predates the report file; the report now states that accurately.
- **MiniMax INFO-5 (TMPDIR dependency fails closed): accepted.** Missing TMPDIR fails the suite
  rather than skipping; hosted runner inherits TMPDIR (documented in ci.yml). Recorded for future
  CI changes.

## Orchestrator independent verification

- Full diff review: matrix (14 rows, exact cells, all required carry-forward limits present —
  `3747`, `2026-12-18`, `2027-05-18`, `~/.gemini/bin`, `pressly`, `opencode2`, `Dancer`);
  agreement test with deterministic parser + two seeded corruptions; contribution proof through
  the production validator with production-id assertion; three-branch seeded collision control;
  floors 467/80/547/547 with anchors/guard-21/packaging-9 unchanged; guide license-pending and
  vocabularies matched to the validator; README links; **no Sources/** change**.
- Gates rerun personally (`R/evidence/f/parent-*.log`): build exit 0; suite **467 Core + 80
  AppSupport = 547, zero skips/failures**, exit 0 (invocation-local plugin path; recount matches
  the floors exactly); import guard clean; 21 guard fixtures; fresh dev app; 9 packaging;
  preflight `registry_count=14`.
- R1 gates: CapabilityMatrix filter 3/3 exit 0; two-file diff verified; protected manifest clean.

## Limits and carry-forward

- Matrix markers pin the seven critical limits; the full limit set is content-verified but not
  regression-pinned (INFO-2) — future-phase decision.
- License remains the owner's open choice (OD-7); no LICENSE file; no public invitations.
- Per-tool mutation promotion remains separate owner-authorized work (OD-5/D-021).
- No merge, no release. Next: the orchestrator-run combined M11 gate (local reruns + seven hosted
  gates at the exact candidate SHA + end-to-end contribution proof + evidence index).

## Team and process

Sole implementer DeepSeek V4.1 Flash 1017/OMP max; mandatory independent reviewers MiniMax + Grok;
Herdr/hc orchestration only. Candidate frozen before review; the one LOW returned as a bounded
revision brief, corrected by the same implementer, verified by the orchestrator.