import Foundation

public struct MockChatGateway: ChatGateway {
    public init() {}

    public func stream(_ request: ChatRequest) -> AsyncThrowingStream<CompanionEventV1, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(
                CompanionEventV1(
                    eventID: "\(request.requestID)-received",
                    requestID: request.requestID,
                    threadID: request.threadID,
                    sessionID: request.sessionID,
                    characterID: request.characterID,
                    phase: .received,
                    contentState: .acceptedInput,
                    displayText: request.text
                )
            )
            continuation.yield(
                CompanionEventV1(
                    eventID: "\(request.requestID)-done",
                    requestID: request.requestID,
                    threadID: request.threadID,
                    sessionID: request.sessionID,
                    characterID: request.characterID,
                    phase: .done,
                    contentState: .acceptedFinal,
                    displayText: "这是本地模拟回复。",
                    voiceLine: "这是本地模拟回复。",
                    memoryEligibility: .proposalAllowed
                )
            )
            continuation.finish()
        }
    }
}

public struct MockRoutePlanningProvider: RoutePlanningProvider {
    public init() {}

    public func plan(
        _ request: RouteRequest,
        availability: NavigationAvailability
    ) async throws -> AcceptedNavigationRoute {
        guard availability == .online else {
            throw NavigationError.newRouteUnavailableOffline
        }
        return AcceptedNavigationRoute(
            routeID: "mock-route",
            coordinates: [request.origin, request.destination],
            cached: false
        )
    }
}

public actor MockNavigationProvider: NavigationProvider {
    private var route: AcceptedNavigationRoute?
    private var sessionID: NavigationSessionID?

    public init() {}

    public func start(
        _ route: AcceptedNavigationRoute,
        session: NavigationSessionID,
        mode _: NavigationAvailability
    ) async throws {
        self.route = route
        sessionID = session
    }

    public func observe(
        _ location: LocationObservation,
        session: NavigationSessionID
    ) async -> NavigationObservation {
        guard session == sessionID, let route else {
            return NavigationObservation(
                sessionID: session,
                candidateProgress: 0,
                distanceToRouteMeters: .infinity,
                offRoute: true,
                nearestCoordinate: nil
            )
        }
        let nearest = route.coordinates.min { lhs, rhs in
            squaredDistance(lhs, location.coordinate) < squaredDistance(rhs, location.coordinate)
        }
        return NavigationObservation(
            sessionID: session,
            candidateProgress: route.coordinates.last == nearest ? 1 : 0,
            distanceToRouteMeters: 0,
            offRoute: false,
            nearestCoordinate: nearest
        )
    }

    public func stop(session: NavigationSessionID, reason _: NavigationStopReason) async {
        guard session == sessionID else { return }
        route = nil
        sessionID = nil
    }

    private func squaredDistance(_ lhs: GeoCoordinate, _ rhs: GeoCoordinate) -> Double {
        let latitude = lhs.latitude - rhs.latitude
        let longitude = lhs.longitude - rhs.longitude
        return latitude * latitude + longitude * longitude
    }
}

public actor MockCharacterRenderer: CharacterRenderer {
    public nonisolated let kind: CharacterRendererKind
    private var currentGeneration: RendererGeneration?

    public init(kind: CharacterRendererKind = .static) {
        self.kind = kind
    }

    public func load(
        _ package: ValidatedCharacterPackageHandle,
        generation: RendererGeneration
    ) async -> CharacterLoadResult {
        currentGeneration = generation
        guard package.manifest.renderer == kind || kind == .static else {
            return package.manifest.portraitPath == nil
                ? .bundledStaticJoi(reason: .runtimeUnavailable)
                : .packagePortrait(reason: .runtimeUnavailable)
        }
        return .animated(capabilities: CharacterCapabilities(lipSync: true), generation: generation)
    }

    public func apply(_ state: CharacterPresentationState, generation: RendererGeneration) async {
        guard generation == currentGeneration else { return }
        _ = state
    }

    public func stop(generation: RendererGeneration) async {
        guard generation == currentGeneration else { return }
    }

    public func release(generation: RendererGeneration) async {
        guard generation == currentGeneration else { return }
        currentGeneration = nil
    }
}
