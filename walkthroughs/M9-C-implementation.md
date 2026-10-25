# M9-C implementation — identity-bound versions per canonical installation

Status: R2 worker implementation candidate. This is **not** parent acceptance, not whole-M9
completion and not a claim that the native UI was observed by this worker. The parent owns
independent verification, the actual native surface and Git delivery. The R1 candidate
`7a281605bff4806d98077afbf43ca858ca46073b094aae128d666110bf1cdc1d` was not accepted; its frozen
snapshot and evidence remain preserved. This document describes the R2 replacement candidate, which
retains the R1 behavior and narrows the PATH-origin recovery and CLI provenance wording.

Worker route: DeepSeek V4.1 Flash Free through OpenCode
`opencode/deepseek-v4.1-flash-free#max`. Observed CLI version: `opencode v2.1.4`. No other model,
provider, CLI or subagent was used. No Git staging, commit, branch switch, reset, clean, merge, push
or publication was performed, and no installed tool, package, cache or preference was changed.

## User-visible behavior

`agent-lens scan` prints a `canonical installation versions:` section inside each tool's PATH
report. Every observed canonical executable target has one row pairing:

- the canonical target,
- the representative entry that was observed and queried,
- the local version measured for that exact executable, or a neutral typed unknown reason.

The native Diagnostics view presents the same facts under **Canonical Installation Versions**, with
one row per canonical target. The selected tool summary still shows the selected installation's
version; it is derived from the selected observation, not a second query. Aliases and repeated PATH
slots share one row and one query. A shadowed target keeps its own measured value.

A selected declared extra-root executable remains the only extra root measured. Its observation
retains the actual discovery origin (`.extraRoot(index:directoryText:)`) independently of whether
the final selection remains valid. When the selected executable changes during collection, the
version row still shows its original canonical target, entry, declared root and neutral
`identityChanged` reason, but the selection becomes a consistency failure. CLI rows describe this
as an **observed discovery origin**, not a current shell winner or verified ownership.

An ordinary failed/no-token query leaves the PATH winner valid and reports a neutral unknown. If
the selected executable's target, identity or fingerprint changes during collection — including
after the per-target publication loop and immediately before the final selected-entry recheck —
the selected summary version becomes nil, the selection becomes a consistency failure, and the
still-measured selected observation is downgraded to `unknown(identityChanged)`. Unrelated shadowed
measurements are retained. No stale value or new winner is published.

## Implementation shape

- `Sources/AgentLensCore/Diagnostics/InstallationVersionObservation.swift` — public
  `InstallationVersionObservation` now requires `origin: PathCandidateOrigin` as the durable
  discovery fact; `InstallationVersionOutcome` and `InstallationVersionUnknownReason` are unchanged.
- `Sources/AgentLensCore/Diagnostics/InstallationVersionCollector.swift` — sequential
  identity-bound collection, before/after observations, per-target final revalidation, terminal
  selected-entry recheck and the fixed aggregate budget. A detected selected-identity failure
  invalidates a still-measured selected observation after the terminal check. A narrow dormant
  internal `@TaskLocal` checkpoint exists immediately before that terminal recheck for the
  deterministic consumer-visible regression.
- `Sources/AgentLensCore/Diagnostics/PathDiagnostics.swift` — required
  `ToolPathDiagnostic.installationVersions`, selected-first probe ordering, selected off-PATH
  inclusion, actual discovery origins for each probe target, selected identity propagation and
  derivation of `DetectedTool.version` only from the final valid selection. A PATH group's
  representative origin is built in O(1) from the group's `firstSlotIndex` into the same immutable
  original `environment.pathEntries` array; it does not rescan live candidates or the filesystem.
- `Sources/AgentLensCore/Detection/ToolDetector.swift` — internal `ToolLocation` /
  `locate` / `detectedTool(from:version:)` seam. Public `detect` still performs exactly its ordinary
  one local query.
- `Sources/AgentLensCore/Process/ExecutableIdentity.swift` — moved from
  `Sources/AgentLensCore/Ownership/ExecutableIdentity.swift` (no shim or re-export). Only the header
  changed; the observation, descriptor-read, containment and fingerprint behavior is unchanged.
