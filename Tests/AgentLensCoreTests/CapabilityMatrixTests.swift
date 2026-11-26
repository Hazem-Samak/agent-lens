// CapabilityMatrixTests — M11-F: the published capability matrix is enforced against the registry,
// and a new tool can be contributed as data only. M13-F extends the mutation grammar to exact
// Homebrew formula/cask cells and a deterministic multi-manager order.
//
// Two independent properties:
//
// 1. MATRIX TRUTH. `docs/capability-matrix.md` is parsed deterministically (fixed header, nine
//    cells, no escaping) and checked against `DetectorRegistry.loadDefault()`. Identity cells must
//    match exactly; capability cells obey the M11-F/M13-F rules: Update/Uninstall `yes` only for
//    an accepted operation of the matching kind plus a declared candidate of that same manager,
//    latest-check `yes` only for a declared npm, formula, or (M13-B) cask candidate, and every row
//    carries limits. Multiple accepted, proved managers in one mutation cell are emitted in the
//    fixed order npm, homebrewFormula, homebrewCask joined by `; `. A seeded corruption must fail
//    the same agreement function, so a green run cannot be vacuous.
//
// 2. DATA-ONLY CONTRIBUTION. The current bundled detectors plus one extra definition are loaded
//    through the production JSON validator and detector builder, and the extra tool is detected in
//    a synthetic tree. The production registry's id list is asserted unchanged in the same test.

import Testing
import Foundation
@testable import AgentLensCore

// MARK: - Matrix model and parser

private let capabilityMatrixHeader =
    "| id | display name | category | tested fixture | declared packages | latest-check | Update | Uninstall | known limits |"

private let capabilityMatrixColumns = [
    "id", "display name", "category", "tested fixture", "declared packages",
    "latest-check", "Update", "Uninstall", "known limits",
]

private struct CapabilityMatrixRow: Equatable {
    let id: String
    let displayName: String
    let category: String
    let testedFixture: String
    let declaredPackages: String
    let latestCheck: String
    let update: String
    let uninstall: String
    let knownLimits: String
}

private enum CapabilityMatrixParseError: Error, CustomStringConvertible {
    case missingHeader
    case missingSeparator
    case malformedRow(line: Int, reason: String)
    case emptyTable

    var description: String {
        switch self {
        case .missingHeader:
            return "missing exact capability-matrix header line"
        case .missingSeparator:
            return "missing markdown separator line after the header"
        case .malformedRow(let line, let reason):
            return "malformed matrix row on line \(line): \(reason)"
        case .emptyTable:
            return "capability matrix contains no data rows"
        }
    }
}

/// The cells between the outer pipes. Returns nil when the line is not a pipe-delimited row.
private func matrixCells(of line: String) -> [String]? {
    guard line.hasPrefix("|") else { return nil }
    let components = line.split(separator: "|", omittingEmptySubsequences: false)
    guard components.count >= 3, components.first?.isEmpty == true, components.last?.isEmpty == true
    else { return nil }
    return components.dropFirst().dropLast().map {
        $0.trimmingCharacters(in: .whitespaces)
    }
}

private func matrixRowID(of line: String) -> String? {
    guard let cells = matrixCells(of: line), let first = cells.first else { return nil }
    return first
}

private func isMatrixSeparator(_ line: String) -> Bool {
    guard let cells = matrixCells(of: line), cells.count == capabilityMatrixColumns.count else {
        return false
    }
    return cells.allSatisfy {
        $0.range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil
    }
}

private func parseCapabilityMatrix(_ markdown: String) throws -> [CapabilityMatrixRow] {
    let lines = markdown.components(separatedBy: .newlines)
    guard let headerIndex = lines.firstIndex(of: capabilityMatrixHeader) else {
        throw CapabilityMatrixParseError.missingHeader
    }
    let separatorIndex = headerIndex + 1
    guard separatorIndex < lines.count, isMatrixSeparator(lines[separatorIndex]) else {
        throw CapabilityMatrixParseError.missingSeparator
    }

    var rows: [CapabilityMatrixRow] = []
    var index = separatorIndex + 1
    while index < lines.count, lines[index].hasPrefix("|") {
        let line = lines[index]
        guard let cells = matrixCells(of: line) else {
            throw CapabilityMatrixParseError.malformedRow(
                line: index + 1, reason: "not a pipe-delimited row"
            )
        }
        guard cells.count == capabilityMatrixColumns.count else {
            throw CapabilityMatrixParseError.malformedRow(
                line: index + 1,
                reason: "expected \(capabilityMatrixColumns.count) cells, found \(cells.count)"
            )
        }
        guard let id = cells.first, !id.isEmpty else {
            throw CapabilityMatrixParseError.malformedRow(line: index + 1, reason: "empty id")
        }
        for (column, cell) in zip(capabilityMatrixColumns, cells) where cell.isEmpty {
            throw CapabilityMatrixParseError.malformedRow(
                line: index + 1, reason: "empty '\(column)' cell"
            )
        }
        rows.append(
            CapabilityMatrixRow(
                id: cells[0],
                displayName: cells[1],
                category: cells[2],
                testedFixture: cells[3],
                declaredPackages: cells[4],
                latestCheck: cells[5],
                update: cells[6],
                uninstall: cells[7],
                knownLimits: cells[8]
            )
        )
        index += 1
    }

    guard !rows.isEmpty else { throw CapabilityMatrixParseError.emptyTable }
    return rows
}

