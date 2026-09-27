import AppKit
import ImageIO
import VitalsCore

/// Where every part of the character sits, in points, with the origin at the
/// top-left of her box (the pack's own orientation). The view and the offscreen
/// composer both place layers through this, so a render strip shows exactly what
/// the panel will.
struct CompanionLayout {
    /// The panel's content size.
    let box: CGSize
    /// Scale from static.png pixels to points.
    let scale: Double
    /// Where static.png lands inside the box, and its size in points.
    let stillOrigin: CGPoint
    let stillSize: CGSize
    /// static.png's native pixel size, so rasters on its canvas are placed exactly.
    let staticNative: CGSize
    /// Eye centres in box points, nil when the pack has no eyes.
    let eyeLeft: CGPoint?
    let eyeRight: CGPoint?
    let travel: Double
    let spriteSize: CGSize

    /// Where a body raster of the given NATIVE pixel size goes. Anything on
    /// static.png's canvas lands on the still rect exactly. Any other canvas is
    /// scaled so its height matches the still's, centred across the box and
    /// sitting on its floor, so a clip drawn on a wider canvas does not shift her.
    /// Called once per raster at load time; the result travels with the raster.
    func bodyRect(nativeWidth: Int, nativeHeight: Int) -> CGRect {
        let w = Double(nativeWidth), h = Double(nativeHeight)
        if w == staticNative.width && h == staticNative.height {
            return CGRect(origin: stillOrigin, size: stillSize)
        }
        let s = CompanionFit.clipScale(fittedHeight: stillSize.height, clipNativeHeight: h)
        let fw = max(1, (w * s).rounded())
        return CGRect(x: ((box.width - fw) / 2).rounded(), y: box.height - stillSize.height,
                      width: fw, height: stillSize.height)
    }

    func irisRect(eye: CGPoint, offset: CompanionPoint) -> CGRect {
        CGRect(x: eye.x + offset.x - spriteSize.width / 2, y: eye.y + offset.y - spriteSize.height / 2,
               width: spriteSize.width, height: spriteSize.height)
    }

    var eyePoints: (left: CompanionPoint, right: CompanionPoint)? {
        guard let l = eyeLeft, let r = eyeRight else { return nil }
        return (CompanionPoint(x: l.x, y: l.y), CompanionPoint(x: r.x, y: r.y))
    }

    /// Top-left rect to the bottom-left frame CALayer and CGContext use.
    func flipped(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: box.height - r.maxY, width: r.width, height: r.height)
    }
}

/// A body raster drawn at its on-screen size, with the box rect it was drawn for.
struct CompanionRaster {
    let image: CGImage
    /// Points, top-left origin.
    let rect: CGRect
}

/// A character pack in memory: config, rasters already drawn at their on-screen
/// size (two device pixels per point), and the asset manifest the engine reasons
/// over. Loaded once when the companion is switched on, freed when she is off.
final class CompanionPack {
    /// SwiftPM's name for the MacVitals target's resource bundle. Resolved by hand
    /// because SwiftPM's generated accessor traps when the bundle is not where
    /// the build put it, and the .app moves it into Contents/Resources.
    static let bundleName = "mac-vitals_MacVitals.bundle"
    /// Device pixels per point for the fitted rasters.
    static let rasterScale: CGFloat = 2

    let url: URL
    let config: CompanionConfig
    let assets: CompanionAssets
    let layout: CompanionLayout
    private let stills: [String: CompanionRaster]
    private let clips: [String: [CompanionRaster]]
    /// Costume overlays, keyed by outfit name (the part after `outfit_`).
    private let outfits: [String: CompanionRaster]
    let eyeLeft: CGImage?
    let eyeRight: CGImage?

    var name: String { config.name }
    /// The outfits this pack has art for.
    var outfitNames: Set<String> { Set(outfits.keys) }
    func outfit(_ name: String) -> CompanionRaster? { outfits[name] }

