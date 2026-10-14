# M6 — Version / update probing

> **Current status: independently accepted by the parent on 2026-10-14 (EEST); Git publication and branch closeout are parent-owned.** Two distinct fresh full-suite gates passed 180/180 with exit 0; see `walkthroughs/M6-version-update-probing.md`.
> The implementation contract and historical plan below remain frozen. Explicitly approved narrow exceptions were the additional production async bridge `ProcessUpdateCommandRunner.swift` and fixture-root-only helper changes in four existing M2–M5 test files; no product assertions changed. Details and evidence are in the walkthrough.
> Prepared on 2026-10-13 against commit `460000b` (accepted M5). The original implementation handoff text is historical; M6 is no longer plan-only, and M7 has not started.

## Goal and completion boundary

Extend the existing CLI inventory with a trustworthy, tri-state update result
for each detected tool: `upToDate`, `updateAvailable`, or `unknown`. Preserve
the locally detected version and every M5 PATH diagnostic even when update
checking is disabled, unsupported, offline, timed out, or unsuccessful.

The first supported adapter is **Homebrew formulae**. M6 delivers the shared
status/comparison/probe/cache layer, a batched Homebrew adapter, CLI integration,
and deterministic acceptance evidence. It ends when those checks pass and the
orchestrator independently accepts the result. M7 does not begin automatically.

This is a diagnostic milestone. Checking for updates does not install, upgrade,
uninstall, relink, pin, unpin, or delete any tool.

## Authority and verified starting point

The governing requirements are `AGENT_LENS_SCOPE.md` §21, §27.1/3/5, §28.2–3,
and §29.4–5/10–12, plus `DECISIONS.md` D-002, D-004–007, D-010–014, D-016–018.
This brief makes their M6 implementation choices explicit:

| Requirement | M6 decision |
|---|---|
| Local installed version | Reuse `DetectedTool.version`; never replace it with manager or network output. |
| Tri-state update result | Add typed, `Sendable`, equatable values alongside the existing detection result. |
| Optional asynchronous probing | Explicit CLI opt-in; publish local inventory before awaiting the probe. |
| Batch queries | One Homebrew batch workflow per scan, independent of the number of tools. |
| Six-hour TTL and manual refresh | Persist only validated successful metadata in an app-owned cache; refresh bypasses it. |
| Offline degradation | An explicit offline mode launches no update probe and returns neutral unknown results. |
| Real version ordering | Semantic version precedence and Homebrew package revisions; unsupported schemes stay unknown. |
| Update count | Count only `updateAvailable` for installed, selected tools. |
| Homebrew first | Formulae only; npm, uv/pip, Cargo, and cask adapters are later work. |

The current source tree was inspected while drafting this brief:

- `Sources/agent-lens/main.swift` accepts exactly `scan` or `debug-env` and
  renders M5 reports through `DiagnosticsScanRenderer`.
- `ToolDetector.detect(in:)` supplies install state, selected entry/target,
  heuristic source (`npm`, `brew`, or `standalone`), and a local optional version.
  Its version query already uses a three-second bounded process.
- `PathDiagnosticsScanner.scan(...)` calls the detector once and returns a
  `ToolPathDiagnostic`. Its selection is a verified winner, an off-PATH
  selection, a missing tool, or a consistency failure.
- `DetectorRegistry.loadDefault()` returns ordered definitions with `id`,
  executable name, extra roots, and fixtures. There is no manager package-name
  field. Fixture `expectedSource` describes a test; it is not runtime ownership.
- `DefaultDetectors.json` contains Codex, OpenCode, and Grok. None is guaranteed
  to be Homebrew-managed on the next machine.
- `BoundedProcessRunner` is internal to `AgentLensCore`, synchronous, limited
  to 1 MiB stdout, and returns spawn failure or exit/timeout/output-limit data.
  It discards stderr. It does not expose a network-error classifier.
- `Package.swift` uses Swift tools version 6.0, macOS 14+, and no external
  dependencies. The core has no SwiftUI/AppKit imports.
- M5's recorded acceptance is 46 tests. This is historical evidence; measure
  the actual baseline before implementation rather than asserting a fixed total.

There is no existing `Version`, `VersionStatus`, update adapter, update cache,
or asynchronous scan coordinator to call. Add the necessary seams in M6.

## Frozen scope

In scope:

- Typed update statuses and reasons, selected-install identity, and provenance.
- Pure semantic-version parsing/comparison, including prereleases and build
  metadata; a narrow Homebrew package-revision comparison policy.
