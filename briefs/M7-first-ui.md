# M7 — First Native UI

> STATUS: PLAN ONLY — awaiting explicit user approval before implementation.
>
> User-approved product shape: “A single native window with inventory, diagnostics, and tool details.” The specific
> layout, interactions, architecture, and defaults below are proposals, not settled product requirements.
>
> The parent is authorized to publish the accepted M6 correction and this plan to `main`; that publication does
> not authorize M7 source changes, an M7 branch, prototype, build, compilation, test, or release. No M7
> implementation operation was performed while drafting this plan.

## Goal and completion boundary

Build the first native SwiftUI macOS app over the accepted M0–M6 engine. Show every registry tool, local installation
facts, first-class PATH diagnostics, and selected-tool details in one window. The GUI consumes typed AgentLensCore
models; it does not launch the CLI and parse presentation text.

M7 ends at an independently verified, locally runnable development `.app` with truthful inventory/diagnostic/update
state and the approved one-window shape. It adds no management operations, persistent inventory, release pipeline, or
background behavior. The current deliverable is this plan only.

## Authority and prerequisite status

Governing requirements: `AGENT_LENS_SCOPE.md` §§14, 20, 21, 25, 27, 28.3; `DECISIONS.md` D-001, D-002, D-005–007, D-009, D-011–015, D-019; and accepted M0–M6 briefs/walkthroughs, especially M5/M6.

M6 is a prerequisite. The original milestone is accepted; the unsupported-version-reason correction is independently accepted at 184/184 (exit 0), with compiled classification proof and targeted review passed.
It is documented in `walkthroughs/M6-version-update-probing.md`. Its acceptance checkpoint was `fix/m6-unsupported-version-reason` based on `13afef5`; current Git refs/history determine publication and base status.

Protect the accepted M6 source/test snapshot regardless of Git status; do not use dirty-file counts as a proxy.
The parent is authorized to publish the M6 correction and this plan to `main`. Before any future M7 branch or
preflight, verify that the accepted correction is included in the chosen base. This publication authorization
does not authorize M7 implementation. Do not create an M7 branch during planning.

Baseline caveat: ordinary default-Darwin-`TMPDIR` runs retain fixture portability failures; do not assign M2–M5 fixes to M7. Use invocation-local `TMPDIR` beneath approved Hermes scratch, leaving optional `AGENT_LENS_TEST_SCRATCH` and `AGENT_LENS_TEST_PRODUCTS` unset for the full-suite gate.
Swift Testing macro discovery is intermittent; use the existing library fallback only for that specific failure. Do not modify or install tooling.

## Verified starting point

- `Package.swift`: Swift tools 6.0, macOS 14+, zero external packages; targets are `AgentLensCore`, `agent-lens`, and
  `AgentLensCoreTests`. Core has no SwiftUI/AppKit imports; preserve the CLI as an independent product.
- `DetectorDefinition`: `id`, `displayName`, `executableName`, `extraSearchRoots`, optional fixture, `makeDetector()`;
  no category, package metadata, icon, or documentation-link field. Default Codex/OpenCode/Grok JSON remains schema 1.
- `DetectorRegistry.loadDefault()` throws for validation failures but `fatalError`s if `DefaultDetectors.json` is absent
  from `Bundle.module`. Package the Core resource and prove its presence before normal GUI launch; do not require an
  unrelated Core refactor.
- `PathDiagnosticsScanner.scan(detector:environment:currentDirectory:)` is synchronous and returns
  `ToolPathDiagnostic`, which has no registry ID. Its local `--version` query is bounded to three seconds. Shadowed
  versions are not queried and must never be presented as known.
- `ToolPathDiagnostic` contains the selected `DetectedTool`, tri-state install facts, candidate paths/kinds, winner,
  off-PATH/missing/inconsistent selection, aliases, repeated slots, shadowed count, and selected paths.
- `ShellEnvironmentResolver.resolve()` caches once per process; no invalidate/reset/force-refresh API exists. Public
  `loginShellPath()`, `capture(shellPath:script:timeout:)`, and `buildEnvironment(shellPath:outcome:)` allow explicit
  rescan without editing Core. All processes use that raw environment, never `ProcessInfo` PATH or `$SHELL`.
