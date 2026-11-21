# M13 Planning Council — judgment record

Orchestrator/main judge: Hermes (Herdr `t12k`). Date: 2026-11-21.
Base commit for the freeze: `9b37a334eefd06802daa7bd006c6e995f8698af2` (`9b37a33`, `main` tip;
M0–M12 delivered). Milestone branch: `milestone/m13-homebrew`, created from that tip. Nothing
stacks; no rebase.

## Council composition and process

| Member | CLI / build | Model | Effort | Herdr terminal | Output |
|---|---|---|---|---|---|
| MiniMax | mcode v0.7.6 | MiniMax-M3.1-Flash (default route) | xhigh (status bar `M3.1-Flash · Effort xhigh`) | `t12r` m13-minimax | `proposal-minimax.md` |
| Grok | grok 1.0.89 | grok-4.7 | high (`--reasoning-effort high`, banner `Grok 4.7 (high)`) | `t12s` m13-grok | `proposal-grok.md` (revised once) |

- Shared task: `council-brief.md`. Members worked independently; both explicitly confirmed they
  did not read the other's proposal. Both were visible in the Agent Lens space panels (owner
  requested Herdr panels).
- Read-only on the product: no product edits, no git mutations, no builds/tests/app launches, no
  subagents; single writable proposal file each. Read-only brew queries allowed per brief §5.
- Process notes (disclosed):
  - mcode launched without `-m` (default route M3.1-Flash; M11 judgment records `-m` rejection on
    the en-prod route). Effort xhigh verified in the status bar before dispatch. mcode runs in its
    default **Full access** permission mode — the user's pre-existing setting, not a
    coordinator-added bypass.
  - grok launched with `--permission-mode acceptEdits`. Its first read-only brew research command
    blocked on a per-command permission dialog. After verifying the pending command was read-only
    and within brief §5, the coordinator selected the dialog's always-approve option — the same
    **session-scoped grant recorded in the M11/M12 judgments** — so bounded research and the single
    proposal write could proceed unattended. Repo integrity is audited before the freeze commit.
  - A dispatch wording slip told grok not to read `proposal-grok.md` (its own file) instead of
    naming minimax's file. The coordinator sent a mid-flight clarification naming
    `proposal-minimax.md` as the forbidden file; brief §5 independence was already loaded and
    binding. Independence confirmed at collection.
  - grok self-revised once (six corrections: one verifier dispatch rule; non-string `installed` →
    `.invalidManagerOutput` only; `list --pinned` matches formula rack basename or cask token; an
    older cask absent from plain outdated is not `updateAvailable`; cask upgrade keeps the saved
    appdir and unsets `HOMEBREW_CASK_OPTS`; codex/claude latest-check cells gain `yes: homebrewCask`
    while mutation cells stay unchanged). The revision was collected before adjudication.
  - minimax ran 1h18m; the coordinator sent one convergence nudge at 33% remaining context. It
    delivered a complete proposal; no content was supplied by the coordinator.
- Judge's independent research: six disposable scratch-prefix probe rounds (below), read-only
  personal-prefix brew queries, and read-only Homebrew source reads at the pinned checkout. The
  judge's verified facts win over either proposal where they conflict.

## Judge's independent baseline evidence

Baseline gates at `9b37a33` (orchestrator-run, Herdr `t12m`, logs
`~/.hermes/cache/scratch/agent-lens-m13-planning/baseline/`): all exit 0 — `swift build`; full
suite `--no-parallel` + CLT TestingMacros plugin flag (**467 Core + 119 AppSupport = 586**, zero
skips/failures); both import guards; guard fixtures **21**; dev-app build; packaging **9**;
`git diff --check`. CI floors/anchors read from `.github/workflows/ci.yml:180-209`.

Code seams verified by the judge (file:line at base): `HomebrewOwnershipProbe.swift:69,131,177`
(formula three-query proof), `:101-105` (`.unsupportedCask`), `:35-52` (FormulaProof.revalidate);
`HomebrewIdentity.swift:25-38` (login-PATH manager resolution), `:79-102` (Cellar component
parser); `HomebrewUpdateProbe.swift:204` (10s query), `:543-548` (diagnostic env), `:259-281`
(cask payload tolerated never consumed), `:554-692` (status resolver);
`InstallationOwnershipVerifier.swift:61-82` (source-string router; standalone →
`.unsupportedSource`); `DetectorMetadata.swift:78-81` (closed vocabulary), `:270-295` (shared
validator); `OperationModels.swift:261-278` (shared gate); `NpmUpdateOperation.swift:61-64`
(D-021 guard position), `:46-48` (60/60/120 budgets), `:266-355` (execute revalidation chain);
`WorkflowPresentation.swift:153-238` (ManagementPresentation, npm-shaped gates);
`CapabilityMatrixTests.swift:143,176-234` (test-enforced matrix rules);
`BoundedProcessRunner.swift:84,370` (POSIX_SPAWN_SETPGROUP only — **no SETSID**).

## Judge's disposable-prefix feasibility probe (rounds 1–6)

