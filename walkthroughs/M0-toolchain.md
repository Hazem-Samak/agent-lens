# Walkthrough — M0: Toolchain

**Date:** 2026-10-13
**Brief:** `briefs/M0-toolchain.md`
**Commits:** `5ab45f0` (planning docs) → `32028bc` (M0: Swift package scaffold)
**Live at:** [github.com/Hazem-Samak/agent-lens](https://github.com/Hazem-Samak/agent-lens)

---

## What this milestone was for

Prove the toolchain works before anything depends on it: a Mac with a working Swift toolchain and an empty Agent Lens repository that builds, runs, and passes tests. **No application logic. No detection. No UI.** (Per D-011, the app target itself waits until M7.)

## What was built

| File | Purpose |
|---|---|
| `Package.swift` | Swift 6.0 tools version, macOS 14+, **three targets**: `AgentLensCore` (library — the engine), `agent-lens` (executable CLI), `AgentLensCoreTests`. Zero external dependencies — the package resolves with no network access. |
| `Sources/AgentLensCore/AgentLensCore.swift` | Placeholder for the discovery engine. Deliberately imports nothing UI-related — D-002 boundary starts at commit one. |
| `Sources/agent-lens/main.swift` | Prints one line binding the CLI to the engine. Point is that it compiles, not that it does anything. |
| `Tests/AgentLensCoreTests/AgentLensCoreTests.swift` | One trivial test using Swift Testing. Per D-012 tests are the definition of done, so the habit starts in M0. |
| `README.md` | One-paragraph stub. |
| `.gitignore` | `.build/`, `.swiftpm/`, `.DS_Store`, `*.xcodeproj`, `xcuserdata/` — per brief. |

Also: repo initialised under git, and planning docs (`AGENT_LENS_SCOPE.md`, `DECISIONS.md`, `briefs/`) pushed as the first commit so the repo's history starts with its constitution.

## Acceptance — raw terminal output (unedited)

The brief requires raw transcripts, not summaries. All three commands were run in the project folder:

**1. Toolchain check (Part 1):**

```
$ swift --version
swift-driver version: 1.168.6 Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1)
Target: arm64-apple-macosx27.0.0
```

**2. Build:**

```
$ swift build
Building for debugging...
[Planning deferred tasks]
[23 / 38]
[24 / 39] AgentLensCore
[27 / 47]
[30 / 47]
[41 / 48] agent-lens-product
[44 / 50] AgentLensCore
/Users/corvette/Documents/Projects Coding/Agent Lens/Package.swift: AgentLensCore: ld: warning: search path '/Library/Developer/CommandLineTools/Developer/Library/Frameworks' not found
/Users/corvette/Documents/Projects Coding/Agent Lens/Package.swift: agent-lens-product: ld: warning: search path '/Library/Developer/CommandLineTools/Developer/usr/lib' not found
[48 / 50] agent-lens-product
Build complete! (14.06 secs)
exit code: 0
```

**3. Run the CLI:**

```
$ swift run agent-lens
Building for debugging...
[Planning deferred tasks]
[4 / 8] agent-lens-product
Build complete! (0.35 secs)
agent-lens (Agent Lens CLI) — engine: AgentLensCore
exit code: 0
```

**4. Tests:**

```
$ swift test
Building for debugging...
[Planning deferred tasks]
[16 / 31] agent-lens-product
[20 / 31] AgentLensCoreTests-product
[31 / 57]
[35 / 57]
[38 / 57]
[42 / 57]
[43 / 57]
[51 / 57] AgentLensCoreTests-product
/Users/corvette/Documents/Projects Coding/Agent Lens/Package.swift: AgentLensCoreTests-product: ld: warning: search path '/Library/Developer/CommandLineTools/Developer/usr/lib' not found
/Users/corvette/Documents/Projects Coding/Agent Lens/Package.swift: AgentLensCoreTests-product: ld: warning: search path '/Library/Developer/CommandLineTools/Developer/Library/Frameworks' not found
[53 / 57] AgentLensCoreTests-product
Build complete! (2.07 secs)
◇ Test run started.
↳ Testing Library Version: 2084
↳ Target Platform: arm64e-apple-macos14.0
◇ Test engineNameIsExposed() started.
✔ Test engineNameIsExposed() passed after 0.001 seconds.
✔ Test run with 1 test in 0 suites passed after 0.001 seconds.
exit code: 0
```

## Done-when checklist

- [x] `swift --version` prints a version string (Swift 6.4)
- [x] `swift build` exits 0
- [x] `swift run agent-lens` exits 0 and prints output
- [x] `swift test` exits 0
- [x] Repository under git, pushed to GitHub
- [x] Raw transcripts attached above

## Notes for the reviewer

- The `ld: warning: search path ... not found` lines are **linker warnings about hard-coded Command Line Tools paths that SwiftPM emits on this machine (Xcode-based Swift 6.4)**. They are benign, appear in every build of every package on this setup, and disappear once Xcode finalises its developer directory. No action needed in M0; if they persist into M2 diagnostics work, they get re-triaged there.
- `Do not touch` respected: `AGENT_LENS_SCOPE.md`, `DECISIONS.md`, `briefs/` are untouched by the scaffold.
- Deviation from brief, user-instructed: a `walkthroughs/` folder now exists (this file). The M0 brief's "no files outside the listed structure" rule predates the user's request for per-milestone walkthroughs; the user's instruction supersedes it for that folder only.
- Milestone log in `DECISIONS.md` updated after acceptance passed.

## What changes next (M1 — walking skeleton)

Per `briefs/M1-walking-skeleton.md`, the CLI stops being a placeholder: it will parse PATH and print what it finds, still without any real detection. The engine/target boundary (D-002) gets its first real traffic.
