<div align="center">

<img src="docs/hero.png" alt="Mac Vitals: a menu-bar item, popover, and floating widget showing CPU, GPU, memory, and power" width="880">

# Mac Vitals

**A live CPU, GPU, memory, and power monitor for Apple Silicon.**
No password. No dependencies. And the same engine speaks MCP, so your coding agent can read the machine too.

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
- **No password, ever.** Everything comes through Apple's IOReport interface as a normal user.
- **Zero dependencies.** One Swift package, no runtime, no helper daemon, no kernel extension.
- **Light and dark**, following the system, on native vibrancy.
- **An MCP server** so an agent can ask what a build or a training run cost the machine.

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
| `get_vitals` | One live reading: CPU (overall plus E and P clusters), GPU, memory, and power in watts. |
| `get_vitals_history` | Per-second history for up to the last 60 seconds of CPU%, GPU%, memory%, and watts. |

Both are read-only. The agent can see the machine and never change it.

## How it works

Apple Silicon exposes its telemetry through a private framework called IOReport, the same source `powermetrics` reads. The difference is that a normal user can subscribe to it directly, with no root and no entitlement, once you resolve the symbols yourself.

```
   ┌──────────────┐   ┌──────────────┐   ┌──────────────┐
   │  GUI (SwiftUI)│   │ CLI --json   │   │ MCP --mcp    │
   │  menu bar +   │   │ scripts, CI  │   │ agent-facing │
   │  widget       │   │              │   │ read-only    │
   └──────┬───────┘   └──────┬───────┘   └──────┬───────┘
          └──────────────────┼──────────────────┘
                    ┌─────────▼─────────┐
                    │   Sensors (core)  │
                    │  IOReport · Mach  │
                    └───────────────────┘
```

- **CPU** comes from Mach's `host_processor_info`, diffed per core each second.
- **Memory** comes from `host_statistics64` plus `hw.memsize`.
- **GPU and power** come from IOReport, loaded at runtime from `/usr/lib/libIOReport.dylib`. Those private symbols live in one file, so if a future macOS changes them, exactly one place fails and says so.

### A note on GPU percent

GPU utilization is marked **provisional** in the UI, and that is deliberate. It comes from the GPU's performance-state residency, and every tool of record treats state 0 as idle. That holds on M1 through M4. On the M5, that state stays near zero while the display is on and the GPU parks in its lowest active state instead, so the usual formula reads a flat 100%. The interim reading treats both states as idle and flags itself until it is calibrated against one `powermetrics` run. GPU **power** in watts is exact today, and it is the GPU signal to trust in the meantime.

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
- [ ] Calibrate GPU percent against `powermetrics` on M-series
- [ ] Network and disk throughput
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
