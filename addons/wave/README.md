# Wave

![Wave preview](screenshot.png)

A live audio spectrum along the dock edge: 48 bands mirrored into 96 bars, bass in the middle, in the accent colour. Flat when silent.

Off by default.

## Settings (desk.json)

| Field | Effect |
|---|---|
| `addons.wave` | `true` installs it |

## Data and privacy

None. It reads the sound your speakers play through the AudioLevel plugin that ships with Rainmeter.

## CPU cost

Updates every 40 ms while visible, so it costs more than the panel. Small CPU budget; not measured yet. Turn it off on weak laptops.

## Helper

none (the dock helper keeps it above the dock).

The preview is a render with made-up data, not a capture of a live desk.