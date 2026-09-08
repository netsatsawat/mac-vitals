import Foundation
import Combine
import VitalsCore

/// Drives the `Monitor` on a 1 Hz timer and keeps three resolutions of history,
/// each persisted to its own file: per-second detail for the last hour, minute
/// averages for about a week, and hour averages for over a year.
///
/// Every tier is a deterministic downsample of the one below, keyed by a
/// wall-clock bucket (`floor(t / resolution)`), so a coarser point is just the
/// average of the finer points whose timestamps fall in its bucket. That is what
/// makes it survive a quit: on launch each coarser tier is reconciled against the
/// finer one, and any elapsed bucket the finer tier covers but the coarser tier
/// is missing gets rebuilt. Nothing depends on the app having run without a break.
@MainActor
final class SampleStore: ObservableObject {
    @Published private(set) var latest: Snapshot = .placeholder
    @Published private(set) var history: [Sample] = []   // per-second, last hour
    @Published private(set) var minutes: [Sample] = []   // minute averages
    @Published private(set) var hours: [Sample] = []     // hour averages
    /// Top-process list, refreshed only while a view asks for it (the full window),
    /// so scanning every pid never runs when nothing shows it.
    @Published private(set) var processes: [ProcessUsage] = []

    private let monitor = Monitor()
    private let processReader = ProcessReader()
    private var wantsProcesses = false
    private var procTick = 0
    private let secondsStore: TierStore?
    private let minutesStore: TierStore?
    private let hoursStore: TierStore?
    private var timer: Timer?
    private let liveWindow: TimeInterval = 3600   // one hour of per-second detail

    /// Last sixty seconds of each metric, for the small sparklines.
    var cpuHistory: [Double] { history.suffix(60).map(\.cpu) }
    var gpuHistory: [Double] { history.suffix(60).map(\.gpu) }
    var memHistory: [Double] { history.suffix(60).map(\.mem) }

    init() {
        secondsStore = TierStore(filename: "seconds.ndjson", resolution: 1, retention: 3600)          // 1 hour
        minutesStore = TierStore(filename: "minutes.ndjson", resolution: 60, retention: 8 * 24 * 60)  // 8 days
        hoursStore   = TierStore(filename: "hours.ndjson", resolution: 3600, retention: 400 * 24)     // ~13 months

        let cutoff = Date().addingTimeInterval(-liveWindow)
        history = (secondsStore?.samples ?? []).filter { $0.t >= cutoff }
        minutes = minutesStore?.samples ?? []
        hours = hoursStore?.samples ?? []

        // Rebuild any coarse bucket that elapsed while the app was closed. This is
        // what fills the hour tier from the minute data without a 60-minute run.
        rollUp(force: true)

        _ = monitor.sample() // prime the delta baseline
        start()
    }

    /// Seeded store with no live timer or persistence, for offscreen rendering.
    init(seed: [Snapshot], minutes: [Sample] = [], hours: [Sample] = [], processes: [ProcessUsage] = []) {
        secondsStore = nil
        minutesStore = nil
        hoursStore = nil
        history = seed.map(Sample.init(from:))
        self.minutes = minutes
        self.hours = hours
        self.processes = processes
        latest = seed.last ?? .placeholder
    }

    func start() {
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() { timer?.invalidate(); timer = nil }

    /// The full window calls these on appear/disappear so the per-pid scan only
    /// runs when a view actually shows the list.
    func startProcesses() { wantsProcesses = true; procTick = 0; _ = processReader.read() } // prime the CPU baseline
    func stopProcesses() { wantsProcesses = false; processes = [] }

    private func tick() {
        let snap = monitor.sample()
        latest = snap

        let s = Sample(from: snap)
        history.append(s)
        let cutoff = Date().addingTimeInterval(-liveWindow)
        if let first = history.first, first.t < cutoff {
            history.removeAll { $0.t < cutoff }
        }
        secondsStore?.append(s)

        // Refresh the top-process list every two seconds while the window wants it.
        if wantsProcesses {
            procTick += 1
            if procTick % 2 == 0 { processes = processReader.read() }
        }

        rollUp()
    }

    /// Fill coarser tiers from finer ones for any fully-elapsed bucket not yet
    /// stored. Runs after every tick (closing a minute once a minute, an hour once
    /// an hour) and once at launch with `force` to backfill what accumulated while
    /// the app was closed.
    private func rollUp(force: Bool = false) {
        let newMinutes = Self.reconcile(fine: history, into: minutes, bucket: 60)
        if !newMinutes.isEmpty {
            minutesStore?.merge(newMinutes)
            minutes = minutesStore?.samples ?? mergedSorted(minutes, newMinutes)
        }
        // Rolling minutes into hours reads the whole minute tier, so only do it
        // when a minute just closed or at launch, not on every idle second.
        if force || !newMinutes.isEmpty {
            let newHours = Self.reconcile(fine: minutes, into: hours, bucket: 3600)
            if !newHours.isEmpty {
                hoursStore?.merge(newHours)
                hours = hoursStore?.samples ?? mergedSorted(hours, newHours)
            }
        }
    }

    private func mergedSorted(_ a: [Sample], _ b: [Sample]) -> [Sample] {
        (a + b).sorted { $0.t < $1.t }
    }

    /// The start of the wall-clock bucket a time falls in, for a given width.
    static func bucketStart(_ t: Date, _ bucket: TimeInterval) -> Date {
        Date(timeIntervalSince1970: (t.timeIntervalSince1970 / bucket).rounded(.down) * bucket)
    }

    /// New coarse points to add: for each fully-elapsed bucket the `fine` tier
    /// covers, average its members if the `coarse` tier does not already hold that
    /// bucket. Pure and idempotent, keyed by bucket start, so running it twice adds
    /// nothing the second time.
    static func reconcile(fine: [Sample], into coarse: [Sample], bucket: TimeInterval) -> [Sample] {
        guard !fine.isEmpty else { return [] }
        let now = Date()
        let existing = Set(coarse.map { bucketStart($0.t, bucket).timeIntervalSince1970 })

        var groups: [Double: [Sample]] = [:]
        for s in fine {
            groups[bucketStart(s.t, bucket).timeIntervalSince1970, default: []].append(s)
        }

        var out: [Sample] = []
        for key in groups.keys.sorted() {
            let start = Date(timeIntervalSince1970: key)
            if start.addingTimeInterval(bucket) > now { continue }  // bucket still in progress
            if existing.contains(key) { continue }                  // already stored
            out.append(Sample(averaging: groups[key]!, at: start))
        }
        return out
    }
}
