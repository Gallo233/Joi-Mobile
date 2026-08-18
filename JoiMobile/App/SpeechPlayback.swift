import AVFoundation
import Foundation
import OSLog
import QuartzCore

private let speechLog = Logger(subsystem: "com.joi.mobile", category: "speech")

/// Per-frame mouth opening, read by a character renderer.
///
/// It is deliberately derived from played audio only. Driving a mouth from text
/// timing would animate speech that is not being spoken, and this product would
/// rather stay still than mime.
@MainActor
protocol LipSyncAmplitudeSource: AnyObject {
    /// 0 when silent, up to 1 at full amplitude.
    var currentAmplitude: Float { get }
}

/// Fetches and plays one character line, exposing its live amplitude.
///
/// A failure here is silent by design: the transcript already carries the words,
/// and no substitute voice may speak as the character.
@MainActor
@Observable
final class SpeechPlayer: LipSyncAmplitudeSource {
    private(set) var isSpeaking = false
    @ObservationIgnored private var player: AVAudioPlayer?
    /// AVAudioPlayer calls back off the main actor, so the delegate is a separate
    /// non-isolated object that hops rather than making this whole type unsafe.
    @ObservationIgnored private lazy var playbackDelegate = PlaybackDelegate { [weak self] in
        Task { @MainActor in self?.finishPlayback() }
    }
    @ObservationIgnored private var fetchTask: Task<Void, Never>?
    @ObservationIgnored private let endpoint: URL
    @ObservationIgnored private let session: URLSession

    /// Mouth shape lives in its own value type so its rules can be tested
    /// without audio hardware; see `MouthOpening` and `G2-J2B`.
    @ObservationIgnored private var mouth = MouthOpening()
    @ObservationIgnored private var peakAmplitude: Float = 0
    @ObservationIgnored private var lastPoll: CFTimeInterval?
    @ObservationIgnored private var sessionActivated = false

    init(endpoint: URL, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    var currentAmplitude: Float {
        let now = CACurrentMediaTime()
        // Clamped: a stage that was paused or is loading a model must not deliver
        // one enormous step that snaps the mouth.
        let elapsed = Float(min(max(now - (lastPoll ?? now), 0), 0.1))
        lastPoll = now
        // averagePower is dBFS: -160 is silence, 0 is full scale. Nothing playing
        // is `nil`, which releases the mouth rather than cutting it shut.
        let level: Float?
        if let player, player.isPlaying {
            player.updateMeters()
            level = player.averagePower(forChannel: 0)
        } else {
            level = nil
        }
        let opening = mouth.advance(levelDecibels: level, elapsed: elapsed)
        // Peak is reported once when playback ends: a mouth that never opened is
        // otherwise indistinguishable from audio that played silently.
        peakAmplitude = max(peakAmplitude, opening)
        return opening
    }

    /// Speaks `line`. Any line already playing is replaced, because a newer
    /// response supersedes an older one rather than queueing behind it.
    func speak(_ line: String, emotion: String = "neutral") {
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        stop()
        fetchTask = Task { [weak self] in
            guard let self else { return }
            guard let data = await fetchAudio(text: text, emotion: emotion) else { return }
            guard !Task.isCancelled else { return }
            play(data)
        }
    }

    func stop() {
        fetchTask?.cancel()
        fetchTask = nil
        player?.stop()
        player = nil
        // Same reason as `finishPlayback`: releasing the mouth is the job of the
        // next poll, so a stopped turn closes the mouth instead of freezing it
        // mid-vowel.
        isSpeaking = false
    }

    private func fetchAudio(text: String, emotion: String) async -> Data? {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(
            withJSONObject: ["text": text, "emotion": emotion]
        )
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                // The stable code is server-side; the client only needs to know
                // that the character has no voice for this line.
                speechLog.error("speech unavailable: upstream refused")
                return nil
            }
            return data
        } catch {
            speechLog.error("speech unavailable: transport failed")
            return nil
        }
    }

    /// Claims the audio session for playback, once, immediately before the first
    /// line is spoken.
    ///
    /// Without this the app runs on the default `soloAmbient` category, which the
    /// ring/silent switch silences: on a real device with the switch flipped the
    /// character is mute and its mouth never moves, with nothing in the log to
    /// say why. `spokenAudio` is the mode for a voice rather than for music.
    ///
    /// Claiming it lazily rather than at launch matters: configuring the session
    /// at startup would interrupt whatever the user was already listening to
    /// merely because they opened the app.
    private func activateSession() {
        guard !sessionActivated else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
            sessionActivated = true
        } catch {
            // Playback will most likely fail next, which stays silent by design.
            // Naming it here is the difference between a diagnosable silence and
            // a mystery.
            speechLog.error("speech unavailable: audio session refused")
        }
    }

    private func play(_ data: Data) {
        activateSession()
        do {
            let player = try AVAudioPlayer(data: data)
            player.isMeteringEnabled = true
            player.delegate = playbackDelegate
            guard player.play() else {
                speechLog.error("speech unavailable: playback refused")
                return
            }
            self.player = player
            peakAmplitude = 0
            isSpeaking = true
            speechLog.notice("speech playing: \(player.duration, privacy: .public)s of audio")
        } catch {
            speechLog.error("speech unavailable: audio not decodable")
        }
    }

    private func finishPlayback() {
        speechLog.notice("speech finished: peak mouth amplitude \(self.peakAmplitude, privacy: .public)")
        player = nil
        // The mouth is deliberately left alone: with no player, the next poll
        // releases it to zero over the same time constant the gaps between
        // syllables use, so a line ends with a mouth that closes rather than one
        // that snaps shut on the last frame.
        peakAmplitude = 0
        isSpeaking = false
    }
}

/// Bridges AVAudioPlayer's non-isolated callback onto the main actor.
private final class PlaybackDelegate: NSObject, AVAudioPlayerDelegate {
    private let onFinish: @Sendable () -> Void

    init(onFinish: @escaping @Sendable () -> Void) {
        self.onFinish = onFinish
        super.init()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let finish = onFinish
        Task { @MainActor in finish() }
    }
}
