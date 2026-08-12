@_spi(CharacterPackageInstaller) import CompanionCore
import CryptoKit
import Darwin
import Foundation
import ZIPFoundation

struct CharacterStorePaths: Sendable {
    let root: URL
    var characters: URL { root.appendingPathComponent("Characters", isDirectory: true) }
    var staging: URL { characters.appendingPathComponent("Staging", isDirectory: true) }
    var assets: URL { characters.appendingPathComponent("Assets/v1/sha256", isDirectory: true) }
    var catalog: URL { characters.appendingPathComponent("Catalog/v1", isDirectory: true) }
    var deletionJournal: URL { catalog.appendingPathComponent("Deletions", isDirectory: true) }
    var trash: URL { characters.appendingPathComponent("Trash", isDirectory: true) }

    func makeOperationRoot() throws -> URL {
        try CharacterSecureFilesystem.makePrivateDirectory(staging)
        let operation = staging.appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
        try CharacterSecureFilesystem.makePrivateDirectory(operation)
        return operation
    }

    func removeOperationRoot(_ operation: URL) {
        guard operation.deletingLastPathComponent().standardizedFileURL == staging.standardizedFileURL else { return }
        try? FileManager.default.removeItem(at: operation)
    }

    func assetRoot(_ contentID: CharacterContentID) throws -> URL {
        guard let hex = CharacterDigests.hex(from: contentID), hex.count == 64 else {
            throw CharacterPackageImportFailure(.hashMismatch, .recovery)
        }
        return assets.appendingPathComponent(String(hex.prefix(2)), isDirectory: true).appendingPathComponent(hex, isDirectory: true)
    }

    func catalogFile(_ installationID: CharacterInstallationID) -> URL {
        catalog.appendingPathComponent(installationID.rawValue + ".json")
    }
}

struct MaterializedCharacterPackage {
    let packageRoot: URL
    let manifest: CharacterPackageManifestV1
    let legacyReceipt: LegacyManifestReceiptV1?
    let warnings: [String]
    let activationAllowed: Bool
}

struct StoredCharacterRecord: Codable, Sendable {
    let schemaVersion: Int
    let installationID: CharacterInstallationID
    let contentID: CharacterContentID
    let manifest: CharacterPackageManifestV1
    let receipt: CharacterPackageValidationReceiptV1
    let rootIdentity: CharacterRootIdentity
    let legacyReceipt: LegacyManifestReceiptV1?
    let warnings: [String]
    let activationAllowed: Bool
    var available: Bool
}

struct CharacterRootIdentity: Codable, Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
}

struct CharacterActivationLease: Equatable, Sendable {
    let installationID: CharacterInstallationID
    let generation: UUID
    let rootCapabilityID: UUID
    let contentID: CharacterContentID

    func matches(_ handle: ValidatedCharacterPackageHandle) -> Bool {
        installationID == handle.installationID
            && generation == handle.validationGeneration
            && rootCapabilityID == handle.rootCapabilityID
            && contentID == handle.contentID
    }
}

enum CharacterDeletionFaultPoint: String, Sendable {
    case afterJournal
    case afterAssetMove
    case afterCatalogRemoval
    case beforeTrashDeletion
}

private enum CharacterDeletionPhase: String, Codable, Sendable {
    case journaled
    case assetMoved
    case catalogRemoved
}

private struct CharacterDeletionJournal: Codable, Sendable {
    let schemaVersion: Int
    let recoveryKey: String
    let installationID: CharacterInstallationID
    let contentID: CharacterContentID
    let rootIdentity: CharacterRootIdentity
    let trashName: String
    var phase: CharacterDeletionPhase
}

enum CharacterCoding {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}

enum CharacterDigests {
    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func sha256File(
        _ url: URL,
        maximum: Int,
        phase: CharacterPackageImportPhase
    ) throws -> (digest: String, size: UInt64) {
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw CharacterPackageImportFailure(.notFound, phase) }
        defer { Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_nlink == 1,
              info.st_size >= 0,
              info.st_size <= off_t(maximum) else {
            throw CharacterPackageImportFailure(.unsafeArchive, phase)
        }
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        var total: UInt64 = 0
        while true {
            try Task.checkCancellation()
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw CharacterPackageImportFailure(.installFailed, phase, .rolledBack) }
            if count == 0 { break }
            hasher.update(data: Data(buffer.prefix(count)))
            total += UInt64(count)
        }
        guard total == UInt64(info.st_size) else { throw CharacterPackageImportFailure(.sourceChanged, phase) }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return (digest, total)
    }

    static func hex(from contentID: CharacterContentID) -> String? {
        let prefix = "sha256:"
        guard contentID.rawValue.hasPrefix(prefix) else { return nil }
        let value = String(contentID.rawValue.dropFirst(prefix.count))
        return isLowercaseSHA(value) ? value : nil
    }

    static func isLowercaseSHA(_ value: String) -> Bool {
        value.count == 64 && value.utf8.allSatisfy {
            ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102)
        }
    }

    static func validationReceiptDigest(_ receipt: CharacterPackageValidationReceiptV1) -> String {
        let stable = [
            "joi.character.validation-receipt.v1",
            receipt.manifestSHA256,
            String(receipt.expandedBytes),
            String(receipt.fileCount),
        ].joined(separator: "\0")
        return sha256(Data(stable.utf8))
    }
}

