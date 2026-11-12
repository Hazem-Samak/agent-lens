# M11-E — owner-confirmed remainder: dsh + qodercli (dispatch brief)

Status: authorized under the owner-approved M11 plan (2026-11-12). Worker brief, not acceptance
evidence. Freeze this revision once dispatched; corrections use a separate revision brief.

## Identity and authority

- Phase: M11-E, revision 1. Milestone branch: `milestone/m11-catalogue`.
- HEAD baseline: `c1183b4633d9f584cdd30929386c866794bea6dd` (M11-D accepted). Parent baseline:
  464 Core + 80 AppSupport = 544 tests, exit 0.
- Sole implementer: **DeepSeek V4.1 Flash 1017 via OMP** (`river/deepseek-ai/DeepSeek-V4.1-Flash-1017`,
  `--thinking max`), owner-selected. No other implementer, subagent, provider, model or CLI.
- Owner gate satisfied: OD-2 (DSH = DeepSeek Harness) and OD-3 (AGY) were approved by the owner's
  2026-11-12 delegation on the verified primary-source evidence recorded in
  `briefs/M11-planning/judgment.md` (post-freeze log) and `docs/catalogue-identities.md`.
  OD-4 rules the Qoder detector executable `qodercli` (the `qoder` dispatcher can launch the IDE).
- Review: **orchestrator acceptance** (data-only phase, two frozen owner-confirmed rows; the
  mutation gate and the collision regression were independently reviewed in M11-B/D; ceremony
  matches stakes, scope §29.9). The orchestrator may still summon reviewers after inspection.
- Orchestrator owns acceptance and all Git delivery. **Do not stage, commit, branch, reset, merge,
  push, or publish.**
- Evidence root `R`: `/Users/corvette/.hermes/cache/scratch/agent-lens-m11-Jb11B5`. Use
  `R/worker-e`, `R/tmp` (TMPDIR), `R/evidence/e`.
- Authority: `briefs/M11-plan.md` §5 M11-E; **`docs/catalogue-identities.md` (frozen) is the ONLY
  identity source**; its do-not-declare table is BINDING.

## Goal and exclusions

Add `dsh` and `qodercli` from the frozen packet. After this phase the registry ships all fourteen
originally named catalogue entries.

Exclusions: no new layout/source/manager vocabulary; no `acceptedOperations` on either entry
(D-021); no mutation adapter; no UI change; no scanner change; no ci.yml change; no floor change;
no matrix (M11-F); no version pins; no license file; no detector for `qoder` (dispatcher) or the
Qoder IDE; no Homebrew package for either tool (brew `dsh` is Dancer's shell; cask `qoder` is the
IDE — both binding do-not-declare).

## Registry contract (copy from the frozen packet; restated for cross-check)

Append after the existing twelve, in this order: `dsh`, `qodercli`. `id` equals `executableName`.
Both `versionQuery`: `["--version"]`, stdout, first (measured in M11-A: `0.2.2-rc.1` prerelease
token; `1.1.88`). Both: `acceptedOperations` key ABSENT.

| id | displayName | category | fixture | packages | extraSearchRoots | informationURL | uninstallInstructionsURL |
|---|---|---|---|---|---|---|---|
| dsh | DeepSeek Harness | aiHarness | npmGlobal / npm | npm `@deepseek-ai/dsh` | `["~/.local/bin"]` | `https://github.com/deepseek-ai/deepseek-harness` | absent/null |
| qodercli | Qoder | aiCodingTool | singleDirectory / standalone | npm `@qoder-ai/qodercli` | `["~/.local/bin"]` | `https://docs.qoder.com/cli/installation` | `https://docs.qoder.com/cli/installation#uninstallation` |

Root authority: `~/.local/bin` is the observed npm-global/launcher prefix for both on this machine
(packet entries 11–12, `observed-local`), consistent with the existing codex root. The Qoder
versioned runtime directory `~/.qoder/bin/qodercli/` and the dispatcher `~/.qoder/entry/qoder`
are personal artifacts — NEVER roots, layouts, or fixtures. The DSH data dir `~/.dsh` is vendor
data, not an install root. If a frozen name fails validation, STOP and report.

## Test/CI contract

- `bundledDefaultDetectorsMatchFrozenCatalogue`: exact ordered 14-id list; extend the per-row
  assertions for dsh/qodercli (packages, roots, categories, URLs, acceptance empty). Keep the
  existing twelve rows' assertions intact.
