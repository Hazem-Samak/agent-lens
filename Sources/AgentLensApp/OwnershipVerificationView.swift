// OwnershipVerificationView — native details and explicit action for M9-B ownership.
//
// Stateless by design: every value is read from the published entry (or the current phase passed
// by the window). The view never derives ownership from source labels, declared packages or path
// text, and it never offers update/uninstall actions.

import AgentLensAppSupport
import AgentLensCore
import SwiftUI

public struct OwnershipVerificationView: View {
    private let entry: InventoryEntry
    private let isVerifying: Bool
    private let isCancelling: Bool
    private let canVerify: Bool
    private let isBusy: Bool
    private let onVerify: @MainActor () -> Void
    private let onCancel: @MainActor () -> Void

    public init(
        entry: InventoryEntry,
        isVerifying: Bool,
        isCancelling: Bool,
        canVerify: Bool,
        isBusy: Bool,
        onVerify: @escaping @MainActor () -> Void,
        onCancel: @escaping @MainActor () -> Void
    ) {
        self.entry = entry
        self.isVerifying = isVerifying
        self.isCancelling = isCancelling
        self.canVerify = canVerify
        self.isBusy = isBusy
        self.onVerify = onVerify
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Installation Ownership")
                .font(.headline)

            HStack(spacing: 8) {
                statusLabel
                Spacer()
                action
            }

            details
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        if isVerifying {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(isCancelling ? "Cancelling…" : "Verifying…")
                    .foregroundColor(.secondary)
            }
        } else if let ownership = entry.ownership {
            switch ownership.outcome {
            case .verified:
                Label("Verified", systemImage: "checkmark.seal.fill")
                    .foregroundColor(.green)
                    .fontWeight(.medium)
            case .unknown:
                Label("Unknown", systemImage: "questionmark.circle")
                    .foregroundColor(.secondary)
            }
        } else {
            Text("Not verified")
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var action: some View {
        if isVerifying {
            Button("Cancel") {
                onCancel()
            }
            .buttonStyle(.borderless)
            .disabled(isCancelling)
            .accessibilityLabel("Cancel ownership verification for \(entry.definition.displayName)")
        } else if canVerify {
            Button("Verify Installation") {
                onVerify()
            }
            .disabled(isBusy)
            .accessibilityLabel("Verify Installation for \(entry.definition.displayName)")
            .help(
                "Read-only ownership verification for \(entry.definition.displayName). "
                + "This launches no install, update or uninstall command."
            )
        }
    }

    @ViewBuilder
    private var details: some View {
        if let ownership = entry.ownership {
            switch ownership.outcome {
            case .verified(let installation):
                verifiedDetails(installation, observedAt: ownership.observedAt)
            case .unknown(let reason):
                unknownDetails(reason, observedAt: ownership.observedAt, ownership: ownership)
            }
        } else if !isVerifying {
            Text("Ownership has not been verified. Verification is explicit and read-only.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func verifiedDetails(
        _ installation: VerifiedInstallation,
        observedAt: Date
    ) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
                Text("Manager").foregroundColor(.secondary)
                Text(installation.manager.label)
            }
            GridRow(alignment: .top) {
                Text("Package").foregroundColor(.secondary)
                wrappedText(installation.packageName)
            }
            GridRow(alignment: .top) {
                Text("Manager Executable").foregroundColor(.secondary)
                wrappedText(installation.managerEntryPath)
            }
            GridRow(alignment: .top) {
                Text("Manager Target").foregroundColor(.secondary)
                wrappedText(installation.managerTarget)
            }
            GridRow(alignment: .top) {
                Text("Manager Root").foregroundColor(.secondary)
                wrappedText(installation.managerRoot)
            }
            GridRow(alignment: .top) {
                Text("Installation Root").foregroundColor(.secondary)
                wrappedText(installation.installationRoot)
            }
            GridRow(alignment: .top) {
                Text("Selected Entry").foregroundColor(.secondary)
                wrappedText(installation.selection.entryPath)
            }
            GridRow(alignment: .top) {
                Text("Selected Target").foregroundColor(.secondary)
                wrappedText(installation.selection.canonicalTarget)
            }
            GridRow(alignment: .top) {
                Text("Observed").foregroundColor(.secondary)
                Text(timestamp(observedAt))
                    .foregroundColor(.secondary)
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)

        Text(
            "Read-only observation from this verification. No installation changes were made, "
            + "and updates or uninstalls remain unavailable."
        )
        .font(.caption)
        .foregroundColor(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func unknownDetails(
        _ reason: InstallationOwnershipReason,
        observedAt: Date,
        ownership: InstallationOwnershipResult
    ) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow(alignment: .top) {
                Text("Reason").foregroundColor(.secondary)
                Text(reason.message)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let entryPath = ownership.observedSelectedEntry {
                GridRow(alignment: .top) {
                    Text("Selected Entry").foregroundColor(.secondary)
                    wrappedText(entryPath)
                }
            }
            if let target = ownership.observedSelectedTarget {
                GridRow(alignment: .top) {
                    Text("Selected Target").foregroundColor(.secondary)
                    wrappedText(target)
                }
            }
            GridRow(alignment: .top) {
                Text("Observed").foregroundColor(.secondary)
                Text(timestamp(observedAt))
                    .foregroundColor(.secondary)
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func wrappedText(_ value: String) -> some View {
        Text(value)
            .fontDesign(.monospaced)
            .textSelection(.enabled)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static let timestampStyle = Date.ISO8601FormatStyle(
        timeZone: TimeZone(secondsFromGMT: 0)!
    )

    private func timestamp(_ date: Date) -> String {
        date.formatted(Self.timestampStyle)
    }
}
