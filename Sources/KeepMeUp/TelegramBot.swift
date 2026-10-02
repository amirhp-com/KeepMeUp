import AppKit
import Foundation

final class TelegramBot: ObservableObject {
    static let shared = TelegramBot()

    enum State: Equatable {
        case stopped
        case connecting
        case running(String)
        case failed(String)
    }

    @Published private(set) var state: State = .stopped
    @Published private(set) var pairingOpenUntil: Date?

    private var task: Task<Void, Never>?
    private var token: String?
    private var offset: Int64 = 0
    private var pendingPair = false
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 70
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    private init() {}

    static let tokenAccount = "telegram-bot-token"

    var hasToken: Bool { !(Keychain.read(Self.tokenAccount) ?? "").isEmpty }

    var isPairingOpen: Bool {
        if Preferences.shared.allowedChatIDs.isEmpty { return true }
        guard let pairingOpenUntil else { return false }
        return pairingOpenUntil > Date()
    }

    func openPairing(minutes: Double = 5) {
        pairingOpenUntil = Date().addingTimeInterval(minutes * 60)
    }

    func startIfEnabled() {
        if Preferences.shared.botEnabled { start() }
    }

    func start() {
        stop()
        guard let saved = Keychain.read(Self.tokenAccount), !saved.isEmpty else {
            state = .failed("Add a bot token first")
            return
        }
        token = saved
        state = .connecting
        task = Task { [weak self] in await self?.run() }
    }

    func stop() {
        task?.cancel()
        task = nil
        state = .stopped
    }

    func notify(_ text: String) {
        guard case .running = state else { return }
        for chat in Preferences.shared.allowedChatIDs {
            Task { try? await self.send(text, to: chat) }
        }
    }

    private func setState(_ newState: State) async {
        await MainActor.run { self.state = newState }
    }

