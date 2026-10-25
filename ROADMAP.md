# Agent Lens — complete application delivery roadmap

Planning date: 2026-10-22.

Status: user-endorsed product direction; **M9 is technically accepted, user-UI-approved and branch-delivered** after implementation by DeepSeek V4.1 Flash Free through OpenCode at maximum effort. Approved feature commit `eb4f586` is pushed to `origin/milestone/m9-verified-inventory`. [Acceptance and delivery evidence](walkthroughs/M9-verified-installations.md). M10–M19 remain planned, not implemented or accepted. The assistant remains orchestrator/reviewer, not product implementer. This branch delivery does not merge into `main`, publish an app release, authorize later implementation or permit operations on personal installations.

Authority: [product scope](AGENT_LENS_SCOPE.md), [settled decisions](DECISIONS.md), and [delivered milestone status](briefs/README.md). This roadmap extends the sequence beyond M8; it does not rewrite historical briefs or acceptance evidence.

## 1. The finished product

A normal, installable native Mac app that answers:

- Which supported AI tools are installed, including known off-PATH installations?
- Which installation actually runs, and which copies or aliases explain a conflict?
- What are the local version, category, executable, package identity, and installation source?
- Is a newer version known, with source, observation time, and a truthful unknown state?
- Can this exact installation be updated or removed safely through its existing manager?

Users can search/filter, inspect diagnostics, copy/reveal paths, preview and confirm supported operations, read their output, and see the inventory change afterward. Standalone or ambiguous installs receive useful information, not unsafe deletion. The app can be installed from a DMG or Homebrew cask, opened from Finder/Spotlight, and updated through a signed app updater.

"Complete" means this original scoped product, including the later scope sections on retention and distribution. It does not mean every AI tool ever published or every possible installation layout.

## 2. Baseline and gaps

| Capability | Baseline | Remaining work |
|---|---|---|
| Login-shell environment and local scanner | M2–M5 accepted | Preserve Finder/Terminal parity as manager support grows |
| PATH winner, aliases, shadowed installations | M5 plus M9 identity-bound per-installation local versions accepted | Clearer aggregate conflict presentation and complete native workflows |
| Tool registry | Schema 2; current Codex/OpenCode/Grok metadata, declared packages, official links and bounded queries | Original named tool coverage in M14 |
| Source identification | Heuristics plus explicit read-only npm-global/Homebrew-formula ownership proof in M9 | uv, pip, Cargo, cask discovery and later capability slices |
| Update status | M6 accepted; Homebrew formulae only | npm, casks, Python, Cargo; ecosystem-specific comparison |
| Native app | M7 plus M9 metadata, explicit verification and per-installation diagnostics | Categories/Updates filters, overview, operation UI, preferences, accessibility finish |
| Copy/Reveal | M8 user-approved | Keyboard-only activation remains unverified |
| Update/Uninstall | Absent | Confirmed manager operations and post-operation state reconciliation |
| Everyday installation | Unsigned development bundle | Release artifact, signing/notarization, DMG/cask, app updater |
| Menu bar/scheduled checks | Absent | Minimal retained state, opt-in scheduling, badges |
| CLI | Working scanner, per-installation versions and explicit read-only verification | Bundled companion and opt-in PATH installation |
| Release automation | No .github workflow directory at assessment | CI, release checks, contributor workflow and license |

Historical acceptance is recorded in walkthroughs, not re-certified by this plan. The assessment smoke ran `swift run agent-lens scan --offline` successfully. It found npm Codex and standalone OpenCode/Grok; none is eligible for the existing Homebrew-only update checker. This is why npm is the first end-to-end management milestone.

## 3. Capability policy

Detection, latest-version lookup, update, and uninstall are separate capabilities. A source label is not permission to modify an installation.

