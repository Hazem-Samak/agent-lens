# M10-C R1 — baseline repair

Status: locally technically accepted by the coordinator on 2026-11-02 after Qoder's final independent PASS and final frozen-candidate verification. Uncommitted; no hosted CI or Git delivery is claimed.

- Branch: `codex/m10-npm-management`
- Starting commit: `7ff71b67a665d405fe163b7908b8336d5b45e51e`
- Implementer: River Pi, provider `river`, model `deepseek-ai/DeepSeek-V4.1-Flash-1017`, thinking `max`
- Scope: prerequisite baseline repair only. This acceptance clears the baseline blocker for separately authorized M10-C Update implementation; it does not accept M10-C or M10 as a whole.

## Observed failure

The unchanged full baseline failed twice with 397 Core tests / 61 issues; 71 AppSupport tests passed.
CLI integration fixtures timed out during login-shell capture, fell back to the real-home/off-PATH
inventory, and the direct login-shell portability control hit its 120-second watchdog.

## Causal finding

The failing coordinator full run was launched from a live PTY (`t1n` was `/bin/zsh -l` on
`/dev/ttys007`). Worker subset probes had non-TTY stdin/stdout and passed. Reproducing the actual
product under a PTY reproduced the failure:

- No TTY: `agent-lens debug-env` returned `degraded=false` and the exact fixture PATH.
- PTY: the same binary returned `degraded=true` and the fallback PATH.
- Live process sample: `agent-lens` was in the foreground process group (`S+`), while its
  `/bin/zsh -l -i -c` child was in its own process group and stopped (`T`) on the same terminal.

An external exact-runner probe replicated `BoundedProcessRunner`'s `posix_spawn` setup (new process
group, stdin `/dev/null`, captured stdout, inherited controlling terminal):

| PTY variant | Result |
|---|---|
| zsh baseline `-l -i -c` | stopped with `SIGTTOU`; no output; group cleaned |
| zsh `-l -i +m -c` | exit 0; exact fixture PATH; group cleaned |
| zsh `SETSID` only | exit 0; exact fixture PATH; group cleaned |
| zsh `SETPGROUP | SETSID` | spawn failed; not a valid combination |
| bash baseline / `+m` / `SETSID` only | all passed |

`MONITOR` is the zsh job-control option (documented as enabled by default in interactive shells);
`+m` disables it for this noninteractive probe while preserving `-l -i` startup and rc-file loading.
The same flag is accepted by the installed bash and `/bin/sh`. `POSIX_SPAWN_SETSID` is public in
Darwin `sys/spawn.h` and typechecks at the macOS 14 deployment target, but it is broader and was not
needed.

## Repair

- `Sources/AgentLensCore/Environment/ShellEnvironmentResolver.swift`: capture arguments now use
  `-l -i +m -c <script>`. No foreground-terminal takeover, signal change, or `BoundedProcessRunner`
  behavior change.
- `Tests/AgentLensCoreTests/ShellEnvironmentResolverTests.swift`: added
  `ptyProductionCaptureUsesFixturePathForSupportedLoginShells`. It compiles a scratch helper using
  the existing `agentLensCoreProducts()` / `agentLensCoreCompileArguments` pattern and runs it through
  `/usr/bin/script`, so the **production** resolver is exercised with a controlling terminal for both
  zsh and bash. Assertions normalize CRLF, require the tty premise, require the positive full line
  `degraded=false`, and require the exact full line `path=<expectedPath>` rather than a substring;
  a throwaway check also demonstrates that a suffixed PATH line is rejected. No fork in the Swift
  test process, no shipped helper, no dependency.
- `Tests/AgentLensCoreTests/UpdateCLIIntegrationTests.swift`: the existing direct login-shell portability
  control now adds `+m` to its direct zsh/bash argv. That control is deliberately outside the production
  seam; it independently stopped on `SIGTTOU` under a PTY and must be terminal-safe as well.
- `README.md`: verification guidance records the terminal/PTY regression and the production capture
  semantics.

## Red / green evidence

Under the owned evidence root `/private/tmp/agent-lens-m10c-acceptance.TcBGo0/parent`:

