# M11-A — catalogue identity freeze (dispatch brief)

Status: authorized for implementation by the owner on 2026-11-12 ("proceed to implementation",
implementer named below). This is a worker brief, not acceptance evidence. Freeze this revision
once dispatched; corrections use a separate revision brief.

## Identity and authority

- Phase: M11-A, revision 1. Milestone branch: `milestone/m11-catalogue`.
- HEAD baseline: `d98bf7be3e81e0a659757ab19d1c76bd301617c2` (frozen M11 master plan on top of
  `d0a2b41`). Work on this branch only.
- Sole implementer: **DeepSeek V4.1 Flash 1017 via OMP** (`river/deepseek-ai/DeepSeek-V4.1-Flash-1017`,
  `--thinking max`), owner-selected 2026-11-12. No other implementer, subagent, provider, model or
  CLI. Do not start other agents.
- Orchestrator (Qoder, Herdr `t7x`) owns review, acceptance, and all Git delivery. **Do not stage,
  commit, branch, reset, merge, push, or publish.** Leave changes in the working tree.
- Evidence root `R`: `/Users/corvette/.hermes/cache/scratch/agent-lens-m11-Jb11B5`.
  Use `R/worker-a` for artifacts, `R/tmp` for TMPDIR, `R/scratch` for disposable measurements,
  `R/evidence` for transcripts. Never put generated scaffolds in the repository.
- Master plan: `briefs/M11-plan.md` (frozen). Council judgment: `briefs/M11-planning/judgment.md`.
  Owner approvals OD-1…OD-10 are recorded as approved-by-delegation on 2026-11-12 except OD-7
  (license), which remains the owner's open choice; no LICENSE file is created in this phase.

## Goal and exclusions

Produce `docs/catalogue-identities.md`: the frozen, cited identity packet for all 14 catalogue
entries, so later coding phases copy rows instead of re-deriving identity. Every field carries an
evidence mark and, when `verified-docs`, a source URL.

No registry edit, no product/test/script/CI change, no matrix, no UI, no license file, no detector
implementation. Research and measurement only, plus the one document.

## Read set

