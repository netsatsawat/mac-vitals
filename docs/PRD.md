# PRD: Mac Vitals (working title)

A menu-bar and floating-widget monitor for Apple Silicon that shows CPU, GPU, memory,
and power draw live, with no password prompt and nothing to install alongside it.

> **Status:** Draft v0.1 · 2026-09-07 · Author: Net
> **Feasibility:** Core data path proven on this machine (Apple M5, macOS 26). See §5.

---

## 1. Why this is worth building

Every Apple Silicon Mac already collects rich telemetry about itself. Getting at it is the
problem. `powermetrics` shows the most, but it wants `sudo` on every launch. Activity Monitor
hides GPU and per-core power behind a window you have to go and open. Good third-party tools
exist, and the shelf still has room for one that is genuinely nice to look at and reports the
numbers that matter on the newest chips.

The wedge is narrow and I want to keep it honest. **One monitor that reads everything without a
password, ships as a single native app with no runtime, and looks like Apple built it.** It shows
up two ways: a glance in the menu bar, and a floating desktop gadget you can park anywhere.

There is a second wedge none of the incumbents touch. **The same engine speaks MCP**, so an AI
coding agent can read the machine's live vitals directly. "See what your build did to the Mac"
stops being something you eyeball and becomes something the agent running the build can ask for.

If it earns a place on people's menu bars, it becomes a small, visible piece of open-source work
in front of the macOS developer community.

## 2. Who it is for

- Developers and ML engineers on M-series Macs who want to see what a build or a training run is
  doing to the machine, without opening a separate app or typing a password.
- People who liked desktop gadgets and want a live CPU/GPU/RAM readout parked on screen.
- Contributors who want a small, readable Swift codebase with no dependencies to learn from.

## 3. The honest competitive picture

This is a crowded shelf. Pretending otherwise would waste everyone's time.

| Tool | What it is | Where it leaves room |
| --- | --- | --- |
| **stats** (exelban) | The default free choice, very popular, feature-rich | Utilitarian look, heavy option surface, menu-bar first with no real floating gadget |
| **macmon** | Good-looking, no-sudo, reads IOReport | Terminal UI only, so no menu-bar item and no desktop widget |
| **iStat Menus** | The polished paid standard | Paid, closed source |
| **MenuMeters and similar** | Classic menu-bar meters | Dated design, CPU/RAM/net focus, weak on GPU and power |

**What none of them do all at once:** read without sudo, look genuinely Apple-native, offer a real
floating desktop widget, and expose an MCP interface an agent can read, all in one app with no
dependencies. That combination is the reason to build instead of adopting one of these.

Assume `stats` and `macmon` are excellent at what they do, and compete only on those points. If
the mockups cannot beat the field on look and on the floating gadget, there is no project.

## 4. What it does

### v1.0 (MVP, the thing worth shipping)

1. **Menu-bar readout.** A compact live item showing CPU%, GPU%, and memory pressure, updating
   about once a second and staying legible in light and dark menu bars.
2. **Detail popover.** Click the menu-bar item for ring gauges and short history sparklines:
   overall CPU with an E-core and P-core split, GPU%, memory used against pressure, and package
   power in watts.
3. **Floating widget.** A borderless, always-on-top, draggable panel with the same live gauges,
   drawn on the system blur material so it reads as native. Toggle it from the menu. It remembers
   where you left it.
4. **No password, no dependencies.** Reads through IOReport and Mach as a normal user. Ships as one
   signed `.app`. Nothing to `brew install`, no helper daemon, no kernel extension.
5. **Launch at login** as an optional toggle, and a look that follows the system between light and
   dark.
6. **MCP server** (`vitals --mcp`, over stdio). Exposes the same snapshots as agent-readable tools:
   a one-shot `get_vitals` and a short `get_vitals_history` over the rolling window, returning CPU
   (overall plus the E/P split), GPU%, memory, and power in watts. Read-only, local, no network. A
   coding agent adds it like any other MCP server and can ask "what did that build cost the
   machine?" It ships in v1.0 as a launch differentiator, because it comes nearly for free once the
   engine exists.

### v1.x (soon after)

- Network and disk throughput.
- Per-core CPU grid.
- Thermal pressure and fan, where the hardware exposes them.
- A choice of which metrics show in the menu bar.

### Later, maybe

- History beyond the short rolling window.
- Per-process attribution. Activity Monitor already does this, so only if it earns its keep.
- A mini-graph rendered in the menu-bar item itself.

### Non-goals

- Not an Activity Monitor replacement, and not a process killer.
- No Intel-Mac support in v1. Apple Silicon only, on purpose.
- No telemetry, no network calls, no analytics. The app never phones home.

