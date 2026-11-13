// WorkflowPresentationTests — M12-A pure presentation-model tests.
//
// Every value here is constructed from Core's own validated types: a real `DetectorDefinition`, a
// `ToolPathDiagnostic` built from explicit observations, and update/ownership results that carry
// only the facts a test states. No test reads the real registry, PATH, cache, or any manager.
//
// The ruled contracts under test (judgment R1/R2/R3/R4/R8): conflict kinds are exactly three and
// count tools, measured versions only; `ManagementPresentation` reproduces the current controls and
// refusal text; the status filter is tri-state with unknown neutral; counts stay snapshot-derived.

@testable import AgentLensCore
import Foundation
import Testing
@testable import AgentLensAppSupport

// MARK: - Fixture construction

private func makeDefinition(
    id: String = "tool-id",
    displayName: String = "Tool",
    category: ToolCategory = .aiAgent,
    packages: [(PackageManager, String)] = [],
    accepted: [AcceptedOperation] = []
) throws -> DetectorDefinition {
    try DetectorDefinition(
        id: id,
        displayName: displayName,
        executableName: "tool",
        extraSearchRoots: [],
        fixture: nil,
        category: category,
        packages: try packages.map { try DeclaredPackage(manager: $0.0, name: $0.1) },
        informationURL: nil,
        uninstallInstructionsURL: nil,
        versionQuery: .standard,
        acceptedOperations: accepted
    )
}

private func makeCandidate(
    entryPath: String = "/fixture/bin/tool",
    target: String? = "/fixture/targets/tool",
    slotIndex: Int = 0
) -> PathCandidateObservation {
    PathCandidateObservation(
        origin: .path(slotIndex: slotIndex, directoryText: "/fixture/bin"),
        entryPath: entryPath,
        kind: .executableFile,
        canonicalTarget: target
    )
}

private func makeGroup(_ target: String, entryPath: String = "/fixture/bin/tool") -> PathTargetGroup {
    PathTargetGroup(canonicalTarget: target, entryPaths: [entryPath], firstSlotIndex: 0)
}

private func makeDiagnostic(
    state: InstallState = .installedAndOnPath,
    source: String = "npm",
    selection: PathSelection,
    groups: [PathTargetGroup] = [],
    shadowed: Int?,
    candidates: [PathCandidateObservation] = [],
    repeatedSlots: Int = 0,
    aliasCount: Int = 0,
    versions: [InstallationVersionObservation] = []
) -> ToolPathDiagnostic {
    ToolPathDiagnostic(
        detectedTool: DetectedTool(
            displayName: "Tool",
            executableName: "tool",
            state: state,
            entryPath: candidates.first { $0.kind.isLiveExecutable }?.entryPath,
            resolvedPath: candidates.first { $0.kind.isLiveExecutable }?.canonicalTarget,
            source: source,
            version: versions.compactMap(\.version).first
        ),
        pathCandidates: candidates,
        firstLiveCandidate: candidates.first { $0.kind.isLiveExecutable },
        targetGroups: groups,
        repeatedPathSlotCount: repeatedSlots,
        sameTargetAliasCount: aliasCount,
        selection: selection,
        shadowedInstallationCount: shadowed,
        installationVersions: versions
    )
}

private func measured(_ target: String, _ version: String) -> InstallationVersionObservation {
    InstallationVersionObservation(
        canonicalTarget: target,
        entryPath: "/fixture/bin/tool",
        origin: .path(slotIndex: 0, directoryText: "/fixture/bin"),
        fingerprint: nil,
        outcome: .measured(version)
    )
}

private func unmeasured(_ target: String) -> InstallationVersionObservation {
    InstallationVersionObservation(
        canonicalTarget: target,
        entryPath: "/fixture/bin/tool",
        origin: .path(slotIndex: 0, directoryText: "/fixture/bin"),
        fingerprint: nil,
        outcome: .unknown(.budgetExhausted)
    )
}

