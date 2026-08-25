"""
probe.py — 探測一個 WebForms 頁面，把欄位結構整包吐出來。

不需要登入也能跑（登入頁本身就是最重要的一頁）。
目的是省掉「開 DevTools 一個一個抄 input name」的工。

用法：
    python probe.py                        # 探測登入頁
    python probe.py Default.aspx           # 指定路徑
    python probe.py --save fixtures/login.html
"""
from __future__ import annotations

import _console  # noqa: F401  # 必須最先 import

import argparse
import sys

from ais import AisSession, Page


def describe(page: Page) -> None:
    soup = page.soup

    title = soup.find("title")
    print(f"\n=== {page.url}")
    print(f"    status : {page.status}")
    print(f"    title  : {title.get_text(strip=True) if title else '(無)'}")

    meta = soup.find("meta", attrs={"charset": True})
    if meta:
        print(f"    charset: {meta['charset']}")

    forms = soup.find_all("form")
    print(f"\n--- <form> x{len(forms)} ---")
    for i, form in enumerate(forms):
        action = form.get("action", "(同頁)")
        print(f"\n[form {i}] action={action!r} method={form.get('method', 'get')}")

        rows = []
        for el in form.find_all(["input", "select", "textarea"]):
            name = el.get("name") or "(無 name)"
            tag = el.name
            typ = el.get("type", "") if tag == "input" else tag
            el_id = el.get("id", "")
            val = el.get("value", "")

            if name.startswith("__"):
                # 隱藏欄位只報長度，VIEWSTATE 印出來會洗版
                val = f"<{len(val)} bytes>"
            elif typ == "password":
                val = "<password>"
            elif len(val) > 40:
                val = val[:40] + "..."

            if tag == "select":
                opts = el.find_all("option")
                val = f"<{len(opts)} options>"
                if opts:
                    val += "  e.g. " + ", ".join(
                        f"{o.get('value', '')!r}" for o in opts[:3]
                    )

            rows.append((name, typ, el_id, val))

        if not rows:
            print("    (沒有欄位)")
            continue

        w0 = max(len(r[0]) for r in rows)
        w1 = max(len(r[1]) for r in rows)
        w2 = max(len(r[2]) for r in rows)
        for name, typ, el_id, val in rows:
            flag = " <-- ?" if _interesting(name, typ, el_id) else ""
            print(f"    {name:<{w0}}  {typ:<{w1}}  id={el_id:<{w2}}  {val}{flag}")

    targets = AisSession().postback_targets(page)
    if targets:
        print(f"\n--- __doPostBack 目標 x{len(targets)} ---")
        for t, a in targets:
            print(f"    {t!r}, {a!r}")

    imgs = [
        i for i in soup.find_all("img")
        if any(k in " ".join([i.get("src", ""), i.get("id", ""),
                              i.get("alt", ""), i.get("title", "")]).lower()
               for k in ("captcha", "valid", "code", "checkcode", "vcode", "驗證"))
    ]
    if imgs:
        print("\n--- 疑似驗證碼圖片 ---")
        for i in imgs:
            src_ = i.get("src")
            note = "" if src_ else "   <-- HTML 裡沒有 src，可能要先通過排隊/前置頁"
            print(f"    id={i.get('id')!r} src={src_!r}{note}")

    frames = soup.find_all(["iframe", "frame"])
    if frames:
        print("\n--- frame（內容可能在這裡面，要另外抓）---")
        for f in frames:
            print(f"    {f.name} src={f.get('src')!r} name={f.get('name')!r}")


def _interesting(name: str, typ: str, el_id: str) -> bool:
    """粗略標記「這八成是帳號/密碼/驗證碼/登入鈕」的欄位。"""
    if name.startswith("__"):
        return False          # WebForms 的機制欄位，不是你要填的
    blob = f"{name} {el_id}".lower()
    if typ == "password":
        return True
    keys = ("user", "id", "acc", "login", "std", "num", "pwd", "pass",
            "captcha", "valid", "code", "submit", "btn", "logon")
    return any(k in blob for k in keys)


def main() -> int:
    ap = argparse.ArgumentParser(description="探測 WebForms 頁面結構")
    ap.add_argument("path", nargs="?", default="Default.aspx", help="相對路徑")
    ap.add_argument("--base", default="https://ais.ntou.edu.tw/", help="站台 base URL")
    ap.add_argument("--save", metavar="FILE", help="順便把 HTML 存成 fixture")
    args = ap.parse_args()

    sess = AisSession(base_url=args.base, verbose=False)
    try:
        page = sess.get(args.path)
    except Exception as e:
        print(f"抓不到頁面：{type(e).__name__}: {e}", file=sys.stderr)
        print("\n如果是連線/憑證問題，先確認你在校內網路或 VPN。", file=sys.stderr)
        return 1

    describe(page)

    if args.save:
        p = page.save(args.save)
        print(f"\n已存 fixture：{p}")
        print("提醒：登入後的頁面含個資，commit 前先跑 scrub.py")

    print("\n下一步：把上面標 <-- ? 的欄位名填進 selectors.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
