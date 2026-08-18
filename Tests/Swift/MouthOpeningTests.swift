import XCTest
@testable import JoiMobile

/// `G2-J2B` acceptance. Mouth opening is the one part of lip sync that can be
/// proven without audio hardware or a renderer, which is exactly why it is a
/// value type: every rule below was previously only ever observed once, by eye,
/// in a simulator.
final class MouthOpeningTests: XCTestCase {
    /// `J2B-02` — at or below the floor the mouth is shut, however long it is driven.
    func testSilenceFloorReadsAsAClosedMouth() {
        var mouth = MouthOpening()
        for _ in 0..<200 {
            _ = mouth.advance(levelDecibels: MouthOpening.silenceFloor, elapsed: 1.0 / 60)
        }
        XCTAssertEqual(mouth.value, 0, accuracy: 0.0001)

        for _ in 0..<200 {
            _ = mouth.advance(levelDecibels: -160, elapsed: 1.0 / 60)
        }
        XCTAssertEqual(mouth.value, 0, accuracy: 0.0001)
    }

    /// `J2B-02` — nothing playing releases towards closed instead of cutting to
    /// zero, so a line ends with a mouth that closes.
    func testNoAudioReleasesTowardsClosedRatherThanSnapping() {
        var mouth = MouthOpening()
        for _ in 0..<60 { _ = mouth.advance(levelDecibels: 0, elapsed: 1.0 / 60) }
        let open = mouth.value
        XCTAssertGreaterThan(open, 0.9, "full-scale audio should open the mouth")

        // One frame after the audio stops it is on its way down, not already shut.
        let afterOneFrame = mouth.advance(levelDecibels: nil, elapsed: 1.0 / 60)
        XCTAssertLessThan(afterOneFrame, open)
        XCTAssertGreaterThan(afterOneFrame, 0)

        // Given long enough it does reach closed.
        for _ in 0..<200 { _ = mouth.advance(levelDecibels: nil, elapsed: 1.0 / 60) }
        XCTAssertEqual(mouth.value, 0, accuracy: 0.001)
    }

    /// `J2B-03` — the shape is set by seconds, so asking more often over the same
    /// interval must not change where the mouth ends up. This is the property a
    /// per-poll smoothing factor cannot have, and it is why a stage that drops
    /// frames no longer animates differently.
    func testSameElapsedTimeReachesSameOpeningRegardlessOfPollCount() {
        let total: Float = 0.2

        var coarse = MouthOpening()
        _ = coarse.advance(levelDecibels: -10, elapsed: total)

        var fine = MouthOpening()
        for _ in 0..<20 { _ = fine.advance(levelDecibels: -10, elapsed: total / 20) }

        XCTAssertEqual(coarse.value, fine.value, accuracy: 0.02)
    }

    /// `J2B-04` — opening beats closing. A mouth that shuts as fast as it opens
    /// chatters between syllables.
    func testMouthOpensFasterThanItCloses() {
        XCTAssertLessThan(MouthOpening.attackSeconds, MouthOpening.releaseSeconds)

        var opening = MouthOpening()
        let openedInOneFrame = opening.advance(levelDecibels: 0, elapsed: 1.0 / 60)

        var closing = MouthOpening()
        for _ in 0..<200 { _ = closing.advance(levelDecibels: 0, elapsed: 1.0 / 60) }
        let before = closing.value
        let closedInOneFrame = before - closing.advance(levelDecibels: nil, elapsed: 1.0 / 60)

        XCTAssertGreaterThan(
            openedInOneFrame,
            closedInOneFrame,
            "one frame of attack should move further than one frame of release"
        )
    }

    /// `J2B-05` — a renderer receives a weight it can use unguarded.
    func testOpeningStaysWithinZeroToOneForAnyInput() {
        var mouth = MouthOpening()
        // Above full scale, at it, below the floor, and absurd values.
        for level in [Float(40), 0, -3, -45, -200, -Float.infinity] {
            for _ in 0..<30 {
                let value = mouth.advance(levelDecibels: level, elapsed: 1.0 / 60)
                XCTAssertGreaterThanOrEqual(value, 0)
                XCTAssertLessThanOrEqual(value, 1)
            }
        }
    }

    /// A non-advancing or backwards clock must not move the mouth or produce a
    /// non-finite weight. `CACurrentMediaTime` deltas are clamped upstream, but
    /// the type cannot assume that.
    func testDegenerateElapsedTimesAreInert() {
        var mouth = MouthOpening()
        for _ in 0..<10 { _ = mouth.advance(levelDecibels: 0, elapsed: 1.0 / 60) }
        let steady = mouth.value

        XCTAssertEqual(mouth.advance(levelDecibels: 0, elapsed: 0), steady, accuracy: 0.0001)
        XCTAssertEqual(mouth.advance(levelDecibels: 0, elapsed: -1), steady, accuracy: 0.0001)
        XCTAssertTrue(mouth.value.isFinite)
    }

    /// Loudness maps monotonically: louder audio never yields a smaller opening
    /// once both have settled.
    func testLouderAudioSettlesWider() {
        func settled(at level: Float) -> Float {
            var mouth = MouthOpening()
            for _ in 0..<300 { _ = mouth.advance(levelDecibels: level, elapsed: 1.0 / 60) }
            return mouth.value
        }
        let quiet = settled(at: -30)
        let mid = settled(at: -15)
        let loud = settled(at: -3)
        XCTAssertLessThan(quiet, mid)
        XCTAssertLessThan(mid, loud)
    }
}
