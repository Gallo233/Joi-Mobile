import CompanionCore
import Darwin
import Foundation

struct RestrictedZIPPlan: Sendable {
    struct File: Sendable {
        let originalPath: String
        let normalizedPath: String
        let compressedSize: UInt64
        let uncompressedSize: UInt64
        let crc32: UInt32
    }

    let files: [File]
    let expandedBytes: UInt64
}

enum RestrictedZIPPolicy {
    static func adding(_ lhs: UInt64, _ rhs: UInt64, limit: UInt64) throws -> UInt64 {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow, value <= limit else {
            throw CharacterPackageImportFailure(.unsafeArchive, .preflight)
        }
        return value
    }

    static func normalizedPath(_ path: String) throws -> String {
        guard !path.isEmpty,
              path.utf8.count <= 512,
              !path.hasPrefix("/"),
              !path.hasPrefix("\\"),
              !path.contains("\\"),
              !path.contains(":"),
              !path.unicodeScalars.contains(where: { $0.value == 0 || $0.value < 0x20 || $0.value == 0x7f }) else {
            throw CharacterPackageImportFailure(.unsafeArchive, .preflight)
        }
        let isDirectory = path.hasSuffix("/")
        let body = isDirectory ? String(path.dropLast()) : path
        let parts = body.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.isEmpty,
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw CharacterPackageImportFailure(.unsafeArchive, .preflight)
        }
        let normalized = body.precomposedStringWithCanonicalMapping
        guard normalized.utf8.count <= 512 else {
            throw CharacterPackageImportFailure(.unsafeArchive, .preflight)
        }
        return normalized + (isDirectory ? "/" : "")
    }

    /// Apple archiver bookkeeping: the resource-fork sidecar tree and the folder
    /// metadata file. Matched on the normalized path so a nested `.DS_Store` is
    /// caught too.
    static func isAppleSidecar(_ normalizedPath: String) -> Bool {
        if normalizedPath == "__MACOSX" || normalizedPath.hasPrefix("__MACOSX/") { return true }
        return normalizedPath == ".DS_Store" || normalizedPath.hasSuffix("/.DS_Store")
    }

    static func collisionKey(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping.folding(
            options: [.caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    static func validateLimits(
        archiveBytes: UInt64,
        fileBytes: UInt64,
        expandedBytes: UInt64,
        fileCount: Int,
        compressedBytes: UInt64
    ) throws {
        guard archiveBytes <= UInt64(CharacterPackageLimits.maximumArchiveBytes),
              fileBytes <= UInt64(CharacterPackageLimits.maximumFileBytes),
              expandedBytes <= UInt64(CharacterPackageLimits.maximumExpandedBytes),
              fileCount <= CharacterPackageLimits.maximumFileCount else {
            throw CharacterPackageImportFailure(.unsafeArchive, .preflight)
        }
        let maximum = max(compressedBytes, 1).multipliedReportingOverflow(by: UInt64(CharacterPackageLimits.maximumExpansionRatio))
        guard !maximum.overflow, expandedBytes <= maximum.partialValue else {
            throw CharacterPackageImportFailure(.unsafeArchive, .preflight)
        }
    }
}

private final class BoundedZIPReader {
    private var descriptor: Int32
    let size: Int

    init(url: URL, maximumBytes: Int) throws {
        descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw CharacterPackageImportFailure(.unsafeArchive, .preflight)
        }
        var info = stat()
        guard fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_nlink == 1,
              info.st_size >= 0,
              info.st_size <= off_t(maximumBytes) else {
            Darwin.close(descriptor)
            descriptor = -1
            throw CharacterPackageImportFailure(.unsafeArchive, .preflight)
        }
        size = Int(info.st_size)
    }

    func read(offset: Int, count: Int) throws -> Data {
        guard descriptor >= 0, offset >= 0, count >= 0,
              offset <= size, count <= size - offset else {
            throw CharacterPackageImportFailure(.malformedArchive, .preflight)
        }
        if count == 0 { return Data() }
        var result = Data(count: count)
        var completed = 0
        try result.withUnsafeMutableBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else {
                throw CharacterPackageImportFailure(.malformedArchive, .preflight)
            }
            while completed < count {
                try Task.checkCancellation()
                let amount = Darwin.pread(
                    descriptor,
                    base.advanced(by: completed),
                    count - completed,
                    off_t(offset + completed)
                )
                if amount < 0, errno == EINTR { continue }
                guard amount > 0 else {
                    throw CharacterPackageImportFailure(.malformedArchive, .preflight)
                }
                completed += amount
            }
        }
        return result
    }

    func close() {
        if descriptor >= 0 {
            Darwin.close(descriptor)
            descriptor = -1
        }
    }

    deinit { close() }
}

