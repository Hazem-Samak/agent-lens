# M13-C disposable Homebrew acceptance fixture

**This directory is fixture evidence, not a product capability and not an acceptance verdict.**
The acceptance decision belongs to the orchestrator (D-014); this harness only produces raw,
inspectable evidence that the disposable real-Homebrew environment and the synthetic lifecycle
primitives work. It contains no product source change.

`homebrew_acceptance.py` is a standard-library-only Python 3 script. It builds a completely
disposable Homebrew prefix from the pinned local Homebrew git source, redirects every cache, log,
temp and application path into an operator-owned scratch root, and runs the synthetic
formula/cask lifecycle only while an outer macOS seatbelt profile denies every write outside that
root except `/dev/null`, and denies all IP networking.

The fixture never uses `sudo`, never enters a password, never runs a cask `uninstall`/`zap`
stanza, and never falls back to a personal Homebrew prefix as an execution target. It does not
launch the personal `brew` binary even read-only: personal-root evidence comes from the full-run
manifests and the deny-by-default profile.

## Prerequisites

- macOS with `/usr/bin/sandbox-exec` available.
- A local Homebrew git repository at `/opt/homebrew` (override with `--source`) containing the
  pinned revision `456c79a9946d416cac0b675850a33b169ccdc19a`. The checkout may have a newer HEAD;
  the revision must exist locally. No download or network is used.
- The pinned revision's vendored portable Ruby under
  `<source>/Library/Homebrew/vendor/portable-ruby/current` (4.x). It is copied read-only into the
  scratch prefix and verified before use; system Ruby 2.6 is not sufficient.
- Python 3.9 or newer. Only the standard library is imported.
- The operator's account must own the chosen destination parent and its full ancestor chain must
  be safe (see Root ownership below). The standard per-user Darwin `$TMPDIR` route is admitted.

The Homebrew revision is fixed. `--expected-revision` exists only for explicitness: any value
other than the pinned revision is rejected by argparse, so a version-specific safety protocol can
never be run against a different manager revision.

## Running

```sh
# Help, exit code and controls; creates nothing.
python3 Tests/Fixtures/M13/homebrew_acceptance.py --help

# Validate a destination without creating it. Exit 0 means acceptable.
python3 Tests/Fixtures/M13/homebrew_acceptance.py --check-root /path/that/does/not/exist

# The same check with an explicitly relocated read-only source.
python3 Tests/Fixtures/M13/homebrew_acceptance.py --source /path/to/homebrew \
  --check-root /path/that/does/not/exist

# Full fixture run. ROOT must be absolute and must not exist.
python3 Tests/Fixtures/M13/homebrew_acceptance.py --root "$SCRATCH/m13-c"
```

`--check-root` uses exactly the same validation function and requirements as `--root` (absolute
normalized path, non-existent, identity-based protected/unsafe ancestor refusal, operator-owned
safe parent, full ancestor trust chain). It creates nothing and never cleans anything.

`--bootstrap` stops after environment construction and prints the environment facts and a
**bootstrap-only** proof count: preflight/environment checks and containment probes, with zero
lifecycle scenarios. It is useful for diagnosing the pinned source, portable Ruby, clone, stub
core tap and fixture tap; it is not an acceptance run.

The full run prints a machine-readable summary and exits `0` only when every check passed and the
personal manifests are byte-identical. Nonzero exit codes:

- `1` unexpected fixture failure (traceback printed; evidence retained);
- `2` unsafe/invalid destination, rejected revision override, or argparse usage error;
- `3` blocked, missing environment prerequisite, or one or more fixture checks failed;
- `0` fixture evidence passed (still not an orchestrator acceptance verdict).

## Root ownership, retention and inspection

`--root` is created once, exclusively, with mode `0700`; it must be physically owned by the
invoking user. `ownership.json` records a random nonce, owner uid, device/inode, and the parent
device/inode/owner. Before every manager mutation the harness revalidates the physical root and
parent identity, owner, nonce, mode and that both are still real directories (not symlinks), and
that the parent is not writable by another account. A destination that already exists is refused;
the harness never adopts, reuses or recursively cleans a root. **The root is retained on every
success and failure for inspection.** Delete it manually only after reviewing the evidence.
Nothing under the root is committed to the repository.

