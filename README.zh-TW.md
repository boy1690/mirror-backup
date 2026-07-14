# mirror-backup

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

## 快速開始

1. 從 restic 官方專案下載並驗證 `restic.exe`。
2. 複製 `config/mirror-backup.example.psd1` 到私人位置，替換所有 placeholder，並確認來源與排除清單。
3. 在系統管理員 Windows PowerShell 安裝：

```powershell
.\Install.ps1 -ResticPath 'C:\Path\To\restic.exe' -ConfigPath 'C:\Path\To\mirror-backup.psd1'
```

4. 依序初始化線上與離線版本庫，兩者使用不同的強密碼，並把密碼記錄在電腦以外。
5. 執行第一次線上及離線備份，確認 canary 還原成功。
6. 安全退出並拔除離線磁碟。
7. 使用密碼管理器或紙本密碼執行 `Test-Recovery.ps1`。
8. 還原成功後才執行 `Install-ScheduledTasks.ps1`。

完整英文安裝命令與日常操作請看 [README.md](README.md)，緊急救援請看 [docs/RECOVERY.md](docs/RECOVERY.md)。
