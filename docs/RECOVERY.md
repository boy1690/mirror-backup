# Recovery guide

Print this document before an emergency. Do not write real passwords into a copy stored on the computer.

## Required items

- a clean, updated Windows computer;
- `restic.exe` from the repository recovery kit or the official project;
- the repository location;
- the matching repository password; and
- enough clean storage for restored files.

## Online repository

Open Windows PowerShell and set the repository location. Enter the password only when restic prompts for it.

```powershell
$env:RESTIC_REPOSITORY = '\\<NAS-HOST>\<BACKUP-SHARE>\mirror-backup'
& '.\restic.exe' snapshots
& '.\restic.exe' restore latest --target 'D:\Recovered'
```

## Offline repository

Keep the removable drive disconnected until the recovery computer is updated and trusted. After connecting it:

```powershell
$env:RESTIC_REPOSITORY = 'E:\MirrorBackup\repository'
& 'E:\MirrorBackup\recovery-kit\restic.exe' snapshots
& 'E:\MirrorBackup\recovery-kit\restic.exe' restore latest --target 'D:\Recovered'
```

## Verification

After restore:

1. open several important files with their normal applications;
2. compare known hashes when available;
3. keep the original repository unchanged until the restored data is independently copied; and
4. do not run `forget`, `prune`, `repair`, or repository migration during an emergency restore.

## Password failure

If restic reports that no key can open the repository:

- stop after one careful retry;
- verify that the password belongs to the correct repository;
- try the second sealed record or password-manager entry; and
- never initialize the repository again. Initialization does not repair an existing encrypted repository.
