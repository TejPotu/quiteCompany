import Foundation

// Tool-calling layer Gemma uses to drive Roku. Three pieces:
//   1. catalog — plain-text description Gemma sees in its prompt.
//   2. Plan / ToolCall — the parsed result of Gemma's response.
//   3. Executor — runs each call against RokuController.
//
// Line-based grammar (one call per line) instead of JSON because smaller
// models follow simple grammars more reliably and there's no markdown-fence
// noise to strip.

enum RokuToolKit {

    /// Catalog text injected into Gemma's prompt. Cues come FIRST (knowledge
    /// before actions), then TOOLS, then OUTPUT shape, then examples that
    /// teach fuzzy matching + reasoned prose (not verbatim recitation).
    static func catalog(showTitles: [String], cues: [CueSpec] = []) -> String {
        let titles = showTitles.joined(separator: ", ")
        var out = ""

        if !cues.isEmpty {
            out += "CUES — caregiver-authored knowledge about THIS person. These are\n"
            out += "your highest priority — most questions are answered from these, not\n"
            out += "from TV tools. The Hears phrases are just hints; match meaning, not\n"
            out += "exact words. Reason naturally from Content + Schedule + Threshold +\n"
            out += "the current time/weather. Speak in plain prose; do NOT recite the\n"
            out += "Content verbatim if it would sound robotic or contradict the moment.\n\n"
            for cue in cues {
                let kw = cue.keywords.map { "\u{201C}\($0)\u{201D}" }.joined(separator: ", ")
                out += "- \(cue.name)\n"
                out += "  Hears (examples — match meaning, not wording): \(kw)\n"
                out += "  Content: \(cue.value)\n"
                if let s = cue.schedule, !s.isEmpty { out += "  Schedule: \(s)\n" }
                if let t = cue.threshold, !t.isEmpty { out += "  Threshold: \(t)\n" }
            }
            out += "\n"
        }

        out += """
        TOOLS — TV control. One per line, args space-separated. Numbers in
        brackets are repeat counts (default 1). Use these ONLY for clear TV
        intent (pause, louder, put on a show, etc.).

        - play                — toggle play/pause
        - volumeUp [n]        — louder, n times
        - volumeDown [n]      — quieter, n times
        - mute                — toggle mute
        - rewind [n]          — InstantReplay (~10s back), n times
        - fastForward [n]     — Fwd key, n times
        - next                — Select key (advances Netflix Up Next overlay)
        - home                — back to Roku home, stops watching
        - launchShow <title>  — open a show by exact title from this list:
          \(titles)
        - press <key>         — any Roku key: Up, Down, Left, Right, Select,
                                Back, Info, Search, VolumeMute, ChannelUp,
                                ChannelDown, PowerOff, InstantReplay, Rev, Fwd

        OUTPUT — reply as exactly one of:
        A) Cue answer (no tool call):
             say <warm sentence weaving cue facts with right-now context>
        B) TV action (one or more tool lines) ending with a say-line:
             <tool> [args]
             say <one short sentence about what just happened>
        C) Genuinely unsure:
             say <one short follow-up question — never echo their words>

        STRICT RULES:
        - NEVER echo the user's question back as your say-line.
        - NEVER say "I'm here to help with the TV" or similar refusals.
          Cues are first-class — answer from them.
        - NEVER invent facts beyond Content/Schedule/Threshold + Right-Now.
        - If you can hear ANY topic word that maps to a cue (weather, cold,
          hot, jacket, medicine, pills, meds, tablets, news, show, time…),
          you MUST answer from that cue. Do NOT fall back to "I didn't catch
          that" — that response is ONLY for true silence or fully unparseable
          audio.
        - No preamble, no markdown, no labels. Just the lines.

        EXAMPLES — study how cue facts get REASONED about, not recited.

        > pause this
        play
        say Paused.

        > turn it down a lot
        volumeDown 4
        say Quieter now.

        > put on Young Sheldon
        launchShow Young Sheldon
        say Putting on Young Sheldon.

        """

        if let med = cues.first(where: { $0.name.lowercased().contains("medic") || $0.name.lowercased().contains("pill") }) {
            _ = med
            out += "// [Medicine cue, Right now is late at night]\n"
            out += "> is it time for my medicine\n"
            out += "say Not yet — that's tomorrow morning around nine. Plenty of time to rest.\n\n"
            out += "// [Medicine cue, Right now around 9 AM]\n"
            out += "> did I take my pills\n"
            out += "say They're due right about now. The organizer is on the desk by the TV — the red one from the morning slot.\n\n"
        }

        if let weather = cues.first(where: { $0.name.lowercased().contains("weather") }) {
            _ = weather
            out += "// [Weather cue, outside is 45°F]\n"
            out += "> is it cold\n"
            out += "say A little chilly out — in the forties. A jacket would help if you head out.\n\n"
            out += "// [Weather cue, outside is 72°F]\n"
            out += "> how's the weather\n"
            out += "say It feels mild today — about seventy-two and comfortable. No jacket needed.\n"
        }

        return out
    }

