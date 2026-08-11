import CompanionCore
import CryptoKit
import Foundation

public enum CharacterFixtureFormat: String, Equatable, Sendable {
    case live2D
    case vrm0
    case vrm1
    case vrma
    case gltf2
}

public enum CharacterFixtureSourceStatus: String, Equatable, Sendable {
    case userSelected
    case environmentProvided
    case syntheticTest
}

public enum CharacterFixtureRightsStatus: String, Equatable, Sendable {
    case unverified
    case userDeclared
    case privateTestingOnly
    case verifiedRedistributable
}

public struct CharacterFixtureDisclosure: Equatable, Sendable {
    public let sourceStatus: CharacterFixtureSourceStatus
    public let rightsStatus: CharacterFixtureRightsStatus
    /// A non-file reference suitable for UI disclosure, such as an HTTPS source page.
    public let sourceReference: String?
    public let rightsNotice: String?

    public init(
        sourceStatus: CharacterFixtureSourceStatus,
        rightsStatus: CharacterFixtureRightsStatus,
        sourceReference: String? = nil,
        rightsNotice: String? = nil
    ) {
        self.sourceStatus = sourceStatus
        self.rightsStatus = rightsStatus
        self.sourceReference = sourceReference
        self.rightsNotice = rightsNotice
    }
}

public enum CharacterFixtureFingerprintExpectation: Equatable, Sendable {
    /// Compute and report a fingerprint for a newly selected user asset.
    case computeOnly
    /// Admit only the exact previously inventoried private fixture.
    case requireSHA256(String)
}

public struct CharacterFixtureAdmissionPolicy: Equatable, Sendable {
    public let fingerprint: CharacterFixtureFingerprintExpectation
    public let expectedFileCount: Int?
    public let maximumBytes: Int
    public let maximumFileCount: Int

    public init(
        fingerprint: CharacterFixtureFingerprintExpectation,
        expectedFileCount: Int? = nil,
        maximumBytes: Int = CharacterPackageLimits.maximumExpandedBytes,
        maximumFileCount: Int = CharacterPackageLimits.maximumFileCount
    ) {
        self.fingerprint = fingerprint
        self.expectedFileCount = expectedFileCount
        self.maximumBytes = maximumBytes
        self.maximumFileCount = maximumFileCount
    }
}

public struct CharacterFixtureCompatibilityResult: Equatable, Sendable {
    public let format: CharacterFixtureFormat
    public let capabilities: CharacterCapabilities
    public let omissions: [String]
    public let fallback: CharacterFallbackReason?
    public let runtimeVerificationRequired: Bool
    public let sourceStatus: CharacterFixtureSourceStatus
    public let rightsStatus: CharacterFixtureRightsStatus
    public let sourceReference: String?
    public let rightsNotice: String?
    public let contentSHA256: String
    public let hashVerified: Bool
    public let expandedBytes: Int
    public let fileCount: Int

    public init(
        format: CharacterFixtureFormat,
        capabilities: CharacterCapabilities,
        omissions: [String],
        fallback: CharacterFallbackReason?,
        runtimeVerificationRequired: Bool,
        sourceStatus: CharacterFixtureSourceStatus,
        rightsStatus: CharacterFixtureRightsStatus,
        sourceReference: String?,
        rightsNotice: String?,
        contentSHA256: String,
        hashVerified: Bool,
        expandedBytes: Int,
        fileCount: Int
    ) {
        self.format = format
        self.capabilities = capabilities
        self.omissions = omissions
        self.fallback = fallback
        self.runtimeVerificationRequired = runtimeVerificationRequired
        self.sourceStatus = sourceStatus
        self.rightsStatus = rightsStatus
        self.sourceReference = sourceReference
        self.rightsNotice = rightsNotice
        self.contentSHA256 = contentSHA256
        self.hashVerified = hashVerified
        self.expandedBytes = expandedBytes
        self.fileCount = fileCount
    }
}

/// A security-admitted local fixture. Admission never activates a character or mutates session state.
public struct AdmittedCharacterFixture: Equatable, Sendable {
    public let rootURL: URL
    public let entryURL: URL
    public let compatibility: CharacterFixtureCompatibilityResult

