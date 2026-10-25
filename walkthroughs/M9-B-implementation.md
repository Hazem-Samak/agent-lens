# M9-B implementation — explicit read-only installation ownership

Status: worker implementation report and R2 candidate handoff. This is **not** independent
acceptance, not parent approval, and not a claim that M9 is complete. The parent owns acceptance and
the actual native UI observation.

Worker route: DeepSeek V4.1 Flash Free through OpenCode `opencode/deepseek-v4.1-flash-free#max`.
Observed CLI version: `opencode v2.1.3`. No other model, provider, CLI or subagent was used. No Git
staging, commit, branch switch, reset, clean, merge, push or publication was performed.

## User-visible behavior

`agent-lens verify-installation <registry-id>` performs one explicit read-only ownership check for a
single validated registry entry:

- It resolves the login-shell environment once, scans only the named definition and prints that
  entry's local/path/declared facts followed by `OWNERSHIP VERIFICATION`.
- A verified result identifies the manager, package, manager entry/target, npm prefix or Homebrew
  Cellar, npm package root or selected keg, selected PATH entry/canonical target and observation
  time.
- An unknown result carries a neutral typed reason instead of a fabricated package identity.
- Unknown is a diagnostic outcome and exits 0. Invalid syntax, an unknown registry ID and a
  registry-load failure exit 1 with stderr. No-argument behavior still prints usage and exits 0.
- Verification never invokes update checking, a cache, `brew update`, `brew outdated`, npm install,
  uninstall or any other modifying command.

The macOS app publishes `InventoryEntry.ownership` and offers a native `Verify Installation` action
only for winner/off-PATH selections. The detail view shows verified manager/package/root identities or
the neutral unknown reason, with `Verifying…`/`Cancelling…` states. A fresh scan, rescan or failed
rescan clears old proof; selecting another tool cancels and discards an in-flight verification.
Update outcomes applied to the same snapshot preserve its ownership value. Source remains a
heuristic label and declared packages remain declarations only.

## Implementation shape

- `Sources/AgentLensCore/Ownership/InstallationOwnership.swift` — public typed result, verified
  identity, selection identity, fingerprint and neutral reason enum.
- `Sources/AgentLensCore/Ownership/ExecutableIdentity.swift` — shared live executable/file/directory
  observation, canonical targets, stat fingerprints, component containment, descriptor-relative
  directory walking and strict single-path manager-output parsing.
- `Sources/AgentLensCore/Ownership/InstallationOwnershipVerifier.swift` — selection eligibility,
  adapter dispatch, cancellation checks and final selection revalidation.
- `Sources/AgentLensCore/Ownership/NpmOwnershipProbe.swift` — exactly `npm prefix --global` and
  `npm root --global`; exact canonical `<prefix>/lib/node_modules` layout by components; bounded
  descriptor-relative, nonblocking manifest reads; object/string `bin` handling; retained lexical
  prefix/root/package/prefix-bin bindings; `<prefix>/bin/<executable>` same-target proof.
- `Sources/AgentLensCore/Ownership/HomebrewOwnershipProbe.swift` — exactly `brew --cellar`,
  named `brew info --json=v2 --formula` and named `brew list --verbose --formula`; ownership-only
  record parsing; exact formula stem/full-name/installed-keg agreement and one-pass exact selected
  file-list proof, without `--installed`, semver, `versions.stable` or `revision` dependence.
- `Sources/AgentLensCore/Ownership/InstallationOwnershipRenderer.swift` — CLI section rendering,
  including the read-only notice.
- `Sources/agent-lens/main.swift` and `AgentLensCore.swift` — bounded subcommand dispatch and usage.
- `Sources/AgentLensAppSupport/*` — typed ownership on entries, service verification with the
  session environment/runner/clock/current directory off the main actor, and the verification
  pipeline/generation/stale-publication guards.
- `Sources/AgentLensApp/OwnershipVerificationView.swift` plus MainWindow/ToolDetailView/ToolListView —
  explicit native action, details, busy/cancel state and exhaustive phase handling.
- `DetectorMetadataRenderer` appends `(declaration only)` to declared package lines so a declared
  candidate is not presented as already verified.

## R1 review corrections