enum CharacterSecureFilesystem {
    static func makePrivateDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    static func copyUntrustedSource(
        _ source: URL,
        to destination: URL,
        observer: (@Sendable (Int) -> Void)?
    ) async throws {
        guard source.isFileURL else {
            throw CharacterPackageImportFailure(.notFound, .copySource)
        }
        try makePrivateDirectory(destination.deletingLastPathComponent())
        var linkInfo = stat()
        guard lstat(source.path, &linkInfo) == 0 else {
            throw CharacterPackageImportFailure(.notFound, .copySource)
        }
        guard (linkInfo.st_mode & S_IFMT) == S_IFREG, linkInfo.st_nlink == 1 else {
            throw CharacterPackageImportFailure(.unsafeArchive, .copySource)
        }
        let inputFD = Darwin.open(source.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard inputFD >= 0 else { throw CharacterPackageImportFailure(.sourceChanged, .copySource) }
        defer { Darwin.close(inputFD) }
        var before = stat()
        guard fstat(inputFD, &before) == 0,
              (before.st_mode & S_IFMT) == S_IFREG,
              before.st_nlink == 1,
              before.st_size >= 0,
              before.st_size <= CharacterPackageLimits.maximumArchiveBytes else {
            throw CharacterPackageImportFailure(.unsafeArchive, .copySource)
        }
        let outputFD = Darwin.open(
            destination.path,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            S_IRUSR | S_IWUSR
        )
        guard outputFD >= 0 else { throw CharacterPackageImportFailure(.installFailed, .copySource, .rolledBack) }
        defer { Darwin.close(outputFD) }

        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        var total = 0
        while true {
            try Task.checkCancellation()
            let amount = Darwin.read(inputFD, &buffer, buffer.count)
            guard amount >= 0 else { throw CharacterPackageImportFailure(.sourceChanged, .copySource) }
            if amount == 0 { break }
            total += amount
            guard total <= CharacterPackageLimits.maximumArchiveBytes else {
                throw CharacterPackageImportFailure(.unsafeArchive, .copySource)
            }
            try writeAll(outputFD, bytes: buffer, count: amount, phase: .copySource)
            observer?(total)
        }
        guard fsync(outputFD) == 0 else { throw CharacterPackageImportFailure(.installFailed, .copySource, .rolledBack) }
        var after = stat()
        guard fstat(inputFD, &after) == 0, sameIdentity(before, after), total == Int(before.st_size) else {
            throw CharacterPackageImportFailure(.sourceChanged, .copySource)
        }
        var output = stat()
        guard fstat(outputFD, &output) == 0,
              (output.st_mode & S_IFMT) == S_IFREG,
              output.st_nlink == 1,
              output.st_size == before.st_size else {
            throw CharacterPackageImportFailure(.sourceChanged, .copySource)
        }
    }

    static func copyOwnedFile(_ source: URL, to destination: URL) async throws {
        try makePrivateDirectory(destination.deletingLastPathComponent())
        let input = Darwin.open(source.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard input >= 0 else { throw CharacterPackageImportFailure(.notFound, .validate) }
        defer { Darwin.close(input) }
        var info = stat()
        guard fstat(input, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_nlink == 1 else {
            throw CharacterPackageImportFailure(.unsafeArchive, .validate)
        }
        let output = Darwin.open(destination.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard output >= 0 else { throw CharacterPackageImportFailure(.installFailed, .validate, .rolledBack) }
        defer { Darwin.close(output) }
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            try Task.checkCancellation()
            let count = Darwin.read(input, &buffer, buffer.count)
            guard count >= 0 else { throw CharacterPackageImportFailure(.installFailed, .validate, .rolledBack) }
            if count == 0 { break }
            try writeAll(output, bytes: buffer, count: count, phase: .validate)
        }
        guard fsync(output) == 0 else { throw CharacterPackageImportFailure(.installFailed, .validate, .rolledBack) }
    }

    static func createExtractedFile(
        relativePath: String,
        beneath root: URL,
        body: (_ fileDescriptor: Int32) throws -> Void
    ) throws {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.isEmpty else { throw CharacterPackageImportFailure(.unsafeArchive, .extract) }
        let rootFD = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard rootFD >= 0 else { throw CharacterPackageImportFailure(.installFailed, .extract, .rolledBack) }
        var directoryFD = rootFD
        defer {
            if directoryFD != rootFD { Darwin.close(directoryFD) }
            Darwin.close(rootFD)
        }
        for component in components.dropLast() {
            if mkdirat(directoryFD, component, S_IRWXU) != 0 && errno != EEXIST {
                throw CharacterPackageImportFailure(.installFailed, .extract, .rolledBack)
            }
            let next = openat(directoryFD, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else { throw CharacterPackageImportFailure(.unsafeArchive, .extract) }
            if directoryFD != rootFD { Darwin.close(directoryFD) }
            directoryFD = next
        }
        guard let name = components.last else { throw CharacterPackageImportFailure(.unsafeArchive, .extract) }
        let fileFD = openat(directoryFD, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard fileFD >= 0 else { throw CharacterPackageImportFailure(.unsafeArchive, .extract) }
        defer { Darwin.close(fileFD) }
        try body(fileFD)
        guard fsync(fileFD) == 0 else { throw CharacterPackageImportFailure(.installFailed, .extract, .rolledBack) }
        var info = stat()
        guard fstat(fileFD, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_nlink == 1 else {
            throw CharacterPackageImportFailure(.unsafeArchive, .extract)
        }
    }

    static func writeAll(_ fd: Int32, bytes: [UInt8], count: Int, phase: CharacterPackageImportPhase) throws {
        var written = 0
        while written < count {
            let result = bytes.withUnsafeBytes { pointer in
                Darwin.write(fd, pointer.baseAddress!.advanced(by: written), count - written)
            }
            guard result > 0 else { throw CharacterPackageImportFailure(.installFailed, phase, .rolledBack) }
            written += result
        }
    }

    static func writeAll(_ fd: Int32, data: Data, phase: CharacterPackageImportPhase) throws {
        var written = 0
        while written < data.count {
            let result = data.withUnsafeBytes { pointer in
                Darwin.write(fd, pointer.baseAddress!.advanced(by: written), data.count - written)
            }
            guard result > 0 else { throw CharacterPackageImportFailure(.installFailed, phase, .rolledBack) }
            written += result
        }
    }

    private static func sameIdentity(_ lhs: stat, _ rhs: stat) -> Bool {
        lhs.st_dev == rhs.st_dev
            && lhs.st_ino == rhs.st_ino
            && lhs.st_size == rhs.st_size
            && lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec
            && lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec
            && lhs.st_ctimespec.tv_sec == rhs.st_ctimespec.tv_sec
            && lhs.st_ctimespec.tv_nsec == rhs.st_ctimespec.tv_nsec
    }
}

enum CharacterPackageMaterializer {
    static func rawVRM(from source: URL, operation: URL) async throws -> MaterializedCharacterPackage {
        try Task.checkCancellation()
        try CharacterMediaValidator.validate(url: source, path: "model.vrm", declaredMediaType: "model/gltf-binary")
        let packageRoot = operation.appendingPathComponent("package", isDirectory: true)
        try CharacterSecureFilesystem.makePrivateDirectory(packageRoot)
        let entry = "model.vrm"
        try await CharacterSecureFilesystem.copyOwnedFile(source, to: packageRoot.appendingPathComponent(entry))
        let sourceDigest = try CharacterDigests.sha256File(source, maximum: CharacterPackageLimits.maximumFileBytes, phase: .validate).digest
        let asset = CharacterAssetV1(path: entry, mediaType: "model/gltf-binary", sha256: sourceDigest)
        let identity = CharacterDigests.sha256(Data("joi.raw-vrm.v1\0".utf8) + Data(sourceDigest.utf8))
        let manifest = CharacterPackageManifestV1(
            packageID: "local.raw-vrm." + String(identity.prefix(24)),
            characterID: "local.raw-vrm." + String(identity.prefix(24)),
            version: "1.0.0",
            displayName: "导入的 VRM 角色",
            renderer: .vrm,
            entryPath: entry,
            locales: ["zh-Hans"],
            assets: [asset],
            provenance: CharacterProvenanceV1(author: "本地导入", license: "权利状态未验证")
        )
        try writeCanonicalManifest(manifest, to: packageRoot)
        _ = try CharacterManifestValidator.validateCanonical(at: packageRoot)
        return MaterializedCharacterPackage(
            packageRoot: packageRoot,
            manifest: manifest,
            legacyReceipt: nil,
            warnings: ["rights_unverified"],
            activationAllowed: false
        )
    }

    static func joiArchive(from source: URL, operation: URL) async throws -> MaterializedCharacterPackage {
        let extracted = try await extract(source, operation: operation)
        let packageRoot = try locateManifestRoot(extracted.root, files: extracted.files)
        let decoded = try CharacterManifestValidator.decodeAndAdapt(at: packageRoot)
        let validated = try CharacterManifestValidator.validateCanonical(at: packageRoot, expected: decoded.manifest)
        let activationAllowed = decoded.legacyReceipt == nil && rightsAreExplicit(validated.provenance)
        return MaterializedCharacterPackage(
            packageRoot: packageRoot,
            manifest: validated,
            legacyReceipt: decoded.legacyReceipt,
            warnings: decoded.warnings + (activationAllowed ? [] : ["rights_unverified"]),
            activationAllowed: activationAllowed
        )
    }

    static func live2DArchive(from source: URL, operation: URL) async throws -> MaterializedCharacterPackage {
        let extracted = try await extract(source, operation: operation)
        guard !extracted.files.contains("manifest.json") else {
            throw CharacterPackageImportFailure(.invalidManifest, .validate)
        }
        let models = extracted.files.filter { $0.lowercased().hasSuffix(".model3.json") }
        guard models.count == 1, let modelPath = models.first else {
            throw CharacterPackageImportFailure(.invalidRenderer, .validate)
        }
        let base = (modelPath as NSString).deletingLastPathComponent
        let packageRoot = base.isEmpty ? extracted.root : extracted.root.appendingPathComponent(base, isDirectory: true)
        let entry = (modelPath as NSString).lastPathComponent
        guard base.isEmpty || extracted.files.allSatisfy({ $0.hasPrefix(base + "/") }) else {
            throw CharacterPackageImportFailure(.unsafeArchive, .validate)
        }
        let modelData = try readBounded(packageRoot.appendingPathComponent(entry), maximum: 4 * 1024 * 1024, phase: .validate)
        let references = try Live2DClosure.references(modelData)
        let closure = Set([entry] + references)
        let relativeFiles = Set(extracted.files.compactMap { path -> String? in
            if base.isEmpty { return path }
            let prefix = base + "/"
            return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : nil
        })
        guard closure == relativeFiles else {
            throw CharacterPackageImportFailure(.unsafeArchive, .validate)
        }
        var assets: [CharacterAssetV1] = []
        for path in closure.sorted() {
            try Task.checkCancellation()
            try CharacterMediaValidator.validate(url: packageRoot.appendingPathComponent(path), path: path, declaredMediaType: CharacterMediaValidator.mediaType(for: path))
            let digest = try CharacterDigests.sha256File(packageRoot.appendingPathComponent(path), maximum: CharacterPackageLimits.maximumFileBytes, phase: .validate).digest
            assets.append(CharacterAssetV1(path: path, mediaType: CharacterMediaValidator.mediaType(for: path), sha256: digest))
        }
        let sourceIdentity = CharacterDigests.sha256(modelData)
        let manifest = CharacterPackageManifestV1(
            packageID: "local.live2d." + String(sourceIdentity.prefix(24)),
            characterID: "local.live2d." + String(sourceIdentity.prefix(24)),
            version: "1.0.0",
            displayName: "导入的 Live2D 角色",
            renderer: .live2d,
            entryPath: entry,
            locales: ["zh-Hans"],
            assets: assets,
            provenance: CharacterProvenanceV1(author: "本地导入", license: "权利状态未验证")
        )
        try writeCanonicalManifest(manifest, to: packageRoot)
        _ = try CharacterManifestValidator.validateCanonical(at: packageRoot)
        return MaterializedCharacterPackage(
            packageRoot: packageRoot,
            manifest: manifest,
            legacyReceipt: nil,
            warnings: ["rights_unverified"],
            activationAllowed: false
        )
    }

    private static func extract(_ source: URL, operation: URL) async throws -> (root: URL, files: Set<String>) {
        let plan = try RestrictedZIPPreflight.plan(source)
        try Task.checkCancellation()
        let output = operation.appendingPathComponent("extracted", isDirectory: true)
        try CharacterSecureFilesystem.makePrivateDirectory(output)
        let archive: Archive
        do { archive = try Archive(url: source, accessMode: .read) }
        catch { throw CharacterPackageImportFailure(.malformedArchive, .extract) }
        var aggregate: UInt64 = 0
        for planned in plan.files {
            try Task.checkCancellation()
            guard let entry = archive[planned.originalPath], entry.type == .file,
                  UInt64(entry.compressedSize) == planned.compressedSize,
                  UInt64(entry.uncompressedSize) == planned.uncompressedSize,
                  entry.checksum == planned.crc32 else {
                throw CharacterPackageImportFailure(.malformedArchive, .extract)
            }
            var entryBytes: UInt64 = 0
            var prefix = Data()
            var crc = CharacterCRC32()
            try CharacterSecureFilesystem.createExtractedFile(relativePath: planned.normalizedPath, beneath: output) { fd in
                do {
                    _ = try archive.extract(entry, bufferSize: 64 * 1024) { chunk in
                        try Task.checkCancellation()
                        entryBytes = try RestrictedZIPPolicy.adding(entryBytes, UInt64(chunk.count), limit: planned.uncompressedSize)
                        aggregate = try RestrictedZIPPolicy.adding(aggregate, UInt64(chunk.count), limit: UInt64(CharacterPackageLimits.maximumExpandedBytes))
                        if prefix.count < 512 { prefix.append(chunk.prefix(512 - prefix.count)) }
                        crc.update(chunk)
                        try CharacterSecureFilesystem.writeAll(fd, data: chunk, phase: .extract)
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch let failure as CharacterPackageImportFailure {
                    throw failure
                } catch {
                    throw CharacterPackageImportFailure(.malformedArchive, .extract)
                }
                guard entryBytes == planned.uncompressedSize, crc.finalized == planned.crc32 else {
                    throw CharacterPackageImportFailure(.malformedArchive, .extract)
                }
                if CharacterMediaValidator.looksLikeNestedArchive(prefix, path: planned.normalizedPath) {
                    throw CharacterPackageImportFailure(.unsafeArchive, .extract)
                }
            }
        }
        guard aggregate == plan.expandedBytes else {
            throw CharacterPackageImportFailure(.malformedArchive, .extract)
        }
        return (output, Set(plan.files.map(\.normalizedPath)))
    }

    private static func locateManifestRoot(_ extracted: URL, files: Set<String>) throws -> URL {
        if files.contains("manifest.json") { return extracted }
        let candidates = files.filter { $0.hasSuffix("/manifest.json") }
        guard candidates.count == 1, let candidate = candidates.first else {
            throw CharacterPackageImportFailure(.invalidManifest, .validate)
        }
        let wrapper = String(candidate.dropLast("/manifest.json".count))
        guard !wrapper.contains("/") && files.allSatisfy({ $0.hasPrefix(wrapper + "/") }) else {
            throw CharacterPackageImportFailure(.invalidManifest, .validate)
        }
        return extracted.appendingPathComponent(wrapper, isDirectory: true)
    }

    private static func rightsAreExplicit(_ provenance: CharacterProvenanceV1) -> Bool {
        let value = provenance.license.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !value.isEmpty && !value.contains("unknown") && !value.contains("unverified") && !value.contains("未验证")
    }

    private static func writeCanonicalManifest(_ manifest: CharacterPackageManifestV1, to root: URL) throws {
        let data = try CharacterCoding.encoder.encode(manifest)
        let url = root.appendingPathComponent("manifest.json")
        guard FileManager.default.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CharacterPackageImportFailure(.installFailed, .validate, .rolledBack)
        }
    }

    static func readBounded(_ url: URL, maximum: Int, phase: CharacterPackageImportPhase) throws -> Data {
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw CharacterPackageImportFailure(.notFound, phase) }
        defer { Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_nlink == 1,
              info.st_size >= 0,
              info.st_size <= maximum else {
            throw CharacterPackageImportFailure(.unsafeArchive, phase)
        }
        var result = Data()
        result.reserveCapacity(Int(info.st_size))
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            try Task.checkCancellation()
            let count = Darwin.read(fd, &buffer, buffer.count)
            guard count >= 0 else { throw CharacterPackageImportFailure(.installFailed, phase, .rolledBack) }
            if count == 0 { break }
            guard result.count <= maximum - count else { throw CharacterPackageImportFailure(.unsafeArchive, phase) }
            result.append(contentsOf: buffer.prefix(count))
        }
        return result
    }

    static func readRange(
        _ url: URL,
        offset: Int,
        count: Int,
        maximumFileBytes: Int = CharacterPackageLimits.maximumFileBytes,
        phase: CharacterPackageImportPhase
    ) throws -> (data: Data, fileSize: Int) {
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw CharacterPackageImportFailure(.notFound, phase) }
        defer { Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_nlink == 1,
              info.st_size >= 0,
              info.st_size <= off_t(maximumFileBytes),
              offset >= 0, count >= 0,
              offset <= Int(info.st_size), count <= Int(info.st_size) - offset else {
            throw CharacterPackageImportFailure(.unsafeArchive, phase)
        }
        var data = Data(count: count)
        var completed = 0
        try data.withUnsafeMutableBytes { buffer in
            while completed < count {
                try Task.checkCancellation()
                guard let base = buffer.baseAddress else { throw CharacterPackageImportFailure(.unsafeArchive, phase) }
                let amount = Darwin.pread(fd, base.advanced(by: completed), count - completed, off_t(offset + completed))
                if amount < 0, errno == EINTR { continue }
                guard amount > 0 else { throw CharacterPackageImportFailure(.installFailed, phase, .rolledBack) }
                completed += amount
            }
        }
        return (data, Int(info.st_size))
    }
}

enum CharacterContentStore {
    static func seal(
        _ materialized: MaterializedCharacterPackage,
        operation: URL,
        paths: CharacterStorePaths
    ) throws -> (
        contentID: CharacterContentID,
        manifest: CharacterPackageManifestV1,
        receipt: CharacterPackageValidationReceiptV1,
        rootIdentity: CharacterRootIdentity,
        newlyCreated: Bool
    ) {
        try Task.checkCancellation()
        let verified = try CharacterTreeVerifier.verifyPackage(at: materialized.packageRoot, expected: materialized.manifest)
        let contentID = try CharacterTreeVerifier.contentID(at: materialized.packageRoot)
        let destination = try paths.assetRoot(contentID)
        try CharacterSecureFilesystem.makePrivateDirectory(destination.deletingLastPathComponent())
        var created = false
        do {
            if !FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.moveItem(at: materialized.packageRoot, to: destination)
                created = true
                try sealPermissions(destination)
            }
            let reopened = try CharacterTreeVerifier.verifyPackage(at: destination, expected: verified.manifest)
            let reopenedID = try CharacterTreeVerifier.contentID(at: destination)
            guard reopenedID == contentID else { throw CharacterPackageImportFailure(.hashMismatch, .seal) }
            return (contentID, reopened.manifest, reopened.receipt, try CharacterTreeVerifier.rootIdentity(at: destination), created)
        } catch {
            if created { removeOwnedTree(destination) }
            throw error
        }
    }

    static func persist(_ record: StoredCharacterRecord, paths: CharacterStorePaths) throws {
        try CharacterSecureFilesystem.makePrivateDirectory(paths.catalog)
        let data = try CharacterCoding.encoder.encode(record)
        let destination = paths.catalogFile(record.installationID)
        let temporary = paths.catalog.appendingPathComponent("." + UUID().uuidString + ".tmp")
        guard FileManager.default.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CharacterPackageImportFailure(.installFailed, .install, .rolledBack)
        }
        do {
            let fileFD = Darwin.open(temporary.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
            guard fileFD >= 0 else {
                throw CharacterPackageImportFailure(.installFailed, .install, .rolledBack)
            }
            let fileSyncResult = Darwin.fsync(fileFD)
            Darwin.close(fileFD)
            guard fileSyncResult == 0 else {
                throw CharacterPackageImportFailure(.installFailed, .install, .rolledBack)
            }
            if rename(temporary.path, destination.path) != 0 {
                throw CharacterPackageImportFailure(.installFailed, .install, .rolledBack)
            }
            try syncDirectory(paths.catalog, phase: .install)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    static func removeCatalog(_ record: StoredCharacterRecord, paths: CharacterStorePaths) throws {
        let file = paths.catalogFile(record.installationID)
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw CharacterPackageImportFailure(.notFound, .removal)
        }
        do {
            try FileManager.default.removeItem(at: file)
            try syncDirectory(paths.catalog, phase: .removal)
        }
        catch { throw CharacterPackageImportFailure(.installFailed, .removal) }
    }

    static func removeLastReference(
        _ record: StoredCharacterRecord,
        paths: CharacterStorePaths,
        faultInjector: (@Sendable (CharacterDeletionFaultPoint) -> Bool)?
    ) throws {
        let recoveryKey = "delete-" + UUID().uuidString.lowercased()
        let journal = CharacterDeletionJournal(
            schemaVersion: 1,
            recoveryKey: recoveryKey,
            installationID: record.installationID,
            contentID: record.contentID,
            rootIdentity: record.rootIdentity,
            trashName: recoveryKey,
            phase: .journaled
        )
        do {
            try persistDeletion(journal, paths: paths)
            try resumeDeletion(journal, paths: paths, faultInjector: faultInjector)
        } catch let failure as CharacterPackageImportFailure where failure.code == .recoveryRequired {
            throw failure
        } catch {
            throw CharacterPackageImportFailure(.recoveryRequired, .removal, recoveryKey: recoveryKey)
        }
    }

    static func retryPendingRemoval(
        _ installationID: CharacterInstallationID,
        paths: CharacterStorePaths
    ) throws -> Bool {
        guard let journal = deletionJournals(paths: paths).first(where: { $0.installationID == installationID }) else {
            return false
        }
        do {
            try resumeDeletion(journal, paths: paths, faultInjector: nil)
            return true
        } catch {
            throw CharacterPackageImportFailure(.recoveryRequired, .removal, recoveryKey: journal.recoveryKey)
        }
    }

    static func recoverPendingDeletions(paths: CharacterStorePaths) {
        for journal in deletionJournals(paths: paths) {
            try? resumeDeletion(journal, paths: paths, faultInjector: nil)
        }
    }

    static func removeUnjournaledTrash(paths: CharacterStorePaths) {
        let retained = Set(deletionJournals(paths: paths).map(\.trashName))
        guard let children = try? FileManager.default.contentsOfDirectory(at: paths.trash, includingPropertiesForKeys: nil) else { return }
        for child in children where !retained.contains(child.lastPathComponent) {
            removeOwnedTree(child)
        }
    }

    private static func resumeDeletion(
        _ initial: CharacterDeletionJournal,
        paths: CharacterStorePaths,
        faultInjector: (@Sendable (CharacterDeletionFaultPoint) -> Bool)?
    ) throws {
        var journal = initial
        let asset = try paths.assetRoot(journal.contentID)
        let trash = paths.trash.appendingPathComponent(journal.trashName, isDirectory: true)
        if journal.phase == .journaled {
            if faultInjector?(.afterJournal) == true { throw recovery(journal) }
            if FileManager.default.fileExists(atPath: asset.path) {
                guard try CharacterTreeVerifier.rootIdentity(at: asset) == journal.rootIdentity else { throw recovery(journal) }
                try CharacterSecureFilesystem.makePrivateDirectory(paths.trash)
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: asset.path)
                guard Darwin.rename(asset.path, trash.path) == 0 else { throw recovery(journal) }
                try syncDirectory(asset.deletingLastPathComponent(), phase: .removal)
                try syncDirectory(paths.trash, phase: .removal)
            } else if !FileManager.default.fileExists(atPath: trash.path) {
                throw recovery(journal)
            }
            journal.phase = .assetMoved
            try persistDeletion(journal, paths: paths)
        }
        if journal.phase == .assetMoved {
            if faultInjector?(.afterAssetMove) == true { throw recovery(journal) }
            let catalog = paths.catalogFile(journal.installationID)
            if FileManager.default.fileExists(atPath: catalog.path) {
                try FileManager.default.removeItem(at: catalog)
                try syncDirectory(paths.catalog, phase: .removal)
            }
            journal.phase = .catalogRemoved
            try persistDeletion(journal, paths: paths)
        }
        if journal.phase == .catalogRemoved {
            if faultInjector?(.afterCatalogRemoval) == true || faultInjector?(.beforeTrashDeletion) == true {
                throw recovery(journal)
            }
            if FileManager.default.fileExists(atPath: trash.path) {
                guard try CharacterTreeVerifier.rootIdentity(at: trash) == journal.rootIdentity else { throw recovery(journal) }
                makeWritableForDeletion(trash)
                do { try FileManager.default.removeItem(at: trash) }
                catch { throw recovery(journal) }
                guard !FileManager.default.fileExists(atPath: trash.path) else { throw recovery(journal) }
                try syncDirectory(paths.trash, phase: .removal)
            }
            let journalFile = deletionFile(journal.recoveryKey, paths: paths)
            if FileManager.default.fileExists(atPath: journalFile.path) {
                try FileManager.default.removeItem(at: journalFile)
                try syncDirectory(paths.deletionJournal, phase: .removal)
            }
        }
    }

    private static func persistDeletion(_ journal: CharacterDeletionJournal, paths: CharacterStorePaths) throws {
        try CharacterSecureFilesystem.makePrivateDirectory(paths.deletionJournal)
        let data = try CharacterCoding.encoder.encode(journal)
        let destination = deletionFile(journal.recoveryKey, paths: paths)
        let temporary = paths.deletionJournal.appendingPathComponent("." + UUID().uuidString + ".tmp")
        let fd = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw recovery(journal) }
        var closed = false
        defer {
            if !closed { Darwin.close(fd) }
            try? FileManager.default.removeItem(at: temporary)
        }
        try CharacterSecureFilesystem.writeAll(fd, data: data, phase: .removal)
        guard fsync(fd) == 0 else { throw recovery(journal) }
        Darwin.close(fd)
        closed = true
        guard Darwin.rename(temporary.path, destination.path) == 0 else { throw recovery(journal) }
        try syncDirectory(paths.deletionJournal, phase: .removal)
    }

    private static func deletionJournals(paths: CharacterStorePaths) -> [CharacterDeletionJournal] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: paths.deletionJournal, includingPropertiesForKeys: nil) else { return [] }
        return files.compactMap { file in
            guard file.pathExtension == "json",
                  let data = try? CharacterPackageMaterializer.readBounded(file, maximum: 64 * 1024, phase: .recovery),
                  let journal = try? CharacterCoding.decoder.decode(CharacterDeletionJournal.self, from: data),
                  journal.schemaVersion == 1,
                  file.deletingPathExtension().lastPathComponent == journal.recoveryKey else { return nil }
            return journal
        }
    }

    private static func deletionFile(_ recoveryKey: String, paths: CharacterStorePaths) -> URL {
        paths.deletionJournal.appendingPathComponent(recoveryKey + ".json")
    }

    private static func recovery(_ journal: CharacterDeletionJournal) -> CharacterPackageImportFailure {
        CharacterPackageImportFailure(.recoveryRequired, .removal, recoveryKey: journal.recoveryKey)
    }

    private static func syncDirectory(_ directory: URL, phase: CharacterPackageImportPhase) throws {
        let fd = Darwin.open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw CharacterPackageImportFailure(.installFailed, phase, .rolledBack) }
        defer { Darwin.close(fd) }
        guard Darwin.fsync(fd) == 0 else {
            throw CharacterPackageImportFailure(.installFailed, phase, .rolledBack)
        }
    }

    static func trashUnreferencedContent(_ contentID: CharacterContentID, paths: CharacterStorePaths) throws {
        let asset = try paths.assetRoot(contentID)
        guard FileManager.default.fileExists(atPath: asset.path) else { return }
        try CharacterSecureFilesystem.makePrivateDirectory(paths.trash)
        let trash = paths.trash.appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
        // Logical removal (catalog deletion) is already committed. Physical
        // cleanup is retryable: a rename failure leaves an orphan that startup
        // recovery removes, while a deletion failure leaves an item in Trash.
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: asset.path)
        guard Darwin.rename(asset.path, trash.path) == 0 else { return }
        removeOwnedTree(trash)
    }

