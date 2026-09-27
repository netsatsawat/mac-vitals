import AppKit
import QuartzCore
import VitalsCore

/// The character on screen: three layers (body, left iris, right iris) whose
/// contents and positions change without any drawing code, so a pupil move is a
/// layer move the window server composites. Layer-hosting rather than
/// layer-backed, so the geometry is plain Core Animation with a bottom-left
/// origin and `CompanionLayout.flipped` does the one conversion.
final class CompanionView: NSView {
    let layout: CompanionLayout
    var onClick: (() -> Void)?

    private let bodyLayer = CALayer()
    private let outfitLayer = CALayer()
    private let irisLeft = CALayer()
    private let irisRight = CALayer()
    private var downEvent: NSEvent?
    private var dragging = false

    init(layout: CompanionLayout, eyeLeft: CGImage?, eyeRight: CGImage?) {
        self.layout = layout
        super.init(frame: CGRect(origin: .zero, size: layout.box))
        let root = CALayer()
        root.isOpaque = false
        root.backgroundColor = nil
        layer = root
        wantsLayer = true

        // Order is z-order: body, then the costume overlay, then the irises on top.
        for l in [bodyLayer, outfitLayer, irisLeft, irisRight] {
            l.contentsGravity = .resize
            l.minificationFilter = .trilinear
            l.magnificationFilter = .linear
            l.isOpaque = false
            l.actions = ["contents": NSNull(), "position": NSNull(), "bounds": NSNull(),
                         "frame": NSNull(), "hidden": NSNull(), "contentsScale": NSNull()]
            root.addSublayer(l)
        }
        irisLeft.contents = eyeLeft
        irisRight.contents = eyeRight
        outfitLayer.isHidden = true
        irisLeft.isHidden = true
        irisRight.isHidden = true
        applyScale()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Layer frames in view coordinates (bottom-left origin), for the probe.
    var layerFrames: (body: CGRect, left: CGRect, right: CGRect, pupilsShown: Bool) {
        (bodyLayer.frame, irisLeft.frame, irisRight.frame, !irisLeft.isHidden)
    }

    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        applyScale()
    }

    private func applyScale() {
        let s = window?.backingScaleFactor ?? 2
        for l in [bodyLayer, outfitLayer, irisLeft, irisRight] { l.contentsScale = s }
    }

    /// Show a costume overlay over the body, or nothing. The overlay sits on
    /// static's canvas, so its frame is the raster's own rect.
    func setOutfit(_ raster: CompanionRaster?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let raster {
            outfitLayer.contents = raster.image
            outfitLayer.frame = layout.flipped(raster.rect)
            outfitLayer.isHidden = false
        } else {
            outfitLayer.isHidden = true
        }
        CATransaction.commit()
    }

    /// Put a frame on screen: the body raster and whether the irises show.
    func show(raster: CompanionRaster, pupils: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bodyLayer.contents = raster.image
        bodyLayer.frame = layout.flipped(raster.rect)
        let showEyes = pupils && layout.eyeLeft != nil
        irisLeft.isHidden = !showEyes
        irisRight.isHidden = !showEyes
        CATransaction.commit()
    }

    func setPupils(_ offsets: (left: CompanionPoint, right: CompanionPoint)) {
        guard let l = layout.eyeLeft, let r = layout.eyeRight else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        irisLeft.frame = layout.flipped(layout.irisRect(eye: l, offset: offsets.left))
        irisRight.frame = layout.flipped(layout.irisRect(eye: r, offset: offsets.right))
        CATransaction.commit()
    }

    // MARK: - Mouse: a short press is a click, a 3 pt move is a drag of the panel.

    override func mouseDown(with event: NSEvent) {
        downEvent = event
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = downEvent, !dragging else { return }
        let a = down.locationInWindow, b = event.locationInWindow
        if hypot(b.x - a.x, b.y - a.y) >= 3 {
            dragging = true
            window?.performDrag(with: down)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if downEvent != nil, !dragging { onClick?() }
        downEvent = nil
        dragging = false
    }
}
