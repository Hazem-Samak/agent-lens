# M11-D independent review — Grok

Verdict: **PASS**

Findings: **0** (0 blocking, 0 non-blocking)

Candidate: `cdd8ccc3eb488fd980f6f6182df451f1f7d4f7c7` on `milestone/m11-catalogue` (`feat(catalogue): M11-D collision batch candidate (twelve entries)`). Product range reviewed: `git diff 8ac1b50..cdd8ccc`. Identity authority: frozen `docs/catalogue-identities.md` (do-not-declare table) and frozen `briefs/M11-D-collision-batch.md`. Checked against the tree at that commit. The worker report was not used as evidence. Gates below were read from the cited parent logs; this review did not re-run them.

## Findings

None.

## Checks

### 1. New registry rows match the frozen packet

`Sources/AgentLensCore/Detectors/DefaultDetectors.json` is schema 2 with twelve detectors. The six new objects are appended in order `hermes`, `aider`, `goose`, `kiro-cli`, `omp`, `agy` (lines 136–257). For each, `id` equals `executableName`, `versionQuery` is `arguments: ["--version"]`, `stream: stdout`, `line: first`, and the fixture is `singleDirectory` / `standalone`.

| id | lines | category | packages | extraSearchRoots | informationURL | uninstallInstructionsURL |
|---|---|---|---|---|---|---|
| hermes | 136–155 | aiAgent | homebrewFormula `hermes-agent` | `["~/.local/bin"]` | hermes installation page | updating `#uninstalling` |
| aider | 157–175 | aiCodingTool | homebrewFormula `aider` | `[]` | `https://aider.chat/docs/install.html` | key absent |
| goose | 177–195 | aiCodingTool | homebrewFormula `block-goose-cli` | `["~/.local/bin"]` | goose CLI commands page | key absent |
| kiro-cli | 197–216 | aiCodingTool | homebrewCask `kiro-cli` | `["~/.local/bin"]` | `https://kiro.dev/docs/cli/` | installation page with trailing slash |
| omp | 218–236 | aiHarness | npm `@oh-my-pi/pi-coding-agent`; homebrewFormula `can1357/tap/omp` | `["~/.local/bin"]` | `https://omp.sh/docs/quickstart` | key absent |
| agy | 238–257 | aiHarness | homebrewCask `antigravity-cli` | `["~/.local/bin", "~/.gemini/bin"]` | `https://antigravity.google/docs/getting-started/` | key absent |

Those strings match the brief’s registry table and the packet’s frozen candidates, URLs, and roots. `~/.gemini/bin` is an extra search root on `agy` only. The agy fixture stays `singleDirectory` / `standalone` (lines 243–246).

`acceptedOperations` appears once in the file, on the existing `codex` row (line 18). It is absent from all six new objects. `DetectorRegistryTests.swift:108` still requires every definition after the first to have an empty `acceptedOperations` array, so the new rows are covered by that assertion together with the per-row package, root, and URL expects at lines 156–209.

### 2. Do-not-declare identities, and a non-vacuous regression

The bundled JSON contains none of the binding do-not-declare names. Confirmed by parsing the file and scanning package `(manager, name)` pairs:

- Homebrew formula names present are the pre-existing OpenCode taps, `opencode`, `gemini-cli`, `cline`, plus `hermes-agent`, `aider`, `block-goose-cli`, and `can1357/tap/omp`. Formula `dsh` and formula `goose` are absent. Goose’s package is `block-goose-cli` (line 187), which is the frozen candidate, distinct from pressly formula `goose` and from cask `block-goose`.
- The only `kiro-cli` package is homebrewCask (line 207). npm `kiro-cli`, npm `@aws/kiro-cli`, and a detector id or executable `kiro` are absent.
- npm `@oh-my-pi/cli` is absent. OMP’s npm package is `@oh-my-pi/pi-coding-agent` (line 227).
- Casks `qoder`, `opencode-desktop`, and `block-goose` are absent. npm `qoder`, `@qoder-ai/qoder`, and `@aws/kiro-cli` are absent. Detector id and executable `qoder` are absent.
- PyPI names `goose`, `deepseek-harness`, `deepseek-harness-cli`, and `google-antigravity` do not appear. `PackageManager` (`DetectorMetadata.swift:61–64`) is still only `npm`, `homebrewFormula`, and `homebrewCask`, so those PyPI names have no declarable manager.

`bundledRegistryNeverDeclaresCollisionIdentities` (`DetectorRegistryTests.swift:248–266`) loads the bundled registry and expects `collisionIdentityViolations` to be empty. The forbidden map (`lines 217–223`) is the brief’s required set: formula `dsh`/`goose`; npm `goose`/`kiro-cli`/`qoder`/`@qoder-ai/qoder`/`@aws/kiro-cli`/`@oh-my-pi/cli`; cask `qoder`/`opencode-desktop`/`block-goose`; ids and executables `kiro` and `qoder`. Lookup uses `package.manager.rawValue`, and those raw values match the map keys.

The seeded control (`lines 255–265`) validates a one-detector copy whose id is `kiro`, executable is `kiro`, and npm package is `@aws/kiro-cli`, then expects all three violation strings. An empty forbidden set, or a scanner that ignores id, executable, or package name, fails those expects. The bundled-registry expect fails if the same scanner always reports violations. The control is therefore non-vacuous for the function it guards. The committed seed covers one package name plus both name channels; the other forbidden strings are the constant table, which matches the brief’s enumerated list.

### 3. Hermetic CLI fixture