// MARK: - Agreement rules

private let exactNpmMutationYes = "yes: npm (verified npm-global copies only)"
private let exactFormulaMutationYes =
    "yes: homebrewFormula (verified Homebrew formula copies only)"
private let exactCaskMutationYes =
    "yes: homebrewCask (verified Homebrew cask copies only)"

/// A cell of the form `<prefix> <non-empty reason>`.
private func reasonCell(_ cell: String, prefix: String) -> String? {
    guard cell.hasPrefix(prefix) else { return nil }
    let reason = cell.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
    return reason.isEmpty ? nil : reason
}

private func isReasonCell(_ cell: String, prefix: String) -> Bool {
    reasonCell(cell, prefix: prefix) != nil
}

/// Distinctive carry-forward substrings that bind the limits to the right row.
private let requiredLimitMarkers: [String: [String]] = [
    "opencode": ["opencode2"],
    "gemini": ["2026-12-18", "antigravity-cli"],
    "cline": ["2027-05-18"],
    "aider": ["3747"],
    "goose": ["pressly", "block-goose-cli"],
    "agy": ["~/.gemini/bin"],
    "dsh": ["Dancer"],
]

/// The cross-row classification note must be present and substantive.
private let requiredDocumentSubstrings = [
    "/lib/node_modules/",
    "/Cellar/",
    "standalone classification",
    "verified cask copy is Homebrew-owned",
    "not formula proof",
    "synthetic <layout>",
    "fixed order `npm`, `homebrewFormula`, `homebrewCask`",
]

private enum MutationCapability {
    case update
    case uninstall
}

/// Exact affirmative segments, in the one documented order npm, homebrewFormula, homebrewCask.
/// A segment is emitted only when BOTH the matching kind-specific operation is accepted AND the
/// detector declares a candidate of that same manager kind. An accepted grant with no matching
/// declaration is never advertised.
private func mutationYesSegments(
    capability: MutationCapability,
    definition: DetectorDefinition
) -> [String] {
    let declaresNPM = definition.packages.contains { $0.manager == .npm }
    let declaresFormula = definition.packages.contains { $0.manager == .homebrewFormula }
    let declaresCask = definition.packages.contains { $0.manager == .homebrewCask }
    var segments: [String] = []
    switch capability {
    case .update:
        if declaresNPM && definition.acceptedOperations.contains(.npmUpdate) {
            segments.append(exactNpmMutationYes)
        }
        if declaresFormula && definition.acceptedOperations.contains(.homebrewFormulaUpdate) {
            segments.append(exactFormulaMutationYes)
        }
        if declaresCask && definition.acceptedOperations.contains(.homebrewCaskUpdate) {
            segments.append(exactCaskMutationYes)
        }
    case .uninstall:
        if declaresNPM && definition.acceptedOperations.contains(.npmUninstall) {
            segments.append(exactNpmMutationYes)
        }
        if declaresFormula && definition.acceptedOperations.contains(.homebrewFormulaUninstall) {
            segments.append(exactFormulaMutationYes)
        }
        if declaresCask && definition.acceptedOperations.contains(.homebrewCaskUninstall) {
            segments.append(exactCaskMutationYes)
        }
    }
    return segments
}

private func mutationCellProblems(
    _ cell: String,
    label: String,
    capability: MutationCapability,
    definition: DetectorDefinition
) -> [String] {
    let expected = mutationYesSegments(capability: capability, definition: definition)
    if expected.isEmpty {
        if cell.hasPrefix("yes:") {
            return [
                "\(definition.id) \(label) claims '\(cell)' without a matching accepted \(label.lowercased()) operation and declared manager candidate"
            ]
        }
        guard isReasonCell(cell, prefix: "informational: ")
            || isReasonCell(cell, prefix: "disabled: ")
        else {
            return [
                "\(definition.id) \(label) must be an exact 'yes: <manager> (<proof scope>)' only for a matching accepted operation and matching declared manager, otherwise 'informational: <reason>' or 'disabled: <reason>'"
            ]
        }
        return []
    }
    let expectedCell = expected.joined(separator: "; ")
    guard cell == expectedCell else {
        return [
            "\(definition.id) \(label) must be exactly '\(expectedCell)' for its accepted operations and declared manager kinds, found '\(cell)'"
        ]
    }
    return []
}

