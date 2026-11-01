import AppKit
import Foundation

enum TerminalRemote {
    struct TabInfo {
        let windowID: Int
        let tabIndex: Int
        let tty: String
        let title: String
        let windowName: String
        let processes: [String]
        let busy: Bool
        let selected: Bool

        var label: String {
            let program = processes.first ?? "shell"
            let name = title.isEmpty ? windowName : title
            return name.isEmpty ? program : "\(name) · \(program)"
        }
    }

    enum Failure: Error {
        case message(String)

        var text: String {
            switch self {
            case .message(let text): return text
            }
        }
    }

    private static let separator = "\u{1F}"

    @MainActor
    static func tabs() -> Result<[TabInfo], Failure> {
        let source = """
        set sep to (ASCII character 31)
        set rows to {}
        tell application "Terminal"
            repeat with w in windows
                try
                    set wid to id of w
                    set wname to name of w
                    set tabCount to count of tabs of w
                    repeat with i from 1 to tabCount
                        set t to tab i of w
                        set AppleScript's text item delimiters to ","
                        set procs to (processes of t) as text
                        set AppleScript's text item delimiters to ""
                        set ctitle to ""
                        try
                            set ctitle to custom title of t
                        end try
                        set end of rows to (wid as text) & sep & i & sep & (tty of t) & sep & ctitle & sep & wname & sep & procs & sep & (busy of t) & sep & (selected of t)
                    end repeat
                end try
            end repeat
        end tell
        set AppleScript's text item delimiters to linefeed
        return rows as text
        """
        switch run(source) {
        case .failure(let error):
            return .failure(error)
        case .success(let text):
            let tabs = text.split(separator: "\n").compactMap { line -> TabInfo? in
                let parts = line.components(separatedBy: separator)
                guard parts.count >= 8, let wid = Int(parts[0]), let index = Int(parts[1]) else { return nil }
                return TabInfo(
                    windowID: wid,
                    tabIndex: index,
                    tty: parts[2],
                    title: parts[3],
                    windowName: parts[4],
                    processes: parts[5].split(separator: ",").map { String($0) }.filter { !$0.hasPrefix("-") && $0 != "login" },
                    busy: parts[6] == "true",
                    selected: parts[7] == "true"
                )
            }
            return .success(tabs)
        }
    }

    @MainActor
    static func frontTab() -> TabInfo? {
        guard case .success(let tabs) = tabs() else { return nil }
        let front = runString("tell application \"Terminal\" to get id of front window").flatMap(Int.init)
        return tabs.first { $0.windowID == front && $0.selected } ?? tabs.first { $0.selected }
    }

    @MainActor
    static func find(tty: String) -> TabInfo? {
        guard case .success(let tabs) = tabs() else { return nil }
        return tabs.first { $0.tty == tty }
    }

    @MainActor
    static func select(_ tab: TabInfo) -> Failure? {
        let source = """
        tell application "Terminal"
            set w to window id \(tab.windowID)
            set selected of tab \(tab.tabIndex) of w to true
            set index of w to 1
            activate
        end tell
        """
        if case .failure(let error) = run(source) { return error }
        return nil
    }

    @MainActor
    static func send(_ text: String, to tab: TabInfo) -> Failure? {
        sendRaw("\"\(escape(text))\"", to: tab)
    }

    @MainActor
    static func pick(option: Int, in tab: TabInfo) -> Failure? {
        let downs = max(0, option - 1)
        let expression = downs == 0 ? "\"\"" : Array(repeating: "((ASCII character 27) & \"[B\")", count: downs).joined(separator: " & ")
        return sendRaw(expression, to: tab)
    }

    @MainActor
    static func interrupt(_ tab: TabInfo) -> Failure? {
        sendRaw("(ASCII character 3)", to: tab)
    }

    @MainActor
    static func contents(of tab: TabInfo, lines: Int) -> String? {
        let source = "tell application \"Terminal\" to get contents of tab \(tab.tabIndex) of window id \(tab.windowID)"
        guard let text = runString(source) else { return nil }
        let rows = text.components(separatedBy: "\n")
            .map { $0.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) }
        var trimmed = Array(rows.drop { $0.isEmpty })
        while trimmed.last?.isEmpty == true { trimmed.removeLast() }
        return trimmed.suffix(lines).joined(separator: "\n")
    }

    static func screenshot(of tab: TabInfo) -> URL? {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("KeepMeUp", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("terminal-\(Int(Date().timeIntervalSince1970)).jpg")
        PowerActions.run("/usr/sbin/screencapture", ["-x", "-o", "-t", "jpg", "-l\(tab.windowID)", url.path])
        guard RemoteTools.fileSize(url) > 0 else { return nil }
        return url
    }

    @MainActor
    private static func sendRaw(_ expression: String, to tab: TabInfo) -> Failure? {
        let source = "tell application \"Terminal\" to do script \(expression) in tab \(tab.tabIndex) of window id \(tab.windowID)"
        if case .failure(let error) = run(source) { return error }
        return nil
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    @MainActor
    private static func runString(_ source: String) -> String? {
        if case .success(let text) = run(source) { return text }
        return nil
    }

    @MainActor
    private static func run(_ source: String) -> Result<String, Failure> {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            let message = error[NSAppleScript.errorMessage] as? String ?? "Terminal could not be controlled"
            return .failure(.message(message))
        }
        return .success(result?.stringValue ?? "")
    }
}
