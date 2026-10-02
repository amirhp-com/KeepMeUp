import Foundation

struct ScheduledAction: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var action: PowerAction
    var hour: Int
    var minute: Int
    var weekdaysOnly: Bool
    var enabled: Bool = true

    var timeText: String {
        String(format: "%02d:%02d", hour, minute)
    }

    var describe: String {
        "\(action.title) at \(timeText)\(weekdaysOnly ? " on weekdays" : " every day")"
    }
}

final class ScheduleStore: ObservableObject {
    static let shared = ScheduleStore()

    @Published var actions: [ScheduledAction] {
        didSet {
            if let data = try? JSONEncoder().encode(actions) {
                UserDefaults.standard.set(data, forKey: "scheduledActions")
            }
        }
    }

    private var timer: Timer?
    private var fired = Set<String>()

    private init() {
        if let data = UserDefaults.standard.data(forKey: "scheduledActions"),
           let saved = try? JSONDecoder().decode([ScheduledAction].self, from: data) {
            actions = saved
        } else {
            actions = []
        }
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in self?.tick() }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    func add(_ action: ScheduledAction) {
        actions.append(action)
    }

    func remove(_ id: UUID) {
        actions.removeAll { $0.id == id }
    }

    private func tick() {
        let now = Date()
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.hour, .minute, .weekday, .day], from: now)
        guard let hour = parts.hour, let minute = parts.minute, let weekday = parts.weekday else { return }
        let isWeekday = (2...6).contains(weekday)
        let minuteKey = "\(parts.day ?? 0)-\(hour)-\(minute)"
        fired = fired.filter { $0.hasSuffix(minuteKey) }

        for action in actions where action.enabled {
            guard action.hour == hour, action.minute == minute else { continue }
            guard !action.weekdaysOnly || isWeekday else { continue }
            let fireKey = "\(action.id)-\(minuteKey)"
            guard !fired.contains(fireKey) else { continue }
            fired.insert(fireKey)
            TelegramBot.shared.notify("⏰ Scheduled: \(action.action.title) now.")
            if action.action != .stopAwake { AwakeManager.shared.enable() }
            PowerActions.perform(action.action)
        }
    }
}
