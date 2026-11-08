# M10-D — npm Uninstall and combined npm acceptance implementation

Status: **technically accepted on the feature branch and owner-authorized for merge**, 2026-11-08
(Africa/Cairo). All seven hosted gates, controlled/combined/public real-npm acceptance, and the
ordinary-app native click-through pass. A final R2 correction pass fixed the review findings and was
self-reviewed twice under the owner's explicit waiver of a further independent review; merge is
authorized. The plan is frozen at `3d6129d`; the binding review corrections are frozen in
[`briefs/M10-D-R1-review-corrections.md`](../briefs/M10-D-R1-review-corrections.md).

## Candidate and authority

- Branch: `codex/m10-npm-management`.
- Base: `4b828c7` (M10-C accepted) plus the frozen M10-D plan/R1 documentation commits.
- Implementation candidate after CI hardening: `308b7d2bce8875752219f4dbe9a58d9492285c30`;
  earlier candidates were `ef3a778` and `406b18e`. Pushed to `codex/m10-npm-management`; PR #1 is
  open against `main` for the whole M10 stage.
- Writer: the orchestrator (owner-authorized D-014 exception). Independent read-only reviews:
  mcode `minimax/MiniMax-M3.1-Flash` at `xhigh` (plan review BLOCK and implementation review BLOCK),
  agy `gemini-3.8-flash-high` at `high` (implementation review; status recorded in evidence).
  OpenCode `opencode/glm-5.3-flash-free#max` was the requested plan reviewer but stalled twice; its
  completed material finding (npm v7+ does not run uninstall lifecycle scripts) was verified and
  corrected.
- No dependency, packaging, registry, frozen-brief, `main`, or release change is included. R2
  raises only the CI count floors and adds the correction/test changes recorded below.

## Implemented surface

- `NpmUninstallOperation.prepare` performs a fresh live `NpmOwnershipProbe.verifyWithProof` using an
  owned scratch environment, claims a mode-0700 operation root, binds the selected entry/target,
  optional locally tool-reported version, manager, `VerifiedInstallation`, complete proof, prefix,
  environment context, and literal argv. It reads/writes no metadata cache and sends no metadata
  query.
- `execute(confirmed:)` repeats a fresh local scan and full ownership/proof comparison, revalidates
  the live proof and owned root immediately before launch, consumes one process-wide gate, and runs
  one literal global `npm uninstall` with the verified manager/prefix and public registry pins.
- R1-1 tri-state removal observation distinguishes absent, present-with-identity, replaced identity,
  released target, dangling residue, and observation failure. `.succeeded` requires exit 0, package
  directory observed absent, selected target released, and no failed observation. Any observation
  failure is `.uncertain`.
- Post-launch reconciliation reports before/after entry/target/version/alias/shadowed/install state,
  package-directory replacement, residue, observation failure, and neutral ownership of any remaining
  selection.
- AppSupport owns a separate uninstall pipeline but shares one mutation slot with Update. A launched
  removal clears the affected entry's ownership even when the rescan fails or is cancelled (R1-2).
- Native `UninstallOperationView` shows the exact preview/argv/effect, uses Cancel as the default
  action, and renders separate bounded stdout/stderr, exit, delta, residue, and observation facts.
  `ToolDetailView` only offers Uninstall after a current verified npm ownership observation.
- No CLI mutation command was added.

## Local gates

Targeted evidence:

```sh
swift test --no-parallel --build-system swiftbuild \
  -Xswiftc -load-plugin-library \
  -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib \
  --filter NpmUninstallOperation
```

Observed: all **20** Core uninstall tests passed, including in-root symlink store, replacement,
shared-bin, dangling-residue, unreadable-prefix, interruption, stale-proof, gate, and cleanup cases. AppSupport integration test `uninstallPreparationAndExecutionPublishTheFreshRemovalDelta`
and ViewModel test `failedPostUninstallRescanClearsOwnershipAndDisarmsUninstall` passed.

The final full suite passed **454 Core + 78 AppSupport = 532 tests**, zero failures/skips, exit 0
([receipt](M10-D-implementation-evidence/full-suite-final.log)). The R2 correction pass then added
three regression tests and passed **456 Core + 79 AppSupport = 535 tests**, zero failures/skips,
exit 0 ([R2 receipt](M10-D-implementation-evidence/full-suite-r2.log)). The local TestingMacros
load-plugin fallback is test-only; hosted commands are unchanged. Guard: 21 behavioral fixtures
passed; import guard passed; packaging: 9 tests passed ([guard](M10-D-implementation-evidence/packaging-import.log),
[packaging](M10-D-implementation-evidence/packaging.log)).

## Real npm acceptance

### Controlled Uninstall

`Tests/Fixtures/M10D/npm_uninstall_acceptance.py --scenario controlled` installed real npm package
`@openai/codex@1.0.0` into a disposable prefix from an owned loopback registry, then executed the
production Core operation with real npm. Receipts:
[controlled](M10-D-implementation-evidence/controlled/uninstall-summary.json).