| Installation | Discovery and update status | Update | Uninstall |
|---|---|---|---|
| npm global | Verify package, registry, manager and global prefix; registry dist-tag semantics | Confirmed operation on verified package/prefix | Confirmed manager uninstall |
| Homebrew formula | Extend existing verified formula behavior | Confirmed formula upgrade | Confirmed formula uninstall |
| Homebrew cask exposing a supported CLI | Verify cask ownership; truthful handling of latest/auto-updates metadata | Confirmed cask upgrade where supported | Confirmed cask uninstall; disclose whole-cask scope |
| uv tool | Verify tool environment/package ownership; Python registry semantics | Confirmed uv tool upgrade | Confirmed uv tool uninstall |
| pip-managed | Identify interpreter/environment and package where provable; compatible Python registry metadata | Informational in V1 | Informational in V1 |
| Cargo install | Verify package, installation root, registry/source and executable ownership | Confirmed supported registry-package operation preserving relevant install options | Confirmed manager uninstall |
| Standalone/native installer | Detect known locations and local version; latest unknown without a supported registry | Official instructions only | Install root and official uninstall instructions only |
| Unknown/ambiguous | Preserve observed facts; explain uncertainty | Disabled with reason | Disabled with reason |

The pip policy follows the existing V1 uninstall matrix, which authorizes uv tool operations, not arbitrary pip-environment mutation. Do not turn this into a system-Python package manager. Custom/private registries, VCS installs, pins, or unprovable build options stay explicitly unsupported where no safe adapter exists; do not substitute public-registry metadata or default installation options.

Supported managers may change dependencies as part of their documented operation. Disclose that scope; never claim only one filesystem entry can change. Do not install AI tools that were absent: fresh tool installation is not part of the original product commitment.

## 4. Execution sequence

Use the listed order by default. Each milestone produces working user-visible behavior, not an unused framework. Implementation remains one milestone/branch at a time under the existing brief protocol.

Milestones are product outcomes, not single worker prompts. Large milestones must be divided into sequential, independently verifiable phase briefs on the same milestone branch; the whole milestone passes only after combined acceptance. The phase breakdown and worker protocol are in §6. Do not dispatch M9–M19, or even all of M10, as one unbounded task.

### Before M9 — close the M8 measurement gap

Exercise keyboard-only focus and activation for both Copy/Reveal rows in the actual app, with any needed user-controlled accessibility preference. Record the environment and result. Do not silently change a system preference, re-label old evidence as a pass, or hold unrelated design work hostage to an unavailable manual check. Carry an unmeasured result as an explicit release blocker until measured.

Before the first worker dispatch, the orchestrator also verifies the configured worker route and current repository baseline, resolves the exact identities of the current catalogue entries, and checks availability of the first phase's toolchain and disposable acceptance environment. Research ambiguous future catalogue names now and track unresolved names against M14; do not guess package identities in M9 or silently drop entries. Missing Apple credentials do not block earlier phases, but an unavailable npm isolation environment blocks dispatch of the phase that requires it.

### M9 — verified installation details and detector contract

**Status:** A/B/C and corrected candidates technically accepted; final independent gate passed 329 Swift tests and 9 packaging checks plus actual CLI/native and isolated failure scenarios. The user approved the M9 UI, then separately authorized commit/push. Feature commit `eb4f586` is delivered to `origin/milestone/m9-verified-inventory`. [Whole-milestone contract](briefs/M9-verified-installations.md) and [acceptance/delivery record](walkthroughs/M9-verified-installations.md). No Update/Uninstall, main-branch integration or app release is implied.

**User result:** details distinguish observed source hints from verified installation ownership and show category/package identity when known.

- Extend the versioned JSON registry with categories, package identities by ecosystem, official information/uninstall URLs, and bounded version-query arguments/parsing where required by supported tools.
- Build on current diagnostics: installation identity includes entry, canonical target, manager identity, package, install root/prefix, and proof of ownership. Unverified fields remain unknown.
- Associate each installation with its own local version; do not reuse the PATH winner's version for a shadowed copy. Bound process concurrency and time/output.
- Verify npm ownership/global prefix and reuse Homebrew identity machinery first; subsequent managers extend the same facts as their vertical slices land.
- Keep detection and read-only scan usable without manager queries. Perform optional ownership verification explicitly; always reverify before a modifying operation.
- Migrate all current callers, fixtures and bundled registry together; no schema compatibility shim for obsolete bundled data.

**Depends on:** current accepted app.

**Acceptance:** two real fixture installs with different versions retain correct winner/shadow identities; same-target aliases remain one installation; heuristic-only, off-PATH, shimmed, relocated and missing cases are truthful. CLI and app agree on facts. Current three tools remain usable. Schema rejects invalid definitions.