- Resolution of the first live `brew` executable from `ShellEnvironment`.
- Verification that a selected Cellar executable belongs to the resolved
  manager's Cellar and to the formula/keg named by its metadata.
- Batched formula metadata and outdated queries using the existing bounded
  runner, with a nonblocking async bridge and injected test dependencies.
- A versioned six-hour metadata cache, explicit refresh, and offline controls.
- An appended update-status report, deterministic output, and focused tests.
- README usage and an M6 walkthrough with raw evidence during implementation.

Out of scope:

- M7 UI, app packaging, release automation, background scheduling, notifications,
  automatic operations, generic filesystem cleanup, or installation history.
- npm/PyPI/crates.io/standalone release adapters; Homebrew casks, HEAD builds,
  renamed-formula migrations, and discovery across multiple Homebrew managers.
- New default detectors, registry/schema changes, broad scanner refactors,
  a general package-ownership engine, or an arbitrary-command interface.
- Running `brew update`, changing taps, refreshing package installations, or
  interpreting caches/configuration as tool-installation clutter.
- Replacing the accepted local `--version` parser or executing shadowed copies.
- A new networking framework, external semantic-version library, dependency,
  or process runner.

The lack of a brew installation among the three default tools is acceptable.
Homebrew success paths must be proved with synthetic fixtures; a live scan with
only npm/standalone tools must honestly report unknown and perform zero brew
queries. Do not install a tool merely to make this milestone look successful.

## File boundaries

Add these production files under `Sources/AgentLensCore/Updates/`:

| File | Responsibility |
|---|---|
| `VersionStatus.swift` | Status/reason/result/provenance models and selected-install identity. |
| `VersionComparison.swift` | Pure semantic-version and Homebrew revision comparison. |
| `HomebrewIdentity.swift` | Manager resolution and safe selected Cellar/formula/keg matching. |
| `HomebrewUpdateProbe.swift` | Typed JSON parsing and bounded batch adapter. |
| `UpdateMetadataCache.swift` | Versioned, limited, atomic cache storage and TTL policy. |
| `UpdateProbeCoordinator.swift` | Eligibility, mode, async work, cache and result association. |
| `UpdateScanRenderer.swift` | Pure appended status section and update count. |

Add tests named `VersionComparisonTests.swift`, `VersionStatusTests.swift`,
`HomebrewUpdateProbeTests.swift`, `UpdateMetadataCacheTests.swift`,
`UpdateProbeCoordinatorTests.swift`, and `UpdateCLIIntegrationTests.swift`
under `Tests/AgentLensCoreTests/`. Keep small JSON fixtures inline or generate
them in scratch space, so no new package-resource declaration is needed.

Permitted existing-file changes are limited to:

- `Sources/agent-lens/main.swift`: validated flag dispatch and orchestration.
- `Sources/AgentLensCore/AgentLensCore.swift`: the usage string only.
- `Tests/AgentLensCoreTests/AgentLensCoreTests.swift`: the existing usage assertion
  only, if necessary to reflect the added flags.
- `README.md`: concise M6 usage and latest-known-metadata limitations.
- New `walkthroughs/M6-version-update-probing.md`: raw evidence and results.
- `DECISIONS.md`: orchestrator-owned M6 decisions/log entry after acceptance.

**DO NOT TOUCH:** every other file, including the detector, registry/schema,
default JSON, environment resolver, bounded runner, both existing renderers,
M5 diagnostics, `Package.swift`, scope document, and other briefs/walkthroughs.
This plan remains read-only during implementation. If a boundary makes the
agreed behavior impossible, stop that dependent change and report the exact
needed exception to the orchestrator. Do not quietly widen the milestone.

## User-visible command contract

Accept exactly the following forms:

| Command | Behavior |
|---|---|
| `agent-lens scan` | Local inventory and PATH diagnostics; no update-cache reads or manager queries; append unknown statuses. |
| `agent-lens scan --check-updates` | Local inventory first; use a valid cache or perform the eligible Homebrew batch probe. |
| `agent-lens scan --refresh-updates` | Local inventory first; bypass cache reads and perform the eligible probe, replacing cache on success. |
| `agent-lens scan --offline` | Local inventory first; no update-cache reads or manager queries; supported installed tools are unknown due to offline mode. |
| `agent-lens debug-env` | Preserve existing behavior. |

