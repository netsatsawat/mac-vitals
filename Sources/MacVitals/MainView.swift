import SwiftUI
import VitalsCore

enum HistoryRange: String, CaseIterable, Identifiable {
    case m1 = "1m", m15 = "15m", h1 = "1h", h6 = "6h", h24 = "24h"
    case d7 = "7d", d15 = "15d", d30 = "30d", d90 = "90d", d180 = "180d", d365 = "365d", ytd = "YTD"

    var seconds: TimeInterval {
        switch self {
        case .m1: 60; case .m15: 900; case .h1: 3600; case .h6: 21_600; case .h24: 86_400
        case .d7: 7 * 86_400; case .d15: 15 * 86_400; case .d30: 30 * 86_400
        case .d90: 90 * 86_400; case .d180: 180 * 86_400; case .d365: 365 * 86_400
        case .ytd: max(3600, Date().timeIntervalSince(Self.startOfYear))
        }
    }

    enum Tier { case live, minutes, hours }
    /// Which stored resolution answers this range.
    var tier: Tier {
        if seconds <= 3600 { return .live }
        if seconds <= 7 * 86_400 { return .minutes }
        return .hours
    }

    var name: String {
        switch self {
        case .m1: "1 minute"; case .m15: "15 minutes"; case .h1: "1 hour"; case .h6: "6 hours"
        case .h24: "24 hours"; case .d7: "7 days"; case .d15: "15 days"; case .d30: "30 days"
        case .d90: "90 days"; case .d180: "180 days"; case .d365: "365 days"; case .ytd: "Year to date"
        }
    }

    var id: String { rawValue }
    static var startOfYear: Date {
        let c = Calendar.current
        return c.date(from: c.dateComponents([.year], from: Date())) ?? Date()
    }
}

/// The full window: every metric as a time-series chart over a selectable range,
/// from one minute of live detail to a full year of persisted history.
struct MainView: View {
    @ObservedObject var store: SampleStore
    @State private var range: HistoryRange
    @State private var rangeMenu = false
    @State private var traceStart: Date?
    @State private var traceResult: TraceResult?
    @State private var showTrace = false
    var scrolls: Bool

    private let readTeal = Palette.teal
    private let writeOrange = Palette.orange

    init(store: SampleStore, scrolls: Bool = true, initialRange: HistoryRange = .h24) {
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
            if store.latest.thermal.available {
                HStack(spacing: 14) { temperatureChart; fanChart }
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            GaugeMark(size: 18)
            Text("Mac Vitals").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink)
            batteryPill
            traceButton
            Spacer()
            collectingHint
            rangeControl
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var traceButton: some View {
        Button {
            if let start = traceStart {
                var t = Trace(start: start)
                for s in store.history where s.timestamp >= start { t.add(s) }
                traceResult = t.result(); traceStart = nil; showTrace = true
            } else {
                traceStart = Date()
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: traceStart == nil ? "record.circle" : "stop.circle.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text(traceStart == nil ? "Trace" : "Stop")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(traceStart == nil ? Palette.ink2 : Color(red: 1, green: 0.23, blue: 0.19))
            .padding(.vertical, 4).padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Palette.track))
        }
        .buttonStyle(.plain)
        .help("Measure what a task costs: start, do the work, stop.")
        .popover(isPresented: $showTrace, arrowEdge: .bottom) { traceResultView }
    }

    @ViewBuilder private var traceResultView: some View {
        if let r = traceResult {
            VStack(alignment: .leading, spacing: 9) {
                Text("Task cost").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
                Text(String(format: "%.0f seconds · %d samples", r.durationSeconds, r.samples))
                    .font(.system(size: 10.5)).foregroundStyle(Palette.ink3)
                Rectangle().fill(Palette.hair).frame(height: 0.5)
                traceRow("CPU", String(format: "avg %.0f%%   peak %.0f%%", r.cpuAvgPercent, r.cpuPeakPercent))
                traceRow("GPU", String(format: "avg %.0f%%   peak %.0f%%", r.gpuAvgPercent, r.gpuPeakPercent))
                traceRow("Power", String(format: "%.1f W avg · %.3f Wh", r.avgWatts, r.energyWattHours))
                traceRow("Network", "↓ \(Fmt.bytes(r.networkDownBytes))   ↑ \(Fmt.bytes(r.networkUpBytes))")
                traceRow("Disk", "R \(Fmt.bytes(r.diskReadBytes))   W \(Fmt.bytes(r.diskWriteBytes))")
                if r.socTempPeakC > 0 { traceRow("Temp", String(format: "peak %.0f°C", r.socTempPeakC)) }
            }
            .padding(14).frame(width: 264)
        }
    }

