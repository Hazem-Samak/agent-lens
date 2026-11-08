# M10-A planning and council record

Date: 2026-10-26, Africa/Cairo. Planning only. The user authorized preparation of M10-A's brief and selected Qwen 3.8 Flash Free through Qoder plus GLM 5.3 Flash Free through OpenCode as council members. No product implementation, branch creation, commit/push, hosted run or repository-settings change was authorized or performed by this planning work.

## Candidate and baseline

- Product baseline: `0005dcf3eb0f7a0bb4416c10ffa181e99834d244`, clean local `main` before preparation. Local tracking ref matched; remote was not freshly queried.
- Brief: [`M10-A-clean-ci.md`](../briefs/M10-A-clean-ci.md), revision 2. Reviewed candidate SHA-256: `66c1e556d0ed94f2dfdf7a100e0c2875214363d46c69675e66db0440296a3fb6`.
- Evidence root `R`: `/private/tmp/agent-lens-m10a-20261026-a9el6aow`. Raw receipts/transcripts remain local and disposable, not shipping resources or committed binaries.
- Historical M9 acceptance reports 329 Swift and nine packaging checks. This session did not rerun that full gate or certify any M10-A implementation.

## Fresh diagnosis used to bound the brief

1. Unchanged native targeted build: exit 1 before test execution because `TestingMacros` discovery failed. Receipt: `R/evidence/default-tmp-baseline/`.
2. Documented local plugin fallback, inherited default TMPDIR, both Agent Lens test overrides unset: build succeeded; `sandboxDeniesAllAccessToTheRealAgentLensCache` executed and failed two assertions. The allegedly denied `touch` exited 0 and created the fixture file. Receipt: `R/evidence/default-tmp-explicit/`.
3. Same unchanged targeted test with explicit `AGENT_LENS_TEST_SCRATCH=R/tmp`: again failed the same two assertions. Owned children were created in the supplied root, so this was not merely an unobserved parent environment setting. Receipt: `R/evidence/explicit-scratch-control/`.
4. Direct Foundation probe: an existing URL's `/private/tmp/...` spelling became `/tmp/...` after `resolvingSymlinksInPath()`. Receipt: `R/evidence/foundation-path-probe.json`.
5. Identical `sandbox-exec` profile shape and `/bin/sh` plus `touch` invocation against owned fixtures: a profile subpath spelled `/tmp/...` allowed the write, while physical `/private/tmp/...` denied it and left the target absent. Direct physical-path read/write probes denied both operations, with successful unsandboxed controls. Receipts: `R/evidence/alias-profile-comparison.json` and `mechanism-probe.json`.
6. An additional probe under **ordinary inherited TMPDIR** confirmed the same distinction: `/var/folders/...` profile spelling allowed fixture reads/writes; physical `/private/var/folders/...` spelling denied both. Receipt: `R/evidence/default-root-physical-comparison.json`. This corroborates revision 2's physical-path requirement without changing the frozen brief.

The measured result is a path-spelling mismatch in the test's mechanism proof. The old source explanation of a general Darwin-temp sandbox exception is not established by these observations. No product/test source was edited to fix it. No real-cache read/write denial was exercised directly; fixture mechanism proof, actual profile/path inspection and two-run cache non-reuse remain distinct evidence.

## Council routes and read-only boundary

| Member | Configured and observed route | Capability check |
|---|---|---|
| Qwen 3.8 Flash Free, user designation | Qoder CLI 1.1.78, `Qwen3.8-Flash`; CLI event attested that model name | `COUNCIL_ROUTE_OK`, exit 0 |
| GLM 5.3 Flash Free | OpenCode 2.1.4, `opencode/glm-5.3-flash-free`, plan agent | `COUNCIL_ROUTE_OK`, exit 0; first review reported cost $0 |

