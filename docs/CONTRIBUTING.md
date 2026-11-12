# Contributing to the Agent Lens catalogue

Status: **M11-F contributor foundation.** The project is licensed under the **MIT License**
(owner's choice, 2026-11-12 — see [`LICENSE`](../LICENSE)). Contributions are **not publicly
invited yet**: opening the catalogue to public contributions remains a separate owner decision.
Until then, do not send unsolicited patches as if participation were open.

This guide covers the data-only path: adding a tool that already fits an existing layout. No
scanner, UI, or manager-adapter change is involved. Anything else needs an owner-authorized plan.

## Add a tool on an existing layout

Edit exactly these files:

1. `Sources/AgentLensCore/Detectors/DefaultDetectors.json` — one registry entry copied from a
   frozen identity row.
2. `Tests/AgentLensCoreTests/DetectorRegistryTests.swift` — the exact ordered id list, the fixture
   and category sequences, and the per-row assertions.
3. `Tests/AgentLensCoreTests/BundledRegistryResourceTests.swift` and
   `Tests/AgentLensAppSupportTests/BundleResourceTests.swift` — their exact id/display/executable
   lists.
4. `Tests/AgentLensCoreTests/UpdateCLIIntegrationTests.swift` — the synthetic PATH shadows and the
   exact invoked-tool set when the tool declares an extra search root.
5. `Tests/Packaging/test_dev_app_bundle.py` — the full-registry count/id list and the matching
   `bundle-preflight` expectation. The separate two-id fixture expectation is not touched.
6. `docs/capability-matrix.md` — one row in registry order, with the exact cells described below.
7. `Tests/AgentLensCoreTests/CapabilityMatrixTests.swift` — the hardcoded `frozenCatalogue` id
   list in `dataOnlyContributionLoadsExtraToolWithoutProductionChange`, extended with the new id
   in registry order. The same test parses `docs/capability-matrix.md`, so the row from item 6
   must land in the same change.
8. `README.md` — the `verify-installation` accepted-id sentence, kept truthful.

Do not add a detector for a second executable name, a desktop app, an IDE, or a package that only
*looks* related. The binding do-not-declare table is in
[`docs/catalogue-identities.md`](catalogue-identities.md); read it before proposing a package.

## Registry fields and closed vocabularies

The registry root is `{"schemaVersion": 2, "detectors": [...]}`. Schema 1 is rejected outright, and
unknown keys are rejected at every level. Each detector has these fields:

| Field | Required | Rule |
|---|---|---|
| `id` | yes | Non-empty, unique. Bundled entries keep `id == executableName` (the catalogue test enforces it). |
| `displayName` | yes | Non-empty human name. |
| `executableName` | yes | Non-empty executable basename; detection looks up this name only. |
| `extraSearchRoots` | no | String array. Only documented install destinations or explicitly observed legacy roots. Defaults to `[]`. |
| `fixture` | policy: yes | `{ "layout": <layout>, "expectedSource": <source> }`. |
| `category` | yes | Closed: `aiAgent`, `aiCodingTool`, `aiHarness`. |
| `packages` | yes | Array (may be empty) of `{ "manager": <manager>, "name": <package> }`; duplicates rejected. |
| `acceptedOperations` | no | Closed: `npmUpdate`, `npmUninstall`; no duplicates. Absent/empty means informational. |
| `informationURL` | no | HTTPS URL with a host and no user information. |
| `uninstallInstructionsURL` | no | Same HTTPS rule; only a real published instruction page. |
| `versionQuery` | yes | `{ "arguments": [...], "stream": <stream>, "line": <line> }`. |

Closed vocabularies:

- **Categories:** `aiAgent`, `aiCodingTool`, `aiHarness`.
- **Package managers:** `npm`, `homebrewFormula`, `homebrewCask` — nothing else is declarable in
  M11. uv, pip, pipx, cargo, bun, PyPI, MacPorts, and WinGet identities
  stay documentation-only until their ownership adapters exist.
- **Fixture layouts:** `npmGlobal`, `singleDirectory`, `brewCellar`.
- **Fixture expected sources:** `npm`, `brew`, `standalone`.
- **Version-query stream:** `stdout`, `stderr`.
- **Version-query line:** `first`, `firstNonempty`.
- **Version-query bounds:** 1–8 arguments; each argument non-empty, NUL-free, at most 256 UTF-8
  bytes; 1024 bytes total. The standard query is `["--version"]`, `stdout`, `first`; M11 entries all
  use it. No shell parsing, no `--help` fallback, no per-tool scripts.
- **Package names:** npm scoped/unscoped names per the validator; Homebrew names are a bare
  formula/cask or a fully qualified `user/repo/name` tap. Two path components are rejected.

A declared package is a **candidate**, never ownership proof, install proof, or permission to run
a manager command. Ownership verification remains diagnostic.

## Evidence rules

Every identity claim needs an evidence mark, exactly as used in
`docs/catalogue-identities.md`:

- `verified-docs` — re-confirmed against a primary source (official vendor docs, official
  repository, npm/PyPI/Homebrew registry listing, or the vendor's install script read as text).
  Record the source URL and fetch date.
- `observed-local` — measured read-only on the contributor's machine. It is evidence about that
  machine only, never a registry pin.
- `unverified` — not confirmed. State exactly what is missing and what would resolve it.

Primary sources only. Never copy a package name from memory, a blog post, an aggregator, or another
tool's output, and never guess a flag or version shape. "Unknown" is a valid registry outcome; a
fabricated identity is a defect.

## Fixtures and limits

A synthetic fixture proves the detector and the source classifier. It never proves that a vendor
installation exists, and an unobserved vendor layout is never described as "verified". The matrix
therefore writes `synthetic <layout>` — never "verified against the vendor".

Source classification is a heuristic: `/lib/node_modules/` resolves to `npm`, `/Cellar/` to
`brew`, everything else to `standalone`. Cask binaries under a Homebrew prefix, script installs,
uv/pip/pipx installs, git checkouts, and Tern stores all classify `standalone`. A path under a
Homebrew prefix is not formula proof.

- Personal artifacts are never roots or fixtures: signature shims, version stores, versioned
  runtime filenames, and Tern copies.
- Second executables are known limits, not detectors (`opencode2`, `hermes-agent`, `hermes-acp`,
  the `qoder` dispatcher).
- Vendor self-updaters are never Agent Lens operations.

## Mutation acceptance gate (D-021)

Detection never implies mutation eligibility. A new tool ships **informational**: no Update, no
Uninstall, even when npm ownership verifies. Promotion requires the entry's `acceptedOperations`
to contain the operation and a separately accepted, owner-authorized mutation scenario. Do not add
`acceptedOperations` as part of a data-only contribution, and do not present a matrix `yes` cell
without both the accepted operation and a declared npm candidate verified as npm-global.

## The capability matrix row

`docs/capability-matrix.md` is enforced by
`Tests/AgentLensCoreTests/CapabilityMatrixTests.swift`. One row per registry id, in registry order,
with these cells:

- `tested fixture`: `synthetic <layout>` using the registry fixture layout.
- `declared packages`: every candidate as `<manager>:<name>`, semicolon-separated, registry order;
  `none` when empty.
- `latest-check`: `yes: npm` only with an npm candidate; `yes: homebrewFormula` only with a formula
  candidate (both may appear, semicolon-separated); otherwise `disabled: <reason>`. A cask
  latest-check is never `yes`.
- `Update` / `Uninstall`: `yes: npm (verified npm-global copies only)` only for an entry whose
  `acceptedOperations` contains the operation and which declares an npm candidate; otherwise
  `informational: <reason>` or `disabled: <reason>`.
- `known limits`: non-empty, specific facts — deprecations, collisions, classification surprises,
  second executables, version-shape noise, and vendor-owned updaters.

## Local gates

Run from the repository root with both Agent Lens test overrides unset:

```sh
env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS swift build
env -u AGENT_LENS_TEST_SCRATCH -u AGENT_LENS_TEST_PRODUCTS swift test --no-parallel
python3 scripts/check-core-ui-imports.py
python3 Tests/Packaging/test_core_ui_imports.py
python3 scripts/build-dev-app.py --scratch-root <fresh-root> --configuration debug
python3 Tests/Packaging/test_dev_app_bundle.py --app <fresh-root>/AgentLensApp-debug.app
```

`--no-parallel` keeps the real-process timing bounds meaningful. The full suite must report zero
skips and zero failures. Use a fresh scratch root outside the repository and protected roots.

**Command Line Tools-only workstations.** If `swift test` fails before any test with
`TestingMacros … plugin not found`, rerun the same command once with the invocation-local
workaround below and record **both** runs:

```sh
swift test --no-parallel \
  -Xswiftc -plugin-path \
  -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
```

This is an environment workaround, not a repository change. Do not change `Package.swift`, the
toolchain, or `xcode-select`; hosted CI uses a full Xcode and must pass without the flag.

A new tool on an existing layout must make no source change under
`Sources/AgentLensCore/` other than the registry JSON, and no change under `scripts/**` or
`Tests/Packaging/**` beyond the named packaging list.
