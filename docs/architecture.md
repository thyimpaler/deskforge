# Architecture

```
config\desk.json ──> tools\install.ps1 ──> Documents\Rainmeter\Skins\deskforge\
                        │                     Panel, Now, Dock, Home, Boot, addons
                        │                     @Resources\ theme.inc, desk.inc, home.inc, apps.txt, helpers (.exe)
                        ├─> %APPDATA%\Rainmeter\Layouts\deskforge  (loaded into Rainmeter)
                        ├─> HKCU Control Panel\Desktop  (wallpaper)
                        ├─> HKCU ...\Run "deskforge"     (only if startup is true)
                        └─> %LOCALAPPDATA%\deskforge\   backup\<time>\, install-log.json
```

- **Skins** are plain Rainmeter .ini files. They read colours and fonts from `theme.inc` and the desk settings
  from `desk.inc`, both generated, so one skin file serves every theme.
- **Helpers** are small C# programs built on the machine with the in-box `csc`. They push values to the skins
  with Rainmeter bangs over WM_COPYDATA and exit when Rainmeter closes.
- **The dock** reserves its strip as a Windows AppBar so maximized windows stop at it.
- **The startup check** (`tools\desk-startup.ps1`) waits for sign-in to settle and for the network, starts
  Rainmeter if needed, writes the boot line and plays the reveal.
- **The configurator** (`site/`) is static and offline. It validates with the same rules as install.ps1.