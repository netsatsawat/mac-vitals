import Foundation
import VitalsCore

/// One aggregated point (a minute's or an hour's average of each metric).
/// Persisted so the long ranges survive quits and fill in over time. Live
/// 1-second detail stays in memory for the short ranges.
struct MinuteSample: Codable {
    var t: Date
    var cpu: Double
    var gpu: Double
    var mem: Double
    var watts: Double
    var netDown: Double
    var netUp: Double
    var diskRead: Double
    var diskWrite: Double

    init(t: Date, cpu: Double, gpu: Double, mem: Double, watts: Double,
         netDown: Double, netUp: Double, diskRead: Double, diskWrite: Double) {
        self.t = t; self.cpu = cpu; self.gpu = gpu; self.mem = mem; self.watts = watts
        self.netDown = netDown; self.netUp = netUp; self.diskRead = diskRead; self.diskWrite = diskWrite
    }

    /// Average a minute of 1-second snapshots into one persisted point.
    init(from snapshots: [Snapshot]) {
        let n = Double(max(snapshots.count, 1))
        func avg(_ f: (Snapshot) -> Double) -> Double { snapshots.reduce(0) { $0 + f($1) } / n }
        t = snapshots.last?.timestamp ?? Date()
        cpu = avg { $0.cpu.usage }
        gpu = avg { $0.gpu.usage }
        mem = avg { $0.memory.usedPercent }
        watts = avg { $0.power.totalWatts }
        netDown = avg { $0.network.downloadBytesPerSec }
        netUp = avg { $0.network.uploadBytesPerSec }
        diskRead = avg { $0.disk.readBytesPerSec }
        diskWrite = avg { $0.disk.writeBytesPerSec }
    }

    /// Roll a set of minute samples up into one coarser (hourly) point.
    init(rollingUp samples: [MinuteSample]) {
        let n = Double(max(samples.count, 1))
        func avg(_ f: (MinuteSample) -> Double) -> Double { samples.reduce(0) { $0 + f($1) } / n }
        t = samples.last?.t ?? Date()
        cpu = avg(\.cpu); gpu = avg(\.gpu); mem = avg(\.mem); watts = avg(\.watts)
        netDown = avg(\.netDown); netUp = avg(\.netUp); diskRead = avg(\.diskRead); diskWrite = avg(\.diskWrite)
    }
}

/// The metrics a chart can plot, with one extractor per data source so the same
/// chart reads live snapshots for short ranges and aggregated samples for long ones.
enum Metric {
    case cpu, gpu, memory, power, netDown, netUp, diskRead, diskWrite

    func value(_ s: Snapshot) -> Double {
        switch self {
        case .cpu: s.cpu.usage
        case .gpu: s.gpu.usage
        case .memory: s.memory.usedPercent
        case .power: s.power.totalWatts
        case .netDown: s.network.downloadBytesPerSec
        case .netUp: s.network.uploadBytesPerSec
        case .diskRead: s.disk.readBytesPerSec
        case .diskWrite: s.disk.writeBytesPerSec
        }
    }

    func value(_ m: MinuteSample) -> Double {
        switch self {
        case .cpu: m.cpu
        case .gpu: m.gpu
        case .memory: m.mem
        case .power: m.watts
        case .netDown: m.netDown
        case .netUp: m.netUp
        case .diskRead: m.diskRead
        case .diskWrite: m.diskWrite
        }
    }
}

/// Append-only NDJSON persistence for one resolution tier (minutes or hours).
/// Loads on launch, appends one line per new sample, and prunes to its retention.
final class HistoryStore {
    private let url: URL
    private let retention: Int
    private(set) var samples: [MinuteSample] = []

    init(filename: String, retention: Int) {
        self.retention = retention
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MacVitals", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent(filename)
        load()
    }

    private func decoder() -> JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }
    private func encoder() -> JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }

    private func load() {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let dec = decoder()
        var parsed: [MinuteSample] = []
        for line in text.split(separator: "\n") {
            if let data = line.data(using: .utf8), let m = try? dec.decode(MinuteSample.self, from: data) {
                parsed.append(m)
            }
        }
        if parsed.count > retention {
            parsed = Array(parsed.suffix(retention))
            rewrite(parsed)
        }
        samples = parsed
    }

    func append(_ m: MinuteSample) {
        samples.append(m)
        if samples.count > retention {
            samples.removeFirst(samples.count - retention)
            rewrite(samples)
            return
        }
        guard let data = try? encoder().encode(m) else { return }
        var line = data
        line.append(0x0a)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: url)
        }
    }

    private func rewrite(_ samples: [MinuteSample]) {
        let enc = encoder()
        var out = Data()
        for s in samples {
            if let d = try? enc.encode(s) { out.append(d); out.append(0x0a) }
        }
        try? out.write(to: url)
    }
}
