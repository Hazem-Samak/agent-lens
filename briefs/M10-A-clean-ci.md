# M10-A — clean CI and default-TMPDIR fixture portability

Status: planning draft, revision 2, 2026-10-26 (Africa/Cairo), revised after the first council round. The user authorized this brief and a planning council, not product implementation or Git delivery. This document is not an acceptance report. Freeze the dispatched revision; later corrections receive numbered revision briefs.

## Identity, roles and prerequisite

- Phase M10-A, first phase of M10 (npm management). Proposed single milestone branch: `codex/m10-npm-management`; create it only when implementation is authorized. All M10 phases use that branch, in order.
- Inspected baseline: clean `main`, `0005dcf3eb0f7a0bb4416c10ffa181e99834d244`. Local `origin/main` matches; no fresh remote-ref equality is inferred. Recheck HEAD, status and prerequisite evidence before dispatch. Planning documents added after this baseline are orchestrator-owned inputs, not worker changes.
- M9 prerequisite is accepted and delivered. Its final record reports 329 Swift tests (258 Core, 71 AppSupport), nine packaging tests, native observations and user UI approval. These are historical results, not a fresh M10-A pass.
- Planning council selected by the user: Qwen 3.8 Flash Free through Qoder (`Qwen3.8-Flash`), and GLM 5.3 Flash Free through OpenCode (`opencode/glm-5.3-flash-free`). They review and report without edits. They are not assigned as implementers.
- Sole product implementer: not selected or authorized yet. Verify the user's chosen model/provider/CLI with a harmless route check before dispatch; no silent fallback. The orchestrator writes briefs, adjudicates findings and independently exercises the candidate; it does not implement product code/tests.
- Planning evidence root `R`: `/private/tmp/agent-lens-m10a-20261026-a9el6aow`. This root is disposable local evidence, not shipping input. Before implementation, create and record a new unique external evidence root `E`; never reuse existing build/output children. Parent and worker use separate subdirectories. Do not embed this machine's evidence path into CI.
- Local toolchain observed: Swift 6.4, arm64, CommandLineTools at `/Library/Developer/CommandLineTools`. Qoder 1.1.78 and OpenCode 2.1.4 returned the exact smoke response `COUNCIL_ROUTE_OK` on the selected routes. Qoder's catalog reports the model name without a pricing field; the user supplied the free-tier designation.
- Fresh unchanged-baseline diagnosis: the native targeted build exited 1 before executing tests (`TestingMacros` plugin not found). The documented local plugin fallback built successfully and executed the targeted isolation test under inherited `/var/folders/.../T/` with both overrides unset: one test failed with two issues, because the denied `touch` returned 0 and created the decoy. Raw records: `R/evidence/default-tmp-baseline/{command.json,stdout,stderr}` and `R/evidence/default-tmp-explicit/{command.json,stdout,stderr}`. This is measured failing-before evidence, not a full regression result or proof about the real cache.
- Further preparation changed the diagnosis: the same unchanged test also failed with `AGENT_LENS_TEST_SCRATCH=R/tmp`. Foundation returned `/tmp/...` for the existing `/private/tmp/...` path. Identical shell/`touch` profiles against an owned fixture allowed the write when their subpath used `/tmp/...`, and denied it when their subpath used physical `/private/tmp/...`. Direct physical-path read/write controls also denied both operations, with successful unsandboxed controls. Evidence: `R/evidence/explicit-scratch-control/`, `foundation-path-probe.json`, `alias-profile-comparison.json`, and `mechanism-probe.json` (the last three under `R/evidence`). This supports a pathname mismatch, not an established Darwin-temp sandbox exception. Do not transfer the earlier source comment's explanation into the fix.

## Outcome and scope

Deliver reliable, reproducible checks for the existing diagnostic app before any modifying npm operation is introduced: a clean hosted macOS job builds/tests the package, validates current detector-schema behavior, enforces the Core/UI boundary, builds the development app and runs packaging checks. The full existing fixture suite must work with the process's ordinary inherited TMPDIR and no Agent Lens scratch/products overrides.

