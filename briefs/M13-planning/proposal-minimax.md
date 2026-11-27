# M13 — complete Homebrew management: council proposal

Council member: **MiniMax M3.1-Flash / xhigh (mcode)**. Written independently, 2026-11-21.
Authority: `briefs/M13-planning/council-brief.md`. Output file: this file only.

Nothing in this proposal was executed, built, launched, or mutated. Every code claim is a **static
read** of the working tree at `9b37a33` with a file:line citation. Every manager claim is a
**read-only `brew` invocation** with the exact command shown, all run with
`HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1`, plus a few reads of the vendored Homebrew
source under `/opt/homebrew/Library/Homebrew` (read-only). I did not read `proposal-grok.md`.

**Two facts I could not verify and therefore do not claim:** (1) I did not run the Swift test suite,
the build, or the app (read-only constraint) — the 467/119/586 floors below are read from
`.github/workflows/ci.yml`, not measured by me; (2) I did not run a *mutating* `brew` command
against any prefix, so every claim about what `brew upgrade`/`brew uninstall` actually does at
runtime is derived from the vendored Homebrew source plus its `--help` text, and is labelled as
such.

---

## 0. Summary for the judge

**Eight phases** (M13-A … M13-H) on the single milestone branch `milestone/m13-homebrew`, base
`9b37a33`. A–B are read-only Core, C is a test-only disposable environment, D–E are the two
mutation phases, F is promotion + matrix, G is AppSupport/App/CLI, H is the combined gate.

**The single most important technical conclusion of this audit:** *a cask-installed CLI is
invisible to the current ownership router.* `ToolDetector.classifySource`
(`Sources/AgentLensCore/Detection/ToolDetector.swift:187-191`) labels a copy `brew` only when the
resolved path contains `/Cellar/`; a cask binary resolves into `/opt/homebrew/Caskroom/...`, so it
labels **`standalone`**. `InstallationOwnershipVerifier.verify`
(`Sources/AgentLensCore/Ownership/InstallationOwnershipVerifier.swift:61-82`) switches on that
source string and returns `.unsupportedSource` for anything that is not `npm` or `brew`. So today
the cask path cannot even be *attempted* — the `.unsupportedCask` reason
(`InstallationOwnership.swift:70,110-111`) is effectively dead code for real cask copies.
M13-A must add a cask route that is entered by **declared cask candidate + manager evidence**, not
by the source heuristic, and it must prove ownership with the manager's own three queries plus
path-component decomposition of the Caskroom — the exact analogue of the formula proof, with the
Caskroom replacing the Cellar. Details in §C.

**Second conclusion:** *the manager-side side effects of a Homebrew mutation are wider than the
named package, and four of them have documented environment switches.* Verbatim from
`brew upgrade --help`: "Unless $HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK is set, brew upgrade or
brew reinstall will be run for outdated dependents" and "Unless $HOMEBREW_NO_INSTALL_CLEANUP is
set, brew cleanup will then be run for the upgraded formulae and casks or, every 30 days, for all
packages." And from `brew uninstall --help` + `cmd/uninstall.rb:168-171`, uninstall runs
`Cleanup.autoremove` unless `HOMEBREW_NO_AUTOREMOVE` is set. Without those three switches, one
"update one package" click can upgrade *dependents*, prune *other* packages' old versions, and
remove *now-unused dependencies*. M13-D/M13-E must set all of them, and disclose that it does.
This is the single most dangerous seam in the milestone and it is invisible in the CLI help.

**Third conclusion:** *the frozen M11 catalogue is already stale on one M13-critical fact.* The M11
matrix says the `agy` cask "sets `auto_updates: true`". Verified today: `brew info --json=v2 --cask
antigravity-cli` returns `auto_updates = null`, the signed API payload has `auto_updates: null`
for that token, and the current upstream cask source has **no** `auto_updates` stanza at all (it
uses `command_wrapper` + `AGY_CLI_DISABLE_AUTO_UPDATE`). The revision that *did* carry
`auto_updates true` is the 2026-11-12 upstream file. The cask changed upstream on 2026-11-13.
M13-F must correct the `agy` row rather than ship the stale claim, and M13-B's cask latest-check
must treat `auto_updates` as a **manager-reported fact with a per-invocation provenance**, never as
an assumption.

**Fourth conclusion (acceptance):** *a scratch Homebrew prefix is achievable without touching the
personal prefix, and the mechanism is already in the product.* `HomebrewManagerResolver.resolve`
(`Sources/AgentLensCore/Updates/HomebrewIdentity.swift:25-38`) takes the **first live `brew` on the
ordered login-shell PATH**. A scratch prefix reached through a scratch `bin/brew` therefore
re-targets the *entire* product — ownership, latest-check and mutations — with no product change
at all. `bin/brew:81` derives `HOMEBREW_PREFIX` from the brew file's own location, so a scratch
prefix is a matter of *where brew lives*, not of an env var. §G specifies the environment and
exactly what the feasibility probe must have demonstrated.

---

## A. Current-state audit

### A.1 Council-brief §3 claims, verified

| §3 claim | Verdict | Evidence |
|---|---|---|
| `HomebrewOwnershipProbe` — formula-only ownership, exactly three queries | **Verified** | `Sources/AgentLensCore/Ownership/HomebrewOwnershipProbe.swift:69` (`brew --cellar`), `:131` (`brew info --json=v2 --formula <declared-name>`), `:177` (`brew list --verbose --formula <record.fullName>`). Header `:3-7` states the three-query contract; `:5-6` states `--installed` is never used. |
| Cask declarations return `.unsupportedCask` | **Verified** | `HomebrewOwnershipProbe.swift:101-105` (`hasCask ? .unsupportedCask : .noDeclaredPackage`); message at `InstallationOwnership.swift:110-111` ("Homebrew cask ownership is not supported"). |
| `FormulaProof.revalidate()` re-observes selection/manager/cellar/keg | **Verified** | `HomebrewOwnershipProbe.swift:35-52`; call sites `:205` and the in-loop `revalidate(selection:manager:)` at `:62,81,124,140,170,186,206`. |
| Ownership never depends on semver support or update availability | **Verified** | `HomebrewOwnershipProbe.swift:7` (comment) and the code: the probe reads `installed` versions from the info record (`:163`) but never `versions.stable`. |
| `HomebrewManagerResolver.resolve` takes the first live `brew` in the ordered login-shell PATH | **Verified** | `Sources/AgentLensCore/Updates/HomebrewIdentity.swift:25-38`; `:32-33` requires a regular executable via `fstatat`+`access(X_OK)`. No `which`, no inherited PATH, no hardcoded prefix. |
| `HomebrewTargetParser.parse` decomposes by PATH COMPONENTS | **Verified** | `HomebrewIdentity.swift:79-102`; `:83` requires the cellar prefix, `:86-94` splits into ≥3 components and rejects `.`/`..`. |
| M6 batch = at most three commands | **Verified** | `Sources/AgentLensCore/Updates/HomebrewUpdateProbe.swift:490` (`--cellar`), `:519` (`info --json=v2 --formula <names>`), `:527` (`outdated --json=v2 --formula`); `:442-464` dedupes and rejects invalid names before any process; `:509` the selected-target mode. |
| `queryTimeout = 10` | **Verified** | `HomebrewUpdateProbe.swift:204`. |
| `diagnosticEnvironment` adds `HOMEBREW_NO_AUTO_UPDATE=1` and `HOMEBREW_NO_ANALYTICS=1` | **Verified** | `HomebrewUpdateProbe.swift:543-548`. |
| `parseOutdated` tolerates cask data but never consumes it | **Verified** | `HomebrewUpdateProbe.swift:259-261` (comment) and `:262-281` — the parser reads only `root["formulae"]` (`:285-301`). The `outdated --json=v2` envelope really does carry a separate `casks` array (verified below). |
| `HomebrewStatusResolver.status` — ordering with revision suffix, alias/identity poisoning, outdated cross-check, typed unknown reasons | **Verified** | `HomebrewUpdateProbe.swift:554-692`; identity checks `:602-620`, alias conflict `:615-620`, outdated cross-check `:643-682`, typed reasons `:561-591,608,619,637,652,664,672,680,690`. |
| `UpdateMetadataCache` — formula-only, schema 3, 6 h TTL, 1 MiB cap, full identity keys | **Verified** | `Sources/AgentLensCore/Updates/UpdateMetadataCache.swift:245` (schema 3), `:254` (ttl 21 600), `:256` (1 MiB), `:21-50` (key fields), `:153-167` (structural coherence on restore). |
| npm metadata lives in a SEPARATE document | **Verified** | `Sources/AgentLensCore/Updates/NpmUpdateMetadataCache.swift:296-304` writes the sibling `npm-update-metadata-v1.json`; the Homebrew document is `update-metadata-v1.json` (`Sources/agent-lens/main.swift:54-59`, `Sources/AgentLensApp/MainWindow.swift:52-61`). |
| `AcceptedOperation` closed vocabulary is exactly `npmUpdate`, `npmUninstall` | **Verified** | `Sources/AgentLensCore/Detection/DetectorMetadata.swift:78-81`. |
| Both decode paths reject with "must be one of npmUpdate, npmUninstall" | **Verified** | Codable path `Sources/AgentLensCore/Detection/DetectorRegistry.swift:215-240`; JSON path `:1076-1108`; shared validator `DetectorMetadata.swift:270-295` (message text at `:282`). Two tests pin that exact string: `Tests/AgentLensCoreTests/DetectorRegistryTests.swift:399-404`, `Tests/AgentLensCoreTests/DetectorMetadataTests.swift:337-341`. |
| `PackageManager` already has `homebrewFormula` / `homebrewCask` | **Verified** | `DetectorMetadata.swift:61-73` (labels "Homebrew formula" / "Homebrew cask"). |
| Declared formula/cask names accept bare or `user/repo/name` | **Verified** | `DetectorMetadata.swift:144-157` (one or three components, per-component pattern). |
| `OperationModels` — npm-shaped public vocabulary | **Verified** | `Sources/AgentLensCore/Operations/OperationModels.swift:20-22` (update effect text), `:26-51` (`NpmUpdatePreview`), `:284-286` (uninstall effect text), `:290-314` (`NpmUninstallPreview`), `:104-140` / `:349-383` (opaque preparations with claim/release-once), `:143-167` (`InstallationDelta`), `:387-428` (`NpmUninstallDelta`), `:250-258` (`OperationCommandRunner`), `:261-278` (`OperationExecutionGate.shared`). |
| D-021 guard is the second statement (after cancellation), before scratch/observation/process | **Verified** | `Sources/AgentLensCore/Operations/NpmUpdateOperation.swift:61-64` (cancel → `acceptedOperations.contains(.npmUpdate)` → `.operationNotAccepted`); uninstall `NpmUninstallOperation.swift:51-54`. |
| Registry: 14 entries, only `codex` carries `acceptedOperations` | **Verified** | `Sources/AgentLensCore/Detectors/DefaultDetectors.json` — 14 detectors; `codex` alone has `acceptedOperations: ["npmUpdate","npmUninstall"]`; every other entry has none. Formula-declared: `opencode` (5 candidates incl. two taps), `gemini` (`gemini-cli`), `cline` (`cline`), `hermes` (`hermes-agent`), `aider` (`aider`), `goose` (`block-goose-cli`), `omp` (`can1357/tap/omp`). Cask-declared: `codex` (`codex`), `claude` (`claude-code`, `claude-code@latest`), `kiro-cli` (`kiro-cli`), `agy` (`antigravity-cli`). |
| Source classification is a heuristic; cask copies classify `standalone` | **Verified** | `ToolDetector.swift:187-191`; `docs/capability-matrix.md:45-49` states it explicitly; `docs/catalogue-identities.md:563-570` binds it as a plan rule. |
| Capability-matrix rule is test-enforced | **Verified** | `docs/capability-matrix.md:18-21`; `Tests/AgentLensCoreTests/CapabilityMatrixTests.swift:176-205` (`mutationCellProblems`), `:207-234` (`latestCheckProblems`, and `:230-232` forbids `yes: homebrewCask`), `:143` (`exactMutationYes`). |
| Shipping CLI dispatches only `scan`, `verify-installation`, `debug-env` | **Verified** | `Sources/agent-lens/main.swift:61-63`, `:114-116`, `:160-163`; no other `case`. |
| `verify-installation` already runs the ownership verifier | **Verified** | `main.swift:141-151` calls `InstallationOwnershipVerifier.verify` and renders `InstallationOwnershipRenderer`. |
| App: `ManagementPresentation` is the single source of "control offered, and why not" | **Verified** | `Sources/AgentLensAppSupport/WorkflowPresentation.swift:153-238`; `:186-238` the whole decision; `:175-184` the fixed contract sentences; npm reason strings **read** from Core (`:196`, `:217`). |
| Sheets bind to preview/preparation/outcome/unavailable, never `selectedEntry` | **Verified** | `Sources/AgentLensApp/MainWindow.swift:102-126` (update sheet), `:127-150` (uninstall sheet); `Sources/AgentLensApp/ToolDetailView.swift:280-311`. |
| M12 R1 invalidation contract and C-1 footer contract are accepted | **Verified** | `InventoryViewModel.swift:649-711` (`invalidatePendingUpdate`, executing early-return `:655`); `Sources/AgentLensApp/UpdateOperationView.swift:72-80` (no `.defaultAction` in preview state, Cancel = `.cancelAction`); `UninstallOperationView.swift` mirrors it. |
| Baseline 467 Core + 119 AppSupport = 586; guard 21; packaging 9 | **Verified from CI config, not re-measured** | `.github/workflows/ci.yml:180-209` (`guard-fixtures` floor 21 `:182`; Core 467 / AppSupport 119 / total 586 `:194-198`; packaging 9 `:208`; anchors `:170-178`). |

### A.2 Findings the council brief did **not** list (verified, and they shape the plan)

