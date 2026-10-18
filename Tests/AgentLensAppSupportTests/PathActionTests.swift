import Foundation
import Testing
@testable import AgentLensCore
@testable import AgentLensAppSupport

// MARK: - Fixture builders

private func makeDetectedTool(
    displayName: String = "Codex",
    executableName: String = "codex",
    entryPath: String? = "/usr/local/bin/codex",
    resolvedPath: String? = "/opt/homebrew/bin/codex"
) -> DetectedTool {
    DetectedTool(
        displayName: displayName,
        executableName: executableName,
        state: .installedAndOnPath,
        entryPath: entryPath,
        resolvedPath: resolvedPath,
        source: "npm",
        version: "0.1.0"
    )
}

private func makeCandidate(
    entryPath: String,
    canonicalTarget: String? = nil,
    kind: PathCandidateKind = .executableFile,
    slot: Int = 0
) -> PathCandidateObservation {
    PathCandidateObservation(
        origin: .path(slotIndex: slot, directoryText: "/usr/local/bin"),
        entryPath: entryPath,
        kind: kind,
        canonicalTarget: canonicalTarget
    )
}

private func makeDiagnostic(
    detectedTool: DetectedTool = makeDetectedTool(),
    selection: PathSelection,
    candidates: [PathCandidateObservation] = []
) -> ToolPathDiagnostic {
    let winner: PathCandidateObservation? = {
        switch selection {
        case .winner(let c), .offPath(let c, _): return c
        case .notInstalled, .inconsistent: return nil
        }
    }()
    return ToolPathDiagnostic(
        detectedTool: detectedTool,
        pathCandidates: candidates,
        firstLiveCandidate: winner,
        targetGroups: [],
        repeatedPathSlotCount: 0,
        sameTargetAliasCount: 0,
        selection: selection,
        shadowedInstallationCount: 0
    )
}

private func makeEntry(
    selection: PathSelection,
    candidates: [PathCandidateObservation] = [],
    detectedTool: DetectedTool = makeDetectedTool()
) -> InventoryEntry {
    let definition = DetectorDefinition(
        id: "codex",
        displayName: "Codex",
        executableName: "codex",
        extraSearchRoots: [],
        fixture: nil
    )
    return InventoryEntry(
        definition: definition,
        diagnostic: makeDiagnostic(
            detectedTool: detectedTool,
            selection: selection,
            candidates: candidates
        ),
        update: nil
    )
}

// MARK: - Target derivation: winner / off-PATH

@Suite("PathActionTarget target derivation")
struct PathActionTargetDerivationTests {

    @Test("Winner exposes actionable entry and target using candidate facts, not detectedTool")
    func winnerUsesCandidateFacts() {
        let candidate = makeCandidate(
            entryPath: "/usr/local/bin/codex",
            canonicalTarget: "/opt/homebrew/bin/codex"
        )
        // detectedTool.entryPath intentionally different/relative to prove it is ignored.
        let detected = makeDetectedTool(
            entryPath: "relative/detected/codex",
            resolvedPath: "relative/resolved/codex"
        )
        let entry = makeEntry(
            selection: .winner(candidate),
            candidates: [candidate],
            detectedTool: detected
        )

        let targets = PathActionTarget.targets(for: entry)
        #expect(targets.count == 2)

        let entryTarget = targets.first { $0.field == .selectedEntry }!
        let resolvedTarget = targets.first { $0.field == .resolvedTarget }!

        #expect(entryTarget.path == "/usr/local/bin/codex")
        #expect(entryTarget.isActionable)
        #expect(resolvedTarget.path == "/opt/homebrew/bin/codex")
        #expect(resolvedTarget.isActionable)
    }

    @Test("Off-PATH candidate is also actionable")
    func offPathIsActionable() {
        let candidate = makeCandidate(
            entryPath: "/opt/tools/codex",
            canonicalTarget: "/opt/tools/codex"
        )
        let entry = makeEntry(
            selection: .offPath(candidate: candidate, root: "/opt/tools"),
            candidates: [candidate]
        )
        let targets = PathActionTarget.targets(for: entry)
        let entryTarget = targets.first { $0.field == .selectedEntry }!
        #expect(entryTarget.isActionable)
        #expect(entryTarget.path == "/opt/tools/codex")
    }

