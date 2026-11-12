# M11 — combined acceptance: original catalogue and contributor foundation

Date: 2026-11-12. Orchestrator: Qoder (Herdr `t7x`). Milestone branch: `milestone/m11-catalogue`.
**Combined candidate: `b07e321d13e1d380a8b371ba0636892c51ada38c`** (pushed to origin; no merge,
no release).

**Decision: M11 is TECHNICALLY ACCEPTED on `milestone/m11-catalogue`.** All six implementation
phases are individually accepted; the combined gate passes locally and on all seven hosted gates
at the exact candidate SHA. Git delivery to `main` and any release remain separate owner
authorizations.

## Phase acceptances (all on the milestone branch)

| Phase | Candidate | Result | Record |
|---|---|---|---|
| M11-A identity freeze | `c48b226` | accepted — 14/14 identities, 5/5 scratch measurements | [M11-A](M11-A-acceptance.md) |
| M11-B mutation gate | `caae348` | accepted — D-021/D-022; both reviews PASS; native spot-check | [M11-B](M11-B-acceptance.md) |
| M11-C settled batch | `5a0fb54` | accepted — six entries, anchor rename | [M11-C](M11-C-acceptance.md) |
| M11-D collision batch | `cdd8ccc` | accepted — twelve entries, collision regression; both reviews PASS | [M11-D](M11-D-acceptance.md) |
| M11-E remainder | `28738dc` | accepted — fourteen entries | [M11-E](M11-E-acceptance.md) |
| M11-F matrix/contributor | `d3f0324` + R1 | accepted — both reviews PASS; Grok LOW corrected | [M11-F](M11-F-acceptance.md) |

Implementer for all phases: DeepSeek V4.1 Flash 1017 via OMP (`river`), max reasoning (owner-
selected). Independent reviewers: MiniMax M3.1-Flash/xhigh (mcode) and Grok 4.7/high (grok CLI) —
mandatory for B/D/F, all PASS. Planning council and judgments: `briefs/M11-planning/`.
All agents summoned and managed through Herdr panels + hc only (owner rule).

## Combined gate results (orchestrator-run, D-014)

### 1. Local gates at the exact candidate SHA (`R/evidence/combined/`)

- Full suite: **467 Core + 80 AppSupport = 547 passed, zero skips/failures**, exit 0
  (`full-suite.log`; invocation-local TestingMacros plugin path on the CLT-only workstation —
  the documented M11-C/D/E environment workaround; no package/toolchain change).
- Core/UI import guard: clean (32 Core files). Guard behavioral fixtures: 21 OK.
- Protected-file SHA-256 manifest: clean at the candidate (450 tracked files).

### 2. Hosted gates — all seven at the exact SHA

