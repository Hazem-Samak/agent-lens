# M11-B — mutation acceptance gate: orchestrator acceptance record

Date: 2026-11-12. Orchestrator: Qoder (Herdr `t7x`). Phase brief:
[briefs/M11-B-mutation-gate.md](../briefs/M11-B-mutation-gate.md) (frozen at `5da1624`).
Implementer: DeepSeek V4.1 Flash 1017 via OMP (`river`), max reasoning, sole writer.

**Decision: M11-B is technically accepted at candidate `caae348f9cebc5133d34a5b4ff4485c615a0ad0c`
on `milestone/m11-catalogue`.** Both mandatory independent reviews PASS; the orchestrator reran all
gates and performed the native spot-check. The mutation surface is fail-closed per registry entry.

## Independent reviews (mandatory, ROADMAP §5.4)

| Reviewer | Route | Verdict | Findings | Report |
|---|---|---|---|---|
| MiniMax M3.1-Flash/xhigh | mcode v0.7.6, Herdr `t8f` | **PASS** | 0 blocking, 1 medium (brief defect F-1), 6 low | [minimax.md](M11-B-evidence/reviews/minimax.md) |
| Grok 4.7/high | grok 1.0.77, Herdr `t8d` | **PASS** | 0 | [grok.md](M11-B-evidence/reviews/grok.md) |

Both reviews were read-only, re-derived claims from the candidate source (not the worker report),
did not read each other's files, and independently re-read the orchestrator gate logs. Both
verified: gate placement before scratch/observation/runner in both Core prepare seams; no bypass
via Codable/constructor/alternate entry (`prepare` is the only construction site of the internal
preparation types); closed vocabulary; zero assertions/tests removed or skipped; correct fixture
migrations; single-source reason strings; scope confined to the allow-list plus three reported
migrations.

## Orchestrator rulings on findings and deviations

- **F-1 / D-1 (medium): ACCEPTED as a brief defect, not a code defect.** The shipping CLI has only
  `scan`, `verify-installation`, `debug-env` (verified in `main.swift`); the frozen M10-C/M10-D
  contracts forbid CLI mutation syntax. Contract 7 / B-AC05 of the M11-B brief was unsatisfiable as
  written. Ruling: the clause is **vacuous**; `main.swift` correctly unchanged; **B-AC05 is recorded
  as vacuous-by-ruling, NOT evidenced**. No revision brief. Recorded as D-022. The implementer
  detected and reported the conflict instead of improvising — exactly the required behavior.
- **F-2 / D-2 (low): accepted.** Showing the uninstall reason for any npm-declared unaccepted entry
  (before Verify) is a fail-closed broadening and more truthful than the old hint, which would now
  promise that Verify enables Uninstall. The Manage section remains npm-declared-only; grok (no
  packages) has no Manage section. Verify control unchanged.
- **F-3 / D-3 (low): accepted.** Present `null` is a non-array value; rejection is the
  contract-correct, fail-closed reading. Absence alone yields `[]`.
- **F-4 (low): accepted as cosmetic.** Both decode paths reject mixed-type arrays with named
  detector/field errors; index granularity differs. No correction required.
- **F-5 (low): weighed.** No App test target exists (`Package.swift` protected). The orchestrator's
  native spot-check (below) is the App-mirror evidence, as the reviewer noted.
- **F-6 (low): accepted.** The literal message assertions pin the brief's exact wording and
  strengthen the enum-equality check; no duplicated surface string exists to drift.
- **F-7 / D-4 (low): accepted.** The three out-of-list fixture migrations are within the brief's
  forced-migration allowance, reported, and necessary for the M10 harnesses to keep exercising
  their accepted scenarios. No assertion weakened (both reviewers verified at assertion level).

## Orchestrator independent verification

- **Gates rerun personally** (`R/evidence/b/parent-*.log`): `swift build` exit 0;
  `swift test --no-parallel` exit 0 — **463 Core + 80 AppSupport = 543 passed, 0 skipped, 0 failed**
  (baseline 535 + 8 new); `check-core-ui-imports.py` exit 0 (32 Core files, no UI imports);
  `test_core_ui_imports.py` 21 OK; fresh dev app exit 0; `test_dev_app_bundle.py` 9 OK.
- **Diff review**: full production diff read against the contract; gate is the second statement in
  both prepares; reason strings byte-identical to the contract; codex seeded; schema stays 2;
  validation strict on both decode paths; 16 manifest mismatches = 13 allow-listed + 3 reported
  migrations; all other protected files OK.
- **B-AC07 native spot-check (orchestrator-performed, read-only, no mutation executed)**:
  built app launched; Codex Verify → ownership Verified (npm, `@openai/codex`) → Manage offers
  "Verified npm-global package" + Uninstall… (M10 surface intact; Update button correctly absent
  because the local version is unknown from the measured optional-dependency failure). OpenCode
  (npm-declared, unaccepted) → Manage shows the exact Core uninstall reason, no button. Grok CLI
  (no packages) → no Manage section, no mutation surface. Screenshots and transcript:
  `R/evidence/b/native-spotcheck.md`, `native-01…04.png`. **PASS.**

## Acceptance matrix result

| ID | Result |
|---|---|
| B-AC01 | Met — validation strict on both paths (reviews + orchestrator diff) |
| B-AC02 | Met — zero-invocation refusal proofs, gate-before-scratch ordering test |
| B-AC03 | Met — M10 suites unweakened; data-driven codex copy refuses when acceptance removed |
| B-AC04 | Met — ViewModel refusal with verified ownership, no pipeline, zero runner calls |
| B-AC05 | **Vacuous by ruling (D-022)** — no CLI mutation surface exists; not evidenced |
| B-AC06 | Met — orchestrator reran all six gates, exit 0 |
| B-AC07 | Met — orchestrator native spot-check PASS |

## Schema decision

Recorded as D-021: `acceptedOperations` is an additive optional field on registry schema 2 (closed
`npmUpdate`/`npmUninstall` vocabulary, absent → `[]`, strict fail-closed validation). Schema 1/3
and unknown keys remain rejected. Per-entry mutation acceptance is now a product invariant:
detection never implies mutation eligibility.

## Limits and carry-forward

- New catalogue entries (M11-C/D/E) ship WITHOUT acceptance: informational until a per-tool
  accepted mutation scenario is separately owner-authorized (OD-5). Promotion is not part of M11.
- The App mirror has no automated App-target coverage (F-5); native observation is the evidence.
  M12's workflow work should consider an App test surface.
- Aider cold-start > 3 s and the deprecation calendar from M11-A remain matrix limits for M11-F.
- No merge to `main`, no release. Milestone continues with M11-C.

## Team and process

Sole implementer DeepSeek V4.1 Flash 1017/OMP max. Mandatory independent reviewers MiniMax
M3.1-Flash/xhigh (mcode) and Grok 4.7/high (grok CLI). Herdr/hc orchestration only (owner rule).
Worker and reviewer terminals retired after acceptance. Candidate frozen before review; reviews
read the frozen SHA; no post-review code change was needed.