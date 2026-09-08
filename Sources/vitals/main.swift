import Foundation
import VitalsCore

// vitals: a headless readout over the same engine the GUI uses.
//
//   vitals            one human-readable reading
//   vitals --json     one reading as JSON
//   vitals --watch    stream human-readable readings once a second
//   vitals --json --watch   stream JSON, one object per line (ndjson)

let args = Set(CommandLine.arguments.dropFirst())
let asJSON = args.contains("--json")
let watch = args.contains("--watch")

// MCP server mode: speak JSON-RPC over stdio and never return.
if args.contains("--mcp") {
    MCPServer().run()
}

// Self-test: bounded-value checks, no test framework needed.
if args.contains("--selftest") {
    exit(runSelfTest())
}

let monitor = Monitor()

func encoder() -> JSONEncoder {
    let e = JSONEncoder()
    e.outputFormatting = [.prettyPrinted, .sortedKeys]
    e.dateEncodingStrategy = .iso8601
    return e
}

func printJSON(_ snap: Snapshot, pretty: Bool) {
    let e = JSONEncoder()
    e.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
    e.dateEncodingStrategy = .iso8601
    if let data = try? e.encode(snap), let s = String(data: data, encoding: .utf8) {
        print(s)
    }
}

func gb(_ bytes: UInt64) -> String {
    String(format: "%.2f GB", Double(bytes) / 1_073_741_824.0)
}

func rate(_ bytesPerSec: Double) -> String {
    if bytesPerSec >= 1_048_576 { return String(format: "%.1f MB/s", bytesPerSec / 1_048_576) }
    if bytesPerSec >= 1024 { return String(format: "%.0f KB/s", bytesPerSec / 1024) }
    return String(format: "%.0f B/s", bytesPerSec)
}

func printHuman(_ s: Snapshot) {
    let cpu = s.cpu, gpu = s.gpu, mem = s.memory, pw = s.power
    print(String(format: "CPU  %5.1f%%   (E %4.1f%%  P %4.1f%%)", cpu.usage, cpu.efficiencyUsage, cpu.performanceUsage))
    if gpu.available {
        print(String(format: "GPU  %5.1f%%%@", gpu.usage, gpu.provisional ? "  (provisional)" : ""))
    } else {
        print("GPU     n/a")
    }
    print("MEM  \(gb(mem.usedBytes)) / \(gb(mem.totalBytes))  (\(String(format: "%.0f%%", mem.usedPercent)))")
    if pw.available {
        print(String(format: "PWR  %.2f W   (CPU %.2f  GPU %.2f)", pw.totalWatts, pw.cpuWatts, pw.gpuWatts))
    } else {
        print("PWR     n/a")
    }
    let net = s.network, dsk = s.disk, bat = s.battery
    print("NET  down \(rate(net.downloadBytesPerSec))   up \(rate(net.uploadBytesPerSec))")
    print("DSK  read \(rate(dsk.readBytesPerSec))   write \(rate(dsk.writeBytesPerSec))   \(gb(dsk.freeBytes)) free / \(gb(dsk.totalBytes))")
    if bat.present {
        let rem = bat.minutesRemaining.map { "  (\($0 / 60)h \($0 % 60)m)" } ?? ""
        print("BAT  \(Int(bat.percent))%   \(bat.isCharging ? "charging" : "on battery")\(rem)")
    }
    let th = s.thermal
    if th.available {
        let fan = th.fanPresent ? "   fan \(th.fanRPM) rpm" : ""
        print(String(format: "TMP  %.1f°C%@", th.socTempC, fan))
    }
}

if watch {
    // Prime the baseline, then emit once a second.
    _ = monitor.sample()
    while true {
        Thread.sleep(forTimeInterval: 1.0)
        let snap = monitor.sample()
        if asJSON { printJSON(snap, pretty: false) } else {
            printHuman(snap); print("")
        }
    }
} else {
    let snap = monitor.sampleOnce(interval: 0.6)
    if asJSON { printJSON(snap, pretty: true) } else { printHuman(snap) }
}
