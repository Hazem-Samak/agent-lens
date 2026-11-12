# M11-F — capability matrix and contributor foundation: independent review (MiniMax)

Reviewer: **MiniMax M3.1-Flash** (mcode, independent read-only reviewer).
Date: 2026-11-12. Candidate: `d3f0324` on `milestone/m11-catalogue`.
Product diff reviewed: `git diff 62aa642..d3f0324`.
Spec: `briefs/M11-F-matrix-contributor.md` (frozen, revision 1).
Limit-cell source of truth: `docs/catalogue-identities.md` (frozen M11-A packet).
Carry-forwards: `walkthroughs/M11-D-acceptance.md`.

**Verdict: PASS** — 0 blocking, 0 high, 0 medium, 0 low, 5 informational.

No product edit, git mutation, subagent, or install was performed by this reviewer. The only file
written is this report. Findings were verified against code, registry JSON, the frozen packet, and
the orchestrator's own gate logs — not against the worker's report.

---

## 1. What was independently verified

| # | Check | Method | Result |
|---|---|---|---|
| 1 | Matrix row set / order / identity cells | Re-parsed `docs/capability-matrix.md` with an independent Python parser and compared against `Sources/AgentLensCore/Detectors/DefaultDetectors.json` | **PASS** — 14 rows, exact registry order, zero mismatches |
| 2 | Capability cell rules | Independent re-implementation of the cell rules from the brief | **PASS** — all 14 rows conform |
| 3 | Required carry-forward limits | Independent per-row keyword check against the brief's limit list | **PASS** — all 14 rows carry their required limits |
| 4 | Agreement-test non-vacuity | Read the seeded-corruption test; corroborated by the orchestrator's own `focused-02b` failure | **PASS** — genuinely non-vacuous |
| 5 | Parser determinism | Traced parser, ordering, and every `Set`/`Dictionary` iteration | **PASS** — fully deterministic |
| 6 | Contribution proof | Traced `loadDefaultRegistryData` → `DetectorRegistry.validate` → `makeDetector` → `detect` | **PASS** — production validator, production bytes, production unchanged asserted |
| 7 | Seeded collision control | Read `DetectorRegistryTests.swift:274-302` | **PASS** — all three manager branches seeded and named |
| 8 | Floors | Read `ci.yml`; recounted the suite from `parent-02-suite.log` | **PASS** — 467 / 80 / 547 exactly; anchors, guard 21, packaging 9 unchanged |
| 9 | CONTRIBUTING | Cross-checked every vocabulary and field claim against the validator source | **PASS** — all claims accurate |
| 10 | Scope | `git diff --name-only` per protected path | **PASS** — allow-list only; zero `Sources/**` changes |

### 1.1 Matrix truth (re-derived, not taken on trust)

An independent parser read the markdown table and compared every cell to the registry JSON:

- 14 data rows; ids and order identical to `DefaultDetectors.json`
  (`codex, opencode, grok, claude, gemini, cline, hermes, aider, goose, kiro-cli, omp, agy, dsh, qodercli`).
- `display name`, `category`, `tested fixture` (`synthetic <layout>`, registry layout only),
  and `declared packages` (`<manager>:<name>`, semicolon-separated, registry order, `none` when
  empty) matched all 14 rows — **no mismatches**.
- The table header at `docs/capability-matrix.md:26` is byte-identical to the Swift constant at
  `Tests/AgentLensCoreTests/CapabilityMatrixTests.swift:23-24`, and appears exactly once.

Capability cells, re-derived from the registry and checked against the brief's rules:

- **`Update` / `Uninstall`** — `yes: npm (verified npm-global copies only)` appears on **codex
  only**, the sole entry whose `acceptedOperations` contains the matching operation *and* which
  declares an npm candidate. Every other row is `informational: <reason>` or `disabled: <reason>`
  with a non-empty reason. No other row carries a `yes` claim.
