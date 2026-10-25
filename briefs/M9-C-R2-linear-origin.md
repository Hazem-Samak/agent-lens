# M9-C R2 — linear origin lookup and explicit CLI evidence boundary

Same external worker/session `ses_e9075990dffeh8w7l1a6lam5Fj`, DeepSeek/OpenCode max route. Original C and R1 safety/scope/no-Git contracts remain binding. R1 candidate `7a281605bff4806d98077afbf43ca858ca46073b094aae128d666110bf1cdc1d` is frozen and not accepted; preserve its evidence. Use `R/worker-c-r2`, where R remains `/Users/corvette/.hermes/cache/scratch/agent-lens-m9-20261022-382vfoyi`.

## R2-01 — avoid the new quadratic origin lookup

R1 correctly retains typed origin, but `PathDiagnostics.swift:294–310` invokes `representativeOrigin(for:in:)` for each canonical group. That helper at 324–331 linearly scans all live candidates each time. This adds O(groups × candidates) work just to retrieve a fact already recorded in `PathTargetGroup.firstSlotIndex`, and even re-scans the selected group before its duplicate is skipped. It is new avoidable computation on the local scan path, outside the bounded process budget.

Use the existing firstSlotIndex into the **same immutable original environment.pathEntries array** from which the scanner constructed those groups to build `.path(slotIndex:directoryText:)` in O(1) per group. This is the representative's exact original discovery slot/text, not a filesystem rescan or inferred canonical-parent directory. Preserve empty/relative/raw PATH text. The private helper only receives groups produced by that scan; the index relationship is an internal invariant. Keep off-PATH origin directly from the selected candidate. Pass the original PATH entries narrowly where needed; do not allocate a duplicate origin dictionary/index, introduce a cache, expand PathTargetGroup's public model or change any observable origin/version/selection result. Skip already-seen groups before unnecessary work. Remove the obsolete linear helper and comments/parameters.

Do not optimize the pre-existing M5 grouping algorithm or perform unrelated cleanup. This revision is only the newly introduced origin-recovery regression. No new permanent implementation/complexity/source-spelling test: existing typed-origin, repeated-slot, alias, relative/empty-slot and changed-off-root regressions must remain correct.

## R2-02 — align CLI provenance disclaimer with the native boundary

Final contract rereview closed both original behavior defects but noted `DiagnosticsScanRenderer.swift:80` says the observed extra-root origin is not a current shell winner without the native view's explicit “not verified ownership” distinction. Keep the observed-origin/root annotation and add the same ownership boundary to the CLI text. This is a narrow clarity alignment with the R1 contract, not a request to infer ownership or change any typed fact. No new wording/source-spelling test; existing behavioral coverage plus parent production-renderer smoke is sufficient.

## Authority and gates

Only product edits expected: `Sources/AgentLensCore/Diagnostics/PathDiagnostics.swift` and the extra-root annotation in `Sources/AgentLensCore/Diagnostics/DiagnosticsScanRenderer.swift`. Worker implementation documentation `walkthroughs/M9-C-implementation.md` may record the final invariant. Anything else substantive is STOP/request first. No shared identity/ownership/query transport/service/update/cache/registry/package/builder/packaging or parent documentation edits.

After these corrections, focused affected diagnostics/version tests and one final complete serial Swift gate using the established invocation-local explicit TestingMacros plugin, fresh builder and packaging. Repeat compiled scanner smoke, terminal-selected-failure and off-root-origin regression evidence plus the closed two-version CLI fixture. No installed tool mutation, no meaningful test loosening/skipping, no repository .build move. Preserve complete raw argv/cwd/stdout/stderr/exit/duration and failed attempts in fresh R/worker-c-r2 roots.

Persist `R/worker-c-r2/final-report.md`, exact results and scope/protected comparison, delta from R1, complete replacement C candidate manifest and frozen snapshot. Freeze after final report/implementation documentation are consistent; do not amend after freeze. Parent independently reruns final gates/native/identity probes and performs final source rereview. No parent acceptance, whole-M9 completion or Git delivery on worker assertion.
