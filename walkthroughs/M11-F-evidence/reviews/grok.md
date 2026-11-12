# M11-F independent review — Grok

Reviewer: Grok 4.7 (read-only). Candidate: `d3f0324292c392af0037ec8398df129451b01ada` on `milestone/m11-catalogue`. Product range: `62aa642..d3f0324` (one commit). Spec: `briefs/M11-F-matrix-contributor.md`. Limit source: `docs/catalogue-identities.md`. Carry-forward: `walkthroughs/M11-D-acceptance.md`.

**Verdict: PASS.** 0 blocking, 0 high, 0 medium, 1 low.

Checked the diff, the registry JSON, the validator, the matrix parser and agreement function, the collision scanner, `ci.yml`, and the orchestrator logs under `R/evidence/f/parent-*.log`. The worker report was not used as evidence.

## Scope

`git diff --name-status 62aa642..d3f0324` is exactly the allow-list:

- `.github/workflows/ci.yml` (floor numbers and the M11-F floor comments)
- `README.md` (catalogue/contributing links; the fourteen-id sentence is unchanged and still lists `codex` through `qodercli`)
- `Tests/AgentLensCoreTests/CapabilityMatrixTests.swift` (added)
- `Tests/AgentLensCoreTests/DetectorRegistryTests.swift` (seeded-control extension only)
- `docs/CONTRIBUTING.md` (added)
- `docs/capability-matrix.md` (added)
- `walkthroughs/M11-F-implementation.md` (added)

No `Sources/**` change. No `Package.swift`, `scripts/**`, `Tests/Packaging/**`, `Resources/**`, or `docs/catalogue-identities.md` change. No `LICENSE` file.

## 1. Matrix truth

`docs/capability-matrix.md` has one header, one separator, and fourteen data rows. Every data line has ten pipes (nine cells). A cell-by-cell compare against `Sources/AgentLensCore/Detectors/DefaultDetectors.json` found no mismatch:

- Order is the registry order, each id once: `codex`, `opencode`, `grok`, `claude`, `gemini`, `cline`, `hermes`, `aider`, `goose`, `kiro-cli`, `omp`, `agy`, `dsh`, `qodercli`.
- Display name, category, and `synthetic <fixture.layout>` match each definition.
- Declared packages are `<manager.rawValue>:<name>`, semicolon-separated, registry order. `grok` is `none`.
- Every `versionQuery` in the registry is `["--version"]` / `stdout` / `first`. The matrix does not invent another query.
- `acceptedOperations` is `npmUpdate` + `npmUninstall` on `codex` only. Update and Uninstall are `yes: npm (verified npm-global copies only)` on that row only. Every other row is `informational: …` or `disabled: …` with a non-empty reason.
- `latest-check` is `yes: npm` and/or `yes: homebrewFormula` only when that candidate exists (`codex` is npm-only despite its cask; `hermes`/`aider`/`goose` are formula-only; `opencode`/`gemini`/`cline`/`omp` are both). `grok`, `kiro-cli`, and `agy` are `disabled: …`. No cell contains `yes: homebrewCask`.

Required carry-forward limits are in the named rows, and they match the frozen packet:

| Marker | Row | Packet |
|---|---|---|
| `3747` | aider | cold start 3747 ms above the 3 s budget |
| `2026-12-18` | gemini | formula `gemini-cli` disabled 2026-12-18; deprecated 2026-06-18, reason `unsupported`; replacement cask `antigravity-cli` |
| `2027-05-18` | cline | formula `cline` disabled 2027-05-18; deprecated 2026-05-18 |
| `~/.gemini/bin` | agy | legacy root, observed-local only, not a documented default |
| `pressly` | goose | formula `goose` 3.30.1; mutation identity `block-goose-cli` |
| `opencode2` | opencode | second executable, not a detector |
| `Dancer` | dsh | brew formula `dsh` is Dancer's shell, never declared |

The other required limit facts from the brief (codex optional-dependency unknown version, cask/standalone classification, vendor installer rerun, tap conflict, grok hash/channel line, claude `versions/` symlink, MacPorts/npx, cline shim, hermes git-checkout and `hermes-agent`/`hermes-acp`, goose helpers and `block-goose`, kiro never-detect and DMG, qoder dispatcher and `qodercli-1.1.88`, dsh prerelease and third-party PyPI, omp Tern store and `@oh-my-pi/cli` 404, agy `auto_updates`) are present and agree with the packet. The cross-row note states the `/lib/node_modules/` → npm, `/Cellar/` → brew, else standalone heuristic, including cask, script, uv, git, and Tern.

