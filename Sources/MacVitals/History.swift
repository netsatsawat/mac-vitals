import Foundation
import VitalsCore

/// The metrics a chart can plot. One extractor pulls the value off a `Sample`,
/// so the same chart code reads every resolution: raw seconds, minute averages,
/// or hour averages.
enum Metric {
    case cpu, gpu, memory, power, netDown, netUp, diskRead, diskWrite, temperature, fanRPM

    func value(_ s: Sample) -> Double {
        switch self {
        case .cpu: s.cpu
        case .gpu: s.gpu
        case .memory: s.mem
        case .power: s.watts
        case .netDown: s.netDown
        case .netUp: s.netUp
        case .diskRead: s.diskRead
        case .diskWrite: s.diskWrite
        case .temperature: s.temp ?? 0
        case .fanRPM: s.fan ?? 0
        }
    }
}

/// Append-only NDJSON persistence for one resolution tier (seconds, minutes, or
/// hours). Loads on launch, appends one line per new sample, and prunes to its
/// retention with a slack margin so the one-second tier does not rewrite the
/// whole file every second: it appends all day and trims only when it drifts a
/// slack's worth past the cap.
final class TierStore {
    /// The bucket width this tier holds, in seconds (1, 60, or 3600).
    let resolution: TimeInterval
    private let url: URL
    private let retention: Int
    private let slack: Int
    private(set) var samples: [Sample] = []

    init(filename: String, resolution: TimeInterval, retention: Int) {
        self.resolution = resolution
        self.retention = retention
        self.slack = max(60, retention / 8)
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
        var parsed: [Sample] = []
        for line in text.split(separator: "\n") {
            if let data = line.data(using: .utf8), let m = try? dec.decode(Sample.self, from: data) {
                parsed.append(m)
            }
        }
        if parsed.count > retention {
            parsed = Array(parsed.suffix(retention))
            rewrite(parsed)
        }
        samples = parsed
    }

    /// Append one new sample. Cheap in the common case (one line to the file);
    /// only rewrites when the file has grown a slack past its retention.
    func append(_ m: Sample) {
        samples.append(m)
        if samples.count > retention + slack {
            samples.removeFirst(samples.count - retention)
            rewrite(samples)
        } else {
            appendLine(m)
        }
    }

    /// Fold in a batch of derived samples (a launch backfilling coarser tiers).
    /// Keeps the tier sorted and pruned, then rewrites once.
    func merge(_ additions: [Sample]) {
        guard !additions.isEmpty else { return }
        samples.append(contentsOf: additions)
        samples.sort { $0.t < $1.t }
        if samples.count > retention {
            samples.removeFirst(samples.count - retention)
        }
        rewrite(samples)
    }

    private func appendLine(_ m: Sample) {
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

    private func rewrite(_ samples: [Sample]) {
        let enc = encoder()
        var out = Data()
        for s in samples {
            if let d = try? enc.encode(s) { out.append(d); out.append(0x0a) }
        }
        try? out.write(to: url)
    }
}
