import Foundation
import Darwin

/// Per-core and aggregate CPU busy percentage from Mach `host_processor_info`.
///
/// Each poll reads cumulative user/system/idle/nice ticks per logical core and
/// diffs against the previous poll, so the first reading returns zeros (no baseline).
/// The efficiency-versus-performance split uses the kernel's per-perflevel core counts.
/// On Apple Silicon the efficiency cluster occupies the first logical cores.
final class CPUReader {
    private var previous: [[UInt32]] = []
    let efficiencyCoreCount: Int
    let performanceCoreCount: Int

    init() {
        // perflevel0 = highest-performance cluster (P), perflevel1 = efficiency (E).
        performanceCoreCount = CPUReader.sysctlInt("hw.perflevel0.logicalcpu") ?? 0
        efficiencyCoreCount = CPUReader.sysctlInt("hw.perflevel1.logicalcpu") ?? 0
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }

    func read() -> CPUSnapshot {
        var cpuCount: natural_t = 0
        var infoArray: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &infoArray, &infoCount
        )
        guard result == KERN_SUCCESS, let info = infoArray else {
            return emptySnapshot()
        }
        defer {
            vm_deallocate(mach_task_self_,
                          vm_address_t(bitPattern: info),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size))
        }

        let n = Int(cpuCount)
        let states = Int(CPU_STATE_MAX) // USER, SYSTEM, IDLE, NICE
        var current: [[UInt32]] = []
        current.reserveCapacity(n)
        for core in 0..<n {
            var ticks = [UInt32](repeating: 0, count: states)
            for s in 0..<states {
                ticks[s] = UInt32(bitPattern: info[core * states + s])
            }
            current.append(ticks)
        }

        defer { previous = current }
        guard previous.count == n else {
            return CPUSnapshot(usage: 0, efficiencyUsage: 0, performanceUsage: 0,
                               perCore: Array(repeating: 0, count: n),
                               efficiencyCoreCount: efficiencyCoreCount,
                               performanceCoreCount: performanceCoreCount)
        }

        var perCore = [Double](repeating: 0, count: n)
        var totalBusy = 0.0, totalTicks = 0.0
        var eBusy = 0.0, eTicks = 0.0, pBusy = 0.0, pTicks = 0.0

        for core in 0..<n {
            let dUser = Double(current[core][Int(CPU_STATE_USER)] &- previous[core][Int(CPU_STATE_USER)])
            let dSys  = Double(current[core][Int(CPU_STATE_SYSTEM)] &- previous[core][Int(CPU_STATE_SYSTEM)])
            let dIdle = Double(current[core][Int(CPU_STATE_IDLE)] &- previous[core][Int(CPU_STATE_IDLE)])
            let dNice = Double(current[core][Int(CPU_STATE_NICE)] &- previous[core][Int(CPU_STATE_NICE)])
            let busy = dUser + dSys + dNice
            let total = busy + dIdle
            let pct = total > 0 ? busy / total * 100.0 : 0
            perCore[core] = pct
            totalBusy += busy; totalTicks += total

            if core < efficiencyCoreCount {
                eBusy += busy; eTicks += total
            } else {
                pBusy += busy; pTicks += total
            }
        }

        return CPUSnapshot(
            usage: totalTicks > 0 ? totalBusy / totalTicks * 100.0 : 0,
            efficiencyUsage: eTicks > 0 ? eBusy / eTicks * 100.0 : 0,
            performanceUsage: pTicks > 0 ? pBusy / pTicks * 100.0 : 0,
            perCore: perCore,
            efficiencyCoreCount: efficiencyCoreCount,
            performanceCoreCount: performanceCoreCount
        )
    }

    private func emptySnapshot() -> CPUSnapshot {
        CPUSnapshot(usage: 0, efficiencyUsage: 0, performanceUsage: 0, perCore: [],
                    efficiencyCoreCount: efficiencyCoreCount,
                    performanceCoreCount: performanceCoreCount)
    }
}
