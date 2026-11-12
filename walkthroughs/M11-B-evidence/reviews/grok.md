# M11-B independent review — Grok

Verdict: **PASS**
Findings: **0**
Candidate: `caae348f9cebc5133d34a5b4ff4485c615a0ad0c` (`feat(safety): M11-B fail-closed mutation acceptance gate candidate`)
Diff reviewed: `git diff 5da1624..caae348` (18 files, +882/−25)
Spec: `briefs/M11-B-mutation-gate.md` (revision 1). Implementation walkthrough was not used as evidence. The other reviewer's file was not opened.

Orchestrator logs were read, not re-run. `parent-02-suite.log` records two passing runs: 463 Core tests, then 80 AppSupport tests (543). `parent-01-build.log` ends `Build complete!`. `parent-03-guard.log` and `parent-04-guardfix.log` are clean. `parent-06-packaging.log` is `Ran 9 tests` / `OK`. `parent-05-app.log` ends `Build complete!`. That is +7 Core and +1 AppSupport over the brief's 456+79 baseline, matching the seven new Core tests and one new AppSupport test. No existing test was deleted.

## 1. Fail-closed prepare seams

Both prepares return after the existing cancellation check and before scratch selection, observation, ownership, or runner use.

- `NpmUpdateOperation.prepare` (`Sources/AgentLensCore/Operations/NpmUpdateOperation.swift:61-64`) guards `acceptedOperations.contains(.npmUpdate)` and returns `.unavailable(.operationNotAccepted)`. Scratch base selection starts at line 66. `NpmUpdateProbe.observeFresh` is at line 78.
- `NpmUninstallOperation.prepare` (`Sources/AgentLensCore/Operations/NpmUninstallOperation.swift:51-54`) is the same for `.npmUninstall`. Scratch base selection starts at line 56. `selectionPair` / `FileIdentityObserver` / `NpmOwnershipProbe` start at line 68. `NpmScratchRoot.claim` is at line 77.

`NpmUpdatePreparation.init` and `NpmUninstallPreparation.init` are `internal` (`OperationModels.swift:112`, `:357`). `execute` only consumes a preparation those inits can build, and only `prepare` calls them. There is no second `prepare` overload. AppSupport `executeUpdate` / `executeUninstall` call Core `execute` and do not build a plan.

`InventoryViewModel.prepareSelectedUpdate` (`InventoryViewModel.swift:313-316`) and `prepareSelectedUninstall` (`:466-469`) return before `updateGeneration` / `uninstallGeneration` increment and before `service.prepareUpdate` / `prepareUninstall`. A refusal sets the existing `updateUnavailableReason` / `uninstallUnavailableReason` and starts no pipeline.

`InventoryService.prepareUpdate` / `prepareUninstall` were not changed and do not themselves test acceptance. They still refresh a local inventory and then call Core `prepare`. The product path does not reach them on refusal: the view model returns first, and Core `prepare` still refuses before runner use or scratch claim if the service is called directly. The brief allows leaving `InventoryService.swift` untouched when the reason does not have to flow through it. Toolbar actions (`MainWindow.swift:349-376`) are Rescan, Check Updates, and Refresh Updates only. List rows show a status badge (`ToolListView.swift:99-143`), not a prepare action.

Codable and the throwing initializer cannot grant an operation outside the enum. `AcceptedOperation` is `String`-raw with exactly `npmUpdate` and `npmUninstall` (`DetectorMetadata.swift:78-81`). `DetectorDefinition.init` takes `[AcceptedOperation] = []` (`DetectorRegistry.swift:64-68`); there is no public memberwise initializer. Duplicates are expressible only through that Swift array. `contains` does not treat a duplicate as a new operation, and both JSON parsers reject duplicates. Unknown strings are not constructible.

