import CompanionCore
import XCTest
@testable import JoiMobile

/// The stage says why it is empty.
///
/// The character stage has always had a silhouette to fall back to, and falling
/// back was silent. Three unrelated situations therefore rendered as the same
/// picture: no character activated, a character this build has no runtime for,
/// and a runtime that failed to present a model. Only the first is healthy, and
/// the second has cost three debugging cycles — a default-spec `xcodegen
/// generate` replaces the native project, the next build installs over the
/// native app, and the stage correctly shows a silhouette that looks exactly
/// like a broken model.
///
/// `decide` is pure so the spec ladder cannot make this untestable: the
/// compile-time facts are arguments, and every rung runs all four cases.
final class CharacterStageFallbackTests: XCTestCase {

    /// No character activated is not a fault, and must not be narrated as one.
    func testAnEmptyStageWithNoActivatedCharacterSaysNothing() {
        XCTAssertNil(
            StageFallbackReason.decide(renderer: nil, isAdmitted: true, presentationFailed: false)
        )
        XCTAssertNil(
            StageFallbackReason.decide(renderer: nil, isAdmitted: false, presentationFailed: true),
            "with no character there is nothing to be unable to draw"
        )
    }

    /// The regression this exists to make visible.
    func testACharacterThisBuildCannotDrawIsNamedAsABuildProperty() {
        for kind in [CharacterRendererKind.live2d, .vrm] {
            XCTAssertEqual(
                StageFallbackReason.decide(renderer: kind, isAdmitted: false, presentationFailed: false),
                .runtimeAbsentFromBuild(kind)
            )
        }
    }

    /// A missing runtime outranks a presentation failure: a runtime that is not
    /// in the binary cannot have failed to present anything, and reporting it
    /// that way would send the reader looking for a defect in the model.
    func testAMissingRuntimeIsReportedAheadOfAPresentationFailure() {
        XCTAssertEqual(
            StageFallbackReason.decide(renderer: .vrm, isAdmitted: false, presentationFailed: true),
            .runtimeAbsentFromBuild(.vrm)
        )
    }

    /// The other silent case: the runtime is present and gave up.
    func testAnAdmittedRuntimeThatFailedToPresentSaysSo() {
        XCTAssertEqual(
            StageFallbackReason.decide(renderer: .live2d, isAdmitted: true, presentationFailed: true),
            .runtimeCouldNotPresent(.live2d)
        )
    }

    /// A working native stage stays quiet.
    func testAWorkingNativeStageIsNotAnnounced() {
        XCTAssertNil(
            StageFallbackReason.decide(renderer: .vrm, isAdmitted: true, presentationFailed: false)
        )
    }

    /// A `static` package renders as the silhouette by design, so no build can
    /// be missing a runtime for it and no notice is owed.
    func testTheStaticRendererIsAdmittedByEveryRungOfTheLadder() {
        XCTAssertTrue(StageRuntimeAdmission.admits(.static))
        XCTAssertNil(
            StageFallbackReason.decide(
                renderer: .static,
                isAdmitted: StageRuntimeAdmission.admits(.static),
                presentationFailed: false
            )
        )
    }

    /// Whatever this build admitted, `admits` must agree with the flag rather
    /// than answer from a default — otherwise the notice would be decided by a
    /// constant instead of by the build.
    func testAdmissionAnswersFromTheCompiledFlags() {
        #if JOI_LIVE2D
        XCTAssertTrue(StageRuntimeAdmission.admits(.live2d))
        #else
        XCTAssertFalse(StageRuntimeAdmission.admits(.live2d))
        #endif

        #if JOI_VRM
        XCTAssertTrue(StageRuntimeAdmission.admits(.vrm))
        #else
        XCTAssertFalse(StageRuntimeAdmission.admits(.vrm))
        #endif
    }

    /// A notice that did not name the runtime would leave the reader exactly
    /// where the silent fallback left them.
    func testEveryNoticeNamesItsRuntime() {
        for kind in CharacterRendererKind.allCases {
            XCTAssertFalse(kind.stageName.isEmpty, "\(kind) has no name to put in the notice")
        }
        XCTAssertEqual(Set(CharacterRendererKind.allCases.map(\.stageName)).count, CharacterRendererKind.allCases.count)

        for reason in [
            StageFallbackReason.runtimeAbsentFromBuild(.vrm),
            StageFallbackReason.runtimeCouldNotPresent(.vrm),
        ] {
            XCTAssertTrue(reason.message.contains("VRM"), reason.message)
        }
        XCTAssertNotEqual(
            StageFallbackReason.runtimeAbsentFromBuild(.vrm).message,
            StageFallbackReason.runtimeCouldNotPresent(.vrm).message,
            "the two causes need different fixes, so they may not share one sentence"
        )
    }
}
