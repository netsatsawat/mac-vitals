import Foundation
import Darwin
import Metal

/// Memory usage from `host_statistics64` (VM stats) plus `hw.memsize` for the total.
///
/// "Used" is built the way Activity Monitor presents it: app memory + wired +
/// compressed, rather than "total minus free", which overstates pressure because
/// macOS keeps inactive pages around on purpose. Also reports swap, the OS
/// memory-pressure level, and the GPU's memory ceiling, all of which speak to the
/// "will this local model fit, and why did it slow down" question.
final class MemReader {
    private let pageSize: UInt64
    private let total: UInt64
    /// Metal's recommended working-set size: the practical cap on how much memory
    /// the GPU may use. Constant for the machine, so read once.
    private let gpuLimit: UInt64

    init() {
        pageSize = UInt64(vm_kernel_page_size)
        var mem: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &mem, &size, nil, 0)
        total = mem
        gpuLimit = MTLCreateSystemDefaultDevice().map { UInt64($0.recommendedMaxWorkingSetSize) } ?? 0
    }

    /// Swap used and total, from `vm.swapusage`.
    private func swap() -> (used: UInt64, total: UInt64) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return (0, 0) }
        return (usage.xsu_used, usage.xsu_total)
    }

    /// The OS memory-pressure level: 1 normal, 2 warning, 4 critical.
    private func pressureLevel() -> String {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return "normal" }
        switch level {
        case 4: return "critical"
        case 2: return "warning"
        default: return "normal"
        }
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
        let sw = swap()

        return MemorySnapshot(
            totalBytes: total,
            usedBytes: used,
            wiredBytes: wired,
            compressedBytes: compressed,
            appBytes: app,
            usedPercent: total > 0 ? Double(used) / Double(total) * 100.0 : 0,
            swapUsedBytes: sw.used,
            swapTotalBytes: sw.total,
            gpuLimitBytes: gpuLimit,
            pressure: pressureLevel()
        )
    }
}
