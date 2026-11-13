# M12-E implementation — WORKER EVIDENCE (not acceptance)

**This document is worker evidence, not acceptance.** The orchestrator reruns every gate, performs
the AX label read independently (D-014), and summons BOTH independent reviewers. Phase M12-E
(native menus, keyboard, accessibility, layout, appearance) of milestone M12, implemented against
the frozen dispatch brief `briefs/M12-E-native-accessibility.md` and judgment rulings R9/R10/R11
(plus R1/R12/R16).

- Base: `1f2b62b` (M12-D accepted tip). Dispatch-brief commit `c9012b9`; branch
  `milestone/m12-workflow`.
- Candidate state: **uncommitted working tree** on top of `c9012b9`. No stage/commit/branch/reset/
  merge/push was performed.
- `Sources/AgentLensAppSupport/**` and Core are untouched (frozen).
- **No system VoiceOver / Full Keyboard Access / appearance / text-size setting was flipped.**
  Measurement belongs to M12-F under OD-M12-1.
- Evidence root: `$HOME/.hermes/cache/scratch/agent-lens-m12-e` (outside the repository).

## 1. What was built

| File | Change |
|---|---|
| `Sources/AgentLensApp/AgentLensApp.swift` | `.commands` with the R9 menu bar and shortcut table; focused-scene command value types |
| `Sources/AgentLensApp/MainWindow.swift` | command-action snapshot (`focusedSceneValue`); sidebar VoiceOver activation; split-root `760×480` minimum |
| `Sources/AgentLensApp/PathActions.swift` | path-button hints; AppKit accessibility announcement of transient feedback |
| `Sources/AgentLensApp/ToolDetailView.swift` | section/tool-name headers; combined error banners; wrapped banner text |
| `Sources/AgentLensApp/DiagnosticsView.swift` | section/tool-name headers; combined error banners; wrapped state/failure text |
| `Sources/AgentLensApp/OverviewView.swift` | combined degraded banner (tiles already labelled) |
| `Sources/AgentLensApp/SettingsView.swift` | section headers; long statements already wrap |
| `Sources/AgentLensApp/UpdateOperationView.swift` | sheet title/result labels, confirm/cancel hints, unavailable announcement, terminal-state announcement, stale claim none (comment unchanged); C-1 untouched |
| `Sources/AgentLensApp/UninstallOperationView.swift` | same accessibility work; stale "Cancel is the safe default action" comment corrected |
| `walkthroughs/M12-E-implementation.md` | this worker report |

`ToolListView.swift` needed no edit: M12-B already extended the row's accessibility description
(category, version or "version unknown", conflict kinds) and the list has no truncating limit. Its
label behavior is preserved.

No AppSupport/Core/CLI/registry/`Package.swift`/tests/fixtures/scripts/packaging change. No new
dependency. C-1 footers and every public initializer are unchanged.

## 2. Menu bar and shortcuts (R9)

`.commands` is attached to the main `Window` scene. Menu state comes from
`.focusedSceneValue(\.appCommandActions, …)`; every action closure calls the MainWindow `runAction`
path (main actor, busy-gated, tracked by the termination gate) and destination selection writes the
same `selectedDestination` state the sidebar writes.

| Menu | Item | Shortcut | Action | Disabled when |
|---|---|---|---|---|
| Agent Lens | Settings… | ⌘, | select Settings destination | never |
| File | Rescan | ⌘R | `rescan()` | `isBusy` |
| File | Check for Updates | ⌘U | `checkForUpdates()` | `isBusy` |
| File | Refresh Update Metadata | ⌘⇧U | `refreshUpdates()` | `isBusy` |
| View | Overview | ⌘1 | select Overview | never |
| View | AI Agents | ⌘2 | select AI Agents | never |
| View | AI Coding Tools | ⌘3 | select AI Coding Tools | never |
| View | AI Harnesses | ⌘4 | select AI Harnesses | never |
| View | Updates | ⌘5 | select Updates | never |
| View | Diagnostics | ⌘6 | select Diagnostics | never |
| View | Settings | ⌘7 | select Settings | never |
| Tool | Prepare Update… | ⌥⌘U | `prepareSelectedUpdate()` | busy, sheet presented, or `ManagementPresentation(selected).update ≠ .prepareNpmUpdate` |
| Tool | Prepare Uninstall… | ⌥⌘⌫ | `prepareSelectedUninstall()` | busy, sheet presented, or `.uninstall ≠ .prepareNpmUninstall` |
| Tool | Verify Installation | ⌥⌘I | `verifySelectedInstallation()` | busy, or selection not winner/off-PATH |

- **No menu item calls `confirmSelectedUpdate`/`confirmSelectedUninstall`.** The only confirm calls
  remain the accepted sheet callback closures in MainWindow.
