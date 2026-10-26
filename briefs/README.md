# Task briefs

Each file in this folder is a **milestone brief**, in the format defined in `AGENT_LENS_SCOPE.md` §29.11.

---

## How to use them

1. Work on **one milestone at a time, in order.** Large milestones use sequential, separately accepted phase briefs on the same milestone branch; the milestone passes only after its combined acceptance gate.
2. The **orchestrator** owns the master plan, prepares each bounded phase brief, and dispatches it to a separate implementer using the user-selected different model, provider and CLI. The orchestrator does not implement product code or quietly fix worker defects; revisions return to the implementer. Bounding a phase does not remove requirements from the milestone.
3. When the milestone is done, **the orchestrator re-runs the acceptance command itself** and observes it pass. An implementer reporting success is not sufficient (D-014).
4. Record the result in the **Milestone log** at the bottom of `DECISIONS.md`, including the T3 Code build string.
5. Only then start the next milestone.

---

## Rules that apply to every brief

| Rule | Detail |
|---|---|
| **One branch per milestone** | Not per agent, not per thread. The implementer's branch is the source of truth (D-013). |
| **Reviewers are read-only** | They inspect and report. A proposed fix returns to the implementer as a new task (D-013). |
| **Raw transcripts only** | Never accept "it works". Require the unedited terminal output. |
| **`DO NOT TOUCH` is binding** | If the implementer needs a file outside the allow-list, it must stop and ask — not proceed. |
| **Do not give the implementer the scope document** | Give it only the brief. The full document dilutes focus and wastes context (§29.10). |

---

## Model assignment per milestone

Per §29.6: **ambiguity → strongest reasoning model. Volume → fastest model.**

| Milestone | Implementer | Why |
|---|---|---|
| M0, M1 | Flash-tier is fine | Low ambiguity, mostly scaffolding |
| **M2** | **Orchestrator, or strongest reasoning model** | Diagnostic work — see below |
| M3 | Strongest reasoning model | First real integration with the machine |
| M4, M6 | Flash-tier is fine | High volume, low ambiguity |
| M5 | Strongest reasoning model | The product's differentiator |
| M7 | Flash-tier is fine | UI over a working engine |

---

## Order

| Brief | Milestone | Status |
|---|---|---|
| `M0-toolchain.md` | Toolchain | passed |
| `M1-walking-skeleton.md` | Walking skeleton | passed |
| `M2-environment-resolution.md` | Environment resolution | passed — **highest risk in the project** |
| `M3-real-detector.md` | One real detector | passed |
| `M4-detector-registry.md` | Detector schema + registry | passed |
| `M5-duplicate-path-diagnostics.md` | Duplicate / PATH diagnostics | passed |
| `M6-version-update-probing.md` | Version / update probing | passed |
| `M7-first-ui.md` | First UI | passed — technical acceptance + user visual approval 2026-10-16; delivered to `main` as `36a3f1c` |
| [`M8-path-actions.md`](M8-path-actions.md) | Copy Path and Reveal in Finder | user-approved for delivery 2026-10-18; automated gates and final reviews passed; keyboard-only activation unverified |
| [`M9-verified-installations.md`](M9-verified-installations.md) | Metadata, explicit ownership, per-installation versions | technically accepted, user-UI-approved and delivered to `main` — 329 Swift + 9 packaging passed; feature `eb4f586`, integrated milestone tip `1ac22c4` |

M0–M7 complete. M7 passed technical acceptance and user approved the initial UI 2026-10-16; source and closeout documentation were committed and pushed as `36a3f1c`. Local `main`, `origin/main`, and GitHub `main` were independently checked at that commit on 2026-10-17. M7 (`M7-first-ui.md`) implemented the first native SwiftUI macOS app; see [`../walkthroughs/M7-first-ui.md`](../walkthroughs/M7-first-ui.md) for the measured implementation/acceptance walkthrough. The frozen M7 brief remains untouched as the historical plan.

M8 implements native path actions in tool details. The user subsequently authorized implementation, selected DeepSeek V4.1 Flash free via WorkBuddy/Pi as sole implementer and Gemini 3.8 Flash High/Antigravity plus MiMo v2.6 Flash Free/OpenCode as independent reviewers, then approved the UI and Git delivery on 2026-10-18. Parent independent gates passed 246 Swift tests and 9 packaging tests; both final reviews passed. Keyboard-only activation remains unverified and is not represented as a passed gate. See the [M8 walkthrough](../walkthroughs/M8-path-actions.md). The frozen brief retains its historical planning-only header; it is not the current status record.

M9 was separately authorized with DeepSeek V4.1 Flash Free through OpenCode at maximum effort. Its bounded [A](M9-A-detector-metadata.md), [B](M9-B-installation-ownership.md), and [C](M9-C-installation-versions.md) phases and corrected candidates passed parent acceptance, followed by the combined final gate. The user confirmed “M9 UI approved”, then separately authorized branch delivery and main integration. Approved feature commit `eb4f586` reached `origin/main` through the fast-forward of milestone tip `1ac22c4`; no app release was performed. The [M9 walkthrough](../walkthroughs/M9-verified-installations.md) records findings, revisions, hashes, actual versus fixture-host observations, limits and Git delivery. No M10 implementation is authorized by this delivery.

## Remaining application roadmap

[ROADMAP.md](../ROADMAP.md) extends delivery through M19. M9's verified installation details and per-installation versions are technically accepted; M10–M19 remain planned: npm/Homebrew/Python/Cargo management, the original tool catalogue, complete native workflows, menu-bar refresh, bundled CLI, and signed public distribution. [The orchestration contract](../ROADMAP.md#6-orchestration-phase-briefs-and-acceptance) defines phase sizing, required brief contents, external-worker preflight, pinned candidate handoff, independent review, revision loops and acceptance/delivery states. The [M10-A clean-CI/default-TMPDIR brief](M10-A-clean-ci.md), revision 2, passed both user-selected council reviews: Qwen 3.8 Flash Free/Qoder and GLM 5.3 Flash Free/OpenCode. Its [planning/council record](../walkthroughs/M10-A-planning.md) distinguishes fresh pathname evidence from implementation acceptance. Implementation is authorized with DeepSeek V4.1 Flash through WorkBuddy/OMP; the two council members remain reviewers. The user separately approved the [bounded identity amendment](M10-A-approved-amendment-dispatch.md). The [independent acceptance record](../walkthroughs/M10-A-acceptance.md) records the locally verified candidate, both final council PASS verdicts, the documented local native-macro limitation and pending hosted AC08. The user subsequently approved branch commit/push and hosted AC08: `e227c35` is pushed, but its first hosted package build failed on the protected PathActionRow initializer. The [one-file compatibility amendment](M10-A-hosted-compatibility-approved-dispatch.md) was separately approved and implemented exactly; fresh local native353/packaging9 and final Qwen/Gemini replacement reviews passed. The corrected hosted AC08 run remains required. Preserve historical briefs.

---

## A note on the M2 brief

M2 is the milestone where the project is most likely to go quietly wrong.

The code will compile, the output will look plausible, and the PATH will be **subtly incorrect**. Everything built on top of it will inherit that error, and it will present as a detector bug several milestones later — by which point it is expensive to find.

Do not let M2 pass on a visual inspection. Use the `diff` command in the brief. It either prints `MATCH` or it does not.