`init(from:)` (`DetectorRegistry.swift:145-240`) rejects unknown keys via `firstUnknownDetectorKey`, rejects JSON null, rejects non-`[String]` values, then calls `DetectorMetadataValidation.acceptedOperations`. Absent key decodes as `[]`. `validDefinitionsRoundTripThroughCodable` still requires encode/decode equality of `loadDefault()`, so a synthesized encode cannot drop `acceptedOperations` without failing that existing test.

## 2. Codex M10 behavior and fixture migrations

`DefaultDetectors.json` changes by one line. `codex` gains `"acceptedOperations": ["npmUpdate", "npmUninstall"]` (`DefaultDetectors.json:18`). `opencode` and `grok` do not contain the key (the only match in that file is line 18). `schemaVersion` remains 2.

Existing M10 suites were kept on the post-gate path by granting the operation their journey already performed. No assertion, timeout, skip, or expected outcome was edited.

- `NpmUpdateOperationTests.swift` fixture builder passes `acceptedOperations: [.npmUpdate]`.
- `NpmUninstallOperationTests.swift` fixture builder passes `acceptedOperations: [.npmUninstall]`.
- `InventoryServiceTests.swift` and `InventoryViewModelTests.swift` add the same key to the codex JSON used by the existing update or uninstall journey. The new view-model test uses a registry with the key absent and expects `.operationNotAccepted` for both prepares.
- `Tests/Fixtures/M10C/npm_update_acceptance.py` adds `"acceptedOperations":["npmUpdate"]` in both embedded registries.
- `Tests/Fixtures/M10D/npm_uninstall_acceptance.py` adds `npmUninstall` for the uninstall hosts and both operations for `CombinedHost`.

Those files are outside the named test list. The brief allows other existing test files only for a constructor or fixture migration. The Swift default `[]` keeps old call sites compiling, but a JSON codex fixture that omitted the key would now refuse inside `prepare` and fail the M10 journey. The edits are that migration and nothing else. `MutationAcceptanceGateTests.bundledCodexAcceptanceIsDataAndARemovedCopyRefusesBothOperations` loads bundled codex, checks both operations, then prepares a copy with acceptance removed and expects both refusals with zero runner calls. The gate is data on the definition, not a hardcoded tool id.

## 3. Validation strictness

`DetectorRegistry.supportedSchemaVersion` is still `2` (`DetectorRegistry.swift:671`). Schema 1 and 3 expectations in `DetectorRegistryTests` were not edited. `definitionKeys` adds only `acceptedOperations` (`:676-680`). Root, fixture, package, and version-query key sets are unchanged. `unknownKeysAreRejectedAtRootDefinitionFixturePackageAndQueryLevels` was not weakened.

Both parsers share `DetectorMetadataValidation.acceptedOperations` (`DetectorMetadata.swift:270-296`): unknown raw value → `acceptedOperations[index]` "must be one of npmUpdate, npmUninstall"; duplicate → `acceptedOperations[index]` "duplicate operation". Absent and `[]` become `[]`.

`DetectorRegistry.validate` (`parseAcceptedOperations`, `DetectorRegistry.swift:1076-1107`) rejects `NSNull`, non-arrays, and non-string elements (`acceptedOperations[index]` "must be a string") before vocabulary checks. `init(from:)` rejects null and any value that is not a string array with field `acceptedOperations` "must be an array of accepted operation strings", then the shared vocabulary check. A mixed array such as `["npmUpdate", 7]` therefore names `acceptedOperations[1]` on the JSONSerialization path and the whole field on the Codable path. Both fail closed with a named detector field. Tests cover absent, empty, both legal values, unknown value, duplicate, string, null, and a numeric element on each path.

## 4. AppSupport / App mirror and reason text

Messages match the brief exactly and live only on the enums:

- Update, `OperationModels.swift:89`: `Update is not yet accepted for this tool. Agent Lens detects it, but no managed update has been verified for it.`
- Uninstall, `OperationModels.swift:334`: `Uninstall is not yet accepted for this tool. Agent Lens detects it, but no managed uninstall has been verified for it.`

