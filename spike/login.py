"""
login.py — 實際登入一次，把每一頁存成 fixture。

密碼用 getpass 讀，只存在記憶體，不寫檔、不進 log、不進 shell history。

**fixture 在寫檔當下就洗個資**（明文密碼、學號、姓名、IP、VIEWSTATE）。
這個系統的登入回應會把密碼明文寫進 HTML（見 README），不能只靠事後手動跑
scrub.py：只要忘記一次，明文密碼就留在硬碟上，而且很可能跟著 commit 出去。

用法：
    python login.py                              # 登入，列出可以去的地方
    python login.py --save --menu                # 遞迴展開選單，找功能路徑
    python login.py --save --fetch MenuTree.aspx # 登入後在 session 內抓指定頁
    python login.py --goto 'ctl00$xxx'           # 跟著某個 __doPostBack 目標走
"""
from __future__ import annotations

import _console  # noqa: F401  # 必須最先 import

import argparse
import getpass
import itertools
import json
import os
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from urllib.parse import urlparse

import probe
from ais import (
    AisSession,
    CallbackError,
    LoginFailed,
    Page,
    SessionExpired,
    load_config,
)
from parsers import (
    MenuNode,
    is_empty_result,
    hidden_field_value,
    parse_callback_response,
    parse_menu,
    treeview_last_index,
)
from scrub import looks_dirty, scrub

HERE = Path(__file__).parent
FIXTURES = HERE / "fixtures"


@dataclass(frozen=True)
class Identity:
    """存 fixture 時要洗掉的身分資訊。姓名程式問不到，要 --name 自己給。"""
    student_id: str | None = None
    name: str | None = None


# 不知道身分時用這個 —— 只洗學號、IP 這類固定樣式，洗不掉姓名。
NOBODY = Identity()


@dataclass(frozen=True)
class FormSubmit:
    """查詢頁要填的欄位 + 要按的按鈕。例如學年 115 學期 1 按「選課課表」。"""

    button: str
    values: dict[str, str] = field(default_factory=dict)

    def slug(self) -> str:
        """給 fixture 檔名用 —— 不同查詢條件不能互相覆蓋。"""
        return "_".join([self.button, *self.values.values()])


def expand_sweep(button: str, fixed: dict[str, str],
                 sweep: dict[str, list[str]]) -> list[FormSubmit]:
    """
    把 --sweep 的多值欄位展開成所有組合。

    每次登入都要人工打驗證碼，所以「一次猜一個學期、猜錯再重登入」很貴。
    一次登入掃完 114-1 / 114-2 / 115-1 / 115-2 只多幾個 request。
    """
    if not sweep:
        return [FormSubmit(button=button, values=dict(fixed))]

    keys = list(sweep)
    out = []
    for combo in itertools.product(*(sweep[k] for k in keys)):
        values = dict(fixed)
        values.update(dict(zip(keys, combo, strict=True)))
        out.append(FormSubmit(button=button, values=values))
    return out


def save_fixture(page: Page, filename: str, who: Identity = NOBODY) -> Path:
    """
    存 fixture，**寫檔當下就洗乾淨**：明文密碼、學號、姓名、身分證、IP、VIEWSTATE。

    刻意不是「先存原始檔、之後記得跑 scrub.py」——那種要靠記性的流程一定會漏，
    而且漏的那次就是明文密碼躺在硬碟上。fixture 的價值在 HTML 結構，
    不在內容真假，所以直接洗掉沒有任何損失。

    scrub.py 留著給「用別的方式取得的檔案」以及 commit 前的 --check 把關。
    """
    cleaned, n = scrub(page.html, who.student_id, who.name)

    p = FIXTURES / filename
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(cleaned, encoding="utf-8")

    leftover = looks_dirty(cleaned)
    warn = f"  ⚠ 仍有 {', '.join(leftover)}" if leftover else ""
    print(f"  存檔 {p.name}（已洗掉 {n} 處個資）{warn}")
    return p


