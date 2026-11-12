# M11-F — capability matrix and contributor foundation: worker implementation report

Status: **worker evidence, revision 1, 2026-11-12.** This is the implementer's report, not
acceptance. The orchestrator reruns every gate independently, counts the suite, and owns all Git
delivery. No Git mutation was performed by this worker.

- Phase: M11-F, revision 1, dispatch brief `briefs/M11-F-matrix-contributor.md`.
- Branch: `milestone/m11-catalogue`. Dispatch HEAD: `62aa642f886068ebb47da51b5e9429cddc78425b`
  ("docs: dispatch M11-F capability matrix and contributor foundation"), whose parent is the
  brief's accepted baseline `28738dc86f6911a633df3b138ae1ef07ed7c07dd` (M11-E accepted). The
  difference between the two commits is `ROADMAP.md`, `briefs/M11-F-matrix-contributor.md`, and
  `briefs/README.md` only; no product code differed.
- Sole implementer: DeepSeek V4.1 Flash 1017 via OMP. No subagent, provider, model, or other CLI
  was used.
- Evidence root `R`: `/Users/corvette/.hermes/cache/scratch/agent-lens-m11-Jb11B5`.
  Raw gate logs are under `R/evidence/f`; the development app is under `R/worker-f/app`.

## What changed

### 1. `docs/capability-matrix.md` (new)

One table row per bundled detector, in registry order:

`codex`, `opencode`, `grok`, `claude`, `gemini`, `cline`, `hermes`, `aider`, `goose`,
`kiro-cli`, `omp`, `agy`, `dsh`, `qodercli`

Columns are exactly the dispatch header: id, display name, category, tested fixture, declared
packages, latest-check, Update, Uninstall, known limits. Cell decisions:

- `tested fixture` is `synthetic <layout>` from the registry fixture (never a vendor claim).
- `declared packages` copies every registry candidate as `<manager>:<name>` in registry order;
  grok is `none`.
- `latest-check` is `yes: npm` and/or `yes: homebrewFormula` exactly when those candidates are
  declared; cask-only rows (kiro-cli, agy) and grok are `disabled` with the cause named.
- `Update`/`Uninstall` are `yes: npm (verified npm-global copies only)` only for codex (the only
  entry with accepted operations and an npm candidate). Formula-only rows are
  `informational: no accepted mutation scenario (M11); formula adapter M13`; npm-declared but
  unaccepted rows are informational; grok and the cask-only rows are disabled with the cause.
- Every limits cell is non-empty and carries the frozen packet's facts, including all
  carry-forwards: codex optional-dependency unknown version, cask/standalone classification,
  vendor installer rerun; opencode `opencode2`, tap conflict, excluded desktop cask; grok no
  package identity and build/channel noise; claude `versions/` launcher store, background
  auto-update, optional npm platform dependency; gemini DEPRECATED 2026-06-18 / DISABLED
  2026-12-18 and replacement cask; cline DEPRECATED 2026-05-18 / DISABLED 2027-05-18, shim and
  npm-under-prefix limits; hermes git-checkout, PyPI non-declarable, second executables,
  multi-field version line; aider 3747 ms cold start over the 3 s budget, uv/pip/pipx
  non-declarable, dependency warning; goose pressly basename collision with mutation identity
  `block-goose-cli`, desktop cask, helper binaries; kiro-cli never `kiro`, no formula, installer
  `--version` is not the query, DMG surface; qodercli dispatcher, versioned runtime filename, IDE
  cask; dsh developer preview, prerelease tokens, brew `dsh` is Dancer's shell, third-party PyPI
  exclusions; omp `@oh-my-pi/cli` excluded, Tern store is not the tap, bun non-declarable; agy
  legacy `~/.gemini/bin` observed-local only (R10), cask `auto_updates` and `agy update`
  vendor-owned, SDK excluded.
- A cross-row note states the source-classification heuristic (`/lib/node_modules/` → npm,
  `/Cellar/` → brew, else standalone), that cask/script/uv/git/Tern installs classify standalone,
  and that a Homebrew-prefix path is not formula proof. Declared candidates are not ownership.

### 2. `Tests/AgentLensCoreTests/CapabilityMatrixTests.swift` (new, three tests)

- `capabilityMatrixMatchesTheBundledRegistry` — parses the markdown deterministically (exact
  header, nine cells, malformed rows fail), and asserts: id set/order equals
  `DetectorRegistry.loadDefault()`; display name, category, synthetic fixture, and declared
  packages match each definition; latest-check/Update/Uninstall obey the cell rules against
  `packages` and `acceptedOperations`; every limits cell is non-empty; the required carry-forward
  substrings are present (`3747`, `2026-12-18`, `2027-05-18`, `~/.gemini/bin`, `pressly`,
  `opencode2`, `Dancer`) and the cross-row note is substantive.