    @Test("Identical entry and target are both independently actionable")
    func identicalPathBothUsable() {
        let candidate = makeCandidate(
            entryPath: "/usr/local/bin/codex",
            canonicalTarget: "/usr/local/bin/codex"
        )
        let entry = makeEntry(selection: .winner(candidate), candidates: [candidate])
        let targets = PathActionTarget.targets(for: entry)
        #expect(targets.allSatisfy { $0.isActionable })
        #expect(targets.allSatisfy { $0.path == "/usr/local/bin/codex" })
    }

    @Test("Symlink entry versus target are distinct actionables")
    func symlinkEntryVsTarget() {
        let candidate = makeCandidate(
            entryPath: "/usr/local/bin/codex",
            canonicalTarget: "/opt/homebrew/Cellar/codex/0.1/bin/codex",
            kind: .executableSymlink
        )
        let entry = makeEntry(selection: .winner(candidate), candidates: [candidate])
        let targets = PathActionTarget.targets(for: entry)
        let entryTarget = targets.first { $0.field == .selectedEntry }!
        let resolvedTarget = targets.first { $0.field == .resolvedTarget }!
        #expect(entryTarget.path == "/usr/local/bin/codex")
        #expect(resolvedTarget.path == "/opt/homebrew/Cellar/codex/0.1/bin/codex")
    }
}

// MARK: - Target derivation: absent / invalid selections

@Suite("PathActionTarget invalid input policy")
struct PathActionTargetInvalidInputTests {

    @Test("No selected tool yields noSelection for both fields")
    func noSelection() {
        let targets = PathActionTarget.targets(for: nil)
        #expect(targets.count == 2)
        #expect(targets.allSatisfy { !$0.isActionable })
        #expect(targets.allSatisfy { $0.ineligibility == .noSelection })
    }

    @Test("notInstalled exposes no enabled path actions")
    func notInstalled() {
        let entry = makeEntry(selection: .notInstalled)
        let targets = PathActionTarget.targets(for: entry)
        #expect(targets.allSatisfy { !$0.isActionable })
        #expect(targets.allSatisfy { $0.ineligibility == .notInstalled })
    }

    @Test("inconsistent exposes no enabled path actions")
    func inconsistent() {
        let entry = makeEntry(selection: .inconsistent("mismatch"))
        let targets = PathActionTarget.targets(for: entry)
        #expect(targets.allSatisfy { !$0.isActionable })
        #expect(targets.allSatisfy { $0.ineligibility == .inconsistent })
    }

    @Test("Missing canonicalTarget makes only the target field ineligible")
    func missingTargetValue() {
        let candidate = makeCandidate(
            entryPath: "/usr/local/bin/codex",
            canonicalTarget: nil
        )
        let entry = makeEntry(selection: .winner(candidate), candidates: [candidate])
        let targets = PathActionTarget.targets(for: entry)
        let entryTarget = targets.first { $0.field == .selectedEntry }!
        let resolvedTarget = targets.first { $0.field == .resolvedTarget }!
        #expect(entryTarget.isActionable)
        #expect(!resolvedTarget.isActionable)
        #expect(resolvedTarget.ineligibility == .missingValue)
    }

    @Test("Empty path is ineligible")
    func emptyPath() {
        #expect(PathActionTarget.ineligibility(forPath: "", gatedBy: .winner(makeCandidate(entryPath: ""))) == .empty)
    }

    @Test("Relative path is ineligible")
    func relativePath() {
        #expect(PathActionTarget.ineligibility(forPath: "bin/codex", gatedBy: .winner(makeCandidate(entryPath: "bin/codex"))) == .relativePath)
    }

    @Test("Path containing NUL is ineligible")
    func nulPath() {
        let withNul = "/usr/local/bin/co\u{0}dex"
        #expect(PathActionTarget.ineligibility(forPath: withNul, gatedBy: .winner(makeCandidate(entryPath: withNul))) == .containsNUL)
    }

    @Test("Unexpanded tilde is ineligible")
    func tildePath() {
        #expect(PathActionTarget.ineligibility(forPath: "~/bin/codex", gatedBy: .winner(makeCandidate(entryPath: "~/bin/codex"))) == .unexpandedTilde)
    }

