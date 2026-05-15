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

    // Diagnostic trace for a single voice-routing turn. Captures the exact
    // prompt sent to Gemma (so we can spot a catalog/cue divergence), the
    // raw model output (so we can see whether the parser stripped useful
    // narration), the parsed plan, and timing/size hints. Published as an
    // @Observable property so the TVScreen debug card refreshes after every
    // tap-to-talk without us having to thread the value back through the
    // call site.
    struct VoiceTrace: Equatable {
        let promptUsed: String
        let rawResponse: String
        let plan: RokuToolKit.Plan
        let elapsed: TimeInterval
        let audioBytes: Int
        let timestamp: Date
        // Best-effort transcript of what Gemma seems to have heard — the
        // first orphan (non-`say`, non-tool) line in the raw response. The
        // audio model often leaks its internal transcription as the first
        // line; surfacing it in the UI's "Heard" column makes ASR errors
        // visible instead of mysterious. nil when Gemma cleanly produced
        // only tool calls + a `say` line.
        let likelyHeard: String?
    }

    private(set) var lastVoiceTrace: VoiceTrace? = nil

    // Plans a voice action via a 2-step pipeline:
    //
    //   Step 1 (audio → text): engine.audio() with a strict transcribe-only
    //                          prompt. The audio model does ONE thing well —
    //                          ASR — and is not asked to route or speak in
    //                          character.
    //   Step 2 (text → plan):  build the same prompt planTextAction uses
    //                          (system + catalog + cues + USER SAID: ...)
    //                          and run it through sessionGenerateStreaming.
    //                          The text path is proven to route correctly,
    //                          so by routing the transcript through it we
    //                          eliminate the audio-model's chronic problem
    //                          of defaulting to generic greetings or
    //                          ignoring the audio content entirely.
    //
    // Side effect: publishes a fresh `lastVoiceTrace` carrying the real
    // transcript so the TV tab's Heard column makes sense.
    //
    // Trade-off: ~2× latency (one audio call + one text call) but the audio
    // call is short (transcribe-only, maxTokens 64) so total stays in the
    // ~6–8s range. Worth it for correctness — the previous single-shot path
    // would mishear "play Young Sheldon" and answer "Hi there!" with no way
    // to tell whether ASR or routing failed.
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

        let start = Date()

        // ───── Step 1: transcribe ─────
        // Prompt is intentionally minimal — the audio model is much better
        // at ASR when not also asked to route, route into a tool catalog,
        // or stay in character. We rip everything else out.
        let transcribePrompt = """
        Transcribe the audio. Output ONLY the exact words actually spoken,
        in plain English.

        Hard rules:
        - Do NOT add words that weren't spoken.
        - Do NOT interpret, embellish, complete, or extend the sentence.
        - Do NOT add sentiment ("I miss her", "please", "thanks") if it
          wasn't said.
        - Do NOT add quotes, labels, prefixes, or commentary.
        - If part is unclear, transcribe only the part you heard. Do not
          fill in the rest.
        - If the audio is silent or unintelligible, output an empty line.

        Reply with the transcription only — nothing else.
        """
        var transcript = ""
        do {
            if sessionOpen { engine.closeSession(); sessionOpen = false }
            let raw = try await engine.audio(
                audioData: audioData,
                prompt: transcribePrompt,
                format: .wav,
                temperature: 0.1,
                maxTokens: 80
            )
            transcript = clean(raw)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"' \t\n"))
        } catch {
            try? await openSession()
            status = .error(error.localizedDescription)
            let fallback = RokuToolKit.Plan(
                calls: [],
                narration: "I had trouble hearing — try once more?"
            )
            lastVoiceTrace = VoiceTrace(
                promptUsed: transcribePrompt,
                rawResponse: "ERROR (transcribe): \(error.localizedDescription)",
                plan: fallback,
                elapsed: Date().timeIntervalSince(start),
                audioBytes: audioData.count,
                timestamp: Date(),
                likelyHeard: nil
            )
            return fallback
        }

        // Empty transcript = nothing to route. Surface a clarification.
        guard !transcript.isEmpty else {
            let fallback = RokuToolKit.Plan(
                calls: [],
                narration: "I didn't catch that — try once more?"
            )
            lastVoiceTrace = VoiceTrace(
                promptUsed: transcribePrompt,
                rawResponse: "(empty transcript)",
                plan: fallback,
                elapsed: Date().timeIntervalSince(start),
                audioBytes: audioData.count,
                timestamp: Date(),
                likelyHeard: nil
            )
            return fallback
        }

        // ───── Step 2: route via text path ─────
        // Same shape as planTextAction's prompt — system + catalog +
        // USER SAID line — so the proven text router handles routing.
        let catalog = RokuToolKit.catalog(showTitles: showTitles, cues: cues)
        let stateBlock = formatState(state)
        let system = """
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
        let routePrompt = "<|turn>user\n\(system)\n\nUSER SAID: \(transcript)\n<turn|>\n<|turn>model\n"

        do {
            if sessionOpen { engine.closeSession(); sessionOpen = false }
            try await engine.openSession(temperature: 0.3, maxTokens: 256)
            sessionOpen = true
            var out = ""
            for try await chunk in engine.sessionGenerateStreaming(input: routePrompt) {
                out += chunk
            }
            engine.closeSession()
            sessionOpen = false
            try? await openSession()

            let cleaned = clean(out)
            let plan = RokuToolKit.parse(cleaned)
            lastVoiceTrace = VoiceTrace(
                promptUsed: routePrompt,
                rawResponse: cleaned,
                plan: plan,
                elapsed: Date().timeIntervalSince(start),
                audioBytes: audioData.count,
                timestamp: Date(),
                likelyHeard: transcript
            )
            return plan
        } catch {
            try? await openSession()
            status = .error(error.localizedDescription)
            let fallback = RokuToolKit.Plan(
                calls: [],
                narration: "I had trouble understanding — try once more?"
            )
            lastVoiceTrace = VoiceTrace(
                promptUsed: routePrompt,
                rawResponse: "ERROR (route): \(error.localizedDescription)",
                plan: fallback,
                elapsed: Date().timeIntervalSince(start),
                audioBytes: audioData.count,
                timestamp: Date(),
                likelyHeard: transcript
            )
            return fallback
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

    // MARK: - Text-mode planning (debug)
    //
    // Mirrors planVoiceAction's prompt but feeds Gemma a typed string
    // instead of audio so we can iterate on routing/cues without
    // recording every test. Returns the parsed Plan plus the raw model
    // output and the exact prompt sent — both critical for the
    // WellnessSheet debug pane.
    struct TextPlanResult {
        let plan: RokuToolKit.Plan
        let rawResponse: String
        let promptUsed: String
        let elapsed: TimeInterval
    }

    func planTextAction(
        text: String,
        state: VoiceWorldState,
        showTitles: [String],
        cues: [RokuToolKit.CueSpec] = []
    ) async -> TextPlanResult? {
        guard case .ready = status, let engine, !generating else { return nil }
        generating = true
        defer { generating = false }

        let catalog = RokuToolKit.catalog(showTitles: showTitles, cues: cues)
        let stateBlock = formatState(state)
        let system = """
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
        let prompt = "<|turn>user\n\(system)\n\nUSER SAID: \(text)\n<turn|>\n<|turn>model\n"

        let start = Date()
        do {
            // Fresh session so previous debug calls don't bleed in.
            if sessionOpen { engine.closeSession(); sessionOpen = false }
            try await engine.openSession(temperature: 0.3, maxTokens: 256)
            sessionOpen = true
            var out = ""
            for try await chunk in engine.sessionGenerateStreaming(input: prompt) {
                out += chunk
            }
            engine.closeSession()
            sessionOpen = false
            try? await openSession()
            let elapsed = Date().timeIntervalSince(start)
            let cleaned = clean(out)
            return TextPlanResult(
                plan: RokuToolKit.parse(cleaned),
                rawResponse: cleaned,
                promptUsed: prompt,
                elapsed: elapsed
            )
        } catch {
            try? await openSession()
            return TextPlanResult(
                plan: RokuToolKit.Plan(calls: [], narration: "Error: \(error.localizedDescription)"),
                rawResponse: "ERROR: \(error.localizedDescription)",
                promptUsed: prompt,
                elapsed: Date().timeIntervalSince(start)
            )
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

    // MARK: - Cue extraction from inbound notes
    //
    // When the caregiver sends a Telegram note ("Hi dad, staying late, home
    // around 8, lasagna in the fridge"), we want Hearth to answer dad's
    // future "where is Sarah?" / "when is dinner?" with that information.
    // The cue catalog already does that — but only if the right keywords
    // are on the cue. Gemma reads the note and predicts likely questions
    // dad might ask, which become the cue's keywords.
    func extractQuestionsForCue(message: String, sender: String) async -> [String]? {
        guard case .ready = status, let engine, !generating else { return nil }
        generating = true
        defer { generating = false }

        let user = """
        Below is a short note from \(sender) to an older relative who has
        mild memory difficulty.

        NOTE: "\(message)"

        Predict 5 to 8 SHORT questions that relative might ask LATER, where
        this note is the answer. Cover:
          - where \(sender) is or what they're doing
          - when \(sender) is coming home / when something happens
          - any specific facts (food, plans, instructions) mentioned

        Reply with ONE question per line. No numbering, no bullets, no
        quotation marks, no preamble. Plain question text only.
        """
        let prompt = "<|turn>user\n\(user)\n<turn|>\n<|turn>model\n"

        do {
            // Reopen the session with more tokens than the default 96 so
            // we get the full list. Restore the default afterwards so the
            // next streaming generation behaves as before.
            if sessionOpen { engine.closeSession(); sessionOpen = false }
            try await engine.openSession(temperature: 0.4, maxTokens: 220)
            sessionOpen = true
            var out = ""
            for try await chunk in engine.sessionGenerateStreaming(input: prompt) {
                out += chunk
            }
            engine.closeSession()
            sessionOpen = false
            try? await openSession()

            let cleaned = clean(out)
            let lines = cleaned
                .split(whereSeparator: \.isNewline)
                .map {
                    String($0)
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "0123456789.-•* \""))
                        .trimmingCharacters(in: .whitespaces)
                }
                .filter { !$0.isEmpty && $0.count <= 80 }
                .prefix(8)
            let result = Array(lines)
            return result.isEmpty ? nil : result
        } catch {
            try? await openSession()
            return nil
        }
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
