import Foundation
import SwiftUI
import Observation
import LiteRTLMSwift

// First Gemma surface: writes the orienting line on HomeScreen, grounded in
// real app state (time, day, next reminder). Falls back to nil if the engine
// isn't ready — callers keep their existing hardcoded line in that case.
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
    private(set) var lastHomeLine: String?

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

    // Snapshot of the current TV state passed to Gemma so it can plan in one
    // shot ("they said 'next' and we're 99% in — that's the Up Next overlay
    // moment"). All fields are optional; pass what you have.
    struct VoiceWorldState {
        let rokuStatus: String          // "ready", "unreachable", "unconfigured"
        let activeShowTitle: String?    // what Hearth last launched
        let activeEpisode: String?
        let playbackState: String?      // "playing"/"paused"/"stopped"/"idle"
        let positionSeconds: Int?
        let durationSeconds: Int?
    }

    // Plans a voice action with Gemma's audio model + the RokuToolKit catalog.
    // Single-shot tool calling: the model sees the user's audio, the current
    // world state, and the tool catalog, then emits one tool call per line
    // followed by a `say` line for narration. Returns the parsed Plan, or an
    // empty Plan if Gemma is busy or errors out.
    func planVoiceAction(
        audioData: Data,
        state: VoiceWorldState,
        showTitles: [String]
    ) async -> RokuToolKit.Plan {
        guard case .ready = status, let engine, !generating else {
            return RokuToolKit.Plan(calls: [], narration: nil)
        }
        generating = true
        defer { generating = false }

        let catalog = RokuToolKit.catalog(showTitles: showTitles)
        let stateBlock = formatState(state)
        let prompt = """
        You are the voice agent inside Hearth, an iPad app helping someone with
        mild memory difficulty control their TV. The user just spoke. Decide
        which Roku tools to call and what to say back. Be warm and gentle.

        CURRENT STATE
        \(stateBlock)

        TOOLS
        \(catalog)

        Reply ONLY with tool calls (one per line) followed by a single `say`
        line. No preamble, no markdown, no explanations. If you're not sure
        what they meant, reply only with a `say` line asking them to try again.
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
        if lines.count == 1 { lines.append("- (no further playback info)") }
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

    private static func fmtClock(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        if m == 0 { return "\(s) seconds" }
        if s == 0 { return m == 1 ? "1 minute" : "\(m) minutes" }
        return "\(m) min \(s) sec"
    }

    struct HomeContext {
        let timeOfDay: String       // "morning", "afternoon", "evening", "night"
        let dayOfWeek: String       // "Tuesday"
        let clock: String           // "8:42 AM"
        let nextReminder: String?   // "Medicine at 9:00 AM, about 18 minutes away"
    }

    func generateHomeLine(_ ctx: HomeContext) async {
        guard case .ready = status, let engine, !generating else { return }
        generating = true
        defer { generating = false }

        let next = ctx.nextReminder ?? "no specific reminder coming up"
        let user = """
        Write ONE warm, calm sentence (max 22 words) that orients an older
        viewer with mild memory difficulty. Be specific and gentle. No greetings
        like "Hello" — speak as if continuing a quiet conversation. Never invent
        events. Never blame. Use only these facts:

        - Time of day: \(ctx.timeOfDay)
        - Day: \(ctx.dayOfWeek)
        - Clock: \(ctx.clock)
        - Next thing: \(next)

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
            // Reset for the next single-shot turn so prompts don't compound.
            engine.closeSession()
            sessionOpen = false
            let cleaned = clean(out)
            if !cleaned.isEmpty { lastHomeLine = cleaned }
        } catch {
            status = .error(error.localizedDescription)
        }
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
