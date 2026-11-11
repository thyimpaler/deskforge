<#
.SYNOPSIS
  Draws the theme wallpapers and every README screenshot from the theme files and the offline sample data.
.DESCRIPTION
  These are preview renders made with System.Drawing, not captures of a live desk. They use the same
  colours, fonts and layout numbers as the skins, and the made-up values in examples/. No network, no
  Rainmeter. Run it after changing a theme or a skin layout, then run tools\strip-metadata.ps1.
.EXAMPLE
  .\tools\render-previews.ps1
#>
[CmdletBinding()]
param([string[]]$Only)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$repo = Split-Path -Parent $PSScriptRoot
$wx = Get-Content -Raw (Join-Path $repo 'examples\weather.json') | ConvertFrom-Json
$px = Get-Content -Raw (Join-Path $repo 'examples\prices.json') | ConvertFrom-Json
$np = (Get-Content -Raw (Join-Path $repo 'examples\nowplaying.txt')) -split "`n"
$inv = [Globalization.CultureInfo]::InvariantCulture

function C([string]$hex, [int]$a = 255) { return [Drawing.Color]::FromArgb($a, [Convert]::ToInt32($hex.Substring(1, 2), 16), [Convert]::ToInt32($hex.Substring(3, 2), 16), [Convert]::ToInt32($hex.Substring(5, 2), 16)) }
function Get-Theme([string]$n) { return Get-Content -Raw (Join-Path $repo "themes\$n\theme.json") | ConvertFrom-Json }

