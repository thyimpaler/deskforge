# helpers

Three small C# programs, built on your machine with the `csc` that ships with Windows (.NET Framework 4).
No binaries are committed. `tools\install.ps1` builds only the ones your desk needs.

| Source | Built for | Network |
|---|---|---|
| dock.cs | Dock and Home: window tracking, AppBar, hotkeys, volume, brightness, wake reveal | none |
| nowplaying.cs | Now: reads the Spotify window title | none |
| market.cs | Tape and Depth addons: public exchange candles and order book | api.binance.com, data-api.binance.vision (public, keyless, 6 s timeout) |

All three run at normal or idle priority, allow a single copy, and exit when Rainmeter closes.

Build by hand: `.\helpers\build.ps1 -OutDir .\build` (fails on any compiler warning).