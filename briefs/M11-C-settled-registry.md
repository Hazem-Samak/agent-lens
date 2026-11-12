# M11-C — settled registry batch (dispatch brief)

Status: authorized under the owner-approved M11 plan (2026-11-12). Worker brief, not acceptance
evidence. Freeze this revision once dispatched; corrections use a separate revision brief.

## Identity and authority

- Phase: M11-C, revision 1. Milestone branch: `milestone/m11-catalogue`.
- HEAD baseline: `c6a0fef963cbf6b623b01685179232777f73b6cf` (M11-B accepted). Fresh parent
  baseline: 463 Core + 80 AppSupport = 543 tests, exit 0.
- Sole implementer: **DeepSeek V4.1 Flash 1017 via OMP** (`river/deepseek-ai/DeepSeek-V4.1-Flash-1017`,
  `--thinking max`), owner-selected. No other implementer, subagent, provider, model or CLI.
- Orchestrator owns acceptance and all Git delivery. **Do not stage, commit, branch, reset, merge,
  push, or publish.** This is a data-only phase: orchestrator acceptance suffices (ROADMAP §5.4);
  no standing independent review unless the orchestrator requests one after inspection.
- Evidence root `R`: `/Users/corvette/.hermes/cache/scratch/agent-lens-m11-Jb11B5`. Use
  `R/worker-c`, `R/tmp` (TMPDIR), `R/evidence/c`.
- Authority: `briefs/M11-plan.md` §5 M11-C; **`docs/catalogue-identities.md` (frozen M11-A packet)
  is the ONLY identity source** — copy rows from it, never re-derive from memory, proposals, or
  local installs. Rulings R1–R12 in `briefs/M11-planning/judgment.md` bind.

## Goal and exclusions

Add `claude`, `gemini`, `cline` to the bundled registry and apply the frozen corrections to
`opencode`. After this phase the registry loads six entries, each with a synthetic fixture, and
the CI anchor names the real test function.

Exclusions: no hermes/aider/goose/kiro/qoder/dsh/omp/agy (M11-D/E); no new layout/source/manager
vocabulary; no `acceptedOperations` on any new entry (they are informational — D-021); no mutation
adapter; no UI change; no floor-number change; no matrix (M11-F); no version pins; no desktop
casks (`opencode-desktop`); no personal shim paths; no license file.

## Registry contract (copy from the frozen packet; values restated for cross-check)

Order: existing `codex`, `opencode`, `grok` first (unchanged order), then `claude`, `gemini`,
`cline`. `id` equals `executableName`. All `versionQuery`: `["--version"]`, stdout, first.
All new entries: `acceptedOperations` key ABSENT.

| id | displayName | category | fixture | packages | extraSearchRoots | informationURL | uninstallInstructionsURL |
|---|---|---|---|---|---|---|---|
| claude | Claude Code | aiAgent | singleDirectory / standalone | npm `@anthropic-ai/claude-code`; homebrewCask `claude-code`; homebrewCask `claude-code@latest` | `["~/.local/bin"]` | `https://code.claude.com/docs/en/setup` | `https://code.claude.com/docs/en/setup#uninstall-claude-code` |
| gemini | Gemini CLI | aiAgent | npmGlobal / npm | npm `@google/gemini-cli`; homebrewFormula `gemini-cli` | `[]` | `https://geminicli.com/docs/get-started/installation/` | `https://geminicli.com/docs/resources/uninstall/` |
| cline | Cline CLI | aiAgent | npmGlobal / npm | npm `cline`; homebrewFormula `cline` | `[]` | `https://docs.cline.bot/usage/cli-overview` | absent/null |

Corrections to delivered entries:
- `opencode`: ADD homebrewFormula `opencode` (homebrew-core, one component) to the existing
  candidates (keep npm `@opencode/cli`, `opencode-ai`; tap formulae `anomalyco/tap/opencode-v2`,
  `anomalyco/tap/opencode`). UPDATE informationURL to `https://opencode.ai/docs/` and
  uninstallInstructionsURL to `https://opencode.ai/docs/cli/#uninstall` (frozen M11-A URL
  correction; old `/v2/docs/` paths redirect). Keep fixture, extraSearchRoots, versionQuery.
- `codex`: NO change (M11-A ruled the information URL kept; acceptance seed stays).
- `grok`: NO change.

If the validator rejects any frozen name (e.g. `claude-code@latest`), STOP and report with the
exact error — do not rename or drop it silently. The `@` character is expected to be legal in the
existing cask-name alphabet; prove it by loading, not by reading the regex alone.

## Test/CI contract (R7: exact sets stay exact)

