import Foundation

/// What a pack contains, by name only. The engine never sees a pixel: it decides
/// which asset shows and when the next change is due, and the app draws it.
public struct CompanionAssets: Sendable {
    /// Stills present, by basename without ".png" ("static", "blink", "sleep", "busy", ...).
    public var stills: Set<String>
    /// Clips present, by basename without ".gif", each with its per-frame delays in seconds.
    public var clips: [String: [Double]]
    /// Clip keys matched by prefix and sorted by name: idle*, click*, hungry*.
    public var idlePool: [String]
    public var clickPool: [String]
    public var hungryPool: [String]
    /// Both pupil sprites and an eyes block in the config.
    public var hasEyes: Bool
    public var config: CompanionConfig

    public init(stills: Set<String>, clips: [String: [Double]], idlePool: [String], clickPool: [String],
                hungryPool: [String], hasEyes: Bool, config: CompanionConfig) {
        self.stills = stills; self.clips = clips; self.idlePool = idlePool; self.clickPool = clickPool
        self.hungryPool = hungryPool; self.hasEyes = hasEyes; self.config = config
    }

    public var hasBlink: Bool { stills.contains("blink") }

    /// Whether a state has art to show. Asleep counts a sleep_in clip as art (the
    /// held frame then falls back to static), hungry counts its clip pool.
    public func has(_ state: CompanionState) -> Bool {
        switch state {
        case .awake: return true
        case .asleep: return stills.contains("sleep") || clips["sleep_in"] != nil
        case .hungry: return stills.contains("hungry") || !hungryPool.isEmpty
        default: return stills.contains(state.stillName ?? "")
        }
    }
}

/// One thing to draw, and when it stops being right.
public struct CompanionFrame: Equatable, Sendable {
    public enum Asset: Equatable, Sendable {
        case still(String)
        case clip(String, Int)
    }
    /// open: static with live pupils. blink: the blink still. anim: a clip frame.
    /// held: a state still, no pupils and no blink.
    public enum Mode: Equatable, Sendable { case open, blink, anim, held }

    public var asset: Asset
    public var mode: Mode
    /// Monotonic time at which the frame changes on its own, or nil when only an
    /// input or a new reading can change it. The controller arms one timer for it.
    public var nextChange: Double?

    public var drawsPupils: Bool { mode == .open }

    public init(asset: Asset, mode: Mode, nextChange: Double?) {
        self.asset = asset; self.mode = mode; self.nextChange = nextChange
    }
}

/// The frame machine: mycat's `update_pack_frame` ported over an asset manifest.
/// One state is shown at a time, chosen by walking the mood's ordered active list
/// to the first state the pack has art for. A one-shot clip plays to completion
/// and settles; sleep has entry and exit clips; the hungry and idle pools play a
/// random member on their own schedule; blink is a timed swap of the blink still;
/// a click plays a click clip or squints. Time is an injected monotonic clock and
/// randomness an injected generator, so every branch is testable without a window.
public struct CompanionEngine {
    public var assets: CompanionAssets
    public var rng: any RandomNumberGenerator
    /// The state currently shown (after asset gating), not the mood's winner.
    public private(set) var displayed: CompanionState = .awake

    private struct Playing { var key: String; var start: Double; var total: Double }
    private var playing: Playing?
    private var active: [CompanionState] = [.awake]
    private var squintUntil: Double = -1
    private var nextBlink: Double
    private var nextIdle: Double
    private var nextHungry: Double
    private var yawned = false
    /// Deadlines are compared with a microsecond of slack: a timer armed for
    /// `start + 0.45` fires at a double that can sit a hair under the sum, and
    /// without slack the same frame would come back once more before advancing.
    private let eps = 1e-6

    public init(assets: CompanionAssets, now: Double, rng: any RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.assets = assets
        self.rng = rng
        // Set after the stored properties so the helpers can use the generator.
        nextBlink = 0; nextIdle = 0; nextHungry = now
        nextBlink = now + uniform(assets.config.blink.every)
        nextIdle = now + uniform(assets.config.idle.randomEvery)
    }

    // MARK: - Inputs

    /// A new ordered active list from the mood (once a second). Resolves the shown
    /// state and starts a transition clip when the pack has one.
    public mutating func update(active: [CompanionState], now: Double) {
        self.active = active
        let target = resolve(active)
        if target != displayed {
            let wasAsleep = displayed == .asleep
            displayed = target
            if wasAsleep, let clip = assets.clips["sleep_out"] {
                start(key: "sleep_out", delays: clip, now: now)
            } else if target == .asleep, let clip = assets.clips["sleep_in"] {
                start(key: "sleep_in", delays: clip, now: now)
            }
        }
        // The yawn follows the mood, not the art: a pack with yawn.gif and no
        // sleepy.png still yawns once when she turns drowsy, then looks awake
        // (mycat's behaviour). Not while a warning still or sleep itself shows.
        let drowsy = active.contains(.sleepy) || active.contains(.asleep)
        if drowsy, !yawned, target == .sleepy || target == .awake, let clip = assets.clips["yawn"] {
            yawned = true
            start(key: "yawn", delays: clip, now: now)
        }
        // The latch clears once she is neither sleepy nor asleep, so the next idle
        // stretch yawns again.
        if !drowsy { yawned = false }
    }

