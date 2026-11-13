# M12 Planning Council — shared task brief

Date: 2026-11-12. Orchestrator/main judge: Qoder (Herdr terminal `t7x`).
Council members plan **independently**; the orchestrator judges, reconciles, and freezes the final plan.

## 1. Context

Agent Lens is a native Swift 6 / SwiftUI macOS app (zero external dependencies) that diagnoses
AI CLI installations (which copy PATH runs, duplicates, versions, ownership) and delegates
Update/Uninstall to package managers. M0–M10 are delivered to `main` (PR #1 merge `65f7a82`).
**M11 (fourteen-entry catalogue + fail-closed mutation gate + capability matrix + contributor
foundation) is technically accepted** on `milestone/m11-catalogue` at combined candidate `b07e321`;
PR #2 to `main` is open and NOT merged (owner gate).

The next milestone is **M12 — complete native diagnostic and operation workflow** (ROADMAP §4).
Its user result: *Overview, AI Agents, AI Coding Tools, AI Harnesses, Updates, Diagnostics, and
focused Settings make the complete catalogue understandable and manageable.*

ROADMAP §4 M12 requirements (binding):

- Add category/update filters, counts, package/source details, and a conflict summary that leads
  to per-installation PATH evidence and versions.
- Complete the existing npm confirmation/progress/output/result journey. Future manager
  capabilities use the same capability-driven UI and remain explicitly unavailable until their
  adapters land.
- Preserve local-first launch, search, neutral unknowns, loading/empty/failure states, and
  Copy/Reveal behavior. **Selection or filtering cannot retarget an existing confirmation.**
- Finish native menus, keyboard navigation/shortcuts, VoiceOver labels and spoken checks, large
  text, narrow windows, and light/dark appearance. **Settings only control delivered features.**
- **Close the outstanding M8 keyboard-only Copy/Reveal measurement here.** It is a required M12
  gate, not something to defer to M18.

M12 acceptance (ROADMAP): actual-app journeys cover find/filter → inspect competing copies →
confirm or cancel an eligible operation → review output → observe the post-rescan winner/version.
Exercise empty inventory, offline, failed rescan, missing manager, permission denial, long paths,
keyboard-only, and VoiceOver. No destructive acceptance touches personal installations.

**Branch and base:** the milestone branch is `milestone/m12-workflow`, created from
`milestone/m11-catalogue` tip `0589fac` (M11 accepted content + MIT license D-023 + PR #2 record).
M12 stacks on unmerged M11; do not rebase onto `main`, do not switch branches. The orchestrator
freezes the plan and commits it on this branch after judging your proposals.

**Authorization already given (owner message 2026-11-12):** the owner authorized the full flow —
council planning → orchestrator freeze/commit on the branch → implementation by **DeepSeek V4.1
Flash 1017 via OMP (`river/deepseek-ai/DeepSeek-V4.1-Flash-1017`, max reasoning)** as sole product
writer → independent read-only reviews by the two council models (**MiniMax M3.1-Flash/xhigh via
mcode; Grok 4.7/high via grok CLI**) → orchestrator combined acceptance → pull request → owner
merge decision (merge is NOT authorized in advance). Technical decisions are delegated to the
orchestrator/judge; only genuine product choices go back to the owner. Your proposal must
therefore be dispatch-ready: bounded phases, exact allow-lists, measurable gates, and design
decisions resolved or explicitly flagged as owner decisions with a recommendation.

## 2. Required reading (in this order)

1. `ROADMAP.md` — §2 finish line, §4 M12 (and M11/M13 for boundaries), §5 operating protocol,
   §6 architecture/safety invariants, §7 owner gates, §8 next action.
2. `DECISIONS.md` — D-001…D-023, especially D-006/007 (tri-state), D-008 (uninstall policy),
   D-012/013/014 (tests, one branch, orchestrator acceptance), D-021 (mutation gate), D-022
   (shipping CLI read-only), D-023 (MIT). Do not re-litigate settled decisions.
3. `AGENT_LENS_SCOPE.md` — §2 categories, §4 detail view, §5 Update, §6 Uninstall, §7 Search &
   Filtering (proposed shortcuts), §8 Duplicate Detection, §9 Proposed Main UI, §12 native stack,
   §27 implementation notes, §29 operating protocol (read selectively; the file is large).
4. `briefs/README.md` — brief rules (one branch per milestone, read-only reviewers, orchestrator
   runs acceptance, DO NOT TOUCH is binding, implementer gets the brief not the scope document).
5. Current app surface (read all of these): `Sources/AgentLensApp/MainWindow.swift`,
   `ToolListView.swift`, `ToolDetailView.swift`, `DiagnosticsView.swift`, `PathActions.swift`,
   `OwnershipVerificationView.swift`, `UpdateOperationView.swift`, `UninstallOperationView.swift`,
   `AgentLensApp.swift`.
6. Presentation state: `Sources/AgentLensAppSupport/InventoryViewModel.swift`,
   `InventoryService.swift`, `InventorySnapshot.swift`, `PathActionTarget.swift`.
7. Core seams you may need (read selectively): `Detection/DetectorMetadata.swift` (category,
   acceptedOperations), `Diagnostics/PathDiagnostics.swift`, `Updates/VersionStatus.swift`,
   `Operations/OperationModels.swift`.
8. Gates and evidence precedent: `.github/workflows/ci.yml` (seven hosted gates, floors
   467/80/547, guard 21, packaging 9, anchors); `briefs/M8-path-actions.md` (the open keyboard
   gate); `walkthroughs/M10-D-implementation.md` §"Native ordinary-app click-through"
   (Accessibility-driven real-app evidence method); `walkthroughs/M11-B-acceptance.md` (native
   spot-check + gate reason surfacing); `docs/capability-matrix.md` (what is manageable today).
9. One recent brief for format calibration: `briefs/M11-B-mutation-gate.md`.

## 3. Verified starting point (judge-audited; re-verify anything you rely on)

- Sidebar today has exactly two destinations: **Inventory** and **Diagnostics**
  (`NavigationDestination` in `MainWindow.swift`). There is no Overview, no per-category
  destinations, no Updates section, no Settings, no conflict summary surface.
- `ToolListView` already has `.searchable` (name/executable/path) over `model.filteredEntries`;
  counts exist in toolbar/sidebar (`knownToolCount`, `installedToolCount`, `updateAvailableCount`).
- `ToolDetailView` carries M8 Copy Path / Reveal in Finder (both path rows), M9 ownership
  verification, and M10 Update/Uninstall preparation; the confirmation/progress/output/result
  sheets are `UpdateOperationView` / `UninstallOperationView` (M10-C/D accepted semantics).
- Registry: 14 entries, categories `aiAgent`/`aiCodingTool`/`aiHarness`; only `codex` carries
  `acceptedOperations: [npmUpdate, npmUninstall]` (D-021 fail-closed gate). Every other entry is
  informational for mutation with a Core reason surfaced in app/CLI.
- Shipping CLI (`Sources/agent-lens/main.swift`) dispatches only `scan`, `verify-installation`,
  `debug-env` — read-only (D-022). No CLI mutation syntax may be added.
- Local suite: 547 tests (467 Core + 80 AppSupport), zero skips/failures; CI floors match;
  guard behavioral fixtures 21; packaging checks 9. This is a CLT-only workstation: local
  `swift test` needs the documented invocation-local TestingMacros plugin flag (see
  `briefs/M8-path-actions.md` acceptance commands); hosted CI (full Xcode) is unaffected.
- Native evidence precedent: the owner granted Accessibility; M10-D drove the real debug app
  through Accessibility with screenshots + action transcripts under a disposable public fixture
  (synthetic HOME/config/cache). M11-B did an orchestrator-observed native spot-check.
- The M8 keyboard-only Copy/Reveal activation measurement is OPEN and is a required M12 gate.

## 4. Your task

Write an independent M12 delivery plan proposal to **your assigned output file** (given in the
dispatch message). Cover, with concrete specifics rather than generalities:

### A. Current-state audit
Verify §3 against the code. List what M12 must ADD vs CHANGE vs PRESERVE, with file:line
citations. Mark anything you could not verify. Identify which M12 requirements are already
satisfied (e.g., search, sheets) so phases do not redo accepted work.

### B. Phase decomposition
Split M12 into bounded, sequential phases on the ONE milestone branch (suggested naming
`M12-A`, `M12-B`, …; you choose the split). For each phase give:
- observable goal and explicit non-goals;
- allow-list sketch: exact files/directories the implementer may touch, and protected files;
- contracts that must not change (M10 confirmation semantics, D-021 gate, tri-state, Core/UI
  boundary);
- acceptance outline: exact commands where possible, expected observable results, evidence format;
- dependencies and stop conditions;
- review recommendation (mandatory independent review for anything touching operation/mutation
  contracts or safety behavior; orchestrator acceptance for routine UI; the owner named both
  council models as standing independent reviewers).
Phases must be small enough for one implementer dispatch each, and unambiguous enough for the
owner-selected flash-tier implementer: resolve design decisions in the plan, do not leave them
to the implementer. Suggested ordering logic (yours to justify or replace): presentation-state
foundations → navigation/filters/counts → conflict summary → operation-journey completion →
accessibility/native polish → M8 keyboard gate + combined hardening.

### C. Information architecture and navigation
Design the seven-destination surface (Overview, AI Agents, AI Coding Tools, AI Harnesses,
Updates, Diagnostics, Settings) against scope §9 and the existing `NavigationSplitView`:
- what each destination shows; where counts come from; category/update filters and their
  interaction with search;
- the conflict summary: what counts as a conflict (duplicates, shadowing, off-PATH winners,
  inconsistent state), how it leads to per-installation PATH evidence and versions without
  duplicating `DiagnosticsView`;
- Updates section semantics under tri-state rules: unknown never counts as up-to-date and never
  inflates update counts; only capability-matrix-supported latest checks; mutation controls only
  where D-021 accepts them (today: codex npm-global verified copies);
- **selection/filter safety:** enumerate the ways a filter, search, category switch, or rescan
  could retarget an existing confirmation/preview, and the exact invariant + tests that prevent
  it (M10 contract: a changed target/manager/package/registry/prefix invalidates the preview);
- what lives in Core vs AppSupport vs App (Core stays UI-free; no SwiftUI/AppKit imports).

### D. Operation journey completion
Audit the existing npm confirmation/progress/output/result journey end to end. What is actually
missing for M12 ("complete the existing journey") versus already accepted in M10? Design the
capability-driven availability pattern future managers (M13–M15) will reuse: explicitly
unavailable with truthful reasons, never hidden or speculative. No new adapter, no semantic
change to accepted M10 behavior without a named, justified contract decision.

### E. Native polish, accessibility, and Settings
Concrete plan for: native menu bar commands; keyboard navigation and shortcuts (scope §7
suggests ↑/↓, Enter, U, R, S, ⌘K — refine; shortcuts must never execute a mutation directly and
must not collide with text entry/search); VoiceOver labels, hints, and spoken checks; large
text (accessibility dynamic type sizes); narrow-window behavior (minimum sizes, wrapping,
no clipped safety text); light/dark appearance (semantic colors).
**Settings honesty:** enumerate what delivered features could legitimately be controlled today.
M16 (cached launch/menu bar/opt-in checks) is NOT delivered; Settings must not expose speculative
toggles. If nothing is legitimately configurable yet, say so and design the minimal truthful
Settings surface (or recommend deferring the destination with a recorded reason — but ROADMAP
names Settings in the M12 user result, so prefer a truthful minimal surface).

### F. M8 keyboard gate closure and accessibility measurement method
Design the exact measurement that closes the open M8 gate: keyboard-only activation of Copy Path
and Reveal in Finder in the REAL app (no mouse), including focus traversal to both path rows,
activation keys, clipboard read-back, and Finder selection observation. Also design the VoiceOver
spoken-check method (what is spoken for list rows, details, path actions, operation sheets,
error states). Methods must be executable on this macOS machine by the orchestrator (Accessibility
API / VoiceOver / screenshots / transcripts — precedent in M10-D walkthrough). Specify evidence
format and what would count as a failure. State any TCC/permission prerequisites.

### G. Acceptance strategy
Per-phase gates plus the combined M12 gate. The combined gate must include the ROADMAP actual-app
journey matrix: find/filter → inspect competing copies → confirm or cancel an eligible operation →
review output → post-rescan winner/version; plus empty inventory, offline, failed rescan, missing
manager, permission denial, long paths, keyboard-only, VoiceOver. Reuse the disposable npm
fixture machinery (`Tests/Fixtures/M10C/npm_update_acceptance.py`, `M10D/npm_uninstall_acceptance.py`)
for mutation journeys — never personal installations. Specify: full-suite/guard/dev-app/packaging
reruns, hosted gates at the exact candidate SHA, floor policy (raise only to orchestrator-measured
counts, never lower), protected-file manifests, and what is NOT an acceptance target.

### H. Risks and open questions
Ranked risks (confirmation retargeting, accessibility regressions, scope creep into M13–M16,
CI integrity, flash-tier implementer ambiguity, native-measurement feasibility) and a numbered
list of decisions only the owner can make (OD-M12-1, …), each with a recommendation. Include
anything you could not resolve and why.

### I. Explicit non-goals (binding)
No new manager mutation adapters (M13–M15); no per-tool mutation promotions; no cached launch,
menu bar, or opt-in periodic checks (M16); no bundled CLI (M17); no release/signing/publication
(M18–M19); no CLI mutation syntax (D-022); no registry/schema/detector changes unless a phase
names a precise, justified exception; no new dependencies; no speculative Settings toggles;
no public contribution invitation; no personal installation as an acceptance target.

## 5. Hard constraints

- **Read-only on the product.** Do not edit anything under `Sources/`, `Tests/`, `scripts/`,
  `Resources/`, `Package.swift`, `.github/`, or any existing brief/walkthrough/doc. Do not run
  git commands that mutate state (no commit/branch/checkout/stash/reset/push). No installs, no
  builds, no test runs, no launching the app — static reading plus read-only shell inspection
  (`ls`, `command -v`, reading files) only. The orchestrator runs all gates.
- **Do not start subagents or other CLIs.** You are one council member.
- **Do not read the other member's proposal.** Independence is the point.
- The ONLY file you may write is your assigned proposal path under `briefs/M12-planning/`.
- Never fabricate code behavior, API availability, or measurement results. `unverified` is an
  acceptable and expected answer; a confident guess is not. Cite file:line for code claims.
- If you are blocked (missing access, ambiguous instruction, tool failure), stop and report
  the blocker instead of improvising.

## 6. Reporting

When done — or stuck — report to the orchestrator:

```sh
hc send t7x "M12 proposal complete: briefs/M12-planning/<your-file>.md — <3-line summary: phase count, key design decisions, open blockers>"
```

Write the full proposal to the file; the message is only a pointer and summary.

## 7. How the judge will weigh proposals

1. Truthfulness and evidence quality (verified code citations; honest unknowns).
2. Phase boundedness and dispatch-readiness (one writer, clear allow-lists, measurable gates,
   design decisions resolved for a flash-tier implementer).
3. Fidelity to settled decisions and safety invariants (DECISIONS.md, ROADMAP §6, M10 contracts,
   D-021 gate, confirmation-retargeting invariant).
4. Native UX quality and accessibility measurability (real keyboard/VoiceOver evidence, not
   claims; truthful Settings; honest unavailable states).
5. Clear separation of owner decisions from technical recommendations.