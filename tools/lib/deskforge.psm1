# deskforge shared functions: config validation, generated include files, paths, registry access.
# Windows PowerShell 5.1. No admin rights. In test mode (TestRoot set) nothing outside TestRoot is touched:
# files go under TestRoot and registry reads and writes go to TestRoot\registry.json.

Set-StrictMode -Version 2

$script:Utf8 = New-Object Text.UTF8Encoding($false)
$script:Repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

function Get-DeskRepo { return $script:Repo }

# ------------------------------------------------------------------ JSON Schema subset validator
# Supports: type, const, enum, required, properties, additionalProperties:false, minimum, maximum,
# minLength, maxLength, pattern, items, minItems, maxItems, uniqueItems. Enough for desk.schema.json.

function Test-IsNumber($v) { return ($v -is [int] -or $v -is [long] -or $v -is [double] -or $v -is [decimal] -or $v -is [single]) }

function Test-JsonType($v, [string]$type) {
    switch ($type) {
        'object'  { return ($v -is [System.Management.Automation.PSCustomObject]) }
        'array'   { return ($v -is [array]) }
        'string'  { return ($v -is [string]) }
        'boolean' { return ($v -is [bool]) }
        'number'  { return (Test-IsNumber $v) }
        'integer' { return ((Test-IsNumber $v) -and ([decimal]$v % 1 -eq 0)) }
        'null'    { return ($null -eq $v) }
    }
    return $false
}

function Test-JsonNode($v, $s, [string]$at, [System.Collections.Generic.List[string]]$errors) {
    $names = @($s.PSObject.Properties.Name)
    if ($names -contains 'type') {
        if (-not (Test-JsonType $v $s.type)) { $errors.Add("$at must be $($s.type)"); return }
    }
    if ($names -contains 'const' -and "$v" -ne "$($s.const)") { $errors.Add("$at must be $($s.const)") }
    if ($names -contains 'enum' -and -not (@($s.enum) -ccontains $v)) { $errors.Add("$at must be one of: $(@($s.enum) -join ', ')") }
    if (Test-IsNumber $v) {
        if ($names -contains 'minimum' -and $v -lt $s.minimum) { $errors.Add("$at must be at least $($s.minimum)") }
        if ($names -contains 'maximum' -and $v -gt $s.maximum) { $errors.Add("$at must be at most $($s.maximum)") }
    }
    if ($v -is [string]) {
        if ($names -contains 'minLength' -and $v.Length -lt $s.minLength) { $errors.Add("$at is too short") }
        if ($names -contains 'maxLength' -and $v.Length -gt $s.maxLength) { $errors.Add("$at is too long (max $($s.maxLength))") }
        if ($names -contains 'pattern' -and -not [regex]::IsMatch($v, $s.pattern)) { $errors.Add("$at has characters that are not allowed") }
    }
    if ($v -is [array]) {
        if ($names -contains 'minItems' -and $v.Count -lt $s.minItems) { $errors.Add("$at needs at least $($s.minItems) item(s)") }
        if ($names -contains 'maxItems' -and $v.Count -gt $s.maxItems) { $errors.Add("$at allows at most $($s.maxItems) item(s)") }
        if ($names -contains 'uniqueItems' -and $s.uniqueItems) {
            $seen = @{}
            foreach ($i in $v) { $k = ($i | ConvertTo-Json -Compress -Depth 5); if ($seen.ContainsKey($k)) { $errors.Add("$at has a duplicate item"); break }; $seen[$k] = 1 }
        }
        if ($names -contains 'items') { for ($i = 0; $i -lt $v.Count; $i++) { Test-JsonNode $v[$i] $s.items "$at[$i]" $errors } }
    }
    if ($v -is [System.Management.Automation.PSCustomObject]) {
        $have = @($v.PSObject.Properties.Name)
        $props = if ($names -contains 'properties') { $s.properties } else { New-Object psobject }
        $known = @($props.PSObject.Properties.Name)
        if ($names -contains 'required') { foreach ($r in $s.required) { if ($have -notcontains $r) { $errors.Add("$at.$r is missing") } } }
        foreach ($p in $have) {
            if ($known -contains $p) { Test-JsonNode $v.$p $props.$p "$at.$p" $errors }
            elseif ($names -contains 'additionalProperties' -and $s.additionalProperties -eq $false) { $errors.Add("$at.$p is not a known field") }
        }
    }
}