    /// A pack folder by name: the user's own folder first, then the one shipped
    /// in the app. Nil when neither has a static.png.
    static func locate(name: String) -> URL? {
        let fm = FileManager.default
        var candidates: [URL] = []
        if let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            candidates.append(support.appendingPathComponent("MacVitals/Companion/\(name)", isDirectory: true))
        }
        if let res = Bundle.main.resourceURL {
            candidates.append(res.appendingPathComponent("\(bundleName)/Companion/\(name)", isDirectory: true))
        }
        return candidates.first { fm.fileExists(atPath: $0.appendingPathComponent("static.png").path) }
    }

    /// A folder path (contains a slash) or a pack name.
    static func resolve(spec: String) -> URL? {
        if spec.contains("/") {
            let url = URL(fileURLWithPath: (spec as NSString).expandingTildeInPath, isDirectory: true)
            return FileManager.default.fileExists(atPath: url.appendingPathComponent("static.png").path) ? url : nil
        }
        return locate(name: spec)
    }

    static func load(url: URL) -> CompanionPack? {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: url.path) else { return nil }
        var nativeStills: [String: CGImage] = [:]
        var gifData: [String: Data] = [:]
        var delays: [String: [Double]] = [:]
        // Two clips with identical bytes (yuna's wink is both idle1 and click1)
        // decode once and share their frames.
        var decodedGIFs: [Data: (frames: [CGImage], delays: [Double])] = [:]
        for file in names.sorted() {
            // Names are matched in lower case, so a pack saved as Blink.PNG on a
            // case-insensitive disk still works.
            let ext = (file as NSString).pathExtension.lowercased()
            let base = (file as NSString).deletingPathExtension.lowercased()
            let fileURL = url.appendingPathComponent(file)
            if ext == "png" {
                if let img = stillImage(at: fileURL) { nativeStills[base] = img }
            } else if ext == "gif" {
                guard let data = try? Data(contentsOf: fileURL) else { continue }
                let decoded = decodedGIFs[data] ?? gifFrames(data)
                guard !decoded.frames.isEmpty else { continue }
                decodedGIFs[data] = decoded
                gifData[base] = data
                delays[base] = decoded.delays
            }
        }
        guard let staticImage = nativeStills["static"] else { return nil }
        let eyeLeft = nativeStills.removeValue(forKey: "eye_left")
        let eyeRight = nativeStills.removeValue(forKey: "eye_right")
        // Costume overlays live under `outfit_<name>.png`. Pull them out so they
        // are not counted as state stills.
        var nativeOutfits: [String: CGImage] = [:]
        for key in nativeStills.keys where key.hasPrefix("outfit_") {
            nativeOutfits[String(key.dropFirst("outfit_".count))] = nativeStills.removeValue(forKey: key)
        }

        let hasBlink = nativeStills["blink"] != nil
        let configData = (try? Data(contentsOf: url.appendingPathComponent("config.json"))) ?? Data("{}".utf8)
        let config = CompanionConfig.decode(configData, folderName: url.lastPathComponent, hasBlink: hasBlink)
            ?? {
                NSLog("companion: %@/config.json is not JSON, using defaults", url.lastPathComponent)
                return CompanionConfig.decode(Data("{}".utf8), folderName: url.lastPathComponent, hasBlink: hasBlink)!
            }()

        func pool(_ prefix: String) -> [String] {
            gifData.keys.filter { $0.hasPrefix(prefix) && $0.dropFirst(prefix.count).allSatisfy(\.isNumber) }.sorted()
        }
        let hasEyes = eyeLeft != nil && eyeRight != nil && config.eyes != nil
        let assets = CompanionAssets(stills: Set(nativeStills.keys), clips: delays,
                                     idlePool: pool("idle"), clickPool: pool("click"), hungryPool: pool("hungry"),
                                     hasEyes: hasEyes, config: config)

        let staticNative = CGSize(width: staticImage.width, height: staticImage.height)
        let fit = CompanionFit(nativeWidth: staticNative.width, nativeHeight: staticNative.height,
                               maxWidth: config.maxWidth, maxHeight: config.maxHeight)
        // The box is as wide as the widest fitted raster so no clip is clipped.
        // Same rule as bodyRect: static's own canvas is the still width exactly.
        var boxWidth = fit.width
        func fittedWidth(_ img: CGImage) -> Double {
            if Double(img.width) == staticNative.width && Double(img.height) == staticNative.height { return fit.width }
            let s = CompanionFit.clipScale(fittedHeight: fit.height, clipNativeHeight: Double(img.height))
            return max(1, (Double(img.width) * s).rounded())
        }
        for img in nativeStills.values { boxWidth = max(boxWidth, fittedWidth(img)) }
        for decoded in decodedGIFs.values {
            if let f = decoded.frames.first { boxWidth = max(boxWidth, fittedWidth(f)) }
        }
        let box = CGSize(width: boxWidth, height: fit.height)
        let stillOrigin = CGPoint(x: ((boxWidth - fit.width) / 2).rounded(), y: 0)
        let stillSize = CGSize(width: fit.width, height: fit.height)
        // The eyes map through the same per-axis scale the still is drawn with
        // (its rounded fitted size over its native size), so a pupil lands on its
        // socket pixel even when rounding nudges the fit.
        let sx = stillSize.width / staticNative.width, sy = stillSize.height / staticNative.height
        var left: CGPoint? = nil, right: CGPoint? = nil
        var sprite = CGSize.zero
        if hasEyes, let e = config.eyes, let sl = eyeLeft {
            left = CGPoint(x: stillOrigin.x + e.left.x * sx, y: stillOrigin.y + e.left.y * sy)
            right = CGPoint(x: stillOrigin.x + e.right.x * sx, y: stillOrigin.y + e.right.y * sy)
            sprite = CGSize(width: Double(sl.width) * sx, height: Double(sl.height) * sy)
        }
        let layout = CompanionLayout(box: box, scale: fit.scale, stillOrigin: stillOrigin, stillSize: stillSize,
                                     staticNative: staticNative, eyeLeft: left, eyeRight: right,
                                     travel: (config.eyes?.travelRadius ?? 0) * fit.scale, spriteSize: sprite)

        // Draw every body raster once at its on-screen size, keep only that, and
        // keep the rect it was drawn for beside it. Native decodes of a 669x1243
        // still are 3.3 MB each; fitted ones are under 1 MB, and every later
        // layer swap uploads the small one.
        func fitted(_ img: CGImage) -> CompanionRaster {
            let rect = layout.bodyRect(nativeWidth: img.width, nativeHeight: img.height)
            return CompanionRaster(image: redraw(img, to: rect), rect: rect)
        }
        let stills = nativeStills.mapValues(fitted)
        let outfits = nativeOutfits.mapValues(fitted)
        var fittedGIFs: [Data: [CompanionRaster]] = [:]
        for (data, decoded) in decodedGIFs { fittedGIFs[data] = decoded.frames.map(fitted) }
        var clips: [String: [CompanionRaster]] = [:]
        for (key, data) in gifData { clips[key] = fittedGIFs[data] }

        return CompanionPack(url: url, config: config, assets: assets, layout: layout,
                             stills: stills, clips: clips, outfits: outfits,
                             eyeLeft: eyeLeft, eyeRight: eyeRight)
    }

    private init(url: URL, config: CompanionConfig, assets: CompanionAssets, layout: CompanionLayout,
                 stills: [String: CompanionRaster], clips: [String: [CompanionRaster]],
                 outfits: [String: CompanionRaster], eyeLeft: CGImage?, eyeRight: CGImage?) {
        self.url = url; self.config = config; self.assets = assets; self.layout = layout
        self.stills = stills; self.clips = clips; self.outfits = outfits
        self.eyeLeft = eyeLeft; self.eyeRight = eyeRight
    }

    /// An overlay draws only when the body is on static's canvas (a still or a
    /// same-canvas clip), so it lines up with her. Its rect is the still rect.
    var stillRect: CGRect { CGRect(origin: layout.stillOrigin, size: layout.stillSize) }

    /// The raster for a frame. A still the engine names but the folder lacks
    /// (it never should: the manifest comes from the same scan) falls back to static.
    func raster(for asset: CompanionFrame.Asset) -> CompanionRaster? {
        switch asset {
        case .still(let name): return stills[name] ?? stills["static"]
        case .clip(let name, let i):
            guard let frames = clips[name], !frames.isEmpty else { return stills["static"] }
            return frames[min(max(i, 0), frames.count - 1)]
        }
    }

    // MARK: - Rasters

    /// A body raster redrawn at the size of its rect, in device pixels.
    private static func redraw(_ img: CGImage, to rect: CGRect) -> CGImage {
        let w = Int(rect.width * rasterScale), h = Int(rect.height * rasterScale)
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return img }
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? img
    }

    private static func stillImage(at url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    private static func gifFrames(_ data: Data) -> (frames: [CGImage], delays: [Double]) {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return ([], []) }
        let n = CGImageSourceGetCount(src)
        var frames: [CGImage] = []
        var delays: [Double] = []
        for i in 0..<n {
            guard let img = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
            let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
            let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let unclamped = gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double
            let clamped = gif?[kCGImagePropertyGIFDelayTime] as? Double
            frames.append(img)
            delays.append(CompanionClipTiming.frameDelay(unclamped: unclamped, clamped: clamped))
        }
        return (frames, delays)
    }
}
