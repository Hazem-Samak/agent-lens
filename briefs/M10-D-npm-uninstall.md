# M10-D — confirmed npm Uninstall and combined npm acceptance

Status: **FROZEN — planning complete**, 2026-11-08 (Africa/Cairo). Two self-review rounds and the
independent review disposition are recorded in §10 and
[the planning record](../walkthroughs/M10-D-planning.md). Implementation is owner-authorized;
M10-A/B/C are technically accepted on `codex/m10-npm-management`; M10 as a whole is not accepted.

## 1. Identity and prerequisites

- Single milestone branch: `codex/m10-npm-management`. Planning baseline:
  `4b828c72d4d443bcaeb9ec37b654118ce2e4583e`, which contains accepted M10-C implementation
  `fff287d79884bf2163642dfa6ef3543da5682565` plus documentation/evidence only. Recheck and pin the
  exact planning commit before dispatch.
- M10-C is technically accepted; its frozen brief and evidence are historical and immutable. This
  brief adds Uninstall and the combined Update/Uninstall gate. It does not reopen M10-C behavior
  unless a regression is proven.
- Owner authorization: 2026-11-08, planning and implementation by the orchestrator acting as sole
  product writer. This is an owner-authorized exception to D-014's separation: independent read-only
  review and exact-SHA hosted CI remain the external verification, and final acceptance must disclose
  that coordinator acceptance and implementation were performed by the same agent. Plan reviewer:
  OpenCode `opencode/glm-5.3-flash-free#max`. Implementation reviewers: mcode
  `minimax/MiniMax-M3.1-Flash` at `xhigh` first, then agy `gemini-3.8-flash-high` at `high`. Perch
  `glm-5.3-flash-starter` at `max` is the alternate/emergency route only. Reviews are read-only;
  every finding returns to the writer for correction.
- Observed planning tools: npm 10.9.7, Node 22.22.2, Swift 6.4. No new dependency, package
  installation, credential, privilege, signing, publication, or `main` mutation is authorized.
- The plan is committed and frozen before implementation. Two self-review/revision rounds and one
  independent OpenCode plan review precede freeze. Implementation requires two review/revision
  rounds with the selected reviewers.

## 2. User outcome and exclusions

For a selected, freshly ownership-verified npm-global installation, the native app can prepare an
exact Uninstall preview, cancel without effects, confirm after complete revalidation, run one
bounded `npm uninstall`, show stdout/stderr/exit status, and rescan to show the actual installation
and PATH delta. The same candidate then performs Update followed by Uninstall (and the reverse order
where practical) in one disposable prefix, proving the two mutations share one exclusion gate and
never overlap.

This phase delivers **app-driven npm Uninstall plus the combined M10 npm acceptance gate only**. No
update-all/remove-all, no fresh install of an absent tool, no Homebrew/pip/uv/Cargo mutation, no
catalogue/schema expansion, no custom/private registry support, no new CLI mutation syntax, no
scheduled/background mutation, no signing/distribution, and no M8 keyboard-only work. A displayed
ownership result, update badge, cached metadata, source hint, or prior verification is never
mutation authority.

## 3. Primary research and inspected seams

Primary npm documentation inspected 2026-11-08:

