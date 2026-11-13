# M12-F R1 independent review — MiniMax (read-only)

**Candidate:** `255fd9c` on `milestone/m12-workflow` (HEAD).
**Base:** `775d5bc` (M12-E accepted tip). **R1 delta inspected:** `git diff 775d5bc..255fd9c` —
`Sources/AgentLensApp/MainWindow.swift` (+95/−22) and `walkthroughs/M12-F-implementation.md`.
**Contract:** `briefs/M12-plan.md` §5 M12-F; `briefs/M12-planning/judgment.md` R1, R10;
`briefs/M8-path-actions.md` (the gate); `walkthroughs/M12-F-implementation.md` (worker evidence).
**Reviewer:** MiniMax M3.1-Flash, independent, read-only. No product/test/brief file was edited, no
git mutation, no install, no subagent, no build/test/destructive fixture, no system setting flipped.
This file is the only write.

## Verdict

**PASS** — 0 blocking, 0 high, 0 medium, 1 low, 4 info.

The fix is minimal (one file, three hunks), evidence-backed, and preserves every behavior the
review was asked to confirm. The sidebar rows keep the selection write, the snapshot-derived badge,
the spoken label with its count, the VoiceOver activation, and arrow-key navigation; the
destination wiring, sheet bindings, conflict navigation, menus, C-1 footers, and public
initializers are untouched; the traversal evidence is real and independently reproduced; and the
diff stays inside the allow-list with a clean protected manifest.

One low finding: the structural swap replaces the native sidebar `List` with hand-drawn rows, so
the **appearance** of an M12-B-accepted surface changes in the final phase. Nothing functional is
lost, and M12-F's light/dark and narrow-window screenshots are exactly the gate for it — but it
should be compared explicitly against the M12-B accepted screenshots rather than assumed
equivalent.

---

## 1. The sidebar rows preserve every required property — **verified**

`Sources/AgentLensApp/MainWindow.swift:371-419` (`sidebarRow`) against the base `List` rows:

| Required property | Base (`775d5bc`) | R1 candidate | Result |
|---|---|---|---|
| Selection write = the single R1 invalidation path | `List(selection: _selectedDestination.projectedValue)` → `NavigationLink(value:)` | `Button { selectedDestination = destination }` (`:372-374`) → the same `.onChange(of: selectedDestination)` → `applyDestination` (`:78`) | ✓ same State, same path |
| Badges (`badgeCount`) | `Text("\(badge)")` with `.caption2` / `.secondary` / `.monospacedDigit()` | identical rendering at `:384-388` | ✓ |
| Spoken label with the count | `.accessibilityLabel(accessibilityLabel(for: destination))` (M12-E R1) | identical at `:400`, same helper at `:396-400` | ✓ |
| `.isSelected` trait | *(not present — the List conveyed selection itself)* | `.accessibilityAddTraits(selectedDestination == destination ? .isSelected : [])` at `:401` | ✓ **added** |
| VoiceOver activation | `.accessibilityAction { selectedDestination = destination }` | identical at `:404-406` | ✓ |
| Arrow-key navigation | List's own arrow handling | `.onKeyPress(.downArrow/.upArrow)` at `:408-414` → `moveSidebarFocus` (`:420-427`), wrapping via `(index + offset + count) % count`, moving **both** selection and focus | ✓ |

The `.isSelected` trait is a genuine improvement over the base: the selected destination is now
announced as "selected" rather than being conveyed only by the List's own selection semantics.

**The R1 invalidation path is untouched.** The Button writes `selectedDestination`; the single
`.onChange(of: selectedDestination)` handler at `MainWindow.swift:78` still calls `applyDestination`
(`:256-278`), which writes only `model.listScope` / `model.detailPane` — so the ViewModel's R1
`didSet` hooks remain the only invalidation trigger. The App still adds no second one ✓.

**Arrow navigation is evidenced end to end.** `focus-arrows.log` (worker probe): start "Overview, 4"
→ down → "AI Agents, 5" → down → "AI Coding Tools, 1" → up → "AI Agents, 5", and Shift-Tab from
the sidebar leaves it ("shift-tab from Overview: AXTextField" → "Refresh Updates") — so reverse
traversal is no longer trapped either ✓.

