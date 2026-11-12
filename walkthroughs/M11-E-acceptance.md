# M11-E — owner-confirmed remainder: orchestrator acceptance record

Date: 2026-11-12. Orchestrator: Qoder (Herdr `t7x`). Phase brief:
[briefs/M11-E-owner-remainder.md](../briefs/M11-E-owner-remainder.md) (frozen at `50e93e7`).
Implementer: DeepSeek V4.1 Flash 1017 via OMP (`river`), max reasoning, sole writer.

**Decision: M11-E is technically accepted.** The bundled registry now ships all fourteen
originally named catalogue entries. Data-only phase with owner-confirmed identities: orchestrator
acceptance per the brief (ceremony matches stakes, §29.9); the mutation gate (M11-B) and collision
regression (M11-D) were independently reviewed and remain green.

## Requirement-to-evidence results

| Requirement | Result | Evidence |
|---|---|---|
| dsh/qodercli rows match the frozen packet | PASS | Full diff review: packages (`@deepseek-ai/dsh`, `@qoder-ai/qodercli`), roots `["~/.local/bin"]`, categories aiHarness/aiCodingTool, fixtures npmGlobal/singleDirectory, URLs incl. Qoder `#uninstallation`; no uninstall URL invented for DSH; `acceptedOperations` absent on both; codex the only accepted entry |
| Exact 14-id order | PASS | Renamed catalogue test asserts the full ordered list; existing twelve rows' assertions intact |
| Collision regression | PASS | `bundledRegistryNeverDeclaresCollisionIdentities` green; brew `dsh`, cask `qoder`, id/executable `qoder` remain forbidden and absent |
| Full gates (orchestrator rerun) | PASS | build exit 0; suite 464+80=544 exit 0 (see environment note); guards clean; 21 guard fixtures; fresh dev app; 9 packaging (`R/evidence/e/parent-*.log`) |
| Preflight + CLI parity | PASS | `registry_count=14` exact id list (packaging test); orchestrator CLI scan: fourteen entries, DSH `0.2.2-rc.1` npm, Qoder `1.1.88` standalone, truthful absent/unknown states elsewhere |
| Hermetic CLI integration | PASS | Exact invoked set = twelve shadowed tools (dsh/qodercli fakes added); gemini/cline truthfully absent; no real tool executed |
| Scope | PASS | 7 allow-listed files + worker report; protected manifest diff empty; ci.yml/floors untouched |

## Environment note

The worker's unflagged suite run passed; the orchestrator's unflagged rerun hit the known
intermittent CLT-only `TestingMacros … plugin not found` failure (cache-state dependent) and
passed with the documented invocation-local flag (`parent-02b-suite-pluginpath.log`, 544 tests).
Both runs retained. No package/toolchain change (M11-C/D precedent).

## Deviations

None reported by the worker; none found by the orchestrator. Dispatch HEAD `50e93e7` is the
accepted baseline `c1183b4` plus the dispatch documents only.

## Limits and carry-forward

- All fourteen entries are informational for mutation except codex (D-021). Per-tool promotion
  remains a separate owner-authorized dispatch (OD-5).
- M11-F inherits: matrix truth rules; seeded-control extension to all three manager branches;
  agy legacy-root limit; goose basename limit; deprecation calendar; Aider cold-start limit;
  contributor guide with license pending the owner's OD-7 choice; measured floor raise.
- No merge, no release. M11 continues with M11-F, then the orchestrator-run combined gate.

## Team and process

Sole implementer DeepSeek V4.1 Flash 1017/OMP max. Herdr/hc orchestration only. Worker terminal
retired after acceptance.