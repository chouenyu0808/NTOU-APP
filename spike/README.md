# NTOU AIS spike

先用 Python 把海大教學務系統（`ais.ntou.edu.tw`）的登入與抓資料流程打通，
確認可行、把 HTML 存成 fixture、把 parser 寫成純函式並鎖上測試，
**之後才移植到 Flutter**。

在 App 裡 debug WebForms 的 `__VIEWSTATE` 是地獄，在這裡改一行跑一次是三秒。

## ⚠️ 先看這個：系統會把密碼明文回吐

**任何一次登入 POST 的回應**（成功或失敗都一樣）HTML 裡，你的密碼會以**明文**出現兩次：

```html
<script>var keyObj = {LoginPWD:'你的密碼'};</script>
...
<script>_i(0, 'LoginPWD').value = '你的密碼';</script>
```

這是校方系統的行為，不是這個 spike 造成的。後果：

- 任何存下來的回應（fixture、log、HTTP debug proxy、瀏覽器開發者工具的 Network 頁籤）
  都含明文密碼
- 密碼會留在瀏覽器 DOM 裡，任何在該頁執行的第三方 script 都讀得到
- **做 App 時絕對不要把登入回應整包寫進 log 或崩潰回報**

三道防線：`login.py` 存檔時就完整洗掉（密碼根本不落地）、`scrub.py --check` 是 commit 前的第二道、
`test_ais.py` 有守門測試擋住含密碼的 fixture 被 commit。

這值得寄信給圖資處校務系統組回報。

## 目前進度

- [x] TLS 連線（要用 OS 憑證庫）
- [x] 登入頁欄位名
- [x] 排隊關卡握手流程
- [x] 驗證碼圖片抓取
- [x] **登入 POST 成功**（2026-08-25 實測）
- [x] 登入成功的判斷方式（JS 導向，不是 302，也不是找字串）
- [x] 登入後的落地頁結構（`MainFrame.aspx` 是 frameset）
- [x] `MenuTree.aspx` 選單解析 + TreeView 延遲載入 callback
- [x] 選單第一層（13 個模組）與 `Application/<模組>/<代碼>_.aspx` 路徑格式
- [x] callback 封裝與 `__EVENTVALIDATION` 換發（第二層展不開的真因）
- [x] 遞迴展開整棵選單（50 個功能，存在 `fixtures/menu_tree.json`）
- [x] 找到課表路徑
- [x] 功能頁的派發器導向（`_.aspx` -> `_01.aspx`）
- [x] 課表 parser 支援 rowspan / colspan（連堂課）
- [ ] 抓真實課表頁、對著 fixture 調 parser ← **現在做這個**
- [ ] 成績 —— **不在這個系統裡**（見第七節）

`.venv\Scripts\python.exe -m pytest -q` → 87 passed, 2 skipped
（skip 的是還沒抓到的課表 / 成績 fixture）
`.venv\Scripts\python.exe check.py` → 3 項全過（個資 / 測試 / lint）

## 登入流程（實測，不是猜的）

### 一、排隊關卡

AIS 在登入前擋了一層**虛擬排隊**：

| 步驟 | 回應 | 登入表單 | 驗證碼 `src` |
|---|---|---|---|
| 1. `GET Default.aspx` | 21992B，含 `location.href='DefaultQ.aspx'` | 有 | **無** |
| 2. `GET DefaultQ.aspx` | 20651B，排隊頁 | — | — |
| 3. `GET Default.aspx` | 21988B | 有 | **有** |

第 1 步拿到的頁面**看起來**是完整登入頁 —— 帳號、密碼、驗證碼欄位都在，
但驗證碼 `<img id="importantImg">` **沒有 `src` 屬性**。
瀏覽器會被第 1 行的 JS 導去排隊頁，排完再回來，這時候伺服器才產生驗證碼圖。

`requests` 不跑 JS，所以直接 POST 只會拿到「驗證碼錯誤」，而且你會找不到原因 ——
因為頁面上根本沒有圖可以看。`ais.open_login_page()` 已經把這三步包好了。

> 排隊機制是選課尖峰保護伺服器用的。**照著走，不要繞過。**

### 二、欄位

| 用途 | `name` | 備註 |
|---|---|---|
| 帳號 | `M_PORTAL_LOGIN_ACNT` | |
| 密碼 | `LoginPWD` | 明文 POST，前端**沒有**做雜湊 |
| 驗證碼 | `M_PW2` | 4 碼，**區分大小寫** |
| 登入鈕 | `LGOIN_BTN` | value=`登入/Login`（校方自己拼錯成 LGOIN，照抄） |

