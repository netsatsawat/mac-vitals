import SwiftUI

/// A ring gauge: a track plus a rounded value arc from the top, with whatever
/// the caller centers inside it.
struct RingGauge<Center: View>: View {
    var value: Double            // 0 to 100
    var color: Color
    var size: CGFloat = 78
    var lineWidth: CGFloat = 8
    @ViewBuilder var center: () -> Center

    var body: some View {
        ZStack {
            Circle().stroke(Palette.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, value / 100)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.45), value: value)
            center()
        }
        .frame(width: size, height: size)
    }
}

/// The percentage read out in the middle of a ring.
struct RingLabel: View {
    var value: Double
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("\(Int(value.rounded()))").font(.vitalsNumber(18))
            Text("%").font(.vitalsNumber(10)).foregroundStyle(Palette.ink.opacity(0.5))
        }
        .foregroundStyle(Palette.ink)
        .monospacedDigit()
    }
}

/// A minute of history as a filled sparkline with an emphasized endpoint.
struct Sparkline: View {
    var values: [Double]
    var color: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let pts = points(in: CGSize(width: w, height: h))
            ZStack {
                if pts.count > 1 {
                    areaPath(pts, height: h)
                        .fill(LinearGradient(colors: [color.opacity(0.30), color.opacity(0)],
                                             startPoint: .top, endPoint: .bottom))
                    linePath(pts)
                        .stroke(color, style: StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round))
                    if let last = pts.last {
                        Circle().fill(color).frame(width: 4, height: 4).position(last)
                    }
                }
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let lo = values.min() ?? 0, hi = values.max() ?? 1
        let range = max(hi - lo, 0.0001)
        return values.enumerated().map { i, v in
            let x = CGFloat(i) / CGFloat(values.count - 1) * size.width
            let y = size.height - 2 - CGFloat((v - lo) / range) * (size.height - 4)
            return CGPoint(x: x, y: y)
        }
    }
    private func linePath(_ pts: [CGPoint]) -> Path {
        var p = Path(); p.addLines(pts); return p
    }
    private func areaPath(_ pts: [CGPoint], height: CGFloat) -> Path {
        var p = Path()
        p.addLines(pts)
        if let last = pts.last, let first = pts.first {
            p.addLine(to: CGPoint(x: last.x, y: height))
            p.addLine(to: CGPoint(x: first.x, y: height))
            p.closeSubpath()
        }
        return p
    }
}

/// A thin fill bar used in the popover rows.
struct MiniBar: View {
    var value: Double
    var color: Color
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.track)
                Capsule().fill(color)
                    .frame(width: max(0, min(1, value / 100)) * geo.size.width)
                    .animation(.easeOut(duration: 0.45), value: value)
            }
        }
        .frame(height: 4)
    }
}
