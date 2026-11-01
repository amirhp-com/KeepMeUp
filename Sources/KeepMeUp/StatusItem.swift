import AppKit
import Combine
import SwiftUI

final class MenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class BubbleHostingView: NSHostingView<MenuBubble> {
    var onResize: (() -> Void)?

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        DispatchQueue.main.async { [weak self] in self?.onResize?() }
    }
}

final class ArrowModel: ObservableObject {
    @Published var offset: CGFloat = 0
}

struct BubbleShape: Shape {
    var arrowOffset: CGFloat
    var arrowWidth: CGFloat = 24
    var arrowHeight: CGFloat = 10
    var radius: CGFloat = 16

    func path(in rect: CGRect) -> Path {
        let body = CGRect(x: rect.minX, y: rect.minY + arrowHeight, width: rect.width, height: rect.height - arrowHeight)
        let tipX = min(max(rect.midX + arrowOffset, body.minX + radius + arrowWidth / 2), body.maxX - radius - arrowWidth / 2)
        var path = Path()
        path.move(to: CGPoint(x: body.minX + radius, y: body.minY))
        path.addLine(to: CGPoint(x: tipX - arrowWidth / 2, y: body.minY))
        path.addQuadCurve(to: CGPoint(x: tipX, y: rect.minY), control: CGPoint(x: tipX - arrowWidth / 6, y: body.minY))
        path.addQuadCurve(to: CGPoint(x: tipX + arrowWidth / 2, y: body.minY), control: CGPoint(x: tipX + arrowWidth / 6, y: body.minY))
        path.addLine(to: CGPoint(x: body.maxX - radius, y: body.minY))
        path.addArc(center: CGPoint(x: body.maxX - radius, y: body.minY + radius), radius: radius, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: body.maxX, y: body.maxY - radius))
        path.addArc(center: CGPoint(x: body.maxX - radius, y: body.maxY - radius), radius: radius, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: body.minX + radius, y: body.maxY))
        path.addArc(center: CGPoint(x: body.minX + radius, y: body.maxY - radius), radius: radius, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: body.minX, y: body.minY + radius))
        path.addArc(center: CGPoint(x: body.minX + radius, y: body.minY + radius), radius: radius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}

struct MenuBubble: View {
    @ObservedObject var arrow: ArrowModel

    var body: some View {
        let shape = BubbleShape(arrowOffset: arrow.offset)
        MenuView()
            .padding(.top, 10)
            .background(VisualEffect().clipShape(shape))
            .overlay(shape.stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
            .padding(.horizontal, 12)
            .padding(.bottom, 20)
    }
}

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

final class StatusItem: NSObject, NSWindowDelegate {
    static let shared = StatusItem()

    private var item: NSStatusItem?
    private var panel: MenuPanel?
    private let arrow = ArrowModel()
    private var hosting: BubbleHostingView?
    private var monitor: Any?
    private var cancellable: AnyCancellable?

    var button: NSStatusBarButton? { item?.button }
    var isShown: Bool { panel?.isVisible ?? false }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.target = self
        item.button?.action = #selector(toggle)
        self.item = item

        let hosting = BubbleHostingView(rootView: MenuBubble(arrow: arrow))
        hosting.onResize = { [weak self] in self?.fitToContent() }
        let panel = MenuPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.delegate = self
        panel.contentView = hosting
        self.hosting = hosting
        self.panel = panel

        cancellable = AwakeManager.shared.$isActive
            .receive(on: RunLoop.main)
            .sink { [weak self] active in self?.updateIcon(active) }
    }

    private func updateIcon(_ active: Bool) {
        let image = NSImage(systemSymbolName: active ? "cup.and.saucer.fill" : "cup.and.saucer", accessibilityDescription: "KeepMeUp")
        image?.isTemplate = true
        item?.button?.image = image
    }

    @objc private func toggle() {
        isShown ? close() : show()
    }

    func show() {
        guard let panel, let hosting, let button = item?.button, let buttonWindow = button.window else { return }
        LaunchTip.close()
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.main
        let size = hosting.fittingSize
        let shadowInset: CGFloat = 12
        var x = anchor.midX - size.width / 2
        if let frame = screen?.visibleFrame {
            x = min(max(x, frame.minX + 4 - shadowInset), frame.maxX - size.width - 4 + shadowInset)
        }
        arrow.offset = anchor.midX - (x + size.width / 2)
        panel.setFrame(NSRect(x: x, y: anchor.minY - size.height - 2, width: size.width, height: size.height), display: true)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
        button.highlight(true)
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
    }

    private func fitToContent() {
        guard let panel, let hosting, panel.isVisible else { return }
        let size = hosting.fittingSize
        let frame = panel.frame
        guard abs(frame.height - size.height) > 0.5 else { return }
        panel.setFrame(NSRect(x: frame.minX, y: frame.maxY - size.height, width: frame.width, height: size.height), display: true)
    }

    func close() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        item?.button?.highlight(false)
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }
}
