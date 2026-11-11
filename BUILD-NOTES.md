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