private func latestCheckProblems(
    _ cell: String,
    definition: DetectorDefinition
) -> [String] {
    var problems: [String] = []
    let hasNPM = definition.packages.contains { $0.manager == .npm }
    let hasFormula = definition.packages.contains { $0.manager == .homebrewFormula }
    let hasCask = definition.packages.contains { $0.manager == .homebrewCask }

    if hasNPM || hasFormula || hasCask {
        var expected: [String] = []
        if hasNPM { expected.append("yes: npm") }
        if hasFormula { expected.append("yes: homebrewFormula") }
        // M13-B ships the read-only cask latest-check; a declared cask now lists the capability
        // beside any npm/formula probe. The cell still never implies a cask mutation.
        if hasCask { expected.append("yes: homebrewCask") }
        let expectedCell = expected.joined(separator: "; ")
        if cell != expectedCell {
            problems.append(
                "\(definition.id) latest-check must be '\(expectedCell)' for its declared npm/formula/cask candidates, found '\(cell)'"
            )
        }
    } else if !isReasonCell(cell, prefix: "disabled: ") {
        problems.append(
            "\(definition.id) latest-check must be 'disabled: <reason>' when no npm, formula, or cask candidate is declared, found '\(cell)'"
        )
    }
    // A false cask capability claim is rejected even though the cask probe now ships.
    if cell.contains("yes: homebrewCask") && !hasCask {
        problems.append(
            "\(definition.id) latest-check claims 'yes: homebrewCask' without a declared cask"
        )
    }
    return problems
}

private func matrixProblems(
    markdown: String,
    definitions: [DetectorDefinition]
) -> [String] {
    let rows: [CapabilityMatrixRow]
    do {
        rows = try parseCapabilityMatrix(markdown)
    } catch {
        return ["matrix parse failed: \(error)"]
    }

    var problems: [String] = []
    let registryIDs = definitions.map(\.id)
    let rowIDs = rows.map(\.id)
    if rowIDs != registryIDs {
        problems.append(
            "matrix ids \(rowIDs) do not equal registry ids \(registryIDs) in registry order"
        )
    }
    let duplicateIDs = Dictionary(grouping: rowIDs, by: { $0 })
        .filter { $0.value.count > 1 }
        .keys
        .sorted()
    if !duplicateIDs.isEmpty {
        problems.append("duplicate matrix ids: \(duplicateIDs)")
    }
    let unknownIDs = Set(rowIDs).subtracting(registryIDs).sorted()
    if !unknownIDs.isEmpty {
        problems.append("matrix rows not present in the registry: \(unknownIDs)")
    }

    let rowsByID = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    for definition in definitions {
        guard let row = rowsByID[definition.id] else {
            problems.append("missing matrix row for \(definition.id)")
            continue
        }
        if row.displayName != definition.displayName {
            problems.append(
                "\(definition.id) display name '\(row.displayName)' != '\(definition.displayName)'"
            )
        }
        if row.category != definition.category.rawValue {
            problems.append(
                "\(definition.id) category '\(row.category)' != '\(definition.category.rawValue)'"
            )
        }
        let layout = definition.fixture?.layout ?? "(no fixture)"
        let expectedFixture = "synthetic \(layout)"
        if row.testedFixture != expectedFixture {
            problems.append(
                "\(definition.id) tested fixture '\(row.testedFixture)' != '\(expectedFixture)'"
            )
        }
        let expectedPackages = definition.packages.isEmpty
            ? "none"
            : definition.packages.map { "\($0.manager.rawValue):\($0.name)" }
                .joined(separator: "; ")
        if row.declaredPackages != expectedPackages {
            problems.append(
                "\(definition.id) declared packages '\(row.declaredPackages)' != '\(expectedPackages)'"
            )
        }

        problems += latestCheckProblems(row.latestCheck, definition: definition)
        problems += mutationCellProblems(
            row.update, label: "Update", capability: .update, definition: definition
        )
        problems += mutationCellProblems(
            row.uninstall, label: "Uninstall", capability: .uninstall, definition: definition
        )

        if row.knownLimits.trimmingCharacters(in: .whitespaces).isEmpty {
            problems.append("\(definition.id) known limits cell is empty")
        }
        for marker in requiredLimitMarkers[definition.id] ?? [] where !row.knownLimits.contains(marker) {
            problems.append("\(definition.id) known limits are missing required '\(marker)'")
        }
    }

    for required in requiredDocumentSubstrings where !markdown.contains(required) {
        problems.append("capability matrix is missing the cross-row note substring '\(required)'")
    }
    return problems
}

