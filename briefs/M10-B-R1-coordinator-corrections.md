# M10-B implementation R1 — coordinator corrections required

Date: 2026-10-27. Revision to the submitted implementation, not a change to the frozen product contract. Candidate1 is **NOT accepted**. Fix all findings below using the existing frozen allow-list, then return a new frozen candidate. No Git delivery is authorized.

## Candidate and independent evidence

All12 reported product/test SHA256 values matched the handed-off tree. Exact copies/hashes/diff are retained under E/parent/qoder-candidate1, E=`/private/tmp/agent-lens-m10b-implementation-9jaujmja`. Coordinator fresh `swift build --scratch-path E/parent/qoder-candidate1/products` passed. The full suite was not repeated after finding material functional defects; worker427 PASS remains worker evidence only.

Coordinator external compiled probe: E/parent/qoder-candidate1/ReviewProbe.swift, executable ReviewProbe, compile receipt review-probe-compile.json, raw results review-probe-results.json. It links the freshly built candidate Core and uses the real owned npm fixture tree with a scripted runner; this is Core behavioral proof, not real npm/network acceptance. It made only owned fixture changes and restored manifest/bin content afterward. Do not change E/parent; copy/run the probe in E/worker/qoder-flash/r1 if useful. Preserve old evidence.

## R01 — derive lookup identity from the verified matched package (blocking wrong-package result)

`NpmUpdateProbe.swift:394-396` takes `definition.packages.first`, even though full ownership verification may match a later declaration. Reproducer `verified-second-package`: declarations `["@missing/not-installed","@openai/codex"]`, actual owned installation `@openai/codex`; candidate queried `@missing/not-installed@latest` and published updateAvailable with npmPackage=`@missing/not-installed`. Existing shipped OpenCode declares multiple npm alternatives, so this is a real supported layout.

After unique ownership succeeds, use `installation.packageName` for registry scope, metadata argv, cache key, source/result and final proof comparison. No pre-verification first-declaration identity may authorize a lookup. Regression: second/later match uses that name; unmatched/ambiguous candidates launch zero view and cannot borrow another package's metadata.

## R02 — pin the effective public scope even when scope config is unset

`metadataArguments` at :206-209 appends the scope flag only when scopeRegistry is nonnil. The ordinary unset-scope path is nil; reproducible `unset-scope-pin` has no `--@openai:registry=...` flag. This breaks B02.4's explicit binding and leaves a config-change window after eligibility.

For every scoped verified package, append both base and scoped flags using the accepted normalized public origin even when config emitted `undefined`/`null`. Do not reinterpret empty/malformed scope output as unset (`resolveRegistryRoute:177` currently accepts empty); only the measured unset values or an accepted public URL qualify. Tests must cover unset as well as explicitly-public scopes, malformed/empty scope refusal and config changing after eligibility. Real controlled host must detect `view` by token/parsed argv, since scratch flags precede the subcommand; do not rely on `arguments.first == "view"` in the external host readiness scaffold.

## R03 — persist actual proof identity, not only paths (blocking stale cache hit)

`NpmOwnershipProof.fingerprint` frames paths only, omitting directory device/inode/mode and manifest/bin identity fingerprints. Reproducer `manifest-before` then atomically replacing package.json at the same path (same valid content plus newline) then `manifest-after`: candidate reused cached2.0.0 and made zero view calls even though the manifest identity changed. B04.2 explicitly requires that replacement to invalidate the hit.

Include all stable identity fields from every recorded directory and file/executable, length-framed deterministically: device/inode/mode for directories, complete existing ExecutableFingerprint for manager/selection/manifest/bin/managerBin, plus canonical/lexical path fields. Continue excluding DirectoryIdentity.physicalPath and raw manifest content. Test same-path manifest and directory replacement, selected/bin/manager changes independently; all must miss or refuse, never reuse prior proof metadata. Retain aliases/symlink behavior and existing M9 assertions.