    private static func makeWritableForDeletion(_ root: URL) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        if let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey]) {
            var directories = [root]
            while let item = enumerator.nextObject() as? URL {
                if (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    directories.append(item)
                } else {
                    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: item.path)
                }
            }
            for directory in directories.reversed() {
                try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            }
        }
    }

    static func removeOwnedTree(_ root: URL) {
        makeWritableForDeletion(root)
        try? FileManager.default.removeItem(at: root)
    }

    private static func sealPermissions(_ root: URL) throws {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) else { throw CharacterPackageImportFailure(.installFailed, .seal, .rolledBack) }
        var directories = [root]
        while let item = enumerator.nextObject() as? URL {
            let values = try item.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw CharacterPackageImportFailure(.unsafeArchive, .seal) }
            if values.isRegularFile == true {
                try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: item.path)
            } else if values.isDirectory == true {
                directories.append(item)
            } else {
                throw CharacterPackageImportFailure(.unsafeArchive, .seal)
            }
        }
        for directory in directories.reversed() {
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        }
    }
}

private struct CharacterCRC32 {
    private var value: UInt32 = 0xffff_ffff

    mutating func update(_ data: Data) {
        for byte in data {
            value ^= UInt32(byte)
            for _ in 0..<8 {
                value = (value & 1) == 1 ? (value >> 1) ^ 0xedb8_8320 : value >> 1
            }
        }
    }

