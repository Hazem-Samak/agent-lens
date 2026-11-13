# M12-F R2 independent re-review — MiniMax (read-only)

**Candidate:** `a411661` — `feat(workflow): M12-F measurement + R2 hint fix (checkpoint)`.
**Diff base:** `255fd9c` (M12-F R1, the sidebar focus fix).
**Branch:** `milestone/m12-workflow`. **HEAD at review time:** `c0aec94` (`docs: add M12 hand-off
snapshot and resume prompt`) — `git diff --stat a411661..c0aec94` touches only `HANDOFF.md` and the
M12-E R1 review files, so **no product file differs between the candidate and HEAD**; the reviewed
candidate is the current product state.
**Scope of this review:** `git diff 255fd9c..a411661 -- Sources/AgentLensApp/PathActions.swift` —
exactly two changed lines (`:74` and `:85`).

**Reviewer:** MiniMax M3.1-Flash/xhigh, independent, read-only. No product edit, no git mutation,
no build/test, no system-setting change, no fixture run. This review markdown is the only write.

## Verdict

**PASS** — 0 blocking, 0 high, 0 medium, 1 low, 2 info.

The two-line fix is correct, minimal, and it closes a real R10 defect that static review could not
have caught. The AXHelp attribute for all four path buttons now carries the required hint text,
the accessible names are untouched, and nothing else in the button's behavior moved.

---

## 1. Verified points

### 1. `.help()` now equals the hint text, not the long action label — **confirmed**

`Sources/AgentLensApp/PathActions.swift` at `a411661`:

```swift
72:                .accessibilityLabel(actionLabel("Copy"))
73:                .accessibilityHint("Copies the path text.")
74:                .help("Copies the path text.")          // ← was .help(actionLabel("Copy"))
...
83:                .accessibilityLabel(actionLabel("Reveal in Finder"))
84:                .accessibilityHint("Asks Finder to select this path.")
85:                .help("Asks Finder to select this path.") // ← was .help(actionLabel("Reveal in Finder"))
```

The tooltip text no longer masks the AX help. Runtime proof from the worker's AX read against the
disposable fixture app (`$HOME/.hermes/cache/scratch/agent-lens-m12-f-r2/evidence/hint-fix-ax.log`):
all four path buttons now report the short help while their descriptions are unchanged —

```text
AXButton desc=Copy Selected Entry path for Codex            help=Copies the path text.
AXButton desc=Reveal in Finder Selected Entry path for Codex help=Asks Finder to select this path.
AXButton desc=Copy Resolved Target path for Codex           help=Copies the path text.
AXButton desc=Reveal in Finder Resolved Target path for Codex help=Asks Finder to select this path.
```

