import Foundation
import AVFoundation
import Speech
import Observation

/// On-device transcription for voice reflections.
///
/// Transcription is on-device so the text is available immediately and no
/// third party sees it. Note this is no longer the *whole* privacy story: as
/// of 2026-10-01 the audio file is uploaded too, so the group can hear each
/// other (Notion items 35–41). What stays local is the recognition, not the
/// recording.
///
/// `requiresOnDeviceRecognition` is set wherever the locale supports it, and
/// `isOnDevice` reports honestly when it doesn't — some locales fall back to
/// Apple's servers, which is a claim we shouldn't make blindly. See item 26b.
@MainActor
@Observable
final class SpeechRecognizer {

    enum State: Equatable {
        case idle
        case unauthorized(String)
        case recording
        case finished
        case failed(String)
    }

    private(set) var state: State = .idle
    /// Grows as you speak — partial results, so the UI fills in live.
    private(set) var transcript = ""
    private(set) var duration: TimeInterval = 0
    /// Normalised 0…1 levels for the waveform.
    private(set) var levels: [CGFloat] = []
    /// False when the locale forced server-side recognition.
    private(set) var isOnDevice = true
    /// The recorded m4a, once recording stops. Uploaded to
    /// `reflection-media/{user id}/{uuid}.m4a` before the reflection is
    /// posted — the transcript is still required, audio is additional.
    private(set) var recordingURL: URL?

    /// The backend accepts 120s; on-device recognition degrades past about a
    /// minute, so this stops itself well before either becomes a problem.
    let maximumDuration: TimeInterval = 120

    private let locale: Locale
    private var recognizer: SFSpeechRecognizer?
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var started: Date?
    private var ticker: Timer?
    private var audioFile: AVAudioFile?

    /// `preferred_language` drives the locale: the recogniser must be told the
    /// language up front — it cannot detect it (Notion item 26a).
    init(languageCode: String = "en") {
        self.locale = Locale(identifier: languageCode)
        self.recognizer = SFSpeechRecognizer(locale: locale)
    }

    var isAvailable: Bool { recognizer?.isAvailable ?? false }

    var remaining: TimeInterval { max(maximumDuration - duration, 0) }

    func requestAuthorization() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else {
            state = .unauthorized("Dwell needs permission to transcribe speech.")
            return false
        }
        let mic = await AVAudioApplication.requestRecordPermission()
        guard mic else {
            state = .unauthorized("Dwell needs permission to use the microphone.")
            return false
        }
        return true
    }

    func start() async {
        guard state != .recording else { return }
        guard await requestAuthorization() else { return }
        guard let recognizer, recognizer.isAvailable else {
            state = .failed("Speech recognition isn't available for \(locale.identifier) right now.")
            return
        }

        transcript = ""
        levels = []
        duration = 0
        recordingURL = nil

        do {
            let session = AVAudioSession.sharedInstance()
            // `.measurement` was the wrong choice: it gives honest level
            // metering for the waveform by switching off input processing —
            // including automatic gain control. The stored audio measured
            // −39.3 LUFS, roughly 20 dB below where speech should sit, so
            // every recording played back nearly inaudible. `.default` keeps
            // AGC; the waveform is drawn from buffer RMS either way, and a
            // gain-corrected signal actually draws a more useful one.
            try session.setCategory(.record, mode: .default, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            // A simulator usually has no audio input device at all: CoreAudio
            // reports "there is no proxy object" and the engine refuses to
            // start with an error nobody can act on. Check first and say
            // something useful instead.
            guard session.isInputAvailable,
                  engine.inputNode.inputFormat(forBus: 0).sampleRate > 0 else {
                state = .failed(Self.noInputMessage)
                cleanUp()
                return
            }

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
                isOnDevice = true
            } else {
                // Honest rather than silent: this locale will use Apple's
                // servers, so the "stays on your device" claim doesn't hold.
                isOnDevice = false
            }
            self.request = request

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)

            // Write the audio as well as recognising it. AAC in m4a, matching
            // the bucket's accepted mimes; the transcript still drives
            // moderation and translation, this is the artifact the group hears.
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("m4a")
            audioFile = try? AVAudioFile(forWriting: url, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: format.channelCount,
                AVEncoderBitRateKey: 48_000
            ])
            if audioFile != nil { recordingURL = url }

            input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
                request.append(buffer)
                try? self?.audioFile?.write(from: buffer)
                let level = Self.level(of: buffer)
                Task { @MainActor in self?.append(level: level) }
            }

            engine.prepare()
            try engine.start()

            started = Date()
            state = .recording
            startTicking()

            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                        if result.isFinal { self.finish() }
                    }
                    if error != nil, self.state == .recording {
                        // A recogniser error after speech has been captured is
                        // not worth losing the text over.
                        self.finish()
                    }
                }
            }
        } catch {
            state = .failed(error.localizedDescription)
            cleanUp()
        }
    }

    func stop() { finish() }

    private func finish() {
        guard state == .recording else { return }
        cleanUp()
        state = .finished
    }

    private func cleanUp() {
        ticker?.invalidate(); ticker = nil
        // Closing the file flushes the AAC encoder; without this the m4a can
        // be truncated or unreadable.
        audioFile = nil
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startTicking() {
        ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let started = self.started else { return }
                self.duration = Date().timeIntervalSince(started)
                if self.duration >= self.maximumDuration { self.finish() }
            }
        }
    }

    private func append(level: CGFloat) {
        levels.append(level)
        if levels.count > 60 { levels.removeFirst(levels.count - 60) }
    }

    /// RMS of the buffer, compressed into something that reads as a waveform.
    private static func level(of buffer: AVAudioPCMBuffer) -> CGFloat {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<frames { sum += channel[i] * channel[i] }
        let rms = sqrt(sum / Float(frames))
        let shaped = CGFloat(min(max(rms * 12, 0), 1))
        return 0.15 + shaped * 0.85
    }

    /// Named rather than inlined so the simulator case reads as a known
    /// limitation rather than a crash.
    static var noInputMessage: String {
        #if targetEnvironment(simulator)
        return "The simulator has no microphone. Turn on Simulator → I/O → "
             + "Audio Input, or run on a device to record."
        #else
        return "No microphone is available right now."
        #endif
    }

    /// Waveform peaks for the backend: 1–512 whole numbers, each 0–100.
    /// Sending these means nobody has to download and decode the audio just
    /// to draw the bars.
    var peaks: [Int] {
        guard !levels.isEmpty else { return [] }
        let target = min(levels.count, 64)
        let stride = max(levels.count / target, 1)
        return Swift.stride(from: 0, to: levels.count, by: stride)
            .prefix(512)
            .map { Int((levels[$0] * 100).rounded()) }
            .map { Swift.min(Swift.max($0, 0), 100) }
    }

    static func durationLabel(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
