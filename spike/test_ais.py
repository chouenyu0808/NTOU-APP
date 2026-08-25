"""
test_ais.py — session 層的回歸測試（不連網，全部吃 fixture）。

這裡鎖的是「怎麼判斷登入成功」和「fixture 裡不能有明文密碼」。
兩件事都曾經出過錯，而且錯的時候都不會有明顯症狀：
  - 成功被誤判成失敗（success_markers 找 "登出" 找不到）
  - 密碼被存進 fixture（學校系統把密碼回吐到 HTML）
"""
from __future__ import annotations

import json
from pathlib import Path

import pytest

from ais import AisSession, Page, SessionExpired, parse_callback_envelope
from parsers import parse_callback_response, parse_menu
from scrub import PW_REFLECT_PATTERNS, looks_dirty, scrub

HERE = Path(__file__).parent
FIXTURES = HERE / "fixtures"


def _page(name: str) -> Page:
    p = FIXTURES / name
    if not p.exists():
        pytest.skip(f"還沒有 {p.name}")
    return Page(url=f"https://ais.ntou.edu.tw/{name}", status=200,
                html=p.read_text(encoding="utf-8"))


# ---------- 登入成功判斷 ----------

def test_success_response_redirects_to_mainframe():
    """
    登入成功的回應不是 302，是一頁 JS：top.location.href = 'MainFrame.aspx'。
    這一行如果被改掉，App 會變成「登入成功但卡在登入頁」。

    吃的是登入 POST 的**原始回應**（login_post.html），不是導向後的落地頁 ——
    證據在原始回應裡，落地頁上沒有。
    """
    assert AisSession.js_redirect_target(_page("login_post.html")) == "MainFrame.aspx"


def test_landing_page_is_a_frameset():
    """
    MainFrame.aspx 只是框架容器，沒有 postback 目標。
    真正的選單在 MenuTree.aspx —— 課表 / 成績的入口要從那裡找。
    """
    page = _page("mainframe.html")
    srcs = {f.get("src") for f in page.soup.find_all(["frame", "iframe"])}
    assert "MenuTree.aspx" in srcs
    assert AisSession().postback_targets(page) == []


def test_login_page_redirects_to_queue():
    """登入前的頁面導向排隊頁 —— 不能被當成登入成功。"""
    assert AisSession.js_redirect_target(_page("login.html")) == "DefaultQ.aspx"


def test_queue_page_redirects_back_to_login():
    assert AisSession.js_redirect_target(_page("queue.html")) == "Default.aspx"


def test_no_redirect_on_plain_html():
    page = Page(url="x", status=200, html="<html><body>沒有導向</body></html>")
    assert AisSession.js_redirect_target(page) is None


def test_failed_login_has_no_redirect():
    """
    登入失敗的回應（22063B）跟成功的（22101B）大小只差 38 bytes，
    但失敗的**完全沒有** location.href 導向指令。
    這就是區分成功失敗的唯一可靠訊號。
    """
    assert AisSession.js_redirect_target(_page("login_failed.html")) is None


def test_config_success_redirect_matches_fixture():
    """selectors.json 設定的成功導向，要跟實際 fixture 對得上。"""
    cfg = json.loads((HERE / "selectors.json").read_text(encoding="utf-8"))
    assert cfg["login"]["success_redirect"] == \
        AisSession.js_redirect_target(_page("login_post.html"))


# ---------- 密碼回吐 ----------

def test_scrub_removes_reflected_password():
    """
    學校系統會把密碼明文回吐到回應 HTML 裡（兩處）。
    這不是我們造成的，但代表任何存下來的頁面都含明文密碼。
    """
    dirty = (
        "<script>var\tkeyObj\t=\t{LoginPWD:'P@ssw0rd123'};</script>\n"
        "<script>_i(0, 'LoginPWD').value\t=\t'P@ssw0rd123';</script>"
    )
    assert looks_dirty(dirty) == ["回吐的明文密碼"]

    cleaned, n = scrub(dirty)
    assert "P@ssw0rd123" not in cleaned
    assert n >= 2
    assert looks_dirty(cleaned) == []


@pytest.mark.parametrize(
    "name",
    ["login.html", "queue.html", "login_post.html",
     "login_failed.html", "mainframe.html"],
)
def test_committed_fixtures_have_no_secrets(name):
    """守門測試：fixture 目錄裡不准出現明文密碼或個資。"""
    p = FIXTURES / name
    if not p.exists():
        pytest.skip(f"還沒有 {name}")
    assert looks_dirty(p.read_text(encoding="utf-8")) == []


