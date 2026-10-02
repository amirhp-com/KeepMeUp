import AppKit
import Foundation

enum PowerAction: String, CaseIterable, Identifiable, Codable {
    case stopAwake
    case displayOff
    case screensaver
    case lock
    case sleep
    case restart
    case shutdown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stopAwake: return "Stop keeping awake"
        case .displayOff: return "Turn display off"
        case .screensaver: return "Start screensaver"
        case .lock: return "Lock screen"
        case .sleep: return "Sleep"
        case .restart: return "Restart"
        case .shutdown: return "Shut down"
        }
    }

    var symbol: String {
        switch self {
        case .stopAwake: return "cup.and.saucer"
        case .displayOff: return "display"
        case .screensaver: return "sparkles.tv"
        case .lock: return "lock"
        case .sleep: return "moon.zzz"
        case .restart: return "arrow.clockwise"
        case .shutdown: return "power"
        }
    }

    var keyword: String {
        switch self {
        case .stopAwake: return "off"
        case .displayOff: return "displayoff"
        case .screensaver: return "screensaver"
        case .lock: return "lock"
        case .sleep: return "sleep"
        case .restart: return "restart"
        case .shutdown: return "shutdown"
        }
    }

    static func from(keyword: String) -> PowerAction? {
        let key = keyword.lowercased()
        let aliases: [String: PowerAction] = ["display": .displayOff, "screen": .displayOff, "saver": .screensaver, "reboot": .restart, "poweroff": .shutdown, "stop": .stopAwake]
        return allCases.first { $0.keyword == key } ?? aliases[key]
    }
}

enum PowerActions {
    static func perform(_ action: PowerAction) {
        switch action {
        case .stopAwake:
            AwakeManager.shared.disable()
        case .displayOff:
            run("/usr/bin/pmset", ["displaysleepnow"])
        case .screensaver:
            run("/usr/bin/open", ["-b", "com.apple.ScreenSaver.Engine"])
        case .lock:
            lockScreen()
        case .sleep:
            AwakeManager.shared.disable()
            run("/usr/bin/pmset", ["sleepnow"])
        case .restart:
            AwakeManager.shared.disable()
            appleScript("tell application \"System Events\" to restart")
        case .shutdown:
            AwakeManager.shared.disable()
            appleScript("tell application \"System Events\" to shut down")
        }
    }

    private static func lockScreen() {
        typealias LockFunction = @convention(c) () -> Int32
        let path = "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login"
        if let handle = dlopen(path, RTLD_LAZY), let symbol = dlsym(handle, "SACLockScreenImmediate") {
            let lock = unsafeBitCast(symbol, to: LockFunction.self)
            _ = lock()
            return
        }
        run("/usr/bin/pmset", ["displaysleepnow"])
    }

    private static func appleScript(_ source: String) {
        DispatchQueue.main.async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            if error != nil {
                run("/usr/bin/osascript", ["-e", source])
            }
        }
    }

    @discardableResult
    static func run(_ launchPath: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}