- **`latest-check`** — `yes: npm` only where an npm candidate is declared; `yes: homebrewFormula`
  only where a formula candidate is declared; both, semicolon-separated, where both exist
  (`opencode`, `gemini`, `cline`, `omp`); `disabled: <reason>` otherwise (`grok`, `kiro-cli`,
  `agy`, and the npm/formula-only-elsewhere cases). **No cell claims a cask latest-check.**
- **`tested fixture`** — every row reads `synthetic <layout>`; no row says "verified" against a
  vendor tree.
- **`known limits`** — non-empty on all 14 rows.

### 1.2 Required carry-forward limits — all present

Verified per row against the brief's REQUIRED limit list and the frozen packet:

- **codex** — optional-dependency failure → unknown version (never an error); cask/standalone
  classify `standalone`; vendor installer rerun is not an Agent Lens operation; Homebrew-prefix
  npm copy is npm, not a formula; no formula listing.
- **opencode** — `opencode2` second executable; tap conflict; desktop cask `opencode-desktop` excluded.
- **grok** — no package identity; build hash and channel token in the version line.
- **claude** — `versions/` launcher store (not a fixture/root); background auto-update is
  vendor-owned; npm optional platform dependency.
- **gemini** — formula DEPRECATED 2026-06-18 (`unsupported`), DISABLED 2026-12-18, replacement
  cask `antigravity-cli`; upstream transition banner; MacPorts/npx not declarable.
- **cline** — formula DEPRECATED 2026-05-18, DISABLED 2027-05-18; personal signature shim is not
  a layout; npm-under-Homebrew-prefix is not a formula.
- **hermes** — git-checkout → `standalone`; PyPI identity not declarable; second executables
  `hermes-agent` / `hermes-acp`; multi-field version line, first token wins.
- **aider** — cold start measured **3747 ms** above the 3 s budget → unknown on cold start;
  uv/pip/pipx not declarable; vendor dependency warning.
- **goose** — basename shared with pressly formula `goose`; mutation identity is `block-goose-cli`,
  never the basename; desktop cask excluded; helper binaries named.
- **kiro-cli** — never detect `kiro`; formula does not exist (cask only); installer `--version` is
  not the CLI query; DMG app surface excluded.
- **qodercli** — `qoder` dispatcher can launch the IDE; versioned runtime filename is a personal
  artifact; cask `qoder` is the IDE.
- **dsh** — developer preview with upstream breaking changes; prerelease tokens normal; brew `dsh`
  is **Dancer's** shell, never declared; third-party PyPI names excluded.
- **omp** — `@oh-my-pi/cli` is a different project (excluded); Tern-store copy is not the tap;
  bun not declarable.
- **agy** — legacy root `~/.gemini/bin` is **observed-local** only (R10), not a documented
  default; cask `auto_updates: true` and `agy update` are vendor-owned; Python SDK excluded.

All seven distinctive carry-forward substrings the brief requires the test to assert are present
in the document: `3747`, `2026-12-18`, `2027-05-18`, `~/.gemini/bin`, `pressly`, `opencode2`,
`Dancer`.

The cross-row note is present (`docs/capability-matrix.md:43-53`) and states the heuristic
(`/lib/node_modules/` → npm, `/Cellar/` → brew, else `standalone`), that cask/script/uv/git/Tern
installs classify `standalone`, and that a Homebrew-prefix path is not formula proof.

### 1.3 Agreement test — non-vacuous, and the parser is deterministic

`Tests/AgentLensCoreTests/CapabilityMatrixTests.swift:414-444` seeds **two** independent
corruptions on in-memory copies (the repository file is never written):

1. `opencode`'s Update cell is replaced with the `yes: npm (verified npm-global copies only)`
   literal. `opencode` has no `acceptedOperations`, so `mutationCellProblems`
   (`CapabilityMatrixTests.swift:176-205`) must reject it. The test asserts the failure is
   non-empty **and** names `opencode` + `Update`.
2. The `opencode` row is dropped. The id-set comparison (`CapabilityMatrixTests.swift:250-254`)
   must fail, and the test asserts the failure names `opencode`.

