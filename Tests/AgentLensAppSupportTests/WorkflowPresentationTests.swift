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
    npmPackage: String? = nil,
    formulaStem: String? = nil,
    fullFormulaName: String? = nil,
    caskToken: String? = nil,
    caskFullToken: String? = nil,
    registryID: String? = nil,
    selectedEntryPath: String? = nil,
    selectedTarget: String? = nil
) -> ToolUpdateResult {
    let isHomebrew = formulaStem != nil || caskToken != nil
    return ToolUpdateResult(
        registryID: registryID ?? definition.id,
        displayName: definition.displayName,
        diagnosticIndex: 0,
        diagnostic: diagnostic,
        localVersion: nil,
        selectedEntryPath: selectedEntryPath ?? (isHomebrew ? "/fixture/bin/tool" : nil),
        selectedTarget: selectedTarget ?? (isHomebrew ? "/fixture/targets/tool" : nil),
        selectedKegVersion: formulaStem != nil ? "1.0.0" : nil,
        managerEntryPath: isHomebrew ? "/fixture/prefix/bin/brew" : nil,
        managerTarget: isHomebrew ? "/fixture/prefix/bin/brew" : nil,
        managerFingerprint: nil,
        managerCellar: formulaStem != nil ? "/fixture/prefix/Cellar" : nil,
        formulaStem: formulaStem,
        fullFormulaName: fullFormulaName,
        npmPackage: npmPackage,
        npmRegistry: nil,
        npmTag: nil,
        npmVersion: nil,
        caskToken: caskToken,
        caskFullToken: caskFullToken,
        status: status,
        provenance: .freshProbe(observedAt: Date(timeIntervalSince1970: 0))
    )
}

private func makeVerifiedOwnership(
    registryID: String,
    manager: PackageManager = .npm,
    selectionEntryPath: String = "/fixture/bin/tool",
    selectionTarget: String = "/fixture/targets/tool"
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
        entryPath: selectionEntryPath,
        canonicalTarget: selectionTarget,
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
        observedSelectedEntry: selectionEntryPath,
        observedSelectedTarget: selectionTarget,
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
        HomebrewCaskUpdateUnavailableReason.operationNotAccepted.message
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
    #expect(
        presentation.uninstall
            == .unavailable(HomebrewFormulaUninstallUnavailableReason.operationNotAccepted.message)
    )
    #expect(presentation.otherLimits == [
        HomebrewFormulaUpdateUnavailableReason.operationNotAccepted.message
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
    #expect(
        presentation.uninstall
            == .unavailable(HomebrewCaskUninstallUnavailableReason.operationNotAccepted.message)
    )
    #expect(presentation.otherLimits == [
        HomebrewCaskUpdateUnavailableReason.operationNotAccepted.message
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
        HomebrewFormulaUpdateUnavailableReason.operationNotAccepted.message,
        HomebrewCaskUpdateUnavailableReason.operationNotAccepted.message,
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

@Test func noDeclaredNpmPackageHidesTheNpmUninstallRoute() throws {
    let definition = try makeDefinition(packages: [(.homebrewFormula, "tool")])
    let presentation = ManagementPresentation(
        entry: makeEntry(definition: definition, diagnostic: singleWinnerDiagnostic(source: "brew"))
    )

    // The npm route is absent, but the declared formula's own Core refusal is the truthful
    // per-entry explanation; it is never the retired fixed version sentence.
    #expect(
        presentation.uninstall
            == .unavailable(HomebrewFormulaUninstallUnavailableReason.operationNotAccepted.message)
    )
}

// MARK: - R11: Homebrew affordance truth table

private func formulaUpdate(
    definition: DetectorDefinition,
    diagnostic: ToolPathDiagnostic,
    target: String = "2.0.0"
) -> ToolUpdateResult {
    makeUpdate(
        definition: definition,
        diagnostic: diagnostic,
        status: .updateAvailable(installed: Version("1.0.0"), latest: Version(target)),
        formulaStem: "tool",
        fullFormulaName: "tool"
    )
}

private func caskUpdate(
    definition: DetectorDefinition,
    diagnostic: ToolPathDiagnostic,
    target: String = "2.0.0"
) -> ToolUpdateResult {
    makeUpdate(
        definition: definition,
        diagnostic: diagnostic,
        status: .updateAvailable(installed: Version("1.0.0"), latest: Version(target)),
        caskToken: "tool",
        caskFullToken: "tool"
    )
}

