# M11-B — mutation acceptance gate (dispatch brief)

Status: authorized under the owner-approved M11 plan (2026-11-12). Worker brief, not acceptance
evidence. Freeze this revision once dispatched; corrections use a separate revision brief.

## Identity and authority

- Phase: M11-B, revision 1. Milestone branch: `milestone/m11-catalogue`.
- HEAD baseline: `c48b2262165186c23917fadb2de45586fecc6450` (M11-A accepted). Fresh parent
  baseline at dispatch: 456 Core + 79 AppSupport = 535 tests, exit 0
  (`E/evidence/baseline.log` from M11-A dispatch).
- Sole implementer: **DeepSeek V4.1 Flash 1017 via OMP** (`river/deepseek-ai/DeepSeek-V4.1-Flash-1017`,
  `--thinking max`), owner-selected. No other implementer, subagent, provider, model or CLI.
- **Independent read-only review is MANDATORY for this phase** (ROADMAP §5.4, mutation contract):
  MiniMax M3.1-Flash/xhigh (mcode) and Grok 4.7/high (grok CLI), summoned by the orchestrator
  through Herdr/hc after the candidate is frozen. Reviewers never edit; findings return here as a
  revision brief.
- Orchestrator owns acceptance, the native spot-check, and all Git delivery. **Do not stage,
  commit, branch, reset, merge, push, or publish.**
- Evidence root `R`: `/Users/corvette/.hermes/cache/scratch/agent-lens-m11-Jb11B5`. Use
  `R/worker-b`, `R/tmp` (TMPDIR), `R/evidence/b`. Never put scaffolds in the repository.
- Authority: `briefs/M11-plan.md` §5 M11-B and ruling R1 in `briefs/M11-planning/judgment.md`;
  `docs/catalogue-identities.md` (frozen; mutation rules section). Do not read the full scope doc.

## Goal and exclusions

Close the verified safety gap: today any detector declaring an npm candidate becomes eligible for
the M10 Update/Uninstall workflow once npm ownership verifies
(`InstallationOwnershipVerifier.verifyNpm` is generic; `InventoryViewModel` and `ToolDetailView`
gate controls only on `verifiedInstallation.manager == .npm`). After this phase, mutation
eligibility is **fail-closed per entry**: only detectors whose registry definition carries
accepted operations may prepare or offer Update/Uninstall. `codex` keeps its M10-accepted
behavior exactly; every other entry is informational with a truthful reason.

Exclusions: no new catalogue entries (M11-C/D/E own those); no ownership-verifier behavior
change; no latest-probe change (latest-check stays available per M6/M10-B — it is read-only
diagnostics); no new layout/source/manager vocabulary; no confirmation-journey redesign; no new
operation type; no category navigation or other M12 UI; no CI floor/anchor change in this phase;
no dependency; no license file.

## Behavioral contract

1. **Vocabulary.** New public `AcceptedOperation` enum in `DetectorMetadata.swift`:
   `String, Codable, Sendable, Equatable`, cases `npmUpdate`, `npmUninstall` (raw values exactly
   those strings). Closed vocabulary; nothing else is expressible.
2. **Registry field.** `DetectorDefinition.acceptedOperations: [AcceptedOperation]`.
   - JSON: optional key `acceptedOperations`; absent → `[]`. When present it must be an array of
     strings from the closed vocabulary; reject unknown values, duplicates, wrong types, and
     non-array values with named detector/field errors in the existing `DetectorRegistryError`
     style. Empty array is valid and means no accepted operations.
   - Swift initializer: new parameter with default `[]` so existing direct constructions stay
     valid; invalid values must be impossible to express through the enum.
   - `schemaVersion` stays **2** (additive optional field). Schema 1 and 3 remain rejected;
     unknown keys at every level remain rejected. The additive change is recorded by the
     orchestrator as a new DECISIONS entry at acceptance — do not edit DECISIONS.md yourself.
3. **Seed data.** In `DefaultDetectors.json`, `codex` gains
   `"acceptedOperations": ["npmUpdate", "npmUninstall"]`. `opencode` and `grok` are unchanged
   (key absent). No other registry change.
4. **Core gate (authoritative).** Add `case operationNotAccepted` to BOTH
   `NpmUpdateUnavailableReason` and `NpmUninstallUnavailableReason` in `OperationModels.swift`,
   each with a `message`:
   - update: `"Update is not yet accepted for this tool. Agent Lens detects it, but no managed update has been verified for it."`
   - uninstall: `"Uninstall is not yet accepted for this tool. Agent Lens detects it, but no managed uninstall has been verified for it."`
   In `NpmUpdateOperation.prepare` and `NpmUninstallOperation.prepare`, immediately after the
   initial cancellation check and **before** any scratch-root claim, observation, ownership
   query, or runner use:
   `guard definition.acceptedOperations.contains(.npmUpdate /* or .npmUninstall */) else { return .unavailable(.operationNotAccepted) }`.
   A refusal launches zero processes and claims no scratch root. No other prepare logic changes.
5. **AppSupport mirror.** In `InventoryViewModel`, the update preparation guard
   (`prepareSelectedUpdate`) and the uninstall preparation guard gain the acceptance check on
   `entry.definition`; a refusal sets the existing unavailable-reason property
   (`updateUnavailableReason` / the uninstall equivalent) to `.operationNotAccepted` through the
   existing pattern. No new phase, state, or pipeline. Selection/invalidations semantics unchanged.
6. **App mirror.** In `ToolDetailView` (and `UpdateOperationView`/`UninstallOperationView` only
   as needed), when npm ownership is verified but the operation is not accepted, show the
   Core `message` as static informational text in the existing native style instead of the
   operation control. The Verify-ownership control and its eligibility are unchanged. Existing
   unavailable-reason rendering is reused, not duplicated. No other UI change.