- `UpdateProbeSubject` carries `registryID`, `displayName`, and diagnostic. `UpdateProbeCoordinator.run(...)` accepts
  typed subjects/environment/mode/runner/cache URL/current directory/clock; modes are `localOnly`, `checkUpdates`,
  `refresh`, and `offline`; `ProcessUpdateCommandRunner` is public. Preserve M6's six-hour cache, formula-only support,
  provenance, neutral unknowns, and updateAvailable-only count.
- CLI flow already maps definitions to diagnostics, builds typed update subjects, prints local facts before optional
  probing, then appends results. CLI renderers are presentation only; the GUI must not parse CLI output.

## Approved shape and proposed defaults

Only the single-native-window shape is user-approved. These concrete defaults are proposals for approval:

- One `NavigationSplitView` with Inventory and Diagnostics destinations; the selected tool's details occupy the
  detail pane. Diagnostics is first-class, not a footnote.
- Inventory lists every registry definition, including missing tools. Distinguish “known tools” (definitions) from
  “installed” in counts; do not depict missing tools as installations.
- Search by display name, executable name, and observed entry/target path. Selection survives filtering/rescan by
  registry ID.
- No fabricated categories or per-tool icons. Use native labels/symbols only for generic state and controls.
- Details show local version, source heuristic, install state, selected entry/target, and matching PATH evidence.
  Unknown versions remain neutral, never “up to date.” Diagnostics shows winner/off-PATH status, candidate kinds,
  aliases, repeated slots, shadowed count, and degraded-environment warning without implying ownership.
- Native light/dark appearance, keyboard focus/navigation, selectable path text, resizing, and accessibility labels;
  no custom design system.

Proposed freshness/actions:

- Launch displays the window/loading shell immediately and runs a local-only scan asynchronously. Never auto-check
  updates on launch, activation, timer, or window focus.
- Rescan captures a fresh login-shell environment and refreshes local inventory; it does not check updates.
- Check Updates refreshes local facts with the current session environment, publishes them, then runs M6
  `checkUpdates` (cache-aware). Refresh Updates does the same with M6 `refresh` (bypass cache).
- Local-only/offline retain M6's zero manager/cache-I/O guarantee. No separate offline toggle unless the user asks.
- Update failures remain typed unknown results and do not hide local inventory. Latest means latest known to verified
  Homebrew formula metadata, not guaranteed global latest. Unsupported managers/schemes stay unknown; add no manager.

Before implementation, ask about material product choices not covered by the approved shape and proposed defaults.
Visual refinements may be settled by Hazem's review of the real native window, but do not imply feature approval.

## Bounded scope and non-goals

In scope after approval: app-support and SwiftUI executable targets; typed snapshots, injectable service/environment
seams, observable main-actor state, one-window views, local-first async scanning, explicit rescan/check/refresh,
truthful loading/error/unknown states, deterministic synthetic tests, and scratch-only unsigned `.app` packaging.

Out of scope: package operations (install/upgrade/uninstall), delete/relink/pin, copy-path/Finder actions, settings,
persistent inventory/history, cache redesign, new detectors/managers/schema fields/categories/metadata, or versions for
shadowed executables; menu bar/scheduling/notifications/automatic checks; inventory persistence or sub-300 ms launch
claims; Xcode-project migration; CI/release automation; signing/notarization/DMG/cask/Sparkle/entitlements/App Sandbox;
and remaining default-TMPDIR fixes or broad Core/CLI refactors.

## Proposed future file boundary

This is a future allow-list, not permission to edit now. Stop and ask before expanding it.

New production files:

- `Sources/AgentLensAppSupport/InventorySnapshot.swift`
- `Sources/AgentLensAppSupport/InventoryService.swift`
- `Sources/AgentLensAppSupport/SessionEnvironmentProvider.swift`
- `Sources/AgentLensAppSupport/InventoryViewModel.swift`
- `Sources/AgentLensApp/AgentLensApp.swift`
- `Sources/AgentLensApp/MainWindow.swift`
- `Sources/AgentLensApp/ToolListView.swift`
- `Sources/AgentLensApp/ToolDetailView.swift`
- `Sources/AgentLensApp/DiagnosticsView.swift`
- `Resources/AgentLensApp/Info.plist`
- `scripts/build-dev-app.py`

New tests:

- `Tests/AgentLensAppSupportTests/InventoryServiceTests.swift`
- `Tests/AgentLensAppSupportTests/SessionEnvironmentProviderTests.swift`
- `Tests/AgentLensAppSupportTests/InventoryViewModelTests.swift`
- `Tests/AgentLensAppSupportTests/BundleResourceTests.swift`
- `Tests/Packaging/test_dev_app_bundle.py` using Python standard-library `unittest` only.

