"""
ais.py — ASP.NET WebForms session client for ais.ntou.edu.tw

設計目標：把 WebForms 的固定舞步（__VIEWSTATE 續傳、__doPostBack 換頁、
cookie session、編碼偵測）包成一層，讓上面的 parser 可以是純函式。

這一層之後要移植到 Flutter (dio + cookie_jar)。移植時對照的就是這個檔案，
所以刻意不用任何 requests 專屬的花招。

安全原則：
  - 密碼只存在記憶體，絕不寫檔、絕不進 log
  - 所有 dump 出來的 HTML 都是「你自己的帳號、你自己的資料」
  - 內建節流，不要把學校的機器打爛
"""
from __future__ import annotations

import json
import re
import ssl
import time
from dataclasses import dataclass, field
from pathlib import Path
from urllib.parse import urljoin, urlparse

import requests
from bs4 import BeautifulSoup
from requests.adapters import HTTPAdapter
from urllib3.poolmanager import PoolManager

# WebForms 每次 postback 都要原封不動帶回去的隱藏欄位。
# 少帶任何一個都可能被丟回登入頁。
HIDDEN_FIELDS = (
    "__VIEWSTATE",
    "__VIEWSTATEGENERATOR",
    "__VIEWSTATEENCRYPTED",
    "__EVENTVALIDATION",
    "__PREVIOUSPAGE",
    "__LASTFOCUS",
)

# 從 inline JS 抓 __doPostBack('ctl00$xxx','') —— 這就是頁面的「導覽表」
DOPOSTBACK_RE = re.compile(
    r"""__doPostBack\(\s*['"]([^'"]*)['"]\s*,\s*['"]([^'"]*)['"]\s*\)"""
)

# JS 導向的三種寫法都要認：
#   location.href='X'                     （前面可能緊接著 <script>，所以不能限定前綴字元）
#   top.location.href='X'
#   top.<frameName>.location.href='X'
#
# 右邊一定要是字面值字串，這樣 onclick="self.location.href=self.location.href"
# （驗證碼圖的重新整理）就不會被誤判成導向。
_JS_REDIRECT_RE = re.compile(
    r"""(?<![\w$])(?:(?:top|self|parent|window)(?:\.\w+)*\.)?location"""
    r"""(?:\.href)?\s*=\s*['"]([^'"]+)['"]"""
)

DEFAULT_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/124.0 Safari/537.36"
)


class SystemTrustAdapter(HTTPAdapter):
    """
    讓 requests 改用作業系統的憑證庫，而不是 certifi 打包的那份。

    為什麼需要：ais.ntou.edu.tw 的憑證由 TWCA 簽發，用 certifi 的 bundle 建出來的
    信任鏈裡有一張中介 CA 缺少 Subject Key Identifier 擴充欄位，OpenSSL 3.5 的
    嚴格檢查（VERIFY_X509_STRICT，Python 3.13+ 預設開啟）會直接拒絕，錯誤訊息是
    `CERTIFICATE_VERIFY_FAILED: Missing Subject Key Identifier`。

    改用 OS 憑證庫後可以建出合規的鏈，驗證就過了。

    注意這跟 verify=False 完全是兩回事：
      - 信任鏈驗證：保持開啟
      - hostname 檢查：保持開啟
      - VERIFY_X509_STRICT：保持開啟
    只是換一個信任錨的來源 —— 跟你瀏覽器用的是同一套。

    **絕對不要**因為憑證錯誤就改成 verify=False。這支程式接下來會送學生的密碼，
    關掉驗證等於在校園 Wi-Fi 上對中間人門戶大開。

    移植到 Flutter 時不用管這段：Android / iOS 的 HTTP stack 本來就走 OS 憑證庫。
    """

    def init_poolmanager(self, connections, maxsize, block=False, **kw):
        ctx = ssl.create_default_context()
        kw["ssl_context"] = ctx
        self.poolmanager = PoolManager(
            num_pools=connections, maxsize=maxsize, block=block, **kw
        )


