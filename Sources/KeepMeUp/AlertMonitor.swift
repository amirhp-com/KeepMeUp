import Foundation
import IOKit.ps

final class AlertMonitor {
    static let shared = AlertMonitor()

    private var runLoopSource: CFRunLoopSource?
    private var timer: Timer?
    private var lastPlugged: Bool?
    private var lowNotified = false
    private let lowThreshold = 20

    private init() {}

    func start() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<AlertMonitor>.fromOpaque(context).takeUnretainedValue().evaluate()
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = source
        }
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in self?.evaluate() }
        announceOnlineIfNeeded()
        primeState()
    }

    private func primeState() {
        let snapshot = SystemInfo.batterySnapshot()
        lastPlugged = snapshot.plugged
        if let percent = snapshot.percent { lowNotified = percent <= lowThreshold }
    }

    private func announceOnlineIfNeeded() {
        guard Preferences.shared.onlineAlert else { return }
        TelegramBot.shared.notify("✅ \(SystemInfo.hostName()) is online.\n\(SystemInfo.battery())")
    }

    private func evaluate() {
        let snapshot = SystemInfo.batterySnapshot()

        if Preferences.shared.powerAlerts, let plugged = snapshot.plugged {
            if let previous = lastPlugged, previous != plugged {
                let detail = snapshot.percent.map { " · \($0)%" } ?? ""
                TelegramBot.shared.notify(plugged ? "🔌 Power adapter connected\(detail)." : "🔋 Running on battery\(detail).")
            }
            lastPlugged = plugged
        }

        if Preferences.shared.batteryAlerts, let percent = snapshot.percent, let plugged = snapshot.plugged {
            if !plugged, percent <= lowThreshold, !lowNotified {
                TelegramBot.shared.notify("🪫 Battery low: \(percent)%. Plug in \(SystemInfo.hostName()) soon.")
                lowNotified = true
            } else if plugged || percent > lowThreshold + 5 {
                lowNotified = false
            }
        }
    }
}
