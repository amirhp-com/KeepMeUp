import Foundation

final class ClaudeRemote {
    static let shared = ClaudeRemote()

    enum Access: String, CaseIterable, Identifiable {
        case ask = "default"
        case edits = "acceptEdits"
        case full = "bypassPermissions"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .ask: return "Read and answer only"
            case .edits: return "Can edit files"
            case .full: return "Can do anything"
            }
        }
    }

    struct Answer {
        let prompt: String
        let text: String
        let failed: Bool
        let seconds: Int
        let cost: Double?
        let finished: Date
    }

    private let lock = NSLock()
    private var process: Process?
    private var startedAt: Date?
    private var runningPrompt: String?
    private(set) var lastAnswer: Answer?

    private init() {}

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return process != nil
    }

    var runningFor: (prompt: String, seconds: Int)? {
        lock.lock()
        defer { lock.unlock() }
        guard process != nil, let startedAt, let runningPrompt else { return nil }
        return (runningPrompt, Int(Date().timeIntervalSince(startedAt)))
    }

    static func executable() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = ["\(home)/.local/bin/claude", "\(home)/.claude/local/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) { return found }
        let lookup = RemoteTools.shell("command -v claude", timeout: 10).output.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = lookup.split(separator: "\n").last.map(String.init) ?? ""
        return path.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    func ask(_ prompt: String, folder: URL, session: String?, access: Access) -> (Answer, String?) {
        let started = Date()
        guard let claude = Self.executable() else {
            let answer = Answer(prompt: prompt, text: "Claude Code isn't installed on this Mac, or KeepMeUp can't find it.", failed: true, seconds: 0, cost: nil, finished: Date())
            return (answer, session)
        }

        var arguments = ["-p", prompt, "--output-format", "json"]
        if access == .full {
            arguments.append("--dangerously-skip-permissions")
        } else {
            arguments += ["--permission-mode", access.rawValue]
        }
        if let session { arguments += ["--resume", session] }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claude)
        process.arguments = arguments
        process.currentDirectoryURL = folder
        var environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        environment["PATH"] = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = environment
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = FileHandle.nullDevice

        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        group.enter()
        DispatchQueue.global().async {
            outData = output.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        DispatchQueue.global().async {
            errData = errors.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        do {
            try process.run()
        } catch {
            let answer = Answer(prompt: prompt, text: error.localizedDescription, failed: true, seconds: 0, cost: nil, finished: Date())
            return (answer, session)
        }

        lock.lock()
        self.process = process
        self.startedAt = started
        self.runningPrompt = prompt
        lock.unlock()

        process.waitUntilExit()
        group.wait()

        lock.lock()
        self.process = nil
        self.startedAt = nil
        self.runningPrompt = nil
        lock.unlock()

        let seconds = Int(Date().timeIntervalSince(started))
        var newSession = session
        let answer: Answer
        if let json = try? JSONSerialization.jsonObject(with: outData) as? [String: Any] {
            newSession = (json["session_id"] as? String) ?? session
            let text = (json["result"] as? String) ?? ""
            let failed = (json["is_error"] as? Bool) ?? false
            answer = Answer(prompt: prompt, text: text.isEmpty ? "(no answer)" : text, failed: failed, seconds: seconds, cost: json["total_cost_usd"] as? Double, finished: Date())
        } else if process.terminationReason == .uncaughtSignal {
            answer = Answer(prompt: prompt, text: "Stopped.", failed: true, seconds: seconds, cost: nil, finished: Date())
        } else {
            let raw = String(decoding: outData + errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            answer = Answer(prompt: prompt, text: raw.isEmpty ? "Claude Code exited with code \(process.terminationStatus)." : raw, failed: true, seconds: seconds, cost: nil, finished: Date())
        }
        lock.lock()
        lastAnswer = answer
        lock.unlock()
        return (answer, newSession)
    }

    func stop() -> Bool {
        lock.lock()
        let running = process
        lock.unlock()
        guard let running, running.isRunning else { return false }
        running.interrupt()
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            if running.isRunning { running.terminate() }
        }
        return true
    }
}
