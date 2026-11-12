// CapabilityMatrixTests — M11-F: the published capability matrix is enforced against the registry,
// and a new tool can be contributed as data only.
//
// Two independent properties:
//
// 1. MATRIX TRUTH. `docs/capability-matrix.md` is parsed deterministically (fixed header, nine
//    cells, no escaping) and checked against `DetectorRegistry.loadDefault()`. Identity cells must
//    match exactly; capability cells obey the M11-F rules: Update/Uninstall `yes` only for an
//    accepted operation plus a declared npm candidate, latest-check `yes` only for npm or formula
//    candidates, cask latest-check never `yes`, and every row carries limits. A seeded corruption
//    must fail the same agreement function, so a green run cannot be vacuous.
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

private let exactMutationYes = "yes: npm (verified npm-global copies only)"

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
    "standalone",
    "not formula proof",
    "synthetic <layout>",
]

private func mutationCellProblems(
    _ cell: String,
    label: String,
    operation: AcceptedOperation,
    definition: DetectorDefinition
) -> [String] {
    let accepted = definition.acceptedOperations.contains(operation)
    let declaresNPM = definition.packages.contains { $0.manager == .npm }
    if accepted && declaresNPM {
        guard cell == exactMutationYes else {
            return [
                "\(definition.id) \(label) must be exactly '\(exactMutationYes)' for an accepted npm operation"
            ]
        }
        return []
    }
    if cell == exactMutationYes {
        return [
            "\(definition.id) \(label) claims '\(exactMutationYes)' without a matching accepted operation and declared npm candidate"
        ]
    }
    guard isReasonCell(cell, prefix: "informational: ")
        || isReasonCell(cell, prefix: "disabled: ")
    else {
        return [
            "\(definition.id) \(label) must be '\(exactMutationYes)' only when accepted and npm-declared, otherwise 'informational: <reason>' or 'disabled: <reason>'"
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

    if hasNPM || hasFormula {
        var expected: [String] = []
        if hasNPM { expected.append("yes: npm") }
        if hasFormula { expected.append("yes: homebrewFormula") }
        let expectedCell = expected.joined(separator: "; ")
        if cell != expectedCell {
            problems.append(
                "\(definition.id) latest-check must be '\(expectedCell)' for its declared npm/formula candidates, found '\(cell)'"
            )
        }
    } else if !isReasonCell(cell, prefix: "disabled: ") {
        problems.append(
            "\(definition.id) latest-check must be 'disabled: <reason>' when no npm or formula candidate is declared, found '\(cell)'"
        )
    }
    if cell.contains("yes: homebrewCask") {
        problems.append("\(definition.id) latest-check must never be 'yes' for a cask")
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
            row.update, label: "Update", operation: .npmUpdate, definition: definition
        )
        problems += mutationCellProblems(
            row.uninstall, label: "Uninstall", operation: .npmUninstall, definition: definition
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
            in: markdown, rowID: "opencode", columnIndex: 6, with: exactMutationYes
        ),
        "the seeded Update-cell mutation must apply to the real matrix"
    )
    let falseYesProblems = matrixProblems(markdown: falseYes, definitions: definitions)
    #expect(!falseYesProblems.isEmpty)
    #expect(
        falseYesProblems.contains { $0.contains("opencode") && $0.contains("Update") },
        "the seeded false Update claim must be named: \(falseYesProblems)"
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
