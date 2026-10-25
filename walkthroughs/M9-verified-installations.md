# M9 — independent acceptance record

Status: **M9 technically accepted and user-UI-approved**. Corrected A/B/C candidates and the combined final gate passed parent acceptance; the user then explicitly confirmed “M9 UI approved”. Sole product implementer remained DeepSeek/OpenCode; the parent did not patch product code/tests. Commit/push and public release are **not** claimed. Source remains uncommitted on `milestone/m9-verified-inventory`.

## Authority and implementer

User authorized M9 with DeepSeek V4.1 Flash through OpenCode at maximum effort. Configured route `opencode/deepseek-v4.1-flash-free#max`; provider metadata advertised `reasoningEffort: max` and the harmless route/auth probe returned `ROUTE_OK`. This proves the configured route and working request, not independent upstream model attestation. Initial CLI v2.0.32; later live/relay observations reported 2.1.3 and 2.1.4 as external host-state changes, not upgrades performed by this work.

Milestone branch `milestone/m9-verified-inventory`, HEAD baseline `a405b56183ad0233f286f4d93b027ba7d21c2a01`. Pre-existing README/index/roadmap changes were preserved. Parent authors plans/briefs/review records; external worker authors product code/tests. All current product changes remain uncommitted.

Evidence root (machine-local, not in repository):

```text
R=/Users/corvette/.hermes/cache/scratch/agent-lens-m9-20261022-382vfoyi
```

## M9-A — technically accepted

Authority: [original brief](../briefs/M9-A-detector-metadata.md) and [R1 correction brief](../briefs/M9-A-R1-review-corrections.md). Worker session `ses_e9acd902cffeqBxG0XdXrtKEmo`. Reviewed replacement candidate manifest `59402e1afdc8b7ccb2af5d3c76ae251dab6f55a05ab81de0d976631385e37160` covers 20 product/test/resource/worker-report files. Parent verified every content hash before independent acceptance.

### Review findings and corrections

- Worker crossed the runner and packaging-test allow-lists instead of stopping. The parent found the original brief had omitted files required for its stderr-query and schema-migration requirements, then prospectively authorized those narrow edits in R1. The original process violation is not reclassified as compliant. Future boundary changes require stopping and a revised brief.
- Parent reproduced a real crash: schemaVersion `9223372036854775807` and `9223372036854775808` both terminated a compiled validator probe with signal 5 because Double rounding defeated an Int conversion guard. The worker corrected integer conversion and added subprocess regression coverage. Parent rebuilt and observed ordinary typed rejection for both inputs, booleans and fractions.
- Parent reproduced malformed `tap/name` accepted as a Homebrew identity. Worker corrected the shared validator to accept exactly one or three nonempty components; parent observed two-component rejection and valid tapped-formula acceptance afterward.
- Worker removed avoidable full-output line copies and per-render enumeration allocation, and deleted new incidental/mock-echo tests instead of re-pinning their wording.
- The worker moved the original ignored `.build` tree while investigating stale test-product lookup. A later SourceKit index occupied the original location. Parent preserved the new index separately and restored the original generated tree without deleting, overwriting or merging files. Receipt: `R/evidence/dot-build-restoration.json`. Current tests now prioritize the active test products and passed with generated state present.

### Parent-observed gates

