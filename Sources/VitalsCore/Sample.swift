import Foundation

/// One compact reading: the handful of scalars the history charts and traces
/// need, small enough to keep a full day of and cheap to persist. `Snapshot`
/// carries the live detail (per core, the memory breakdown, battery); `Sample`
/// is what history is made of, at every resolution.
///
/// The same shape holds a raw one-second reading, a one-minute average, and a
/// one-hour average. A coarser point is just the average of the finer points in
/// its wall-clock bucket, stamped at the bucket's start.
public struct Sample: Codable, Sendable {
    public var t: Date
    public var cpu: Double
    public var gpu: Double
    public var mem: Double
    public var watts: Double
    public var netDown: Double
    public var netUp: Double
    public var diskRead: Double
    public var diskWrite: Double
    // Optional so files written before these fields existed still decode.
    public var temp: Double?
    public var fan: Double?

    public init(t: Date, cpu: Double, gpu: Double, mem: Double, watts: Double,
                netDown: Double, netUp: Double, diskRead: Double, diskWrite: Double,
                temp: Double? = nil, fan: Double? = nil) {
        self.t = t; self.cpu = cpu; self.gpu = gpu; self.mem = mem; self.watts = watts
        self.netDown = netDown; self.netUp = netUp
        self.diskRead = diskRead; self.diskWrite = diskWrite
        self.temp = temp; self.fan = fan
    }

    /// Project a live snapshot down to the scalars history keeps.
    public init(from s: Snapshot) {
        self.init(t: s.timestamp,
                  cpu: s.cpu.usage, gpu: s.gpu.usage, mem: s.memory.usedPercent,
                  watts: s.power.totalWatts,
                  netDown: s.network.downloadBytesPerSec, netUp: s.network.uploadBytesPerSec,
                  diskRead: s.disk.readBytesPerSec, diskWrite: s.disk.writeBytesPerSec,
                  temp: s.thermal.socTempC, fan: Double(s.thermal.fanRPM))
    }

    /// Average a set of finer samples into one coarser point, stamped at `time`
    /// (the start of the bucket it stands for).
    public init(averaging samples: [Sample], at time: Date) {
        let n = Double(max(samples.count, 1))
        func avg(_ f: (Sample) -> Double) -> Double { samples.reduce(0) { $0 + f($1) } / n }
        self.init(t: time,
                  cpu: avg(\.cpu), gpu: avg(\.gpu), mem: avg(\.mem), watts: avg(\.watts),
                  netDown: avg(\.netDown), netUp: avg(\.netUp),
                  diskRead: avg(\.diskRead), diskWrite: avg(\.diskWrite),
                  temp: avg { $0.temp ?? 0 }, fan: avg { $0.fan ?? 0 })
    }
}
