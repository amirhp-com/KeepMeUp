import SwiftUI

struct MenuView: View {
    @ObservedObject private var awake = AwakeManager.shared
    @ObservedObject private var scheduler = Scheduler.shared
    @ObservedObject private var updater = Updater.shared

    @State private var action: PowerAction = .stopAwake
    @State private var customText = ""

    private let presets: [(String, TimeInterval)] = [("15m", 900), ("30m", 1800), ("1h", 3600), ("2h", 7200)]

    var body: some View {
        VStack(spacing: 12) {
            header
            if let remaining = scheduler.remaining, let current = scheduler.action {
                countdown(remaining: remaining, action: current)
            } else {
                timerCard
            }
            if updater.updateAvailable, let latest = updater.latest {
                updateBanner(latest)
            }
            footer
        }
        .padding(14)
        .frame(width: 320)
        .noFocusRing()
    }

    private var header: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { awake.toggle() }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(awake.isActive
                              ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0.31, green: 0.27, blue: 0.9), Color(red: 0.13, green: 0.83, blue: 0.93)], startPoint: .topLeading, endPoint: .bottomTrailing))
                              : AnyShapeStyle(Color.secondary.opacity(0.18)))
                    Image(systemName: awake.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(awake.isActive ? Color.white : Color.secondary)
                }
                .frame(width: 46, height: 46)
                .shadow(color: awake.isActive ? Color.cyan.opacity(0.35) : .clear, radius: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(awake.isActive ? (awake.linkedApp.map { "Awake for \($0)" } ?? "Staying awake") : "Sleep as usual")
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Text(awake.isActive ? "Sleep & screensaver are blocked" : "Click to keep your Mac awake")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Capsule()
                    .fill(awake.isActive ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 38, height: 22)
                    .overlay(alignment: awake.isActive ? .trailing : .leading) {
                        Circle().fill(.white).padding(2).shadow(radius: 1)
                    }
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassCard(cornerRadius: 18)
    }

    private func countdown(remaining: TimeInterval, action: PowerAction) -> some View {
        HStack(spacing: 12) {
            Image(systemName: action.symbol)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.accentColor.opacity(0.18)))
            VStack(alignment: .leading, spacing: 0) {
                Text(action.title).font(.caption).foregroundStyle(.secondary)
                Text(DurationText.format(remaining))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            Spacer()
            Button("Cancel") { scheduler.cancel() }
                .compatGlassButton()
        }
        .padding(12)
        .glassCard()
    }

    private var timerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Timer", systemImage: "timer")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Menu {
                    ForEach(PowerAction.allCases) { item in
                        Button {
                            action = item
                        } label: {
                            Label(item.title, systemImage: item.symbol)
                        }
                    }
                } label: {
                    Label(action.title, systemImage: action.symbol)
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            HStack(spacing: 6) {
                ForEach(presets, id: \.0) { preset in
                    Button {
                        start(preset.1)
                    } label: {
                        Text(preset.0)
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity)
                    }
                    .compatGlassButton()
                }
            }
            HStack(spacing: 6) {
                TextField("", text: $customText, prompt: Text("Custom: 45m, 1h30m, 2:15"))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
                    .onSubmit(startCustom)
                Button(action: startCustom) {
                    Image(systemName: "play.fill")
                }
                .compatGlassButton()
                .disabled(DurationText.parse(customText) == nil)
            }
        }
        .padding(12)
        .glassCard()
    }

    private func updateBanner(_ latest: Updater.Release) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 0) {
                Text("Update available").font(.system(size: 12, weight: .semibold))
                Text("Version \(latest.version)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if updater.phase == .downloading {
                ProgressView().controlSize(.small)
            } else {
                Button("Update") { updater.install() }
                    .compatGlassButton(prominent: true)
            }
        }
        .padding(10)
        .glassCard()
    }

    private var footer: some View {
        HStack {
            Button {
                SettingsWindow.show()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .compatGlassButton()
            Spacer()
            Text("v\(updater.currentVersion)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .compatGlassButton()
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

extension View {
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = 14) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    @ViewBuilder
    func compatGlassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                buttonStyle(.glassProminent)
            } else {
                buttonStyle(.glass)
            }
        } else if prominent {
            buttonStyle(.borderedProminent)
        } else {
            buttonStyle(.bordered)
        }
    }
}
