# M13-B implementation — worker evidence, not acceptance

**Status:** correction round 1 completed. Candidate bytes are left unstaged for orchestrator and
both reviewers. No Git writes (add/commit/stash/checkpoint/push), no delegation, no personal
installation writes, no dependency or toolchain change, no M13-C work.

- Base: `440c30b6832bcc2e9d64df5ce2814c696d397ea0` (`milestone/m13-homebrew`)
- Worker: River DeepSeek V4.1 Flash 1017 in Pi, thinking max
- Correction brief: `M13-B-R1-corrections.md`
  (`c29aabb618fff173993aacd7de9a0b1ea29df159dd439bfea2dd5b9612d4d5b1`)
- Initial evidence root: `/var/folders/tf/jsdyxcts6y72fs98s7wl3dfm0000gn/T/agent-lens-m13-b-2xun7a8x/worker`
- Correction evidence root: `/var/folders/tf/jsdyxcts6y72fs98s7wl3dfm0000gn/T/agent-lens-m13-b-2xun7a8x/worker-r1`
- Worktree: shared milestone checkout. `git status --porcelain` contains only the exact candidate
  paths below; `worker-r1/scope-check.diff` is empty. Nothing is staged; HEAD is still the base.

## Correction round 1

Seven product corrections from the orchestrator review were applied to the already-reviewed
candidate:

1. **Live root binding.** The reported prefix and Caskroom are bound to `DirectoryIdentity`
   (reported spelling + canonical path + device/inode). A missing/unbound prefix is a typed
   unknown. Listing lines accept only the exact reported or canonical root spelling, normalize
   that root alias by path components, and leave final links (including staged `.app` links)
   intact. `.metadata`, traversal, siblings and exact token/version component checks follow the
   accepted M13-A principles.
2. **Snapshot + per-call revalidation.** Each cask subject's complete selected-executable identity
   and the manager executable identity are snapshotted before stage admission. The batch
   revalidates the manager, every selection, the bound roots and every known token/version
   directory before AND after each manager call; a same-path replacement or root retarget stops
   the batch before the next launch. The coordinator rechecks at publish and again immediately
   before save. Formula/npm paths and revalidation are byte-preserved.
3. **Manager verdict only.** The formula comparator is no longer used by cask status or cask-cache
   validation. Agreeing manager records with unequal opaque strings attest an update, even where
   formula ordering would veto it. Equal + absent verdict is `upToDate`; unequal + absent verdict is
   `.caskMetadataInconsistent`. No cask path produces a directional `newerThanKnownMetadata`.
4. **Moved app.** A freshly verified external app is accepted only through the narrow M13-A proof:
   a listed staged symlink whose name and resolved target are `.app` directories and whose bundle
   contains the selection by path components. Broad, unrelated, redirected, non-app and
   `.metadata` links are refused. R3 still permits only exact staged-target decomposition in the
   on-disk cache, so a freshly verified external app is published but never written or restored.
5. **Duplicate bare identity.** The bare token must occur exactly once in the whole info response;
   two different tapped full_tokens sharing one bare token are ambiguity. Outdated records stay
   keyed on the bare token. The combined listing addresses a tapped cask by its verified full
   identity; basic core casks keep their exact bare-token argv. Contradicting aliases/foreign
   claims fail closed, and unrelated manager-wide outdated rows are never stripped.
6. **Cache identity.** Restore requires the current declaration set, manager, observed selected
   executable fingerprint, reported + canonical prefix/Caskroom identities, exact token/version
   directory identities, TTL and stage time left. A changed declaration, a replaced selected file
   at the same path, or a retargeted root alias is a miss and a fresh probe. A fully valid staged
   hit still launches zero manager queries. Saved external app targets remain forbidden.
7. **Oversized save is an unmodified document.** The complete merged document is measured before
   any write; a set that cannot fit returns failure and leaves the previous bytes (including a
   prior record with the same key) untouched. Atomic publication, 1 MiB cap, fixed TTL, unknown
   never persisted and sibling isolation are retained.
8. **Adjudication items.** Whole-subject declaration sets are admitted or excluded together, so a
   rejected subject leaves no orphan name in the info request. The inaccurate splitting comment is
   corrected, and the unused `runBatch` wrapper was removed. The CLI/report keeps the local CLI
   version and the manager installed directory as distinct facts: only Homebrew-verified membership
   and manager values decide the cask verdict; provenance shows the manager installed version and
   pin. The six legacy CLI fixture assertions now pin the exact three formula argv plus the refused
   cask `--prefix` instead of a broad count.

## Changed exact paths

Production (allow-list):

- `Sources/AgentLensCore/Updates/HomebrewCaskUpdateProbe.swift` (new)
- `Sources/AgentLensCore/Updates/CaskUpdateMetadataCache.swift` (new)
- `Sources/AgentLensCore/Updates/UpdateProbeCoordinator.swift` (cask stage after the formula
  batch, eligibility change, additive cask/pin fields on `ToolUpdateResult`)
