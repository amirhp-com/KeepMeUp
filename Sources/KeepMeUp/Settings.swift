import Foundation

final class Preferences: ObservableObject {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    @Published var restoreOnLaunch: Bool {
        didSet { defaults.set(restoreOnLaunch, forKey: "restoreOnLaunch") }
    }

    @Published var botEnabled: Bool {
        didSet { defaults.set(botEnabled, forKey: "botEnabled") }
    }

    @Published var allowedChatIDs: [Int64] {
        didSet { defaults.set(allowedChatIDs.map { NSNumber(value: $0) }, forKey: "allowedChatIDs") }
    }

    var lastActive: Bool {
        get { defaults.bool(forKey: "lastActive") }
        set { defaults.set(newValue, forKey: "lastActive") }
    }

    private init() {
        restoreOnLaunch = defaults.object(forKey: "restoreOnLaunch") as? Bool ?? true
        botEnabled = defaults.bool(forKey: "botEnabled")
        allowedChatIDs = (defaults.array(forKey: "allowedChatIDs") as? [NSNumber])?.map { $0.int64Value } ?? []
    }
}