@Test func promotedFormulaOffersBothBrewControlsWhenOwnershipIsVerified() throws {
    let definition = try makeDefinition(
        id: "hermes-id",
        packages: [(.homebrewFormula, "hermes-agent")],
        accepted: [.homebrewFormulaUpdate, .homebrewFormulaUninstall]
    )
    let diagnostic = singleWinnerDiagnostic(source: "brew")
    let entry = makeEntry(
        definition: definition,
        diagnostic: diagnostic,
        update: formulaUpdate(definition: definition, diagnostic: diagnostic),
        ownership: makeVerifiedOwnership(registryID: "hermes-id", manager: .homebrewFormula)
    )
    let presentation = ManagementPresentation(entry: entry)

    #expect(presentation.update == .prepareFormulaUpdate)
    #expect(presentation.update.isPrepare)
    #expect(presentation.uninstall == .prepareFormulaUninstall)
    #expect(presentation.uninstall.isPrepare)
    #expect(presentation.otherLimits.isEmpty)
}

@Test func promotedFormulaUpdateNeedsNoExplicitOwnershipButUninstallNeedsVerification() throws {
    let definition = try makeDefinition(
        id: "hermes-id",
        packages: [(.homebrewFormula, "hermes-agent")],
        accepted: [.homebrewFormulaUpdate, .homebrewFormulaUninstall]
    )
    let diagnostic = singleWinnerDiagnostic(source: "brew")
    let entry = makeEntry(
        definition: definition,
        diagnostic: diagnostic,
        update: formulaUpdate(definition: definition, diagnostic: diagnostic)
    )
    let presentation = ManagementPresentation(entry: entry)

    #expect(presentation.update == .prepareFormulaUpdate)
    #expect(
        presentation.uninstall
            == .needsVerification(
                "Verify Installation to enable Uninstall for this Homebrew formula."
            )
    )
    #expect(presentation.update.isPrepare)
    #expect(presentation.otherLimits.isEmpty)
}

@Test func promotedCaskOffersBothBrewControlsAndSuppressesTheStandaloneSentence() throws {
    let definition = try makeDefinition(
        id: "kiro-id",
        packages: [(.homebrewCask, "kiro-cli")],
        accepted: [.homebrewCaskUpdate, .homebrewCaskUninstall]
    )
    let diagnostic = singleWinnerDiagnostic(source: "standalone")
    let entry = makeEntry(
        definition: definition,
        diagnostic: diagnostic,
        update: caskUpdate(definition: definition, diagnostic: diagnostic),
        ownership: makeVerifiedOwnership(registryID: "kiro-id", manager: .homebrewCask)
    )
    let presentation = ManagementPresentation(entry: entry)

    #expect(presentation.update == .prepareCaskUpdate)
    #expect(presentation.uninstall == .prepareCaskUninstall)
    // The source heuristic may still say standalone, but a verified cask copy is Homebrew-owned.
    #expect(!presentation.otherLimits.contains { $0.contains("standalone") })
    #expect(presentation.otherLimits.isEmpty)
}

@Test func verifiedCaskOwnershipSuppressesStandaloneWithoutAnyUpdateResult() throws {
    let definition = try makeDefinition(
        id: "kiro-id",
        packages: [(.homebrewCask, "kiro-cli")],
        accepted: [.homebrewCaskUpdate, .homebrewCaskUninstall]
    )
    let entry = makeEntry(
        definition: definition,
        diagnostic: singleWinnerDiagnostic(source: "standalone"),
        ownership: makeVerifiedOwnership(registryID: "kiro-id", manager: .homebrewCask)
    )
    let presentation = ManagementPresentation(entry: entry)

    #expect(presentation.update == .hidden)
    #expect(presentation.uninstall == .prepareCaskUninstall)
    #expect(presentation.otherLimits.isEmpty)
}

