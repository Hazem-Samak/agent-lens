// PromotionAcceptanceHost — M13-F owner-promotion scenario host (test-only).
//
// Fixture evidence, not a product capability or an acceptance verdict. Compiled in orchestrator
// scratch and invoked by promotion_acceptance.py inside the existing M13-C seatbelt, fixed
// environment, containment checks and fd 198 inherited-sandbox protocol.
//
//     swiftc -parse-as-library -I "$SCRATCH/out/Products/Debug" \
//       Tests/Fixtures/M13/PromotionAcceptanceHost.swift \
//       "$SCRATCH/out/Products/Debug/AgentLensCore.o" \
//       -o "$SCRATCH/PromotionAcceptanceHost"
//
// `pre-promotion` requires the selected id to have no accepted operations and overlays exactly the
// expected pair; `final` requires exactly that pair with no overlay. Manager, declared name and
// executable must equal the driver's case constants. The production process runners run behind a
// recording policy guard; no direct fallback mutation exists.

import AgentLensCore
import Darwin
import Foundation

func samePath(_ lhs: String, _ rhs: String) -> Bool {
    URL(fileURLWithPath: lhs).resolvingSymlinksInPath().path
        == URL(fileURLWithPath: rhs).resolvingSymlinksInPath().path
}
func argumentValue(_ name: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else {
        return nil
    }
    return arguments[index + 1]
}
func jsonInt(_ value: Int32?) -> Any { value.map { Int($0) } ?? NSNull() }
func isSymlink(_ path: String) -> Bool {
    var information = stat()
    return lstat(path, &information) == 0 && (information.st_mode & S_IFMT) == S_IFLNK
}
struct HostFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