/// The winning single-copy installation every non-conflict test starts from.
private func singleWinnerDiagnostic(source: String = "npm") -> ToolPathDiagnostic {
    let candidate = makeCandidate()
    return makeDiagnostic(
        source: source,
        selection: .winner(candidate),
        groups: [makeGroup("/fixture/targets/tool")],
        shadowed: 0,
        candidates: [candidate],
        versions: [measured("/fixture/targets/tool", "1.0.0")]
    )
}

private func notInstalledDiagnostic() -> ToolPathDiagnostic {
    makeDiagnostic(state: .notInstalled, source: "unavailable", selection: .notInstalled, shadowed: 0)
}

private func makeEntry(
    definition: DetectorDefinition,
    diagnostic: ToolPathDiagnostic,
    update: ToolUpdateResult? = nil,
    ownership: InstallationOwnershipResult? = nil
) -> InventoryEntry {
    InventoryEntry(definition: definition, diagnostic: diagnostic, update: update, ownership: ownership)
}

private func makeUpdate(
    definition: DetectorDefinition,
    diagnostic: ToolPathDiagnostic,
    status: VersionStatus,
    npmPackage: String? = nil
) -> ToolUpdateResult {
    ToolUpdateResult(
        registryID: definition.id,
        displayName: definition.displayName,
        diagnosticIndex: 0,
        diagnostic: diagnostic,
        localVersion: nil,
        selectedEntryPath: nil,
        selectedTarget: nil,
        selectedKegVersion: nil,
        managerEntryPath: nil,
        managerTarget: nil,
        managerFingerprint: nil,
        managerCellar: nil,
        formulaStem: nil,
        fullFormulaName: nil,
        npmPackage: npmPackage,
        npmRegistry: nil,
        npmTag: nil,
        npmVersion: nil,
        status: status,
        provenance: .freshProbe(observedAt: Date(timeIntervalSince1970: 0))
    )
}

private func makeVerifiedOwnership(
    registryID: String,
    manager: PackageManager = .npm
) -> InstallationOwnershipResult {
    let fingerprint = ExecutableFingerprint(
        device: 1,
        inode: 2,
        mode: 0o755,
        size: 3,
        modifiedSeconds: 4,
        modifiedNanoseconds: 5,
        changedSeconds: 6,
        changedNanoseconds: 7
    )
    let selection = InstallationSelectionIdentity(
        entryPath: "/fixture/bin/tool",
        canonicalTarget: "/fixture/targets/tool",
        fingerprint: fingerprint
    )
    let installation = VerifiedInstallation(
        manager: manager,
        packageName: "@scope/tool",
        managerEntryPath: "/fixture/manager/bin/npm",
        managerTarget: "/fixture/manager/bin/npm",
        managerFingerprint: fingerprint,
        managerRoot: "/fixture/prefix",
        installationRoot: "/fixture/prefix/lib/node_modules/@scope/tool",
        selection: selection
    )
    return InstallationOwnershipResult(
        registryID: registryID,
        observedSelectedEntry: "/fixture/bin/tool",
        observedSelectedTarget: "/fixture/targets/tool",
        observedAt: Date(timeIntervalSince1970: 0),
        outcome: .verified(installation)
    )
}

// MARK: - R3: conflict classification

@Test func singleCopyWithOneCanonicalTargetIsNotAConflict() throws {
    let definition = try makeDefinition()
    let entry = makeEntry(definition: definition, diagnostic: singleWinnerDiagnostic())

    #expect(ToolConflict.kinds(for: entry.diagnostic).isEmpty)
    #expect(ToolConflict(entry: entry) == nil)
    #expect(InventorySnapshot(entries: [entry], isDegradedEnvironment: false).conflictToolCount == 0)
}