**R1-01 — bounded, nonblocking manifest open.** `package.json` is opened only through a
descriptor-relative `openat` with `O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC`, then validated with `fstat`
before any read. An `fstatat` guard rejects an already-visible non-regular final component before
the open; the descriptor check remains authoritative for a replacement race. FIFO, socket/device,
directory and symlink-to-nonregular layouts return `.manifestUnreadable` without waiting for a
writer. A real-CLI subprocess regression places a writerless FIFO at the manifest path and runs under
a 20-second watchdog, so a future blocking open fails the test instead of wedging the suite.

**R1-02 — ownership-specific Homebrew parsing.** The ownership adapter has its own bounded v2
`formulae` parser that reads only `name`, `full_name` and `installed[].version`. `versions.stable`
and `revision` are ignored; absent, null, non-string and non-semver values no longer affect
ownership. Full-name consistency still uses the shared validator. Malformed or contradictory
records keep their raw identity claims so a duplicate or borrowed name remains visible and cannot
lend proof to a neighbour. The protected M6 update parser and timeout/list command behavior are
unchanged.

**R1-03 — truthful identity-change reason.** Every adapter callsite now propagates the actual
`revalidate(selection:manager:)` reason instead of hard-coding `.selectedExecutableChanged`.
Replacing only the manager reports `.managerChanged`; replacing only the selected executable reports
`.selectedExecutableChanged`; proof files, roots, manifests and lexical bindings report
`.proofChanged`. Subsequent queries remain suppressed and no verified result is published. The
existing Homebrew manager-change regression and a new npm manager-change regression assert the
actual identity.

**R1-04 — avoidable work in B-introduced paths.** The npm manifest is validated and parsed from the
single bounded original `Data`; the tautological String re-encoding and duplicate full-manifest
copies are gone. The Homebrew list proof computes the selected path components once and validates
membership in one pass while still rejecting malformed output after a match. The app observation
time uses a cached value-style `Date.ISO8601FormatStyle` in UTC instead of constructing an
`ISO8601DateFormatter` per render.

**R1-05 — canonical npm root layout.** Directory-identity equality at a symlinked
`<prefix>/lib/node_modules` is no longer sufficient. The reported canonical root must be exactly the
canonical prefix followed by the `lib`, `node_modules` components. A redirected P1 node_modules
pointing at P2's package and executable now returns `.managerRootMismatch`; an ordinary prefix still
verifies.

**R1-06 — lexical bindings are part of the proof.** The npm proof retains the manager-reported
lexical prefix and root paths, the declared lexical package path and the lexical prefix-bin path, as
well as their canonical directory identities. Final revalidation observes both spellings, the
manifest under both spellings, and the prefix-bin executable. Retargeting only the declared package
link from one in-root store to another after package observation now reports `.proofChanged`;
ordinary packages, selected aliases and manager executable symlinks that target the same executable
still verify. A narrow internal `@TaskLocal` hook
(`NpmOwnershipProbeTestHooks.onBeforeAnchoredManifestOpen`) makes the retarget deterministic and is
dormant outside tests.

**R1-07 — anchored manifest read.** The manifest is opened relative to a directory descriptor
obtained by walking the observed canonical package path component by component with `O_NOFOLLOW`,
then verifying the final descriptor's device/inode against the captured `DirectoryIdentity`. A
static ancestor symlink is rejected by canonical containment before any read. A deterministic
ancestor replacement between observation and open makes the walk fail with `.packagePathUnsafe`
while an oversized outside decoy manifest is never consumed. Symlinked manifests are rejected as
unsupported (`.manifestUnreadable`); regular inside-package manifests remain the supported layout.

## R2 review corrections

**R2-01 — the bin containment check constrains the observation used as proof.** The npm adapter no
longer resolves the declared bin link once for containment and then observes it again for proof. It
observes `lexical` once, applies `isStrictDescendant(observed.canonicalTarget, of: packageRoot)` to
that exact observation, and only then compares its canonical target and fingerprint with the
selected executable. The redundant pre-resolution snapshot is gone, so a retarget between two
snapshots cannot leave the proof outside the package. Exact target/fingerprint equality, package
identity/root, prefix-bin proof and final revalidation are unchanged. A dormant internal
`@TaskLocal` seam, `NpmOwnershipProbeTestHooks.onBeforeBinObservation`, sits immediately before the
observation.

