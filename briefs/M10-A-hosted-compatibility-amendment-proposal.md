# M10-A hosted compatibility amendment proposal

2026-10-26. Proposal only; no authority to edit the protected UI source is inferred from Git/CI approval or the follow-up instruction to continue preparing this amendment.

## Observed checkpoint

The user approved committing/pushing the reviewed M10-A candidate and running hosted AC08. Candidate commit `e227c3502fc34f524a611f6fdfdbe9b6aa0aef68` was pushed to `codex/m10-npm-management`; local/tracking/remote refs matched and the checkout was clean. No PR/main merge/release occurred.

First hosted run: https://github.com/Hazem-Samak/agent-lens/actions/runs/40300975808, push event, exact commit above, job121498490420. Runner macOS15.7.9/24G830, arm64, image20260907.0337.1, Xcode26.3/17C529 at the specified job-local developer path, Apple Swift6.2.4. Guard and all21 guard fixtures passed (zero skipped); package build exited1 after28.146s. Native isolation/full-suite/debug-app/package checks did not run. Summary retained FAILED/NOT RUN honestly; uploaded artifact12640591213, zipSHA256 c13ba009fcda26bf64f746801a91dda56e377566b766f4ebe8b566e943a99295, verified on download.

The actual build diagnostic at ToolDetailView.swift:359 says PathActionRow initializer is inaccessible due to private protection. PathActions.swift:18 names synthesized `init(target:toolName:rowLabel:_feedback:_feedbackIsError:)`; both State backing properties are private. That UI source was byte-identical to the M9 baseline and protected throughout M10-A. The local Swift6.4 synthetic two-file access-control model compiles both before and after variants; it does NOT reproduce the hosted6.2.4 failure. Its successful proposed variant is syntax evidence only. No claim that the local native macro-discovery failure caused this different hosted build error.

## Smallest proposed source authority

Authorize ONLY `Sources/AgentLensApp/PathActions.swift` in addition to the already approved M10-A source paths. Add the explicit INTERNAL three-argument initializer shown below. Parameters remain exactly target/toolName/rowLabel, assign only those three existing lets. Do not expose or accept the two private State backing values; keep their declarations, nil/false initial values and privacy unchanged. Do not alter body/layout/accessibility, dispatcher, native effects, feedback logic or ToolDetailView identity/callsite. No visibility changes to PathActionRow or its state, no new framework, wrapper macro, toolchain replacement, build flag workaround or skipped tests. This is compiler compatibility, not an M8 UI redesign.

All other sources remain protected. Package/workflow/builder/schema/dependencies and test assertions remain frozen. Parent may update this proposal, acceptance/status docs and delivery facts; worker may append an honest implementation report only. Sole implementer remains user-selected DeepSeekV4.1Flash/workbuddy/OMP; council Qwen3.8Flash/Qoder + GLM5.3FlashFree/OpenCode. No model fallback. Existing Git delivery approval covers the M10-A branch but does not itself lift the explicit source DO NOT TOUCH boundary. No code edit before bounded human approval.

## Proposed exact patch

```diff
diff --git a/Sources/AgentLensApp/PathActions.swift b/Sources/AgentLensApp/PathActions.swift
index dcec65a..0c84735 100644
--- a/Sources/AgentLensApp/PathActions.swift
+++ b/Sources/AgentLensApp/PathActions.swift
@@ -25,0 +26,6 @@ struct PathActionRow: View {
+    init(target: PathActionTarget, toolName: String, rowLabel: String) {
+        self.target = target
+        self.toolName = toolName
+        self.rowLabel = rowLabel
+    }
+
```

## Acceptance after authorization

1. DeepSeek applies only the bounded initializer. Parent compares the complete diff and proves all other shipping inputs unchanged; State privacy/defaults/body/effects must be byte-identical. No text-mirroring permanent test is needed for this mechanical initializer; cross-file compiler build is the regression gate.
2. Fresh local package build, full353 Swift tests under inherited TMPDIR with overrides unset (native attempt; only documented invocation-local macro fallback if necessary, labelled), fresh debug app and all9 packaging checks. Guard21 and Core26 source scan remain valid if unchanged, with scope/digest receipt. No UI behavior approval is inferred; existing M8 keyboard release blocker remains.
3. Both council members review the actual bounded diff and raw parent results. Parent owns acceptance. Capture candidate identity before commit; commit/push only after approval and affected verification, compare local/tracking/remote refs. Keep first red hosted run; no retry-to-green.
4. A NEW push-triggered hosted run must pass the specified Xcode26.3 native package build, isolation gate, full353-or-more suite with no skips, debug builder and all9 packaging checks, with all receipts and exact SHA correlation. Preserve native macro failure/summary shape/isolation failures if discovered; return them for bounded revision. No technical acceptance/M10-B until all AC08 checks pass on identified candidate.

## Evidence

E=/private/tmp/agent-lens-m10a-impl-20261026-4_wjuwpb. First run log/metadata and verified artifact receipts are under E/parent/hosted-ci-40300975808 and E/parent/hosted-ci-run-1*. Git receipts: git-delivery-commit.json and git-delivery-ref-verification.json. Synthetic scope-limited model receipt: E/parent/hosted-constructor-probe/receipt.json (both variants compiled on6.4; initial parent assertion expecting a local failure was wrong and is retained, not treated as a reproduced red).

## Council verdicts and pre-approval class audit

Qwen/Qoder and GLM/OpenCode both returned **PASS, zero blockers**, for human consideration only. Reports: `E/hosted-amendment-qwen-review/final.txt`, `E/hosted-amendment-glm-review/final.txt`; same user-selected routes/sessions. The exact reviewed proposal/patch hashes remain retained in `E/parent/hosted-constructor-proposal/input-sha256.json`; this appended section records subsequent read-only evidence and does not change the proposed source hunk or authority.

The parent audited stored private/fileprivate properties and cross-file construction across all12 App/AppSupport Swift files. MainWindow, ToolListView and OwnershipVerificationView already have explicit public initializers; ToolDetailView/DiagnosticsView also have explicit initializers. Public AppSupport value constructors are explicit; private nested value types are constructed within their own files. Private class/actor default initialization does not use a struct memberwise initializer. PathActionRow is the sole identified cross-file struct constructor with private stored state and no explicit initializer. This is source-level inspection, not hosted compilation of the proposed repair. If a subsequent hosted run surfaces another out-of-authority UI/access error, stop for a new bounded amendment; this authority does not expand automatically.

Before SHA256 for PathActions.swift: `2099bd143585d65b4c7e4fee11eb5905cce824505d88ec7204be61ebdc8a9584`; after-proposal SHA256 is in the retained input manifest. The proposed source diff is exactly one file, six insertions, zero deletions. No workspace source edit has been performed. Parent source-level audit receipt: `E/parent/hosted-constructor-proposal/source-class-audit.json`.

The displayed source diff uses zero context to avoid trailing-whitespace-only context lines in Markdown; the original reviewed full-context patch and its hashes are retained unchanged under E/parent/hosted-constructor-proposal. The six inserted source lines are identical.
