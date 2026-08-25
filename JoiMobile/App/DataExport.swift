import CharacterRuntime
import CompanionCore
import CryptoKit
import Foundation
import OfflinePack
import OSLog

private let exportLog = Logger(subsystem: "com.joi.mobile", category: "export")

/// The file an export produces (`G2-J5I`).
///
/// One JSON document, because everything a person can take out of this app is
/// short text: memories, a conversation, an inventory of what is installed. The
/// large things on the device — a character's model, textures and motions — are
/// deliberately not in it, and the document says so where the reader will be
/// looking for them.
struct DataExportDocumentV1: Codable, Equatable {
    static let schemaID = "joi.data-export.v1"

    struct AppFacts: Codable, Equatable {
        let version: String
        let build: String
    }

    /// One line of the open conversation. The author, the words and the time —
    /// and not the event, request or thread identifiers, which are this app's
    /// plumbing rather than the reader's data.
    struct ConversationLine: Codable, Equatable {
        let author: TranscriptAuthor
        let text: String
        let at: Date
    }

    /// An installed character, as an inventory entry rather than as its files.
    struct CharacterPackageEntry: Codable, Equatable {
        let installationID: String
        let contentID: String
        let characterID: String
        let displayName: String
        let renderer: CharacterRendererKind
        let available: Bool
        let activationAllowed: Bool
    }

    struct TravelPackEntry: Codable, Equatable {
        let packID: String
        let version: String
        /// Absent when the pack's own content file no longer decodes; the pack
        /// is still installed, and is still listed.
        let title: String?
        let rights: String
        let sourceRevisionIDs: [String]
    }

    /// One category, what it holds, and what it does not.
    ///
    /// `statement` is prose for the person reading the file; `coverage` is the
    /// same fact in a form a program can check. Both are here because an export
    /// is read by people and audited by tests, and neither should have to infer
    /// the other.
    struct Section: Codable, Equatable {
        let category: DataCategory
        let coverage: DataExportCoverage
        let statement: String
        var memory: [MemoryRecordV1]?
        var conversation: [ConversationLine]?
        var characterPackages: [CharacterPackageEntry]?
        var travelPacks: [TravelPackEntry]?
    }

    let schema: String
    let requestID: String
    let producedAt: Date
    let app: AppFacts
    /// What this document is, and what it is not, before any of the data.
    let scope: String
    let sections: [Section]
}

/// Builds the document from what the device actually holds.
///
/// Pure: it takes values and returns a document, so every honesty rule — every
/// category present exactly once, an absent feature distinguished from an empty
/// one, no filesystem path anywhere — is checkable without a screen, a disk or a
/// simulator.
enum DataExportBuilder {

    static func document(
        request: DataExportRequestV1,
        app: DataExportDocumentV1.AppFacts,
        memory: [MemoryRecordV1],
        conversation: [TranscriptEntry],
        characters: [CharacterPackageCatalogEntry],
        travelPacks: [InstalledTravelPackSummary]
    ) -> DataExportDocumentV1 {
        DataExportDocumentV1(
            schema: DataExportDocumentV1.schemaID,
            requestID: request.requestID,
            producedAt: request.requestedAt,
            app: app,
            scope: String(localized: "这份导出只包含这台设备上的数据。这一版没有账户，也没有任何内容为了同步离开过这台设备。"),
            // Built from `DataCategory.allCases` rather than by listing sections
            // here: a category added to the contract and forgotten here would be
            // a category silently missing from every export.
            sections: DataCategory.allCases.map { category in
                section(
                    category,
                    memory: memory,
                    conversation: conversation,
                    characters: characters,
                    travelPacks: travelPacks
                )
            }
        )
    }

    private static func section(
        _ category: DataCategory,
        memory: [MemoryRecordV1],
        conversation: [TranscriptEntry],
        characters: [CharacterPackageCatalogEntry],
        travelPacks: [InstalledTravelPackSummary]
    ) -> DataExportDocumentV1.Section {
        switch category {
        case .packages:
            return packages(characters: characters, travelPacks: travelPacks)
        case .conversations:
            return conversations(conversation)
        case .memory:
            return self.memory(memory)
        case .travelHistory:
            return travelHistory()
        case .account:
            return account()
        }
    }

