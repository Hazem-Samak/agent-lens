# Agent Lens

> **Your AI tools, in one place.**

> **Revision note (2026-10-11)** — Sections 20–29 were added following an architecture and product review. They cover environment resolution (§20), version-detection reliability (§21), uninstall safety (§22), distribution constraints (§23), retention (§24), positioning (§25), a consolidated risk register (§26), Swift 6 / SwiftUI implementation notes (§27), the execution model for a solo, non-coder builder working with AI tools (§28), and the multi-agent team configuration and protocols (§29). Sections 1, 3.1, 6, and 10 were amended for consistency with those findings.

Agent Lens is an open-source, native macOS utility for discovering and managing AI development tools installed on a Mac.

The goal is simple: **find out what AI agents, coding tools, harnesses, and related CLIs are installed, where they came from, what version they are running, and give the user simple, safe actions such as update or uninstall.**

---

## 1. Product Positioning

Agent Lens is **not** another terminal, package manager, or general Mac cleaner.

It is a lightweight **control center for AI development tooling**.

The primary value is **diagnostic, not managerial**: determining *which* AI CLI is actually running when multiple copies exist on the same machine. Management actions (update, uninstall) are secondary and are delegated to existing package managers. See §25.

The core user problem:

> “I have accumulated a bunch of AI CLIs and agents. What exactly is installed on my Mac, where did each one come from, which ones are outdated, and how do I safely remove or update them?”

Agent Lens answers that question with a native Mac interface.

---

# 2. Scope

Agent Lens initially focuses on exactly four categories.

## 2.1 AI Agents

Examples:

- Codex
- Claude Code
- Gemini CLI
- OpenCode
- Hermes
- Cline CLI

## 2.2 AI Coding Tools

Examples:

- Aider
- Goose
- Kiro CLI
- Qoder
- Similar AI-focused coding tools

## 2.3 AI Harnesses

Examples:

- DSH
- OMP
- AGY
- Similar AI agent/harness tooling

## 2.4 Package Managers / Installed CLIs

Package managers are primarily treated as **installation sources**, rather than as products that Agent Lens itself manages.

Examples:

- npm
- Homebrew
- Cargo
- pip
- uv

Agent Lens should be able to identify when a supported tool was installed through one of these mechanisms.

---

# 3. Core MVP

## 3.1 Scan & Discover

Agent Lens scans the Mac and builds an inventory of recognized AI tooling.

For each detected tool, determine where possible:

- Name
- Category
- Installed version
- Latest version — **tri-state**, not a single value: `up to date` / `update available` / `unknown`. "Latest" is not always knowable (standalone installs have no registry) and must never be fabricated. See §21.
- Installation method
- Package name
- Executable path
- Whether the executable is reachable through `$PATH`
- Whether an update is available
- Basic installation status

Example:

```text
AI AGENTS                         5

✓ Codex          0.154.0    npm
✓ Hermes         0.20.5     uv
✓ OpenCode       1.18.18    standalone
✓ Claude Code    1.x        npm
✓ Gemini CLI     0.x        npm
```

---

# 4. Detail View

Selecting a tool opens a simple information view.

Example:

```text
OpenCode

Version       1.18.18
Latest        1.18.19
Source        npm
Executable    ~/.opencode/bin/opencode
Status        Update available

[ Update ]
[ Uninstall ]
[ Reveal in Finder ]
[ Copy Path ]
```

The detail view should prioritize useful system information without becoming a configuration editor.

---

# 5. Update

Agent Lens should **not become a package manager**.

Instead, it detects the installation mechanism and delegates the operation to the existing package manager.

Examples:

```bash
npm update -g <package>
brew upgrade <package>
cargo install <package>
uv tool upgrade <package>
```

Before executing a potentially modifying command, show the user what will happen.

Example:

```text
Update OpenCode?

$ npm update -g opencode

[ Cancel ]    [ Run Update ]
```

The user remains in control of destructive or modifying operations.

---

# 6. Uninstall

Uninstall follows the same principle.

For package-managed tools, Agent Lens invokes the appropriate package manager.

Example:

```text
Remove Cline?

Installation:
npm global package

Command:
npm uninstall -g cline

[ Cancel ]    [ Remove ]
```

For standalone installations, V1 is **informational only**: Agent Lens displays the detected install root and links to the tool's official uninstall instructions, but does not delete anything. Deleting a single executable while leaving `node_modules`, caches, and configuration behind produces *more* clutter than it removes, and can leave a stale `$PATH` entry pointing at nothing.

V1 must be conservative: **do not delete ambiguous files, install roots, or unrelated configuration automatically.**

See §22 for the complete uninstall policy matrix.

---

# 7. Search & Filtering

The inventory should support simple search and filtering.

Suggested filters:

- All
- AI Agents
- AI Coding Tools
- AI Harnesses
- Updates

