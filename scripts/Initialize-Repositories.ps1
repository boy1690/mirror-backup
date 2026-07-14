[CmdletBinding()]
param(
    [switch]$Online,
    [switch]$Offline,
    [string]$ConfigPath = (Join-Path $env:ProgramData 'MirrorBackup\config.psd1')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'MirrorBackup.Common.psm1') -Force

Assert-MirrorBackupAdministrator
if (-not $Online -and -not $Offline) { throw 'Specify -Online, -Offline, or both.' }
$config = Get-MirrorBackupConfig -ConfigPath $ConfigPath
Initialize-MirrorBackupLayout -Config $config

if ($Online) {
    $repositoryConfig = Join-Path $config.OnlineRepository 'config'
    if (Test-Path -LiteralPath $repositoryConfig -PathType Leaf) {
        throw 'Online repository already exists. Initialization never overwrites a repository.'
    }
    New-Item -ItemType Directory -Path $config.OnlineRepository -Force | Out-Null
    $secret = Read-MirrorBackupConfirmedSecret -Label 'Online repository'
    Invoke-MirrorBackupRestic -Secret $secret -Repository $config.OnlineRepository -Arguments @('init') -ResticPath $config.ResticPath
    $repositoryId = Get-MirrorBackupRepositoryId -Secret $secret -Repository $config.OnlineRepository -ResticPath $config.ResticPath
    Write-MirrorBackupTextAtomic -Path $config.OnlineRepositoryId -Content $repositoryId
    Save-MirrorBackupSecret -Secret $secret -Path $config.OnlineSecret
    if ($config.OnlineRecoveryKit) {
        Copy-MirrorBackupRecoveryKit -Config $config -Destination $config.OnlineRecoveryKit
    }
    Write-Host "Online repository initialized: $repositoryId" -ForegroundColor Green
}

if ($Offline) {
    $driveRoot = [IO.Path]::GetPathRoot($config.OfflineRoot)
    if (-not (Test-Path -LiteralPath $driveRoot -PathType Container)) {
        throw "Offline drive is not connected: $driveRoot"
    }
    $repositoryConfig = Join-Path $config.OfflineRepository 'config'
    if (Test-Path -LiteralPath $repositoryConfig -PathType Leaf) {
        throw 'Offline repository already exists. Initialization never overwrites a repository.'
    }
    New-Item -ItemType Directory -Path $config.OfflineRepository -Force | Out-Null
    $secret = Read-MirrorBackupConfirmedSecret -Label 'Offline repository'
    Invoke-MirrorBackupRestic -Secret $secret -Repository $config.OfflineRepository -Arguments @('init') -ResticPath $config.ResticPath
    $repositoryId = Get-MirrorBackupRepositoryId -Secret $secret -Repository $config.OfflineRepository -ResticPath $config.ResticPath
    Write-MirrorBackupTextAtomic -Path $config.OfflineRepositoryId -Content $repositoryId
    Save-MirrorBackupSecret -Secret $secret -Path $config.OfflineSecret
    Initialize-MirrorBackupOfflineMarker -Config $config
    Copy-MirrorBackupRecoveryKit -Config $config -Destination $config.OfflineRecoveryKit
    Write-Host "Offline repository initialized: $repositoryId" -ForegroundColor Green
    Write-Host 'Record this password outside the computer, then safely eject the drive after its first update.'
}