- `bundledRegistryNeverDeclaresCollisionIdentities` stays green (brew `dsh`, cask `qoder`, npm
  `qoder`/`@qoder-ai/qoder`, detector id/executable `qoder` remain forbidden). Do NOT extend the
  seeded control here — that is an M11-F requirement.
- Id-list updates: `BundledRegistryResourceTests.swift`, `BundleResourceTests.swift`,
  `UpdateCLIIntegrationTests.swift`, `Tests/Packaging/test_dev_app_bundle.py`
  (`registry_count=14 registry_ids=codex opencode grok claude gemini cline hermes aider goose kiro-cli omp agy dsh qodercli`;
  spare the two-id fixture expectation).
- **Fixture hermeticity:** shadow `dsh` and `qodercli` on the closed fixture PATH
  (`writeFakeTool`, versions `0.2.2-rc.1` and `1.1.88`); both declare `~/.local/bin`. The exact
  invoked set becomes twelve (the ten from M11-D plus dsh, qodercli); gemini/cline stay truthfully
  absent. Update the exact-set assertion and message; keep once-only/brew-log assertions intact.
- `bundledFixtureDefinitionsMatchSyntheticLayouts` stays green for all fourteen.
- `.github/workflows/ci.yml`: NOT touched. Floors NOT touched.
- `README.md`: the one `verify-installation` id sentence → the fourteen shipped ids.
- Out-of-allow-list failure on a hardcoded list: STOP and report.

## Allow-list

- `Sources/AgentLensCore/Detectors/DefaultDetectors.json`
- `Tests/AgentLensCoreTests/DetectorRegistryTests.swift`
- `Tests/AgentLensCoreTests/BundledRegistryResourceTests.swift`
- `Tests/AgentLensAppSupportTests/BundleResourceTests.swift`
- `Tests/AgentLensCoreTests/UpdateCLIIntegrationTests.swift`
- `Tests/Packaging/test_dev_app_bundle.py`
- `README.md` (the one id sentence ONLY)
- Add `walkthroughs/M11-E-implementation.md` (worker report, labeled worker evidence)

DO NOT TOUCH: all production Swift sources, `Package.swift`, `scripts/**`, `.github/**`, other
tests/packaging, `Resources/**`, historical briefs/walkthroughs, root docs except the named
sentence, `docs/catalogue-identities.md` (frozen), personal installations, the real Agent Lens
cache, credentials.

## Acceptance matrix

| ID | Scenario | Expected observation |
|---|---|---|
| E-AC01 | Bundled registry loads | Fourteen entries, exact order; new rows per contract; acceptance absent; existing rows unchanged |
| E-AC02 | Collision regression | Still green; no forbidden identity declared |
| E-AC03 | Full gates | build, full suite (544+, zero skips/failures), both import guards, fresh dev app, 9 packaging — exit 0 |
| E-AC04 | Preflight + CLI parity | `registry_count=14` exact id list; built CLI scan shows fourteen entries with truthful states |
| E-AC05 | Hermetic CLI integration | Exact invoked set = twelve shadowed tools; gemini/cline absent; no real tool executed |
| E-AC06 | Scope | diff within allow-list; protected hashes otherwise clean; ci.yml/floors untouched |

## Exact gates and evidence

```sh
env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS swift build
env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS swift test --no-parallel
python3 scripts/check-core-ui-imports.py
python3 Tests/Packaging/test_core_ui_imports.py
python3 scripts/build-dev-app.py --scratch-root R/worker-e/app --configuration debug
python3 Tests/Packaging/test_dev_app_bundle.py --app R/worker-e/app/AgentLensApp-debug.app
```

Environment note (M11-C/D D-1): if the suite fails before any test with `TestingMacros … plugin
not found` on this CLT-only workstation, rerun with the invocation-local flag
`-Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing`
and record BOTH runs. No package/toolchain/xcode-select change.

Raw evidence under `R/evidence/e`; SHA-256 of changed files; protected manifest comparison.

## Stop conditions

Stop and report if: any proposal would declare brew `dsh`, cask `qoder`, or detect `qoder`; a
frozen row fails validation; an out-of-allow-list test pins an old list; any production Swift
change seems required; anything asks for credentials or privileges.

## Report contract

```sh
hc send t7x "M11-E complete: remainder candidate — <entries, tests count, gates, deviations>"
```