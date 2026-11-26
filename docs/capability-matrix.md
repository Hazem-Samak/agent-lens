# Capability matrix

Status: **M11-F deliverable; M13-F extends the mutation grammar and corrects the agy cask limit.**
One row per bundled detector, in registry order. The source of truth is
[`Sources/AgentLensCore/Detectors/DefaultDetectors.json`](../Sources/AgentLensCore/Detectors/DefaultDetectors.json);
every identity claim below is copied from the frozen
[`docs/catalogue-identities.md`](catalogue-identities.md) packet. `Tests/AgentLensCoreTests/CapabilityMatrixTests.swift`
parses this table and fails if a row disagrees with the registry or a cell breaks the rules below.

**How to read the capability cells.**

- `tested fixture` is a **synthetic** layout that proves the detector and the source classifier.
  It never proves a vendor installation, and an unobserved vendor layout is never called
  "verified".
- `declared packages` are candidate identities copied from the registry. A declaration is never
  ownership proof, install proof, or mutation authority.
- `latest-check` `yes` means the shipped read-only latest probe can query that ecosystem. A
  declared cask now lists `yes: homebrewCask` beside any npm/formula probes (M13-B ships the
  read-only cask latest-check); it still never implies a cask mutation.
- `Update` / `Uninstall` `yes` uses the exact grammar in this table. The only accepted affirmative
  segments are:
  - `yes: npm (verified npm-global copies only)`
  - `yes: homebrewFormula (verified Homebrew formula copies only)`
  - `yes: homebrewCask (verified Homebrew cask copies only)`

  A segment is permitted only when the entry's `acceptedOperations` contains the matching
  kind-specific operation **and** the entry declares a candidate of that same manager kind **and**
  that manager's ownership probe verified the copy. An accepted grant with no matching declared
  candidate is never advertised as `yes`. When one cell has multiple accepted, proved managers,
  the segments appear in the fixed order `npm`, `homebrewFormula`, `homebrewCask`, joined by
  `; ` (for example `yes: npm (verified npm-global copies only); yes: homebrewCask (verified
  Homebrew cask copies only)`). No other `yes` spelling is accepted. Every row without an
  accepted and matching manager is `informational: <non-empty reason>` or `disabled: <non-empty
  reason>`; the reason cannot be empty, even though the cell itself is non-empty.
- Homebrew eligibility shown here is a published claim rule, not yet an app button. M13-G owns the
  native mutation presentation; a `yes` cell does not mean Update/Uninstall controls are exposed
  in the app.
- Vendor self-updaters (`claude update`, `codex` installer rerun, `opencode uninstall`,
  `cline update`, `hermes update`/`hermes uninstall`, `goose update`, `kiro-cli update`/`kiro-cli
  uninstall`, `qoder update`, `agy update`, cask `auto_updates`) are never Agent Lens operations.

