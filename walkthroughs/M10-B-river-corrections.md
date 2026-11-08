# M10-B — River RC1/RC2 corrections and verification

Status: both findings corrected; local gates passed; [independent River R2 recheck](M10-B-river-review-r2.md) PASS — no blockers and no required changes. The user’s condition for commit/push is satisfied. Exact-SHA hosted CI remains pending at this pre-push checkpoint.

The [River R1 report](M10-B-river-review-r1.md) supersedes the same-provider Qwen review as the independent implementation gate. Neither finding allowed wrong metadata publication, but both were explicit frozen-contract gaps and were accepted for correction.

## Changes

- **RC1, test-only:** `RecordingNpmRunner` now snapshots every invocation's child environment and observes the cache directory's mode while the command is live. `everyNpmInvocationOverridesInheritedCacheLogsAndNotifierIncludingFourOwnershipQueries` seeds inherited lowercase/mixed-case cache/log/notifier duplicates and sentinel cache/log roots. It reaches initial and final prefix/root (four ownership calls), both config groups, view and version. Every call must use canonical cache/log keys pointing to a mode0700 direct child of the injected base, notifier=false, and preserved TMPDIR; no inherited key spelling survives. The initial/final ownership groups must have distinct roots. All claimed children are removed, and sentinel directory contents and bytes remain unchanged. No product isolation change was needed.
- **RC2, product:** `metadataView` receives the existing monotonic uptime/deadline and reuses the existing cause-aware failure mapping after a failed runner call. A clipping refusal represented by cancelled becomes budgetExhausted only when the deadline is exhausted and the task is not cancelled. Actual task cancellation remains probeFailed; timeout/overflow behavior is unchanged.
- **RC2, regression:** `metadataDeadlineRefusalUsesBudgetReasonWhileTaskCancellationStaysNeutral` deterministically advances the clock at the view-runner refusal seam, after the pre-view guard. It checks both deadline-only and actual-task-cancelled cases, no downstream metadata launch, no provenance/cache record, and no leftover scratch child.

These two source/test files are the only code changes since River's pinned R1 candidate. The coordinator made these small review corrections directly; they are not attributed to the prior Qwen implementer. No protected file, dependency, registry, CI, frozen brief, or toolchain changed.

## Actual verification

Raw receipts, including argv, exit, elapsed time, stdout and stderr, are retained in [river-corrections evidence](M10-B-river-corrections-evidence/README.md). Test runs inherit the normal TMPDIR, with both Agent Lens test overrides unset. The documented invocation-local TestingMacros load-plugin fallback remains local only; hosted commands are unchanged.

| Gate | Result |
|---|---|
| Initial targeted reproduction before product fix | RC2 fails: expected budgetExhausted, actual probeFailed. RC1's contract assertions passed, but an unnecessary exact scratch-root-count assumption failed (config base/scope intentionally share a group root); that extra assumption was removed. Original failed receipt retained. |
| Corrected targeted regressions | Both tests pass; genuine task cancellation is separately checked within the RC2 test. |
| Fresh `swift build` | Exit0, 27.95s |
| Full `swift test --no-parallel` with documented local macro fallback | **397 Core +71 AppSupport =468** pass, zero failures/skips;82.86s including incremental macro build |
| Core/UI guard |28 files clean, exit0 |
| Guard behavior fixtures |**21** pass, exit0 |
| Fresh ordinary debug-app builder |Exit0,26.53s |
| Original packaging suite |**9** pass, exit0 |
| Whitespace check |Clean, exit0 |

Fresh external harnesses were compiled against the corrected final Core/AppSupport objects. Real npm10.9.8 confirmed Check→fresh / Check→cache preserving the original18:09:08Z observation / Refresh→fresh18:09:10Z. Two view launches; schema1 document with one entry; scratch empty after each run. Actual sandboxed CLI Check/Refresh both show local1.0.0/latest2.0.0, public @openai/codex/latest, npm10.9.8 and one update. Only prevalidated public base/scope pins are externally substituted to loopback; no product override exists.

The corrected native host compiled unchanged product views and showed Check fresh18:09:20Z, second Check cache with that same observation, Refresh fresh18:09:30Z, then Rescan Not checked/count reset. Screenshots were emitted through CUA; interaction and query receipts are retained. The separately built ordinary packaged app also opened local-only3known/3installed/Not checked and was quit without update or ownership actions. The server recorded six requests total: two headless, two actualCLI, two native. Both injected scratch bases were empty afterward; apps and server were stopped. The earlier delayed native Cancel/window-close and adversarial matrices remain retained historical checks; the affected deadline/cancellation distinction is now covered directly by the new regression on this final candidate.

## Boundaries

The frozen brief remains SHA256 `1270cb3dc660195c71e67977f6bbab883e9b0dcbb730e34c484f4c424ec0c35c`. Prior evidence and failed receipts are retained, not overwritten. Guard21 and packaging9 now have separate final receipt JSON and full outputs, closing River's evidence-hygiene observation. Independent River approval is complete. Exact-SHA hosted all-seven acceptance remains pending at this pre-push checkpoint; no Git mutation or delivery is claimed by these local receipts.
