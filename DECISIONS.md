# DECISIONS.md — Agent Lens

Settled decisions, with rationale.

**Every agent must read this file before proposing changes.** It exists so that settled questions are not re-litigated in every session.

---

## How to use this file

- Every entry below is **settled**. Do not re-open one without a stated reason and the builder's explicit approval.
- To change a settled decision, **add a new entry** that supersedes it. Never edit or delete the original — the history is the point.
- To add an entry, append at the bottom with the next free ID.
- **Source** points to the section of `AGENT_LENS_SCOPE.md` that justifies the decision. If you disagree with a decision, read the source before arguing.
- Status values: `settled` · `superseded by D-0xx` · `open`

---

## D-001 — Stack: native Swift 6 + SwiftUI, macOS-first

**Status:** settled
**Source:** `AGENT_LENS_SCOPE.md` §12

Agent Lens is built in Swift 6, with SwiftUI as the primary UI framework, AppKit where lower-level macOS integration is required, Foundation, and `Process` for command execution. Build system is Swift Package Manager.

**Explicitly rejected:** Electron, Tauri, React, any WebView-based UI, Rust/GPUI.

**Rationale:** the product's core job is macOS system introspection — PATH resolution, executable inspection, Finder integration, process spawning. These are AppKit/Foundation primitives. Shipping a browser runtime inside a utility whose entire purpose is *reducing* tooling sprawl would be self-contradictory.

**Consequence:** macOS-only. Windows and Linux are out of scope (§15).

---

## D-002 — The discovery engine is a separate module with no UI imports

**Status:** settled
**Source:** `AGENT_LENS_SCOPE.md` §13, §27.1, §28.4.7

The `AgentLensCore` target contains models, scanner, detectors, package-manager adapters, and operations. It must **never** import SwiftUI or AppKit.

The SwiftUI app is a separate target that consumes `AgentLensCore`.

**Rationale:** keeps the engine unit-testable and makes the command-line interface (M0–M6) possible. A non-coder cannot easily refactor a monolith later, so the boundary must be enforced from the first milestone.

**Enforcement:** a CI check that `AgentLensCore` does not import SwiftUI or AppKit. Once CI exists, this becomes a hard gate.

---

## D-003 — Zero backend, no accounts, no telemetry

**Status:** settled
**Source:** `AGENT_LENS_SCOPE.md` §16.5, §16.6

The inventory is local. There is no server, database, cloud component, user account, or telemetry in the core product.

**Rationale:** correct for a local developer tool, and anything else would be a trust liability for a utility that inspects the user's machine.

---

## D-004 — Delegate to package managers; never become one

**Status:** settled
**Source:** `AGENT_LENS_SCOPE.md` §5, §16.2

Agent Lens detects the installation mechanism and delegates the operation to the existing package manager (`npm`, `brew`, `uv`, `cargo`). It does not implement package management itself.

**Rationale:** removes roughly 70% of the scope. Reimplementing package-manager semantics is a trap.

---

## D-005 — Login-shell environment resolution is mandatory

**Status:** settled
**Source:** `AGENT_LENS_SCOPE.md` §20

`ProcessInfo.processInfo.environment["PATH"]` must **never** be the source of truth for tool discovery or command execution.

The app resolves the login-shell environment once per session — determining the shell via `getpwuid(getuid())->pw_shell` (never `$SHELL`) and capturing the environment with sentinel markers and a timeout — and passes that environment to every `Process`.

**Rationale:** a GUI `.app` does not inherit the login shell's PATH. Without this, every later milestone reports tools as "not installed" while they work perfectly in Terminal. The failure is silent and looks like a detector bug.

---

## D-006 — Installation state is tri-state

**Status:** settled
**Source:** `AGENT_LENS_SCOPE.md` §20.4

Installation is modelled as `installedAndOnPath` / `installedNotOnPath` / `notInstalled` — never as a boolean.

**Rationale:** `installedNotOnPath` is the condition that confuses users most. Surfacing it is a core diagnostic feature, not an error state.

---

## D-007 — Version status is tri-state; the latest version is never fabricated

**Status:** settled
**Source:** `AGENT_LENS_SCOPE.md` §21

`VersionStatus` is `upToDate` / `updateAvailable` / `unknown`. `unknown` is a first-class, neutral state and is rendered as a dash, never as an error and never as "up to date".

The installed version is always obtained locally. The latest version is an optional, asynchronous, network-dependent probe.

**Rationale:** standalone installs have no registry — "latest" is genuinely unknowable for them. An unreliable status indicator is worse than no indicator.

---

## D-008 — Uninstall is package-manager-only; standalone is informational

