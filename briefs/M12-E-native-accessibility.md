# M12-E dispatch brief — native menus, keyboard, accessibility, layout, appearance

Status: **FROZEN dispatch brief.** Implementer receives ONLY this brief (not the scope document).
Authority: `briefs/M12-plan.md` §5 M12-E and `briefs/M12-planning/judgment.md` rulings R9/R10/R11
(binding). M12-A…D accepted at `1f2b62b`; the AppSupport model is FROZEN. **Mandatory independent
review by BOTH council models** (menus can prepare a mutation; accessibility regression risk).

```text
MILESTONE:   M12 — complete native diagnostic and operation workflow
PHASE:       M12-E — native menus, keyboard, accessibility, layout, appearance
BASE:        1f2b62b (milestone/m12-workflow; M12-D accepted tip). Product base 0589fac.
BRANCH:      milestone/m12-workflow (already checked out; do NOT switch/rebase/branch)
WORKER:      DeepSeek V4.1 Flash 1017 via OMP (river/deepseek-ai/DeepSeek-V4.1-Flash-1017), max
GOAL:        Native menu bar + R9 shortcuts; VoiceOver labels/hints on every surface; safety text
             wraps; 760x480 content minimum; system appearance; transient path-action feedback
             announced. No system-setting flips (measurement is M12-F).
```

## 1. Required reading (in this order)

1. `briefs/M12-plan.md` §3, §4, §5 M12-E, §6.
2. `briefs/M12-planning/judgment.md` rulings **R9, R10, R11** (full text) and R1/R12/R16.
3. `briefs/M12-B-acceptance.md` — forward note: sidebar rows do not select via the Accessibility
   `AXPress` action (SwiftUI `NavigationSplitView` characteristic); keyboard arrows work. M12-E must
   make sidebar destinations activatable by VoiceOver (VO navigation + activate), not only arrows.
4. `briefs/M12-D-acceptance.md` — carried note: the uninstall sheet's file comment still calls Cancel
   the "default action" (stale after C-1); correct it while editing that file for accessibility.
5. `Sources/AgentLensApp/AgentLensApp.swift` — the `Window` scene (add `.commands` here; NO second
   `Settings` scene; NO `preferredColorScheme`; NO `windowResizability`).
6. `Sources/AgentLensApp/MainWindow.swift` — sidebar, toolbar, sheet bindings, `applyDestination`.
7. `Sources/AgentLensApp/ToolListView.swift`, `ToolDetailView.swift`, `DiagnosticsView.swift`,
   `OverviewView.swift`, `SettingsView.swift`, `PathActions.swift`, `UpdateOperationView.swift`,
   `UninstallOperationView.swift` — the surfaces to label/wrap.
8. `Sources/AgentLensAppSupport/InventoryViewModel.swift` — the actions menus call: `rescan()`,
   `checkForUpdates()`, `refreshUpdates()`, `prepareSelectedUpdate()`, `prepareSelectedUninstall()`,
   `verifySelectedInstallation()`, `listScope`, `detailPane`, `isBusy`, the sheet presentation flags,
   `selectedEntry`, the `ManagementPresentation` affordances (read-only).

## 2. FILES — explicit allow-list

Production (modify):
- `Sources/AgentLensApp/AgentLensApp.swift` (`.commands`, window minimum)
- `Sources/AgentLensApp/MainWindow.swift` (menu wiring, focus, sidebar VO activation, minimum)
- `Sources/AgentLensApp/ToolListView.swift` (a11y labels, focus, large text)
- `Sources/AgentLensApp/ToolDetailView.swift` (a11y labels, wrapping)
- `Sources/AgentLensApp/PathActions.swift` (announce transient feedback)
- `Sources/AgentLensApp/OverviewView.swift`, `SettingsView.swift`, `DiagnosticsView.swift` (a11y)
- `Sources/AgentLensApp/UpdateOperationView.swift`, `UninstallOperationView.swift` (a11y labels +
  wrapping ONLY; correct the stale Cancel comment; do NOT change C-1 footer or initializers)

Worker report (new):
- `walkthroughs/M12-E-implementation.md` (labeled WORKER EVIDENCE, not acceptance)

No new test target. No AppSupport test change expected. If a test change seems required, STOP/report.

## 3. DO NOT TOUCH (binding — stop and ask, never edit)

