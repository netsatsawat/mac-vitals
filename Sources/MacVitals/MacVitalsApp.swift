import SwiftUI

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

/// The always-visible menu-bar readout: CPU, GPU, memory, and network in/out.
struct MenuBarLabel: View {
    @ObservedObject var store: SampleStore
    var body: some View {
        let s = store.latest
        HStack(spacing: 7) {
            item(Sym.cpu, "\(Int(s.cpu.usage.rounded()))%")
            item(Sym.gpu, "\(Int(s.gpu.usage.rounded()))%")
            item(Sym.mem, "\(Int(s.memory.usedPercent.rounded()))%")
            HStack(spacing: 2) {
                Image(systemName: "arrow.down").imageScale(.small)
                Text(Fmt.rateCompact(s.network.downloadBytesPerSec))
                Image(systemName: "arrow.up").imageScale(.small)
                Text(Fmt.rateCompact(s.network.uploadBytesPerSec))
            }
        }
        .monospacedDigit()
    }

    private func item(_ symbol: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).imageScale(.small)
            Text(value)
        }
    }
}
