import Foundation

enum BotCommand: String, CaseIterable, Identifiable {
    case status, on, off, timer, cancel
    case displayoff, screensaver, lock, sleep, restart, shutdown
    case desktop, show
    case screenshot, info
    case apps, open, quit
    case terminal, term, run
    case find, get, openfile
    case help

    var id: String { rawValue }

    enum Group: String, CaseIterable, Identifiable {
        case awake = "Keep awake"
        case power = "Power and screen"
        case windows = "Desktop"
        case info = "Screen and info"
        case apps = "Apps"
        case shell = "Terminal and shell"
        case files = "Files"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .awake: return "cup.and.saucer"
            case .power: return "power"
            case .windows: return "macwindow.on.rectangle"
            case .info: return "camera.viewfinder"
            case .apps: return "square.grid.2x2"
            case .shell: return "terminal"
            case .files: return "folder"
            }
        }
    }

    var group: Group? {
        switch self {
        case .status, .on, .off, .timer, .cancel: return .awake
        case .displayoff, .screensaver, .lock, .sleep, .restart, .shutdown: return .power
        case .desktop, .show: return .windows
        case .screenshot, .info: return .info
        case .apps, .open, .quit: return .apps
        case .terminal, .term, .run: return .shell
        case .find, .get, .openfile: return .files
        case .help: return nil
        }
    }

    var usage: String {
        switch self {
        case .on: return "/on [time]"
        case .off: return "/off [time]"
        case .timer: return "/timer <time> <action>"
        case .open: return "/open [name or number]"
        case .quit: return "/quit [name or number]"
        case .term: return "/term <command>"
        case .run: return "/run <command>"
        case .find: return "/find <name>"
        case .get: return "/get <path or number>"
        case .openfile: return "/openfile <path or number>"
        default: return "/\(rawValue)"
        }
    }

    var summary: String {
        switch self {
        case .status: return "Current state"
        case .on: return "Keep awake, optionally for a while"
        case .off: return "Stop keeping awake, now or later"
        case .timer: return "Schedule an action"
        case .cancel: return "Cancel the running timer"
        case .displayoff: return "Turn the display off"
        case .screensaver: return "Start the screensaver"
        case .lock: return "Lock the screen"
        case .sleep: return "Sleep now"
        case .restart: return "Restart (asks first)"
        case .shutdown: return "Shut down (asks first)"
        case .desktop: return "Hide all apps and show the desktop"
        case .show: return "Bring hidden apps back"
        case .screenshot: return "Capture the screen"
        case .info: return "Battery and system info"
        case .apps: return "List running apps with quick quit links"
        case .open: return "List installed apps or launch one"
        case .quit: return "Quit an app"
        case .terminal: return "Open Terminal"
        case .term: return "Run in Terminal and send a screenshot"
        case .run: return "Run a shell command and get the output"
        case .find: return "Find files by name"
        case .get: return "Send a file to this chat"
        case .openfile: return "Open a file on the Mac"
        case .help: return "Show all commands"
        }
    }

    var enabledByDefault: Bool {
        switch self {
        case .run, .term, .find, .get, .openfile: return false
        default: return true
        }
    }

    var isSensitive: Bool {
        switch self {
        case .run, .term, .find, .get, .openfile, .screenshot: return true
        default: return false
        }
    }

    var isToggleable: Bool { self != .help }

    static func enabledCommands() -> [BotCommand] {
        allCases.filter { !$0.isToggleable || Preferences.shared.isEnabled($0) }
    }

    static func helpText() -> String {
        var lines = ["KeepMeUp commands"]
        for group in Group.allCases {
            let commands = enabledCommands().filter { $0.group == group }
            guard !commands.isEmpty else { continue }
            lines.append("")
            lines.append(group.rawValue)
            lines.append(contentsOf: commands.map { "\($0.usage) – \($0.summary)" })
        }
        lines.append("")
        lines.append("Times: 30m, 2h, 1h30m, 90s or 1:30")
        return lines.joined(separator: "\n")
    }
}
