import SwiftUI
import AgentLensAppSupport
import AgentLensCore

public struct DiagnosticsView: View {
    public let entry: InventoryEntry?
    public let isDegradedEnvironment: Bool
    public let freshnessFailure: InventoryViewModel.Failure?

    public init(
        entry: InventoryEntry?,
        isDegradedEnvironment: Bool,
        freshnessFailure: InventoryViewModel.Failure?
    ) {
        self.entry = entry
        self.isDegradedEnvironment = isDegradedEnvironment
        self.freshnessFailure = freshnessFailure
    }

    public var body: some View {
        Group {
            if let entry {
                diagnosticsContent(entry)
            } else {
                ContentUnavailableView(
                    "No Tool Selected",
                    systemImage: "stethoscope",
                    description: Text("Select a tool from the inventory to view its PATH diagnostics.")
                )
            }
        }
        .navigationTitle(entry.map { "\($0.definition.displayName) Diagnostics" } ?? "Diagnostics")
    }

    private func diagnosticsContent(_ entry: InventoryEntry) -> some View {
        let diagnostic = entry.diagnostic

        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if isDegradedEnvironment {
                    degradedEnvironmentBanner
                }

                if let freshnessFailure {
                    freshnessFailureBanner(freshnessFailure)
                }

                headerSection(entry)

                Divider()

                selectionSection(diagnostic)

                Divider()

                countsSection(diagnostic)

                Divider()

                installationVersionsSection(diagnostic)

                Divider()

                candidatesSection(diagnostic)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Banners

    private var degradedEnvironmentBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.body)
            VStack(alignment: .leading, spacing: 2) {
                Text("Degraded Environment")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("The login shell could not be captured; PATH uses the documented fallback PATH. Results may not represent the login shell's authoritative PATH.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private func freshnessFailureBanner(_ failure: InventoryViewModel.Failure) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.orange)
                .font(.body)
            VStack(alignment: .leading, spacing: 2) {
                Text("Rescan Failed")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("\(failure.message). Displaying retained local diagnostics.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Header

    private func headerSection(_ entry: InventoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.definition.displayName)
                .font(.title)
                .fontWeight(.bold)

            HStack(spacing: 8) {
                Text(entry.definition.executableName)
                    .font(.subheadline)
                    .fontDesign(.monospaced)
                    .foregroundColor(.secondary)

                Text("•")
                    .foregroundColor(.secondary)

                Text(entry.registryID)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: Selection Status

    private func selectionSection(_ diagnostic: ToolPathDiagnostic) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Selection Status")
                .font(.headline)

            switch diagnostic.selection {
            case .winner(let winner):
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.accentColor)
                        Text("Verified Winner")
                            .fontWeight(.medium)
                        Text("(matches detector)")
                            .foregroundColor(.secondary)
                    }

                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                        GridRow {
                            Text("Slot")
                                .foregroundColor(.secondary)
                            Text(originText(winner.origin))
                        }

                        GridRow(alignment: .top) {
                            Text("Entry Path")
                                .foregroundColor(.secondary)
                            selectablePath(winner.entryPath)
                        }

                        GridRow(alignment: .top) {
                            Text("Canonical Target")
                                .foregroundColor(.secondary)
                            selectablePath(winner.canonicalTarget ?? "Unknown target")
                        }

                        GridRow {
                            Text("Kind")
                                .foregroundColor(.secondary)
                            Text(winner.kind.label)
                        }
                    }
                    .font(.subheadline)
                }

            case .offPath(let candidate, let root):
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.branch")
                            .foregroundColor(.orange)
                        Text("Known Extra Root (off PATH; not a shell winner)")
                            .fontWeight(.medium)
                            .foregroundColor(.orange)
                    }

                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                        GridRow(alignment: .top) {
                            Text("Declared Root")
                                .foregroundColor(.secondary)
                            selectablePath(root)
                        }

                        GridRow(alignment: .top) {
                            Text("Found Path")
                                .foregroundColor(.secondary)
                            selectablePath(candidate.entryPath)
                        }

                        GridRow(alignment: .top) {
                            Text("Canonical Target")
                                .foregroundColor(.secondary)
                            selectablePath(candidate.canonicalTarget ?? "Unknown target")
                        }

                        GridRow {
                            Text("Kind")
                                .foregroundColor(.secondary)
                            Text(candidate.kind.label)
                        }
                    }
                    .font(.subheadline)
                }

            case .notInstalled:
                HStack(spacing: 6) {
                    Image(systemName: "slash.circle")
                        .foregroundColor(.secondary)
                    Text("No live executable found in PATH or declared extra roots")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

            case .inconsistent(let reason):
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .foregroundColor(.orange)
                    Text("Consistency Failure: \(reason)")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                }
            }
        }
    }

    // MARK: Summary Counts

    private func countsSection(_ diagnostic: ToolPathDiagnostic) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Summary Counts")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                GridRow {
                    Text("Live entry paths")
                        .foregroundColor(.secondary)
                    Text("\(diagnostic.distinctLiveEntryPathCount)")
                        .fontWeight(.medium)

                    Text("Canonical targets")
                        .foregroundColor(.secondary)
                    Text("\(diagnostic.canonicalTargetCount)")
                        .fontWeight(.medium)
                }

                GridRow {
                    Text("Repeated PATH slots")
                        .foregroundColor(.secondary)
                    Text("\(diagnostic.repeatedPathSlotCount)")
                        .fontWeight(.medium)

                    Text("Same-target aliases")
                        .foregroundColor(.secondary)
                    Text("\(diagnostic.sameTargetAliasCount)")
                        .fontWeight(.medium)
                }

                GridRow {
                    Text("Shadowed installations")
                        .foregroundColor(.secondary)
                    Text(shadowedText(diagnostic.shadowedInstallationCount))
                        .fontWeight(.medium)
                }
            }
            .font(.subheadline)
        }
    }

    private func shadowedText(_ count: Int?) -> String {
        guard let count else { return "— (unavailable due to consistency failure)" }
        return "\(count)"
    }

    // MARK: Canonical Installation Versions

    private func installationVersionsSection(_ diagnostic: ToolPathDiagnostic) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Canonical Installation Versions")
                .font(.headline)

            if diagnostic.installationVersions.isEmpty {
                Text("No live canonical installation was observed.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(
                    diagnostic.installationVersions,
                    id: \.canonicalTarget
                ) { observation in
                    installationVersionRow(observation)
                }
            }
        }
    }

    private func installationVersionRow(
        _ observation: InstallationVersionObservation
    ) -> some View {
        let extraRootText: String?
        if case .extraRoot(_, let directoryText) = observation.origin {
            extraRootText = directoryText
        } else {
            extraRootText = nil
        }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Canonical Target")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if extraRootText != nil {
                    Text("Observed discovery origin · off PATH")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                        .foregroundColor(.orange)
                }
            }

            selectablePath(observation.canonicalTarget)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow(alignment: .top) {
                    Text("Representative Entry")
                        .foregroundColor(.secondary)
                    selectablePath(observation.entryPath)
                }

                GridRow(alignment: .top) {
                    Text("Local Version")
                        .foregroundColor(.secondary)
                    versionOutcomeText(observation.outcome)
                }

                if let extraRootText {
                    GridRow(alignment: .top) {
                        Text("Observed Discovery Origin")
                            .foregroundColor(.secondary)
                        Text(
                            "declared extra root \(extraRootText); not a current shell winner or verified ownership"
                        )
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(.subheadline)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func versionOutcomeText(_ outcome: InstallationVersionOutcome) -> some View {
        switch outcome {
        case .measured(let version):
            Text(version)
                .fontDesign(.monospaced)
                .textSelection(.enabled)
        case .unknown(let reason):
            HStack(alignment: .top, spacing: 4) {
                Image(systemName: "questionmark.circle")
                    .foregroundColor(.secondary)
                Text("Unknown — \(reason.message)")
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Observed Candidates

    private func candidatesSection(_ diagnostic: ToolPathDiagnostic) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Observed Candidates")
                .font(.headline)

            // Live PATH candidates
            VStack(alignment: .leading, spacing: 8) {
                Text("Live PATH Entries")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                if diagnostic.liveCandidates.isEmpty {
                    Text("None observed")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(uniqueLiveCandidates(diagnostic), id: \.entryPath) { candidate in
                        candidateRow(candidate, diagnostic: diagnostic)
                    }
                }
            }

            // Declared off-PATH selection (if applicable)
            if case .offPath(let candidate, let root) = diagnostic.selection {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Off-PATH Selected Candidate")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Declared root: \(root)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(candidate.kind.label)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.12), in: Capsule())
                        }

                        selectablePath(candidate.entryPath)

                        if let target = candidate.canonicalTarget {
                            HStack(spacing: 4) {
                                Text("→")
                                    .foregroundColor(.secondary)
                                selectablePath(target)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                }
            }

            // Invalid PATH candidates
            if !diagnostic.invalidCandidates.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Invalid PATH Entries")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    ForEach(Array(diagnostic.invalidCandidates.enumerated()), id: \.offset) { _, candidate in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(originText(candidate.origin))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(candidate.kind.label)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.12), in: Capsule())
                            }

                            selectablePath(candidate.entryPath)
                        }
                        .padding(10)
                        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
    }

    private func candidateRow(_ candidate: PathCandidateObservation, diagnostic: ToolPathDiagnostic) -> some View {
        let matchingObservations = diagnostic.liveCandidates.filter { $0.entryPath == candidate.entryPath }
        let slotsText = slotSummaryText(matchingObservations)
        let note = classificationNote(candidate: candidate, diagnostic: diagnostic)

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(slotsText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(candidate.kind.label)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }

            selectablePath(candidate.entryPath)

            if let target = candidate.canonicalTarget {
                HStack(spacing: 4) {
                    Text("→")
                        .foregroundColor(.secondary)
                    selectablePath(target)
                }
            }

            Text(note)
                .font(.caption)
                .foregroundColor(noteColor(note))
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }

    private func uniqueLiveCandidates(_ diagnostic: ToolPathDiagnostic) -> [PathCandidateObservation] {
        var seen = Set<String>()
        return diagnostic.liveCandidates.filter { seen.insert($0.entryPath).inserted }
    }

    private func slotSummaryText(_ observations: [PathCandidateObservation]) -> String {
        let slots = observations.compactMap { obs -> (slot: Int, dir: String)? in
            if case .path(let slot, let dir) = obs.origin { return (slot, dir) }
            return nil
        }
        if slots.isEmpty { return "Extra root" }
        if slots.count == 1 {
            return "Slot \(slots[0].slot) (\(slots[0].dir))"
        }
        let slotNumbers = slots.map { String($0.slot) }.joined(separator: ", ")
        return "Slots \(slotNumbers) (\(slots[0].dir))"
    }

    private func classificationNote(
        candidate: PathCandidateObservation,
        diagnostic: ToolPathDiagnostic
    ) -> String {
        let winner: PathCandidateObservation?
        if case .winner(let selected) = diagnostic.selection {
            winner = selected
        } else {
            winner = nil
        }

        if let winner, candidate.entryPath == winner.entryPath {
            return "Verified winner"
        } else if let winner, candidate.canonicalTarget == winner.canonicalTarget {
            return "Same-target alias of \(winner.entryPath)"
        } else if winner != nil {
            return "Shadowed because it appears later in PATH"
        } else {
            return "Live candidate; no winner claimed"
        }
    }

    private func noteColor(_ note: String) -> Color {
        if note == "Verified winner" {
            return .accentColor
        } else if note.starts(with: "Shadowed") {
            return .secondary
        } else {
            return .secondary
        }
    }

    private func originText(_ origin: PathCandidateOrigin) -> String {
        switch origin {
        case .path(let slotIndex, let directoryText):
            "Slot \(slotIndex) (\(directoryText))"
        case .extraRoot(let index, let directoryText):
            "Extra root \(index) (\(directoryText))"
        }
    }

    private func selectablePath(_ path: String) -> some View {
        Text(path)
            .font(.subheadline)
            .fontDesign(.monospaced)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}