enum RestrictedZIPPreflight {
    private static let localSignature: UInt32 = 0x0403_4b50
    private static let centralSignature: UInt32 = 0x0201_4b50
    private static let endSignature: UInt32 = 0x0605_4b50
    private static let zip64EndSignature = Data([0x50, 0x4b, 0x06, 0x06])
    private static let zip64LocatorSignature = Data([0x50, 0x4b, 0x06, 0x07])

    static func plan(_ url: URL) throws -> RestrictedZIPPlan {
        try Task.checkCancellation()
        let reader = try BoundedZIPReader(url: url, maximumBytes: CharacterPackageLimits.maximumArchiveBytes)
        defer { reader.close() }
        guard reader.size >= 22 else { throw CharacterPackageImportFailure(.malformedArchive, .preflight) }
        let tailCount = min(reader.size, 65_557)
        let tailOffset = reader.size - tailCount
        let tail = try reader.read(offset: tailOffset, count: tailCount)
        if tail.range(of: zip64EndSignature) != nil || tail.range(of: zip64LocatorSignature) != nil {
            throw CharacterPackageImportFailure(.unsupportedArchiveProfile, .preflight)
        }
        guard let relativeEnd = findEOCD(tail) else { throw CharacterPackageImportFailure(.malformedArchive, .preflight) }
        let end = tailOffset + relativeEnd
        let eocd = try reader.read(offset: end, count: 22)
        let disk = try u16(eocd, 4)
        let centralDisk = try u16(eocd, 6)
        let diskEntries = try u16(eocd, 8)
        let totalEntries = try u16(eocd, 10)
        let centralSize32 = try u32(eocd, 12)
        let centralOffset32 = try u32(eocd, 16)
        let commentLength = Int(try u16(eocd, 20))
        guard end + 22 + commentLength == reader.size else {
            throw CharacterPackageImportFailure(.malformedArchive, .preflight)
        }
        guard disk == 0, centralDisk == 0, diskEntries == totalEntries else {
            throw CharacterPackageImportFailure(.unsupportedArchiveProfile, .preflight)
        }
        guard totalEntries != UInt16.max,
              centralSize32 != UInt32.max,
              centralOffset32 != UInt32.max else {
            throw CharacterPackageImportFailure(.unsupportedArchiveProfile, .preflight)
        }
        let count = Int(totalEntries)
        guard count <= CharacterPackageLimits.maximumFileCount else {
            throw CharacterPackageImportFailure(.unsafeArchive, .preflight)
        }
        let centralOffset = Int(centralOffset32)
        let centralSize = Int(centralSize32)
        let (centralEnd, overflow) = centralOffset.addingReportingOverflow(centralSize)
        guard !overflow, centralOffset >= 0, centralEnd == end else {
            throw CharacterPackageImportFailure(.malformedArchive, .preflight)
        }

        var cursor = centralOffset
        var files: [RestrictedZIPPlan.File] = []
        var collisionKeys = Set<String>()
        var localRanges: [Range<Int>] = []
        var expanded: UInt64 = 0
        var compressedTotal: UInt64 = 0
        for _ in 0..<count {
            try Task.checkCancellation()
            guard cursor <= centralEnd - 46 else {
                throw CharacterPackageImportFailure(.malformedArchive, .preflight)
            }
            let central = try reader.read(offset: cursor, count: 46)
            guard try u32(central, 0) == centralSignature else {
                throw CharacterPackageImportFailure(.malformedArchive, .preflight)
            }
            let madeBy = try u16(central, 4)
            let needed = try u16(central, 6)
            let flags = try u16(central, 8)
            let method = try u16(central, 10)
            let crc = try u32(central, 16)
            let compressed32 = try u32(central, 20)
            let uncompressed32 = try u32(central, 24)
            let nameLength = Int(try u16(central, 28))
            let extraLength = Int(try u16(central, 30))
            let commentLength = Int(try u16(central, 32))
            let diskStart = try u16(central, 34)
            let externalAttributes = try u32(central, 38)
            let localOffset32 = try u32(central, 42)
            if needed >= 45 || compressed32 == UInt32.max || uncompressed32 == UInt32.max || localOffset32 == UInt32.max {
                throw CharacterPackageImportFailure(.unsupportedArchiveProfile, .preflight)
            }
            try validateFlags(flags, method: method)
            guard method == 0 || method == 8 else {
                throw CharacterPackageImportFailure(.unsupportedArchiveProfile, .preflight)
            }
            guard diskStart == 0 else { throw CharacterPackageImportFailure(.unsupportedArchiveProfile, .preflight) }
            let variableLength = try checkedAdd(nameLength, extraLength, commentLength)
            let next = try checkedAdd(cursor, 46, variableLength)
            guard next <= centralEnd else { throw CharacterPackageImportFailure(.malformedArchive, .preflight) }
            let variable = try reader.read(offset: cursor + 46, count: variableLength)
            let nameBytes = variable.prefix(nameLength)
            guard let originalPath = String(data: nameBytes, encoding: .utf8),
                  Data(originalPath.utf8) == nameBytes else {
                throw CharacterPackageImportFailure(.unsafeArchive, .preflight)
            }
            let normalized = try RestrictedZIPPolicy.normalizedPath(originalPath)
            let collision = RestrictedZIPPolicy.collisionKey(normalized)
            guard collisionKeys.insert(collision).inserted else {
                throw CharacterPackageImportFailure(.unsafeArchive, .preflight)
            }
            try validateExtra(Data(variable[nameLength..<(nameLength + extraLength)]))
            let isDirectory = normalized.hasSuffix("/")
            try validateAttributes(madeBy: madeBy, external: externalAttributes, isDirectory: isDirectory)

            let localOffset = Int(localOffset32)
            guard localOffset <= centralOffset - 30 else {
                throw CharacterPackageImportFailure(.malformedArchive, .preflight)
            }
            let local = try reader.read(offset: localOffset, count: 30)
            guard try u32(local, 0) == localSignature else {
                throw CharacterPackageImportFailure(.malformedArchive, .preflight)
            }
            let localFlags = try u16(local, 6)
            let localMethod = try u16(local, 8)
            let localCRC = try u32(local, 14)
            let localCompressed = try u32(local, 18)
            let localUncompressed = try u32(local, 22)
            let localNameLength = Int(try u16(local, 26))
            let localExtraLength = Int(try u16(local, 28))
            let localHeaderEnd = try checkedAdd(localOffset, 30, localNameLength, localExtraLength)
            let localVariable = try reader.read(offset: localOffset + 30, count: localNameLength + localExtraLength)
            guard localHeaderEnd <= centralOffset,
                  localFlags == flags,
                  localMethod == method,
                  localNameLength == nameLength,
                  localVariable.prefix(localNameLength) == Data(originalPath.utf8) else {
                throw CharacterPackageImportFailure(.malformedArchive, .preflight)
            }
            // With a data descriptor the local header is required to hold zeros
            // and the real values trail the payload. Some writers fill both in
            // anyway, so either is accepted — but nothing else is, and without the
            // flag the two headers must still agree exactly.
            let streamed = flags & Self.dataDescriptorFlag != 0
            let localMatchesCentral = localCRC == crc
                && localCompressed == compressed32
                && localUncompressed == uncompressed32
            let localIsPlaceholder = localCRC == 0 && localCompressed == 0 && localUncompressed == 0
            guard localMatchesCentral || (streamed && localIsPlaceholder) else {
                throw CharacterPackageImportFailure(.malformedArchive, .preflight)
            }
            try validateExtra(Data(localVariable.dropFirst(localNameLength)))
            let dataEnd = try checkedAdd(localHeaderEnd, Int(compressed32))
            guard dataEnd <= centralOffset else { throw CharacterPackageImportFailure(.malformedArchive, .preflight) }
            let fullRange = localOffset..<dataEnd
            guard !localRanges.contains(where: { $0.overlaps(fullRange) }) else {
                throw CharacterPackageImportFailure(.unsafeArchive, .preflight)
            }
            localRanges.append(fullRange)
            if isDirectory {
                guard compressed32 == 0, uncompressed32 == 0 else {
                    throw CharacterPackageImportFailure(.unsafeArchive, .preflight)
                }
            } else if RestrictedZIPPolicy.isAppleSidecar(normalized) {
                // Finder writes a __MACOSX/ tree of resource forks beside the real
                // entries, and .DS_Store into every folder. Neither is package
                // content, and a renderer graph would refuse them as undeclared
                // assets — so a Finder archive would be unimportable for a reason
                // the user cannot see or act on.
                //
                // Deliberately skipped *here*, after every check above has already
                // run: a hostile entry hiding under __MACOSX/ is refused on the
                // same terms as any other, it simply is not extracted.
                ()
            } else {
                let compressed = UInt64(compressed32)
                let uncompressed = UInt64(uncompressed32)
                guard uncompressed <= UInt64(CharacterPackageLimits.maximumFileBytes) else {
                    throw CharacterPackageImportFailure(.unsafeArchive, .preflight)
                }
                expanded = try RestrictedZIPPolicy.adding(expanded, uncompressed, limit: UInt64(CharacterPackageLimits.maximumExpandedBytes))
                compressedTotal = try RestrictedZIPPolicy.adding(compressedTotal, compressed, limit: UInt64(CharacterPackageLimits.maximumArchiveBytes))
                files.append(.init(
                    originalPath: originalPath,
                    normalizedPath: normalized,
                    compressedSize: compressed,
                    uncompressedSize: uncompressed,
                    crc32: crc
                ))
            }
            cursor = next
        }
        guard cursor == centralEnd, files.count <= CharacterPackageLimits.maximumFileCount else {
            throw CharacterPackageImportFailure(.malformedArchive, .preflight)
        }
        let denominator = max(compressedTotal, 1)
        let maximum = denominator.multipliedReportingOverflow(by: UInt64(CharacterPackageLimits.maximumExpansionRatio))
        guard !maximum.overflow, expanded <= maximum.partialValue else {
            throw CharacterPackageImportFailure(.unsafeArchive, .preflight)
        }
        return RestrictedZIPPlan(files: files, expandedBytes: expanded)
    }