No npm latest lookup, cache-policy/product changes, Update/Uninstall lifecycle or UI, new catalogue entries, package-manager commands against personal installations, dependency additions, signing/notarization, release, schedules, global toolchain/settings changes or M10-B work. Do not resolve unrelated compiler/linker warnings or alter historical milestone evidence. M8's unmeasured native keyboard activation remains a release blocker and is outside this phase.

## Relevant contracts and source context

- Swift tools version 6.0, minimum macOS 14, zero package dependencies. Core is UI-free (D-002); no `SwiftUI` or `AppKit` imports, including attributed, scoped and conditional imports. The CI guard is a source-boundary check, not a reason to add either framework to package dependencies.
- D-010/D-017: declarative JSON registry, currently schema 2. `DetectorRegistryTests`, `DetectorMetadataTests` and `VersionQuerySpecificationTests` cover validation, direct construction and bounded query behavior. Run these real tests; JSON parsing alone is not schema acceptance.
- D-013/D-014: one milestone branch, read-only reviewers, orchestrator-owned independent acceptance. A worker's successful command or council approval is evidence, not phase acceptance.
- `Tests/AgentLensCoreTests/UpdateCLIIntegrationTests.swift`: `cliScratch`, `denialProfile`, `runCLI`, `launchCLIWithFileCapture`, `builtAgentLensExecutable`, and `sandboxDeniesAllAccessToTheRealAgentLensCache` are the relevant seams. Fixtures use explicit `AGENT_LENS_TEST_SCRATCH`, otherwise inherited TMPDIR. Missing both fails closed. Paths are canonicalized before sandbox comparisons. The optional products override must fail loudly when invalid; implicit discovery must identify the executable from this run's products, never an old `.build` link or PATH.
- Both CLI launch seams install read/write denial for the actual Foundation-resolved Agent Lens cache. Synthetic HOME alone is insufficient on the measured local system. Retain a closed fixture PATH, synthetic shell files and fake Codex/OpenCode/Grok; do not merge in real login-shell PATH.
- The sandbox proof currently uses a scratch decoy, denied write plus identical unsandboxed successful control. The source comments' claim that Darwin temp is unenforceable is superseded by the narrower fresh pathname evidence above. Foundation's `resolvingSymlinksInPath()` is not sufficient proof of the physical pathname used by Seatbelt. Correct those comments as part of the test fix.
- Other Core/AppSupport scratch helpers already accept inherited TMPDIR. Do not consolidate or migrate them without a demonstrated phase requirement and revised authority. Keep test environment overrides invocation-local; no global process-environment mutation in concurrent tests.
- `scripts/build-dev-app.py` builds an unsigned app and rejects broad/protected/repository scratch roots. `Tests/Packaging/test_dev_app_bundle.py` validates the actual app, relocated resources under denial of original build paths, and malformed/missing-registry behavior. Preserve those guards and all nine existing checks.

## File authority

Allowed edits/additions after implementation authorization:

| Path | Allowed purpose |
|---|---|
| `.github/workflows/ci.yml` (new) | The required macOS CI workflow only |
| `scripts/check-core-ui-imports.py` (new) | Dependency-free executable Core import-boundary guard; optional explicit source-root argument for isolated fixtures |
| `Tests/Packaging/test_core_ui_imports.py` (new) | Focused behavioral fixtures for that guard, outside shipping source |
| `Tests/AgentLensCoreTests/UpdateCLIIntegrationTests.swift` | Default-TMPDIR isolation/control fix, mandatory truthful related comments, bounded owned cleanup, and current-build CLI discovery only if measured necessary |
| `Tests/AgentLensCoreTests/CLIFixtureIsolationTests.swift` (optional new) | Focused behavioral regressions for any extracted fixture seam; same test target, no package changes |
| `Tests/AgentLensCoreTests/CLIFixtureIsolation.swift` (optional new) | Small test-only seam shared by those integration/regression tests; no general fixture-framework rewrite |
| `README.md` | Accurate check commands, override/default behavior, supported CI environment and evidence limits |
| `walkthroughs/M10-A-implementation.md` (new) | Worker report, raw-evidence references and limitations, explicitly not independent acceptance |