## R04 — final live proof and deadline check must follow the final external query (blocking stale success)

Full final ownership runs before the final registry reads. After those reads, the candidate checks cancellation only, not current identity or stage deadline. Two executed reproducers:

- `replacement-after-final-proof`: runner replaces the selected executable during the last scope-config response; candidate still publishes updateAvailable(installed1.0.0,latest2.0.0) and writes metadata.
- `deadline-after-final-scope`: last scope response advances injected uptime beyond stageDeadline; candidate still publishes/caches fresh success.

After all final config queries and immediately before cache commit/publication, require non-cancelled, unexpired stage, and `finalProof.revalidate()` success against the full recorded proof. Compare effective route state as required; observed route/proof changes refuse. A changed executable/manifest/root yields identityUnverified, exhaustion budgetExhausted, with no success/cache write. No claim of eliminating every unavoidable filesystem race. Add deterministic regressions for replacement and exhaustion at that exact last-query window, including cache-hit path. DeadlineClippingRunner's refusal must map to budgetExhausted when the aggregate deadline caused it, rather than reporting generic cancelled/probeFailed.

## R05 — admission and active budget must cover BOTH managers and all optional stages

`UpdateProbeCoordinator.run:226-248` runs Homebrew before `resolveNpmBatch` acquires the new gate at :517 and starts its60s clock at :533. Thus Homebrew-only/cache-only stages bypass the required gate, Homebrew can overlap another run's npm, total stage time excludes brew, and admission expiry can still launch a Homebrew manager before refusing npm. The comments claim a shared budget but the code is npm-only. This contradicts frozen B03.4 and the final clarification that every optional stage acquires admission.

Acquire bounded10s/cancellation-aware admission once for the complete Check/Refresh stage, create one60s monotonic deadline, and pass the same deadline-clipped runner to Homebrew and npm paths. Run Homebrew first, preserving completed results if later npm exhausts the budget; then npm registry-order. Plain/offline return before any gate/query/cache. Release exactly once on every exit/cancellation. Preserve existing Homebrew inner batch gate and lock order; no protected-file edit is needed. Add coordinator-level—not probe-only—tests for two concurrent mixed-manager calls (no cross-run overlap), Homebrew-only/cache-only admission, expiry before any launch, clipping of brew+ownership/config/view, and npm exhaustion retaining completed Homebrew results. Keep the120s CLI watchdog and existing Homebrew semantics except the explicitly authorized bounded-stage refusal.

## R06 — validate the stored metadata with the same strict semantics; preserve ambiguity as a miss

`NpmUpdateMetadataEntry.isStructurallyCoherent` currently checks only nonempty strings and name==package. Cache-hit path constructs NpmViewOutput directly without parser validation. It can accept `version != distTagsLatest`, invalid SemVer, unsupported registry/tag, or prerelease metadata from a structurally parseable corrupted document; a valid key is not proof of valid metadata. `save` also silently picks the newest of duplicate existing identity records, contrary to the frozen ambiguity-as-miss rule.

Require accepted normalized registry/tag, validated package/name equality, exact strict stable version==distTagsLatest and coherent bound identity fields before returning/storing records. Corrupt/incoherent/ambiguous entries are misses; merge/prune must not silently resolve ambiguous metadata into a verified observation for another tool. Preserve Homebrew document and valid other-tool entries. Serialize in-process read/merge/write as specified (public cache operations currently have no synchronization; coordinator stage serialization alone does not serialize direct/concurrent saves). Test poisoned-but-parseable metadata, duplicate records surviving unrelated saves, and simultaneous saves preserving both valid records. No new lock framework/dependency.

## R07 — enforce the scratch ownership/unsafe-root contract

`createScratchRoot:263-269` follows arbitrary symlink ancestors with intermediate creation; `removeScratchRoot:277-284` removes a supplied lexical path without observing/rechecking the directory it created and ignores cleanup failure. This does not implement the brief's symlink/unsafe-root refusal or owned-child-only cleanup guarantees. Do not use source comments as proof.