This is not a claim I took on trust — it is corroborated by the orchestrator's own evidence.
`R/evidence/f/focused-02b.stdout` records a **real** run in which the agreement function
correctly rejected a matrix whose cross-row note had the `not formula proof` phrase split across a
line wrap:

```
✘ Test capabilityMatrixMatchesTheBundledRegistry() recorded an issue at CapabilityMatrixTests.swift:408:5
↳ capability matrix disagreements: capability matrix is missing the cross-row note substring 'not formula proof'
```

The next run (`focused-03.stdout`) passes all four M11-F contract tests with exit 0. The worker
recorded the same episode as deviation D-4. The agreement function demonstrably fails on a
mutated document and passes on the shipped one.

**Parser determinism** (`CapabilityMatrixTests.swift:88-139`): the header is located by exact
string equality (`firstIndex(of:)`), the separator is matched by a fixed per-cell regex, rows are
read only while the line begins with `|`, and every row must have exactly nine non-empty cells
with a non-empty id. A malformed row throws rather than being skipped, so the parser fails
closed. Line splitting uses `.newlines`, and every set/dictionary whose iteration order could
reach a message is explicitly `.sorted()`
(`CapabilityMatrixTests.swift:255-265`). No ordering ambiguity can leak into a verdict.

### 1.4 Data-only contribution proof — genuinely production

`CapabilityMatrixTests.swift:448-524`:

- The extended payload is built from `DetectorRegistry.loadDefaultRegistryData()` — the **same
  production byte loader** `loadDefault()` uses
  (`Sources/AgentLensCore/Detection/DetectorRegistry.swift:700-703, 712-773`), not a hand-written
  copy of the registry.
- The extra definition is loaded through `DetectorRegistry.validate(data:)`
  (`DetectorRegistry.swift:784`) — the **production validator** — and built through the
  **production** `makeDetector` (`DetectorRegistry.swift:334`).
- Detection runs in a scratch tree: a real executable is written with mode 0755 into a
  `AGENT_LENS_TEST_SCRATCH`/`TMPDIR` root, and the detector is given a PATH containing only that
  root. The assertion `state == .installedAndOnPath` and `source == "standalone"` is a genuine
  detection, and it is hermetic: the proof definition declares `extraSearchRoots: []`, and
  `ToolDetector.locate` consults PATH first (`ToolDetector.swift:103-116`).
- **Production unchanged is asserted in the same test**: the production id list is pinned to the
  exact fourteen ids (`CapabilityMatrixTests.swift:451-457`) and re-verified after the extended
  load (`CapabilityMatrixTests.swift:520-523`).
- No production file gains the tool — confirmed independently: `git diff --name-only
  62aa642..d3f0324 -- Sources/` returns **0 files**, and `DefaultDetectors.json` is unchanged.
- The existing Swift-constructor proof `addingAFourthDefinitionRequiresNoSourceChanges` is intact
  at `Tests/AgentLensCoreTests/DetectorRegistryTests.swift:493`, untouched by the diff.

### 1.5 Seeded collision control — all three manager branches

`Tests/AgentLensCoreTests/DetectorRegistryTests.swift:274-302`. The in-test seeded control now
carries one violation per manager branch and asserts each by exact message:

| Branch | Seed | Assertion |
|---|---|---|
| `npm` | `@aws/kiro-cli` (kept from M11-D) | `npm @aws/kiro-cli (detector kiro)` (`:299`) |
| `homebrewFormula` | formula `goose` | `homebrewFormula goose (detector seed-formula)` (`:300`) |
| `homebrewCask` | cask `qoder` | `homebrewCask qoder (detector seed-cask)` (`:301`) |

The forbidden map (`DetectorRegistryTests.swift:243-246`) already contained `goose` under
`homebrewFormula` and `qoder` under `homebrewCask`, and the seeded registry is loaded through the
production `DetectorRegistry.validate`, so the branches are exercised against real validation.
The M11-D MiniMax ruling #1 (npm branch only) is now discharged.

