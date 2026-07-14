[CmdletBinding()]
param([string]$ConfigPath = (Join-Path $env:ProgramData 'MirrorBackup\config.psd1'))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'MirrorBackup.Common.psm1') -Force

$config = Get-MirrorBackupConfig -ConfigPath $ConfigPath
$message = $null
if (-not (Test-Path -LiteralPath $config.OnlineSuccess -PathType Leaf)) {
    $message = 'No successful online backup has been recorded.'
} else {
    $online = Get-Content -Raw -LiteralPath $config.OnlineSuccess | ConvertFrom-Json
    $onlineAge = [DateTime]::UtcNow - [DateTime]::Parse([string]$online.completedUtc).ToUniversalTime()
    if ($onlineAge.TotalHours -gt 36) { $message = "Online backup is stale: $([math]::Round($onlineAge.TotalHours, 1)) hours." }
    if (-not $message -and (Test-Path -LiteralPath $config.MaintenanceFailure -PathType Leaf)) {
        $failure = Get-Content -Raw -LiteralPath $config.MaintenanceFailure | ConvertFrom-Json
        $message = "Online maintenance failed at $($failure.failedUtc): $($failure.message)"
    }
    if (-not $message -and (Test-Path -LiteralPath $config.MaintenanceSuccess -PathType Leaf)) {
        $maintenance = Get-Content -Raw -LiteralPath $config.MaintenanceSuccess | ConvertFrom-Json
        $age = [DateTime]::UtcNow - [DateTime]::Parse([string]$maintenance.completedUtc).ToUniversalTime()
        if ($age.TotalDays -gt 9) { $message = "Online maintenance is stale: $([math]::Round($age.TotalDays, 1)) days." }
    }
    if (-not $message -and -not (Test-Path -LiteralPath $config.OfflineSuccess -PathType Leaf)) {
        $message = 'No successful offline backup has been recorded.'
    }
    if (-not $message -and (Test-Path -LiteralPath $config.OfflineFailure -PathType Leaf)) {
        $failure = Get-Content -Raw -LiteralPath $config.OfflineFailure | ConvertFrom-Json
        $message = "Offline backup failed at $($failure.failedUtc): $($failure.message)"
    }
    if (-not $message -and (Test-Path -LiteralPath $config.OfflineSuccess -PathType Leaf)) {
        $offline = Get-Content -Raw -LiteralPath $config.OfflineSuccess | ConvertFrom-Json
        $age = [DateTime]::UtcNow - [DateTime]::Parse([string]$offline.completedUtc).ToUniversalTime()
        if ($age.TotalDays -gt 35) { $message = "Offline backup is stale: $([math]::Round($age.TotalDays, 1)) days." }
    }
}

if ($message) {
    Write-MirrorBackupTextAtomic -Path $config.HealthAlert -Content $message
    Write-Warning $message
    exit 2
}
Remove-Item -LiteralPath $config.HealthAlert -Force -ErrorAction SilentlyContinue
Write-Host 'mirror-backup health is good.' -ForegroundColor Green
