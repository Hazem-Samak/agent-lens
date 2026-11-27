import SwiftUI
import AppKit
import AgentLensAppSupport
import AgentLensCore

/// Native confirmation/result sheet for one Homebrew formula or cask uninstall. Every dynamic value
/// is plain text; the displayed command is a rendering only and is never executed. The footer
/// follows M12-D C-1: Cancel is Escape, the destructive confirmation has no key equivalent, and a
/// cask confirmation hint names the companion-app consequence.
public struct HomebrewUninstallOperationView: View {
    public let preview: HomebrewUninstallPreviewSlot?
    public let outcome: HomebrewUninstallOutcomeSlot?
    public let unavailable: HomebrewUninstallUnavailableSlot?
    public let isExecuting: Bool
    public let isCancelling: Bool
    public let onConfirm: @MainActor () -> Void
    public let onCancel: @MainActor () -> Void
    public let onDismiss: @MainActor () -> Void

    public init(
        preview: HomebrewUninstallPreviewSlot?,
        outcome: HomebrewUninstallOutcomeSlot?,
        unavailable: HomebrewUninstallUnavailableSlot?,
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
                // C-1: no default action while a destructive mutation is reviewable. Escape
                // cancels; the confirmation is reachable by Tab + Space or click only.
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isCancelling)
                    .accessibilityHint("Closes this confirmation without a change.")
                Button(role: .destructive) {
                    onConfirm()
                } label: {
                    Text(isExecuting
                         ? (isCancelling ? "Cancelling..." : "Uninstalling...")
                         : "Uninstall Package")
                }
                .disabled(isExecuting || isCancelling)
                .accessibilityHint(confirmHint)
            }
        }
    }

    private var confirmHint: String {
        switch preview {
        case .cask:
            "Removes the reviewed Homebrew cask after this confirmation. This may remove a companion app, not only the selected CLI."
        case .formula, nil:
            "Removes the reviewed Homebrew formula after this confirmation."
        }
    }

    // MARK: Preview

    @ViewBuilder
    private func previewView(_ preview: HomebrewUninstallPreviewSlot) -> some View {
        switch preview {
        case .formula(let formula):
            formulaPreview(formula)
        case .cask(let cask):
            caskPreview(cask)
        }
    }

    private func formulaPreview(_ preview: HomebrewFormulaUninstallPreview) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if isExecuting {
                progressRegion(
                    sentence: "Homebrew formula uninstall in progress",
                    registryID: preview.registryID,
                    identity: preview.fullName,
                    prefix: preview.prefix
                )
            }

            Text("Uninstall \(preview.displayName)")
                .font(.title2)
                .fontWeight(.bold)
                .accessibilityAddTraits(.isHeader)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                row("Registry ID", preview.registryID)
                row("Kind", "Homebrew formula")
                row("Formula", preview.formulaName)
                row("Full Identity", preview.fullName)
                row("Selected Keg", preview.selectedKegVersion)
                row("Installed Kegs", preview.installedKegs.isEmpty ? "—" : preview.installedKegs.joined(separator: ", "))
                row("Manager", preview.managerPath)
                row("Prefix", preview.prefix)
                row("Cellar", preview.cellar)
                row("Working Directory", preview.workingDirectory)
                row("Selected Entry", preview.selectedEntryPath)
                row("Selected Target", preview.selectedTarget)
                row("Timeout", "\(preview.timeoutSeconds) seconds")
            }
            .font(.subheadline)

            Text(preview.remainingKegDisclosure)
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(preview.dependentRefusalDisclosure)
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(preview.effect)
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            commandSection(preview.executablePath, arguments: preview.arguments)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "Homebrew formula uninstall preview for \(preview.fullName), prefix \(preview.prefix)"
        )
    }

    private func caskPreview(_ preview: HomebrewCaskUninstallPreview) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if isExecuting {
                progressRegion(
                    sentence: "Homebrew cask uninstall in progress",
                    registryID: preview.registryID,
                    identity: preview.fullToken,
                    prefix: preview.prefix
                )
            }

            Text("Uninstall \(preview.displayName)")
                .font(.title2)
                .fontWeight(.bold)
                .accessibilityAddTraits(.isHeader)

            // The whole-cask consequence sits beneath the title, above the long identity rows: a
            // tall grid must never push it out of the first screen while Confirm stays visible.
            Text(preview.companionAppDisclosure)
                .font(.callout)
                .fontWeight(.semibold)
                .foregroundColor(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isStaticText)
                .accessibilityLabel(preview.companionAppDisclosure)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                row("Registry ID", preview.registryID)
                row("Kind", "Homebrew cask")
                row("Cask Token", preview.token)
                row("Full Identity", preview.fullToken)
                row("Tap", preview.tap)
                row("Installed Version", preview.installedVersion)
                row("Deprecated", preview.deprecated ? "yes" : "no")
                if let disclosure = preview.deprecationDisclosure {
                    row("Deprecation", disclosure)
                }
                row("Manager", preview.managerPath)
                row("Prefix", preview.prefix)
                row("Caskroom", preview.caskroom)
                row("Working Directory", preview.workingDirectory)
                row("Selected Entry", preview.selectedEntryPath)
                row("Selected Target", preview.selectedTarget)
                row("Timeout", "\(preview.timeoutSeconds) seconds")
            }
            .font(.subheadline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Managed CLI artifact targets")
                    .font(.headline)
                ForEach(Array(preview.artifactTargets.enumerated()), id: \.offset) { _, target in
                    Text("\(target.kind.rawValue): \(target.target) (\(target.presence.rawValue))")
                        .font(.system(.caption, design: .monospaced))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(
                            "Managed \(target.kind.rawValue) artifact target \(target.target), \(target.presence.rawValue)"
                        )
                }
            }

            Text(preview.artifactScopeDisclosure)
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(preview.zapDisclosure)
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(preview.effect)
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            commandSection(preview.executablePath, arguments: preview.arguments)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "Homebrew cask uninstall preview for \(preview.fullToken), prefix \(preview.prefix). \(preview.companionAppDisclosure)"
        )
    }

    private func commandSection(_ executablePath: String, arguments: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Exact executable and arguments")
                .font(.headline)
            Text(executablePath)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(arguments.enumerated()), id: \.offset) { _, argument in
                    Text(argument)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Exact executable \(executablePath), arguments \(arguments.joined(separator: " "))")
        }
    }

    private func progressRegion(
        sentence: String,
        registryID: String,
        identity: String,
        prefix: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 4) {
                Text(sentence)
                    .font(.headline)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Registry ID: \(registryID)")
                    Text("Package: \(identity)")
                    Text("Prefix: \(prefix)")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(sentence), registry ID \(registryID), package \(identity), prefix \(prefix)"
        )
    }

    // MARK: Unavailable

    private func unavailableView(_ reason: HomebrewUninstallUnavailableSlot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Uninstall Unavailable")
                .font(.title2)
                .fontWeight(.bold)
                .accessibilityAddTraits(.isHeader)
            Text(reason.message)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Uninstall unavailable. \(reason.message)")
        .onAppear {
            Self.announce("Uninstall unavailable. \(reason.message)")
        }
    }

    // MARK: Result

    @ViewBuilder
    private func resultView(_ outcome: HomebrewUninstallOutcomeSlot) -> some View {
        switch outcome {
        case .formula(let value):
            formulaResult(value)
        case .cask(let value):
            caskResult(value)
        }
    }

    private func formulaResult(_ outcome: HomebrewFormulaUninstallOutcome) -> some View {
        commonResult(
            title: resultTitle(outcome.state),
            message: outcome.message,
            exitStatus: outcome.exitStatus,
            cleanupWarnings: outcome.cleanupWarnings,
            stdoutText: outcome.stdoutText,
            stdoutTruncated: outcome.stdoutTruncated,
            stderrText: outcome.stderrText,
            stderrTruncated: outcome.stderrTruncated
        ) {
            if let delta = outcome.reconciliation {
                formulaDelta(delta)
            }
        }
    }

    private func caskResult(_ outcome: HomebrewCaskUninstallOutcome) -> some View {
        commonResult(
            title: resultTitle(outcome.state),
            message: outcome.message,
            exitStatus: outcome.exitStatus,
            cleanupWarnings: outcome.cleanupWarnings,
            stdoutText: outcome.stdoutText,
            stdoutTruncated: outcome.stdoutTruncated,
            stderrText: outcome.stderrText,
            stderrTruncated: outcome.stderrTruncated
        ) {
            if let delta = outcome.reconciliation {
                caskDelta(delta)
            }
        }
    }

    private func commonResult<Delta: View>(
        title: String,
        message: String?,
        exitStatus: Int32?,
        cleanupWarnings: [String],
        stdoutText: String,
        stdoutTruncated: Bool,
        stderrText: String,
        stderrTruncated: Bool,
        @ViewBuilder delta: () -> Delta
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel(
                    "\(title), exit status \(exitStatus.map(String.init) ?? "unavailable")"
                )
            if let message {
                Text(message)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Exit status: \(exitStatus.map(String.init) ?? "unavailable")")
                .font(.subheadline)
                .fontDesign(.monospaced)
            delta()
            if !cleanupWarnings.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(cleanupWarnings, id: \.self) { Text($0) }
                }
                .font(.caption)
                .foregroundColor(.orange)
            }

            outputView("stdout", stdoutText, truncated: stdoutTruncated)
            outputView("stderr", stderrText, truncated: stderrTruncated)
        }
        .onAppear {
            Self.announce(
                "\(title), exit status \(exitStatus.map(String.init) ?? "unavailable")"
            )
        }
    }

    private func formulaDelta(_ delta: HomebrewFormulaUninstallDelta) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Reconciliation")
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                row("Selected Keg", "\(delta.beforeSelectedKegVersion) → \(delta.afterSelectedKegVersion ?? "—")")
                row("Installed Kegs Before", delta.beforeInstalledKegs.isEmpty ? "—" : delta.beforeInstalledKegs.joined(separator: ", "))
                row("Installed Kegs After", delta.afterInstalledKegs.map { $0.isEmpty ? "none" : $0.joined(separator: ", ") } ?? "unknown")
                row("Recorded Keg Absent", delta.recordedKegAbsent ? "yes" : "no")
                row("Recorded Keg Replaced", delta.recordedKegReplaced ? "yes" : "no")
                row("Selected Target Released", delta.selectedTargetReleased ? "yes" : "no")
                row("Selected Entry Residue", delta.selectedEntryResidue ? "yes (dangling link)" : "no")
                row("Remaining Kegs", delta.remainingKegs.map { $0.isEmpty ? "none" : $0.joined(separator: ", ") } ?? "unknown")
                row("Formula Still Installed Via Remaining Keg", delta.formulaStillInstalledViaRemainingKeg.map { $0 ? "yes" : "no" } ?? "unknown")
                row("Entry", "\(delta.beforeEntryPath ?? "—") → \(delta.afterEntryPath ?? "—")")
                row("Target", "\(delta.beforeTarget ?? "—") → \(delta.afterTarget ?? "—")")
                row("Aliases", "\(delta.beforeAliases.count) → \(delta.afterAliases.count)")
                row("Shadowed", "\(delta.beforeShadowedCount) → \(delta.afterShadowedCount)")
                row("Observation Failed", delta.observationFailed ? "yes" : "no")
                ownershipRow(delta.ownership)
            }
            .font(.system(.caption, design: .monospaced))
        }
    }

    private func caskDelta(_ delta: HomebrewCaskUninstallDelta) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Reconciliation")
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                row("Installed Version", "\(delta.beforeInstalledVersion) → \(delta.afterInstalledVersion ?? "—")")
                row("Installed Record Absent", delta.infoInstalledAbsent ? "yes" : "no")
                row("Token Directory Absent", delta.tokenDirectoryAbsent ? "yes" : "no")
                row("Token Directory Replaced", delta.tokenDirectoryReplaced ? "yes" : "no")
                row("Selected Target Released", delta.selectedTargetReleased ? "yes" : "no")
                row("Selected Entry Residue", delta.selectedEntryResidue ? "yes (dangling link)" : "no")
                row("Entry", "\(delta.beforeEntryPath ?? "—") → \(delta.afterEntryPath ?? "—")")
                row("Target", "\(delta.beforeTarget ?? "—") → \(delta.afterTarget ?? "—")")
                row("Aliases", "\(delta.beforeAliases.count) → \(delta.afterAliases.count)")
                row("Shadowed", "\(delta.beforeShadowedCount) → \(delta.afterShadowedCount)")
                row("Observation Failed", delta.observationFailed ? "yes" : "no")
                ownershipRow(delta.ownership)
            }
            .font(.system(.caption, design: .monospaced))
            if !delta.managedTargets.isEmpty {
                Text("Managed target release")
                    .font(.headline)
                ForEach(Array(delta.managedTargets.enumerated()), id: \.offset) { _, target in
                    Text("\(target.kind.rawValue): \(target.target) — \(target.release.rawValue)")
                        .font(.system(.caption, design: .monospaced))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func ownershipRow(_ ownership: InstallationOwnershipOutcome?) -> some View {
        if let ownership {
            switch ownership {
            case .verified(let installation):
                row("Remaining Ownership", "verified \(installation.manager.label) \(installation.packageName)")
            case .unknown(let reason):
                row("Remaining Ownership", "unknown: \(reason.message)")
            }
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

    /// VoiceOver announcement for the terminal state (M12-E/R10). The visible content is unchanged.
    private static func announce(_ message: String) {
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }
}