    var finalized: UInt32 { value ^ 0xffff_ffff }
}

enum CharacterStoreRecovery {
    static func bootstrap(paths: CharacterStorePaths) -> [CharacterInstallationID: StoredCharacterRecord] {
        try? CharacterSecureFilesystem.makePrivateDirectory(paths.staging)
        try? CharacterSecureFilesystem.makePrivateDirectory(paths.catalog)
        try? CharacterSecureFilesystem.makePrivateDirectory(paths.trash)
        try? CharacterSecureFilesystem.makePrivateDirectory(paths.deletionJournal)
        CharacterContentStore.recoverPendingDeletions(paths: paths)
        CharacterContentStore.removeUnjournaledTrash(paths: paths)
        removeChildren(of: paths.staging)
        var records: [CharacterInstallationID: StoredCharacterRecord] = [:]
        if let files = try? FileManager.default.contentsOfDirectory(at: paths.catalog, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "json" {
                guard let data = try? CharacterPackageMaterializer.readBounded(file, maximum: 512 * 1024, phase: .recovery),
                      var record = try? CharacterCoding.decoder.decode(StoredCharacterRecord.self, from: data),
                      record.schemaVersion == 1,
                      file.deletingPathExtension().lastPathComponent == record.installationID.rawValue else {
                    continue
                }
                record.available = (try? CharacterTreeVerifier.verify(record: record, paths: paths)) != nil
                records[record.installationID] = record
                try? CharacterContentStore.persist(record, paths: paths)
            }
        }
        removeOrphanAssets(paths: paths, referenced: Set(records.values.map(\.contentID)))
        return records
    }

    private static func removeChildren(of directory: URL) {
        guard let children = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for child in children { CharacterContentStore.removeOwnedTree(child) }
    }

    private static func removeOrphanAssets(paths: CharacterStorePaths, referenced: Set<CharacterContentID>) {
        let expected = Set(referenced.compactMap { try? paths.assetRoot($0).standardizedFileURL.path })
        guard let prefixes = try? FileManager.default.contentsOfDirectory(at: paths.assets, includingPropertiesForKeys: nil) else { return }
        for prefix in prefixes {
            guard let roots = try? FileManager.default.contentsOfDirectory(at: prefix, includingPropertiesForKeys: nil) else { continue }
            for root in roots where !expected.contains(root.standardizedFileURL.path) {
                CharacterContentStore.removeOwnedTree(root)
            }
            if (try? FileManager.default.contentsOfDirectory(atPath: prefix.path).isEmpty) == true {
                try? FileManager.default.removeItem(at: prefix)
            }
        }
    }
}
