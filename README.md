# Agent Lens

A macOS-native utility that tells you **which AI CLI tools are actually installed, where they came from, and which copy PATH resolves to**. Built in Swift 6 (D-001): an `AgentLensCore` engine plus an `agent-lens` CLI, with a SwiftUI native macOS development app added at M7.

This repository surfaces the diagnostic that no existing tool answers: when multiple copies of an AI CLI exist on your machine, which one wins — and why. See `AGENT_LENS_SCOPE.md` for the full scope and `DECISIONS.md` for settled design decisions.

The [complete application roadmap](ROADMAP.md) maps the remaining work through manager-backed Update/Uninstall, broader tool support, the finished native interface, and signed distribution. **M9 is technically accepted, user-UI-approved, and delivered to `main` (feature commit `eb4f586`, integrated milestone tip `1ac22c4`).** No public app release was published. M10–M19 remain planned, not delivered features.

## Build and open the development app

A scratch-only, unsigned native macOS development app was added at M7. Build it locally with `scripts/build-dev-app.py` (default `debug`; `--configuration release` is also supported) into a fresh scratch root outside the repo and protected roots, e.g. under `$HOME/.hermes/cache/scratch`:

```sh
app_root="$HOME/.hermes/cache/scratch/agent-lens-$(uuidgen)"
mkdir -p "$app_root/tmp"
TMPDIR="$app_root/tmp" python3 scripts/build-dev-app.py \
  --scratch-root "$app_root/dev-app" --configuration debug
```

The builder prints the absolute `.app` path. Open it from Finder or with:

```sh
open "$app_root/dev-app/AgentLensApp-debug.app"
```

M7 source and acceptance documentation are delivered on `main` in commit `36a3f1c`. The app remains local development only: unsigned, with no signed/notarized app distribution or public release. See [walkthrough](walkthroughs/M7-first-ui.md) for the measured implementation/acceptance walkthrough, including debug/release builder command shapes and the packaging trust boundary.

M8 adds **Copy Path** and **Reveal in Finder** for the selected executable entry and its recorded resolved target in tool details. Independent automated gates and two final reviews passed; the user approved the UI and Git delivery on 2026-10-18. Native keyboard-only activation remains unverified. See the [M8 walkthrough](walkthroughs/M8-path-actions.md) for evidence and limits, and the [milestone index](briefs/README.md) for status.

M9 adds category/declared-package/official-link metadata, explicit **Verify Installation** for supported npm-global/Homebrew-formula layouts, and **Canonical Installation Versions** in Diagnostics. Separate copies keep their own versions; aliases share one observation. Source hints and package declarations are not ownership proof. Verification can return a neutral Unknown and does not enable Update or Uninstall. See the [M9 acceptance record](walkthroughs/M9-verified-installations.md).

This is still a locally built, unsigned development app: no Agent Lens installer, DMG, Homebrew cask, notarized release or app updater is available yet. Building/opening it does not install the companion CLI globally. From this repository, use `swift run agent-lens scan --offline` or invoke a built `agent-lens` binary by its absolute path.

## Usage

```sh
agent-lens scan                      # local inventory and PATH diagnostics; no update checks
agent-lens scan --check-updates      # add update status; uses a valid six-hour cache when present
agent-lens scan --refresh-updates    # bypass the cache and probe Homebrew again
agent-lens scan --offline            # local inventory only; no update probe, no cache read
agent-lens verify-installation codex # explicit read-only ownership check for the selected installation
agent-lens debug-env                 # show the login-shell environment used for discovery
```

The three `scan` update flags are mutually exclusive. Invalid syntax prints usage to stderr and exits 1.
The `VERSION / UPDATE STATUS` section follows PATH diagnostics and declared detector metadata. Status values are
`up to date`, `update available`, or `unknown` with a neutral reason. Plain `scan` and `--offline` do
not run manager queries or read/write update metadata; `--check-updates` uses valid cached metadata
when available, while `--refresh-updates` bypasses it.

`verify-installation <registry-id>` accepts `codex`, `opencode`, or `grok`, scans that tool locally, then explicitly verifies supported npm-global/Homebrew-formula ownership. Unknown is a valid result (exit 0); invalid syntax or an unknown registry ID exits 1 before manager queries. The native app offers the same explicit action in tool details. No manager verification runs automatically during launch, plain scan, offline scan or rescan.

Local version measurement executes the discovered tool with its validated literal argument array. Diagnostic scans query each canonical target at most once, sequentially, with up to 3 seconds per query and a 10-second monotonic aggregate probe budget per tool. Remaining targets stay visible as budget-exhausted unknowns. Process cleanup and filesystem work can extend wall time; this is not an atomic filesystem freeze. A detected identity change invalidates the value, and a changed selected executable cannot retain a known selected version.

## Update status limitations

- Only **Homebrew formulae** are checked. npm, standalone, and unsupported managers show `unknown`.
- Latest values are **the latest known to Homebrew metadata**, not guaranteed newest upstream releases. The
  checker never runs `brew update`, so the displayed time is the observation time, not an upstream refresh time.
- Cached metadata is reused for six hours (`~/Library/Caches/AgentLens/update-metadata-v1.json`). The JSON
  document is schema 3, capped at 1 MiB, and stores only validated successful selected-formula metadata;
  status is recalculated from the current local version and selection. Keys include verified manager,
  formula, selected-target, and probe-context identities; context is stored as a stable digest, not raw
  environment values. Invalid or older-schema documents are cache misses.
