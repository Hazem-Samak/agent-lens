# M11-D — collision batch: worker implementation report

Status: **worker evidence, revision 1, 2026-11-12.** This is the implementer's report, not
acceptance. The orchestrator reruns every gate independently and owns all Git delivery. No Git
mutation was performed by this worker.

- Phase: M11-D, revision 1, dispatch brief `briefs/M11-D-collision-batch.md`.
- Branch: `milestone/m11-catalogue`. Dispatch HEAD: `8ac1b509a071361431668e9506e41e80530e4649`
  (the M11-D dispatch docs commit on top of the brief's product baseline
  `5a0fb54644102c7864985201d8fe3b9d419ae43a`, M11-C accepted).
- Sole implementer: DeepSeek V4.1 Flash 1017 via OMP. No subagent, provider, model, or other CLI
  was used.
- Evidence root `R`: `/Users/corvette/.hermes/cache/scratch/agent-lens-m11-Jb11B5`.
  Worker evidence is under `R/evidence/d`; the development app is under `R/worker-d/app`.

## What changed

The bundled registry now loads twelve entries in the frozen order:

`codex`, `opencode`, `grok`, `claude`, `gemini`, `cline`, `hermes`, `aider`, `goose`,
`kiro-cli`, `omp`, `agy`

All six new rows were copied from `docs/catalogue-identities.md` and use fixture
`singleDirectory` / `standalone`, the standard `--version` stdout/first query, and an absent
`acceptedOperations` key (D-021; the only registry entry with accepted operations remains
`codex`).

- `hermes`: displayName `Hermes`, category `aiAgent`, extraSearchRoots `["~/.local/bin"]`,
  package formula `hermes-agent`, frozen installation and uninstall URLs.
- `aider`: displayName `Aider`, category `aiCodingTool`, no extra roots (no frozen static
  destination; uv/pipx dirs vary), package formula `aider`, frozen install URL, no uninstall URL.
- `goose`: displayName `Goose`, category `aiCodingTool`, extraSearchRoots `["~/.local/bin"]`,
  package formula `block-goose-cli` only, frozen CLI-commands URL, no uninstall URL.
- `kiro-cli`: displayName `Kiro CLI`, category `aiCodingTool`, extraSearchRoots
  `["~/.local/bin"]`, package cask `kiro-cli` only, frozen CLI and installation URLs.
- `omp`: displayName `Oh My Pi`, category `aiHarness`, extraSearchRoots `["~/.local/bin"]`,
  packages npm `@oh-my-pi/pi-coding-agent` and formula `can1357/tap/omp`, frozen quickstart URL,
  no uninstall URL.
- `agy`: displayName `Antigravity CLI`, category `aiHarness`, extraSearchRoots
  `["~/.local/bin", "~/.gemini/bin"]` (the legacy root is the packet's observed-local root,
  never a fixture), package cask `antigravity-cli`, frozen getting-started URL, no uninstall URL.

The pre-existing six rows are unchanged. No do-not-declare identity was written: no formula
`dsh`/`goose`, no npm `goose`/`kiro-cli`/`qoder`/`@qoder-ai/qoder`/`@aws/kiro-cli`/
`@oh-my-pi/cli`, no cask `qoder`/`opencode-desktop`/`block-goose`, and no detector id or
executable `kiro`/`qoder`.

## Tests

One permanent test was added; no existing test function was removed or renamed.

- `DetectorRegistryTests.swift`
  - `bundledDefaultDetectorsMatchFrozenCatalogue` now asserts the exact ordered twelve-id list,
    all twelve fixture pairs, the category sequence
    (`aiAgent` × 7, `aiCodingTool` × 3, `aiHarness` × 2), standard queries, the codex mutation
    seed, empty accepted operations for every other entry, and the frozen package/URL rows for
    all six additions. Existing six-row assertions are intact.
  - New `bundledRegistryNeverDeclaresCollisionIdentities` scans the bundled definitions for the
    binding do-not-declare table, keyed by manager (so formula `goose` is forbidden while formula
    `block-goose-cli` is the frozen Goose candidate), and for detector ids/executables `kiro` and
    `qoder`. It also validates a seeded in-memory registry containing npm `@aws/kiro-cli`,
    id `kiro`, and executable `kiro`, and asserts the scan reports all three violations. This
    makes the empty result on the real registry non-vacuous.