    public init(
        rootURL: URL,
        entryURL: URL,
        compatibility: CharacterFixtureCompatibilityResult
    ) {
        self.rootURL = rootURL
        self.entryURL = entryURL
        self.compatibility = compatibility
    }
}

public enum CharacterFixtureAdmissionError: Error, Equatable, Sendable {
    case notFileURL
    case relativeEnvironmentPath(String)
    case missingPath(String)
    case notDirectory(String)
    case notRegularFile(String)
    case pathEscape(String)
    case symlink(String)
    case executable(String)
    case unsupportedFileType(String)
    case contentTypeMismatch(String)
    case unreadable(String)
    case tooManyFiles(maximum: Int)
    case contentTooLarge(maximum: Int)
    case invalidExpectedSHA256
    case sha256Mismatch(expected: String, actual: String)
    case fileCountMismatch(expected: Int, actual: Int)
    case privatePathDisclosure
    case fileChanged(String)
    case live2DInspection(JMLive2DModel3InspectionError)
    case vrmInspection(VRMNativeMetadataError)
}

public enum CharacterFixtureEnvironment {
    public static let live2DEntryURL = "JOI_MOBILE_LIVE2D_FIXTURE_ENTRY_URL"
    public static let live2DTreeSHA256 = "JOI_MOBILE_LIVE2D_FIXTURE_TREE_SHA256"
    public static let live2DFileCount = "JOI_MOBILE_LIVE2D_FIXTURE_FILE_COUNT"
    public static let vrmFileURL = "JOI_MOBILE_VRM_FIXTURE_FILE_URL"
    public static let vrmSHA256 = "JOI_MOBILE_VRM_FIXTURE_SHA256"

    public static func fileURL(
        for variable: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> URL? {
        guard let path = environment[variable], !path.isEmpty else { return nil }
        guard NSString(string: path).isAbsolutePath else {
            throw CharacterFixtureAdmissionError.relativeEnvironmentPath(variable)
        }
        return URL(fileURLWithPath: path, isDirectory: false)
    }
}

public struct CharacterFixtureAdmitter: Sendable {
    private let live2DInspector: JMLive2DModel3Inspector
    private let vrmInspector: VRMNativeMetadataInspector

    public init(
        live2DInspector: JMLive2DModel3Inspector = JMLive2DModel3Inspector(),
        vrmInspector: VRMNativeMetadataInspector = VRMNativeMetadataInspector()
    ) {
        self.live2DInspector = live2DInspector
        self.vrmInspector = vrmInspector
    }