// MARK: - Matrix file location

private var capabilityMatrixFileURL: URL {
    URL(fileURLWithPath: #filePath) // Tests/AgentLensCoreTests/CapabilityMatrixTests.swift
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("docs/capability-matrix.md")
}

// MARK: - Seeded corruption helpers (work on a copy; the real doc is never written)

private func replacingMatrixCell(
    in markdown: String,
    rowID: String,
    columnIndex: Int,
    with value: String
) -> String? {
    var lines = markdown.components(separatedBy: .newlines)
    guard let lineIndex = lines.firstIndex(where: { matrixRowID(of: $0) == rowID }),
          var cells = matrixCells(of: lines[lineIndex]),
          cells.count == capabilityMatrixColumns.count,
          (0..<capabilityMatrixColumns.count).contains(columnIndex)
    else {
        return nil
    }
    cells[columnIndex] = value
    lines[lineIndex] = "| " + cells.joined(separator: " | ") + " |"
    return lines.joined(separator: "\n")
}

private func droppingMatrixRow(in markdown: String, rowID: String) -> String? {
    var lines = markdown.components(separatedBy: .newlines)
    let originalCount = lines.count
    lines.removeAll { matrixRowID(of: $0) == rowID }
    guard lines.count < originalCount else { return nil }
    return lines.joined(separator: "\n")
}

// MARK: - In-memory promotion proofs (never written to the bundled registry)

private func derivedDefinition(
    _ definition: DetectorDefinition,
    acceptedOperations: [AcceptedOperation],
    packages: [DeclaredPackage]? = nil
) throws -> DetectorDefinition {
    try DetectorDefinition(
        id: definition.id,
        displayName: definition.displayName,
        executableName: definition.executableName,
        extraSearchRoots: definition.extraSearchRoots,
        fixture: definition.fixture,
        category: definition.category,
        packages: packages ?? definition.packages,
        informationURL: definition.informationURL,
        uninstallInstructionsURL: definition.uninstallInstructionsURL,
        versionQuery: definition.versionQuery,
        acceptedOperations: acceptedOperations
    )
}

private func definitionsReplacing(
    _ definitions: [DetectorDefinition],
    id: String,
    with replacement: DetectorDefinition
) -> [DetectorDefinition] {
    definitions.map { $0.id == id ? replacement : $0 }
}

// MARK: - Fixtures

@discardableResult
private func makeContributionExecutable(script: String, at fileURL: URL) throws -> String {
    try Data("#!/bin/sh\n\(script)\n".utf8).write(to: fileURL)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755], ofItemAtPath: fileURL.path
    )
    return fileURL.path
}

private func contributionTempRoot(_ label: String) throws -> URL {
    let environment = ProcessInfo.processInfo.environment
    guard let basePath = [environment["AGENT_LENS_TEST_SCRATCH"], environment["TMPDIR"]]
        .compactMap({ $0 })
        .first(where: { !$0.isEmpty })
    else {
        throw NSError(
            domain: "AgentLensTests", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "no approved test scratch root is available"]
        )
    }
    let base = URL(fileURLWithPath: basePath, isDirectory: true).resolvingSymlinksInPath()
    let dir = base.appendingPathComponent(
        "agentlens-m11f-\(label)-\(UUID().uuidString)", isDirectory: true
    )
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.resolvingSymlinksInPath()
}

private func contributionEnvironment(pathEntries: [URL]) -> ShellEnvironment {
    let joined = pathEntries.map(\.path).joined(separator: ":")
    return ShellEnvironment(
        shellPath: "/bin/zsh",
        pathEntries: pathEntries.map(\.path),
        pathJoined: joined,
        raw: ["PATH": joined],
        isDegraded: false
    )
}

// MARK: - Agreement tests

@Test func capabilityMatrixMatchesTheBundledRegistry() throws {
    let definitions = try DetectorRegistry.loadDefault()
    let markdown = try String(contentsOf: capabilityMatrixFileURL, encoding: .utf8)
    let problems = matrixProblems(markdown: markdown, definitions: definitions)
    #expect(
        problems.isEmpty,
        "capability matrix disagreements: \(problems.joined(separator: "; "))"
    )
}

