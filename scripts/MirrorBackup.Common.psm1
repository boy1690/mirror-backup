Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:DefaultConfigPath = Join-Path $env:ProgramData 'MirrorBackup\config.psd1'

function Test-MirrorBackupAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-MirrorBackupAdministrator {
    if (-not (Test-MirrorBackupAdministrator)) {
        throw 'Run this command from an elevated Windows PowerShell session.'
    }
}

function Assert-MirrorBackupNoReparsePoint {
    param([Parameter(Mandatory = $true)][string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Reparse points are not allowed for protected paths: $Path"
    }
}

function Set-MirrorBackupAdminOnlyAcl {
    param([Parameter(Mandatory = $true)][string]$Path)

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    $administrators = New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')
    $system = New-Object Security.Principal.SecurityIdentifier('S-1-5-18')
    if ($item.PSIsContainer) {
        $acl = New-Object Security.AccessControl.DirectorySecurity
        $inheritance = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
        $propagation = [Security.AccessControl.PropagationFlags]::None
        foreach ($sid in @($administrators, $system)) {
            $rule = New-Object Security.AccessControl.FileSystemAccessRule(
                $sid,
                [Security.AccessControl.FileSystemRights]::FullControl,
                $inheritance,
                $propagation,
                [Security.AccessControl.AccessControlType]::Allow
            )
            [void]$acl.AddAccessRule($rule)
        }
    } else {
        $acl = New-Object Security.AccessControl.FileSecurity
        foreach ($sid in @($administrators, $system)) {
            $rule = New-Object Security.AccessControl.FileSystemAccessRule(
                $sid,
                [Security.AccessControl.FileSystemRights]::FullControl,
                [Security.AccessControl.AccessControlType]::Allow
            )
            [void]$acl.AddAccessRule($rule)
        }
    }
    $acl.SetOwner($administrators)
    $acl.SetAccessRuleProtection($true, $false)
    Set-Acl -LiteralPath $Path -AclObject $acl
    Assert-MirrorBackupNoReparsePoint -Path $Path
}

function Resolve-MirrorBackupValue {
    param([Parameter(Mandatory = $true)][string]$Value)
    return [Environment]::ExpandEnvironmentVariables($Value)
}

function Get-MirrorBackupConfig {
    param([string]$ConfigPath = $script:DefaultConfigPath)

    $resolvedConfigPath = [IO.Path]::GetFullPath((Resolve-MirrorBackupValue -Value $ConfigPath))
    if (-not (Test-Path -LiteralPath $resolvedConfigPath -PathType Leaf)) {
        throw "Configuration file is missing: $resolvedConfigPath"
    }
    $raw = Import-PowerShellDataFile -LiteralPath $resolvedConfigPath
    if ([int]$raw.SchemaVersion -ne 1) {
        throw 'Unsupported configuration schema. Expected SchemaVersion = 1.'
    }

    foreach ($name in @('ResticPath', 'OnlineRepository', 'OfflineRoot')) {
        if (-not $raw.ContainsKey($name) -or [string]::IsNullOrWhiteSpace([string]$raw[$name])) {
            throw "Configuration value is required: $name"
        }
        if ([string]$raw[$name] -match '<[^>]+>') {
            throw "Replace the placeholder before use: $name"
        }
    }
    if (-not $raw.ContainsKey('Sources')) { throw 'Configuration value is required: Sources' }
    $sources = @($raw['Sources'] | ForEach-Object { Resolve-MirrorBackupValue -Value ([string]$_) })
    if ($sources.Count -eq 0) {
        throw 'At least one source path is required.'
    }
    foreach ($source in $sources) {
        if ($source -match '<[^>]+>' -or -not [IO.Path]::IsPathRooted($source)) {
            throw "Source paths must be absolute and contain no placeholders: $source"
        }
    }

    $dataRoot = Join-Path $env:ProgramData 'MirrorBackup'
    $stateRoot = Join-Path $dataRoot 'state'
    $canaryRoot = Join-Path $dataRoot 'canary'
    $offlineRoot = Resolve-MirrorBackupValue -Value ([string]$raw.OfflineRoot)
    $onlineRecoveryKit = $null
    if ($raw.ContainsKey('OnlineRecoveryKit') -and -not [string]::IsNullOrWhiteSpace([string]$raw['OnlineRecoveryKit'])) {
        $onlineRecoveryKit = Resolve-MirrorBackupValue -Value ([string]$raw['OnlineRecoveryKit'])
        if ($onlineRecoveryKit -match '<[^>]+>') {
            throw 'Replace the OnlineRecoveryKit placeholder before use, or leave it empty.'
        }
    }

    $retention = if ($raw.ContainsKey('Retention')) { $raw.Retention } else { @{} }
    $schedule = if ($raw.ContainsKey('Schedule')) { $raw.Schedule } else { @{} }
    return [pscustomobject]@{
        ConfigPath = $resolvedConfigPath
        ResticPath = Resolve-MirrorBackupValue -Value ([string]$raw.ResticPath)
        OnlineRepository = Resolve-MirrorBackupValue -Value ([string]$raw.OnlineRepository)
        OnlineRecoveryKit = $onlineRecoveryKit
        OfflineRoot = $offlineRoot
        OfflineRepository = [IO.Path]::Combine($offlineRoot, 'repository')
        OfflineMarker = [IO.Path]::Combine($offlineRoot, 'media.json')
        OfflineRecoveryKit = [IO.Path]::Combine($offlineRoot, 'recovery-kit')
        Sources = $sources
        Excludes = if ($raw.ContainsKey('Excludes')) { @($raw['Excludes'] | ForEach-Object { [string]$_ }) } else { @() }
        OnlineTag = if ($raw.ContainsKey('OnlineTag') -and $raw['OnlineTag']) { [string]$raw['OnlineTag'] } else { 'mirror-online' }
        OfflineTag = if ($raw.ContainsKey('OfflineTag') -and $raw['OfflineTag']) { [string]$raw['OfflineTag'] } else { 'mirror-offline' }
        DataRoot = $dataRoot
        StateRoot = $stateRoot
        LogRoot = Join-Path $dataRoot 'logs'
        CacheRoot = Join-Path $dataRoot 'cache'
        TempRoot = Join-Path $dataRoot 'tmp'
        CanaryRoot = $canaryRoot
        CanaryFile = Join-Path $canaryRoot 'restore-canary.txt'
        OperationLock = Join-Path $stateRoot 'operation.lock'
        OnlineSecret = Join-Path $stateRoot 'secret.online.dpapi'
        OfflineSecret = Join-Path $stateRoot 'secret.offline.dpapi'
        OnlineRepositoryId = Join-Path $stateRoot 'repository-id.online.txt'
        OfflineRepositoryId = Join-Path $stateRoot 'repository-id.offline.txt'
        OfflineMediaIdentity = Join-Path $stateRoot 'offline-media.json'
        OnlineSuccess = Join-Path $stateRoot 'last-success.online.json'
        OfflineSuccess = Join-Path $stateRoot 'last-success.offline.json'
        OnlineFailure = Join-Path $stateRoot 'last-failure.online.json'
        OfflineFailure = Join-Path $stateRoot 'last-failure.offline.json'
        OnlineRestore = Join-Path $stateRoot 'last-restore.online.json'
        OfflineRestore = Join-Path $stateRoot 'last-restore.offline.json'
        MaintenanceSuccess = Join-Path $stateRoot 'last-maintenance.online.json'
        MaintenanceFailure = Join-Path $stateRoot 'last-maintenance-failure.online.json'
        OnlineCheckCounter = Join-Path $stateRoot 'check-counter.online.txt'
        OfflineCheckCounter = Join-Path $stateRoot 'check-counter.offline.txt'
        HealthAlert = Join-Path $stateRoot 'BACKUP-STALE.txt'
        KeepLast = if ($retention.ContainsKey('KeepLast') -and $retention['KeepLast']) { [int]$retention['KeepLast'] } else { 3 }
        KeepDaily = if ($retention.ContainsKey('KeepDaily') -and $retention['KeepDaily']) { [int]$retention['KeepDaily'] } else { 14 }
        KeepWeekly = if ($retention.ContainsKey('KeepWeekly') -and $retention['KeepWeekly']) { [int]$retention['KeepWeekly'] } else { 8 }
        KeepMonthly = if ($retention.ContainsKey('KeepMonthly') -and $retention['KeepMonthly']) { [int]$retention['KeepMonthly'] } else { 12 }
        KeepYearly = if ($retention.ContainsKey('KeepYearly') -and $retention['KeepYearly']) { [int]$retention['KeepYearly'] } else { 3 }
        BackupAt = if ($schedule.ContainsKey('BackupAt') -and $schedule['BackupAt']) { [string]$schedule['BackupAt'] } else { '02:15' }
        MaintenanceDay = if ($schedule.ContainsKey('MaintenanceDay') -and $schedule['MaintenanceDay']) { [string]$schedule['MaintenanceDay'] } else { 'Sunday' }
        MaintenanceAt = if ($schedule.ContainsKey('MaintenanceAt') -and $schedule['MaintenanceAt']) { [string]$schedule['MaintenanceAt'] } else { '04:30' }
        HealthAt = if ($schedule.ContainsKey('HealthAt') -and $schedule['HealthAt']) { [string]$schedule['HealthAt'] } else { '09:00' }
    }
}

function Initialize-MirrorBackupLayout {
    param([Parameter(Mandatory = $true)][object]$Config)
    Assert-MirrorBackupAdministrator
    foreach ($path in @($Config.DataRoot, $Config.StateRoot, $Config.LogRoot, $Config.CacheRoot, $Config.TempRoot, $Config.CanaryRoot)) {
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
        Set-MirrorBackupAdminOnlyAcl -Path $path
    }
    if (-not (Test-Path -LiteralPath $Config.CanaryFile -PathType Leaf)) {
        Write-MirrorBackupTextAtomic -Path $Config.CanaryFile -Content ('mirror-backup restore canary ' + [guid]::NewGuid().ToString('D'))
    }
}

function Write-MirrorBackupTextAtomic {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
    )
    $directory = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Path))
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $temporary = Join-Path $directory ('.mirror-backup-' + [guid]::NewGuid().ToString('N') + '.tmp')
    $backup = Join-Path $directory ('.mirror-backup-' + [guid]::NewGuid().ToString('N') + '.bak')
    try {
        [IO.File]::WriteAllText($temporary, $Content, (New-Object Text.UTF8Encoding($false)))
        Set-MirrorBackupAdminOnlyAcl -Path $temporary
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            [IO.File]::Replace($temporary, $Path, $backup, $true)
        } else {
            [IO.File]::Move($temporary, $Path)
        }
        Set-MirrorBackupAdminOnlyAcl -Path $Path
    } finally {
        Remove-Item -LiteralPath $temporary, $backup -Force -ErrorAction SilentlyContinue
    }
}

