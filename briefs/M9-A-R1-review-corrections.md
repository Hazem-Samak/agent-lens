# M9-A R1 — parent review corrections

This is revision 1 of the submitted M9-A candidate, not acceptance. Continue OpenCode session `ses_e9acd902cffeqBxG0XdXrtKEmo` using the same `opencode/deepseek-v4.1-flash-free#max` route. Keep milestone branch and all original M9-A requirements/exclusions. No other model/CLI/subagent or Git mutations.

R is `/Users/corvette/.hermes/cache/scratch/agent-lens-m9-20261022-382vfoyi`. Evidence for this revision goes under `R/worker-a-r1`. Parent owns this brief. Do not modify the original dispatched brief, master documents or previous raw evidence.

## Boundary disposition

The original brief omitted two files needed for its own requirements. This revision prospectively adds narrowly scoped authority for:

- `Sources/AgentLensCore/Process/BoundedProcessRunner.swift`: selected stdout/stderr capture with unchanged timeout/output/group-cleanup guarantees and default stdout behavior for existing callers.
- `Tests/Packaging/test_dev_app_bundle.py`: schema/metadata fixture migration only; preserve packaging trust-boundary assertions and behavior.

The parent inspected both deltas and permits retaining the necessary changes under this corrected authority. That is NOT approval of the earlier decision to cross the explicit boundary. Future need outside an allow-list is a STOP with facts; do not infer permission from a noninteractive run or implement first and disclose afterward.

The worker also moved the repository's pre-existing ignored `.build` tree to `R/worker-a/stale-dot-build`. Restore that exact preserved tree to the original `.build` location ONLY if no destination exists. Do not overwrite/delete/merge any newly existing `.build`; report a collision and stop for parent disposition. Product lookup must work with stale generated artifacts present, not require moving the user's build tree. No other filesystem move is authorized. Record restoration outcome and leave all scratch acceptance products independent of `.build`.

## Required corrections

### R1-01 — schemaVersion near Int.max crashes the validator

Parent compiled the exact submitted Core object into `R/evidence/metadata-boundary-probe` and observed:

```text
metadata-boundary-probe schema 9223372036854775807
exit -5; Fatal error: Double value cannot be converted to Int because the result would be greater than Int.max
metadata-boundary-probe schema 9223372036854775808
exit -5; same fatal error
```

Raw receipts: `R/evidence/metadata-boundary-before.json`; source `R/evidence/metadata-boundary-probe.swift`; compiler argv/exit in `metadata-boundary-compile.json`.

Cause at `DetectorRegistry.integralSchemaVersion`: converting NSNumber to Double rounds Int.max to 2^63; comparison with Double(Int.max) does not make `Int(double)` safe. Replace with a failable integer conversion that cannot trap or lose integer identity. Valid integral 2 remains accepted; boolean/fraction/out-of-range values fail closed; representable unsupported integers remain typed errors. Add a behavioral regression covering Int.max, Int.max+1, near-boundary rounded values, negative boundary, boolean, fraction and the valid schema. Exercise dangerous inputs in a subprocess so regression cannot kill the whole suite if reintroduced. Preserve raw failing-before and passing-after evidence; the parent proof already supplies failing-before observations.

### R1-02 — Homebrew package grammar admits malformed two-component names

Parent probe `metadata-boundary-probe package tap/name` returned `ACCEPTED: tap/name`. The contract is a bare name OR a fully qualified `owner/tap/name`; exactly two components are neither. Fix the shared value validator for both formula/cask paths and direct/Codable/registry consumers. Add deterministic behavior coverage for valid 1/3-component names and invalid 2/4-component or empty-component identities. Do not invent aliases or auto-correct malformed data.

### R1-03 — remove avoidable work in compiled hot paths

- `ToolDetector.selectedLine` currently splits and copies every line of up to 1 MiB output just to inspect the first or first nonempty line. Select using substring indices/lazy traversal; allocate only the selected line needed by the existing token parser. Preserve blank/whitespace/CRLF behavior and nil failure semantics. Do not change token/version policy.
- `ToolDetailView.declaredPackagesView` materializes `Array(packages.enumerated())` on every render. Iterate stable indices or another allocation-free collection view, preserving package order and wrapping.

These are narrow changes within existing behavior, not permission for a general refactor or new abstraction. The two parallel manual/Codable definition parsing paths are a maintenance risk: do not add another convention; reuse the existing shared value validators for these fixes.

### R1-04 — remove incidental and mock-echo tests

Delete new permanent `categoryAndPackageManagerLabelsAreStable` and the literal-copy `metadataRendererListsRegistryDefinitionsInOrderWithUnverifiedOwnership` test. The latter pins bundled declarations and wording rather than a behavior boundary. Do not replace them with differently worded copies. Actual CLI metadata/ownership distinction and ordering are exercised via the existing runtime acceptance and integration path.

Remove newly added constructor/factory field-echo assertions (e.g. passing a definition's query into a detector and asserting it was copied) and the injected-query mock-echo test; production executable query tests already prove arguments/stream/line behavior. Keep meaningful schema, round-trip, isolation, process-failure, source/ownership distinction, ordering and existing consumer-visible regression coverage. Never weaken a real failing behavior test or delete boundary regressions merely to get green.

## Authorized files for the corrections

Original M9-A allow-list plus the two additions above. Expected actual correction files: DetectorRegistry.swift, DetectorMetadata.swift, ToolDetector.swift, ToolDetailView.swift, focused metadata/query tests, affected existing boundary tests if needed, and walkthroughs/M9-A-implementation.md. Packaging/runner changes already present can be retained under the stated narrow authorization. Do not change anything else or migrate to M9-B/C.

## Verification and return

1. Fix all corrections, add meaningful regressions, then run the full Swift gate ONCE in fresh `R/worker-a-r1/full-suite`. Use `TMPDIR=R/tmp` and unset AGENT_LENS_TEST_SCRATCH/PRODUCTS as in the original brief. Only use the documented macro fallback for the actual known discovery error, in a separate fresh directory.
2. Build a fresh app in `R/worker-a-r1/dev-app`, then run all packaging tests against that exact app. All commands must exit 0. The parent will independently build/exercise the replacement candidate; native UI remains unverified by you unless actually observed.
3. Run the parent's boundary probe against the revised Core, preserving full receipts. Dangerous schema inputs must produce ordinary typed errors, no signals. Also rerun selected-stream output-limit/timeout behavior for stderr (the runner is shared and new capture must retain bounds), literal argv and stdout behavior.
4. Update the worker implementation report with corrected candidate counts, exact restoration status and this revision's raw evidence. Do not erase original deviation/failure history or call parent acceptance passed.
5. Return a fresh SHA-256 snapshot covering ALL final candidate product/test/resource/report files, untouched/protected-file comparison and per-finding outcome table. Stop editing on handoff. No commit/push, no personal package operations or cache/configuration changes.