DO NOT TOUCH: `Sources/**`, `Package.swift`, detector resources/schema, all other tests, the existing builder and packaging suite, `.gitignore`, decisions/scope/roadmap, this brief, other briefs, historical walkthroughs, personal cache/configuration/installed tools or credentials. Parent owns index/status updates and acceptance records. If the measured fix needs another file, stop with the exact path, reproduction and reason for a revised brief; do not weaken checks to fit this list.

## Requirements

### M10-A-R01 — safe temporary-directory portability

1. All existing CLI integration tests run with inherited default TMPDIR, `AGENT_LENS_TEST_SCRATCH` unset and `AGENT_LENS_TEST_PRODUCTS` unset. Do not solve this by forcing the whole suite into `/private/tmp`, setting a CI-wide TMPDIR override, skipping the isolation test or accepting sandbox startup failure as proof of denial.
2. Preserve explicit scratch override support and missing/empty-root fail-closed semantics. Any introduced scratch selection must validate scope before creation and exclusive ownership/mode of newly created children before removing content; canonicalize symlink aliases. An existing explicit base is allowed only as an operator-authorized base for unique new owned children, never as a cleanup target. No fallback to HOME, repository or installed-manager roots.
3. Keep the mechanism-control decoy under the same selected root as the ordinary CLI fixtures, including inherited default TMPDIR. Resolve the existing owned path to its physical filesystem pathname for the sandbox profile using a test-only POSIX `realpath` or equivalent measured resolver; do not hardcode a `/private` prefix or assume Foundation's path spelling is physical. Keep human/display spelling separate where necessary. Resolve existing parents when constructing a nonexistent leaf. Resolution failure fails closed before subprocess launch. Test both default/physical spellings and an owned symlink alias; all must refer to the intended vnode and enforce denial. Log narrow test-process receipts for selected root, physical control path and override presence so parent environment settings cannot be mistaken for child observations. No relocated-decoy fallback: if physical-path denial still fails, report a blocked prerequisite for a revised brief.
4. Extend `sandboxDeniesAllAccessToTheRealAgentLensCache` with denied read AND denied write against an existing readable/writable fixture sentinel, successful unsandboxed controls, and absence of unintended modifications. Prove the launched child executed the intended operation using an allowed sibling marker written before denied access, together with its denied-operation result. A launch failure or generic nonzero status alone is not isolation evidence. Correct comments to say the decoy proves mechanism behavior only at its measured path, not a direct syscall guarantee about the personal cache.
5. Both production-CLI test launch seams retain denial for the exact Foundation cache path and physical parent-derived alias, for reads and writes and children. Preserve any existing cache-path denial while adding physical-path handling; do not remove it when a cache leaf does not exist. No real-cache content read/write is needed to exercise controls; use owned decoys, and do not create/modify the personal cache to prove denial. `sandboxedCheckUpdatesPublishesNoReusableCacheAcrossTwoRuns`, under default TMPDIR with both overrides unset, must still show six manager queries across two `--check-updates` runs. This is indirect evidence of no reusable cache, combined with path/profile review and the mechanism controls; it does not itself prove all cache reads/writes were prevented. Plain/offline scans retain zero manager calls. State these limits explicitly in comments and the report.
6. Preserve watchdogs, literal argv, fixture-only managers and exact current-run product discovery. Add focused failing-before/passing-after evidence for the portability correction. Keep existing timing semantics; serial acceptance is allowed, but no hidden retries or larger deadlines to conceal failures.

### M10-A-R02 — clean CI check