function Test-DeskConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Config, [string]$SchemaPath = (Join-Path $script:Repo 'config\desk.schema.json'))
    $schema = Get-Content -Raw $SchemaPath | ConvertFrom-Json
    $errors = New-Object System.Collections.Generic.List[string]
    Test-JsonNode $Config $schema '$' $errors
    if ($errors.Count -eq 0) {
        $themeDir = Join-Path $script:Repo ("themes\" + $Config.theme)
        if (-not (Test-Path (Join-Path $themeDir 'theme.json'))) { $errors.Add("`$.theme '$($Config.theme)' has no themes/$($Config.theme)/theme.json") }
    }
    return , $errors.ToArray()
}

function Read-DeskConfig([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "config not found: $Path (copy config\desk.example.json to config\desk.json first)" }
    try { return (Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json) } catch { throw "config is not valid JSON: $Path" }
}

# ------------------------------------------------------------------ themes

function ConvertTo-RmColor([string]$hex) {
    if ($hex -notmatch '^#([0-9a-fA-F]{2})([0-9a-fA-F]{2})([0-9a-fA-F]{2})$') { throw "bad colour '$hex' (use #rrggbb)" }
    return '{0},{1},{2}' -f [Convert]::ToInt32($Matches[1], 16), [Convert]::ToInt32($Matches[2], 16), [Convert]::ToInt32($Matches[3], 16)
}

function Read-DeskTheme([string]$Name) {
    $p = Join-Path $script:Repo "themes\$Name\theme.json"
    $t = Get-Content -Raw $p | ConvertFrom-Json
    foreach ($k in 'bg', 'surface', 'ink', 'mid', 'dim', 'rule', 'accent', 'warn', 'onAccent') { $null = ConvertTo-RmColor $t.colors.$k }
    return $t
}

function New-ThemeInc($Theme) {
    $c = $Theme.colors
    $lines = @(('; generated by deskforge from themes/' + $Theme.name + '/theme.json. Do not edit; edit the theme and reinstall.'), '[Variables]')
    foreach ($k in 'bg', 'surface', 'ink', 'mid', 'dim', 'rule', 'accent', 'warn', 'onAccent') {
        $lines += ('{0}={1}' -f ($k.Substring(0, 1).ToUpper() + $k.Substring(1)), (ConvertTo-RmColor $c.$k))
    }
    $lines += "Display=$($Theme.fonts.display)"
    $lines += "Mono=$($Theme.fonts.mono)"
    return ($lines -join "`r`n") + "`r`n"
}

# ------------------------------------------------------------------ desk include files

function Get-CoinLabel([string]$id) {
    $known = @{ bitcoin = 'BTC'; ethereum = 'ETH'; solana = 'SOL'; tether = 'USDT'; 'usd-coin' = 'USDC'; binancecoin = 'BNB'; ripple = 'XRP'; dogecoin = 'DOGE'; cardano = 'ADA'; litecoin = 'LTC' }
    if ($known.ContainsKey($id)) { return $known[$id] }
    $s = ($id -replace '[^a-z0-9]', '').ToUpper()
    return $s.Substring(0, [Math]::Min(4, $s.Length))
}

