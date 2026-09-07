import SwiftUI

/// One line in a chart: a label, a color, and time-stamped points.
struct ChartLine: Identifiable {
    let id = UUID()
    var label: String
    var color: Color
    var points: [(date: Date, value: Double)]
}

/// A time-series tile for the full window: header with the current value, a
/// gridded plot area, y-axis labels, and left/right time markers. Draws its own
/// paths so the app keeps zero third-party dependencies and the exact house style.
struct TimeChart: View {
    var title: String
    var symbol: String
    var accent: Color
    var lines: [ChartLine]
    var span: TimeInterval
    var yMax: Double
    var yFormat: (Double) -> String
    var currentText: String
    var note: String?

    private let plotHeight: CGFloat = 118

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            plot
            footer
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Palette.track.opacity(0.5))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Palette.hair, lineWidth: 0.5))
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(accent)
            Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Palette.ink2)
            if let note {
                Text(note).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Palette.ink3)
            }
            Spacer()
            Text(currentText).font(.vitalsNumber(17)).foregroundStyle(Palette.ink).monospacedDigit()
        }
    }

    private var plot: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let tMin = Date().addingTimeInterval(-span)
            let x: (Date) -> CGFloat = { d in
                CGFloat(max(0, min(1, d.timeIntervalSince(tMin) / span))) * w
            }
            let y: (Double) -> CGFloat = { v in h - CGFloat(min(v, yMax) / max(yMax, 0.0001)) * h }

            ZStack(alignment: .topLeading) {
                // gridlines at 0, half, full
                ForEach(0..<3) { i in
                    let frac = Double(i) / 2
                    Path { p in
                        let yy = h - CGFloat(frac) * h
                        p.move(to: CGPoint(x: 0, y: yy)); p.addLine(to: CGPoint(x: w, y: yy))
                    }
                    .stroke(Palette.hair, lineWidth: 0.5)
                    Text(yFormat(yMax * frac))
                        .font(.system(size: 9)).foregroundStyle(Palette.ink3)
                        .offset(x: 2, y: h - CGFloat(frac) * h - 12)
                }
                // series
                ForEach(lines) { line in
                    if line.points.count > 1 {
                        area(line, x: x, y: y, h: h).fill(
                            LinearGradient(colors: [line.color.opacity(0.26), line.color.opacity(0)],
                                           startPoint: .top, endPoint: .bottom))
                        stroke(line, x: x, y: y)
                            .stroke(line.color, style: StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round))
                        if let last = line.points.last {
                            Circle().fill(line.color).frame(width: 4.5, height: 4.5)
                                .position(x: x(last.date), y: y(last.value))
                        }
                    }
                }
            }
        }
        .frame(height: plotHeight)
    }

    private func stroke(_ line: ChartLine, x: (Date) -> CGFloat, y: (Double) -> CGFloat) -> Path {
        Path { p in
            for (i, pt) in line.points.enumerated() {
                let point = CGPoint(x: x(pt.date), y: y(pt.value))
                if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
            }
        }
    }
    private func area(_ line: ChartLine, x: (Date) -> CGFloat, y: (Double) -> CGFloat, h: CGFloat) -> Path {
        Path { p in
            for (i, pt) in line.points.enumerated() {
                let point = CGPoint(x: x(pt.date), y: y(pt.value))
                if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
            }
            if let last = line.points.last, let first = line.points.first {
                p.addLine(to: CGPoint(x: x(last.date), y: h))
                p.addLine(to: CGPoint(x: x(first.date), y: h))
                p.closeSubpath()
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(spanLabel).font(.system(size: 9.5)).foregroundStyle(Palette.ink3)
            Spacer()
            if lines.count > 1 {
                HStack(spacing: 12) {
                    ForEach(lines) { line in
                        HStack(spacing: 4) {
                            Circle().fill(line.color).frame(width: 6, height: 6)
                            Text(line.label).font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.ink2)
                        }
                    }
                }
            }
            Spacer()
            Text("now").font(.system(size: 9.5)).foregroundStyle(Palette.ink3)
        }
    }

    private var spanLabel: String {
        let m = Int(span / 60)
        return m >= 60 ? "\(m / 60)h ago" : "\(m)m ago"
    }
}