- `Sources/AgentLensCore/Diagnostics/DiagnosticsScanRenderer.swift` — deterministic CLI section;
  declared-root provenance is rendered from the observation, never from the final selection.
- `Sources/AgentLensApp/DiagnosticsView.swift` — native section with one row per canonical target,
  target, representative entry, measured version or neutral reason, and a badge plus declared-root
  row driven by the observation's origin. The section iterates `installationVersions` directly with
  `id: \.canonicalTarget`; no temporary enumerated array is built per render.

No registry, query-specification, bounded-runner, ownership, update-coordinator, inventory or app
pipeline contract changed. No persistence, cache, Codable version scheme or mutable global clock was
added. The origin field is not a JSON/Codable schema change and has no default fabricated PATH
origin.

## Identity, origin and collection invariants

1. Live PATH targets are enumerated once in first-seen order; the selected target is probed first.
   Repeated slots and same-target aliases do not launch another query. When the existing selection
   is off PATH, only that selected declared extra root is included.
2. Each probe target carries the actual discovery origin observed by the PATH scan or declared-root
   search. A PATH group's representative origin is the raw slot and text recorded when that group
   was first seen, read directly as `environment.pathEntries[group.firstSlotIndex]` from the same
   immutable PATH array the groups were built from. It is not found by rescanning live candidates,
   re-reading the filesystem, or inferring a canonical-parent directory; empty and relative PATH
   text is preserved exactly. Origins are not guessed or copied from aliases.
3. Before a query, the representative entry is observed and its canonical target must equal the
   group's target. The selected entry is also compared with an earlier selected baseline.
4. The declared `VersionQuerySpecification` and the detector's injectable production query function
   run against that same entry and captured environment.
5. The entry is observed again after the query. Any changed, vanished or replaced identity discards
   a plausible printed version and produces `unknown(identityChanged)`.
6. Every measured identity is observed once more before publication. The selected entry is
   rechecked even when its own query failed or was never launched. If that terminal check detects a
   change, the selection becomes inconsistent and its matching still-measured observation is
   downgraded; an existing meaningful unknown reason and unrelated shadowed observations are kept.
7. `DetectedTool.version` is taken from the selected observation only after the final selection is
   known to be valid. `PathSelection.inconsistent` never contributes a summary version, even when an
   earlier candidate was captured before collection.
8. Declared-root provenance survives every later invalidation because it is part of the observation,
   not derived from the current selection. That provenance is an observed discovery origin, not
   ownership, authorization or a claim that the shell would select it now.

## Budget and concurrency

Collection is sequential: at most one version process is alive at a time, with no retries,
parallelism, scheduler or background refresh. Each query keeps the existing literal arguments,
selected stream/line, output cap and at most the existing 3-second timeout. Each tool scan also has
a fixed 10-second monotonic aggregate budget: a query starts only while budget remains and its
timeout is `min(3 s, remaining budget)`. Later, unqueried canonical targets remain explicit
`unknown(budgetExhausted)` observations with their representative entry; they are not dropped.
Existing process termination and pipe-drain grace can extend wall-clock duration beyond 10 seconds.

Production inventory scanning still uses the unchanged AppSupport utility queue. The aggregate bound
keeps a scan of many slow PATH copies from making that queue wait unbounded.

## Presentation

CLI rows use collection order and the shape
`<canonical target> -> version <v> (entry: <representative>)`, or
`... -> unknown — <neutral reason>`. A row whose observation origin is an extra root appends
`observed discovery origin: off PATH, declared extra root "<configured root>"; not a current shell
winner or verified ownership`. This note is present after invalidation too, because it describes
where the executable was observed, not the final selection. The successful `known extra root (off
PATH; not a shell winner)` selection line is rendered only for a currently valid off-PATH selection;
it is never resurrected for an invalidated executable. Existing winner, same-target alias, shadowed
and invalid PATH evidence remains unchanged.

