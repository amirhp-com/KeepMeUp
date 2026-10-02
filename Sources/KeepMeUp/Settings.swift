import Foundation

struct ChatInfo: Codable, Identifiable, Equatable {
    var id: Int64
    var type: String
    var title: String
    var username: String?

    var isPrivate: Bool { type == "private" }
    var isGroup: Bool { type == "group" || type == "supergroup" }

    var symbol: String {
        switch type {
        case "private": return "person.fill"
        case "group", "supergroup": return "person.3.fill"
        case "channel": return "megaphone.fill"
        default: return "questionmark.bubble.fill"
        }
    }

    var kind: String {
        switch type {
        case "private": return "Private chat"
        case "group": return "Group"
        case "supergroup": return "Supergroup"
        case "channel": return "Channel"
        default: return "Unknown chat"
        }
    }

    init(id: Int64, type: String = "unknown", title: String = "", username: String? = nil) {
        self.id = id
        self.type = type
        self.title = title
        self.username = username
    }

    init?(telegram chat: [String: Any]) {
        guard let id = (chat["id"] as? NSNumber)?.int64Value else { return nil }
        let type = chat["type"] as? String ?? "unknown"
        let name = [chat["first_name"], chat["last_name"]].compactMap { $0 as? String }.joined(separator: " ")
        let title = (chat["title"] as? String) ?? name
        self.init(
            id: id,
            type: type,
            title: String(title.filter { !$0.isNewline }.prefix(64)),
            username: (chat["username"] as? String).map { String($0.prefix(32)) }
        )
    }
}

final class Preferences: ObservableObject {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    @Published var restoreOnLaunch: Bool {
        didSet { defaults.set(restoreOnLaunch, forKey: "restoreOnLaunch") }
    }

    @Published var botEnabled: Bool {
        didSet { defaults.set(botEnabled, forKey: "botEnabled") }
    }

    @Published var allowedChats: [ChatInfo] {
        didSet {
            if let data = try? JSONEncoder().encode(allowedChats) {
                defaults.set(data, forKey: "allowedChats")
            }
        }
    }

    @Published var commandOverrides: [String: Bool] {
        didSet { defaults.set(commandOverrides, forKey: "commandOverrides") }
    }

    var allowedChatIDs: [Int64] { allowedChats.map(\.id) }

    func isAllowed(_ id: Int64) -> Bool {
        allowedChats.contains { $0.id == id }
    }

    func isPairedUser(_ id: Int64) -> Bool {
        allowedChats.contains { $0.id == id && $0.isPrivate }
    }

    func upsert(_ chat: ChatInfo) {
        if let index = allowedChats.firstIndex(where: { $0.id == chat.id }) {
            allowedChats[index] = chat
        } else {
            allowedChats.append(chat)
        }
    }

    func isEnabled(_ command: BotCommand) -> Bool {
        commandOverrides[command.rawValue] ?? command.enabledByDefault
    }

    func setEnabled(_ command: BotCommand, _ value: Bool) {
        commandOverrides[command.rawValue] = value
    }

    var lastActive: Bool {
        get { defaults.bool(forKey: "lastActive") }
        set { defaults.set(newValue, forKey: "lastActive") }
    }

    private init() {
        restoreOnLaunch = defaults.object(forKey: "restoreOnLaunch") as? Bool ?? true
        botEnabled = defaults.bool(forKey: "botEnabled")
        commandOverrides = defaults.dictionary(forKey: "commandOverrides") as? [String: Bool] ?? [:]
        if let data = defaults.data(forKey: "allowedChats"),
           let chats = try? JSONDecoder().decode([ChatInfo].self, from: data) {
            allowedChats = chats
        } else {
            let legacy = (defaults.array(forKey: "allowedChatIDs") as? [NSNumber])?.map { $0.int64Value } ?? []
            allowedChats = legacy.map { ChatInfo(id: $0, type: $0 > 0 ? "private" : "unknown") }
        }
    }
}
