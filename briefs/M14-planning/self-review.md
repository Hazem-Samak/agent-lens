# M14 Planning — Two-Pass Adversarial Self-Review Record

- **Date:** 2026-11-27
- **Target Plan:** `briefs/M14-plan.md`
- **Review Mode:** Owner-directed solo planning with two mandatory adversarial self-review passes before branch creation and commit.

---

## Pass 1 — Codebase Symbol, Path, Allow-List & Test-Pin Alignment Audit

In Pass 1, every file path, struct/enum definition, JSON schema key, and test assertion referenced in the initial draft of `briefs/M14-plan.md` was cross-checked against the live repository at `main` (`882afd3517cda6f10c901dd973dc8f5e4083b2c2`).

### Defects Identified & Resolved in Pass 1

1. **`P1-1` — Directory & File Path Alignment (`Sources/AgentLensCore/Detection/` and `Sources/AgentLensApp/`):**
   - **Defect Found:** The initial draft placed `DetectorMetadata.swift` and `ToolDetector.swift` under `Sources/AgentLensCore/Detectors/` and SwiftUI views under `Sources/AgentLens/Views/`, and combined `uv` update/uninstall operations into a single `UvToolOperationCoordinator.swift`.
   - **Codebase Fact:**
     - `DetectorMetadata.swift`, `DetectorRegistry.swift`, and `ToolDetector.swift` reside in `Sources/AgentLensCore/Detection/` (only `DefaultDetectors.json` resides in `Sources/AgentLensCore/Detectors/`).
     - All SwiftUI views (`ToolDetailView.swift`, `OwnershipVerificationView.swift`, `SettingsView.swift`, `MainWindow.swift`, `HomebrewUpdateOperationView.swift`, `HomebrewUninstallOperationView.swift`) reside directly in `Sources/AgentLensApp/`.
     - Core operations follow the per-operation file pattern (`NpmUpdateOperation.swift`, `NpmUninstallOperation.swift`, `HomebrewFormulaUpdateOperation.swift`, `HomebrewFormulaUninstallOperation.swift`, `HomebrewCaskUpdateOperation.swift`, `HomebrewCaskUninstallOperation.swift`).
   - **Fix Applied:** Corrected every path in `R1`–`R16` and the `R13`/`R14`/`R16` tables (`Sources/AgentLensCore/Detection/...`, `Sources/AgentLensApp/...`, `UvToolUpdateOperation.swift`, `UvToolUninstallOperation.swift`, `PyPIUpdateMetadataCache.swift`).

2. **`P1-2` — Exact Core Model & Schema Property Names (`packages`, `executableName`, `VerifiedInstallation`, `VersionStatus`):**
   - **Defect Found:** The initial draft referred to `allowedPackageManagers` / `executable` on `DetectorDefinition`, `InstallationOwnershipRecord`, and `VersionCheckResult.outdated`.
   - **Codebase Fact:**
     - `DetectorDefinition` uses `packages: [DeclaredPackage]` (JSON key `"packages"`) and `executableName: String`.
     - `InstallationOwnership.swift` defines `VerifiedInstallation`, `InstallationOwnershipReason` (`CaseIterable`), and `InstallationOwnershipOutcome` (`.verified(VerifiedInstallation)` / `.unknown(InstallationOwnershipReason)`).
     - `VersionStatus.swift` defines `VersionScheme` (`.semanticVersion`, `.homebrewStable`) and `VersionStatus` (`.upToDate`, `.updateAvailable`, `.unknown(installed:reason:)`). `DetectorDefinition` does not store `versionScheme` in `DefaultDetectors.json`; update probes pass `VersionScheme` to `VersionStatus.evaluate`.
   - **Fix Applied:** Updated `R1`, `R2`, `R3`, and `R10` to use the exact `packages`, `executableName`, `VerifiedInstallation`, `InstallationOwnershipReason`, `VersionScheme.pep440`, and `VersionStatus` symbols, avoiding any schema change to `DetectorDefinition` for `VersionScheme`.

3. **`P1-3` — Pinned Validation Strings & Test Assertions in `DetectorMetadata.swift`, `DetectorRegistry.swift`, and `DetectorMetadataTests.swift`:**
   - **Defect Found:**
     - `DetectorMetadataTests.swift` line 139 (`unknownPackageManagerIsRejectedWithTheManagerField`) uses `"pip"` as its test fixture for an unknown package manager!
     - Both `DetectorMetadata.swift` (line 91) and `DetectorRegistry.swift` (line 552) validate `PackageManager(rawValue:)` and emit `"must be one of npm, homebrewFormula, homebrewCask"`.
     - `DetectorMetadata.swift` (line 213) and `DetectorMetadataTests.swift` (line 294) pin `"must be one of npmUpdate, npmUninstall, homebrewFormulaUpdate, homebrewFormulaUninstall, homebrewCaskUpdate, homebrewCaskUninstall"`.
   - **Fix Applied:** Added `Sources/AgentLensCore/Detection/DetectorRegistry.swift` to the `M14-B` allow-list alongside `DetectorMetadata.swift` and `DetectorMetadataTests.swift`, documented the exact updated error strings in `R1` and `R4`, and specified replacing `"pip"` with `"cargo"` in `unknownPackageManagerIsRejectedWithTheManagerField`.

