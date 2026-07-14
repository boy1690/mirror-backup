[CmdletBinding()]
param(
    [ValidateSet('Online', 'Offline')][string]$Repository = 'Online',
    [switch]$UseDpapi,
    [string]$ConfigPath = (Join-Path $env:ProgramData 'MirrorBackup\config.psd1')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'MirrorBackup.Common.psm1') -Force

Assert-MirrorBackupAdministrator
$config = Get-MirrorBackupConfig -ConfigPath $ConfigPath
Initialize-MirrorBackupLayout -Config $config
$lock = Enter-MirrorBackupLock -Config $config
$stagedRestic = $null
try {
    if ($Repository -eq 'Online') {
        $repositoryPath = $config.OnlineRepository
        $expectedId = $config.OnlineRepositoryId
        $tag = $config.OnlineTag
        $evidence = $config.OnlineRestore
        $kitRestic = if ($config.OnlineRecoveryKit) { Join-Path $config.OnlineRecoveryKit 'restic.exe' } else { $config.ResticPath }
        $secretPath = $config.OnlineSecret
    } else {
        Assert-MirrorBackupOfflineMedia -Config $config
        $repositoryPath = $config.OfflineRepository
        $expectedId = $config.OfflineRepositoryId
        $tag = $config.OfflineTag
        $evidence = $config.OfflineRestore
        $kitRestic = Join-Path $config.OfflineRecoveryKit 'restic.exe'
        $secretPath = $config.OfflineSecret
    }
    Wait-MirrorBackupPath -Path (Join-Path $repositoryPath 'config')
    if ($UseDpapi) {
        $secret = Get-MirrorBackupSecret -Path $secretPath
        $resticPath = $config.ResticPath
    } else {
        $secret = Read-Host "$Repository repository password from your password manager or sealed paper" -AsSecureString
        if (-not (Test-Path -LiteralPath $kitRestic -PathType Leaf)) {
            throw "Recovery-kit restic is missing: $kitRestic"
        }
        $installedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $config.ResticPath).Hash
        $kitHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $kitRestic).Hash
        if ($kitHash -cne $installedHash) {
            throw 'Recovery-kit restic does not match the trusted installed executable.'
        }
        $stagedRestic = Join-Path $config.TempRoot ('restic-recovery-' + [guid]::NewGuid().ToString('N') + '.exe')
        Copy-Item -LiteralPath $kitRestic -Destination $stagedRestic
        Set-MirrorBackupAdminOnlyAcl -Path $stagedRestic
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath $stagedRestic).Hash -cne $kitHash) {
            throw 'Staged recovery-kit restic failed SHA-256 read-back.'
        }
        $resticPath = $stagedRestic
    }
    Assert-MirrorBackupRepositoryId -Secret $secret -Repository $repositoryPath -ExpectedIdPath $expectedId -ResticPath $resticPath | Out-Null
    $snapshot = Get-MirrorBackupLatestSnapshot -Secret $secret -Repository $repositoryPath -Tag $tag -ResticPath $resticPath
    $log = New-MirrorBackupLogPath -Config $config -Prefix ('test-' + $Repository.ToLowerInvariant())
    Test-MirrorBackupCanaryRestore -Config $config -Secret $secret -Repository $repositoryPath -Tag $tag -SnapshotId $snapshot.id -EvidencePath $evidence -LogPath $log -ResticPath $resticPath
    Write-Host "$Repository recovery restored and hash-verified the canary." -ForegroundColor Green
} finally {
    if ($stagedRestic) { Remove-Item -LiteralPath $stagedRestic -Force -ErrorAction SilentlyContinue }
    $lock.Dispose()
}
