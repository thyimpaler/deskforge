# Quickstart: the 15-minute path

1. **Install Rainmeter** from rainmeter.net (free). Start it once, then leave it running.
2. **Get deskforge**: clone this repo or download the zip and unpack it, for example to `Documents\deskforge`.
3. **Make desk.json**, either way:
   - open `site\index.html` in your browser, choose, and press Download desk.json; save it as `config\desk.json`, or
   - `Copy-Item config\desk.example.json config\desk.json` and edit it.
4. **Open PowerShell** (not as administrator) in the deskforge folder. If scripts are blocked, run
   `Set-ExecutionPolicy -Scope Process Bypass` for this window only.
5. **Dry run**: `.\tools\install.ps1`. Read the list. Nothing has changed yet.
6. **Install**: `.\tools\install.ps1 -Apply`. It saves a snapshot first, then installs.
7. **Look**: the panel sits on the right, the dock at the bottom. Press Win+Z for Home.
8. **Undo** any time: `.\tools\restore.ps1`.

To change something later: `.\tools\restore.ps1`, edit `config\desk.json`, install again.
The Windows taskbar is left alone. If you want only the deskforge dock, set the taskbar to auto-hide yourself.