1. This brief.
2. `briefs/M11-plan.md` §4 (catalogue summary + do-not-declare table), §5 M11-A, §7.
3. `briefs/M11-planning/judgment.md` (rulings R1–R12 and the judge's verified registry facts).
4. `briefs/M11-planning/proposal-grok.md` §B and `briefs/M11-planning/proposal-minimax.md`
   §B + appendices — research leads with citations. Treat them as claims to re-verify, not truth.
Do not read the full scope document; it dilutes focus.

## Allow-list

- Add `docs/catalogue-identities.md` (the only repository file you may create or edit).

DO NOT TOUCH: everything else — all `Sources/`, `Tests/`, `scripts/`, `Resources/`,
`Package.swift`, `.github/`, existing `briefs/**` and `walkthroughs/**`, `README.md`,
`DECISIONS.md`, `ROADMAP.md`, `AGENT_LENS_SCOPE.md`, system preferences, personal installed
tools/managers, the real Agent Lens cache, user environment, credentials. If another file seems
required, stop and report why.

## Evidence marks

- `verified-docs` — re-confirmed against a primary vendor source (official docs/repo, npm/PyPI/
  Homebrew registry listing) during this phase; URL recorded with fetch date.
- `observed-local` — measured read-only on this machine during this phase; raw output recorded.
- `unverified` — could not confirm; state exactly what is missing and what would resolve it.
Never upgrade a mark without the evidence. A confident guess is a defect.

## Work items

1. **Rows for all 14 entries** (plan §4): vendor/project, executable, category, declared package
   candidates per manager, install layouts with path patterns, version-query specification
   (arguments/stream/line) with the raw measured or documented output line, information URL,
   uninstall-instructions URL or explicit "none published", known limits, evidence marks, URLs.
   Re-verify and freshly cite the judge-verified listings: formulae `hermes-agent`, `cline`
   (deprecated 2026-05-18, disabled 2027-05-18), `gemini-cli` (deprecated 2026-06-18, disabled
   2026-12-18, replacement cask `antigravity-cli`), `block-goose-cli`, `aider`; casks `claude-code`,
   `claude-code@latest`, `antigravity-cli`, `kiro-cli` (formula `kiro-cli` is 404), `codex`; npm
   `@oh-my-pi/pi-coding-agent` (bin `omp`), `@deepseek-ai/dsh`, `@anthropic-ai/claude-code`,
   `@google/gemini-cli`, `cline`, `@qoder-ai/qodercli`; tap `can1357/tap/omp`; core formula
   `opencode`. Record deprecations/disable dates as known limits.
2. **Close the open flags (read-only):**
   - Aider: confirm the version flag from the official CLI reference (not just the install page).
   - Kiro CLI: fetch `https://cli.kiro.dev/install` and READ the script text; record the destination
     directory and any version hints. **Never execute it.** Cross-check the cask `kiro-cli` zap
     list (`~/.local/bin/kiro-cli`).
   - Codex: check whether `https://developers.openai.com/codex/cli` is a stable install page;
     the GitHub README is the install authority either way. Recommend keep/replace with evidence.
   - OpenCode: re-verify taps `anomalyco/tap/opencode-v2` and `anomalyco/tap/opencode` are live.
   - Qoder: record both official wordings (`qoder` dispatcher vs `qodercli` runtime). Do not pick;
     the plan rules `qodercli` (OD-4 approved).
3. **Measure the five unverified version shapes in disposable scratch (OD-8 authorized).**
   Exactly these routes, all inside `R/scratch`, never touching personal installations:
   - `claude`: `npm install --prefix R/scratch/claude @anthropic-ai/claude-code`, then run the
     installed binary's `--version`. If postinstall fails (missing optional platform dependency),
     record the failure raw — that is itself the expected unknown-version case.
   - `gemini`: `npm install --prefix R/scratch/gemini @google/gemini-cli`, then `--version`.
   - `aider`: `UV_TOOL_DIR=R/scratch/uv/tools UV_TOOL_BIN_DIR=R/scratch/uv/bin uv tool install
     --python 3.12 aider-chat` (or the documented equivalent), then `--version`.
   - `goose`: download the official release binary from the canonical `aaif-goose/goose` stable
     release asset into `R/scratch/goose` (read the download script to find the asset URL; do not
     execute the script), then `--version`.
   - `kiro-cli`: download the official cask artifact (URL from the cask JSON) into
     `R/scratch/kiro`, extract, run `kiro-cli --version`.
   For each: record exact argv, raw first output line(s), stream (stdout/stderr), exit code,
   duration. Use a timeout (≤25 s). If a route fails or is unavailable, mark the shape
   `unverified` with the raw failure — do not improvise another route without reporting.
   **Destroy `R/scratch` contents when done and record the cleanup** (keep transcripts in
   `R/evidence`). No other installs anywhere.
4. **Version-query rules:** the specification must match measured/documented behavior. Where the
   flag is confirmed but the stream/shape is unknown, say so; failure→unknown is safe. Where the
   flag itself cannot be confirmed from primary docs AND cannot be measured, mark the row `held`
   and name this brief's stop condition. Never invent argv.
5. **Do-not-declare table** (plan §4, binding): brew `dsh` (Dancer's shell); npm/PyPI/brew `goose`
   (unrelated/pressly); npm `kiro-cli` placeholder (bin `kirox`); cask `qoder` (IDE);
   `@oh-my-pi/cli`; third-party PyPI `deepseek-harness*`; npm `qoder`/`@qoder-ai/qoder`/
   `@aws/kiro-cli` (404); desktop casks `opencode-desktop`, `block-goose`; PyPI
   `google-antigravity` (SDK). Re-cite each with a registry URL.
6. **Known limits per entry**, including: source-heuristic classification (cask/script/uv installs
   classify `standalone`; npm under `/opt/homebrew/bin` is not a formula; Tern copies are not
   taps); second executables (`opencode2`, `hermes-agent`, `hermes-acp`, `qoder` dispatcher) are
   limits, not detectors; vendor self-updaters (`agy update`, `goose update`, `cline update`,
   `hermes update`, `qoder update`, cask `auto_updates`) are never Agent Lens operations;
   personal artifacts (Cline signature shim, Tern store, versioned runtime filenames) are never
   layouts/roots/fixtures; AGY legacy root `~/.gemini/bin` is `observed-local` with a limit note.
7. **Evidence appendix** in the same document: raw measurement transcripts, fetched URLs with
   dates, scratch cleanup record, and an explicit list of everything still `unverified`/`held`.

## Safety envelope

- Read-only on the product and on personal installations. The only writes: the allow-listed doc
  and `R/**`.
- No git mutations of any kind. No subagents or other CLIs. No credentials in output.
- Never execute vendor install scripts; reading them is allowed. No manager mutating subcommand
  against personal installs (`npm install` only with the scratch `--prefix` routes above; `uv`
  only with the scratch env above). No `brew install`/`brew update` anywhere.
- Network reads only from official vendor/registry sources named in this brief or the plan.

## Acceptance (orchestrator-run, not worker-claimed)

- Citation review: every `verified-docs` field independently re-checked against its URL.
- `git status`/diff shows only `docs/catalogue-identities.md`; protected-file SHA-256 manifest
  (taken by the orchestrator at dispatch) unchanged.
- Every entry/field marked; held rows name the reason; raw measurement lines present for every
  claimed measurement; scratch cleanup recorded.
- The worker's report is evidence to inspect, never acceptance itself (D-014).

## Stop conditions

Stop and report (do not improvise) if: a primary source is unreachable and no second primary
source resolves the fact; an identity cannot be disambiguated from a same-named project; a
measurement would require touching a personal installation or an unlisted route; any product
file seems to need editing; a tool prompt asks for credentials or privileges.

## Report contract

When done — or stuck — send:

```sh
hc send t7x "M11-A complete: docs/catalogue-identities.md — <entries frozen/held, measurements succeeded/failed, open items>"
```

The document is the deliverable; the message is a pointer and summary. Include in the document a
short worker report section: what was measured, what failed, what remains unverified, and any
deviation from this brief (deviations must be reported, not silently taken).