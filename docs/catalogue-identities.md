# Catalogue identities — M11-A frozen identity packet

Status: **frozen research artifact, revision 1, 2026-11-12.** This document is the M11-A
deliverable. Later coding phases may copy these rows; they must not re-derive identity from
memory, a proposal, or a local installation. A correction here requires a new revision brief.

- Milestone: M11, phase A. Branch `milestone/m11-catalogue`.
- Baseline: `d98bf7be3e81e0a659757ab19d1c76bd301617c2` (frozen master plan), on top of `d0a2b41`.
  Dispatch HEAD observed: `197d6323b2707bce6eab43f65458974db3cae19a`. During the phase HEAD
  advanced externally to `93c169dfcfee728342c48b4a2b5bc05fa62d807e` (“docs: record owner
  authorizations for M11 execution”), which touches `ROADMAP.md` and `briefs/` only. The worker
  made no Git mutation.
- Sole implementer: DeepSeek V4.1 Flash 1017 via OMP. Orchestrator owns review, acceptance, and
  all Git delivery. This phase made no Git mutations.
- Evidence root `R`: `/Users/corvette/.hermes/cache/scratch/agent-lens-m11-Jb11B5`.
  In this document `E/` means `R/evidence/`. Raw registry snapshots, page captures, scripts,
  measurement JSON, and logs are under `E/`.
- Repository file created: this document only. No registry, source, test, script, CI, brief,
  walkthrough, README, DECISIONS, ROADMAP, or scope edit.

## How to read the marks

| Mark | Meaning in this packet |
|---|---|
| `verified-docs` | Re-confirmed against a primary vendor source (official docs, official repository, npm/PyPI/Homebrew registry listing, or the vendor's install script read as text) during this phase. The source URL and fetch date are on the row. |
| `observed-local` | Measured read-only on this machine during this phase. The raw output is in `E/local/` or `E/scratch/`. Local measurements are evidence about this machine only; they are never registry pins. |
| `unverified` | Could not be confirmed. The row states exactly what is missing and what would resolve it. |
| `binding-plan` | A value fixed by the frozen M11 plan or an owner ruling, not an external observation. It is not an evidence upgrade. Source: `briefs/M11-plan.md` §4, `briefs/M11-planning/judgment.md`, or the named OD. |

A `held` entry would mean the version flag could not be confirmed by primary docs **and** could
not be measured. No entry is held. Every version flag below was confirmed and every query shape
was measured.

## Frozen identity summary

All 14 entries are frozen. “Packages” are declared candidates only; a declaration is never
ownership or install proof (M9/M11 contract).

| id | Vendor / project | Executable | Category | Declared candidates (manager: name) | Fixture (synthetic) | Version shape |
|---|---|---|---|---|---|---|
| `codex` | OpenAI — Codex CLI | `codex` | `aiAgent` | npm `@openai/codex`; cask `codex` | `npmGlobal` / `npm` | measured |
| `opencode` | Anomaly — OpenCode | `opencode` | `aiAgent` | npm `@opencode/cli`, `opencode-ai`; formulae `anomalyco/tap/opencode-v2`, `anomalyco/tap/opencode`, `opencode` | `singleDirectory` / `standalone` | measured |
| `grok` | xAI — Grok CLI | `grok` | `aiAgent` | none | `singleDirectory` / `standalone` | measured |
| `claude` | Anthropic — Claude Code | `claude` | `aiAgent` | npm `@anthropic-ai/claude-code`; casks `claude-code`, `claude-code@latest` | `singleDirectory` / `standalone` | measured (scratch) |
| `gemini` | Google — Gemini CLI | `gemini` | `aiAgent` | npm `@google/gemini-cli`; formula `gemini-cli` | `npmGlobal` / `npm` | measured (scratch) |
| `cline` | Cline — Cline CLI | `cline` | `aiAgent` | npm `cline`; formula `cline` | `npmGlobal` / `npm` | measured |
| `hermes` | Nous Research — Hermes Agent | `hermes` | `aiAgent` | formula `hermes-agent` | `singleDirectory` / `standalone` | measured |
| `aider` | Aider-AI — Aider | `aider` | `aiCodingTool` | formula `aider` | `singleDirectory` / `standalone` | measured (scratch) |
| `goose` | Agentic AI Foundation — Goose | `goose` | `aiCodingTool` | formula `block-goose-cli` | `singleDirectory` / `standalone` | measured (scratch) |
| `kiro-cli` | Amazon / Kiro — Kiro CLI | `kiro-cli` | `aiCodingTool` | cask `kiro-cli` | `singleDirectory` / `standalone` | measured (scratch) |
| `qodercli` | Qoder — Qoder CLI | `qodercli` | `aiCodingTool` | npm `@qoder-ai/qodercli` | `singleDirectory` / `standalone` | measured |
| `dsh` | DeepSeek AI — DeepSeek Harness | `dsh` | `aiHarness` | npm `@deepseek-ai/dsh` | `npmGlobal` / `npm` | measured |
| `omp` | Oh My Pi — OMP | `omp` | `aiHarness` | npm `@oh-my-pi/pi-coding-agent`; formula `can1357/tap/omp` | `singleDirectory` / `standalone` | measured |
| `agy` | Google — Antigravity CLI | `agy` | `aiHarness` | cask `antigravity-cli` | `singleDirectory` / `standalone` | measured (cask artifact) |

## Entry records

**Citation convention.** Each entry starts with a `Sources:` line listing every URL used by that
entry's `verified-docs` rows. The short evidence labels inside the table (`npm metadata`,
`formula page`, `cask JSON`, `install docs`, `install script`) refer to those URLs. The appendix
§D and §E reproduce the registry and documentation URLs with fetch status. `observed-local` rows
cite the raw file under `E/`; `binding-plan` rows cite the plan.

### 1. `codex` — Codex (OpenAI)

**Sources:** https://github.com/openai/codex; https://chatgpt.com/codex/install.sh; https://registry.npmjs.org/@openai%2Fcodex/0.167.2; https://formulae.brew.sh/cask/codex; https://formulae.brew.sh/formula/codex; https://developers.openai.com/codex/cli

| Field | Frozen value | Mark | Evidence |
|---|---|---|---|
| Vendor / project | OpenAI, Codex CLI; repository `openai/codex` | `verified-docs` | https://github.com/openai/codex (README, fetched 2026-11-12) |
| Executable | `codex` | `verified-docs` | README; install script writes `$HOME/.local/bin/codex` |
| Category | `aiAgent` | `binding-plan` | `briefs/M11-plan.md` §4 |
| Fixture | synthetic `npmGlobal` / `npm` | `binding-plan` + `observed-local` | plan §4; npm-global layout measured below |
| npm candidate | `@openai/codex` 0.167.2, bin `codex -> bin/codex.js`, repo `openai/codex`, Apache-2.0, Node >= 16 | `verified-docs` | https://registry.npmjs.org/@openai%2Fcodex/0.167.2 |
| Homebrew cask candidate | `codex` 0.167.2, artifact `bin/codex` → `$HOMEBREW_PREFIX/bin/codex`, `auto_updates: false` | `verified-docs` | https://formulae.brew.sh/cask/codex |
| No formula candidate | Homebrew formula `codex` is 404; the cask is the live Homebrew listing. Do not declare a formula. | `verified-docs` | https://formulae.brew.sh/formula/codex (404, 2026-11-12) |
| npm-global layout | `<prefix>/lib/node_modules/@openai/codex/bin/codex.js`; `<prefix>/bin/codex` symlink. Measured at `~/.local` and `/opt/homebrew` prefixes. | `observed-local` | `E/local/layouts.txt` |
| Standalone installer layout | `CODEX_INSTALL_DIR` default `$HOME/.local/bin`; wrapper `$HOME/.local/bin/codex`; `CODEX_HOME` default `$HOME/.codex`; releases under `$CODEX_HOME/packages/standalone/releases/`, selected by `$CODEX_HOME/packages/standalone/current`; optional `codex-code-mode-host` beside the wrapper | `verified-docs` | https://releases.openai.com/codex/install.sh (redirect of https://chatgpt.com/codex/install.sh; read, never executed) |
| Cask layout | artifact maps `bin/codex` → `$HOMEBREW_PREFIX/bin/codex`; Caskroom tree was not installed or observed | `verified-docs` (mapping) / `unverified` (tree) | https://formulae.brew.sh/cask/codex |
| Version query | argv `["--version"]`; stream `stdout`; line `first`. Raw measured line: `codex-cli 0.167.0`. First token `0.167.0`. | `observed-local` | `E/local/codex-homebrew-prefix.json` |
| Version failure case | User-prefix copy exits 1, stderr begins `Error: Missing optional dependency @openai/codex-darwin-arm64.` → version unknown, not an error | `observed-local` | `E/local/codex-user-local.json` |
| Information URL | `https://developers.openai.com/codex/cli`. It returns 200 via redirect to `https://learn.chatgpt.com/docs/codex/cli` (canonical tag), which is a live install page with standalone, npm, and Homebrew tabs. Recommendation: **keep** the current URL; the redirect absorbs the host migration, and the GitHub README remains the install authority. | `verified-docs` | both URLs fetched 2026-11-12; `E/docs/codex-cli-headers.txt` |
| Uninstall instructions | None published in the official README or the fetched CLI docs page. | `verified-docs` (absence on reviewed pages) | README and CLI page; no uninstall section found |

**Known limits.**

- Two local npm copies exist (`~/.local` 0.167.2, `/opt/homebrew` 0.167.0). The `/opt/homebrew`
  copy is npm under a prefix, not a formula: `classifySource` sees `/lib/node_modules/`. `observed-local`.
- The user-prefix copy's missing optional dependency is an install defect on this machine, not a
  catalogue identity. It makes the version unknown; it must not make the tool an error. `observed-local`.
- The cask and standalone installer both classify `standalone`; cask ownership is not M11. `binding-plan`.
- The vendor update path is an installer rerun (`curl ... install.sh | sh`); it is never an Agent
  Lens operation. `verified-docs` (CLI page “Update Codex”).
- Cask `auto_updates: false`; `brew upgrade` is a future Homebrew-adapter concern, not M11. `verified-docs`.

### 2. `opencode` — OpenCode (Anomaly)

**Sources:** https://opencode.ai/v2/install; https://opencode.ai/docs/; https://opencode.ai/docs/cli/; https://registry.npmjs.org/@opencode%2Fcli/2.2.7; https://registry.npmjs.org/opencode-ai/1.19.5; https://formulae.brew.sh/formula/opencode; https://raw.githubusercontent.com/anomalyco/homebrew-tap/master/opencode-v2.rb; https://raw.githubusercontent.com/anomalyco/homebrew-tap/master/opencode.rb