7. **CLI mirror.** `agent-lens/main.swift` update/uninstall paths render the identical Core
   `message` for a refused operation. Existing flags, dispatch, scan modes, and cache rules
   unchanged.
8. **Identity of reason text.** CLI and app show the exact Core `message` strings (tests assert
   equality against the enum, not re-typed copies).
9. **Preserved behavior.** With `codex` seeded, every existing M10 update/uninstall test passes
   without weakening. Ownership verification, latest probes, metadata cache, confirmation
   sheets, process runner, and scratch cleanup are untouched.

## Allow-list

Production:
- `Sources/AgentLensCore/Detection/DetectorMetadata.swift`
- `Sources/AgentLensCore/Detection/DetectorRegistry.swift`
- `Sources/AgentLensCore/Detectors/DefaultDetectors.json`
- `Sources/AgentLensCore/Operations/OperationModels.swift`
- `Sources/AgentLensCore/Operations/NpmUpdateOperation.swift`
- `Sources/AgentLensCore/Operations/NpmUninstallOperation.swift`
- `Sources/AgentLensAppSupport/InventoryViewModel.swift` (and `InventoryService.swift` only if
  the reason must flow through it — report why)
- `Sources/AgentLensApp/ToolDetailView.swift`, `UpdateOperationView.swift`,
  `UninstallOperationView.swift` (reason surfacing only)
- `Sources/agent-lens/main.swift` (reason rendering only)

Tests:
- `Tests/AgentLensCoreTests/DetectorRegistryTests.swift`, `DetectorMetadataTests.swift`,
  `NpmUpdateOperationTests.swift`, `NpmUninstallOperationTests.swift`
- New `Tests/AgentLensCoreTests/MutationAcceptanceGateTests.swift`
- `Tests/AgentLensAppSupportTests/InventoryViewModelTests.swift`
- Other existing test files ONLY for constructor/fixture migration forced by the new initializer
  parameter (default `[]` should make this unnecessary; report any migration you must do).

Documentation:
- Add `walkthroughs/M11-B-implementation.md` — worker report, clearly labeled worker evidence,
  not acceptance.

DO NOT TOUCH: everything else — `Ownership/**`, `Updates/**`, `Process/**`, `Environment/**`,
`Diagnostics/**`, app navigation/list/detail beyond the named views, `Package.swift`,
`scripts/**`, `Tests/Packaging/**`, `.github/**`, `Resources/**`, root docs, historical
briefs/walkthroughs, `docs/catalogue-identities.md` (frozen), personal installations, the real
Agent Lens cache, credentials. If another file is genuinely required, stop and report.

## Acceptance matrix

| ID | Scenario | Expected observation |
|---|---|---|
| B-AC01 | Registry validation: absent/empty/valid `acceptedOperations`; unknown value, duplicate, non-array, wrong element type; schema 1/3; unknown keys | Valid loads (absent→[]); each invalid shape rejected with a named detector/field error; existing rejection behavior unchanged |
| B-AC02 | Synthetic npm-verified definition WITHOUT acceptance, injected counting runner, both prepares | `.unavailable(.operationNotAccepted)`; zero runner invocations; no scratch root claimed; message equals the Core enum string |
| B-AC03 | Codex with seeded acceptance: existing M10 update/uninstall suites; a test copy of codex with acceptance removed | All existing tests pass unweakened; removed-acceptance copy refuses both operations (gate is data-driven, not hardcoded per tool) |
| B-AC04 | AppSupport: unaccepted entry with verified npm ownership prepares update/uninstall | Existing unavailable-reason property set to `.operationNotAccepted`; no pipeline starts; selection/invalidation tests still pass |
| B-AC05 | Built CLI: update path for an unaccepted npm-declared entry; existing scan/update flags | Identical Core message rendered; dispatch/flags/quiet rules unchanged |
| B-AC06 | Full gates: `swift build`, `swift test --no-parallel`, import guards, fresh dev app, 9 packaging checks; protected-file hashes | All exit 0; 535+ tests, zero skips/failures; no scope drift |
| B-AC07 | Orchestrator native spot-check (worker does NOT claim this): built app, controlled disposable npm environment per M10 pattern | Codex Verify→Update/Uninstall journey intact; opencode/grok details offer no mutation controls; reason text observed where reachable |

Permanent tests exercise behavior and boundaries, not source text or existence-only checks.
Deterministic isolation; no global environment mutations in parallel tests.

## Exact gates and evidence

```sh
env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS swift build
env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS swift test --no-parallel
python3 scripts/check-core-ui-imports.py
python3 Tests/Packaging/test_core_ui_imports.py
python3 scripts/build-dev-app.py --scratch-root R/worker-b/app --configuration debug
python3 Tests/Packaging/test_dev_app_bundle.py --app R/worker-b/app/AgentLensApp-debug.app
```

Capture exact argv, raw stdout/stderr, exit codes, durations under `R/evidence/b`. SHA-256 of
every changed file; compare protected files against the dispatch manifest. The orchestrator
reruns everything independently and freezes the candidate for the two mandatory reviews.

## Stop conditions

Stop and report (do not improvise) if: the gate cannot be enforced without changing M10
confirmation semantics; the reason text cannot be identical in CLI and app; an out-of-allow-list
file seems required; any ownership/probe/coordinator change seems required; a test outside the
allow-list fails for a reason you cannot migrate within it; anything asks for credentials or
privileges.

## Report contract

When done — or stuck — send:

```sh
hc send t7x "M11-B complete: gate candidate ready — <tests count, gates passed, deviations, open items>"
```

The walkthrough plus raw evidence is the deliverable; the message is a pointer and summary.
Report every deviation explicitly; never silently broaden scope.