@Test func shadowedCopyReportsKindCopyCountAndMeasuredVersionsOnly() throws {
    let definition = try makeDefinition()
    let first = makeCandidate(entryPath: "/fixture/one/tool", target: "/fixture/targets/one", slotIndex: 0)
    let second = makeCandidate(entryPath: "/fixture/two/tool", target: "/fixture/targets/two", slotIndex: 1)
    let diagnostic = makeDiagnostic(
        selection: .winner(first),
        groups: [
            makeGroup("/fixture/targets/one", entryPath: "/fixture/one/tool"),
            makeGroup("/fixture/targets/two", entryPath: "/fixture/two/tool"),
        ],
        shadowed: 1,
        candidates: [first, second],
        versions: [
            measured("/fixture/targets/one", "1.0.0"),
            measured("/fixture/targets/two", "2.0.0"),
        ]
    )
    let conflict = try #require(ToolConflict(entry: makeEntry(definition: definition, diagnostic: diagnostic)))

    #expect(conflict.kinds == [.shadowedCopy])
    #expect(conflict.copyCount == 2)
    #expect(conflict.localVersions == ["1.0.0", "2.0.0"])
    #expect(conflict.winnerEntryPath == "/fixture/one/tool")
    #expect(conflict.offPathRoot == nil)
    #expect(conflict.inconsistencyReason == nil)
}

@Test func inconsistentSelectionWithNilShadowedIsInconsistentOnly() throws {
    let definition = try makeDefinition()
    let reason = "the detector selected an executable, but no live PATH or declared extra-root candidate was found"
    let diagnostic = makeDiagnostic(
        selection: .inconsistent(reason),
        shadowed: nil,
        versions: [measured("/fixture/targets/tool", "1.0.0")]
    )
    let conflict = try #require(ToolConflict(entry: makeEntry(definition: definition, diagnostic: diagnostic)))

    #expect(conflict.kinds == [.inconsistentDiagnostics])
    #expect(conflict.inconsistencyReason == reason)
    #expect(conflict.winnerEntryPath == nil)
    #expect(conflict.offPathRoot == nil)
    #expect(conflict.localVersions == ["1.0.0"])
}

@Test func offPathCopyWithPositiveShadowedReportsBothKindsInRuledOrder() throws {
    let definition = try makeDefinition()
    let offPath = PathCandidateObservation(
        origin: .extraRoot(index: 0, directoryText: "/fixture/extra"),
        entryPath: "/fixture/extra/tool",
        kind: .executableFile,
        canonicalTarget: "/fixture/targets/extra"
    )
    let diagnostic = makeDiagnostic(
        state: .installedNotOnPath,
        selection: .offPath(candidate: offPath, root: "/fixture/extra"),
        groups: [
            makeGroup("/fixture/targets/extra", entryPath: "/fixture/extra/tool"),
            makeGroup("/fixture/targets/other", entryPath: "/fixture/other/tool"),
        ],
        shadowed: 1,
        versions: [
            measured("/fixture/targets/extra", "1.0.0"),
            measured("/fixture/targets/other", "2.0.0"),
        ]
    )
    let conflict = try #require(ToolConflict(entry: makeEntry(definition: definition, diagnostic: diagnostic)))

    #expect(conflict.kinds == [.shadowedCopy, .offPathCopy])
    #expect(conflict.offPathRoot == "/fixture/extra")
    #expect(conflict.winnerEntryPath == nil)
    #expect(conflict.copyCount == 2)
}

@Test func aliasesAndRepeatedPathSlotsAreNotConflictKinds() throws {
    let definition = try makeDefinition()
    let diagnostic = makeDiagnostic(
        selection: .winner(makeCandidate()),
        groups: [makeGroup("/fixture/targets/tool")],
        shadowed: 0,
        candidates: [makeCandidate()],
        repeatedSlots: 3,
        aliasCount: 2,
        versions: [measured("/fixture/targets/tool", "1.0.0")]
    )

    #expect(ToolConflict.kinds(for: diagnostic).isEmpty)
    #expect(ToolConflict(entry: makeEntry(definition: definition, diagnostic: diagnostic)) == nil)
    // The closed vocabulary: exactly these three kinds, in this order.
    #expect(ToolConflictKind.allCases == [.shadowedCopy, .offPathCopy, .inconsistentDiagnostics])
}

