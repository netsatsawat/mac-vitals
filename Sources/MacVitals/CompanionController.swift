import AppKit
import Combine
import QuartzCore
import VitalsCore

/// Owns the companion: the floating panel, the pack, the mood and the engine, and
/// the two timers that move her. Opt-in through the `companionEnabled` default,
/// and hidden along with the menu-bar icon in background mode.
///
/// Cost discipline, since this app is a vitals monitor and must not become a
/// load of its own: one deadline timer armed only for the engine's next change
/// (a blink every few seconds, a clip frame), and a 10 Hz cursor poll that runs
/// only while she is awake with live pupils and the user touched the machine in
/// the last three seconds. Everything stops while the panel is occluded, the
/// display sleeps or the session is switched away.
@MainActor
final class CompanionController {
    static let enabledKey = "companionEnabled"
    static let nameKey = "companionName"
    static let originKey = "companionOrigin"
    static let unlockedKey = "companionUnlocked"
    static let outfitKey = "companionOutfit"
    static let defaultName = "rin"

    private weak var store: SampleStore?
    private var panel: NSPanel?
    private var view: CompanionView?
    private var pack: CompanionPack?
    private var mood = CompanionMood()
    private var engine: CompanionEngine?
    private var frame: CompanionFrame?
    private var deadline: Timer?
    private var cursorPoll: Timer?
    private var lastOffsets: (left: CompanionPoint, right: CompanionPoint)?
    private var lastIdle: Double = 0
    /// Why she is resting. Each source owns its own reason, so a display waking
    /// cannot resume her while another app still covers her.
    private enum PauseReason { case occluded, screensAsleep, sessionInactive }
    private var pauseReasons: Set<PauseReason> = []
    private var paused: Bool { !pauseReasons.isEmpty }
    private var packMissing = false
    private var appliedOutfit = ""
    private var challengeTick = 0
    private var subscriptions = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []

    /// One line for the ⋯ menu.
    var statusText: String {
        if packMissing { return "Off (no character pack found)" }
        guard let pack, panel != nil else { return "Off" }
        if paused { return "\(pack.name) is resting" }
        return "\(pack.name) is \(mood.state.word)"
    }

    /// One outfit and whether it is earned yet, for the ⋯ menu. Only outfits the
    /// current pack has art for appear.
    struct OutfitItem: Identifiable { let id: String; let title: String; let detail: String; let unlocked: Bool }

    func outfitItems() -> [OutfitItem] {
        guard let pack else { return [] }
        let earned = Set(UserDefaults.standard.stringArray(forKey: Self.unlockedKey) ?? [])
        return CompanionChallenge.allCases.compactMap { c in
            guard pack.outfitNames.contains(c.outfit) else { return nil }
            return OutfitItem(id: c.outfit, title: c.title, detail: c.detail, unlocked: earned.contains(c.outfit))
        }
    }

