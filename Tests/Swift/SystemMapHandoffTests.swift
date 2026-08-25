import CompanionCore
import XCTest
@testable import JoiMobile

@MainActor
final class SystemMapHandoffTests: XCTestCase {
    func testProposalIsInspectOnlyAndCancellationNeverOpensSystemMaps() {
        let opener = SystemMapOpenerStub(result: true)
        let model = SystemMapHandoffModel(opener: opener)
        let destination = Self.destination

        model.proposeDriving(to: destination)

        XCTAssertEqual(model.phase, .confirming(destination))
        XCTAssertEqual(opener.destinations, [])

        model.cancel()

        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(opener.destinations, [])
    }

    func testConfirmationHandsTheExactDestinationToSystemMapsOnlyOnce() {
        let opener = SystemMapOpenerStub(result: true)
        let model = SystemMapHandoffModel(opener: opener)

        model.proposeDriving(to: Self.destination)
        XCTAssertTrue(model.confirm())
        XCTAssertFalse(model.confirm(), "a dismissed confirmation cannot launch twice")

        XCTAssertEqual(opener.destinations, [Self.destination])
        XCTAssertEqual(model.phase, .idle)
    }

    func testSystemRefusalKeepsTheDestinationRecoverableAndRetryIsExplicit() {
        let opener = SystemMapOpenerStub(result: false)
        let model = SystemMapHandoffModel(opener: opener)

        model.proposeDriving(to: Self.destination)
        XCTAssertFalse(model.confirm())

        XCTAssertEqual(model.phase, .failed(Self.destination))
        XCTAssertEqual(opener.destinations, [Self.destination])

        model.proposeDriving(to: Self.destination)
        XCTAssertEqual(model.phase, .confirming(Self.destination))
        XCTAssertEqual(opener.destinations, [Self.destination], "retry still needs confirmation")
    }

    func testInvalidDestinationNeverReachesSystemMaps() {
        let opener = SystemMapOpenerStub(result: true)
        let model = SystemMapHandoffModel(opener: opener)
        let invalid = MapSearchResult(
            id: "invalid",
            name: "无效地点",
            subtitle: nil,
            coordinate: GeoCoordinate(latitude: 200, longitude: 121.47)
        )

        model.proposeDriving(to: invalid)
        XCTAssertFalse(model.confirm())

        XCTAssertEqual(model.phase, .failed(invalid))
        XCTAssertEqual(opener.destinations, [])
    }

    private static let destination = MapSearchResult(
        id: "museum",
        name: "上海博物馆（人民广场馆）",
        subtitle: "上海市黄浦区人民大道 201 号",
        coordinate: GeoCoordinate(latitude: 31.230_288, longitude: 121.470_024)
    )
}

@MainActor
private final class SystemMapOpenerStub: SystemMapOpening {
    private let result: Bool
    private(set) var destinations: [MapSearchResult] = []

    init(result: Bool) { self.result = result }

    func openDrivingDirections(to destination: MapSearchResult) -> Bool {
        destinations.append(destination)
        return result
    }
}
