import Foundation

/// One point-in-time reading of the machine. Codable so the CLI and the MCP
/// server can emit it as JSON unchanged, and the GUI can hold it directly.
public struct Snapshot: Codable, Sendable {
    public var timestamp: Date
    public var cpu: CPUSnapshot
    public var gpu: GPUSnapshot
    public var memory: MemorySnapshot
    public var power: PowerSnapshot
    public var network: NetworkSnapshot
    public var disk: DiskSnapshot
    public var battery: BatterySnapshot
    public var thermal: ThermalSnapshot

    public init(timestamp: Date, cpu: CPUSnapshot, gpu: GPUSnapshot, memory: MemorySnapshot,
                power: PowerSnapshot, network: NetworkSnapshot, disk: DiskSnapshot,
                battery: BatterySnapshot, thermal: ThermalSnapshot) {
        self.timestamp = timestamp; self.cpu = cpu; self.gpu = gpu; self.memory = memory
        self.power = power; self.network = network; self.disk = disk; self.battery = battery
        self.thermal = thermal
    }
}

public struct CPUSnapshot: Codable, Sendable {
    /// Overall busy percentage across all logical cores, 0 to 100.
    public var usage: Double
    /// Busy percentage of the efficiency-core cluster, 0 to 100.
    public var efficiencyUsage: Double
    /// Busy percentage of the performance-core cluster, 0 to 100.
    public var performanceUsage: Double
    /// Per-core busy percentage, in the kernel's logical-core order.
    public var perCore: [Double]
    public var efficiencyCoreCount: Int
    public var performanceCoreCount: Int

    public init(usage: Double, efficiencyUsage: Double, performanceUsage: Double,
                perCore: [Double], efficiencyCoreCount: Int, performanceCoreCount: Int) {
        self.usage = usage; self.efficiencyUsage = efficiencyUsage; self.performanceUsage = performanceUsage
        self.perCore = perCore; self.efficiencyCoreCount = efficiencyCoreCount
        self.performanceCoreCount = performanceCoreCount
    }
}

public struct GPUSnapshot: Codable, Sendable {
    /// Busy percentage from GPU performance-state residency, 0 to 100.
    public var usage: Double
    /// Whether the reading came from IOReport (false means unavailable on this machine).
    public var available: Bool
    /// True until the residency->utilization mapping is calibrated against
    /// `powermetrics` on this chip family. See docs/PRD.md §5 and GPUReader.
    public var provisional: Bool

    public init(usage: Double, available: Bool, provisional: Bool) {
        self.usage = usage; self.available = available; self.provisional = provisional
    }
}

public struct MemorySnapshot: Codable, Sendable {
    public var totalBytes: UInt64
    public var usedBytes: UInt64
    public var wiredBytes: UInt64
    public var compressedBytes: UInt64
    public var appBytes: UInt64
    /// Used as a fraction of total, 0 to 100.
    public var usedPercent: Double
    /// Swap in use, and the swap file's current size. Swap climbing is the sign a
    /// local model no longer fits in memory and generation is about to crawl.
    public var swapUsedBytes: UInt64
    public var swapTotalBytes: UInt64
    /// How much memory the GPU is allowed to use (Metal's recommended working-set
    /// size). The practical "will this model fit" ceiling on Apple Silicon.
    public var gpuLimitBytes: UInt64
    /// The OS memory-pressure level: "normal", "warning", or "critical".
    public var pressure: String

    public init(totalBytes: UInt64, usedBytes: UInt64, wiredBytes: UInt64,
                compressedBytes: UInt64, appBytes: UInt64, usedPercent: Double,
                swapUsedBytes: UInt64 = 0, swapTotalBytes: UInt64 = 0,
                gpuLimitBytes: UInt64 = 0, pressure: String = "normal") {
        self.totalBytes = totalBytes; self.usedBytes = usedBytes; self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes; self.appBytes = appBytes; self.usedPercent = usedPercent
        self.swapUsedBytes = swapUsedBytes; self.swapTotalBytes = swapTotalBytes
        self.gpuLimitBytes = gpuLimitBytes; self.pressure = pressure
    }
}

