import Foundation
import AVFoundation
import os

// 16 kHz mono PCM WAV recorder — the format LiteRTLM expects for engine.audio().
// Same settings as gemmaDemo's working recorder. Owned by TVScreen for the
// voice control loop; not @Observable because the UI tracks state itself.
@MainActor
final class AudioRecorder {

    private var recorder: AVAudioRecorder?
    private var url: URL?
    private static let log = Logger(subsystem: "Hearth", category: "Audio")

    // Asks for mic permission, configures the session, starts capturing.
    // Returns false if permission was denied or the session couldn't start.
    func start() async -> Bool {
        guard await Self.requestPermission() else { return false }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord,
                                    mode: .default,
                                    options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            Self.log.error("Audio session setup failed: \(error.localizedDescription)")
            return false
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hearth-voice.wav")
        self.url = url

        let settings: [String: Any] = [
            AVFormatIDKey:           Int(kAudioFormatLinearPCM),
            AVSampleRateKey:         16000,
            AVNumberOfChannelsKey:   1,
            AVLinearPCMBitDepthKey:  16,
            AVLinearPCMIsFloatKey:   false,
            AVLinearPCMIsBigEndianKey: false
        ]
        do {
            recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder?.record()
            return true
        } catch {
            Self.log.error("Recorder start failed: \(error.localizedDescription)")
            return false
        }
    }

    // Stop and return the WAV bytes. Caller hands these to Gemma.
    func stop() -> Data? {
        recorder?.stop()
        recorder = nil
        // Release the session so Bluetooth audio / other apps can use mic.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        guard let url else { return nil }
        return try? Data(contentsOf: url)
    }

    private static func requestPermission() async -> Bool {
        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        }
        return await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
    }
}