**Status:** settled
**Source:** `AGENT_LENS_SCOPE.md` §6, §22

V1 uninstalls only through package managers. For standalone or `curl | sh` installations, the app displays the install root and a link to official uninstall instructions, and **deletes nothing**.

Configuration files and caches are never touched in V1.

**Rationale:** deleting one executable while leaving `node_modules`, caches, and configuration behind produces *more* clutter than it removes, and leaves a stale PATH entry pointing at nothing.

---

## D-009 — Distribution: Developer ID + notarization + Homebrew cask

**Status:** settled
**Source:** `AGENT_LENS_SCOPE.md` §23

The app is signed with Developer ID, notarized, and distributed as a `.dmg` and a Homebrew cask.

**App Sandbox is not enabled**, and the app is therefore **not eligible for the Mac App Store**. This is a deliberate consequence of D-004 and D-005 — spawning `npm` and `brew` is incompatible with the sandbox.

**Rationale:** recorded explicitly so that contributors and agents do not attempt to sandbox the app, which would break its core function.

---

## D-010 — Detectors are data-driven with a versioned schema and fixture tests

**Status:** settled
**Source:** `AGENT_LENS_SCOPE.md` §11, §17, §27.2

Adding support for a new tool must not require modifying the core scanner. Detectors are declarative definitions in a versioned format, each with a fixture test. CI validates every detector against the schema.

**Rationale:** this is what makes the project approachable for outside contributors, and it prevents the detector registry from rotting.

**Open:** the concrete format (YAML vs JSON) is not yet decided — see O-003.

---

## D-011 — Repository layout: Swift package first, app target at M7

**Status:** settled
**Source:** `AGENT_LENS_SCOPE.md` §13, §28.3

For milestones M0–M6 the repository is a **Swift Package** with:

- `AgentLensCore` — library target (the engine)
- `agent-lens` — executable target (the CLI)
- `AgentLensCoreTests` — test target

The SwiftUI application target is added at **M7**, once the engine works.

**Rationale:** §13 sketches an Xcode-project-shaped layout including `App/` and `Features/`. That is the *destination*, not the starting point. A pure Swift package needs no Xcode project file, builds with `swift build`, and is far easier for an agent to work with and for a non-coder to verify.

---

## D-012 — Tests are the definition of done

**Status:** settled
**Source:** `AGENT_LENS_SCOPE.md` §28.2

A milestone is not complete without a test that fails before the change and passes after it. "It works" is not evidence.

**Rationale:** with AI-generated code, generation is nearly free and verification is the bottleneck. Tests are the only mechanism by which a non-coder can distinguish working code from plausible-looking code.

---

## D-013 — One branch per milestone; reviewers are read-only

**Status:** settled
**Source:** `AGENT_LENS_SCOPE.md` §29.5

- One git branch per **milestone** — not per agent, not per thread.
- The implementer's branch is the source of truth.
- Reviewers inspect and report; they never push. A proposed fix returns to the implementer as a new task.
- The orchestrator performs the merge, after acceptance passes.
- No two agents edit the same file within the same milestone.

**Rationale:** T3 Code gives every agent thread its own branch. Three branches touching the same files produce merge conflicts, and resolving a merge conflict is precisely the task a non-coder cannot do.

---

## D-014 — The orchestrator runs acceptance; no agent grades its own work

**Status:** settled
**Source:** `AGENT_LENS_SCOPE.md` §29.4

The implementer produces the change **and** the raw transcript of running the acceptance command. The **orchestrator re-runs the acceptance command independently**, in a clean shell, and must personally observe it pass.

An implementer reporting success is not sufficient. Ever.

**Rationale:** an agent that both writes and grades its own work will pass itself — reliably and in good faith. This single rule is worth more than the entire reviewer council.

---

## D-015 — Positioning: diagnose first, manage second

**Status:** settled
**Source:** `AGENT_LENS_SCOPE.md` §25

The product's primary value is diagnostic: telling the user *which* AI CLI is actually running when multiple copies exist. Management actions (update, uninstall) are secondary and delegated.

Diagnostics is a first-class UI destination, not a footnote.

**Rationale:** updates are a commodity already handled by `brew upgrade` and `npm update -g`. The PATH/duplicate diagnostic has no existing solution and is the memorable, shareable feature.

---

## D-016 — MVP ships as a command-line tool

**Status:** settled
**Source:** `AGENT_LENS_SCOPE.md` §28.3

The shipping target is **M5 or M6**. A CLI that reliably reports what is installed, where it came from, and which copy PATH resolves to is a legitimate, complete open-source project.

The GUI (M7) is an enhancement, not the product, and is the part most likely to be abandoned.