- `BundledRegistryResourceTests.swift`: bundled id list updated to twelve; unrelated payload,
  marker, and fallback cases are untouched.
- `BundleResourceTests.swift`: count, id, displayName, executableName, and category lists updated
  to twelve.
- `UpdateCLIIntegrationTests.swift`: the synthetic scan fixture now shadows `hermes`, `aider`,
  `goose`, `kiro-cli`, `omp`, and `agy` in addition to the previous tools, because five of them
  declare `~/.local/bin` and Foundation resolves `~` to the real user even under a synthetic
  HOME. The exact detector-invocation assertion is now the ten shadowed tools
  (`codex`, `opencode`, `grok`, `claude`, `hermes`, `aider`, `goose`, `kiro-cli`, `omp`, `agy`),
  queried exactly once each; `gemini` and `cline` declare no extra roots and remain absent.
  Per-tool once-only and brew-log assertions are intact.
- `Tests/Packaging/test_dev_app_bundle.py`: full-registry count/id list and the matching
  `registry_count=12 registry_ids=…` preflight expectation updated. The separate two-id fixture
  expectation (`registry_count=2 registry_ids=opencode codex`) is untouched.
- `README.md`: only the `verify-installation` accepted-id sentence changed, to the twelve shipped
  ids.

Full suite: **544 passing, 0 skipped, 0 failed** (464 Core + 80 AppSupport). The count is the
543-test M11-C baseline plus the one new collision test.

## Gates run (worker evidence)

All commands ran from the repository root with `TMPDIR=R/tmp` and
`AGENT_LENS_TEST_SCRATCH` / `AGENT_LENS_TEST_PRODUCTS` unset. Raw stdout/stderr are under
`R/evidence/d`.

| Gate | Exact argv | Exit | Observation |
|---|---|---|---|
| Build | `env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS swift build` | 0 | `Build complete!` in 3.63 s; linker search-path and deprecation warnings only |
| Focused, unflagged | `env -u … swift test --no-parallel --filter 'DetectorRegistryTests\|BundleResourceTests\|BundledRegistryResourceTests'` | 1 | Known D-1 pre-test failure: `plugin for module 'TestingMacros' not found`; no test executed |
| Focused, flagged | same filter + `-Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing` | 0 | 53 tests passed (43 Core filter + 10 BundleResourceTests) |
| CLI integration | `swift test --no-parallel --filter UpdateCLIIntegrationTests` + D-1 flags | 0 | 23 tests passed in 34.97 s; exact invoked set is the ten shadowed tools |
| Seed corruption | same, `--filter bundledRegistryNeverDeclaresCollisionIdentities`, with npm `goose` seeded into the `goose` entry | 1 (expected) | Failed with `["npm goose (detector goose)"]`; registry restored byte-identically (`869f501a…`) |
| Seed restored | same filter + D-1 flags after restore | 0 | 1 test passed |
| Full suite, unflagged | `env -u … swift test --no-parallel` | 1 | Known D-1 pre-test failure; no test executed |
| Full suite, flagged | same + D-1 flags | 0 | 464 Core + 80 AppSupport = 544 passed in 100.41 s + 7.24 s; zero skips/failures |
| Import guard | `python3 scripts/check-core-ui-imports.py` | 0 | 32 Core Swift files; no SwiftUI/AppKit imports |
| Guard fixtures | `python3 Tests/Packaging/test_core_ui_imports.py` | 0 | 21 tests OK in 1.12 s |
| Dev app | `python3 scripts/build-dev-app.py --scratch-root R/worker-d/app --configuration debug` | 0 | `R/worker-d/app/AgentLensApp-debug.app` in 25.18 s |
| Packaging | `python3 Tests/Packaging/test_dev_app_bundle.py --app R/worker-d/app/AgentLensApp-debug.app` | 0 | 9 tests OK in 1.70 s |
| Dev-app preflight | `AgentLensApp-debug.app/Contents/MacOS/AgentLensApp --bundle-preflight` | 0 | `bundle-preflight: ok registry_count=12 registry_ids=codex opencode grok claude gemini cline hermes aider goose kiro-cli omp agy` |
| CLI parity | built `.build/debug/agent-lens scan` under a closed synthetic PATH (ten fakes; gemini/cline absent) | 0 | Twelve entries with truthful states; each of the ten shows its fixture version, gemini/cline show `not installed` |