- Rename `bundledDefaultDetectorsIsValidWithThreeTools` →
  `bundledDefaultDetectorsMatchFrozenCatalogue` in `DetectorRegistryTests.swift`, asserting the
  EXACT ordered id list `["codex","opencode","grok","claude","gemini","cline"]`, the new fixtures,
  categories, and packages (including `claude-code@latest` validating and opencode's core formula).
- `.github/workflows/ci.yml`: update the `CORE_ANCHORS` entry to the new function name IN THIS
  PHASE, plus any comment/description that would become false (e.g. the full-test-suite stream
  description naming the old function). **No floor changes** (Core 456 / AppSupport 79 / total 535
  floors stay; the suite now exceeds them — floors are raised only in M11-F to the measured count).
- Update the exact id-list assertions in `BundledRegistryResourceTests.swift` (bundled id list
  only; leave the unrelated `zeta-fixture`/`alpha-fixture` case alone),
  `BundleResourceTests.swift` (id and executableName lists),
  `UpdateCLIIntegrationTests.swift` (`Set(detectorCalls) == Set([...])` and any sibling assuming
  the trio is the whole default set).
- `Tests/Packaging/test_dev_app_bundle.py`: update the full-registry id list and the matching
  `registry_count=6 registry_ids=codex opencode grok claude gemini cline` preflight expectation.
  **Do not touch the separate two-id fixture expectation** (`registry_count=2 registry_ids=opencode codex`).
- `bundledFixtureDefinitionsMatchSyntheticLayouts` must stay green for every bundled definition
  (the loop builds each fixture; the new layouts are existing ones).
- `addingAFourthDefinitionRequiresNoSourceChanges` stays (Swift-constructor proof; JSON-only proof
  is M11-F).
- `README.md`: update the one sentence about `verify-installation` accepted registry ids to the
  six shipped ids. No other README change.
- If a test OUTSIDE this allow-list fails because it hardcodes the trio: STOP and report the file
  and assertion; the orchestrator decides scope. Do not edit walkthroughs/DECISIONS to make
  anything pass.

## Allow-list

- `Sources/AgentLensCore/Detectors/DefaultDetectors.json`
- `Tests/AgentLensCoreTests/DetectorRegistryTests.swift`
- `Tests/AgentLensCoreTests/BundledRegistryResourceTests.swift`
- `Tests/AgentLensAppSupportTests/BundleResourceTests.swift`
- `Tests/AgentLensCoreTests/UpdateCLIIntegrationTests.swift`
- `Tests/Packaging/test_dev_app_bundle.py`
- `.github/workflows/ci.yml` (anchor name + false comments ONLY)
- `README.md` (the one id sentence ONLY)
- Add `walkthroughs/M11-C-implementation.md` (worker report, labeled worker evidence)

DO NOT TOUCH: all production Swift sources (the registry JSON is the only product file),
`Package.swift`, `scripts/**`, other tests, other packaging files, `Resources/**`, historical
briefs/walkthroughs, root docs except the named README sentence, `docs/catalogue-identities.md`
(frozen), personal installations, the real Agent Lens cache, credentials.

## Acceptance matrix

| ID | Scenario | Expected observation |
|---|---|---|
| C-AC01 | Bundled registry loads | Six entries, exact order; new fixtures/categories/packages per contract; `acceptedOperations` absent on new entries; codex seed intact |
| C-AC02 | Filtered tests | `bundledDefaultDetectorsMatchFrozenCatalogue` and `bundledFixtureDefinitionsMatchSyntheticLayouts` pass |
| C-AC03 | Full gates | `swift build`, `swift test --no-parallel` (543+, zero skips/failures), both import guards, fresh dev app, 9 packaging checks — all exit 0 |
| C-AC04 | Dev-app preflight | `registry_count=6 registry_ids=codex opencode grok claude gemini cline` |
| C-AC05 | CLI parity | Built CLI `scan` reports the six entries with correct categories/candidates/links; existing flags/dispatch unchanged; absent binaries render not-installed/unknown truthfully |
| C-AC06 | Scope | diff within allow-list; protected-file hashes otherwise unchanged; no floor change; anchor renamed in ci.yml |

## Exact gates and evidence

```sh
env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS swift build
env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS swift test --no-parallel
python3 scripts/check-core-ui-imports.py
python3 Tests/Packaging/test_core_ui_imports.py
python3 scripts/build-dev-app.py --scratch-root R/worker-c/app --configuration debug
python3 Tests/Packaging/test_dev_app_bundle.py --app R/worker-c/app/AgentLensApp-debug.app
```

Raw argv/stdout/stderr/exit/durations under `R/evidence/c`; SHA-256 of changed files; protected
manifest comparison. Orchestrator reruns independently.

## Stop conditions

Stop and report if: the validator rejects a frozen name; a row's identity is not frozen in the
packet; an out-of-allow-list test pins the trio; any production Swift change seems required;
anything asks for credentials or privileges.

## Report contract

```sh
hc send t7x "M11-C complete: registry batch candidate — <entries, tests count, gates, deviations>"
```