# Agent Lens

A macOS-native utility that tells you **which AI CLI tools are actually installed, where they came from, and which copy PATH resolves to**. Built in Swift 6 (D-001): an `AgentLensCore` engine plus an `agent-lens` CLI, with a SwiftUI native macOS development app added at M7.

This repository surfaces the diagnostic that no existing tool answers: when multiple copies of an AI CLI exist on your machine, which one wins — and why. See `AGENT_LENS_SCOPE.md` for the full scope and `DECISIONS.md` for settled design decisions.

## Development app (M7)

A scratch-only, unsigned native macOS development app was added at M7. Build it locally with `scripts/build-dev-app.py` (default `debug`; `--configuration release` is also supported) into a fresh scratch root outside the repo and protected roots, e.g. under `$HOME/.hermes/cache/scratch`:

```sh
m7_root="$HOME/.hermes/cache/scratch/agent-lens-m7-$(uuidgen)"
mkdir -p "$m7_root/tmp"
TMPDIR="$m7_root/tmp" python3 scripts/build-dev-app.py \
  --scratch-root "$m7_root/dev-app" --configuration debug
```

The builder prints the absolute `.app` path. Open it from Finder or with:

```sh
open "$m7_root/dev-app/AgentLensApp-debug.app"
```

This is local development only: unsigned, no signing, notarization, install, release, or GitHub delivery. It is not a release product. See [walkthrough](walkthroughs/M7-first-ui.md) for the measured implementation/acceptance walkthrough, including debug/release builder command shapes and the packaging trust boundary.

## Usage

```sh
agent-lens scan                      # local inventory and PATH diagnostics; no update checks
agent-lens scan --check-updates      # add update status; uses a valid six-hour cache when present
agent-lens scan --refresh-updates    # bypass the cache and probe Homebrew again
agent-lens scan --offline            # local inventory only; no update probe, no cache read
agent-lens debug-env                 # show the login-shell environment used for discovery
```

The three `scan` update flags are mutually exclusive. Invalid syntax prints usage to stderr and exits 1.
The `VERSION / UPDATE STATUS` section is appended after the PATH diagnostics report. Status values are
`up to date`, `update available`, or `unknown` with a neutral reason. Plain `scan` and `--offline` do
not run manager queries or read/write update metadata; `--check-updates` uses valid cached metadata
when available, while `--refresh-updates` bypasses it.

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
is intermittent, the M6 walkthrough records the invocation-local `swiftbuild`/macro-plugin fallback;
no package or toolchain change is required.
