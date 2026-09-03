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
  lib/src/transit/  交通（TDX）—— 跟 AIS 無關，不用登入也能看
  test/             536 個測試
spike/          Python 探索腳本（有進版控）與真實擷取頁面（fixtures/*.html 不進）
```

## 不進版控的東西

**只有這些不在 git 裡**：`spike/fixtures/*.html`（真實擷取的頁面，含個資）、
`spike/fixtures/callbacks/`、`zeroday-submission.md`、`漏洞回報信稿.md`
（未公開的漏洞細節）、`.claude/settings.local.json`。

`spike/` 本身**有進版控** —— 那些 Python 腳本（`login.py`、`scrub.py`、
`check.py`、`parsers.py` 和它們的 pytest）、`README.md`、`selectors.json`、
`menu_tree.json` 都在。改了要一起 commit，而且 pre-commit hook 會跑 spike 的
pytest，那邊紅了就 commit 不進去。

`app/test/` 會直接讀 `../spike/fixtures/` —— 沒有那個資料夾時測試會自己 skip，
不會失敗。所以程式碼裡指向 `spike/` 的註解不是壞掉的參照，別「順手清掉」。

## 常用指令

Flutter **不在 PATH** 上（在 `C:\Users\choue\flutter\bin`），先加再跑：

```powershell
$env:PATH = "C:\Users\choue\flutter\bin;$env:PATH"
```

```bash
cd app && flutter analyze          # 應該是 No issues found
cd app && flutter test             # 475 個測試
```

裝到手機（Android，release 目前借用 debug key 簽章）：

```bash
cd app && flutter build apk --release --target-platform android-arm64 --dart-define=TDX_CLIENT_ID=<client id> --dart-define=TDX_CLIENT_SECRET=<client secret>
C:\dev\android-sdk\platform-tools\adb.exe install -r app/build/app/outputs/flutter-apk/app-release.apk
```

**漏掉那兩個 `--dart-define` 不會有任何錯誤**，交通分頁會安靜地變成
「交通資訊還沒開通」。金鑰哪裡來、為什麼用這個方式帶，見「交通資料」那節。

**不要用 `flutter install`。** 它會先 `Uninstalling old version...`，而移除會把
App 私有儲存整個清掉 —— 預排課表（`PlanStore`，存在 SharedPreferences）、
記住的帳密、課表快取全部不見，使用者要重新登入而且預排要重排。
`adb install -r` 是覆蓋安裝，簽章相同就會保留資料。

真的需要全新狀態時才用 `flutter install`（或 `adb uninstall`），而且要先講一聲。

## 交通資料（TDX）

交通分頁的資料來自交通部的 TDX，**跟學校的 AIS session 完全無關** ——
沒登入、甚至學校系統掛掉的時候那一頁照常能用。

海大那三個站牌（體育館、濱海校門、祥豐校門）是**基隆市公車**，不在台北市
政府的公車資料裡。台鐵、基隆市公車、國道客運現在都走 TDX 同一組 API，
註冊一次全通。

金鑰用 `--dart-define` 在 build 時注入，**不進版控**：

```powershell
$env:TDX_CLIENT_ID = "..."
$env:TDX_CLIENT_SECRET = "..."
```

這不是把 secret 藏起來 —— `--dart-define` 的值會編進 APK，反編譯挖得到。
TDX 免費金鑰最壞的下場是配額被別人用掉，這個代價收得起；真正該藏的東西
（學校密碼）走的是 Keystore，不是這條路。值得這樣做的理由只有一個：
金鑰不會進 git，不會跟著原始碼被推上去。

`app/assets/transit.json` 跟 `selectors.json` 同樣的用意 —— 端點路徑、
站牌名、狀態碼對照全在裡面，Dart 裡一個都不寫死。**TDX 的公開 swagger 在
schema 那段是截斷的**，所以欄位名一開始全是候選清單而不是單一答案。
拿到金鑰之後跑 `spike/tdx.py` 對真實回應驗證，它會印出實際欄位名、
以及哪一個候選命中。**對過之後才可以把候選清單收斂成一個。**

### 對到哪了（2026-09-03）

**公車和台鐵都對完了**，`_busFrom` / `_trainFrom` 都已經收斂成確定的欄位名。
真實回應存在 `spike/fixtures/tdx/`（公開資訊，沒個資，**進版控**），
`transit_test.dart` 拿它們把解析釘死。

對出來的四件事，每一件都是「猜錯不會有錯誤訊息」的那種：

- **台鐵表定時間是 `ScheduleDepartureTime`，不是 `ScheduledDepartureTime`**
  —— 少一個 d。原本三個候選全部落空，那一欄解析出空字串，而它是列車那一列
  右邊的主角。測試當初也寫著同一個不存在的名字，所以兩邊講好了一個謊，
  一直是綠的。

- **`StopCountDown` 是「還有幾站」，不是秒數**（`EstimateTime: 725` 配
  `StopCountDown: 19`）。當成秒數的備援，19 站會顯示成「19 秒 → 進站中」。
- **`EstimateTime` 是選擇性欄位**，只有真的有車的那筆才有。深夜 15 筆裡
  只有 1 筆帶著它 —— 所以「沒有這個 key」是常態，不是解析失敗。
- **`DestinationStop` 是 StopID 不是站名**（`"306195"`）。所以「往哪裡」
  那一欄目前一律空白，要補得另外去查路線資料，**還沒做**。

台鐵基隆站的 `station_id` 現在是查證過的 `0900`。在那之前它刻意留空 ——
**填一個猜的代碼會安靜地查出別站的車**，畫面上一切正常，只是列車全是別的
地方的。要改動它就得重跑一次 `spike/tdx.py`。

基隆是**端點站**，抓到的列車 `EndingStationID` 全都是 `0900`（基隆自己）。
照著印會變成站在基隆站看到「往 基隆」，所以終點等於本站時改說「本站為終點」。

### 「往哪裡」是拼出來的，不是 API 給的

到站資料**沒有終點站名**，只有 `DestinationStop`（StopID）。畫面上的
「往 八斗子車站」是拿 `RouteUID` 去路線資料查這條路線的兩頭，再靠
`Direction` 挑一邊補上的：**0 是去程看終點欄位、1 是返程看起點欄位**。

這個對應關係**弄反了不會有任何錯誤** —— 畫面上是一個看起來完全合理的
站名，只是方向相反，使用者照著搭反邊。所以它是對過真實資料才寫進去的
（基隆市公車七筆 Direction 0 全中終點欄位；國道客運那邊基隆轉運站
StopID `309639` 在八條路線上的位置完全一致），而且**認不得的 Direction
寧可留白也不猜**。

路線的起訖站查過就整個 session 快取，查不到的也記起來 —— 這一頁每 30 秒
重整一次，每次都重問一輪就是拿 429 換一份不會變的資料。

### 刷新頻率不要再調快

30 秒不是隨便訂的。台鐵回應的外層自己帶著 `UpdateInterval: 30`、
`SrcUpdateInterval: 60` —— **資料在 TDX 端每 30 秒才換一次**。調成 15 秒
只會把同一份資料抓兩次，請求量翻倍、429 風險翻倍，畫面上的數字一個都不會
提早變。


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

- 節流：內建，不要把學校的機器打爛。**而且節流必須是佇列，不能是「每個
  請求各自看上一次是什麼時候」** —— 後者對併發完全無效：同時發出的幾個
  呼叫會讀到同一個舊時間、同時通過檢查、同時打出去。交通頁就是這樣在真機上
  炸成五張「服務忙碌中」的（TDX 回 429），而在此之前它看起來一直是有節流的
- `selectors.json`：任何會因學校改版而爛掉的字串都寫在這裡，程式碼裡不寫死
- 註解寫中文，說明「為什麼」而不是「做了什麼」——尤其是學校系統的反直覺行為
- UI 文字對使用者講人話，不要解釋 App 或伺服器的內部運作
