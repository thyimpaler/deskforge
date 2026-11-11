<#
.SYNOPSIS
  Privacy and secret scan for the whole repo tree, archive contents and the git log.
.DESCRIPTION
  1. Text patterns in every tracked-or-not file (except .git and the owner-only list itself):
     user-profile paths, key/secret assignments, private key blocks, chat workspace URLs, support-desk
     hosts, and any email address.
  2. Secret token shapes (cloud keys, GitHub tokens, chat tokens, API keys).
  3. The same checks inside every .zip and .rmskin archive.
  4. Owner-only banned terms from tests/privacy/banned-terms.local.txt (gitignored, one regex per line).
     If the file is missing this part is skipped and the scan says so.
  5. The git log (messages only). Author and committer fields are checked by tests/author-check.ps1.
  Some patterns are assembled from pieces so this file does not match itself.
  Exit code 1 when anything is found.
#>
[CmdletBinding()]
param([string]$Root = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$allowEmail = @('@users.noreply.github.com', 'noreply@anthropic.com', '@example.com', '@example.org')
$generic = @(
    @{ n = 'user profile path'; p = '(?i)[a-z]:\\' + 'users\\' },
    @{ n = 'key assignment';    p = '(?i)\bapi[_-]?key\s*[:=]\s*["'']?[A-Za-z0-9_\-]{8,}' },
    @{ n = 'secret assignment'; p = '(?i)\b(client_)?secret\s*[:=]\s*["'']?[A-Za-z0-9_\-]{8,}' },
    @{ n = 'private key block'; p = '-----BEGIN [A-Z ]*' + 'PRIVATE KEY-----' },
    @{ n = 'chat workspace url'; p = '(?i)disc' + 'ord(app)?\.com/channels' },
    @{ n = 'support desk host'; p = '(?i)help' + 'crunch' },
    @{ n = 'email address';     p = '(?i)[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}' }
)
$secrets = @(
    @{ n = 'cloud access key';  p = 'AKIA[0-9A-Z]{16}' },
    @{ n = 'github token';      p = '(gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{20,})' },
    @{ n = 'chat bot token';    p = 'xox[abprs]-[A-Za-z0-9\-]{10,}' },
    @{ n = 'google api key';    p = 'AIza[0-9A-Za-z_\-]{35}' },
    @{ n = 'sk- style key';     p = '\bsk-[A-Za-z0-9_\-]{20,}' },
    @{ n = 'bearer token';      p = '(?i)bearer\s+[A-Za-z0-9\-_\.=]{20,}' },
    @{ n = 'hex private key';   p = '(?i)\b(priv(ate)?[_-]?key)\s*[:=]\s*["'']?(0x)?[0-9a-f]{64}' }
)
$bannedFile = Join-Path $Root 'tests\privacy\banned-terms.local.txt'
$banned = @()
if (Test-Path $bannedFile) {
    $banned = Get-Content $bannedFile | Where-Object { $_ -and -not $_.StartsWith('#') } |
        ForEach-Object { @{ n = 'banned term'; p = $_ } }
}

$textExt = '.ps1', '.psm1', '.psd1', '.ini', '.inc', '.cs', '.json', '.md', '.txt', '.html', '.css', '.js', '.mjs', '.yml', '.yaml', '.gitignore', '.gitattributes', '.svg', '.xml', '.wsb', ''
$hits = New-Object System.Collections.Generic.List[string]

function Test-Text([string]$label, [string]$text) {
    $lines = $text -split "`n"
    for ($i = 0; $i -lt $lines.Length; $i++) {
        $line = $lines[$i]
        foreach ($rule in ($generic + $secrets + $banned)) {
            foreach ($m in [regex]::Matches($line, $rule.p)) {
                if ($rule.n -eq 'email address') {
                    $ok = $false
                    foreach ($a in $allowEmail) { if ($m.Value.ToLower().EndsWith($a)) { $ok = $true } }
                    if ($ok) { continue }
                }
                $script:hits.Add(('{0}:{1}  [{2}]  {3}' -f $label, ($i + 1), $rule.n, $line.Trim()))
            }
        }
    }
}

$files = Get-ChildItem -Path $Root -Recurse -File -Force |
    Where-Object { $_.FullName -notmatch '\\\.git\\' -and $_.FullName -ne $bannedFile -and $_.FullName -notmatch '\\\.test-root\\' }
$scanned = 0; $archives = 0
foreach ($f in $files) {
    $rel = $f.FullName.Substring($Root.Length + 1)
    if ($textExt -contains $f.Extension.ToLower()) {
        Test-Text $rel ([IO.File]::ReadAllText($f.FullName)); $scanned++
    }
    elseif ('.zip', '.rmskin' -contains $f.Extension.ToLower()) {
        $archives++
        $z = [IO.Compression.ZipFile]::OpenRead($f.FullName)
        try {
            foreach ($e in $z.Entries) {
                Test-Text ("$rel!" + $e.FullName) $e.FullName
                if ($textExt -contains [IO.Path]::GetExtension($e.Name).ToLower()) {
                    $r = New-Object IO.StreamReader($e.Open()); Test-Text ("$rel!" + $e.FullName) $r.ReadToEnd(); $r.Dispose()
                }
            }
        } finally { $z.Dispose() }
    }
    # file names count too
    Test-Text "name:$rel" $rel
}

$gitScanned = $false
if (Test-Path (Join-Path $Root '.git')) {
    $log = & git -C $Root log --all --format='%H%n%B' 2>$null
    if ($LASTEXITCODE -eq 0 -and $log) { Test-Text 'git-log' ($log -join "`n"); $gitScanned = $true }
}

Write-Output ("privacy scan: {0} text files, {1} archives, banned list {2}, git log {3}" -f $scanned, $archives,
    $(if ($banned.Count) { "$($banned.Count) terms" } else { 'MISSING (skipped)' }), $(if ($gitScanned) { 'scanned' } else { 'none' }))
if ($hits.Count -gt 0) {
    $hits | ForEach-Object { Write-Output "ERROR  $_" }
    Write-Output "privacy scan: FAIL ($($hits.Count) hits)"
    exit 1
}
Write-Output 'privacy scan: PASS (0 hits)'
