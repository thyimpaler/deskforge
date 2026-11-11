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
