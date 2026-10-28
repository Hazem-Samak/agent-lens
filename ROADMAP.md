# Agent Lens — value-first application delivery roadmap

Planning revision: 2026-10-28. Original plan: 2026-10-22.

This revision supersedes the previous **future execution order**, not completed work or acceptance evidence. M0–M9 remain delivered as recorded; M10-A and M10-B remain technically accepted only on `codex/m10-npm-management`. The accepted M10-B implementation is `72ffb1e`. M10-C is next, M10 as a whole is not accepted, and no PR, `main` merge, or public release has occurred. See [M10-B acceptance](walkthroughs/M10-B-acceptance.md).

Authority: [product scope](AGENT_LENS_SCOPE.md), [settled decisions](DECISIONS.md), and [milestone status](briefs/README.md). Historical briefs and walkthroughs are immutable evidence; this file is the living plan.

## 1. Sanity-check conclusion

The original plan had the right architecture and safety rules, but its product order was not optimal. It postponed the original tool catalogue until after npm, Homebrew, Python, and Cargo management, and postponed the complete native workflow until after all of them. That conflicted with the product's diagnostic-first value and delayed visible, user-testable progress.

The revised order therefore delivers:

1. One safe management vertical slice: npm.
2. The complete original detection catalogue.
3. The complete native diagnostic workflow and accessibility.
4. The remaining manager adapters through that proven workflow.
5. Retention, companion CLI, release engineering, and signed distribution.

No council approval or implementer was used for this planning revision. Future implementation keeps independent technical acceptance; trust in an implementer is not a verification method.

## 2. Product finish line

Agent Lens is complete when a normal, installable native Mac app can:

- Discover the originally named AI agents, coding tools, and harnesses, including supported off-PATH installations.
- Explain which copy PATH runs, aliases, shadowed copies, versions, package identity, installation source, and uncertainty.
- Report supported latest-version checks with source and observation time; unknown remains neutral and truthful.
- Preview, confirm, execute, and reconcile supported manager-backed Update and Uninstall operations.
- Provide search, categories, Updates, Diagnostics, Settings, Copy/Reveal, accessible native interaction, and understandable output.
- Offer dated cached launch, an optional menu-bar presence and opt-in checks, plus an optional bundled CLI link.
- Install through signed/notarized DMG and Homebrew cask channels and update itself through a verified app updater.

The app diagnoses first and manages second. It is not a generic package manager, Mac cleaner, security scanner, chat product, configuration editor, or backend service. Configuration/caches are not removed, arbitrary pip environments are not mutated, and standalone/ambiguous installations remain informational.

## 3. Current baseline and checkpoints

| Checkpoint | Meaning | Status |
|---|---|---|
| M0–M9 | Discovery, PATH diagnostics, native foundation, path actions, verified details | Delivered as recorded; M8 keyboard check remains open |
| M10-A/B | Clean CI and verified npm latest metadata | Accepted on the M10 feature branch |
| M10-C/D | npm Update, Uninstall, and combined safety acceptance | Next; not started by this plan |
| M12 | Original catalogue plus complete native diagnostic workflow | Revised early-value checkpoint |
| M15 | All scoped manager capabilities delivered | Feature capability checkpoint |
| M17 | Feature-complete unsigned app with retention and companion CLI | Release-engineering entry point |
| M18 | Clean release candidate | Requires every advertised capability measured |
| M19 | Signed public distribution and app self-update | Full scoped finish line |

An optional public **diagnostic beta** may be considered after M12, but only as a separate owner decision with release scope and signing reviewed then. It is not assumed by this roadmap and does not replace M19.

## 4. Revised execution sequence

Work one milestone and one phase at a time. Do not start a dependent milestone until the previous milestone's combined acceptance is recorded.

### M10 — npm management end to end

**Status:** A and B technically accepted on the feature branch. **M10-C is the immediate next phase.**

**User result:** an ownership-verified npm tool such as Codex can show a real latest-version result, then Update or Uninstall through a visible confirmation and result workflow.

