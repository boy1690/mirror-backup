# Contributing

English | [繁體中文](CONTRIBUTING.zh-TW.md)

Contributions are welcome, especially improvements to recovery verification, accessibility, documentation, and test coverage.

Before opening a pull request:

```powershell
.\tests\Parse-All.ps1
.\tests\Config.Tests.ps1
.\tools\scan-secrets.ps1 -Root .
```

Rules:

- Never commit passwords, tokens, private IP addresses, hostnames, real usernames, email addresses, repository IDs, device IDs, or real backup data.
- Use placeholders such as `<USER>`, `<NAS-HOST>`, and `<BACKUP-SHARE>`.
- Do not add third-party binaries to the repository.
- Preserve fail-closed behavior: a missing canary, repository ID mismatch, or verification error must fail the operation.
- Any destructive repository action requires an explicit command and documentation of its scope.
