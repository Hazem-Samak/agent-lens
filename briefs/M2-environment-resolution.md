# M2 — Environment resolution

> ⚠️ **This is the highest-risk milestone in the project.**
> The code will compile, the output will look plausible, and the PATH will be subtly wrong.
> Do not let this milestone pass on visual inspection. Use the `diff` command below — it either prints `MATCH` or it does not.
>
> **Model assignment (§29.6):** the orchestrator implements this directly, or escalates the implementer to the strongest reasoning model for this milestone only. **Do not use the flash-tier implementer here.** This is diagnostic work, not typing work.

> **Hand this to the orchestrator.** Acceptance is judged by the orchestrator, not the implementer (D-014).
> Read `briefs/README.md` first for the rules that apply to every brief.

---

## Goal

`agent-lens debug-env` prints the environment Agent Lens will use to find tools — specifically a PATH that **matches the builder's Terminal**.

## Why this matters

A macOS application launched outside Terminal — from Finder, Spotlight, or any `.app` bundle — does **not** inherit the login shell's PATH. Entries added by `.zshrc`, `.zprofile`, `eval "$(brew shellenv)"`, `~/.local/bin`, `~/.opencode/bin`, `~/.cargo/bin` are all absent.

Without this milestone, every later milestone reports tools as "not installed" while they work perfectly in Terminal. **That failure is silent and looks like a detector bug.** By the time it is noticed, several milestones have been built on top of it.

This implements **D-005** and `AGENT_LENS_SCOPE.md` §20.

---

## Requirements

1. Determine the login shell from the password database — `getpwuid(getuid())->pw_shell`. **Do not read `$SHELL`** (it may be unset in a GUI context).
2. Launch a login **and interactive** shell, with sentinel markers around the environment dump:

   ```bash
   <shell> -l -i -c 'printf "\n__AGENTLENS_ENV_BEGIN__\n"; env -0; printf "__AGENTLENS_ENV_END__\n"'
   ```

   The `-i` flag is required so that `.zshrc` is read — without it the result will not match the user's interactive Terminal.
   The sentinels exist because rc files may print banners or prompts; everything outside the markers must be discarded.
   `env -0` uses NUL delimiters so that values containing newlines survive.

3. **Timeout of 3 seconds.** On timeout or failure, fall back to a documented default PATH and set `isDegraded = true`. Do not hang.
4. **Never `eval` or source rc files** into the app process. Capture output only.
5. **Cache the result** for the session.
6. Expose the result from `AgentLensCore` as:

   ```swift
   public struct ShellEnvironment: Sendable {
       public let shellPath: String        // e.g. /bin/zsh
       public let pathEntries: [String]    // ordered, as the shell would search them
       public let pathJoined: String       // the entries joined with ":"
       public let raw: [String: String]    // full environment, for Process
       public let isDegraded: Bool         // true when the fallback PATH was used
   }
   ```

7. **No other code may read `ProcessInfo.processInfo.environment["PATH"]`** for discovery or execution. Add a comment saying so at the top of the file.

---

## Required output format

`agent-lens debug-env` prints exactly this shape. Field labels are lowercase; alignment whitespace is not significant.

```
shell:       /bin/zsh
degraded:    false
path_joined: /Users/you/.local/bin:/opt/homebrew/bin:/usr/bin:/bin
path_entries:
  /Users/you/.local/bin
  /opt/homebrew/bin
  /usr/bin
  /bin
```

- `path_joined` is on **one line** — this is what the acceptance test compares.
- `path_entries` is for humans to read.
- Exit code 0.

---

## DO NOT TOUCH

- `AGENT_LENS_SCOPE.md`, `DECISIONS.md`, `briefs/` — read-only reference
- `Package.swift` — no dependencies

And do not write, in this milestone:

- Any tool detection
- Any detectors
- Any version probing
- Any network calls
- Any UI or SwiftUI code
- Any code that inspects installed tools

Confine changes to a new `Sources/AgentLensCore/Environment/` directory and the executable's command dispatch.

---

## Acceptance

Run in Terminal, from the project folder. Copy these exactly.

```bash
swift build
```

Then:

```bash
.build/debug/agent-lens debug-env | grep '^path_joined: ' | sed 's/^path_joined: //' > /tmp/agentlens_path.txt
echo "$PATH" > /tmp/shell_path.txt
diff /tmp/agentlens_path.txt /tmp/shell_path.txt && echo "MATCH"
```

**Required:** the word `MATCH` is printed, and the exit code is 0.

If `diff` prints any lines, the milestone has **failed**, even if the output looks close.

Also verify the shell detection:

```bash
.build/debug/agent-lens debug-env | grep '^shell:'
echo "$SHELL"
```

**Required:** the same shell path in both.

And confirm the degraded flag:

```bash
.build/debug/agent-lens debug-env | grep '^degraded:'
```

**Required:** `degraded: false` on the builder's machine. If it is `true`, the fallback is being used and the milestone has failed.

---

## If `diff` reports a difference

The implementer must **explain exactly why** before the milestone can be considered passed. A difference is not automatically a bug — but it must be *demonstrated*, never asserted.

The most likely legitimate cause: the shell modifies PATH on each interactive prompt (some prompt frameworks do this), so `echo "$PATH"` in an interactive Terminal differs from what a one-shot `-l -i -c` invocation produces. If that is the case, demonstrate it — for example by showing that a second `-l -i -c` invocation produces a stable, consistent result — and record the explanation in `DECISIONS.md` as a new entry.

"I think it's close enough" is not an acceptable explanation.

---

## Evidence required

Paste the **raw, unedited** terminal output of:

1. `swift build`
2. The `diff` block, including the `MATCH` line
3. The shell comparison
4. The degraded flag
5. `swift test`

Do not summarise. Do not write "it works".

---

## Done when

- [ ] `agent-lens debug-env` prints `shell:`, `degraded:`, `path_joined:`, and `path_entries:`
- [ ] `diff` reports `MATCH` with exit code 0
- [ ] `shell:` matches `$SHELL`
- [ ] `degraded:` is `false`
- [ ] A unit test covers parsing the sentinel-delimited output, including a value containing a newline
- [ ] A unit test covers the timeout fallback path, asserting `isDegraded == true` and that the default PATH is used
- [ ] A unit test asserts that the raw environment is passed through for `Process`
- [ ] `swift test` exits 0
- [ ] Raw transcripts of all five items above are attached
- [ ] One commit on the milestone branch

---

## If it fails

| Symptom | Likely cause |
|---|---|
| `path_joined` is missing entries that are in `$PATH` | The shell was launched without `-i`, so `.zshrc` was not read |
| `path_joined` contains a banner, prompt text, or version output | The sentinel markers are not being stripped correctly |
| `path_joined` is the bare system default | The shell invocation failed and the fallback is being used — check `degraded:` |
| The command hangs | No timeout is implemented, or the shell is waiting on input |
| `path_joined` matches but `path_entries` is empty | Parsing bug — the entries list is derived incorrectly from the joined value |
| Values containing `=` or newlines are mangled | The dump is not NUL-delimited, or is being split on the wrong character |
| `shell:` is empty or wrong | `$SHELL` is being read instead of the password database |

---

## What M3 will build on this

M3 detects a single real tool. It will use `ShellEnvironment` to resolve the executable, and it must be able to report `installedNotOnPath` (D-006).

If M2 is wrong, M3 will report tools as missing. **That is the failure this milestone exists to prevent.**