### M10 — npm management end to end

**User result:** an npm-managed tool such as Codex has a real latest-version check, Update, and Uninstall, with confirmation and result output.

- Add npm metadata lookup using the verified package/registry identity, dist-tags, six-hour metadata caching, explicit refresh, and appropriate prerelease handling. Do not confuse npm "wanted" with "latest".
- Deliver command preview, explicit confirmation, one-at-a-time execution, bounded output, visible stdout/stderr and exit status, then rescan and show the delta.
- Execute the verified manager via executable plus argument array, never shell-interpolated user/path strings. The displayed preview describes the actual executable, arguments, prefix and effect.
- Verify the installation again after confirmation, immediately before launch. A changed target/manager/package/prefix invalidates the preview and requires a new confirmation.
- Define the shared operation lifecycle here with a real npm implementation; add other adapters only when their milestone lands. Keep mutation logic out of SwiftUI and share it through Core.
- Handle app/window closure and cancellation explicitly: request bounded process shutdown where needed, label outcome interrupted/uncertain, and rescan. Cancellation is not rollback. Never retry an install/uninstall automatically.
- Add CI now, before merging modifying operations: existing Swift and packaging checks, schema fixtures and Core UI-import prohibition. Address the documented default-TMPDIR fixture portability issue, not just a local environment override.

**Depends on:** M9.

**Acceptance:** in an explicitly disposable npm prefix and fixture registry, scan old package → check newer metadata → preview → Cancel changes nothing → confirm Update changes the expected package/version → rescan → confirm Uninstall removes the managed installation. Exercise process failure, offline/unsupported metadata, changed prefix/target after preview, concurrent clicks and interrupted execution. An unrelated prefix/package remains unchanged. Repeat the confirmation/result flow in the actual app with an isolated fixture install. No real user tool is modified as an acceptance shortcut.

### M11 — complete Homebrew management

**User result:** verified formula and supported cask installations can be checked, updated and uninstalled from the app.

- Reuse formula metadata/cache identity; add cask ownership and metadata support, not Cellar-shaped guesses for casks.
- Show formula versus cask, exact manager prefix and full package identity. Explain that cask removal may remove its companion app, not just the CLI.
- Respect manager restrictions/pins and report errors; do not force, unpin, relink, auto-remove unrelated packages or run broad cleanup. Never run `brew update` as a hidden update-check side effect.

**Depends on:** M10's working operation lifecycle.

**Acceptance:** isolated formula and cask scenarios exercise preview/cancel/update/uninstall, stale identity, pinned/unsupported versions, manager failure and accurate post-operation inventory. Prove a real Homebrew path in a disposable test environment in addition to deterministic fixtures; ordinary installed packages stay untouched. Cask scope is visible before confirmation.

### M12 — Python tool support

**User result:** uv-installed AI tools are correctly recognized and manageable; pip installs have accurate environment/package details and safe guidance.

- Discover verified uv tool environments and known pip-managed executables without recursively scanning arbitrary Python projects or treating every environment as a tool.
- Add Python-version ordering and registry metadata with interpreter compatibility, prerelease and index provenance rules. Do not apply the current semver parser to PEP 440 versions.
- Add uv tool Update/Uninstall through the existing confirmation/output/rescan flow. Keep system/shared/ambiguous pip environments informational.

**Depends on:** M10; execute after M11 in the default sequence.

**Acceptance:** disposable uv tool installs upgrade and uninstall through the app; different Python environments cannot be cross-targeted; uv and pip ownership are distinguished; Python version-order/compatibility and unavailable/custom-index cases remain truthful. Local inventory works offline.

### M13 — Cargo tool support

**User result:** supported Cargo-installed AI tools show package/root/source and offer safe manager-backed actions.

- Verify install manifest ownership and root, crates.io/custom source and relevant build options before offering an update.
- Add registry metadata and ecosystem-correct ordering, caching and unknown reasons. Preserve captured installation options; if they cannot be established, offer instructions rather than a default rebuild.
- Add targeted Update/Uninstall without changing unrelated crates or roots.

**Depends on:** M10; execute after M12 in the default sequence.

