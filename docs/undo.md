# Undo

```powershell
.\tools\restore.ps1                  # undo everything
.\tools\restore.ps1 -DryRun          # see what it would do
.\tools\restore.ps1 -Phase wallpaper # undo one part: skins, theme, wallpaper, startup or helpers
```

Restore reads `%LOCALAPPDATA%\deskforge\install-log.json` and the snapshot it points to. It:

- puts back your previous Rainmeter layout, wallpaper values and startup value,
- removes only the files and folders the install created, and only folders that are empty,
- keeps any listed file you edited after the install, and says so,
- never touches Explorer and never uninstalls anything (Rainmeter stays installed).

The snapshot folder `%LOCALAPPDATA%\deskforge\backup\` is kept. Delete it yourself when you no longer need it.

If restore cannot run, the snapshot has everything by hand: `Rainmeter.ini` (copy it back to
`%APPDATA%\Rainmeter\`) and `snapshot.json` (the old wallpaper and startup values).