import Foundation
import IOKit.pwr_mgt

final class AwakeManager: ObservableObject {
    static let shared = AwakeManager()

    @Published private(set) var isActive = false

    private var assertionIDs: [IOPMAssertionID] = []
    private let reason = "KeepMeUp is keeping this Mac awake" as CFString

    private init() {}

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
        Preferences.shared.lastActive = false
    }

    func toggle() {
        isActive ? disable() : enable()
    }
}