def ask_captcha(sess: AisSession, page: Page, cfg: dict) -> str | None:
    """把驗證碼圖存到暫存檔、用系統看圖程式開起來，讓你自己打。不要 OCR。"""
    data = sess.fetch_captcha(page, cfg)
    if data is None:
        print("頁面上沒有驗證碼 src —— 排隊關卡可能沒走完，或學校改版了。")
        return None

    tmp = Path(tempfile.gettempdir()) / "ntou_captcha.png"
    tmp.write_bytes(data)
    print(f"驗證碼圖片：{tmp}")
    try:
        if sys.platform == "win32":
            os.startfile(tmp)  # noqa: S606
        else:
            # 指令和路徑都是我們自己組的（暫存目錄裡的驗證碼圖），沒有外部輸入。
            # check=False：看圖程式開不起來就算了，路徑已經印出來了。
            subprocess.run(  # noqa: S603
                ["open" if sys.platform == "darwin" else "xdg-open", tmp],
                check=False,
            )
    except Exception:
        pass
    return input("輸入驗證碼：").strip()


def report_navigation(sess: AisSession, page: Page) -> None:
    """把這一頁能去的地方全列出來：postback 目標 + frame。"""
    targets = sess.postback_targets(page)
    if targets:
        print(f"\n可以去的地方 —— __doPostBack（{len(targets)} 個）：")
        for t, a in targets:
            print(f"    --goto {t!r}" + (f"  arg={a!r}" if a else ""))

    frames = [
        f for f in page.soup.find_all(["frame", "iframe"])
        if f.get("src") and f["src"] != "about:blank"
    ]
    if frames:
        print(f"\n可以去的地方 —— frame（{len(frames)} 個）：")
        for f in frames:
            print(f"    --fetch {f['src']!r}   (name={f.get('name')!r})")

    if not targets and not frames:
        print("\n這一頁沒有 postback 目標也沒有 frame。")


MENU_KEYWORDS = ("課表", "成績", "選課", "課程", "學分", "修課", "排課")

# 會改變資料的頁面。--fetch-all 一律跳過 —— 選課期間誤觸一次，
# 後果不是「重跑一次」就能解決的。要看這些頁面請用 --fetch 明確指定。
MUTATING_PATTERNS = (
    "TKE2011",   # 線上加退選
    "ENRD140",   # 申請休退學
    "SDM2010", "SDM2070",          # 申請住宿 / 換床
    "SAC3010", "SAC2010",          # 申請減免 / 就學貸款
    "ENR6030",   # 申請抵免學分
    "SEC6000", "SEC2020", "SEC2030",   # 請假申請 / 取消 / 刪除
    "PWD1020",   # 修改密碼
    "LogOut",    # 登出會把 session 作廢，後面全部白跑
)


def is_mutating(path: str) -> bool:
    return any(p.lower() in path.lower() for p in MUTATING_PATTERNS)


def page_title(page: Page) -> str:
    t = page.soup.find("title")
    return " ".join(t.get_text().split()) if t else "(無標題)"


def fixture_name(url: str) -> str:
    """由最終 URL 產生 fixture 檔名（用導向後的網址，才對得上實際內容）。"""
    path = urlparse(url).path.strip("/")
    safe = re.sub(r"[^\w.-]+", "_", path) or "index"
    safe = safe.removesuffix(".aspx")
    return safe + ".html"


def menu_paths() -> list[str]:
    """從 menu_tree.json 取出所有唯讀的功能頁路徑。"""
    p = FIXTURES / "menu_tree.json"
    if not p.exists():
        print(f"沒有 {p.name} —— 先跑一次 --menu 產生選單結構。", file=sys.stderr)
        return []

    out, skipped = [], []
    for item in json.loads(p.read_text(encoding="utf-8")):
        href = (item.get("href") or "").lstrip("./")
        if ".aspx" not in href.lower():
            continue          # Portal.aspx 之類留著，非 aspx 的（錨點等）跳過
        (skipped if is_mutating(href) else out).append(href)

    # 同一個頁面可能從多條路徑進來（例如英檢抵免），去重但保留順序
    out = list(dict.fromkeys(out))
    print(f"menu_tree.json：{len(out)} 個唯讀頁面，跳過 {len(skipped)} 個會改資料的")
    for s in skipped:
        print(f"    跳過 {s}")
    return out