function Save-MirrorBackupSecret {
    param(
        [Parameter(Mandatory = $true)][Security.SecureString]$Secret,
        [Parameter(Mandatory = $true)][string]$Path
    )
    Write-MirrorBackupTextAtomic -Path $Path -Content ($Secret | ConvertFrom-SecureString)
}

function Get-MirrorBackupSecret {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "DPAPI secret is missing: $Path"
    }
    return (Get-Content -Raw -LiteralPath $Path | ConvertTo-SecureString)
}

function ConvertFrom-MirrorBackupSecureString {
    param([Parameter(Mandatory = $true)][Security.SecureString]$Secret)
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secret)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

function Read-MirrorBackupConfirmedSecret {
    param([Parameter(Mandatory = $true)][string]$Label)
    while ($true) {
        $first = Read-Host "$Label password" -AsSecureString
        $second = Read-Host "Confirm $Label password" -AsSecureString
        $firstText = ConvertFrom-MirrorBackupSecureString -Secret $first
        $secondText = ConvertFrom-MirrorBackupSecureString -Secret $second
        try {
            if ($firstText.Length -lt 20) {
                Write-Warning 'Use at least 20 characters from a password generator.'
                continue
            }
            if ($firstText -cne $secondText) {
                Write-Warning 'Passwords do not match.'
                continue
            }
            return $first
        } finally {
            $firstText = $null
            $secondText = $null
        }
    }
}

