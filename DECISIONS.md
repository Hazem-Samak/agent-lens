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

## Open questions

| ID | Question | Decide by |
|---|---|---|
| O-001 | Should a co-maintainer with Swift experience be sought? | Before M4 |
| O-002 | When to purchase the Apple Developer Program ($99/year) | Only when preparing to ship (§23) |
| O-003 | Detector schema format: YAML or JSON | M4 |
| O-004 | Which specific tools the first detector set covers | M4 |

---

## Milestone log

Record each milestone result here. Include the T3 Code build string so a regression can be attributed to a tool update rather than to the code (§29.7).

| Milestone | Date | Result | T3 Code build | Notes |
|---|---|---|---|---|
| M0 — Toolchain | | | | |
| M1 — Walking skeleton | | | | |
| M2 — Environment resolution | | | | |
| M3 — One real detector | | | | |
| M4 — Detector schema + 3–5 tools | | | | |
| M5 — Duplicate / PATH diagnostics | | | | |
| M6 — Version / update probing | | | | |
| M7 — First UI | | | | |

---

## Out of scope

MCP servers, agent skills, configuration files, generic system utilities, arbitrary binaries, security scanning, generic Mac applications, Mac cleaning, AI chat, cloud sync, user accounts, telemetry, plugin marketplace, automatic broad cleanup, Windows, Linux.

See `AGENT_LENS_SCOPE.md` §15 for the authoritative list.