    public func admitLive2D(
        entryURL: URL,
        policy: CharacterFixtureAdmissionPolicy,
        disclosure: CharacterFixtureDisclosure
    ) throws -> AdmittedCharacterFixture {
        try validateDisclosure(disclosure)
        guard entryURL.isFileURL else { throw CharacterFixtureAdmissionError.notFileURL }
        guard entryURL.lastPathComponent.lowercased().hasSuffix(".model3.json") else {
            throw CharacterFixtureAdmissionError.unsupportedFileType(entryURL.lastPathComponent)
        }

        let rootURL = entryURL.deletingLastPathComponent().standardizedFileURL
        let inventory = try inventoryLive2DDirectory(rootURL, policy: policy)
        let relativeEntry = try relativePath(of: entryURL.standardizedFileURL, under: rootURL)
        guard let entry = inventory.files.first(where: { $0.relativePath == relativeEntry }) else {
            throw CharacterFixtureAdmissionError.missingPath(relativeEntry)
        }
        let model3Data = try readData(entry.url, expectedBytes: entry.bytes, maximumBytes: policy.maximumBytes)

        let manifest = CharacterPackageManifestV1(
            packageID: "private.fixture.live2d",
            characterID: "private-fixture",
            version: "0",
            displayName: "Private Live2D fixture",
            renderer: .live2d,
            entryPath: relativeEntry,
            locales: ["zh-Hans"],
            assets: inventory.files.map {
                CharacterAssetV1(
                    path: $0.relativePath,
                    mediaType: Self.live2DMediaType(for: $0.relativePath),
                    sha256: $0.sha256
                )
            },
            provenance: CharacterProvenanceV1(
                author: "Private fixture owner",
                license: disclosure.rightsStatus.rawValue,
                source: disclosure.sourceReference
            )
        )

        let inspection: JMLive2DModel3Inspection
        do {
            inspection = try live2DInspector.inspect(model3Data, manifest: manifest)
        } catch let error as JMLive2DModel3InspectionError {
            if case let .undeclaredReference(path) = error, !Self.isSafeRelativePath(path) {
                throw CharacterFixtureAdmissionError.pathEscape(path)
            }
            throw CharacterFixtureAdmissionError.live2DInspection(error)
        }

        var omissions: [String] = []
        if inspection.motionPaths.isEmpty { omissions.append("motion:undeclared") }
        if inspection.expressionPaths.isEmpty { omissions.append("expression:undeclared") }
        if inspection.physicsPath == nil { omissions.append("physics:undeclared") }
        if inspection.posePath == nil { omissions.append("pose:undeclared") }
        if inspection.eyeBlinkParameterIDs.isEmpty { omissions.append("eyeBlink:undeclared") }
        if inspection.lipSyncParameterIDs.isEmpty { omissions.append("lipSync:undeclared") }

        let capabilities = CharacterCapabilities(
            motion: !inspection.motionPaths.isEmpty,
            expression: !inspection.expressionPaths.isEmpty,
            physics: inspection.physicsPath != nil,
            pose: inspection.posePath != nil,
            lookAt: false,
            animation: !inspection.motionPaths.isEmpty,
            lipSync: !inspection.lipSyncParameterIDs.isEmpty
        )
        let compatibility = CharacterFixtureCompatibilityResult(
            format: .live2D,
            capabilities: capabilities,
            omissions: omissions,
            fallback: capabilities.lipSync ? nil : .unsupportedCapability,
            runtimeVerificationRequired: true,
            disclosure: disclosure,
            contentSHA256: inventory.treeSHA256,
            hashVerified: inventory.hashVerified,
            expandedBytes: inventory.expandedBytes,
            fileCount: inventory.files.count
        )
        return AdmittedCharacterFixture(
            rootURL: rootURL,
            entryURL: entry.url,
            compatibility: compatibility
        )
    }

    public func admitVRM(
        fileURL: URL,
        policy: CharacterFixtureAdmissionPolicy,
        disclosure: CharacterFixtureDisclosure
    ) throws -> AdmittedCharacterFixture {
        try validateDisclosure(disclosure)
        guard fileURL.isFileURL else { throw CharacterFixtureAdmissionError.notFileURL }
        guard fileURL.pathExtension.lowercased() == "vrm" else {
            throw CharacterFixtureAdmissionError.unsupportedFileType(fileURL.lastPathComponent)
        }
        let standardizedURL = fileURL.standardizedFileURL
        let record = try inspectSingleFile(standardizedURL, displayPath: standardizedURL.lastPathComponent, policy: policy)
        if let expected = policy.expectedFileCount, expected != 1 {
            throw CharacterFixtureAdmissionError.fileCountMismatch(expected: expected, actual: 1)
        }
        let hashVerified = try verify(record.sha256, against: policy.fingerprint)
        let data = try readData(standardizedURL, expectedBytes: record.bytes, maximumBytes: policy.maximumBytes)
        guard data.count >= 4,
              data[0] == 0x67,
              data[1] == 0x6C,
              data[2] == 0x54,
              data[3] == 0x46 else {
            throw CharacterFixtureAdmissionError.contentTypeMismatch(standardizedURL.lastPathComponent)
        }

        let report: VRMNativeCapabilityReport
        do {
            report = try vrmInspector.inspect(data)
        } catch let error as VRMNativeMetadataError {
            throw CharacterFixtureAdmissionError.vrmInspection(error)
        }
        let summary = Self.vrmCompatibility(report)
        let compatibility = CharacterFixtureCompatibilityResult(
            format: summary.format,
            capabilities: report.characterCapabilities,
            omissions: summary.omissions,
            fallback: summary.supported ? nil : .unsupportedCapability,
            runtimeVerificationRequired: true,
            disclosure: disclosure,
            contentSHA256: record.sha256,
            hashVerified: hashVerified,
            expandedBytes: record.bytes,
            fileCount: 1
        )
        return AdmittedCharacterFixture(
            rootURL: standardizedURL.deletingLastPathComponent(),
            entryURL: standardizedURL,
            compatibility: compatibility
        )
    }