**Acceptance:** isolated Cargo roots demonstrate real update/removal; multiple binaries belonging to one package are disclosed; alternate roots, renamed packages, VCS/custom-registry installs and uncertain options cannot be silently mis-targeted.

### M14 — original tool catalogue and contributor path

**User result:** the app covers the originally named families, rather than only the current three executables.

Target catalogue: Codex, Claude Code, Gemini CLI, OpenCode, Hermes, Cline CLI, Aider, Goose, Kiro CLI, Qoder, DSH, OMP, AGY, plus existing Grok CLI.

- Verify the exact project, executable, package identity, official install paths and version behavior from primary project documentation before defining each detector. DSH/AGY and other ambiguous names are not permission to guess; unresolved identity is a named blocker, not a silently dropped tool.
- Add categories, official instructions and representative fixtures for each supported layout. Reuse detectors/adapters; do not add bespoke shell scripts per tool.
- Publish an explicit catalogue matrix: tool, category, tested install methods, latest-check support, update/removal support and known limits. Native installers remain informational under the settled standalone policy.
- Document registry contributions; CI validates each fixture and rejects invalid schema changes.

**Depends on:** M9–M13 capability contracts.

**Acceptance:** every target catalogue entry is identified and has a validated fixture plus measured version-query evidence where available. Record any unavailable real-install environment separately; do not label an unobserved method verified. A new tool using existing layouts can be contributed through registry/fixtures without changing scanner/UI source. All named entries must be resolved before calling this milestone complete.

### M15 — complete native application workflow

**User result:** Overview, AI Agents, AI Coding Tools, AI Harnesses, Updates, Diagnostics and focused Settings make the full inventory manageable.

- Add category/update filters, counts, package/source details and a conflict summary that leads into per-installation PATH evidence and versions.
- Finish operation progress/output/result presentation across managers; selection or filtering cannot retarget an existing confirmation. Unsupported actions explain why and offer official instructions.
- Preserve search, local-first launch, neutral unknowns, loading/empty/failure/retained-snapshot states and Copy/Reveal semantics.
- Add keyboard navigation/shortcuts, native menus, VoiceOver labels and spoken interaction checks, large text/narrow-window behavior and light/dark verification. Settings only govern actual delivered features.

**Depends on:** M14.

**Acceptance:** actual-app journeys cover find/filter → inspect competing copies → confirm or cancel an eligible operation → review output → observe new winner/version after rescan. Exercise no tools installed, offline, failed rescan, missing manager, permission denial, long paths, keyboard-only and VoiceOver. No destructive acceptance touches personal installations.

### M16 — menu bar and opt-in refresh

**User result:** a lightweight menu-bar item surfaces known updates/conflicts and opens the main window; useful inventory appears immediately on relaunch.

- Persist only minimal inventory/update-display facts, with schema and observation times; never raw captured environments, credentials or terminal output. Cached facts are explicitly stale/read-only until verified; cached ownership cannot authorize an operation.
- Rescan locally on launch; refresh stale session environment on activation as appropriate. No automatic package changes.
- Add optional periodic update checks while the app is running, off by default, with a focused preference and visible last-check status. Closing the window/menu-bar lifetime must be explicit. Do not introduce a daemon or login-item installation silently.
- Show truthful conflict/update badges. Preserve explicit offline behavior and manual Check/Refresh.

**Depends on:** M15.

**Acceptance:** quit/relaunch displays dated cached facts then replaces them with fresh results; changed filesystem identity blocks stale actions. Offline and corrupted cache remain usable; opt-out creates no scheduled probe. Sleep/wake and repeated activation do not create overlapping work. Measure cached first render against the scope's sub-300 ms target and record hardware/build/method, not a guessed timing.

### M17 — bundled CLI and opt-in installation

**User result:** the distributed app includes the same-engine `agent-lens` scanner and can optionally make it available from Terminal.

- Package the CLI and required resources with the app; existing scan/update flags remain documented and supported.
- Offer explicit opt-in linking into an eligible user-writable directory already on the resolved PATH. Show the exact destination; do not silently overwrite an existing command, edit shell startup files or request broad elevated privileges.
- Explain how to remove only the app-owned link, and how moving/removing the app affects it. No new mutation CLI commands are required by the original scope.

**Depends on:** M15; execute after M16 by default.

