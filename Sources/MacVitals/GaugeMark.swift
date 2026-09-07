import SwiftUI

/// The app's gauge mark, matching the icon: a 270-degree ring with a load-ramp
/// sweep and a center hub, gap at the bottom. Used next to the name in the
/// widget and popover headers so the brand reads on every surface.
struct GaugeMark: View {
    var size: CGFloat = 16

    var body: some View {
        let lw = size * 0.17
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(Palette.track, style: StrokeStyle(lineWidth: lw, lineCap: .round))
            Circle()
                .trim(from: 0, to: 0.56)
                .stroke(
                    AngularGradient(
                        colors: [Palette.good, Palette.amber, Color(red: 1, green: 0.23, blue: 0.19)],
                        center: .center,
                        startAngle: .degrees(0), endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: lw, lineCap: .round)
                )
            Circle().fill(Palette.ink).frame(width: size * 0.17, height: size * 0.17)
        }
        .rotationEffect(.degrees(135)) // move the gap to the bottom, like the icon
        .frame(width: size, height: size)
    }
}
