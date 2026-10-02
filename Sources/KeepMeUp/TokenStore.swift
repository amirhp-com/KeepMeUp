import Foundation

enum TokenStore {
    private static var cached: String?

    private static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("KeepMeUp", isDirectory: true)
    }

    private static var file: URL { folder.appendingPathComponent("bot-token") }

    static func read() -> String {
        if let cached { return cached }
        var value = (try? String(contentsOf: file, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if value.isEmpty, !UserDefaults.standard.bool(forKey: "tokenMigrated") {
            UserDefaults.standard.set(true, forKey: "tokenMigrated")
            if let legacy = Keychain.read(TelegramBot.tokenAccount), !legacy.isEmpty {
                value = legacy
                write(legacy)
                Keychain.delete(TelegramBot.tokenAccount)
            }
        }
        cached = value
        return value
    }

    static func save(_ value: String) {
        let token = value.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(true, forKey: "tokenMigrated")
        write(token)
        cached = token
    }

    private static func write(_ token: String) {
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if token.isEmpty {
            try? fm.removeItem(at: file)
            return
        }
        fm.createFile(atPath: file.path, contents: Data(token.utf8), attributes: [.posixPermissions: 0o600])
    }
}
