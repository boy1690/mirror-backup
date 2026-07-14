[CmdletBinding()]
param([string]$Root)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Split-Path $PSScriptRoot -Parent }
$errors = New-Object System.Collections.Generic.List[object]
$files = Get-ChildItem -LiteralPath $Root -File -Recurse | Where-Object { $_.Extension -in @('.ps1', '.psm1', '.psd1') }
foreach ($file in $files) {
    $tokens = $null
    $parseErrors = $null
    [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
    foreach ($parseError in @($parseErrors)) {
        [void]$errors.Add([pscustomobject]@{ file = $file.FullName; message = $parseError.Message })
    }
}
if ($errors.Count -gt 0) {
    $errors | Format-Table -AutoSize
    throw "PowerShell parser errors: $($errors.Count)"
}
Write-Host "PARSE_PASS files=$($files.Count)" -ForegroundColor Green
