# M10-C — confirmed npm Update implementation

Status: **candidate implementation, uncommitted, locally verified, not accepted**. M10-C remains
blocked on independent review/acceptance and hosted AC14; M10-D is out of scope.

- Branch: `codex/m10-npm-management`
- Starting commit: `7ff71b67a665d405fe163b7908b8336d5b45e51e`
- Starting content includes the accepted uncommitted R1 baseline repair.
- Writer: River Pi, provider `river`, model `deepseek-ai/DeepSeek-V4.1-Flash-1017`, thinking `max`.
- Evidence root: `/private/tmp/agent-lens-m10c-acceptance.TcBGo0/m10c-impl.4CODUE`.
- No Git staging, commit, push, or publication was performed.

## Implemented surface

- Core fresh npm observation is shared by preparation and confirmation and never reads/writes the
  Check/Refresh metadata cache.
- `NpmUpdateOperation.prepare` returns an opaque preparation with a public preview and internal
  proof/environment/route/operation-root authorization evidence. It claims a mode-0700 owned root.
- Confirmation rescans locally, repeats ownership/route/latest observation, compares every bound fact,
  revalidates the live proof and root, consumes the preparation through a process-wide gate, and runs
  one literal exact-version npm install.
- `ProcessOperationCommandRunner` uses a dual-stream runner with process-group TERM/KILL cleanup,
  cancellation, timeout, per-stream 1 MiB prefixes, truncation flags, and current-directory support.
- Reconciliation measures before/after inventory and ownership; exit zero alone is not success.
  A launched process with no observed exit status is uncertain, not failed. A scratch-cleanup refusal
  after a proven successful update retains success and adds a cleanup warning.
- The app service/view-model own preparation, confirmation, cancellation, stale invalidation, and the
  single operation slot. The native sheet scrolls its complete preview/result and keeps its actions in
  a fixed footer so long fixture paths cannot hide the heading or Cancel/Confirm/Done.
- `AgentLensTerminationDelegate`/`AppLifecycleGate` owns termination waiting. `MainWindow` registers
  `shouldWait = model.isBusy || activeActionTask != nil || model.isUpdateSheetPresented` and
  `cancelAndJoin` calls both `model.cancel()` and `model.cancelUpdate()`. This covers an idle prepared
  sheet holding an operation root, not only an in-flight preparation/execution.
- `WindowCloseObserver` no longer replaces the NSWindow delegate. It retains only the will-close
  notification hook; the previous `forwardingTarget` proxy/`responds(to:)` hazard and the obsolete
  close-gating delegate were deleted. The notification path releases pending state; App termination
  owns the actual join.
- No CLI mutation command was added; no shipping debug switch was added.

## Final identities

- `agent-lens`: `0748ac423fa48b0f1971c3392a9ce8ba134bb089a23f11da937c6334b1b6df1c`
- AgentLensCoreTests: `7849d538cb51b0433c2673403ffa15c17510e5700b021392edd176996dc3bc9f`
- AgentLensAppSupportTests: `626b2912efa681ccd7630a3b3a9ab69406e6c920bbdf5dd782082e9b73738dc6`
- Final debug app: `d860e9d38c67c9f81bf0c77ec668536a2bde88bcbd7c0c46293a9653ffcee544`
- MainWindow: `d1e1b3240c00e20c24a1061df22de29434055ffdfb038c3a5b92f3a0982e0dfe`
- Fixture: `d551ebb2b564b1e3a7e9a6354ebc5779f6651510fab721bf9a2b5c26d9e56413`
- R1 files unchanged: `e4154a6f…`, `dd89a822…`, `8cb44582…`.

## Local gates

Parent's independent fresh run11: **434 Core + 76 AppSupport passed in both no-TTY and PTY**, with all
469 starts accounted for and 22 before/after hashes unchanged; packaging 9, guard/build/app exit 0.
These Core/Test sources are unchanged by the MainWindow-only lifecycle repair. Receipts:
`parent/final-gates-run11.log`, `parent/final-gates.json`.

After the MainWindow repair, the app was rebuilt and packaging/guard rerun in this slice:

| Check | Result | Receipt |
|---|---|---|
| App build | exit 0 | `parent/r3-app-build.out/.err` |
| Core/UI guard | exit 0 | `parent/r3-guard.*` |
| Guard fixtures | exit 0 | `parent/r3-guard-fixtures.*` |
| Packaging | 9 tests OK | `parent/r3-packaging.*` |
| `git diff --check` | exit 0 | working tree |

