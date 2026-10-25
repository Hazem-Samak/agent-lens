# M9-B R1 — bounded reads and ownership evidence corrections

Status: parent revision brief for the submitted M9-B candidate, not acceptance. Continue the same external worker session `ses_e97e98650ffeFslpBSeLSVc27k` on `opencode/deepseek-v4.1-flash-free#max`. All original M9-B authority, file boundaries, safety envelope and no-Git/no-mutation rules remain binding. R is `/Users/corvette/.hermes/cache/scratch/agent-lens-m9-20261022-382vfoyi`; put this revision's evidence under `R/worker-b-r1`.

The submitted candidate digest is `c9a18127fff3225405925f9a61805c22f032c845b86a779c43d713982d7fa362`. Parent independently built it, passed the full 304-test fallback suite and 9 packaging tests, and observed real npm Codex ownership plus neutral standalone results in the actual app. These passing gates do not excuse the failures below. Independent read-only review found defects; parent reproduced the first two through a compiled production-Core probe.

## R1-01 — FIFO package.json blocks forever before regular-file validation

`NpmOwnershipProbe.readManifest` opens with blocking O_RDONLY before `fstat` proves the descriptor is a regular file. A named pipe without a writer never reaches the check or returns to cancellation cleanup. Query timeouts do not cover it.

Parent proof: `R/evidence/ownership-edge-probe.swift`, compiled against independently built Core. In `R/evidence/ownership-edge-before.json`, the regular-manifest control verified, while an otherwise identical manifest replaced with a FIFO printed START then required the parent's 3-second watchdog to terminate it (exit -15). No installed package was changed; all fixtures were test-owned under `R/parent-b/edge-fixtures`.

Fix with a nonblocking descriptor open and descriptor-level regular-file validation before any reads, retaining no-follow, size cap and identity revalidation. Do not pre-stat alone then perform a blocking open: that leaves the same race. FIFO, socket/device/directory/symlink-to-nonregular cases must produce neutral outcomes promptly without waiting for another process, and cancellation/next actions must settle. Add a deterministic subprocess behavioral regression so a future hang fails under a bounded watchdog instead of wedging the full suite. Preserve the parent's failing-before evidence and passing-after observations.

## R1-02 — Homebrew ownership incorrectly depends on upstream stable metadata

`HomebrewOwnershipProbe` calls `HomebrewUpdateProbe.parseInfo` and requires its `isValid`; that update parser additionally requires `versions.stable` as a string and a valid revision. This contradicts the ownership contract. A HEAD-only or locally known installed formula can have correct name/full_name/installed-keg/file-list evidence with no stable upstream version.

Parent production-Core probe: normal formula record verified; changing only `versions.stable` to null produced `.formulaRecordMismatch`. Receipt: `R/evidence/ownership-edge-before.json` (homebrew control and stable-null scenarios).

Parse the ownership-required record fields in the ownership adapter, not the version/update parser. Reuse existing full-name consistency validation, but do not modify protected M6 update behavior. Ownership needs the matching name/full_name, exact selected installed-keg membership and exact selected file-list proof, not stable/latest/semver/revision. Preserve malformed/conflicting identity claims so duplicate/borrowed names cannot disappear and lend proof to a neighbour. Add regressions for absent/null/non-semver stable and absent/irrelevant revision, plus malformed/ambiguous required identity fields. The same local installation must remain verifiable without upstream metadata. Keep the documented current-keg list limitation neutral.

## R1-03 — identity-change reasons identify the wrong executable

Both adapters' `revalidate(selection:manager:)` distinguish `.managerChanged` from `.selectedExecutableChanged`, but numerous callers discard that reason and always return `.selectedExecutableChanged`. The existing manager-change test currently pins this wrong result.

Propagate the observed reason at each callsite. Replacing only brew/npm must report managerChanged; replacing only the selected tool must report selectedExecutableChanged. Do not collapse proof/root/manifest changes into a fabricated selected-tool change either. Keep subsequent queries suppressed and verified status absent. Update the behavioral mutation regression to assert the actual changed identity; do not preserve the incorrect message for compatibility.

## R1-04 — remove obvious avoidable compiled-code work

Narrowly within B-introduced paths:

- `NpmOwnershipProbe.readManifest` converts bounded Data to String, re-encodes it for an equality check, then re-encodes again for JSONSerialization. Remove the tautological round-trip and duplicate full-manifest copies; parse the bounded original bytes, retaining real validity/size/identity requirements. Do not invent new manifest-encoding policy.
- `HomebrewOwnershipProbe.parseListedPaths` allocates a whole normalized path array and `samePathComponents` repeatedly recomputes the selected target components. Verify membership while validating the bounded list in one pass; do not normalize/allocate the same selected path for every listed file. Preserve malformed-output and exact-path semantics, even after a match is found.
- `OwnershipVerificationView.timestamp` creates/configures a new ISO8601DateFormatter for each render. Use Foundation's value-style/cached ISO8601 formatting rather than a per-render formatter or a new formatting abstraction. Preserve UTC observation-time meaning.

These are local corrections, not permission to redesign adapters, rename unrelated APIs or modify accepted A implementation.

## R1-05 — a canonical npm root outside the reported prefix is accepted

Independent safety review found that directory-identity equality at the expected lexical root follows an escaping `lib/node_modules` symlink and therefore accepts another prefix. Parent reproduced it: P1/lib/node_modules linked to P2/lib/node_modules, npm reported prefix P1/root P2, P1/bin/codex pointed at P2's executable, and verification returned VERIFIED. Raw receipt: `R/evidence/ownership-prefix-escape-before.json`; test-owned trees under `R/parent-b/edge-fixtures/redirect-prefix` and `other-prefix`.

Require canonical root containment and exact canonical `<prefix>/lib/node_modules` layout by components, not only equality after following the expected path's symlink. A physical/ancestor symlink escape from the prefix must remain neutral. Keep legitimate selected-entry aliases and manager executable symlinks working; they are not package-root containment. Add a positive ordinary-prefix control plus this escaped-root regression.

## R1-06 — revalidate lexical package/root bindings, not only old canonical paths

The current proof stores/checks the original canonical prefix/root/package directories. If the declared package's lexical link is retargeted to another in-root store, the old store, selected executable and prefix-bin can remain unchanged and final validation still checks only that old store. The declared package binding has changed, but VERIFIED can survive.

Retain and revalidate the actual manager-reported prefix/root paths and declared lexical package path against their captured identities, as well as the canonical directories. Do the same for relevant prefix-bin bindings. A changed mapping must produce a truthful unknown, not borrow the original store's proof. Deterministically exercise retargeting after package observation but before publication. A small internal test coordination seam following existing TaskLocal test-hook conventions is allowed if necessary; no public test mode, alternate production algorithm or sleep-based race test. Conservative rejection of unusual linked-package layouts is acceptable as an explicit supported-layout limit, but ordinary npm packages and the required same-target selected aliases must continue to verify.

## R1-07 — anchor manifest opening to the package directory

Containment is currently checked before an unanchored `open(resolved.path, ...)`; O_NOFOLLOW protects only its final component. A `package.json` symlink can initially resolve inside the package through an ancestor that is replaced by an outside symlink between checking and opening. The outside file is then read before JSON/final revalidation reject it. This is a missing read-containment control, not a requirement to make every filesystem publication race atomic.

Use descriptor-relative traversal/opening anchored to a verified package directory (or an equally strong containment mechanism), prevent ancestor escape and validate the descriptor/identity before reading. A pre-stat followed by the same absolute open is insufficient. Reject unsupported symlink-manifest layouts explicitly rather than inspect an arbitrary outside target. Preserve the nonblocking/nonregular protections of R1-01 and the byte cap.

Regression fixtures must use only test-owned external decoys, never real credentials or unrelated user files. Cover an inside path/regular-file control, a static ancestor escape and a deterministic ancestor replacement between path resolution and open. Demonstrate no outside decoy was consumed, not merely that final JSON verification failed. If an internal read coordination hook is needed, keep it narrow and dormant outside tests; do not add manager commands or another filesystem implementation.

## Verification and handoff

After all review corrections are complete, run the original full Swift gate (use the documented explicit TestingMacros fallback directly when that known discovery failure is the active recorded environment), a fresh app builder and all 9 packaging tests, each under fresh `R/worker-b-r1` roots. Run focused regressions and the parent's edge probe against revised Core, retaining raw argv/stdout/stderr/exit/duration. No need to repeatedly run unchanged builds or a known failing macro-discovery invocation merely to confirm the reported host failure.

Update `walkthroughs/M9-B-implementation.md` and persist a final report at `R/worker-b-r1/final-report.md`. Include numbered finding outcomes, regression counts/exits, any unobserved native gate, baseline/protected-file comparison against accepted A, and a new SHA-256 manifest covering all final B candidate files. Keep prior raw evidence intact. Freeze edits on handoff; parent and independent reviewers own the decision. No M9-C, no update/uninstall implementation and no installed-state changes.
