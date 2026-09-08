import SwiftUI
import VitalsCore

enum HistoryRange: String, CaseIterable, Identifiable {
    case m1 = "1m", m15 = "15m", h1 = "1h", h6 = "6h", h24 = "24h", d7 = "7d"
    var seconds: TimeInterval {
        switch self {
        case .m1: 60; case .m15: 900; case .h1: 3600
        case .h6: 21_600; case .h24: 86_400; case .d7: 604_800
        }
    }
    /// Ranges past an hour read the persisted minute samples; shorter ranges use
    /// the live 1-second history.
    var usesMinutes: Bool { seconds > 3600 }
    var id: String { rawValue }
}

/// The full window: every metric as a time-series chart over a selectable range,
/// from one minute of live detail to seven days of persisted history.
struct MainView: View {
    @ObservedObject var store: SampleStore
    @State private var range: HistoryRange
    var scrolls: Bool

    private let readTeal = Palette.teal
    private let writeOrange = Palette.orange

    init(store: SampleStore, scrolls: Bool = true, initialRange: HistoryRange = .m15) {
        _store = ObservedObject(wrappedValue: store)
        self.scrolls = scrolls
        _range = State(initialValue: initialRange)
    }

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

    private var rangeControl: some View {
        HStack(spacing: 2) {
            ForEach(HistoryRange.allCases) { r in
                Text(r.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(range == r ? Palette.ink : Palette.ink2)
                    .padding(.vertical, 4).padding(.horizontal, 9)
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

    /// Points for a metric over the current range, from the right source and
    /// thinned so a long window does not draw tens of thousands of points.
    private func series(_ metric: Metric) -> [(date: Date, value: Double)] {
        let cutoff = Date().addingTimeInterval(-range.seconds)
        let raw: [(Date, Double)]
        if range.usesMinutes {
            raw = store.minutes.filter { $0.t >= cutoff }.map { ($0.t, metric.value($0)) }
        } else {
            raw = store.history.filter { $0.timestamp >= cutoff }.map { ($0.timestamp, metric.value($0)) }
        }
        return downsample(raw)
    }

    private func downsample(_ pts: [(Date, Double)], limit: Int = 500) -> [(date: Date, value: Double)] {
        guard pts.count > limit else { return pts.map { (date: $0.0, value: $0.1) } }
        let step = pts.count / limit + 1
        var out: [(date: Date, value: Double)] = []
        out.reserveCapacity(limit + 1)
        var i = 0
        while i < pts.count { out.append((date: pts[i].0, value: pts[i].1)); i += step }
        if let last = pts.last { out.append((date: last.0, value: last.1)) }
        return out
    }

    // MARK: - Charts

    private var cpuChart: some View {
        let s = store.latest.cpu
        return TimeChart(
            title: "CPU", symbol: "cpu", accent: Palette.load(s.usage),
            lines: [ChartLine(label: "CPU", color: Palette.load(s.usage), points: series(.cpu))],
            span: range.seconds, yMax: 100, yFormat: { "\(Int($0))%" },
            currentText: "\(Int(s.usage))%", note: "E \(Int(s.efficiencyUsage)) · P \(Int(s.performanceUsage))")
    }

    private var gpuChart: some View {
        let s = store.latest.gpu
        return TimeChart(
            title: "GPU", symbol: "display", accent: Palette.load(s.usage),
            lines: [ChartLine(label: "GPU", color: Palette.load(s.usage), points: series(.gpu))],
            span: range.seconds, yMax: 100, yFormat: { "\(Int($0))%" },
            currentText: "\(Int(s.usage))%", note: s.provisional ? "provisional" : nil)
    }

    private var memoryChart: some View {
        let m = store.latest.memory
        return TimeChart(
            title: "Memory", symbol: "memorychip", accent: Palette.blue,
            lines: [ChartLine(label: "Memory", color: Palette.blue, points: series(.memory))],
            span: range.seconds, yMax: 100, yFormat: { "\(Int($0))%" },
            currentText: "\(Int(m.usedPercent))%", note: "\(Fmt.gb(m.usedBytes)) / \(Fmt.gb(m.totalBytes)) GB")
    }

    private var powerChart: some View {
        let p = store.latest.power
        let pts = series(.power)
        let yMax = Fmt.niceMax(pts.map(\.value), floor: 10)
        return TimeChart(
            title: "Power", symbol: "bolt.fill", accent: Palette.amber,
            lines: [ChartLine(label: "Power", color: Palette.amber, points: pts)],
            span: range.seconds, yMax: yMax, yFormat: { String(format: "%.0f W", $0) },
            currentText: String(format: "%.1f W", p.totalWatts),
            note: String(format: "CPU %.1f · GPU %.1f", p.cpuWatts, p.gpuWatts))
    }

    private var networkChart: some View {
        let n = store.latest.network
        let down = series(.netDown), up = series(.netUp)
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
        let read = series(.diskRead), write = series(.diskWrite)
        let yMax = Fmt.niceMax(read.map(\.value) + write.map(\.value), floor: 1024 * 1024)
        return TimeChart(
            title: "Disk", symbol: "internaldrive", accent: readTeal,
            lines: [ChartLine(label: "read", color: readTeal, points: read),
                    ChartLine(label: "write", color: writeOrange, points: write)],
            span: range.seconds, yMax: yMax, yFormat: { Fmt.rate($0) },
            currentText: "\(Fmt.gb(d.freeBytes)) GB free", note: nil)
    }
}