| Gate | Observed result | Evidence |
|---|---|---|
| Fresh original M8 baseline | 184 Core + 62 AppSupport passed | `R/evidence/baseline.log` |
| Fresh replacement-candidate full Swift suite | 208 Core + 63 AppSupport = 271 passed; plain invocation, no fallback needed by parent | `R/evidence/parent-a-r1-suite.log` |
| Independent development app build | succeeded, 31.95 s reported by Swift; absolute app produced | command/result retained in parent conversation; app under `R/parent-a-r1/dev-app` |
| Packaging against that exact app | 9 tests passed, exit 0 | raw result retained in parent conversation |
| Parent boundary probe compiled against independent Core product | dangerous integer cases ordinary typed errors, malformed two-component package rejected, valid tapped package accepted | `R/evidence/metadata-boundary-before.json`, `metadata-boundary-after-parent.json` |
| Parent production-query smoke | 7 scenarios passed: configured argument, stderr selection, blank/first-nonempty distinction, nonzero exit, stderr output cap and deadline | `R/evidence/parent-a-r1-query-smoke.json` |
| Actual parent-built CLI offline scan | Codex 0.163.0, OpenCode 2.1.3, Grok 1.0.62; correct winners, Grok same-target alias; declared metadata appears before neutral update status | raw result retained in parent conversation |
| Actual parent-built native app | selected Codex → OpenCode → Grok → Codex; metadata/official links and path-action labels changed correctly; Grok has no declared package and no leftover OpenCode uninstall link | `R/evidence/native-receipts.jsonl`, `a-final-*.png` |
| Native 760-point window and scrolling | requested/read-back width 760; long package identifiers wrap; ownership remains Not verified; official/uninstall links remain readable after scroll | `a-final-opencode-760.png`, `a-final-opencode-760-scrolled.png` and native receipts |

The suite also exercised all existing CLI update modes/invalid forms and their manager/cache isolation behavior. No latest-version adapter or ownership query was added by A. The parent's version-query smoke uses real test-owned executables through production `makeDetector`, not mock output.

Technical acceptance applies only to M9-A's behavior on the identified replacement snapshot. The worker's empty final chat message in R1 was not treated as proof; the candidate report, hashes, source changes and independent observations supplied the evidence. At A's phase acceptance, user visual approval had not yet been recorded; whole-M9 approval is recorded below.

## M9-B — corrected candidate technically accepted

Authority: [original brief](../briefs/M9-B-installation-ownership.md), [R1](../briefs/M9-B-R1-review-corrections.md) and [R2](../briefs/M9-B-R2-bin-identity.md). Worker session `ses_e97e98650ffeFslpBSeLSVc27k`. Accepted R2 manifest `d00d9ae6dfbe0af505c8b3a2b8a713feb76d7ab88786b96c5ea58bfd0163a20a`: 21 files, independently rehashed; 72 protected accepted-A files independently compared with zero mismatches. Copies are under `R/accepted-b`.

### Rejected candidates and corrected findings

- Parent reproduced an npm manifest FIFO hanging verification, a canonical global root redirected into another prefix incorrectly verifying, and Homebrew ownership rejecting an installed HEAD-like keg when stable metadata was null. R1 introduced nonblocking descriptor-validated manifest reads, exact canonical prefix/root containment and an ownership-only Homebrew parser.
- Independent source review found unrevalidated lexical package/root bindings and an unanchored ancestor-swap read boundary. R1 retains and revalidates lexical bindings and walks canonical directory descriptors with `O_NOFOLLOW`; deterministic fixture regressions passed. These original race findings were source-derived, not parent-executed attacks on private files.
- R1 corrected manager-change reason propagation, single-pass brew-list matching and per-render timestamp allocation.
- Safety rereview rejected R1: a bin symlink could change between one containment resolution and a second proof observation. R2 now contains the exact canonical target in the accepted executable observation. Worker preserved a behavioral RED (cross-prefix verified) and GREEN (`executableOutsidePackage`); the parent independently passed the new regression in the complete suite. R2 also removed a bounded JSON re-encoding copy.
- Independent standards and safety reviewers inspected the artifacts without product edits/builds. Final safety rereview found no material blocker and closed the same-observation issue. Reports: `R/evidence/m9-b-r1-standards-review.txt`, `m9-b-r1-spec-review.txt`, `m9-b-r2-spec-review.txt`.

### Parent-observed final B gates

