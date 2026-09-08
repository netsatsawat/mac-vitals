import Foundation
import Combine
import VitalsCore

/// Drives the `Monitor` on a 1 Hz timer. Keeps a live hour of 1-second detail in
/// memory for the short ranges, and rolls each minute into a persisted average so
/// the long ranges (6h, 24h, 7d) survive quits and fill in over time.
@MainActor
final class SampleStore: ObservableObject {
    @Published private(set) var latest: Snapshot = .placeholder
    @Published private(set) var history: [Snapshot] = []
    @Published private(set) var minutes: [MinuteSample] = []

    private let monitor = Monitor()
    private let historyStore: HistoryStore?
    private var timer: Timer?
    private var minuteAccumulator: [Snapshot] = []
    private let capacity = 3600 // one hour of 1-second detail

    /// Last sixty seconds of each metric, for the small sparklines.
    var cpuHistory: [Double] { history.suffix(60).map(\.cpu.usage) }
    var gpuHistory: [Double] { history.suffix(60).map(\.gpu.usage) }
    var memHistory: [Double] { history.suffix(60).map(\.memory.usedPercent) }

    init() {
        historyStore = HistoryStore()
        minutes = historyStore?.minutes ?? []
        _ = monitor.sample() // prime the delta baseline
        start()
    }

    /// Seeded store with no live timer or persistence, for offscreen rendering.
    init(seed: [Snapshot], minutes: [MinuteSample] = []) {
        historyStore = nil
        history = seed
        self.minutes = minutes
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
        if minuteAccumulator.count >= 60 {
            let sample = MinuteSample(from: minuteAccumulator)
            minuteAccumulator.removeAll(keepingCapacity: true)
            historyStore?.append(sample)
            minutes = historyStore?.minutes ?? (minutes + [sample])
        }
    }
}