## 5. What is already proven

Measured on this machine (Apple M5, 10-core, 24 GB, macOS 26 / Darwin 25.5) as an ordinary user:

- `dlopen("/usr/lib/libIOReport.dylib")` resolves and every symbol we need binds. No entitlement,
  no root.
- A subscription to `CPU Stats`, `GPU Stats`, and `Energy Model` returns real sample deltas as
  `uid=501`, with no password prompt.
- GPU utilization comes from `GPU Stats / GPU Performance States` (channel `GPUPH`, 16 named
  P-states). It is the residency-weighted share of non-idle states, the same basis `powermetrics`
  reports.
- Power is granular. Separate energy counters cover E-cores, P-cores, per-core SRAM, GPU, and a
  CPU aggregate, each as energy used over the sample window. Divide by window length for watts.

**Resolved during P0.** Energy units differ per rail. The CPU aggregate reports in millijoules and
the GPU in nanojoules, so the reader now takes each channel's own unit label and normalises to
joules. Wattage comes out correct. Under a sustained Metal load, GPU power rose from 6 to 16 W
while CPU power fell from 13 to 7 W, exactly as work shifted onto the GPU.

**Calibrated against `powermetrics` (M5).** GPU utilization is `1 - OFF/total`, where `OFF`
(state 0) is the idle share and `P1` upward are active frequencies. `powermetrics` reports its
own "GPU active residency" the same way: its idle residency is exactly the `OFF` time, and its
338 to 1620 MHz frequency buckets are `P1` to `P13`. Verified with `scripts/calibrate/`: under a
sustained Metal load both read 100%, and at idle both read the small `P1` share the compositor
keeps the GPU awake for (about 17%, with GPU power near zero). The reading is no longer
provisional. GPU power in watts is exact too. The earlier "flat 100%" was a busy machine, not an
idle one.

Nothing in the core data path is guesswork. What is left is UI polish and generalising across
chips (§10), not whether the numbers are reachable.

## 6. Design direction

The look is the product here, so it gets first-class treatment, held to the same visual bar as the
site and blog work.

- **Native materials, not a web skin.** SwiftUI on the system blur and vibrancy material, SF Pro,
  SF Symbols, and the system accent color. The floating widget should be hard to tell apart from a
  first-party macOS gadget.
- **Ring gauges over bar clutter.** One ring per domain (CPU, GPU, memory), with a thin sparkline
  under each for the last minute or so. The palette stays restrained: neutral by default, warming
  toward amber and red only as a value climbs, so a hot core is the thing your eye catches.
- **Readable at a glance.** The menu-bar item and the widget both pass the squint test. You learn
  the machine's state without reading the digits.
- **Light and dark, automatically.** Every color is defined for both, and the widget tracks the
  system appearance.
- **No chartjunk.** No 3D, no decorative gradients, no gauge that encodes nothing. Every mark
  carries a value. That is data-viz discipline applied to a native surface.

Before any GUI code: a small set of static mockups (menu-bar item, popover, floating widget) in
both appearances, reviewed against this bar, then built to match.

## 7. Architecture

```
   ┌──────────────┐   ┌──────────────┐   ┌──────────────┐
   │  GUI (SwiftUI)│   │ CLI --json   │   │ MCP --mcp    │
   │  menu bar +   │   │ scripts, CI, │   │ agent-facing │
   │  floating     │   │ correctness  │   │ tools, stdio │
   │  widget       │   │ tests        │   │ read-only    │
   └──────┬───────┘   └──────┬───────┘   └──────┬───────┘
          └──────────────────┼──────────────────┘
                    ┌─────────▼─────────┐
                    │  SampleStore      │  1 Hz timer,
                    │  typed snapshots  │  rolling ~60s buffers
                    └─────────┬─────────┘
                    ┌─────────▼─────────┐
                    │  Sensors (no UI)  │
                    │  IOReportReader   │ → GPU%, power rails
                    │  CPUReader        │ → host_processor_info
                    │  MemReader        │ → host_statistics64+sysctl
                    └───────────────────┘
```

Three faces, one engine. The GUI, the CLI, and the MCP server are thin front-ends over the same
sensors core. That is why the MCP interface costs so little once the CLI exists.

- **Language and UI:** Swift 6, SwiftUI, and AppKit where it is needed (the floating `NSPanel`).
  Target macOS 14 and up, which covers M1 through M5.
- **Dependencies:** none. IOReport is reached through `dlopen` and typed function pointers, kept in
  one file with a plain note that these are private symbols.
- **Build:** a Swift Package Manager executable, assembled into a `.app` bundle with `LSUIElement`
  set so there is no Dock icon. A script produces the app, and CI builds and signs it.
