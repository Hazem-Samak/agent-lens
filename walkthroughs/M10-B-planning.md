# M10-B planning freeze and council record

Date: 2026-10-27, Africa/Cairo. Surface: T3 Code. **Planning complete and frozen; implementer selection and product implementation pending.** The user authorized M9 branch removal, M10 retention, stale documentation repair and M10-B planning with the staged council below. No product/test/resource/toolchain change, commit, push of new content, PR, main integration or release is implied by this record.

## Frozen artifact and baseline

- Brief: [M10-B npm latest](../briefs/M10-B-npm-latest.md), revision3 plus coordinator freeze clarifications.
- Final frozen SHA-256: `1270cb3dc660195c71e67977f6bbab883e9b0dcbb730e34c484f4c424ec0c35c`.
- Qwen-reviewed complete R3 SHA-256: `10359d7e7046dcef1afe127599bfd5459964a02874dc5665980e51862e33f1a9`; [exact bytes](M10-B-planning-evidence/M10-B-R3-reviewed.md).
- Initial R1 SHA-256: `8e2163fc9c95d0079248b93d7d462d317d7ffc58a4ca70f9bac863a8a1180aba`; [exact bytes](M10-B-planning-evidence/M10-B-R1.md).
- Initial-council-cleared R2 SHA-256: `7ee8bfa74f19360e638e7e58265c974f34f630106567bb0fb1f40db87e76d139`. **Exact R2 bytes were not retained before replacement.** The earlier external R2-candidate differs and is not the reviewed artifact. Both unedited R2 reports identify the working-tree R2 they inspected; the complete independently Qwen-reviewed R3 supersedes it with the delta recorded in the brief. No exact-R2 snapshot is fabricated.
- Product baseline and unchanged HEAD: `b667be6a177d42f26def815e9acd6f801aa6d52c`, `codex/m10-npm-management`. Main: `0005dcf3eb0f7a0bb4416c10ffa181e99834d244`. M10-A's accepted all7 hosted runs remain historical prerequisite evidence, not M10-B acceptance.
- [Evidence hash manifest](M10-B-planning-evidence/sha256-manifest.json). Source probe receipts first lived under `/private/tmp/agent-lens-m10b-plan-b7klgulu`; the selected unedited reports/receipts and exact R1/R3 are now retained in this repository for review. The manifest's brief path is relative to the evidence directory.

## Council process and outcomes

| Round/member | Requested and configured T3 route | Outcome | Unedited report |
|---|---|---|---|
| R1 MiniMax | `mcode`, `m:minimax:MiniMax-M3.1-Flash:v:thinking`, thinkingEffort=high, plan | CHANGES_REQUIRED, six material findings | [R1](M10-B-planning-evidence/minimax-r1.md) |
| R1 DeepSeek | `pi`, `river/deepseek-ai/DeepSeek-V4.1-Flash-1017`, thinking=high, plan | CHANGES_REQUIRED, five material findings | [R1](M10-B-planning-evidence/deepseek-r1.md) |
| R2 MiniMax | same model/provider/effort; default session to return review directly | PASS, no blockers | [R2](M10-B-planning-evidence/minimax-r2.md) |
| R2 DeepSeek | same River model/provider/effort, plan | PASS, no blockers | [R2](M10-B-planning-evidence/deepseek-r2.md) |
| Final R3 Qwen | `acpRegistry_qoder_cli`, `qmodel_38max`, default session | PASS, no blockers | [Final review](M10-B-planning-evidence/qwen-final-r3.md) |

Qwen was invoked **once**, only after both initial council members returned no blockers. T3 exposes no Qoder effort option. The user explicitly accepted maximum-effort reasoning requested in the prompt; no provider-enforced effort or backend identity is attested. No replacement provider/model was used. No second paid review was necessary.

R1 MiniMax's provider plan workflow wrote its report into its own session artifact and asked a generic implementation-approval question. The coordinator answered that only the existing read-only review was authorized, with no implementation. Repository R1 stayed byte-identical. Later rechecks returned reports directly with no file edits. No reviewer was authorized to write product code or select the implementer.

## Adjudication

Material R1 findings were resolved in R2 with internal proof-carrying/revalidation seams, an enforceable flat JSON contract, precise observable error mappings, actual10-second ownership bounds, bounded monotonic stage admission/execution, npm scratch isolation for the update flow's ownership/config/metadata commands, scratch-stable cache keys and explicit registry/source identity. All affected constructors/callers and tests are bounded by the brief's allow-list. Historical Homebrew cache/probe/comparison files stay protected.

