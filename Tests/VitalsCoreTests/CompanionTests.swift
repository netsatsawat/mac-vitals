import Foundation
import Testing
@testable import VitalsCore

/// The full deterministic sweep (config, fit, gaze, mood latches, engine) lives in
/// `CompanionSelfCheck` so `vitals --selftest` runs it too. Each failure line
/// names what broke.
@Test func companionSelfCheckPasses() {
    let failures = CompanionSelfCheck.run()
    #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
}

/// The numbers the yuna pack renders at, pinned so a change to the fit rule is a
/// deliberate one.
@Test func yunaFitsItsBox() {
    let fit = CompanionFit(nativeWidth: 669, nativeHeight: 1243, maxWidth: 220, maxHeight: 330)
    #expect(abs(fit.scale - 0.26549) < 0.0001)
    #expect(fit.width == 178)
    #expect(fit.height == 330)
    #expect(abs(10 * fit.scale - 2.655) < 0.01)
}

/// A target between the sockets converges the gaze; one outside moves the pupils
/// in parallel; one on the eye rests them.
@Test func gazeConvergesBetweenTheEyes() {
    let l = CompanionPoint(x: 60, y: 100), r = CompanionPoint(x: 120, y: 100)
    let mid = CompanionGaze.offsets(target: CompanionPoint(x: 90, y: 100), left: l, right: r, travel: 3)
    #expect(abs(mid.left.x - 3) < 0.01)
    #expect(abs(mid.right.x + 3) < 0.01)
    let far = CompanionGaze.offsets(target: CompanionPoint(x: 900, y: 100), left: l, right: r, travel: 3)
    #expect(abs(far.left.x - 3) < 0.01)
    #expect(abs(far.right.x - 3) < 0.01)
    let rest = CompanionGaze.offsets(target: CompanionPoint(x: 120.4, y: 100), left: l, right: r, travel: 3)
    #expect(rest.right == CompanionPoint(x: 0, y: 0))
}

/// Working needs three ticks over the line and five under it to clear.
@Test func workingLatchDoesNotFlap() {
    var snap = Snapshot.placeholder
    var mood = CompanionMood()
    snap.cpu.usage = 90
    #expect(mood.update(snap, idleSeconds: 0) == .awake)
    #expect(mood.update(snap, idleSeconds: 0) == .awake)
    #expect(mood.update(snap, idleSeconds: 0) == .working)
    snap.cpu.usage = 30
    for _ in 0..<4 { #expect(mood.update(snap, idleSeconds: 0) == .working) }
    #expect(mood.update(snap, idleSeconds: 0) == .awake)
}

/// A week of cool hours earns Cozy, a hot stretch earns Sun's out, and unlocks
/// are independent.
@Test func challengesUnlockFromHistory() {
    let ref = Date(timeIntervalSince1970: 1_700_000_000)
    func hours(_ n: Int, temp: Double?, throttled: Bool = false) -> [Sample] {
        (0..<n).map { i in
            Sample(t: ref.addingTimeInterval(Double(-(n - 1 - i)) * 3600), cpu: 10, gpu: 10, mem: 50, watts: 5,
                   netDown: 0, netUp: 0, diskRead: 0, diskWrite: 0, temp: temp, fan: 1000, throttled: throttled, swap: 0)
        }
    }
    #expect(CompanionChallenges.unlocked(hours: hours(8 * 24, temp: 45), now: ref) == ["cozy"])
    #expect(!CompanionChallenges.isMet(.cozy, hours: hours(3 * 24, temp: 45), now: ref))
    var run = hours(2 * 24, temp: 50)
    run[3].temp = 90; run[4].temp = 90
    #expect(CompanionChallenges.isMet(.sunny, hours: run, now: ref))
    #expect(CompanionChallenges.unlocked(hours: [], now: ref).isEmpty)
}

/// A state the pack has no art for falls through to the next one that does, and
/// the mood still reports the true state.
@Test func engineFallsThroughMissingArt() {
    let config = CompanionConfig.decode(Data("{}".utf8), folderName: "t", hasBlink: true)!
    let assets = CompanionAssets(stills: ["static", "blink"], clips: [:], idlePool: [], clickPool: [],
                                 hungryPool: [], hasEyes: false, config: config)
    var engine = CompanionEngine(assets: assets, now: 0, rng: SplitMix64(seed: 1))
    engine.update(active: [.working, .awake], now: 0)
    #expect(engine.displayed == .awake)
    let f = engine.frame(now: 0)
    #expect(f.asset == .still("static"))
    #expect(f.mode == .open)
}
