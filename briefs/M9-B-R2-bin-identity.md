# M9-B R2 — contain the exact observed bin identity

Continue external worker session `ses_e97e98650ffeFslpBSeLSVc27k` with the same DeepSeek/OpenCode max route. Original M9-B and R1 scope/safety/no-Git rules remain binding. R is `/Users/corvette/.hermes/cache/scratch/agent-lens-m9-20261022-382vfoyi`; new evidence root `R/worker-b-r2`. R1 candidate digest `9766d392b947600b828fd85fa9e460d123af339e244bd276cb004cbcc91f32f3` is NOT accepted.

Parent independently passed all 314 R1 tests, fresh builder, 9 packaging tests, actual native/npm verification, real Homebrew proof, FIFO/root-escape/stable-null before/after probes. Both independent reviewers found the earlier fixes represented in source; safety rereview found one new blocker below. Do not treat green gates as acceptance or change unrelated working behavior.

## R2-01 — bin containment must constrain the same observation used as proof

Safety reviewer identified `NpmOwnershipProbe.resolveBin` around lines 531–542:

- A first symlink resolution is checked for containment inside packageRoot.
- `observeExecutable(entryPath:)` resolves the bin independently afterward.
- The returned observation is matched to selection, but its canonical target is not itself checked for containment.

Concrete source-derived race (not yet executed by the parent): selected S belongs to another prefix; the current manager prefix/bin/codex points to S; the declared package has a regular valid manifest and bin symlink initially pointing inside its own package. Retarget that bin link to S after the first containment resolution and before observeExecutable. The latter consistently snapshots S; its identity matches selection and final proof revalidation accepts that outside target. This is not a demand for atomic final publication: the actual accepted observation may already violate containment.

Fix by obtaining the executable observation and applying package containment to THAT observation's canonicalTarget before matching it to selection or using it as proof. Remove the redundant pre-resolution where possible rather than maintaining two snapshots that can disagree. Keep exact target/fingerprint equality, package identity/root, prefix-bin proof and final revalidation. No shell/watcher/retry, no fallback to a different target, no broad adapter refactor.

Add a deterministic consumer-visible regression through InstallationOwnershipVerifier.verify: construct S in another test-owned prefix, initial in-package bin link, and retarget at the vulnerable transition using a narrow dormant TaskLocal coordination seam if needed. Capture behavioral RED against the previous logic and GREEN against corrected logic. Assert neutral ownership/no cross-prefix claim, not merely that a hook ran. Keep positive ordinary/in-root alias cases and prior static escape regressions passing. No real credentials or installed tools.

## R2-02 — avoid re-encoding new Homebrew ownership JSON

R1's new `infoFormulaObjects` validates UTF-8 text then creates `Data(text.utf8)` for JSONSerialization even though the original Data is already available and validated. Parse the original bounded data after transport validation; do not add another full JSON copy. Preserve all encoding/envelope/identity behavior and the ownership-only parser (do not revert to the M6 update parser). This is a narrow correction inside the B-introduced adapter, not a new feature or abstraction.

## Authority, gates and handoff

Original allow-list applies. Expected edits: NpmOwnershipProbe.swift, HomebrewOwnershipProbe.swift, InstallationOwnershipTests.swift and worker implementation report. Any required extra file change is a STOP/request first. Do not modify parent briefs/status records or accepted A; no M9-C.

Run targeted new and existing ownership regressions, then one final full Swift gate using the documented invocation-local explicit-plugin fallback for the currently recorded discovery failure, a fresh app builder and all packaging tests in fresh `R/worker-b-r2` roots. Preserve raw RED/GREEN/argv/stdout/stderr/exit/duration. Re-run read-only real npm/Homebrew smoke if those paths changed. No real package mutation or cache/config changes.

Return and persist `R/worker-b-r2/final-report.md`, numbered finding outcomes, exact counts/exits, protected comparison relative to accepted A and new candidate SHA-256 manifest. Freeze files. Parent will independently rerun gates and obtain artifact-only safety rereview; neither R1 nor R2 is technically accepted on worker assertion.
