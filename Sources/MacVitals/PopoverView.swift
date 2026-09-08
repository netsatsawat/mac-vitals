import SwiftUI
import VitalsCore

/// The panel that drops from the menu-bar item: a denser list of the same
/// metrics, each with a fill bar and a minute of history, plus a footer.
struct PopoverView: View {
    @ObservedObject var store: SampleStore
    var onToggleWidget: () -> Void
    var onQuit: () -> Void
    @Environment(\.openWindow) private var openWindow
    @AppStorage("menuBarFull") private var menuBarFull: Bool = true

    private func openMainWindow() {
        NSApp.setActivationPolicy(.regular) // show the Dock icon while the window is open
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    var body: some View {
        let s = store.latest
        VStack(alignment: .leading, spacing: 0) {
            SurfaceHeader().padding(.bottom, 8)

            MetricRow(name: "CPU", symbol: Sym.cpu, tint: Palette.load(s.cpu.usage),
                      value: "\(Int(s.cpu.usage.rounded()))", unit: "%", bar: s.cpu.usage,
                      sub: "E \(Int(s.cpu.efficiencyUsage)) · P \(Int(s.cpu.performanceUsage))",
                      history: store.cpuHistory)
            divider
            MetricRow(name: "GPU", symbol: Sym.gpu, tint: Palette.load(s.gpu.usage),
                      value: "\(Int(s.gpu.usage.rounded()))", unit: "%", bar: s.gpu.usage,
                      sub: s.gpu.provisional ? "provisional" : "",
                      history: store.gpuHistory)
            divider
            MetricRow(name: "Memory", symbol: Sym.mem, tint: Palette.blue,
                      value: "\(Int(s.memory.usedPercent.rounded()))", unit: "%", bar: s.memory.usedPercent,
                      sub: "\(gbString(s.memory.usedBytes)) / \(gbString(s.memory.totalBytes)) GB",
                      history: store.memHistory)
            divider
            MetricRow(name: "Power", symbol: Sym.power, tint: Palette.amber,
                      value: String(format: "%.1f", s.power.totalWatts), unit: "W", bar: nil,
                      sub: String(format: "CPU %.1f · GPU %.1f", s.power.cpuWatts, s.power.gpuWatts),
                      history: nil)
            divider
            MetricRow(name: "Network", symbol: "network", tint: Palette.blue,
                      value: Fmt.rate(s.network.downloadBytesPerSec), unit: "", bar: nil,
                      sub: "up \(Fmt.rate(s.network.uploadBytesPerSec))", history: nil)
            divider
            MetricRow(name: "Disk", symbol: "internaldrive", tint: Palette.teal,
                      value: "\(Fmt.gb(s.disk.freeBytes)) GB", unit: "", bar: nil,
                      sub: "R \(Fmt.rate(s.disk.readBytesPerSec)) · W \(Fmt.rate(s.disk.writeBytesPerSec))",
                      history: nil)
            if s.battery.present {
                divider
                MetricRow(name: "Battery", symbol: s.battery.isCharging ? "battery.100.bolt" : "battery.100",
                          tint: Palette.good,
                          value: "\(Int(s.battery.percent))", unit: "%", bar: s.battery.percent,
                          sub: s.battery.isCharging ? "charging" : "on battery", history: nil)
            }

            footer
        }
        .padding(16)
        .frame(width: 268)
        .background(VisualEffect(material: .popover))
    }

    private var divider: some View {
        Rectangle().fill(Palette.hair).frame(height: 0.5)
    }

    private func footerButton(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                Text(label).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(Palette.ink2)
            .padding(.vertical, 3).padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Palette.track))
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Circle().fill(Palette.good).frame(width: 7, height: 7)
                Text("Normal").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Palette.ink2)
            }
            Spacer(minLength: 8)
            footerButton("square.grid.2x2", "Widget", onToggleWidget)
            footerButton("macwindow", "Open", openMainWindow)
            Menu {
                Toggle("Full menu-bar readout", isOn: $menuBarFull)
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                Text(menuBarFull ? "Showing CPU, GPU, memory, network"
                                 : "Showing CPU and GPU")
                Divider()
                Button("Quit Mac Vitals", action: onQuit)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.ink2)
                    .frame(width: 24, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.top, 12)
        .overlay(alignment: .top) { Rectangle().fill(Palette.hair).frame(height: 0.5) }
    }
}
