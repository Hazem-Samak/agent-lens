# M11-E — owner-confirmed remainder (dsh, qodercli): worker implementation report

Status: **worker evidence, revision 1, 2026-11-12.** This is the implementer's report, not
acceptance. The orchestrator reruns every gate independently and owns all Git delivery. No Git
mutation was performed by this worker.

- Phase: M11-E, revision 1, dispatch brief `briefs/M11-E-owner-remainder.md`.
- Branch: `milestone/m11-catalogue`. Dispatch HEAD: `50e93e7d02713049b906b3efccfb56da35ab32f6`
  (“docs: dispatch M11-E owner-confirmed remainder (dsh, qodercli)”), whose parent is the brief's
  accepted baseline `c1183b4633d9f584cdd30929386c866794bea6dd` (M11-D accepted). No product code
  differed between the two commits.
- Sole implementer: DeepSeek V4.1 Flash 1017 via OMP. No subagent, provider, model, or other CLI
  was used.
- Evidence root `R`: `/Users/corvette/.hermes/cache/scratch/agent-lens-m11-Jb11B5`.
  Worker evidence is under `R/evidence/e`; the development app is under `R/worker-e/app`.

## What changed

The bundled registry now loads fourteen entries in the frozen order:

`codex`, `opencode`, `grok`, `claude`, `gemini`, `cline`, `hermes`, `aider`, `goose`,
`kiro-cli`, `omp`, `agy`, `dsh`, `qodercli`

Both new rows were copied from `docs/catalogue-identities.md`; `id` equals `executableName`, the
query is the standard `--version`/stdout/first, and `acceptedOperations` is absent (the only
registry entry with accepted operations remains `codex`). The existing twelve rows are unchanged.

- `dsh`: displayName `DeepSeek Harness`, category `aiHarness`, fixture `npmGlobal`/`npm`,
  extraSearchRoots `["~/.local/bin"]`, package npm `@deepseek-ai/dsh`, information URL
  `https://github.com/deepseek-ai/deepseek-harness`, no uninstall URL.
- `qodercli`: displayName `Qoder`, category `aiCodingTool`, fixture
  `singleDirectory`/`standalone`, extraSearchRoots `["~/.local/bin"]`, package npm
  `@qoder-ai/qodercli`, information URL `https://docs.qoder.com/cli/installation`, uninstall URL
  `https://docs.qoder.com/cli/installation#uninstallation`.

The binding do-not-declare table was not crossed: no formula `dsh`, no cask `qoder`, no npm
`qoder` or `@qoder-ai/qoder`, and no detector id or executable `qoder`. `~/.qoder` and `~/.dsh`
were not used as roots, layouts, or fixtures; `qodercli-<version>` was not used anywhere.

## Tests

No test function was added, removed, or renamed; the suite remains 544 tests. Assertions were
extended:

- `DetectorRegistryTests.swift`
  - `bundledDefaultDetectorsMatchFrozenCatalogue`: exact ordered fourteen-id list, fixture and
    category sequences extended, and per-row assertions for `dsh`/`qodercli` (displayName, roots,
    packages, information/uninstall URLs, empty accepted operations). The existing twelve rows'
    assertions are intact.
  - `bundledRegistryNeverDeclaresCollisionIdentities` is unchanged and green; its seeded control
    was deliberately not extended (M11-F scope).
- `BundledRegistryResourceTests.swift`: the bundled loader id list is fourteen.
- `BundleResourceTests.swift`: count, id, displayName, executableName, and category lists are
  fourteen.
- `UpdateCLIIntegrationTests.swift`: the synthetic scan fixture shadows `dsh` and `qodercli`
  (versions `0.2.2-rc.1`, `1.1.88`) in addition to the previous ten tools, because both declare
  `~/.local/bin` and Foundation resolves `~` to the real user even under a synthetic HOME. The
  exact detector-invocation assertion is now the twelve shadowed tools, queried exactly once
  each; `gemini` and `cline` declare no extra roots and remain absent. Once-only and brew-log
  assertions are intact.
- `Tests/Packaging/test_dev_app_bundle.py`: full-registry count/id list and the matching
  `registry_count=14 registry_ids=…` preflight expectation updated. The separate two-id fixture
  expectation (`registry_count=2 registry_ids=opencode codex`) is untouched.
- `README.md`: only the `verify-installation` accepted-id sentence changed, to the fourteen
  shipped ids.

## Gates run (worker evidence)

All commands ran from the repository root with `TMPDIR=R/tmp` and
`AGENT_LENS_TEST_SCRATCH` / `AGENT_LENS_TEST_PRODUCTS` unset. Raw stdout/stderr are under
`R/evidence/e`. Unlike M11-C/M11-D, no D-1 plugin-path workaround was needed: the exact unflagged
commands passed on this workstation.

