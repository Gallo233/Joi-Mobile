import CompanionCore
import Foundation

/// Configuration for deterministic observations along one immutable cached route.
public struct RouteProgressConfiguration: Equatable, Sendable {
    public let offRouteThresholdMeters: Double
    public let arrivalThresholdMeters: Double
    public let maximumAccuracyAllowanceMeters: Double

    public init(
        offRouteThresholdMeters: Double = 25,
        arrivalThresholdMeters: Double = 8,
        maximumAccuracyAllowanceMeters: Double = 15
    ) {
        self.offRouteThresholdMeters = max(0, offRouteThresholdMeters)
        self.arrivalThresholdMeters = max(0, arrivalThresholdMeters)
        self.maximumAccuracyAllowanceMeters = max(0, maximumAccuracyAllowanceMeters)
    }
}

/// Direction back to the accepted route. It is intentionally not a maneuver or a reroute.
public struct RouteReturnGuidance: Equatable, Sendable {
    public let nearestRouteCoordinate: GeoCoordinate
    public let distanceMeters: Double
    public let bearingToRouteDegrees: Double

    public init(
        nearestRouteCoordinate: GeoCoordinate,
        distanceMeters: Double,
        bearingToRouteDegrees: Double
    ) {
        self.nearestRouteCoordinate = nearestRouteCoordinate
        self.distanceMeters = distanceMeters
        self.bearingToRouteDegrees = bearingToRouteDegrees
    }
}

/// An observation candidate. `JourneyContextStore` remains the only progress writer.
public struct CachedRouteProgressObservation: Equatable, Sendable {
    public let navigationObservation: NavigationObservation
    public let arrived: Bool
    public let returnGuidance: RouteReturnGuidance?

    public init(
        navigationObservation: NavigationObservation,
        arrived: Bool,
        returnGuidance: RouteReturnGuidance?
    ) {
        self.navigationObservation = navigationObservation
        self.arrived = arrived
        self.returnGuidance = returnGuidance
    }
}

/// Pure geometry for following a previously accepted cached route.
public struct RouteProgressEngine: Sendable {
    private struct Segment: Sendable {
        let start: GeoCoordinate
        let end: GeoCoordinate
        let lengthMeters: Double
        let cumulativeStartMeters: Double
    }

    private struct Projection {
        let coordinate: GeoCoordinate
        let distanceMeters: Double
        let distanceAlongRouteMeters: Double
    }

    private static let earthRadiusMeters = 6_371_008.8

    public let route: AcceptedNavigationRoute
    public let configuration: RouteProgressConfiguration
    public let totalDistanceMeters: Double

    private let segments: [Segment]

    public init(
        route: AcceptedNavigationRoute,
        configuration: RouteProgressConfiguration = .init()
    ) throws {
        guard route.cached,
              route.coordinates.count >= 2,
              route.coordinates.allSatisfy(Self.isValid)
        else {
            throw NavigationError.invalidCachedRoute
        }

        var builtSegments: [Segment] = []
        var cumulativeDistance = 0.0

        for (start, end) in zip(route.coordinates, route.coordinates.dropFirst()) {
            let length = Self.haversineDistance(from: start, to: end)
            guard length.isFinite else {
                throw NavigationError.invalidCachedRoute
            }
            guard length > 0 else { continue }

            builtSegments.append(
                Segment(
                    start: start,
                    end: end,
                    lengthMeters: length,
                    cumulativeStartMeters: cumulativeDistance
                )
            )
            cumulativeDistance += length
        }

        guard !builtSegments.isEmpty, cumulativeDistance > 0 else {
            throw NavigationError.invalidCachedRoute
        }

        self.route = route
        self.configuration = configuration
        self.totalDistanceMeters = cumulativeDistance
        self.segments = builtSegments
    }

    public func observe(
        _ location: LocationObservation,
        session: NavigationSessionID
    ) throws -> CachedRouteProgressObservation {
        guard Self.isValid(location.coordinate),
              location.horizontalAccuracyMeters.isFinite,
              location.horizontalAccuracyMeters >= 0
        else {
            throw NavigationError.locationUnavailable
        }

        guard let projection = nearestProjection(to: location.coordinate) else {
            throw NavigationError.invalidCachedRoute
        }

        let accuracyAllowance = min(
            location.horizontalAccuracyMeters,
            configuration.maximumAccuracyAllowanceMeters
        )
        let effectiveOffRouteThreshold = configuration.offRouteThresholdMeters + accuracyAllowance
        let offRoute = projection.distanceMeters > effectiveOffRouteThreshold
        let progress = min(1, max(0, projection.distanceAlongRouteMeters / totalDistanceMeters))
        let remainingDistance = max(0, totalDistanceMeters - projection.distanceAlongRouteMeters)
        let arrived = !offRoute && remainingDistance <= configuration.arrivalThresholdMeters

        let baseObservation = NavigationObservation(
            sessionID: session,
            candidateProgress: progress,
            distanceToRouteMeters: projection.distanceMeters,
            offRoute: offRoute,
            nearestCoordinate: projection.coordinate
        )

        let returnGuidance: RouteReturnGuidance? = offRoute
            ? RouteReturnGuidance(
                nearestRouteCoordinate: projection.coordinate,
                distanceMeters: projection.distanceMeters,
                bearingToRouteDegrees: Self.initialBearing(
                    from: location.coordinate,
                    to: projection.coordinate
                )
            )
            : nil

        return CachedRouteProgressObservation(
            navigationObservation: baseObservation,
            arrived: arrived,
            returnGuidance: returnGuidance
        )
    }

