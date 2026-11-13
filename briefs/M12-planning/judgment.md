# M12 Planning Council — judgment record

Orchestrator/main judge: Qoder (Herdr `t7x`). Date: 2026-11-13.
Base commit for the freeze: `0589fac3cf8f57cf3639ed65077211ab7f2dcd80` (`0589fac`,
`milestone/m11-catalogue` tip; M11 accepted content + MIT license D-023 + PR #2 record).
Milestone branch: `milestone/m12-workflow`, created from that tip. M12 stacks on unmerged M11
(PR #2 open); no rebase onto `main`.

## Council composition and process

| Member | CLI / build | Model | Effort | Herdr terminal | Output |
|---|---|---|---|---|---|
| MiniMax | mcode v0.7.6 | MiniMax-M3.1-Flash (default route) | xhigh (status bar `M3.1-Flash · Eff xhigh`) | `t9h` council-minimax | `proposal-minimax.md` |
| Grok | grok 1.0.77 | grok-4.7 | high (`--reasoning-effort high`) | `t9j` council-grok | `proposal-grok.md` |

- Shared task: `council-brief.md`. Members worked independently and were instructed not to read
  each other's proposals. Both confirmed they did not.
- Both were launched read-only on the product: no product edits, no git mutations, no installs,
  no builds/tests/app launches, no subagents; single writable proposal file each.
- Process notes:
  - mcode launched without `-m` (the default route is already M3.1-Flash; the M11 judgment records
    that `-m minimax_oauth/MiniMax-M3.1-Flash` is rejected by the en-prod route). Effort was already
    xhigh in the persisted TUI state; verified in the status bar before dispatch. mcode runs in its
    default "Full access" permission mode.
  - Grok launched with `--permission-mode acceptEdits`. Its read-only shell research prompted
    per-command. After one individually-approved read-only git inspection, the session was switched
    to always-approve (option 1 in Grok's permission dialog) so bounded research and the single
    proposal write could proceed unattended — the same scoped grant recorded in the M11 judgment.
    This grant is scoped to this planning session; repo integrity is audited by the orchestrator
    before the freeze commit (see below).
- Both agents are visible in the Herdr window: Agent Lens space → "M12 Planning Council" tab.

## Judge's independent baseline evidence (read-only, 2026-11-13)

The judge read the full app surface and the gate configuration before judging:

- `MainWindow.swift` — `NavigationDestination` has exactly `.inventory` and `.diagnostics`;
  three-column `NavigationSplitView`; toolbar counts + Rescan/Check/Refresh; Update/Uninstall
  sheets bound to `updatePreview`/`updatePreparation`/`uninstallPreview`/`uninstallPreparation`
  (never `selectedEntry`); `AppLifecycleGate` termination seam. No `.commands`, no Settings scene.
- `ToolListView.swift` — `.searchable` over `model.filteredEntries`; `ToolRow` accessibility label
  = name, executable, install state, "Update available" only for `.updateAvailable`.
- `ToolDetailView.swift` — Manage section gated on `hasDeclaredNpmPackage`; D-021 reason rendered
  from `Npm*UnavailableReason.operationNotAccepted.message`; Update button only for
  `.updateAvailable` + npm + accepted; path rows via `PathActionRow` with stable `.id(identity)`.
- `InventoryViewModel.swift` — selection by registry ID; `invalidatePendingUpdate()` called from
  exactly four sites (`searchText.didSet` :99, `select` :197, `verifySelectedInstallation` :249,
  `run` :690); the executing-mutation early-return at :621; prepare-time generation +
  `ObservedSelection` (entryPath + canonicalTarget) guards at :331-339 / :484-492.
- `InventorySnapshot.swift` — `updateAvailableCount` counts only `.updateAvailable`;
  `installedToolCount` counts `installedNotOnPath` as installed.
- `PathDiagnostics.swift` — `PathSelection` = winner/offPath/notInstalled/inconsistent;
  `shadowedInstallationCount` = max(0, targetGroups.count-1) for winner, 0 for offPath/notInstalled,
  nil for inconsistent; `sameTargetAliasCount`, `repeatedPathSlotCount`, `installationVersions`,
  `canonicalTargetCount` all present. The conflict summary needs no Core change.
- `UpdateOperationView.swift:74-78` — "Confirm Update" holds `.keyboardShortcut(.defaultAction)`
  (Return confirms a mutation). `UninstallOperationView.swift:73-75` — "Cancel" holds
  `.defaultAction`; the destructive "Uninstall Package" button has no key equivalent. The
  asymmetry both councils flagged is real and verified.
- `Package.swift` — test targets are `AgentLensCoreTests` and `AgentLensAppSupportTests` only;
  `AgentLensApp` is an executableTarget with no test target. App-layer logic has no automated
  test surface; testable logic must live in AppSupport.
- `NpmUpdateOperation.swift` / `NpmUninstallOperation.swift` — the D-021 acceptance guard is the
  second statement (after the cancellation check), before any scratch claim/observation/runner.
- `ci.yml` — seven hosted gates; floors Core 467 / AppSupport 80 / total 547, guard fixtures 21,
  packaging 9; anchors `bundledDefaultDetectorsMatchFrozenCatalogue`,
  `unknownKeysAreRejectedAtRootDefinitionFixturePackageAndQueryLevels`,
  `makeDetectorUsesRegistryArgumentsInTheProductionPath`,
  `productionWiringUsesOnlyTheCoreLoginShellSeams`.
- `grep -rn "apability" Sources/` returns nothing: there is no capability type in product code;
  `docs/capability-matrix.md` is a test-enforced Markdown document, not a model.

Baseline suite: the judge's first local run omitted `--no-parallel` and produced load-sensitive
failures in `UpdateProbeCoordinatorTests` / cancel-after-spawn tests (bounded subprocess deadlines
exceeded under parallel execution plus two concurrent council CLIs). That run was discarded. The
authoritative baseline is `swift test --no-parallel` (the CI-matching invocation, M11-B precedent)
with the documented invocation-local TestingMacros plugin flag on this CLT-only workstation; its
result is recorded in the freeze commit and the M12-A dispatch brief. No product code changed
between M11 acceptance (`b07e321`) and this base (`0589fac`, docs-only commits).

## Evaluation criteria (from council-brief §7)

1. Truthfulness and evidence quality (verified code citations; honest unknowns).
2. Phase boundedness and dispatch-readiness (one writer, clear allow-lists, measurable gates,
   design decisions resolved for a flash-tier implementer).
3. Fidelity to settled decisions and safety invariants (DECISIONS.md, ROADMAP §6, M10 contracts,
   D-021 gate, confirmation-retargeting invariant).
4. Native UX quality and accessibility measurability (real keyboard/VoiceOver evidence; truthful
   Settings; honest unavailable states).
5. Clear separation of owner decisions from technical recommendations.

## Proposals received

Both proposals are high quality, independently verified against the code, and agree on the
load-bearing bounds: **zero Core/CLI/registry changes** (Core count stays 467), all testable logic
in AppSupport, no new App test target, no speculative Settings toggles, no bare-letter shortcuts,
no ⌘K palette, no ⌘C override, no menu item that confirms a mutation, the M8 gate closed with real
key events (never AXPress), six sequential phases with the invalidation contract fixed first, and
mutation journeys only against the disposable npm fixtures. Both flag the same two genuine
findings: the Return-key asymmetry (F-2) and the missing capability model (F-3).

Where they diverge, the judge rules below. The frozen plan (`M12-plan.md`) carries the rulings;
the dispatch briefs quote them verbatim.

## Rulings (binding on the dispatch briefs)

**R1 — Navigation model: Grok's orthogonal `listScope` / `detailPane` wins.**
`listScope` (`.all` / `.category(ToolCategory)` / `.updates`) is orthogonal to `detailPane`
(`.tool` / `.diagnostics` / `.settings`), both on `InventoryViewModel`. A pending preview
invalidates on `listScope`, `searchText`, and selection-ID change (via the existing
`invalidatePendingUpdate()`); a pure `detailPane` switch (Diagnostics/Settings) that changes
neither scope nor selection does NOT invalidate — it cannot retarget a confirmation, and today's
Inventory↔Diagnostics switch already does not invalidate. Executing mutations are never cancelled
by these changes (preserve :621). Sheets bind to preview/preparation/outcome/unavailable, never
`selectedEntry`. MiniMax's blanket "any destination change invalidates" is over-broad: it would
kill a pending preview when the user merely opens Diagnostics to inspect evidence. The ROADMAP
invariant is about *retargeting*, not every navigation. Grok's model satisfies it precisely and
preserves accepted behavior. (Grok TD-1/TD-4; MiniMax D-A8/D-A9 superseded.)

**R2 — Updates destination: installed entries with tri-state cells + an update-status filter.**
The ROADMAP requires "category/update filters". The Updates destination lists installed entries
(`installState != .notInstalled`) with tri-state update cells and a status filter
(`all` / `updateAvailable` / `upToDate` / `unknown` / `notChecked`). Unknown rows are neutral with
their typed reason, never counted in the badge, never rendered "up to date". Not-installed entries
are excluded (no install adapter, D-004). The badge is the global `updateAvailableCount`. This is
MiniMax's D-A1/D-C2 design; Grok's "Updates = only updateAvailable" would make the required update
filter meaningless and could read as "everything is current" on an offline machine. The filter
applies before search; counts stay snapshot-derived. (MiniMax D-A1/D-C1/D-C2 adopted; Grok C.4
membership superseded.)

**R3 — Conflict kinds: three actionable kinds; aliases/repeated-slots are not conflicts.**
Conflict kinds, in order: `shadowedCopy` (`shadowedInstallationCount > 0`), `offPathCopy`
(`selection == .offPath`), `inconsistentDiagnostics` (`selection == .inconsistent`, shows the
stored reason, invents no winner path). Each conflict row displays the measured local versions of
the canonical targets (from `installationVersions`) so version skew is visible as evidence.
`sameTargetAliasCount` and `repeatedPathSlotCount` are NOT conflict kinds — they do not change
which binary runs and remain in the existing Diagnostics summary counts. The conflict count counts
TOOLS (one tool with two kinds counts once). `notInstalled` is not a conflict. This is Grok's tight,
truthful definition (TD-3); MiniMax's `aliasOnly`/`repeatedPathSlot`/`multipleLiveCopies` kinds are
dropped (they inflate the count and overlap `shadowedCopy`), and its `versionSkew` is folded into
the row's displayed versions rather than a separate overlapping kind. No Core change.

**R4 — Capability model: Grok's full coverage, MiniMax's reason-text rule.**
One manager-agnostic AppSupport presentation value (`ManagementPresentation`, a pure function of
one `InventoryEntry`) is the single source for "is a control offered, and why not". It covers ALL
installed entries: npm accepted (prepare buttons), npm unaccepted (the Core enum's own
`operationNotAccepted.message`, read never retyped), Homebrew formula/cask (fixed "not available in
this version" sentences), standalone (fixed sentence). This adopts Grok's broader coverage (TD-6):
a formula-only tool such as `hermes` gets a truthful unavailable explanation today it lacks. The
`codex` button predicates and every Core reason string stay byte-identical. No speculative buttons,
no command names for unshipped managers (no `brew upgrade`/`brew uninstall`/uv/pip/cargo), no new
`AcceptedOperation` case. The view renders the value and never re-derives predicates. (Grok TD-6
base + MiniMax D-A7 reason-text rule.)

**R5 — Return-key asymmetry: adopt the safety hardening as named contract decision M12-D/C-1.**
In the PREVIEW state of BOTH sheets: no button holds `.keyboardShortcut(.defaultAction)`; Cancel
becomes `.keyboardShortcut(.cancelAction)` (Escape); the destructive confirm has no key equivalent
and is reachable by Tab + Space or click. In the RESULT and UNAVAILABLE states, Done/Close keep
`.defaultAction` (safe, non-mutating). This removes the Return-to-confirm-update path
(`UpdateOperationView.swift:77`) and makes the two sheets consistent. Justification: the council
brief requires that shortcuts never execute a mutation directly; no accepted M10 evidence depends
on Return-to-confirm (the M10-D click-through used AXPress, not Return); this strengthens, never
weakens, safety. It is a NAMED contract change to accepted M10 UI behavior and is subject to
mandatory independent review by BOTH council models, who must specifically adjudicate it. Grok's
TD-9 preservation of Return-to-confirm is overruled on safety grounds; if both reviewers BLOCK C-1,
the judge will revisit before acceptance. Initializers stay source-compatible (the M10-D Python
host constructs `UninstallOperationView`; a parameter change is a phase failure).

**R6 — In-sheet progress region: adopt Grok's ADD (TD-11).**
The ROADMAP names "progress" in the journey; today only the button title changes. While
`isExecuting` is true, `outcome` is nil, and `preview` is non-nil, both sheets show a `ProgressView`
plus "Update in progress" / "Uninstall in progress" and the preview's registry ID, package, prefix.
No stdout subscription, no new `OperationState` case, no initializer change. The result view remains
the only place output appears.

**R7 — Settings: Grok's truthful read-only surface wins; no appearance toggle.**
Settings is minimal and read-only: catalogue size + category counts; the accepted-operation
statement (codex is the only tool with accepted managed operations, npm Update/Uninstall after
ownership verification); the quoted Core reason other tools are informational; the degraded-
environment note; "The window follows the system appearance."; and explicit absence statements (no
saved inventory between launches, no menu-bar item, no scheduled update checks, no CLI install).
NO toggles, NO appearance override, NO second Settings scene. Appearance follows the system (no
`preferredColorScheme`). Rationale: the ROADMAP requires correct light/dark appearance, not a manual
override; "Settings only control delivered features" is satisfied most conservatively by a truthful
read-only surface; a UserDefaults preference is extra surface not required. MiniMax's appearance
toggle (its OD-M12-1) is declined as optional polish the owner may revisit later. (Grok TD-8/E.4.)

**R8 — Search predicate: preserve existing fields exactly (Grok TD-2).**
`filteredEntries` applies `listScope` then the existing `matches` predicate, in registry order.
The haystack is NOT extended (no category-label or package-name matching in M12). Category
filtering is the sidebar; package details are visible in rows. This preserves accepted search
behavior and removes implementer ambiguity. MiniMax's D-A4 haystack extension is deferred.

**R9 — Menus and shortcuts: synthesized table; no mutation confirm, no bare keys, no ⌘K, no ⌘C.**
App menu: Settings… ⌘, (selects the Settings destination; no second scene). File: Rescan ⌘R;
Check for Updates ⌘U; Refresh Update Metadata ⌘⇧U. View: ⌘1…⌘7 for the seven destinations.
Tool: Prepare Update… ⌥⌘U; Prepare Uninstall… ⌥⌘⌫; Verify Installation ⌥⌘I — these call
`prepareSelectedUpdate`/`prepareSelectedUninstall`/`verifySelectedInstallation` ONLY, never
`confirmSelected*`, and are disabled when busy, a sheet is presented, or the matching affordance is
not eligible. Edit: standard system items; ⌘C is NOT overridden; ⌘F is the searchable field's own
shortcut (no custom item). NO path menu items: path actions remain the detail-view buttons, measured
by the M8 keyboard gate (Grok TD-12). NO bare U/R/S, NO ⌘K palette. View shortcuts that change
`listScope` invalidate a pending preview (R1); ⌘,/⌘6/⌘7 (Settings/Diagnostics) do not change scope
and do not invalidate by themselves. (MiniMax D-E1/D-E2 + Grok TD-9, synthesized.)

**R10 — M8 keyboard gate + VoiceOver: real key events; Grok's caption-panel method.**
The M8 gate closes only with REAL key events (Space on the focused button), never AXPress or a
mouse click or a menu item, for all four controls (Copy/Reveal × Selected Entry/Resolved Target):
keyboard focus traversal reaches each button; Space activates; clipboard read-back equals the exact
displayed path byte-for-byte (no `file://`, no quotes, no trailing newline); Finder selects the exact
recorded target (not the parent, not a re-resolved symlink); transient feedback appears, is
announced, and does not leak across tools; disabled rows expose no activatable control. Prerequisites:
Accessibility permission (re-check, do not assume); Full Keyboard Access enabled so Tab traverses
buttons (record + restore); the disposable M10-D environment with a fixture executable + symlink on
the resolved login-shell PATH (stop if `debug-env` does not list it; never a personal path);
clipboard preserved/restored; fixture hashes unchanged. VoiceOver spoken checks use Grok's caption-
panel method (⌘F5, VoiceOver navigation, caption screenshots + AX title/description/help dump) — the
caption panel displays the spoken text and is machine-capturable, resolving MiniMax's "speech not
capturable" concern. An AX dump alone does NOT pass the spoken gate. Unknown is never spoken as
"up to date"; a destructive control is announced as destructive. Full Keyboard Access / VoiceOver /
appearance toggles require OD-M12-1 (owner) and are restored. (MiniMax §F.1 detail + Grok §F.2/F.3.)

**R11 — Large text, narrow window, appearance measurement (Grok TD-10/F.4).**
Content minimum 760×480 via `.frame(minWidth:minHeight:)` on the split root; default size stays
960×600; sheet minimums (640×500) stay. Semantic text styles only; no fixed point sizes; safety/
unavailable/effect text wraps with vertical `fixedSize` and no truncating `lineLimit`. No
`preferredColorScheme`; no `windowResizability` (unverified on macOS 14). Large text: offscreen
`NSHostingView` with `.environment(\.dynamicTypeSize, .accessibility5)` reading AX values (layout
evidence, M10-D offscreen precedent); optional real-app screenshot under OD-M12-1. Light/dark:
screenshot Overview + a detail in both under OD-M12-1, restore; a single-appearance run is not a
pass. Measurement is M12-F; M12-E does not flip system settings.

**R12 — Zero Core/CLI/registry change; floors raise-only at combined acceptance.**
No Core file, no CLI dispatch, no registry/schema/detector, no capability-matrix edit, no
`Package.swift`, no `scripts/**`, no `Tests/Fixtures/**`, no `Tests/Packaging/**`, no `.github/**`
edit by the implementer. Core test count stays 467 in every phase; AppSupport rises above 80; total
above 547. CI floors move only at combined acceptance, only upward, only to orchestrator-measured
counts at the frozen candidate SHA, in a separate orchestrator commit; anchors frozen. The
implementer never edits `ci.yml`. The AppSupport import guard is also run with
`--source-root Sources/AgentLensAppSupport` (a command-line flag, not a script edit). (Both agree.)

**R13 — Journey reachable via the accepted detail-view controls; no new prepare entry point.**
Updates rows have NO prepare button (Grok C.4). Selecting an Updates row shows the detail view where
the accepted M10 prepare controls live. The journey is reachable: Updates → select codex → detail →
Prepare Update. This avoids MiniMax's `prepareUpdate(forRegistryID:)` non-selected-tool entry point
(D-D2) and keeps mutation controls in one accepted place. MiniMax's retained per-tool last-operation
summary (D-A10/D-D5) is DEFERRED: the ROADMAP journey's "review output" is the result sheet and
"observe post-rescan winner/version" is the refreshed tool/Updates row; both are satisfied without
retention. (Grok boundedness adopted; MiniMax F-6 enhancement deferred.)

**R14 — Overview is a summary, not a second inventory (Grok TD-1).**
Overview = summary tiles (known / installed / off-PATH / update-available / conflict-tool count) +
the conflict summary section + the degraded-environment banner. NO full 14-row all-tools table
(MiniMax D-B1 superseded): the three category destinations partition the complete catalogue, and a
second full list could disagree with them (Grok risk #10). A non-empty Overview search shows matches
across all categories that navigate into the tool's category scope (a scope change → invalidation).
The conflict summary lives ONLY in Overview; its rows call `showPathEvidence(registryID:)` which
selects the ID and sets `detailPane = .diagnostics`, rendering the existing `DiagnosticsView` — the
only per-candidate surface. No duplication of the evidence.

**R15 — Review matrix (risk-matched, ROADMAP §5.4; owner named both council models).**
M12-A: mandatory independent review by BOTH (changes when a confirmation dies). M12-B: orchestrator
acceptance + native spot-check; stops if its diff enters the ViewModel or the operation views.
M12-C: orchestrator acceptance + spot-check; independent review only if it changes
`showPathEvidence`/`invalidatePendingUpdate` (A locks those). M12-D: mandatory BOTH (mutation
presentation + C-1). M12-E: mandatory BOTH (menus can prepare a mutation; accessibility). M12-F:
orchestrator-run measurement + combined gate; both reviewers read the evidence read-only and do not
re-run destructive fixtures against personal installs.

**R16 — Local suite invocation.**
The authoritative local gate is `swift test --no-parallel` (CI-matching) under
`env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS`, fresh scratch, with the documented
invocation-local TestingMacros plugin flag on this CLT-only workstation
(`-Xswiftc -load-plugin-library -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib`,
`--build-system swiftbuild`). No `xcode-select` switch, no toolchain/package change. The judge's
first parallel run produced load-sensitive failures and was discarded; serial execution is
authoritative. Hosted CI (full Xcode) needs no flag.

## Owner decisions

**OD-M12-1 (the only genuine owner gate; blocks M12-F only).** May the orchestrator, during M12-F
only, temporarily enable Full Keyboard Access (Keyboard navigation) and VoiceOver, and toggle
appearance (and optionally a larger system text size), restoring each previous value before
finishing? Recommendation: YES — without it the M8 keyboard gate and the VoiceOver spoken checks
cannot be evidenced and M12 cannot be accepted. M12-A…M12-E do not need it and proceed while it is
open. Default if unanswered by F: toggle nothing, leave F open, never record an AX-only dump as a
VoiceOver pass. (Grok OD-M12-1; MiniMax OD-M12-7 is the same question.)

**OD-M12-2 (delegated technical decision; ruled).** Scope §7's bare keys U/R/S and the ⌘K palette
are NOT bound (R9). Both councils recommend declining; the judge accepts the decline. Chorded Tool
items prepare, never confirm. Not a dispatch blocker; the owner may object before freeze.

MiniMax's remaining OD-M12-1…6 are resolved by the rulings above (appearance toggle declined R7;
unknown Updates rows adopted R2; Overview shape R14; conflict placement R3/R14; App test target
declined R12; ⌘K declined R9). They are recorded as settled technical decisions, not open owner
gates; the owner may override any ruling explicitly before dispatch.

## Repo integrity audit (before freeze)

Grok's session-scoped always-approve grant was bounded by the council brief to one writable file.
Before the freeze commit the orchestrator audits `git status`: the only working-tree changes must
be the three new planning files (`council-brief.md`, `proposal-minimax.md`, `proposal-grok.md`)
plus the judge's `judgment.md` and `M12-plan.md`. No product file, no existing brief/walkthrough,
no git state mutation by either council member. The audit result is recorded in the freeze commit
message and the M12-A dispatch brief.

## Freeze decision

The judge freezes `M12-plan.md` on base `0589fac` after the baseline recount is green and the
integrity audit is clean. The owner pre-authorized the full M12 flow (plan → freeze/commit →
implement → independent review → PR → owner merge decision); merge is NOT authorized in advance.
Sole product writer: DeepSeek V4.1 Flash 1017 via OMP (`river/deepseek-ai/DeepSeek-V4.1-Flash-1017`,
max reasoning). Standing independent reviewers: MiniMax M3.1-Flash/xhigh (mcode) and Grok 4.7/high
(grok CLI), summoned through Herdr/hc only.