[Run 43288284409](https://github.com/Hazem-Samak/agent-lens/actions/runs/43288284409), push event,
headSha `b07e321d13e1d380a8b371ba0636892c51ada38c`, conclusion **success**
(macOS 15 runner, Xcode 26.3, full receipt log `hosted-43288284409.log`):

1. Core/UI import boundary guard — verification OK.
2. Core/UI guard behavioral fixtures — 21, OK.
3. Build package — OK.
4. Early isolation capability gate (native macros) — 1 test passed, OK.
5. Full Swift test suite — **"Test run with 547 tests in 5 suites passed"**; the renamed anchor
   `bundledDefaultDetectorsMatchFrozenCatalogue` appears as a PASSED event; floors 467/80/547 met.
6. Build debug development app — OK.
7. Packaging checks — all nine, OK.

### 3. CLI/app fact agreement

CLI and app load the same bundled registry. Orchestrator observed the built CLI `scan --offline`
(fourteen entries, truthful states/versions) and the native app list/details (M11-B native
spot-check: codex accepted path intact; unaccepted entries informational with the Core reason;
grok no Manage section). Preflight `registry_count=14 registry_ids=codex opencode grok claude
gemini cline hermes aider goose kiro-cli omp agy dsh qodercli` asserted by packaging.

### 4. End-to-end data-only contribution proof (ROADMAP M11 acceptance clause)

A synthetic fifteenth tool (`contrib-e2e-tool`, singleDirectory/standalone, absolute scratch
root) was added by editing ONLY `DefaultDetectors.json` in the working tree:
- built CLI detected it: `Contrib E2E Tool 9.9.9 standalone (not on PATH)` (`e2e-cli-scan.log`);
- built native app displayed it: "Contrib E2E Tool, contrib-e2e-tool, Installed off PATH"
  (`e2e-app-15th-tool.png`);
- no `Sources/**` scanner/UI edit, no new layout/manager;
- registry restored byte-identically afterwards (pre/post SHA-256
  `9c82605c…718dc` match; `registry-pre.sha`/`registry-post.sha`); working tree clean at the
  candidate SHA. The permanent unit proof (`dataOnlyContributionLoadsExtraToolWithoutProductionChange`)
  ships in the suite.

### 5. Safety regression

- Mutation gate: only codex carries `acceptedOperations`; every other entry informational
  (D-021). Gate refusal proven before any process/scratch (M11-B tests + native observation).
- Collision regression: `bundledRegistryNeverDeclaresCollisionIdentities` with seeded controls in
  all three manager branches; no do-not-declare identity declared.
- M10 codex journey: suites unweakened; native Verify→Uninstall control intact (M11-B spot-check).

## Requirement-to-evidence summary (ROADMAP M11)

| Requirement | Evidence |
|---|---|
| Every named entry resolved with validated fixture | 14 frozen identity rows (M11-A) + synthetic fixture per entry (suite) |
| Measured version behavior where available | 5 scratch + 14 local measurements (M11-A); unknown-safe elsewhere |
| CLI/app facts agree | Same registry; observed CLI scan + app list/details; preflight id list |
| Data-only contribution without scanner/UI changes | Unit proof + end-to-end fifteenth-tool proof (above) |
| Capability matrix published | `docs/capability-matrix.md`, test-enforced truth (M11-F) |
| Registry/fixture contribution documented | `docs/CONTRIBUTING.md` (license pending owner choice; no public invitations) |
| Categories/links | Scope §2 categories; HTTPS links validated; canonical URLs frozen |

## Limits (honest, carried forward)

- **License (OD-7) remains the owner's open choice** (MIT vs Apache-2.0); no LICENSE file; public
  contribution invitations closed until chosen (no later than M18).
- New entries are informational for mutation; per-tool promotion requires separate owner-authorized
  controlled scenarios (OD-5). Homebrew/uv/Cargo adapters remain M13–M15.
- Aider cold start (3747 ms) exceeds the 3 s query budget → unknown on cold start; budget unchanged.
- gemini-cli formula disabled 2026-12-18 (replacement cask antigravity-cli); cline formula disabled
  2027-05-18 — matrix limits, entries kept (OD-6).
- Source classification is heuristic (cask/script/uv/git/Tern → standalone); documented per row.
- Matrix regression pins the seven critical limit markers; the full limit set is content-verified
  (M11-F INFO-2) — widening is a future-phase decision.
- Homebrew Cellar/Caskroom trees were never installed/observed; fixtures are synthetic.
- The M8 keyboard-only Copy/Reveal measurement remains open and is a required M12 gate.
- CLT-only workstation needs the invocation-local macro-plugin flag for local suites; hosted CI
  (full Xcode) is unaffected.

## Owner authorizations still required

1. Merge of `milestone/m11-catalogue` to `main` (Git delivery) — NOT authorized by this acceptance.
2. License choice before any public contribution invitation.
3. Any per-tool mutation promotion scenarios.
4. M12 dispatch (next milestone per ROADMAP) — separate owner decision.
5. Optional diagnostic beta after M12 (ROADMAP §7) — separate owner decision.

## Evidence index

`R = /Users/corvette/.hermes/cache/scratch/agent-lens-m11-Jb11B5`:
`evidence/combined/` (full-suite.log, guard logs, hosted-43288284409.log, e2e-build/cli/app logs,
e2e-app-15th-tool.png, registry-pre/post.sha, registry-backup.json); per-phase `evidence/{b,c,d,e,f,f-r1}/`
(worker + orchestrator gate logs, native spot-check screenshots, changed-file hashes);
`evidence/protected-manifest.txt`; phase walkthroughs and reviews under `walkthroughs/`.