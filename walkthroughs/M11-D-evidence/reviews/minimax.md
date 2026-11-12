# M11-D — independent read-only review (MiniMax M3.1-Flash)

- **Reviewer:** MiniMax M3.1-Flash, summoned via Herdr/hc. Independent of the implementer
  (DeepSeek V4.1 Flash 1017 via OMP) and of the Grok reviewer.
- **Candidate:** commit `cdd8ccc` on `milestone/m11-catalogue`; product diff `git diff 8ac1b50..cdd8ccc`.
- **Authorities:** `briefs/M11-D-collision-batch.md` (frozen brief), `docs/catalogue-identities.md`
  (frozen identity packet, incl. the binding do-not-declare table), `briefs/M11-planning/judgment.md`
  (rulings R1–R12).
- **Mode:** READ-ONLY. No product edit, no Git mutation, no subagent, no install. The only file
  written by this review is this report.

## Verdict: **PASS**

0 blocking findings, 0 high/medium findings, 1 low finding, 3 informational findings. The candidate
satisfies the brief's registry contract, the binding do-not-declare table, the hermeticity
requirement, the exact-set test contract, and the scope/allow-list rules. Nothing found blocks
acceptance.

Findings are numbered below. Severity is my own judgment; INFO findings are recorded for the
orchestrator's awareness, not as objections.

---

## Findings

### 1. LOW — the permanent seeded control covers only the `npm` branch of the forbidden map

- **File:** `Tests/AgentLensCoreTests/DetectorRegistryTests.swift:217-224`, `:248-266`
- **Rationale:** `forbiddenCollisionPackages` is keyed by manager raw value with three branches
  (`homebrewFormula`, `homebrewCask`, `npm`), but the in-test seeded control at `:255-261` seeds
  only an npm package (`@aws/kiro-cli`). The two Homebrew branches therefore have no seeded
  control: a future typo in the `homebrewFormula`/`homebrewCask` keys would make the *bundled*
  assertion at `:250-251` pass vacuously for every brew-name row while the seeded control still
  passed on the npm path.
- **Not a defect in this candidate.** I verified the keys are exactly the `PackageManager` raw
  values (`Sources/AgentLensCore/Detection/DetectorMetadata.swift:61-64`: `npm`,
  `homebrewFormula`, `homebrewCask`), so no typo exists today, and the orchestrator's independent
  seed-corruption gate proves the bundled assertion is non-vacuous on a real path (npm `goose`
  seeded into the bundled registry → the test failed with
  `["npm goose (detector goose)"]`, then the file was restored byte-identically —
  sha256 `869f501adae9ad5a331ff387be599d68347753646d9d61e82272ae64872961dc`, matching the
  pre-seed hash and the current working copy).
- **Suggested (non-blocking, M11-F):** extend the seeded control to one `homebrewFormula` and one
  `homebrewCask` violation so all three branches are permanently non-vacuous.

### 2. INFO — agy's R10 legacy-root limit has no machine-readable carrier inside the registry

- **File:** `Sources/AgentLensCore/Detectors/DefaultDetectors.json:242`; schema at
  `Sources/AgentLensCore/Detection/DetectorRegistry.swift:130-142`, `:146-152`