`Sources/AgentLensAppSupport/**` (frozen), `Sources/AgentLensCore/**`, `Sources/agent-lens/**`,
`Sources/AgentLensApp/ConflictSummaryView.swift` (already accessible; leave unless a label is missing),
`Package.swift`, `Tests/**`, `scripts/**`, `.github/**`, `Resources/**`, `docs/**`, `DECISIONS.md`,
`ROADMAP.md`, `AGENT_LENS_SCOPE.md`, every existing `briefs/**` and `walkthroughs/**` (except the new
worker report). No new dependency. No CLI mutation syntax. No M16 features (cached launch/menu-bar
presence/opt-in checks) and no toggles for them. No `preferredColorScheme`, no `windowResizability`,
no product fixture mode, no launch argument forcing text size/appearance. Personal installations, the
real cache, credentials out of bounds. **Do NOT flip system VoiceOver/Full Keyboard Access/appearance
or text size** — that measurement is M12-F under OD-M12-1. If a file outside the allow-list seems
necessary, STOP and report.

## 4. Contracts (quote of the binding rulings)

**R9 — menu bar + shortcuts (NO mutation confirm, NO bare keys, NO ⌘K, NO ⌘C override).** Add
`.commands` to the `Window` scene:

| Menu | Item | Shortcut | Calls | Disabled when |
|---|---|---|---|---|
| Agent Lens | Settings… | ⌘, | select Settings destination (`detailPane = .settings`) | never |
| File | Rescan | ⌘R | `rescan()` | `isBusy` |
| File | Check for Updates | ⌘U | `checkForUpdates()` | `isBusy` |
| File | Refresh Update Metadata | ⌘⇧U | `refreshUpdates()` | `isBusy` |
| View | Overview / AI Agents / AI Coding Tools / AI Harnesses / Updates / Diagnostics / Settings | ⌘1…⌘7 | select destination | never |
| Tool | Prepare Update… | ⌥⌘U | `prepareSelectedUpdate()` | busy, sheet presented, or update affordance ≠ `.prepareNpmUpdate` |
| Tool | Prepare Uninstall… | ⌥⌘⌫ | `prepareSelectedUninstall()` | busy, sheet presented, or uninstall affordance ≠ `.prepareNpmUninstall` |
| Tool | Verify Installation | ⌥⌘I | `verifySelectedInstallation()` | busy, or selection not winner/off-PATH |

Edit keeps the STANDARD system items (⌘C/⌘X/⌘V/⌘A); ⌘C is NOT overridden. ⌘F is the searchable
field's own shortcut (no custom menu item). NO path menu items (path actions remain the detail-view
buttons, measured by the M8 gate). NO bare U/R/S; NO ⌘K palette. **NO menu item calls
`confirmSelectedUpdate`/`confirmSelectedUninstall`** — prepare/verify only. View shortcuts that change
`listScope` invalidate a pending preview through the ViewModel's R1 hook (the App adds no second
trigger); ⌘,/⌘6/⌘7 (Settings/Diagnostics) do not change scope. Menu actions run on the main actor and
respect the busy gate (use the same `runAction` pattern as the toolbar).

**R10 — VoiceOver labels/hints (every surface).** Required spoken content:
- List row: extend the current `accessibilityDescription` with category label, local version or
  "version unknown", and conflict kind labels when non-empty. Unknown adds NO "up to date"/"update
  available". (M12-B already added these; preserve and ensure they remain.)
- Section titles in detail/diagnostics/overview/settings are headers (`.accessibilityAddTraits(.isHeader)`).
- Path buttons keep their current labels (`Copy Selected Entry path for <tool>` etc.) and gain hints
  "Copies the path text." / "Asks Finder to select this path.".
- Operation sheets: visible title exposed as label; Confirm hint "Applies the reviewed npm update
  after this confirmation." / "Removes the reviewed npm package after this confirmation."; Cancel hint
  "Closes this confirmation without a change."; progress region label = progress sentence + registry ID
  (already present); result announced with state + exit status; unavailable announced with the Core reason.
- Error banners (Rescan Failed / Update Check Failed / Degraded Environment) are accessibility elements
  whose label names the failure.
- **Sidebar destinations must be activatable by VoiceOver** (VO navigate + activate selects the
  destination). If the SwiftUI `NavigationLink` row does not expose an activatable accessibility action,
  add an explicit accessibility action/label that performs the same selection as a click (writing
  `selectedDestination`), WITHOUT adding a second invalidation path. Verify the row exposes a press/
  activate action that changes the selection.
- **Announce transient path-action feedback** (`PathActions.swift`): post an AppKit accessibility
  announcement when feedback appears. Confirm the exact API at build time
  (`NSAccessibility.post(element:notification:userInfo:)` with the announcement notification, e.g.
  `.announcement`/`.announcementRequested`, and the `.announcement` user-info key). If the symbol is
  unavailable in this toolchain, the agreed fallback is to expose the feedback as the focused element's
  accessibility value. The requirement: a VoiceOver user is told the outcome without hunting for it.
  Report which path you used. Do NOT change any visible string.