Only existing production file planned for modification: `Package.swift`, adding `AgentLensAppSupport`, the
`AgentLensApp` executable, and app-support test target. Support depends on Core and Foundation/Observation, never UI
frameworks. The SwiftUI-only app consumes support. No external package, platform-floor change, Xcode project, or
Core/CLI change.

Protected from implementation edits absent an exact approved exception: all M6 correction changes;
`Sources/AgentLensCore/**`, `Sources/agent-lens/main.swift`, existing `Tests/AgentLensCoreTests/**`,
`DefaultDetectors.json`, `README.md`, `AGENT_LENS_SCOPE.md`, `DECISIONS.md`, existing briefs/walkthroughs/indexes.
Keep the accepted M6 correction source/test snapshot byte-for-byte protected regardless of Git status.

After independent M7 acceptance, the parent owns acceptance/documentation orchestration and supplies Luna Max the
exact evidence and approved closeout scope. Luna Max is the sole editor of the scoped closeout files: the M7 result
in `DECISIONS.md`, status in `briefs/README.md`, concise `README.md` development note, and
`walkthroughs/M7-first-ui.md`. The parent reviews but does not edit them. Do not change settled decisions; if new
decision text is needed, stop for user approval. No closeout documentation changes before acceptance.

## Proposed architecture and state contract

`AgentLensAppSupport` owns the typed app boundary; SwiftUI owns layout. `InventorySnapshot` holds ordered entries that
pair registry ID/definition with diagnostic and update state. `InventoryService` is injectable for registry,
environment, scanner, update runner, clock, and cache URL so tests never touch real package state or the real app cache.

Construct definition-to-diagnostic associations from the complete ordered registry scan before UI filtering. Carry the
registry ID beside every `ToolPathDiagnostic` (it has no ID). Never zip filtered definitions to unfiltered
reports/results; never associate by display name or executable basename. Use IDs for result association and selection.

`SessionEnvironmentProvider` caches one app-session environment. Initial resolution may call `resolve()`. Explicit
Rescan obtains `loginShellPath()`, calls `capture`, and uses `buildEnvironment`; do not reset Core's static cache.
Check/Refresh reuse the current environment. Persist or log no environment values.

`PathDiagnosticsScanner.scan` and shell capture block. Bridge them off MainActor on a utility queue with a checked
continuation; a `Task` on the main executor is not an offload. Reuse typed M6 coordinator/runner APIs with injected
cache/clock; never invoke the CLI or parse its renderer.

Proposed main-actor phases: `idle`, `loadingLocal`, `localReady`, `checkingUpdates`, `ready`, `failed`. Errors are
values. Keep the window visible while loading; publish local diagnostics before delayed optional updates. Update
failure returns to useful local/ready data with neutral reasons. Invalid JSON/schema in a present registry resource
produces a typed `DetectorRegistryError` rendered as failed state. A missing bundled resource triggers the existing
`fatalError`; it cannot be caught as a Swift error and is not promised as a UI state. Reject it in packaging/preflight
before normal GUI launch. A failed rescan retains last useful local data and shows a freshness error.

Permit one active scan/probe pipeline. Disable/coalesce conflicting controls, cancel obsolete work, wait for bounded
child cleanup, and use generation IDs to suppress late publication. Synchronous local work may finish its current
bounded version query before cancellation takes effect; never publish that obsolete generation. Reconcile selection by
ID. Clear previous verified update results at new scan/check start; failed refresh must not present an earlier verified
badge as its current result.

Every process receives `ShellEnvironment.raw`. Never use `ProcessInfo.processInfo.environment["PATH"]`, `$SHELL`, or a
terminal-derived PATH. Persist/log no raw environment, credentials, or shell output.

## Local development bundle contract

Current tool discovery supplied for this plan: `xcode-select -p` is `/Library/Developer/CommandLineTools` and
`xcodebuild -version` exits 1. This does not establish that full Xcode is installed. Do not install/select Xcode. First
attempt a real SwiftPM SwiftUI build with the installed toolchain/macOS SDK; if SwiftUI/AppKit or its SDK is unavailable,
stop and ask for toolchain approval. No paid signing is needed for local development.

