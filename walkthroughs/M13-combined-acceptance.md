# M13 — combined Homebrew acceptance

**Decision: technically accepted on `milestone/m13-homebrew`.** The frozen product is
`00ed6ec1dd25e19446b7d8ab5477a4f120b666c9`. The checked acceptance candidate is
`17ff7fb269ea8ab77e12d0e4c8a6d375f33e64b1`, which adds only the CI floor calibration
(`de7e4c9`) and the capability matrix correction with its stale prose assertion removed.
No product source changed in M13-H. This record does not authorize a PR, merge, or release.

## Local and hosted gates

The orchestrator independently built and tested the frozen product in fresh scratch trees.
Serial Swift Build with the workstation's explicit CLT TestingMacros plugin passed **726 Core +
162 AppSupport = 888 tests**, with zero failures or skips. Both import guards, 21 guard fixtures,
the debug app build, and 9 packaging tests passed. The five matrix cases passed again after its
correction. The new verifier accepted the actual split and combined receipts and rejected weakened
counts and a missing anchor; only the four Swift floor values changed. `git diff --check HEAD`
passed on the H delta. A broader milestone-base diff separately flagged one trailing space in the
frozen Grok planning proposal; that historical file was not edited.

[Hosted run 45873711857](https://github.com/Hazem-Samak/agent-lens/actions/runs/45873711857)
passed on exact SHA `17ff7fb269ea8ab77e12d0e4c8a6d375f33e64b1` after the floor increase.
All producer and verifier exits were zero. The hosted runner reported one combined Swift summary,
not separate measured Core and AppSupport counts.

| Hosted gate | Observed result |
|---|---|
| Import guard | Pass |
| Guard fixtures | 21 passed, 0 skipped |
| Swift build | Pass |
| Isolation | 1 passed, 0 skipped |
| Full Swift suite | 888 passed, 0 skipped; all four existing anchors present |
| Development app build | Pass |
| Packaging | 9 passed, 0 skipped |

`check-receipts` artifact `15143972133`, SHA-256
`0a7c2c247e17bc46cffe21203625069d63fb6d86d0e9ea82ab0a70240d2920e0`. The frozen product also
passed all seven gates at [run 45866539533](https://github.com/Hazem-Samak/agent-lens/actions/runs/45866539533)
before the floors were raised. The protected-tree comparison against the milestone base was empty
for the CLI dispatch, npm sheets, established npm/formula probes and caches, earlier fixture suites,
packaging, resources, build scripts, and `Package.swift`.

## Contained Homebrew journeys

The real scratch manager was Homebrew `7.0.15-76-g456c79a` at pinned revision
`456c79a9946d416cac0b675850a33b169ccdc19a`. Mutations ran only in operator-owned disposable roots,
using an offline fixture tap, no IP networking, and a Seatbelt profile that allowed writes only
inside each fixture and to `/dev/null`. The promotion host used the product's registry grants,
without an overlay, and the production verifier and operation code.

| Registry ID | Exact package | Observed lifecycle |
|---|---|---|
| `hermes` | Formula `hermes-agent` | Cancel unchanged; update 0.23.1 → 0.24.0; uninstall and rescan |
| `aider` | Formula `aider` | Cancel unchanged; update 0.86.2 → 0.87.0; uninstall and rescan |
| `goose` | Formula `block-goose-cli` | Cancel unchanged; update 1.59.0 → 1.60.0; uninstall and rescan; Pressly `goose` refused and preserved |
| `kiro-cli` | Cask `kiro-cli` | Cancel unchanged; update 3.6.1 → 3.6.2; uninstall and rescan; zap sentinel intact |

The four scenarios passed **300 checks**. A separate real-manager fixture passed **173 checks**:
multi-keg residue, pin/dependent/broken refusals, binary and no-stanza app-cask lifecycles,
`auto_updates`/`:latest`/comma metadata, and artifact-guard refusal for stanza/unsafe casks.
The app-cask removal was a **manager fixture control**; Agent Lens itself refuses app artifacts
and uninstall stanzas. The Swift suite covered typed product refusals, stale proof, revalidation,
shared mutation exclusion, interruption, and post-launch reconciliation. The isolated real-npm
Codex journey passed update/uninstall, rejected the competing confirm before launch, and reconciled
an interrupted uninstall; the protected npm SwiftUI render host also passed. This was not a
deliberate interruption of real Homebrew.

## Native Accessibility and shipping CLI

The app's executable and bundled detector registry were byte-identical to the built candidate. A
scratch launch shim and unique bundle ID supplied the closed login-shell environment, outer
Seatbelt profile, and pinned Homebrew's inherited sandbox descriptor 198. The live descriptor
pointed to the scratch manager's `sandbox.rb`; no product hooks or registry grants were injected.

1. **Check Updates** showed Kiro CLI 3.6.1 with 3.6.2 available; **Verify Installation** verified
   `kiro-cli` as the Homebrew cask in the disposable prefix.
2. **Uninstall…** showed the exact scratch executable and `uninstall --cask kiro-cli`, the
   whole-cask and companion-app disclosure, the zap exclusion, and the 900-second bound. Return
   left the preview open; Escape dismissed it. All 6,234 prefix node records were byte-identical.
3. A fresh preview and explicit **Uninstall Package** produced **Uninstall Succeeded**, exit 0,
   `3.6.1 → —`, and a released selected target. The staged cask and linked executable were absent;
   the zap-target sentinel survived. After **Done**, inventory showed `Not installed` and zero updates.
4. The shipping CLI verified scratch ownership and agreed that Kiro 3.6.2 was available before
   uninstall. After uninstall it reported no live executable and zero updates. It also verified
   the disposable `hermes-agent` formula and reported 0.23.1 → 0.24.0. Both CLI environments
   resolved the scratch PATH without degradation.

The native measurement exercised a real cask uninstall, not an Accessibility-confirmed Update.
Updates were confirmed in the four product-host lifecycles. All package payloads were synthetic;
no vendor installations were mutated. Personal manifests matched across the product, manager,
native, and CLI windows: eight roots recorded, four present node files compared byte-for-byte,
including the personal Homebrew tree (Cellar and Caskroom), `/Applications`, and the recorded
cache, log, and application-data roots. Combined manifest SHA-256:
`6ae2c4f335445b368e0e4bb9d5741d98e1e65259399ac200bcf8271523994390`.

## Independent review and evidence index

DeepSeek V4.1 Flash free from Token Harbor implemented acceptance support outside the checkout.
The orchestrator ran the acceptance; Grok 4.7 High via Grok CLI and Gemini 4 Hydrogen Extra High
via Antigravity CLI reviewed the candidate and native evidence independently through Rex. Both
returned no product blockers and cleared the push for the hosted gate. Neither fallback was used.

Raw evidence remains outside the checkout in the retained operator scratch root
`$TMPDIR/agent-lens-m13-h.CiURBX0X`:

| Evidence | Relative location |
|---|---|
| Local commands, exits, test events, protected-file hashes and manifest comparisons | `local-receipts/` |
| Named product lifecycles and manager controls | `promotions/evidence/`, `corrected-scenarios/evidence/` |
| AX actions, Cancel hash, CLI before/after, immutable app payload and registry digests | `local-receipts/`, `review-input/` |
| Fixture containment, native personal and prefix manifests | `native-kiro-state/evidence/` |
| npm launch and reconciliation receipts | `npm-combined/`, `npm-render/` |
| Implementer support and independent review transcripts | `worker-primary/`, `implementer-rex.txt`, `grok-final-rex.txt`, `gemini-final-rex.txt` |
| Hosted SHA, artifact digest and downloaded check receipts | `hosted-h-run.json`, `hosted-h-artifact.json`, `hosted-h-receipts/` |

[D-024](../DECISIONS.md#d-024--opt-in-homebrew-cask-latest-check) records the new cask latest-check
contract. The authorized delivery target is the milestone branch only.
