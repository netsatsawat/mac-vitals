import AppKit
import VitalsCore

/// Draws one companion frame offscreen, through the same layout the view uses,
/// so `--render-companion` shows the panel's exact pixels without a display.
enum CompanionComposer {
    /// The box at `scale` device pixels per point. `gaze` is a target in box
    /// points (top-left origin); nil rests the pupils at their centres.
    static func compose(pack: CompanionPack, frame: CompanionFrame, gaze: CompanionPoint?,
                        outfit: CompanionRaster? = nil, scale: CGFloat = 2) -> CGImage? {
        let layout = pack.layout
        let w = Int(layout.box.width * scale), h = Int(layout.box.height * scale)
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        ctx.interpolationQuality = .high

        var onStatic = true
        if let body = pack.raster(for: frame.asset) {
            ctx.draw(body.image, in: layout.flipped(body.rect))
            onStatic = body.rect == pack.stillRect
        }
        // The costume overlay only lines up while the body is on static's canvas.
        if let outfit, onStatic {
            ctx.draw(outfit.image, in: layout.flipped(outfit.rect))
        }
        if frame.drawsPupils, let eyes = layout.eyePoints, let l = pack.eyeLeft, let r = pack.eyeRight,
           let el = layout.eyeLeft, let er = layout.eyeRight {
            let offsets: (left: CompanionPoint, right: CompanionPoint)
            if let g = gaze {
                offsets = CompanionGaze.offsets(target: g, left: eyes.left, right: eyes.right, travel: layout.travel)
            } else {
                offsets = (CompanionPoint(x: 0, y: 0), CompanionPoint(x: 0, y: 0))
            }
            ctx.draw(l, in: layout.flipped(layout.irisRect(eye: el, offset: offsets.left)))
            ctx.draw(r, in: layout.flipped(layout.irisRect(eye: er, offset: offsets.right)))
        }
        return ctx.makeImage()
    }
}
