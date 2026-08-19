import AVFoundation
import Foundation
import OSLog
import QuartzCore
import UIKit

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

/// Why the character had no voice for a line (`FAIL-006`, `G2-J5H`).
///
/// Three cases rather than one, because the product can genuinely tell them
/// apart and they do not have the same remedy: a voice service that is down
/// recovers on its own, audio that will not decode is a bug in what was sent,
/// and a route that refuses is usually something the user can change.
enum SpeechFailure: Equatable, Sendable {
    /// The voice service refused the request or could not be reached.
    case voiceUnavailable
    /// Bytes arrived and were not audio this device can play.
    case audioUndecodable
    /// The device would not play it: the audio session or the current route
    /// refused.
    case routeRefused

    var message: String {
        switch self {
        case .voiceUnavailable: String(localized: "这句话没有语音，文字仍在。")
        case .audioUndecodable: String(localized: "这句话的语音无法播放，文字仍在。")
        case .routeRefused: String(localized: "这台设备现在不能播放语音，文字仍在。")
        }
    }
}

/// Fetches and plays one character line, exposing its live amplitude.
///
/// A failure never substitutes another voice for the character's — that rule is
/// DEC-021's and is unchanged. What *has* changed is that it is no longer
/// silent: a line that could not be spoken says so, because a character that
/// simply stops making sound is indistinguishable from one that is broken.
@MainActor
@Observable
final class SpeechPlayer: LipSyncAmplitudeSource {
    private(set) var isSpeaking = false
    /// Why the last line had no voice, or `nil` if none is owed. Cleared by the
    /// next line, because a fresh attempt supersedes the previous verdict.
    private(set) var failure: SpeechFailure?
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

    /// Called when the system took the audio away (`G2-J5F`).
    ///
    /// A closure rather than a direct call into the coordinator, because
    /// `SpeechCoordinator` is the unique owner of who may talk and this type is
    /// not it: the player knows the audio stopped, and the owner decides what
    /// that means for the cue.
    @ObservationIgnored var onInterrupted: (@MainActor () -> Void)?

    /// Called when a line could not be spoken at all (`FAIL-006`). PRD §7.1
    /// requires the playback generation to be ended, which only the owner can
    /// do — until this existed, a line that never played left `SpeechCoordinator`
    /// naming it as the thing the character was currently saying.
    @ObservationIgnored var onFailed: (@MainActor (SpeechFailure) -> Void)?

    @ObservationIgnored private let observers = ObserverTokens()

    init(endpoint: URL, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
        observeAudioInterruptions()
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
        // A new attempt supersedes the previous verdict, so the old reason must
        // not outlive the line it was about.
        failure = nil
        fetchTask = Task { [weak self] in
            guard let self else { return }
            guard let data = await fetchAudio(text: text, emotion: emotion) else {
                // A cancelled fetch is not a failure: `stop()` and a superseding
                // line both cancel, and neither owes the user an explanation.
                guard !Task.isCancelled else { return }
                self.fail(.voiceUnavailable)
                return
            }
            guard !Task.isCancelled else { return }
            play(data)
        }
    }

    func stop() {
        // A line the user or a newer line ended owes no explanation, so a stale
        // reason must not survive into the next one.
        failure = nil
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

    /// Subscribes to the three ways the system takes audio away.
    ///
    /// Registered at construction rather than when a line starts: an interruption
    /// that arrives in the same runloop turn as playback would otherwise be
    /// missed, and an unregistered observer costs nothing while nothing is
    /// speaking because the policy is inert without a line.
    private func observeAudioInterruptions() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()

        // Each block reduces the notification to plain numbers *before* hopping
        // to the main actor. `Notification` and its `userInfo` are not
        // `Sendable`, and under Swift 6 capturing one into an actor-isolated
        // closure is an error rather than a warning — correctly, since only
        // these scalars are ever read.
        observers.keep(
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: session,
                queue: .main
            ) { [weak self] note in
                let rawType = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                let rawOptions = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
                MainActor.assumeIsolated {
                    guard let self else { return }
                    guard let type = rawType.flatMap(AVAudioSession.InterruptionType.init(rawValue:)) else { return }
                    switch type {
                    case .began:
                        self.handle(.interruptionBegan)
                    case .ended:
                        let suggests = rawOptions
                            .map(AVAudioSession.InterruptionOptions.init(rawValue:))?
                            .contains(.shouldResume) ?? false
                        self.handle(.interruptionEnded(systemSuggestsResume: suggests))
                    @unknown default:
                        // A kind this build does not know is still an
                        // interruption; ending the line is the safe reading.
                        self.handle(.interruptionBegan)
                    }
                }
            }
        )

        observers.keep(
            center.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: session,
                queue: .main
            ) { [weak self] note in
                let rawReason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let reason = rawReason.flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
                    self.handle(.routeChanged(outputDeviceLost: reason == .oldDeviceUnavailable))
                }
            }
        )

        observers.keep(
            center.addObserver(
                forName: UIApplication.willResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.handle(.leftForeground) }
            }
        )
    }

    /// Applies the policy. Kept separate from the observers so a test can drive
    /// the same path the system drives without posting a notification.
    func handle(_ event: SpeechInterruptionEvent) {
        switch SpeechInterruptionPolicy.decide(event, isSpeaking: isSpeaking) {
        case .ignore:
            return
        case .endLine:
            speechLog.notice("speech interrupted: the system took the audio")
            // `stop()` and not `finishPlayback()`: this line did not finish, and
            // logging a peak amplitude for it would record a completed line.
            stop()
            onInterrupted?()
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
    @discardableResult
    private func activateSession() -> Bool {
        guard !sessionActivated else { return true }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
            sessionActivated = true
            return true
        } catch {
            // Returned rather than swallowed: a session that refuses is a route
            // problem, and reporting it as one is the difference between a
            // diagnosable silence and a mystery.
            speechLog.error("speech unavailable: audio session refused")
            return false
        }
    }

    private func play(_ data: Data) {
        guard activateSession() else {
            fail(.routeRefused)
            return
        }
        do {
            let player = try AVAudioPlayer(data: data)
            player.isMeteringEnabled = true
            player.delegate = playbackDelegate
            guard player.play() else {
                speechLog.error("speech unavailable: playback refused")
                fail(.routeRefused)
                return
            }
            self.player = player
            peakAmplitude = 0
            isSpeaking = true
            failure = nil
            speechLog.notice("speech playing: \(player.duration, privacy: .public)s of audio")
        } catch {
            speechLog.error("speech unavailable: audio not decodable")
            fail(.audioUndecodable)
        }
    }

    /// Records the reason and hands the owner the one part only it can do: end
    /// the playback generation, as PRD §7.1 requires of `FAIL-006`.
    ///
    /// Internal so a test can drive the same path a dead voice service drives,
    /// without one.
    func fail(_ reason: SpeechFailure) {
        failure = reason
        isSpeaking = false
        onFailed?(reason)
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

/// Holds notification tokens and removes them when its owner goes.
///
/// Separate from `SpeechPlayer` because that type is `@MainActor` while `deinit`
/// is nonisolated, so a deinit there may not touch its stored properties. This
/// object holds nothing but opaque tokens: `keep` is called only from the
/// owner's initialiser and `deinit` runs exactly once, which is what makes the
/// unchecked conformance true rather than merely convenient.
private final class ObserverTokens: @unchecked Sendable {
    private var tokens: [any NSObjectProtocol] = []

    func keep(_ token: any NSObjectProtocol) { tokens.append(token) }

    deinit {
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
        }
    }
}
