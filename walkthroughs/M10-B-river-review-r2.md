# M10-B — independent implementation review, R2 recheck (River Pi DeepSeek V4.1 Flash1017, thinking=high)

**Verdict: PASS — no blockers, no required changes.** RC1 and RC2 are closed by the two-file code delta, and the close is evidenced both in source/tests and in retained raw receipts (including the pre-fix red run).

I performed this as a fresh read-only recheck: no edits, no builds/tests/npm/network/installs, no git mutation, no subagents, no tree-wide content searches (bounded `rg` on `Sources/` and `Tests/` and exact receipt reads only).

---

## 1. Identity and pin verification I actually performed

- Repo/Branch/HEAD unchanged: `b667be6a177d42f26def815e9acd6f801aa6d52c`, `codex/m10-npm-management`, candidate still **uncommitted**.
- **New pinned manifest recomputed**: `recheck-candidate-manifest.json` 249 entries → **249/249 present, 0 missing, 0 hash mismatches.**
- **Frozen brief** `briefs/M10-B-npm-latest.md` = `1270cb3dc660195c71e67977f6bbab883e9b0dcbb730e34c484f4c424ec0c35c` — matches; unchanged.
- **Delta vs my pinned R1 manifest** (`E/parent/river-final-review/candidate-manifest.json`, 201 entries) recomputed myself: exactly **4 changed** = `Sources/AgentLensCore/Updates/NpmUpdateProbe.swift`, `Tests/AgentLensCoreTests/NpmUpdateProbeTests.swift`, `briefs/M10-B-R1-coordinator-corrections.md`, `walkthroughs/M10-B-coordinator-verification.md`; **0 removed**; **48 added** = the `river-corrections-evidence/` set + `M10-B-river-corrections.md` + my retained `M10-B-river-review-r1.md`. So the code delta is exactly the two allow-listed files, as `delta-from-river-r1.json` states.
- Transitive scope proof: because only those 4 files changed since R1 (whose protected-scope check I ran myself and which had `unexpected_changed_baseline_paths: []`), no protected file, dependency, CI, registry, packaging/builder/guard, or toolchain file changed. `git status` agrees (all modified/untracked paths are allow-listed or coordinator records).
- Evidence set `SHA256.json`: **45/45** files present and matching.
- Gate receipts read (all raw, all final-candidate): `build.*`, `full-tests.*`, `core-ui.*`, `guard-fixtures.*`, `debug-builder.*`, `packaging.*`, `diff-check.*`, `red.*`, `targeted.*`, `native-compile.json`, `transport-compile.json`, `transport/*`, `cli-transport/*`, `native/*`. I also read `cli-transport/bin/npm` in full.

## 2. RC1 closure — the four ownership queries now have an observed derived-environment regression

**Requirement** (`briefs/M10-B-npm-latest.md`, B02.5): *"Add a regression proving all four ownership queries receive the override and no real-cache trap is touched"*, with the derived-env rule = copy `raw`, drop case-insensitive cache/logs/notifier duplicates, set canonical `NPM_CONFIG_CACHE`/`NPM_CONFIG_LOGS_DIR` to this invocation's owned root and `NPM_CONFIG_UPDATE_NOTIFIER=false`.

**Product (unchanged, and correct as written):** `npmEnvironment` `NpmUpdateProbe.swift:318-334` (duplicate removal `:323-327`, canonical sets `:328-330`); `derivedScratchEnvironment:338-349`; threaded into the verifier at `verifyOwnership:996-998`; consumed by `NpmOwnershipProbe.query` via `environment.raw` (`NpmOwnershipProbe.swift:355-368`).

**Test:** `everyNpmInvocationOverridesInheritedCacheLogsAndNotifierIncludingFourOwnershipQueries` (`NpmUpdateProbeTests.swift:1346-1422`), enabled by `RecordingNpmRunner.Invocation` capture (`:201-215`) and `noteCall` snapshotting `environment` plus live `lstat` mode (`:283-296`). It seeds inherited `npm_config_cache`, `Npm_Config_Cache`, `NPM_CONFIG_LOGS_DIR`, `npm_config_logs_dir`, `Npm_Config_Update_Notifier`, `npm_config_update_notifier`, overrides `TMPDIR`, and creates two sentinel trap dirs with a byte-checked file each. It then asserts, across **all 10** recorded launches:

- `:1389` exactly 10 invocations (4 ownership, 4 config, 1 view, 1 version — I traced the flow `:666-700`, `:716-723`, `:768-785`, `:791-798`, `:799-852`, `:878-884` and the count is right); `:1390-1391` 2×`prefix` + 2×`root`.
- `:1394-1397` canonical cache/logs keys present, notifier exactly `"false"`, `TMPDIR` preserved verbatim.
- `:1399-1401` **exactly one surviving key per case-insensitive name, spelled canonically** — this is the assertion that would fail if a duplicate spelling survived.
- `:1402` cache dir mode observed as `0o700` *while the command was live* (not after cleanup).
- `:1403-1404` the root is a direct child of the injected base; `:1405` every claimed root is gone afterwards.
- `:1408-1413` the two ownership groups each share one root and the final group's root is distinct from the initial group's — i.e. the four ownership queries are individually observed, with group semantics.
- `:1414-1415` base has no leftovers; `:1416-1421` both trap dirs still contain only `sentinel` and the bytes are identical.

**Why it is a real regression, not a tautology:** if production passed the *base* environment, `NPM_CONFIG_CACHE` would be the trap path → `:1396`, `:1401`, `:1402`, `:1403` all fail; if the duplicate loop dropped the wrong spelling, `:1399-1401` fails; if a group root leaked, `:1405`/`:1415` fail. The `red` receipt proves these assertions execute and pass against the intended code path (only the harness-only `Set(roots).count == 8` assumption failed, `red.stdout` line: `Set(roots).count → 6`). `targeted.stdout` shows both corrected regressions passing. I grepped the test file and `Set(roots)` is indeed absent now.

**RC1: CLOSED.** The brief also forbids touching real personal caches here; the traps are synthetic and untouched, and production `~/.npm` isolation is unchanged.

## 3. RC2 closure — the metadata `view` refusal now reports by cause, and task cancellation stays neutral

**Product:** `metadataView` now takes `uptime`/`stageDeadline` (`:1053-1063`) and, after a failed runner call, keeps `timedOut → queryTimedOut` and `outputLimitExceeded → metadataInvalid` but routes the rest through the pre-existing cause-aware helper (`:1088-1093`): `configFailureReason(failure, aggregateDeadlineExhausted: uptime() >= stageDeadline, taskCancelled: Task.isCancelled)`. `configFailureReason` (`:199-209`) yields `.budgetExhausted` only for `.cancelled && deadlineExhausted && !taskCancelled`, `queryTimedOut` for `.timedOut`, `probeFailed` otherwise — identical to the config paths (`:243-245`, `:261-263`) and to the coordinator's Homebrew-side rule (`UpdateProbeCoordinator.swift:351`).

**Why the mapping is precise in production:** I checked every producer of `.cancelled`. `Sources/AgentLensCore/Process/BoundedProcessRunner.swift` contains no `cancelled` emission at all (bounded `rg` over the file: zero hits), so in production `.cancelled` *is* the coordinator's clipping refusal (`UpdateProbeCoordinator.swift:695-716`, `:707 return .failure(.cancelled)`). Genuine cancellation is represented by `Task.isCancelled` at the probe's own guards (`:768`, `:799`, `:878`), which is exactly the discriminator used. No other failure kind changed behaviour.

**Test:** `metadataDeadlineRefusalUsesBudgetReasonWhileTaskCancellationStaysNeutral` (`:1449-1482`) drives the real probe through `MetadataDeadlineRefusalRunner` (`:1418-1444`): at the `view` seam (after the pre-view guard passed, clock 0 < deadline 100) it advances the clock to 100 and returns `.cancelled` without forwarding a launch, running both the deadline-only and the actual-task-cancelled branch. It asserts `clock.get() == 100` (`:1470`, proves the seam was reached), reason `budgetExhausted` vs `probeFailed` (`:1471`), `provenance == .none` (`:1472`), **zero forwarded metadata launches** (`:1473`), **no persisted `npm-update-metadata-v1.json`** (`:1474-1477`), and **no leftover scratch child** (`:1478-1479`).

`red.stdout` is the decisive pre-fix evidence: the RC2 test failed with `npmProbeReason(result.status) → .probeFailed` where `.budgetExhausted` was required, in the same build tree where RC1's contract assertions already passed. `targeted.stdout` shows both tests pass after the correction, and `full-tests.stdout` shows both by name passing in the fresh full suite.

**RC2: CLOSED**, with no change to timeout/overflow semantics and no publication/cache on either branch.

## 4. Gates I could independently corroborate from raw receipts (read, not executed)

