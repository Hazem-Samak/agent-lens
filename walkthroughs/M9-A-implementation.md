# M9-A — detector metadata and bounded version queries

Status: **worker implementation report, revision 1, 2026-10-22. Candidate only, not independent acceptance.** The orchestrator owns review, acceptance and Git delivery. All edits are uncommitted. The worker did not observe the native UI scenarios; that remains parent-observed.

The frozen [M9-A brief](../briefs/M9-A-detector-metadata.md) is the authority for the original phase. This revision also follows the orchestrator-owned [R1 review corrections](../briefs/M9-A-R1-review-corrections.md), which was read but not edited.

## Revision 1 corrections

| Finding | Outcome | Evidence |
|---|---|---|
| R1-01 — near-`Int.max` schema crash | Fixed. `integralSchemaVersion` no longer converts every `NSNumber` through `Double`: signed/unsigned integer storage is read exactly, `NSDecimalNumber` is rounded and range-checked in `Decimal`, and floating-point storage uses an exclusive `2^63` bound. A valid detector registry with schema `2` is accepted; `Int.max` and `Int.min` remain typed unsupported-version errors; above/below range, boolean and fractional values fail closed. A permanent subprocess regression drives the dangerous inputs so a reintroduced trap fails the test instead of killing the suite. | `Tests/AgentLensCoreTests/DetectorMetadataTests.swift` (`dangerousSchemaVersionsAreRejectedWithoutTrappingTheTestProcess`); `R/worker-a-r1/evidence/metadata-boundary-compile.json`, `metadata-boundary-after.json`; failing-before `R/evidence/metadata-boundary-before.json` left untouched |
| R1-02 — two-component Homebrew names | Fixed in the shared package validator. Homebrew formula/cask names now accept exactly one bare component or exactly three `owner/tap/name` components; two and four components, including empty components, are rejected. Direct construction, Codable and registry validation all use the same validator. | `Sources/AgentLensCore/Detection/DetectorMetadata.swift`; `homebrewCandidatesAcceptOnlyBareOrFullyQualifiedNames` and the existing package-boundary tests; boundary probe package receipts |
| R1-03 — avoidable compiled hot-path work | Fixed. Version-query line selection now uses substring indices and allocates only the selected line passed to the existing token parser; blank/whitespace/CRLF and `nil` behavior are preserved. `ToolDetailView.declaredPackagesView` iterates `packages.indices` instead of materializing enumerated pairs on every render. No general refactor or new parsing convention was added. | `Sources/AgentLensCore/Detection/ToolDetector.swift`; `Sources/AgentLensApp/ToolDetailView.swift`; CRLF/whitespace coverage in `VersionQuerySpecificationTests`; full suite |
| R1-04 — incidental and mock-echo tests | Removed `categoryAndPackageManagerLabelsAreStable`, `metadataRendererListsRegistryDefinitionsInOrderWithUnverifiedOwnership`, `injectedQuerySeamReceivesTheDeclaredSpecificationAndDoesNotLaunch`, and the newly added field-echo assertions in the registry, bundle-loader and query tests. No differently worded copy replaced them. Real schema, round-trip, isolation, process-failure, source/ownership, ordering and consumer-visible coverage remains. | Full suite below; CLI runtime evidence remains the metadata/ordering check |

The test count is unchanged at 271: three incidental tests were removed and three boundary regressions were added (Homebrew grammar, isolated schema boundary, CRLF/whitespace line selection).

## Behavior implemented

- Registry `schemaVersion` is now `2`. Schema 1 is rejected outright; there is no compatibility shim. The bundled Codex/OpenCode/Grok definitions and all migrated fixtures carry the required metadata.
- Each definition requires a `category` (`aiAgent`, `aiCodingTool`, `aiHarness`), a `packages` array of `{manager, name}` candidates (`npm`, `homebrewFormula`, `homebrewCask`; empty is valid), and a `versionQuery` (`arguments`, `stream`, `line`). Optional official links are HTTPS with a host and no user information. Unknown keys, wrong types, unknown enum values, duplicate candidates and invalid package identities fail closed with the detector ID and field named.
- A declared candidate is presentation metadata only. The CLI and native details state that ownership is not verified; no manager command, install action or ownership inference was added.
- `makeDetector` passes the definition's validated query specification into the production `ToolDetector`. The injected query seam remains for deterministic tests. The bounded runner executes literal argv (no shell), keeps the fixed 3-second deadline and existing output limit, and captures the declared stdout or stderr stream. Failure, timeout, output-limit, invalid UTF-8 and no-token outcomes stay `nil`.
- The CLI appends a `DETECTOR METADATA` section after the unchanged PATH report and before `VERSION / UPDATE STATUS` in `scan`, `scan --offline`, `scan --check-updates` and `scan --refresh-updates`. Metadata comes directly from the same ordered definitions; it is not inferred from display names or PATH text.
- Tool details show Category, Declared Packages, Ownership (`Not verified`), and the official information/uninstall links when present. Empty candidates read `No declared package`. Long package names and links wrap; the existing path actions and update status are unchanged. The view reads the current `InventoryEntry`, so switching or clearing selection does not leave stale metadata.