驗證碼圖是伺服器產的實體檔：`/Temp/Captcha/<每個 session 隨機>.png?t=<timestamp>`，
檔名每次都不同，**一定要從頁面上抓，不能寫死**。不要做 OCR。

### 三、怎麼判斷登入成功

**這裡最容易踩雷。** 登入成功時伺服器**不回 302**，而是回一頁 JS：

```javascript
top.location.href = 'MainFrame.aspx';
```

成功的回應（22101B）跟登入頁（21988B）長得幾乎一模一樣 —— 一樣有登入表單、
一樣有新的驗證碼圖 —— **只差那一行導向指令**。

所以用「找 `登出` 字串」判斷成功是錯的，會把成功誤判成失敗。
`ais.js_redirect_target()` 負責抓這個。

失敗時系統**不給任何錯誤訊息**，只是重畫登入頁配一張新驗證碼。
失敗的回應 22063B、成功的 22101B —— **只差 38 bytes**，但失敗的完全沒有
`location.href` 導向指令。這是區分兩者唯一可靠的訊號。

### 四、登入後的站台結構

`MainFrame.aspx`（9762B，`__VIEWSTATE` 是 0B）**只是個框架容器**，
沒有任何 `__doPostBack` 目標 —— 別在這頁找選單。真正的內容在 iframe 裡：

| frame name | src | 用途 |
|---|---|---|
| `titleFrame` | `title.aspx?XX=<數字>` | 標題列 |
| **`menuFrame`** | **`MenuTree.aspx`** | **選單 —— 課表 / 成績的入口在這** |
| `mainFrame` | `portal.aspx` | 內容區 |
| `timeoutFrame` | `timeout.aspx` | session 逾時計時器 |

用 `login.py --fetch MenuTree.aspx` 在同一個 session 內把它抓下來。
（`probe.py` 抓不到 —— 它每次都開新 session，沒有登入狀態。）

### 五、選單是延遲載入的 TreeView

`MenuTree.aspx` 的初始 HTML **只有第一層 13 個節點**，子項目要靠 ASP.NET 的
client callback 才拿得到 —— 不是 postback，回傳的也不是 HTML 而是一段原始字串。

節點連結長這樣（注意 JS 寫在 `href` 屬性裡，引號被編碼成 `&#39;`）：

```javascript
TreeView_PopulateNode(Menu_TreeView_Data, 1, ..., '教務系統', 'NTOU\\STU', 'f', '', 'tf')
```

`__CALLBACKPARAM` 的組法抄自 `WebResource.axd` 裡的 TreeView 實作，**不是猜的**：

```
index | lastIndex | databound+isChecked+parentIsLast | len(text) | text+len(datapath) | datapath+path
```

教務系統那個節點就是 `1|19|fftf|4|教務系統0|NTOU\STU`
（JS 字面值裡是兩個反斜線，unescape 之後送出去的是一個）。
這個字串錯一個字元選單就展不開，所以 `test_parsers.py` 有測試鎖住它。

第一層的 13 個模組：教務系統(`STU`)、暑修作業(`SUM`)、學生宿舍(`SDM`)、
校外租賃(`SDO`)、就學貸款(`SAC`)、學生請假(`SEC`)、社團活動(`CAS`)、
兵役(`SMM`)、新生體檢(`PHY`)、體育室辦證(`SCM`)、SDGs(`SDG`)、
電子公布欄(`BBS`)、校內資訊系統(`MAP`)。

功能頁的路徑格式是 `Application/<模組>/<子模組>/<代碼>_.aspx?progcd=<代碼>`，例如
`Application/SEC/SEC20/SEC2050_.aspx?progcd=SEC2050`（學生請假查詢）。

**課表和成績在更深一層。** `教務系統` 展開後是 4 個還可以再展開的節點：
學生基本資料維護作業、選課系統、抵免/免修作業、休/退/復學作業。
所以 `--menu` 是遞迴的，預設展開 3 層（`--menu-depth` 可調）。

### 六、callback 每次都換發 __EVENTVALIDATION

**這裡卡最久，而且錯誤訊息完全沒有幫助。** 症狀：第一層 13 個節點全部展得開，
第二層一律回 9 個字元 `e回呼中發生錯誤。`。

