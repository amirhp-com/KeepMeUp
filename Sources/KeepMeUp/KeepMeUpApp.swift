import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        StatusItem.shared.install()
        let prefs = Preferences.shared
        if prefs.restoreOnLaunch && prefs.lastActive {
            AwakeManager.shared.enable()
        }
        TelegramBot.shared.startIfEnabled()
        Updater.shared.startAutomaticChecks()
        ScheduleStore.shared.start()
        LidManager.shared.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            AlertMonitor.shared.start()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            LaunchTip.show()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { StatusItem.shared.show() }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        let wasActive = AwakeManager.shared.isActive
        AwakeManager.shared.disable()
        LidManager.shared.restoreOnQuit()
        Preferences.shared.lastActive = wasActive
    }
}
