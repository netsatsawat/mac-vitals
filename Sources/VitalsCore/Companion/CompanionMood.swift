import Foundation

/// What the machine is doing, as the companion sees it. Declaration order is
/// priority: a warning outranks sleep (it is what you want to see when you come
/// back to the desk), sleep outranks work (a long build with nobody at the desk
/// shows a sleeping face until the first input), and awake is always last.
public enum CompanionState: String, CaseIterable, Sendable, Codable {
    case throttling, hot, hungry, asleep, working, sleepy, awake

    /// The reserved still that draws this state, without ".png". Awake has none:
    /// it is static.png with live pupils.
    public var stillName: String? {
        switch self {
        case .throttling: "throttle"
        case .hot: "hot"
        case .hungry: "hungry"
        case .asleep: "sleep"
        case .working: "busy"
        case .sleepy: "sleepy"
        case .awake: nil
        }
    }

    /// The word after "<Name> is" in the menu's status line.
    public var word: String { rawValue }
}

/// The thresholds that turn readings into states. The load and heat numbers are
/// the stops of the popover's own colour ramp (`Palette.load`: green to 55, yellow
/// at 70, orange at 85), so her face changes where the rings and the temperature
/// row change colour, and no character carries its own opinion of what "hot" is.
/// The tick counts are design parameters chosen to stop flapping on a 1 Hz feed,
/// not measurements. The battery and idle values come from the pack's config.
public struct CompanionRules: Sendable, Equatable {
    public var workingEnter: Double = 70
    public var workingExit: Double = 55
    public var hotEnterC: Double = 85
    public var hotExitC: Double = 70
    /// Consecutive ticks above the enter line before a latch sets.
    public var enterTicks: Int = 3
    /// Consecutive ticks below the exit line before a latch clears.
    public var exitTicks: Int = 5
    public var hungryBelow: Double = 20
    public var sleepyAfter: Double = 60
    public var sleepAfter: Double = 300

    public static let `default` = CompanionRules()

    public init() {}

    public init(config: CompanionConfig) {
        self.init()
        hungryBelow = config.battery.hungryBelow
        sleepyAfter = config.idle.yawnAfter
        sleepAfter = config.idle.sleepAfter
    }
}

/// Snapshot plus seconds of system input idle in, an ordered list of active states
/// out. The list, not just the winner, is what the engine wants: a state whose art
/// the pack lacks is skipped for the next active one, so a pack with no busy.png
/// shows awake while the menu still says she is working.
public struct CompanionMood: Sendable {
    public var rules: CompanionRules
    public private(set) var state: CompanionState = .awake
    public private(set) var active: [CompanionState] = [.awake]

    private var workingLatched = false
    private var workingAbove = 0
    private var workingBelow = 0
    private var hotLatched = false
    private var hotAbove = 0
    private var hotBelow = 0
    private var throttling = false
    private var hungry = false

    public init(rules: CompanionRules = .default) { self.rules = rules }

    /// One reading of the machine: advances the latches, then rebuilds the list.
    @discardableResult
    public mutating func update(_ s: Snapshot, idleSeconds: Double) -> CompanionState {
        // Throttling: the OS state is already damped, and the face must agree with
        // the amber menu bar the moment it turns. No availability gate: the string
        // comes from ProcessInfo even on a machine with no SMC reading.
        throttling = s.thermal.pressure == "serious" || s.thermal.pressure == "critical"

        // Working: instantaneous load with a 3-in / 5-out latch and a 15-point band.
        let load = max(s.cpu.usage, s.gpu.available ? s.gpu.usage : 0)
        if workingLatched {
            if load < rules.workingExit {
                workingBelow += 1
                if workingBelow >= rules.exitTicks { workingLatched = false; workingBelow = 0 }
            } else {
                workingBelow = 0
            }
        } else {
            if load >= rules.workingEnter {
                workingAbove += 1
                if workingAbove >= rules.enterTicks { workingLatched = true; workingAbove = 0 }
            } else {
                workingAbove = 0
            }
        }

        // Hot: same latch on the die temperature, and only while the SMC answers.
        if !s.thermal.available {
            hotLatched = false; hotAbove = 0; hotBelow = 0
        } else if hotLatched {
            if s.thermal.socTempC < rules.hotExitC {
                hotBelow += 1
                if hotBelow >= rules.exitTicks { hotLatched = false; hotBelow = 0 }
            } else {
                hotBelow = 0
            }
        } else {
            if s.thermal.socTempC >= rules.hotEnterC {
                hotAbove += 1
                if hotAbove >= rules.enterTicks { hotLatched = true; hotAbove = 0 }
            } else {
                hotAbove = 0
            }
        }

        // Hungry: on battery the percent only falls, so no margin is needed, and
        // charging ends it at once. Desktops never get hungry.
        hungry = s.battery.present && !s.battery.isCharging && s.battery.percent <= rules.hungryBelow

        return refresh(idleSeconds: idleSeconds)
    }

    /// Rebuild the list from the last reading's latches and a new idle time,
    /// without counting another sample. For a click, which resets idle but is not
    /// a reading: fed through `update` it would push the 3-in / 5-out counters.
    @discardableResult
    public mutating func refresh(idleSeconds: Double) -> CompanionState {
        let asleep = idleSeconds >= rules.sleepAfter
        let sleepy = idleSeconds >= rules.sleepyAfter

        var list: [CompanionState] = []
        if throttling { list.append(.throttling) }
        if hotLatched { list.append(.hot) }
        if hungry { list.append(.hungry) }
        if asleep { list.append(.asleep) }
        if workingLatched { list.append(.working) }
        if sleepy { list.append(.sleepy) }
        list.append(.awake)
        active = list
        state = list[0]
        return state
    }
}
