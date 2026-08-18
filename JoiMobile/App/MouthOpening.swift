import Foundation

/// How far the character's mouth is open, derived from the level of the audio
/// actually playing.
///
/// This is a value type on purpose. Lip sync used to live inside `SpeechPlayer`
/// welded to an `AVAudioPlayer`, which meant none of its rules could be checked
/// without audio hardware — every one of them had been confirmed exactly once,
/// by eye, in a simulator. Holding no player, no clock and no renderer makes the
/// rules provable (`G2-J2B`) and leaves `SpeechPlayer` responsible only for
/// fetching and playing.
///
/// Driving the mouth from played audio rather than from text timing is DEC-021:
/// this product stays still rather than miming speech that is not being spoken.
struct MouthOpening {
    /// Level below which the character is treated as silent, in dBFS.
    /// Synthesised speech sits well above this between syllables, so a lower
    /// floor would hold the mouth open through the gaps.
    static let silenceFloor: Float = -45
    /// A mouth reaches its opening quickly and closes more slowly. Symmetric
    /// smoothing either chatters on syllable edges or hangs open at the end of a
    /// line. These are seconds, which is what makes the motion independent of
    /// how often a renderer happens to ask.
    static let attackSeconds: Float = 0.035
    static let releaseSeconds: Float = 0.09

    /// Current opening, always within `0...1`.
    private(set) var value: Float = 0

    /// Advances towards the opening implied by `levelDecibels`.
    ///
    /// - Parameters:
    ///   - levelDecibels: dBFS of the audio playing right now, or `nil` when
    ///     nothing is playing. `nil` releases towards closed rather than cutting
    ///     to zero, so a line ends with a mouth that closes the same way it does
    ///     between syllables.
    ///   - elapsed: seconds since the previous call. Zero, negative and
    ///     non-finite values leave the opening untouched.
    /// - Returns: the new opening, for callers that want it without a second read.
    @discardableResult
    mutating func advance(levelDecibels: Float?, elapsed: Float) -> Float {
        guard elapsed.isFinite, elapsed > 0 else { return value }
        // dB is already a perceptual scale, so opening maps linearly across it
        // from the floor up to full scale.
        let target: Float
        if let level = levelDecibels, level.isFinite {
            target = min(max((level - Self.silenceFloor) / -Self.silenceFloor, 0), 1)
        } else {
            target = 0
        }
        let seconds = target > value ? Self.attackSeconds : Self.releaseSeconds
        let approached = value + (target - value) * (1 - exp(-elapsed / seconds))
        value = min(max(approached.isFinite ? approached : target, 0), 1)
        return value
    }
}
