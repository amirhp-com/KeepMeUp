import SwiftUI

struct MenuView: View {
    @ObservedObject private var awake = AwakeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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

            Divider()

            Button("Quit KeepMeUp") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(14)
        .frame(width: 300)
    }
}