    private static func findEOCD(_ data: Data) -> Int? {
        let start = max(0, data.count - 65_557)
        guard data.count >= 4 else { return nil }
        var cursor = data.count - 4
        while cursor >= start {
            if (try? u32(data, cursor)) == endSignature { return cursor }
            if cursor == 0 { break }
            cursor -= 1
        }
        return nil
    }

    /// Flag bit 3 says the writer streamed: the local header carries zeros and
    /// the true CRC and sizes follow the payload. It is admitted (DEC-029)
    /// because macOS Finder sets it on every entry, and refusing it refused the
    /// most likely way a Mac user produces an archive.
    ///
    /// Admitting it costs one thing only: the local header can no longer confirm
    /// the central directory's sizes. That confirmation was never the guarantee —
    /// the central directory is what every extractor treats as authoritative, its
    /// values are still bounded here, and the extracted bytes are still hashed
    /// against the manifest afterwards. Encryption stays refused, because nothing
    /// here can read those bytes at all.
    static let dataDescriptorFlag: UInt16 = 0x0008

    private static func validateFlags(_ flags: UInt16, method: UInt16) throws {
        let encryption: UInt16 = 0x0001 | 0x0040
        guard flags & encryption == 0 else {
            throw CharacterPackageImportFailure(.unsupportedArchiveProfile, .preflight)
        }
        let compressionOptions: UInt16 = method == 8 ? 0x0006 : 0
        let allowed: UInt16 = 0x0800 | dataDescriptorFlag | compressionOptions
        guard flags & ~allowed == 0 else {
            throw CharacterPackageImportFailure(.unsupportedArchiveProfile, .preflight)
        }
    }