Route proven: `git clone --no-hardlinks /opt/homebrew <scratch>/prefix` (real brew code at
`456c79a994`, Homebrew 7.0.15-76-g456c79a); vendored portable-ruby copied read-only (satisfies
brew 7's Ruby 4.0 requirement; system Ruby 2.6 is insufficient); `HOMEBREW_CACHE/LOGS/TEMP` inside
scratch; `NO_AUTO_UPDATE/NO_ANALYTICS/NO_INSTALL_CLEANUP/NO_INSTALLED_DEPENDENTS_CHECK/NO_AUTOREMOVE=1`;
`NO_INSTALL_FROM_API=1` (offline); local tap `m13test/test` with `file://` tarball URLs; **stub
homebrew/core tap** (empty git repo — a `depends_on` formula otherwise triggers a full network
core clone); **`brew trust m13test/test`** (brew 7.x tap-trust gate for dependency loading); every
brew call stdin `</dev/null`; `--yes` on install/upgrade. Tier 3 "prefix not /opt/homebrew"
warning emitted; operations proceed. Evidence: `brew-feasibility-4b/log{,5,6}/`.

Verified manager facts (raw logs retained):

1. **Formula lifecycle offline**: install 1.0.0 → bump 1.2.0 → `outdated --json=v2 --formula`
   record `{name: FULL tap name, installed_versions, current_version, pinned, pinned_version}` →
   `upgrade --yes` → linked 1.2.0, **old keg 1.0.0 remains** (cleanup suppressed) → `uninstall`
   removes the linked keg only; "1.0.0 is still installed"; bin symlink **not relinked**
   (readlink fails); old keg remains installed-but-unlinked.
2. **Suppression proof**: sentinel formula kegs `[1.0.0, 1.0.1]` byte-identical before/after the
   target upgrade (NO_INSTALL_CLEANUP + NO_AUTOREMOVE effective).
3. **Pin refusal**: `brew pin` then `upgrade --yes` → exit 1 "Error: Not upgrading 1 pinned
   package", keg unchanged; unpin restores.
4. **Dependent uninstall refusal**: consumer depends_on m13-lib; `uninstall m13-lib` → exit 1
   "Refusing to uninstall … required by m13-consumer … override with --ignore-dependencies";
   both kegs remain.
5. **Broken update**: 1.0.1 install stanza `system "false"` → upgrade exit 1, old keg remains.
6. **Binary cask lifecycle**: install → `list --verbose --cask` prints staged Caskroom file (the
   canonical target of the prefix/bin symlink) + `.metadata` receipts → `info` `installed` string
   equals version dir → bump → `outdated --json=v2 --cask` record `{name: BARE TOKEN,
   installed_versions, current_version, pinned, pinned_version}` → `upgrade --yes` → `uninstall`
   → Caskroom token dir absent, bin symlink absent. Clean, no sudo.
7. **App cask**: `install --cask --appdir <scratch>/Applications` → `list --verbose` prints the
   staged `Caskroom/<token>/<ver>/M13Test.app` which is a **symlink** (readlink) to
   `<scratch>/Applications/M13Test.app`; the Mach-O inside is a strict descendant → `info`
   installed string → bump → `upgrade --yes` WITHOUT `--appdir` **keeps the saved scratch appdir**
   (install receipt config); `/Applications/M13Test.app` ABSENT → `uninstall` removes the scratch
   app + Caskroom. App-symlink membership PROVEN.
8. **sudo delete-stanza hazard**: a cask with `uninstall delete:` reaches "Removing files:
   <sentinel>" then a **sudo Password prompt on /dev/tty** even with stdin `</dev/null` (PTY
   context). Source: `abstract_uninstall.rb:670-683` runs xargs/rm with `sudo: true`
   unconditionally; pkgutil/kext/rmdir also elevate. Probe aborted (no password entered); cask
   remains installed `1.0.0`, stanza + zap sentinels intact. → **Casks with elevating/interactive
   uninstall stanzas must be refused from `artifacts` metadata BEFORE any process** (R7).
9. **Variant casks**: `auto_updates true` cask info reports True; `:latest` cask version string
   `"latest"`, installed `"latest"`; comma cask version `"1.2.3,9"` installed `"1.2.3,9"`. After
   bumps: `outdated --cask` plain → **[m13comma 1.2.4,10] ONLY** (auto_updates skipped, :latest
   skipped); `--greedy` → [m13auto, m13comma]; `--greedy-auto-updates` → [m13auto, m13comma];
   `--greedy-latest` → [m13comma] (:latest not detected without livecheck). → plain absence is NOT
   currency for auto_updates/:latest; **comma versions ARE brew-comparable** (the manager's
   verdict is the oracle; no invented comparator needed).
10. **Personal sentinels**: formulae/casks/Cellar/Caskroom/pinned lists byte-identical pre/post
    across ALL rounds; personal `brew --prefix` still `/opt/homebrew`.