def fetch_pages(sess: AisSession, paths: list[str], *, save: bool = False,
                quiet: bool = False, who: Identity = NOBODY,
                submits: list[FormSubmit] | None = None) -> list[Page]:
    """
    在已登入的 session 內依序抓多個頁面。

    每個頁面都會跟隨 JS 導向 —— `Application/…/XXXX_.aspx?progcd=…` 只是派發器，
    直接存下來會得到 1.4KB 空殼。檔名用**導向後**的網址，才對得上內容。

    一頁失敗不中斷後面的：每次登入都要手打驗證碼，重跑很貴。
    """
    out: list[Page] = []
    for path, submit in itertools.product(paths, submits or [None]):
        print(f"\n抓取 {path} ...")
        try:
            page = sess.check_session(sess.follow_js_redirect(sess.get(path)))
            if submit:
                shown = ", ".join(f"{k}={v}" for k, v in submit.values.items())
                print(f"  送出 {submit.button}（{shown or '無額外欄位'}）...")
                page = sess.check_session(
                    sess.follow_js_redirect(
                        sess.submit_form(page, submit.button, submit.values)
                    )
                )
        except SessionExpired as e:
            # 這個不能 continue：session 沒了，後面每一頁都會存成登入頁
            print(f"\n  {e}", file=sys.stderr)
            # 把擋住我們的那一頁存下來 —— 沒有它就只能憑症狀猜原因
            if e.page is not None:
                save_fixture(e.page, "session_blocked.html", who)
            print(f"  已抓到 {len(out)} 頁，剩下的中止。", file=sys.stderr)
            break
        except Exception as e:
            print(f"  失敗：{type(e).__name__}: {e}", file=sys.stderr)
            continue

        if is_empty_result(page.html):
            print("  查無符合資料")
        elif quiet:
            print(f"  {len(page.html)}B  {page_title(page)}")
        else:
            probe.describe(page)

        if save:
            name = fixture_name(page.url)
            if submit:
                # 同一頁不同查詢條件會互相覆蓋，把條件寫進檔名
                name = name.removesuffix(".html") + f"__{submit.slug()}.html"
            save_fixture(page, name, who)
        out.append(page)
    return out


