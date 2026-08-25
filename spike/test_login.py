"""
test_login.py — login.py 裡不需要網路的部分。

重點在 --fetch-all 的安全性：**絕對不能把會改變資料的頁面掃進去**。
選課期間誤觸「線上加退選」一次，後果不是重跑一次能解決的。
"""
from __future__ import annotations

import pytest

from ais import AisSession, Page
from login import fixture_name, is_mutating, page_title


@pytest.mark.parametrize("path", [
    "Application/TKE/TKE20/TKE2011_.aspx?progcd=STU1010",   # 線上加退選
    "Application/ENR/ENRD0/ENRD140_.aspx?progcd=ENRD140",   # 申請休退學
    "Application/SEC/SEC60/SEC6000_.aspx?progcd=SEC6000",   # 請假申請
    "Application/PWD/PWD1020_.aspx",                        # 修改密碼
    "LogOut.aspx",                                          # 會作廢 session
    "./LOGOUT.ASPX",                                        # 大小寫不敏感
])
def test_mutating_pages_are_flagged(path):
    assert is_mutating(path), f"{path} 應該被判定為會改資料"


@pytest.mark.parametrize("path", [
    "Application/TKE/TKE22/TKE2240_.aspx?progcd=STU1220",   # 個人課表
    "Application/TKE/TKE22/TKE2211_.aspx?progcd=STU1250",   # 課程查詢
    "Application/SEC/SEC20/SEC2050_.aspx?progcd=SEC2050",   # 請假查詢（唯讀）
    "Application/BBS/BBS30/BBS3010_.aspx?progcd=BBS3010",   # 公告
    "Portal.aspx",
])
def test_readonly_pages_are_not_flagged(path):
    assert not is_mutating(path), f"{path} 是唯讀頁，不該被跳過"


def test_leave_query_and_leave_apply_are_distinguished():
    """SEC2050（查詢）和 SEC2020（取消）只差幾個字元，不能一起誤判。"""
    assert not is_mutating("Application/SEC/SEC20/SEC2050_.aspx")
    assert is_mutating("Application/SEC/SEC20/SEC2020_.aspx")


def test_fixture_name_uses_final_url_not_dispatcher():
    """
    派發器 TKE2240_.aspx 會導向 TKE2240_01.aspx，
    檔名要用**導向後**的網址，才對得上檔案裡的實際內容。
    """
    assert fixture_name(
        "https://ais.ntou.edu.tw/Application/TKE/TKE22/TKE2240_01.aspx"
    ) == "Application_TKE_TKE22_TKE2240_01.html"


def test_fixture_name_drops_query_string():
    assert fixture_name(
        "https://ais.ntou.edu.tw/Application/BBS/BBS30/BBS3010_.aspx?progcd=BBS3010"
    ) == "Application_BBS_BBS30_BBS3010_.html"


def test_fixture_name_on_root():
    assert fixture_name("https://ais.ntou.edu.tw/") == "index.html"


def test_page_title():
    page = Page(url="x", status=200,
                html="<html><head><title>\n\t學生個人選課清單課表列印 \n</title></head></html>")
    assert page_title(page) == "學生個人選課清單課表列印"


# ---------- 站外導向防護 ----------

def test_same_origin_rejects_protocol_relative_url():
    """
    MenuTree.aspx 裡有 `top.mainFrame.location.href = "//portal.aspx"`
    —— 校方少打一條斜線。urljoin 會把它解析成 https://portal.aspx（站外主機）。
    自動跟隨的話就把 session cookie 送出去了。
    """
    from urllib.parse import urljoin
    sess = AisSession(verbose=False)
    dest = urljoin("https://ais.ntou.edu.tw/MenuTree.aspx", "//portal.aspx")
    assert dest == "https://portal.aspx"
    assert not sess.same_origin(dest)


@pytest.mark.parametrize("url, expected", [
    ("https://ais.ntou.edu.tw/x.aspx", True),
    ("https://ais.ntou.edu.tw:443/x.aspx", True),      # 預設埠要正規化
    ("https://AIS.NTOU.EDU.TW/x.aspx", True),          # 主機名不分大小寫
    ("http://ais.ntou.edu.tw/x.aspx", False),          # 降級成 http 不算同源
    ("https://portal.aspx", False),
    ("https://evil.example/x", False),
])
def test_same_origin(url, expected):
    assert AisSession(verbose=False).same_origin(url) is expected


def test_follow_js_redirect_resolves_relative_to_page_url():
    """
    派發器導向的是相對路徑 'TKE2240_01.aspx'，要相對於**該頁的 URL** 解析，
    不是相對於 base_url —— 功能頁埋在 Application/TKE/TKE22/ 這種深層目錄。
    """
    from urllib.parse import urljoin
    page_url = "https://ais.ntou.edu.tw/Application/TKE/TKE22/TKE2240_.aspx?progcd=X"
    assert urljoin(page_url, "TKE2240_01.aspx") == \
        "https://ais.ntou.edu.tw/Application/TKE/TKE22/TKE2240_01.aspx"


def test_dispatcher_shell_redirect_is_detected():
    """派發器空殼只有 1.4KB，唯一有用的訊息就是那行 frame 導向。"""
    shell = ("<html><body><form><div>"
             "<script>top.mainFrame.location.href='TKE2240_01.aspx';"
             "top.viewFrame.location.href='about:blank';</script>"
             "</div></form></body></html>")
    page = Page(url="https://ais.ntou.edu.tw/Application/TKE/TKE22/TKE2240_.aspx",
                status=200, html=shell)
    assert AisSession.js_redirect_target(page) == "TKE2240_01.aspx"
