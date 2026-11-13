# M12-F implementation — WORKER EVIDENCE (M12-F R1, not acceptance)

**This document is worker evidence, not acceptance.** The orchestrator owns the M8 keyboard gate,
VoiceOver measurement, and every system toggle (OD-M12-1); it reruns all gates independently (D-014).
This R1 answers the orchestrator-measured finding that Tab could not leave the sidebar, so the four
detail path-action buttons were not keyboard-reachable.

- Base: `775d5bc` (M12-E accepted tip). Candidate: **uncommitted working tree**; nothing staged,
  committed, or pushed.
- Allow-list used: `Sources/AgentLensApp/MainWindow.swift` (focus management) and this report. No
  AppSupport/Core/CLI/registry/tests/fixtures/scripts/.github change; no system setting was flipped.
- Evidence root: `$HOME/.hermes/cache/scratch/agent-lens-m12-f-r1/evidence`.

## 1. Finding and investigation

The reported failure: with Full Keyboard Access on, Tab entered the sidebar `List` and cycled through
its cells; the four `PathActionRow` Copy/Reveal buttons in the detail column were never reached.

Investigated with the macOS Accessibility API plus real key events against debug builds (no source
instrumentation):

- The sidebar `List` exposes its rows as `AXOutline`/`AXRow`/`AXCell` key-loop participants. Which
  of those becomes the Tab stop depends on the window's focus state; the orchestrator measured a
  cell-level loop (`AXCell` cycling), and a probe on this workstation reproduced a complete
  `AXOutline` trap after the rows were made non-focusable (`evidence/focus-gate-probe.log` earlier
  runs). In every trapping state the sidebar stayed in its own key loop.
- Global HID Tab plus system-wide `AXFocusedUIElement` reads show that the **accepted List sidebar
  is not guaranteed** to be one stop: its internal cells can own Tab, and the detail buttons then
  never enter the loop.
- The detail buttons themselves are standard `AXButton`s and are activatable (Space copies the
  exact path); the blocker is reaching them.

## 2. Fix

`Sources/AgentLensApp/MainWindow.swift`: the sidebar `List`/`NavigationLink` rows are replaced with a
`ScrollView` + `VStack` of real `Button` rows.

- Each destination is exactly **one** key-view stop. Tab traverses the seven destinations in order
  and then leaves the sidebar for the content and detail columns; Shift-Tab does the reverse.
  There is no row/cell focus engine left to trap Tab.
- The row keeps the accepted presentation: SF Symbol, destination name, snapshot-derived badge
  (`0` shown, Diagnostics/Settings none), accent-tinted selection highlight, and the degraded-path
  inset at the bottom.
- The spoken label is unchanged (`name, badge` when a badge exists, name only otherwise) and the
  explicit `.accessibilityAction` still performs the same selection write. A `Button` also gives
  VoiceOver a native press action.
- Arrow keys still move the selected destination and carry keyboard focus (`FocusState` +
  `.onKeyPress`), preserving the accepted List behavior.
- Destination writes, `applyDestination`, menu/shortcut selection, invalidation, sheets, C-1 footers,
  and every public initializer are untouched.

No focus modifier on the `List` was sufficient: `.focusable(false)` on the rows produced the
`AXOutline` trap, and `.focusable(false)` on the List removed the sidebar from the key loop
entirely (both measured and rejected). Replacing the row container is the smallest structure that
keeps every destination reachable while removing the cell loop.

## 3. Runtime verification (worker probe)

Raw logs in `evidence/` (all produced by Accessibility focus reads with CGEvent Tab/Space delivery
against a debug build):

- `focus-traversal-attempt1.log`, `focus-traversal-attempt2.log`: **both** runs show the complete
  forward order from the selected sidebar destination:
  `Overview` → `AI Agents` → `AI Coding Tools` → `AI Harnesses` → `Updates` → `Diagnostics` →
  `Settings` → Overview conflict "Show PATH evidence" actions → **Copy Selected Entry path** →
  **Reveal in Finder Selected Entry path** → **Copy Resolved Target path** →
  **Reveal in Finder Resolved Target path** → `Verify Installation` → info link → toolbar
  (`Hide Sidebar`, `Rescan`, `Check Updates`, `Refresh Updates`, search) → wrap. Raw frames in the
  log place stops 11–14 on the four detail buttons.