- **M10-C — Update:** research and pin exact npm arguments and target-version semantics; preview actual executable/arguments/package/prefix/effect; Cancel changes nothing; revalidate identity immediately before execution; run one operation at a time; capture bounded stdout/stderr/exit status; rescan and show the inventory and PATH delta.
- **M10-D — Uninstall and combined gate:** confirmed npm removal, interruption/window-closure handling, truthful uncertain outcomes, and combined Update/Uninstall acceptance. Cancellation is not rollback; never retry a mutation automatically.
- Use executable plus argument arrays, never shell-interpolated path/user strings. A changed target, manager, package, registry, or prefix invalidates the preview.
- Keep mutation logic in Core, presentation state in AppSupport, and native interaction in the app. Do not build speculative adapters for later managers.

**Acceptance:** in a disposable npm prefix and controlled registry environment, prove old package → newer metadata → preview/Cancel unchanged → confirmed Update → correct rescan delta → confirmed Uninstall. Exercise stale identity, concurrent clicks, manager failure, offline/unsupported metadata, interruption, and unrelated package/prefix sentinels. Repeat the workflow in the actual app. No personal installation is an acceptance target.

### M11 — original catalogue and contributor foundation

**User result:** the app detects the originally named families instead of only Codex, OpenCode, and Grok.

Target catalogue: Codex, Claude Code, Gemini CLI, OpenCode, Hermes, Cline CLI, Aider, Goose, Kiro CLI, Qoder, DSH, OMP, AGY, and Grok CLI.

- Research each exact project, executable, package identity, official installation layout, and version behavior from primary documentation before adding a detector. Ambiguous names such as DSH/AGY are named research blockers, never guesses.
- Add categories, official links, representative fixtures, and measured version-query evidence in small data-driven batches. Do not add bespoke shell scripts per tool.
- Detection may be delivered before a manager's mutation adapter. Such entries must remain informational or disabled with a specific reason; declared metadata is not ownership proof.
- Publish a capability matrix: tool, category, tested layouts, latest-check support, Update/Uninstall support, and known limits.
- Document registry/fixture contributions. Select the OSS license before inviting public contributions and no later than M18; the owner must choose MIT or Apache-2.0.

**Depends on:** M10 combined acceptance.

**Acceptance:** every named entry is resolved and has a validated fixture plus measured version behavior where available. CLI/app facts agree. A new tool using an existing layout can be contributed through registry/fixtures without scanner or UI source changes. Unobserved real layouts are not labeled verified.

### M12 — complete native diagnostic and operation workflow

**User result:** Overview, AI Agents, AI Coding Tools, AI Harnesses, Updates, Diagnostics, and focused Settings make the complete catalogue understandable and manageable.

- Add category/update filters, counts, package/source details, and a conflict summary that leads to per-installation PATH evidence and versions.
- Complete the existing npm confirmation/progress/output/result journey. Future manager capabilities use the same capability-driven UI and remain explicitly unavailable until their adapters land.
- Preserve local-first launch, search, neutral unknowns, loading/empty/failure states, and Copy/Reveal behavior. Selection or filtering cannot retarget an existing confirmation.
- Finish native menus, keyboard navigation/shortcuts, VoiceOver labels and spoken checks, large text, narrow windows, and light/dark appearance. Settings only control delivered features.
- **Close the outstanding M8 keyboard-only Copy/Reveal measurement here.** It is a required M12 gate, not something to defer to M18.

**Depends on:** M11.

**Acceptance:** actual-app journeys cover find/filter → inspect competing copies → confirm or cancel an eligible operation → review output → observe the post-rescan winner/version. Exercise empty inventory, offline, failed rescan, missing manager, permission denial, long paths, keyboard-only, and VoiceOver. No destructive acceptance touches personal installations.

### M13 — complete Homebrew management

**User result:** verified formula and supported cask installations can be checked, updated, and uninstalled through the finished native workflow.

- Reuse formula identity/metadata and add cask ownership and appropriate metadata; do not apply Cellar-shaped assumptions to casks.
- Show formula versus cask, exact manager prefix, and full package identity. Disclose that cask removal may remove a companion app, not only a CLI.
- Respect pins and manager restrictions. Never force, unpin, relink, perform broad cleanup, or run hidden `brew update`.

**Depends on:** M12.

**Acceptance:** disposable formula and cask scenarios cover preview/Cancel, Update, Uninstall, stale identity, pins/unsupported versions, manager failure, and accurate post-operation inventory. Include a real Homebrew path in a disposable environment and visible whole-cask disclosure.

