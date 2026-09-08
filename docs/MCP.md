# Using Mac Vitals from an AI agent (MCP)

Mac Vitals runs as a [Model Context Protocol](https://modelcontextprotocol.io) server, so an AI coding agent can read this Mac's live state and measure what its own work costs. The server is read-only and local. It never changes the machine and never touches the network.

## Setup

Build the CLI once. It carries the MCP server behind the `--mcp` flag.

```bash
cd mac-vitals
swift build -c release --product vitals
```

Add it to Claude Code:

```bash
claude mcp add mac-vitals -- /absolute/path/to/mac-vitals/.build/release/vitals --mcp
```

Or point any MCP client at it through JSON:

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

The server speaks JSON-RPC 2.0 over stdio. It has no dependencies and starts instantly.

## The tools

### `get_vitals`

One live reading of the whole machine. No arguments.

```jsonc
// The text content the agent receives, trimmed:
{
  "cpu":     { "usage": 42.1, "efficiencyUsage": 18.0, "performanceUsage": 66.2,
               "perCore": [ ... ], "efficiencyCoreCount": 6, "performanceCoreCount": 4 },
  "gpu":     { "usage": 71.0, "available": true, "provisional": false },
  "memory":  { "usedPercent": 59.0, "usedBytes": 15250000000, "totalBytes": 25769803776,
               "wiredBytes": ..., "compressedBytes": ..., "appBytes": ... },
  "power":   { "cpuWatts": 11.3, "gpuWatts": 9.8, "totalWatts": 21.1, "available": true },
  "network": { "downloadBytesPerSec": 5300000, "uploadBytesPerSec": 420000 },
  "disk":    { "readBytesPerSec": 0, "writeBytesPerSec": 900000,
               "freeBytes": 1656000000000, "totalBytes": 1995000000000 },
  "battery": { "present": true, "percent": 100, "isCharging": false, "minutesRemaining": null },
  "thermal": { "available": true, "socTempC": 35.6, "fanRPM": 2502, "fanPresent": true },
  "timestamp": "2026-09-08T03:11:53Z"
}
```

### `get_vitals_history`

Per-second history for up to the last 60 seconds. Optional `seconds` argument (1 to 60, default 30).

```json
{ "seconds": 5, "gpuProvisional": false,
  "samples": [ { "t": "...", "cpu": 40.2, "gpu": 71.0, "memory": 59.0, "watts": 21.1 }, ... ] }
```

### `start_trace` and `stop_trace`

Bracket a task and get its cost. Call `start_trace`, run the work, then `stop_trace`. Only one trace runs at a time.

`stop_trace` returns:

```json
{
  "durationSeconds": 92.4,
  "samples": 92,
  "cpuAvgPercent": 64.1, "cpuPeakPercent": 98.0,
  "gpuAvgPercent": 12.0, "gpuPeakPercent": 55.0,
  "avgWatts": 28.7, "energyWattHours": 0.736,
  "networkDownBytes": 1250000000, "networkUpBytes": 45000000,
  "diskReadBytes": 3400000000, "diskWriteBytes": 1100000000,
  "socTempPeakC": 78.0
}
```

## Example: measure what a build costs

The trace tools let an agent measure its own work. A run looks like this:

1. Agent calls `start_trace`.
2. Agent runs the build (for example `swift build -c release`).
3. Agent calls `stop_trace`.
4. It reports back: "that build took 92 seconds, averaged 65% CPU, peaked at 98%, and used 0.74 watt-hours, with 3.4 GB read from disk."

A number like that is not something the other monitors expose to an agent.

## Verifying it works

```bash
python3 scripts/test-mcp.py .build/release/vitals
```

That runs a full session (initialize, list, `get_vitals`, and a trace) and checks every response. It also runs in CI.
