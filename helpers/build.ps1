<#
.SYNOPSIS
  Compiles the deskforge helpers with the csc that ships with Windows (.NET Framework 4). Fails on any warning.
.EXAMPLE
  .\helpers\build.ps1 -OutDir .\build
  .\helpers\build.ps1 -Only dock -OutDir "$env:TEMP\df"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$OutDir,
    [ValidateSet('dock', 'nowplaying', 'market')][string[]]$Only = @('dock', 'nowplaying', 'market')
)
$ErrorActionPreference = 'Stop'
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
if (-not (Test-Path $csc)) { Write-Output 'ERROR csc.exe not found (it ships with .NET Framework 4)'; exit 1 }
$refs = @{
    dock       = @('/r:System.Management.dll', '/r:System.Windows.Forms.dll', '/r:System.Drawing.dll')
    nowplaying = @()
    market     = @()
}
New-Item -ItemType Directory -Force $OutDir | Out-Null
$fail = 0
foreach ($n in $Only) {
    $src = Join-Path $PSScriptRoot "$n.cs"
    $out = Join-Path $OutDir "$n.exe"
    $cargs = @('/nologo', '/target:winexe', '/optimize+', '/warn:4', '/warnaserror+', "/out:$out") + $refs[$n] + @($src)
    $text = & $csc @cargs 2>&1
    if ($LASTEXITCODE -ne 0) { $fail++; Write-Output "ERROR build $n failed"; $text | ForEach-Object { Write-Output "      $_" } }
    else { Write-Output "built $out" }
}
if ($fail) { exit 1 }
exit 0
