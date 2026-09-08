<div align="center">

<img src="docs/hero.png" alt="Mac Vitals: a menu-bar item, popover, and floating widget showing CPU, GPU, memory, and power" width="880">

# Mac Vitals

**A live CPU, GPU, memory, and power monitor for Apple Silicon.**
No password. No dependencies. And the same engine speaks MCP, so your coding agent can read the machine too.

[![CI](https://github.com/netsatsawat/mac-vitals/actions/workflows/ci.yml/badge.svg)](https://github.com/netsatsawat/mac-vitals/actions/workflows/ci.yml)
![Platform](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-M1--M5-0a84ff)
![Swift](https://img.shields.io/badge/Swift-6-f05138?logo=swift&logoColor=white)
![No sudo](https://img.shields.io/badge/sudo-not%20required-34c759)
![License](https://img.shields.io/badge/license-MIT-blue)

</div>

---

## Why this exists

Every Apple Silicon Mac already measures itself in detail. Reaching that data is the hard part. `powermetrics` shows the most and wants `sudo` on every launch. Activity Monitor keeps GPU and per-core power behind a window you have to open. Mac Vitals reads all of it as a normal user and puts it one glance away, in a look that belongs on macOS.

It shows up three ways, over one engine:

- a **menu-bar item** you read at a glance,
- a **floating widget** you park anywhere on the desktop,
- and an **MCP server** an AI agent can query.

## Features

- **CPU** overall, plus the efficiency and performance clusters split out, plus every core.
- **GPU** utilization from the hardware's own performance-state residency.
- **Memory** used against total, the way Activity Monitor counts it.
- **Power** in watts, per rail: CPU and GPU, read from the chip's energy counters.
- **Network, disk, and battery** too: up and down throughput, read and write activity with free space, and charge.
- **Temperature and fan** from the SMC, and **task traces** that measure what a build or run cost (CPU, GPU, watt-hours, bytes moved) in the app, the CLI, and over MCP.
- **A full window** with every metric charted from the last minute to a full year, plus year-to-date, with all three resolutions persisted so every range picks up where it left off and the long ranges fill in over time.
- **No password, ever.** Everything comes through Apple's IOReport interface as a normal user.
- **Zero dependencies.** One Swift package, no runtime, no helper daemon, no kernel extension.
- **Light and dark**, following the system, on native vibrancy.
- **An MCP server** so an agent can ask what a build or a training run cost the machine.

## The full window

Open it from the popover for every metric charted over a selectable range, from one minute of live detail up to a year, plus year-to-date. Three resolutions keep it cheap: live seconds in memory for the short ranges, one-minute averages persisted for about a week, and one-minute samples rolled up into one-hour averages persisted for over a year. All told a few MB, and the long ranges survive quits and fill in as the app runs.

<div align="center">
<img src="docs/window.png" alt="The Mac Vitals window: CPU, GPU, memory, power, network, and disk charted over the last fifteen minutes" width="840">
</div>

## Install

Mac Vitals is young and not yet notarized, so build it from source. You need macOS 14 or later on Apple Silicon and the Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/netsatsawat/mac-vitals.git
cd mac-vitals
./scripts/build-app.sh
open build/MacVitals.app
```

The app lives in the menu bar with no Dock icon. To keep it around, drag `build/MacVitals.app` into `/Applications`.

## Using it

- **Menu bar:** a compact CPU and GPU readout, refreshed once a second.
- **Click it** for the popover: CPU, GPU, memory, and power, each with a minute of history.
- **Show widget** (in the popover) toggles the floating gadget. Drag it anywhere. It floats above other windows and remembers where you left it.
- **Quit** from the popover's `⋯` menu.

## Command line

The same engine ships as a headless CLI, handy for scripts and for confirming a reading.

```bash
swift build -c release --product vitals
.build/release/vitals            # one human-readable reading
.build/release/vitals --json     # one reading as JSON
.build/release/vitals --watch    # stream once a second
.build/release/vitals --trace 30 # measure the next 30s and print the cost
.build/release/vitals --selftest # bounded-value check, exits 0 or 1
```

## For your AI agent (MCP)

Mac Vitals runs as a [Model Context Protocol](https://modelcontextprotocol.io) server over stdio, read-only. Point an MCP client at the built `vitals` binary with the `--mcp` flag.

In Claude Code:

```bash
claude mcp add mac-vitals -- /absolute/path/to/mac-vitals/.build/release/vitals --mcp
```

Or in a client's JSON config:

```json
{
  "mcpServers": {
    "mac-vitals": {
      "command": "/absolute/path/to/mac-vitals/.build/release/vitals",
      "args": ["--mcp"]
    }
  }
}
```

Two tools are exposed:

| Tool | What it returns |
| --- | --- |
| `get_vitals` | One live reading: CPU (overall plus E and P clusters), GPU, memory, power, network, disk, battery, temperature. |
| `get_vitals_history` | Per-second history for up to the last 60 seconds of CPU%, GPU%, memory%, and watts. |
| `start_trace` / `stop_trace` | Bracket a task. `stop_trace` returns what it cost: CPU and GPU average and peak, average watts and energy in watt-hours, network and disk totals, and peak temperature. |

They are read-only. The agent can see the machine and never change it. An agent can wrap its own build in `start_trace` … `stop_trace` and get the energy and resource cost back. Full setup and examples are in [docs/MCP.md](docs/MCP.md).

## How it works

Five front-ends read from one Swift engine, which reads every metric from the system as a normal user, with no root and no entitlement.

<div align="center">
<img src="docs/architecture.png" alt="Mac Vitals architecture: five faces (menu bar, popover, widget, CLI, MCP) over one engine, over no-sudo sensors" width="900">
</div>

- **CPU and memory** from Mach (`host_processor_info` diffed per core, `host_statistics64`, `hw.memsize`).
- **GPU and power** from IOReport, loaded at runtime from `/usr/lib/libIOReport.dylib`. Those private symbols live in one file, so a future macOS change fails in one obvious place.
- **Network** from `getifaddrs`, **disk and battery** from IOKit, **temperature and fan** from the SMC.

For the agent interface, see [docs/MCP.md](docs/MCP.md).

### A note on GPU percent

GPU utilization is **calibrated against `powermetrics`** on the M5. It comes from the GPU's performance-state residency, where state 0 (`OFF`) is the idle share and the active frequencies (338 to 1620 MHz) are the rest, so `usage = 1 - OFF/total`. That matches how `powermetrics` reports its own "GPU active residency": under a sustained Metal load both read 100%, and at idle both read the small share the compositor keeps the GPU awake for. GPU **power** in watts is exact too.

## How it compares

Mac Vitals is a newcomer on a well-served shelf. It competes on three things, not on feature count.

| | Mac Vitals | stats | macmon | iStat Menus |
| --- | :---: | :---: | :---: | :---: |
| Reads without `sudo` | ✅ | ✅ | ✅ | ✅ |
| Native menu-bar item | ✅ | ✅ | | ✅ |
| Floating desktop widget | ✅ | | | partial |
| Agent-readable (MCP) | ✅ | | | |
| Zero dependencies | ✅ | ✅ | ✅ | |
| Open source | ✅ | ✅ | ✅ | |
| Price | free | free | free | paid |

If you want the most features today, `stats` is excellent. Mac Vitals is for people who want the native look, the floating gadget, and an interface their agent can read.

## Roadmap

- [x] Sensors engine and CLI
- [x] Menu-bar item and popover
- [x] Floating widget
- [x] MCP server
- [x] Full window with history from 1 minute to 1 year (plus YTD), persisted across restarts
- [x] Network, disk, and battery
- [x] Calibrate GPU percent against `powermetrics` (M5)
- [x] Task traces (app, CLI, and MCP)
- [x] Temperature and fan (SMC)
- [ ] Per-process attribution (what is using the machine)
- [ ] Launch at login toggle
- [ ] Notarized release and a Homebrew cask

## Development

```bash
swift build            # build everything
.build/debug/vitals --selftest   # quick correctness check (no Xcode needed)
swift test             # unit tests (needs a full Xcode toolchain)
```

The core is in `Sources/VitalsCore` and has no UI. The app is `Sources/MacVitals`, the CLI and MCP server are `Sources/vitals`. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE) © Net Satsawat