    /// Where a fixed point sits along this route, as a fraction of its length.
    ///
    /// Stops are authored as coordinates, not as fractions: a fraction would go
    /// silently wrong the moment the route geometry changed, and the route is
    /// the thing that decides where its own stops fall.
    public func progressAlong(_ coordinate: GeoCoordinate) -> Double? {
        guard Self.isValid(coordinate), let projection = nearestProjection(to: coordinate) else {
            return nil
        }
        return min(1, max(0, projection.distanceAlongRouteMeters / totalDistanceMeters))
    }

    private func nearestProjection(to location: GeoCoordinate) -> Projection? {
        var best: Projection?

        for segment in segments {
            let meanLatitude = Self.degreesToRadians(
                (segment.start.latitude + segment.end.latitude + location.latitude) / 3
            )
            let metersPerRadianLongitude = Self.earthRadiusMeters * cos(meanLatitude)
            let startToEndLongitude = Self.normalizedLongitudeDelta(
                segment.end.longitude - segment.start.longitude
            )
            let startToLocationLongitude = Self.normalizedLongitudeDelta(
                location.longitude - segment.start.longitude
            )

            let endX = Self.degreesToRadians(startToEndLongitude) * metersPerRadianLongitude
            let endY = Self.degreesToRadians(segment.end.latitude - segment.start.latitude)
                * Self.earthRadiusMeters
            let locationX = Self.degreesToRadians(startToLocationLongitude) * metersPerRadianLongitude
            let locationY = Self.degreesToRadians(location.latitude - segment.start.latitude)
                * Self.earthRadiusMeters

            let squaredLength = endX * endX + endY * endY
            guard squaredLength > 0 else { continue }

            let rawFraction = (locationX * endX + locationY * endY) / squaredLength
            let fraction = min(1, max(0, rawFraction))
            let nearestLatitude = segment.start.latitude
                + fraction * (segment.end.latitude - segment.start.latitude)
            let nearestLongitude = Self.normalizedLongitude(
                segment.start.longitude + fraction * startToEndLongitude
            )
            let nearestCoordinate = GeoCoordinate(
                latitude: nearestLatitude,
                longitude: nearestLongitude
            )
            let distance = Self.haversineDistance(from: location, to: nearestCoordinate)
            let candidate = Projection(
                coordinate: nearestCoordinate,
                distanceMeters: distance,
                distanceAlongRouteMeters: segment.cumulativeStartMeters
                    + fraction * segment.lengthMeters
            )

            if best == nil || candidate.distanceMeters < best!.distanceMeters {
                best = candidate
            }
        }

        return best
    }

    private static func isValid(_ coordinate: GeoCoordinate) -> Bool {
        coordinate.latitude.isFinite
            && coordinate.longitude.isFinite
            && (-90...90).contains(coordinate.latitude)
            && (-180...180).contains(coordinate.longitude)
    }

    private static func haversineDistance(
        from start: GeoCoordinate,
        to end: GeoCoordinate
    ) -> Double {
        let startLatitude = degreesToRadians(start.latitude)
        let endLatitude = degreesToRadians(end.latitude)
        let latitudeDelta = endLatitude - startLatitude
        let longitudeDelta = degreesToRadians(
            normalizedLongitudeDelta(end.longitude - start.longitude)
        )
        let a = sin(latitudeDelta / 2) * sin(latitudeDelta / 2)
            + cos(startLatitude) * cos(endLatitude)
            * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        return 2 * earthRadiusMeters * atan2(sqrt(a), sqrt(max(0, 1 - a)))
    }

    private static func initialBearing(
        from start: GeoCoordinate,
        to end: GeoCoordinate
    ) -> Double {
        let startLatitude = degreesToRadians(start.latitude)
        let endLatitude = degreesToRadians(end.latitude)
        let longitudeDelta = degreesToRadians(
            normalizedLongitudeDelta(end.longitude - start.longitude)
        )
        let y = sin(longitudeDelta) * cos(endLatitude)
        let x = cos(startLatitude) * sin(endLatitude)
            - sin(startLatitude) * cos(endLatitude) * cos(longitudeDelta)
        let bearing = atan2(y, x) * 180 / .pi
        return (bearing + 360).truncatingRemainder(dividingBy: 360)
    }

    private static func normalizedLongitudeDelta(_ longitude: Double) -> Double {
        var result = longitude.truncatingRemainder(dividingBy: 360)
        if result > 180 { result -= 360 }
        if result < -180 { result += 360 }
        return result
    }

    private static func normalizedLongitude(_ longitude: Double) -> Double {
        var result = (longitude + 180).truncatingRemainder(dividingBy: 360)
        if result < 0 { result += 360 }
        return result - 180
    }

    private static func degreesToRadians(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }
}