Native rows use the same facts. An extra-root observation shows an **Observed discovery origin ·
off PATH** badge and an **Observed Discovery Origin** row naming the configured declared root and
stating that it is not a current shell winner or verified ownership. Long target and entry text
wraps in the existing wrapping style; the section is not horizontally scrollable and adds no filter,
icon or action. Copy/Reveal eligibility, ownership verification, update status and all three registry
entries are unchanged.

## Evidence

All R2 worker output and raw captures are under
`/Users/corvette/.hermes/cache/scratch/agent-lens-m9-20261022-382vfoyi/worker-c-r2/`. R1 and earlier
evidence remain untouched under `worker-c-r1/` and `worker-c/`.

| Gate | Result | Raw evidence |
|---|---|---|
| Focused diagnostics/version tests | exit 0; **26/26 passed** (0.710 s test run; 30.9 s fresh build+run) | `evidence/focused-diagnostics-version/` |
| Affected Core scanner/detector/CLI/coordinator suites | exit 0; **100/100 passed** (24.7 s) | `evidence/affected-core/` |
| Full serial Swift gate, fresh root, explicit TestingMacros fallback | exit 0; **258 Core + 71 AppSupport = 329 tests**, `--no-parallel`, no skips; **85.7 s** | `evidence/full-suite/` |
| Fresh dev app builder | exit 0; `AgentLensApp-debug.app` produced; 25.8 s | `evidence/dev-app/` |
| Packaging suite | exit 0; **9/9 tests, OK**; 1.8 s | `evidence/packaging/` |
| Compiled Core scanner smoke, real executables | exit 0; 5 scenarios / 5 PASS lines: two versions, alias+repeated slot, off-PATH ownership boundary, failed query, real retarget, empty/relative raw PATH origins | `evidence/smoke-{compile,run}/`; source `smoke/scanner-smoke.swift` |
| Compiled R2 production probes | exit 0; terminal 1500-target publication probe and changed off-root origin probe; off-root CLI row carries the explicit ownership boundary | `evidence/r2-probes-{compile,run}/`; source `smoke/r2-probes.swift` |
| Actual built CLI, live environment | exit 0; Codex 0.164.0, OpenCode **2.1.4**, Grok 1.0.70; one canonical row each | `evidence/cli-live/` |
| Actual built CLI, closed two-version fixture under cache-denial sandbox | exit 0; Codex **0.100.0** + **0.200.0**; alias/repeated deduped; query log exactly `winner, shadow, opencode, grok` | `evidence/cli-fixture/` |
| Compiled app/CLI string check | exit 0; observed-discovery-origin and ownership-boundary strings present in both binaries | `evidence/compiled-strings.txt` |

The full suite used a fresh scratch root and the known invocation-local TestingMacros plugin
fallback (`-load-plugin-library .../libTestingMacros.dylib`); no test was skipped and no
package/toolchain setting changed. The repository `.build` directory was preserved; all builds used
`R/worker-c-r2` scratch roots. The focused and affected gates retain the typed-origin,
repeated-slot/alias, relative/empty PATH, changed-off-root, terminal-invalidation and aggregate-budget
coverage; R2 added no permanent implementation or wording test.

The compiled smoke linked the built Core object and used real test-owned executables. It also verifies
that a group first seen through an empty PATH slot reports `.path(slotIndex: 0, directoryText: "")`
and one first seen through a relative slot reports
`.path(slotIndex: 0, directoryText: "relative-bin")`, with empty and relative text preserved exactly.
The closed CLI fixture ran under `sandbox-exec` with a kernel-level denial of the real AgentLens cache
and a synthetic `HOME`/`ZDOTDIR`; fake Codex, OpenCode and Grok entries kept real extra roots out. The
live run only read local version output and manager-free local diagnostics.

The R2 production probes linked the same built Core object. The terminal probe created 1500 real
canonical targets, retargeted the selected entry from a concurrent thread after the last query and
observed: 1500 queries, inconsistent selection, selected version nil, selected observation
`unknown(identityChanged)`, and an unaffected later observation still `measured("2.3.4")`. The
off-root probe retargeted a selected declared extra root during its query and observed: selection
inconsistent, version nil, one observation carrying `.extraRoot(index: 0, directoryText:)` for its
original target, no query to the unselected root, and a rendered version row containing the observed
declared-root origin plus `not a current shell winner or verified ownership`. Raw output is in
`evidence/r2-probes-run/stdout.txt`.

