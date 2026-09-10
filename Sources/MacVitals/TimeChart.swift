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

    /// X of the mouse inside the plot while hovering, in the plot's own space.
    @State private var hoverX: CGFloat?
    /// Preview-only: forces a hover position so the crosshair can be rendered
    /// offscreen for a visual check. Nil in the running app.
    var previewHoverX: CGFloat?

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
                // hover crosshair, drawn on top of the series
                if let hx = hoverX ?? previewHoverX { crosshair(hx: hx, w: w, h: h, x: x, y: y) }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let p): hoverX = p.x
                case .ended: hoverX = nil
                }
            }
        }
        .frame(height: plotHeight)
    }

    /// A vertical guide, a dot on each series at the hovered time, and a small
    /// card reading out the time and each series' value at that point. Snaps to
    /// the nearest real sample so the numbers are exact, not interpolated.
    @ViewBuilder
    private func crosshair(hx: CGFloat, w: CGFloat, h: CGFloat,
                           x: @escaping (Date) -> CGFloat, y: @escaping (Double) -> CGFloat) -> some View {
        let snap = lines.first.flatMap { nearest($0, toX: hx, x: x) }
        let snapX = snap.map { x($0.date) } ?? hx
        let rows: [(label: String, color: Color, value: String)] = lines.compactMap { line in
            guard let pt = nearest(line, toX: hx, x: x) else { return nil }
            return (line.label, line.color, yFormat(pt.value))
        }

        Path { p in
            p.move(to: CGPoint(x: snapX, y: 0)); p.addLine(to: CGPoint(x: snapX, y: h))
        }
        .stroke(Palette.ink3.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

        ForEach(lines) { line in
            if let pt = nearest(line, toX: hx, x: x) {
                Circle().fill(line.color).frame(width: 7, height: 7)
                    .overlay(Circle().strokeBorder(Palette.track, lineWidth: 1.5))
                    .position(x: x(pt.date), y: y(pt.value))
            }
        }

        hoverCard(date: snap?.date, rows: rows)
            .position(x: min(max(snapX, cardHalfWidth + 2), w - cardHalfWidth - 2), y: cardHalfHeight(rows.count) + 4)
            .allowsHitTesting(false)
    }

    private var cardHalfWidth: CGFloat { lines.count > 1 ? 62 : 46 }
    private func cardHalfHeight(_ rows: Int) -> CGFloat { CGFloat(11 + (rows > 1 ? rows * 15 : 8)) }

    private func hoverCard(date: Date?, rows: [(label: String, color: Color, value: String)]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let date {
                Text(timeLabel(date)).font(.system(size: 9.5, weight: .medium)).foregroundStyle(Palette.ink3)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                HStack(spacing: 5) {
                    if rows.count > 1 { Circle().fill(r.color).frame(width: 5, height: 5) }
                    if rows.count > 1 {
                        Text(r.label).font(.system(size: 10)).foregroundStyle(Palette.ink2)
                    }
                    Text(r.value).font(.vitalsNumber(11)).foregroundStyle(Palette.ink)
                }
            }
        }
        .padding(.vertical, 5).padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Palette.hair, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.12), radius: 5, y: 1)
        )
        .fixedSize()
    }

    /// The point in `line` whose plotted x is closest to the hovered x.
    private func nearest(_ line: ChartLine, toX hx: CGFloat, x: (Date) -> CGFloat) -> (date: Date, value: Double)? {
        guard var best = line.points.first else { return nil }
        var bestDist = abs(x(best.date) - hx)
        for pt in line.points.dropFirst() {
            let d = abs(x(pt.date) - hx)
            if d < bestDist { bestDist = d; best = pt }
        }
        return best
    }

    /// Time label for the hovered sample, at a resolution that fits the range.
    private func timeLabel(_ d: Date) -> String {
        let f = DateFormatter()
        if span <= 3600 { f.dateFormat = "HH:mm:ss" }
        else if span <= 86_400 { f.dateFormat = "HH:mm" }
        else if span <= 15 * 86_400 { f.dateFormat = "MMM d, HH:mm" }
        else { f.dateFormat = "MMM d" }
        return f.string(from: d)
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
        let s = Int(span)
        if s >= 350 * 86_400 { return "1y ago" }
        if s >= 86_400 { return "\(s / 86_400)d ago" }
        if s >= 3600 { return "\(s / 3600)h ago" }
        return "\(s / 60)m ago"
    }
}
