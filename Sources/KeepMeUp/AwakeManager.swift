import AppKit
import Foundation
import IOKit.pwr_mgt

final class AwakeManager: ObservableObject {
    static let shared = AwakeManager()

    @Published private(set) var isActive = false
    @Published private(set) var linkedApp: String?

    private var assertionIDs: [IOPMAssertionID] = []
    private let reason = "KeepMeUp is keeping this Mac awake" as CFString
    private var appObserver: NSObjectProtocol?

    private init() {}

    @discardableResult
    func caffeinate(whileRunning name: String) -> String? {
        guard let app = RemoteTools.findRunningApp(name) else { return nil }
        let title = app.localizedName ?? name
        enable()
        linkedApp = title
        appObserver.map(NSWorkspace.shared.notificationCenter.removeObserver)
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, let quit = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            if quit.processIdentifier == app.processIdentifier {
                self.disable()
                TelegramBot.shared.notify("💤 \(title) quit, so KeepMeUp stopped keeping \(SystemInfo.hostName()) awake.")
            }
        }
        return title
    }

    private func clearLink() {
        linkedApp = nil
        appObserver.map(NSWorkspace.shared.notificationCenter.removeObserver)
        appObserver = nil
    }

    func enable() {
        guard !isActive else { return }
        let types = [
            kIOPMAssertionTypePreventUserIdleDisplaySleep,
            kIOPMAssertionTypePreventUserIdleSystemSleep,
            kIOPMAssertionTypePreventSystemSleep
        ]
        for type in types {
            var id = IOPMAssertionID(0)
            if IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), reason, &id) == kIOReturnSuccess {
                assertionIDs.append(id)
            }
        }
        isActive = !assertionIDs.isEmpty
        Preferences.shared.lastActive = isActive
    }

    func disable() {
        for id in assertionIDs { IOPMAssertionRelease(id) }
        assertionIDs.removeAll()
        isActive = false
        clearLink()
        Preferences.shared.lastActive = false
    }

    func toggle() {
        isActive ? disable() : enable()
    }
}
