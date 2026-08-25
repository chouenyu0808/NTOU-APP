"""
test_check.py — commit 把關掃描的行為。

這個掃描會擋住整個 repo 的 commit（包含 app/ 的 Flutter 程式），
所以**誤報的代價很高**：擋到別人、又找不出原因，最後大家會乾脆關掉檢查。

實際踩過的兩個誤報都在這裡：
  - jdk-17.0.20.1+1 的版本號被當成 IP
  - 別人測試檔裡的假密碼 hunter2 被當成外洩
"""
from __future__ import annotations

import pytest

from check import DUMMY_SECRETS, SCRUB_OK, TRACKED_PATTERNS

IP = TRACKED_PATTERNS["對外 IP"]
PW = TRACKED_PATTERNS["明文密碼"]
TWID = TRACKED_PATTERNS["身分證字號"]


# ---------- IP：版本號不能誤判 ----------

@pytest.mark.parametrize("text", [
    r"C:\dev\toolchain\jdk\jdk-17.0.20.1+1",   # JDK 版本
    "platform-tools 37.0.1",
    "NDK 28.2.13676358",
    "CMake 3.22.1",
    "Flutter SDK 3.47.1",
])
def test_version_strings_are_not_ips(text):
    assert not IP.search(text), f"版本號被誤判成 IP：{text}"


@pytest.mark.parametrize("text, expected", [
    ("Client:123.192.160.13", "123.192.160.13"),  # scrub-ok
    ("連到 140.121.91.111 了", "140.121.91.111"),  # scrub-ok
    ('"remote": "203.74.205.18"', "203.74.205.18"),  # scrub-ok
])
def test_real_ips_are_still_caught(text, expected):
    m = IP.search(text)
    assert m and m.group(0) == expected


@pytest.mark.parametrize("text", [
    # 這些是測試資料不是綁定位址 —— 0.0.0.0 在這裡只是「要被忽略的網段」
    "Client:10.0.0.1", "127.0.0.1", "192.168.1.1", "0.0.0.0",  # noqa: S104
])
def test_private_ranges_are_ignored(text):
    assert not IP.search(text)


# ---------- 密碼：假的要放行、真的要擋 ----------

@pytest.mark.parametrize("dummy", ["hunter2", "REDACTED", "P@ssw0rd123", "changeme"])
def test_dummy_passwords_are_exempt(dummy):
    m = PW.search(f"LoginPWD:'{dummy}'")  # scrub-ok
    assert m and m.group(1) in DUMMY_SECRETS


def test_real_looking_password_is_flagged():
    m = PW.search("var keyObj = {LoginPWD:'Xk9#mQ2vLp'};")  # scrub-ok
    assert m and m.group(1) not in DUMMY_SECRETS


def test_password_pattern_captures_only_the_value():
    """
    要比對捕獲群組而不是整段：整段會連欄位名一起帶進來，  scrub-ok
    拿它去跟假密碼清單比對永遠不會相等。
    """
    m = PW.search("LoginPWD:'hunter2'")  # scrub-ok
    assert m.group(1) == "hunter2"
    assert m.group(0) != "hunter2"


# ---------- 行內豁免 ----------

def test_scrub_ok_marker_is_a_plain_substring():
    """標記就是一段純文字，任何語言的註解都能用（Python / Dart / Markdown）。"""
    assert SCRUB_OK == "scrub-ok"
    for comment in ["# 說明 scrub-ok", "// 說明 scrub-ok", "<!-- scrub-ok -->"]:
        assert SCRUB_OK in comment


# ---------- 身分證 ----------

def test_twid_pattern():
    assert TWID.search("身分證 A123456789")
    assert not TWID.search("課號 B57011RQ")
    assert not TWID.search("學號 B10900000")


# ---------- 樣板佔位符 ----------

@pytest.mark.parametrize("value", [
    "$fakePassword",      # Dart 字串插值（app/test 裡真的有）
    "${pw}",              # Dart / JS
    "{password}",         # Python format
    "%s",                 # printf
    "<password>",         # 尖括號佔位
])
def test_interpolations_are_not_secrets(value):
    """佔位符不是值本身，是「這裡之後會填東西」。"""
    from check import INTERPOLATION_RE
    assert INTERPOLATION_RE.match(value)


def test_real_password_is_not_treated_as_interpolation():
    from check import INTERPOLATION_RE
    assert not INTERPOLATION_RE.match("Xk9#mQ2vLp")  # scrub-ok