Qoder's catalog does not attest pricing. No alternate route was selected. CLI model reporting is not independent backend-model attestation. Qoder requested plan mode but reported effective `default`, so permission mode alone is not claimed as a no-edit guarantee: reviews used self-contained packets in disposable snapshots, explicitly prohibited tools/edits, and are checked against packet/snapshot hashes and tool events. OpenCode used `--read-only`/plan without passing an auto-approval flag. Relay metadata's `auto` field alone does not describe the actual plan invocation.

Both members received revision 1 with the same source excerpts and baseline facts; each returned `CHANGES_REQUIRED`. Revision-1 brief hash: `bf26359fdf72f48378203b06eb2b950395660c517c2f65b311e97213ca07027f`. Complete raw reports: `R/qwen-council-r1/final.txt` and `R/glm-council-r1/final.txt`; structured results and event logs are alongside them.

## Findings adjudication and revision 2

| Finding | Decision and correction |
|---|---|
| Local fallback versus full-suite acceptance was ambiguous | Clarified full local fallback acceptance and targeted default/override cases; native hosted macro discovery remains a separate early gate |
| Relocation to `/private/tmp` was unmeasured | New direct probes exposed Foundation alias spelling instead; removed relocation and required physical-path resolution, default-root controls, alias/resolution-failure regressions and child path receipts |
| Decoy success was being generalized to actual cache denial | Mandatory truthful comments distinguish measured decoy behavior, path/profile review and the named two-run six-query non-reuse check; no blanket real-cache syscall guarantee |
| A "required check" could imply configured branch protection | Workflow delivers a check; repository branch-protection settings explicitly remain separate |
| Simulated sandbox failure, new Python entrypoint and mutation ownership lacked precision | Added test-only fake-control results/marker failure cases, direct Python entrypoint, and source-copy-only guard mutation cycle |
| Serial suite budget and repeated builds | Kept a bounded 30-minute initial job budget with elapsed-time evidence and explicit timeout failure/revision; build/tests share a fresh tree, packaging builds independently |
| Potential packaging tests omitted | Source inventory confirms all nine existing packaging methods are in the named bundle test script; no new discovery framework is required |
| Request to prove hosted macro discovery before brief approval | Not treated as a planning blocker: cannot claim a hosted observation before authorized delivery. Specified early hosted capability gate, fail-closed stop and AC08 instead |

Second-round packets contained the complete revision 2 plus these corrections and raw diagnostic facts. Qoder initially could not resume from a different snapshot directory (exit 42, no review); retrying from the original session directory preserved the chosen route. The failed resume remains at `R/qwen-council-r2/`; the actual second review is `R/qwen-council-r2-resumed/`. GLM's second review is `R/glm-council-r2/`.

## Current boundary

Both second-round reviews completed with exit 0 and **PASS**, with no remaining blocking planning-contract findings:

- Qwen: `R/qwen-council-r2-resumed/{result.json,final.txt,events.jsonl}`. Its non-blocking request for an additional inherited-TMPDIR physical-path control was already satisfied by preparation step 6 above; it was measured while the frozen revision-2 review was running.
- GLM: `R/glm-council-r2/{result.json,final.txt,events.jsonl}`. Its non-blocking wording note on R01.3 has this intended reading: default, physical and symlink **input** spellings resolve to the same physical path first; sandbox profiles built from that resolved path must enforce denial. The raw unnormalized alias is not expected to enforce denial. This follows R01.3's explicit physical-resolution requirement; the reviewed brief remains byte-identical.

Reviewers used no model tool calls in either round. Both disposable snapshot hashes remained unchanged. The final brief hash matches the revision-2 packet; parent validation checks protected baseline files and permits only the two new planning documents plus the roadmap/index link/status updates. Narrow diagnostic fixtures/builds stayed outside the checkout; no product source, test, resource, package manifest, builder or installed tool was changed. Verification receipt: `R/evidence/final-verification.json`.

**Planning review complete; implementer selection and implementation authorization pending.** The brief is not M10-A implementation acceptance. Native hosted CI and Git delivery remain pending; M10-B is not dispatched. No branch, commit or push was created during preparation. M8 keyboard-only activation remains a separately tracked release blocker.
