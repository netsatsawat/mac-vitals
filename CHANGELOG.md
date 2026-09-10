# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- A **per-core grid** in the full window: one load bar per logical core, the
  efficiency cluster then the performance cluster, colored by load. Watching all
  cores during a build or an inference run is a glance now.
- **Throttling warning in the menu bar.** When the machine starts throttling, the
  readout turns amber, then red when pressure is critical, with a warning
  triangle. It is the alert without a system notification, which suits a tool that
  already lives in the menu bar and needs no notification permission to work.
- **Hover readout on the full-window charts.** Move the mouse over any chart and a
  guide line, a dot on each series, and a small card show the exact time and value
  at that point, snapped to the nearest real sample rather than interpolated.
- **A CPU trend line in the menu bar.** The last minute of CPU load, drawn as a
  small sparkline beside the numbers, so the bar shows where load is heading and
  not just its value this instant.

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

[Unreleased]: https://github.com/netsatsawat/mac-vitals/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/netsatsawat/mac-vitals/releases/tag/v0.1.0