**Acceptance:** install from a relocated app bundle → run CLI from Terminal → compare inventory with the app → remove the owned link. Existing files/symlinks remain untouched, and missing eligible destinations produce actionable guidance. CLI resources resolve without repository/build-tree access.

### M18 — release candidate and everyday installation

**User result:** a release-built app can be copied to Applications and used without the source checkout, developer scratch roots or special environment variables.

- Run clean CI builds/tests/packaging, relocation and absence-of-repo checks; retain raw results. Fix reproducible compiler/linker/package warnings affecting the release rather than masking them.
- Exercise supported macOS versions starting at the declared minimum (currently macOS 14) and each distributed architecture. Distribute only architectures actually built and exercised; do not claim Intel compatibility from an arm64 run.
- Produce release packaging, user instructions, screenshots, troubleshooting, privacy/safety documentation and a contributor guide.
- Select and add an actual OSS license (MIT or Apache-2.0 per scope; owner decision required before publication), license notices and dependency inventory if dependencies were added.
- Run the complete catalogue/capability matrix, native accessibility and operation-safety checks. Resolve any remaining M8 keyboard measurement gap before release acceptance.

**Depends on:** M9–M17 and their accepted evidence.

**Acceptance:** clean test account, no source/build path access: copy app to Applications → launch via Finder/Spotlight → scan and diagnose → exercise a disposable supported operation → quit/relaunch → use optional CLI. All advertised capabilities have recorded results, unsupported cases remain explicit, and the release checklist has no hidden unchecked gates.

### M19 — signed public distribution and app self-updates

**User result:** download a DMG or use the published Homebrew cask, open normally under Gatekeeper, and receive verified updates to Agent Lens itself.

- Obtain owner-approved Apple Developer membership/signing identity when preparing this milestone; configure protected release credentials. No sandbox, minimal entitlements, hardened runtime.
- Automate Developer ID signing, notarization and ticket stapling; publish checksums, release notes and a DMG plus the planned Homebrew cask.
- Integrate a maintained signed app updater (for example Sparkle) with verified update signatures and a hosted static feed/artifacts. This requires a new dependency decision and revising earlier zero-external-dependency brief constraints for the app if adopted; preserve a UI-free Core. No accounts or application backend are required.
- Establish updater/cask ownership behavior so they do not fight over the same installed app. Confirm channel behavior in the release brief rather than enabling competing updates by default.
- Keep tool updates separate from Agent Lens app updates; neither may silently perform the other.

**Depends on:** M18; Apple credentials, selected license and publication destinations are external prerequisites.

**Acceptance:** quarantined download on a clean supported Mac passes signature, notarization and stapling checks and launches without disabling Gatekeeper. Both DMG and actual published cask installation work. Upgrade from an older signed app to a newer signed app succeeds; tampered update metadata/artifact is rejected and the current app remains usable. Verify the cask-managed update policy and recovery from interrupted download. No release-complete claim without observed public-channel behavior.

## 5. Architecture and safety invariants

- Keep `AgentLensCore` free of SwiftUI/AppKit. Discovery, verified installation facts, version comparison and manager operations live in Core; `AgentLensAppSupport` owns presentation state; app code owns native UI/clipboard/Finder effects. CLI consumes Core rather than duplicating logic.
- Reuse the existing environment provider, bounded process runner, diagnostics identities and cache patterns where their contracts fit. A modifying operation needs its own lifecycle/time limits, not the short read-only probe timeout blindly reused.
- Provide a small operation interface: prepare a preview bound to verified identity, then execute that confirmed plan and return a typed outcome. Manager-specific details remain behind real adapters. Do not build a plugin framework, universal task engine or speculative adapter hierarchy.
- Never treat a heuristic source, cached snapshot, display name or executable basename as package ownership. Revalidation refusal is a user-visible result, not a fallback to another install.
- A manager operation may affect aliases, multiple binaries or dependencies. Preview package-level scope. Removal of a PATH winner may expose a previously shadowed installation; show that change, do not claim the tool vanished.
- One modifying operation at a time. No update-all, removal-all, automatic retries, shell interpolation, implicit `sudo`, hidden manager refresh or automatic cleanup.
- Report denied permissions, manager locks and interruptions honestly. Do not claim atomicity/rollback or that identity verification eliminates every filesystem race. Never delete configuration/caches or edit PATH startup files as part of tool management.
- Version ordering follows the ecosystem; an unsupported format or unknown registry stays unknown. The update count includes only proven available updates.

