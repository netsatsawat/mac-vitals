import Foundation

/// The engine every front-end sits on: the GUI, the `--json` CLI, and the MCP server.
///
/// The IOReport-backed readers (GPU, power) and the Mach-backed readers (CPU) all
/// work on deltas, so a reading needs two samples. Create the monitor, then call
/// `sample()` on a cadence. The first call primes the baseline and returns zeros for
/// the delta-based metrics. `SampleStore` (the GUI) drives this on a 1 Hz timer, and
/// `sampleOnce(interval:)` gives one honest reading for one-shot callers.
public final class Monitor {
    private let cpu = CPUReader()
    private let mem = MemReader()
    private let gpu = GPUReader()
    private let power = PowerReader()

    public init() {}

    /// One reading. Delta metrics reflect the interval since the previous `sample()`.
    public func sample() -> Snapshot {
        Snapshot(
            timestamp: Date(),
            cpu: cpu.read(),
            gpu: gpu.read(),
            memory: mem.read(),
            power: power.read()
        )
    }

    /// Prime the baseline, wait `interval`, and return one honest reading.
    /// For one-shot callers (CLI single output, MCP `get_vitals`).
    public func sampleOnce(interval: TimeInterval = 0.5) -> Snapshot {
        _ = sample()
        Thread.sleep(forTimeInterval: interval)
        return sample()
    }
}
