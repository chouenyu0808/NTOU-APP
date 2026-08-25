# ntou-app

國立臺灣海洋大學學生 App。接教學務系統（`ais.ntou.edu.tw`）做原生課表。

## 現在的狀態

還在 spike 階段。**先用 Python 把登入與抓資料的流程打通**、把頁面存成 fixture、
把 parser 寫成純函式並鎖上測試，確認整條路徑可行之後才移植到 Flutter。

在 App 裡 debug WebForms 的 `__VIEWSTATE` 是地獄，在這裡改一行跑一次是三秒。

- [`spike/`](spike/) — Python 逆向與 parser。**完整技術文件在 [spike/README.md](spike/README.md)**
- Flutter App — 還沒開始（SDK 未安裝）

## 已經打通的

登入（含虛擬排隊關卡、驗證碼）、選單樹遞迴展開（50 個功能）、
功能頁的派發器導向、課表頁路徑。

## 已知的限制

- **成績查詢不在這個系統裡。** 學生選單 50 個功能全部查過，沒有學期成績。要另找入口。
- **一個帳號同時只能有一個 session。** 學生在網頁登入時，App 抓不到資料 ——
  這是產品設計上要處理的，不是能繞過的技術問題。
- 學校系統會把登入密碼明文回吐到回應 HTML 裡。
  所以**登入回應永遠不能進 log 或崩潰回報**。

## 架構紅線

密碼只存 iOS Keychain / Android Keystore，爬蟲跑在**裝置端**。
一旦密碼經過自己的伺服器，就是在替全校學生保管帳密。

## 開發

```powershell
cd spike
.venv\Scripts\python.exe check.py
```

`check.py` 是 commit 前的把關：個資掃描 → 測試 → lint。
個資檢查刻意排第一 —— 測試紅了只是重跑，密碼推上遠端就救不回來了。
