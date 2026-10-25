# M9-B — explicit read-only installation ownership verification

Status: authorized implementation phase of M9, revision 1. M9-A was independently accepted before this dispatch. This brief is not acceptance evidence. Do not implement M9-C or any package mutation.

## Baseline, route and evidence

- Branch `milestone/m9-verified-inventory`; HEAD `a405b56183ad0233f286f4d93b027ba7d21c2a01` plus accepted uncommitted M9-A candidate manifest `59402e1afdc8b7ccb2af5d3c76ae251dab6f55a05ab81de0d976631385e37160`.
- Accepted A source copies: `R/accepted-a`; current full baseline hashes: `R/evidence/accepted-a-baseline-sha256.json`. Parent independently passed 208 Core + 63 AppSupport tests, fresh app build, 9 packaging tests, production query smoke and actual native UI. See parent `walkthroughs/M9-verified-installations.md` for evidence if necessary, not the whole roadmap.
- R is `/Users/corvette/.hermes/cache/scratch/agent-lens-m9-20261022-382vfoyi`. Worker output: `R/worker-b`, invocation-local TMPDIR `R/tmp`. Use fresh child build roots; leave repository `.build` and other pre-existing generated state in place.
- Sole worker: DeepSeek V4.1 Flash Free through OpenCode `opencode/deepseek-v4.1-flash-free#max`, build agent; no other model/provider/CLI/subagents. Record actual CLI version, because host inventory now observes OpenCode 2.1.3 rather than the original 2.0.32. Do not upgrade or reconfigure anything.
- No stage, commit, branch switch, reset, clean, merge, push, publication, tooling install or credential access. Parent owns acceptance/status and fixes return to this worker.

## User-visible outcome

A user can explicitly verify the selected installed executable's npm-global or Homebrew-formula ownership, see the verified manager/package/root identities or a truthful reason it is unknown, and obtain the same facts from a new CLI subcommand. Local scanning remains local and does not implicitly query managers.

No install, update, uninstall, deletion, relink, pin, sudo, manager refresh, registry/latest-version lookup, new detector, cask ownership implementation, uv/pip/Cargo support, persistence/cache, background scheduling or M9-C version observation work. Read-only verification is not permission to modify an installation.

## Read set and file authority

Read the accepted metadata types/registry, `InventorySnapshot`, `InventoryService`, `InventoryViewModel`, `SessionEnvironmentProvider`, MainWindow/ToolDetail/ToolList, CLI main/usage, existing `HomebrewManagerResolver`, `HomebrewTargetParser`, bounded runner and `UpdateCommandRunner`/`ProcessUpdateCommandRunner`. Use existing resolved-environment, generation, off-main and process-bound patterns. Research packet: `R/evidence/ownership-research.md` and recorded read-only manager probes.

Allowed production changes:

- Add concrete runtime files under `Sources/AgentLensCore/Ownership/`: `InstallationOwnership.swift`, `InstallationOwnershipVerifier.swift`, `InstallationOwnershipRenderer.swift`; split actual npm/Homebrew implementations into `NpmOwnershipProbe.swift`/`HomebrewOwnershipProbe.swift` and a shared internal `ExecutableIdentity.swift` only if this keeps real policy local. No plugin/protocol framework or unused adapter.
- Modify `Sources/AgentLensCore/AgentLensCore.swift` only to document the new subcommand in usage; do not clean up historical skeleton types.
- Modify `Sources/agent-lens/main.swift` for the bounded new command, retaining all existing scan/debug/no-argument/invalid-form behavior.
- Modify `Sources/AgentLensCore/Detection/DetectorMetadataRenderer.swift` only if needed to distinguish declared candidates from separately verified ownership; do not present the same matched package as simultaneously verified and explicitly unverified. Do not change registry schema, candidates or version-query behavior.
- Modify `Sources/AgentLensAppSupport/InventorySnapshot.swift`, `InventoryService.swift`, `InventoryViewModel.swift` for typed ownership result and the explicit action/lifetime only.
- Modify `Sources/AgentLensApp/MainWindow.swift`, `ToolDetailView.swift`, `ToolListView.swift` for ownership UI, busy/cancel feedback and exhaustive phase handling. Add `Sources/AgentLensApp/OwnershipVerificationView.swift` if it keeps the details rendering small and stateless.
- Add `Tests/AgentLensCoreTests/InstallationOwnershipTests.swift`, `Tests/AgentLensAppSupportTests/OwnershipVerificationTests.swift`. Modify existing Core/AppSupport tests only for directly affected contracts/callers and meaningful behavioral regressions. CLI integration scenarios may extend `UpdateCLIIntegrationTests.swift`; preserve existing cache isolation and closed-PATH safeguards.
- Add `walkthroughs/M9-B-implementation.md`: worker report/current usage and explicit limits, not independent acceptance.