| Field | Frozen value | Mark | Evidence |
|---|---|---|---|
| Vendor / project | Anomaly, OpenCode; repository `anomalyco/opencode` | `verified-docs` | https://github.com/anomalyco/opencode; npm metadata |
| Executable | `opencode` | `verified-docs` | installer and docs |
| Category | `aiAgent` | `binding-plan` | plan §4 |
| Fixture | synthetic `singleDirectory` / `standalone` | `binding-plan` + `observed-local` | plan §4; standalone tree measured |
| npm candidate | `@opencode/cli` 2.2.7, bins `opencode` and `opencode2` -> `bin/opencode.exe`, repo `anomalyco/opencode`, MIT | `verified-docs` | https://registry.npmjs.org/@opencode%2Fcli/2.2.7 |
| npm candidate | `opencode-ai` 1.19.5, bin `opencode -> bin/opencode.exe`; repository field absent in registry metadata; version aligns with the v1 tap | `verified-docs` | https://registry.npmjs.org/opencode-ai/1.19.5 |
| Formula candidate (tap) | `anomalyco/tap/opencode-v2` 2.2.7, installs `opencode`, conflicts with `opencode` | `verified-docs` | https://raw.githubusercontent.com/anomalyco/homebrew-tap/master/opencode-v2.rb |
| Formula candidate (tap) | `anomalyco/tap/opencode` 1.19.5, installs `opencode` | `verified-docs` | https://raw.githubusercontent.com/anomalyco/homebrew-tap/master/opencode.rb |
| Formula candidate (core) | `opencode` 2.2.7, binary `opencode` | `verified-docs` | https://formulae.brew.sh/formula/opencode |
| Standalone layout | `INSTALL_DIR=$HOME/.opencode/bin`; binary `opencode`; `opencode2` is a 47-byte shell shim that execs `opencode` in the same directory | `verified-docs` + `observed-local` | https://opencode.ai/v2/install; `E/local/layouts.txt` |
| npm-global layout | `<prefix>/lib/node_modules/@opencode/cli/bin/opencode.exe`; symlinks `opencode` and `opencode2` | `verified-docs` | npm metadata; layout pattern |
| Homebrew layout | core and both tap formulae install a `Cellar/.../bin/opencode`; no Cellar tree was installed or observed | `verified-docs` (formulae) / `unverified` (tree) | formula and tap files |
| Version query | argv `["--version"]`; stream `stdout`; line `first`. Raw measured: `opencode v2.2.7`. First token `2.2.7`. The same line comes from `opencode2`. | `observed-local` | `E/local/opencode-offpath.json`, `E/local/opencode2-offpath.json` |
| Information URL | `https://opencode.ai/docs/` (current; the old `https://opencode.ai/v2/docs/` redirects here; canonical is the `/docs/` tree). | `verified-docs` | fetch log 2026-11-12 |
| Uninstall instructions | `https://opencode.ai/docs/cli/#uninstall` — documents `opencode uninstall --dry-run` and `opencode uninstall`; the vendor self-uninstaller is not an Agent Lens operation. | `verified-docs` | https://opencode.ai/docs/cli/ |

**Known limits.**

- `opencode2` is a second executable name in both the npm package and the standalone directory.
  It is a known limit, not a second detector. `binding-plan` + `observed-local`.
- Both tap formulae install `opencode`, and the v2 tap declares `conflicts_with "opencode"`; only
  one Homebrew copy can own the binary. `verified-docs` (tap formula).
- `opencode-ai` 1.19.5 aligns with the v1 tap; `@opencode/cli` 2.2.7 aligns with v2. The registry
  may declare both as candidates, but neither is ownership proof. `verified-docs` (npm metadata)
  + `binding-plan`.
- The desktop cask `opencode-desktop` is a different surface and is never declared. `verified-docs`.
- `~/.opencode/bin` is off the login-shell PATH on this machine; off-PATH detection is a search
  policy concern, not an identity change. `observed-local`.
- No tap or Cellar tree was installed; declarations are not install proof. `binding-plan`.

### 3. `grok` — Grok CLI (xAI)

**Sources:** https://docs.x.ai/build/overview; https://x.ai/cli/install.sh

| Field | Frozen value | Mark | Evidence |
|---|---|---|---|
| Vendor / project | xAI, Grok CLI | `verified-docs` | https://docs.x.ai/build/overview |
| Executable | `grok` | `verified-docs` | docs install command |
| Category | `aiAgent` | `binding-plan` | plan §4 |
| Fixture | synthetic `singleDirectory` / `standalone` | `binding-plan` + `observed-local` | plan §4; local layout measured |
| Declared packages | none | `verified-docs` | No npm or Homebrew package is documented on the fetched official pages; do not invent one. |
| Standalone layout | `GROK_BIN_DIR` default `$HOME/.grok/bin`; `grok` symlink → `$HOME/.grok/downloads/grok-<version>-macos-<arch>`; installer also symlinks into the first writable PATH directory, preferring `$HOME/.local/bin` then `/usr/local/bin`; it adds `~/.grok/bin` to shell config | `verified-docs` | https://x.ai/cli/install.sh (read, never executed) |
| Observed layout | `~/.local/bin/grok` → `~/.grok/bin/grok` → `~/.grok/downloads/grok-1.0.77-macos-aarch64` (Mach-O arm64) | `observed-local` | `E/local/layouts.txt` |
| Extra search root | `~/.grok/bin` (existing registry value; confirmed by the observed layout) | `observed-local` + `binding-plan` | `E/local/layouts.txt` |
| Version query | argv `["--version"]`; stream `stdout`; line `first`. Raw measured: `grok 1.0.77 (50ca579fa996) [stable]`. First token `1.0.77`; the hash and `[stable]` are noise. | `observed-local` | `E/local/grok.json` |
| Information URL | `https://docs.x.ai/build/overview` | `verified-docs` | page fetched 2026-11-12 |
| Uninstall instructions | None published on the fetched official overview; the install script is a vendor-owned layout. | `verified-docs` (absence on reviewed page) | https://docs.x.ai/build/overview |

**Known limits.**

- No package identity is declared. A package invented for Grok would be a defect. `binding-plan`.
- The version line contains a build hash and channel token after the version; first-match
  extraction handles it. `observed-local`.
- The downloaded filename is versioned (`grok-1.0.77-macos-aarch64`); a versioned runtime filename
  is a personal artifact and never a root, layout, or fixture. `observed-local` + `binding-plan`.
- The installer writes shell config to keep `~/.grok/bin` on PATH. That is vendor behavior, not an
  Agent Lens operation. `verified-docs` (script).
- A symlink in `~/.local/bin` classifies `standalone`, not Homebrew. `binding-plan` (source heuristic).

### 4. `claude` — Claude Code (Anthropic)

**Sources:** https://code.claude.com/docs/en/setup; https://claude.ai/install.sh; https://registry.npmjs.org/@anthropic-ai%2Fclaude-code; https://formulae.brew.sh/cask/claude-code; https://formulae.brew.sh/cask/claude-code@latest

| Field | Frozen value | Mark | Evidence |
|---|---|---|---|
| Vendor / project | Anthropic, Claude Code | `verified-docs` | https://code.claude.com/docs/en/setup |
| Executable | `claude` | `verified-docs` | setup docs and npm metadata |
| Category | `aiAgent` | `binding-plan` | plan §4 |
| Fixture | synthetic `singleDirectory` / `standalone` | `binding-plan` + `verified-docs` | plan §4; native launcher is a single directory; fixture does not reproduce `versions/` |
| npm candidate | `@anthropic-ai/claude-code` 2.1.322, bin `claude -> bin/claude.exe`, Node >= 22, per-platform optional dependency (e.g. `@anthropic-ai/claude-code-darwin-arm64`) linked by postinstall | `verified-docs` | https://registry.npmjs.org/@anthropic-ai%2Fclaude-code; https://code.claude.com/docs/en/setup |
| Cask candidate (stable) | `claude-code` 2.1.311, artifact `claude` → `$HOMEBREW_PREFIX/bin/claude`, `auto_updates: false` | `verified-docs` | https://formulae.brew.sh/cask/claude-code |
| Cask candidate (latest) | `claude-code@latest` 2.1.322, artifact `claude` → `$HOMEBREW_PREFIX/bin/claude`, `auto_updates: false` | `verified-docs` | https://formulae.brew.sh/cask/claude-code@latest |
| Native layout | `~/.local/bin/claude` is a symlink into `~/.local/share/claude/versions/`; bootstrap downloads into `~/.claude/downloads` and runs the downloaded binary's `install` subcommand; installer puts everything under `$HOME` | `verified-docs` | setup docs; https://downloads.claude.ai/claude-code-releases/bootstrap.sh (read, never executed) |
| npm-global layout | `<prefix>/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe`; platform binary in `<prefix>/lib/node_modules/@anthropic-ai/claude-code-darwin-arm64/claude`; postinstall links the native binary | `verified-docs` | setup docs; scratch install |
| Cask layout | artifact maps `claude` → `$HOMEBREW_PREFIX/bin/claude`; Caskroom tree not observed | `verified-docs` (mapping) / `unverified` (tree) | cask JSON |
| Version query | argv `["--version"]`; stream `stdout`; line `first`. Raw measured (scratch install): `2.1.322 (Claude Code)`. First token `2.1.322`. Docs show the same shape for 2.1.211 and 2.1.89. | `verified-docs` + `observed-local` | setup docs; `E/scratch/claude-version.json` |
| Information URL | `https://code.claude.com/docs/en/setup` | `verified-docs` | page fetched 2026-11-12 |
| Uninstall instructions | `https://code.claude.com/docs/en/setup#uninstall-claude-code` — covers native, Homebrew casks, npm, and config cleanup. | `verified-docs` | setup page |

**Known limits.**

- The fixture `singleDirectory`/`standalone` proves classification only. It does not reproduce the
  `~/.local/bin/claude` → `~/.local/share/claude/versions/` symlink. `versions/` is a version store,
  not an `extraSearchRoots` entry. `verified-docs` + `binding-plan`.
- Native installations auto-update in the background; `claude update` and `claude install` are
  vendor self-update operations, never Agent Lens operations. `verified-docs`.
- The npm package relies on an optional platform dependency and a postinstall link. A missing
  optional dependency yields an unknown version, not a product error. `verified-docs` + `observed-local`
  (the analogous Codex failure is the measured example).
- Both casks classify `standalone` (outside `Cellar`); cask ownership is not M11. `binding-plan`.
- The stable and latest casks are separate channels; do not collapse them into one name.
  `verified-docs`.

### 5. `gemini` — Gemini CLI (Google)

**Sources:** https://geminicli.com/docs/get-started/installation/; https://geminicli.com/docs/resources/uninstall/; https://registry.npmjs.org/@google%2Fgemini-cli; https://formulae.brew.sh/formula/gemini-cli

