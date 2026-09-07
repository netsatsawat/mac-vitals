import Foundation
import Darwin

/// Memory usage from `host_statistics64` (VM stats) plus `hw.memsize` for the total.
///
/// "Used" is built the way Activity Monitor presents it: app memory + wired +
/// compressed, rather than "total minus free", which overstates pressure because
/// macOS keeps inactive pages around on purpose.
final class MemReader {
    private let pageSize: UInt64
    private let total: UInt64

    init() {
        pageSize = UInt64(vm_kernel_page_size)
        var mem: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &mem, &size, nil, 0)
        total = mem
    }

    func read() -> MemorySnapshot {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return MemorySnapshot(totalBytes: total, usedBytes: 0, wiredBytes: 0,
                                  compressedBytes: 0, appBytes: 0, usedPercent: 0)
        }

        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let internalPages = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        let app = internalPages > purgeable ? (internalPages - purgeable) * pageSize : 0
        let used = app + wired + compressed

        return MemorySnapshot(
            totalBytes: total,
            usedBytes: used,
            wiredBytes: wired,
            compressedBytes: compressed,
            appBytes: app,
            usedPercent: total > 0 ? Double(used) / Double(total) * 100.0 : 0
        )
    }
}
