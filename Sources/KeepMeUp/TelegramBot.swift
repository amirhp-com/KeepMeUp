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
    @Published private(set) var botUsername: String?
    @Published private(set) var pairingOpenUntil: Date?
    @Published private(set) var awaitingApproval = false

    private var task: Task<Void, Never>?
    private var token: String?
    private var offset: Int64 = 0
    private var foundFiles: [Int64: [URL]] = [:]
    private var runningLists: [Int64: [(name: String, pid: pid_t)]] = [:]
    private var installedLists: [Int64: [RemoteTools.InstalledApp]] = [:]
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 70
        config.timeoutIntervalForResource = 600
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    private init() {}

    static let tokenAccount = "telegram-bot-token"
    private static let uploadLimit: Int64 = 50 * 1024 * 1024

    var isPairingOpen: Bool {
        if Preferences.shared.allowedChats.isEmpty { return true }
        guard let pairingOpenUntil else { return false }
        return pairingOpenUntil > Date()
    }

    func openPairing(minutes: Double = 5) {
        pairingOpenUntil = Date().addingTimeInterval(minutes * 60)
    }

    func closePairing() {
        pairingOpenUntil = nil
    }

    func startIfEnabled() {
        if Preferences.shared.botEnabled { start() }
    }

    func start() {
        stop()
        let saved = TokenStore.read()
        guard !saved.isEmpty else {
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

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    func notify(_ text: String) {
        guard isRunning else { return }
        for chat in Preferences.shared.allowedChatIDs {
            Task { try? await self.send(text, to: chat) }
        }
    }

    func refreshCommands() {
        guard isRunning else { return }
        Task { try? await self.registerCommands() }
    }

    func lookUp(_ id: Int64) {
        guard isRunning else { return }
        Task {
            guard let result = try? await self.call("getChat", ["chat_id": id]),
                  let info = ChatInfo(telegram: result) else { return }
            await MainActor.run { Preferences.shared.upsert(info) }
        }
    }

    private func setState(_ newState: State) async {
        await MainActor.run { self.state = newState }
    }

    private func run() async {
        do {
            let me = try await call("getMe", [:])
            let username = me["username"] as? String
            await MainActor.run { self.botUsername = username }
            await setState(.running(username.map { "@\($0)" } ?? "bot"))
        } catch {
            await setState(.failed(redact(error.localizedDescription)))
            return
        }
        try? await registerProfile()
        try? await registerCommands()
        await refreshChats()

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

    private func refreshChats() async {
        let ids = await MainActor.run { Preferences.shared.allowedChatIDs }
        for id in ids {
            guard let result = try? await call("getChat", ["chat_id": id]),
                  let info = ChatInfo(telegram: result) else { continue }
            await MainActor.run { Preferences.shared.upsert(info) }
        }
    }

    private func isAuthorized(chat: ChatInfo, senderID: Int64) -> Bool {
        let prefs = Preferences.shared
        if chat.isPrivate { return chat.id == senderID && prefs.isAllowed(chat.id) }
        if chat.isGroup { return prefs.isAllowed(chat.id) && prefs.isPairedUser(senderID) }
        return false
    }

    private func handle(_ update: [String: Any]) async {
        if let callback = update["callback_query"] as? [String: Any] {
            await handleCallback(callback)
            return
        }
        guard let message = update["message"] as? [String: Any],
              let rawChat = message["chat"] as? [String: Any],
              let chat = ChatInfo(telegram: rawChat),
              chat.isPrivate || chat.isGroup,
              let from = message["from"] as? [String: Any],
              let senderID = (from["id"] as? NSNumber)?.int64Value,
              from["is_bot"] as? Bool != true else { return }
        if chat.isPrivate && senderID != chat.id { return }

        if let document = message["document"] as? [String: Any] {
            let allowed = await MainActor.run { isAuthorized(chat: chat, senderID: senderID) }
            let enabled = await MainActor.run { Preferences.shared.isEnabled(.upload) }
            if allowed {
                if enabled {
                    await receiveUpload(document, chatID: chat.id)
                } else {
                    try? await send("🚫 /upload is turned off. Turn it on in KeepMeUp → Settings → Commands.", to: chat.id)
                }
            }
            return
        }

        guard let text = message["text"] as? String, text.hasPrefix("/") else { return }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let head = trimmed.split(separator: " ", maxSplits: 1).first.map(String.init) ?? trimmed
        let headParts = head.split(separator: "@", maxSplits: 1).map(String.init)
        if headParts.count == 2, let me = botUsername, headParts[1].lowercased() != me.lowercased() { return }
        var command = headParts[0].lowercased()
        var argument = String(trimmed.dropFirst(head.count)).trimmingCharacters(in: .whitespaces)
        let aliases = ["open_app": "open", "launch": "open", "close_app": "quit", "close": "quit", "quit_app": "quit"]
        var base = String(command.dropFirst())
        if let underscore = base.lastIndex(of: "_"), let number = Int(base[base.index(after: underscore)...]) {
            base = String(base[..<underscore])
            argument = argument.isEmpty ? String(number) : "\(number) \(argument)"
        }
        base = aliases[base] ?? base
        command = "/" + base

        let allowed = await MainActor.run { isAuthorized(chat: chat, senderID: senderID) }

        if command == "/pair" || command == "/start" {
            if allowed {
                try? await send("✅ This chat is already paired with \(SystemInfo.hostName()).\n\n\(BotCommand.helpText())", to: chat.id)
            } else if chat.isGroup {
                let paired = await MainActor.run { Preferences.shared.isPairedUser(senderID) }
                if paired {
                    await requestPairing(chat)
                } else {
                    try? await send("🔒 Pair with me in a private chat first, then send /pair here.", to: chat.id)
                }
            } else {
                await requestPairing(chat)
            }
            return
        }

        guard allowed else {
            if chat.isPrivate {
                try? await send("🔒 This chat isn't paired yet. Send /start and approve it on your Mac.", to: chat.id)
            }
            return
        }

        Task { await self.execute(command: command, argument: argument, chatID: chat.id) }
    }

    private func requestPairing(_ chat: ChatInfo) async {
        let open = await MainActor.run { isPairingOpen && !awaitingApproval }
        guard open else {
            try? await send("🔒 Pairing is closed. On your Mac, open KeepMeUp → Settings → Telegram and click “Pair another chat”, then send /start again.", to: chat.id)
            return
        }
        try? await send("👋 Hi! One last step: look at your Mac and click “Allow” in the KeepMeUp window.", to: chat.id)

        let approved = await MainActor.run { () -> Bool in
            awaitingApproval = true
            defer { awaitingApproval = false }
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Allow Telegram control?"
            let username = chat.username.map { "@\($0)" } ?? "none"
            let name = chat.title.isEmpty ? "none" : chat.title
            alert.informativeText = "\(chat.kind) wants to control this Mac through KeepMeUp.\n\nChat ID: \(chat.id)\nUsername: \(username)\nName: \(name)\n\nOnly allow this if you sent /start yourself just now."
            alert.addButton(withTitle: "Allow")
            alert.addButton(withTitle: "Deny")
            alert.alertStyle = .warning
            let ok = alert.runModal() == .alertFirstButtonReturn
            if ok {
                Preferences.shared.upsert(chat)
                pairingOpenUntil = nil
            }
            return ok
        }

        if approved {
            try? await registerCommands()
            let intro = """
            ✅ Paired with \(SystemInfo.hostName())!

            Tap the menu button next to the message box to see every command, or send /help any time.
            Try /status first. Some commands (like /run and /get) are off until you turn them on in KeepMeUp → Settings → Commands.

            \(BotCommand.helpText())
            """
            try? await send(intro, to: chat.id)
        } else {
            try? await send("❌ Pairing was denied on the Mac.", to: chat.id)
        }
    }

    private func execute(command: String, argument: String, chatID: Int64) async {
        let reply: (String) async -> Void = { text in try? await self.send(text, to: chatID) }
        let args = argument.split(separator: " ").map(String.init)

        guard let cmd = BotCommand(rawValue: String(command.dropFirst())) else {
            return await reply("🤔 Unknown command. Send /help to see what I can do.")
        }
        let enabled = await MainActor.run { !cmd.isToggleable || Preferences.shared.isEnabled(cmd) }
        guard enabled else {
            return await reply("🚫 /\(cmd.rawValue) is turned off. Turn it on in KeepMeUp → Settings → Commands.")
        }

        switch cmd {
        case .help:
            await reply(await MainActor.run { BotCommand.helpText() })
        case .status:
            await reply(await MainActor.run { self.statusText() })
        case .on, .off:
            if let arg = args.first {
                guard let interval = DurationText.parse(arg) else { return await reply("⚠️ Could not read “\(arg)”. Try 30m, 1h or 1h30m.") }
                await MainActor.run {
                    AwakeManager.shared.enable()
                    Scheduler.shared.schedule(.stopAwake, after: interval)
                }
                await reply(cmd == .on ? "☕️ Keeping awake for \(DurationText.describe(interval))." : "⏰ Keep-awake turns off in \(DurationText.describe(interval)).")
            } else if cmd == .on {
                await MainActor.run { AwakeManager.shared.enable() }
                await reply("☕️ Keeping this Mac awake until you turn it off.")
            } else {
                await MainActor.run {
                    if Scheduler.shared.action == .stopAwake { Scheduler.shared.cancel() }
                    AwakeManager.shared.disable()
                }
                await reply("😴 Keep-awake is off. Normal sleep settings apply.")
            }
        case .timer:
            guard args.count >= 2, let interval = DurationText.parse(args[0]), let action = PowerAction.from(keyword: args[1]) else {
                return await reply("Usage: /timer <time> <action>\nActions: off, displayoff, screensaver, lock, sleep, restart, shutdown\nExample: /timer 1h30m shutdown")
            }
            await MainActor.run {
                AwakeManager.shared.enable()
                Scheduler.shared.schedule(action, after: interval)
            }
            await reply("⏰ \(action.title) in \(DurationText.describe(interval)).")
        case .cancel:
            let had = await MainActor.run { () -> Bool in
                let had = Scheduler.shared.action != nil
                Scheduler.shared.cancel()
                return had
            }
            await reply(had ? "🛑 Timer cancelled." : "No timer is running.")
        case .caffeinate:
            guard !argument.isEmpty else { return await reply("Usage: /caffeinate <app>\nKeeps the Mac awake only while that app is running.\nExample: /caffeinate Final Cut Pro") }
            let linked = await MainActor.run { AwakeManager.shared.caffeinate(whileRunning: argument) }
            if let linked {
                await reply("☕️ Keeping \(SystemInfo.hostName()) awake while \(linked) is running. It stops on its own when \(linked) quits.")
            } else {
                await reply("⚠️ “\(argument)” isn't running. Open it first, or send /apps to see what's running.")
            }
        case .schedules:
            let items = await MainActor.run { ScheduleStore.shared.actions }
            guard !items.isEmpty else { return await reply("🗓 No scheduled actions.\nAdd one with /schedule, e.g. /schedule 01:00 sleep weekdays") }
            let lines = items.enumerated().map { i, a in "\(i + 1). \(a.describe)\(a.enabled ? "" : " (off)")  /unschedule_\(i + 1)" }
            await reply("🗓 Scheduled actions\n\n" + lines.joined(separator: "\n"))
        case .schedule:
            await addSchedule(args, chatID: chatID)
        case .unschedule:
            let items = await MainActor.run { ScheduleStore.shared.actions }
            guard let n = args.first.flatMap(Int.init), n >= 1, n <= items.count else {
                return await reply("Usage: /unschedule <number from /schedules>")
            }
            let removed = items[n - 1]
            await MainActor.run { ScheduleStore.shared.remove(removed.id) }
            await reply("🗑 Removed: \(removed.describe)")
        case .upload:
            await reply("📥 Send me a file (as a document) and I'll save it to your Downloads folder.")
        case .displayoff:
            await reply("🌑 Turning the display off.")
            await perform(.displayOff)
        case .screensaver:
            await reply("✨ Starting the screensaver.")
            await perform(.screensaver)
        case .lock:
            await reply("🔒 Locking the screen.")
            await perform(.lock)
        case .sleep:
            await reply("🌙 Putting the Mac to sleep.")
            await perform(.sleep)
        case .restart, .shutdown:
            let action: PowerAction = cmd == .restart ? .restart : .shutdown
            let keyboard: [String: Any] = ["inline_keyboard": [[
                ["text": "✅ Yes, \(action.title.lowercased())", "callback_data": "confirm:\(action.rawValue)"],
                ["text": "Cancel", "callback_data": "cancel"]
            ]]]
            _ = try? await call("sendMessage", ["chat_id": chatID, "text": "⚠️ \(action.title) \(SystemInfo.hostName()) now?", "reply_markup": keyboard])
        case .desktop:
            await MainActor.run { RemoteTools.showDesktop() }
            await reply("🖼 All apps are hidden. Send /show to bring them back.")
        case .show:
            await MainActor.run { RemoteTools.showApps() }
            await reply("🪟 Hidden apps are back.")
        case .screenshot:
            await sendScreenshots(to: chatID)
        case .info:
            await reply(SystemInfo.summary())
        case .apps:
            await sendRunningApps(to: chatID)
        case .open:
            await openApp(argument, chatID: chatID)
        case .quit:
            await quitApp(argument, chatID: chatID)
        case .brightness:
            if let value = args.first.flatMap(Int.init) {
                let ok = await MainActor.run { SystemControls.setBrightness(value) }
                await reply(ok ? "🔆 Brightness set to \(max(0, min(100, value)))%." : "⚠️ This display's brightness can't be changed from KeepMeUp.")
            } else if let level = await MainActor.run(body: { SystemControls.brightness() }) {
                await reply("🔆 Brightness is \(level)%. Send /brightness 0-100 to change it.")
            } else {
                await reply("⚠️ Couldn't read the brightness of this display.")
            }
        case .volume:
            if let value = args.first.flatMap(Int.init) {
                await Task.detached { SystemControls.setVolume(value) }.value
                await reply("🔊 Volume set to \(max(0, min(100, value)))%.")
            } else {
                let (level, muted) = await Task.detached { (SystemControls.outputVolume(), SystemControls.isMuted()) }.value
                await reply("🔊 Volume is \(level)%\(muted ? " (muted)" : ""). Send /volume 0-100 to change it.")
            }
        case .mute:
            let muted = await Task.detached { () -> Bool in
                let next = !SystemControls.isMuted()
                SystemControls.setMuted(next)
                return next
            }.value
            await reply(muted ? "🔇 Muted." : "🔊 Unmuted.")
        case .play, .next, .previous:
            let key: SystemControls.MediaKey = cmd == .play ? .playPause : (cmd == .next ? .next : .previous)
            await MainActor.run { SystemControls.pressMediaKey(key) }
            await reply(cmd == .play ? "⏯ Play/pause." : (cmd == .next ? "⏭ Next track." : "⏮ Previous track."))
        case .say:
            guard !argument.isEmpty else { return await reply("Usage: /say <text>\nExample: /say Dinner is ready") }
            SystemControls.speak(String(argument.prefix(500)))
            await reply("🗣 Speaking on the Mac.")
        case .notify:
            guard !argument.isEmpty else { return await reply("Usage: /notify <text>\nExample: /notify Call me back") }
            let text = String(argument.prefix(300))
            await Task.detached { SystemControls.notify(text) }.value
            await reply("🔔 Notification shown on the Mac.")
        case .clip:
            if argument.isEmpty {
                let text = await MainActor.run { SystemControls.readClipboard() }
                guard let text, !text.isEmpty else { return await reply("📋 The clipboard has no text.") }
                let body = text.count > 3500 ? String(text.prefix(3500)) + "\n…" : text
                _ = try? await call("sendMessage", ["chat_id": chatID, "text": "📋 Clipboard\n<pre>\(escape(body))</pre>", "parse_mode": "HTML"])
            } else {
                await MainActor.run { SystemControls.writeClipboard(argument) }
                await reply("📋 Clipboard updated.")
            }
        case .wifi:
            let line = await Task.detached { SystemControls.wifi() }.value
            await reply(line)
        case .ip:
            let local = await Task.detached { SystemControls.localIPs() }.value
            let publicIP = await SystemControls.publicIP()
            var lines = ["🌐 Public: \(publicIP ?? "unavailable")"]
            lines += local.map { "🏠 \($0)" }
            await reply(lines.joined(separator: "\n"))
        case .terminal:
            await MainActor.run { RemoteTools.openTerminal() }
            await reply("🖥 Terminal is open.")
        case .term:
            guard !argument.isEmpty else { return await reply("Usage: /term <command>\nExample: /term top -l 1 | head -20") }
            let error = await MainActor.run { RemoteTools.runInTerminal(argument) }
            if let error {
                return await reply("⚠️ \(error)\nAllow KeepMeUp to control Terminal in System Settings → Privacy & Security → Automation.")
            }
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await sendScreenshots(to: chatID)
        case .run:
            guard !argument.isEmpty else { return await reply("Usage: /run <command>\nExample: /run df -h") }
            _ = try? await call("sendChatAction", ["chat_id": chatID, "action": "typing"])
            let result = await Task.detached { RemoteTools.shell(argument) }.value
            await sendOutput(result, command: argument, to: chatID)
        case .find:
            guard !argument.isEmpty else { return await reply("Usage: /find <name>\nExample: /find invoice\nSearch one folder with /desk, /docs or /dl.") }
            await search(argument, in: .home, chatID: chatID)
        case .desk, .docs, .dl:
            let place: RemoteTools.Place = cmd == .desk ? .desktop : (cmd == .docs ? .documents : .downloads)
            if argument.isEmpty {
                let items = await Task.detached { RemoteTools.latest(in: place) }.value
                await sendFileList(items.map { ($0.0, Optional($0.1)) }, header: "🗂 Newest in \(place.title)", empty: "\(place.title) is empty, or KeepMeUp isn't allowed to read it yet.", chatID: chatID)
            } else {
                await search(argument, in: place, chatID: chatID)
            }
        case .recent:
            let days = max(1, min(Int(args.first ?? "") ?? 7, 90))
            let items = await Task.detached { RemoteTools.recentFiles(days: days) }.value
            await sendFileList(items.map { ($0.0, Optional($0.1)) }, header: "🕘 Opened in the last \(days) day\(days == 1 ? "" : "s")", empty: "No recently opened files found in the last \(days) days.", chatID: chatID)
        case .get:
            guard let url = await resolveFile(argument, chatID: chatID) else {
                return await reply("Usage: /get <path or number from a file list>\nExample: /get ~/Desktop/report.pdf")
            }
            await sendFile(url, to: chatID)
        case .openfile:
            guard let url = await resolveFile(argument, chatID: chatID) else {
                return await reply("Usage: /openfile <path or number from /find>")
            }
            let ok = await MainActor.run { NSWorkspace.shared.open(url) }
            await reply(ok ? "📂 Opened \(url.lastPathComponent)." : "⚠️ Couldn't open \(url.lastPathComponent).")
        }
    }

    private func sendRunningApps(to chatID: Int64) async {
        let apps = await MainActor.run { RemoteTools.runningApps().map { (name: $0.localizedName ?? "?", pid: $0.processIdentifier, hidden: $0.isHidden, active: $0.isActive) } }
        await MainActor.run { self.runningLists[chatID] = apps.map { (name: $0.name, pid: $0.pid) } }
        let lines = apps.enumerated().map { index, app in
            "\(index + 1). \(app.name)\(app.active ? " ●" : "")\(app.hidden ? " (hidden)" : "")  /quit_\(index + 1)"
        }
        await sendLong(header: "🧩 Running apps — tap /quit_N to quit one", lines: lines, footer: "Force quit: /quit 3 --force · Open another app: /open", to: chatID)
    }

    private func sendInstalledApps(_ apps: [(Int, RemoteTools.InstalledApp)], header: String, to chatID: Int64) async {
        let lines = apps.map { "\($0.0). \($0.1.name)  /open_\($0.0)" }
        await sendLong(header: header, lines: lines, footer: "Tap /open_N, or send /open <name>.", to: chatID)
    }

    private func openApp(_ argument: String, chatID: Int64) async {
        let cached = argument.isEmpty ? nil : await MainActor.run { self.installedLists[chatID] }
        let apps = cached ?? RemoteTools.installedApps()
        await MainActor.run { self.installedLists[chatID] = apps }

        if argument.isEmpty {
            return await sendInstalledApps(Array(zip(1..., apps)), header: "📦 Installed apps — tap /open_N to launch one", to: chatID)
        }
        if let number = Int(argument) {
            guard number >= 1, number <= apps.count else {
                try? await send("⚠️ There's no app #\(number). Send /open to see the list.", to: chatID)
                return
            }
            let app = apps[number - 1]
            await MainActor.run { RemoteTools.open(app) }
            try? await send("🚀 Opening \(app.name).", to: chatID)
            return
        }
        let query = argument.lowercased()
        let matches = zip(1..., apps).filter { $0.1.name.lowercased().contains(query) }
        if let exact = matches.first(where: { $0.1.name.lowercased() == query }) ?? (matches.count == 1 ? matches.first : nil) {
            await MainActor.run { RemoteTools.open(exact.1) }
            try? await send("🚀 Opening \(exact.1.name).", to: chatID)
        } else if matches.isEmpty {
            let ok = await MainActor.run { RemoteTools.launchApp(argument) }
            try? await send(ok ? "🚀 Opening \(argument)." : "⚠️ No app matches “\(argument)”. Send /open to see the list.", to: chatID)
        } else {
            await sendInstalledApps(Array(matches), header: "🔍 Apps matching “\(argument)”", to: chatID)
        }
    }

    private func quitApp(_ argument: String, chatID: Int64) async {
        var name = argument
        let force = name.hasSuffix("--force") || name.hasSuffix(" -f")
        if force {
            name = name.replacingOccurrences(of: "--force", with: "").replacingOccurrences(of: " -f", with: "").trimmingCharacters(in: .whitespaces)
        }
        if name.isEmpty {
            return await sendRunningApps(to: chatID)
        }
        let target = name
        let quit: String?
        if let number = Int(target) {
            let list = await MainActor.run { self.runningLists[chatID] }
            guard let list, number >= 1, number <= list.count else {
                try? await send("⚠️ Send /apps first, then tap /quit_N.", to: chatID)
                return
            }
            quit = await MainActor.run { RemoteTools.quit(pid: list[number - 1].pid, force: force) }
        } else {
            quit = await MainActor.run { RemoteTools.quitApp(target, force: force) }
        }
        if let quit {
            try? await send(force ? "💥 Force quit \(quit)." : "👋 Asked \(quit) to quit.", to: chatID)
        } else {
            try? await send("⚠️ That app isn't running anymore. Send /apps for a fresh list.", to: chatID)
        }
    }

    private func sendLong(header: String, lines: [String], footer: String, to chatID: Int64) async {
        var chunks: [String] = []
        var current = header + "\n"
        for line in lines {
            if current.count + line.count + 1 > 3800 {
                chunks.append(current)
                current = ""
            }
            current += "\n" + line
        }
        current += "\n\n" + footer
        chunks.append(current)
        for chunk in chunks {
            try? await send(chunk, to: chatID)
        }
    }

    private func search(_ query: String, in place: RemoteTools.Place, chatID: Int64) async {
        _ = try? await call("sendChatAction", ["chat_id": chatID, "action": "typing"])
        let urls = await Task.detached { RemoteTools.find(query, in: place) }.value
        await sendFileList(urls.map { ($0, nil) }, header: "🔍 “\(query)” in \(place.title)", empty: "🔍 Nothing in \(place.title) matches “\(query)”.", chatID: chatID)
    }

    private func sendFileList(_ items: [(URL, Date?)], header: String, empty: String, chatID: Int64) async {
        await MainActor.run { self.foundFiles[chatID] = items.map(\.0) }
        guard !items.isEmpty else {
            try? await send(empty, to: chatID)
            return
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .short
        let lines = items.enumerated().map { index, item -> String in
            var isFolder: ObjCBool = false
            FileManager.default.fileExists(atPath: item.0.path, isDirectory: &isFolder)
            let icon = isFolder.boolValue ? "📁" : "📄"
            let when = item.1.map { " · " + relative.localizedString(for: $0, relativeTo: Date()) } ?? ""
            let path = item.0.deletingLastPathComponent().path.replacingOccurrences(of: home, with: "~")
            return "\(index + 1). \(icon) \(item.0.lastPathComponent)\(when)\n    \(path)\n    /get_\(index + 1) · /openfile_\(index + 1)"
        }
        await sendLong(header: header, lines: lines, footer: "Tap /get_N to receive a file here, or /openfile_N to open it on the Mac.", to: chatID)
    }

    private func resolveFile(_ argument: String, chatID: Int64) async -> URL? {
        guard !argument.isEmpty else { return nil }
        if let index = Int(argument) {
            let list = await MainActor.run { self.foundFiles[chatID] ?? [] }
            guard index >= 1, index <= list.count else { return nil }
            return list[index - 1]
        }
        let url = RemoteTools.expand(argument)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func addSchedule(_ args: [String], chatID: Int64) async {
        guard args.count >= 2 else {
            return try! await send("Usage: /schedule <time> <action> [weekdays]\nActions: off, displayoff, screensaver, lock, sleep, restart, shutdown\nExample: /schedule 01:00 sleep weekdays", to: chatID)
        }
        let pieces = args[0].split(separator: ":")
        guard pieces.count == 2, let hour = Int(pieces[0]), let minute = Int(pieces[1]), (0...23).contains(hour), (0...59).contains(minute) else {
            return try! await send("⚠️ Use a 24-hour time like 01:00 or 18:30.", to: chatID)
        }
        guard let action = PowerAction.from(keyword: args[1]) else {
            return try! await send("⚠️ Unknown action “\(args[1])”. Try off, displayoff, screensaver, lock, sleep, restart or shutdown.", to: chatID)
        }
        let weekdays = args.count > 2 && ["weekday", "weekdays", "wd"].contains(args[2].lowercased())
        let item = ScheduledAction(action: action, hour: hour, minute: minute, weekdaysOnly: weekdays)
        await MainActor.run { ScheduleStore.shared.add(item) }
        try? await send("🗓 Scheduled: \(item.describe).", to: chatID)
    }

    private func receiveUpload(_ document: [String: Any], chatID: Int64) async {
        guard let fileID = document["file_id"] as? String else { return }
        let size = (document["file_size"] as? NSNumber)?.int64Value ?? 0
        if size > 2 * 1024 * 1024 * 1024 {
            try? await send("⚠️ That file is larger than Telegram lets bots download (2 GB).", to: chatID)
            return
        }
        let name = (document["file_name"] as? String) ?? "upload-\(Int(Date().timeIntervalSince1970))"
        _ = try? await call("sendChatAction", ["chat_id": chatID, "action": "typing"])
        do {
            let info = try await call("getFile", ["file_id": fileID])
            guard let path = info["file_path"] as? String, let token else { throw BotError.message("Telegram didn't return a file path") }
            guard let url = URL(string: "https://api.telegram.org/file/bot\(token)/\(path)") else { throw BotError.message("Bad file URL") }
            let (location, _) = try await session.download(from: url)
            let saved = try saveToDownloads(location, suggestedName: name)
            try? await send("📥 Saved to Downloads as \(saved.lastPathComponent).", to: chatID)
        } catch {
            try? await send("⚠️ Couldn't save that file: \(redact(error.localizedDescription))", to: chatID)
        }
    }

    private func saveToDownloads(_ source: URL, suggestedName: String) throws -> URL {
        let fm = FileManager.default
        let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let safeName = (suggestedName as NSString).lastPathComponent.replacingOccurrences(of: "/", with: "-")
        var target = downloads.appendingPathComponent(safeName.isEmpty ? "upload" : safeName)
        let base = target.deletingPathExtension().lastPathComponent
        let ext = target.pathExtension
        var counter = 1
        while fm.fileExists(atPath: target.path) {
            let numbered = ext.isEmpty ? "\(base) (\(counter))" : "\(base) (\(counter)).\(ext)"
            target = downloads.appendingPathComponent(numbered)
            counter += 1
        }
        try fm.moveItem(at: source, to: target)
        return target
    }

    private func sendFile(_ url: URL, to chatID: Int64) async {
        var isFolder: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder)
        var target = url
        var temporary = false
        if isFolder.boolValue {
            guard let zip = RemoteTools.zipFolder(url) else {
                try? await send("⚠️ Couldn't zip \(url.lastPathComponent).", to: chatID)
                return
            }
            target = zip
            temporary = true
        }
        defer { if temporary { try? FileManager.default.removeItem(at: target) } }
        guard RemoteTools.fileSize(target) <= Self.uploadLimit else {
            try? await send("⚠️ \(target.lastPathComponent) is larger than Telegram's 50 MB bot limit.", to: chatID)
            return
        }
        _ = try? await call("sendChatAction", ["chat_id": chatID, "action": "upload_document"])
        do {
            try await upload(file: target, method: "sendDocument", field: "document", mime: "application/octet-stream", chatID: chatID)
        } catch {
            try? await send("⚠️ Upload failed: \(redact(error.localizedDescription))", to: chatID)
        }
    }

    private func sendScreenshots(to chatID: Int64) async {
        _ = try? await call("sendChatAction", ["chat_id": chatID, "action": "upload_photo"])
        let urls = await MainActor.run { SystemInfo.screenshots() }
        if urls.isEmpty {
            try? await send("⚠️ Could not take a screenshot. Allow KeepMeUp in System Settings → Privacy & Security → Screen Recording.", to: chatID)
        }
        for url in urls {
            try? await upload(file: url, method: "sendPhoto", field: "photo", mime: "image/jpeg", chatID: chatID)
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func sendOutput(_ result: RemoteTools.ShellResult, command: String, to chatID: Int64) async {
        var footer = "exit \(result.status)"
        if result.timedOut { footer = "stopped after 60s" }
        let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if output.count <= 3500 {
            let body = output.isEmpty ? "(no output)" : output
            let html = "<b>$ \(escape(command))</b>\n<pre>\(escape(body))</pre>\n<i>\(footer)</i>"
            _ = try? await call("sendMessage", ["chat_id": chatID, "text": html, "parse_mode": "HTML"])
            return
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("KeepMeUp", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("output-\(Int(Date().timeIntervalSince1970)).txt")
        try? Data("$ \(command)\n\n\(output)\n\n\(footer)\n".utf8).write(to: file)
        try? await upload(file: file, method: "sendDocument", field: "document", mime: "text/plain", chatID: chatID)
        try? FileManager.default.removeItem(at: file)
    }

    private func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func handleCallback(_ callback: [String: Any]) async {
        guard let id = callback["id"] as? String,
              let message = callback["message"] as? [String: Any],
              let rawChat = message["chat"] as? [String: Any],
              let chat = ChatInfo(telegram: rawChat),
              let from = callback["from"] as? [String: Any],
              let senderID = (from["id"] as? NSNumber)?.int64Value,
              let messageID = message["message_id"] as? NSNumber,
              let data = callback["data"] as? String else { return }

        let allowed = await MainActor.run { isAuthorized(chat: chat, senderID: senderID) }
        guard allowed else {
            _ = try? await call("answerCallbackQuery", ["callback_query_id": id, "text": "Not authorized"])
            return
        }

        if data.hasPrefix("confirm:"), let action = PowerAction(rawValue: String(data.dropFirst(8))) {
            _ = try? await call("answerCallbackQuery", ["callback_query_id": id])
            _ = try? await call("editMessageText", ["chat_id": chat.id, "message_id": messageID, "text": "⏻ \(action.title) in progress…"])
            await perform(action)
        } else {
            _ = try? await call("answerCallbackQuery", ["callback_query_id": id, "text": "Cancelled"])
            _ = try? await call("editMessageText", ["chat_id": chat.id, "message_id": messageID, "text": "Cancelled."])
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

    private func registerProfile() async throws {
        let description = "KeepMeUp lets you control your Mac from Telegram: keep it awake, set timers, lock, sleep, take screenshots and more.\n\nTap Start, then click “Allow” on your Mac to pair."
        _ = try await call("setMyDescription", ["description": description])
        _ = try await call("setMyShortDescription", ["short_description": "Remote control for your Mac, by KeepMeUp."])
    }

    private func registerCommands() async throws {
        let (commands, chats) = await MainActor.run {
            (BotCommand.enabledCommands().map { ["command": $0.rawValue, "description": $0.summary] }, Preferences.shared.allowedChats)
        }
        let publicCommands = [["command": "start", "description": "Pair this chat with your Mac"]]
        _ = try await call("setMyCommands", ["commands": publicCommands])
        for chat in chats where chat.isPrivate || chat.isGroup {
            _ = try? await call("setMyCommands", ["commands": commands, "scope": ["type": "chat", "chat_id": chat.id]])
        }
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

    private func upload(file: URL, method: String, field: String, mime: String, chatID: Int64) async throws {
        let boundary = "KeepMeUp-\(UUID().uuidString)"
        var request = URLRequest(url: try endpoint(method))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let filename = file.lastPathComponent.replacingOccurrences(of: "\"", with: "")
        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"chat_id\"\r\n\r\n\(chatID)\r\n".utf8))
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(field)\"; filename=\"\(filename)\"\r\nContent-Type: \(mime)\r\n\r\n".utf8))
        body.append(try Data(contentsOf: file))
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
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
