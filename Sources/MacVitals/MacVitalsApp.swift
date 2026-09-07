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
        if let i = args.firstIndex(of: "--render-popover"), i + 1 < args.count {
            RenderTool.renderPopover(to: args[i + 1])
            NSApp.terminate(nil)
        }
        if let i = args.firstIndex(of: "--render"), i + 1 < args.count {
            RenderTool.renderMainWindow(to: args[i + 1])
            NSApp.terminate(nil)
        }
    }
}

/// The always-visible menu-bar readout: CPU and GPU percent, kept compact.
struct MenuBarLabel: View {
    @ObservedObject var store: SampleStore
    var body: some View {
        let s = store.latest
        HStack(spacing: 5) {
            Image(systemName: Sym.cpu)
            Text("\(Int(s.cpu.usage.rounded()))%")
            Image(systemName: Sym.gpu)
            Text("\(Int(s.gpu.usage.rounded()))%")
        }
        .monospacedDigit()
    }
}
