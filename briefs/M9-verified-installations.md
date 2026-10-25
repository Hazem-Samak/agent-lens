# M9 — verified installation details and per-installation versions

Status: **technically accepted, user-UI-approved and delivered to `main`**. Parent acceptance followed A/B/C and the combined final gate; the user confirmed “M9 UI approved”, then separately authorized branch delivery and main integration. Approved feature commit `eb4f586` reached `origin/main` through the fast-forward of milestone tip `1ac22c4`; no app release was performed. Sole implementer: DeepSeek V4.1 Flash Free through OpenCode at maximum reasoning effort (`opencode/deepseek-v4.1-flash-free#max`), authorized on 2026-10-22. This is the orchestrator's whole-milestone acceptance contract, not an unbounded worker prompt. [Independent acceptance/delivery evidence](../walkthroughs/M9-verified-installations.md).

Branch: `milestone/m9-verified-inventory`, based on M8 commit `a405b56183ad0233f286f4d93b027ba7d21c2a01`. Preserve pre-existing planning documentation. No commit/push/publication is implied by technical acceptance. Parent authors briefs/review/status documents; worker authors product code/tests and scoped implementation documentation. Revisions always go back to the worker.

## User outcome

The current three tools retain reliable discovery and PATH diagnostics. Their category, declared package candidates and official information are visible; declarations are not confused with verified installation ownership. An explicit read-only action can verify the selected npm/Homebrew-formula installation, including manager, package and root/prefix identities. Each observed canonical executable installation has its own locally measured version or neutral unknown, including copies shadowed on PATH. No tool is installed, updated, removed, relinked or otherwise managed by M9.

## Sequential phases

1. **M9-A** — registry schema 2 metadata and bounded version-query configuration, integrated into CLI/details. Worker brief: [M9-A-detector-metadata.md](M9-A-detector-metadata.md). No ownership-query side effects.
2. **M9-B** — explicit read-only verification of selected npm/Homebrew formula ownership with typed verified/unknown outcomes in CLI/app. [Bounded brief](M9-B-installation-ownership.md), authored after accepting A; corrected B accepted before C dispatch.
3. **M9-C** — per-installation version observations, deduplicated by canonical target, correct for winner/aliases/shadow/off-PATH and visibly represented in CLI/diagnostics. [Bounded brief](M9-C-installation-versions.md), authored after accepting B; corrected C and the combined milestone gate are accepted.

Each phase has independent acceptance. Later preparation may research manager semantics while a worker runs, but no dependent implementation or product edits proceed before the current candidate is accepted. All phases share one milestone branch and one product writer. The whole milestone is not complete until the combined gates below pass on the final source snapshot.

## Whole-milestone requirements and evidence

| Requirement | Required final observation | Phase ownership |
|---|---|---|
| M9-R01 | All bundled/synthetic registry consumers migrate cleanly; schema 1 is rejected; new metadata/query fields fail closed; direct construction/decoding cannot bypass executable-query validity | A |
| M9-R02 | Category, declared candidate packages and official links agree between CLI/app and remain clearly distinct from installed/verified ownership | A, B |
| M9-R03 | Current Codex/OpenCode/Grok IDs/order, shell environment, tri-state install status, off-PATH behavior and Copy/Reveal semantics remain intact | A–C |
| M9-R04 | Only an explicit verification action launches bounded read-only manager queries; launch/plain scan/offline/rescan never perform manager or update-cache I/O; no background verification or mutation | B |
| M9-R05 | A verified result binds selected entry/target, manager identity, actual package identity and manager-reported prefix/root/Cellar to local ownership evidence; path substrings and registry declarations alone never count | B |
| M9-R06 | Unsupported, missing, ambiguous, malformed, oversized, failed, changed-during-query and cancelled verification are truthful unknowns; stale selection/environment results cannot attach to another snapshot/tool | B |
| M9-R07 | Two independent executable installs reporting different versions keep their own values; aliases/repeated PATH slots do not create additional canonical-install observations; vanished/retargeted/failed queries remain unknown | C |
| M9-R08 | Query processes are time/output/concurrency bounded, run off the app's main executor with the resolved environment, and never interpret query arguments as shell code | A–C |
| M9-R09 | Full regression, fresh app build, packaging, real CLI and actual native surface checks pass on the final snapshot; Core stays UI-free, no added dependency, no protected-file drift and no personal installation/cache/configuration changes | Combined |

## Combined final gate

Use a fresh child of `/Users/corvette/.hermes/cache/scratch/agent-lens-m9-20261022-382vfoyi` and invocation-local TMPDIR. Capture complete argv/stdout/stderr/exit/duration without environment or credential dumps.

```sh
R=/Users/corvette/.hermes/cache/scratch/agent-lens-m9-20261022-382vfoyi
env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS \
  TMPDIR="$R/tmp" swift test --scratch-path "$R/parent-final/full-suite"
TMPDIR="$R/tmp" python3 scripts/build-dev-app.py \
  --scratch-root "$R/parent-final/dev-app" --configuration debug
TMPDIR="$R/tmp" python3 Tests/Packaging/test_dev_app_bundle.py \
  --app "$R/parent-final/dev-app/AgentLensApp-debug.app"
```

Expected exit 0 for each. The known invocation-local TestingMacros fallback from M9-A may be used only for that specific discovery failure, in a separate fresh directory, never as a silent package/toolchain change.

Runtime acceptance additionally requires:

- Actual built CLI offline scan shows current three tools, declared metadata, correct PATH winner/alias counts and independent versions. Existing update-mode/invalid-syntax tests preserve their contracts.
- Explicit CLI/app verification correctly handles selected npm and Homebrew-formula fixtures and unsupported standalone cases. Exercise a real npm read-only ownership path and actual Homebrew query plumbing; distinguish fixtures from real-manager evidence rather than treating one as the other. Stronger per-phase requirements are specified in the dispatched brief.
- Two test-owned real executable files with distinct versions, an alias, repeated PATH entries and an off-PATH selection demonstrate the version/identity behavior. No installed tool is modified to create a fixture.
- Actual app selection changes, verification lifecycle/cancellation, rescan and retained failures cannot show one tool's metadata/ownership/version as another tool's. Observe the changed native surface, not only a host or unit test. A fixture host, if needed, reuses unchanged product source and is reported separately.
- An independent read-only reviewer checks M9 ownership and version/identity safety against pinned source and raw evidence, without receiving implementer persuasion. Parent resolves findings through worker revision briefs and reruns acceptance.
- Final candidate is identified by source/test/resource hashes and the recorded base commit. Parent compares scope and protected files before recording technical acceptance. User visual approval and Git delivery remain separate.

## Existing limits carried honestly

M8 keyboard-only activation is still unverified. Parent opened a separate accepted M8 app instance during preflight and observed the controls, but a background Tab event did not prove focus/activation; no global keyboard preference was changed. This remains a release blocker, not a passed M9 gate or reason to alter unrelated preferences.

Default macOS temporary-directory fixture portability and pre-existing compiler/linker warnings remain outside M9 unless they block a newly required behavior. The accepted invocation-local scratch pattern works; CI/portability repair belongs to M10-A. Future M14 names DSH/AGY remain unresolved catalogue research, not guessed metadata or omitted scope.

Route/preflight evidence and raw baseline results live under the external M9 evidence root. No worker result is accepted merely because its CLI exited 0 or it reported success.