1. Add one CI check job on `macos-15`, using invocation/job-local `DEVELOPER_DIR=/Applications/Xcode_26.3.app/Contents/Developer`. The official runner inventory lists that Xcode; record `sw_vers`, architecture, selected developer directory, `xcrun swift --version`, Python and runner image version at runtime. The runner label is mutable; do not call it an immutable machine image. Missing specified toolchain is a failure, not automatic fallback. No sudo/global `xcode-select` or downloaded Swift toolchain. Configuring GitHub branch protection to require this check is a separate repository-settings action and is not authorized or claimed here.
2. Trigger on `push`, `pull_request` and `workflow_dispatch`, without source-path filters that leave changes unchecked. Do not use `pull_request_target`, deploy, publish, schedule, credentials or write permissions. Set `permissions: contents: read`, a 30-minute job timeout, and per-ref concurrency that cancels superseded runs. The cap is a bounded initial budget, not a measured performance claim; record local/hosted total and per-gate durations. A timeout is a failure requiring diagnosis and a reviewed budget revision, not an automatic retry or deadline increase. It is separate from the existing subprocess watchdogs.
3. Use official checkout/artifact actions pinned to verified full commit SHAs; record repository, SHA and corresponding release in the worker evidence. No external setup/marketplace action is needed. No dependency install, Homebrew refresh, caches or reuse of built test products in this first clean gate. Build scratch is a unique child of runner temp outside checkout, not a fixed machine-specific path.
4. Run the Core guard and its fixtures; `swift build`; all Swift tests with `--no-parallel`; a debug development app build; and all nine existing packaging checks (the nine `test_*` methods in `Tests/Packaging/test_dev_app_bundle.py`, invoked with `--app`). Explicitly identify the registry/schema suites in the result summary. Expected baseline inventory is at least the existing 329 Swift and nine packaging checks, plus new meaningful tests; report exact executed counts, zero skipped/disabled existing tests and unexpected count changes. Counts alone never substitute for behavior. Use one fresh scratch tree for package build plus tests; the independent builder retains its separate scratch tree to exercise real packaging discovery.
5. Tests inherit the runner's normal TMPDIR with both Agent Lens test overrides unset. A separate additional override case is allowed; it cannot replace the default case. No silent retry, `continue-on-error`, `|| true`, skipped test or log pipeline that masks failure. Before the full suite, run the named isolation test once on the hosted toolchain as an early compile/runtime capability gate; capture native `TestingMacros` discovery and isolation separately. Native macro non-discovery or failed physical-path control stops dependent gates and returns to the orchestrator; do not improvise a toolchain/dependency change. CI uses native toolchain macro discovery; do not hardcode this workstation's plugin path or turn the local macro fallback into an automatic hosted success path.
6. Preserve command/exit/duration records and stdout/stderr for each gate. Upload only explicitly listed check logs/receipts with `if: always()` and seven-day retention, never the whole runner temp, shell environments, credentials or built app release. If an early step fails, artifacts identify later checks as not run. CI must be red when any required check fails.

### M10-A-R03 — Core boundary guard and schema gate

1. Guard recursively inspects Swift source in `Sources/AgentLensCore`, reports forbidden framework imports with source path/line and exits nonzero. Honor legal import forms (including attributes, scoped imports, conditional compilation and whitespace); do not reject words appearing only in comments or string literals. Missing source root or unreadable input is a failure. No compiler plugin or third-party parser dependency.
2. Focused scratch-source fixtures demonstrate acceptance for Foundation/comments/strings and rejection for actual SwiftUI/AppKit imports, attributed/scoped/conditional forms and multiline spelling. Use these as behavior tests, not snapshots of implementation text. `Tests/Packaging/test_core_ui_imports.py` must have a direct `python3` entrypoint returning nonzero for failed tests; it owns the plant/fail/clean/pass cycle against a disposable source-root copy using the exact guard CLI. It never edits real `Sources/AgentLensCore`.
3. CI runs the existing positive/negative registry/schema/query fixtures through the real Swift loader. No separate replacement schema, golden-output weakening or bundled-data change.

## Acceptance matrix