@Test func uninstallDoesNotDependOnVersionStatusButUpdateDoes() throws {
    let definition = try makeDefinition(
        id: "aider-id",
        packages: [(.homebrewFormula, "aider")],
        accepted: [.homebrewFormulaUpdate, .homebrewFormulaUninstall]
    )
    let entry = makeEntry(
        definition: definition,
        diagnostic: singleWinnerDiagnostic(source: "brew"),
        ownership: makeVerifiedOwnership(registryID: "aider-id", manager: .homebrewFormula)
    )
    let presentation = ManagementPresentation(entry: entry)

    #expect(presentation.update == .hidden)
    #expect(presentation.uninstall == .prepareFormulaUninstall)
}

@Test func brewUpdateIdentityMustAgreeWithTheDeclaredManagerAndAcceptedOperation() throws {
    // A cask-shaped update result on a formula-only, formula-accepting entry is not silently
    // presented as a formula update; it falls back to the honest "no managed update" sentence.
    let formulaDefinition = try makeDefinition(
        id: "formula-id",
        packages: [(.homebrewFormula, "tool")],
        accepted: [.homebrewFormulaUpdate, .homebrewFormulaUninstall]
    )
    let formulaDiagnostic = singleWinnerDiagnostic(source: "brew")
    let mismatched = makeEntry(
        definition: formulaDefinition,
        diagnostic: formulaDiagnostic,
        update: caskUpdate(definition: formulaDefinition, diagnostic: formulaDiagnostic)
    )
    #expect(
        ManagementPresentation(entry: mismatched).update
            == .unavailable(
                "A newer version is reported by the supported latest check. Managed update is not available for this installation in this version."
            )
    )

    // A promoted cask accepting only its own update kind never borrows the formula reason.
    let unaccepted = try makeDefinition(
        id: "kiro-id",
        packages: [(.homebrewCask, "kiro-cli")],
        accepted: [.homebrewCaskUninstall]
    )
    let caskDiagnostic = singleWinnerDiagnostic(source: "brew")
    let caskEntry = makeEntry(
        definition: unaccepted,
        diagnostic: caskDiagnostic,
        update: caskUpdate(definition: unaccepted, diagnostic: caskDiagnostic)
    )
    #expect(
        ManagementPresentation(entry: caskEntry).update
            == .unavailable(HomebrewCaskUpdateUnavailableReason.operationNotAccepted.message)
    )
}

@Test func unacceptedFormulaUpdateExplainsWhyAndDoesNotRepeatTheReason() throws {
    let definition = try makeDefinition(
        id: "opencode-id",
        packages: [(.homebrewFormula, "opencode")],
        accepted: []
    )
    let diagnostic = singleWinnerDiagnostic(source: "brew")
    let entry = makeEntry(
        definition: definition,
        diagnostic: diagnostic,
        update: formulaUpdate(definition: definition, diagnostic: diagnostic)
    )
    let presentation = ManagementPresentation(entry: entry)

    #expect(
        presentation.update
            == .unavailable(HomebrewFormulaUpdateUnavailableReason.operationNotAccepted.message)
    )
    // The not-promoted "why" is already the update slot's text, so it is not duplicated as a
    // manager-limit sentence.
    #expect(presentation.otherLimits.isEmpty)
    #expect(
        presentation.uninstall
            == .unavailable(HomebrewFormulaUninstallUnavailableReason.operationNotAccepted.message)
    )
}

@Test func acceptedUpdateWithoutAcceptedUninstallExplainsTheRemovalGap() throws {
    let definition = try makeDefinition(
        id: "hermes-id",
        packages: [(.homebrewFormula, "hermes-agent")],
        accepted: [.homebrewFormulaUpdate]
    )
    let diagnostic = singleWinnerDiagnostic(source: "brew")
    let entry = makeEntry(
        definition: definition,
        diagnostic: diagnostic,
        update: formulaUpdate(definition: definition, diagnostic: diagnostic)
    )
    let presentation = ManagementPresentation(entry: entry)

    #expect(presentation.update == .prepareFormulaUpdate)
    #expect(
        presentation.uninstall
            == .unavailable(HomebrewFormulaUninstallUnavailableReason.operationNotAccepted.message)
    )
    #expect(presentation.otherLimits.isEmpty)
}

