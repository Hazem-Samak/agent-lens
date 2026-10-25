# M9-A — detector metadata and bounded version-query contract

Status: authorized for implementation by the user on 2026-10-22 as the first phase of M9. This is a worker brief, not acceptance evidence. Freeze this revision once dispatched; corrections use a separate revision brief.

## Identity and authority

- Phase: M9-A, revision 1. Milestone branch: `milestone/m9-verified-inventory`.
- HEAD baseline: `a405b56183ad0233f286f4d93b027ba7d21c2a01` (M8). Pre-existing orchestrator changes: `README.md`, `briefs/README.md`, and new `ROADMAP.md`; preserve them. This brief is also orchestrator-owned.
- Sole implementer: DeepSeek V4.1 Flash Free via OpenCode `opencode/deepseek-v4.1-flash-free#max`, build agent. OpenCode v2.0.32. No other implementer, subagent, provider, model or CLI.
- Orchestrator owns review/acceptance and any Git delivery. Do not stage, commit, branch, reset, merge, push or publish.
- Evidence root `R`: `/Users/corvette/.hermes/cache/scratch/agent-lens-m9-20261022-382vfoyi`. Use `R/worker-a` for worker artifacts, `R/tmp` for TMPDIR. Never put generated scaffolds in the repository.
- Fresh parent baseline: 184 Core and 62 AppSupport tests passed. Raw log: `R/evidence/baseline.log`. Baseline hashes: `R/evidence/baseline-sha256.json`. Swift 6.4, arm64. Existing compiler/linker warnings are not this phase's cleanup scope.
- Load-bearing decisions: native Swift 6; Core imports no SwiftUI/AppKit; discovery and every child process use captured `ShellEnvironment`, not inherited PATH; three installation states and neutral unknown versions; zero external dependencies; declarative versioned JSON detectors; reviewers are read-only; parent independently runs acceptance.

## Goal and exclusions

User-visible goal: CLI and tool details show a supported tool's category, declared package candidates and official information, distinguish declarations from installation ownership, and execute its bounded version-query specification from the registry.

No ownership verification, manager commands, latest-version adapters, installation changes, catalogue additions, category navigation/filter redesign, update-cache changes, packaging changes, CI, background work, settings, signing or release. No M9-B/C implementation in this phase. No unused operation interface or future manager abstraction.

## Read set and allow-list

Read existing patterns in `Sources/AgentLensCore/Detection/{DetectorRegistry,ToolDetector,ScanRenderer}.swift`, `Sources/AgentLensCore/Process/BoundedProcessRunner.swift`, `Sources/AgentLensCore/Diagnostics/DiagnosticsScanRenderer.swift`, `Sources/agent-lens/main.swift`, `Sources/AgentLensApp/ToolDetailView.swift`, `Sources/AgentLensAppSupport/InventorySnapshot.swift`, current registry and related tests. No need to read the full scope/roadmap or credential/configuration files.

Allowed production edits/additions:

- Modify `Sources/AgentLensCore/Detection/DetectorRegistry.swift`.
- Modify `Sources/AgentLensCore/Detection/ToolDetector.swift` only for typed version-query configuration; preserve path/source detection semantics.
- Add `Sources/AgentLensCore/Detection/DetectorMetadata.swift` for the concrete category/package/version-query value types.
- Add `Sources/AgentLensCore/Detection/DetectorMetadataRenderer.swift` for CLI metadata text.
- Modify `Sources/AgentLensCore/Detectors/DefaultDetectors.json`.
- Modify `Sources/agent-lens/main.swift` only to append declared metadata in every valid scan mode; preserve flags, usage/error dispatch and update coordinator behavior.
- Modify `Sources/AgentLensApp/ToolDetailView.swift` only to display this metadata/information links using the existing native style; preserve path action identity/eligibility and update status.
- Existing files under `Tests/AgentLensCoreTests/` and `Tests/AgentLensAppSupportTests/`: migrate affected schema/constructor fixtures and replace obsolete incidental assertions, preserving their real behavior coverage. New focused tests may be `Tests/AgentLensCoreTests/DetectorMetadataTests.swift` and `Tests/AgentLensCoreTests/VersionQuerySpecificationTests.swift`.
- Add `walkthroughs/M9-A-implementation.md` with worker-observed behavior, usage and limits. Clearly label it a worker report, not independent acceptance. This is the in-repo implementation documentation for this phase; parent owns README/index/status closeout.

DO NOT TOUCH: all other production code, `Package.swift`, packaging tests/scripts/resources, historical briefs/walkthroughs, root docs/status/decisions, system preferences, installed tools/managers, actual Agent Lens cache, user environment or credentials. If an additional file is genuinely required, stop and request it with exact reason; do not silently broaden scope. The allow-list permits fixture migration, not unrelated test cleanup.

