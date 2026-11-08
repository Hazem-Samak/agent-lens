// UpdateScanRenderer — M6 appended VERSION / UPDATE STATUS section (brief §"User-visible command contract").
//
// Pure: no I/O, no clock reads. The caller supplies results already associated by registry
// order. The M5 report is printed first and unchanged; this section is appended after it.

import Foundation

public enum UpdateScanRenderer {

    /// Renders one section in registry order. Unknown statuses use neutral text, never a
    /// check mark or error marker. Only `updateAvailable` for installed, selected tools counts.
    public static func render(results: [ToolUpdateResult], mode: UpdateProbeMode) -> String {
        var lines: [String] = []
        lines.append("")
        lines.append("VERSION / UPDATE STATUS")
        for result in results {
            lines.append(row(for: result, mode: mode))
            if let provenance = provenanceLine(for: result) {
                lines.append("           \(provenance)")
            }
        }
        let count = results.filter(countsAsSelectedUpdate).count
        lines.append("\(count) update\(count == 1 ? "" : "s") available")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func countsAsSelectedUpdate(_ result: ToolUpdateResult) -> Bool {
        guard case .updateAvailable(let installed, _) = result.status,
              result.localVersion == installed.text,
              let selectedEntryPath = result.selectedEntryPath,
              let selectedTarget = result.selectedTarget,
              result.diagnostic.detectedTool.version == installed.text,
              result.diagnostic.detectedTool.resolvedPath == selectedTarget
        else {
            return false
        }

        switch result.diagnostic.selection {
        case .winner(let candidate):
            return result.diagnostic.detectedTool.state == .installedAndOnPath
                && candidate.kind.isLiveExecutable
                && candidate.entryPath == selectedEntryPath
                && candidate.canonicalTarget == selectedTarget
        case .offPath(let candidate, _):
            return result.diagnostic.detectedTool.state == .installedNotOnPath
                && candidate.kind.isLiveExecutable
                && candidate.entryPath == selectedEntryPath
                && candidate.canonicalTarget == selectedTarget
        case .notInstalled, .inconsistent:
            return false
        }
    }

    /// The visible label is the registry's display name — never the stable ID and never the
    /// executable basename. A display rename changes the text but not the association.
    static func row(for result: ToolUpdateResult, mode: UpdateProbeMode) -> String {
        let installed = installedText(result.status)
        switch result.status {
        case .upToDate(_, let latest):
            return "\(result.displayName)  installed \(installed)  latest known \(latest.text)  up to date"
        case .updateAvailable(_, let latest):
            return "\(result.displayName)  installed \(installed)  latest known \(latest.text)  update available"
        case .unknown(_, let reason):
            return "\(result.displayName)  installed \(installed)  latest known —  unknown — \(explanation(for: reason, mode: mode, npm: result.npmPackage != nil))"
        }
    }

    private static func installedText(_ status: VersionStatus) -> String {
        switch status {
        case .upToDate(let installed, _), .updateAvailable(let installed, _):
            return installed.text
        case .unknown(let installed, _):
            return installed?.text ?? "—"
        }
    }

    private static func provenanceLine(for result: ToolUpdateResult) -> String? {
        // A result carrying an npm package is an npm observation; everything else is Homebrew.
        if let package = result.npmPackage, let registry = result.npmRegistry, let tag = result.npmTag {
            let identity = "npm package \(package) registry \(registry) tag \(tag); npm version \(result.npmVersion ?? "unknown")"
            switch result.provenance {
            case .none:
                return nil
            case .freshProbe(let observedAt):
                return "source: npm metadata (\(identity)); checked at \(timestamp(observedAt))"
            case .cache(let observedAt):
                return "source: npm metadata cache (\(identity)); observed at \(timestamp(observedAt))"
            }
        }
        switch result.provenance {
        case .none:
            return nil
        case .freshProbe(let observedAt):
            return "source: Homebrew metadata; checked at \(timestamp(observedAt))"
        case .cache(let observedAt):
            return "source: Homebrew metadata cache; observed at \(timestamp(observedAt))"
        }
    }

    /// Neutral explanations per typed reason. Offline mode is named explicitly.
    static func explanation(for reason: UnknownReason, mode: UpdateProbeMode, npm: Bool = false) -> String {
        switch reason {
        case .noRegistry: "no registry"
        case .networkUnavailable:
            switch mode {
            case .offline: "offline mode was requested"
            case .localOnly, .checkUpdates, .refresh: "network unavailable"
            }
        case .probeFailed: "update probe failed"
        case .rateLimited: "rate limited"
        case .notChecked: "update check not requested"
        case .notInstalled: "not installed"
        case .unsupportedSource: "unsupported installation manager"
        case .installedVersionUnavailable: "installed version unavailable"
        case .unsupportedVersion: "unsupported version format"
        case .managerUnavailable: npm ? "npm not available on PATH" : "Homebrew not available on PATH"
        case .managerMismatch: "selected executable is not in the Homebrew Cellar"
        case .identityUnverified: "selected package could not be verified"
        case .diagnosticInconsistent: "PATH diagnostics are inconsistent"
        case .newerThanKnownMetadata: "installed version is newer than known metadata"
        case .unsupportedRegistry: "unsupported registry"
        case .unsupportedChannel: "unsupported update channel"
        case .budgetExhausted: "update stage budget exhausted"
        case .metadataInvalid: "invalid metadata"
        case .queryTimedOut: "metadata query timed out"
        }
    }

    /// ISO 8601 UTC with whole seconds, so output is deterministic for a fixed clock.
    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}
