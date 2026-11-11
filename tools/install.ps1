<#
.SYNOPSIS
  Installs a deskforge desk from config\desk.json. Dry run by default: it prints every change and writes nothing.
.DESCRIPTION
  -Apply makes the changes, in this order:
    1. Snapshot to %LOCALAPPDATA%\deskforge\backup\<timestamp>\ (Rainmeter.ini, the wallpaper values,
       the startup value, and any file that would be overwritten).
    2. Copy skins and addons, write the theme and desk include files, compile helpers with csc,
       write and load the Rainmeter layout, set the wallpaper, add a startup entry only if desk.json asks.
    3. Write install-log.json listing every file, folder and registry value changed.
  Undo with tools\restore.ps1. Nothing here needs admin rights, and it refuses to run elevated.
  Only HKCU is written: the wallpaper values under Control Panel\Desktop and one value named deskforge
  under ...\CurrentVersion\Run (only when startup is true). Explorer is never touched.
  -TestRoot <folder> redirects every path into that folder and keeps registry values in a JSON file there,
  so tests never touch the real desk, Rainmeter or registry.
.EXAMPLE
  .\tools\install.ps1              # dry run
  .\tools\install.ps1 -Apply       # make the changes
#>
[CmdletBinding()]
param(
    [string]$Config,
    [switch]$Apply,
    [string]$TestRoot,
    [switch]$SkipHelpers
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib\deskforge.psm1') -Force
$repo = Get-DeskRepo
if (-not $Config) { $Config = Join-Path $repo 'config\desk.json' }

function Say([string]$level, [string]$text) { Write-Output ('{0,-5} {1}' -f $level, $text) }

try {
    if (Test-IsAdmin) { throw 'refusing to run as administrator. Open a normal PowerShell window and run it again.' }
    $ctx = New-DeskContext -TestRoot $TestRoot
    $cfg = Read-DeskConfig $Config
    $errs = Test-DeskConfig -Config $cfg
    if ($errs.Count -gt 0) { foreach ($e in $errs) { Say 'ERROR' "desk.json: $e" }; exit 1 }
    $theme = Read-DeskTheme $cfg.theme
    if (-not $ctx.Test -and -not $ctx.RainmeterExe) { throw 'Rainmeter is not installed (expected it under Program Files). Install it from rainmeter.net, then run this again.' }
    if (Test-Path $ctx.LogPath) { throw "deskforge is already installed (found $($ctx.LogPath)). Run tools\restore.ps1 first, then install again." }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = Join-Path $ctx.StateRoot "backup\$stamp"
    $items = Get-DeskItems $cfg | Where-Object { $_.on }

    # ------------------------------------------------------------ build the plan
    $plan = New-Object System.Collections.Generic.List[object]
    function Add-File([string]$phase, [string]$target, [string]$from, [string]$text, [switch]$Rm, [switch]$Volatile) {
        $plan.Add(@{ phase = $phase; kind = 'file'; path = $target; from = $from; text = $text; rm = [bool]$Rm; volatile = [bool]$Volatile })
    }
    function Add-Reg([string]$phase, [string]$path, [string]$name, [string]$value) {
        $plan.Add(@{ phase = $phase; kind = 'registry'; path = $path; name = $name; value = $value })
    }

    foreach ($it in $items) {
        $dest = Join-Path $ctx.ConfigRoot $it.cfg
        Get-ChildItem -File (Join-Path $repo $it.src) | Where-Object { $_.Name -ne 'README.md' -and $_.Name -ne 'screenshot.png' } |
            ForEach-Object { Add-File 'skins' (Join-Path $dest $_.Name) $_.FullName $null }
    }
    Add-File 'skins' (Join-Path $ctx.Resources 'desk.inc') $null (New-DeskInc $cfg) -Rm
    Add-File 'skins' (Join-Path $ctx.Resources 'apps.txt') $null (New-AppsTxt $cfg)
    if ($cfg.skins.home) { Add-File 'skins' (Join-Path $ctx.Resources 'home.inc') $null (New-HomeInc $cfg) -Rm }
    # run-time files the skins and helpers rewrite; created up front so Rainmeter never logs a missing file,
    # and marked volatile so restore removes them even though their contents changed
    Add-File 'skins' (Join-Path $ctx.Resources 'bootcheck.txt') $null 'ok|' -Volatile
    Add-File 'skins' (Join-Path $ctx.Resources 'bootseq.inc') $null "[Variables]`r`n" -Volatile
    Add-File 'skins' (Join-Path $ctx.Resources 'dockstate.txt') $null '' -Volatile
    Add-File 'skins' (Join-Path $ctx.Resources 'nowplaying.txt') $null "`n" -Volatile
    Add-File 'skins' (Join-Path $ctx.Resources 'alert.inc') $null "[Variables]`r`n" -Volatile
    Add-File 'theme' (Join-Path $ctx.Resources 'theme.inc') $null (New-ThemeInc $theme) -Rm
    $layoutFile = Join-Path $ctx.RmSettings 'Layouts\deskforge\Rainmeter.ini'
    Add-File 'skins' $layoutFile $null (New-LayoutIni $cfg) -Rm

    $helpers = @()
    if ($cfg.skins.dock -or $cfg.skins.home) { $helpers += 'dock' }
    if ($cfg.skins.now) { $helpers += 'nowplaying' }
    if ($cfg.addons.tape -or $cfg.addons.depth) { $helpers += 'market' }
    if (-not $SkipHelpers) { foreach ($h in $helpers) { $plan.Add(@{ phase = 'helpers'; kind = 'helper'; path = (Join-Path $ctx.Resources "$h.exe"); name = $h }) } }

    # the layout loads after helpers exist, because the skins start their helpers when they load
    $plan.Add(@{ phase = 'skins'; kind = 'rmlayout'; path = (Join-Path $ctx.RmSettings 'Rainmeter.ini'); layout = $layoutFile })

    $wpSrc = Join-Path $repo "themes\$($cfg.theme)\$($theme.wallpaper)"
    $wpDest = Join-Path $ctx.StateRoot "wallpaper\$($cfg.theme)-wallpaper.png"
    Add-File 'wallpaper' $wpDest $wpSrc $null
    $desk = 'HKCU:\Control Panel\Desktop'
    Add-Reg 'wallpaper' $desk 'WallpaperStyle' '10'
    Add-Reg 'wallpaper' $desk 'TileWallpaper' '0'
    Add-Reg 'wallpaper' $desk 'WallPaper' $wpDest

    if ($cfg.startup) {
        $startScript = Join-Path $ctx.StateRoot 'desk-startup.ps1'
        Add-File 'startup' $startScript (Join-Path $repo 'tools\desk-startup.ps1') $null
        $cmd = 'powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -ConfigRoot "{1}"' -f $startScript, $ctx.ConfigRoot
        Add-Reg 'startup' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' 'deskforge' $cmd
    }

    # ------------------------------------------------------------ dry run
    $mode = if ($ctx.Test) { "test root $($ctx.TestRoot)" } else { 'this PC' }
    Say 'INFO' "deskforge install, $(if ($Apply) { 'APPLY' } else { 'DRY RUN' }), target: $mode"
    Say 'INFO' "theme $($cfg.theme), skins: $((@($items | Where-Object { $_.kind -eq 'skins' }) | ForEach-Object { $_.key }) -join ', '), addons: $(((@($items | Where-Object { $_.kind -eq 'addons' }) | ForEach-Object { $_.key }) -join ', '))"
    Say 'PLAN' "snapshot  $backup"
    foreach ($a in $plan) {
        switch ($a.kind) {
            'file'     { Say 'PLAN' ("{0,-9} {1} file  {2}" -f $a.phase, $(if (Test-Path -LiteralPath $a.path) { 'replace' } else { 'create ' }), $a.path) }
            'registry' { $b = Get-DeskReg $ctx $a.path $a.name; Say 'PLAN' ("{0,-9} set registry  {1}\{2} = {3}   (now: {4})" -f $a.phase, $a.path, $a.name, $a.value, $(if ($b.exists) { $b.value } else { 'not set' })) }
            'rmlayout' { Say 'PLAN' ("{0,-9} load layout  deskforge into Rainmeter ({1} is backed up first)" -f $a.phase, $a.path) }
            'helper'   { Say 'PLAN' ("{0,-9} compile  helpers\{1}.cs -> {2}" -f $a.phase, $a.name, $a.path) }
        }
    }
    Say 'PLAN' "log       $($ctx.LogPath)"
    if (-not $Apply) {
        Say 'INFO' "dry run: $($plan.Count) change(s) listed, nothing written. Run again with -Apply to make them."
        exit 0
    }

    # ------------------------------------------------------------ snapshot first
    New-Item -ItemType Directory -Force $backup | Out-Null
    $log = [ordered]@{ tool = 'deskforge'; schemaVersion = 1; installed = (Get-Date -Format 's'); test = $ctx.Test; theme = $cfg.theme; backup = $backup; entries = @() }
    $snap = @{ registry = @(); files = @() }
    $rmIni = Join-Path $ctx.RmSettings 'Rainmeter.ini'
    if (Test-Path -LiteralPath $rmIni) { Copy-Item -LiteralPath $rmIni (Join-Path $backup 'Rainmeter.ini') }
    foreach ($a in $plan | Where-Object { $_.kind -eq 'registry' }) { $b = Get-DeskReg $ctx $a.path $a.name; $snap.registry += @{ path = $a.path; name = $a.name; exists = $b.exists; value = $b.value } }
    $n = 0
    foreach ($a in $plan | Where-Object { $_.kind -eq 'file' -or $_.kind -eq 'helper' }) {
        if (Test-Path -LiteralPath $a.path) { $n++; $bk = Join-Path $backup "files\$n.bak"; New-Item -ItemType Directory -Force (Split-Path $bk) | Out-Null; Copy-Item -LiteralPath $a.path $bk; $a.backupCopy = $bk; $snap.files += @{ path = $a.path; backup = $bk } }
    }
    Write-DeskText (Join-Path $backup 'snapshot.json') ($snap | ConvertTo-Json -Depth 5)
    Say 'DONE' "snapshot  $backup"

    function Save-Log { Write-DeskText $ctx.LogPath ($log | ConvertTo-Json -Depth 6) }
    function Add-Entry($e) { $log.entries += $e; Save-Log }
    function Confirm-Folder([string]$dir, [string]$phase) {
        $missing = @(); $d = $dir
        while ($d -and -not (Test-Path -LiteralPath $d)) { $missing += $d; $d = Split-Path -Parent $d }
        [array]::Reverse($missing)
        foreach ($m in $missing) { New-Item -ItemType Directory $m | Out-Null; Add-Entry ([ordered]@{ phase = $phase; kind = 'folder'; path = $m }) }
    }
    Confirm-Folder $ctx.StateRoot 'state'
    Save-Log

    # ------------------------------------------------------------ apply
    foreach ($a in $plan) {
        switch ($a.kind) {
            'file' {
                Confirm-Folder (Split-Path -Parent $a.path) $a.phase
                if ($a.from) { Copy-Item -LiteralPath $a.from $a.path -Force } else { Write-DeskText $a.path $a.text -Rainmeter:$a.rm }
                $e = [ordered]@{ phase = $a.phase; kind = 'file'; path = $a.path; sha256 = (Get-FileSha256 $a.path); backup = $a.backupCopy; volatile = $a.volatile }
                Add-Entry $e; Say 'DONE' ("{0,-9} file  {1}" -f $a.phase, $a.path)
            }
            'helper' {
                Confirm-Folder (Split-Path -Parent $a.path) $a.phase
                $out = & (Join-Path $repo 'helpers\build.ps1') -Only $a.name -OutDir (Split-Path -Parent $a.path)
                if ($LASTEXITCODE -ne 0) { throw "helper build failed: $($a.name)`n$($out -join "`n")" }
                Add-Entry ([ordered]@{ phase = 'helpers'; kind = 'file'; path = $a.path; sha256 = (Get-FileSha256 $a.path); backup = $a.backupCopy })
                Say 'DONE' ("helpers   compiled  {0}" -f $a.path)
            }
            'registry' {
                $b = Get-DeskReg $ctx $a.path $a.name
                Set-DeskReg $ctx $a.path $a.name $a.value
                Add-Entry ([ordered]@{ phase = $a.phase; kind = 'registry'; path = $a.path; name = $a.name; before = [ordered]@{ exists = $b.exists; value = $b.value }; after = $a.value })
                Say 'DONE' ("{0,-9} registry  {1}\{2}" -f $a.phase, $a.path, $a.name)
            }
            'rmlayout' {
                $had = Test-Path -LiteralPath $a.path
                Add-Entry ([ordered]@{ phase = 'skins'; kind = 'rmini'; path = $a.path; existed = $had; backup = $(if ($had) { Join-Path $backup 'Rainmeter.ini' } else { $null }) })
                if (-not $ctx.Test -and (Test-RainmeterRunning)) {
                    & $ctx.RainmeterExe '!RefreshApp'
                    Start-Sleep -Seconds 2
                    & $ctx.RainmeterExe '!LoadLayout' 'deskforge'
                    Say 'DONE' 'skins     layout deskforge loaded into the running Rainmeter'
                }
                else {
                    Confirm-Folder (Split-Path -Parent $a.path) 'skins'
                    Copy-Item -LiteralPath $a.layout $a.path -Force
                    Say 'DONE' "skins     Rainmeter.ini set to the deskforge layout (start Rainmeter to see it)"
                }
            }
        }
    }
    if (-not $ctx.Test) {
        $ok = Set-DeskWallpaper $wpDest
        if ($ok) { Say 'DONE' 'wallpaper applied' } else { Say 'WARN' 'wallpaper value saved, but Windows did not apply it yet; it shows after the next sign-in' }
    }
    Save-Log
    Say 'INFO' "installed. Log: $($ctx.LogPath). Undo any time with tools\restore.ps1"
    exit 0
}
catch {
    Say 'ERROR' $_.Exception.Message
    if ($Apply -and $ctx -and (Test-Path $ctx.LogPath)) { Say 'INFO' 'partial install recorded in install-log.json; tools\restore.ps1 undoes it' }
    exit 1
}
