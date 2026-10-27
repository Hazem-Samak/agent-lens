# M10-B authorized implementation dispatch

Date: 2026-10-27. User instruction: “implement !”. This authorizes M10-B implementation and coordinator verification under the frozen brief, not Git delivery/main integration/release or M10-C/D. The selected implementer and fallback are in [the selection supplement](M10-B-implementer-selection.md).

Read the complete [frozen brief](M10-B-npm-latest.md), SHA256 `1270cb3dc660195c71e67977f6bbab883e9b0dcbb730e34c484f4c424ec0c35c`. This dispatch supplies readiness facts/commands without altering the frozen product contract or file authority.

## Baseline and evidence ownership

- Checkout: `/Users/corvette/Documents/Projects Coding/Agent Lens`, branch `codex/m10-npm-management`, HEAD `b667be6a177d42f26def815e9acd6f801aa6d52c`.
- Evidence E: `/private/tmp/agent-lens-m10b-implementation-9jaujmja`. Worker owns only E/worker and future newly named scratch children; coordinator owns E/parent. Shared prepared fixture E/fixture is immutable except through explicitly recorded acceptance scenario changes to that owned fixture. Never clean E itself or the repository.
- Pre-existing working changes: README.md/ROADMAP.md/briefs/README.md documentation corrections; frozen M10-B brief, selection and planning record/evidence are untracked. This dispatch is coordinator-owned. Preserve all of them. README is worker-allowed for M10-B usage updates, but retain the already authorized corrections and freeze links. Do not commit, stash, reset, clean, push, merge or publish.
- Baseline manifest: E/parent/baseline-manifest.json; context E/context.json. Source/resources/tests/package/build/workflow match HEAD. Recheck status and frozen hash before edits.
- T3 primary: `pi`, `openrouter/nvidia/nemotron-3.5-super-vl:free`, advertised default thinking=medium. Provider default is selected, not an imported council effort. Fallback only for actual primary issues/quota: `pi`, `workbuddy/deepseek-v4.1-flash`; coordinator records failure/stops primary before handing off. No simultaneous writer or self-delegation.

## Coordinator baseline gates actually run

Raw argv/stdout/stderr/exit/elapsed receipts are E/parent/<name>/:

- core-ui: PASS; guard-fixtures: PASS21.
- fresh `swift build --scratch-path E/parent/baseline-products`: PASS.
- native-tests: FAIL before execution due known local TestingMacros discovery; retained, not relabeled PASS.
- local-macro-fallback-tests: PASS335 Core +71 AppSupport =406, no failed events. Exact allowed invocation: `swift test --scratch-path E/parent/baseline-explicit-products --build-system swiftbuild -Xswiftc -load-plugin-library -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib --no-parallel`. Ordinary TMPDIR inherited; both Agent Lens test overrides unset. This is local-only fallback, never a hosted-CI exemption.
- fresh debug-builder and original packaging: PASS9. Baseline app E/parent/baseline-app/AgentLensApp-debug.app.

Use separate fresh E/worker products/app roots for your final gates. Do not run timing-sensitive suites concurrently with another suite/build. Preserve failures and exact commands. No count-floor weakening or skip.

## Prepared real fixture and recipe

Coordinator constructed a dependency-free local tarball declaring `@openai/codex` version1.0.0 with one shell bin and no lifecycle scripts. Real npm installed it **offline** with `--ignore-scripts --no-audit --no-fund --package-lock=false --global --prefix E/fixture/npm-prefix E/fixture/fixture-package.tgz`; only the owned prefix changed. E/parent/fixture-install.json retains raw result. Prefix/root queries and fixture bin version all PASS. No personal package installation changed.

- Fixture environment: E/fixture/environment.json, synthetic HOME/user/global configs/prefix/cache, closed fixture PATH plus /usr/bin:/bin and manager/node symlinks to the already installed npm10/Node22. Do not import the live login-shell PATH. Native injected registry E/fixture/registry.json is validated through Core, contains only Codex, and clears extraSearchRoots; shipping registry remains untouched.
- Unrelated sentinel: E/fixture/unrelated-prefix/sentinel.json; preserve hash/content.
- Actual CLI: E/parent/baseline-products/out/Products/Debug/agent-lens. Its fixture home has synthetic .zshenv/.zshrc/.zprofile/.profile; pass ZDOTDIR to that home. Use the generated E/fixture/cli-isolation.sb with `/usr/bin/sandbox-exec -p <profile> <current-build-cli> ...`. Deny physical personal AgentLens/npm caches and known off-PATH tool roots; never remove these denials to make a test pass. Current preflight E/parent/fixture-cli-isolated-offline.json passed with fixture versions only. Baseline explicit verify-installation codex proved real npm ownership of the fixture (E/parent/fixture-cli-ownership.json).
- Earlier E/parent/fixture-cli-offline.json was insufficient isolation: fixed shipping off-PATH roots exposed read-only real OpenCode/Grok version observations despite synthetic HOME. It is retained as a preparation failure, not acceptance. The corrected sandbox and fixture PATH executables close that path. Do not assert that synthetic HOME alone isolates the app.
- Controlled registry recipe: `python3 E/fixture/registry-server.py --probe` starts an owned loopback server, runs real npm against it and shuts down. Recorded latest2.0.0 with next3.0.0-beta.1 proves latest-tag shape; E/parent/controlled-registry-readiness.json PASS. For acceptance, run the same script without --probe in an owned bounded process, capture its PID, read E/fixture/registry-url.txt, and stop/join that exact server after the scenario. No server is currently left running.

## Native and Core/CLI observation recipe

