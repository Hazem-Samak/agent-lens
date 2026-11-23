// HomebrewOperationEnvironment — the one environment builder for Homebrew mutations (M13-D R6).
//
// Every brew mutation is launched with exactly this environment. It starts from the M6 diagnostic
// environment (no hidden `brew update`, no analytics) and adds only the mutation switches R6 names.
// It deliberately does NOT add HOMEBREW_NO_ASK (`--yes` in the reviewed argv is the visible
// suppression) and does NOT redirect HOMEBREW_CACHE / HOMEBREW_LOGS / HOMEBREW_TEMP: Homebrew uses
// its own defaults exactly as the user's own brew would, the effect text discloses those manager
// writes, and Agent Lens never deletes them (D-008).
//
// The removals are deliberate and closed. Greedy-upgrade overrides would silently widen the target
// set, cask options would redirect app placement, the upgrade-quit override would falsify the
// "may quit" disclosure, and the autorremove override would disable the cleanup suppression this
// operation relies on. The user's captured environment is otherwise inherited unchanged.

import Foundation

public enum HomebrewOperationEnvironment {

    /// Variables removed from every Homebrew mutation, whatever the captured environment holds.
    public static let removedKeys: [String] = [
        "HOMEBREW_UPGRADE_GREEDY",
        "HOMEBREW_UPGRADE_GREEDY_CASKS",
        "HOMEBREW_NO_UPGRADE_QUIT_CASKS",
        "HOMEBREW_CASK_OPTS",
        "HOMEBREW_AUTOREMOVE",
    ]

    /// The exact switches this builder adds for one mutation kind. Update additionally suppresses
    /// Homebrew's check for outdated dependent formulae; Uninstall keeps that default so Homebrew's
    /// dependent refusal is surfaced honestly. Uninstall deliberately does not force this variable
    /// either way beyond that: Homebrew's uninstall dependent refusal is governed by the absence of
    /// `--ignore-dependencies` in the reviewed argv (and the tested argv never contains it), not by
    /// this upgrade-only switch, so an inherited value cannot bypass the refusal.
    public static func requiredSwitches(kind: HomebrewMutationKind) -> [String: String] {
        var switches = [
            "HOMEBREW_NO_AUTO_UPDATE": "1",
            "HOMEBREW_NO_ANALYTICS": "1",
            "HOMEBREW_NO_INSTALL_CLEANUP": "1",
            "HOMEBREW_NO_AUTOREMOVE": "1",
        ]
        if kind.isUpdate {
            switches["HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK"] = "1"
        }
        return switches
    }

    /// Builds the mutation environment from the captured login-shell environment. The caller's
    /// value is untouched; the returned dictionary is the exact process environment.
    public static func mutationEnvironment(
        from environment: ShellEnvironment,
        kind: HomebrewMutationKind
    ) -> [String: String] {
        var values = HomebrewUpdateProbe.diagnosticEnvironment(from: environment)
        for (key, value) in requiredSwitches(kind: kind) {
            values[key] = value
        }
        for key in removedKeys {
            values.removeValue(forKey: key)
        }
        return values
    }

    /// The stable confirmation binding for the captured environment and working directory. It is
    /// the same length-framed material the npm lifecycle uses, so a changed captured environment
    /// invalidates a preview without inventing a new identity scheme.
    static func contextFingerprint(
        environment: ShellEnvironment,
        currentDirectory: String
    ) -> String {
        let working = URL(fileURLWithPath: currentDirectory, isDirectory: true)
            .standardizedFileURL.path
        let values = environment.raw.keys.sorted().map {
            "\($0.utf8.count):\($0)\(environment.raw[$0]!.utf8.count):\(environment.raw[$0]!)"
        }.joined()
        return UpdateMetadataKey.stableDigest(
            "environment-context-v1" + "\(working.utf8.count):\(working)" + values
        )
    }
}
