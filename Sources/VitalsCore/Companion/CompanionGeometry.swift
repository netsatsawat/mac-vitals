import Foundation

/// How a pack is shrunk to fit its box. mycat's rule, kept exactly: one scale for
/// the still, the sprites, the eye centres and the travel radius (so the eyes stay
/// where the artist put them), shrink only, and the fitted size rounded to whole
/// points the way the original rounds to whole pixels.
public struct CompanionFit: Sendable, Equatable {
    public let scale: Double
    /// Fitted size in points, rounded.
    public let width: Double
    public let height: Double

    public init(nativeWidth: Double, nativeHeight: Double, maxWidth: Double, maxHeight: Double) {
        let w = max(nativeWidth, 1), h = max(nativeHeight, 1)
        let s = min(maxWidth / w, maxHeight / h, 1.0)
        scale = s
        width = max(1, (w * s).rounded())
        height = max(1, (h * s).rounded())
    }

    /// A clip is scaled so its on-screen height matches the still's, keeping its own
    /// aspect. The clip is often authored on a different canvas than static.png;
    /// sharing the still's scale would shrink it, fitting it to the box on its own
    /// would change its height, and either way the body would jump when a clip
    /// starts. Matching heights keeps her the same size in every state.
    public static func clipScale(fittedHeight: Double, clipNativeHeight: Double) -> Double {
        fittedHeight / max(clipNativeHeight, 1)
    }
}

/// Where the pupils look. Pure functions over points in character content space
/// (top-left origin, points), so the view and the offscreen renderer share them
/// and a unit test can pin every branch.
public enum CompanionGaze {
    /// AppKit screen space (origin bottom-left of the primary display, y up) to
    /// content space for a borderless panel whose content fills its frame:
    /// x is measured from the frame's left edge, y down from its top edge.
    public static func contentPoint(screenX: Double, screenY: Double, frameMinX: Double, frameMaxY: Double) -> CompanionPoint {
        CompanionPoint(x: screenX - frameMinX, y: frameMaxY - screenY)
    }

    /// Where she looks when the cursor is not on her display: a point between and
    /// just below the eyes, so the pupils converge and drop, as if at her own nose.
    public static func nose(left: CompanionPoint, right: CompanionPoint, travel: Double) -> CompanionPoint {
        CompanionPoint(x: (left.x + right.x) / 2, y: max(left.y, right.y) + 2 * travel)
    }

    /// Pupil offsets from their rest centres, mycat's rule verbatim. Both pupils
    /// share one angle, that of whichever eye is nearer the target. Outside the
    /// eye pair they move in parallel; when the target sits horizontally between
    /// the sockets the far eye mirrors so the gaze converges. Sockets at equal
    /// height make the two cases meet continuously. A 1 pt dead zone stops a
    /// pupil spinning when the cursor rests on the eye itself.
    public static func offsets(target: CompanionPoint, left: CompanionPoint, right: CompanionPoint,
                               travel: Double) -> (left: CompanionPoint, right: CompanionPoint) {
        func dist(_ a: CompanionPoint, _ b: CompanionPoint) -> Double {
            ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
        }
        func aim(_ e: CompanionPoint) -> CompanionPoint {
            let d = dist(target, e)
            return d > 1 ? CompanionPoint(x: (target.x - e.x) / d * travel, y: (target.y - e.y) / d * travel)
                         : CompanionPoint(x: 0, y: 0)
        }
        let leftNearer = dist(target, left) <= dist(target, right)
        let base = aim(leftNearer ? left : right)
        if left.x < target.x && target.x < right.x {
            let mirrored = CompanionPoint(x: -base.x, y: base.y)
            return leftNearer ? (base, mirrored) : (mirrored, base)
        }
        return (base, base)
    }

    /// The repaint gate: true when any component of either offset changed by at
    /// least `atLeast` points. A tenth of a point is a fifth of a device pixel at
    /// 2x, invisible as quantisation, and it filters far-cursor jitter.
    public static func moved(_ a: (left: CompanionPoint, right: CompanionPoint),
                             _ b: (left: CompanionPoint, right: CompanionPoint), atLeast: Double) -> Bool {
        abs(a.left.x - b.left.x) >= atLeast || abs(a.left.y - b.left.y) >= atLeast
            || abs(a.right.x - b.right.x) >= atLeast || abs(a.right.y - b.right.y) >= atLeast
    }
}

/// GIF frame timing. ImageIO reports an unclamped and a clamped delay; the
/// unclamped one is the author's number when present. A zero or near-zero delay
/// is a legacy encoder quirk and every browser shows it as 100 ms, so we do too.
public enum CompanionClipTiming {
    public static func frameDelay(unclamped: Double?, clamped: Double?) -> Double {
        let v = unclamped ?? clamped ?? 0.1
        return v <= 0.01 ? 0.1 : v
    }
}
