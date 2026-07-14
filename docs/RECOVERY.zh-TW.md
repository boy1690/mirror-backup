# 救援指南

[English](RECOVERY.md) | 繁體中文

請在發生緊急狀況之前列印這份文件。不要把真實密碼寫進儲存在電腦裡的副本。

## 必備項目

- 一台乾淨且已完成安全更新的 Windows 電腦；
- 版本庫救援工具包或 restic 官方專案提供的 `restic.exe`；
- 版本庫位置；
- 與該版本庫相符的密碼；
- 足夠且乾淨的還原空間。

## 線上版本庫

開啟 Windows PowerShell 並設定版本庫位置。只在 restic 提示時輸入密碼。

```powershell
$env:RESTIC_REPOSITORY = '\\<NAS-HOST>\<BACKUP-SHARE>\mirror-backup'
& '.\restic.exe' snapshots
& '.\restic.exe' restore latest --target 'D:\Recovered'
```

## 離線版本庫

在救援電腦完成更新並確認可信任之前，保持卸除式磁碟拔除。接上磁碟後執行：

```powershell
$env:RESTIC_REPOSITORY = 'E:\MirrorBackup\repository'
& 'E:\MirrorBackup\recovery-kit\restic.exe' snapshots
& 'E:\MirrorBackup\recovery-kit\restic.exe' restore latest --target 'D:\Recovered'
```

## 還原後驗證

1. 使用原本的應用程式開啟幾個重要檔案；
2. 若有已知雜湊值，逐一比對；
3. 在還原資料另行複製完成前，保持原始版本庫不變；
4. 緊急救援期間不要執行 `forget`、`prune`、`repair` 或版本庫移轉。

## 密碼無法開啟版本庫

如果 restic 回報沒有金鑰可以開啟版本庫：

- 仔細重試一次後就停止；
- 確認密碼屬於正確的版本庫；
- 嘗試第二份密封紀錄或密碼管理器項目；
- 絕對不要再次初始化版本庫。初始化無法修復既有的加密版本庫。
