# mirror-backup

Privacy-focused, encrypted, versioned backups for Windows.

`mirror-backup` maintains two independent [restic](https://restic.net/) repositories:

- an online repository for unattended daily backups; and
- a removable repository that stays physically disconnected between updates.

Every successful operation restores one exact canary path and verifies its SHA-256 hash. The name is a project name: this tool deliberately does **not** use file mirroring such as `/MIR`, because deletion, corruption, or ransomware should not be propagated into the offline copy.

> Status: early public release. Review the threat model and test recovery with non-critical data before relying on it.

## Privacy properties

- Repository contents, filenames, and snapshots are encrypted by restic.
- Daily repository passwords are stored with Windows DPAPI for the same Windows account.
- Online and offline repositories use separate passwords and repository IDs.
- The offline drive is useful only when it is safely ejected and physically disconnected.
- Password-manager and sealed-paper recovery are tested without using DPAPI.
- No telemetry, cloud account, or hosted control plane is included.

## What it protects against

- system-drive failure;
- accidental deletion and unwanted changes;
- replacement of the computer;
- loss or corruption of the online repository; and
- ransomware reaching always-connected storage, when the offline drive is disconnected.

It cannot protect a connected drive from an administrator-level attacker, and it cannot recover a password that was never recorded outside the computer. See [docs/THREAT-MODEL.md](docs/THREAT-MODEL.md).

## Requirements

- Windows 10 or Windows 11;
- Windows PowerShell 5.1;
- an administrator account with a real account password (scheduled tasks cannot use a Windows Hello PIN);
- a user-supplied `restic.exe` from the official restic project;
- one online local/SMB filesystem location; and
- one removable drive for the offline repository.

Third-party binaries are intentionally not committed to this repository.

## Quick start

1. Download and verify `restic.exe` from the official project.
2. Copy `config/mirror-backup.example.psd1` to a private location, replace every placeholder, and review the source/exclude list.
3. From an elevated Windows PowerShell session:

```powershell
.\Install.ps1 -ResticPath 'C:\Path\To\restic.exe' -ConfigPath 'C:\Path\To\mirror-backup.psd1'
```

4. Initialize the online repository, then the connected offline drive. Use different generated passwords and record both outside the computer.

```powershell
& 'C:\Program Files\MirrorBackup\scripts\Initialize-Repositories.ps1' -Online
& 'C:\Program Files\MirrorBackup\scripts\Initialize-Repositories.ps1' -Offline
```

5. Create and verify the first snapshots:

```powershell
& 'C:\Program Files\MirrorBackup\scripts\Backup-Online.ps1'
& 'C:\Program Files\MirrorBackup\scripts\Update-Offline.ps1'
```

6. Safely eject and physically disconnect the offline drive.
7. Test recovery using the password-manager or paper record:

```powershell
& 'C:\Program Files\MirrorBackup\scripts\Test-Recovery.ps1' -Repository Online
```

8. Install scheduled tasks only after recovery succeeds:

```powershell
& 'C:\Program Files\MirrorBackup\scripts\Install-ScheduledTasks.ps1'
```

## Operating routine

- Daily: the online task runs automatically and verifies the canary.
- Weekly: retention, prune, rotating data reads, and canary restore run automatically.
- Monthly: connect the offline drive, run `Update-Offline.ps1`, wait for verification, safely eject, and disconnect it.
- After changing the Windows account password: reinstall the scheduled tasks so Task Scheduler has the new credential.

## Recovery

Read [docs/RECOVERY.md](docs/RECOVERY.md) before an emergency. Keep a printed copy with each repository password and repository ID, separate from the computer and offline drive.

## Development and verification

```powershell
.\tests\Parse-All.ps1
.\tests\Config.Tests.ps1
.\tools\scan-secrets.ps1 -Root .
```

## License

Apache License 2.0. See [LICENSE](LICENSE).

繁體中文說明：[README.zh-TW.md](README.zh-TW.md)