| Field | Frozen value | Mark | Evidence |
|---|---|---|---|
| Vendor / project | Google, Gemini CLI; repository `google-gemini/gemini-cli` | `verified-docs` | https://github.com/google-gemini/gemini-cli; npm metadata |
| Executable | `gemini` | `verified-docs` | installation docs; formula binary list |
| Category | `aiAgent` | `binding-plan` | plan §4; scope §2 names it (OD-6 keep) |
| Fixture | synthetic `npmGlobal` / `npm` | `binding-plan` | plan §4 |
| npm candidate | `@google/gemini-cli` 0.68.0, bin `gemini -> bundle/gemini.js`, repo `google-gemini/gemini-cli`, Apache-2.0, Node >= 20 | `verified-docs` | https://registry.npmjs.org/@google%2Fgemini-cli |
| Formula candidate | `gemini-cli` 0.68.0, binary `gemini`; **deprecated 2026-06-18**, reason `unsupported`; **disabled 2026-12-18**; recommended replacement cask `antigravity-cli` | `verified-docs` | https://formulae.brew.sh/formula/gemini-cli |
| npm-global layout | `<prefix>/lib/node_modules/@google/gemini-cli/bundle/gemini.js`; `<prefix>/bin/gemini` symlink | `verified-docs` | npm metadata; layout pattern |
| Homebrew layout | `Cellar/gemini-cli/<version>/bin/gemini`; no Cellar tree was installed or observed | `verified-docs` (formula) / `unverified` (tree) | formula page |
| Non-declarable layout | MacPorts `gemini-cli` is documented by the vendor but is not a `PackageManager` value in M11 | `verified-docs` + `binding-plan` | installation docs; plan §3/R2 |
| Version query | argv `["--version"]`; stream `stdout`; line `first`. Raw measured (scratch install): `0.68.0`. First token `0.68.0`. The install page does not print the flag; the shape is measured. | `observed-local` | `E/scratch/gemini-version.json` |
| Information URL | `https://geminicli.com/docs/get-started/installation/` | `verified-docs` | page fetched 2026-11-12 |
| Uninstall instructions | `https://geminicli.com/docs/resources/uninstall/` — `npm uninstall -g @google/gemini-cli`; `brew uninstall gemini-cli`; npx cache cleanup | `verified-docs` | uninstall page |

**Known limits.**

- The formula is deprecated and has a published disable date. It may be declared with the
  deprecation/disable limits, never silently treated as a stable channel. `verified-docs`.
- The vendor banner states: “Unpaid tier and Google One users: Gemini CLI was replaced by
  Antigravity CLI on June 18th, 2026.” Keeping the entry is OD-6; merging it with AGY is a
  catalogue error. `verified-docs` (installation page).
- MacPorts and npx are documented install routes but cannot be declared in M11. `binding-plan`.
- The Cellar tree is a declaration, not an observed installation. `binding-plan`.
- The formula version and npm version agree today (0.68.0); do not pin either. `verified-docs`.

### 6. `cline` — Cline CLI (Cline)

**Sources:** https://docs.cline.bot/usage/cli-overview; https://docs.cline.bot/cli/cli-reference; https://docs.cline.bot/cline-cli/installation; https://registry.npmjs.org/cline; https://formulae.brew.sh/formula/cline

| Field | Frozen value | Mark | Evidence |
|---|---|---|---|
| Vendor / project | Cline, Cline CLI; repository `cline/cline` | `verified-docs` | npm metadata; https://docs.cline.bot/usage/cli-overview |
| Executable | `cline` | `verified-docs` | CLI docs; formula binary list |
| Category | `aiAgent` | `binding-plan` | plan §4 |
| Fixture | synthetic `npmGlobal` / `npm` | `binding-plan` | plan §4 |
| npm candidate | `cline` 3.0.74, bin `cline -> bin/cline`, repo `cline/cline`, Apache-2.0 | `verified-docs` | https://registry.npmjs.org/cline |
| Formula candidate | `cline` 3.0.3, binary `cline`; **deprecated 2026-05-18**, reason `uses non-FOSS @anthropic-ai/claude-agent-sdk and pre-built binaries`; **disabled 2027-05-18** | `verified-docs` | https://formulae.brew.sh/formula/cline |
| npm-global layout | `<prefix>/lib/node_modules/cline/bin/cline` (Node entry) plus the packaged Bun binary `bin/.cline`; `<prefix>/bin/cline` symlink | `verified-docs` + `observed-local` | npm metadata; `E/local/layouts.txt` |
| Homebrew layout | `Cellar/cline/<version>/bin/cline`; no Cellar tree was observed | `verified-docs` (formula) / `unverified` (tree) | formula page |
| Personal shim (never a layout) | `~/.local/shims/cline` re-signs the Bun binary ad hoc before exec'ing the npm resolver. It shadows npm. It is a personal artifact and must never become a layout, root, or fixture. | `observed-local` | `E/local/layouts.txt` (shim read, not executed) |
| Version query | argv `["--version"]`; stream `stdout`; line `first`. Raw measured: `3.0.74`. The CLI reference documents `-V, --version` “Output the version number” and `cline version`. | `verified-docs` + `observed-local` | CLI reference; `E/local/cline-homebrew-prefix.json` |
| Information URL | `https://docs.cline.bot/usage/cli-overview` (CLI-specific, 200). The older `https://docs.cline.bot/cline-cli/installation` redirects to the general install page; it is not the CLI reference. | `verified-docs` | both URLs fetched 2026-11-12 |
| Uninstall instructions | None published in the CLI overview or CLI reference. `npm uninstall -g cline` is generic npm, not a Cline instruction. | `verified-docs` (absence on reviewed pages) | CLI docs |

**Known limits.**

- The formula is deprecated for licensing/prebuilt-binary reasons and has a disable date.
  `verified-docs`.
- `cline update` is a vendor self-update command, never an Agent Lens operation. `verified-docs`
  (CLI reference).
- The personal shim repairs a code signature by mutating the npm package. Agent Lens must not
  model it, search it, or copy it into a fixture. `observed-local` + `binding-plan`.
- `/opt/homebrew/bin/cline` is npm under the Homebrew prefix, not a formula; the path contains
  `/lib/node_modules/` after resolution. `observed-local` + `binding-plan`.
- npm 3.0.74 and formula 3.0.3 differ; no live version is registry data. `verified-docs`.

### 7. `hermes` — Hermes Agent (Nous Research)

**Sources:** https://hermes-agent.nousresearch.com/docs/getting-started/installation; https://hermes-agent.nousresearch.com/docs/getting-started/updating; https://hermes-agent.nousresearch.com/install.sh; https://formulae.brew.sh/formula/hermes-agent; https://pypi.org/project/hermes-agent/

| Field | Frozen value | Mark | Evidence |
|---|---|---|---|
| Vendor / project | Nous Research, Hermes Agent | `verified-docs` | https://hermes-agent.nousresearch.com/docs/getting-started/installation |
| Executable | `hermes` | `verified-docs` | installation docs; formula binary list |
| Category | `aiAgent` | `binding-plan` | plan §4 |
| Fixture | synthetic `singleDirectory` / `standalone` | `binding-plan` + `observed-local` | plan §4; source checkout measured |
| Formula candidate | `hermes-agent` 0.22.4; binaries `hermes`, `hermes-acp`, `hermes-agent` | `verified-docs` | https://formulae.brew.sh/formula/hermes-agent |
| Non-declarable identity | PyPI `hermes-agent` 0.19.0 (Nous Research summary) is documented but is not a declarable manager in M11 | `verified-docs` + `binding-plan` | https://pypi.org/project/hermes-agent/; plan §3/R2 |
| Source-install layout | checkout `~/.hermes/hermes-agent/`; launcher wrapper `~/.local/bin/hermes`; data `~/.hermes/`; `HERMES_HOME` and `--dir` override; installer bootstraps a pinned uv and does not reuse a uv on PATH | `verified-docs` | installation docs; https://hermes-agent.nousresearch.com/install.sh (read, never executed) |
| Observed layout | 76-byte `/bin/sh` wrapper at `~/.local/bin/hermes` exec'ing `~/.hermes/hermes-agent/.hermes/bin/hermes`; install method `git`; extra binaries `hermes-agent`, `hermes-acp` in `.hermes/bin` | `observed-local` | `E/local/layouts.txt`; `E/local/hermes.json` |
| Homebrew layout | `Cellar/hermes-agent/<version>/bin/{hermes,hermes-acp,hermes-agent}`; no Cellar tree was observed | `verified-docs` (formula) / `unverified` (tree) | formula page |
| Version query | argv `["--version"]`; stream `stdout`; line `first`. Raw measured first line: `Hermes Agent v0.23.1 (2026.9.24) · stable · local 3b4215785882`. First token `0.23.1`; the date is later in the line and must not win. The command is documented. | `verified-docs` + `observed-local` | updating docs; `E/local/hermes.json` |
| Information URL | `https://hermes-agent.nousresearch.com/docs/getting-started/installation` | `verified-docs` | fetched 2026-11-12 |
| Uninstall instructions | `https://hermes-agent.nousresearch.com/docs/getting-started/updating#uninstalling` — `hermes uninstall` (review `--dry-run`); `--full`/`--data` modes; source uninstaller is vendor-owned | `verified-docs` | updating page |

**Known limits.**

- The local install is a git checkout; `classifySource` calls it `standalone`. `observed-local`.
- uv is the bootstrap tool, not a package manager identity; PyPI `hermes-agent` is documented but
  not declarable. `binding-plan`.
- `hermes-agent` and `hermes-acp` are second executables. They are known limits, not detectors.
  `verified-docs` (formula binaries) + `binding-plan`.
- The version output is multi-line and contains a date plus a build token. First-match extraction
  yields `0.23.1`. `observed-local`.
- `hermes update` and `hermes uninstall` are vendor operations, never Agent Lens operations.
  `verified-docs`.
- Formula 0.22.4, PyPI 0.19.0, and local 0.23.1 differ; no pin. `verified-docs` + `observed-local`.

### 8. `aider` — Aider (Aider-AI)

**Sources:** https://aider.chat/docs/install.html; https://aider.chat/docs/config/options.html; https://formulae.brew.sh/formula/aider; https://pypi.org/project/aider-chat/

| Field | Frozen value | Mark | Evidence |
|---|---|---|---|
| Vendor / project | Aider-AI, Aider; repository `Aider-AI/aider` | `verified-docs` | https://aider.chat/docs/install.html |
| Executable | `aider` | `verified-docs` | formula binary list; install docs |
| Category | `aiCodingTool` | `binding-plan` | plan §4 |
| Fixture | synthetic `singleDirectory` / `standalone` | `binding-plan` | plan §4 |
| Formula candidate | `aider` 0.86.2, binary `aider` | `verified-docs` | https://formulae.brew.sh/formula/aider |
| Non-declarable identity | PyPI/uv/pipx `aider-chat` 0.86.2 is documented but is not a declarable manager in M11 | `verified-docs` + `binding-plan` | https://pypi.org/project/aider-chat/; install docs; plan §3/R2 |
| Install layouts | formula `Cellar/aider/<version>/bin/aider`; uv tool `<uv-tool-dir>/aider-chat/bin/aider`; pipx/pip venv equivalents; the vendor warns system package managers often install incorrect dependencies | `verified-docs` | install docs; uv scratch route |
| Observed layout | none on PATH (not installed); scratch uv tool installed only for measurement | `observed-local` | `E/local/which.log`; `E/scratch/manifest-before-cleanup.txt` |
| Version query | argv `["--version"]`; stream `stdout`; line `first`. Official CLI reference says “Show the version number and exit.” Raw measured (scratch uv install): `aider 0.86.2`. First token `0.86.2`. | `verified-docs` (flag) + `observed-local` (shape) | https://aider.chat/docs/config/options.html; `E/scratch/aider-version.json` |
| Information URL | `https://aider.chat/docs/install.html` | `verified-docs` | fetched 2026-11-12 |
| Uninstall instructions | None published on the official install or options pages reviewed. | `verified-docs` (absence on reviewed pages) | install/options pages |