Core/Test binary hashes remained exactly `7849d538…` and `626b2912…`.

## Helper/fixture corrections

### Compiler isolation

Both the Core test-host compile and the native shipping-view host compile now use one owned compiler
environment and explicit module cache:

- `HOME`/`CFFIXED_USER_HOME` = `<root>/compiler-home`
- `TMPDIR` = `<root>/tmp`
- `CLANG_MODULE_CACHE_PATH` = `<root>/clang-module-cache`
- argv includes `-module-cache-path <root>/clang-module-cache`
- compile runs under the same strict write envelope (`ordinary-app.sb`).

Final receipts: `parent/harness-r3-controlled3-root.txt` →
`receipts/controlled-compile.json` and `receipts/controlled-native-compile.json`, both exit 0. The
native compile profile additionally allows read access to the repository's shipping-source paths;
writes remain confined to the owned root. No personal compiler/temp cache was used.

### Reproducible native journey

`controlled()` keeps the Core prefix proof at `2.0.0`, but seeds a **distinct** `native-prefix` at
`1.0.0` with real npm. `native-seed.json` records the real npm-created bin inode/target and the alias;
no fixture-created npm bin is used. The native recipe points at `native-prefix` and
`native-alias-bin/codex`, so a fresh workflow starts at old and offers Prepare.

The native operation transport now asserts the reviewed original public base and scope **before**
rewriting:

- original `--registry=https://registry.npmjs.org/`
- original `--@openai:registry=https://registry.npmjs.org/`
- only then maps both to the owned loopback endpoint
- records `registryGuard: reviewed-public-base-and-scope`

Final native full flow: app `4357`, window `6146`, `1.0.0 → 2.0.0`, exit 0, actual npm mutating the
native prefix. `native-result.json` records the owning root, native seed, registry PID/stop/join,
argv guard, and empty operation base. `record-native` reports:
`RECORD-NATIVE OK ... version=2.0.0 registry_stopped=yes`.

The generated native and close recipes are executable `/bin/sh` scripts that:

- use `/usr/bin/env -i` with shlex-quoted owned `HOME`, `ZDOTDIR`, `TMPDIR`,
  `CFFIXED_USER_HOME`, `PATH`, and synthetic npm config (`userconfig`, `globalconfig`, cache, logs,
  prefix);
- start the recorded registry, wait for `native-base.txt`, launch under the strict profile, and use
  the recorded-PID `stop-native` identity check in a cleanup trap;
- remove stale close-trigger before launch.

The ordinary public recipe uses the same clean `env -i` form. Native raw captured environment pins the
owned user/global npmrc, cache, logs, and prefix so the operation cannot consult the allowed tool-root
global npmrc.

### Permission failure correction

The prior failure flow left the registry packument empty after the deliberate registry failure, so the
"permission" invocation reported `ENODATA`. Before the permission scenario the fixture now resets a
valid packument and tarball set, makes the owned prefix/bin unwritable in the host runner, and requires
the operation stderr to contain `EACCES` or `EPERM`. Final receipt root
`parent/harness-r3-controlled5-root.txt` records `npm error code EACCES`, `syscall rename`, exit 243,
measured after-version `1.0.0`, raw stdout/stderr, one operation (argv record count 2), `noRetry=true`,
and unchanged sentinel manifests. No permanent wording assertion exists outside this disposable
fixture.

### Public fixture

`parent/harness-r3-public6-root.txt` → root `harness-r3-public6-1793645851`:

- `PREPARE-PUBLIC OK old=0.165.0 latest=0.166.0 strict-older=yes`
- immutable profile SHA-256 `f59d4ee042bef4d69be4457454ace129e163c2da5d0993db45ff9a04cab6f5c5`
- `VERIFY-PUBLIC OK sentinels=2 sandboxed=yes`
- Final app UI Check → Prepare → Confirm succeeded `0.165.0 → 0.166.0`, exit 0, actual npm; result
  receipt `public-final-result.txt`; post-update verify also `VERIFY-PUBLIC OK`.
- Idle ordinary-app close with the final app (PID `3561`, Cmd-W after front): `idle-close.txt`,
  app gone.

## Lifecycle evidence

- Original red: direct `NSWindow.close()` during a delayed TERM-resistant child left the child at
  ppid 1. The raw `close-app.err/.out` files are zero bytes and are **not** cited as raw output. A
  truthful attestation quoting the worker report is `worker/AC08-red-attestation.md`: app PID 86953 /
  window 5412, child 87296 ppid 1, provenance `worker/R2-final-evidence.md`; no old failure was rerun.
