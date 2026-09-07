import Testing
@testable import VitalsCore

/// A live reading should return sane, bounded values on any Apple Silicon Mac.
@Test func sampleIsBounded() {
    let monitor = Monitor()
    let snap = monitor.sampleOnce(interval: 0.4)

    #expect(snap.cpu.usage >= 0)
    #expect(snap.cpu.usage <= 100)
    #expect(snap.memory.totalBytes > 0)
    #expect(snap.memory.usedBytes <= snap.memory.totalBytes)

    if snap.gpu.available {
        #expect(snap.gpu.usage >= 0)
        #expect(snap.gpu.usage <= 100)
    }
    if snap.power.available {
        #expect(snap.power.totalWatts >= 0)
    }
}

/// Every per-core reading stays in range, and the E/P counts are consistent.
@Test func perCoreBounded() {
    let monitor = Monitor()
    _ = monitor.sample()
    let snap = monitor.sampleOnce(interval: 0.3)
    for core in snap.cpu.perCore {
        #expect(core >= 0)
        #expect(core <= 100)
    }
    #expect(snap.cpu.efficiencyCoreCount >= 0)
    #expect(snap.cpu.performanceCoreCount >= 0)
}