    private static func validateAttributes(madeBy: UInt16, external: UInt32, isDirectory: Bool) throws {
        let host = UInt8(madeBy >> 8)
        if host == 3 {
            let mode = UInt16(external >> 16)
            let type = mode & 0o170000
            let expected: UInt16 = isDirectory ? 0o040000 : 0o100000
            // A zero type nibble means the writer recorded permissions and no
            // file type — Python's zipfile and several Java libraries do this. It
            // is not a way to smuggle a link past the check: a symbolic link is
            // only a link when S_IFLNK is *set*, so an absent type is an absent
            // claim, not a false one.
            guard type == expected || type == 0 else {
                throw CharacterPackageImportFailure(.unsafeArchive, .preflight)
            }
            // The execute bits are refused on files only. On a directory the same
            // bit is the search bit: a directory without it cannot be entered, so
            // every archiver writes 0o755 and refusing it refused every archive
            // containing a folder — which is every Live2D package.
            guard isDirectory || mode & 0o111 == 0 else {
                throw CharacterPackageImportFailure(.unsafeArchive, .preflight)
            }
        } else if host == 0 || host == 10 {
            let dos = UInt8(external & 0xff)
            guard (dos & 0x10 != 0) == isDirectory else {
                throw CharacterPackageImportFailure(.unsafeArchive, .preflight)
            }
        } else {
            throw CharacterPackageImportFailure(.unsupportedArchiveProfile, .preflight)
        }
    }

