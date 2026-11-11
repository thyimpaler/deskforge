# themes

Four complete themes ship. Each folder holds `theme.json` (colours, fonts, wallpaper file), `README.md`,
`screenshot.png` and `wallpaper.png`.

| Theme | Look |
|---|---|
| [red-on-black](red-on-black/) | the default: near black, off-white, deep red accent |
| [paper-light](paper-light/) | warm paper, dark ink, blue accent |
| [terminal-green](terminal-green/) | phosphor green, all monospace |
| [minimal-grey](minimal-grey/) | graphite, no colour accent |

## Make your own

1. Copy a theme folder and rename it (lowercase letters, digits and dashes).
2. Edit `theme.json`: every colour is `#rrggbb`. `onAccent` is the text colour used on top of `accent`.
3. Run `tools\render-previews.ps1` to draw `wallpaper.png` and `screenshot.png`, then `tools\strip-metadata.ps1 -Path .`.
4. Run `tests\run-all.ps1`. It fails if the README or the screenshot is missing, or the screenshot is 300 KB or more.