@Test func notInstalledIsNeverAConflict() throws {
    let definition = try makeDefinition()
    let entry = makeEntry(definition: definition, diagnostic: notInstalledDiagnostic())

    #expect(ToolConflict(entry: entry) == nil)
    #expect(InventorySnapshot(entries: [entry], isDegradedEnvironment: false).conflictToolCount == 0)
}

@Test func conflictVersionsExcludeUnmeasuredTargetsAndNeverUseLatestVersions() throws {
    let definition = try makeDefinition()
    let first = makeCandidate(entryPath: "/fixture/one/tool", target: "/fixture/targets/one")
    let second = makeCandidate(entryPath: "/fixture/two/tool", target: "/fixture/targets/two", slotIndex: 1)
    let diagnostic = makeDiagnostic(
        selection: .winner(first),
        groups: [
            makeGroup("/fixture/targets/one", entryPath: "/fixture/one/tool"),
            makeGroup("/fixture/targets/two", entryPath: "/fixture/two/tool"),
        ],
        shadowed: 1,
        candidates: [first, second],
        versions: [
            measured("/fixture/targets/one", "1.0.0"),
            unmeasured("/fixture/targets/two"),
        ]
    )
    let update = makeUpdate(
        definition: definition,
        diagnostic: diagnostic,
        status: .updateAvailable(installed: Version("1.0.0"), latest: Version("9.9.9")),
        npmPackage: "@scope/tool"
    )
    let conflict = try #require(
        ToolConflict(entry: makeEntry(definition: definition, diagnostic: diagnostic, update: update))
    )

    #expect(conflict.localVersions == ["1.0.0"])
    #expect(!conflict.localVersions.contains("9.9.9"))
}

@Test func conflictToolCountCountsToolsNotKinds() throws {
    let definition = try makeDefinition()
    let offPath = PathCandidateObservation(
        origin: .extraRoot(index: 0, directoryText: "/fixture/extra"),
        entryPath: "/fixture/extra/tool",
        kind: .executableFile,
        canonicalTarget: "/fixture/targets/extra"
    )
    let twoKinds = makeDiagnostic(
        state: .installedNotOnPath,
        selection: .offPath(candidate: offPath, root: "/fixture/extra"),
        groups: [makeGroup("/fixture/targets/extra")],
        shadowed: 2
    )
    let oneKind = makeDiagnostic(selection: .inconsistent("stored reason"), shadowed: nil)
    let clean = singleWinnerDiagnostic()

    let snapshot = InventorySnapshot(
        entries: [
            makeEntry(definition: definition, diagnostic: twoKinds),
            makeEntry(definition: definition, diagnostic: oneKind),
            makeEntry(definition: definition, diagnostic: clean),
        ],
        isDegradedEnvironment: false
    )

    #expect(snapshot.conflictToolCount == 2)
    #expect(snapshot.offPathToolCount == 1)
}

// MARK: - R2: list scope and update-status filter membership

@Test func listScopeMembershipIsScopeOnly() throws {
    let definition = try makeDefinition(category: .aiHarness)
    let installed = makeEntry(definition: definition, diagnostic: singleWinnerDiagnostic())
    let notInstalled = makeEntry(definition: definition, diagnostic: notInstalledDiagnostic())

    #expect(ListScope.all.includes(installed))
    #expect(ListScope.all.includes(notInstalled))
    #expect(ListScope.updates.includes(installed))
    #expect(!ListScope.updates.includes(notInstalled))
    #expect(ListScope.category(.aiHarness).includes(installed))
    #expect(!ListScope.category(.aiAgent).includes(installed))
}