This satisfies the R10 clause quoted in the dispatch contract
(`briefs/M12-E-native-accessibility.md:98-99`: "Path buttons keep their current labels … and gain
hints 'Copies the path text.' / 'Asks Finder to select this path.'").

### 2. `.accessibilityLabel(...)` and `.accessibilityHint(...)` are unchanged — **confirmed**

The diff contains exactly two hunks, both touching a `.help(...)` line only. Lines `:72`, `:73`,
`:83`, `:84` are byte-identical to `255fd9c`; the accessible names still come from `actionLabel`
("Copy Selected Entry path for <tool>" / "Copy Resolved Target path for <tool>"), and the AX
descriptions in the evidence above confirm they did not move.

### 3. No behavior change beyond the tooltip/hint text — **confirmed**

By construction the delta is two literal strings, but I verified the surrounding behavior directly
in the candidate file rather than relying on that:

| Behavior | Candidate state |
|---|---|
| Button action | `perform(.copyPath)` (`:65-66`), `perform(.revealInFinder)` (`:76-77`) — unchanged |
| Visible control | `Label("Copy Path", systemImage: "doc.on.doc")` (`:68`), `Label("Reveal in Finder", systemImage: "folder")` (`:79`) — unchanged |
| Eligibility / disabled rule | `.disabled(!target.isActionable)` (`:71`, `:82`) — unchanged |
| Style | `.buttonStyle(.borderless)` (`:70`, `:81`) — unchanged |
| Dispatch | `perform(_:)` → `PathActionDispatcher.perform` (`:108-109`) — unchanged |
| Transient feedback + announcement | `.accessibilityLabel(feedback)` (`:102`) — unchanged |
| Ineligibility reason text | `Text(reason.reason)` with `.fixedSize(horizontal: false, vertical: true)` (`:90-95`) — unchanged |

R11 is unaffected: no new `.font(.system(size:))` literal, no `preferredColorScheme`, no
`windowResizability`, and the ineligible-path reason text keeps its semantic style and wrapping.

---

## 2. Concerns

### LOW-1 — the mouse tooltip lost the tool / entry-versus-target distinction that the previous
tooltip carried

`Sources/AgentLensApp/PathActions.swift:74`, `:85`.

Before the fix, hovering the Copy button showed **"Copy Selected Entry path for Codex"** — a string
that names the tool and distinguishes the entry from the target, which is what `briefs/M8-path-actions.md:44-45`
asks of the control's "accessible names/help": *"Use native controls and accessible names/help that
distinguish the tool and the entry versus target action."* After the fix the tooltip reads
"Copies the path text." for every one of the four buttons.

The distinction is **not lost to the user overall** — it survives in two other carriers that remain:
the accessible name ("Copy Selected Entry path for Codex" vs "Copy Resolved Target path for Codex",
`:72`/`:83`, confirmed unchanged in the AX evidence), and the visible row label the buttons sit in
("Selected Entry" / "Resolved Target"). So VoiceOver users and sighted users both still get the
distinction. What is reduced is the *hover* affordance for a sighted mouse user.

**Alternative that would have kept both:** apply `.accessibilityHint(...)` *after* `.help(...)`.
The base's failure mode is itself the evidence of the mechanism — `.help` was applied after
`.accessibilityHint` and therefore won the AXHelp attribute — so reversing the order should let the
hint own AXHelp while the tooltip keeps the long, distinguishing label. The chosen fix is correct
and satisfies R10; the reordering was simply not taken, at the cost of the hover text. Recorded for
the milestone record, not as a defect.

### INFO-1 — `.help()` and `.accessibilityHint()` now carry the same literal in two places

`PathActions.swift:73-74` and `:84-85`. The duplication is benign today and is arguably
drift-resistant, since the two attributes can no longer disagree about the hint (that disagreement
was the bug being fixed). But they are two separate literals, so a future edit that changes one and
not the other would reintroduce exactly the masking defect. A single shared constant used by both
modifiers would make the divergence structurally impossible. Not required for acceptance.

### INFO-2 — the base defect was invisible to static review, which is worth recording

My M12-E review verified `.accessibilityHint("Copies the path text.")` was present in source and
passed it. The hint *was* in the source the whole time — it simply never reached AXHelp, because
the later `.help(...)` overrode the attribute. Only a runtime AX read (which M12-F performed)
could have caught that. This is a limit of source review worth carrying into the milestone record:
"the modifier is present" is not the same as "the attribute reaches the assistive technology".

---

## 3. Scope and attribution check on the surrounding range

The range `255fd9c..a411661` also contains `3212255` (`ci: raise M12 test floors to
orchestrator-measured counts (R12)`), which is **not** an implementer change:

- R12 requires the floors to move "only at combined acceptance, only upward, only to
  orchestrator-measured counts at the frozen candidate SHA, **in a separate orchestrator commit**";
  the implementer never edits `ci.yml`. The commit is that separate orchestrator commit, and it
  sets AppSupport 80 → 119, `total_floor` 547 → 586, `combined_total_floor` 547 → 586, with the Core
  floor left at 467 — upward only, to the measured counts ✓.
- `a411661` itself contains only `Sources/AgentLensApp/PathActions.swift` (2 changed lines),
  `walkthroughs/M12-F-measurement.md` (the orchestrator's measurement record), and the two review
  files. No Core, AppSupport, CLI, registry, test, fixture, script, or packaging file changed ✓.

---

## 4. Sign-off

Reviewed-by: MiniMax M3.1-Flash/xhigh (independent, read-only)

**PASS — 0 blocking, 0 high, 0 medium, 1 low, 2 info.** The R2 hint fix is exactly the two lines
the brief scoped, it makes AXHelp carry the R10-required hint on all four path buttons with the
accessible names untouched, and it changes no behavior beyond the tooltip text. The one low note is
that the visible mouse tooltip now carries the short hint instead of the tool-and-target
distinguishing label; the distinction remains in the accessible name and the visible row label, and
reordering the two modifiers would have preserved both.
