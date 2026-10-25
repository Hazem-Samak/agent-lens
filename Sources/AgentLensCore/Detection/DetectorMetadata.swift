// DetectorMetadata — concrete, validated registry metadata value types (M9-A).
//
// A declared package candidate is metadata only. It never proves that an
// installation is package-owned, and it never authorizes a manager command.
// Every value that can be constructed or decoded here is validated: invalid
// package identities or version-query arguments cannot reach a process launch
// merely because a caller bypassed JSON validation.

import Foundation

/// A CodingKey that accepts every string. `allKeys` on a container keyed by a
/// concrete enum silently drops keys the enum cannot represent, which would hide
/// unknown JSON members from Codable validation. This key exposes them so the
/// canonical schema checks can reject them on the decoding path too.
private struct AnyDetectorCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

/// Returns the first unknown key in a keyed decoder, using the same ordering as
/// the JSONSerialization validation path.
func firstUnknownDetectorKey(
    in decoder: any Decoder,
    allowed: Set<String>
) throws -> String? {
    let container = try decoder.container(keyedBy: AnyDetectorCodingKey.self)
    return container.allKeys
        .map(\.stringValue)
        .filter { !allowed.contains($0) }
        .sorted()
        .first
}

/// Tool category shown in the CLI and native details. This is detector metadata,
/// not a manager category and not a navigation/filter model.
public enum ToolCategory: String, Codable, Sendable, Equatable, CaseIterable {
    case aiAgent
    case aiCodingTool
    case aiHarness

    public var label: String {
        switch self {
        case .aiAgent: "AI Agent"
        case .aiCodingTool: "AI Coding Tool"
        case .aiHarness: "AI Harness"
        }
    }
}

/// The package ecosystems a detector may declare. A candidate is not ownership.
public enum PackageManager: String, Codable, Sendable, Equatable, CaseIterable {
    case npm
    case homebrewFormula
    case homebrewCask

    public var label: String {
        switch self {
        case .npm: "npm"
        case .homebrewFormula: "Homebrew formula"
        case .homebrewCask: "Homebrew cask"
        }
    }
}

/// One declared package candidate, e.g. npm `@openai/codex` or Homebrew cask `codex`.
public struct DeclaredPackage: Codable, Sendable, Equatable {

    public let manager: PackageManager
    public let name: String

    public init(manager: PackageManager, name: String) throws {
        if let failure = Self.validationFailure(manager: manager, name: name) {
            throw DetectorRegistryError.invalidField(
                field: "name",
                id: "(declared package)",
                reason: failure
            )
        }
        self.manager = manager
        self.name = name
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case manager
        case name
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let allowed = Set(CodingKeys.allCases.map(\.stringValue))
        if let unknown = try firstUnknownDetectorKey(in: decoder, allowed: allowed) {
            throw DetectorRegistryError.unknownKey(key: unknown, id: "(declared package)")
        }

        let rawManager = try container.decode(String.self, forKey: .manager)
        guard let manager = PackageManager(rawValue: rawManager) else {
            throw DetectorRegistryError.invalidField(
                field: "manager",
                id: "(declared package)",
                reason: "must be one of npm, homebrewFormula, homebrewCask"
            )
        }
        let name = try container.decode(String.self, forKey: .name)
        try self.init(manager: manager, name: name)
    }

    /// A named validation failure, or nil when the candidate is valid.
    static func validationFailure(manager: PackageManager, name: String) -> String? {
        guard !name.isEmpty else { return "must not be empty" }
        guard !name.unicodeScalars.contains(where: { $0.value == 0 }) else {
            return "must not contain NUL"
        }
        guard !name.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) }) else {
            return "must not contain whitespace"
        }
        guard !name.hasPrefix("-") else { return "must not start with an option marker" }

        switch manager {
        case .npm:
            // Scoped and unscoped npm names. Paths, shell syntax and options are rejected
            // because they fall outside this conservative package-name alphabet.
            let pattern = #"^(@[A-Za-z0-9][A-Za-z0-9._~-]*/)?[A-Za-z0-9][A-Za-z0-9._~-]*$"#
            guard name.range(of: pattern, options: .regularExpression) != nil else {
                return "must be a valid npm package name (scoped names use @scope/name)"
            }
        case .homebrewFormula, .homebrewCask:
            // A bare formula/cask name or a fully qualified tap user/repo/name.
            // Two components are neither and must not be accepted.
            let components = name.split(separator: "/", omittingEmptySubsequences: false)
            guard components.count == 1 || components.count == 3 else {
                return "must be a formula/cask name or a fully qualified tap"
            }
            let pattern = #"^[A-Za-z0-9][A-Za-z0-9._+@-]*$"#
            for component in components {
                guard String(component).range(of: pattern, options: .regularExpression) != nil else {
                    return "must be a formula/cask name or a fully qualified tap"
                }
            }
        }
        return nil
    }
}

