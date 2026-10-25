// InstallationVersionCollector — sequential, identity-bound local version observations.
//
// One canonical target gets one query at most. The entry is observed before and after the query,
// and every measured identity is observed once more before publication. A changed, vanished or
// replaced executable loses its value instead of borrowing an alias or a later copy's response.

import Foundation

struct InstallationVersionProbeTarget: Equatable, Sendable {
    let canonicalTarget: String
    let entryPath: String
    let origin: PathCandidateOrigin
    let isSelected: Bool
}

enum InstallationVersionCollectorTestHooks {
    /// Dormant outside tests. Invoked after every measured identity has been revalidated and
    /// immediately before the terminal selected-entry recheck, so a test can deterministically
    /// change the selected fixture after the per-target publication loop has finished.
    @TaskLocal static var onBeforeTerminalSelectedRecheck: (@Sendable () -> Void)?
}

struct InstallationVersionCollection: Sendable {
    let observations: [InstallationVersionObservation]
    /// Non-nil when the selected candidate's identity changed during collection. The scanner then
    /// invalidates the PATH selection instead of retaining a stale success or claiming a new winner.
    let selectedIdentityFailure: String?
}

enum InstallationVersionCollector {

    /// Fixed aggregate budget for one tool scan. Not registry metadata and not configurable.
    static let aggregateBudgetNanoseconds: UInt64 = 10_000_000_000

    private struct ProbeState {
        let target: InstallationVersionProbeTarget
        var observation: InstallationVersionObservation
        var verifiedIdentity: ObservedExecutable?
    }

