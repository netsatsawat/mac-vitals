# The companion

A small character who stands on your desktop while Mac Vitals runs. She is off by default. To switch her on, click the menu-bar item, open the `⋯` menu, and turn on Companion. The line under the toggle tells you what she is doing right now, for example "rin is working".

The app ships two characters, Rin and yuna. Rin, an anime schoolgirl, is the default. Yuna is a rounder chibi. Switch between them with the `companionName` setting below.

She hides while the menu-bar icon is off (background mode) and comes back with it.

## What she does

Four things happen on her face. Her eyes follow your pointer. She blinks every few seconds. Click her and she either winks or turns shy, blushing and glancing away. And every minute or two (60 to 150 seconds, from her config) she either winks or smiles with her eyes closed. Which one she picks is random each time. These are ordinary pack clips (`click1.gif` and `click2.gif`, `idle1.gif` and `idle2.gif`), so a pack of your own can have as many reactions as you draw.

Underneath, the engine tracks what the machine is doing, and the status line in the `⋯` menu reports it:

- **Awake.** Nothing else applies.
- **Sleepy** after a minute with no keyboard, mouse or trackpad input, and **asleep** after five minutes. Any input wakes her, and opening the menu is input too, so you will rarely see these two in the status line. They show on her face when the pack has the art (`sleepy.png`, `sleep.png`), and the shipped characters do not have it yet.
- **Working** when CPU or GPU load holds at 70% or more for three readings in a row. She stops when it holds under 55% for five. The gap between the two lines is what keeps her from flickering on a load that hovers near the line.
- **Hot** when the chip holds at 85 °C or more for three readings, until it holds under 70 °C for five. Only on Macs where the temperature sensor is readable.
- **Throttling** the moment macOS reports serious or critical thermal pressure, the same thermal signal that colours the menu-bar readout.
- **Hungry** at 20% battery or less while not charging. Charging ends it at once. A desktop Mac never gets hungry.

When several apply, the first of these wins: throttling, hot, hungry, asleep, working, sleepy, awake. A warning outranks sleep because it is what you want to see when you come back to the desk. Sleep outranks work because a long build with nobody at the desk should still look like nobody is at the desk.

The load and heat lines are the stops of the popover's own colour ramp (green to 55, yellow at 70, orange at 85), so a state changes where the rings change colour. The battery and idle lines come from the character pack's `config.json`.

A character pack that carries a picture for a state shows it on her face. When the picture is missing she shows the next state down that has one, and the status line still names the real state. Neither shipped pack has state pictures yet, so the face stays awake while the menu says "rin is working". The pictures are yours to draw, one PNG per state, and the section below says what to name them.

## Moving her

Drag her anywhere. She remembers the spot, and she keeps it across restarts. A short press is a click. Moving three points or more is a drag. She floats above other windows and shows on every Space.

## Challenges and outfits

She can earn outfits by how the machine runs over time, read from the same history the charts are drawn from. An earned outfit is an achievement: once you have it, it stays, so a Mac that runs cool for a week and then runs hot keeps both. Two challenges ship:

- **Cozy**: a week of use with the Mac staying cool. The app only records while it runs and the Mac is awake, so it counts the hours it saw: at least 42 across the last seven days (about six a day), spread over the week, every one at 55 °C or below and none throttling. It needs a Mac whose temperature sensor can be read.
- **Sun's out**: a hot stretch, two hours or more running at 85 °C or above, or any spell of throttling.

An outfit only shows up when the character pack has a picture for it. Once the pack has the art, an Outfit item appears in the `⋯` menu: it lists any outfits you have earned, None, and the locked ones underneath as hints of what earns them. The numbers above are design choices, set in `CompanionChallengeRules`, not readings.

Both shipped characters come with an outfit for each challenge: a knit scarf for Cozy (`outfit_cozy.png`) and a straw sun hat for Sun's out (`outfit_sunny.png`). Earning one does not dress her by itself: once it is earned, pick it from the Outfit menu. An outfit a pack has no art for does not appear in the menu, even when earned. Draw more the same way: an outfit is a full-canvas `outfit_<name>.png` on the same canvas as `static.png`, drawn over her body and under her eyes. The names that pair with the two challenges are `outfit_cozy.png` and `outfit_sunny.png`.

## Character packs