## 6. Orchestration, phase briefs and acceptance

### 6.1 Ownership

| Role | Owns | Must not do |
|---|---|---|
| Orchestrator (this assistant) | Master plan, source/API research, phase design, worker briefs, dispatch, independent verification, technical approval and acceptance/status records | Implement product code/tests, quietly patch a worker's defect, or approve from the worker's success claim |
| Implementer (external worker) | Product code, behavioral tests and in-scope user documentation; raw build/test/runtime evidence; fixes requested through revision briefs | Grade its own work, expand scope/allow-list, alter acceptance requirements, rewrite historical evidence or publish |
| Independent reviewer | Read-only spec/safety/maintainability review of the pinned candidate and evidence | Edit the candidate, inherit the worker's self-justification, or replace the orchestrator's acceptance run |
| User | Product/scope tradeoffs, visual acceptance where relevant, provider/CLI choice, expenses, credentials and publication authorization | Be treated as having approved unmeasured technical gates merely by liking the UI |

This restates D-013/D-014 and scope §29; it does not supersede them. Planning/review/status documentation is orchestrator work. Production fixes, regression tests, fixture changes and implementation documentation go back to the implementer, even when the fix appears small.

### 6.2 Master milestones versus worker-sized phases

Each phase has its own brief and acceptance IDs, but no separate agent branch. Proposed initial decomposition:

| Milestone | Sequential phase briefs and independently observable outcomes |
|---|---|
| M9 | A: registry/category/package metadata displayed in CLI/details, explicitly unverified; B: explicit read-only npm/Homebrew ownership verification with visible verified/unknown results; C: correct per-installation local versions and winner/alias/shadow evidence |
| M10 | A: existing checks run in clean CI and default-TMPDIR portability is fixed; B: verified npm latest-version lookup/cache displayed in CLI/app; C: confirmed npm Update with output and post-operation delta; D: confirmed npm Uninstall plus interruption/closure and combined safety acceptance |
| M11 | A: formula Update/Uninstall through the existing flow; B: cask ownership/status with whole-cask disclosure; C: cask actions and combined Homebrew acceptance |
| M12 | A: uv/pip discovery and Python-compatible update status; B: uv Update/Uninstall and cross-environment safety acceptance |
| M13 | A: Cargo identity/source/options and latest status; B: eligible Cargo operations with alternate-root and uncertain-option safety acceptance |
| M14 | Small named catalogue batches, each with completed detector definitions/fixtures/documented capabilities; final complete-catalogue and contributor-path gate |
| M15 | A: overview/category/update navigation; B: complete conflict and operation-result journeys; C: keyboard/VoiceOver/layout/native-menu acceptance |
| M16 | A: dated cached launch and refresh; B: menu-bar lifetime/badges; C: opt-in scheduling, sleep/wake and performance acceptance |
| M17 | A: relocatable bundled CLI; B: opt-in link installation/removal with collision protection |
| M18 | A: clean build/compatibility/relocation matrix; B: user/contributor/license packaging and clean-account release-candidate acceptance |
| M19 | A: signed/notarized artifacts and release automation; B: signed app updater and channel policy; C: final-candidate regression, public DMG/cask installation and upgrade/tamper acceptance |

The orchestrator refines these cuts against the then-current code before writing each brief, without omitting a milestone requirement. A phase must deliver the stated observable result, not leave a disconnected interface or placeholder for the next worker. Later phase briefs are written after accepting their dependencies, not frozen speculatively today.

Early phase acceptance does not accept a partial milestone. At milestone close, rerun combined behavior against the final candidate. M19 changes the app after M18: rerun the applicable M18 regression/compatibility gates on the final signed release candidate, not an earlier binary.

### 6.3 Mandatory brief contents

Every dispatched brief must be self-contained and ready to execute. It must contain actual paths/commands/contracts, not directions to invent the acceptance test or read the whole master plan.

