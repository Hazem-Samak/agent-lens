// PythonOwnershipProof — shared, read-only helpers for the M14 Python ownership proofs.
//
// This file contains only local filesystem mechanics: bounded descriptor-relative regular-file
// reads, a single-level directory listing, small parsers for pyvenv.cfg/RECORD/shebangs, and
// SHA-256 helpers. It does not launch a process, fetch network data, infer ownership from a path,
// or interpret a uv receipt. The uv receipt shape stays private to UvToolOwnershipProbe.
//
// Every proof file is opened relative to an already observed directory. The directory walk uses
// FileIdentityObserver.openVerifiedDirectory, so a symlinked ancestor fails instead of redirecting
// the read. The file itself is opened with O_NOFOLLOW and O_NONBLOCK and validated as a regular
// file with fstat before any read.

import CryptoKit
import Darwin
import Foundation

/// Dormant outside tests. Invoked immediately before a Python probe's final re-observation so a
/// test can deterministically replace a consumed proof file and exercise negative evidence.
enum PythonOwnershipProbeTestHooks {
    @TaskLocal static var onBeforeFinalRevalidation: (@Sendable () -> Void)?
}

enum PythonProofSupport {

    struct BoundedFile: Equatable, Sendable {
        let data: Data
        let identity: FileIdentity
    }

    /// Observe a directory only through its canonical spelling. A lexical symlink/alias spelling
    /// does not qualify: Python proof paths must not hide a redirect in an ancestor.
    static func observePlainDirectory(_ path: String) -> DirectoryIdentity? {
        guard path.hasPrefix("/"), !path.utf8.contains(0) else { return nil }
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        guard standardized == path else { return nil }
        guard let identity = FileIdentityObserver.observeDirectory(path: path),
              identity.canonicalPath == path
        else { return nil }
        return identity
    }

    static func readFile(
        in directoryPath: String,
        name: String,
        maximumBytes: Int
    ) -> Result<BoundedFile, InstallationOwnershipReason> {
        guard let directory = observePlainDirectory(directoryPath) else {
            return .failure(.unsupportedInstallationLayout)
        }
        return readFile(in: directory, name: name, maximumBytes: maximumBytes)
    }

    static func readFile(
        in directory: DirectoryIdentity,
        name: String,
        maximumBytes: Int
    ) -> Result<BoundedFile, InstallationOwnershipReason> {
        guard isSimpleName(name), maximumBytes > 0 else {
            return .failure(.unsupportedInstallationLayout)
        }
        guard let directoryDescriptor = FileIdentityObserver.openVerifiedDirectory(
            path: directory.canonicalPath,
            expected: directory
        ) else {
            return .failure(.unsupportedInstallationLayout)
        }
        defer { _ = close(directoryDescriptor) }

        var pathInfo = stat()
        let pathStatus = name.withCString {
            fstatat(directoryDescriptor, $0, &pathInfo, AT_SYMLINK_NOFOLLOW)
        }
        if pathStatus != 0 {
            return .failure(errno == ENOENT || errno == ENOTDIR ? .manifestMissing : .manifestUnreadable)
        }
        guard FileIdentityObserver.isRegular(pathInfo.st_mode) else {
            return .failure(.manifestUnreadable)
        }

        let descriptor = name.withCString {
            openat(
                directoryDescriptor,
                $0,
                O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC
            )
        }
        guard descriptor >= 0 else {
            return .failure(errno == ENOENT || errno == ENOTDIR ? .manifestMissing : .manifestUnreadable)
        }
        defer { _ = close(descriptor) }

        var info = stat()
        guard fstat(descriptor, &info) == 0,
              FileIdentityObserver.isRegular(info.st_mode)
        else {
            return .failure(.manifestUnreadable)
        }
        guard info.st_size >= 0, UInt64(info.st_size) <= UInt64(maximumBytes) else {
            return .failure(.manifestTooLarge)
        }

        var data = Data()
        data.reserveCapacity(Int(info.st_size))
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { bytes -> Int in
                guard let base = bytes.baseAddress else { return 0 }
                return Darwin.read(descriptor, base, bytes.count)
            }
            if count < 0 { return .failure(.manifestUnreadable) }
            if count == 0 { break }
            if data.count + count > maximumBytes {
                return .failure(.manifestTooLarge)
            }
            data.append(contentsOf: buffer[0..<count])
        }