DO NOT TOUCH all other production/packaging/resource files, `Package.swift`, update adapters/cache/environment resolver, path scanner/query behavior, existing registry JSON/schema, historical docs/briefs/walkthroughs, root docs/status/decisions, real tool installations/caches/configuration or system preferences. Stop with the precise additional file/reason before any needed boundary change. A noninteractive run is NOT permission to cross the boundary.

Run language-server references before changing exported symbols when available. Parent found 25 InventoryEntry references across app, AppSupport and tests; Phase is also switched on in ToolListView and model cancellation logic despite a partial LSP reference list. UsageMessage references include CLI and integration tests. Read all affected callsites; do not assume a cold/partial index is exhaustive.

## Fixed interfaces and invariants

### Core

Deliver concrete `InstallationOwnershipResult`, a typed verified identity and neutral reason enum, plus:

```text
InstallationOwnershipVerifier.verify(
    definition: DetectorDefinition,
    diagnostic: ToolPathDiagnostic,
    environment: ShellEnvironment,
    runner: UpdateCommandRunner,
    currentDirectory: String,
    now: @Sendable () -> Date
) async -> InstallationOwnershipResult
```

The result carries registry ID, observed selected entry/target (where available), observation time and typed verified/unknown outcome. A verified identity carries actual package manager/name, manager entry/canonical target/fingerprint, manager root (npm prefix or Homebrew Cellar), installation root (package root or selected keg) and selection identity. Only evidence from this invocation can produce verified status. It is a read-only observation, not a durable authorization token. No raw environment is returned/logged/persisted.

Winner and off-PATH selection are eligible; inconsistent/notInstalled/missing paths are typed neutral outcomes with zero manager calls. Standalone/unsupported/cask/ambiguous ownership stays unknown with explanation, not verified standalone or fabricated package identity. A heuristic source can help select an adapter, never positively establish ownership. Work from the diagnostic selection, not detectedTool's possibly-relative path text or display name.

Use a shared internal executable-identity observation for both real adapters: canonical target and live-regular/executable checks, stat identity including device/inode/mode/size and modification/change times. Match manager/selected entry and target before queries, between needed steps, after local proof reads and immediately before publication. Retargeting, replacement, disappearance or identity/proof-file change during verification returns unknown. Do not invent an identity digest when stat fails. Preserve the selected entry separately from its target.

### Process/lifecycle

Use the existing `UpdateCommandRunner` seam and `ProcessUpdateCommandRunner`, executable + argv, no shell command interpolation, `which`, inherited PATH or hardcoded manager prefix. Resolve the first live npm/brew in ordered captured PATH with existing relative/empty-root semantics. Use `HomebrewManagerResolver`/`HomebrewTargetParser` for brew; do not reimplement their conventions.

Commands are sequential and bounded by 10 seconds/output cap per command. Max npm 2 queries; max formula 3. Zero eligible candidates or unsupported installation produces zero unnecessary queries. Check cancellation between steps and before publishing; await any bounded in-flight command cleanup rather than orphaning it. No HTTP/network registry client, brew outdated, brew update, npm install, or modifying command. Overlay only `HOMEBREW_NO_AUTO_UPDATE=1` and `HOMEBREW_NO_ANALYTICS=1` for brew diagnostics, as in the existing adapter; preserve captured environment otherwise. No raw environment capture in logs.

### npm proof

1. Resolve/snapshot npm; run `npm prefix --global` and `npm root --global` under the captured environment. Parse exactly one absolute NUL-free path line (optional terminal newline/CRLF); do not trim significant path spaces. Relative/multiline/malformed output is unknown. Bind canonical root to the expected Unix global layout `<prefix>/lib/node_modules` by components, not a substring. An independently changed prefix/root is not interchangeable.
2. For declared npm candidates only, inspect `<global root>/<package>/package.json` as a bounded regular-file read, maximum 1 MiB. Do not read arbitrary config/credentials/npmrc. Reject symlink escapes, oversized/invalid JSON and ambiguous matches without allocating the whole oversized file. The exact manifest `name` must match the candidate. `bin` must bind `definition.executableName` to the selected canonical target. Support object maps and documented string shorthand (basename of unscoped/scoped package is the command). Normalize relative bin paths, reject absolute/traversal escape, and ensure resolved bin stays in the canonical package root.
3. Require the manager's `<prefix>/bin/<executable>` entry to resolve to the same target. A selected PATH alias outside the prefix may still be owned if it points to this proven managed executable; record it separately. A same-content copied executable outside the package or another prefix is not owned by this manager. Linked packages escaping the global package root remain unknown in this phase.
4. Revalidate manager, selection, prefix/root and manifest/bin identity before returning the one matching package. Do not trust source `npm`, a node_modules substring, or the declaration alone. Preserve unknown if the current manager belongs to a different Node/npm prefix; no searching arbitrary manager installations or fallback to an unverified prefix.