/// The bounded version-query contract declared by a detector.
public struct VersionQuerySpecification: Codable, Sendable, Equatable {

    public enum Stream: String, Codable, Sendable, Equatable, CaseIterable {
        case stdout
        case stderr
    }

    public enum LineSelection: String, Codable, Sendable, Equatable, CaseIterable {
        case first
        case firstNonempty
    }

    public static let maximumArgumentCount = 8
    public static let maximumArgumentBytes = 256
    public static let maximumTotalBytes = 1024

    public let arguments: [String]
    public let stream: Stream
    public let line: LineSelection

    public init(arguments: [String], stream: Stream, line: LineSelection) throws {
        if let failure = Self.validationFailure(arguments: arguments) {
            throw DetectorRegistryError.invalidField(
                field: "arguments",
                id: "(version query)",
                reason: failure
            )
        }
        self.arguments = arguments
        self.stream = stream
        self.line = line
    }

    /// The validated explicit standard query used by existing consumers that do
    /// not declare their own version behavior.
    public static let standard: VersionQuerySpecification = {
        // This literal is valid by construction; failure would be a programming error.
        try! VersionQuerySpecification(arguments: ["--version"], stream: .stdout, line: .first)
    }()

    /// A named validation failure, or nil when the argument list is valid.
    static func validationFailure(arguments: [String]) -> String? {
        guard (1...maximumArgumentCount).contains(arguments.count) else {
            return "must contain 1 to \(maximumArgumentCount) arguments"
        }
        var totalBytes = 0
        for (index, argument) in arguments.enumerated() {
            guard !argument.isEmpty else {
                return "argument \(index) must not be empty"
            }
            guard !argument.unicodeScalars.contains(where: { $0.value == 0 }) else {
                return "argument \(index) must not contain NUL"
            }
            let byteCount = argument.utf8.count
            guard byteCount <= maximumArgumentBytes else {
                return "argument \(index) must be at most \(maximumArgumentBytes) UTF-8 bytes"
            }
            totalBytes += byteCount
        }
        guard totalBytes <= maximumTotalBytes else {
            return "arguments must total at most \(maximumTotalBytes) UTF-8 bytes"
        }
        return nil
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case arguments
        case stream
        case line
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let allowed = Set(CodingKeys.allCases.map(\.stringValue))
        if let unknown = try firstUnknownDetectorKey(in: decoder, allowed: allowed) {
            throw DetectorRegistryError.unknownKey(key: unknown, id: "(version query)")
        }

        let arguments = try container.decode([String].self, forKey: .arguments)
        let rawStream = try container.decode(String.self, forKey: .stream)
        guard let stream = Stream(rawValue: rawStream) else {
            throw DetectorRegistryError.invalidField(
                field: "stream",
                id: "(version query)",
                reason: "must be one of stdout, stderr"
            )
        }
        let rawLine = try container.decode(String.self, forKey: .line)
        guard let line = LineSelection(rawValue: rawLine) else {
            throw DetectorRegistryError.invalidField(
                field: "line",
                id: "(version query)",
                reason: "must be one of first, firstNonempty"
            )
        }
        try self.init(arguments: arguments, stream: stream, line: line)
    }
}

/// Metadata validation helpers shared by the registry and direct construction.
enum DetectorMetadataValidation {

    static func validatedHTTPSURL(_ text: String) -> URL? {
        guard !text.isEmpty else { return nil }
        guard !text.unicodeScalars.contains(where: { $0.value == 0 }) else { return nil }
        guard !text.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) })
        else { return nil }
        guard let url = URL(string: text),
              url.scheme?.lowercased() == "https",
              let host = url.host,
              !host.isEmpty,
              url.user == nil,
              url.password == nil
        else {
            return nil
        }
        return url
    }

    static func isValidHTTPSURL(_ url: URL) -> Bool {
        validatedHTTPSURL(url.absoluteString) != nil
    }
}
