import Foundation
import Darwin

/// One process's live resource use.
public struct ProcessUsage: Codable, Sendable {
    public var pid: Int
    public var name: String
    /// CPU busy as a percentage of one core, so a multi-threaded process can exceed
    /// 100, the same way Activity Monitor and `top` report it.
    public var cpuPercent: Double
    public var memoryBytes: UInt64

    public init(pid: Int, name: String, cpuPercent: Double, memoryBytes: UInt64) {
        self.pid = pid; self.name = name; self.cpuPercent = cpuPercent; self.memoryBytes = memoryBytes
    }
}

/// Per-process CPU and memory, the "what is using the machine" view, read as a
/// normal user through `libproc`, the same interface `top` uses. Per-process GPU
/// is deliberately absent: macOS only exposes it through a private path that needs
/// more than a normal user has, and a wrong number is worse than none.
///
/// CPU is a delta: cumulative CPU time per pid is diffed against the previous read
/// and divided by the elapsed wall-clock, so the first read after construction
/// returns an empty list (no baseline yet).
public final class ProcessReader {
    private var previousCPU: [Int32: UInt64] = [:]
    private var previousTime: Date?

    public init() {}

    private func name(_ pid: Int32) -> String {
        var buf = [CChar](repeating: 0, count: 2 * Int(MAXCOMLEN) + 1)
        if proc_name(pid, &buf, UInt32(buf.count)) > 0 {
            let s = String(cString: buf)
            if !s.isEmpty { return s }
        }
        return "pid \(pid)"
    }

    /// All processes with their CPU% (over the interval since the previous call)
    /// and current memory footprint. Empty on the first call.
    public func read() -> [ProcessUsage] {
        let now = Date()
        let maxPids = 8192
        var pids = [pid_t](repeating: 0, count: maxPids)
        let returned = proc_listallpids(&pids, Int32(maxPids * MemoryLayout<pid_t>.size))
        guard returned > 0 else { return [] }
        let count = Int(returned)

        let elapsed = previousTime.map { now.timeIntervalSince($0) } ?? 0
        var currentCPU: [Int32: UInt64] = [:]
        currentCPU.reserveCapacity(count)
        var out: [ProcessUsage] = []
        out.reserveCapacity(count)

        for i in 0..<count {
            let pid = pids[i]
            guard pid > 0 else { continue }
            var ti = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.size)
            let got = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &ti, size)
            guard got == size else { continue } // not readable (some system pids), skip
            let cpuNs = ti.pti_total_user &+ ti.pti_total_system
            currentCPU[pid] = cpuNs

            var cpuPercent = 0.0
            if elapsed > 0, let prev = previousCPU[pid], cpuNs >= prev {
                cpuPercent = Double(cpuNs - prev) / (elapsed * 1_000_000_000.0) * 100.0
            }
            out.append(ProcessUsage(pid: Int(pid), name: name(pid),
                                    cpuPercent: cpuPercent, memoryBytes: ti.pti_resident_size))
        }

        previousCPU = currentCPU
        previousTime = now
        return elapsed > 0 ? out : []
    }

    /// Prime the baseline, wait, and return the top `limit` processes by CPU or
    /// memory. For one-shot callers (the CLI and the MCP tool).
    public func topOnce(limit: Int = 8, byMemory: Bool = false, interval: TimeInterval = 0.5) -> [ProcessUsage] {
        _ = read()
        Thread.sleep(forTimeInterval: interval)
        return Self.top(read(), limit: limit, byMemory: byMemory)
    }

    /// Sort and slice a process list.
    public static func top(_ list: [ProcessUsage], limit: Int, byMemory: Bool) -> [ProcessUsage] {
        let sorted = byMemory
            ? list.sorted { $0.memoryBytes > $1.memoryBytes }
            : list.sorted { $0.cpuPercent > $1.cpuPercent }
        return Array(sorted.prefix(limit))
    }
}