    func attach(store: SampleStore) {
        self.store = store
        store.$latest
            .dropFirst()
            .sink { [weak self] snap in self?.tick(snap) }
            .store(in: &subscriptions)
        observers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.sync() }
        })
        sync()
    }

    /// Reconcile the panel with the defaults. Called at launch and whenever any
    /// default changes (the toggle, or background mode).
    func sync() {
        guard !probing else { return }
        let d = UserDefaults.standard
        let wanted = d.bool(forKey: Self.enabledKey) && !d.bool(forKey: "runInBackground")
        if wanted && panel == nil { show() }
        if !wanted && panel != nil { hide() }
        // A change to the chosen outfit (from the menu) lands here too.
        if panel != nil, selectedOutfit != appliedOutfit { applyOutfit() }
    }

    private var selectedOutfit: String { UserDefaults.standard.string(forKey: Self.outfitKey) ?? "" }

    /// The overlay for the current selection, or nil when none is chosen or the
    /// current frame is not on static's canvas (a clip on another canvas).
    private func applyOutfit() {
        guard let pack, let view else { return }
        appliedOutfit = selectedOutfit
        let onStatic = frame.flatMap { pack.raster(for: $0.asset)?.rect } == pack.stillRect
        let raster = (!selectedOutfit.isEmpty && onStatic) ? pack.outfit(selectedOutfit) : nil
        view.setOutfit(raster)
    }

    /// Fold any freshly earned outfits into what is saved. Sticky, so a badge is
    /// never taken back. Cheap, but run on a coarse cadence all the same.
    private func evaluateChallenges() {
        guard let hours = store?.hours else { return }
        let met = CompanionChallenges.unlocked(hours: hours, now: Date())
        let saved = Set(UserDefaults.standard.stringArray(forKey: Self.unlockedKey) ?? [])
        let union = saved.union(met)
        if union != saved { UserDefaults.standard.set(Array(union).sorted(), forKey: Self.unlockedKey) }
    }

    /// Developer probe for `--companion-probe <png>`: put her on screen whatever
    /// the defaults say, wait for a reading and a cursor poll, then write what
    /// the panel's own layers render and print the geometry, so the layer
    /// placement can be checked without a screenshot permission.
    func probe(to path: String, packSpec: String?, then done: @escaping @MainActor () -> Void) {
        probing = true
        // Start from the off state, whatever the defaults already showed.
        if panel != nil { hide() }
        if let spec = packSpec {
            pack = CompanionPack.resolve(spec: spec).flatMap(CompanionPack.load(url:))
            guard pack != nil else {
                print("probe: no pack for \(spec)")
                done()
                return
            }
        }
        show()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self else { return }
            defer { done() }
            guard let panel = self.panel, let view = self.view else {
                print("probe: no panel, status '\(self.statusText)'")
                return
            }
            self.pollCursor()
            if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
            let lf = view.layerFrames
            print("probe: status '\(self.statusText)'")
            print("probe: panel frame \(panel.frame) on screen \(panel.screen?.frame ?? .zero), visible \(panel.isVisible), level \(panel.level.rawValue)")
            print("probe: box \(view.layout.box) still \(view.layout.stillSize) eyes \(String(describing: view.layout.eyeLeft)) \(String(describing: view.layout.eyeRight)) travel \(view.layout.travel) sprite \(view.layout.spriteSize)")
            print("probe: body layer \(lf.body) irisL \(lf.left) irisR \(lf.right) pupils shown \(lf.pupilsShown)")
            print("probe: frame \(String(describing: self.frame)) offsets \(String(describing: self.lastOffsets)) idle \(Self.systemIdleSeconds()) mouse \(NSEvent.mouseLocation)")
            print("probe: timers deadline \(self.deadline != nil) cursorPoll \(self.cursorPoll != nil) paused \(self.paused)")
        }
    }

    private var probing = false

    // MARK: - Panel

    private func show() {
        if pack == nil {
            let name = UserDefaults.standard.string(forKey: Self.nameKey) ?? Self.defaultName
            pack = CompanionPack.locate(name: name).flatMap(CompanionPack.load(url:))
        }
        guard let pack else {
            packMissing = true
            return
        }
        packMissing = false
        appliedOutfit = ""
        mood = CompanionMood(rules: CompanionRules(config: pack.config))
        engine = CompanionEngine(assets: pack.assets, now: now())
        evaluateChallenges() // so a returning user sees an earned outfit at once

        let view = CompanionView(layout: pack.layout, eyeLeft: pack.eyeLeft, eyeRight: pack.eyeRight)
        view.onClick = { [weak self] in self?.clicked() }
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: pack.layout.box),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = view
        panel.setFrameOrigin(savedOrigin(box: pack.layout.box))
        panel.orderFrontRegardless()
        self.panel = panel
        self.view = view

        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let p = self.panel else { return }
                UserDefaults.standard.set(NSStringFromPoint(p.frame.origin), forKey: Self.originKey)
            }
        })
        observers.append(nc.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let p = self.panel else { return }
                self.setPaused(.occluded, !p.occlusionState.contains(.visible))
            }
        })
        let wnc = NSWorkspace.shared.notificationCenter
        let sources: [(Notification.Name, PauseReason, Bool)] = [
            (NSWorkspace.screensDidSleepNotification, .screensAsleep, true),
            (NSWorkspace.screensDidWakeNotification, .screensAsleep, false),
            (NSWorkspace.sessionDidResignActiveNotification, .sessionInactive, true),
            (NSWorkspace.sessionDidBecomeActiveNotification, .sessionInactive, false),
        ]
        for (name, reason, on) in sources {
            observers.append(wnc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setPaused(reason, on) }
            })
        }

        // First frame now, from the latest reading, rather than waiting a second.
        if let snap = store?.latest { tick(snap) } else { refresh() }
    }

    private func hide() {
        deadline?.invalidate(); deadline = nil
        cursorPoll?.invalidate(); cursorPoll = nil
        panel?.orderOut(nil)
        panel = nil
        view = nil
        engine = nil
        frame = nil
        lastOffsets = nil
        pauseReasons = []
        // Drop the rasters while she is off, and so a changed `companionName`
        // takes effect on the next switch-on.
        pack = nil
        // Keep the store subscription and the defaults observer (they were added
        // in attach); drop only the window and workspace observers.
        let nc = NotificationCenter.default, wnc = NSWorkspace.shared.notificationCenter
        for o in observers.dropFirst() { nc.removeObserver(o); wnc.removeObserver(o) }
        observers = Array(observers.prefix(1))
    }

    /// The saved spot, or bottom-right above the Dock, clamped onto a screen.
    private func savedOrigin(box: CGSize) -> NSPoint {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let vf = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        var p = NSPoint(x: vf.maxX - box.width - 24, y: vf.minY + 12)
        if let s = UserDefaults.standard.string(forKey: Self.originKey) {
            let saved = NSPointFromString(s)
            // (0, 0) is a real spot (bottom-left corner with the Dock hidden), so
            // only an off-screen origin is discarded.
            let onSome = NSScreen.screens.contains { $0.visibleFrame.intersects(CGRect(origin: saved, size: box)) }
            if onSome { p = saved }
        }
        return p
    }

    // MARK: - Ticks

    private func now() -> Double { CACurrentMediaTime() }

    /// Seconds since the last keyboard, mouse or trackpad event anywhere in the
    /// session. Reads without a permission prompt.
    static func systemIdleSeconds() -> Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    private func tick(_ snap: Snapshot) {
        guard panel != nil, var engine else { return }
        lastIdle = Self.systemIdleSeconds()
        mood.update(snap, idleSeconds: lastIdle)
        engine.update(active: mood.active, now: now())
        self.engine = engine
        // Challenges look at days of history, so a check a minute is plenty.
        challengeTick += 1
        if challengeTick % 60 == 0 { evaluateChallenges() }
        if !paused { refresh() }
    }

    /// A click reacts through the engine, then re-reads the idle-driven states
    /// with the idle clock at zero (not the latches, which count 1 Hz samples),
    /// so a sleeping character wakes on the click itself, and a pack's sleep_out
    /// clip starts then, rather than at the next reading.
    private func clicked() {
        guard var engine else { return }
        engine.click(now: now())
        lastIdle = 0
        mood.refresh(idleSeconds: 0)
        engine.update(active: mood.active, now: now())
        self.engine = engine
        refresh()
    }

    /// Ask the engine for the frame, put it on screen, arm the one timer for its
    /// next change, and start or stop the cursor poll.
    private func refresh() {
        guard let pack, let view, var engine, !paused else { return }
        let t = now()
        let f = engine.frame(now: t)
        self.engine = engine
        if f != frame || frame == nil {
            if let r = pack.raster(for: f.asset) {
                view.show(raster: r, pupils: f.drawsPupils && pack.assets.hasEyes)
                // The costume rides on top when the body is on static's canvas.
                let overlay = (!selectedOutfit.isEmpty && r.rect == pack.stillRect) ? pack.outfit(selectedOutfit) : nil
                view.setOutfit(overlay)
                appliedOutfit = selectedOutfit
            }
            if f.drawsPupils && (frame?.drawsPupils != true) {
                // Pupils just became live: place them now rather than at the next poll.
                lastOffsets = nil
                pollCursor()
            }
            frame = f
        }
        deadline?.invalidate()
        deadline = nil
        if let next = f.nextChange {
            let interval = max(0.01, next - t)
            let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            timer.tolerance = max(0.005, 0.1 * interval)
            RunLoop.main.add(timer, forMode: .common)
            deadline = timer
        }
        updateCursorPoll()
    }

    private var wantsCursorPoll: Bool {
        guard let pack, let frame, panel != nil, !paused else { return false }
        return frame.drawsPupils && pack.assets.hasEyes && lastIdle < 3
    }

    private func updateCursorPoll() {
        if wantsCursorPoll {
            if cursorPoll == nil {
                let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.pollCursor() }
                }
                timer.tolerance = 0.02
                RunLoop.main.add(timer, forMode: .common)
                cursorPoll = timer
            }
        } else {
            cursorPoll?.invalidate()
            cursorPoll = nil
        }
    }

    /// Where the pointer is, in her box, or her nose when it is on another display.
    private func pollCursor() {
        guard let panel, let view, let eyes = view.layout.eyePoints else { return }
        let m = NSEvent.mouseLocation
        let onHerScreen = panel.screen.map { $0.frame.contains(m) } ?? false
        let target: CompanionPoint
        if onHerScreen {
            target = CompanionGaze.contentPoint(screenX: m.x, screenY: m.y,
                                                frameMinX: panel.frame.minX, frameMaxY: panel.frame.maxY)
        } else {
            target = CompanionGaze.nose(left: eyes.left, right: eyes.right, travel: view.layout.travel)
        }
        let offsets = CompanionGaze.offsets(target: target, left: eyes.left, right: eyes.right, travel: view.layout.travel)
        if let last = lastOffsets, !CompanionGaze.moved(offsets, last, atLeast: 0.1) { return }
        lastOffsets = offsets
        view.setPupils(offsets)
    }

    private func setPaused(_ reason: PauseReason, _ on: Bool) {
        let was = paused
        if on { pauseReasons.insert(reason) } else { pauseReasons.remove(reason) }
        guard paused != was else { return }
        if paused {
            deadline?.invalidate(); deadline = nil
            cursorPoll?.invalidate(); cursorPoll = nil
        } else {
            refresh()
        }
    }
}
