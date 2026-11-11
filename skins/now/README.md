# Now

![Now playing preview](screenshot.png)

The track playing in the Spotify desktop app, under the panel: an accent tick, the song large, the artist small.
Hidden when nothing plays. Fades in once per new track.

## Look

Section `06 / NOW PLAYING` in the panel column, 330 px wide, long titles clipped. Colours and fonts from the theme.
The preview is a render with the sample track in `examples/nowplaying.txt`.

## Settings (desk.json)

| Field | Effect |
|---|---|
| `skins.now` | `false` leaves it out (and the helper is not built) |

## How it works

`nowplaying.exe` (built from `helpers/nowplaying.cs`) reads the Spotify window title (`Artist - Song`) every
1.5 s and writes `nowplaying.txt` only when it changes. It runs at idle priority, allows one copy, makes no
network calls, and exits when Rainmeter closes. Other players are not read yet; Windows media session support
is a later step (see BUILD-NOTES.md).

## CPU cost

One window enumeration every 1.5 s and one small file read every 2 s. Expected well under 1 percent of one core;
not measured yet.