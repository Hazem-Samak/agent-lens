# M10-C R1 — prerequisite baseline repair

Status: diagnosis/repair authorized by the owner on 2026-11-02 after the mandatory preflight failed. This is a separate prerequisite phase, not M10-C Update acceptance. The frozen `M10-C-npm-update.md` remains unchanged.

## Baseline and roles

- Branch: `codex/m10-npm-management`; starting commit `7ff71b67a665d405fe163b7908b8336d5b45e51e`, including accepted M10-B `72ffb1e`.
- Preserve the existing untracked `.workbuddy-ai/memory/2026-10-28.md`.
- Sole writer: Pi, provider `river`, model `deepseek-ai/DeepSeek-V4.1-Flash-1017`, thinking `max` (observed in the live session).
- Independent read-only reviewers: Perch `glm-5.3-flash-starter`, effort `max`; Qoder `Qwen3.8-Max`, reasoning `xhigh` (observed as Extra High).
- Coordinator owns this brief, gate adjudication, and independent verification. No subagents, Git delivery, publication, dependency installation, toolchain changes, or personal-installation mutation.

## Observed problem

The unchanged full baseline failed twice with 397 Core tests reporting 61 issues; 71 AppSupport tests passed. CLI integration fixtures time out during login-shell capture and fall back to the real home/off-PATH inventory rather than their synthetic fixture. The separate login-shell portability control hits its 120-second watchdog.

A native recheck additionally encountered the documented local missing TestingMacros plugin before tests ran. A fresh scratch full run using the already permitted local macro fallback reproduced the original 61 runtime issues. Macro discovery and runtime fixture failure are separate facts.

Exact profile, minimal/full environment, pipe/file capture, Foundation Process probes, CLI-file subsets, and the exact 298-test prefix through the first failing CLI case pass. No root cause has been established. Do not classify this as a proven FD, orphan, shell-profile, or sandbox defect based on those observations alone.

Parent raw receipts are beneath `/private/tmp/agent-lens-m10c-acceptance.TcBGo0/parent`: `preflight-recheck.json`, `suite-recheck.stdout`, `suite-recheck.stderr`, `preflight-fallback.json`, `suite-fallback.stdout`, and `suite-fallback.stderr`. Worker subset/probe receipts share that evidence root. Original terminal capture is bounded/incomplete; do not call it a complete raw transcript.

Other baseline gates passed: Core/UI guard, 21 guard fixtures, Swift build, fresh development-app builder, and 9 packaging checks. Public npm metadata for Codex 0.165.0 and latest 0.166.0 was reachable; no package was installed.

## Goal and authority

Identify and correct the underlying reproducible baseline cause without hiding it. First compare the failing coordinator full-run launch context with the passing worker prefix/subset context using only non-secret selected context fields, executable/product identities, FD/process state, and reproducible commands. Never dump raw environments or credentials.

Read any relevant source. Before editing, return the minimal reproduction, causal evidence, exact proposed files/change, and regression/verification plan to the coordinator. The coordinator must approve that bounded implementation slice. No source file is pre-authorized for speculative edits.

Potential correction must remain limited to the proven test-harness/process/environment defect. Product npm Update/Uninstall implementation, detector/catalogue changes, package dependencies, CI relaxation, deadline increases, skipped tests, forced TMPDIR, hidden retries, cache/config mutation, and arbitrary target splitting are excluded. Do not isolate the failing tests into another target/process merely to hide corruption. A legitimate isolation requirement must itself be demonstrated and reviewed.

External disposable diagnostic scripts and raw receipts may be created only under the owned evidence root. Record owned process IDs, enforce bounded timeouts, and terminate/reap only owned process groups. Never stop unrelated processes or restart Herdr/system services.

### Approved implementation slice — terminal job-control correction

