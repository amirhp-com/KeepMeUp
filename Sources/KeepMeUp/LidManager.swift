import Foundation
import IOKit.ps

final class LidManager: ObservableObject {
    static let shared = LidManager()

    @Published private(set) var helperInstalled = false
    @Published private(set) var sleepDisabled = false
    @Published private(set) var lastError: String?

    private let sudoersPath = "/etc/sudoers.d/keepmeup"
    private let pmset = "/usr/bin/pmset"
    private var runLoopSource: CFRunLoopSource?

    private init() {
        helperInstalled = FileManager.default.fileExists(atPath: sudoersPath)
    }

    func start() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<LidManager>.fromOpaque(context).takeUnretainedValue().apply()
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = source
        }
        apply()
    }

    func setEnabled(_ enabled: Bool) {
        if enabled && !helperInstalled {
            installHelper { [weak self] ok in
                guard let self else { return }
                Preferences.shared.lidAwakeOnPower = ok
                self.apply()
            }
            return
        }
        Preferences.shared.lidAwakeOnPower = enabled
        apply()
    }

    func apply() {
        let plugged = SystemInfo.batterySnapshot().plugged ?? false
        let want = Preferences.shared.lidAwakeOnPower && plugged
        setSleepDisabled(want)
    }

    func restoreOnQuit() {
        if sleepDisabled { setSleepDisabled(false) }
    }

    private func setSleepDisabled(_ value: Bool) {
        let current = Self.readSleepDisabled()
        guard current != value else {
            sleepDisabled = current
            return
        }
        guard helperInstalled else {
            sleepDisabled = current
            return
        }
        let status = PowerActions.run("/usr/bin/sudo", ["-n", pmset, "-a", "disablesleep", value ? "1" : "0"])
        sleepDisabled = Self.readSleepDisabled()
        lastError = status == 0 ? nil : "Couldn't change the sleep setting. Turn the option off and on to set it up again."
        if status != 0 {
            helperInstalled = FileManager.default.fileExists(atPath: sudoersPath)
        }
    }

    private func installHelper(completion: @escaping (Bool) -> Void) {
        let user = NSUserName()
        guard user.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else {
            lastError = "Your user name can't be used for this setup."
            completion(false)
            return
        }
        let rule = "\(user) ALL=(root) NOPASSWD: \(pmset) -a disablesleep 0, \(pmset) -a disablesleep 1"
        let temp = "/tmp/keepmeup-sudoers-\(UUID().uuidString)"
        let script = "/bin/echo '\(rule)' > \(temp) && /usr/sbin/visudo -cf \(temp) && /usr/sbin/chown root:wheel \(temp) && /bin/chmod 0440 \(temp) && /bin/mv \(temp) \(sudoersPath)"
        let source = "do shell script \"\(script)\" with prompt \"KeepMeUp needs your password once to let your Mac stay awake with the lid closed while charging.\" with administrator privileges"
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            let ok = error == nil && FileManager.default.fileExists(atPath: self.sudoersPath)
            DispatchQueue.main.async {
                self.helperInstalled = ok
                if !ok {
                    let cancelled = (error?[NSAppleScript.errorNumber] as? Int) == -128
                    self.lastError = cancelled ? nil : "Setup failed. Try again."
                }
                completion(ok)
            }
        }
    }

    func removeHelper() {
        setSleepDisabled(false)
        Preferences.shared.lidAwakeOnPower = false
        let source = "do shell script \"/bin/rm -f \(sudoersPath)\" with administrator privileges"
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            DispatchQueue.main.async {
                self.helperInstalled = FileManager.default.fileExists(atPath: self.sudoersPath)
            }
        }
    }

    private static func readSleepDisabled() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(decoding: data, as: UTF8.self)
            for line in text.split(separator: "\n") {
                let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                if parts.first == "SleepDisabled" { return parts.last == "1" }
            }
        } catch {}
        return false
    }
}
