<#
.SYNOPSIS
  Undoes a deskforge install, using only install-log.json and the snapshot it points to.
.DESCRIPTION
  Restores Rainmeter.ini, the wallpaper values and the startup value from the snapshot, and removes only the
  files and folders install-log.json lists. A listed file you edited since the install (its hash changed) is
  kept and reported. Folders are removed only when empty. It never touches Explorer and never uninstalls anything.
  -Phase skins|theme|wallpaper|startup|helpers undoes one part and keeps the rest in the log.
  -DryRun prints what it would do and changes nothing.
  -TestRoot works like install.ps1 -TestRoot.
.EXAMPLE
  .\tools\restore.ps1
  .\tools\restore.ps1 -Phase wallpaper
#>
[CmdletBinding()]
param(
    [ValidateSet('all', 'skins', 'theme', 'wallpaper', 'startup', 'helpers')][string]$Phase = 'all',
    [switch]$DryRun,
    [string]$TestRoot
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib\deskforge.psm1') -Force
function Say([string]$level, [string]$text) { Write-Output ('{0,-5} {1}' -f $level, $text) }

try {
    if (Test-IsAdmin) { throw 'refusing to run as administrator. Open a normal PowerShell window and run it again.' }
    $ctx = New-DeskContext -TestRoot $TestRoot
    if (-not (Test-Path $ctx.LogPath)) { throw "nothing to restore: $($ctx.LogPath) not found" }
    $log = Get-Content -Raw $ctx.LogPath | ConvertFrom-Json
    $all = @($log.entries)
    $mine = @($all | Where-Object { $Phase -eq 'all' -or $_.phase -eq $Phase })
    $prefix = if ($DryRun) { 'PLAN' } else { 'DONE' }
    Say 'INFO' "deskforge restore, phase $Phase, $(if ($DryRun) { 'DRY RUN' } else { 'APPLY' }), $($mine.Count) entr$(if ($mine.Count -eq 1) { 'y' } else { 'ies' })"

    $touchSkins = ($Phase -eq 'all' -or $Phase -eq 'skins' -or $Phase -eq 'helpers')
    if (-not $ctx.Test -and -not $DryRun -and $touchSkins -and (Test-RainmeterRunning) -and $ctx.RainmeterExe) {
        foreach ($c in 'Panel', 'Now', 'Dock', 'Home', 'Boot', 'Tape', 'Depth', 'Wave', 'Mood', 'Alert') { & $ctx.RainmeterExe '!DeactivateConfig' "deskforge\$c" }
        Start-Sleep -Seconds 1
        # stop only our own helpers, found by their path inside the deskforge config folder
        Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($ctx.Resources, [StringComparison]::OrdinalIgnoreCase) } |
            ForEach-Object { Say 'DONE' "stopped helper $($_.Path)"; Stop-Process -Id $_.Id -Force }
        Start-Sleep -Milliseconds 500
    }

    $warns = 0
    $done = New-Object System.Collections.Generic.HashSet[int]
    for ($i = $all.Count - 1; $i -ge 0; $i--) {
        $e = $all[$i]
        if (-not ($mine -contains $e)) { continue }
        switch ($e.kind) {
            'file' {
                if (Test-Path -LiteralPath $e.path) {
                    $h = Get-FileSha256 $e.path
                    if ($h -ne $e.sha256 -and -not ($e.PSObject.Properties.Name -contains 'volatile' -and $e.volatile)) { Say 'WARN' "kept $($e.path): it changed after install"; $warns++; continue }
                    if (-not $DryRun) {
                        if ($e.backup -and (Test-Path -LiteralPath $e.backup)) { Copy-Item -LiteralPath $e.backup $e.path -Force } else { Remove-Item -LiteralPath $e.path -Force }
                    }
                    Say $prefix ("{0,-9} {1}  {2}" -f $e.phase, $(if ($e.backup) { 'put back' } else { 'removed ' }), $e.path)
                }
                $null = $done.Add($i)
            }
            'folder' {
                if ($Phase -ne 'all') { continue }
                if (Test-Path -LiteralPath $e.path) {
                    $left = @(Get-ChildItem -Force -LiteralPath $e.path)
                    $isState = ($e.path -eq $ctx.StateRoot -or $ctx.StateRoot.StartsWith($e.path + '\', [StringComparison]::OrdinalIgnoreCase))
                    if ($isState) { Say 'INFO' "kept $($e.path): it holds the backups"; continue }
                    if ($left.Count -gt 0 -and -not $DryRun) { Say 'WARN' "kept $($e.path): not empty"; $warns++; continue }
                    if (-not $DryRun) { Remove-Item -LiteralPath $e.path -Force }
                    Say $prefix "folder    removed  $($e.path)"
                }
                $null = $done.Add($i)
            }
            'registry' {
                if (-not $DryRun) {
                    if ($e.before.exists) { Set-DeskReg $ctx $e.path $e.name ([string]$e.before.value) } else { Remove-DeskReg $ctx $e.path $e.name }
                }
                Say $prefix ("{0,-9} registry {1}\{2} -> {3}" -f $e.phase, $e.path, $e.name, $(if ($e.before.exists) { $e.before.value } else { '(removed)' }))
                $null = $done.Add($i)
            }
            'rmini' {
                if (-not $DryRun) {
                    if ($e.existed) {
                        if (-not $ctx.Test -and (Test-RainmeterRunning) -and $ctx.RainmeterExe) {
                            $tmp = Join-Path $ctx.RmSettings 'Layouts\deskforge-restore'
                            New-Item -ItemType Directory -Force $tmp | Out-Null
                            Copy-Item -LiteralPath $e.backup (Join-Path $tmp 'Rainmeter.ini') -Force
                            & $ctx.RainmeterExe '!LoadLayout' 'deskforge-restore'
                            Start-Sleep -Seconds 2
                            Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
                        }
                        else { Copy-Item -LiteralPath $e.backup $e.path -Force }
                    }
                    elseif (Test-Path -LiteralPath $e.path) { Remove-Item -LiteralPath $e.path -Force }
                }
                Say $prefix "skins     Rainmeter.ini put back from $(if ($e.existed) { $e.backup } else { '(none: removed)' })"
                $null = $done.Add($i)
            }
        }
    }

    if (-not $ctx.Test -and -not $DryRun -and ($Phase -eq 'all' -or $Phase -eq 'wallpaper')) {
        $wp = Get-DeskReg $ctx 'HKCU:\Control Panel\Desktop' 'WallPaper'
        if ($wp.exists) { $null = Set-DeskWallpaper $wp.value; Say 'DONE' 'wallpaper re-applied from the restored value' }
    }

    if (-not $DryRun) {
        $left = @(); for ($i = 0; $i -lt $all.Count; $i++) { if (-not $done.Contains($i)) { $left += $all[$i] } }
        if ($Phase -eq 'all' -and $warns -eq 0) {
            $dest = Join-Path $log.backup ('install-log.restored-{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
            Move-Item -LiteralPath $ctx.LogPath $dest
            Say 'DONE' "log moved to $dest"
        }
        else {
            $log.entries = $left
            Write-DeskText $ctx.LogPath ($log | ConvertTo-Json -Depth 6)
            Say 'INFO' "$($left.Count) entr$(if ($left.Count -eq 1) { 'y' } else { 'ies' }) left in install-log.json"
        }
    }
    Say 'INFO' $(if ($warns) { "restore finished with $warns warning(s)" } else { 'restore finished' })
    exit 0
}
catch {
    Say 'ERROR' $_.Exception.Message
    exit 1
}
