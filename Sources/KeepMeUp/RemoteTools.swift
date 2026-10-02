import AppKit
import CoreServices
import Foundation

enum RemoteTools {
    struct ShellResult {
        let output: String
        let status: Int32
        let timedOut: Bool
    }

    static func shell(_ command: String, timeout: TimeInterval = 60) -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        var data = Data()
        let lock = NSLock()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            lock.lock()
            if data.count < 2_000_000 { data.append(chunk) }
            lock.unlock()
        }

        do {
            try process.run()
        } catch {
            return ShellResult(output: error.localizedDescription, status: -1, timedOut: false)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        let timedOut = process.isRunning
        if timedOut {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.5)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
        pipe.fileHandleForReading.readabilityHandler = nil
        let rest = pipe.fileHandleForReading.readDataToEndOfFile()
        lock.lock()
        data.append(rest)
        let output = String(decoding: data, as: UTF8.self)
        lock.unlock()
        return ShellResult(output: output, status: process.terminationStatus, timedOut: timedOut)
    }

    static func openTerminal() {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"), configuration: NSWorkspace.OpenConfiguration())
    }

    static func runInTerminal(_ command: String) -> String? {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            return error[NSAppleScript.errorMessage] as? String ?? "Terminal could not be controlled"
        }
        return nil
    }

    static func runningApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.localizedName != nil }
            .sorted { ($0.localizedName ?? "") .localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending }
    }

    struct InstalledApp {
        let name: String
        let url: URL
    }

    static func installedApps() -> [InstalledApp] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let roots = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities", "\(home)/Applications"]
        var seen = Set<String>()
        var apps: [InstalledApp] = []

        func collect(_ folder: String, depth: Int) {
            guard let items = try? fm.contentsOfDirectory(atPath: folder) else { return }
            for item in items where !item.hasPrefix(".") {
                let path = (folder as NSString).appendingPathComponent(item)
                if item.hasSuffix(".app") {
                    let name = String(item.dropLast(4))
                    if seen.insert(name.lowercased()).inserted {
                        apps.append(InstalledApp(name: name, url: URL(fileURLWithPath: path)))
                    }
                } else if depth > 0 {
                    var isFolder: ObjCBool = false
                    if fm.fileExists(atPath: path, isDirectory: &isFolder), isFolder.boolValue, !roots.contains(path) {
                        collect(path, depth: depth - 1)
                    }
                }
            }
        }

        for root in roots { collect(root, depth: 1) }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func open(_ app: InstalledApp) {
        NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration())
    }

    static func quit(pid: pid_t, force: Bool) -> String? {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return nil }
        let title = app.localizedName ?? "App"
        _ = force ? app.forceTerminate() : app.terminate()
        return title
    }

    static func findRunningApp(_ name: String) -> NSRunningApplication? {
        let query = name.lowercased()
        let apps = runningApps()
        return apps.first { $0.localizedName?.lowercased() == query }
            ?? apps.first { $0.bundleIdentifier?.lowercased() == query }
            ?? apps.first { $0.localizedName?.lowercased().contains(query) == true }
    }

    static func launchApp(_ name: String) -> Bool {
        let workspace = NSWorkspace.shared
        if let url = workspace.urlForApplication(withBundleIdentifier: name) {
            workspace.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return true
        }
        return PowerActions.run("/usr/bin/open", ["-a", name]) == 0
    }

    static func quitApp(_ name: String, force: Bool) -> String? {
        guard let app = findRunningApp(name) else { return nil }
        let title = app.localizedName ?? name
        _ = force ? app.forceTerminate() : app.terminate()
        return title
    }

    static func showDesktop() {
        let me = NSRunningApplication.current
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app != me {
            app.hide()
        }
    }

    static func showApps() {
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app.isHidden {
            app.unhide()
        }
    }

    static func expand(_ path: String) -> URL {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
    }

    enum Place: String {
        case home, desktop, documents, downloads

        var title: String {
            switch self {
            case .home: return "your home folder"
            case .desktop: return "Desktop"
            case .documents: return "Documents"
            case .downloads: return "Downloads"
            }
        }

        var url: URL {
            let fm = FileManager.default
            switch self {
            case .home: return fm.homeDirectoryForCurrentUser
            case .desktop: return fm.urls(for: .desktopDirectory, in: .userDomainMask)[0]
            case .documents: return fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            case .downloads: return fm.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            }
        }
    }

    static func find(_ name: String, in place: Place = .home, limit: Int = 20) -> [URL] {
        let result = shell("/usr/bin/mdfind -onlyin \(quoted(place.url.path)) -name \(quoted(name)) | head -n \(limit)", timeout: 30)
        return result.output
            .split(separator: "\n")
            .map { URL(fileURLWithPath: String($0)) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func latest(in place: Place, limit: Int = 20) -> [(URL, Date)] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .addedToDirectoryDateKey]
        guard let items = try? FileManager.default.contentsOfDirectory(at: place.url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return [] }
        let dated = items.map { url -> (URL, Date) in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return (url, values?.addedToDirectoryDate ?? values?.contentModificationDate ?? .distantPast)
        }
        return Array(dated.sorted { $0.1 > $1.1 }.prefix(limit))
    }

    static func recentFiles(days: Int, limit: Int = 25) -> [(URL, Date)] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let query = "kMDItemLastUsedDate >= $time.today(-\(days)) && kMDItemContentType != 'com.apple.application-bundle' && kMDItemContentType != 'public.folder'"
        let result = shell("/usr/bin/mdfind -onlyin \(quoted(home)) \(quoted(query))", timeout: 30)
        var items: [(URL, Date)] = []
        for line in result.output.split(separator: "\n") {
            let path = String(line)
            guard !path.contains("/Library/"), !path.contains("/."),
                  let item = MDItemCreate(kCFAllocatorDefault, path as CFString),
                  let date = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date else { continue }
            items.append((URL(fileURLWithPath: path), date))
        }
        return Array(items.sorted { $0.1 > $1.1 }.prefix(limit))
    }

    static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func fileSize(_ url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
    }

    static func zipFolder(_ url: URL) -> URL? {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("KeepMeUp", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let zip = folder.appendingPathComponent("\(url.lastPathComponent).zip")
        try? FileManager.default.removeItem(at: zip)
        let status = PowerActions.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", url.path, zip.path])
        return status == 0 ? zip : nil
    }
}
