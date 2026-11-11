# Build notes (Stage 1)

Choices made where the plan was open or unclear. Each one takes the simpler option.

## M1 intake

- The allowlist lives in `tools/intake-allowlist.json` (source to repo paths). `tools/build-manifest.json`
  is the install manifest (repo files plus SHA-256), written later by `tools/verify.ps1 -Write`.
- Source paths are passed at run time with `-SourceRoot`, so no personal folder name is stored in the repo.
- Copied: 5 core skins, 5 addon skins, 3 helper sources, 1 image (the mood gradient). Nothing else.
- Not copied: the countdown overlay skin and everything camera related, wallpapers, avatars, photos,
  run-time state files, compiled helpers, logs, backups, restore scripts from earlier desk work.
- Scrub after copy: config root renamed to `deskforge`, author lines set to `deskforge contributors`,
  the city and coordinates set to a neutral default (London), personal app and project rows removed from
  Home, the on-screen countdown button removed from Dock, personal app list, support-desk and chat
  workspace entries removed from the dock helper.
- The owner-only banned-terms list is `tests/privacy/banned-terms.local.txt` (gitignored). It exists on the
  build machine only. Without it the scan still runs the generic patterns and says the list is missing.
- Commit author is set in local git config only. The plan named only the email; the author name is the
  GitHub login that the noreply address already contains, so it adds nothing new. The privacy scan reads
  commit messages; author and committer fields are checked by `tests/author-check.ps1` instead, because
  the noreply address necessarily contains the login.

## M2 panel, install and restore

- Windows Sandbox is not available on the build machine (WindowsSandbox.exe is absent; enabling it is an
  owner decision that changes the machine). So the Sandbox proof is NOT done. Instead install and restore
  run against a throwaway `-TestRoot` folder in %TEMP%: every path is redirected there and registry values
  live in a JSON file there. The owner's Rainmeter, desktop and registry were not touched, and no real-mode
  run (not even a dry run) was made on the build machine.
- `tests/install-restore.tests.ps1` seeds a fake Rainmeter.ini, wallpaper values and an unrelated skin, then
  checks: the dry run writes nothing; apply writes the files, values and log; a second install is refused;
  `-Phase wallpaper` restores only those values; a full restore leaves every file outside State\ and every
  registry value identical to the seed. It was checked to fail when restore skips putting Rainmeter.ini back.
- The Panel is one `Panel.ini` instead of the plan's proposed `Weather.inc`, `Crypto.inc` etc. Splitting it
  bought nothing, and the plan marked those names as proposals.
- Theme and desk values reach the skins through two generated include files in `@Resources`
  (`theme.inc`, `desk.inc`), written as UTF-16 so non-ASCII city names show correctly.
- The layout is written to `Rainmeter\Layouts\deskforge` and loaded with `!LoadLayout` when Rainmeter runs.
  Restore loads the backed-up Rainmeter.ini through a temporary layout the same way.
- `%LOCALAPPDATA%\deskforge` (backups and the moved install log) is kept after a full restore on purpose.
- Restore acts directly (it is the undo); `-DryRun` previews it.
- Pester 3.4 is the only Pester on the build machine and CI would use Pester 5, whose syntax differs. The
  tests are plain PowerShell scripts that print PASS or FAIL and exit 1 on failure, so they run the same
  everywhere. PSScriptAnalyzer and gitleaks are not installed locally.
- Screenshots are renders from `tools/render-previews.ps1` (System.Drawing, sample data), not captures.

## M3 dock, home, now, boot and helpers

- No camera code: the countdown overlay skin and its camera script were never copied, and
  `tests/capture-check.ps1` fails on any capture API name in code (checked to fail on a probe file).
- The dock helper reads apps from `@Resources\apps.txt` (from `homeApps`), colours from `theme.inc`, and the
  dock edge and switches from `desk.inc`. Personal app lists, watched support-desk and chat tabs, and browser
  profile arguments are gone. Any pinned app whose title starts with an unread count like `(3)` shows it, and
  raises the Alert band only when the alert addon is on.
- Removed the low-level keyboard hook that turned a lone Win key into Home. Home now opens with Win+Z only
  (Ctrl+Alt+Z fallback). A global keyboard hook is more than a desk kit should ask for.
- Home's search opens Windows search (Win+S) instead of a third-party launcher.
- Wake reveal: the dock helper listens for unlock and resume (SystemEvents) and plays the Boot skin when
  `wakeReveal.enabled` is true. The startup check plays it after sign-in.
