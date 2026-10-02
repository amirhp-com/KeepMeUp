import ServiceManagement
import SwiftUI

enum SettingsWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView())
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

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            TelegramSettingsView()
                .tabItem { Label("Telegram", systemImage: "paperplane") }
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .padding(20)
        .frame(width: 520, height: 480)
    }
}

struct GeneralSettingsView: View {
    @ObservedObject private var prefs = Preferences.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
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
            Text("While active, KeepMeUp holds macOS power assertions that block display sleep, the screensaver and idle system sleep, no matter what Energy or Lock Screen settings say.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct TelegramSettingsView: View {
    @ObservedObject private var prefs = Preferences.shared
    @ObservedObject private var bot = TelegramBot.shared
    @State private var token = Keychain.read(TelegramBot.tokenAccount) ?? ""
    @State private var newChatID = ""

    var body: some View {
        Form {
            Section {
                SecureField("Bot token from @BotFather", text: $token)
                HStack {
                    Toggle("Enable Telegram control", isOn: $prefs.botEnabled)
                        .onChange(of: prefs.botEnabled) { enabled in
                            enabled ? saveAndStart() : bot.stop()
                        }
                    Spacer()
                    Button("Save & Restart") { saveAndStart() }
                        .disabled(token.isEmpty)
                }
                statusLine
            }

            Section("Allowed chats") {
                if prefs.allowedChatIDs.isEmpty {
                    Text("No chats yet. Send /pair to your bot and approve it here.")
                        .foregroundStyle(.secondary)
                }
                ForEach(prefs.allowedChatIDs, id: \.self) { id in
                    HStack {
                        Text(String(id)).font(.system(.body, design: .monospaced))
                        Spacer()
                        Button(role: .destructive) {
                            prefs.allowedChatIDs.removeAll { $0 == id }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField("Add chat ID", text: $newChatID)
                    Button("Add") {
                        if let id = Int64(newChatID.trimmingCharacters(in: .whitespaces)), !prefs.allowedChatIDs.contains(id) {
                            prefs.allowedChatIDs.append(id)
                        }
                        newChatID = ""
                    }
                    .disabled(Int64(newChatID.trimmingCharacters(in: .whitespaces)) == nil)
                }
                if !prefs.allowedChatIDs.isEmpty {
                    HStack {
                        Button("Allow a new /pair for 5 minutes") { bot.openPairing() }
                        if let until = bot.pairingOpenUntil, until > Date() {
                            Text("Open").foregroundStyle(.green).font(.caption)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
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
        Keychain.save(token.trimmingCharacters(in: .whitespacesAndNewlines), for: TelegramBot.tokenAccount)
        if prefs.botEnabled { bot.start() }
    }
}

struct AboutView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("KeepMeUp").font(.title).bold()
            Text("Version \(version)").foregroundStyle(.secondary)
            Text("Free and open source. Keep your Mac awake, on your terms.")
                .multilineTextAlignment(.center)
            HStack(spacing: 16) {
                Link("amirhp.com", destination: URL(string: "https://amirhp.com")!)
                Link("GitHub", destination: URL(string: "https://github.com/amirhp-com/KeepMeUp")!)
            }
            Spacer()
            Text("© 2026 AmirhpCom. Released under the MIT License.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
