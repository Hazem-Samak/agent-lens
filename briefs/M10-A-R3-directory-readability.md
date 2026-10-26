# M10-A R3 — unreadable-directory failure and final validation

Date: 2026-10-26, Africa/Cairo. Original authorized files only, same sole WorkBuddy/DeepSeek/OMP implementer. Protected-source amendment remains unapproved; no production/older-test edits, Git mutations, subagents or route changes.

Evidence root `E`: `/private/tmp/agent-lens-m10a-impl-20261026-4_wjuwpb`. Preserve earlier receipts; use `E/worker/r3`.

## Guard correction (R03/AC05)

The parent's real CLI probe placed a forbidden AppKit import in an owned fixture. With either the source root unreadable or only its nested directory unreadable (mode 000), the guard returned **exit 0 / 0 Swift files / clean**. Receipt: `E/parent/guard-directory-access-probe/receipt.json`. `Path.rglob` silently suppresses directory traversal errors, so the existing unreadable-file test is insufficient.

Correct traversal to fail closed on an unreadable root or any inaccessible source subtree instead of accepting a partial scan. Preserve existing comment/string/identifier handling and every current fixture. Add real owned-fixture regressions for unreadable root and unreadable nested directory, restoring permissions in `finally`; do not mutate global state. Changes are limited to `scripts/check-core-ui-imports.py` and `Tests/Packaging/test_core_ui_imports.py` plus the worker report.

## Finish R2 and freeze

R2's last run stopped after printing a long write-tool payload as plain text. Its source changes partly landed, but its body validator did not execute. The parent prepared an independent external validator so a large generated-script tool call is unnecessary:

```sh
python3 "$E/parent/validate_workflow_bodies.py" --out "$E/worker/r3/workflow-bodies"
```

It parses actual YAML and executes every exact run body against an owned fake runner, comparing **complete argv** and exit status for all seven gates, with normal/space-containing paths and producer exits 0/7 (28 cases). It never runs actual Swift/builder commands. Fix any actual invocation quoting failures only in `.github/workflows/ci.yml`; quote each runner/path argument independently. Single-line YAML quotes do not become shell quotes, so check all seven call sites, not only multiline ones. Preserve all prior CI requirements and raw receipt capture. Do not edit this parent validator.

Finish the mode/owner checks and controlled group-write regression from R2 in the allowed helper/test files. Rerun the affected focused helper/isolation tests, guard fixtures, real-tree guard and workflow validator. Retain exact raw argv/stdout/stderr/exit/duration; update `walkthroughs/M10-A-implementation.md` with accurate current results and prior-run limits. Existing builder/packaging observations remain valid only while shipping inputs stay byte-identical; parent already independently rebuilt and passed nine packaging checks on those unchanged inputs.

Submit a final candidate manifest, stop editing and report. The protected baseline failures, full-suite acceptance, user approval of the amendment, hosted AC08 and Git delivery remain pending. Do not claim M10-A complete.