### Homebrew formula proof

1. Resolve/snapshot brew via the existing resolver. Run `brew --cellar`; parse a single absolute path and use `HomebrewTargetParser` to identify the selected keg under that exact Cellar. Require a declared homebrewFormula candidate matching the selected formula stem; do not infer a package from the executable name. Homebrew casks remain explicitly unsupported here.
2. Query the exact declared full formula identity using `brew info --json=v2 --formula <full-name>`. **Do not add `--installed`: real Homebrew was measured ignoring the supplied name and dumping all installed formulae with that flag.** Read ownership identity/installed versions, not latest-version status: verify full_name/name consistency, unique record and selected keg version in `installed`. Ownership must not depend on semver support, current upstream `stable` or update availability. Malformed/conflicting matches cannot lend identity to another record.
3. Run `brew list --verbose --formula <verified-full-name>` and require the selected canonical executable in the returned file paths, with matching current keg identity. Exact paths/components only; a path prefix collision is not a match. If an older selected keg is not confirmed by this manager list, return a specific neutral limitation rather than borrowing the current keg's proof or calling it absent.
4. Revalidate manager, selected executable and selected installation-root identity around the proof. Store Cellar and selected keg as distinct roots. No metadata cache reads/writes and no modifying manager operation.

Primary sources: https://docs.npmjs.com/cli/v11/commands/npm-prefix/ , https://docs.npmjs.com/cli/v11/commands/npm-root/ , https://docs.npmjs.com/cli/v11/configuring-npm/package-json/#bin , https://docs.brew.sh/Manpage . Parent read-only probes are real npm 10.9.8 and Homebrew 7.0.10; all persistent writes/network were denied by the research sandbox. Do not copy that blanket sandbox into the product: it interferes with brew shell temp/null operations. Existing test cache denial remains mandatory.

## App integration

- Add `InventoryEntry.ownership: InstallationOwnershipResult?`; nil means not verified. Migrate copy/rebuild callsites deliberately. Fresh local snapshots/rescan clear previous proof; failed rescans must also clear old verified ownership on retained data. Check/Refresh already publish fresh local facts and must not preserve stale proof through that scan. Applying update outcomes to the same unchanged snapshot must not accidentally drop a current ownership fact.
- Add `InventoryService.verifyingOwnership(of entry: InventoryEntry) async -> InstallationOwnershipResult`, passing the session environment, existing runner, clock and fixed currentDirectory into Core; Core process work stays off the main executor. Reuse the existing command-runner injection, not a second fake production path.
- Add `InventoryViewModel.verifySelectedInstallation() async` as the only app entry point. Reuse its activePipeline/generation ownership; introduce a truthful verifying phase. Existing actions coalesce while one owns the slot. Snapshot, selection ID and selected entry/target must still match before publication. Selection changes during verification cancel/discard that verification, not attach it to another tool. Do not change existing all-tool update-selection behavior when not verifying. Cancellation/window closure waits for bounded in-flight cleanup; no stale publish, misleading failure or permanently busy state.
- Details offer native `Verify Installation` near ownership status with accessible name/help identifying the current tool. No absent/inconsistent path can trigger queries. Explicit verification of standalone/no-candidate tools can show a neutral reason without querying managers. Busy state and Cancel say Verifying/Cancelling as appropriate, not Checking Updates.
- Verified details show manager executable/target, actual package, npm prefix/package root or Cellar/keg, observation time and a read-only notice. Unknown displays a neutral reason. Existing Source remains a heuristic; declared candidates remain declarations. Do not enable Update/Uninstall or imply future management is already safe/available.
- Preserve native selection, search, local-only launch/rescan, Copy/Reveal eligibility/identity/feedback and current update status. Wrap long roots/package names in a 760-point window. Use existing explicit State backing pattern where needed; no toolchain/package fix.

## CLI contract

Add exactly `agent-lens verify-installation <registry-id>` (singular). Load the same validated registry, resolve shell environment once, scan only the named definition, render its local/path/declared facts then an `OWNERSHIP VERIFICATION` section from the typed result. Do not invoke update checking/cache. Unknown is a diagnostic result with neutral reason and exit 0; invalid syntax/unknown registry ID/registry load failure exits 1 with stderr, without manager effects. No arguments retain usage/exit 0. Existing scan flags remain mutually exclusive and unchanged; do not add scan --verify or modifying commands. Update usage for discoverability, not brittle wording tests.

