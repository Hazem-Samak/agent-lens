# River RC1/RC2 correction evidence

Coordinator-run receipts for the revised candidate; see [corrections and results](../M10-B-river-corrections.md). Every top-level gate has `.json`, `.stdout` and `.stderr`; JSON contains the exact argv, exit, elapsed time and test isolation settings. The fresh full suite has397 Core +71 AppSupport passing tests. Guard21, fresh debug-builder and packaging9 receipts are final-candidate results, distinct from the old baseline-era receipts discussed in River R1.

`red.*` preserves the original deadline-mapping failure and the removed harness-only exact root-count assumption. `targeted.*` records both corrected regressions passing. `delta-from-river-r1.json` confirms the two-file code delta. External transport/native/CLI sources and receipts support the normal-path rerun against final fresh objects; their runtime substitutions are outside product code and assert public pins before redirection. No binaries, environment dumps, npm package install trees or personal cache files are retained here.

`SHA256.json` fingerprints this evidence set. Earlier evidence and the full River R1 report remain separate and unchanged. Hosted CI is still pending conditional commit/push and exact-SHA verification.
