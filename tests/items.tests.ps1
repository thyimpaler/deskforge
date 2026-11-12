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

# ------------------------------------------------------------------ coins are optional
# desk.inc for zero, one and two coins, and Panel.ini resolved against it: a hidden coin must hide its meters
# and disable every CoinGecko measure, and the manual refresh must not command a hidden coin's measure.
function Get-IncVars([string]$inc) {
    $h = @{}; foreach ($l in ($inc -split "`r`n")) { if ($l -match '^([A-Za-z0-9]+)=(.*)$') { $h[$Matches[1]] = $Matches[2] } }; return $h
}
function Read-Ini([string]$path) {
    $secs = [ordered]@{}; $cur = $null
    foreach ($l in [IO.File]::ReadAllLines($path)) {
        if ($l -match '^\[(.+)\]\s*$') { $cur = $Matches[1]; $secs[$cur] = @{} }
        elseif ($cur -and $l -match '^([A-Za-z0-9]+)=(.*)$') { $secs[$cur][$Matches[1]] = $Matches[2] }
    }
    return $secs
}
function Resolve-Var([string]$v, $vars) { return ([regex]::Replace($v, '#([A-Za-z0-9]+)#', { param($m) if ($vars.ContainsKey($m.Groups[1].Value)) { $vars[$m.Groups[1].Value] } else { $m.Value } })) }
$base = (Get-Content -Raw (Join-Path $repo 'tests\fixtures\valid-no-coins.json') | ConvertFrom-Json).config
$panel = Read-Ini (Join-Path $repo 'skins\panel\Panel.ini')
foreach ($case in @(@{ n = 0; coins = @() }, @{ n = 1; coins = @('solana') }, @{ n = 2; coins = @('bitcoin', 'ethereum') })) {
    $cfg = $base | ConvertTo-Json -Depth 6 | ConvertFrom-Json
    $cfg.coins = $case.coins
    $inc = $null; try { $inc = New-DeskInc $cfg } catch { }
    Check "desk.inc builds with $($case.n) coin(s)" ($null -ne $inc)
    if ($null -eq $inc) { continue }
    $v = Get-IncVars $inc
    Check "desk.inc with $($case.n) coin(s) sets Coin1Hidden=$([int]($case.n -lt 1)) and Coin2Hidden=$([int]($case.n -lt 2))" (
        ($v['Coin1Hidden'] -eq "$([int]($case.n -lt 1))") -and ($v['Coin2Hidden'] -eq "$([int]($case.n -lt 2))"))
    if ($case.n -eq 0) { Check 'desk.inc with no coins leaves Coin1 and Coin2 empty' (($v['Coin1'] -eq '') -and ($v['Coin2'] -eq '')) }
    $badMeasure = @(); $badMeter = @()
    foreach ($k in $panel.Keys) {
        $s = $panel[$k]
        foreach ($i in 1, 2) {
            $hiddenNow = $v["Coin${i}Hidden"] -eq '1'
            $isWeb = $s.ContainsKey('URL') -and ($s['URL'] -match "coingecko\.com.*#Coin$i#" -or $s['URL'] -eq "[mCoin${i}Web]")
            if ($isWeb) {
                $dis = if ($s.ContainsKey('Disabled')) { Resolve-Var $s['Disabled'] $v } else { '0' }
                if ($s['Disabled'] -ne "#Coin${i}Hidden#" -or ($hiddenNow -and $dis -ne '1') -or (-not $hiddenNow -and $dis -ne '0')) { $badMeasure += $k }
            }
            $usesCoin = ($s.ContainsKey('Meter')) -and (($s['MeasureName'] -like "mCoin$i*") -or ($s['Text'] -like "*#Coin$i*"))
            if ($usesCoin) {
                $hid = if ($s.ContainsKey('Hidden')) { Resolve-Var $s['Hidden'] $v } else { '0' }
                if (($hiddenNow -and $hid -ne '1') -or (-not $hiddenNow -and $hid -ne '0')) { $badMeter += $k }
            }
        }
    }
    Check "Panel.ini with $($case.n) coin(s): CoinGecko measures disabled exactly for hidden coins" ($badMeasure.Count -eq 0)
    Check "Panel.ini with $($case.n) coin(s): coin meters hidden exactly for hidden coins" ($badMeter.Count -eq 0)
    $tl = Resolve-Var $panel['TLabel']['Hidden'] $v
    Check "Panel.ini with $($case.n) coin(s): the PRICES label is $(if ($case.n) { 'shown' } else { 'hidden' })" ($tl -eq $(if ($case.n) { '0' } else { '1' }))
}
$ctxAll = (@($panel['Rainmeter'].Keys | Where-Object { $_ -like 'ContextAction*' }) | ForEach-Object { $panel['Rainmeter'][$_] }) -join ' '
Check 'Panel.ini context menu never commands a coin measure directly' ($ctxAll -notmatch 'mCoin\dWeb')
$pr = if ($panel.Contains('mPxRefresh')) { $panel['mPxRefresh'] } else { @{} }
Check 'Panel.ini manual price refresh is gated on Coin1Hidden and Coin2Hidden' ($pr.Count -gt 0 -and
    ($pr['IfCondition'] -match '#Coin1Hidden# = 0') -and ($pr['IfTrueAction'] -match 'mCoin1Web') -and
    ($pr['IfCondition2'] -match '#Coin2Hidden# = 0') -and ($pr['IfTrueAction2'] -match 'mCoin2Web') -and ($pr['UpdateDivider'] -eq '-1'))
Write-Output $(if ($fails) { "items: FAIL ($fails)" } else { 'items: PASS' })
if ($fails) { exit 1 }