**F-1 — A cask-installed CLI never reaches the Homebrew branch at all.**
`InstallationOwnershipVerifier.verify:61-82` switches on `diagnostic.detectedTool.source`:
`"npm"` → npm probe, `"brew"` → homebrew probe, **anything else → `.unsupportedSource`**. A cask
binary's resolved path is under `/opt/homebrew/Caskroom/...`, so `classifySource`
(`ToolDetector.swift:187-191`) returns `standalone` and the verifier refuses before any manager
query. The `.unsupportedCask` reason is therefore only reachable for a *Cellar* copy whose
definition declares a cask — i.e. essentially never. **Consequence:** M13 needs a *routing* change
as well as a *proof* change, and the routing must not be driven by the source heuristic (the
heuristic is exactly what fails for casks).

**F-2 — Cask ownership cannot be proved by any Cellar-shaped rule, but it has an exact analogue.**
Verified live shapes: `brew --caskroom` → `/opt/homebrew/Caskroom`; `brew --caskroom codex` →
`/opt/homebrew/Caskroom/codex`; `brew list --verbose --cask homebrew-app` prints
`/opt/homebrew/Caskroom/homebrew-app/.metadata/INSTALL_RECEIPT.json`,
`.../.metadata/config.json`,
`.../.metadata/0.6.0/20261015125242.755/Casks/homebrew-app.json` and
`/opt/homebrew/Caskroom/homebrew-app/0.6.0/Homebrew.app`. The Caskroom layout is
`<caskroom>/<token>/<version>/<artifact>` — structurally the Cellar's
`<cellar>/<formula>/<keg-version>/<rel>` with **token** where **formula** goes and a
**version directory** where the **keg version** goes — but the version component is an
*arbitrary* string, not a Homebrew-stable version (e.g. `1.5.13,5999302598852608`,
`3.4.4`, `latest`). The proof therefore must decompose by **path components** and must never
apply the formula version grammar to the Caskroom version directory.

**F-3 — `brew list --verbose --cask` is the cask membership oracle, exactly as
`brew list --verbose --formula` is for formulae.** From `cmd/list.rb:200-204`: for casks the
command runs `find <caskroom_path> -not -type d -not -name .DS_Store -print`, i.e. it enumerates
the **staged files of that token**. The formula proof already has the matching primitive —
`listConfirmsSelectedPath` (`HomebrewOwnershipProbe.swift:342-362`) — which requires the selected
canonical path to be one of the manager's listed paths. Cask ownership reuses that idea with the
Caskroom listing instead of the keg listing.

**F-4 — `brew info --json=v2 --cask` carries the install-time facts the proof needs, but only for
a *known* cask.** Verified: `brew info --json=v2 --cask codex` → `installed = null`,
`auto_updates = null`, `pinned = false`, `outdated = false`, `version = "0.171.0"`,
`artifacts = [{"binary":["bin/codex"],"target":"/opt/homebrew/bin/codex"}, …]`.
`brew info --json=v2 --cask vorssaint` → `installed = "3.4.3"`, `version = "3.4.4"`,
`installed_time = 1793617399`, `auto_updates = true`. `brew info --json=v2 --cask
no-such-cask-xyz` → **exit 1**, stdout empty. `brew info --json=v2 --cask amazon-q` (an *old*
token of `kiro-cli`) → resolves to `token = "kiro-cli"`, `old_tokens = ["amazon-q","codewhisperer"]`.
So the *manager* resolves renames; our proof must compare against the **returned** token and the
recorded `old_tokens`, not against the string we asked for.

**F-5 — the `installed` field is the installed version, the `version` field is the manager's
latest known version, and `outdated` is the manager's own verdict.** Verified in the cask JSON
schema (`/opt/homebrew/Library/Homebrew/cask/cask.rb:614-634`): `"installed" => installed_version`,
`"version" => version`, `"outdated" => outdated?`, `"pinned" => pinned?`,
`"pinned_version" => pinned_version`, `"auto_updates" => auto_updates?` (via `to_hash`), plus
`"old_tokens"`, `"tap"`, `"token"`, `"full_token"`, `"artifacts"`. For the *outdated* JSON the
cask record shape is `{name: token, installed_versions: [installed], current_version: version,
pinned:, pinned_version:}` (`cask/cask.rb:529-536`) — note **`name` is the token, not the full
name** for casks, whereas formulae use `full_name` (`cmd/outdated.rb:200`). Any cask association
must key on the token, never on a basename.

**F-6 — cask versions are not comparable by any grammar we own.** Live evidence:
`version` is `"latest"` for 2 157 casks in the signed API payload and comma-multi-part
(`"1.5.13,5999302598852608"`, `"6.0,9001"`, `"3.5.1,4.0"`) for 820 of them. Homebrew's own cask
comparison is *equality plus special classes* (`cask/cask.rb:473-509`): a cask is outdated when
`installed_version != version`, with `:latest` handled by download-SHA comparison and
`auto_updates` by bundle-version comparison. **Therefore M13-B must not invent a cask version
comparator**: the manager's `outdated` verdict is the oracle, and `:latest` / `auto_updates` casks
are *unknown*, never "up to date".

**F-7 — `brew upgrade` of a *named* cask uses greedy semantics.** `cask/upgrade.rb:57-79`: when
cask names are given, the cask is considered outdated with `greedy: true`; `:71` `cask.outdated?(greedy:
true)`, `:73-75` "Not upgrading X, the downloaded artifact has not changed" for a `:latest` cask.
For formulae, `cmd/upgrade.rb:214-227` resolves named args and `:249-250` prevents the
"upgrade everything" path when names were given. So a named target never turns into a broad
upgrade — provided we always pass exactly one name.

**F-8 — `brew upgrade` cannot be pinned to a version; the preview cannot promise a version.**
`brew upgrade --help` documents no version-selection flag for `upgrade` (only `--minimum-version`,
a floor, and `--build-from-source`). Homebrew resolves the target itself at execution time. So
the M13 preview must state the **observed latest-known version** and must additionally state that
Homebrew re-resolves the target when it runs; the M12-style "target changed → invalidate" rule
still applies to the *observed* target, but it cannot be a version guarantee.

**F-9 — a cask uninstall runs the cask's own uninstall steps, and the app-artifact case removes a
companion app.** From `brew uninstall --help`: `--zap` "Remove all files associated with a
<cask>. *May remove files which are shared between applications*", `--force` "Delete all installed
versions … ignore errors when removing files", `--ignore-dependencies` "Don't fail uninstall, even
if <formula> is a dependency of any installed formulae". Source: `cask/installer.rb:641-667`
(`uninstall` → `uninstall_artifacts(clear: true, successor:)`), `:745-791` (the directive pass
runs `Artifact::Uninstall` stanzas — quit, pkgutil, launchctl, script, delete — and the
**zap** stanza only in the `zap` path `:794-811`), `cask/artifact/moved.rb:200-226` (the app
artifact is copied back and the target deleted → the app leaves `/Applications`).
Default (no `--zap`) therefore runs the *uninstall* stanza and the artifact removal but **not** the
zap trash list — which is precisely the D-008 "configurations and caches are never touched"
boundary, provided we never pass `--zap`.

**F-10 — three documented environment switches stand between "one package" and "many packages".**
`/opt/homebrew/Library/Homebrew/env_config.rb`: `HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK`
(`:596-601`), `HOMEBREW_NO_INSTALL_CLEANUP` (`:603-608`), `HOMEBREW_NO_AUTOREMOVE` (`:538-542`),
`HOMEBREW_NO_ASK` (`:534-537`), `HOMEBREW_NO_AUTO_UPDATE` (`:543-550`), `HOMEBREW_NO_ANALYTICS`
(`:529-532`), `HOMEBREW_CACHE` (`:236-242`), `HOMEBREW_LOGS` (`:514-520`), `HOMEBREW_TEMP`
(`:748-755`). `cmd/uninstall.rb:164-171` runs `Cleanup.autoremove` unless
`HOMEBREW_NO_AUTOREMOVE` is set; `cmd/uninstall.rb:47` picks `kegs` vs `default_kegs` by
`--force` (so without `--force` only the default keg is removed and
`uninstall.rb:85-91` prints "X 1.0 2.0 are still installed").

**F-11 — Homebrew's prefix is derived from where `brew` lives, so a scratch prefix is a *location*
decision, and the product already follows it.** `bin/brew:79-96` computes `HOMEBREW_PREFIX` from
`HOMEBREW_BREW_FILE`; `bin/brew:117-125` lists `HOMEBREW_PREFIX`, `HOMEBREW_REPOSITORY`,
`HOMEBREW_LIBRARY`, `HOMEBREW_BREW_FILE` as **not user-overridable**; `startup/config.rb:13-70`
derives `HOMEBREW_CELLAR`, `HOMEBREW_CASKROOM`, `HOMEBREW_CACHE`, `HOMEBREW_LOGS`,
`HOMEBREW_TEMP` from it. Combined with `HomebrewManagerResolver.resolve`
(`HomebrewIdentity.swift:25-38`) taking the first live `brew` on the login-shell PATH, a scratch
prefix is reached by putting the scratch `bin` first on PATH — no product change, no env var
override of the prefix.

**F-12 — the `agy` cask changed upstream after M11 froze it.** The upstream file at revision
`60c151f6` (2026-11-12) contains `auto_updates true` and `binary "antigravity", target: "agy"`; the
current upstream file contains **no** `auto_updates` stanza and instead uses
`command_wrapper "agy", executable: "#{staged_path}/antigravity", env: {"AGY_CLI_DISABLE_AUTO_UPDATE"
=> "true"}` with the caveat "Use `brew upgrade --cask #{token}` instead of `agy update`". Live
`brew info --json=v2 --cask antigravity-cli` → `auto_updates = null`; the signed API payload has
`auto_updates = null` for that token while `iterm2`, `visual-studio-code`, `docker`,
`google-chrome` all report `true`. The M11 matrix row (`docs/capability-matrix.md:39`,
`docs/catalogue-identities.md:493,504-505`) therefore describes the 2026-11-12 state and is stale
as of 2026-11-21. `auto_updates` must be read per invocation and never assumed.

**F-13 — `opencode`'s three formula candidates are ambiguous under the existing formula proof.**
`HomebrewOwnershipProbe.swift:106-110` matches declared candidates by **stem**
(`formulaStem($0.name) == keg.formula`) and requires exactly one match. `opencode` declares
`opencode`, `anomalyco/tap/opencode` and `anomalyco/tap/opencode-v2`; the first two share the stem
`opencode`, so a core-`opencode` keg matches **two** candidates → `.ambiguousOwnership`. Two of the
three also live in taps that are not installed here — verified:
`brew info --json=v2 --formula can1357/tap/omp` → exit 1, "This command requires the tap
can1357/tap". So a tap-declared formula is provable **only when the tap is present**.

**F-14 — the npm vocabulary and codex behaviour are entangled in two places M13 must not break.**
`WorkflowPresentation.swift:193` gates the Update affordance on `entry.update?.npmPackage != nil`
— a *brew* status never satisfies it; `:216` gates Uninstall on
`entry.ownership?.verifiedInstallation?.manager == .npm`. `ToolDetailView.swift:293-302` renders the
Manage section only for npm-declared entries, and `:493-495` labels the version cell
"Latest Known Homebrew Metadata" purely by "not npm". Every one of these is npm-shaped and must be
extended, not replaced, or the accepted codex behaviour changes.

**F-15 — `PackageManager.homebrewCask` already exists but is unreachable.** `DetectorMetadata.swift:66-71`
defines it and `OwnershipVerificationView.swift:117-124` renders `installation.manager.label`, so
the *display* vocabulary is ready; only the proof and the router are missing.

### A.3 ADD / CHANGE / PRESERVE

**ADD (new, no existing behaviour touched)**

| Item | Where | Note |
|---|---|---|
| Cask ownership proof (3 manager queries + path-component decomposition + revalidation) | new `Sources/AgentLensCore/Ownership/HomebrewCaskOwnershipProbe.swift` | mirrors `HomebrewOwnershipProbe` structure |
| Cask-specific typed ownership reasons | `InstallationOwnership.swift` (additive enum cases) | existing reasons untouched |
| Cask router in the ownership verifier | `InstallationOwnershipVerifier.swift` | existing npm/brew branches byte-identical |
| Cask latest-check probe + status resolver | new `Sources/AgentLensCore/Updates/HomebrewCaskUpdateProbe.swift` | ≤3 commands per batch, M6 shape |
| Cask metadata cache document | new `Sources/AgentLensCore/Updates/HomebrewCaskMetadataCache.swift` | separate file, M10-B isolation pattern |
| Homebrew operation models (previews, outcomes, deltas, effect texts) | new `Sources/AgentLensCore/Operations/HomebrewOperationModels.swift` | npm vocabulary untouched |
| Formula Update/Uninstall operations | new `Sources/AgentLensCore/Operations/HomebrewFormulaUpdateOperation.swift`, `…/HomebrewFormulaUninstallOperation.swift` | reuse `OperationProcessRunner` + `OperationExecutionGate.shared` |
| Cask Update/Uninstall operations | new `Sources/AgentLensCore/Operations/HomebrewCaskUpdateOperation.swift`, `…/HomebrewCaskUninstallOperation.swift` | same lifecycle |
| Operation environment policy | new `Sources/AgentLensCore/Operations/HomebrewOperationEnvironment.swift` | one place that builds the env + disclosure |
| Brew preview sheets | new `Sources/AgentLensApp/HomebrewUpdateOperationView.swift`, `…/HomebrewUninstallOperationView.swift` | npm sheets byte-identical (M10-D fixture host compiles `UninstallOperationView.swift`) |
| Disposable acceptance harness | new `Tests/Fixtures/M13/homebrew_acceptance.py` | test code, stdlib only |
| New `AcceptedOperation` cases | `DetectorMetadata.swift:78-81` | additive, schema stays 2 |

**CHANGE (existing files; each is additive or a named-contract change the judge must rule on)**