@dataclass
class CallbackEnvelope:
    """
    ASP.NET client callback 的外層封裝。格式抄自 WebForm_ExecuteCallback：

        's' + 結果                      -> 成功，沒有新的 event validation
        'e' + 訊息                      -> 伺服器端拋例外
        <長度> + '|' + <新的 __EVENTVALIDATION> + 結果

    第三種是最常見也最容易漏的：那個長度是**驗證欄位的長度**，不是結果的一部分。
    誤把它當成結果的第一個欄位，送出去的參數就全錯，伺服器回
    'e回呼中發生錯誤。' —— 而且不會告訴你錯在哪。
    """

    result: str
    event_validation: str | None = None
    error: str | None = None


class CallbackError(RuntimeError):
    """伺服器在 callback 中拋例外（回應以 'e' 開頭）。"""


def parse_callback_envelope(payload: str) -> CallbackEnvelope:
    if not payload:
        return CallbackEnvelope(result="")
    if payload[0] == "s":
        return CallbackEnvelope(result=payload[1:])
    if payload[0] == "e":
        return CallbackEnvelope(result="", error=payload[1:])

    sep = payload.find("|")
    if sep == -1:
        return CallbackEnvelope(result=payload)
    try:
        length = int(payload[:sep])
    except ValueError:
        return CallbackEnvelope(result=payload)

    start = sep + 1
    validation = payload[start:start + length]
    return CallbackEnvelope(
        result=payload[start + length:],
        event_validation=validation or None,
    )


class SessionExpired(RuntimeError):
    """
    被踢回登入頁了。上層應該重新登入，而不是重試或繼續。

    為什麼要專門偵測：這個系統 session 逾時不會回 401/403，
    而是**直接回一份登入頁的 HTML，狀態碼 200**。
    連抓幾十頁的時候中途逾時，就會把一堆登入頁存成「課表」「成績」的 fixture ——
    檔案大小正常、看起來也像 HTML，要等到 parser 解析出 0 筆才會發現，
    而那時你會以為是 parser 壞了。

    帶著擋住我們的那一頁 —— 沒有它就只能憑症狀猜原因。
    """

    def __init__(self, message: str, page: Page | None = None) -> None:
        super().__init__(message)
        self.page = page


class LoginFailed(RuntimeError):
    """帶著失敗當下的頁面，方便直接 dump 出來看是驗證碼還是密碼錯。"""

    def __init__(self, message: str, page: Page | None = None) -> None:
        super().__init__(message)
        self.page = page


@dataclass
class Page:
    """一次 response 的快照。parser 只吃這個，不碰網路。"""

    url: str
    status: int
    html: str

    @property
    def soup(self) -> BeautifulSoup:
        return BeautifulSoup(self.html, "lxml")

    def save(self, path: str | Path) -> Path:
        p = Path(path)
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(self.html, encoding="utf-8")
        return p


