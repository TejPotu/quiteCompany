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

    /// Catalog text injected into Gemma's prompt. Keep it tight — the model
    /// only needs enough to plan, not exhaustive docs.
    static func catalog(showTitles: [String]) -> String {
        let titles = showTitles.joined(separator: ", ")
        return """
        Tools you can use. One tool per line, with arguments separated by
        spaces. Numbers in brackets are optional repeat counts (default 1).

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

        After tool calls, ALWAYS end with one final line:
        say <one warm sentence to the user about what just happened>

        If no tool fits, output only a single `say <...>` line.

        Examples:

        > pause this
        play
        say Paused.

        > turn it down a lot
        volumeDown 4
        say Quieter now.

        > I missed that last bit
        rewind 3
        say I went back about thirty seconds.

        > put on Young Sheldon
        launchShow Young Sheldon
        say Putting on Young Sheldon.

        > what's happening
        say You're 4 minutes into Young Sheldon's pilot, about 18 minutes left.

        > pause it and turn the volume down two
        play
        volumeDown 2
        say Paused and a little quieter.
        """
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

    /// Parses Gemma's raw response. Ignores preamble, blank lines, and lines
    /// that don't start with a known prefix.
    static func parse(_ raw: String) -> Plan {
        var calls: [ToolCall] = []
        var narration: String? = nil
        for rawLine in raw.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "-*•"))
                .trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            // SAY narration line.
            if let stripped = line.dropPrefix(caseInsensitive: "say ") {
                narration = stripped.trimmingCharacters(in: .whitespaces)
                continue
            }

            // Tool call.
            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard let head = parts.first else { continue }
            let name = String(head).lowercased()
            let args = parts.count > 1
                ? String(parts[1]).trimmingCharacters(in: .whitespaces)
                : ""
            // Filter obvious junk (preamble like "I'll", "Sure," etc.).
            guard knownTools.contains(name) else { continue }
            calls.append(ToolCall(name: name, args: args))
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