| Gate | Receipt evidence |
|---|---|
| Fresh `swift build` (fresh `final-products`) | `build.json` exit 0, 27.95 s, both Agent Lens overrides unset, inherited `TMPDIR`; `build.stdout` "Build complete" |
| Full suite, documented local macro-loading fallback only | `full-tests.json` exit 0, 82.86 s; `full-tests.stdout`: `397` Core + `71` AppSupport = **468**, both new tests present and passing (`:467-470`), **zero** `✘`/skipped; `full-tests.stderr` no errors |
| Core/UI guard | `core-ui.stdout`: 28 Swift files, no SwiftUI/AppKit imports, exit 0 |
| Guard behaviour fixtures | `guard-fixtures.stderr`: `Ran 21 tests … OK`, exit 0 |
| Fresh debug builder + original packaging | `debug-builder.json`/`.stdout` fresh `devapp/AgentLensApp-debug.app`, exit 0, 26.53 s; `packaging.stderr`: `Ran 9 tests … OK` |
| Whitespace | `diff-check.json` exit 0, empty streams |
| Protected scope | manifest delta (§1): only the 2 allow-listed code files; `ci.yml`, `Package.swift`, `scripts/**`, `Tests/Packaging/**`, `Sources/AgentLensCore/Process/**`, `ProcessUpdateCommandRunner.swift`, `HomebrewUpdateProbe.swift`, `UpdateMetadataCache.swift`, `VersionComparison.swift` all byte-identical to my R1 pin |

Runtime receipts cross-check the claims rather than merely restating them:

- **Contract shape is right**: `native-query-receipts.jsonl` has 29 launches = 2 ownership groups × (prefix+root) + 4 config + 2 views + 3 versions, i.e. **view omitted on the cache hit** and **2 views total** for Check-fresh/Check-cache/Refresh; Rescan launches nothing.
- **Exactly 6 metadata HTTP requests**: `transport/registry-requests.jsonl` has 6 lines, all `/@openai%2fcodex` — matching 2 headless + 2 actual CLI + 2 native views. My own count of view launches in the three receipt sets sums to 6, which independently reconciles the "six requests" claim.
- **Public pins asserted before transport substitution**: `cli-transport/bin/npm` asserts both `--registry=https://registry.npmjs.org/` and `--@openai:registry=https://registry.npmjs.org/` on the view, then substitutes *only* those two flags with the loopback endpoint and execs the real npm CLI; `argv.jsonl` retains `original` vs `executed`. Actual launcher argv for ownership calls (`prefix --global`, `root --global`) is unsubstituted, and every other call carries `--cache/--logs-dir/--no-update-notifier`.
- **Scratch and personal caches**: `transport/check1|check2|refresh.json` all show `scratchBase-before: []`, `scratchBase-after: []`, `personalCachesAgentLens: false`; cache hit preserves the original `18:09:08Z` observation across Check→Check and Refresh re-fetches (`18:09:10Z`).
- **CLI parity**: `cli-transport/check.json`/`refresh.json` run the final `final-products` binary under the fixture sandbox profile, exit 0, and render `latest known 2.0.0… source: npm metadata (npm package @openai/codex registry https://registry.npmjs.org/ tag latest; npm version 10.9.8)`, `1 update available`.
- Harnesses were compiled against the **corrected final objects**: both `native-compile.json` and `transport-compile.json` link `final-products/out/Products/Debug/{AgentLensCore.o,AgentLensAppSupport.o}`.