The consumer-visible regression
`npmBinRetargetToOutsidePrefixCannotBorrowManagerBinProof` constructs another test-owned prefix
whose executable is the selected target and the current manager prefix-bin target, while the
declared package bin link initially points inside its own package. It retargets the package link at
the seam. Against the R1 logic, the vulnerable build returned a verified cross-prefix installation
(RED: exit 1, two failed expectations). The corrected build returns neutral
`.executableOutsidePackage` with no verified installation (GREEN: exit 0). Ordinary-prefix,
in-root alias and prior static-escape regressions remain green.

**R2-02 — Homebrew parses the original bounded JSON bytes.** `infoFormulaObjects` still performs the
strict UTF-8, BOM and NUL transport checks, but now passes the original bounded `Data` to
`JSONSerialization`; the R1 re-encoding copy at that parser call is removed. The strict validator,
ownership-only v2 parser, envelope checks, formula identity and selected-keg/list proof are
unchanged.

## Supported layouts and limits

- npm manifests must be regular files inside the canonical package directory; symlinked manifests
  are deliberately unsupported.
- The canonical npm root must be exactly `<canonical prefix>/lib/node_modules` by components. A
  linked prefix or manager executable is allowed only when its canonical target remains the required
  same executable/inside the prefix; an escaping node_modules link is neutral.
- A declared package directory may itself be a link only when its canonical target is a strict
  descendant of the canonical npm root. The lexical package binding is revalidated. Unusual linked
  layouts that cannot satisfy that containment are conservatively unsupported.
- Homebrew ownership requires the selected canonical executable to be inside the exact current keg,
  the matching formula name/full name, the selected keg in `installed`, and the selected canonical
  executable in the current `brew list --verbose` output. The documented current-keg list limitation
  remains neutral, not verified.
- No Homebrew cask ownership, standalone ownership, uv/pip/Cargo support, cache/persistence,
  background work or M9-C version observation was implemented.
- No install/update/uninstall/relink/pin/sudo/manager-refresh path exists in this feature.

## Evidence

All R2 worker output is under
`/Users/corvette/.hermes/cache/scratch/agent-lens-m9-20261022-382vfoyi/worker-b-r2/`. Prior R1
evidence under `worker-b-r1/`, and earlier raw evidence under `R/worker-b` and `R/evidence`, remain
intact.

| Gate | Result | Raw evidence |
|---|---|---|
| Final full Swift gate, explicit TestingMacros fallback, fresh R2 root | exit 0; 244 Core + 71 AppSupport = **315 tests passed** with `--no-parallel` | `full-suite-noparallel.log`, `.stderr.log`, `.exit`, `.argv.txt` |
| R2-01 deterministic regression RED against R1 logic | exit 1; **2 failed expectations**; vulnerable build returned a verified cross-prefix installation | `red/stdout.log`, `.stderr.log`, `.exit`, `.argv.txt` |
| R2-01 deterministic regression GREEN against corrected logic | exit 0; neutral `.executableOutsidePackage`, no verified installation | `green/stdout.log`, `.stderr.log`, `.exit`, `.argv.txt` |
| Focused Core ownership regressions | exit 0; **30/30 passed** | `focused/ownership.stdout.log`, `.stderr.log`, `.exit` |
| Focused AppSupport ownership regressions | exit 0; **8/8 passed** | `focused/app.stdout.log`, `.stderr.log`, `.exit` |
| Focused `verify-installation` CLI tests | exit 0; **6/6 passed**, including the FIFO watchdog regression | `focused/cli.stdout.log`, `.stderr.log`, `.exit` |
| Fresh dev app builder, fresh R2 root | exit 0; `AgentLensApp-debug.app` produced | `app-build.log`, `.stderr.log`, `.exit`; `dev-app/AgentLensApp-debug.app` |
| Packaging suite | exit 0; **9/9 tests, OK** | `packaging.log`, `.stderr.log`, `.exit` |
| Fresh real npm Codex read-only verification | exit 0; verified `@openai/codex`, prefix `/Users/corvette/.local`, **0.41 s** wall | `real-manager/real-npm-codex.{stdout,stderr,exit,argv}` |
| Fresh real Homebrew `python@3.15` read-only verification | compile exit 0; run exit 0; verified, Cellar `/opt/homebrew/Cellar`, **1.45 s** wall | `real-manager/real-brew-compile.{stdout,stderr,exit,argv}`; `real-brew-python.{stdout,stderr,exit,argv}` |
| Accepted-A protected comparison | 72 protected baseline files checked, 0 mismatches; 11 modified + 10 added B candidate files | `baseline-comparison.json` |
| Final B candidate hashes | 21 files; new SHA-256 manifest | `candidate-sha256.json` |

