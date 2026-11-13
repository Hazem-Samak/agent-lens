# M12-A acceptance — presentation-state foundation

Date: 2026-11-13. Orchestrator: Qoder (Herdr `t7x`). Milestone branch: `milestone/m12-workflow`.
**Accepted candidate: `64a5056` + R1 (`2ed3a77`).** Phase M12-A of the frozen master plan
`briefs/M12-plan.md`; dispatch brief `briefs/M12-A-presentation-foundation.md`; binding rulings
R1/R2/R3/R4/R8/R12/R16 in `briefs/M12-planning/judgment.md`.

**Decision: M12-A is TECHNICALLY ACCEPTED.** Both mandatory independent reviews PASS with zero
blocking findings; the orchestrator independently reran every gate (D-014). The app is visually
unchanged (zero `Sources/AgentLensApp/**` diff); the behavioral change is the AppSupport
presentation model and the extended confirmation-invalidation trigger set.

## Independent reviews (both PASS)

| Reviewer | Route | Verdict | Findings | Record |
|---|---|---|---|---|
| MiniMax M3.1-Flash/xhigh | mcode v0.7.6, Herdr `t9q` | **PASS** | 0 blocking/high/medium, 3 low, 4 info | [minimax.md](M12-A-evidence/reviews/minimax.md) |
| Grok 4.7/high | grok 1.0.77, Herdr `t9r` | **PASS** | 0 blocking/high/medium, 2 low, 3 info | [grok.md](M12-A-evidence/reviews/grok.md) |

Both reviewers independently recomputed the changed-file SHA-256 (matching the committed tree),
recounted the AppSupport `@Test` cases, re-ran the AppSupport import guard, and verified the
`ToolDetailView` predicates and the `matches` search predicate are byte-identical to the base. Both
confirmed the executing-mutation early-return is unchanged and the sheets bind to preview/preparation,
never `selectedEntry`.

## Orchestrator gate results (D-014, independent rerun)

At candidate `64a5056` (fresh scratch `agent-lens-m12-a-orch`) and R1 `2ed3a77`
(`agent-lens-m12-a-r1orch`), `swift test --no-parallel` with the documented CLT TestingMacros flag:

- Full suite: **467 Core + 119 AppSupport = 586 passed, zero skips/failures**, exit 0 (R1; the
  pre-R1 candidate measured 467 + 118 = 585).
- Core/UI import guard: clean (32 Core files). AppSupport import guard
  (`--source-root Sources/AgentLensAppSupport`): clean (6 files, no SwiftUI/AppKit).
- Guard behavioral fixtures: 21 OK. Packaging checks: 9 OK. Dev app built. `git diff --check`: clean.
- Protected-file manifest: only the six allow-listed files changed at `64a5056`; R1 changed only
  `InventoryViewModelTests.swift` + the worker report (no production diff). No Core/CLI/registry/
  Package.swift/scripts/.github/fixture change.

## Requirement-to-evidence

| Ruling | Evidence |
|---|---|
| R1 invalidation (listScope/updateStatusFilter/searchText/selection invalidate; detailPane does not; executing never cancelled; sheets bind to preview) | `InventoryViewModel.swift` didSet hooks + `showPathEvidence`; one test per vector + seeded-corruption test + both executing-exemption tests; both reviews verified no missed vector |
| R2 Updates tri-state membership + status filter | `ListScope.updates.includes` excludes notInstalled; `UpdateStatusFilter` five cases; unknown never inflates `updateAvailableCount`; tests + reviews |
| R3 three conflict kinds, measured versions only, count counts tools | `ToolConflict.kinds(for:)` + record; positive/negative tests incl. closed `allCases` vocabulary; reviews |
| R4 ManagementPresentation reproduces controls; Core reason read not retyped | `ManagementPresentation` slots + `otherLimits`; codex/formula/cask/standalone tests; reviews compared line-by-line to `ToolDetailView` |
| R8 search predicate unchanged | `matches` byte-identical (not in diff); two-sided tests; reviews |
| R12 zero Core change; AppSupport UI-free | Core 467 unchanged; import guards clean; protected manifest; reviews |

## R1 corrections (low findings, no production change)

- **LOW-1 (both reviewers):** added `updateStatusFilterIsInertOutsideTheUpdatesScope` — under
  `listScope = .all`, `updateStatusFilter = .updateAvailable` keeps both tools listed; dropping the
  scope-conditioning guard fails the test.
- **Seeded-trigger comment:** corrected the backwards direction (a removed `listScope` hook makes the
  final assertion FAIL, not pass).
- **Worker-report slip:** floor sentence corrected 117 → 118 (now 119 after the R1 pin).
- **LOW-2 (both reviewers):** recorded as a documented Core coupling — Core publishes
  `shadowedInstallationCount == 0` for `.notInstalled` (`PathDiagnostics.swift:242-251`), so the
  production invariant holds; R3 stays as written (the pure function classifies the fields given).
  No code change.

## Limitations and forward notes (honest, carried forward)

- The app is visually unchanged by design; visual invariance is inferred from zero App diff, not
  observed (no native check this phase). M12-B is the first visible change.
- INFO (both): off-PATH + positive shadowed is synthetic (Core sets shadowed 0 for off-PATH); M12-C
  must not expect a live two-kind row.
- INFO (both): `ToolConflict.localVersions` is a flat unattributed list; M12-C's row display is
  limited to what A exposed (per-copy attribution would need an A revision).
- LOW-3/INFO-2 (both): the update slot's "newer version" sentence is new text relative to today's
  silent detail view; M12-D will surface it for the first time and must not displace/re-word the
  codex affordances.
- `updateStatusFilter` invalidates even outside `.updates` (R1's literal trigger list; safe
  over-release direction). M12-C/E must not assume it is inert outside Updates.
- `InventorySnapshot.swift` has no trailing newline (pre-existing, not introduced; diff --check clean).

## Owner authorizations

The owner pre-authorized the full M12 flow (implement → independent review → PR → owner merge
decision). M12-B dispatch proceeds under that authorization. **Merge to `main` is NOT authorized**
(M11 PR #2 and M12 both await the owner). OD-M12-1 (temporary Full Keyboard Access / VoiceOver /
appearance for the M8 keyboard gate, restored after) remains the one open owner gate, blocking M12-F
only. No release.

## Evidence index

`R = $HOME/.hermes/cache/scratch/agent-lens-m12-a` (worker) and `agent-lens-m12-a-orch` /
`agent-lens-m12-a-r1orch` (orchestrator reruns): `evidence/` (build/full-suite/guard/dev-app/packaging
logs + meta), `evidence/r1/`, `changed-files.sha256`, protected-manifest logs. Reviews:
`walkthroughs/M12-A-evidence/reviews/{minimax,grok}.md`. Worker report:
`walkthroughs/M12-A-implementation.md` (labeled worker evidence).