# NTOU

國立臺灣海洋大學的學生 App。`spike/` 把登入與抓資料的流程打通之後，這裡是移植過來的 Flutter 版。

範圍：**學校選單上的 13 個模組（50 個功能）全部原生**，加上專屬的課表畫面。
成績不做（不在這個系統裡，見 `spike/README.md` 第七節）。

## 現在的狀態

```
dart analyze  ->  No issues found
flutter test  ->  107 passed
```

跑得起來的部分：登入流程（排隊關卡、驗證碼、frame 握手、派發器導向）、
13 個模組 50 個功能的通用驅動器、課表查詢與解析、離線快取、整套 UI。

**Android debug APK 在這個路徑上直接建得起來**（debug build 含全部 ABI 和除錯資訊）。

**還沒有裝到實體手機上跑過** —— 手機的 USB 偵錯授權要在手機上按，見「怎麼跑」。

## 工具鏈裝在哪

全部裝在使用者目錄下，**沒有一個需要系統管理員權限**
（JDK 的 MSI 要提權，所以改用 zip 版）：

| 東西 | 位置 |
|---|---|
| Flutter SDK 3.47.1 | `C:\Users\choue\flutter` |
| JDK 17（Microsoft OpenJDK） | `C:\dev\toolchain\jdk17` — 路徑刻意不含版號，JDK 更新時不用改設定 |
| Android SDK | `C:\dev\android-sdk`（platform-tools 37.0.1、platform 36 + 37.0、build-tools 36.1.0、NDK 28.2.13676358、CMake 3.22.1） |

`flutter config` 已經記住 Android SDK 和 JDK 的位置，所以 `flutter` 自己找得到。
要直接用 `adb` / `sdkmanager` 的話才需要設環境變數：

```powershell
$env:JAVA_HOME = 'C:\dev\toolchain\jdk17'
$env:ANDROID_HOME = 'C:\dev\android-sdk'
$env:Path = "C:\Users\choue\flutter\bin;$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:Path"
```

要一勞永逸就把 `C:\Users\choue\flutter\bin` 加進使用者的 PATH（不用管理員權限）：

```powershell
[Environment]::SetEnvironmentVariable('Path', [Environment]::GetEnvironmentVariable('Path','User') + ';C:\Users\choue\flutter\bin', 'User')
```

## 怎麼跑

測試與 lint（commit 前跑這個）：

```powershell
.\check.ps1
```

裝到手機上：

```powershell
.\run.ps1
```

`run.ps1` 會自己設好 `JAVA_HOME` / `ANDROID_HOME` / PATH（**刻意不改系統環境變數**），
先確認手機有沒有接上、有沒有授權，再跑 `flutter run`。
沒接手機或沒授權的話會直接告訴你缺哪一步，而不是丟一句 flutter 的通用錯誤。

手機要先開：設定 → 關於手機 → 連點「版本號碼」7 次 → 回到「開發者選項」→ 開 **USB 偵錯**。
插上線之後 USB 模式要選**檔案傳輸 / MTP**，只充電的模式 adb 看不到。
第一次會在手機上跳出 RSA 指紋的確認框，要按允許。

> **測試前先把瀏覽器上的 AIS 登出。** 一個帳號同時只能有一個 session，
> 沒登出的話 App 會被擋，而錯誤訊息（「一次僅許可一個帳號登入」）
> 看起來完全不像是這個原因。

## 架構

