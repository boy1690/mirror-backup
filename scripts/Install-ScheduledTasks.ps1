[CmdletBinding()]
param([string]$ConfigPath = (Join-Path $env:ProgramData 'MirrorBackup\config.psd1'))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'MirrorBackup.Common.psm1') -Force
Import-Module ScheduledTasks -ErrorAction Stop

Assert-MirrorBackupAdministrator
$config = Get-MirrorBackupConfig -ConfigPath $ConfigPath
if (-not (Test-Path -LiteralPath $config.OnlineSecret -PathType Leaf)) {
    throw 'Initialize and verify the online repository before installing tasks.'
}

$persistentTasks = [ordered]@{
    'Mirror Backup - Online' = 'Backup-Online.ps1'
    'Mirror Backup - Maintenance' = 'Maintain-Online.ps1'
    'Mirror Backup - Health' = 'Check-Health.ps1'
    'Mirror Backup - Cold Boot Test' = 'Test-Recovery.ps1'
}
$testTask = 'Mirror Backup - Credential Test'
$taskNames = @($persistentTasks.Keys) + $testTask
$existing = @(Get-ScheduledTask -TaskName $taskNames -ErrorAction SilentlyContinue)
if ($existing.Count -gt 0) {
    throw "mirror-backup tasks already exist: $($existing.TaskName -join ', ')"
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$identitySid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$credential = Get-Credential -UserName $identity -Message 'Enter the current Windows account password, not the Windows Hello PIN.'
if ($credential.UserName -ine $identity) {
    throw "The credential user must remain exactly: $identity"
}
$plainPassword = ConvertFrom-MirrorBackupSecureString -Secret $credential.Password
$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$created = New-Object System.Collections.Generic.List[string]

function New-MirrorTaskAction {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptName,
        [string]$ExtraArguments = ''
    )
    $scriptPath = Join-Path $PSScriptRoot $ScriptName
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -ConfigPath `"$ConfigPath`""
    if ($ExtraArguments) { $arguments += ' ' + $ExtraArguments }
    return New-ScheduledTaskAction -Execute $powershell -Argument $arguments -WorkingDirectory $PSScriptRoot
}

function Assert-MirrorTask {
    param(
        [Parameter(Mandatory = $true)][string]$TaskName,
        [Parameter(Mandatory = $true)][string]$ScriptName
    )
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
    if ([string]$task.Principal.LogonType -ne 'Password') { throw "$TaskName is not using Password logon." }
    if ([string]$task.Principal.RunLevel -ne 'Highest') { throw "$TaskName is not running at Highest." }
    $sid = (New-Object Security.Principal.NTAccount($task.Principal.UserId)).Translate([Security.Principal.SecurityIdentifier]).Value
    if ($sid -cne $identitySid) { throw "$TaskName is registered to an unexpected identity." }
    if ($task.Actions.Count -ne 1 -or $task.Actions[0].Execute -ine $powershell -or $task.Actions[0].Arguments -notmatch [regex]::Escape($ScriptName)) {
        throw "$TaskName action did not read back as expected."
    }
}