R2's nonblocking notes became R3: both base and scope eligibility must be public/unset as specified; both base/scope registry arguments are pinned only after eligibility; scratch roots are per ownership-verification group or individual other invocation; physicalPath is excluded; the clipping runner reaches every ownership call; unknown npm version affects provenance only. Admission waits at most10 seconds, then a60-second active stage runs Homebrew first before npm. A valid metadata cache never overrides failed/exhausted live validation.

Qwen's nonblocking final suggestions were adjudicated without a second review: admission expiry is explicitly budgetExhausted; all optional stages including cache-hit-only acquire admission; fetch-timeout is10000 as measured; AC07 must prove npm exhaustion preserves completed Homebrew results. The reviewed R3 is retained and the missing exact R2 artifact is explicitly disclosed. Prefix/root hoisting and narrower environment digests remain excluded optimizations; their cost/hit-rate limitations stay visible.

## Executed planning probes

All probes used synthetic HOME/user/global configuration and owned cache/prefix roots. Only read-only npm config/view/version/prefix/root commands ran. No npm install/update/uninstall, toolchain install, personal config edit or package mutation ran.

- [Initial output shape](M10-B-planning-evidence/view.json): real npm10.9.8 `view @openai/codex@latest name version dist-tags.latest --json --global …` returned the three flat string fields with exact package and equal tag/version; unset scope emitted `undefined`.
- [Populated configuration precedence](M10-B-planning-evidence/registry-probe.json): user base/scope honored, project base/scope ignored in global mode. A controlled local HTTP endpoint recorded the scoped request that bypassed a lone base-registry flag.
- [Scoped binding](M10-B-planning-evidence/scope-pin-probe.json): binding both base and scoped CLI flags selected the public registry despite a configured closed fixture scope endpoint. Production must first refuse custom routing; this raw npm probe is not permission to override it.
- [Scratch/cache isolation](M10-B-planning-evidence/scratch-policy-probe.json): real config/metadata calls passed with personal ~/.npm reads/writes kernel-denied; displaced owned-cache sentinel unchanged; distinct mode0700 temporary roots removed after return. This is observed recipe behavior on npm10, not a universal syscall guarantee or product acceptance.
- [Environment and second-major compatibility](M10-B-planning-evidence/env-and-second-major-probe.json): existing npm10.9.8 and11.20.0 honored env base/scope and returned the same strict public metadata shape. No npm major was installed for the probe.
- [Global config and ownership command recipe](M10-B-planning-evidence/ownership-and-global-probe.json): both installed majors honored global-file override; prefix/root with scratch/log/notifier flags returned the owned prefix/root, exit0, mode0700 and owned cleanup recorded.

The controlled transport server existed only for the probe and was shut down. Fixture roots and raw logs remain outside product paths; no production registry URL override was added. These probes establish planning facts, not that future Core/CLI/native M10-B behavior has passed.

## Branch/docs cleanup and verification boundary

`milestone/m9-verified-inventory` at `1ac22c4` had zero commits absent from main and was removed locally and from origin under explicit user authorization. M10 and main were retained; the M10 recovery stash was left untouched. README's pending-hosted-CI/two-summary-only descriptions and ROADMAP's missing-CI baseline were corrected against the accepted workflow and records.

Final verification checks the evidence hashes, local relative links, `git diff --check`, documentation-only change scope and live branch refs. Product source/test/build commands were not rerun for this planning-only change. No new commit or push of these documents was made; the freeze identifies local bytes rather than a new delivered Git SHA.

The next action is the user's implementer selection. Before dispatch, verify that exact route and prepare/freeze its owned fixture/native-host command recipe and baseline gates. No worker is selected, no implementation is dispatched, and no M10-C/D or release action follows automatically. M8 keyboard-only activation remains a separate release blocker.

## Subsequent implementer selection

The user selected OpenRouter Nemotron 3.5 Super VL as primary and WorkBuddy DeepSeek V4.1 Flash through Pi as fallback for issues/quota. See the [selection supplement](../briefs/M10-B-implementer-selection.md) for exact T3 routes and fallback handling. This resolves selection without changing the frozen artifact. Implementation dispatch remains pending; no effort level was specified.

## Implementation authorization

The user subsequently instructed “implement !”. M10-B implementation is authorized with the selected primary/fallback routes; see the [dispatch and readiness record](../briefs/M10-B-implementation-dispatch.md). The frozen artifact remains byte-identical. Baseline gates and real fixture/native-host compile readiness are recorded there; product acceptance and Git delivery remain separate.
