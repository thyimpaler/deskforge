<#
.SYNOPSIS
  Dry run, apply and restore against a throwaway test root. Never touches the real desk, Rainmeter or registry.
.DESCRIPTION
  1. Seeds a fake Rainmeter.ini, fake wallpaper registry values and an unrelated skin.
  2. Dry run: nothing in the test root may change.
  3. Apply: expected files, registry values and install-log.json appear; zero ERROR lines.
  4. Restore -Phase wallpaper: only the wallpaper values go back.
  5. Restore: every file outside State\ and every registry value is identical to the seed.
  -Config picks the desk.json used (default: the example with startup on and two addons on).
#>
[CmdletBinding()]
param([switch]$SkipHelpers, [switch]$Keep)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$install = Join-Path $repo 'tools\install.ps1'
$restore = Join-Path $repo 'tools\restore.ps1'
$root = Join-Path $env:TEMP ('deskforge-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$fails = 0
function Check([string]$name, [bool]$ok, [string]$detail = '') {
    if ($ok) { Write-Output "PASS  $name" } else { Write-Output "FAIL  $name $detail"; $script:fails++ }
}
function Get-State {
    $h = @{}
    Get-ChildItem -Recurse -File -Force $root | Where-Object { $_.FullName -notlike "$root\State\*" } |
        ForEach-Object { $h[$_.FullName.Substring($root.Length)] = (Get-FileHash -Algorithm SHA256 $_.FullName).Hash }
    return $h
}
function Get-Reg { return (Get-Content -Raw (Join-Path $root 'registry.json') | ConvertFrom-Json | ConvertTo-Json -Compress) }
function Same($a, $b) {
    if ($a.Count -ne $b.Count) { return $false }
    foreach ($k in $a.Keys) { if (-not $b.ContainsKey($k) -or $a[$k] -ne $b[$k]) { return $false } }
    return $true
}

try {
    # ---- seed
    New-Item -ItemType Directory -Force "$root\RainmeterSettings", "$root\Skins\SomeoneElse" | Out-Null
    [IO.File]::WriteAllText("$root\RainmeterSettings\Rainmeter.ini", "[Rainmeter]`r`nSkinPath=x`r`n`r`n[SomeoneElse]`r`nActive=1`r`n", [Text.Encoding]::Unicode)
    [IO.File]::WriteAllText("$root\Skins\SomeoneElse\Other.ini", "[Rainmeter]`r`nUpdate=1000`r`n")
    # a file the install will overwrite, so it gets a backup that restore must put back
    New-Item -ItemType Directory -Force "$root\Skins\deskforge\Panel" | Out-Null
    [IO.File]::WriteAllText("$root\Skins\deskforge\Panel\Panel.ini", "[Rainmeter]`r`n; the user's own earlier Panel.ini`r`n")
    $seedReg = [ordered]@{
        'HKCU:\Control Panel\Desktop|TileWallpaper'  = '0'
        'HKCU:\Control Panel\Desktop|WallPaper'      = 'X:\seed\wallpaper.jpg'
        'HKCU:\Control Panel\Desktop|WallpaperStyle' = '2'
    }
    [IO.File]::WriteAllText("$root\registry.json", ($seedReg | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
    $cfg = Get-Content -Raw (Join-Path $repo 'config\desk.example.json') | ConvertFrom-Json
    $cfg.startup = $true; $cfg.addons.wave = $true; $cfg.addons.alert = $true
    $cfgPath = Join-Path $root 'desk.json'
    [IO.File]::WriteAllText($cfgPath, ($cfg | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false)))
    $state0 = Get-State; $reg0 = Get-Reg

    # ---- dry run
    $out = & $install -Config $cfgPath -TestRoot $root -SkipHelpers:$SkipHelpers
    Check 'dry run exit code 0' ($LASTEXITCODE -eq 0) "($LASTEXITCODE)"
    Check 'dry run has zero ERROR lines' (-not ($out -match '^ERROR')) (($out -match '^ERROR') -join ' | ')
    Check 'dry run lists files and registry values' ((@($out -match '^PLAN .* file ').Count -gt 5) -and (@($out -match '^PLAN .*set registry').Count -eq 4))
    Check 'dry run writes nothing' ((Same $state0 (Get-State)) -and ($reg0 -eq (Get-Reg)) -and -not (Test-Path "$root\State"))

    # ---- apply
    $out = & $install -Config $cfgPath -TestRoot $root -Apply -SkipHelpers:$SkipHelpers
    Check 'apply exit code 0' ($LASTEXITCODE -eq 0) (($out | Select-Object -Last 3) -join ' | ')
    Check 'apply has zero ERROR lines' (-not ($out -match '^ERROR')) (($out -match '^ERROR') -join ' | ')
    Check 'install-log.json written' (Test-Path "$root\State\install-log.json")
    Check 'snapshot written before changes' ((Test-Path (Join-Path (Get-ChildItem "$root\State\backup" | Select-Object -First 1).FullName 'Rainmeter.ini')))
    Check 'panel installed' (Test-Path "$root\Skins\deskforge\Panel\Panel.ini")
    Check 'theme and desk include files written' ((Test-Path "$root\Skins\deskforge\@Resources\theme.inc") -and (Test-Path "$root\Skins\deskforge\@Resources\desk.inc"))
    if (-not $SkipHelpers) { Check 'helpers compiled' ((Test-Path "$root\Skins\deskforge\@Resources\dock.exe") -and (Test-Path "$root\Skins\deskforge\@Resources\nowplaying.exe")) }
    $reg1 = Get-Content -Raw "$root\registry.json" | ConvertFrom-Json
    Check 'wallpaper registry value set' ($reg1.'HKCU:\Control Panel\Desktop|WallPaper' -like '*\State\wallpaper\red-on-black-wallpaper.png')
    Check 'startup value set only under HKCU Run' ($reg1.'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run|deskforge' -like 'powershell.exe*desk-startup.ps1*')
    Check 'Rainmeter.ini now holds the deskforge layout' ((Get-Content "$root\RainmeterSettings\Rainmeter.ini") -contains '[deskforge\Panel]')
    Check 'unrelated skin untouched' ($state0['\Skins\SomeoneElse\Other.ini'] -eq (Get-FileHash -Algorithm SHA256 "$root\Skins\SomeoneElse\Other.ini").Hash)
    $out = & $install -Config $cfgPath -TestRoot $root -Apply -SkipHelpers:$SkipHelpers
    Check 'second install refused while installed' ($LASTEXITCODE -eq 1 -and ($out -match 'already installed'))

    # ---- the helpers and skins rewrite their run-time files while the desk runs
    [IO.File]::WriteAllText("$root\Skins\deskforge\@Resources\dockstate.txt", "1|0|0|1`n")
    [IO.File]::WriteAllText("$root\Skins\deskforge\@Resources\nowplaying.txt", "Song`nArtist")
    Check 'home rows generated from homeApps' ((Get-Content "$root\Skins\deskforge\@Resources\home.inc" -Raw) -match 'Text=05  Task Manager')

    # ---- partial restore
    $out = & $restore -TestRoot $root -Phase wallpaper
    Check 'restore -Phase wallpaper exit 0, zero ERROR' ($LASTEXITCODE -eq 0 -and -not ($out -match '^ERROR')) ($out -join ' | ')
    $reg2 = Get-Content -Raw "$root\registry.json" | ConvertFrom-Json
    Check 'wallpaper values back, startup value kept' (($reg2.'HKCU:\Control Panel\Desktop|WallPaper' -eq 'X:\seed\wallpaper.jpg') -and ($reg2.'HKCU:\Control Panel\Desktop|WallpaperStyle' -eq '2') -and ($null -ne $reg2.'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run|deskforge'))
    Check 'panel still installed after partial restore' (Test-Path "$root\Skins\deskforge\Panel\Panel.ini")

    # ---- a restore that stops half way keeps a log of exactly what is left
    $logPath = "$root\State\install-log.json"
    $before = @((Get-Content -Raw $logPath | ConvertFrom-Json).entries)
    $lock = [IO.File]::Open("$root\Skins\deskforge\Now\Now.ini", 'Open', 'ReadWrite', 'None')
    try { $out = & $restore -TestRoot $root; $code = $LASTEXITCODE } finally { $lock.Close() }
    $after = @((Get-Content -Raw $logPath | ConvertFrom-Json).entries)
    Check 'restore stops with exit 1 on a locked file' ($code -eq 1 -and ($out -match '^ERROR'))
    Check 'log saved after each entry: undone entries are gone, the rest stay' (($after.Count -lt $before.Count) -and ($after.Count -gt 0) -and -not ($after | Where-Object { $_.phase -eq 'startup' }) -and [bool]($after | Where-Object { $_.path -like '*\Now\Now.ini' }))

    # ---- a file an earlier restore already put back (it matches its backup) is not "changed after install"
    $pe = $after | Where-Object { $_.path -like '*\Panel\Panel.ini' }
    Check 'overwritten file has a backup in the log' ([bool]$pe -and [bool]$pe.backup -and (Test-Path -LiteralPath $pe.backup))
    Copy-Item -LiteralPath $pe.backup $pe.path -Force

    # ---- full restore
    $out = & $restore -TestRoot $root
    Check 'restore exit 0, zero ERROR, zero WARN' ($LASTEXITCODE -eq 0 -and -not ($out -match '^(ERROR|WARN)')) (($out -match '^(ERROR|WARN)') -join ' | ')
    $state2 = Get-State
    Check 'every file outside State\ identical to the seed' (Same $state0 $state2) (($state2.Keys | Where-Object { -not $state0.ContainsKey($_) }) -join ', ')
    Check 'registry values identical to the seed' ($reg0 -eq (Get-Reg)) (Get-Reg)
    Check 'install-log.json moved aside' (-not (Test-Path "$root\State\install-log.json"))
}
catch { Write-Output "FAIL  test harness: $($_.Exception.Message)"; $fails++ }
finally {
    if (-not $Keep -and (Test-Path $root)) { Remove-Item -Recurse -Force $root }
}
Write-Output $(if ($fails) { "install-restore: FAIL ($fails)" } else { 'install-restore: PASS' })
if ($fails) { exit 1 }
