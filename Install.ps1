[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ResticPath,
    [string]$ConfigPath,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run Install.ps1 from an elevated Windows PowerShell session.'
}

$sourceRoot = $PSScriptRoot
$installRoot = Join-Path $env:ProgramFiles 'MirrorBackup'
$dataRoot = Join-Path $env:ProgramData 'MirrorBackup'
$installedConfig = Join-Path $dataRoot 'config.psd1'
if (-not (Test-Path -LiteralPath $ResticPath -PathType Leaf)) { throw "restic.exe is missing: $ResticPath" }
if (Test-Path -LiteralPath $installRoot -PathType Container -and -not $Force) {
    throw "Installation exists: $installRoot. Use -Force only for an intentional code update."
}

New-Item -ItemType Directory -Path $installRoot, (Join-Path $installRoot 'scripts'), (Join-Path $installRoot 'docs'), (Join-Path $installRoot 'bin'), $dataRoot -Force | Out-Null
foreach ($item in Get-ChildItem -LiteralPath (Join-Path $sourceRoot 'scripts') -Force) {
    Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $installRoot 'scripts') -Recurse -Force
}
foreach ($item in Get-ChildItem -LiteralPath (Join-Path $sourceRoot 'docs') -Force) {
    Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $installRoot 'docs') -Recurse -Force
}
Copy-Item -LiteralPath $ResticPath -Destination (Join-Path $installRoot 'bin\restic.exe') -Force

if ($ConfigPath) {
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { throw "Configuration file is missing: $ConfigPath" }
    Copy-Item -LiteralPath $ConfigPath -Destination $installedConfig -Force
} elseif (-not (Test-Path -LiteralPath $installedConfig -PathType Leaf)) {
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'config\mirror-backup.example.psd1') -Destination $installedConfig
}

$modulePath = Join-Path $installRoot 'scripts\MirrorBackup.Common.psm1'
Import-Module $modulePath -Force
foreach ($path in @($installRoot, $dataRoot)) {
    Set-MirrorBackupAdminOnlyAcl -Path $path
    Get-ChildItem -LiteralPath $path -Recurse -Force | ForEach-Object { Set-MirrorBackupAdminOnlyAcl -Path $_.FullName }
}

[pscustomobject]@{
    installRoot = $installRoot
    configPath = $installedConfig
    resticSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $installRoot 'bin\restic.exe')).Hash
    next = 'Edit config.psd1, then run scripts\Initialize-Repositories.ps1.'
} | ConvertTo-Json
