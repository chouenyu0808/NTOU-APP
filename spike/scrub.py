"""
scrub.py — 把 fixture 裡的個資洗掉，才能安心 commit / 給別人看。

fixture 是你自己帳號抓的真實頁面，裡面有學號、姓名、成績。
測試只在乎「HTML 結構」，不在乎內容真假，所以洗掉不影響測試價值。

用法：
    python scrub.py fixtures/*.html
    python scrub.py fixtures/timetable.html --id B10932001 --name 王小明
    python scrub.py fixtures/*.html --check      # 只檢查不改（給 pre-commit 用）
"""
from __future__ import annotations

import _console  # noqa: F401  # 必須最先 import

import argparse
import re
import sys
from pathlib import Path

# 學號：一個英文字母 + 8~9 碼數字，或純 8~9 碼數字
STUDENT_ID_RE = re.compile(r"\b([A-Za-z]\d{8,9}|\d{8,9})\b")
# 隱藏欄位的 base64 值：又臭又長又可能含 session 資訊
VIEWSTATE_RE = re.compile(
    r'(name="(?:__VIEWSTATE|__EVENTVALIDATION|__PREVIOUSPAGE)"[^>]*?value=")([^"]*)(")'
)
# 身分證、生日、電話、email
TWID_RE = re.compile(r"\b[A-Z][12]\d{8}\b")
PHONE_RE = re.compile(r"\b09\d{2}-?\d{3}-?\d{3}\b")
EMAIL_RE = re.compile(r"\b[\w.+-]+@[\w-]+\.[\w.-]+\b")
# 排隊頁頁尾會印出你的對外 IP：「Server:87 Client:x.x.x.x」
IP_RE = re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b")

# AIS 登入成功的回應會把密碼「明文回吐」兩次：
#   <script>var keyObj = {LoginPWD:'明文'};</script>
#   _i(0,'LoginPWD').value = '明文';
# 這是學校系統的行為，不是我們造成的，但代表任何存下來的回應都含明文密碼。
PW_REFLECT_PATTERNS = (
    re.compile(r"""(keyObj\s*=\s*\{\s*LoginPWD\s*:\s*)['"][^'"]*['"]"""),
    re.compile(r"""(_i\(\s*\d+\s*,\s*['"]LoginPWD['"]\s*\)\.value\s*=\s*)['"][^'"]*['"]"""),
    re.compile(r"""(['"]?LoginPWD['"]?\s*[:=]\s*)['"][^'"]{3,}['"]"""),
)

PLACEHOLDER_ID = "B10900000"


def scrub(html: str, student_id: str | None = None, name: str | None = None) -> tuple[str, int]:
    n = 0

    def count(pattern, repl, text):
        nonlocal n
        text, k = pattern.subn(repl, text)
        n += k
        return text

    if student_id:
        n += html.count(student_id)
        html = html.replace(student_id, PLACEHOLDER_ID)
    if name:
        n += html.count(name)
        html = html.replace(name, "王小明")

    html = count(VIEWSTATE_RE, lambda m: m.group(1) + "SCRUBBED" + m.group(3), html)
    html = count(STUDENT_ID_RE, PLACEHOLDER_ID, html)
    html = count(TWID_RE, "A123456789", html)
    html = count(PHONE_RE, "0912-345-678", html)
    html = count(EMAIL_RE, "student@mail.ntou.edu.tw", html)
    html = count(IP_RE, "10.0.0.1", html)
    for pat in PW_REFLECT_PATTERNS:
        html = count(pat, lambda m: m.group(1) + "'REDACTED'", html)
    return html, n


def looks_dirty(html: str) -> list[str]:
    """
    --check 用：回報還殘留哪些疑似個資。

    要排掉我們自己填的佔位符，否則洗過的檔案會被自己的檢查判成髒的
    （佔位符本身當然也符合「像個 IP / email」的樣子）。
    """
    hits = []
    for label, pattern, placeholder in (
        ("身分證字號", TWID_RE, "A123456789"),
        ("手機", PHONE_RE, "0912-345-678"),
        ("email", EMAIL_RE, "student@mail.ntou.edu.tw"),
        ("IP 位址", IP_RE, "10.0.0.1"),
    ):
        if any(m.group(0) != placeholder for m in pattern.finditer(html)):
            hits.append(label)
    for pat in PW_REFLECT_PATTERNS:
        for m in pat.finditer(html):
            if "REDACTED" not in m.group(0):
                hits.append("回吐的明文密碼")
                break

    for m in VIEWSTATE_RE.finditer(html):
        if m.group(2) != "SCRUBBED" and len(m.group(2)) > 32:
            hits.append("未清除的 __VIEWSTATE")
            break

    # 同一件事可能被多個 pattern 命中（密碼回吐有三個 pattern），
    # 報告裡不要出現三次「回吐的明文密碼」。
    return list(dict.fromkeys(hits))


def main() -> int:
    ap = argparse.ArgumentParser(description="清掉 fixture 裡的個資")
    ap.add_argument("files", nargs="+", type=Path)
    ap.add_argument("--id", dest="student_id", help="你的學號（精準取代）")
    ap.add_argument("--name", help="你的姓名（精準取代）")
    ap.add_argument("--check", action="store_true", help="只檢查，發現個資就 exit 1")
    args = ap.parse_args()

    dirty = False
    for f in args.files:
        if not f.exists():
            print(f"跳過（不存在）：{f}", file=sys.stderr)
            continue
        html = f.read_text(encoding="utf-8")

        if args.check:
            hits = looks_dirty(html)
            if hits:
                dirty = True
                print(f"{f}: 還有 {', '.join(hits)}")
            continue

        cleaned, n = scrub(html, args.student_id, args.name)
        f.write_text(cleaned, encoding="utf-8")
        print(f"{f}: 取代 {n} 處")

    if args.check:
        if dirty:
            print("\n先跑 python scrub.py fixtures/*.html 再 commit", file=sys.stderr)
            return 1
        print("fixture 乾淨")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
