[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$Root)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$resolvedRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\')
if (-not (Test-Path -LiteralPath $resolvedRoot -PathType Container)) { throw "Scan root is missing: $resolvedRoot" }

$patterns = [ordered]@{
    'Windows user path' = 'C:\\Users\\(?!<USER>\\)[^\\\s''"`]+\\'
    'Email address' = '(?i)\b[A-Z0-9._%+-]+@(?!example\.com\b)[A-Z0-9.-]+\.[A-Z]{2,}\b'
    'Private IPv4' = '\b(?:10\.(?:\d{1,3}\.){2}\d{1,3}|192\.168\.(?:\d{1,3}\.)\d{1,3}|172\.(?:1[6-9]|2\d|3[01])\.(?:\d{1,3}\.)\d{1,3})\b'
    'MAC address' = '(?i)\b(?:[0-9A-F]{2}[:-]){5}[0-9A-F]{2}\b'
    'OOBE machine name' = '\bWIN-[A-Z0-9]{8,15}\b'
    'GitHub token' = '\bgh[pousr]_[A-Za-z0-9_]{20,}\b'
    'Generic API secret' = '(?i)\b(?:sk|api)[-_][A-Za-z0-9_-]{20,}\b'
    'Bearer token' = '(?i)\bBearer\s+[A-Za-z0-9._~+/-]{20,}={0,2}\b'
    'BitLocker recovery key' = '\b\d{6}(?:-\d{6}){7}\b'
    'Literal GUID' = '(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b'
}

$extensions = @('.ps1', '.psm1', '.psd1', '.md', '.yml', '.yaml', '.json', '.txt', '.gitignore')
$findings = New-Object System.Collections.Generic.List[object]
$files = Get-ChildItem -LiteralPath $resolvedRoot -File -Recurse -Force | Where-Object {
    $_.FullName -notmatch '[\\/]\.git[\\/]' -and $extensions -contains $_.Extension.ToLowerInvariant()
}
foreach ($file in $files) {
    $lines = Get-Content -LiteralPath $file.FullName
    for ($index = 0; $index -lt $lines.Count; $index++) {
        foreach ($entry in $patterns.GetEnumerator()) {
            if ($lines[$index] -match $entry.Value) {
                [void]$findings.Add([pscustomobject]@{
                    rule = $entry.Key
                    file = $file.FullName.Substring($resolvedRoot.Length + 1)
                    line = $index + 1
                })
            }
        }
    }
}

if ($findings.Count -gt 0) {
    $findings | Sort-Object file, line, rule | Format-Table -AutoSize
    Write-Error "RESULT=BLOCKED findings=$($findings.Count)"
    exit 1
}
Write-Host "RESULT=CLEAN files=$($files.Count)" -ForegroundColor Green