    private func inventoryLive2DDirectory(
        _ rootURL: URL,
        policy: CharacterFixtureAdmissionPolicy
    ) throws -> DirectoryInventory {
        let rootValues = try resourceValues(rootURL, displayPath: ".")
        guard rootValues.isDirectory == true else {
            throw CharacterFixtureAdmissionError.notDirectory(rootURL.lastPathComponent)
        }
        guard rootValues.isSymbolicLink != true else {
            throw CharacterFixtureAdmissionError.symlink(".")
        }

        var files: [FileRecord] = []
        var normalizedPaths = Set<String>()
        try walkDirectory(rootURL, rootURL: rootURL, files: &files, normalizedPaths: &normalizedPaths, policy: policy)
        files.sort { $0.relativePath < $1.relativePath }
        if let expected = policy.expectedFileCount, expected != files.count {
            throw CharacterFixtureAdmissionError.fileCountMismatch(expected: expected, actual: files.count)
        }

        var canonicalManifest = Data()
        var expandedBytes = 0
        for file in files {
            expandedBytes += file.bytes
            canonicalManifest.append(contentsOf: "\(file.sha256)  ./\(file.relativePath)\n".utf8)
        }
        guard expandedBytes <= policy.maximumBytes else {
            throw CharacterFixtureAdmissionError.contentTooLarge(maximum: policy.maximumBytes)
        }
        let treeSHA256 = Self.sha256(canonicalManifest)
        return DirectoryInventory(
            files: files,
            treeSHA256: treeSHA256,
            hashVerified: try verify(treeSHA256, against: policy.fingerprint),
            expandedBytes: expandedBytes
        )
    }

    private func walkDirectory(
        _ directoryURL: URL,
        rootURL: URL,
        files: inout [FileRecord],
        normalizedPaths: inout Set<String>,
        policy: CharacterFixtureAdmissionPolicy
    ) throws {
        let children: [URL]
        do {
            children = try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
                options: []
            ).sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            throw CharacterFixtureAdmissionError.unreadable(try relativePath(of: directoryURL, under: rootURL))
        }

        for child in children {
            let relative = try relativePath(of: child, under: rootURL)
            let values = try resourceValues(child, displayPath: relative)
            if values.isSymbolicLink == true {
                throw CharacterFixtureAdmissionError.symlink(relative)
            }
            if values.isDirectory == true {
                try walkDirectory(
                    child,
                    rootURL: rootURL,
                    files: &files,
                    normalizedPaths: &normalizedPaths,
                    policy: policy
                )
                continue
            }
            guard values.isRegularFile == true else {
                throw CharacterFixtureAdmissionError.notRegularFile(relative)
            }
            guard Self.isAllowedLive2DPath(relative) else {
                throw CharacterFixtureAdmissionError.unsupportedFileType(relative)
            }
            guard normalizedPaths.insert(relative.precomposedStringWithCanonicalMapping.lowercased()).inserted else {
                throw CharacterFixtureAdmissionError.pathEscape(relative)
            }
            guard try !isExecutable(child) else {
                throw CharacterFixtureAdmissionError.executable(relative)
            }
            guard files.count < policy.maximumFileCount else {
                throw CharacterFixtureAdmissionError.tooManyFiles(maximum: policy.maximumFileCount)
            }
            let bytes = values.fileSize ?? 0
            guard bytes <= policy.maximumBytes else {
                throw CharacterFixtureAdmissionError.contentTooLarge(maximum: policy.maximumBytes)
            }
            let digest = try hashFile(child, expectedBytes: bytes, maximumBytes: policy.maximumBytes, displayPath: relative)
            files.append(FileRecord(url: child, relativePath: relative, bytes: digest.bytes, sha256: digest.sha256))
        }
    }