`ToolDetector.locate` (`ToolDetector.swift:103–109`) returns the first PATH hit and consults `extraSearchRoots` only when PATH misses. `expandTilde` (`lines 173–179`) uses `NSHomeDirectory()`, so a miss would reach the real user. `makeBrewCLIScenario` (`UpdateCLIIntegrationTests.swift:651–664`) places executable fakes for `opencode`, `grok`, `claude`, `hermes`, `aider`, `goose`, `kiro-cli`, `omp`, and `agy` on the closed fixture PATH, beside the existing Codex Cellar symlink. That is the ten tools the scan invokes. `writeRC` (`lines 585–590`) exports only that bin plus `/usr/bin:/bin`.

Gemini and Cline stay off that PATH. Their `extraSearchRoots` are still empty (unchanged rows; asserted at `DetectorRegistryTests.swift:139` and `:148`), so a PATH miss is `notInstalled` and runs no version query.

`verify-installation` scans the single named definition (`Sources/agent-lens/main.swift:114–130`). The npm and formula ownership scenarios still call it only for `codex`, `opencode`, or `grok`, which those scenarios place on the fixture PATH. They do not open a scan of the new extra-root tools.

The exact-set test (`UpdateCLIIntegrationTests.swift:827–883`) rewrites those same ten binaries to log their names, expects `detectorCalls.count == 10`, and expects set equality with exactly `{codex, opencode, grok, claude, hermes, aider, goose, kiro-cli, omp, agy}`. Count plus set equality means each name once. The shadowed-codex once-only expect (`line 875`) and the three-line brew log expect (`line 877`) are still there. The assertion message still states that gemini and cline are absent.

### 4. Exact lists, floors, and the original six rows

Deep comparison of the parsed detectors: the first six objects at `cdd8ccc` are equal to the six objects at `8ac1b50`, including Codex `acceptedOperations`.

Ordered twelve-id lists, with the original six first, are in:

- `DetectorRegistryTests.swift:82–85` (ids), `:87–100` (fixtures), `:102–105` (categories)
- `BundleResourceTests.swift:36–52` (count, ids, display names, executables, categories)
- `BundledRegistryResourceTests.swift:593–596`
- `Tests/Packaging/test_dev_app_bundle.py:132–138` and the preflight string at `:192–193`

`bundledFixtureDefinitionsMatchSyntheticLayouts` (`DetectorRegistryTests.swift:405–452`) walks `loadDefault()` and switches on `npmGlobal` and `singleDirectory`. All twelve fixtures are one of those two layouts.

The two-id disposable preflight expectation is unchanged: `registry_count=2 registry_ids=opencode codex` (`test_dev_app_bundle.py:274`).

`git rev-parse 8ac1b50:.github/workflows/ci.yml` and `cdd8ccc:.github/workflows/ci.yml` are the same blob (`8dd2b0da5d702e2f715db199d3da121497d22dd5`). Floors in that file remain Core 456, AppSupport 79, total 535. The diff of `ci.yml` is empty.

### 5. Scope

`git diff --name-status 8ac1b50..cdd8ccc` is eight paths, all on the allow-list:

- `Sources/AgentLensCore/Detectors/DefaultDetectors.json`
- `Tests/AgentLensCoreTests/DetectorRegistryTests.swift`
- `Tests/AgentLensCoreTests/BundledRegistryResourceTests.swift`
- `Tests/AgentLensAppSupportTests/BundleResourceTests.swift`
- `Tests/AgentLensCoreTests/UpdateCLIIntegrationTests.swift`
- `Tests/Packaging/test_dev_app_bundle.py`
- `README.md` (one sentence: the `verify-installation` id list now names the twelve shipped ids, `README.md:51`)
- `walkthroughs/M11-D-implementation.md` (added worker report)

No production Swift, `Package.swift`, `scripts/**`, `.github/**`, `docs/catalogue-identities.md`, or other tests. Working tree at review time was clean and HEAD was `cdd8ccc`.

## Gate transcripts (read, not re-run)

Parent logs under `…/evidence/d/parent-*.log`:

- `parent-01-build.log` ends `Build complete! (3.25 secs)`.
- `parent-02-suite.log`: `Test run with 464 tests … passed` and `Test run with 80 tests in 5 suites passed` (544). Includes passes for `bundledDefaultDetectorsMatchFrozenCatalogue`, `bundledRegistryNeverDeclaresCollisionIdentities`, and `bundledFixtureDefinitionsMatchSyntheticLayouts`.
- `parent-03-guard.log`: 32 Core Swift files, no SwiftUI/AppKit imports.
- `parent-04-guardfix.log`: `Ran 21 tests … OK`.
- `parent-05-app.log`: `Build complete!` and the debug app path.
- `parent-06-packaging.log`: `Ran 9 tests … OK`.
- `dev-app-preflight.stdout`: `bundle-preflight: ok registry_count=12 registry_ids=codex opencode grok claude gemini cline hermes aider goose kiro-cli omp agy`.
- `parent-07-cli-scan.log` opens with `AI AGENTS 12` and lists twelve entries. Installed rows that printed versions match the packet’s measured shapes for the tools present on this machine (Hermes `0.23.1`, Oh My Pi `18.19.0`, Antigravity CLI `1.5.6`). Aider, Goose, and Kiro CLI print as not installed.

Worker `gates.tsv` records the same 544 and the same gate exits 0, plus the expected D-1 plugin failure on the unflagged suite run. That table is worker evidence; the parent transcripts above are what this review relied on.
