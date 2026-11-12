# M11-C — settled registry batch: worker implementation report

Status: **worker evidence, revision 1, 2026-11-12.** This is the implementer's report, not
acceptance. The orchestrator reruns every gate independently and owns all Git delivery. No Git
mutation was performed by this worker.

- Phase: M11-C, revision 1, dispatch brief `briefs/M11-C-settled-registry.md`.
- Branch: `milestone/m11-catalogue`. Dispatch HEAD: `a77b29b` (M11-C brief), product baseline
  `c6a0fef` (M11-B accepted).
- Sole implementer: DeepSeek V4.1 Flash 1017 via OMP. No subagent, provider, model, or other CLI
  was used.
- Evidence root `R`: `/Users/corvette/.hermes/cache/scratch/agent-lens-m11-Jb11B5`.
  Worker evidence is under `R/evidence/c`; the development app is under `R/worker-c/app`.

## What changed

The bundled registry now loads six entries in the frozen order:

`codex`, `opencode`, `grok`, `claude`, `gemini`, `cline`

- `claude`: displayName `Claude Code`, fixture `singleDirectory`/`standalone`, extraSearchRoots
  `["~/.local/bin"]`, packages npm `@anthropic-ai/claude-code`, casks `claude-code` and
  `claude-code@latest`, the frozen setup/uninstall URLs, standard version query.
- `gemini`: displayName `Gemini CLI`, fixture `npmGlobal`/`npm`, no extra roots, packages npm
  `@google/gemini-cli` and formula `gemini-cli`, the frozen installation/uninstall URLs, standard
  version query.
- `cline`: displayName `Cline CLI`, fixture `npmGlobal`/`npm`, no extra roots, packages npm
  `cline` and formula `cline`, the frozen CLI-overview URL, no uninstall URL, standard version
  query.
- All three new entries omit `acceptedOperations` (absent key → informational; no mutation).
- `opencode`: core formula `opencode` appended to the existing four candidates; information URL
  corrected to `https://opencode.ai/docs/`; uninstall URL corrected to
  `https://opencode.ai/docs/cli/#uninstall`. Fixture, extraSearchRoots, and version query unchanged.
- `codex` and `grok`: unchanged; the codex `acceptedOperations` seed is intact.
- Frozen rows were copied from `docs/catalogue-identities.md`; no identity was re-derived and the
  frozen file was not edited. The cask name `claude-code@latest` was accepted by the existing
  cask-name alphabet (`^[A-Za-z0-9][A-Za-z0-9._+@-]*$`), proved by loading the real registry.

## Tests

The rename replaced the three-tool test function; no test function was added or removed.

- `DetectorRegistryTests.swift`: `bundledDefaultDetectorsIsValidWithThreeTools` renamed to
  `bundledDefaultDetectorsMatchFrozenCatalogue`. It asserts the exact ordered six-id list, every
  fixture pair, all six `aiAgent` categories, standard version queries, the codex mutation seed,
  empty accepted operations on the other five, opencode's five exact package candidates including
  the core formula, claude's three candidates including validating `claude-code@latest`, and all
  frozen URLs.
- `BundledRegistryResourceTests.swift`: bundled id list updated to the six ids; the unrelated
  `zeta-fixture`/`alpha-fixture` cases are untouched.
- `BundleResourceTests.swift`: count, id, displayName, executableName, and category lists updated
  to six.
- `UpdateCLIIntegrationTests.swift`: the synthetic PATH now shadows `claude` as well as
  `opencode`/`grok` (claude declares `~/.local/bin`, which resolves to the real user even under a
  synthetic HOME). The exact detector-invocation set is now the four synthetic PATH tools,
  `Set(["codex", "opencode", "grok", "claude"])`, queried exactly once each; `gemini` and `cline`
  declare no extra roots and remain genuinely absent under the closed PATH. The stale opencode
  uninstall URL assertion was corrected to the frozen URL.
- `Tests/Packaging/test_dev_app_bundle.py`: full-registry count/id list and the matching
  `registry_count=6 registry_ids=codex opencode grok claude gemini cline` preflight expectation
  updated. The separate two-id fixture expectation (`registry_count=2 registry_ids=opencode codex`)
  is untouched.
- `.github/workflows/ci.yml`: `CORE_ANCHORS` and the summary description now name
  `bundledDefaultDetectorsMatchFrozenCatalogue`; the stale “Test run with 535 tests” expectation
  comment now says the observed total exceeds the unchanged 535 floors until M11-F. No floor
  number changed.
- `README.md`: only the `verify-installation` accepted-id sentence changed, to the six shipped ids.

Full suite: **543 passing, 0 skipped, 0 failed** (463 Core + 80 AppSupport). Filtered runs:
`bundledDefaultDetectorsMatchFrozenCatalogue` passed; `bundledFixtureDefinitionsMatchSyntheticLayouts`
passed for every bundled definition; the affected loader/invocation/metadata tests passed.

## Gates run (worker evidence)

All commands ran from the repository root with `TMPDIR=R/tmp` and
`AGENT_LENS_TEST_SCRATCH` / `AGENT_LENS_TEST_PRODUCTS` unset. Raw argv/stdout/stderr/exit/duration:
`R/evidence/c/01…11`.

