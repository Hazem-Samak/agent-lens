# M10-C — confirmed npm Update

Status: **FROZEN — planning complete**, R2 plus freeze clarifications, 2026-10-28 (Africa/Cairo). Two coordinator self-review passes are complete; no council review is claimed. Implementer selection and product implementation remain pending. Do not edit this frozen brief during implementation; use numbered revision briefs.

## 1. Identity and prerequisites

- Single milestone branch: `codex/m10-npm-management`. Product baseline: `a8c78d87b77362a2b00f9f5a9d7c54ddaa24435b`, which contains accepted M10-B implementation `72ffb1e0b52ffe65dfb8616e648dec9c46d48ae4` plus documentation/evidence only. Recheck and pin the exact planning commit before dispatch.
- M10-A and M10-B are technically accepted on this branch. M10-B hosted run 40558867751 passed all seven gates: 468 Swift tests, 21 guard fixtures, and 9 packaging checks. This is baseline evidence, not an M10-C result. M10 as a whole remains incomplete.
- Implementer: **not selected**. This brief does not authorize implementation, Git delivery, `main` integration, release, or M10-D. The coordinator owns planning, independent acceptance, and status records; the selected worker owns only authorized product/tests/documentation changes.
- Planning-time working tree already contains coordinator-owned modifications to `ROADMAP.md` and `DECISIONS.md`, plus untracked workspace memory. Preserve them; they are not worker product changes and are not part of this brief's implementation authority.
- Observed planning tools: npm 10.9.7, Node 22.22.2, Swift 6.4. No toolchain or external package dependency installation is authorized. Verify the selected worker's actual npm/Node versions and command shapes before dispatch.
- User authorized planning without a council for this phase. Two coordinator self-review passes are required before freeze. Future high-risk implementation still requires coordinator acceptance and independent read-only safety review.

## 2. User outcome and exclusions

For a selected npm-global installation with a verified stable update, the native app can prepare an exact Update preview, cancel without effects, confirm after complete revalidation, run one bounded npm operation, show stdout/stderr/exit status, and rescan to show the resulting version and PATH/inventory delta.

This phase delivers **app-driven Update only**. No Uninstall, update-all, new mutation CLI command, fresh installation of an absent tool, custom/private registry support, dependency additions, catalogue/schema changes, Homebrew/Python/Cargo operations, scheduled/background mutation, signing/distribution, or M8 keyboard work. A displayed update badge, cached metadata, source hint, or earlier Verify Installation result is not mutation authority.

## 3. Primary research and inspected seams

Primary npm documentation inspected 2026-10-28:

- [npm install](https://docs.npmjs.com/cli/v11/commands/npm-install/): `<name>@<version>` requests an exact published version; global mode installs under the selected prefix and installs dependencies. An exact version is used here so a moving tag cannot silently change the confirmed target.
- [npm update](https://docs.npmjs.com/cli/v11/commands/npm-update/): update can install missing packages, respects configured release filters, and is therefore not the M10-C execution verb. Do not substitute `npm update` for the pinned exact-version install.
- [npm scripts](https://docs.npmjs.com/cli/v11/using-npm/scripts/): install-time lifecycle scripts can run. Production must not silently add `--ignore-scripts`, `--dangerously-allow-all-scripts`, or a script-policy override; the preview discloses this effect.
- [npm config](https://docs.npmjs.com/cli/v11/using-npm/config/): cache/log locations, audit, fund, package-lock, fetch retry/timeout, and script policy affect command behavior. Process timeout is separate from npm's per-request timeout.

Current code facts:

- `NpmOwnershipProbe.verifyWithProof` returns the complete internal proof and `revalidate()`; `VerifiedInstallation` alone is not sufficient authority.
- `NpmUpdateProbe` already implements public-registry/scoped-route validation, strict fresh `@latest` metadata, scratch roots, and final proof checks. Refactor a shared internal fresh-observation seam rather than duplicating these rules. Existing Check/Refresh/cache behavior must remain unchanged.
- `UpdateCommandRunner`/`ProcessUpdateCommandRunner` discards stderr and nonzero output and cannot drive a mutation. `BoundedProcessRunner` captures one stream. M10-C requires an operation-specific dual-stream, cancellable lifecycle.
- `InventoryService` owns Core boundaries and `InventoryViewModel` owns one app pipeline. Extend those seams; do not launch npm from SwiftUI or create a second operation engine in the CLI.

Planning probe on npm 10.9.7: public `@openai/codex@latest` returned the M10-B flat metadata shape, and exact-version `npm install ... --dry-run --ignore-scripts` accepted the proposed global/prefix/registry/scratch/no-audit/no-fund/no-lock/no-save flags. Dry-run observed optional platform dependencies, confirming that package scope is larger than one executable. Initial empty-prefix probes also showed that a bare directory is not a realistic installed-prefix fixture; acceptance always starts from a real old package installation. The dry-run flag and `--ignore-scripts` were probe-only and are forbidden in production execution. No package was installed.

## 4. Behavioral and interface contract

### C01 — eligibility and fresh preparation

1. Offer Update only for a selected winner/off-PATH installation whose current typed status is `.updateAvailable` and whose package is npm. All other states show the existing neutral reason; no button performs preparation as a workaround.
2. `InventoryViewModel.prepareSelectedUpdate()` first obtains a fresh local inventory using the captured session environment. Require the same registry ID and selected entry/canonical target as the clicked entry; a changed selection invalidates preparation and never falls back to another installation.
3. Core preparation performs complete live ownership verification, public base/scope registry resolution, and a **fresh** strict `@latest` metadata query. It must not read or write either Agent Lens metadata cache and must not reuse a previous Verify Installation result. Existing normal Check/Refresh cache behavior is preserved.
4. Require one unique verified package, stable strict-SemVer installed and target versions, and target strictly newer than the exact selected installation's fresh local version. Equal, older, newer-than-metadata, prerelease-channel, malformed, offline, unsupported-route, ambiguous, or unverified cases return typed unavailability with zero mutation launch.
5. Add an internal `NpmUpdateProbe` fresh-observation result carrying the fresh local version, target metadata, `VerifiedInstallation`, complete `NpmOwnershipProof`, manager, effective route, and selection. It remains internal and unforgeable from AppSupport; do not expose proof or cache it.

### C02 — immutable preview and confirmation plan

1. Core exposes `NpmUpdateOperation.prepare` returning a typed unavailable result or `NpmUpdatePreparation`. The preparation has a public `preview: NpmUpdatePreview` and internal authorization evidence; it has no public initializer and cannot be constructed from display strings.
2. The preview shows: registry ID/tool, selected entry/target, installed version, exact target version, verified package, normalized public registry/tag, manager path, verified prefix, package-level effect, working directory, and the exact executable plus argument array. A shell-escaped string may be rendered for readability but is never executed.
3. Effect text states explicitly: npm replaces/updates the named global package to the reviewed version; package dependencies and executable links may change; package lifecycle scripts may run subject to npm policy; Agent Lens does not sandbox those scripts and cannot promise that only the prefix/scratch paths change. Configuration/caches outside the owned invocation scratch and verified prefix are not intentionally targeted; no rollback or atomicity is claimed.
4. Claim the mode-0700 operation root during preparation, record its device/inode/physical identity in the plan, and revalidate it before launch. Cancel, staleness, execution completion, and every failure path release only that owned root; replacement or unsafe cleanup refuses/warns rather than deleting a substitute. A pending preview may retain the owned directory but never a mutation process.
5. The plan binds fresh local/target versions, complete proof and proof fingerprint, manager identity, package, prefix/root, selected entry/target/fingerprint, effective base/scope route, captured environment context, operation-root identity, and exact argument array. It contains no credentials dump and is never persisted.
6. A pending preview owns the app's single operation slot. Selection, filtering, Rescan, Check, Refresh, ownership verification, or another Update invalidates/closes it without mutation. Cancel releases it with zero mutation process. The same displayed plan is returned to Core for confirmation; the UI never edits its fields.

### C03 — confirmation and exact execution

1. `NpmUpdateOperation.execute(confirmed:)` first performs a fresh local diagnostic/version scan of the same registry definition through the existing identity-bound scanner (injected in tests), then repeats complete fresh ownership and registry proof plus a fresh `@latest` metadata observation after confirmation. Cache reads are forbidden. Compare every bound field, including freshly measured installed and target versions. After the final external query, revalidate the complete live proof and operation-root identity again immediately before launch. Any change, cancellation, deadline expiry, or new metadata target invalidates/consumes the plan with zero mutation and requires a new preview.
2. Execution uses the verified manager's absolute path and literal array in this exact semantic shape (argument order may vary only if receipts preserve every flag):

   ```text
   <npm> --cache <owned-operation-root> --logs-dir <owned-operation-root> --no-update-notifier
     install <verified-package>@<exact-reviewed-version>
     --global --prefix <verified-prefix>
     --registry=https://registry.npmjs.org/
     [--@scope:registry=https://registry.npmjs.org/]
     --prefer-online --offline=false
     --no-audit --no-fund --package-lock=false --no-save
     --fetch-retries=0 --fetch-timeout=30000
   ```

   The scoped pin is required for every scoped package, including an initially unset scope. Eligibility is established before pinning; the flags never convert a custom route into a supported one. Never use a bare package, `@latest`, a range, `npm update`, a shell command, `sudo`, `--force`, `--ignore-scripts`, `--dangerously-allow-all-scripts`, or automatic retry.
3. The operation working directory is the owned operation scratch root, not a project or personal directory. Copy the captured environment, override only cache/log/notifier values to that root, preserve validated routing/auth context, and never log the environment. Global mode, `--no-save`, and `--package-lock=false` protect project files.
4. A Core operation gate enforces one mutation at a time and consumes a preparation before launch. Production shares the gate process-wide across every service/window; tests receive independent injected gates. Double Confirm, concurrent executions, replay of the same preparation, or calls for two tools cannot produce two mutation processes. UI disabling alone is insufficient.
5. Respect other npm engine/platform/script policies. Do not override them to force success. If they reject the exact target or produce an unexpected result, report failure/uncertainty with output; never fall back to another version.

### C04 — operation process, output, timeout, and cancellation

1. Add public `OperationCommandRunner` as the injectable seam and `ProcessOperationCommandRunner` as production, implemented in `OperationProcessRunner.swift`. Add public `OperationExecutionGate`; production defaults to one process-wide instance while tests inject independent gates and runners through `InventoryService`. The runner supports captured working directory/environment, separate stdout/stderr capture, process-group lifetime, exit status, spawn failure, timeout, cancellation, and truncation. Do not use `UpdateCommandRunner` for mutation.
2. Extend `BoundedProcessRunner` only through a backward-compatible operation-specific dual-stream API, preserving every existing read-only caller and capture-stream behavior. Poll both pipes so a noisy stderr cannot deadlock stdout. Capture at most 1 MiB per stream, retain bounded prefixes with explicit truncated flags, and terminate on overflow.
3. Preparation and confirmation revalidation each have a separate 60-second monotonic read-only budget; user review time between them is excluded. Mutation process timeout is 120 seconds; npm per-request timeout is 30 seconds; retries are zero. On cancellation after launch, send SIGTERM to the exact process group, allow 2 seconds, then SIGKILL and bounded reaping/join. No orphaned process or unjoined runner may remain. Timeout and output overflow follow the same interrupted path.
4. Cancellation before launch returns `.cancelled` with zero mutation. After launch return `.interrupted` or `.uncertain` as appropriate, never “rolled back” or “unchanged.” Always reconcile after a launched process, including nonzero exit, cancellation, timeout, overflow, and window closure.
5. `OperationOutcome` retains separate stdout/stderr data, truncation flags, exit status when available, typed state (`succeeded`, `failed`, `cancelled`, `interrupted`, `uncertain`), reconciliation delta when available, and cleanup warnings. Output is in-memory only. Evidence uses secret-free fixtures; never print captured environment or auth configuration.

### C05 — reconciliation and native presentation

1. After every launched operation, perform a fresh login-shell/local inventory rescan and explicit ownership verification of the resulting selected installation where possible. Old proof is expected to change; verify the new package/prefix/manager/selection instead of comparing it to the old fingerprint.
2. `.succeeded` requires npm exit 0 **and** fresh ownership plus the selected local version semantically equal to the reviewed stable target (compare parsed versions, not decorative raw prefixes). Exit 0 with a different/missing version is not success. Nonzero exit can still leave changes; display the observed delta rather than claiming no effect. Failed/inconclusive rescan or ownership produces `.uncertain` with the process result retained.
3. Compare before/after inventory and diagnostics: selected version, entry/target, aliases, winner/shadowed installations, install state, and ownership. Show the actual PATH-winner change; do not claim the whole tool disappeared or that only one filesystem entry changed.
4. Add native preparation progress, confirmation sheet, executing/cancelling states, and result view. Result output has separate monospaced scrolling stdout/stderr sections, exit status, truncation/cleanup warnings, and the delta. All dynamic values are plain text, not shell interpolation.
5. `InventoryViewModel` remains the only app state owner and all preparation/execution/reconciliation belongs to its single slot. Window closure cancels and joins the operation, performs required bounded reconciliation, and a subsequent launch shows current local facts. No stale completion may attach to another selection or generation.
6. Do not add CLI mutation syntax. Use the shipping CLI only for read-only post-operation parity checks.

## 5. File authority for implementation

Modify only these existing files and add only these named new files. A needed change elsewhere is a stop for a bounded revision.

- `Sources/AgentLensCore/Updates/NpmUpdateProbe.swift` — shared internal fresh observation only; preserve M10-B behavior.
- `Sources/AgentLensCore/Process/BoundedProcessRunner.swift` — backward-compatible dual-stream operation support only.
- Add `Sources/AgentLensCore/Operations/NpmUpdateOperation.swift`, `OperationModels.swift`, and `OperationProcessRunner.swift`.
- `Sources/AgentLensAppSupport/InventoryService.swift` and `InventoryViewModel.swift`.
- `Sources/AgentLensApp/MainWindow.swift` and `ToolDetailView.swift`; add `Sources/AgentLensApp/UpdateOperationView.swift`.
- Add `Tests/AgentLensCoreTests/NpmUpdateOperationTests.swift` and `OperationProcessRunnerTests.swift`.
- `Tests/AgentLensCoreTests/NpmUpdateProbeTests.swift` only for shared-observation regressions.
- `Tests/AgentLensAppSupportTests/InventoryServiceTests.swift` and `InventoryViewModelTests.swift` only for operation integration/state.
- Add `Tests/Fixtures/M10C/npm_update_acceptance.py` as the secret-free disposable real-npm/controlled-registry fixture harness, using only the Python standard library. It is test code, not a shipping dependency.
- `README.md`; add `walkthroughs/M10-C-implementation.md` for worker evidence. Coordinator owns acceptance/index/roadmap/status records.

DO NOT TOUCH: `Package.swift` or dependencies; bundled registry/schema/resources; `Sources/agent-lens/main.swift`; other Core process/update/ownership/Homebrew files; other app views; CI workflows/gates/count floors; packaging/builder/guard scripts; scope/decisions/roadmap; historical briefs/walkthroughs; personal installations, caches, npmrc, shell files, or global toolchain. Do not weaken or skip existing tests/timeouts/assertions.

## 6. Acceptance matrix

Every row requires raw secret-free argv/stdout/stderr/exit/elapsed receipts and exact candidate identity. Worker evidence is not coordinator acceptance.

| ID | Setup and observation | Pass requirement |
|---|---|---|
| M10-C-AC01 eligibility | Cached/fresh badges, up-to-date/older/ahead/prerelease/malformed/offline/unknown, winner/off-PATH/shadowed/ambiguous selections | Only fresh verified newer stable npm target prepares; no cache/ownership hint authorizes; no mutation launch |
| M10-C-AC02 preview | Scoped/unscoped packages, spaces/metacharacters in owned paths, dependency/script-bearing fixture | Exact package@version/prefix/registry/argv/effect displayed; no @latest/shell string; dependency, lifecycle, and no-sandbox scope disclosed |
| M10-C-AC03 pre-launch cancel | Cancel during preparation and pending confirmation; repeated Cancel; operation root removed/replaced while waiting | Zero mutation spawn, unchanged package/prefix/sentinels, slot and owned scratch released safely, no stale plan |
| M10-C-AC04 stale confirmation | After preview change target/manager/package/prefix/root/manifest/bin/selection/registry/local version/latest tag/operation-root identity; include custom route and moving latest | Fresh local scan plus full fresh comparison refuses before mutation and demands a new preview; no fallback package/version/registry |
| M10-C-AC05 controlled success | Real npm, disposable prefix, controlled registry, old script-free fixture → newer exact target | One exact-version install; separate output/exit0; fresh ownership/version matches; correct delta; unrelated prefix/package unchanged |
| M10-C-AC06 operation failure | Nonzero npm, registry/network failure, lifecycle failure, permission denial, engine/script-policy refusal, exit0 but wrong/missing version | Output and exit retained; no retry/fallback; post-state measured; exit0 never alone means success |
| M10-C-AC07 concurrency | Double Confirm, replayed plan, simultaneous tools, Confirm plus Rescan/Check/selection | Core gate permits at most one mutation; other actions coalesce/invalidate without retargeting |
| M10-C-AC08 interruption | Cancel before/after spawn, delayed child, timeout, output overflow, actual window closure | Bounded TERM/KILL/reap/join; no orphan; cancelled only before launch, interrupted/uncertain after; mandatory reconciliation |
| M10-C-AC09 dual-stream runner | Large interleaved stdout/stderr, one stream silent, invalid UTF-8, spawn failure, timeout, truncation | No deadlock; 1 MiB bound per stream and explicit flags; existing read-only process tests unchanged |
| M10-C-AC10 reconciliation | Aliases/shadowed copies, winner change, ownership/rescan failure, nonzero-after-change, scratch cleanup failure | Truthful delta and typed outcome/warnings; no unchanged/rollback/atomicity claim; stale output cannot attach elsewhere |
| M10-C-AC11 native controlled flow | Unchanged product views in controlled native host, real npm and owned registry transport substitution only outside production | Prepare/Cancel/Confirm/output/rescan observed; original versus executed transport argv recorded; host evidence not mislabeled ordinary app |
| M10-C-AC12 actual app/public npm | Ordinary built app with no injected service/runner/debug switch, isolated public Codex old stable → current stable latest in disposable prefix, synthetic HOME/config/cache and sandbox | Actual shipping preparation/confirmation/result flow works; target observed from fresh metadata; shipping CLI offline agrees afterward; personal paths untouched |
| M10-C-AC13 isolation and scope | Secret-free fixture HOME/config, personal-cache/install denials, unrelated sentinels, protected-file hashes | Only owned prefix/scratch changes; no custom production registry; no credentials/environment dumps; allow-list and cleanup verified |
| M10-C-AC14 regression/hosted | Full local gates, fresh debug app/packaging, exact candidate hosted CI | All pre-existing 468 Swift tests plus additions, zero skips/failures; guard 21; packaging 9; all seven exact-SHA hosted gates pass |

## 7. Required fixture and native recipes

### Deterministic controlled registry

`Tests/Fixtures/M10C/npm_update_acceptance.py` must create only beneath an operator-supplied owned evidence root E:

- Tiny tarballs for the validated fixture package identity with a `codex` bin reporting exact versions 1.0.0 and 2.0.0, plus `next` 3.0.0-beta.1. Include a separate harmless dependency/lifecycle fixture whose effects stay inside E.
- Synthetic HOME, user/global npmrc, cache/log roots, prefix, closed PATH with existing npm/Node, fixture registry JSON validated by Core, and an unrelated package/prefix sentinel manifest. No shipping registry edit.
- Owned loopback registry serving exact packuments/tarballs and recording requests. Start/stop/join only its recorded PID; never leave a server running.
- Real npm installation of old fixture into the owned prefix before scenarios. Production operation argv must first be asserted by the external harness; only then may the harness substitute public base/scope registry flags with the owned loopback endpoint. Record original and executed argv. Production has no loopback/custom-registry switch.

The controlled native host may compile unchanged product views and inject services/runners as in M10-B. It is deterministic native evidence, not the ordinary-app gate.

### Ordinary app and public npm

Use the shipping detector registry and real public npm metadata. The harness selects an older stable public Codex and current stable `latest`, installs the old exact package only into E's prefix, and verifies the fixture `codex --version`. If no suitable older stable package or required public transport is available, mark AC12 BLOCKED with evidence; do not substitute a fake or personal installation.

Launch the ordinary built app with synthetic login-shell HOME/ZDOTDIR/PATH/TMPDIR and Seatbelt denials for personal AgentLens/npm caches, npmrc, off-PATH tool roots, and writes outside E. It uses the production service, runner, registry, and public route—no injected transport or debug switch. Exercise preview → Cancel (hash unchanged) → fresh preview → Confirm → output/delta. Then run the current shipping CLI `scan --offline` against the same isolated environment and compare facts. Controlled-host success cannot waive this gate.

## 8. Verification commands and evidence

From repository root, create one owned evidence root and record its absolute path. E is never a cleanup target; the harness removes only recorded owned children and preserves receipts.

```sh
E=$(mktemp -d /private/tmp/agent-lens-m10c-acceptance.XXXXXX)
mkdir -p "$E/worker" "$E/parent" "$E/fixtures"
```

Use inherited TMPDIR with Agent Lens test overrides unset for default gates. Use fresh worker/parent roots beneath E; do not run timing-sensitive suites concurrently. Before dispatch the coordinator runs these baseline gates against the pinned unmodified baseline and verifies the selected route and fixture/public transport; any failure is BLOCKED, not a skipped gate.

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
swift test --no-parallel --filter NpmUpdateOperation
swift test --no-parallel --filter OperationProcessRunner
PRODUCTS="$E/parent/products"
swift build --scratch-path "$PRODUCTS"
BIN_DIR=$(swift build --scratch-path "$PRODUCTS" --show-bin-path)
python3 Tests/Fixtures/M10C/npm_update_acceptance.py \
  --root "$E/parent/controlled" --scenario controlled \
  --cli "$BIN_DIR/agent-lens" --products "$PRODUCTS"
python3 Tests/Fixtures/M10C/npm_update_acceptance.py \
  --root "$E/parent/public" --scenario prepare-public \
  --cli "$BIN_DIR/agent-lens" \
  --app "$E/parent/debug-app/AgentLensApp-debug.app"
```

The controlled scenario runs deterministic Core/CLI/native-host scenarios. `prepare-public` creates the isolated old installation and owned fixture state only beneath its root, prints the exact ordinary-app launch recipe, and records hashes/sentinels; after the coordinator performs the native journey, `--scenario verify-public` with the same root/CLI/app arguments checks final CLI parity, sentinels, process/server cleanup, and owned cleanup. Preparation refuses a pre-existing root; verification requires the root's recorded ownership identity. The harness never deletes or adopts a non-owned root.

Build a fresh current candidate for the harness and native host; never mix baseline Core/AppSupport objects with candidate views. Record the exact binary/module paths. The public-app recipe and raw interaction receipts are mandatory separate evidence. Local TestingMacros fallback, if needed, follows M10-A exactly and never changes hosted commands.

Baseline failures stop dispatch for adjudication. Final acceptance inventories exact passed test names/counts and rejects zero-test exit 0. Worker returns touched files/hashes, requirement-to-evidence matrix, all raw receipts, screenshots, scope/protected-file proof, process/server cleanup, and limitations. Coordinator independently reruns the gates, observes controlled and ordinary native journeys, and obtains pinned independent read-only safety review. Exact-SHA hosted CI follows separate Git authorization. UI approval and Git delivery remain separate.

## 9. Stop and done conditions

Stop for missing worker route/npm/Node, unavailable isolation or public fixture, ambiguous ownership/registry/target, need outside the allow-list, new dependency/privilege/credential/publication request, inability to capture both streams or join processes, unexpected file changes, or any personal-installation/cache effect. Report facts and request a bounded revision; never improvise or edit this frozen brief during implementation.

Done only when M10-C-AC01–14 all pass on one frozen candidate, material review findings are closed, all required real/native evidence exists, and no placeholder remains. M10-C acceptance does not accept M10 as a whole or authorize M10-D.

## 10. Planning verification and freeze

R0 received a dedicated safety/npm-semantics review. R1 added fresh local version measurement at confirmation, final live proof and operation-root checks, process-wide mutation exclusion, explicit preparation/revalidation budgets, semantic post-version comparison, and an explicit warning that package scripts are not sandboxed. It also bound operation-root identity and cleanup through the complete preview lifecycle.

The separate R1 executability/completeness review produced R2: named operation runner/gate injection seams, exact evidence-root setup, required binary/products/app harness arguments, separate controlled/prepare-public/verify-public scenarios, a standard-library-only fixture constraint, and an explicit production-only ordinary-app path. Both revisions are coordinator self-review; no council review is claimed.

Final mechanical checks verified sequential AC01–AC14 rows, balanced code fences, required sections, local links, command exclusions, and harness scenarios. Freeze clarifications only made public-root ownership semantics and the unchanged guard count explicit. The brief is now frozen. Planning freeze does not attest that future baseline, implementation, runtime, native, or hosted gates have passed and does not authorize implementation.
