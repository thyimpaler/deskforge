<#
.SYNOPSIS
  desk.json schema tests: every fixture in tests/fixtures is checked with the PowerShell validator that
  install.ps1 uses. Valid fixtures must pass; invalid ones must fail and name the field in the error.
  The example config must pass too. tests/site.test.mjs runs the same fixtures through the site's validator.
#>
[CmdletBinding()]
param()
$repo = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repo 'tools\lib\deskforge.psm1') -Force
$fails = 0
function Check([string]$name, [bool]$ok, [string]$detail = '') { if ($ok) { Write-Output "PASS  $name" } else { Write-Output "FAIL  $name $detail"; $script:fails++ } }

$ex = Get-Content -Raw (Join-Path $repo 'config\desk.example.json') | ConvertFrom-Json
$e = Test-DeskConfig -Config $ex
Check 'config/desk.example.json is valid' ($e.Count -eq 0) ($e -join '; ')

$schema = Get-Content -Raw (Join-Path $repo 'config\desk.schema.json') | ConvertFrom-Json
Check 'schema rejects unknown fields at the top' ($schema.additionalProperties -eq $false)

foreach ($f in Get-ChildItem (Join-Path $repo 'tests\fixtures') -Filter *.json) {
    $fx = Get-Content -Raw -Encoding UTF8 $f.FullName | ConvertFrom-Json
    $errs = Test-DeskConfig -Config $fx.config
    if ($fx.expect -eq 'valid') { Check "$($f.BaseName)" ($errs.Count -eq 0) ($errs -join '; ') }
    else { Check "$($f.BaseName)" (($errs.Count -gt 0) -and (($errs -join ' ') -like "*$($fx.mustMention)*")) ("got: " + ($errs -join '; ')) }
}
Write-Output $(if ($fails) { "schema: FAIL ($fails)" } else { 'schema: PASS' })
if ($fails) { exit 1 }
