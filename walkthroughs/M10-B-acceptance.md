# M10-B — verified npm latest metadata acceptance

**Technically accepted on the feature branch** `codex/m10-npm-management`, implementation commit [`72ffb1e0b52ffe65dfb8616e648dec9c46d48ae4`](https://github.com/Hazem-Samak/agent-lens/commit/72ffb1e0b52ffe65dfb8616e648dec9c46d48ae4). This milestone does not authorize M10-C/D, PR/main integration or release. User visual approval remains separate; no new visual-approval claim is made.

## Review and authorship

Qwen3.8-Flash through Qoder completed implementation after the authorized Nemotron quota and WorkBuddy restriction failures. The coordinator independently inspected and reproduced initial defects, then verified the sequential corrections and runtime acceptance. The same-model Qwen review is supplemental only. The user-selected **River Pi DeepSeek V4.1 Flash1017, thinking=high**, independently reviewed the candidate, required RC1/RC2, and returned [R2 PASS — no blockers, no required changes](M10-B-river-review-r2.md) after the coordinator's small corrections. Both unedited River reports and red/green correction receipts are retained.

The user explicitly authorized commit/push conditional on that independent PASS. Before recording approval/status-only documentation, the coordinator rehashed River's full249-file candidate pin with zero mismatches. All72 reviewed source/test files were then checked against the committed Git blobs and matched. Subsequent closeout changes are documentation/evidence only.

## Verified result

CLI and native Check/Refresh now report public-npm `latest` metadata only for the exact selected, ownership-verified package. Both base/scope public pins are bound after effective-route eligibility; custom routes refuse. Strict metadata/SemVer parsing, stable-channel policy, final identity/deadline checks, separate six-hour metadata cache, cross-manager admission/Homebrew-first budget, and owned temporary npm cache/log roots are verified. No Update/Uninstall, dependency, catalogue, protected Process/Homebrew implementation, CI, guard or packaging-source change is included.

The [coordinator verification](M10-B-coordinator-verification.md) contains the AC01–AC11 accounting; [River corrections](M10-B-river-corrections.md) contains the final local results and receipt links. Real npm10.9.8 controlled transport, actual isolated CLI, native Check/cache/Refresh/Rescan, native cancellation/window close, and ordinary packaged local startup were exercised and distinguished. External transport substitution exists only in harnesses, after asserting both public pins. Owned servers/apps were stopped; scratch children removed; no personal install/config/cache mutation is claimed or authorized.

## Exact-SHA hosted acceptance

[CI run40558867751](https://github.com/Hazem-Samak/agent-lens/actions/runs/40558867751), **attempt1**, completed successfully for exactly `72ffb1e0b52ffe65dfb8616e648dec9c46d48ae4`. All seven gates have producer exit0 and verification exit0:

| Gate | Observed result |
|---|---|
| Core/UI boundary guard |Pass |
| Guard behavior fixtures |21 pass, zero skips |
| Package build |Pass |
| Native isolation capability gate |1 test pass, zero skips |
| Full Swift suite |468 combined tests pass, zero skips |
| Fresh debug development-app builder |Pass |
| Original packaging checks |9 pass, zero skips |

The hosted run used native macro discovery, with no local load-plugin fallback. Its single combined468 summary is not misreported as separate hosted target counts; locally the final candidate passed397Core+71AppSupport. The coordinator independently compared all468 passed-test events, preserving duplicate-name multiplicity, and the hosted/local multisets match exactly.

The 33-file GitHub artifact's ZIP SHA256 was independently matched to GitHub's digest: `0cddfa86e9874cf70e1cb0c16d06392fc2abab28031a093d7fc03f2f3b137252`. [All hosted receipts and coordinator verification](M10-B-hosted-evidence/README.md) are retained in the repository so the original seven-day GitHub artifact retention is not the only record.

## Remaining boundaries and limitations

M10 as a whole remains incomplete; M10-C Update and M10-D Uninstall are separate future scopes. No PR, main merge or app release was performed. Existing M8 keyboard-only activation remains a separate release blocker. Accepted limitations include broad environment digests reducing cache hits, per-process admission/atomic last-writer cross-process cache semantics, extra proof/config work on hits, safe refusal for unsafe TMPDIR roots, and generic failure labels inside the inherited M9 ownership-query seam. River explicitly classified those as optional rather than required changes; its full rationale remains in the unedited R2 report.