原因是 callback 的回應有**兩層封裝**，我原本只看到內層。真實格式
（抄自 `WebForm_ExecuteCallback`）：

```
's' + 結果                                    成功，沒換驗證欄位
'e' + 訊息                                    伺服器端拋例外
<驗證欄位長度> + '|' + <新的 __EVENTVALIDATION> + 結果
```

實際抓到的回應開頭長這樣：

```
476|RPPeLglyMy1RYHsh…（476 字元的 base64）…=23|cccc|<div id="Menu_TreeViewn1Nodes"…
```

`476` 是**驗證欄位的長度**，不是 TreeView 的 lastIndex。
剝掉外層之後，內層才是 `23|cccc|<div…`。

我原本把 `476` 當成 lastIndex、把那串 base64 當成 ExpandState 送回去，
參數自然全錯。**而且更關鍵的是：那個新的 `__EVENTVALIDATION` 必須沿用。**

第一層之所以會過，是因為那些節點的參數已經註冊在原始頁面的 event validation 裡；
第二層節點的參數是伺服器在回應第一層時才註冊的，繼續送舊的驗證欄位一定被拒。

`ais.callback()` 現在會自動剝外層、更新 `__EVENTVALIDATION`、把伺服器錯誤
轉成 `CallbackError`。內層的 TreeView 格式由 `parse_callback_response()` 處理：

```
<新的 lastIndex>|<新增的 ExpandState>|<HTML 片段>
```

瀏覽器收到後還會做三件事，一件都不能漏：

```javascript
data.lastIndex     = 內層第一段        // 讀回來，不是自己算
expandState.value += 內層第二段        // 累加
populateLog.value += index + ","      // 累加
```

所以選單走訪是**循序有狀態**的，不能平行化。

教訓：這個系統的失敗全都是靜默的。卡住的時候先把原始回應 dump 出來看，
不要憑推理猜 —— 我在這裡猜錯兩次，dump 出來三分鐘就定案。
`--save` 會把每次 callback 的送出參數與原始回應寫進 `fixtures/callbacks/`。

### 七、課表在哪、成績不在哪

選單全部展開後（50 個功能，`fixtures/menu_tree.json`）：

| 功能 | 路徑 |
|---|---|
| **個人課表** | `Application/TKE/TKE22/TKE2240_.aspx?progcd=STU1220` |
| 課程課表查詢（全校） | `Application/TKE/TKE22/TKE2211_.aspx?progcd=STU1250` |
| 歷年課程課表查詢 | `Application/TKE/TKE22/TKE2210_.aspx?progcd=STU1190` |
| 查詢必修科目表 | `Application/ENR/ENRA0/ENRA120_.aspx?progcd=STU1101` |
| 線上加退選 | `Application/TKE/TKE20/TKE2011_.aspx?progcd=STU1010` |

個人課表在「教務系統 > 選課系統 > 學生個人選課清單課表列印」。

> **線上加退選是會改變資料的頁面。** 開發時只讀取、絕對不要自動送出。

**成績查詢不在 `ais.ntou.edu.tw` 的學生選單裡。** 50 個功能全查過，唯一含「成績」
兩個字的是「英檢成績申請抵免/免修課程」，那是拿英檢成績去抵學分，不是學期成績。

所以 App 想做成績就得另外找入口 —— 那是獨立的目標，不是這個 spike 的延伸。
`selectors.json` 的 `pages.grades.path` 目前是 `null`，不要當成待填的 TODO。

### 八、登入握手要載完 frame

**功能頁在載完 frame 之前一律被擋。** 症狀是被導到 `ConfirmInOrOut.aspx`
（「系統同時一次僅許可一個帳號登入」），很容易誤判成「舊 session 沒登出」——
我就誤判了兩次。

實測對照：

| 路徑 | 結果 |
|---|---|
| 登入 → `MenuTree.aspx` → 展開選單 | 成功 |
| 登入 → 直接抓 `Application/…` | 被擋 |
| 登入 → 載完四個 frame → 抓 `Application/…` | **成功** |

`MainFrame.aspx` 是 frameset，瀏覽器載完它會接著載 `title` / `MenuTree` /
`portal` / `timeout` 四個 frame。直接跳去功能頁等於握手只做一半。
`--menu` 那條路徑之所以會過，是因為它剛好碰到了 `MenuTree.aspx`。

`ais.enter_portal()` 照瀏覽器的行為把 frame 載一遍，`--no-frames` 可以關掉做對照。

