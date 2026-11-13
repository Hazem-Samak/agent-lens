# M12-F measurement — WORKER EVIDENCE (not acceptance)

**This is worker measurement evidence, not acceptance.** The orchestrator owns the M8 gate decision
and the final record. No product code was changed for this measurement (git tree: no tracked file
modified; only this report and evidence are new).

- Base: `775d5bc` (M12-E accepted tip), milestone/m12-workflow.
- Evidence root: `$HOME/.hermes/cache/scratch/agent-lens-m12-f-measure/evidence` (INDEX below).
- Disposable environment: `$R/env` — synthetic `HOME`, `ZDOTDIR`, `TMPDIR`, `CFFIXED_USER_HOME`,
  a fixture `codex` executable under `env/prefix/lib/node_modules/@openai/codex/bin/`, a symlink
  `env/bin/codex` on the resolved login-shell PATH. `debug-env-fixture.log` proves
  `degraded: false` and exactly the fixture PATH (no personal installation path).
- App: debug bundle built by `scripts/build-dev-app.py` into `$R/dev-app`, launched directly with
  the synthetic environment (so the login-shell capture sees the fixture PATH). No Check/Refresh
  was pressed, so the real Agent Lens cache was not touched.
- Tool used: dev app + macOS Accessibility API (`AXUIElement`, real `CGEvent` Tab/Space/arrow
  keys). Full Keyboard Access was already `AppleKeyboardUIMode=3`; it was not changed.

## 1. Result summary

| Area | Result |
|---|---|
| M8 keyboard matrix (four path buttons, Tab + Space, fixture paths) | **PASS** (details §2) |
| Category content-list Tab traversal (Grok INFO-3) | **PASS** — Tab leaves the list and reaches the four detail buttons (§3) |
| VoiceOver spoken checks | **PARTIAL** — captions captured for both path buttons, the unavailable sentence, and the path-feedback announcement; the list row and Settings captions were not captured (AX + item-chooser evidence instead). One R10 **defect** found: path-button hints are masked by the tooltip (§4) |
| Large text / wrapping | **PARTIAL** — `.dynamicTypeSize(.accessibility5)` did not scale macOS semantic text; at 320 pt width the safety sentence wraps to two lines (frame height 30) with the full AX value (§5) |
| Light / dark | **PASS** — screenshots in both, system appearance restored to Dark (§5) |
| 760×480 minimum | **PASS** — a 700×400 resize request clamps to 760×532 window (content 480 high), restored 960×600 (§5) |
| Settings restoration | FKA 3→3, appearance Dark→Dark, VoiceOver off→off, clipboard none→none, fixture SHA unchanged, window 960×600 (§6) |

## 2. M8 keyboard matrix (disposable fixture)

Starting focus: the content `ToolListView` (category AI Agents), fixture executable installed.
`Tab 1` = content scroll bar; the four path buttons are Tab stops 2–5 in this order:

| # | Tab stop (role/description/frame) | Space activation evidence |
|---|---|---|
| 2 | `AXButton Copy Selected Entry path for Codex` (774,407) 74×16 | clipboard byte-equal to `env/bin/codex`; SHA-256 `3c6b4be7…` = expected; clipboard restored |
| 3 | `AXButton Reveal in Finder Selected Entry path for Codex` (860,407) 105×16 | Finder selection = `alias file codex of folder bin of folder env …` (the symlink; saved) |
| 4 | `AXButton Copy Resolved Target path for Codex` (774,539) 74×16 | clipboard byte-equal to `env/prefix/lib/node_modules/@openai/codex/bin/codex`; SHA-256 `f9cea9fd…` = expected; clipboard restored |
| 5 | `AXButton Reveal in Finder Resolved Target path for Codex` (860,539) 105×16 | Finder selection = `document file codex of folder bin of folder codex of folder @openai …` (the canonical target; saved) |

Raw: `m8-copy-selected.log`, `m8-copy-resolved.log`, `m8-reveal-selected-r3.log`,
`m8-reveal-resolved-r2.log`, `finder-selection-selected.txt`, `finder-selection-resolved.txt`,
`finder-reveal-*.png`. Fixture digests: `fixture-hashes.txt`; target SHA-256
`a6a4a3b76d07034ad3a1f59de71e0314dedbfdbea7d7eba8a269073fb3d94fc3`, unchanged after measurement.
Clipboard save/restore: `clipboard-restore.log` (before none, after none).

## 3. Category content-list traversal (Grok INFO-3)

`category-list-traversal.log` starts on the AI Agents content `AXOutline` (231,132) 407×548:

```text
tab 1  AXScrollBar
tab 2  AXButton Copy Selected Entry path for Codex
tab 3  AXButton Reveal in Finder Selected Entry path for Codex
tab 4  AXButton Copy Resolved Target path for Codex
tab 5  AXButton Reveal in Finder Resolved Target path for Codex
tab 6  AXButton Verify Installation for Codex
tab 7  AXLink information URL
tab 8  Hide Sidebar … tab 12 search field, then the seven sidebar destination buttons
```

Tab does **not** trap in the category content list; it leaves for the detail path buttons. No focus
defect was found in the content list, so no product change was made.

## 4. VoiceOver spoken checks (caption panel)

VoiceOver was started from the pre-existing Quickstart (`Use VoiceOver`), and the caption panel was
screen-captured at `(100,936) 600×110`. Captured captions (raw PNGs in `evidence/voiceover/`):

| Stop | Caption text (worker transcription of the PNG) | Raw file |
|---|---|---|
| Copy Selected Entry button | "Copy Selected Entry path for Codex, button" | `caption-01-copy-selected.png`, `caption-13-left-copy-selected.png` |
| Reveal Selected Entry button | "Reveal in Finder Selected Entry path for Codex, button" | `caption-11-right.png` |
| Unavailable sentence (Manage) | "Verify Installation to enable Uninstall for this npm package." | `caption-33-unavailable.png` |
| Path-feedback announcement (VO activation of Copy) | "Copied path to clipboard." | `caption-34-list-row.png` |
| Window/toolbar | "Agent Lens, window, toolbar" | `caption-41-settings-real.png` |

AX evidence for the stops that could not be captioned:

- List row: the row's AX value is exactly
  `Codex, codex, Installed and on PATH, AI Agent, version 0.0.1`
  (category and version present; no conflict kinds for this fixture; "version unknown" rows show
  that phrase). The VoiceOver item chooser screenshot also shows this label:
  `voiceover/item-chooser-list.png`.
- Path buttons: AX descriptions as above; the unavailable sentence and the cask sentence are
  `AXStaticText` elements with the full values (`voiceover/ax-dump-aiagents.log`).
- Settings: `voiceover/ax-dump-settings.log` shows the read-only headings and statements
  (`Settings apply to this window…`, `Catalogue`, `14 known tools`, `Managed Operations`,
  `Environment`, `What Agent Lens Does Not Do`); `screen-settings-vo.png` shows the Settings
  destination. A caption for the Settings content itself was not captured (VO focus remained on
  the toolbar), so this stop is AX + visual, not spoken-caption evidence.

**R10 defect found (product), fixed in R2.** `AXHelp` for each of the four
path buttons equals the button's label, not the required hints "Copies the path text." / "Asks
Finder to select this path." (`voiceover/ax-dump-aiagents.log`). The cause is visible in
`PathActions.swift`: `.help(actionLabel(…))` is applied after `.accessibilityHint(…)`, so the
tooltip text wins the AXHelp attribute. This is an accessibility defect, not a focus defect, and no
product code was changed in this measurement phase.

VoiceOver was quit afterwards; no VoiceOver process remains.

## 5. Large text, light/dark, narrow

- **Large text**: an offscreen/temporary `NSHostingView` host compiled from the shipping
  `ToolDetailView`/`UpdateOperationView` sources with `.environment(\.dynamicTypeSize,
  .accessibility5)`:
  - At 760 pt width: safety sentence AX frame `347×15` (`large-text-ax.log`). The dynamic-type
    environment did **not** increase macOS semantic font sizes in this environment; the sentence
    was a single line at its normal size. This is recorded as an environment limitation, not a
    scale pass.
  - At 320 pt width: the same sentence AX value is intact and its frame is `232×30`
    (`large-text-ax-narrow.log`) — it wraps to two lines; no truncating line limit.
  - The rendered PNGs from the offscreen host are unusable for appearance review (bitmap caching
    under a windowless host produced a white/inverted image); the AX frame/value is the
    measurement.
- **Light/dark**: system appearance was Dark; switched to Light with System Events, captured
  Overview and the tool detail, then restored Dark (`app-light-overview.png`,
  `app-light-detail.png`, `app-dark-overview.png`, `app-dark-detail.png`). The app follows the
  system appearance (no override in the app).
- **Narrow**: requesting a 700×400 window clamps to **760×532** (the 760×480 content minimum);
  `app-narrow-760x480.png` (window 760×532), `app-narrow-clamped.png`. Restored 960×600
  (`app-restored-960x600.png`).

## 6. Restoration record

`environment-state.log`:

```text
FKA AppleKeyboardUIMode before=3 after=3
Appearance before=Dark after=Dark
VoiceOver before=off after=off
Window size before=960x600 after=960x600
Clipboard before=<none> after=<none>
Fixture target sha256 unchanged: a6a4a3b7…d94fc3
```

No product code changed; nothing staged/committed. The temporary probe app/host under `$R` and the
debug app are disposable; the personal Agent Lens cache and credentials were not touched.