### 1.6 CI floors — measured, never lowered

Independently recounted from the orchestrator's own rerun
(`R/evidence/f/parent-02-suite.log`), not from the worker's file:

```
✔ Test run with 467 tests in 0 suites passed after 108.398 seconds.
✔ Test run with 80 tests in 5 suites passed after 7.368 seconds.
```

Zero `✘`, zero `recorded an issue`, zero `skipped` markers in that log. `467 + 80 = 547`.

Arithmetic reconciliation: the M11-D accepted baseline was 464 Core + 80 AppSupport; M11-E added
**0** new `@Test` functions (`git diff cdd8ccc..28738dc -- Tests/` → 0 added `@Test`), and M11-F
adds exactly **3** (`CapabilityMatrixTests.swift`). `464 + 3 = 467`; AppSupport is unchanged at 80.
The floors therefore equal the measured count exactly, with no inflation.

`ci.yml` floors are `Core 467`, `AppSupport 80`, `total_floor 547`, `combined_total_floor 547`.
Nothing was lowered. `CORE_ANCHORS`, `APPSUPPORT_ANCHORS`, `guard-fixtures` 21, `packaging` 9,
and every other workflow value are unchanged — the ci.yml diff touches only four floor numbers
and comment lines. The floor-history comment records the M11-F measurement truthfully.

### 1.7 CONTRIBUTING — license status and validator vocabulary

- **License pending / no invitation**: `docs/CONTRIBUTING.md:3-6` states the repository has **no
  license file**, that the owner has not selected one, that **MIT or Apache-2.0** must be chosen
  before any public contribution invitation (no later than **M18**), and that contributions are
  **not publicly invited yet**. `README.md:11` repeats this. No `LICENSE` file exists anywhere in
  the repository — confirmed. The brief's OD-7 "still open" condition is respected.
- **Vocabularies verified against the validator source**, not paraphrased:
  categories `aiAgent / aiCodingTool / aiHarness` (`DetectorMetadata.swift:46-49`); managers
  `npm / homebrewFormula / homebrewCask` (`DetectorMetadata.swift:61-64`); layouts
  `npmGlobal / singleDirectory / brewCellar` (`DetectorRegistry.swift:672`); expected sources
  `npm / brew / standalone` (`DetectorRegistry.swift:673`); query stream `stdout / stderr` and
  line `first / firstNonempty` (`DetectorMetadata.swift:165-173`); bounds 1–8 arguments, ≤256
  UTF-8 bytes each, 1024 bytes total (`DetectorMetadata.swift:175-177, 204-226`); two-component
  package names rejected (`DetectorMetadata.swift:144-157`); unknown keys rejected at root,
  definition, fixture, package and query levels (`DetectorRegistry.swift:805, 846, 1002, 1051,
  1143`); schema 1 rejected (`DetectorRegistry.swift:671`).
- The guide's `fixture | policy: yes` correctly distinguishes *policy-required* from
  *validator-required* — `parseFixture` returns nil when absent
  (`DetectorRegistry.swift:992-996`), so calling it simply "required" would have been false.
- `id == executableName` for bundled entries is genuinely enforced
  (`DetectorRegistryTests.swift:87`), as the guide claims.
- The file list for adding a tool was checked against the files it names: `DefaultDetectors.json`,
  `DetectorRegistryTests.swift` (id list at `:84-86`), `BundledRegistryResourceTests.swift:596`,
  `AgentLensAppSupportTests/BundleResourceTests.swift:40,50`,
  `UpdateCLIIntegrationTests.swift:885`, `Tests/Packaging/test_dev_app_bundle.py:132,138,193`
  (and the separate two-id fixture expectation at `:275` is correctly left untouched),
  `docs/capability-matrix.md`, and the `README.md` `verify-installation` id sentence at `:55`.
  Every named file genuinely contains the claim attributed to it, and every path exists.
