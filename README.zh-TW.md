# mirror-backup

[English](README.md) | 繁體中文

`mirror-backup` 是給重視隱私的 Windows 使用者使用的加密、版本化備份工具。

它維護兩個彼此獨立的 restic 版本庫：

- 線上版本庫：每日自動備份；
- 離線版本庫：更新成功後安全退出並實際拔除。

每次成功都會從精確的 canary 路徑還原一個檔案並驗證 SHA-256。專案名稱雖然有 mirror，但刻意不使用 `/MIR`：誤刪、損壞或勒索污染不應同步進離線副本。

> 目前是早期公開版本。正式使用前，請先用非關鍵資料演練完整還原。

## 隱私設計

- restic 會加密版本庫內容、檔名與快照。
- 日常密碼由同一個 Windows 帳戶的 DPAPI 保護。
- 線上與離線版本庫使用不同密碼與版本庫 ID。
- 離線磁碟平常必須實際拔除。
- 救援測試會使用密碼管理器或密封紙本，不依賴 DPAPI。
- 不包含遙測、雲端帳戶或託管控制平面。

## 可以防範什麼

- 系統碟損壞；
- 誤刪檔案與不希望保留的變更；
- 更換整台電腦；
- 線上版本庫遺失或損壞；
- 當離線磁碟確實拔除時，防範勒索軟體同時污染所有備份。

它無法保護仍插在電腦上的離線磁碟，也無法找回從未記錄在電腦以外的密碼。完整邊界請閱讀[威脅模型](docs/THREAT-MODEL.zh-TW.md)。

## 系統需求

- Windows 10 或 Windows 11；
- Windows PowerShell 5.1；
- 具有真實帳戶密碼的系統管理員帳戶（工作排程器不能使用 Windows Hello PIN）；
- 由使用者自行從 restic 官方專案取得並驗證的 `restic.exe`；
- 一個本機或 SMB 檔案系統位置，作為線上版本庫；
- 一個卸除式磁碟，作為離線版本庫。

本專案刻意不提交任何第三方執行檔。

## 快速開始

1. 從 restic 官方專案下載並驗證 `restic.exe`。
2. 複製 `config/mirror-backup.example.psd1` 到私人位置，替換所有 placeholder，並確認來源與排除清單。
3. 在系統管理員 Windows PowerShell 安裝：

```powershell
.\Install.ps1 -ResticPath 'C:\Path\To\restic.exe' -ConfigPath 'C:\Path\To\mirror-backup.psd1'
```

4. 先初始化線上版本庫，再初始化已接上的離線磁碟。兩者必須使用不同的隨機密碼，並將兩組密碼記錄在電腦以外。

```powershell
& 'C:\Program Files\MirrorBackup\scripts\Initialize-Repositories.ps1' -Online
& 'C:\Program Files\MirrorBackup\scripts\Initialize-Repositories.ps1' -Offline
```

5. 建立並驗證第一份線上及離線快照：

```powershell
& 'C:\Program Files\MirrorBackup\scripts\Backup-Online.ps1'
& 'C:\Program Files\MirrorBackup\scripts\Update-Offline.ps1'
```

6. 安全退出並實際拔除離線磁碟。
7. 使用密碼管理器或密封紙本中的密碼測試救援，確認不依賴 DPAPI 也能還原：

```powershell
& 'C:\Program Files\MirrorBackup\scripts\Test-Recovery.ps1' -Repository Online
```

8. 救援測試成功後，才安裝定期工作：

```powershell
& 'C:\Program Files\MirrorBackup\scripts\Install-ScheduledTasks.ps1'
```

## 日常操作

- 每日：線上工作自動執行，並驗證 canary 還原。
- 每週：自動執行保留政策、清理、輪替資料讀取與 canary 還原。
- 每月：接上離線磁碟，執行 `Update-Offline.ps1`，等待驗證成功後安全退出並拔除。
- 變更 Windows 帳戶密碼後：重新安裝定期工作，讓工作排程器保存新的認證。

## 緊急救援

發生故障前就應閱讀並列印[繁體中文救援指南](docs/RECOVERY.zh-TW.md)。將每個版本庫的密碼與版本庫 ID 分開保存，且不要與電腦或離線磁碟放在同一處。

## 開發與驗證

```powershell
.\tests\Parse-All.ps1
.\tests\Config.Tests.ps1
.\tools\scan-secrets.ps1 -Root .
```

## 其他繁體中文文件

- [威脅模型](docs/THREAT-MODEL.zh-TW.md)
- [安全政策](SECURITY.zh-TW.md)
- [貢獻指南](CONTRIBUTING.zh-TW.md)

## 授權

Apache License 2.0，詳見 [LICENSE](LICENSE)。
