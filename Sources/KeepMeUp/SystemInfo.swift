import AppKit
import Foundation
import IOKit.ps

enum SystemInfo {
    static func summary() -> String {
        var lines: [String] = []
        lines.append("💻 \(hostName())")
        lines.append("🖥 \(modelName()) · macOS \(osVersion())")
        lines.append("🔋 \(battery())")
        lines.append("⏱ Uptime: \(DurationText.describe(ProcessInfo.processInfo.systemUptime))")
        lines.append("⚙️ Load: \(loadAverage())")
        lines.append("🧠 Memory: \(memory())")
        lines.append("💾 Disk: \(disk())")
        return lines.joined(separator: "\n")
    }

    static func hostName() -> String {
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }

    static func osVersion() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    static func modelName() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        var arch = "Apple Silicon"
        #if arch(x86_64)
        arch = "Intel"
        #endif
        return "\(String(cString: buffer)) (\(arch))"
    }

    struct BatterySnapshot {
        let percent: Int?
        let plugged: Bool?
    }

    static func batterySnapshot() -> BatterySnapshot {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return BatterySnapshot(percent: nil, plugged: nil)
        }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let capacity = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = description[kIOPSMaxCapacityKey] as? Int ?? 100
            let percent = max > 0 ? capacity * 100 / max : capacity
            let plugged = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            return BatterySnapshot(percent: percent, plugged: plugged)
        }
        return BatterySnapshot(percent: nil, plugged: true)
    }

    static func battery() -> String {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return "Unavailable"
        }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let capacity = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = description[kIOPSMaxCapacityKey] as? Int ?? 100
            let percent = max > 0 ? capacity * 100 / max : capacity
            let state = description[kIOPSPowerSourceStateKey] as? String
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            var text = "\(percent)%"
            if charging {
                text += " · charging"
            } else if state == kIOPSACPowerValue {
                text += " · on power adapter"
            } else {
                text += " · on battery"
            }
            return text
        }
        return "No battery · on power adapter"
    }

    static func loadAverage() -> String {
        var loads = [Double](repeating: 0, count: 3)
        guard getloadavg(&loads, 3) == 3 else { return "Unavailable" }
        return loads.map { String(format: "%.2f", $0) }.joined(separator: " / ")
    }

    static func memory() -> String {
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return gigabytes(total) }
        let page = Double(vm_kernel_page_size)
        let used = Double(stats.active_count + stats.wire_count + stats.compressor_page_count) * page
        return "\(gigabytes(used)) of \(gigabytes(total))"
    }

    static func disk() -> String {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]),
              let free = values.volumeAvailableCapacityForImportantUsage,
              let total = values.volumeTotalCapacity else { return "Unavailable" }
        return "\(gigabytes(Double(free))) free of \(gigabytes(Double(total)))"
    }

    private static func gigabytes(_ bytes: Double) -> String {
        String(format: "%.1f GB", bytes / 1_073_741_824)
    }

    static func screenshots() -> [URL] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("KeepMeUp", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970)
        let count = max(NSScreen.screens.count, 1)
        let urls = (1...count).map { folder.appendingPathComponent("screen-\(stamp)-\($0).jpg") }
        PowerActions.run("/usr/sbin/screencapture", ["-x", "-t", "jpg"] + urls.map(\.path))
        return urls.filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}
