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

struct SettingsView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case general = "General"
        case telegram = "Telegram"
        case about = "About"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .general

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.top, 16)

            Group {
                switch tab {
                case .general: GeneralSettingsView()
                case .telegram: TelegramSettingsView()
                case .about: AboutView()
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 480)
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
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }
}

struct TelegramSettingsView: View {
    @ObservedObject private var prefs = Preferences.shared
    @ObservedObject private var bot = TelegramBot.shared
    @State private var token = Keychain.read(TelegramBot.tokenAccount) ?? ""
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
                    TextField("", text: $newChatID, prompt: Text("Chat ID, e.g. 123456789"))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
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
        .scrollDisabled(true)
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
            .noFocusRing()
            Text("© 2026 AmirhpCom. Released under the MIT License.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }
}

private extension View {
    @ViewBuilder
    func noFocusRing() -> some View {
        if #available(macOS 14.0, *) {
            focusEffectDisabled()
        } else {
            self
        }
    }
}