- Now playing still reads the Spotify window title, as the source did. The plan's "Windows media session" needs
  WinRT projections that the in-box csc cannot reference cleanly; left for later.
- Skins use the theme variables and screen-size variables instead of fixed 1920x1080 pixel positions.
  Rainmeter's own scaling at 125 and 150 percent is not verified (owner laptop, Stage 4).
- Install pre-creates the run-time files (bootcheck.txt, bootseq.inc, dockstate.txt, nowplaying.txt,
  alert.inc) so Rainmeter never logs a missing file, and restore removes them even though they changed.
- csc builds all three helpers with /warnaserror+: zero warnings. The skins were NOT loaded in Rainmeter:
  that would touch the owner's running Rainmeter. The skin load test stays an owner step (plan section 8).

## M4 themes and addons

- Four complete themes: red-on-black (default), paper-light, terminal-green, minimal-grey. Each has
  theme.json, README.md, screenshot.png and wallpaper.png. Wallpapers are drawn by the render tool, so no
  personal wallpaper or photo ships.
- Added an `onAccent` colour to every theme (text drawn on the accent, used by the Alert band), because white
  text on the light accents of terminal-green and minimal-grey would be unreadable.
- Bug found and fixed: the generated theme.inc put `[Variables]` inside its comment line (a PowerShell
  operator-precedence slip from M2), so Rainmeter would not have seen the theme. `tests/items.tests.ps1` now
  checks the header and was confirmed to fail on the M2 code.
- Addons use the theme colours; the market helper reads theme.inc for its candle and ladder colours.
  Wave's bar width now follows the screen width. Mood loads its gradient from its own folder.
- Tape and Depth stay in the kit, off by default, until the owner decides (open decision 3).
- The wake reveal line is the placeholder `WELCOME BACK` until the owner picks the wording (open decision 1).

## M5 configurator and schema tests

- `site/` is static: index.html, style.css, app.js, schema.js and a generated data.js (schema, example,
  themes and sample data copied verbatim by `tools/build-site-data.ps1`; `-Check` fails if it is stale).
  A Content-Security-Policy blocks every connection; no fonts, scripts or images load from anywhere else.
- The site validator mirrors the PowerShell one. Both run the same 18 fixtures in `tests/fixtures`
  (`tests/schema.tests.ps1`, `node tests/site.test.mjs`): all pass.
- Checked in a browser over a local 127.0.0.1 server (stopped afterwards): at 375 px
  scrollWidth equals clientWidth (no horizontal scroll), no control under 44 px tall, no console errors,
  only same-origin requests. An invalid refresh value disables Download and names the field; Import accepts a
  valid file and refuses one with an unknown field. Screenshot at 1440 looked right. The headless 390 px
  screenshot was clipped by headless Chrome's minimum window width, so 390 px was judged by the in-page check
  at 375 px instead.
- Download itself (the browser save dialog) was not exercised end to end; the Blob path ran without errors.

## M6 docs, agent rules and CI

- README opens with the "Give this to your Claude" block. It names the repo and AGENTS.md instead of a raw
  GitHub URL, because the URL would carry the owner's handle and nothing is pushed yet. Add the URL at push time.
- AGENTS.md holds the hard rules (ask before any machine change, dry run first and shown, never admin, never
  disable or uninstall, no data sent, no secrets) and the step list. CLAUDE.md is one line pointing at it.
- LICENSE is MIT, copyright "deskforge contributors" (no personal name). SECURITY.md points to GitHub private
  vulnerability reporting, no email address.
- `.github/workflows/ci.yml` is written, not pushed: PSScriptAnalyzer (errors fail), `tests/run-all.ps1 -Ci`,
  the site tests, the site data check, and gitleaks. It has never run.
- `tools/verify.ps1` writes and checks `tools/build-manifest.json` (SHA-256 of every shipped skin, addon, theme,
  helper and tool file).
- `tests/run-all.ps1` runs the local suite. The capture-API check was renamed `capture-check.ps1` so its own
  name does not trip it.

## Not done in Stage 1 (needs the owner or later stages)

- Windows Sandbox install and restore (Sandbox not enabled; enabling it changes the machine).
- Rainmeter skin load test and Rainmeter.log check (would touch the owner's running Rainmeter).
- PSScriptAnalyzer and gitleaks (not installed locally; both are in the CI file).
- CPU, scaling at 125 and 150 percent, and the demo GIF (Stage 4 on the owner's laptop).
- Owner review of every image by eye. All images are generated renders except `addons/mood/mood.png`
  (a plain gradient from the source).