- **A headless CLI target** (`vitals --json`) wraps the same sensors, so correctness is testable
  from the terminal and in CI with no GUI.
- **An MCP server target** (`vitals --mcp`) reuses those sensors and snapshot types to expose
  read-only tools over stdio. Local only, no network, no side effects. An agent can read the
  machine and never change it.

## 8. Correctness, and how we defend it

A monitor that shows wrong numbers is worse than no monitor.

- Cross-check every rail and utilization figure once against `sudo powermetrics` on the dev
  machine, and turn the ratios into unit tests over the CLI's JSON.
- Cross-check CPU% against `top` and Activity Monitor under a known load.
- Pin and document the private IOReport symbols. If a future macOS drops one, the CLI test fails
  loudly instead of the app quietly showing zeros.

## 9. Success criteria

- The app's own idle CPU overhead stays near 1% on this machine. A monitor must not be the load.
- Menu-bar and widget readings track Activity Monitor within a small tolerance under load.
- A first-time user gets a working menu-bar readout from one download and one launch, no password.
- The floating widget looks, to a macOS designer's eye, like it could ship with the OS.

## 10. Risks

| Risk | Likelihood | Mitigation |
| --- | --- | --- |
| Private IOReport symbols change across macOS versions | Medium | Isolate them in one file, fail the CLI test loudly, document the contract |
| Channel names differ between M1 to M4 and M5 | Medium | Discover channels by group and subgroup, not by hard-coded index, and run a test matrix if contributors have older chips |
| Gatekeeper friction on an unsigned app | High for OSS | Document the right-click-open path, notarize the app, and consider a Homebrew cask later |
| "Yet another system monitor" indifference | High | Compete only on look, the floating gadget, and zero dependencies. If the mockups do not clearly beat the field, stop |
| Power unit calibration wrong | Low | The one-time powermetrics validation is locked into tests before any wattage ships |

## 11. Decisions (settled 2026-09-07)

1. **Name.** Deferred. `mac-vitals` stays as the working name, and the real one gets locked before
   the first release, not before the build. Candidates in §12.
2. **License.** MIT.
3. **macOS floor.** macOS 14 Sonoma and up, which covers M1 through M5 with modern SwiftUI.
4. **MCP.** Ships in v1.0, not deferred.
5. **Menu-bar default content.** CPU%, GPU%, and memory pressure, with everything else in the
   popover.

## 12. Name candidates

- **Vitals** or **Mac Vitals.** Plain, says what it does.
- **SoCScope.** A nod to the system-on-chip it reads.
- **Glance.** The menu-bar-glance framing.
- **Pulse.** Common, and likely to collide with existing projects.
- **Reado** or **Rail.** After the IOReport rails it reads.

## 13. Phasing

- **P0, sensors and CLI.** The IOReport, CPU, and memory readers, `vitals --json`, the powermetrics
  calibration, and tests. Proves every number before any pixel.
- **P1, design mockups.** Menu-bar item, popover, and widget, in light and dark, reviewed to the
  quality bar.
- **P2, menu-bar app.** A `MenuBarExtra` live label with popover gauges.
- **P3, floating widget.** The always-on-top `NSPanel`, dragging, and position persistence.
- **P4, polish and release.** Launch at login, settings, signing and notarization, README, license,
  and a first tagged release.
- **P5, MCP server.** `vitals --mcp` over the same engine, read-only tools, an example agent
  config, and docs for adding it to Claude Code and other MCP clients.

## 14. Adding on top of Activity Monitor and Stats

Two incumbents set the bar. Activity Monitor's real strength is per-process attribution
and energy impact, but it is a window you open, with no widget and nothing else can read
it. Stats is the feature king: nine modules (CPU, GPU, RAM, disk, sensors, network,
battery, Bluetooth, clock), per-process top lists, temperatures and fans, notifications,
and deep menu-bar customization.

We do not win by out-featuring Stats. We add three things neither of them has:

1. **A real floating desktop widget.** Already built.
2. **An MCP interface.** An agent can read the machine. Already built.
3. **Task traces (the headline).** Bracket a piece of work, a build or a training run,
   and get back what it cost: CPU, GPU, memory, and watt-hours over that window. Neither
   incumbent frames monitoring as "measure this task," and it sits on our two unique
   strengths, per-rail power and MCP. A coding agent can wrap its own build in a trace and
   report the energy cost. That is the AI-native system monitor nobody else is building.

Parity worth reaching over time, none of it the wedge: per-process top lists, disk and
network throughput, sensors (temperature and fan), battery, threshold alerts, and a choice
of which modules show in the menu bar.
