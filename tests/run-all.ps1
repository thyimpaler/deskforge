<#
.SYNOPSIS
  Runs the whole local suite. Never touches the real desk: install and restore run in a temp folder.
  -Ci skips the checks that need this machine's local setup (commit author config, owner-only banned list).
#>
[CmdletBinding()]
param([switch]$Ci, [switch]$SkipHelpers)
$repo = Split-Path -Parent $PSScriptRoot
$steps = @(
    @{ n = 'parse';           c = { & "$repo\tests\parse-check.ps1" } },
    @{ n = 'schema';          c = { & "$repo\tests\schema.tests.ps1" } },
    @{ n = 'items';           c = { & "$repo\tests\items.tests.ps1" } },
    @{ n = 'install-restore'; c = { & "$repo\tests\install-restore.tests.ps1" -SkipHelpers:$SkipHelpers } },
    @{ n = 'capture-apis';    c = { & "$repo\tests\capture-check.ps1" } },
    @{ n = 'metadata';        c = { & "$repo\tools\strip-metadata.ps1" -Path $repo -Check } },
    @{ n = 'site-data';       c = { & "$repo\tools\build-site-data.ps1" -Check } },
    @{ n = 'manifest';        c = { & "$repo\tools\verify.ps1" } },
    @{ n = 'privacy';         c = { & "$repo\tests\privacy-scan.ps1" } }
)
if (-not $Ci) { $steps += @{ n = 'author'; c = { & "$repo\tests\author-check.ps1" } } }
$failed = @()
foreach ($s in $steps) {
    $global:LASTEXITCODE = 0
    $out = & $s.c
    $code = $LASTEXITCODE
    $last = @($out)[-1]
    $errLines = @($out | Where-Object { $_ -match '^(ERROR|FAIL)' }).Count
    if ($code -ne 0 -or $errLines -gt 0) { $failed += $s.n; Write-Output ("FAIL  {0,-16} {1}" -f $s.n, $last); $out | Where-Object { $_ -match '^(ERROR|FAIL)' } | ForEach-Object { Write-Output "        $_" } }
    else { Write-Output ("PASS  {0,-16} {1}" -f $s.n, $last) }
}
Write-Output $(if ($failed) { "suite: FAIL ($($failed -join ', '))" } else { 'suite: PASS' })
if ($failed) { exit 1 }