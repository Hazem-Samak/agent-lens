import SwiftUI
import AgentLensCore

/// Native confirmation/result sheet for one M10-D npm Uninstall. Every dynamic value is plain
/// text; the displayed command is a rendering only and is never executed. Cancel is the safe
/// default action; the destructive confirmation is explicit.
public struct UninstallOperationView: View {
    public let preview: NpmUninstallPreview?
    public let outcome: NpmUninstallOutcome?
    public let unavailable: NpmUninstallUnavailableReason?
    public let isExecuting: Bool
    public let isCancelling: Bool
    public let onConfirm: @MainActor () -> Void
    public let onCancel: @MainActor () -> Void
    public let onDismiss: @MainActor () -> Void

    public init(
        preview: NpmUninstallPreview?,
        outcome: NpmUninstallOutcome?,
        unavailable: NpmUninstallUnavailableReason?,
        isExecuting: Bool,
        isCancelling: Bool,
        onConfirm: @escaping @MainActor () -> Void,
        onCancel: @escaping @MainActor () -> Void,
        onDismiss: @escaping @MainActor () -> Void
    ) {
        self.preview = preview
        self.outcome = outcome
        self.unavailable = unavailable
        self.isExecuting = isExecuting
        self.isCancelling = isCancelling
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Group {
                    if let outcome {
                        resultView(outcome)
                    } else if let preview {
                        previewView(preview)
                    } else if let unavailable {
                        unavailableView(unavailable)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)

            Divider()
            footer
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
        }
        .frame(minWidth: 640, minHeight: 500)
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            Spacer()
            if outcome != nil {
                Button("Done") { onDismiss() }
                    .keyboardShortcut(.defaultAction)
            } else if unavailable != nil {
                Button("Close") { onDismiss() }
                    .keyboardShortcut(.defaultAction)
            } else if preview != nil {
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isCancelling)
                Button(role: .destructive) {
                    onConfirm()
                } label: {
                    Text(isExecuting
                         ? (isCancelling ? "Cancelling…" : "Uninstalling…")
                         : "Uninstall Package")
                }
                .disabled(isExecuting || isCancelling)
            }
        }
    }

    private func previewView(_ preview: NpmUninstallPreview) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Uninstall \(preview.displayName)")
                .font(.title2)
                .fontWeight(.bold)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                row("Registry ID", preview.registryID)
                row("Tool-Reported Version", preview.installedVersion ?? "unavailable")
                row("Package", preview.packageName)
                row("Registry Pin", "\(preview.registry) (no metadata query)")
                row("Manager", preview.managerPath)
                row("Prefix", preview.prefix)
                row("Installation Root", preview.installationRoot)
                row("Working Directory", preview.workingDirectory)
                row("Selected Entry", preview.selectedEntryPath)
                row("Selected Target", preview.selectedTarget)
            }
            .font(.subheadline)

            Text(preview.effect)
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Exact executable and arguments")
                .font(.headline)
            Text(preview.executablePath)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(preview.arguments.enumerated()), id: \.offset) { _, argument in
                    Text(argument)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func unavailableView(_ reason: NpmUninstallUnavailableReason) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Uninstall Unavailable")
                .font(.title2)
                .fontWeight(.bold)
            Text(reason.message)
                .foregroundColor(.secondary)
        }
    }

    private func resultView(_ outcome: NpmUninstallOutcome) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(resultTitle(outcome.state))
                .font(.title2)
                .fontWeight(.bold)
            if let message = outcome.message {
                Text(message)
                    .foregroundColor(.secondary)
            }
            Text("Exit status: \(outcome.exitStatus.map(String.init) ?? "unavailable")")
                .font(.subheadline)
                .fontDesign(.monospaced)
            if let delta = outcome.reconciliation {
                deltaView(delta)
            }
            if !outcome.cleanupWarnings.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(outcome.cleanupWarnings, id: \.self) { Text($0) }
                }
                .font(.caption)
                .foregroundColor(.orange)
            }

            outputView("stdout", outcome.stdoutText, truncated: outcome.stdoutTruncated)
            outputView("stderr", outcome.stderrText, truncated: outcome.stderrTruncated)
        }
    }

    private func deltaView(_ delta: NpmUninstallDelta) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Reconciliation")
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                row("Version", "\(delta.beforeVersion ?? "—") → \(delta.afterVersion ?? "—")")
                row("Entry", "\(delta.beforeEntryPath ?? "—") → \(delta.afterEntryPath ?? "—")")
                row("Target", "\(delta.beforeTarget ?? "—") → \(delta.afterTarget ?? "—")")
                row("Aliases", "\(delta.beforeAliases.count) → \(delta.afterAliases.count)")
                row("Shadowed", "\(delta.beforeShadowedCount) → \(delta.afterShadowedCount)")
                row("Install State", "\(delta.beforeInstallState.rawValue) → \(delta.afterInstallState.rawValue)")
                row("Package Directory Gone", delta.packageDirectoryAbsent ? "yes" : "no")
                row("Package Directory Replaced", delta.packageDirectoryReplaced ? "yes" : "no")
                row("Selected Target Released", delta.selectedTargetReleased ? "yes" : "no")
                row("Selected Entry Residue", delta.selectedEntryResidue ? "yes (dangling link)" : "no")
                row("Observation Failed", delta.observationFailed ? "yes" : "no")
                if let ownership = delta.ownership {
                    switch ownership {
                    case .verified(let installation):
                        row("Remaining Ownership", "verified \(installation.packageName)")
                    case .unknown(let reason):
                        row("Remaining Ownership", "unknown: \(reason.message)")
                    }
                }
            }
            .font(.system(.caption, design: .monospaced))
        }
    }

    private func outputView(_ title: String, _ text: String, truncated: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.headline)
                if truncated {
                    Text("truncated")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            ScrollView {
                Text(text.isEmpty ? "—" : text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 70, maxHeight: 140)
            .padding(8)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow(alignment: .top) {
            Text(label)
                .foregroundColor(.secondary)
            Text(value)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func resultTitle(_ state: OperationState) -> String {
        switch state {
        case .succeeded: "Uninstall Succeeded"
        case .failed: "Uninstall Failed"
        case .cancelled: "Uninstall Cancelled"
        case .interrupted: "Uninstall Interrupted"
        case .uncertain: "Uninstall Result Uncertain"
        }
    }
}
