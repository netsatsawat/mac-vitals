import SwiftUI
import VitalsCore

@main
struct MacVitalsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = SampleStore()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(
                store: store,
                onToggleWidget: { delegate.panel.toggle(store: store) },
                onQuit: { NSApp.terminate(nil) }
            )
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)

        Window("Mac Vitals", id: "main") {
            MainView(store: store)
        }
        .defaultSize(width: 840, height: 620)
        .windowResizability(.contentMinSize)
    }
}

/// Runs the app as a menu-bar accessory: no Dock icon, no main window.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let panel = FloatingPanelController()
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let args = CommandLine.arguments

        // Diagnostics for the Launch at Login path, so registration can be
        // verified from the command line under the app's real bundle identity.
        if args.contains("--login-status") {
            print("login-item status: \(LoginItem.statusText)")
            NSApp.terminate(nil)
        }
        if args.contains("--login-register") {
            let ok = LoginItem.setEnabled(true)
            print("register accepted: \(ok) · status now: \(LoginItem.statusText)")
            NSApp.terminate(nil)
        }
        if args.contains("--login-unregister") {
            let ok = LoginItem.setEnabled(false)
            print("unregister accepted: \(ok) · status now: \(LoginItem.statusText)")
            NSApp.terminate(nil)
        }
        if let i = args.firstIndex(of: "--render-menubar"), i + 1 < args.count {
            RenderTool.renderMenuBar(to: args[i + 1])
            NSApp.terminate(nil)
        }
        if let i = args.firstIndex(of: "--render-popover"), i + 1 < args.count {
            RenderTool.renderPopover(to: args[i + 1])
            NSApp.terminate(nil)
        }
        if let i = args.firstIndex(of: "--render24"), i + 1 < args.count {
            RenderTool.renderMainWindow(to: args[i + 1], range: .h24)
            NSApp.terminate(nil)
        }
        if let i = args.firstIndex(of: "--render-long"), i + 1 < args.count {
            RenderTool.renderMainWindow(to: args[i + 1], range: .d365)
            NSApp.terminate(nil)
        }
        if let i = args.firstIndex(of: "--render-sparse"), i + 1 < args.count {
            RenderTool.renderSparse(to: args[i + 1])
            NSApp.terminate(nil)
        }
        if let i = args.firstIndex(of: "--render"), i + 1 < args.count {
            RenderTool.renderMainWindow(to: args[i + 1])
            NSApp.terminate(nil)
        }

        // Drop back to a menu-bar accessory (no Dock icon) once the full window closes.
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { note in
            MainActor.assumeIsolated {
                guard let closing = note.object as? NSWindow,
                      closing.title == "Mac Vitals", !(closing is NSPanel) else { return }
                DispatchQueue.main.async {
                    let stillOpen = NSApp.windows.contains {
                        $0 !== closing && $0.isVisible && $0.title == "Mac Vitals" && !($0 is NSPanel)
                    }
                    if !stillOpen { NSApp.setActivationPolicy(.accessory) }
                }
            }
        }
    }

    /// Keep running when the window closes; the app lives in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

/// The always-visible menu-bar readout. `MenuBarExtra` renders SwiftUI labels
/// unreliably in the bar (a multi-view label collapses to its first element, and
/// SF Symbols interpolated into Text do not draw), so the readout is rendered to
/// a template NSImage and shown as that image, which the bar tints like any other
/// item. Compact shows CPU and GPU; full adds memory and network in/out.
struct MenuBarLabel: View {
    @ObservedObject var store: SampleStore
    @AppStorage("menuBarFull") private var full: Bool = true

    var body: some View {
        if let image = rendered(store.latest, full: full) {
            Image(nsImage: image)
        } else {
            Text("Vitals")
        }
    }

    private func rendered(_ s: Snapshot, full: Bool) -> NSImage? {
        let renderer = ImageRenderer(content: readout(s, full: full))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = true // let the menu bar tint it for light/dark
        return image
    }

    private func readout(_ s: Snapshot, full: Bool) -> some View {
        HStack(spacing: 9) {
            metric(Sym.cpu, "\(Int(s.cpu.usage.rounded()))%")
            metric(Sym.gpu, "\(Int(s.gpu.usage.rounded()))%")
            if full {
                metric(Sym.mem, "\(Int(s.memory.usedPercent.rounded()))%")
                HStack(spacing: 7) {
                    metric("arrow.down", Fmt.rateCompact(s.network.downloadBytesPerSec))
                    metric("arrow.up", Fmt.rateCompact(s.network.uploadBytesPerSec))
                }
            }
        }
        .font(.system(size: 12, weight: .regular))
        .monospacedDigit()
        .foregroundStyle(.black) // a template image uses only the alpha shape
        .padding(.vertical, 1)
        .padding(.horizontal, 3) // keep edge glyphs from clipping in the rendered image
        .fixedSize()
    }

    private func metric(_ symbol: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).imageScale(.small)
            Text(value)
        }
    }
}