| Field | Required contents |
|---|---|
| Identity and baseline | Milestone/phase ID, brief revision, pinned base commit, branch, recorded pre-existing changes, accepted prerequisite evidence, toolchain and worker route |
| Goal and exclusions | One user-visible outcome, complete requirement IDs for the phase, explicit non-goals and protected behavior |
| Context packet | Relevant settled-decision excerpts, precise files/symbols and existing patterns, verified manager/project documentation where needed; only the context required for this phase |
| File authority | Explicit modify/add allow-list, `DO NOT TOUCH` list, generated-output/scratch locations, and no-overwrite/no-publish rules |
| Behavioral/interface contract | Inputs/outputs, identity/ownership rules, state transitions, cancellation/errors, manager/version policy and UI behavior; fix shared interface names and invariants before dependent work |
| Migration contract | Every affected caller, schema, fixture, resource and documentation change; clean cutover without obsolete aliases/shims |
| Acceptance matrix | Stable IDs such as `M10-C-AC01`; each maps a requirement to setup, exact command or native interaction, expected observable state/output and required evidence |
| Safety envelope | Explicit disposable roots/manager environment, allowed effects, personal installs/caches/configuration that must remain untouched, restoration and process-cleanup steps |
| Verification commands | Baseline and final Swift/build/packaging gates as applicable, targeted behavioral regressions, real runtime/native smoke; exact environment/scratch command shapes and exit expectations |
| Evidence and return format | Raw command/stdout/stderr/exit records, runtime receipts, artifact paths, candidate identity, touched-file list, requirement-to-evidence table, failures/limitations and requested scope changes |
| Stop conditions | Missing prerequisite, unexpected file change, need outside allow-list, unavailable isolation, ambiguous identity, dependency/privilege/purchase/publication change; report facts and wait for a revised brief rather than improvising |
| Done condition | All phase requirements implemented, deterministic tests and runtime gates observed, no placeholders, no unresolved blocking findings; worker submits a candidate, orchestrator decides acceptance |

Do not log credentials or captured environment secrets as evidence. Set up command capture to avoid secret-bearing arguments/environment dumps. Preserve normal raw output; if a secret is emitted accidentally, restrict the original, produce an explicitly redacted copy and report the incident rather than silently rewriting a transcript.

Fixture-only proof is not real-manager proof. Native-host evidence is separate from actual-product evidence. A missing runtime gate is blocked/unverified, never inferred to pass. Baseline failures outside the brief are reported and triaged by the orchestrator; they do not authorize unrelated cleanup or tests weakened to pass.

### 6.4 Worker dispatch and candidate handoff

1. **Prepare.** The orchestrator inspects the accepted baseline, researches relevant manager semantics, writes/reviews the bounded brief, and ensures its acceptance setup is available before dispatch. A material scope or settled-decision change goes to the user; ordinary technical brief preparation stays with the orchestrator.
2. **Verify route.** Use the user-selected different model/provider/CLI. Record configured route and actual CLI/version/reported model, verify authentication with a harmless capability check, and ensure repository/filesystem access. Distinguish configured identity from provider identity actually attested by the tool. Do not silently fall back to another route, expose credentials or enroll a new paid service.
3. **Dispatch once.** Send only the phase brief and referenced context packet through that external CLI. One product writer owns the milestone branch; no concurrent changes by the orchestrator or reviewer. A restarted/replacement worker receives the current candidate and prior acceptance/revision facts, not a new divergent branch.
4. **Implement.** Worker makes the authorized change and exercises the brief's baseline/final gates. For changed behavior, keep a meaningful failing-before/passing-after regression where practical; no tests for source wording or copied wiring. Worker updates in-scope usage documentation and returns a requirement-to-evidence table.
5. **Freeze candidate.** Worker stops edits and identifies the candidate commit plus any declared uncommitted/generated changes; an uncommitted handoff must include content hashes/snapshot of all candidate files. Acceptance commands build that exact candidate with fresh scratch; a commit label alone is insufficient if files have drifted.
6. **Review and exercise.** The orchestrator checks scope, code and changed behavior, independently runs acceptance, and commissions read-only independent review for high-risk ownership, mutation and signing work. Review packets contain the pinned artifact, requirement/acceptance contract and raw results, not persuasive worker rationale. Review both spec coverage and safety/maintainability.
7. **Revise or accept.** Findings return to the implementer in a numbered revision brief: affected requirement, reproducible evidence, required correction, file authority and rerun gates. The orchestrator does not patch the product. Any candidate change invalidates approval for the affected behavior; rerun affected gates and final combined gates on the replacement candidate, and re-review safety-relevant changes.
8. **Close out.** The orchestrator records candidate identity, requirement results, raw evidence and technical decision in the walkthrough/status log. User visual acceptance and Git delivery/publication permission are separate. After acceptance and delivery authorization, the orchestrator integrates/delivers the accepted artifact under the existing branch protocol. Do not mark a different binary/commit delivered.

