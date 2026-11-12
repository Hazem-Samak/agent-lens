# M11-B — mutation acceptance gate: worker implementation report

Status: **worker evidence, revision 1, 2026-11-12.** This is the implementer's report, not
acceptance. The orchestrator reruns every gate independently, performs the native spot-check, and
owns all Git delivery. No Git mutation was performed by this worker.

- Phase: M11-B, revision 1, dispatch brief `briefs/M11-B-mutation-gate.md`.
- Branch: `milestone/m11-catalogue`. Dispatch HEAD: `5da1624` (M11-B brief); product baseline
  `c48b226` (M11-A accepted).
- Sole implementer: DeepSeek V4.1 Flash 1017 via OMP. No subagent, provider, model, or other CLI
  was used.
- Evidence root `R`: `/Users/corvette/.hermes/cache/scratch/agent-lens-m11-Jb11B5`.
  Worker evidence is under `R/evidence/b`; the development app is under `R/worker-b/app`.

## What changed

The mutation surface is now fail-closed per registry entry: preparation refuses before any
observation, ownership query, scratch claim, or process launch unless the definition carries the
matching accepted operation.

- `AcceptedOperation` closed vocabulary (`npmUpdate`, `npmUninstall`) added to
  `DetectorMetadata.swift`.
- `DetectorDefinition.acceptedOperations: [AcceptedOperation]` with JSON key
  `acceptedOperations`, default `[]` in the Swift initializer. JSON validation rejects unknown
  values, duplicates, non-array values, non-string elements, and `null` with named detector/field
  errors. Schema stays 2; unknown keys remain rejected at every level.
- Bundled `codex` seeds `["npmUpdate", "npmUninstall"]`; `opencode` and `grok` remain unchanged
  (key absent → `[]`).
- Core authoritative gate inserted immediately after the initial cancellation check in
  `NpmUpdateOperation.prepare` and `NpmUninstallOperation.prepare`.
- `NpmUpdateUnavailableReason.operationNotAccepted` and
  `NpmUninstallUnavailableReason.operationNotAccepted` added with the exact contract messages.
- `InventoryViewModel.prepareSelectedUpdate` / `prepareSelectedUninstall` mirror the check on
  `entry.definition` and set the existing unavailable-reason properties. No new phase, state, or
  pipeline.
- `ToolDetailView` shows the exact Core message as static informational text where the Update or
  Uninstall control would be offered. The Verify-ownership control and its eligibility are
  unchanged. `UpdateOperationView` / `UninstallOperationView` already render `reason.message`
  through their existing unavailable view, so they required no edit.
- `Sources/agent-lens/main.swift`: **unchanged.** See deviation D-1.
- `InventoryService.swift`: **unchanged.** The Core refusal already flows back as
  `.unavailable(.operationNotAccepted)`; the ViewModel guard refuses earlier without starting a
  pipeline, so no service change was needed.

## Tests

Added 8 permanent tests (Core +7, AppSupport +1). Total suite: **543 passing, 0 skipped,
0 failed** (463 Core + 80 AppSupport; baseline 456 + 79 = 535).

- `Tests/AgentLensCoreTests/MutationAcceptanceGateTests.swift` (new, 5 tests):
  unaccepted Update refusal; unaccepted Uninstall refusal; per-operation independence;
  gate-before-scratch-order proof; bundled codex accepted and a data-only copy with acceptance
  removed refusing both operations. Each refusal asserts `.operationNotAccepted`, the exact Core
  message, zero injected-runner invocations, and an empty operation base.
- `DetectorRegistryTests.swift`: seeded codex operations; optional/empty/valid shapes; unknown,
  duplicate, non-array, wrong-element, and null rejections with named fields.
- `DetectorMetadataTests.swift`: default `[]`, explicit preservation, Codable round-trip, and
  fail-closed decoding of malformed shapes.
- `InventoryViewModelTests.swift`: an unaccepted npm entry with a **verified npm ownership
  observation** refuses Update and Uninstall through the existing reason properties, starts no
  pipeline, and never invokes the operation runner.

Forced fixture migration (no assertions weakened or removed):

- `NpmUpdateOperationTests.swift` / `NpmUninstallOperationTests.swift`: synthetic fixtures now
  declare their matching accepted operation.
- `InventoryViewModelTests.swift` and `InventoryServiceTests.swift`: synthetic registry JSON for
  the M10-C/M10-D scenarios now declares the operation each scenario exercises.
- `Tests/Fixtures/M10C/npm_update_acceptance.py` and
  `Tests/Fixtures/M10D/npm_uninstall_acceptance.py`: their embedded synthetic definitions now
  declare the matching accepted operation, so the historical M10 controlled harnesses still
  express an accepted scenario instead of silently refusing at the new gate.