        var after = stat()
        guard fstat(descriptor, &after) == 0,
              FileIdentityObserver.fingerprint(after) == FileIdentityObserver.fingerprint(info)
        else {
            return .failure(.proofChanged)
        }

        let canonicalPath = URL(fileURLWithPath: directory.canonicalPath, isDirectory: true)
            .appendingPathComponent(name)
            .path
        let identity = FileIdentity(
            canonicalPath: canonicalPath,
            fingerprint: FileIdentityObserver.fingerprint(info)
        )
        return .success(BoundedFile(data: data, identity: identity))
    }

    /// Stream a single directory level through a verified descriptor and stop at the entry cap.
    /// The cap applies as entries are read; a directory is never materialized in full first.
    static func listNames(
        in directory: DirectoryIdentity,
        maximumEntries: Int
    ) -> [String]? {
        guard maximumEntries > 0,
              let descriptor = FileIdentityObserver.openVerifiedDirectory(
                path: directory.canonicalPath,
                expected: directory
              )
        else { return nil }
        guard let stream = fdopendir(descriptor) else {
            _ = close(descriptor)
            return nil
        }
        defer { _ = closedir(stream) }
        var result: [String] = []
        while true {
            errno = 0
            guard let entry = readdir(stream) else {
                // ENOENT is not a directory-list EOF. Only a NULL with errno 0 is EOF.
                return errno == 0 ? result.sorted() : nil
            }
            let name = withUnsafePointer(to: entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) {
                    String(cString: $0)
                }
            }
            if name == "." || name == ".." { continue }
            guard isSimpleName(name) else { return nil }
            if result.count == maximumEntries { return nil }
            result.append(name)
        }
    }

    enum LexicalNode: Equatable, Sendable {
        case absent
        case present
        case error
    }

    /// Distinguish a genuinely absent path from an unsafe/unreadable lstat error. Callers that
    /// use absence as negative evidence must not treat an error as absence.
    static func lexicalNode(_ path: String) -> LexicalNode {
        guard path.hasPrefix("/"), !path.utf8.contains(0) else { return .error }
        var info = stat()
        let status = path.withCString { lstat($0, &info) }
        if status == 0 { return .present }
        if errno == ENOENT || errno == ENOTDIR { return .absent }
        return .error
    }

    /// Anchored lstat relative to an already observed directory. `.absent` is only ENOENT or
    /// ENOTDIR; any other failure is unsafe/unknown.
    static func lexicalNode(in directory: DirectoryIdentity, name: String) -> LexicalNode {
        guard isSimpleName(name),
              let descriptor = FileIdentityObserver.openVerifiedDirectory(
                path: directory.canonicalPath,
                expected: directory
              )
        else { return .error }
        defer { _ = close(descriptor) }
        var info = stat()
        let status = name.withCString {
            fstatat(descriptor, $0, &info, AT_SYMLINK_NOFOLLOW)
        }
        if status == 0 { return .present }
        if errno == ENOENT || errno == ENOTDIR { return .absent }
        return .error
    }

    /// Positive local Python layout evidence used to avoid running uv on an unrelated standalone
    /// executable. All reads are bounded and anchored; an error is not absence.
    static func hasPythonLayoutEvidence(_ envRoot: DirectoryIdentity) -> Bool {
        let pyvenv = lexicalNode(in: envRoot, name: "pyvenv.cfg")
        if pyvenv == .present { return true }
        if pyvenv == .error { return false }
        let pipx = lexicalNode(in: envRoot, name: "pipx_metadata.json")
        if pipx == .present { return true }
        if pipx == .error { return false }
        let libPath = envRoot.canonicalPath + "/lib"
        guard let lib = observePlainDirectory(libPath),
              let names = listNames(in: lib, maximumEntries: 256)
        else { return false }
        for name in names where name == "python" || name.hasPrefix("python3.") {
            let versionPath = libPath + "/" + name
            guard let versionDir = observePlainDirectory(versionPath),
                  let entries = listNames(in: versionDir, maximumEntries: 256)
            else { continue }
            if entries.contains("site-packages") { return true }
        }
        return false
    }

    /// The frozen R3 public-PyPI evidence is exactly this URL. No port, query, fragment,
    /// credentials, trailing slash, or alternate spelling qualifies.
    static func isExactPublicPyPI(_ text: String) -> Bool {
        text == "https://pypi.org/simple"
    }

    /// Corroborating console-script declaration from entry_points.txt. It never substitutes for
    /// RECORD ownership.
    static func consoleScriptDeclared(_ data: Data, executableName: String) -> Bool {
        guard !data.contains(0), String(data: data, encoding: .utf8) != nil else { return false }
        var inConsoleScripts = false
        for rawLine in String(decoding: data, as: UTF8.self).split(
            whereSeparator: { $0 == "\n" || $0 == "\r" }
        ) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") && line.hasSuffix("]") {
                inConsoleScripts = line == "[console_scripts]"
                continue
            }
            guard inConsoleScripts, !line.isEmpty, !line.hasPrefix("#") else { continue }
            guard let equals = line.firstIndex(of: "=") else { return false }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if key == executableName, !value.isEmpty { return true }
        }
        return false
    }

    struct PythonMetadata: Equatable, Sendable {
        let name: String
        let version: String
        let requiresPython: String?
    }

    static func parseMetadata(_ data: Data) -> PythonMetadata? {
        guard !data.contains(0), String(data: data, encoding: .utf8) != nil else { return nil }
        var name: String?
        var version: String?
        var requiresPython: String?
        let lines = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            // Metadata headers end at the first blank line. Header-like text in the body must
            // never replace or duplicate a header.
            if line.isEmpty { break }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            switch key {
            case "name":
                if name != nil { return nil }
                name = value
            case "version":
                if version != nil { return nil }
                version = value
            case "requires-python":
                if requiresPython != nil { return nil }
                requiresPython = value
            default:
                break
            }
        }
        guard let name, let version, !name.isEmpty, !version.isEmpty else { return nil }
        return PythonMetadata(name: name, version: version, requiresPython: requiresPython)
    }

    struct PythonSitePackages: Equatable, Sendable {
        let path: String
        let identity: DirectoryIdentity
    }

    /// Locate the unique versioned `lib/pythonX.Y/site-packages` below an environment root.
    static func locateVersionedSitePackages(
        envRoot: DirectoryIdentity,
        version: String,
        maximumEntries: Int
    ) -> PythonSitePackages? {
        let libPath = envRoot.canonicalPath + "/lib"
        guard let lib = observePlainDirectory(libPath),
              let names = listNames(in: lib, maximumEntries: maximumEntries)
        else { return nil }
        let components = version.split(separator: ".")
        guard components.count >= 2 else { return nil }
        let expected = "python\(components[0]).\(components[1])"
        guard names.filter({ $0 == expected }).count == 1 else { return nil }
        let versionPath = libPath + "/" + expected
        guard let versionDir = observePlainDirectory(versionPath),
              let entries = listNames(in: versionDir, maximumEntries: maximumEntries),
              entries.contains("site-packages")
        else { return nil }
        let sitePath = versionPath + "/site-packages"
        guard let site = observePlainDirectory(sitePath) else { return nil }
        return PythonSitePackages(path: sitePath, identity: site)
    }

    struct PythonDistribution: Equatable, Sendable {
        let path: String
        let identity: DirectoryIdentity
    }

    /// Locate exactly one matching distribution directory under the verified site-packages.
    /// Enumeration is capped while reading; a competing matching dist-info is ambiguous.
    static func locateDistribution(
        in sitePackages: DirectoryIdentity,
        sitePackagesPath: String,
        packageNames: [String],
        maximumEntries: Int
    ) -> Result<PythonDistribution, InstallationOwnershipReason> {
        guard let names = listNames(in: sitePackages, maximumEntries: maximumEntries) else {
            return .failure(.unsupportedInstallationLayout)
        }
        let normalized = Set(packageNames.map(PythonPackageIdentity.normalized))
        var matches: [String] = []
        for name in names where name.hasSuffix(".dist-info") {
            let stem = String(name.dropLast(".dist-info".count))
            guard let dash = stem.lastIndex(of: "-") else { continue }
            if normalized.contains(PythonPackageIdentity.normalized(String(stem[..<dash]))) {
                matches.append(name)
            }
        }
        guard !matches.isEmpty else { return .failure(.packageNotInstalled) }
        guard matches.count == 1, let name = matches.first else {
            return .failure(.ambiguousOwnership)
        }
        let path = sitePackagesPath + "/" + name
        guard let identity = observePlainDirectory(path) else {
            return .failure(.unsupportedInstallationLayout)
        }
        return .success(PythonDistribution(path: identity.canonicalPath, identity: identity))
    }

    /// Require a RECORD row for the exact selected script and validate size/SHA-256. The pipx
    /// `-E` rewrite is the only normalization permitted, and only when both hash and size match.
    static func verifyRecord(
        recordData: Data,
        scriptData: Data,
        sitePackagesPath: String,
        selectedTarget: String,
        executableName: String,
        allowPipxNormalization: Bool
    ) -> Result<Void, InstallationOwnershipReason> {
        guard URL(fileURLWithPath: selectedTarget).lastPathComponent == executableName,
              let rows = parseRecordCSV(recordData)
        else { return .failure(.manifestInvalid) }
        let expectedPath = "../../../bin/\(executableName)"
        var matching: [[String]] = []
        for row in rows where row.count == 3 && row[0] == expectedPath {
            guard let resolved = resolvedRecordPath(row[0], sitePackagesPath: sitePackagesPath),
                  resolved == selectedTarget else { continue }
            matching.append(row)
        }
        guard !matching.isEmpty else { return .failure(.executableNotDeclared) }
        guard matching.count == 1, let row = matching.first else {
            return .failure(.ambiguousOwnership)
        }
        guard let expectedSize = Int(row[2]), expectedSize >= 0,
              row[2].allSatisfy({ $0.isNumber }),
              let expectedHash = recordSHA256(row[1])
        else { return .failure(.manifestInvalid) }
        if sha256Hex(scriptData) == expectedHash, scriptData.count == expectedSize {
            return .success(())
        }
        if allowPipxNormalization,
           let normalized = normalizedPipxScript(scriptData),
           sha256Hex(normalized) == expectedHash,
           normalized.count == expectedSize {
            return .success(())
        }
        return .failure(.manifestExecutableMismatch)
    }

    /// Re-read a proof file through its anchored parent and compare the exact identity. This is
    /// intentionally no-follow; positive proof rechecks never accept a symlinked replacement.
    static func revalidateFile(
        in directory: DirectoryIdentity,
        name: String,
        identity: FileIdentity,
        maximumBytes: Int
    ) -> Bool {
        switch readFile(in: directory, name: name, maximumBytes: maximumBytes) {
        case .success(let file): return file.identity == identity
        case .failure: return false
        }
    }

    /// Display-safe receipt constraint text. Specifier syntax is not evaluated in B; only a
    /// conservative character set is shown, and names are validated separately.
    static func safeConstraint(_ name: String, _ specifier: String?) -> String {
        guard let specifier,
              specifier.range(
                of: #"^[A-Za-z0-9.*+!=<>,~_-]+$"#,
                options: .regularExpression
              ) != nil
        else { return name }
        return name + specifier
    }

    static func isPythonInterpreterName(_ name: String) -> Bool {
        if name == "python" || name == "python3" { return true }
        guard name.hasPrefix("python3.") else { return false }
        return name.dropFirst("python3.".count).allSatisfy { $0.isNumber }
    }

    static func isSimpleName(_ name: String) -> Bool {
        !name.isEmpty
            && name != "."
            && name != ".."
            && !name.contains("/")
            && !name.utf8.contains(0)
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Decode a PEP 427 `sha256=<urlsafe-base64>` RECORD field into lowercase hex.
    static func recordSHA256(_ value: String) -> String? {
        guard value.hasPrefix("sha256=") else { return nil }
        let encoded = String(value.dropFirst("sha256=".count))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - encoded.count % 4) % 4
        guard let data = Data(base64Encoded: encoded + String(repeating: "=", count: padding)),
              data.count == 32
        else { return nil }
        return data.map { String(format: "%02x", $0) }.joined()
    }

    /// Parse the bounded RECORD CSV into rows. Supports quoted fields, doubled quotes, CRLF and LF.
    /// NUL bytes are rejected rather than silently truncated.
    static func parseRecordCSV(_ data: Data) -> [[String]]? {
        guard !data.contains(0) else { return nil }
        let bytes = [UInt8](data)
        var rows: [[String]] = []
        var row: [String] = []
        var field: [UInt8] = []
        var inQuotes = false
        var quotedField = false
        var fieldClosed = false
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if inQuotes {
                if byte == 0x22 {
                    if index + 1 < bytes.count, bytes[index + 1] == 0x22 {
                        field.append(0x22)
                        index += 2
                        continue
                    }
                    inQuotes = false
                    fieldClosed = true
                } else {
                    field.append(byte)
                }
                index += 1
                continue
            }
            if byte == 0x22 {
                guard field.isEmpty, !quotedField, !fieldClosed else { return nil }
                inQuotes = true
                quotedField = true
                index += 1
                continue
            }
            switch byte {
            case 0x2C:
                guard !inQuotes else { return nil }
                row.append(String(decoding: field, as: UTF8.self))
                field.removeAll(keepingCapacity: true)
                quotedField = false
                fieldClosed = false
            case 0x0A, 0x0D:
                if byte == 0x0D, index + 1 < bytes.count, bytes[index + 1] == 0x0A {
                    index += 1
                }
                row.append(String(decoding: field, as: UTF8.self))
                rows.append(row)
                row.removeAll(keepingCapacity: true)
                field.removeAll(keepingCapacity: true)
                quotedField = false
                fieldClosed = false
            default:
                guard !fieldClosed, byte != 0x0A, byte != 0x0D else { return nil }
                field.append(byte)
            }
            index += 1
        }
        guard !inQuotes else { return nil }
        if !field.isEmpty || !row.isEmpty || quotedField {
            row.append(String(decoding: field, as: UTF8.self))
            rows.append(row)
        }
        return rows
    }

    static func parsePyvenv(_ data: Data) -> [String: String]? {
        guard !data.contains(0),
              String(data: data, encoding: .utf8) != nil
        else { return nil }
        var values: [String: String] = [:]
        for rawLine in String(decoding: data, as: UTF8.self).split(
            whereSeparator: { $0 == "\n" || $0 == "\r" }
        ) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let equals = line.firstIndex(of: "=") else { return nil }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, values[key] == nil else { return nil }
            values[key] = value
        }
        return values.isEmpty ? nil : values
    }

    /// The absolute interpreter token of a console-script shebang, ignoring any arguments.
    static func shebangInterpreter(_ data: Data) -> String? {
        guard !data.contains(0),
              let newline = data.firstIndex(of: 0x0A)
                ?? Optional(data.endIndex),
              newline > data.startIndex
        else { return nil }
        let firstLine = data[..<newline]
        guard firstLine.starts(with: Data("#!".utf8)) else { return nil }
        let body = firstLine.dropFirst(2)
        guard let text = String(data: Data(body), encoding: .utf8) else { return nil }
        let token = text.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init)
        guard let token, token.hasPrefix("/"), !token.contains("\0") else { return nil }
        return token
    }

    /// Return bytes with exactly a terminal ASCII " -E" removed from the first shebang line.
    /// Any other difference returns nil. This is the measured pipx 1.18.11 rewrite.
    static func normalizedPipxScript(_ data: Data) -> Data? {
        let suffix = Data(" -E".utf8)
        guard let newline = data.firstIndex(of: 0x0A) else {
            return data.count >= suffix.count && data.suffix(suffix.count) == suffix
                ? data.dropLast(suffix.count)
                : nil
        }
        let firstLine = data[..<newline]
        guard firstLine.count >= suffix.count, firstLine.suffix(suffix.count) == suffix else {
            return nil
        }
        var result = Data()
        result.append(contentsOf: data[..<data.index(newline, offsetBy: -3)])
        result.append(contentsOf: data[newline...])
        return result
    }

    /// Require an absolute lexical path with no NUL. Used for receipt install-path and shebang
    /// bindings before the live identity observer is consulted.
    static func isAbsolute(_ path: String) -> Bool {
        path.hasPrefix("/") && !path.utf8.contains(0)
    }

    /// The canonical path a RECORD relative path names from the distribution's site-packages.
    static func resolvedRecordPath(
        _ recordPath: String,
        sitePackagesPath: String
    ) -> String? {
        guard !recordPath.isEmpty,
              !recordPath.hasPrefix("/"),
              !recordPath.contains("://"),
              !recordPath.utf8.contains(0)
        else { return nil }
        let base = URL(fileURLWithPath: sitePackagesPath, isDirectory: true)
        let resolved = base.appendingPathComponent(recordPath).standardizedFileURL.path
        guard resolved.hasPrefix("/") else { return nil }
        return resolved
    }
}