---

## 2. No regression of M12-B/C/D/E behavior — **verified**

- **`applyDestination`** (`MainWindow.swift:256-278`) — not in the diff ✓; the destination → scope
  mapping (Overview → `.all`, categories → `.category(…)`, Updates → `.updates`, Diagnostics/Settings
  → `detailPane` only, hence no scope change and no invalidation) is unchanged.
- **Sheet bindings** — not in the diff; `updateSheetBinding` / `uninstallSheetBinding` and the two
  `.sheet` presentations are untouched ✓.
- **Conflict navigation** — `MainWindow.swift:222-225` (`model.showPathEvidence(registryID:)`) is
  untouched, and the traversal log shows the four "Show PATH evidence for …" conflict buttons live
  and reachable as Tab stops 7–10 ✓. `ConflictSummaryView.swift` is not in the diff ✓.
- **Overview's search→category navigation** — `MainWindow.swift:218-221` untouched ✓.
- **Menus and C-1** — `AgentLensApp.swift` is not in the diff; the App-wide shortcut inventory is
  still **20** (14 menu + 6 sheet-footer) ✓, and `grep -rn "confirmSelected" Sources/AgentLensApp/`
  still returns only the two accepted sheet callbacks (`MainWindow.swift:113`, `:138`) ✓. No menu
  item can confirm ✓.
- **R11 layout constraints** — `preferredColorScheme`, `windowResizability`, and
  `.font(.system(size:` remain absent from `Sources/AgentLensApp/` ✓; `.frame(minWidth: 760,
  minHeight: 480)` is untouched ✓.
- **The content and detail columns are driven by `selectedDestination`, not by the split view's List
  selection** (`MainWindow.swift:208-230` switches on `selectedDestination`), so removing the
  `List(selection:)` binding does not change what any column renders ✓.
- **`NavigationLink(value:)` was used nowhere else in the App** — the sidebar was the only user of
  it, so nothing else depended on the split view's selection-driven navigation ✓.

---

## 3. The keyboard traversal evidence — **read, and it holds up**

`focus-traversal-attempt1.log` and `focus-traversal-attempt2.log` show the complete forward order
from the selected sidebar destination:

```text
1–6    AXButton  AI Agents, 5 / AI Coding Tools, 1 / AI Harnesses, 3 / Updates, 0 / Diagnostics / Settings
7–10   AXButton  Show PATH evidence for Codex / Cline CLI / Oh My Pi / DeepSeek Harness
11     AXButton  Copy Selected Entry path for Codex
12     AXButton  Reveal in Finder Selected Entry path for Codex
13     AXButton  Copy Resolved Target path for Codex
14     AXButton  Reveal in Finder Resolved Target path for Codex
15     AXButton  Verify Installation for Codex
16     AXLink    https://developers.openai.com/codex/cli
17+    toolbar   Hide Sidebar / Rescan / …
```