@Test func updateStatusFilterIsTriStateAndUnknownIsNeverCurrent() throws {
    let definition = try makeDefinition()
    let diagnostic = singleWinnerDiagnostic()
    let notChecked = makeEntry(definition: definition, diagnostic: diagnostic, update: nil)
    let unknown = makeEntry(
        definition: definition,
        diagnostic: diagnostic,
        update: makeUpdate(
            definition: definition,
            diagnostic: diagnostic,
            status: .unknown(installed: Version("1.0.0"), reason: .networkUnavailable)
        )
    )
    let upToDate = makeEntry(
        definition: definition,
        diagnostic: diagnostic,
        update: makeUpdate(
            definition: definition,
            diagnostic: diagnostic,
            status: .upToDate(installed: Version("1.0.0"), latest: Version("1.0.0"))
        )
    )
    let available = makeEntry(
        definition: definition,
        diagnostic: diagnostic,
        update: makeUpdate(
            definition: definition,
            diagnostic: diagnostic,
            status: .updateAvailable(installed: Version("1.0.0"), latest: Version("2.0.0")),
            npmPackage: "@scope/tool"
        )
    )

    #expect(UpdateStatusFilter.all.includes(notChecked))
    #expect(UpdateStatusFilter.all.includes(available))

    #expect(UpdateStatusFilter.updateAvailable.includes(available))
    #expect(!UpdateStatusFilter.updateAvailable.includes(unknown))
    #expect(!UpdateStatusFilter.updateAvailable.includes(upToDate))
    #expect(!UpdateStatusFilter.updateAvailable.includes(notChecked))

    #expect(UpdateStatusFilter.upToDate.includes(upToDate))
    #expect(!UpdateStatusFilter.upToDate.includes(available))

    #expect(UpdateStatusFilter.unknown.includes(unknown))
    #expect(!UpdateStatusFilter.unknown.includes(upToDate))

    #expect(UpdateStatusFilter.notChecked.includes(notChecked))
    #expect(!UpdateStatusFilter.notChecked.includes(unknown))
}

@Test func unknownAndUpToDateNeverInflateTheUpdateAvailableCount() throws {
    let definition = try makeDefinition()
    let diagnostic = singleWinnerDiagnostic()
    let snapshot = InventorySnapshot(
        entries: [
            makeEntry(
                definition: definition,
                diagnostic: diagnostic,
                update: makeUpdate(
                    definition: definition,
                    diagnostic: diagnostic,
                    status: .unknown(installed: nil, reason: .managerUnavailable)
                )
            ),
            makeEntry(
                definition: definition,
                diagnostic: diagnostic,
                update: makeUpdate(
                    definition: definition,
                    diagnostic: diagnostic,
                    status: .upToDate(installed: Version("1.0.0"), latest: Version("1.0.0"))
                )
            ),
        ],
        isDegradedEnvironment: false
    )

    #expect(snapshot.updateAvailableCount == 0)
}

// MARK: - R4: ManagementPresentation

@Test func codexShapedEntryOffersBothNpmControlsAndTheCaskSentenceAsAdditionalText() throws {
    let definition = try makeDefinition(
        id: "codex-id",
        displayName: "Codex",
        packages: [(.npm, "@openai/codex"), (.homebrewCask, "codex")],
        accepted: [.npmUpdate, .npmUninstall]
    )
    let diagnostic = singleWinnerDiagnostic()
    let entry = makeEntry(
        definition: definition,
        diagnostic: diagnostic,
        update: makeUpdate(
            definition: definition,
            diagnostic: diagnostic,
            status: .updateAvailable(installed: Version("1.0.0"), latest: Version("2.0.0")),
            npmPackage: "@openai/codex"
        ),
        ownership: makeVerifiedOwnership(registryID: "codex-id")
    )
    let presentation = ManagementPresentation(entry: entry)

    #expect(presentation.update == .prepareNpmUpdate)
    #expect(presentation.uninstall == .prepareNpmUninstall)
    #expect(presentation.otherLimits == [
        "Homebrew cask update and uninstall are not available in this version."
    ])
}

@Test func formulaOnlyEntryExplainsTheLimitAndOffersNoControl() throws {
    let definition = try makeDefinition(
        id: "hermes-id",
        displayName: "Hermes",
        packages: [(.homebrewFormula, "hermes")]
    )
    let entry = makeEntry(
        definition: definition,
        diagnostic: singleWinnerDiagnostic(source: "brew")
    )
    let presentation = ManagementPresentation(entry: entry)

    #expect(presentation.update == .hidden)
    #expect(presentation.uninstall == .hidden)
    #expect(presentation.otherLimits == [
        "Homebrew formula update and uninstall are not available in this version."
    ])
}