The R1 SourceKit-LSP reference cross-check was not rerun: R2 changed no public type, initializer or
selector. The R1 result (9 references to the exported observation type) remains under
`worker-c-r1/evidence/references-observation-type-final/`; the full R2 build and tests cover every
constructor and use site.

## Acceptance-criteria map

- **AC01** — `installationVersionsKeepDistinctValuesForTwoRealCanonicalTargets`; closed CLI fixture
  and compiled smoke retain 0.100.0/0.200.0 and 1.2.3/4.5.6 respectively; selected summaries match
  the selected observation.
- **AC02** — `installationVersionsQueryEachCanonicalTargetOnceDespiteAliasesAndRepeatedSlots`;
  fixture query log has exactly one winner, one shadow, one OpenCode and one Grok query; counts and
  labels are unchanged. Origin assertions cover the representative PATH slots; the R2 compiled smoke
  additionally confirms raw empty/relative PATH text preservation.
- **AC03** — `selectedExtraRootGetsOnlyItsOwnOffPathVersion` and the off-root R2 probes: only the
  selected declared root is measured, its exact `.extraRoot` origin is retained, and it is described
  as an observed discovery origin that is not a current shell winner or verified ownership.
- **AC04** — `unchangedFailedQueryKeepsTheWinnerAndPublishesNeutralUnknown`,
  `selectedRetargetDuringQueryCannotKeepAPlausiblePrintedVersion`,
  `samePathReplacementDuringQueryLosesThePrintedVersion`,
  `earlySelectedChangeWhileALaterQueryRunsClearsTheSelectedVersion`,
  `earlyShadowedChangeWhileALaterQueryRunsLeavesTheWinnerIntact`,
  `missingAndUnexecutableShadowedCandidatesStayUnknownWithoutBorrowing`,
  `terminalSelectedRetargetAfterPublicationInvalidatesTheSelectedObservation`,
  `offRootSelectedRetargetDuringQueryRetainsItsExactDiscoveryOrigin`,
  `vanishedOffRootSelectionRetainsItsExactDiscoveryOrigin`, plus the existing
  changed-target/off-PATH diagnostics regressions and the terminal production probe.
- **AC05** — `aggregateVersionProbeBudgetStopsAfterThreeSecondsRemainderAndKeepsEveryTarget`
  observes three sequential calls with timeouts `[3, 3, 2]`, maximum concurrency 1 and an explicit
  fourth `unknown(budgetExhausted)` observation.
- **AC06** — `directDetectStillRunsExactlyOneLocalVersionQuery`; the full serial suite includes the
  unchanged CLI scan/update/invalid forms and the B ownership lifecycle. No new manager, cache or
  query side effect was introduced.
- **AC07** — full Swift, app builder and 9 packaging checks pass; live, closed-fixture and compiled
  scanner evidence is listed above. Actual native window observation remains for the parent.

## Limits and unobserved items

- These are bounded before/after filesystem observations, not an atomic filesystem freeze or an
  FD-bound exec guarantee. A change after the terminal selected recheck can still occur later;
  versions are scan facts and never ownership or authorization for a future mutation. The terminal
  check detects and invalidates a change before publication; it does not claim atomicity.
- The existing query seam returns `String?`, so `.queryFailed` truthfully covers nonzero exit,
  timeout, output-cap, invalid output and no-token outcomes without inventing a finer distinction.
- The aggregate budget bounds query launches, not total wall time; process termination and pipe-drain
  grace can extend a scan.
- The observed discovery origin records where an executable was found. It does not prove package
  ownership, shell winner status after invalidation, or permission to modify anything.
- This worker did not launch or visually inspect the native app. Native canonical rows, origin
  badge/root row, wrapping at a 760-point window, Copy/Reveal behavior and selection freshness remain
  unobserved here; the parent owns that verification.
- No parent acceptance, whole-M9 completion, update/uninstall capability or Git delivery is claimed.