**Rationale:** protects against the most probable failure mode — a project that spends its effort on a UI and never has a working engine.

---

## D-017 — Detector schema format: JSON (settles O-003)

**Status:** settled (2026-10-13, at M4)
**Source:** `AGENT_LENS_SCOPE.md` §11, §17; supersedes the open question in D-010

Detectors are defined in **JSON**, versioned by a `schemaVersion` field in the file.

**Rationale:** JSON parses with Foundation's built-in `JSONDecoder` — the zero-dependency rule (M-series briefs: Package.swift) is preserved without authoring and maintaining a hand-rolled YAML parser. YAML's hand-editing ergonomics were weighed against JSON's mechanical validation; the detector file is small (dozens of lines per tool), so JSON verbosity costs little. Hand-written parsers are themselves a bug class; JSONDecoder is battle-tested.

**Consequence:** contributors add tools by editing `Detectors/DefaultDetectors.json` only (D-010); schema validation is test-enforced and becomes a CI gate once CI exists.

---

## D-018 — First detector set: Codex, OpenCode, Grok CLI (settles O-004)

**Status:** settled (2026-10-13, at M4)
**Source:** `AGENT_LENS_SCOPE.md` §11; resolves O-004 for the first registry

The first data-driven detector registry covers:

| Tool | Executable | Install mechanism (verified on this machine, 2026-10-13) |
|---|---|---|
| Codex | `codex` | npm — `~/.local/lib/node_modules/@openai/codex`, version 0.162.1 |
| OpenCode | `opencode` | standalone — real binary at `~/.opencode/bin/opencode`, version v2.0.28 |
| Grok CLI | `grok` | standalone — symlink to `~/.grok/downloads/grok-1.0.52-macos-aarch64`, version 1.0.52 |

All three were on the login-shell PATH per the M2 resolver at draft time. The registry format (D-010, D-017) makes adding further tools a data change, not a code change.

---

## Open questions

| ID | Question | Decide by |
|---|---|---|
| O-001 | Should a co-maintainer with Swift experience be sought? | Before M7 / OSS release (M5–M6 completed solo) |
| O-002 | When to purchase the Apple Developer Program ($99/year) | Only when preparing to ship (§23) |
| ~~O-003~~ | Detector schema format — ~~YAML or JSON~~ → **settled: JSON (D-017)** | M4 |
| ~~O-004~~ | Which tools in the first set → **settled (D-018)** | M4 |

---

## Milestone log

Record each milestone result here. Include the T3 Code build string so a regression can be attributed to a tool update rather than to the code (§29.7).