Before exported-symbol changes, obtain language-server references if available. Parent's sourcekit query for `DetectorDefinition` (from InventorySnapshot.swift:23) returned 19 references across registry, AppSupport, app preflight and tests; the initial cold declaration query returned none, so do not treat an empty cold query as complete. Inspect all affected callsites.

## Behavioral/interface contract

1. Clean cutover to registry `schemaVersion: 2`. Schema 1 is rejected, not silently defaulted or supported through a shim. Migrate every bundled definition and synthetic JSON fixture/constructor together. Preserve stable IDs, display names, executable names, extra roots, registry order and existing fixture layouts for Codex/OpenCode/Grok.
2. Define concrete `ToolCategory` values `aiAgent`, `aiCodingTool`, `aiHarness` with presentation labels. Required `category` on each definition; the three current entries are `aiAgent`. This is tool metadata, not a manager category or new sidebar.
3. Required `packages` is an array of `DeclaredPackage` candidates `{ "manager": ..., "name": ... }`, with managers `npm`, `homebrewFormula`, `homebrewCask`. Empty is valid. Reject unknown manager values, duplicate manager/name pairs, empty/invalid package identities or values that are not a package name (paths, whitespace, NUL, shell/options text). Scoped npm names and fully qualified Homebrew taps are valid. A candidate NEVER means the installation is package-owned or manageable.
4. Optional `informationURL` and `uninstallInstructionsURL` are HTTPS URLs with nonempty host and no user info, or absent/null. Reject malformed/file/javascript URLs. Do not label a general homepage as uninstall instructions. No automatic network calls or opening links during scanning.
5. Required `versionQuery` is a concrete `VersionQuerySpecification`: `arguments` (1–8 nonempty NUL-free strings, at most 256 UTF-8 bytes each and 1024 total), `stream` (`stdout`/`stderr`), `line` (`first`/`firstNonempty`). Extract a version token with the existing bounded token parser; no arbitrary regex, shell command, executable override or user-configured timeout. `first` preserves current first-line behavior; `firstNonempty` permits introductory blank lines. Keep the 3-second process deadline and existing output limits. Treat failed/timed-out/limited/invalid-UTF8/no-version results as nil, not a fabricated version.
6. `makeDetector` must actually use the definition's query configuration in the production path. Preserve an injection seam suitable for deterministic tests without a second production convention. Protect validity for direct Swift construction too: invalid argument specifications must not reach a process launch just because JSON validation was bypassed. Do not retain the obsolete hardcoded-query production path as a compatibility alias. Existing consumers may use a validated standard specification explicitly.
7. Validation fails closed with a named detector/field reason. Reject wrong field types, unknown enum values and unknown keys at root/definition/nested metadata objects. Keep existing meaningful schema errors for prior required fields; migrate obsolete schema-version assumptions, not pin exact incidental wording. Validate integral schemaVersion without accepting booleans/fractions as version 2. `Codable` decoding, if exposed for definitions, must not bypass schema/value validity; one canonical validated path or invariant-preserving decoding.
8. CLI: append a `DETECTOR METADATA` section after the existing PATH report and before VERSION/UPDATE output. Associate directly from the same registry definitions in order; show category and declared candidates with explicit unverified ownership. Show official links if present. Do not alter the existing PATH report or infer metadata by display name/source text. All four scan modes retain manager/cache side-effect rules and existing flags.
9. Native details: show Category, Declared Packages and Ownership (`Not verified`) and official links when present. Empty candidates are "No declared package" or equivalent, not "standalone verified". Existing `Source (heuristic)` stays a heuristic. Do not present a declared candidate as installed package or enable modifying controls. Long package names/links wrap without clipping existing path controls. Display reflects the current selected entry and clears with selection, not stale local state.

### Verified initial catalogue data

Primary-source packet: `R/evidence/catalogue-sources.md`.

- Codex candidates: npm `@openai/codex`, Homebrew cask `codex`; information `https://developers.openai.com/codex/cli`; uninstall URL absent/null. Source https://github.com/openai/codex explicitly documents both managers.
- OpenCode candidates: npm `@opencode/cli` and `opencode-ai`; formulae `anomalyco/tap/opencode-v2` and `anomalyco/tap/opencode`. These represent distinct v2/v1 possibilities, not a version claim. Information `https://opencode.ai/v2/docs/`; uninstall instructions `https://opencode.ai/v2/docs/cli/#uninstall`. Sources https://opencode.ai/v2/docs/ and https://opencode.ai/docs/ . Preserve display name OpenCode and executable opencode.
- Grok CLI: packages empty; information `https://docs.x.ai/build/overview`; uninstall URL absent/null. Official https://x.ai/cli redirects to https://x.ai/build; installed vendor README documents `grok --version`. Do not invent a Grok npm or Homebrew package.
- All three queries use arguments `["--version"]`, stream stdout, first line; all current categories aiAgent. Unknown/unavailable uninstall instructions remain absent, not guessed.

