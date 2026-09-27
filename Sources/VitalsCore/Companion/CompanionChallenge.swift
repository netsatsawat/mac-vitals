import Foundation

/// An outfit the companion earns by doing something over time, read from the same
/// history the charts are drawn from. An unlock is an achievement: once earned it
/// stays earned, so a cool machine that later runs hot keeps both badges. The
/// character shows an outfit only when its pack carries the matching
/// `outfit_<id>.png`; the challenge and the art are independent, so a pack can add
/// a costume for any of these without touching the rules.
public enum CompanionChallenge: String, CaseIterable, Sendable {
    /// A week of the Mac staying cool.
    case cozy
    /// A hot stretch, or a spell of throttling.
    case sunny

    /// The outfit name a pack carries for this, as `outfit_<outfit>.png`.
    public var outfit: String { rawValue }

    /// Menu title.
    public var title: String {
        switch self {
        case .cozy: "Cozy"
        case .sunny: "Sun's out"
        }
    }

    /// One line shown in the menu whether it is earned or still locked.
    public var detail: String {
        switch self {
        case .cozy: "A week of use with the Mac staying cool."
        case .sunny: "A hot stretch, or a spell of throttling."
        }
    }
}

/// The rules that turn recorded history into earned outfits. The numbers here are
/// game-design choices, not measurements, and they are exposed so a pack or a test
/// can retune them. They read the hour tier (`SampleStore.hours`), which is where
/// a multi-day challenge lives.
public struct CompanionChallengeRules: Sendable, Equatable {
    /// Days the machine must stay cool for `cozy`.
    public var coolDays: Double = 7
    /// Recorded hours `cozy` needs per day of the window, on average. The app only
    /// records while it runs and the Mac is awake, so this is a floor on real use,
    /// set low enough for a laptop that sleeps overnight.
    public var minHoursPerDay: Double = 6
    /// The hour-average temperature `cozy` must stay under, in Celsius.
    public var coolCeilingC: Double = 55
    /// Consecutive hot hours that earn `sunny`.
    public var hotRunHours: Int = 2
    /// The hour-average temperature that counts as hot, in Celsius.
    public var hotFloorC: Double = 85

    public static let `default` = CompanionChallengeRules()
    public init() {}
}

public enum CompanionChallenges {
    /// The outfits earned by this history, as of `now`. Pure and order-free, so a
    /// test pins it and the controller unions it into what is already saved.
    public static func unlocked(hours: [Sample], now: Date,
                                rules: CompanionChallengeRules = .default) -> Set<String> {
        var out: Set<String> = []
        for c in CompanionChallenge.allCases where isMet(c, hours: hours, now: now, rules: rules) {
            out.insert(c.outfit)
        }
        return out
    }

    public static func isMet(_ challenge: CompanionChallenge, hours: [Sample], now: Date,
                             rules: CompanionChallengeRules = .default) -> Bool {
        switch challenge {
        case .cozy:
            // The Mac must have been recording across the week, not just twice, and
            // every recorded hour cool and never throttling. The app only records
            // while it runs, so "cool" means the hours it did see. A missing or
            // implausible temperature (no thermal sensor) does not count as cool,
            // so a Mac that reports nothing never earns the badge.
            let window = now.addingTimeInterval(-rules.coolDays * 86_400)
            let recent = hours.filter { $0.t >= window }
            // Enough hours, and spread across the week rather than clustered in a day,
            // so two cool hours far apart do not pass.
            guard recent.count >= Int(rules.coolDays * rules.minHoursPerDay) else { return false }
            let times = recent.map(\.t)
            guard let lo = times.min(), let hi = times.max(),
                  hi.timeIntervalSince(lo) >= (rules.coolDays - 1) * 86_400 else { return false }
            return recent.allSatisfy { s in
                guard let t = s.temp, t > 5 else { return false }
                return t <= rules.coolCeilingC && s.throttled != true
            }
        case .sunny:
            let sorted = hours.sorted { $0.t < $1.t }
            if sorted.contains(where: { $0.throttled == true }) { return true }
            var run = 0
            for s in sorted {
                if let t = s.temp, t >= rules.hotFloorC {
                    run += 1
                    if run >= rules.hotRunHours { return true }
                } else {
                    run = 0
                }
            }
            return false
        }
    }
}