@Test func capabilityMatrixAgreementRejectsSeededCorruption() throws {
    let definitions = try DetectorRegistry.loadDefault()
    let markdown = try String(contentsOf: capabilityMatrixFileURL, encoding: .utf8)
    #expect(matrixProblems(markdown: markdown, definitions: definitions).isEmpty)

    // A false Update claim: opencode has no accepted operations, so the exact `yes` cell must fail.
    let falseYes = try #require(
        replacingMatrixCell(
            in: markdown, rowID: "opencode", columnIndex: 6, with: exactNpmMutationYes
        ),
        "the seeded Update-cell mutation must apply to the real matrix"
    )
    let falseYesProblems = matrixProblems(markdown: falseYes, definitions: definitions)
    #expect(!falseYesProblems.isEmpty)
    #expect(
        falseYesProblems.contains { $0.contains("opencode") && $0.contains("Update") },
        "the seeded false Update claim must be named: \(falseYesProblems)"
    )

    // A false cask latest-check claim: grok declares no package at all, so the shipped cask probe
    // can never serve it. The blanket prohibition is gone, but the new rule still rejects this.
    let falseCaskYes = try #require(
        replacingMatrixCell(
            in: markdown, rowID: "grok", columnIndex: 5, with: "yes: homebrewCask"
        ),
        "the seeded cask latest-check mutation must apply to the real matrix"
    )
    let falseCaskProblems = matrixProblems(markdown: falseCaskYes, definitions: definitions)
    #expect(!falseCaskProblems.isEmpty)
    #expect(
        falseCaskProblems.contains { $0.contains("grok") && $0.contains("homebrewCask") },
        "the seeded false cask latest-check claim must be named: \(falseCaskProblems)"
    )

    // A dropped row: the id set/order must no longer agree with the registry.
    let droppedRow = try #require(
        droppingMatrixRow(in: markdown, rowID: "opencode"),
        "the seeded row drop must apply to the real matrix"
    )
    let droppedRowProblems = matrixProblems(markdown: droppedRow, definitions: definitions)
    #expect(!droppedRowProblems.isEmpty)
    #expect(
        droppedRowProblems.contains { $0.contains("opencode") },
        "the dropped row must be named: \(droppedRowProblems)"
    )
}

@Test func capabilityMatrixAgreementAcceptsExactHomebrewMutationGrammar() throws {
    let definitions = try DetectorRegistry.loadDefault()
    let markdown = try String(contentsOf: capabilityMatrixFileURL, encoding: .utf8)

    let hermes = try derivedDefinition(
        try #require(definitions.first { $0.id == "hermes" }),
        acceptedOperations: [.homebrewFormulaUpdate, .homebrewFormulaUninstall]
    )
    let kiro = try derivedDefinition(
        try #require(definitions.first { $0.id == "kiro-cli" }),
        acceptedOperations: [.homebrewCaskUpdate, .homebrewCaskUninstall]
    )
    let claude = try derivedDefinition(
        try #require(definitions.first { $0.id == "claude" }),
        acceptedOperations: [
            .npmUpdate, .npmUninstall, .homebrewCaskUpdate, .homebrewCaskUninstall,
        ]
    )

    var seededDefinitions = definitions
    seededDefinitions = definitionsReplacing(seededDefinitions, id: "hermes", with: hermes)
    seededDefinitions = definitionsReplacing(seededDefinitions, id: "kiro-cli", with: kiro)
    seededDefinitions = definitionsReplacing(seededDefinitions, id: "claude", with: claude)

    var seeded = markdown
    seeded = try #require(replacingMatrixCell(
        in: seeded, rowID: "hermes", columnIndex: 6, with: exactFormulaMutationYes
    ))
    seeded = try #require(replacingMatrixCell(
        in: seeded, rowID: "hermes", columnIndex: 7, with: exactFormulaMutationYes
    ))
    seeded = try #require(replacingMatrixCell(
        in: seeded, rowID: "kiro-cli", columnIndex: 6, with: exactCaskMutationYes
    ))
    seeded = try #require(replacingMatrixCell(
        in: seeded, rowID: "kiro-cli", columnIndex: 7, with: exactCaskMutationYes
    ))
    let mixedNpmAndCask = "\(exactNpmMutationYes); \(exactCaskMutationYes)"
    seeded = try #require(replacingMatrixCell(
        in: seeded, rowID: "claude", columnIndex: 6, with: mixedNpmAndCask
    ))
    seeded = try #require(replacingMatrixCell(
        in: seeded, rowID: "claude", columnIndex: 7, with: mixedNpmAndCask
    ))

    let problems = matrixProblems(markdown: seeded, definitions: seededDefinitions)
    #expect(
        problems.isEmpty,
        "exact in-memory Homebrew grants must agree in deterministic order: \(problems.joined(separator: "; "))"
    )
    // The positive proof above is in-memory only and never a temporary shipping grant; the real
    // document still has to agree with whatever accepted operations the bundled registry declares.
    #expect(matrixProblems(markdown: markdown, definitions: definitions).isEmpty)
}

