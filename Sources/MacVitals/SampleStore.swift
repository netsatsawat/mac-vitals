import Foundation
import Combine
import VitalsCore

/// Drives the `Monitor` on a 1 Hz timer and keeps three resolutions:
/// live 1-second detail in memory (an hour) for the short ranges, 1-minute
/// averages persisted for days, and 1-hour averages persisted for a year. The
/// long ranges read the persisted tiers, so they survive quits and fill over time.
@MainActor
final class SampleStore: ObservableObject {
    @Published private(set) var latest: Snapshot = .placeholder
    @Published private(set) var history: [Snapshot] = []
    @Published private(set) var minutes: [MinuteSample] = []
    @Published private(set) var hours: [MinuteSample] = []

    private let monitor = Monitor()
    private let minutesStore: HistoryStore?
    private let hoursStore: HistoryStore?
    private var timer: Timer?
    private var minuteAccumulator: [Snapshot] = []
    private var hourAccumulator: [MinuteSample] = []
    private let capacity = 3600 // one hour of 1-second detail

    /// Last sixty seconds of each metric, for the small sparklines.
    var cpuHistory: [Double] { history.suffix(60).map(\.cpu.usage) }
    var gpuHistory: [Double] { history.suffix(60).map(\.gpu.usage) }
    var memHistory: [Double] { history.suffix(60).map(\.memory.usedPercent) }

    init() {
        minutesStore = HistoryStore(filename: "minutes.ndjson", retention: 8 * 24 * 60)   // 8 days
        hoursStore = HistoryStore(filename: "hours.ndjson", retention: 400 * 24)          // ~13 months
        minutes = minutesStore?.samples ?? []
        hours = hoursStore?.samples ?? []
        _ = monitor.sample() // prime the delta baseline
        start()
    }

    /// Seeded store with no live timer or persistence, for offscreen rendering.
    init(seed: [Snapshot], minutes: [MinuteSample] = [], hours: [MinuteSample] = []) {
        minutesStore = nil
        hoursStore = nil
        history = seed
        self.minutes = minutes
        self.hours = hours
        latest = seed.last ?? .placeholder
    }

    func start() {
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func tick() {
        let s = monitor.sample()
        latest = s
        history.append(s)
        if history.count > capacity { history.removeFirst(history.count - capacity) }

        minuteAccumulator.append(s)
        guard minuteAccumulator.count >= 60 else { return }

        let minute = MinuteSample(from: minuteAccumulator)
        minuteAccumulator.removeAll(keepingCapacity: true)
        minutesStore?.append(minute)
        minutes = minutesStore?.samples ?? (minutes + [minute])

        hourAccumulator.append(minute)
        if hourAccumulator.count >= 60 {
            let hour = MinuteSample(rollingUp: hourAccumulator)
            hourAccumulator.removeAll(keepingCapacity: true)
            hoursStore?.append(hour)
            hours = hoursStore?.samples ?? (hours + [hour])
        }
    }
}