    static func collect(
        targets: [InstallationVersionProbeTarget],
        selectedEntryPath: String?,
        selectedCanonicalTarget: String?,
        detector: ToolDetector,
        environment: ShellEnvironment,
        monotonicNow: @Sendable () -> UInt64
    ) -> InstallationVersionCollection {
        let budgetStart = monotonicNow()
        let deadline = budgetStart.addingReportingOverflow(aggregateBudgetNanoseconds)

        func budgetRemainingNanoseconds() -> UInt64 {
            guard !deadline.overflow else { return UInt64.max }
            let now = monotonicNow()
            guard now < deadline.partialValue else { return 0 }
            return deadline.partialValue - now
        }

        var selectedIdentityFailure: String?
        var selectedBaseline: ObservedExecutable?
        if let selectedEntryPath, let selectedCanonicalTarget {
            if let baseline = FileIdentityObserver.observeExecutable(entryPath: selectedEntryPath),
               baseline.canonicalTarget == selectedCanonicalTarget {
                selectedBaseline = baseline
            } else {
                selectedIdentityFailure =
                    "the selected executable target or identity changed before version collection"
            }
        }

        var states: [ProbeState] = []
        states.reserveCapacity(targets.count)

        for target in targets {
            if budgetRemainingNanoseconds() == 0 {
                states.append(ProbeState(
                    target: target,
                    observation: unknownObservation(target, reason: .budgetExhausted),
                    verifiedIdentity: nil
                ))
                continue
            }

            guard let before = FileIdentityObserver.observeExecutable(entryPath: target.entryPath) else {
                if target.isSelected {
                    selectedIdentityFailure =
                        "the selected executable became unavailable before its version query"
                }
                states.append(ProbeState(
                    target: target,
                    observation: unknownObservation(target, reason: .executableUnavailable),
                    verifiedIdentity: nil
                ))
                continue
            }
            guard before.canonicalTarget == target.canonicalTarget else {
                if target.isSelected {
                    selectedIdentityFailure =
                        "the selected executable target or identity changed before its version query"
                }
                states.append(ProbeState(
                    target: target,
                    observation: unknownObservation(target, reason: .identityChanged),
                    verifiedIdentity: nil
                ))
                continue
            }

            if target.isSelected {
                guard let selectedBaseline, before == selectedBaseline else {
                    selectedIdentityFailure =
                        "the selected executable target or identity changed before its version query"
                    states.append(ProbeState(
                        target: target,
                        observation: unknownObservation(
                            target,
                            reason: .identityChanged,
                            fingerprint: before.fingerprint
                        ),
                        verifiedIdentity: nil
                    ))
                    continue
                }
            }

            // Observing the entry can use part of the budget. Re-check immediately before launch.
            let remainingNanoseconds = budgetRemainingNanoseconds()
            guard remainingNanoseconds > 0 else {
                states.append(ProbeState(
                    target: target,
                    observation: unknownObservation(target, reason: .budgetExhausted),
                    verifiedIdentity: nil
                ))
                continue
            }

            let remainingSeconds = Double(remainingNanoseconds) / 1_000_000_000
            let timeout = min(ToolDetector.versionTimeout, remainingSeconds)
            let measured = detector.versionQuery(
                target.entryPath,
                environment,
                timeout,
                detector.versionQuerySpecification
            )

            guard let after = FileIdentityObserver.observeExecutable(entryPath: target.entryPath),
                  after == before
            else {
                if target.isSelected {
                    selectedIdentityFailure =
                        "the selected executable target or identity changed during its version query"
                }
                states.append(ProbeState(
                    target: target,
                    observation: unknownObservation(
                        target,
                        reason: .identityChanged,
                        fingerprint: before.fingerprint
                    ),
                    verifiedIdentity: nil
                ))
                continue
            }

            let outcome: InstallationVersionOutcome
            if let measured {
                outcome = .measured(measured)
            } else {
                outcome = .unknown(.queryFailed)
            }
            states.append(ProbeState(
                target: target,
                observation: InstallationVersionObservation(
                    canonicalTarget: target.canonicalTarget,
                    entryPath: target.entryPath,
                    origin: target.origin,
                    fingerprint: before.fingerprint,
                    outcome: outcome
                ),
                verifiedIdentity: before
            ))
        }

        // Probing a later copy creates a real interval in which an earlier installation can change.
        // Revalidate every measured identity before publishing the report.
        for index in states.indices {
            guard let verified = states[index].verifiedIdentity else { continue }
            let current = FileIdentityObserver.observeExecutable(
                entryPath: states[index].target.entryPath
            )
            guard current == verified else {
                if states[index].target.isSelected {
                    selectedIdentityFailure =
                        "the selected executable target or identity changed before publication"
                }
                states[index].observation = unknownObservation(
                    states[index].target,
                    reason: .identityChanged,
                    fingerprint: verified.fingerprint
                )
                states[index].verifiedIdentity = nil
                continue
            }
        }

        // Check the selected entry even when its own query failed or was never launched.
        InstallationVersionCollectorTestHooks.onBeforeTerminalSelectedRecheck?()
        if let selectedEntryPath, let selectedBaseline {
            let current = FileIdentityObserver.observeExecutable(entryPath: selectedEntryPath)
            if current != selectedBaseline {
                selectedIdentityFailure =
                    "the selected executable target or identity changed during version collection"
            }
        }

        // The terminal check is the last opportunity to detect that the selected identity moved.
        // A still-measured selected observation then describes the previous identity and must not
        // survive publication. An existing unknown reason remains meaningful, and observations for
        // unrelated shadowed targets are never touched.
        if selectedIdentityFailure != nil {
            for index in states.indices where states[index].target.isSelected {
                guard case .measured = states[index].observation.outcome else { continue }
                states[index].observation = unknownObservation(
                    states[index].target,
                    reason: .identityChanged,
                    fingerprint: states[index].observation.fingerprint
                )
                states[index].verifiedIdentity = nil
            }
        }

        return InstallationVersionCollection(
            observations: states.map(\.observation),
            selectedIdentityFailure: selectedIdentityFailure
        )
    }

    private static func unknownObservation(
        _ target: InstallationVersionProbeTarget,
        reason: InstallationVersionUnknownReason,
        fingerprint: ExecutableFingerprint? = nil
    ) -> InstallationVersionObservation {
        InstallationVersionObservation(
            canonicalTarget: target.canonicalTarget,
            entryPath: target.entryPath,
            origin: target.origin,
            fingerprint: fingerprint,
            outcome: .unknown(reason)
        )
    }
}