    // Lightweight value type used to inject cues into the prompt without
    // dragging UI-bound CueEntry into the service layer.
    struct CueSpec: Equatable {
        let name: String
        let keywords: [String]
        let value: String
        var schedule: String? = nil
        var threshold: String? = nil
    }

    struct Plan: Equatable {
        var calls: [ToolCall]
        var narration: String?

        static let empty = Plan(calls: [], narration: nil)
    }

    struct ToolCall: Equatable {
        let name: String
        let args: String   // remainder of the line; tool-specific parsing
    }

    /// Parses Gemma's raw response. Permissive: any non-tool, non-comment
    /// line becomes part of the narration even without a `say` prefix —
    /// otherwise Gemma's natural prose answers (which often drop the prefix)
    /// would be discarded and the UI would fall back to "didn't catch that."
    static func parse(_ raw: String) -> Plan {
        var calls: [ToolCall] = []
        var saySegments: [String] = []
        var orphan: [String] = []

        for rawLine in raw.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "-*•>"))
                .trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            // Drop comment lines that may leak from examples (e.g. "// [Weather cue, ...]").
            if line.hasPrefix("//") || line.hasPrefix("#") { continue }

            // Explicit SAY narration line.
            if let stripped = line.dropPrefix(caseInsensitive: "say ") {
                saySegments.append(stripped.trimmingCharacters(in: .whitespaces))
                continue
            }

            // Possible tool call.
            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard let head = parts.first else { continue }
            let name = String(head).lowercased()
            let args = parts.count > 1
                ? String(parts[1]).trimmingCharacters(in: .whitespaces)
                : ""
            if knownTools.contains(name) {
                calls.append(ToolCall(name: name, args: args))
            } else {
                // Not a tool — treat as narration prose Gemma forgot to prefix.
                orphan.append(line)
            }
        }

        var narration: String? = saySegments.isEmpty
            ? nil
            : saySegments.joined(separator: " ")
        if narration == nil, !orphan.isEmpty {
            narration = orphan.joined(separator: " ")
        }
        return Plan(calls: calls, narration: narration)
    }

    private static let knownTools: Set<String> = [
        "play", "volumeup", "volumedown", "mute",
        "rewind", "fastforward", "next", "home",
        "launchshow", "press"
    ]
}

@MainActor
struct RokuToolExecutor {
    let roku: RokuController
    let shows: [Show]

    func execute(_ call: RokuToolKit.ToolCall) async {
        switch call.name {
        case "play":
            await roku.play()
        case "volumeup":
            await repeat_(call.intArg(default: 1)) { await roku.volumeUp() }
        case "volumedown":
            await repeat_(call.intArg(default: 1)) { await roku.volumeDown() }
        case "mute":
            await roku.press("VolumeMute")
        case "rewind":
            await roku.instantReplay(times: clamp(call.intArg(default: 1)))
        case "fastforward":
            await repeat_(call.intArg(default: 1)) { await roku.fastForward() }
        case "next":
            await roku.nextEpisode()
        case "home":
            await roku.home()
        case "launchshow":
            if let show = findShow(title: call.args) {
                await roku.launchShow(show)
            }
        case "press":
            await roku.press(call.args)
        default:
            break
        }
    }

    // Run an action N times with a small cap so a hallucinated "volumeUp 999"
    // doesn't blast the TV. 10 is plenty for everyday voice phrasing.
    private func repeat_(_ n: Int, _ action: () async -> Void) async {
        for _ in 0..<clamp(n) { await action() }
    }

    private func clamp(_ n: Int) -> Int { max(1, min(n, 10)) }

    private func findShow(title: String) -> Show? {
        let normalized = title.lowercased()
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "'", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty else { return nil }
        return shows.first { show in
            let candidate = show.title.lowercased()
                .replacingOccurrences(of: "*", with: "")
                .replacingOccurrences(of: "'", with: "")
            return candidate == normalized
                || candidate.contains(normalized)
                || normalized.contains(candidate)
        }
    }
}

// MARK: - Small helpers

private extension RokuToolKit.ToolCall {
    func intArg(default fallback: Int) -> Int {
        let head = args.split(separator: " ").first.map(String.init) ?? args
        return Int(head) ?? fallback
    }
}

private extension String {
    /// If `self` starts with `prefix` (case-insensitive), returns the rest.
    func dropPrefix(caseInsensitive prefix: String) -> String? {
        guard lowercased().hasPrefix(prefix.lowercased()) else { return nil }
        return String(dropFirst(prefix.count))
    }
}