function New-MirrorBackupLogPath {
    param(
        [Parameter(Mandatory = $true)][object]$Config,
        [Parameter(Mandatory = $true)][string]$Prefix
    )
    return Join-Path $Config.LogRoot ($Prefix + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
}

function Invoke-MirrorBackupRestic {
    param(
        [Parameter(Mandatory = $true)][Security.SecureString]$Secret,
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$ResticPath,
        [string]$LogPath,
        [switch]$Capture
    )
    if (-not (Test-Path -LiteralPath $ResticPath -PathType Leaf)) {
        throw "restic executable is missing: $ResticPath"
    }
    $oldRepository = $env:RESTIC_REPOSITORY
    $oldPassword = $env:RESTIC_PASSWORD
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secret)
    try {
        $env:RESTIC_REPOSITORY = $Repository
        $env:RESTIC_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
        if ($LogPath) {
            Add-Content -LiteralPath $LogPath -Value "[$(Get-Date -Format o)] $ResticPath $($Arguments -join ' ')"
        }
        $oldPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $output = @(& $ResticPath @Arguments 2>&1)
            $exitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $oldPreference
        }
        $text = ($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
        if ($LogPath -and $text) {
            Add-Content -LiteralPath $LogPath -Value $text
        }
        if ($exitCode -ne 0) {
            throw "restic exited with code $exitCode. $text"
        }
        if ($Capture) {
            return $text.Trim()
        }
        if ($text) { Write-Host $text }
    } finally {
        $env:RESTIC_REPOSITORY = $oldRepository
        $env:RESTIC_PASSWORD = $oldPassword
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

function Wait-MirrorBackupPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$Seconds = 30
    )
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        if (Test-Path -LiteralPath $Path) { return }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    throw "Path is unavailable: $Path"
}