function New-DeskInc($Config) {
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $c1 = $Config.coins[0]
    $c2 = if (@($Config.coins).Count -gt 1) { $Config.coins[1] } else { $Config.coins[0] }
    $twelve = $Config.clock -eq '12'
    $f = $Config.units -eq 'f'
    $lines = @(
        '; generated by deskforge from config\desk.json. Do not edit; edit desk.json and reinstall.',
        '[Variables]',
        "City=$($Config.city.ToUpper())",
        ('Lat={0}' -f ([double]$Config.latitude).ToString('0.####', $inv)),
        ('Lon={0}' -f ([double]$Config.longitude).ToString('0.####', $inv)),
        "TempUnit=$(if ($f) { 'fahrenheit' } else { 'celsius' })",
        "WindUnit=$(if ($f) { 'mph' } else { 'kmh' })",
        "WindLabel=$(if ($f) { 'MPH' } else { 'KM/H' })",
        "ClockFmt=$(if ($twelve) { '%#I:%M' } else { '%H:%M' })",
        "ClockSubFmt=$(if ($twelve) { '%p  .  %a %#d %b' } else { '%a %#d %b' })",
        "DockClockFmt=$(if ($twelve) { '%#I:%M %p' } else { '%H:%M' })",
        "Coin1=$c1",
        "Coin1Label=$(Get-CoinLabel $c1)",
        "Coin2=$c2",
        "Coin2Label=$(Get-CoinLabel $c2)",
        "Coin2Hidden=$(if (@($Config.coins).Count -gt 1) { 0 } else { 1 })",
        "PriceRate=$($Config.refreshSeconds)",
        "DockEdge=$($Config.dock)",
        "WakeReveal=$(if ($Config.wakeReveal.enabled -and $Config.skins.boot) { 1 } else { 0 })",
        "WakeText=$(if ($Config.wakeReveal.text) { $Config.wakeReveal.text.ToUpper() } else { 'DESKFORGE' })",
        "AddonAlert=$(if ($Config.addons.alert) { 1 } else { 0 })",
        "AddonWave=$(if ($Config.addons.wave) { 1 } else { 0 })"
    )
    return ($lines -join "`r`n") + "`r`n"
}

function New-AppsTxt($Config) {
    $lines = @('# generated by deskforge from homeApps in config\desk.json: name|path')
    foreach ($a in @($Config.homeApps)) { $lines += "$($a.name)|$($a.path)" }
    return ($lines -join "`r`n") + "`r`n"
}

function New-HomeInc($Config) {
    $out = @('; generated by deskforge from homeApps in config\desk.json. Do not edit; edit desk.json and reinstall.')
    $i = 0
    foreach ($a in @($Config.homeApps)) {
        $i++
        $n = 'A' + $i
        $out += @(
            "[$n]",
            'Meter=String',
            'MeterStyle=sRow',
            ('Text={0:00}  {1}' -f $i, $a.name),
            'X=(#SCREENAREAWIDTH#*0.048)',
            ('Y=(#SCREENAREAHEIGHT#*0.38+{0})' -f (($i - 1) * 44)),
            ('LeftMouseUpAction=["#@#dock.exe" "go" "{0}"]' -f $i),
            ('MouseOverAction=[!SetOption {0} FontColor "#Ink#"][!SetOption {0} InlineSetting "Color | #Accent#"][!UpdateMeter {0}][!Redraw]' -f $n),
            ('MouseLeaveAction=[!SetOption {0} FontColor "#Mid#"][!SetOption {0} InlineSetting "Color | #Dim#"][!UpdateMeter {0}][!Redraw]' -f $n),
            ''
        )
    }
    return ($out -join "`r`n") + "`r`n"
}