| Gate | Exact argv | Exit | Duration | Observation |
|---|---|---|---|---|
| Filtered catalogue | `swift test --no-parallel --filter bundledDefaultDetectorsMatchFrozenCatalogue` + toolchain plugin-path flags (D-1) | 0 | 10.4 s | 1 test passed |
| Filtered fixtures | `swift test --no-parallel --filter bundledFixtureDefinitionsMatchSyntheticLayouts` + flags (D-1) | 0 | 1.0 s | 1 test passed; all six fixtures |
| Filtered affected | loader/invocation/metadata filter + flags (D-1) | 0 | 16.9 s | 4 tests passed |
| Build | `env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS swift build` | 0 | 4.1 s | `Build complete!`; linker search-path warnings only |
| Full suite | `env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS swift test --no-parallel` + flags (D-1) | 0 | 101.9 s | 463 Core + 80 AppSupport = 543 passed; zero skips/failures |
| Import guard | `python3 scripts/check-core-ui-imports.py` | 0 | 0.1 s | 32 Core files; no SwiftUI/AppKit imports |
| Guard fixtures | `python3 Tests/Packaging/test_core_ui_imports.py` | 0 | 1.2 s | 21 tests OK |
| Dev app | `python3 scripts/build-dev-app.py --scratch-root R/worker-c/app --configuration debug` | 0 | 26.0 s | `R/worker-c/app/AgentLensApp-debug.app` |
| Packaging | `python3 Tests/Packaging/test_dev_app_bundle.py --app R/worker-c/app/AgentLensApp-debug.app` | 0 | 1.8 s | 9 tests OK |
| Dev-app preflight | `AgentLensApp-debug.app/Contents/MacOS/AgentLensApp --bundle-preflight` | 0 | 0.03 s | `registry_count=6 registry_ids=codex opencode grok claude gemini cline` |
| CLI parity | built `agent-lens scan` under a closed synthetic PATH (four installed fakes; gemini/cline absent) | 0 | 1.1 s | six entries, correct categories/candidates/links; absent tools render `–` and `not installed` |

## Deviations and interpretations

**D-1 (toolchain plugin-path workaround).** The exact documented test command currently fails on
this workstation before running any test:

`error: external macro implementation type 'TestingMacros.TestDeclarationMacro' could not be found
for macro 'Test'; plugin for module 'TestingMacros' not found`

`swift build` succeeds. A minimal package containing one `@Test` reproduces the failure outside
the repository, so it is not a repo change. The active toolchain is CommandLineTools only
(`xcode-select -p` → `/Library/Developer/CommandLineTools`; no `/Applications/Xcode.app`), and the
Swift Build engine resolves only `libSwiftMacros.dylib`, not the `testing/libTestingMacros.dylib`
subdirectory. Adding an explicit plugin path fixes it:

`-Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing`

The failing exact run is kept as `R/evidence/c/00-plugin-failure-*`; D-1 runs are marked in
`R/evidence/c/01…05` command records. This is an environment workaround, not a repository change.
M11-B's evidence recorded the exact command passing earlier in the same evidence root; the
toolchain state changed afterwards.

**D-2 (CLI invocation set).** `UpdateCLIIntegrationTests` now asserts the exact injected set of
four PATH tools, not six registry ids: only tools found on the synthetic PATH (or an extra root)
are executed, and `gemini`/`cline` are deliberately absent there. `claude` had to be shadowed
because it declares `~/.local/bin`; without the shadow a developer machine with a native Claude
Code install would execute it and change the exact set. The six-entry catalogue itself is asserted
by the registry/loader tests and by `R/evidence/c/11-cli-scan.stdout`.

**D-3 (CI comment).** No floor changed. The one stale count comment was updated because it claimed
exactly 535 tests were expected; the actual suite has exceeded that floor since M11-B. The anchor
rename is synchronous with the test rename.

## Protected-file comparison

`shasum -a 256 -c R/evidence/protected-manifest.txt` reports mismatches only for the eight
allow-listed files that changed:

- `Sources/AgentLensCore/Detectors/DefaultDetectors.json`
- `Tests/AgentLensCoreTests/DetectorRegistryTests.swift`
- `Tests/AgentLensCoreTests/BundledRegistryResourceTests.swift`
- `Tests/AgentLensAppSupportTests/BundleResourceTests.swift`
- `Tests/AgentLensCoreTests/UpdateCLIIntegrationTests.swift`
- `Tests/Packaging/test_dev_app_bundle.py`
- `.github/workflows/ci.yml`
- `README.md`

All other protected files are `OK`; the new report is absent from the dispatch manifest. Raw
comparison and per-file SHA-256 are under `R/evidence/c/12…13`. `git status` records working-tree
entries only; no commit, branch, stage, reset, merge, push, or publish was performed.

## Not claimed / open items

- Orchestrator acceptance and any independent review remain orchestrator-owned.
- The D-1 plugin-path workaround depends on this workstation's CommandLineTools layout; a machine
  with a complete Xcode installation may not need it.
- No native UI spot-check was performed beyond the dev-app preflight and packaging checks.