The exact full-suite gate without the plugin flag is retained as
`R/evidence/d/full-suite-unflagged.stderr` (D-1); the flagged run is
`R/evidence/d/full-suite.stdout` / `.stderr`.

## Deviations and interpretations

**D-1 (toolchain plugin-path workaround).** The documented `swift test --no-parallel` invocation
fails on this CLT-only workstation before running any test with
`external macro implementation type 'TestingMacros.…' could not be found ... plugin for module
'TestingMacros' not found`. `swift build` succeeds. Both the exact failing run and the flagged
passing run are recorded. The invocation-local flag is the M11-C D-1 workaround; no
package/toolchain/xcode-select change was made.

**D-2 (CLI invocation set):** `UpdateCLIIntegrationTests` asserts the exact injected set of ten
PATH tools, not twelve registry ids. `gemini` and `cline` remain genuinely absent because they
declare no extra roots, and the ten shadowed tools prevent any real `~/.local/bin` or
`~/.gemini/bin` execution. This is the same interpretation accepted in M11-C, extended by six
tools.

**D-3 (dispatch HEAD):** the brief names product baseline `5a0fb54`; dispatch HEAD was `8ac1b50`,
whose only addition is the M11-D dispatch documents. No product code differed at dispatch.

**D-4 (seed probe):** the D-AC02 corruption was applied to the working copy of the registry,
executed, and then restored from a byte-identical backup. The restored SHA-256 matches the
pre-seed value; `diff` reports no difference. The permanent test also contains an in-memory
seeded control, so the regression remains demonstrable without editing the file.

## Protected-file comparison

SHA-256 manifests for every tracked file outside the allow-list were captured before and after
(`R/evidence/d/protected-baseline.sha256`, `R/evidence/d/protected-after.sha256`); `diff` reports
no difference. `git status` records only the seven allow-listed modifications plus the new
walkthrough report. No commit, branch, stage, reset, merge, push, or publish was performed.

Changed-file SHA-256 (`R/evidence/d/changed-sha256.txt`):

```text
869f501adae9ad5a331ff387be599d68347753646d9d61e82272ae64872961dc  Sources/AgentLensCore/Detectors/DefaultDetectors.json
cecc5d72ee6bc2aab63aea4974c8fdeedbf58ca5a30c4e4721493e593156b30a  Tests/AgentLensCoreTests/DetectorRegistryTests.swift
7827d7d0833e5cd7dbbf352d13ccb86734426cceaf9056d36062cd91b11bcb14  Tests/AgentLensCoreTests/BundledRegistryResourceTests.swift
a9f5f885f9e4cf536a9d0bb5a876cfb0db22259949fec03c59834aa4b87df308  Tests/AgentLensAppSupportTests/BundleResourceTests.swift
4d39e2a21998c36a00e9e2504d9ead5e34f39ccf40b14b0ec42db9751ce2a102  Tests/AgentLensCoreTests/UpdateCLIIntegrationTests.swift
af9fbc9f68ff83b594a2deb1d363fd0a36477cf94ca3cb0a6c86461349661af6  Tests/Packaging/test_dev_app_bundle.py
1078b51a155ef0b7507e38f0f996d8cb64139b451a7209eb6c0eff5b23f15a20  README.md
```

`.github/workflows/ci.yml` and the test floors are untouched; the CI anchor name carries no
count.

## Not claimed / open items

- Orchestrator acceptance and the required independent review (MiniMax M3.1-Flash/xhigh and Grok
  4.7/high) remain orchestrator-owned; this report is worker evidence only.
- The Aider cold-start timeout limit remains as documented in the frozen packet; the registry does
  not change the 3 s version budget.
- No native UI spot-check was performed beyond the dev-app preflight and packaging checks.
