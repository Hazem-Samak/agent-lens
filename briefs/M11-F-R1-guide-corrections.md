# M11-F-R1 — contributor guide correction (revision brief)

Status: authorized orchestrator revision under the accepted M11 process. Returns the single LOW
finding from the Grok independent review of M11-F candidate `d3f0324` to the sole implementer.
Freeze this revision once dispatched.

## Identity and authority

- Phase: M11-F, revision R1. Branch: `milestone/m11-catalogue`. Base: `d3f0324` (frozen F candidate).
- Sole implementer: DeepSeek V4.1 Flash 1017 via OMP (`river`), max reasoning. No subagents/other CLIs.
- Orchestrator owns acceptance and Git delivery. **No git mutations by the worker.**
- Evidence root `R`: `/Users/corvette/.hermes/cache/scratch/agent-lens-m11-Jb11B5` (`R/evidence/f-r1`).
- Finding source: `walkthroughs/M11-F-evidence/reviews/grok.md` finding 1 (LOW). Both reviews are
  otherwise PASS; no other finding requires a code change.

## Failed requirement

M11-F brief Deliverable 4: the contributor guide must state the EXACT files to edit for a new tool
on an existing layout. `docs/CONTRIBUTING.md` (the edit list near lines 13–27) omits
`Tests/AgentLensCoreTests/CapabilityMatrixTests.swift`.

## Reproduction

`dataOnlyContributionLoadsExtraToolWithoutProductionChange` asserts
`productionIDs == frozenCatalogue` (the hardcoded fourteen-id list,
`CapabilityMatrixTests.swift:450-456` and the later re-check). A contributor who follows the guide
and adds a fifteenth tool — updating `DefaultDetectors.json`, the named id-list tests, the matrix
row, and the README sentence — still fails this test until `frozenCatalogue` is updated. The guide
names every other hardcoded id list but not this one.

## Correction (bounded)

1. `docs/CONTRIBUTING.md`: add `Tests/AgentLensCoreTests/CapabilityMatrixTests.swift` to the
   edit list, naming BOTH obligations: the `frozenCatalogue` id list in the contribution-proof
   test, and the new row in `docs/capability-matrix.md` (already listed) — i.e. make the list
   complete and truthful. Keep the guide's existing structure, license-pending stance, and
   commands unchanged.
2. `walkthroughs/M11-F-implementation.md`: correct the F-AC07 evidence-provenance wording flagged
   by MiniMax INFO-4 — the captured `git-status-after.txt` snapshot shows the six allow-listed
   paths only; the report file itself was written after that snapshot. State that accurately.
   No other report change.

## Allow-list

- `docs/CONTRIBUTING.md`
- `walkthroughs/M11-F-implementation.md`

DO NOT TOUCH: everything else — no test change (the test is correct; the guide was incomplete),
no registry/matrix/ci.yml/README/Sources change, no historical briefs/walkthroughs, no LICENSE.

## Rerun gates

```sh
env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS swift test --no-parallel --filter CapabilityMatrix
```

(plus the plugin-path flag if the CLT-only TestingMacros failure appears; record both runs).
The full suite is orchestrator-rerun at acceptance. Evidence under `R/evidence/f-r1`; SHA-256 of
the two changed files; protected-manifest comparison.

## Report contract

```sh
hc send t7x "M11-F-R1 complete: guide corrected — <files changed, gate result>"
```