# M11-D — collision batch (dispatch brief)

Status: authorized under the owner-approved M11 plan (2026-11-12). Worker brief, not acceptance
evidence. Freeze this revision once dispatched; corrections use a separate revision brief.

## Identity and authority

- Phase: M11-D, revision 1. Milestone branch: `milestone/m11-catalogue`.
- HEAD baseline: `5a0fb54644102c7864985201d8fe3b9d419ae43a` (M11-C accepted). Parent baseline:
  463 Core + 80 AppSupport = 543 tests, exit 0.
- Sole implementer: **DeepSeek V4.1 Flash 1017 via OMP** (`river/deepseek-ai/DeepSeek-V4.1-Flash-1017`,
  `--thinking max`), owner-selected. No other implementer, subagent, provider, model or CLI.
- **Independent read-only review is REQUIRED for this phase** (orchestrator risk decision: wrong
  package identities here become wrong mutation targets later): MiniMax M3.1-Flash/xhigh (mcode)
  and Grok 4.7/high (grok CLI), summoned through Herdr/hc after the candidate is frozen.
- Orchestrator owns acceptance and all Git delivery. **Do not stage, commit, branch, reset, merge,
  push, or publish.**
- Evidence root `R`: `/Users/corvette/.hermes/cache/scratch/agent-lens-m11-Jb11B5`. Use
  `R/worker-d`, `R/tmp` (TMPDIR), `R/evidence/d`.
- Authority: `briefs/M11-plan.md` §5 M11-D; **`docs/catalogue-identities.md` (frozen) is the ONLY
  identity source**; the do-not-declare table in it is BINDING. Rulings R1–R12 bind.

## Goal and exclusions

Add the six collision-risk entries — `hermes`, `aider`, `goose`, `kiro-cli`, `omp`, `agy` — from
the frozen packet, and add a permanent regression test that the bundled registry never declares a
do-not-declare identity. After this phase the registry ships twelve entries.

Exclusions: no dsh/qodercli (M11-E, owner-gated); no new layout/source/manager vocabulary; no
`acceptedOperations` on any new entry (D-021); no mutation adapter; no UI change; no scanner or
classifier change (the pressly/goose basename collision is a documented limit, NOT a scanner
project); no ci.yml change (the anchor name carries no count); no floor change; no matrix (M11-F);
no version pins; no license file.

## Registry contract (copy from the frozen packet; restated for cross-check)

Append after the existing six, in this order: `hermes`, `aider`, `goose`, `kiro-cli`, `omp`, `agy`.
`id` equals `executableName`. All `versionQuery`: `["--version"]`, stdout, first (all measured in
M11-A). All new entries: `acceptedOperations` key ABSENT.

| id | displayName | category | fixture | packages | extraSearchRoots | informationURL | uninstallInstructionsURL |
|---|---|---|---|---|---|---|---|
| hermes | Hermes | aiAgent | singleDirectory / standalone | homebrewFormula `hermes-agent` | `["~/.local/bin"]` | `https://hermes-agent.nousresearch.com/docs/getting-started/installation` | `https://hermes-agent.nousresearch.com/docs/getting-started/updating#uninstalling` |
| aider | Aider | aiCodingTool | singleDirectory / standalone | homebrewFormula `aider` | `[]` | `https://aider.chat/docs/install.html` | absent/null |
| goose | Goose | aiCodingTool | singleDirectory / standalone | homebrewFormula `block-goose-cli` | `["~/.local/bin"]` | `https://goose-docs.ai/docs/guides/goose-cli-commands` | absent/null |
| kiro-cli | Kiro CLI | aiCodingTool | singleDirectory / standalone | homebrewCask `kiro-cli` | `["~/.local/bin"]` | `https://kiro.dev/docs/cli/` | `https://kiro.dev/docs/getting-started/installation/` |
| omp | Oh My Pi | aiHarness | singleDirectory / standalone | npm `@oh-my-pi/pi-coding-agent`; homebrewFormula `can1357/tap/omp` | `["~/.local/bin"]` | `https://omp.sh/docs/quickstart` | absent/null |
| agy | Antigravity CLI | aiHarness | singleDirectory / standalone | homebrewCask `antigravity-cli` | `["~/.local/bin", "~/.gemini/bin"]` | `https://antigravity.google/docs/getting-started/` | absent/null |

Root authority: `~/.local/bin` roots are the documented installer destinations frozen in the
packet (hermes wrapper; `GOOSE_BIN_DIR`; `USER_INSTALL_DIR`; `PI_INSTALL_DIR`; `TARGET_DIR`).
`~/.gemini/bin` for agy is the packet's observed-local legacy root, allowed by R10 with a limit
note; it is never a fixture. Aider has no frozen static destination (uv/pipx dirs vary) → `[]`.

**Never declare** (binding table, packet §Do-not-declare): brew formula `dsh`; npm/PyPI/brew
`goose` (pressly); npm `kiro-cli` (placeholder, bin `kirox`); cask `qoder`; `@oh-my-pi/cli`;
third-party PyPI `deepseek-harness*`; npm `qoder`/`@qoder-ai/qoder`/`@aws/kiro-cli`; casks
`opencode-desktop`, `block-goose`; PyPI `google-antigravity`. Never detect `kiro` (IDE/router).
If any frozen name fails validation, STOP and report the exact error.

## Test/CI contract

