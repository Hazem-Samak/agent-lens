# Council RECHECK — M10-B npm latest-version status, planning R2

**Review role:** read-only planning-council recheck (R2). Backend/model identity is **not attested** by this report; nothing here claims provider verification.
**Subject:** `briefs/M10-B-npm-latest.md` (R2, 144 lines, working tree `b667be6` + orchestrator-owned `README.md`/`ROADMAP.md` edits + untracked brief).
**Prior round:** `minimax-r1.md` (CHANGES_REQUIRED, 6 material) and `deepseek-r1.md` (CHANGES_REQUIRED, 5 material) under `/private/tmp/agent-lens-m10b-plan-b7klgulu/`.
**Method:** source/doc/receipt inspection only. No build, test, npm, network, git mutation, implementation, delegation or file edit. npm behaviour claims are static derivations from the installed 10.9.8 tree plus the coordinator's recorded receipts, marked as such.

---

## Verdict: PASS — no blocking findings

Both R1 verdicts CHANGES_REQUIRED. R2 closes every material item I re-tested, and the remaining items are documented limitations, small specification gaps with safe failure directions, or optional refinements. Nothing in R2 is unimplementable inside its own file authority, and no clause contradicts verified code.

Two accounting facts first, because a recheck should confirm the record rather than repeat it:

- R1 hash claim is honest: `shasum -a256 M10-B-R1.md` = `8e2163fc9c95d0079248b93d7d462d317d7ffc58a4ca70f9bac863a8a1180aba`, exactly the value the brief cites, 127 lines.
- The brief's npm-source claims check out: `npm-registry-fetch/lib/index.js:206-210` maps `preferOnline → 'no-cache'`; `:190-204` (`pickRegistry`) puts a scope registry above `opts.registry`; `@npmcli/config/lib/index.js:619-623` marks project config `(global mode enabled, ignored)`.

---

## 1. Recheck of the ten items named for this pass

