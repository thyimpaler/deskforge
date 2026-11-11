<#
.SYNOPSIS
  Fails if any code file in the repo refers to a camera or video capture API. deskforge has no camera features.
#>
[CmdletBinding()]
param([string]$Root = (Split-Path -Parent $PSScriptRoot))
$p = '(?i)(web' + 'cam|cam' + 'era|video' + 'capture|media' + 'capture|\bcv2\b|avicap|capCreate' + 'CaptureWindow|getUser' + 'Media|hand_land' + 'marker)'
$files = Get-ChildItem -Recurse -File -Path $Root -Include *.cs, *.ps1, *.psm1, *.ini, *.inc, *.js, *.html, *.py, *.yml |
    Where-Object { $_.FullName -notmatch '\\\.git\\' -and $_.FullName -ne $PSCommandPath }
$hits = @($files | Select-String -Pattern $p)
foreach ($h in $hits) { Write-Output ("ERROR  {0}:{1}  {2}" -f $h.Path.Substring($Root.Length + 1), $h.LineNumber, $h.Line.Trim()) }
Write-Output ("capture-api check: {0} code files, {1} hit(s)" -f $files.Count, $hits.Count)
if ($hits.Count) { exit 1 }