try {
    $backupAction = New-MirrorTaskAction -ScriptName 'Backup-Online.ps1'
    $backupTrigger = New-ScheduledTaskTrigger -Daily -At $config.BackupAt
    $backupSettings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 30) -ExecutionTimeLimit (New-TimeSpan -Hours 12)
    Register-ScheduledTask -TaskName 'Mirror Backup - Online' -Action $backupAction -Trigger $backupTrigger -Settings $backupSettings -User $identity -Password $plainPassword -RunLevel Highest -Description 'Daily encrypted, versioned online backup with a canary restore.' | Out-Null
    [void]$created.Add('Mirror Backup - Online')

    $maintenanceAction = New-MirrorTaskAction -ScriptName 'Maintain-Online.ps1'
    $maintenanceTrigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $config.MaintenanceDay -At $config.MaintenanceAt
    $maintenanceSettings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -RestartCount 2 -RestartInterval (New-TimeSpan -Hours 1) -ExecutionTimeLimit (New-TimeSpan -Hours 24)
    Register-ScheduledTask -TaskName 'Mirror Backup - Maintenance' -Action $maintenanceAction -Trigger $maintenanceTrigger -Settings $maintenanceSettings -User $identity -Password $plainPassword -RunLevel Highest -Description 'Weekly retention, prune, rotating integrity read, and canary restore.' | Out-Null
    [void]$created.Add('Mirror Backup - Maintenance')

    $healthAction = New-MirrorTaskAction -ScriptName 'Check-Health.ps1'
    $healthTriggers = @((New-ScheduledTaskTrigger -Daily -At $config.HealthAt), (New-ScheduledTaskTrigger -AtLogOn -User $identity))
    $healthSettings = New-ScheduledTaskSettingsSet -StartWhenAvailable -RestartCount 2 -RestartInterval (New-TimeSpan -Minutes 15) -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
    Register-ScheduledTask -TaskName 'Mirror Backup - Health' -Action $healthAction -Trigger $healthTriggers -Settings $healthSettings -User $identity -Password $plainPassword -RunLevel Highest -Description 'Checks online and offline backup freshness.' | Out-Null
    [void]$created.Add('Mirror Backup - Health')

    $coldBootAction = New-MirrorTaskAction -ScriptName 'Test-Recovery.ps1' -ExtraArguments '-Repository Online -UseDpapi'
    $coldBootTrigger = New-ScheduledTaskTrigger -AtStartup -RandomDelay (New-TimeSpan -Minutes 3)
    $coldBootSettings = New-ScheduledTaskSettingsSet -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 10) -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
    Register-ScheduledTask -TaskName 'Mirror Backup - Cold Boot Test' -Action $coldBootAction -Trigger $coldBootTrigger -Settings $coldBootSettings -User $identity -Password $plainPassword -RunLevel Highest -Description 'At startup, verifies Password logon, DPAPI, repository access, and canary restore.' | Out-Null
    [void]$created.Add('Mirror Backup - Cold Boot Test')

    foreach ($entry in $persistentTasks.GetEnumerator()) { Assert-MirrorTask -TaskName $entry.Key -ScriptName $entry.Value }

    $testAction = New-MirrorTaskAction -ScriptName 'Test-Recovery.ps1' -ExtraArguments '-Repository Online -UseDpapi'
    $testTrigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(30))
    Register-ScheduledTask -TaskName $testTask -Action $testAction -Trigger $testTrigger -User $identity -Password $plainPassword -RunLevel Highest -Description 'Temporary credential and restore verification.' | Out-Null
    Start-ScheduledTask -TaskName $testTask
    $deadline = (Get-Date).AddMinutes(5)
    do {
        Start-Sleep -Seconds 2
        $state = (Get-ScheduledTask -TaskName $testTask).State
    } while ($state -in @('Queued', 'Running') -and (Get-Date) -lt $deadline)
    if ($state -in @('Queued', 'Running')) { throw 'Credential test did not finish within five minutes.' }
    $result = [uint32](Get-ScheduledTaskInfo -TaskName $testTask).LastTaskResult
    if ($result -ne 0) { throw "Credential test failed with result 0x$('{0:X8}' -f $result)." }
    foreach ($entry in $persistentTasks.GetEnumerator()) { Assert-MirrorTask -TaskName $entry.Key -ScriptName $entry.Value }
    Unregister-ScheduledTask -TaskName $testTask -Confirm:$false
    Get-ScheduledTask -TaskName @($persistentTasks.Keys) | Select-Object TaskName, State
    Write-Host 'Scheduled Password logon, DPAPI access, and canary restore were verified.' -ForegroundColor Green
} catch {
    Unregister-ScheduledTask -TaskName $testTask -Confirm:$false -ErrorAction SilentlyContinue
    foreach ($taskName in $created) { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue }
    throw
} finally {
    $plainPassword = $null
}
