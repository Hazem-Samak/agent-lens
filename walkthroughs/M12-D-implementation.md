# M12-D implementation — WORKER EVIDENCE (not acceptance)

**This document is worker evidence, not acceptance.** The orchestrator reruns every gate, performs the
native spot-check and the disposable npm mutation journey, and summons BOTH independent reviewers
(mandatory for this phase; they adjudicate C-1). Phase M12-D (operation-journey completion) of
milestone M12, implemented against the frozen dispatch brief
`briefs/M12-D-operation-journey.md` and judgment rulings R4/R5/R6/R13 (plus R1/R12/R16).

- Base: `2229ddf` (M12-C accepted tip). Dispatch-brief commit `d057ea8`; branch
  `milestone/m12-workflow`.
- Candidate state: **uncommitted working tree** on top of `d057ea8`. No stage/commit/branch/reset/
  merge/push was performed.
- `Sources/AgentLensAppSupport/**` is untouched (frozen model consumed as-is).
- Evidence root: `$HOME/.hermes/cache/scratch/agent-lens-m12-d` (outside the repository).

## 1. What was built

| File | Change | Contract |
|---|---|---|
| `Sources/AgentLensApp/ToolDetailView.swift` | renders `ManagementPresentation(entry:)` for the Manage and Update slots; no view-side eligibility predicate remains | R4 |
| `Sources/AgentLensApp/UpdateOperationView.swift` | C-1 footer key equivalents; in-sheet progress region | R5/R6 |
| `Sources/AgentLensApp/UninstallOperationView.swift` | C-1 footer key equivalents; in-sheet progress region | R5/R6 |
| `walkthroughs/M12-D-implementation.md` | new | this worker report |

No AppSupport/Core/CLI/registry/`Package.swift`/tests/fixture/script/packaging change. No new
dependency. No new prepare entry point; Updates rows still have no prepare button (R13).

### R4 — the detail view renders the frozen presentation

- `detailContent` computes `ManagementPresentation(entry:)` once and passes it to the Manage and
  Update slots. The old predicate code (`acceptedOperations.contains`, `updateAvailable` +
  `npmPackage`, verified `manager == .npm`, `hasSelectedInstallation`) is gone from those slots.
  The only remaining `.updateAvailable` matches are the status label and version text rows, which
  display the probe result rather than decide an affordance.
- Update slot:
  - `.prepareNpmUpdate` renders the accepted button byte-identically: label
    "Prepare Update…" / "Preparing Update…", system image `arrow.down.circle`, `disabled(isBusy)`,
    action `onPrepareUpdate`.
  - `.unavailable(text)` renders `text` as caption/secondary wrapping text and no button. That is
    either the Core `NpmUpdateUnavailableReason.operationNotAccepted.message` (read through the
    model) or the fixed newer-version sentence (surfaced for the first time, per the A LOW-3 note).
  - `.hidden` renders nothing.