Packs use the format of [mycat](https://github.com/yumiaura/mycat), a desktop pet built on the same idea, so a pack drawn for it works here. A pack is a folder:

| File | Role |
| --- | --- |
| `static.png` | Required. Her resting pose, eyes drawn as empty white sockets when the pack has live pupils. |
| `eye_left.png`, `eye_right.png` | The iris sprites drawn over the sockets. Both, plus an `eyes` block in the config, turn on live pupils. |
| `blink.png` | Eyes closed. Also the squint on a click when there is no click clip. |
| `busy.png`, `hot.png`, `throttle.png`, `hungry.png`, `sleepy.png`, `sleep.png` | One still per state, all optional. |
| `yawn.gif` | Played once when she turns sleepy, whether or not the pack has `sleepy.png`. |
| `sleep_in.gif`, `sleep_out.gif` | Played once when she falls asleep and when she wakes. `sleep_out.gif` plays only when she was shown asleep, so it needs `sleep.png` or `sleep_in.gif` beside it. |
| `idle1.gif`, `idle2.gif`, … | A random one plays now and then while she is awake. |
| `click1.gif`, `click2.gif`, … | A random one plays when she is clicked. |
| `hungry1.gif`, `hungry2.gif`, … | A random one plays now and then while she is hungry. |
| `outfit_cozy.png`, `outfit_sunny.png`, … | A costume overlay. Once its challenge is earned, pick it from the Outfit menu. Full canvas, drawn over the body and under the eyes. |
| `config.json` | Sizes, eye positions and timings. Every key is optional. |

Filenames are matched in lower case, and a numbered pool is the prefix followed by digits only (`idle1.gif`, `idle12.gif`, not `idle_a.gif`).

### config.json

Yuna's file, as shipped:

```json
{
  "name": "yuna",
  "max_width": 220,
  "max_height": 330,
  "eyes": { "travel_radius": 10.0, "left": { "x": 225.5, "y": 400.5 }, "right": { "x": 442.0, "y": 400.0 } },
  "blink": { "enabled": true, "every": [3, 7], "duration": 0.28 },
  "click_squint": 0.5,
  "idle": { "random_every": [60, 150] }
}
```

The eye positions are pixel coordinates on her own 669x1243 `static.png`, measured from its top-left corner, so they mean nothing for another drawing. What each key does, and what it defaults to when left out:

| Key | Meaning | Default |
| --- | --- | --- |
| `name` | Shown in the status line. | The folder name |
| `max_width`, `max_height` | The box she is shrunk to fit, in points. She is never enlarged. | 200, 400 |
| `eyes.left`, `eyes.right` | Iris centres in `static.png` pixels. | None: no `eyes` block means no live pupils |
| `eyes.travel_radius` | How far a pupil may move from its centre, in `static.png` pixels. | 0 |
| `blink.enabled` | Whether she blinks. | Whether `blink.png` exists |
| `blink.every` | Seconds between blinks, a random draw between the two. | [3, 7] |
| `blink.duration` | Seconds the eyes stay shut. | 0.28 |
| `click_squint` | Seconds the blink frame is held on a click when there is no click clip. | 0.5 |
| `idle.yawn_after` | Seconds of no input before she is sleepy. | 60 |
| `idle.sleep_after` | Seconds of no input before she is asleep. | 300 |
| `idle.random_every` | Seconds between idle clips, a random draw between the two. | [25, 60] |
| `battery.hungry_below` | Battery percent at or below which she is hungry. | 20 |
| `battery.every` | Seconds between hungry clips. | [30, 60] |

A key that is missing, has the wrong type, or holds a number that makes no sense (a zero box, a negative delay) falls back to its own default and the rest of the file still counts.

Every raster is scaled so its height matches `static.png`'s on screen, so a clip drawn on a wider canvas does not make her jump when it plays. GIF frames keep their own delays. A delay of 10 ms or less is shown for 100 ms, the way browsers do it.

### Where packs live

The app ships two packs, `rin` and `yuna`, and `rin` is the default. Your own packs go in

```
~/Library/Application Support/MacVitals/Companion/<name>/
```

A pack there with the same name as a shipped one wins. To pick yuna, or any pack by name:

```bash
defaults write com.netsatsawat.macvitals companionName yuna
```

then switch Companion off and on in the `⋯` menu.

## What she costs

This app is a vitals monitor, so she is built not to become a load of her own. Two timers move her. One fires only when the next change is due: the next blink in a few seconds, or the next frame of a clip. The other reads the pointer ten times a second, and only while she is awake with live pupils and you have touched the machine in the last three seconds. A pupil that moved less than a tenth of a point is not redrawn. Both timers stop while she is hidden behind other windows, while the display sleeps, and while your session is switched away. Her pictures are decoded once, when she is switched on, drawn down to their on-screen size and kept only at that size, and freed when she is switched off.

## Checking a pack without a display

`MacVitals` has two developer flags for this. The first draws a strip of every gaze direction and state for a pack, with each eye blown up three times underneath so you can see where the pupils land. States the pack has no art for are labelled with what they fall through to.

```bash
swift build
.build/debug/MacVitals --render-companion strip.png
.build/debug/MacVitals --render-companion strip.png --companion-pack ~/Downloads/rin
.build/debug/MacVitals --render-companion one.png --companion-state awake --companion-gaze "-1000,106"
```

`--companion-pack` takes a pack name or a folder path. `--companion-state` is `all` (the default), a state name, or `blink`. `--companion-gaze` is a point in her box, in points from its top-left corner, that the pupils look at when you render a single state. In the `all` strip the four awake cells keep their fixed directions. `--companion-outfit <name>` draws the outfit overlay on top, so you can check a costume lines up.

The second flag puts her on screen for two seconds, writes what her own layers render, and prints the panel frame, the eye geometry and the layer frames, so the placement can be checked on a machine where screenshots are not allowed.

```bash
.build/debug/MacVitals --companion-probe probe.png
.build/debug/MacVitals --companion-probe probe.png --companion-pack ~/Downloads/rin
```

`vitals --selftest` runs the pure-logic checks for the config decoder, the fit and gaze geometry, the mood rules and the frame engine, with no display and no Xcode.

## Making a character

Both shipped characters were drawn with a local image model and cut into the pack format by hand: key out the background, measure the iris centres from the pixels, lift each iris into its sprite and heal the socket behind it to plain white, and paint the closed eyes for `blink.png` over the open ones. A two-frame GIF (eye shut for 450 ms, open for 60 ms) makes the wink. Any drawing tool that can export PNG with transparency works. The one rule that matters: the eye sprites must be cut from `static.png` at the positions in `config.json`, or the pupils will not sit in the sockets. State pictures are plain PNGs on the same canvas as `static.png`, named as in the table above.