Catalogue data is exactly the verified packet: Codex npm `@openai/codex` and cask `codex`; OpenCode npm `@opencode/cli`, `opencode-ai` and formulae `anomalyco/tap/opencode-v2`, `anomalyco/tap/opencode`; Grok has no declared package. All three remain category `aiAgent` with `--version`/stdout/first and their existing IDs, names, executables and extra roots.

## Deviations and decisions

1. **stderr capture — original allow-list crossing, now within corrected authority.** `BoundedProcessRunner` previously discarded stderr and always captured stdout, so a declared `stream: stderr` query could not be honored without changing it. A minimal `captureStream` parameter (default `.standardOutput`) was added. Existing callers keep stdout capture; the non-captured stream is still discarded. The original run crossed the production allow-list; the R1 brief prospectively authorizes this file and permits retaining the change. That authority is not approval of the earlier boundary decision, which remains recorded here.
2. **Packaging fixtures — original allow-list crossing, now within corrected authority.** `Tests/Packaging/test_dev_app_bundle.py` was on the brief's do-not-touch list, but it hardcodes schema-1 registries and asserts the bundled registry is schema 1. With the clean cutover those tests cannot pass: `test_01` would reject the real bundle, `test_03` would reject its custom registry, and `test_09` would fail before reaching the mismatch/decoy assertions. The smallest fixture-only migration was applied: schema 1→2 plus the required `category`, `packages` and `versionQuery` fields, preserving each test's IDs, order and intent. Packaging trust-boundary assertions and behavior were not changed. The R1 brief prospectively authorizes this file and permits retaining the change; the earlier crossing remains recorded.
3. **Test discovery and `.build` restoration.** `ToolDetectorTests` locates a build product for its external probe. Its fallback once found a stale ignored `.build` product and compiled against the old module. It now prefers the active `.xctest` named by SwiftPM's `--test-bundle-path`, so stale generated artifacts can remain present. The original run moved the pre-existing `.build` tree to `R/worker-a/stale-dot-build`. On R1 restoration check, a new `.build` destination already existed (a 169-file partial `index-build` module cache); per the correction, the preserved 4,651-file tree was **not** restored, overwritten, deleted or merged. The collision is recorded for parent disposition. The R1 full suite and external probes passed with that destination present, so product lookup does not require moving the user's build tree.
4. **Unknown-key decoding.** The first Codable implementation used `allKeys` with a concrete `CodingKeys` enum. JSONDecoder silently drops keys the enum cannot represent, so unknown keys survived the decoding path. A dynamic coding key now exposes them and rejects them for definitions, fixtures, packages and queries, aligning Codable with JSONSerialization validation.
5. `VersionQuerySpecification.standard` is the explicit validated `--version`/stdout/first spec used by existing consumers that do not declare a query.

## Candidate files

Production:

- `Sources/AgentLensCore/Detection/DetectorMetadata.swift` (new)
- `Sources/AgentLensCore/Detection/DetectorMetadataRenderer.swift` (new)
- `Sources/AgentLensCore/Detection/DetectorRegistry.swift`
- `Sources/AgentLensCore/Detection/ToolDetector.swift`
- `Sources/AgentLensCore/Detectors/DefaultDetectors.json`
- `Sources/AgentLensCore/Process/BoundedProcessRunner.swift` (corrected-authority file)
- `Sources/agent-lens/main.swift`
- `Sources/AgentLensApp/ToolDetailView.swift`

Tests and fixtures:

- `Tests/AgentLensCoreTests/DetectorMetadataTests.swift` (new)
- `Tests/AgentLensCoreTests/VersionQuerySpecificationTests.swift` (new)
- `Tests/AgentLensCoreTests/DetectorRegistryTests.swift`
- `Tests/AgentLensCoreTests/ToolDetectorTests.swift`
- `Tests/AgentLensCoreTests/PathDiagnosticsTests.swift`
- `Tests/AgentLensCoreTests/UpdateCLIIntegrationTests.swift`
- `Tests/AgentLensCoreTests/UpdateProbeCoordinatorTests.swift`
- `Tests/AgentLensAppSupportTests/BundleResourceTests.swift`
- `Tests/AgentLensAppSupportTests/InventoryServiceTests.swift`
- `Tests/AgentLensAppSupportTests/PathActionTests.swift`
- `Tests/Packaging/test_dev_app_bundle.py` (corrected-authority file)

Report:

- `walkthroughs/M9-A-implementation.md` (this file)

The R1 SHA-256 manifest at `R/worker-a-r1/candidate-sha256.json` covers all 20 candidate files above and is generated after the final gates. It deliberately excludes the orchestrator-owned documents left untouched: `README.md`, `briefs/README.md`, `ROADMAP.md`, `briefs/M9-A-detector-metadata.md`, `briefs/M9-A-R1-review-corrections.md` and `briefs/M9-verified-installations.md`.

## Worker-observed evidence

Evidence root:

```text
R = /Users/corvette/.hermes/cache/scratch/agent-lens-m9-20261022-382vfoyi
```

Revision 1 evidence is under `R/worker-a-r1`; the original submission history remains under `R/worker-a`. Machine-local evidence is not part of the repository.

### Revision 1 final gates

| Check | Result | Evidence |
|---|---|---|
| Plain default `swift test` (fresh scratch) | exit 1 before tests: documented TestingMacros plugin-discovery error | `R/worker-a-r1/gates/full-suite.meta`, `.stdout`, `.stderr` |
| Explicit full suite fallback (separate fresh scratch) | **208 Core + 63 AppSupport = 271 passed, exit 0**, 54.1 s | `R/worker-a-r1/gates/full-suite-explicit.*` |
| Fresh development app builder | exit 0, 26.7 s | `R/worker-a-r1/gates/dev-app-build.*` |
| Packaging suite against that exact app | 9 tests passed, exit 0, 5.2 s | `R/worker-a-r1/gates/packaging.*` |
| Version-query driver (including stderr bounds) | 15/15 checks passed, exit 0, 3.1 s | `R/worker-a-r1/gates/version-query-proof.*`; sources in `R/worker-a-r1/version-proof/` |
| Parent boundary probe against revised Core | compile exit 0; all 20 dangerous/valid cases exit 0 with ordinary typed results, no signals | `R/worker-a-r1/evidence/metadata-boundary-compile.json`, `metadata-boundary-after.json` |
| AC04 actual CLI, four modes | all four exit 0; metadata at lines 32–51 between PATH (line 7) and VERSION/UPDATE (line 52) | `R/worker-a-r1/evidence/cli-runtime/ordering-and-metadata.txt` and per-mode files |
| AC04 invalid forms | 5/5 exit 1, empty stdout, usage on stderr | `R/worker-a-r1/evidence/cli-runtime/invalid-forms.txt` |
| Bundled app registry/preflight | schema 2, three ordered IDs, metadata present, preflight `ok registry_count=3 registry_ids=codex opencode grok` | `R/worker-a-r1/evidence/bundled-app-registry.txt` |
| Protected-file hash comparison | 74-file baseline: 59 unchanged, 15 expected candidate changes, 0 missing; orchestrator documents excluded from candidate scope | `R/worker-a-r1/evidence/protected-hash-diff.json` |
| Candidate SHA-256 manifest | 20/20 files re-hashed after the final gates; no mismatches | `R/worker-a-r1/candidate-sha256.json` |
| Core UI-free | no SwiftUI/AppKit imports in `Sources/AgentLensCore` | `R/worker-a-r1/evidence/core-ui-imports.txt` |
| `git diff --check` | exit 0 | `R/worker-a-r1/evidence/diff-check.txt` |
| `.build` restoration | not performed; destination collision recorded, preserved tree untouched | `R/worker-a-r1/evidence/dot-build-collision.json` |

### Original submission history (retained, superseded by R1 gates)

