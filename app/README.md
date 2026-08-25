# ntou_app

海大課表 App。`spike/` 把登入與抓資料的流程打通之後，這裡是移植過來的 Flutter 版。

第一版範圍：**登入 + 個人課表**。成績不做（不在這個系統裡，見 `spike/README.md` 第七節）。

## 現在的狀態

```
dart analyze  ->  No issues found
flutter test  ->  78 passed
```

跑得起來的部分：登入流程（排隊關卡、驗證碼、frame 握手、派發器導向）、
課表查詢與解析、離線快取、整套 UI。

**Android debug APK 已經建置成功**（162MB，debug build 含全部 ABI 和除錯資訊）。
但**不是在這個路徑上跑的** —— 「桌面」是非 ASCII，AGP 直接拒絕建置，
所以驗證是在 `C:\dev` 的拋棄式複本上做的。搬完之後這裡就能直接 build。

**還沒有裝到實體手機上跑過。**

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

裝到手機上（手機要開開發者選項 + USB 偵錯）：

```powershell
flutter devices
flutter run
```

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
  parsing/      spike/parsers.py 的移植。純函式，不碰網路
    tables.dart        GridView 解析 + rowspan/colspan 攤平
    timetable.dart     選課清單、上課時間、課表格線
    models.dart        Course / TimeSlot / TimetableResult
  config/       selectors.json 的型別化版本
  storage/      Keychain/Keystore（密碼）與 SharedPreferences（課表快取）
  data/         把上面接起來，UI 只跟這層講話
  ui/           畫面
```

`assets/selectors.json` 跟 `spike/selectors.json` 是同一份。
**所有會因為學校改版而爛掉的字串都在裡面**，之後接遠端設定就不用發新版 App。

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

> 這個帳號還沒有修課資料（轉學生），所以**還沒有人拿真實的「上課時間」欄對過**。
> 選課之後第一件事就是回來補上真實格式，然後這個函式就可以放心一點。

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
- App 進背景就登出，免得 App 掛著的 session 擋住使用者自己在瀏覽器登入
- 代價是回到 App 要重新打一次驗證碼。這是刻意的取捨 —— 課表看得到，
  擋住使用者選課則不能接受

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
- [ ] 個人課表的真實欄位 —— 這個帳號沒有修課資料，選課後要回來對
      `parseCourseList()` 的欄名和 `parseTimeSlots()` 的時間格式
- [ ] `selectors.json` 改成從遠端拉（GitHub raw / Remote Config），
      學校改版時就不用發新版
- [ ] 成績 —— 不在這個系統裡，要另找入口
