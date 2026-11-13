# M12-D dispatch brief — operation-journey completion (mutation presentation; safety phase)

Status: **FROZEN dispatch brief.** Implementer receives ONLY this brief (not the scope document).
Authority: `briefs/M12-plan.md` §5 M12-D and `briefs/M12-planning/judgment.md` rulings R4/R5/R6/R13
(binding; contract decision **C-1**). M12-A/B/C accepted at `2229ddf`; the AppSupport model is FROZEN.
**This phase touches the mutation presentation and is subject to mandatory independent review by BOTH
council models, who must specifically adjudicate C-1.**

```text
MILESTONE:   M12 — complete native diagnostic and operation workflow
PHASE:       M12-D — operation-journey completion (mutation presentation; safety phase)
BASE:        2229ddf (milestone/m12-workflow; M12-C accepted tip). Product base 0589fac.
BRANCH:      milestone/m12-workflow (already checked out; do NOT switch/rebase/branch)
WORKER:      DeepSeek V4.1 Flash 1017 via OMP (river/deepseek-ai/DeepSeek-V4.1-Flash-1017), max
GOAL:        The detail view renders ManagementPresentation; both operation sheets show an in-flight
             progress region bound to the prepared preview; the footer key equivalents are
             normalized (C-1: Return never confirms a mutation); future managers stay explicitly
             unavailable; codex npm behavior is unchanged.
```

## 1. Required reading (in this order)

1. `briefs/M12-plan.md` §3 (safety envelope), §4, §5 M12-D, §6.
2. `briefs/M12-planning/judgment.md` rulings **R4, R5, R6, R13** (full text) and R1/R12/R16.
3. `briefs/M12-A-acceptance.md` — LOW-3/INFO-2 forward note: the update slot's "newer version"
   sentence is new text M12-D surfaces for the first time; it must not displace/re-word codex
   affordances.
4. `Sources/AgentLensAppSupport/WorkflowPresentation.swift` — `ManagementPresentation`
   (`update: UpdateAffordance`, `uninstall: UninstallAffordance`, `otherLimits: [String]`), the fixed
   sentences, and that Core `operationNotAccepted.message` strings are read from the enums. Consume;
   do not modify.
5. `Sources/AgentLensApp/ToolDetailView.swift` — the CURRENT predicates you must reproduce exactly:
   `hasDeclaredNpmPackage` (:268-270), `managementSection` (:280-311), `updateSection` (:439-541),
   `hasSelectedInstallation` (:272-277). The rendered Core reason text and codex button
   titles/roles must stay byte-identical.
6. `Sources/AgentLensApp/UpdateOperationView.swift` and `UninstallOperationView.swift` — the current
   footer key equivalents (Update: Confirm Update holds `.defaultAction` :74-78; Uninstall: Cancel
   holds `.defaultAction` :73-75, destructive button has none), the preview/result/unavailable views,
   `isExecuting`/`isCancelling`, the public initializers, `.frame(minWidth: 640, minHeight: 500)`,
   `interactiveDismissDisabled`.
7. `Sources/AgentLensCore/Operations/OperationModels.swift` — `NpmUpdatePreview`, `NpmUninstallPreview`,
   `OperationOutcome`, `NpmUninstallOutcome`, the unavailable reason enums (read-only).
8. `Tests/Fixtures/M10D/npm_uninstall_acceptance.py` — the native host constructs
   `UninstallOperationView` with the CURRENT initializer (around the host at lines ~480/499). A
   parameter change breaks this protected fixture → phase failure. Do NOT edit the fixture.

## 2. FILES — explicit allow-list

Production (modify):
- `Sources/AgentLensApp/ToolDetailView.swift`
- `Sources/AgentLensApp/UpdateOperationView.swift`
- `Sources/AgentLensApp/UninstallOperationView.swift`

Worker report (new):
- `walkthroughs/M12-D-implementation.md` (labeled WORKER EVIDENCE, not acceptance)

