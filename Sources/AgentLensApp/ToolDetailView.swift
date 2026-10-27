import SwiftUI
import AgentLensAppSupport
import AgentLensCore

public struct ToolDetailView: View {
    public let entry: InventoryEntry?
    public let isDegradedEnvironment: Bool
    public let freshnessFailure: InventoryViewModel.Failure?
    public let updateFailure: InventoryViewModel.Failure?
    public let isVerifyingOwnership: Bool
    public let isCancellingOwnership: Bool
    public let isBusy: Bool
    public let onVerifyOwnership: @MainActor () -> Void
    public let onCancelOwnership: @MainActor () -> Void

    public init(
        entry: InventoryEntry?,
        isDegradedEnvironment: Bool,
        freshnessFailure: InventoryViewModel.Failure?,
        updateFailure: InventoryViewModel.Failure?,
        isVerifyingOwnership: Bool = false,
        isCancellingOwnership: Bool = false,
        isBusy: Bool = false,
        onVerifyOwnership: @escaping @MainActor () -> Void = {},
        onCancelOwnership: @escaping @MainActor () -> Void = {}
    ) {
        self.entry = entry
        self.isDegradedEnvironment = isDegradedEnvironment
        self.freshnessFailure = freshnessFailure
        self.updateFailure = updateFailure
        self.isVerifyingOwnership = isVerifyingOwnership
        self.isCancellingOwnership = isCancellingOwnership
        self.isBusy = isBusy
        self.onVerifyOwnership = onVerifyOwnership
        self.onCancelOwnership = onCancelOwnership
    }

    public var body: some View {
        Group {
            if let entry {
                detailContent(entry)
            } else {
                ContentUnavailableView(
                    "No Tool Selected",
                    systemImage: "wrench.and.screwdriver",
                    description: Text("Select a tool from the inventory to view its details.")
                )
            }
        }
        .navigationTitle(entry?.definition.displayName ?? "Tool Details")
    }

