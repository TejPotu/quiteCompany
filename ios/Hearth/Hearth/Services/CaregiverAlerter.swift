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

    // MARK: - Persistence

    private enum Key: String {
        case botToken = "hearth.alerter.botToken"
        case chatId   = "hearth.alerter.chatId"
    }

    private func persist(_ key: Key, _ value: String) {
        UserDefaults.standard.set(value, forKey: key.rawValue)
    }
}
