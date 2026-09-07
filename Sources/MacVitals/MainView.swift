import SwiftUI
import VitalsCore

enum HistoryRange: String, CaseIterable, Identifiable {
    case m1 = "1 min"
    case m15 = "15 min"
    case h1 = "1 hour"
    var seconds: TimeInterval { switch self { case .m1: 60; case .m15: 900; case .h1: 3600 } }
    var id: String { rawValue }
}

/// The full window: every metric as a time-series chart over a selectable range.
struct MainView: View {
    @ObservedObject var store: SampleStore
    @State private var range: HistoryRange = .m15
    /// The offscreen renderer cannot capture a ScrollView, so it opts out.
    var scrolls: Bool = true

    private let readTeal = Palette.teal
    private let writeOrange = Palette.orange

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().overlay(Palette.hair)
            if scrolls {
                ScrollView { grid.padding(16) }
            } else {
                grid.padding(16)
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var grid: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) { cpuChart; gpuChart }
            HStack(spacing: 14) { memoryChart; powerChart }
            HStack(spacing: 14) { networkChart; diskChart }
        }
    }

    private var rangeControl: some View {
        HStack(spacing: 2) {
            ForEach(HistoryRange.allCases) { r in
                Text(r.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(range == r ? Palette.ink : Palette.ink2)
                    .padding(.vertical, 4).padding(.horizontal, 10)
                    .background {
                        if range == r {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .shadow(color: .black.opacity(0.12), radius: 1, y: 0.5)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { range = r }
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.track))
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            GaugeMark(size: 18)
            Text("Mac Vitals").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink)
            batteryPill
            Spacer()
            rangeControl
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    @ViewBuilder private var batteryPill: some View {
        let b = store.latest.battery
        if b.present {
            HStack(spacing: 5) {
                Image(systemName: b.isCharging ? "battery.100.bolt" : "battery.100")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(b.isCharging ? Palette.good : Palette.ink2)
                Text("\(Int(b.percent))%").font(.vitalsNumber(11)).foregroundStyle(Palette.ink2)
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Palette.track.opacity(0.5)))
        }
    }

    // MARK: - Data

    private func pts(_ f: @escaping (Snapshot) -> Double) -> [(date: Date, value: Double)] {
        let cutoff = Date().addingTimeInterval(-range.seconds)
        return store.history.filter { $0.timestamp >= cutoff }.map { (date: $0.timestamp, value: f($0)) }
    }

    // MARK: - Charts

    private var cpuChart: some View {
        let s = store.latest.cpu
        return TimeChart(
            title: "CPU", symbol: "cpu", accent: Palette.load(s.usage),
            lines: [ChartLine(label: "CPU", color: Palette.load(s.usage), points: pts { $0.cpu.usage })],
            span: range.seconds, yMax: 100, yFormat: { "\(Int($0))%" },
            currentText: "\(Int(s.usage))%", note: "E \(Int(s.efficiencyUsage)) · P \(Int(s.performanceUsage))")
    }

    private var gpuChart: some View {
        let s = store.latest.gpu
        return TimeChart(
            title: "GPU", symbol: "display", accent: Palette.load(s.usage),
            lines: [ChartLine(label: "GPU", color: Palette.load(s.usage), points: pts { $0.gpu.usage })],
            span: range.seconds, yMax: 100, yFormat: { "\(Int($0))%" },
            currentText: "\(Int(s.usage))%", note: s.provisional ? "provisional" : nil)
    }

    private var memoryChart: some View {
        let m = store.latest.memory
        return TimeChart(
            title: "Memory", symbol: "memorychip", accent: Palette.blue,
            lines: [ChartLine(label: "Memory", color: Palette.blue, points: pts { $0.memory.usedPercent })],
            span: range.seconds, yMax: 100, yFormat: { "\(Int($0))%" },
            currentText: "\(Int(m.usedPercent))%", note: "\(Fmt.gb(m.usedBytes)) / \(Fmt.gb(m.totalBytes)) GB")
    }

    private var powerChart: some View {
        let p = store.latest.power
        let series = pts { $0.power.totalWatts }
        let yMax = Fmt.niceMax(series.map(\.value), floor: 10)
        return TimeChart(
            title: "Power", symbol: "bolt.fill", accent: Palette.amber,
            lines: [ChartLine(label: "Power", color: Palette.amber, points: series)],
            span: range.seconds, yMax: yMax, yFormat: { String(format: "%.0f W", $0) },
            currentText: String(format: "%.1f W", p.totalWatts),
            note: String(format: "CPU %.1f · GPU %.1f", p.cpuWatts, p.gpuWatts))
    }

    private var networkChart: some View {
        let n = store.latest.network
        let down = pts { $0.network.downloadBytesPerSec }
        let up = pts { $0.network.uploadBytesPerSec }
        let yMax = Fmt.niceMax(down.map(\.value) + up.map(\.value), floor: 128 * 1024)
        return TimeChart(
            title: "Network", symbol: "network", accent: Palette.blue,
            lines: [ChartLine(label: "down", color: Palette.blue, points: down),
                    ChartLine(label: "up", color: Palette.good, points: up)],
            span: range.seconds, yMax: yMax, yFormat: { Fmt.rate($0) },
            currentText: "↓ \(Fmt.rate(n.downloadBytesPerSec))", note: nil)
    }

    private var diskChart: some View {
        let d = store.latest.disk
        let read = pts { $0.disk.readBytesPerSec }
        let write = pts { $0.disk.writeBytesPerSec }
        let yMax = Fmt.niceMax(read.map(\.value) + write.map(\.value), floor: 1024 * 1024)
        return TimeChart(
            title: "Disk", symbol: "internaldrive", accent: readTeal,
            lines: [ChartLine(label: "read", color: readTeal, points: read),
                    ChartLine(label: "write", color: writeOrange, points: write)],
            span: range.seconds, yMax: yMax, yFormat: { Fmt.rate($0) },
            currentText: "\(Fmt.gb(d.freeBytes)) GB free", note: nil)
    }
}