- Active close green on the repaired source: root
  `parent/harness-r3-controlled3-root.txt` → `active-close-green.txt`; delayed child `4006` gone,
  app `3824` gone, operation base has no child. Same direct `window?.close()` trigger.
- Idle **prepared preview** green: same final root → `prepared-preview-green-final.txt`; sheet showed
  Installed 1.0.0 / Target 2.0.0 with a claimed operation-base child before close; after direct close
  app `4127` was gone and the operation base had no entries. The old 2c1 prepared-close trial released
  its root because the asynchronous will-close cleanup won the race, so no new red is claimed from
  that trial; the gate condition was nevertheless false while a prepared sheet existed and is now
  explicitly covered.
- Idle ordinary-app close final: `parent/harness-r3-public6-root.txt` → `idle-close.txt`.
- B6: obsolete NSWindowDelegate replacement/forwarding is deleted; only the will-close notification
  hook remains. No `forwardingTarget`/missing `responds(to:)` proxy hazard remains.
- Repeated-termination coalescing remains implemented but not separately runtime-measured.

## AC matrix

| ID | Status | Evidence / limitation |
|---|---|---|
| AC01 eligibility | PASS | Actual app exposed Prepare only for verified `updateAvailable` npm Codex; service guard refuses missing update; eligibility tests green. |
| AC02 preview | PASS | Public/controlled previews and AX show package@version, prefix, registry/tag, manager, cwd, literal argv, effect text; clean-env recipe. |
| AC03 cancel | PASS | Actual Cancel preserved prefix/sentinels, removed the sheet, fresh Prepare succeeded; service/Core cancel tests green. |
| AC04 stale confirmation | PASS | Production-boundary Core tests cover target/selection, manager, package/manifest, prefix, root, bin, registry, scoped route, local version, moving latest, owned-root drift; zero operation-runner invocation and refusal. |
| AC05 controlled success | PASS | Controlled native host real-npm/loopback update succeeded with exact one argv, exit 0, fresh `1.0.0 → 2.0.0`, matching target/ownership/delta; sentinels unchanged. |
| AC06 operation failure | PASS | Six actual real-npm failures (registry/tarball/network/permission/lifecycle/engine) each one launched operation, nonzero exit, retained raw stdout/stderr/after-state, `noRetry=true`, unchanged sentinel manifests: final root `parent/harness-r3-controlled5-root.txt` → `controlled-failures.json`. Permission was reset to a valid packument before the scenario and asserts actual `EACCES` (`rename` denied), not any nonzero. |
| AC07 concurrency | PASS | Gate acquisition/replay tests prevent a second process; ViewModel owns one slot and invalidates competing actions. |
| AC08 interruption/lifecycle | PASS | Active direct-close green (child `4006` and app gone, operation base empty); prepared-preview close green (root released); idle ordinary-app close green. B6 proxy deleted; termination gate waits on sheet state and joins both cancel paths. Repeated coalescing runtime case not separately measured. |
| AC09 dual-stream runner | PASS | Interleaved streams, per-stream truncation, working directory, timeout, cancellation, spawn failure, delayed child, overflow tests pass. |
| AC10 reconciliation | PASS | Alias/same-target success, different-target uncertain, nonzero-after-change, failed-rescan uncertainty, ownership/selection refusal, cleanup-warning success with retained state/message; actual success/uncertain/interrupted native views recorded. |
| AC11 controlled native host | PASS | Reproducible fixture compiles shipping views against injected service; exact PID/window-bound screenshots/AX, clean recipes, transport guard, actual npm-created native bin, successful full journey, and registry stop/join retained. |
| AC12 actual app/public npm | PASS | Final app public Check → Prepare → Confirm `0.165.0 → 0.166.0` exit 0; receipt `public-final-result.txt`; idle close and post-update CLI parity verified under strict profile. |
| AC13 isolation/scope | PASS | Final public6 strict profile denies writes outside the owned child and personal-home reads; preview/result show E-root working directory; both sentinels manifest-identical; controlled fixture verifies sentinels, actual npm bin, lifecycle/dependency markers, empty owned cache sentinel, registry PID/stop/join. |
| AC14 regression/hosted | PARTIAL | Local build/all suites (434+76, no-TTY and PTY), app, packaging, guard, diff-check pass. Exact-SHA hosted CI remains external/unauthorized. |