| Gate | Observed result | Evidence under R |
|---|---|---|
| Full Swift suite | 244 Core + 71 AppSupport = **315 passed**, exit 0 | `evidence/parent-b-r2-suite/{stdout,stderr,command.json}` |
| Fresh app build / packaging | build exit 0; **9 packaging checks passed** | `evidence/parent-b-r2-builder`, `parent-b-r2-packaging` |
| Compiled boundary replay | ordinary npm verified; cross-prefix root neutral `managerRootMismatch`; stable-null Homebrew fixture verified | `evidence/ownership-edge-b-r2-parent.json`; earlier FIFO before/after in `ownership-edge-before.json` / `ownership-edge-after-parent.json` |
| Actual CLI, real npm | `verify-installation codex` verified `@openai/codex`; current observed Codex 0.164.0 | `evidence/parent-b-r2-cli-codex` |
| Real Homebrew plumbing | read-only existing `python@3.15` verified through rebuilt Core; ephemeral harness, not a catalogue addition | `evidence/parent-real-brew-verify-b-r2.json` |
| Actual native app | Codex verified with manager/package/root/selected identities; OpenCode selection had no borrowed proof, explicit verification returned unsupported-source Unknown; Rescan cleared it | `evidence/b-r2-native-*.png`, `native-receipts.jsonl` |
| Narrow native details | 760-point actual app; long manager and installation roots wrap without clipping | `evidence/b-r2-native-proof-760.png` |
| Controlled native lifecycle | real test-owned child held a manager query; Verifying → Cancelling → idle/Not verified; selection-change cancellation suppressed the next query; failed Rescan retained local facts but cleared verified ownership | `evidence/ownership-controlled-native-result.json`, `b-controlled-*.png`, `ownership-controlled-host-build.json` |

The controlled host stayed outside the repository, compiled unchanged product views and linked the independently built Core/AppSupport. It injected a closed fixture environment, scratch cache URL and explicit registry-failure trigger; it is not evidence that the ordinary app can select fixture environments. The actual-app and controlled-host observations are separate. Its cache file was never created; its query log showed only prefix for each cancelled verification, then prefix/root for the completed one.

The final suite used the invocation-local explicit TestingMacros fallback and `--no-parallel`. Worker parallel attempts had failed an unchanged M6 real-process timing bound under load; failures are preserved, no assertion was loosened/skipped, and the parent did not rerun the known failure merely to confirm it. Parent's complete serial gate passed. Native snapshot assertions/visuals established text states; a driver role-only `verify_state` selector incorrectly checked the first static text and returned unsatisfied for two already-visible states, so those helper replies are not claimed as successful checks.

At B's phase acceptance, C and the combined milestone gate were still pending; their completed results follow below. B did not add a package-management operation or user visual approval.

## M9-C — corrected candidate technically accepted

Authority: [C brief](../briefs/M9-C-installation-versions.md), [R1](../briefs/M9-C-R1-publication-and-origin.md) and [R2](../briefs/M9-C-R2-linear-origin.md). Worker session `ses_e9075990dffeh8w7l1a6lam5Fj`. Final C manifest `ef22b04c54e11f2dc4745a521035f822667ef98e2a8f6e8e62e7d5fe80be3da7` covers 14 files. Parent independently matched every hash and all 85 protected accepted-B inputs before documentation closeout. The old ownership-local identity helper is absent; its shared `Process/` implementation retained B behavior. Copies: `R/accepted-c`.

### Findings and corrections

- Both independent reviewers rejected the initial candidate: the terminal selected-identity check could detect a retarget after the per-target publication loop, yet leave the selected observation measured. The scanner then published inconsistent selection alongside a known old selected version.
- Parent reproduced that contradiction through the unmodified public scanner, real filesystem identities and a controlled query callback across 1500 targets. This is **not** a claim of executing/measuring 1500 real child tools. Before: inconsistent selection plus selected/observation version 1.2.3. After R1 and final R2: both versions nil, selected observation identityChanged, unrelated shadows retained. A permanent deterministic TaskLocal regression covers the terminal-only transition.
- An off-root query changing its entry correctly became unknown/inconsistent but lost its declared-root label. Parent reproduced the production-renderer omission. The original fixed-model packet omitted durable origin; R1 prospectively authorized required `origin: PathCandidateOrigin`. Both measured and unknown observations now retain it, independently of final selection.
- R1 removed the native enumerated-array allocation and offset identity. R2 removed the newly introduced quadratic origin lookup, using the exact original firstSlotIndex/raw PATH entry; it did not claim to optimize the pre-existing M5 grouping algorithm. CLI provenance now explicitly disclaims both shell-winner status and verified ownership, matching native presentation.
- Final independent safety and contract rereviews reported no material findings. Source-review-only reports: `R/evidence/m9-c-r2-identity-review.txt`, `m9-c-r2-contract-review.txt`. Earlier rejected-candidate reviews and snapshots remain preserved.