No new test target. No AppSupport test change expected (A's `ManagementPresentation` tests already
describe the affordances; D adds no parallel predicate). If a test change seems required, STOP and
report.

## 3. DO NOT TOUCH (binding — stop and ask, never edit)

`Sources/AgentLensAppSupport/**` (frozen), `Sources/AgentLensCore/**`, `Sources/agent-lens/**`,
`Sources/AgentLensApp/MainWindow.swift`, `ToolListView.swift`, `OverviewView.swift`,
`ConflictSummaryView.swift`, `SettingsView.swift`, `DiagnosticsView.swift`, `PathActions.swift`,
`OwnershipVerificationView.swift`, `AgentLensApp.swift`, `Package.swift`, `Tests/**` (including
`Tests/Fixtures/**`), `scripts/**`, `.github/**`, `Resources/**`, `docs/**`, `DECISIONS.md`,
`ROADMAP.md`, `AGENT_LENS_SCOPE.md`, every existing `briefs/**` and `walkthroughs/**` (except the new
worker report). No new dependency. No new `AcceptedOperation` case. No CLI mutation syntax. Personal
installations, the real Agent Lens cache, and credentials are out of bounds. If a file outside the
allow-list seems necessary, STOP and report.

## 4. Contracts (quote of the binding rulings)

**R4 — render ManagementPresentation; reproduce the current controls exactly.** `ToolDetailView`
renders `ManagementPresentation(entry:)` and re-derives NO predicate in the view. The codex
affordances stay byte-identical:
- Update button shown iff `update == .prepareNpmUpdate`; title stays "Prepare Update…" /
  "Preparing Update…"; calls `onPrepareUpdate`. When `update == .unavailable(text)`, render `text`
  (the Core `operationNotAccepted.message` or the fixed newer-version sentence) and NO button. When
  `.hidden`, render nothing for the update affordance.
- Uninstall: `.prepareNpmUninstall` → the destructive "Uninstall…"/"Preparing Uninstall…" button
  (role `.destructive`, calls `onPrepareUninstall`); `.unavailable(text)` → the Core sentence, no
  button; `.needsVerification(text)` → "Verify Installation to enable Uninstall for this npm
  package."; `.hidden` → no Manage npm block.
- The Manage npm section is rendered only when the entry declares an npm package (preserve the
  current `hasDeclaredNpmPackage` gate behavior — grok, which declares no package, has no Manage npm
  block). `otherLimits` (formula/cask/standalone sentences) render as TEXT for installed entries,
  each at most once, and must NEVER replace or hide a codex npm affordance. The newer-version
  sentence (update `.unavailable` when `npmPackage == nil`) is surfaced for the first time here; it
  is additional truthful text, not a button.
- Every Core reason string is read from `ManagementPresentation` (which reads the Core enums); the
  App NEVER retypes a Core reason. No sentence names an unshipped manager's command.

**R6 / TD-11 — in-sheet progress region.** In BOTH sheets, when `isExecuting == true`,
`outcome == nil`, and `preview != nil`, show a `ProgressView` plus the text "Update in progress" /
"Uninstall in progress" and the preview's registry ID, package name, and prefix. Keep the preview
grid (above or below the region). Do NOT subscribe to stdout. When `outcome != nil`, the existing
result view is the only body. When `unavailable != nil` and no preview/outcome, the existing
unavailable view is the only body. No new `OperationState` case. **Public view initializers stay
source-compatible** (no added/removed/reordered parameters) — the M10-D Python host constructs
`UninstallOperationView` with the current initializer; a change is a phase failure.

**R5 / C-1 — footer key equivalents (NAMED contract change; both reviewers adjudicate).** In the
PREVIEW state of BOTH sheets:
- NO button holds `.keyboardShortcut(.defaultAction)`;
- Cancel becomes `.keyboardShortcut(.cancelAction)` (Escape);
- the destructive confirm button (Confirm Update / Uninstall Package) has NO key equivalent — it is
  reachable by Tab + Space or click only.
