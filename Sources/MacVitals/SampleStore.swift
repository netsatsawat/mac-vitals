import Foundation
import Combine
import VitalsCore

/// Drives the `Monitor` on a 1 Hz timer and retains an hour of history, so the
/// full window can show the last minute, fifteen minutes, or hour. The popover
/// and widget read the last sixty samples through the convenience accessors.
/// The CLI and MCP server talk to `Monitor` directly, so this stays GUI-only.
@MainActor
final class SampleStore: ObservableObject {
    @Published private(set) var latest: Snapshot = .placeholder
    @Published private(set) var history: [Snapshot] = []

    private let monitor = Monitor()
    private var timer: Timer?
    private let capacity = 3600 // one hour at 1 Hz

    /// Last sixty seconds of each metric, for the small sparklines.
    var cpuHistory: [Double] { history.suffix(60).map(\.cpu.usage) }
    var gpuHistory: [Double] { history.suffix(60).map(\.gpu.usage) }
    var memHistory: [Double] { history.suffix(60).map(\.memory.usedPercent) }

    init() {
        _ = monitor.sample() // prime the delta baseline
        start()
    }

    /// Seeded store with no live timer, for offscreen rendering and previews.
    init(seed: [Snapshot]) {
        history = seed
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
    }
}
