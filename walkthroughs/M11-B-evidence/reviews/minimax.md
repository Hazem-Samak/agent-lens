# M11-B — independent read-only review (MiniMax M3.1-Flash)

Reviewer: MiniMax M3.1-Flash (mcode), summoned by the orchestrator through Herdr/hc.
Candidate: commit `caae348` on `milestone/m11-catalogue`. Product diff: `git diff 5da1624..caae348`.
Spec: `briefs/M11-B-mutation-gate.md` (frozen, revision 1).

**Verdict: PASS** — 0 blocking defects, 1 medium finding that needs an orchestrator ruling, 6 low /
observation findings. The safety gap the phase targets is closed fail-closed on every path I could
reach. The one medium finding is a defect in the *frozen brief*, not in the candidate code; the
implementer detected it, reported it correctly, and declined to improvise.

---

## 1. Method

Read-only. No product file was edited, no Git mutation was performed, no subagent, provider or
install was used. The only file written is this report. Every claim below was re-derived from the
candidate source at `caae348`, not from `walkthroughs/M11-B-implementation.md`; the walkthrough was
read only to check its factual claims, and the other reviewer's file was not read.

Verification performed:

- Full read of the candidate diff (`git diff 5da1624..caae348`, 18 files) and of the changed
  product files at their candidate revision.
- Read of the full `NpmUpdateOperation` / `NpmUninstallOperation` prepare seams and every caller of
  `NpmUpdateOperation.*` / `NpmUninstallOperation.*` under `Sources/`.
- Read of `DetectorDefinition` (init, `init(from:)`, `CodingKeys`), `DetectorRegistry` schema
  handling, key allow-lists and the JSON parse path.
- Enumeration of every consumer of `NpmUpdateUnavailableReason` / `NpmUninstallUnavailableReason` to
  confirm the new case cannot be swallowed by a `default:` branch.
- Assertion-level diff of the test surface (added/removed `@Test`, removed `#expect`/`#require`).
- Independent re-read of the orchestrator's rerun logs under
  `/Users/corvette/.hermes/cache/scratch/agent-lens-m11-Jb11B5/evidence/b/parent-*.log`.

---

## 2. Findings

### F-1 — MEDIUM — The frozen brief's CLI-mirror clause (contract 7 / B-AC05) is unsatisfiable; it contradicts the frozen M10-C/M10-D contracts. Requires an orchestrator ruling.

`briefs/M11-B-mutation-gate.md:79-83` requires "`agent-lens/main.swift` update/uninstall paths render
the identical Core `message` for a refused operation", and B-AC05 (`:129`) asks the built CLI to
render that message "for an unaccepted npm-declared entry".

The shipping CLI has no mutation path to refuse. `Sources/agent-lens/main.swift` is the only CLI
source and dispatches exactly three commands — `scan` (`:62`), `verify-installation` (`:114`) and
`debug-env` (`:160`). There is no update or uninstall operation, no `NpmUpdateOperation.prepare`
call, and no `NpmUpdateUnavailableReason` / `NpmUninstallUnavailableReason` reference anywhere in
`Sources/agent-lens/main.swift`. `Package.swift:21` confirms `agent-lens` is the only executable
besides the SwiftUI app, and `Sources/agent-lens/` contains only `main.swift`.

This clause is not merely unmet — it conflicts with two frozen earlier contracts:

- `briefs/M10-D-npm-uninstall.md:78` — "No CLI mutation command exists; the shipping CLI remains
  read-only." (`briefs/M10-D-npm-uninstall.md:42` and `:240` repeat the exclusion.)
- `briefs/M10-C-npm-update.md:93` — "Do not add CLI mutation syntax. Use the shipping CLI only for
  read-only post-operation parity checks."

Satisfying contract 7 literally would have required adding CLI mutation syntax, which the M11-B
brief itself excludes ("no new operation type", `briefs/M11-B-mutation-gate.md:38`) and which
M10-C/M10-D forbid.

**The candidate's handling is correct.** `Sources/agent-lens/main.swift` is unchanged, no CLI
mutation syntax was invented, and the Core message strings are defined exactly once in
`Sources/AgentLensCore/Operations/OperationModels.swift:89` and `:334` and consumed as
`reason.message` everywhere. Leaving `main.swift` untouched is the only action consistent with the
frozen contracts; adding a CLI path would have been a scope violation and a safety regression.

