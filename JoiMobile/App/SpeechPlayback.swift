import AVFoundation
import Foundation
import OSLog

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

    /// Smoothed so the mouth does not chatter on per-frame amplitude noise.
    @ObservationIgnored private var smoothed: Float = 0
    @ObservationIgnored private var peakAmplitude: Float = 0

    init(endpoint: URL, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    var currentAmplitude: Float {
        guard let player, player.isPlaying else {
            smoothed = 0
            return 0
        }
        player.updateMeters()
        // averagePower is dBFS: -160 is silence, 0 is full scale. Below -40 dB is
        // inaudible for this purpose and must read as a closed mouth.
        let decibels = player.averagePower(forChannel: 0)
        let normalized = decibels < -40 ? 0 : (decibels + 40) / 40
        let target = min(max(normalized, 0), 1)
        smoothed += (target - smoothed) * 0.45
        // Peak is reported once when playback ends: a mouth that never opened is
        // otherwise indistinguishable from audio that played silently.
        peakAmplitude = max(peakAmplitude, smoothed)
        return smoothed
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
        smoothed = 0
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

    private func play(_ data: Data) {
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
        smoothed = 0
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