Keyboard-first interaction should be supported.

Potential shortcuts:

- `↑ / ↓` — navigate
- `Enter` — open
- `U` — update
- `R` — remove
- `S` — scan
- `⌘K` — command/search palette

Exact shortcuts can be refined during implementation.

---

# 8. Duplicate Detection

Duplicate installations are an important MVP feature.

Example:

```text
⚠ Multiple OpenCode installations

~/.opencode/bin/opencode       1.18.18
/opt/homebrew/bin/opencode     1.18.17

PATH resolves to:
~/.opencode/bin/opencode
```

Agent Lens should help users understand:

- Multiple installations
- Multiple versions
- Which executable `$PATH` resolves to
- Which installation is actually being used

This is one of the key reasons for the product to exist.

---

# 9. Proposed Main UI

A simple native Mac dashboard:

```text
┌─────────────────────────────────────────────────────┐
│  Agent Lens                              Search      │
├──────────────┬──────────────────────────────────────┤
│              │                                      │
│  Overview    │  AI AGENTS                           │
│              │                                      │
│  AI Agents 8 │  Codex          0.154.0     ✓       │
│  Coding     3│  OpenCode       1.18.18     ↑       │
│  Harnesses  3│  Hermes         0.20.5      ✓       │
│              │  Cline          3.0.62      ✓       │
│  Updates  2  │  DSH            0.1.5       ↑       │
│              │                                      │
│  ──────────  │  2 updates available                │
│  Settings    │                                      │
│              │                                      │
└──────────────┴──────────────────────────────────────┘
```

The visual design should feel like a **native macOS utility**, not a web application placed inside a Mac window.

---

# 10. Architecture

The application should separate the discovery/management engine from the UI.

```text
                    Agent Lens
                        │
             ┌──────────┴──────────┐
             │                     │
      Discovery Engine          SwiftUI UI
             │                     │
       ┌─────┼─────┐          Native Mac UI
       │     │     │
      npm   brew   uv/cargo
       │
       └── executable / PATH / version
```

## Discovery Engine

Conceptual pipeline:

```text
Scanner
  ↓
Shell environment resolution   ← added: see §20
  ↓
PATH scanner
  ↓
Known-tool detectors
  ↓
Package-manager detection
  ↓
Version detection
  ↓
Update detection   ← tri-state, network-optional: see §21
  ↓
Agent model
```

The UI consumes the resulting structured inventory.

---

# 11. Data-Driven Detectors

Tool detection should be designed to be extensible.

Conceptually:

```text
Codex
├── category: AI Agent
├── commands: codex
├── package managers:
│   └── npm
├── executable paths:
│   └── ~/.local/bin/codex
└── version command:
    └── codex --version
```

The exact implementation can evolve, but the principle is important:

> **Adding support for a new tool should not require rewriting the core scanner.**

This also creates a natural OSS contribution model.

A contributor should eventually be able to add support for a new tool by adding a detector definition rather than modifying core application logic.

---

# 12. Native macOS Stack

## Primary stack

- **Swift 6**
- **SwiftUI** — primary UI
- **AppKit** — only where lower-level macOS integration is useful
- **Foundation**
- **Process** — executing package-manager and CLI commands
- **Swift Package Manager**
- **Xcode 27**
- **macOS-first**

## Why native SwiftUI

Agent Lens is fundamentally a Mac system utility.

Native SwiftUI provides:

- Native macOS windows
- Native menus and toolbars
- Native keyboard shortcuts
- Native search/navigation patterns
- Finder integration
- Accessibility support
- macOS appearance integration
- Apple Silicon support
- Straightforward `.app` packaging

There is no need for:

- Electron
- Tauri
- React
- WebView-based UI
- Rust/GPUI in the initial implementation

The discovery engine itself remains separated from SwiftUI so the core logic does not become tightly coupled to presentation.

---

# 13. Suggested Project Structure

```text
AgentLens/
│
├── App/
│   └── AgentLensApp.swift
│
├── Core/
│   ├── Models/
│   ├── Scanner/
│   ├── Detectors/
│   ├── PackageManagers/
│   └── Operations/
│
├── Features/
│   ├── Dashboard/
│   ├── AgentDetail/
│   ├── Updates/
│   └── Settings/
│
├── Resources/
│   └── Detectors/
│
└── Tests/
```

This is a starting structure, not a rigid requirement.

---

# 14. Development Phases

## Phase 1 — Discovery Core

Build the underlying scanner before spending significant effort on UI.

Goal:

```bash
agent-lens scan
```

should be able to produce a reliable structured inventory.

Implement:

- PATH discovery
- Known-tool detection
- Installation-source detection
- Version detection
- Basic duplicate detection
- Structured agent/tool model

## Phase 2 — Native UI

Build the SwiftUI interface around the discovery model.

Implement:

- Sidebar/categories
- Tool list
- Tool detail view
- Search
- Update indicators
- Empty/error states

