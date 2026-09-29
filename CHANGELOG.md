# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- The Widget and Open buttons at the foot of the popover no longer break
  mid-word onto two lines ("Widge t"). The footer is a little tighter, so both
  labels fit on one line next to every status, including "Throttling".

## [0.4.1] - 2026-09-29

A fix for the ⋯ menu. Still a normal user, no `sudo`.

### Fixed

- The ⋯ menu no longer rebuilds itself while it is open. The popover redraws
  every second to show fresh readings, and the menu redrew with it, which reset
  its submenus under the pointer and made the Outfit list hard to pick from. It
  now redraws only when one of its own settings changes, and a change in the
  companion's status waits until the menu closes.

## [0.4.0] - 2026-09-28

A sun hat for the hot days, and two new reactions. Still a normal user, no
`sudo`.

### Added

- A straw sun hat for the Sun's out outfit on both characters, so both earned
  outfits now have art. Like the scarf, you put it on from the Outfit item in the
  ⋯ menu once it is earned.
- Two more reactions on both characters. A click now makes her wink or turn shy,
  blushing and glancing away, and now and then she winks or smiles with her eyes
  closed. They are extra clips in the pools packs already have (`click2.gif`,
  `idle2.gif`), so the pack format is unchanged.

### Changed

- The prebuilt zip grows from about 6 MB to about 7 MB with the new art.
- CI and the release workflow use `actions/checkout@v7`, which runs on Node 24,
  because GitHub is retiring Node 20.

## [0.3.0] - 2026-09-27

A face for the numbers. Still a normal user, no `sudo`.

### Added

- A desktop companion, off by default. Switch it on under ⋯ in the popover and a
  small anime character stands on your desktop. Her eyes follow the pointer, she
  blinks, a click makes her wink, and now and then she winks on her own. Drag her
  anywhere and she stays there. The line under the toggle says what the machine
  is doing: working when CPU or GPU load holds at 70% or more, hot when the chip
  holds at 85 °C or more, throttling the moment macOS says so, and hungry at 20%
  battery. A character pack that carries a picture for a state shows it on her
  face, and that includes sleepy after a minute with no input and asleep after
  five. Two characters ship, Rin (the default) and yuna, and both draw awake,
  blink and wink, so those other faces are there for you to draw. Packs use
  [mycat](https://github.com/yumiaura/mycat)'s format, so packs made for it work
  here, and your own go in `~/Library/Application Support/MacVitals/Companion/`.
  She hides while the menu-bar icon is off. See
  [docs/COMPANION.md](docs/COMPANION.md).
- Companion outfits, earned by how the machine runs. Two challenges to start:
  Cozy (a week of use with the Mac staying cool, at least 42 recorded hours) and
  Sun's out (a hot stretch or a spell of throttling), read from the recorded
  history. An earned outfit stays earned. Once earned, you put it on from the
  Outfit item in the ⋯ menu. A pack shows an outfit only when it carries the
  matching `outfit_<name>.png`. Both shipped characters come with a Cozy knit
  scarf, and more are yours to draw.
- Developer flags: `MacVitals --render-companion <png>` draws a strip of every
  state and gaze for a pack without a display (add `--companion-outfit <name>`
  to check a costume), and `--companion-probe <png>` dumps the live panel's
  layers and geometry.
- `vitals --selftest` now runs the companion's logic checks (config decoding,
  fit and gaze geometry, the mood latches, the frame engine) alongside the
  sensor bounds.

### Changed

- The prebuilt zip grows from about 1 MB to about 6 MB, because the two
  characters ship as art.
- `scripts/build-app.sh` copies the character packs into the app and now stops
  if signing fails. It used to carry on silently.

## [0.2.1] - 2026-09-10

Reading the numbers at a glance, and catching a run that has started to
throttle. All still a normal user, no `sudo`.

### Added
- **A CPU trend line in the menu bar.** The last minute of CPU load, drawn as a
  small sparkline beside the numbers, so the bar shows where load is heading and
  not just its value this instant.
- **Throttling warning in the menu bar.** When the machine starts throttling, the
  readout turns amber, then red when pressure is critical, with a warning
  triangle. It is the alert without a system notification, which suits a tool that
  already lives in the menu bar and needs no notification permission to work.
- **Hover readout on the full-window charts.** Move the mouse over any chart and a
  guide line, a dot on each series, and a small card show the exact time and value
  at that point, snapped to the nearest real sample rather than interpolated.
- A **per-core grid** in the full window: one load bar per logical core, the
  efficiency cluster then the performance cluster, colored by load. Watching all
  cores during a build or an inference run is a glance now.

