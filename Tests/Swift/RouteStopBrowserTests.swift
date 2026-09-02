import XCTest
@testable import JoiMobile

final class RouteStopBrowserTests: XCTestCase {
    private let routeA = "route-a"
    private let routeB = "route-b"
    private let stops = ["a", "b", "c"]

    func testSelectionAcceptsOnlyAStopOnTheCurrentRoute() {
        var browser = RouteStopBrowser()

        XCTAssertTrue(browser.select(stopID: "b", routeID: routeA, stopIDs: stops))
        XCTAssertEqual(browser.selectedStopID, "b")
        XCTAssertFalse(browser.select(stopID: "stale", routeID: routeA, stopIDs: stops))
        XCTAssertNil(browser.selectedStopID)
    }

    func testChangingRouteClearsTheOldSelection() {
        var browser = RouteStopBrowser()
        browser.select(stopID: "b", routeID: routeA, stopIDs: stops)

        browser.synchronize(routeID: routeB, stopIDs: ["b", "d"])

        XCTAssertEqual(browser.routeID, routeB)
        XCTAssertNil(browser.selectedStopID, "the same stop ID cannot carry authority across routes")
    }

    func testRemovingAStopClearsAStaleSelection() {
        var browser = RouteStopBrowser()
        browser.select(stopID: "b", routeID: routeA, stopIDs: stops)

        browser.synchronize(routeID: routeA, stopIDs: ["a", "c"])

        XCTAssertNil(browser.selectedStopID)
    }

    func testPreviousAndNextFollowCurrentNarrativeOrderWithoutWrapping() {
        var browser = RouteStopBrowser()
        browser.select(stopID: "b", routeID: routeA, stopIDs: stops)

        XCTAssertEqual(browser.move(by: 1, routeID: routeA, stopIDs: stops), "c")
        XCTAssertEqual(browser.move(by: 1, routeID: routeA, stopIDs: stops), "c")
        XCTAssertEqual(browser.move(by: -1, routeID: routeA, stopIDs: stops), "b")

        let reordered = ["c", "b", "a"]
        XCTAssertEqual(browser.move(by: 1, routeID: routeA, stopIDs: reordered), "a")
    }

    func testBrowsingDoesNotMutateNarrativeProgress() {
        let narrative = CachedWalk.sample.narrative.state(currentProgress: 0, furthestProgress: 0)
        var browser = RouteStopBrowser()
        let stopIDs = narrative.stops.map(\.stop.stopID)

        browser.select(stopID: stopIDs[1], routeID: routeA, stopIDs: stopIDs)
        _ = browser.move(by: 1, routeID: routeA, stopIDs: stopIDs)

        XCTAssertEqual(
            CachedWalk.sample.narrative.state(currentProgress: 0, furthestProgress: 0),
            narrative,
            "inspection cannot mark a stop complete or advance route progress"
        )
    }
}