> 順帶更正一個中途的錯誤推論：`LogOut.aspx` **本來就會清 session**。
> 有 session 時回 48B 導向 `Logout.htm`，沒有時回 50B 導向 `Default.aspx` ——
> 回應不同就是它有做事的證據。`Logout.htm` 只是靜態確認頁。

### 九、功能頁都是派發器

選單給的 `Application/<模組>/<子模組>/<代碼>_.aspx?progcd=<代碼>` **不是內容頁**。
直接 GET 只會拿到 1.4KB 的空殼，裡面就一行：

```javascript
top.mainFrame.location.href='TKE2240_01.aspx';
```

它的作用是註冊 session 狀態，然後叫框架去載真正的 `_01.aspx`。
所以每個功能頁都要跟一次導向 —— `sess.follow_js_redirect()` 負責這件事，
`--fetch` 和 `--fetch-all` 都會自動跟。

導向目標是**相對於該頁的 URL**，不是相對於 base_url ——
功能頁埋在 `Application/TKE/TKE22/` 這種深層目錄，用 base_url 解析會跑到根目錄。

> **站外導向防護。** `MenuTree.aspx` 裡有一行
> `top.mainFrame.location.href = "//portal.aspx"` —— 校方少打一條斜線，
> 本意是 `/portal.aspx`。但 `//portal.aspx` 是協定相對 URL，
> `urljoin` 會解析成 `https://portal.aspx`，**一個站外主機**。
> 自動跟隨就會把帶 session cookie 的請求送出去，而那個網域誰都能註冊。
> `follow_js_redirect()` 有 `same_origin()` 檢查，不同源直接停下並警告。

### 十、查詢頁：填欄位再按按鈕

`TKE2240_01.aspx` 拿到的**不是課表，是查詢表單**：

| 欄位 | 預設 | 說明 |
|---|---|---|
| `Q_AYEAR` | `115` | 學年（105–116） |
| `Q_SMS` | `1` | 學期 |
| `QUERY_BTN1` | | 選課清單 |
| `QUERY_BTN3` | | 選課課表（Crystal Reports，輸出格式未驗證） |

按鈕的 `onclick="return doQuery()"` 只做欄位驗證，不會偷塞值，直接 postback 即可。
（`doPrint()` 才會動 `QUERY_COND` 和 `Q_AYEARSMS`，那是列印用的。）

用 `--set` / `--submit` 送出，`--sweep` 可以在**同一次登入內**掃過多組條件 ——
每次登入都要人工打驗證碼，一次猜一個學期太貴。

> **查無資料時狀態碼一樣是 200**，只有一行「查無符合資料!!」不同。
> `parsers.is_empty_result()` 專門認這個 —— 不認得的話會以為 parser 壞了，
> 然後跑去 debug 錯的東西。

**目前這個帳號沒有修課資料。** 2026-08-25 實測 113-1 ~ 115-2 六個學期全空
（轉學生，尚未在本校選課）。查詢參數確認有生效 —— 六個回應各自帶回對應的
學年學期、內容雜湊全不同，所以是真的沒資料，不是查詢沒送出去。

所以**個人課表 parser 要等選課後才能對真實資料調**。
在那之前用「課程課表查詢」（`TKE2211_.aspx?progcd=STU1250`）——
那是全校課程，跟有沒有選課無關。

### 十一、課程的上課時間：點課號**不會換頁**

查詢結果那張表有 17 欄（序號／學期／課號／課名／開課單位／年級班別／授課老師／…），
**沒有上課時間那一欄**。時間只在點課號進去的課程內容頁裡。

而「點課號」不是你以為的那樣 —— 它是 `__doPostBack('DataGrid$ctl02$COSID','')`，
但回應**不是詳細頁**，而是**同一份 HTML**，只多注入一行 JS。
實測整份回應只差 3 個 byte：

```
- Message.hideProcess();
+ fn_open('137171415','1');
```

`fn_open()` 定義在頁面上，它做的是開一個 lightbox：

```javascript
function fn_open(pkno, lesson_type) {
    doOpenFancyBox('', '800', '600',
        '/Application/TKE/TKE22/TKE2240_03.aspx?PKNO=' + pkno + '&LESSON_TYPE=' + lesson_type + '#');
}
```

所以完整流程是**三步**：postback → 從回應裡抽出 `PKNO` → **普通 GET** 那一頁。
`login.py --goto` 會自動走完後面兩步。

