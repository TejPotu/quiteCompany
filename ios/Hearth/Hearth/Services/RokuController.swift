import Foundation
import SwiftUI
import Observation
import os

// Drives a Roku TV over the LAN via ECP (port 8060). All actions are async +
// no-throwing — on failure we flip status to .unreachable and let the caller
// keep its narration. We never lie about state we can't verify.
@Observable
@MainActor
final class RokuController {

    enum Status: Equatable {
        case unconfigured
        case ready
        case unreachable
        case error(String)
    }

    var status: Status
    var host: String? {
        didSet {
            if let host { UserDefaults.standard.set(host, forKey: Self.hostKey) }
            else { UserDefaults.standard.removeObject(forKey: Self.hostKey) }
        }
    }

    private static let hostKey = "rokuHost"
    private static let log = Logger(subsystem: "Hearth", category: "Roku")

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 3
        cfg.timeoutIntervalForResource = 5
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.hostKey)
        self.host = saved
        self.status = (saved == nil) ? .unconfigured : .ready
    }

    // MARK: Setup

    // Persist the host and probe it. Flips status to .ready on 200, .unreachable
    // otherwise. Returns whether the probe succeeded so the setup sheet can show
    // inline feedback.
    @discardableResult
    func setHost(_ ip: String) async -> Bool {
        let trimmed = ip.trimmingCharacters(in: .whitespaces)
        host = trimmed
        return await probe()
    }

    @discardableResult
    private func probe() async -> Bool {
        guard let host, let url = URL(string: "http://\(host):8060/") else {
            status = .unreachable
            return false
        }
        do {
            let (_, resp) = try await session.data(from: url)
            if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                status = .ready
                return true
            }
            status = .unreachable
            return false
        } catch {
            Self.log.warning("Roku probe failed: \(error.localizedDescription)")
            status = .unreachable
            return false
        }
    }

    // MARK: Actions

    // Launching a show on the Roku, best-effort tiered:
    //   1. Platform + contentId → /launch/<appId>?contentId=<id>&mediaType=series.
    //      Streaming app lands on the title page; if there's watch history,
    //      "Resume" is the primary CTA and one click plays.
    //   2. Platform only → /launch/<appId>. App opens to its home screen with
    //      the user's "Continue watching" row.
    //   3. No platform → global Roku search.
    func launchShow(_ show: Show) async {
        if let appId = show.platform?.rokuAppId {
            if let id = show.contentId,
               let encodedId = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                let mt = show.mediaType ?? "series"
                await post("launch/\(appId)?contentId=\(encodedId)&mediaType=\(mt)")
                return
            }
            await post("launch/\(appId)")
            return
        }
        let query = show.rokuKeyword ?? show.title
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return }
        await post("search/browse?keyword=\(encoded)&type=series&launch=true&match-any=true")
    }

    // Snapshot of the Roku's playback state. Surfaced so Gemma + the UI can
    // narrate the real thing instead of mock copy.
    struct MediaState: Equatable {
        enum Status {
            case playing, paused, stopped, buffering, idle
            init(raw: String) {
                switch raw {
                case "play":   self = .playing
                case "pause":  self = .paused
                case "stop":   self = .stopped
                case "buffer": self = .buffering
                default:       self = .idle  // "none", "open", ""
                }
            }
        }
        let status: Status
        let positionSeconds: Int?
        let durationSeconds: Int?
    }

    func mediaPlayerState() async -> MediaState? {
        guard let host, let url = URL(string: "http://\(host):8060/query/media-player")
        else { return nil }
        do {
            let (data, resp) = try await session.data(from: url)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let xml = String(data: data, encoding: .utf8) else { return nil }
            return Self.parseMediaPlayer(xml: xml)
        } catch {
            Self.log.warning("Roku query/media-player failed: \(error.localizedDescription)")
            return nil
        }
    }

    // Response shape: <player state="play">…<position>14000 ms</position>
    // <duration>1320000 ms</duration></player>. Some firmwares omit position/
    // duration when nothing is playing.
    private static func parseMediaPlayer(xml: String) -> MediaState? {
        func firstMatch(_ pattern: String) -> String? {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            let range = NSRange(xml.startIndex..., in: xml)
            guard let m = regex.firstMatch(in: xml, range: range),
                  m.numberOfRanges > 1,
                  let r = Range(m.range(at: 1), in: xml) else { return nil }
            return String(xml[r])
        }
        func msToSeconds(_ s: String?) -> Int? {
            guard let s else { return nil }
            let head = s.split(separator: " ").first.map(String.init) ?? s
            return Int(head).map { $0 / 1000 }
        }
        guard let stateStr = firstMatch(#"<player[^>]*\bstate="([^"]+)""#)
        else { return nil }
        return MediaState(
            status: MediaState.Status(raw: stateStr),
            positionSeconds: msToSeconds(firstMatch(#"<position>([^<]+)</position>"#)),
            durationSeconds: msToSeconds(firstMatch(#"<duration>([^<]+)</duration>"#))
        )
    }

    // Raw XML responses for the diagnostic view. We hand them back unparsed
    // so the UI shows everything Roku exposes — useful for spotting fields
    // we could read but currently don't.
    func rawMediaPlayer() async -> String? { await rawGet("query/media-player") }
    func rawActiveApp() async -> String?   { await rawGet("query/active-app") }
    func rawDeviceInfo() async -> String?  { await rawGet("query/device-info") }

    private func rawGet(_ path: String) async -> String? {
        guard let host, let url = URL(string: "http://\(host):8060/\(path)")
        else { return nil }
        do {
            let (data, resp) = try await session.data(from: url)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode)
            else { return nil }
            return String(data: data, encoding: .utf8)
        } catch {
            Self.log.warning("Roku \(path) failed: \(error.localizedDescription)")
            return nil
        }
    }

    // Diagnostic: returns the installed-app list with channel IDs. Used by
    // setup sheet so the user can verify their Roku actually has the apps
    // we're assigning to shows. Returns nil if the Roku is unreachable.
    func installedApps() async -> [(name: String, id: String)]? {
        guard let host, let url = URL(string: "http://\(host):8060/query/apps")
        else { return nil }
        do {
            let (data, resp) = try await session.data(from: url)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode)
            else { return nil }
            return Self.parseApps(xml: data)
        } catch {
            Self.log.warning("Roku query/apps failed: \(error.localizedDescription)")
            return nil
        }
    }

    // Tiny XML scrape — the response shape is <apps><app id="12">Netflix</app>…</apps>.
    private static func parseApps(xml data: Data) -> [(name: String, id: String)] {
        guard let s = String(data: data, encoding: .utf8) else { return [] }
        var out: [(String, String)] = []
        let pattern = #"<app[^>]*\bid="([^"]+)"[^>]*>([^<]+)</app>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(s.startIndex..., in: s)
        regex.enumerateMatches(in: s, range: range) { m, _, _ in
            guard let m,
                  let idR = Range(m.range(at: 1), in: s),
                  let nameR = Range(m.range(at: 2), in: s) else { return }
            out.append((String(s[nameR]), String(s[idR])))
        }
        return out
    }

    func play() async        { await post("keypress/Play") }
    func fastForward() async { await post("keypress/Fwd") }
    func volumeUp() async    { await post("keypress/VolumeUp") }
    func volumeDown() async  { await post("keypress/VolumeDown") }
    func home() async        { await post("keypress/Home") }

    // Generic keypress so the tool layer can pass any Roku key (Up, Down,
    // Select, VolumeMute, ChannelUp, Info, Search, PowerOff, etc.). The input
    // is URL-encoded so a value like "Lit_a" works for keyboard input.
    func press(_ key: String) async {
        let trimmed = key.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return }
        await post("keypress/\(encoded)")
    }

    // "Next episode" via ECP has no canonical key. We send Select — during
    // Netflix's end-of-episode "Up Next" countdown overlay this triggers the
    // focused "Next Episode" button, which is the common moment a viewer
    // actually needs this. Outside that window Select opens the playback UI.
    // The clean long-term fix is per-episode contentIds and re-launching.
    func nextEpisode() async { await post("keypress/Select") }

    // 10 s back per InstantReplay press; chips chain multiple presses for
    // bigger jumps.
    func instantReplay(times: Int = 1) async {
        for _ in 0..<max(1, times) {
            await post("keypress/InstantReplay")
        }
    }

    // MARK: Internal

    private func post(_ path: String) async {
        guard let host, let url = URL(string: "http://\(host):8060/\(path)") else {
            status = .unreachable
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        do {
            let (_, resp) = try await session.data(for: req)
            if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                if status != .ready { status = .ready }
            } else {
                status = .unreachable
            }
        } catch {
            Self.log.warning("Roku POST \(path) failed: \(error.localizedDescription)")
            status = .unreachable
        }
    }
}