- **Rationale:** `~/.gemini/bin` is the packet's `observed-local` legacy root
  (`docs/catalogue-identities.md:496`), permitted by R10 only "when explicitly marked
  `observed-local` with a matrix limit" (`briefs/M11-planning/judgment.md:184-187`). The registry
  schema has no notes/limits field and rejects unknown keys, so the mark cannot live in the
  registry. Today it lives in the frozen packet (`docs/catalogue-identities.md:496`, marked
  `observed-local` + `binding-plan`) and in the worker report
  (`walkthroughs/M11-D-implementation.md:39-41`, "the legacy root is the packet's observed-local
  root, never a fixture"). The matrix that R10 names — `docs/capability-matrix.md` — is an M11-F
  deliverable (`briefs/M11-plan.md:174-179`) and does not exist yet, so it is correctly out of
  M11-D scope.
- **Action:** none for M11-D. Carry the R10 limit forward so the M11-F matrix row for `agy` records
  the legacy `~/.gemini/bin` root as `observed-local` rather than dropping it.

### 3. INFO — hermeticity rests on PATH-first lookup ordering, not on the shadow set alone

- **Files:** `Sources/AgentLensCore/Detection/ToolDetector.swift:104-109`,
  `Sources/AgentLensCore/Diagnostics/PathDiagnostics.swift:184-191`, `:266-286`,
  `Tests/AgentLensCoreTests/UpdateCLIIntegrationTests.swift:651-667`, `:878-883`
- **Rationale (verification, not objection):** I traced the real-tool execution path rather than
  trusting the shadow set. `ToolDetector.locate` searches `environment.pathEntries` **before**
  `~`-expanded extra roots, and the diagnostics scanner consults `findExtraRootCandidate` only
  when there is **no** live PATH candidate; an extra-root target is version-probed only for an
  off-PATH selection. Consequently, in this fixture the extra roots are never even stat'd, let
  alone executed. This matters on this workstation: real `~/.local/bin/hermes` (76-byte wrapper),
  `~/.local/bin/omp` and `~/.gemini/bin/agy` (1.2.12) binaries exist, so a lookup-order inversion
  would have executed them. The candidate's six added `writeFakeTool` shadows make the ten-tool
  closed PATH complete and truthful; `gemini`/`cline` declare no extra roots and are genuinely
  absent.
- **Residual:** the exact-set assertion at `:878-883` observes only the fake-tool log, so its
  detection power against a future lookup-order regression depends on the real host having those
  binaries in the extra roots. On a host without `~/.local/bin/hermes`, such a regression would be
  invisible for that tool. Detected regressions would still fail the assertion (the fake would not
  be invoked → count ≠ 10), but the real binary would already have run once.

### 4. INFO — pressly/`goose` basename collision remains a documented runtime limit (correctly out of scope)

- **Files:** `Sources/AgentLensCore/Detectors/DefaultDetectors.json:181-189`,
  `Tests/AgentLensCoreTests/DetectorRegistryTests.swift:218`
- **Rationale:** the `goose` detector's executable basename is shared with pressly's formula
  `goose`; the registry declares only the frozen candidate `block-goose-cli`, and the permanent
  test forbids formula `goose` specifically. Runtime detection still cannot distinguish pressly's
  binary from the Goose CLI binary. This is recorded as a known limit in the frozen packet
  (`docs/catalogue-identities.md:339-341`) and the brief explicitly forbids fixing it with a
  scanner change, so the candidate is right to leave it alone. **Carried forward:** any future
  mutation phase must target the declared formula identity, never the `goose` basename.

---

## Verification detail

### (1) Every new registry row matches the frozen packet exactly

Verified programmatically against `docs/catalogue-identities.md` (summary table, lines 47-54) and
the brief's restated contract table (`briefs/M11-D-collision-batch.md:43-48`) — per row:
displayName, category, fixture (`singleDirectory`/`standalone`), packages (manager + name),
extraSearchRoots, informationURL, uninstallInstructionsURL (present/absent), and
`versionQuery` = `["--version"]` / stdout / first.

| id | displayName | category | packages | extraSearchRoots | verdict |
|---|---|---|---|---|---|
| `hermes` | Hermes | aiAgent | formula `hermes-agent` | `~/.local/bin` | exact |
| `aider` | Aider | aiCodingTool | formula `aider` | `[]` | exact |
| `goose` | Goose | aiCodingTool | formula `block-goose-cli` | `~/.local/bin` | exact |
| `kiro-cli` | Kiro CLI | aiCodingTool | cask `kiro-cli` | `~/.local/bin` | exact |
| `omp` | Oh My Pi | aiHarness | npm `@oh-my-pi/pi-coding-agent`; formula `can1357/tap/omp` | `~/.local/bin` | exact |
| `agy` | Antigravity CLI | aiHarness | cask `antigravity-cli` | `~/.local/bin`, `~/.gemini/bin` | exact |

- `id == executableName` for all twelve; order is exactly
  `codex opencode grok claude gemini cline hermes aider goose kiro-cli omp agy`.
- `acceptedOperations` key **absent** on all six new rows (D-021). The permanent assertion
  `definitions.dropFirst().allSatisfy { $0.acceptedOperations.isEmpty }`
  (`DetectorRegistryTests.swift:108`) keeps only `codex` mutating; the M11-B gate refuses
  update/uninstall for every unaccepted definition
  (`Sources/AgentLensAppSupport/InventoryViewModel.swift:313`, `:466`).
- No new layout, source, manager, or operation vocabulary: layouts `singleDirectory`/`npmGlobal`,
  sources `npm`/`standalone`, managers `npm`/`homebrewFormula`/`homebrewCask` are all pre-existing
  enum cases (`DetectorRegistry.swift:672-673`, `DetectorMetadata.swift:46-64`).

### (2) No do-not-declare identity is declared; the regression test is non-vacuous

- Independent scan of all twelve rows against the binding table
  (`docs/catalogue-identities.md:516-536`): **zero** forbidden package hits and **zero** forbidden
  ids/executables. Every row of that table whose manager is declarable in M11 is covered by the
  test's map (`DetectorRegistryTests.swift:217-226`): formula `dsh`/`goose`; npm
  `goose`/`kiro-cli`/`qoder`/`@qoder-ai/qoder`/`@aws/kiro-cli`/`@oh-my-pi/cli`; cask
  `qoder`/`opencode-desktop`/`block-goose`; ids/executables `kiro`/`qoder`. The table's PyPI rows
  (`goose`, `deepseek-harness`, `deepseek-harness-cli`, `google-antigravity`) are documentation-only
  per the packet's cross-entry rules (no PyPI `PackageManager` value exists in M11), so no
  declarable surface is left unguarded.
- The map is keyed by manager, so formula `goose` is rejected while formula `block-goose-cli` — the
  frozen Goose candidate — is not. Confirmed by the seeded control: an npm package named `goose`
  is caught; `block-goose-cli` is not a violation.
- **Non-vacuity, verified two ways:** (a) the in-test seeded control at `:255-265` validates a
  registry containing id `kiro`, executable `kiro`, npm `@aws/kiro-cli` and asserts all three
  violation strings appear — I confirmed that payload passes `DetectorRegistry.validate`
  (`DetectorRegistry.swift:784-884`: `fixture` is optional at `:857`/`parseFixture`, `packages`
  and `versionQuery` are present, manager `npm` is valid), so the control exercises the real code
  path rather than throwing; (b) the orchestrator's independent seed-corruption gate seeded npm
  `goose` into the real bundled registry and the test failed with
  `["npm goose (detector goose)"]` (`R/evidence/d/seed-corruption.stdout`), then the file was
  restored byte-identically and the test passed again
  (`R/evidence/d/seed-restored-pass.stdout`).

### (3) Hermetic CLI fixture

- All ten invoked tools are shadowed on the closed fixture PATH: `codex` (symlinked into a fake
  Cellar), `opencode`, `grok`, `claude`, `hermes`, `aider`, `goose`, `kiro-cli`, `omp`, `agy`
  (`UpdateCLIIntegrationTests.swift:643-664`, logging variants at `:827-840`).
- `gemini` and `cline` are truthfully absent: they declare no extra roots, and the closed PATH
  contains neither, so they are `not installed` rather than silently stubbed.
- No real-tool execution path exists (see Finding 3 for the code trace).
- The exact-set assertion was updated, not weakened: `detectorCalls.count == 10` **and**
  `Set(detectorCalls) == Set([...ten...])` (`:878-883`), with the message naming the ten tools and
  the absent pair. Per-tool once-only and brew-log assertions (`readLog(scenario.logURL).count == 3`,
  `:877`, and `:809-810`) are intact.

### (4) Exact-set assertions stay exact; ci.yml and floors untouched; existing six rows unchanged

- `bundledDefaultDetectorsMatchFrozenCatalogue` asserts the exact ordered twelve-id list, all
  twelve fixture pairs, the twelve-element category sequence, `versionQuery == .standard` for all,
  the codex mutation seed, and the frozen package/URL rows for each new entry
  (`DetectorRegistryTests.swift:79-160`). The existing six rows' assertions were not weakened —
  the diff only appends.
- Id lists updated in the four allow-listed places plus the packaging test
  (`BundledRegistryResourceTests.swift:592-596`, `BundleResourceTests.swift:33-53`,
  `UpdateCLIIntegrationTests.swift:878-883`, `Tests/Packaging/test_dev_app_bundle.py:129-142`,
  `:189-194`). The separate two-id fixture expectation
  (`registry_count=2 registry_ids=opencode codex`, `test_dev_app_bundle.py:274`) is untouched, as
  the brief requires.
- `.github/workflows/ci.yml` is **not** in the diff; the CI anchor
  `bundledDefaultDetectorsMatchFrozenCatalogue` carries no count, and the floors
  (Core 456 / AppSupport 79 / total 535 / packaging 9) are unchanged. The observed counts
  (464 / 80 / 544 / 9) clear them without any floor edit.
- The existing six registry rows are byte-identical to the `8ac1b50` baseline (verified by
  comparing the parsed first six entries against the baseline file: identical; the diff is
  append-only).
- `README.md` changed on exactly one line — the `verify-installation` accepted-id sentence, now
  listing the twelve shipped ids (`README.md:51`).

### (5) Scope drift beyond the allow-list

`git diff 8ac1b50..cdd8ccc --name-only` returns exactly eight paths, all allow-listed:

1. `README.md` (the one id sentence only)
2. `Sources/AgentLensCore/Detectors/DefaultDetectors.json`
3. `Tests/AgentLensAppSupportTests/BundleResourceTests.swift`
4. `Tests/AgentLensCoreTests/BundledRegistryResourceTests.swift`
5. `Tests/AgentLensCoreTests/DetectorRegistryTests.swift`
6. `Tests/AgentLensCoreTests/UpdateCLIIntegrationTests.swift`
7. `Tests/Packaging/test_dev_app_bundle.py`
8. `walkthroughs/M11-D-implementation.md` (the allowed worker report, explicitly labelled worker
   evidence, not acceptance)

No production Swift source, `Package.swift`, `scripts/**`, `.github/**`, `Resources/**`,
historical brief/walkthrough, or `docs/catalogue-identities.md` change is present. The frozen packet
was last touched by `c48b226` (M11-A) and is unmodified. No out-of-allow-list test pins the old
six-item list: a repo-wide search for the old ordered list finds only the allow-listed files plus
historical M11-C briefs/walkthroughs, which are correctly untouched.

---

## Acceptance matrix assessment

| ID | Expected | Reviewer assessment | Basis |
|---|---|---|---|
| D-AC01 | Twelve entries, exact order; new rows per contract; acceptance absent; existing rows unchanged | **PASS** | §(1), programmatic row-by-row comparison; baseline diff |
| D-AC02 | Collision regression passes; seeded corruption fails it | **PASS** | §(2); in-test seeded control + orchestrator seed-corruption gate |
| D-AC03 | build, full suite (543+, zero skips/failures), both import guards, fresh dev app, 9 packaging — exit 0 | **PASS (orchestrator rerun)** | `R/evidence/d/gates.tsv`: build 0, full-flagged 0 (464+80=544), guard-core-ui 0 (32 files), guard-packaging 0 (21 OK), build-dev-app 0, packaging 0 (9 OK); unflagged runs fail only with the documented D-1 `TestingMacros` plugin error before any test executes |
| D-AC04 | `registry_count=12` with the exact id list; built CLI scan shows twelve entries with truthful states | **PASS** | `R/evidence/d/dev-app-preflight.stdout` = `bundle-preflight: ok registry_count=12 registry_ids=codex opencode grok claude gemini cline hermes aider goose kiro-cli omp agy`; `R/evidence/d/cli-scan-parity.stdout` shows all six new entries with correct categories (AI Agent / AI Coding Tool ×3 / AI Harness ×2) and truthful versions |
| D-AC05 | Exact invoked set = ten shadowed tools; gemini/cline absent; no real tool executed | **PASS** | §(3), code-level trace of the lookup and probe order |
| D-AC06 | Diff within allow-list; protected hashes otherwise clean; ci.yml/floors untouched | **PASS** | §(4), §(5); working tree clean, registry hash restored |

---

## What I did not verify

- I did not re-run `swift build` / `swift test` myself. The gate results above are the
  orchestrator's independent rerun, read from `R/evidence/d` (`gates.tsv`, `full-suite.stdout`,
  `seed-corruption.stdout`, `dev-app-preflight.stdout`, `cli-scan-parity.stdout`). My independent
  work was static: every claim above was checked against the code and data, not against
  `walkthroughs/M11-D-implementation.md`.
