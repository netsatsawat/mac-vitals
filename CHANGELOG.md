# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