- `Sources/AgentLensCore/Updates/VersionStatus.swift` (four additive `UnknownReason` cases)
- `Sources/AgentLensCore/Updates/UpdateScanRenderer.swift` (four new reason arms + cask
  provenance line; every existing formula/npm arm is byte-identical)
- `Sources/AgentLensApp/ToolDetailView.swift` (`plainLanguageReason` four new arms only)
- `Sources/AgentLensCore/Operations/NpmUpdateOperation.swift` (`map(_:UnknownReason)` four new
  arms only; existing arms byte-identical)

Tests / docs (allow-list):

- `Tests/AgentLensCoreTests/HomebrewCaskUpdateProbeTests.swift` (new; live bindings, alias,
  moved app, duplicate bare token, comparator-free verdicts, replacement/retarget)
- `Tests/AgentLensCoreTests/CaskUpdateMetadataCacheTests.swift` (new; live restore identity,
  comparator-free coherence, oversized same-key replacement)
- `Tests/AgentLensCoreTests/UpdateProbeCoordinatorTests.swift` (cask coordinator cases appended,
  including moved-app non-persistence, same-path/manager replacement, stale declaration and
  whole-set cap admission)
- `Tests/AgentLensCoreTests/UpdateCLIIntegrationTests.swift` (two cask CLI cases; all six existing
  formula-scenario assertions tightened to exact argv boundaries)
- `Tests/AgentLensCoreTests/CapabilityMatrixTests.swift` (latest-check rule now permits/requires
  `yes: homebrewCask` only for a declared cask; mutation cells untouched; seeded false-cask case)
- `docs/capability-matrix.md` (latest-check cells for declared casks; mutation cells and the agy
  note untouched)
- `walkthroughs/M13-B-implementation.md` (this worker report)

`CONTRIBUTING.md` is protected and unchanged pending separate owner approval.

## What the candidate does

**Eligibility (R2).** A `standalone` subject that declares at least one `homebrewCask` leaves the
`.noRegistry` path and joins a cask batch. A `standalone` subject without a cask declaration stays
`.noRegistry`. `brew` subjects stay in the formula batch and `npm` subjects stay in the npm stage.
Local-only and offline modes return before admission and execute zero cask commands/cache access.
The selected executable identity is observed before admission; a selection that cannot be observed
is `.identityUnverified` without a manager launch.

**Batch (R2).** A declared cask name may be bare or fully qualified (`owner/tap/token`); `info`
uses the declaration, while outdated records and cache identity use the manager's bare token. No
eligible cask means zero commands. Otherwise the exact ordered ceiling is five: `--prefix`,
`--caskroom`, `info --json=v2 --cask <whole admitted declaration set>`, `outdated --json=v2 --cask`
(no `--greedy`), and one combined `list --verbose --cask <installed identities>` (verified full
identity for tapped casks, bare token for basic core casks). The deduplicated declared-name cap is
16; a subject is admitted only with its entire new declaration set and otherwise reports
`.budgetExhausted` without contributing an orphan name. The stage runs after the formula batch and
before npm inside the same complete-stage admission and 60 s monotonic budget; the cask batch
reacquires the existing `HomebrewBatchAdmissionGate` and adds no process gate. Per-query bound is
still 10 s. A combined-list or listing-parse failure marks every subject in that cask batch
`.probeFailed`/the typed cause; no subject borrows another subject's partial listing.

**Live bindings (correction 1/2).** The batch binds the reported prefix and Caskroom to live
directory identity and re-observes every root and every derived token/version directory before and
after each manager call. A missing prefix, changed manager, same-path executable replacement,
retargeted root alias, retargeted token directory or invalid staged layout returns a typed
unknown and launches no further query. Membership is exact: the selected canonical target must be
a listed regular file under `<caskroom>/<token>/<installed>`, or (moved app) the selection must be
component-bounded inside a listed staged `.app` link to an actual `.app` directory. `.metadata`
never proves membership.

**Tri-state (R2, correction 3).** The manager's verdict is the oracle; cask strings (including
commas and `latest`) are opaque and never ordered. In order after identity/membership verification:

- `disabled == true` → `.caskDisabled`
- `version == "latest"` → `.caskTracksLatest`
- `auto_updates == true` → `.caskAutoUpdates`
- `auto_updates` null/absent → proceed (not declared)
- info `outdated` and the bare-token outdated record agree on identity/version/install/pin →
  `.updateAvailable(installed: local CLI text, latest: manager version verbatim)`
- `installed == version` on manager strings and not outdated → `.upToDate`
- unequal on manager strings and not outdated → `.caskMetadataInconsistent` (both directions; no
  numerical direction is invented)
- pinned + manager-reported newer stays `updateAvailable` with a visible pin flag.

A record that claims only an old token, is uninstalled, is duplicated, is invalid, disagrees with
the combined listing, or carries a foreign full-token outdated key is `.identityUnverified`.

