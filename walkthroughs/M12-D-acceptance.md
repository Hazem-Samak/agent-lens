# M12-D acceptance — operation-journey completion (mutation presentation)

Date: 2026-11-13. Orchestrator: Qoder (Herdr `t7x`). Milestone branch: `milestone/m12-workflow`.
**Accepted candidate: `6c1405a`.** Phase M12-D of `briefs/M12-plan.md`; dispatch brief
`briefs/M12-D-operation-journey.md`; binding rulings R4/R5/R6/R13 (contract decision **C-1**).

**Decision: M12-D is TECHNICALLY ACCEPTED.** Both mandatory independent reviews PASS with zero
blocking findings and both adjudicate C-1 safe; the orchestrator independently reran every gate
(D-014), observed the real app, and natively proved the C-1 key behavior.

## Independent reviews (both PASS; C-1 adjudicated)

| Reviewer | Route | Verdict | Findings | C-1 adjudication |
|---|---|---|---|---|
| MiniMax M3.1-Flash/xhigh | mcode, Herdr `t9q` | **PASS** | 0 blocking/high/medium, 1 low, 4 info | SAFE and JUSTIFIED — removes Return-to-confirm, adds zero-mutation Escape=cancel, breaks no M10 evidence, restores the M10-D planning constraint the shipped M10-C update sheet had violated |
| Grok 4.7/high | grok, Herdr `t9r` | **PASS** | 0 blocking/high/medium/low, 1 info | ACCEPT — Return no longer confirms either mutation, Escape cancels, no M10 safety property weakened |

Records: [minimax.md](M12-D-evidence/reviews/minimax.md), [grok.md](M12-D-evidence/reviews/grok.md).
Both confirmed the diff is exactly the three allow-listed App files; codex affordances byte-identical;
Core reason strings read through the model never retyped; non-npm limits are text only; progress
region bound to the preview with no stdout/new state/initializer change; public initializers absent
from the diff (source-compatible).

## Orchestrator gate results (D-014, independent rerun)

Fresh scratch `agent-lens-m12-d-orch`, `swift test --no-parallel` + CLT TestingMacros flag:

- Full suite: **467 Core + 119 AppSupport = 586 passed, zero skips/failures**, exit 0.
- Core/UI import guard clean (32 Core files); AppSupport import guard clean (6 files).
- Guard behavioral fixtures 21 OK; packaging 9 OK; dev app built; `git diff --check` clean.
- Diff inside the allow-list: `ToolDetailView.swift`, `UpdateOperationView.swift`,
  `UninstallOperationView.swift`, worker report. **No AppSupport/Core/CLI/registry/fixture/Package/
  scripts/.github diff.** The M10-D fixture is untouched; initializers source-compatible.

## Native spot-check + C-1 key proof (orchestrator-observed, real debug app)

Screenshots: `agent-lens-m12-d-orch/evidence/native/`. Read-only verification + preview + cancel only
(no mutation; M11-B precedent for read-only ownership verification):

- **Codex affordances**: Manage shows "Verify Installation to enable Uninstall for this npm package."
  (needsVerification) plus the additional cask limit sentence "Homebrew cask update and uninstall are
  not available in this version." (codex declares npm + cask; the cask sentence is additional text,
  not a replacement). Update Status "Not checked" → no update button (hidden). After read-only Verify
  Installation, ownership shows "Verified" (npm, @openai/codex) and the destructive "Uninstall…"
  button appears.
- **C-1 key proof**: opened the Uninstall preview sheet ("Uninstall Codex", registry ID codex, package
  @openai/codex, registry pin, manager). Pressed **Return** → the sheet stayed in preview
  (`stillPreview: true`, `resultShown: false`) — Return did NOT confirm. Pressed **Escape** → the sheet
  dismissed (`sheetGone: true`, back to detail) — zero mutation. The destructive confirm has no key
  equivalent (code + reviews); it was NOT activated against the personal installation.
- Conflict summary (M12-C) still renders measured versions (Codex 0.168.0/0.167.0; Cline 3.0.74×3).

## Requirement-to-evidence

| Ruling | Evidence |
|---|---|
| R4 render ManagementPresentation; codex byte-identical; Core reason read; limits text | code inspection; A's model tests; native codex spot-check; both reviews |
| R5/C-1 Return never confirms; Escape cancels; destructive no key equiv | native key proof (Return no-confirm, Escape cancel); both reviews adjudicate safe |
| R6 progress region bound to preview; no stdout/new state/initializer | code; both reviews; initializer-check |
| R13 mutation controls stay in detail; no new prepare entry point | code (Updates rows unchanged); reviews |
| R12 zero Core/AppSupport/CLI/fixture change | protected manifest; import guards; 586 unchanged |

## Limitations and carried-forward notes (honest)

- The full destructive confirm path (Tab+Space activating the destructive button → result) was NOT
  run against the personal codex installation (no personal mutation). Core mutation semantics are
  unchanged (M10-accepted; all M10 operation tests pass in the 586). The disposable M10-C/D fixtures
  remain the destructive-journey evidence; the presentation changes do not alter Core.
- Grok INFO-1: the uninstall sheet's file comment still calls Cancel the "default action" (stale
  comment, cosmetic). MiniMax 1 low + info notes are test-pinning/forward observations. These are
  carried to M12-E (which touches both sheets for accessibility) for cleanup; non-blocking.
- App layer has no automated test surface; native spot-check + reviews are the App evidence.

## Owner authorizations

M12-E dispatch proceeds under the owner's pre-authorized flow. Merge to `main` is NOT authorized.
OD-M12-1 remains the one open owner gate (blocks M12-F only). No release.

## Evidence index

`R = $HOME/.hermes/cache/scratch/agent-lens-m12-d-orch`: `evidence/` (gate logs), `evidence/native/`
(codex detail/verified, uninstall preview, after-return screenshots). Reviews:
`walkthroughs/M12-D-evidence/reviews/{minimax,grok}.md`. Worker report:
`walkthroughs/M12-D-implementation.md`.