- I did not open the other reviewer's file.
- The D-1 toolchain workaround (`-Xswiftc -plugin-path …/swift/host/plugins/testing`) is an
  invocation-local environment workaround, matching the M11-C precedent; it changes no package,
  toolchain, or `xcode-select` state, and I found no repo change that would conceal it.
- I did not visually inspect the native app; M11-D makes no UI change, and the dev-app preflight
  plus the 9-test packaging suite are the in-scope native checks.

## Evidence consulted

- `briefs/M11-D-collision-batch.md` (frozen brief)
- `docs/catalogue-identities.md` (frozen packet; summary table, entries 7–14, binding
  do-not-declare table, cross-entry rules)
- `briefs/M11-planning/judgment.md` (R10), `briefs/M11-plan.md` (§ M11-D, M11-F)
- `Sources/AgentLensCore/Detectors/DefaultDetectors.json`, `Sources/AgentLensCore/Detection/DetectorRegistry.swift`,
  `Sources/AgentLensCore/Detection/ToolDetector.swift`, `Sources/AgentLensCore/Detection/DetectorMetadata.swift`,
  `Sources/AgentLensCore/Diagnostics/PathDiagnostics.swift`, `Sources/agent-lens/main.swift`,
  `Sources/AgentLensAppSupport/InventoryViewModel.swift`
- `Tests/AgentLensCoreTests/DetectorRegistryTests.swift`, `BundledRegistryResourceTests.swift`,
  `UpdateCLIIntegrationTests.swift`, `MutationAcceptanceGateTests.swift`,
  `Tests/AgentLensAppSupportTests/BundleResourceTests.swift`, `Tests/Packaging/test_dev_app_bundle.py`,
  `.github/workflows/ci.yml`
- Orchestrator gate evidence under `/Users/corvette/.hermes/cache/scratch/agent-lens-m11-Jb11B5/evidence/d/`