Destination validation compares directory **device/inode identities**, not path strings. This is
required on a case-insensitive disk where `Path.realpath` preserves the supplied letter case.
Refused regardless of alias spelling:

- the personal Homebrew prefix (`/opt/homebrew`), `/Applications`, system trees, `/Volumes`, the
  invoking account's password-database home (independent of inherited `HOME`), and the local
  `--source` repository;
- descendants of any of those trees (`/OPT/HomeBrew/x`, `/applications/x`, `/USERS/<name>/x`,
  symlinked parents into them);
- the shared/excluded trees `/opt`, `/Users`, `/Users/Shared`, `/tmp`, `/private/tmp`, `/var/tmp`
  and `/private/var/tmp`;
- any destination whose physical ancestor chain contains a directory that is writable by another
  account without the sticky bit, or is owned by an account other than the operator or root;
- a destination whose immediate parent is not owned by the invoking account.

The **entire** ancestor chain to `/` is inspected; inspection does not stop at the first
`/private/var/folders` component. The normal per-user Darwin temp route
(`/private/var/folders/<a>/<b>/T/...`, or its `/var/folders/...` alias) is therefore admitted
because each component is root- or operator-owned and not writable by another account. A
synthetic world-writable ancestor above the parent is refused even when the parent itself is
private and operator-owned.

## What the harness constructs

1. Validates the destination and creates the owned root, seatbelt profile and closed environment.
2. Proves containment with harmless controls **before any manager mutation** (see below).
3. Verifies the pinned revision exists and the vendored portable Ruby is 4.x.
4. Clones the local source with literal argv `git clone --no-hardlinks <source> <prefix>`,
   checks out the exact revision detached, verifies `HEAD`, copies only the needed portable Ruby,
   and makes the scratch `bin/brew` read-only (`0555`). `clone.json` records the literal clone
   argv, per-command cwd and step sequence; `no_hardlinks` is read from the clone argv itself.
5. Creates an empty stub `homebrew/core` git tap so a `depends_on` can never trigger a network
   core clone. Creates the local `m13test/test` tap from deterministic `file://` payloads and
   trusts it offline (`brew trust m13test/test`).
6. Runs synthetic formulae and casks with literal argv, closed stdin, bounded timeouts, process
   group cleanup, fixture `HOME`/cache/logs/temp, scratch `--appdir`, and an explicit scratch brew
   executable (never PATH resolution of a personal `brew`).

Every command runs with a cwd physically inside the root and with the fixed fixture environment
(`HOME`, cache, logs and temp all inside the root; no inherited `HOMEBREW_PREFIX`, `CELLAR` or
`CASKROOM`). Every egress revalidates the profile digest, cwd identity, root/parent identity and
environment, and records the cwd and profile digest in the step receipt. Every scratch brew call
is launched as:

```text
/usr/bin/sandbox-exec -f <root>/seatbelt.sb <root>/prefix/bin/brew <literal arguments...>
```

with descriptor `198` pointing read-only at `<root>/prefix/Library/Homebrew/sandbox.rb` and the
scratch `bin/brew` mode `0555`. That is the pinned Homebrew inherited-sandbox protocol: Homebrew
detects the outer sandbox and skips its nested `sandbox-exec` PTY path. No personal `brew` file or
personal sandbox descriptor is used.

## Isolation profile and its exact exceptions

The generated profile (`<root>/seatbelt.sb`) is:

- `(deny network*)` first, then one path-filtered Unix-socket rule:
  `(allow network* network-outbound (subpath "<root>/tmp"))`. IP networking has no path and
  remains fully denied; Unix bind and connect are confined to the fixture temp directory.
- `(deny file-write*)` first, then writes only under `<root>` and the literal `/dev/null`.
  **There is no system temporary write exception** and no grant to `/private/tmp`,
  `/private/var/tmp` or any `sh-thd`/mkstemp name pattern.
- No `/dev/tty` allowance and no inherited controlling TTY. Child stdin is `/dev/null`.

Bash here-strings work because every child runs with a scratch cwd: macOS Bash creates its
temporary file in the writable cwd rather than in the system temp directory. The preflight
control proves this with the same cwd and closed environment used by manager launches; a scratch
cwd is required, not assumed. If a future command needed a system temp file, the correct action
is a stop, never a broad directory grant.