**Known limits.**

- The version flag is confirmed, but the measured cold-start run took **3747 ms**, above the
  current `ToolDetector.versionTimeout` of 3 s (`Sources/AgentLensCore/Detection/ToolDetector.swift:81`).
  A cold uv/Python start may therefore yield unknown version. Unknown is safe; do not raise the
  timeout in M11. `observed-local` + `binding-plan`.
- uv, pip, and pipx are not declarable managers; the formula is the only frozen candidate.
  `binding-plan`.
- No uninstall instructions were found; do not invent a pip/uv uninstall command as a vendor
  instruction. `verified-docs` (absence).
- The uv tool path and pip venv paths are not Homebrew Cellar paths; they would classify
  `standalone`. `binding-plan`.

### 9. `goose` — Goose (Agentic AI Foundation)

**Sources:** https://goose-docs.ai/docs/getting-started/installation/; https://goose-docs.ai/docs/guides/goose-cli-commands; https://github.com/aaif-goose/goose/releases/download/stable/download_cli.sh; https://formulae.brew.sh/formula/block-goose-cli; https://formulae.brew.sh/formula/goose; https://formulae.brew.sh/cask/block-goose

| Field | Frozen value | Mark | Evidence |
|---|---|---|---|
| Vendor / project | Goose, current org `aaif-goose/goose`; docs `goose-docs.ai`; Homebrew names retain `block` | `verified-docs` | https://goose-docs.ai/docs/getting-started/installation/; https://formulae.brew.sh/formula/block-goose-cli |
| Executable | `goose` | `verified-docs` | formula binary list; CLI commands docs |
| Category | `aiCodingTool` | `binding-plan` | plan §4 |
| Fixture | synthetic `singleDirectory` / `standalone` | `binding-plan` | plan §4 |
| Formula candidate | `block-goose-cli` 1.59.0; binaries `goose`, `generate_manpages`, `mcp_conformance_driver`; conflicts with formula `goose` | `verified-docs` | https://formulae.brew.sh/formula/block-goose-cli |
| Never declare | formula `goose` is pressly’s database migration CLI (3.30.1); cask `block-goose` is the desktop app | `verified-docs` | https://formulae.brew.sh/formula/goose; https://formulae.brew.sh/cask/block-goose |
| Script-install layout | `GOOSE_BIN_DIR` default `$HOME/.local/bin`; downloads `goose-<arch>-apple-darwin.tar.bz2` from the `stable` release tag; moves the extracted `goose` binary into that directory | `verified-docs` | https://github.com/aaif-goose/goose/releases/download/stable/download_cli.sh (read, never executed) |
| Homebrew layout | `Cellar/block-goose-cli/<version>/bin/{goose,generate_manpages,mcp_conformance_driver}`; no Cellar tree was observed | `verified-docs` (formula) / `unverified` (tree) | formula page |
| Version query | argv `["--version"]`; stream `stdout`; line `first`. Raw measured (official stable binary): ` 1.59.0` — one leading space. First token `1.59.0`. The command is documented. | `verified-docs` + `observed-local` | https://goose-docs.ai/docs/guides/goose-cli-commands; `E/scratch/goose-version.json` |
| Information URL | `https://goose-docs.ai/docs/guides/goose-cli-commands` | `verified-docs` | fetched 2026-11-12 |
| Uninstall instructions | None published for the CLI on the fetched installation/commands pages. Windows desktop removal is documented separately; that is not the CLI. | `verified-docs` (absence on reviewed pages) | installation/commands pages |

**Known limits.**

- The basename `goose` is shared with pressly’s formula `goose`; both install a `goose` binary.
  Identity for any future mutation is the declared formula `block-goose-cli`, not the basename.
  `verified-docs` + `binding-plan`.
- Cask `block-goose` is the desktop `Goose.app`, never the CLI. `verified-docs`.
- The formula installs two helper binaries (`generate_manpages`, `mcp_conformance_driver`). They
  are known limits, not detectors. `verified-docs`.
- `goose update` is a vendor self-update, never an Agent Lens operation. `verified-docs`.
- The script default `~/.local/bin/goose` and the formula Cellar path are different layouts.
  `verified-docs`.

### 10. `kiro-cli` — Kiro CLI (Amazon / Kiro)

**Sources:** https://kiro.dev/docs/cli/; https://kiro.dev/docs/getting-started/installation/; https://cli.kiro.dev/install; https://formulae.brew.sh/cask/kiro-cli; https://formulae.brew.sh/formula/kiro-cli; https://registry.npmjs.org/kiro-cli; https://registry.npmjs.org/@aws%2Fkiro-cli

| Field | Frozen value | Mark | Evidence |
|---|---|---|---|
| Vendor / project | Amazon / Kiro, Kiro CLI | `verified-docs` | https://kiro.dev/docs/cli/ |
| Executable | `kiro-cli` | `verified-docs` | CLI docs; cask artifact |
| Category | `aiCodingTool` | `binding-plan` | plan §4 |
| Fixture | synthetic `singleDirectory` / `standalone` | `binding-plan` | plan §4 |
| Cask candidate | `kiro-cli` 3.2.1, artifact `kirocli-universal-darwin.zip` → `kirocli/bin/kiro-cli` → `$HOMEBREW_PREFIX/bin/kiro-cli`; zap lists `~/.local/bin/kiro-cli`, `~/.local/bin/kiro-cli-chat` | `verified-docs` | https://formulae.brew.sh/cask/kiro-cli |
| Formula candidate | none: formula `kiro-cli` returned 404 on retry after an initial 503 transient | `verified-docs` | https://formulae.brew.sh/formula/kiro-cli (404, 2026-11-12) |
| Never declare | npm `kiro-cli` 0.0.1 is an unrelated placeholder whose bin is `kirox`; npm `@aws/kiro-cli` is 404 | `verified-docs` | registry URLs in the do-not-declare table |
| Script-install layout | `USER_INSTALL_DIR=$HOME/.local/bin`; `BINARY_NAME=kiro-cli`; bundle also has `kiro-cli-chat`; script can install `Kiro CLI.app` via DMG on macOS or a universal zip; version selection uses `--version <semver>` as an installer option and the stable channel manifest | `verified-docs` | https://cli.kiro.dev/install (read, never executed) |
| Observed local layout | not installed; `~/.local/bin/kiro-cli` absent | `observed-local` | `E/local/which.log` |
| Cask artifact measurement | downloaded the cask artifact to scratch; SHA-256 matched `bfda7f0b…87f06`; extracted `kirocli/bin/kiro-cli` (Mach-O arm64); ran `--version` | `observed-local` | `E/scratch/kiro-download.json`, `E/scratch/kiro-cli-version.json`, `E/scratch/cleanup.txt` |
| Version query | argv `["--version"]`; stream `stdout`; line `first`. Raw measured: `kiro-cli 3.2.1`. First token `3.2.1`. Docs say `kiro-cli --version` should show 3.0.0 or later. | `verified-docs` + `observed-local` | installation docs; `E/scratch/kiro-cli-version.json` |
| Information URL | `https://kiro.dev/docs/cli/` | `verified-docs` | fetched 2026-11-12 |
| Uninstall instructions | `https://kiro.dev/docs/getting-started/installation/` — CLI tab documents `kiro-cli uninstall` (removes `~/.local/bin/kiro-cli`, signs out, keeps `~/.kiro`, does not remove binaries elsewhere) and `brew uninstall --cask kiro-cli`. | `verified-docs` | installation page |

**Known limits.**

- The official installation page also writes `brew install kiro-cli` while the only live registry
  listing is the cask. The cask is the frozen package; do not declare a formula. `verified-docs`.
- Do not detect `kiro` (the IDE/router). The detector is `kiro-cli`. `binding-plan` (R5/R4).
- The installer’s `--version` is an installer option, not the CLI `--version`; do not confuse them.
  `verified-docs` (script).
- The macOS installer can place `Kiro CLI.app` in `/Applications` via a DMG, which is a different
  surface from the standalone zip. `verified-docs` (script).
- `kiro-cli update` and `kiro-cli uninstall` are vendor operations, never Agent Lens operations.
  `verified-docs`.
- The Homebrew artifact was fetched directly and measured; no `brew install` was run. The
  Homebrew installation tree itself is not observed. `binding-plan`.

### 11. `qodercli` — Qoder CLI (Qoder)

**Sources:** https://docs.qoder.com/cli/installation; https://docs.qoder.com/cli/cli-reference; https://qoder.com/install; https://registry.npmjs.org/@qoder-ai%2Fqodercli; https://formulae.brew.sh/cask/qoder; https://registry.npmjs.org/qoder; https://registry.npmjs.org/@qoder-ai%2Fqoder

| Field | Frozen value | Mark | Evidence |
|---|---|---|---|
| Vendor / project | Qoder, Qoder CLI | `verified-docs` | https://docs.qoder.com/cli/installation |
| Executable | `qodercli` (plan ruling OD-4; official docs mostly call the command `qoder`) | `binding-plan` (choice) + `verified-docs` (both names exist) | plan §4; npm bins; docs |
| Category | `aiCodingTool` | `binding-plan` | plan §4 |
| Fixture | synthetic `singleDirectory` / `standalone` | `binding-plan` | plan §4 |
| npm candidate | `@qoder-ai/qodercli` 1.1.88, bins `qoder -> bundle/qoder-npm-dispatcher.cjs` and `qodercli -> bundle/qodercli.js`, Node >= 20; docs call this legacy and still document it | `verified-docs` | https://registry.npmjs.org/@qoder-ai%2Fqodercli; https://docs.qoder.com/cli/installation |
| Native script | `curl -fsSL https://qoder.com/install` piped to bash; the script downloads and delegates placement to `qodercli install` (versioned binary placement, entry-point creation, PATH config, marker, verification) | `verified-docs` | https://qoder.com/install (read, never executed) |
| Observed layout | `~/.local/bin/qodercli` → `~/.qoder/bin/qodercli/qodercli-1.1.88` (Mach-O arm64); dispatcher `~/.qoder/entry/qoder` is a bash script routing to `qodercli` or the IDE; config/data default `~/.qoder` | `observed-local` | `E/local/layouts.txt` |
| npm-global layout | `<prefix>/lib/node_modules/@qoder-ai/qodercli/bundle/qodercli.js`; `<prefix>/lib/node_modules/@qoder-ai/qodercli/bundle/qoder-npm-dispatcher.cjs` | `verified-docs` | npm metadata |
| Version query | argv `["--version"]`; stream `stdout`; line `first`. Raw measured on both executables: `1.1.88`. Official CLI reference documents `--version`, `-v` “Print the version number and exit”; installation verification uses `qoder --version`. | `verified-docs` + `observed-local` | https://docs.qoder.com/cli/cli-reference; `E/local/qodercli.json`, `E/local/qoder-dispatcher.json` |
| Information URL | `https://docs.qoder.com/cli/installation` | `verified-docs` | fetched 2026-11-12 |
| Uninstall instructions | `https://docs.qoder.com/cli/installation#uninstallation` — npm: `npm uninstall -g @qoder-ai/qodercli`; script: delete the placed executable and its PATH entry; data/config default `~/.qoder` (delete separately). | `verified-docs` | installation page |