Proposed `scripts/build-dev-app.py` interface: explicit `--scratch-root PATH` and `--configuration debug|release`.
All build/bundle output stays under that root: SwiftPM products in `<root>/swiftpm`, app at
`<root>/AgentLensApp-<configuration>.app`; print the absolute `.app` path and fail nonzero on missing/copy/validation
errors. Discover products using `swift build --show-bin-path`. Copy the GUI executable and every required SPM resource
bundle into the actual location resolved by compiled `Bundle.module` accessors; do not assume bundle names or rely on
the original build folder. Add `Info.plist`, validate layout, and never write to `/Applications`, create symlinks, or
modify user installations/caches.

The executable recognizes exactly `AgentLensApp --bundle-preflight` before constructing the SwiftUI window or starting
local scan, shell capture, tool `--version`, Homebrew, or cache work. No-argument launch remains unchanged. The
preflight first checks a packaging-generated `AgentLensCoreResourceBundlePath` entry in `Info.plist` and physically
verifies that the referenced bundled resource bundle and `DefaultDetectors.json` exist. Missing files return nonzero
before calling `DetectorRegistry.loadDefault()`; do not claim Swift can catch its missing-resource `fatalError`. If
the files exist, call the real loader: catch/report thrown invalid-JSON/schema `DetectorRegistryError`s as nonzero.
Success prints only `bundle-preflight: ok registry_count=<N> registry_ids=<validated IDs in registry order>` and exits
0. Failure prints a safe missing/invalid-resource summary and exits nonzero; print no paths or environment values.

The packaging script derives the Info.plist relative resource path from the actual compiled `Bundle.module` lookup,
not an assumed bundle name. The packaging test copies (does not move) the `.app` to
`<root>/packaging/relocated/AgentLensApp-debug.app` and leaves `<root>/swiftpm` intact. A fixture-only sandbox denies
reads from the original build directory; a same-sandbox control read must prove the denial before running the copied
app's `Contents/MacOS/AgentLensApp --bundle-preflight`. Assert the printed IDs/count match the relocated bundle's
registry while the original absolute fallback is unreadable. Do not rename, delete, or rebuild original build
evidence to simulate relocation. Test the missing-resource case only on a disposable copy of the relocated `.app`;
its structural check must return nonzero before the fatal loader path. If read denial cannot be demonstrated, stop.
An equivalent fixture-only isolation mechanism is acceptable only with an observed denial proof; this is not the
production App Sandbox.

The local app remains unsigned/unsandboxed per D-009. Fixture-only test restrictions are not production App Sandbox.
No Developer ID, notarization, entitlements, DMG/cask, updater, or paid account.

## Staged implementation plan and stop gates

1. **Preflight after approval:** parent ensures the correction is preserved/included in the M7 base, gets any needed
   branch-transition authorization, checks SDK/toolchain, and records build/full-test/CLI baseline in scratch. Stop if
   approval, correction inclusion, or a usable SwiftUI SDK is missing. Do not fix unrelated TMPDIR failures.

2. **Package and support:** add targets/models/service; write behavioral RED tests for registry order, stable IDs,
   missing tools, diagnostics, environment reuse/refresh, and local-only behavior. Proposed tests:
   `allDefinitionsKeepIDsBeforeFiltering`, `missingAndOffPathFactsRemainTyped`,
   `explicitRescanCapturesFreshEnvironment`, `localOnlyDoesNotReadCacheOrCallManager`. Stop if protected Core/CLI
   changes are needed; request an exact exception.

3. **View model:** prove concurrency/state with controlled fakes, not sleeps alone. Proposed tests:
   `loadingDoesNotBlockMainActor`, `localInventoryPublishesBeforeDelayedUpdates`,
   `newerGenerationSuppressesOlderCompletion`, `refreshFailureClearsPriorVerifiedBadge`,
   `cancelWaitsForBoundedCleanup`, `selectionReconcilesByRegistryID`,
   `rescanFailureRetainsLastUsefulSnapshot`.

4. **SwiftUI window:** add Inventory/Diagnostics destinations, proposed search/selection/details, and native loading,
   empty, error, and degraded states. No settings/categories/management/automatic probes. Stop for user approval if a
   product decision falls outside this brief.

5. **Packaging:** add scratch-only app builder and resource test. Prove real Core bundle lookup after relocation with
   original products unavailable. If the compiled accessor's resource location cannot be proved, stop; do not refactor
   Core or weaken the test.

