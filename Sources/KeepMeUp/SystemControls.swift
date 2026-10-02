import AppKit
import CoreGraphics
import Foundation

enum SystemControls {
    static func outputVolume() -> Int {
        let result = RemoteTools.shell("osascript -e 'output volume of (get volume settings)'", timeout: 5)
        return Int(result.output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    static func isMuted() -> Bool {
        let result = RemoteTools.shell("osascript -e 'output muted of (get volume settings)'", timeout: 5)
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    static func setVolume(_ value: Int) {
        let clamped = max(0, min(100, value))
        PowerActions.run("/usr/bin/osascript", ["-e", "set volume output volume \(clamped)"])
    }

    static func setMuted(_ muted: Bool) {
        PowerActions.run("/usr/bin/osascript", ["-e", "set volume output muted \(muted)"])
    }

    enum MediaKey: Int32 {
        case playPause = 16
        case next = 17
        case previous = 18
    }

    static func pressMediaKey(_ key: MediaKey) {
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = Int((key.rawValue << 16) | ((down ? 0xA : 0xB) << 8))
            if let event = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1) {
                event.cgEvent?.post(tap: .cghidEventTap)
            }
        }
    }

    static func brightness() -> Int? {
        guard let get = displayServices("DisplayServicesGetBrightness") else { return nil }
        typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
        let fn = unsafeBitCast(get, to: GetFn.self)
        var level: Float = 0
        guard fn(CGMainDisplayID(), &level) == 0 else { return nil }
        return Int((level * 100).rounded())
    }

    @discardableResult
    static func setBrightness(_ value: Int) -> Bool {
        guard let set = displayServices("DisplayServicesSetBrightness") else { return false }
        typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
        let fn = unsafeBitCast(set, to: SetFn.self)
        let level = Float(max(0, min(100, value))) / 100
        return fn(CGMainDisplayID(), level) == 0
    }

    private static func displayServices(_ symbol: String) -> UnsafeMutableRawPointer? {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let handle = dlopen(path, RTLD_LAZY) else { return nil }
        return dlsym(handle, symbol)
    }

    static func readClipboard() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    static func writeClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    static func notify(_ text: String) {
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        PowerActions.run("/usr/bin/osascript", ["-e", "display notification \"\(escaped)\" with title \"KeepMeUp\""])
    }

    static func speak(_ text: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = [text]
        try? process.run()
    }

    static func wifi() -> String {
        let script = "/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I 2>/dev/null"
        let result = RemoteTools.shell(script, timeout: 6)
        var values: [String: String] = [:]
        for line in result.output.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            values[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1].trimmingCharacters(in: .whitespaces)
        }
        if let ssid = values["SSID"], !ssid.isEmpty {
            var line = "📶 \(ssid)"
            if let rssi = values["agrCtlRSSI"] { line += " · \(rssi) dBm" }
            if let rate = values["lastTxRate"] { line += " · \(rate) Mbps" }
            return line
        }
        let fallback = RemoteTools.shell("networksetup -getairportnetwork en0", timeout: 6).output
        let name = fallback.components(separatedBy: ": ").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !name.isEmpty, !name.contains("not associated") { return "📶 \(name)" }
        let hasAddress = localIPs().contains { $0.hasPrefix("en0:") }
        return hasAddress ? "📶 Connected to Wi-Fi (macOS hides the network name from apps without Location access)" : "📶 Not connected to Wi-Fi"
    }

    static func localIPs() -> [String] {
        var addresses: [String] = []
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return [] }
        defer { freeifaddrs(pointer) }
        var node = first as UnsafeMutablePointer<ifaddrs>?
        while let current = node {
            let flags = Int32(current.pointee.ifa_flags)
            let family = current.pointee.ifa_addr.pointee.sa_family
            if (flags & IFF_UP) == IFF_UP, (flags & IFF_LOOPBACK) == 0, family == UInt8(AF_INET) {
                let name = String(cString: current.pointee.ifa_name)
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(current.pointee.ifa_addr, socklen_t(current.pointee.ifa_addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    addresses.append("\(name): \(String(cString: host))")
                }
            }
            node = current.pointee.ifa_next
        }
        return addresses
    }

    static func publicIP() async -> String? {
        guard let url = URL(string: "https://api.ipify.org") else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