**Known limits.**

- Two official wordings: the docs address the command as `qoder` (installation verification and CLI
  reference), while the npm package publishes both `qoder` (dispatcher) and `qodercli` (runtime).
  The plan rules `qodercli` as the detector (OD-4); do not silently switch to `qoder` later.
  `binding-plan` + `verified-docs`.
- The `qoder` dispatcher can launch the IDE. It is not a stable CLI detector in M11. `observed-local`
  (dispatcher script read) + `binding-plan`.
- `qodercli-<version>` is a versioned runtime filename; it is a personal artifact, not a root or
  fixture. `observed-local`.
- The native script’s final placement is delegated to the binary and is not stated in docs; the
  observed layout is the evidence. `observed-local`.
- `qoder update` and auto-upgrade are vendor operations, never Agent Lens operations. `verified-docs`.
- The cask `qoder` is the IDE (“Agentic coding platform”), never the CLI. `verified-docs`.

### 12. `dsh` — DeepSeek Harness (DeepSeek AI)

**Sources:** https://github.com/deepseek-ai/deepseek-harness; https://raw.githubusercontent.com/deepseek-ai/deepseek-harness/master/docs/cli-help.md; https://raw.githubusercontent.com/deepseek-ai/deepseek-harness/master/docs/config-catalog.md; https://registry.npmjs.org/@deepseek-ai%2Fdsh; https://formulae.brew.sh/formula/dsh; https://pypi.org/project/deepseek-harness/; https://pypi.org/project/deepseek-harness-cli/

| Field | Frozen value | Mark | Evidence |
|---|---|---|---|
| Vendor / project | DeepSeek AI, DeepSeek Harness; repository `deepseek-ai/deepseek-harness` | `verified-docs` | https://github.com/deepseek-ai/deepseek-harness (README) |
| Executable | `dsh` | `verified-docs` | README; npm metadata; CLI help |
| Category | `aiHarness` | `binding-plan` | plan §4 |
| Fixture | synthetic `npmGlobal` / `npm` | `binding-plan` + `observed-local` | plan §4; npm-global layout measured |
| npm candidate | `@deepseek-ai/dsh` 0.2.2-rc.1, bin `dsh -> lib/bin.js`, repo `deepseek-ai/deepseek-harness`, MIT, Node >= 24.9.0 | `verified-docs` | https://registry.npmjs.org/@deepseek-ai%2Fdsh |
| Never declare | Homebrew formula `dsh` is Dancer’s shell/distributed shell (0.25.10), not DeepSeek Harness. No official Python wheel is documented in the README; third-party PyPI names are excluded. | `verified-docs` | https://formulae.brew.sh/formula/dsh; README; do-not-declare table |
| npm-global layout | `<prefix>/lib/node_modules/@deepseek-ai/dsh/lib/bin.js`; `<prefix>/bin/dsh` symlink. Measured at `~/.local` and `/opt/homebrew` prefixes. | `observed-local` | `E/local/layouts.txt` |
| Zero-install layout | `npx @deepseek-ai/dsh ...` is the README’s official zero-install path | `verified-docs` | README |
| Data directory | `$DSH_HOME`, default `~/.dsh`; profiles under `$DSH_HOME/profiles/<name>` | `verified-docs` | official repo `docs/cli-help.md`, `docs/config-catalog.md` |
| Version query | argv `["--version"]`; stream `stdout`; line `first`. Raw measured: `0.2.2-rc.1`. First token `0.2.2-rc.1`; the existing regex accepts the prerelease suffix. Official CLI help documents `-V, --version` as the launcher flag (must precede app arguments). | `verified-docs` + `observed-local` | repo `docs/cli-help.md`; `E/local/dsh.json` |
| Information URL | `https://github.com/deepseek-ai/deepseek-harness` | `verified-docs` | fetched 2026-11-12 |
| Uninstall instructions | None published in the README or official CLI docs reviewed. Removing an npm global install is generic npm behavior, not a vendor instruction. | `verified-docs` (absence on reviewed pages) | README; `docs/cli-help.md` |

**Known limits.**

- The brew formula named `dsh` belongs to an unrelated project. Never declare it. `verified-docs`.
- Third-party PyPI packages `deepseek-harness` and `deepseek-harness-cli` are not DeepSeek AI. Never
  declare them. `verified-docs`.
- Developer preview: the README warns of compatibility-breaking changes. Upstream breakage is not
  an Agent Lens defect. `verified-docs`.
- The version is a prerelease (`0.2.2-rc.1`); the existing token regex handles it, and the value is
  not a pin. `observed-local` + `binding-plan`.
- `dsh` may write profiles/data under `~/.dsh`; that is vendor data, not an install layout root.
  `verified-docs`.
- No uninstall instructions were found; do not invent a Python wheel name or a brew package.
  `verified-docs` (absence) + `binding-plan`.

### 13. `omp` — Oh My Pi (OMP)

**Sources:** https://omp.sh/docs/quickstart; https://github.com/can1357/oh-my-pi; https://omp.sh/install; https://registry.npmjs.org/@oh-my-pi%2Fpi-coding-agent; https://raw.githubusercontent.com/can1357/homebrew-tap/master/Formula/omp.rb; https://registry.npmjs.org/@oh-my-pi%2Fcli

| Field | Frozen value | Mark | Evidence |
|---|---|---|---|
| Vendor / project | Oh My Pi, repository `can1357/oh-my-pi`, site `omp.sh` | `verified-docs` | https://github.com/can1357/oh-my-pi (README); https://omp.sh/docs/quickstart |
| Executable | `omp` | `verified-docs` | quickstart; npm/tap metadata |
| Category | `aiHarness` | `binding-plan` | plan §4 |
| Fixture | synthetic `singleDirectory` / `standalone` | `binding-plan` + `observed-local` | plan §4; standalone binary measured |
| npm candidate | `@oh-my-pi/pi-coding-agent` 18.19.0, bin `omp -> dist/cli.js`, repo `can1357/oh-my-pi`, MIT, Bun >= 1.4.4 | `verified-docs` | https://registry.npmjs.org/@oh-my-pi%2Fpi-coding-agent |
| Formula candidate | `can1357/tap/omp` 18.19.0; installs `omp`; formula test asserts `omp --version` | `verified-docs` | https://raw.githubusercontent.com/can1357/homebrew-tap/master/Formula/omp.rb |
| Never declare | npm `@oh-my-pi/cli` is 404 in the registry on 2026-11-12; regardless, it is not this project’s declared package. | `verified-docs` | https://registry.npmjs.org/@oh-my-pi%2Fcli (404) |
| Script-install layout | `PI_INSTALL_DIR` default `$HOME/.local/bin`; downloads the platform binary, checksum-verifies, moves it to `$PI_INSTALL_DIR/omp`, then smoke-tests `omp --version` | `verified-docs` | https://omp.sh/install → https://raw.githubusercontent.com/can1357/oh-my-pi/main/scripts/install.sh (read, never executed) |
| npm/bun layout | `<prefix>/lib/node_modules/@oh-my-pi/pi-coding-agent/dist/cli.js`; `omp` bin; the README recommends Bun for this route | `verified-docs` | README; npm metadata |
| Homebrew layout | `Cellar/omp/<version>/bin/omp` for the tap; no Cellar tree was observed | `verified-docs` (formula) / `unverified` (tree) | tap file |
| Personal layout (never a root) | `/opt/homebrew/bin/omp` resolves to the Tern store `~/Library/Application Support/Tern/omp/versions/18.18.8`; `manager.json` says `tern`, not Homebrew | `observed-local` | `E/local/layouts.txt`; `E/local/omp-homebrew-prefix.json` |
| Version query | argv `["--version"]`; stream `stdout`; line `first`. Raw measured: `omp/18.19.0`. First token `18.19.0`. Quickstart documents the command. | `verified-docs` + `observed-local` | quickstart; `E/local/omp-user-local.json` |
| Information URL | `https://omp.sh/docs/quickstart` | `verified-docs` | fetched 2026-11-12 |
| Uninstall instructions | None published in the quickstart or README reviewed. | `verified-docs` (absence on reviewed pages) | quickstart; README |

**Known limits.**

- The `/opt/homebrew/bin/omp` copy is a Tern version store, not a tap and not `/Cellar/`;
  `classifySource` calls it `standalone`. Tern is not a declarable manager. `observed-local`.
- `@oh-my-pi/cli` is not declared; the registry 404 is recorded. `verified-docs`.
- The executable basename alone is not identity. The frozen identities are the npm package
  `@oh-my-pi/pi-coding-agent` and the tap `can1357/tap/omp`; `@oh-my-pi/cli` is excluded.
  `binding-plan`.
- The tap formula’s test uses `omp --version`; this corroborates the query but is not an
  installation. `verified-docs`.
- Bun is documented but not a declarable manager; `npm` is the registry candidate. `binding-plan`.
- No uninstall instructions were found. `verified-docs` (absence).

### 14. `agy` — Antigravity CLI (Google)

**Sources:** https://antigravity.google/docs/getting-started/; https://antigravity.google/product/antigravity-cli; https://antigravity.google/cli/install.sh; https://formulae.brew.sh/cask/antigravity-cli; https://pypi.org/project/google-antigravity/; https://antigravity.google/llms.txt

| Field | Frozen value | Mark | Evidence |
|---|---|---|---|
| Vendor / project | Google, Antigravity CLI (`agy`) | `verified-docs` | https://antigravity.google/docs/getting-started/ (CLI tab); https://antigravity.google/product/antigravity-cli |
| Executable | `agy` | `verified-docs` | getting-started; cask artifact |
| Category | `aiHarness` | `binding-plan` | plan §4 (OD-3 approved) |
| Fixture | synthetic `singleDirectory` / `standalone` | `binding-plan` + `observed-local` | plan §4; local binary measured |
| Cask candidate | `antigravity-cli` version `1.5.7,6190022064472064` (version,build), artifact `antigravity` → target `agy` → `$HOMEBREW_PREFIX/bin/agy`, `auto_updates: true`, zap `~/.gemini/antigravity-cli` | `verified-docs` | https://formulae.brew.sh/cask/antigravity-cli |
| Script-install layout | `TARGET_DIR=$HOME/.local/bin`; installer is `curl -fsSL https://antigravity.google/cli/install.sh` piped to bash; default binary location `~/.local/bin/agy` | `verified-docs` (docs + script) + `observed-local` (local binary) | getting-started; install script (read, never executed); `E/local/layouts.txt` |
| Cask layout | artifact maps `antigravity` → `$HOMEBREW_PREFIX/bin/agy`; Caskroom tree not observed | `verified-docs` (mapping) / `unverified` (tree) | cask JSON |
| Legacy root (observed only) | `~/.gemini/bin/agy` is an older binary (1.2.12), off PATH, not documented by the current install page. It may be an `extraSearchRoots` candidate only with an explicit `observed-local` limit; it is never a fixture. | `observed-local` + `binding-plan` | `E/local/agy-legacy.json`; `E/local/layouts.txt` |
| Settings/data | `~/.gemini/antigravity-cli/settings.json`; cask zap lists `~/.gemini/antigravity-cli` | `verified-docs` | authentication/getting-started docs; cask JSON |
| Version query | argv `["--version"]`; stream `stdout`; line `first`. Raw measured: `1.5.6`. First token `1.5.6`. Docs document `agy --version`. The cask is 1.5.7; the local copy is 1.5.6 — no pin. | `verified-docs` + `observed-local` | getting-started; `E/local/agy.json` |
| Information URL | `https://antigravity.google/docs/getting-started/` (canonical; CLI tab). The previously cited `https://antigravity.google/docs/cli/install/` now redirects through `/docs/install?tab=cli`; use the canonical getting-started page. | `verified-docs` | canonical tag on the fetched page |
| Uninstall instructions | None published for the CLI on the fetched getting-started or CLI reference pages. The cask’s zap list is not a user uninstall instruction. | `verified-docs` (absence on reviewed pages) | getting-started; cask JSON |