    /// She was clicked. Awake (or hungry between clips) reacts with a click clip,
    /// else a squint; asleep, sleepy and held vitals stills ignore it (the caller
    /// re-ticks with fresh idle time, which is what actually wakes her).
    public mutating func click(now: Double) {
        guard displayed == .awake || displayed == .hungry else { return }
        if let key = pick(assets.clickPool), let clip = assets.clips[key] {
            start(key: key, delays: clip, now: now)
        } else if assets.hasBlink {
            squintUntil = now + assets.config.clickSquint
        }
    }

    // MARK: - Output

    /// The frame for `now`, advancing clip playback and the blink and pool
    /// schedules as it goes.
    public mutating func frame(now: Double) -> CompanionFrame {
        if let p = playing {
            let age = now - p.start
            if age + eps < p.total, let delays = assets.clips[p.key] {
                var acc = 0.0
                for (i, d) in delays.enumerated() {
                    acc += d
                    if age + eps < acc { return CompanionFrame(asset: .clip(p.key, i), mode: .anim, nextChange: p.start + acc) }
                }
            }
            playing = nil
        }

        switch displayed {
        case .awake:
            return openFrame(now: now, hungryDue: nil)
        case .hungry:
            if let key = pick(assets.hungryPool, when: now + eps >= nextHungry), let clip = assets.clips[key] {
                nextHungry = now + uniform(assets.config.battery.every)
                start(key: key, delays: clip, now: now)
                return CompanionFrame(asset: .clip(key, 0), mode: .anim, nextChange: now + clip[0])
            }
            let due: Double? = assets.hungryPool.isEmpty ? nil : nextHungry
            if assets.stills.contains("hungry") {
                return CompanionFrame(asset: .still("hungry"), mode: .held, nextChange: due)
            }
            return openFrame(now: now, hungryDue: due)
        case .asleep:
            return CompanionFrame(asset: .still(assets.stills.contains("sleep") ? "sleep" : "static"), mode: .held, nextChange: nil)
        case .throttling, .hot, .working, .sleepy:
            return CompanionFrame(asset: .still(displayed.stillName ?? "static"), mode: .held, nextChange: nil)
        }
    }

    // MARK: - Helpers

    private func resolve(_ list: [CompanionState]) -> CompanionState {
        for s in list where assets.has(s) { return s }
        return .awake
    }

    private mutating func start(key: String, delays: [Double], now: Double) {
        playing = Playing(key: key, start: now, total: delays.reduce(0, +))
    }

    /// The awake branch: a due idle clip, else a blink in progress or due, else
    /// static with live pupils and the earliest of the pending deadlines.
    private mutating func openFrame(now: Double, hungryDue: Double?) -> CompanionFrame {
        if let key = pick(assets.idlePool, when: now + eps >= nextIdle), let clip = assets.clips[key] {
            nextIdle = now + uniform(assets.config.idle.randomEvery)
            start(key: key, delays: clip, now: now)
            return CompanionFrame(asset: .clip(key, 0), mode: .anim, nextChange: now + clip[0])
        }
        let blinks = assets.config.blink.enabled && assets.hasBlink
        if blinks && now + eps >= nextBlink {
            squintUntil = now + assets.config.blink.duration
            nextBlink = now + uniform(assets.config.blink.every)
        }
        if now + eps < squintUntil {
            return CompanionFrame(asset: .still("blink"), mode: .blink, nextChange: squintUntil)
        }
        var deadlines: [Double] = []
        if blinks { deadlines.append(nextBlink) }
        if !assets.idlePool.isEmpty { deadlines.append(nextIdle) }
        if let h = hungryDue { deadlines.append(h) }
        return CompanionFrame(asset: .still("static"), mode: .open, nextChange: deadlines.min())
    }

    private mutating func uniform(_ r: ClosedRange<Double>) -> Double {
        r.lowerBound >= r.upperBound ? r.lowerBound : Double.random(in: r, using: &rng)
    }

    private mutating func pick(_ pool: [String], when due: Bool = true) -> String? {
        guard due, !pool.isEmpty else { return nil }
        return pool.count == 1 ? pool[0] : pool[Int.random(in: 0..<pool.count, using: &rng)]
    }
}
