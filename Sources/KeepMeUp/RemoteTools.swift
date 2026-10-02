import AppKit
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

    static func find(_ name: String, limit: Int = 20) -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let result = shell("/usr/bin/mdfind -onlyin \(quoted(home)) -name \(quoted(name)) | head -n \(limit)", timeout: 30)
        return result.output
            .split(separator: "\n")
            .map { URL(fileURLWithPath: String($0)) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
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
