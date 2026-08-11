import CryptoKit
import Foundation

public struct GeoCoordinate: Codable, Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct JourneyContextSnapshot: Codable, Equatable, Sendable {
    public let journeyID: String?
    public let placeID: String?
    public let routeID: String?
    public let stopID: String?
    public let coordinate: GeoCoordinate?
    public let horizontalAccuracyMeters: Double?
    public let observedAt: Date?
    public let routeProgress: Double?
    public let identityConfidence: Double?
    public let sourceRevisionIDs: [String]
    public let consentScope: String

    public init(
        journeyID: String? = nil,
        placeID: String? = nil,
        routeID: String? = nil,
        stopID: String? = nil,
        coordinate: GeoCoordinate? = nil,
        horizontalAccuracyMeters: Double? = nil,
        observedAt: Date? = nil,
        routeProgress: Double? = nil,
        identityConfidence: Double? = nil,
        sourceRevisionIDs: [String] = [],
        consentScope: String = "ephemeral"
    ) {
        self.journeyID = journeyID
        self.placeID = placeID
        self.routeID = routeID
        self.stopID = stopID
        self.coordinate = coordinate
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.observedAt = observedAt
        self.routeProgress = routeProgress
        self.identityConfidence = identityConfidence
        self.sourceRevisionIDs = sourceRevisionIDs
        self.consentScope = consentScope
    }

    public static let empty = JourneyContextSnapshot()

    /// Deterministic digest for one-turn consent binding. Raw coordinates never enter the receipt.
    public func payloadDigest() -> String {
        let fields = [
            "joi.journey-context-digest.v1",
            digestField(journeyID),
            digestField(placeID),
            digestField(routeID),
            digestField(stopID),
            digestNumber(coordinate?.latitude, decimals: 8),
            digestNumber(coordinate?.longitude, decimals: 8),
            digestNumber(horizontalAccuracyMeters, decimals: 3),
            observedAt.map { String(Int64(($0.timeIntervalSince1970 * 1_000).rounded())) } ?? "-",
            digestNumber(routeProgress, decimals: 6),
            digestNumber(identityConfidence, decimals: 6),
            sourceRevisionIDs.map { digestField($0) }.joined(separator: "."),
            digestField(consentScope),
        ]
        let data = Data(fields.joined(separator: "\n").utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func digestField(_ value: String?) -> String {
        guard let value else { return "-" }
        return Data(value.utf8).base64EncodedString()
    }

    private func digestNumber(_ value: Double?, decimals: Int) -> String {
        guard let value else { return "-" }
        return String(
            format: "%.*f",
            locale: Locale(identifier: "en_US_POSIX"),
            decimals,
            value
        )
    }
}

public struct TravelPackFileV1: Codable, Equatable, Sendable {
    public let path: String
    public let sha256: String
    public let mediaType: String
}

public struct TravelPackManifestV1: Codable, Equatable, Sendable {
    public let schema: String
    public let packID: String
    public let routeID: String
    public let version: String
    public let locales: [String]
    public let routePath: String
    public let files: [TravelPackFileV1]
    public let sourceRevisionIDs: [String]
    public let rights: [String]
    public let createdAt: Date
    public let expiresAt: Date?

    public init(
        schema: String = "joi.travel-pack.v1",
        packID: String,
        routeID: String,
        version: String,
        locales: [String],
        routePath: String,
        files: [TravelPackFileV1],
        sourceRevisionIDs: [String],
        rights: [String],
        createdAt: Date,
        expiresAt: Date? = nil
    ) {
        self.schema = schema
        self.packID = packID
        self.routeID = routeID
        self.version = version
        self.locales = locales
        self.routePath = routePath
        self.files = files
        self.sourceRevisionIDs = sourceRevisionIDs
        self.rights = rights
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }
}

public struct AcceptedNavigationRoute: Codable, Equatable, Sendable {
    public let routeID: String
    public let coordinates: [GeoCoordinate]
    public let cached: Bool

    public init(routeID: String, coordinates: [GeoCoordinate], cached: Bool) {
        self.routeID = routeID
        self.coordinates = coordinates
        self.cached = cached
    }
}

public struct RouteRequest: Codable, Equatable, Sendable {
    public let origin: GeoCoordinate
    public let destination: GeoCoordinate
    public let mode: String

    public init(origin: GeoCoordinate, destination: GeoCoordinate, mode: String) {
        self.origin = origin
        self.destination = destination
        self.mode = mode
    }
}

public enum NavigationAvailability: String, Codable, Sendable {
    case online
    case cachedRouteOnly
}

public struct NavigationSessionID: Hashable, Codable, Sendable {
    public let rawValue: UUID
    public init(rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

public struct LocationObservation: Codable, Equatable, Sendable {
    public let coordinate: GeoCoordinate
    public let horizontalAccuracyMeters: Double
    public let observedAt: Date

    public init(
        coordinate: GeoCoordinate,
        horizontalAccuracyMeters: Double,
        observedAt: Date
    ) {
        self.coordinate = coordinate
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.observedAt = observedAt
    }
}

public struct NavigationObservation: Codable, Equatable, Sendable {
    public let sessionID: NavigationSessionID
    public let candidateProgress: Double
    public let distanceToRouteMeters: Double
    public let offRoute: Bool
    public let nearestCoordinate: GeoCoordinate?

    public init(
        sessionID: NavigationSessionID,
        candidateProgress: Double,
        distanceToRouteMeters: Double,
        offRoute: Bool,
        nearestCoordinate: GeoCoordinate?
    ) {
        self.sessionID = sessionID
        self.candidateProgress = candidateProgress
        self.distanceToRouteMeters = distanceToRouteMeters
        self.offRoute = offRoute
        self.nearestCoordinate = nearestCoordinate
    }
}

public enum NavigationStopReason: String, Codable, Sendable {
    case userStopped
    case completed
    case cancelled
    case replaced
}

public enum NavigationError: Error, Equatable, Sendable {
    case routeUnavailable
    case newRouteUnavailableOffline
    case invalidCachedRoute
    case staleSession
    case locationUnavailable
    case cancelled
}

public protocol RoutePlanningProvider: Sendable {
    func plan(
        _ request: RouteRequest,
        availability: NavigationAvailability
    ) async throws -> AcceptedNavigationRoute
}

public protocol NavigationProvider: Actor {
    func start(
        _ route: AcceptedNavigationRoute,
        session: NavigationSessionID,
        mode: NavigationAvailability
    ) async throws
    func observe(
        _ location: LocationObservation,
        session: NavigationSessionID
    ) async -> NavigationObservation
    func stop(session: NavigationSessionID, reason: NavigationStopReason) async
}