    private func run() async {
        do {
            let me = try await call("getMe", [:])
            let username = (me["username"] as? String).map { "@\($0)" } ?? "bot"
            await setState(.running(username))
            try? await registerCommands()
        } catch {
            await setState(.failed(redact(error.localizedDescription)))
            return
        }

        var failures = 0
        while !Task.isCancelled {
            do {
                let result = try await call("getUpdates", ["offset": offset, "timeout": 50, "allowed_updates": ["message", "callback_query"]])
                failures = 0
                guard let updates = result["result"] as? [[String: Any]] else { continue }
                for update in updates {
                    if let id = (update["update_id"] as? NSNumber)?.int64Value { offset = id + 1 }
                    await handle(update)
                }
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                failures += 1
                let delay = min(60, pow(2, Double(min(failures, 6))))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    private func handle(_ update: [String: Any]) async {
        if let callback = update["callback_query"] as? [String: Any] {
            await handleCallback(callback)
            return
        }
        guard let message = update["message"] as? [String: Any],
              let chat = message["chat"] as? [String: Any],
              let chatID = (chat["id"] as? NSNumber)?.int64Value,
              chat["type"] as? String == "private",
              let from = message["from"] as? [String: Any],
              (from["id"] as? NSNumber)?.int64Value == chatID,
              from["is_bot"] as? Bool != true,
              let text = message["text"] as? String else { return }

        let parts = text.split(separator: " ").map(String.init)
        guard let first = parts.first else { return }
        let command = first.lowercased().split(separator: "@").first.map(String.init) ?? first
        let args = Array(parts.dropFirst())

        let allowed = await MainActor.run { Preferences.shared.allowedChatIDs.contains(chatID) }

        if command == "/pair" || command == "/start" {
            if allowed {
                try? await send("✅ This chat is already paired.\n\n\(Self.helpText)", to: chatID)
            } else {
                await requestPairing(chatID: chatID, chat: chat)
            }
            return
        }

        guard allowed else {
            try? await send("🔒 This chat is not paired. Send /pair and approve it on the Mac.", to: chatID)
            return
        }

        await execute(command: command, args: args, chatID: chatID)
    }

    private func requestPairing(chatID: Int64, chat: [String: Any]) async {
        let open = await MainActor.run { isPairingOpen && !pendingPair }
        guard open else {
            try? await send("🔒 Pairing is closed. Open it from KeepMeUp Settings → Telegram on the Mac.", to: chatID)
            return
        }
        let rawName = [chat["first_name"], chat["last_name"]].compactMap { $0 as? String }.joined(separator: " ")
        let name = String(rawName.filter { !$0.isNewline }.prefix(64))
        let handle = (chat["username"] as? String).map { "@\(String($0.prefix(32)))" } ?? "none"
        try? await send("⏳ Approve this chat on your Mac to finish pairing.", to: chatID)

        let approved = await MainActor.run { () -> Bool in
            pendingPair = true
            defer { pendingPair = false }
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Allow Telegram control?"
            alert.informativeText = "A Telegram user wants to control this Mac through KeepMeUp.\n\nChat ID: \(chatID)\nUsername: \(handle)\nName they set: \(name.isEmpty ? "none" : name)\n\nOnly allow this if you sent /pair yourself just now."
            alert.addButton(withTitle: "Allow")
            alert.addButton(withTitle: "Deny")
            alert.alertStyle = .warning
            let ok = alert.runModal() == .alertFirstButtonReturn
            if ok {
                if !Preferences.shared.allowedChatIDs.contains(chatID) {
                    Preferences.shared.allowedChatIDs.append(chatID)
                }
                pairingOpenUntil = nil
            }
            return ok
        }

        if approved {
            try? await send("✅ Paired with \(SystemInfo.hostName()).\n\n\(Self.helpText)", to: chatID)
        } else {
            try? await send("❌ Pairing was denied.", to: chatID)
        }
    }

    private func execute(command: String, args: [String], chatID: Int64) async {
        let reply: (String) async -> Void = { text in try? await self.send(text, to: chatID) }

        switch command {
        case "/help":
            await reply(Self.helpText)
        case "/status":
            await reply(await MainActor.run { self.statusText() })
        case "/on":
            if let arg = args.first {
                guard let interval = DurationText.parse(arg) else { return await reply("⚠️ Could not read \"\(arg)\". Try 30m, 1h or 1h30m.") }
                await MainActor.run {
                    AwakeManager.shared.enable()
                    Scheduler.shared.schedule(.stopAwake, after: interval)
                }
                await reply("☕️ Keeping awake for \(DurationText.describe(interval)).")
            } else {
                await MainActor.run { AwakeManager.shared.enable() }
                await reply("☕️ Keeping this Mac awake until you turn it off.")
            }
        case "/off":
            if let arg = args.first {
                guard let interval = DurationText.parse(arg) else { return await reply("⚠️ Could not read \"\(arg)\". Try 30m, 1h or 1h30m.") }
                await MainActor.run {
                    AwakeManager.shared.enable()
                    Scheduler.shared.schedule(.stopAwake, after: interval)
                }
                await reply("⏰ Keep-awake turns off in \(DurationText.describe(interval)).")
            } else {
                await MainActor.run {
                    if Scheduler.shared.action == .stopAwake { Scheduler.shared.cancel() }
                    AwakeManager.shared.disable()
                }
                await reply("😴 Keep-awake is off. Normal sleep settings apply.")
            }
        case "/timer":
            guard args.count >= 2, let interval = DurationText.parse(args[0]), let action = PowerAction.from(keyword: args[1]) else {
                return await reply("Usage: /timer <duration> <action>\nActions: off, displayoff, screensaver, lock, sleep, restart, shutdown\nExample: /timer 1h30m shutdown")
            }
            await MainActor.run {
                AwakeManager.shared.enable()
                Scheduler.shared.schedule(action, after: interval)
            }
            await reply("⏰ \(action.title) in \(DurationText.describe(interval)).")
        case "/cancel":
            let had = await MainActor.run { () -> Bool in
                let had = Scheduler.shared.action != nil
                Scheduler.shared.cancel()
                return had
            }
            await reply(had ? "🛑 Timer cancelled." : "No timer is running.")
        case "/displayoff":
            await reply("🌑 Turning the display off.")
            await perform(.displayOff)
        case "/screensaver":
            await reply("✨ Starting the screensaver.")
            await perform(.screensaver)
        case "/lock":
            await reply("🔒 Locking the screen.")
            await perform(.lock)
        case "/sleep":
            await reply("🌙 Putting the Mac to sleep.")
            await perform(.sleep)
        case "/restart", "/shutdown":
            let action: PowerAction = command == "/restart" ? .restart : .shutdown
            let keyboard: [String: Any] = ["inline_keyboard": [[
                ["text": "✅ Yes, \(action.title.lowercased())", "callback_data": "confirm:\(action.rawValue)"],
                ["text": "Cancel", "callback_data": "cancel"]
            ]]]
            _ = try? await call("sendMessage", ["chat_id": chatID, "text": "⚠️ \(action.title) \(SystemInfo.hostName()) now?", "reply_markup": keyboard])
        case "/screenshot":
            let urls = await MainActor.run { SystemInfo.screenshots() }
            if urls.isEmpty {
                await reply("⚠️ Could not take a screenshot. Allow KeepMeUp in System Settings → Privacy & Security → Screen Recording.")
            }
            for url in urls {
                try? await sendPhoto(url, to: chatID)
                try? FileManager.default.removeItem(at: url)
            }
        case "/info":
            await reply(SystemInfo.summary())
        default:
            await reply("🤔 Unknown command. Send /help to see what I can do.")
        }
    }

    private func handleCallback(_ callback: [String: Any]) async {
        guard let id = callback["id"] as? String,
              let message = callback["message"] as? [String: Any],
              let chat = message["chat"] as? [String: Any],
              let chatID = (chat["id"] as? NSNumber)?.int64Value,
              chat["type"] as? String == "private",
              let from = callback["from"] as? [String: Any],
              (from["id"] as? NSNumber)?.int64Value == chatID,
              let messageID = message["message_id"] as? NSNumber,
              let data = callback["data"] as? String else { return }

        let allowed = await MainActor.run { Preferences.shared.allowedChatIDs.contains(chatID) }
        guard allowed else {
            _ = try? await call("answerCallbackQuery", ["callback_query_id": id, "text": "Not authorized"])
            return
        }

        if data.hasPrefix("confirm:"), let action = PowerAction(rawValue: String(data.dropFirst(8))) {
            _ = try? await call("answerCallbackQuery", ["callback_query_id": id])
            _ = try? await call("editMessageText", ["chat_id": chatID, "message_id": messageID, "text": "⏻ \(action.title) in progress…"])
            await perform(action)
        } else {
            _ = try? await call("answerCallbackQuery", ["callback_query_id": id, "text": "Cancelled"])
            _ = try? await call("editMessageText", ["chat_id": chatID, "message_id": messageID, "text": "Cancelled."])
        }
    }

    private func perform(_ action: PowerAction) async {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        await MainActor.run { PowerActions.perform(action) }
    }

    private func statusText() -> String {
        var lines = [AwakeManager.shared.isActive ? "☕️ Keep-awake is ON" : "😴 Keep-awake is OFF"]
        if let action = Scheduler.shared.action, let remaining = Scheduler.shared.remaining {
            lines.append("⏰ \(action.title) in \(DurationText.describe(remaining))")
        }
        lines.append("🔋 \(SystemInfo.battery())")
        lines.append("💻 \(SystemInfo.hostName())")
        return lines.joined(separator: "\n")
    }

    static let helpText = """
    KeepMeUp commands
    /status – current state
    /on [time] – keep awake, optionally for a while (e.g. /on 2h)
    /off [time] – stop now, or after a delay (e.g. /off 30m)
    /timer <time> <action> – e.g. /timer 1h shutdown
    /cancel – cancel the running timer
    /displayoff – turn the display off
    /screensaver – start the screensaver
    /lock – lock the screen
    /sleep – sleep now
    /restart – restart (asks first)
    /shutdown – shut down (asks first)
    /screenshot – capture the screen
    /info – battery and system info
    """

    private func registerCommands() async throws {
        let commands: [(String, String)] = [
            ("status", "Current state"),
            ("on", "Keep awake, optionally for a while"),
            ("off", "Stop keeping awake, now or later"),
            ("timer", "Schedule an action"),
            ("cancel", "Cancel the running timer"),
            ("displayoff", "Turn the display off"),
            ("screensaver", "Start the screensaver"),
            ("lock", "Lock the screen"),
            ("sleep", "Sleep now"),
            ("restart", "Restart the Mac"),
            ("shutdown", "Shut down the Mac"),
            ("screenshot", "Capture the screen"),
            ("info", "Battery and system info"),
            ("help", "Show all commands")
        ]
        _ = try await call("setMyCommands", ["commands": commands.map { ["command": $0.0, "description": $0.1] }])
    }

    private func send(_ text: String, to chatID: Int64) async throws {
        _ = try await call("sendMessage", ["chat_id": chatID, "text": text])
    }

    private func endpoint(_ method: String) throws -> URL {
        guard let token, let url = URL(string: "https://api.telegram.org/bot\(token)/\(method)") else {
            throw BotError.message("Missing bot token")
        }
        return url
    }

    @discardableResult
    private func call(_ method: String, _ params: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: try endpoint(method))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: params)
        let (data, _) = try await session.data(for: request)
        return try decode(data)
    }

    private func sendPhoto(_ file: URL, to chatID: Int64) async throws {
        let boundary = "KeepMeUp-\(UUID().uuidString)"
        var request = URLRequest(url: try endpoint("sendPhoto"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"chat_id\"\r\n\r\n\(chatID)\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"photo\"; filename=\"\(file.lastPathComponent)\"\r\nContent-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(try Data(contentsOf: file))
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        let (data, _) = try await session.data(for: request)
        _ = try decode(data)
    }

    private func redact(_ text: String) -> String {
        guard let token, !token.isEmpty else { return text }
        return text.replacingOccurrences(of: token, with: "•••")
    }

    private func decode(_ data: Data) throws -> [String: Any] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BotError.message("Unexpected response")
        }
        guard json["ok"] as? Bool == true else {
            throw BotError.message(json["description"] as? String ?? "Telegram error")
        }
        if let result = json["result"] as? [String: Any] { return result }
        return json
    }

    enum BotError: LocalizedError {
        case message(String)
        var errorDescription: String? {
            if case .message(let text) = self { return text }
            return nil
        }
    }
}
