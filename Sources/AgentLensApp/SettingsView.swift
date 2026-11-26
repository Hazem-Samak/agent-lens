// SettingsView — M12-B read-only Settings destination (R7).
//
// Settings controls only delivered features, and M12 delivers no preference: appearance follows
// the system and nothing here can be flipped. Every statement is a published fact (catalogue
// counts, the degraded-environment observation) or an explicit absence. There is no Toggle, no
// preference write, and no second SwiftUI Settings scene.

import SwiftUI
import AgentLensAppSupport
import AgentLensCore

public struct SettingsView: View {
    let model: InventoryViewModel

    public init(model: InventoryViewModel) {
        self.model = model
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                catalogueSection

                Divider()

                managedOperationsSection

                Divider()

                environmentSection

                Divider()

                absentFeaturesSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Settings")
    }

    // MARK: Catalogue

    private var catalogueSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Catalogue")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text("\(model.knownToolCount) known tools")
                .font(.subheadline)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                ForEach(ToolCategory.allCases, id: \.rawValue) { category in
                    GridRow {
                        Text(category.label)
                            .foregroundColor(.secondary)
                        Text("\(catalogueCount(in: category))")
                            .monospacedDigit()
                    }
                }
            }
            .font(.subheadline)
        }
    }

    private func catalogueCount(in category: ToolCategory) -> Int {
        model.entries.filter { $0.definition.category == category }.count
    }

    // MARK: Managed operations

    /// Scope language, not a hard-coded per-tool list. Update eligibility and uninstall eligibility
    /// are different gates: an update needs the accepted update operation plus a newer version the
    /// matching manager observed (and re-observes before it runs); an uninstall needs the accepted
    /// uninstall operation plus exact verified ownership of the selected installation. The former
    /// "verified installation" rule described a gate the update path does not have, and the former
    /// unqualified npm refusal sentence would have read as an npm-only ban.
    private var managedOperationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Managed Operations")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text("Agent Lens offers an update only for a registry entry that accepts the update operation and only while the matching package manager reports a newer version; that version is re-checked live before the update runs. It offers an uninstall only for a registry entry that accepts the uninstall operation and only after the selected installation's exact ownership is verified. Accepted operations cover npm packages and Homebrew formulas and casks; every other tool stays read-only.")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Text("Agent Lens runs the manager's own command for the operation you confirm; nothing is changed without your confirmation.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Environment

    private var environmentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Environment")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            if model.isDegradedEnvironment {
                Text("The login shell could not be captured; PATH uses the documented fallback PATH. Results may not represent the login shell's authoritative PATH.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("The window follows the system appearance.")
                .font(.subheadline)
        }
    }

    // MARK: Explicit absences

    private var absentFeaturesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What Agent Lens Does Not Do")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text("Agent Lens does not keep a saved inventory between launches.")
            Text("Agent Lens does not add a menu-bar item.")
            Text("Agent Lens does not schedule update checks.")
            Text("Agent Lens does not install a command-line tool for you.")
        }
        .font(.subheadline)
        .foregroundColor(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}
