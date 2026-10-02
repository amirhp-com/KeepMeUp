import Foundation

enum BotCommand: String, CaseIterable, Identifiable {
    case status, on, off, timer, cancel
    case displayoff, screensaver, lock, sleep, restart, shutdown, brightness
    case desktop, show
    case screenshot, info
    case apps, open, quit
    case volume, mute, play, next, previous
    case say, notify, clip
    case wifi, ip
    case terminal, term, run
    case find, desk, docs, dl, recent, get, openfile
    case help

    var id: String { rawValue }

    enum Group: String, CaseIterable, Identifiable {
        case awake = "Keep awake"
        case power = "Power and screen"
        case windows = "Desktop"
        case info = "Screen and info"
        case apps = "Apps"
        case sound = "Sound and media"
        case system = "System"
        case network = "Network"
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
            case .sound: return "speaker.wave.2"
            case .system: return "bubble.left.and.text.bubble.right"
            case .network: return "wifi"
            case .shell: return "terminal"
            case .files: return "folder"
            }
        }
    }

    var group: Group? {
        switch self {
        case .status, .on, .off, .timer, .cancel: return .awake
        case .displayoff, .screensaver, .lock, .sleep, .restart, .shutdown, .brightness: return .power
        case .desktop, .show: return .windows
        case .screenshot, .info: return .info
        case .apps, .open, .quit: return .apps
        case .volume, .mute, .play, .next, .previous: return .sound
        case .say, .notify, .clip: return .system
        case .wifi, .ip: return .network
        case .terminal, .term, .run: return .shell
        case .find, .desk, .docs, .dl, .recent, .get, .openfile: return .files
        case .help: return nil
        }
    }

    var usage: String {
        switch self {
        case .on: return "/on [time]"
        case .off: return "/off [time]"
        case .timer: return "/timer <time> <action>"
        case .brightness: return "/brightness [0-100]"
        case .open: return "/open [name or number]"
        case .quit: return "/quit [name or number]"
        case .volume: return "/volume [0-100]"
        case .say: return "/say <text>"
        case .notify: return "/notify <text>"
        case .clip: return "/clip [text]"
        case .term: return "/term <command>"
        case .run: return "/run <command>"
        case .find: return "/find <name>"
        case .desk: return "/desk [name]"
        case .docs: return "/docs [name]"
        case .dl: return "/dl [name]"
        case .recent: return "/recent [days]"
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
        case .brightness: return "Show or set display brightness"
        case .desktop: return "Hide all apps and show the desktop"
        case .show: return "Bring hidden apps back"
        case .screenshot: return "Capture the screen"
        case .info: return "Battery and system info"
        case .apps: return "List running apps with quick quit links"
        case .open: return "List installed apps or launch one"
        case .quit: return "Quit an app"
        case .volume: return "Show or set the output volume"
        case .mute: return "Mute or unmute the output"
        case .play: return "Play or pause the current media"
        case .next: return "Skip to the next track"
        case .previous: return "Go to the previous track"
        case .say: return "Speak text out loud on the Mac"
        case .notify: return "Show a notification on the Mac"
        case .clip: return "Read the clipboard, or set it"
        case .wifi: return "Wi-Fi network and signal"
        case .ip: return "Local and public IP addresses"
        case .terminal: return "Open Terminal"
        case .term: return "Run in Terminal and send a screenshot"
        case .run: return "Run a shell command and get the output"
        case .find: return "Find files anywhere in your home folder"
        case .desk: return "Search Desktop, or list its newest items"
        case .docs: return "Search Documents, or list its newest items"
        case .dl: return "Search Downloads, or list its newest items"
        case .recent: return "Files you opened recently (Finder Recents)"
        case .get: return "Send a file to this chat"
        case .openfile: return "Open a file on the Mac"
        case .help: return "Show all commands"
        }
    }

    var enabledByDefault: Bool { !isSensitive }

    var isSensitive: Bool {
        switch self {
        case .run, .term, .find, .desk, .docs, .dl, .recent, .get, .openfile, .screenshot, .clip: return true
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
