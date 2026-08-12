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
                  localCRC == crc,
                  localCompressed == compressed32,
                  localUncompressed == uncompressed32,
                  localNameLength == nameLength,
                  localVariable.prefix(localNameLength) == Data(originalPath.utf8) else {
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

    private static func validateFlags(_ flags: UInt16, method: UInt16) throws {
        let encryption: UInt16 = 0x0001 | 0x0040
        let dataDescriptor: UInt16 = 0x0008
        guard flags & encryption == 0, flags & dataDescriptor == 0 else {
            throw CharacterPackageImportFailure(.unsupportedArchiveProfile, .preflight)
        }
        let compressionOptions: UInt16 = method == 8 ? 0x0006 : 0
        let allowed: UInt16 = 0x0800 | compressionOptions
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
            guard type == expected, mode & 0o111 == 0 else {
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
