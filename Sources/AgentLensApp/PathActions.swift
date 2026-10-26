import SwiftUI
import AppKit
import Darwin
import AgentLensAppSupport

/// A native path-row control: shows the (selectable, wrapping) path text plus
/// Copy Path and Reveal in Finder buttons, with truthful accessibility and
/// transient feedback.
///
/// All action policy — eligibility, copy-without-existence, reveal-existence
/// gating, clipboard-failure reporting — is delegated to
/// `PathActionDispatcher`. This view supplies the real native effects:
/// `NSPasteboard` for Copy and `NSWorkspace`/`lstat` for Reveal.
///
/// Feedback is transient and lives in local `@State`. The host view assigns a
/// stable `.id` that incorporates the tool registry ID and both path values so
/// the state (and any stale feedback) resets when the tool or its paths change.
struct PathActionRow: View {
    let target: PathActionTarget
    /// Human-readable tool name, used to distinguish accessible labels
    /// (e.g. "Copy Selected Entry path for Codex").
    let toolName: String
    /// Short row label, e.g. "Selected Entry" or "Resolved Target".
    let rowLabel: String

    init(target: PathActionTarget, toolName: String, rowLabel: String) {
        self.target = target
        self.toolName = toolName
        self.rowLabel = rowLabel
    }

    // Avoid `@State` macro syntax (the builder toolchain's SwiftUIMacros
    // plugin is unavailable for the app target); use the explicit
    // `State(initialValue:)` wrapper pattern already used by MainWindow.
    private var _feedback = State<String?>(initialValue: nil)
    private var feedback: String? {
        get { _feedback.wrappedValue }
        nonmutating set { _feedback.wrappedValue = newValue }
    }

    private var _feedbackIsError = State<Bool>(initialValue: false)
    private var feedbackIsError: Bool {
        get { _feedbackIsError.wrappedValue }
        nonmutating set { _feedbackIsError.wrappedValue = newValue }
    }

    private var displayPath: String {
        target.path ?? "—"
    }

    /// Accessible action name distinguishing tool, row, and action.
    private func actionLabel(_ verb: String) -> String {
        "\(verb) \(rowLabel) path for \(toolName)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(displayPath)
                .fontDesign(.monospaced)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                Button {
                    perform(.copyPath)
                } label: {
                    Label("Copy Path", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .disabled(!target.isActionable)
                .accessibilityLabel(actionLabel("Copy"))
                .help(actionLabel("Copy"))

                Button {
                    perform(.revealInFinder)
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
                .buttonStyle(.borderless)
                .disabled(!target.isActionable)
                .accessibilityLabel(actionLabel("Reveal in Finder"))
                .help(actionLabel("Reveal in Finder"))

                Spacer(minLength: 0)
            }

            if let reason = target.ineligibility {
                Text(reason.reason)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let feedback {
                Text(feedback)
                    .font(.footnote)
                    .foregroundColor(feedbackIsError ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(feedback)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func perform(_ action: PathActionTarget.Action) {
        let outcome = PathActionDispatcher.perform(
            action,
            target: target,
            pathExists: Self.pathExists,
            writeClipboard: Self.writeClipboard,
            revealInFinder: Self.revealInFinder
        )

        switch outcome {
        case .copied:
            setFeedback("Copied path to clipboard.", isError: false)
        case .clipboardFailed:
            setFeedback("Could not copy the path to the clipboard.", isError: true)
        case .revealed:
            setFeedback("Finder selection requested.", isError: false)
        case .revealMissing:
            setFeedback(
                "This path is missing or inaccessible. Rescan to refresh, or Copy Path to keep the recorded text.",
                isError: true
            )
        case .ineligible(let reason):
            setFeedback(reason.reason, isError: true)
        }
    }

    private func setFeedback(_ text: String, isError: Bool) {
        feedback = text
        feedbackIsError = isError
    }

    // MARK: - Native effects

    /// lstat-style existence check on the exact path. Returns true for a live
    /// entry including a broken symlink (the link itself exists) — matching the
    /// brief's "lstat-style broken-symlink existence at activation".
    private static func pathExists(_ path: String) -> Bool {
        var info = stat()
        return path.withCString { lstat($0, &info) } == 0
    }

    /// Write the exact literal path as plain text; return false on failure.
    private static func writeClipboard(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    /// Ask Finder to select the item. Only reached after a successful existence
    /// check in the dispatcher.
    private static func revealInFinder(_ path: String) -> PathActionOutcome {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        return .revealed
    }
}