The R1 evidence-hygiene observation (#4) is thereby **closed**: guard-21 and packaging-9 for the final candidate now have their own `json`/`stdout`/`stderr`, distinct from the old baseline-era receipts.

## 5. Optional observations (separate; not blockers, not required changes, my adjudication stated)

1. **Ownership-stage refusal labels remain generic — the leading residual, disclosed in full.** `NpmOwnershipProbe.reason(for:)` maps `.cancelled → .cancelled` and every other failure → `.managerQueryFailed` (`NpmOwnershipProbe.swift:328-330`), and `mapOwnershipReason` maps `.cancelled → .probeFailed` and falls through `default → .probeFailed` (`NpmUpdateProbe.swift:1169-1181`). Trigger: the aggregate 60 s budget expires *inside* an ownership group (e.g. Homebrew legitimately consumed most of the shared budget, so the npm subject starts with <20 s), or an ownership `prefix`/`root` query is clamped down and times out at `min(10 s, remaining)`. Consequence: a neutral unknown labelled "update probe failed" rather than `budgetExhausted`/`queryTimedOut`. **No wrong data, no publication, no cache write, no process leak** — the result is neutral and everything downstream refuses. Why I do **not** make this a required change: (a) the frozen brief's mapping sentence is co-emitted with *"actual runner timeout to queryTimedOut"*, which is **not satisfiable** for ownership without widening the M9 `InstallationOwnershipReason` vocabulary that the brief restricts ("existing ownership verifier… without weakening M9") — that asymmetry indicates the sentence targets the query stages whose reason mapping M10-B owns (config/view/version), which RC2 has now finished; (b) B02.5 only mandates that the derived env reaches the verifier, which RC1 now proves. I state it plainly so the coordinator can adjudicate the **broad** reading of R04 ("DeadlineClippingRunner's refusal must map to budgetExhausted…"), under which one bounded change would be needed: thread `uptime`/`stageDeadline` into `verifyOwnership` (`NpmUpdateProbe.swift:983-1013`) and map an ownership `.cancelled` outcome cause-aware when `uptime() >= stageDeadline && !Task.isCancelled`, plus one regression that fires the clock between `prefix` and `root`. I did not flag this in R1; I am recording it now rather than letting it pass silently.
2. **Removal of the harness-only `Set(roots).count == 8` assumption is correct**, not a weakening: the true unique-root count is 6 because each config pair legitimately shares its group root. Per-invocation mode/owned-child/cleanup and the initial-vs-final ownership distinctness are still asserted (`:1402-1413`), and unique claim generation is separately covered by `claimedScratchChildIsOwnedMode0700DirectPhysicalChildOfBase`.
3. `npm --version` is still observed **per subject**, not once per manager/stage, so two npm tools cost two version queries. The brief explicitly says proof optimization beyond exact-request dedup is not required this phase; cost note only.
4. The RC1 test's hard `invocations.count == 10` (`:1389`) is intentionally brittle against silent flow changes; acceptable, worth knowing.
5. Unchanged from R1: the coordinator test `admissionExpiryBeforeAnyLaunchReportsBudgetAndKeepsTheStageUsable` asserts a `>= 9 && < 30` s wall-clock window and is the most plausible flake site in the pending exact-SHA hosted run; and `NpmScratchBase` refuses a group/other-writable base, so a user with `TMPDIR=/tmp` gets a permanent opaque npm "probe update failed".

## 6. Strongest objection to this PASS (stated, then why it does not hold)

The strongest case for blocking is **observation 1 read broadly**: R04's wording is not restricted to config/view, and the clipping runner does refuse inside ownership groups, so a budget-exhausted npm stage can surface a generic label — and my own RC2 rationale ("explicit contract deviation plus an internal inconsistency in the same path family") would seem to demand the same treatment there. It does not carry because the sibling half of the same brief sentence is unimplementable for ownership without the M9 vocabulary change the brief forbids, which makes the "query stages we own" reading the only self-consistent one; because the consequence is a label on a neutral result with zero data/publication risk; and because it is unchanged behaviour from the candidate I already reviewed. I flag it prominently instead of burying it, and I name the exact bounded remedy if the coordinator prefers the broad reading.

## 7. Verification limits (nothing softened)

- **I executed nothing.** No build, test, npm, network, sandbox, GUI, CUA or toolchain command. Every gate statement in §4 is my reading of retained receipts; the receipts could in principle be fabricated by their author, and I can only attest to internal consistency (request counts, argv, hashes, counts) and source/receipt agreement.
- I could not byte-diff the pre-fix `NpmUpdateProbe.swift`, because it is untracked and no copy of the R1 text is retained (only its manifest hash). "No production isolation change" is therefore supported by the 4-file manifest delta, by reading the current code against B02.5, and by the `red` receipt in which RC1's isolation assertions already passed pre-fix — not by a textual diff.
- `native/interaction.json` and the packaged-app/CUA statements are **human-authored JSON**, not raw command stdout; the screenshots live only in the "parent CUA transcript", which I cannot inspect. I treat the native/packaged-app observations as corroborated-by-context, not as independently reproducible evidence.
- AC11 exact-SHA hosted all-seven remains pending after a conditional push by instruction; it is not a code finding and I do not count it.
- I did not repeat any tree-wide content search (per the health constraint); all source inspection was bounded `rg`/`sed` on `Sources/` and `Tests/` plus the exact listed receipt files. No builds, `.build` trees, or special files (FIFOs etc.) were read.

## 8. Boundary

Report only. I wrote no file anywhere (repository, provider plan, evidence, caches, config, hooks), made no Git mutation, ran no build/test/npm/network/install, and used no subagents. I make no provider-execution attestation and no self-acceptance claim. Conditional commit/push of this candidate is the coordinator's decision on the PASS above; PR, main merge, release and M10-C/D remain unauthorized.