Stops **11–14 are exactly the four detail path-action buttons** the M8 gate requires, so the
keyboard-only blocker (Tab trapped in the sidebar's cells) is resolved.

**The two logs are independent runs, not copies.** They differ only in the recorded pid (38696 vs
39025) and were written 14 seconds apart — two separate app launches that produced identical
traversal sequences. The report's claim that "both runs show the complete forward order" is accurate
✓.

**The evidence set is honest.** The failed synthetic runs are filed unedited and are *not* presented
as passes: `focus-verification.log` (every stop an `AXGroup`; "reached AI Agents via shift-tab:
false"), `focus-sidebar-space.log` (stops on the search `AXTextField`), and
`focus-gate-probe.log` (the pre-fix investigation, including the `AXOutline` trap and the
`.focusable(false)` experiments). The worker's §3 caveat names these explicitly and states that
the orchestrator's real-key M8 measurement remains authoritative ✓. The rejected alternatives
(`.focusable(false)` on the rows → `AXOutline` trap; on the List → the sidebar leaves the key loop
entirely) are documented, which is what justifies replacing the container rather than tuning it.

---

## 4. Scope — **clean**

```text
git diff --name-only 775d5bc..255fd9c
  Sources/AgentLensApp/MainWindow.swift
  walkthroughs/M12-F-implementation.md

git diff 775d5bc..255fd9c -- Sources/AgentLensApp/MainWindow.swift   → 3 hunks:
  @@ -36,6 +36,12 @@   (the FocusState property)
  @@ -333,32 +339,16 @@ (sidebarView: List+NavigationLink → ScrollView+VStack)
  @@ -374,6 +364,67 @@ (sidebarRow + moveSidebarFocus)
```

Filtering for `AgentLensCore`, `agent-lens`, `AgentLensAppSupport`, `Package.swift`, `scripts/`,
`.github`, `Tests/`, `Resources/`, `docs/`, `DECISIONS.md`, `ROADMAP.md`, `AGENT_LENS_SCOPE.md` →
**no match** ✓. The protected-manifest log (`protected-manifest-vs-base-775d5bc.log`) shows exactly
one difference: `MainWindow.swift` (base `75a4c19f…` → candidate `00b10131…`) ✓. The committed
file's SHA-256 is `00b10131abfd640bb6256d57ff7e050d1e1eb68f0d150d6aab9065d45deed015`, matching the
worker's manifest exactly ✓ — the reviewed tree is the measured tree.

`onKeyPress` requires macOS 14; `Package.swift:7` declares `.macOS(.v14)` ✓.

---

## 5. Severity-ranked findings

### BLOCKING — none
### HIGH — none
### MEDIUM — none

### LOW

**LOW-1 — the native sidebar `List` is replaced by hand-drawn rows, so an M12-B-accepted visual
surface changes in the final phase.**
`Sources/AgentLensApp/MainWindow.swift:341-368` (sidebarView) and `:371-419` (sidebarRow).

The base used `List(..., selection:)` with `.listStyle(.sidebar)`, which gave the column the
system sidebar material, the native selected-row treatment, and list semantics. The candidate uses
a `ScrollView` + `VStack` of `.buttonStyle(.plain)` buttons with a hand-drawn selection fill
(`Color.accentColor.opacity(0.2)` inside a `RoundedRectangle(cornerRadius: 6)`, `:392-397`), custom
row metrics (`.padding(8)` on the stack plus `.padding(.horizontal, 8)` / `.padding(.vertical, 5)`
per row), and `.symbolRenderingMode(.multicolor)` on the destination icons (`:377`) — the icons
were rendered with the default mode in the accepted M12-B sidebar.

This is a side effect of a change that was **necessary and evidence-backed**: the worker's probe
shows `.focusable(false)` on the rows produced an `AXOutline` trap and `.focusable(false)` on the
List removed the sidebar from the key loop entirely, so replacing the container was the smallest
structure that keeps every destination reachable while removing the cell loop. Nothing functional
is lost — the selection write, badge, spoken label with count, `.isSelected` trait, VoiceOver
activation, and arrow navigation are all preserved or improved (see §1).

So this is not a defect; it is a visual delta the owner should look at deliberately. M12-F's
light/dark and narrow-window screenshots are exactly the gate for it, and the comparison to
against is the M12-B accepted screenshot set. The custom selection highlight and the multicolor
icons are approximations of native macOS sidebar styling and are the two most likely to read as a
regression in a dark-mode screenshot.

### INFO

**INFO-1 — arrow-key destination navigation is now focus-dependent.**
`MainWindow.swift:408-414`. The base `List` took the window's initial keyboard focus, so arrow
keys moved the selection immediately. With real `Button`s, the arrow handler only runs while a
sidebar row holds focus. `focus-arrows.log` shows the initial focused element was the first row
("start: role=AXButton desc=Overview, 4"), and arrows then worked correctly; but
`focus-verification.log` and `focus-space-activation.log` show the initial focused element as an
`AXGroup` in other runs, in which case arrows do nothing until the user Tabs into the sidebar.
The orchestrator's real-key pass should confirm arrows work from a cold launch.

**INFO-2 — the worker's Space-activation probe used a personal installation path and is not the M8
gate.**
`focus-space-activation.log` and `focus-gate-probe.log`: Space on the focused Copy button produced
`/Users/corvette/.local/bin/codex` — a real personal path. Copy is read-only and the clipboard was
saved and restored, so nothing was harmed; but M12-F's method requires the authoritative M8
measurement to use the disposable M10-D fixture environment ("never a personal path"), and the
activation here was performed on a **programmatically focused** button (`set focus copy err=0`),
not reached by Tab in the same run. The two halves of the gate are demonstrated in separate runs —
Tab reaching the buttons (attempt1/attempt2) and Space activating a focused Copy
(space-activation) — so this probe must not be read as the M8 gate passing. The orchestrator's
real-key measurement remains the gate, per the plan's method.

**INFO-3 — the explicit `.accessibilityAction` on the rows is now redundant.**
`MainWindow.swift:404-406`. A `Button` gives VoiceOver a native press action, so the explicit
default action is a second route to the same `selectedDestination` write. It is harmless, it keeps
M12-E R1's contract literally intact, and it writes the same State — keep or drop, no behavioral
difference.

**INFO-4 — the R1 commit also carries the two M12-E reviewer artifacts.**
`255fd9c` contains the product file, the worker report, and
`walkthroughs/M12-E-evidence/reviews/{grok-r1,minimax-r1}.md` — reviewer files that were untracked
at the time. Git delivery is the orchestrator's (the M12-D precedent filed the reviews in a
separate `docs:` commit), so this is an orchestrator-side accounting detail, not an implementer
scope issue. The implementer's product delta is one file plus its report, and the protected
manifest confirms exactly that ✓.

---

## 6. Residual risks and forward notes

1. **M12-F's real-key measurement is the gate, and two things should be checked there specifically:**
   a single continuous run (Tab from the top of the window to the Copy button, then Space) for
   **each** of the four controls, in the disposable M10-D fixture environment; and arrows working
   from a cold launch (INFO-1).
2. **Compare the M12-F sidebar screenshots against the M12-B accepted set** (LOW-1), particularly in
   dark mode, for the custom selection fill and the multicolor icons.
3. **The fix pattern generalizes**: any future view that uses a `List` with cells can re-introduce
   a cell-level Tab trap. If M12-B/C/D surfaces ever add a `List`, it should be checked against the
   same traversal probe rather than assumed safe.
4. **The R1 revision rule in the plan named `PathActions.swift` + `ToolDetailView`'s path rows as
   the expected allow-list for a focus failure.** The implementer instead changed the sidebar
   container in `MainWindow.swift`, justified by the probe evidence that the `List`'s cells — not
   the path buttons — owned Tab. The outcome is correct and the evidence is filed; recording it
   only so the plan's default expectation and the actual repair site are not conflated in the
   milestone record.

---

## 7. Checks performed

```text
git rev-parse HEAD                                     → 255fd9cd76fb5cdd964467a1a5fd091decd0d713
git diff --name-only 775d5bc..255fd9c                  → MainWindow.swift + worker report
git diff --name-only 775d5bc..255fd9c | grep -E "AgentLensCore|agent-lens|AgentLensAppSupport|
    Package.swift|scripts/|\.github|Tests/|Resources/|docs/|DECISIONS.md|ROADMAP.md|
    AGENT_LENS_SCOPE.md"                                                   → empty
git diff --check 775d5bc..255fd9c                     → (worker diff-check.log exit 0)
shasum -a 256 Sources/AgentLensApp/MainWindow.swift     → 00b10131…015 (matches worker manifest)
grep -rn "confirmSelected" Sources/AgentLensApp/       → only MainWindow.swift:113 and :138
grep -c "keyboardShortcut" Sources/AgentLensApp/*.swift → 20 (unchanged)
grep -rn "preferredColorScheme|windowResizability|\.font(\.system(size:" Sources/AgentLensApp/ → none
grep -rn "NavigationLink(value:\|projectedValue" Sources/AgentLensApp/ → only the new FocusState binding
diff focus-traversal-attempt1.log focus-traversal-attempt2.log → pid differs only (two real runs)
```

Read but not executed: the worker evidence logs under
`$HOME/.hermes/cache/scratch/agent-lens-m12-f-r1/evidence/`. No build, no test suite, no destructive
fixture, no personal-path action, no system-setting change, and no product file was touched by this
reviewer.
