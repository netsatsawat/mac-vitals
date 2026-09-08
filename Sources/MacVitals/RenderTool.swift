import SwiftUI
import VitalsCore

/// Offscreen rendering of the full window, used to verify the layout and to make
/// the README screenshot without a display. Invoked via `MacVitals --render <path>`.
@MainActor
enum RenderTool {
    static func renderMainWindow(to path: String) {
        let store = SampleStore(seed: synthetic())
        let view = MainView(store: store, scrolls: false).frame(width: 840, height: 760)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        write(renderer, to: path)
    }

    static func renderPopover(to path: String) {
        let store = SampleStore(seed: synthetic())
        let view = PopoverView(store: store, onToggleWidget: {}, onQuit: {}).fixedSize()
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
                                 performanceUsage: clamp(cpu * 1.25), perCore: [],
                                 efficiencyCoreCount: 6, performanceCoreCount: 4),
                gpu: GPUSnapshot(usage: gpu, available: true, provisional: true),
                memory: MemorySnapshot(totalBytes: total, usedBytes: UInt64(Double(total) * mem / 100),
                                       wiredBytes: 0, compressedBytes: 0, appBytes: 0, usedPercent: mem),
                power: PowerSnapshot(cpuWatts: watts * 0.6, gpuWatts: watts * 0.4,
                                     totalWatts: watts, available: true),
                network: NetworkSnapshot(uploadBytesPerSec: up, downloadBytesPerSec: down),
                disk: DiskSnapshot(readBytesPerSec: readB, writeBytesPerSec: writeB,
                                   freeBytes: 1_655_000_000_000, totalBytes: 1_995_000_000_000),
                battery: BatterySnapshot(present: true, percent: 100, isCharging: false, minutesRemaining: nil)
            )
        }
    }
}
