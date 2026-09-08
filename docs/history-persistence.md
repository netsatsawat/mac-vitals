# How history survives a restart

Close a monitor and reopen it, and the charts should not start from a blank page. Getting there took one idea, applied in three places. This note records the design and the trade-offs behind it, so the next person to touch the store knows why it looks the way it does.

## The problem it fixes

The first version tied aggregation to the process. Each coarser tier was built by an in-memory counter: "every 60th live sample becomes a minute, every 60th minute becomes an hour." That counter emptied on launch, and two bugs fell out of the one flaw.

- The per-second detail was never written to disk, so the short ranges (1 minute, 15 minutes, 1 hour) regathered from nothing on every launch.
- The hour tier needed 60 uninterrupted minutes in a single run. On a machine that sleeps and reopens through the day, it never got them. The file stayed empty even with hours of minute data sitting next to it.

## The idea

Treat the store as one time series kept at three resolutions, where each coarser tier is a plain downsample of the tier below, keyed by wall-clock time.

The bucket a sample belongs to is a function of its timestamp, not its position in a stream:

```
bucketStart(t, width) = floor(t / width) * width
```

A minute point is the average of the per-second samples whose timestamps land in the same 60-second bucket. An hour point is the average of the minute points in the same 3600-second bucket, stamped at the bucket's start.

That one change makes the rollup **idempotent** (running it twice adds nothing the second time, because the bucket is already there), **restart-safe** (a bucket is defined by the clock, not by how long the app has been up), and **gap-safe** (a bucket the app slept through simply has no members and produces no point).

## The three tiers

| Tier | Resolution | Kept for | On disk | Size |
| --- | --- | --- | --- | --- |
| seconds | 1 s | last hour | `seconds.ndjson` | about 540 KB |
| minutes | 60 s | about 8 days | `minutes.ndjson` | about 1.7 MB |
| hours | 3600 s | over a year | `hours.ndjson` | about 1.4 MB |

All of it loads into memory on launch. Disk is only durability. Charts read memory, so drawing never waits on a file. A range picks the tier whose resolution fits its span, filters to the cutoff, and thins to about 500 points to draw.

Every tier holds the same row, a compact `Sample` of the ten scalars the charts and traces need. The live instantaneous readout still uses the richer `Snapshot` (per core, the memory breakdown, battery), but history does not carry that weight.

## Reconcile, on launch and on the minute

One function does the aggregation. Given a finer tier and a coarser one, it finds every fully elapsed bucket the finer tier covers, and for any that the coarser tier does not already hold, it averages the members and appends the point.

It runs at launch with everything the finer tier loaded, which is what backfills the hour tier from the minute data without waiting for a 60-minute run. It runs again after each tick, closing a minute once a minute and an hour once an hour. Because it is keyed by bucket, the launch pass and the steady passes cannot double-count.

An in-progress bucket is left alone until it has fully elapsed, so the newest hour point can be up to an hour behind. That matches what a 30-day chart needs and keeps the write cadence low.

## Why not just read what macOS already keeps

The fair question before building any of this: does the Mac already keep this history, so we could read it instead of storing our own? The honest answer is no, not for what these charts show.

macOS does keep some things. There is a real SQLite store under `/private/var/db/powerlog` that logs battery and app-energy analytics. `pmset -g log` keeps a history of power-state events and battery charge. Both exist, and the powerlog file even happens to be readable without a password today. But they are the wrong data. What they record is battery and energy for Apple's own analytics, not the per-second CPU, GPU, and memory utilization these charts are made of. The powerlog schema is private and Apple rewrites it between releases, so building on it means building on sand, and a notarized sandboxed app cannot reach into that folder at all.

The live tools are no help for history either. Activity Monitor and `powermetrics` sample the moment and keep nothing. Their little graphs are a few minutes of memory that vanish when you close them. And unlike Linux, macOS ships no background metrics collector, no `sar`, no `atop`, that quietly records utilization to disk for later.

So the numbers this app charts do not live in any store we could query. We already read them live, as a normal user, from IOReport and Mach. The only piece with no system equivalent is keeping those readings over time, and that piece is small. Leaning on powerlog would have meant more fragility for data that does not even answer the question. Storing a few MB of our own readings is the simpler and sturdier path.

## Why files and not SQLite

SQLite would be the textbook answer, and it is a system library, so it would not add a dependency. It was still the wrong call here. The whole dataset is a few MB and about 30,000 rows on a single machine read by one reader. NDJSON with the deterministic rollup solves the actual bugs with far less surface, stays readable with `cat`, and matches the rest of the project. SQLite is the escalation path if this ever becomes many metrics times long retention times frequent queries, which a single-Mac monitor will not reach.

## Writing without becoming the load

A monitor must not be the thing it is measuring. The seconds tier appends one small line per second and trims the file only when it drifts a slack past its cap, roughly every fifteen minutes, so steady-state cost is one short write a second and no periodic full rewrite. The minute and hour tiers write far less often. There is no flush-on-quit to get right, because the current second is already on disk. A hard kill loses nothing the next launch cannot rebuild from the finer tier.

## What a reader can rely on

- Reopen the app and the last hour of per-second detail is already there. No regather.
- The long ranges fill from the minute data on the first launch after they have any, not after an unbroken hour of uptime.
- Sleep, quit, and reopen leave honest gaps rather than fabricated continuity.
- Old history files still load. The `Sample` row has the same fields the earlier `MinuteSample` did, and the added ones are optional.
