import CompanionCore
import Foundation
import OfflinePack

/// One cached cultural walk, and where the user is along it.
///
/// This is the product shape of DEC-004: a downloaded route can be shown,
/// advanced along, and departed from — with guidance back — and nothing here
/// plans a new one. `RouteProgressEngine` decides progress and departure;
/// `JourneyContextStore` remains the only thing that records it.
struct CachedWalk {
    let route: AcceptedNavigationRoute
    let title: String
    /// What the character says on arrival. Cached with the route, not fetched.
    let arrivalNote: String
    /// Built once, because the engine validates the route: a `CachedWalk` cannot
    /// exist for a route that is not cached or has too few usable coordinates.
    let engine: RouteProgressEngine
    /// The ordered story this route tells (`G2-J4B`).
    let narrative: RouteNarrative

    init(
        route: AcceptedNavigationRoute,
        title: String,
        arrivalNote: String,
        stops: [RouteStop]
    ) throws {
        self.route = route
        self.title = title
        self.arrivalNote = arrivalNote
        // Thresholds are the engine's own defaults: departure and arrival are its
        // decision, not something the view re-invents.
        engine = try RouteProgressEngine(route: route, configuration: RouteProgressConfiguration())
        narrative = try RouteNarrative(engine: engine, stops: stops)
    }

    /// A short demonstration walk, bundled rather than downloaded.
    ///
    /// It is labelled as a sample everywhere it is shown: a real travel pack
    /// arrives through `TravelPackManifestV1` with its own rights receipt, and
    /// presenting this as downloaded content would be the kind of claim this
    /// repository refuses to make. The coordinates trace a short riverside path
    /// so a walk can be followed end to end without any network.
    ///
    /// Force-tried because every input is a literal in this file and the throw
    /// can only mean the constant below was edited into an invalid route.
    /// `CachedWalkTests` constructs it, so that mistake fails a test rather than
    /// reaching a device.
    static let sample = try! CachedWalk(
        route: AcceptedNavigationRoute(
            routeID: "sample.riverside",
            coordinates: [
                GeoCoordinate(latitude: 31.2304, longitude: 121.4737),
                GeoCoordinate(latitude: 31.2312, longitude: 121.4749),
                GeoCoordinate(latitude: 31.2325, longitude: 121.4761),
                GeoCoordinate(latitude: 31.2338, longitude: 121.4770),
                GeoCoordinate(latitude: 31.2351, longitude: 121.4776),
            ],
            cached: true
        ),
        title: String(localized: "示例：外滩滨江步行"),
        arrivalNote: String(localized: "到了。这段路就走到这里。"),
        // Mostly the character's own words. A bundled sample is not a
        // rights-cleared travel pack, so it makes almost no factual claims — and
        // the one that it does carries a repository-authored fixture revision
        // that names itself as such, rather than borrowing someone's research.
        stops: [
            RouteStop(
                stopID: "sample.riverside.start",
                name: String(localized: "起点：江边台阶"),
                coordinate: GeoCoordinate(latitude: 31.2304, longitude: 121.4737),
                narration: String(localized: "从这里开始。风是从水面上来的，走两步就习惯了。"),
                suggestedDurationSeconds: 120
            ),
            RouteStop(
                stopID: "sample.riverside.embankment",
                name: String(localized: "堤岸"),
                coordinate: GeoCoordinate(latitude: 31.2325, longitude: 121.4761),
                narration: String(localized: "这段堤岸是二十世纪初修的，示例资料如此记载。"),
                sourceRevisionIDs: ["fixture://sources/bund-history@2026-08-18"],
                suggestedDurationSeconds: 180
            ),
            RouteStop(
                stopID: "sample.riverside.end",
                name: String(localized: "终点：转角"),
                coordinate: GeoCoordinate(latitude: 31.2351, longitude: 121.4776),
                narration: String(localized: "走到这个转角，江面一下子就宽了。我喜欢在这里停一会儿。"),
                suggestedDurationSeconds: 120
            ),
        ]
    )

    /// The walk a verified travel pack describes (`G2-J4C`).
    ///
    /// Everything here was checked by `TravelPackInstaller` before the pack was
    /// sealed — the route is long enough to follow and every stop projects onto
    /// it — so this cannot fail for a pack that installed. It still throws
    /// rather than force-trying, because a `CachedWalk` that could not be built
    /// is a bug worth surfacing, not a crash worth shipping.
    init(pack: InstalledTravelPack) throws {
        try self.init(
            route: pack.route,
            title: pack.title,
            arrivalNote: String(localized: "到了。这段路就走到这里。"),
            stops: pack.stops
        )
    }

    /// Route coordinates projected into a unit square for drawing, preserving
    /// aspect at this latitude so the corridor is not visibly stretched.
    ///
    /// Deliberately not a map: there are no tiles, no basemap and no claim to
    /// one. It is the shape of the route and where you are on it, which is what
    /// the cached-corridor promise actually covers.
    func normalizedPath(aspect: Double) -> [(x: Double, y: Double)] {
        Self.normalize(route.coordinates, aspect: aspect)
    }

    func normalizedPoint(_ coordinate: GeoCoordinate, aspect: Double) -> (x: Double, y: Double)? {
        Self.normalize(route.coordinates + [coordinate], aspect: aspect).last
    }

    private static func normalize(
        _ coordinates: [GeoCoordinate],
        aspect: Double
    ) -> [(x: Double, y: Double)] {
        guard let first = coordinates.first else { return [] }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for point in coordinates {
            minLat = min(minLat, point.latitude); maxLat = max(maxLat, point.latitude)
            minLon = min(minLon, point.longitude); maxLon = max(maxLon, point.longitude)
        }
        // Longitude degrees are shorter than latitude degrees away from the
        // equator, so they are scaled by cos(latitude) before fitting.
        let latitudeScale = cos((minLat + maxLat) / 2 * .pi / 180)
        let width = max((maxLon - minLon) * latitudeScale, 1e-9)
        let height = max(maxLat - minLat, 1e-9)
        let span = max(width / max(aspect, 1e-9), height)
        return coordinates.map { point in
            let x = ((point.longitude - minLon) * latitudeScale / span / max(aspect, 1e-9))
            let y = ((point.latitude - minLat) / span)
            // 0.1…0.9 keeps the drawn corridor inside its card with a margin.
            return (x: 0.1 + x * 0.8, y: 0.9 - y * 0.8)
        }
    }
}