**Known limits.**

- The cask sets `auto_updates: true`; `agy update` is a vendor self-update, never an Agent Lens
  operation. `verified-docs` + `binding-plan`.
- The legacy `~/.gemini/bin/agy` root is `observed-local` only; it is not the documented default
  and must not be treated as a first-class layout. `binding-plan`.
- The desktop Antigravity App and the Python SDK `google-antigravity` are different surfaces; never
  declare them for the CLI. `verified-docs`.
- No npm or Homebrew formula identity is documented; the cask and the script are the only frozen
  layouts. `verified-docs`.
- The local binary (1.5.6) and cask (1.5.7) differ; do not pin either. `observed-local` + `verified-docs`.
- The old `/docs/cli/install/` path is unstable; the canonical getting-started URL is the frozen
  information URL. `verified-docs`.

## Do-not-declare table (binding)

These names look plausible and must never be written into the registry for the listed tool. Each
was re-checked against a primary registry on 2026-11-12.

| Tempting declaration | What it actually is | Evidence | Rule |
|---|---|---|---|
| Homebrew formula `dsh` | “Dancer’s shell, or distributed shell” 0.25.10 | https://formulae.brew.sh/formula/dsh | Never for DeepSeek Harness |
| npm `goose` | Unrelated `jiyinyiyong/goose` 0.0.3 (Go bracket tool) | https://registry.npmjs.org/goose | Never for Goose |
| PyPI `goose` | Unrelated `steder/goose` 1.0.0 (SQL migration tool) | https://pypi.org/project/goose/ | Never for Goose |
| Homebrew formula `goose` | pressly database migration CLI 3.30.1; conflicts with `block-goose-cli` | https://formulae.brew.sh/formula/goose | Use `block-goose-cli` |
| npm `kiro-cli` | 0.0.1 placeholder; bin is `kirox` | https://registry.npmjs.org/kiro-cli | Never for Kiro CLI |
| Homebrew cask `qoder` | Qoder desktop/IDE 0.5.7 (“Agentic coding platform”), `Qoder.app` | https://formulae.brew.sh/cask/qoder | Never for the Qoder CLI |
| npm `@oh-my-pi/cli` | 404 on the registry on 2026-11-12; not this project’s declared package either way | https://registry.npmjs.org/@oh-my-pi%2Fcli | Never for OMP |
| PyPI `deepseek-harness` | Third-party project by `HenryZ838978` 0.3.1, not DeepSeek AI | https://pypi.org/project/deepseek-harness/ | Never for DSH |
| PyPI `deepseek-harness-cli` | Third-party companion 0.7.0 by the same author | https://pypi.org/project/deepseek-harness-cli/ | Never for DSH |
| npm `qoder`; npm `@qoder-ai/qoder` | Both 404 on the registry | https://registry.npmjs.org/qoder; https://registry.npmjs.org/@qoder-ai%2Fqoder | Only `@qoder-ai/qodercli` exists |
| npm `@aws/kiro-cli` | 404 on the registry | https://registry.npmjs.org/@aws%2Fkiro-cli | Kiro CLI has no npm package |
| Homebrew cask `opencode-desktop` | OpenCode desktop app 2.2.7, not the terminal CLI | https://formulae.brew.sh/cask/opencode-desktop | Never for OpenCode CLI |
| Homebrew cask `block-goose` | Goose desktop `Goose.app` 1.59.0, not the CLI | https://formulae.brew.sh/cask/block-goose | Never for Goose CLI |
| PyPI `google-antigravity` | Google Antigravity SDK 0.1.23 (`antigravity-sdk-python`), not the CLI | https://pypi.org/project/google-antigravity/ | Never for AGY |

## Cross-entry rules

### Version-query rules (binding for coding phases)

- All frozen queries are exactly `arguments: ["--version"]`, `stream: "stdout"`, `line: "first"`.
  No shell parsing, no `--help` fallback, no per-tool scripts.
- The version token is the first match of the existing bounded regex
  `[0-9]+(\.[0-9]+){1,3}(-[0-9A-Za-z.]+)?` in `ToolDetector.extractVersionToken`. Prerelease
  suffixes such as `0.2.2-rc.1` match. Dates and hashes after the first token do not win.
- The process timeout is 3 s (`ToolDetector.versionTimeout`, `Sources/AgentLensCore/Detection/ToolDetector.swift:81`).
  A timeout, a non-zero exit, or empty output yields **unknown version**, never an error and never
  a guessed value. The measured Codex user-prefix failure is the canonical failure example.
- Measured shapes (all stdout, first line):
  `codex-cli 0.167.0`; `opencode v2.2.7`; `grok 1.0.77 (50ca579fa996) [stable]`;
  `2.1.322 (Claude Code)`; `0.68.0`; `3.0.74`;
  `Hermes Agent v0.23.1 (2026.9.24) · stable · local 3b4215785882`;
  `aider 0.86.2`; ` 1.59.0` (leading space); `kiro-cli 3.2.1`; `1.1.88`;
  `0.2.2-rc.1`; `omp/18.19.0`; `1.5.6`.
- Aider’s cold start measured 3747 ms, above the 3 s budget. This is a known limit, not a reason
  to change the timeout in M11. `observed-local` + `binding-plan`.
- Claude and Kiro cold starts were 2291 ms and 2565 ms, inside the budget but close; report
  unknown on a slower machine rather than extending the budget. `observed-local`.

### Layout and source-classification rules

- `classifySource` recognizes npm by `/lib/node_modules/`, Homebrew by `/Cellar/`, and everything
  else as `standalone`. Therefore:
  - cask binaries (`$HOMEBREW_PREFIX/bin/...`), script installs (`~/.local/bin/...`,
    `~/.opencode/bin`, `~/.grok/bin`), uv tool installs, git checkouts, and Tern stores classify
    `standalone`;
  - npm globals under `/opt/homebrew/lib/node_modules` classify `npm`, not a formula;
  - a Tern copy under `~/Library/Application Support/Tern/...` classifies `standalone`, not a tap.
  `binding-plan` (R2) + `observed-local`.
- Synthetic fixtures prove the detector and the classifier; they never prove a vendor tree exists.
  A fixture cell is written `synthetic <layout>` in the capability matrix, never “verified against
  the vendor”. `binding-plan` (R3/R10).
- Declared packages are candidates, never ownership proof and never install proof. `binding-plan`.
- Second executables (`opencode2`, `hermes-agent`, `hermes-acp`, `qoder` dispatcher) are known
  limits, not detectors.
- Personal artifacts are never layouts, `extraSearchRoots`, or fixtures: the Cline signature shim
  `~/.local/shims/cline`, the Tern store, `qodercli-1.1.88`, `grok-1.0.77-macos-aarch64`, and the
  Claude `versions/` directory. `binding-plan` + `observed-local`.
- No new layouts, sources, or `PackageManager` values in M11. uv/pip/cargo/bun/PyPI/MacPorts/WinGet
  identities stay documentation-only. `binding-plan` (R2).

### Mutation and vendor-update rules

- No entry in this packet grants a mutation. The M11-B fail-closed gate decides Update/Uninstall;
  M11-B will seed only the M10-accepted `codex` entry, and this packet adds no operations.
  `binding-plan` (R1).
- Vendor self-updaters are never Agent Lens operations: `claude update` / background auto-update,
  `codex` installer rerun, `opencode uninstall`, `cline update`, `hermes update` / `hermes uninstall`,
  `goose update`, `kiro-cli update` / `kiro-cli uninstall`, `qoder update` / auto-upgrade,
  `agy update`, cask `auto_updates`. `verified-docs` per entry.
- Declared casks with `auto_updates: true` (`antigravity-cli`) are informational; Agent Lens must
  never invoke their updater. `verified-docs`.

### Deprecation calendar

| Package | Deprecated | Reason | Disabled | Replacement / limit |
|---|---|---|---|---|
| formula `cline` | 2026-05-18 | non-FOSS `@anthropic-ai/claude-agent-sdk` and pre-built binaries | 2027-05-18 | keep as a candidate with the limit; npm `cline` remains |
| formula `gemini-cli` | 2026-06-18 | `unsupported` | 2026-12-18 | replacement cask `antigravity-cli`; keep Gemini CLI per OD-6 |