    @Test("Each field validated independently")
    func independentValidation() {
        let candidate = makeCandidate(
            entryPath: "/usr/local/bin/codex",
            canonicalTarget: "relative/target"
        )
        let entry = makeEntry(selection: .winner(candidate), candidates: [candidate])
        let targets = PathActionTarget.targets(for: entry)
        #expect(targets.first { $0.field == .selectedEntry }!.isActionable)
        #expect(targets.first { $0.field == .resolvedTarget }!.ineligibility == .relativePath)
    }

    @Test("Literal special characters are preserved verbatim")
    func literalSpecialCharacters() {
        let tricky = "/tmp/a b/quote'\"/$HOME;|&*()[]{}?#%\\ é-ü"
        let inelig = PathActionTarget.ineligibility(
            forPath: tricky,
            gatedBy: .winner(makeCandidate(entryPath: tricky))
        )
        #expect(inelig == nil)
        let target = PathActionTarget(
            field: .selectedEntry,
            path: tricky,
            ineligibility: inelig
        )
        #expect(target.path == tricky)
    }
}

// MARK: - Action dispatch / failure policy via injected closures

@Suite("PathActionDispatcher policy")
struct PathActionDispatcherTests {

    @Test("Copy writes the exact literal path with no mutation")
    func copyWritesLiteralExact() {
        let tricky = "/tmp/a b/quote'\"/$HOME;|&*()[]{}?#%\\ é-ü"
        let target = PathActionTarget(field: .selectedEntry, path: tricky, ineligibility: nil)

        var written: [String?] = []
        let outcome = PathActionDispatcher.perform(
            .copyPath,
            target: target,
            pathExists: { _ in true },
            writeClipboard: { text in
                written.append(text)
                return true
            },
            revealInFinder: { _ in
                Issue.record("Reveal must not be called for copy")
                return .revealed
            }
        )
        #expect(outcome == .copied)
        #expect(written == [tricky])
    }

    @Test("Clipboard failure is reported, not claimed as success")
    func clipboardFailureReported() {
        let target = PathActionTarget(field: .selectedEntry, path: "/usr/local/bin/codex", ineligibility: nil)
        let outcome = PathActionDispatcher.perform(
            .copyPath,
            target: target,
            pathExists: { _ in true },
            writeClipboard: { _ in false },
            revealInFinder: { _ in .revealed }
        )
        #expect(outcome == .clipboardFailed)
        #expect(outcome != .copied)
    }

    @Test("Copy retains recorded text even if the path has disappeared (no existence check)")
    func copyDoesNotRequireExistence() {
        let target = PathActionTarget(field: .selectedEntry, path: "/gone/bin/codex", ineligibility: nil)
        var didCheckExistence = false
        var written: [String?] = []
        let outcome = PathActionDispatcher.perform(
            .copyPath,
            target: target,
            pathExists: { _ in didCheckExistence = true; return false },
            writeClipboard: { t in written.append(t); return true },
            revealInFinder: { _ in .revealed }
        )
        #expect(outcome == .copied)
        #expect(didCheckExistence == false)
        #expect(written == ["/gone/bin/codex"])
    }

    @Test("Ineligible target performs no action")
    func ineligiblePerformsNothing() {
        let target = PathActionTarget(field: .selectedEntry, path: nil, ineligibility: .missingValue)
        var clipboardTouched = false
        var finderTouched = false
        let outcome = PathActionDispatcher.perform(
            .copyPath,
            target: target,
            pathExists: { _ in true },
            writeClipboard: { _ in clipboardTouched = true; return true },
            revealInFinder: { _ in finderTouched = true; return .revealed }
        )
        #expect(outcome == .ineligible(.missingValue))
        #expect(clipboardTouched == false)
        #expect(finderTouched == false)
    }

    @Test("Reveal on a missing path requests no Finder call")
    func revealMissingDoesNotCallFinder() {
        let target = PathActionTarget(field: .selectedEntry, path: "/gone/bin/codex", ineligibility: nil)
        var finderCalls = 0
        let outcome = PathActionDispatcher.perform(
            .revealInFinder,
            target: target,
            pathExists: { _ in false },
            writeClipboard: { _ in Issue.record("clipboard must not be touched for reveal"); return true },
            revealInFinder: { _ in finderCalls += 1; return .revealed }
        )
        #expect(outcome == .revealMissing)
        #expect(finderCalls == 0)
    }