## Acceptance criteria

| ID | Scenario | Expected observable result |
|---|---|---|
| M9-B-AC01 | Positive scratch npm prefix, manifest/bin object and string forms; selected same-target alias | Correct package/prefix/root/manager/selected identities; declarations alone cannot produce verified status |
| M9-B-AC02 | Decoy node_modules path, wrong manager prefix/root, wrong manifest name/bin, path traversal/symlink escape, oversized/malformed/changed proof, duplicate matches | Specific neutral unknown; no borrowing another package's ownership or unsafe filesystem read |
| M9-B-AC03 | Formula fixture manager with Cellar, exact full-name installed record and file list; malformed/duplicate/full-name mismatch/wrong or unlisted keg | Verified only for exact supported proof; no stable-version comparison dependency; cask/old-unconfirmed/other Cellar stays unknown |
| M9-B-AC04 | Runner gate changes selected symlink/manager/manifest/root between phases; cancel before/during query | Identity change or cancellation never publishes verified, next query suppressed where possible, in-flight cleanup awaited; bounded commands/outputs |
| M9-B-AC05 | Existing launch/plain scan/offline/rescan/update modes; new CLI valid/invalid/missing/unknown-ID forms | No new manager/cache effects except explicit verification; old CLI gates still pass; unsupported verification is neutral; invalid forms side-effect-free |
| M9-B-AC06 | App launch → select Codex → Verify; select standalone tool; selection switch/rescan/failed rescan/cancel while controlled query pending | Correct current result, no cross-tool or stale ownership, current query doesn't freeze main actor, correct busy/cancel state. Core/AppSupport tests plus parent actual native observation |
| M9-B-AC07 | Real manager runtime, not only injected output | Verify the existing npm Codex read-only or a safe isolated npm prefix with real npm; exercise real brew --cellar/named info/list plumbing against test-owned/strict read-only observation, label real versus synthetic proof explicitly |
| M9-B-AC08 | Full Swift, fresh app builder, packaging, protected hashes | All pass; no protected/source/package/cache drift; current three tools and path actions intact |

Permanent tests cover actual invariants and transitions; no source-text tests, label/default pinning, model property echoes or mocked forwarding assertions. Keep behavioral RED/GREEN evidence for ownership mistakes and stale-publication regressions. Isolate every fixture under R; never mutate global environment in parallel tests. Do not disable, loosen or skip meaningful existing checks.

## Exact gates and safety envelope

Use `R/worker-b`. Capture argv/stdout/stderr/exit/duration, not environment dumps. Run targeted regressions as needed, then one final full gate/build/packaging after implementation; do not repeatedly build unchanged snapshots. Parent will independently run final gates.

```sh
R=/Users/corvette/.hermes/cache/scratch/agent-lens-m9-20261022-382vfoyi
mkdir -p "$R/worker-b"
env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS \
  TMPDIR="$R/tmp" swift test --scratch-path "$R/worker-b/full-suite"
TMPDIR="$R/tmp" python3 scripts/build-dev-app.py \
  --scratch-root "$R/worker-b/dev-app" --configuration debug
TMPDIR="$R/tmp" python3 Tests/Packaging/test_dev_app_bundle.py \
  --app "$R/worker-b/dev-app/AgentLensApp-debug.app"
```

All must exit 0. Only for the actual known macro-discovery failure, use the documented explicit TestingMacros library flags from M9-A in a separate fresh root. No toolchain/package change or silent retry loop.

For CLI fixtures reuse closed synthetic shell PATH and sandbox denial of the real Agent Lens cache from existing integration tests. Do not fall back to live extra roots in missing-tool fixtures. Explicit live npm/brew verification is read-only and must never run modifying commands or dump credentials/config. Disposable shell scripts/manifests and processes stay under R. Do not move `.build` or real user files to make tests pass. Native injected hosts, if needed, stay outside the repo, reuse unchanged product source and are labeled separately from the actual entry app; no permanent product fixture mode.

## Handoff and stop rules

Stop BEFORE an allow-list/system/dependency/tooling change, missing isolation, ambiguous evidence or unexpected user-source changes; report exact facts. No silent noninteractive assumptions. Freeze edits on handoff.

Return a written `<structured_output_contract>` report: files/behavior, every AC ID with exact raw evidence path/outcome, counts/exits, known limitations and unobserved native gates, deviations/decisions, and a SHA-256 snapshot of the final candidate files under `R/worker-b/candidate-sha256.json`. Include a baseline/protected-file comparison relative to accepted A, not just HEAD. Persist the same report at `R/worker-b/final-report.md` even if the CLI fails to stream a final text message. Do not claim parent approval, whole-M9 completion, Update/Uninstall availability or Git delivery.