| Item | Where | Contract impact |
|---|---|---|
| `AcceptedOperation` gains 4 cases; validator message changes | `DetectorMetadata.swift:78-81`, `:270-295`; `DetectorRegistry.swift:215-240`, `:1076-1108` | **named contract change**: the pinned error string "must be one of npmUpdate, npmUninstall" becomes a 6-name list; two tests pin it and must be updated |
| `InstallationOwnershipReason` gains cask cases | `InstallationOwnership.swift:63-94` | additive enum cases; `NpmUpdateProbe.mapOwnershipReason` (`:1359-1371`) has a `default:` arm so it keeps compiling |
| `UnknownReason` gains cask reasons | `Sources/AgentLensCore/Updates/VersionStatus.swift:27-47` | **exhaustive switches** in `UpdateScanRenderer.explanation` (`:101-127`) and `ToolDetailView.plainLanguageReason` (`:620-655`) must gain arms in the same phase |
| Ownership router learns casks | `InstallationOwnershipVerifier.swift:139-164` | new branch; npm/brew branches unchanged |
| Coordinator gains a cask stage | `UpdateProbeCoordinator.swift:187-330` | same admitted stage, same 60 s budget; formula stage unchanged |
| `ManagementPresentation` learns brew affordances | `WorkflowPresentation.swift:153-238` | npm sentences byte-identical; new sentences for brew |
| `InventoryService` / `InventoryViewModel` gain brew pipelines | `InventoryService.swift:294-517`; `InventoryViewModel.swift:338-646` | M12 R1 invalidation must also release brew preparations |
| Tool detail view gains brew sections | `ToolDetailView.swift:280-311`, `:468-557` | codex block byte-identical |
| Capability matrix rules | `docs/capability-matrix.md:16-21`; `CapabilityMatrixTests.swift:143-234` | **named contract change** (see §E) |
| Registry `acceptedOperations` for promoted entries | `Sources/AgentLensCore/Detectors/DefaultDetectors.json` | data-only; owner decision §E |
| `agy` matrix row corrected (auto_updates) | `docs/capability-matrix.md:39` | data correction, F-12 |

**PRESERVE (must be byte-identical; a change here is a phase failure)**

1. `Sources/AgentLensCore/Operations/OperationModels.swift` — the npm public vocabulary, effect
   texts, `InstallationDelta`, `NpmUninstallDelta`, `OperationExecutionGate.shared`,
   `OperationCommandRunner`.
2. `Sources/AgentLensCore/Operations/NpmUpdateOperation.swift`, `NpmUninstallOperation.swift` —
   including the D-021 guard position and the npm argv.
3. `Sources/AgentLensCore/Ownership/NpmOwnershipProbe.swift`.
4. `Sources/AgentLensCore/Updates/HomebrewUpdateProbe.swift` — formula batch, `queryTimeout`,
   `diagnosticEnvironment`, `HomebrewStatusResolver`.
5. `Sources/AgentLensCore/Updates/UpdateMetadataCache.swift` (formula cache) and
   `NpmUpdateMetadataCache.swift`.
6. `Sources/AgentLensCore/Detection/DetectorMetadata.swift` — `PackageManager`, `ToolCategory`,
   declared-package grammar, `DetectorRegistry` schema-2 semantics (absent → `[]`).
7. `Sources/AgentLensApp/UpdateOperationView.swift`, `UninstallOperationView.swift` — public
   initializers (the M10-D fixture host compiles and constructs them:
   `Tests/Fixtures/M10D/npm_uninstall_acceptance.py:480-481,499-500,548-551`).
8. `Sources/AgentLensAppSupport/WorkflowPresentation.swift` — the npm sentences and the
   `update.npmPackage != nil` / `manager == .npm` npm gating.
9. `Sources/agent-lens/main.swift` — the three-command dispatch surface; no mutation syntax (D-022).
10. `.github/workflows/ci.yml`, `scripts/**`, `Package.swift`, `Resources/**`, `Tests/Fixtures/M10C/**`,
    `Tests/Fixtures/M10D/**`, all historical `briefs/**` and `walkthroughs/**`.

---

## B. Phase decomposition

Shared protected set for **every** phase: `Package.swift`, `Resources/**`, `scripts/**`,
`.github/**`, `Sources/agent-lens/**` (except where a phase names it), `Sources/AgentLensCore/**`
(except where a phase names it), `Sources/AgentLensAppSupport/**` (except where a phase names it),
`Sources/AgentLensApp/**` (except where a phase names it), `Tests/Fixtures/M10C/**`,
`Tests/Fixtures/M10D/**`, `Tests/Packaging/**`, `DECISIONS.md`, `ROADMAP.md`,
`AGENT_LENS_SCOPE.md`, `docs/**` (except `docs/capability-matrix.md` in M13-F), and every
historical `briefs/**` / `walkthroughs/**` file. Zero new dependencies. One writer at a time.

Local gate set (every phase; R16-style, fresh scratch):

```sh
env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS swift build
env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS \
  swift test --build-system swiftbuild --scratch-path <scratch>/full-suite --no-parallel \
  -Xswiftc -load-plugin-library \
  -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib
python3 scripts/check-core-ui-imports.py
python3 scripts/check-core-ui-imports.py --source-root Sources/AgentLensAppSupport
python3 Tests/Packaging/test_core_ui_imports.py
python3 scripts/build-dev-app.py --scratch-root <scratch>/app --configuration debug
python3 Tests/Packaging/test_dev_app_bundle.py --app <scratch>/app/AgentLensApp-debug.app
git diff --check
```

Expected: exit 0; zero skips/failures; guard 21; packaging 9. **Floors move only at M13-H**, and
only to orchestrator-measured counts. The implementer never edits `ci.yml`.

### M13-A — Cask identity and ownership proof (Core, read-only)

- **Goal:** a cask-installed CLI can be *proven* to belong to a declared cask, with the manager's
  own evidence, and `verify-installation` can report it. No mutation, no latest-check, no App
  change.
- **Non-goals:** no `acceptedOperations` change; no `brew upgrade`/`uninstall`; no matrix edit; no
  registry data change; the `agy` matrix correction waits for M13-F.
- **Allow-list (production):** `Sources/AgentLensCore/Ownership/HomebrewCaskOwnershipProbe.swift`
  (new); `Sources/AgentLensCore/Ownership/InstallationOwnership.swift` (additive reasons only);
  `Sources/AgentLensCore/Ownership/InstallationOwnershipVerifier.swift` (cask branch);
  `Sources/AgentLensCore/Ownership/InstallationOwnershipRenderer.swift` (cask fields only).
- **Allow-list (tests):** `Tests/AgentLensCoreTests/HomebrewCaskOwnershipProbeTests.swift` (new);
  `Tests/AgentLensCoreTests/InstallationOwnershipTests.swift` (new cases only).
- **Contracts:** §C (proof). Ownership never depends on version comparability, update
  availability, or the source heuristic. The npm and formula branches of the verifier are
  byte-identical. The cask probe returns `.unknown(reason)` — never `.verified` — unless every
  step of §C succeeds.
- **Acceptance:** scripted-runner unit tests covering: cask binary owned; cask `command_wrapper`
  owned; app-bundle cask (no CLI) → not a CLI installation; standalone copy → not owned; wrong
  token; old-token/rename (record token ≠ requested token, requested token ∈ `old_tokens`);
  Caskroom version dir ≠ receipt version; selected path not in the manager's listing; missing
  receipt; disabled cask; tap cask (`full_token` = `owner/repo/token`); manager changed mid-proof;
  selection changed mid-proof. Plus a **read-only** live observation against the two personal
  casks (`vorssaint`, `homebrew-app` — observation only, never a mutation target) recording the
  exact `brew --caskroom`, `brew info --json=v2 --cask`, `brew list --verbose --cask` argv and
  output, and a SHA-256 manifest of the personal prefix before/after proving the read-only path
  changed nothing.
- **Dependencies:** none (first phase).
- **Stop conditions:** the proof would need a Cellar-shaped assumption; the router would need to
  change the npm/brew branches; a declared cask name would have to be trusted without the
  manager's confirmation; `/Applications` or the personal prefix would have to be touched.
- **Tier:** strongest reasoning. **Review: mandatory independent review by BOTH council models**
  (ownership contract).

### M13-B — Cask latest-check, tri-state and cask metadata cache (Core, read-only)

- **Goal:** a cask's manager-known latest version can be observed with a truthful tri-state, cached
  in its own document, and surfaced in the existing Update-Status surface — without any cask
  version comparator and without `unknown` ever collapsing into "up to date".
- **Non-goals:** no mutation; no promotion; no matrix cell change (the cask latest-check cell
  becomes truthful in M13-F); no `agy` correction.
- **Allow-list (production):**
  `Sources/AgentLensCore/Updates/HomebrewCaskUpdateProbe.swift` (new);
  `Sources/AgentLensCore/Updates/HomebrewCaskMetadataCache.swift` (new);
  `Sources/AgentLensCore/Updates/UpdateProbeCoordinator.swift` (cask stage);
  `Sources/AgentLensCore/Updates/VersionStatus.swift` (additive reasons);
  `Sources/AgentLensCore/Updates/UpdateScanRenderer.swift` (cask provenance + reasons);
  `Sources/AgentLensApp/ToolDetailView.swift` (the `plainLanguageReason` arms only — no layout
  or copy change beyond the new reasons).
- **Allow-list (tests):** `Tests/AgentLensCoreTests/HomebrewCaskUpdateProbeTests.swift` (new);
  `Tests/AgentLensCoreTests/HomebrewCaskMetadataCacheTests.swift` (new);
  `Tests/AgentLensCoreTests/UpdateProbeCoordinatorTests.swift` (cask cases);
  `Tests/AgentLensCoreTests/UpdateCLIIntegrationTests.swift` (cask rows).
- **Contracts:** §F. Batch = at most three commands (`brew --caskroom`,
  `brew info --json=v2 --cask <names…>`, `brew outdated --json=v2 --cask`), only when ≥1 cask
  candidate is eligible; the formula batch, npm batch, 60 s stage budget and 10 s per-query bound
  are unchanged; `unknown` never inflates `updateAvailableCount`.
- **Acceptance:** unit tests for each tri-state branch (§F.3) including `:latest`, `auto_updates`,
  multi-part version, deprecated, disabled, pinned, unknown-token, offline, manager failure; cache
  tests for TTL boundary, 1 MiB cap, context-digest mismatch, ambiguity miss, ecosystem isolation
  (a cask entry can never satisfy a formula lookup and vice versa); a read-only live observation of
  `brew info --json=v2 --cask <token>` and `brew outdated --json=v2 --cask` recorded verbatim.
- **Dependencies:** M13-A (the status may only be published for a *proven* cask installation).
- **Stop conditions:** a cask version comparator would have to be invented; `unknown` would have
  to be reported as "up to date"; the formula cache document would have to be extended in place.
- **Tier:** strongest reasoning. **Review: mandatory independent review by BOTH council models**
  (truthfulness + a second cache document).

### M13-C — Disposable real-Homebrew acceptance environment (test-only; no product code)

- **Goal:** a *real* Homebrew in a *scratch* prefix, with synthetic formulae and casks, that the
  later phases can mutate without touching the personal prefix, the personal Cellar/Caskroom,
  `/Applications`, or any personal cache.
- **Non-goals:** no product source change; no acceptance verdict; no registry/CLI/App change.
- **Allow-list (tests only):** `Tests/Fixtures/M13/homebrew_acceptance.py` (new);
  `Tests/Fixtures/M13/README.md` (new, harness notes).
- **Contracts:** §G. The environment is disposable; it is destroyed by the harness at the end of
  each scenario; the personal prefix is read-only and hash-manifested before and after.
- **Acceptance:** the harness proves, in order: (i) a scratch `bin/brew` runs the *real* Homebrew
  code at a pinned revision and reports a scratch `--prefix`/`--cellar`/`--caskroom`; (ii) a
  synthetic tap can be installed into the scratch prefix; (iii) a synthetic **formula** installs
  and links; (iv) a synthetic **binary-artifact cask** installs and links a CLI; (v) a synthetic
  **app-artifact cask** installs into a scratch app dir, never `/Applications`; (vi) a synthetic
  **`auto_updates` cask** and a synthetic **`:latest` cask** can be produced; (vii) upgrade and
  uninstall inside the scratch prefix work and the personal prefix is byte-identical afterwards;
  (viii) a pinned synthetic package is refused by brew itself. Each step records raw argv, stdout,
  stderr, exit code and elapsed time.
- **Dependencies:** M13-A/B may proceed in parallel conceptually but the branch is sequential, so
  M13-C lands before the mutation phases.
- **Stop conditions:** the scratch prefix cannot be made to work without the personal prefix or
  without network; any scenario would touch `/Applications` or a personal cache; the harness
  cannot prove a sentinel.
- **Tier:** flash (test code, no product semantics). **Review: orchestrator acceptance** (the
  judge runs the feasibility probe and records the result), plus a read-only note from one council
  model on the harness's honesty.

### M13-D — Operation vocabulary + Homebrew **formula** Update/Uninstall (Core, mutation)

- **Goal:** `AcceptedOperation` can express Homebrew operations; a verified Homebrew *formula*
  copy can be updated and uninstalled through the M10 lifecycle with a literal argv, an honest
  effect text, and a reconciliation that never trusts exit zero.
- **Non-goals:** no cask operation; no registry promotion; no matrix edit; no App change; no
  cask ownership/latest work.
- **Allow-list (production):**
  `Sources/AgentLensCore/Detection/DetectorMetadata.swift` (the 4 new cases + validator list);
  `Sources/AgentLensCore/Detection/DetectorRegistry.swift` (both decode paths use the shared
  validator — only the message text changes);
  `Sources/AgentLensCore/Operations/HomebrewOperationModels.swift` (new);
  `Sources/AgentLensCore/Operations/HomebrewOperationEnvironment.swift` (new);
  `Sources/AgentLensCore/Operations/HomebrewFormulaUpdateOperation.swift` (new);
  `Sources/AgentLensCore/Operations/HomebrewFormulaUninstallOperation.swift` (new).
- **Allow-list (tests):** `Tests/AgentLensCoreTests/HomebrewFormulaUpdateOperationTests.swift`
  (new); `…/HomebrewFormulaUninstallOperationTests.swift` (new);
  `…/DetectorMetadataTests.swift` and `…/DetectorRegistryTests.swift` (vocabulary list + the two
  pinned message assertions — updated, not weakened).
- **Contracts:** §D. The D-021 gate position is preserved exactly: cancellation first, then
  `acceptedOperations.contains(.homebrewFormulaUpdate)` → `.operationNotAccepted`, before any
  observation, scratch claim or process. `OperationExecutionGate.shared` is the **same**
  process-wide gate npm uses, so an npm mutation and a brew mutation can never overlap. The npm
  vocabulary files are not edited.