## 2. Agreement test

`Tests/AgentLensCoreTests/CapabilityMatrixTests.swift` parses `docs/capability-matrix.md` via `#filePath` (three directory deletions from `Tests/AgentLensCoreTests/` to the repo root). The parser is a pure function: exact header, a nine-cell dash separator, then contiguous `|` rows. Cells are split on `|` with empty subsequences kept, then trimmed. A wrong cell count, an empty cell, a missing header, or a missing separator throws. Duplicate ids are reported. There is no randomness, clock, or unordered set iteration in the verdict.

`matrixProblems` checks id set and order against `DetectorRegistry.loadDefault()`, display name, category raw value, `synthetic <layout>`, and package strings from `manager.rawValue`. Latest-check must be exactly `yes: npm`, `yes: homebrewFormula`, or `yes: npm; yes: homebrewFormula` when those candidates exist, and `disabled: <reason>` otherwise. `yes: homebrewCask` is rejected in every case. Update/Uninstall must be the exact npm-global yes string only when that operation is in `acceptedOperations` and an npm candidate exists; otherwise `informational: ` or `disabled: ` plus a non-empty reason. Known-limits must be non-empty, and the seven carry-forward markers are required on the named rows.

`capabilityMatrixAgreementRejectsSeededCorruption` requires the live document to agree, then:

- rewrites the opencode Update cell (column 6) to the exact yes string and requires a problem that names both `opencode` and `Update`;
- deletes the opencode row and requires a non-empty problem list.

Opencode has npm candidates and an empty `acceptedOperations`, so the yes string is illegal. Both corruptions are in-memory. The orchestrator log shows this test passed (`parent-02-suite.log`).

## 3. Data-only contribution proof

`dataOnlyContributionLoadsExtraToolWithoutProductionChange` loads the production bytes with `DetectorRegistry.loadDefaultRegistryData()`, appends `contrib-proof-tool` (`singleDirectory` / `standalone`, no packages, standard query), and loads that payload with `DetectorRegistry.validate`. It builds the detector with `DetectorDefinition.makeDetector` (`DetectorRegistry.swift:334`), which is the production builder, and detects a scratch executable named `contrib-proof-tool`. The test expects `installedAndOnPath` and source `standalone`, which is what `ToolDetector` reports for a PATH file outside `/lib/node_modules/` and `/Cellar/` (`ToolDetector.swift:188`).

The same test records the production id list before the extension and again after detection. Both equal the fourteen bundled ids, and neither contains `contrib-proof-tool`. The test does not write `DefaultDetectors.json`. `addingAFourthDefinitionRequiresNoSourceChanges` is still in `DetectorRegistryTests.swift` and passed in the same log.

## 4. Seeded collision control

`forbiddenCollisionPackages` is keyed by `PackageManager` raw value: `npm`, `homebrewFormula` (`dsh`, `goose`), `homebrewCask` (`qoder`, `opencode-desktop`, `block-goose`). `collisionIdentityViolations` looks up `package.manager.rawValue`.

`bundledRegistryNeverDeclaresCollisionIdentities` still validates a seeded document through `DetectorRegistry.validate` and now contains three detectors:

- npm `@aws/kiro-cli` on id/executable `kiro`
- homebrewFormula `goose` on `seed-formula`
- homebrewCask `qoder` on `seed-cask`

The expects are the scanner's own strings, including `homebrewFormula goose (detector seed-formula)` and `homebrewCask qoder (detector seed-cask)`. A missing or misspelled formula or cask key fails the test. The npm seed is still there. The test passed in `parent-02-suite.log`.

## 5. Floors, anchors, guard, packaging

`parent-02-suite.log`:

- `✔ Test run with 467 tests in 0 suites passed after 108.398 seconds.`
- `✔ Test run with 80 tests in 5 suites passed after 7.368 seconds.`

