import ServiceManagement
import SwiftUI

enum SettingsWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            hosting.sizingOptions = [.preferredContentSize]
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = "KeepMeUp Settings"
            newWindow.styleMask = [.titled, .closable, .miniaturizable]
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            window = newWindow
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

final class SettingsRouter: ObservableObject {
    static let shared = SettingsRouter()
    @Published var tab: SettingsView.Tab = .general
}

struct SettingsView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case general = "General"
        case telegram = "Telegram"
        case commands = "Commands"
        case about = "About"
        var id: String { rawValue }
    }

    @ObservedObject private var router = SettingsRouter.shared

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $router.tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.top, 16)

            Group {
                switch router.tab {
                case .general: GeneralSettingsView()
                case .telegram: TelegramSettingsView()
                case .commands: CommandsSettingsView()
                case .about: AboutView()
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 480)
        .noFocusRing()
    }
}

struct GeneralSettingsView: View {
    @ObservedObject private var prefs = Preferences.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Launch KeepMeUp at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { value in
                        do {
                            if value {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                Toggle("Resume keeping awake after relaunch", isOn: $prefs.restoreOnLaunch)
            } footer: {
                Text("While active, KeepMeUp blocks display sleep, the screensaver and idle system sleep, no matter what Energy or Lock Screen settings say.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Toggle("Low battery warning", isOn: $prefs.batteryAlerts)
                Toggle("Power adapter connected or unplugged", isOn: $prefs.powerAlerts)
                Toggle("“Mac is online” after launch", isOn: $prefs.onlineAlert)
            } header: {
                Text("Telegram alerts")
            } footer: {
                Text("When on, your paired chat gets a message for these events. They need Telegram control turned on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }
}

struct TelegramSettingsView: View {
    @ObservedObject private var prefs = Preferences.shared
    @ObservedObject private var bot = TelegramBot.shared
    @State private var token = TokenStore.read()
    @State private var newChatID = ""
    @State private var revealToken = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bot token")
                    HStack(spacing: 6) {
                        Group {
                            if revealToken {
                                TextField("", text: $token, prompt: Text("123456789:AAH…"))
                            } else {
                                SecureField("", text: $token, prompt: Text("123456789:AAH…"))
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .labelsHidden()
                        Button {
                            revealToken.toggle()
                        } label: {
                            Image(systemName: revealToken ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                        .help(revealToken ? "Hide token" : "Show token")
                    }
                    Text("Create a bot with [@BotFather](https://t.me/BotFather) and paste its token here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Toggle("Enable Telegram control", isOn: $prefs.botEnabled)
                        .onChange(of: prefs.botEnabled) { enabled in
                            enabled ? saveAndStart() : bot.stop()
                        }
                    Spacer()
                    Button("Save & Connect") { saveAndStart() }
                        .disabled(token.isEmpty)
                }
                statusLine
                if bot.isRunning {
                    HStack(spacing: 10) {
                        Image(systemName: "switch.2")
                            .foregroundStyle(Color.accentColor)
                        Text("Your bot is connected. Choose which commands your chats can use in the Commands tab.")
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Button("Open Commands") { SettingsRouter.shared.tab = .commands }
                            .controlSize(.small)
                    }
                }
            }

            if prefs.allowedChats.isEmpty {
                Section("Get started") {
                    onboarding
                }
            }

            Section {
                if prefs.allowedChats.isEmpty {
                    Text("No chats yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(prefs.allowedChats) { chat in
                    ChatRow(chat: chat) {
                        prefs.allowedChats.removeAll { $0.id == chat.id }
                        bot.refreshCommands()
                    }
                }
                HStack {
                    TextField("", text: $newChatID, prompt: Text("Chat ID, e.g. 123456789"))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .onSubmit(addChat)
                    Button("Add", action: addChat)
                        .disabled(parsedChatID == nil)
                }
            } header: {
                Text("Allowed chats")
            }

            if !prefs.allowedChats.isEmpty {
                Section {
                    pairAnother
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }

    private var parsedChatID: Int64? {
        Int64(newChatID.trimmingCharacters(in: .whitespaces))
    }

    private func addChat() {
        guard let id = parsedChatID else { return }
        if !prefs.isAllowed(id) {
            prefs.upsert(ChatInfo(id: id, type: id > 0 ? "private" : "unknown"))
            bot.lookUp(id)
            bot.refreshCommands()
        }
        newChatID = ""
    }

    @ViewBuilder
    private var onboarding: some View {
        let hasToken = !TokenStore.read().isEmpty
        let running = bot.isRunning
        StepRow(number: 1, done: hasToken && running, title: "Connect your bot", detail: "Paste the token above, turn on Telegram control and click Save & Connect.")
        StepRow(number: 2, done: false, active: running && !bot.awaitingApproval, title: "Start the bot in Telegram", detail: running ? "Open \(bot.botUsername.map { "@\($0)" } ?? "your bot") and tap Start." : "Available once the bot is connected.") {
            if running, let username = bot.botUsername, let url = URL(string: "https://t.me/\(username)?start=pair") {
                Link(destination: url) {
                    Label("Open in Telegram", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        StepRow(number: 3, done: false, active: bot.awaitingApproval, title: "Approve on this Mac", detail: bot.awaitingApproval ? "Click Allow in the KeepMeUp window that just appeared." : "KeepMeUp will ask you to allow the chat. Then the bot sends you the list of commands.")
    }

    @ViewBuilder
    private var pairAnother: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let until = bot.pairingOpenUntil, until > Date() {
                    Label("Pairing is open — send /start from the new chat", systemImage: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(.green)
                    Spacer()
                    Button("Close") { bot.closePairing() }
                } else {
                    Button {
                        bot.openPairing()
                    } label: {
                        Label("Pair another chat", systemImage: "plus.circle")
                    }
                }
            }
            Text("After your first chat is paired, KeepMeUp stops accepting new /start requests so strangers who find your bot can't ask for access. This opens pairing for 5 minutes. To add a group, add the bot to it and send /pair there.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch bot.state {
        case .stopped:
            Label("Stopped", systemImage: "circle").foregroundStyle(.secondary)
        case .connecting:
            Label("Connecting…", systemImage: "circle.dotted").foregroundStyle(.orange)
        case .running(let name):
            Label("Running as \(name)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
    }

    private func saveAndStart() {
        TokenStore.save(token)
        if prefs.botEnabled { bot.start() }
    }
}

struct ChatRow: View {
    let chat: ChatInfo
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: chat.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(color))
            VStack(alignment: .leading, spacing: 2) {
                Text(chat.title.isEmpty ? "Chat \(chat.id)" : chat.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(role: .destructive, action: onRemove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove this chat")
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        [chat.username.map { "@\($0)" }, chat.kind, String(chat.id)].compactMap { $0 }.joined(separator: " · ")
    }

    private var color: Color {
        switch chat.type {
        case "private": return .blue
        case "group", "supergroup": return .green
        case "channel": return .orange
        default: return .gray
        }
    }
}

struct StepRow<Accessory: View>: View {
    let number: Int
    let done: Bool
    var active: Bool = false
    let title: String
    let detail: String
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? Color.green : (active ? Color.accentColor : Color.secondary.opacity(0.25)))
                if done {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(.system(size: 12, weight: .bold)).foregroundStyle(active ? .white : .primary)
                }
            }
            .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                accessory()
            }
            Spacer(minLength: 0)
        }
    }
}

extension StepRow where Accessory == EmptyView {
    init(number: Int, done: Bool, active: Bool = false, title: String, detail: String) {
        self.init(number: number, done: done, active: active, title: title, detail: detail) { EmptyView() }
    }
}

struct CommandsSettingsView: View {
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        Form {
            Section {
                Text("Choose what your paired chats can do. Turned-off commands disappear from the bot menu and are refused. Commands marked with a shield can see your screen, read files or run code on this Mac, so turning one on asks for your password or Touch ID.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(BotCommand.Group.allCases) { group in
                Section {
                    ForEach(BotCommand.allCases.filter { $0.group == group }) { command in
                        Toggle(isOn: Binding(
                            get: { prefs.isEnabled(command) },
                            set: { value in
                                guard value, command.isSensitive else {
                                    prefs.setEnabled(command, value)
                                    TelegramBot.shared.refreshCommands()
                                    return
                                }
                                Authenticator.confirm("turn on /\(command.rawValue) for your Telegram chats") { approved in
                                    guard approved else { return }
                                    prefs.setEnabled(command, true)
                                    TelegramBot.shared.refreshCommands()
                                }
                            }
                        )) {
                            HStack(spacing: 6) {
                                Text(command.usage).font(.system(.body, design: .monospaced))
                                if command.isSensitive {
                                    Image(systemName: "checkmark.shield")
                                        .foregroundStyle(.orange)
                                        .help("Sensitive")
                                }
                            }
                            Text(command.summary)
                        }
                    }
                } header: {
                    Label(group.rawValue, systemImage: group.symbol)
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 560)
    }
}

struct AboutView: View {
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("KeepMeUp").font(.title).bold()
            Text("Version \(updater.currentVersion)").foregroundStyle(.secondary)
            Text("Free and open source. Keep your Mac awake, on your terms.")
                .multilineTextAlignment(.center)
            HStack(spacing: 16) {
                Link("AmirhpCom", destination: URL(string: "https://amirhp.com")!)
                Link("GitHub", destination: URL(string: "https://github.com/amirhp-com/KeepMeUp")!)
            }
            .noFocusRing()

            UpdatePanel()
                .padding(.top, 6)

            HStack(spacing: 4) {
                Text("© 2026")
                Link("AmirhpCom", destination: URL(string: "https://amirhp.com")!)
                Text("· Released under the MIT License.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .noFocusRing()
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }
}

struct UpdatePanel: View {
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        VStack(spacing: 8) {
            switch updater.phase {
            case .available:
                if let latest = updater.latest {
                    Text("Version \(latest.version) is available").font(.headline)
                    HStack {
                        Button("Update & Relaunch") { updater.install() }
                            .buttonStyle(.borderedProminent)
                        Button("Release Notes") { NSWorkspace.shared.open(latest.page) }
                    }
                }
            case .downloading:
                ProgressView().controlSize(.small)
                Text("Downloading the update…").font(.caption).foregroundStyle(.secondary)
            case .checking:
                ProgressView().controlSize(.small)
            case .upToDate:
                Label("You're up to date", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                Button("Check Again") { updater.check() }
            case .failed(let message):
                Text(message).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center)
                Button("Try Again") { updater.check() }
            case .idle:
                Button("Check for Updates") { updater.check() }
            }
            Toggle("Check for updates automatically", isOn: $updater.autoCheck)
                .toggleStyle(.checkbox)
                .font(.caption)
        }
    }
}

extension View {
    @ViewBuilder
    func noFocusRing() -> some View {
        if #available(macOS 14.0, *) {
            focusEffectDisabled()
        } else {
            self
        }
    }
}
