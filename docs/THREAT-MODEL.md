# Threat model

## Security goals

`mirror-backup` aims to preserve confidential, versioned, recoverable copies of selected Windows data when one storage layer fails or is corrupted.

The design assumes:

- the computer is trusted while backups run;
- the Windows account and administrator boundary are not already compromised;
- restic's cryptography and repository format behave as documented; and
- at least one repository password is recorded outside the computer.

## Defenses

| Threat | Defense |
|---|---|
| Accidental deletion or unwanted edits | Versioned snapshots with retention |
| Online repository loss | Independent removable repository |
| Ransomware reaching online storage | Physically disconnected removable drive |
| Wrong removable drive | Local and removable media marker comparison plus repository ID verification |
| Silent repository damage | Rotating `restic check --read-data-subset` |
| Backup that cannot restore | Exact-path canary restore with `--verify` and SHA-256 comparison |
| Computer replacement | Password-manager or sealed-paper password plus portable restic recovery kit |
| Password exposed in command history | Password is provided to restic through a temporary process environment, not command-line arguments |

## Explicit non-goals

- Protecting a repository password from a process already running as the same user or as administrator.
- Protecting a removable drive while it remains connected.
- Replacing endpoint security, operating-system updates, or NAS access controls.
- Guaranteeing availability of an online repository or network.
- Automatically backing up every application database safely; applications may require their own export or quiescing mechanism.

## Important operating rules

1. Use different generated passwords for online and offline repositories.
2. Record both passwords outside the computer before relying on the system.
3. Disconnect the offline drive immediately after a verified update.
4. Test recovery with the external password record, not only DPAPI.
5. Reinstall scheduled tasks after changing the Windows account password.
6. Treat any failed canary restore as a failed backup, even if restic created a snapshot.

## Residual risks

- A malicious administrator can modify installed scripts, scheduled tasks, DPAPI secrets, or backup sources.
- A copied offline marker is not a hardware attestation. Repository ID and password verification still prevent accidental use of an unrelated repository.
- Source files may contain their own secrets. Encryption protects the repository at rest, not an unlocked Windows session.
- Retention and prune operations intentionally delete unreferenced repository data; they run only against the online repository in the default workflow.