Both listings were re-checked on 2026-11-12. `verified-docs`
(https://formulae.brew.sh/formula/cline, https://formulae.brew.sh/formula/gemini-cli).

## Evidence appendix

### A. Measurement environment

- macOS Darwin 27.0.0, arm64. Login-shell environment inherited.
- Node `v22.23.2`, npm `10.9.8`, uv `0.13.7`, Python `3.15.2` (system); Python 3.12 provisioned
  by uv inside scratch for Aider.
- `TMPDIR=R/tmp`. npm cache and user config were redirected to `R/scratch/npm-cache` and an empty
  scratch npmrc; uv cache, tool dir, tool bin dir, and Python install dir were redirected under
  `R/scratch/uv`. No personal manager install was modified.
- Version queries used a 25 s outer cap. Install/download steps used larger caps (44 s, 75 s, etc.);
  the 25 s cap is the version-query cap required by the brief.

### B. Scratch measurements (all five succeeded)

Raw JSON is in `E/scratch/`. Every query below is `--version`, stream stdout, line first.

| id | Install route (exact argv) | Install exit / time | Query exit / time | Raw stdout | Token |
|---|---|---|---|---|---|
| `claude` | `npm install --prefix R/scratch/claude --no-audit --no-fund @anthropic-ai/claude-code` | 0 / 44498 ms | 0 / 2291 ms | `2.1.322 (Claude Code)` | `2.1.322` |
| `gemini` | `npm install --prefix R/scratch/gemini --no-audit --no-fund @google/gemini-cli` | 0 / 12664 ms | 0 / 810 ms | `0.68.0` | `0.68.0` |
| `aider` | `UV_TOOL_DIR=R/scratch/uv/tools UV_TOOL_BIN_DIR=R/scratch/uv/bin UV_CACHE_DIR=R/scratch/uv/cache uv tool install --python 3.12 aider-chat` | 0 / 40952 ms | 0 / 3747 ms | `aider 0.86.2` | `0.86.2` |
| `goose` | `curl -fL -o R/scratch/goose/goose-aarch64-apple-darwin.tar.bz2 https://github.com/aaif-goose/goose/releases/download/stable/goose-aarch64-apple-darwin.tar.bz2`; `tar -xjf` | 0 / 15395 ms | 0 / 1109 ms | ` 1.59.0` | `1.59.0` |
| `kiro-cli` | `curl -fL -o R/scratch/kiro/kirocli-universal-darwin.zip https://desktop-release.q.us-east-1.amazonaws.com/3.2.1/kirocli-universal-darwin.zip`; SHA-256 matched; `unzip` | 0 / 75465 ms | 0 / 2565 ms | `kiro-cli 3.2.1` | `3.2.1` |

Raw transcripts (exact):

```text
claude --version
stdout: "2.1.322 (Claude Code)\n"
stderr: ""
exit: 0
duration: 2291 ms
```

```text
gemini --version
stdout: "0.68.0\n"
stderr: ""
exit: 0
duration: 810 ms
```

```text
aider --version
stdout: "aider 0.86.2\n"
stderr: ""
exit: 0
duration: 3747 ms
```

```text
goose --version
stdout: " 1.59.0\n"
stderr: ""
exit: 0
duration: 1109 ms
```

```text
kiro-cli --version
stdout: "kiro-cli 3.2.1\n"
stderr: ""
exit: 0
duration: 2565 ms
```

Install outputs of record:

```text
npm install claude: "added 2 packages in 44s"; exit 0; 44498 ms
npm install gemini: "added 7 packages in 13s"; stderr: one deprecation warning for @github/keytar; exit 0; 12664 ms
uv tool install aider: "Installed 1 executable: aider"; exit 0; 40952 ms
goose download: 48.7 MB; exit 0; 15395 ms
kiro download: 253 MB; SHA-256 bfda7f0b1c3d37e53143054a730df94dde52149ac7aea5699b6d36dabec87f06; exit 0; 75465 ms
```

No scratch route failed. No fallback route was improvised.

### C. Local observations (read-only)

Raw JSON is in `E/local/`; the layout log is `E/local/layouts.txt`.

| Target | Exit | Raw stdout / notable stderr | Duration | Evidence |
|---|---|---|---|---|
| `~/.local/bin/codex` | 1 | stderr: `Error: Missing optional dependency @openai/codex-darwin-arm64. Reinstall Codex: npm install -g @openai/codex@latest` | 115 ms | `codex-user-local.json` |
| `/opt/homebrew/bin/codex` | 0 | `codex-cli 0.167.0` | 95 ms | `codex-homebrew-prefix.json` |
| `~/.opencode/bin/opencode` | 0 | `opencode v2.2.7` | 202 ms | `opencode-offpath.json` |
| `~/.opencode/bin/opencode2` | 0 | `opencode v2.2.7` | 243 ms | `opencode2-offpath.json` |
| `~/.local/bin/grok` | 0 | `grok 1.0.77 (50ca579fa996) [stable]` | 44 ms | `grok.json` |
| `/opt/homebrew/bin/cline` | 0 | `3.0.74` | 750 ms | `cline-homebrew-prefix.json` |
| `~/.local/bin/cline` | 0 | `3.0.74` | 694 ms | `cline-user-npm.json` |
| `~/.local/bin/hermes` | 0 | `Hermes Agent v0.23.1 (2026.9.24) · stable · local 3b4215785882` plus 5 more lines | 392 ms | `hermes.json` |
| `~/.qoder/entry/qoder` | 0 | `1.1.88` | 111 ms | `qoder-dispatcher.json` |
| `~/.local/bin/qodercli` | 0 | `1.1.88` | 101 ms | `qodercli.json` |
| `~/.local/bin/dsh` | 0 | `0.2.2-rc.1` | 73 ms | `dsh.json` |
| `~/.local/bin/omp` | 0 | `omp/18.19.0` | 13 ms | `omp-user-local.json` |
| `/opt/homebrew/bin/omp` (Tern) | 0 | `omp/18.18.8` | 75 ms | `omp-homebrew-prefix.json` |
| `~/.local/bin/agy` | 0 | `1.5.6` | 248 ms | `agy.json` |
| `~/.gemini/bin/agy` (legacy) | 0 | `1.2.12` | 242 ms | `agy-legacy.json` |
| `claude`, `gemini`, `aider`, `goose`, `kiro-cli` on PATH | 127 | not found (not installed) | 1 ms each | `*-absent.json` |

Raw transcript for the multi-line Hermes output:

```text
Hermes Agent v0.23.1 (2026.9.24) · stable · local 3b4215785882
Install directory: /Users/corvette/.hermes/hermes-agent
Install method: git
Python: 3.14.9
OpenAI SDK: 2.54.0
Up to date
```

Key layout facts recorded in `E/local/layouts.txt`:

- `~/.local/bin/codex` → `~/.local/lib/node_modules/@openai/codex/bin/codex.js`;
  `/opt/homebrew/bin/codex` → the same relative path under `/opt/homebrew` (0.167.0).
- `~/.local/bin/grok` → `~/.grok/bin/grok` → `~/.grok/downloads/grok-1.0.77-macos-aarch64`.
- `~/.local/bin/cline` and `/opt/homebrew/bin/cline` are npm Node scripts; `~/.local/shims/cline`
  is the personal re-signing shim (read, not executed).
- `~/.local/bin/hermes` is a 76-byte wrapper exec'ing `~/.hermes/hermes-agent/.hermes/bin/hermes`;
  `.install_method` is `git`; `.hermes/bin` also contains `hermes-agent` and `hermes-acp`.
- `~/.qoder/entry/qoder` is the dispatcher; `~/.local/bin/qodercli` → `~/.qoder/bin/qodercli/qodercli-1.1.88`.
- `~/.local/bin/dsh` and `/opt/homebrew/bin/dsh` are npm shims into `@deepseek-ai/dsh/lib/bin.js`.
- `~/.local/bin/omp` is a standalone Mach-O (222,891,152 bytes); `/opt/homebrew/bin/omp` → Tern
  store `versions/18.18.8`, manager `tern`.
- `~/.local/bin/agy` is a standalone Mach-O (233,521,200 bytes); `~/.gemini/bin/agy` is a legacy
  Mach-O (186,868,816 bytes) at 1.2.12.

### D. Registry snapshots and primary listings

All fetched 2026-11-12. Raw JSON/HTML is under `E/registry/`.

| Source | Result | Used for |
|---|---|---|
| `formulae.brew.sh/formula/hermes-agent` | 200; 0.22.4; binaries hermes, hermes-acp, hermes-agent | Hermes |
| `formulae.brew.sh/formula/cline` | 200; 3.0.3; deprecated 2026-05-18; disabled 2027-05-18; binary cline | Cline |
| `formulae.brew.sh/formula/gemini-cli` | 200; 0.68.0; deprecated 2026-06-18; disabled 2026-12-18; replacement antigravity-cli; binary gemini | Gemini |
| `formulae.brew.sh/formula/block-goose-cli` | 200; 1.59.0; binaries goose, generate_manpages, mcp_conformance_driver; conflicts goose | Goose |
| `formulae.brew.sh/formula/aider` | 200; 0.86.2; binary aider | Aider |
| `formulae.brew.sh/formula/opencode` | 200; 2.2.7; binary opencode | OpenCode |
| `formulae.brew.sh/formula/goose` | 200; 3.30.1; pressly | Do-not-declare |
| `formulae.brew.sh/formula/dsh` | 200; 0.25.10; Dancer’s shell | Do-not-declare |
| `formulae.brew.sh/formula/codex` | 404 | Codex formula absence |
| `formulae.brew.sh/formula/kiro-cli` | 404 (retried after 503) | Kiro |
| `formulae.brew.sh/formula/omp` | 404 | OMP |
| `formulae.brew.sh/cask/claude-code` | 200; 2.1.311; binary claude; auto_updates false | Claude |
| `formulae.brew.sh/cask/claude-code@latest` | 200; 2.1.322; binary claude; auto_updates false | Claude |
| `formulae.brew.sh/cask/antigravity-cli` | 200; version `1.5.7,6190022064472064`; binary antigravity → agy; auto_updates true | AGY |
| `formulae.brew.sh/cask/kiro-cli` | 200; 3.2.1; binary kirocli/bin/kiro-cli; zap ~/.local/bin/kiro-cli | Kiro |
| `formulae.brew.sh/cask/codex` | 200; 0.167.2; binary bin/codex | Codex |
| `formulae.brew.sh/cask/qoder` | 200; 0.5.7; Qoder.app | Do-not-declare |
| `formulae.brew.sh/cask/opencode-desktop` | 200; 2.2.7; OpenCode.app | Do-not-declare |
| `formulae.brew.sh/cask/block-goose` | 200; 1.59.0; Goose.app | Do-not-declare |
| `registry.npmjs.org/@openai%2Fcodex/0.167.2` | 200; bin codex → bin/codex.js; repo openai/codex; Apache-2.0 | Codex |
| `registry.npmjs.org/@opencode%2Fcli/2.2.7` | 200; bins opencode, opencode2; repo anomalyco/opencode; MIT | OpenCode |
| `registry.npmjs.org/opencode-ai` | 200; 1.19.5; bin opencode; repository field absent | OpenCode |
| `registry.npmjs.org/@anthropic-ai%2Fclaude-code` | 200; 2.1.322; bin claude → bin/claude.exe; Node >= 22 | Claude |
| `registry.npmjs.org/@google%2Fgemini-cli` | 200; 0.68.0; bin gemini; Apache-2.0 | Gemini |
| `registry.npmjs.org/cline` | 200; 3.0.74; bin cline; Apache-2.0 | Cline |
| `registry.npmjs.org/@qoder-ai%2Fqodercli` | 200; 1.1.88; bins qoder, qodercli; Node >= 20 | Qoder |
| `registry.npmjs.org/@deepseek-ai%2Fdsh` | 200; 0.2.2-rc.1; bin dsh; MIT | DSH |
| `registry.npmjs.org/@oh-my-pi%2Fpi-coding-agent` | 200; 18.19.0; bin omp; MIT | OMP |
| `pypi.org/pypi/hermes-agent/json` | 200; 0.19.0; Nous Research | Hermes (non-declarable) |
| `pypi.org/pypi/aider-chat/json` | 200; 0.86.2; Aider-AI/aider | Aider (non-declarable) |
| `pypi.org/pypi/goose/json` | 200; 1.0.0; steder | Do-not-declare |
| `pypi.org/pypi/deepseek-harness/json` | 200; 0.3.1; HenryZ838978 | Do-not-declare |
| `pypi.org/pypi/deepseek-harness-cli/json` | 200; 0.7.0; HenryZ838978 | Do-not-declare |
| `pypi.org/pypi/google-antigravity/json` | 200; 0.1.23; Google SDK | Do-not-declare |
| `api.github.com/repos/anomalyco/homebrew-tap/contents/` | 200; root formulae include opencode-v2.rb, opencode.rb | OpenCode taps |
| `raw.githubusercontent.com/anomalyco/homebrew-tap/master/opencode-v2.rb` | 200; 2.2.7; installs opencode; conflicts opencode | OpenCode tap |
| `raw.githubusercontent.com/anomalyco/homebrew-tap/master/opencode.rb` | 200; 1.19.5; installs opencode | OpenCode tap |
| `raw.githubusercontent.com/can1357/homebrew-tap/master/Formula/omp.rb` | 200; 18.19.0; installs omp; test `omp --version` | OMP tap |
| `registry.npmjs.org/@oh-my-pi%2Fcli` | 404 | Do-not-declare |
| `registry.npmjs.org/qoder` | 404 | Do-not-declare |
| `registry.npmjs.org/@qoder-ai%2Fqoder` | 404 | Do-not-declare |
| `registry.npmjs.org/@aws%2Fkiro-cli` | 404 | Do-not-declare |
| `registry.npmjs.org/kiro-cli` | 200; 0.0.1; bin kirox; placeholder | Do-not-declare |
| `registry.npmjs.org/goose` | 200; 0.0.3; jiyinyiyong | Do-not-declare |

### E. Vendor documentation and install scripts

All fetched 2026-11-12. Raw captures are under `E/docs/` and `E/scripts/`.

| Source | Status / final URL | Used for |
|---|---|---|
| `https://github.com/openai/codex` README | 200 | Codex install methods, authority |
| `https://chatgpt.com/codex/install.sh` | 200 → `https://releases.openai.com/codex/install.sh` | Codex standalone layout |
| `https://developers.openai.com/codex/cli` | 200 → `https://learn.chatgpt.com/docs/codex/cli` | Codex info URL |
| `https://opencode.ai/v2/install` | 200 | OpenCode script layout |
| `https://opencode.ai/download` | 200 → `https://opencode.ai/product` | OpenCode install routes |
| `https://opencode.ai/docs/` (from `/v2/docs/`) | 200 | OpenCode info |
| `https://opencode.ai/docs/cli/` | 200 | OpenCode uninstall |
| `https://docs.x.ai/build/overview` | 200 | Grok identity/install |
| `https://x.ai/cli/install.sh` | 200 | Grok layout |
| `https://code.claude.com/docs/en/setup` | 200 | Claude identity/version/uninstall |
| `https://claude.ai/install.sh` | 200 → `https://downloads.claude.ai/claude-code-releases/bootstrap.sh` | Claude native layout |
| `https://geminicli.com/docs/get-started/installation/` | 200 (after one retry) | Gemini identity/banner |
| `https://geminicli.com/docs/resources/uninstall/` | 200 | Gemini uninstall |
| `https://docs.cline.bot/usage/cli-overview` | 200 | Cline CLI overview |
| `https://docs.cline.bot/cli/cli-reference` | 200 | Cline version/update |
| `https://docs.cline.bot/cline-cli/installation` | 200 → `/getting-started/installing-cline` | Cline install |
| `https://hermes-agent.nousresearch.com/docs/getting-started/installation` | 200 | Hermes layouts |
| `https://hermes-agent.nousresearch.com/docs/getting-started/updating` | 200 | Hermes version/update/uninstall |
| `https://hermes-agent.nousresearch.com/install.sh` | 200 | Hermes source installer |
| `https://aider.chat/docs/install.html` | 200 | Aider install |
| `https://aider.chat/docs/config/options.html` | 200 | Aider `--version` |
| `https://goose-docs.ai/docs/getting-started/installation/` | 200 | Goose install |
| `https://goose-docs.ai/docs/guides/goose-cli-commands` | 200 | Goose version/update |
| `https://github.com/aaif-goose/goose/releases/download/stable/download_cli.sh` | 200 | Goose script layout |
| `https://kiro.dev/docs/cli/` | 200 | Kiro identity |
| `https://kiro.dev/docs/getting-started/installation/` | 200 | Kiro install/uninstall/version |
| `https://cli.kiro.dev/install` | 200 | Kiro script layout |
| `https://docs.qoder.com/cli/installation` | 200 | Qoder install/version/uninstall |
| `https://docs.qoder.com/cli/cli-reference` | 200 | Qoder `--version` |
| `https://qoder.com/install` | 200 → `https://download.qoder.com/qodercli/install.sh` | Qoder script layout |
| `https://github.com/deepseek-ai/deepseek-harness` README | 200 | DSH identity |
| `https://raw.githubusercontent.com/deepseek-ai/deepseek-harness/master/docs/cli-help.md` | 200 | DSH `-V/--version`, `$DSH_HOME` |
| `https://github.com/can1357/oh-my-pi` README | 200 | OMP tap/npm routes |
| `https://omp.sh/docs/quickstart` | 200 | OMP install/version |
| `https://omp.sh/install` | 200 → `https://raw.githubusercontent.com/can1357/oh-my-pi/main/scripts/install.sh` | OMP script layout |
| `https://antigravity.google/docs/getting-started/` | 200; canonical | AGY identity/install/version |
| `https://antigravity.google/product/antigravity-cli` | 200 | AGY product identity |
| `https://antigravity.google/cli/install.sh` | 200 | AGY script layout |
| `https://antigravity.google/docs/cli/install/` | 200 but redirects through `/docs/install?tab=cli`; not the frozen URL | URL-stability note |
| `https://antigravity.google/llms.txt` | 200 | AGY docs index |
| `https://docs.qoder.com/` pages | 200 | Qoder docs |
| `https://opencode.ai/v2/docs/cli/#uninstall` | old path; current `/docs/cli/#uninstall` | URL-stability note |

The vendor install scripts were **read as text and never executed**: Codex, Claude, Grok, OpenCode,
Hermes, Goose, Kiro, Qoder, AGY, OMP. The Kiro and Goose scripts were read specifically to close
the open flags.

### F. Scratch cleanup record

`E/scratch/cleanup.txt`:

```text
# Scratch cleanup (2026-11-12)
2026-11-12T16:47:53Z
before: 2.8G
after: 0
remaining entries:
exit: cleanup completed
```

`E/scratch/manifest-before-cleanup.txt` records the pre-cleanup tree: npm installs for Claude and
Gemini, the uv tool environment for Aider, the Goose tarball, the Kiro zip and extracted cask, the
scratch npm cache, and the scratch uv cache. The scratch directory is empty after cleanup.
Transcripts and registry snapshots remain under `E/`.

### G. Held and unverified list

**Held rows: none.** Every flag was confirmed and every version shape was measured.

Still `unverified`, with the missing evidence named:

1. **Homebrew installation trees** for every formula/cask entry. No `brew install` was run (the
   brief forbids it). The registry listings and artifact mappings are `verified-docs`; the actual
   `Cellar/` or `Caskroom/` trees are unobserved. A read-only inspection of an already-installed
   Homebrew copy would resolve it.
2. **Codex cask installation tree** and the cask's runtime ownership. The artifact mapping is
   verified; the tree is not.
3. **Claude native `~/.local/share/claude/versions/` tree** and native auto-update behavior on this
   machine. The layout is documented; the tree is not observed. The scratch npm install measured
   the npm path, not the native path.
4. **Gemini MacPorts layout** and the formula Cellar tree. MacPorts is not declarable.
5. **Cline signature-shim behavior under execution.** The shim was read, never executed; executing
   it would mutate a personal installation. Its existence and logic are recorded; its runtime
   effect is not measured.
6. **Goose CLI removal instructions.** None were found on the official installation/commands pages.
   A vendor page or a `goose --help` uninstall subcommand would resolve it; neither is published
   in the reviewed pages.
7. **Kiro cask Homebrew installation tree.** The artifact was downloaded and measured; no Homebrew
   install was run. The DMG `Kiro CLI.app` path in the script is read, not executed.
8. **Qoder native script's final placement algorithm.** The script delegates to `qodercli install`;
   the observed `~/.qoder/bin/...` layout is local evidence, not a vendor statement. Reading the
   binary's install subcommand or vendor docs would resolve it.
9. **AGY cask installation tree** and legacy root provenance. The legacy `~/.gemini/bin/agy` 1.2.12
   copy is observed only; no vendor page documents it.
10. **Codex standalone installer runtime** beyond the script text. The script was read, not executed;
    its destination is documented by the script, but the actual runtime tree is not observed.
11. **`opencode-ai` npm package's repository/official relationship.** The registry version metadata
    has no repository field; its 1.19.5 version aligns with the v1 tap, but the relationship is not
    independently documented. It remains a declared candidate, not ownership proof.
12. **`@qoder-ai/qodercli` repository field.** The registry metadata has no repository field; the
    official Qoder docs name the npm package. The package name is verified; its source repository
    is not.
13. **Codex information-URL permanence.** `developers.openai.com` currently redirects to
    `learn.chatgpt.com`. The recommendation is keep; if the redirect is removed, replace with the
    canonical target or the GitHub README.
14. **AGY old `/docs/cli/install/` URL.** It currently redirects through an authentication page;
    the canonical getting-started URL is frozen instead. The old URL is not stable enough to cite.

### H. Worker report

Produced by the sole implementer named in the M11-A brief. This report is worker evidence, not
acceptance (D-014).

- **What was measured.** Five unverified `--version` shapes in disposable scratch, all successful:
  `claude` (`2.1.322 (Claude Code)`), `gemini` (`0.68.0`), `aider` (`aider 0.86.2`), `goose`
  (` 1.59.0`), `kiro-cli` (`kiro-cli 3.2.1`). Fourteen additional local version runs covered every
  installed catalogue tool, including both Codex prefixes, both OpenCode executables, both Cline
  prefixes, both Qoder executables, both OMP copies, and the AGY legacy copy. Five absent binaries
  were recorded as not installed.
- **What failed.** One local version run failed as expected: the user-prefix Codex copy exits 1
  because `@openai/codex-darwin-arm64` is missing. This is the expected unknown-version case, not
  a measurement failure. No scratch route failed.
- **What remains unverified.** The list in §G. No row is held.
- **Deviations.** (1) Version runs of vendor binaries caused incidental cache/log writes outside
  `R/`: two empty `~/.gemini/projects.json.*.tmp` files at 18:43, Qoder logs and
  `~/.qoder/.cache/dns-cache.json`, and a Codex `~/.codex/tmp/arg0-macos` entry. No personal
  installation was installed, updated, uninstalled, or re-signed; the Cline shim was never
  executed. Hermes gateway state in `~/.hermes` also changed during the window, but that daemon is
  background activity and is not attributed to the version query. (2) Install/download steps
  exceeded 25 s (44 s npm, 75 s Kiro download); the 25 s cap was applied to every version query,
  all of which finished within it. (3) `docs/` did not exist; it was created for the allow-listed
  document. No other repository file was touched.
- **External repository change.** HEAD advanced during the phase from `197d632` to `93c169d`
  (owner-authorization docs commit touching `ROADMAP.md` and `briefs/`). It is not a worker
  change; `git status` shows only this new document.
- **Safety.** No `brew install`/`brew update`, no vendor install-script execution, no personal npm
  or uv install, no subagent, no other CLI, no credentials in output. Scratch was destroyed and
  its cleanup is recorded in §F.
