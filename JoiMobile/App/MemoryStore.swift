import CompanionCore
import Foundation
import OSLog

private let memoryLog = Logger(subsystem: "com.joi.mobile", category: "memory")

/// The durable local memory (`G2-J2D`), and the only thing that writes it.
///
/// `MemoryRepository` has been a frozen contract since G1 with no implementation
/// behind it, so `JM-P0-005`'s "every durable item records category and
/// provenance" was a sentence rather than a file. This is the file.
///
/// Deliberately plain JSON in Application Support rather than a database: the
/// whole store is a handful of short records a person is entitled to read, and
/// `JM-P0-023` will have to export and delete it. Nothing here is encrypted —
/// this is on-device storage covered by the device's own protection, and calling
/// it encrypted without a key story would be a claim this repository has not
/// earned.
actor MemoryStore: MemoryRepository {
    private let fileURL: URL
    private var loaded: [MemoryRecordV1]?

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// The default store, beside the character root rather than inside it:
    /// DEC-002 and the package-isolation rule both require that removing a
    /// character package cannot take the conversation's memory with it.
    static func defaultFileURL() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return root
            .appendingPathComponent("JoiMobile", isDirectory: true)
            .appendingPathComponent("memory.v1.json")
    }

    func list(characterID: String) async throws -> [MemoryRecordV1] {
        // Scoped by character, because memory belongs to a relationship. A second
        // character must not read what was said to the first.
        try records()
            .filter { $0.characterID == characterID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func save(_ record: MemoryRecordV1, authorizationDigest: String?) async throws {
        // The contract passes the digest separately so the caller cannot save a
        // record whose stored authorisation disagrees with the one it presented.
        // They must match, or the record is not the one that was authorised.
        guard authorizationDigest == record.authorizationDigest else {
            throw MemoryStoreError.authorizationMismatch
        }
        var current = try records()
        if let index = current.firstIndex(where: { $0.recordID == record.recordID }) {
            current[index] = record
        } else {
            current.append(record)
        }
        try write(current)
    }

    func delete(recordID: String) async throws {
        var current = try records()
        let before = current.count
        current.removeAll { $0.recordID == recordID }
        guard current.count != before else { throw MemoryStoreError.notFound }
        try write(current)
    }

    // MARK: - Storage

    private func records() throws -> [MemoryRecordV1] {
        if let loaded { return loaded }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            loaded = []
            return []
        }
        let data = try Data(contentsOf: fileURL)
        // A store that cannot be read is not silently replaced with an empty one:
        // that would delete a person's memory to avoid showing an error.
        let decoded = try Self.decoder.decode([MemoryRecordV1].self, from: data)
        loaded = decoded
        return decoded
    }

    private func write(_ records: [MemoryRecordV1]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try Self.encoder.encode(records)
        // Written to a sibling and moved into place, so an interrupted write
        // leaves the previous store intact rather than a truncated file.
        let staging = fileURL.deletingLastPathComponent()
            .appendingPathComponent("memory.v1.\(UUID().uuidString).tmp")
        try data.write(to: staging, options: .atomic)
        _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: staging)
        loaded = records
        // Count only. A memory value is exactly the kind of user content the
        // logging rule keeps out of the log.
        memoryLog.info("memory store written: \(records.count, privacy: .public) records")
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

enum MemoryStoreError: Error, Equatable {
    case authorizationMismatch
    case notFound
}