- exit 0; one uninstall invocation; exact argv contains `uninstall @openai/codex --global --prefix
  <verified-prefix>`, base and scope registry pins, `--no-audit --no-fund --package-lock=false
  --no-save --fetch-retries=0 --fetch-timeout=30000`; no `--force`, `--ignore-scripts`, `--dry-run`,
  `prune`, or `update`.
- `packageDirectoryAbsent=true`, `selectedTargetReleased=true`, `selectedEntryResidue=true` (the
  external alias is dangling), `observationFailed=false`, after state `notInstalled`.
- Unrelated package/prefix sentinel manifests unchanged; operation base clean; one registry
  install request set only, no uninstall registry request.

### Combined Update → Uninstall

The original `--scenario combined` performed Update `1.0.0 → 2.0.0` and then Uninstall in one
prefix with one `OperationExecutionGate`. Receipts:
[combined](M10-D-implementation-evidence/combined/combined-summary.json).

- Update exit 0, after version `2.0.0`; controlled registry used only for the update.
- Uninstall exit 0, package absent, target released, residue reported, observation not failed.
- Sentinels unchanged; exactly one update and one uninstall invocation; operation base clean.
- No concurrent operation was possible; the gate is released between operations.

**R2 extension (2026-11-08):** the combined scenario now also performs a deliberate concurrent
confirm and a window-close/interruption case on one shared gate. The wrapper manager marks the
launched update; a second `execute` on the same preparation is attempted while the first process is
alive (gate held, preparation claimed), then the uninstall is cancelled after its process starts.
Observed: update `succeeded`, competing confirm `cancelled` with `processStarted=false`, no cleanup
warning, and exactly one update invocation; interrupted uninstall `interrupted` with
`processStarted=true`, reconciliation present, and `installedAndOnPath` still true; a fresh uninstall
then `succeeded`, package absent, target released, dangling residue reported, observation not failed,
final state `notInstalled`, exactly two uninstall invocations (interrupted + final). Receipts:
[combined summary r2](M10-D-implementation-evidence/combined/combined-summary-r2.json),
[combined result r2](M10-D-implementation-evidence/combined/combined-result-r2.json).

### Public npm through the shipping service boundary

The M10-C public fixture prepared real public `@openai/codex@0.165.0` (fresh latest `0.167.0`) in a
disposable prefix with synthetic HOME/config/cache and a strict Seatbelt profile. The M10-D public
host used the shipping `InventoryService`, the shipping detector registry source, production scanner,
`ProcessUpdateCommandRunner`, and `ProcessOperationCommandRunner`, with no injected transport.

Receipts: [public](M10-D-implementation-evidence/public/public-uninstall-summary.json).

- Ownership verified before preparation; uninstall exit 0; package directory absent; selected target
  released; no failed observation; after state `notInstalled`.
- Sentinel manifests unchanged.
- Post-operation shipping CLI `agent-lens scan --offline` under the same isolated environment reports
  Codex as not installed: [CLI parity](M10-D-implementation-evidence/public/cli-post-uninstall.txt).
- `stdout` reported "removed 2 packages"; the measured package directory and target are gone, and
  the delta is reported without claiming that dependency/cache residue is absent.

### Offscreen native view evidence

The shipping `UninstallOperationView` was compiled from source into a small AppKit host and rendered
offscreen through `NSHostingView` for the prepared preview and the reconciled result. The operation
facts were a real success: package directory absent, target released, dangling residue reported, no
observation failure, sentinel unchanged. Receipts: [preview](M10-D-implementation-evidence/render/preview.png),
[result](M10-D-implementation-evidence/render/result.png), [render summary](M10-D-implementation-evidence/render/render-summary.json).
The offscreen renderer drew layout and controls but did not rasterize legible text glyphs in this
environment, so it is layout/state evidence, not visual approval.

### Native ordinary-app click-through

After the owner granted Accessibility, the current debug app was built and launched under the public
fixture with synthetic HOME/config/cache and the strict profile. The ordinary app was driven through
Accessibility:

1. `Verify Installation for Codex` → `Uninstall…` appeared.
2. `Uninstall…` → the destructive sheet exposed `Cancel` and `Uninstall Package`.
3. `Cancel` → prefix SHA-256 manifest was byte-identical before/after.
4. Fresh `Uninstall…` → `Uninstall Package` → result sheet.
5. Result: **Uninstall Succeeded**, exit 0, `0.165.0 → —`, install state
   `installedAndOnPath → notInstalled`, package directory gone, target released, no replacement,
   no residue, no failed observation, remaining ownership neutral.
6. Shipping CLI `scan --offline` then reported Codex not installed; public sentinels unchanged.

Window screenshots and the action transcript are retained:
[preview](M10-D-implementation-evidence/native/preview.png),
[result](M10-D-implementation-evidence/native/result.png),
[actions](M10-D-implementation-evidence/native/native-actions.txt). This closes M10-D-AC09 and the
ordinary-app/public route; offscreen renders are supplemental only.

## Review dispositions

