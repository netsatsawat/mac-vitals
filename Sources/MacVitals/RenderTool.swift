import SwiftUI
import VitalsCore

/// Offscreen rendering of the full window, used to verify the layout and to make
/// the README screenshot without a display. Invoked via `MacVitals --render <path>`.
@MainActor
enum RenderTool {
    static func renderMainWindow(to path: String, range: HistoryRange = .h24) {
        let store = SampleStore(seed: synthetic(),
                                minutes: syntheticSamples(1440, step: 60),
                                hours: syntheticSamples(370 * 24, step: 3600),
                                processes: syntheticProcesses())
        let view = MainView(store: store, scrolls: false, initialRange: range).frame(width: 840, height: 940)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        write(renderer, to: path)
    }

    /// A freshly-started machine: only a few minutes of history against a 24h
    /// range, to show the "collecting…" hint.
    static func renderSparse(to path: String) {
        let store = SampleStore(seed: Array(synthetic().suffix(180)),
                                minutes: syntheticSamples(8, step: 60), hours: [])
        let view = MainView(store: store, scrolls: false, initialRange: .h24).frame(width: 840, height: 940)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        write(renderer, to: path)
    }

    /// Plausible aggregated samples spaced `step` seconds apart, for rendering the
    /// minute and hour tiers behind the long ranges.
    static func syntheticSamples(_ n: Int, step: Double) -> [Sample] {
        let now = Date()
        func clamp(_ v: Double) -> Double { max(0, min(100, v)) }
        return (0..<n).map { i in
            let f = Double(i)
            let t = now.addingTimeInterval(Double(i - n) * step)
            return Sample(
                t: t,
                cpu: clamp(38 + 26 * sin(f / 70) + 10 * sin(f / 13)),
                gpu: clamp(45 + 32 * sin(f / 90 + 1)),
                mem: clamp(55 + 8 * sin(f / 150)),
                watts: max(2, 14 + 9 * sin(f / 80)),
                netDown: max(0, 3_000_000 + 6_000_000 * (0.5 + 0.5 * sin(f / 40))),
                netUp: max(0, 300_000 + 400_000 * abs(sin(f / 33))),
                diskRead: max(0, 12_000_000 * abs(sin(f / 25))),
                diskWrite: max(0, 6_000_000 * abs(sin(f / 29 + 1))),
                temp: 44 + 14 * sin(f / 60),
                fan: max(0, 1600 + 900 * sin(f / 70))
            )
        }
    }

    static func syntheticProcesses() -> [ProcessUsage] {
        [
            ProcessUsage(pid: 4821, name: "ollama", cpuPercent: 312, memoryBytes: 9_200_000_000),
            ProcessUsage(pid: 731, name: "WindowServer", cpuPercent: 47, memoryBytes: 640_000_000),
            ProcessUsage(pid: 5012, name: "Google Chrome Helper (GPU)", cpuPercent: 22, memoryBytes: 1_100_000_000),
            ProcessUsage(pid: 902, name: "Xcode", cpuPercent: 14, memoryBytes: 2_300_000_000),
            ProcessUsage(pid: 233, name: "kernel_task", cpuPercent: 9, memoryBytes: 280_000_000),
            ProcessUsage(pid: 6120, name: "Claude", cpuPercent: 6, memoryBytes: 540_000_000),
            ProcessUsage(pid: 388, name: "mds_stores", cpuPercent: 3, memoryBytes: 190_000_000),
            ProcessUsage(pid: 27172, name: "MacVitals", cpuPercent: 1, memoryBytes: 46_000_000),
        ]
    }

    static func renderPopover(to path: String) {
        let store = SampleStore(seed: synthetic())
        let view = PopoverView(store: store, onToggleWidget: {}, onHideMenuBar: {}, onQuit: {}).fixedSize()
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        write(renderer, to: path)
    }

    /// Preview of the menu-bar readout on a mock dark bar (the real bar renders it
    /// as a monochrome template).
    static func renderMenuBar(to path: String) {
        let store = SampleStore(seed: synthetic())
        let view = MenuBarLabel(store: store)
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color(red: 0.13, green: 0.13, blue: 0.15))
            .fixedSize()
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        write(renderer, to: path)
    }

    private static func write(_ renderer: ImageRenderer<some View>, to path: String) {
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }

    /// Fifteen minutes of plausible, wavy history so the charts read as live data.
    static func synthetic() -> [Snapshot] {
        let n = 900
        let now = Date()
        func clamp(_ v: Double) -> Double { max(0, min(100, v)) }
        let total: UInt64 = 25_769_803_776
        return (0..<n).map { i in
            let f = Double(i)
            let t = now.addingTimeInterval(Double(i - n))
            let cpu = clamp(42 + 24 * sin(f / 40) + 9 * sin(f / 7))
            let gpu = clamp(56 + 30 * sin(f / 55 + 1))
            let mem = clamp(58 + 4 * sin(f / 120))
            let watts = max(2, 15 + 8 * sin(f / 50))
            let down = max(0, 5_000_000 + 8_000_000 * sin(f / 30))
            let up = max(0, 400_000 + 320_000 * sin(f / 25))
            let readB = max(0, 22_000_000 * abs(sin(f / 18)))
            let writeB = max(0, 9_000_000 * abs(sin(f / 22 + 1)))
            return Snapshot(
                timestamp: t,
                cpu: CPUSnapshot(usage: cpu, efficiencyUsage: clamp(cpu * 0.45),
                                 performanceUsage: clamp(cpu * 1.25),
                                 perCore: (0..<10).map { k in
                                     clamp((k < 6 ? 18.0 : 55.0) + 30 * sin(f / 20 + Double(k)))
                                 },
                                 efficiencyCoreCount: 6, performanceCoreCount: 4),
                gpu: GPUSnapshot(usage: gpu, available: true, provisional: false),
                memory: MemorySnapshot(totalBytes: total, usedBytes: UInt64(Double(total) * mem / 100),
                                       wiredBytes: 0, compressedBytes: 0, appBytes: 0, usedPercent: mem),
                power: PowerSnapshot(cpuWatts: watts * 0.6, gpuWatts: watts * 0.4,
                                     totalWatts: watts, available: true),
                network: NetworkSnapshot(uploadBytesPerSec: up, downloadBytesPerSec: down),
                disk: DiskSnapshot(readBytesPerSec: readB, writeBytesPerSec: writeB,
                                   freeBytes: 1_655_000_000_000, totalBytes: 1_995_000_000_000),
                battery: BatterySnapshot(present: true, percent: 100, isCharging: false, minutesRemaining: nil),
                thermal: ThermalSnapshot(available: true, socTempC: 44 + 14 * sin(f / 60),
                                         fanRPM: Int(max(0, 1600 + 900 * sin(f / 70))), fanPresent: true)
            )
        }
    }
}