`ToolDetailView` reads those `message` properties (`:285`, `:535`). It does not retype them. `UpdateOperationView.unavailableView` and `UninstallOperationView.unavailableView` already render `reason.message` (`UpdateOperationView.swift:132`, `UninstallOperationView.swift:136`), so a view-model refusal presented through `isUpdateSheetPresented` / `isUninstallSheetPresented` uses the same string. Those sheets did not need an edit.

Update control: the Prepare Update button still appears only for `.updateAvailable` with an npm package, and only if `.npmUpdate` is accepted (`ToolDetailView.swift:523-538`). Otherwise that same site shows the Core update message. Codex still gets the button.

Uninstall control: the destructive button still requires `.npmUninstall` plus verified npm plus a selected installation (`:284-309`). The Manage section is already limited to a declared npm package (`:96-98`). Verify Installation stays in `ownershipSection` (`:245-264`); `canVerifyOwnership` was not changed. Codex verified npm still gets the Uninstall button. Codex without acceptance removed is what the new Core test refuses.

Unaccepted npm-declared tools show the uninstall message even before ownership is verified, where the old copy was "Verify Installation to enable Uninstall for this npm package." That hint would now be false, because verification would not enable the control. The Verify button itself is unchanged. This is the truthful informational state the goal requires, not a second mutation path.

`agent-lens/main.swift` is unchanged. Its commands are `scan`, `verify-installation`, and `debug-env` (`main.swift:61-174`). There is no CLI update or uninstall mutation command whose renderer could diverge or bypass the gate. Scan flags, dispatch, and cache use are byte-identical. B-AC05's "identical Core message" has no CLI mutation surface to render; adding one would be a new command. Latest-check remains the existing read-only probe.

## 5. Scope

Production edits are only the allow-listed files: `DetectorMetadata.swift`, `DetectorRegistry.swift`, `DefaultDetectors.json`, `OperationModels.swift`, `NpmUpdateOperation.swift`, `NpmUninstallOperation.swift`, `InventoryViewModel.swift`, `ToolDetailView.swift`. No edits under `Ownership/`, `Updates/`, `Process/`, `Environment/`, `Diagnostics/`, `Package.swift`, `scripts/`, `Tests/Packaging/`, `.github/`, or root docs. `InventoryService.swift`, `UpdateOperationView.swift`, `UninstallOperationView.swift`, and `main.swift` stayed as they were, for the reasons above.

Out-of-list test edits are the fixture migrations in section 2, plus the new `MutationAcceptanceGateTests.swift` and the new cases in the named registry, metadata, and view-model test files. `walkthroughs/M11-B-implementation.md` is the allowed worker report.

## Acceptance matrix (code, not the worker report)

| ID | Result |
|---|---|
| B-AC01 | Met. Absent/empty/valid accepted; unknown, duplicate, null, non-array, and bad element rejected with a named field. Schema 1/3 and unknown-key tests untouched. |
| B-AC02 | Met. Both prepares return `.operationNotAccepted` before scratch and runner use. Counting-runner tests expect zero invocations and an empty operation base. Messages are the enum strings. |
| B-AC03 | Met. Bundled codex carries both operations. Existing M10 suites keep their assertions and now pass acceptance into the same journeys. A codex copy with acceptance removed refuses both operations. |
| B-AC04 | Met. View model sets the existing reason properties and does not start a pipeline. New test uses verified npm ownership, an empty acceptance list, and zero operation-runner calls. Selection invalidation code was not modified. |
| B-AC05 | Met for the CLI that exists. No mutation command. Scan/update flags unchanged. App and view model render the Core enum message. |
| B-AC06 | Orchestrator logs cited above: build, 543 tests, import guards, dev app, 9 packaging checks. This review did not re-execute them. Diff scope is the allow-list plus the fixture migrations in section 2. |
| B-AC07 | Not claimed. Native spot-check stays with the orchestrator. Code path: codex with both operations still reaches the existing controls; opencode (npm declared, key absent) has no prepare/uninstall button; grok has no declared npm package so the Manage section is not built. |
