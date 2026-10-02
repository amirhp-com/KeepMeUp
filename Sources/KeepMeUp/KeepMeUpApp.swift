import SwiftUI

@main
struct KeepMeUpApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var awake = AwakeManager.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView()
        } label: {
            Image(systemName: awake.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let prefs = Preferences.shared
        if prefs.restoreOnLaunch && prefs.lastActive {
            AwakeManager.shared.enable()
        }
        TelegramBot.shared.startIfEnabled()
    }

    func applicationWillTerminate(_ notification: Notification) {
        let wasActive = AwakeManager.shared.isActive
        AwakeManager.shared.disable()
        Preferences.shared.lastActive = wasActive
    }
}