- Unsupported version formats (dates, `HEAD`, `1.x`, malformed text) remain unknown, keeping the local text.
- Generic process failures remain `unknown` (`probeFailed`); network or rate-limit reasons are used only
  with explicit policy or typed evidence. No failure is guessed to mean “up to date.”
- Update checking never installs, upgrades, uninstalls, pins, relinks a tool, or refreshes Homebrew metadata.

## Tests and fixture safety

Run `swift build` and `swift test`. M6 integration fixtures use `AGENT_LENS_TEST_SCRATCH` when it is
nonempty, otherwise the standard macOS `TMPDIR`; they fail closed if neither supplies an authorized,
writable root. `AGENT_LENS_TEST_PRODUCTS` is optional and, when set, names a **directory** containing a
regular executable `agent-lens`. Tests use synthetic tools/managers and must not
change installed tools or the real Agent Lens cache.

### Check commands

```sh
python3 scripts/check-core-ui-imports.py        # D-002: no SwiftUI/AppKit imports in AgentLensCore
python3 Tests/Packaging/test_core_ui_imports.py # behavioral fixtures for that guard
swift build
swift test --no-parallel                        # inherits TMPDIR; leave both overrides unset
python3 scripts/build-dev-app.py --scratch-root <fresh-root> --configuration debug
python3 Tests/Packaging/test_dev_app_bundle.py --app <fresh-root>/AgentLensApp-debug.app
```

`--no-parallel` keeps the real-process timing bounds meaningful. The Core/UI guard exits nonzero on a
forbidden import and reports path and line; `--source-root` lets its fixtures inspect a disposable copy
instead of the real `Sources/AgentLensCore`.

### Default TMPDIR and the two overrides

With `AGENT_LENS_TEST_SCRATCH` unset (or empty) the fixtures use the inherited `TMPDIR`. With neither
set they fail closed. An explicit scratch root is an operator-authorized base for new uniquely named
children only; it is never a cleanup target. `AGENT_LENS_TEST_PRODUCTS` is optional and must name a
**directory** containing a regular executable `agent-lens` — an invalid value fails loudly rather than
using another build.

On the workstation where these fixtures were measured, `TMPDIR` is spelled `/var/folders/.../T/`, an
alias of `/private/var/folders/.../T/`, and the sandbox profile written for the CLI launch seams must use
the **physical** spelling for denial to take effect: in that observation the Seatbelt profile matched
physical pathnames only. This is measured behavior on that machine, not a claim about every macOS
release or every sandbox consumer. Accordingly the fixture scratch root keeps the display spelling for
its returned and asserted paths (`cliScratch` returns `/var/...`), while the profile receives the
`realpath(3)`-resolved physical spelling. Foundation's `resolvingSymlinksInPath()` returned the
un-resolved `/var/...` spelling in that same observation, which is why it is not used to build the
profile. The sandbox decoy proves mechanism behavior at its measured path; it is not a direct syscall
guarantee about the personal cache. The two-run `--check-updates` test is indirect no-reuse evidence
(six manager queries), not proof that every cache access was blocked.

### Continuous integration and its limits

`.github/workflows/ci.yml` runs one check on `macos-15` with `DEVELOPER_DIR=/Applications/Xcode_26.3.app/Contents/Developer`,
no caches, no dependency install, read-only permissions and a 30-minute budget. It builds, runs the
guard and its fixtures, an early isolation capacity gate, the full suite with `--no-parallel`, the debug app
build and all nine packaging checks. The `macos-15` label is a mutable image: the job records the observed
versions rather than assuming them. Requiring the check in branch protection is a separate
repository-settings action and is not covered here.

Each of those seven gates runs through a runner-temp helper that keeps the producer's raw stdout and
stderr in separate receipts, records the producer exit verbatim, and then runs a generated count
verifier that writes a per-gate metrics JSON. The step's effective exit is the producer's nonzero exit
unchanged, otherwise the verifier's exit, so a producer failure and a count-verification failure stay
distinguishable. The verifier fails a gate on absent, zero, under-floor or actually-skipped results: the
full suite requires two Swift Testing run summaries (`Test run with N tests`) satisfying the Core and
AppSupport floors and a declared total, plus three named registry/schema/query tests appearing as
**passed** events; the isolation gate requires at least one case; the guard fixtures require their
declared floor; packaging requires all nine. XCTest's `Executed 0 tests` wrapper is not counted as Swift
Testing cases. The summary step reports passed / failed / NOT RUN per gate with executed counts, skipped
counts, per-gate seconds and an aggregate, and fails when a count-bearing gate is missing evidence.

The two Swift summaries are matched to their floors by observed count, not by position, because the
emission order of the two targets is not guaranteed; the receipt reports the count that satisfied each
floor. Summaries are therefore not attributed to a specific target. Parsing reads both captured streams,
so a future toolchain that multiplexes the summary onto stderr still verifies; a summary split mid-line
across the two streams would not be rejoined and would fail closed.

Local tooling note (this workstation only, not a supported CI command): where Swift Testing macro
discovery is intermittent, the invocation-local fallback adds `-Xswiftc -load-plugin-library -Xswiftc
/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib` together
with `--build-system swiftbuild`. CI uses native macro discovery and must pass on its own.

The final M9 gate passed all 329 Swift tests with `--no-parallel` and 9 packaging checks; no assertion was loosened or test skipped. An unchanged M6 real-process timing bound had failed under worker parallel load. Those are historical results, not an M10-A pass: hosted CI for this phase is still pending.
