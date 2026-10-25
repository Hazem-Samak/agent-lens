# M9-C — identity-bound versions for each observed installation

## 1. Authority and accepted baseline

M9-B R2 is technically accepted by the parent. Implement only this final M9 phase, not the full roadmap. Whole-milestone contract: [M9-verified-installations.md](M9-verified-installations.md); parent acceptance record: [walkthrough](../walkthroughs/M9-verified-installations.md). These are requirements/status, not instructions to change later milestones.

- Repository `/Users/corvette/Documents/Projects Coding/Agent Lens`; branch `milestone/m9-verified-inventory`; HEAD baseline `a405b56183ad0233f286f4d93b027ba7d21c2a01`, plus accepted uncommitted A/B.
- Accepted A manifest `59402e1afdc8b7ccb2af5d3c76ae251dab6f55a05ab81de0d976631385e37160`.
- Accepted B manifest `d00d9ae6dfbe0af505c8b3a2b8a713feb76d7ab88786b96c5ea58bfd0163a20a` (21 files). Parent independently passed 244 Core + 71 AppSupport tests, fresh app build, 9 packaging checks, real npm/Homebrew and actual/controlled native scenarios. Copies `R/accepted-b`; protected baseline `R/evidence/accepted-b-baseline-sha256.json`, finalized by the parent before dispatch.
- R is `/Users/corvette/.hermes/cache/scratch/agent-lens-m9-20261022-382vfoyi`. New worker root `R/worker-c`; all temporary files/processes/smokes/build roots stay under R. Invocation-local TMPDIR `R/tmp`.
- Sole implementer: DeepSeek V4.1 Flash Free through OpenCode, route `opencode/deepseek-v4.1-flash-free#max`, build agent. No other model/provider/CLI/subagents. Record live CLI version; do not install, upgrade or reconfigure tools. Relay now reported 2.1.4, an external host-state change.
- No staging, commit, branch switch, reset, clean, merge, push, publication, credential/config access or installed-package mutation. Parent owns review/status; fixes return to this worker.

## 2. User-visible outcome

Diagnostics distinguish separate executable installations by canonical target. Two real executables reporting different versions retain those different values; aliases and repeated PATH slots share one observation. The selected detail/list version comes from the selected installation's observation, not a second query. A selected declared extra-root executable also has its own observation, explicitly off PATH. Failures or changes are neutral unknowns, never another installation's value.

The CLI PATH report and native Diagnostics show an unambiguous version/unknown reason paired with each canonical target. Existing winner/alias/shadow/off-PATH labels and count definitions remain correct. Ownership remains an independent, explicit read-only action; no management action becomes available.

## 3. Scope and protected boundaries

Allowed product edits:

- `Sources/AgentLensCore/Detection/ToolDetector.swift`: factor a small internal location-only path for the diagnostic scanner; retain direct public detect semantics. Do not add a public test/fixture mode.
- `Sources/AgentLensCore/Diagnostics/PathDiagnostics.swift`, `DiagnosticsScanRenderer.swift`.
- Add `Sources/AgentLensCore/Diagnostics/InstallationVersionObservation.swift`; a separate narrowly named collector file in the same directory is allowed only if it keeps the scanner/model small rather than adding a generic framework.
- **Move**, do not copy/shim, `Sources/AgentLensCore/Ownership/ExecutableIdentity.swift` to `Sources/AgentLensCore/Process/ExecutableIdentity.swift`: fingerprints/observation now have a real second Core consumer. Narrow sharing/header changes only; preserve B's descriptor-read and containment behavior. No obsolete old file or re-export.
- `Sources/AgentLensApp/DiagnosticsView.swift` for the new canonical-installation version section. `ToolDetailView.swift` or `ToolListView.swift` only if necessary to consume the correctly selected version; no layout redesign or unrelated styling.
- Directly affected Core/AppSupport tests for required model initializer migration and real behavioral regressions: notably `PathDiagnosticsTests.swift`, `ToolDetectorTests.swift`, `UpdateProbeCoordinatorTests.swift`, `UpdateCLIIntegrationTests.swift`, `PathActionTests.swift`. A focused new Core test file is allowed. Only migrate other directly broken fixture/caller construction when the compiler/reference list proves it necessary; list it in the report.
- New worker report/usage `walkthroughs/M9-C-implementation.md`.