- [npm uninstall](https://docs.npmjs.com/cli/v11/commands/npm-uninstall): uninstalls a package and
  "completely removes everything npm installed on its behalf"; in global mode it operates in the
  configured `prefix`, removes the package from `{prefix}/lib/node_modules`, and removes its bin
  links from `{prefix}/bin`. `--no-save` is ignored in global mode; `--global` and `--prefix` select
  the target. npm v7+ does **not** run `uninstall` lifecycle scripts (`preuninstall`/`postuninstall`
  are not implemented); Agent Lens must not claim they run or override script policy.
- [npm folders](https://docs.npmjs.com/cli/v11/configuring-npm/folders): global packages live under
  the prefix, and bin links are separate from the package directory. A removed package can reveal a
  different PATH winner or leave another installation installed; the delta must show that.
- [npm config](https://docs.npmjs.com/cli/v11/using-npm/config): cache/log locations, script policy,
  audit/fund, retries/timeouts, and registry values affect command behavior. Agent Lens pins the
  supported public registry literally but does not query metadata for removal.

Current code facts:

- `NpmOwnershipProbe.verifyWithProof` returns the complete `NpmOwnershipProof` and `revalidate()`;
  `VerifiedInstallation` alone is not sufficient authority.
- `NpmUpdateOperation` already implements fresh preparation, an opaque preparation, a process-wide
  `OperationExecutionGate`, exact argv execution, dual-stream capture, process-group interruption,
  and mandatory post-launch reconciliation. Uninstall must reuse those seams, not add a second
  process engine.
- `BoundedProcessRunner.runDualStream`, `ProcessOperationCommandRunner`, `NpmScratchBase`,
  `NpmScratchRoot`, `NpmScratchCleanupLedger`, `npmEnvironment`, and the operation DTOs are the
  existing security boundaries. Uninstall-specific behavior stays in Core; presentation state stays
  in `InventoryViewModel`; native effects stay in the app.
- `InventoryEntry.ownership` is a read-only observation, not permission. Uninstall preparation must
  repeat full live verification even when that result says verified.
- No CLI mutation command exists; the shipping CLI remains read-only.

Planning probe (to repeat in implementation): on a disposable prefix, install a tiny fixture package
with real npm, run `npm uninstall <pkg> --global --prefix <prefix> --dry-run` to measure accepted
flags and effects, then use production argv without `--dry-run`. Dry-run is probe-only and forbidden
in production execution. No package was installed during planning.

## 4. Behavioral and interface contract

### D01 — eligibility and fresh preparation

1. Offer Uninstall only for a selected entry whose selected entry/canonical target exists and whose
   declared package is npm. A previously verified ownership result may decide whether the native
   button is shown, but preparation must repeat full live verification and must not trust it.
2. `InventoryViewModel.prepareSelectedUninstall()` first obtains a fresh local inventory from the
   captured session environment and requires the same registry ID and selected entry/canonical
   target as the clicked entry. A changed selection invalidates preparation and never retargets.
3. Core preparation performs a fresh `NpmOwnershipProbe.verifyWithProof` using the captured
   environment and an owned scratch root. It requires exactly one verified npm package, the selected
   entry/target, the manager, package name, prefix, root, and proof. No metadata cache or latest
   query is read or written.
4. A missing local version does not by itself refuse Uninstall: ownership is the authority for
   removal. If a version is present, bind its exact text; if absent, bind `nil`. A malformed,
   changed, ambiguous, unverified, Homebrew/cask, pip/uv, or inconsistent selection refuses with a
   typed unavailability and zero mutation.
5. Add an internal `NpmUninstallObservation`/`NpmUninstallPlan` carrying the fresh diagnostic,
   selected entry/target, optional installed version, manager, `VerifiedInstallation`, complete
   `NpmOwnershipProof`, environment context, operation root, and exact argv. The proof is internal,
   unforgeable from AppSupport, never persisted, and never exposed as a public token. The public
   surface is an opaque `NpmUninstallPreparation` with no public initializer.
6. Claim a mode-0700 operation root during preparation and record its device/inode/physical identity.
   Cancel, staleness, execution completion, and every failure path release only that owned root.
   Replacement or unsafe cleanup refuses/warns rather than deleting a substitute.

### D02 — immutable preview and confirmation plan

1. Core exposes `NpmUninstallOperation.prepare` returning `.ready(NpmUninstallPreparation)` or a
   typed `.unavailable`. The public preparation exposes only `preview: NpmUninstallPreview`; it has
   no public initializer and cannot be constructed from display strings.
2. The preview shows: registry ID/tool, selected entry/target, installed version or an explicit
   "unavailable" marker, verified package, manager path, verified prefix, installation root,
   working directory, exact executable plus argument array, and the effect text. A shell-escaped
   string may be rendered for readability but is never executed.
3. Effect text states explicitly: npm removes the named global package from the verified prefix and
   may remove its executable links; npm v7+ does not run uninstall lifecycle scripts, and Agent
   Lens does not add a script-policy override; transitive dependency directories, caches,
   configuration, logs, or other
   installations outside the verified package are not intentionally targeted and may remain;
   removal changes the PATH winner and may reveal another copy; no rollback, reinstall, or atomicity
   is promised; a failed or interrupted removal may leave a partial state that must be re-observed.
4. The plan binds fresh selected entry/target, optional installed version, manager identity,
   `VerifiedInstallation`, complete proof and proof fingerprint, package, prefix/root, captured
   environment context, operation-root identity, and exact argument array. It contains no
   credentials dump and is never persisted.
5. A pending Uninstall preview owns the app's single mutation slot. Selection, filtering, Rescan,
   Check, Refresh, ownership verification, another Uninstall, or an Update invalidates/closes it
   without mutation. Cancel releases it with zero mutation. The same displayed plan is returned to
   Core for confirmation; the UI never edits its fields.

### D03 — confirmation and exact execution

1. `NpmUninstallOperation.execute(confirmed:)` first performs a fresh local diagnostic scan of the
   same registry definition through the existing identity-bound scanner, then repeats complete live
   ownership verification with a fresh proof and compares every bound field, including the optional
   installed version and operation-root identity. Any change, cancellation, deadline expiry, or
   failed scan invalidates/consumes the plan with zero mutation and requires a new preview.
2. Immediately before launch, revalidate the live proof and owned operation root again. The
   preparation is consumed through the process-wide `OperationExecutionGate`; double Confirm,
   replay, or a concurrent Update/Uninstall cannot produce two mutation processes.
3. Use the verified manager's absolute path and literal array in this exact semantic shape
   (argument order may vary only when receipts preserve every flag):

   ```text
   <npm> --cache <owned-operation-root> --logs-dir <owned-operation-root> --no-update-notifier
     uninstall <verified-package>
     --global --prefix <verified-prefix>
     --registry=https://registry.npmjs.org/
     [--@scope:registry=https://registry.npmjs.org/]
     --no-audit --no-fund --package-lock=false --no-save
     --fetch-retries=0 --fetch-timeout=30000
   ```

   The scoped pin is required for every scoped package, including an initially unset scope. Never
   use a bare package pattern, `npm rm` alias, shell command, `sudo`, `--force`, `--ignore-scripts`,
   `--dangerously-allow-all-scripts`, automatic retry, `update`, or `prune`. `--dry-run` is forbidden
   in production execution (it is a planning probe only). Uninstall does not query latest metadata;
   the registry pins exist only to keep any incidental npm request on the supported public route.
   Do not pass a log-level override that suppresses failure output.
4. The working directory is the owned operation scratch root, not a project or personal directory.
   Copy the captured environment, rewrite only cache/log/notifier values to that root, preserve
   other validated context, and never log the environment. Global mode and `--no-save` protect
   project files; no project directory is ever the target.
5. Respect other npm engine/platform/script policies. Do not override them to force success. If
   they reject the removal, report failure/uncertainty with output; never fall back to a broader
   command or a second attempt.

### D04 — operation process, output, timeout, and cancellation

1. Reuse `OperationCommandRunner`/`ProcessOperationCommandRunner` and the existing dual-stream
   bounded runner. Do not change accepted M10-C read-only callers or capture-stream behavior; any
   shared-runner correction must be backward-compatible and covered by the existing tests.
2. Preparation and confirmation revalidation each have a separate 60-second monotonic read-only
   budget; user review time between them is excluded. Mutation timeout is 120 seconds; npm
   per-request timeout is 30 seconds; retries are zero. Output is capped at 1 MiB per stream with
   explicit truncation flags.
3. On cancellation after launch, send SIGTERM to the exact process group, allow 2 seconds, then
   SIGKILL and bounded reaping/join. Timeout and output overflow follow the same interrupted path.
   No orphaned process or unjoined runner may remain.
4. Cancellation before launch returns `.cancelled` with zero mutation. After launch return
   `.interrupted` or `.uncertain` as appropriate, never "rolled back" or "unchanged." Always
   reconcile after a launched process, including nonzero exit, cancellation, timeout, overflow, and
   window closure.
5. `UninstallOperationOutcome` retains separate stdout/stderr data, truncation flags, exit status
   when available, typed state (`succeeded`, `failed`, `cancelled`, `interrupted`, `uncertain`),
   reconciliation delta when available, cleanup warnings, and a neutral message. Output is in-memory
   only; evidence uses secret-free fixtures and never prints captured environment or auth config.

### D05 — removal reconciliation and truthful outcome

1. After every launched operation, perform a fresh login-shell/local inventory rescan and measure
   the reviewed installation from the bound proof. Do not claim success from exit status alone.
2. Define the reviewed package as removed only when both hold on fresh observations:
   - the exact recorded package directory (`proof.packageLexicalPath`) no longer has the recorded
     directory identity, and
   - the selected entry no longer resolves to the recorded selected canonical target.
   A package directory replaced by a different identity, a still-live old selected target (even if
   the package path is gone, which would mean the target lies outside the reviewed package), or an
   unreadable/failed observation is not proof of clean removal.
3. `.succeeded` requires npm exit 0 **and** the two removal facts above. Exit 0 with the package or
   selected target still present is `.uncertain`. Nonzero exit is `.failed` even if a partial delta
   shows removal. A launched process with no observed exit status is `.uncertain`. Interrupted
   process results are `.interrupted` when reconciliation is available, otherwise `.uncertain`.
4. Record a `NpmUninstallDelta`: before/after selected entry/target/version/aliases/shadowed
   count/install state, whether the reviewed package identity is gone, whether the selected entry
   was released, and post-operation ownership of any remaining selected installation (verified or
   neutral reason). Show the actual PATH-winner change; never claim the tool or its configuration
   disappeared. After any launched Uninstall, clear the prior verified ownership observation in the
   published snapshot and require a fresh Verify before another ownership-gated action.
5. A cleanup refusal after a proven removal retains `.succeeded` and adds a warning. A failed or
   inconclusive rescan, ownership query, or proof revalidation produces `.uncertain` with the
   process result retained. Never claim atomicity, rollback, or "no effect" after launch.

### D06 — native workflow and single-slot exclusion

1. Add native preparation progress, confirmation sheet, executing/cancelling states, and result
   view for Uninstall. The sheet shows the exact preview/argv/effect and separate monospaced
   scrolling stdout/stderr, exit status, truncation/cleanup warnings, and the delta. All dynamic
   values are plain text, never shell interpolation.
2. Cancel is the default/prominent safe action for the destructive sheet; the destructive confirm
   button is explicit, not the Return-key default. `interactiveDismissDisabled` applies while
   executing. A pending preview releases with zero mutation.
3. `InventoryViewModel` remains the only app state owner. Update and Uninstall share one mutation
   slot and one operation pipeline concept: a pending preview of either kind is invalidated by the
   other, and no scan/check/refresh/verify may leave two operation sheets or two processes alive.
4. Window closure and app termination cancel and join both Update and Uninstall, release any
   pending preview root, and perform the required bounded reconciliation after launch. No stale
   completion may attach to another selection or generation.
5. Show Uninstall only where the selected entry has a current verified npm ownership observation and
   a selected entry/target; the action is recoverable if ownership becomes stale because preparation
   refuses. Do not offer it for Homebrew, cask, pip/uv, unknown, or unverified entries. A successful
   or launched removal publishes the fresh snapshot with ownership cleared, so the button cannot
   remain armed against a package that may already be gone.
6. Do not add a CLI mutation command or a shipping debug switch. Use the shipping CLI only for
   read-only post-operation parity checks.

### D07 — combined M10 npm gate

1. On one frozen candidate, using one disposable npm prefix and controlled registry, perform a
   confirmed Update from an older exact version to a newer exact version, observe the delta, then a
   confirmed Uninstall of that same package, observe the removal delta, and verify unrelated
   package/prefix sentinels are unchanged.
2. Prove single-operation exclusion across kinds: an Update preparation and an Uninstall preparation
   cannot both execute; double Confirm, replay, concurrent selection changes, and a competing scan
   launch at most one mutation. The gate is process-wide in production; tests inject independent
   gates.
3. Where practical, run the reverse order on a fresh prefix (Uninstall then install/update setup) and
   a public-npm ordinary-app Uninstall. If the public fixture cannot be made deterministic, record a
   truthful BLOCKED limitation rather than substituting a personal installation.
4. M10 acceptance is not declared until M10-D and the combined gate both pass on one frozen commit,
   both independent implementation reviews close all material findings after two review/revision
   rounds, and exact-SHA hosted CI passes all seven existing gates. The PR-ready review is separate
   from accepting M10: it may identify defects and return them, but it cannot merge.

## 5. File authority

Modify only these existing files and add only these named new files. A needed change elsewhere is a
stop for a bounded revision.

- Add `Sources/AgentLensCore/Operations/NpmUninstallOperation.swift` and, only if mechanical reuse
  is proven by unchanged M10-C tests, `Sources/AgentLensCore/Operations/NpmOperationSupport.swift`.
- `Sources/AgentLensCore/Operations/OperationModels.swift` — add uninstall DTOs; preserve every
  existing M10-C public type and behavior.
- `Sources/AgentLensCore/Operations/OperationProcessRunner.swift` — only if a backward-compatible
  reuse correction is required; no M10-C semantics change without regression proof.
- `Sources/AgentLensAppSupport/InventoryService.swift` and `InventoryViewModel.swift`.
- `Sources/AgentLensApp/MainWindow.swift`, `Sources/AgentLensApp/ToolDetailView.swift`; add
  `Sources/AgentLensApp/UninstallOperationView.swift` (or one shared operation sheet view if it
  preserves the accepted Update presentation).
- Add `Tests/AgentLensCoreTests/NpmUninstallOperationTests.swift`.
- `Tests/AgentLensCoreTests/NpmUpdateOperationTests.swift` and `OperationProcessRunnerTests.swift`
  only for shared-seam regressions.
- `Tests/AgentLensAppSupportTests/InventoryServiceTests.swift` and `InventoryViewModelTests.swift`
  for mutation-slot/state integration.
- Extend `Tests/Fixtures/M10C/npm_update_acceptance.py` with additive Uninstall/combined scenarios,
  or add `Tests/Fixtures/M10D/npm_uninstall_acceptance.py` that imports/reuses the existing
  standard-library harness without duplicating the registry/tarball implementation. Existing
  M10-C scenarios must remain behaviorally unchanged.
- `README.md`; add `walkthroughs/M10-D-implementation.md` for writer evidence and
  `walkthroughs/M10-D-acceptance.md` for coordinator acceptance. Coordinator owns roadmap/status
  records.

DO NOT TOUCH: `Package.swift` or dependencies; bundled registry/schema/resources; `Sources/agent-lens/main.swift`;
other Core process/update/ownership/Homebrew files; CI workflows/gates/count floors; packaging/builder/guard
scripts; scope/decisions/roadmap; historical briefs/walkthroughs; personal installations, caches, npmrc,
shell files, or global toolchain. Do not weaken or skip existing tests/timeouts/assertions.

## 6. Acceptance matrix

Every row requires raw secret-free argv/stdout/stderr/exit/elapsed receipts and exact candidate
identity. Writer evidence is not coordinator acceptance.

| ID | Setup and observation | Pass requirement |
|---|---|---|
| M10-D-AC01 eligibility | Verified/unverified npm, update-available/up-to-date/off-PATH/shadowed/ambiguous selections, Homebrew/cask/pip/uv, missing version, inconsistent diagnostic | Only a fresh verified npm package prepares; no cache/ownership hint authorizes; no mutation launch |
| M10-D-AC02 preview | Scoped/unscoped packages, spaces/metacharacters in owned paths, existing version and missing version, real npm dry-run probe | Exact package/prefix/argv/effect displayed; no wildcard/alias/shell string; destructive, no-uninstall-scripts, dependency-remainder, PATH-winner, and no-rollback effects disclosed |
| M10-D-AC03 pre-launch cancel | Cancel during preparation and pending confirmation; repeated Cancel; operation root removed/replaced while waiting | Zero mutation spawn, unchanged package/prefix/sentinels, slot and owned scratch released safely, no stale plan |
| M10-D-AC04 stale confirmation | After preview change selection/entry/target/manager/package/prefix/root/proof/optional version/environment/operation-root identity | Fresh scan plus full fresh ownership/proof comparison refuses before mutation and demands a new preview; no fallback |
| M10-D-AC05 controlled success | Real npm, disposable prefix, controlled registry, old fixture package installed | One exact npm uninstall; separate output/exit 0; package identity and selected target gone; correct delta; unrelated package/prefix sentinels unchanged |
| M10-D-AC06 failure/uncertain | Nonzero npm, permission denial, missing package, exit 0 but package/target still present, partial removal, no observed exit | Output and exit retained; no retry/fallback; post-state measured; exit 0 never alone means success; no rollback claim |
| M10-D-AC07 concurrency | Double Confirm, replayed plan, simultaneous Update+Uninstall, Confirm plus Rescan/Check/selection/Verify | Shared Core gate permits at most one mutation; other actions coalesce/invalidate without retargeting; one process |
| M10-D-AC08 interruption | Cancel before/after spawn, delayed child, timeout, output overflow, actual window closure, app termination | Bounded TERM/KILL/reap/join; no orphan; cancelled only before launch, interrupted/uncertain after; mandatory reconciliation |
| M10-D-AC09 native flow | Unchanged product views in controlled native host; actual built app through Accessibility; captured preview and result sheets | Verify → Uninstall preview → Cancel unchanged → fresh preview → Confirm → output/delta observed; Cancel is the safe default and Confirm is not the Return default; no body/sheet ambiguity; actual app and controlled-host results distinguished |
| M10-D-AC10 combined gate | Update older→newer then Uninstall; reverse order where practical; same shared gate | Both mutations succeed sequentially on one prefix; sentinels unchanged; no overlap; truthful deltas; combined M10 npm gate passes |
| M10-D-AC11 actual app/public npm | Ordinary built app, production service/runner, public Codex old stable in a disposable prefix, synthetic HOME/config/cache and sandbox | Actual shipping preview/confirm/result works; post-operation CLI `scan --offline` agrees; personal paths untouched; public limitation recorded if unavoidable |
| M10-D-AC12 isolation and scope | Secret-free fixture HOME/config, personal-cache/install denials, unrelated sentinels, protected-file hashes | Only owned prefix/scratch changes; no custom production registry; no credentials/environment dumps; allow-list and cleanup verified |
| M10-D-AC13 regression | Full local gates, fresh debug app/packaging, exact candidate hosted CI | All pre-existing 510 Swift tests plus additions, zero skips/failures; guard 21; packaging 9; all seven exact-SHA hosted gates pass |

## 7. Required fixture and native recipes

### Deterministic controlled registry

Extend the existing M10-C harness or add an importing M10-D harness that creates only beneath an
operator-supplied owned root E:

- Tiny tarballs for the validated fixture package identity with a `codex` bin reporting exact
  versions 1.0.0 and 2.0.0, plus a harmless dependency fixture whose effects stay inside E.
- Synthetic HOME, user/global npmrc, cache/log roots, prefix, closed PATH with existing npm/Node,
  fixture registry JSON validated by Core, and unrelated package/prefix sentinel manifests.
- Owned loopback registry serving exact packuments/tarballs and recording requests. Start/stop/join
  only its recorded PID; never leave a server running.
- Real npm installation of the old fixture into the owned prefix before scenarios. Production
  operation argv must first be asserted by the external harness; only then may the harness
  substitute public base/scope registry flags with the owned loopback endpoint. Record original and
  executed argv. Production has no loopback/custom-registry switch.
- Add a controlled Uninstall scenario that seeds 1.0.0, prepares/executes Uninstall, and records:
  exact argv, exit, streams, package identity gone, selected target released, sentinels unchanged,
  operation scratch empty, and no retry.
- Add a combined scenario that performs Update 1.0.0→2.0.0 and then Uninstall in the same prefix,
  including a deliberate concurrent-confirm attempt and a window-close/interruption case.
- The controlled native host may compile unchanged product views and inject services/runners as in
  M10-C. It is deterministic native evidence, not the ordinary-app gate.

### Ordinary app and public npm

Use the shipping detector registry and real public npm. The harness selects an older stable public
Codex, installs the old exact package only into E's prefix, and verifies the fixture `codex --version`.
If no suitable older stable package or required public transport is available, mark the row BLOCKED
with evidence; do not substitute a fake or personal installation.

Launch the ordinary built app with synthetic login-shell HOME/ZDOTDIR/PATH/TMPDIR and Seatbelt denials
for personal AgentLens/npm caches, npmrc, off-PATH tool roots, and writes outside E. It uses the
production service, runner, registry, and public route—no injected transport or debug switch. Exercise
Verify → Uninstall preview → Cancel (hash unchanged) → fresh preview → Confirm → output/delta. Then run
the current shipping CLI `scan --offline` against the same isolated environment and compare facts.
Controlled-host success cannot waive this gate.

## 8. Verification commands and evidence

From repository root, create one owned evidence root and record its absolute path. E is never a
cleanup target; the harness removes only recorded owned children and preserves receipts.

```sh
E=$(mktemp -d /private/tmp/agent-lens-m10d-acceptance.XXXXXX)
mkdir -p "$E/writer" "$E/parent" "$E/fixtures"
```

Use inherited TMPDIR with Agent Lens test overrides unset for default gates. Use fresh writer/parent
roots beneath E; do not run timing-sensitive suites concurrently. Before implementation the writer
runs these baseline gates against the pinned unmodified baseline and verifies the selected route and
fixture/public transport; any failure is BLOCKED, not a skipped gate.

```sh
python3 scripts/check-core-ui-imports.py
python3 Tests/Packaging/test_core_ui_imports.py
swift build
swift test --no-parallel
python3 scripts/build-dev-app.py --scratch-root "$E/parent/debug-app" --configuration debug
python3 Tests/Packaging/test_dev_app_bundle.py --app "$E/parent/debug-app/AgentLensApp-debug.app"
git diff --check
```

Targeted operation tests may diagnose but never replace the full suite:

```sh
swift test --no-parallel --filter NpmUninstallOperation
swift test --no-parallel --filter NpmUpdateOperation
swift test --no-parallel --filter OperationProcessRunner
PRODUCTS="$E/parent/products"
swift build --scratch-path "$PRODUCTS"
BIN_DIR=$(swift build --scratch-path "$PRODUCTS" --show-bin-path)
python3 Tests/Fixtures/M10C/npm_update_acceptance.py \
  --root "$E/parent/controlled" --scenario controlled \
  --cli "$BIN_DIR/agent-lens" --products "$PRODUCTS"
```

The exact M10-D harness command and scenario names are added by implementation and recorded in the
walkthrough. The harness must reject a pre-existing root, record ownership identity, and never
delete or adopt a non-owned root.

Build a fresh current candidate for the harness and native host; never mix baseline Core/AppSupport
objects with candidate views. Record the exact binary/module paths. Raw interaction receipts are
mandatory separate evidence. Local TestingMacros fallback, if needed, follows M10-A exactly and never
changes hosted commands.

Baseline failures stop implementation for adjudication. Final acceptance inventories exact passed
test names/counts and rejects zero-test exit 0. Writer returns touched files/hashes,
requirement-to-evidence matrix, all raw receipts, screenshots, scope/protected-file proof,
process/server cleanup, and limitations. Coordinator independently reruns the gates, observes
controlled and ordinary native journeys, and obtains pinned independent read-only safety review.
Exact-SHA hosted CI follows separate Git authorization. UI approval, Git delivery, and PR/merge
remain separate owner authorizations.

## 9. Stop and done conditions

Stop for missing writer/reviewer route, npm/Node, unavailable isolation or public fixture, ambiguous
ownership/target, need outside the allow-list, new dependency/privilege/credential/publication
request, inability to capture both streams or join processes, unexpected file changes, or any
personal-installation/cache effect. Report facts and request a bounded revision; never improvise or
edit this frozen brief during implementation.

Done only when M10-D-AC01–13 all pass on one frozen candidate, material review findings are closed,
all required real/native evidence exists, and no placeholder remains. M10-D acceptance plus the
combined gate accepts M10 npm management; it does not authorize `main` integration, PR creation, or
release unless the owner separately authorizes them.

## 10. Planning verification and freeze

- P1 self-review: verify D01–D07 traceability to AC01–AC13, single-slot semantics, exact argv,
  offline removal, optional version binding, removal criteria, failure/interruption truthfulness,
  file authority, and combined gate. Correct omissions before independent review.
- Independent plan review: OpenCode `opencode/glm-5.3-flash-free#max` reads this brief and the
  inspected seams read-only, then reports blocking and non-blocking findings. No reviewer edits.
  Two time-boxed invocations were interrupted after extended stalls before a complete verdict. The
  completed portion found one material error: npm v7+ does not run `uninstall` lifecycle scripts.
  That finding was verified against npm's primary documentation and corrected here. mcode and agy
  were started as read-only fallback plan checks; their status is retained, and no timed-out review
  is represented as a PASS.
- P2 revision: adjudicate every finding, revise the brief, re-check the matrix and commands, and
  record the disposition. The lifecycle-script finding was corrected in §3, D02, and AC02. Freeze
  proceeded after the second revision under the owner's explicit instruction, with the missing
  complete independent verdict disclosed.
- Freeze commit includes this brief, the planning record, and the raw review transcript. Planning
  freeze does not attest that future baseline, implementation, runtime, native, or hosted gates
  have passed and does not authorize merge or release.