The three scan flags are mutually exclusive. Reject repeated flags, combined
flags, extra operands, unknown flags, and flags on `debug-env`; print usage to
stderr and exit 1. Preserve the clean no-argument usage exit 0 and the existing
unknown-command exit 1. No new subcommand is required.

Keep stdout deterministic: print the existing M5 report once, flush it, then
append one `VERSION / UPDATE STATUS` section in registry order. Do not print
an initial status section and a second replacement, ANSI cursor updates,
unbounded subprocess output, or interleaved task logs.

The appended section identifies each tool, its local installed version or `—`,
latest known version or `—`, status, neutral explanation for unknown, and
cache/probe provenance when available. Use `unknown`, never an error marker or
an up-to-date checkmark, for unknown statuses. Display a single update counter.
Missing tools remain normal missing tools and do not contribute to that count.

Examples below are synthetic, not assertions about this Mac:

```text
VERSION / UPDATE STATUS
Example A  installed 1.9.0  latest known 1.10.0  update available
           source: Homebrew metadata; checked at <UTC timestamp>
Example B  installed 2.0.0  latest known —       unknown — no registry
Example C  installed —      latest known —       unknown — not installed
1 update available
```

A probe failure is a result value: scan still exits 0 after a useful inventory.
Invalid CLI syntax and a broken detector registry retain their nonzero exits.
An update-cache read/write failure is neutral, never a fatal inventory failure.

## Model and comparison contract

Add public models with explicit initializers where the CLI needs to construct
them. All values crossing tasks are `Sendable`; pure models are also equatable.
Suggested signatures are an interface sketch, not code that already exists:

```swift
enum VersionStatus {
    case upToDate(installed: Version, latest: Version)
    case updateAvailable(installed: Version, latest: Version)
    case unknown(installed: Version?, reason: UnknownReason)
}
```

The optional installed value deliberately extends §21's sketch: the existing
detector can return nil and must keep doing so. `Version` retains the original
version text; strict parsing/comparison is separate. Retaining a raw version
must not turn an unsupported scheme into a comparable version.

`UnknownReason` includes §21's `noRegistry`, `networkUnavailable`, `probeFailed`,
and `rateLimited`, plus `notChecked`, `notInstalled`, `unsupportedSource`,
`installedVersionUnavailable`, `unsupportedVersion`, `managerUnavailable`,
`managerMismatch`, `identityUnverified`, and `diagnosticInconsistent`.
Keep the reason typed, with any technical detail separate and bounded.

Result association uses a registry ID and selected canonical target, not a
display name or array zip after filtering. A result also carries the manager's
package identity where verified, local version text, optional latest metadata,
observation time, and whether it came from a fresh probe or cache. It references
the existing `ToolPathDiagnostic`; it does not mutate its detection or selection.

Apply eligibility in this order so reasons are stable:

1. Missing tool → `notInstalled`.
2. M5 selection consistency failure → `diagnosticInconsistent`.
3. Standalone source → `noRegistry`; npm/other unsupported managers →
   `unsupportedSource`. Neither is eligible for a Homebrew launch.
4. Brew source with no local version → `installedVersionUnavailable`.
5. Eligible brew tool in plain scan → `notChecked`; in explicit offline mode →
   `networkUnavailable` with explanation that offline mode was requested.
6. Probe modes → verify manager/identity, then obtain and compare metadata.

An off-PATH selected executable is eligible if identity is verified; retain the
off-PATH label. A same-target alias receives no separate result. Shadowed targets
remain in PATH diagnostics and receive no local version or update probe.