- `focus-space-activation.log`: after focusing `Copy Selected Entry path for Codex`, Space produced
  exactly `/Users/corvette/.local/bin/codex` on the pasteboard (clipboard saved and restored).
- `focus-arrows.log`: Arrow Down/Up move both selection and focus across sidebar destinations
  (`Overview` → `AI Agents` → `AI Coding Tools` → `AI Agents`); Shift-Tab from the sidebar moves
  into the toolbar/search, so the sidebar no longer traps reverse traversal either.
- `sidebar-focus-ring.png`: the focused sidebar destination shows the system focus ring.
- Harness caveat, stated honestly: synthetic AX focus plus injected keys is state-sensitive. Some
  runs (`focus-gate-probe.log`, `focus-verification.log`, `focus-sidebar-space.log`) landed on
  SwiftUI column-section focus (`AXGroup` stops) or a text field instead of individual controls
  depending on the window's first-responder state. Those runs are filed unedited and are **not**
  presented as a pass. The orchestrator's real-key M8 measurement remains authoritative.

## 4. Counts and gates

| Target | Baseline | Candidate |
|---|---|---|
| `AgentLensCoreTests` | 467 | 467 |
| `AgentLensAppSupportTests` | 119 | 119 |
| Total | 586 | 586 |
| Guard fixtures | 21 | 21 |
| Packaging checks | 9 | 9 |

Acceptance commands (fresh scratch `$R/full-suite`, CLT plugin flag) ran from the repo root; raw
argv/stdout/stderr/exit codes/durations are in `evidence/*.log` and `*.meta`.

| Command | Exit | Duration |
|---|---|---|
| `env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS swift build` | 0 | 5s |
| full suite (fresh scratch, `--no-parallel`, plugin flag) | 0 | 117s |
| `python3 scripts/check-core-ui-imports.py` | 0 | 0s |
| `python3 scripts/check-core-ui-imports.py --source-root Sources/AgentLensAppSupport` | 0 | 0s |
| `python3 Tests/Packaging/test_core_ui_imports.py` | 0 | 1s |
| `python3 scripts/build-dev-app.py … --configuration debug` | 0 | 4s |
| `python3 Tests/Packaging/test_dev_app_bundle.py …` | 0 | 2s |
| `git diff --check` | 0 | — |

Observed: Core `467 passed`; AppSupport `119 passed`; zero failures/skips; import guards clean
(32 Core files, 6 AppSupport files); fixtures `Ran 21 tests ... OK`; packaging `Ran 9 tests ... OK`;
dev app built.

## 5. Changed files, hashes, manifest

`evidence/changed-files.sha256` and `evidence/protected-manifest-vs-base-775d5bc.log` are at the
candidate. Only the allow-listed `MainWindow.swift` differs in the tracked manifest; the only
implementer untracked addition is this report. External reviewer artifacts under
`walkthroughs/M12-E-evidence/reviews/` are not implementer changes and are excluded from the hash
list.

```text
00b10131abfd640bb6256d57ff7e050d1e1eb68f0d150d6aab9065d45deed015  Sources/AgentLensApp/MainWindow.swift
```

This report's own SHA-256 is recorded in the same evidence file after the report's final write.

## 6. Stop-condition audit

- No system VoiceOver, Full Keyboard Access, appearance, or text-size setting was flipped.
- No AppSupport/Core/CLI/registry/test/fixture/script/packaging file changed.
- C-1 footer key equivalents, menu shortcut table, public initializers, sheet bindings, and the R1
  invalidation contract are unchanged.
- No new prepare entry point; no mutation can be confirmed with Return.
- No spoken/list label regressed: unknown still adds neither "up to date" nor "update available".

## 7. Unverified / unobserved

- The authoritative M8 keyboard-only gate (real hardware keys, Full Keyboard Access controlled by
  the orchestrator), VoiceOver spoken checks, and system-setting restoration are M12-F work, not
  performed here.
- The synthetic focus harness is state-sensitive (see §3); the recorded logs include failed
  synthetic runs and only the observed successful traversal is claimed.
