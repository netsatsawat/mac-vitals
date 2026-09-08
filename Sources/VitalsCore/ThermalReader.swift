import Foundation
import CSMC

/// Temperature and fan from the SMC (no root needed). The SoC has dozens of die
/// sensors with undocumented names; at startup we enumerate them once, keep the
/// on-die sensors (dropping battery and ambient), and report their average as the
/// SoC temperature. Fan speed is read directly.
final class ThermalReader {
    private var tempKeys: [String] = []
    private var fanKeys: [String] = []
    private var opened = false

    init() {
        guard csmc_open() == 0 else { return }
        opened = true
        discover()
    }

    deinit { if opened { csmc_close() } }

    private func discover() {
        let count = csmc_key_count()
        guard count > 0 else { return }
        var buf = [CChar](repeating: 0, count: 5)
        for i in 0..<count {
            guard csmc_key_at(Int32(i), &buf) == 0 else { continue }
            let key = String(cString: buf)
            guard let first = key.first else { continue }
            if first == "T" {
                // On-die temperature sensors, dropping battery (TB*) and ambient (TA*).
                if key.hasPrefix("TB") || key.hasPrefix("TA") { continue }
                var v = 0.0
                if csmc_read(key, &v) == 0, v > 10, v < 120 { tempKeys.append(key) }
            } else if first == "F", key.hasSuffix("Ac") {
                fanKeys.append(key) // F0Ac, F1Ac, ...
            }
        }
        // Keep the reads cheap: a representative sample is plenty for an average.
        if tempKeys.count > 40 { tempKeys = Array(tempKeys.prefix(40)) }
    }

    /// The OS thermal-pressure state, independent of the SMC. "serious" and up mean
    /// the machine is throttling.
    private func pressureString() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "nominal"
        }
    }

    func read() -> ThermalSnapshot {
        let pressure = pressureString()
        guard opened, !tempKeys.isEmpty else {
            return ThermalSnapshot(available: false, socTempC: 0, fanRPM: 0, fanPresent: false, pressure: pressure)
        }
        var sum = 0.0, n = 0.0
        for key in tempKeys {
            var v = 0.0
            if csmc_read(key, &v) == 0, v > 10, v < 120 { sum += v; n += 1 }
        }
        let temp = n > 0 ? sum / n : 0

        var maxRPM = 0.0, present = false
        for key in fanKeys {
            var v = 0.0
            if csmc_read(key, &v) == 0, v >= 0 { present = true; maxRPM = max(maxRPM, v) }
        }

        return ThermalSnapshot(available: n > 0, socTempC: temp,
                               fanRPM: Int(maxRPM.rounded()), fanPresent: present, pressure: pressure)
    }
}
