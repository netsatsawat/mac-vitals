# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Sensors engine (`VitalsCore`) reading CPU, memory, GPU, and per-rail power on
  Apple Silicon through IOReport and Mach, with no `sudo` and no dependencies.
- `vitals` CLI: `--json`, `--watch`, and `--selftest`.
- MCP server (`vitals --mcp`) exposing read-only `get_vitals` and
  `get_vitals_history` tools over stdio.
- SwiftUI app: a menu-bar item, a popover with a minute of history, and a
  draggable, always-on-top floating widget.
- Design mockup and a rendered hero for the README.

### Known limitations
- GPU utilization is provisional on the M5 until it is calibrated against a
  single `powermetrics` run. GPU power in watts is exact.
- The app's steady-state CPU overhead still wants a tuning pass.

[Unreleased]: https://github.com/netsatsawat/mac-vitals/commits/main