The exact default `swift test` still hits the pre-existing local TestingMacros macro-discovery
failure; the documented explicit-plugin fallback above compiled and passed the entire R2 suite in a
fresh root. This is a toolchain/environment fact, not a test skip or a product-source change.
Two earlier full-suite attempts without `--no-parallel` each failed only
`productionProcessOutcomesReachTheCoordinatorWithinTheirRealBounds` at
`UpdateProbeCoordinatorTests.swift:1769` on its `timeoutElapsed < 9` bound under parallel load; every
ownership and other test passed. Both attempts are preserved as
`full-suite-attempt1.*` and `full-suite-rerun.*`. An intermediate `--num-workers 1` attempt was
rejected by SwiftPM before any test because that option is XCTest-only; its raw logs are preserved
as `full-suite-serial.*`. The final complete run with `--no-parallel` passed all 315 tests and
skipped none.

R2 repeated both read-only real-manager observations: the R2-built CLI verified the existing
`@openai/codex` installation (prefix `/Users/corvette/.local`, 0.41 s), and the ephemeral Homebrew
harness, rebuilt against the R2 Core object, verified the existing `python@3.15` formula (Cellar
`/opt/homebrew/Cellar`, 1.45 s). The harness is not part of the product or its permanent tests, and
neither observation changed installed state.

## Acceptance-criteria map

- **AC01** — `npmObjectBinAndExternalSameTargetAliasProveTheDeclaredPackage`,
  `npmStringBinShorthandUsesThePackageBasename`; ordinary-prefix positive CLI test. Declaration-only
  proof is rejected by `npmDeclarationAloneDoesNotProveOwnershipWhenTheManagerBinIsMissing`.
- **AC02** — decoy prefix/root, exact-layout escape, wrong manifest name/bin, traversal/symlink
  escape, symlinked/non-regular/oversized/malformed manifests, missing declared package, duplicate
  declarations, and the R2 exact-observed-bin retarget regression in
  `InstallationOwnershipTests`; the retarget is neutral, not a verified cross-prefix claim.
- **AC03** — formula Cellar/info/list positive proof plus malformed/duplicate/full-name/other-keg/
  unlisted/other-Cellar/cask cases; ownership does not require stable or revision; the fixture
  `stable` 9.9.9 is never borrowed for the 1.0.0 keg. R2-02 validates transport encoding while
  parsing the original bounded JSON bytes.
- **AC04** — runner-gated selection/manager retarget tests with actual reasons, cancellation before
  and during a query, next-query suppression and awaited cleanup; AppSupport main-actor/cancellation
  tests.
- **AC05** — existing scan/offline/update/rescan tests still pass; six CLI ownership tests cover
  valid npm, valid formula, FIFO manifest, standalone-neutral, cask-neutral and
  missing/invalid/unknown-ID forms and zero manager effects for invalid forms.
- **AC06** — AppSupport tests cover launch/verify, standalone-neutral, selection switch, fresh/failed
  rescan clearing, cancel, coalescing, off-main heartbeat and stale-publication rejection. Actual
  native UI observation remains for the parent.
- **AC07** — fresh R2 real npm Codex and real Homebrew `python@3.15` read-only observations both
  verified; prior R1/B evidence remains under `R/worker-b-r1/real-manager/` and
  `R/worker-b/real-manager/`. The parent owns any final independent live rerun.
- **AC08** — R2 fallback suite, fresh app and packaging pass; accepted-A protected comparison and
  candidate hashes are in `R/worker-b-r2/baseline-comparison.json` and
  `R/worker-b-r2/candidate-sha256.json`.

## Limits and unobserved items

- The actual native app UI was not observed by this worker; the parent must perform that observation.
- The parent must independently rerun the exact gates and reject this candidate if any result
  differs. No parent approval, whole-M9 completion, Update/Uninstall availability or Git delivery is
  claimed. R1 is not accepted; R2 is a new worker candidate only.
- The final full suite required `--no-parallel` because the pre-existing real-process timing test is
  sensitive to parallel load on this host. Both failed parallel attempts and the clean serial final
  pass are preserved; no test was skipped. This is an execution-environment limitation, not a
  product behavior change.