**Why this is not a BLOCK:** there is no code defect to fix, and the implementer did not improvise
past the conflict — `walkthroughs/M11-B-implementation.md:109-118` (D-1) reports the clause as
unsatisfiable, states that B-AC05 cannot be evidenced as written, and asks for a ruling. That is
exactly the behaviour the brief's stop conditions and report contract require.

**Orchestrator action required:** accept the CLI clause as vacuous, or issue a revision brief naming
a read-only CLI surface (for example a refusal line in `verify-installation` output). B-AC05 must
not be recorded as evidenced either way.

### F-2 — LOW — The App mirror shows the reason text more broadly than contract 6 specifies (reported by the implementer as D-2).

`Sources/AgentLensApp/ToolDetailView.swift:284` renders the Uninstall refusal whenever
`entry.definition.acceptedOperations` lacks `.npmUninstall`, *before* and independently of the npm
ownership check at `:288`. Contract 6 (`briefs/M11-B-mutation-gate.md:74-78`) names the case
"when npm ownership is verified but the operation is not accepted".

This is a fail-closed broadening, not a loosening: the operation control is withheld in strictly
more cases, never fewer. It is also more truthful than the M10 text it replaces — the previous
"Verify Installation to enable Uninstall for this npm package." hint (`ToolDetailView.swift:306`)
promises that verification will enable Uninstall, which is no longer true for an unaccepted entry.
The update side (`:526`) stays inside its original visibility condition
(`updateStatus == .updateAvailable` and an npm package present), so the update reason is shown only
where the update control would have been offered.

The Verify-ownership control is untouched and its eligibility still derives only from
`entry.diagnostic.selection` (`ToolDetailView.swift:257-264`, passed through at `:250`) — it is not
gated by acceptance, exactly as contract 6 requires.

Not blocking: no control is offered for an unaccepted entry, no new section or state is introduced,
and the deviation is disclosed.

### F-3 — LOW — `acceptedOperations: null` is rejected, which is stricter than the sibling optional arrays (reported by the implementer as D-3).

`Sources/AgentLensCore/Detection/DetectorRegistry.swift:217-222` and `:1081-1086` reject a present
`null`, while other optional fields in the same decoders (for example `extraSearchRoots` at
`DetectorRegistry.swift:160`) treat `null` as absent.

Contract 2 (`briefs/M11-B-mutation-gate.md:47-50`) says "When present it must be an array of
strings … reject unknown values, duplicates, wrong types, and non-array values". A present `null`
is a non-array value, so rejection is the contract-correct reading. Absence alone yields `[]`.

Not blocking: the strictness direction is fail-closed — a `null` can never be silently read as
"no acceptance" *and* as "present" at once, and no input shape is accepted that the contract does
not name. Disclosed as D-3.

### F-4 — LOW — The two decode paths report different error granularity for a mixed-type element array.

For `"acceptedOperations":["npmUpdate",7]`:

- Codable path — `Sources/AgentLensCore/Detection/DetectorRegistry.swift:225-233` — reports
  `invalidField(field: "acceptedOperations", reason: "must be an array of accepted operation
  strings")`, because `container.decode([String].self)` fails as a whole.
- Registry JSON path — `DetectorRegistry.swift:1095-1104` — reports
  `invalidField(field: "acceptedOperations[1]", reason: "must be a string")`, because the element
  loop type-checks per index.

Both reject; both are named detector/field errors in the existing `DetectorRegistryError` style, as
contract 2 requires. The divergence is cosmetic (index granularity only) and both outcomes are
fail-closed. Worth noting only because a consumer matching on the field string would see two
different shapes for the same malformed input.

### F-5 — LOW — The SwiftUI mirror has no automated coverage; no App test target exists.

`Package.swift` defines `AgentLensCoreTests` and `AgentLensAppSupportTests` only — there is no
`AgentLensAppTests` target, and `Package.swift` is on the brief's DO-NOT-TOUCH list
(`briefs/M11-B-mutation-gate.md:116`). Consequently the `ToolDetailView` control-suppression and
static-text branches (`ToolDetailView.swift:284-287`, `:534-538`) are exercised only by code
inspection here and by the orchestrator's native spot-check (B-AC07).

