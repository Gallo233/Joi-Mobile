import AVFoundation
import Foundation
import OSLog
import Speech

private let voiceLog = Logger(subsystem: "com.joi.mobile", category: "voice")

/// Push-to-talk dictation into the composer.
///
/// Recognition is on device or it does not happen (DEC-031): server recognition
/// would upload the recording, and speaking into a companion is not consent to
/// send that recording to a third party. A device or locale that cannot do it
/// says so and the keyboard keeps working.
@MainActor
@Observable
final class VoiceInput {
    /// Every state the microphone can be in, including each way it can fail.
    /// A closed set, so the composer never has to guess what to show.
    enum State: Equatable {
        case idle
        /// The system prompts are up. Reached only from a deliberate press.
        case requestingPermission
        /// Recording, carrying whatever has been recognised so far.
        case listening(partial: String)
        /// This device or locale cannot recognise on device.
        case unavailable
        /// The user refused the microphone or speech recognition.
        case denied
        /// The recording ended without any recognisable speech.
        case heardNothing
        /// The recogniser or the audio engine failed.
        case failed

        var isListening: Bool {
            if case .listening = self { return true }
            return false
        }

        /// Chinese copy for the states the composer surfaces. `nil` where the
        /// state speaks for itself through the button.
        var message: String? {
            switch self {
            case .idle, .requestingPermission, .listening: nil
            case .unavailable: String(localized: "此设备无法在本机识别中文语音，请用键盘输入。")
            case .denied: String(localized: "没有麦克风或语音识别权限，请在系统设置里开启。")
            case .heardNothing: String(localized: "没有听清，请再说一次。")
            case .failed: String(localized: "语音识别没有完成，请再试一次。")
            }
        }
    }

    private(set) var state: State = .idle

    /// The recogniser for the displayed language. Speech in, Chinese text out —
    /// the character answers in Chinese, and the Japanese voice is only ever
    /// output (DEC-021).
    @ObservationIgnored private let locale = Locale(identifier: "zh-Hans-CN")
    @ObservationIgnored private var recognizer: SFSpeechRecognizer?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var transcript = ""

    init() {}

    /// Whether this build, device and locale can recognise without uploading.
    /// Checked before any permission prompt so a device that could never do it
    /// does not ask the user for access it cannot use.
    var isAvailable: Bool {
        guard let recognizer = SFSpeechRecognizer(locale: locale) else { return false }
        return recognizer.isAvailable && recognizer.supportsOnDeviceRecognition
    }

    /// Begins listening. Authorisation is requested here, on the first press,
    /// rather than at launch.
    func begin() async {
        // A press delivers many gesture updates, and authorisation is awaited, so
        // the state is `requestingPermission` for a while before it is
        // `listening`. Guarding only on `listening` let a single press start
        // several authorisation requests and several audio engines.
        guard !state.isListening, state != .requestingPermission else { return }
        transcript = ""
        // Logged on entry, not only on failure: without this, "nothing happened"
        // cannot be told apart from "the button was never pressed".
        voiceLog.notice("voice input: press received, available \(self.isAvailable, privacy: .public)")
        guard isAvailable else {
            voiceLog.notice("voice input unavailable: no on-device recognition for this locale")
            state = .unavailable
            return
        }
        state = .requestingPermission
        guard await requestAuthorization() else {
            state = .denied
            return
        }
        do {
            try startEngine()
            state = .listening(partial: "")
        } catch {
            voiceLog.error("voice input failed: audio engine refused")
            stopEngine()
            state = .failed
        }
    }

    /// Ends the utterance and returns the recognised text, or `nil` when nothing
    /// was heard. The caller decides what to do with it; nothing is sent here.
    @discardableResult
    func finish() -> String? {
        guard state.isListening else { return nil }
        stopEngine()
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        state = text.isEmpty ? .heardNothing : .idle
        return text.isEmpty ? nil : text
    }

    /// Abandons the utterance without producing text.
    func cancel() {
        guard state.isListening || state == .requestingPermission else { return }
        stopEngine()
        state = .idle
    }

    /// Clears a message the composer has already shown, so a failure does not
    /// stay on screen after the user moves on.
    func acknowledge() {
        switch state {
        case .unavailable, .denied, .heardNothing, .failed: state = .idle
        default: break
        }
    }

    /// Both system callbacks arrive on an arbitrary queue. Written inside a
    /// `@MainActor` type their closures are inferred main-actor isolated, and
    /// resuming from the wrong queue trips the concurrency runtime's isolation
    /// assertion — a `SIGTRAP` the moment the user first presses to talk, on the
    /// one path that only runs once per install. `nonisolated` keeps the
    /// closures off the actor; the caller is already back on it when this
    /// returns.
    private nonisolated func requestAuthorization() async -> Bool {
        let speechAuthorized: Bool = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speechAuthorized else { return false }
        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func startEngine() throws {
        let recognizer = SFSpeechRecognizer(locale: locale)
        self.recognizer = recognizer
        let request = SFSpeechAudioBufferRecognitionRequest()
        // The whole point of DEC-031: the recogniser may not reach the network.
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        self.request = request

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
        try session.setActive(true)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [request] buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        try engine.start()

        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    transcript = result.bestTranscription.formattedString
                    if state.isListening { state = .listening(partial: transcript) }
                }
                if error != nil, state.isListening {
                    voiceLog.error("voice input failed: recogniser stopped early")
                    stopEngine()
                    state = transcript.isEmpty ? .failed : .idle
                }
            }
        }
    }

    private func stopEngine() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        // Hand the session back for playback, or the character would be left
        // unable to speak after the user talked to it.
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        } catch {
            voiceLog.error("voice input: audio session would not return to playback")
        }
    }
}