final class HostReport {
    var fields: [String: Any] = [
        "host": "PromotionAcceptanceHost",
        "label": "fixture evidence, not an acceptance verdict (D-014)",
    ]
    private(set) var checks: [[String: Any]] = []
    @discardableResult
    func check(_ name: String, _ ok: Bool, _ detail: Any? = nil) -> Bool {
        checks.append(["name": name, "ok": ok, "detail": detail ?? ""])
        return ok
    }
    var failed: Bool { checks.contains { ($0["ok"] as? Bool) != true } }
    func emit() {
        fields["checks"] = checks
        fields["failed"] = failed
        guard JSONSerialization.isValidJSONObject(fields),
              let data = try? JSONSerialization.data(
                withJSONObject: fields, options: [.sortedKeys]
              )
        else {
            FileHandle.standardError.write(Data("host report is not JSON-serializable\n".utf8))
            return
        }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}

// MARK: - Recording process seams

final class QueryRunner: UpdateCommandRunner, @unchecked Sendable {
    let inner = ProcessUpdateCommandRunner()
    let brew: String
    var records: [[String: Any]] = []
    var violations: [String] = []
    init(brew: String) { self.brew = brew }
    func run(
        executablePath: String, arguments: [String],
        environment: [String: String], timeout: TimeInterval
    ) async -> CommandOutcome {
        let verb = arguments.first ?? ""
        guard samePath(executablePath, brew),
              ["--prefix", "--cellar", "--caskroom", "info", "list", "outdated"]
                .contains(verb)
        else {
            violations.append("read-only query policy refused \(arguments) at \(executablePath)")
            return .failure(.spawnFailure)
        }
        let outcome = await inner.run(
            executablePath: executablePath, arguments: arguments,
            environment: environment, timeout: timeout
        )
        let ok: Bool
        switch outcome {
        case .success: ok = true
        case .failure: ok = false
        }
        records.append(["argv": arguments, "ok": ok, "timeout": timeout])
        return outcome
    }
}

// Independent R6 expectations. Using the product environment builder as the oracle would
// let a regression to that builder silently widen what this fixture launches.
func requiredSwitches(for kind: HomebrewMutationKind) -> [String] {
    var switches = [
        "HOMEBREW_NO_AUTO_UPDATE", "HOMEBREW_NO_ANALYTICS",
        "HOMEBREW_NO_INSTALL_CLEANUP", "HOMEBREW_NO_AUTOREMOVE",
    ]
    if kind.isUpdate { switches.append("HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK") }
    if kind.packageKind == .cask { switches.append("HOMEBREW_NO_SUDO") }
    return switches
}

func forbiddenSwitches(for kind: HomebrewMutationKind) -> [String] {
    var switches = [
        "HOMEBREW_UPGRADE_GREEDY", "HOMEBREW_UPGRADE_GREEDY_CASKS",
        "HOMEBREW_NO_UPGRADE_QUIT_CASKS", "HOMEBREW_CASK_OPTS", "HOMEBREW_AUTOREMOVE",
        "HOMEBREW_NO_ASK",
    ]
    if kind.packageKind == .cask {
        switches += ["SUDO_ASKPASS", "HOMEBREW_SUDO_THROUGH_SUDO_USER"]
    }
    return switches
}

func mutationPolicyViolations(
    executablePath: String, arguments: [String], environment: [String: String],
    timeout: TimeInterval, expectedArgv: [String], brew: String,
    kind: HomebrewMutationKind
) -> [String] {
    var violations: [String] = []
    if !samePath(executablePath, brew) {
        violations.append("mutation executable is not the scratch manager")
    }
    if arguments != expectedArgv {
        violations.append("mutation argv is not the exact expected argv")
    }
    if timeout != 900 {
        violations.append("mutation timeout is not 900 seconds")
    }
    for key in requiredSwitches(for: kind) where environment[key] != "1" {
        violations.append("mutation environment \(key) is not 1")
    }
    for key in forbiddenSwitches(for: kind) where environment[key] != nil {
        violations.append("mutation environment retained \(key)")
    }
    for token in ["sudo", "zap", "--zap", "--force", "-f", "--ignore-dependencies",
                  "--greedy", "--greedy-auto-updates", "--greedy-latest", "--all",
                  "--dry-run", "--overwrite", "--build-from-source", "--installed"]
    where arguments.contains(token) {
        violations.append("mutation argv contains forbidden token \(token)")
    }
    return violations
}

func environmentAudit(
    kind: HomebrewMutationKind, environment: [String: String]
) -> [String: Any] {
    var audit: [String: Any] = [:]
    for key in requiredSwitches(for: kind) { audit[key] = environment[key] ?? "missing" }
    for key in forbiddenSwitches(for: kind) {
        audit[key] = environment[key] == nil ? "absent" : "present"
    }
    return audit
}

final class MutationRunner: OperationCommandRunner, @unchecked Sendable {
    let inner = ProcessOperationCommandRunner()
    let brew: String
    let expectedArgv: [String]
    let kind: HomebrewMutationKind
    var attempts: [[String: Any]] = []
    var launches: [[String: Any]] = []
    var violations: [String] = []
    init(brew: String, expectedArgv: [String], kind: HomebrewMutationKind) {
        self.brew = brew
        self.expectedArgv = expectedArgv
        self.kind = kind
    }
    func run(
        executablePath: String, arguments: [String], environment: [String: String],
        currentDirectory: String, timeout: TimeInterval
    ) async -> OperationCommandResult {
        var policy = mutationPolicyViolations(
            executablePath: executablePath, arguments: arguments,
            environment: environment, timeout: timeout,
            expectedArgv: expectedArgv, brew: brew, kind: kind
        )
        if !launches.isEmpty { policy.append("mutation launch was attempted more than once") }
        if !policy.isEmpty {
            violations.append(contentsOf: policy)
            attempts.append([
                "argv": arguments,
                "environmentAudit": environmentAudit(kind: kind, environment: environment),
                "violations": policy, "launched": false,
            ])
            return OperationCommandResult(
                stdout: Data(), stderr: Data(),
                stdoutTruncated: false, stderrTruncated: false,
                exitStatus: nil, processStarted: false,
                timedOut: false, cancelled: false, cleanupWarning: false
            )
        }
        let result = await inner.run(
            executablePath: executablePath, arguments: arguments,
            environment: environment, currentDirectory: currentDirectory, timeout: timeout
        )
        launches.append([
            "executable": executablePath,
            "workingDirectory": currentDirectory,
            "timeout": timeout,
            "argv": arguments,
            "environmentAudit": environmentAudit(kind: kind, environment: environment),
            "processStarted": result.processStarted,
            "exitStatus": jsonInt(result.exitStatus),
            "cleanupWarning": result.cleanupWarning,
        ])
        return result
    }
}

// MARK: - Expected case and JSON facts

struct Expected {
    let id, manager, package, executable, oldVersion, newVersion, root, brew, prefix: String
    var isFormula: Bool { manager == "formula" }
    var formulaName: String {
        package.split(separator: "/").last.map(String.init) ?? package
    }
    var target: String { prefix + "/bin/" + executable }
    var updateArgv: [String] {
        isFormula ? ["upgrade", "--formula", "--yes", package]
            : ["upgrade", "--cask", "--yes", package]
    }
    var uninstallArgv: [String] {
        isFormula ? ["uninstall", "--formula", package]
            : ["uninstall", "--cask", package]
    }
    var operations: [AcceptedOperation] {
        isFormula ? [.homebrewFormulaUpdate, .homebrewFormulaUninstall]
            : [.homebrewCaskUpdate, .homebrewCaskUninstall]
    }
    func kind(uninstall: Bool) -> HomebrewMutationKind {
        switch (isFormula, uninstall) {
        case (true, false): .formulaUpdate
        case (true, true): .formulaUninstall
        case (false, false): .caskUpdate
        case (false, true): .caskUninstall
        }
    }
}

func scanJSON(
    _ diagnostic: ToolPathDiagnostic, _ ownership: InstallationOwnershipResult
) -> [String: Any] {
    let tool = diagnostic.detectedTool
    let owner: [String: Any]
    switch ownership.outcome {
    case .verified(let installation):
        owner = [
            "result": "verified", "packageName": installation.packageName,
            "installationRoot": installation.installationRoot,
            "selectionTarget": installation.selection.canonicalTarget,
        ]
    case .unknown(let reason):
        owner = ["result": "unknown", "reason": String(describing: reason)]
    }
    return [
        "state": tool.state.rawValue, "source": tool.source,
        "entryPath": tool.entryPath ?? NSNull(),
        "version": tool.version ?? NSNull(),
        "selection": String(describing: diagnostic.selection), "ownership": owner,
    ]
}

func caskArtifactTargetsJSON(_ targets: [HomebrewCaskArtifactTarget]) -> [[String: Any]] {
    targets.map { ["kind": $0.kind.rawValue, "target": $0.target] }
}

func previewJSON(_ p: HomebrewFormulaUpdatePreview) -> [String: Any] {
    [
        "fullName": p.fullName, "selectedEntryPath": p.selectedEntryPath,
        "selectedKegVersion": p.selectedKegVersion, "installedKegs": p.installedKegs,
        "targetVersion": p.targetVersion, "workingDirectory": p.workingDirectory,
        "arguments": p.arguments, "timeoutSeconds": p.timeoutSeconds, "effect": p.effect,
    ]
}
func previewJSON(_ p: HomebrewFormulaUninstallPreview) -> [String: Any] {
    [
        "fullName": p.fullName, "selectedEntryPath": p.selectedEntryPath,
        "selectedKegVersion": p.selectedKegVersion, "installedKegs": p.installedKegs,
        "remainingKegDisclosure": p.remainingKegDisclosure,
        "dependentRefusalDisclosure": p.dependentRefusalDisclosure,
        "workingDirectory": p.workingDirectory, "arguments": p.arguments,
        "timeoutSeconds": p.timeoutSeconds, "effect": p.effect,
    ]
}
func previewJSON(_ p: HomebrewCaskUpdatePreview) -> [String: Any] {
    [
        "token": p.token, "fullToken": p.fullToken, "tap": p.tap,
        "selectedEntryPath": p.selectedEntryPath, "installedVersion": p.installedVersion,
        "targetVersion": p.targetVersion,
        "artifactTargets": caskArtifactTargetsJSON(p.artifactTargets),
        "zapDeclared": p.zapDeclared, "zapDisclosure": p.zapDisclosure,
        "workingDirectory": p.workingDirectory, "arguments": p.arguments,
        "timeoutSeconds": p.timeoutSeconds, "effect": p.effect,
    ]
}
func previewJSON(_ p: HomebrewCaskUninstallPreview) -> [String: Any] {
    [
        "token": p.token, "fullToken": p.fullToken, "tap": p.tap,
        "selectedEntryPath": p.selectedEntryPath, "installedVersion": p.installedVersion,
        "artifactTargets": caskArtifactTargetsJSON(p.artifactTargets),
        "companionAppDisclosure": p.companionAppDisclosure,
        "zapDeclared": p.zapDeclared, "zapDisclosure": p.zapDisclosure,
        "workingDirectory": p.workingDirectory, "arguments": p.arguments,
        "timeoutSeconds": p.timeoutSeconds, "effect": p.effect,
    ]
}

// MARK: - Host

@main
struct PromotionAcceptanceHost {
    static func main() async {
        let report = HostReport()
        do {
            try await run(report)
            report.emit()
            exit(report.failed ? 3 : 0)
        } catch {
            report.check("host completed", false, String(describing: error))
            report.emit()
            exit(3)
        }
    }

