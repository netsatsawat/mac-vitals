import Foundation

/// Power from the `Energy Model` group.
///
/// Each channel is a simple counter of energy used over the sample window. The
/// tricky part is units: on this hardware the CPU aggregate reports in millijoules
/// while the GPU aggregate reports in nanojoules. Rather than hard-code that, we
/// read each channel's own unit label and normalise to joules, then divide by the
/// measured window length to get watts. That keeps the reading correct across chips
/// even if Apple changes a rail's unit.
final class PowerReader {
    private var subscription: IOReportSubscription?

    init() {
        subscription = try? IOReportSubscription(groups: [("Energy Model", nil)])
    }

    /// Joules per one unit of the given IOReport unit label.
    private func joulesPerUnit(_ label: String) -> Double {
        switch label.lowercased() {
        case "nj", "nanojoules": return 1e-9
        case "uj", "µj", "microjoules": return 1e-6
        case "mj", "millijoules": return 1e-3
        case "j", "joules": return 1.0
        default: return 1e-3 // millijoules is the common default. A new unit label would need adding here.
        }
    }

    func read() -> PowerSnapshot {
        guard let sub = subscription else {
            return PowerSnapshot(cpuWatts: 0, gpuWatts: 0, totalWatts: 0, available: false)
        }

        var cpuJoules = 0.0
        var gpuJoules = 0.0
        var sawAny = false

        let elapsed = sub.sampleDelta { chan in
            let value = Double(chan.integerValue)
            guard value != 0 else { return }
            let joules = value * joulesPerUnit(chan.unit)
            switch chan.name {
            case "CPU Energy":
                cpuJoules += joules
                sawAny = true
            case "GPU Energy":
                gpuJoules += joules
                sawAny = true
            default:
                break
            }
        }

        guard let seconds = elapsed, seconds > 0, sawAny else {
            return PowerSnapshot(cpuWatts: 0, gpuWatts: 0, totalWatts: 0, available: subscription != nil)
        }
        let cpuW = cpuJoules / seconds
        let gpuW = gpuJoules / seconds
        return PowerSnapshot(
            cpuWatts: cpuW,
            gpuWatts: gpuW,
            totalWatts: cpuW + gpuW,
            available: true
        )
    }
}
