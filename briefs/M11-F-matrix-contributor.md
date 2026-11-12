# M11-F — capability matrix and contributor foundation (dispatch brief)

Status: authorized under the owner-approved M11 plan (2026-11-12). Worker brief, not acceptance
evidence. Freeze this revision once dispatched; corrections use a separate revision brief.

## Identity and authority

- Phase: M11-F, revision 1. Milestone branch: `milestone/m11-catalogue`.
- HEAD baseline: `28738dc86f6911a633df3b138ae1ef07ed7c07dd` (M11-E accepted; 14-entry catalogue).
  Parent baseline: 464 Core + 80 AppSupport = 544 tests, exit 0.
- Sole implementer: **DeepSeek V4.1 Flash 1017 via OMP** (`river/deepseek-ai/DeepSeek-V4.1-Flash-1017`,
  `--thinking max`), owner-selected. No other implementer, subagent, provider, model or CLI.
- **Independent read-only review is REQUIRED** (matrix truth is a safety property; the contribution
  proof is an M11 acceptance clause): MiniMax M3.1-Flash/xhigh (mcode) and Grok 4.7/high (grok CLI),
  summoned through Herdr/hc after the candidate is frozen.
- Orchestrator owns acceptance and all Git delivery. **Do not stage, commit, branch, reset, merge,
  push, or publish.**
- Evidence root `R`: `/Users/corvette/.hermes/cache/scratch/agent-lens-m11-Jb11B5`. Use
  `R/worker-f`, `R/tmp` (TMPDIR), `R/evidence/f`.
- Authority: `briefs/M11-plan.md` §5 M11-F and rulings R1/R3/R7; `docs/catalogue-identities.md`
  (frozen packet — the source of every limit cell); `walkthroughs/M11-D-acceptance.md`
  (carry-forward requirements). OD-7 (license) is STILL OPEN — the owner has not chosen; no
  LICENSE file, no public contribution invitation.

## Goal and exclusions

Publish the truthful capability matrix, the contributor guide, and the data-only contribution
proof; extend the collision regression's seeded control; raise CI floors to the measured count.

Exclusions: no new detector or registry data change; no production Swift change under
`Sources/AgentLensCore/Detection/`, `Ownership/`, `Operations/`, `Updates/` (the registry JSON is
READ-ONLY this phase); no UI change; no new layout/manager vocabulary; no renderer/validator
scripts (R3: the Swift test is the enforcement; no `scripts/**` additions); no license file; no
public invitation; no anchor rename (anchors stay as M11-C set them).

## Deliverable 1 — `docs/capability-matrix.md` + agreement test

One markdown table, one row per bundled detector id (all fourteen, registry order), columns
EXACTLY:

`| id | display name | category | tested fixture | declared packages | latest-check | Update | Uninstall | known limits |`

Cell rules (the test enforces ALL of these):
- `tested fixture`: `synthetic <layout>` using the registry's fixture layout — NEVER "verified"
  against a vendor tree.
- `declared packages`: every registry candidate as `<manager>:<name>` (managers spelled
  `npm`, `homebrewFormula`, `homebrewCask`), semicolon-separated, registry order; `none` when empty.
- `latest-check`: `yes: npm` only if an npm candidate is declared; `yes: homebrewFormula` only if
  a formula candidate is declared (both may appear, semicolon-separated); otherwise
  `disabled: <reason>` (e.g. `disabled: no declared package`). Cask latest-check is NEVER `yes`
  (not shipped).
- `Update` / `Uninstall`: `yes: npm (verified npm-global copies only)` ONLY for an entry whose
  registry `acceptedOperations` contains the matching operation AND declares an npm candidate
  (today: codex only). Every other row: `informational: <reason>` or `disabled: <reason>` naming
  the cause (e.g. `informational: no accepted mutation scenario (M11); adapter M13` for
  formula-only entries; `disabled: no declared package` for grok/agy/kiro-cli).