### M14 — Python tool support

**User result:** uv-installed tools are recognized and manageable; supported pip installations show accurate environment/package details and safe guidance.

- Discover verified uv tool environments and known pip-managed executables without recursively scanning arbitrary Python projects.
- Implement PEP 440-compatible ordering and registry metadata with interpreter compatibility, prerelease, and index-provenance rules. Do not reuse semver blindly.
- Add uv Update/Uninstall through the existing workflow. Keep system/shared/ambiguous pip environments informational.

**Depends on:** M13.

**Acceptance:** disposable uv installs upgrade and uninstall through the app; environments cannot be cross-targeted; uv/pip ownership is distinguished; custom/unavailable indexes and unsupported compatibility remain truthful; local inventory works offline.

### M15 — Cargo tool support

**User result:** supported Cargo-installed tools show package/root/source and offer safe manager-backed actions.

- Verify install-manifest ownership, root, registry/source, executable ownership, and relevant build options before offering Update.
- Add registry metadata and ecosystem-correct ordering, caching, and unknown reasons. Preserve captured install options or provide instructions instead of a default rebuild.
- Add targeted Update/Uninstall without changing unrelated crates or roots.

**Depends on:** M14.

**Acceptance:** isolated Cargo roots demonstrate real operations; multiple binaries from one package are disclosed; alternate roots, renamed packages, VCS/custom registries, and uncertain options cannot be silently mis-targeted.

### M16 — cached launch, menu bar, and opt-in refresh

**User result:** useful dated inventory appears immediately on relaunch, and a lightweight menu-bar item surfaces known updates/conflicts.

- Persist only minimal display facts with schema and observation times—never raw environments, credentials, ownership authority, or terminal output. Cached facts are stale/read-only until verified.
- Rescan locally on launch and refresh stale session environment on activation as appropriate. No automatic package changes.
- Add optional periodic update checks while running, off by default, with visible last-check status and explicit window/menu-bar lifetime. No silent daemon or login item.
- Preserve offline/manual behavior and prevent overlapping work after repeated activation or sleep/wake.

**Depends on:** M15.

**Acceptance:** quit/relaunch replaces dated cached facts with fresh results; changed identity blocks stale actions; corrupted/offline cache remains usable; opt-out creates no scheduled probe; cached first render is measured against the sub-300 ms target with hardware/build/method recorded.

### M17 — bundled CLI and opt-in installation

**User result:** the app includes the same-engine `agent-lens` CLI and can optionally expose it to Terminal.

- Bundle the CLI and resources so they resolve without repository/build-tree access.
- Offer explicit opt-in linking into an eligible user-writable directory already on the resolved PATH. Show the destination; never silently overwrite a command, edit shell startup files, or request broad elevation.
- Explain removal of only the app-owned link and the effect of moving/removing the app.

**Depends on:** M16.

**Acceptance:** relocated app → Terminal CLI → inventory matches app → owned link removed. Existing files/symlinks remain untouched and missing destinations produce actionable guidance.

### M18 — release candidate and everyday installation

**User result:** a release-built app can be copied to Applications and used without the source checkout or special environment variables.

- Run clean CI, relocation, absence-of-repository, packaging, operation-safety, catalogue/capability, and accessibility checks. Fix release-affecting warnings rather than masking them.
- Exercise macOS 14 and other supported versions/architectures actually distributed. Do not claim Intel support from an arm64-only run.
- Produce user instructions, screenshots, troubleshooting, privacy/safety documentation, contributor guide, selected license, notices, and dependency inventory if applicable.
- Rerun the complete native workflow, including the M8/M12 keyboard requirement, on the release candidate.

**Depends on:** M9–M17 accepted evidence.

**Acceptance:** on a clean test account without source/build-path access: copy to Applications → Finder/Spotlight launch → scan/diagnose → disposable supported operation → quit/relaunch → optional CLI. Every advertised capability has evidence and no hidden unchecked gate remains.

### M19 — signed public distribution and app self-updates

**User result:** download a DMG or install the published cask, open normally under Gatekeeper, and receive verified Agent Lens updates.