def test_pw_patterns_do_not_match_redacted():
    """清乾淨的檔案不能被自己的檢查判成髒的。"""
    clean = "var keyObj = {LoginPWD:'REDACTED'};"
    assert all("REDACTED" in m.group(0)
               for pat in PW_REFLECT_PATTERNS
               for m in pat.finditer(clean))


# ---------- ASP.NET callback 封裝 ----------

def test_callback_envelope_extracts_new_event_validation():
    """
    真實格式（實測 2026-08-25）：
        <驗證欄位長度>|<新的 __EVENTVALIDATION><真正的結果>

    那個開頭數字是**驗證欄位的長度**，不是結果的第一個欄位。
    誤讀成 lastIndex 的話，送出的參數全錯，伺服器回 'e回呼中發生錯誤。'。
    """
    validation = "A" * 476
    env = parse_callback_envelope(f"476|{validation}23|cccc|<div>子節點</div>")
    assert env.error is None
    assert env.event_validation == validation
    assert env.result == "23|cccc|<div>子節點</div>"


def test_callback_envelope_reports_server_error():
    env = parse_callback_envelope("e回呼中發生錯誤。")
    assert env.error == "回呼中發生錯誤。"
    assert env.result == ""
    assert env.event_validation is None


def test_callback_envelope_plain_success_prefix():
    """'s' 前綴＝成功但沒有新的 event validation。"""
    env = parse_callback_envelope("s23|cccc|<div/>")
    assert env.error is None
    assert env.event_validation is None
    assert env.result == "23|cccc|<div/>"


def test_callback_envelope_empty_validation_field():
    """長度 0 代表沒換新的驗證欄位，不要把空字串存進 __EVENTVALIDATION。"""
    env = parse_callback_envelope("0|23|cccc|<div/>")
    assert env.event_validation is None
    assert env.result == "23|cccc|<div/>"


def test_callback_envelope_and_treeview_parse_compose():
    """兩層解析要串得起來：先拆封裝，再拆 TreeView 結果。"""
    env = parse_callback_envelope("4|ABCD440|nnnn|<a href='x.aspx'>課表</a>")
    assert env.event_validation == "ABCD"
    inner = parse_callback_response(env.result)
    assert inner is not None
    assert inner.last_index == 440
    assert inner.new_expand_state == "nnnn"
    assert parse_menu(inner.html)[0].href == "x.aspx"


# ---------- session 逾時偵測 ----------

def test_login_page_is_recognised():
    """
    session 逾時不會回 401 —— 是直接回一份登入頁，狀態碼 200。
    連抓幾十頁時中途逾時，就會把登入頁存成「課表」的 fixture。
    """
    sess = AisSession(verbose=False)
    assert sess.is_login_page(_page("login.html"))


def test_content_page_is_not_mistaken_for_login():
    sess = AisSession(verbose=False)
    assert not sess.is_login_page(_page("mainframe.html"))
    assert not sess.is_login_page(_page("MenuTree.aspx.html"))


def test_check_session_raises_on_login_page():
    sess = AisSession(verbose=False)
    page = Page(url="https://ais.ntou.edu.tw/Application/TKE/TKE22/TKE2240_01.aspx",
                status=200,
                html='<input name="M_PORTAL_LOGIN_ACNT"><input name="LoginPWD">')
    with pytest.raises(SessionExpired) as exc:
        sess.check_session(page)
    assert "TKE2240_01.aspx" in str(exc.value), "錯誤訊息要指出是哪一頁"


def test_check_session_passes_through_real_content():
    sess = AisSession(verbose=False)
    page = Page(url="x", status=200, html="<table><tr><td>微積分</td></tr></table>")
    assert sess.check_session(page) is page


def test_session_conflict_is_detected():
    """
    「系統同時一次僅許可一個帳號登入」—— 舊 session 沒登出就再登入，
    所有功能頁都會被導到 ConfirmInOrOut.aspx，而且是 200。
    不偵測的話會把這一頁存成 30 份「課表」fixture。
    """
    page = Page(url="https://ais.ntou.edu.tw/ConfirmInOrOut.aspx", status=200,
                html="<p>系統同時一次僅許可一個帳號登入，你已登入過系統</p>")
    assert AisSession.is_session_conflict(page)
    with pytest.raises(SessionExpired, match="一次只允許一個登入"):
        AisSession(verbose=False).check_session(page)


def test_session_conflict_detected_by_url_alone():
    """內容變了也要認得出來 —— URL 是比文案更穩定的訊號。"""
    page = Page(url="https://ais.ntou.edu.tw/ConfirmInOrOut.aspx", status=200,
                html="<html></html>")
    assert AisSession.is_session_conflict(page)