# Which skin and addon folders get installed, with their Rainmeter config names and layout positions.
function Get-DeskItems($Config) {
    $items = @(
        @{ key = 'panel'; kind = 'skins'; src = 'skins\panel'; cfg = 'Panel'; ini = 'Panel.ini'; on = $Config.skins.panel; pos = @{ WindowX = '64R'; WindowY = '96'; AnchorX = '100%' } },
        @{ key = 'now'; kind = 'skins'; src = 'skins\now'; cfg = 'Now'; ini = 'Now.ini'; on = $Config.skins.now; pos = @{ WindowX = '64R'; WindowY = '160B'; AnchorX = '100%'; AnchorY = '100%' } },
        @{ key = 'dock'; kind = 'skins'; src = 'skins\dock'; cfg = 'Dock'; ini = 'Dock.ini'; on = $Config.skins.dock; pos = $(if ($Config.dock -eq 'top') { @{ WindowX = '0'; WindowY = '0' } } else { @{ WindowX = '0'; WindowY = '0B'; AnchorY = '100%' } }) },
        @{ key = 'home'; kind = 'skins'; src = 'skins\home'; cfg = 'Home'; ini = 'Home.ini'; on = $Config.skins.home; pos = @{ WindowX = '0'; WindowY = '0' } },
        @{ key = 'boot'; kind = 'skins'; src = 'skins\boot'; cfg = 'Boot'; ini = 'Boot.ini'; on = $Config.skins.boot; pos = @{ WindowX = '0'; WindowY = '0' }; startActive = $false },
        @{ key = 'tape'; kind = 'addons'; src = 'addons\tape'; cfg = 'Tape'; ini = 'Tape.ini'; on = $Config.addons.tape; pos = @{ WindowX = '120'; WindowY = '120' } },
        @{ key = 'depth'; kind = 'addons'; src = 'addons\depth'; cfg = 'Depth'; ini = 'Depth.ini'; on = $Config.addons.depth; pos = @{ WindowX = '120'; WindowY = '380' } },
        @{ key = 'wave'; kind = 'addons'; src = 'addons\wave'; cfg = 'Wave'; ini = 'Wave.ini'; on = $Config.addons.wave; pos = $(if ($Config.dock -eq 'top') { @{ WindowX = '0'; WindowY = '56' } } else { @{ WindowX = '0'; WindowY = '56B'; AnchorY = '100%' } }) },
        @{ key = 'mood'; kind = 'addons'; src = 'addons\mood'; cfg = 'Mood'; ini = 'Mood.ini'; on = $Config.addons.mood; pos = @{ WindowX = '0'; WindowY = '0' } },
        @{ key = 'alert'; kind = 'addons'; src = 'addons\alert'; cfg = 'Alert'; ini = 'Alert.ini'; on = $Config.addons.alert; pos = @{ WindowX = '0'; WindowY = '0' }; startActive = $false }
    )
    return $items
}

function New-LayoutIni($Config) {
    $lines = @('[Rainmeter]', '')
    foreach ($it in (Get-DeskItems $Config)) {
        if (-not $it.on) { continue }
        $active = if ($it.ContainsKey('startActive') -and -not $it.startActive) { 0 } else { 1 }
        $lines += "[deskforge\$($it.cfg)]"
        $lines += "Active=$active"
        foreach ($k in ($it.pos.Keys | Sort-Object)) { $lines += "$k=$($it.pos[$k])" }
        $lines += ''
    }
    return ($lines -join "`r`n")
}

# ------------------------------------------------------------------ paths and context

function New-DeskContext {
    param([string]$TestRoot)
    $ctx = @{ Test = [bool]$TestRoot }
    if ($TestRoot) {
        $root = [IO.Path]::GetFullPath($TestRoot)
        $ctx.TestRoot = $root
        $ctx.SkinsRoot = Join-Path $root 'Skins'
        $ctx.RmSettings = Join-Path $root 'RainmeterSettings'
        $ctx.StateRoot = Join-Path $root 'State'
        $ctx.RegistryFile = Join-Path $root 'registry.json'
        $ctx.RainmeterExe = $null
    }
    else {
        $ctx.SkinsRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Rainmeter\Skins'
        $ctx.RmSettings = Join-Path $env:APPDATA 'Rainmeter'
        $ctx.StateRoot = Join-Path $env:LOCALAPPDATA 'deskforge'
        $exe = Join-Path $env:ProgramFiles 'Rainmeter\Rainmeter.exe'
        $ctx.RainmeterExe = if (Test-Path $exe) { $exe } else { $null }
    }
    $ctx.ConfigRoot = Join-Path $ctx.SkinsRoot 'deskforge'
    $ctx.Resources = Join-Path $ctx.ConfigRoot '@Resources'
    $ctx.LogPath = Join-Path $ctx.StateRoot 'install-log.json'
    return $ctx
}