```
lib/src/
  ais/          spike/ais.py 的移植。WebForms 的舞步都在這層
    ais_session.dart   session client：排隊握手、JS 導向、VIEWSTATE、frame、登出
    forms.dart         表單欄位、onclick 副作用、選項驗證
    js_redirect.dart   這個系統換頁靠 JS 不靠 302，專門認那三種寫法
    origin.dart        站外導向防護
    decode.dart        編碼（AIS 是 UTF-8，有測試鎖住這個假設）
    page.dart          一次回應。**刻意沒有存檔、沒有印出 html 的路徑**
    exceptions.dart    每個例外都帶一句可以直接顯示的中文
    form_schema.dart   讀出「這一頁能做什麼」——通用驅動器的核心
  parsing/      spike/parsers.py 的移植。純函式，不碰網路
    tables.dart        GridView 解析 + rowspan/colspan 攤平
    data_grid.dart     通用查詢結果（欄名、列、分頁）
    timetable.dart     選課清單、上課時間、課表格線
    models.dart        Course / TimeSlot / TimetableResult
  menu/         13 個模組 50 個功能的目錄，含「會改資料」的標記
  planner/      預排課表的資料模型（做到一半，見「還沒做的」）
  config/       selectors.json 的型別化版本
  storage/      Keychain/Keystore（密碼）與 SharedPreferences（課表快取）
  data/         把上面接起來，UI 只跟這層講話
  ui/           畫面
```

`assets/selectors.json` 跟 `spike/selectors.json` 是同一份。
**所有會因為學校改版而爛掉的字串都在裡面**，之後接遠端設定就不用發新版 App。

## 50 個功能怎麼可能都原生

不為每一頁寫 parser。**讀頁面自己的宣告。**

這個系統的 50 個功能頁是同一套產生器做出來的，而且每樣東西都標好了：

| 頁面上的宣告 | App 拿來做什麼 |
|---|---|
| `<select name="Q_AYEAR" CNAME="學年度">` | 欄位的**中文標籤**（不是我們翻譯的） |
| `<option value="115">115</option>` | 下拉的選項（每年變動的東西不寫死在 App 裡） |
| `<input type=submit ml="CB_選課清單">` | 按鈕的中文文字 |
| `<title>TKE2211_課程課表查詢</title>` | 功能名稱（不一定有填，以選單為準） |
| `onchange="…__doPostBack('Q_DEGREE_CODE'…)"` | 這一格改了要重送（連動下拉） |
| `<table id="DataGrid">` | 查詢結果，照學校給的欄名和欄序畫 |

所以 `FunctionPage` 這一頁**沒有為任何特定功能寫過一行程式碼**，卻能正確畫出
50 個功能的查詢表單。學校加一個欄位、改一個標籤、多一顆按鈕，App 自動跟上。

代價是畫面比不上手工雕的。值得為特定功能做專屬畫面時再另外做 —— 課表就是。

**分頁式的頁面要照標籤頁分組。** 課程課表查詢是 jQuery UI tabs，同一頁擺了六套
互不相干的查詢條件（單位／關鍵字／開課老師／上課時間／教室排課／全英語課），
每套自己一顆送出鈕。攤平成一張表單的話，畫面上會出現**六顆都叫「查詢」**的按鈕，
十幾個欄位混在一起 —— 使用者不知道哪個配哪個。

分組依據一樣是頁面自己的宣告：DOM 的 `<div id="tabs-N">` 容器 +
標籤列的 `<a href="#tabs-N">單位查詢</a>`。送出時 `hdnSelectedTab` 要帶
**0-based** 的索引（容器 id 是 1-based，差一個就會拿別組的空欄位去查，
而回應是「查無符合資料」—— 看起來像沒資料，其實是問錯問題）。

三個必須特別處理的：

- **0 個 option 的下拉不能送。** 瀏覽器根本不送它，我們送空字串會被 ASP.NET 的
  event validation 擋掉，而錯誤只是一句通用的 403，完全看不出是哪個欄位。
  這種欄位在畫面上會顯示「要先選上面的條件」。
- **`type=button` 的列印鈕不收。** 它們的 `onclick="doPrint()"` 會先動
  `QUERY_COND` 和 `Q_AYEARSMS` 再送，不是單純的 postback。收進來而不重現那些
  副作用，按下去只會得到看不懂的 403。
- **不是每個欄位都有 `CNAME`。** 課程查詢的節次（`Q_CLASS`）就沒有。
  只認 `CNAME` 的話那一格會整個消失，而使用者只會覺得「時間查詢只能選星期」。
  所以還要退回去讀畫面上真正的標籤：`<span ml="PL_節次">節次</span>`。