- Edit keeps the standard system items; ⌘C is not overridden. ⌘F remains the searchable field's own
  shortcut. No path menu items, no bare U/R/S, no ⌘K.
- View shortcuts that change scope go through the accepted destination write (R1 hook); ⌘, / ⌘6 /
  ⌘7 do not change scope.

## 3. Accessibility (R10)

- **List row**: the M12-B description is preserved verbatim (category, version/version unknown,
  conflict kinds, update availability only for `.updateAvailable`; unknown adds neither "up to
  date" nor "update available").
- **Headers**: tool names and section titles in the detail view, Diagnostics, and Settings carry
  `.accessibilityAddTraits(.isHeader)`. (The Overview "Conflicts" heading lives in
  `ConflictSummaryView.swift`, which the brief marks DO NOT TOUCH; its text label remains.)
- **Path buttons**: labels unchanged (`Copy Selected Entry path for <tool>`, etc.) plus hints
  "Copies the path text." / "Asks Finder to select this path."
- **Operation sheets**: preview and result titles are headers; the result title's accessibility
  label carries state + exit status; unavailable views are one element labelled "Update
  unavailable. <Core reason>" / "Uninstall unavailable. <Core reason>"; confirm hints are
  "Applies the reviewed npm update after this confirmation." / "Removes the reviewed npm package
  after this confirmation."; Cancel's hint is "Closes this confirmation without a change.";
  the progress region keeps its sentence + registry ID/package/prefix label.
- **Error banners**: degraded-environment and both failure banners are combined accessibility
  elements, so their labels name the failure and keep the detail.
- **Sidebar VoiceOver activation**: each destination row keeps its navigation link and gains an
  explicit default `.accessibilityAction` that writes the same `selectedDestination` state as a
  click. There is no second invalidation path.
- **Transient path feedback announced** (see §4).

## 4. Announcement API path used

Confirmed at build time on this toolchain (macOS 14 SDK): the AppKit accessibility announcement API
compiles and is used, not the fallback.

```swift
NSAccessibility.post(
    element: NSApplication.shared,
    notification: .announcementRequested,
    userInfo: [
        .announcement: message,
        .priority: NSAccessibilityPriorityLevel.high.rawValue,
    ]
)
```

- `PathActions.swift` posts the visible feedback text on every transient outcome (copied, clipboard
  failure, Finder selection, missing path, ineligible). No visible string changed.
- Both operation sheets post the terminal result (state + exit status) and the unavailable reason
  when those views appear. The visible content is unchanged.
- The fallback (feedback as the focused element's accessibility value) was **not** needed.

## 5. Layout, text, appearance (R11)

- Split-view root `.frame(minWidth: 760, minHeight: 480)`; the scene default size stays 960×600; the
  operation sheets keep their `640×500` minimums.
- New/edited views use semantic text styles only: grep finds no `.font(.system(size:` literal, no
  `preferredColorScheme`, and no `windowResizability`.
- Safety/state text wraps with `.fixedSize(horizontal: false, vertical: true)`; the existing
  `lineLimit(nil)` uses are non-truncating.
- No non-semantic palette was introduced; state text still carries the meaning (badges are
  supplementary).
- C-1 footers are unchanged; the stale uninstall-file comment now says Cancel is the Escape action
  and the destructive confirmation has no key equivalent.

## 6. Counts

| Target | Baseline | Candidate |
|---|---|---|
| `AgentLensCoreTests` | 467 | 467 |
| `AgentLensAppSupportTests` | 119 | 119 |
| Total | 586 | 586 |
| Guard fixtures | 21 | 21 |
| Packaging checks | 9 | 9 |

## 7. Acceptance commands and raw evidence

Runner: `$R/run-acceptance.sh`; raw argv + stdout/stderr + exit code + duration in
`$R/evidence/<name>.{log,meta}`. `R="$HOME/.hermes/cache/scratch/agent-lens-m12-e"`.

| Command | Exit | Duration | Raw log |
|---|---|---|---|
| `env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS swift build` | 0 | 1s | `build.log` |
| full suite (fresh scratch, `--no-parallel`, CLT plugin flag) | 0 | 154s | `full-suite.log` |
| `python3 scripts/check-core-ui-imports.py` | 0 | 0s | `guard-core.log` |
| `python3 scripts/check-core-ui-imports.py --source-root Sources/AgentLensAppSupport` | 0 | 0s | `guard-appsupport.log` |
| `python3 Tests/Packaging/test_core_ui_imports.py` | 0 | 1s | `guard-fixtures.log` |
| `python3 scripts/build-dev-app.py --scratch-root "$R/dev-app" --configuration debug` | 0 | 27s | `dev-app.log` |
| `python3 Tests/Packaging/test_dev_app_bundle.py --app "$R/dev-app/AgentLensApp-debug.app"` | 0 | 2s | `packaging.log` |
| `git diff --check` | 0 | — | `diff-check.log` |

Observed results (worker run; orchestrator will rerun and read AX):

- `full-suite.log`: `✔ Test run with 467 tests in 0 suites passed` (Core) and
  `✔ Test run with 119 tests in 5 suites passed` (AppSupport); no failure, no skip, no issue line.
- `guard-core.log`: `32 Swift file(s) under Sources/AgentLensCore; no SwiftUI/AppKit imports`.
- `guard-appsupport.log`: `6 Swift file(s) under Sources/AgentLensAppSupport; no SwiftUI/AppKit imports`.
- `guard-fixtures.log`: `Ran 21 tests ... OK`. `packaging.log`: `Ran 9 tests ... OK`.
- `dev-app.log`: `Build complete!` and `$R/dev-app/AgentLensApp-debug.app`.
- `static-checks.log`: no `.font(.system(size:` literal, no `preferredColorScheme`, no
  `windowResizability`; only non-truncating `lineLimit(nil)` uses remain.
- `menu-audit.log`: the shortcut table above; no `confirmSelected*` in the commands file (the two
  confirm calls are the accepted sheet callbacks in MainWindow); C-1 footer shortcuts unchanged.
- `initializer-check.log`: no public-parameter change; `Tests/Fixtures/M10D/npm_uninstall_acceptance.py`
  untouched (SHA-256 `249606a4…`).

## 8. Changed-file hashes and protected manifest

`evidence/changed-files.sha256`, the manifests vs base `1f2b62b` and vs HEAD `c9012b9`, plus
`static-checks.log`, `menu-audit.log`, and `initializer-check.log` are at the candidate. Result: only
the nine allow-listed App files differ in the tracked manifest; the only implementer untracked
addition is this report. `walkthroughs/M12-D-evidence/reviews/*` are orchestrator/reviewer artifacts,
not implementer changes, and are excluded from the hash list. The only committed delta
`1f2b62b..HEAD` is `briefs/M12-E-native-accessibility.md` (orchestrator dispatch-brief commit
`c9012b9`). No Core/AppSupport/test/fixture/script/packaging file differs.

Candidate SHA-256 (`evidence/changed-files.sha256`):

```text
2e72a846a4ad0a8475062995d5a5e5664ea299f41c3c57debc10bc6ecb0fa0a2  Sources/AgentLensApp/AgentLensApp.swift
b8c460fdf223027ac493009496816e721dc946847bfdd86644dab79f03fbd64b  Sources/AgentLensApp/DiagnosticsView.swift
40c33bfefc1e343717e13cc2462729ecb79dcedb8e081d4fd21dab571153582b  Sources/AgentLensApp/MainWindow.swift
4cdba1c305cf6c086a322c49a34bd06f5e4fcce28b08ff8c993db30cf592b01e  Sources/AgentLensApp/OverviewView.swift
ae6fc4f3025c82ab34a77f73ce2258e38c932cb4ef3d62a31aa942d0f9b4c583  Sources/AgentLensApp/PathActions.swift
b22aeba9906be131bd3ae1a4567b99f0f4ea28ea744fb3d83f72801a25de8041  Sources/AgentLensApp/SettingsView.swift
c8e1066461bafab3cb1730b42b12550e1df7859c1129f8f77cb6eb899bf63669  Sources/AgentLensApp/ToolDetailView.swift
c20eaff7a23c7599f079d1d182b6cf5e72e0b33be6817a47e01b9357157a8356  Sources/AgentLensApp/UninstallOperationView.swift
371c6dd1ac70b457a5e5261bb50cf2e2066b18b5587f0f5c09b793143060648a  Sources/AgentLensApp/UpdateOperationView.swift
```

This report's own SHA-256 is recorded in the same evidence file after the report's final write.

## 9. Stop-condition audit

- No shortcut collides with search entry or ⌘C; no bare keys were introduced.
- No control is keyboard-reachable only via a bare key; destructive confirmation remains
  click/Tab+Space only from M12-D.
- No spoken string reads unknown as current: the row adds "update available" only for
  `.updateAvailable`.
- The announcement API was available; the fallback was not needed and no visible string changed.
- No menu item needed a confirm call; no Settings toggle was added.
- No file outside the allow-list was edited; no system setting was flipped.

## 10. Unverified / unobserved

- No VoiceOver run, keyboard-only journey, AX dump, large-text render, or light/dark screenshot was
  performed by the worker; these are M12-F / orchestrator measurement and require OD-M12-1.
- The sidebar VoiceOver activation and menu enablement/actions are implemented in source and
  compile; the orchestrator's AX read is the first runtime observation and is not claimed here.
- The Overview conflict heading's header trait is left as-is because `ConflictSummaryView.swift` is
  DO NOT TOUCH for this phase.