### 6.5 Approval and stop rules

- **READY:** all prerequisites and acceptance environments exist; a complete brief and known route are ready for dispatch.
- **IN PROGRESS:** worker is implementing the current brief revision.
- **IN REVIEW:** candidate is frozen; independent checks are running. No next phase starts yet.
- **CHANGES REQUIRED:** failed criterion or blocking finding has a revision brief assigned back to the implementer.
- **BLOCKED:** missing prerequisite or unavailable gate is named with what was tried and the exact next action/owner. No pass claim and no silent scope reduction.
- **TECHNICALLY ACCEPTED:** every required criterion passed on the identified candidate and blocking review findings are closed. A worker's PASS is not this state.
- **DELIVERED:** the technically accepted candidate is integrated/published only to the destinations actually authorized, with required user visual approval recorded separately.

Do not start the next phase until the current phase is technically accepted; do not start the next milestone until the current milestone's combined gate passes and its accepted integration baseline is recorded. Technical acceptance is not authorization to purchase, push, publish, alter system preferences or perform operations on personal installations.

M9 used the user-selected `opencode/deepseek-v4.1-flash-free#max` route and separately accepted bounded A/B/C briefs. That authorization does not dispatch M10. Prepare its first bounded brief and verify its acceptance environment before requesting/using further implementation authorization.

## 7. Requirement traceability and finish line

| Scope requirement | Existing or planned delivery |
|---|---|
| §2 tool families and manager sources | M9, M12–M14 |
| §3 inventory/category/package/version facts | Existing scanner + M9, M14–M15 |
| §4 details and path actions | M7–M8 + M9, M15 |
| §5 manager-backed Update | M10–M13 |
| §6/§22 safe Uninstall and post-operation delta | M10–M13; standalone/pip guidance M14–M15 |
| §7 search/filter/keyboard | M7 + M15 |
| §8/§25 duplicate diagnostics as primary value | M5/M7 + M9, M15–M16 |
| §9 native dashboard | M15 |
| §10–§13/§27 native stack, module separation, declarative detectors | Preserve existing design; M9–M14, CI in M10 |
| §14 complete operations and polish phases | M10–M19 |
| §15–§16 non-goals, privacy and conservative behavior | Capability policy and invariants throughout |
| §17 OSS/contribution model | M14, M18–M19 |
| §18 future ideas | Not silently included: history, advanced health checks and marketplace-style expansion remain future |
| §20 environment fidelity and optional bundled CLI | Preserve M2; M9–M13, M16–M17 |
| §21 complete scoped update strategies | M10–M13 |
| §23 signed distribution and app updater | M18–M19 |
| §24 menu bar, cached launch, opt-in checks, conflict badges | M16 |
| §28–§29 verification, bounded briefs and independent acceptance | Gates for every milestone |

The diagnostic app already works. M10 is the first usable manager-backed control-center increment; M15 completes the main application workflows; M19 is the full scoped public-release finish line. None of those intermediate points substitutes for the full delivery requested here.

Excluded throughout: MCP/skills/configuration management, arbitrary binaries, generic Mac apps, cleaning, chat, accounts, cloud sync, telemetry, security scanning, plugin marketplace, Windows/Linux, deep standalone deletion and automatic broad cleanup. Inspecting a cask that owns a supported AI CLI does not turn this into a generic Mac app manager.

Immediate next preparation: M10-A's clean-CI/default-TMPDIR portability brief and acceptance setup, with the remaining M8 native keyboard measurement still tracked as a release blocker. M10 implementation has not started; signed distribution remains M18–M19 work.