    private static func validateExtra(_ data: Data) throws {
        var cursor = 0
        while cursor < data.count {
            guard cursor <= data.count - 4 else { throw CharacterPackageImportFailure(.malformedArchive, .preflight) }
            let identifier = try u16(data, cursor)
            let length = Int(try u16(data, cursor + 2))
            let end = try checkedAdd(cursor, 4, length)
            guard end <= data.count else { throw CharacterPackageImportFailure(.malformedArchive, .preflight) }
            switch identifier {
            case 0x0001:
                throw CharacterPackageImportFailure(.unsupportedArchiveProfile, .preflight)
            case 0x5455:
                guard length >= 1, length <= 13 else { throw CharacterPackageImportFailure(.unsupportedArchiveProfile, .preflight) }
            case 0x000a:
                guard length >= 4 else { throw CharacterPackageImportFailure(.unsupportedArchiveProfile, .preflight) }
            // Info-ZIP's Unix fields. Both carry integers — uid, gid, timestamps —
            // and neither carries a path or a link target, so the length is
            // checked and the body ignored. They are refused nowhere else in the
            // industry, and `zip` and Finder write one or the other on every
            // entry: without these two, no archive a person actually produces can
            // be imported (DEC-029).
            case 0x7875:
                guard length >= 3, length <= 64 else { throw CharacterPackageImportFailure(.unsupportedArchiveProfile, .preflight) }
            case 0x5855:
                guard length >= 8, length <= 64 else { throw CharacterPackageImportFailure(.unsupportedArchiveProfile, .preflight) }
            default:
                throw CharacterPackageImportFailure(.unsupportedArchiveProfile, .preflight)
            }
            cursor = end
        }
        guard cursor == data.count else { throw CharacterPackageImportFailure(.malformedArchive, .preflight) }
    }

    private static func checkedAdd(_ values: Int...) throws -> Int {
        var total = 0
        for value in values {
            let (next, overflow) = total.addingReportingOverflow(value)
            guard !overflow, value >= 0 else { throw CharacterPackageImportFailure(.malformedArchive, .preflight) }
            total = next
        }
        return total
    }

    private static func u16(_ data: Data, _ offset: Int) throws -> UInt16 {
        guard offset >= 0, offset <= data.count - 2 else { throw CharacterPackageImportFailure(.malformedArchive, .preflight) }
        return UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private static func u32(_ data: Data, _ offset: Int) throws -> UInt32 {
        guard offset >= 0, offset <= data.count - 4 else { throw CharacterPackageImportFailure(.malformedArchive, .preflight) }
        return UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }
}