- `known limits`: non-empty for every row; specific facts from the frozen packet. REQUIRED limits
  (carry-forwards, do not drop):
  - codex: optional-dependency install failure yields unknown version; cask/standalone classify
    standalone; vendor installer rerun is not an Agent Lens operation.
  - opencode: `opencode2` second executable; tap conflicts; desktop cask excluded.
  - grok: no package identity; version line carries build hash/channel noise.
  - claude: native launcher symlink into a versions store (not a fixture/root); background
    auto-update is vendor-owned; npm optional platform dependency.
  - gemini: formula DEPRECATED 2026-06-18, DISABLED 2026-12-18, replacement cask antigravity-cli;
    upstream transition banner; MacPorts/npx not declarable.
  - cline: formula DEPRECATED 2026-05-18, DISABLED 2027-05-18; personal signature shim is not a
    layout; npm-under-Homebrew-prefix is not a formula.
  - hermes: git-checkout install classifies standalone; PyPI identity not declarable; second
    executables hermes-agent/hermes-acp; multi-field version line (first token wins).
  - aider: **cold start measured 3747 ms > 3 s query budget → unknown on cold start**; uv/pip/pipx
    not declarable; vendor dependency warning.
  - goose: basename shared with pressly formula `goose` — mutation identity is the declared
    formula `block-goose-cli`, never the basename; desktop cask excluded; helper binaries.
  - kiro-cli: never detect `kiro` (IDE/router); formula does not exist (cask only); installer
    `--version` option is not the CLI query; DMG app surface excluded.
  - qodercli: `qoder` dispatcher can launch the IDE (not the detector); versioned runtime filename
    is a personal artifact; cask `qoder` is the IDE.
  - dsh: developer preview with breaking changes upstream; prerelease tokens normal; brew `dsh`
    is Dancer's shell (never declared); third-party PyPI names excluded.
  - omp: `@oh-my-pi/cli` is a different project (excluded); Tern-store copy is not the tap; bun
    not declarable.
  - agy: **legacy root `~/.gemini/bin` is observed-local only (R10), not a documented default**;
    cask `auto_updates: true` and `agy update` are vendor-owned; Python SDK excluded.
  - Cross-row note (above or below the table): source classification is heuristic
    (`/lib/node_modules/` → npm, `/Cellar/` → brew, else standalone); cask/script/uv/git/Tern
    installs classify standalone; a Homebrew-prefix path is not formula proof.

The agreement test (new file `Tests/AgentLensCoreTests/CapabilityMatrixTests.swift`):
- Locates `docs/capability-matrix.md` relative to `#file` (repo root), parses the table rows
  deterministically (strict format above; fail on malformed rows).
- Asserts: row id set == registry id set (each exactly once, registry order); display name,
  category, fixture layout, and declared packages match `DetectorRegistry.loadDefault()`;
  latest-check/Update/Uninstall cells obey the cell rules against each definition's packages and
  `acceptedOperations`; every known-limits cell non-empty; the required carry-forward limits
  present (assert distinctive substrings: `3747`, `2026-12-18`, `2027-05-18`, `~/.gemini/bin`,
  `pressly`, `opencode2`, `Dancer`).
- A seeded corruption in a test copy (e.g. flip one Update cell to `yes: npm` for an unaccepted
  entry, or drop a row) must fail the parse/agreement — prove non-vacuity in the test.

## Deliverable 2 — collision regression seeded-control extension (M11-D carry-forward)

In `DetectorRegistryTests.swift`, extend the in-test seeded control of
`bundledRegistryNeverDeclaresCollisionIdentities` with ONE homebrewFormula violation (e.g. formula
`goose`) and ONE homebrewCask violation (e.g. cask `qoder`), asserting the named violations are
detected — so all three manager branches are permanently non-vacuous. Keep the existing npm seed.

## Deliverable 3 — data-only contribution proof

New test (in `CapabilityMatrixTests.swift` or `DetectorRegistryTests.swift` — one place): build a
schemaVersion-2 JSON string containing the CURRENT bundled detectors plus ONE extra definition
(id `contrib-proof-tool`, singleDirectory/standalone, no packages, standard query), load it through
`DetectorRegistry.validate` + the existing detector builder, and detect a synthetic executable in
a scratch fixture tree; assert the production `DefaultDetectors.json` id list is UNCHANGED in the
same test. No production file gains the tool. Keep the existing Swift-constructor proof
`addingAFourthDefinitionRequiresNoSourceChanges` intact.

## Deliverable 4 — `docs/CONTRIBUTING.md`

