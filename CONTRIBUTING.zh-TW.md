# 貢獻指南

[English](CONTRIBUTING.md) | 繁體中文

歡迎各種貢獻，尤其是救援驗證、無障礙設計、文件與測試覆蓋率方面的改進。

提出 pull request 前請執行：

```powershell
.\tests\Parse-All.ps1
.\tests\Config.Tests.ps1
.\tools\scan-secrets.ps1 -Root .
```

規則：

- 絕對不可提交密碼、token、私人 IP、主機名稱、真實使用者名稱、電子郵件、版本庫 ID、裝置 ID 或真實備份資料。
- 一律使用 `<USER>`、`<NAS-HOST>` 與 `<BACKUP-SHARE>` 等 placeholder。
- 不可把第三方執行檔加入版本庫。
- 保持失敗即停止：缺少 canary、版本庫 ID 不符或驗證錯誤時，作業必須失敗。
- 任何會刪除版本庫資料的動作，都必須使用明確命令，並在文件中說明影響範圍。
