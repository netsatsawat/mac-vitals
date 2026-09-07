import Foundation

/// GPU utilization from `GPU Stats / GPU Performance States` (channel `GPUPH`).
///
/// The channel reports residency across the GPU's power states, and every state's
/// residencies sum to wall-clock (a 24 MHz tick base), so utilization is the share
/// of time spent outside the idle states. The subtlety is *which* state is idle.
///
/// On M1 to M4 the tools of record treat state index 0 (`OFF`) as idle. On the M5,
/// measured directly, `OFF` stays near 0% whenever the display is on, and the GPU
/// parks in its lowest performance state (`P1`) instead. So here we treat `OFF` and the
/// lowest performance state as idle. This is a defensible heuristic, not a
/// calibrated truth: the exact mapping is validated against `powermetrics` once per
/// chip family (PRD §5), until which point `provisional` stays true.
final class GPUReader {
    private var subscription: IOReportSubscription?

    init() {
        // Subscribe to the whole group (no sub-group filter): the filtered form
        // returns channels with no state data on this hardware.
        subscription = try? IOReportSubscription(groups: [("GPU Stats", nil)])
    }

    func read() -> GPUSnapshot {
        guard let sub = subscription else {
            return GPUSnapshot(usage: 0, available: false, provisional: true)
        }

        var total: Int64 = 0
        var idle: Int64 = 0
        var sawChannel = false

        let elapsed = sub.sampleDelta { chan in
            guard chan.name == "GPUPH" else { return }
            sawChannel = true
            let n = chan.stateCount
            guard n > 0 else { return }
            for i in 0..<n {
                let r = chan.residency(i)
                total += r
                if i == 0 || i == 1 { idle += r } // OFF + P1 (parked)
            }
        }

        // First sample (no baseline) or channel absent this interval.
        guard elapsed != nil, sawChannel, total > 0 else {
            return GPUSnapshot(usage: 0, available: subscription != nil, provisional: true)
        }
        let usage = Double(total - idle) / Double(total) * 100.0
        return GPUSnapshot(usage: min(max(usage, 0), 100), available: true, provisional: true)
    }
}
