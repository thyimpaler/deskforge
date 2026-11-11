<#
.SYNOPSIS
  Every author and committer email in the git log must be the GitHub noreply address set for this repo.
#>
[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    # Defaults to this repo's local user.email, which must itself be a GitHub noreply address.
    [string]$Expected = (& git -C (Split-Path -Parent $PSScriptRoot) config --local user.email)
)
if ($Expected -notmatch '^[0-9]+\+[A-Za-z0-9-]+@users\.noreply\.github\.com$') {
    Write-Output "ERROR  expected address '$Expected' is not a GitHub noreply address"; Write-Output 'author check: FAIL'; exit 1
}
$rows = & git -C $Root log --all --format='%h %ae %ce' 2>$null
if (-not $rows) { Write-Output 'author check: no commits yet'; exit 0 }
$bad = $rows | Where-Object { ($_ -split ' ')[1] -ne $Expected -or ($_ -split ' ')[2] -ne $Expected }
if ($bad) { $bad | ForEach-Object { Write-Output "ERROR  $_" }; Write-Output 'author check: FAIL'; exit 1 }
Write-Output "author check: PASS ($(@($rows).Count) commits, all $Expected)"
