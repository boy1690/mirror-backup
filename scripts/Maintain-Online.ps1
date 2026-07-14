[CmdletBinding()]
param([string]$ConfigPath = (Join-Path $env:ProgramData 'MirrorBackup\config.psd1'))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'MirrorBackup.Common.psm1') -Force

Assert-MirrorBackupAdministrator
$config = Get-MirrorBackupConfig -ConfigPath $ConfigPath
Initialize-MirrorBackupLayout -Config $config
$log = New-MirrorBackupLogPath -Config $config -Prefix 'maintain-online'
$lock = $null
try {
    $lock = Enter-MirrorBackupLock -Config $config
    Wait-MirrorBackupPath -Path (Join-Path $config.OnlineRepository 'config')
    $secret = Get-MirrorBackupSecret -Path $config.OnlineSecret
    Assert-MirrorBackupRepositoryId -Secret $secret -Repository $config.OnlineRepository -ExpectedIdPath $config.OnlineRepositoryId -ResticPath $config.ResticPath | Out-Null
    Invoke-MirrorBackupRestic -Secret $secret -Repository $config.OnlineRepository -Arguments @(
        'forget', '--host', $env:COMPUTERNAME, '--tag', $config.OnlineTag,
        '--keep-last', [string]$config.KeepLast,
        '--keep-daily', [string]$config.KeepDaily,
        '--keep-weekly', [string]$config.KeepWeekly,
        '--keep-monthly', [string]$config.KeepMonthly,
        '--keep-yearly', [string]$config.KeepYearly,
        '--prune'
    ) -ResticPath $config.ResticPath -LogPath $log
    $subset = Get-MirrorBackupNextSubset -CounterPath $config.OnlineCheckCounter -Total 20
    Invoke-MirrorBackupRestic -Secret $secret -Repository $config.OnlineRepository -Arguments @('check', "--read-data-subset=$subset") -ResticPath $config.ResticPath -LogPath $log
    Complete-MirrorBackupSubset -CounterPath $config.OnlineCheckCounter
    $snapshot = Get-MirrorBackupLatestSnapshot -Secret $secret -Repository $config.OnlineRepository -Tag $config.OnlineTag -ResticPath $config.ResticPath
    Test-MirrorBackupCanaryRestore -Config $config -Secret $secret -Repository $config.OnlineRepository -Tag $config.OnlineTag -SnapshotId $snapshot.id -EvidencePath $config.OnlineRestore -LogPath $log
    Write-MirrorBackupTextAtomic -Path $config.MaintenanceSuccess -Content (([ordered]@{
        completedUtc = [DateTime]::UtcNow.ToString('o')
        checkedSubset = $subset
        snapshotId = [string]$snapshot.id
    }) | ConvertTo-Json -Depth 3)
    Remove-Item -LiteralPath $config.MaintenanceFailure -Force -ErrorAction SilentlyContinue
    Write-Host "Online maintenance completed; verified rotating data subset $subset." -ForegroundColor Green
} catch {
    Write-MirrorBackupFailureState -Path $config.MaintenanceFailure -Message $_.Exception.Message
    throw
} finally {
    if ($lock) { $lock.Dispose() }
}