def test_normal_page_is_not_session_conflict():
    page = Page(url="https://ais.ntou.edu.tw/Portal.aspx", status=200,
                html="<table><tr><td>公告</td></tr></table>")
    assert not AisSession.is_session_conflict(page)


def test_logout_dispatcher_redirect_is_detected():
    """
    LogOut.aspx 只是派發器，回 48 bytes：
        <script>top.location.href='Logout.htm';</script>
    只做 GET 不跟導向的話，會印出「已登出」但其實沒登出 ——
    session 一路累積，下次登入被擋，症狀看起來完全是另一個問題。
    """
    page = Page(url="https://ais.ntou.edu.tw/LogOut.aspx", status=200,
                html="<script>top.location.href='Logout.htm';</script>")
    assert AisSession.js_redirect_target(page) == "Logout.htm"


def test_blocked_page_carries_conflict_signal():
    """
    被擋時拿到的是登入頁 + location.href='ConfirmInOrOut.aspx'。
    兩個訊號都要認得：頁面文字和導向目標。
    """
    p = FIXTURES / "session_blocked.html"
    if not p.exists():
        pytest.skip("還沒有 session_blocked.html")
    page = Page(url="https://ais.ntou.edu.tw/Default.aspx", status=200,
                html=p.read_text(encoding="utf-8"))
    assert AisSession.is_session_conflict(page)
    assert AisSession.js_redirect_target(page) == "ConfirmInOrOut.aspx"


# ---------- onclick 的隱藏欄位副作用 ----------

def test_onclick_sets_query_type():
    """
    onclick="return doQuery('1')" 對應 JS 裡的
        _i(0, "QUERY_TYPE").value = type;
    不送這個欄位伺服器就拋例外，而且只回一句通用的 403
    「系統發生錯誤, 請通知系統管理人員」—— 完全看不出少了什麼。
    """
    from bs4 import BeautifulSoup
    el = BeautifulSoup(
        """<input type="submit" name="QUERY_BTN1" onclick="return doQuery('1');">""",
        "lxml",
    ).find("input")
    assert AisSession.onclick_side_effects(el) == {"QUERY_TYPE": "1"}


def test_onclick_without_argument_sets_nothing():
    """TKE2240 的 doQuery() 沒帶參數，不該亂補欄位。"""
    from bs4 import BeautifulSoup
    el = BeautifulSoup(
        """<input type="submit" name="QUERY_BTN1" onclick="return doQuery();">""",
        "lxml",
    ).find("input")
    assert AisSession.onclick_side_effects(el) == {}


@pytest.mark.parametrize("html", [
    '<input name="X">',                                  # 沒有 onclick
    '<input name="X" onclick="clearQueryForm();">',      # 不相干的函式
])
def test_onclick_side_effects_on_other_buttons(html):
    from bs4 import BeautifulSoup
    el = BeautifulSoup(html, "lxml").find("input")
    assert AisSession.onclick_side_effects(el) == {}


def test_onclick_side_effects_on_missing_button():
    assert AisSession.onclick_side_effects(None) == {}


def test_real_course_search_buttons_map_to_query_types():
    """真實頁面：七顆查詢按鈕各自對應一個 QUERY_TYPE。"""
    p = FIXTURES / "Application_TKE_TKE22_TKE2211_01.html"
    if not p.exists():
        pytest.skip("還沒有課程查詢頁")
    soup = Page(url="x", status=200, html=p.read_text(encoding="utf-8")).soup
    expected = {"QUERY_BTN1": "1", "QUERY_BTN7": "2", "QUERY_BTN3": "3",
                "QUERY_BTN4": "4", "QUERY_BTN5": "5", "QUERY_BTN6": "6",
                "QUERY_BTN8": "7"}
    for name, want in expected.items():
        el = soup.find("input", {"name": name})
        assert AisSession.onclick_side_effects(el) == {"QUERY_TYPE": want}, name


# ---------- 連線層重試 ----------

def test_get_retries_on_connection_error(monkeypatch):
    """
    每次跑都要人工打驗證碼，一次網路抖動就浪費掉整輪 ——
    實測遇過 TLS 握手被 RST（WinError 10054），下一秒就恢復。
    """
    import requests

    sess = AisSession(verbose=False, min_interval=0)
    calls = {"n": 0}

    class FakeResponse:
        content = b"<html>ok</html>"
        encoding = "utf-8"
        status_code = 200
        url = "https://ais.ntou.edu.tw/x.aspx"

    def flaky(url, timeout=None):
        calls["n"] += 1
        if calls["n"] < 3:
            raise requests.ConnectionError("Connection aborted")
        return FakeResponse()

    monkeypatch.setattr(sess.s, "get", flaky)
    monkeypatch.setattr("time.sleep", lambda _: None)

    page = sess.get("x.aspx", retries=2)
    assert page.status == 200
    assert calls["n"] == 3, "應該重試到成功"


