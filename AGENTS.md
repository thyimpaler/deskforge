# AGENTS.md: rules and steps for coding agents

You are helping a person set up a Windows desk with deskforge. **The person makes every decision.**

## Hard rules

1. **Ask before any change to the machine.** Reading files is fine. Writing outside this repo, the registry,
   Rainmeter, the wallpaper or startup needs a clear yes from the person, every time.
2. **Dry run first.** Run `tools\install.ps1` without `-Apply`, show the person its full output, and wait
   for a clear yes before running `tools\install.ps1 -Apply`.
3. **Never run as administrator.** The scripts refuse to; do not work around that.
4. **Never disable, uninstall or kill software**, and never touch Explorer or the Windows shell.
5. **Never send the person's data anywhere.** deskforge needs no accounts or keys. Do not add any.
6. **Never write secrets** (passwords, tokens, keys) into any file.
7. Only edit `config\desk.json` and files inside this repo unless the person asks for more.
8. If something fails, stop, show the output, and offer `tools\restore.ps1`. Do not improvise fixes on the
   machine.

## Steps

1. Read [QUICKSTART.md](QUICKSTART.md).
2. Check prerequisites by reading, not changing: Windows 10, PowerShell 5.1, Rainmeter installed under
   Program Files. If Rainmeter is missing, tell the person to install it from rainmeter.net themselves.
3. Ask only the questions that change the plan, in plain words:
   - Which theme: red-on-black, paper-light, terminal-green or minimal-grey? (show `themes/*/screenshot.png`)
   - Which city for the weather, and Celsius or Fahrenheit?
   - Do they want crypto prices at all? The default is none (`"coins": []`). If yes, which one or two coins?
   - Dock at the top or bottom? Which apps on the dock and Home (up to 12)?
   - Start the desk at sign-in? (adds one value under HKCU Run)
   - Any addons? They are off by default; Tape, Depth and Wave cost more CPU.
4. Write `config\desk.json` (start from `config\desk.example.json`). Look up latitude and longitude for the
   city from your own knowledge; do not call a web service with the person's location without asking.
5. Run `tools\install.ps1`. It validates desk.json first. Fix any `ERROR` lines in desk.json and run it again.
6. Show the whole dry-run output. Say in one or two sentences what will change.
7. On a clear yes, run `tools\install.ps1 -Apply`. Show the output. Any `ERROR` line means stop.
8. Ask the person to look at the desk. If something looks wrong, check
   `%APPDATA%\Rainmeter\Rainmeter.log` (Rainmeter: right click its tray icon, About, Log) and report what it says.
9. Tell the person how to undo: `tools\restore.ps1` (everything) or `tools\restore.ps1 -Phase theme`
   (one part). See [docs/undo.md](docs/undo.md).

## Where things live

| Path | What |
|---|---|
| `config/desk.schema.json` | every allowed field of desk.json; unknown fields are rejected |
| `skins/`, `addons/` | Rainmeter skins, each with a README |
| `themes/` | colours, fonts, wallpaper |
| `helpers/` | C# sources for the dock, now-playing and market helpers (built on install) |
| `tools/` | install, restore, render previews, build site data |
| `site/` | the offline configurator |

## Tests (safe: they never touch the real desk)

```powershell
.\tests\run-all.ps1      # parse, schema, items, install and restore in a temp folder, privacy, no capture APIs
node tests\site.test.mjs # site validator against the same fixtures
node tests\site-app.test.mjs # the configurator page itself, against a stand-in DOM
```