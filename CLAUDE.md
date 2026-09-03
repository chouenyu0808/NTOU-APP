# NTOU App

海大教務系統（`ais.ntou.edu.tw`）的 Flutter App。學校端是 ASP.NET WebForms，
App 用 HTTP session 直接操作它，不套 WebView。

## 回覆語言

用**繁體中文**回覆、摘要、問問題。技術名詞（`git add`、adaptive icon、
`__VIEWSTATE`、檔名、指令）保持原文不要硬翻。程式碼註解、commit 訊息、
UI 文字、測試的 `group`/`test` 名稱在這個 repo 裡一律是中文。

## 這個 repo 同時有多個 Claude session 在動

**這是最重要的一節。** 已經因此出過兩次事，兩次的方向相反：

### 1. 絕不 `git add -A` / `git add .`

有 session 在根目錄跑了 `git add -A`，把另一個 session 96 個未 commit 的
`app/` 檔案掃進一個講掃描器的無關 commit，push 出去才被發現，而且沒辦法改寫
歷史（對方還在那些檔案裡工作）。

- 只 stage 自己這個 session 動過的路徑：`git add app/test/foo.dart`
- commit 前重跑 `git status`，逐一確認每個 staged 路徑都是自己改的
- 工作樹裡有你沒動過的改動 → **原封不動留著並說出來**，不要 commit 也不要還原
- 不要主動 commit，等使用者說

### 2. 動過的檔要盡快 commit

有 session 建 release APK 裝到使用者手機，那份 APK 含著另一個 session
當時還沒 commit 的改動。他不知道，所以他 commit 訊息裡寫的「使用者回報修好了」
其實是在「他的修正 + 別人的修正」上驗的。

**在這個 repo 裡「未 commit」不等於「還沒生效」** —— build 會把工作樹的內容
一起編進去，而 git 完全看不到。任何一個 session 做 checkout 就會把它弄丟，
症狀突然變回來，沒人知道為什麼。

- 交付 build 之前先看 `git status`：跑出別人的檔就先問，別假設 build 的是 HEAD
- 別人回報「裝上去好了」時，想一下他驗的到底是哪個組合

## 專案結構

```
app/            Flutter 專案（幾乎所有工作都在這）
  lib/src/ais/      學校 WebForms session client（登入、表單、postback）
  lib/src/parsing/  HTML → 資料模型
  lib/src/ui/       畫面
  lib/src/config/   selectors.json —— 所有會因學校改版而爛掉的字串都在這裡
  test/             444 個測試
spike/          Python 探索腳本與真實擷取頁面（**不進版控**）
```

## 不進版控的東西

`spike/`、`zeroday-submission.md`、`漏洞回報信稿.md` 都不在 git 裡，因為含
真實擷取的頁面和未公開的漏洞細節。但 `app/test/` 會直接讀 `../spike/fixtures/`
—— 沒有那個資料夾時測試會自己 skip，不會失敗。所以程式碼裡指向 `spike/` 的
註解不是壞掉的參照，別「順手清掉」。

## 常用指令

Flutter **不在 PATH** 上（在 `C:\Users\choue\flutter\bin`），先加再跑：

```powershell
$env:PATH = "C:\Users\choue\flutter\bin;$env:PATH"
```

```bash
cd app && flutter analyze          # 應該是 No issues found
cd app && flutter test             # 444 個測試
```

裝到手機（Android，release 目前借用 debug key 簽章）：

```bash
cd app && flutter build apk --release --target-platform android-arm64
C:\dev\android-sdk\platform-tools\adb.exe install -r app/build/app/outputs/flutter-apk/app-release.apk
```

**不要用 `flutter install`。** 它會先 `Uninstalling old version...`，而移除會把
App 私有儲存整個清掉 —— 預排課表（`PlanStore`，存在 SharedPreferences）、
記住的帳密、課表快取全部不見，使用者要重新登入而且預排要重排。
`adb install -r` 是覆蓋安裝，簽章相同就會保留資料。

真的需要全新狀態時才用 `flutter install`（或 `adb uninstall`），而且要先講一聲。

## 安全紅線

學校系統**登入回應裡含兩次明文密碼**。因此：

- 密碼只存在記憶體與 Keychain / Keystore，絕不寫檔、絕不進 log
- 登入回應永遠不進 log、不進例外、不落地
- 例外不要掛整頁 HTML（`LoginFailed` 刻意不帶 page，見 `exceptions.dart`）
- fixture 在寫檔當下就要洗過（`spike/scrub.py`），`password_leak_test.dart` 守這條
- 不要把 `e.toString()` 丟給使用者：dio 的訊息裡有完整 URL 和堆疊

驗證碼**不做 OCR 自動送出**。圖是一次性的、學校的失敗是靜默的，加上會認錯的
OCR 就是一個使用者插不進手的重試迴圈。輸入框任何時候都能手動編輯。

## 寫程式的慣例

- 節流：內建，不要把學校的機器打爛
- `selectors.json`：任何會因學校改版而爛掉的字串都寫在這裡，程式碼裡不寫死
- 註解寫中文，說明「為什麼」而不是「做了什麼」——尤其是學校系統的反直覺行為
- UI 文字對使用者講人話，不要解釋 App 或伺服器的內部運作
