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
            if !Keychain.exists(TelegramBot.tokenAccount) {
                UserDefaults.standard.set(true, forKey: "tokenMigrated")
            } else if let legacy = Keychain.read(TelegramBot.tokenAccount), !legacy.isEmpty, write(legacy) {
                value = legacy
                UserDefaults.standard.set(true, forKey: "tokenMigrated")
                Keychain.delete(TelegramBot.tokenAccount)
            }
        }
        cached = value
        return value
    }

    static func save(_ value: String) {
        let token = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if write(token) {
            UserDefaults.standard.set(true, forKey: "tokenMigrated")
        }
        cached = token
    }

    @discardableResult
    private static func write(_ token: String) -> Bool {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        } catch {
            return false
        }
        if token.isEmpty {
            try? fm.removeItem(at: file)
            return true
        }
        let fd = open(file.path, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        guard fchmod(fd, 0o600) == 0 else { return false }
        let bytes = Array(token.utf8)
        return bytes.withUnsafeBytes { Foundation.write(fd, $0.baseAddress, $0.count) } == bytes.count
    }
}
