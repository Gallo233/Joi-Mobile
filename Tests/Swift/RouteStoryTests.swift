import CompanionCore
import Foundation
import OfflinePack
import XCTest
@testable import JoiMobile

/// `G2-J4B` — the walk as a story, at the App boundary.
///
/// `RouteNarrativeTests` in OfflinePack covers the rules. These cover what it
/// cannot: that the App keeps a high-water mark rather than recomputing
/// completion from wherever the walker is standing, that the bundled sample is
/// a usable tour, and that only a sourced recap fact can be kept.
@MainActor
final class RouteStoryTests: XCTestCase {
    /// The sample walk's stops are force-constructed at a `static let`, so this
    /// is what keeps that safe: a stop edited off the route fails here instead
    /// of trapping on a device.
    func testTheBundledSampleIsAUsableTour() {
        let walk = CachedWalk.sample
        XCTAssertGreaterThanOrEqual(walk.narrative.stops.count, 2)
        XCTAssertEqual(
            walk.narrative.stops.map(\.progressAlongRoute).sorted(),
            walk.narrative.stops.map(\.progressAlongRoute),
            "stops come out in route order"
        )
        for entry in walk.narrative.stops {
            XCTAssertFalse(entry.stop.name.isEmpty)
            XCTAssertFalse(entry.stop.narration.isEmpty)
            XCTAssertGreaterThan(entry.stop.suggestedDurationSeconds, 0)
        }
    }

    /// A bundled sample is not a rights-cleared travel pack, so it must not make
    /// factual claims it cannot support. The one stop that does carries a
    /// repository-authored fixture revision that names itself as such.
    func testTheSampleMakesAlmostNoFactualClaimsAndLabelsTheOneItDoes() {
        let stops = CachedWalk.sample.narrative.stops.map(\.stop)
        let factual = stops.filter(\.isFactual)
        XCTAssertLessThanOrEqual(factual.count, 1, "a sample walk is not a researched tour")
        for stop in factual {
            for revision in stop.sourceRevisionIDs {
                XCTAssertTrue(
                    revision.hasPrefix("fixture://"),
                    "a sample's source must announce that it is a fixture: \(revision)"
                )
            }
        }
        for stop in stops where !stop.isFactual {
            XCTAssertTrue(stop.sourceRevisionIDs.isEmpty)
        }
    }

    /// `J4B-03` at the App boundary — the walk keeps the furthest point reached,
    /// so doubling back does not un-visit stops and the recap does not shrink.
    func testTheAppKeepsAHighWaterMarkRatherThanTheCurrentPosition() async throws {
        let model = AppModel()
        model.startWalk()
        XCTAssertEqual(model.furthestWalkProgress, 0)

        try Self.walk(model, to: CachedWalk.sample.route.coordinates.last!)
        let atEnd = model.furthestWalkProgress
        XCTAssertGreaterThan(atEnd, 0.9)
        let recapAtEnd = model.walkRecap
        XCTAssertEqual(recapAtEnd.count, CachedWalk.sample.narrative.stops.count)

        // Walk back to the start.
        try Self.walk(model, to: CachedWalk.sample.route.coordinates.first!)
        XCTAssertEqual(model.furthestWalkProgress, atEnd, "the furthest point does not go backwards")
        XCTAssertEqual(model.walkRecap.count, recapAtEnd.count, "the tour was still walked")
        XCTAssertTrue(model.narrativeState.isComplete)
        XCTAssertEqual(
            model.narrativeState.currentStop?.stopID,
            "sample.riverside.start",
            "but you are standing back at the first stop"
        )
    }

    /// Starting a new walk starts a new story; the previous walk's recap does
    /// not carry over into it.
    func testANewWalkStartsANewStory() async throws {
        let model = AppModel()
        model.startWalk()
        try Self.walk(model, to: CachedWalk.sample.route.coordinates.last!)
        XCTAssertFalse(model.walkRecap.isEmpty)

        model.stopWalk()
        model.startWalk()

        XCTAssertEqual(model.furthestWalkProgress, 0)
        XCTAssertFalse(model.narrativeState.isComplete)
        // Back at the trailhead, which is itself the first stop — standing there
        // is reaching it. So the new story is one stop long, not zero.
        XCTAssertEqual(model.narrativeState.completedCount, 1)
        XCTAssertEqual(model.walkRecap.map(\.stopID), ["sample.riverside.start"])
    }

    // MARK: - Keeping a recap fact

    /// `J4B-06` — a sourced fact may be kept, and arrives as a `travelRecap`
    /// proposal rather than being written.
    func testASourcedRecapFactOpensATravelRecapProposal() async throws {
        let model = AppModel(memoryStore: RecordingStore())
        model.startWalk()
        try Self.walk(model, to: CachedWalk.sample.route.coordinates.last!)

        let fact = try XCTUnwrap(model.walkRecap.first(where: \.isFact))
        await model.proposeMemory(from: fact)

        let proposal = try XCTUnwrap(model.memoryProposal)
        XCTAssertEqual(proposal.proposal.category, .travelRecap)
        XCTAssertEqual(model.memoryCategory, .travelRecap)
        XCTAssertFalse(proposal.proposal.reason.isEmpty, "a durable item records why it exists")
        // Still a proposal: nothing is durable until it is accepted.
        XCTAssertTrue(model.memories.isEmpty)
    }

    /// `J4B-06` — the character's passing remark is not a trip fact and cannot
    /// be kept as one.
    func testAReflectionCannotBeKept() async throws {
        let model = AppModel(memoryStore: RecordingStore())
        model.startWalk()
        try Self.walk(model, to: CachedWalk.sample.route.coordinates.last!)

        let reflection = try XCTUnwrap(model.walkRecap.first(where: { !$0.isFact }))
        await model.proposeMemory(from: reflection)

        XCTAssertNil(model.memoryProposal, "a reflection is not something the trip taught you")
    }

    // MARK: - Helpers

    /// Feeds one reading through the model's real `advanceWalk` path, under the
    /// walk's own session — the same call the location provider makes.
    private static func walk(_ model: AppModel, to coordinate: GeoCoordinate) throws {
        let session = try XCTUnwrap(model.walkSession)
        model.advanceWalk(
            with: LocationObservation(
                coordinate: coordinate,
                horizontalAccuracyMeters: 5,
                observedAt: Date()
            ),
            session: session
        )
    }
}

private actor RecordingStore: MemoryRepository {
    private var records: [MemoryRecordV1] = []
    func list(characterID: String) async throws -> [MemoryRecordV1] {
        records.filter { $0.characterID == characterID }
    }
    func save(_ record: MemoryRecordV1, authorizationDigest _: String?) async throws {
        records.append(record)
    }
    func delete(recordID: String) async throws { records.removeAll { $0.recordID == recordID } }
    func export() async throws -> [MemoryRecordV1] { records }
}
