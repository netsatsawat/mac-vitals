# Contributing to Mac Vitals

Thanks for looking. Mac Vitals is meant to stay small, readable, and dependency-free, so contributions that keep it that way are the most welcome.

## Getting set up

You need macOS 14 or later on Apple Silicon and the Xcode Command Line Tools.

```bash
git clone https://github.com/netsatsawat/mac-vitals.git
cd mac-vitals
swift build
.build/debug/vitals --selftest   # confirms the readers return sane values
./scripts/build-app.sh && open build/MacVitals.app
```

## How the code is laid out

- `Sources/VitalsCore` is the engine and has no UI. The readers, the snapshot types, and the IOReport binding live here.
- `Sources/vitals` is the headless CLI and the MCP server.
- `Sources/MacVitals` is the SwiftUI app: menu-bar item, popover, and floating widget.
- `docs/` holds the PRD, the design mockup, and the README hero.

Three front-ends sit on one engine, so a new metric is added once in `VitalsCore` and then surfaced in each face.

## The rules that keep it clean

- **No third-party dependencies.** If you reach for a package, open an issue first and make the case.
- **Private symbols stay in one file.** Everything undocumented that Apple exposes through IOReport is resolved in `Sources/VitalsCore/IOReport.swift`. Add new private symbols there, with a comment, so a future macOS change fails in one obvious place.
- **A monitor must not be the load.** Watch the app's own CPU and memory. Sample once a second, and do not redraw more than you must.
- **Numbers must be defensible.** A wrong reading is worse than none. If you add a metric, say where it comes from and how you checked it. Cross-check against `powermetrics`, `top`, or Activity Monitor and note the result in the PR.

## Adding a metric, end to end

1. Add a reader in `VitalsCore` and a field to the matching snapshot type in `Snapshot.swift`.
2. Extend `--selftest` in `Sources/vitals/SelfTest.swift` with a bounds check.
3. Surface it in the popover and widget, and in the MCP tool output if it belongs there.

## Before you open a PR

```bash
swift build -c release
.build/release/vitals --selftest
swift test        # needs a full Xcode toolchain, not just Command Line Tools
```

Keep the diff focused, match the surrounding style, and describe how you verified any reading you changed.

## Reporting a bug

Include your chip (for example M2 Pro, M5), your macOS version, and what `vitals --json` prints. Wrong numbers are the bugs that matter most, so a reading next to what Activity Monitor or `powermetrics` shows is the most useful thing you can attach.