function Enter-MirrorBackupLock {
    param([Parameter(Mandatory = $true)][object]$Config)
    try {
        return [IO.File]::Open($Config.OperationLock, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    } catch {
        throw 'Another mirror-backup operation is already running.'
    }
}

function Get-MirrorBackupRepositoryId {
    param(
        [Parameter(Mandatory = $true)][Security.SecureString]$Secret,
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string]$ResticPath
    )
    $json = Invoke-MirrorBackupRestic -Secret $Secret -Repository $Repository -Arguments @('cat', 'config') -ResticPath $ResticPath -Capture
    $config = $json | ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace([string]$config.id)) {
        throw 'restic repository config did not return an ID.'
    }
    return [string]$config.id
}

function Assert-MirrorBackupRepositoryId {
    param(
        [Parameter(Mandatory = $true)][Security.SecureString]$Secret,
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string]$ExpectedIdPath,
        [Parameter(Mandatory = $true)][string]$ResticPath
    )
    if (-not (Test-Path -LiteralPath $ExpectedIdPath -PathType Leaf)) {
        throw "Repository ID record is missing: $ExpectedIdPath"
    }
    $expected = (Get-Content -Raw -LiteralPath $ExpectedIdPath).Trim()
    $actual = Get-MirrorBackupRepositoryId -Secret $Secret -Repository $Repository -ResticPath $ResticPath
    if ($actual -cne $expected) {
        throw 'Repository ID mismatch. Refusing to continue.'
    }
    return $actual
}

function Get-MirrorBackupLatestSnapshot {
    param(
        [Parameter(Mandatory = $true)][Security.SecureString]$Secret,
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string]$Tag,
        [Parameter(Mandatory = $true)][string]$ResticPath
    )
    $json = Invoke-MirrorBackupRestic -Secret $Secret -Repository $Repository -Arguments @(
        'snapshots', '--json', '--host', $env:COMPUTERNAME, '--tag', $Tag
    ) -ResticPath $ResticPath -Capture
    $snapshots = @($json | ConvertFrom-Json)
    if ($snapshots.Count -eq 0) { throw "No snapshot found for tag $Tag." }
    return @($snapshots | Sort-Object { [DateTime]::Parse([string]$_.time) } -Descending)[0]
}

