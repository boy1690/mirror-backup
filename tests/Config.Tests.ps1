[CmdletBinding()]
param([string]$Root)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Split-Path $PSScriptRoot -Parent }
$module = Join-Path $Root 'scripts\MirrorBackup.Common.psm1'
Import-Module $module -Force

$temporary = Join-Path $env:TEMP ('mirror-backup-config-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporary | Out-Null
try {
    $configPath = Join-Path $temporary 'config.psd1'
    @'
@{
    SchemaVersion = 1
    ResticPath = 'C:\Tools\restic.exe'
    OnlineRepository = '\\nas.example.test\backup\mirror-backup'
    OnlineRecoveryKit = ''
    OfflineRoot = 'E:\MirrorBackup'
    Sources = @('C:\Data')
    Excludes = @('**\cache\**')
    OnlineTag = 'test-online'
    OfflineTag = 'test-offline'
    Retention = @{}
    Schedule = @{}
}
'@ | Set-Content -LiteralPath $configPath -Encoding UTF8
    $config = Get-MirrorBackupConfig -ConfigPath $configPath
    if ($config.OfflineRepository -cne 'E:\MirrorBackup\repository') { throw 'Offline repository derivation failed.' }
    if ($config.OnlineTag -cne 'test-online' -or $config.KeepDaily -ne 14 -or $config.BackupAt -cne '02:15') { throw 'Defaults or explicit values failed.' }
    if ($config.Sources.Count -ne 1 -or $config.Sources[0] -cne 'C:\Data') { throw 'Sources failed.' }

    $availableSource = Join-Path $temporary 'available-source'
    New-Item -ItemType Directory -Path $availableSource | Out-Null
    $sourceConfig = [pscustomobject]@{ Sources = @($availableSource) }
    Assert-MirrorBackupSourcesAvailable -Config $sourceConfig
    $sourceConfig.Sources = @((Join-Path $temporary 'missing-source'))
    $missingRejected = $false
    try { Assert-MirrorBackupSourcesAvailable -Config $sourceConfig } catch { $missingRejected = $true }
    if (-not $missingRejected) { throw 'Unavailable source was not rejected.' }

    $invalidPath = Join-Path $temporary 'invalid.psd1'
    (Get-Content -Raw -LiteralPath $configPath).Replace("'C:\Data'", "'C:\Users\<USER>\Documents'") | Set-Content -LiteralPath $invalidPath -Encoding UTF8
    $placeholderRejected = $false
    try { Get-MirrorBackupConfig -ConfigPath $invalidPath | Out-Null } catch { $placeholderRejected = $true }
    if (-not $placeholderRejected) { throw 'Placeholder configuration was not rejected.' }

    $fakeRestic = Join-Path $temporary 'fake-restic.cmd'
    "@echo off`r`necho {`"id`":`"test-repository-id`"}`r`nexit /b 0" | Set-Content -LiteralPath $fakeRestic -Encoding Ascii
    $secret = ConvertTo-SecureString 'test-only-password-longer-than-twenty' -AsPlainText -Force
    $env:RESTIC_REPOSITORY = 'sentinel-repository'
    $env:RESTIC_PASSWORD = 'sentinel-password'
    $repositoryId = Get-MirrorBackupRepositoryId -Secret $secret -Repository 'test-repository' -ResticPath $fakeRestic
    if ($repositoryId -cne 'test-repository-id') { throw 'Repository ID capture failed.' }
    if ($env:RESTIC_REPOSITORY -cne 'sentinel-repository' -or $env:RESTIC_PASSWORD -cne 'sentinel-password') {
        throw 'restic environment was not restored.'
    }
    Write-Host 'CONFIG_PASS' -ForegroundColor Green
} finally {
    $env:RESTIC_REPOSITORY = $null
    $env:RESTIC_PASSWORD = $null
    Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
}
