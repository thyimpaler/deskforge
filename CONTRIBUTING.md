# Contributing

Thanks for helping. Keep it small, private by default, and light on CPU.

## Where does my idea go?

| Idea | Where |
|---|---|
| a new colour scheme | a new folder in `themes/` (see themes/README.md) |
| a new widget | a new folder in `addons/`, off by default |
| a change to the panel, dock, home, now or boot | `skins/<name>/` |
| a new desk.json field | `config/desk.schema.json`, `tools/lib/deskforge.psm1`, `site/`, fixtures |
| a helper change | `helpers/*.cs` (must build with the in-box csc, no warnings) |
| a bug | an issue with the Rainmeter log lines and your Windows build |

## Pull request checklist

- [ ] `.\tests\run-all.ps1` passes and `node tests\site.test.mjs` and `node tests\site-app.test.mjs` pass.
- [ ] Every new skin, theme or addon folder has `README.md` (look, settings, CPU cost) and `screenshot.png`
      under 300 KB with metadata stripped (`tools\strip-metadata.ps1 -Path .`).
- [ ] The privacy scan is clean: no names, emails, user paths, coordinates of real homes, keys or tokens.
- [ ] No new network host without a README line saying what is sent; no keys; every request has a timeout or
      a visible error state.
- [ ] Nothing changes the machine outside `tools\install.ps1`, and every change it makes is in install-log.json
      so `tools\restore.ps1` can undo it.
- [ ] No camera, microphone recording, keylogging or keyboard hooks.

By contributing you agree your work is released under the MIT licence of this repo.