**Cache (R3, corrections 6/7).** `cask-update-metadata-v1.json`, a sibling of the formula and npm
documents. Schema 1, TTL 21,600 s, 1 MiB cap in both directions, atomic write, exact timestamp text,
no precomputed status stored. Only successful comparisons are stored; unknown is never written; a
comparison completed at the aggregate deadline may be published but is never stored. The key is
registry ID, manager entry/target/fingerprint, reported + canonical prefix/Caskroom and their
device/inode, token, full token, tap, manager installed version, exact token/version directory
identities, selected entry/target/fingerprint, declaration-set digest, and the length-framed
context digest with domain label `agent-lens-cask-update-context-v1`. Restore fails closed on
structural incoherence, a non-current root/token/version or selected binding, an altered
declaration set, a replaced selected file at the same path, ambiguity, expiry, bad timestamps/size,
or corrupt/schema-mismatched input. An oversized save leaves the existing document byte-identical.
Saves merge unrelated valid identities and never read or replace the formula/npm documents.
Operations do not read this document. A fully valid staged hit launches zero manager queries; a
freshly verified external app is never written or restored, so it re-probes.

**Presentation.** `UpdateScanRenderer` adds a cask provenance line (`cask <full token> tap <tap>
installed <manager installed>; pinned|not pinned`, plus fresh/cache timestamp). Existing formula
and npm lines are unchanged. `ToolDetailView.plainLanguageReason` and the npm operation mapper gain
exhaustive-switch arms; cask reasons map to existing npm reasons and never through an npm
ownership mapper. The row's installed text remains the CLI local version so the existing
selected-update count semantics are unchanged; the manager installed directory is the visible,
separate provenance fact used by the verdict.

**Capability matrix.** The blanket "cask latest-check never yes" rule is replaced by the new rule:
a latest-check cell may list `yes: homebrewCask` only when the definition declares a cask, and a
declared cask now lists it beside npm/formula probes. Mutation cells are unchanged; the agy
`auto_updates` note correction remains out of scope (F).

## Required decisions / interpretations (no blocked scope)

- "outdated --json=v2 --cask (plain)" means **no `--greedy`**; the manager-wide cask list is parsed
  from the `casks` array and keyed on the bare token.
- No cask comparator or numerical direction is used. `.newerThanKnownMetadata` remains a formula
  reason only; cask unequal/not-outdated is `.caskMetadataInconsistent`.
- The local CLI version and the manager's installed version directory may legitimately differ.
  Only manager strings decide the verdict; both facts stay visible (row vs provenance).
- A moved app is a fresh comparison only; R3's staged-target cache rule forbids saving/restoring
  an external app target. This preserves R1's narrow app membership and fail-closed refusals.
- The info declaration cap admits whole subject declaration sets; a rejected subject leaves no
  token in the info request.
- The six existing CLI checks that count manager launches now assert exact argv boundaries: the
  three unchanged formula queries, then one refused cask `--prefix` per admitted run. The formula
  batch itself is unchanged.

## Evidence in `worker-r1/`

- `full-suite-r1.stdout`, `full-suite-r1.stderr` — final fresh R16 suite:
  **Core 597 tests, AppSupport 119 tests, zero failures, zero skips**. (`full-suite.*` is the
  same-count run before the last defensive cache selected-executable check.)
- `build.stdout/stderr`, `core-guard.*`, `appsupport-guard.*`, `guard-fixtures.*` (21 tests),
  `dev-app.*`, `packaging.*` (9 tests), `diff-check.*` — all exit 0.
- `focused-*.stdout/stderr` — focused cask/coordinator/cache regressions.
- `cli-r1.stdout`, `cli-r1.stderr`, `cli-r1/` — the four independent CLI cases re-run with the
  disposable closed-PATH fixtures:
  - reported alias → `up to date`, 5 manager calls
  - moved app → `update available`, 5 manager calls, count 1
  - manager verdict lower than installed → `update available`, 5 manager calls, count 1
  - nonexistent prefix → `unknown — selected package could not be verified`, 1 manager call
  The orchestrator's red receipts are retained in `cli-edge-r0/`.
- `changed-file-sha256.txt` (14 candidate paths), `rest-of-tree.sha256` (every one of the 495
  tracked non-candidate files), `protected-check.stdout/stderr` (`sha256sum -c
  protected-before.sha256` — all 495 protected paths unchanged), `scope-check.diff` (empty),
  `git-status.txt`, `git-diff-name-status.txt`, `tracked-candidate.diff` (tracked files),
  `candidate.diff` (tracked diff plus every new candidate file), `diffstat.txt`, `head.txt`.
- `verify-cask-check-edge-cases.py` and `personal-brew-readonly.sb` — the disposable CLI harness
  and its read-only sandbox profile. The harness denies the real home and `/opt/homebrew`; no
  personal installation was a mutation target.

## Open issues / risks

- `CONTRIBUTING.md` still contains the stale cask latest-check rule. It is protected and excluded
  from this candidate until separate owner approval; this does not block the product candidate.
- No other blocking issue. The review-sensitive areas remain (1) the live root/selected/proof
  binding and moved-app membership, and (2) the separate cask document's identity/restore/
  oversize behavior. Both are explicitly tested and left for independent review.
- This report is worker evidence, not acceptance. The orchestrator must rerun the acceptance gate
  set at the frozen SHA.