| id | display name | category | tested fixture | declared packages | latest-check | Update | Uninstall | known limits |
|---|---|---|---|---|---|---|---|---|
| codex | Codex | aiAgent | synthetic npmGlobal | npm:@openai/codex; homebrewCask:codex | yes: npm; yes: homebrewCask | yes: npm (verified npm-global copies only) | yes: npm (verified npm-global copies only) | Optional-dependency install failure yields unknown version, never an error; cask and standalone installer copies classify `standalone`; the vendor installer rerun is not an Agent Lens operation; an npm copy under the Homebrew prefix is npm, not a formula; the cask has no formula listing. |
| opencode | OpenCode | aiAgent | synthetic singleDirectory | npm:@opencode/cli; npm:opencode-ai; homebrewFormula:anomalyco/tap/opencode-v2; homebrewFormula:anomalyco/tap/opencode; homebrewFormula:opencode | yes: npm; yes: homebrewFormula | informational: no accepted mutation scenario (M11) | informational: no accepted mutation scenario (M11) | `opencode2` is a second executable in the npm package and the standalone directory, not a second detector; both tap formulae install `opencode` and the v2 tap declares a conflict, so only one Homebrew copy can own the binary; desktop cask `opencode-desktop` is excluded; `~/.opencode/bin` is off the measured login-shell PATH. |
| grok | Grok CLI | aiAgent | synthetic singleDirectory | none | disabled: no declared package | disabled: no declared package | disabled: no declared package | No package identity is documented or declared; do not invent one. The version line carries a build hash and channel token (`grok 1.0.77 (50ca579fa996) [stable]`), so the first token wins. The versioned download filename is a personal artifact, never a root or fixture; the installer shell-config edit is vendor behavior. |
| claude | Claude Code | aiAgent | synthetic singleDirectory | npm:@anthropic-ai/claude-code; homebrewCask:claude-code; homebrewCask:claude-code@latest | yes: npm; yes: homebrewCask | informational: no accepted mutation scenario (M11) | informational: no accepted mutation scenario (M11) | The native launcher `~/.local/bin/claude` is a symlink into a `versions/` store, which is not a fixture or a search root; background auto-update is vendor-owned; the npm package relies on an optional platform dependency and a postinstall link, so a missing dependency yields unknown version, never an error; both casks classify `standalone`; stable and latest are separate cask channels. |
| gemini | Gemini CLI | aiAgent | synthetic npmGlobal | npm:@google/gemini-cli; homebrewFormula:gemini-cli | yes: npm; yes: homebrewFormula | informational: no accepted mutation scenario (M11) | informational: no accepted mutation scenario (M11) | Formula `gemini-cli` is DEPRECATED 2026-06-18 (`unsupported`) and DISABLED 2026-12-18; the recommended replacement cask is `antigravity-cli`; the upstream transition banner says Gemini CLI was replaced by Antigravity CLI on 2026-06-18; MacPorts and npx install routes are not declarable in M11; the Cellar tree is a declaration, not an observed installation. |
| cline | Cline CLI | aiAgent | synthetic npmGlobal | npm:cline; homebrewFormula:cline | yes: npm; yes: homebrewFormula | informational: no accepted mutation scenario (M11) | informational: no accepted mutation scenario (M11) | Formula `cline` is DEPRECATED 2026-05-18 (non-FOSS SDK and pre-built binaries) and DISABLED 2027-05-18; the personal signature shim `~/.local/shims/cline` is not a layout, root, or fixture; npm under the Homebrew prefix is not a formula (`/lib/node_modules/` after resolution); `cline update` is vendor-owned. |
| hermes | Hermes | aiAgent | synthetic singleDirectory | homebrewFormula:hermes-agent | yes: homebrewFormula | yes: homebrewFormula (verified Homebrew formula copies only) | yes: homebrewFormula (verified Homebrew formula copies only) | A git-checkout install classifies `standalone`; PyPI `hermes-agent` is documented but not declarable in M11; second executables `hermes-agent` and `hermes-acp` are known limits, not detectors; the multi-field version line yields its first token (`Hermes Agent v0.23.1 ...`); `hermes update` and `hermes uninstall` are vendor-owned. |
| aider | Aider | aiCodingTool | synthetic singleDirectory | homebrewFormula:aider | yes: homebrewFormula | yes: homebrewFormula (verified Homebrew formula copies only) | yes: homebrewFormula (verified Homebrew formula copies only) | Cold start measured 3747 ms, above the 3 s version-query budget, so a cold start yields unknown version (safe, never guessed); uv, pip, and pipx `aider-chat` are not declarable in M11; the vendor warns that system package managers often install incorrect dependencies. |
| goose | Goose | aiCodingTool | synthetic singleDirectory | homebrewFormula:block-goose-cli | yes: homebrewFormula | yes: homebrewFormula (verified Homebrew formula copies only) | yes: homebrewFormula (verified Homebrew formula copies only) | The basename `goose` is shared with pressly formula `goose` (3.30.1); any mutation identity is the declared formula `block-goose-cli`, never the basename; desktop cask `block-goose` is excluded; the formula installs helper binaries `generate_manpages` and `mcp_conformance_driver`; the script default `~/.local/bin/goose` is a different layout. |
| kiro-cli | Kiro CLI | aiCodingTool | synthetic singleDirectory | homebrewCask:kiro-cli | yes: homebrewCask | yes: homebrewCask (verified Homebrew cask copies only) | yes: homebrewCask (verified Homebrew cask copies only) | Never detect `kiro` (the IDE/router); formula `kiro-cli` does not exist, the cask is the only frozen package; the installer `--version <semver>` option is not the CLI query; the DMG `Kiro CLI.app` surface is excluded; `kiro-cli update` and `kiro-cli uninstall` are vendor-owned. |
| omp | Oh My Pi | aiHarness | synthetic singleDirectory | npm:@oh-my-pi/pi-coding-agent; homebrewFormula:can1357/tap/omp | yes: npm; yes: homebrewFormula | informational: no accepted mutation scenario (M11) | informational: no accepted mutation scenario (M11) | npm `@oh-my-pi/cli` is a different project and is excluded (404 on 2026-11-12); the `/opt/homebrew/bin/omp` copy resolves to a Tern store, not the tap, and classifies `standalone`; bun is documented but not declarable in M11; the tap formula test corroborates the query but is not an installation. |
| agy | Antigravity CLI | aiHarness | synthetic singleDirectory | homebrewCask:antigravity-cli | yes: homebrewCask | informational: no accepted cask mutation scenario | informational: no accepted cask mutation scenario | The legacy root `~/.gemini/bin` is observed-local only (R10), not a documented default; the cask does not declare `auto_updates` (absent since 2026-11-13; the 2026-11-26 API reports null — not declared, not false), and its `command_wrapper` sets `AGY_CLI_DISABLE_AUTO_UPDATE=true` with a caveat to let brew manage updates rather than `agy update`; `autobump` is Homebrew source metadata, not a vendor self-updater; no install or runtime was observed; the desktop Antigravity App and Python SDK `google-antigravity` are excluded; the canonical information URL is the getting-started page; the local version and the cask version differ, so no pin. |
| dsh | DeepSeek Harness | aiHarness | synthetic npmGlobal | npm:@deepseek-ai/dsh | yes: npm | informational: no accepted mutation scenario (M11) | informational: no accepted mutation scenario (M11) | A developer preview with compatibility-breaking changes upstream; prerelease version tokens are normal (`0.2.2-rc.1`); brew formula `dsh` is Dancer's shell (never declared); third-party PyPI `deepseek-harness` and `deepseek-harness-cli` are excluded; `~/.dsh` is vendor data, not an install layout root. |
| qodercli | Qoder | aiCodingTool | synthetic singleDirectory | npm:@qoder-ai/qodercli | yes: npm | informational: no accepted mutation scenario (M11) | informational: no accepted mutation scenario (M11) | The `qoder` dispatcher can launch the IDE, so it is not the detector; the versioned runtime filename `qodercli-1.1.88` is a personal artifact, never a root or fixture; cask `qoder` is the IDE (never declared); the native script's final placement is delegated to the binary and is observed-local. |

## Cross-row source-classification note

Source classification is a heuristic: a resolved path containing `/lib/node_modules/` classifies
`npm`, a path containing `/Cellar/` classifies `brew`, and everything else classifies
`standalone`. Therefore cask binaries under a Homebrew prefix, script installs, uv/pip/pipx
installs, git checkouts, and Tern stores all classify `standalone`; npm globals under
`/opt/homebrew/lib/node_modules` classify `npm`; a Homebrew-prefix path is not formula proof.

The `standalone classification` is not ownership proof. A verified cask copy is Homebrew-owned
when the declared cask proof succeeds (Caskroom membership and the manager's own install record),
even while the source classifier still reports `standalone`. These are separate facts: the
heuristic stays unchanged for compatibility and display, while ownership uses the manager's
evidence. A cask cell's affirmative claim therefore rests on the verified cask proof, never on
the classifier and never on a basename.

Every `tested fixture` cell says `synthetic <layout>` because a fixture proves the detector
and classifier only — never a vendor installation. Second executables are known limits, not
detectors, and personal artifacts (signature shims, version stores, versioned runtime filenames)
are never roots or fixtures. The binding do-not-declare table is in
[`docs/catalogue-identities.md`](catalogue-identities.md).
