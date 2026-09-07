import SwiftUI
import VitalsCore

/// SF Symbol per metric. Native symbols read better in a menu-bar app than
/// custom glyphs, and they inherit weight and color for free.
enum Sym {
    static let cpu = "cpu"
    static let gpu = "display"
    static let mem = "memorychip"
    static let power = "bolt.fill"
}

func gbString(_ bytes: UInt64) -> String {
    String(format: "%.1f", Double(bytes) / 1_073_741_824)
}

/// The "Mac Vitals · Live" header shared by both surfaces.
struct SurfaceHeader: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: Sym.cpu).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.ink.opacity(0.9))
            Text("Mac Vitals").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
            Spacer(minLength: 8)
            HStack(spacing: 5) {
                Circle().fill(Palette.good).frame(width: 6, height: 6)
                    .overlay(Circle().stroke(Palette.good.opacity(0.18), lineWidth: 3))
                Text("LIVE").font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.6).foregroundStyle(Palette.ink3)
            }
        }
    }
}

/// A rounded tinted square holding a metric's icon.
struct IconChip: View {
    var system: String
    var tint: Color
    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(tint.opacity(0.16))
            .frame(width: 28, height: 28)
            .overlay(
                Image(systemName: system)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
            )
    }
}

/// One row of the popover: icon, name and value, a fill bar, a sub-label, and a
/// sparkline. Power passes `bar: nil` and `history: nil` to drop those.
struct MetricRow: View {
    var name: String
    var symbol: String
    var tint: Color
    var value: String
    var unit: String
    var bar: Double?
    var sub: String
    var history: [Double]?

    var body: some View {
        HStack(spacing: 11) {
            IconChip(system: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(name).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Palette.ink)
                    Spacer(minLength: 6)
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(value).font(.vitalsNumber(13))
                        Text(unit).font(.vitalsNumber(9.5)).foregroundStyle(Palette.ink.opacity(0.5))
                    }
                    .foregroundStyle(Palette.ink).monospacedDigit()
                }
                if let bar { MiniBar(value: bar, color: tint) }
                if !sub.isEmpty {
                    Text(sub).font(.vitalsNumber(10, weight: .regular))
                        .foregroundStyle(Palette.ink3).lineLimit(1)
                }
            }
            if let history {
                Sparkline(values: history, color: tint).frame(width: 50, height: 24)
            }
        }
        .padding(.vertical, 10)
    }
}
