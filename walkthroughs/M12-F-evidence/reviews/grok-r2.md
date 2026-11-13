# M12-F R2 independent re-review — hint fix

**Candidate:** `a411661` (`feat(workflow): M12-F measurement + R2 hint fix (checkpoint)`) on `milestone/m12-workflow`. Working HEAD at review time is `c0aec94` (a later docs commit). The candidate under review is `a411661`.
**Diff base:** `255fd9c`.
**Scope:** `git diff 255fd9c..a411661 -- Sources/AgentLensApp/PathActions.swift` only. That product diff is two lines. The same commit range also records reviews, `walkthroughs/M12-F-measurement.md`, and the earlier CI-floor commit `3212255`. Those are outside this review. No product file other than `PathActions.swift` is judged here.
**Reviewer:** Grok, independent, read-only. No product edit, no git mutation, no build, no test, no system-setting change. This file is the only write.

## Verdict

**PASS** — 0 blocking, 0 high, 0 medium, 0 low, 1 info.

`.help()` now carries the R10 hint sentence. The accessible name is still the long action label. Button actions, eligibility, and feedback are unchanged.

## Verified

### 1. `.help()` is the hint text, not the long action label

`PathActions.swift:74` is `.help("Copies the path text.")`.
`PathActions.swift:85` is `.help("Asks Finder to select this path.")`.

Before this diff those calls were `.help(actionLabel("Copy"))` and `.help(actionLabel("Reveal in Finder"))`. `actionLabel` (`PathActions.swift:52-54`) is `"\(verb) \(rowLabel) path for \(toolName)"`, the same string as the accessibility label. On macOS, `.help()` supplies the tooltip and `AXHelp`, and a later `.help()` was winning over `.accessibilityHint()`, so `AXHelp` repeated the button name. The tooltip and `AXHelp` are now the hint.

`hint-fix-ax.log` (four path buttons, plus the untouched Verify button):

```text
desc=Copy Selected Entry path for Codex                         help=Copies the path text.
desc=Reveal in Finder Selected Entry path for Codex             help=Asks Finder to select this path.
desc=Copy Resolved Target path for Codex                        help=Copies the path text.
desc=Reveal in Finder Resolved Target path for Codex            help=Asks Finder to select this path.
```

`desc` is still the long label. `help` is the short hint. The empty `label=` field in that log is the harness title slot; the spoken name is `desc`.

### 2. Hint and label modifiers are unchanged

`PathActions.swift:72` is still `.accessibilityLabel(actionLabel("Copy"))`.
`PathActions.swift:73` is still `.accessibilityHint("Copies the path text.")`.
`PathActions.swift:83` is still `.accessibilityLabel(actionLabel("Reveal in Finder"))`.
`PathActions.swift:84` is still `.accessibilityHint("Asks Finder to select this path.")`.

The diff does not touch those four lines. Visible button titles stay `Label("Copy Path", …)` (`:68`) and `Label("Reveal in Finder", …)` (`:79`).

### 3. No other behavior change

The diff does not touch `perform`, `PathActionDispatcher`, `disabled(!target.isActionable)`, feedback strings, or `NSAccessibility.post`. Copy still runs `.copyPath` (`:66`). Reveal still runs `.revealInFinder` (`:77`). Ineligibility and feedback wrapping are the same (`:90-94` and the feedback block below).

### R10 / R11

The hint sentences match R10: "Copies the path text." and "Asks Finder to select this path." Labels stay "Copy/Reveal \<row\> path for \<tool\>". This diff adds no `.font(.system(size:))`, no `lineLimit` truncation, and no color or layout change. Tab/Space traversal and VoiceOver captions are recorded in `walkthroughs/M12-F-measurement.md` and `walkthroughs/M12-F-implementation.md`; they are not re-measured here. The AX log above is the R2 proof that `AXHelp` now matches the hint.

## Findings

### INFO-1 — Hint text is now on both modifiers, on purpose

`.accessibilityHint` and `.help` carry the same sentence (`PathActions.swift:73-74` and `:84-85`). That is duplicated source text. It is required: `.help()` is what macOS publishes as `AXHelp` and as the tooltip, and it was masking the hint. Removing either modifier would drop either the SwiftUI hint or the tooltip/`AXHelp`. The two literals should stay equal if one is edited later.

## Sign-off

Reviewed-by: Grok 4.7/high (independent, read-only)