467 + 80 = 547. A line count of `✔ Test ` agrees (467 Core lines before the first summary; 80 AppSupport lines between the summaries). No `✘` and no skip. `ci.yml` floors are Core 467, AppSupport 80, `total_floor` 547, `combined_total_floor` 547. Previous floors were 456 / 79 / 535. Nothing was lowered.

The `ci.yml` diff does not touch `CORE_ANCHORS`, `APPSUPPORT_ANCHORS`, `guard-fixtures` floor 21, or `packaging` floor 9. `parent-04-guardfix.log` is `Ran 21 tests … OK`. `parent-06-packaging.log` is `Ran 9 tests … OK`.

## 6. CONTRIBUTING

`docs/CONTRIBUTING.md` states that no license file exists, that the owner must choose MIT or Apache-2.0 before any public invitation (no later than M18), and that contributions are not publicly invited. `README.md` repeats the no-invitation, no-license sentence.

Closed vocabularies match `DetectorMetadata.swift` and `DetectorRegistry.swift`: categories `aiAgent` / `aiCodingTool` / `aiHarness`; managers `npm` / `homebrewFormula` / `homebrewCask`; layouts `npmGlobal` / `singleDirectory` / `brewCellar`; sources `npm` / `brew` / `standalone`; streams `stdout` / `stderr`; lines `first` / `firstNonempty`; version-query bounds 1–8 arguments, non-empty, NUL-free, 256 bytes each, 1024 total; accepted operations `npmUpdate` / `npmUninstall` with duplicates rejected; schema 2 with schema 1 rejected; unknown keys rejected. The HTTPS rule matches the validator's reason string ("HTTPS URL with a host and no user information"). Homebrew names are bare or `user/repo/name`, and two components are rejected (`DeclaredPackage.validationFailure`, count 1 or 3). Evidence marks `verified-docs` / `observed-local` / `unverified` match the packet. The primary gate block matches the brief, including the CLT plugin path.

`id == executableName` is correctly attributed to the catalogue test (`DetectorRegistryTests.swift` `bundledDefaultDetectorsMatchFrozenCatalogue`), not to the validator.

## 7. Gates

| Log | Observation |
|---|---|
| `parent-01-build.log` | `Build complete! (3.50 secs)` |
| `parent-02-suite.log` | 467 + 80 passed, 0 failed, 0 skipped |
| `parent-03-guard.log` | 32 Core Swift files, no SwiftUI/AppKit imports |
| `parent-04-guardfix.log` | 21 tests, OK |
| `parent-05-app.log` | `Build complete! (24.27 secs)` |
| `parent-06-packaging.log` | 9 tests, OK |

## Findings

1. **LOW** — `docs/CONTRIBUTING.md:13` (list through line 27). The guide says to edit exactly seven paths for a new tool on an existing layout. That list omits `Tests/AgentLensCoreTests/CapabilityMatrixTests.swift`. The matrix agreement function reads ids from `DetectorRegistry.loadDefault()`, but `dataOnlyContributionLoadsExtraToolWithoutProductionChange` also requires `productionIDs == frozenCatalogue` (`CapabilityMatrixTests.swift:450-456` and `:523`). `frozenCatalogue` is the fourteen-id list. A data-only addition that follows the guide and updates `DefaultDetectors.json`, the other id-list tests, the matrix row, and the README sentence still fails this test until `frozenCatalogue` is edited. The other hardcoded id lists (`DetectorRegistryTests.swift`, `BundledRegistryResourceTests.swift`, `BundleResourceTests.swift`, `UpdateCLIIntegrationTests.swift`, `Tests/Packaging/test_dev_app_bundle.py`) are named.

## Not filed

- Hermes known-limits quotes the raw line start `Hermes Agent v0.23.1 ...` beside "first token". The packet's extracted token is `0.23.1`. The raw line is the packet's measured line, and the required "first token wins" fact is present. The wording is tighter on the grok row than here. It does not contradict a date, package, or classification rule.
- `ci.yml` says the combined count 547 is "above the Core/AppSupport floors". 547 equals the total floor and is above the 467 and 80 component floors. The floor numbers themselves are the measured count.
- The CLT workaround block shows `swift test --no-parallel` plus the plugin flags, while the primary block also unsets `AGENT_LENS_TEST_SCRATCH` and `AGENT_LENS_TEST_PRODUCTS`. The paragraph says to rerun the same command with those flags. The plugin path matches the brief.