- **Acceptance:** unit tests for: refusal ordering (gate before any manager call — a counting
  runner must observe zero calls); cancel-before-gate; preview content (manager prefix, formula vs
  cask, full package identity, literal argv, effect text); stale-identity invalidation (manager,
  prefix, cellar, keg version, selected entry/target, observed target version); operation-time
  revalidation; exit-zero-without-change → not success; interruption → `.interrupted`/`.uncertain`
  with reconciliation; gate contention (a second prepare/execute is refused while one is in
  flight); environment policy assertions (the exact env keys and values of §D.4); one-argument
  argv (`upgrade --formula <full-name>`, `uninstall --formula <full-name>`) with no `--all`,
  no `--force`, no `--ignore-dependencies`.
- **Dependencies:** M13-A (formula ownership already exists; the cask proof is not required here),
  M13-C (the live scenario).
- **Stop conditions:** the npm vocabulary would have to change; the gate would have to move; a
  second mutation gate would be introduced; the argv would need more than one target.
- **Tier:** strongest reasoning. **Review: mandatory independent review by BOTH council models**
  (mutation + gate).

### M13-E — Homebrew **cask** Update/Uninstall (Core, mutation)

- **Goal:** a verified cask installation can be updated and uninstalled with the whole-cask
  disclosure visible in the preview, `zap` never used, and a cask-specific reconciliation.
- **Non-goals:** no promotion; no matrix edit; no App change; no `brew install`; no cask
  auto-updater invocation.
- **Allow-list (production):**
  `Sources/AgentLensCore/Operations/HomebrewCaskUpdateOperation.swift` (new);
  `Sources/AgentLensCore/Operations/HomebrewCaskUninstallOperation.swift` (new);
  `Sources/AgentLensCore/Operations/HomebrewOperationModels.swift` (cask previews/outcomes/
  deltas/effect text);
  `Sources/AgentLensCore/Operations/HomebrewOperationEnvironment.swift` (cask env policy).
- **Allow-list (tests):** `Tests/AgentLensCoreTests/HomebrewCaskUpdateOperationTests.swift` (new);
  `…/HomebrewCaskUninstallOperationTests.swift` (new).
- **Contracts:** §D. Cask argv is `upgrade --cask <token>` / `uninstall --cask <token>`; the
  preview must show the cask's own uninstall steps and the companion-app consequence read from
  the manager's `artifacts`; `--zap`, `--force`, `--ignore-dependencies` are structurally
  impossible (argv is built from a closed field list, and a test asserts the forbidden flags
  cannot appear).
- **Acceptance:** unit tests for: whole-cask disclosure content (app target named, uninstall
  stanza named, zap explicitly excluded); pinned refusal before launch; disabled-cask refusal;
  `:latest`/`auto_updates` cask refusal for Update with a typed reason; dependent-cask refusal
  surfaced as an honest manager failure; reconciliation facts (Caskroom version dir replaced,
  receipt replaced, target relinked, app artifact gone, residue reported, observation failure
  reported); interruption handling; gate contention; env-policy assertions.
- **Dependencies:** M13-A (cask proof), M13-B (cask status), M13-C (live scenario), M13-D
  (shared operation models, environment policy and the shared gate).
- **Stop conditions:** the preview would need to promise a version; `--zap` would appear; the
  manager's refusal would have to be bypassed; a second gate would appear.
- **Tier:** strongest reasoning. **Review: mandatory independent review by BOTH council models**
  (mutation + destructive disclosure).

### M13-F — Promotion, capability matrix, registry and catalogue facts

- **Goal:** the owner's promotion decision is applied as registry data, the capability matrix gains
  Homebrew cells and a test-enforced rule, and the stale `agy` auto-update claim is corrected.
- **Non-goals:** no Core logic change; no App change; no new tools; no behaviour for
  non-promoted entries.
- **Allow-list (production/docs):**
  `Sources/AgentLensCore/Detectors/DefaultDetectors.json` (data only — `acceptedOperations`);
  `docs/capability-matrix.md` (cell grammar + the `agy` correction);
  `docs/catalogue-identities.md` (the `agy` auto-update sentence only).
- **Allow-list (tests):** `Tests/AgentLensCoreTests/CapabilityMatrixTests.swift` (rule extension);
  `Tests/AgentLensCoreTests/BundledRegistryResourceTests.swift` (frozen-catalogue assertions if
  they pin accepted operations); `Tests/AgentLensCoreTests/DetectorMetadataTests.swift` and
  `DetectorRegistryTests.swift` (vocabulary list).
- **Contracts:** §E. The matrix rule becomes: a `yes` cell requires (a) the matching accepted
  operation, (b) a declared candidate of the *matching manager kind*, and (c) — by the row's own
  wording — verified ownership of that kind. Non-promoted rows keep the `informational:` /
  `disabled:` grammar. The `latest-check` cell gains `yes: homebrewCask` where the cask
  latest-check is shipped (replacing the current blanket prohibition at
  `CapabilityMatrixTests.swift:230-232`), and the cross-row note keeps saying that cask copies
  classify `standalone` (F-1) while adding that a *verified* cask copy is owned by Homebrew.
- **Acceptance:** matrix test passes with the new grammar; a seeded corruption (a `yes` cell
  without the accepted operation; a `yes: homebrewCask` latest-check on a cask-less row) must fail
  the same function; the frozen 14-id catalogue assertion still holds; the registry JSON still
  validates on both decode paths.
- **Dependencies:** M13-D and M13-E accepted (the operations exist before any entry is
  promoted). **This phase is gated on the owner's OD-M13-1 answer; without it, this phase
  delivers only the rule extension and the `agy` correction, with zero promotions.**
- **Stop conditions:** the matrix would have to claim a capability no phase proved; a promotion
  would happen without its own acceptance scenario; the `agy` row would keep a claim the live
  manager contradicts.
- **Tier:** flash (data + test). **Review: mandatory independent review by BOTH council models**
  (the mutation-authority surface).

### M13-G — AppSupport / App / CLI integration

- **Goal:** brew management is reachable from the native workflow with truthful presentation, the
  M12 invalidation and footer contracts preserved, and the CLI extended **read-only**.
- **Non-goals:** no Core change; no new CLI command; no mutation syntax; no new setting; no
  change to the codex npm surface.
- **Allow-list (production):**
  `Sources/AgentLensAppSupport/WorkflowPresentation.swift` (brew affordances + new sentences);
  `Sources/AgentLensAppSupport/InventoryService.swift` (brew prepare/execute/cancel);
  `Sources/AgentLensAppSupport/InventoryViewModel.swift` (brew pipelines + invalidation);
  `Sources/AgentLensApp/HomebrewUpdateOperationView.swift` (new);
  `Sources/AgentLensApp/HomebrewUninstallOperationView.swift` (new);
  `Sources/AgentLensApp/ToolDetailView.swift` (brew section, formula-vs-cask, prefix, identity,
  whole-cask disclosure);
  `Sources/AgentLensApp/MainWindow.swift` (brew sheets);
  `Sources/agent-lens/main.swift` (**read-only** cask rows in `scan --check-updates`; the cask
  route in `verify-installation` arrives free from M13-A).
- **Allow-list (tests):** `Tests/AgentLensAppSupportTests/WorkflowPresentationTests.swift`;
  `Tests/AgentLensAppSupportTests/InventoryServiceTests.swift`;
  `Tests/AgentLensAppSupportTests/InventoryViewModelTests.swift`;
  `Tests/AgentLensAppSupportTests/OwnershipVerificationTests.swift`.
- **Contracts:** §H. The codex npm block, the npm sheets and their initializers are
  byte-identical; the brew sheets follow the **C-1** footer contract (no `.defaultAction` in the
  preview state, Cancel = `.cancelAction`, destructive confirm with no key equivalent); the
  **M12 R1** invalidation trigger set additionally releases a pending *brew* preparation; sheets
  still bind to preview/preparation/outcome/unavailable and never to `selectedEntry`; Core reason
  strings are read, never retyped.
- **Acceptance:** AppSupport tests for each new affordance and its refusal sentence; the R1
  trigger set proven to release a brew preparation on every trigger; the C-1 footer proven for the
  brew sheets; a native spot-check by the orchestrator (brew Update/Uninstall preview shows manager
  prefix, formula-vs-cask, full identity, literal argv, whole-cask disclosure; Return does not
  confirm; Escape cancels). The M10-D fixture host still compiles and runs unchanged.
- **Dependencies:** M13-D, M13-E, M13-F.
- **Stop conditions:** the npm sheets would change; a reason string would be retyped in AppSupport;
  a brew sheet would bind to `selectedEntry`; a CLI mutation verb would appear.
- **Tier:** strongest reasoning (mutation presentation). **Review: mandatory independent review by
  BOTH council models.**

### M13-H — Combined acceptance (orchestrator-run)

- **Goal:** the milestone's ROADMAP acceptance, end to end, on the frozen candidate.
- **Method:** the full local gate set re-run by the orchestrator at the frozen SHA; the M13
  disposable harness run for **every** promoted entry (one controlled scenario each: preview →
  Cancel with byte-identical prefix hashes → preview → Confirm → reconciled result → post-rescan
  inventory); the native ordinary-app journey driven through Accessibility against the scratch
  prefix (M10-D method) with the before/after SHA-256 manifest; CLI parity (`agent-lens
  scan --check-updates` and `agent-lens verify-installation <id>` agree with the app);
  interruption and concurrent-Confirm cases; **sentinels** proving the personal prefix, personal
  Cellar/Caskroom, `/Applications` and personal caches are byte-identical before and after; all
  seven hosted gates at the exact SHA with floors raised **only** to orchestrator-measured counts;
  the capability matrix agreeing with the registry and with the runtime facts.
- **Acceptance:** all of §G.6.
- **Tier:** orchestrator. **Review:** both council models read the evidence; they do not re-run
  destructive scenarios against personal installs.

---

## C. Cask identity and ownership

### C.1 The proof, step by step

The formula proof (`HomebrewOwnershipProbe.swift:55-225`) is three manager queries plus local
identity observations plus a revalidation. The cask proof is the same skeleton with the Caskroom
in place of the Cellar. **No step may be satisfied by a declaration, a basename, or a Caskroom
substring alone.**

**Step 0 — manager resolution (no query).** Reuse `HomebrewManagerResolver.resolve`
(`HomebrewIdentity.swift:25-38`): the first live `brew` on the ordered login-shell PATH. Same
rule as the formula proof, so a scratch prefix re-targets the proof (§G.2).

**Step 1 — manager-reported Caskroom root.** `brew --caskroom` → exactly one absolute path
(`/opt/homebrew/Caskroom` here). One query. Fail-closed: the output must be a single absolute
path (reuse `ManagerOutputParser.singleAbsolutePath`, `ExecutableIdentity.swift:265-282`).

**Step 2 — path-component decomposition of the selected executable.** Let `T` be the selected
executable's **canonical target** (symlinks resolved, exactly as
`FileIdentityObserver.observeExecutable` computes it, `ExecutableIdentity.swift:59-83`). Then `T`
must decompose, **by path components**, as

```
<caskroom>/<token>/<version-dir>/<relative…>
```

with: the caskroot prefix matched component-wise (never by string prefix); at least three
components below the caskroot; no empty, `.` or `..` component; and the **token** component
matching the manager's own token for the cask we are about to query (step 3). The
**version-dir component is opaque** — it is a directory name such as `3.4.3` or
`1.5.13,5999302598852608`; it is never parsed as a version. The `relative…` part may be empty
(the cask's staged artifact may be the directory itself, e.g. `…/3.4.3/Vorssaint.app`) or may
include a `.homebrew-command-wrappers/…` component (the `command_wrapper` shape).

> **Why this is the right analogue.** `HomebrewTargetParser.parse`
> (`HomebrewIdentity.swift:79-102`) decomposes `<cellar>/<formula>/<keg-version>/<rel>` by
> components and refuses `.`/`..`. The Caskroom has the same *shape* with a different
> *vocabulary*: `<caskroom>/<token>/<version-dir>/<rel>`. Copying the Cellar grammar verbatim
> would be wrong in three ways: the token is not a formula name (it may be `user/repo/name`); the
> version component is not a Homebrew-stable version (it may be `latest` or comma-multi-part); and
> a cask's staged artifact may be a *directory* (an `.app`), which the formula parser would
> reject. So the cask parser is a **new** primitive that shares the *method* (component-wise
> decomposition, strict descendant, no substring) and not the *grammar*.

**Step 3 — manager metadata for the token.** `brew info --json=v2 --cask <token>` → the
`casks` array of the v2 envelope (verified: the envelope carries both `formulae` and `casks`;
`brew info --json=v2 --cask codex kiro-cli` returns exactly those two casks in one call, exit 0).
Required facts:
- the record's `token` (and `full_token`) must identify the same package we asked about —
  matched against the record's own `token`/`old_tokens` (the manager resolves renames: verified
  `brew info --json=v2 --cask amazon-q` → `token = "kiro-cli"`, `old_tokens = ["amazon-q",
  "codewhisperer"]`);
- `installed` must be non-null (the cask is installed) and must equal the **version-dir**
  component from step 2 — this is what binds the staged directory to the manager's install
  record;
- `pinned`, `pinned_version`, `deprecated`, `disabled`, `auto_updates` are captured as facts
  (they drive *operation* refusals, not ownership);
- `artifacts` is captured for the whole-cask disclosure (§D.5).

**Step 4 — manager listing membership.** `brew list --verbose --cask <token>` → the staged
files of that token (verified shape and the `find` implementation at `cmd/list.rb:200-204`).
Required facts:
- the output must list the selected executable's canonical target `T` **exactly** — the same
  membership primitive as the formula proof's `listConfirmsSelectedPath`
  (`HomebrewOwnershipProbe.swift:342-362`), applied to the Caskroom listing;
- the output must list `.metadata/INSTALL_RECEIPT.json` for that token — the receipt is what
  proves *this manager* installed it. Verified receipt content includes `source.tap`,
  `source.version`, `arch`, `time` and the `uninstall_artifacts` the cask will run;
