import AppKit
import SwiftUI

enum LaunchTip {
    private static var popover: NSPopover?
    private static var dismissTimer: Timer?

    static func show(attempt: Int = 0) {
        guard let button = statusButton() else {
            if attempt < 10 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { show(attempt: attempt + 1) }
            }
            return
        }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: LaunchTipView { close() })
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        self.popover = popover
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { _ in close() }
    }

    static func close() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        popover?.performClose(nil)
        popover = nil
    }

    private static func statusButton() -> NSView? {
        for window in NSApp.windows where String(describing: type(of: window)).contains("StatusBarWindow") {
            if let button = find(NSStatusBarButton.self, in: window.contentView) {
                return button
            }
        }
        return nil
    }

    private static func find<T: NSView>(_ type: T.Type, in view: NSView?) -> T? {
        guard let view else { return nil }
        if let match = view as? T { return match }
        for child in view.subviews {
            if let match = find(type, in: child) { return match }
        }
        return nil
    }
}

struct LaunchTipView: View {
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.up")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(LinearGradient(colors: [Color(red: 0.31, green: 0.27, blue: 0.9), Color(red: 0.13, green: 0.83, blue: 0.93)], startPoint: .topLeading, endPoint: .bottomTrailing)))
            VStack(alignment: .leading, spacing: 3) {
                Text("KeepMeUp is running here")
                    .font(.system(size: 13, weight: .semibold))
                Text("Click the cup in the menu bar to keep your Mac awake, set a timer or open Settings.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(14)
        .frame(width: 290)
        .noFocusRing()
    }
}