    /// Installed packages, as an inventory.
    ///
    /// The asset bytes stay behind on purpose. A character package's model,
    /// textures and motions are the author's work under the licence the package
    /// declares — and DEC-010 is explicit that a hash proves integrity, not
    /// authorship or the right to redistribute. Writing those files out under
    /// the heading "your data" would turn every export into a redistribution the
    /// rights quarantine exists to prevent, and it would give the user nothing:
    /// the file they imported is still theirs, where they got it.
    private static func packages(
        characters: [CharacterPackageCatalogEntry],
        travelPacks: [InstalledTravelPackSummary]
    ) -> DataExportDocumentV1.Section {
        let characterEntries = characters.map {
            DataExportDocumentV1.CharacterPackageEntry(
                installationID: $0.installationID.rawValue,
                contentID: $0.contentID.rawValue,
                characterID: $0.characterID,
                displayName: $0.displayName,
                renderer: $0.renderer,
                available: $0.available,
                activationAllowed: $0.activationAllowed
            )
        }
        let packEntries = travelPacks.map {
            DataExportDocumentV1.TravelPackEntry(
                packID: $0.packID,
                version: $0.version,
                title: $0.title,
                rights: $0.rights,
                sourceRevisionIDs: $0.sourceRevisionIDs
            )
        }
        let count = characterEntries.count + packEntries.count
        return DataExportDocumentV1.Section(
            category: .packages,
            coverage: count == 0
                ? .empty
                : .partial(
                    itemCount: count,
                    missing: String(localized: "角色包与旅行包的模型、贴图、动作与地图资源文件本身")
                ),
            statement: String(localized: "这台设备上已安装的角色包与旅行包清单。资源文件本身不在导出里：它们的使用权利属于作者，把它们复制出来就成了一次再分发。你导入时用的原始文件仍然在你自己手里。"),
            characterPackages: characterEntries.isEmpty ? nil : characterEntries,
            travelPacks: packEntries.isEmpty ? nil : packEntries
        )
    }

    /// The open conversation, and the fact that there is no other.
    ///
    /// Always `partial`, including when it is empty: this app keeps no
    /// conversation after it closes, so an empty list here means "nothing was
    /// said in this session", never "you have no history". Reporting it as
    /// `empty` would let the second reading stand.
    private static func conversations(_ conversation: [TranscriptEntry]) -> DataExportDocumentV1.Section {
        let lines = conversation.map {
            DataExportDocumentV1.ConversationLine(author: $0.author, text: $0.text, at: $0.timestamp)
        }
        return DataExportDocumentV1.Section(
            category: .conversations,
            coverage: .partial(
                itemCount: lines.count,
                missing: String(localized: "更早的对话：这一版从未把它们保存下来")
            ),
            statement: String(localized: "当前这一段对话。这一版在应用关闭后不保留对话，所以这里不会有更早的内容——不是被省略了，而是从未被保存。"),
            conversation: lines
        )
    }

    private static func memory(_ records: [MemoryRecordV1]) -> DataExportDocumentV1.Section {
        DataExportDocumentV1.Section(
            category: .memory,
            coverage: records.isEmpty ? .empty : .complete(itemCount: records.count),
            statement: String(localized: "你确认保存的记忆，连同它的分类、来源、理由与时间。包含所有角色的记忆，也包含角色被删除后留下的记忆。"),
            memory: records.isEmpty ? nil : records
        )
    }

    /// Nothing, and the difference between the two ways of having nothing.
    ///
    /// Travel *memories* are durable and are exported — under `memory`, where
    /// the user accepted them. Where the walk went is not recorded anywhere, so
    /// this category is unavailable rather than empty, and says which.
    private static func travelHistory() -> DataExportDocumentV1.Section {
        DataExportDocumentV1.Section(
            category: .travelHistory,
            coverage: .unavailable(reason: String(localized: "这一版不记录行程历史。")),
            statement: String(localized: "这一版不会记录你走过的路线、到过的地点或走完的时间。你在步行后确认保存的旅行记忆在「记忆」一节里。")
        )
    }

    private static func account() -> DataExportDocumentV1.Section {
        DataExportDocumentV1.Section(
            category: .account,
            coverage: .unavailable(reason: String(localized: "这一版没有账户。")),
            statement: String(localized: "这一版没有账户，也没有任何账户数据：没有登录、没有服务器上的副本，也没有需要向谁索取的内容。")
        )
    }
}

/// The export as the app holds it: the file, and the evidence it landed.
struct DataExport: Equatable, Identifiable {
    let fileURL: URL
    let result: DataExportResultV1

    var id: String { result.requestID }
    var fileName: String { fileURL.lastPathComponent }
}

/// Where the export flow is.
///
/// `ready` is the only state in which a file exists, and `failed` is the only
/// one that carries a reason. Nothing here is "partially exported": an export
/// either landed and was read back, or it did not happen.
enum DataExportState: Equatable {
    case idle
    case working
    case ready(DataExport)
    case failed(message: String)
}