The external native host E/native/FixtureHost.swift compiles the unchanged product view files (all Sources/AgentLensApp/*.swift except AgentLensApp.swift) and links current Core/AppSupport objects. It injects SessionEnvironmentSource, validated fixture registry/cache/currentDirectory and the existing runner seam through MainWindow(service:). No product debug switch or custom-registry policy is needed. The baseline compile succeeded; raw exact swiftc argv is E/parent/native-host-build.json. Re-run that recipe with your **fresh current candidate** Products/Debug modules/objects, never baseline objects. It may need ordinary external harness maintenance for the new optional scratch seam; it must not alter/replace product views.

E/native/FixtureHost.swift's injected runner asserts original public base/scope flags, records original/executed argv and substitutes only those metadata registry flags to the one owned loopback endpoint when executing real npm. Config/ownership queries use real captured fixture settings unchanged. Native receipts append E/fixture/native-query-receipts.jsonl. This is controlled transport proof, not a production custom-registry feature or public-network observation. For CLI contract/state scenarios use the brief's current-build sandbox fixtures and an external Core driver using the same production coordinator with validated definitions/environment and this runner; distinguish an external Core driver from the actual shipping CLI. Real current CLI Check/Refresh must also exercise the shipping path without an internal URL switch (public read-only metadata is allowed from the isolated prefix with real-cache denial); because the fixture version1.0.0 and public latest may order differently, assert the actual observed comparison rather than fabricate fixture latest there.

Launch controlled host only with the owned server alive, interact with actual product Check/Refresh/Rescan/cancel/selection flows, capture evidence and close its window/process. Coordinator independently observes native behavior after handoff. Ordinary built-app local-only startup is a distinct gate; no metadata/manager request on launch. Do not present a host screenshot as an ordinary-app fixture flow.

## Submission and stop

Implement only the frozen allow-list and requirements, no placeholders. Return exact candidate files/hashes, full requirements-to-evidence matrix, raw gates and runtime receipts, warnings/limits and process/fixture cleanup. Your walkthrough must distinguish worker-run evidence from coordinator acceptance; do not declare your own work technically accepted. Stop editing on handoff. If a needed file/interface change lies outside authority, report the exact need; do not silently broaden scope. No subagents, commit/push/PR/main/release, personal-tool mutation or M10-C/D work.

## Authorized fallback activation — OpenRouter daily quota

The primary T3 Pi Nemotron run failed with HTTP429, `openrouter_free_tier_daily`, limit50/remaining0, reset1793145600000. No credits were purchased and no quota retry was attempted. The coordinator read the failed result and cancelled the primary task before starting fallback. Raw result: E/parent/nemotron-quota-failure.json.

Nemotron left a partial, untested candidate in six allowed product files: Ownership/NpmOwnershipProbe.swift and Updates/{UpdateProbeCoordinator,UpdateScanRenderer,VersionStatus,NpmUpdateMetadataCache,NpmUpdateProbe}.swift. There are no worker test/build receipts or accepted results. Its last reported action was inspecting diagnostic types needed to compile the new probe. The coordinator preserved exact copies, SHA256 manifest and tracked diff under E/parent/nemotron-partial/. This snapshot is recovery evidence, not acceptance.

The user-authorized fallback is now `pi` / `workbuddy/deepseek-v4.1-flash`. It must inspect and finish the current candidate, retaining the frozen contract, all coordinator-owned documentation/evidence and the current branch. Do not mistake the River council model for WorkBuddy. Use a fresh E/worker/workbuddy subtree for evidence; primary E/worker is empty. No concurrent implementer remains.

## Fallback provider failure — awaiting replacement route

WorkBuddy Pi failed before making product changes with HTTP403, upstream code11140 (`request illegal`), and provider message “Your account has been restricted due to unusual activity”; requestId `01a17d71b20d7e43b534cb40ae10a0b9`. The coordinator read and stopped that failed task. Raw result: E/parent/workbuddy-provider-failure.json. Snapshot/hash comparison in E/parent/after-workbuddy-failure confirms all six partial product files are byte-identical to the retained Nemotron snapshot; no new fallback tests/builds ran.

Both explicitly authorized routes are unavailable. No replacement implementer was selected automatically, no account appeal was sent, no credits purchased and no extra provider retry started. Implementation is incomplete and unaccepted; the frozen brief remains unchanged. A new user-selected route or restored selected-provider availability is needed to resume. The current partial candidate and recovery evidence remain intact on the existing M10 branch.

## Replacement activation — Qwen3.8-Flash / Qoder

After both authorized Pi routes failed, the user selected Qwen3.8-Flash through Qoder, maximum effort available. Verified T3 route: `acpRegistry_qoder_cli` / `qfmodel`; no effort control exists in its catalog, so the prompt requests maximum-effort reasoning and does not claim a configured effort setting. Both prior tasks are stopped. The six-file partial candidate still matches the Nemotron recovery hashes. Continue from that candidate under the frozen brief, using E/worker/qoder-flash for new evidence. No new baseline run or product acceptance is inferred from the provider switch. This authorization does not use the expensive Qwen Max reviewer or grant Git delivery.

## Qoder R1 transport interruption

The first correction run failed with “SSE message timeout: no data for60s”. It was stopped before a same-route continuation. All12 candidate1 product/test hashes remain unchanged; no R1 evidence directory, edits or new gate results were produced. Raw failed result E/parent/qoder-r1-sse-timeout.json. Resume the selected Qwen3.8-Flash route with a bounded R01–R04 correction batch first; R05–R08 remain outstanding and no phase acceptance is implied by the smaller checkpoint.