## 會改資料的 11 個功能

線上加退選、申請休退學、申請住宿/換床、申請減免/就學貸款、申請抵免、
請假申請/取消/刪除、維護新生舊生資料、線上註冊、維護兵役資料、修改密碼。

點進去之前會跳一次提醒，講清楚這一頁會送出什麼。**不是擋** —— 是不要讓人在
選課期間手滑點進「線上加退選」。清單和判斷邏輯在 `menu/menu_catalog.dart`，
`menu_catalog_test.dart` 兩邊都鎖：該標的要標，純查詢的**不能誤標**
（誤標的代價是每次查課表都跳警告，久了就沒人看警告了）。

## 跟 spike 刻意不一樣的三個地方

### 一、登入例外不帶頁面

`ais.py` 的 `LoginFailed(msg, page)` 把登入回應掛在例外上，在 CLI 上很好用。
在 App 裡不行 —— Flutter 的 `FlutterError.onError`、Zone 的 uncaught handler、
任何崩潰回報 SDK 收走的都是 `toString()`，而**登入回應含兩次明文密碼**。

所以 `LoginFailed` 只帶 `diagnostics`：狀態碼、長度、有沒有導向。
足夠分辨「驗證碼打錯」和「學校改版了」，但沒有任何一個 byte 是頁面內容。
`test/password_leak_test.dart` 鎖住這件事。

### 二、`AisPage` 沒有 `save()`

spike 的 `Page.save()` 是拿來產 fixture 的。App 裡只要存在一條把 html 寫出去的路徑，
遲早會經過 log 或崩潰回報。所以那條路徑不存在。

### 三、上課時間解析不出來時，不猜

`一34` 可以是「第 3、第 4 節」，`一12` 可以是「第 12 節」也可以是「第 1、2 節」——
海大的節次編號是 00–16，兩種讀法都合法，**沒有線索可以判斷**。

猜錯的代價不對稱：課排到錯的格子，使用者看不出來，就這樣去錯的教室。
所以 `parseTimeSlots()` 只認明確的寫法（`一3,4`、`一3-4`、`星期二第3節`），
分不出來就回空的 —— 課仍然列在清單裡，只是不畫進格子，畫面上也會說明為什麼。

> **但目前這條路上根本沒有時間欄位可以解。** spike 在 2026-08-25 實測確認：
> 學校這個 UI 的清單檢視（`QUERY_BTN1`）回的 17 欄裡完全沒有上課時間和教室，
> 也沒有隱藏欄位。時間只存在於 Crystal Report 的課表檢視（`QUERY_BTN3`）。
>
> 所以 v1 的課表格子**實際上永遠不會有東西**，畫面上一律顯示清單 +
> 一句「學校的選課清單沒有附上課時間」。`parseTimeSlots()` 和 `TimetableGrid`
> 是為了 `QUERY_BTN3` 接上來之後準備的，現在是空轉的。
> 見下面「還沒做的」。

## 安全

架構紅線跟 spike 一樣，在 App 上更要緊：

- **密碼只存 Keychain / Keystore，爬蟲跑在裝置端。**
  一旦密碼經過自己的伺服器，就是在替全校學生保管帳密。
- iOS 的 `synchronizable: false` 是刻意寫出來的 —— 不同步到 iCloud Keychain。
- **登入回應永遠不進 log、不進例外、不落地。**
- `log` callback 只收得到 URL / 狀態碼 / 長度，而且只在 debug build 接上。

## 產品上要處理的事（不是技術問題）

**一個帳號同時只能有一個 session。** 使用者在電腦上開著選課系統時，App 一定登不進去。
處理方式：

- 課表抓到就存本機，開 App 先畫快取再更新，畫面上標明「還沒跟學校核對」
- **進背景兩分鐘之後才登出**（`AppController.backgroundGrace`）。
  一開始是「一離開前景就登出」，但那樣切出去看一眼訊息再回來就要重打驗證碼，
  太煩。兩分鐘是「切出去一下」和「不用了」的分界。
