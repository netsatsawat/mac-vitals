import SwiftUI
import VitalsCore

/// The panel that drops from the menu-bar item: a denser list of the same
/// metrics, each with a fill bar and a minute of history, plus a footer.
struct PopoverView: View {
    @ObservedObject var store: SampleStore
    var onToggleWidget: () -> Void
    var onQuit: () -> Void

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

            footer
        }
        .padding(16)
        .frame(width: 268)
        .background(VisualEffect(material: .popover))
    }

    private var divider: some View {
        Rectangle().fill(Palette.hair).frame(height: 0.5)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                Circle().fill(Palette.good).frame(width: 7, height: 7)
                Text("Pressure normal").font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Palette.ink2)
            }
            Spacer(minLength: 10)
            Button(action: onToggleWidget) {
                HStack(spacing: 5) {
                    Image(systemName: "square.grid.2x2").font(.system(size: 10, weight: .semibold))
                    Text("Show widget").font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Palette.ink2)
                .padding(.vertical, 3).padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Palette.track)
                )
            }
            .buttonStyle(.plain)
            Menu {
                Button("Show widget", action: onToggleWidget)
                Divider()
                Button("Quit Mac Vitals", action: onQuit)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.ink2)
                    .frame(width: 26, height: 22)
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
