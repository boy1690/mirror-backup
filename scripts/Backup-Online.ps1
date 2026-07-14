[CmdletBinding()]
param([string]$ConfigPath = (Join-Path $env:ProgramData 'MirrorBackup\config.psd1'))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'MirrorBackup.Common.psm1') -Force

Assert-MirrorBackupAdministrator
$config = Get-MirrorBackupConfig -ConfigPath $ConfigPath
Initialize-MirrorBackupLayout -Config $config
$log = New-MirrorBackupLogPath -Config $config -Prefix 'backup-online'
$lock = $null
try {
    $lock = Enter-MirrorBackupLock -Config $config
    Wait-MirrorBackupPath -Path (Join-Path $config.OnlineRepository 'config')
    $secret = Get-MirrorBackupSecret -Path $config.OnlineSecret
    Assert-MirrorBackupRepositoryId -Secret $secret -Repository $config.OnlineRepository -ExpectedIdPath $config.OnlineRepositoryId -ResticPath $config.ResticPath | Out-Null
    $snapshot = Invoke-MirrorBackupSnapshot -Config $config -Secret $secret -Repository $config.OnlineRepository -Tag $config.OnlineTag -EvidencePath $config.OnlineRestore -LogPath $log
    Write-MirrorBackupSuccessState -Path $config.OnlineSuccess -Snapshot $snapshot -Tag $config.OnlineTag
    Remove-Item -LiteralPath $config.OnlineFailure -Force -ErrorAction SilentlyContinue
    Write-Host "Online backup and canary restore completed: $($snapshot.id)" -ForegroundColor Green
} catch {
    Write-MirrorBackupFailureState -Path $config.OnlineFailure -Message $_.Exception.Message
    throw
} finally {
    if ($lock) { $lock.Dispose() }
}