Validate/anchor the injected scratch base, create unique0700 children and retain their observed ownership identity. Refuse unsafe/symlinked injected bases before launching; account for the sanctioned default TMPDIR physical alias correctly. Cleanup must recheck the exact owned child/root and never follow a retargeted ancestor into another tree. Propagate/report cleanup failures rather than silently claiming zero leftovers. Keep this inside the new probe file and allowed test seams; no product Process/** edits or fixture-isolation weakening. Tests: symlink base, retargeted/replaced base/child, permission refusal, cleanup failure, mode0700, and no sibling/sentinel deletion. Do not mutate personal roots for these cases.

## R08 — complete the promised behavioral evidence and usage docs before next handoff

The worker left most adversarial identity, coordinator lifecycle/order, native-host and real-npm gates unexercised. Those gaps hid R01–R07. Add meaningful regressions for each correction in existing allow-listed files and run the real prepared npm/CLI/native-host recipes for feasible worker gates; clearly list coordinator-only observations without calling the phase complete. Coordinator independently re-exercises them. No final acceptance without each AC accounted for.

README is explicitly worker-allowed for M10-B usage migration in the frozen file authority (the existing coordinator corrections must be preserved). Update the stale Homebrew-only limitation to describe the actually implemented npm eligibility/cache/source/unknown behavior and limits; do not leave contradictory usage docs. Do not alter roadmap/brief/index/acceptance/history. Use E/worker/qoder-flash/r1 for all new logs/builds; the prior worker debug app wrote under E/parent despite dispatch ownership—do not repeat that. Verify current candidate hashes and protected files, new exact passed test inventory, zero skips/failures, fresh debug builder/original9 packaging, real argv/exit/elapsed receipts and owned cleanup. No .build-only incremental proof substituted for requested fresh roots.

## Return and boundary

Frozen brief stays byte-identical. Product/test file authority is unchanged. This revision does not authorize M10-C/D, personal package operations, dependencies, Git commit/push/main/release or extra delegates. Do not self-accept; report CHANGES/requirements/evidence and freeze the new candidate for independent coordinator review. Any genuinely necessary out-of-allow-list change must stop for a bounded request.

## R01–R04 checkpoint — coordinator observed

The bounded first batch returned438 worker-reported tests (367 Core+71 AppSupport), with11 new targeted regressions. Coordinator independently snapshotted its12 candidate product/test files, built fresh under E/parent/qoder-r1-batch1/products (exit0), and recompiled the original external ReviewProbe against those fresh Core objects. Raw receipts E/parent/qoder-r1-batch1/{build.json,probe-compile.json,probe-results.json}.

The original failing cases now show: unset scope includes both registry flags; a later matched declaration queries/labels `@openai/codex`; replacing the manifest causes a new view returning3.0.0 rather than cached2.0.0; final-query deadline exhaustion returns budgetExhausted/no provenance; final-query executable replacement returns identityUnverified/no provenance. This is acceptance of those reproduced corrections only, not complete M10-B acceptance or a new hosted/full/native pass. R05–R08 remain open. Next bounded batch implements R05–R06; then R07–R08 and final combined acceptance.

## R05–R06 checkpoint — default gate passed; one residual R06 defect

Coordinator verified the post-batch hashes, retained exact candidate copies under E/parent/qoder-r1-batch2/source, and ran a fresh full suite with inherited TMPDIR, BOTH Agent Lens test overrides unset, fresh products and only the permitted local macro-loading fallback. Raw argv/context/exit/elapsed: default-tests.json; streams default-tests.stdout/stderr. Exit0, 387 Core+71 AppSupport=458, zero issues/skips. The worker's explicit `/private/tmp`-scratch CLI assertion failures are not reproduced under the required default gate; retain those raw failures but do not change fixture-isolation or product path semantics merely to fit that optional spelling. Default gate must pass again on final candidate; an explicit-override limitation remains documented separately.

Shared admission now encloses both manager paths; the coordinator inspected its acquisition/deadline/runner/release ordering and queue identity snapshot regression fix. Strict cache validation and in-process lock are present. One R06 hole remains independently reproduced by external CacheProbe.swift compiled against the coordinator's freshly built Core; receipts cache-probe-compile.json and cache-probe-results.json under E/parent/qoder-r1-batch2:

- Stored tool-A records: one valid2.0.0, one parseable same-identity poison `version=2.0.0` / `distTagsLatest=9.0.0`. Lookup correctly misses initially.
- `cache.save([valid tool B])` succeeds; `saveMerged` filters out A's poison but preserves A's valid-looking sibling.
- Lookup A now HITS without a fresh verified A observation. Exact stdout: `before-unrelated-save hit=false`, `save-B success=true`, `after-unrelated-save hit=true`.

Correct this in the next batch: preclassify contaminated complete identities (any invalid record, or ambiguity) before pruning; an unrelated save must never promote their sibling. Dropping ALL existing records for a contaminated identity is acceptable and preserves a miss; preserving ambiguity explicitly is also acceptable, provided invalid data never becomes a usable record and the document stays bounded. Only incoming verified metadata for that same identity can repair it. Add this mixed valid+invalid sibling/unrelated-save regression (the two-valid-duplicates case alone did not cover it), keeping independent other-tool metadata and Homebrew bytes intact. No new authority needed.

Next bounded batch: this residual R06, R07 scratch ownership, and R08 README/walkthrough plus final worker gates/evidence. No phase acceptance yet. Coordinator independently performs final runtime/native/real-npm acceptance; worker must not relabel those future observations as passed. No Git delivery authorized.


## Final coordinator checkpoint — 2026-10-27

R01–R08 are closed in the reviewed working-tree implementation. Final fresh independent verification passed466 Swift tests, guard21 and packaging9. The independent fresh Qwen Flash read-only review returned PASS/no material blockers; real npm controlled transport, actual CLI parity, native Check/cache/Refresh/Rescan and Cancel/window-close observations are recorded in `walkthroughs/M10-B-coordinator-verification.md`. The review's narrow cancellation-reason labeling case remains a documented nonblocking limitation; no wrong metadata or cached claim is published. No protected product files changed after review, and all12 reviewed source/test hashes remain unchanged. Coordinator status/docs and evidence were updated afterward. Hosted all-seven exact-SHA acceptance is pending separate commit/push authorization, as required by the frozen brief. No Git delivery, PR, main integration, M10-C/D or release is claimed.


## Independent River implementation review — RC1/RC2

River Pi DeepSeek V4.1 Flash1017 returned CHANGES_REQUIRED, retained verbatim in `walkthroughs/M10-B-river-review-r1.md`. RC1 requires a regression observing the derived environment on every npm call, including initial/final prefix/root; RC2 requires view-side aggregate-deadline clipping refusal to report budgetExhausted while actual task cancellation remains neutral. Both findings are accepted; the earlier same-provider Qwen review is supplemental only. Commit/push remains held until River rechecks the corrected candidate with no blockers or required changes. Corrections are small and coordinator-owned under the review workflow; they are not attributed to the prior Qwen worker. Frozen brief remains byte-identical.

RC1/RC2 correction checkpoint: both regressions pass; fresh397Core+71AppSupport=468, guard21 and packaging9 all pass with raw final receipts retained under `walkthroughs/M10-B-river-corrections-evidence/`. Only NpmUpdateProbe.swift and NpmUpdateProbeTests.swift changed in code. New River review pending; no commit/push.

Final independent River R2 recheck PASS/no blockers/no required changes (`walkthroughs/M10-B-river-review-r2.md`). RC1/RC2 closed; the coordinator accepts the explicitly optional observations as within frozen scope. User’s condition for feature-branch commit/push is satisfied. No product or test bytes changed after this review; final approval record/status docs only. Exact-SHA hosted CI follows push.
