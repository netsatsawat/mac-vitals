import Foundation

/// A point in a character pack's own pixel space: `static.png` pixels, origin at
/// the top-left, y down. The same orientation the pack's config.json uses.
public struct CompanionPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// The parameters a pack's config.json carries, resolved with the mycat defaults so
/// a minimal config (just a name) still yields a usable character. No file paths
/// live here on purpose: the pack folder is scanned for reserved filenames, which
/// is what lets a pack grow one asset at a time without touching its config.
public struct CompanionConfig: Sendable, Equatable {
    public struct Eyes: Sendable, Equatable {
        /// How far a pupil may travel from its rest centre, in static.png pixels.
        public var travelRadius: Double
        public var left: CompanionPoint
        public var right: CompanionPoint
        public init(travelRadius: Double, left: CompanionPoint, right: CompanionPoint) {
            self.travelRadius = travelRadius; self.left = left; self.right = right
        }
    }
    public struct Blink: Sendable, Equatable {
        public var enabled: Bool
        /// Seconds between blinks, drawn uniformly.
        public var every: ClosedRange<Double>
        public var duration: Double
        public init(enabled: Bool, every: ClosedRange<Double>, duration: Double) {
            self.enabled = enabled; self.every = every; self.duration = duration
        }
    }
    public struct Idle: Sendable, Equatable {
        /// Seconds of no input before she turns sleepy (and yawns once, if the pack has a yawn).
        public var yawnAfter: Double
        /// Seconds of no input before she falls asleep.
        public var sleepAfter: Double
        /// Seconds between spontaneous idle clips, drawn uniformly, measured from clip start.
        public var randomEvery: ClosedRange<Double>
        public init(yawnAfter: Double, sleepAfter: Double, randomEvery: ClosedRange<Double>) {
            self.yawnAfter = yawnAfter; self.sleepAfter = sleepAfter; self.randomEvery = randomEvery
        }
    }
    public struct Battery: Sendable, Equatable {
        /// Battery percent at or below which she is hungry (while not charging).
        public var hungryBelow: Double
        /// Seconds between hungry clips while she stays hungry.
        public var every: ClosedRange<Double>
        public init(hungryBelow: Double, every: ClosedRange<Double>) {
            self.hungryBelow = hungryBelow; self.every = every
        }
    }

    public var name: String
    /// The box she is shrunk to fit, in points. Never enlarged.
    public var maxWidth: Double
    public var maxHeight: Double
    /// Nil when the config names no eyes; live pupils then never draw.
    public var eyes: Eyes?
    public var blink: Blink
    /// Seconds the blink frame is held on a click when the pack has no click clip.
    public var clickSquint: Double
    public var idle: Idle
    public var battery: Battery

    public init(name: String, maxWidth: Double, maxHeight: Double, eyes: Eyes?, blink: Blink,
                clickSquint: Double, idle: Idle, battery: Battery) {
        self.name = name; self.maxWidth = maxWidth; self.maxHeight = maxHeight; self.eyes = eyes
        self.blink = blink; self.clickSquint = clickSquint; self.idle = idle; self.battery = battery
    }

    /// Decode a pack's config.json. `hasBlink` (whether blink.png exists) is the
    /// default for `blink.enabled`, as in mycat. Returns nil only for text that is
    /// not JSON. Every missing value, wrong-typed value, or number that makes no
    /// sense (a zero box, a negative delay) falls back to its own default and
    /// leaves the rest of the file intact, so a hand-edited config degrades one
    /// key at a time instead of disabling the character.
    public static func decode(_ data: Data, folderName: String, hasBlink: Bool) -> CompanionConfig? {
        guard let dto = try? JSONDecoder().decode(DTO.self, from: data) else { return nil }
        var eyes: Eyes? = nil
        if let e = dto.eyes, let l = e.left, let r = e.right,
           let lx = l.x, let ly = l.y, let rx = r.x, let ry = r.y,
           [lx, ly, rx, ry].allSatisfy(\.isFinite) {
            eyes = Eyes(travelRadius: atLeastZero(e.travel_radius, or: 0),
                        left: CompanionPoint(x: lx, y: ly), right: CompanionPoint(x: rx, y: ry))
        }
        let name = (dto.name?.isEmpty == false) ? dto.name! : folderName
        return CompanionConfig(
            name: name,
            maxWidth: positive(dto.max_width, or: 200), maxHeight: positive(dto.max_height, or: 400),
            eyes: eyes,
            blink: Blink(enabled: dto.blink?.enabled ?? hasBlink,
                         every: range(dto.blink?.every, or: 3...7),
                         duration: positive(dto.blink?.duration, or: 0.28)),
            clickSquint: atLeastZero(dto.click_squint, or: 0.5),
            idle: Idle(yawnAfter: atLeastZero(dto.idle?.yawn_after, or: 60),
                       sleepAfter: atLeastZero(dto.idle?.sleep_after, or: 300),
                       randomEvery: range(dto.idle?.random_every, or: 25...60)),
            battery: Battery(hungryBelow: atLeastZero(dto.battery?.hungry_below, or: 20),
                             every: range(dto.battery?.every, or: 30...60))
        )
    }