    private func inspectSingleFile(
        _ url: URL,
        displayPath: String,
        policy: CharacterFixtureAdmissionPolicy
    ) throws -> FileRecord {
        let values = try resourceValues(url, displayPath: displayPath)
        guard values.isSymbolicLink != true else { throw CharacterFixtureAdmissionError.symlink(displayPath) }
        guard values.isRegularFile == true else { throw CharacterFixtureAdmissionError.notRegularFile(displayPath) }
        guard try !isExecutable(url) else { throw CharacterFixtureAdmissionError.executable(displayPath) }
        let bytes = values.fileSize ?? 0
        guard bytes <= policy.maximumBytes else {
            throw CharacterFixtureAdmissionError.contentTooLarge(maximum: policy.maximumBytes)
        }
        let digest = try hashFile(url, expectedBytes: bytes, maximumBytes: policy.maximumBytes, displayPath: displayPath)
        return FileRecord(url: url, relativePath: displayPath, bytes: digest.bytes, sha256: digest.sha256)
    }

    private func resourceValues(_ url: URL, displayPath: String) throws -> URLResourceValues {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CharacterFixtureAdmissionError.missingPath(displayPath)
        }
        do {
            return try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        } catch {
            throw CharacterFixtureAdmissionError.unreadable(displayPath)
        }
    }

    private func readData(_ url: URL, expectedBytes: Int, maximumBytes: Int) throws -> Data {
        guard expectedBytes <= maximumBytes else {
            throw CharacterFixtureAdmissionError.contentTooLarge(maximum: maximumBytes)
        }
        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            guard data.count == expectedBytes else {
                throw CharacterFixtureAdmissionError.fileChanged(url.lastPathComponent)
            }
            return data
        } catch let error as CharacterFixtureAdmissionError {
            throw error
        } catch {
            throw CharacterFixtureAdmissionError.unreadable(url.lastPathComponent)
        }
    }

    private func hashFile(
        _ url: URL,
        expectedBytes: Int,
        maximumBytes: Int,
        displayPath: String
    ) throws -> (sha256: String, bytes: Int) {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw CharacterFixtureAdmissionError.unreadable(displayPath)
        }
        defer { try? handle.close() }

        var hasher = SHA256()
        var bytes = 0
        do {
            while let chunk = try handle.read(upToCount: 64 * 1_024), !chunk.isEmpty {
                bytes += chunk.count
                guard bytes <= maximumBytes else {
                    throw CharacterFixtureAdmissionError.contentTooLarge(maximum: maximumBytes)
                }
                hasher.update(data: chunk)
            }
        } catch let error as CharacterFixtureAdmissionError {
            throw error
        } catch {
            throw CharacterFixtureAdmissionError.unreadable(displayPath)
        }
        guard bytes == expectedBytes else { throw CharacterFixtureAdmissionError.fileChanged(displayPath) }
        return (Self.hex(hasher.finalize()), bytes)
    }

    private func verify(
        _ actual: String,
        against expectation: CharacterFixtureFingerprintExpectation
    ) throws -> Bool {
        switch expectation {
        case .computeOnly:
            return false
        case let .requireSHA256(expected):
            let normalized = expected.lowercased()
            guard normalized.count == 64, normalized.allSatisfy({ $0.isHexDigit }) else {
                throw CharacterFixtureAdmissionError.invalidExpectedSHA256
            }
            guard normalized == actual else {
                throw CharacterFixtureAdmissionError.sha256Mismatch(expected: normalized, actual: actual)
            }
            return true
        }
    }

    private func validateDisclosure(_ disclosure: CharacterFixtureDisclosure) throws {
        guard let reference = disclosure.sourceReference else { return }
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        if NSString(string: trimmed).isAbsolutePath || URL(string: trimmed)?.isFileURL == true {
            throw CharacterFixtureAdmissionError.privatePathDisclosure
        }
    }

    private func relativePath(of url: URL, under rootURL: URL) throws -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard path.hasPrefix(prefix) else {
            throw CharacterFixtureAdmissionError.pathEscape(url.lastPathComponent)
        }
        let relative = String(path.dropFirst(prefix.count))
        guard Self.isSafeRelativePath(relative) else {
            throw CharacterFixtureAdmissionError.pathEscape(relative)
        }
        return relative
    }

    private func isExecutable(_ url: URL) throws -> Bool {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
            return permissions & 0o111 != 0
        } catch {
            throw CharacterFixtureAdmissionError.unreadable(url.lastPathComponent)
        }
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains("\\"),
              !path.unicodeScalars.contains(where: { $0.value == 0 }) else {
            return false
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    private static func isAllowedLive2DPath(_ path: String) -> Bool {
        let lowercased = path.lowercased()
        return [
            ".model3.json", ".moc3", ".png", ".physics3.json", ".pose3.json",
            ".cdi3.json", ".motion3.json", ".exp3.json",
        ].contains { lowercased.hasSuffix($0) }
    }

    private static func live2DMediaType(for path: String) -> String {
        let lowercased = path.lowercased()
        if lowercased.hasSuffix(".png") { return "image/png" }
        if lowercased.hasSuffix(".moc3") { return "application/octet-stream" }
        return "application/json"
    }

    private static func vrmCompatibility(
        _ report: VRMNativeCapabilityReport
    ) -> (format: CharacterFixtureFormat, supported: Bool, omissions: [String]) {
        var omissions: [String] = []
        if !report.humanoid { omissions.append("humanoid:undeclared") }
        if !report.mtoon { omissions.append("mtoon:undeclared") }
        if !report.expressions { omissions.append("expression:undeclared") }
        if !report.lookAt { omissions.append("lookAt:undeclared") }
        if !report.constraints { omissions.append("constraints:undeclared") }
        if !report.springBone { omissions.append("springBone:undeclared") }
        if !report.animation { omissions.append("vrma:undeclared") }
        if report.lipSync == .unavailable { omissions.append("lipSync:undeclared") }

        switch report.format {
        case .vrm0:
            return (
                .vrm0,
                report.humanoid && report.mtoon && report.expressions && report.lookAt
                    && report.lipSync == .vrm0VowelBlendShapes,
                omissions
            )
        case .vrm1:
            return (
                .vrm1,
                report.humanoid && report.mtoon && report.expressions && report.lookAt
                    && report.lipSync == .vrm1PhonemeExpressions,
                omissions
            )
        case .vrma:
            return (.vrma, false, omissions)
        case .gltf2:
            return (.gltf2, false, omissions)
        }
    }

    private static func sha256(_ data: Data) -> String {
        hex(SHA256.hash(data: data))
    }

    private static func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}

private struct FileRecord: Sendable {
    let url: URL
    let relativePath: String
    let bytes: Int
    let sha256: String
}

private struct DirectoryInventory: Sendable {
    let files: [FileRecord]
    let treeSHA256: String
    let hashVerified: Bool
    let expandedBytes: Int
}

private extension CharacterFixtureCompatibilityResult {
    init(
        format: CharacterFixtureFormat,
        capabilities: CharacterCapabilities,
        omissions: [String],
        fallback: CharacterFallbackReason?,
        runtimeVerificationRequired: Bool,
        disclosure: CharacterFixtureDisclosure,
        contentSHA256: String,
        hashVerified: Bool,
        expandedBytes: Int,
        fileCount: Int
    ) {
        self.init(
            format: format,
            capabilities: capabilities,
            omissions: omissions,
            fallback: fallback,
            runtimeVerificationRequired: runtimeVerificationRequired,
            sourceStatus: disclosure.sourceStatus,
            rightsStatus: disclosure.rightsStatus,
            sourceReference: disclosure.sourceReference,
            rightsNotice: disclosure.rightsNotice,
            contentSHA256: contentSHA256,
            hashVerified: hashVerified,
            expandedBytes: expandedBytes,
            fileCount: fileCount
        )
    }
}