    private func traceRow(_ key: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(key).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.ink2)
                .frame(width: 62, alignment: .leading)
            Text(value).font(.vitalsNumber(11)).foregroundStyle(Palette.ink)
            Spacer(minLength: 0)
        }
    }

    /// Seconds of history actually available for the current range's tier.
    private func coverage() -> TimeInterval {
        let oldest: Date?
        switch range.tier {
        case .live: oldest = store.history.first?.timestamp
        case .minutes: oldest = store.minutes.first?.t
        case .hours: oldest = store.hours.first?.t
        }
        guard let oldest else { return 0 }
        return Date().timeIntervalSince(oldest)
    }

    private func shortDuration(_ s: TimeInterval) -> String {
        let x = Int(s)
        if x >= 86_400 { return "\(x / 86_400)d" }
        if x >= 3600 { return "\(x / 3600)h" }
        if x >= 60 { return "\(x / 60)m" }
        return "\(x)s"
    }

    /// Shown when the app has not been running long enough to fill the range yet.
    @ViewBuilder private var collectingHint: some View {
        let covered = coverage()
        if covered < range.seconds * 0.9 {
            HStack(spacing: 5) {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 10, weight: .semibold))
                Text(covered < 60 ? "collecting…" : "collecting · \(shortDuration(covered)) of \(range.rawValue)")
                    .font(.system(size: 10.5, weight: .medium))
            }
            .foregroundStyle(Palette.ink3)
        }
    }

    private var rangeControl: some View {
        Button { rangeMenu.toggle() } label: {
            HStack(spacing: 6) {
                Text(range.rawValue).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.ink)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(Palette.ink2)
            }
            .frame(minWidth: 40)
            .padding(.vertical, 4).padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Palette.track))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $rangeMenu, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(HistoryRange.allCases) { r in
                    Button {
                        range = r; rangeMenu = false
                    } label: {
                        HStack(spacing: 10) {
                            Text(r.name).font(.system(size: 12))
                            Spacer()
                            if r == range {
                                Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Palette.blue)
                            }
                        }
                        .foregroundStyle(Palette.ink)
                        .padding(.vertical, 5).padding(.horizontal, 10)
                        .frame(width: 156, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
        }
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

    /// Points for a metric over the current range, from the right storage tier and
    /// thinned so a long window does not draw tens of thousands of points.
    private func series(_ metric: Metric) -> [(date: Date, value: Double)] {
        let cutoff = Date().addingTimeInterval(-range.seconds)
        let raw: [(Date, Double)]
        switch range.tier {
        case .live:
            raw = store.history.filter { $0.timestamp >= cutoff }.map { ($0.timestamp, metric.value($0)) }
        case .minutes:
            raw = store.minutes.filter { $0.t >= cutoff }.map { ($0.t, metric.value($0)) }
        case .hours:
            raw = store.hours.filter { $0.t >= cutoff }.map { ($0.t, metric.value($0)) }
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

    private var temperatureChart: some View {
        let th = store.latest.thermal
        let pts = series(.temperature)
        let yMax = Fmt.niceMax(pts.map(\.value), floor: 60)
        return TimeChart(
            title: "Temperature", symbol: "thermometer.medium", accent: Palette.load(th.socTempC),
            lines: [ChartLine(label: "SoC", color: Palette.load(th.socTempC), points: pts)],
            span: range.seconds, yMax: yMax, yFormat: { "\(Int($0))°" },
            currentText: String(format: "%.0f°C", th.socTempC), note: "SoC die average")
    }

    private var fanChart: some View {
        let th = store.latest.thermal
        let pts = series(.fanRPM)
        let yMax = Fmt.niceMax(pts.map(\.value), floor: 2000)
        return TimeChart(
            title: "Fan", symbol: "fan", accent: Palette.teal,
            lines: [ChartLine(label: "Fan", color: Palette.teal, points: pts)],
            span: range.seconds, yMax: yMax, yFormat: { "\(Int($0))" },
            currentText: "\(th.fanRPM) rpm", note: th.fanRPM == 0 ? "idle" : nil)
    }
}