@Test func verifiedManagerKindMustMatchTheDeclaredManagerForUninstall() throws {
    // A verified cask copy on a formula-declaring entry never offers a cask button; the declared
    // formula's accepted operation still only reaches the verification hint.
    let definition = try makeDefinition(
        id: "formula-id",
        packages: [(.homebrewFormula, "tool")],
        accepted: [.homebrewFormulaUninstall]
    )
    let entry = makeEntry(
        definition: definition,
        diagnostic: singleWinnerDiagnostic(source: "brew"),
        ownership: makeVerifiedOwnership(registryID: "formula-id", manager: .homebrewCask)
    )
    let presentation = ManagementPresentation(entry: entry)

    #expect(
        presentation.uninstall
            == .needsVerification(
                "Verify Installation to enable Uninstall for this Homebrew formula."
            )
    )
}

@Test func codexNpmRouteStaysByteIdenticalAndTheCaskOnlyExplainsItsOwnReason() throws {
    let definition = try makeDefinition(
        id: "codex-id",
        displayName: "Codex",
        packages: [(.npm, "@openai/codex"), (.homebrewCask, "codex")],
        accepted: [.npmUpdate, .npmUninstall]
    )
    let diagnostic = singleWinnerDiagnostic(source: "npm")
    let entry = makeEntry(
        definition: definition,
        diagnostic: diagnostic,
        update: makeUpdate(
            definition: definition,
            diagnostic: diagnostic,
            status: .updateAvailable(installed: Version("1.0.0"), latest: Version("2.0.0")),
            npmPackage: "@openai/codex"
        ),
        ownership: makeVerifiedOwnership(registryID: "codex-id", manager: .npm)
    )
    let presentation = ManagementPresentation(entry: entry)

    #expect(presentation.update == .prepareNpmUpdate)
    #expect(presentation.uninstall == .prepareNpmUninstall)
    #expect(presentation.otherLimits == [
        HomebrewCaskUpdateUnavailableReason.operationNotAccepted.message
    ])
}

@Test func notInstalledBrewEntriesOfferNoControlsAndNoLimits() throws {
    let definition = try makeDefinition(
        id: "hermes-id",
        packages: [(.homebrewFormula, "hermes-agent")],
        accepted: [.homebrewFormulaUpdate, .homebrewFormulaUninstall]
    )
    let entry = makeEntry(
        definition: definition,
        diagnostic: notInstalledDiagnostic(),
        ownership: makeVerifiedOwnership(registryID: "hermes-id", manager: .homebrewFormula)
    )
    let presentation = ManagementPresentation(entry: entry)

    #expect(presentation.update == .hidden)
    #expect(presentation.uninstall == .hidden)
    #expect(presentation.otherLimits.isEmpty)
}

@Test func prepareAffordanceFlagsIdentifyExactlyTheActionableShapes() {
    #expect(ManagementPresentation.UpdateAffordance.prepareNpmUpdate.isPrepare)
    #expect(ManagementPresentation.UpdateAffordance.prepareFormulaUpdate.isPrepare)
    #expect(ManagementPresentation.UpdateAffordance.prepareCaskUpdate.isPrepare)
    #expect(!ManagementPresentation.UpdateAffordance.unavailable("reason").isPrepare)
    #expect(!ManagementPresentation.UpdateAffordance.hidden.isPrepare)

    #expect(ManagementPresentation.UninstallAffordance.prepareNpmUninstall.isPrepare)
    #expect(ManagementPresentation.UninstallAffordance.prepareFormulaUninstall.isPrepare)
    #expect(ManagementPresentation.UninstallAffordance.prepareCaskUninstall.isPrepare)
    #expect(!ManagementPresentation.UninstallAffordance.needsVerification("verify").isPrepare)
    #expect(!ManagementPresentation.UninstallAffordance.unavailable("reason").isPrepare)
    #expect(!ManagementPresentation.UninstallAffordance.hidden.isPrepare)
}

// MARK: - R11: exact evidence, contradictions and manager shadowing

@Test func promotedCaskUpdateOffersItsControlButUninstallStillNeedsVerification() throws {
    let definition = try makeDefinition(
        id: "kiro-id",
        packages: [(.homebrewCask, "kiro-cli")],
        accepted: [.homebrewCaskUpdate, .homebrewCaskUninstall]
    )
    let diagnostic = singleWinnerDiagnostic(source: "standalone")
    let entry = makeEntry(
        definition: definition,
        diagnostic: diagnostic,
        update: caskUpdate(definition: definition, diagnostic: diagnostic)
    )
    let presentation = ManagementPresentation(entry: entry)

    #expect(presentation.update == .prepareCaskUpdate)
    #expect(presentation.uninstall.isPrepare == false)
    #expect(
        presentation.uninstall
            == .needsVerification(
                "Verify Installation to enable Uninstall for this Homebrew cask."
            )
    )
    // Nothing is verified yet, so the standalone classification is still disclosed.
    #expect(presentation.otherLimits == [
        "This copy is classified as standalone. Agent Lens does not delete standalone files."
    ])
}

