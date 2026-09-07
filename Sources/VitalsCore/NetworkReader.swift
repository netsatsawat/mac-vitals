import Foundation
import Darwin

/// Network throughput from `getifaddrs`, summed over every non-loopback
/// interface. The kernel keeps cumulative byte counters per interface, so we diff
/// against the previous read and divide by elapsed time to get bytes per second.
final class NetworkReader {
    private var previousUp: UInt64 = 0
    private var previousDown: UInt64 = 0
    private var previousTime: Date?

    /// Cumulative (upBytes, downBytes) across physical interfaces since boot.
    private func cumulative() -> (up: UInt64, down: UInt64) {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return (0, 0) }
        defer { freeifaddrs(addrs) }

        var up: UInt64 = 0, down: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let node = cursor {
            let ifa = node.pointee
            if let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_LINK) {
                let name = String(cString: ifa.ifa_name)
                if !name.hasPrefix("lo"), let raw = ifa.ifa_data {
                    let data = raw.assumingMemoryBound(to: if_data.self).pointee
                    up += UInt64(data.ifi_obytes)
                    down += UInt64(data.ifi_ibytes)
                }
            }
            cursor = ifa.ifa_next
        }
        return (up, down)
    }

    func read() -> NetworkSnapshot {
        let now = Date()
        let (up, down) = cumulative()
        defer { previousUp = up; previousDown = down; previousTime = now }

        guard let prev = previousTime else {
            return NetworkSnapshot(uploadBytesPerSec: 0, downloadBytesPerSec: 0)
        }
        let elapsed = now.timeIntervalSince(prev)
        guard elapsed > 0 else {
            return NetworkSnapshot(uploadBytesPerSec: 0, downloadBytesPerSec: 0)
        }
        // Counters only ever climb; guard against a wrap or interface reset.
        let upRate = up >= previousUp ? Double(up - previousUp) / elapsed : 0
        let downRate = down >= previousDown ? Double(down - previousDown) / elapsed : 0
        return NetworkSnapshot(uploadBytesPerSec: upRate, downloadBytesPerSec: downRate)
    }
}