4. **`P1-4` — Test Allow-List Completeness Across `M14-B`, `M14-C`, `M14-D`, and `M14-F`:**
   - **Defect Found:** Adding cases to `PackageManager`, `VersionScheme`, and `UnknownReason` requires updating tests in `OwnershipVerificationTests.swift`, `VersionComparisonTests.swift`, `VersionStatusTests.swift`, `UpdateProbeCoordinatorTests.swift`, and `InventoryServiceTests.swift`, plus `MainWindow.swift` in `M14-F`.
   - **Fix Applied:** Added all five test files and `MainWindow.swift` to their respective phase allow-lists in `R13`.

---

## Pass 2 — Safety Invariants, PEP 440 / `uv` / `pip` Edge-Case & Acceptance Rigor Audit

In Pass 2, the updated plan was audited specifically for TOCTOU security seams, Python virtual environment mechanics, multi-manager routing edge cases when `uv` is not installed on the host, PEP 440 parsing corner cases, and operations lifecycle contracts.

### Defects Identified & Resolved in Pass 2

1. **`P2-1` — `VerifiedInstallation` Manager Identity Binding for `.pip` Without Requiring Global `pip` on `PATH`:**
   - **Defect Found:** `VerifiedInstallation` requires `managerEntryPath`, `managerTarget`, and `managerFingerprint: ExecutableFingerprint`. If `PipOwnershipProbe` required resolving a global `pip` executable on `PATH`, virtual environments where `pip` is not on the global `PATH` (or where the environment was created by `python -m venv` / `pipx`) would fail verification with `.managerUnavailable`.
   - **Fix Applied:** Specified in `R1.6` that `PipOwnershipProbe` binds `managerEntryPath`, `managerTarget`, and `managerFingerprint` to the target environment's own `<env-root>/bin/python3` (or `<env-root>/bin/python`) observed via `FileIdentityObserver.observeExecutable`, and attaches `public let pythonEnvironment: PythonEnvironmentMetadata?` (defaulting to `nil`) on `VerifiedInstallation`.

2. **`P2-2` — Multi-Manager Routing When `uv` Is Not Installed on a Host with a `pip` Virtualenv:**
   - **Defect Found:** Because `aider` and `hermes` declare both `uvTool` and `pip`, routing to `verifyUvTool` before checking whether `<env-root>/uv-receipt.toml` exists would return `.unknown(.managerUnavailable)` on hosts without `uv` (such as this workstation's default `PATH`) instead of verifying a valid `pip` / `pipx` virtualenv!
   - **Fix Applied:** Updated `R1.3` so the Anchored Python Environment Classifier inspects `<env-root>/uv-receipt.toml` via local `lstat` *before* requiring `uv` on `PATH`: if `uv-receipt.toml` is absent and `<env-root>/pyvenv.cfg` or `<env-root>/lib/python*/site-packages` is present, it routes directly to `verifyPip` with zero dependency on `uv`.

3. **`P2-3` — Explicit TOCTOU Re-Observation & Two-Phase `prepare` → `claim()` → `execute` Operation Contract:**
   - **Defect Found:** The initial draft described `UvToolOperationCoordinator` without specifying the codebase's single-use preparation token (`prepare` → `claim()` → `execute` with `.preconditionChanged` TOCTOU defense) and pre/post-read file fingerprint checks.
   - **Fix Applied:** Updated `R1.5`, `R1.6`, `R5.2`, `R6`, and `R7` to enforce pre/post-read `FileIdentityObserver` fingerprint verification on `selection`, `manager`, `uv-receipt.toml`, and `.dist-info/METADATA`, and to use the single-use `UvToolUpdatePreparation` / `UvToolUninstallPreparation` `claim()` pattern serialized under `OperationExecutionGate.shared`.

4. **`P2-4` — PEP 440 Alternative Spellings, `Requires-Python` Parentheses & `UnknownReason` Vocabulary Discipline:**
   - **Defect Found:**
     - Real PyPI metadata uses alternative PEP 440 forms (`1.0-1` implicit post release, `c`/`pre`/`preview` aliases for `rc`, `rev`/`r` aliases for `post`) and parenthesized `Requires-Python: (>=3.9,<3.14)`.
     - The initial draft proposed adding three new `UnknownReason` cases (`.incompatiblePython`, `.customIndexUnsupported`, `.nonRegistrySource`), even though `VersionStatus.swift` already has `.unsupportedRegistry`, `.networkUnavailable`, `.queryTimedOut`, `.rateLimited`, `.metadataInvalid`, and `.unsupportedChannel`.
   - **Fix Applied:** Added full PEP 440 alternative-spelling normalization and parenthesized `Requires-Python` handling in `R2.2`–`R2.3`, and consolidated `R3.1` to reuse existing `UnknownReason` cases (including `.unsupportedRegistry` for custom/non-PyPI sources) while adding only the single orthogonal case `UnknownReason.pythonInterpreterIncompatible`.

---

## Final Verification Summary

- All 16 rulings (`R1`–`R16`) and 8 phases (`M14-A`–`M14-H`) in `briefs/M14-plan.md` are internally consistent and aligned with the live codebase at `882afd3517cda6f10c901dd973dc8f5e4083b2c2`.
- No product source files were modified during planning.
