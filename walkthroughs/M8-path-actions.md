# M8 — Copy Path and Reveal in Finder

Status: **user-approved for delivery, 2026-10-18 (Africa/Cairo)**. Independent automated gates and two final code reviews passed. The user approved the UI and authorized commit, push, and branch cleanup with “all good, clean branches comm push all”. Native keyboard-only activation remains **unverified**; approval and delivery are not recorded as evidence that this check passed. No global keyboard preference was changed.

The frozen [M8 brief](../briefs/M8-path-actions.md) remains the historical plan, including its original planning-only header. Session instructions subsequently authorized implementation and delivery.

## Behavior and ownership

Tool details offer Copy Path and Reveal in Finder beside both Selected Entry and Resolved Target. Paths come from the selected winner/off-PATH candidate, not possibly-relative detected-tool text. Entry and recorded target remain distinct, even when identical.

The immutable AppSupport target enforces supplied, nonempty, absolute, NUL-free path validity with one shared validator. Selection gates disable absent/inconsistent/not-installed paths. Copy preserves exact displayed text without quoting or existence checks. Reveal uses native file URLs and lstat directory-entry semantics, allowing an extant broken symlink to be selected. Missing or inaccessible paths block Finder requests and suggest Rescan. Feedback says selection was requested, not that Finder acknowledged display.

All AppKit/Darwin effects belong to the app target. Native labels distinguish tool, row, and action. Structured row identity resets feedback when tool/path/eligibility changes. Scan/update behavior, Core/CLI, package/dependencies, registry, existing tests, and packaging code were unchanged.

## Team and corrections

- Sole implementer: DeepSeek V4.1 Flash free via WorkBuddy/Pi (`workbuddy/deepseek-v4.1-flash`).
- Independent reviewer: Gemini 3.8 Flash via Antigravity, High (`gemini-3.8-flash`).
- Independent reviewer: MiMo v2.6 Flash Free via OpenCode (`opencode/mimo-v2.6-flash-free`).
- All three routes completed a simple reply test. The user replaced an expired OpenCode API key before MiMo's successful reply; no key value was read or archived.
- Both final reviews returned PASS. Gemini reconfirmed through working Python/exec reads after its direct read tool failed. Reviewers remained read-only; frozen hashes did not drift.
- Parent review reproduced a public-constructor validation bypass using fake effects and corrected missing-only wording that was inaccurate for permission denial. DeepSeek fixed both within the four-file scope, with additional regressions.

Configured routes and successful replies do not independently attest upstream provider identity or effective reasoning.

## Independent evidence

Local external evidence root:

```text
R = /Users/corvette/.hermes/cache/scratch/agent-lens-m8-20261017-223126
```

These are machine-local artifacts, not files included in this repository.

| Parent-observed gate | Result | Raw evidence under R |
|---|---|---|
| Baseline Swift | 184 Core + 38 AppSupport = 222 passed, exit 0 | evidence/baseline.log and .exit |
| Final fresh Swift | 184 Core + 62 AppSupport = 246 passed, exit 0 | evidence/parent-r2-suite.log, .exit, .command.json |
| Fresh development app builder | exit 0 | evidence/parent-r2-builder.log, .exit, .command.json |
| Packaging against that app | 9 passed, exit 0 | evidence/parent-r2-packaging.log, .exit, .command.json |
| Invalid-target fake-effect probe before correction | 8 violations, exit 1 | evidence/parent-invalid-policy-r1.log and .exit |
| Same probe after correction | zero callbacks for invalid paths, exit 0 | evidence/parent-r2-policy.log and .exit |
| Frozen implementation hashes | no drift | evidence/pre-review-r2.json, final-r2.json, delivery-approved.json |

Worker runtime RED/GREEN evidence is separate from parent acceptance: initial Copy/existence regression failed then passed; constructor regressions produced 47 issues in 24 tests, then 24 tests passed. R1's pre-fix source artifact was reconstructed after GREEN; R2's pre-fix snapshot was captured after runtime RED and before restoring GREEN. The initial R1 outer-shell exit capture was bogus and is excluded as a gate. Raw logs remain under `R/worker` and `R/worker/r2`.

Final reports: `R/evidence/parent-candidate-verification.md`, `review-r2-mimo.json`, `review-r2-gemini-followup.json`, and `R/worker/r2/implementation-report.md`. Exact frozen source/test copies are under `R/evidence/final-sources`.

Toolchain: Apple Swift 6.4 (swiftlang-6.4.0.34.1), swift-driver 1.168.6, arm64; macOS 27.0.1 (26A434). Zeron orchestration (0.2.113 observed during model preflight); T3 build is not applicable. New views reuse the existing explicit State storage pattern because the local builder could not expand the State macro. No package/toolchain fix was made.

## Native observations and limits

The independently built actual app at `R/parent-r2-dev-app/AgentLensApp-debug.app` copied Codex's displayed entry and target exactly, and Finder visibly selected each intended item. Switching to OpenCode cleared feedback and Copy used the newly selected path.

An isolated external native host copied 28 product source/resource files byte-for-byte, excluded the product entry point from its build, and injected synthetic services. It is not the actual product entry app. Fixture observations covered literal special characters, entry versus target, broken symlinks, disappeared files, retained failed-rescan snapshots, retargeting followed by rescan, feedback reset, off-PATH/missing tools, and 760-point wrapping. Focused final checks exercised the constructor correction, actual product actions, and permission denial: a test-owned directory at mode 000 caused errno 13, showed missing-or-inaccessible feedback, and still allowed exact Copy; mode 0755 was restored.

Eight clipboard equality receipts and two restoration confirmations are in `R/native-host/native-receipts.jsonl`. Prior clipboard content was held only in process memory and never logged. Finder/view observations are recorded in the conversation's CUA transcript; no screenshot file archive is claimed.

Keyboard-only activation was not observed because normal keyboard navigation was off. Test-only preference/getter experiments did not prove traversal and were removed from the final host. Spoken VoiceOver was not exercised; AX labels and error text were observed. Pasteboard-failure policy was tested with injected closures, not by forcing a real clipboard failure. A filesystem race between lstat and Finder handling remains possible.

## Reproduction

Use fresh external scratch and retain actual stdout/stderr/exit codes:

```sh
m8_root="$HOME/.hermes/cache/scratch/agent-lens-m8-$(uuidgen)"
mkdir -p "$m8_root/tmp"
env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS \
  TMPDIR="$m8_root/tmp" swift test --scratch-path "$m8_root/full-suite"
TMPDIR="$m8_root/tmp" python3 scripts/build-dev-app.py \
  --scratch-root "$m8_root/dev-app" --configuration debug
TMPDIR="$m8_root/tmp" python3 Tests/Packaging/test_dev_app_bundle.py \
  --app "$m8_root/dev-app/AgentLensApp-debug.app"
git diff --check
```

The documented TestingMacros fallback in the frozen brief applies only to the known discovery failure; the parent's final plain Swift test invocation passed. Default-Darwin-TMPDIR portability remains outside M8. No signing, notarization, installation, or public app release is claimed.