- the receipt's `source.version` must equal the version-dir component from step 2.

**Step 5 — local identity observations and revalidation.** Observe the manager executable, the
selected entry, the caskroom directory and the receipt file with
`FileIdentityObserver` (`ExecutableIdentity.swift:57-261`) and revalidate them immediately before
returning `.verified`, mirroring `FormulaProof.revalidate()`
(`HomebrewOwnershipProbe.swift:35-52`). Any change → `.unknown(reason)`.

**Ordering.** Steps 1–5 are the same *order* as the formula proof (root → metadata → membership →
revalidate), and the revalidation points sit where the formula proof puts them.

### C.2 Why each step is necessary (no single hint is proof)

| Without | What could wrongly verify |
|---|---|
| step 1 (manager caskroot) | any `/Caskroom/`-looking path anywhere on disk would pass |
| step 2 (component decomposition) | a same-named directory tree not owned by this manager |
| step 3 (manager metadata) | a directory named after a cask that the manager never installed |
| step 4 (manager listing + receipt) | a cask token that exists but is not installed, or is installed under a different version |
| step 5 (revalidation) | a proof that went stale between query and return |

A declaration, a basename, or the substring `Caskroom` alone verifies **nothing**: the token
component is only accepted when the *manager* confirms that token's identity, install record and
staged files.

### C.3 Typed unknown reasons (additive to `InstallationOwnershipReason`)

Existing reasons are untouched. New, cask-specific:

| Reason | Message | When |
|---|---|---|
| `.caskManagerUnavailable` | "Homebrew is not available on the captured PATH." | no live `brew` |
| `.caskMetadataUnavailable` | "Homebrew could not provide metadata for this cask." | `info --cask` failed (exit ≠ 0 / unparsable) |
| `.caskNotInstalled` | "This cask is not installed by Homebrew." | record `installed == null` |
| `.caskIdentityMismatch` | "The staged installation does not belong to the declared cask." | record token ≠ staged token and requested token ∉ `old_tokens` |
| `.caskTargetOutsideCaskroom` | "The selected executable is not inside this cask's staged installation." | component decomposition failed |
| `.caskVersionMismatch` | "The staged cask version does not match Homebrew's install record." | version-dir ≠ receipt/`installed` |
| `.caskArtifactNotFound` | "Homebrew does not list this executable as part of the cask." | `T` ∉ the manager listing |
| `.caskReceiptMissing` | "Homebrew's install receipt for this cask is missing." | no `INSTALL_RECEIPT.json` |
| `.caskLayoutUnsupported` | "This cask installation does not have a supported layout." | e.g. the selected path is an `.app` bundle, not a CLI |
| `.caskAmbiguousOwnership` | "More than one declared cask matches this installation." | two declared cask candidates match |
| `.caskRenamedToken` | "This cask was installed under a previous name." | requested token ∈ record `old_tokens` (informational, still a *verified* ownership of the canonical token) |

The last one is deliberately a **fact**, not a failure: the manager resolves the rename, so
ownership is verified for the canonical token and the rename is disclosed.

### C.4 Routing: how the cask branch is entered

The current router (`InstallationOwnershipVerifier.swift:61-82`) switches on the source string.
M13-A adds a **third branch** with this order:

1. source `npm` **and** an npm candidate declared → npm proof (unchanged).
2. source `brew` **and** a formula candidate declared → formula proof (unchanged).
3. **a homebrewCask candidate declared** → cask proof, regardless of the source string.

Rule 3 is entered because the source heuristic is exactly what fails for casks (F-1). It is safe
because the proof itself is closed: a standalone script install never reaches `.verified`
because step 2 (Caskroom decomposition) fails. The *display* consequence — the app still shows
`Source: standalone` for a cask copy, which is the truth of the heuristic — is stated in the
matrix note in M13-F.

A cask-declaring entry with an npm candidate (`codex`, `claude`) keeps its npm branch first: an
npm-installed copy is still owned by npm, exactly as today.

### C.5 The four cask facts M13 must handle explicitly

1. **`version :latest`** — the cask has no fixed version; its installed version is whatever the
   artifact was at install time. The *manager* decides currency by download SHA
   (`cask/cask.rb:495-497`). M13 reports **unknown** (`.caskVersionIsLatest`), never "up to date",
   and refuses Update (there is no target version to promise). Evidence: 2 157 of the 7 843 casks
   in the signed API payload carry `version == "latest"`.
2. **`auto_updates`** — the vendor app updates itself, so Homebrew deliberately does not report
   it as outdated (`cask/cask.rb:503-508`). M13 reports **unknown**
   (`.caskAutoUpdatesManaged`) and refuses Update. `auto_updates` is read per invocation from the
   manager's own JSON and is never assumed — see F-12: the `agy` cask's value changed upstream
   one day after M11 froze it.
3. **Renamed / old tokens** — `old_tokens` on the record; the manager resolves the old name to
   the canonical token (verified with `amazon-q` → `kiro-cli`). M13 verifies ownership of the
   **canonical** token and discloses the rename (`.caskRenamedToken`).
4. **Multi-part versions** (`"1.5.13,5999302598852608"`, `"6.0,9001"`) — 820 of 7 843 casks in the
   API payload. The version-dir component is **opaque**; it is compared for *equality* with the
   receipt/`installed` string and never parsed.

---

## D. Formula and cask Update / Uninstall operations

### D.1 Lifecycle (identical to M10, re-verified)

`prepare` → reviewable preview → `cancel` releases the owned scratch root and the plan
→ `confirm` re-observes everything and revalidates the exact plan → **one** literal argv
launched under the shared gate → bounded dual-stream output → mandatory reconciliation against
fresh local facts. Exit zero alone is never success (M10 precedent:
`NpmUpdateOperation.swift:410-429`). One mutation at a time via
`OperationExecutionGate.shared` (`OperationModels.swift:261-278`) — the **same** gate npm uses, so
an npm and a brew mutation cannot overlap. No automatic retry. Cancellation before launch is
`.cancelled`; after launch it is `.interrupted`/`.uncertain` with reconciliation.

### D.2 Exact argv

| Operation | argv | Manager evidence |
|---|---|---|
| Formula Update | `["upgrade", "--formula", "<full-name>"]` | `brew upgrade --help`: "If cask or formula are specified, upgrade only the given cask or formula (unless they are pinned…)"; `--formula` forces the named argument to be a formula (`cmd/upgrade.rb:85-89`) |
| Formula Uninstall | `["uninstall", "--formula", "<full-name>"]` | `cmd/uninstall.rb:34-35`; without `--force` only the default keg is removed (`cmd/uninstall.rb:47`, `uninstall.rb:85-91`) |
| Cask Update | `["upgrade", "--cask", "<token>"]` | `cmd/upgrade.rb:161-163`; named cask uses greedy semantics (`cask/upgrade.rb:57-79`) |
| Cask Uninstall | `["uninstall", "--cask", "<token>"]` | `cmd/uninstall.rb:36-37`; runs the cask's uninstall stanza, not zap (`cask/installer.rb:641-667,745-791`) |

`<full-name>` is the **manager-returned** `full_name` (bare name or `owner/tap/name`) from the
ownership proof, never a string we composed. `<token>` is the manager-returned canonical cask
token.

**Forbidden by construction, not by convention.** The argv is built from a closed field list, so
`--all`, `--force`, `--zap`, `--ignore-dependencies`, `--dry-run`, `--greedy` and a second target
cannot be produced. A unit test asserts the forbidden flags cannot appear in any generated argv.
`--dry-run` is excluded on purpose: it is a *read* of what would happen, not the operation.

### D.3 Target-version semantics and invalidation

`brew upgrade` has **no version-selection flag** (F-8); Homebrew resolves the target itself when
it runs. Therefore:

- the preview shows the **observed manager-known latest** (formula: `versions.stable` +
  `revision` as `packageVersion`, `HomebrewUpdateProbe.swift:143-145,669`; cask: the record's
  `version` string, verbatim);
- the preview **additionally states** that Homebrew re-resolves the target at execution time and
  that a version published in between may be installed instead;
- the confirm step re-observes the manager's latest and refuses when it **changed**
  (stale-preview invalidation, the M10 rule), with the message "Homebrew's known version for this
  package changed; a new preview is required.";
- after the run, the reconciliation compares the *installed* version with the *observed* target and
  reports a mismatch as `uncertain`, never as success.

### D.4 Operation environment policy (one place, disclosed)

Built by `HomebrewOperationEnvironment`, applied to every brew mutation, and asserted by tests:

| Variable | Value | Why |
|---|---|---|
| `HOMEBREW_NO_AUTO_UPDATE` | `1` | stops the hidden `brew update` / API refresh Homebrew performs before install/upgrade (`env_config.rb:543-550`; `api.rb:242-250`) — ROADMAP §6 forbids a hidden refresh |
| `HOMEBREW_NO_ANALYTICS` | `1` | privacy; already the M6 probe's rule (`HomebrewUpdateProbe.swift:543-548`) |
| `HOMEBREW_NO_ASK` | `1` | no interactive prompt can ever block a GUI-launched mutation (`env_config.rb:534-537`); the manager's own plan text is still captured in stdout |
| `HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK` | `1` | otherwise `brew upgrade` also upgrades **outdated dependents** (`brew upgrade --help`; `env_config.rb:596-601`) — a second, undisclosed mutation |
| `HOMEBREW_NO_INSTALL_CLEANUP` | `1` | otherwise `brew upgrade` runs `brew cleanup` for the upgraded packages "or, every 30 days, for all packages" (`brew upgrade --help`; `env_config.rb:603-608`) — ROADMAP §6 forbids broad cleanup |
| `HOMEBREW_NO_AUTOREMOVE` | `1` | otherwise `brew uninstall` removes now-unused formula dependents (`cmd/uninstall.rb:168-171`; `env_config.rb:538-542`) |
| `HOMEBREW_CACHE` | `<owned scratch>/brew-cache` | the manager's download cache stays inside the owned scratch and is destroyed with it |
| `HOMEBREW_LOGS` | `<owned scratch>/brew-logs` | manager logs stay inside the owned scratch |
| `HOMEBREW_TEMP` | `<owned scratch>/brew-temp` | build temporaries stay inside the owned scratch |

Everything else in the captured login-shell environment is inherited unchanged (PATH, HOME,
locale, credentials) so the manager behaves exactly as the user would see it.

**Disclosure (effect text, verbatim in the Core constant).** The brew effect text names, in plain
words: that the named package is the only target; that Homebrew will not upgrade dependents, will
not run its periodic cleanup and will not remove now-unused dependencies **for this operation**;
that Homebrew's cache, logs and temporary files are written only inside the operation scratch and
removed with it; that Homebrew's own metadata auto-update is disabled; that **no rollback,
reinstall or atomicity is guaranteed** and an interrupted operation may leave a partial state that
must be re-observed; and — for casks — that Homebrew runs the cask's own uninstall steps, that a
companion application may be removed with it, and that configuration and caches are **not** removed
because the zap step is never used.

### D.5 Whole-cask disclosure (cask Uninstall preview)

The preview must show, read from the manager's own `artifacts` and the install receipt, never
invented:

1. the cask's **full identity** (`token`, `full_token`, `tap`);
2. the **artifact targets** the cask installed — for `codex`: `binary bin/codex` → `/opt/homebrew/bin/codex`;
   for `kiro-cli`: `binary kirocli/bin/kiro-cli` → `/opt/homebrew/bin/kiro-cli`; for
   `antigravity-cli`: `command_wrapper agy` → `/opt/homebrew/bin/agy`;
3. the **uninstall steps** the cask declares — `uninstall` stanza directives (quit / pkgutil /
   launchctl / script / delete) read from the record's `artifacts`, and the receipt's
   `uninstall_artifacts` (verified: the `vorssaint` receipt lists an `uninstall` stanza with
   `quit: com.vorssaint.utils`, an `app` stanza, and a `zap` stanza);
4. the **companion-app consequence** — "Uninstalling this cask removes the application bundle it
   installed, not only the command-line binary", with the app name when the cask declares one;
5. the **zap exclusion** — "Homebrew's zap step, which removes configuration and caches, is not
   used.";
6. the literal argv and the manager prefix.

### D.6 Pin, deprecation, disabled and dependent refusals

| Situation | Manager fact | M13 behaviour |
|---|---|---|
| pinned formula | `info --formula` `pinned: true`; `brew list --pinned` lists it | **refuse before launch**, typed `.packagePinned`; never `brew unpin` (ROADMAP: "Never force, unpin, relink") |
| pinned cask | record `pinned: true` | refuse before launch, typed `.packagePinned` |
| deprecated formula | `info --formula` `deprecated: true` (verified for `gemini-cli` and `cline`) | update permitted, **disclosed** as deprecated in the preview |
| disabled formula/cask | `disabled: true` | refuse; Homebrew itself refuses to upgrade disabled casks (`cask/upgrade.rb:47-51`) |
| formula is a dependency of an installed formula | `brew uninstall` fails by default | **honest failure result**: the manager's message is surfaced, exit status recorded, no `--ignore-dependencies` |
| cask is a dependency of an installed cask | `Cask::Uninstall.check_dependent_casks` (`cmd/uninstall.rb:79-80,95-96`) | same honest failure result |

### D.7 Reconciliation facts (brew-specific)

Formula Update: installed keg version before/after; the old keg directory replaced or left
behind; `Cellar/<formula>/<version>` presence; the linked binary's new target; the PATH winner
before/after; install state before/after.

Formula Uninstall: the formula's cellar rack removed (or, without `--force`, only the default keg —
`uninstall.rb:85-91` prints "X 1.0 2.0 are still installed"); the linked binary released;
dangling-symlink residue reported; ownership re-verified afterwards.

Cask Update: the staged version directory replaced (`<caskroom>/<token>/<version>` before/after);
the receipt replaced; the target binary relinked to the new staged path; the app artifact
replaced; residue reported.

Cask Uninstall: the staged version directory gone; the receipt gone; the linked binary released
(dangling residue reported); the companion app target gone **if** the cask declared one; the
zap-listed configuration and caches **still present** (that is the D-008 guarantee, and it is
asserted in the acceptance scenario).

