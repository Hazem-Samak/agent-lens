# M11 Planning Council — judgment record

Orchestrator/main judge: Qoder (Herdr `t7x`). Date: 2026-11-12.
Base commit for the freeze: `d0a2b417e8c7d05f3c715a24e93f17851f7ab904` (`main`, clean tree at council start).

## Council composition and process

| Member | CLI / build | Model | Effort | Herdr terminal | Output |
|---|---|---|---|---|---|
| MiniMax | mcode v0.7.6 | MiniMax-M3.1-Flash (default route, en-prod) | xhigh (set via `/model` selector; verified in status bar) | `t85` council-minimax | `proposal-minimax.md` |
| Grok | grok 1.0.77 (grok-1.0.77-macos-aarch64) | grok-4.7 | high (`--reasoning-effort high`) | `t81` council-grok | `proposal-grok.md` |

- Shared task: `council-brief.md`. Members worked independently and were instructed not to read
  each other's proposals.
- Both were launched read-only on the product: no product edits, no git mutations, no installs,
  no subagents; single writable proposal file each.
- Process notes:
  - mcode `-m minimax_oauth/MiniMax-M3.1-Flash` was rejected by the en-prod route; the default
    model is already M3.1-Flash, so it was launched without `-m` and effort set to xhigh in the
    TUI selector (status bar confirmed `M3.1-Flash · Effort xhigh`). mcode runs in its default
    "Full access" permission mode.
  - Grok launched with `--permission-mode acceptEdits`; its read-only shell research still
    prompted per-command. After two individually-approved read-only inspections, the session
    was switched to always-approve (option 1 in Grok's permission dialog) so bounded research
    could proceed unattended. This grant is scoped to this planning session; repo integrity is
    audited by the orchestrator before the freeze commit.
- Both agents are visible in the Herdr window: Agent Lens space → "M11 Planning Council" tab.

## Judge's independent baseline evidence (read-only, 2026-11-12)

Local observations on this machine (supplement, not replacement, for primary-source research):

- `dsh` → `~/.local/bin/dsh` symlink → `../lib/node_modules/@deepseek-ai/dsh/lib/bin.js`.
  Package identity `@deepseek-ai/dsh` v0.2.2-rc.1, described as "dsh CLI: profile launch, plugin
  management, and configuration inspection". npm-global layout. DSH ambiguity is resolvable:
  DeepSeek harness; primary documentation still required for the plan.
- `agy` → standalone ~233 MB binary at `~/.local/bin/agy` (Google Antigravity CLI per local
  tooling metadata). No package manager identity observed.
- `omp` → standalone ~223 MB binary at `~/.local/bin/omp` (Oh My Pi per local tooling metadata).
- `hermes` → 76-byte `/bin/sh` wrapper at `~/.local/bin/hermes` exec'ing
  `~/.hermes/hermes-agent/.hermes/bin/hermes`. Standalone layout under `~/.hermes`.
- `qoder` → wrapper at `~/.qoder/entry/qoder`; `qodercli` → symlink to versioned binary
  `~/.qoder/bin/qodercli/qodercli-1.1.88`. Two related executables; identity needs care.
- `cline` → shim at `~/.local/shims/cline` that repairs an invalid macOS code signature on the
  Bun-compiled binary inside npm package `cline`, then execs it. The shim deliberately shadows
  the npm-global binary. A real-world shadowing case M11 fixtures should represent honestly.
- Not on PATH here: `claude`, `gemini`, `aider`, `goose`, `kiro`. Their layouts must come from
  primary documentation; local absence is not evidence of absence elsewhere.

Schema facts that bound the plan (from `Sources/AgentLensCore/Detection/`):

- Fixture layouts known to the registry: `npmGlobal`, `singleDirectory`, `brewCellar` only
  (`DetectorRegistry.knownLayouts`).
- `PackageManager` enum: `npm`, `homebrewFormula`, `homebrewCask` only. uv/pip/cargo package
  identities cannot be declared today; M11 must decide between bounded schema extension and
  informational-only entries for tools installed through those managers.
- Categories: `aiAgent`, `aiCodingTool`, `aiHarness` (matches scope §2).
- Declared packages are candidates, never ownership proof (M9 contract); version queries are
  bounded argv specifications, not shell.

## Evaluation criteria (from council-brief §6)

1. Truthfulness and evidence quality (cited primary sources; honest unknowns).
2. Phase boundedness and dispatch-readiness.
3. Fidelity to settled decisions and safety invariants.
4. Contributor scalability (data-only additions, schema gates, docs).
5. Clear separation of owner decisions from technical recommendations.

## Proposals received

- `proposal-grok.md` (t81, 2026-11-12 ~18:07): 5 implementer phases (A identity freeze, B settled
  registry, C collisions, D owner remainder/skip, E matrix + contributor proof) plus orchestrator
  combined gate. Conservative vocabulary: no new layouts/managers/sources; exact-set test pinning
  with CI anchor rename; markdown matrix enforced by a Swift test. DSH held for owner confirmation.
- `proposal-minimax.md` (t85, 2026-11-12 ~18:2x): 8 phases (0 freeze, A vocabulary, B capability
  gate, C/D/E batches, F matrix + contributor, G combined). Found the mutation-surface safety gap;
  proposed a runtime CapabilityMatrix.json + fail-closed gate, new layouts/managers, generated
  docs + validator/renderer scripts + CI step. Resolved DSH/AGY identities from primary sources.

Both proposals are high quality, independently researched, and honestly marked. The judge verified
load-bearing claims against the code and primary registries before ruling.

## Judge verification performed

Code (read-only):
- `InstallationOwnershipVerifier.verifyNpm` is generic: any definition declaring an npm candidate
  and classified npm proceeds to `NpmOwnershipProbe`.
- `InventoryViewModel.swift:458-459` gates Uninstall on `verifiedInstallation.manager == .npm`;
  `ToolDetailView.swift:284-285` gates the Update control the same way;
  `canVerifyOwnership` (ToolDetailView.swift:257-269) offers Verify on declared npm candidates.
- Core operation seams: `NpmUpdateOperation.prepare`, `NpmUninstallOperation.prepare`.
- **MiniMax's safety finding is confirmed:** adding npm-declared detectors silently enables the
  M10 Verify→Update/Uninstall chain for tools that never had a per-tool accepted mutation scenario.
- CI anchor `bundledDefaultDetectorsIsValidWithThreeTools` exists in `.github/workflows/ci.yml`
  (CORE_ANCHORS, line ~168); floors 456/79/535, guard 21, packaging 9; `build-dev-app.py` preflight
  accepts any `registry_count`/`registry_ids` (Grok's claims verified).

Primary registries (judge spot-checks, 2026-11-12):
- `block-goose-cli` formula: AI agent, goose-docs.ai, conflicts with pressly `goose`. ✔ both members.
- Casks `claude-code` and `claude-code@latest`: real, binary `claude`. ✔ Grok.
- `hermes-agent` formula: official homebrew-core, source NousResearch/hermes-agent, binaries
  `hermes`/`hermes-acp`/`hermes-agent`. **MiniMax right; Grok under-declared (empty packages).**
- `cline` formula: real but **deprecated 2026-05-18** (non-FOSS SDK/prebuilt binaries), disabled
  2027-05-18. **Missed by both.** Declare with a known limit.
- `gemini-cli` formula: real but **deprecated 2026-06-18 "unsupported", disabled 2026-12-18,
  replacement cask `antigravity-cli`**. Grok had left the listing unverified; MiniMax verified the
  formula but missed the deprecation. Declare with a known limit; keep the entry (scope names it).
- Cask **`antigravity-cli`**: official Google, binary artifact `antigravity` → target `agy`,
  v1.5.6, `auto_updates: true`. **Missed by both members** (both had AGY packages empty). Declare.
- npm `@oh-my-pi/pi-coding-agent`: real, bin `omp → dist/cli.js`, repo can1357/oh-my-pi.
  **MiniMax right**; distinct from the unrelated `@oh-my-pi/cli` Grok warned about. Declare both
  this npm package and tap `can1357/tap/omp`.
- Kiro: formula `kiro-cli` → 404; **cask `kiro-cli` → real** (3.2.1, kiro.dev/docs/cli, binary
  `kiro-cli`; zap lists `~/.local/bin/kiro-cli`, evidencing the script destination). Resolves the
  Grok (formula-vs-cask conflict) / MiniMax (no package) disagreement: **cask only**.

## Rulings

**R1 — Mutation acceptance gate (conflict: MiniMax gate vs Grok protected ownership/operations).**
MiniMax's safety finding is real and verified in code; Grok's plan misses it. M11 MUST close the
gap before any new npm-declared entry ships. Mechanism ruling: a **minimal additive registry
field**, not MiniMax's separate runtime CapabilityMatrix.json schema. Optional per-detector
`acceptedOperations` array, closed vocabulary `npmUpdate`/`npmUninstall` (the only operations that
exist today); absent/empty = no mutation. Fail-closed in Core `prepare` seams AND mirrored in
AppSupport/App/CLI eligibility with a truthful reason. Ownership verification stays diagnostic
(Verify still offered); latest-check stays ungated (read-only, tri-state, M6/M10-B contracts).
Codex seeds both operations (M10 accepted); every new entry is informational until its own
accepted scenario. Mandatory independent read-only review for this phase (ROADMAP §5.4).
Per-tool promotion scenarios are a separate owner-authorized dispatch, not silently inside M11.

**R2 — Vocabulary (conflict: MiniMax new layouts/managers vs Grok none).** Grok wins. M11 adds no
layouts, sources, or PackageManager values. uv/pip/cargo/bun identities are recorded in the
identity doc and matrix limits; the vocabulary arrives with ownership adapters in M13–M15.
Rejected: `uvTool`/`pipxVenv`/`cargoBin`/`nativeInstaller`/`gitSource` layouts, uv/cargo enum
values, `alternateExecutableNames` (Qoder/OpenCode/Hermes second executables become known limits).
Rationale: ROADMAP §6 forbids speculative work; a source label without ownership proof is exactly
what the invariants prohibit; M11's acceptance is data-driven detection, not schema expansion.

**R3 — Matrix mechanism (conflict: runtime JSON + scripts + CI step vs markdown + Swift test).**
Grok wins, extended for R1: `docs/capability-matrix.md` + one Swift agreement test enforcing
id/category/packages/layout agreement with the registry AND capability truth (Update/Uninstall
`yes` only where `acceptedOperations` + npm; latest-check only npm/homebrewFormula). No new
scripts, no new CI step, no runtime matrix file. The registry JSON is the single source of truth.
M12 may revisit presentation with the full workflow.

**R4 — Identity corrections (binding on the freeze phase).** From judge spot-checks: Hermes
formula `hermes-agent` declared; Cline formula `cline` declared with deprecation limit; Gemini
formula `gemini-cli` declared with deprecation/disable/replacement limits; AGY cask
`antigravity-cli` declared (auto-update limit); OMP npm `@oh-my-pi/pi-coding-agent` + tap
`can1357/tap/omp`; Kiro cask `kiro-cli` only, executable `kiro-cli`, script destination
`~/.local/bin/kiro-cli` to be confirmed from the installer text in M11-A; OpenCode core formula
`opencode` added (Grok verified). Do-not-declare table adopted from MiniMax §B.3 (brew `dsh`,
npm/PyPI `goose`, npm `kiro-cli` placeholder, cask `qoder`, `@oh-my-pi/cli`, third-party
`deepseek-harness*` PyPI names) plus Grok's pressly/goose and desktop-surface exclusions.

**R5 — Qoder executable (conflict: Grok `qodercli` vs MiniMax `qoder` + alternates).** Grok wins:
`qodercli` is the stable CLI runtime; the `qoder` dispatcher can launch the IDE and is not a
trustworthy CLI identity. No alternate-executable schema field in M11. Owner decision OD-Q;
choosing `qoder` reopens research instead of being implemented.

**R6 — Unverified version shapes.** Five tools (claude, gemini, aider, goose, kiro-cli) have
unverified `--version` shapes. M11-A may measure them in an **owner-authorized disposable scratch**
(npm `--prefix` scratch, uv tool install into scratch; never personal installs). If the flag itself
cannot be confirmed from primary docs and cannot be measured, the entry is held (Grok's rule).
If the flag is confirmed but the stream/shape is unknown, ship the documented query; failure →
nil → neutral unknown is already safe (D-007), and the matrix records the limit.

**R7 — Test/CI discipline (conflict: exact-set pin + rename vs generic assertion).** Grok wins:
keep exact-set assertions, rename the anchor to `bundledDefaultDetectorsMatchFrozenCatalogue`
in the same phase as the CORE_ANCHORS edit, update every allow-listed id-list pin, raise floors
only to the orchestrator-measured count in the final phase. MiniMax's "generic set-based"
replacement would weaken the gate that catches accidental catalogue drift.

**R8 — Phase structure.** Hybrid: A identity freeze → B mutation gate → C settled batch →
D collision batch → E owner remainder (skippable) → F matrix + contributor foundation →
orchestrator combined gate. Gate before catalogue data (MiniMax's ordering insight); batches and
allow-lists largely Grok's; research isolated (both).

**R9 — DSH/AGY blocker status.** Both members resolved the identities from primary sources, which
is what ROADMAP M11 demands ("research… never guesses"). The judge's cask finding strengthens AGY.
Owner confirmation is still requested (one line each); the plan defaults to inclusion on approval.
DSH: npm only, never brew `dsh`. AGY: cask + standalone script layout.

**R10 — extraSearchRoots.** Official documented destinations, plus observed legacy roots only when
explicitly marked `observed-local` with a matrix limit (AGY `~/.gemini/bin` legacy 1.2.12 copy
qualifies and surfaces a real duplicate). Personal artifacts (Cline `~/.local/shims` shim, Tern
store, versioned runtime filenames) are never roots or fixtures.

**R11 — Contributor foundation.** `docs/CONTRIBUTING.md` + `docs/capability-matrix.md` +
`docs/catalogue-identities.md`. JSON-only extra-tool unit proof in F (Grok's design) AND an
end-to-end fifteenth-tool proof at the combined gate (MiniMax's design), reverted afterwards.
License: both recommend MIT; owner decides (OD-L). Recommend deciding at plan approval so the
guide can name it; LICENSE file added only on the owner's recorded choice. No public invitations.

**R12 — Acceptance culture.** Both proposals' evidence rules adopted: raw transcripts, SHA-256
protected-file manifests, orchestrator reruns everything (D-014), hosted seven gates at the exact
candidate SHA, CLI/app fact agreement from the same registry, native spot-check observed by the
orchestrator, personal installs never an acceptance target, unknown never fabricated.

## Owner decisions carried into the plan

See `briefs/M11-plan.md` §7 (OD-1…OD-10). Technical rulings R1–R12 are the judge's authority under
the lean protocol; the owner approves scope, names the implementer and reviewers, and answers the
listed decisions before dispatch.

## Owner authorizations (post-freeze log)

- **2026-11-12 — implementation authorization.** Owner: "if the plan is solid and you are sure of
  it go ahead and proceed to implementation". The orchestrator confirmed the plan's soundness and
  proceeded. Technical decisions OD-1…OD-10 are approved by delegation to orchestrator judgment,
  **except OD-7 (license)** which remains the owner's explicit open choice (MIT vs Apache-2.0;
  required before public contribution invitations, no later than M18). DSH (OD-2) and AGY (OD-3)
  inclusions rest on the verified primary-source evidence in this record.
- **2026-11-12 — implementer.** DeepSeek V4.1 Flash 1017 via OMP (`river` provider), max
  reasoning; sole product writer for M11 phases. M11-A dispatched on `milestone/m11-catalogue`
  at dispatch commit `197d632` (plan baseline `d98bf7b`).
- **2026-11-12 — independent reviewers.** The planning council models serve as the standing
  independent read-only reviewers for M11: **MiniMax M3.1-Flash/xhigh via mcode** and
  **Grok 4.7/high via grok CLI**. Mandatory for M11-B (mutation gate); recommended for D/E/F per
  the plan. Reviewers never edit; proposed fixes return to the implementer as revision briefs.
- **2026-11-12 — orchestration rule (binding).** All implementers and reviewers are summoned and
  managed through **Herdr panels + hc (Herdr Core) orchestration only — no delegate skills**.
  Agents run interactively in named Herdr terminals, watchable and steerable; reports arrive via
  `hc send t7x`.