@Test func mutationGrammarUsesDeterministicManagerOrder() throws {
    let definition = try DetectorDefinition(
        id: "order-proof",
        displayName: "Order Proof",
        executableName: "order-proof",
        extraSearchRoots: [],
        fixture: nil,
        category: .aiHarness,
        packages: [
            try DeclaredPackage(manager: .npm, name: "@example/order-proof"),
            try DeclaredPackage(manager: .homebrewFormula, name: "order-proof"),
            try DeclaredPackage(manager: .homebrewCask, name: "order-proof"),
        ],
        informationURL: nil,
        uninstallInstructionsURL: nil,
        versionQuery: .standard,
        acceptedOperations: [
            .npmUpdate, .homebrewFormulaUpdate, .homebrewCaskUpdate,
        ]
    )
    let ordered = [
        exactNpmMutationYes, exactFormulaMutationYes, exactCaskMutationYes,
    ].joined(separator: "; ")
    #expect(
        mutationCellProblems(
            ordered, label: "Update", capability: .update, definition: definition
        ).isEmpty
    )
    let reversed = [
        exactCaskMutationYes, exactFormulaMutationYes, exactNpmMutationYes,
    ].joined(separator: "; ")
    #expect(
        !mutationCellProblems(
            reversed, label: "Update", capability: .update, definition: definition
        ).isEmpty
    )
    let missingOneManager = [exactNpmMutationYes, exactCaskMutationYes]
        .joined(separator: "; ")
    #expect(
        !mutationCellProblems(
            missingOneManager, label: "Update", capability: .update, definition: definition
        ).isEmpty
    )
}