停在第二步就找「上課時間」是抓不到的 —— 查詢頁上的「上課時間」
全是分頁標籤「上課時間查詢」（`#tabs-4`）。症狀是「每一門課都沒有時間」。

三個會讓你拿到錯資料而且不會報錯的地方：

1. **課程內容頁自己帶著一行指向 `/Portal.aspx` 的 JS。**
   跟下去會把剛拿到的 57KB 內容整份換成首頁。直接給內容頁網址時用 `--no-follow`。

2. **`PKNO` 是純 9 碼數字**（`137171415`），不是課號（課號是 `B57011RQ`）。
   它正好符合 `scrub.py` 的學號樣式，存進 fixture 會被洗成 `B10900000` ——
   **不能事後從 fixture 讀 PKNO**，讀出來的是佔位值，拿去 GET 只會得到
   一頁 `Mode=ADD` 的空表單（每一格都是空的，但版面完全正常）。

3. **同一個課號常常有好幾列。** `B57011RQ 計算機概論` 同時有
   「1年A班／許為元」和「1年B班／林韓禹」，上課時間不一樣。
   只比課號會固定拿第一列。

內容頁的值都在有 id 的 span 裡，伺服器算好塞進去（**沒有 callback、沒有 ajax**）：

```html
<span id="M_SEG"       CNAME="時間">102,103,104</span>
<span id="M_CLSSRM_ID" CNAME="教室代號">INS105,INS105,INS105</span>
```

`102` = 星期一（第一碼，同 `Q_WEEK`）第 02 節（後兩碼，同 `Q_CLASS`，範圍 `00`–`16`）。

> **一定要讀 `#M_SEG`，不要掃頁面文字。** 隔壁的教室代號 `INS105` 裡的 `105`
> 就是合法的時間代碼（週一第 5 節）—— 掃文字會憑空多排一節課出來。

### 十二、分頁式頁面有**兩套**機制

| | 錨點式 | 按鈕式 |
|---|---|---|
| 例子 | `TKE2211`（課程課表查詢，6 組） | `ENR3030`（維護新生資料，8 組） |
| 標籤 | `<a href="#tabs-1">單位查詢</a>` | `<input type="button" id="TabBtn1" ml="CB_基本資料">` |
| 內容 | `<div id="tabs-1">` | `<div id="TabCnt1">`（非作用中 `style="display:none"`） |

只認錨點式的話，`ENR3030` 的 8 組會攤平成同一畫面：
**16 顆按鈕、其中 14 顆都叫「存檔」**，而瀏覽器實際只顯示 3 顆。
那還是一頁會真的寫學籍資料的表單。

按鈕標籤的前綴也不只 `CB_`：同一頁上有 `ml="PL_填寫範例說明"`，
只剝 `CB_` 的話畫面上會出現「PL_填寫範例說明」。

就算分好組，每一組**還是有兩顆「存檔」** —— 長表單會在最上面和最下面各放一顆。
分辨「同一個動作放兩次」和「兩個不同的動作」要看 `onclick`，光看標籤分不出來：

```
SAVE_BTN1  onclick="return doSave();"                              ← 同一個動作
SAVE_BTN2  onclick="return doSave();"                              ←

QUERY_BTN1 onclick="return doQuery('1');"                          ← 六個不同的查詢
QUERY_BTN7 onclick="return doQuery('2');"                          ←

DEL_BTN1   onclick="return doDelete('DataGrid','chkBox','CHECK');" ← 各自不同
TMP_SAVE_BTN onclick="return doStcollateralSave();"                ←
```

所以去重的鍵是**（標籤, onclick）**，而且只能在同一組裡比 ——
每個標籤頁都有自己的存檔鈕，跨組去重會把第二頁之後的存檔全部吃掉。

## 檔案

