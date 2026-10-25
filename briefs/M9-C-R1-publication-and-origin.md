# M9-C R1 — terminal identity failure and durable discovery origin

Resume external worker session `ses_e9075990dffeh8w7l1a6lam5Fj` on the same DeepSeek/OpenCode max route. Original [C brief](M9-C-installation-versions.md) and all safety/no-Git/protected-file rules remain binding. The candidate `3f2f35d9587c90f60f44fe91d90d73c460cacb20656657ff148521fd5e1330e3` is NOT accepted. Preserve its frozen snapshot/evidence.

R is `/Users/corvette/.hermes/cache/scratch/agent-lens-m9-20261022-382vfoyi`; use new `R/worker-c-r1` roots. Parent independently passed all 326 tests, fresh builder and 9 packaging checks; real-file two-version/alias/off-PATH/failure/retarget/replacement/later-change/budget probes passed their ordinary cases. Actual CLI shows current tools correctly. Native host compiling unchanged product sources showed 1.2.3 and 2.3.4 on distinct canonical rows at 760 points, exactly two Codex queries and no cache. Green ordinary paths do not supersede the defects below.

## R1-01 — invalidate the selected observation on the terminal identity failure

Both independent read-only reviewers found this source path:

- `InstallationVersionCollector.swift:177–195` revalidates the selected observation, then later shadowed observations.
- Selected entry changes after its own per-state revalidation.
- The last selected check at 198–203 detects the change, but only assigns `selectedIdentityFailure`; its observation remains measured.
- `PathDiagnostics.swift:227–239` sets selection inconsistent yet derives selectedVersion from the previously captured selectedCandidate and still-measured observation.

**Parent reproduced this against its independently built, unmodified production Core.** Evidence `R/evidence/version-publication-race-before-parent.json`; source `R/evidence/parent-version-publication-race.swift`. This uses real filesystem identities and a controlled fast query callback, with 1500 canonical targets widening the final revalidation interval. Recorded outcome: `selectionInconsistent: true`, `selectedVersion: "1.2.3"`, selected observation still `.measured("1.2.3")`, current entry target changed from target-0 to target-1. It is not a real-child/version-measurement claim for those 1500 files; it is a runtime proof of the publication contradiction through the actual public scanner.

Correct the collector's terminal failure propagation so the matching selected observation cannot remain known after any detected selected-identity failure. Preserve meaningful unknown reasons where appropriate; do not wipe unrelated shadowed observations. Gate selected summary version on the final valid selection/no-identity-failure as well, instead of relying on an earlier captured candidate. Do not restore a winner, retry, suppress the inconsistency or remove the final check. AC04 and C §5.4–5.5 require both the observation and selected summary to lose the stale known value.

Add a deterministic consumer-visible regression that mutates a real fixture **after the per-state publication loop and immediately before the terminal selected recheck**, rather than inside a version query. A narrow dormant internal TaskLocal checkpoint in the collector is prospectively authorized for this exact transition; no public fixture flag, mutable global, watcher or duplicated production algorithm. Assert inconsistent selection, selected version nil, selected observation unknown, and unaffected shadowed measurement retained. Parent before evidence is ground truth; do not rerun the same failure merely to confirm it. Preserve any genuine regression RED you obtain, and GREEN plus full gates after correction.

This is not an atomic-filesystem demand: the actual final check detects the mismatch before publication and its known result must be honored.

## R1-02 — retain off-PATH discovery origin after invalidation

Independent contract review found CLI `DiagnosticsScanRenderer.swift:74–79` and native `DiagnosticsView.offPathSelectionMatches` derive off-PATH annotation from the FINAL `.offPath` selection. When that selection becomes inconsistent during a changed query, the version observation loses its declared-extra-root provenance even though that is exactly where it was discovered.

Parent reproduced this with a real test-owned off-root executable retargeting its entry during its version query. Evidence `R/evidence/offpath-origin-before-parent.json`: selection inconsistent and version unknown correctly, but the canonical-version line no longer has the off-PATH annotation. Current observation fields cannot retain the original root. The original fixed-model packet omitted this durable fact while requiring accurate off-PATH presentation; this revision authorizes its narrow addition, not a broader discovery design.

Add required `origin: PathCandidateOrigin` to the version probe target and `InstallationVersionObservation`, reusing the existing `.path(slotIndex:directoryText:)` / `.extraRoot(index:directoryText:)` type rather than another parallel provenance enum. Retain the deterministic representative's actual discovery origin before any selection invalidation. PATH groups already retain firstSlotIndex; pass the original PATH entries or actual candidate origin as narrowly necessary, without rescanning/guessing roots or copying alias arrays. Cleanly migrate every constructor; no default fabricated PATH origin, shim or schema change.

Render observed off-PATH/declared-root origin from the observation, independently of final selection validity, including the configured root where needed to keep the provenance unambiguous. State it as observed discovery origin, NOT a currently valid shell winner or verified ownership. Do not resurrect a valid `.offPath` selection or the successful `Off-PATH Selected Candidate` block for an invalidated executable just to obtain a badge. The version row's retained origin/root/entry/target and unknown reason are the truthful evidence after failure. Remove obsolete selection-matching helper/parameters when no longer used.

Add a real-fixture regression for an off-root selection changing/vanishing during collection: no known selected value, inconsistent selection, observation still carries its exact extra-root origin, unaffected candidates are not invented. Keep ordinary off-PATH and PATH/alias behavior correct. Parent will re-exercise production rendering and native failure presentation; do not add wording/source-text pinning tests.

## R1-03 — remove new per-render enumeration allocation

`DiagnosticsView.swift:301–305` materializes `Array(diagnostic.installationVersions.enumerated())` and keys rows by transient offset. Each observation already has a unique canonical target by invariant. Iterate the observations directly with `id: \.canonicalTarget`. No array copy, stable installation identity, same values/layout. No permanent test for this source spelling; parent native verification covers the real surface. No unrelated UI polish.

## File authority and verification

Expected edits only:

- Core Diagnostics `InstallationVersionCollector.swift`, `InstallationVersionObservation.swift`, `PathDiagnostics.swift`, `DiagnosticsScanRenderer.swift`;
- App `DiagnosticsView.swift`;
- `Tests/AgentLensCoreTests/InstallationVersionObservationTests.swift` and direct origin-initializer fixture migrations strictly required by compiler/references;
- worker `walkthroughs/M9-C-implementation.md`.

No shared identity-helper behavior, ownership, manager/update/cache, registry/resources, service/model/pipeline, package/build/packaging or parent-document changes. If another substantive file edit is required, STOP/request before making it. Run references for exported observation changes; the new required origin must migrate all actual constructors.

After corrections and focused behavioral checks, one fresh full serial Swift gate with the documented invocation-local explicit macro plugin, fresh dev builder and all packaging checks. Preserve complete argv/cwd/stdout/stderr/exit/duration and failed attempts under `R/worker-c-r1`. Re-run your compiled real-executable scanner smoke and closed two-version CLI fixture, plus changed off-PATH evidence. Do not modify real installations or disable/loosen/skip meaningful checks. Keep repository `.build` intact.

Persist `R/worker-c-r1/final-report.md`, numbered finding outcomes/AC evidence, exact counts/exits, protected comparison against accepted B, candidate delta from C r0 and a full replacement C SHA-256 manifest. Record actual route/CLI version; freeze all candidate files. Parent will independently rebuild/run, replay the actual terminal-publication and origin probes, observe final actual/fixture native surfaces, and obtain artifact-only rereview. No parent acceptance or whole-M9 completion on worker assertion; no commit/push/publication.