Contributor guide stating: the exact files to edit for a new tool on an existing layout
(`DefaultDetectors.json` + the id-list tests + the matrix row + README id sentence); every field
and closed vocabulary (categories, managers, layouts, versionQuery bounds, HTTPS URL rules);
evidence rules (`verified-docs`/`observed-local`/`unverified`, primary sources, no guesses);
a fixture proves the detector, never a real installation; unobserved layouts are never "verified";
declared candidates are never ownership proof; personal artifacts are never roots/fixtures;
the do-not-declare table pointer; the mutation acceptance gate (D-021: new tools are informational
until a separately accepted scenario); **license: not yet selected — the owner must choose MIT or
Apache-2.0 before any public contribution invitation (no later than M18); contributions are not
publicly invited yet**; the exact local gate commands (including the CLT-only plugin-path note).

## Deliverable 5 — CI floors (measured, never lowered)

Run the full suite, count Core/AppSupport/total from the Swift Testing summaries, and raise
`.github/workflows/ci.yml` floors (Core floor, AppSupport floor, total/combined floors) to EXACTLY
that measured count. Guard-fixtures 21 and packaging 9 unchanged. Anchors unchanged. Update the
floor comments truthfully (M11-F measurement). Record the measured count in the worker report;
the orchestrator will recount independently — a mismatch is a revision.

## README

Add links to `docs/capability-matrix.md` and `docs/CONTRIBUTING.md` (one short section or two
lines); keep the fourteen-id sentence truthful. No other README change.

## Allow-list

- Add `docs/capability-matrix.md`, `docs/CONTRIBUTING.md`
- Add `Tests/AgentLensCoreTests/CapabilityMatrixTests.swift`
- `Tests/AgentLensCoreTests/DetectorRegistryTests.swift` (seeded-control extension + optional
  contribution proof if placed here)
- `.github/workflows/ci.yml` (floor numbers + truthful floor comments ONLY)
- `README.md` (links + truthful id sentence ONLY)
- Add `walkthroughs/M11-F-implementation.md` (worker report, labeled worker evidence)

DO NOT TOUCH: `Sources/**` (registry JSON read-only this phase), `Package.swift`, `scripts/**`,
`Tests/Packaging/**`, other tests, `Resources/**`, historical briefs/walkthroughs, root docs
except README, `docs/catalogue-identities.md` (frozen), DECISIONS/ROADMAP/scope, personal
installations, the real Agent Lens cache, credentials. No LICENSE file.

## Acceptance matrix

| ID | Scenario | Expected observation |
|---|---|---|
| F-AC01 | Matrix agreement | Test passes; every row matches the registry; cell rules enforced; required limits present; seeded corruption fails |
| F-AC02 | Seeded-control extension | All three manager branches detect seeded violations |
| F-AC03 | Contribution proof | Extra tool loads/detects from JSON only; production id list unchanged; constructor proof intact |
| F-AC04 | Full gates | build, full suite (544+new, zero skips/failures), guards, dev app, 9 packaging — exit 0 |
| F-AC05 | Floors | ci.yml floors equal the orchestrator-recounted suite; nothing lowered; anchors/guard/packaging unchanged |
| F-AC06 | Guide | CONTRIBUTING states license-pending + no-invitation; vocabularies match the validator; commands correct |
| F-AC07 | Scope | diff within allow-list; no Sources change; protected hashes otherwise clean |

## Exact gates and evidence

```sh
env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS swift build
env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS swift test --no-parallel
python3 scripts/check-core-ui-imports.py
python3 Tests/Packaging/test_core_ui_imports.py
python3 scripts/build-dev-app.py --scratch-root R/worker-f/app --configuration debug
python3 Tests/Packaging/test_dev_app_bundle.py --app R/worker-f/app/AgentLensApp-debug.app
```

Environment note (M11-C/D/E): if the suite fails before any test with `TestingMacros … plugin not
found`, rerun with
`-Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing`
and record BOTH runs. No package/toolchain/xcode-select change.

Raw evidence under `R/evidence/f`; SHA-256 of changed files; protected manifest comparison;
the measured suite count. Orchestrator reruns independently; reviewers read the frozen candidate.

## Stop conditions

Stop and report if: the matrix cannot be expressed truthfully under the cell rules; the agreement
test requires a production change; the contribution proof needs a new layout/manager; the measured
count is ambiguous; any out-of-allow-list file seems required; anything asks for credentials or
privileges.

## Report contract

```sh
hc send t7x "M11-F complete: matrix/contributor candidate — <tests count, floors, gates, deviations>"
```