Observation failure (permission, race, wrong type) is reported as an observation failure, never as
success — the M10 `NpmUninstallDelta` semantics (`OperationModels.swift:387-428`).

### D.8 Timeouts and budgets

| Bound | Value | Note |
|---|---|---|
| per-query (read-only) | 10 s | the existing M6 bound (`HomebrewUpdateProbe.swift:204`), reused unchanged |
| preparation budget | 60 s | same as M10 (`NpmUpdateOperation.swift:46`) |
| confirmation budget | 60 s | same as M10 (`:47`) |
| stage budget (all update probes) | 60 s | unchanged (`UpdateProbeCoordinator.swift:571`) |
| **mutation timeout** | **900 s** | a real brew upgrade downloads and links artifacts; 120 s (M10's value) is not honest for brew. The value is disclosed in the preview and the interruption semantics are the M10 ones (process-group TERM/KILL, `.uncertain`, reconciliation). |

The 900 s figure is a proposal the judge must accept explicitly; it is the only M13 bound that
differs from M10.

---

## E. Mutation gate, promotion and capability matrix

### E.1 Vocabulary extension (D-021, additive on schema 2)

Proposed new `AcceptedOperation` cases (`DetectorMetadata.swift:78-81`):

```
homebrewFormulaUpdate
homebrewFormulaUninstall
homebrewCaskUpdate
homebrewCaskUninstall
```

**Why four, not two (`homebrewUpdate` / `homebrewUninstall`).** An entry may declare both a
formula and a cask candidate (`codex`: npm + cask; `claude`: npm + two casks; `opencode`: npm +
five formulae). With two names, accepting `homebrewUpdate` for an entry would authorise a *cask*
upgrade whenever the user's installed copy happens to be the cask — a grant the owner never made,
and exactly the kind of silent widening D-021 exists to prevent. Four names keep the grant
per (manager kind × operation). The manager kind is also what the matrix cell must name, so the
vocabulary and the matrix agree.

**Additive semantics preserved.** `acceptedOperations` stays an optional additive field on registry
**schema 2** (`DetectorRegistry.swift:215-240` Codable path, `:1076-1108` JSON path, shared
validator `DetectorMetadata.swift:270-295`): absent → `[]`; present `null`, non-array, non-string
element, unknown value or duplicate → **named** errors on **both** decode paths; schema 1/3 and
unknown keys still rejected. The only contract change is the **message text**, which currently
reads "must be one of npmUpdate, npmUninstall" and must become the six-name list; two tests pin
that string (`DetectorRegistryTests.swift:399-404`, `DetectorMetadataTests.swift:337-341`) and
must be updated to the new list.

**Gate position.** Unchanged: cancellation first, then the accepted-operation check, then any
observation, scratch claim or process (the M10 position, `NpmUpdateOperation.swift:61-64`). The
brew prepare seams use the same shape with the matching case.

**AppSupport/App mirror.** The refusal text is read from the Core enum's `.message`, never
retyped (M12 R4 discipline, `WorkflowPresentation.swift:186-238`).

### E.2 Capability-matrix rule extension

Current rule (doc `:18-21`; test `CapabilityMatrixTests.swift:176-205`): `yes` requires the
matching accepted operation **and** an npm candidate **and** verified npm-global ownership; the
cell text is the single exact string `yes: npm (verified npm-global copies only)`.

Proposed rule:

- the cell grammar gains two exact strings:
  `yes: homebrewFormula (verified Homebrew formula copies only)` and
  `yes: homebrewCask (verified Homebrew cask copies only)`;
- a `yes` cell requires: the matching accepted operation **and** a declared candidate of the
  matching manager kind (`homebrewFormula` / `homebrewCask`) — the analogue of today's npm
  candidate rule;
- the `latest-check` cell grammar gains `yes: homebrewCask`, replacing the current blanket
  prohibition (`CapabilityMatrixTests.swift:230-232`) — that prohibition encoded *M6's* state, and
  M13 ships the cask latest-check. The rule becomes "a cask latest-check cell is `yes` iff the row
  declares a cask candidate";
- the cross-row note keeps the truthful statement that cask copies **classify** `standalone`
  (F-1) and adds that a *verified* cask copy is owned by Homebrew — the heuristic and the
  ownership answer are different facts and the matrix must say so;
- the `agy` row is corrected: the live manager reports `auto_updates = null` and the current
  upstream cask has no `auto_updates` stanza (F-12). The row must not keep asserting
  `auto_updates: true`.

**Named contract changes the judge must rule on:** (1) the `AcceptedOperation` vocabulary grows
from two to six names and the validator message text changes; (2) the capability-matrix rule
gains two Update/Uninstall cell strings and a `yes: homebrewCask` latest-check cell; (3) the
`agy` matrix row's `auto_updates` claim is corrected. Nothing else in the matrix grammar moves.

### E.3 Promotion set — OWNER DECISION (OD-M13-1)

Every promotion needs its own controlled acceptance scenario (D-021). Recommendation, with the
reason for each exclusion:

**Tier 1 — recommend promoting in M13 (5 entries).**

| Entry | Operation | Why |
|---|---|---|
| `hermes` (`hermes-agent`) | formula Update + Uninstall | homebrew-core formula; matrix already says "formula adapter M13"; no conflict, no tap needed, not deprecated |
| `aider` (`aider`) | formula Update + Uninstall | homebrew-core; same |
| `goose` (`block-goose-cli`) | formula Update + Uninstall | homebrew-core; the declared name is the full package identity (`block-goose-cli`), never the `goose` basename (do-not-declare table, `docs/catalogue-identities.md:526`) |
| `kiro-cli` (`kiro-cli`) | cask Update + Uninstall | single cask candidate; a `binary`-artifact cask with a CLI; no npm twin, no conflict |
| `agy` (`antigravity-cli`) | cask Update + Uninstall | single cask candidate; the cask explicitly disables the vendor self-updater (`AGY_CLI_DISABLE_AUTO_UPDATE`), so Homebrew-managed update is the vendor's own recommendation; the cask is a `command_wrapper`, exercising the cask wrapper path |

**Tier 2 — recommend deferring (each with a named reason).**

| Entry | Why defer |
|---|---|
| `codex` (cask) | the entry already carries npm acceptance; adding the cask path would give one tool two independent mutation channels. It is a valid future promotion, but it needs its own scenario and it dilutes the first milestone's evidence. Recommend deferring. |
| `claude` (`claude-code`, `claude-code@latest`) | **two** cask candidates for one executable, and they `conflicts_with` each other; the ownership proof must disambiguate by Caskroom token. Valuable but not a first promotion. Defer. |
| `opencode` (formula) | three formula candidates, two sharing the stem `opencode` → the existing formula proof returns `.ambiguousOwnership` (F-13). Promoting it before the proof is tightened would ship a permanently unprovable row. Defer. |
| `omp` (`can1357/tap/omp`) | third-party tap; `brew info --json=v2 --formula can1357/tap/omp` fails here (exit 1, "This command requires the tap can1357/tap"), so tap formulae are provable only when the tap is present. Defer. |

**Never promote (permanent).** `gemini` (`gemini-cli`, formula deprecated 2026-06-18, disabled
2026-12-18 — verified) and `cline` (`cline`, deprecated 2026-05-18). A deprecated formula is not a
sensible update target and the disable dates are imminent; these stay informational with a
truthful reason.

**Owner alternatives to put on the table:** (a) Tier 1 only (recommended); (b) Tier 1 + `codex`
cask; (c) Tier 1 + `codex` cask + `claude` casks, which requires the two-candidate disambiguation
to be proven by a scenario; (d) an empty promotion set (M13 ships the *capability* with no entry
authorised — legitimate, but then the ROADMAP user result "can be checked, updated and uninstalled"
is not demonstrated end to end and the acceptance environment has no product target).

---

## F. Cask latest-check and cache

### F.1 Batch shape

At most **three** commands per uncached batch, mirroring the M6 formula batch
(`HomebrewUpdateProbe.swift:488-531`), and only when at least one cask candidate is eligible:

1. `brew --caskroom` — one manager-wide root query;
2. `brew info --json=v2 --cask <name…>` — one query for all selected casks (verified: multiple
   names in one call, one `casks` array, exit 0);
3. `brew outdated --json=v2 --cask` — one manager-wide outdated query.

`brew outdated --json=v2 --cask` returns `{"formulae": [], "casks": [...]}` — verified — so the
cask records live in the **`casks`** array, whose cask record shape is
`{name: token, installed_versions: [installed], current_version: version, pinned, pinned_version}`
(`cask/cask.rb:529-536`). **The formula parser must not be pointed at it** (the formula parser
reads `root["formulae"]`, `HomebrewUpdateProbe.swift:285-301`); the cask parser reads
`root["casks"]` and keys on the **token**. Formula and cask batches are separate queries because
`brew info --formula … --cask …` conflicts (`cmd/info.rb:92`) and `brew outdated --formula …
--cask …` conflicts (`cmd/outdated.rb:52`).

### F.2 The `auto_updates` / `:latest` / greedy semantics

Plain `brew outdated --cask` **skips** `version :latest` casks and `auto_updates true` casks
(`brew outdated --help`: "--greedy: Also include outdated casks with `version :latest` and
`auto_updates true` casks that would otherwise be skipped"; the implementation is
`cask/cask.rb:491-509`). **Absence from the plain outdated list is therefore not proof of
currency** for those two classes. M13 does not use `--greedy` (it would change the manager's
selection semantics for *other* casks and is a hidden widening); instead it reports **unknown**
for those classes and says why.

### F.3 Tri-state decision table (cask)

Inputs: the info record (`version`, `installed`, `auto_updates`, `pinned`, `deprecated`,
`disabled`, `outdated`) and the outdated list.

| # | Condition | Result | Reason |
|---|---|---|---|
| 1 | record unavailable / `installed == null` | not an installed cask | — (never a status) |
| 2 | `disabled == true` | **unknown** | `.caskDisabled` |
| 3 | `pinned == true` | **unknown** | `.caskPinned` (Homebrew will not upgrade a pinned package — `brew upgrade --help`) |
| 4 | `version == "latest"` | **unknown** | `.caskVersionIsLatest` |
| 5 | `auto_updates == true` | **unknown** | `.caskAutoUpdatesManaged` |
| 6 | `deprecated == true` | allowed, **disclosed** | status computed normally, preview says "deprecated" |
| 7 | manager says outdated (`outdated == true`, or the token appears in the outdated list) | **updateAvailable** (installed → the manager's `version` string, verbatim) | — |
| 8 | `installed == version` and not outdated | **upToDate** | — |
| 9 | installed ≠ version but the manager does not say outdated | **unknown** | `.caskMetadataInconsistent` (never "up to date") |
| 10 | offline / manager failure | **unknown** | `.networkUnavailable` / `.probeFailed` |

**No cask version comparator.** Rule 7 relies on the manager's own verdict, exactly as the M6
formula resolver leans on the manager's `stable` + revision. Rule 8 is string equality on the
manager's own strings. We never order `1.5.13,5999302598852608` against `1.5.14`; we only ask
the manager. This is the honest reading of F-6.

### F.4 Cache design

**Proposal: a separate document, not a schema extension** — `cask-update-metadata-v1.json`,
a sibling of `update-metadata-v1.json` and `npm-update-metadata-v1.json`, following the M10-B
ecosystem-isolation pattern (`NpmUpdateMetadataCache.swift:296-304`).

Rationale: the cask entry's key shape is different (caskroom + token + full token + installed
version, no cellar, no formula stem, no keg version), the version semantics are different (opaque
strings, no ordering), and a shared document would let a formula key and a cask key collide in the
same namespace. The M10-B precedent already accepted "one document per ecosystem"; extending it is
consistent and keeps the formula cache (schema 3, `UpdateMetadataCache.swift:245`) untouched.

- **TTL** 6 h (21 600 s), matching both existing documents.
- **Cap** 1 MiB in both directions.
- **Schema** 1 (new document, new schema).
- **Keys** — every field must match for a hit: `registryID`, `managerEntryPath`, `managerTarget`,
  `managerFingerprint`, `caskroom`, `caskToken`, `caskFullToken`, `caskTap`, `installedVersion`,
  `selectedEntryPath`, `selectedTarget`, `contextFingerprint`.
- **Only successful verified comparisons are persisted.** `unknown` is never cached (M6 rule,
  `UpdateProbeCoordinator.swift:499-519`).
- **Never cross-read**: a cask lookup can never satisfy a formula lookup and vice versa; a test
  asserts this for all three documents.
- **Validation on restore**: the record must be internally consistent (token/full_token/tap
  agree; the selected target decomposes under the recorded caskroom for the recorded token) — the
  cask analogue of `UpdateMetadataEntry.isStructurallyCoherent` (`:153-167`). A corrupt or
  ambiguous record is a **miss**, never a hit.

---

## G. Disposable acceptance environment

### G.1 Route

A **scratch Homebrew prefix** whose `bin/brew` is the real Homebrew code at a pinned revision, plus
a **local synthetic tap** whose formulae and casks are built and consumed entirely inside the
scratch prefix, plus a **loopback artifact server** for the payloads a cask or formula must
download (the M10-C loopback-registry precedent, `Tests/Fixtures/M10C/npm_update_acceptance.py`).

**Never** the personal prefix, the personal Cellar/Caskroom, `/Applications`, a personal
cache/log directory, or a personal installation as a target.

### G.2 How the product is pointed at the scratch prefix (no product change)

`HomebrewManagerResolver.resolve` (`HomebrewIdentity.swift:25-38`) takes the **first live `brew`
on the ordered login-shell PATH**, and `bin/brew:79-96` derives `HOMEBREW_PREFIX` from the brew
file's own location (`bin/brew:117-125` marks the prefix/repository/library as non-overridable).
So the harness runs the product with a synthetic login shell whose PATH begins with the scratch
`bin` and whose `HOME`/`TMPDIR`/`ZDOTDIR` are synthetic. Every manager call then lands in the
scratch prefix — ownership, latest-check and mutations alike — with zero product changes. The
personal prefix is only ever *read* (for the sentinel manifest).

### G.3 What the scratch prefix must be

- the **real** Homebrew code, at a pinned revision (the local checkout is at `456c79a994`,
  `Homebrew 7.0.15-76-g456c79a`), so the acceptance exercises the same `brew` a user runs;
- its own `Cellar`, `Caskroom`, `Library/Taps`, cache, logs and temp — all under the scratch;
- the vendored Ruby the brew code needs. **Feasibility risk, explicitly:** the vendored
  portable-ruby lives at `Library/Homebrew/vendor/portable-ruby` and is **git-ignored**
  (`.gitignore:23`), so a fresh checkout does not contain it, and the system Ruby here is 2.6.10
  while Homebrew 7 requires 4.0 (`utils/ruby.sh:6`, `:91-160`). The harness must therefore
  provide a Ruby 4.0 — by copying the vendored directory from the local install into the scratch
  tree, or by another route the probe proves. If the probe cannot show a working `brew` in the
  scratch prefix, the environment phase is **BLOCKED** and M13-D/E are not dispatched.
- no network dependency for the *metadata* the scenarios need (the synthetic tap supplies it);
  network may be used only by the loopback artifact server, which is local.

### G.4 The synthetic tap

One local tap under the scratch prefix's `Library/Taps`, containing:

**Formulae**
| Name | Purpose |
|---|---|
| `m13-formula-old` → `m13-formula-new` | a version bump proving upgrade-to-known-target |
| `m13-formula-pinned` | pinned variant; `brew upgrade` must refuse it |
| `m13-formula-dependent` | a formula another installed formula depends on; uninstall must be refused by the manager |
| `m13-formula-failing` | an install that fails, proving the failure path |

**Casks**
| Name | Purpose |
|---|---|
| `m13-cask-cli` | a `binary`-artifact cask installing a CLI into the scratch prefix |
| `m13-cask-app` | an `app`-artifact cask whose target is redirected to a scratch app dir, never `/Applications`; also carries an `uninstall` stanza |
| `m13-cask-auto-updates` | an `auto_updates true` cask → the unknown/auto-update branch |
| `m13-cask-latest` | a `version :latest` cask → the unknown/latest branch |
| `m13-cask-zap` | a cask with a `zap` trash list → proves zap is never executed |

### G.5 Fixture harness shape (`Tests/Fixtures/M13/homebrew_acceptance.py`)

Standard library only, secret-free, operator-supplied `--root` that must not pre-exist and is
never a cleanup target. Per scenario it: builds the scratch prefix (or reuses one), builds the
synthetic tap, starts the loopback artifact server (recording its PID; start/stop/join only that
PID), runs the scenario, records raw argv/stdout/stderr/exit/elapsed, and writes a JSON receipt.
Each scenario's harness code is the M10-C/M10-D shape: the harness asserts the **production argv
first**, and only then substitutes the loopback endpoint for the payload URL — the substitution
lives in the *fixture's* cask/formula definition, never in a production switch.

### G.6 Acceptance scenarios (the combined gate's evidence)

| ID | Scenario | Required evidence |
|---|---|---|
| M13-AC01 | ownership, formula | `brew --cellar` + `info --formula` + `list --verbose --formula` observed; the app reports a verified Homebrew-formula owner with the prefix, full name and keg path |
| M13-AC02 | ownership, cask | `brew --caskroom` + `info --cask` + `list --verbose --cask` observed; the app reports a verified Homebrew-cask owner; the Caskroom token appears in the disclosure |
| M13-AC03 | latest-check, formula and cask | `outdated --json=v2 --formula` and `outdated --json=v2 --cask` observed; the tri-state matches §F.3 row by row, including `:latest`, `auto_updates`, deprecated and pinned |
| M13-AC04 | preview / Cancel | preview shows prefix, formula-vs-cask, full identity, literal argv, effect text; Cancel changes **nothing**: SHA-256 manifest of the scratch prefix byte-identical before/after |
| M13-AC05 | formula Update | one `upgrade --formula <full-name>`; the observed target installed; the reconciling facts of §D.7; the personal prefix manifest unchanged |
| M13-AC06 | cask Update | one `upgrade --cask <token>`; the staged version dir and receipt replaced; the target relinked; the whole-cask disclosure was visible before Confirm |
| M13-AC07 | formula Uninstall | one `uninstall --formula <full-name>`; keg removed, binary released, residue reported; **the dependent formula's uninstall refusal is surfaced as an honest failure** |
| M13-AC08 | cask Uninstall | one `uninstall --cask <token>`; the staged dir and receipt gone; the CLI released; the companion app gone; **the zap-listed configuration and caches still present** (D-008 proof); the uninstall stanza's effect observed |
| M13-AC09 | pin / deprecated / disabled | pinned formula and pinned cask both refused **before** any process launch (a counting runner proves zero manager calls) |
| M13-AC10 | manager failure | a non-zero-exit manager is an honest failure, no retry, reconciliation still reported |
| M13-AC11 | interruption / window close | the mutation is interrupted, the outcome is `.interrupted`/`.uncertain`, the state is reconciled, no orphan process |
| M13-AC12 | concurrency | two Confirms → exactly one mutation (the shared gate refuses the other) |
| M13-AC13 | sentinels | the personal prefix, the personal Cellar/Caskroom, `/Applications` and the personal caches are **byte-identical** before and after the whole run (SHA-256 manifests) |
| M13-AC14 | native journey | the ordinary app, driven through Accessibility (M10-D method), prepares → cancels (hashes identical) → prepares → confirms → shows the reconciled result → the post-rescan inventory shows the new state |
| M13-AC15 | CLI parity | `agent-lens scan --check-updates` and `agent-lens verify-installation <id>` agree with the app for the same scratch environment (read-only; D-022 preserved — no CLI mutation verb exists) |
| M13-AC16 | per-promotion scenario | one controlled scenario **per promoted entry** (D-021), each with its own receipts |

### G.7 Feasibility probe — what it must demonstrate

The judge runs a bounded scratch probe before the freeze. The probe must demonstrate, with raw
output:

1. a scratch `bin/brew` at a pinned revision starts, prints its version, and reports a scratch
   `--prefix`, `--cellar` and `--caskroom` (and **not** `/opt/homebrew`);
2. the scratch prefix's `Cellar`, `Caskroom` and `Library/Taps` are inside the scratch;
3. a Ruby 4.0 is available to that brew (the vendored-portable-ruby route works — F/G.3);
4. the synthetic tap is visible to the scratch brew and its formula/cask metadata resolves
   **without network**;
5. a synthetic formula installs, links, upgrades and uninstalls inside the scratch prefix;
6. a synthetic binary cask installs and links a CLI inside the scratch prefix;
7. an app-artifact cask installs into a scratch app dir and **not** into `/Applications`;
8. the loopback artifact server can serve a payload that brew accepts with its sha256;
9. the personal prefix, Cellar, Caskroom, `/Applications` and personal caches are
   **byte-identical** before and after the probe;
10. `brew info --json=v2 --cask <token>` works in the scratch prefix and the `casks` array
    carries the fields the proof needs.

Any failure is a **BLOCKED** verdict for the environment phase, escalated to the judge/owner —
never a workaround that touches the personal prefix, and never a fake.

---

## H. App / AppSupport / CLI integration

### H.1 `ManagementPresentation`

Extend with brew affordances alongside the npm ones (`WorkflowPresentation.swift:186-238`):

- Update: `prepareHomebrewUpdate` when the entry's published status is `updateAvailable` **and**
  the ownership observation is a Homebrew manager **and** the entry accepts the matching
  operation; `unavailable(<Core reason message>)` otherwise;
- Uninstall: `prepareHomebrewUninstall` when the published ownership is a verified Homebrew
  installation **and** the entry accepts the matching operation;
- the npm sentences stay byte-identical; brew sentences are new constants **read from the Core
  reason enums** (M12 R4 discipline);
- `otherLimits` gains the formula/cask limitation sentences, and the existing
  "Homebrew formula update and uninstall are not available in this version." /
  "…cask…" sentences (`WorkflowPresentation.swift:179-182`) are replaced by truthful
  per-entry text — an entry that is *not* promoted must say **why** (not accepted / not
  verifiable / pinned / deprecated), citing the Core reason, not a version claim.

### H.2 Sheets

- **New** `HomebrewUpdateOperationView` / `HomebrewUninstallOperationView`. The npm sheets
  (`UpdateOperationView.swift`, `UninstallOperationView.swift`) are **not** edited — the M10-D
  fixture host compiles and constructs them
  (`Tests/Fixtures/M10D/npm_uninstall_acceptance.py:480-481,499-500,548-551`), so an initializer
  change there is a hard failure.
- The brew sheets follow the **C-1** footer contract exactly: no `.defaultAction` in the preview
  state, Cancel = `.cancelAction` (Escape), the destructive confirm has **no** key equivalent,
  and the result/unavailable states keep Done/Close as `.defaultAction`
  (`UpdateOperationView.swift:66-84` is the pattern).
- Preview content: manager prefix, formula-vs-cask, full package identity, the literal argv, the
  effect text, and — for a cask — the whole-cask disclosure of §D.5.
- Accessibility: every new control gets a label and a hint, and the sheet title announces the
  outcome, following the M12-E/R10 conventions.

### H.3 Tool detail and window

- The **Manage** section currently renders only for npm-declared entries
  (`ToolDetailView.swift:99-102`, `:293-302`); M13-G renders the brew block for brew-declared
  entries, with the same "control offered, and why not" discipline.
- The Update-Status version cell's label is chosen by "is npm?" (`:493-495`); M13-G makes it
  manager-aware ("Latest Known Homebrew Formula Metadata" / "…Cask Metadata").
- `MainWindow.swift:102-150` gains the two brew sheets, bound to preview/preparation/outcome/
  unavailable and never to `selectedEntry`.

### H.4 ViewModel / service

- `InventoryService` gains brew `prepareUpdate` / `executeUpdate` / `prepareUninstall` /
  `executeUninstall` / `cancel…` seams mirroring `:298-517`: a fresh scan identifies the exact
  clicked registry entry and selection before Core is called, and the post-launch reconciliation
  republishes a fresh snapshot.
- `InventoryViewModel` gains the brew pipelines and, critically, extends the **M12 R1**
  invalidation trigger set (`InventoryViewModel.swift:649-711`) so that a pending brew
  preparation is released — with zero mutation — on selection change, scope change, filter
  change, search change, rescan, check, refresh and verify, exactly like the npm preparation; the
  executing-mutation early-return (`:655`) is preserved.
- The ViewModel's `phase`, busy flags and single-pipeline rule stay as they are: one mutation at a
  time across npm **and** brew.

### H.5 CLI (read-only only, D-022)

- `agent-lens scan --check-updates` prints the cask rows (M13-B's provenance line) in the existing
  VERSION / UPDATE STATUS section.
- `agent-lens verify-installation <id>` reaches the cask proof automatically once M13-A routes
  casks (`main.swift:141-151`); the OWNERSHIP VERIFICATION section already prints the manager
  label, so a verified cask prints "manager: Homebrew cask" with the caskroom root.
- **No new command, no mutation syntax.** The dispatch surface stays `scan`,
  `verify-installation`, `debug-env` (`main.swift:61-176`).

---

## I. Risks and open questions

### I.1 Ranked risks

1. **Homebrew side effects beyond the named package (High, safety).** Four switches stand between
   "one package" and "many packages" (§D.4). A missing switch silently upgrades dependents,
   prunes other packages' old versions or removes now-unused dependencies. *Mitigation:* one
   environment builder, a test asserting the exact env, an effect text that names each switch, and
   mandatory BOTH review of D/E.
2. **Cask ownership mis-proof (High, safety).** A path that merely *looks* like a Caskroom tree
   could verify if any step were skippable. *Mitigation:* the five-step proof (§C.1) with manager
   root, manager metadata, manager listing membership, receipt and revalidation; a basename or a
   declaration never suffices; mandatory BOTH review of A.
3. **A cask's whole-cask consequence is understated (High, honesty).** `brew uninstall --cask`
   runs the cask's uninstall stanza and removes a companion app. *Mitigation:* the disclosure is
   generated from the manager's own `artifacts` and the install receipt (§D.5) and the preview
   states it before Confirm; the acceptance scenario asserts the zap-listed files survive.
4. **Scratch-prefix feasibility (High, delivery).** The vendored Ruby 4.0 and the offline metadata
   path are the two known obstacles (§G.3). *Mitigation:* the probe (§G.7) runs **before** the
   freeze; a failed probe is a BLOCKED verdict, not a workaround.
5. **The M11 catalogue is already stale on a M13-critical fact (Med-High).** `agy`'s
   `auto_updates: true` no longer matches the manager or the upstream cask (F-12). *Mitigation:*
   M13-F corrects the row with the dated evidence; the cask latest-check reads the value per
   invocation and never assumes it.
6. **npm regression (Med-High).** The npm vocabulary, sheets, gate position and codex behaviour
   are load-bearing. *Mitigation:* PRESERVE list (§A.3) is enforced per phase; the M10-D fixture
   host must still compile and run; the codex journey is re-run in M13-H.
7. **CI integrity (Med).** Floors could be moved by an implementer. *Mitigation:* floors move only
   at M13-H, only upward, only to orchestrator-measured counts; `ci.yml` is in every phase's
   protected set.
8. **Flash-tier ambiguity (Med).** M13 has more new seams than M12 (four new operation families,
   a second cache document, a new router). *Mitigation:* §C/§D/§F fix every design decision here;
   each phase's brief quotes the relevant rulings verbatim; anything unlisted is a stop, not a
   judgement call.
9. **Promotion scope creep (Med).** Promoting `codex`/`claude`/`opencode`/`omp` would ship rows
   whose proof is unproven. *Mitigation:* the promotion set is an OD with a per-entry reason, and
   each promotion needs its own scenario (§E.3).
10. **Cask version truthfulness (Med).** Cask versions are opaque; a comparator would be a guess.
    *Mitigation:* the manager's verdict is the only oracle (§F.3); `:latest` and `auto_updates`
    are unknown, never "up to date".
11. **Ownership ambiguity for `opencode` (Med, pre-existing).** Two declared candidates share the
    stem `opencode` → the existing formula proof returns `.ambiguousOwnership` (F-13). *Mitigation:*
    `opencode` is not promoted; M13 does not change the formula proof.
12. **App-layer truthfulness (Med-Low).** The npm-shaped gating in `WorkflowPresentation` and
    `ToolDetailView` could mislabel brew entries. *Mitigation:* manager-aware predicates with
    AppSupport tests per case; the codex block is asserted byte-identical.

### I.2 Owner decisions

| ID | Decision | Recommendation |
|---|---|---|
| **OD-M13-1** | The M13 promotion set (§E.3) | **Tier 1 only** — `hermes`, `aider`, `goose` (formula Update+Uninstall) and `kiro-cli`, `agy` (cask Update+Uninstall). Each gets its own controlled scenario. Defer `codex` (cask), `claude` (two conflicting casks), `opencode` (stem ambiguity), `omp` (tap dependency). Exclude `gemini`/`cline` permanently (deprecated). |
| **OD-M13-2** | Correct the `agy` matrix row (`auto_updates: true` → not set upstream since 2026-11-13) | **Correct it**, with the dated evidence in the row. Keeping the stale claim would make the cask latest-check's auto-update branch untestable against a real catalogue entry. |
| **OD-M13-3** | The Homebrew mutation timeout (900 s vs M10's 120 s) | **Accept 900 s** for brew and disclose it. A 120 s bound would convert ordinary bottle downloads into false "interrupted" outcomes. The npm timeout stays 120 s. |
| **OD-M13-4** | Whether M13 may ship a cask latest-check at all (it revises D-019's "cask latest-check not shipped" and the matrix's blanket cask-latest-check prohibition) | **Ship it**, in its own document, with the manager's verdict as the only oracle. The alternative — no cask latest-check — leaves "verified … cask installations can be checked" unmet and makes the cask Update operation unpresentable (no target version). |
| **OD-M13-5** | Whether the app should keep showing `Source: standalone` for a cask copy (the source heuristic) while the ownership view says "Homebrew cask" | **Keep both, and explain the difference** (the matrix note states it). Changing `classifySource` would re-label every cask copy, alter the fixture vocabulary and the M11 binding rule — a much larger change for no accuracy gain. |
| **OD-M13-6** | Whether M13 may use `brew list --pinned` (a read-only query outside the M6 three-query shape) | **Do not need it**: the info record already carries `pinned`/`pinned_version`. If the judge wants an independent cross-check, add it as an *optional* fourth query in the cask proof only, never in the M6 formula batch. |

### I.3 Things I could not resolve

1. **Whether the scratch prefix can be made to work offline** (the vendored Ruby 4.0 and the
   metadata path). This is the judge's probe (§G.7); I did not build a scratch prefix, because
   building one mutates the filesystem outside the repository and the brief limits me to read-only
   Homebrew queries.
2. **The exact runtime exit codes and stdout of `brew upgrade --cask <token>` for a *pinned* cask
   and for a `:latest` cask.** The source path for casks (`cask/upgrade.rb:57-79`) is clear, but I
   could not observe it without a mutating command. M13 refuses both cases *before* launch, so
   the observable difference is nil — but the acceptance scenario should still record the manager's
   own refusal text for the pinned case.
3. **Whether `brew uninstall --cask` leaves the *staged* directory behind when the cask has other
   versions.** `cask/installer.rb:662-663` purges the caskroom path only under `force?`; the
   version directory is removed by `purge_versioned_files`. The exact residue shape is an
   observation for the acceptance scenario, not a design input.
4. **Whether `brew upgrade` for a formula with several installed versions upgrades the *linked*
   one or all.** `cmd/upgrade.rb:429-437` splits `not_outdated` and the installer set; the
   reconciliation in §D.7 reports whatever the manager does, but the exact selection rule is a
   runtime observation.

---

## J. Explicit non-goals (binding)

- No uv/pip (M14), Cargo (M15), cached launch/menu bar/opt-in checks (M16), bundled CLI (M17),
  release/signing/notarization/publication (M18–M19).
- **No CLI mutation syntax** (D-022): the dispatch surface stays `scan`, `verify-installation`,
  `debug-env`.
- No `brew update`; no `brew install`; no `brew cleanup`; no `brew autoremove`; no `brew pin` /
  `unpin`; no `brew tap` / `untap`; no `brew reinstall`; no `brew migrate`; no `brew link` /
  `unlink`.
- No `--force`, `--zap`, `--ignore-dependencies`, `--all`, `--dry-run`, `--greedy` on any
  operation argv.
- No formula or cask **install** operation in M13 — only Update and Uninstall of an already
  verified installation.
- No personal installation as an acceptance target; no mutation of the personal prefix, Cellar,
  Caskroom, `/Applications` or personal caches.
- No new dependencies; no `Package.swift` change; no CI floor change before the combined gate.
- No weakening of the accepted npm/codex behaviour, the M12 R1 invalidation contract, the C-1
  footer contract, the D-021 fail-closed gate, or the D-007/D-019 truthfulness rules.
- No public contribution invitation; no release.

---

## Appendix — citation index

**Product code (base `9b37a33`)**

- `Sources/AgentLensCore/Ownership/HomebrewOwnershipProbe.swift:3-7,35-52,62,69,101-105,124,131,140,170,177,186,205-207,227,274-294,298-311,326-337,342-362`
- `Sources/AgentLensCore/Ownership/InstallationOwnership.swift:61-94,96-161`
- `Sources/AgentLensCore/Ownership/InstallationOwnershipVerifier.swift:12-112,61-82,114-164,190-203`
- `Sources/AgentLensCore/Updates/HomebrewIdentity.swift:21-38,52-67,76-102`
- `Sources/AgentLensCore/Updates/HomebrewUpdateProbe.swift:194-216,226-257,259-281,285-301,364-370,374-377,383-400,404-408,442-464,466-486,488-531,543-548,552-692,704-715`
- `Sources/AgentLensCore/Updates/UpdateMetadataCache.swift:21-50,96-167,244-249,251-335`
- `Sources/AgentLensCore/Updates/NpmUpdateMetadataCache.swift:285-304`
- `Sources/AgentLensCore/Updates/UpdateProbeCoordinator.swift:187-330,334-360,538-560,565-627,632-684,695-716`
- `Sources/AgentLensCore/Updates/VersionStatus.swift:5-77`
- `Sources/AgentLensCore/Updates/UpdateScanRenderer.swift:12-98,101-127`
- `Sources/AgentLensCore/Updates/ProcessUpdateCommandRunner.swift:11-52`
- `Sources/AgentLensCore/Operations/OperationModels.swift:20-22,26-51,54-94,104-140,143-167,170-212,250-258,261-278,284-314,317-339,349-383,387-428,431-472`
- `Sources/AgentLensCore/Operations/NpmUpdateOperation.swift:13-36,46-48,52-190,199-453,457-534`
- `Sources/AgentLensCore/Operations/NpmUninstallOperation.swift:14-38,42-175,177-180,182-…`
- `Sources/AgentLensCore/Operations/OperationProcessRunner.swift:11-85`
- `Sources/AgentLensCore/Detection/DetectorMetadata.swift:44-58,61-73,78-81,84-159,262-317`
- `Sources/AgentLensCore/Detection/DetectorRegistry.swift:44-53,68-128,130-142,215-240,270-284,672-683,854-881,1076-1108`
- `Sources/AgentLensCore/Detection/ToolDetector.swift:184-191`
- `Sources/AgentLensCore/Process/ExecutableIdentity.swift:57-95,98-126,150-181,265-282`
- `Sources/AgentLensAppSupport/WorkflowPresentation.swift:152-238`
- `Sources/AgentLensAppSupport/InventoryService.swift:294-517`
- `Sources/AgentLensAppSupport/InventoryViewModel.swift:282-336,338-401,403-443,445-489,490-554,556-601,602-646,648-711`
- `Sources/AgentLensAppSupport/InventorySnapshot.swift:19-70,73-117`
- `Sources/AgentLensApp/ToolDetailView.swift:71-102,280-311,468-557,561-655`
- `Sources/AgentLensApp/UpdateOperationView.swift:7-35,37-135`
- `Sources/AgentLensApp/UninstallOperationView.swift`
- `Sources/AgentLensApp/OwnershipVerificationView.swift:11-37,100-224`
- `Sources/AgentLensApp/MainWindow.swift:45-62,102-150`
- `Sources/agent-lens/main.swift:14-59,61-113,114-159,160-176`
- `docs/capability-matrix.md:16-21,26-41,43-53`
- `docs/catalogue-identities.md:493,504-505,516-536,561-583`
- `Tests/AgentLensCoreTests/CapabilityMatrixTests.swift:143,157-174,176-205,207-234,404-444`
- `Tests/AgentLensCoreTests/DetectorMetadataTests.swift:337-341`
- `Tests/AgentLensCoreTests/DetectorRegistryTests.swift:399-404`
- `Tests/Fixtures/M10D/npm_uninstall_acceptance.py:477-502,545-551`
- `.github/workflows/ci.yml:145-178,180-209`

**Manager facts (read-only, `HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1`)**

- `brew --version` → `Homebrew 7.0.15-76-g456c79a`; `brew --prefix` → `/opt/homebrew`;
  `brew --cellar` → `/opt/homebrew/Cellar`; `brew --caskroom` → `/opt/homebrew/Caskroom`;
  `brew --caskroom codex` → `/opt/homebrew/Caskroom/codex`;
  `brew --caskroom codex kiro-cli` → one line per cask.
- `brew upgrade --help` → the dependents-check and cleanup paragraphs quoted in §0/§D.4.
- `brew uninstall --help` → `--force`, `--zap`, `--ignore-dependencies`, `--formula/--cask`.
- `brew outdated --help` → `--greedy`, `--greedy-latest`, `--greedy-auto-updates`.
- `brew info --json=v2 --cask codex|claude-code|claude-code@latest|kiro-cli|antigravity-cli` →
  envelope `{formulae, casks}`; cask fields as in §C.1 step 3; `antigravity-cli` version
  `1.5.13,5999302598852608`, `command_wrapper` artifact, `auto_updates: null`.
- `brew info --json=v2 --cask vorssaint|homebrew-app` → `installed` `3.4.3` / `0.6.0`,
  `installed_time`, `auto_updates` `true` / `null`, `pinned` false.
- `brew info --json=v2 --cask amazon-q` → resolves to `kiro-cli`, `old_tokens`
  `["amazon-q","codewhisperer"]`.
- `brew info --json=v2 --cask no-such-cask-xyz` → exit 1, empty stdout.
- `brew info --json=v2 --formula hermes-agent|aider|block-goose-cli|opencode|gemini-cli|cline` →
  `full_name`, `tap`, `versions.stable`, `revision`, `installed`, `pinned`, `deprecated`,
  `disabled`; `gemini-cli` deprecated 2026-06-18 / disabled 2026-12-18; `cline` deprecated
  2026-05-18.
- `brew info --json=v2 --formula can1357/tap/omp` → exit 1, "This command requires the tap
  can1357/tap".
- `brew list --verbose --cask homebrew-app|vorssaint` → the four Caskroom paths quoted in §C.1.
- `brew list --verbose --cask codex` → exit 1, "Error: Cask 'codex' is not installed."
- `brew list --cask` → `homebrew-app`, `vorssaint`; `brew list --cask --versions` →
  `homebrew-app 0.6.0`, `vorssaint 3.4.3`.
- `brew list --pinned` → empty, exit 0.
- `brew outdated --json=v2` → envelope `{formulae, casks}`, 27 formulae, 0 casks; formula record
  `{name: full_name, installed_versions, current_version, pinned, pinned_version}`;
  `brew outdated --json=v2 --cask` → `{formulae: [], casks: []}`.
- `brew info --json=v2 --cask` with `HOMEBREW_CACHE=<empty dir>` → downloads the API JSON
  ("==> Downloading Homebrew API data"), exit 0 — i.e. the API cache is a *download*, not a
  guaranteed local read.
- `~/Library/Caches/Homebrew/api/internal/packages.arm64_golden_gate.jws.json` (signed payload) →
  `auto_updates` null for `antigravity-cli`, `codex`, `kiro-cli`; true for `iterm2`,
  `visual-studio-code`, `docker`, `google-chrome`, `vorssaint`; `version == "latest"` for 2 157 of
  7 843 casks; 820 casks with comma-multi-part versions; `installed` null for every cask in the
  payload (the installed facts are local, from the receipt).
- `/opt/homebrew/Library/Homebrew/` (read-only source): `bin/brew:49-56,79-96,117-125,162`;
  `startup/config.rb:13-70`; `env_config.rb:236-242,514-520,534-550,568-571,596-608,748-755`;
  `cask/cask.rb:276-300,354-363,458-460,473-509,523-542,614-660`;
  `cask/caskroom.rb:14-19,46-69`; `cask/upgrade.rb:40-80`; `cask/installer.rb:281-287,641-667,745-811`;
  `cask/uninstall.rb:27-58,61-73`; `cask/artifact/moved.rb:149-171,200-253`;
  `cask/artifact/symlinked.rb:108-170`; `cask/artifact/command_wrapper.rb:53-101`;
  `cask/artifact/uninstall.rb:9-40`; `cask/artifact/zap.rb:9-25`;
  `cask/artifact/abstract_uninstall.rb:23-41,64-91`;
  `cmd/upgrade.rb:85-89,161-172,214-227,249-250,429-437,442-452,484-486,875-918`;
  `cmd/uninstall.rb:19-42,46-48,79-96,140-174`; `cmd/info.rb:85-98`;
  `cmd/outdated.rb:22-55,63-81,186-225`; `cmd/list.rb:176-209`;
  `uninstall.rb:25-92,158-174`; `api.rb:242-256`; `utils/ruby.sh:6,91-160`;
  `.gitignore:23` (vendored portable-ruby is ignored).
- Upstream cask sources (read-only fetch): `homebrew-cask` `Casks/a/antigravity-cli.rb` at
  revision `60c151f6` (has `auto_updates true`) and at HEAD (no `auto_updates`, uses
  `command_wrapper` + `AGY_CLI_DISABLE_AUTO_UPDATE`); `Casks/c/claude-code.rb` (`binary "claude"`,
  `conflicts_with cask: "claude-code@latest"`); `Casks/c/codex.rb` (`binary "bin/codex"`).
