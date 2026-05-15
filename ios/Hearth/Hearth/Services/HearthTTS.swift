import Foundation
import AVFoundation
import Observation

// On-device text-to-speech for everything Hearth wants to read aloud:
//   - voice orchestrator narration ("Around nine in the morning, plenty of
//     time to rest")
//   - caregiver messages ("Hi dad, staying late tonight…")
//   - person-recognition cards ("This is Sarah, your daughter")
//
// Uses AVSpeechSynthesizer — fully on-device, free, decent quality with
// any neural voice the user has installed. Configured for spoken-audio
// playback with .duckOthers so the Roku TV's audio quiets while Hearth
// is speaking. A single isEnabled toggle (persisted) kills every call
// site at once.
@Observable @MainActor
final class HearthTTS: NSObject {

    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Key.enabled)
            if !isEnabled { stop() }
        }
    }

    /// Identifier of the voice the user picked in the Wellness sheet.
    /// `nil` = auto-pick the highest-quality English voice on the device.
    var selectedVoiceIdentifier: String? {
        didSet {
            if let id = selectedVoiceIdentifier {
                UserDefaults.standard.set(id, forKey: Key.voiceId)
            } else {
                UserDefaults.standard.removeObject(forKey: Key.voiceId)
            }
        }
    }

    private(set) var isSpeaking: Bool = false
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        // Default ON for the demo so spoken playback is the out-of-box
        // experience; caregivers can flip it off from the Wellness sheet.
        let stored = UserDefaults.standard.object(forKey: Key.enabled) as? Bool
        self.isEnabled = stored ?? true
        self.selectedVoiceIdentifier = UserDefaults.standard.string(forKey: Key.voiceId)
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
    }

    /// Natural-sounding English voices installed on the device. We hide
    /// the bundled `.default` compact voices entirely — those are the
    /// robotic-sounding ones, and showing them just clutters the picker
    /// once the user has installed a Premium voice. Sorted Premium →
    /// Enhanced, then alphabetically.
    static func voicesForPicker() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .filter { $0.quality == .premium || $0.quality == .enhanced }
            .sorted {
                if $0.quality.rawValue != $1.quality.rawValue {
                    return $0.quality.rawValue > $1.quality.rawValue
                }
                return $0.name < $1.name
            }
    }

    /// Resolve the voice to use for the next utterance. Honors the user's
    /// explicit pick when set + still installed; otherwise picks the best
    /// Premium/Enhanced English voice available. If none are installed,
    /// falls back to whatever the system can produce so playback never
    /// silently dies — even if it sounds robotic.
    private func voiceToUse() -> AVSpeechSynthesisVoice? {
        if let id = selectedVoiceIdentifier,
           let chosen = AVSpeechSynthesisVoice(identifier: id) {
            return chosen
        }
        if let best = Self.voicesForPicker().first {
            return best
        }
        return AVSpeechSynthesisVoice(language: "en-US")
    }

    /// Speak the given text. Cancels anything currently speaking so the
    /// most recent utterance wins (avoids overlapping narrations when the
    /// user fires actions back-to-back).
    func speak(_ text: String) {
        guard isEnabled else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = voiceToUse()
        // 0.5 is iOS's natural baseline — anything slower starts to feel
        // robotic on its own, which defeats the point of picking a good
        // voice.
        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.0
        utterance.preUtteranceDelay = 0.0
        utterance.postUtteranceDelay = 0.1
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    private func configureAudioSession() {
        // .playback so Hearth's voice plays through the loud speaker
        // (not the earpiece on an iPad-shaped device). .spokenAudio is
        // the iOS hint for narration/TTS — gives the system the right
        // routing + interruption rules. .duckOthers softens whatever
        // else is playing on the device (e.g. TV via Roku — though Roku
        // audio is on the TV, not the iPad — and any local media).
        try? AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .spokenAudio,
            options: [.duckOthers]
        )
        try? AVAudioSession.sharedInstance().setActive(true, options: [])
    }

    private enum Key {
        static let enabled = "hearth.tts.enabled"
        static let voiceId = "hearth.tts.voiceId"
    }
}

extension AVSpeechSynthesisVoiceQuality {
    /// Short human label for voice picker rows.
    var label: String {
        switch self {
        case .premium:  return "Premium"
        case .enhanced: return "Enhanced"
        case .default:  return "Default"
        @unknown default: return "Default"
        }
    }
}

extension HearthTTS: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart u: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = true }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}