Read-only personal-prefix/API observations (judge): `auto_updates` null for codex/claude-code/
kiro-cli/antigravity-cli; **iterm2 (NOT installed) reports true** → the API reports the source
declaration regardless of install state; **null = not declared** (Homebrew `dsl.rb:166-167,665-667`
nilable; `cask.rb:875` treats nil falsy). The agy cask source at HEAD has NO `auto_updates` stanza
(minimax fetched upstream: revision `60c151f6` 2026-11-12 had `auto_updates true`; changed
2026-11-13 to `command_wrapper` + `AGY_CLI_DISABLE_AUTO_UPDATE=true`). The M11 matrix agy note is
**stale**. codex/claude-code/kiro-cli casks: `binary` artifact, **no uninstall stanza**; agy:
`command_wrapper`, no uninstall stanza, comma version. `brew upgrade --help`: `-y, --no-ask,
--yes` ("Ask mode is the default"); dependents-check and cleanup paragraphs; `--no-quit`;
`--appdir`. `brew uninstall --help`: no `--yes`; `--force`/`--zap`/`--ignore-dependencies`.
man brew: `HOMEBREW_NO_AUTOREMOVE` governs cleanup AND uninstall autoremove.

## Evaluation criteria (council-brief §7)

Truthfulness/evidence; phase boundedness/dispatch-readiness; fidelity to settled decisions and
safety invariants; acceptance-environment rigor; owner-vs-technical separation. Both proposals
are high quality, independently verified, and agree on the load-bearing bounds: four
per-kind×operation vocabulary cases, additive schema 2, shared gate, M10 lifecycle, separate cask
cache document, new brew sheets with npm sheets byte-identical, scratch-prefix acceptance, no CLI
mutation syntax, no force/zap/ignore-dependencies/greedy/brew-update, floors raise-only at
combined. Where they diverge, the judge rules below; verified probe facts win.

## Rulings (binding on the dispatch briefs)

