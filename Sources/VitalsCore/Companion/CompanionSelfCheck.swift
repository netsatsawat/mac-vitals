import Foundation

/// Deterministic checks over the companion's pure logic: config decoding, fit and
/// gaze geometry, the mood latches and the frame engine. They run from
/// `vitals --selftest` (which builds anywhere, including a Mac with only the
/// Command Line Tools) and again from the swift-testing suite in CI, so the same
/// assertions cover both. Returns the failures, empty on a pass.
public enum CompanionSelfCheck {
    public static func run() -> [String] {
        var out: [String] = []
        func expect(_ ok: Bool, _ what: String) { if !ok { out.append(what) } }
        func near(_ a: Double, _ b: Double, _ tol: Double = 0.01) -> Bool { abs(a - b) <= tol }

        // MARK: config
        let yuna = CompanionConfig.decode(Data(yunaJSON.utf8), folderName: "folder", hasBlink: true)
        expect(yuna != nil, "yuna config failed to decode")
        if let c = yuna {
            expect(c.name == "yuna", "name: \(c.name)")
            expect(c.maxWidth == 220 && c.maxHeight == 330, "max box: \(c.maxWidth)x\(c.maxHeight)")
            expect(c.eyes?.travelRadius == 10, "travel radius: \(String(describing: c.eyes?.travelRadius))")
            expect(c.eyes?.left == CompanionPoint(x: 225.5, y: 400.5), "left eye: \(String(describing: c.eyes?.left))")
            expect(c.eyes?.right == CompanionPoint(x: 442, y: 400), "right eye: \(String(describing: c.eyes?.right))")
            expect(c.blink.enabled && c.blink.every == 3...7 && c.blink.duration == 0.28, "blink: \(c.blink)")
            expect(c.clickSquint == 0.5, "click squint: \(c.clickSquint)")
            expect(c.idle.randomEvery == 60...150, "random every: \(c.idle.randomEvery)")
            expect(c.idle.yawnAfter == 60 && c.idle.sleepAfter == 300, "idle defaults: \(c.idle)")
            expect(c.battery.hungryBelow == 20 && c.battery.every == 30...60, "battery defaults: \(c.battery)")
        }
        let bare = CompanionConfig.decode(Data("{}".utf8), folderName: "mika", hasBlink: false)
        expect(bare?.name == "mika", "empty config should take the folder name")
        expect(bare?.maxWidth == 200 && bare?.maxHeight == 400, "empty config box default")
        expect(bare?.eyes == nil, "empty config should have no eyes")
        expect(bare?.blink.enabled == false, "blink.enabled should default to hasBlink")
        expect(bare?.idle.randomEvery == 25...60, "random_every default")
        expect(CompanionConfig.decode(Data("not json".utf8), folderName: "x", hasBlink: true) == nil,
               "malformed JSON should decode to nil")
        let odd = CompanionConfig.decode(Data(#"{"name":"","blink":{"every":[5]},"idle":{"random_every":[9,2]}}"#.utf8),
                                         folderName: "f", hasBlink: true)
        expect(odd?.name == "f", "empty name should fall back to the folder")
        expect(odd?.blink.every == 3...7, "one-element every should fall back")
        expect(odd?.idle.randomEvery == 25...60, "descending every should fall back")
        // One wrong-typed or senseless value must cost only that key.
        let typedJSON = #"{"max_width":"220","max_height":0,"click_squint":true,"blink":{"enabled":"yes","every":[-1,5],"duration":-2},"#
            + #""eyes":{"travel_radius":"10","left":{"x":225.5,"y":400.5},"right":{"x":442,"y":400}},"idle":7}"#
        let typed = CompanionConfig.decode(Data(typedJSON.utf8), folderName: "t", hasBlink: true)
        expect(typed != nil, "a valid JSON file with wrong-typed values should still decode")
        expect(typed?.maxWidth == 200 && typed?.maxHeight == 400, "bad box values should fall back one key at a time")
        expect(typed?.eyes?.left == CompanionPoint(x: 225.5, y: 400.5), "eyes should survive a bad sibling key")
        expect(typed?.eyes?.travelRadius == 0, "a wrong-typed travel radius should read as 0")
        expect(typed?.blink.enabled == true && typed?.blink.every == 3...7 && typed?.blink.duration == 0.28,
               "bad blink values should fall back: \(String(describing: typed?.blink))")
        expect(typed?.clickSquint == 0.5 && typed?.idle.sleepAfter == 300, "bad squint and idle should fall back")

        // MARK: fit
        let yf = CompanionFit(nativeWidth: 669, nativeHeight: 1243, maxWidth: 220, maxHeight: 330)
        expect(near(yf.scale, 0.26549, 0.0001), "yuna scale \(yf.scale)")
        expect(yf.width == 178 && yf.height == 330, "yuna fitted \(yf.width)x\(yf.height)")
        expect(near(225.5 * yf.scale, 59.87) && near(400.5 * yf.scale, 106.33), "yuna left eye in points")
        expect(near(442 * yf.scale, 117.35) && near(400 * yf.scale, 106.20), "yuna right eye in points")
        expect(near(10 * yf.scale, 2.655), "yuna travel in points")
        expect(near(82 * yf.scale, 21.77), "yuna sprite in points")
        let rf = CompanionFit(nativeWidth: 404, nativeHeight: 1392, maxWidth: 220, maxHeight: 330)
        expect(near(rf.scale, 0.23707, 0.0001), "rin scale \(rf.scale)")
        expect(rf.width == 96 && rf.height == 330, "rin fitted \(rf.width)x\(rf.height)")
        expect(near(6 * rf.scale, 1.42) && near(48 * rf.scale, 11.38), "rin travel and sprite")
        let small = CompanionFit(nativeWidth: 100, nativeHeight: 50, maxWidth: 220, maxHeight: 330)
        expect(small.scale == 1 && small.width == 100 && small.height == 50, "a small pack is never enlarged")
        expect(near(CompanionFit.clipScale(fittedHeight: 330, clipNativeHeight: 660), 0.5), "clip scale")

        // MARK: gaze
        let L = CompanionPoint(x: 60, y: 100), R = CompanionPoint(x: 120, y: 100), t = 3.0
        let far = CompanionGaze.offsets(target: CompanionPoint(x: -500, y: 100), left: L, right: R, travel: t)
        expect(near(far.left.x, -3) && near(far.left.y, 0) && near(far.right.x, -3) && near(far.right.y, 0),
               "far-left target should move both pupils left in parallel: \(far)")
        let mid = CompanionGaze.offsets(target: CompanionPoint(x: 90, y: 100), left: L, right: R, travel: t)
        expect(near(mid.left.x, 3) && near(mid.right.x, -3) && near(mid.left.y, 0),
               "a target between the eyes should converge: \(mid)")
        let onEye = CompanionGaze.offsets(target: CompanionPoint(x: 60.5, y: 100), left: L, right: R, travel: t)
        expect(onEye.left == CompanionPoint(x: 0, y: 0) && onEye.right == CompanionPoint(x: 0, y: 0),
               "a target within 1 pt of the eye should rest: \(onEye)")
        let up = CompanionGaze.offsets(target: CompanionPoint(x: 90, y: 0), left: L, right: R, travel: t)
        expect(up.left.y < 0 && near(up.left.x, -up.right.x) && near(up.left.y, up.right.y),
               "a target above the midpoint should mirror x and share y: \(up)")
        expect(near(up.left.x * up.left.x + up.left.y * up.left.y, 9), "offset magnitude should be the travel")
        let nose = CompanionGaze.nose(left: L, right: R, travel: t)
        expect(nose == CompanionPoint(x: 90, y: 106), "nose point \(nose)")
        let cp = CompanionGaze.contentPoint(screenX: 130, screenY: 480, frameMinX: 100, frameMaxY: 500)
        expect(cp == CompanionPoint(x: 30, y: 20), "content point \(cp)")
        let a = (left: CompanionPoint(x: 1, y: 1), right: CompanionPoint(x: 1, y: 1))
        let b = (left: CompanionPoint(x: 1.05, y: 1), right: CompanionPoint(x: 1, y: 1.2))
        expect(CompanionGaze.moved(a, b, atLeast: 0.1), "a 0.2 pt change should count as moved")
        expect(!CompanionGaze.moved(a, (left: b.left, right: a.right), atLeast: 0.1), "a 0.05 pt change should not")

        // MARK: clip timing
        expect(CompanionClipTiming.frameDelay(unclamped: nil, clamped: nil) == 0.1, "no delay should be 100 ms")
        expect(CompanionClipTiming.frameDelay(unclamped: 0.45, clamped: 0.1) == 0.45, "unclamped wins")
        expect(CompanionClipTiming.frameDelay(unclamped: 0, clamped: 0.1) == 0.1, "zero delay should be 100 ms")
        expect(CompanionClipTiming.frameDelay(unclamped: nil, clamped: 0.06) == 0.06, "clamped fallback")
        expect(CompanionClipTiming.frameDelay(unclamped: 0.005, clamped: nil) == 0.1, "near-zero delay should be 100 ms")

        // MARK: mood
        var snap = Snapshot.placeholder
        snap.thermal.available = true
        snap.thermal.socTempC = 40
        snap.thermal.pressure = "nominal"
        snap.battery = BatterySnapshot(present: true, percent: 80, isCharging: true, minutesRemaining: nil)
        var mood = CompanionMood()
        expect(mood.update(snap, idleSeconds: 0) == .awake, "quiet machine should be awake")
        snap.cpu.usage = 90
        expect(mood.update(snap, idleSeconds: 0) == .awake && mood.update(snap, idleSeconds: 0) == .awake,
               "two hot ticks should not latch working")
        expect(mood.update(snap, idleSeconds: 0) == .working, "third tick at 90% should latch working")
        snap.cpu.usage = 60
        expect(mood.update(snap, idleSeconds: 0) == .working, "60% is inside the band, should stay working")
        snap.cpu.usage = 50
        for _ in 0..<4 { _ = mood.update(snap, idleSeconds: 0) }
        expect(mood.state == .working, "four quiet ticks should not release working")
        expect(mood.update(snap, idleSeconds: 0) == .awake, "fifth quiet tick should release working")
        snap.cpu.usage = 10
        snap.gpu = GPUSnapshot(usage: 95, available: false, provisional: false)
        for _ in 0..<3 { _ = mood.update(snap, idleSeconds: 0) }
        expect(mood.state == .awake, "an unavailable GPU reading should not count as load")
        snap.gpu.available = true
        for _ in 0..<3 { _ = mood.update(snap, idleSeconds: 0) }
        expect(mood.state == .working, "GPU load should latch working")
        snap.gpu.usage = 0
        for _ in 0..<5 { _ = mood.update(snap, idleSeconds: 0) }
        snap.thermal.socTempC = 90
        for _ in 0..<2 { _ = mood.update(snap, idleSeconds: 0) }
        expect(mood.state == .awake, "two ticks at 90 C should not latch hot")
        expect(mood.update(snap, idleSeconds: 0) == .hot, "third tick at 90 C should latch hot")
        snap.thermal.socTempC = 75
        for _ in 0..<6 { _ = mood.update(snap, idleSeconds: 0) }
        expect(mood.state == .hot, "75 C is inside the band, should stay hot")
        snap.thermal.available = false
        expect(mood.update(snap, idleSeconds: 0) == .awake, "losing the sensor should clear hot")
        snap.thermal.available = true
        snap.thermal.socTempC = 40
        snap.thermal.pressure = "serious"
        expect(mood.update(snap, idleSeconds: 0) == .throttling, "serious pressure should throttle at once")
        snap.thermal.pressure = "fair"
        expect(mood.update(snap, idleSeconds: 0) == .awake, "fair pressure is not throttling")
        snap.battery.isCharging = false
        snap.battery.percent = 15
        expect(mood.update(snap, idleSeconds: 0) == .hungry, "15% on battery should be hungry")
        snap.battery.isCharging = true
        expect(mood.update(snap, idleSeconds: 0) == .awake, "charging should end hungry at once")
        snap.battery.present = false
        snap.battery.percent = 5
        snap.battery.isCharging = false
        expect(mood.update(snap, idleSeconds: 0) == .awake, "a desktop never gets hungry")
        expect(mood.update(snap, idleSeconds: 59.9) == .awake, "just under a minute idle is awake")
        expect(mood.update(snap, idleSeconds: 60) == .sleepy, "a minute idle is sleepy")
        expect(mood.update(snap, idleSeconds: 300) == .asleep, "five minutes idle is asleep")
        expect(mood.active == [.asleep, .sleepy, .awake], "asleep list \(mood.active)")
        snap.thermal.pressure = "critical"
        expect(mood.update(snap, idleSeconds: 300) == .throttling, "throttling outranks sleep")
        expect(mood.active == [.throttling, .asleep, .sleepy, .awake], "ordered list \(mood.active)")
        var custom = CompanionRules(config: CompanionConfig.decode(
            Data(#"{"battery":{"hungry_below":35},"idle":{"yawn_after":10,"sleep_after":20}}"#.utf8),
            folderName: "c", hasBlink: false)!)
        expect(custom.hungryBelow == 35 && custom.sleepyAfter == 10 && custom.sleepAfter == 20, "rules from config")
        custom.enterTicks = 1
        var quick = CompanionMood(rules: custom)
        snap.thermal.pressure = "nominal"
        snap.cpu.usage = 80
        expect(quick.update(snap, idleSeconds: 0) == .working, "enterTicks 1 should latch on the first tick")
        // refresh() re-reads idle only: it never advances a latch counter.
        var m2 = CompanionMood()
        snap.cpu.usage = 90
        snap.battery.present = false
        _ = m2.update(snap, idleSeconds: 0)
        m2.refresh(idleSeconds: 0)
        m2.refresh(idleSeconds: 0)
        expect(m2.state == .awake, "a refresh must not count as a sample toward the working latch")
        expect(m2.refresh(idleSeconds: 400) == .asleep, "refresh should follow idle time")
        expect(m2.refresh(idleSeconds: 0) == .awake, "refresh with idle 0 should wake her")
        _ = m2.update(snap, idleSeconds: 0)
        expect(m2.update(snap, idleSeconds: 0) == .working, "readings still latch after refreshes")
        expect(m2.refresh(idleSeconds: 500) == .asleep && m2.active == [.asleep, .working, .sleepy, .awake],
               "refresh keeps the latched working state in the list \(m2.active)")

        // MARK: engine
        var rng = SplitMix64(seed: 7)
        let config = yuna ?? CompanionConfig.decode(Data("{}".utf8), folderName: "yuna", hasBlink: true)!
        let assets = CompanionAssets(stills: ["static", "blink"], clips: ["click1": [0.45, 0.06], "idle1": [0.45, 0.06]],
                                     idlePool: ["idle1"], clickPool: ["click1"], hungryPool: [],
                                     hasEyes: true, config: config)
        var engine = CompanionEngine(assets: assets, now: 0, rng: rng)
        let f0 = engine.frame(now: 0)
        expect(f0.asset == .still("static") && f0.mode == .open && f0.drawsPupils, "first frame \(f0)")
        guard let blinkAt = f0.nextChange else { out.append("open frame should schedule a blink"); return out }
        expect(blinkAt >= 3 && blinkAt <= 7, "first blink due in [3, 7], got \(blinkAt)")
        let f1 = engine.frame(now: blinkAt - 0.01)
        expect(f1.asset == .still("static") && f1.nextChange == blinkAt, "just before the blink \(f1)")
        let f2 = engine.frame(now: blinkAt)
        expect(f2.asset == .still("blink") && f2.mode == .blink && !f2.drawsPupils, "blink frame \(f2)")
        expect(near(f2.nextChange ?? -1, blinkAt + 0.28), "blink should end after 0.28 s \(String(describing: f2.nextChange))")
        let f3 = engine.frame(now: blinkAt + 0.28)
        expect(f3.asset == .still("static") && f3.mode == .open, "eyes should reopen \(f3)")
        expect((f3.nextChange ?? 0) >= blinkAt + 3, "next blink should be at least 3 s later")
        engine.click(now: 10)
        let c0 = engine.frame(now: 10)
        expect(c0.asset == .clip("click1", 0) && c0.mode == .anim && near(c0.nextChange ?? -1, 10.45), "click frame 0 \(c0)")
        let c1 = engine.frame(now: 10.45)
        expect(c1.asset == .clip("click1", 1) && near(c1.nextChange ?? -1, 10.51), "click frame 1 \(c1)")
        let c2 = engine.frame(now: 10.51)
        expect(c2.asset == .still("static") && c2.mode == .open, "click clip should settle to open \(c2)")
        engine.update(active: [.working, .awake], now: 11)
        expect(engine.displayed == .awake, "no busy.png: working should fall through to awake")
        engine.update(active: [.asleep, .sleepy, .awake], now: 12)
        expect(engine.displayed == .awake, "no sleep art: asleep should fall through to awake")
        // A blink may be due at 12; step past it if so.
        var noArt = engine.frame(now: 12)
        if noArt.mode == .blink, let end = noArt.nextChange { noArt = engine.frame(now: end) }
        expect(noArt.asset == .still("static") && noArt.mode == .open, "fallthrough frame \(noArt)")

        // A fuller pack: state stills, sleep clips, a hungry pool, no click clip.
        rng = SplitMix64(seed: 3)
        let full = CompanionAssets(
            stills: ["static", "blink", "busy", "hot", "throttle", "sleep", "sleepy", "hungry"],
            clips: ["sleep_in": [0.2, 0.2], "sleep_out": [0.3], "yawn": [0.5], "hungry1": [0.25, 0.25]],
            idlePool: [], clickPool: [], hungryPool: ["hungry1"], hasEyes: true, config: config)
        var e2 = CompanionEngine(assets: full, now: 100, rng: rng)
        e2.update(active: [.working, .awake], now: 100)
        let busy = e2.frame(now: 100)
        expect(e2.displayed == .working && busy.asset == .still("busy") && busy.mode == .held && busy.nextChange == nil,
               "busy still should be held \(busy)")
        e2.click(now: 100.5)
        expect(e2.frame(now: 100.5).asset == .still("busy"), "a click on a held still should be ignored")
        e2.update(active: [.throttling, .working, .awake], now: 101)
        expect(e2.frame(now: 101).asset == .still("throttle"), "throttling should outrank working")
        e2.update(active: [.sleepy, .awake], now: 102)
        let y0 = e2.frame(now: 102)
        expect(e2.displayed == .sleepy && y0.asset == .clip("yawn", 0) && near(y0.nextChange ?? -1, 102.5),
               "entering sleepy should yawn once \(y0)")
        expect(e2.frame(now: 102.5).asset == .still("sleepy"), "after the yawn the sleepy still holds")
        e2.update(active: [.asleep, .sleepy, .awake], now: 103)
        let s0 = e2.frame(now: 103)
        expect(s0.asset == .clip("sleep_in", 0) && near(s0.nextChange ?? -1, 103.2), "sleep_in frame 0 \(s0)")
        expect(e2.frame(now: 103.2).asset == .clip("sleep_in", 1), "sleep_in frame 1")
        let held = e2.frame(now: 103.4)
        expect(held.asset == .still("sleep") && held.mode == .held && held.nextChange == nil, "sleep held \(held)")
        e2.update(active: [.awake], now: 200)
        let w0 = e2.frame(now: 200)
        expect(e2.displayed == .awake && w0.asset == .clip("sleep_out", 0) && near(w0.nextChange ?? -1, 200.3),
               "waking should play sleep_out \(w0)")
        // Her blink was due long ago, so the first open frame may be that blink.
        var woke = e2.frame(now: 200.3)
        if woke.mode == .blink, let end = woke.nextChange { woke = e2.frame(now: end) }
        expect(woke.asset == .still("static") && woke.mode == .open, "after sleep_out she is awake \(woke)")
        e2.update(active: [.sleepy, .awake], now: 201)
        expect(e2.frame(now: 201).asset == .clip("yawn", 0), "a fresh idle stretch should yawn again")
        e2.update(active: [.awake], now: 202)
        e2.click(now: 202)
        let sq = e2.frame(now: 202)
        expect(sq.asset == .still("blink") && sq.mode == .blink && near(sq.nextChange ?? -1, 202.5),
               "no click clip: a click should squint for click_squint \(sq)")
        e2.update(active: [.hungry, .awake], now: 300)
        let h0 = e2.frame(now: 300)
        expect(e2.displayed == .hungry && h0.asset == .clip("hungry1", 0), "hungry should play a pool clip \(h0)")
        let h1 = e2.frame(now: 300.5)
        expect(h1.asset == .still("hungry") && h1.mode == .held, "between hungry clips the hungry still holds \(h1)")
        guard let again = h1.nextChange else { out.append("hungry still should schedule the next clip"); return out }
        expect(again >= 330 && again <= 360, "next hungry clip due in [30, 60] s, got \(again - 300)")
        expect(e2.frame(now: again).asset == .clip("hungry1", 0), "the next hungry clip plays when due")

        // A yawn without sleepy.png: the yawn follows the mood, then she looks awake.
        rng = SplitMix64(seed: 5)
        var yawnOnly = assets
        yawnOnly.clips["yawn"] = [0.5]
        var e4 = CompanionEngine(assets: yawnOnly, now: 0, rng: rng)
        e4.update(active: [.sleepy, .awake], now: 1)
        let ya = e4.frame(now: 1)
        expect(e4.displayed == .awake && ya.asset == .clip("yawn", 0), "no sleepy.png: she should still yawn once \(ya)")
        e4.update(active: [.sleepy, .awake], now: 2)
        var afterYawn = e4.frame(now: 2)
        if afterYawn.mode == .blink, let end = afterYawn.nextChange { afterYawn = e4.frame(now: end) }
        expect(afterYawn.asset == .still("static") && afterYawn.mode == .open, "after the yawn she looks awake \(afterYawn)")
        e4.update(active: [.sleepy, .awake], now: 3)
        expect(e4.frame(now: 3).asset != .clip("yawn", 0), "one yawn per idle stretch")
        e4.update(active: [.awake], now: 4)
        e4.update(active: [.asleep, .sleepy, .awake], now: 5)
        expect(e4.frame(now: 5).asset == .clip("yawn", 0), "a new idle stretch yawns again, even straight into asleep")

        // Idle pool timing, on a short schedule so the check does not lean on the seed.
        rng = SplitMix64(seed: 11)
        let quickIdle = CompanionConfig.decode(Data(#"{"idle":{"random_every":[8,9]}}"#.utf8), folderName: "q", hasBlink: true)!
        var quickAssets = assets
        quickAssets.config = quickIdle
        var e3 = CompanionEngine(assets: quickAssets, now: 0, rng: rng)
        var probe = e3.frame(now: 0)
        var due = 0.0
        var seenIdle = false
        for _ in 0..<40 {
            due = probe.nextChange ?? (due + 1)
            probe = e3.frame(now: due)
            if case .clip("idle1", 0) = probe.asset { seenIdle = true; break }
        }
        expect(seenIdle, "an idle clip should play within a few blink cycles")
        expect(due >= 8 && due <= 9, "first idle clip due in [8, 9] s, got \(due)")

        // MARK: challenges
        let ref = Date(timeIntervalSince1970: 1_700_000_000)
        func hoursBack(_ n: Int, temp: Double?, throttled: Bool = false) -> [Sample] {
            (0..<n).map { i in
                Sample(t: ref.addingTimeInterval(Double(-(n - 1 - i)) * 3600), cpu: 10, gpu: 10, mem: 50, watts: 5,
                       netDown: 0, netUp: 0, diskRead: 0, diskWrite: 0, temp: temp, fan: 1000, throttled: throttled, swap: 0)
            }
        }
        let coolWeek = hoursBack(8 * 24, temp: 45)
        expect(CompanionChallenges.unlocked(hours: coolWeek, now: ref) == ["cozy"], "eight cool days should earn cozy only")
        expect(!CompanionChallenges.isMet(.cozy, hours: hoursBack(3 * 24, temp: 45), now: ref), "three days is not a week")
        // Two cool hours eight days apart must not earn cozy: no coverage across the week.
        let sparse = [Sample(t: ref.addingTimeInterval(-8 * 86_400), cpu: 5, gpu: 5, mem: 50, watts: 5,
                             netDown: 0, netUp: 0, diskRead: 0, diskWrite: 0, temp: 40, fan: 900, throttled: false, swap: 0),
                      Sample(t: ref, cpu: 5, gpu: 5, mem: 50, watts: 5,
                             netDown: 0, netUp: 0, diskRead: 0, diskWrite: 0, temp: 40, fan: 900, throttled: false, swap: 0)]
        expect(!CompanionChallenges.isMet(.cozy, hours: sparse, now: ref), "sparse cool hours should not earn cozy")
        // A laptop used about eight hours a day and asleep overnight does earn it.
        let workdays = (0..<7).flatMap { day in (0..<8).map { h in
            Sample(t: ref.addingTimeInterval(Double(-day * 86_400 - h * 3600)), cpu: 20, gpu: 10, mem: 60, watts: 8,
                   netDown: 0, netUp: 0, diskRead: 0, diskWrite: 0, temp: 45, fan: 1000, throttled: false, swap: 0)
        } }
        expect(CompanionChallenges.isMet(.cozy, hours: workdays, now: ref), "eight cool hours a day for a week should earn cozy")
        let shortDays = (0..<7).flatMap { day in (0..<5).map { h in
            Sample(t: ref.addingTimeInterval(Double(-day * 86_400 - h * 3600)), cpu: 20, gpu: 10, mem: 60, watts: 8,
                   netDown: 0, netUp: 0, diskRead: 0, diskWrite: 0, temp: 45, fan: 1000, throttled: false, swap: 0)
        } }
        expect(!CompanionChallenges.isMet(.cozy, hours: shortDays, now: ref), "five hours a day is under the floor")
        var oneHot = coolWeek
        oneHot[oneHot.count / 2].temp = 90
        expect(!CompanionChallenges.isMet(.cozy, hours: oneHot, now: ref), "a hot hour breaks cozy")
        expect(!CompanionChallenges.isMet(.sunny, hours: oneHot, now: ref), "one hot hour is not a hot stretch")
        oneHot[oneHot.count / 2 + 1].temp = 90
        expect(CompanionChallenges.isMet(.sunny, hours: oneHot, now: ref), "two hot hours in a row earn sunny")
        var throttledRun = hoursBack(2 * 24, temp: 50)
        throttledRun[5].throttled = true
        expect(CompanionChallenges.isMet(.sunny, hours: throttledRun, now: ref), "a throttled hour earns sunny")
        expect(CompanionChallenges.unlocked(hours: [], now: ref).isEmpty, "no history earns nothing")
        expect(!CompanionChallenges.isMet(.cozy, hours: hoursBack(8 * 24, temp: nil), now: ref),
               "no temperature reading never earns cozy")

        return out
    }

    /// Reference config, identical to Sources/MacVitals/Resources/Companion/yuna/config.json.
    static let yunaJSON = """
    {"name":"yuna","max_width":220,"max_height":330,
     "eyes":{"travel_radius":10.0,"left":{"x":225.5,"y":400.5},"right":{"x":442.0,"y":400.0}},
     "blink":{"enabled":true,"every":[3,7],"duration":0.28},
     "click_squint":0.5,"idle":{"random_every":[60,150]}}
    """
}

/// A tiny seedable generator so the engine's schedules are reproducible in checks.
public struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
