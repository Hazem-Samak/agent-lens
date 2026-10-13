# Task briefs

Each file in this folder is a **milestone brief**, in the format defined in `AGENT_LENS_SCOPE.md` §29.11.

---

## How to use them

1. Work on **one milestone at a time, in order.** Do not start the next one until the current one has passed.
2. Give the brief to the **orchestrator** — not directly to the implementer. The orchestrator owns the brief and may narrow it before delegating.
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
| `M0-toolchain.md` | Toolchain | ready |
| `M1-walking-skeleton.md` | Walking skeleton | ready |
| `M2-environment-resolution.md` | Environment resolution | ready — **highest risk in the project** |

M3 onward are written after M2 passes, because M2's outcome may change what M3 needs to look like.

---

## A note on the M2 brief

M2 is the milestone where the project is most likely to go quietly wrong.

The code will compile, the output will look plausible, and the PATH will be **subtly incorrect**. Everything built on top of it will inherit that error, and it will present as a detector bug several milestones later — by which point it is expensive to find.

Do not let M2 pass on a visual inspection. Use the `diff` command in the brief. It either prints `MATCH` or it does not.