function Test-MirrorBackupCanaryRestore {
    param(
        [Parameter(Mandatory = $true)][object]$Config,
        [Parameter(Mandatory = $true)][Security.SecureString]$Secret,
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string]$Tag,
        [Parameter(Mandatory = $true)][string]$SnapshotId,
        [Parameter(Mandatory = $true)][string]$EvidencePath,
        [Parameter(Mandatory = $true)][string]$LogPath,
        [string]$ResticPath
    )
    if (-not $ResticPath) { $ResticPath = $Config.ResticPath }
    $snapshotPath = '/' + $Config.CanaryFile.Replace(':', '').Replace('\', '/')
    $restoreRoot = Join-Path $Config.StateRoot ('restore-test-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $restoreRoot | Out-Null
    try {
        Invoke-MirrorBackupRestic -Secret $Secret -Repository $Repository -Arguments @(
            'restore', $SnapshotId, '--target', $restoreRoot, '--include', $snapshotPath, '--verify'
        ) -ResticPath $ResticPath -LogPath $LogPath
        $files = @(Get-ChildItem -LiteralPath $restoreRoot -File -Recurse -Force)
        if ($files.Count -ne 1 -or $files[0].Name -cne 'restore-canary.txt') {
            throw "Canary restore produced an unexpected file set: $($files.Count) files."
        }
        $expectedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Config.CanaryFile).Hash
        $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $files[0].FullName).Hash
        if ($actualHash -cne $expectedHash) { throw 'Canary restore SHA-256 mismatch.' }
        $evidence = [ordered]@{
            verifiedUtc = [DateTime]::UtcNow.ToString('o')
            repositoryTag = $Tag
            snapshotId = $SnapshotId
            restoredPath = $snapshotPath
            canarySha256 = $expectedHash
            resticSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $ResticPath).Hash
        }
        Write-MirrorBackupTextAtomic -Path $EvidencePath -Content ($evidence | ConvertTo-Json -Depth 4)
    } finally {
        Remove-Item -LiteralPath $restoreRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Assert-MirrorBackupSourcesAvailable {
    param([Parameter(Mandatory = $true)][object]$Config)

    $missing = @($Config.Sources | Where-Object { -not (Test-Path -LiteralPath $_) })
    if ($missing.Count -gt 0) {
        throw "Configured source paths are unavailable; refusing a partial backup: $($missing -join ', ')"
    }
}

function Invoke-MirrorBackupSnapshot {
    param(
        [Parameter(Mandatory = $true)][object]$Config,
        [Parameter(Mandatory = $true)][Security.SecureString]$Secret,
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string]$Tag,
        [Parameter(Mandatory = $true)][string]$EvidencePath,
        [Parameter(Mandatory = $true)][string]$LogPath
    )
    Assert-MirrorBackupSourcesAvailable -Config $Config
    $sources = @($Config.Sources)
    $sources += $Config.CanaryFile
    $sources = @($sources | Sort-Object -Unique)
    $arguments = @('backup', '--use-fs-snapshot', '--compression', 'auto', '--host', $env:COMPUTERNAME, '--tag', $Tag)
    foreach ($exclude in $Config.Excludes) {
        if (-not [string]::IsNullOrWhiteSpace($exclude)) { $arguments += @('--exclude', $exclude) }
    }
    $arguments += $sources
    Invoke-MirrorBackupRestic -Secret $Secret -Repository $Repository -Arguments $arguments -ResticPath $Config.ResticPath -LogPath $LogPath
    $snapshot = Get-MirrorBackupLatestSnapshot -Secret $Secret -Repository $Repository -Tag $Tag -ResticPath $Config.ResticPath
    Test-MirrorBackupCanaryRestore -Config $Config -Secret $Secret -Repository $Repository -Tag $Tag -SnapshotId $snapshot.id -EvidencePath $EvidencePath -LogPath $LogPath
    return $snapshot
}