@dataclass
class AisSession:
    base_url: str = "https://ais.ntou.edu.tw/"
    min_interval: float = 1.0          # 節流：兩次 request 至少間隔幾秒
    timeout: float = 20.0
    verbose: bool = True

    s: requests.Session = field(default_factory=requests.Session, repr=False)
    # 登入 POST 的原始回應。login() 會跟隨 JS 導向，回傳的是導向後的落地頁，
    # 但「怎麼判斷登入成功」的證據在原始回應裡，測試需要它。
    login_response: Page | None = field(default=None, repr=False)
    # 登出的回應。只有 48 bytes，看起來不像真的做了什麼 —— 要留著檢查。
    last_logout_response: Page | None = field(default=None, repr=False)
    _hidden: dict[str, str] = field(default_factory=dict, repr=False)
    _last_url: str = ""
    _last_request_at: float = 0.0

    def __post_init__(self) -> None:
        self.s.mount("https://", SystemTrustAdapter())
        self.s.headers.update(
            {
                "User-Agent": DEFAULT_UA,
                "Accept-Language": "zh-TW,zh;q=0.9,en;q=0.8",
                "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            }
        )

    # ---------- 低階 ----------

    def _throttle(self) -> None:
        delta = time.monotonic() - self._last_request_at
        if delta < self.min_interval:
            time.sleep(self.min_interval - delta)
        self._last_request_at = time.monotonic()

    def _decode(self, r: requests.Response) -> str:
        """
        台灣的舊 WebForms 站常常是 Big5，而且 header 不一定講實話。
        順序：meta charset > requests 猜的 > utf-8 硬上。
        """
        raw = r.content
        head = raw[:2048].decode("ascii", errors="ignore").lower()
        m = re.search(r'charset=["\']?\s*([\w-]+)', head)
        candidates = []
        if m:
            candidates.append(m.group(1))
        if r.encoding and r.encoding.lower() != "iso-8859-1":
            candidates.append(r.encoding)
        candidates += ["utf-8", "big5-hkscs", "cp950"]

        for enc in candidates:
            try:
                return raw.decode(enc)
            except (UnicodeDecodeError, LookupError):
                continue
        return raw.decode("utf-8", errors="replace")

    def _absorb(self, r: requests.Response) -> Page:
        """
        把 response 收進來：更新隱藏欄位快取、記住當前 URL。
        關鍵：每次 postback 後 __VIEWSTATE 都會變，一定要重抓。
        """
        html = self._decode(r)
        page = Page(url=r.url, status=r.status_code, html=html)
        self._last_url = r.url

        soup = page.soup
        found = {}
        for name in HIDDEN_FIELDS:
            el = soup.find("input", {"name": name})
            if el is not None and el.has_attr("value"):
                found[name] = el["value"]
        if found:
            self._hidden = found

        if self.verbose:
            vs = found.get("__VIEWSTATE", "")
            print(f"  [{r.status_code}] {r.url}  (viewstate {len(vs)}B, html {len(html)}B)")
        return page

    def get(self, path: str = "") -> Page:
        self._throttle()
        url = urljoin(self.base_url, path)
        r = self.s.get(url, timeout=self.timeout)
        return self._absorb(r)

    def post(self, path: str, fields: dict[str, str]) -> Page:
        self._throttle()
        url = urljoin(self.base_url, path)
        r = self.s.post(
            url,
            data=fields,
            timeout=self.timeout,
            headers={
                "Referer": self._last_url or url,
                "Content-Type": "application/x-www-form-urlencoded",
                "Origin": self.base_url.rstrip("/"),
            },
        )
        return self._absorb(r)

    # ---------- WebForms 舞步 ----------

    def form_fields(self, page: Page, form_index: int = 0) -> dict[str, str]:
        """
        把頁面上某個 <form> 的所有欄位現值撈出來當 postback 的基底。
        WebForms 很多控制項的狀態靠這些欄位維持，漏帶會出現「怎麼按都沒反應」。
        """
        forms = page.soup.find_all("form")
        if not forms:
            return {}
        form = forms[min(form_index, len(forms) - 1)]
        out: dict[str, str] = {}

        for el in form.find_all("input"):
            name = el.get("name")
            if not name:
                continue
            t = (el.get("type") or "text").lower()
            if t in ("submit", "button", "image", "reset"):
                continue          # 這些只在「你按的那顆」才送
            if t in ("checkbox", "radio") and not el.has_attr("checked"):
                continue
            out[name] = el.get("value", "")

        for el in form.find_all("select"):
            name = el.get("name")
            if not name:
                continue
            opt = el.find("option", selected=True) or el.find("option")
            if opt is not None:
                out[name] = opt.get("value", opt.get_text(strip=True))
            else:
                out[name] = ""

        for el in form.find_all("textarea"):
            if el.get("name"):
                out[el["name"]] = el.get_text()

        return out

    def postback(
        self,
        page: Page,
        target: str,
        argument: str = "",
        extra: dict[str, str] | None = None,
        path: str | None = None,
    ) -> Page:
        """
        模擬 __doPostBack(target, argument)。
        內頁換頁十之八九是這個，不是 GET 帶 query string。
        """
        fields = self.form_fields(page)
        fields.update(self._hidden)
        fields["__EVENTTARGET"] = target
        fields["__EVENTARGUMENT"] = argument
        if extra:
            fields.update(extra)

        dest = path if path is not None else _path_of(page.url, self.base_url)
        return self.post(dest, fields)

    def callback(self, page: Page, callback_id: str, param: str,
                 extra: dict[str, str] | None = None,
                 path: str | None = None) -> str:
        """
        ASP.NET client callback（WebForm_DoCallback）。

        跟 postback 的差別：回傳的**不是 HTML 頁面**，而是一段原始字串。
        TreeView 的延遲載入選單就是走這個 —— 子節點不在初始 HTML 裡，
        要 callback 才拿得到。

        送出內容 = 表單所有欄位 + __CALLBACKID + __CALLBACKPARAM，
        跟 WebForm_DoCallback 在瀏覽器裡做的一樣。

        **每次 callback 伺服器都會發一組新的 __EVENTVALIDATION**，這裡會自動
        接收並更新。不接的話：第一次成功（用的是原始頁面的驗證欄位），
        第二次之後只要參數是「伺服器在上一次回應才註冊的」就會被拒絕，
        回一句 'e回呼中發生錯誤。'，看不出任何線索。
        """
        fields = self.form_fields(page)
        fields.update(self._hidden)
        fields["__CALLBACKID"] = callback_id
        fields["__CALLBACKPARAM"] = param
        if extra:
            # 控制項自己的狀態欄位（TreeView 的 ExpandState / PopulateLog）
            # 要由呼叫端接力維護 —— 初始頁面的值只對第一次 callback 有效。
            fields.update(extra)

        dest = path if path is not None else _path_of(page.url, self.base_url)
        raw = self.post(dest, fields).html

        env = parse_callback_envelope(raw)
        if env.event_validation:
            self._hidden["__EVENTVALIDATION"] = env.event_validation
        if env.error is not None:
            raise CallbackError(env.error)
        return env.result

    def postback_targets(self, page: Page) -> list[tuple[str, str]]:
        """列出這一頁所有 __doPostBack 目標 —— 探索站台結構用。"""
        seen: dict[tuple[str, str], None] = {}
        for m in DOPOSTBACK_RE.finditer(page.html):
            seen.setdefault((m.group(1), m.group(2)), None)
        return list(seen.keys())

    # ---------- 登入 ----------

    def open_login_page(self, cfg: dict) -> Page:
        """
        取得**真正可以登入的**登入頁。

        海大 AIS 在登入前擋了一層虛擬排隊（DefaultQ.aspx）。實測流程：

            GET Default.aspx   -> 21992B，有登入表單，但驗證碼 <img> 沒有 src
            GET DefaultQ.aspx  -> 排隊頁（人少時直接放行）
            GET Default.aspx   -> 21988B，這次驗證碼 src 才出現
                                  /Temp/Captcha/xxxxxxxx.png?t=...

        跳過中間那步，驗證碼永遠是空的，登入一定失敗。

        排隊機制是選課尖峰時保護伺服器用的，**照著走、不要繞過**。
        繞過等於在最脆弱的時候加壓，也是最容易被封 IP 的行為。
        """
        login_path = cfg.get("path", "Default.aspx")
        page = self.get(login_path)

        queue_path = cfg.get("queue_path")
        marker = cfg.get("queue_redirect_marker", "DefaultQ.aspx")
        if queue_path and marker in page.html:
            if self.verbose:
                print("  偵測到排隊關卡，依序通過...")
            self.get(queue_path)
            page = self.get(login_path)

        return page

    def captcha_url(self, page: Page, cfg: dict) -> str | None:
        """驗證碼檔名每個 session 都不一樣，只能從頁面上抓，不能寫死。"""
        img = page.soup.find("img", id=cfg.get("captcha_img_id", "importantImg"))
        if img is None or not img.get("src"):
            return None
        return img["src"]

    def fetch_captcha(self, page: Page, cfg: dict) -> bytes | None:
        """驗證碼圖片。不要 OCR，顯示給使用者自己打就好。"""
        src = self.captcha_url(page, cfg)
        if not src:
            return None
        self._throttle()
        r = self.s.get(
            urljoin(self.base_url, src),
            timeout=self.timeout,
            headers={"Referer": self._last_url},
        )
        return r.content

    def login(self, cfg: dict, username: str, password: str, captcha: str | None = None,
              page: Page | None = None) -> Page:
        """
        cfg 就是 selectors.json 裡的 "login" 區塊。
        欄位名不寫死在程式裡，是為了之後學校改版時只改設定不改 code
        （Flutter 版就是靠這個做到不用送審 App Store 就能修）。

        page 要傳 open_login_page() 的結果 —— 驗證碼跟 __VIEWSTATE 都綁在那次 session
        狀態上，重抓一次頁面驗證碼就換了。
        """
        login_path = cfg.get("path", "Default.aspx")
        if page is None:
            page = self.open_login_page(cfg)

        fields = self.form_fields(page)
        fields.update(self._hidden)
        fields[cfg["username_field"]] = username
        fields[cfg["password_field"]] = password

        if captcha and cfg.get("captcha_field"):
            fields[cfg["captcha_field"]] = captcha

        # 登入鈕：Button 用 name=value，LinkButton 用 __EVENTTARGET
        if cfg.get("submit_event_target"):
            fields["__EVENTTARGET"] = cfg["submit_event_target"]
            fields["__EVENTARGUMENT"] = cfg.get("submit_event_argument", "")
        elif cfg.get("submit_field"):
            fields[cfg["submit_field"]] = cfg.get("submit_value", "登入")

        fields.update(cfg.get("extra_fields", {}))

        result = self.post(login_path, fields)
        self.login_response = result

        for needle in cfg.get("failure_markers", []):
            if needle in result.html:
                raise LoginFailed(f"登入失敗，頁面出現：{needle!r}", result)

        # 登入成功時伺服器不送 302，而是回一頁 JS：top.location.href = 'MainFrame.aspx'
        # 所以「成功」的判斷是「有沒有導向指令」，不是找 "登出" 這種字串
        # —— 成功的回應長得跟登入頁幾乎一樣，只差這一行。
        # 登入失敗會重畫登入頁，那頁帶的是 location.href='DefaultQ.aspx'（排隊頁）。
        # 不排掉的話會把「失敗」誤判成「成功」。
        dest = self.js_redirect_target(result)
        not_progress = {
            cfg.get("queue_path", "DefaultQ.aspx"),
            cfg.get("path", "Default.aspx"),
        }
        if dest and dest.lstrip("./") in not_progress:
            dest = None

        if dest:
            if self.verbose:
                print(f"  登入成功，跟隨 JS 導向 -> {dest}")
            return self.get(dest)

        markers = cfg.get("success_markers", [])
        if markers and any(n in result.html for n in markers):
            return result

        raise LoginFailed(
            "登入後既沒有導向指令、也找不到 success_markers。"
            "多半是驗證碼或密碼錯了（這個系統錯誤時不會給訊息，只會重畫登入頁）。",
            result,
        )

    @staticmethod
    def js_redirect_target(page: Page) -> str | None:
        """
        抓 JS 導向目標。這個系統換頁幾乎全靠 JS，而且有三種寫法：

            location.href='DefaultQ.aspx'                    排隊關卡
            top.location.href='MainFrame.aspx'               登入成功
            top.mainFrame.location.href='TKE2240_01.aspx'    功能頁派發

        第三種最容易漏 —— `Application/…/XXXX_.aspx?progcd=…` 這種選單連結
        其實只是派發器，它註冊完 session 狀態就叫框架去載真正的頁面。
        直接 GET 只會拿到 1.4KB 的空殼，看起來像「這頁沒東西」。

        回傳的可能是相對路徑，要用 urljoin(page.url, target) 解析，
        不能用 base_url —— 功能頁埋在 Application/TKE/TKE22/ 之類的深層目錄。
        """
        for m in _JS_REDIRECT_RE.finditer(page.html):
            target = m.group(1).strip()
            if not target or target.lower().startswith(("about:", "javascript:")):
                continue
            return target
        return None

    # 登入頁的指紋。session 逾時的回應會長成這樣（而且是 200）。
    login_markers: tuple[str, ...] = ("M_PORTAL_LOGIN_ACNT", "LoginPWD")

    def is_login_page(self, page: Page) -> bool:
        """這一頁是不是（被踢回的）登入頁。"""
        return all(m in page.html for m in self.login_markers)

    @staticmethod
    def is_session_conflict(page: Page) -> bool:
        """
        「系統同時一次僅許可一個帳號登入，你已登入過系統」。

        這個系統**每個帳號同時只能有一個 session**。舊 session 沒登出就再登入，
        所有功能頁都會被導到 ConfirmInOrOut.aspx，而且是 200 —— 看起來像正常回應。
        """
        return "ConfirmInOrOut.aspx" in page.url or "僅許可一個帳號登入" in page.html

    def check_session(self, page: Page) -> Page:
        """抓到登入頁或重複登入警告就直接停 —— 繼續抓只會存下一堆假 fixture。"""
        if self.is_session_conflict(page):
            raise SessionExpired(
                "帳號在別處還有未登出的 session —— 這個系統一次只允許一個登入。\n"
                "  這支程式結束前會自動登出（LogOut.aspx 是「登出全部視窗」），"
                "所以**直接重跑一次就會正常**。\n"
                "  如果重跑還是一樣，用瀏覽器登入再正常登出一次。",
                page,
            )
        if self.is_login_page(page):
            raise SessionExpired(
                f"{page.url} 回傳的是登入頁（session 逾時或被登出）。"
                "後面的頁面不用再抓了，重新登入吧。",
                page,
            )
        return page

    def logout(self, path: str = "LogOut.aspx") -> None:
        """
        登出。**每次跑完都要做**，否則 session 留在伺服器上，
        下次登入會被 ConfirmInOrOut.aspx 擋掉，而且症狀完全不像「忘了登出」。

        `LogOut.aspx` 跟這個系統其他地方一樣**只是派發器**，只回 48 bytes：

            <script>top.location.href='Logout.htm';</script>

        真正把 session 作廢的是它導向的頁面。只做 GET 不跟導向的話，
        每次都會印出「已登出」但**其實沒有登出** —— 然後 session 一路累積，
        下次登入就被擋，而且看起來完全是另一個問題。
        """
        try:
            page = self.follow_js_redirect(self.get(path))
            self.last_logout_response = page
            if self.verbose:
                print(f"  已登出（最後停在 {_path_of(page.url, self.base_url)}）")
        except Exception as e:
            print(f"  登出失敗（{type(e).__name__}），"
                  f"下次登入可能會被擋，屆時先用瀏覽器登入再登出一次。")

    def same_origin(self, url: str) -> bool:
        """
        導向目標是不是還在同一個站台。

        必要防護：MenuTree.aspx 裡有一行 `top.mainFrame.location.href = "//portal.aspx"`
        —— 校方少打一條斜線，本意是 /portal.aspx。但 `//portal.aspx` 是協定相對 URL，
        urljoin 會解析成 https://portal.aspx，一個**站外主機**。
        自動跟隨的話，帶著 session cookie 的請求就送出去了，
        而那個網域任何人都能註冊。
        """
        return _origin(url) == _origin(self.base_url)

    def follow_js_redirect(self, page: Page, max_hops: int = 3) -> Page:
        """
        一路跟著 JS 導向走到真正有內容的頁面。

        `Application/…/XXXX_.aspx?progcd=…` 這種選單連結只是派發器，
        直接 GET 會拿到 1.4KB 空殼，真正的內容在它導向的 `XXXX_01.aspx`。
        """
        seen = {page.url}
        for _ in range(max_hops):
            target = self.js_redirect_target(page)
            if not target:
                break

            dest = urljoin(page.url, target)
            if not self.same_origin(dest):
                print(f"  ⚠ 跳過站外導向：{target!r} -> {dest}")
                break
            if dest in seen:
                break
            # 導回登入頁 = session 有問題。再跟下去只會走到 ConfirmInOrOut，
            # 然後把那頁存成「課表」。停在這裡，讓 check_session 報出真正的原因。
            if self.is_login_page(page) or _path_of(dest, self.base_url).lower().startswith(
                ("default.aspx", "defaultq.aspx")
            ):
                break

            seen.add(dest)
            if self.verbose:
                print(f"  跟隨 JS 導向 -> {target}")
            page = self.get(dest)
        return page


_DEFAULT_PORTS = {"http": 80, "https": 443}


def _origin(url: str) -> tuple[str, str, int]:
    """(scheme, host, port)，預設埠正規化 —— https://x 和 https://x:443 是同源。"""
    u = urlparse(url)
    host = (u.hostname or "").lower()
    port = u.port or _DEFAULT_PORTS.get(u.scheme, 0)
    return u.scheme, host, port


def _path_of(url: str, base: str) -> str:
    return url.removeprefix(base)


def load_config(path: str | Path = "selectors.json") -> dict:
    return json.loads(Path(path).read_text(encoding="utf-8"))