### Parent runtime proof

`R/evidence/installation-version-before-parent.json` records the original selected-only measurement and stale replacement/retarget version behavior. Final compiled real-file scenarios are in `installation-version-final-parent.json`: two distinct values, alias/repeated-slot deduplication, raw empty/relative PATH origins, selected off-PATH, nonzero query, retarget, same-path replacement, change while a later copy runs, and aggregate-budget exhaustion. The eight scenario modes passed. The six-target slow fixture launched four sequential children, retained six unknown observations, detected no overlap and completed collection in **10.013 seconds**; the last two were explicitly unqueried/budget-exhausted. This is an observation, not a hard total-time/atomicity guarantee.

Terminal-publication before/final proof: `version-publication-race-before-parent.json` and `version-publication-race-final-parent.json`. Changed off-root before/final: `offpath-origin-before-parent.json` and `offpath-origin-final-parent.json`.

Final native evidence is separate by surface:

- **Actual parent-built app:** selected Codex/OpenCode/Grok diagnostics, exact version text, metadata, explicit real npm verification, standalone Unknown and Rescan clearing. `R/evidence/final-actual-native-result.json`, `final-native-*.png`.
- **Two-installation host:** unchanged product MainWindow/DiagnosticsView linked to final Core/AppSupport; only closed fixture environment/cache/registry injection. Distinct canonical rows show 1.2.3 and 2.3.4 at width 760, with exactly two Codex queries. `final-two-version-native-result.json`, `final-two-version-native-760.png`.
- **Changed off-root host:** unchanged views and scanner with isolated roots; inconsistent selection, unknown version and original declared-root provenance remain visible together at width 760. `final-offpath-native-result.json`, `final-offpath-origin-760.png`.

## Combined M9 acceptance — passed

Final product/source/resource/test/worker-report manifest: **43 current files**, digest `2ce17e4b840c7410e0f4aaaf3bb1fa5eed348add964f66259ec9c0890950ca25`, in `R/evidence/m9-final-product-manifest.json`; the required old helper removal is recorded separately. Base HEAD remains `a405b56183ad0233f286f4d93b027ba7d21c2a01`. Parent README/roadmap/index/whole-contract/log/acceptance changes are intentional documentation closeout, separately recorded in the final repository-input manifest after source acceptance.

