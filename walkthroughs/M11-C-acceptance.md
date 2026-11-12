# M11-C — settled registry batch: orchestrator acceptance record

Date: 2026-11-12. Orchestrator: Qoder (Herdr `t7x`). Phase brief:
[briefs/M11-C-settled-registry.md](../briefs/M11-C-settled-registry.md) (frozen at `a77b29b`).
Implementer: DeepSeek V4.1 Flash 1017 via OMP (`river`), max reasoning, sole writer.

**Decision: M11-C is technically accepted.** The bundled registry now ships six entries
(`codex`, `opencode`, `grok`, `claude`, `gemini`, `cline`); the CI anchor names the real test
function; all gates orchestrator-rerun. Data-only phase: orchestrator acceptance per ROADMAP §5.4
(no standing independent review; the mutation gate was reviewed in M11-B).

## Requirement-to-evidence results

| Requirement | Result | Evidence |
|---|---|---|
| Registry rows match the frozen packet | PASS | Full diff review: claude/gemini/cline rows exact (packages incl. `claude-code@latest`, fixtures, categories, URLs, extraSearchRoots); `acceptedOperations` absent on all new entries; codex seed intact; order preserved |
| OpenCode corrections | PASS | Core formula `opencode` added; informationURL → `https://opencode.ai/docs/`; uninstall → `https://opencode.ai/docs/cli/#uninstall` (frozen M11-A correction) |
| Anchor rename synchronized | PASS | `bundledDefaultDetectorsMatchFrozenCatalogue` in the test AND `CORE_ANCHORS` AND the stream description; floors unchanged (456/79/535); no other ci.yml change |
| Exact-set assertions stay exact | PASS | Renamed test asserts full ordered id list, fixtures, categories, packages, URLs, acceptance; id lists updated in BundledRegistryResourceTests, BundleResourceTests, UpdateCLIIntegrationTests, test_dev_app_bundle.py; two-id fixture expectation untouched |
| Full gates (orchestrator rerun) | PASS | build exit 0; suite 463+80=543 exit 0 (see D-1); import guard 32 files clean; 21 guard fixtures OK; fresh dev app exit 0; 9 packaging OK (`R/evidence/c/parent-*.log`) |
| Preflight | PASS | `registry_count=6 registry_ids=codex opencode grok claude gemini cline` (packaging test asserts it; worker preflight transcript) |
| CLI parity (C-AC05) | PASS | Orchestrator ran built `agent-lens scan --offline`: six entries, correct names/categories; Claude/Gemini not installed → `–`; Cline 3.0.74; Codex version unknown (measured optional-dependency failure); OpenCode 2.2.7 via extra root |
| Scope | PASS | Only the 8 allow-listed files + worker walkthrough; protected manifest otherwise clean; no production Swift change |

## Deviations assessed

- **D-1 (toolchain plugin path): ACCEPTED as an environment workaround, not a repo change.**
  The CLT-only workstation (`xcode-select -p` → `/Library/Developer/CommandLineTools`, no
  Xcode.app) fails `swift test` with `TestingMacros … plugin not found` before any test runs.
  The orchestrator reproduced the failure with the exact documented command, then reran with the
  invocation-local flag
  `-Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing`
  → 543 passed, exit 0 (`parent-02b-suite-pluginpath.log`). No package, toolchain, or xcode-select
  change (M6 precedent: invocation-local macro-plugin loading). Hosted CI uses full Xcode 26.3 and
  is unaffected. The failed exact run is retained (`parent-02-suite.log`).
- **D-2 (CLI invocation set): ACCEPTED.** `UpdateCLIIntegrationTests` asserts the exact injected
  set of four synthetic PATH tools (codex/opencode/grok/claude); gemini/cline declare no extra
  roots and are truthfully absent on the closed fixture PATH. `claude` is shadowed because it
  declares `~/.local/bin` — without the shadow a real native Claude install would execute and
  break hermeticity. The six-entry catalogue is asserted by the registry/loader tests and the
  orchestrator CLI scan. No assertion weakened.

## Limits and carry-forward

- Cline's PATH winner on this machine is the personal signature shim → `standalone` heuristic
  source; documented known limit (identity packet), not a defect.
- New entries are informational (no acceptance) per D-021; the Manage section shows the gate
  reason for npm-declared unaccepted entries (M11-B behavior, unchanged here).
- Floors remain 456/79/535 until M11-F raises them to the measured count.
- No native UI spot-check required for a data-only phase beyond preflight/packaging; M11-B's
  native evidence covers the gate UI. No merge, no release.

## Team and process

Sole implementer DeepSeek V4.1 Flash 1017/OMP max. Herdr/hc orchestration only. Candidate frozen
by the orchestrator after gate reruns; worker terminal retired after acceptance.