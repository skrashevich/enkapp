import AVFoundation
import Foundation
import Speech

/// Dictation for the assistant's input field, transcribed entirely on the device.
///
/// `requiresOnDeviceRecognition` is forced on and the recognizer is rejected when
/// it cannot honour it, so audio never leaves the phone. That matters here: the
/// player is dictating game codes and level details mid-game.
@MainActor
@Observable
final class VoiceDictationModel {
    enum State: Equatable {
        case idle
        case preparing
        case listening
        case unavailable(String)
    }

    private(set) var state: State = .idle
    /// Text recognized so far in the current session.
    private(set) var transcript = ""

    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    var isListening: Bool { state == .listening || state == .preparing }

    /// Dictation is Russian first: the app's interface, the games and the codes
    /// players read out are all Russian, and a device set to another language
    /// would otherwise transcribe them as nonsense.
    ///
    /// The device language is used only when Russian has no on-device model
    /// installed, so the button still works instead of disappearing.
    init(preferred: Locale = Locale(identifier: "ru_RU"), deviceLocale: Locale = .current) {
        if let russian = SFSpeechRecognizer(locale: preferred), russian.supportsOnDeviceRecognition {
            recognizer = russian
            return
        }
        recognizer = SFSpeechRecognizer(locale: deviceLocale)
    }

    /// True when the device can transcribe locally. Dictation is hidden otherwise
    /// rather than silently falling back to Apple's servers.
    var isSupported: Bool {
        recognizer?.supportsOnDeviceRecognition == true
    }

    func toggle(onText: @escaping (String) -> Void) {
        if isListening {
            stop()
        } else {
            start(onText: onText)
        }
    }

    func start(onText: @escaping (String) -> Void) {
        guard !isListening else { return }
        guard let recognizer, recognizer.supportsOnDeviceRecognition else {
            state = .unavailable("Локальное распознавание речи недоступно на этом устройстве.")
            return
        }

        state = .preparing
        transcript = ""

        Task {
            guard await Self.requestSpeechAuthorization() else {
                state = .unavailable("Нет доступа к распознаванию речи. Разрешите его в настройках iOS.")
                return
            }
            guard await Self.requestMicrophoneAccess() else {
                state = .unavailable("Нет доступа к микрофону. Разрешите его в настройках iOS.")
                return
            }
            beginListening(recognizer: recognizer, onText: onText)
        }
    }

    func stop() {
        audioEngine.inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if isListening {
            state = .idle
        }
    }

    private func beginListening(recognizer: SFSpeechRecognizer, onText: @escaping (String) -> Void) {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // The whole point of this feature: never ship the audio anywhere.
        request.requiresOnDeviceRecognition = true
        self.request = request

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let input = audioEngine.inputNode
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
                request.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            stop()
            state = .unavailable("Не удалось начать запись: \(error.localizedDescription)")
            return
        }

        state = .listening
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    onText(self.transcript)
                    if result.isFinal {
                        self.stop()
                    }
                    return
                }
                if error != nil {
                    // A recognizer error ends the session; whatever was already
                    // transcribed stays in the field.
                    self.stop()
                }
            }
        }
    }

    private static func requestSpeechAuthorization() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        @unknown default:
            return false
        }
    }

    private static func requestMicrophoneAccess() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }
}
