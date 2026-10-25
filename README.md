# Agent Lens

A macOS-native utility that tells you **which AI CLI tools are actually installed, where they came from, and which copy PATH resolves to**. Built in Swift 6 (D-001): an `AgentLensCore` engine plus an `agent-lens` CLI, with a SwiftUI native macOS development app added at M7.

This repository surfaces the diagnostic that no existing tool answers: when multiple copies of an AI CLI exist on your machine, which one wins — and why. See `AGENT_LENS_SCOPE.md` for the full scope and `DECISIONS.md` for settled design decisions.

The [complete application roadmap](ROADMAP.md) maps the remaining work through manager-backed Update/Uninstall, broader tool support, the finished native interface, and signed distribution. **M9 is technically accepted and user-UI-approved on `milestone/m9-verified-inventory`; it has not been committed/pushed.** M10–M19 remain planned, not delivered features.

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
writable root. `AGENT_LENS_TEST_PRODUCTS` is optional. Tests use synthetic tools/managers and must not
change installed tools or the real Agent Lens cache. On machines where Swift Testing macro discovery
is intermittent, the M9 acceptance record documents the invocation-local `swiftbuild`/macro-plugin fallback.
The final M9 gate passed all 329 Swift tests with `--no-parallel` and 9 packaging checks; no assertion was loosened or test skipped. An unchanged M6 real-process timing bound had failed under worker parallel load. No package/toolchain change was made; clean-CI/default-TMPDIR portability remains M10-A work.
