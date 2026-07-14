# Security policy

## Supported versions

Security fixes are applied to the latest tagged release and the default branch.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting feature when it is enabled for this repository. Do not include repository passwords, recovery keys, private network addresses, personal file paths, or real backup data in a report.

Include:

- the affected commit or release;
- a minimal reproduction using placeholder paths;
- expected and actual behavior; and
- whether the issue could expose plaintext, corrupt a repository, or make verification report a false success.

## Security boundaries

The project treats administrator access as a trusted boundary. It does not claim to defend against an attacker who already controls the Windows administrator account. See [docs/THREAT-MODEL.md](docs/THREAT-MODEL.md).