@Test func ownershipForAnotherSelectionIsNotProofForThisEntry() throws {
    let definition = try makeDefinition(
        id: "hermes-id",
        packages: [(.homebrewFormula, "hermes-agent")],
        accepted: [.homebrewFormulaUpdate, .homebrewFormulaUninstall]
    )
    let diagnostic = singleWinnerDiagnostic(source: "brew")
    let update = formulaUpdate(definition: definition, diagnostic: diagnostic)

    // The proof names a different selected entry (and another canonical target) than the one the
    // diagnostics publish now. It is not this entry's proof, so no armed control may appear.
    let otherSelection = makeEntry(
        definition: definition,
        diagnostic: diagnostic,
        update: update,
        ownership: makeVerifiedOwnership(
            registryID: "hermes-id",
            manager: .homebrewFormula,
            selectionEntryPath: "/fixture/other/tool"
        )
    )
    #expect(ManagementPresentation(entry: otherSelection).uninstall == .needsVerification(
        "Verify Installation to enable Uninstall for this Homebrew formula."
    ))

    let otherTarget = makeEntry(
        definition: definition,
        diagnostic: diagnostic,
        update: update,
        ownership: makeVerifiedOwnership(
            registryID: "hermes-id",
            manager: .homebrewFormula,
            selectionTarget: "/fixture/targets/other"
        )
    )
    #expect(ManagementPresentation(entry: otherTarget).uninstall == .needsVerification(
        "Verify Installation to enable Uninstall for this Homebrew formula."
    ))
}

@Test func ownershipForAnotherRegistryEntryIsNotProofForThisEntry() throws {
    let definition = try makeDefinition(
        id: "hermes-id",
        packages: [(.homebrewFormula, "hermes-agent")],
        accepted: [.homebrewFormulaUninstall]
    )
    let entry = makeEntry(
        definition: definition,
        diagnostic: singleWinnerDiagnostic(source: "brew"),
        ownership: makeVerifiedOwnership(registryID: "another-id", manager: .homebrewFormula)
    )

    #expect(ManagementPresentation(entry: entry).uninstall == .needsVerification(
        "Verify Installation to enable Uninstall for this Homebrew formula."
    ))
}

@Test func verifiedOffPathCopyOffersThePrepareRouteForItsOwnSelection() throws {
    let definition = try makeDefinition(
        id: "aider-id",
        packages: [(.homebrewFormula, "aider")],
        accepted: [.homebrewFormulaUninstall]
    )
    let offPath = PathCandidateObservation(
        origin: .extraRoot(index: 0, directoryText: "/fixture/extra"),
        entryPath: "/fixture/extra/aider",
        kind: .executableFile,
        canonicalTarget: "/fixture/targets/aider"
    )
    let diagnostic = makeDiagnostic(
        state: .installedNotOnPath,
        source: "brew",
        selection: .offPath(candidate: offPath, root: "/fixture/extra"),
        groups: [makeGroup("/fixture/targets/aider", entryPath: "/fixture/extra/aider")],
        shadowed: 0,
        candidates: [offPath],
        versions: [measured("/fixture/targets/aider", "1.0.0")]
    )
    let entry = makeEntry(
        definition: definition,
        diagnostic: diagnostic,
        ownership: makeVerifiedOwnership(
            registryID: "aider-id",
            manager: .homebrewFormula,
            selectionEntryPath: "/fixture/extra/aider",
            selectionTarget: "/fixture/targets/aider"
        )
    )

    #expect(ManagementPresentation(entry: entry).uninstall == .prepareFormulaUninstall)
}

