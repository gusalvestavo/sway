# Sway

A small macOS menu bar app that reminds you to take breaks.

Sage green · Soft geometry · A subtle sense of movement

## Features

- **Menu bar countdown** to your next break, shown as hours and minutes (`1h20m`, `40m`). A tiny pause badge appears on the logo while paused.
- **Live menu header** with a rolling countdown and buttons to add 1, 5 or 15 minutes.
- **Heads-up popover** before each break (configurable: off, 30 sec, 1/2/5 min or custom), with *Start now* and *Postpone 5 min*.
- **Full-screen break overlay** on every display, fading in and out:
  - the primary display shows the Sway logo filling up as the break runs, a random calming message, snooze buttons (+1/+3/+5 min), *Skip break* (available after 5 seconds) and *Lock screen*;
  - other displays are just blurred.
- **Liquid Glass** styling on macOS 26+, including a layered glass app icon; older systems get the standard look.
- Configurable work interval and break length, saved between launches. Sleep or a locked screen counts as a break.
- Optional *Launch at Login*.

## Requirements

- macOS 13 or later (Liquid Glass on macOS 26+)
- Xcode, for `swiftc` and `actool` (the icon compiler)

## Build and install

```sh
./build.sh
cp -R Sway.app /Applications/
open /Applications/Sway.app
```

`build.sh` compiles `Sources/*.swift` and the Icon Composer icon in `Resources/AppIcon.icon` into an ad-hoc signed `Sway.app`.

## Testing with short timers

These flags override the saved settings for one run:

```sh
./Sway.app/Contents/MacOS/Sway --interval-seconds 10 --break-seconds 20 --warn-seconds 5
```

## Project layout

| Path | What it is |
| --- | --- |
| `Sources/main.swift` | App delegate: timer, phases, menu and settings |
| `Sources/BreakOverlay.swift` | Full-screen break overlay, logo progress, screen lock |
| `Sources/BreakWarning.swift` | Popover shown shortly before a break |
| `Sources/MenuHeader.swift` | Menu header with the rolling countdown |
| `Sources/SwayMark.swift` | The Sway logo: colours, geometry, menu bar images |
| `Sources/Glass.swift` | Liquid Glass helpers with pre-macOS 26 fallbacks |
| `Resources/AppIcon.icon` | Layered app icon (open in Icon Composer) |
