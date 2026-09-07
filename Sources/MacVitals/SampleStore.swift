import Foundation
import Combine
import VitalsCore

/// Drives the `Monitor` on a 1 Hz timer and keeps a rolling minute of history
/// for the sparklines. The views observe this. The CLI and MCP server talk to
/// `Monitor` directly, so this GUI-only history layer stays out of the core.
@MainActor
final class SampleStore: ObservableObject {
    @Published private(set) var latest: Snapshot = .placeholder
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var gpuHistory: [Double] = []
    @Published private(set) var memHistory: [Double] = []

    private let monitor = Monitor()
    private var timer: Timer?
    private let capacity = 60

    init() {
        _ = monitor.sample() // prime the delta baseline
        start()
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
        push(&cpuHistory, s.cpu.usage)
        push(&gpuHistory, s.gpu.usage)
        push(&memHistory, s.memory.usedPercent)
    }

    private func push(_ buffer: inout [Double], _ value: Double) {
        buffer.append(value)
        if buffer.count > capacity { buffer.removeFirst(buffer.count - capacity) }
    }
}