| Milestone | Date | Result | T3 Code build | Notes |
|---|---|---|---|---|
| M0 — Toolchain | 2026-10-13 | **passed** — `swift build` / `swift run agent-lens` / `swift test` all exit 0 (raw transcripts in `walkthroughs/M0-toolchain.md`) | n/a — no orchestrator build string in use; Swift 6.4, swift-driver 1.168.6 | Repo live at github.com/Hazem-Samak/agent-lens. Scaffold per D-011; walkthrough folder is a user-directed addition to the M0 allow-list. |
| M1 — Walking skeleton | 2026-10-13 | **passed** — `agent-lens scan` prints hardcoded Codex/npm report (exit 0); unknown command exits 1; `swift test` 3/3 green (transcripts in `walkthroughs/M1-walking-skeleton.md`) | n/a — Swift 6.4, swift-driver 1.168.6 | Real argument dispatch via `CommandLine.arguments`; renderer in AgentLensCore is a pure function ready to receive real detection output in M2+ |
| M2 — Environment resolution | 2026-10-13 | **passed** — `path_joined` diff vs `echo "$PATH"`: MATCH, exit 0; shell from getpwuid matches `$SHELL`; `degraded: false`; `swift test` 10/10 (transcripts in `walkthroughs/M2-environment-resolution.md`) | n/a — Swift 6.4, swift-driver 1.168.6 | Highest-risk milestone; accepted on byte-exact diff, not visual inspection. No ProcessInfo-PATH reads anywhere (M2 req. 7). Swift 6 strict-concurrency cache fix applied rather than suppressed. |
| M3 — One real detector | 2026-10-13 | **passed** — `agent-lens scan` detects Codex for real: `✓ Codex 0.162.1 npm`; version diff vs `codex --version`: VERSION MATCH; source proven against realpath; `swift test` 18/18 (transcripts in `walkthroughs/M3-real-detector.md`) | n/a — Swift 6.4, swift-driver 1.168.6 | Fixture tool: Codex at ~/.local/bin, npm-managed (real 0.162.1, stale vs M1's 0.154.0 fixture). Brief drafted in-repo per plan (M3+ briefs written after M2). Two test-caught bugs fixed: version-token regex for prerelease suffixes; stale M1 usage assertion. |
| M4 — Detector schema + registry | 2026-10-13 | **passed** — `agent-lens scan` reports all three D-018 tools from the registry; per-tool version diffs MATCH (codex 0.162.1 / opencode 2.0.28 / grok 1.0.52); 9 schema-violation cases rejected named; 4th tool via data-only edit proven live then reverted; `swift test` 22/22 (transcripts in `walkthroughs/M4-detector-registry.md`) | n/a — Swift 6.4, swift-driver 1.168.6 | O-003/O-004 settled as D-017 (JSON) / D-018 (Codex, OpenCode, Grok) before implementation. D-010 fulfilled: adding a tool requires zero source changes. Known grep-trap in the first acceptance loop fixed and recorded; the brief's check was corrected accordingly. |
| Pre-M5 stabilization | 2026-10-13 (EEST) | **passed** — 34-test stabilization baseline accepted | n/a — Hermes orchestration; Swift 6.4 | `walkthroughs/pre-m5-stabilization.md` |
| M5 — Duplicate / PATH diagnostics | 2026-10-13 (EEST) | **passed** — final review-found canonical-target fix and 2 regression tests accepted; fresh full suite 46/46 (2.016s) plus no-override rerun 46/46 (2.026s), both exit 0; three CLI winners/versions verified, aliases 0/1/1, 0 shadowed each; login+interactive PATH MATCH; dispatch unchanged | n/a — Hermes orchestration; Swift 6.4 | Acceptance: `walkthroughs/pre-m5-stabilization.md`; `walkthroughs/M5-duplicate-path-diagnostics.md` |
| M6 — Version / update probing | 2026-10-14 (EEST) | **passed / independently accepted** — two distinct fresh builds each passed 180/180 (23.447s and 22.716s, exit 0); all 12 CLI forms passed; live M5 prefix remained byte-identical; accepted source/test snapshot and real app-cache content stayed unchanged | n/a — Hermes orchestration; Swift 6.4; final test runs used invocation-local Swift Testing macro-plugin loading, with no package or toolchain change | `walkthroughs/M6-version-update-probing.md`; two independent read-only review axes and targeted blocker rereview passed. Homebrew-formula-only; latest known metadata, not guaranteed globally latest. No M7 or package operations. |
| M6 post-acceptance correction — unsupported-version reason priority | 2026-10-15 (EEST) | **passed / parent accepted** — independent fresh full gate 184/184 (23.145s, exit 0); compiled classification proof exit 0; targeted artifact-only rereview passed | n/a — Hermes orchestration; Swift 6.4; explicit Swift Testing macro-plugin fallback | Enforces the existing M6 reason-priority contract; see dated correction section in `walkthroughs/M6-version-update-probing.md`. Accepted on `fix/m6-unsupported-version-reason` from the `13afef5` checkpoint. Parent is authorized to publish the correction with the M7 plan; current Git refs/history are authoritative for integration status. Default-Darwin-TMPDIR fixture portability remained unresolved; M7 was plan-only at this correction checkpoint. M7 delivery is recorded in the following row. |
| M7 — First UI | 2026-10-16 | **passed** — initial native SwiftUI macOS app accepted; user visual approval 2026-10-16 (Africa/Cairo) for initial UI; DeepSeek R4/final PASS with no blocking findings; parent independent technical acceptance. 222 Swift (184 Core +38 AppSupport) +9 Python packaging, all exit 0; hosted selfchecks 8/8 exit 0. All 29 Core/CLI source and test files unchanged. The historical documentation closeout preserved 65 of 68 pinned files, changed only the 3 approved docs (`DECISIONS.md`, `README.md`, `briefs/README.md`), and added one walkthrough (`walkthroughs/M7-first-ui.md`, 69 total). That closeout phase made no source expansion or Git mutation; subsequent Git delivery is recorded in Notes. No signing, notarization, or app release. | 0.1.1-nightly.20261016.3218 (observed at documentation closeout 2026-10-16; earlier acceptance-gate T3 build not recorded) — macOS 27.0.1 build 26A434; Swift 6.4 (swiftlang-6.4.0.34.1), swift-driver 1.168.6, arm64-apple-macosx27.0.0 | Closeout docs: `walkthroughs/M7-first-ui.md` (measured implementation/acceptance), `briefs/README.md`, `README.md`, `DECISIONS.md`. Delivered to `main` and GitHub as `36a3f1cd4ce3c926deadb2565d8e2a6938161c9f` (`feat(ui): complete M7 native macOS app`). Local `main`, `origin/main`, and remote `main` matched in a read-only check on 2026-10-17; worktree clean before the delivery-note/M8-plan update. M8 path actions are a separate draft; implementation has not started. |
| M8 — Copy Path and Reveal in Finder | 2026-10-18 | **user-approved for delivery** — parent independently observed 246 Swift tests, fresh app build, 9 packaging tests, and invalid-target probe pass; Gemini High and MiMo final PASS; user visual approval and commit/push/cleanup authorization. Native keyboard-only activation remains unverified, not a passed gate. | n/a — Zeron orchestration (0.2.113 observed at preflight); Swift 6.4; macOS 27.0.1 (26A434) | Sole implementer: DeepSeek V4.1 Flash free / WorkBuddy Pi. Exactly four implementation files; all 69 protected baseline files unchanged before documentation closeout. See `walkthroughs/M8-path-actions.md` for native evidence and limits. No system keyboard preference changed; no signed/notarized app release. |
| M9 — Verified installation details and per-installation versions | 2026-10-25 | **technically accepted, user-UI-approved and delivered to `main`** — corrected A/B/C plus parent combined gate: 329 Swift (258 Core +71 AppSupport), fresh app build and 9 packaging; actual CLI/native, read-only real npm/Homebrew, isolated identity/budget/lifecycle scenarios; final independent safety/contract reviews clear | n/a — omp orchestration; installed T3 Code Nightly `0.1.3-nightly.20261024.3630` observed from public bundle metadata, not claimed as the orchestration build; Swift 6.4 | Sole implementer: DeepSeek V4.1 Flash Free / OpenCode, maximum effort. User approved M9 UI, then separately authorized branch delivery and main integration. Feature `eb4f586` reached `origin/main` through the fast-forward of milestone tip `1ac22c4`. See `walkthroughs/M9-verified-installations.md` for accepted hashes, corrections, raw evidence and delivery. No tool Update/Uninstall or signed distribution. M8 keyboard-only activation remains unverified. |
| M10-A — Clean CI and default-TMPDIR portability | 2026-10-26 | **technically accepted on the M10 feature branch** — parent independent local406 Swift, both real bundle layouts/9 packaging each, parser39 on Python3.9/3.15, guard21, workflow controls; hosted exact candidate all7 gates including406 Swift and original9 packaging, zero skips/failures | n/a — Codex desktop orchestration, no T3 build claimed; hosted Xcode26.3/Swift6.2.4 on macOS15.7.9 arm64 | Sole implementer DeepSeekV4.1Flash/WorkBuddy/OMP; final Qwen3.8Flash/Qoder and user-authorized replacement Gemini3.8FlashHigh/agy PASS. Feature `f442aa25f513afd2ae92af7da544b405791fafa7`; [run40389308783](https://github.com/Hazem-Samak/agent-lens/actions/runs/40389308783), attempt1; artifact digest/33 receipts independently verified. See [acceptance](walkthroughs/M10-A-acceptance.md). M10-B unstarted; no PR/main merge/release. M8 keyboard-only gate remains unverified. |
| M10-C R1 — Terminal-context baseline repair | 2026-11-02 | **locally technically accepted, uncommitted** — final coordinator 469/469 test events in both controlling-PTY and detached contexts; guard21, fresh app, packaging9, actual terminal CLI exact non-degraded fixture PATH; final Qoder independent PASS | n/a — OMP orchestration through Herdr; Swift 6.4 on macOS27 arm64; no T3 build claimed | River/Pi `deepseek-ai/DeepSeek-V4.1-Flash-1017`, max, sole writer. Interactive zsh stopped on SIGTTOU in the inherited controlling-terminal session; capture now disables job control with `+m`. Perch hit quota before verdict; owner explicitly waived its verdict for this repair only. [Acceptance](walkthroughs/M10-C-R1-baseline-repair.md); M10-C product implementation separately dispatched, not accepted; original two product reviewers retained; no Git/hosted/release claim. |
| M10-C — Confirmed npm Update | 2026-11-02 | **technically accepted on the feature branch** — parent510 Swift in each controlling-TTY/detached context, guard21, fresh app, packaging9; native1.0.0→2.0.0 and ordinary packaged public0.165.0→0.166.0, Cancel unchanged, active/prepared-close cleanup; hosted exact-SHA all7 gates/510 combined Swift, zero skips/failures | n/a — OMP orchestration through Herdr; Swift6.4 local; hosted macOS15.8.2 arm64/Xcode26.3/Swift6.2.4; no T3 build claimed | River/Pi `deepseek-ai/DeepSeek-V4.1-Flash-1017`, max, sole product writer. Perch `glm-5.3-flash-starter`/max and Qoder `Qwen3.8-Max`/xhigh both final PASS, no remaining material findings. Owner-authorized implementation `fff287d79884bf2163642dfa6ef3543da5682565`; [hosted run41519177534](https://github.com/Hazem-Samak/agent-lens/actions/runs/41519177534), attempt1, digest-verified33-file artifact retained. [Evidence/limits](walkthroughs/M10-C-implementation.md). No main merge, release, or M10-D authorization. |

## M10-D — acceptance (2026-11-08)

The owner authorized M10-D planning and implementation, with the orchestrator as sole product writer
and independent read-only reviewers. The plan is frozen at `3d6129d`; review corrections are frozen
at `46778d2`. Implementation candidate `308b7d2` passed all seven exact-SHA hosted gates: guard,
21 guard fixtures, package build, native-macro isolation, **532** combined Swift tests, fresh debug
app, and **9** packaging checks, with no skips. Local evidence includes 20 Core uninstall tests,
AppSupport/ViewModel coverage, controlled real-npm Uninstall, combined Update→Uninstall on one
prefix/gate, public npm Uninstall through the shipping service boundary, and unchanged sentinels.
After the owner granted Accessibility, the ordinary debug app passed the native click-through:
Verify → Uninstall preview → Cancel with byte-identical prefix hashes → fresh preview → Uninstall
Package → **Uninstall Succeeded**, exit 0, `0.165.0 → —`, install state `installedAndOnPath →
notInstalled`, package directory gone, target released, no replacement/residue/failed observation.
The shipping CLI then agreed; public sentinels were unchanged. Screenshots and the action transcript
are retained with the implementation record.

**M10-D and the combined npm gate are technically accepted on the feature branch; M10 as a whole is
accepted on `codex/m10-npm-management`.** PR #1 is open and owner-authorized for merge after the R2
corrections and two documented self-reviews (see below); no public release is authorized. mcode
issued plan and implementation BLOCKs corrected in R1/follow-up; agy's static BLOCK contained one
stale `repo` finding disproved by the passing render scenario and the pre-grant TCC finding now
resolved by the successful click-through. OpenCode GLM plan review stalled after one verified
lifecycle-script correction. See [M10-D implementation](walkthroughs/M10-D-implementation.md).

## M10-D R2 — corrections, self-reviews, and merge authorization (2026-11-08)

The owner authorized a final R2 correction pass on the accepted M10 branch, explicitly waived a
further independent post-correction implementation review because no other implementer or model was
authorized, and directed the sole implementer to review the work twice and then merge. The waiver is
recorded in `walkthroughs/M10-D-implementation-evidence/reviews/README.txt`; no independent PASS is
claimed for R2.

Corrections: Check/Refresh no longer forwards the captured login-shell `TMPDIR` and uses Foundation's
`temporaryDirectory` when no base is injected; the update busy-gate branch suppresses the false
scratch-cleanup warning for an already-consumed preparation; `runDualStream` rechecks cancellation
immediately before `posix_spawn`; both confirmation sheets show the stable registry ID; the combined
real-npm scenario now includes the required deliberate concurrent-confirm and
window-close/interruption cases; CI floors are raised to the measured final inventory; local absolute
paths in PR-added text evidence are redacted with the affected SHA manifests regenerated.

Verification: full local suite **456 Core + 79 AppSupport = 535**, zero failures/skips, exit 0
(`walkthroughs/M10-D-implementation-evidence/full-suite-r2.log`); extended combined real-npm scenario
`COMBINED-CONTROLLED OK` with update succeeded, competing confirm cancelled/no process, interrupted
uninstall reconciled, final uninstall succeeded, residue reported, and exactly one update/two
uninstall invocations (`combined-summary-r2.json`, `combined-result-r2.json`). Targeted regressions
passed. Exact-SHA hosted CI and the merge commit are recorded on PR #1.

## M10 — PR #1 merge and delivery to main (2026-11-08)

PR #1 (`codex/m10-npm-management` → `main`), "M10: npm Update, Uninstall, and combined safety
acceptance", was merged on 2026-11-08 at 15:27 UTC after the owner-authorized R2 corrections and
two documented self-reviews. Merge commit: `65f7a8225524533924db87132f2563e01d7b6432` (`65f7a82`).
[Hosted run 42494920522](https://github.com/Hazem-Samak/agent-lens/actions/runs/42494920522)
passed at that exact SHA. Local `main` and `origin/main` were verified at the merge commit in a
read-only check on 2026-11-12.

M10-A/B/C/D and the combined npm gate are delivered to `main`. The ROADMAP §8 merge-recording
gate is satisfied; M11 preparation may begin under the lean operating protocol. No public release
was published or authorized. The merged feature branch remains on origin pending a separate owner
decision.

## M8 — user-approved delivery (2026-10-18)

The user authorized implementation of [M8 path actions](briefs/M8-path-actions.md), then approved the UI and Git delivery with “all good, clean branches comm push all”. Automated gates and independent final reviews passed. The unverified keyboard-only activation check remains a documented limitation; user approval is not evidence that it was measured. [The walkthrough](walkthroughs/M8-path-actions.md) records the result, team, raw-evidence locations, and limits. The frozen M7/M8 briefs and historical acceptance transcripts remain unchanged.

---

## Out of scope

MCP servers, agent skills, configuration files, generic system utilities, arbitrary binaries, security scanning, generic Mac applications, Mac cleaning, AI chat, cloud sync, user accounts, telemetry, plugin marketplace, automatic broad cleanup, Windows, Linux.

See `AGENT_LENS_SCOPE.md` §15 for the authoritative list.

## D-019 — M6 update checks are opt-in Homebrew formula diagnostics

**Status:** settled (2026-10-14, at M6)
**Source:** `AGENT_LENS_SCOPE.md` §21, §27.1/3/5, §28.2–3, §29.4–5/10–12; `briefs/M6-version-update-probing.md`

M6 preserves local detection and adds an opt-in, asynchronous, tri-state update result based on the selected installation and verified Homebrew formula metadata. The adapter supports formulae only and runs at most three bounded queries per eligible batch; it does not run `brew update` or perform package operations. Unsupported managers, unsupported version schemes, and opaque process failures remain neutral `unknown` results. Only verified successful metadata is cached, in schema 3 with a six-hour TTL and a 1 MiB limit; the cache is keyed by full manager/formula/selection/context identity and does not store raw environment values. Status is recomputed from current local facts on every run.

**Consequence:** latest means latest known to Homebrew metadata at observation time, not a guarantee of the newest upstream release. npm, standalone, cask, uv/pip, and Cargo adapters remain outside M6. M7 subsequently consumed this same contract without extending manager support; see the delivered M7 milestone above.

---

## D-020 — Value-first delivery order and lean planning

**Status:** settled (2026-10-28, after M10-B)
**Source:** `AGENT_LENS_SCOPE.md` §7, §9, §25, §28.2, §29.4–5; `ROADMAP.md` (2026-10-28 revision)

The future execution order is **M10 npm management → M11 original catalogue/contributor foundation → M12 complete native diagnostic and operation workflow → M13 Homebrew → M14 Python → M15 Cargo → M16 cached launch/menu bar → M17 bundled CLI → M18 release candidate → M19 signed distribution**. This supersedes only the future ordering in the 2026-10-22 roadmap; historical milestone IDs, briefs, and acceptance evidence remain unchanged.

**Rationale:** the previous order delivered three additional manager tracks before broad detection and the complete diagnostic UI. That delayed the product's primary value and user-testable progress. The revised order proves one safe mutation lifecycle, expands diagnostic coverage, completes the native workflow, and then reuses that workflow for the remaining managers.

**Consequence:** catalogue entries whose manager adapters do not yet exist remain informational or disabled with a truthful reason. The outstanding M8 keyboard-only Copy/Reveal check becomes a required M12 acceptance gate. Planning changes require no council or implementer; independent orchestrator acceptance and risk-based read-only review for high-risk implementation remain mandatory.

---

## D-021 — Per-entry mutation acceptance gate; additive schema-2 field

**Status:** settled (2026-11-12, at M11-B)
**Source:** `ROADMAP.md` §4 M11 / §6; `briefs/M11-plan.md` R1; `briefs/M11-B-mutation-gate.md`;
`walkthroughs/M11-B-acceptance.md`

Detection never implies mutation eligibility. Each detector definition may carry an optional
`acceptedOperations` array with the closed vocabulary `npmUpdate`, `npmUninstall`; absent or empty
means no mutation is offered, even when npm ownership verifies. Both Core prepare seams refuse
with `.operationNotAccepted` before any observation, scratch claim, or process; AppSupport/App
mirror the refusal with the single-source Core reason text. `codex` is seeded from its M10
acceptance; every other entry is informational until a per-tool accepted mutation scenario is
separately owner-authorized.

The field is **additive on registry schema 2** (no version bump): absent → `[]`; present `null`,
non-array, unknown values, duplicates, and non-string elements are rejected with named
detector/field errors on both decode paths; schema 1/3 and unknown keys remain rejected.

**Rationale:** the M10 npm ownership path is generic; without the gate, adding npm-declared
catalogue entries in M11 would silently enable Update/Uninstall for tools that never had an
accepted mutation scenario. Verified in code during M11 planning (council finding, judge-confirmed).

**Consequence:** new catalogue entries (M11-C/D/E) ship without acceptance. Promotion requires its
own controlled acceptance scenario and owner authorization. Accepted at `caae348` with two
independent PASS reviews (MiniMax M3.1-Flash/xhigh, Grok 4.7/high), 543 tests, and an
orchestrator-performed native spot-check.

---

## D-022 — Shipping CLI remains read-only; M11-B CLI-mirror clause vacuous

**Status:** settled (2026-11-12, at M11-B)
**Source:** `briefs/M10-C-npm-update.md` (no CLI mutation syntax); `briefs/M10-D-npm-uninstall.md`
(shipping CLI read-only); `walkthroughs/M11-B-acceptance.md` (F-1 ruling)

The M11-B brief's contract 7 / B-AC05 assumed a CLI update/uninstall path that does not exist: the
shipping CLI dispatches only `scan`, `verify-installation`, and `debug-env`. The clause was a brief
defect. Ruling: the clause is vacuous; `main.swift` correctly unchanged; B-AC05 is recorded as
vacuous-by-ruling, not evidenced. Adding CLI mutation syntax remains forbidden by the frozen
M10-C/M10-D contracts; any future CLI mutation surface is a separate owner decision.

---

## M11 — phase acceptances (2026-11-12)

Planning Council (MiniMax M3.1-Flash/xhigh via mcode; Grok 4.7/high via grok CLI; Herdr/hc
orchestration) produced independent proposals; the orchestrator judged and froze
`briefs/M11-plan.md` on base `d0a2b41` (commit `d98bf7b`). Owner approved implementation the same
day, delegating technical decisions (license OD-7 remains the owner's open choice), naming DeepSeek
V4.1 Flash 1017 via OMP (max) as sole implementer and the council models as standing independent
reviewers; all agents summoned through Herdr/hc only.

- **M11-A — identity freeze: technically accepted** at `c48b226`. 14/14 identities frozen with
  primary-source citations; 5/5 disposable-scratch version measurements (claude 2.1.322, gemini
  0.68.0, aider 0.86.2, goose 1.59.0, kiro-cli 3.2.1); 425 protected hashes clean; scratch
  destroyed. Carry-forward: Aider cold start 3747 ms > 3 s query budget (unknown is safe);
  gemini-cli/cline formula deprecations; OpenCode/AGY canonical URL corrections.
  [Acceptance](walkthroughs/M11-A-acceptance.md).
- **M11-B — mutation acceptance gate: technically accepted** at `caae348`. D-021/D-022 recorded.
  543 tests (463 Core + 80 AppSupport), all six gates orchestrator-rerun exit 0; both mandatory
  independent reviews PASS (0 blocking); native spot-check PASS (codex M10 surface intact,
  unaccepted entries informational). [Acceptance](walkthroughs/M11-B-acceptance.md).

No merge to `main`, no release. M11 continues with M11-C (settled registry batch).

## M11 — combined acceptance (2026-11-12)

**M11 is technically accepted on `milestone/m11-catalogue` at combined candidate `b07e321`.**
Phases A–F accepted individually (A `c48b226`, B `caae348`, C `5a0fb54`, D `cdd8ccc`, E `28738dc`,
F `d3f0324`+R1); sole implementer DeepSeek V4.1 Flash 1017 via OMP max; mandatory independent
reviews (MiniMax M3.1-Flash/xhigh, Grok 4.7/high) PASS for B/D/F; one LOW (contributor guide
edit-list omission) corrected via R1. Combined gate: local 547 tests (467 Core + 80 AppSupport)
plus all seven hosted gates at the exact SHA
([run 43288284409](https://github.com/Hazem-Samak/agent-lens/actions/runs/43288284409), success);
end-to-end fifteenth-tool data-only contribution proof observed in CLI and native app, registry
restored byte-identically. The original fourteen-entry catalogue ships with the fail-closed
mutation acceptance gate (D-021), the test-enforced capability matrix, and the contributor guide.
[Combined acceptance](walkthroughs/M11-combined-acceptance.md).

**Open owner gates:** merge to `main` (Git delivery) is NOT authorized by this acceptance; license
(OD-7, MIT vs Apache-2.0) before public contribution invitations; per-tool mutation promotions;
M12 dispatch. The M8 keyboard-only Copy/Reveal measurement remains a required M12 gate. No public
release was published or authorized.