/// Writes an export, then proves it landed.
///
/// The order of the three things this does is the whole design. Room is checked
/// before anything is written, so a full device costs a message rather than a
/// half-written file (`FAIL-029`). The new file is verified by re-reading it,
/// because a write that cannot be read back is not an export and must not be
/// reported as one. Only then is the previous export removed — a failed export
/// must never be the reason the user lost the one they already had.
struct DataExportWriter: Sendable {
    /// Room for the staging copy's directory entry and the atomic replace. Small
    /// and fixed, like DEC-039's: a percentage of a JSON document would scale
    /// with the wrong thing.
    static let storageMarginBytes = 256 * 1_024

    let directory: URL
    /// Injected for the same reason DEC-039 injects it: the refusal branch is
    /// only reachable by controlling what the volume reports, and a test that
    /// filled the real disk would be testing the filesystem and breaking the
    /// machine.
    let availableBytes: @Sendable (URL) -> Int64?
    /// Injected so "the bytes that landed are not the bytes we wrote" is a case
    /// a test can actually produce. Nothing in the product replaces it.
    let writeData: @Sendable (Data, URL) throws -> Void

    init(
        directory: URL,
        availableBytes: @escaping @Sendable (URL) -> Int64? = DataExportWriter.volumeCapacity,
        writeData: @escaping @Sendable (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }
    ) {
        self.directory = directory
        self.availableBytes = availableBytes
        self.writeData = writeData
    }

    static let volumeCapacity: @Sendable (URL) -> Int64? = { url in
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let capacity = values?.volumeAvailableCapacityForImportantUsage else { return nil }
        return Int64(capacity)
    }

    func write(_ document: DataExportDocumentV1, request: DataExportRequestV1) throws -> DataExport {
        let data: Data
        do {
            data = try Self.encoder.encode(document)
        } catch {
            throw DataExportError.writeFailed
        }
        let expected = Self.digest(data)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw DataExportError.writeFailed
        }
        try requireRoom(for: data.count)

        let destination = directory.appendingPathComponent(Self.fileName(at: request.requestedAt))
        let staging = directory.appendingPathComponent("export.\(UUID().uuidString).tmp")
        do {
            try writeData(data, staging)
            if FileManager.default.fileExists(atPath: destination.path) {
                // Swapped rather than deleted-then-moved. Two exports in the same
                // second land on the same name, and removing the old file first
                // would open a window where a failed move leaves the user with
                // neither — the one thing the ordering here exists to prevent.
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
            } else {
                try FileManager.default.moveItem(at: staging, to: destination)
            }
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw DataExportError.writeFailed
        }

        // Measured from the file, not from `data`: the point is to prove that
        // what a person can now open holds what this export claims.
        guard let landed = try? Data(contentsOf: destination), Self.digest(landed) == expected else {
            try? FileManager.default.removeItem(at: destination)
            throw DataExportError.verificationFailed
        }

        removeExportsOtherThan(destination)
        exportLog.info("data export written: \(landed.count, privacy: .public) bytes")
        return DataExport(
            fileURL: destination,
            result: DataExportResultV1(
                requestID: request.requestID,
                producedAt: request.requestedAt,
                categories: document.sections.map {
                    DataExportCategoryResultV1(category: $0.category, coverage: $0.coverage)
                },
                byteCount: landed.count,
                sha256: Self.digest(landed),
                remote: .notApplicable(
                    reason: String(localized: "这一版没有服务器副本，也没有需要等待的确认。")
                )
            )
        )
    }

    /// Refuses an export the device cannot hold, with both numbers.
    ///
    /// The requirement is the document plus the previous export, because the old
    /// one is still there while the new one is written — deleting it first would
    /// make room by destroying the thing the user already had.
    private func requireRoom(for requiredBytes: Int) throws {
        guard let available = availableBytes(directory) else { return }
        let needed = requiredBytes + Self.storageMarginBytes
        guard available >= Int64(needed) else {
            throw DataExportError.storageInsufficient(
                requiredBytes: needed,
                availableBytes: Int(clamping: available)
            )
        }
    }

    /// One export at a time.
    ///
    /// An export is a second copy of everything the user holds, sitting inside
    /// the app. Letting them accumulate would quietly turn a privacy feature
    /// into a growing pile of duplicates nobody remembers making.
    private func removeExportsOtherThan(_ keep: URL) {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        for url in contents where url.lastPathComponent != keep.lastPathComponent {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// `joi-export-2026-08-20-143005.json`, in the device's own time zone.
    ///
    /// Built from calendar components rather than a `DateFormatter` so no shared
    /// mutable formatter has to be reasoned about under strict concurrency.
    static func fileName(at date: Date) -> String {
        let parts = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        return String(
            format: "joi-export-%04d-%02d-%02d-%02d%02d%02d.json",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0,
            parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0
        )
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // Pretty-printed and sorted, because a person opens this file. The
        // ordering also makes two exports of the same state comparable.
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return encoder
    }()
}
