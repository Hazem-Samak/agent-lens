// DetectorMetadataRenderer — the CLI DETECTOR METADATA section (M9-A).
//
// Pure and registry-ordered: it renders exactly the validated definitions the
// scanner used. It never infers metadata from a display name, PATH text or
// detected source, and it never contacts the network.

import Foundation

public enum DetectorMetadataRenderer {

    public static func render(definitions: [DetectorDefinition]) -> String {
        var lines: [String] = []
        lines.append("")
        lines.append("DETECTOR METADATA")
        lines.append(
            "Declared package candidates are supported package names, not proof of installation ownership."
        )

        for definition in definitions {
            lines.append("")
            lines.append("\(definition.displayName)  category: \(definition.category.label)")
            if definition.packages.isEmpty {
                lines.append("  declared packages: none")
            } else {
                for package in definition.packages {
                    lines.append(
                        "  declared package: \(package.manager.label) \(package.name) (declaration only)"
                    )
                }
            }
            if let informationURL = definition.informationURL {
                lines.append("  official information: \(informationURL.absoluteString)")
            }
            if let uninstallURL = definition.uninstallInstructionsURL {
                lines.append("  uninstall instructions: \(uninstallURL.absoluteString)")
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }
}