Protected: registry schema/resources/metadata/package declarations; version query argument/stream/line validation and extraction; bounded runner; ownership adapters/verifier/results/UI; update adapters/coordinator/cache; InventoryService/ViewModel and app pipeline/selection/cancellation policy; Package.swift/dependencies/bundle builder/packaging; original scope/decision files; README/roadmap/briefs/parent acceptance record; installed tools/cache/config/environment. If a required behavior cannot be implemented without crossing these boundaries, STOP and request a bounded authorization before changing it. Do not silently widen scope or weaken requirements.

Run language-server references before exported model changes and helper move. Parent's ToolPathDiagnostic query returned 42 references, including app diagnostics, service/snapshot, renderers, M6 coordinator and multiple tests; its index can be partial/stale, so compiler callsite migration is also required. All diagnostic constructors must explicitly represent observations; no fabricated known values to placate fixtures.

## 4. Fixed model / seam contract

Add `ToolPathDiagnostic.installationVersions: [InstallationVersionObservation]` as a required initializer input, migrated at every caller (empty means no measurement in manually constructed fixtures). Keep original fields/count meanings.

Use one typed observation per observed canonical target, plus the selected off-PATH target if present:

- `canonicalTarget: String`: the diagnostic group's originally observed target; never silently rewrite it to a concurrently discovered replacement.
- `entryPath: String`: deterministic representative entry chosen for this installation. This names the candidate even when budget prevents querying; do not label an unexecuted candidate as successfully queried.
- `fingerprint: ExecutableFingerprint?`: reuse the shared B target identity; known measurements must be bound to an observed executable fingerprint.
- `outcome: InstallationVersionOutcome`, with `.measured(String)` and `.unknown(InstallationVersionUnknownReason)`; a `version: String?` derived accessor is appropriate.
- Minimum unknown reasons: unavailable executable, changed identity, failed/no-token query, aggregate budget exhausted. Exact reason case spelling is your implementation choice; make distinctions truthful. The current query seam returns String? and cannot distinguish exit/timeout/no-token: do not invent that detail or refactor A's transport contract just to name it.

No persistence/cache/Codable version scheme or mutable global observer. Ordinary public `ToolDetector.detect(in:)` must continue its existing local query behavior. Give the scanner a small internal location-only operation so it does not execute the winner once during detect and again during collection. Reuse the declared VersionQuerySpecification and existing injectable production query function; no shell string, global process environment or hardcoded alternate `--version` convention.

## 5. Collection and identity invariants

1. Discover/validate selection and PATH candidates using existing semantics. Enumerate current live canonical target groups once, in deterministic first-seen order, selected target first. Same-target aliases/repeated slots do not launch another query. Include selected extra-root/off-PATH only when that is the existing selection; do not expand discovery to every configured root, filesystem tree or package catalogue.
2. Before querying, observe the chosen entry and require its observed canonical target to equal THIS group's target. Bind containment/identity conditions to the same observation, not a separate earlier resolution (the B-R2 failure must not recur in a new guise).
3. Run the declared local query for that representative entry with the captured environment and bounded timeout. Observe/revalidate entry/target/fingerprint afterward. Changed, vanished or replaced identity means unknown even when the process printed a plausible version. Do not borrow an alias's response or retry another binary to turn a failure into success.
4. Revalidate measured identities again before publishing the whole report, because probing a later shadowed copy creates a real interval in which an earlier target/selected entry can change. A changed observation loses its known value. Recheck the selected identity even when its own query failed; if the selected path/target/fingerprint changed, clear its selected version and mark PathSelection inconsistent rather than claim a new winner or retain a stale success. Preserve M5's unavailable shadow-count behavior for inconsistency. An ordinary version-query failure on an unchanged executable does NOT make PATH selection inconsistent.
5. Derive DetectedTool.version from the selected observation only after these checks. No second selected query; direct callers of detect still get their ordinary one local query. Update-mode consumers continue receiving selected local-version semantics; no M6 adapter changes or new latest-version work.
6. These are bounded before/after filesystem observations, not an atomic filesystem freeze or FD-bound exec guarantee. Do not promise stronger semantics than the implementation provides. Versions are scan facts, not ownership or authorization for future mutations.