- 兩道防線，因為 **Android 會凍結背景的 App**，被凍住的 isolate 不會執行 Timer：
  1. `handlePaused()` 開一個兩分鐘的計時器 —— 能跑就跑
  2. `handleResumed()` 檢查實際經過多久 —— 這道一定會跑到
  3. `handleDetached()` 立刻登出，不等緩衝（要被關掉了，最後一次機會）

  三道都沒跑到（App 被系統直接殺掉）就只能靠學校自己的 session 逾時。
- 開 App 直接跳登入頁，是 `push` 的 —— 按返回就能退出去看快取的課表。
  學校系統掛掉或帳號在別處登著的時候，那是唯一還看得到的東西。

## 測試

```
test/
  js_redirect_test.dart      三種 JS 導向寫法 + 驗證碼重整不能誤判
  origin_test.dart           //portal.aspx 站外導向防護
  forms_test.dart            表單欄位規則、onclick 副作用、選項驗證
  tables_test.dart           rowspan / colspan 攤平、空結果判斷
  timetable_test.dart        時段解析（含「刻意不猜」）、課表格線、選課清單
  fixtures_test.dart         對著 spike/fixtures 的**真實頁面**測
  password_leak_test.dart    守門：頁面內容不能經由 toString 外流
  form_schema_test.dart      通用驅動器：從真實頁面讀出欄位/標籤/選項/按鈕
  postback_test.dart         連動下拉的 AutoPostBack 欄位偵測
  menu_catalog_test.dart     13 個模組的順序、會改資料的標記不能誤標
  timetable_page_test.dart   畫面：「沒課」和「出錯」必須長得不一樣
```

`fixtures_test.dart` 直接讀 `../spike/fixtures/`，**不複製一份進來** ——
複製等於在版控範圍內多開一個個資出口。檔案不在時整組 skip，跟 spike 的 pytest 一樣。

## 這台機器上的環境地雷

> **這一整節的根因都是同一個：專案路徑裡的「桌面」是非 ASCII，而且在 OneDrive 裡。**
> 搬到 `C:\dev\ntou-app` 一次解決全部。`C:\dev\finish-move.ps1` 會做完整件事
> （複製 → 比對 git HEAD → 驗證 venv → 把舊的改名保留）。
> 要先關掉 VS Code 和所有 Claude Code session，不然改名會失敗（"the item is in use"）。

**Android build 在這個路徑上直接掛掉 —— 這是硬性阻擋，不是警告。**

```
> Failed to apply plugin 'com.android.internal.application'.
   > Your project path contains non-ASCII characters. This will most likely cause
     the build to fail on Windows. Please move your project to a different directory.
```

AGP 自己拒絕跑。`gradle.properties` 加 `android.overridePathCheck=true` 可以繞過，
但 AGP 那句話說得很清楚：繞過之後**多半還是會在別的地方失敗**，
而那時候的錯誤訊息就不會這麼好懂了。不要繞，搬走。

**NDK 一定要先手動裝好，不能讓 Gradle 自己去裝。**
cmdline-tools 23 的 `sdkmanager` 只是新版 `android` CLI 的殼，而**新版只吃 `/` 分隔的
套件 id**（`ndk/28.2.13676358`）。Flutter 的 Gradle plugin 送的是舊語法：

```kotlin
// FlutterPluginUtils.kt:901
sdkmanager --sdk_root=... --install "ndk;$configuredNdkVersion"
```

新 CLI 把它拆成兩個名字（`Package ndk not found. Package 28.2.13676358 not found.`）
然後以 `0xC0000409` 當掉，Gradle 就報一句看不出原因的
`finished with non-zero exit value -1073740791`。

但同一個函式前面有這一段：

```kotlin
if (installedNdkVersions.contains(configuredNdkVersion)) return true
```

**所以只要 NDK 事先裝好，那段呼叫根本不會執行。** 已經裝好了
（`C:\dev\android-sdk\ndk\28.2.13676358`）。
順帶一提：把 `ndkVersion = flutter.ndkVersion` 從 `build.gradle.kts` 拿掉**沒有用** ——
`getConfiguredNdkVersion()` 會退回 Flutter 的預設值。實測過了。