function Write-MirrorBackupSuccessState {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Snapshot,
        [Parameter(Mandatory = $true)][string]$Tag
    )
    $state = [ordered]@{
        completedUtc = [DateTime]::UtcNow.ToString('o')
        tag = $Tag
        snapshotId = [string]$Snapshot.id
        snapshotTime = [string]$Snapshot.time
        host = [string]$Snapshot.hostname
    }
    Write-MirrorBackupTextAtomic -Path $Path -Content ($state | ConvertTo-Json -Depth 4)
}

function Write-MirrorBackupFailureState {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Message
    )
    Write-MirrorBackupTextAtomic -Path $Path -Content (([ordered]@{
        failedUtc = [DateTime]::UtcNow.ToString('o')
        message = $Message
    }) | ConvertTo-Json -Depth 3)
}

function Get-MirrorBackupNextSubset {
    param(
        [Parameter(Mandatory = $true)][string]$CounterPath,
        [Parameter(Mandatory = $true)][int]$Total
    )
    $counter = 0
    if (Test-Path -LiteralPath $CounterPath -PathType Leaf) {
        $raw = (Get-Content -Raw -LiteralPath $CounterPath).Trim()
        if ($raw -match '^\d+$') { $counter = [int]$raw }
    }
    return "$(($counter % $Total) + 1)/$Total"
}

function Complete-MirrorBackupSubset {
    param([Parameter(Mandatory = $true)][string]$CounterPath)
    $counter = 0
    if (Test-Path -LiteralPath $CounterPath -PathType Leaf) {
        $raw = (Get-Content -Raw -LiteralPath $CounterPath).Trim()
        if ($raw -match '^\d+$') { $counter = [int]$raw }
    }
    Write-MirrorBackupTextAtomic -Path $CounterPath -Content ([string]($counter + 1))
}

function Initialize-MirrorBackupOfflineMarker {
    param([Parameter(Mandatory = $true)][object]$Config)
    $identity = [ordered]@{
        markerId = [guid]::NewGuid().ToString('D')
        repositoryId = (Get-Content -Raw -LiteralPath $Config.OfflineRepositoryId).Trim()
        createdUtc = [DateTime]::UtcNow.ToString('o')
    }
    $json = $identity | ConvertTo-Json -Depth 3
    Write-MirrorBackupTextAtomic -Path $Config.OfflineMediaIdentity -Content $json
    [IO.File]::WriteAllText($Config.OfflineMarker, $json, (New-Object Text.UTF8Encoding($false)))
}

function Assert-MirrorBackupOfflineMedia {
    param([Parameter(Mandatory = $true)][object]$Config)
    if (-not (Test-Path -LiteralPath $Config.OfflineMediaIdentity -PathType Leaf) -or
        -not (Test-Path -LiteralPath $Config.OfflineMarker -PathType Leaf)) {
        throw 'Offline media identity is missing.'
    }
    $expected = Get-Content -Raw -LiteralPath $Config.OfflineMediaIdentity | ConvertFrom-Json
    $actual = Get-Content -Raw -LiteralPath $Config.OfflineMarker | ConvertFrom-Json
    if ($expected.markerId -cne $actual.markerId -or $expected.repositoryId -cne $actual.repositoryId) {
        throw 'The connected offline media does not match the enrolled recovery drive.'
    }
}

function Copy-MirrorBackupRecoveryKit {
    param(
        [Parameter(Mandatory = $true)][object]$Config,
        [Parameter(Mandatory = $true)][string]$Destination
    )
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Copy-Item -LiteralPath $Config.ResticPath -Destination (Join-Path $Destination 'restic.exe') -Force
    $recoveryDocument = Join-Path (Split-Path $PSScriptRoot -Parent) 'docs\RECOVERY.md'
    if (Test-Path -LiteralPath $recoveryDocument -PathType Leaf) {
        Copy-Item -LiteralPath $recoveryDocument -Destination (Join-Path $Destination 'RECOVERY.md') -Force
    }
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $Destination 'restic.exe')).Hash
    [IO.File]::WriteAllText((Join-Path $Destination 'RESTIC-SHA256.txt'), ($hash + '  restic.exe'), (New-Object Text.UTF8Encoding($false)))
}

Export-ModuleMember -Function *-MirrorBackup*
