# Troubleshooting

| Symptom | Try |
|---|---|
| `install.ps1` says Rainmeter is not installed | install it from rainmeter.net to the default folder |
| "already installed" | run `tools\restore.ps1`, then install again |
| scripts are blocked | `Set-ExecutionPolicy -Scope Process Bypass` in that window only |
| a skin shows OFFLINE | no internet or the host is down; it retries on its own schedule |
| the dock is empty | the dock helper did not start: right click the dock, Refresh skin |
| Win+Z does nothing | another app owns it; use Ctrl+Alt+Z |
| Rainmeter freezes at sign-in | turn `startup` on, so the startup check waits for sign-in to settle |
| a skin misbehaves | the Rainmeter bang `!DeactivateConfig "deskforge\<Name>"` turns it off at once |

Rainmeter writes its log to `%APPDATA%\Rainmeter\Rainmeter.log` when logging is on (tray icon, About, Log).