| Requirement / gate | Parent-observed final result | Evidence under R |
|---|---|---|
| R01–R02 metadata/schema | Bundled schema 2 and current metadata passed the complete suite; 6 compiled integer/package boundaries returned ordinary typed outcomes; CLI/native declarations remain distinct from ownership | `evidence/final-metadata-query-compatibility.json`, `parent-final-r2-cli-live`, `final-native-*.png` |
| R03 current discovery/path semantics | Codex 0.164.0, OpenCode 2.1.4, Grok 1.0.70; correct selected targets; Grok two entry aliases/one canonical observation; direct/extra-root/path-action regressions pass | `evidence/parent-final-r2-cli-live`, `final-actual-native-result.json`, full suite |
| R04 explicit-only effects | Closed offline CLI produced two distinct Codex versions with exactly winner/shadow/OpenCode/Grok queries and no manager trap; real cache access kernel-denied. Controlled native launch had no manager query before Verify; fixture cache remained absent | `evidence/parent-final-r2-cli-fixture`, `final-controlled-ownership-result.json` |
| R05 verified ownership | Real npm Codex verified through final CLI/app; real Homebrew python@3.15 verified through an ephemeral consumer of final Core, not a catalogue addition | `evidence/parent-final-r2-cli-verify-codex`, `final-real-brew-ownership.json` |
| R06 lifecycle/stale safety | Final linked native host: Verifying → Cancelling → Not verified; selection switch cancels without borrowed proof; failed Rescan retains local facts and clears ownership; query log suppresses the next query on cancellation | `evidence/final-controlled-ownership-result.json`, `final-controlled-*.png` |
| R07 per-installation identity | Real-file association, aliases, off-root, changed/missing/failing identities, raw origins and terminal-publication regression correct | `evidence/installation-version-final-parent.json`, `version-publication-race-final-parent.json`, `offpath-origin-final-parent.json` |
| R08 process bounds/literal queries | 7 production-query cases passed (declared args, stderr, line policy, exit/cap/deadline); sequential aggregate-budget fixture behaved as described above | `evidence/final-metadata-query-compatibility.json`, `installation-version-final-parent.json` |
| R09 full regression | **258 Core +71 AppSupport = 329 Swift tests passed**, exit 0, explicit invocation-local macro plugin and `--no-parallel`; no skips or weakened assertions | `evidence/parent-final-r2-suite/{stdout,stderr,command.json}` |
| R09 app/bundle | Independent fresh debug app build passed; **9 packaging checks passed**, exit 0 | `evidence/parent-final-r2-builder`, `parent-final-r2-packaging` |
| R09 source/scope/review | Final C hashes and 85 protected B inputs matched before parent docs; helper cutover clean; both final independent reviews clear; Core remains UI-free and no dependency/package change | `evidence/parent-c-r2-hash-verification.json`, final review reports and full suite |

The cache-denial fixture proves access was prevented, not that a swallowed denied read attempt can be inferred absent from exit 0 alone. Explicit-only code/state and CLI/service regression coverage establish that contract; no captured environment or credential dump was used as evidence. All manager observations were read-only. External changes to installed Codex/OpenCode/Grok versions during the session were observed, not performed by Agent Lens.

All final product/fixture windows and their owned processes were closed after observation. Native sessions ended; no global keyboard setting, clipboard content or managed-tool configuration was changed. Fixture sources/builds remain under R for reproducibility, not in shipping source.

### Open the reviewed development build

```sh
R="$HOME/.hermes/cache/scratch/agent-lens-m9-20261022-382vfoyi"
open "$R/parent-final-r2/dev-app/AgentLensApp-debug.app"
"$R/parent-final-r2/full-suite-explicit/out/Products/Debug/agent-lens" scan --offline
"$R/parent-final-r2/full-suite-explicit/out/Products/Debug/agent-lens" verify-installation codex
```

Technical acceptance and user visual approval are complete. Git delivery remains pending separate authorization; nothing was staged, committed, pushed, signed, notarized or released by this work. Update/Uninstall are still unavailable. Next planned phase is **M10-A: clean CI and default-TMPDIR fixture portability**, not an automatically authorized dispatch.

### User visual approval

The user explicitly confirmed **“M9 UI approved”** for the reviewed M9 build. This approval is associated with the accepted product manifest `2ce17e4b840c7410e0f4aaaf3bb1fa5eed348add964f66259ec9c0890950ca25` and final C candidate `ef22b04c54e11f2dc4745a521035f822667ef98e2a8f6e8e62e7d5fe80be3da7`.

No additional technical or keyboard-only measurement is inferred from this approval. It does not authorize commit/push, public release or M10 implementation. The technical evidence and earlier acceptance snapshots remain unchanged.


## Carried limits

- M8 keyboard-only activation remains unverified: controls were observed, but background Tab delivery did not prove keyboard traversal/activation. No global keyboard preference or permission bypass was used.
- Existing temporary-directory portability and compiler/linker warnings remain outside M9; all parent gates used authorized invocation-local scratch.
- No installed tool, package, configuration or actual Agent Lens update cache was modified by M9-A acceptance. The OpenCode version change was observed host state, not an Agent Lens operation.
- Final C identity/contract review and combined M9 gates passed, and the user approved the M9 UI. Git delivery remains separately authorized. The current app still cannot update or uninstall tools, and signed public installation remains future work.