- Local gate commands match the brief's gates, including the CLT-only plugin-path workaround and
  the instruction not to change `Package.swift`, the toolchain, or `xcode-select`.

### 1.8 Scope — allow-list only

`git diff --name-only 62aa642..d3f0324` returns exactly seven paths, all allow-listed:
`docs/capability-matrix.md`, `docs/CONTRIBUTING.md`,
`Tests/AgentLensCoreTests/CapabilityMatrixTests.swift`,
`Tests/AgentLensCoreTests/DetectorRegistryTests.swift`, `.github/workflows/ci.yml`, `README.md`,
`walkthroughs/M11-F-implementation.md`.

Zero changes under `Sources/`, `scripts/`, `Tests/Packaging/`, `Resources/`, or to
`Package.swift` or `docs/catalogue-identities.md` (the frozen packet). The registry JSON is
unchanged. The `ci.yml` diff is confined to floor numbers and truthful floor comments; the
`README.md` diff is one short section with the two links plus the license/no-invitation sentence,
and the fourteen-id `verify-installation` sentence is untouched. The worker's report is labeled
worker evidence, not acceptance.

### 1.9 Orchestrator gates

From `R/evidence/f/`: build exit 0; full suite exit 0 (467 + 80 = 547, zero skips, zero
failures); import guard exit 0 (32 Core files, no SwiftUI/AppKit imports); 21 guard fixtures OK;
fresh dev app exit 0; 9 packaging tests OK; `bundle-preflight: ok registry_count=14` with the
exact fourteen ids. All six `parent-*.log` files end in success. The worker's recorded
SHA-256 values for all six changed files match the files byte-for-byte, and
`protected-diff.txt` is empty.

---

## 2. Findings

No blocking, high, medium, or low findings. Five informational observations, none of which
requires a code change to accept.

### INFO-1 — Matrix prose is one clause stricter than the test enforces
**File:** `docs/capability-matrix.md:18-21`

The "How to read the capability cells" prose says an `Update`/`Uninstall` `yes` means all of:
accepted operation, declared npm candidate, **and** the ownership probe verified an npm-global
copy. The agreement test (`CapabilityMatrixTests.swift:176-205`) enforces only the first two
conditions, matching the brief's cell rule verbatim. A future entry that received
`acceptedOperations` and an npm candidate without ownership verification would therefore still
pass the agreement test while the prose reads stricter. The asymmetry is in the safe direction —
the prose can never license a `yes` the test would reject — so it is not a defect. Recording it
so the next phase does not read the prose as a third enforced rule.

### INFO-2 — The test pins 7 substrings across 14 rows; the brief's full limit list is content-verified but not regression-pinned
**File:** `Tests/AgentLensCoreTests/CapabilityMatrixTests.swift:157-165`

