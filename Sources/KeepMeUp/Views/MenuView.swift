import SwiftUI

struct MenuView: View {
    @ObservedObject private var awake = AwakeManager.shared
    @ObservedObject private var scheduler = Scheduler.shared
    @Environment(\.openURL) private var openURL

    @State private var action: PowerAction = .stopAwake
    @State private var customText = ""

    private let presets: [(String, TimeInterval)] = [("15m", 900), ("30m", 1800), ("1h", 3600), ("2h", 7200)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            timerSection
            Divider()
            quickActions
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
    }

    private var header: some View {
        HStack {
            Image(systemName: awake.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                .font(.title2)
                .foregroundStyle(awake.isActive ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading) {
                Text("KeepMeUp").font(.headline)
                Text(awake.isActive ? "Your Mac stays awake" : "Normal sleep settings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { awake.isActive }, set: { $0 ? awake.enable() : awake.disable() }))
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    @ViewBuilder
    private var timerSection: some View {
        if let remaining = scheduler.remaining, let current = scheduler.action {
            HStack {
                Image(systemName: current.symbol)
                VStack(alignment: .leading) {
                    Text(current.title).font(.subheadline)
                    Text("in \(DurationText.format(remaining))")
                        .font(.system(.title3, design: .monospaced))
                }
                Spacer()
                Button("Cancel") { scheduler.cancel() }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Timer").font(.subheadline).foregroundStyle(.secondary)
                Picker("", selection: $action) {
                    ForEach(PowerAction.allCases) { item in
                        Label(item.title, systemImage: item.symbol).tag(item)
                    }
                }
                .labelsHidden()
                HStack(spacing: 6) {
                    ForEach(presets, id: \.0) { preset in
                        Button(preset.0) { start(preset.1) }
                    }
                }
                HStack(spacing: 6) {
                    TextField("e.g. 45m, 1h30m, 2:15", text: $customText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(startCustom)
                    Button("Start", action: startCustom)
                        .disabled(DurationText.parse(customText) == nil)
                }
            }
        }
    }

    private var quickActions: some View {
        HStack(spacing: 8) {
            ForEach([PowerAction.displayOff, .screensaver, .lock, .sleep]) { item in
                Button {
                    PowerActions.perform(item)
                } label: {
                    Image(systemName: item.symbol).frame(maxWidth: .infinity)
                }
                .help(item.title)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Settings…") { SettingsWindow.show() }
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }

    private func start(_ interval: TimeInterval) {
        awake.enable()
        scheduler.schedule(action, after: interval)
    }

    private func startCustom() {
        guard let interval = DurationText.parse(customText) else { return }
        start(interval)
        customText = ""
    }
}