| 檔案 | 用途 |
|---|---|
| `ais.py` | session client：排隊握手、JS 導向、callback 封裝、VIEWSTATE、TLS、編碼 |
| `probe.py` | 探測頁面欄位結構，**取代手動開 DevTools 抄 input name** |
| `login.py` | 登入；`--menu` 展開選單、`--fetch-all` 一次抓完所有唯讀頁 |
| `parsers.py` | 純函式：HTML → `Course` / `Grade` / `MenuNode`。不碰網路 |
| `scrub.py` | 洗掉學號、姓名、身分證、IP、**回吐的明文密碼** |
| `selectors.json` | **所有會變的東西都在這**。之後就是 App 的遠端設定檔 |
| `test_parsers.py` | parser 回歸測試（含 rowspan / colspan、選單、callback 格式） |
| `test_ais.py` | 登入判斷、callback 封裝、密碼外洩守門測試 |
| `test_login.py` | `--fetch-all` 的安全性：不能掃到會改資料的頁面 |
| `check.py` | commit 前的把關：個資 → 測試 → lint，一個指令 |
| `test_check.py` | 把關掃描本身的測試（誤報會擋到整個 repo，包含 app/） |
| `pyproject.toml` | ruff 設定。每條 ignore 都寫了為什麼 |
| `_console.py` / `.venv/…/sitecustomize.py` | Windows 中文輸出修正 |
| `fixtures/` | 抓下來的頁面（已洗個資）+ `menu_tree.json` 選單結構 |
| `fixtures/callbacks/` | 每次 callback 的送出參數與原始回應（debug 用，gitignore） |

## 你的下一步

```powershell
cd spike
```

一次登入把所有唯讀頁面抓完（38 頁，會改資料的自動跳過）：

```powershell
.venv\Scripts\python.exe login.py --save --fetch-all --quiet --name 你的姓名
```

或只抓課表：

```powershell
.venv\Scripts\python.exe login.py --save --fetch 'Application/TKE/TKE22/TKE2240_.aspx?progcd=STU1220' --name 你的姓名
```

抓到之後把課表頁改名成 `fixtures/timetable.html`，那個 skip 的測試就會生效，
再對著真實 HTML 調 `parse_timetable()`。

> **如果你這學期還沒選課**，抓到的課表會是空的，parser 就沒有真實資料可以對。
> 這種情況改用「歷年課程課表查詢」（`TKE2210_.aspx?progcd=STU1190`）
> 或「課程課表查詢」（`TKE2211_.aspx?progcd=STU1250`）——
> 那是全校課程資料，跟你有沒有選課無關，表格結構通常一樣。

**fixture 在寫檔當下就洗乾淨**（明文密碼、學號、姓名、身分證、IP、VIEWSTATE）。
`--name` 要自己給，因為程式只知道學號、不知道姓名。

commit 前跑這個（個資檢查 → 測試 → lint，一個指令）：

```powershell
.venv\Scripts\python.exe check.py
```

掃描範圍是**整個 repo 的 tracked 檔案**，不只 fixtures/ —— 個資會跑進註解和文件。
誤報時在那一行加 `scrub-ok` 就會跳過（跟 `# noqa` 同一個用意）。
已知會自動放行的：版本號（`jdk-17.0.20.1+1` 不是 IP）、私有網段、
常見假密碼（`hunter2` 等）、樣板佔位符（`$fakePassword`、`{pw}`、`%s`）。

個資檢查刻意排在第一個：測試紅了、lint 髒了都只是重跑一次的事，
但明文密碼一旦推上遠端，改密碼也救不回歷史紀錄。

掛成 git hook（`.git/hooks/pre-commit`）：

```bash
#!/bin/sh
exec spike/.venv/Scripts/python.exe spike/check.py --quiet
```

> PowerShell 5.1 沒有 `&&`，指令要分行下。`*.html` 也不會自動展開，
> 所以用 `(ls fixtures\*.html)` 讓 PowerShell 先展開再傳進去。

## 踩過的雷

**TLS：`Missing Subject Key Identifier`**
`requests` 預設用 certifi 的 CA bundle，建出來的信任鏈裡有張中介 CA 缺少
Subject Key Identifier，OpenSSL 3.5 的嚴格檢查（Python 3.13+ 預設開啟）直接拒絕。
`ais.SystemTrustAdapter` 改用 OS 憑證庫解決 —— 跟瀏覽器同一套信任來源。
信任鏈驗證、hostname 檢查、`VERIFY_X509_STRICT` **全部維持開啟**。

**絕對不要**因為憑證錯誤就改成 `verify=False`：這支程式會送學生的密碼，
關掉驗證等於在校園 Wi-Fi 上對中間人門戶大開。
移植到 Flutter 時不用管這段，Android / iOS 本來就走 OS 憑證庫。

**這個系統大量用 JS 導向而不是 HTTP 302**
排隊關卡是這樣，登入成功也是這樣。`requests` 不跑 JS，兩個地方都會靜默卡住 ——
沒有錯誤、沒有 302，就是拿到一頁「看起來很正常」的 HTML。
`ais.js_redirect_target()` 是專門處理這件事的，遇到新頁面卡住先想到它。