| Check | Result | Evidence |
|---|---|---|
| Original plain default `swift test` | 271 passed, exit 0 | `R/worker-a/gates/full-suite-default-postfix.*` |
| Original explicit fallback | 271 passed, exit 0 | `R/worker-a/gates/full-suite-explicit-final.*` |
| Original earlier default attempt | TestingMacros plugin-discovery failure before tests | `R/worker-a/gates/full-suite.*` |
| Original app builder / packaging | exit 0 / 9 passed | `R/worker-a/gates/dev-app-build.*`, `packaging.*` |
| Original version proof | 12/12 checks passed | `R/worker-a/gates/version-query-proof.*` |
| Original protected comparison and manifest | 59 unchanged / 15 changed / 20 files | `R/worker-a/evidence/protected-hash-diff.json`, `R/worker-a/candidate-sha256.json` |

### Acceptance matrix status

- **M9-A-AC01 — candidate evidence.** Bundled loader, schema-2 round trip, schema-1 rejection and ordered IDs pass in the suite. The built app's own preflight reports `registry_count=3 registry_ids=codex opencode grok`.
- **M9-A-AC02 — candidate evidence.** Focused tests cover invalid category/package/URL/query/nested keys, duplicate pairs, Homebrew one-or-three-component grammar, direct `DeclaredPackage`/`VersionQuerySpecification` construction and Codable decoding (including nested unknown keys). Dangerous schema values are exercised in a subprocess so a regression cannot take down the suite. All passed in the final suite and boundary probe.
- **M9-A-AC03 — candidate evidence.** The driver starts fixture executables through `makeDetector` and observes `version` versus `--version`, stdout versus stderr, `first` versus `firstNonempty`, literal argv with spaces/metacharacters, and nil for nonzero, no-token, invalid UTF-8, timeout and output-limit cases. R1 also observes stderr timeout, stderr output-limit and stderr invalid UTF-8. All passed.
- **M9-A-AC04 — candidate evidence.** The actual built `agent-lens` ran all four modes under a closed synthetic PATH with the real cache directory denied by `sandbox-exec`; invalid combinations exit 1 with usage. The CLI integration test additionally asserts the unchanged PATH prefix, metadata ordering, and zero-manager behavior for plain/offline plus one manager batch each for check/refresh.
- **M9-A-AC05 — NOT VERIFIED by the worker.** The app builds and its bundle preflight passes, but no native window was selected or inspected. Category/package/link display, narrow-window wrapping, selection switching and the existing Copy/Reveal controls still require parent observation. The R1 `ToolDetailView` allocation change was compiled and exercised only through the app build, not visually.
- **M9-A-AC06 — candidate evidence.** Full Swift, fresh app builder and 9-test packaging suite pass; protected hashes show no drift outside the candidate files; Core has no UI imports; no package/dependency or manager/cache behavior was changed.

## Limits

- The R1 plain default `swift test` invocation hit the documented TestingMacros plugin-discovery failure before executing tests. The documented explicit `swiftbuild` + CLT Testing-plugin fallback then passed all 271 tests in a separate fresh scratch directory. The failure is toolchain discovery, not a test failure; the failing attempt and passing fallback are both retained.
- The original `.build` tree could not be restored because the destination was recreated before the R1 check. The preserved tree remains at `R/worker-a/stale-dot-build`; no overwrite/delete/merge was attempted. This collision needs parent disposition.
- No live update check, manager install command, signing, notarization, installation or public release was performed. AC04 update modes used only the sandboxed synthetic CLI fixture/manual closed-PATH runs.
- Native UI and keyboard/VoiceOver behavior are outside this worker's claims.
- The `BoundedProcessRunner` and packaging-fixture changes are retained under the R1 corrected authority; the original boundary crossings remain part of the report history.

## Reproduction

Use fresh external scratch and retain actual stdout/stderr/exit codes:

```sh
R="$HOME/.hermes/cache/scratch/agent-lens-m9-$(uuidgen)"
mkdir -p "$R/tmp" "$R/worker"
env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS \
  TMPDIR="$R/tmp" swift test --scratch-path "$R/worker/full-suite"
TMPDIR="$R/tmp" python3 scripts/build-dev-app.py \
  --scratch-root "$R/worker/dev-app" --configuration debug
TMPDIR="$R/tmp" python3 Tests/Packaging/test_dev_app_bundle.py \
  --app "$R/worker/dev-app/AgentLensApp-debug.app"
git diff --check
```

If the known macro-discovery error occurs, use a separate fresh directory with the brief's invocation-local flags:

```sh
env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS \
  TMPDIR="$R/tmp" swift test --build-system swiftbuild \
  --scratch-path "$R/worker/full-suite-explicit" \
  -Xswiftc -load-plugin-library \
  -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib
```