Comparison must return older/equal/newer/**incomparable**, not a boolean:

- Follow the [Semantic Versioning 2.0.0 specification](https://semver.org/)
  for the strict parser, including rejection of leading zeroes in numeric core
  and numeric prerelease identifiers, empty identifiers, and trailing junk.
- Strict SemVer major/minor/patch integers compare numerically; avoid fixed-width
  integer overflow by validating magnitude or comparing normalized digit strings.
- A release outranks its prereleases; numeric prerelease identifiers compare
  numerically, numeric identifiers precede nonnumeric ones, text compares in
  SemVer order, and a shorter otherwise equal prerelease sequence comes first.
- Build metadata does not affect precedence. Preserve it in displayed raw text.
- For Homebrew stable versions, support two-component numeric versions by adding
  a zero patch for comparison, and use the manager's revision as a separate
  nonnegative package component (`1.2.3_1` is later than `1.2.3`).
- Verify that the selected keg's upstream version agrees with the detected CLI
  version. Compare that keg's package revision with formula metadata; do not
  invent revision data from the CLI banner.
- Date formats outside the supported grammar, `1.x`, `HEAD`, formula renames,
  epochs, malformed text,
  and other unsupported formats return `unsupportedVersion`. Preserve their
  local text and avoid lexical ordering or a fabricated latest value.
- Equal verified selected-package/latest versions → `upToDate`. Older →
  `updateAvailable`. A selected package newer than known metadata → unknown,
  with a bounded explanation; do not imply downgrade availability.

## Homebrew batch contract

Homebrew documents JSON queries, including v2 metadata and outdated output.
Its outdated implementation reports formula names, outdated installed versions,
and a current package version. These are inputs, not proof of the selected
executable's identity. See the [Homebrew manual](https://docs.brew.sh/Manpage),
[JSON query documentation](https://docs.brew.sh/Querying-Brew), and
[outdated implementation](https://github.com/Homebrew/brew/blob/main/Library/Homebrew/cmd/outdated.rb).

Resolve `brew` from the ordered `ShellEnvironment.pathEntries` with the accepted
live-file, empty-root, relative-root, and symlink semantics. Normalize against
the same working directory as discovery. Never use inherited PATH, `which`,
`/usr/bin/env brew`, or a hardcoded `/opt/homebrew/bin/brew` fallback. Retain the
absolute entry path and canonical manager target as cache identity.

Use an argument array and explicit `ShellEnvironment.raw` for every process.
For these diagnostic subprocesses only, add `HOMEBREW_NO_AUTO_UPDATE=1` and
`HOMEBREW_NO_ANALYTICS=1`, without modifying the original environment value.
M6 does not invoke `brew update`. Latest values are therefore **latest known to
Homebrew metadata**, not a guarantee of the newest worldwide release. Show the
observation time; do not pretend it is the time upstream metadata was refreshed.

For an uncached eligible batch, execute at most these three queries:

```text
<resolved brew> --cellar
<resolved brew> info --json=v2 --formula <deduplicated formula names...>
<resolved brew> outdated --json=v2 --formula
```

The outdated query has no package operands. Query metadata only for selected
eligible formulas, rather than all installed packages: this limits stdout and
does not tie work to unrelated package count. Argument count grows with tools;
process count stays at most three. Reject invalid package tokens before process
construction; formula IDs are parsed data, not shell text. A zero-eligible batch
executes zero queries. A fresh cache hit also executes zero queries.

Verify identity before assigning a status:

1. Parse selected canonical targets by path components as
   `<cellar>/<formula>/<keg-version>/<relative executable path>`. A substring
   containing `/Cellar/` alone is insufficient.
2. The absolute Cellar returned by the resolved manager must match that selected
   path's Cellar. Another manager's target returns `managerMismatch`.
3. Match the formula stem and selected keg version against the returned formula
   record and its installed versions. Record the formula's full name/tap when
   supplied. A fixture source label or executable name is never that match.
4. Confirm local CLI-version agreement with the selected keg upstream version.
   Missing, duplicate, ambiguous, renamed, or contradictory records return
   `identityUnverified` or `unsupportedVersion` as appropriate.
5. Use stable formula version plus revision for the candidate latest package.
   Cross-check any matching outdated record's `current_version` and relevant
   `installed_versions`. Contradiction produces unknown, not a preferred guess.

**Absence from the outdated list is not sufficient for `upToDate`.** A machine
may have a current keg installed while PATH selects an older keg. Compare the
verified selected package with stable metadata even when no outdated record is
present. Similarly, an outdated unselected keg must not make a current selected
tool show an update. This seam requires both positive and negative tests.

JSON decoding validates consumed fields and collection types, while tolerating
additional fields. Require a v2 root object and formula arrays, string names,
installed-version collections, and usable stable/revision data for relevant
records. Ignore unrelated cask records; their presence does not enable cask
support. An invalid envelope fails the batch; a malformed relevant record makes
that tool unknown without assigning its data to another tool.

Each process has a ten-second wall-clock deadline and the existing 1 MiB stdout
limit. No subprocess failure, nonzero exit, invalid UTF-8/JSON, truncation, or
timeout is a successful empty result. Maximum manager-work time is three
sequential deadlines plus existing bounded cleanup; skip later queries after a
batch-wide failure. Do not retry automatically.

Reuse `BoundedProcessRunner` from within the core. Bridge its blocking work onto
a utility dispatch queue with a checked continuation; do not block an actor or
the main executor. M6 runs one manager batch at a time, so update concurrency is
bounded at one. Support task cancellation between queries and before cache
publication; an already running query remains bounded by its deadline and must
finish cleanup. Do not report cancellation as successful empty metadata.

Represent process outcomes behind an injectable adapter. Production cannot
distinguish a DNS failure or HTTP 429 from arbitrary nonzero exit with the
current stdout-only runner; classify those opaque outcomes as `probeFailed`.
Use `networkUnavailable` for explicit offline policy or otherwise verified
network-unavailable evidence, and `rateLimited` only with typed evidence from a
future/controlled adapter. Do not guess either from empty stdout. This keeps
§21's reasons available without expanding the bounded-runner contract in M6.

## Cache contract

Use a versioned JSON file in an app-owned directory under the user's caches
directory, for example `~/Library/Caches/AgentLens/update-metadata-v1.json`.
Inject its URL and clock into tests. No test may read or write the real cache.

Persist validated metadata, not a precomputed `VersionStatus`. Recalculate
status against the current local version, selected target, install state, and
M5 consistency result every run. Cache keys include canonical manager identity
and its file modification/size fingerprint,
Cellar, full formula identity, selected keg/target, and a fingerprint of the
probe-affecting environment/working directory. Persist no raw environment,
credentials, tokens, shell output, or unrelated package inventory. A changed
environment fingerprint invalidates reuse without revealing its contents.
Use a stable cryptographic digest of a deterministic serialization, not Swift's
process-randomized `Hasher`. Foundation/platform libraries are permitted within
the zero-external-dependency boundary. Recheck that the selected entry still
resolves to its observed target before publishing a cached or probed status;
a changed target yields an unavailable identity result rather than stale claims.

- TTL is exactly 21,600 seconds. Age must satisfy `0 <= age < TTL`; age equal to
  TTL, a future timestamp, or malformed time is a miss.
- Only a validated successful batch writes reusable metadata. Unknown/failure
  outcomes do not become six-hour negative cache entries.
- `--refresh-updates` bypasses reads; a failed refresh yields current unknowns,
  never silently falls back to old successful status. An old cache may stay on
  disk with its original timestamp; it is not promoted or served by that refresh.
- Plain and offline scans neither read nor write update metadata.
- Bad schema, corrupt JSON, absent file, read failure, or mismatched identity
  causes a miss. A write failure leaves the successful current result usable.
- Limit cache input/output to 1 MiB; store only eligible selected-tool records.
  Use an atomic replacement in the same app-owned directory. Concurrent scans
  may be last-writer-wins, but must never expose a partial document.
- Store the actual metadata observation timestamp. A cache hit never renews it.
  Display cached provenance and that timestamp.

No scan mutates a package-manager cache deliberately. Homebrew may maintain its
own metadata while answering a query; that does not authorize tool operations.
The Agent Lens cache is the only storage this implementation owns.

## Implementation sequence and per-step exits

Use one milestone branch, suggested `feat/m6-version-update-probing`. Preserve
unrelated user changes and keep each implementation increment small. Reviewers
remain read-only; the implementer supplies evidence and the orchestrator accepts.
The user chooses any worker/model roster separately; this brief assigns none.

1. **Preflight and baseline.** Record HEAD, branch, working-tree status, Swift
   version, and fresh build/test output. Read only the current APIs named above.
   Exit: baseline is understood, existing suite passes, and scope matches this
   brief. If HEAD differs, inspect the intervening diff before proceeding.
2. **Status and comparison.** Add models and pure tests, then comparison code.
   Use a compiling minimal scaffold to demonstrate a semantic RED assertion,
   not an import/type/compiler failure. Exit: strict ordering, revision policy,
   optional local version, and unknown behavior pass focused tests.
3. **Identity and JSON adapter.** Add synthetic Cellar/manager layouts, raw JSON
   fixtures, injected command results, and the adapter. Exit: selected ownership,
   stale/current selected-keg controls, parsing failures, and fixed query counts
   pass; no real installation is needed.
4. **Async coordination and cache.** Add injected clock/cache/process seams,
   then async bridging and storage. Exit: no-probe policies, six-hour boundaries,
   refresh failures, concurrency/cancellation, and correct association pass.
5. **Renderer and CLI.** Append the pure status section and implement exact flag
   parsing. Exit: subprocess CLI tests observe stdout/stderr/exit status, local
   output arrives before delayed probe completion, and M5 output is preserved.
6. **Full acceptance and focused review.** Run the matrix and gates below; inspect
   the complete diff and file scope. Exit: all failures/findings are resolved
   within scope, raw evidence is attached, and no background child remains.
7. **Independent acceptance and handoff.** The orchestrator reruns the same gates
   in a fresh scratch root and checks the diff itself. Only then update the M6
   log and record acceptance. Stop at M6; follow the user's delivery instructions
   for commits/pushes rather than inferring publication from this plan.

## Required synthetic acceptance matrix

Tests use isolated scratch paths, injected environments, and controlled fake
executables/results. They must never change real PATH directories, package
installations, shell profiles, or manager state. Use the repository's Swift
Testing conventions. Every requirement below needs a discriminating assertion;
the test count itself is not the gate.

| Area | Required proof |
|---|---|
| Three statuses | Equal and older verified versions yield the correct state; unknown stays neutral. |
| Numeric ordering | `1.9.0 < 1.10.0`; multi-digit and large components are handled safely. |
| SemVer | `alpha.2 < alpha.10 < beta < release`; shorter prerelease order and build-metadata equality. |
| Homebrew revision | Equal CLI upstream versions but selected `_1` versus latest `_2` yield an update. |
| Unsupported formats | Date/non-semver/`1.x`/HEAD/malformed/newer-than-known produce unknown, retaining local text. |
| Selected package | Verified Cellar/formula/keg metadata is attached only to its selected target. |
| Identity failures | Same basename in another prefix/tap, false `/Cellar/` substring, ambiguous/missing metadata, and changed target cannot borrow another result. |
| Multiple kegs | Older selected keg with current keg installed still shows update; current selected keg with older unselected keg stays current. |
| Batch behavior | Several eligible tools use at most three commands; deduplicated metadata arguments; no per-tool process fanout. |
| Empty eligibility | Default-style npm/standalone/missing tools invoke zero manager commands. |
| Manager lookup | Ordered PATH winner, broken links/directories skipped, empty/relative roots and manager symlinks work; explicit environment reaches every query. |
| Process bounds | Hanging descendant, early stdout EOF, continuous/oversized stdout, and nonzero exit return unknown within deadlines; selected local versions survive. |
| JSON | Invalid envelope/types/truncation fail closed; extra fields are tolerated; relevant malformed record is isolated; irrelevant package/cask data is not rendered. |
| Offline/disabled | Plain scan yields `notChecked` where eligible; offline yields `networkUnavailable`; neither launches probes nor reads update cache. |
| Reason honesty | Generic failed subprocess is `probeFailed`; only typed network/rate-limit evidence produces those specific reasons. |
| Cache TTL | Valid hit before six hours; exact expiry, future timestamp, changed manager/target/environment, and corrupt/wrong schema are misses. |
| Cache refresh | Refresh ignores cache; success replaces metadata; failed refresh produces unknown and does not renew old data. |
| Cache storage | Only successful validated metadata persists; atomic replacement and failed writes do not break inventory. |
| Reassociation | Filtering/completion order cannot mix IDs; installed-version changes recompute status; M5 inconsistency suppresses status claims. |
| Async behavior | Delayed fake probe leaves local report observable first; work does not block actor/main execution; only one manager batch is active. |
| Cancellation | No later command/cache publication after cancellation is observed; any running child is bounded and cleaned up. |
| Output/count | Registry order, dashes, reasons and provenance are stable; only selected `updateAvailable` results increase count. |
| CLI syntax | All four valid scan forms, no arguments, debug-env, unknown command/flag, duplicates/combinations and extra operands have specified exit/stream behavior. |
| M5 preservation | Existing report remains the prefix; winner/alias/shadowed/invalid/off-PATH/degraded behavior and local query count remain unchanged. |

CLI integration must execute the built CLI, rather than only test a usage string
or argument-parser function. Provide a synthetic login-shell environment using
an isolated HOME/rc fixture and a fake brew on its PATH, following the existing
resolver's actual shell-capture behavior. On this zsh machine, set `ZDOTDIR` to
the scratch rc directory and control PATH from its startup files; `$SHELL` does
not select the resolver's shell. Put fake Codex/OpenCode/Grok executables in the
fixture PATH so the default detectors do not fall through to real extra roots.
Include `/usr/bin:/bin` for the resolver's `env -0` command. Do not add a production test-only
environment override. Fake scripts must use absolute interpreter paths and
write command logs only inside scratch space. Mark any test that changes
process-wide CWD/environment as serialized or use isolated subprocesses.

Record at least one meaningful RED→GREEN transcript for update classification
and one for offline/no-probe integration. RED must fail on the intended behavior
with compiling code; deliberately broken imports do not demonstrate acceptance.

## Acceptance commands and evidence

These commands are for the future implementation worker and orchestrator.
They were **not executed while writing this plan**.

Start with the ordinary package gates in the project root:

```sh
git status --short
git rev-parse HEAD
swift --version
swift build
swift test
```

Build and full tests must exit 0. Retain the measured baseline and final test
totals; acceptance requires all existing tests plus the matrix, not a predicted
number. If this Mac reproduces the previously recorded Swift Testing macro
loading problem, use the documented toolchain workaround and explain it in the
walkthrough rather than changing `Package.swift`:

```sh
m6_acceptance_root=$(mktemp -d /tmp/agent-lens-m6.XXXXXX)
mkdir -p "$m6_acceptance_root/fixtures"
AGENT_LENS_TEST_SCRATCH="$m6_acceptance_root/fixtures" swift test \
  --build-system swiftbuild \
  --scratch-path "$m6_acceptance_root/build" \
  -Xswiftc -load-plugin-library \
  -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib
```

Treat that library path as a machine-specific fallback, not a portable project
requirement. The orchestrator uses a new scratch root for its rerun.

Run the CLI smoke checks separately and capture each exit status:

```sh
swift run agent-lens scan
swift run agent-lens scan --offline
swift run agent-lens scan --check-updates
swift run agent-lens scan --refresh-updates
swift run agent-lens debug-env
swift run agent-lens
swift run agent-lens unknown-command
swift run agent-lens scan --unknown-flag
swift run agent-lens scan --check-updates --offline
swift run agent-lens scan --offline --offline
swift run agent-lens debug-env --offline
swift run agent-lens scan extra-operand
```

The first six forms exit 0. The remaining six exit 1 with usage on stderr.
Probe-mode success does not require any real tool to be brew-managed or any
network to be available. Full success-path evidence comes from the synthetic
CLI tests, including the fake manager's raw command log and delayed output.
`debug-env` exposes only the resolver's existing debug output; do not dump raw
environment variables into transcripts.

Verify scope and module boundaries:

```sh
git diff --check
git diff --name-only
git status --short
git diff
rg -n '^import (SwiftUI|AppKit)' Sources/AgentLensCore
```

Expected: whitespace check passes, all changes are allow-listed, untracked files
are included in the review, and the import search has no matches (rg exit 1).
Inspect new files too; `git diff` alone omits untracked content. Do not stage
unrelated files merely to make them appear in a diff.

The M6 walkthrough must include baseline/RED/GREEN/final raw stdout/stderr and
exit statuses, scratch/toolchain details, fake-manager query counts, offline
zero-query proof, cache-boundary proof, final diff scope, reviewer findings and
their disposition, and the independent rerun. Summaries may explain evidence
but must not replace or manufacture terminal output.

## Done when

M6 is complete only when the full existing suite and every applicable matrix
requirement pass, CLI behavior matches this brief, raw evidence is attached,
the orchestrator independently reruns acceptance and inspects the complete
allowed diff, and the M6 decision/log entry records the actual limitations.

In particular, the finished milestone must demonstrate both a supported
Homebrew update/current result on synthetic selected installations and a useful
offline inventory with unknown statuses. Unsupported managers and unsupported
version schemes remain explicit unknowns. No M7 work or tool-modifying action
is included in this acceptance.

## Paste-ready worker handoff

```text
Implement M6 using briefs/M6-version-update-probing.md as the frozen task brief.
Start with its preflight/baseline, then follow the ordered implementation steps.
Keep all changes within its file allow-list. Preserve M5 detection and PATH
diagnostics. Add the Homebrew formula batch adapter, typed unknown outcomes,
six-hour metadata cache, explicit CLI modes, and deterministic synthetic tests.
Supply raw RED/GREEN and final acceptance transcripts in the M6 walkthrough.
Do not self-declare acceptance: the orchestrator must independently rerun it.
Stop at M6. Do not start M7 or perform install/update/uninstall operations.
```
