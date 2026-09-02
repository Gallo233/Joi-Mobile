import CompanionCore
import MapKit

/// Pure geometry for presenting the cached route on a native map.
///
/// Navigation truth stays in `RouteProgressEngine`. These helpers only decide
/// what part of that truth is visible: a padded viewport and the polyline up to
/// the engine's reported progress.
enum MapRoutePresentation {
    static func coordinate(_ point: GeoCoordinate) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
    }

    static func routeRect(for coordinates: [GeoCoordinate]) -> MKMapRect {
        let points = coordinates.map { MKMapPoint(coordinate($0)) }
        guard let first = points.first else { return .world }

        let minX = points.reduce(first.x) { min($0, $1.x) }
        let maxX = points.reduce(first.x) { max($0, $1.x) }
        let minY = points.reduce(first.y) { min($0, $1.y) }
        let maxY = points.reduce(first.y) { max($0, $1.y) }
        let center = MKMapPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        let latitude = coordinates.reduce(0) { $0 + $1.latitude } / Double(coordinates.count)
        let minimumSide = 450 * MKMapPointsPerMeterAtLatitude(latitude)
        let width = max(maxX - minX, minimumSide)
        let height = max(maxY - minY, minimumSide)

        // Forty percent around the route keeps the line and marker labels away
        // from the map chrome without pretending the viewport is a route bound.
        return MKMapRect(
            x: center.x - width * 0.7,
            y: center.y - height * 0.7,
            width: width * 1.4,
            height: height * 1.4
        )
    }

    static func userRegion(around coordinate: GeoCoordinate) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: self.coordinate(coordinate),
            latitudinalMeters: 650,
            longitudinalMeters: 650
        )
    }

    static func searchResultRegion(around coordinate: GeoCoordinate) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: self.coordinate(coordinate),
            latitudinalMeters: 800,
            longitudinalMeters: 800
        )
    }

    static func routeStopRegion(around coordinate: GeoCoordinate) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: self.coordinate(coordinate),
            latitudinalMeters: 550,
            longitudinalMeters: 550
        )
    }

    /// Returns a path ending exactly at `progress`, rather than merely choosing
    /// the nearest authored waypoint. That keeps the visible walked portion in
    /// lockstep with the progress percentage emitted by the route engine.
    static func completedCoordinates(
        from coordinates: [GeoCoordinate],
        progress: Double
    ) -> [CLLocationCoordinate2D] {
        guard let first = coordinates.first else { return [] }
        guard coordinates.count > 1 else { return [coordinate(first)] }

        let clamped = min(max(progress, 0), 1)
        if clamped == 0 { return [coordinate(first)] }
        if clamped == 1 { return coordinates.map(coordinate) }

        let points = coordinates.map { MKMapPoint(coordinate($0)) }
        let lengths = zip(points, points.dropFirst()).map { $0.distance(to: $1) }
        let target = lengths.reduce(0, +) * clamped
        var travelled = 0.0
        var result = [coordinate(first)]

        for index in lengths.indices {
            let segment = lengths[index]
            if travelled + segment < target {
                result.append(coordinate(coordinates[index + 1]))
                travelled += segment
                continue
            }

            let fraction = segment > 0 ? (target - travelled) / segment : 0
            let start = points[index]
            let end = points[index + 1]
            result.append(
                MKMapPoint(
                    x: start.x + (end.x - start.x) * fraction,
                    y: start.y + (end.y - start.y) * fraction
                ).coordinate
            )
            break
        }
        return result
    }
}
