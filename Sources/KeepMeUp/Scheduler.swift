import Foundation

final class Scheduler: ObservableObject {
    static let shared = Scheduler()

    @Published private(set) var fireDate: Date?
    @Published private(set) var action: PowerAction?
    @Published private(set) var now = Date()

    private var timer: Timer?
    private var ticker: Timer?

    private init() {}

    var remaining: TimeInterval? {
        guard let fireDate else { return nil }
        return max(0, fireDate.timeIntervalSince(now))
    }

    func schedule(_ action: PowerAction, after interval: TimeInterval) {
        cancel()
        guard interval > 0 else { return }
        let date = Date().addingTimeInterval(interval)
        self.action = action
        fireDate = date
        now = Date()
        let fire = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in
            self?.fire()
        }
        RunLoop.main.add(fire, forMode: .common)
        timer = fire
        let tick = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.now = Date()
        }
        RunLoop.main.add(tick, forMode: .common)
        ticker = tick
    }

    func cancel() {
        timer?.invalidate()
        ticker?.invalidate()
        timer = nil
        ticker = nil
        fireDate = nil
        action = nil
    }

    private func fire() {
        guard let action else { return }
        cancel()
        PowerActions.perform(action)
    }
}

enum DurationText {
    static func parse(_ text: String) -> TimeInterval? {
        let input = text.lowercased().replacingOccurrences(of: " ", with: "")
        guard !input.isEmpty else { return nil }
        if let minutes = Double(input) { return minutes * 60 }
        if input.contains(":") {
            let parts = input.split(separator: ":").compactMap { Double($0) }
            guard parts.count == 2 else { return nil }
            return parts[0] * 3600 + parts[1] * 60
        }
        var total: TimeInterval = 0
        var number = ""
        var matched = false
        for char in input {
            if char.isNumber || char == "." {
                number.append(char)
                continue
            }
            guard let value = Double(number) else { return nil }
            switch char {
            case "h": total += value * 3600
            case "m": total += value * 60
            case "s": total += value
            case "d": total += value * 86400
            default: return nil
            }
            number = ""
            matched = true
        }
        if !number.isEmpty {
            guard let value = Double(number) else { return nil }
            total += value * 60
        }
        return matched || total > 0 ? total : nil
    }

    static func format(_ interval: TimeInterval) -> String {
        let seconds = Int(interval.rounded())
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    static func describe(_ interval: TimeInterval) -> String {
        let seconds = Int(interval.rounded())
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h)h") }
        if m > 0 { parts.append("\(m)m") }
        if parts.isEmpty { parts.append("\(seconds)s") }
        return parts.joined(separator: " ")
    }
}
