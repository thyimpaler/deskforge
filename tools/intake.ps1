<#
.SYNOPSIS
  M1 allowlist intake: copies only the files listed in tools/intake-allowlist.json into this repo.
.DESCRIPTION
  Reads from -SourceRoot, writes only inside this repo. Never deletes, moves or edits anything in the source.
  Refuses to overwrite a file that already exists in the repo unless -Force is given.
  After copying it strips image metadata. The copied text is then scrubbed by hand and checked with
  tests/privacy-scan.ps1 before any commit.
.EXAMPLE
  .\tools\intake.ps1 -SourceRoot "$env:USERPROFILE\Documents\Rainmeter\Skins\<your config>"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$list = Get-Content -Raw (Join-Path $PSScriptRoot 'intake-allowlist.json') | ConvertFrom-Json
$src = (Resolve-Path $SourceRoot).Path

foreach ($e in $list.files) {
    $from = Join-Path $src ($e.from -replace '/', '\')
    $to = Join-Path $repo ($e.to -replace '/', '\')
    $full = [IO.Path]::GetFullPath($to)
    # The root is compared with its trailing separator, so a sibling folder whose name merely starts with the
    # repo's name (deskforge-old next to deskforge) does not count as inside it.
    $repoRoot = [IO.Path]::GetFullPath($repo).TrimEnd('\') + '\'
    $srcRoot = [IO.Path]::GetFullPath($src).TrimEnd('\') + '\'
    if (-not $full.StartsWith($repoRoot, [StringComparison]::OrdinalIgnoreCase)) { throw "refusing to write outside the repo: $($e.to)" }
    if (-not [IO.Path]::GetFullPath($from).StartsWith($srcRoot, [StringComparison]::OrdinalIgnoreCase)) { throw "refusing to read outside the source folder: $($e.from)" }
    if (-not (Test-Path -LiteralPath $from)) { Write-Output "MISSING   $($e.from)"; continue }
    if ((Test-Path -LiteralPath $to) -and -not $Force) { Write-Output "EXISTS    $($e.to) (use -Force)"; continue }
    New-Item -ItemType Directory -Force (Split-Path -Parent $to) | Out-Null
    Copy-Item -LiteralPath $from -Destination $to
    Write-Output "copied    $($e.to)"
}

& (Join-Path $PSScriptRoot 'strip-metadata.ps1') -Path $repo