`requiredLimitMarkers` covers `opencode2`, gemini `2026-12-18`/`antigravity-cli`, cline
`2027-05-18`, aider `3747`, goose `pressly`/`block-goose-cli`, agy `~/.gemini/bin`, dsh `Dancer`
— exactly the seven substrings the brief requires the test to assert, so the test satisfies the
brief precisely. The brief's Deliverable 1 additionally enumerates roughly forty required limit
facts across the remaining rows (e.g. codex's "vendor installer rerun is not an Agent Lens
operation", claude's `versions/` store, the gemini/cline deprecation calendar). Those facts are all
present in the shipped matrix and I verified each one, but they are not pinned by the test: a
future edit could drop, say, the codex installer-rerun limit and the suite would stay green. Not a
brief violation; worth a future-phase decision on whether to widen the marker map.

### INFO-3 — The `disabled:` wording for cask-only rows deviates from the brief's illustrative string, and the deviation is the correct one
**Files:** `docs/capability-matrix.md:37,39`; worker report deviation D-3

The brief's parenthetical offers `disabled: no declared package` for grok/agy/kiro-cli. `grok`
uses that exact string. `agy` and `kiro-cli` instead read
`disabled: no declared npm package; cask mutation not shipped`, because both rows *do* declare a
cask candidate — the same table's `declared packages` cell reads `homebrewCask:antigravity-cli`
and `homebrewCask:kiro-cli`. Applying the brief's literal example would have made the matrix
contradict itself. The brief's operative rule is "`informational: <reason>` or `disabled: <reason>`
*naming the cause*", and the example is marked "e.g.", so the deviation satisfies the normative
requirement while preserving matrix truth. Worker deviation D-3 documents it. Accepted as correct.

### INFO-4 — Worker report overstates one line of its own evidence snapshot
**File:** `walkthroughs/M11-F-implementation.md:144` (F-AC07 row)

The report states git status records "the six allow-listed paths **plus this report**". The
captured `R/evidence/f/git-status-after.txt` shows the six paths only — the report file itself
was written after that snapshot (its SHA-256 was taken a minute later, at 20:29:44 versus 20:28:18)
and was committed by the orchestrator, which owns Git delivery. Purely an evidence-provenance
wording inaccuracy in the worker report; it does not affect the product diff or any gate.

### INFO-5 — The contribution proof depends on a non-empty `TMPDIR`; it fails closed rather than skipping
**File:** `Tests/AgentLensCoreTests/CapabilityMatrixTests.swift:372-389`

`contributionTempRoot` requires `AGENT_LENS_TEST_SCRATCH` or `TMPDIR` and **throws** when neither
is present. The gate commands unset both Agent Lens overrides, so the test relies on the ambient
`TMPDIR`; `ci.yml:545-546` documents that the hosted runner inherits its normal `TMPDIR`, so this
holds. A missing `TMPDIR` would fail the suite rather than silently skip it, which is the
correct direction. Noted only so a future CI change that clears `TMPDIR` is caught by intent
rather than by surprise.

---

## 3. Acceptance-matrix assessment

| ID | Scenario | Reviewer assessment |
|---|---|---|
| F-AC01 | Matrix agreement | **PASS** — 14 rows match the registry exactly; all cell rules hold; all required limits present; both seeded corruptions fail the agreement function (independently corroborated by `focused-02b`) |
| F-AC02 | Seeded-control extension | **PASS** — npm, homebrewFormula, and homebrewCask branches all seeded and each violation named by exact message |
| F-AC03 | Contribution proof | **PASS** — extra tool loads through the production validator and builder, detects from a scratch tree; production id list asserted unchanged in the same test; constructor proof intact |
| F-AC04 | Full gates | **PASS** — build, 547 suite (zero skips/failures), import guard, 21 guard fixtures, dev app, 9 packaging — all exit 0 |
| F-AC05 | Floors | **PASS** — 467 / 80 / 547 / 547 equal the independently recounted count; nothing lowered; anchors, guard 21, packaging 9 unchanged |
| F-AC06 | Guide | **PASS** — license-pending and no-invitation stated; every vocabulary and field claim verified against the validator source; gate commands correct |
| F-AC07 | Scope | **PASS** — seven allow-listed paths only; zero `Sources/**` change; protected manifest diff empty |

---

## 4. Conclusion

**M11-F is technically acceptable at candidate `d3f0324` on `milestone/m11-catalogue`.**

The matrix is truthful against the registry, the capability cells obey the M11-F rules, every
required carry-forward limit from the brief and from M11-D is present, the agreement test is
demonstrably non-vacuous (it caught a real document defect during this very phase), the parser is
deterministic, the data-only contribution proof runs through the production validator and builder
and asserts production is unchanged, the seeded collision control now covers all three manager
branches, the CI floors equal the independently recounted 467/80/547 with nothing lowered, the
contributor guide states the license-pending and no-invitation position with vocabularies that
match the validator exactly, and the diff stays inside the allow-list with no `Sources/**` change.

Matrix truth — the safety property this phase exists to establish — holds. The five informational
observations are recorded for future phases and require no change to accept.

Independent of the orchestrator's gate reruns, no merge, push, or release is claimed or implied by
this review.