    static func run(_ report: HostReport) async throws {
        let arguments = CommandLine.arguments
        guard let root = argumentValue("--root", in: arguments),
              let registryPath = argumentValue("--registry", in: arguments),
              let mode = argumentValue("--mode", in: arguments),
              let id = argumentValue("--id", in: arguments),
              let manager = argumentValue("--manager", in: arguments),
              let package = argumentValue("--package", in: arguments),
              let executable = argumentValue("--executable", in: arguments),
              let oldVersion = argumentValue("--old-version", in: arguments),
              let newVersion = argumentValue("--new-version", in: arguments),
              let action = argumentValue("--action", in: arguments)
        else { throw HostFailure("missing required arguments") }
        guard ["formula", "cask"].contains(manager) else {
            throw HostFailure("unknown manager: \(manager)")
        }
        guard root.hasPrefix("/"), registryPath.hasPrefix("/") else {
            throw HostFailure("root and registry must be absolute paths")
        }
        guard ["pre-promotion", "final"].contains(mode) else {
            throw HostFailure("unknown mode: \(mode)")
        }
        guard ["scan", "collision", "update-preview", "update-execute",
               "uninstall-preview", "uninstall-execute"].contains(action)
        else { throw HostFailure("unknown action: \(action)") }

        let brew = root + "/prefix/bin/brew"
        let prefix = root + "/prefix"
        guard FileManager.default.isExecutableFile(atPath: brew) else {
            throw HostFailure("scratch brew is not executable: \(brew)")
        }
        let expected = Expected(
            id: id, manager: manager, package: package, executable: executable,
            oldVersion: oldVersion, newVersion: newVersion,
            root: root, brew: brew, prefix: prefix
        )
        report.fields["expected"] = [
            "id": id, "manager": manager, "package": package,
            "executable": executable, "oldVersion": oldVersion,
            "newVersion": newVersion, "mode": mode, "action": action,
        ]

        let definitions = try DetectorRegistry.validate(
            data: try Data(contentsOf: URL(fileURLWithPath: registryPath))
        )
        guard let base = definitions.first(where: { $0.id == id }) else {
            throw HostFailure("registry has no id \(id)")
        }
        let expectedManager: PackageManager = expected.isFormula
            ? .homebrewFormula : .homebrewCask
        guard base.packages.count == 1, let declared = base.packages.first,
              declared.manager == expectedManager, declared.name == package,
              base.executableName == executable
        else {
            throw HostFailure(
                "\(id) does not declare exactly the expected \(manager) package \(package) and executable \(executable)"
            )
        }
        report.check(
            "registry declares exactly the expected manager, package and executable", true,
            ["manager": declared.manager.rawValue, "package": declared.name]
        )

        let definition: DetectorDefinition
        if mode == "pre-promotion" {
            guard base.acceptedOperations.isEmpty else {
                report.check(
                    "pre-promotion baseline has no accepted operations for the selected id",
                    false, base.acceptedOperations.map(\.rawValue)
                )
                throw HostFailure("\(id) already has accepted operations; use final mode")
            }
            report.check(
                "pre-promotion baseline has no accepted operations for the selected id", true, []
            )
            definition = try DetectorDefinition(
                id: base.id, displayName: base.displayName,
                executableName: base.executableName, extraSearchRoots: base.extraSearchRoots,
                fixture: base.fixture, category: base.category, packages: base.packages,
                informationURL: base.informationURL,
                uninstallInstructionsURL: base.uninstallInstructionsURL,
                versionQuery: base.versionQuery, acceptedOperations: expected.operations
            )
            let preserved = definition.id == base.id
                && definition.displayName == base.displayName
                && definition.executableName == base.executableName
                && definition.extraSearchRoots == base.extraSearchRoots
                && definition.fixture == base.fixture
                && definition.category == base.category
                && definition.packages == base.packages
                && definition.informationURL == base.informationURL
                && definition.uninstallInstructionsURL == base.uninstallInstructionsURL
                && definition.versionQuery == base.versionQuery
            report.check(
                "pre-promotion overlay changes only acceptedOperations", preserved,
                ["base": base.acceptedOperations.map(\.rawValue),
                 "overlay": definition.acceptedOperations.map(\.rawValue)]
            )
        } else {
            let exactPair = base.acceptedOperations.count == 2
                && expected.operations.allSatisfy {
                    base.acceptedOperations.contains($0)
                }
                && base.acceptedOperations.allSatisfy {
                    expected.operations.contains($0)
                }
            report.check(
                "final bundled registry grants exactly the expected operation pair", exactPair,
                ["expected": expected.operations.map(\.rawValue),
                 "declared": base.acceptedOperations.map(\.rawValue)]
            )
            guard exactPair else {
                throw HostFailure("bundled registry does not grant the exact expected pair")
            }
            definition = base
        }
        report.fields["directBundledAcceptedOperations"] =
            base.acceptedOperations.map(\.rawValue)

        var raw = ProcessInfo.processInfo.environment
        guard let inheritedPath = raw["PATH"],
              inheritedPath.split(separator: ":").first.map(String.init) == prefix + "/bin",
              raw["TMPDIR"] == root + "/tmp", raw["HOME"] == root + "/home",
              samePath(NSHomeDirectory(), root + "/home"),
              base.extraSearchRoots.isEmpty || base.extraSearchRoots == ["~/.local/bin"]
        else { throw HostFailure("fixture PATH or Foundation home is not contained") }
        // Seed adversarial inputs that R6 rejects, and ensure the cask sudo ban is not inherited.
        raw.removeValue(forKey: "HOMEBREW_NO_SUDO")
        raw.removeValue(forKey: "HOMEBREW_NO_ASK")
        raw["SUDO_ASKPASS"] = root + "/not-a-program"
        raw["HOMEBREW_SUDO_THROUGH_SUDO_USER"] = "1"
        raw["HOMEBREW_UPGRADE_GREEDY"] = "1"
        raw["HOMEBREW_UPGRADE_GREEDY_CASKS"] = "1"
        raw["HOMEBREW_NO_UPGRADE_QUIT_CASKS"] = "1"
        raw["HOMEBREW_CASK_OPTS"] = "--appdir=" + root + "/hostile-appdir"
        raw["HOMEBREW_AUTOREMOVE"] = "1"
        let environment = ShellEnvironment(
            shellPath: "/bin/sh",
            pathEntries: inheritedPath.split(separator: ":").map(String.init),
            pathJoined: inheritedPath, raw: raw, isDegraded: false
        )

        let isUninstall = action.contains("uninstall")
        let kind = expected.kind(uninstall: isUninstall)
        let expectedArgv = isUninstall ? expected.uninstallArgv : expected.updateArgv
        let query = QueryRunner(brew: brew)
        let mutation = MutationRunner(brew: brew, expectedArgv: expectedArgv, kind: kind)
        let gate = OperationExecutionGate.shared

        func scan(_ entry: DetectorDefinition) -> ToolPathDiagnostic {
            PathDiagnosticsScanner.scan(
                detector: entry.makeDetector(), environment: environment,
                currentDirectory: root
            )
        }
        func verify(
            _ entry: DetectorDefinition, _ diagnostic: ToolPathDiagnostic
        ) async -> InstallationOwnershipResult {
            await InstallationOwnershipVerifier.verify(
                definition: entry, diagnostic: diagnostic, environment: environment,
                runner: query, currentDirectory: root, now: { Date() }
            )
        }
        let scanClosure: @Sendable (
            DetectorDefinition, ShellEnvironment, String
        ) -> ToolPathDiagnostic? = { entry, shell, cwd in
            PathDiagnosticsScanner.scan(
                detector: entry.makeDetector(), environment: shell, currentDirectory: cwd
            )
        }
        let reconcile: @Sendable (
            DetectorDefinition
        ) async -> (ToolPathDiagnostic, ShellEnvironment)? = { entry in
            (PathDiagnosticsScanner.scan(
                detector: entry.makeDetector(), environment: environment,
                currentDirectory: root
            ), environment)
        }

        func recordScan(_ label: String) async {
            let diagnostic = scan(definition)
            let ownership = await verify(definition, diagnostic)
            report.fields[label] = scanJSON(diagnostic, ownership)
        }
        func recordOutcome(
            _ state: OperationState, _ started: Bool, _ exit: Int32?,
            _ cleanup: [String], _ message: String?
        ) {
            report.fields["outcome"] = [
                "state": state.rawValue, "processStarted": started,
                "exitStatus": jsonInt(exit), "cleanupWarnings": cleanup,
                "message": message ?? NSNull(),
            ]
        }
        func checkCancellation(_ cancelled: Bool) {
            let preview = report.fields["preview"] as? [String: Any] ?? [:]
            report.fields["cancel"] = cancelled
            report.check("preview cancel was accepted exactly once", cancelled, preview)
            if let working = preview["workingDirectory"] as? String {
                report.check(
                    "preview cancel released its owned operation root",
                    !FileManager.default.fileExists(atPath: working), working
                )
            }
            report.check(
                "preview cancel launched no mutation",
                mutation.launches.isEmpty && mutation.attempts.isEmpty,
                ["launches": mutation.launches, "attempts": mutation.attempts]
            )
        }
        func finish(executing: Bool) {
            report.fields["queries"] = query.records
            report.fields["queryViolations"] = query.violations
            report.fields["mutationAttempts"] = mutation.attempts
            report.fields["mutationLaunches"] = mutation.launches
            report.fields["mutationViolations"] = mutation.violations
            report.check(
                "read-only query policy has no violations",
                query.violations.isEmpty, query.violations
            )
            report.check(
                "mutation launch policy has no violations",
                mutation.violations.isEmpty, mutation.violations
            )
            report.check(
                "mutation attempts are empty", mutation.attempts.isEmpty, mutation.attempts
            )
            report.check(
                "mutation launch count is exactly \(executing ? 1 : 0)",
                mutation.launches.count == (executing ? 1 : 0), mutation.launches
            )
        }

        if action == "collision" {
            guard expected.id == "goose", expected.isFormula else {
                throw HostFailure("collision action is only defined for the goose formula case")
            }
            let diagnostic = scan(definition)
            let ownership = await verify(definition, diagnostic)
            let json = scanJSON(diagnostic, ownership)
            report.fields["scan"] = json
            report.check(
                "collision scan selects the live basename entry",
                diagnostic.detectedTool.entryPath == expected.target, json
            )
            let unknown: Bool
            if case .unknown = ownership.outcome { unknown = true } else { unknown = false }
            report.check(
                "collision ownership is not verified for the declared formula", unknown, json
            )
            switch await HomebrewFormulaUpdateOperation.prepare(
                definition: definition, diagnostic: diagnostic, environment: environment,
                currentDirectory: root, runner: query
            ) {
            case .unavailable(let reason):
                report.fields["refusal"] = reason.message
                report.check(
                    "collision preparation refused before any mutation launch", true,
                    reason.message
                )
            case .ready(let preparation):
                report.check(
                    "collision preparation refused before any mutation launch", false,
                    "a basename collision produced a ready preparation"
                )
                _ = HomebrewFormulaUpdateOperation.cancel(preparation)
            }
            finish(executing: false)
            return
        }

        if action == "scan" {
            await recordScan("scan")
            finish(executing: false)
            return
        }

        if expected.isFormula {
            switch action {
            case "update-preview", "update-execute":
                switch await HomebrewFormulaUpdateOperation.prepare(
                    definition: definition, diagnostic: scan(definition),
                    environment: environment, currentDirectory: root, runner: query
                ) {
                case .unavailable(let reason):
                    report.check(
                        "formula Update preparation is available", false, reason.message
                    )
                    throw HostFailure("formula Update preparation refused")
                case .ready(let preparation):
                    report.fields["preview"] = previewJSON(preparation.preview)
                    if action == "update-preview" {
                        checkCancellation(HomebrewFormulaUpdateOperation.cancel(preparation))
                        finish(executing: false)
                    } else {
                        let outcome = await HomebrewFormulaUpdateOperation.execute(
                            confirmed: preparation, environment: environment,
                            scan: scanClosure, reconcileAfterLaunch: reconcile,
                            updateRunner: query, operationRunner: mutation, gate: gate
                        )
                        recordOutcome(
                            outcome.state, outcome.processStarted, outcome.exitStatus,
                            outcome.cleanupWarnings, outcome.message
                        )
                        if let delta = outcome.reconciliation {
                            report.fields["delta"] = [
                                "beforeSelectedKegVersion": delta.beforeSelectedKegVersion,
                                "afterSelectedKegVersion": delta.afterSelectedKegVersion ?? NSNull(),
                                "afterInstalledKegs": delta.afterInstalledKegs,
                                "previousKegStillPresent": delta.previousKegStillPresent,
                                "previousKegReplaced": delta.previousKegReplaced,
                                "observedTargetVersion": delta.observedTargetVersion,
                                "versionMatchesTarget": delta.versionMatchesTarget,
                                "observationFailed": delta.observationFailed,
                            ]
                        }
                        await recordScan("postScan")
                        finish(executing: true)
                    }
                }
            case "uninstall-preview", "uninstall-execute":
                switch await HomebrewFormulaUninstallOperation.prepare(
                    definition: definition, diagnostic: scan(definition),
                    environment: environment, currentDirectory: root, runner: query
                ) {
                case .unavailable(let reason):
                    report.check(
                        "formula Uninstall preparation is available", false, reason.message
                    )
                    throw HostFailure("formula Uninstall preparation refused")
                case .ready(let preparation):
                    report.fields["preview"] = previewJSON(preparation.preview)
                    if action == "uninstall-preview" {
                        checkCancellation(HomebrewFormulaUninstallOperation.cancel(preparation))
                        finish(executing: false)
                    } else {
                        let outcome = await HomebrewFormulaUninstallOperation.execute(
                            confirmed: preparation, environment: environment,
                            scan: scanClosure, reconcileAfterLaunch: reconcile,
                            updateRunner: query, operationRunner: mutation, gate: gate
                        )
                        recordOutcome(
                            outcome.state, outcome.processStarted, outcome.exitStatus,
                            outcome.cleanupWarnings, outcome.message
                        )
                        if let delta = outcome.reconciliation {
                            report.fields["delta"] = [
                                "beforeSelectedKegVersion": delta.beforeSelectedKegVersion,
                                "recordedKegAbsent": delta.recordedKegAbsent,
                                "recordedKegReplaced": delta.recordedKegReplaced,
                                "selectedTargetReleased": delta.selectedTargetReleased,
                                "selectedEntryResidue": delta.selectedEntryResidue,
                                "observationFailed": delta.observationFailed,
                                "remainingKegs": delta.remainingKegs ?? NSNull(),
                                "formulaStillInstalledViaRemainingKeg":
                                    delta.formulaStillInstalledViaRemainingKeg ?? NSNull(),
                            ]
                        }
                        await recordScan("postScan")
                        finish(executing: true)
                    }
                }
            default:
                throw HostFailure("formula id does not support action \(action)")
            }
        } else {
            switch action {
            case "update-preview", "update-execute":
                switch await HomebrewCaskUpdateOperation.prepare(
                    definition: definition, diagnostic: scan(definition),
                    environment: environment, currentDirectory: root, runner: query
                ) {
                case .unavailable(let reason):
                    report.check(
                        "cask Update preparation is available", false, reason.message
                    )
                    throw HostFailure("cask Update preparation refused")
                case .ready(let preparation):
                    report.fields["preview"] = previewJSON(preparation.preview)
                    if action == "update-preview" {
                        checkCancellation(HomebrewCaskUpdateOperation.cancel(preparation))
                        finish(executing: false)
                    } else {
                        let outcome = await HomebrewCaskUpdateOperation.execute(
                            confirmed: preparation, environment: environment,
                            scan: scanClosure, reconcileAfterLaunch: reconcile,
                            updateRunner: query, operationRunner: mutation, gate: gate
                        )
                        recordOutcome(
                            outcome.state, outcome.processStarted, outcome.exitStatus,
                            outcome.cleanupWarnings, outcome.message
                        )
                        if let delta = outcome.reconciliation {
                            report.fields["delta"] = [
                                "beforeInstalledVersion": delta.beforeInstalledVersion,
                                "afterInstalledVersion": delta.afterInstalledVersion ?? NSNull(),
                                "observedTargetVersion": delta.observedTargetVersion,
                                "versionMatchesTarget": delta.versionMatchesTarget,
                                "tokenMatches": delta.tokenMatches,
                                "stagedMembershipConfirmed": delta.stagedMembershipConfirmed,
                                "managedTargetsReleased": delta.managedTargetsReleased,
                                "observationFailed": delta.observationFailed,
                            ]
                        }
                        await recordScan("postScan")
                        finish(executing: true)
                    }
                }
            case "uninstall-preview", "uninstall-execute":
                switch await HomebrewCaskUninstallOperation.prepare(
                    definition: definition, diagnostic: scan(definition),
                    environment: environment, currentDirectory: root, runner: query
                ) {
                case .unavailable(let reason):
                    report.check(
                        "cask Uninstall preparation is available", false, reason.message
                    )
                    throw HostFailure("cask Uninstall preparation refused")
                case .ready(let preparation):
                    report.fields["preview"] = previewJSON(preparation.preview)
                    if action == "uninstall-preview" {
                        checkCancellation(HomebrewCaskUninstallOperation.cancel(preparation))
                        finish(executing: false)
                    } else {
                        let outcome = await HomebrewCaskUninstallOperation.execute(
                            confirmed: preparation, environment: environment,
                            scan: scanClosure, reconcileAfterLaunch: reconcile,
                            updateRunner: query, operationRunner: mutation, gate: gate
                        )
                        recordOutcome(
                            outcome.state, outcome.processStarted, outcome.exitStatus,
                            outcome.cleanupWarnings, outcome.message
                        )
                        if let delta = outcome.reconciliation {
                            report.fields["delta"] = [
                                "beforeInstalledVersion": delta.beforeInstalledVersion,
                                "infoInstalledAbsent": delta.infoInstalledAbsent,
                                "tokenDirectoryAbsent": delta.tokenDirectoryAbsent,
                                "tokenDirectoryReplaced": delta.tokenDirectoryReplaced,
                                "selectedTargetReleased": delta.selectedTargetReleased,
                                "selectedEntryResidue": delta.selectedEntryResidue,
                                "managedTargetsReleased": delta.managedTargetsReleased,
                                "observationFailed": delta.observationFailed,
                            ]
                        }
                        await recordScan("postScan")
                        finish(executing: true)
                    }
                }
            default:
                throw HostFailure("cask id does not support action \(action)")
            }
        }
    }
}
