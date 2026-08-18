import CompanionCore
import Foundation
import OfflinePack
import XCTest
@testable import JoiMobile

/// `G2-J5D` — arrive-and-tell at the App boundary.
///
/// `PlaceResolverTests` covers the rule. These cover what the App does with it:
/// that a confident proposal settles itself, that an ambiguous one waits, that a
/// correction outranks every later reading, and that walking away clears it.
@MainActor
final class ArriveAndTellTests: XCTestCase {
    /// Arriving at a stop with a good fix settles it without asking.
    func testArrivingAtAStopConfirmsItWithoutAsking() throws {
        let model = AppModel()
        model.startWalk()
        let stop = try XCTUnwrap(model.walk.narrative.stops.first?.stop)

        try Self.stand(model, at: stop.coordinate, accuracy: 5)

        XCTAssertEqual(model.confirmedPlace?.stop.stopID, stop.stopID)
        XCTAssertFalse(model.confirmedPlace?.wasCorrected ?? true, "an arrival is not a correction")
        XCTAssertFalse(model.placeProposal.needsConfirmation)
    }

    /// Between stops there is nothing to confirm, and saying nothing is right.
    func testWalkingBetweenStopsConfirmsNothing() throws {
        let model = AppModel()
        model.startWalk()

        try Self.stand(model, at: GeoCoordinate(latitude: 31.5, longitude: 121.9), accuracy: 5)

        XCTAssertNil(model.confirmedPlace)
        XCTAssertEqual(model.placeProposal, .betweenStops)
    }

    /// `FAIL-017` — a fix too poor to single out a stop does not auto-confirm
    /// one, and keeps its candidates for the user to choose from.
    func testAPoorFixDoesNotAutoConfirmAndKeepsItsCandidates() throws {
        let model = AppModel()
        model.startWalk()
        let stop = try XCTUnwrap(model.walk.narrative.stops.first?.stop)

        try Self.stand(model, at: stop.coordinate, accuracy: 2_000)

        XCTAssertNil(model.confirmedPlace, "drift must not auto-confirm")
        XCTAssertTrue(model.placeProposal.needsConfirmation)
        XCTAssertFalse(model.placeProposal.candidates.isEmpty, "the candidate set is preserved")
    }

    /// The user answers an ambiguous proposal, and that answer is authoritative.
    func testConfirmingAnAmbiguousProposalSettlesIt() throws {
        let model = AppModel()
        model.startWalk()
        let stop = try XCTUnwrap(model.walk.narrative.stops.first?.stop)
        try Self.stand(model, at: stop.coordinate, accuracy: 2_000)
        XCTAssertNil(model.confirmedPlace)

        let chosen = try XCTUnwrap(model.placeProposal.candidates.first?.stop)
        model.confirmPlace(chosen)

        XCTAssertEqual(model.confirmedPlace?.stop.stopID, chosen.stopID)
        // Chosen from an ambiguous set rather than proposed outright, so it is
        // recorded as the user's correction of the product's uncertainty.
        XCTAssertTrue(model.confirmedPlace?.wasCorrected ?? false)
    }

    /// `FAIL-018` — a correction applies immediately and locally, and is not
    /// waiting on anything.
    func testACorrectionOverridesTheProposalImmediately() throws {
        let model = AppModel()
        model.startWalk()
        let stops = model.walk.narrative.stops.map(\.stop)
        let here = try XCTUnwrap(stops.first)
        let elsewhere = try XCTUnwrap(stops.last)
        XCTAssertNotEqual(here.stopID, elsewhere.stopID)

        try Self.stand(model, at: here.coordinate, accuracy: 5)
        XCTAssertEqual(model.confirmedPlace?.stop.stopID, here.stopID)

        model.confirmPlace(elsewhere)

        XCTAssertEqual(model.confirmedPlace?.stop.stopID, elsewhere.stopID)
        XCTAssertTrue(model.confirmedPlace?.wasCorrected ?? false)
    }

    /// A user's answer outranks later readings: drift must not silently move
    /// them to a different stop after they said where they were.
    func testALaterReadingDoesNotOverrideTheUsersAnswer() throws {
        let model = AppModel()
        model.startWalk()
        let stops = model.walk.narrative.stops.map(\.stop)
        let here = try XCTUnwrap(stops.first)
        let elsewhere = try XCTUnwrap(stops.last)

        try Self.stand(model, at: here.coordinate, accuracy: 5)
        model.confirmPlace(elsewhere)

        // A perfectly good reading, right on top of a different stop.
        try Self.stand(model, at: here.coordinate, accuracy: 5)

        XCTAssertEqual(
            model.confirmedPlace?.stop.stopID,
            elsewhere.stopID,
            "the user's own answer is not overwritten by a proposal"
        )
    }

    /// A correction survives readings that disagree with it; only the user
    /// takes it back.
    func testOnlyTheUserClearsACorrection() throws {
        let model = AppModel()
        model.startWalk()
        let stops = model.walk.narrative.stops.map(\.stop)
        let here = try XCTUnwrap(stops.first)
        let elsewhere = try XCTUnwrap(stops.last)

        try Self.stand(model, at: here.coordinate, accuracy: 5)
        model.confirmPlace(elsewhere)
        try Self.stand(model, at: GeoCoordinate(latitude: 31.5, longitude: 121.9), accuracy: 5)
        XCTAssertEqual(model.confirmedPlace?.stop.stopID, elsewhere.stopID, "walking does not undo a correction")

        model.clearConfirmedPlace()
        XCTAssertNil(model.confirmedPlace)
    }

    /// But walking away does retire an *automatic* confirmation: staying
    /// confirmed somewhere you have left is worse than saying nothing.
    func testWalkingAwayClearsAnAutomaticConfirmation() throws {
        let model = AppModel()
        model.startWalk()
        let stop = try XCTUnwrap(model.walk.narrative.stops.first?.stop)
        try Self.stand(model, at: stop.coordinate, accuracy: 5)
        XCTAssertNotNil(model.confirmedPlace)

        try Self.stand(model, at: GeoCoordinate(latitude: 31.5, longitude: 121.9), accuracy: 5)

        XCTAssertNil(model.confirmedPlace)
    }

    /// The narration is the pack's cached text, and the app knows whether it is
    /// a sourced claim or the character talking — the same distinction the recap
    /// makes.
    func testTheNarrationIsTheStopsCachedTextAndKnowsWhatKindItIs() throws {
        let model = AppModel()
        model.startWalk()
        let sourced = try XCTUnwrap(model.walk.narrative.stops.map(\.stop).first(where: \.isFactual))

        model.confirmPlace(sourced)
        let narration = try XCTUnwrap(model.placeNarration)

        XCTAssertEqual(narration.text, sourced.narration)
        XCTAssertTrue(narration.isFactual)

        let reflective = try XCTUnwrap(model.walk.narrative.stops.map(\.stop).first(where: { !$0.isFactual }))
        model.confirmPlace(reflective)
        XCTAssertEqual(model.placeNarration?.isFactual, false)
    }

    func testNothingConfirmedMeansNothingToNarrate() {
        let model = AppModel()
        XCTAssertNil(model.placeNarration)
    }

    // MARK: - Helpers

    /// Feeds one reading through the model's real walk path.
    private static func stand(
        _ model: AppModel,
        at coordinate: GeoCoordinate,
        accuracy: Double
    ) throws {
        let session = try XCTUnwrap(model.walkSession)
        model.advanceWalk(
            with: LocationObservation(
                coordinate: coordinate,
                horizontalAccuracyMeters: accuracy,
                observedAt: Date()
            ),
            session: session
        )
    }
}