- Manage slot: the npm block is still gated by the entry's declared npm package. Inside it,
  `.prepareNpmUninstall` renders the accepted destructive button ("Uninstall…"/"Preparing
  Uninstall…", role `.destructive`, `disabled(isBusy)`, `onPrepareUninstall`) with the verified
  package fact and the accepted help sentence; `.unavailable(text)` and `.needsVerification(text)`
  render the model's text; `.hidden` renders nothing. No Core reason string is copied in the App.
- `otherLimits` render as caption/secondary wrapping text, each once, for any installed tool. They
  appear after the npm block when both exist (codex's cask sentence is additional, never a
  replacement). The Manage section appears when an npm package is declared or limits exist; a tool
  with neither gets no Manage section.
- A formula-only/cask-only/standalone installed tool now gets its truthful limit sentence; the
  existing ownership verification section and metadata/update-status grids are unchanged.

### R5 / C-1 — footer key equivalents (named contract change)

- Update sheet, preview state: Cancel has `.keyboardShortcut(.cancelAction)` (Escape); "Confirm
  Update" has **no** `.keyboardShortcut`; the previous `.defaultAction` on Confirm is removed. The
  result (Done) and unavailable (Close) states keep `.defaultAction`.
- Uninstall sheet, preview state: Cancel's former `.defaultAction` is replaced by `.cancelAction`;
  the destructive "Uninstall Package" button has no key equivalent. Done/Close keep `.defaultAction`.
- `disabled(isCancelling)` on Cancel and `disabled(isExecuting || isCancelling)` on the confirm
  button are unchanged; titles/roles unchanged; `interactiveDismissDisabled(isExecuting)` is applied
  by `MainWindow` and untouched.
- Exact current lines: UpdateOperationView preview branch — Cancel `.cancelAction` (:75), Confirm no
  shortcut (:77-80); result/unavailable `.defaultAction` (:67, :70). UninstallOperationView preview
  branch — Cancel `.cancelAction` (:76), destructive confirm no shortcut (:78-84); result/unavailable
  `.defaultAction` (:68, :71).

### R6 / TD-11 — progress region

- Both sheets show, inside the preview body and before the preview grid, a `ProgressView` plus
  "Update in progress" / "Uninstall in progress" and the prepared preview's registry ID, package
  name, and prefix. The region is rendered only while `isExecuting`; the sheet body already prefers
  the result view when an outcome exists and the unavailable view when no preview exists.
- No stdout subscription, no new operation state, no new initializer parameter.

### Initializer compatibility

The public initializers of `ToolDetailView`, `UpdateOperationView`, and `UninstallOperationView` are
byte-identical to the base (no added/removed/reordered parameters; only private view builders were
added). The protected M10-D host still constructs the sheet with the accepted labels:

```swift
UninstallOperationView(preview: preparation.preview, outcome: nil, unavailable: nil,
    isExecuting: false, isCancelling: false, onConfirm: {}, onCancel: {}, onDismiss: {})
UninstallOperationView(preview: nil, outcome: outcome, unavailable: nil,
    isExecuting: false, isCancelling: false, onConfirm: {}, onCancel: {}, onDismiss: {})
```

`Tests/Fixtures/M10D/npm_uninstall_acceptance.py` was not edited.

## 2. Counts

| Target | Baseline | Candidate |
|---|---|---|
| `AgentLensCoreTests` | 467 | 467 |
| `AgentLensAppSupportTests` | 119 | 119 |
| Total | 586 | 586 |
| Guard fixtures | 21 | 21 |
| Packaging checks | 9 | 9 |

## 3. Acceptance commands and raw evidence

Runner: `$R/run-acceptance.sh`; raw argv + stdout/stderr + exit code + duration in
`$R/evidence/<name>.{log,meta}`. `R="$HOME/.hermes/cache/scratch/agent-lens-m12-d"`.

| Command | Exit | Duration | Raw log |
|---|---|---|---|
| `env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS swift build` | 0 | 1s | `build.log` |
| full suite (fresh scratch, `--no-parallel`, CLT plugin flag) | 0 | 153s | `full-suite.log` |
| `python3 scripts/check-core-ui-imports.py` | 0 | 0s | `guard-core.log` |
| `python3 scripts/check-core-ui-imports.py --source-root Sources/AgentLensAppSupport` | 0 | 0s | `guard-appsupport.log` |
| `python3 Tests/Packaging/test_core_ui_imports.py` | 0 | 1s | `guard-fixtures.log` |
| `python3 scripts/build-dev-app.py --scratch-root "$R/dev-app" --configuration debug` | 0 | 26s | `dev-app.log` |
| `python3 Tests/Packaging/test_dev_app_bundle.py --app "$R/dev-app/AgentLensApp-debug.app"` | 0 | 2s | `packaging.log` |
| `git diff --check` | 0 | — | `diff-check.log` |

Observed results (worker run; orchestrator will rerun, spot-check, and run the disposable journey):

- `full-suite.log`: `✔ Test run with 467 tests in 0 suites passed` (Core) and
  `✔ Test run with 119 tests in 5 suites passed` (AppSupport); no failure, no skip, no issue line.
- `guard-core.log`: `32 Swift file(s) under Sources/AgentLensCore; no SwiftUI/AppKit imports`.
- `guard-appsupport.log`: `6 Swift file(s) under Sources/AgentLensAppSupport; no SwiftUI/AppKit imports`.
- `guard-fixtures.log`: `Ran 21 tests ... OK`. `packaging.log`: `Ran 9 tests ... OK`.
- `dev-app.log`: `Build complete!` and `$R/dev-app/AgentLensApp-debug.app`.

## 4. Changed-file hashes and protected manifest

`evidence/changed-files.sha256` and the manifests vs base `2229ddf` and vs HEAD `d057ea8` were
regenerated at the candidate. Result: only the three allow-listed modified files differ in the
tracked manifest; the only untracked addition is this report. The only committed delta
`2229ddf..HEAD` is `briefs/M12-D-operation-journey.md` (orchestrator dispatch-brief commit
`d057ea8`), not an implementer change. No test/fixture file differs.

Candidate SHA-256 (`evidence/changed-files.sha256`):

```text
8dde3555ebb3dfbe1c6e55d2ce635e85f2a251607d8e191e7ae187c11282ce59  Sources/AgentLensApp/ToolDetailView.swift
3c9d696f5f3df3473cbf08f56b623178c8b4fd0ea4e370103366b8290b613a1d  Sources/AgentLensApp/UninstallOperationView.swift
6f0fd735d36721a84ac76b305151cd5b027aa5262d8b0e6d07659ba75fc379a9  Sources/AgentLensApp/UpdateOperationView.swift
```

This report's own SHA-256 is recorded in the same evidence file after the report's final write.

## 5. Stop-condition audit

- The progress region needed no streaming output, no new outcome state, and no initializer
  parameter.
- No non-npm sentence hides or re-words a codex affordance: limits are rendered after the npm slot
  and the npm button is emitted solely from `.prepareNpmUninstall`/`.prepareNpmUpdate`.
- The capability model needed no Core change and no predicate was re-derived in the view.
- The destructive confirm was made un-triggerable by a key while Cancel keeps Escape; no design
  ambiguity was encountered.
- No file outside the three-file allow-list was edited; no new prepare entry point; no retained
  operation history.

## 6. Unverified / unobserved

- No native sheet was launched or keyboard-driven by the worker. Return-does-not-confirm,
  Escape-cancels, and Tab+Space on the destructive button are implemented in source but are the
  orchestrator's spot-check evidence.
- No destructive mutation journey was run by the worker (orchestrator runs the disposable M10-C/D
  fixtures).
- Both independent reviewers' C-1 adjudication is outside this report.