## 6. Runtime bounds and lifetime

Sequential collection, **maximum one version process at a time**. Preserve existing output caps and declared literal arguments/selected stream/line. Each process timeout is at most the existing 3 seconds.

Add one fixed **10-second monotonic aggregate version-probe budget per tool scan** (not configurable metadata/UI). Launch no new query after expiry, cap a launched query by min(3 seconds, remaining budget), and retain later canonical observations as explicit budget-exhausted unknowns rather than dropping them. Existing process termination/pipe-drain grace can extend wall time; document the real bound instead of hiding it. No batch parallelism, scheduler, retries or background refresh. An internal clock seam is allowed only if needed for a deterministic behavioral boundary test; no public fixture option or global mutable clock.

Production inventory scanning remains off the main executor through the unchanged service utility queue. Its existing cancellation waits for the current bounded tool scan and checks before the next tool/publication; do not introduce a second pipeline or casually change that API. The aggregate budget prevents an arbitrary number of slow PATH copies from making that wait unbounded.

## 7. Presentation and compatibility

CLI and native Diagnostics: a clearly titled canonical-installation version section pairs target, representative entry and measured version or concise neutral unknown reason. Render collection order deterministically. The existing PATH entries still explain winner/aliases/shadowing, so do not duplicate an entire alias array or copy one winner version onto all candidate rows. A flat per-canonical section avoids repeated linear lookup work and makes identity association explicit. Label off-PATH measurement accurately.

Keep existing three IDs/order/category/declarations/links, install tri-state, source heuristic warning, update summary behavior, local-only launch/offline/rescan, ownership clearing, Copy/Reveal identities/help/eligibility and failed-scan freshness banners. Wrap long entry/target paths at a 760-point window. No filter/search redesign, icon polish or new tool. Unknown local versions remain neutral (existing selected summary dash is fine; the installation section explains why).

## 8. Acceptance matrix

| ID | Scenario | Required outcome |
|---|---|---|
| M9-C-AC01 | Two real test-owned executable targets print distinct versions | Both observations and CLI/native associations retain their own value; selected summary equals selected observation |
| M9-C-AC02 | Repeated PATH slot and distinct symlink alias for the winner, plus shadowed second target | Existing counts/labels intact; exactly one query per canonical target; no extra winner query; stable first-seen order |
| M9-C-AC03 | Selected declared extra root with no live PATH winner | Exactly its own off-PATH measurement; no discovery expansion; no shell-winner claim |
| M9-C-AC04 | Missing/unexecutable/failed/no-token query, selected/shadowed retarget or same-path file replacement during query, early target changes while a later query runs | Affected observation unknown; no copied version; changed selected identity makes consistency failure and selected version nil; unchanged query failure preserves valid selection |
| M9-C-AC05 | Enough slow targets to exhaust aggregate budget | Single-process concurrency; no query beyond remaining budget; every observed canonical target represented, later unqueried targets explicitly unknown; no main-actor block or abandoned process |
| M9-C-AC06 | Existing direct detect, CLI scan/update/invalid forms and B ownership lifecycle | Direct detect remains compatible; no extra manager/cache/query side effects; ownership verification still explicit and identity-safe |
| M9-C-AC07 | Fresh full Swift, app builder and packaging; actual CLI/native plus fixture native view | All pass; no protected drift; independent actual native selected versions/diagnostics visible; fixture two-version diagnostics reuse unchanged product source and are labeled separately |