Not blocking — the mirror is a 4-line view-level change over an already-tested ViewModel contract,
and it consumes `NpmUpdateUnavailableReason.operationNotAccepted.message` /
`NpmUninstallUnavailableReason.operationNotAccepted.message` directly, so no string copy can drift.
Recorded so the orchestrator weights B-AC07 accordingly: it is the *only* automated evidence for the
App mirror.

### F-6 — LOW — The new Core tests re-type the exact message literals instead of asserting only against the enum.

`Tests/AgentLensCoreTests/MutationAcceptanceGateTests.swift:155` and `:182` assert
`reason.message == "<literal>"` with the message re-typed from the brief. Contract 8
(`briefs/M11-B-mutation-gate.md:82-83`) asks for tests that "assert equality against the enum, not
re-typed copies".

The risk the parenthetical guards against — a surface rendering its own copy of the string that
drifts from Core — is absent here: the App and the AppSupport sheet both render `reason.message`
(`Sources/AgentLensApp/UpdateOperationView.swift:132`, `Sources/AgentLensApp/UninstallOperationView.swift:135`,
`Sources/AgentLensApp/ToolDetailView.swift:285`, `:535`), and no copy of either string exists
anywhere in `Sources/`. The same tests also assert the enum value itself
(`reason == .operationNotAccepted`), so enum equality is covered; the literal additionally pins the
brief's exact required wording, which would catch a Core-message drift.

Not blocking: the literal strengthens the check and there is no duplicated surface string for it to
mask. Noted for completeness against the letter of contract 8.

### F-7 — LOW — Three files outside the named allow-list were changed (reported by the implementer as D-4).

`Tests/AgentLensAppSupportTests/InventoryServiceTests.swift`,
`Tests/Fixtures/M10C/npm_update_acceptance.py` and `Tests/Fixtures/M10D/npm_uninstall_acceptance.py`.