Denial evidence is explicit, per call: each probe reports a syscall outcome and errno as JSON;
a check passes only when the outcome is an `OSError` with `EPERM` or `EACCES` (or `ENXIO` for the
no-TTY control). An arbitrary nonzero exit, timeout, import error or refused connection is never
accepted as containment. The egress check before every manager mutation includes a live IP-bind
probe with the same explicit-errno requirement.

Preflight writes are attempted only in disposable synthetic canaries owned by the harness outside
the root. The controls try to write-open an existing canary file and create nonce-named directories
beside the root and in shared temp. If a creation succeeds, the harness records a failure and
attempts to remove the test directory. The personal-home and pinned-source controls write-open an
existing operator-owned file **without writing data** and compare its contents and metadata.
The full-run manifests also record any change to the protected roots.

## Manifest proof window

The run is wrapped in one manifest window:

1. the `before` snapshot is captured **before** fixture directory setup, the seatbelt preflight,
   clone, portable Ruby, stub core tap, tap/trust, and any manager use (`before_step: 0`);
2. the after snapshot is captured **after the last recorded command** (final formula and cask
   inventories), so its `captured_after_step` equals the total step count;
3. the same after capture and manifest comparison run after any failed scenario, and on an
   ordinary early bootstrap failure before that failure is re-raised.

Equality means the full node set is identical and every recorded value is equal:

- regular files: SHA-256 of contents, size, mode, uid, gid, `mtime_ns`, `nlink`;
- directories: mode, uid, gid, `mtime_ns`, `nlink`;
- symlinks: target, mode, uid, gid, `mtime_ns`, `nlink` (symlink entries inside a tree are never
  followed);
- absent roots are recorded as absent and must stay absent;
- entry paths and their physical targets are both represented, so a symlinked Homebrew prefix,
  `/Applications` or cache entry cannot hide the tree it points at; a relocated `--source` is
  manifested too.

Any read/hash error fails the run rather than dropping entries. A failed before snapshot aborts
safely before setup; a failed after snapshot fails the run and retains the raw failure receipt.
A manifest difference fails acceptance even when another subprocess also failed.

## Cask refusal: fixture launch guard and argv audit

The general launcher requires an explicit `--formula` for upgrades and uninstalls. Cask upgrades
and uninstalls go through `guard_cask_mutation`. The guard verifies the bare and fully qualified
identity from fresh `brew info --json=v2 --cask` and records that command before checking:

- uninstall stanza -> refusal;
- zap stanza -> refusal;
- any artifact kind other than `binary`/`app`/`command_wrapper` -> refusal;
- any absolute artifact target that resolves outside the fixture root -> refusal (`unsafeTarget`);
- no artifacts -> refusal.

A refused cask gets a recorded `fixture-refused` decision with the fresh info step, artifact
SHA-256 and reasons; **no upgrade/uninstall process is launched**. Allowed casks get a
`fixture-allowed` record whose launched receipt is later matched against the argv audit. The
delete/zap and app/quit casks remain installed with their sentinels intact; a synthetic escape
cask whose uninstall target is an absent path outside the root proves `unsafeTarget`
classification, and the target remains absent. `zap`, `sudo`, `--ignore-dependencies`,
`--force`, AppleScript, `pkgutil` and kext operations are never launched.

The full-run audit (`manager-argv-audit.json`) checks every recorded scratch `brew` launch after
the final inventory commands. It checks for bare and fully qualified names of refused casks,
matches each cask upgrade or uninstall to its guard decision, and flags forbidden arguments. The claim is limited
to **argv the harness launched**; descendant processes are not enumerated. This is fixture policy
evidence, not a future Agent Lens verdict. The product mutation boundary is narrower than this
fixture's scenario set (R7): the no-stanza app cask here is a dispatch-required fixture scenario,
not approval for product app-cask mutation.

## Scenario coverage

