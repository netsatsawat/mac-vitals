import AppKit
import SwiftUI

/// Hosts the widget in a borderless, always-on-top panel that floats over other
/// apps, drags by its background, and remembers where it was left.
@MainActor
final class FloatingPanelController {
    private var panel: NSPanel?
    private var moveObserver: NSObjectProtocol?
    private let originKey = "widgetOrigin"

    var isVisible: Bool { panel != nil }

    func toggle(store: SampleStore) {
        if panel != nil { hide() } else { show(store: store) }
    }

    private func show(store: SampleStore) {
        let hosting = NSHostingView(rootView: WidgetView(store: store))
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 240),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = hosting

        let fit = hosting.fittingSize
        panel.setContentSize(fit == .zero ? NSSize(width: 300, height: 240) : fit)
        panel.setFrameOrigin(savedOrigin(for: panel))
        panel.orderFrontRegardless()

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let p = self.panel else { return }
                UserDefaults.standard.set(NSStringFromPoint(p.frame.origin), forKey: self.originKey)
            }
        }
        self.panel = panel
    }

    private func hide() {
        if let o = moveObserver { NotificationCenter.default.removeObserver(o); moveObserver = nil }
        panel?.orderOut(nil)
        panel = nil
    }

    /// The saved origin, or a resting spot below the menu bar on the right.
    private func savedOrigin(for panel: NSPanel) -> NSPoint {
        if let s = UserDefaults.standard.string(forKey: originKey) {
            let p = NSPointFromString(s)
            if p != .zero { return p }
        }
        guard let screen = NSScreen.main else { return NSPoint(x: 80, y: 80) }
        let vf = screen.visibleFrame
        return NSPoint(x: vf.maxX - panel.frame.width - 24,
                       y: vf.maxY - panel.frame.height - 12)
    }
}