    @Test("Reveal on an existing path asks Finder and reports result")
    func revealExistingCallsFinder() {
        let target = PathActionTarget(field: .resolvedTarget, path: "/opt/homebrew/bin/codex", ineligibility: nil)
        var revealedPath: String?
        let outcome = PathActionDispatcher.perform(
            .revealInFinder,
            target: target,
            pathExists: { _ in true },
            writeClipboard: { _ in Issue.record("clipboard must not be touched for reveal"); return true },
            revealInFinder: { p in revealedPath = p; return .revealed }
        )
        #expect(outcome == .revealed)
        #expect(revealedPath == "/opt/homebrew/bin/codex")
    }
}
// MARK: - R2: constructor validity invariant (direct construction, nil reason)

@Suite("PathActionTarget constructor validity invariant")
struct PathActionTargetConstructorTests {

    /// Invalid raw paths that must never be actionable, even when a caller
    /// passes `nil` for the ineligibility argument.
    private static let invalidInputs: [(String, PathActionTarget.Ineligibility)] = [
        ("", .empty),
        ("bin/codex", .relativePath),
        ("~", .unexpandedTilde),
        ("~/bin/codex", .unexpandedTilde),
        ("/usr/local/bin/co\u{0}dex", .containsNUL),
    ]

    @Test("Direct construction with nil reason for nil path is not actionable")
    func nilPathWithNilReason() {
        let target = PathActionTarget(field: .selectedEntry, path: nil, ineligibility: nil)
        #expect(!target.isActionable)
        #expect(target.ineligibility == .missingValue)
    }

    @Test("Invalid raw paths with nil reason cannot be actionable")
    func invalidRawPathsNeverActionable() {
        for (raw, expected) in Self.invalidInputs {
            for field in [PathActionTarget.Field.selectedEntry, .resolvedTarget] {
                let target = PathActionTarget(field: field, path: raw, ineligibility: nil)
                #expect(!target.isActionable, "raw \(raw.debugDescription) field \(field) must be disabled")
                #expect(target.ineligibility == expected, "raw \(raw.debugDescription) reason")
            }
        }
    }

    @Test("Invalid constructed targets perform no callbacks for either action")
    func invalidConstructedTargetsPerformNothing() {
        for (raw, _) in Self.invalidInputs {
            let target = PathActionTarget(field: .selectedEntry, path: raw, ineligibility: nil)
            for action in [PathActionTarget.Action.copyPath, .revealInFinder] {
                var existenceChecked = false
                var clipboardTouched = false
                var finderTouched = false
                let outcome = PathActionDispatcher.perform(
                    action,
                    target: target,
                    pathExists: { _ in existenceChecked = true; return true },
                    writeClipboard: { _ in clipboardTouched = true; return true },
                    revealInFinder: { _ in finderTouched = true; return .revealed }
                )
                #expect(existenceChecked == false, "exists callback must not run for invalid raw \(raw.debugDescription)")
                #expect(clipboardTouched == false, "clipboard must not be touched for invalid raw \(raw.debugDescription)")
                #expect(finderTouched == false, "Finder must not be touched for invalid raw \(raw.debugDescription)")
                if case .ineligible = outcome {
                    // expected
                } else {
                    Issue.record("invalid target for \(raw.debugDescription) action \(action) must be ineligible, got \(outcome)")
                }
            }
        }
    }

    @Test("A valid absolute path with nil reason is still actionable and copies")
    func validPathStillActionable() {
        let target = PathActionTarget(field: .selectedEntry, path: "/usr/local/bin/codex", ineligibility: nil)
        #expect(target.isActionable)
        var written: [String?] = []
        let outcome = PathActionDispatcher.perform(
            .copyPath,
            target: target,
            pathExists: { _ in true },
            writeClipboard: { t in written.append(t); return true },
            revealInFinder: { _ in .revealed }
        )
        #expect(outcome == .copied)
        #expect(written == ["/usr/local/bin/codex"])
    }
}