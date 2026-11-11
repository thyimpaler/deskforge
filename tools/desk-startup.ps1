<#
.SYNOPSIS
  Optional sign-in check, run from the HKCU Run value that install.ps1 adds when desk.json has "startup": true.
.DESCRIPTION
  1. Waits 20 s so sign-in settles. 2. Waits up to 2 min for the internet (one keyless request).
  3. Starts Rainmeter if it is not running, and waits up to 60 s for the deskforge skins to load.
  4. Writes the boot line the panel shows (bootcheck.txt) and the values the boot reveal shows (bootseq.inc),
     then plays the boot reveal once if it is enabled. 5. Appends one line to startup-check.log.
  It never kills, disables or uninstalls anything, and sends no data anywhere.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ConfigRoot,
    [switch]$NoWait
)

$ErrorActionPreference = 'Continue'
$rm = Join-Path $env:ProgramFiles 'Rainmeter\Rainmeter.exe'
$res = Join-Path $ConfigRoot '@Resources'
$logFile = Join-Path $PSScriptRoot 'startup-check.log'
$t0 = Get-Date
$utf8 = New-Object Text.UTF8Encoding($false)

Add-Type @'
using System; using System.Runtime.InteropServices; using System.Text;
public static class DeskforgeWin {
  delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr l);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  public static int Skins(uint pid) {
    int n = 0;
    EnumWindows((h, l) => { uint p; GetWindowThreadProcessId(h, out p);
      if (p == pid) { var c = new StringBuilder(64); GetClassName(h, c, 64); if (c.ToString() == "RainmeterMeterWindow") n++; }
      return true; }, IntPtr.Zero);
    return n;
  }
}
'@

function Get-SkinCount {
    $p = Get-Process Rainmeter -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $p) { return 0 }
    return [DeskforgeWin]::Skins([uint32]$p.Id)
}

function Read-DeskVar([string]$name) {
    $f = Join-Path $res 'desk.inc'
    if (-not (Test-Path $f)) { return $null }
    $m = Select-String -Path $f -Pattern "^$name=(.*)$" | Select-Object -First 1
    if ($m) { return $m.Matches[0].Groups[1].Value }
    return $null
}

if (-not $NoWait) { Start-Sleep -Seconds 20 }

# internet: one small keyless request, up to about 2 minutes
$online = $false
for ($i = 0; $i -lt 24; $i++) {
    try {
        $r = Invoke-WebRequest 'https://api.open-meteo.com/v1/forecast?latitude=0&longitude=0&current=temperature_2m' -UseBasicParsing -TimeoutSec 4
        if ($r.StatusCode -eq 200) { $online = $true; break }
    } catch { }
    Start-Sleep -Seconds 5
}
$netSecs = [int]((Get-Date) - $t0).TotalSeconds

# Rainmeter: start it with no arguments (a bang on the command line makes a fresh Rainmeter exit)
$want = @(Get-ChildItem -Directory $ConfigRoot -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin '@Resources', 'Boot', 'Alert', 'Home' }).Count
if (-not (Get-Process Rainmeter -ErrorAction SilentlyContinue) -and (Test-Path $rm)) { Start-Process $rm }
$skins = 0
for ($w = 0; $w -lt 60; $w++) { Start-Sleep -Seconds 1; $skins = Get-SkinCount; if ($skins -ge $want) { break } }

$state = if ($online -and $skins -ge $want) { 'ok' } elseif ($skins -ge $want) { 'warn' } else { 'fail' }
$line = 'BOOT {0:HH:mm}  .  {1}  .  WIDGETS {2}/{3}' -f $t0, $(if ($online) { 'ONLINE' } else { 'OFFLINE' }), $skins, $want
try { [IO.File]::WriteAllText((Join-Path $res 'bootcheck.txt'), "$state|$line", $utf8) } catch { }

if ($skins -ge 1 -and (Test-Path $rm)) {
    & $rm '!CommandMeasure' 'mBoot' 'Update' 'deskforge\Panel'
    if ((Read-DeskVar 'WakeReveal') -eq '1' -and (Test-Path (Join-Path $ConfigRoot 'Boot\Boot.ini'))) {
        $inc = @(
            '[Variables]',
            ('BTime={0:HH:mm}' -f $t0),
            "BNet=$(if ($online) { "ONLINE  ${netSecs}S" } else { 'OFFLINE' })",
            "BWid=$skins/$want",
            "BDock=$(if (Get-Process dock -ErrorAction SilentlyContinue) { 'READY' } else { 'OFF' })"
        ) -join "`r`n"
        try { [IO.File]::WriteAllText((Join-Path $res 'bootseq.inc'), $inc, [Text.Encoding]::ASCII) } catch { }
        & $rm '!ActivateConfig' 'deskforge\Boot' 'Boot.ini'
    }
}

'{0:yyyy-MM-dd HH:mm:ss}  net={1} ({2}s)  skins={3}/{4}  total={5}s' -f $t0, $(if ($online) { 'online' } else { 'offline' }), $netSecs, $skins, $want, [int]((Get-Date) - $t0).TotalSeconds |
    Add-Content -Path $logFile -Encoding UTF8