    private func detailContent(_ entry: InventoryEntry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if isDegradedEnvironment {
                    degradedEnvironmentBanner
                }

                if let freshnessFailure {
                    freshnessFailureBanner(freshnessFailure)
                }

                if let updateFailure {
                    updateFailureBanner(updateFailure)
                }

                headerSection(entry)

                Divider()

                installationSection(entry)

                Divider()

                ownershipSection(entry)

                Divider()

                metadataSection(entry)

                Divider()

                updateSection(entry)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Banners

    private var degradedEnvironmentBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.body)
            VStack(alignment: .leading, spacing: 2) {
                Text("Degraded Environment")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("The login shell could not be captured; PATH uses the documented fallback PATH. Results may not represent the login shell's authoritative PATH.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private func freshnessFailureBanner(_ failure: InventoryViewModel.Failure) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.orange)
                .font(.body)
            VStack(alignment: .leading, spacing: 2) {
                Text("Rescan Failed")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("\(failure.message). Displaying retained local inventory.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private func updateFailureBanner(_ failure: InventoryViewModel.Failure) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.orange)
                .font(.body)
            VStack(alignment: .leading, spacing: 2) {
                Text("Update Check Failed")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("\(failure.message). Displaying retained local inventory.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Header

    private func headerSection(_ entry: InventoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.definition.displayName)
                .font(.title)
                .fontWeight(.bold)

            HStack(spacing: 8) {
                Text(entry.definition.executableName)
                    .font(.subheadline)
                    .fontDesign(.monospaced)
                    .foregroundColor(.secondary)

                Text("•")
                    .foregroundColor(.secondary)

                Text(entry.registryID)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: Installation Details

    private func installationSection(_ entry: InventoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Installation")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    Text("State")
                        .foregroundColor(.secondary)
                    installStateText(entry.installState)
                }

                GridRow {
                    Text("Local Version")
                        .foregroundColor(.secondary)
                    Text(entry.diagnostic.detectedTool.version ?? "—")
                        .fontDesign(.monospaced)
                }

                GridRow {
                    Text("Source (heuristic)")
                        .foregroundColor(.secondary)
                    Text(entry.diagnostic.detectedTool.source.isEmpty ? "—" : entry.diagnostic.detectedTool.source)
                }

                GridRow(alignment: .top) {
                    Text("Selected Entry")
                        .foregroundColor(.secondary)
                    pathActionRow(entry, .selectedEntry, rowLabel: "Selected Entry")
                }

                GridRow(alignment: .top) {
                    Text("Resolved Target")
                        .foregroundColor(.secondary)
                    pathActionRow(entry, .resolvedTarget, rowLabel: "Resolved Target")
                }
            }
            .font(.subheadline)
        }
    }

    // MARK: Ownership Verification

    /// Explicit, read-only installation ownership. The action is only offered for a
    /// selected winner or off-PATH candidate; absent and inconsistent diagnostics never
    /// expose a trigger that could run manager queries.
    private func ownershipSection(_ entry: InventoryEntry) -> some View {
        OwnershipVerificationView(
            entry: entry,
            isVerifying: isVerifyingOwnership,
            isCancelling: isCancellingOwnership,
            canVerify: Self.canVerifyOwnership(entry),
            isBusy: isBusy,
            onVerify: onVerifyOwnership,
            onCancel: onCancelOwnership
        )
    }

    private static func canVerifyOwnership(_ entry: InventoryEntry) -> Bool {
        switch entry.diagnostic.selection {
        case .winner, .offPath:
            true
        case .notInstalled, .inconsistent:
            false
        }
    }

    // MARK: Metadata

    /// Registry-declared facts for the selected entry. Nothing here is cached in
    /// local view state, so switching tools replaces every value and deselecting
    /// the tool clears the whole detail view.
    private func metadataSection(_ entry: InventoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tool Metadata")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    Text("Category")
                        .foregroundColor(.secondary)
                    Text(entry.definition.category.label)
                }

                GridRow(alignment: .top) {
                    Text("Declared Packages")
                        .foregroundColor(.secondary)
                    declaredPackagesView(entry.definition.packages)
                }

                if let informationURL = entry.definition.informationURL {
                    GridRow(alignment: .top) {
                        Text("Official Information")
                            .foregroundColor(.secondary)
                        metadataLink(informationURL)
                    }
                }

                if let uninstallURL = entry.definition.uninstallInstructionsURL {
                    GridRow(alignment: .top) {
                        Text("Uninstall Instructions")
                            .foregroundColor(.secondary)
                        metadataLink(uninstallURL)
                    }
                }
            }
            .font(.subheadline)
        }
    }

    @ViewBuilder
    private func declaredPackagesView(_ packages: [DeclaredPackage]) -> some View {
        if packages.isEmpty {
            Text("No declared package")
                .foregroundColor(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(packages.indices, id: \.self) { index in
                    Text("\(packages[index].manager.label): \(packages[index].name)")
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func metadataLink(_ url: URL) -> some View {
        Link(destination: url) {
            Text(url.absoluteString)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func installStateText(_ state: InstallState) -> some View {
        switch state {
        case .installedAndOnPath:
            Text("Installed and on PATH")
                .fontWeight(.medium)
        case .installedNotOnPath:
            Text("Installed, off PATH")
                .fontWeight(.medium)
                .foregroundColor(.orange)
        case .notInstalled:
            Text("Not installed")
                .foregroundColor(.secondary)
        }
    }

    /// Identity key for a path-action row. Distinguishes registry ID, field,
    /// both path values (nil-preserving) and their eligibility, so transient
    /// feedback resets when the tool or its paths change without flattening
    /// path contents into an ambiguous concatenation.
    private struct PathActionRowIdentity: Hashable {
        let registryID: String
        let field: PathActionTarget.Field
        let entryPath: String?
        let targetPath: String?
        let entryEligibility: PathActionTarget.Ineligibility?
        let targetEligibility: PathActionTarget.Ineligibility?
    }

    private func pathActionRow(
        _ entry: InventoryEntry,
        _ field: PathActionTarget.Field,
        rowLabel: String
    ) -> some View {
        let targets = PathActionTarget.targets(for: entry)
        let selected = targets.first { $0.field == .selectedEntry }
        let resolved = targets.first { $0.field == .resolvedTarget }
        let target = (field == .selectedEntry ? selected : resolved)
            ?? PathActionTarget(field: field, path: nil, ineligibility: .missingValue)
        let identity = PathActionRowIdentity(
            registryID: entry.registryID,
            field: field,
            entryPath: selected?.path,
            targetPath: resolved?.path,
            entryEligibility: selected?.ineligibility,
            targetEligibility: resolved?.ineligibility
        )
        return PathActionRow(
            target: target,
            toolName: entry.definition.displayName,
            rowLabel: rowLabel
        )
        .id(identity)
    }

    // MARK: Update Status

    private func updateSection(_ entry: InventoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Update Status")
                .font(.headline)

            if let update = entry.update {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        Text("Status")
                            .foregroundColor(.secondary)
                        updateStatusLabel(update.status)
                    }

                    GridRow {
                        Text("Local Version")
                            .foregroundColor(.secondary)
                        Text(installedVersionText(update.status))
                            .fontDesign(.monospaced)
                    }

                    GridRow {
                        Text(update.npmPackage != nil
                             ? "Latest Known npm Metadata"
                             : "Latest Known Homebrew Metadata")
                            .foregroundColor(.secondary)
                        Text(latestVersionText(update.status))
                            .fontDesign(.monospaced)
                    }

                    if let package = update.npmPackage {
                        GridRow(alignment: .top) {
                            Text("npm Package")
                                .foregroundColor(.secondary)
                            Text(package)
                                .fontDesign(.monospaced)
                        }
                        GridRow(alignment: .top) {
                            Text("npm Registry / Tag")
                                .foregroundColor(.secondary)
                            Text("\(update.npmRegistry ?? "—") / \(update.npmTag ?? "—")")
                                .fontDesign(.monospaced)
                        }
                        GridRow(alignment: .top) {
                            Text("npm Version Observed")
                                .foregroundColor(.secondary)
                            Text(update.npmVersion ?? "unknown")
                                .fontDesign(.monospaced)
                        }
                    }

                    if case .unknown(_, let reason) = update.status {
                        GridRow(alignment: .top) {
                            Text("Reason")
                                .foregroundColor(.secondary)
                            Text(plainLanguageReason(reason, npm: update.npmPackage != nil))
                                .foregroundColor(.secondary)
                        }
                    }

                    if let kegVersion = update.selectedKegVersion {
                        GridRow {
                            Text("Selected Keg Version")
                                .foregroundColor(.secondary)
                            Text(kegVersion)
                                .fontDesign(.monospaced)
                        }
                    }

                    if let provenanceText = provenanceDescription(update) {
                        GridRow(alignment: .top) {
                            Text("Provenance")
                                .foregroundColor(.secondary)
                            Text(provenanceText)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .font(.subheadline)
            } else {
                Text("Not checked")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func updateStatusLabel(_ status: VersionStatus) -> some View {
        switch status {
        case .upToDate:
            Text("Up to date")
                .fontWeight(.medium)
        case .updateAvailable:
            Text("Update available")
                .fontWeight(.medium)
                .foregroundColor(.accentColor)
        case .unknown:
            Text("Unknown")
                .foregroundColor(.secondary)
        }
    }

    private func installedVersionText(_ status: VersionStatus) -> String {
        switch status {
        case .upToDate(let installed, _), .updateAvailable(let installed, _):
            return installed.text
        case .unknown(let installed, _):
            return installed?.text ?? "—"
        }
    }

    private func latestVersionText(_ status: VersionStatus) -> String {
        switch status {
        case .upToDate(_, let latest), .updateAvailable(_, let latest):
            return latest.text
        case .unknown:
            return "—"
        }
    }

    private func plainLanguageReason(_ reason: UnknownReason, npm: Bool = false) -> String {
        switch reason {
        case .noRegistry:
            "No registry"
        case .networkUnavailable:
            "Network unavailable"
        case .probeFailed:
            "Update probe failed"
        case .rateLimited:
            "Rate limited"
        case .notChecked:
            "Update check not requested"
        case .notInstalled:
            "Not installed"
        case .unsupportedSource:
            "Unsupported installation manager"
        case .installedVersionUnavailable:
            "Installed version unavailable"
        case .unsupportedVersion:
            "Unsupported version format"
        case .managerUnavailable:
            npm ? "npm not available on PATH" : "Homebrew not available on PATH"
        case .managerMismatch:
            "Selected executable is not in the Homebrew Cellar"
        case .identityUnverified:
            "Selected package could not be verified"
        case .diagnosticInconsistent:
            "PATH diagnostics are inconsistent"
        case .newerThanKnownMetadata:
            "Installed version is newer than known metadata"
        case .unsupportedRegistry:
            "Unsupported registry"
        case .unsupportedChannel:
            "Unsupported update channel"
        case .budgetExhausted:
            "Update stage budget exhausted"
        case .metadataInvalid:
            "Invalid metadata"
        case .queryTimedOut:
            "Metadata query timed out"
        }
    }

    private func provenanceDescription(_ result: ToolUpdateResult) -> String? {
        if let package = result.npmPackage, let registry = result.npmRegistry, let tag = result.npmTag {
            let identity = "npm package \(package), registry \(registry), tag \(tag); npm version \(result.npmVersion ?? "unknown")"
            switch result.provenance {
            case .none:
                return nil
            case .freshProbe(let observedAt):
                return "npm metadata (\(identity)); checked at \(formatTimestamp(observedAt))"
            case .cache(let observedAt):
                return "npm metadata cache (\(identity)); observed at \(formatTimestamp(observedAt))"
            }
        }
        switch result.provenance {
        case .none:
            return nil
        case .freshProbe(let observedAt):
            return "Homebrew metadata; checked at \(formatTimestamp(observedAt))"
        case .cache(let observedAt):
            return "Homebrew metadata cache; observed at \(formatTimestamp(observedAt))"
        }
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}
