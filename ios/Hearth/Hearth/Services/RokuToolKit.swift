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

        // Split family notes from caregiver-authored standing cues. Family
        // notes are time-sensitive answers to "where/when/what about
        // <person>" and need their own section so Gemma reaches for them
        // first instead of defaulting to a topic cue (weather, medicine,
        // …) when a person's name is mentioned.
        let familyNotes = cues.filter { $0.name.lowercased().hasPrefix("note from ") }
        let standingCues = cues.filter { !$0.name.lowercased().hasPrefix("note from ") }

        if !familyNotes.isEmpty {
            out += "TODAY'S FAMILY NOTES — time-sensitive messages family members\n"
            out += "have sent to this person today. If the user mentions someone by\n"
            out += "name (Sarah, mom, daughter, etc.) or with a pronoun (\"where is\n"
            out += "she\", \"when is he coming\"), and there's a note from that\n"
            out += "person below, you MUST answer from that note in a warm sentence.\n\n"
            for note in familyNotes {
                // "Note from Sarah" -> "Sarah"
                let sender = note.name
                    .replacingOccurrences(of: "Note from ", with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespaces)
                out += "- From \(sender)\n"
                out += "  Content: \(note.value)\n"
                out += "  Patient may ask: \(note.keywords.map { "\u{201C}\($0)\u{201D}" }.joined(separator: ", "))\n"
            }
            out += "\n"
        }

        if !standingCues.isEmpty {
            out += "CUES — caregiver-authored standing knowledge. The Hears phrases\n"
            out += "are hints; match meaning, not exact words. Reason naturally from\n"
            out += "Content + Schedule + Threshold + the current time/weather. Speak\n"
            out += "in plain prose; do NOT recite the Content verbatim if it would\n"
            out += "sound robotic or contradict the moment.\n\n"
            for cue in standingCues {
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
        brackets are repeat counts (default 1).

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

        ROUTING — every request falls into exactly ONE of three buckets:

        1) TV CONTROL — user wants to change what's on the TV (pause,
           play, louder, quieter, mute, rewind/back, fast forward,
           next episode, go home, launch a specific show). Emit the
           matching tool line, then a short say-line confirming.

        2) NOTE / CUE ANSWER — user's question is genuinely about
           something in TODAY'S FAMILY NOTES or CUES above. Answer
           warmly in one sentence, reasoning from the content + the
           Right-Now state (time, weather). NEVER recite verbatim;
           NEVER stretch a cue to fit an unrelated question.

        3) GENERAL CONVERSATION — anything else: greetings, "what can
           you do", small talk, factual questions you know the answer
           to. Just answer naturally and briefly using your own
           knowledge, like a calm companion would. Do NOT redirect to
           the TV. Do NOT shoehorn a cue.

        OUTPUT — exactly one of two shapes, NO labels, NO headers:
          For a question/note answer: a single line starting with `say `
              followed by your short warm sentence. Nothing before `say`.
          For a TV action: one tool line, then on the next line a single
              `say <short confirmation>`. Nothing before the tool name.

        NEVER write words like "Note answer:", "Cue answer:", "TV action:",
        "Answer:", or any other label in your reply. Just the `say` line
        (or a tool line + `say` line).

        HARD RULES:
        - NEVER echo the user's question back.
        - NEVER invent personal facts (names, schedules) not in the
          notes or cues. For general questions, use your own knowledge
          but keep it brief and grounded.
        - One reply only. No preamble, no markdown, no labels.

        EXAMPLES — one per route.

        // TV CONTROL
        > pause this
        play
        say Paused.

        > turn it down a lot
        volumeDown 4
        say Quieter now.

        > put on Young Sheldon
        launchShow Young Sheldon
        say Putting on Young Sheldon.

        // GENERAL CONVERSATION — your own knowledge, kept brief
        > what can you do
        say I can change shows for you, remind you about the things we've set up together, and tell you what's playing. Just ask.

        > tell me a joke
        say Why don't scientists trust atoms? Because they make up everything.

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
            out += "say It feels mild today — about seventy-two and comfortable. No jacket needed.\n\n"
        }

        if cues.contains(where: { $0.name.lowercased().hasPrefix("note from ") }) {
            // The example uses a clearly-fictional note (Maria / groceries /
            // seven) so Gemma cannot memorize-and-parrot the answer. The
            // teaching point is: read the Content of the matching note, then
            // paraphrase warmly. The earlier wording ("Sarah / at work / around
            // eight / lasagna") was being copied verbatim regardless of the
            // real note content — the placeholder words made it look like
            // factual data to repeat.
            out += "// [Suppose today's note is — From Maria, Content: \"Picking up groceries, home by 7.\"]\n"
            out += "> where is Maria\n"
            out += "say She's out grabbing groceries — should be home by seven.\n\n"
            out += "// [Same Maria note]\n"
            out += "> when is she back\n"
            out += "say Around seven — she's just out for groceries.\n\n"
            out += "RULE: when you answer from a note, use ONLY the words in that note's Content. Do not invent times, places, or details that aren't in the Content line above.\n"
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
                // Defensive label strip — Gemma occasionally parrots a header
                // from the catalog's OUTPUT description after the `say`
                // prefix (e.g. "say Note / Cue / General answer: Sarah is…").
                // Strip a known-label prefix when present so the patient
                // hears only the actual answer.
                let cleaned = stripped
                    .stripLeadingLabel(any: [
                        "Note / Cue / General answer:",
                        "Note answer:",
                        "Cue answer:",
                        "General answer:",
                        "TV action:",
                        "Answer:"
                    ])
                    .trimmingCharacters(in: .whitespaces)
                saySegments.append(cleaned)
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

    /// Strips the first leading label (case-insensitive) from any of the
    /// given candidates. Used defensively after a `say` prefix to remove
    /// shape headers Gemma sometimes parrots from the prompt catalog.
    func stripLeadingLabel(any labels: [String]) -> String {
        let lowered = lowercased()
        for label in labels {
            let l = label.lowercased()
            if lowered.hasPrefix(l) {
                return String(dropFirst(label.count))
            }
        }
        return self
    }
}