| Section | Evidence |
| --- | --- |
| Environment | pinned clone revision, literal clone argv, portable Ruby 4.x, scratch `brew --prefix/--cellar/--caskroom`, stub core tap, trusted offline tap, fixed revision set |
| Formula old→new | install 1.0.0, populated `outdated --json=v2 --formula` record with the full tap name, upgrade to 1.2.0, old keg retained, linked-keg-only uninstall, bin link not relinked |
| Formula sentinels | sentinel formula with two kegs; byte-identical contents after target upgrade and uninstall; suppression flags effective |
| Formula refusals | pinned upgrade exits 1 with the manager's exact "Not upgrading 1 pinned package" text and no version change; broken update exits 1, shows the failing `false` command, keeps the old keg and the old 1.0.0 link; dependent uninstall exits 1, names the consumer, keeps both kegs, no `--ignore-dependencies` |
| Binary cask | install, `list --verbose` staged Caskroom target, populated cask outdated JSON, guarded upgrade, guarded clean Caskroom/bin removal |
| App cask, no stanza | scratch `--appdir`, staged symlink into scratch, app upgraded without repeating `--appdir`, saved appdir honored, guarded clean removal, real `/Applications` untouched |
| Cask variants | `auto_updates true`, `:latest`, comma/CSV versions; plain outdated lists only the comma cask; `--greedy`, `--greedy-auto-updates`, `--greedy-latest` sets match manager behavior |
| Cask refusal | app/quit-stanza, delete/zap-stanza and unsafe-target casks are installed, classified from fresh `info` artifacts, refused before any upgrade/uninstall launch, remain installed; delete/zap sentinels retain hashes; unsafe target remains absent; zap is never run |
| Final state | personal `/opt/homebrew` (including Cellar/Caskroom/pinned state), `/Applications`, Homebrew caches/logs and Agent Lens cache roots hashed before setup and after the last command; contents + metadata byte-identical required; absent roots recorded; relocated source included |

The cask refusals are **fixture policy** evidence, not a future Agent Lens verdict. They show the
manager metadata, classification and zero-mutation-launch shape that product code will later
classify. The fixture does not implement or approve product promotion, confirmation, preview,
native Accessibility journeys, CLI parity, interruption or concurrency behavior; those belong to
later product tests and the combined M13 gate.

The harness does not run cask `zap`, `uninstall` stanzas, AppleScript, `sudo`, `pkgutil`, `kext*`
or any elevating/interactive step. Multi-keg residue is reported as residue, never as complete
removal.

## Evidence layout

Everything is under `<root>/evidence/`:

- `report.json` — machine-readable checks, scenarios (including `failed_checks`), failures and
  step index;
- `summary.json` — status, manifest window, manifest digests, proof counts, refused casks and
  allowed guarded mutations;
- `steps/*.json` — literal argv, exit, stdout, stderr, elapsed, actual cwd and cwd identity,
  sandboxed flag, profile SHA-256, environment SHA-256, fd 198 marker;
- `seatbelt.json` — profile text, digest, exact write allowlist and the no-system-temp note;
- `preflight-canaries.json` — canary locations, open-only personal/source probes and the
  explicit-errno policy;
- `manifests/{before,after}/` — per-root JSONL node manifests, summaries and capture step;
- `digests/` — sentinel and keg tree digests;
- `manager-argv-audit.json` — every scratch-brew launch with action, arguments and audit verdicts;
- `environment.json`, `source.json`, `clone.json`, `portable-ruby.json`, `brew-identity.json`,
  `stub-core-tap.json`, `tap.json`, `payloads.json`, `outdated-variants.json`,
  `cask-refusals.json`, `residual-state.json`.

`report.json` and the retained steps are the raw evidence to inspect.

## Limits and honest gaps

- The harness is not an Agent Lens binary and does not exercise product ownership, mutation,
  preview, refusal or promotion code.
- Homebrew is a real manager at a pinned revision, but the fixture tap, formulae and casks are
  synthetic and use local `file://` payloads only.
- Cask stanza/unsafe-target refusal is demonstrated by fixture classification and a fixture
  launch guard. The product's typed refusal and disclosure vocabulary is reviewed elsewhere
  (R7/R8).
- Plain `outdated --cask` absence is not currency for `auto_updates`/`:latest`; the fixture
  records the manager's exact JSON and the greedy variants instead of inventing a comparator.
- The personal manifests include content hashes and metadata of large trees (`/opt/homebrew`,
  `/Applications`), so a full run takes minutes. Unrelated external activity that changes a
  personal tree will honestly fail the byte-identical requirement.
- Personal-root probes are non-mutating write-opens of existing files. They prove a path-specific
  denial with explicit errno; they do not attempt to create files there, by design. Full-run
  manifest equality is the field evidence that the roots did not change.
- The argv audit covers harness launches only; it does not enumerate descendant processes.
- The fixture leaves installed synthetic packages and the scratch root behind for inspection. It
  never claims cleanup.