function New-Canvas([int]$w, [int]$h) {
    $b = New-Object Drawing.Bitmap($w, $h, [Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $g = [Drawing.Graphics]::FromImage($b)
    $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'; $g.InterpolationMode = 'HighQualityBicubic'
    return @{ b = $b; g = $g }
}
function Save-Canvas($cv, [string]$path, [int]$w = 0, [int]$h = 0) {
    New-Item -ItemType Directory -Force (Split-Path $path) | Out-Null
    if ($w -gt 0) {
        $s = New-Canvas $w $h; $s.g.DrawImage($cv.b, 0, 0, $w, $h); $s.b.Save($path, [Drawing.Imaging.ImageFormat]::Png); $s.g.Dispose(); $s.b.Dispose()
    } else { $cv.b.Save($path, [Drawing.Imaging.ImageFormat]::Png) }
    Write-Output "rendered  $($path.Substring($repo.Length + 1))"
}
function T($g, [string]$s, [string]$face, [double]$pt, $col, [double]$x, [double]$y, [switch]$Bold, [switch]$Right) {
    $style = if ($Bold) { [Drawing.FontStyle]::Bold } else { [Drawing.FontStyle]::Regular }
    $f = New-Object Drawing.Font($face, [single]($pt * 1.333), $style, [Drawing.GraphicsUnit]::Pixel)
    $br = New-Object Drawing.SolidBrush($col)
    $fmt = New-Object Drawing.StringFormat
    if ($Right) { $fmt.Alignment = 'Far' }
    $g.DrawString($s, $f, $br, [single]$x, [single]$y, $fmt)
    $sz = $g.MeasureString($s, $f)
    $f.Dispose(); $br.Dispose()
    return $sz
}
function Box($g, $col, [double]$x, [double]$y, [double]$w, [double]$h) { $br = New-Object Drawing.SolidBrush($col); $g.FillRectangle($br, [single]$x, [single]$y, [single]$w, [single]$h); $br.Dispose() }

# ------------------------------------------------------------------ pieces

function Draw-Wallpaper($g, $t, [int]$W, [int]$H) {
    $c = $t.colors
    Box $g (C $c.bg) 0 0 $W $H
    for ($y = 120; $y -lt $H; $y += 120) { Box $g (C $c.rule 110) 0 $y $W 1 }
    $stake = [int]($W * 0.618)
    Box $g (C $c.accent) $stake 0 3 $H
    $null = T $g ("DESKFORGE / " + $t.name.ToUpper()) $t.fonts.mono 9 (C $c.dim) 48 ($H - 44)
}

function Draw-Panel($g, $t, [double]$x0, [double]$y0) {
    $c = $t.colors; $W = 360; $d = $t.fonts.display; $m = $t.fonts.mono
    $y = $y0
    $null = T $g 'BOOT 08:41  .  ONLINE  .  WIDGETS 5/5' $m 10 (C $c.dim) $x0 $y; $y += 20
    $null = T $g '09:41' $d 66 (C $c.ink) ($x0 - 6) $y -Bold; $y += 92
    $null = T $g 'WED 11 NOV' $m 12 (C $c.mid) $x0 $y; $y += 34
    Box $g (C $c.rule) $x0 ($y + 4) $W 1; Box $g (C $c.accent) ($x0 + 220) $y 4 10; $y += 34
    $null = T $g '02 / LONDON' $m 10 (C $c.dim) $x0 $y; $y += 20
    $temp = [int][Math]::Floor([double]$wx.current.temperature_2m)
    $s = T $g ("$temp" + [char]0x00B0) $d 39 (C $c.ink) ($x0 - 3) $y -Bold
    $null = T $g 'OVERCAST' $m 12 (C $c.mid) ($x0 + $s.Width + 14) ($y + 9)
    $null = T $g ("{0}% HUMID  .  {1} KM/H" -f $wx.current.relative_humidity_2m, [int][Math]::Floor([double]$wx.current.wind_speed_10m)) $m 12 (C $c.mid) ($x0 + $s.Width + 14) ($y + 30); $y += 86
    $null = T $g '03 / PRICES' $m 10 (C $c.dim) $x0 $y; $y += 26
    foreach ($coin in @(@('BTC', $px.bitcoin), @('ETH', $px.ethereum))) {
        $price = ([double]$coin[1].usd).ToString('#,0', $inv)
        $chg = [double]$coin[1].usd_24h_change
        $chgS = $(if ($chg -ge 0) { '+' } else { '' }) + $chg.ToString('0.00', $inv) + '%'
        $null = T $g $coin[0] $m 12 (C $c.mid) $x0 ($y + 9)
        $null = T $g ('$' + $price) $d 24 (C $c.ink) ($x0 + 60) $y -Bold
        $null = T $g $chgS $m 12 $(if ($chg -lt 0) { C $c.accent } else { C $c.warn }) ($x0 + $W) ($y + 12) -Right
        $y += 39
    }
    $y += 20
    $null = T $g '04 / MACHINE' $m 10 (C $c.dim) $x0 $y; $y += 22
    foreach ($row in @(@('C:  61.4 GB FREE', 0.68, $c.mid), @('RAM  54%', 0.54, $c.mid), @('CPU  7%', 0.07, $c.accent))) {
        $null = T $g $row[0] $m 12 (C $c.mid) $x0 $y; $y += 22
        Box $g (C $c.rule) $x0 $y $W 3; Box $g (C $row[2]) $x0 $y ($W * $row[1]) 3; $y += 16
    }
    $y += 18
    $null = T $g '05 / CLAUDE' $m 10 (C $c.dim) $x0 $y; $y += 24
    Box $g (C $c.mid) $x0 ($y + 4) 12 12
    $null = T $g 'OPERATIONAL' $m 12 (C $c.ink) ($x0 + 24) $y
}

function Draw-Now($g, $t, [double]$x0, [double]$y0) {
    $c = $t.colors
    $null = T $g '06 / NOW PLAYING' $t.fonts.mono 10 (C $c.dim) $x0 $y0
    Box $g (C $c.accent) $x0 ($y0 + 26) 4 30
    $null = T $g $np[0] $t.fonts.display 24 (C $c.ink) ($x0 + 16) ($y0 + 18) -Bold
    $null = T $g $np[1].ToUpper() $t.fonts.mono 12 (C $c.mid) ($x0 + 16) ($y0 + 58)
}

function Draw-Dock($g, $t, [int]$W, [double]$y0) {
    $c = $t.colors
    Box $g (C $c.surface) 0 $y0 $W 56; Box $g (C $c.rule) 0 $y0 $W 1
    $x = 24
    $labels = @(@('00', 'HOME', 2), @('01', 'FILES', 1), @('02', 'NOTEPAD', 0), @('03', 'TERMINAL', 2), @('04', 'SETTINGS', 0), @('05', 'TASKS', 1))
    foreach ($l in $labels) {
        $idx = if ($l[2] -eq 0) { C $c.dim } else { C $c.accent }
        $col = switch ($l[2]) { 0 { C $c.dim } 1 { C $c.mid } 2 { C $c.ink } }
        $s1 = T $g $l[0] $t.fonts.mono 9 $idx $x ($y0 + 20)
        $s2 = T $g $l[1] $t.fonts.display 12 $col ($x + $s1.Width) ($y0 + 16) -Bold
        $x += $s1.Width + $s2.Width + 28
        if ($l[1] -eq 'HOME') { Box $g (C $c.rule) ($x - 14) ($y0 + 16) 1 24 }
    }
    $null = T $g 'VOL 42' $t.fonts.mono 9 (C $c.mid) ($W - 384) ($y0 + 20); Box $g (C $c.rule) ($W - 384) ($y0 + 41) 72 2; Box $g (C $c.accent) ($W - 384) ($y0 + 41) 30 2
    $null = T $g 'BRT 70' $t.fonts.mono 9 (C $c.mid) ($W - 292) ($y0 + 20); Box $g (C $c.rule) ($W - 292) ($y0 + 41) 72 2; Box $g (C $c.accent) ($W - 292) ($y0 + 41) 50 2
    $null = T $g 'AC 100%' $t.fonts.mono 9 (C $c.mid) ($W - 150) ($y0 + 22) -Right
    $null = T $g '09:41' $t.fonts.display 13 (C $c.ink) ($W - 24) ($y0 + 16) -Right -Bold
}

function Draw-Home($g, $t, [int]$W, [int]$H) {
    $c = $t.colors; $m = $t.fonts.mono
    Box $g (C $c.surface 247) 0 0 $W $H
    Box $g (C $c.accent) ([int]($W * 0.618)) 0 3 $H
    $x = $W * 0.048
    $null = T $g '00 / HOME' $m 10 (C $c.dim) $x 56
    $null = T $g 'ESC TO CLOSE  .  WIN+Z TO OPEN' $m 10 (C $c.dim) ($W - $x) 56 -Right
    $null = T $g '09:41' $t.fonts.display 112 (C $c.ink) ($x - 12) 66 -Bold
    $null = T $g 'WEDNESDAY 11 NOVEMBER' $m 12 (C $c.mid) $x 276
    $null = T $g 'Search anything' $t.fonts.display 26 (C $c.mid) ($W - $x) 206 -Right -Bold
    $null = T $g 'ALT + SPACE' $m 10 (C $c.dim) ($W - $x) 278 -Right
    Box $g (C $c.rule) $x 340 ($W - 2 * $x) 1
    $null = T $g '01 / APPS' $m 10 (C $c.dim) $x 372
    $null = T $g '02 / SYSTEM' $m 10 (C $c.dim) ($W * 0.67) 372
    $apps = 'Files', 'Notepad', 'Terminal', 'Settings', 'Task Manager'
    for ($i = 0; $i -lt $apps.Count; $i++) {
        $hot = $i -eq 2
        $s = T $g ('{0:00}' -f ($i + 1)) $m 10 $(if ($hot) { C $c.accent } else { C $c.dim }) $x (418 + $i * 44)
        $null = T $g $apps[$i] $t.fonts.display 19 $(if ($hot) { C $c.ink } else { C $c.mid }) ($x + $s.Width + 8) (410 + $i * 44) -Bold
    }
    $sys = 'Lock', 'Power'
    for ($i = 0; $i -lt $sys.Count; $i++) {
        $s = T $g ('{0:00}' -f ($i + 1)) $m 10 (C $c.dim) ($W * 0.67) (418 + $i * 44)
        $null = T $g $sys[$i] $t.fonts.display 19 (C $c.mid) ($W * 0.67 + $s.Width + 8) (410 + $i * 44) -Bold
    }
}

function Draw-Boot($g, $t, [int]$W, [int]$H) {
    $c = $t.colors; $m = $t.fonts.mono
    Box $g (C $c.surface) 0 0 $W $H
    $x = $W * 0.106
    $null = T $g 'DESK / BOOT  08:41' $m 10 (C $c.accent) ($x + 4) 262
    $null = T $g 'WELCOME BACK' $t.fonts.display 72 (C $c.ink) ($x - 4) 282 -Bold
    Box $g (C $c.rule) $x 440 ($W - 2 * $x) 2; Box $g (C $c.accent) $x 440 (($W - 2 * $x) * 0.83) 2
    $rows = @(@('SESSION', 'READY'), @('NETWORK', 'ONLINE  14S'), @('WIDGETS', '5/5'), @('DOCK', 'READY'), @('DESK', 'READY'))
    for ($i = 0; $i -lt $rows.Count; $i++) {
        $y = 480 + $i * 48
        $null = T $g ('{0:00}' -f ($i + 1)) $m 11 (C $c.accent) ($x + 4) ($y + 4)
        $null = T $g $rows[$i][0] $t.fonts.display 14 (C $c.mid) ($x + 70) $y -Bold
        $null = T $g $rows[$i][1] $t.fonts.display 14 (C $c.ink) ($x + 420) $y -Bold
    }
}

function Get-Candles {
    $rnd = New-Object Random(7); $p = 87000.0; $out = @()
    for ($i = 0; $i -lt 46; $i++) {
        $o = $p; $p = $p + ($rnd.NextDouble() - 0.48) * 260
        $hi = [Math]::Max($o, $p) + $rnd.NextDouble() * 120; $lo = [Math]::Min($o, $p) - $rnd.NextDouble() * 120
        $out += , @($o, $hi, $lo, $p)
    }
    return , $out
}

function Draw-Tape($g, $t, [double]$x0, [double]$y0) {
    $c = $t.colors; $cs = Get-Candles; $TW = 850; $TH = 200; $pad = 10
    $max = ($cs | ForEach-Object { $_[1] } | Measure-Object -Maximum).Maximum; $min = ($cs | ForEach-Object { $_[2] } | Measure-Object -Minimum).Minimum
    $Y = { param($v) $y0 + $pad + ($max - $v) / ($max - $min) * ($TH - 2 * $pad) }
    $step = $TW / 46
    for ($i = 0; $i -lt 46; $i++) {
        $k = $cs[$i]; $up = $k[3] -ge $k[0]; $last = $i -eq 45
        $col = if ($last) { C $c.warn } elseif ($up) { C $c.mid 150 } else { C $c.accent 170 }
        $x = $x0 + $i * $step + ($step - 8) / 2
        Box $g $col ($x + 3.5) (& $Y $k[1]) 1 ((& $Y $k[2]) - (& $Y $k[1]))
        $top = & $Y ([Math]::Max($k[0], $k[3])); $bot = & $Y ([Math]::Min($k[0], $k[3]))
        Box $g $col $x $top 8 ([Math]::Max($bot - $top, 2))
    }
    $null = T $g ('BTCUSDT 15M  ' + $cs[45][3].ToString('#,0', $inv)) $t.fonts.mono 9 (C $c.dim) $x0 ($y0 + $TH + 8)
}

function Draw-Depth($g, $t, [double]$x0, [double]$y0) {
    $c = $t.colors; $rnd = New-Object Random(11)
    for ($r = 0; $r -lt 20; $r++) {
        $w = 4 + [Math]::Sqrt($rnd.NextDouble()) * 200; if ($r -eq 13) { $w = 204 }
        $yy = $y0 + $r * 22 + $(if ($r -ge 10) { 8 } else { 0 })
        $col = if ($r -eq 13) { C $c.warn 150 } elseif ($r -lt 10) { C $c.mid 90 } else { C $c.dim 120 }
        Box $g $col ($x0 + 244 - $w) $yy $w 12
        $null = T $g ((87520 - $r * 10).ToString('#,0', $inv)) $t.fonts.mono 9 (C $c.mid) ($x0 + 254) ($yy - 2)
    }
}

function Draw-Wave($g, $t, [int]$W, [double]$y0) {
    $c = $t.colors; $bw = $W / 96
    for ($i = 0; $i -lt 96; $i++) {
        $k = [Math]::Abs(48 - $i - 0.5) / 48; $h = [Math]::Max(1, 14 * [Math]::Pow(1 - $k, 1.6) * (0.5 + 0.5 * [Math]::Abs([Math]::Sin($i * 0.7))))
        Box $g (C $c.accent 200) ($i * $bw + 1) ($y0 + 14 - $h) ($bw - 2) $h
    }
}

function Draw-Alert($g, $t, [int]$W) {
    $c = $t.colors
    Box $g (C $c.accent) 0 0 $W 72
    $null = T $g 'NEW' $t.fonts.mono 10 ([Drawing.Color]::FromArgb(235, 255, 255, 255)) 40 28
    $null = T $g 'MAIL' $t.fonts.display 22 ([Drawing.Color]::White) 110 14 -Bold
    $null = T $g '3 UNREAD MESSAGES' $t.fonts.display 14 ([Drawing.Color]::FromArgb(235, 255, 255, 255)) ($W - 40) 24 -Right -Bold
}

function Draw-Desk($t) {
    $cv = New-Canvas 1920 1080
    Draw-Wallpaper $cv.g $t 1920 1080
    Draw-Panel $cv.g $t 1496 96
    Draw-Now $cv.g $t 1496 860
    Draw-Dock $cv.g $t 1920 1024
    return $cv
}

function Want([string]$k) { return (-not $Only) -or ($Only -contains $k) }

# ------------------------------------------------------------------ outputs

$themes = Get-ChildItem -Directory (Join-Path $repo 'themes') | ForEach-Object { $_.Name }
foreach ($tn in $themes) {
    if (-not (Want $tn) -and -not (Want 'themes')) { continue }
    $t = Get-Theme $tn
    $cv = New-Canvas 1920 1080; Draw-Wallpaper $cv.g $t 1920 1080
    Save-Canvas $cv (Join-Path $repo "themes\$tn\wallpaper.png"); $cv.g.Dispose(); $cv.b.Dispose()
    $cv = Draw-Desk $t; Save-Canvas $cv (Join-Path $repo "themes\$tn\screenshot.png") 960 540; $cv.g.Dispose(); $cv.b.Dispose()
}

$t = Get-Theme 'red-on-black'
function Crop-Desk([int]$x, [int]$y, [int]$w, [int]$h, [string]$path) {
    $cv = Draw-Desk $t
    $o = New-Canvas $w $h; $o.g.DrawImage($cv.b, (New-Object Drawing.Rectangle(0, 0, $w, $h)), (New-Object Drawing.Rectangle($x, $y, $w, $h)), [Drawing.GraphicsUnit]::Pixel)
    Save-Canvas $o $path; $o.g.Dispose(); $o.b.Dispose(); $cv.g.Dispose(); $cv.b.Dispose()
}
if (Want 'panel') { Crop-Desk 1440 64 460 760 (Join-Path $repo 'skins\panel\screenshot.png') }
if (Want 'now') { Crop-Desk 1440 830 460 150 (Join-Path $repo 'skins\now\screenshot.png') }
if (Want 'dock') { Crop-Desk 0 1000 1920 80 (Join-Path $repo 'skins\dock\screenshot.png') }
if (Want 'home') {
    $cv = New-Canvas 1920 1080; Draw-Wallpaper $cv.g $t 1920 1080; Draw-Home $cv.g $t 1920 1080
    Save-Canvas $cv (Join-Path $repo 'skins\home\screenshot.png') 960 540; $cv.g.Dispose(); $cv.b.Dispose()
}
if (Want 'boot') {
    $cv = New-Canvas 1920 1080; Draw-Boot $cv.g $t 1920 1080
    Save-Canvas $cv (Join-Path $repo 'skins\boot\screenshot.png') 960 540; $cv.g.Dispose(); $cv.b.Dispose()
}
if (Want 'tape') {
    $cv = New-Canvas 920 260; Draw-Wallpaper $cv.g $t 920 260; Draw-Tape $cv.g $t 35 20
    Save-Canvas $cv (Join-Path $repo 'addons\tape\screenshot.png'); $cv.g.Dispose(); $cv.b.Dispose()
}
if (Want 'depth') {
    $cv = New-Canvas 360 480; Draw-Wallpaper $cv.g $t 360 480; Draw-Depth $cv.g $t 20 16
    Save-Canvas $cv (Join-Path $repo 'addons\depth\screenshot.png'); $cv.g.Dispose(); $cv.b.Dispose()
}
if (Want 'wave') {
    $cv = New-Canvas 1920 80; Draw-Wallpaper $cv.g $t 1920 80; Draw-Dock $cv.g $t 1920 24; Draw-Wave $cv.g $t 1920 10
    Save-Canvas $cv (Join-Path $repo 'addons\wave\screenshot.png'); $cv.g.Dispose(); $cv.b.Dispose()
}
if (Want 'mood') {
    $cv = Draw-Desk $t
    $lg = New-Object Drawing.Drawing2D.LinearGradientBrush((New-Object Drawing.Point(0, 1080)), (New-Object Drawing.Point(0, 300)), (C $t.colors.accent 70), (C $t.colors.accent 0))
    $cv.g.FillRectangle($lg, 0, 0, 1920, 1080); $lg.Dispose()
    $null = T $cv.g 'BTC 4H  -1.12%   RISK OFF' $t.fonts.mono 9 (C $t.colors.accent) 300 272
    Save-Canvas $cv (Join-Path $repo 'addons\mood\screenshot.png') 960 540; $cv.g.Dispose(); $cv.b.Dispose()
}
if (Want 'alert') {
    $cv = New-Canvas 1920 120; Draw-Wallpaper $cv.g $t 1920 120; Draw-Alert $cv.g $t 1920
    Save-Canvas $cv (Join-Path $repo 'addons\alert\screenshot.png') 1280 80; $cv.g.Dispose(); $cv.b.Dispose()
}
