import SwiftUI
import VitalsCore

/// The floating desktop gadget: three ring gauges, package power, and a per-core
/// grid. Fixed width so it reads as a compact widget, height driven by content.
struct WidgetView: View {
    @ObservedObject var store: SampleStore

    var body: some View {
        let s = store.latest
        VStack(alignment: .leading, spacing: 14) {
            SurfaceHeader()

            HStack(spacing: 6) {
                gauge(value: s.cpu.usage, color: Palette.load(s.cpu.usage),
                      symbol: Sym.cpu, label: "CPU",
                      sub: "E \(Int(s.cpu.efficiencyUsage)) · P \(Int(s.cpu.performanceUsage))")
                gauge(value: s.gpu.usage, color: Palette.load(s.gpu.usage),
                      symbol: Sym.gpu, label: "GPU",
                      sub: s.gpu.provisional ? "provisional" : " ")
                gauge(value: s.memory.usedPercent, color: Palette.blue,
                      symbol: Sym.mem, label: "Memory",
                      sub: "\(gbString(s.memory.usedBytes)) / \(gbString(s.memory.totalBytes)) GB")
            }

            VStack(alignment: .leading, spacing: 13) {
                Divider().overlay(Palette.hair)
                power(s.power)
                cores(s.cpu)
            }
        }
        .padding(EdgeInsets(top: 16, leading: 16, bottom: 14, trailing: 16))
        .frame(width: 300)
        .background(surface)
    }

    private func gauge(value: Double, color: Color, symbol: String, label: String, sub: String) -> some View {
        VStack(spacing: 9) {
            RingGauge(value: value, color: color) { RingLabel(value: value) }
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                Text(label).font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(Palette.ink2)
            Text(sub).font(.vitalsNumber(10, weight: .regular))
                .foregroundStyle(Palette.ink3).lineLimit(1)
                .padding(.top, -3)
        }
        .frame(maxWidth: .infinity)
    }

    private func power(_ p: PowerSnapshot) -> some View {
        HStack(spacing: 9) {
            Image(systemName: Sym.power).font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.ink.opacity(0.72))
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(String(format: "%.1f", p.totalWatts)).font(.vitalsNumber(22))
                Text("W").font(.vitalsNumber(12)).foregroundStyle(Palette.ink.opacity(0.5))
            }
            .foregroundStyle(Palette.ink)
            Spacer()
            HStack(spacing: 12) {
                splitStat("CPU", p.cpuWatts)
                splitStat("GPU", p.gpuWatts)
            }
        }
    }
    private func splitStat(_ label: String, _ w: Double) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 11)).foregroundStyle(Palette.ink2)
            Text(String(format: "%.1f", w)).font(.vitalsNumber(11)).foregroundStyle(Palette.ink)
        }
    }

    private func cores(_ cpu: CPUSnapshot) -> some View {
        HStack(spacing: 10) {
            Text("Cores").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Palette.ink2)
            HStack(spacing: 3) {
                ForEach(Array(cpu.perCore.enumerated()), id: \.offset) { _, v in
                    GeometryReader { geo in
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 3).fill(Palette.track)
                            RoundedRectangle(cornerRadius: 3).fill(Palette.load(v))
                                .frame(height: max(3, CGFloat(max(8, v)) / 100 * geo.size.height))
                                .animation(.easeOut(duration: 0.4), value: v)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 18)
        }
    }

    private var surface: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(.clear)
            .background(VisualEffect(material: .hudWindow))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Palette.ink.opacity(0.08), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