    private static func positive(_ v: Double?, or fallback: Double) -> Double {
        guard let v, v.isFinite, v > 0 else { return fallback }
        return v
    }

    private static func atLeastZero(_ v: Double?, or fallback: Double) -> Double {
        guard let v, v.isFinite, v >= 0 else { return fallback }
        return v
    }

    /// A two-element, finite, non-negative, ascending array becomes a range;
    /// anything else is the default.
    private static func range(_ values: [Double]?, or fallback: ClosedRange<Double>) -> ClosedRange<Double> {
        guard let v = values, v.count == 2, v[0].isFinite, v[1].isFinite, v[0] >= 0, v[0] <= v[1] else { return fallback }
        return v[0]...v[1]
    }

    // Every field is decoded leniently: a missing key, a null, or a value of the
    // wrong type all read as nil, so one odd key never rejects the whole file.
    // (Synthesized Decodable would throw on a wrong type.) Keys match
    // config.json's snake_case verbatim.
    private struct DTO: Decodable {
        struct P: Decodable {
            var x: Double?; var y: Double?
            enum K: String, CodingKey { case x, y }
            init(from d: Decoder) throws {
                let c = try d.container(keyedBy: K.self)
                x = c.lenient(.x); y = c.lenient(.y)
            }
        }
        struct EyesDTO: Decodable {
            var travel_radius: Double?; var left: P?; var right: P?
            enum K: String, CodingKey { case travel_radius, left, right }
            init(from d: Decoder) throws {
                let c = try d.container(keyedBy: K.self)
                travel_radius = c.lenient(.travel_radius); left = c.lenient(.left); right = c.lenient(.right)
            }
        }
        struct BlinkDTO: Decodable {
            var enabled: Bool?; var every: [Double]?; var duration: Double?
            enum K: String, CodingKey { case enabled, every, duration }
            init(from d: Decoder) throws {
                let c = try d.container(keyedBy: K.self)
                enabled = c.lenient(.enabled); every = c.lenient(.every); duration = c.lenient(.duration)
            }
        }
        struct IdleDTO: Decodable {
            var yawn_after: Double?; var sleep_after: Double?; var random_every: [Double]?
            enum K: String, CodingKey { case yawn_after, sleep_after, random_every }
            init(from d: Decoder) throws {
                let c = try d.container(keyedBy: K.self)
                yawn_after = c.lenient(.yawn_after); sleep_after = c.lenient(.sleep_after)
                random_every = c.lenient(.random_every)
            }
        }
        struct BatteryDTO: Decodable {
            var hungry_below: Double?; var every: [Double]?
            enum K: String, CodingKey { case hungry_below, every }
            init(from d: Decoder) throws {
                let c = try d.container(keyedBy: K.self)
                hungry_below = c.lenient(.hungry_below); every = c.lenient(.every)
            }
        }
        var name: String?
        var max_width: Double?
        var max_height: Double?
        var eyes: EyesDTO?
        var blink: BlinkDTO?
        var click_squint: Double?
        var idle: IdleDTO?
        var battery: BatteryDTO?
        enum K: String, CodingKey { case name, max_width, max_height, eyes, blink, click_squint, idle, battery }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: K.self)
            name = c.lenient(.name); max_width = c.lenient(.max_width); max_height = c.lenient(.max_height)
            eyes = c.lenient(.eyes); blink = c.lenient(.blink); click_squint = c.lenient(.click_squint)
            idle = c.lenient(.idle); battery = c.lenient(.battery)
        }
    }
}

private extension KeyedDecodingContainer {
    /// The value when present and of the right type, else nil.
    func lenient<T: Decodable>(_ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }
}