| Gate | Exact argv | Exit | Observation |
|---|---|---|---|
| Build | `env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS swift build` | 0 | `Build complete!` in 3.20 s; deprecation and linker search-path warnings only |
| Focused | `env -u … swift test --no-parallel --filter 'bundledDefaultDetectorsMatchFrozenCatalogue\|bundledRegistryNeverDeclaresCollisionIdentities\|bundledFixtureDefinitionsMatchSyntheticLayouts\|realCLIAppendsAfterTheExactM5WinnerAliasShadowedAndInvalidPrefix\|absentMarkersUseBundledResource\|realBundledLoaderLoadsValidDefinitions'` | 0 | 6 tests passed in 4.88 s (5 Core + 1 AppSupport suite) |
| Full suite | `env -u … swift test --no-parallel` | 0 | 464 Core + 80 AppSupport = **544 passing, 0 skipped, 0 failed** in 105.71 s + 5.87 s |
| Import guard | `python3 scripts/check-core-ui-imports.py` | 0 | 32 Core Swift files; no SwiftUI/AppKit imports |
| Guard fixtures | `python3 Tests/Packaging/test_core_ui_imports.py` | 0 | 1.27 s combined; OK |
| Dev app | `python3 scripts/build-dev-app.py --scratch-root R/worker-e/app --configuration debug` | 0 | `R/worker-e/app/AgentLensApp-debug.app` in 24.39 s |
| Packaging | `python3 Tests/Packaging/test_dev_app_bundle.py --app R/worker-e/app/AgentLensApp-debug.app` | 0 | 9 tests OK in 1.78 s |
| Dev-app preflight | `AgentLensApp-debug.app/Contents/MacOS/AgentLensApp --bundle-preflight` | 0 | `bundle-preflight: ok registry_count=14 registry_ids=codex opencode grok claude gemini cline hermes aider goose kiro-cli omp agy dsh qodercli` |
| CLI parity | built `.build/debug/agent-lens scan` under a closed synthetic PATH (twelve fakes; gemini/cline absent) | 0 | Fourteen entries with truthful states; `dsh` shows `0.2.2-rc.1`, `qodercli` shows `1.1.88`, gemini/cline show `not installed` |

## Acceptance-matrix mapping

| ID | Observed |
|---|---|
| E-AC01 | `bundledDefaultDetectorsMatchFrozenCatalogue`, `realBundledLoaderLoadsValidDefinitions`, and the dev-app preflight show the exact fourteen-entry order, contract rows, absent acceptance, and unchanged existing rows |
| E-AC02 | `bundledRegistryNeverDeclaresCollisionIdentities` passed; the registry contains no forbidden identity |
| E-AC03 | build, full suite (544, zero skips/failures), both import guards, fresh dev-app build, and 9 packaging tests all exit 0 |
| E-AC04 | preflight `registry_count=14` with the exact id list; the built CLI scan lists fourteen entries with truthful states |
| E-AC05 | `realCLIAppendsAfterTheExactM5WinnerAliasShadowedAndInvalidPrefix`: exactly twelve shadowed tools invoked once each; gemini/cline absent; no real tool executed |
| E-AC06 | `git diff --name-only` is exactly the seven allow-listed files; protected SHA-256 manifest diff is empty; `ci.yml` and floors untouched |

## Deviations and interpretations

**D-1 (toolchain).** No deviation. `swift build`, the focused run, and the full suite passed with
the exact unflagged gate commands; the M11-C/D `TestingMacros` plugin-path failure did not occur.

**D-2 (CLI invocation set).** `UpdateCLIIntegrationTests` asserts the exact injected set of
twelve PATH tools, not fourteen registry ids. `gemini` and `cline` are truthfully absent because
they declare no extra roots; the twelve shadows prevent any real `~/.local/bin` or
`~/.gemini/bin` execution. This extends the accepted M11-C/D interpretation by two tools.

**D-3 (dispatch HEAD).** The brief names accepted baseline `c1183b4`; dispatch HEAD was `50e93e7`,
whose only addition is the M11-E dispatch documents. `c1183b4` is an ancestor of HEAD; no product
code differed at dispatch.

## Protected-file comparison

SHA-256 manifests for every tracked file outside the allow-list were captured from HEAD before
editing and from the working tree after (`R/evidence/e/protected-baseline.sha256`,
`R/evidence/e/protected-after.sha256`); `diff` reports no difference
(`R/evidence/e/protected-diff.txt`). `git status` records only the seven allow-listed
modifications plus this new walkthrough report. No commit, branch, stage, reset, merge, push, or
publish was performed.

Changed-file SHA-256 (`R/evidence/e/changed-sha256.txt`):

```text
9c82605c3148e156f192585fa5e759d5b81e5533c952528ec1ef925c9d5718dc  Sources/AgentLensCore/Detectors/DefaultDetectors.json
12d17ab1d7a7d8f0eab051a09d454cafcefc2ed9d772c6a67465777cfcb3fddd  Tests/AgentLensCoreTests/DetectorRegistryTests.swift
57bfd60f343755e192fb058a8631622eae31cfd15aa132c2850737f6abd72cd0  Tests/AgentLensCoreTests/BundledRegistryResourceTests.swift
0bf9e45a83972fe46d19401cdc3a548c1738ce436cca3f494a727c39f04b445c  Tests/AgentLensAppSupportTests/BundleResourceTests.swift
adf9a89cee8ebb4a5f8d8a78d784d0e94fd5b0c878ce3df273a97ee4caf58446  Tests/AgentLensCoreTests/UpdateCLIIntegrationTests.swift
de4aa5ad5f5d5bb820d1323619725f08885fa3b5208bfbc995ffad354d5dcab0  Tests/Packaging/test_dev_app_bundle.py
82834423e250b7024616866d1bcaace26e281660c0d9f2652c036f5abcdb56f5  README.md
```

## Not claimed / open items

- Orchestrator acceptance remains orchestrator-owned; this report is worker evidence only.
- No mutation adapter, UI change, scanner change, CI change, floor change, version pin, license
  file, or `qoder` dispatcher/detector was added.
- No native UI spot-check was performed beyond the dev-app preflight and packaging checks.
