[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$tasks = @(
    'Mirror Backup - Online',
    'Mirror Backup - Maintenance',
    'Mirror Backup - Health',
    'Mirror Backup - Cold Boot Test',
    'Mirror Backup - Credential Test'
)
foreach ($task in $tasks) {
    Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction SilentlyContinue
}
Write-Host 'mirror-backup scheduled tasks were removed. Repositories and snapshots were not deleted.' -ForegroundColor Green