6. **Acceptance:** run synthetic matrix, app/CLI product builds, full suite, packaging/resource test, and native smoke.
   Parent independently reruns and reviews all tracked/untracked changes. Luna fixes only allow-listed blockers; do not
   stage/commit/push/publish.

7. **Post-acceptance docs:** parent supplies exact measured totals, toolchain, raw command evidence, review disposition,
   visual acceptance, and packaging limits. Luna Max alone edits the scoped closeout files above; parent reviews them
   but does not edit documentation. Do not change settled decisions. A green build or this plan is not acceptance.

## Required acceptance matrix

All tests use immutable synthetic registry/environment/filesystem/runner/clock/cache inputs in approved scratch. No
real package manager or real Agent Lens cache is used.

| Area | Required proof |
|---|---|
| Registry | All IDs in registry order, including missing tools; known and installed counts are distinct. |
| Identity | Filtering, duplicate display names/basenames, and completion order cannot mix results; no post-filter zip. |
| Local facts | Install state, local version/source, selected paths, PATH selection, candidates/kinds, counts and degraded warning match typed Core facts. |
| Unknown/shadowed | Unknown stays neutral; only `updateAvailable` counts; shadowed versions remain unqueried/unshown; no ownership/latest claims. |
| Environment | Session reuse, explicit fresh rescan, raw environment passed to every process; no ProcessInfo PATH or `$SHELL` fallback. |
| Local-first | Window/loading appears before a controlled scan completes; launch/check/refresh publish local facts before delayed updates; local-only/offline do zero manager/cache I/O. |
| Update policy | Check uses cache; Refresh bypasses it; M6 TTL/provenance holds; failed refresh cannot retain a stale verified badge. |
| Concurrency | Main actor responsive; one active pipeline; bounded cancellation cleanup; generation suppresses obsolete completion. |
| Recovery | Update failure leaves diagnostics usable; failed rescan retains useful local data with freshness warning; invalid present registry renders typed error; missing resource is rejected before normal GUI launch. |
| Packaging | Valid app executable/Info.plist and SPM bundles; relocated preflight passes with original build path read-denied; missing-resource structural check returns nonzero before the fatal loader path. |
| GUI/Core parity | Same immutable input; GUI snapshot matches the typed Core facts used by CLI for every ID, state, local version/source, selected paths, PATH selection, diagnostic counts, update reasons. Never parse CLI presentation. |
| CLI regression | Existing scan/debug-env products still work; typed facts agree under the same fixtures; renderer remains presentation-only. |
| Native usability | Parent smoke: Finder/open without Terminal PATH, keyboard, search, resize, light/dark, selectable paths, VoiceOver labels. Hazem confirms appearance. |

Fixtures must include current/update-available, unknown/unsupported reasons, degraded, missing, duplicate, off-PATH,
delayed, cancellation, registry/update errors, failed rescan, and missing bundle. Use controlled gates/continuations
to prove publication order and MainActor responsiveness; deadlines are bounded watchdogs, not sleeps as sole proof.
Measure/report observed cold-first-render separately without a sub-300 ms promise. Do not invent screenshots or UI claims.

## Future acceptance commands

For a future explicitly approved implementation only; none was run while drafting. Use fresh invocation-local scratch roots.

```sh
m7_root="$HOME/.hermes/cache/scratch/agent-lens-m7-$(uuidgen)"
mkdir -p "$m7_root/tmp" "$m7_root/tmp-explicit"

swift --version
TMPDIR="$m7_root/tmp" swift build --configuration debug --product AgentLensApp \
  --scratch-path "$m7_root/app-build"
TMPDIR="$m7_root/tmp" swift build --configuration debug --product agent-lens \
  --scratch-path "$m7_root/cli-build"
TMPDIR="$m7_root/tmp" swift build --configuration debug --scratch-path "$m7_root/app-build" \
  --show-bin-path
```

Expected: each build exits 0 and `--show-bin-path` reports the products folder used by packaging. No Xcode install or
dependency change. If SwiftUI/AppKit or SDK is unavailable, stop for approval.

Full suite with optional fixture overrides unset and invocation-local `TMPDIR`:

```sh
env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS \
  TMPDIR="$m7_root/tmp" \
  swift test --scratch-path "$m7_root/full-suite"
```

Expected: exit 0 and measured total; 184 is the accepted M6 correction baseline, not a predicted M7 total. Only if
failure is solely the known macro-discovery error, verify the installed fallback and retry from the distinct fresh
scratch path below. Do not mask other failures or install tooling.

