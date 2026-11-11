<#
.SYNOPSIS
  Writes or checks tools/build-manifest.json: every shipped skin, addon, theme, helper and tool file, the shared
  module (tools/lib), the helper build script and every file under tests/, each with its SHA-256. -Write regenerates it. Without -Write it checks the files still match and exits 1 if not.
#>
[CmdletBinding()]
param([switch]$Write)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$out = Join-Path $repo 'tools\build-manifest.json'
function Get-Group([string]$dir) {
    Get-ChildItem -Directory (Join-Path $repo $dir) | Sort-Object Name | ForEach-Object {
        $d = $_
        [ordered]@{ name = $d.Name; folder = "$dir/$($d.Name)/"; files = @(Get-ChildItem -File $d.FullName | Sort-Object Name | ForEach-Object {
            [ordered]@{ path = "$dir/$($d.Name)/$($_.Name)"; sha256 = (Get-FileHash -Algorithm SHA256 $_.FullName).Hash.ToLower() } }) }
    }
}
function Get-Flat([string]$dir, [string]$filter) {
    @(Get-ChildItem -File (Join-Path $repo $dir) -Filter $filter | Sort-Object Name | ForEach-Object {
        [ordered]@{ path = "$dir/$($_.Name)"; sha256 = (Get-FileHash -Algorithm SHA256 $_.FullName).Hash.ToLower() } })
}
# Every file under a folder, sub-folders included. Owner-only *.local.txt files are never committed, so they are left out.
function Get-Tree([string]$dir) {
    $base = (Join-Path $repo $dir).TrimEnd('\') + '\'
    $rels = [string[]]@(Get-ChildItem -File -Recurse $base | Where-Object { $_.Name -notlike '*.local.txt' } |
        ForEach-Object { $_.FullName.Substring($base.Length) -replace '\\', '/' })
    [Array]::Sort($rels, [StringComparer]::Ordinal)
    @($rels | ForEach-Object { [ordered]@{ path = "$dir/$_"; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $base $_)).Hash.ToLower() } })
}
$m = [ordered]@{
    skins = @(Get-Group 'skins'); addons = @(Get-Group 'addons'); themes = @(Get-Group 'themes')
    helpers = @((Get-Flat 'helpers' '*.cs') + (Get-Flat 'helpers' '*.ps1'))
    tools = @(Get-Flat 'tools' '*.ps1')
    lib = @(Get-Flat 'tools/lib' '*.psm1')
    tests = @(Get-Tree 'tests')
}
$text = (($m | ConvertTo-Json -Depth 6) -replace "`r`n", "`n") + "`n"
if ($Write) { [IO.File]::WriteAllText($out, $text, (New-Object Text.UTF8Encoding($false))); Write-Output 'wrote tools/build-manifest.json'; exit 0 }
$cur = if (Test-Path $out) { [IO.File]::ReadAllText($out) } else { '' }
if ($cur -ne $text) { Write-Output 'ERROR  tools/build-manifest.json does not match the files: run tools\verify.ps1 -Write'; exit 1 }
Write-Output 'manifest: matches'