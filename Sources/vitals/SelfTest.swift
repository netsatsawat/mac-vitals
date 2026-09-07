import Foundation
import VitalsCore

/// A dependency-free correctness check that runs anywhere, including CI without a
/// full Xcode install (where `swift test` cannot build XCTest). It samples once
/// and asserts every reading is in range. Exit code 0 passes, 1 fails.
func runSelfTest() -> Int32 {
    let monitor = Monitor()
    let s = monitor.sampleOnce(interval: 0.5)
    var failures: [String] = []

    func check(_ ok: Bool, _ message: String) { if !ok { failures.append(message) } }

    check(s.cpu.usage >= 0 && s.cpu.usage <= 100, "cpu.usage out of range: \(s.cpu.usage)")
    check(s.cpu.perCore.allSatisfy { $0 >= 0 && $0 <= 100 }, "a per-core value is out of range")
    check(s.memory.totalBytes > 0, "memory.totalBytes is zero")
    check(s.memory.usedBytes <= s.memory.totalBytes, "used memory exceeds total")
    if s.gpu.available {
        check(s.gpu.usage >= 0 && s.gpu.usage <= 100, "gpu.usage out of range: \(s.gpu.usage)")
    }
    if s.power.available {
        check(s.power.totalWatts >= 0, "total power is negative")
        check(s.power.totalWatts < 500, "total power implausibly high: \(s.power.totalWatts)")
    }
    check(s.network.downloadBytesPerSec >= 0 && s.network.uploadBytesPerSec >= 0, "network rate negative")
    check(s.disk.readBytesPerSec >= 0 && s.disk.writeBytesPerSec >= 0, "disk rate negative")
    check(s.disk.freeBytes <= s.disk.totalBytes, "disk free exceeds total")
    check(s.disk.totalBytes > 0, "disk total is zero")
    if s.battery.present {
        check(s.battery.percent >= 0 && s.battery.percent <= 100, "battery percent out of range: \(s.battery.percent)")
    }

    if failures.isEmpty {
        print("selftest PASS: cpu \(Int(s.cpu.usage))%, gpu \(s.gpu.available ? "\(Int(s.gpu.usage))%" : "n/a"), "
              + "mem \(Int(s.memory.usedPercent))%, power \(s.power.available ? String(format: "%.1fW", s.power.totalWatts) : "n/a")")
        return 0
    } else {
        for f in failures { FileHandle.standardError.write(Data("selftest FAIL: \(f)\n".utf8)) }
        return 1
    }
}