## Phase 3 — Operations

Implement:

- Update
- Uninstall
- Reveal in Finder
- Copy path
- Rescan

Operations should show the command/action before execution where appropriate.

## Phase 4 — Polish

Focus on:

- Native macOS interaction
- Keyboard navigation
- Error handling
- Loading states
- Accessibility
- Visual polish
- macOS application packaging
- README
- Screenshots
- Initial OSS release

---

# 15. Explicit Non-Goals for MVP

Agent Lens should **not** initially manage:

- MCP servers
- Agent skills
- Configuration files
- Generic system utilities
- Arbitrary binaries
- Security/signature scanning
- Generic Mac applications
- Mac cleaning/optimization
- AI chat
- Cloud synchronization
- User accounts
- Telemetry
- Plugin marketplace
- Automatic broad cleanup
- Windows
- Linux

The product should stay focused on AI development tooling.

---

# 16. Product Principles

### 1. Discover first

The most important feature is understanding what is installed.

### 2. Don't reinvent package managers

Use npm, Homebrew, Cargo, pip, uv, etc. rather than implementing package management ourselves.

### 3. Safe by default

Never make destructive assumptions about files or installations.

### 4. Native Mac experience

Agent Lens should feel like a Mac utility, not a cross-platform application adapted to macOS.

### 5. Zero backend

The initial product does not need an account, server, database, or cloud component.

### 6. Privacy-first

The inventory is local. No telemetry is required for the core product.

### 7. Extensible detection

New AI tools should be easy for the community to add.

### 8. Keep the MVP small

The product succeeds if it makes AI-tool discovery and basic management dramatically easier.

---

# 17. OSS Direction

Agent Lens will be open source.

Potential license choices:

- MIT
- Apache-2.0

The detector system should eventually make community contributions straightforward.

A future contribution might effectively be:

```text
Add detector for NewAI CLI
```

rather than:

```text
Modify scanner internals
Modify UI
Modify package-manager logic
Modify several unrelated files
```

This keeps the project approachable for contributors.

---

# 18. Possible Future Direction

These are **not MVP commitments**.

If the core product proves useful, Agent Lens could later expand into:

- More sophisticated installation diagnostics
- Better PATH conflict explanations
- More package-manager support
- Community-maintained detector registry
- Additional AI-tool metadata
- Historical version information
- Better update workflows
- CLI companion
- More advanced health checks

Any expansion should preserve the central identity:

> **Agent Lens helps you understand and manage the AI development tools installed on your Mac.**

---

# 19. One-Sentence Definition

> **Agent Lens is an open-source native macOS control center that discovers your installed AI agents, AI coding tools, and AI harnesses, shows how they were installed and whether they need updates, and provides simple, safe management actions.**

> A diagnostic-led revision of this definition is proposed in §25.2.

---

# 20. Environment Resolution & PATH Fidelity

## 20.1 Problem

A macOS `.app` launched from Finder, Spotlight, or `open` inherits the minimal environment provided by `launchd`. It does **not** inherit the user's login-shell environment. Entries added by `.zshrc`, `.zprofile`, `.bash_profile`, `eval "$(brew shellenv)"`, `~/.local/bin`, `~/.opencode/bin`, `~/.cargo/bin`, and similar tool-managed directories are **absent**.

Consequences if unaddressed:

1. **False negatives.** Tools that work perfectly in the user's terminal are reported as "not installed" or "not on `$PATH`".
2. **Execution failure.** `Process` cannot locate `npm`, `brew`, `node`, `uv`, or `cargo`, so update and uninstall operations fail with `command not found`.
3. **Incorrect diagnostics.** PATH-resolution and duplicate reporting (the product's core value, §8) becomes wrong, which destroys trust immediately.

This is the single most common failure mode for macOS developer utilities. It must be solved in the discovery engine, not patched in the UI.

## 20.2 Solution — resolve the login-shell environment once per session

1. **Determine the user's shell** from the password database, not from `$SHELL` (which may be unset in a GUI context): `getpwuid(getuid())->pw_shell`.
2. **Capture the environment** by launching a login + interactive shell with sentinel markers so rc-file noise can be stripped:

   ```bash
   <shell> -l -i -c 'printf "\n__AGENTLENS_ENV_BEGIN__\n"; env -0; printf "__AGENTLENS_ENV_END__\n"'
   ```

   Use NUL-delimited output (`env -0`) to survive values that contain newlines.
3. **Enforce a timeout** (default 3 s). If the shell hangs or fails, fall back to a documented default PATH (`/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin` plus the Homebrew prefixes) and mark the environment as `degraded` so the UI can disclose it.
4. **Never `eval` or source user rc files** into the app process. Capture output only.
5. **Cache the result** for the session; re-resolve on explicit "Rescan" and on activation when the cache is stale.

## 20.3 Environment is a first-class dependency

Both the scanner and the operation executor must receive the resolved environment explicitly:

```swift
public struct ShellEnvironment: Sendable {
    public let pathEntries: [String]   // ordered, exactly as the shell would search
    public let raw: [String: String]   // full environment passed to Process
    public let isDegraded: Bool        // true when the fallback PATH was used
}
```

Rules:

- **Never** treat `ProcessInfo.processInfo.environment["PATH"]` as the source of truth for discovery or execution.
- Every `Process` launch sets `environment = shellEnvironment.raw`.
- The PATH search must mirror the shell: iterate `pathEntries` left to right, skip non-directories, require the executable bit, and follow symlinks — recording **both** the symlink path and its resolved target, because duplicate detection (§8) depends on distinguishing them.

## 20.4 Installation state must be explicit

Replace the implicit "found / not found" with three explicit states:

| State | Meaning |
|---|---|
| `installedAndOnPath` | Executable exists and the resolved PATH reaches it |
| `installedNotOnPath` | Executable exists on disk but the resolved PATH does not reach it |
| `notInstalled` | No executable found in any known location |

`installedNotOnPath` is precisely the condition that confuses users most. Surfacing it is a core diagnostic feature, not an error state.

## 20.5 Optional shell integration

Ship the Phase 1 CLI (§14) as a binary inside the `.app` bundle and offer an opt-in "Install command-line tool" action that symlinks `agent-lens` into a directory already on the user's PATH. This provides scriptability and reinforces the "same engine, two front ends" architecture (§13).

---

# 21. Version & Update Detection Model

## 21.1 Problem

§3.1 lists "Latest version" as a single, always-available field. In practice it is not:

- **npm** — the registry exposes dist-tags; "latest" differs from "wanted" under semver ranges, and private registries may not respond.
- **Homebrew** — versions derive from formula/cask metadata plus local tap state.
- **pip / uv** — PyPI index lookups are comparatively slow and can be rate-limited.
- **cargo** — crates.io lookups.
- **Standalone / `curl | sh` installs** — there is **no registry at all**. "Latest" is genuinely unknowable for these.

If "Latest version" is presented as authoritative when it is only a guess, the headline feature ("2 updates available") becomes untrustworthy — and an unreliable status indicator is worse than no indicator.

## 21.2 Solution — tri-state version status

```swift
public enum VersionStatus: Sendable {
    case upToDate(installed: Version, latest: Version)
    case updateAvailable(installed: Version, latest: Version)
    case unknown(installed: Version, reason: UnknownReason)
}

public enum UnknownReason: Sendable {
    case noRegistry          // standalone install — expected, not an error
    case networkUnavailable
    case probeFailed
    case rateLimited
}
```

## 21.3 Rules

1. **Installed version is always local.** It comes from `--version` parsing and never depends on the network. It must remain available fully offline.
2. **Latest version is a separate, optional, asynchronous probe.** It is never required for the inventory to be useful.
3. **`unknown` is a first-class, neutral state.** Render it as a dash or "—". Never as an error, and never as "up to date".
4. **Batch, do not fan out.** Prefer one batched query per manager over N per-tool queries — for example a single `brew outdated --json=v2` instead of one call per formula. This reduces latency, rate-limit pressure, and process count.
5. **Cache with a TTL** (default 6 h), with an explicit manual refresh.
6. **Offline-first degradation.** If the network is unavailable, mark probes `unknown(.networkUnavailable)` and keep the rest of the inventory fully functional.
7. **Real version comparison, not string comparison.** Use semver-aware ordering per ecosystem, and handle prerelease, build metadata, and non-semver schemes (date-based, `1.x`).
8. **The update counter counts only `.updateAvailable`.** Unknowns must never inflate it.

## 21.4 Per-manager probe strategies

| Manager | Latest-version source |
|---|---|
| npm | `npm view <pkg> version --json`, or the registry HTTP API |
| Homebrew | `brew outdated --json=v2` (batched — preferred) |
| uv / pip | PyPI JSON API — `https://pypi.org/pypi/<pkg>/json` |
| cargo | crates.io API, or `cargo search` |
| standalone | none — always `unknown(.noRegistry)` |

---

# 22. Uninstall Policy

## 22.1 Problem

Deleting only the detected standalone executable (for example `~/.opencode/bin/opencode`) orphans the surrounding `node_modules`, caches, and configuration, and leaves a stale `$PATH` entry pointing at nothing. The user ends up with **more** clutter than before — the opposite of the product promise.

## 22.2 V1 policy matrix

| Installation method | V1 action |
|---|---|
| npm global package | Run `npm uninstall -g <package>` |
| Homebrew formula / cask | Run `brew uninstall <name>` |
| uv tool | Run `uv tool uninstall <package>` |
| cargo install | Run `cargo uninstall <package>` |
| standalone / curl installer | **Informational only** — show install root and link to official uninstall instructions; delete nothing |
| unknown / ambiguous | **Informational only** |

## 22.3 Additional rules

1. **Always show the exact command before execution**, following the confirmation pattern in §5.
2. **Capture and display stdout/stderr.** A failed uninstall must be visible, not silent.
3. **Never touch configuration or caches in V1** (§15 lists configuration files as an explicit non-goal).
4. **Rescan and show the delta** after the operation so the user sees the effect.
5. A future (non-MVP) "deep clean" mode may handle standalone install roots, but only behind an explicit manifest of everything that will be removed and a separate confirmation step.

---

# 23. Distribution, Signing & Sandbox Constraints

## 23.1 Problem

Agent Lens must spawn arbitrary user processes (`npm`, `brew`, user CLIs) and inspect arbitrary filesystem locations. This is incompatible with the App Sandbox and therefore makes the app **ineligible for the Mac App Store**. Separately, macOS Gatekeeper requires notarization for distribution outside the store.

## 23.2 Solution

1. **Sign with Developer ID**, enable the **hardened runtime**, and **notarize** the app. Distribute as a `.dmg` and as a **Homebrew cask** (`brew install --cask agent-lens`) — an appropriate channel given the target audience.
2. **Do not enable App Sandbox.** Record this decision and its rationale in the README so contributors do not attempt to sandbox the app.
3. **Minimize entitlements.** With no sandbox, no sandbox entitlements are required; avoid requesting entitlements the app does not demonstrably need.
4. **Use a signed updater** (for example Sparkle with EdDSA signatures) so the app can update itself outside the store.
5. **Phase 4 must include**: signing identity, a notarization step in CI, ticket stapling, and a release checklist.

---

# 24. Engagement & Retention

## 24.1 Problem

This is a low-frequency-use utility: a user scans, resolves duplicates, updates, and then does not reopen the app for weeks. Without a deliberate re-entry mechanism it risks becoming an impressive one-time demo.

## 24.2 Solution

1. **Menu-bar presence.** A status item showing "N updates available" (or a neutral icon when everything is clean) is the primary re-entry point.
2. **Rescan on launch**, rendering instantly from cached state and refreshing in the background.
3. **Optional scheduled check** (for example once daily) that only probes update status — no UI, no telemetry, opt-in.
4. **Proactive diagnostics.** Surface a badge when a duplicate install or a PATH conflict is detected (§8, §20.4). This is the feature most likely to bring the user back.
5. **Fast launch.** Target sub-300 ms to first render from cache. A slow utility does not get reopened.

---

# 25. Positioning: Diagnose First, Manage Second

## 25.1 Problem

§1 and §9 lead with the tool list and update counts. Updates are a commodity and, per §16.2, are delegated to existing package managers anyway. The defensible, memorable feature is the **diagnostic**: telling the user which AI CLI is actually running.

## 25.2 Solution

1. **Lead the narrative with diagnosis.** Primary pitch: *"Which AI CLI are you actually running?"* Agent Lens resolves PATH conflicts and duplicate installs, then offers management actions.
2. **Make diagnostics a first-class UI destination.** A top-level "Conflicts / Diagnostics" view, not a footnote to §8. Update counts become secondary metadata.
3. **Revise the one-sentence definition (§19)** to lead with diagnosis:

   > **Agent Lens is an open-source native macOS control center that tells you which AI agents, AI coding tools, and AI harnesses are actually installed and running on your Mac, explains PATH and duplicate conflicts, and offers simple, safe update and removal actions delegated to your existing package managers.**

4. **Sharpen OSS word-of-mouth.** The screenshot people share is the "you have three copies of opencode — this is the one that runs" view.

---

# 26. Risk Register

| # | Risk | Severity | Mitigation | Section |
|---|---|---|---|---|
| R1 | GUI app lacks shell PATH → false negatives and execution failure | High | Login-shell environment capture; explicit `installedNotOnPath` state | §20 |
| R2 | "Latest version" unknowable or unreliable | High | Tri-state model; batched probes; TTL cache; offline degradation | §21 |
| R3 | Standalone uninstall orphans files and stale PATH entries | Medium | Informational-only uninstall in V1 | §22 |
| R4 | No App Store eligibility; notarization required | Medium | Developer ID + notarization + Homebrew cask | §23 |
| R5 | Low retention — one-time-use tool | Medium | Menu-bar presence; proactive conflict badges; fast launch | §24 |
| R6 | Detector registry rot as the tool list grows | Medium | Versioned schema; per-detector fixture tests; CI validation | §27 |
| R7 | SwiftUI limitations for dense, sortable tables | Low | Fall back to `NSTableView` / `NSOutlineView` via `NSViewRepresentable` | §27 |
| R8 | Swift 6 strict concurrency with blocking `Process` | Low | Async continuations; bounded `TaskGroup` concurrency | §27 |
| R9 | Ecosystem consolidation shrinks the problem | Low | Neutral cross-vendor position is durable; keep expanding detector coverage | §18 |
| R10 | Scope creep toward "generic Mac cleaner" | Medium | Enforce §15 non-goals in code review | §15 |
| R11 | Solo non-coder builder — code coherence drifts across AI sessions; no way to verify correctness | High | Tests as acceptance criterion; one milestone per session; `DECISIONS.md`; commit-or-revert; consider a Swift-experienced co-maintainer | §28 |
| R12 | Multi-agent council is not genuinely independent; implementer grades its own work; branch divergence | High | Artifact-only review packets; orchestrator runs acceptance independently; one branch per milestone; reviewers read-only | §29 |

---

# 27. Implementation Notes (Swift 6 / SwiftUI)

1. **Module boundaries.** `AgentLensCore` (SPM, no UI framework imports) holds models, scanner, detectors, adapters, and operations. The `AgentLens` app target holds SwiftUI. Add a CI check that `AgentLensCore` does not import SwiftUI or AppKit, so the Phase 1 CLI (§14) and unit tests remain possible.
2. **Detector schema.** Use a versioned, declarative format (YAML or JSON) with a strict schema. Every detector ships with a fixture test, and CI validates all detectors against the schema so an invalid community contribution fails fast.
3. **Concurrency.** `Process` is blocking; wrap invocations in `withCheckedThrowingContinuation`. Run probes in a `TaskGroup` with **bounded** concurrency (for example 4–6) to avoid rate limits and process storms.
4. **Dense lists.** Use `NavigationSplitView` for the shell. If sortable multi-column presentation becomes painful in SwiftUI, drop to `NSTableView` / `NSOutlineView` through `NSViewRepresentable`. Mixed SwiftUI + AppKit is normal and not a compromise.
5. **Errors are values.** Every probe returns a typed result; nothing throws into the UI. The UI renders states, not exceptions.
6. **Testing.** Golden-file tests for the scanner against a synthetic filesystem; fixture-based tests per detector; snapshot tests for the inventory model.

---

# 28. Execution Model: Solo, Non-Coder Builder

## 28.1 Context

The builder has **no prior coding experience** and will direct AI coding tools rather than write code directly. This does not change *whether* Agent Lens can be built — it changes where the risk sits. The risk moves from "can this be written?" (yes, by an AI) to **"can it be verified, debugged, and kept coherent over many sessions?"** (the real question).

This section adjusts sequencing and working method. It does **not** change the product scope, architecture (§10, §13), or stack (§12).

## 28.2 The real bottleneck is verification, not generation

AI coding tools generate plausible Swift quickly. They are considerably weaker at knowing whether the result is *correct* in a system-integration context — and Agent Lens is almost entirely system integration.

The characteristic failure mode: the code compiles, the app launches, the output looks reasonable, and it is **subtly wrong** — for example, tools reported as missing because the login-shell PATH was never resolved (§20). Without a way to check, that error can survive for weeks.

Three non-negotiable working rules:

1. **Tests are the acceptance criterion.** "It works" is not evidence. Require a test that fails before the change and passes after it.
2. **Every scan result must be cross-checkable in a terminal.** If Agent Lens reports a tool as not installed, the builder must be able to run `which -a <tool>` and compare. Adopt a "show me the evidence" habit with the AI.
3. **Small increments.** One capability per change. If a change touches more than roughly two files, split it.

## 28.3 Revised milestone sequence

| Milestone | Deliverable | Acceptance criterion |
|---|---|---|
| **M0 — Toolchain** | Xcode installed; repo created per §13; empty Swift package | `swift build` exits 0 |
| **M1 — Walking skeleton** | `agent-lens scan` prints one hardcoded tool (no real detection) | Running it in Terminal prints the expected output |
| **M2 — Environment resolution (§20)** | `ShellEnvironment` implemented; debug command prints the resolved PATH | Printed PATH matches `echo $PATH` in the user's Terminal |
| **M3 — One real detector** | Detect a single tool (suggest `opencode` or `codex`): path + version | Output matches `which -a <tool>` and `<tool> --version` |
| **M4 — Detector schema + 3–5 tools** | Schema formalized (§27.2); M3 tool ported; 3–5 more added | Every detector has a fixture test |
| **M5 — Duplicate / PATH diagnostics** | The differentiator (§8, §25) | On a machine with two installs, correctly identifies which one PATH resolves to |
| **M6 — Version / update probing (§21)** | Tri-state model; Homebrew batch probe first | Offline run degrades to `unknown` without crashing |
| **M7 — First UI** | Menu-bar or single-window SwiftUI shell over the existing engine | UI shows the same inventory the CLI prints |

**M0–M2 are the critical path.** They answer the only question that matters early: *can the engine see the machine the way the shell does?* M7 is last deliberately — the UI is the most likely part to be abandoned, and the least important to the product's core value.

**Shipping target:** M5 or M6. A CLI that reliably reports what is installed, where it came from, and which copy PATH resolves to is already a legitimate, useful OSS project. The GUI is an enhancement, not the product.

## 28.4 Working method with AI tools

1. **Give the AI this document.** §13 (structure) and §27 (implementation notes) are the map. Keep them accurate — a stale map produces drifting code.
2. **One milestone per session.** Explicitly forbid scope expansion ("do not also refactor X").
3. **Require tests as the definition of done.** Make the AI write the failing test first.
4. **Keep a `DECISIONS.md`.** Record each technical choice and why, so later sessions do not re-litigate settled questions.
5. **Commit after every green test.** If a change breaks the build and cannot be fixed within ~15 minutes, revert it.
6. **Never paste credentials or tokens into a prompt.**
7. **Keep the engine free of UI imports** (§27.1). A non-coder cannot easily refactor a monolith later, so the boundary must be enforced from M1.

## 28.5 Prerequisites and costs

| Item | Requirement |
|---|---|
| Mac | ~40 GB free disk for Xcode |
| Xcode | Free — provides `swift`, `swift build`, and the debugger |
| Apple Developer Program | **$99/year** — needed only for notarized distribution (§23), **not** for local development. Defer until there is something worth shipping |
| GitHub account | For the OSS release (§17) |
| Backend / servers | None — §16.5 (zero backend) |

## 28.6 Honest risk assessment

- **Most likely outcome:** a working scanner covering a handful of tools. That is a genuine success and a shippable project.
- **Most likely failure point:** §20 (environment resolution). It is the highest-risk item and the least forgiving. Do it at M2, in isolation, before building anything on top of it.
- **Second most likely failure point:** long-horizon coherence — the code slowly drifting as AI sessions accumulate. Mitigated by §28.4.1–28.4.5.
- **De-risking option worth considering:** a co-maintainer with Swift experience. For an OSS project this is the single highest-leverage risk reduction available.
- **Fallback, not the plan:** if the Swift path stalls badly at M2, the same engine logic could be written as a Node/TypeScript CLI, where AI tools have substantially more training data and errors are easier to surface. Be aware this would force a re-evaluation of §12 (the UI would then likely become Tauri or Electron), which conflicts with the native-experience principle (§16.4). Treat it as a real fork, not a free swap.

## 28.7 Recommendation

Start with **M0 → M1 → M2**. Do not start with the UI. Do not start with the full tool list. The first three milestones are cheap, and they either validate the core premise or reveal that it needs rethinking — before any significant effort has been invested.

---

# 29. Multi-Agent Team Configuration

## 29.1 Declared setup

| Role | Model | Function |
|---|---|---|
| Orchestrator | ChatGPT Sol 6.1 | Judges, plans, orchestrates |
| Implementer | Gemini 3.8 Flash High | Writes code |
| Reviewers | 1–2 independent council members | Independent review |
| Platform | T3 Code (nightly channel) | Runs and coordinates all of the above |

## 29.2 What the platform actually provides

T3 Code is Ping.gg's MIT-licensed control surface for agent harnesses. Relevant facts as of 2026-10-11:

- It drives harnesses you already authenticate (Claude Code, Codex, Cursor, Grok Build, OpenCode, Antigravity) on your own subscriptions. No token resale.
- **Orchestrator V2** (shipped 2026-10-03 on the `v0.0.46-nightly` line) adds `delegate_task` — cross-provider **child agents** — plus a thread-control MCP and a restart-durable server queue. This is the exact mechanism the parent → implementer → reviewer structure depends on.
- **Every agent thread writes to its own git branch**, with a one-click thread → GitHub PR flow and inline diff review.
- Models can be **switched mid-thread**.
- Nightly-only releases; the project's own notice is "very early, expect bugs". The V1 → V2 database migration is **one-way**.

**Conclusion:** the architecture you describe is directly supported. The remaining risks are all matters of *protocol*, not capability — and they are the kind that silently produce wrong code.

## 29.3 Risk 1 — council independence is not automatic

`delegate_task` passes a task from a parent to a child. If the orchestrator forwards the implementer's **reasoning and self-justification** to the reviewers, the council inherits the implementer's blind spots and stops being a council. It becomes an echo chamber with extra steps.

**Protocol:**

- Reviewers receive **only the artifact**: the diff, the acceptance criterion, and the **raw, unedited command output**. Never the implementer's explanation of why the code is correct.
- Ask **adversarial, falsifiable questions** tied to the acceptance criterion — not "does this look right?" Example: *"Run `echo $PATH` in Terminal and compare byte-for-byte with the app's output. Report any difference. Do not comment on code style."*
- Reviewers must have terminal access. A reviewer that can only read prose is a rubber stamp.
- Use a **different model family** for the reviewer than the implementer where possible — same-family reviewers share training biases and tend to share blind spots.

## 29.4 Risk 2 — self-grading (the single most important protocol decision)

The implementer is capable of running the acceptance test. **It must not be the one that decides whether it passed.** An agent that both writes and grades its own work will pass itself, reliably and in good faith.

**Protocol:**

1. The implementer produces the change **and** the raw transcript of running the acceptance command.
2. The **orchestrator or a reviewer re-runs the acceptance command independently**, in a clean shell, and compares.
3. A milestone is not complete until the **orchestrator has personally observed a passing run**. "The implementer says it works" is not evidence (§28.2).

This single rule is worth more than the entire reviewer council.

## 29.5 Risk 3 — branch divergence

Every thread writing to its own branch is powerful for review and dangerous for a non-coder. Three branches touching the same files produce merge conflicts, and resolving a merge conflict is precisely the task you cannot do without coding experience.

**Protocol:**

- **One branch per milestone.** Not per agent, not per thread.
- The implementer's branch is the source of truth.
- Reviewers work **read-only** — they inspect and report; they do not push. If a reviewer proposes a fix, it returns to the implementer as a new task.
- The orchestrator performs the merge, and only after the acceptance run has passed.
- **Never let two agents edit the same file within the same milestone.**

## 29.6 Risk 4 — model fit per milestone

A flash-tier implementer is optimised for throughput, not for diagnosing subtle runtime behaviour. **M2 (§28.3, environment resolution) is a diagnostic problem**: the code will compile, look correct, and return the wrong PATH. Speed is irrelevant there; reasoning quality is everything.

**Protocol:**

- For **M2**, have the orchestrator implement it directly, or escalate the implementer to the strongest reasoning model for that milestone only. T3 Code supports switching models mid-thread — use it.
- Reserve the flash-tier implementer for high-volume, low-ambiguity work: M4's detector porting, boilerplate, fixture tests.
- General rule: **ambiguity → strongest reasoning model. Volume → fastest model.**

## 29.7 Risk 5 — nightly instability

T3 Code ships multiple nightly builds per day and describes itself as very early. The V1 → V2 migration is one-way.

**Protocol:**

- **Pin the T3 Code build for the duration of a milestone.** Upgrade only *between* milestones, never mid-milestone.
- **Back up the T3 Code data directory before any upgrade.** The migration cannot be reversed.
- Record the build string (for example `v0.0.46-nightly.20261003.2610`) in `DECISIONS.md` next to each milestone result, so a regression can be attributed to a tool update rather than to your code.

## 29.8 Risk 6 — the control surface is remote-capable

T3 Code can drive a machine running authenticated agents from iOS, Android, and web clients. That is convenient, and it is also a high-value target.

- Do not expose the T3 Code server to the public internet.
- Never paste credentials, tokens, or API keys into an agent thread (§28.4.6).

## 29.9 Ceremony should match stakes

| Work type | Team | Rationale |
|---|---|---|
| Architecture decisions (e.g. the detector schema, §27.2) | Full council | This is where independent review earns its cost |
| Routine milestones (M1, M4) | Orchestrator + implementer | A council per commit adds latency, not safety |
| M2 and M5 | Full council **plus** independent acceptance runs | Being wrong here is expensive and invisible |

## 29.10 Context allocation

Giving every agent the whole document is a common and costly mistake.

| Agent | Receives |
|---|---|
| Orchestrator | The full document + `DECISIONS.md` |
| Implementer | **Only the task brief** + the specific files in scope. Not the whole document — it dilutes focus and wastes context |
| Reviewers | Only the diff + the acceptance criterion + raw command output |

## 29.11 Task brief template

The orchestrator writes one of these per milestone. It is the implementer's entire world.

```text
MILESTONE:   M2 — Environment resolution
GOAL:        <one sentence, in terms of observable behaviour>
FILES:       <explicit allow-list>
DO NOT TOUCH:<everything else — say so explicitly>
ACCEPTANCE:  <exact command(s) + expected observable result>
EVIDENCE:    paste raw stdout/stderr of the acceptance command, unedited
DONE WHEN:   acceptance command passes AND a test was added AND transcript attached
```

The `DO NOT TOUCH` line matters more than it looks. Without it, an eager implementer will "helpfully" refactor neighbouring files, and a non-coder will not notice until much later.

## 29.12 Role summary

| Role | Responsibility | Must NOT do |
|---|---|---|
| Orchestrator | Holds the spec; plans; writes task briefs; **runs acceptance**; merges | Implement code; accept "it works" without a transcript |
| Implementer | Writes code and tests; produces raw command transcripts | Grade its own work; touch files outside the brief |
| Reviewer A | Adversarial check against the acceptance criterion | Read the implementer's justification; push code |
| Reviewer B | Second opinion on architecture and edge cases | Same as Reviewer A |