function Test-IsAdmin {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-RainmeterRunning { return [bool](Get-Process Rainmeter -ErrorAction SilentlyContinue) }

# ------------------------------------------------------------------ registry (real HKCU, or a JSON file in test mode)

function Read-TestRegistry($ctx) {
    $h = @{}
    if (Test-Path $ctx.RegistryFile) {
        $o = Get-Content -Raw $ctx.RegistryFile | ConvertFrom-Json
        foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = $p.Value }
    }
    return $h
}

function Write-TestRegistry($ctx, $h) {
    $o = New-Object psobject
    foreach ($k in ($h.Keys | Sort-Object)) { $o | Add-Member -NotePropertyName $k -NotePropertyValue $h[$k] }
    [IO.File]::WriteAllText($ctx.RegistryFile, ($o | ConvertTo-Json -Depth 5), $script:Utf8)
}

function Get-DeskReg($ctx, [string]$Path, [string]$Name) {
    if ($ctx.Test) {
        $h = Read-TestRegistry $ctx; $k = "$Path|$Name"
        if ($h.ContainsKey($k)) { return @{ exists = $true; value = [string]$h[$k] } }
        return @{ exists = $false; value = $null }
    }
    $item = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
    if ($null -ne $item -and ($item.PSObject.Properties.Name -contains $Name)) { return @{ exists = $true; value = [string]$item.$Name } }
    return @{ exists = $false; value = $null }
}

function Set-DeskReg($ctx, [string]$Path, [string]$Name, [string]$Value) {
    if (-not $Path.StartsWith('HKCU:\')) { throw "deskforge only writes under HKCU: $Path" }
    if ($ctx.Test) { $h = Read-TestRegistry $ctx; $h["$Path|$Name"] = $Value; Write-TestRegistry $ctx $h; return }
    if (-not (Test-Path -LiteralPath $Path)) { throw "registry key not found: $Path" }
    Set-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -Type String
}

function Remove-DeskReg($ctx, [string]$Path, [string]$Name) {
    if (-not $Path.StartsWith('HKCU:\')) { throw "deskforge only writes under HKCU: $Path" }
    if ($ctx.Test) { $h = Read-TestRegistry $ctx; $null = $h.Remove("$Path|$Name"); Write-TestRegistry $ctx $h; return }
    Remove-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
}

# Applies the wallpaper the supported way (SystemParametersInfo). Real mode only.
function Set-DeskWallpaper([string]$File) {
    if (-not ('DeskforgeSpi' -as [type])) {
        Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class DeskforgeSpi {
  [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  public static extern bool SystemParametersInfo(uint a, uint b, string c, uint f);
}
'@
    }
    # SPI_SETDESKWALLPAPER, SPIF_UPDATEINIFILE | SPIF_SENDCHANGE
    return [DeskforgeSpi]::SystemParametersInfo(0x0014, 0, $File, 0x03)
}

function Get-FileSha256([string]$Path) { return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLower() }

# -Rainmeter writes UTF-16 LE with a BOM, the encoding Rainmeter reads non-ASCII text from reliably.
function Write-DeskText([string]$Path, [string]$Text, [switch]$Rainmeter) {
    New-Item -ItemType Directory -Force (Split-Path -Parent $Path) | Out-Null
    $enc = if ($Rainmeter) { New-Object Text.UnicodeEncoding($false, $true) } else { $script:Utf8 }
    [IO.File]::WriteAllText($Path, $Text, $enc)
}

Export-ModuleMember -Function *