@Test func contradictoryHomebrewUpdateEvidenceProvesNeitherKind() throws {
    // Both identity shapes at once cannot come from one coordinator result; the entry falls back to
    // the honest "no managed update" sentence instead of borrowing one manager's route.
    let definition = try makeDefinition(
        id: "both-id",
        packages: [(.homebrewFormula, "tool"), (.homebrewCask, "tool")],
        accepted: [.homebrewFormulaUpdate, .homebrewCaskUpdate]
    )
    let diagnostic = singleWinnerDiagnostic(source: "brew")
    let entry = makeEntry(
        definition: definition,
        diagnostic: diagnostic,
        update: makeUpdate(
            definition: definition,
            diagnostic: diagnostic,
            status: .updateAvailable(installed: Version("1.0.0"), latest: Version("2.0.0")),
            formulaStem: "tool",
            fullFormulaName: "tool",
            caskToken: "tool",
            caskFullToken: "tool"
        )
    )

    #expect(
        ManagementPresentation(entry: entry).update
            == .unavailable(
                "A newer version is reported by the supported latest check. Managed update is not available for this installation in this version."
            )
    )
}

@Test func homebrewUpdateResultForAnotherRegistryEntryOrSelectionIsNotProof() throws {
    let definition = try makeDefinition(
        id: "hermes-id",
        packages: [(.homebrewFormula, "hermes-agent")],
        accepted: [.homebrewFormulaUpdate]
    )
    let diagnostic = singleWinnerDiagnostic(source: "brew")
    let sentence =
        "A newer version is reported by the supported latest check. Managed update is not available for this installation in this version."

    let otherRegistryEntry = makeEntry(
        definition: definition,
        diagnostic: diagnostic,
        update: makeUpdate(
            definition: definition,
            diagnostic: diagnostic,
            status: .updateAvailable(installed: Version("1.0.0"), latest: Version("2.0.0")),
            formulaStem: "tool",
            fullFormulaName: "tool",
            registryID: "another-id"
        )
    )
    #expect(ManagementPresentation(entry: otherRegistryEntry).update == .unavailable(sentence))

    let otherSelection = makeEntry(
        definition: definition,
        diagnostic: diagnostic,
        update: makeUpdate(
            definition: definition,
            diagnostic: diagnostic,
            status: .updateAvailable(installed: Version("1.0.0"), latest: Version("2.0.0")),
            formulaStem: "tool",
            fullFormulaName: "tool",
            selectedTarget: "/fixture/targets/other"
        )
    )
    #expect(ManagementPresentation(entry: otherSelection).update == .unavailable(sentence))
}

@Test func anUnverifiedDeclaredNpmRouteCannotShadowTheVerifiedHomebrewRoute() throws {
    // Codex-shaped entry: npm and cask declared, both removal operations accepted, and the exact
    // verified manager is the cask. The npm slot's verification hint must not displace the cask
    // control the entry's own proof names.
    let definition = try makeDefinition(
        id: "dual-id",
        packages: [(.npm, "@scope/tool"), (.homebrewCask, "tool")],
        accepted: [.npmUninstall, .homebrewCaskUninstall]
    )
    let entry = makeEntry(
        definition: definition,
        diagnostic: singleWinnerDiagnostic(source: "standalone"),
        ownership: makeVerifiedOwnership(registryID: "dual-id", manager: .homebrewCask)
    )
    let presentation = ManagementPresentation(entry: entry)

    #expect(presentation.uninstall == .prepareCaskUninstall)
    #expect(!presentation.otherLimits.contains(HomebrewCaskUninstallUnavailableReason.operationNotAccepted.message))
    #expect(presentation.otherLimits == [
        HomebrewCaskUpdateUnavailableReason.operationNotAccepted.message
    ])
}

@Test func anExactVerifiedNpmProofStillWinsItsOwnRouteOnADualEntry() throws {
    let definition = try makeDefinition(
        id: "dual-id",
        packages: [(.npm, "@scope/tool"), (.homebrewCask, "tool")],
        accepted: [.npmUninstall, .homebrewCaskUninstall]
    )
    let entry = makeEntry(
        definition: definition,
        diagnostic: singleWinnerDiagnostic(source: "standalone"),
        ownership: makeVerifiedOwnership(registryID: "dual-id", manager: .npm)
    )
    let presentation = ManagementPresentation(entry: entry)

    #expect(presentation.uninstall == .prepareNpmUninstall)
    // A verified npm copy is not a cask copy, so the standalone sentence still applies.
    #expect(presentation.otherLimits.contains(
        "This copy is classified as standalone. Agent Lens does not delete standalone files."
    ))
}