## Acceptance matrix

| ID | Scenario/setup | Expected observation/evidence |
|---|---|---|
| M9-A-AC01 | Decode/load schema 2 metadata, encode/decode if supported, migrate current three entries and old callers | Real bundled loader/preflight works; stable tool selection/order preserved; schema 1 rejected |
| M9-A-AC02 | Fixtures for invalid category/package/URL/query/nested keys and direct-constructor/decoder bypass | Typed named rejection; no invalid query launches; valid scoped npm/tapped formula accepted |
| M9-A-AC03 | Scratch executable prints different versions for `--version` versus `version`, with stdout/stderr and blank first-line variants | Registry chooses correct arguments/stream/line through `makeDetector`; failure/nonzero/timeout/output limit remain nil. Arguments with spaces/metacharacters are literal argv, not shell evaluation |
| M9-A-AC04 | Built actual CLI: `scan`, `scan --offline`, `scan --check-updates`, `scan --refresh-updates`, plus existing invalid forms | Declared metadata associated to correct ID; unverified status explicit; PATH report remains unchanged; existing zero-manager/cache quiet behavior and dispatch tests pass |
| M9-A-AC05 | Actual built app: select Codex, OpenCode, Grok and switch back; narrow window; inspect new metadata and current path actions | Correct category/candidates/links per current entry; no false ownership; existing Copy/Reveal controls remain available. Parent independently observes; worker must not claim an unseen UI pass |
| M9-A-AC06 | Full Swift, fresh app builder and packaging suite; compare protected-file hashes | All gates pass, no scope drift, Core UI-free, no dependency/package or manager/cache behavior change |

Permanent tests must exercise consumer behavior and boundaries, not source text, wiring echoes, arbitrary default spelling or existence-only checks. Delete obsolete incidental assertion tests rather than re-pin wording. Keep deterministic isolated regression coverage for changed behavior. No global environment mutations in parallel tests.

## Exact gates and evidence

Create `R/worker-a` and use unique fresh child directories. Capture command argv, stdout, stderr, exit status and duration without dumping environments/secrets. Worker baseline may cite the parent baseline; final gates must be worker-observed and parent will rerun independently.

```sh
env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS \
  TMPDIR="$R/tmp" swift test --scratch-path "$R/worker-a/full-suite"
TMPDIR="$R/tmp" python3 scripts/build-dev-app.py \
  --scratch-root "$R/worker-a/dev-app" --configuration debug
TMPDIR="$R/tmp" python3 Tests/Packaging/test_dev_app_bundle.py \
  --app "$R/worker-a/dev-app/AgentLensApp-debug.app"
```

Expected all exit 0. The CLI built next to the test products can be used for runtime proof. Do not run live update checks against personal state as an acceptance shortcut: use the existing sandboxed CLI integration fixture pattern (closed PATH and real-cache denial) for update modes. Plain live offline scan is read-only. Use the version fixture programs under `R` for changed query proof. Do not add permanent product test mode/fixture overrides. Keep any native host outside repo and reuse product source unchanged.

Only if the known Swift Testing macro-discovery error occurs, use a separate fresh directory with the documented invocation-local flags:

```sh
env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS \
  TMPDIR="$R/tmp" swift test --build-system swiftbuild \
  --scratch-path "$R/worker-a/full-suite-explicit" \
  -Xswiftc -load-plugin-library \
  -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib
```

Do not change package/toolchain to hide a failure. Unrelated baseline failures or permission/isolation prerequisites are reported, not suppressed.

## Return contract and stop conditions

Stop for an allow-list change, unexpected concurrent edits, ambiguous catalogue identity, missing safe fixture environment, need for credentials/dependency/system changes or inability to run required gates. Do not implement another phase to work around it.

End with a written report: (1) files changed and concrete behavior; (2) each AC ID with exact evidence path/outcome, explicitly unverified native observations; (3) real test counts/exits; (4) decisions/deviations/blockers; (5) SHA-256 snapshot of candidate source/test/resource/implementation-doc files under `R/worker-a/candidate-sha256.json`. Leave edits uncommitted and stop changing files on handoff. Worker completion is a candidate submission only; parent owns technical acceptance.
