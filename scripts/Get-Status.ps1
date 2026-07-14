[CmdletBinding()]
param([string]$ConfigPath = (Join-Path $env:ProgramData 'MirrorBackup\config.psd1'))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'MirrorBackup.Common.psm1') -Force
$config = Get-MirrorBackupConfig -ConfigPath $ConfigPath

$readState = {
    param($Path)
    if (Test-Path -LiteralPath $Path -PathType Leaf) { return (Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json) }
    return $null
}
[ordered]@{
    onlineSuccess = & $readState $config.OnlineSuccess
    onlineFailure = & $readState $config.OnlineFailure
    onlineRestore = & $readState $config.OnlineRestore
    offlineSuccess = & $readState $config.OfflineSuccess
    offlineFailure = & $readState $config.OfflineFailure
    offlineRestore = & $readState $config.OfflineRestore
    maintenance = & $readState $config.MaintenanceSuccess
    healthAlert = if (Test-Path -LiteralPath $config.HealthAlert -PathType Leaf) { Get-Content -Raw -LiteralPath $config.HealthAlert } else { $null }
} | ConvertTo-Json -Depth 8