- `bundledDefaultDetectorsMatchFrozenCatalogue`: exact ordered 12-id list; extend fixture,
  category, package, URL, and acceptance assertions for the six new rows (all acceptance empty).
  Keep the existing six rows' assertions intact.
- **New permanent test** (in `DetectorRegistryTests.swift` or the new gate test file — one place):
  the bundled registry declares NONE of the do-not-declare identities: assert no package equals
  brew formula `dsh`/`goose`, npm `goose`/`kiro-cli`/`qoder`/`@qoder-ai/qoder`/`@aws/kiro-cli`/
  `@oh-my-pi/cli`, cask `qoder`/`opencode-desktop`/`block-goose`; and no detector id/executable is
  `kiro` or `qoder`. Name the test clearly (e.g. `bundledRegistryNeverDeclaresCollisionIdentities`).
- Id-list updates: `BundledRegistryResourceTests.swift` (bundled id list only),
  `BundleResourceTests.swift` (ids/displayNames/executableNames/categories),
  `UpdateCLIIntegrationTests.swift`, `Tests/Packaging/test_dev_app_bundle.py`
  (`registry_count=12 registry_ids=codex opencode grok claude gemini cline hermes aider goose kiro-cli omp agy`;
  spare the two-id fixture expectation).
- **Fixture hermeticity (critical):** every new executable must be shadowed on the closed fixture
  PATH in `UpdateCLIIntegrationTests` (`writeFakeTool` for hermes, aider, goose, kiro-cli, omp,
  agy), because five of them declare `~/.local/bin` and Foundation resolves `~` to the real user
  even with a synthetic HOME. The exact invoked set becomes the ten shadowed tools
  (codex, opencode, grok, claude, hermes, aider, goose, kiro-cli, omp, agy); gemini and cline stay
  truthfully absent (no extra roots, not on the fixture PATH). Update the exact-set assertion and
  its message; keep the per-tool once-only and brew-log assertions intact.
- `bundledFixtureDefinitionsMatchSyntheticLayouts` stays green for all twelve.
- `.github/workflows/ci.yml`: NOT touched. Floors NOT touched.
- `README.md`: the one `verify-installation` id sentence → the twelve shipped ids.
- If a test outside the allow-list fails on a hardcoded list: STOP and report; orchestrator decides.

## Allow-list

- `Sources/AgentLensCore/Detectors/DefaultDetectors.json`
- `Tests/AgentLensCoreTests/DetectorRegistryTests.swift`
- `Tests/AgentLensCoreTests/BundledRegistryResourceTests.swift`
- `Tests/AgentLensAppSupportTests/BundleResourceTests.swift`
- `Tests/AgentLensCoreTests/UpdateCLIIntegrationTests.swift`
- `Tests/Packaging/test_dev_app_bundle.py`
- `README.md` (the one id sentence ONLY)
- Add `walkthroughs/M11-D-implementation.md` (worker report, labeled worker evidence)

DO NOT TOUCH: all production Swift sources, `Package.swift`, `scripts/**`, `.github/**`, other
tests/packaging, `Resources/**`, historical briefs/walkthroughs, root docs except the named
sentence, `docs/catalogue-identities.md` (frozen), personal installations, the real Agent Lens
cache, credentials.

## Acceptance matrix

| ID | Scenario | Expected observation |
|---|---|---|
| D-AC01 | Bundled registry loads | Twelve entries, exact order; new rows per contract; acceptance absent; existing rows unchanged |
| D-AC02 | Collision regression | New do-not-declare test passes; seeded corruption (adding a forbidden name in a test copy) fails it |
| D-AC03 | Full gates | build, full suite (543+, zero skips/failures), both import guards, fresh dev app, 9 packaging — exit 0 |
| D-AC04 | Preflight + CLI parity | `registry_count=12` with the exact id list; built CLI scan shows twelve entries with truthful states |
| D-AC05 | Hermetic CLI integration | Exact invoked set = ten shadowed tools; gemini/cline absent; no real tool executed |
| D-AC06 | Scope | diff within allow-list; protected hashes otherwise clean; ci.yml/floors untouched |

## Exact gates and evidence

```sh
env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS swift build
env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS swift test --no-parallel
python3 scripts/check-core-ui-imports.py
python3 Tests/Packaging/test_core_ui_imports.py
python3 scripts/build-dev-app.py --scratch-root R/worker-d/app --configuration debug
python3 Tests/Packaging/test_dev_app_bundle.py --app R/worker-d/app/AgentLensApp-debug.app
```

Environment note (M11-C D-1, reproduced by the orchestrator): on this CLT-only workstation the
suite may fail before any test with `TestingMacros … plugin not found`. If so, rerun with the
invocation-local flag
`-Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing`
and record BOTH runs. No package/toolchain/xcode-select change is permitted.

Raw argv/stdout/stderr/exit/durations under `R/evidence/d`; SHA-256 of changed files; protected
manifest comparison. Orchestrator reruns independently; reviewers read the frozen candidate.

## Stop conditions

Stop and report if: any proposal would declare a do-not-declare name or detect `kiro`/`qoder`;
distinguishing Goose from pressly would require a scanner change; a frozen row fails validation;
an out-of-allow-list test pins an old list; any production Swift change seems required; anything
asks for credentials or privileges.

## Report contract

```sh
hc send t7x "M11-D complete: collision batch candidate — <entries, tests count, gates, deviations>"
```