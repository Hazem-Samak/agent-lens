# M10-D-R1 — review corrections for npm Uninstall

Status: **FROZEN revision**, 2026-11-08 (Africa/Cairo). This revision supplements
[`M10-D-npm-uninstall.md`](M10-D-npm-uninstall.md); it does not reopen accepted M10-C behavior. The
base brief remains frozen and immutable.

## Source review

mcode `minimax/MiniMax-M3.1-Flash` at `xhigh`, read-only independent plan/code review, returned
**BLOCK** on the frozen plan and current implementation draft. Findings are retained verbatim in
[`walkthroughs/M10-D-planning-evidence/mcode-plan-review.txt`](../walkthroughs/M10-D-planning-evidence/mcode-plan-review.txt).
The accepted corrections below are binding for M10-D.

## R1 corrections

### R1-1 — tri-state removal observation (blocking)

`FileIdentityObserver` returns `nil` for absent, unreadable, raced, and wrong-type observations. A
`nil` must never be treated as removal.

- Add Core-internal removal observations that distinguish: package directory present / absent /
  observation failed; selected entry still present at the reviewed target / released / dangling
  residue / absent / observation failed.
- Distinguish absence using `lstat` errno (`ENOENT`/`ENOTDIR` only) from every other failure.
- `NpmUninstallDelta` adds `selectedEntryResidue` and `observationFailed` (or equivalent typed
  facts). `.succeeded` requires npm exit 0, package directory observed absent, selected target
  released, and **no observation failure**. Any observation failure is `.uncertain`.
- A dangling selected-entry symlink is released but sets the residue fact; a still-live reviewed
  target is not released.
- Add focused tests for an unreadable prefix (chmod-denied observation) and dangling residue.

### R1-2 — clear ownership after any launched removal (blocking)

On `outcome.processStarted == true`, the ViewModel must clear the affected entry's verified
ownership even when the post-launch rescan produced no snapshot. A failed/refused rescan must not
leave the destructive Uninstall button armed. A fresh Verify is required before another
ownership-gated action. Add a test or an actual-app observation for this path.

### R1-3 — acceptance matrix additions (blocking)

The following supplementary rows are mandatory:

| ID | Setup and observation | Pass requirement |
|---|---|---|
| M10-D-AC05b | Package directory is a symlink/in-root store layout; remove it | Removal facts use the recorded package identity; no false success from a different store identity |
| M10-D-AC06b | A second package owns the same bin name in the same prefix | Reviewed package and its target are gone; remaining ownership of the new bin target is reported, not misattributed |
| M10-D-AC06c | Dangling bin/alias residue remains after removal | Removal may succeed with an explicit residue fact; residue is visible in the result, never hidden |
| M10-D-AC06d | Prefix/package observation is permission-denied or otherwise failed | Outcome is `.uncertain`, never `.succeeded`; raw observation failure is recorded |

### R1-4 — public-npm row is not waivable by ambiguity (blocking)

M10-D-AC11 is mandatory. A `BLOCKED` public fixture does **not** pass AC11 and does **not** allow
M10 acceptance. If the public fixture is genuinely unavailable, implementation stops and the owner
must decide the limitation explicitly; controlled-registry evidence cannot silently substitute.
§9's "all pass" remains literal.

### R1-5 — presentation and state corrections (non-blocking, accepted)

- Label the preview's version as the locally tool-reported version, not the npm package version.
- Keep one keyboard shortcut on Cancel (`.defaultAction`); do not apply both default and cancel to
  the same button.
- Add the generation guard to `confirmSelectedUninstall` publication for symmetry with preparation.
- Delta/result view shows observation failure and selected-entry residue.
- D03.4's wording must not claim `--no-save` protects project files; global mode is the protection.
  The flag remains harmless and may stay in argv for consistency.
- The coordinator's roadmap/status documentation write is the sole exception to DO NOT TOUCH.

## Authority

Modify only M10-D's authorized files plus the previously authorized test/fixture files. No
dependency, CI, packaging, registry, historical-evidence, or frozen-brief change. Re-run the
targeted Core/AppSupport tests, the controlled real-npm acceptance, full local gates, and both
implementation reviews after these corrections.
