import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics
import Foundation

enum PermissionState {
    case granted
    case denied
    case unknown

    var label: String {
        switch self {
        case .granted: return "Allowed"
        case .denied: return "Not allowed"
        case .unknown: return "Not set up"
        }
    }
}

enum AppPermission: String, CaseIterable, Identifiable {
    case screenRecording
    case camera
    case automation
    case files

    var id: String { rawValue }

    var title: String {
        switch self {
        case .screenRecording: return "Screen Recording"
        case .camera: return "Camera"
        case .automation: return "Automation"
        case .files: return "Files & Folders"
        }
    }

    var detail: String {
        switch self {
        case .screenRecording: return "For /screenshot and /term"
        case .camera: return "For /webcam"
        case .automation: return "For restart, shut down and /term"
        case .files: return "For /find, /get and folder search"
        }
    }

    var symbol: String {
        switch self {
        case .screenRecording: return "rectangle.inset.filled.badge.record"
        case .camera: return "camera"
        case .automation: return "gearshape.2"
        case .files: return "folder"
        }
    }

    private var settingsURL: URL {
        let anchor: String
        switch self {
        case .screenRecording: anchor = "Privacy_ScreenCapture"
        case .camera: anchor = "Privacy_Camera"
        case .automation: anchor = "Privacy_Automation"
        case .files: anchor = "Privacy_FilesAndFolders"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
    }

    func openSettings() {
        NSWorkspace.shared.open(settingsURL)
    }
}

final class Permissions: ObservableObject {
    static let shared = Permissions()

    @Published private(set) var states: [AppPermission: PermissionState] = [:]

    private init() { refresh() }

    func state(_ permission: AppPermission) -> PermissionState {
        states[permission] ?? .unknown
    }

    func refresh() {
        DispatchQueue.global(qos: .userInitiated).async {
            var result: [AppPermission: PermissionState] = [:]
            result[.screenRecording] = CGPreflightScreenCaptureAccess() ? .granted : .denied
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: result[.camera] = .granted
            case .denied, .restricted: result[.camera] = .denied
            default: result[.camera] = .unknown
            }
            result[.automation] = self.automationState()
            result[.files] = self.filesState()
            DispatchQueue.main.async { self.states = result }
        }
    }

    func request(_ permission: AppPermission) {
        switch permission {
        case .screenRecording:
            if !CGRequestScreenCaptureAccess() { permission.openSettings() }
            finish(after: 1)
        case .camera:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if !granted { DispatchQueue.main.async { permission.openSettings() } }
                self.finish()
            }
        case .automation:
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                NSAppleScript(source: "tell application \"System Events\" to get name of current user")?.executeAndReturnError(&error)
                if error != nil { DispatchQueue.main.async { permission.openSettings() } }
                self.finish()
            }
        case .files:
            DispatchQueue.global(qos: .userInitiated).async {
                let fm = FileManager.default
                for folder: FileManager.SearchPathDirectory in [.desktopDirectory, .documentDirectory, .downloadsDirectory] {
                    if let url = fm.urls(for: folder, in: .userDomainMask).first {
                        _ = try? fm.contentsOfDirectory(atPath: url.path)
                    }
                }
                self.finish()
            }
        }
    }

    private func finish(after seconds: Double = 0.4) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { self.refresh() }
    }

    private func automationState() -> PermissionState {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.systemevents")
        guard let desc = target.aeDesc else { return .unknown }
        let status = AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, false)
        switch status {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        default: return .unknown
        }
    }

    private func filesState() -> PermissionState {
        let fm = FileManager.default
        guard let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return .unknown }
        return (try? fm.contentsOfDirectory(atPath: downloads.path)) != nil ? .granted : .unknown
    }
}
