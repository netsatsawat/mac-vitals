import Foundation
import IOKit.ps

/// Battery state from IOKit's power-source API. Charge percentage, whether it is
/// charging, and the estimated minutes remaining (to full when charging, to empty
/// otherwise). Desktops with no battery report `present == false`.
final class BatteryReader {
    func read() -> BatterySnapshot {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              !list.isEmpty else {
            return BatterySnapshot(present: false, percent: 0, isCharging: false, minutesRemaining: nil)
        }

        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }

            let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            let charging = desc[kIOPSIsChargingKey] as? Bool ?? false
            let percent = maximum > 0 ? Double(current) / Double(maximum) * 100 : 0

            let minutes = charging
                ? desc[kIOPSTimeToFullChargeKey] as? Int
                : desc[kIOPSTimeToEmptyKey] as? Int
            let remaining = (minutes ?? -1) > 0 ? minutes : nil

            return BatterySnapshot(present: true, percent: percent,
                                   isCharging: charging, minutesRemaining: remaining)
        }
        return BatterySnapshot(present: false, percent: 0, isCharging: false, minutesRemaining: nil)
    }
}
