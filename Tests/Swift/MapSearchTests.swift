import CompanionCore
import MapKit
import XCTest
@testable import JoiMobile

@MainActor
final class MapSearchTests: XCTestCase {
    private let region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 31.231, longitude: 121.474),
        latitudinalMeters: 2_000,
        longitudinalMeters: 2_000
    )

    func testBlankQueryDoesNotReachAppleAdapter() async {
        let provider = SearchProviderStub { _, _ in XCTFail("blank query searched"); return [] }
        let model = MapSearchModel(provider: provider)
        model.query = "  \n "

        model.submit(reachability: .interfaceAvailable, region: region)

        XCTAssertEqual(model.query, "")
        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(provider.queries, [])
    }

    func testPreparedChatHandoffPrefillsWithoutReachingAppleAdapter() async {
        let provider = SearchProviderStub { _, _ in XCTFail("prefill searched"); return [] }
        let model = MapSearchModel(provider: provider)

        model.prepare(query: "  上海博物馆  ")

        XCTAssertEqual(model.query, "上海博物馆")
        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(provider.queries, [], "only the later Search action may contact the provider")
    }

    func testKnownOfflineRefusesBeforeSearchAndKeepsTrimmedQuery() async {
        let provider = SearchProviderStub { _, _ in XCTFail("offline query searched"); return [] }
        let model = MapSearchModel(provider: provider)
        model.query = "  上海博物馆  "

        model.submit(reachability: .unreachable, region: region)

        XCTAssertEqual(model.query, "上海博物馆")
        XCTAssertEqual(model.phase, .offline)
        XCTAssertEqual(provider.queries, [])
    }

    func testUnknownNetworkMayAttemptAndForwardsOnlyTheSuppliedRouteRegion() async throws {
        let result = Self.result(id: "museum", name: "上海博物馆")
        let provider = SearchProviderStub { _, _ in [result] }
        let model = MapSearchModel(provider: provider)
        model.query = "上海博物馆"

        model.submit(reachability: .unknown, region: region)
        await settle(model)

        XCTAssertEqual(model.phase, .results([result]))
        XCTAssertEqual(provider.queries, ["上海博物馆"])
        let requestedRegion = try XCTUnwrap(provider.regions.first)
        XCTAssertEqual(requestedRegion.center.latitude, region.center.latitude, accuracy: 0.000_001)
        XCTAssertEqual(requestedRegion.center.longitude, region.center.longitude, accuracy: 0.000_001)
    }

    func testResultsAreBoundedToTwelve() async {
        let results = (0..<20).map { Self.result(id: "\($0)", name: "地点 \($0)") }
        let model = MapSearchModel(provider: SearchProviderStub { _, _ in results })
        model.query = "地点"

        model.submit(reachability: .interfaceAvailable, region: region)
        await settle(model)

        guard case let .results(bounded) = model.phase else { return XCTFail("missing results") }
        XCTAssertEqual(bounded.count, MapSearchModel.maximumResults)
        XCTAssertEqual(bounded.last?.id, "11")
    }

    func testEmptyAndFailureAreDifferentRecoverableStates() async {
        let empty = MapSearchModel(provider: SearchProviderStub { _, _ in [] })
        empty.query = "不存在的地点"
        empty.submit(reachability: .interfaceAvailable, region: region)
        await settle(empty)
        XCTAssertEqual(empty.phase, .empty(query: "不存在的地点"))

        let failed = MapSearchModel(provider: SearchProviderStub { _, _ in throw SearchFailure.offlineService })
        failed.query = "上海博物馆"
        failed.submit(reachability: .interfaceAvailable, region: region)
        await settle(failed)
        XCTAssertEqual(failed.phase, .failed)
    }

    func testCancelledOlderSearchCannotOverwriteNewerResult() async throws {
        let old = Self.result(id: "old", name: "旧结果")
        let new = Self.result(id: "new", name: "新结果")
        let provider = SearchProviderStub { query, _ in
            if query == "旧查询" {
                do { try await Task.sleep(for: .milliseconds(80)) } catch { /* imitate a provider that returns late */ }
                return [old]
            }
            return [new]
        }
        let model = MapSearchModel(provider: provider)
        model.query = "旧查询"
        model.submit(reachability: .interfaceAvailable, region: region)
        await Task.yield()
        model.query = "新查询"
        model.submit(reachability: .interfaceAvailable, region: region)

        await settle(model)
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(model.phase, .results([new]))
        XCTAssertEqual(provider.queries, ["旧查询", "新查询"])
    }

    func testClosingSearchCancelsAndForgetsTheQuery() async {
        let provider = SearchProviderStub { _, _ in
            try await Task.sleep(for: .seconds(1))
            return [Self.result(id: "late", name: "晚到结果")]
        }
        let model = MapSearchModel(provider: provider)
        model.query = "不应保留"
        model.submit(reachability: .interfaceAvailable, region: region)

        model.clear()
        await Task.yield()

        XCTAssertEqual(model.query, "")
        XCTAssertEqual(model.phase, .idle)
    }

    private func settle(_ model: MapSearchModel) async {
        for _ in 0..<100 where model.phase.isLoading {
            await Task.yield()
        }
    }

    private static func result(id: String, name: String) -> MapSearchResult {
        MapSearchResult(
            id: id,
            name: name,
            subtitle: "上海市黄浦区",
            coordinate: GeoCoordinate(latitude: 31.23, longitude: 121.47)
        )
    }
}

@MainActor
private final class SearchProviderStub: MapSearchProviding {
    typealias Handler = @MainActor (String, MKCoordinateRegion) async throws -> [MapSearchResult]

    private let handler: Handler
    private(set) var queries: [String] = []
    private(set) var regions: [MKCoordinateRegion] = []

    init(handler: @escaping Handler) { self.handler = handler }

    func search(query: String, region: MKCoordinateRegion) async throws -> [MapSearchResult] {
        queries.append(query)
        regions.append(region)
        return try await handler(query, region)
    }
}

private enum SearchFailure: Error {
    case offlineService
}