In the RESULT and UNAVAILABLE states, Done / Close KEEP `.keyboardShortcut(.defaultAction)` (safe,
non-mutating). This removes the Return-to-confirm-update path and makes the two sheets consistent.
Justification: the council brief requires that shortcuts never execute a mutation directly; no
accepted M10 evidence depends on Return-to-confirm (the M10-D click-through used AXPress). Keep
`interactiveDismissDisabled(isExecuting)` and the Cancel `disabled(isCancelling)` behavior.

**R13 — mutation controls stay in the detail view.** Updates rows have NO prepare button (unchanged
from C). The journey is reachable: Updates → select tool → detail → Prepare. Do not add a new prepare
entry point. No retained per-tool operation history (deferred).

**R12 — zero Core/AppSupport/CLI/registry change.** Core 467 / AppSupport 119 unchanged. No new
dependency. Semantic text styles; safety/effect text wraps (`fixedSize(horizontal: false, vertical:
true)`), no truncating line limit.

## 5. Acceptance (exact commands + expected observable results)

Evidence root: `R = $HOME/.hermes/cache/scratch/agent-lens-m12-d`. Run from the repo root, fresh
scratch, no toolchain/package change:

```sh
R="$HOME/.hermes/cache/scratch/agent-lens-m12-d"; mkdir -p "$R/tmp" "$R/evidence"
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
packaging 9; both import guards clean; dev app builds. The M10 fixture scripts are NOT edited; the
orchestrator reruns their accepted non-personal paths (a compile failure in the M10-D host because an
initializer changed is a D failure). Plugin-flag workaround as in A/B/C; STOP and report if the
plugin path is unavailable or the failure differs.

The orchestrator performs the read-only native spot-check (M11-B standard): codex still offers the
M10 controls when its facts qualify and withholds Update when not update-available; an unaccepted
npm-declared tool shows the Core sentence and no button; a formula/cask/standalone tool shows the
limit sentences and no brew button; grok has no Manage npm block. **Key-equivalent proof:** with a
preview sheet open, Return does NOT confirm; Escape cancels; the destructive button is reachable by
Tab and activates with Space. The orchestrator also drives the disposable npm mutation journey
(M10-C/D fixtures) — you do NOT run destructive acceptance.

## 6. EVIDENCE (raw, unedited)

Under `$R/evidence`: raw argv + stdout/stderr + exit codes + durations; SHA-256 of every changed file;
a protected-file manifest diff proving ONLY allow-listed files changed (hash every tracked file at
base `2229ddf`, compare at the candidate). Write `walkthroughs/M12-D-implementation.md` labeled WORKER
EVIDENCE: what you built, counts, changed-file hashes, the C-1 footer change, the initializer
compatibility check, stop-condition audit, unverified/unobserved items. The orchestrator reruns every
gate + the native spot-check + the disposable mutation journey independently (D-014), and summons
both independent reviewers.

## 7. STOP conditions (stop and report, never improvise)

- The progress region needs streaming output, a new outcome state, or an initializer parameter.
- A non-npm sentence would hide or re-word a codex button.
- The capability model needs a Core change, or you would re-derive a predicate in the view.
- The destructive confirm cannot be made un-triggerable by a key while keeping Cancel on Escape.
- Any design choice not resolved in this brief or the rulings — report it, do not decide it.

## 8. DONE WHEN

The acceptance commands pass (orchestrator will rerun + spot-check + mutation journey); the diff is
inside the allow-list with a clean protected manifest; Core 467 / AppSupport 119 unchanged; the
initializers are source-compatible; the worker report + raw evidence are filed. Then report:

```sh
hc send t7x "M12-D candidate ready: <state> — <counts>; <changed files>; <evidence root>; <blocker>"
```

Do NOT stage/commit/branch/reset/merge/push — the orchestrator owns Git delivery. Do NOT start
subagents or other CLIs. Do NOT grade your own work as accepted. Both council reviewers will
independently review this candidate (mandatory; they adjudicate C-1).