def test_get_gives_up_after_retries(monkeypatch):
    import requests

    sess = AisSession(verbose=False, min_interval=0)

    def always_fail(url, timeout=None):
        raise requests.ConnectionError("Connection aborted")

    monkeypatch.setattr(sess.s, "get", always_fail)
    monkeypatch.setattr("time.sleep", lambda _: None)

    with pytest.raises(requests.ConnectionError):
        sess.get("x.aspx", retries=2)


def test_post_is_not_retried(monkeypatch):
    """
    POST **不能**重試：連線斷掉時沒辦法知道伺服器處理了沒有，
    重送可能造成重複提交。登入 POST 還綁著一次性驗證碼，重送本來就會失敗。
    """
    import requests

    sess = AisSession(verbose=False, min_interval=0)
    calls = {"n": 0}

    def failing_post(url, **kwargs):
        calls["n"] += 1
        raise requests.ConnectionError("Connection aborted")

    monkeypatch.setattr(sess.s, "post", failing_post)

    with pytest.raises(requests.ConnectionError):
        sess.post("x.aspx", {"a": "1"})
    assert calls["n"] == 1, "POST 只能送一次"


def test_empty_select_is_omitted_not_sent_blank():
    """
    沒有任何 <option> 的 select，瀏覽器完全不送這個欄位。
    送空字串會踩到 ASP.NET 的 event validation（值不是伺服器渲染的），
    伺服器拋例外，表面上只回一句通用的資料庫錯誤 403。
    """
    page = Page(url="x", status=200, html="""
        <form>
          <select name="有選項"><option value="A">A</option></select>
          <select name="空的"></select>
        </form>
    """)
    fields = AisSession(verbose=False).form_fields(page)
    assert fields["有選項"] == "A"
    assert "空的" not in fields, "空 select 不能送出去"


def test_real_course_search_omits_empty_teacher_select():
    """真實頁面：Q_LECTR_TCH_CH 是 0 個選項的 select。"""
    p = FIXTURES / "Application_TKE_TKE22_TKE2211_01.html"
    if not p.exists():
        pytest.skip("還沒有課程查詢頁")
    page = Page(url="https://ais.ntou.edu.tw/x.aspx", status=200,
                html=p.read_text(encoding="utf-8"))
    fields = AisSession(verbose=False).form_fields(page)
    assert "Q_LECTR_TCH_CH" not in fields
    # 有選項的照送
    assert fields["Q_FACULTY_CODE"]
    assert fields["Q_DEGREE_CODE"] == "0"


# ---------- 送出前的值驗證 ----------

def _select_page() -> Page:
    return Page(url="x", status=200, html="""
        <form>
          <select name="Q_CLASS">
            <option value="00">00</option><option value="03">03</option>
            <option value="05">05</option>
          </select>
          <input name="Q_TEXT" type="text">
        </form>
    """)


def test_check_values_accepts_real_options():
    AisSession.check_values(_select_page(), {"Q_CLASS": "03"})


def test_check_values_rejects_stripped_leading_zero():
    """
    PowerShell 把 --sweep Q_CLASS=03,05 裡的 05 當數字轉成 5。
    送出去只會得到看不懂的 403，在本機擋下來錯誤訊息才有用。
    """
    with pytest.raises(ValueError, match="不是合法選項"):
        AisSession.check_values(_select_page(), {"Q_CLASS": "5"})


def test_check_values_error_lists_valid_options():
    try:
        AisSession.check_values(_select_page(), {"Q_CLASS": "99"})
    except ValueError as e:
        assert "'00'" in str(e) and "'03'" in str(e), "要把可用的值列出來"
    else:
        pytest.fail("應該要擋下來")


def test_check_values_ignores_non_select_fields():
    """文字欄位沒得驗，交給伺服器。"""
    AisSession.check_values(_select_page(), {"Q_TEXT": "任何值"})
    AisSession.check_values(_select_page(), {"不存在的欄位": "x"})


def test_check_values_on_real_page():
    p = FIXTURES / "Application_TKE_TKE22_TKE2211_01.html"
    if not p.exists():
        pytest.skip("還沒有課程查詢頁")
    page = Page(url="x", status=200, html=p.read_text(encoding="utf-8"))
    AisSession.check_values(page, {"Q_CLASS": "03", "Q_WEEK": "1",
                                   "Q_FACULTY_CODE": "0507"})
    with pytest.raises(ValueError):
        AisSession.check_values(page, {"Q_CLASS": "5"})
