# M0 — Toolchain

> **Hand this to the orchestrator.** The orchestrator may narrow it before passing it to the implementer.
> Acceptance is judged by the orchestrator, not the implementer (D-014).
> Read `briefs/README.md` first for the rules that apply to every brief.

---

## Goal

A Mac with a working Swift toolchain, and an empty Agent Lens repository that builds.

**No application logic. No detection. No UI.** This milestone exists to prove the toolchain works before anything depends on it.

---

## Part 1 — The builder does this (not an agent)

These steps are manual. An agent cannot install Xcode for you.

1. Install **Xcode** from the Mac App Store. It is free. Allow roughly 40 GB of disk.
2. Open Xcode once and let it finish installing its components.
3. Open **Terminal** and run:

   ```bash
   swift --version
   ```

   **Required:** a version string is printed, for example `swift-driver version: 1.xxx  Apple Swift version 6.x`.

If you see `command not found`, run `xcode-select --install` and try again. **Do not continue until `swift --version` works.** Nothing in this milestone can succeed without it.

---

## Part 2 — The agent does this

Create a Swift package **in the existing project folder**, so that `Package.swift` sits alongside `AGENT_LENS_SCOPE.md`:

```
Agent Lens/                      <- existing project folder
├── AGENT_LENS_SCOPE.md          <- already exists, do not modify
├── DECISIONS.md                 <- already exists, do not modify
├── Package.swift                <- create
├── .gitignore                   <- create
├── README.md                    <- create (one-paragraph stub)
├── Sources/
│   ├── AgentLensCore/
│   │   └── AgentLensCore.swift
│   └── agent-lens/
│       └── main.swift
└── Tests/
    └── AgentLensCoreTests/
        └── AgentLensCoreTests.swift
```

This layout implements **D-011**. It deliberately differs from the sketch in `AGENT_LENS_SCOPE.md` §13, which describes the destination layout including `App/` and `Features/` — those arrive at M7.

### Package.swift

- `swift-tools-version: 6.0`
- Platforms: `.macOS(.v14)` or later. Raise it if a later milestone needs a newer API.
- Three targets:
  - `AgentLensCore` — library
  - `agent-lens` — executable, depends on `AgentLensCore`
  - `AgentLensCoreTests` — test target, depends on `AgentLensCore`
- **No external dependencies.** The package must resolve with zero network access.

### .gitignore

Must include at minimum:

```
.build/
.swiftpm/
.DS_Store
*.xcodeproj
xcuserdata/
```

### Content

`AgentLensCore.swift` may be an empty placeholder or a single trivial function. `main.swift` should print something. The point is that it compiles, not that it does anything.

### Initialise git

```bash
git init
git add -A
git commit -m "M0: Swift package scaffold"
```

---

## DO NOT TOUCH

- `AGENT_LENS_SCOPE.md` — read-only reference
- `DECISIONS.md` — read-only reference
- `briefs/` — read-only reference

And do not create, in this milestone:

- Any detection logic
- Any detectors
- Any UI or SwiftUI code
- Any network code
- Any `Process` usage
- Any file outside the structure listed above

---

## Acceptance

Run in Terminal, from the project folder:

```bash
swift build
echo "exit code: $?"
```

**Required:** `exit code: 0`

```bash
swift run agent-lens
echo "exit code: $?"
```

**Required:** `exit code: 0`, and some output (any output).

```bash
swift test
echo "exit code: $?"
```

**Required:** `exit code: 0`

---

## Evidence required

Paste the **raw, unedited** terminal output of all three commands.

Do not summarise it. Do not write "it works". Do not paraphrase the exit codes.

---

## Done when

- [ ] `swift --version` prints a version string
- [ ] `swift build` exits 0
- [ ] `swift run agent-lens` exits 0 and prints something
- [ ] `swift test` exits 0
- [ ] The repository is under git with one commit
- [ ] Raw transcripts of all three commands are attached

---

## If it fails

| Symptom | Likely cause |
|---|---|
| `swift: command not found` | Xcode not installed, or command-line tools not selected |
| `xcodebuild: error: requires Xcode` | Xcode installed but not opened once, or licence not accepted. Run `sudo xcodebuild -license accept` |
| Build error in `Package.swift` | Tools version mismatch — check the installed Swift version against `swift-tools-version` |
| Package resolution tries to reach the network | An external dependency was added. There must be none |

---

## Note on the folder path

The project folder contains a space: `Projects Coding/Agent Lens`. This is fine for Swift and git. When writing shell commands by hand, quote the path: `cd "/Users/you/Documents/Projects Coding/Agent Lens"`.