| ID | Setup / exact interaction | Expected evidence |
|---|---|---|
| M10-A-AC01 | Unchanged baseline, inherited TMPDIR, unset both test overrides; targeted isolation test below | Raw failure or pass with toolchain/path context. Separate compile/macro failure from executed test failure; never infer the latter from the former |
| M10-A-AC02 | Final named isolation test and `sandboxedCheckUpdatesPublishesNoReusableCacheAcrossTwoRuns` under inherited TMPDIR, then explicit owned scratch override | Physical-path read/write controls, successful unsandboxed controls, child execution marker, no unintended modification, owned cleanup; both modes pass with zero skips. Two-run six-query behavior is indirect no-reuse evidence, not direct real-cache syscall proof |
| M10-A-AC03 | Focused fixture-seam scenarios: empty/missing root, symlink spelling, physical resolution failure, simulated unenforced sandbox result, invalid explicit products override | Fail-closed errors; fake runner returning success for a denied operation must be rejected, and launch failure without marker must not count as denial. Inject only into test-only control seam, never replace real `/usr/bin/sandbox-exec` at actual CLI launch seams. No launch after failed prerequisite/no stale product fallback; missing-root scenario uses a subprocess or pure input seam, not global environment mutation |
| M10-A-AC04 | Full final Swift suite under inherited TMPDIR, both overrides absent; documented fallback explicitly allowed for this full local gate after recording native macro failure | All existing behavior preserved, at least historical 329 tests plus additions; exact counts, exit 0, no skips or weakened assertions; current-build CLI exercised; fallback evidence clearly labeled local only |
| M10-A-AC05 | Guard CLI and its fixture suite, plus forbidden import planted into owned source copy | Clean passes; deliberate violation fails with location; missing/unreadable root fails; removed violation passes. Real schema/query suites pass |
| M10-A-AC06 | Fresh `swift build`, debug builder and existing packaging suite | Exit 0; all nine existing packaging checks pass, relocation/invalid-registry/denial behavior retained; no signing/release |
| M10-A-AC07 | Read workflow and perform local command-equivalent gates; review failure propagation, permissions, action SHAs, artifacts | Commands execute against frozen candidate; no temp override hides default case; exact runner/toolchain and artifact contract satisfied; local result remains distinct from hosted execution |
| M10-A-AC08 | After separately authorized Git delivery, first clean hosted job for the exact accepted candidate | Run URL, event/ref, commit SHA, runner/toolchain, complete raw gate results and artifacts; red run is not accepted. Hosted evidence is required before M10-B dispatch; no push/PR permission is inferred from this brief |
| M10-A-AC09 | Parent before/after candidate manifest, `git diff --check`, scope comparison | All protected source/resource/package/builder inputs unchanged; only authorized implementation paths differ; reviewer no-edit evidence; no personal installations/cache/configuration touched |

No UI change is intended, so packaging preflight is the native executable gate here; a new visual approval is not invented. Full npm-fixture mutation acceptance belongs to M10-C/D.

## Commands and evidence layout

Before implementation the orchestrator records an absolute unique `E` outside protected/repository roots. Use `E/worker` and `E/parent` independently; preserve inherited TMPDIR. In CI derive `E` using `mktemp -d "$RUNNER_TEMP/agent-lens-m10a.XXXXXX"`. Do not log environment dumps. Capture each command's raw stdout/stderr, argv, exit, elapsed time and narrow non-secret context; every nonzero result stops dependent gates. If using shell pipelines, preserve the producer exit with `pipefail`.

From the repository root, with `E` set to the recorded evidence root:

```sh
swift --version
swift build --scratch-path "$E/worker/default-suite"
env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS \
  swift test --scratch-path "$E/worker/default-suite" --no-parallel \
  --filter sandboxDeniesAllAccessToTheRealAgentLensCache
env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS \
  swift test --scratch-path "$E/worker/default-suite" --no-parallel
env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS \
  swift test --scratch-path "$E/worker/default-suite" --no-parallel \
  --filter sandboxedCheckUpdatesPublishesNoReusableCacheAcrossTwoRuns
mkdir -p "$E/worker/explicit-scratch"
env -u AGENT_LENS_TEST_PRODUCTS AGENT_LENS_TEST_SCRATCH="$E/worker/explicit-scratch" \
  swift test --scratch-path "$E/worker/default-suite" --no-parallel \
  --filter sandboxDeniesAllAccessToTheRealAgentLensCache
env -u AGENT_LENS_TEST_PRODUCTS AGENT_LENS_TEST_SCRATCH="$E/worker/explicit-scratch" \
  swift test --scratch-path "$E/worker/default-suite" --no-parallel \
  --filter sandboxedCheckUpdatesPublishesNoReusableCacheAcrossTwoRuns
python3 scripts/check-core-ui-imports.py
python3 Tests/Packaging/test_core_ui_imports.py
python3 scripts/build-dev-app.py \
  --scratch-root "$E/worker/dev-app" --configuration debug
python3 Tests/Packaging/test_dev_app_bundle.py \
  --app "$E/worker/dev-app/AgentLensApp-debug.app"
git diff --check
```

The new guard and its tests are required deliverables, so those two commands are final-candidate commands, not baseline commands. New fixture-seam tests run as part of the full Swift suite. Parent uses corresponding fresh `E/parent` paths and independently reruns the required local gates. Baseline may use a targeted test first to avoid unrelated fixture work; no targeted run substitutes for final full-suite acceptance.

Only upon the known **local** missing `TestingMacros` discovery error, record that failure, then use a separate fresh scratch directory with the already documented invocation-local workaround. This full-suite invocation is explicitly allowed for local acceptance AC04:

```sh
env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS \
  swift test --build-system swiftbuild \
  --scratch-path "$E/worker/default-suite-explicit" --no-parallel \
  -Xswiftc -load-plugin-library \
  -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib
```

Preserve default TMPDIR in this fallback too. Run AC02's targeted default/override cases with the same plugin flags and explicit build directory if the native command is blocked; changing only the scratch override for the additional override cases is allowed. Full-suite fallback certifies the local behavior gate, not clean hosted CI. Do not change package settings or install/replace the global toolchain. The native hosted job must pass separately. README must keep this workstation-specific path/fallback in a clearly labeled local tooling note, not present it as a supported hosted-CI command.

## Candidate return, stops and completion

Worker submits files changed, concrete behavior/design choices, failing-before/passing-after receipts, requirement-to-AC/evidence table, exact executed counts/exits/skips, workflow/action references, known limitations and SHA-256 manifest of all candidate inputs. Leave files uncommitted, stop editing on handoff, and report any generated files. No branch/stage/commit/reset/merge/push/PR/publication by the worker. The orchestrator verifies protected hashes and independently tests the frozen candidate; changes after handoff invalidate affected acceptance.

Stop for an unavailable enforceable isolation environment, missing runner/toolchain, authentication or dependency need, unexpected edits, failure requiring out-of-allow-list work, personal-state access, ambiguous current-build discovery, or any proposed weakening of existing contracts. Report facts and the smallest needed revision. Do not absorb unrelated test timing failures, hide stderr, retry to green or implement the next phase.

Completion has two recorded checkpoints: **local candidate verified** after AC01–07/09; **M10-A technically accepted** only after AC08 also passes on that exact candidate. Git delivery and the hosted run require their existing separate authorization. Until then state `hosted CI pending`, keep M10-B undispatched, and do not label M10 or M10-A complete. The brief itself can be council-reviewed while implementer selection and implementation authorization remain pending.

## Primary-source planning references

Checked 2026-10-26; runtime image/toolchain details must still be recorded on execution:

- [GitHub macOS 15 runner inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md): available Xcode paths and mutable image identity.
- [GitHub workflow syntax](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax): triggers, permissions, concurrency, timeouts, failure propagation and conditional artifact steps.

These references establish workflow configuration facts; they do not prove this project's tests pass on a hosted runner.
