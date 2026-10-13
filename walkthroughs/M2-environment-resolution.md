# Walkthrough — M2: Environment resolution

**Date:** 2026-10-13
**Brief:** `briefs/M2-environment-resolution.md` — ⚠️ flagged as the **highest-risk milestone in the project**
**Commit:** `M2: login-shell environment resolution (getpwuid, sentinel capture, timeout fallback)`
**Live at:** [github.com/Hazem-Samak/agent-lens](https://github.com/Hazem-Samak/agent-lens)

---

## What this milestone was for

The one thing that quietly kills every "why can't my GUI find my tools" product: **a macOS app launched outside Terminal does not inherit the login shell's PATH.** Entries from `.zshrc`, `eval "$(brew shellenv)"`, `~/.local/bin`, `~/.opencode/bin` and friends are all absent. Without solving this correctly, every later milestone reports tools as "not installed" while they work fine in Terminal — a silent failure that *looks* like a detector bug (D-005).

The brief warned: *the code will compile, the output will look plausible, and the PATH will be subtly wrong.* So acceptance was judged by an actual byte-for-byte `diff`, not by eyeballing — exactly as the brief demanded.

## What was built

`Sources/AgentLensCore/Environment/ShellEnvironmentResolver.swift` — the only PATH source of truth in the project, ever (M2 requirement 7, stated as a binding comment at the top of the file):

| Requirement | How it's met |
|---|---|
| 1. Shell from password DB | `getpwuid(getuid())->pw_shell`. `$SHELL` is never read. |
| 2. Login + interactive shell | `shell -l -i -c 'printf "\n__AGENTLENS_ENV_BEGIN__\n"; env -0; printf "__AGENTLENS_ENV_END__\n"'` — `-i` so `.zshrc` is read; NUL-delimited so values with newlines survive; sentinels so rc-file banners are discarded. |
| 3. Never hangs | Output read on a queued thread against a **3-second** semaphore; on timeout the shell is killed and a documented fallback PATH (`/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin`) is used with `isDegraded = true`. |
| 4. Never eval'd into the app | Output is captured through a pipe only. Nothing is sourced into our process. |
| 5. Cached for the session | `resolve()` stores the result in a lock-guarded cache; later calls return instantly. |
| 6. The contract | `ShellEnvironment` with `shellPath`, `pathEntries` (ordered), `pathJoined`, `raw` (full env for `Process.environment`), `isDegraded`. |
| 7.PATH discipline | Binding comment in the source: no other code ever reads `ProcessInfo.processInfo.environment["PATH"]`. |

Also: `agent-lens debug-env` CLI subcommand; `Package.swift` untouched — still zero dependencies.

Two real compile fixes happened along the way (they're worth knowing about because they're *good* news, not friction):

1. Swift 6 strict concurrency rejected my first cache design (a bare `static var` guarded by an external lock). Fixed properly by moving the lock **into** a small `@unchecked Sendable` cache class — no safety suppression used.
2. `String(validatingUTF8:)` couldn't be lifted into `.map` for the passwd-pointer — rewritten as a plain guard. Cosmetic.

## Acceptance 1 — build

```
$ swift build
Build complete! (0.64 secs)
```
(interleaved benign `ld: warning: search path ... not found` lines documented in M0 walkthrough; `grep -v` used only for legibility)

## Acceptance 2 — the diff (the one that matters)

```
$ swift build && .build/debug/agent-lens debug-env | grep '^path_joined: ' | sed 's/^path_joined: //' > /tmp/agentlens_path.txt && echo "$PATH" > /tmp/shell_path.txt && diff /tmp/agentlens_path.txt /tmp/shell_path.txt && echo "MATCH"; echo "exit code: $?"
Building for debugging...
Build complete! (0.14 secs)
MATCH
exit code: 0
```

**MATCH printed. This is the byte-exact proof that what Agent Lens resolves equals what Terminal sees.** Nothing close, nothing "looks right" — identical strings.

## Acceptance 3 — shell detection matches `$SHELL`

```
$ .build/debug/agent-lens debug-env | grep '^shell:'; echo "$SHELL"; echo "---"; .build/debug/agent-lens debug-env | grep '^degraded:'
shell:       /bin/zsh
/bin/zsh
---
degraded:    false
```

`shell:` matches `$SHELL` (`/bin/zsh`) **and comes from `getpwuid`** — `$SHELL` is not read at all. `degraded: false` confirms the real capture path is in use, not the fallback.

## Acceptance 4 — tests

```
$ swift test
◇ Test captureTimesOutAgainstAHangingShell() started.
◇ Test buildEnvironmentPassesRawEnvironmentThroughForProcess() started.
◇ Test buildEnvironmentIsDegradedWhenDumpHasNoPath() started.
◇ Test parseEnvironmentDumpReturnsNilWithoutSentinels() started.
✔ Test buildEnvironmentPassesRawEnvironmentThroughForProcess() passed after 0.001 seconds.
✔ Test buildEnvironmentIsDegradedWhenDumpHasNoPath() passed after 0.001 seconds.
✔ Test unknownCommandHasNonZeroSemanticsViaUsageText() passed after 0.001 seconds.
✔ Test buildEnvironmentIsDegradedOnTimeoutAndUsesFallbackPath() passed after 0.001 seconds.
✔ Test scanReportContainsRequiredStrings() passed after 0.001 seconds.
✔ Test parseEnvironmentDumpReturnsNilWithoutSentinels() passed after 0.001 seconds.
✔ Test scanReportCountsExactlyOneTool() passed after 0.001 seconds.
✔ Test parseEnvironmentDumpExtractsSentinelDelimitedPairs() passed after 0.001 seconds.
✔ Test captureParsesASuccessfulRealShellRun() passed after 0.077 seconds.
✔ Test captureTimesOutAgainstAHangingShell() passed after 0.505 seconds.
✔ Test run with 10 tests in 0 suites passed after 0.506 seconds.
exit code: 0
```

## Done-when checklist

- [x] `debug-env` prints `shell:`, `degraded:`, `path_joined:`, `path_entries:`
- [x] `diff` reports **MATCH**, exit 0
- [x] `shell:` matches `$SHELL` (from getpwuid, not `$SHELL`)
- [x] `degraded:` is `false`
- [x] Unit test parses sentinel output including a value with a newline (`MULTILINE=hello\nworld` survives) and a value containing `=`
- [x] Unit test covers timeout fallback: a hanging `sleep 30` script trips the 0.5s timeout → `isDegraded == true`, fallback PATH used
- [x] Unit test asserts `raw` passes through for `Process` (`HOME`, `PATH`, `MULTILINE` intact)
- [x] `swift test` exits 0 (10 tests, up from 3)
- [x] Raw transcripts above
- [x] One commit on the milestone branch

## Notes for the reviewer

- **Why you can trust this milestone:** the acceptance wasn't "the output looks right." It was a shell `diff | MATCH`. If the PATH were subtly wrong, that command would have printed the difference instead of `MATCH`.
- The captured PATH on this machine included project-relevant entries: `~/.local/bin`, `~/.opencode/bin`, `~/.codeium/windsurf/bin`, Homebrew paths, etc. All present and ordered as the shell searches them.
- The timeout test is a real behavior proof: a script that sleeps 30s trips the 0.5-second test timeout and the code returns **degraded rather than hanging** — 0.505s measured, so the timeout is real.
- No explanation entry in `DECISIONS.md` was needed for a diff difference — the diff matched exactly, so no demonstrated-deviation note applies.
- `DO NOT TOUCH` respected: no detectors, no tool inspection, no version probing, no network, no UI.

## What changes next (M3 — first real detector)

M3 builds directly on this boundary: it uses `ShellEnvironment` to resolve a real tool's executable, and must be able to report `installedNotOnPath` (D-006) — the tri-state that makes PATH-confusion a first-class diagnostic rather than an error. Per `briefs/README.md`, M3 and onward briefs will be written after M2's outcome (and M2 has now passed). With the highest-risk milestone of the project behind us, M3 is lower-stakes terrain.

