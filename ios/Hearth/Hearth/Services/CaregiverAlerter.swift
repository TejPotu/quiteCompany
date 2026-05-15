import Foundation
import Observation

// Sends caregiver-facing alerts over Telegram. Picked Telegram over WhatsApp
// or SMTP because:
//   - No infra needed (Telegram hosts the bot, ~5 line HTTP POST)
//   - Free, no SMS/WhatsApp gateway costs
//   - Real push notification rings on the caregiver's phone
//   - Cross-platform on the receiving side
//
// Setup is a one-time three-step the caregiver does once:
//   1) Talk to @BotFather on Telegram → /newbot → copy the bot TOKEN
//   2) Open the new bot, hit /start → opens a chat with the bot
//   3) Visit https://api.telegram.org/bot<TOKEN>/getUpdates → copy chat.id
// Both values land in the Wellness sheet; afterwards it just works.
@Observable @MainActor
final class CaregiverAlerter {

    enum LastSendResult: Equatable {
        case never
        case success(Date)
        case failure(String, Date)
    }

    var botToken: String { didSet { persist(.botToken, botToken) } }
    var chatId: String   { didSet { persist(.chatId, chatId) } }
    private(set) var lastResult: LastSendResult = .never

    // Inbox — caregiver-authored messages waiting for the patient to ack.
    // Populated by pollInbox(). Filtered to only the configured chat_id so
    // strangers who message the bot can't push content onto the iPad.
    private(set) var inbox: [InboundMessage] = []
    private var lastUpdateId: Int = 0

    struct InboundMessage: Identifiable, Equatable {
        let id: Int          // Telegram message_id
        let updateId: Int    // for offset bookkeeping
        let text: String
        let sentAt: Date
        let senderName: String
    }

    var isConfigured: Bool {
        !botToken.trimmingCharacters(in: .whitespaces).isEmpty
            && !chatId.trimmingCharacters(in: .whitespaces).isEmpty
    }

    init() {
        self.botToken = UserDefaults.standard.string(forKey: Key.botToken.rawValue) ?? ""
        self.chatId   = UserDefaults.standard.string(forKey: Key.chatId.rawValue)   ?? ""
    }

    /// Send a text message. Returns true on HTTP 200 + Telegram ok:true.
    @discardableResult
    func send(text: String) async -> Bool {
        guard isConfigured else {
            lastResult = .failure("Not configured", Date())
            return false
        }
        let token = botToken.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: "https://api.telegram.org/bot\(token)/sendMessage") else {
            lastResult = .failure("Bad bot token", Date())
            return false
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 10
        let payload: [String: Any] = [
            "chat_id": chatId.trimmingCharacters(in: .whitespaces),
            "text": text,
            "disable_web_page_preview": true
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let http = response as? HTTPURLResponse
            let ok = (http?.statusCode == 200)
                && ((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["ok"] as? Bool == true)
            if ok {
                lastResult = .success(Date())
                return true
            } else {
                let body = String(data: data, encoding: .utf8) ?? "no body"
                lastResult = .failure("HTTP \(http?.statusCode ?? -1): \(body.prefix(140))", Date())
                return false
            }
        } catch {
            lastResult = .failure(error.localizedDescription, Date())
            return false
        }
    }

    // MARK: - Inbox (incoming from the caregiver)

    // Drop messages that arrived before Hearth opened so we don't replay
    // every old chat on launch. Called from the TVScreen .task once on
    // first poll.
    func anchorInboxToNow() async {
        guard isConfigured else { return }
        let token = botToken.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: "https://api.telegram.org/bot\(token)/getUpdates?offset=-1") else {
            return
        }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["result"] as? [[String: Any]],
              let lastUpdate = results.last,
              let updateId = lastUpdate["update_id"] as? Int
        else { return }
        // Bump our cursor past the latest known update so future polls
        // only return things that arrived AFTER Hearth opened.
        lastUpdateId = updateId
    }

    /// Long-poll for new messages addressed to the configured chat. Safe to
    /// call repeatedly; only new updates make it into `inbox`.
    func pollInbox() async {
        guard isConfigured else { return }
        let token = botToken.trimmingCharacters(in: .whitespaces)
        let configuredChat = chatId.trimmingCharacters(in: .whitespaces)
        let offset = lastUpdateId + 1
        // timeout=25 makes Telegram hold the request open until either a
        // message arrives or 25s passes — far gentler than 30s busy-polling.
        guard let url = URL(string: "https://api.telegram.org/bot\(token)/getUpdates?offset=\(offset)&timeout=25") else {
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 30

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["result"] as? [[String: Any]]
        else { return }

        for update in results {
            guard let updateId = update["update_id"] as? Int else { continue }
            lastUpdateId = max(lastUpdateId, updateId)

            guard let message = update["message"] as? [String: Any],
                  let messageId = message["message_id"] as? Int,
                  let chat = message["chat"] as? [String: Any],
                  let chatIdValue = chat["id"] as? Int,
                  String(chatIdValue) == configuredChat,
                  let text = message["text"] as? String,
                  let date = message["date"] as? TimeInterval
            else { continue }

            // Don't surface our own outbound acks back to the screen.
            if text.hasPrefix("✓") || text.hasPrefix("✨") || text.hasPrefix("🚨") || text.hasPrefix("✅") {
                continue
            }

            let from = (message["from"] as? [String: Any])
            let senderName = (from?["first_name"] as? String)
                ?? (from?["username"] as? String)
                ?? "Family"

            let already = inbox.contains { $0.id == messageId }
            if !already {
                inbox.append(InboundMessage(
                    id: messageId,
                    updateId: updateId,
                    text: text,
                    sentAt: Date(timeIntervalSince1970: date),
                    senderName: senderName
                ))
            }
        }
    }

    /// Mark a message acknowledged. Removes it from the inbox and sends a
    /// silent "✓ Read at 5:43 PM" back so the caregiver knows it landed.
    func acknowledge(_ message: InboundMessage) async {
        inbox.removeAll { $0.id == message.id }
        let stamp = Self.fmtTime(Date())
        await send(text: "✓ Read at \(stamp)")
    }

    private static func fmtTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: d)
    }

    // MARK: - Persistence

    private enum Key: String {
        case botToken = "hearth.alerter.botToken"
        case chatId   = "hearth.alerter.chatId"
    }

    private func persist(_ key: Key, _ value: String) {
        UserDefaults.standard.set(value, forKey: key.rawValue)
    }
}