Each change is a one-line addition of `"acceptedOperations":[...]` to an embedded synthetic
registry literal. The brief permits this class of change
(`briefs/M11-B-mutation-gate.md:108-109`: "Other existing test files ONLY for constructor/fixture
migration forced by the new initializer parameter … report any migration you must do"), and the
migration was reported. Without it the historical M10-C/M10-D harnesses would silently refuse at the
new gate and stop exercising the M10 behaviour they were written to exercise. No production file
outside the allow-list changed; `Package.swift`, `DECISIONS.md`, `ROADMAP.md`, `AGENT_LENS_SCOPE.md`,
`scripts/**`, `.github/**`, `Resources/**`, `docs/**`, `briefs/**` and the `Ownership/`, `Updates/`,
`Process/`, `Environment/`, `Diagnostics/` trees are all untouched (verified by path filter over the
candidate diff).

Not blocking.

---

## 3. Assessment against the orchestrator's five axes

### (1) Fail-closed correctness

**Both Core prepare seams are gated at the correct point.**

- `Sources/AgentLensCore/Operations/NpmUpdateOperation.swift:61-64` — cancellation check, then the
  acceptance guard, then the deadline/scratch-base resolution, then `NpmUpdateProbe.observeFresh`
  (`:78`), then `NpmScratchRoot.claim` (`:128`).
- `Sources/AgentLensCore/Operations/NpmUninstallOperation.swift:51-54` — cancellation check, then the
  acceptance guard, then scratch-base resolution (`:57`), then the selection observation (`:68`) and
  `NpmScratchRoot.claim` (`:77`).

In both seams the guard precedes every scratch-root claim, every observation, every ownership query
and every runner use, and it is the second statement — exactly the placement contract 4 requires
(`briefs/M11-B-mutation-gate.md:64-68`). A refusal launches no process and claims no scratch root.

**No bypass exists via Codable, the constructor, or an alternate entry point.**

- Vocabulary is closed and type-safe: `AcceptedOperation` is
  `String, Codable, Sendable, Equatable` with exactly `npmUpdate` / `npmUninstall`
  (`Sources/AgentLensCore/Detection/DetectorMetadata.swift:78-80`), matching contract 1 verbatim.
- The Swift initializer takes `[AcceptedOperation]` with default `[]`
  (`DetectorRegistry.swift:68`), so an invalid operation is inexpressible there, and existing
  direct constructions stay valid (contract 2).
- The Codable path validates: absent → `[]` (`DetectorRegistry.swift:239`), present-but-null
  rejected (`:217`), non-array rejected (`:225-233`), unknown value and duplicate rejected with
  indexed field names via the shared validator
  (`DetectorMetadata.swift:270-295`, called from `DetectorRegistry.swift:234`).
- The registry JSON path validates independently and rejects unknown value, duplicate, non-array,
  non-string element and null (`DetectorRegistry.swift:1076-1107`), sharing the same vocabulary
  validator, so the two paths cannot drift apart on what is valid.
- `execute` is reachable only through a gated `prepare`: `NpmUpdatePreparation.init` /
  `NpmUninstallPreparation.init` are `internal`
  (`Sources/AgentLensCore/Operations/OperationModels.swift:112`, `:357`), so the AppSupport module
  cannot fabricate one; the only production construction sites are inside `prepare`.
- No third mutation path exists: the only npm mutating argv builders are
  `NpmUninstallOperation.swift:594-602` and the update argument builder in `NpmUpdateOperation`, and
  a search of `Sources/` for a global npm install/uninstall argv found no other construction site.
- The AppSupport seam is guarded *before* any observation: `InventoryViewModel.prepareSelectedUpdate`
  (`Sources/AgentLensAppSupport/InventoryViewModel.swift:313-316`) and `prepareSelectedUninstall`
  (`:466-469`) check `entry.definition.acceptedOperations` and return before touching
  `updateGeneration`/`isPreparingUpdate`/the pipeline task, so no session capture, scan or service
  call occurs and no state is left stuck. `InventoryService` needed no change and got none
  (`Sources/AgentLensAppSupport/InventoryService.swift:335`, `:453` both route into the gated Core
  `prepare`).
- The two guards also fail closed against each other: the ViewModel guards on the *clicked* entry's
  definition while Core re-checks the *freshly loaded* registry definition
  (`InventoryService.swift:336`), so a divergence in either direction refuses rather than proceeds.

**The App UI withholds the controls.** `ToolDetailView.swift:526` suppresses the Update button and
`:284` suppresses the Uninstall button for unaccepted entries, with the reason text in their place.

### (2) codex M10 behaviour preserved, no test weakened

- Seed data is exactly as contracted: `codex` carries
  `"acceptedOperations": ["npmUpdate","npmUninstall"]`
  (`Sources/AgentLensCore/Detectors/DefaultDetectors.json:18`); `opencode` and `grok` are unchanged
  with the key absent → `[]` (contract 3).
- **Zero assertions were removed from the candidate diff.** An assertion-level diff of `Tests/`
  returns 0 removed `#expect`/`#require`/`assert`/`XCTAssert` lines. The only removed test lines are
  (a) the 14 embedded registry JSON literals, each replaced by the same literal plus the
  `acceptedOperations` key, (b) the two `versionQuery: .standard` argument lines, each replaced by
  the same argument plus the new parameter, and (c) one `MARK` comment relocated.
- **Zero tests were removed and zero were skipped.** 8 tests were added (5 in the new
  `MutationAcceptanceGateTests.swift`, 1 each in `DetectorRegistryTests`, `DetectorMetadataTests` and
  `InventoryViewModelTests`), matching the observed suite growth exactly: 456 → 463 Core
  (+7) and 79 → 80 AppSupport (+1) = 535 → 543.
- The migrations are *correct* rather than convenient: they give each M10 scenario the acceptance
  its scenario exercises — `["npmUpdate"]` for update scenarios, `["npmUninstall"]` for uninstall
  scenarios, and `["npmUpdate","npmUninstall"]` for the combined M10-D host
  (`Tests/Fixtures/M10D/npm_uninstall_acceptance.py:274`). A scenario whose fixture had been left
  without acceptance would have returned `.operationNotAccepted` instead of its intended reason and
  failed loudly, so no M10 test can be passing for the wrong reason.
- The pre-existing round-trip test `validDefinitionsRoundTripThroughCodable`
  (`Tests/AgentLensCoreTests/DetectorMetadataTests.swift`) now also proves acceptance survives
  encode/decode: it round-trips the *default* definitions and asserts `decoded == definitions`, and
  because `DetectorDefinition` is `Equatable` with `acceptedOperations` as a stored property
  (`DetectorRegistry.swift:50`), that equality is acceptance-sensitive — a dropped or reordered
  field would fail it.
- Nothing in the ownership verifier, latest probe, metadata cache, confirmation sheet, process
  runner or scratch cleanup was touched; the diff is confined to the allow-list plus the three
  reported fixture migrations.

### (3) Validation strictness

Contract 2 and B-AC01 are met on both decode paths:

| Input | Codable path | Registry JSON path | Result |
|---|---|---|---|
| absent | `[]` (`:239`) | `[]` (`:1080`) | valid |
| `[]` | `[]` | `[]` | valid |
| `["npmUpdate","npmUninstall"]` | accepted, declared order preserved | accepted, declared order preserved | valid |
| unknown value | `invalidField("acceptedOperations[0]", …)` | same | rejected |
| duplicate | `invalidField("acceptedOperations[1]", "duplicate operation 'npmUpdate'")` | same | rejected |
| non-array (string) | `invalidField("acceptedOperations", …)` | same | rejected |
| non-string element | `invalidField("acceptedOperations", …)` | `invalidField("acceptedOperations[1]", "must be a string")` | rejected (see F-4) |
| `null` | `invalidField("acceptedOperations", …)` | same | rejected (see F-3) |

- `schemaVersion` stays **2**: `DetectorRegistry.supportedSchemaVersion = 2`
  (`DetectorRegistry.swift:671`) with the comparison at `:802-804`; schema 1 and 3 remain rejected
  and the diff does not touch this code.
- Unknown keys remain rejected at every level: root keys (`rootKeys`, `:675-676`), detector keys
  (`definitionKeys`, `:676-680` — extended with `"acceptedOperations"`), the nested fixture keys,
  and the `DetectorDefinition.init(from:)` level check against
  `Set(CodingKeys.allCases)` (`DetectorRegistry.swift:148-152`), where `acceptedOperations` was
  added to `CodingKeys` (`:138`) so the new key is allowed while every other key is still rejected.
- The new field is genuinely optional and genuinely additive: `schemaVersion` was not bumped, no
  existing key changed meaning, and the diff adds no new registry entry.

### (4) AppSupport / App mirror correctness and reason-text identity

- **Single source of truth.** The two messages exist exactly once, in the Core enums
  (`Sources/AgentLensCore/Operations/OperationModels.swift:89` and `:334`), and are byte-identical
  to the strings quoted in contract 4. Every surface reads `reason.message`; a search of `Sources/`
  found **no re-typed copy** of either message. The AppSupport properties are typed with the Core
  enums directly (`InventoryViewModel.swift:126`, `:132`), so the typed reason — not a string —
  crosses the module boundary.
- **AppSupport (B-AC04).** `prepareSelectedUpdate` sets `updateUnavailableReason =
  .operationNotAccepted` and `prepareSelectedUninstall` sets `uninstallUnavailableReason =
  .operationNotAccepted`, both through the existing properties and the existing pattern
  (`InventoryViewModel.swift:313-316`, `:466-469`). The new permanent test
  `unacceptedEntryWithVerifiedOwnershipRefusesBothOperationsWithoutAPipeline`
  (`Tests/AgentLensAppSupportTests/InventoryViewModelTests.swift:1087`) proves the full B-AC04 shape
  on an entry with a *verified npm ownership observation*: both reasons set, `updatePreparation` and
  `updatePreview` nil, `isPreparingUpdate`/`isBusy` false, and the injected
  `OperationCommandRunner` invocation count at 0. No new phase, state or pipeline was added;
  `updateGeneration`/`uninstallGeneration` are untouched on the refusal path, and selection and
  invalidation semantics are unchanged.
- **App (contract 6).** The Update control is replaced by
  `NpmUpdateUnavailableReason.operationNotAccepted.message` in the existing caption/secondary style
  (`ToolDetailView.swift:534-538`); the Uninstall control likewise
  (`:284-287`). The existing unavailable-reason rendering is reused rather than duplicated — the
  operation sheets still render `reason.message` through their pre-existing
  `unavailableView` (`UpdateOperationView.swift:127-135`,
  `UninstallOperationView.swift:131-139`), and `MainWindow.swift:93` / `:118` pass the typed reason
  through unchanged. `UpdateOperationView` / `UninstallOperationView` needed no edit, exactly as the
  brief permits.
- The Verify-ownership control and its eligibility are unchanged (`ToolDetailView.swift:250`,
  `:257-264`) — see F-2.
- **CLI (contract 7) is the one unsatisfiable clause** — see F-1.

### (5) Scope drift beyond the allow-list

None beyond the three reported fixture migrations (F-7). The candidate touches 18 files: the 8
allow-listed production files, the 5 allow-listed modified test files plus the new
`MutationAcceptanceGateTests.swift`, the required `walkthroughs/M11-B-implementation.md`, and the
three forced fixture migrations. `Sources/agent-lens/main.swift` and
`Sources/AgentLensAppSupport/InventoryService.swift` are correctly untouched (the latter was
conditional in the allow-list and the reason did not need to flow through it, because the Core
refusal already returns the typed reason). No `Ownership/**`, `Updates/**`, `Process/**`,
`Environment/**`, `Diagnostics/**`, `Package.swift`, `scripts/**`, `Tests/Packaging/**`,
`.github/**`, `Resources/**`, root docs, historical briefs/walkthroughs, or
`docs/catalogue-identities.md` was modified. `DECISIONS.md` was correctly not edited (contract 2
reserves the schema-2 additive entry for the orchestrator). The working tree at `caae348` is clean.

---

## 4. Orchestrator evidence — independently re-read

From `/Users/corvette/.hermes/cache/scratch/agent-lens-m11-Jb11B5/evidence/b/`:

- `parent-02-suite.log` — "Test run with 463 tests in 0 suites passed after 87.916 seconds" and
  "Test run with 80 tests in 5 suites passed after 7.246 seconds". I grepped the log for real
  failure markers: **0** `✘`, **0** "recorded an issue", **0** skipped. The 18 naive matches for
  "failed"/"error:" are all test *names* (e.g. `failedPostLaunchRescanCannotLeaveASuccessfulOutcome`),
  each followed by `✔ … passed`. So 543 passed, 0 skipped, 0 failed — consistent with 535 + 8 new.
- `parent-01-build.log` — "Build complete!" (exit 0; only `ld: warning: search path … not found`
  linker warnings).
- `parent-03-guard.log` — "32 Swift file(s) under Sources/AgentLensCore; no SwiftUI/AppKit imports".
- `parent-04-guardfix.log` — "Ran 21 tests … OK".
- `parent-05-app.log` — "Build complete! (23.92 secs)" and the dev app bundle at
  `…/worker-b/parent-app/AgentLensApp-debug.app`.
- `parent-06-packaging.log` — "Ran 9 tests … OK".

All six gates exit 0, matching the brief's gate list (`briefs/M11-B-mutation-gate.md:138-145`) and
B-AC06.

The worker's own walkthrough claims that I re-checked and found **accurate**: the 8 added tests and
their distribution, the 543 total, the fixture-migration list and its "no assertions weakened or
removed" statement, the protected-file arithmetic (13 allow-listed modified files + 3 forced
migrations = 16 manifest mismatches, with the 2 new files correctly absent from the dispatch
manifest), and all four deviations D-1…D-4. I found no overstated or false claim in it.

