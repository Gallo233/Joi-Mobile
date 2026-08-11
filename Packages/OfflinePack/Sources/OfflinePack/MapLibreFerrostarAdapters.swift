import CompanionCore
import Foundation

/// Frozen input for a MapLibre implementation that renders only downloaded corridor assets.
public struct MapLibreOfflineCorridorRenderRequest: Equatable, Sendable {
    public let routeID: String
    public let coordinates: [GeoCoordinate]
    public let offlineResourcePaths: [String]

    public init(
        routeID: String,
        coordinates: [GeoCoordinate],
        offlineResourcePaths: [String]
    ) {
        self.routeID = routeID
        self.coordinates = coordinates
        self.offlineResourcePaths = offlineResourcePaths
    }
}

/// Dependency-free seam. A later MapLibre adapter may implement it without changing OfflinePack.
public protocol MapLibreOfflineCorridorRendering: Sendable {
    func renderOfflineCorridor(_ request: MapLibreOfflineCorridorRenderRequest) async throws
    func clearOfflineCorridor(routeID: String) async
}

/// Planning seam for Ferrostar. Offline mode never synthesizes a new route.
public struct FerrostarCachedRoutePlanningAdapter: RoutePlanningProvider, Sendable {
    public init() {}

    public func plan(
        _ request: RouteRequest,
        availability: NavigationAvailability
    ) async throws -> AcceptedNavigationRoute {
        _ = request
        switch availability {
        case .cachedRouteOnly:
            throw NavigationError.newRouteUnavailableOffline
        case .online:
            throw NavigationError.routeUnavailable
        }
    }
}

/// Dependency-free cached-navigation seam. It follows one accepted route and emits observations.
public actor FerrostarCachedNavigationAdapter: NavigationProvider {
    private struct ActiveSession: Sendable {
        let id: NavigationSessionID
        let engine: RouteProgressEngine
    }

    private static let rejectedSessionID = NavigationSessionID(
        rawValue: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    )

    private let configuration: RouteProgressConfiguration
    private var activeSession: ActiveSession?
    private var stoppedSessions: Set<NavigationSessionID> = []

    public init(configuration: RouteProgressConfiguration = .init()) {
        self.configuration = configuration
    }

    public func start(
        _ route: AcceptedNavigationRoute,
        session: NavigationSessionID,
        mode: NavigationAvailability
    ) async throws {
        guard mode == .cachedRouteOnly else {
            throw NavigationError.routeUnavailable
        }
        guard route.cached else {
            throw NavigationError.invalidCachedRoute
        }

        let engine = try RouteProgressEngine(route: route, configuration: configuration)
        if let replaced = activeSession?.id {
            stoppedSessions.insert(replaced)
        }
        stoppedSessions.remove(session)
        activeSession = ActiveSession(id: session, engine: engine)
    }

    /// Checked API for callers that need the explicit session lifecycle error.
    public func observeChecked(
        _ location: LocationObservation,
        session: NavigationSessionID
    ) async throws -> CachedRouteProgressObservation {
        if stoppedSessions.contains(session) {
            throw NavigationError.cancelled
        }
        guard let activeSession, activeSession.id == session else {
            throw NavigationError.staleSession
        }
        return try activeSession.engine.observe(location, session: session)
    }

    /// Protocol API cannot throw. Rejected observations use a sentinel session so the store cannot commit them.
    public func observe(
        _ location: LocationObservation,
        session: NavigationSessionID
    ) async -> NavigationObservation {
        do {
            return try await observeChecked(location, session: session).navigationObservation
        } catch {
            return NavigationObservation(
                sessionID: Self.rejectedSessionID,
                candidateProgress: 0,
                distanceToRouteMeters: Double.greatestFiniteMagnitude,
                offRoute: true,
                nearestCoordinate: nil
            )
        }
    }

    public func stop(
        session: NavigationSessionID,
        reason: NavigationStopReason
    ) async {
        _ = reason
        stoppedSessions.insert(session)
        if activeSession?.id == session {
            activeSession = nil
        }
    }
}