## 7. Evidence index

`evidence/`: `INDEX.md` (full list), `debug-env-fixture.log`, `app-*.png` (light/dark/narrow),
`m8-*.log`, `finder-*`, `category-list-traversal.log`, `large-text-*`, `fixture-hashes.txt`,
`clipboard-restore.log`, `environment-state.log`, and `voiceover/` (caption PNGs, AX dumps, item
chooser screenshots, state record).

## 8. R2 follow-up (hint fix + remaining VoiceOver captions)

Evidence root: `$HOME/.hermes/cache/scratch/agent-lens-m12-f-r2/evidence`.

### Hint fix

`Sources/AgentLensApp/PathActions.swift`: the Copy/Reveal buttons now pass the required hint text to
`.help(...)` ("Copies the path text." / "Asks Finder to select this path.") while keeping
`.accessibilityHint(...)` and the accessible labels unchanged; the tooltip became the short hint
instead of the long action label. AX proof against the disposable fixture app
(`hint-fix-ax.log`):

```text
Copy Selected Entry path for Codex        help=Copies the path text.
Reveal in Finder Selected Entry path…     help=Asks Finder to select this path.
Copy Resolved Target path for Codex       help=Copies the path text.
Reveal in Finder Resolved Target path…    help=Asks Finder to select this path.
```

Labels are unchanged; no other behavior changed.

### Remaining VoiceOver captions (list row, Settings)

A fresh VoiceOver session was started from Quickstart on the disposable fixture app. The Item
Chooser opened and listed the row with its full spoken label
(`voiceover-item-chooser-row.png`):

```text
Codex, codex, Installed and on PATH, AI Agent, versio…
```

Filtering the chooser to "Installed and on PATH" and choosing it moved VO into the row's scroll area,
where the caption panel emitted only the scroll-area help/interact instructions; the same happened
when trying to reach the Settings text. Repeated capture attempts
(`caption-53-chooser-fresh.png`, `caption-54-chooser.png`, `caption-55-list-row.png`,
`caption-56-row-f4.png`, `caption-57-row-f3.png`) produced help text, not the element label, so no
dedicated row or Settings-content caption was obtained in R2. The VO commands tried included
VO+arrows, VO+Shift+Up (stop interacting), VO+I (Item Chooser), and VO+F3/F4 (describe).

AX evidence for those two stops remains exact:

- List row: `AXStaticText` value
  `Codex, codex, Installed and on PATH, AI Agent, version 0.0.1` (from the first measurement's
  `voiceover/ax-dump-aiagents.log`; row label includes category and version, no conflict kinds for
  this fixture).
- Settings: `voiceover/ax-dump-settings.log` shows the read-only headings/statements
  (`Settings apply to this window…`, `Catalogue`, `14 known tools`, `Managed Operations`,
  `Environment`, `What Agent Lens Does Not Do`).

Recorded reason: with the VO cursor inside the app's scroll-area text, the caption panel reports
interact/help instructions for text elements and did not surface the row or Settings element label
before the session was closed. VoiceOver was quit and all settings restored; no product code beyond
the hint fix was changed.

### R2 gates

| Target | Result |
|---|---|
| Full gate set | every command exit 0 |
| Core / AppSupport | **467 + 119 = 586** passed, zero failures/skips |
| Import guards | Core 32 files clean; AppSupport 6 files clean |
| Fixtures / packaging | 21 OK / 9 OK |
| Dev app | built |
| Protected tree | only `Sources/AgentLensApp/PathActions.swift` and this report differ from HEAD `3212255`; the manifest vs base `775d5bc` also shows the already-committed orchestrator changes (`255fd9c` sidebar fix, `3212255` CI floors), not R2 edits |

Raw R2 evidence: `$HOME/.hermes/cache/scratch/agent-lens-m12-f-r2/evidence` (`hint-fix-ax.log`,
`voiceover-item-chooser-row.png`, `voiceover-item-chooser-filtered.png`, `caption-53…57` VO attempts,
`voiceover-state.log`, gate logs, `changed-files.sha256`).

Changed-file SHA-256 (R2):

```text
820ae93f22aac402a2c72f4f5a6c730b048c933a8be447b79cc7516a705ea600  Sources/AgentLensApp/PathActions.swift
```

System state: VoiceOver was off before and is off after. Appearance Dark before/after. Full Keyboard
Access was `3` at R2 start; during the gate run an external orchestrator restore command
(`defaults delete -g AppleKeyboardUIMode`) removed the key, and the final state is left
**unset/off** to match that orchestrator-controlled restoration (the worker did not change it while
measuring; it only re-wrote `3` once when the key was found missing, then removed it again to align
with the orchestrator's restore). The fixture app process and temporary host were stopped.


