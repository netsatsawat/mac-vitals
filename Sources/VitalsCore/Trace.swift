import Foundation

/// What a bracketed piece of work cost the machine. Averages and peaks for the
/// rates, totals for the throughput, and energy integrated from power over the
/// window. This is the "measure this task" idea, shared by the CLI and MCP server.
public struct TraceResult: Codable, Sendable {
    public var durationSeconds: Double
    public var samples: Int
    public var cpuAvgPercent: Double
    public var cpuPeakPercent: Double
    public var gpuAvgPercent: Double
    public var gpuPeakPercent: Double
    public var avgWatts: Double
    public var energyWattHours: Double
    public var networkDownBytes: Double
    public var networkUpBytes: Double
    public var diskReadBytes: Double
    public var diskWriteBytes: Double
    public var socTempPeakC: Double
    /// Whether the machine thermally throttled at any point during the window.
    public var throttled: Bool
    /// The most swap in use at any point during the window, in bytes.
    public var peakSwapBytes: Double
}

/// Accumulates snapshots into a `TraceResult`. Feed it each 1 Hz sample between
/// the start and the stop of the work being measured.
public struct Trace {
    private let start: Date
    private var lastTime: Date
    private var samples = 0
    private var cpuSum = 0.0, cpuPeak = 0.0
    private var gpuSum = 0.0, gpuPeak = 0.0
    private var energyJoules = 0.0
    private var netDown = 0.0, netUp = 0.0
    private var diskRead = 0.0, diskWrite = 0.0
    private var tempPeak = 0.0
    private var didThrottle = false
    private var swapPeak = 0.0

    public init(start: Date = Date()) {
        self.start = start
        self.lastTime = start
    }

    public mutating func add(_ s: Snapshot) {
        add(Sample(from: s))
    }

    /// Same accumulation from a compact sample, so the app can measure a task by
    /// replaying its stored per-second history.
    public mutating func add(_ s: Sample) {
        let dt = max(0, s.t.timeIntervalSince(lastTime))
        lastTime = s.t
        samples += 1
        cpuSum += s.cpu; cpuPeak = max(cpuPeak, s.cpu)
        gpuSum += s.gpu; gpuPeak = max(gpuPeak, s.gpu)
        energyJoules += s.watts * dt
        netDown += s.netDown * dt
        netUp += s.netUp * dt
        diskRead += s.diskRead * dt
        diskWrite += s.diskWrite * dt
        tempPeak = max(tempPeak, s.temp ?? 0)
        if s.throttled == true { didThrottle = true }
        swapPeak = max(swapPeak, s.swap ?? 0)
    }

    public func result() -> TraceResult {
        let duration = lastTime.timeIntervalSince(start)
        let n = Double(max(samples, 1))
        return TraceResult(
            durationSeconds: duration,
            samples: samples,
            cpuAvgPercent: cpuSum / n,
            cpuPeakPercent: cpuPeak,
            gpuAvgPercent: gpuSum / n,
            gpuPeakPercent: gpuPeak,
            avgWatts: duration > 0 ? energyJoules / duration : 0,
            energyWattHours: energyJoules / 3600,
            networkDownBytes: netDown,
            networkUpBytes: netUp,
            diskReadBytes: diskRead,
            diskWriteBytes: diskWrite,
            socTempPeakC: tempPeak,
            throttled: didThrottle,
            peakSwapBytes: swapPeak
        )
    }
}
