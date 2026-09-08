import Foundation

/// GPU utilization from `GPU Stats / GPU Performance States` (channel `GPUPH`).
///
/// The channel reports residency across the GPU's power states, and every state's
/// residencies sum to wall-clock (a 24 MHz tick base), so utilization is the share
/// of time spent outside idle. Idle is state index 0 (`OFF`, the GPU powered down);
/// `P1` and above are active frequencies.
///
/// Calibrated against `powermetrics --samplers gpu_power` on the M5: powermetrics
/// reports "GPU active residency" as `1 - idle`, where its idle residency is exactly
/// the `OFF` time and its active-frequency buckets (338…1620 MHz) are `P1…P13`. Under
/// a sustained Metal load both read 100%; at idle both read the small `P1` share the
/// compositor keeps alive. So `usage = 1 - OFF/total`, and it is no longer provisional.
final class GPUReader {
    private var subscription: IOReportSubscription?

    init() {
        // Subscribe to the whole group (no sub-group filter): the filtered form
        // returns channels with no state data on this hardware.
        subscription = try? IOReportSubscription(groups: [("GPU Stats", nil)])
    }

    func read() -> GPUSnapshot {
        guard let sub = subscription else {
            return GPUSnapshot(usage: 0, available: false, provisional: false)
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
                if i == 0 { idle += r } // OFF is the only idle state (calibrated vs powermetrics)
            }
        }

        // First sample (no baseline) or channel absent this interval.
        guard elapsed != nil, sawChannel, total > 0 else {
            return GPUSnapshot(usage: 0, available: subscription != nil, provisional: false)
        }
        let usage = Double(total - idle) / Double(total) * 100.0
        return GPUSnapshot(usage: min(max(usage, 0), 100), available: true, provisional: false)
    }
}