## Gates run (worker evidence)

All commands ran from the repository root with `TMPDIR=R/tmp` and
`AGENT_LENS_TEST_SCRATCH` / `AGENT_LENS_TEST_PRODUCTS` unset. Raw logs and metadata:
`R/evidence/b/01…08`.

| Gate | Exact argv | Exit | Duration | Observation |
|---|---|---|---|---|
| Build | `env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS swift build` | 0 | 23 s | `Build complete!`; linker search-path warnings only |
| Full suite | `env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS swift test --no-parallel` | 0 | 96 s | 463 Core + 80 AppSupport = 543 passed; zero skips/failures |
| Import guard | `python3 scripts/check-core-ui-imports.py` | 0 | <1 s | 32 Core files; no SwiftUI/AppKit imports |
| Guard fixtures | `python3 Tests/Packaging/test_core_ui_imports.py` | 0 | 1 s | 21 tests OK |
| Dev app | `python3 scripts/build-dev-app.py --scratch-root R/worker-b/app --configuration debug` | 0 | 26 s | `R/worker-b/app/AgentLensApp-debug.app` |
| Packaging | `python3 Tests/Packaging/test_dev_app_bundle.py --app R/worker-b/app/AgentLensApp-debug.app` | 0 | 2 s | 9 tests OK |

## Protected-file comparison

`sha256sum -c R/evidence/protected-manifest.txt` exits 1 with exactly 16 mismatches. All are
expected:

- 13 allow-listed production/test files changed.
- 3 forced fixture migrations outside the named allow-list:
  `Tests/AgentLensAppSupportTests/InventoryServiceTests.swift`,
  `Tests/Fixtures/M10C/npm_update_acceptance.py`,
  `Tests/Fixtures/M10D/npm_uninstall_acceptance.py`.
- `Sources/agent-lens/main.swift` is **OK** (unchanged), as are `Package.swift`, `DECISIONS.md`,
  `ROADMAP.md`, `AGENT_LENS_SCOPE.md`, CI, scripts, packaging tests, and all other protected files.
- New files absent from the dispatch manifest: `MutationAcceptanceGateTests.swift` and this report.

Per-file SHA-256: `R/evidence/b/08-changed-file-sha256.txt`. Git status:
`R/evidence/b/07-git-status.txt` (working-tree entries only; no commit, branch, stage, reset, merge,
push, or publish was performed).

## Deviations and interpretations

**D-1 (CLI mirror has no surface).** The brief's contract 7 and B-AC05 describe
`agent-lens/main.swift` update/uninstall paths rendering the refused operation message. No such
CLI path exists: the shipping CLI has only `scan`, `verify-installation`, and `debug-env`, and
M10-D's accepted contract states "No CLI mutation command exists; the shipping CLI remains
read-only." Adding CLI mutation syntax would contradict M10-D and M11's no-new-operation
exclusion. `main.swift` is therefore unchanged, and B-AC05 cannot be evidenced as written. The
exact Core message strings are defined once in `OperationModels.swift`; the app's existing
unavailable views and the detail-view informational text consume `reason.message` directly. This
needs an orchestrator ruling: accept the vacuous CLI clause or issue a revision brief that names a
read-only CLI surface.

**D-2 (detail-view reason is broader than the verified case).** Contract 6 names the
verified-ownership case. The implementation shows the Uninstall reason for any declared-npm entry
whose definition lacks `npmUninstall` (verified or not), and the Update reason whenever an npm
update is available but not accepted. This is the truthful state — Verify cannot enable an
operation that the registry never grants — and keeps the Verify control itself unchanged.

**D-3 (`null` is rejected).** `acceptedOperations: null` is a present non-array value and is
rejected; absence alone yields `[]`. Existing optional arrays treat `null` as absent, but the
brief says "when present it must be an array," so this field is stricter and fail-closed.

**D-4 (forced migrations).** The three fixture files in "Forced fixture migration" are outside
the named allow-list but fall under the test/fixture migration allowance. No production file
outside the allow-list changed.

## Not claimed / open items

- B-AC07 native spot-check is orchestrator-owned and was not performed by this worker.
- Independent read-only review (MiniMax M3.1-Flash/xhigh, Grok 4.7/high) is pending by design.
- The schema-2 additive-field DECISIONS entry is orchestrator-owned; `DECISIONS.md` was not
  edited.
- No review of `opencode`/`grok` runtime UI was performed beyond the compiled views and the
  AppSupport behavior tests; the dev app launched only through the builder/packaging checks.