## [0.2.0] - 2026-09-09

Metrics for people running local models, a diagnostic view of what is using the
machine, plus the always-on and distribution work. Everything still reads as a
normal user, with no `sudo`.

### Added
- **Top processes**: what is using the machine right now, sorted by CPU or
  memory, read as a normal user through `libproc`. Shows in the full window as a
  panel, on the command line (`vitals --top`, `--top --mem`), and as a
  `get_top_processes` MCP tool. Per-process GPU is not available to a normal
  user, so it is deliberately left out rather than guessed.
- **Neural Engine (ANE) power**, from the Energy Model. Near zero for GPU-based
  LLMs, which itself confirms a run is on the GPU and not the ANE.
- **Memory-fit signals**: the OS memory-pressure level, swap in use, and how
  much memory the GPU may use (Metal's recommended working-set size). Together
  they answer "will this local model fit, and why did generation slow down."
- **Thermal throttling**: the OS thermal-pressure state, shown as a throttling
  indicator in the popover, the window, and the CLI. Sustained inference is
  exactly when this matters.
- Launch at Login, off by default, in the popover's `⋯` menu, with a one-time
  opt-in hint on first open. Registered through `SMAppService`, no helper and no
  privileged step. Diagnostic flags (`--login-status`, `--login-register`,
  `--login-unregister`) verify the registration from the terminal.
- A "Show Menu Bar Icon" toggle in the `⋯` menu, on by default. Turn it off and
  the app keeps recording with no icon, after a plain explanation. Reopening the
  app brings the icon back. Pairs with Launch at Login for a quiet recorder.
- A full walkthrough in [docs/WALKTHROUGH.md](docs/WALKTHROUGH.md) and a project
  site at [netsatsawat.github.io/mac-vitals](https://netsatsawat.github.io/mac-vitals/).
- `--dump-ioreport`, a diagnostic that lists every IOReport channel, for
  discovering private channels across chip generations.

### Changed
- Task traces now also report whether the run **thermally throttled** and its
  **peak swap**, so a run that slowed down explains itself. In the app, the CLI,
  and over MCP.
- The popover's status pill now reflects the real memory and thermal pressure
  ("Normal", "Elevated", "Throttling", "Critical") instead of a fixed label.

### Investigated and dropped
- DRAM memory bandwidth. The `AMC Stats` counters that carry it do not bind for
  a normal user, so reading them would require `sudo`. The project will not, so
  bandwidth is out until there is a password-free path to it.

## [0.1.0] - 2026-09-08

First public cut. Everything reads as a normal user, with no `sudo`, no
dependencies, no helper daemon, and no kernel extension.

### Added
- Sensors engine (`VitalsCore`) reading CPU (overall plus the efficiency and
  performance clusters and every core), GPU, memory, and per-rail power on Apple
  Silicon through IOReport and Mach.
- Network, disk, and battery readings, plus temperature and fan from the SMC.
- Task traces: bracket a build or a run and get back what it cost in CPU, GPU,
  watt-hours, and bytes moved. Available in the app, the CLI, and over MCP.
- SwiftUI app with four faces over one engine: a menu-bar readout, a popover
  with a minute of history, a draggable always-on-top floating widget, and a
  full window charting every metric from one minute to a year, plus year-to-date.
- History persisted across restarts at three resolutions, keyed by wall-clock
  bucket, so short ranges no longer regather on launch and the long ranges fill
  from the data already on disk. See [docs/history-persistence.md](docs/history-persistence.md).
- `vitals` CLI: `--json`, `--watch`, `--trace <seconds>`, `--selftest`, `--mcp`.
- MCP server (`vitals --mcp`) exposing read-only `get_vitals`,
  `get_vitals_history`, `start_trace`, and `stop_trace` tools over stdio. See
  [docs/MCP.md](docs/MCP.md).
- Design system, a rendered hero and window screenshot, an app icon, and a
  social preview card.

### Calibrated
- GPU utilization is calibrated against `powermetrics` on the M5. It comes from
  the GPU's performance-state residency, where state 0 (`OFF`) is idle, so
  `usage = 1 - OFF/total`. GPU power in watts is exact.

[Unreleased]: https://github.com/netsatsawat/mac-vitals/compare/v0.4.1...HEAD
[0.4.1]: https://github.com/netsatsawat/mac-vitals/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/netsatsawat/mac-vitals/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/netsatsawat/mac-vitals/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/netsatsawat/mac-vitals/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/netsatsawat/mac-vitals/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/netsatsawat/mac-vitals/releases/tag/v0.1.0
