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
    }
}

/// Runs the app as a menu-bar accessory: no Dock icon, no main window.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let panel = FloatingPanelController()
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
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