```sh
test -r /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib

env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS \
  TMPDIR="$m7_root/tmp-explicit" \
  swift test --build-system swiftbuild \
    --scratch-path "$m7_root/full-suite-explicit" \
    -Xswiftc -load-plugin-library \
    -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib
```

Expected: exit 0 and measured total. This supported scratch invocation does not claim default-Darwin-`TMPDIR`
portability has been fixed.

```sh
TMPDIR="$m7_root/tmp" python3 scripts/build-dev-app.py \
  --scratch-root "$m7_root/dev-app" --configuration debug
TMPDIR="$m7_root/tmp" python3 Tests/Packaging/test_dev_app_bundle.py \
  --app "$m7_root/dev-app/AgentLensApp-debug.app"
```

Expected: builder exits 0 and prints the absolute bundle path; stdlib `unittest` exits 0 after structural,
relocation/resource, missing-resource, and original-build-path-read-denied tests. It preserves the original build tree.
The test creates the deterministic relocated app and deny-read profile described above; output stays under scratch.

The exact future executable preflight invocation (prepared by that packaging test) is:

```sh
TMPDIR="$m7_root/tmp" sandbox-exec \
  -f "$m7_root/dev-app/packaging/deny-original-build.sb" \
  "$m7_root/dev-app/packaging/relocated/AgentLensApp-debug.app/Contents/MacOS/AgentLensApp" \
  --bundle-preflight
```

Expected: exit 0 and one `bundle-preflight: ok registry_count=<N> registry_ids=<validated IDs in registry order>`
summary, with the sandbox control confirming original-build reads are denied. Missing/invalid resources exit nonzero.
This preflight command is future-only; it is not implemented or run today.

Then `git diff --check` must exit 0; inspect tracked and untracked changes; rerun the full suite from a fresh root and
capture raw stdout/stderr/exits. Parent manually launches the relocated app via Finder or `open` in a clean launch
context and records only observed behavior. Do not claim CI/screenshots/visual approval unless obtained. No command
stages/commits/pushes or writes under `/Applications`.

## Division of labor and approval gates

| Role | Future responsibility | Boundary |
|---|---|---|
| Luna Max implementer | Source, tests, packaging scripts, and ALL scoped M7 documentation edits, including post-acceptance closeout from parent-supplied evidence. | Approved allow-list only; sole documentation editor; stop on protected-file need or unresolved product choice. |
| Parent/orchestrator | Scope, authorized branch transition, independent full acceptance, complete-diff review, and documentation orchestration/evidence handoff. | Read-only reviewer and evidence provider; does not edit docs; no self-acceptance or M7 implementation publication without separate authorization. |
| Hazem | Confirm the visible one-window experience and flag visual mismatches. | Visual acceptance only; no coding, Xcode install, paid account, or signing authorization for local development. |

## Risks and open decisions

- Toolchain: current discovery is Command Line Tools only and `xcodebuild -version` exits 1. Actual SwiftUI build decides
  whether the installed SDK suffices; this plan does not prescribe installing Xcode.
- Resource placement: `Bundle.module` must be proved by the relocated preflight, not guessed or “fixed” by preemptive
  Core refactoring.
- Responsiveness: synchronous scan/version query can take time; show loading and keep blocking work off MainActor.
  Measure cold first render separately; no sub-300 ms or persistent-cache promise.
- Freshness/cancellation: async races require generation/single-pipeline/bounded-cleanup/stale-badge tests.
- Missing categories/icons/docs are deliberate: no fabricated metadata. Any schema/UI expansion needs separate approval.
- Product approval gate: approve/revise NavigationSplitView, destinations, search fields, counts, and action freshness
  before implementation. If not approved, stop at this plan. Hazem must visually accept the real native window before
  M7 is declared done.

## Done / stop

M7 is done only after synthetic cases, app/CLI builds, full suite, resource relocation proof, independent parent rerun
and review, native smoke, measured evidence, and Hazem's visual acceptance. Stop at the first usable native window.
Do not add management, settings, scheduling, persistent history, distribution packaging, or detectors without a new
approved brief.

This plan remains pending explicit user approval before implementation. Its inclusion in the parent-authorized M6 publication does not authorize an M7 branch, prototype, implementation, build, test, or release. No secondary plan file is authorized.