@Test func caskOnlyEntryExplainsTheLimitAndOffersNoControl() throws {
    let definition = try makeDefinition(
        id: "grok-id",
        displayName: "Grok",
        packages: [(.homebrewCask, "grok")]
    )
    let entry = makeEntry(
        definition: definition,
        diagnostic: singleWinnerDiagnostic(source: "brew")
    )
    let presentation = ManagementPresentation(entry: entry)

    #expect(presentation.update == .hidden)
    #expect(presentation.uninstall == .hidden)
    #expect(presentation.otherLimits == [
        "Homebrew cask update and uninstall are not available in this version."
    ])
}

@Test func standaloneCopyExplainsThatAgentLensDeletesNothing() throws {
    let definition = try makeDefinition()
    let entry = makeEntry(
        definition: definition,
        diagnostic: singleWinnerDiagnostic(source: "standalone")
    )
    let presentation = ManagementPresentation(entry: entry)

    #expect(presentation.update == .hidden)
    #expect(presentation.uninstall == .hidden)
    #expect(presentation.otherLimits == [
        "This copy is classified as standalone. Agent Lens does not delete standalone files."
    ])
}

@Test func npmSourceAddsNoStandaloneSentenceAndNotInstalledAddsNoLimits() throws {
    let definition = try makeDefinition(
        packages: [(.homebrewFormula, "tool"), (.homebrewCask, "tool")]
    )
    let npmEntry = makeEntry(definition: definition, diagnostic: singleWinnerDiagnostic(source: "npm"))
    #expect(!ManagementPresentation(entry: npmEntry).otherLimits.contains { $0.contains("standalone") })

    let absent = makeEntry(
        definition: definition,
        diagnostic: makeDiagnostic(
            state: .notInstalled,
            source: "standalone",
            selection: .notInstalled,
            shadowed: 0
        )
    )
    let absentPresentation = ManagementPresentation(entry: absent)
    #expect(absentPresentation.update == .hidden)
    #expect(absentPresentation.uninstall == .hidden)
    #expect(absentPresentation.otherLimits.isEmpty)
}

@Test func otherLimitsReportEachDeclaredManagerOnceInFixedOrder() throws {
    let definition = try makeDefinition(
        packages: [(.homebrewFormula, "tool"), (.homebrewCask, "tool")]
    )
    let entry = makeEntry(
        definition: definition,
        diagnostic: singleWinnerDiagnostic(source: "standalone")
    )

    #expect(ManagementPresentation(entry: entry).otherLimits == [
        "Homebrew formula update and uninstall are not available in this version.",
        "Homebrew cask update and uninstall are not available in this version.",
        "This copy is classified as standalone. Agent Lens does not delete standalone files.",
    ])
}

@Test func unacceptedNpmUpdateUsesTheCoreEnumMessage() throws {
    let definition = try makeDefinition(
        packages: [(.npm, "@scope/tool")],
        accepted: []
    )
    let diagnostic = singleWinnerDiagnostic()
    let entry = makeEntry(
        definition: definition,
        diagnostic: diagnostic,
        update: makeUpdate(
            definition: definition,
            diagnostic: diagnostic,
            status: .updateAvailable(installed: Version("1.0.0"), latest: Version("2.0.0")),
            npmPackage: "@scope/tool"
        )
    )
    let presentation = ManagementPresentation(entry: entry)

    #expect(
        presentation.update
            == .unavailable(NpmUpdateUnavailableReason.operationNotAccepted.message)
    )
}

