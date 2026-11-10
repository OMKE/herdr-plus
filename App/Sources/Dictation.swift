import AVFoundation
import Observation
import Speech
import SwiftUI

@MainActor
@Observable
final class Dictation {
    static let shared = Dictation()

    enum State: Equatable { case idle, starting, listening, failed(String) }

    var state: State = .idle
    var text = ""
    var level: Float = 0

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var finish: ((String) -> Void)?

    var listening: Bool { state == .listening || state == .starting }

    static var languages: [Locale] {
        SFSpeechRecognizer.supportedLocales().sorted { $0.identifier < $1.identifier }
    }

    func start(locale: String, onDevice: Bool) async {
        guard !listening else { return }
        state = .starting
        text = ""
        guard await Self.authorize() else {
            state = .failed("Allow microphone and speech recognition in iOS Settings.")
            return
        }
        let loc = locale.isEmpty ? Locale.current : Locale(identifier: locale)
        guard let rec = SFSpeechRecognizer(locale: loc), rec.isAvailable else {
            state = .failed("Speech recognition isn't available for \(loc.identifier).")
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            req.addsPunctuation = true
            if onDevice && rec.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
            request = req
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buf, _ in
                req.append(buf)
                let n = Int(buf.frameLength)
                guard n > 0, let ch = buf.floatChannelData?[0] else { return }
                var sum: Float = 0
                for i in 0..<n { sum += ch[i] * ch[i] }
                let rms = sqrt(sum / Float(n))
                Task { @MainActor in self?.level = min(1, rms * 12) }
            }
            engine.prepare()
            try engine.start()
            task = rec.recognitionTask(with: req) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result { self.text = result.bestTranscription.formattedString }
                    if error != nil || result?.isFinal == true { self.cleanup() }
                }
            }
            state = .listening
        } catch {
            cleanup()
            state = .failed("Couldn't start the microphone: \(error.localizedDescription)")
        }
    }

    func stop(_ done: ((String) -> Void)? = nil) {
        guard listening else {
            done?(text)
            return
        }
        finish = done
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            if self.finish != nil { self.cleanup() }
        }
    }

    func cancel() {
        finish = nil
        task?.cancel()
        cleanup()
        text = ""
    }

    private func cleanup() {
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        request = nil
        task = nil
        level = 0
        if case .failed = state {} else { state = .idle }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        let f = finish
        finish = nil
        f?(text)
    }

    static func authorize() async -> Bool {
        let speech = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }
}