**Windows 主控台編碼**
Python 在 Windows 預設 stdout 是 cp950，遇到 Big5 編不出來的字會 `UnicodeEncodeError`
直接崩。`_console.py` 修一般 CLI；pytest 要靠 venv 裡的 `sitecustomize.py`，
因為 pytest 在 `conftest.py` 被 import 之前就抓住 stdout 了。
重建 venv 的話那個檔案會不見，改用 `$env:PYTHONUTF8 = 1`。

**課表的連堂課是用 rowspan 表示的**
照位置逐格讀，兩小時的課只會出現在第一節 —— App 上的課表就是錯的，
而且錯得很安靜（看起來完全正常，只是課提早一小時結束）。
`expand_grid()` 會把 rowspan / colspan 攤平成規則的二維陣列，
被跨格涵蓋的每一格放**同一個** cell 物件，所以能用 `is` 判斷是不是同一堂課。

星期欄也不假設順序，是用表頭文字比對的 —— 「第一節」含「一」但不是星期欄，
所以含「節」的欄位一律排除。

**`--fetch-all` 會跳過所有會改資料的頁面**
線上加退選、申請休退學、請假申請、修改密碼、登出（會作廢 session）等等，
清單在 `login.MUTATING_PATTERNS`，`test_login.py` 有測試守著。
選課期間誤觸「線上加退選」一次，後果不是重跑一次能解決的。
真的要看那些頁面，用 `--fetch` 明確指定。

**一個帳號同時只能有一個 session**
「系統同時一次僅許可一個帳號登入，你已登入過系統」。舊 session 沒登出就再登入，
**登入本身會成功、MainFrame 也載得起來**，但所有功能頁都被導到 ConfirmInOrOut.aspx
（狀態碼 200）。不偵測的話會把那一頁存成幾十份「課表」fixture。

**`LogOut.aspx` 也是派發器**，只回 48 bytes：

```html
<script>top.location.href='Logout.htm';</script>
```

只做 GET 不跟導向的話，程式會印出「已登出」但**其實沒有登出**。
session 一路累積，下次登入被擋，而症狀看起來完全是另一個問題 ——
這個坑吃掉了三次登入測試才找到，而且中間我兩次都猜錯方向。

`login.py` 每次跑完會自動登出並跟完導向。`--no-logout` 可以關掉，但通常不要用。

對 App 的意義：**學生在網頁登入時，App 抓不到資料。**
這是產品設計要處理的，不是能繞過的技術問題。

**session 逾時不會回 401**
逾時的回應是**一份登入頁的 HTML，狀態碼 200**。連抓 38 頁的時候中途逾時，
就會把一堆登入頁存成「課表」「成績」的 fixture —— 大小正常、看起來也像 HTML，
要等到 parser 解析出 0 筆才會發現，而那時你會以為是 parser 壞了。
`sess.check_session()` 認出登入頁就丟 `SessionExpired`，`--fetch-all` 直接中止整批。

**fixture 含個資**
排隊頁頁尾會印出你的對外 IP。登入回應含明文密碼（見最上面）。
`scrub.py --check` 可以掛 pre-commit hook。

## 移植到 Flutter

Flutter SDK 目前還沒裝。裝好之後對應關係：

| Python | Flutter |
|---|---|
| `requests.Session` | `dio` + `cookie_jar` |
| `BeautifulSoup` | `html` package |
| `getpass` | `flutter_secure_storage`（Keychain / Keystore） |
| `selectors.json` 讀檔 | Firebase Remote Config / GitHub raw |
| fixture 測試 | 原封不動搬，`test/` 放同一批 HTML |
| `SystemTrustAdapter` | 不需要，平台預設就是 OS 憑證庫 |
| `js_redirect_target` | 一樣要 —— 除非你用 WebView，否則 JS 導向還是得自己抓 |

`ais.py` 刻意不用任何 requests 專屬的花招，就是為了讓這層可以一行一行對著搬。

**密碼只能存在 Keychain / Keystore，爬蟲跑在裝置端。**
一旦密碼經過你自己的伺服器，你就是在替全校學生保管帳密 —— 出事你自己扛。
加上這個系統會把密碼明文回吐，登入回應**永遠不要進 log 或崩潰回報**。