@Test func capabilityMatrixAgreementRejectsSeededHomebrewCorruption() throws {
    let definitions = try DetectorRegistry.loadDefault()
    let markdown = try String(contentsOf: capabilityMatrixFileURL, encoding: .utf8)
    #expect(matrixProblems(markdown: markdown, definitions: definitions).isEmpty)

    // Missing formula grant: `opencode` declares formula candidates but is deliberately outside
    // the conditional promotion set, so it remains a no-grant case before and after that lands.
    let missingFormula = try #require(replacingMatrixCell(
        in: markdown, rowID: "opencode", columnIndex: 6, with: exactFormulaMutationYes
    ))
    let missingFormulaProblems = matrixProblems(
        markdown: missingFormula, definitions: definitions
    )
    #expect(
        missingFormulaProblems.count == 1
            && missingFormulaProblems[0].contains("opencode")
            && missingFormulaProblems[0].contains("Update"),
        "a missing formula grant must fail only its own cell: \(missingFormulaProblems)"
    )

    // Missing cask grant: `agy` declares the cask but has no accepted cask operation and is not
    // conditionally approved.
    let missingCask = try #require(replacingMatrixCell(
        in: markdown, rowID: "agy", columnIndex: 6, with: exactCaskMutationYes
    ))
    let missingCaskProblems = matrixProblems(markdown: missingCask, definitions: definitions)
    #expect(
        missingCaskProblems.count == 1
            && missingCaskProblems[0].contains("agy")
            && missingCaskProblems[0].contains("Update"),
        "a missing cask grant must fail only its own cell: \(missingCaskProblems)"
    )

    // Mismatched manager: an in-memory formula grant on a row that declares no package at all.
    // Its real Uninstall cell remains the valid `disabled:` negative, so only Update fails.
    let grok = try derivedDefinition(
        try #require(definitions.first { $0.id == "grok" }),
        acceptedOperations: [.homebrewFormulaUpdate, .homebrewFormulaUninstall]
    )
    let mismatchedDefinitions = definitionsReplacing(
        definitions, id: "grok", with: grok
    )
    let mismatched = try #require(replacingMatrixCell(
        in: markdown, rowID: "grok", columnIndex: 6, with: exactFormulaMutationYes
    ))
    let mismatchedProblems = matrixProblems(
        markdown: mismatched, definitions: mismatchedDefinitions
    )
    #expect(
        mismatchedProblems.count == 1
            && mismatchedProblems[0].contains("grok")
            && mismatchedProblems[0].contains("Update"),
        "an accepted formula grant without a formula declaration must fail only Update: \(mismatchedProblems)"
    )

    // Wrong operation: an Uninstall-only grant cannot advertise Update. Seed the companion
    // Uninstall cell to this derived definition's correct exact answer so only Update fails.
    let hermesUninstallOnly = try derivedDefinition(
        try #require(definitions.first { $0.id == "hermes" }),
        acceptedOperations: [.homebrewFormulaUninstall]
    )
    let wrongUpdateDefinitions = definitionsReplacing(
        definitions, id: "hermes", with: hermesUninstallOnly
    )
    var wrongUpdate = markdown
    wrongUpdate = try #require(replacingMatrixCell(
        in: wrongUpdate, rowID: "hermes", columnIndex: 7, with: exactFormulaMutationYes
    ))
    wrongUpdate = try #require(replacingMatrixCell(
        in: wrongUpdate, rowID: "hermes", columnIndex: 6, with: exactFormulaMutationYes
    ))
    let wrongUpdateProblems = matrixProblems(
        markdown: wrongUpdate, definitions: wrongUpdateDefinitions
    )
    #expect(
        wrongUpdateProblems.count == 1
            && wrongUpdateProblems[0].contains("hermes")
            && wrongUpdateProblems[0].contains("Update"),
        "an Uninstall-only grant must fail only Update: \(wrongUpdateProblems)"
    )

    // The converse: an Update-only grant cannot advertise Uninstall.
    let hermesUpdateOnly = try derivedDefinition(
        try #require(definitions.first { $0.id == "hermes" }),
        acceptedOperations: [.homebrewFormulaUpdate]
    )
    let wrongUninstallDefinitions = definitionsReplacing(
        definitions, id: "hermes", with: hermesUpdateOnly
    )
    var wrongUninstall = markdown
    wrongUninstall = try #require(replacingMatrixCell(
        in: wrongUninstall, rowID: "hermes", columnIndex: 6, with: exactFormulaMutationYes
    ))
    wrongUninstall = try #require(replacingMatrixCell(
        in: wrongUninstall, rowID: "hermes", columnIndex: 7, with: exactFormulaMutationYes
    ))
    let wrongUninstallProblems = matrixProblems(
        markdown: wrongUninstall, definitions: wrongUninstallDefinitions
    )
    #expect(
        wrongUninstallProblems.count == 1
            && wrongUninstallProblems[0].contains("hermes")
            && wrongUninstallProblems[0].contains("Uninstall"),
        "an Update-only grant must fail only Uninstall: \(wrongUninstallProblems)"
    )

    // Imprecise affirmative strings: the full exact scope text is required. The companion
    // Uninstall cell is the derived definition's correct answer.
    let hermesFullGrant = try derivedDefinition(
        try #require(definitions.first { $0.id == "hermes" }),
        acceptedOperations: [.homebrewFormulaUpdate, .homebrewFormulaUninstall]
    )
    let fullGrantDefinitions = definitionsReplacing(
        definitions, id: "hermes", with: hermesFullGrant
    )
    var imprecise = markdown
    imprecise = try #require(replacingMatrixCell(
        in: imprecise, rowID: "hermes", columnIndex: 7, with: exactFormulaMutationYes
    ))
    imprecise = try #require(replacingMatrixCell(
        in: imprecise, rowID: "hermes", columnIndex: 6, with: "yes: homebrewFormula"
    ))
    let impreciseProblems = matrixProblems(
        markdown: imprecise, definitions: fullGrantDefinitions
    )
    #expect(
        impreciseProblems.count == 1
            && impreciseProblems[0].contains("hermes")
            && impreciseProblems[0].contains("Update"),
        "an imprecise formula yes must fail only Update: \(impreciseProblems)"
    )

    // One manager's exact `yes` cannot stand in for another manager's grant.
    var wrongManagerYes = markdown
    wrongManagerYes = try #require(replacingMatrixCell(
        in: wrongManagerYes, rowID: "hermes", columnIndex: 7, with: exactFormulaMutationYes
    ))
    wrongManagerYes = try #require(replacingMatrixCell(
        in: wrongManagerYes, rowID: "hermes", columnIndex: 6, with: exactNpmMutationYes
    ))
    let wrongManagerYesProblems = matrixProblems(
        markdown: wrongManagerYes, definitions: fullGrantDefinitions
    )
    #expect(
        wrongManagerYesProblems.count == 1
            && wrongManagerYesProblems[0].contains("hermes")
            && wrongManagerYesProblems[0].contains("Update"),
        "an npm yes cannot advertise a formula-only grant: \(wrongManagerYesProblems)"
    )

    // Empty negative reasons are not accepted, whether an affirmative grant exists or not.
    var emptyInformational = markdown
    emptyInformational = try #require(replacingMatrixCell(
        in: emptyInformational, rowID: "hermes", columnIndex: 7, with: exactFormulaMutationYes
    ))
    emptyInformational = try #require(replacingMatrixCell(
        in: emptyInformational, rowID: "hermes", columnIndex: 6, with: "informational:"
    ))
    let emptyInformationalProblems = matrixProblems(
        markdown: emptyInformational, definitions: fullGrantDefinitions
    )
    #expect(
        emptyInformationalProblems.count == 1
            && emptyInformationalProblems[0].contains("hermes")
            && emptyInformationalProblems[0].contains("Update"),
        "an empty informational reason must fail only Update: \(emptyInformationalProblems)"
    )

    let emptyDisabled = try #require(replacingMatrixCell(
        in: markdown, rowID: "opencode", columnIndex: 7, with: "disabled:"
    ))
    let emptyDisabledProblems = matrixProblems(
        markdown: emptyDisabled, definitions: definitions
    )
    #expect(
        emptyDisabledProblems.count == 1
            && emptyDisabledProblems[0].contains("opencode")
            && emptyDisabledProblems[0].contains("Uninstall"),
        "an empty disabled reason must fail only Uninstall: \(emptyDisabledProblems)"
    )
}