| # | R2 clause | Code / receipt check | Result |
|---|---|---|---|
| 1 | Internal proof seam: `NpmOwnershipProof`, internal `verifyWithProof(...)`, internal `resolveNpmManager(...)`; public `verify` delegates and discards proof (brief `:44`) | `NpmOwnershipProbe.swift:49-102` already holds exactly the required fields (prefix/root/package/prefixBin `DirectoryIdentity`, manifest `FileIdentity`, bin/managerBin `ObservedExecutable`, `revalidate()`), and `:206` returns `.verified(match.0)` — proof built then dropped. `InstallationOwnershipVerifier.swift:114-137`/`:166-188` are private. All three target files are on the modify list; `VerifiedInstallation.init` is internal (`InstallationOwnership.swift:40`), so the "no public forgeable token" pattern is preserved. | Fixed, implementable |
| 2 | Shared error enum: `unsupportedRegistry`, `unsupportedChannel`, `budgetExhausted`, `metadataInvalid`, `queryTimedOut`, rendered in CLI **and** app (`:61`) | `UnknownReason` (`VersionStatus.swift:27-39`) is not `CaseIterable`, so no test enumerates it. The only exhaustive switches are `UpdateScanRenderer.swift:89-110` and `ToolDetailView.swift:466-497` — both allow-listed. Opaque failures stay `probeFailed` (`UpdateProbeCoordinator.swift:584-589`); `CommandOutcome` really exposes no exit status (`ProcessUpdateCommandRunner.swift:38-52`), so "never invent a raw exit status" is enforceable rather than aspirational. | Fixed |
| 3 | `10s` ownership / `3s` config / `20s` metadata with a stage-wide `60s` monotonic budget, clipping wrapper, refusal ⇒ `budgetExhausted`, acknowledged non-fit | `HomebrewUpdateProbe.queryTimeout = 10` (`:204`) is what `NpmOwnershipProbe.query` passes (`:236-252`), so the 10 s figure is now the real one, and the 3 s figure is correctly attached to new config/version queries rather than the M9 ownership bound. Process seam is injectable (`UpdateCommandRunner`, `HomebrewUpdateProbe.swift:102-111`), so a `min(nominal, remaining)` wrapper plus `uptime:` injection is a coordinator-local change. Budget is explicitly stage-wide, which also closes R1's scan-level gap. | Fixed; arithmetic caveat in §4 |
| 4 | Scratch override for **all** npm queries within M10-B only, with derived env + matching flags, four-query regression, M9 standalone untouched (`:53`) | `NpmOwnershipProbe.query` currently passes `environment.raw` verbatim (`:236-252`), so the override is a real change, not a no-op. Both ownership files are allow-listed; `InstallationOwnershipTests.swift:275-282,322` pins the standalone argv to `["prefix","--global"]`/`["root","--global"]`, which is consistent with "only for this update flow" — the standalone path must keep byte-identical argv, and R2 says it does. | Fixed |
| 5 | Scratch-stable digest (no scratch/TMPDIR in key) plus AC06 distinct-scratch-roots row (`:66`, `:104`) | The existing precedent would have broken this: `contextFingerprint` digests the whole child env key-by-key (`UpdateProbeCoordinator.swift:571-580`). R2 replaces the vague wording with framed inputs and explicit exclusions, and AC06 now contains the row that would have caught the regression. | Fixed (see N-1, N-6) |
| 6 | Effective scoped routing with explicit base **and** scope flags, refusal before any request (`:51-52`) | Receipts are decisive: `registry-probe.json` `user-scope` case shows the scope query reading the loopback value **and** a `view` carrying only `--registry=npmjs` still hitting the controlled user-scope endpoint (`controlled_hits: ["/user-scope/@openai%2fcodex"]`, served `1.2.3`); `scope-pin-probe.json` shows both flags forcing the public route. So the second flag is load-bearing, and "refuse custom scope before `view`" is the right order. `base custom + scope public` is deliberately refused (AC03's "unsupported route" wording matches), i.e. under-query, never a leak. | Fixed, and evidence-backed |
| 7 | Enforceable flat JSON parsing (`:59-60`) | "Exactly three measured flat keys with String values", nested `dist-tags` rejected by the key set, Foundation-only, and — importantly — the duplicate-member claim is retracted rather than faked (`duplicate complete **records**` moved to AC06, `:104`). Matches the measured payload exactly. | Fixed |
| 8 | Transport substitution in host/test only; no product URL backdoor (prep, `:114`) | This is now *stricter* than the R2 candidate reviewed in `/tmp` (`M10-B-R2-candidate.md:113`, which put an internal `NpmRegistryPolicy` test initializer in product code). The repo R2 keeps the product validator public-only, puts substitution in an external wrapper over the existing `UpdateCommandRunner`, requires original-vs-executed argv receipts, and forbids any product URL/env switch. Feasible: the probe proves npm 10.9.8 talks http to a loopback registry. Native host needs no `MainWindow.swift` change (`MainWindow.swift:37-47` supplies only `updateCacheURL`; a defaulted new `InventoryService` parameter is source-compatible, `InventoryService.swift:52-71`). | Fixed |
| 9 | User/global honored, project ignored in global mode, measured on npm 10.9.8 (`:141`) | `registry-probe.json` supplies all four populated-config cases: user base → loopback; user scope → loopback; project base → `https://registry.npmjs.org/`; project scope → `undefined`. So the label/request equivalence R1 called an assumption is now an observation in two directions (scope case: config read matches the actual contact; project case: config read `undefined` and no project contact). R2's rejection of `--userconfig/--globalconfig` pinning is also the better call — pinning would manufacture a routing path npm itself may not use, and the CLI-layer binding flags already defeat every lower layer. | Fixed |
| — | Scratch-policy receipts (`:144`) | `scratch-policy-probe.json`: both invocations exit 0 with distinct owned roots, `mode: 0o700`, logs confined to the owned dir, displaced-cache `sentinel_unchanged: true`, `owned_child_removed: true`, personal `~/.npm` kernel-denied. Also consistent with `view.json` (banners on stderr only) and with `BoundedProcessRunner` discarding the other stream to `/dev/null` (`:35-42`). | Sound |

R1 residual items also look genuinely closed: settled-decision/§21.3-rule-4 context added (`:30-37`), `npmScratchBaseURL` seam with sibling-derived npm document (`:115`), `M10-B-ACxx` IDs, Done-condition and expanded stop list (`:127`), `--prefer-online` sentence corrected, npm version recorded as provenance with "other versions fail closed", cross-manager admission and `uptime` injection, `AC10` now permits manager-neutral unknown-wording changes (`:108`), and the ownership-cache-isolation question answered by option (a) with the four-query regression (`:53`).

---

## 2. Code facts re-verified for this recheck (so the PASS is not a rubber stamp)

- `UpdateProbeSubject` still carries no definition (`UpdateProbeCoordinator.swift:36-48`); only two production construction sites (`main.swift:80`, `InventoryService.swift:176`) — both have the validated definition in scope, so B01.2's carry-through is a bounded migration.
- Coordinator still hard-gates `tool.source == "brew"` (`:171-175`), so B01.2's replacement is required, not optional.
- `UpdateMetadataCache` semantics match B04.3 exactly: `ttl = 21_600` with `0 <= age < ttl` and future/expired as misses, single-match or miss, schema 3 (`:252-290`), and `save(_:)` is a whole-document atomic replace (`:293-300`) — which is precisely why R2 had to specify npm-side merge/prune rather than reuse it.
- `stableDigest` is SHA-256 hex, not `Hasher` (`UpdateMetadataCache.swift:67-70`); `DirectoryIdentity.physicalPath` is documented "never a cache key" (`ExecutableIdentity.swift:56-66`).
- `VersionComparison` compares magnitudes as digit strings ("no fixed-width integer parsing"), so AC05's "very large numeric identifiers" row is satisfiable, not a trap.
- `cliRunBudget = 120` with "three 3 s version queries, and three 10 s manager queries" (`UpdateCLIIntegrationTests.swift:36-38`); CI floors 406 / 21 / 9 (`.github/workflows/ci.yml:175,190-191,201`).
- `InventoryViewModel` already coalesces Check/Refresh/rescan/verify into one pipeline (B05.3 preserved), and Check/Refresh do not require a prior Verify Installation click (B01.1 preserved).

---

## 3. Non-blocking observations (numbered; each safe to defer, none blocks freeze)

1. **`physicalPath` must be excluded from the proof digest.** R2 says "identity/path/fingerprint fields"; `ExecutableIdentity.swift:56-66` explicitly forbids `DirectoryIdentity.physicalPath` in a cache key. One clause in B01.3/B04.2 would prevent an implementer from quietly violating a documented invariant (consequence is hit-rate noise across `/var` vs `/private/var`, not corruption).
2. **The scratch argv for the four ownership queries is asserted, not measured.** The probe covered `config get` and `view`; `prefix --global`/`root --global` with `--cache/--logs-dir/--no-update-notifier` was never executed. Low risk (same config-flag mechanism, output unchanged), but the pre-dispatch freeze should record that exact argv on npm 10.9.8 before dispatch.
3. **The global-file config layer is unmeasured.** Both probes used an empty `global.npmrc`. Failure direction is refusal (under-query), not leakage, since the CLI-layer binding flags defeat lower layers; still worth one case in the populated-config probe.
4. **AC07 observes `mode0700` but not scratch-root removal in the product.** The contract says "cleanup only those children"; the recipe probe shows `owned_child_removed`. A cheap receipt would make the acceptance row match the contract.
5. **No `--fetch-timeout` in the documented argv.** The bounded runner covers the runaway case, but pinning a fetch timeout below the 20 s runner bound converts a kill into a clean typed failure and stops one stuck origin from consuming a third of the stage budget on a single step.
6. **Digest breadth vs. six-hour reuse.** Excluding the overlays and `TMPDIR` is necessary but not sufficient for cross-launch hits: any unrelated captured-env difference (session ids, `_`, shell-injected vars) is a miss. This is inherited from the M6 `contextFingerprint` pattern, so it is consistent rather than new — but for npm the honest routing inputs are `HOME`/prefix/userconfig/globalconfig plus the config-file identities, which would be both stabler and more faithful to "config routing changes cannot borrow old metadata".
7. **No `D-020`.** R2's choice (milestone-log record, no worker amendment of settled docs) is defensible because D-019 is explicitly M6-scoped and is not contradicted. Recording the npm public-registry-only/global-mode eligibility as a coordinator-owned entry before M10-C/D would be cheap and would pre-empt re-litigation.

---

## 4. Strongest objection (not a blocker)

**A stage-wide 60 s budget couples the two managers: one slow npm package can convert *other* tools' statuses — including Homebrew's — into `budgetExhausted`, while AC10 asks that Homebrew statuses be preserved.**

Nominal worst case for a *single* npm tool is ~69–75 s (20 ownership + 3–6 config + 3 version + 20 view + 3–6 config re-read + 20 ownership re-verify), so the budget provably cannot contain the design's own maximum; R2 states this openly and defines the outcome (neutral unknown, no cache write, no publication). That part is honest and safe. The part worth pressure-testing is the *coupling*: because the clock covers "all subjects/managers, including … admission waiting", a slow `view` plus two ownership passes can eject a Homebrew batch that M6 bounded independently (3 × 10 s) and that users already trust. Exhaustion is also reachable purely from waiting on a concurrent run's admission, which a legitimate Refresh could inherit from a preceding Check.

Recommended refinement (optional, one or two sentences in R2): start the monotonic clock when the stage gate is acquired (or exclude admission waiting from the budget while still bounding it), and give each subject a sub-budget or run the Homebrew batch first under its own bound, so a slow npm observation cannot evict an unrelated tool's status. This is not a blocker because the failure mode is a documented, testable neutral unknown that never publishes or caches a wrong claim, and AC07 already carries the "over-budget" and "injected monotonic exhaustion prevents subsequent launch" rows needed to observe whichever rule is chosen.

---

## 5. Review scope and limits

- Read-only: no file created, edited or deleted; no `git` mutation; no `swift build`/`swift test`; no npm/network/packaging execution; no implementation; no subagents. Baseline numbers (406/21/9) were read from CI configuration and acceptance records, not re-measured.
- All npm semantics in this report are static derivations from the installed 10.9.8 tree plus the coordinator's retained receipts (`base.json`, `scope.json`, `view.json`, `registry-probe.json`, `scope-pin-probe.json`, `scratch-policy-probe.json`). I did not re-execute any probe, so the receipts' own fidelity is taken as recorded; their internal consistency with the brief's prose is what I checked.
- No approval of implementation is implied. Freeze, implementer selection and acceptance remain the coordinator's and user's; this report only records that R2 has no blocking findings.

**Disposition:** freeze-eligible. Publish R2 with observation 1 (a one-clause `physicalPath` exclusion) if a micro-revision is cheap; observations 2–7 and the §4 refinement can be folded in or carried into the pre-dispatch freeze notes without another council round.