- OpenCode plan review stall: retained partial transcript; npm lifecycle-script claim corrected.
- mcode plan review BLOCK: R1-1 tri-state observation, R1-2 ownership clearing, R1-3 supplementary
  rows, R1-4 non-waivable public row.
- mcode implementation review BLOCK: B1 matrix rows addressed by Core/AppSupport tests and the
  controlled/combined/public receipts above; B2 ownership-clear ViewModel test added; B3 controlled
  host now asserts residue/observation; B4 public service evidence added, native UI blocked as above.
- agy implementation review: static **BLOCK**. B1 cited `repo` as undefined in the render scenario;
  that was a stale read — the render scenario defines `repo` and ran successfully (`RENDER OK`).
  B2 was the pre-grant TCC limitation; the owner subsequently granted Accessibility and the full
  click-through above passed. Its non-blocking update-confirm generation guard and busy-gate cleanup
  warning were corrected. Full transcript:
  [agy static review](M10-D-implementation-evidence/reviews/agy-static-review.txt).
- Hosted CI run `42469754358` on `406b18e` failed exactly one test:
  `cancellingAfterSpawnInterruptsAndReconcilesWithoutOrphan` observed `.uncertain` instead of
  `.interrupted` because the process exited during the TERM grace period without the runner's
  cancellation flag being set. The operation now treats a cancelled caller after launch as
  interrupted (`Task.isCancelled`), and the fixture's child loops until killed.
- [Hosted run 42470655181](https://github.com/Hazem-Samak/agent-lens/actions/runs/42470655181) on
  exact SHA `308b7d2` passed all seven gates: guard, 21 guard fixtures, package build, native-macro
  isolation, combined full suite **532 tests**, fresh debug app, and **9** packaging checks. No
  skips or failures.

## R2 corrections and merge authorization (2026-11-08)

The owner authorized a final correction pass, explicitly waived a further independent
post-correction review because no other implementer/model was authorized, and authorized the sole
implementer to self-review twice and merge. No independent PASS is claimed for this pass; the
historical mcode/agy verdicts above remain unchanged and the waiver is recorded in
[`reviews/README.txt`](M10-D-implementation-evidence/reviews/README.txt).

Corrections:
- **Check/Refresh scratch default:** `InventoryService` no longer forwards the captured login-shell
  `TMPDIR`; the probe uses Foundation `temporaryDirectory` when no base is injected. Regression
  covers a 0777 captured TMPDIR while still obtaining `updateAvailable` (M10-B B04).
- **Update busy-gate warning:** the update branch mirrors uninstall's `isConsumed` guard, so a
  consumed preparation replayed under a busy gate does not report a false scratch-cleanup failure.
- **Pre-spawn cancellation:** `runDualStream` rechecks cancellation immediately before
  `posix_spawn`; a deterministic test proves `processStarted == false` and no child marker.
- **Preview identity:** both confirmation sheets now show the stable registry ID.
- **Combined acceptance:** the combined scenario now includes the required deliberate concurrent
  confirm and window-close/interruption cases, with the observed fields recorded in
  `combined-result-r2.json`.
- **CI floors:** raised to **456 Core + 79 AppSupport = 535**, the measured post-R2 inventory.
- **Public evidence hygiene:** local absolute paths in PR-added text receipts were redacted to
  `<repo>`/`<home>`; the two affected SHA256 manifests were regenerated and verified. The frozen
  M10-B dispatch brief was left byte-identical.

Verification:
- Full local suite with the documented TestingMacros fallback: **456 + 79 = 535**, zero
  failures/skips, exit 0. Raw log:
  [`full-suite-r2.log`](M10-D-implementation-evidence/full-suite-r2.log).
- Extended combined real-npm scenario: exit 0, `COMBINED-CONTROLLED OK`; receipts:
  [`combined-summary-r2.json`](M10-D-implementation-evidence/combined/combined-summary-r2.json),
  [`combined-result-r2.json`](M10-D-implementation-evidence/combined/combined-result-r2.json).
- Targeted regression tests passed: `busyGateReplayDoesNotReportFalseScratchCleanupFailure`,
  `cancellationDuringSetupPreventsSpawn`, `checkUpdatesUsesFoundationScratchWhenNoBaseIsInjected`.
- Self-review records:
  [`self-review-1.txt`](M10-D-implementation-evidence/reviews/self-review-1.txt),
  [`self-review-2.txt`](M10-D-implementation-evidence/reviews/self-review-2.txt).
- Hosted exact-SHA CI for the R2 head is recorded on PR #1; the merge commit is recorded in
  `ROADMAP.md`/`DECISIONS.md`.

## Limitations

- Controlled registry evidence uses loopback substitution for update; uninstall executes with public
  pins and makes no registry request.
- The result sheet reports npm's "removed 2 packages"; the package directory and selected target are
  gone, but dependency/cache residue outside the package is not claimed absent.
- The R2 self-review is not an independent review; the owner waived that requirement explicitly.
- Historical receipts retain their measured content after the disclosed local-path redaction; the
  affected SHA256 manifests were regenerated.