// MARK: - Data-only contribution proof

@Test func dataOnlyContributionLoadsExtraToolWithoutProductionChange() throws {
    let productionDefinitions = try DetectorRegistry.loadDefault()
    let productionIDs = productionDefinitions.map(\.id)
    let frozenCatalogue = [
        "codex", "opencode", "grok", "claude", "gemini", "cline",
        "hermes", "aider", "goose", "kiro-cli", "omp", "agy",
        "dsh", "qodercli",
    ]
    #expect(productionIDs == frozenCatalogue)
    #expect(!productionIDs.contains("contrib-proof-tool"))

    // Extend the CURRENT bundled registry payload with one extra definition, as data only.
    let bundledData = try DetectorRegistry.loadDefaultRegistryData()
    guard var registryObject = try JSONSerialization.jsonObject(with: bundledData) as? [String: Any] else {
        Issue.record("bundled registry root is not a JSON object")
        return
    }
    #expect(registryObject["schemaVersion"] as? Int == 2)
    guard var detectors = registryObject["detectors"] as? [[String: Any]] else {
        Issue.record("bundled registry has no detector array")
        return
    }
    let extraDefinition: [String: Any] = [
        "id": "contrib-proof-tool",
        "displayName": "Contribution Proof Tool",
        "executableName": "contrib-proof-tool",
        "extraSearchRoots": [],
        "fixture": [
            "layout": "singleDirectory",
            "expectedSource": "standalone",
        ],
        "category": "aiHarness",
        "packages": [],
        "versionQuery": [
            "arguments": ["--version"],
            "stream": "stdout",
            "line": "first",
        ],
    ]
    detectors.append(extraDefinition)
    registryObject["detectors"] = detectors
    let extendedData = try JSONSerialization.data(withJSONObject: registryObject, options: [.sortedKeys])

    let extendedDefinitions = try DetectorRegistry.validate(data: extendedData)
    #expect(extendedDefinitions.count == productionDefinitions.count + 1)
    #expect(extendedDefinitions.dropLast().map(\.id) == productionIDs)

    let proofDefinition = try #require(extendedDefinitions.last)
    #expect(proofDefinition.id == "contrib-proof-tool")
    #expect(proofDefinition.executableName == "contrib-proof-tool")
    #expect(proofDefinition.category == .aiHarness)
    #expect(
        proofDefinition.fixture
            == DetectorDefinition.Fixture(
                layout: "singleDirectory", expectedSource: "standalone"
            )
    )
    #expect(proofDefinition.packages.isEmpty)
    #expect(proofDefinition.acceptedOperations.isEmpty)
    #expect(proofDefinition.versionQuery == .standard)

    let fixtureRoot = try contributionTempRoot("contrib")
    defer { try? FileManager.default.removeItem(at: fixtureRoot) }
    try makeContributionExecutable(
        script: "exit 0", at: fixtureRoot.appendingPathComponent("contrib-proof-tool")
    )
    let detected = proofDefinition.makeDetector(versionQuery: { _, _, _, _ in nil })
        .detect(in: contributionEnvironment(pathEntries: [fixtureRoot]))
    #expect(detected.state == .installedAndOnPath)
    #expect(detected.source == "standalone")
    #expect(detected.displayName == "Contribution Proof Tool")

    // The production registry still contains exactly the fourteen bundled ids.
    let reloadedIDs = try DetectorRegistry.loadDefault().map(\.id)
    #expect(reloadedIDs == productionIDs)
    #expect(reloadedIDs == frozenCatalogue)
}