**R1 — Cask ownership: declared-candidate routing + four-query membership proof; no receipt
parser.** New cask route entered by a declared `homebrewCask` candidate, NOT the source heuristic
(the heuristic classifies cask copies `standalone` and never reaches Homebrew today — both
proposals' central finding, verified). Routing order: source `npm` + npm declaration → npm proof
(unchanged); source `brew` + formula declaration → formula proof (unchanged); a cask declaration
(any source) → cask proof; otherwise existing refusals. codex's npm copy stays npm. Proof:
manager resolution (login PATH) → `brew --prefix` AND `brew --caskroom` (two roots; never derive
Caskroom from prefix by string-trimming; `HOMEBREW_CASKROOM` may differ) → component decomposition
`<caskroom>/<token>/<version-dir>/<rel…>` (version dir OPAQUE — never the formula version grammar;
no empty/`.`/`..`; ≥3 components below caskroom) → `brew info --json=v2 --cask <declared names>`
(cap 4; match declared == `full_token`, or declared == `token` while `full_token == token`; tap
declaration must equal `full_token`; `installed` null → `.packageNotInstalled`; non-string
`installed` → `.invalidManagerOutput` only; `installed` string must equal the version-dir
component) → `brew list --verbose --cask <full_token>` membership (binary/command_wrapper:
selected canonical target equals a listed staged file; moved app: the listed staged symlink's
resolved target, selected path equal or strict descendant via `FileIdentityObserver.
isStrictDescendant`; `.metadata/**` lines never prove membership; malformed listing stays invalid
even after a match; cap 4096 lines/1 MiB) → revalidate selection/manager/caskroom/token-dir around
every query and before `.verified`. **No receipt parser** (Grok boundedness wins over MiniMax's
required receipt step: `info.installed` is already the manager's install record; receipt presence
in the listing is corroborating, `source.version` parsing is not required and is deferred).
Rename: a declaration matching only `old_tokens` (not `token`/`full_token`) → fail-closed
`.caskTokenRenamed` (Grok); the manager resolving an old name to the canonical token is a
disclosed fact, never a silent retarget of the declaration (MiniMax's verify-canonical-and-disclose
is overruled for declarations). New additive `InstallationOwnershipReason` cask cases (synthesize
Grok §C + MiniMax §C.3; reuse existing manager-failure/changed/cancelled cases; existing messages
byte-identical). `VerifiedInstallation`: manager `.homebrewCask`, packageName `full_token`,
managerRoot `--prefix`, installationRoot `<caskroom>/<token>`. Ownership never depends on version
comparability, update availability, auto_updates, pins, or deprecated/disabled. **Review: BOTH.**

**R2 — Cask latest-check: the manager's verdict is the oracle; no invented cask comparator.**
MiniMax F-6 wins on grammar (probe fact 9: brew itself lists the comma cask as outdated); Grok's
homebrewStable-for-casks and comma→unsupportedVersion are overruled. **auto_updates provenance
(judge ruling):** null/absent = NOT DECLARED in the cask source → proceed with comparison
(Homebrew's own falsy semantics; iterm2-uninstalled-true proves API fidelity); true →
unknown(`.caskAutoUpdates`) and Update refused; the agy matrix `auto_updates: true` claim is stale
(corrected in F). Grok's fail-closed null→unknown is over-conservative given the proof. Tri-state
(cask): disabled true → unknown(`.caskDisabled`); version string `latest` →
unknown(`.caskTracksLatest`); auto_updates true → unknown(`.caskAutoUpdates`); pinned + manager
reports newer → **updateAvailable + pin flag** (R9; MiniMax's `.caskPinned` unknown overruled —
D-007: a real newer version was observed); manager outdated verdict true (info `outdated` or token
in the plain outdated list, cross-checked) → updateAvailable(installed → `version` verbatim);
`installed == version` (string equality on manager strings) and not outdated → upToDate;
installed ≠ version and not outdated → unknown(`.caskMetadataInconsistent`); installed newer than
metadata → unknown(`.newerThanKnownMetadata`); offline/failure → existing typed reasons. Identity
cross-checks retained (Grok): cask outdated records key on the BARE TOKEN (formula records key on
full_name — never mix); record uniqueness; `current_version == info.version`; `installed_versions`
agreement; alias/duplicate poisoning → identityUnverified. Plain absence is NOT currency for
auto_updates/:latest/disabled. No `--greedy` (hidden widening). Batch ≤5 commands under the
existing admission gate AFTER the formula batch: `--prefix`, `--caskroom`,
`info --json=v2 --cask <deduped tokens>` (cap 16; excess `.budgetExhausted`),
`outdated --json=v2 --cask` (plain), `list --verbose --cask <tokens whose installed is a string>`
(membership; combined-list failure → all cask subjects unknown(.probeFailed)). Eligibility:
installed, consistent selection, local version, declares a cask, not in the formula batch;
standalone-with-cask leaves the `.noRegistry` path; standalone-without-cask stays `.noRegistry`.
New `UnknownReason` cases additive; existing arms byte-identical; exhaustive switches
(`UpdateScanRenderer.explanation`, `ToolDetailView.plainLanguageReason`, npm `map`) gain arms in
the same phase (npm mapper sends cask reasons to existing npm reasons; cask reasons never route
through npm ownership mappers). **Review: BOTH.**

**R3 — Cask cache: separate document.** `cask-update-metadata-v1.json`, sibling of the formula
(schema 3) and npm documents; schema 1, TTL 21600, cap 1 MiB both directions; keys registryID,
manager entry/target/fingerprint, prefix, caskroom, token, full_token, tap, installedVersion,
selected entry/target, context digest (length-prefixed framing, domain label
`agent-lens-cask-update-context-v1`); only successful verified comparisons persisted; unknown
never cached; restore fails closed on structural incoherence (token/full_token/tap agree; selected
target decomposes under recorded caskroom/token/installed); ecosystem isolation test (cask never
satisfies formula/npm lookup and vice versa); operations never read this cache. Formula/npm caches
untouched. (Both agree.)

**R4 — Vocabulary: four per-kind×operation cases, additive schema 2.** `homebrewFormulaUpdate`,
`homebrewFormulaUninstall`, `homebrewCaskUpdate`, `homebrewCaskUninstall` (both agree; a combined
`homebrewUpdate` would silently widen a formula grant to a cask — D-021 prevents). Absent → `[]`;
null/non-array/non-string/unknown/duplicate → named errors on BOTH decode paths (shared validator
`DetectorMetadataValidation.acceptedOperations`); schema stays 2; schema 1/3 + unknown keys still
rejected. Validator message becomes the six-name list; the two pinned-message tests
(`DetectorRegistryTests.swift:399-404`, `DetectorMetadataTests.swift:337-341`) updated, not
weakened. D-021 guard position unchanged (cancellation → accepted-operation containment → before
any observation/scratch/process). `OperationExecutionGate.shared` is the SAME process-wide gate
(npm and brew never overlap). AppSupport/App read Core `.message`, never retype. **Review: BOTH.**

**R5 — Operation lifecycle + literal argv.** Copy the M10 lifecycle exactly (prepare: fresh
ownership + fresh info, no cache read/write; preview bound to observed facts; one mode-0700 owned
scratch via existing `NpmScratchRoot.claim`/`releaseOperationRoot` — not renamed; cancel releases
only that root, no process; execute: gate acquire → claim-once → environment fingerprint → root
live → budget/cancel → fresh scan → selection match → fresh full observation → bound-fact match →
root live → proof revalidate → budget/cancel → ONE literal argv → bounded dual-stream 1 MiB/stream
→ mandatory reconciliation; exit 0 alone never success; pre-launch mismatch `.failed`
processStarted false; post-launch cancellation `.interrupted`/`.uncertain` with reconciliation; no
retry). Argv: formula update `["upgrade","--formula","--yes",<full_name>]`; formula uninstall
`["uninstall","--formula",<full_name>]`; cask update `["upgrade","--cask","--yes",<full_token>]`;
cask uninstall `["uninstall","--cask",<full_token>]`. `--yes` verified (ask mode default; visible
in the preview; uninstall has no `--yes`). Names are manager-returned proof identities, never
composed; empty/`-`-prefixed refused. Forbidden by construction + asserted: `--force`, `--zap`,
`--ignore-dependencies`, `--greedy*`, `--all`, `--dry-run`, `--overwrite`, `--build-from-source`,
`--installed`, a second target, a missing name, and the verbs update/pin/unpin/cleanup/autoremove/
install/reinstall/migrate/link/unlink/tap/untap. Target-version semantics (MiniMax F-8): brew has
no version-selection flag and re-resolves at execution; the preview shows the observed
latest-known target AND states re-resolution; confirm invalidates when the observed target changed
("Homebrew's known version for this package changed; a new preview is required."); reconciliation
compares installed to the observed target, mismatch → uncertain. **Review: BOTH.**

**R6 — Operation environment + no-controlling-TTY spawn.** From `diagnosticEnvironment`
(NO_AUTO_UPDATE=1, NO_ANALYTICS=1). Mutation adds NO_INSTALL_CLEANUP=1 and NO_AUTOREMOVE=1
(upgrade AND uninstall); NO_INSTALLED_DEPENDENTS_CHECK=1 on **upgrade only** (Grok precision:
uninstall keeps brew's default dependent refusal — the honest failure we surface; MiniMax's
all-operations setting overruled for uninstall). Unset if present: HOMEBREW_UPGRADE_GREEDY,
HOMEBREW_UPGRADE_GREEDY_CASKS, HOMEBREW_NO_UPGRADE_QUIT_CASKS (the "may quit" disclosure must stay
true), HOMEBREW_CASK_OPTS (Grok revision: saved appdir retention; user env cannot redirect),
HOMEBREW_AUTOREMOVE. **No HOMEBREW_NO_ASK** (the visible `--yes` argv is the suppression; MiniMax's
env-only approach is less transparent). **No HOMEBREW_CACHE/LOGS/TEMP redirect in production**
(Grok wins over MiniMax's scratch redirect: brew uses its own defaults exactly as the user's own
brew would; the effect text discloses manager cache/log/temp writes; Agent Lens never deletes them
— D-008. The M10 npm private-cache precedent is distinguished: npm's cache/config could be
polluted by registry pins; brew's download cache is manager-owned and reused. Redirecting would
force per-operation API re-downloads.). The FIXTURE redirects cache/logs/temp inside its root
(disposable environment teardown, not product cache deletion). **Spawn contract (judge finding):**
mutation processes must have NO controlling TTY (new session, `POSIX_SPAWN_SETSID`) so no
interactive prompt can block — `BoundedProcessRunner` currently sets SETPGROUP only (verified),
and the probe proved sudo prompts on /dev/tty despite stdin redirect. This is a NAMED contract
change to the shared runner: BOTH reviewers adjudicate it and the npm acceptance scenarios rerun
to prove no regression (OD-M13-7). If both BLOCK it, the fallback is R7 pre-refusal + `--yes` +
the documented GUI-no-TTY limitation, escalated to the owner. One environment builder
(`HomebrewOperationEnvironment`), exact keys/values asserted by tests, each switch named in the
effect text. **Review: BOTH.**

**R7 — Cask operation support class (JUDGE FINDING — corrects BOTH proposals).** Probe fact 8 +
`abstract_uninstall.rb:670-683`: `uninstall delete:` runs `sudo: true` unconditionally; pkgutil/
kext/rmdir elevate; quit/trash use AppleScript/Automation. Agent Lens never elevates, never enters
a password, never triggers a TCC prompt. Therefore M13 cask Update/Uninstall are supported ONLY
for casks whose fresh `info` `artifacts` show **no uninstall stanza** and only `binary`/
`command_wrapper` artifacts (CLI casks). App-artifact casks and any stanza-bearing cask → typed
refusal (`.caskOperationUnsupported` / `.caskUninstallRequiresElevation`) with a truthful
disclosure, **no process launched**; classification revalidated at execute. codex/claude-code/
kiro-cli (binary, no stanza) and agy (command_wrapper, no stanza) qualify mechanically. Ownership
(R1) still proves app-bundle casks diagnostically (membership via staged symlink + strict
descendant, probe fact 7) — **ownership ≠ mutation eligibility** (D-021 spirit). Fixture
corrections: MiniMax's `m13-cask-app` "carries an uninstall stanza" + AC08 "stanza effect observed"
and Grok's `m13zap` "stanza sentinel gone" are WRONG — a stanza-bearing cask demonstrates REFUSAL
(sentinel intact, cask still installed, zero process or an honest non-interactive failure); the
SUCCESS-path app cask has NO stanza and a scratch appdir (probe fact 7: clean app removal).
zap is never run; zap-listed files survive (asserted). This ruling is a named correction to both
proposals and a product support boundary (OD-M13-8). **Review: BOTH.**

**R8 — Whole-cask disclosure + multi-keg reconciliation truth.** Cask uninstall preview shows,
from the manager's own `artifacts` (never invented): full identity (token/full_token/tap), artifact
targets, the companion-app consequence ("Cask removal may remove a companion app, not only the
selected CLI"), the zap exclusion ("the zap step, which removes configuration and caches, is not
used"), literal argv, manager prefix; for supported no-stanza casks the disclosure states
artifact-only removal. Reconciliation: formula Update `.succeeded` only when exit 0 + fresh
ownership same full_name + selected keg version == observed target + previous keg not the selected
target + observation ok; formula Uninstall `.succeeded` only when exit 0 + the RECORDED keg absent
+ selected target released + observation ok. **Multi-keg truth (probe fact 1):** uninstall removes
the linked keg only; older kegs remain installed-but-unlinked and the bin symlink is not relinked.
The preview discloses ALL installed kegs; the result reports remaining kegs as disclosed residue
(never "completely removed"); a remaining keg is brew's default, not a failure; "formula still
installed via a remaining keg" is disclosed honestly. Cask Update `.succeeded` only when exit 0 +
fresh `installed` == observed target + membership confirms the post-rescan selection; cask
Uninstall `.succeeded` only when exit 0 + `installed` null/token absent + staged token dir absent +
recorded app target absent (if any) + observation ok; zap paths NOT required absent (expected
present). Dependent refusal = honest `.failed`, package still installed, stderr surfaced, no
`--ignore-dependencies`, no retry. Observation failure never success. Sentinels are fixture
assertions, not Core success-struct fields. (Synthesis; MiniMax §D.7 + Grok §D + probe fact 1.)

**R9 — Pins, deprecated, disabled, version refusals.** Pinned formula OR cask: `info.pinned` true
cross-checked against the unscoped `brew list --pinned` (matches formula rack basename or cask
token — Grok revision); disagreement → `.identityUnverified` (fail-closed, no launch); agreement →
refuse Update AND Uninstall before launch (`.pinned`); never `brew unpin`/`pin`. A pin appearing
between prepare and execute fails revalidation, launches nothing. Pinned + comparable newer →
latest-check `updateAvailable` + pin flag visible, button refused, count includes it (OD-M13-2;
D-007: the newer version is real). deprecated true + disabled false → Update permitted, disclosed
(date/reason); disabled true → refuse (`.formulaDisabled`/`.caskDisabled`, surface `disable_reason`
≤200 chars; brew itself refuses disabled casks). Cask Update refused for auto_updates true
(`.caskAutoUpdates`) and version `latest` (`.caskTracksLatest`); auto_updates null → proceed (R2);
comma versions → NOT refused (manager resolves; R2 oracle; Grok's unsupportedVersion-for-casks
overruled). Formula Update keeps the homebrewStable grammar (unsupported → refuse). Uninstall is
NOT refused for deprecated/disabled/:latest/comma/auto_updates (removal stays valid); it refuses
only on ownership failure, non-acceptance, pin/disagreement, support class (R7), or manager
failure. Dependent-formula uninstall: no `brew uses`/`deps` preflight; execute and surface the
honest refusal. (Synthesis.)

**R10 — Promotion set + capability matrix (OD-M13-1).** Matrix rule extension (both agree):
mutation `yes` cells gain the exact strings `yes: homebrewFormula (verified Homebrew formula copies
only)` and `yes: homebrewCask (verified Homebrew cask copies only)`, requiring the matching
accepted operation AND a declared candidate of the matching kind; non-promoted rows keep
`informational:`/`disabled:`. latest-check gains `yes: homebrewCask` for cask-declaring rows
(codex/claude included — Grok revision; shipped probe ≠ mutation acceptance), replacing the
blanket prohibition at `CapabilityMatrixTests.swift:230-232`. Cross-row note keeps "cask copies
classify standalone" and adds that a VERIFIED cask copy is Homebrew-owned (heuristic ≠ ownership;
MiniMax OD-M13-5 ruled YES — `classifySource` unchanged). The **agy row is corrected** with dated
evidence (auto_updates not declared upstream since 2026-11-13; command_wrapper +
AGY_CLI_DISABLE_AUTO_UPDATE); `docs/catalogue-identities.md` gets an appended dated correction
note, not a rewrite (frozen-packet discipline). Seeded-corruption tests must fail the same
agreement function; the frozen 14-id catalogue assertion holds. **Promotion recommendation (judge
synthesis):** Tier 1 = `hermes`/`aider`/`goose` formula Update+Uninstall + `kiro-cli` cask
Update+Uninstall. `agy` cask DEFERRED (command_wrapper ownership shape not probe-proven; comma
update path needs its own scenario; owner may add). Defer codex cask (npm twin channel), claude
casks (two conflicting candidates), opencode (stem ambiguity F-13), omp (tap presence). Never
gemini/cline (deprecated/disabled). Owner options: (a) formulae only [Grok], (b) formulae +
kiro-cli [RECOMMENDED], (c) formulae + kiro-cli + agy [MiniMax], (d) empty. Each promoted entry
needs its OWN controlled scenario (D-021). Zero promotions is legitimate: F still ships the rule +
agy correction; the native journey demonstrates the capability via fixture-registry acceptance.
OD-M13-1 gates the promotion application only. **Review: BOTH.**

**R11 — App/CLI integration.** New `HomebrewUpdateOperationView`/`HomebrewUninstallOperationView`;
npm sheets + public initializers BYTE-IDENTICAL (M10-D fixture host compiles/constructs them).
Brew sheets follow C-1 exactly (preview: no `.defaultAction`, Cancel `.cancelAction`/Escape,
destructive confirm no key equivalent; result/unavailable Done/Close default).
`ManagementPresentation` gains brew affordances gated on updateAvailable + verified Homebrew
manager + matching accepted operation; npm predicates/sentences byte-identical; the fixed
formula/cask "not available in this version" sentences are replaced by truthful per-entry
Core-reason text (not promoted → why); `needsVerification` brew strings ("Verify Installation to
enable Uninstall for this Homebrew formula/cask."); `standaloneLimit` not shown when cask ownership
is verified (Grok). ViewModel: brew preparations in the SAME update/uninstall slots via an enum
(.npm/.formula/.cask); the M12 R1 invalidation trigger set releases a pending brew preparation on
every trigger; the executing-mutation early-return preserved; one busy slot + shared gate; window
close cancels-and-joins an executing operation (reconciliation still runs). ToolDetailView Manage
section renders the brew block; version-cell label manager-aware. MainWindow brew sheets bind to
preview/preparation/outcome/unavailable, NEVER selectedEntry. **CLI: `main.swift` dispatch
BYTE-IDENTICAL** (D-022; Grok wins over MiniMax's main.swift allow-list — cask surfaces arrive via
verifier/renderer/coordinator; a needed call-site change is a stop-and-ask). a11y labels/hints per
M12-E/R10; cask uninstall hint names the companion-app consequence. **Review: BOTH.**

**R12 — Floors, CI, protected set.** Core GROWS in M13 (new adapters/operations/tests); floors are
minima and move ONLY at the combined gate, ONLY upward, ONLY to orchestrator-measured counts at
the frozen SHA, in a separate orchestrator commit; anchors frozen; the implementer never edits
`ci.yml`. Per-phase protected set: `Package.swift`, `Resources/**`, `scripts/**`, `.github/**`,
`Sources/agent-lens/**`, npm operation files' control flow + effect texts + public vocabulary,
`NpmOwnershipProbe`, formula batch command list + `HomebrewStatusResolver` + formula/npm caches,
`Tests/Fixtures/M10C/**`, `Tests/Fixtures/M10D/**`, `Tests/Packaging/**`, `DECISIONS.md`,
`ROADMAP.md`, `AGENT_LENS_SCOPE.md`, historical `briefs/**`/`walkthroughs/**` (except the phase's
own new worker report). Local gate set = M12-plan §5 commands; Core ≥467, AppSupport ≥119 each
phase; zero skips/failures; guard 21; packaging 9. (Both agree.)

**R13 — Acceptance environment (PROVEN; unblocked).** The scratch-prefix route is proven by the
judge's six probe rounds (above): clone --no-hardlinks at pinned revision; vendored ruby copy;
stub core tap; `brew trust`; offline file:// local tap; fixture-only cache/logs/temp redirect;
--appdir scratch for app casks; sentinels. The harness `Tests/Fixtures/M13/homebrew_acceptance.py`
(stdlib only, operator `--root` must not pre-exist and is never a cleanup target, seatbelt denies
personal-home writes + network, M10C shape) formalizes: synthetic formulae (old→new, sentinel,
lib/consumer dependent, pinned, broken) and casks (binary success; app NO-stanza success with
scratch appdir; app/stanza REFUSAL; delete-stanza REFUSAL with sentinels intact; auto_updates;
:latest; comma). file:// tarballs are the primary payload route (probe-proven; MiniMax's loopback
server is optional, not required). Scenarios M13-AC01…AC16 (MiniMax §G.6) CORRECTED per R7/R8:
stanza-bearing casks demonstrate refusal, not stanza execution; multi-keg residue disclosed;
per-promotion scenario each. Native journey via Accessibility (M10-D method) against the scratch
prefix with fixture-registry acceptance; CLI parity; interruption + concurrent-confirm; personal
prefix/Cellar/Caskroom//Applications/caches byte-identical manifests. The environment phase is
UNBLOCKED (probe complete); a harness failure at implementation is a stop, never a personal-prefix
workaround. **Review: orchestrator acceptance + one council read-only honesty note.**

**R14 — Review matrix (risk-matched, ROADMAP §5.4).** A, B, D, E, F, G: mandatory independent
review by BOTH council models (ownership/mutation/truthfulness/promotion/confirmation safety).
C: orchestrator acceptance + one council read-only note. H: orchestrator-run; both read evidence
read-only, never re-run destructive scenarios against personal installs. Changed safety behavior
re-reviewed; two-correction-round boundary enforced (unresolved substantive acceptance → owner).

**R15 — Timeouts/budgets (OD-M13-3).** Per-query 10s; prepare 60s; confirm 60s; stage 60s
(unchanged). Brew mutation timeout: **recommend 900s** (MiniMax; real bottle/DMG downloads and
source builds legitimately exceed 120s; a 120s bound would convert ordinary downloads into false
"interrupted"); npm stays 120s (accepted, untouched); disclosed in the preview; interruption
semantics M10 (process-group TERM/KILL, uncertain, reconciliation). Owner confirms before D
dispatch; the freeze carries the recommendation. Grok's 120s-parity is overruled pending owner.

**R16 — Local suite invocation.** Carried from M12 R16: `swift test --no-parallel` (CI-matching)
under `env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS`, fresh scratch, with the
invocation-local TestingMacros plugin flag (`-Xswiftc -load-plugin-library -Xswiftc
/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib`,
`--build-system swiftbuild`) on this CLT-only workstation. No xcode-select/toolchain/package
change. Hosted CI (full Xcode) needs no flag. Serial execution authoritative; load-sensitive
parallel failures discarded.

## Owner decisions

| ID | Decision | Recommendation |
|---|---|---|
| OD-M13-1 | Promotion set (R10) | **(b) hermes/aider/goose formula Update+Uninstall + kiro-cli cask Update+Uninstall**; options (a) formulae only, (c) +agy, (d) empty. Each promoted id needs its own scenario. Gates F's promotion application only |
| OD-M13-3 | Brew mutation timeout 900s vs 120s (R15) | **900s** for brew, disclosed; npm stays 120s. Confirm before D dispatch |
| OD-M13-4 | Ship cask latest-check (revises D-019's "cask not shipped" consequence + the matrix prohibition) | **YES** — ROADMAP M13 requires cask check; record a new DECISIONS entry (D-024) at acceptance superseding the consequence, not D-019 itself |
| OD-M13-8 | Cask operation support class = no-uninstall-stanza CLI casks only (R7) | **YES** — truthful support boundary; app/stanza casks informational with a typed reason; widening is a later owner decision |

Ruled technical decisions (owner may override explicitly before dispatch): OD-M13-2 pinned
updates count in the badge (YES, R9); OD-M13-5 keep `Source: standalone` heuristic + explain
(YES, R10); OD-M13-6 `brew list --pinned` bounded cross-check (YES, R9); OD-M13-7 no-controlling-TTY
SETSID spawn contract (YES with npm regression + BOTH adjudication, R6; fallback pre-refusal-only
if BLOCKed). MiniMax's OD-M13-2 (agy correction) is ruled YES in R10 (a factual correction, not a
product choice). The optional diagnostic beta, publication, expenses, and public contribution
invitations remain separate post-M13 owner decisions (ROADMAP §7); no release is authorized.

## Owner decisions settled (2026-11-21, post-freeze)

The owner agreed to all four recommendations ("I agree with your 4 recommendations"): OD-M13-1
option (b) (hermes/aider/goose formula Update+Uninstall + kiro-cli cask Update+Uninstall);
OD-M13-3 900s brew mutation timeout; OD-M13-4 ship the cask latest-check; OD-M13-8 no-uninstall-
stanza CLI casks only. The ruled technical decisions (OD-M13-2/5/6/7) stand. Recorded in
DECISIONS.md. The owner authorized pushing the branch and syncing GitHub with local;
implementation is NOT authorized ("don't start implem. yet"); no implementer selected. This note
is appended after the freeze; rulings R1–R16 and the frozen contract text are unchanged.

## Repo integrity audit (before freeze) — CLEAN

Audited 2026-11-21 before the freeze commit. `git rev-parse HEAD` = `9b37a33`; branch
`milestone/m13-homebrew`. Tracked-file SHA-256 manifest (`git ls-files -z | xargs -0 shasum -a 256`)
is **byte-identical** to the pre-wave capture (`tracked-pre.sha` vs `tracked-post.sha`, empty diff,
496 files). `git status --porcelain` shows ONLY the new untracked planning files:
`briefs/M13-plan.md`, `briefs/M13-planning/{council-brief,proposal-minimax,proposal-grok,judgment}.md`.
`council-brief.md` hash unchanged from pre-wave (`fff8005f…`). No product file, no existing
brief/walkthrough/doc changed; no git state mutation by either council member. Grok's
session-scoped always-approve grant was bounded by the brief to one writable file; the audit
confirms it. Manifests retained at `~/.hermes/cache/scratch/agent-lens-m13-planning/`.

## Freeze decision

The judge freezes `briefs/M13-plan.md` on base `9b37a33` after the integrity audit is clean.
**Authorization scope (owner message 2026-11-21): M13 PLANNING + freeze/commit on the milestone
branch ONLY. Implementation is NOT authorized; no implementer is selected** (recorded as "not
selected — implementation not authorized"). Push, publication, per-tool promotions (OD-M13-1),
and any release remain separate owner decisions. Standing independent reviewers for future
implementation: the two council models, summoned through Herdr/hc only. Rulings R1–R16 bind the
dispatch briefs; each brief quotes them verbatim.