## Limitations / stop conditions

- AC14 hosted exact-SHA CI remains external.
- Independent Perch (`glm-5.3-flash-starter`, max) and Qoder (`Qwen3.8-Max`, xhigh) both issued
  SOURCE + LOCAL-EVIDENCE PASS with no remaining material findings on reviewed manifest
  `0741a703bfc0609933c6701643d48081c8c7d28d6f211c309501d711a037cfeb`. The coordinator
  independently matched its source/test hashes; the section below adds coordinator provenance.
- Repeated-termination coalescing is structurally implemented but not separately runtime-measured.
- `.npmrc` and the AgentLens personal cache are absent in the controlled home; literal denial is not
  overclaimed.
- At this pre-delivery local freeze, no Git staging, commit, push, or publication was performed.
  Git delivery and hosted exact-SHA CI require separate owner authorization.

## Touched paths (candidate)

See `worker/R2-final-manifest-final.txt` for the reviewed source/test/product hash map and
`worker/R2-final-evidence-final.md` for the worker evidence index. The coordinator's documentation-only
appendix below follows that reviewed input; production source and tests remain unchanged. The
implementer did not alter `Package.swift`, CLI mutation syntax, bundled registry/schema, CI,
packaging scripts, or R1 source/tests. Coordinator status-document changes are separately identified
in the protected-integrity receipt.

## Coordinator independent local verification

Parent evidence root:
`/private/tmp/agent-lens-m10c-acceptance.TcBGo0/m10c-impl.4CODUE/coordinator-final-r3-i1lp9yh4`.
The structured index is `acceptance-summary.json`; raw command/exit receipts, AX snapshots, and
exact PID/window-bound images remain private under that root.

- Fresh independent full suites produced **510 starts and passes in each TTY/detached context**,
  no skip markers, and all 469 accepted R1 event identities. The TTY premise was measured true.
  `test-inventory.json` and `gates/` retain the proof. After the private MainWindow-only correction,
  unchanged Core/AppSupport/test hashes justified reusing those suites; a fresh final app build and
  all nine packaging checks passed (`app-final-gates.json`).
- The final named controlled workflow passed independently with parent-built objects. The corrected
  permission case produced real `EACCES`, syscall `rename`, exit 243, measured version 1.0.0, and
  unchanged sentinels, not the superseded ENODATA result (`controlled-permission-final/`).
- Unchanged shipping views in the controlled native host exercised Check, Prepare, Cancel, fresh
  Prepare, Confirm, separate output/result, Done, and close. Cancel preserved the complete prefix
  content/identity/mtime fingerprint. Real npm updated **1.0.0 to 2.0.0**, exit 0, with original public
  base/scope pins asserted before loopback substitution. The inspected result sheet is
  `parent-native-success/07-result-sheet.png`; result, argv, registry stop/join, and empty operation
  base are retained alongside it.
- The ordinary packaged app, without injected services/runners/debug switches, exercised the same
  journey against public npm: **0.165.0 to 0.166.0**, exit 0. Cancel preserved the complete prefix
  fingerprint; the shipping CLI agreed under the same immutable sandbox/environment, with both
  sentinels unchanged. The actual update took 47 seconds; an early ten-second UI wait expired
  without resubmitting, then completion was observed. Evidence: `parent-public-app/result.json`,
  `09-public-result-sheet.png`, and `10-verify-public.stdout`.
- The same direct `NSWindow.close()` trigger during a launched TERM-resistant child left app PID
  12453 and child PID 13434 gone, operation base empty, and the recorded registry stopped/joined
  (`parent-active-close/result.json`). A fully settled prepared confirmation held an owned root
  before close and released it with zero mutation (`parent-preview-close/result.json`).

Repeated Quit behavior is **not claimed runtime-proven**. Modal input did not invoke Quit; extra
test-host synchronous `NSApplication.terminate` controls entered the documented modal run loop and
were not valid repeated-event proof. Their receipts are excluded from acceptance and their owned
processes were cleaned. The speculative per-callback-reply finding was withdrawn against the
[AppKit termination contract](https://developer.apple.com/documentation/appkit/nsapplication/terminate(_:));
no extra latch reset, force-exit, or abandoned detached work was added.

Both selected reviewers cleared the final source/local evidence; exact-SHA hosted CI is the
remaining external acceptance gate. This local verification neither accepts M10 as a whole nor
authorizes M10-D, merge, release, or publication.