- `r1-red3-pty-production-seam.stdout/.stderr/.json`: clean red before the source change. zsh reported
  `degraded=true` and fallback PATH; bash passed. 1 test failed with 2 issues.
- `r1-green-pty-production-seam.stdout/.stderr/.json`: green after the change. 1 test passed in
  0.878s.
- Earlier red attempts retained: `r1-red-pty-production-seam.*` (test raw-string compile error) and
  `r1-red2-pty-production-seam.*` (red with an incorrect helper `tty=true` assertion). Neither is
  accepted as the final red; both remain recorded.

The exact-runner evidence is in
`exact-runner-71b3323a-1163-4259-9dcf-38ac644367cd/results.json`; the external source and binary are
`exact_runner_probe.c` and `exact_runner_probe` (SHA-256
`aafc782b5d053780832eb1879d375ad5de4b96b22f897c3fd17e4d2787897482`). The C probe was compiled
with `-mmacosx-version-min=14.0`; its `LC_BUILD_VERSION` records `minos 14.0`.

## Full verification

All commands ran sequentially, with raw stdout/stderr files beneath the same evidence root. Native
TestingMacros discovery failed before tests ran and that failure was recorded before the
invocation-local fallback was used. The fallback with `--build-system swiftbuild` is local toolchain
evidence; it does not certify native hosted discovery.

| Gate | Result |
|---|---|
| Core/UI guard | exit 0 |
| Guard fixtures | exit 0 |
| `swift build` (fallback scratch/flags) | exit 0 |
| Full suite, no TTY | **398 Core + 71 AppSupport passed**, 0 failures; 398 in 70.084s, 71 in 4.854s |
| Full suite, PTY (`/usr/bin/script`) | **398 Core + 71 AppSupport passed**, 0 failures; 398 in 65.481s, 71 in 4.488s |
| Fresh debug app builder | exit 0 |
| Packaging bundle checks | exit 0 |
| `git diff --check` | exit 0 |

`repair-gates.json` contains the exact argv, exit, elapsed time, and receipt paths. The PTY context
receipt shows fd0 is `/dev/ttys005`, `isatty=true`, with stdout/stderr files; `validDebugEnvironment`
and `loginShellFixture` both passed in the PTY full suite. A post-fix direct product probe at
`minimal-pty-84d7b7b8-f391-4644-b635-7d6885894716` ran `agent-lens debug-env` under both no-TTY and
PTY contexts: both exited 0 with `degraded=false` and the exact fixture PATH; the PTY run completed
in 0.092s. The pre-fix `minimal-pty-d2d3799b-9201-48fb-8afe-efef2e841af6` receipt remains recorded
with PTY `degraded=true`. Product identities:
`agent-lens` SHA-256 `3288c95aa8b146ec64b5dd297d88f23b89edb280e7255c9480989cbb9a177a2d`;
`AgentLensCoreTests` `9bfec7d26e2e800a794db15558bfc59de78c2278cd563b5dfd3374458fe0b380`;
`AgentLensAppSupportTests` `91822b3ee97535ce9091918160ed3aeadc7cf5e15776af4865a753508167dd7e`.

## Assertion revision re-run

After tightening the regression to parse complete CRLF-tolerant lines and require the positive
`degraded=false` line plus the exact `path=<expectedPath>` line, all checks were rerun sequentially:

- Targeted PTY regression: exit 0; 1 test passed in 0.963s.
- Full suite, no TTY: 398 Core + 71 AppSupport passed; 69.408s + 5.028s.
- Full suite, PTY: 398 Core + 71 AppSupport passed; 66.076s + 4.661s.
- `git diff --check`: exit 0.

Raw receipts: `rev-targeted-pty-regression.*`, `rev-suite-notty.*`, `rev-suite-pty.*`,
`rev-suite-pty.context.json`, `rev-checks.json`. The throwaway suffix check is
`assertion-exact-suffix-check.txt`; it shows that `path=<expectedPath>:extra` is not equal to the
required complete line.

## Touched paths (candidate)

