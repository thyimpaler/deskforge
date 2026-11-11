<#
.SYNOPSIS
  Item rule and theme checks.
  Every skin, theme and addon folder has README.md and screenshot.png under 300 KB.
  Every theme.json has all colour keys as #rrggbb, both fonts and an existing wallpaper,
  and the theme.inc it produces starts a [Variables] section on its own line.
#>
[CmdletBinding()]
param()
$repo = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repo 'tools\lib\deskforge.psm1') -Force
$fails = 0
function Check([string]$name, [bool]$ok) { if ($ok) { Write-Output "PASS  $name" } else { Write-Output "FAIL  $name"; $script:fails++ } }

foreach ($group in 'skins', 'themes', 'addons') {
    foreach ($d in Get-ChildItem -Directory (Join-Path $repo $group)) {
        $shot = Join-Path $d.FullName 'screenshot.png'
        Check "$group/$($d.Name) has README.md" (Test-Path (Join-Path $d.FullName 'README.md'))
        Check "$group/$($d.Name) has screenshot.png under 300 KB" ((Test-Path $shot) -and ((Get-Item $shot).Length -lt 300KB))
    }
}
$keys = 'bg', 'surface', 'ink', 'mid', 'dim', 'rule', 'accent', 'warn', 'onAccent'
foreach ($d in Get-ChildItem -Directory (Join-Path $repo 'themes')) {
    $ok = $true
    try {
        $t = Get-Content -Raw (Join-Path $d.FullName 'theme.json') | ConvertFrom-Json
        if ($t.name -ne $d.Name) { $ok = $false }
        foreach ($k in $keys) { if ($t.colors.$k -notmatch '^#[0-9a-fA-F]{6}$') { $ok = $false } }
        if (-not $t.fonts.display -or -not $t.fonts.mono) { $ok = $false }
        if (-not (Test-Path (Join-Path $d.FullName $t.wallpaper))) { $ok = $false }
        $inc = (New-ThemeInc (Read-DeskTheme $d.Name)) -split "`r`n"
        if ($inc[1] -ne '[Variables]' -or -not ($inc -match '^Accent=\d+,\d+,\d+$')) { $ok = $false }
    } catch { $ok = $false }
    Check "themes/$($d.Name) theme.json complete and theme.inc well formed" $ok
}
# Read-DeskTheme must refuse values that could break out of theme.inc or the theme folder.
function New-TestTheme { return (Get-Content -Raw (Join-Path $repo 'themes\red-on-black\theme.json') | ConvertFrom-Json) }
function Rejects([scriptblock]$change, [string]$name = 'red-on-black') {
    $t = New-TestTheme; & $change $t
    try { Assert-DeskTheme $t $name (Join-Path $repo 'themes\red-on-black'); return $false } catch { return $true }
}
Check 'theme check accepts the shipped theme' (-not (Rejects { param($t) }))
Check 'theme check rejects a font name with a line break' (Rejects { param($t) $t.fonts.display = "Arial`r`n[Rainmeter]" })
Check 'theme check rejects a font name with a bracket' (Rejects { param($t) $t.fonts.mono = 'Consolas]' })
Check 'theme check rejects a font name with a # variable' (Rejects { param($t) $t.fonts.mono = '#Accent#' })
Check 'theme check rejects an empty font name' (Rejects { param($t) $t.fonts.display = '' })
Check 'theme check rejects .. in the wallpaper path' (Rejects { param($t) $t.wallpaper = '..\..\secret.png' })
Check 'theme check rejects a rooted wallpaper path' (Rejects { param($t) $t.wallpaper = 'C:\Windows\x.png' })
Check 'theme check rejects a wallpaper that is not an image' (Rejects { param($t) $t.wallpaper = 'wallpaper.exe' })
Check 'theme check rejects a theme name with a path' (Rejects { param($t) $t.name = '..\x' } '..\x')
Check 'theme check rejects a name that differs from the folder' (Rejects { param($t) $t.name = 'other' })
$threw = $false; try { $null = Read-DeskTheme '..\..\x' } catch { $threw = $true }
Check 'Read-DeskTheme rejects a theme name with ..' $threw
Check 'four themes ship' (@(Get-ChildItem -Directory (Join-Path $repo 'themes')).Count -eq 4)
Write-Output $(if ($fails) { "items: FAIL ($fails)" } else { 'items: PASS' })
if ($fails) { exit 1 }