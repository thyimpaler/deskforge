<#
.SYNOPSIS
  Removes metadata (EXIF, text chunks, timestamps) from PNG and JPEG files, in place.
.DESCRIPTION
  PNG: keeps only IHDR, PLTE, tRNS, gAMA, cHRM, sRGB, IDAT and IEND. Drops eXIf, tEXt, zTXt, iTXt, tIME and the rest.
  JPEG: drops APP1..APP15 (EXIF, XMP, ICC, vendor data) and COM segments. Keeps APP0 (JFIF) and image data.
  -Check reports files that still carry metadata and exits 1 if any do. It writes nothing.
.EXAMPLE
  .\tools\strip-metadata.ps1 -Path . -Check
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Path,
    [switch]$Check
)

$ErrorActionPreference = 'Stop'
$pngSig = [byte[]](0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
$keepPng = @('IHDR', 'PLTE', 'tRNS', 'gAMA', 'cHRM', 'sRGB', 'IDAT', 'IEND')

function Read-BE32([byte[]]$b, [int]$o) {
    return ([int64]$b[$o] -shl 24) -bor ([int64]$b[$o + 1] -shl 16) -bor ([int64]$b[$o + 2] -shl 8) -bor [int64]$b[$o + 3]
}

function Get-PngClean([byte[]]$bytes, [ref]$dirty) {
    for ($i = 0; $i -lt 8; $i++) { if ($bytes[$i] -ne $pngSig[$i]) { throw 'not a PNG' } }
    $out = New-Object System.IO.MemoryStream
    $out.Write($bytes, 0, 8)
    $o = 8
    while ($o -lt $bytes.Length) {
        $len = [int](Read-BE32 $bytes $o)
        $type = [Text.Encoding]::ASCII.GetString($bytes, $o + 4, 4)
        $total = 12 + $len
        if ($keepPng -contains $type) { $out.Write($bytes, $o, $total) } else { $dirty.Value = $true }
        $o += $total
        if ($type -eq 'IEND') { break }
    }
    return $out.ToArray()
}

function Get-JpegClean([byte[]]$bytes, [ref]$dirty) {
    if ($bytes[0] -ne 0xFF -or $bytes[1] -ne 0xD8) { throw 'not a JPEG' }
    $out = New-Object System.IO.MemoryStream
    $out.WriteByte(0xFF); $out.WriteByte(0xD8)
    $o = 2
    while ($o -lt $bytes.Length - 1) {
        if ($bytes[$o] -ne 0xFF) { throw 'bad JPEG marker' }
        $m = $bytes[$o + 1]
        if ($m -eq 0xDA) { $out.Write($bytes, $o, $bytes.Length - $o); break }   # start of scan: copy the rest
        $len = ([int]$bytes[$o + 2] -shl 8) -bor [int]$bytes[$o + 3]
        $isApp = ($m -ge 0xE1 -and $m -le 0xEF)
        if ($isApp -or $m -eq 0xFE) { $dirty.Value = $true } else { $out.Write($bytes, $o, $len + 2) }
        $o += $len + 2
    }
    return $out.ToArray()
}

$files = Get-ChildItem -Path $Path -Recurse -File -Include *.png, *.jpg, *.jpeg |
    Where-Object { $_.FullName -notmatch '\\\.git\\' }
$bad = @()
foreach ($f in $files) {
    $bytes = [IO.File]::ReadAllBytes($f.FullName)
    $dirty = $false
    if ($f.Extension -ieq '.png') { $clean = Get-PngClean $bytes ([ref]$dirty) } else { $clean = Get-JpegClean $bytes ([ref]$dirty) }
    if ($dirty) {
        if ($Check) { $bad += $f.FullName }
        else { [IO.File]::WriteAllBytes($f.FullName, $clean); Write-Output "stripped  $($f.FullName)" }
    }
}
if ($Check) {
    if ($bad.Count -gt 0) { $bad | ForEach-Object { Write-Output "METADATA  $_" }; exit 1 }
    Write-Output "metadata check: $($files.Count) image(s), all clean"
}
