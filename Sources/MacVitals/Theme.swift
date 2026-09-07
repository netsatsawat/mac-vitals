import SwiftUI

/// The colors and materials that make the app read as native, kept in one place
/// so the popover and the floating widget stay identical. Values mirror the
/// approved P1 mockup (docs/design/mockup.html).
enum Palette {
    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? dark : light
        })
    }

    static let ink   = dynamic(light: NSColor(white: 0.11, alpha: 1),  dark: NSColor(white: 0.96, alpha: 1))
    static let ink2  = dynamic(light: NSColor(white: 0.24, alpha: 0.62), dark: NSColor(white: 0.92, alpha: 0.62))
    static let ink3  = dynamic(light: NSColor(white: 0.24, alpha: 0.40), dark: NSColor(white: 0.92, alpha: 0.40))
    static let track = dynamic(light: NSColor(white: 0.0, alpha: 0.09),  dark: NSColor(white: 1.0, alpha: 0.11))
    static let hair  = dynamic(light: NSColor(white: 0.0, alpha: 0.07),  dark: NSColor(white: 1.0, alpha: 0.09))
    static let blue  = dynamic(light: NSColor(srgbRed: 0, green: 0.478, blue: 1, alpha: 1),
                               dark:  NSColor(srgbRed: 0.039, green: 0.518, blue: 1, alpha: 1))
    static let good  = Color(red: 52/255, green: 199/255, blue: 89/255)
    static let amber = Color(red: 1, green: 0.624, blue: 0.039)

    /// Load level to Apple's system-color ramp: green, to yellow, to orange, to red.
    static func load(_ pct: Double) -> Color {
        let stops: [(Double, (Double, Double, Double))] = [
            (0,  (52, 199, 89)), (55, (52, 199, 89)),
            (70, (255, 204, 0)), (85, (255, 149, 0)), (100, (255, 59, 48))
        ]
        let p = min(max(pct, 0), 100)
        for i in 0..<(stops.count - 1) {
            let (a, ca) = stops[i], (b, cb) = stops[i + 1]
            if p <= b {
                let t = (p - a) / max(b - a, 0.0001)
                return Color(red: (ca.0 + (cb.0 - ca.0) * t) / 255,
                             green: (ca.1 + (cb.1 - ca.1) * t) / 255,
                             blue: (ca.2 + (cb.2 - ca.2) * t) / 255)
            }
        }
        return Color(red: 1, green: 59/255, blue: 48/255)
    }
}

/// The system blur behind a surface, so the widget and popover read as native
/// vibrancy rather than a flat panel.
struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        v.isEmphasized = true
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blending
    }
}

extension Font {
    /// Tabular monospaced digits for every number that lines up in a column.
    static func vitalsNumber(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