def walk_menu(sess: AisSession, save: bool = False, max_depth: int = 3,
              who: Identity = NOBODY,
              menu_path: str = "MenuTree.aspx") -> list[tuple[str, MenuNode]]:
    """
    遞迴展開整棵選單樹，把每個功能的路徑列出來。

    TreeView 是延遲載入的，每展開一個節點就是一次 callback，而且**有狀態**。
    瀏覽器裡 TreeView_ProcessNodeData 在每次回應後會做三件事：

        data.lastIndex     = 回應的第一段        （讀回來，不是自己算）
        expandState.value += 回應的第二段        （累加）
        populateLog.value += str(index) + ","    （累加）

    還有第四件事在傳輸層做（見 ais.callback）：**每次 callback 都會發一組新的
    __EVENTVALIDATION，必須接收並沿用**。少了它，第一層會過、第二層一律被拒。

    所以走訪是循序有狀態的（跟瀏覽器一樣），不能平行化。

    `save=True` 時每次 callback 的參數與原始回應都會寫進 fixtures/callbacks/，
    之後再卡住就先看那些檔案，不要憑推理猜。
    """
    print(f"\n展開選單（{menu_path}，最多 {max_depth} 層）...")
    page = sess.get(menu_path)
    if save:
        save_fixture(page, "MenuTree.aspx.html", who)

    root_nodes = parse_menu(page.html)

    # TreeView 的狀態要像瀏覽器一樣接力維護，三個都不能少：
    #   lastIndex    —— 每次從回應開頭讀回來（不是自己算）
    #   ExpandState  —— 累加回應給的新片段
    #   PopulateLog  —— 每展開一個節點就附加 "index,"
    # 只送初始頁面的值，第一層會過，第二層一定拿到空回應。
    state = {
        "last_index": treeview_last_index(page.html),
        "expand": hidden_field_value(page.html, "Menu_TreeView_ExpandState"),
        "log": hidden_field_value(page.html, "Menu_TreeView_PopulateLog"),
    }
    print(f"  第一層 {sum(1 for n in root_nodes if n.expandable)} 個節點，"
          f"lastIndex={state['last_index']}, ExpandState={state['expand']!r}")

    found: list[tuple[str, MenuNode]] = []

    def expand(node: MenuNode, depth: int, trail: str) -> None:
        indent = "  " * (depth + 1)
        try:
            payload = sess.callback(
                page, "Menu_TreeView", node.callback_param(state["last_index"]),
                extra={
                    "Menu_TreeView_ExpandState": state["expand"],
                    "Menu_TreeView_PopulateLog": state["log"],
                },
                path=menu_path,
            )
        except CallbackError as e:
            print(f"{indent}{node.text} —— 伺服器拒絕：{e}")
            return
        except Exception as e:
            print(f"{indent}{node.text} —— callback 失敗：{type(e).__name__}: {e}")
            return

        if save:
            dump = FIXTURES / "callbacks"
            dump.mkdir(parents=True, exist_ok=True)
            safe = re.sub(r"[^\w]+", "_", f"{depth}_{node.index}_{node.text}")[:60]
            (dump / f"{safe}.txt").write_text(
                f"PARAM: {node.callback_param(state['last_index'])}\n"
                f"EXPAND: {state['expand']}\n"
                f"LOG: {state['log']}\n"
                f"--- RESPONSE ({len(payload)} chars) ---\n{payload}",
                encoding="utf-8",
            )

        result = parse_callback_response(payload)
        if result is None:
            # 印出原始內容 —— 空殼回應長什麼樣是唯一能判斷原因的線索
            print(f"{indent}{node.text}（回應無法解析，{len(payload)}B）")
            print(f"{indent}  原始回應: {payload!r}")
            print(f"{indent}  送出參數: {node.callback_param(state['last_index'])!r}")
            return

        # 先更新狀態，再往下走 —— 順序錯了下一層就拿不到東西
        state["last_index"] = result.last_index
        state["expand"] += result.new_expand_state
        state["log"] += f"{node.index},"

        children = parse_menu(result.html)
        if not children:
            print(f"{indent}{node.text}（沒有子項）")
            return

        print(f"{indent}{node.text}／")
        for c in children:
            path_trail = f"{trail} > {c.text}"
            if c.href:
                mark = "  ***" if any(k in c.text for k in MENU_KEYWORDS) else ""
                print(f"{indent}  {c.text:26} -> {c.href}{mark}")
                found.append((path_trail, c))
            elif depth + 1 < max_depth:
                expand(c, depth + 1, path_trail)
            else:
                print(f"{indent}  {c.text:26} (還有下一層，index={c.index})")

    for node in root_nodes:
        if node.expandable:
            expand(node, 0, node.text)

    leaves = [n for n in root_nodes if n.href]
    if leaves:
        print("\n  第一層的直接連結：")
        for n in leaves:
            print(f"        {n.text:26} -> {n.href}")
            found.append((n.text, n))

    hits = [(t, n) for t, n in found if any(k in t for k in MENU_KEYWORDS)]
    if hits:
        print(f"\n  *** 跟課表 / 成績有關的（{len(hits)} 個）：")
        for trail, n in hits:
            print(f"        {trail}")
            print(f"          --fetch {n.href!r}")

    if save:
        out = FIXTURES / "menu_tree.json"
        out.write_text(json.dumps(
            [{"trail": t, "text": n.text, "href": n.href} for t, n in found],
            ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"\n  選單結構已存 {out.name}（{len(found)} 個功能，無個資）")

    return found


def build_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(description="登入 AIS 並抓 fixture")
    ap.add_argument("--config", default=str(HERE / "selectors.json"))
    ap.add_argument("--save", action="store_true", help="把頁面存進 fixtures/")
    ap.add_argument("--goto", metavar="TARGET", help="登入後跟著這個 __doPostBack 目標走")
    ap.add_argument("--fetch", metavar="PATH", action="append", default=[],
                    help="登入後在同一個 session 內 GET 這個路徑（可重複）")
    ap.add_argument("--menu", action="store_true",
                    help="遞迴展開 MenuTree.aspx，列出每個功能的路徑")
    ap.add_argument("--menu-depth", type=int, default=3, metavar="N",
                    help="選單展開深度上限（預設 3）")
    ap.add_argument("--fetch-all", action="store_true",
                    help="抓 menu_tree.json 裡所有唯讀功能頁（會改資料的自動跳過）")
    ap.add_argument("--submit", metavar="BUTTON",
                    help="抓到頁面後按這顆按鈕送出（例如 QUERY_BTN3）")
    ap.add_argument("--set", metavar="K=V", action="append", default=[],
                    help="送出前設定欄位值，可重複（例如 --set Q_AYEAR=115）")
    ap.add_argument("--sweep", metavar="K=V1,V2", action="append", default=[],
                    help="同一次登入內掃過多個值，可重複"
                         "（例如 --sweep Q_AYEAR=113,114,115 --sweep Q_SMS=1,2）")
    ap.add_argument("--quiet", action="store_true",
                    help="--fetch-all 時只印標題和大小，不印完整欄位表")
    ap.add_argument("--user", help="學號（不給就互動輸入）")
    ap.add_argument("--name", help="你的姓名 —— 存 fixture 時一併洗掉")
    ap.add_argument("--no-frames", action="store_true",
                    help="登入後不載入 frame（用來驗證 frame 是不是必要的）")
    ap.add_argument("--no-logout", action="store_true",
                    help="跑完不登出（這個系統一次只允許一個 session，通常不要用）")
    return ap


def run_session(sess: AisSession, page: Page, args, who: Identity) -> int:
    """登入之後要做的事。抽出來是為了讓 main() 能用 try/finally 保證登出。"""
    if args.save:
        # 登入 POST 的原始回應（含 JS 導向指令）—— 測試用它鎖住「怎麼判斷成功」
        if sess.login_response is not None:
            save_fixture(sess.login_response, "login_post.html", who)
        save_fixture(page, "mainframe.html", who)

    report_navigation(sess, page)

    # 像瀏覽器一樣把 frame 載一遍再開始抓 —— 見 ais.enter_portal()
    if not args.no_frames:
        print("\n載入 frame（模擬瀏覽器完成登入握手）...")
        sess.enter_portal(page)

    if args.menu:
        walk_menu(sess, save=args.save, max_depth=args.menu_depth, who=who)

    targets = list(args.fetch)
    if args.fetch_all:
        targets = menu_paths() + targets
    submits = None
    if args.submit:
        sweep = {}
        for kv in args.sweep:
            key, _, csv = kv.partition("=")
            sweep[key] = [v.strip() for v in csv.split(",") if v.strip()]
        submits = expand_sweep(
            args.submit,
            dict(kv.split("=", 1) for kv in args.set),
            sweep,
        )
        if len(submits) > 1:
            print(f"\n將掃過 {len(submits)} 組查詢條件（同一次登入）")
    fetch_pages(sess, targets, save=args.save, quiet=args.quiet, who=who,
                submits=submits)

    if args.goto:
        print(f"\n前往 {args.goto} ...")
        page = sess.postback(page, args.goto)
        if args.save:
            safe = args.goto.replace("$", "_").replace(":", "_") + ".html"
            save_fixture(page, safe, who)
        report_navigation(sess, page)

    if args.save:
        print("\nfixture 已在寫檔時洗過個資。commit 前跑：")
        print(r"    .venv\Scripts\python.exe check.py")
    return 0


def main() -> int:
    args = build_parser().parse_args()

    cfg = load_config(args.config)
    login_cfg = cfg["login"]

    if str(login_cfg["username_field"]).startswith("TODO"):
        print("selectors.json 還沒填。先跑：", file=sys.stderr)
        print("    python probe.py --save fixtures/login.html", file=sys.stderr)
        return 2

    username = args.user or input("學號：").strip()
    who = Identity(student_id=username, name=args.name)
    password = getpass.getpass("密碼（不會顯示、不會存檔）：")

    sess = AisSession(
        base_url=cfg.get("base_url", "https://ais.ntou.edu.tw/"),
        min_interval=cfg.get("min_interval_seconds", 1.0),
    )

    print("\n取得登入頁（含通過排隊關卡）...")
    page = sess.open_login_page(login_cfg)

    captcha = None
    if login_cfg.get("captcha_field"):
        captcha = ask_captcha(sess, page, login_cfg)

    print("登入中...")
    try:
        # 一定要把同一個 page 傳進去：驗證碼和 __VIEWSTATE 綁在這次的 session 狀態上，
        # 重抓頁面驗證碼就換了，你剛打的那組會失效。
        page = sess.login(login_cfg, username, password, captcha, page=page)
    except LoginFailed as e:
        print(f"\n{e}", file=sys.stderr)
        if e.page is not None:
            p = save_fixture(e.page, "login_failed.html", who)
            print(f"回應已存到 {p}，打開看看是什麼情況", file=sys.stderr)
        return 1
    finally:
        password = "x" * len(password)  # 盡快讓它離開記憶體

    print("\n登入成功。")

    try:
        return run_session(sess, page, args, who)
    finally:
        # 這個系統一次只允許一個 session。不登出的話舊 session 留在伺服器上，
        # 下次登入會被 ConfirmInOrOut.aspx 擋掉，而且症狀完全不像「忘了登出」。
        if not args.no_logout:
            print("\n登出中...")
            sess.logout()


if __name__ == "__main__":
    raise SystemExit(main())