The later actual CLI PTY/no-TTY differential and exact-runner PTY probe established the causal defect: interactive zsh in the runner's new background process group retains the controlling terminal and stops on SIGTTOU (22). The exact spawn/file-action probe shows that `+m` disables job control and avoids the stop while preserving the existing process group and cleanup. The earlier Python flags probe was not an exact runner reproduction; its differing result remains recorded. No BoundedProcessRunner/session-detachment change is needed.

Approved writer paths:

- `Sources/AgentLensCore/Environment/ShellEnvironmentResolver.swift`: disable shell job control with literal `+m` before `-c`, preserving login and interactive startup, capture bounds, fallback policy, and raw environment handling. Verify supported zsh/bash behavior.
- `Tests/AgentLensCoreTests/ShellEnvironmentResolverTests.swift`: first add a failing PTY regression at the production capture/environment-resolution seam using owned fixture HOME/ZDOTDIR/PATH. Prove exact captured fixture PATH and non-degraded status, then apply the fix and prove green. Use existing scratch/product/compiler patterns; no shipped helper or new dependency.
- `Tests/AgentLensCoreTests/UpdateCLIIntegrationTests.swift`: add `+m` to the existing direct-shell portability control, which independently reproduces the same SIGTTOU stop outside the production seam. Keep exact PATH assertions and both shell-family cases.
- `README.md`: document the terminal-safe login-shell capture behavior after smoke proof.
- New `walkthroughs/M10-C-R1-baseline-repair.md`: record causal evidence, red/green results, exact candidate, all gates, and limits.

No other product/test/build/CI files are authorized. In particular, do not change `BoundedProcessRunner`, `Package.swift`, deadlines, assertions, or test-process topology. A newly demonstrated requirement outside this slice returns to the coordinator before editing.

Acceptance includes full suites with and without a controlling PTY, preserving all existing 468 tests plus the meaningful regression; actual CLI `debug-env` under a controlling terminal must capture the fixture PATH without degradation. Test helpers must be bounded and must not introduce deadlock or orphan risks.

### Repair-review authorization amendment

Perch's `glm-5.3-flash-starter` session reached its five-hour Starter quota while inspecting the frozen repair candidate, before returning a verdict. Its earlier static diagnosis is supplemental, not approval. The owner explicitly selected **Qoder-only repair verdict**: for this narrow prerequisite repair only, Qoder's independent verdict plus coordinator verification may satisfy acceptance. The original two-reviewer requirement remains in force for M10-C product implementation. No provider/model/effort substitution or quota bypass is authorized.

## Verification and handoff

- Capture each command, working directory, start/end time, exit, and separate stdout/stderr directly to files; do not rely on terminal scrollback for long receipts.
- A targeted pass never substitutes for the full baseline. A failed attempt remains recorded even if a later attempt passes.
- Preserve inherited TMPDIR; unset Agent Lens test scratch/products overrides for default gates.
- The invocation-local TestingMacros fallback is permitted only after recording native non-discovery, exactly as documented in M10-A. It certifies local behavior only, never native hosted CI.
- The fix must explain a failing-before/passing-after signal and add a permanent regression only if it catches plausible consumer-visible behavior or a real process/fixture safety invariant, not source text or wiring.
- Return the candidate uncommitted with exact touched paths/hashes and stop writing. Both selected reviewers inspect the same frozen candidate independently, read-only. Return defects to River.
- Coordinator independently runs full Swift suite (all existing 468 cases, zero skips/failures), guard plus all 21 fixtures, fresh app builder, all 9 packaging tests, and the minimal runtime reproduction after repair. Preserve exact test inventory, not exit zero alone.
- Update README verification guidance only if the demonstrated correction changes the supported procedure; record repair evidence in `walkthroughs/M10-C-R1-baseline-repair.md` after smoke proof. Do not edit historical evidence or the frozen M10-C brief.
- M10-C product dispatch remains blocked until this prerequisite receives independent acceptance. Git/hosted CI, UI approval, and publication require their existing separate authorizations.
