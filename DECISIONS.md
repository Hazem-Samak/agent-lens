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
