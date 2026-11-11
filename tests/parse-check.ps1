<#
.SYNOPSIS
  Parses every .ps1 and .psm1 in the repo with the PowerShell parser. Any parse error fails.
#>
[CmdletBinding()]
param([string]$Root = (Split-Path -Parent $PSScriptRoot))
$files = Get-ChildItem -Recurse -File -Path $Root -Include *.ps1, *.psm1 | Where-Object { $_.FullName -notmatch '\\\.git\\' }
$bad = 0
foreach ($f in $files) {
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors)
    foreach ($e in $errors) { $bad++; Write-Output ("ERROR  {0}:{1}  {2}" -f $f.FullName.Substring($Root.Length + 1), $e.Extent.StartLineNumber, $e.Message) }
}
Write-Output ("parse check: {0} files, {1} error(s)" -f $files.Count, $bad)
if ($bad) { exit 1 }