---

## 5. Conclusion

**PASS.** The mutation surface is fail-closed per registry entry on every path I could reach: the
Core prepare seams refuse before any scratch-root claim, observation, ownership query or runner use;
the AppSupport ViewModel refuses before any pipeline starts; the App withholds the controls and
shows the Core message; the vocabulary is closed and cannot be widened by Codable, by the
constructor, or by an alternate entry point; `execute` cannot be reached without a gated `prepare`;
and no test was weakened, removed or skipped to make the gate pass. The M10 codex behaviour is
preserved through a correct, disclosed fixture migration.

One action is required before acceptance is recorded, and it is not a code change:

1. **Rule on F-1.** Accept the CLI-mirror clause (contract 7 / B-AC05) as vacuous — the shipping CLI
   is read-only by the frozen M10-C/M10-D contracts and has no mutation path to refuse — or issue a
   revision brief naming a read-only CLI surface. Either way, B-AC05 must not be recorded as
   evidenced, and the ruling should be captured as a DECISIONS entry alongside the schema-2
   additive-field entry.

The six low findings need no correction before acceptance; F-2 through F-4 are disclosed deviations
whose behaviour is fail-closed and contract-consistent, and F-5 through F-7 are coverage and
bookkeeping observations the orchestrator should weigh when scoping B-AC07's native spot-check.
