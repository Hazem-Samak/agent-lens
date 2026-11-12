# M11-A — identity freeze: orchestrator acceptance record

Date: 2026-11-12. Orchestrator: Qoder (Herdr `t7x`). Phase brief:
[briefs/M11-A-identity-freeze.md](../briefs/M11-A-identity-freeze.md) (frozen at dispatch commit
`197d632`). Implementer: DeepSeek V4.1 Flash 1017 via OMP (`river`), max reasoning, sole writer.

**Decision: M11-A is technically accepted.** The deliverable `docs/catalogue-identities.md`
(revision 1, 928 lines) is the frozen identity packet for M11 coding phases. This record is the
orchestrator's independent acceptance, not the worker's self-report (D-014).

## Candidate identity

- Branch `milestone/m11-catalogue`; worker started at `197d632`; orchestrator docs commit
  `93c169d` (owner authorizations) landed during the phase and was correctly reported by the
  worker as external. The candidate is the working-tree document plus this acceptance record,
  committed by the orchestrator (worker made no Git mutation).
- Evidence root: `/Users/corvette/.hermes/cache/scratch/agent-lens-m11-Jb11B5` (`E/` below).

## Requirement-to-evidence results

| Requirement | Result | Evidence |
|---|---|---|
| Only allow-listed file changed | PASS | `git status`: only untracked `docs/`; 425-file SHA-256 protected manifest: all OK |
| 14 entries, every field marked + cited | PASS | Full read of the packet; marks `verified-docs`/`observed-local`/`unverified`/`binding-plan` kept distinct; no mark upgrades |
| Five unverified version shapes measured in disposable scratch | PASS | `E/scratch/*-version.json`: claude `2.1.322 (Claude Code)` 2291 ms; gemini `0.68.0` 810 ms; aider `aider 0.86.2` 3747 ms; goose ` 1.59.0` 1109 ms; kiro-cli `kiro-cli 3.2.1` 2565 ms; exact argv + exits recorded |
| Measurement consistency with primary registries | PASS | All five measured versions equal the registry versions the orchestrator independently fetched (cask `claude-code@latest` 2.1.322; formula `gemini-cli` 0.68.0; formula `aider` 0.86.2; formula `block-goose-cli` 1.59.0; cask `kiro-cli` 3.2.1) |
| Kiro artifact integrity | PASS | Worker SHA-256 `bfda7f0b…87f06` equals the official cask API `sha256` (orchestrator re-fetch) |
| Local read-only observations | PASS | `E/local/`: 14 successful version runs incl. both Codex prefixes, both OpenCode executables, both Qoder executables, both OMP copies, AGY legacy copy; expected Codex user-prefix optional-dependency failure recorded raw; 5 absent binaries recorded |
| Do-not-declare table re-cited | PASS | 14 rows with registry URLs; orchestrator re-confirmed `@oh-my-pi/cli` 404 and pressly `goose`/`block-goose-cli` conflict |
| Open flags closed | PASS | Aider `--version` documented ("Show the version number and exit", orchestrator re-fetch of options.html); Kiro script read (dest `~/.local/bin`, cask-only package); Codex URL redirect resolved (keep); OpenCode taps live; Qoder wordings recorded without picking |
| Scratch destroyed | PASS | `E/scratch/cleanup.txt` 2.8G → 0; `R/scratch` empty at acceptance; transcripts retained (83M) |
| No held rows; honest unverified list | PASS | §G lists 14 named unverified items (Homebrew/Caskroom trees unobserved, etc.) |

## Orchestrator spot-checks (independent)

- Kiro cask SHA-256 vs worker download record: exact match.
- `https://registry.npmjs.org/@oh-my-pi%2Fcli`: 404 confirmed.
- `https://aider.chat/docs/config/options.html`: `--version` description matches the citation.
- Earlier judge-phase fetches (same day) corroborate: `hermes-agent`, `cline` (deprecated),
  `gemini-cli` (deprecated, replacement `antigravity-cli`), `antigravity-cli` cask,
  `block-goose-cli`, `claude-code`/`claude-code@latest`, `@oh-my-pi/pi-coding-agent`.

## Deviations reported by the worker — assessed

1. **Incidental vendor runtime writes during `--version` runs** (empty `~/.gemini/projects.json.*.tmp`,
   Qoder logs/DNS cache, Codex `~/.codex/tmp/arg0-macos`). Assessed: these are the vendor tools'
   own runtime artifacts from executing them — the same execution the product itself performs —
   not installation, update, or configuration mutations. Acceptable; disclosed honestly. Hermes
   daemon state change correctly attributed to background activity, not the query.
2. **Install/download steps exceeded 25 s** (44 s npm claude, 75 s Kiro download). Assessed: the
   brief's 25 s cap applies to version queries; every query finished within it. Install caps were
   larger and disclosed. Acceptable interpretation.
3. **`docs/` directory created.** Implicit in the allow-listed new file. Acceptable.

Install caches were correctly redirected into scratch (npm cache + empty npmrc; uv cache/tool/bin/
python dirs), so no personal manager state was touched by the installs.

## Findings carried into later phases (binding)

- **Aider cold start 3747 ms > 3 s version-query budget** (`ToolDetector.versionTimeout`): cold
  uv/Python starts may render unknown. Unknown is safe; the timeout is NOT raised in M11. The
  capability matrix must carry this limit. Claude (2291 ms) and Kiro (2565 ms) are inside budget
  but close; same rule.
- **URL corrections for M11-C:** OpenCode information URL → `https://opencode.ai/docs/` and
  uninstall → `https://opencode.ai/docs/cli/#uninstall` (old `/v2/docs/` paths redirect); AGY
  information URL → `https://antigravity.google/docs/getting-started/` (canonical); Codex
  information URL kept (redirect absorbs host migration).
- **Deprecation calendar:** formula `cline` disabled 2027-05-18; formula `gemini-cli` disabled
  2026-12-18 (replacement cask `antigravity-cli`). Matrix limits, not removals (OD-6 keeps Gemini).
- **Uninstall instruction URLs** exist for Claude, Gemini, OpenCode, Hermes, Kiro, Qoder; honest
  absence for the rest — never invented.
- All frozen queries are `["--version"]` / stdout / first; no per-tool parsing.

## Limits

- No Homebrew `Cellar/`/`Caskroom/` tree was observed (brief forbids `brew install`); registry
  listings and artifact mappings are verified, trees are not. Fixture cells stay `synthetic`.
- The packet freezes identity, not ownership; declared candidates remain non-proof (M9 contract).
- No product code changed; the mutation gate (M11-B) is still ahead.

## Team and process

Sole implementer DeepSeek V4.1 Flash 1017/OMP max (owner-selected). Orchestrator citation review
per the plan (no independent code review required for a docs-only phase). Herdr/hc orchestration
only, per the owner's binding rule. Worker terminal retired after acceptance.