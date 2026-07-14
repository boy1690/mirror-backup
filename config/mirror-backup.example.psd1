@{
    SchemaVersion = 1

    # Install.ps1 copies the user-supplied restic.exe here.
    ResticPath = 'C:\Program Files\MirrorBackup\bin\restic.exe'

    # The current public release supports a local or SMB filesystem path.
    OnlineRepository = '\\<NAS-HOST>\<BACKUP-SHARE>\mirror-backup'

    # Optional sibling directory containing restic.exe and RECOVERY.md.
    OnlineRecoveryKit = '\\<NAS-HOST>\<BACKUP-SHARE>\mirror-backup-recovery-kit'

    # Keep this drive physically disconnected except while updating it.
    OfflineRoot = 'E:\MirrorBackup'

    Sources = @(
        'C:\Users\<USER>\Documents'
        'D:\Projects'
    )

    Excludes = @(
        '**\node_modules\**'
        '**\.git\objects\**'
        '**\target\**'
        '**\dist\**'
        '**\models\**'
        '**\*.tmp'
    )

    OnlineTag = 'mirror-online'
    OfflineTag = 'mirror-offline'

    Retention = @{
        KeepLast = 3
        KeepDaily = 14
        KeepWeekly = 8
        KeepMonthly = 12
        KeepYearly = 3
    }

    Schedule = @{
        BackupAt = '02:15'
        MaintenanceDay = 'Sunday'
        MaintenanceAt = '04:30'
        HealthAt = '09:00'
    }
}