public struct PowerSnapshot: Codable, Sendable {
    /// Watts drawn by the CPU rails over the sample window.
    public var cpuWatts: Double
    /// Watts drawn by the GPU over the sample window.
    public var gpuWatts: Double
    /// Watts drawn by the Neural Engine over the sample window. Near zero unless a
    /// CoreML model is running; GPU-based LLMs (Metal, MLX) barely touch it.
    public var aneWatts: Double
    /// CPU + GPU. A package-ish figure, not the whole system.
    public var totalWatts: Double
    /// Whether power came from IOReport (false means unavailable).
    public var available: Bool

    public init(cpuWatts: Double, gpuWatts: Double, aneWatts: Double = 0, totalWatts: Double, available: Bool) {
        self.cpuWatts = cpuWatts; self.gpuWatts = gpuWatts; self.aneWatts = aneWatts
        self.totalWatts = totalWatts; self.available = available
    }
}

public struct NetworkSnapshot: Codable, Sendable {
    public var uploadBytesPerSec: Double
    public var downloadBytesPerSec: Double

    public init(uploadBytesPerSec: Double, downloadBytesPerSec: Double) {
        self.uploadBytesPerSec = uploadBytesPerSec; self.downloadBytesPerSec = downloadBytesPerSec
    }
}

public struct DiskSnapshot: Codable, Sendable {
    public var readBytesPerSec: Double
    public var writeBytesPerSec: Double
    public var freeBytes: UInt64
    public var totalBytes: UInt64

    public init(readBytesPerSec: Double, writeBytesPerSec: Double, freeBytes: UInt64, totalBytes: UInt64) {
        self.readBytesPerSec = readBytesPerSec; self.writeBytesPerSec = writeBytesPerSec
        self.freeBytes = freeBytes; self.totalBytes = totalBytes
    }
}

public struct BatterySnapshot: Codable, Sendable {
    /// False on desktops with no battery.
    public var present: Bool
    /// Charge as a percentage, 0 to 100.
    public var percent: Double
    public var isCharging: Bool
    /// Minutes to full when charging, to empty otherwise. Nil while estimating.
    public var minutesRemaining: Int?

    public init(present: Bool, percent: Double, isCharging: Bool, minutesRemaining: Int?) {
        self.present = present; self.percent = percent; self.isCharging = isCharging
        self.minutesRemaining = minutesRemaining
    }
}

public struct ThermalSnapshot: Codable, Sendable {
    /// Whether the SMC gave a usable reading.
    public var available: Bool
    /// Average of the on-die temperature sensors, in Celsius.
    public var socTempC: Double
    /// Fastest fan's speed in RPM (0 when fans are idle).
    public var fanRPM: Int
    /// Whether this machine has fans at all.
    public var fanPresent: Bool
    /// The OS thermal-pressure state: "nominal", "fair", "serious", or "critical".
    /// "serious" and up mean the machine is throttling, which is what quietly slows
    /// a long inference run.
    public var pressure: String

    public init(available: Bool, socTempC: Double, fanRPM: Int, fanPresent: Bool,
                pressure: String = "nominal") {
        self.available = available; self.socTempC = socTempC
        self.fanRPM = fanRPM; self.fanPresent = fanPresent; self.pressure = pressure
    }
}

public extension Snapshot {
    /// A zeroed reading for a view's initial state, before the first real sample lands.
    static var placeholder: Snapshot {
        Snapshot(
            timestamp: Date(),
            cpu: CPUSnapshot(usage: 0, efficiencyUsage: 0, performanceUsage: 0,
                             perCore: [], efficiencyCoreCount: 0, performanceCoreCount: 0),
            gpu: GPUSnapshot(usage: 0, available: false, provisional: true),
            memory: MemorySnapshot(totalBytes: 0, usedBytes: 0, wiredBytes: 0,
                                   compressedBytes: 0, appBytes: 0, usedPercent: 0),
            power: PowerSnapshot(cpuWatts: 0, gpuWatts: 0, totalWatts: 0, available: false),
            network: NetworkSnapshot(uploadBytesPerSec: 0, downloadBytesPerSec: 0),
            disk: DiskSnapshot(readBytesPerSec: 0, writeBytesPerSec: 0, freeBytes: 0, totalBytes: 0),
            battery: BatterySnapshot(present: false, percent: 0, isCharging: false, minutesRemaining: nil),
            thermal: ThermalSnapshot(available: false, socTempC: 0, fanRPM: 0, fanPresent: false)
        )
    }
}
