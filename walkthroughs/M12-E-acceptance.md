# M12-E acceptance — native menus, keyboard, accessibility, layout, appearance

Date: 2026-11-13. Orchestrator: Qoder (Herdr `t7x`). Milestone branch: `milestone/m12-workflow`.
**Accepted candidate: `5214d63` + R1 (`407882b`).** Phase M12-E of `briefs/M12-plan.md`; dispatch
brief `briefs/M12-E-native-accessibility.md`; binding rulings R9/R10/R11.

**Decision: M12-E is TECHNICALLY ACCEPTED.** Both mandatory independent reviews initially returned
CHANGES_REQUIRED (0 blocking); a focused R1 corrected the findings; both re-reviews PASS. The
orchestrator independently reran every gate (D-014) and read the real app's menu bar / AX tree.

## Independent reviews

| Stage | MiniMax M3.1-Flash/xhigh | Grok 4.7/high |
|---|---|---|
| Initial (`5214d63`) | CHANGES_REQUIRED — 0 blocking, 2 medium, 1 low | CHANGES_REQUIRED — 0 blocking, 1 medium, 2 low |
| R1 (`407882b`) | **PASS** — 0 blocking, closure complete | **PASS** — 0 blocking |

Records: [minimax.md](M12-E-evidence/reviews/minimax.md), [grok.md](M12-E-evidence/reviews/grok.md),
[minimax-r1.md](M12-E-evidence/reviews/minimax-r1.md), [grok-r1.md](M12-E-evidence/reviews/grok-r1.md).

Findings corrected in R1 (no production behavior change beyond the menu gate + labels):
- **MEDIUM-1 (both):** Tool > Verify Installation was not disabled while a sheet was presented. R9 /
  plan prose disable all three Tool items when busy/sheet/not-eligible; the frozen brief's table had
  dropped the sheet conjunct for Verify (a brief defect, recorded). R1 adds `!isSheetPresented` to
  `canVerifyInstallation` (`AgentLensApp.swift:298-302`). The brief stays frozen; the deviation is
  recorded in the worker report.
- **MEDIUM-2 (MiniMax) / LOW-1 (Grok):** the sidebar `.accessibilityLabel(destination.rawValue)`
  dropped the badge count the base announced. R1 restores it via `accessibilityLabel(for:)`
  (`MainWindow.swift:398-401`) using the same `badgeCount` the visible row uses (label/row cannot
  diverge).
- **LOW-2 (Grok):** the Overview "Conflicts" title gains `.accessibilityAddTraits(.isHeader)`.
- **LOW-1 (MiniMax):** the winner/off-PATH verify predicate is deduplicated to
  `ToolDetailView.canVerifyOwnership`; `MainWindow` reuses it (the duplicate `canVerifySelection`
  deleted). The frozen AppSupport model is unchanged.

Both re-reviews re-confirmed: no menu item calls `confirmSelectedUpdate`/`confirmSelectedUninstall`;
C-1 footer + public initializers untouched (operation views have zero R1 diff); the 20-shortcut table
unchanged; zero Core/AppSupport/CLI/registry change; all App SHA-256 match the R1 manifest.

## Orchestrator gate results (D-014, independent rerun)

Fresh scratch `agent-lens-m12-e-orch` and `agent-lens-m12-e-r1orch`, `swift test --no-parallel` + CLT
TestingMacros flag:

- Full suite: **467 Core + 119 AppSupport = 586 passed, zero skips/failures**, exit 0. (The worker's
  first attempt hit 3 load-sensitive Core version-query failures under concurrent-agent load; the
  clean fresh-scratch rerun passed — both logs filed. The orchestrator rerun is authoritative.)
- Core/UI import guard clean (32 Core files); AppSupport import guard clean (6 files).
- Guard behavioral fixtures 21 OK; packaging 9 OK; dev app built; `git diff --check` clean.
- Diff inside the allow-list (9 App files at `5214d63`; 4 App files + report at R1). No
  AppSupport/Core/CLI/registry/fixture/Package/scripts/.github diff.

## Native AX / menu read (orchestrator-observed, real debug app)

- Menu bar now: Apple, Agent Lens, **File**, Edit, View, **Tool**, Window, Help. The `.commands`
  declaration matches R9 item-for-item (Settings ⌘,; File Rescan ⌘R / Check ⌘U / Refresh ⌘⇧U; View
  ⌘1…⌘7; Tool Prepare Update ⌥⌘U / Prepare Uninstall ⌥⌘⌫ / Verify ⌥⌘I). Menu audit confirms no
  `confirmSelected*` in the commands file (the only confirm calls are the M10 sheet onConfirm
  callbacks). File items fail-closed when no focused window supplies actions.
- Announcement API: the real AppKit `NSAccessibility.post(element: NSApplication.shared,
  notification: .announcementRequested, userInfo: [.announcement: text, .priority: .high])` — compiled
  and used for path feedback + sheet result/unavailable (no fallback needed).
- Layout: 760×480 content minimum; semantic text; wrapping safety copy; no `preferredColorScheme` /
  `windowResizability` / fixed point sizes (static-checks.log).
- Sidebar destinations expose an `.accessibilityAction` performing the same selection as a click
  (VoiceOver activation); the spoken label includes the badge count after R1.

## Limitations and carried-forward notes (honest)

- The full spoken VoiceOver pass, the keyboard-only M8 gate, and large-text/light-dark measurement
  are M12-F (under OD-M12-1, owner-approved), not this phase. M12-E implements the labels/menus;
  M12-F measures them.
- Grok INFO-1: File items (Rescan/Check/Refresh) stay enabled during a sheet — allowed (those methods
  already release an unconsumed preview; the menu adds no second trigger). INFO-2: Settings states the
  degraded sentence without the banner title (cosmetic).
- App layer has no automated test surface; native AX read + reviews are the App evidence.

## Owner authorizations

**OD-M12-1 SETTLED (owner approved 2026-11-13):** during M12-F only, the orchestrator may temporarily
enable Full Keyboard Access + VoiceOver and toggle appearance/text size, restoring each previous value
before finishing. M12-F proceeds under this approval. Merge to `main` is NOT authorized. No release.

## Evidence index

`R = $HOME/.hermes/cache/scratch/agent-lens-m12-e-orch` / `agent-lens-m12-e-r1orch`: `evidence/` (gate
logs), `evidence/native/` (overview/menu screenshots). Worker evidence:
`$HOME/.hermes/cache/scratch/agent-lens-m12-e/evidence/` (static-checks.log, menu-audit.log,
initializer-check.log, r1/). Reviews: `walkthroughs/M12-E-evidence/reviews/`. Worker report:
`walkthroughs/M12-E-implementation.md`.