**R11 — layout, large text, appearance.** Semantic text styles only in new/edited views (`.body`,
`.headline`, `.caption`, existing monospaced design); NO `.font(.system(size:))` literal. Safety/
unavailable/effect/path-ineligibility text wraps with `.fixedSize(horizontal: false, vertical: true)`
and NO truncating `lineLimit`. Split-view root `.frame(minWidth: 760, minHeight: 480)`; default size
stays 960×600; operation sheet minimums (640×500) stay. NO `preferredColorScheme` (appearance follows
the system); NO `windowResizability` (unverified on macOS 14). Colors stay semantic; do not introduce a
non-semantic palette; state TEXT keeps carrying meaning. M12-E does NOT flip system appearance/text
size (measurement is M12-F).

**R12 — zero Core/AppSupport/CLI/registry change.** Core 467 / AppSupport 119 unchanged. No new
dependency. C-1 footer and public initializers unchanged (D accepted).

## 5. Acceptance (exact commands + expected observable results)

Evidence root: `R = $HOME/.hermes/cache/scratch/agent-lens-m12-e`. Run from the repo root, fresh
scratch, no toolchain/package change:

```sh
R="$HOME/.hermes/cache/scratch/agent-lens-m12-e"; mkdir -p "$R/tmp" "$R/evidence"
env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS swift build 2>&1 | tee "$R/evidence/build.log"
env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS \
  TMPDIR="$R/tmp" swift test --build-system swiftbuild --scratch-path "$R/full-suite" --no-parallel \
  -Xswiftc -load-plugin-library \
  -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib \
  2>&1 | tee "$R/evidence/full-suite.log"
python3 scripts/check-core-ui-imports.py 2>&1 | tee "$R/evidence/guard-core.log"
python3 scripts/check-core-ui-imports.py --source-root Sources/AgentLensAppSupport 2>&1 | tee "$R/evidence/guard-appsupport.log"
python3 Tests/Packaging/test_core_ui_imports.py 2>&1 | tee "$R/evidence/guard-fixtures.log"
TMPDIR="$R/tmp" python3 scripts/build-dev-app.py --scratch-root "$R/dev-app" --configuration debug 2>&1 | tee "$R/evidence/dev-app.log"
TMPDIR="$R/tmp" python3 Tests/Packaging/test_dev_app_bundle.py --app "$R/dev-app/AgentLensApp-debug.app" 2>&1 | tee "$R/evidence/packaging.log"
git diff --check
```

Expected: every command exit 0; **Core 467 + AppSupport 119 = 586, zero skips/failures**; guard 21;
packaging 9; both import guards clean; dev app builds. Plugin-flag workaround as before; STOP/report
if the plugin path is unavailable or the failure differs. Additionally grep the allow-listed views:
no new `.font(.system(size:` and no `preferredColorScheme`.

The orchestrator performs the AX label read (a list row, both path buttons, an unavailable sentence,
both sheet button labels, the menu items) and the independent review confirms no menu item calls
`confirmSelectedUpdate`/`confirmSelectedUninstall`. The full VoiceOver spoken check + keyboard-only
M8 gate + large-text/light-dark measurement are M12-F (under OD-M12-1), not this phase. You do NOT
perform acceptance and do NOT flip system settings.

## 6. EVIDENCE (raw, unedited)

Under `$R/evidence`: raw argv + stdout/stderr + exit codes + durations; SHA-256 of every changed file;
a protected-file manifest diff proving ONLY allow-listed files changed (hash every tracked file at
base `1f2b62b`, compare at the candidate). Write `walkthroughs/M12-E-implementation.md` labeled WORKER
EVIDENCE: what you built, the menu/shortcut table, the announcement API path used, counts, changed-file
hashes, stop-condition audit, unverified/unobserved items. The orchestrator reruns every gate + the AX
read independently (D-014) and summons both reviewers.

## 7. STOP conditions (stop and report, never improvise)

- A shortcut collides with search text entry or ⌘C.
- A button is keyboard-reachable only via a new global bare key.
- A spoken string would lie about a state (e.g. unknown read as "up to date").
- The announcement API is unavailable AND the fallback would change a visible string.
- A menu item would need to call a confirm method, or a Settings toggle would be needed.
- Any design choice not resolved in this brief or the rulings — report it, do not decide it.

## 8. DONE WHEN

The acceptance commands pass (orchestrator will rerun + AX read); the diff is inside the allow-list
with a clean protected manifest; Core 467 / AppSupport 119 unchanged; C-1/initializers intact; the
worker report + raw evidence are filed. Then report:

```sh
hc send t7x "M12-E candidate ready: <state> — <counts>; <changed files>; <announcement API path>; <evidence root>; <blocker>"
```

Do NOT stage/commit/branch/reset/merge/push — the orchestrator owns Git delivery. Do NOT start
subagents or other CLIs. Do NOT grade your own work as accepted. Both council reviewers will
independently review this candidate (mandatory).