**`android/build.gradle.kts` 把 library 子專案的 compileSdk 釘在 36。**
`flutter_secure_storage` 11 宣告 `compileSdk = 37`，AGP 就去找 hash string
`android-37`。但 Google 從 API 37 開始把平台改成有 minor 版本，只發了
`android-37.0` / `37.1`，**沒有平版的 `android-37`**：

```
Failed to find target with hash string 'android-37' in: C:\dev\android-sdk
```

而且 AGP 會先把 `android-37.0` 裝起來、然後才說找不到 `android-37`，
所以看起來像 SDK 沒裝好，其實是版號對不上。修正寫在
`android/build.gradle.kts`，**那段一定要放在 `evaluationDependsOn(":app")` 前面** ——
放後面的話 `:app` 已經求值完了，`afterEvaluate` 會丟
`Cannot run Project.afterEvaluate(Action) when the project is already evaluated`。

這是暫時的。Google 補上 `android-37` 或 plugin 改宣告之後就可以拿掉那一段，
判斷方式：刪掉、build 過就是修好了。

**`flutter analyze` 會崩潰，用 `dart analyze`。**
專案路徑是 `OneDrive\桌面\ntou-app`，裡面的「桌面」是非 ASCII。
Dart analysis server 走 LSP，它的長度標頭把 UTF-8 位元組當字元算，
訊息一被截斷就丟 `FormatException` 然後整個 server 掛掉（exit 255）。
`dart analyze` 不走 LSP，沒這個問題。`check.ps1` 用的就是它。

**`.ps1` 存檔要帶 UTF-8 BOM。**
PowerShell 5.1 看到沒有 BOM 的 `.ps1` 會當成 cp950 讀。中文註解的位元組被誤解之後，
Big5 的前導位元組會把後面那個字元吃掉 —— 剛好吃掉一個 `}` 的話，
錯誤訊息是 `The Try statement is missing its Catch or Finally block`，
指著一個看起來完全正常的地方。`check.ps1` 已經帶 BOM，改的時候不要弄掉。

**`flutter doctor` 會說「Android license status unknown」，可以不用理它。**
新版的 Android CLI 已經拿掉 `--licenses` 這個選項（它會回
「The --licenses option is no longer needed」），而 `flutter doctor --android-licenses`
就是去呼叫它，所以 Flutter 永遠問不到答案。真正的授權檔
`C:\dev\android-sdk\licenses\android-sdk-license` 是存在的，Gradle 讀的是那個。
**判準是 build 過不過，不是 doctor 的勾。**

**OneDrive 會鎖住 `build\`。**
偶爾會看到 `Flutter failed to delete a directory at "build\unit_test_assets"`。
刪掉 `build\` 再跑一次就好（`check.ps1` 每次都會先刪）。
搬出 OneDrive 之後就不會再遇到 —— 順帶也不用再讓 OneDrive 同步幾萬個建置產物。

## 還沒做的

- [ ] **還沒在真的手機上跑過。** 工具鏈已經齊了，接上手機打 `flutter run` 就行。
- [ ] **真正的課表格子要接 `QUERY_BTN3`（Crystal Report）。**
      現在用的 `QUERY_BTN1`（選課清單）**結構上就不含上課時間和教室**，
      不是抓漏也不是解析失敗。v1 因此只有清單，沒有格子。
      `QUERY_BTN3` 掛在 `__CRYSTALSTATECrystalReportViewer` 上，
      **輸出格式沒人驗證過**（可能不是 HTML 表格），而且要有修課資料才驗得了。
- [ ] `parseCourseList()` 的欄名 —— 這個帳號沒有修課資料，選課後要拿真實的
      個人清單回來對（目前是照全校課程查詢的欄位結構推的）
- [ ] `selectors.json` 改成從遠端拉（GitHub raw / Remote Config），
      學校改版時就不用發新版
- [ ] 成績 —— 不在這個系統裡，要另找入口
