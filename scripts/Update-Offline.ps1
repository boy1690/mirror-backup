[CmdletBinding()]
param([string]$ConfigPath = (Join-Path $env:ProgramData 'MirrorBackup\config.psd1'))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'MirrorBackup.Common.psm1') -Force

Assert-MirrorBackupAdministrator
$config = Get-MirrorBackupConfig -ConfigPath $ConfigPath
Initialize-MirrorBackupLayout -Config $config
$log = New-MirrorBackupLogPath -Config $config -Prefix 'update-offline'
$lock = $null
try {
    $lock = Enter-MirrorBackupLock -Config $config
    Wait-MirrorBackupPath -Path (Join-Path $config.OfflineRepository 'config')
    Assert-MirrorBackupOfflineMedia -Config $config
    $secret = Get-MirrorBackupSecret -Path $config.OfflineSecret
    Assert-MirrorBackupRepositoryId -Secret $secret -Repository $config.OfflineRepository -ExpectedIdPath $config.OfflineRepositoryId -ResticPath $config.ResticPath | Out-Null
    $snapshot = Invoke-MirrorBackupSnapshot -Config $config -Secret $secret -Repository $config.OfflineRepository -Tag $config.OfflineTag -EvidencePath $config.OfflineRestore -LogPath $log
    $subset = Get-MirrorBackupNextSubset -CounterPath $config.OfflineCheckCounter -Total 10
    Invoke-MirrorBackupRestic -Secret $secret -Repository $config.OfflineRepository -Arguments @('check', "--read-data-subset=$subset") -ResticPath $config.ResticPath -LogPath $log
    Complete-MirrorBackupSubset -CounterPath $config.OfflineCheckCounter
    Write-MirrorBackupSuccessState -Path $config.OfflineSuccess -Snapshot $snapshot -Tag $config.OfflineTag
    Remove-Item -LiteralPath $config.OfflineFailure -Force -ErrorAction SilentlyContinue
    Write-Host "Offline backup, rotating subset $subset, and canary restore completed: $($snapshot.id)" -ForegroundColor Green
    Write-Host 'Safely eject and physically disconnect the offline drive now.' -ForegroundColor Yellow
} catch {
    Write-MirrorBackupFailureState -Path $config.OfflineFailure -Message $_.Exception.Message
    throw
} finally {
    if ($lock) { $lock.Dispose() }
}
