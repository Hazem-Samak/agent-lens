# M10-C — authorized implementation dispatch

Status: owner authorized product implementation on 2026-11-02 and selected the workers below. This addendum resolves the frozen brief's historical planning-only header and updates the content baseline after separately accepted R1. It does not weaken or replace the frozen behavioral contract, allow-list, or AC01–AC14.

## Source of authority

Implement `briefs/M10-C-npm-update.md` in full, including every safety contract, native/controlled/public fixture recipe, and acceptance row. Do not read the full scope document. R1 was a separate prerequisite: see `walkthroughs/M10-C-R1-baseline-repair.md`. No M10-D, broader catalogue, manager, release, dependency, or CLI-mutation work.

## Pinned starting state

- Single branch: `codex/m10-npm-management`.
- Commit: `7ff71b67a665d405fe163b7908b8336d5b45e51e`, including accepted M10-B `72ffb1e`.
- The working baseline additionally includes accepted, uncommitted R1 changes. No Git delivery has been authorized. Preserve them as the starting content, not M10-C changes:
  - `Sources/AgentLensCore/Environment/ShellEnvironmentResolver.swift`: `e4154a6fb136b389f7f507346e05cbd466a57b0ef936e3ab611c14f7a0cf6284`.
  - `Tests/AgentLensCoreTests/ShellEnvironmentResolverTests.swift`: `dd89a82201fbecc54fab66cfbb52ab1263cae7f13ef3290a2b7be362d279c945`.
  - `Tests/AgentLensCoreTests/UpdateCLIIntegrationTests.swift`: `8cb44582314a73ec32589b8f846f91844f487dc85bc479e93e715d486bbc274f`.
  - README R1 content before M10-C: `b29f4f2546e4439a0e532625140591c2479098a40c85d095b66411a5aedd5c7d`.
- Preserve coordinator-owned R1 brief, acceptance walkthrough/review evidence, this dispatch, all historical records, and `.workbuddy-ai/memory/2026-10-28.md`.
- Record a complete initial input/protected-path manifest before product edits so the accepted uncommitted baseline and coordinator documents are distinguishable from new work. Never reset, stage, commit, push, merge, open a PR, or publish.

## Selected workers and orchestration

- Sole product writer: River through Pi, provider `river`, exact model `deepseek-ai/DeepSeek-V4.1-Flash-1017`, thinking `max`.
- Independent read-only reviewers: Perch `glm-5.3-flash-starter`, effort `max`; Qoder `Qwen3.8-Max`, reasoning `xhigh` (Extra High).
- Use existing interactive Herdr workers, not native subagents, relay scripts, one-shot print modes, alternative providers, or downgraded efforts. No worker launches further agents.
- Perch hit its Starter five-hour quota during the R1 review. The owner waived its verdict **only for R1**. M10-C still needs both selected reviewers; do not silently waive, substitute, or bypass the quota. Product implementation may proceed while the review slot is unavailable, but combined acceptance cannot.
- Coordinator handles brief amendments, technical adjudication, independent acceptance, and status documentation; revisions return to River. Reviewers do not edit.

## Verified preflight and changed counts

The R1 baseline now passes all **469** Swift tests (398 Core, 71 AppSupport) under both controlling-PTY and detached contexts, with exact started/passed-event accounting, no missing old names, and exactly one added PTY regression. Both writer and coordinator observed full passing runs. Guard plus all 21 fixtures, fresh development-app builder, all nine packaging checks, and actual terminal-attached CLI `debug-env` passed independently. Native TestingMacros non-discovery was separately recorded; the already authorized invocation-local fallback was used for local suite gates. Native hosted discovery is not claimed.

Consequently every frozen-brief reference to the pre-existing 468 tests means **all 469 accepted starting tests plus M10-C additions** for this dispatch. No count floor is lowered and no CI source is changed. Run suites sequentially, with inherited TMPDIR and both Agent Lens overrides unset for default gates; also preserve the accepted terminal-context regression.

Tools observed before dispatch: Swift 6.4, Node v22.23.2, npm 10.9.8. Public metadata/tarball coordinates for Codex old stable 0.165.0 and latest stable 0.166.0 were reachable with private owned npm scratch; no personal installation was mutated. Re-observe fresh targets for actual acceptance, never assume these values are still current.

Evidence base: `/private/tmp/agent-lens-m10c-acceptance.TcBGo0`. R1 receipts already live under `parent`; do not overwrite/adopt them. Create a new uniquely named M10-C product child beneath this operator-authorized base with separate worker/parent/fixture roots and record ownership. Preserve R1 receipts. The fixture must begin from a real old package in a disposable prefix, never a personal install or bare directory.

## Execution and handoff

Use only the frozen M10-C section 5 file authority. The R1 source/test paths above are protected starting state and are not additional M10-C edit authority. README is explicitly in M10-C authority; preserve R1 guidance when updating it.

Do not run full builds/tests/formatters while edits are in flight; run one integration verification phase after the bounded implementation is complete, then diagnose any failure with focused reruns. Keep a meaningful red-before/green-after regression only for uncertain consumer-visible boundaries; never test copied argv/wiring/source text or pin incidental wording.

Before mutation acceptance, prove fixture isolation and exact command routing; never touch personal caches, npmrc, installed packages, shell startup files, or credentials. No hidden retry, shell interpolation, privilege escalation, script-policy override, rollback claim, or process orphan. Exercise the actual native app and distinguish controlled-host evidence from ordinary public-npm app evidence exactly as the frozen brief requires.

At handoff stop writes and return touched paths/hashes, exact binaries/modules, complete secret-free receipts, AC01–AC14 matrix with accurate blockers, native screenshots/interaction evidence, protected-path manifest comparison, and owned process/scratch cleanup evidence. No implementation stub, placeholder, simulated production fallback, or false completion. Hosted exact-SHA CI requires separate Git authorization; request it only once the local candidate/reviews justify delivery, not as a hidden prerequisite bypass.
