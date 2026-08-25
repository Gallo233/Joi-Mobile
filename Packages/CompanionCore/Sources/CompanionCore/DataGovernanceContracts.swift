import Foundation

/// The five things PRD §6.4 requires an export to keep apart.
///
/// A closed enum rather than strings chosen at each call site, so "the export
/// covers every category the product promised" is a property a test can check.
/// `packages` is the device's installed packages — character packages and the
/// installed travel pack — while `travelHistory` is where the user has actually
/// been. They are separate because a downloaded product and a person's movements
/// are different data with different rules.
public enum DataCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case packages
    case conversations
    case memory
    case travelHistory
    case account

    public var id: String { rawValue }
}

/// How much of a category an export actually carries.
///
/// The distinction this type exists for is `empty` against `unavailable`. An
/// empty array under `account` reads as "you have no account data", which is a
/// claim about the user; the truth is "this build has no accounts", which is a
/// claim about the app. An export that cannot tell those apart is a document
/// that misinforms the person it was made for.
///
/// `partial` carries what is *not* in it, in words, because a category that is
/// included but not whole is the case most likely to be misread as whole.
public enum DataExportCoverage: Codable, Equatable, Sendable {
    case complete(itemCount: Int)
    case empty
    case partial(itemCount: Int, missing: String)
    case unavailable(reason: String)

    /// How many items this category actually contributed.
    public var itemCount: Int {
        switch self {
        case let .complete(count): count
        case let .partial(count, _): count
        case .empty, .unavailable: 0
        }
    }
}

public struct DataExportCategoryResultV1: Codable, Equatable, Sendable {
    public let category: DataCategory
    public let coverage: DataExportCoverage

    public init(category: DataCategory, coverage: DataExportCoverage) {
        self.category = category
        self.coverage = coverage
    }
}

/// One export the user asked for.
///
/// `requestID` is retry identity: exporting twice after a failure must be two
/// attempts at one request rather than two exports, so a caller that retries
/// reuses the identifier it already has.
public struct DataExportRequestV1: Codable, Equatable, Sendable {
    public static let schemaID = "joi.data-export-request.v1"

    public let schema: String
    public let requestID: String
    public let categories: [DataCategory]
    public let requestedAt: Date

    public init(
        schema: String = DataExportRequestV1.schemaID,
        requestID: String,
        categories: [DataCategory] = DataCategory.allCases,
        requestedAt: Date
    ) {
        self.schema = schema
        self.requestID = requestID
        self.categories = categories
        self.requestedAt = requestedAt
    }
}

/// Whether anything outside this device still has to acknowledge an export.
///
/// Deliberately one case. `JM-P0-023` requires completion evidence for
/// *synchronized* export too, and nothing in this product synchronizes anything
/// — so a type with `pending` and `acknowledged` cases would be a shape no code
/// could produce, and the first reader would reasonably assume something does.
/// Building sync means adding the cases here, and every switch that has to
/// change is a place that was silently assuming local-only.
public enum RemoteExportAcknowledgement: Codable, Equatable, Sendable {
    case notApplicable(reason: String)
}

/// What an export produced, and the evidence that it produced it.
///
/// `byteCount` and `sha256` are measured from the file that landed, re-read
/// after the write, rather than from the bytes that were handed to the writer.
/// An export is a promise that a copy of the user's data now exists somewhere
/// they can reach, and only reading it back proves that.
public struct DataExportResultV1: Codable, Equatable, Sendable {
    public static let schemaID = "joi.data-export-result.v1"

    public let schema: String
    public let requestID: String
    public let producedAt: Date
    public let categories: [DataExportCategoryResultV1]
    public let byteCount: Int
    public let sha256: String
    public let remote: RemoteExportAcknowledgement

    public init(
        schema: String = DataExportResultV1.schemaID,
        requestID: String,
        producedAt: Date,
        categories: [DataExportCategoryResultV1],
        byteCount: Int,
        sha256: String,
        remote: RemoteExportAcknowledgement
    ) {
        self.schema = schema
        self.requestID = requestID
        self.producedAt = producedAt
        self.categories = categories
        self.byteCount = byteCount
        self.sha256 = sha256
        self.remote = remote
    }

    public func coverage(of category: DataCategory) -> DataExportCoverage? {
        categories.first { $0.category == category }?.coverage
    }
}

/// Why an export did not happen.
///
/// `storageInsufficient` carries both numbers for the same reason DEC-039 gives
/// for imports: "not enough space" leaves the user unable to tell whether to
/// free one file or ten thousand. `verificationFailed` exists because a write
/// that cannot be read back is not an export, and reporting it as one would hand
/// someone a file they believe holds their data.
public enum DataExportError: Error, Equatable, Sendable {
    case storageInsufficient(requiredBytes: Int, availableBytes: Int)
    case writeFailed
    case verificationFailed
}
