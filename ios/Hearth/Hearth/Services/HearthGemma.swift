import Foundation
import SwiftUI
import Observation
import LiteRTLMSwift

@Observable
@MainActor
final class HearthGemma {

    enum Status: Equatable {
        case idle
        case downloading(progress: Double)
        case loadingEngine
        case ready
        case error(String)
    }

    var status: Status = .idle

    let downloader = ModelDownloader()
    private var engine: LiteRTLMEngine?
    private var sessionOpen = false
    private var generating = false

    // MARK: Setup

    func prepareIfNeeded() async {
        if case .ready = status { return }
        await reconcileFromDownloader()
        if case .completed = downloader.status {
            await loadEngine()
        }
    }

    func startDownload() async {
        await reconcileFromDownloader()
        do {
            try await downloader.download()
        } catch {
            status = .error(error.localizedDescription)
            return
        }
        await reconcileFromDownloader()
        if case .completed = downloader.status {
            await loadEngine()
        }
    }

    func pauseDownload() {
        downloader.pause()
        Task { await reconcileFromDownloader() }
    }

    func loadEngine() async {
        guard case .completed = downloader.status else { return }
        if case .ready = status { return }
        status = .loadingEngine
        do {
            if engine == nil {
                engine = LiteRTLMEngine(modelPath: downloader.modelPath)
            }
            try await engine?.load()
            try await openSession()
            status = .ready
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    private func openSession() async throws {
        guard let engine else { return }
        if sessionOpen { engine.closeSession(); sessionOpen = false }
        try await engine.openSession(temperature: 0.7, maxTokens: 96)
        sessionOpen = true
    }

    private func reconcileFromDownloader() async {
        switch downloader.status {
        case .notStarted, .paused, .failed:
            if case .ready = status { return }
            status = .idle
        case .downloading(let progress):
            status = .downloading(progress: progress)
        case .completed:
            if case .ready = status { return }
            if case .loadingEngine = status { return }
            // Caller decides whether to load the engine.
            break
        }
    }

    // MARK: Generation

    // Snapshot of the current world passed to Gemma so it can plan in one
    // shot. Time fields matter for cue answers that mention a schedule
    // ("Take meds at 9 AM" — at 11 PM, Gemma should say "in the morning,
    // about 9 hours away," not recite the script blindly).
    struct VoiceWorldState {
        let rokuStatus: String          // "ready", "unreachable", "unconfigured"
        let activeShowTitle: String?    // what Hearth last launched
        let activeEpisode: String?
        let playbackState: String?      // "playing"/"paused"/"stopped"/"idle"
        let positionSeconds: Int?
        let durationSeconds: Int?
        let clock: String?              // "11:58 PM"
        let dayOfWeek: String?          // "Wednesday"
        let weatherTemperature: String? // "72°F" — for Weather cue grounding
    }

    // Plans a voice action with Gemma's audio model + the RokuToolKit catalog.
    // Single-shot tool calling: the model sees the user's audio, the current
    // world state, the Roku tool catalog, and the caregiver-authored cue
    // catalog, then emits one tool call per line followed by a `say` line.
    // Returns the parsed Plan, or an empty Plan if Gemma is busy or errors out.
    func planVoiceAction(
        audioData: Data,
        state: VoiceWorldState,
        showTitles: [String],
        cues: [RokuToolKit.CueSpec] = []
    ) async -> RokuToolKit.Plan {
        guard case .ready = status, let engine, !generating else {
            return RokuToolKit.Plan(calls: [], narration: nil)
        }
        generating = true
        defer { generating = false }

        let catalog = RokuToolKit.catalog(showTitles: showTitles, cues: cues)
        let stateBlock = formatState(state)
        let prompt = """
        You are Hearth's voice companion on the iPad. You help this person, who
        has mild memory difficulty, in two ways:
          1) ANSWER questions using the CUES — caregiver-authored facts about
             this specific person. This is your primary job.
          2) ACT on TV requests using the TOOLS.

        Speak warmly, briefly, as if mid-conversation. Never frame yourself as
        a TV-only helper — cues are first-class.

        RIGHT NOW
        \(stateBlock)

        \(catalog)
        """

        do {
            if sessionOpen { engine.closeSession(); sessionOpen = false }
            let result = try await engine.audio(
                audioData: audioData,
                prompt: prompt,
                format: .wav,
                temperature: 0.3,
                maxTokens: 256
            )
            try? await openSession()
            return RokuToolKit.parse(clean(result))
        } catch {
            try? await openSession()
            status = .error(error.localizedDescription)
            return RokuToolKit.Plan(calls: [], narration: "I had trouble hearing — try once more?")
        }
    }

    private func formatState(_ s: VoiceWorldState) -> String {
        var lines: [String] = []
        if let clock = s.clock {
            let dow = s.dayOfWeek.map { ", \($0)" } ?? ""
            lines.append("- Time: \(clock)\(dow)")
        }
        if let temp = s.weatherTemperature {
            lines.append("- Weather outside: \(temp)")
        }
        lines.append("- TV connection: \(s.rokuStatus)")
        if let title = s.activeShowTitle {
            lines.append("- Currently active show in Hearth: \(title)")
        }
        if let ep = s.activeEpisode {
            lines.append("- Episode label (what Hearth launched): \(ep)")
        }
        if let st = s.playbackState {
            lines.append("- Playback state: \(st)")
        }
        if let p = s.positionSeconds, let d = s.durationSeconds, d > 0 {
            let percent = p * 100 / d
            lines.append("- Position: \(Self.clock(p)) of \(Self.clock(d)) (\(percent)%)")
        }
        return lines.joined(separator: "\n")
    }

    private static func clock(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    struct TVContext {
        let title: String
        let episode: String
        let stateLabel: String        // "playing", "paused", "loading", "stopped"
        let positionSeconds: Int?
        let durationSeconds: Int?
    }

    // One-shot narration for the TV's "What's happening?" chip. Grounded in
    // real Roku state (position/duration). Returns nil if Gemma isn't ready
    // or generation fails — caller falls back to a plain truthful sentence.
    func generateTVStateLine(_ ctx: TVContext) async -> String? {
        guard case .ready = status, let engine, !generating else { return nil }
        generating = true
        defer { generating = false }

        let position = ctx.positionSeconds.map(Self.fmtClock) ?? "unknown"
        let duration = ctx.durationSeconds.map(Self.fmtClock) ?? "unknown"
        let progress: String = {
            guard let p = ctx.positionSeconds, let d = ctx.durationSeconds, d > 0
            else { return "unknown" }
            return "\(p * 100 / d)% through"
        }()

        let user = """
        Write ONE warm, calm sentence (max 25 words) that orients an older
        viewer with mild memory difficulty about what they're watching right
        now. Be specific and gentle. No greetings. Reassure that nothing is
        lost. Never invent details.

        Facts (use only these):
        - Show: \(ctx.title)
        - Episode: \(ctx.episode)
        - Playback state: \(ctx.stateLabel)
        - Current time in episode: \(position)
        - Total length of episode: \(duration)
        - Progress: \(progress)

        Reply with just the sentence, no quotes, no preamble.
        """
        let prompt = "<|turn>user\n\(user)\n<turn|>\n<|turn>model\n"

        do {
            if !sessionOpen {
                try await engine.openSession(temperature: 0.7, maxTokens: 96)
                sessionOpen = true
            }
            var out = ""
            for try await chunk in engine.sessionGenerateStreaming(input: prompt) {
                out += chunk
            }
            engine.closeSession()
            sessionOpen = false
            let cleaned = clean(out)
            return cleaned.isEmpty ? nil : cleaned
        } catch {
            status = .error(error.localizedDescription)
            return nil
        }
    }

    // MARK: - Vision (pairwise person verifier)

    // Result of a single pairwise comparison. `reasoning` is Gemma's own
    // one-sentence justification — exposed to the UI so the caregiver
    // (and the demo audience) can see Gemma actually thought about it,
    // not just rubber-stamped yes/no.
    struct VerifyResult: Equatable {
        let isMatch: Bool
        let reasoning: String
    }

    // Re-ranks the Apple Vision shortlist on the People tab. Sends the
    // captured photo + the candidate's indexed photo through Gemma's
    // multi-image vision path and asks for BOTH a yes/no verdict AND a
    // short sentence explaining what Gemma saw. Returns both so the UI
    // can render the reasoning.
    func verifySamePerson(
        capturedJpeg: Data,
        referenceJpeg: Data
    ) async -> VerifyResult {
        guard case .ready = status, let engine, !generating else {
            return VerifyResult(isMatch: false, reasoning: "Gemma wasn't ready.")
        }
        generating = true
        defer { generating = false }

        let prompt = """
        Look at these two photographs.
        Image 1: a candidate face to identify.
        Image 2: a reference photo of a known person.

        Are Image 1 and Image 2 photos of the SAME PERSON?
        Compare face shape, eyes, nose, mouth, hair, age. Ignore differences
        in lighting, pose, expression, or whether one is a screen recapture.

        Reply on EXACTLY two lines, in this format and nothing else:
        REASONING: <one short sentence (max 20 words) naming the key
        features you compared and what they tell you>
        VERDICT: yes
           or
        VERDICT: no
        """

        do {
            // visionMultiImage uses the Conversation API, which can't run
            // while a Session is open. Close the session, run the vision
            // call, then reopen the session for the next text generation.
            // Same pattern as the audio path on the Watch tab.
            if sessionOpen { engine.closeSession(); sessionOpen = false }
            let raw = try await engine.visionMultiImage(
                imagesData: [capturedJpeg, referenceJpeg],
                prompt: prompt,
                temperature: 0.2,
                maxTokens: 96
            )
            try? await openSession()
            let result = Self.parseVerify(raw)
            print("[Hearth] verifySamePerson raw=\(raw.prefix(160)) -> \(result)")
            return result
        } catch {
            try? await openSession()
            return VerifyResult(
                isMatch: false,
                reasoning: "Gemma error: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Vision (presence sensing)

    // Yes/no: is a person visible in this frame? Powers the Watch tab's
    // presence-sensing loop. Cheaper prompt than the pairwise verifier
    // because we only need a single bit out — Gemma can spend its tokens
    // on confidence, not reasoning.
    func detectPresence(imageData: Data) async -> Bool? {
        guard case .ready = status, let engine, !generating else { return nil }
        generating = true
        defer { generating = false }

        let prompt = """
        Look at this photograph of a room.

        Is there a human person visible anywhere in the frame? Even partially
        — an arm, a leg, a person in the background — counts as yes. Ignore
        people on TV screens, in photographs on walls, or in posters.

        Reply with ONLY one word: yes or no. No punctuation.
        """

        do {
            if sessionOpen { engine.closeSession(); sessionOpen = false }
            let raw = try await engine.vision(
                imageData: imageData,
                prompt: prompt,
                temperature: 0.1,
                maxTokens: 8
            )
            try? await openSession()
            let first = clean(raw)
                .lowercased()
                .split(whereSeparator: { !$0.isLetter })
                .first
                .map(String.init) ?? ""
            print("[Hearth] detectPresence raw=\(raw.prefix(40)) -> first=\(first)")
            return first == "yes" || first == "y"
        } catch {
            try? await openSession()
            return nil
        }
    }

    // Parse Gemma's REASONING/VERDICT reply. Tolerates label drift (case,
    // missing colon) and falls back to first-word heuristic if Gemma
    // skipped the format. Always returns something so the UI never goes
    // blank on a model that decided to be creative.
    private static func parseVerify(_ raw: String) -> VerifyResult {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var reasoning = ""
        var verdict: Bool? = nil

        for rawLine in cleaned.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            let upper = line.uppercased()
            if upper.hasPrefix("REASONING:") {
                reasoning = String(line.dropFirst("REASONING:".count))
                    .trimmingCharacters(in: .whitespaces)
            } else if upper.hasPrefix("REASONING ") {
                reasoning = String(line.dropFirst("REASONING ".count))
                    .trimmingCharacters(in: .whitespaces)
            } else if upper.hasPrefix("VERDICT:") {
                let body = String(line.dropFirst("VERDICT:".count))
                    .trimmingCharacters(in: .whitespaces).lowercased()
                verdict = body.hasPrefix("yes") || body == "y"
            } else if upper.hasPrefix("VERDICT ") {
                let body = String(line.dropFirst("VERDICT ".count))
                    .trimmingCharacters(in: .whitespaces).lowercased()
                verdict = body.hasPrefix("yes") || body == "y"
            }
        }

        // Fallback: model ignored the format. Use first letter-word as the
        // verdict and the whole reply (sans that word) as the reasoning.
        if verdict == nil {
            let first = cleaned
                .lowercased()
                .split(whereSeparator: { !$0.isLetter })
                .first
                .map(String.init) ?? ""
            verdict = (first == "yes" || first == "y")
            if reasoning.isEmpty { reasoning = cleaned }
        }

        if reasoning.isEmpty {
            reasoning = "(Gemma gave no reasoning)"
        }
        return VerifyResult(isMatch: verdict ?? false, reasoning: reasoning)
    }

    private static func fmtClock(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        if m == 0 { return "\(s) seconds" }
        if s == 0 { return m == 1 ? "1 minute" : "\(m) minutes" }
        return "\(m) min \(s) sec"
    }

    private func clean(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip stray turn-token leftovers if the model emits them.
        let strip = ["<turn|>", "<|turn>", "<end_of_turn>", "<|end_of_text|>", "model\n", "user\n"]
        for token in strip { s = s.replacingOccurrences(of: token, with: "") }
        // Drop surrounding quotes if the model wrapped its reply.
        if s.hasPrefix("\""), s.hasSuffix("\""), s.count > 1 {
            s = String(s.dropFirst().dropLast())
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