- `capabilityMatrixAgreementRejectsSeededCorruption` — the real matrix passes the same
  `matrixProblems` function; a copy with `opencode`'s Update cell replaced by the `yes` literal
  fails and names opencode; a copy with the `opencode` row dropped fails and names opencode. The
  repository file is never written.
- `dataOnlyContributionLoadsExtraToolWithoutProductionChange` — takes the CURRENT bundled registry
  bytes, appends one schema-2 definition (`contrib-proof-tool`, `singleDirectory`/`standalone`, no
  packages, standard query), validates it through `DetectorRegistry.validate`, builds it with the
  existing `makeDetector`, and detects a synthetic executable in an owned scratch tree. The
  production `DefaultDetectors.json` id list is asserted unchanged (exact fourteen ids) in the
  same test. The existing constructor proof `addingAFourthDefinitionRequiresNoSourceChanges` is
  untouched.

### 3. `Tests/AgentLensCoreTests/DetectorRegistryTests.swift` (seeded control only)

`bundledRegistryNeverDeclaresCollisionIdentities` now seeds one violation per manager branch: the
existing npm `@aws/kiro-cli`, plus formula `goose` and cask `qoder`, and asserts each violation is
named. The bundled-registry emptiness assertion and the forbidden map are unchanged. The
`addingAFourthDefinitionRequiresNoSourceChanges` test is untouched.

### 4. `docs/CONTRIBUTING.md` (new)

States the exact files to edit for a new tool on an existing layout; every registry field and the
closed vocabularies (categories, managers, layouts, sources, query stream/line/bounds, URL rules,
package-name rules); evidence marks and primary-source rules; fixture limits; personal artifacts;
the do-not-declare pointer; the D-021 mutation gate; the matrix row contract; the exact local gate
commands with the CLT-only plugin-path workaround; and the license status (no license selected;
owner must choose MIT or Apache-2.0 before any public contribution invitation, no later than M18;
contributions are not publicly invited yet).

### 5. `.github/workflows/ci.yml` (floors only)

Measured on this candidate: **467 Core + 80 AppSupport = 547**, zero skips and zero failures.
Floors raised exactly: Core `456 → 467`, AppSupport `79 → 80`, `total_floor` and
`combined_total_floor` `535 → 547`. The floor-history comment records the M11-F measurement, and
the combined-layout comment now states the measured 547. `CORE_ANCHORS`, `APPSUPPORT_ANCHORS`,
guard-fixtures 21, packaging 9, and every other workflow value are unchanged.

### 6. `README.md`

Added one short "Catalogue and contributing" section linking `docs/capability-matrix.md` and
`docs/CONTRIBUTING.md`, and stating that contributions are not publicly invited and no license is
selected. The fourteen-id `verify-installation` sentence is unchanged.

## Tests and measured count

- New Swift Testing cases: 3 (all in `CapabilityMatrixTests.swift`).
- Full suite final: **467 Core + 80 AppSupport = 547 passing, 0 skipped, 0 failed**, exit 0
  (two Swift Testing summaries, `full-suite-final.stdout`).
- Focused M11-F contract run: 4 tests (3 new + the extended collision regression), exit 0
  (`focused-03.stdout`).

## Gates run (worker evidence)

All commands ran from the repository root with `TMPDIR=R/tmp` and
`AGENT_LENS_TEST_SCRATCH` / `AGENT_LENS_TEST_PRODUCTS` unset.

| Gate | Exact argv | Exit | Observation |
|---|---|---|---|
| Build | `env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS swift build` | 0 | `Build complete! (2.59 secs)`; deprecation and linker search-path warnings only |
| Focused | `env -u … swift test --no-parallel --filter 'capabilityMatrix\|dataOnlyContribution\|bundledRegistryNeverDeclaresCollisionIdentities'` (+ plugin path) | 0 | 4 tests passed in 0.012 s |
| Full suite | `env -u … swift test --no-parallel` (+ plugin path) | 0 | 467 + 80 = **547 passing, 0 skipped, 0 failed** in 102.550 s + 6.831 s |
| Import guard | `python3 scripts/check-core-ui-imports.py` | 0 | 32 Core Swift files; no SwiftUI/AppKit imports |
| Guard fixtures | `python3 Tests/Packaging/test_core_ui_imports.py` | 0 | `Ran 21 tests ... OK` |
| Dev app | `python3 scripts/build-dev-app.py --scratch-root R/worker-f/app --configuration debug` | 0 | `R/worker-f/app/AgentLensApp-debug.app`; `Build complete! (24.10 secs)` |
| Packaging | `python3 Tests/Packaging/test_dev_app_bundle.py --app R/worker-f/app/AgentLensApp-debug.app` | 0 | `Ran 9 tests ... OK` |
| Dev-app preflight | `AgentLensApp-debug.app/Contents/MacOS/AgentLensApp --bundle-preflight` | 0 | `bundle-preflight: ok registry_count=14 registry_ids=codex opencode grok claude gemini cline hermes aider goose kiro-cli omp agy dsh qodercli` |