@Test func updateAvailableWithoutAnNpmPackageReportsTheFixedSentence() throws {
    let definition = try makeDefinition(packages: [(.homebrewFormula, "tool")], accepted: [.npmUpdate])
    let diagnostic = singleWinnerDiagnostic(source: "brew")
    let entry = makeEntry(
        definition: definition,
        diagnostic: diagnostic,
        update: makeUpdate(
            definition: definition,
            diagnostic: diagnostic,
            status: .updateAvailable(installed: Version("1.0.0"), latest: Version("2.0.0")),
            npmPackage: nil
        )
    )

    #expect(
        ManagementPresentation(entry: entry).update
            == .unavailable(
                "A newer version is reported by the supported latest check. Managed update is not available for this installation in this version."
            )
    )
}

@Test func notCheckedUpToDateAndUnknownGrowNoUpdateAffordance() throws {
    let definition = try makeDefinition(
        packages: [(.npm, "@scope/tool")],
        accepted: [.npmUpdate]
    )
    let diagnostic = singleWinnerDiagnostic()
    let upToDate = makeEntry(
        definition: definition,
        diagnostic: diagnostic,
        update: makeUpdate(
            definition: definition,
            diagnostic: diagnostic,
            status: .upToDate(installed: Version("1.0.0"), latest: Version("1.0.0")),
            npmPackage: "@scope/tool"
        )
    )
    let unknown = makeEntry(
        definition: definition,
        diagnostic: diagnostic,
        update: makeUpdate(
            definition: definition,
            diagnostic: diagnostic,
            status: .unknown(installed: Version("1.0.0"), reason: .probeFailed),
            npmPackage: "@scope/tool"
        )
    )
    let notChecked = makeEntry(definition: definition, diagnostic: diagnostic, update: nil)

    #expect(ManagementPresentation(entry: upToDate).update == .hidden)
    #expect(ManagementPresentation(entry: unknown).update == .hidden)
    #expect(ManagementPresentation(entry: notChecked).update == .hidden)
}

@Test func unacceptedNpmUninstallUsesTheCoreEnumMessage() throws {
    let definition = try makeDefinition(packages: [(.npm, "@scope/tool")], accepted: [.npmUpdate])
    let entry = makeEntry(
        definition: definition,
        diagnostic: singleWinnerDiagnostic(),
        ownership: makeVerifiedOwnership(registryID: "tool-id")
    )
    let presentation = ManagementPresentation(entry: entry)

    #expect(
        presentation.uninstall
            == .unavailable(NpmUninstallUnavailableReason.operationNotAccepted.message)
    )
}

@Test func acceptedUninstallWithoutVerifiedNpmOwnershipNeedsVerification() throws {
    let definition = try makeDefinition(
        packages: [(.npm, "@scope/tool")],
        accepted: [.npmUninstall]
    )

    let unverified = makeEntry(definition: definition, diagnostic: singleWinnerDiagnostic())
    #expect(
        ManagementPresentation(entry: unverified).uninstall
            == .needsVerification("Verify Installation to enable Uninstall for this npm package.")
    )

    let verifiedButHomebrew = makeEntry(
        definition: definition,
        diagnostic: singleWinnerDiagnostic(),
        ownership: makeVerifiedOwnership(registryID: "tool-id", manager: .homebrewCask)
    )
    #expect(
        ManagementPresentation(entry: verifiedButHomebrew).uninstall
            == .needsVerification("Verify Installation to enable Uninstall for this npm package.")
    )

    let verifiedButInconsistent = makeEntry(
        definition: definition,
        diagnostic: makeDiagnostic(selection: .inconsistent("stored reason"), shadowed: nil),
        ownership: makeVerifiedOwnership(registryID: "tool-id")
    )
    #expect(
        ManagementPresentation(entry: verifiedButInconsistent).uninstall
            == .needsVerification("Verify Installation to enable Uninstall for this npm package.")
    )
}

@Test func noDeclaredNpmPackageHidesTheUninstallSlot() throws {
    let definition = try makeDefinition(packages: [(.homebrewFormula, "tool")])
    let presentation = ManagementPresentation(
        entry: makeEntry(definition: definition, diagnostic: singleWinnerDiagnostic(source: "brew"))
    )

    #expect(presentation.uninstall == .hidden)
}