- Obtain owner-approved Apple Developer membership/signing identity and protected release credentials. Use hardened runtime, minimal entitlements, and no App Sandbox.
- Automate Developer ID signing, notarization, ticket stapling, checksums, release notes, DMG, and the actual published Homebrew cask.
- Integrate a maintained signed updater only after an explicit dependency decision. Verify update signatures and host a static feed/artifacts; Core remains UI-free.
- Define cask-versus-updater ownership so channels do not fight. Agent Lens updates and managed-tool updates remain separate.

**Depends on:** M18 plus credentials, license, and publication destinations.

**Acceptance:** quarantined clean-Mac installation passes signature/notarization/stapling and launches without disabling Gatekeeper; both public channels work; signed upgrade succeeds; tampered metadata/artifacts are rejected; interrupted updates recover. Rerun applicable M18 regression gates on the final signed candidate.

## 5. Lean operating protocol for a non-coder and agents

The user approves product tradeoffs, UI, expenses, credentials, publication, and implementation authorization. The user is not expected to judge source code.

1. **Plan without ceremony.** The orchestrator owns research, this roadmap, phase briefs, and status. Plan changes do not require a council or an implementer.
2. **Brief one observable phase.** Pin the base commit, branch, worker route, goal/non-goals, exact files, protected files, contracts, safety envelope, acceptance matrix, commands, evidence format, and stop conditions. Later briefs are written only after dependencies are accepted.
3. **Use one milestone branch and one product writer.** Phases are sequential on that branch. Reviewers never edit; no two agents write the same candidate concurrently.
4. **Match review to risk.** Independent read-only review is mandatory for ownership/mutation, signing/updater, and other high-risk contracts. Routine low-risk phases need orchestrator acceptance, not a standing council.
5. **Freeze the candidate.** Identify the exact commit and any declared uncommitted files. Do not accept a label while the content has drifted.
6. **Verify independently.** The orchestrator reviews scope and reruns deterministic tests plus required real-runtime/native checks in clean, disposable environments. An implementer's PASS is evidence to inspect, never acceptance itself.
7. **Return defects to the implementer.** A revision brief names the failed requirement, reproduction, correction, file authority, and rerun gates. Changed safety behavior requires re-review and affected/full regression runs.
8. **Close with evidence.** Record candidate identity, requirement-to-evidence results, limitations, and technical decision. UI approval, Git delivery, and publication remain separate owner authorizations.
9. **Stop instead of improvising.** Missing isolation, ambiguous identity, scope/dependency changes, unexpected file edits, credentials, privileges, or personal-installation effects block dispatch or acceptance.

## 6. Architecture and safety invariants

- `AgentLensCore` never imports SwiftUI/AppKit. Discovery, ownership, version comparison, and operations live in Core; AppSupport owns presentation state; app code owns native effects; CLI consumes Core.
- Detectors remain versioned JSON with strict fixtures. A source hint, display name, basename, or cached fact is never ownership proof.
- Login-shell environment resolution remains mandatory for discovery and execution.
- Local inventory works offline. Latest is optional and tri-state; unknown never becomes up-to-date and never inflates update counts.
- Prepare a preview bound to verified identity, then revalidate and execute that exact confirmed plan. One mutation at a time; no update-all/remove-all.
- No shell interpolation, implicit `sudo`, hidden manager refresh, automatic retry, claimed rollback/atomicity, broad cleanup, or deletion of configuration/caches.
- Package-level effects, aliases, dependencies, and PATH-winner changes are disclosed honestly. Unsupported/custom/ambiguous cases remain informational.
- Acceptance fixtures and scratch roots must be disposable and authorized. Never mutate personal installations as a shortcut.

## 7. Owner gates

- **Before M10-C dispatch:** approve the bounded brief, implementer/route, and isolated acceptance setup.
- **Before public contribution invitations:** choose MIT or Apache-2.0.
- **After M12, optional:** decide whether a separately scoped diagnostic beta is worthwhile.
- **Before M19:** approve Apple Developer expense/credentials, updater dependency, signing/release automation, publication destinations, and cask/updater channel policy.

## 8. Immediate next action

Prepare and preflight the bounded **M10-C npm Update** brief on the accepted M10-B baseline. Do not start M11 until M10-D and the combined M10 gate pass. Do not begin product implementation merely because this roadmap revision exists.