## Acceptance-matrix mapping

| ID | Observed |
|---|---|
| F-AC01 | `capabilityMatrixMatchesTheBundledRegistry` and `capabilityMatrixAgreementRejectsSeededCorruption` pass; false `yes` and dropped row both fail the same agreement function; required limits and cross-note present |
| F-AC02 | `bundledRegistryNeverDeclaresCollisionIdentities` passes; seeded npm, homebrewFormula (`goose`), and homebrewCask (`qoder`) violations are all named |
| F-AC03 | `dataOnlyContributionLoadsExtraToolWithoutProductionChange` passes; extended JSON validates and the tool detects from data only; production id list and constructor proof intact; no production file changed |
| F-AC04 | build exit 0; full suite 547, zero skips/failures, exit 0; import guard clean; 21 guard fixtures OK; fresh dev app exit 0; 9 packaging OK |
| F-AC05 | floors are the measured 467 / 80 / 547 / 547; nothing lowered; anchors, guard 21, and packaging 9 unchanged |
| F-AC06 | CONTRIBUTING states license-pending and no-invitation; vocabularies match the validators; gate commands and CLT plugin note included |
| F-AC07 | the captured `git-status-after.txt` snapshot shows exactly the six allow-listed paths; this report was written after that snapshot and committed by the orchestrator, so it does not appear in it; no `Sources/**` change; protected manifest diff empty |

## Deviations and interpretations

**D-1 (toolchain plugin path).** The exact unflagged `swift build` passed. The exact unflagged
`swift test --no-parallel` failed at compile time before any test with the known CLT-only
`TestingMacros … plugin not found` (recorded in `full-suite-01.stdout/.stderr`). The same suite
rerun with the dispatch brief's invocation-local
`-Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing`
passed 547 with exit 0 (both runs retained). No package, toolchain, or `xcode-select` change.

**D-2 (dispatch HEAD).** The brief names accepted baseline `28738dc`; dispatch HEAD is `62aa642`,
whose only addition is the M11-F dispatch documents and a ROADMAP line. `28738dc` is an ancestor;
no product code differed at dispatch.

**D-3 (disabled reason wording for cask-only rows).** The brief's example `disabled: no declared
package` fits grok (no packages). `agy` and `kiro-cli` do declare cask candidates, so their cells
say `disabled: no declared npm package; cask mutation not shipped` and their latest-check cells
say `disabled: cask latest-check not shipped`. This names the actual cause instead of claiming no
package is declared; the agreement test accepts any non-empty `disabled` reason and rejects a
false `yes`.

**D-4 (matrix cross-note phrase).** The required `not formula proof` phrase was initially split
across a markdown line wrap, so the agreement test failed; the note was reflowed to keep the
phrase contiguous. No rule was weakened.

## Protected-file comparison

SHA-256 manifests for every tracked file outside the allow-list were captured before editing
(`R/evidence/f/protected-baseline.sha256`) and after (`protected-after.sha256`); `diff` reports no
difference (`protected-diff.txt`, 442 files). The captured `git status` snapshot
(`R/evidence/f/git-status-after.txt`, taken before this report was written) records only the three
modified allow-listed files and the three new allow-listed files; the orchestrator committed this
report afterward. No commit, branch, stage, reset, merge, push, or publish was performed.

Changed-file SHA-256 (`R/evidence/f/changed-sha256.txt`):

```text
2046412e9aeb66aed938033b100b6994d14177a7ce8501cda0be9ff25a9bf899  docs/capability-matrix.md
c63ab4c5150be7dadb8939592250a274a4bf6fbb5d528540fd6a96b12ae21ea2  docs/CONTRIBUTING.md
e902c221cb8ba238c5408c9257f317c800ddcc3b962d775c86c97e6e88ec0238  Tests/AgentLensCoreTests/CapabilityMatrixTests.swift
9c270a81a871e526a54f25975c27b109e4320172959875e73ab79c75949721a4  Tests/AgentLensCoreTests/DetectorRegistryTests.swift
7350dff2fa8f8c6b5c3ca0a0846d775969ebc6ec6fd13e8b3cb4deb57a0d2439  .github/workflows/ci.yml
ff52364f3ce955a81216f725c4c7273a83a8185d2006dcea9e850098de2afa3f  README.md
```

## Not claimed / open items

- Orchestrator acceptance and the independent read-only reviews remain external; this report is
  worker evidence only.
- No detector, registry row, layout, manager, source, UI, or mutation adapter was added; the
  registry JSON is unchanged.
- No license file exists and no public contribution invitation was made.
- Hosted CI was not run from this workstation; the floors are the measured local count and the
  orchestrator recounts independently. The known hosted combined-summary layout is unchanged.