| Path | SHA-256 |
|---|---|
| `Sources/AgentLensCore/Environment/ShellEnvironmentResolver.swift` | `e4154a6fb136b389f7f507346e05cbd466a57b0ef936e3ab611c14f7a0cf6284` |
| `Tests/AgentLensCoreTests/ShellEnvironmentResolverTests.swift` | `dd89a82201fbecc54fab66cfbb52ab1263cae7f13ef3290a2b7be362d279c945` |
| `Tests/AgentLensCoreTests/UpdateCLIIntegrationTests.swift` | `8cb44582314a73ec32589b8f846f91844f487dc85bc479e93e715d486bbc274f` |
| `README.md` | `b29f4f2546e4439a0e532625140591c2479098a40c85d095b66411a5aedd5c7d` |

This walkthrough's own hash is recorded in the handoff report because adding it here would change the value.

## Coordinator independent verification

The coordinator independently ran the candidate and recorded:

- **469 event identities in both TTY and detached contexts**, with no missing baseline names; the
  inventory records the one added PTY regression and matching inventories.
- Guard exit 0 with its 21 fixtures, packaging exit 0 with all nine checks, and the actual
  HC-terminal `agent-lens debug-env` showing non-degraded exact PATH behavior.
- Receipts: `coordinator-verification.json`, `coordinator-test-inventory.json`, and
  `coordinator-cli-tty.txt` beneath the owned evidence parent.
- Parent smoke binary under `coordinator-verification-products`.

## Remaining limitations

- Only zsh and bash were measured. `+m` is not verified for other passwd shells and may be rejected;
  the old `-l -i -c` form was also not universally verified, so this repair does not claim a proven
  new non-zsh/bash regression.
- The controlling TTY is retained. Shell rc files or grandchildren could still attempt terminal
  operations; the existing bounded capture timeout remains the safety bound.
- Verification is local macOS 27 only; hosted CI and native TestingMacros discovery are not claimed.
- The fix is intentionally limited to shell-environment capture. Other bounded runners are unchanged.
- The candidate is uncommitted. No Git delivery, publication, or M10-C product implementation is
  authorized by this repair.

## Coordinator acceptance — 2026-11-02

Qoder `Qwen3.8-Max`, Extra High (`xhigh`), independently reviewed the frozen candidate and returned final **PASS, no required corrections** after the assertion and limitation-note revision. The coordinator observed the model/effort in the live CLI and independently matched the handoff file hashes. The bounded final review terminal capture is retained in [review evidence](M10-C-R1-review-evidence/qoder-terminal.txt); it is not a complete session transcript.

Perch `glm-5.3-flash-starter`, effort `max`, reached its five-hour Starter quota before returning a candidate verdict. Its earlier static inspection is supplemental, not approval. The owner explicitly waived Perch's verdict **for this repair only**; this is not a two-reviewer consensus. M10-C product work retains the original two-reviewer requirement.

After the final assertion revision, the coordinator rebuilt and independently ran the targeted production-seam PTY regression: one test passed in 0.926 seconds. The coordinator then ran the full frozen suites sequentially in terminal-attached and detached contexts: **469 started / 469 passed in each**, no unpassed events, no missing baseline test names, and exactly the one added PTY regression. Final receipt files are `final-suites.json` and `final-test-inventory.json` under the owned evidence parent. Earlier full fresh-build verification, guard plus 21 fixtures, fresh app build, all nine packaging checks, and the actual Herdr-terminal CLI smoke remain applicable: the production implementation did not change during assertion strengthening.

The actual coordinator-built CLI under a controlling Herdr terminal returned exit 0, `degraded: false`, and exact fixture PATH `/usr/bin:/bin`, whereas the pinned pre-fix binary returned degraded fallback under the same fixture. The native macro-discovery attempt had failed with missing `TestingMacros` before the documented local fallback was used; this does not establish native hosted discovery.

Accepted source/test/README hashes are the candidate table above. This record adds acceptance documentation only. No install, Update/Uninstall operation, personal configuration/cache mutation, Git delivery, `main` integration, hosted CI, or release was performed. The next product phase remains the separately authorized frozen M10-C Update brief.
