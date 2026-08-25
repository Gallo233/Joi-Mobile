import CompanionCore
import MapKit
import XCTest
@testable import JoiMobile

/// Presentation geometry for the native MapKit surface. Navigation progress is
/// tested at its owner; these tests make sure the map neither crops the accepted
/// route nor paints a completed path past the progress it was handed.
final class MapPresentationTests: XCTestCase {
    func testRouteViewportContainsEveryCoordinateAndHasUsefulPadding() {
        let coordinates = CachedWalk.sample.route.coordinates
        let rect = MapRoutePresentation.routeRect(for: coordinates)

        XCTAssertFalse(rect.isNull)
        XCTAssertGreaterThan(rect.width, 0)
        XCTAssertGreaterThan(rect.height, 0)
        for coordinate in coordinates {
            XCTAssertTrue(rect.contains(MKMapPoint(MapRoutePresentation.coordinate(coordinate))))
        }
    }

    func testCompletedPolylineEndsAtExactProgressBetweenWaypoints() throws {
        let coordinates = [
            GeoCoordinate(latitude: 31.23, longitude: 121.47),
            GeoCoordinate(latitude: 31.23, longitude: 121.48),
        ]

        let path = MapRoutePresentation.completedCoordinates(from: coordinates, progress: 0.5)
        XCTAssertEqual(path.count, 2)
        XCTAssertEqual(path[0].latitude, 31.23, accuracy: 0.000_001)
        XCTAssertEqual(path[0].longitude, 121.47, accuracy: 0.000_001)
        XCTAssertEqual(path[1].latitude, 31.23, accuracy: 0.000_001)
        XCTAssertEqual(path[1].longitude, 121.475, accuracy: 0.000_001)
    }

    func testCompletedPolylineClampsBeforeStartAndAfterFinish() {
        let coordinates = CachedWalk.sample.route.coordinates

        let beforeStart = MapRoutePresentation.completedCoordinates(from: coordinates, progress: -1)
        XCTAssertEqual(beforeStart.count, 1)
        XCTAssertEqual(beforeStart[0].latitude, coordinates[0].latitude, accuracy: 0.000_001)
        XCTAssertEqual(beforeStart[0].longitude, coordinates[0].longitude, accuracy: 0.000_001)

        let afterFinish = MapRoutePresentation.completedCoordinates(from: coordinates, progress: 2)
        XCTAssertEqual(afterFinish.count, coordinates.count)
        XCTAssertEqual(afterFinish.last?.latitude, coordinates.last?.latitude)
        XCTAssertEqual(afterFinish.last?.longitude, coordinates.last?.longitude)
    }

    func testUserRegionCentersOnTheObservedLocation() {
        let coordinate = GeoCoordinate(latitude: 31.2304, longitude: 121.4737)
        let region = MapRoutePresentation.userRegion(around: coordinate)

        XCTAssertEqual(region.center.latitude, coordinate.latitude, accuracy: 0.000_001)
        XCTAssertEqual(region.center.longitude, coordinate.longitude, accuracy: 0.000_001)
        XCTAssertGreaterThan(region.span.latitudeDelta, 0)
        XCTAssertGreaterThan(region.span.longitudeDelta, 0)
    }

    func testSearchResultRegionCentersOnTheSelectedPlace() {
        let coordinate = GeoCoordinate(latitude: 31.2285, longitude: 121.4751)
        let region = MapRoutePresentation.searchResultRegion(around: coordinate)

        XCTAssertEqual(region.center.latitude, coordinate.latitude, accuracy: 0.000_001)
        XCTAssertEqual(region.center.longitude, coordinate.longitude, accuracy: 0.000_001)
        XCTAssertGreaterThan(region.span.latitudeDelta, 0)
        XCTAssertGreaterThan(region.span.longitudeDelta, 0)
    }
}