Permanent tests catch version/identity association, alias deduplication, real transitions/failures/budget boundaries. Follow existing isolated fixture patterns. Update directly broken contracts; do not test model property echoes, labels/source text, mock forwarding or bare not-throw. Remove incidental tests encountered in changed contracts instead of re-pinning new wording. Preserve all meaningful existing checks; never loosen timeout assertions, skip tests or alter toolchain/package to obtain green.

## 9. Worker verification and raw evidence

After implementation is complete, run focused relevant tests and then one full regression/build/packaging gate; no mid-edit build/lint/formatter loop. For a new uncertain bug, preserve a meaningful failing-before/passing-after scenario when practical. Use fresh child roots, keep repository `.build` in place, and never remove/reconfigure user-generated state.

Current known environment requires the invocation-local TestingMacros fallback; worker parallel full-suite attempts hit the unchanged M6 real-process timing bound. Use the already-successful complete serial invocation directly rather than rerunning known failures just to confirm:

```sh
env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS \
  TMPDIR="$R/tmp" swift test --build-system swiftbuild \
  --scratch-path "$R/worker-c/full-suite-explicit" --no-parallel \
  -Xswiftc -load-plugin-library \
  -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib
TMPDIR="$R/tmp" python3 scripts/build-dev-app.py \
  --scratch-root "$R/worker-c/dev-app" --configuration debug
TMPDIR="$R/tmp" python3 Tests/Packaging/test_dev_app_bundle.py \
  --app "$R/worker-c/dev-app/AgentLensApp-debug.app"
```

Also run a disposable compiled Core scanner smoke using real executable files: two versions, alias/repeated slot, off-PATH, and changed/failed input. Run the actual built CLI on the live environment and a closed, test-owned fixture environment with two versions; keep real extra roots from leaking into missing-tool fixtures. Do not touch live package state to manufacture a scenario. CLI fixtures retain existing scratch/cache-denial conventions.

Capture exact argv, cwd, stdout, stderr, exit and duration for every gate, including failed attempts. `R/capture-gate.py LABEL command...` is an available parent capture helper using fresh `R/evidence/LABEL` directories, or preserve equivalent raw files in worker-c. No captured environment/credential dumps. Describe actual runtime behavior, not only tests. The parent will drive the actual app and, if necessary, an isolated host compiling unchanged DiagnosticsView against real Core fixture observations. Do not claim native verification you did not perform.

## 10. Documentation / handoff

After smoke proof, write `walkthroughs/M9-C-implementation.md` with usage, model/budget/identity behavior and explicit limits; remove disposable scaffolding from repository (evidence/smoke sources under R may remain for reproducibility). Parent will update master status/README/index after combined acceptance; do not edit those files.

Persist `R/worker-c/final-report.md`: every AC outcome with exact evidence path, full counts/exits, files, actual CLI version/route, changed public contracts, source-scope deviations, failed attempts, unobserved gates and limitations. Provide candidate SHA-256 manifest (sorted sha256/path digest definition consistent with B), protected comparison against accepted B, explicit helper move and any direct fixture migrations. Freeze all candidate files and report manifest digest; no edits after freeze. Parent independently reviews/reruns and may issue revisions.

## 11. Stop / escalation

A missing requirement or necessary protected edit is a stop/request, not permission to reduce scope or create a fake fallback. Never bypass privacy/permission gates, invoke network/latest-package operations, replace real tools or mutate user preferences. No retries, telemetry, new adapter/manager or unrelated cleanup. Leave all current planning and accepted work intact.

## 12. Completion boundary

Worker completion means a frozen, evidenced candidate satisfying AC01–07, not parent acceptance. Parent independently verifies artifact bytes, full gates, real runtime/native behavior and identity safety; defects return to this worker on the same route. User visual approval, Git delivery and later npm/brew management milestones remain separate. The app still must not update or uninstall tools at the end of M9.
